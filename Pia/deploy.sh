#!/bin/bash

# Usage: ./deploy_region.sh <region_name>
# Example: ./deploy_region.sh us_florida

REGION=$1
JSON_FILE="pialist.json"
MANAGEMENT_FILE="managed_ips.txt"
MAX_ATTEMPTS=10 

# 1. Validate Input
if [ -z "$REGION" ]; then
    echo "Error: Please provide a region name (e.g., us_florida)."
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

    # Start the VPN container
    docker run -d \
        --name "$VPN_NAME" \
        --cap-add=NET_ADMIN \
        --device=/dev/net/tun:/dev/net/tun \
        --sysctl net.ipv4.conf.all.src_valid_mark=1 \
        --sysctl net.ipv6.conf.default.disable_ipv6=1 \
        --sysctl net.ipv6.conf.all.disable_ipv6=1 \
        --sysctl net.ipv6.conf.lo.disable_ipv6=1 \
        -v pia:/pia \
        -e LOC="$REGION" \
        -e USER="p3526321" \
        -e PASS="Loc123456789" \
        -e VPNDNS="8.8.8.8,8.8.4.4" \
        thrnz/docker-wireguard-pia

    # 4. Check for a Unique IP
    UNIQUE=false
    CURRENT_IP=""
    ATTEMPT=0 
    
    while [ "$UNIQUE" = false ]; do
        ((ATTEMPT++))
        
        if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
            echo "--------------------------------------------------------"
            echo "CRITICAL: Reached $MAX_ATTEMPTS failed attempts for $VPN_NAME."
            echo "Cleaning up failing container..."
            
            # Stop and Remove the container that couldn't get a unique IP
            docker stop "$VPN_NAME" > /dev/null 2>&1
            docker rm "$VPN_NAME" > /dev/null 2>&1
            
            echo "Container $VPN_NAME removed. Exiting script."
            echo "--------------------------------------------------------"
            exit 1
        fi

        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for connection (10s)..."
        sleep 10
        
        CURRENT_IP=$(docker exec "$VPN_NAME" curl -s https://ifconfig.me)
        
        if [ -z "$CURRENT_IP" ]; then
            echo "Could not retrieve IP. Restarting VPN..."
            docker restart "$VPN_NAME"
            continue
        fi

        # Check persistence file
        if [ -f "$MANAGEMENT_FILE" ] && grep -q "$CURRENT_IP" "$MANAGEMENT_FILE"; then
             echo "IP $CURRENT_IP exists in $MANAGEMENT_FILE. Restarting..."
             docker restart "$VPN_NAME"
             continue
        fi

        # Check session duplicates
        IS_DUPLICATE=false
        for ip in "${USED_IPS[@]}"; do
            if [ "$ip" == "$CURRENT_IP" ]; then
                IS_DUPLICATE=true
                break
            fi
        done

        if [ "$IS_DUPLICATE" = true ]; then
            echo "Duplicate IP in session ($CURRENT_IP). Restarting..."
            docker restart "$VPN_NAME"
        else
            echo "Unique IP obtained: $CURRENT_IP"
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
        traffmonetizer/cli_v2:arm64v8 \
        start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM=" --device-name "$CURRENT_IP"

    # 6. Write to the management file
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$TIMESTAMP | Region: $REGION | IP: $CURRENT_IP | VPN: $VPN_NAME | Traff: $TRAFF_NAME" >> "$MANAGEMENT_FILE"

    echo "Instance $i saved to $MANAGEMENT_FILE"
    echo "--------------------------------------------------------"
done

echo "Deployment for $REGION complete. Total instances deployed: $IP_COUNT."
