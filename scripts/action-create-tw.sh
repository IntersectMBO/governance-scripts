#!/bin/bash

##################################################

# Default configuration values
WITHDRAW_TO_SCRIPT="true"

##################################################

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

# Check if cardano-cli is installed
if ! command -v cardano-cli >/dev/null 2>&1; then
  print_fail "cardano-cli is not installed or not in your PATH."
  exit 1
fi

# Check if ipfs cli is installed
if ! command -v ipfs >/dev/null 2>&1; then
  print_fail "ipfs cli is not installed or not in your PATH."
  exit 1
fi

# Usage message

usage() {
    printf '%s%sCreate a Treasury Withdrawal action from a given JSON-LD metadata file%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<jsonld-file>%s [%s--withdraw-to-key%s] [%s--deposit-return-addr%s <stake address>] [%s--withdrawal-addr%s <stake address>]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<jsonld-file>"                              "Path to the JSON-LD metadata file"
    print_usage_option "[--deposit-return-addr <stake address>]"    "Check that metadata deposit return address matches provided one (Bech32)"
    print_usage_option "[--withdraw-to-key]"                        "Allow withdrawal address to be key-based (default is script-based)"
    print_usage_option "[--withdrawal-addr <stake address>]"        "Check that metadata withdrawal address matches provided one (Bech32)"
    print_usage_option "-h, --help"                                 "Show this help message and exit"
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
                print_fail "--deposit-return-addr requires a value"
                usage
            fi
            ;;
        --withdrawal-addr)
            if [ -n "${2:-}" ]; then
                withdrawal_address_input="$2"
                shift 2
            else
                print_fail "--withdrawal-addr requires a value"
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
                print_fail "Input file already specified. Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

# If no input file provided, show usage
if [ -z "$input_file" ]; then
    print_fail "No input file specified"
    usage
fi

# Enforce .jsonld extension
if [[ "$input_file" != *.jsonld ]]; then
    print_fail "Input file $(fmt_path "$input_file") must be a JSON-LD metadata file with a .jsonld extension."
    print_hint "This script expects a CIP-108 metadata document whose body.onChain.gov_action.tag is 'treasury_withdrawals_action'."
    exit 1
fi

# Ensure the input file actually exists
if [ ! -f "$input_file" ]; then
    print_fail "Input file $(fmt_path "$input_file") not found."
    exit 1
fi

# If deposit return addr is not provided, show usage
if [ -z "$deposit_return_address_input" ]; then
    print_fail "--deposit-return-addr is required"
    usage
fi

# If withdrawal addr is not provided, show usage
if [ -z "$withdrawal_address_input" ]; then
    print_fail "--withdrawal-addr is required"
    usage
fi

print_banner "Creating a treasury withdrawal governance action from a given metadata file"
print_info "This script assumes compliance Intersect's treasury withdrawal action schema"
print_info "This script assumes that CARDANO_NODE_SOCKET_PATH, CARDANO_NODE_NETWORK_ID and IPFS_GATEWAY_URI are set"

# Exit if socket path is not set
if [ -z "$CARDANO_NODE_SOCKET_PATH" ]; then
    print_fail "CARDANO_NODE_SOCKET_PATH environment variable is not set."
    exit 1
fi

# Exit if network id is not set
if [ -z "$CARDANO_NODE_NETWORK_ID" ]; then
    print_fail "CARDANO_NODE_NETWORK_ID environment variable is not set."
fi

# Get if mainnet or testnet
if [ "$CARDANO_NODE_NETWORK_ID" = "764824073" ] || [ "$CARDANO_NODE_NETWORK_ID" = "mainnet" ]; then
    print_info "Local node is using mainnet"
    protocol_magic="mainnet"
else
    print_info "Local node is using a testnet"
    protocol_magic="testnet"
fi

# Open the provided metadata file

# Do some basic validation checks on metadata
print_section "Doing some basic validation and checks on metadata"

