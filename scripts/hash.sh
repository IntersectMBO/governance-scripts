#!/bin/bash

# Colors
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

# Usage message
usage() {
    local col=50
    echo -e "${UNDERLINE}${BOLD}Generate BLAKE2b-256 hash of a file${NC}"
    echo -e "\n"
    echo -e "Syntax:${BOLD} $0 ${GREEN}<jsonld-file>${NC}"
    printf "Params: ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "<jsonld-file>" "- Path to the file to hash"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "-h, --help" "- Show this help message and exit"
    exit 1
}

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

# Input file
input_file="$1"

# Check if the file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Anchor file '$input_file' not found!"
    exit 1
fi

# hash of the input file using b2sum
b2sum_hash=$(b2sum -l 256 "$input_file" | awk '{print $1}')

# hash of the input file using cardano-cli
cardano_cli_hash=$(cardano-cli hash anchor-data --file-text "$(realpath "$input_file")")

# Output the result
echo "For anchor file: $input_file"
echo
echo "BLAKE2b-256 hash (using b2sum -l 256):"
echo "$b2sum_hash"
echo
echo "BLAKE2b-256 hash (using cardano-cli hash anchor-data):"
echo "$cardano_cli_hash"