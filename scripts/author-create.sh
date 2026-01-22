#!/bin/bash

##################################################
DEFAULT_AUTHOR_NAME="Intersect"
DEFAULT_USE_CIP8="false" # default to false, to the script uses Ed25519
DEFAULT_NEW_FILE="false" # default to false, to the script overwrites the input file
##################################################

# This is just a script for testing purposes.

# This script needs a signing key to be held locally
# most setups should and will not have this.

##################################################

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
UNDERLINE='\033[4m'
BOLD='\033[1m'
GRAY='\033[0;90m'

# Check if cardano-signer is installed
if ! command -v cardano-signer >/dev/null 2>&1; then
  echo -e "${RED}Error: cardano-signer is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Usage message
usage() {
    local col=50
    echo -e "${UNDERLINE}${BOLD}Sign metadata files with author witness using cardano-signer${NC}"
    echo -e "\n"
    echo -e "Syntax:${BOLD} $0 ${GREEN}<jsonld-file|directory> <signing-key>${NC} [${GREEN}--author-name${NC} NAME] [${GREEN}--use-cip8${NC}] [${GREEN}--new-file${NC}]"
    printf "Params: ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "<jsonld-file|directory>" "- Path to JSON-LD file or directory to sign"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "<signing-key>" "- Path to the signing key"
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--author-name NAME]" "- Specify the author name (default: $DEFAULT_AUTHOR_NAME)"
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--use-cip8]" "- Use CIP-8 signing algorithm (default: $DEFAULT_USE_CIP8)"
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--new-file]" "- Create a new file with the signed metadata (default: $DEFAULT_NEW_FILE)"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "-h, --help" "- Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_path=""
input_key=""
author_name="$DEFAULT_AUTHOR_NAME"
use_cip8="$DEFAULT_USE_CIP8"
new_file="$DEFAULT_NEW_FILE"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --author-name)
            author_name="$2"
            shift 2
            ;;
        --use-cip8)
            use_cip8="true"
            shift
            ;;
        --new-file)
            new_file="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_path" ]; then
                input_path="$1"
            elif [ -z "$input_key" ]; then
                input_key="$1"
            else
                echo "Error: Unexpected argument '$1'"
                usage
            fi
            shift
            ;;
    esac
done

# Check for required arguments
if [ -z "$input_path" ] || [ -z "$input_key" ]; then
    echo -e "${RED}Error: Missing required arguments${NC}" >&2
    usage
fi

echo -e " "
echo -e "${YELLOW}Creating author witness for metadata files${NC}"
echo -e "${CYAN}This script signs JSON-LD metadata files using cardano-signer${NC}"

# Check if the key input file exists
if [ ! -f "$input_key" ]; then
    echo -e "${RED}Error: Signing key file '$input_key' not found!${NC}" >&2
    exit 1
fi

echo -e "${CYAN}Using signing key: ${YELLOW}$input_key${NC}"
echo -e "${CYAN}Author name: ${YELLOW}$author_name${NC}"
echo -e "${CYAN}Algorithm: ${YELLOW}$([ "$use_cip8" = "true" ] && echo "CIP-8" || echo "Ed25519")${NC}"
echo -e "${CYAN}Output mode: ${YELLOW}$([ "$new_file" = "true" ] && echo "New file (.authored.jsonld)" || echo "Overwrite original")${NC}"

sign_file() {
    local file="$1"
    local use_cip8="$2"
    local new_file="$3"

    echo -e " "
    echo -e "${CYAN}Signing file: ${YELLOW}$file${NC}"

    if [ $new_file = "true" ]; then
        echo -e "${CYAN}Creating a new file with the signed metadata...${NC}"
        extension=".authored.jsonld" # New file will have .authored.jsonld extension
    else
        echo -e "${CYAN}Overwriting the original file with the signed metadata...${NC}"
        extension=".jsonld"
    fi

    if [ "$use_cip8" = "true" ]; then
        echo -e "${CYAN}Signing with CIP-8 algorithm...${NC}"

        temp_vkey=$(mktemp)
        temp_hash=$(mktemp)

        # Generate verification key from the provided secret key
        cardano-cli key verification-key \
            --signing-key-file "$input_key" \
            --verification-key-file "$temp_vkey"

        # hash the verification key to get the public key hash
        public_key_hash=$(cardano-cli address key-hash --payment-verification-key-file "$temp_vkey")

        # Clean up temporary files
        rm "$temp_vkey"
        rm "$temp_hash"

        echo -e "${CYAN}Using public key hash: ${YELLOW}$public_key_hash${NC}"
        cardano-signer sign --cip100 \
            --data-file "$file" \
            --secret-key "$input_key" \
            --author-name "$author_name" \
            --address "$public_key_hash" \
            --out-file "${file%.jsonld}$extension"
    else
        echo -e "${CYAN}Signing with Ed25519 algorithm...${NC}"
        cardano-signer sign --cip100 \
            --data-file "$file" \
            --secret-key "$input_key" \
            --author-name "$author_name" \
            --out-file "${file%.jsonld}$extension"
    fi
    
    echo -e "${GREEN}Successfully signed: ${YELLOW}${file%.jsonld}$extension${NC}"
}

# Use cardano-signer to sign author metadata

if [ -d "$input_path" ]; then
    # If input is a directory: sign all .jsonld files (including subdirectories)
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
    
    # for each .jsonld file in the directory, sign it
    for file in "${jsonld_files[@]}"; do
        echo -e " "
        # skip for the first file
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
        sign_file "$file" "$use_cip8" "$new_file"
    done
    
    echo -e " "
    echo -e "${GREEN}All files processed successfully!${NC}"
    
elif [ -f "$input_path" ]; then
    # Input is a single file
    echo -e " "
    echo -e "${CYAN}Processing single file: ${YELLOW}$input_path${NC}"
    sign_file "$input_path" "$use_cip8" "$new_file"
    echo -e " "
    echo -e "${GREEN}✓ File processed successfully!${NC}"
else
    echo -e "${RED}Error: '$input_path' is not a valid file or directory.${NC}" >&2
    exit 1
fi