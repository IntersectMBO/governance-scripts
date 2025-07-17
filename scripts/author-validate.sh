#!/bin/bash

######################################################
# using permalink to reduce likelihood of breakage, or ability for it to change
INTERSECT_AUTHOR_PATH="https://raw.githubusercontent.com/IntersectMBO/governance-actions/b1c5603fb306623e0261c234312eb7e011ac3d38/intersect-author.json"
######################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BRIGHTWHITE='\033[0;37;1m'
NC='\033[0m'

# Check if cardano-signer is installed
if ! command -v cardano-signer >/dev/null 2>&1; then
  echo -e "${RED}Error: cardano-signer is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <jsonld-file|directory>"
    exit 1
}

# Check correct number of arguments
if [ "$#" -lt 1 ]; then
    usage
fi

input_path="$1"

# Check if the key input file exists
if [ ! -f "$input_path" ]; then
    echo -e "${RED}Error: JSON file '${YELLOW}$input_path${RED}' not found!${NC}"
    exit 1
fi

# Get Intersect author public key
echo -e "${CYAN}Fetching Intersect author public key from ${YELLOW}$INTERSECT_AUTHOR_PATH${NC}"
intersect_author_key=$(curl -s "$INTERSECT_AUTHOR_PATH" | jq -r '.publicKey')
echo -e " "

# Use cardano-signer to verify author witnesses
# https://github.com/gitmachtl/cardano-signer?tab=readme-ov-file#verify-governance-metadata-and-the-authors-signatures
verify_author_witness() {
    local file="$1"
    local output
    output=$(cardano-signer verify --cip100 \
        --data-file "$file" \
        --json-extended | jq '{workMode, result, errorMsg, authors, canonizedHash, fileHash}')
    
    echo "$output"
    
    local result
    result=$(echo "$output" | jq -r '.result')
    if [ "$result" != "true" ]; then
        echo -e "${RED}Error: Verification failed with result: ${YELLOW}$result${NC}" >&2
        exit 1
    fi
}

# Give the user a warning if the author isn't Intersect
check_if_intersect_author() {
    local file="$1"
    author_count=$(jq '.authors | length' "$file")
    
    # Iterate over all author pubkeys present
    for i in $(seq 0 $(($author_count - 1))); do
        author_key=$(jq -r ".authors[$i].witness.publicKey" "$file")
        
        if [ "$author_key" == "$intersect_author_key" ]; then
            echo -e "${GREEN}Author public key matches Intersect's known public key.${NC}"
        else
            echo -e " "
            echo -e "${RED}Warning: Author public key does NOT match Intersect's known public key.${NC}"
            echo -e "Author public key: ${YELLOW}$author_key${NC}"
            echo -e "Intersect's known public key: ${YELLOW}$intersect_author_key${NC}"
        fi
        echo -e " "
    done
}

if [ -d "$input_path" ]; then
    # If input is a directory: verify all .jsonld files
    shopt -s nullglob
    jsonld_files=("$input_path"/*.jsonld)
    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        echo -e "${RED}Error: No .jsonld files found in directory '${YELLOW}$input_path${RED}'.${NC}"
        exit 1
    fi
    # for each .jsonld file in the directory, go over it
    for file in "${jsonld_files[@]}"; do
        verify_author_witness "$file"
        check_if_intersect_author "$file"
    done
elif [ -f "$input_path" ]; then
    # Input is a single file
    verify_author_witness "$input_path"
    check_if_intersect_author "$input_path"
else
    echo -e "${RED}Error: '${YELLOW}$input_path${RED}' is not a valid file or directory.${NC}"
    exit 1
fi