#!/bin/bash

# --- Global Configuration (apply to all instances) ---
# IMPORTANT: Replace with your actual Traffmonetizer token and PacketShare credentials
export TRAFFMONETIZER_TOKEN="cCuCGOWZXNnk9dL5BR+cz1QHbjCdXJnFb8e3a9OAS2k="
export PACKETSHARE_EMAIL="locpaypal@gmail.com"
export PACKETSHARE_PASSWORD="Loc123456789"

# Optional: Set resource limits if needed, otherwise defaults from docker-compose.yml will be used
export ALT_MIN_CPU_LIMIT="0.5" # Example: 0.5 CPU core per instance
export RAM_LIMIT="512m"       # Example: 512MB RAM limit per instance
export RAM_RESERVE="256m"     # Example: 256MB RAM reservation per instance
# --- End Global Configuration ---

PROXY_FILE="proxies.txt"
COMPOSE_FILE="docker-compose.yml"

if [ ! -f "$PROXY_FILE" ]; then
    echo "Error: Proxy file '$PROXY_FILE' not found."
    exit 1
fi

echo "Starting multiple proxy instances..."

instance_counter=0 # Initialize counter

# Read proxies line by line
while IFS= read -r PROXY_URL; do
    # Skip empty lines or lines starting with #
    [[ -z "$PROXY_URL" || "$PROXY_URL" =~ ^# ]] && continue

    # Increment the counter for the unique ID
    instance_counter=$((instance_counter + 1))
    export INSTANCE_ID="${instance_counter}" # Set INSTANCE_ID to the current counter value

    echo "--- Processing proxy: $PROXY_URL (Instance ID: ${INSTANCE_ID}) ---"

    # Export PROXY_URL for this specific compose run
    export PROXY_URL

    # Run docker compose for this instance with a unique project name
    docker compose -f "$COMPOSE_FILE" --project-name "proxy-${INSTANCE_ID}" up -d

    if [ $? -ne 0 ]; then
        echo "Error starting services for proxy: $PROXY_URL. Check logs for details."
        # You might choose to exit here or continue to the next proxy
        # exit 1
    fi
    echo "" # Add a newline for readability

    # Add a 2-second delay before starting the next instance
    sleep 2

done < "$PROXY_FILE"

echo "All proxy instances launched (or attempted). To manage them:"
echo "List all running stacks: docker compose ls"
echo "To stop a specific stack: docker compose -p proxy-<NUMBER> down"
echo "To view logs for a specific stack (e.g., tun2socks): docker logs tun2socks-<NUMBER> -f"
echo "Example: docker logs tun2socks-1 -f"
echo "To stop ALL stacks started by this script: ./stop_all_proxies.sh"
