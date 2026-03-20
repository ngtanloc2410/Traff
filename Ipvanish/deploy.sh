#!/bin/bash

# Usage: ./deploy_auto.sh <ovpn_prefix>
PREFIX=$1
VPN_DIR=$(pwd)
MANAGEMENT_FILE="ips.txt"
MAX_ATTEMPTS=5
MAX_GLOBAL_FAILS=5
GLOBAL_FAIL_COUNT=0

docker pull ghcr.io/ngtanloc2410/tocdocualoc:latest
docker pull ghcr.io/ngtanloc2410/traffmonetizer:latest

# 1. Validate Input
if [ -z "$PREFIX" ]; then
    echo "Error: Please provide the ovpn prefix."
    echo "Usage: ./deploy_auto.sh <OVPN_PREFIX>"
    echo "Example: ./deploy_auto.sh ipvanish-US-Las-Vegas"
    exit 1
fi

if ! docker network inspect my_shared_proxy_network >/dev/null 2>&1; then
    echo "Creating network 'my_shared_proxy_network'..."
    docker network create --subnet=172.20.0.0/16 my_shared_proxy_network
fi

# 2. Find matching ovpn files by prefix
LOC_NAME=$(echo "$PREFIX" | sed 's/ //g')
MATCHING_FILES=($(find "$VPN_DIR" -maxdepth 1 -type f -name "${PREFIX}*.ovpn" | sort))
NUM_SERVERS=${#MATCHING_FILES[@]}

if [ "$NUM_SERVERS" -eq 0 ]; then
    echo "Error: No .ovpn files found matching prefix: ${PREFIX}"
    exit 1
fi

# Count by number of matching files
TOTAL_SERVERS_TO_DEPLOY=$(( (NUM_SERVERS * 2) + 30 ))

echo "Prefix: $PREFIX | Found $NUM_SERVERS matching .ovpn files."
echo "Target: Deploying $TOTAL_SERVERS_TO_DEPLOY instances."

# 3. Loop through matching ovpn files
for (( i=0; i<$TOTAL_SERVERS_TO_DEPLOY; i++ )); do
    SERVER_INDEX=$(( i % NUM_SERVERS ))
    OVPN_FILE="${MATCHING_FILES[$SERVER_INDEX]}"
    INSTANCE_NUM=$((i + 1))
    SERVER_ADDR=$(basename "$OVPN_FILE")

    VPN_NAME="vpn_${LOC_NAME}_${INSTANCE_NUM}"
    TRAFF_NAME="traff_${LOC_NAME}_${INSTANCE_NUM}"

    echo "--- Instance $INSTANCE_NUM/$TOTAL_SERVERS_TO_DEPLOY: Using file $SERVER_ADDR ---"

    # 4. Run VPN container
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
        -e OVPN_FILE="$(basename "$OVPN_FILE")" \
        --log-driver json-file \
        --log-opt max-size="5m" \
        --log-opt max-file="3" \
        ghcr.io/ngtanloc2410/ipvanish:latest

    # 5. UNIQUE IP CHECK
    UNIQUE=false
    CURRENT_IP=""
    ATTEMPT=0

    while [ "$UNIQUE" = false ] && [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
        ((ATTEMPT++))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for IP..."
        sleep 15

        CURRENT_IP=$(docker exec "$VPN_NAME" curl -s --interface tun0 --max-time 15 https://ifconfig.me)

        if [ -z "$CURRENT_IP" ]; then
            echo "Connection failed. Restarting container..."
            docker restart "$VPN_NAME"
            continue
        fi

        if grep -q "$CURRENT_IP" "$MANAGEMENT_FILE" 2>/dev/null; then
            echo "Duplicate IP ($CURRENT_IP) detected. Restarting for new IP..."
            sleep 2
            docker restart "$VPN_NAME"
        else
            echo "Success! Unique IP: $CURRENT_IP"
            UNIQUE=true
        fi
    done

    # 6. Run Traffmonetizer or Handle Failure
    if [ "$UNIQUE" = true ]; then
        docker run -d \
            --name "$TRAFF_NAME" \
            --network "container:$VPN_NAME" \
            --restart always \
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
            start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM=" --device-name "ipvanish"

        TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
        echo "$TIMESTAMP | File: $SERVER_ADDR | IP: $CURRENT_IP | VPN: $VPN_NAME | TRAFF: $TRAFF_NAME" >> "$MANAGEMENT_FILE"
    else
        echo "FAILED: Could not get a unique IP for instance $INSTANCE_NUM."
        docker rm -f "$VPN_NAME" > /dev/null 2>&1

        ((GLOBAL_FAIL_COUNT++))
        echo "Global failures: $GLOBAL_FAIL_COUNT/$MAX_GLOBAL_FAILS"

        if [ "$GLOBAL_FAIL_COUNT" -ge "$MAX_GLOBAL_FAILS" ]; then
            echo "CRITICAL ERROR: Reached $MAX_GLOBAL_FAILS total failures. Exiting script."
            exit 1
        fi
    fi
    echo "--------------------------------------------------------"
done

echo "Deployment finished. Total successfully processed: $TOTAL_SERVERS_TO_DEPLOY."
