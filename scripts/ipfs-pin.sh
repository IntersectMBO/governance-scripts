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

# check if user has ipfs cli installed
if ! command -v ipfs >/dev/null 2>&1; then
  echo -e "${RED}Error: ipfs cli is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Usage message
usage() {
    echo -e "${YELLOW}Usage: $0 <file|directory> [--check-too] [--no-local] [--no-pinata] [--no-blockfrost] [--no-nmkr]${NC}"
    echo -e "${CYAN}Pin a file or directory of .jsonld files to local IPFS node and pin via Blockfrost, NMKR and Pinata.${NC}"
    echo -e "${CYAN}Optionally check if file is already discoverable on IPFS.${NC}"
    echo -e " "
    echo -e "Options:"
    echo -e "  <file|directory>        Path to your file or directory containing .jsonld files."
    echo -e "  --check-too             Run a check if file is discoverable on ipfs, only pin if not discoverable (default: ${YELLOW}$CHECK_TOO${NC})"
    echo -e "  --no-local              Don't try to pin file on local ipfs node (default: ${YELLOW}$DEFAULT_HOST_ON_LOCAL_NODE${NC})"
    echo -e "  --no-pinata             Don't try to pin file on pinata service (default: ${YELLOW}$DEFAULT_HOST_ON_PINATA${NC})"
    echo -e "  --no-blockfrost         Don't try to pin file on blockfrost service (default: ${YELLOW}$DEFAULT_HOST_ON_BLOCKFROST${NC})"
    echo -e "  --no-nmkr               Don't try to pin file on NMKR service (default: ${YELLOW}$DEFAULT_HOST_ON_NMKR${NC})"
    echo -e "  -h, --help              Show this help message and exit"
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

# If no input path provided, show usage
if [ -z "$input_path" ]; then
    echo -e "${RED}Error: No file or directory specified${NC}" >&2
    usage
fi

echo -e " "
echo -e "${YELLOW}IPFS File Pinning Service${NC}"
echo -e "${CYAN}This script pins files to IPFS using multiple pinning services${NC}"

# Function to pin a single file
pin_single_file() {
    local file="$1"
    
    echo -e " "
    echo -e "${CYAN}Processing file: ${YELLOW}$file${NC}"
    
    # Generate CID from the given file
    echo -e "${CYAN}Generating CID for the file...${NC}"
    
    # use ipfs add to generate a CID
    # use CIDv1
    ipfs_cid=$(ipfs add -Q --cid-version 1 "$file")
    echo -e "CID: ${YELLOW}$ipfs_cid${NC}"
    
    # If user wants to check if file is discoverable on IPFS
    if [ "$check_discoverable" = "true" ]; then
        echo -e "${CYAN}Using ./scripts/ipfs-check.sh script to check if file is discoverable on IPFS...${NC}"
        # check if file is discoverable on IPFS
        if ! ./scripts/ipfs-check.sh "$file"; then
            echo -e "${YELLOW}File is not discoverable on IPFS. Proceeding to pin it.${NC}"
        else
            echo -e "${GREEN}File is already discoverable on IPFS. No need to pin it.${NC}"
            return 0
        fi
    else
        echo -e "${CYAN}Skipping check of file on ipfs...${NC}"
    fi
    
    echo -e " "
    echo -e "${CYAN}File is not hosted on IPFS, so pinning it...${NC}"
    
    # Pin on local node
    if [ "$local_host" = "true" ]; then
        echo -e " "
        echo -e "${CYAN}Pinning file on local IPFS node...${NC}"
        if ipfs pin add "$ipfs_cid"; then
            echo -e "${GREEN}File pinned successfully on local IPFS node.${NC}"
        else
            echo -e "${RED}Failed to pin file on local IPFS node.${NC}" >&2
            return 1
        fi
    else
        echo -e "${YELLOW}Skipping pinning on local IPFS node.${NC}"
    fi
    
    # Pin on Pinata
    if [ "$pinata_host" = "true" ]; then
        echo -e " "
        echo -e "${CYAN}Pinning file to Pinata...${NC}"
        
        # Check for secret environment variables
        echo -e "${CYAN}Reading Pinata API key from environment variable...${NC}"
        if [ -z "$PINATA_API_KEY" ]; then
            echo -e "${RED}Error: PINATA_API_KEY environment variable is not set.${NC}" >&2
            return 1
        fi
        
        echo -e "${CYAN}Uploading file to Pinata service...${NC}"
        response=$(curl -s -X POST "https://uploads.pinata.cloud/v3/files" \
                    -H "Authorization: Bearer ${PINATA_API_KEY}" \
                    -F "file=@$file" \
                    -F "network=public" \
                )
        # Check response for errors
        if echo "$response" | grep -q '"errors":'; then
            echo -e "${RED}Error in Pinata response:${NC}" >&2
            echo "$response" | jq . >&2
            return 1
        fi
        
        echo -e "${GREEN}Pinata upload successful!${NC}"
    else
        echo -e "${YELLOW}Skipping pinning on Pinata.${NC}"
    fi
    
    # Pin on Blockfrost
    if [ "$blockfrost_host" = "true" ]; then
        echo -e " "
        echo -e "${CYAN}Pinning file to Blockfrost...${NC}"
        
        # Check for secret environment variables
        echo -e "${CYAN}Reading Blockfrost API key from environment variable...${NC}"
        if [ -z "$BLOCKFROST_API_KEY" ]; then
            echo -e "${RED}Error: BLOCKFROST_API_KEY environment variable is not set.${NC}" >&2
            return 1
        fi
        
        echo -e "${CYAN}Uploading file to Blockfrost service...${NC}"
        response=$(curl -s -X POST "https://ipfs.blockfrost.io/api/v0/ipfs/add" \
                    -H "project_id: $BLOCKFROST_API_KEY" \
                    -F "file=@$file" \
                )
        # Check response for errors
        if echo "$response" | grep -q '"errors":'; then
            echo -e "${RED}Error in Blockfrost response:${NC}" >&2
            echo "$response" | jq . >&2
            return 1
        fi
        
        echo -e "${GREEN}Blockfrost upload successful!${NC}"
    else
        echo -e "${YELLOW}Skipping pinning on Blockfrost.${NC}"
    fi
    
    # Pin on NMKR
    if [ "$nmkr_host" = "true" ]; then
        echo -e " "
        echo -e "${CYAN}Pinning file to NMKR...${NC}"
        
        # Check for secret environment variables
        echo -e "${CYAN}Reading NMKR API key from environment variable...${NC}"
        if [ -z "$NMKR_API_KEY" ]; then
            echo -e "${RED}Error: NMKR_API_KEY environment variable is not set.${NC}" >&2
            return 1
        fi
        echo -e "${CYAN}Reading NMKR user id from environment variable...${NC}"
        if [ -z "$NMKR_USER_ID" ]; then
            echo -e "${RED}Error: NMKR_USER_ID environment variable is not set.${NC}" >&2
            return 1
        fi
        
        # base64 encode the file because NMKR API requires it
        echo -e "${CYAN}Encoding file to base64...${NC}"
        base64_content=$(base64 -i "$file")
        
        echo -e "${CYAN}Uploading file to NMKR service...${NC}"
        response=$(curl -s -X POST "https://studio-api.nmkr.io/v2/UploadToIpfs/${NMKR_USER_ID}" \
            -H 'accept: text/plain' \
            -H 'Content-Type: application/json' \
            -H "Authorization: Bearer ${NMKR_API_KEY}" \
            -d @- <<EOF
{
    "fileFromBase64": "$base64_content",
    "name": "$(basename "$file")",
    "mimetype": "application/json"
}
EOF
        )
        # Check response for errors
        if echo "$response" | grep -q '"errors":'; then
            echo -e "${RED}Error in NMKR response:${NC}" >&2
            echo "$response" | jq . >&2
            return 1
        fi
        
        echo -e "${GREEN}NMKR upload successful!${NC}"
    else
        echo -e "${YELLOW}Skipping pinning on NMKR.${NC}"
    fi
    
    echo -e " "
    echo -e "${GREEN}File pinning completed: ${YELLOW}$file${NC}"
}

# Main processing logic
if [ -d "$input_path" ]; then
    # If input is a directory: pin all .jsonld files (including subdirectories)
    echo -e " "
    echo -e "${CYAN}Processing directory: ${YELLOW}$input_path${NC}"
    
    # Get all .jsonld files in the directory and subdirectories
    jsonld_files=()
    while IFS= read -r -d '' file; do
        jsonld_files+=("$file")
    done < <(find "$input_path" -type f -name "*.jsonld" -print0)
    
    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        echo -e "${RED}Error: No .jsonld files found in directory (including subdirectories): ${YELLOW}$input_path${NC}" >&2
        exit 1
    fi
    
    echo -e "${CYAN}Found ${YELLOW}${#jsonld_files[@]}${NC}${CYAN} .jsonld files to process${NC}"
    
    # for each .jsonld file in the directory, pin it
    for file in "${jsonld_files[@]}"; do
        # ask user if they want to continue with the next file
        # skip for the first file
        if [ "$file" != "${jsonld_files[0]}" ]; then
            echo -e " "
            echo -e "${CYAN}The next file is: ${YELLOW}$file${NC}"
            read -p "Do you want to continue with the next file? (y/n): " choice
            case "$choice" in
                y|Y ) echo -e "${GREEN}Continuing with the next file...${NC}";;
                n|N ) echo -e "${YELLOW}Exiting...${NC}"; exit 0;;
                * ) echo -e "${RED}Invalid choice, exiting...${NC}"; exit 1;;
            esac
        fi
        pin_single_file "$file"
    done
    
    echo -e " "
    echo -e "${GREEN}All files processed successfully!${NC}"
    
elif [ -f "$input_path" ]; then
    # Input is a single file
    echo -e " "
    echo -e "${CYAN}Processing single file: ${YELLOW}$input_path${NC}"
    pin_single_file "$input_path"
    echo -e " "
    echo -e "${GREEN}File processed successfully!${NC}"
else
    echo -e "${RED}Error: '$input_path' is not a valid file or directory.${NC}" >&2
    exit 1
fi

