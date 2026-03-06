#!/bin/bash

echo "Searching for active proxy stacks..."

# We list the stacks, find your project names, and grab the first column
# This works on almost every version of Docker Compose
STACKS=$(docker compose ls | grep "proxy-stack-" | awk '{print $1}')

if [ -z "$STACKS" ]; then
    echo "No active proxy stacks found."
    exit 0
fi

echo "Found the following stacks to shut down:"
echo "$STACKS"
echo "----------------------------------------"

for STACK in $STACKS; do
    echo "Stopping and removing stack: $STACK..."
    
    # -p targets the project name; --volumes cleans up the virtual network
    docker compose -p "$STACK" down --volumes --remove-orphans
    
    if [ $? -eq 0 ]; then
        echo "Successfully stopped $STACK."
    else
        echo "Error: Failed to stop $STACK."
    fi
done

echo "----------------------------------------"
echo "All proxy stacks have been processed."
