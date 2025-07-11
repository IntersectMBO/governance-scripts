#!/bin/bash

######################################################

# Can change if you want!

# Timeout for curl requests in seconds
TIMEOUT=5

######################################################

# Exit immediately if a command exits with a non-zero status, 
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

# Colors
#BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BRIGHTWHITE='\033[0;37;1m'
NC='\033[0m'

# Gateways to check if file is already hosted on IPFS
DEFAULT_GATEWAY_1="https://ipfs.io/ipfs/"
DEFAULT_GATEWAY_2="https://gateway.pinata.cloud/ipfs/"
# DEFAULT_GATEWAY_3="https://w3s.link/ipfs"

# Other gateways like Dweb.link, 4everland, w3s.link don't seem to work well with curl
# in future we can fix them by reading the https header and checking if the file is content is returned

# for more gateways see:
# https://ipfs.github.io/public-gateway-checker/

######################################################

# check if user has ipfs cli installed
if ! command -v ipfs >/dev/null 2>&1; then
  echo -e "${RED}Error: ipfs cli is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <file|CID>"
    echo "Check if a file or IPFS CIDv1 is discoverable via free IPFS gateways"
    echo "  "
    echo "Options:"
    echo "  <file|CID>                  Path to your file."
    exit 1
}

# Initialize variables with defaults
input_path=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_path" ]; then
                input_path="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$input_path" ]; then
    echo -e "${RED}Error: No file or CID specified${NC}" >&2
    usage
fi

echo -e " "
echo -e "${YELLOW}Checking IPFS file availability via public gateways${NC}"
echo -e "${CYAN}This script checks if a file or CID is accessible through free IPFS gateways${NC}"

# Check if the input is a file or CID
file="false"

echo -e " "
if [[ -f "$input_path" ]]; then
    file="true"
    echo -e "${CYAN}Input is a file: ${YELLOW}$input_path${NC}"
elif [[ "$input_path" =~ ^[a-zA-Z0-9]{59,}$ ]]; then
    echo -e "${CYAN}Input is a CID: ${YELLOW}$input_path${NC}"
else
    echo -e "${RED}Input is neither a file nor a valid CID${NC}"
    echo -e "${RED}Error: Invalid input: $input_path is not a valid file or CID${NC}" >&2
    usage
fi

# Generate CID from the given if needed

ipfs_cid=" "

if [ "$file" = "false" ]; then
    ipfs_cid="$input_path"
else
    echo -e " "
    echo -e "${CYAN}Generating CID for the file...${NC}"
    ipfs_cid=$(ipfs add -Q --cid-version 1 "$input_path")
fi

echo -e "CID: ${YELLOW}$ipfs_cid${NC}"

check_file_via_gateway() {
    local gateway="$1"
    local cid="$2"
    local timeout="$3"
    echo -e " "
    echo -e "${CYAN}Checking ${gateway}...${NC}"
    if curl --silent --fail --max-time $timeout "${gateway}${cid}" >/dev/null; then
        echo -e "${GREEN}File is accessible on IPFS via ${gateway}${cid}${NC}"
        return 0
    else
        echo -e "${RED}File not found at: ${gateway}${cid}${NC}"
        return 1
    fi
}

# If file can be found via gateways then exit
if check_file_via_gateway "$DEFAULT_GATEWAY_1" "$ipfs_cid" "$TIMEOUT"; then
    echo -e " "
    echo -e "${GREEN}File found and accessible via IPFS gateways${NC}"
    exit 0
fi
if check_file_via_gateway "$DEFAULT_GATEWAY_2" "$ipfs_cid" "$TIMEOUT"; then
    echo -e " "
    echo -e "${GREEN}File found and accessible via IPFS gateways${NC}"
    exit 0
fi

# todo: add more gateways

# If file cannot be found via gateways then exit
echo -e " "
echo -e "${RED}File cannot be found via any IPFS gateways. Exiting.${NC}"
exit 1
