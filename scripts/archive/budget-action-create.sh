#!/bin/bash

##################################################

# some options maybe

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

# Check if cardano-cli is installed
if ! command -v cardano-cli >/dev/null 2>&1; then
  echo "Error: cardano-cli is not installed or not in your PATH." >&2
  exit 1
fi

# Check if ipfs cli is installed
if ! command -v ipfs >/dev/null 2>&1; then
  echo "Error: ipfs cli is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <directory> --deposit-return-addr <stake address> --withdrawal-addr <stake address> [--no-ipfs-pin]"
    echo "Create treasury withdrawal governance actions from a directory of JSONLD metadata files and host the metadata on ipfs."
    echo "Options:"
    echo "  <directory>                              Path to directory containing .jsonld files"
    echo "  --deposit-return-addr <stake address>    Check that metadata deposit return address matches provided one (Bech32) [REQUIRED]"
    echo "  --withdrawal-addr <stake address>        Check that metadata withdrawal address matches provided one (Bech32) [REQUIRED]"
    echo "  --no-ipfs-pin                            Skip IPFS pinning step"
    echo "  -h, --help                               Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_path=""
deposit_return_address_input=""
withdrawal_address_input=""
skip_ipfs_pin="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --deposit-return-addr)
            if [ -n "${2:-}" ]; then
                deposit_return_address_input="$2"
                shift 2
            else
                echo -e "${RED}Error: --deposit-return-addr requires a value${NC}" >&2
                usage
            fi
            ;;
        --withdrawal-addr)
            if [ -n "${2:-}" ]; then
                withdrawal_address_input="$2"
                shift 2
            else
                echo -e "${RED}Error: --withdrawal-addr requires a value${NC}" >&2
                usage
            fi
            ;;
        --no-ipfs-pin)
            skip_ipfs_pin="true"
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
    echo -e "${RED}Error: No directory specified${NC}" >&2
    usage
fi

# Check if required parameters are provided
if [ -z "$deposit_return_address_input" ]; then
    echo -e "${RED}Error: --deposit-return-addr is required${NC}" >&2
    usage
fi

if [ -z "$withdrawal_address_input" ]; then
    echo -e "${RED}Error: --withdrawal-addr is required${NC}" >&2
    usage
fi

# Check if input is a directory
if [ ! -d "$input_path" ]; then
    echo -e "${RED}Error: Input is not a valid directory: ${YELLOW}$input_path${NC}" >&2
    exit 1
fi

echo -e " "
echo -e "${YELLOW}Budget Action Creation Service${NC}"
echo -e "${CYAN}This script processes JSONLD files to create treasury withdrawal governance actions${NC}"
echo -e "${CYAN}It will host files on IPFS and create governance actions for each file${NC}"

# Get all .jsonld files in the directory and subdirectories
jsonld_files=()
while IFS= read -r -d '' file; do
    jsonld_files+=("$file")
done < <(find "$input_path" -type f -name "*.jsonld" -print0)

# Check if any .jsonld files were found
if [ ${#jsonld_files[@]} -eq 0 ]; then
    echo -e " "
    echo -e "${RED}Error: No .jsonld files found in directory (including subdirectories): ${YELLOW}$input_path${NC}" >&2
    exit 1
fi

echo -e " "
echo -e "${CYAN}Found ${YELLOW}${#jsonld_files[@]}${NC}${CYAN} .jsonld files to process${NC}"

for file in "${jsonld_files[@]}"; do
    # Ask user if they want to continue with the next file
    # Skip for the first file
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

    if [ -f "$file" ]; then
        echo -e " "
        echo -e "${CYAN}Processing file: ${YELLOW}$file${NC}"
        echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

        if [ "$skip_ipfs_pin" = "false" ]; then
            echo -e " "
            echo -e "${CYAN}Hosting file on IPFS using ./ipfs-pin.sh${NC}"
            ./scripts/ipfs-pin.sh "$file"
            echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        else
            echo -e " "
            echo -e "${YELLOW}Skipping IPFS pinning step${NC}"
            echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        fi

        echo -e " "
        echo -e "${CYAN}Creating treasury governance action using ./action-create-tw.sh${NC}"

        ./scripts/action-create-tw.sh --deposit-return-addr "$deposit_return_address_input" \
                                      --withdrawal-addr "$withdrawal_address_input" \
                                      "$file"
        
        echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        echo -e " "
        echo -e "${GREEN}Successfully processed: ${YELLOW}$file${NC}"
        echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

    else
        echo -e " "
        echo -e "${RED}Error: file is not a valid file: ${YELLOW}$file${NC}" >&2
        exit 1
    fi
done

echo -e " "
echo -e "${GREEN}All files processed successfully!${NC}"
echo -e "${CYAN}Treasury withdrawal governance actions have been created for all JSONLD files${NC}"
