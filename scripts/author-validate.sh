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
    echo -e "${YELLOW}Usage: $0 <jsonld-file|directory> [--public-key <file|string>]${NC}"
    echo ""
    echo -e "${CYAN}Verify metadata files with author witness using cardano-signer${NC}"
    echo -e "Options:"
    echo -e "  --public-key <file|string>   Specify the Cardano cli public key file path (default: ${YELLOW}Intersect's public key${NC})"
    exit 1
}

is_default_value=false

# Parse command line arguments
input_path=""
options_list=""
public_key_file_path=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --public-key)
            public_key_file_path="$2"
            options_list+=" --public-key"
            shift 2
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

# Check if the key input file exists
if [ ! -f "$input_path" ]; then
    echo -e "${RED}Error: JSON file '${YELLOW}$input_path${RED}' not found!${NC}"
    exit 1
fi

if [ ! -f "$public_key_file_path" ] && [[ $options_list == *"--public-key"* ]]; then
    echo -e "${RED}Error: Public key file '${YELLOW}$public_key_file_path${RED}' not found!${NC}"
    exit 1
fi

author_key=""

echo -e " "
echo -e "${YELLOW}Validating the authors within given governance metadata${NC}"

# Get Intersect author public key
if [ ! -f "$public_key_file_path" ]; then
    echo -e " "
    echo -e "${CYAN}No public key file provided, using Intersect's known public key${NC}"
    echo -e "${CYAN}Fetching Intersect author public key from ${YELLOW}$INTERSECT_AUTHOR_PATH${NC}"
    author_key=$(curl -s "$INTERSECT_AUTHOR_PATH" | jq -r '.publicKey')
    echo -e "Intersect author public key: ${YELLOW}$author_key${NC}"
else
    if [ -f "$public_key_file_path" ]; then
        # If it's a file, read the public key from the file
        author_key=$(cat "$public_key_file_path" | jq -r '.cborHex' | cut -c5-)
    else
        # Otherwise, treat the input as the public key string itself
        author_key="$public_key_file_path"
    fi
    echo -e "Provided author public key: ${YELLOW}$author_key${NC}"
    echo -e " "
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
        echo -e "${BLUE}Checking author public key against expected public key${NC}"
        
        if [ "$file_author_key" == "$author_key" ]; then
            if [ $is_default_value ]; then
                echo -e "${GREEN}Author public key matches Intersect's known public key.${NC}"
            else
                echo -e "${GREEN}Author public key matches provided public key.${NC}"
            fi
        else
            echo -e " "
            if [ $is_default_value ]; then
                echo -e "${RED}Warning: Author public key does NOT match Intersect's known public key.${NC}"
            else
                echo -e "${RED}Warning: Author public key does NOT match the provided key.${NC}"
            fi
            echo -e "Author public key: ${YELLOW}$file_author_key${NC}"
            echo -e "Expected public key: ${YELLOW}$author_key${NC}"
        fi
        echo -e " "
    done
}

show_author_info() {
    local file="$1"
    author_details=$(jq -r '.authors[] | "Author Name: \(.name)\nPublic Key: \(.witness.publicKey)\nSignature: \(.witness.signature)\n"' "$file")
    echo -e "$author_details"
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
        echo -e "${BLUE} Verifying provided signature on file is valid:${NC}"
        verify_author_witness "$file"
        check_if_correct_author "$file"
    done
elif [ -f "$input_path" ]; then
    # Input is a single file
    echo -e "${BLUE}Verifyng provided signature on file is valid:${NC}"
    verify_author_witness "$input_path"
    check_if_correct_author "$input_path"
    
else
    echo -e "${RED}Error: '${YELLOW}$input_path${RED}' is not a valid file or directory.${NC}"
    exit 1
fi