#!/bin/bash

# Usage: ./deploy.sh <number_of_instances> <city>
# Example: ./deploy.sh 100 'New York'

COUNT=$1
CITY=$2
SERVER_FILE="servers.txt"
MANAGEMENT_FILE="ips.txt"
MAX_ATTEMPTS=20

# 1. Validation
if [[ -z "$COUNT" || -z "$CITY" ]]; then
    echo "Usage: ./deploy.sh <number> <city>"
    exit 1
fi

if [[ ! -f "$SERVER_FILE" ]]; then
    echo "Error: $SERVER_FILE not found."
    exit 1
fi

# Get all hostnames for the specified city from servers.txt
# Filter by city (column 2) and extract hostname (column 3)
MAPFILE_HOSTNAMES=($(grep -i "|$CITY|" "$SERVER_FILE" | cut -d'|' -f3))

if [[ ${#MAPFILE_HOSTNAMES[@]} -eq 0 ]]; then
    echo "Error: No hostnames found for city '$CITY' in $SERVER_FILE."
    exit 1
fi

echo "Found ${#MAPFILE_HOSTNAMES[@]} hostname(s) for $CITY."

NAME_CITY=${CITY// /}
touch "$MANAGEMENT_FILE"
USED_IPS=()

echo "Deploying $COUNT instances to $CITY..."

for (( i=1; i<=$COUNT; i++ )); do
    # Randomly select one hostname from the available list for this specific instance
    RANDOM_INDEX=$(( RANDOM % ${#MAPFILE_HOSTNAMES[@]} ))
    SELECTED_HOSTNAME=${MAPFILE_HOSTNAMES[$RANDOM_INDEX]}
    
    VPN_NAME="vpn_${NAME_CITY}_$i"
    TRAFF_NAME="traff_${NAME_CITY}_$i"

    echo "--- Instance $i of $COUNT: $VPN_NAME ---"
    echo "Using Hostname: $SELECTED_HOSTNAME"

    # 2. Start Surfshark Container
    docker run -d \
        --name "$VPN_NAME" \
        --cap-add=NET_ADMIN \
        --device=/dev/net/tun:/dev/net/tun \
        --restart unless-stopped \
        -e VPN_SERVICE_PROVIDER="surfshark" \
        -e VPN_TYPE="wireguard" \
        -e WIREGUARD_PRIVATE_KEY="wGc4XIHxz1LpHpiUQpCQ+/JB7jIRtpX1XgVqVIwqo2w=" \
        -e WIREGUARD_ADDRESSES="10.14.0.2/16" \
        -e SERVER_HOSTNAMES="$SELECTED_HOSTNAME" \
        -e WIREGUARD_PERSISTENT_KEEPALIVE_INTERVAL="25s" \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        qmcgaw/gluetun
        
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

        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Checking connection (Initial 12s wait)..."
        sleep 12 

        # Try to get IP
        CURRENT_IP=$(docker logs "$VPN_NAME" 2>&1 | grep "Public IP address is" | tail -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

        # --- NEW GRACE PERIOD ---
        if [ -z "$CURRENT_IP" ]; then
            echo "IP not found yet. Giving it 12 more seconds before restarting..."
            sleep 12
            CURRENT_IP=$(docker logs "$VPN_NAME" 2>&1 | grep "Public IP address is" | tail -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        fi
        # ------------------------

        if [ -z "$CURRENT_IP" ]; then
            echo "No IP retrieved after two checks. Restarting VPN..."
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $CITY | $CURRENT_IP | $VPN_NAME | $SELECTED_HOSTNAME" >> "$MANAGEMENT_FILE"
    echo "--------------------------------------------------------"
done

echo "Deployment of $COUNT containers at $CITY finished."
