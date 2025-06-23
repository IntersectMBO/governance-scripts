#!/bin/bash

######################################################

# Can change if you want!

# Gateways to check if file is already hosted on IPFS
DEFAULT_GATEWAY_1="https://ipfs.io/ipfs/"
DEFAULT_GATEWAY_2="https://dweb.link/ipfs/"
DEFAULT_GATEWAY_3="https://gateway.pinata.cloud/ipfs/"

######################################################

# check if user has ipfs cli installed
if ! command -v ipfs >/dev/null 2>&1; then
  echo "Error: ipfs cli is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <file>"
    echo "Check if a file is discoverable via free IPFS gateways"
    echo "  "
    echo "Options:"
    echo "  <file>                  Path to your file."
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

# Generate CID from the given file
echo "Generating CID for the file..."

# use ipfs add to generate a CID
# use CIDv1
ipfs_cid=$(ipfs add -Q --cid-version 1 "$input_path")
echo "CID: $ipfs_cid"

check_file_on_gateway() {
    local gateway="$1"
    local cid="$2"
    echo " "
    echo "Checking ${gateway}..."
    if curl --silent --fail "${gateway}${cid}" >/dev/null; then
        echo "File is accessible on IPFS via ${gateway}${cid}"
        return 0
    else
        echo "File not found at: ${gateway}${cid}"
        return 1
    fi
}

# If file can be found via gateways then exit
echo "Checking if file is already hosted on IPFS..."
if check_file_on_gateway "$DEFAULT_GATEWAY_1" "$ipfs_cid"; then
    exit 0
fi
echo " "
if check_file_on_gateway "$DEFAULT_GATEWAY_2" "$ipfs_cid"; then
    exit 0
fi
echo " "
if check_file_on_gateway "$DEFAULT_GATEWAY_3" "$ipfs_cid"; then
    exit 0
fi

echo " "
echo "File is cannot be found via gateways. Exiting."