# Function to check if jq query returned null or empty
check_field() {
    local field_name="$1"
    local field_value="$2"

    if [ -z "$field_value" ] || [ "$field_value" = "null" ]; then
        print_fail "Required field '$field_name' not found in metadata"
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

# Sanity-check the deposit magnitude. The current Cardano governance action
# deposit is 100,000 ada = 100_000_000_000 lovelace.
EXPECTED_DEPOSIT_LOVELACE="100000000000"
if [ "$deposit_amount" != "$EXPECTED_DEPOSIT_LOVELACE" ]; then
    print_warn "body.onChain.deposit = ${BRIGHTWHITE}${deposit_amount}${NC} lovelace, expected ${BRIGHTWHITE}${EXPECTED_DEPOSIT_LOVELACE}${NC} (100,000 ADA, the current governance action deposit). Verify this is intentional before submitting."
fi

# Authoritative deposit check against the live protocol parameter
print_info "Checking that deposit matches the current protocol parameter"
onchain_deposit=$(cardano-cli conway query protocol-parameters | jq -r '.govActionDeposit')
if [ "$deposit_amount" = "$onchain_deposit" ]; then
    print_pass "Metadata has expected deposit amount"
else
    print_fail "Metadata does not have expected deposit amount"
    print_hint "Expected: $onchain_deposit  found: $deposit_amount"
    exit 1
fi

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
    print_pass "Metadata has correct governanceActionType"
else
    print_fail "Metadata does not have the correct governanceActionType"
    print_hint "Expected: treasury_withdrawals_action  found: $ga_type"
    exit 1
fi

# if return address passed in check against metadata
if [ -n "$deposit_return_address_input" ]; then
    print_info "Comparing provided deposit return address to metadata"
    if [ "$deposit_return_address_input" = "$deposit_return" ]; then
        print_pass "Metadata has expected deposit return address"
    else
        print_fail "Metadata does not have expected deposit return address"
        exit 1
    fi
fi

# check if withdrawal address is provided
if [ -n "$withdrawal_address_input" ]; then
    print_info "Comparing provided withdrawal address to metadata"
    if [ "$withdrawal_address_input" = "$withdrawal_address" ]; then
        print_pass "Metadata has expected withdrawal address"
    else
        print_fail "Metadata does not have expected withdrawal address"
        exit 1
    fi
fi

# Verify bech32 integrity (checksum + address type) of stake address
validate_stake_address() {
    local label="$1"
    local address="$2"
    local info
    if ! info=$(cardano-cli address info --address "$address" 2>&1); then
        print_fail "$label is not a valid bech32 address: $(fmt_path "$address")"
        print_hint "cardano-cli rejected it: $info"
        exit 1
    fi
    local addr_type
    addr_type=$(echo "$info" | jq -r '.type // ""')
    if [ "$addr_type" != "stake" ]; then
        print_fail "$label is bech32-valid but is not a stake address (type=${addr_type:-unknown}): $(fmt_path "$address")"
        exit 1
    fi
}

validate_stake_address "metadata body.onChain.reward_account" "$deposit_return"
validate_stake_address "metadata body.onChain.gov_action.rewards[0].key" "$withdrawal_address"

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
        print_fail "Invalid stake address format: $address"
        exit 1
    fi
}

# if mainnet node then expect addresses to be mainnet
if [ "$protocol_magic" = "mainnet" ]; then
    if is_stake_address_mainnet "$deposit_return"; then
        print_pass "Deposit return address is a valid mainnet stake address"
    else
        print_fail "Deposit return address is not a valid mainnet stake address"
        exit 1
    fi

    if is_stake_address_mainnet "$withdrawal_address"; then
        print_pass "Withdrawal address is a valid mainnet stake address"
    else
        print_fail "Withdrawal address is not a valid mainnet stake address"
        exit 1
    fi
