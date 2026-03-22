#!/bin/bash

# --- CONFIGURATION ---
OUTPUT_FILE="live_proxies.txt"
TEMP_RAW="raw_proxies.txt"
THREADS=150              # Increased threads since we aren't hitting an API limit
TIMEOUT=8                # Seconds to wait for a response
TEST_URL="https://www.wikipedia.org/"

# --- COLORING ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' 

# Clear/Initialize
> "$OUTPUT_FILE"
> "$TEMP_RAW"

echo -e "${BLUE}[*] Scraping all proxy resources...${NC}"

# 1. SOURCES
SOURCES=(
    "https://raw.githubusercontent.com/ProxyScraper/ProxyScraper/refs/heads/main/socks5.txt"
    "https://github.com/ProxyScraper/ProxyScraper/raw/refs/heads/main/http.txt"
    "https://github.com/sunny9577/proxy-scraper/raw/refs/heads/master/generated/socks5_proxies.txt"
    "https://github.com/sunny9577/proxy-scraper/raw/refs/heads/master/generated/http_proxies.txt"
    "https://raw.githubusercontent.com/Skillter/ProxyGather/refs/heads/master/proxies/working-proxies-http.txt"
    "https://raw.githubusercontent.com/Skillter/ProxyGather/refs/heads/master/proxies/working-proxies-socks5.txt"
    "https://github.com/alphaa1111/proxyscraper/raw/refs/heads/main/proxies/http.txt"
    "https://github.com/alphaa1111/proxyscraper/raw/refs/heads/main/proxies/socks.txt"
    "https://api.proxyscrape.com/v2/?request=displayproxies&protocol=http&timeout=10000&country=US&ssl=all&anonymity=all"
    "https://api.proxyscrape.com/v2/?request=displayproxies&protocol=socks5&timeout=10000&country=US&ssl=all&anonymity=all"
    "https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/http.txt"
    "https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/socks5.txt"
    "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt"
    "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/socks5.txt"
    "https://raw.githubusercontent.com/hookzof/socks5_list/master/proxy.txt"
    "https://api.openproxylist.xyz/http.txt"
    "https://api.openproxylist.xyz/socks5.txt"
    "https://raw.githubusercontent.com/komutan234/Proxy-List-Free/main/proxies/http.txt"
    "https://raw.githubusercontent.com/komutan234/Proxy-List-Free/main/proxies/socks5.txt"
    "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies_anonymous/http.txt"
    "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies_anonymous/socks5.txt"
)

# 2. DOWNLOAD & TAG
for url in "${SOURCES[@]}"; do
    if [[ $url == *"socks"* ]]; then proto="socks5"; else proto="http"; fi
    
    echo -e "${YELLOW}[->] Downloading $proto:${NC} ${url##*/}"
    # Download, clean Windows carriage returns, and tag protocol
    curl -sSL --connect-timeout 5 "$url" | tr -d '\r' | sed "s/^/$proto:\/\//" >> "$TEMP_RAW"
done

# 3. DEDUPLICATE BEFORE CHECKING
sort -u "$TEMP_RAW" -o "$TEMP_RAW"
sed -i '/^[[:space:]]*$/d' "$TEMP_RAW"

TOTAL=$(wc -l < "$TEMP_RAW")
echo -e "${BLUE}[*] $TOTAL unique proxies to test. Using $THREADS threads...${NC}"

# 4. EXPORTED LIVENESS CHECKER
# We only care if the connection succeeds (Exit code 0)
check_live() {
    local proxy=$1
    local timeout=$2
    local output=$3
    local target=$4

    # -I fetches headers only (faster/less data)
    if curl -sI --proxy "$proxy" --max-time "$timeout" "$target" > /dev/null; then
        echo -e "${GREEN}[LIVE]${NC} $proxy"
        echo "$proxy" >> "$output"
    fi
}

export -f check_live
export TIMEOUT OUTPUT_FILE TEST_URL GREEN NC

# 5. PARALLEL EXECUTION
cat "$TEMP_RAW" | xargs -I {} -P "$THREADS" bash -c 'check_live "{}" "$TIMEOUT" "$OUTPUT_FILE" "$TEST_URL"'

# 6. FINAL CLEAN & SUMMARY
if [ -f "$OUTPUT_FILE" ]; then
    sort -u "$OUTPUT_FILE" -o "$OUTPUT_FILE"
    FINAL_COUNT=$(wc -l < "$OUTPUT_FILE")
    echo "--------------------------------------------------"
    echo -e "${GREEN}[DONE] Found $FINAL_COUNT live proxies.${NC}"
    echo -e "${BLUE}[FILE] Saved to: $OUTPUT_FILE${NC}"
else
    echo -e "${YELLOW}[!] No live proxies found.${NC}"
fi

rm "$TEMP_RAW"
