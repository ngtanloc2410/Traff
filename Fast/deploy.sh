#!/bin/bash

# Usage: ./deploy_auto.sh <filename.ovpn>
# Example: ./deploy_auto.sh NCVPN-US-Seattle-TCP.ovpn

OVPN_FILE=$1
VPN_DIR=$(pwd) 
MANAGEMENT_FILE="ips.txt"
MAX_ATTEMPTS=8

# 1. Validate Input
if [ -z "$OVPN_FILE" ]; then
    echo "Error: Please provide the .ovpn file."
    echo "Usage: ./deploy_auto.sh <FILE_NAME>"
    exit 1
fi

if [ ! -f "$OVPN_FILE" ]; then
    echo "Error: File $OVPN_FILE not found."
    exit 1
fi

# 2. Extract Location and Count Servers
LOC_NAME=$(echo "$OVPN_FILE" | sed 's/NCVPN-//; s/-TCP.ovpn//; s/-Virtual//; s/ //g')

# Read all remote server lines into an array
SERVERS=($(grep '^remote ' "$OVPN_FILE" | awk '{print $2}'))
TOTAL_SERVERS=${#SERVERS[@]}

if [ "$TOTAL_SERVERS" -eq 0 ]; then
    echo "Error: No 'remote' server lines found in $OVPN_FILE."
    exit 1
fi

echo "Location: $LOC_NAME | Found $TOTAL_SERVERS unique servers. Starting deployment..."

# 3. Loop through each specific server
for (( i=0; i<$TOTAL_SERVERS; i++ )); do
    SERVER_ADDR=${SERVERS[$i]}
    INSTANCE_NUM=$((i * 2 + 1))
    
    VPN_NAME="vpn_${LOC_NAME}_${INSTANCE_NUM}"
    TRAFF_NAME="traff_${LOC_NAME}_${INSTANCE_NUM}"
    
    echo "--- Deploying Instance $INSTANCE_NUM/$TOTAL_SERVERS: $SERVER_ADDR ---"

    # 4. Run VPN container with a specific remote server override
    # We use --remote $SERVER_ADDR 443 to force the specific server for this container
    docker run -d \
        --name "$VPN_NAME" \
        --cap-add=NET_ADMIN \
        --device /dev/net/tun \
	--restart always \
        -v "$VPN_DIR":/vpn \
        --health-cmd="ping -c 1 www.ifconfig.me || exit 1" \
        --health-interval=75s \
        --health-timeout=20s \
        --health-retries=3 \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        alpine sh -c "apk add --no-cache openvpn curl && \
                      openvpn --config /vpn/$OVPN_FILE --auth-user-pass /vpn/vpn.txt --remote $SERVER_ADDR 443"

	# 5. UNIQUE IP CHECK with RESTART LOGIC
    UNIQUE=false
    CURRENT_IP=""
    ATTEMPT=0 
    
    while [ "$UNIQUE" = false ] && [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
        ((ATTEMPT++))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for IP from $SERVER_ADDR..."
        sleep 10

        CURRENT_IP=$(docker exec "$VPN_NAME" curl -s --max-time 10 https://ifconfig.me)
        
        if [ -z "$CURRENT_IP" ]; then
            echo "Connection failed. Restarting container..."
            docker restart "$VPN_NAME"
            continue
        fi

        # Check if IP is already in our management file
        if grep -q "$CURRENT_IP" "$MANAGEMENT_FILE" 2>/dev/null; then
            echo "Duplicate IP ($CURRENT_IP) detected for $SERVER_ADDR. Restarting to try for a new one..."
            sleep 2
            docker restart "$VPN_NAME"
        else
            echo "Success! Unique IP obtained: $CURRENT_IP"
            UNIQUE=true
        fi
    done

    # 6. Run Traffmonetizer if VPN is up
    if [ "$UNIQUE" = true ]; then
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
            start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM=" --device-name "${LOC_NAME}_${INSTANCE_NUM}"

        # Log to file
        TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
        echo "$TIMESTAMP | Server: $SERVER_ADDR | IP: $CURRENT_IP | VPN: $VPN_NAME" >> "$MANAGEMENT_FILE"
	else
        echo "FAILED: Could not get a unique IP for $SERVER_ADDR after $MAX_ATTEMPTS tries. Cleaning up..."
        docker rm -f "$VPN_NAME" > /dev/null 2>&1
    fi
    echo "--------------------------------------------------------"
done

echo "Deployment finished. Total containers: $TOTAL_SERVERS."
