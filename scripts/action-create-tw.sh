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

# Check if ipfs cli is installed
if ! command -v ipfs >/dev/null 2>&1; then
  echo "Error: ipfs cli is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message

usage() {
    echo "Usage: $0 <jsonld-file|directory> [--deposit-return-addr <stake address>] [--withdrawal-addr <stake address>]"
    echo "Options:"
    echo "  --deposit-return-addr <stake address>         Check that metadata deposit return address matches provided one (Bech32)"
    echo "  --withdrawal-addr <stake address>             Check that metadata withdrawal address matches provided one (Bech32)"
    exit 1
}

# Initialize variables with defaults
input_file=""

# Optional variables
deposit_return_address_input=""
withdrawal_address_input=""

# todo check all the inputs work

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

echo -e "${YELLOW}Creating a treasury withdrawal governance action from a given metadata file${NC}"
echo -e "${CYAN}This script assumes compliance Intersect's treasury withdrawal action schema${NC}"
echo -e " "
echo -e "${CYAN}This script assumes that CARDANO_NODE_SOCKET_PATH is set${NC}"
echo -e "${CYAN}This script assumes that CARDANO_NODE_NETWORK_ID is set${NC}"

# Exit if socket path is not set
if [ -z "$CARDANO_NODE_SOCKET_PATH" ]; then
    echo "Error: Cardano node $CARDANO_NODE_SOCKET_PATH environment variable is not set." >&2
    exit 1
fi

# Exit if network id is not set
if [ -z "$CARDANO_NODE_NETWORK_ID" ]; then
    echo "Error: Cardano node $CARDANO_NODE_NETWORK_ID environment variable is not set." >&2
fi

# Open the provided metadata file

# Do some basic validation checks on metadata
echo -e " "
echo -e "${CYAN}Doing some basic validation and checks on metadata${NC}"

# Function to check if jq query returned null or empty
check_field() {
    local field_name="$1"
    local field_value="$2"
    
    if [ -z "$field_value" ] || [ "$field_value" = "null" ]; then
        echo -e "${RED}Error: Required field '$field_name' not found in metadata${NC}" >&2
        exit 1
    fi
}

# Extract and validate required fields
title=$(jq -r '.body.title' "$input_file")
check_field "title" "$title"

ga_type=$(jq -r '.body.onChain.governanceActionType' "$input_file")
check_field "governanceActionType" "$ga_type"

deposit_return=$(jq -r '.body.onChain.depositReturnAddress' "$input_file")
check_field "depositReturnAddress" "$deposit_return"

# todo: support multiple withdrawals
withdrawal_address=$(jq -r '.body.onChain.withdrawals[0].withdrawalAddress' "$input_file")
check_field "withdrawalAddress" "$withdrawal_address"
withdrawal_amount=$(jq -r '.body.onChain.withdrawals[0].withdrawalAmount' "$input_file")
check_field "withdrawalAmount" "$withdrawal_amount"

if [ "$ga_type" = "treasuryWithdrawals" ]; then
    echo "Metadata has correct governanceActionType"
else
    echo "Metadata does not have the correct governanceActionType"
    echo "Expected: treasuryWithdrawals found: $ga_type"
    exit 1
fi

# todo: add check that the deposit address is the same network as the connected and provided testnet_magic

# if return address passed in check against metadata
if [ ! -z "$deposit_return_address_input" ]; then
    echo "Deposit return address provided"
    echo "Comparing provided address to metadata"
    if [ "$deposit_return_address_input" = "$deposit_return" ]; then
        echo -e "${GREEN}Metadata has expected deposit return address${NC}"
    else
        echo -e "${RED}Metadata does not have expected deposit return address${NC}"
        exit 1
    fi
fi

# check if withdrawal address is provided
if [ ! -z "$withdrawal_address_input" ]; then
    echo "Withdrawal address provided"
    echo "Comparing provided address to metadata"
    if [ "$withdrawal_address_input" = "$withdrawal_address" ]; then
        echo -e "${GREEN}Metadata has expected withdrawal address${NC}"
    else
        echo -e "${RED}Metadata does not have expected withdrawal address${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Automatic validations passed${NC}"
echo -e " "
echo -e "${CYAN}Computing details${NC}"

# compute if provided addresses are script-based or key-based
# we should warn the user if they are key-based

# Compute the hash and IPFS URI
file_hash=$(b2sum -l 256 "$input_file" | awk '{print $1}')
echo -e "Metadata file hash: ${YELLOW}$file_hash${NC}"

ipfs_cid=$(ipfs add -Q --cid-version 1 "$input_file")
echo -e "IPFS URI: ${YELLOW}ipfs://$ipfs_cid${NC}"

# Make user manually confirm the choices
echo -e " "
echo -e "${CYAN}Creating treasury withdrawal action${NC}"
echo -e "Title: ${YELLOW}$title${NC}"
echo -e " "
echo -e "Deposit return address: ${YELLOW}$deposit_return${NC}"

read -p "Do you want to proceed with this deposit return address? (yes/no): " confirm_deposit

if [ "$confirm_deposit" != "yes" ]; then
  echo -e "${RED}Deposit address not confirmed by user, exiting.${NC}"
  exit 1
fi

echo -e " "
echo -e "Withdrawal address: ${YELLOW}$withdrawal_address${NC}"

ada_amount=$(echo "scale=6; $withdrawal_amount / 1000000" | bc)
ada_amount_formatted=$(printf "%'0.6f" "$ada_amount")
echo -e "Withdrawal amount (ada): ${YELLOW}$ada_amount_formatted${NC}"

read -p "Do you want to proceed with this withdrawal address and amount? (yes/no): " confirm_withdrawal

if [ "$confirm_withdrawal" != "yes" ]; then
  echo -e "${RED}Withdrawal amount or withdrawal address not confirmed by user, exiting.${NC}"
  exit 1
fi

# Create the action
echo -e " "
echo -e "${CYAN}Creating action file...${NC}"

# todo support other networks
if [ -n "$testnet_magic" ]; then
    echo -e "${YELLOW}Using testnet magic: $testnet_magic${NC}"
else
    echo -e "${YELLOW}Using mainnet${NC}"
fi

cardano-cli conway governance action create-treasury-withdrawal \
  -- \
  --governance-action-deposit $(cardano-cli conway query gov-state --mainnet | jq -r '.currentPParams.govActionDeposit') \
  --deposit-return-stake-address "$deposit_return" \
  --anchor-url "ipfs://$ipfs_cid" \
  --anchor-data-hash "$file_hash" \
  --check-anchor-data \
  --funds-receiving-stake-address "$withdrawal_address" \
  --transfer "$withdrawal_amount" \
  --constitution-script-hash $(cardano-cli conway query constitution --mainnet | jq -r '.script') \
  --out-file "$input_file.action"
