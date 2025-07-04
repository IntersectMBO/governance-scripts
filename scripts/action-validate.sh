#!/bin/bash

##################################################

# Default configuration values
WITHDRAW_TO_SCRIPT="false"

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
    echo "Usage: $0 <jsonld-file> --deposit-return-addr <stake address> --withdrawal-addr <stake address> --withdrawal-amount <number>"
    echo "Options:"
    echo "  <jsonld-file>                                    Path to the JSON-LD metadata file"
    echo "  --deposit-return-addr <stake address>            Check that metadata deposit return address matches provided one (Bech32)"
    echo "  --withdrawal-addr <stake address>                Check that metadata withdrawal address matches provided one (Bech32)"
    echo "  --withdrawal-amount <number>                     Check that metadata withdrawal amount matches"
    echo "  -h, --help                                       Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_file=""

# Optional variables
withdraw_to_script="$WITHDRAW_TO_SCRIPT"
deposit_return_address_input=""
withdrawal_address_input=""

# todo check all the inputs work

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --withdraw-to-script)
            withdraw_to_script="true"
            shift
            ;;    
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
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_file" ]; then
                input_file="$1"
            else
                echo -e "${RED}Error: Input file already specified. Unexpected argument: $1${NC}" >&2
                usage
            fi
            shift
            ;;
    esac
done

# If no input file provided, show usage
if [ -z "$input_file" ]; then
    echo -e "${RED}Error: No input file specified${NC}" >&2
    usage
fi

# Check if input file exists
if [ ! -f "$input_file" ]; then
    echo -e "${RED}Error: Input file not found: $input_file${NC}" >&2
    exit 1
fi

echo -e " "
echo -e "${YELLOW}Creating a treasury withdrawal governance action from a given metadata file${NC}"
echo -e "${CYAN}This script assumes compliance Intersect's treasury withdrawal action schema${NC}"

# Exit if socket path is not set
if [ -z "$CARDANO_NODE_SOCKET_PATH" ]; then
    echo "Error: Cardano node $CARDANO_NODE_SOCKET_PATH environment variable is not set." >&2
    exit 1
fi

# Exit if network id is not set
if [ -z "$CARDANO_NODE_NETWORK_ID" ]; then
    echo "Error: Cardano node $CARDANO_NODE_NETWORK_ID environment variable is not set." >&2
fi

# Get if mainnet or testnet
if [ "$CARDANO_NODE_NETWORK_ID" = "764824073" ] || [ "$CARDANO_NODE_NETWORK_ID" = "mainnet" ]; then
    echo -e "${YELLOW}Local node is using mainnet${NC}"
    protocol_magic="mainnet"
else
    echo -e "${YELLOW}Local node is using a testnet${NC}"
    protocol_magic="$CARDANO_NODE_NETWORK_ID"
fi

# Open the provided metadata file

# Do some basic validation checks on metadata
echo -e " "
echo -e "${CYAN}Doing some basic validation and checks on metadata${NC}"

