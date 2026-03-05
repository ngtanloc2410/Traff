#!/bin/bash

# Configuration
PROXY_FILE="proxies.txt"
COMPOSE_FILE="docker-compose.yml"
# Check if the external network exists; if not, create it
if ! docker network inspect my_shared_proxy_network >/dev/null 2>&1; then
    echo "Creating network 'my_shared_proxy_network'..."
    docker network create my_shared_proxy_network
fi
ID_LOG="managed_instances.log"

# Resources
export TUN2SOCKS_CPU_LIMIT="0.05"
export TUN2SOCKS_RAM_LIMIT="128m"

export APP_CPU_LIMIT="0.03"
export APP_RAM_LIMIT="32m"
export APP_RAM_RESERVE="16m"

if [ ! -f "$PROXY_FILE" ]; then
    echo "Error: Proxy file '$PROXY_FILE' not found."
    exit 1
fi

# Prepare the log file with a header
echo "--- Instance Deployment Log: $(date) ---" >> "$ID_LOG"
echo "Instance_ID | Proxy_URL | Earnapp_UUID | Proxyrack_UUID" >> "$ID_LOG"

instance_counter=0

while IFS= read -r PROXY_URL; do
    [[ -z "$PROXY_URL" || "$PROXY_URL" =~ ^# ]] && continue

    instance_counter=$((instance_counter + 1))
    export INSTANCE_ID="${instance_counter}"
    export PROXY_URL

    # Generate Unique IDs
    export EARNAPP_UUID="sdk-node-$(head -c 16 /dev/urandom | xxd -p)"
    export PROXYRACK_UUID=$(cat /dev/urandom | LC_ALL=C tr -dc 'A-F0-9' | dd bs=1 count=64 2>/dev/null)

    # Create a local folder to store Earnapp data (Persistence)
    mkdir -p "./data/earnapp/instance_${INSTANCE_ID}"

    # Log the IDs to your file
    echo "${INSTANCE_ID} | ${PROXY_URL} | ${EARNAPP_UUID} | ${PROXYRACK_UUID}" >> "$ID_LOG"

    echo "Launching Instance ${INSTANCE_ID}..."
    
    docker compose -f "$COMPOSE_FILE" --project-name "proxy-stack-${INSTANCE_ID}" up -d

    sleep 2 
done < "$PROXY_FILE"

echo "Done! All IDs have been saved to: $ID_LOG"
