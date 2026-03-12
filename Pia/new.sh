#!/bin/bash

# Usage: ./new.sh <hostname>
# Example: ./new.sh au-adelaide-pf.privacy.network

HOSTNAME=$1
SERVERS_FILE="servers.json"
MANAGEMENT_FILE="ips.txt"
MAX_ATTEMPTS=25

# 1. Validate Input
if [ -z "$HOSTNAME" ]; then
    echo "Error: Please provide a hostname (e.g., au-adelaide-pf.privacy.network)."
    exit 1
fi

if [ ! -f "$SERVERS_FILE" ]; then
    echo "Error: $SERVERS_FILE not found."
    exit 1
fi

# 2. Extract Region and Total IP Count across all matching hostnames
# This looks for all servers matching the hostname and sums the length of their "ips" arrays
SERVER_DATA=$(jq -r --arg HOST "$HOSTNAME" '
    .["private internet access"].servers 
    | map(select(.hostname | contains($HOST))) 
    | if length > 0 then 
        {
            region: .[0].region, 
            count: ([.[].ips[]] | length)
        } 
      else 
        empty 
      end 
    | @base64
' "$SERVERS_FILE")

if [ -z "$SERVER_DATA" ]; then
    echo "Error: Hostname $HOSTNAME not found in servers.json."
    exit 1
fi

# Decode the JSON data
_decode() { echo ${SERVER_DATA} | base64 --decode | jq -r "$1"; }
SERVER_REGION=$(_decode '.region')
IP_COUNT=$(((_decode '.count') * 2))

# Sanitize region name for container naming (replace spaces with underscores)
REGION_CLEAN=$(echo "$SERVER_REGION" | tr ' ' '_')

echo "Found Region: $SERVER_REGION"
echo "Found $IP_COUNT total IPs for hostname: $HOSTNAME"

# 3. Deployment Loop
for (( i=1; i<=$IP_COUNT; i++ )); do
    VPN_NAME="vpn_${REGION_CLEAN}_${i}"
    TRAFF_NAME="traff_${REGION_CLEAN}_${i}"
    
    echo "--- Deploying Instance $i: $VPN_NAME ---"

    docker run -d \
        --name "$VPN_NAME" \
        --cap-add=NET_ADMIN \
        --device /dev/net/tun \
        --restart always \
        -e VPN_SERVICE_PROVIDER="private internet access" \
        -e OPENVPN_USER=p3526321 \
        -e OPENVPN_PASSWORD=Loc123456789 \
        -v /gluetun:/gluetun \
        -e SERVER_REGIONS="$SERVER_REGION" \
        qmcgaw/gluetun

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

        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for Gluetun to report IP..."
        
        # Give Gluetun time to finish the handshake and run its internal IP check
        sleep 12

        # Retrieve IP from Docker logs
        # We look for the most recent "Public IP address is" line
        CURRENT_IP=$(docker logs "$VPN_NAME" 2>&1 | grep "Public IP address is" | tail -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        
        if [ -z "$CURRENT_IP" ]; then
            echo "No IP reported in logs yet. (Handshake pending or failed)."
            # Optional: Check if logs show a fatal error to restart faster
            if docker logs "$VPN_NAME" 2>&1 | grep -q "FATAL"; then
                echo "Fatal error detected in logs. Restarting..."
                docker restart "$VPN_NAME"
            fi
            continue
        fi

        # Check if IP is in the managed file OR already used
        if grep -q "$CURRENT_IP" "$MANAGEMENT_FILE" 2>/dev/null || [[ " ${USED_IPS[@]} " =~ " ${CURRENT_IP} " ]]; then
            echo "Duplicate IP detected ($CURRENT_IP). Requesting new IP..."
            sleep 2
            docker restart "$VPN_NAME"
            # Reset current IP so the loop continues
            CURRENT_IP="" 
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
        start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM=" --device-name "n$CURRENT_IP"

    # 6. Write to the management file
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$TIMESTAMP | Region: $SERVER_REGION | IP: $CURRENT_IP | VPN: $VPN_NAME | Traff: $TRAFF_NAME" >> "$MANAGEMENT_FILE"

    echo "Instance $i saved to $MANAGEMENT_FILE"
    echo "--------------------------------------------------------"
done

echo "Deployment of $IP_COUNT instances complete."
