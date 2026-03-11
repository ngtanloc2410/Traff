#!/bin/bash

# Usage: ./deploy.sh <number_of_instances> <server_id>
# Example: ./deploy.sh 100 us-chi

COUNT=$1
SERVER_ID=$2
MANAGEMENT_FILE="managed_ips.txt"
MAX_ATTEMPTS=20

# Credentials from test.yml
VPN_USER="ZSvcsm2zhYe9kthVEmtkzPTK"
VPN_PASS="NuWYDscHPf4aFAZ5vdhY67Yv"

# 1. Validation
if [[ -z "$COUNT" || -z "$SERVER_ID" ]]; then
    echo "Usage: ./deploy.sh <number> <country-city>"
    exit 1
fi

# Split server_id (e.g., us-chi) into variables
COUNTRY=$(echo "$SERVER_ID" | cut -d'-' -f1)
CITY=$(echo "$SERVER_ID" | cut -d'-' -f2)

touch "$MANAGEMENT_FILE"
USED_IPS=()

echo "Deploying $COUNT instances to $SERVER_ID..."

for (( i=1; i<=$COUNT; i++ )); do
    VPN_NAME="vpn_${SERVER_ID}_$i"
    TRAFF_NAME="traff_${SERVER_ID}_$i"

    echo "--- Instance $i of $COUNT: $VPN_NAME ---"

    # 2. Start Surfshark Container
    docker run -d \
        --name "$VPN_NAME" \
        --cap-add=NET_ADMIN \
        --device=/dev/net/tun:/dev/net/tun \
        --restart unless-stopped \
        -e SURFSHARK_USER="$VPN_USER" \
        -e SURFSHARK_PASSWORD="$VPN_PASS" \
        -e SURFSHARK_COUNTRY="$COUNTRY" \
        -e SURFSHARK_CITY="$CITY" \
        -e CONNECTION_TYPE=tcp \
        --dns=1.1.1.1 \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        --health-cmd="ping -c 1 www.ifconfig.me || exit 1" \
        --health-interval=90s \
        --health-timeout=20s \
        --health-retries=3 \
        ilteoood/docker-surfshark

    # 3. Unique IP Check Loop
    UNIQUE=false
    CURRENT_IP=""
    ATTEMPT=0

    while [ "$UNIQUE" = false ]; do
        ((ATTEMPT++))

        if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
            echo "ERROR: Max attempts reached for $VPN_NAME. No unique IP found. Exiting script."
            docker rm -f "$VPN_NAME" > /dev/null 2>&1
            exit 1
        fi

        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Checking connection..."
        sleep 10 # Allow time for tunnel establishment

        # Get current IP via the VPN container
        CURRENT_IP=$(docker exec "$VPN_NAME" curl -s --max-time 10 https://ifconfig.me)

        if [ -z "$CURRENT_IP" ]; then
            echo "No IP retrieved. Restarting VPN..."
            docker restart "$VPN_NAME"
            continue
        fi

        # Verify IP is not in history or current session
        if grep -q "$CURRENT_IP" "$MANAGEMENT_FILE" 2>/dev/null || [[ " ${USED_IPS[@]} " =~ " ${CURRENT_IP} " ]]; then
            echo "Duplicate IP ($CURRENT_IP). Retrying..."
            sleep 5
            docker restart "$VPN_NAME"
        else
            echo "Success! Unique IP: $CURRENT_IP"
            USED_IPS+=("$CURRENT_IP")
            UNIQUE=true
        fi
    done

    # 4. Run Traffmonetizer
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
        start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM=" --device-name "node-$CURRENT_IP"

    # 5. Logging
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $SERVER_ID | $CURRENT_IP | $VPN_NAME" >> "$MANAGEMENT_FILE"
    echo "--------------------------------------------------------"
done

echo "Deployment of $COUNT containers at $SERVER_ID finished."
