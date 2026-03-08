#!/bin/bash

# Usage: ./deploy_region.sh <region_name>
# Example: ./deploy_region.sh us_florida

REGION=$1
JSON_FILE="pialist.json"
MANAGEMENT_FILE="managed_ips.txt"

# 1. Validate Input
if [ -z "$REGION" ]; then
    echo "Error: Please provide a region name (e.g., us_florida)."
    exit 1
fi

if [ ! -f "$JSON_FILE" ]; then
    echo "Error: $JSON_FILE not found in the current directory."
    exit 1
fi

# 2. Extract count and calculate 90% with rounding
RAW_COUNT=$(jq -r --arg REG "$REGION" '.[$REG].count // 0' "$JSON_FILE")

if [ "$RAW_COUNT" -eq 0 ] || [ "$RAW_COUNT" == "null" ]; then
    echo "No IPs found for region: $REGION"
    exit 1
fi

# Math: (Value + 50) / 100 rounds .5 and up to the next integer
IP_COUNT=$(( (RAW_COUNT * 70 + 50) / 100 ))

# Safety: Always deploy at least 1 if the region exists
if [ "$IP_COUNT" -le 0 ] && [ "$RAW_COUNT" -gt 0 ]; then
    IP_COUNT=1
fi

echo "Region: $REGION | Original: $RAW_COUNT | Deploying: $IP_COUNT (Adjusted 10%)"

# Array to keep track of IPs used in THIS specific script run
USED_IPS=()

for (( i=1; i<=$IP_COUNT; i++ )); do
    VPN_NAME="vpn_${REGION}_${i}"
    TRAFF_NAME="traff_${REGION}_${i}"
    
    echo "--- Deploying Instance $i of $IP_COUNT: $VPN_NAME ---"

    # 3. Run the VPN container (Wireguard PIA) based on services.yml
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
        -e USER="p6750469" \
        -e PASS="YeeV2qLNtV" \
        -e VPNDNS="8.8.8.8,8.8.4.4" \
        thrnz/docker-wireguard-pia

    # 4. Check for a Unique IP
    UNIQUE=false
    CURRENT_IP=""
    
    while [ "$UNIQUE" = false ]; do
        echo "Waiting for $VPN_NAME to establish connection (15 seconds)..."
        sleep 15 
        
        # Get public IP via the container
        CURRENT_IP=$(docker exec "$VPN_NAME" curl -s https://ifconfig.me)
        
        if [ -z "$CURRENT_IP" ]; then
            echo "Could not retrieve IP. Restarting VPN..."
            docker restart "$VPN_NAME"
            continue
        fi

        # Check if IP is already in our management file (persistent check across all runs)
        if [ -f "$MANAGEMENT_FILE" ] && grep -q "$CURRENT_IP" "$MANAGEMENT_FILE"; then
             echo "IP $CURRENT_IP already exists in $MANAGEMENT_FILE. Restarting for a new IP..."
             docker restart "$VPN_NAME"
             continue
        fi

        # Check if IP was already used in this specific loop (session check)
        IS_DUPLICATE=false
        for ip in "${USED_IPS[@]}"; do
            if [ "$ip" == "$CURRENT_IP" ]; then
                IS_DUPLICATE=true
                break
            fi
        done

        if [ "$IS_DUPLICATE" = true ]; then
            echo "Duplicate IP found in this session ($CURRENT_IP). Restarting VPN..."
            docker restart "$VPN_NAME"
        else
            echo "Unique IP obtained: $CURRENT_IP"
            USED_IPS+=("$CURRENT_IP")
            UNIQUE=true
        fi
    done

    # 5. Run Traffmonetizer container attached to the VPN network
    # Passing the $CURRENT_IP as the device name
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
        start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM=" --device-name "$CURRENT_IP"

    # 6. Write to the management file
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$TIMESTAMP | Region: $REGION | IP: $CURRENT_IP | VPN: $VPN_NAME | Traff: $TRAFF_NAME" >> "$MANAGEMENT_FILE"

    echo "Instance $i saved to $MANAGEMENT_FILE"
    echo "--------------------------------------------------------"
done

echo "Deployment for $REGION complete. Total instances deployed: $IP_COUNT."
