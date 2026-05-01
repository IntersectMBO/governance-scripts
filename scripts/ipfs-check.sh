#!/bin/bash

######################################################

# Can change if you want!

# Timeout for curl requests in seconds
TIMEOUT=5

######################################################

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

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
  print_fail "ipfs cli is not installed or not in your PATH."
  exit 1
fi

# Usage message

usage() {
    printf '%s%sCheck if a file or IPFS CIDv1 is discoverable via free IPFS gateways%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<file|CID>%s\n' "$BOLD" "$0" "$GREEN" "$NC"
    print_usage_option "<file|CID>"  "Path to your file or IPFS CIDv1"
    print_usage_option "-h, --help"  "Show this help message and exit"
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
    print_fail "No file or CID specified"
    usage
fi

print_banner "Checking IPFS file availability via public gateways"
print_info "This script checks if a file or CID is accessible through free IPFS gateways"

# Check if the input is a file or CID
file="false"

if [[ -f "$input_path" ]]; then
    file="true"
    print_info "Input is a file: $(fmt_path "$input_path")"
elif [[ "$input_path" =~ ^[a-zA-Z0-9]{59,}$ ]]; then
    print_info "Input is a CID: ${YELLOW}${input_path}${NC}"
else
    print_fail "Invalid input: $(fmt_path "$input_path") is not a valid file or CID"
    usage
fi

# Generate CID from the given if needed

ipfs_cid=" "

if [ "$file" = "false" ]; then
    ipfs_cid="$input_path"
else
    print_info "Generating CID for the file..."
    ipfs_cid=$(ipfs add -Q --cid-version 1 "$input_path")
fi

print_info "CID: ${YELLOW}${ipfs_cid}${NC}"

check_file_via_gateway() {
    local gateway="$1"
    local cid="$2"
    local timeout="$3"
    print_section "Checking $gateway"
    if curl --silent --fail --max-time $timeout "${gateway}${cid}" >/dev/null; then
        print_pass "File accessible via ${gateway}${cid}"
        return 0
    else
        print_fail "File not found at: ${gateway}${cid}"
        return 1
    fi
}

# If file can be found via gateways then exit
if check_file_via_gateway "$DEFAULT_GATEWAY_1" "$ipfs_cid" "$TIMEOUT"; then
    print_pass "File found and accessible via IPFS gateways"
    exit 0
fi
if check_file_via_gateway "$DEFAULT_GATEWAY_2" "$ipfs_cid" "$TIMEOUT"; then
    print_pass "File found and accessible via IPFS gateways"
    exit 0
fi

# todo: add more gateways

# If file cannot be found via gateways then exit
print_fail "File cannot be found via any IPFS gateways."
exit 1