else
    if ! is_stake_address_mainnet "$deposit_return"; then
        print_pass "Deposit return address is a valid testnet stake address"
    else
        print_fail "Deposit return address is not a valid testnet stake address"
        exit 1
    fi

    if ! is_stake_address_mainnet "$withdrawal_address"; then
        print_pass "Withdrawal address is a valid testnet stake address"
    else
        print_fail "Withdrawal address is not a valid testnet stake address"
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
        print_fail "Invalid stake address header byte"
        exit 1
    fi
}

withdraw_addr_script_check=$(is_stake_address_script "$withdrawal_address" && echo "true" || echo "false")

if [ "$withdraw_addr_script_check" = "$withdraw_to_script" ]; then
    if [ "$withdraw_to_script" = "true" ]; then
        print_pass "Withdrawal address is script-based, as expected"
    else
        print_pass "Withdrawal address is key-based, as expected"
    fi
else
    expected_type="script-based"
    [ "$withdraw_to_script" = "false" ] && expected_type="key-based"
    print_fail "Withdrawal address type does not match expectation ($expected_type)"
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
    print_pass "Deposit return stake address is registered"
else
    print_fail "Deposit return stake address is not registered"
    exit 1
fi

if is_stake_address_registered "$withdrawal_address"; then
    print_pass "Withdrawal stake address is registered"
else
    print_fail "Withdrawal stake address is not registered"
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
    print_pass "Withdrawal stake address is delegated to always abstain or not delegated at all"
else
    print_fail "Withdrawal stake address is delegated to something other than abstain"
    exit 1
fi

# todo add check if withdrawal address is delegated to an SPO

print_pass "Automatic validations passed"
print_section "Computing details"

# compute if provided addresses are script-based or key-based
# we should warn the user if they are key-based

# Compute the hash and IPFS URI
file_hash=$(b2sum -l 256 "$input_file" | awk '{print $1}')
print_info "Metadata file hash: ${YELLOW}${file_hash}${NC}"

ipfs_cid=$(ipfs add -Q --cid-version 1 "$input_file")
print_info "IPFS URI: ${YELLOW}ipfs://${ipfs_cid}${NC}"

# Make user manually confirm the choices
print_section "Creating treasury withdrawal action"
print_info "Title: ${YELLOW}${title}${NC}"
print_info "Deposit return address: ${YELLOW}${deposit_return}${NC}"
if is_stake_address_script "$deposit_return"; then
    print_info "(this is a script-based address)"
else
    print_info "(this is a key-based address)"
fi

if ! confirm "Do you want to proceed with this deposit return address?"; then
    print_fail "Cancelled by user"
    exit 1
fi

print_info "Withdrawal address: ${YELLOW}${withdrawal_address}${NC}"
if is_stake_address_script "$withdrawal_address"; then
    print_info "(this is a script-based address)"
else
    print_info "(this is a key-based address)"
fi

ada_amount=$(echo "scale=6; $withdrawal_amount / 1000000" | bc)
ada_amount_formatted=$(printf "%'0.6f" "$ada_amount")
print_info "Withdrawal amount (ada): ${YELLOW}${ada_amount_formatted}${NC}"

if ! confirm "Do you want to proceed with this withdrawal address and amount?"; then
    print_fail "Cancelled by user"
    exit 1
fi

# Create the action
print_section "Creating action file"

action_file="$input_file.action"
action_json="$input_file.action.json"

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
  --out-file "$action_file"

print_pass "Action file created at $(fmt_path "$action_file")"

print_section "Creating JSON representation of action file"

cardano-cli conway governance action view --action-file "$action_file" > "$action_json"
print_pass "JSON file created at $(fmt_path "$action_json")"

print_section "Summary"
print_pass "Treasury withdrawal governance action created"
print_kv "Input"      "$(fmt_path "$input_file")"
print_kv "Action"     "$(fmt_path "$action_file")"
print_kv "JSON"       "$(fmt_path "$action_json")"
print_kv "Hash"       "$file_hash"
print_kv "IPFS"       "ipfs://$ipfs_cid"
print_kv "Withdraw"   "${ada_amount_formatted} ada -> ${withdrawal_address}"
