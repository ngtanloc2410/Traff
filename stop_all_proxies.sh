#!/bin/bash

PROXY_FILE="proxies.txt"

if [ ! -f "$PROXY_FILE" ]; then
    echo "Error: Proxy file '$PROXY_FILE' not found. Cannot stop services."
    exit 1
fi

echo "Stopping all proxy instances..."

instance_counter=0 # Initialize counter (must match start script logic)

while IFS= read -r PROXY_URL; do
    [[ -z "$PROXY_URL" || "$PROXY_URL" =~ ^# ]] && continue

    instance_counter=$((instance_counter + 1))
    INSTANCE_ID="${instance_counter}" # Re-generate INSTANCE_ID

    echo "--- Stopping proxy stack: proxy-${INSTANCE_ID} ---"
    docker compose --project-name "proxy-${INSTANCE_ID}" down
    echo ""
done < "$PROXY_FILE"

echo "All proxy instances stopped (or attempted)."
