#!/bin/bash

##################################################

# Default configuration values
WITHDRAW_TO_SCRIPT="true"

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

# Check if cardano-cli is installed
if ! command -v cardano-cli >/dev/null 2>&1; then
  echo -e "${RED}Error: cardano-cli is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Check if ipfs cli is installed
if ! command -v ipfs >/dev/null 2>&1; then
  echo -e "${RED}Error: ipfs cli is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Usage message

usage() {
    local col=50
    echo -e "${UNDERLINE}${BOLD}Create a Treasury Withdrawal action from a given JSON-LD metadata file${NC}"
    echo -e "\n"
    echo -e "Syntax:${BOLD} $0 ${GREEN}<jsonld-file> ${NC}[${GREEN}--withdraw-to-key${NC}] [${GREEN}--deposit-return-addr ${NC}<stake address>] [${GREEN}--withdrawal-addr ${NC}<stake address>]"
    printf "Params: ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "<jsonld-file>" "- Path to the JSON-LD metadata file"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "[--deposit-return-addr <stake address>]" "- Check that metadata deposit return address matches provided one (Bech32)"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "[--withdraw-to-key]" "- Allow withdrawal address to be key-based (default is script-based)"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "[--withdrawal-addr <stake address>]" "- Check that metadata withdrawal address matches provided one (Bech32)"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "-h, --help" "- Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_file=""

# Optional variables
withdraw_to_script="$WITHDRAW_TO_SCRIPT"
deposit_return_address_input=""
withdrawal_address_input=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --withdraw-to-key)
            withdraw_to_script="false"
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

# If deposit return addr is not provided, show usage
if [ -z "$deposit_return_address_input" ]; then
  echo -e "${RED}Error: --deposit-return-addr is required${NC}" >&2
  usage
fi

# If withdrawal addr is not provided, show usage
if [ -z "$withdrawal_address_input" ]; then
  echo -e "${RED}Error: --withdrawal-addr is required${NC}" >&2
  usage
fi

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

ga_type=$(jq -r '.body.onChain.gov_action.tag' "$input_file")
check_field "tag" "$ga_type"

deposit_return=$(jq -r '.body.onChain.reward_account' "$input_file")
check_field "reward_account" "$deposit_return"

deposit_amount=$(jq -r '.body.onChain.deposit' "$input_file")
check_field "deposit" "$deposit_amount"

withdrawal_list=$(jq -r '.body.onChain.gov_action.rewards' "$input_file")
check_field "rewards" "$withdrawal_list"

# todo: support multiple withdrawals
withdrawal_address=$(jq -r '.body.onChain.gov_action.rewards[0].key' "$input_file")
check_field "key" "$withdrawal_address"
withdrawal_amount=$(jq -r '.body.onChain.gov_action.rewards[0].value' "$input_file")
check_field "value" "$withdrawal_amount"

authors=$(jq -r '.authors' "$input_file")
check_field "authors" "$authors"
witness=$(jq -r '.authors[0].witness' "$input_file")
check_field "witness" "$witness"

if [ "$ga_type" = "treasury_withdrawals_action" ]; then
    echo "Metadata has correct governanceActionType"
else
    echo "Metadata does not have the correct governanceActionType"
    echo "Expected: treasury_withdrawals_action found: $ga_type"
    exit 1
fi

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

# use bech32 prefix to determine if addresses are mainnet or testnet
is_stake_address_mainnet() {
    local address="$1"
    # Check if address starts with stake1 (mainnet)
    if [[ "$address" =~ ^stake1 ]]; then
        return 0
    # Check if address starts with stake_test1 (testnet)
    elif [[ "$address" =~ ^stake_test1 ]]; then
        return 1
    else
        echo -e "${RED}Error: Invalid stake address format: $address${NC}" >&2
        exit 1
    fi
}

# if mainnet node then expect addresses to be mainnet
if [ "$protocol_magic" = "mainnet" ]; then
    if is_stake_address_mainnet "$deposit_return"; then
        echo -e "Deposit return address is a valid mainnet stake address"
    else
        echo -e "${RED}Deposit return address is not a valid mainnet stake address${NC}"
        exit 1
    fi

    if is_stake_address_mainnet "$withdrawal_address"; then
        echo -e "Withdrawal address is a valid mainnet stake address"
    else
        echo -e "${RED}Withdrawal address is not a valid mainnet stake address${NC}"
        exit 1
    fi
else
    if ! is_stake_address_mainnet "$deposit_return"; then
        echo -e "Deposit return address is a valid testnet stake address"
    else
        echo -e "${RED}Deposit return address is not a valid testnet stake address${NC}"
        exit 1
    fi

    if ! is_stake_address_mainnet "$withdrawal_address"; then
        echo -e "Withdrawal address is a valid testnet stake address"
    else
        echo -e "${RED}Withdrawal address is not a valid testnet stake address${NC}"
        exit 1
    fi
fi

