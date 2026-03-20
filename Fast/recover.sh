#!/bin/bash

apk add curl

clear

MAX_ATTEMPTS=5
MANAGEMENT_FILE="ips.txt"

# 1. Get the actual Host IP to ensure the VPN isn't leaking it
echo "Fetching Host IP..."
HOST_IP=$(curl -s --max-time 15 https://ifconfig.me)

if [ -z "$HOST_IP" ]; then
    echo "Error: Could not determine Host IP. Check your main internet connection."
    exit 1
fi
echo "Host IP is: $HOST_IP"
echo "--------------------------------------------------------"

# 2. Find all exited VPN containers
EXITED_VPNS=$(docker ps -a --filter "ancestor=ghcr.io/ngtanloc2410/tocdocualoc:latest" --filter "status=exited" --format "{{.Names}}")

if [ -z "$EXITED_VPNS" ]; then
    echo "All good! No exited VPN containers found."
    exit 0
fi

# 3. Process each exited VPN container
for VPN_NAME in $EXITED_VPNS; do
    # Derive the traff container name by replacing 'vpn_' with 'traff_'
    TRAFF_NAME="${VPN_NAME/vpn_/traff_}"
    
    echo "Found exited VPN: $VPN_NAME"
    echo "Corresponding TRAFF: $TRAFF_NAME"
    
    # Extract the Old IP and Server from ips.txt (grabbing the most recent entry)
    OLD_IP=$(grep "VPN: $VPN_NAME |" "$MANAGEMENT_FILE" | tail -n 1 | awk -F'IP: ' '{print $2}' | awk -F' ' '{print $1}')
    SERVER_ADDR=$(grep "VPN: $VPN_NAME |" "$MANAGEMENT_FILE" | tail -n 1 | awk -F'Server: ' '{print $2}' | awk -F' ' '{print $1}')
    
    # Fallback if not found in the file for some reason
    OLD_IP=${OLD_IP:-"Unknown"}
    SERVER_ADDR=${SERVER_ADDR:-"Unknown"}
    
    echo "Last known IP in log: $OLD_IP (Server: $SERVER_ADDR)"
    
    # Stop both just to be safe and clear their states
    echo "Stopping both containers..."
    docker stop "$TRAFF_NAME" "$VPN_NAME" >/dev/null 2>&1
    
    # Start the VPN container
    echo "Starting VPN container ($VPN_NAME)..."
    docker start "$VPN_NAME" >/dev/null 2>&1
    
    # 4. Check for a valid VPN IP
    SUCCESS=false
    for (( ATTEMPT=1; ATTEMPT<=MAX_ATTEMPTS; ATTEMPT++ )); do
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for VPN IP..."
        sleep 15
        
        # Grab the IP from the tun0 interface
        CURRENT_IP=$(docker exec "$VPN_NAME" curl -s --interface tun0 --max-time 15 https://ifconfig.me)
        
        if [ -z "$CURRENT_IP" ]; then
            echo "Connection failed (No IP). Restarting container..."
            docker restart "$VPN_NAME" >/dev/null 2>&1
            continue
        fi

        if [ "$CURRENT_IP" == "$HOST_IP" ]; then
            echo "Warning: Container is using Host IP ($CURRENT_IP). Restarting..."
            docker restart "$VPN_NAME" >/dev/null 2>&1
            continue
        fi

        SUCCESS=true
        break
    done
    
    # 5. Start the Traffmonetizer container if VPN is successful
    if [ "$SUCCESS" = true ]; then
        echo "Starting $TRAFF_NAME..."
        docker start "$TRAFF_NAME" >/dev/null 2>&1
        
        # Display the change
        echo "✅ RECOVERY SUCCESS:"
        echo "IP Change: $OLD_IP  -->  $CURRENT_IP"
        
        # Append the new record to ips.txt so the log remains up to date
        TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
        echo "$TIMESTAMP | Server: $SERVER_ADDR | IP: $CURRENT_IP | VPN: $VPN_NAME | TRAFF: $TRAFF_NAME" >> "$MANAGEMENT_FILE"
        echo "Log updated."

    else
        echo "❌ FAILED: Could not establish a valid VPN connection for $VPN_NAME after $MAX_ATTEMPTS attempts."
        echo "Stopping $VPN_NAME. $TRAFF_NAME will remain stopped."
        docker stop "$VPN_NAME" >/dev/null 2>&1
    fi
    echo "--------------------------------------------------------"
done

echo "Recovery check complete."
