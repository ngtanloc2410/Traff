#!/bin/bash

# Usage: ./deploy_region.sh <region_name>
# Example: ./deploy_region.sh us_florida

REGION=$1
VPN_DIR=$(pwd)
MANAGEMENT_FILE="ips.txt"
MAX_ATTEMPTS=20

# 1. Validate Input
if [ -z "$REGION" ]; then
    echo "Error: Please provide a region name (e.g., us_florida)."
    exit 1
fi

# Check if the external network exists; if not, create it
if ! docker network inspect my_shared_proxy_network >/dev/null 2>&1; then
    echo "Creating network 'my_shared_proxy_network'..."
    docker network create --subnet=172.20.0.0/16 my_shared_proxy_network
fi

OVPN_FILE=$REGION

IP_COUNT=130

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
        --device /dev/net/tun \
        --network="my_shared_proxy_network" \
        --cpus "0.03" \
        --memory "32m" \
        --memory-reservation "16m" \
        --dns "8.8.8.8" \
        --dns "4.4.4.4" \
        --tmpfs /tmp:rw,noexec,nosuid,size=16m \
        -v "$VPN_DIR":/vpn \
        -e OVPN_FILE="$OVPN_FILE" \
        --log-driver json-file \
        --log-opt max-size="5m" \
        --log-opt max-file="3" \
        ghcr.io/ngtanloc2410/wind:latest

    # 4. Check for a Unique IP (Optimized Logic)
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

        # Wait for the container to be "healthy" (as defined by your --health-cmd)
        # This prevents running curl before the WireGuard tunnel is actually up.
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for VPN handshake..."
        
        # Increased wait: VPNs rarely handshake and route in under 10-12s
        sleep 15

        # Retrieve IP with a timeout to prevent the script from hanging
        CURRENT_IP=$(docker exec "$VPN_NAME" curl -s --interface tun0 --max-time 15 https://ifconfig.me)
        
        if [ -z "$CURRENT_IP" ]; then
            echo "Handshake failed or no route. Cooling down (5s) before restart..."
            sleep 3
            docker restart "$VPN_NAME"
            continue
        fi

        # Check if IP is in the managed file OR already used in this session
        if grep -q "$CURRENT_IP" "$MANAGEMENT_FILE" 2>/dev/null || [[ " ${USED_IPS[@]} " =~ " ${CURRENT_IP} " ]]; then
            echo "Duplicate IP detected ($CURRENT_IP). Requesting new IP..."
            
            # Instead of immediate restart, we wait a moment so the VPN server 
            # might assign a different node/IP on the next attempt.
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
            --cpus "0.03" \
            --memory "32m" \
            --memory-reservation "16m" \
            --health-cmd="curl -f ipinfo.io || exit 1" \
            --health-interval=70s \
            --health-timeout=20s \
            --health-retries=3 \
            --log-driver json-file \
            --log-opt max-size=5m \
            --log-opt max-file=3 \
            ghcr.io/ngtanloc2410/traffmonetizer:latest \
            start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM=" --device-name "windscribe"

    # 6. Write to the management file
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$TIMESTAMP | Region: $REGION | IP: $CURRENT_IP | VPN: $VPN_NAME | Traff: $TRAFF_NAME" >> "$MANAGEMENT_FILE"

    echo "Instance $i saved to $MANAGEMENT_FILE"
    echo "--------------------------------------------------------"
done

echo "Deployment for $REGION complete. Total instances deployed: $IP_COUNT."
