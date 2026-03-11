#!/bin/bash

# Usage: ./deploy_region.sh <region_name>
# Example: ./deploy_region.sh singapore

REGION=$1
JSON_FILE="pialist.json"
MANAGEMENT_FILE="managed_ips.txt"
MAX_ATTEMPTS=25

# Get current directory for volume mounting
CURRENT_DIR=$(pwd)

# 1. Validate Input
if [ -z "$REGION" ]; then
    echo "Error: Please provide a region name (e.g., singapore)."
    exit 1
fi

if [ ! -f "$JSON_FILE" ]; then
    echo "Error: $JSON_FILE not found."
    exit 1
fi

# 2. Extract count and calculate
RAW_COUNT=$(jq -r --arg REG "$REGION" '.[$REG].count // 0' "$JSON_FILE")

if [ "$RAW_COUNT" -eq 0 ] || [ "$RAW_COUNT" == "null" ]; then
    echo "No IPs found for region: $REGION"
    exit 1
fi

IP_COUNT=$(( (RAW_COUNT * 70 + 50) / 100 ))
[ "$IP_COUNT" -le 0 ] && [ "$RAW_COUNT" -gt 0 ] && IP_COUNT=1

echo "Region: $REGION | Original: $RAW_COUNT | Deploying: $IP_COUNT"

USED_IPS=()

for (( i=1; i<=$IP_COUNT; i++ )); do
    VPN_NAME="vpn_${REGION}_${i}"
    TRAFF_NAME="traff_${REGION}_${i}"
    
    echo "--- Deploying Instance $i of $IP_COUNT: $VPN_NAME ---"

    # 3. Start the OpenVPN container (Alpine based)
    # Replaced WireGuard with OpenVPN command, mapping current path and region
    docker run -d \
        --name "$VPN_NAME" \
        --privileged \
        --sysctl net.ipv6.conf.all.disable_ipv6=0 \
        --dns 8.8.8.8 --dns 8.8.4.4 \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        --health-cmd="ping -c 1 www.ifconfig.me || exit 1" \
        --health-interval=90s \
        --health-timeout=20s \
        --health-retries=3 \
        -v "$CURRENT_DIR":/vpn \
        alpine sh -c "apk add --no-cache openvpn curl && openvpn --config /vpn/${REGION}.ovpn --auth-user-pass /vpn/vpn.txt --pull-filter ignore 'route-ipv6'"

    # 4. Check for a Unique IP
    UNIQUE=false
    CURRENT_IP=""
    ATTEMPT=0 
    
    while [ "$UNIQUE" = false ]; do
        ((ATTEMPT++))
        
        if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
            echo "--------------------------------------------------------"
            echo "CRITICAL: Max attempts reached for $VPN_NAME. Cleaning up..."
            docker rm -f "$VPN_NAME" > /dev/null 2>&1
            exit 1
        fi

        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for VPN handshake..."
        
        # Alpine needs a bit of time to install apk packages and then connect
        sleep 15

        # Retrieve IP
        CURRENT_IP=$(docker exec "$VPN_NAME" curl -s --max-time 10 https://ifconfig.me)
        
        if [ -z "$CURRENT_IP" ]; then
            echo "Handshake failed or no route. Cooling down (5s) before restart..."
            sleep 5
            docker restart "$VPN_NAME"
            continue
        fi

        # Check if IP is in the managed file OR already used
        if grep -q "$CURRENT_IP" "$MANAGEMENT_FILE" 2>/dev/null || [[ " ${USED_IPS[@]} " =~ " ${CURRENT_IP} " ]]; then
            echo "Duplicate IP detected ($CURRENT_IP). Requesting new IP..."
            sleep 3
            docker restart "$VPN_NAME"
        else
            echo "Success! Unique IP obtained: $CURRENT_IP"
            USED_IPS+=("$CURRENT_IP")
            UNIQUE=true
        fi
    done

    # 5. Run Traffmonetizer container
    docker run -d \
        --name "$TRAFF_NAME" \
        --network "container:$VPN_NAME" \
        --restart always \
        --cpus "0.03" \
        --memory "32m" \
        --memory-reservation "16m" \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        traffmonetizer/cli_v2 \
        start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM=" --device-name "a$CURRENT_IP"

    # 6. Write to the management file
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$TIMESTAMP | Region: $REGION | IP: $CURRENT_IP | VPN: $VPN_NAME | Traff: $TRAFF_NAME" >> "$MANAGEMENT_FILE"

    echo "Instance $i saved to $MANAGEMENT_FILE"
    echo "--------------------------------------------------------"
done

echo "Deployment for $REGION complete. Total instances deployed: $IP_COUNT."
