#!/bin/bash

# Usage: ./deploy_auto.sh <filename.ovpn>
OVPN_FILE=$1
VPN_DIR=$(pwd) 
MANAGEMENT_FILE="ips.txt"
MAX_ATTEMPTS=5     # Retries for a single container to get an IP
MAX_GLOBAL_FAILS=5   # Script will exit if 10 different instances fail
GLOBAL_FAIL_COUNT=0    # Counter for global failures

docker pull ghcr.io/ngtanloc2410/tocdocualoc:latest
docker pull ghcr.io/ngtanloc2410/traffmonetizer:latest

# 1. Validate Input
if [ -z "$OVPN_FILE" ]; then
    echo "Error: Please provide the .ovpn file."
    echo "Usage: ./deploy_auto.sh <FILE_NAME>"
    exit 1
fi

if ! docker network inspect my_shared_proxy_network >/dev/null 2>&1; then
    echo "Creating network 'my_shared_proxy_network'..."
    docker network create --subnet=172.20.0.0/16 my_shared_proxy_network
fi

if [ ! -f "$OVPN_FILE" ]; then
    echo "Error: File $OVPN_FILE not found."
    exit 1
fi

# 2. Extract Location and Count Servers
LOC_NAME=$(echo "$OVPN_FILE" | sed 's/NCVPN-//; s/-TCP.ovpn//; s/-Virtual//; s/ //g')

# Read all remote server lines into an array
SERVERS=($(grep '^remote ' "$OVPN_FILE" | awk '{print $2}'))
NUM_SERVERS=${#SERVERS[@]} # Actual number of servers in the file

if [ "$NUM_SERVERS" -eq 0 ]; then
    echo "Error: No 'remote' server lines found in $OVPN_FILE."
    exit 1
fi

# Determine how many total containers you want to deploy
# This uses your logic: (Server Count * 2) + 30
TOTAL_SERVERS_TO_DEPLOY=$(( (NUM_SERVERS * 2) + 30 ))

echo "Location: $LOC_NAME | Found $NUM_SERVERS unique servers."
echo "Target: Deploying $TOTAL_SERVERS_TO_DEPLOY instances (looping through server list)."

# 3. Loop through each specific server
for (( i=0; i<$TOTAL_SERVERS_TO_DEPLOY; i++ )); do
    # MODULO LOGIC: This ensures if i >= NUM_SERVERS, it starts back at index 0
    SERVER_INDEX=$(( i % NUM_SERVERS ))
    SERVER_ADDR=${SERVERS[$SERVER_INDEX]}
    INSTANCE_NUM=$((i + 1))
    
    VPN_NAME="vpn_${LOC_NAME}_${INSTANCE_NUM}"
    TRAFF_NAME="traff_${LOC_NAME}_${INSTANCE_NUM}"
    
    echo "--- Instance $INSTANCE_NUM/$TOTAL_SERVERS_TO_DEPLOY: Using Server $SERVER_ADDR ---"

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
        -e OVPN_FILE="$OVPN_FILE" \
        -e SERVER_ADDR="$SERVER_ADDR" \
        --log-driver json-file \
        --log-opt max-size="5m" \
        --log-opt max-file="3" \
        ghcr.io/ngtanloc2410/tocdocualoc:latest

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
            start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM=" --device-name "texas"

        TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
        echo "$TIMESTAMP | Server: $SERVER_ADDR | IP: $CURRENT_IP | VPN: $VPN_NAME | TRAFF: $TRAFF_NAME" >> "$MANAGEMENT_FILE"
    else
        echo "FAILED: Could not get a unique IP for instance $INSTANCE_NUM."
        docker rm -f "$VPN_NAME" > /dev/null 2>&1
        
        # GLOBAL FAILURE LOGIC
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
