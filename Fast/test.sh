#!/bin/bash
set -u

# Usage: ./deploy_auto.sh <filename.ovpn>
OVPN_FILE=$1
VPN_DIR=$(pwd)
MANAGEMENT_FILE="ips.txt"
MAX_GLOBAL_FAILS=7
GLOBAL_FAIL_COUNT=0
STARTUP_WAIT=25

IMAGE_NAME="ghcr.io/ngtanloc2410/tocdocualoc:test"
TRAFF_TOKEN="tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM="

if [ -z "${OVPN_FILE:-}" ]; then
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

touch "$MANAGEMENT_FILE"

LOC_NAME=$(echo "$OVPN_FILE" | sed 's/NCVPN-//; s/-TCP.ovpn//; s/-Virtual//; s/ //g')

SERVERS=($(grep '^remote ' "$OVPN_FILE" | awk '{print $2}'))
NUM_SERVERS=${#SERVERS[@]}

if [ "$NUM_SERVERS" -eq 0 ]; then
    echo "Error: No 'remote' server lines found in $OVPN_FILE."
    exit 1
fi

TOTAL_SERVERS_TO_DEPLOY=$(( (NUM_SERVERS * 2) + 30 ))

echo "Location: $LOC_NAME | Found $NUM_SERVERS unique servers."
echo "Target: Deploying $TOTAL_SERVERS_TO_DEPLOY instances (looping through server list)."

for (( i=0; i<$TOTAL_SERVERS_TO_DEPLOY; i++ )); do
    SERVER_INDEX=$(( i % NUM_SERVERS ))
    SERVER_ADDR=${SERVERS[$SERVER_INDEX]}
    INSTANCE_NUM=$((i + 1))

    VPN_NAME="vpn_${LOC_NAME}_${INSTANCE_NUM}"

    echo "--- Instance $INSTANCE_NUM/$TOTAL_SERVERS_TO_DEPLOY: Using Server $SERVER_ADDR ---"

    docker rm -f "$VPN_NAME" >/dev/null 2>&1 || true

    docker run -d \
        --name "$VPN_NAME" \
        --restart always \
        --cap-add=NET_ADMIN \
        --device /dev/net/tun \
        --network="my_shared_proxy_network" \
        --cpus "0.03" \
        --memory "32m" \
        --memory-reservation "16m" \
        -v "$VPN_DIR":/vpn \
        -e OVPN_FILE="$OVPN_FILE" \
        -e SERVER_ADDR="$SERVER_ADDR" \
        -e MANAGEMENT_FILE="/vpn/$MANAGEMENT_FILE" \
        -e TRAFF_TOKEN="$TRAFF_TOKEN" \
        -e MAX_IP_ATTEMPTS="7" \
        -e IP_WAIT_SECONDS="10" \
        --log-driver json-file \
        --log-opt max-size="5m" \
        --log-opt max-file="3" \
        "$IMAGE_NAME"

    sleep "$STARTUP_WAIT"

    CONTAINER_STATUS=$(docker inspect "$VPN_NAME" --format='{{.State.Status}}' 2>/dev/null || echo "missing")
    CONTAINER_EXIT_CODE=$(docker inspect "$VPN_NAME" --format='{{.State.ExitCode}}' 2>/dev/null || echo "999")

    if [ "$CONTAINER_STATUS" = "running" ]; then
        echo "Success! Container $VPN_NAME is running."
    else
        echo "FAILED: Container $VPN_NAME exited early with code $CONTAINER_EXIT_CODE"
        docker logs --tail 30 "$VPN_NAME" 2>/dev/null || true
        docker rm -f "$VPN_NAME" >/dev/null 2>&1 || true

        GLOBAL_FAIL_COUNT=$((GLOBAL_FAIL_COUNT + 1))
        echo "Global failures: $GLOBAL_FAIL_COUNT/$MAX_GLOBAL_FAILS"

        if [ "$GLOBAL_FAIL_COUNT" -ge "$MAX_GLOBAL_FAILS" ]; then
            echo "CRITICAL ERROR: Reached $MAX_GLOBAL_FAILS total failures. Exiting script."
            exit 1
        fi
    fi

    echo "--------------------------------------------------------"
done

echo "Deployment finished. Total successfully processed: $TOTAL_SERVERS_TO_DEPLOY."
