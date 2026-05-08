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
    printf '%s%sCreate a Hard Fork Initiation action from a given JSON-LD metadata file%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<jsonld-file>%s [%s--deposit-return-addr%s <stake address>] [%s--prev-governance-action-id%s <tx-id>#<index>]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<jsonld-file>"                                       "Path to the JSON-LD metadata file"
    print_usage_option "[--deposit-return-addr <stake address>]"             "Optional check that metadata deposit return address matches provided one (Bech32)"
    print_usage_option "[--prev-governance-action-id <tx-id>#<index>]"       "Optional check that metadata previous-HF action id matches provided one"
    print_usage_option "-h, --help"                                          "Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_file=""

# Optional variables
deposit_return_address_input=""
prev_action_id_input=""
prev_tx_input=""
prev_idx_input=""

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
        --prev-governance-action-id)
            if [ -n "${2:-}" ]; then
                prev_action_id_input="$2"
                shift 2
            else
                print_fail "--prev-governance-action-id requires a value"
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
    print_hint "This script expects a CIP-108 metadata document whose body.onChain.gov_action.tag is 'hard_fork_initiation_action'."
    exit 1
fi

# Check if input file exists
if [ ! -f "$input_file" ]; then
    print_fail "Input file not found: $(fmt_path "$input_file")"
    exit 1
fi

