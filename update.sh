#!/bin/bash

INSTANCE_ID=$1
NEW_PROXY=$2

if [ -z "$INSTANCE_ID" ] || [ -z "$NEW_PROXY" ]; then
    echo "Usage: ./update.sh <instance_number> <new_proxy_url>"
    exit 1
fi

LOG_FILE="id.log"

# 1. Find the existing IDs in the log so we don't lose money
# We search for the line starting with the Instance ID
LINE=$(grep "^${INSTANCE_ID} |" "$LOG_FILE")

if [ -z "$LINE" ]; then
    echo "Error: Instance ID $INSTANCE_ID not found in $LOG_FILE"
    exit 1
fi

# Extract IDs using awk
# Format: ID | Proxy | Earnapp | Proxyrack
OLD_EARNAPP=$(echo "$LINE" | awk -F '|' '{print $3}' | xargs)
OLD_PROXYRACK=$(echo "$LINE" | awk -F '|' '{print $4}' | xargs)

echo "Updating Instance $INSTANCE_ID..."
echo "Keeping Earnapp ID: $OLD_EARNAPP"

# 2. Stop the specific stack
sudo docker compose -p "proxy-stack-${INSTANCE_ID}" down

# 3. Start it back up with the NEW proxy but OLD IDs
export INSTANCE_ID="$INSTANCE_ID"
export PROXY_URL="$NEW_PROXY"
export EARNAPP_UUID="$OLD_EARNAPP"
export PROXYRACK_UUID="$OLD_PROXYRACK"
export TUN2SOCKS_CPU_LIMIT="0.05"
export TUN2SOCKS_RAM_LIMIT="128m"

sudo -E docker compose -f compose.yml -p "proxy-stack-${INSTANCE_ID}" up -d

# 4. (Optional) Update the log file with the new proxy URL
# This replaces the old proxy line with the new one in your log
sed -i "/^${INSTANCE_ID} |/c\\${INSTANCE_ID} | ${NEW_PROXY} | ${OLD_EARNAPP} | ${OLD_PROXYRACK}" "$LOG_FILE"

echo "Success! Instance $INSTANCE_ID is now using $NEW_PROXY"
