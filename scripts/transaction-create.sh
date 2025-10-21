#!/bin/bash

##################################################

# Default configuration values

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

# Usage message

usage() {
    echo "Usage: $0 <action-file-path> [--payment-addr <address>] [--deposit-return-addr <stake address>]"
    echo "Options:"
    echo "  <action-file-path>                               Path to the governance action file to create the transaction for"
    echo "  --payment-addr <address>                         Specify the payment address (Bech32)"
    echo "  --deposit-return-addr <stake address>            Check that metadata deposit return address matches provided one (Bech32)"
    echo "  -h, --help                                       Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_action_file=""

# Optional variables
payment_address_input=""
deposit_return_address_input=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --payment-addr)
            if [ -n "${2:-}" ]; then
                payment_address_input="$2"
                shift 2
            else
                echo -e "${RED}Error: --payment-addr requires a value${NC}" >&2
                usage
            fi
            ;;
        --deposit-return-addr)
            if [ -n "${2:-}" ]; then
                deposit_return_address_input="$3"
                shift 2
            else
                echo -e "${RED}Error: --deposit-return-addr requires a value${NC}" >&2
                usage
            fi
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_action_file" ]; then
                input_action_file="$1"
            else
                echo -e "${RED}Error: Input file already specified. Unexpected argument: $1${NC}" >&2
                usage
            fi
            shift
            ;;
    esac
done


echo -e " "
echo -e "${YELLOW}Creating a treasury withdrawal governance action from a given metadata file${NC}"
echo -e "${CYAN}This script assumes compliance Intersect's treasury withdrawal action schema${NC}"
echo -e "${CYAN}This script assumes that CARDANO_NODE_SOCKET_PATH, CARDANO_NODE_NETWORK_ID and IPFS_GATEWAY_URI are set${NC}"

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
    protocol_magic="testnet"
fi

# checks to do:

echo -e " "
echo -e "${CYAN}Performing checks${NC}"

# check that payment address is right network
# check that payment address has enough funds to cover deposit + fees

# check that deposit return address is right network
# check that deposit return address matches metadata if provided

echo -e " "
echo -e "${GREEN}Validation Checks passed!${NC}"

# Give the user all the info and make them confirm
# give user the action type, title, deposit amount, deposit return address, withdrawal address, payment address

# main logic
echo -e " "
echo -e "${CYAN}Processing action file: ${YELLOW}$input_action_file${NC}"

# Query payment wallet UTxOs
echo -e "${CYAN}Querying UTxOs for payment address: ${YELLOW}$PAYMENT_ADDR${NC}"

payment_utxos=$(cardano-cli conway query utxo \
  --address "$PAYMENT_ADDR" \
  --out-file  /dev/stdout)

# Allow user to select UTxOs to use for the transaction
selected_utxos=()
while IFS= read -r utxo; do
    echo -e "${YELLOW}Found UTxO: $utxo${NC}"
    read -p "Include this UTxO in the transaction? (y/n) " include_utxo
    if [[ "$include_utxo" == "y" ]]; then
        selected_utxos+=("$utxo")
    fi
done <<< "$payment_utxos"

cardano-cli conway transaction build \
 --tx-in "${selected_utxos[@]}" \
 --change-address "$PAYMENT_ADDR" \
 --proposal-file $input_action_file \
 --out-file $input_action_file.unsigned