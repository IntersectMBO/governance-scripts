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

# todo get the network/testnet magic from the set $SOCKET_PATH

usage() {
    echo "Usage: $0 <jsonld-file|directory> [--testnet-magic <NUMBER>] [--deposit-return-addr <stake address>] [--single-withdrawal-addr <stake address>]"
    echo "Options:"
    echo "  --testnet-magic <NUMBER>                      Use a test network, denoted by magic value"
    echo "  --deposit-return-addr <stake address>         Check that metadata deposit return address matches provided one (Bech32)"
    echo "  --single-withdrawal-addr <stake address>      Check that metadata withdrawal address matches provided one (Bech32)"
    exit 1
}

# Initialize variables with defaults
input_file=""

# Optional variables
testnet_magic=""
deposit_return_address=""
withdrawal_address=""

# todo check all the inputs work

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --testnet-magic)
            testnet_magic="$2"
            shift 2
            ;;
        --deposit-return-addr)
            deposit_return_address="$3"
            shift 3
            ;;
        --single-withdrawal-addr)
            withdrawal_address="$4"
            shift 4
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_file" ]; then
                input_file="$1"
            fi
            shift
            ;;
    esac
done

echo "Creating a treasury withdrawal governance action from a given metadata file"
echo "This script assumes compliance Intersect's treasury withdrawal action schema"
echo "This script assumes that SOCKET_PATH is set to a local node socket file"
echo " "

# Exit is socket path is not set
if [ -z "$SOCKET_PATH" ]; then
    echo "Error: Cardano node $SOCKET_PATH environment variable is not set." >&2
    exit 1
fi

# Open the provided metadata file

# todo: add checks to exit if any of these fields are not found

title=$(jq -r '.body.title' "$input_file")
ga_type=$(jq -r '.body.onChain.governanceActionType' "$input_file")
deposit_return=$(jq -r '.body.onChain.depositReturnAddress' "$input_file")

# todo: for now just support one withdrawal
withdrawal_address=$(jq -r '.body.onChain.withdrawals[0].withdrawalAddress' "$input_file")
withdrawal_address=$(jq -r '.body.onChain.withdrawals[0].withdrawalAmount' "$input_file")

# Do some basic validation checks
echo -e " "
echo -e "${CYAN}Doing some basic validation and checks on metadata${NC}"

if [ "$ga_type" = "treasuryWithdrawals" ]; then
    echo "Metadata has correct governanceActionType"
else
    echo "Metadata does not have the correct governanceActionType"
    echo "Expected: treasuryWithdrawals found: $ga_type"
    exit 1
fi

# deposit address is the same network as the connected and provided testnet_magic

# check the bech32 prefix to determine network
# if [ "$($deposit_return_address)" = "stake1" && "$testnet_magic" = "" ]; then
#     echo
# else

# fi

# deposit address matches the one provided

# if return address provided check against metadata
if [ !"$deposit_return_address" = "" ]; then
    echo "Deposit return address provided"
    echo "Comparing provided address to metadata"
    if [ "$deposit_return_address" = "$deposit_return" ]; then
        echo "Metadata has expected deposit return address"
    else
        echo "Metadata does not have expected deposit return address"
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
echo "Metadata file hash: $file_hash"

ipfs_cid=$(ipfs add -Q --cid-version 1 "$input_file")
echo "IPFS URI: ipfs://$ipfs_cid"

# Make user manually confirm the choices
echo " "
echo "Creating treasury withdrawal action"
echo "Titled: $title"
echo "Deposit return address: $deposit_return"

read -p "Do you want to proceed with this deposit return address? (yes/no): " confirm_deposit

if [ "$confirm_deposit" != "yes" ]; then
  echo -e "${RED}Deposit address not confirmed by user, exiting.${NC}"
  exit 1
fi

echo "Withdrawal address: $withdrawal_address"

# todo also show amount in ada

echo "Withdrawal amount (lovelace): $withdrawal_amount"

read -p "Do you want to proceed with these files? (yes/no): " confirm_withdrawal

if [ "$confirm_withdrawal" != "yes" ]; then
  echo -e "${RED}Withdrawal amount or withdrawal address not confirmed by user, exiting.${NC}"
  exit 1
fi

# Create the action
echo "Creating action"

cardano-cli conway governance action create-treasury-withdrawal \
  --mainnet \
  --governance-action-deposit $(cardano-cli conway query gov-state | jq -r '.currentPParams.govActionDeposit') \
  --deposit-return-stake-address "$deposit_return_address" \
  --anchor-url "ipfs://$ipfs_cid" \
  --anchor-data-hash "$file_hash" \
  --check-anchor-data \
  --funds-receiving-stake-address "$withdrawal_address" \
  --transfer "$withdrawal_amount" \
  --constitution-script-hash $(cardano-cli conway query constitution | jq -r '.script') \
  --out-file "$input_file.action"


