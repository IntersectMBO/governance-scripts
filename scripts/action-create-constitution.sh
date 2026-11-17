#!/bin/bash

##################################################

# Default configuration values

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
    printf '%s%sCreate a New Constitution action from a given JSON-LD metadata file%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<jsonld-file>%s [%s--deposit-return-addr%s <stake address>]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<jsonld-file>"                             "Path to the JSON-LD metadata file"
    print_usage_option "[--deposit-return-addr <stake address>]"   "Optional check that metadata deposit return address matches provided one (Bech32)"
    print_usage_option "-h, --help"                                "Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_file=""

# Optional variables
deposit_return_address_input=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --deposit-return-addr)
            if [ -n "${2:-}" ]; then
                deposit_return_address_input="$2"
                shift 2
            else
                print_fail "--deposit-return-addr requires a value"
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
    print_hint "This script expects a CIP-108 metadata document whose body.onChain.gov_action.tag is 'new_constitution_action'."
    exit 1
fi

# Check if input file exists
if [ ! -f "$input_file" ]; then
    print_fail "Input file not found: $(fmt_path "$input_file")"
    exit 1
fi

print_banner "Creating a New Constitution governance action from a given metadata file"
print_info "This script assumes compliance with Intersect's new constitution action schema"
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

constitution_url=$(jq -r '.body.onChain.gov_action.constitution.anchor.url' "$input_file")
check_field "constitution.anchor.url" "$constitution_url"

constitution_hash=$(jq -r '.body.onChain.gov_action.constitution.anchor.data_hash' "$input_file")
check_field "constitution.anchor.data_hash" "$constitution_hash"

constitution_script_hash=$(jq -r '.body.onChain.gov_action.constitution.script_hash' "$input_file")
check_field "constitution.script_hash" "$constitution_script_hash"

prev_tx_id=$(jq -r '.body.onChain.gov_action.gov_action_id.transaction_id' "$input_file")
check_field "gov_action_id.transaction_id" "$prev_tx_id"

prev_action_index=$(jq -r '.body.onChain.gov_action.gov_action_id.gov_action_index' "$input_file")
check_field "gov_action_id.gov_action_index" "$prev_action_index"

authors=$(jq -r '.authors' "$input_file")
check_field "authors" "$authors"
witness=$(jq -r '.authors[0].witness' "$input_file")
check_field "witness" "$witness"

if [ "$ga_type" = "new_constitution" ]; then
    print_pass "Metadata has correct governance action tag"
else
    print_fail "Metadata does not have the correct governance action tag"
    print_hint "Expected: new_constitution  found: $ga_type"
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