# use header byte to determine if stake address is script-based or key-based
is_stake_address_script() {
    local address="$1"

    address_hex=$(cardano-cli address info --address "$address"| jq -r ".base16")
    first_char="${address_hex:0:1}"
    
    if [ "$first_char" = "f" ]; then
        return 0  # true
    elif [ "$first_char" = "e" ]; then
        return 1  # false
    else
        echo -e "${RED}Error: Invalid stake address header byte${NC}" >&2
        exit 1
    fi
}

withdraw_addr_script_check=$(is_stake_address_script "$withdrawal_address" && echo "true" || echo "false")

if [ "$withdraw_addr_script_check" = "$withdraw_to_script" ]; then
    if [ "$withdraw_to_script" = "true" ]; then
        echo -e "Withdrawal address is script-based, as expected"
    else
        echo -e "Withdrawal address is key-based, as expected"
    fi
else
    expected_type="script-based"
    [ "$withdraw_to_script" = "false" ] && expected_type="key-based"
    echo -e "${RED}Withdrawal address type does not match expectation ($expected_type), exiting.${NC}"
    exit 1
fi

is_stake_address_registered(){
    local address="$1"
    stake_address_deposit=$(cardano-cli conway query stake-address-info --address "$address" | jq -r '.[0].stakeRegistrationDeposit')
    if [ "$stake_address_deposit" != "null" ]; then
        return 0
    else
        return 1
    fi
}

# check if stake addresses are registered
if is_stake_address_registered "$deposit_return"; then
    echo -e "Deposit return stake address is registered"
else
   echo -e "${RED}Deposit return stake address is not registered, exiting.${NC}"
   exit 1
fi

if is_stake_address_registered "$withdrawal_address"; then
    echo -e "Withdrawal stake address is registered"
else
    echo -e "${RED}Withdrawal stake address is not registered, exiting.${NC}"
    exit 1
fi

is_stake_address_delegated_to_abstain_or_null() {
    local address="$1"
    vote_delegation=$(cardano-cli conway query stake-address-info --address "$address" | jq -r '.[0].voteDelegation')
    if [ "$vote_delegation" = "alwaysAbstain" ] || [ "$vote_delegation" = "null" ] ; then
        return 0
    else
        return 1
    fi
}

if is_stake_address_delegated_to_abstain_or_null "$withdrawal_address"; then
    echo -e "Withdrawal stake address is delegated to always abstain or not delegated at all"
else
    echo -e "${RED}Withdrawal stake address is delegated to something other than abstain, exiting.${NC}"
    exit 1
fi

# todo add check if withdrawal address is delegated to an SPO

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
if is_stake_address_script "$deposit_return"; then
    echo -e "(this is a script-based address)"
else
    echo -e "(this is a key-based address)"
fi

echo -e " "
read -p "Do you want to proceed with this deposit return address? (yes/no): " confirm_deposit

if [ "$confirm_deposit" != "yes" ]; then
  echo -e "${RED}Deposit address not confirmed by user, exiting.${NC}"
  exit 1
fi

echo -e " "
echo -e "Withdrawal address: ${YELLOW}$withdrawal_address${NC}"
if is_stake_address_script "$withdrawal_address"; then
    echo -e "(this is a script-based address)"
else
    echo -e "(this is a key-based address)"
fi

ada_amount=$(echo "scale=6; $withdrawal_amount / 1000000" | bc)
ada_amount_formatted=$(printf "%'0.6f" "$ada_amount")
echo -e "Withdrawal amount (ada): ${YELLOW}$ada_amount_formatted${NC}"

echo -e " "
read -p "Do you want to proceed with this withdrawal address and amount? (yes/no): " confirm_withdrawal

if [ "$confirm_withdrawal" != "yes" ]; then
  echo -e "${RED}Withdrawal amount or withdrawal address not confirmed by user, exiting.${NC}"
  exit 1
fi

# Create the action
echo -e " "
echo -e "${CYAN}Creating action file...${NC}"

cardano-cli conway governance action create-treasury-withdrawal \
  --$protocol_magic \
  --governance-action-deposit $(cardano-cli conway query gov-state | jq -r '.currentPParams.govActionDeposit') \
  --deposit-return-stake-address "$deposit_return" \
  --anchor-url "ipfs://$ipfs_cid" \
  --anchor-data-hash "$file_hash" \
  --check-anchor-data \
  --funds-receiving-stake-address "$withdrawal_address" \
  --transfer "$withdrawal_amount" \
  --constitution-script-hash $(cardano-cli conway query constitution | jq -r '.script') \
  --out-file "$input_file.action"

echo -e "${GREEN}Action file created at "$input_file.action" ${NC}"

echo -e " "
echo -e "${CYAN}Creating JSON representation of action file...${NC}"

cardano-cli conway governance action view --action-file "$input_file.action" > "$input_file.action.json"
echo -e "${GREEN}JSON file created at "$input_file.action.json" ${NC}"