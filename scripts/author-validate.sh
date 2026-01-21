#!/bin/bash

######################################################
# using permalink to reduce likelihood of breakage, or ability for it to change
INTERSECT_AUTHOR_PATH="https://raw.githubusercontent.com/IntersectMBO/governance-actions/b1c5603fb306623e0261c234312eb7e011ac3d38/intersect-author.json"
CHECK_INTERSECT_AUTHOR="false"
######################################################

set -euo pipefail

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
    echo -e "${YELLOW}Usage: $0 <jsonld-file|directory> [--check-intersect]${NC}"
    echo ""
    echo -e "${CYAN}Verify metadata files with author witness using cardano-signer${NC}"
    echo -e "Options:"
    echo -e "  --check-intersect  Compares author's to Intersect's known pub author key"
    exit 1
}

# Check correct number of arguments
if [ "$#" -lt 1 ]; then
    usage
fi

# Parse command line arguments
input_path=""
check_intersect="$CHECK_INTERSECT_AUTHOR"

while [[ $# -gt 0 ]]; do
    case $1 in
        --check-intersect)
            check_intersect="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_path" ]; then
                input_path="$1"
                shift
            else
                echo -e "${RED}Error: Unknown argument: $1${NC}" >&2
                usage
            fi
            ;;
    esac
done

# Check if the metadata input file exists
if [ ! -f "$input_path" ]; then
    echo -e "${RED}Error: JSON file '${YELLOW}$input_path${RED}' not found!${NC}"
    exit 1
fi

echo -e " "
echo -e "${YELLOW}Validating the authors within given governance metadata${NC}"

# Get Intersect author public key
if [ "$check_intersect" == "true" ]; then
    echo -e " "
    echo -e "${CYAN}Comparing author's public key to Intersect's known public key${NC}"
    echo -e "${CYAN}Fetching Intersect author public key from ${YELLOW}$INTERSECT_AUTHOR_PATH${NC}"
    author_key=$(curl -s "$INTERSECT_AUTHOR_PATH" | jq -r '.publicKey')
    echo -e "Intersect author public key: ${YELLOW}$author_key${NC}"
else
    echo -e " "
    echo -e "${CYAN}Not comparing author's against Intersect's known public key${NC}"
fi

# Use cardano-signer to verify author witnesses
# https://github.com/gitmachtl/cardano-signer?tab=readme-ov-file#verify-governance-metadata-and-the-authors-signatures
verify_author_witness() {
    local file="$1"
    local raw_output

    raw_output=$(cardano-signer verify --cip100 \
        --data-file "$file" \
        --json-extended)

    # read exit code of last command
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: cardano-signer command failed while verifying file '${YELLOW}$file${RED}'.${NC}" >&2
        exit 1
    fi
    
    local output
    output=$(echo "$raw_output" | jq '{result, errorMsg, authors, canonizedHash, fileHash}')

    echo -e "${CYAN}Result: ${NC}$(echo "$output" | jq -r '.result')"
    echo -e "${CYAN}Error Messages: ${NC}$(echo "$output" | jq -r '.errorMsg')"
    echo -e "${CYAN}Authors: ${NC}$(echo "$output" | jq -r '.authors')"
    echo -e "${CYAN}Canonized Hash: ${NC}$(echo "$output" | jq -r '.canonizedHash')"
    echo -e "${CYAN}File Hash: ${NC}$(echo "$output" | jq -r '.fileHash')"

    local result
    result=$(echo "$output" | jq -r '.result')
    if [ "$result" != "true" ]; then
        echo -e "${RED}Error: Verification failed with result: ${YELLOW}$result${NC}" >&2
        exit 1
    fi
}

# Give the user a warning if the author isn't Intersect
check_if_correct_author() {
    local file="$1"
    author_count=$(jq '.authors | length' "$file")
    
    # Iterate over all author pubkeys present
    for i in $(seq 0 $(($author_count - 1))); do
        file_author_key=$(jq -r ".authors[$i].witness.publicKey" "$file")
        echo " "
        echo -e "${CYAN}Checking author index $i public key against Intersect's keys${NC}"
        
        # if author's public key matches Intersect's public key
        if [ "$file_author_key" == "$author_key" ]; then
            # and if author name is intersect
            if [ "$(jq -r ".authors[$i].name" "$file")" == "Intersect" ]; then
                echo -e "${GREEN}Author pub key and name is correctly set to 'Intersect'.${NC}"
            else
                echo -e "${RED}Warning: Author name is NOT set to 'Intersect' but public key matches Intersect's key.${NC}"
                echo -e "Author name: ${YELLOW}$(jq -r ".authors[$i].name" "$file")${NC}"
                echo -e "Author public key: ${YELLOW}$file_author_key${NC}"
            fi
            
        else
            echo -e "${RED}Warning: Author public key is not Intersect's key.${NC}"
            echo -e "Author name: ${YELLOW}$(jq -r ".authors[$i].name" "$file")${NC}"
            echo -e "Author public key: ${YELLOW}$file_author_key${NC}"
        fi
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
        echo -e "${CYAN} Verifying provided signature on file is valid:${NC}"
        verify_author_witness "$file"
        if [ "$check_intersect" == "true" ]; then
            check_if_correct_author "$file"
        fi
    done
elif [ -f "$input_path" ]; then
    # Input is a single file
    echo -e "${CYAN}Verifying provided signature on file is valid:${NC}"
    verify_author_witness "$input_path"
    if [ "$check_intersect" == "true" ]; then
        check_if_correct_author "$input_path"
    fi
    
else
    echo -e "${RED}Error: '${YELLOW}$input_path${RED}' is not a valid file or directory.${NC}"
    exit 1
fi