# Parse --prev-governance-action-id if supplied: <64hex>#<integer>
if [ -n "$prev_action_id_input" ]; then
    if [[ ! "$prev_action_id_input" =~ ^[0-9a-fA-F]{64}#[0-9]+$ ]]; then
        print_fail "--prev-governance-action-id must be of the form <64-hex tx-id>#<integer index>. Got: $(fmt_path "$prev_action_id_input")"
        exit 1
    fi
    prev_tx_input="${prev_action_id_input%%#*}"
    prev_idx_input="${prev_action_id_input##*#}"
fi

print_banner "Creating a Hard Fork Initiation governance action from a given metadata file"
print_info "This script assumes compliance with Intersect's hard-fork-initiation action schema"
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

deposit=$(jq -r '.body.onChain.deposit' "$input_file")
check_field "deposit" "$deposit"

# HF-specific fields. All four are required by our contract — for a "very
# first hard fork in the chain" you'd omit gov_action_id, but Conway is well
# past that point and the metadata-create.sh prompt requires it.
target_major=$(jq -r '.body.onChain.gov_action.protocol_version.major' "$input_file")
check_field "protocol_version.major" "$target_major"
target_minor=$(jq -r '.body.onChain.gov_action.protocol_version.minor' "$input_file")
check_field "protocol_version.minor" "$target_minor"
prev_tx=$(jq -r '.body.onChain.gov_action.gov_action_id.transaction_id' "$input_file")
check_field "gov_action_id.transaction_id" "$prev_tx"
prev_idx=$(jq -r '.body.onChain.gov_action.gov_action_id.gov_action_index' "$input_file")
check_field "gov_action_id.gov_action_index" "$prev_idx"

# Sanity-check the deposit magnitude. The current Cardano governance action
# deposit is 100,000 ada = 100_000_000_000 lovelace.
EXPECTED_DEPOSIT_LOVELACE="100000000000"
if [ "$deposit" != "$EXPECTED_DEPOSIT_LOVELACE" ]; then
    print_warn "body.onChain.deposit = ${BRIGHTWHITE}${deposit}${NC} lovelace, expected ${BRIGHTWHITE}${EXPECTED_DEPOSIT_LOVELACE}${NC} (100,000 ADA, the current governance action deposit). Verify this is intentional before submitting."
fi

# Authoritative deposit check against the live protocol parameter
print_info "Checking that deposit matches the current protocol parameter"
onchain_deposit=$(cardano-cli conway query protocol-parameters | jq -r '.govActionDeposit')
if [ "$deposit" = "$onchain_deposit" ]; then
    print_pass "Metadata has expected deposit amount"
else
    print_fail "Metadata does not have expected deposit amount"
    print_hint "Expected: $onchain_deposit  found: $deposit"
    exit 1
fi

authors=$(jq -r '.authors' "$input_file")
check_field "authors" "$authors"
witness=$(jq -r '.authors[0].witness' "$input_file")
check_field "witness" "$witness"

if [ "$ga_type" = "hard_fork_initiation_action" ]; then
    print_pass "Metadata has correct governance action tag"
else
    print_fail "Metadata does not have the correct governance action tag"
    print_hint "Expected: hard_fork_initiation_action  found: $ga_type"
    exit 1
fi

# Shape-check HF-specific fields per CIP-116.
if [[ ! "$target_major" =~ ^[0-9]+$ ]]; then
    print_fail "body.onChain.gov_action.protocol_version.major must be a non-negative integer. Got: $target_major"
    exit 1
fi
if [[ ! "$target_minor" =~ ^[0-9]+$ ]]; then
    print_fail "body.onChain.gov_action.protocol_version.minor must be a non-negative integer. Got: $target_minor"
    exit 1
fi
if [[ ! "$prev_tx" =~ ^[0-9a-fA-F]{64}$ ]]; then
    print_fail "body.onChain.gov_action.gov_action_id.transaction_id must be 64 hex characters. Got: $prev_tx"
    exit 1
fi
if [[ ! "$prev_idx" =~ ^[0-9]+$ ]]; then
    print_fail "body.onChain.gov_action.gov_action_id.gov_action_index must be a non-negative integer. Got: $prev_idx"
    exit 1
fi
print_pass "HF-specific fields have valid shapes"

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

# if previous-action id passed in check against metadata
if [ -n "$prev_action_id_input" ]; then
    print_info "Comparing provided previous-HF action id to metadata"
    if [ "$prev_tx_input" = "$prev_tx" ] && [ "$prev_idx_input" = "$prev_idx" ]; then
        print_pass "Metadata has expected previous-HF action id"
    else
        print_fail "Metadata does not have expected previous-HF action id"
        print_hint "Provided: ${prev_tx_input}#${prev_idx_input}"
        print_hint "Metadata: ${prev_tx}#${prev_idx}"
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

print_pass "Automatic validations passed"

# HF-specific chain cross-checks: previous-action id (hard-fail) and target
# version sanity (warn-only).
print_section "Cross-checking chain state for hard-fork action"

# Cache gov-state once — used for both checks below.
gov_state_json=$(cardano-cli conway query gov-state)

chain_prev_hf=$(echo "$gov_state_json" | jq -c '.nextRatifyState.nextEnactState.prevGovActionIds.HardFork')
if [ "$chain_prev_hf" = "null" ] || [ -z "$chain_prev_hf" ]; then
    print_fail "Chain reports no previous hard fork in prevGovActionIds.HardFork, but metadata claims one (${prev_tx}#${prev_idx})."
    print_hint "If this is genuinely the first hard fork in the chain, the metadata must omit body.onChain.gov_action.gov_action_id — but our contract requires it. Resolve the contradiction before continuing."
    exit 1
fi
chain_prev_tx=$(echo "$chain_prev_hf" | jq -r '.txId')
chain_prev_idx=$(echo "$chain_prev_hf" | jq -r '.govActionIx')
if [ "$chain_prev_tx" != "$prev_tx" ] || [ "$chain_prev_idx" != "$prev_idx" ]; then
    print_fail "Metadata's previous-HF gov_action_id does not match chain state."
    print_hint "Metadata: ${prev_tx}#${prev_idx}"
    print_hint "Chain:    ${chain_prev_tx}#${chain_prev_idx}"
    exit 1
fi
print_pass "Previous-HF action id matches chain state"

# Target version sanity. HARDFORK-01 says the new major must be either equal
# to or one greater than the previous; if one greater, minor must be zero.
chain_major=$(echo "$gov_state_json" | jq -r '.currentPParams.protocolVersion.major')
chain_minor=$(echo "$gov_state_json" | jq -r '.currentPParams.protocolVersion.minor')
if [ "$target_major" = "$((chain_major + 1))" ] && [ "$target_minor" = "0" ]; then
    print_pass "Target version ${target_major}.${target_minor} is currentMajor+1 with minor=0 (HARDFORK-01 happy path)"
elif [ "$target_major" = "$chain_major" ] && [ "$target_minor" -gt "$chain_minor" ]; then
    print_pass "Target version ${target_major}.${target_minor} is a minor bump on currentMajor"
else
    print_warn "Target version ${target_major}.${target_minor} is unusual relative to chain ${chain_major}.${chain_minor}. Verify HARDFORK-01/-02/-03 before submitting."
fi

print_section "Computing details"

# Compute the hash and IPFS URI
file_hash=$(b2sum -l 256 "$input_file" | awk '{print $1}')
print_info "Metadata file hash: ${YELLOW}${file_hash}${NC}"

ipfs_cid=$(ipfs add -Q --cid-version 1 "$input_file")
print_info "IPFS URI: ${YELLOW}ipfs://${ipfs_cid}${NC}"

# Make user manually confirm the choices
print_section "Creating hard-fork-initiation action"
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

print_info "Target protocol version: ${YELLOW}${chain_major}.${chain_minor}${NC} -> ${YELLOW}${target_major}.${target_minor}${NC}"
if ! confirm "Do you want to proceed with this protocol version?"; then
    print_fail "Cancelled by user"
    exit 1
fi

print_info "Previous HF action: ${YELLOW}${prev_tx}#${prev_idx}${NC}"
if ! confirm "Do you want to proceed with this previous-action id?"; then
    print_fail "Cancelled by user"
    exit 1
fi

# Create the action
print_section "Creating action file"

action_file="$input_file.action"
action_json="$input_file.action.json"

cardano-cli conway governance action create-hardfork \
  --$protocol_magic \
  --governance-action-deposit $(cardano-cli conway query gov-state | jq -r '.currentPParams.govActionDeposit') \
  --deposit-return-stake-address "$deposit_return" \
  --anchor-url "ipfs://$ipfs_cid" \
  --anchor-data-hash "$file_hash" \
  --check-anchor-data \
  --protocol-major-version "$target_major" \
  --protocol-minor-version "$target_minor" \
  --prev-governance-action-tx-id "$prev_tx" \
  --prev-governance-action-index "$prev_idx" \
  --out-file "$action_file"

print_pass "Action file created at $(fmt_path "$action_file")"

print_section "Creating JSON representation of action file"

cardano-cli conway governance action view --action-file "$action_file" > "$action_json"
print_pass "JSON file created at $(fmt_path "$action_json")"

print_section "Summary"
print_pass "Hard Fork Initiation governance action created"
print_kv "Input"   "$(fmt_path "$input_file")"
print_kv "Action"  "$(fmt_path "$action_file")"
print_kv "JSON"    "$(fmt_path "$action_json")"
print_kv "Hash"    "$file_hash"
print_kv "IPFS"    "ipfs://$ipfs_cid"
print_kv "Version" "${target_major}.${target_minor}"
print_kv "Prev"    "${prev_tx}#${prev_idx}"
print_next "Include the action file in a transaction:" \
           "  cardano-cli latest transaction build \\" \
           "    --tx-in <utxo> --change-address <addr> \\" \
           "    --proposal-file '$action_file' \\" \
           "    --out-file tx.raw"
