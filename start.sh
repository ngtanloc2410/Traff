#!/bin/bash

# Configuration
PROXY_FILE="live_proxies.txt"
ID_LOG="id.log"
NETWORK_NAME="my_shared_proxy_network"

# Resource Limits (Optimized for 1,000 instances)
CPU_LIMIT="0.03"
RAM_LIMIT="32m"
RAM_RESERVE="16m"

# Logging Limits
LOG_OPTS="--log-driver json-file --log-opt max-size=10m --log-opt max-file=3"

# DNS Servers
DNS_FLAGS="--dns 8.8.8.8 --dns 1.1.1.1 --dns 8.8.4.4"

# Ensure external network exists
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Creating network '$NETWORK_NAME'..."
    docker network create --subnet=172.20.0.0/16 "$NETWORK_NAME"
fi

if [ ! -f "$PROXY_FILE" ]; then
    echo "Error: Proxy file '$PROXY_FILE' not found."
    exit 1
fi

echo "--- Deployment Log: $(date) ---" >> "$ID_LOG"

while IFS= read -r PROXY_URL; do
    [[ -z "$PROXY_URL" || "$PROXY_URL" =~ ^# ]] && continue

    PROTOCOL=$(echo "$PROXY_URL" | cut -d':' -f1 | tr '[:upper:]' '[:lower:]')

    echo "Checking exit IP for proxy..."
    EXIT_IP=$(curl -s --proxy "$PROXY_URL" --max-time 10 https://api.ipify.org)

    if [[ -z "$EXIT_IP" ]]; then
        echo "Error: Proxy unreachable. Skipping..."
        continue
    fi

    if docker ps --format '{{.Names}}' | grep -q "^tun2proxy-$EXIT_IP$"; then
        echo "Instance with Exit IP $EXIT_IP is already running. Skipping..."
        continue
    fi

    # DNS Logic based on Protocol
    DNS_ARG=""
    if [[ "$PROTOCOL" == "http" ]]; then
        DNS_ARG="--dns virtual"
    elif [[ "$PROTOCOL" == "https" ]]; then
        DNS_ARG="--dns over-tcp"
    fi

    echo "Deploying: Exit IP $EXIT_IP [$PROTOCOL]"

    # 1. Run tun2proxy 
    # Removed no-new-privileges and the RO volume mount
    docker run -d \
        --name "tun2proxy-$EXIT_IP" \
        $LOG_OPTS \
        $DNS_FLAGS \
        --restart always \
        --network "$NETWORK_NAME" \
        --cap-add NET_ADMIN \
        --device /dev/net/tun:/dev/net/tun \
        --sysctl net.ipv4.ip_forward=1 \
        --init \
        --cpus "$CPU_LIMIT" \
        --memory "$RAM_LIMIT" \
        --memory-reservation "$RAM_RESERVE" \
        ghcr.io/tun2proxy/tun2proxy-alpine:v0.7.19 \
        --proxy "$PROXY_URL" $DNS_ARG

    sleep 2 

    # 2. Run traffmonetizer
    docker run -d \
        --name "traffmonetizer-$EXIT_IP" \
        $LOG_OPTS \
        --restart always \
        --network "container:tun2proxy-$EXIT_IP" \
        --cpus "$CPU_LIMIT" \
        --memory "$RAM_LIMIT" \
        --memory-reservation "$RAM_RESERVE" \
        --health-cmd "curl -f ipinfo.io || exit 1" \
        --health-interval 70s \
        --health-timeout 20s \
        --health-retries 3 \
        --health-start-period 15s \
        ghcr.io/ngtanloc2410/traffmonetizer:latest \
        start accept --token "tbOBkhRHWXCl8NHzr+/GF5qHDrWRo43PFU1XzPe+GGM="

    echo "$(date '+%Y-%m-%d %H:%M:%S') | Exit: $EXIT_IP | Proto: $PROTOCOL" >> "$ID_LOG"

done < "$PROXY_FILE"
