#!/bin/bash

######################################################

# Can change if you want!

# Timeout for curl requests in seconds
TIMEOUT=5

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
  echo "Error: ipfs cli is not installed or not in your PATH." >&2
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
    echo -e "Error: No file or CID specified" >&2
    usage
fi

# Check if the input is a file or CID
file="false"

if [[ -f "$input_path" ]]; then
    file="true"
    echo "Input is a file"
elif [[ "$input_path" =~ ^[a-zA-Z0-9]{59,}$ ]]; then
    echo "Input is a CID"
else
    echo "Input is neither a file nor a valid CID"
    echo -e "Error: Invalid input: $input_path is not a valid file or CID" >&2
    usage
fi

# Generate CID from the given if needed

ipfs_cid=" "

if [ "$file" = "false" ]; then
    ipfs_cid="$input_path"
else
    echo "Generating CID for the file..."
    ipfs_cid=$(ipfs add -Q --cid-version 1 "$input_path")
fi

echo "CID: $ipfs_cid"

check_file_via_gateway() {
    local gateway="$1"
    local cid="$2"
    local timeout="$3"
    echo " "
    echo "Checking ${gateway}..."
    if curl --silent --fail --max-time $timeout "${gateway}${cid}" >/dev/null; then
        echo "File is accessible on IPFS via ${gateway}${cid}"
        return 0
    else
        echo "File not found at: ${gateway}${cid}"
        return 1
    fi
}

# If file can be found via gateways then exit
if check_file_via_gateway "$DEFAULT_GATEWAY_1" "$ipfs_cid" "$TIMEOUT"; then
    exit 0
fi
if check_file_via_gateway "$DEFAULT_GATEWAY_2" "$ipfs_cid" "$TIMEOUT"; then
    exit 0
fi

# todo: add more gateways

# If file cannot be found via gateways then exit
echo " "
echo "File is cannot be found via gateways. Exiting."
exit 1