# use bech32 prefix to determine if addresses are mainnet or testnet
is_stake_address_mainnet() {
    local address="$1"
    if [[ "$address" =~ ^stake1 ]]; then
        return 0
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
else
    if ! is_stake_address_mainnet "$deposit_return"; then
        print_pass "Deposit return address is a valid testnet stake address"
    else
        print_fail "Deposit return address is not a valid testnet stake address"
        exit 1
    fi
fi

# use header byte to determine if stake address is script-based or key-based
is_stake_address_script() {
    local address="$1"

    address_hex=$(cardano-cli address info --address "$address" | jq -r ".base16")
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

is_stake_address_registered() {
    local address="$1"
    stake_address_deposit=$(cardano-cli conway query stake-address-info --address "$address" | jq -r '.[0].stakeRegistrationDeposit')
    if [ "$stake_address_deposit" != "null" ]; then
        return 0
    else
        return 1
    fi
}

# check if stake address is registered
if is_stake_address_registered "$deposit_return"; then
    print_pass "Deposit return stake address is registered"
else
    print_fail "Deposit return stake address is not registered"
    exit 1
fi

# Check that prev gov action id in metadata matches the one currently on chain
print_info "Checking previous constitution gov action id against chain"
onchain_prev_tx=$(cardano-cli conway query gov-state | jq -r '.nextRatifyState.nextEnactState.prevGovActionIds.Constitution.txId // empty')
onchain_prev_idx=$(cardano-cli conway query gov-state | jq -r '.nextRatifyState.nextEnactState.prevGovActionIds.Constitution.govActionIx // empty')
if [ -z "$onchain_prev_tx" ]; then
    print_warn "No previous constitution action found on chain; cannot verify gov_action_id"
elif [ "$prev_tx_id" = "$onchain_prev_tx" ] && [ "$prev_action_index" = "$onchain_prev_idx" ]; then
    print_pass "Previous gov action id matches chain (${prev_tx_id}#${prev_action_index})"
else
    print_fail "Previous gov action id in metadata does not match chain"
    print_hint "Metadata: ${prev_tx_id}#${prev_action_index}  Chain: ${onchain_prev_tx}#${onchain_prev_idx}"
    exit 1
fi

# Verify the constitution document URL produces the same data_hash as in metadata
print_info "Verifying constitution URL hash matches metadata data_hash"
computed_constitution_hash=$(cardano-cli hash anchor-data --url "$constitution_url" 2>/dev/null) || computed_constitution_hash=""
if [ -z "$computed_constitution_hash" ]; then
    print_warn "Could not fetch constitution URL to verify hash — proceeding without verification"
elif [ "$computed_constitution_hash" = "$constitution_hash" ]; then
    print_pass "Constitution URL hash matches metadata data_hash"
else
    print_fail "Constitution URL hash does not match metadata data_hash"
    print_hint "Computed: ${computed_constitution_hash}  Metadata: ${constitution_hash}"
    exit 1
fi

# Inform the user whether the guardrails script hash is new or the existing on-chain one
print_info "Checking guardrails script hash"
onchain_script_hash=$(cardano-cli conway query constitution 2>/dev/null | jq -r '.script // empty') || onchain_script_hash=""
if [ "$constitution_script_hash" = "$onchain_script_hash" ]; then
    print_info "Guardrails script: ${YELLOW}${constitution_script_hash}${NC} (existing on-chain script — unchanged)"
else
    print_warn "Guardrails script: ${YELLOW}${constitution_script_hash}${NC} is a NEW script hash (current on-chain: ${onchain_script_hash:-none})"
fi

print_pass "Automatic validations passed"
print_section "Computing details"

# Compute the hash and IPFS URI
file_hash=$(b2sum -l 256 "$input_file" | awk '{print $1}')
print_info "Metadata file hash: ${YELLOW}${file_hash}${NC}"

ipfs_cid=$(ipfs add -Q --cid-version 1 "$input_file")
print_info "IPFS URI: ${YELLOW}ipfs://${ipfs_cid}${NC}"

# Make user manually confirm the choices
print_section "Creating new constitution action"
print_info "Title: ${YELLOW}${title}${NC}"
print_info "Deposit return address: ${YELLOW}${deposit_return}${NC}"
if is_stake_address_script "$deposit_return"; then
    print_info "(this is a script-based address)"
else
    print_info "(this is a key-based address)"
fi
print_info "Constitution URL:    ${YELLOW}${constitution_url}${NC}"
print_info "Constitution hash:   ${YELLOW}${constitution_hash}${NC}"
print_info "Previous gov action: ${YELLOW}${prev_tx_id}#${prev_action_index}${NC}"

if ! confirm "Do you want to proceed?"; then
    print_fail "Cancelled by user"
    exit 1
fi

# Create the action
print_section "Creating action file"

action_file="$input_file.action"
action_json="$input_file.action.json"

gov_action_deposit=$(cardano-cli conway query gov-state | jq -r '.currentPParams.govActionDeposit')
require_nonnull "$gov_action_deposit" "governance action deposit (gov-state .currentPParams.govActionDeposit)"

cardano-cli conway governance action create-constitution \
  --"$protocol_magic" \
  --governance-action-deposit "$gov_action_deposit" \
  --deposit-return-stake-address "$deposit_return" \
  --prev-governance-action-tx-id "$prev_tx_id" \
  --prev-governance-action-index "$prev_action_index" \
  --anchor-url "ipfs://$ipfs_cid" \
  --anchor-data-hash "$file_hash" \
  --check-anchor-data \
  --constitution-url "$constitution_url" \
  --constitution-hash "$constitution_hash" \
  --check-constitution-hash \
  --constitution-script-hash "$constitution_script_hash" \
  --out-file "$action_file"

print_pass "Action file created at $(fmt_path "$action_file")"

print_section "Creating JSON representation of action file"

cardano-cli conway governance action view --action-file "$action_file" > "$action_json"
print_pass "JSON file created at $(fmt_path "$action_json")"

print_section "Summary"
print_pass "New constitution governance action created"
print_kv "Input"            "$(fmt_path "$input_file")"
print_kv "Action"           "$(fmt_path "$action_file")"
print_kv "JSON"             "$(fmt_path "$action_json")"
print_kv "Hash"             "$file_hash"
print_kv "IPFS"             "ipfs://$ipfs_cid"
print_kv "Constitution URL" "$constitution_url"
print_next "Include the action file in a transaction:" \
           "  cardano-cli latest transaction build \\" \
           "    --tx-in <utxo> --change-address <addr> \\" \
           "    --proposal-file '$action_file' \\" \
           "    --out-file tx.raw"
