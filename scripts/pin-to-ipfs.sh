#!/bin/bash

######################################################

# Can change if you want!

# Default behavior is to not check if file is discoverable on IPFS
CHECK_TOO="false"

# Pinning services to host the file on IPFS
DEFAULT_HOST_ON_LOCAL_NODE="true"
DEFAULT_HOST_ON_NMKR="true"
DEFAULT_HOST_ON_BLOCKFROST="true"
DEFAULT_HOST_ON_PINATA="true"

# HOST_ON_STORACHA_STORAGE="true"
# https://docs.storacha.network/faq/

######################################################

# check if user has ipfs cli installed
if ! command -v ipfs >/dev/null 2>&1; then
  echo "Error: ipfs cli is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <file> [--check-too] [--no-local] [--no-pinata] [--no-blockfrost] [--no-nmkr]"
    echo "Pin a file to local IPFS node and pin via Blockfrost, NMKR and Pinata. Optionally check if file is already discoverable on IPFS."
    echo "  "
    echo "Options:"
    echo "  <file>                  Path to your file."
    echo "  --check-too             Run a check if file is discoverable on ipfs, only pin if not discoverable (default: $CHECK_TOO)"
    echo "  --no-local              Don't try to pin file on local ipfs node (default: $DEFAULT_HOST_ON_LOCAL_NODE)"
    echo "  --no-pinata             Don't try to pin file on pinata service (default: $DEFAULT_HOST_ON_PINATA)"
    echo "  --no-blockfrost         Don't try to pin file on blockfrost service (default: $DEFAULT_HOST_ON_BLOCKFROST)"
    echo "  --no-nmkr               Don't try to pin file on NMKR service (default: $DEFAULT_HOST_ON_NMKR)"
    exit 1
}

# Initialize variables with defaults
input_path=""
check_discoverable="$CHECK_TOO"
local_host="$DEFAULT_HOST_ON_LOCAL_NODE"
pinata_host="$DEFAULT_HOST_ON_PINATA"
blockfrost_host="$DEFAULT_HOST_ON_BLOCKFROST"
nmkr_host="$DEFAULT_HOST_ON_NMKR"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check-too)
            check_discoverable="true"
            shift
            ;;
        --no-local)
            local_host="false"
            shift
            ;;
        --no-pinata)
            pinata_host="false"
            shift
            ;;
        --no-blockfrost)
            blockfrost_host="false"
            shift
            ;;
        --no-nmkr)
            nmkr_host="false"
            shift
            ;;
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

# If user wants to check if file is discoverable on IPFS
if [ "$check_discoverable" = "true" ]; then
    echo "Checking if file is already hosted on IPFS..."
    echo "Using ./scripts/check-ipfs.sh script to check if file is discoverable on IPFS..."
    ./scripts/check-ipfs.sh "$input_path"
else
    echo "Skipping check of file on ipfs..."
fi

# If file is not accessible then pin it!!
echo " "
echo "File is not hosted on IPFS, so pinning it..."

# Pin on local node
if [ "$local_host" = "true" ]; then
    echo "Pinning file on local IPFS node..."
    if ipfs pin add "$ipfs_cid"; then
        echo "File pinned successfully on local IPFS node."
    else
        echo "Failed to pin file on local IPFS node." >&2
        exit 1
    fi
else
    echo "Skipping pinning on local IPFS node."
fi

# Pin on local node's remote services
# todo
local_node_pinning_services=$(ipfs pin remote service ls)

# Pin on Pinata
echo " "
echo "Pinning file to Pinata..."

if [ "$pinata_host" = "true" ]; then
    # Check for secret environment variables
    # todo, this in a nicer way
    echo "Reading Pinata API key from environment variable..."
    if [ -z "$PINATA_API_KEY" ]; then
        echo "Error: PINATA_API_KEY environment variable is not set." >&2
        exit 1
    fi
    
    echo "Uploading file to Pinata service..."
    response=$(curl -s -X POST "https://uploads.pinata.cloud/v3/files" \
                -H "Authorization: Bearer ${PINATA_API_KEY}" \
                -F "file=@$input_path" \
                -F "network=public" \
            )
    # Check response for errors
    if echo "$response" | grep -q '"errors":'; then
        echo "Error in Pinata response:" >&2
        echo "$response" | jq . >&2
        exit 1
    fi

    echo "Pinata upload successful!"
else
    echo "Skipping pinning on Pinata."
fi

# Pin on Blockfrost
echo " "
echo "Pinning file to Blockfrost..."

if [ "$blockfrost_host" = "true" ]; then
    # Check for secret environment variables
    # todo, this in a nicer way
    echo "Reading Blockfrost API key from environment variable..."
    if [ -z "$BLOCKFROST_API_KEY" ]; then
        echo "Error: BLOCKFROST_API_KEY environment variable is not set." >&2
        exit 1
    fi
    
    echo "Uploading file to Blockfrost service..."
    response=$(curl -s -X POST "https://ipfs.blockfrost.io/api/v0/ipfs/add" \
                -H "project_id: $BLOCKFROST_API_KEY" \
                -F "file=@$input_path" \
            )
    # Check response for errors
    if echo "$response" | grep -q '"errors":'; then
        echo "Error in Blockfrost response:" >&2
        echo "$response" | jq . >&2
        exit 1
    fi

    echo "Blockfrost upload successful!"
else
    echo "Skipping pinning on Blockfrost."
fi

# Pin on NMKR
echo " "
echo "Pinning file to NMKR..."

if [ "$nmkr_host" = "true" ]; then
    # Check for secret environment variables
    # todo, this in a nicer way
    echo "Reading NMKR API key from environment variable..."
    if [ -z "$NMKR_API_KEY" ]; then
        echo "Error: NMKR_API_KEY environment variable is not set." >&2
        exit 1
    fi
    echo "Reading NMKR user id from environment variable..."
    if [ -z "$NMKR_USER_ID" ]; then
        echo "Error: NMKR_USER_ID environment variable is not set." >&2
        exit 1
    fi
    
    # base64 encode the file because NMKR API requires it
    echo "Encoding file to base64..."
    base64_content=$(base64 -i "$input_path")

    echo "Uploading file to NMKR service..."
    response=$(curl -s -X POST "https://studio-api.nmkr.io/v2/UploadToIpfs/${NMKR_USER_ID}" \
        -H 'accept: text/plain' \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer ${NMKR_API_KEY}" \
        -d @- <<EOF
{
    "fileFromBase64": "$base64_content",
    "name": "$(basename "$input_path")",
    "mimetype": "application/json"
}
EOF
    )
    # Check response for errors
    if echo "$response" | grep -q '"errors":'; then
        echo "Error in NMKR response:" >&2
        echo "$response" | jq . >&2
        exit 1
    fi

    echo "NMKR upload successful!"
else
    echo "Skipping pinning on NMKR."
fi

