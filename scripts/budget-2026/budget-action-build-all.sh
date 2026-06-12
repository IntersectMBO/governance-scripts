#!/bin/bash
#
# budget-action-build-all.sh
#
# For every signed 2026 budget metadata file: pin it to IPFS (ipfs-pin.sh) and
# create the treasury-withdrawal governance action (action-create-tw.sh), using
# the single Intersect withdrawal + deposit-return addresses from config.sh.
#
# Run this AFTER the metadata has been author-signed. Requires a live cardano-cli
# node (CARDANO_NODE_SOCKET_PATH, CARDANO_NODE_NETWORK_ID) and the ipfs CLI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUDGET_DIR="$SCRIPT_DIR"
# shellcheck source=../lib/messages.sh
source "$SCRIPTS_DIR/lib/messages.sh"

CONFIG_FILE="$BUDGET_DIR/config.sh"
DEFAULT_DIR="$BUDGET_DIR/output"

usage() {
    printf '%s%sPin + create treasury-withdrawal actions for all 2026 budget metadata%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s [%s<dir>%s] [%s--no-ipfs-pin%s]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "[<dir>]"          "Directory of signed .jsonld files (default: $(fmt_path "$DEFAULT_DIR"))"
    print_usage_option "[--no-ipfs-pin]"  "Skip the IPFS pinning step (metadata must already be reachable)"
    print_usage_option "-h, --help"       "Show this help message and exit"
    exit 1
}

dir="$DEFAULT_DIR"
skip_pin="false"
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-ipfs-pin) skip_pin="true"; shift ;;
        -h|--help)     usage ;;
        -*)            print_fail "Unknown option: $1"; usage ;;
        *)             dir="$1"; shift ;;
    esac
done

[ -f "$CONFIG_FILE" ] || { print_fail "Config not found: $(fmt_path "$CONFIG_FILE")"; exit 1; }
[ -d "$dir" ]         || { print_fail "Not a directory: $(fmt_path "$dir")"; exit 1; }
# shellcheck source=config.sh
source "$CONFIG_FILE"

# These addresses move real treasury funds — refuse to run with placeholders.
for var in WITHDRAWAL_ADDR DEPOSIT_RETURN_ADDR; do
    if [[ "${!var:-}" == *REPLACEME* || -z "${!var:-}" ]]; then
        print_fail "config.sh: $var is not set to a real stake address. Refusing to build on-chain actions."
        exit 1
    fi
done

if [ -z "${CARDANO_NODE_SOCKET_PATH:-}" ] || [ -z "${CARDANO_NODE_NETWORK_ID:-}" ]; then
    print_fail "CARDANO_NODE_SOCKET_PATH and CARDANO_NODE_NETWORK_ID must be set (a live node is required)."
    exit 1
fi

jsonld_files=()
while IFS= read -r -d '' f; do jsonld_files+=("$f"); done \
    < <(find "$dir" -maxdepth 1 -type f -name "*.jsonld" -print0 | sort -z)

[ "${#jsonld_files[@]}" -eq 0 ] && { print_fail "No .jsonld files found in $(fmt_path "$dir")"; exit 1; }

print_banner "Building ${#jsonld_files[@]} treasury-withdrawal action(s)"
print_info "Withdrawal address:     ${YELLOW}${WITHDRAWAL_ADDR}${NC}"
print_info "Deposit-return address: ${YELLOW}${DEPOSIT_RETURN_ADDR}${NC}"

ok=0
for f in "${jsonld_files[@]}"; do
    print_section "$(basename "$f")"

    if [ "$skip_pin" = "false" ]; then
        if ! "$SCRIPTS_DIR/ipfs-pin.sh" "$f"; then
            print_fail "IPFS pinning failed for $(fmt_path "$f"). Stopping."
            print_hint "Already-created actions are unaffected; re-run after fixing the issue."
            exit 1
        fi
    else
        print_info "Skipping IPFS pinning step"
    fi

    if ! "$SCRIPTS_DIR/action-create-tw.sh" "$f" \
            --deposit-return-addr "$DEPOSIT_RETURN_ADDR" \
            --withdrawal-addr "$WITHDRAWAL_ADDR"; then
        print_fail "Action creation failed for $(fmt_path "$f"). Stopping."
        print_hint "$ok action(s) created so far; re-run to resume with the remaining files."
        exit 1
    fi
    ok=$((ok + 1))
done

print_section "Summary"
print_pass "Created ${ok}/${#jsonld_files[@]} treasury-withdrawal action(s) in $(fmt_path "$dir")"
print_next "Each action is in <name>.jsonld.action — include it in a transaction:" \
           "  cardano-cli latest transaction build --proposal-file <file>.jsonld.action ..."
