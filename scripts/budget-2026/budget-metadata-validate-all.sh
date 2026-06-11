#!/bin/bash
#
# budget-metadata-validate-all.sh
#
# Validate every generated 2026 budget metadata file: run the standard
# metadata-validate.sh (CIP-108 / CIP-169 / Intersect schema) and a budget
# cross-check that the ada amount in the title matches the on-chain withdrawal.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUDGET_DIR="$SCRIPT_DIR"
# shellcheck source=../lib/messages.sh
source "$SCRIPTS_DIR/lib/messages.sh"

DEFAULT_DIR="$BUDGET_DIR/output"

usage() {
    printf '%s%sValidate all 2026 budget metadata files%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s [%s<dir>%s] [%s--strict%s] [-- <extra metadata-validate.sh flags>]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "[<dir>]"      "Directory of .jsonld files (default: $(fmt_path "$DEFAULT_DIR"))"
    print_usage_option "[--strict]"   "Validate without --draft (use after author-signing; requires non-empty authors)"
    print_usage_option "[-- ...]"     "Pass remaining flags through to metadata-validate.sh (e.g. --no-link-check)"
    print_usage_option "-h, --help"   "Show this help message and exit"
    exit 1
}

dir="$DEFAULT_DIR"
draft="--draft"
passthrough=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --strict)  draft=""; shift ;;
        --)        shift; passthrough+=("$@"); break ;;
        -h|--help) usage ;;
        -*)        print_fail "Unknown option: $1 (put metadata-validate.sh flags after --)"; usage ;;
        *)         dir="$1"; shift ;;
    esac
done

[ -d "$dir" ] || { print_fail "Not a directory: $(fmt_path "$dir")"; exit 1; }

jsonld_files=()
while IFS= read -r -d '' f; do jsonld_files+=("$f"); done \
    < <(find "$dir" -maxdepth 1 -type f -name "*.jsonld" -print0 | sort -z)

[ "${#jsonld_files[@]}" -eq 0 ] && { print_fail "No .jsonld files found in $(fmt_path "$dir")"; exit 1; }

print_banner "Validating ${#jsonld_files[@]} metadata file(s)${draft:+ (draft / pre-signing)}"

# Budget-specific cross-check: the ada figure stated in body.title must equal the
# on-chain withdrawal amount (lovelace / 1,000,000).
budget_crosscheck() {
    local file="$1" title ada lovelace_from_title onchain tag
    title=$(jq -r '.body.title // empty' "$file")
    tag=$(jq -r '.body.onChain.gov_action.tag // empty' "$file")
    onchain=$(jq -r '.body.onChain.gov_action.rewards[0].value // empty' "$file")

    if [ "$tag" != "treasury_withdrawals_action" ]; then
        print_fail "gov_action.tag is '${tag:-<missing>}', expected 'treasury_withdrawals_action'"
        return 1
    fi
    ada=$(printf '%s' "$title" | sed -n -E 's/.* ([0-9,]+) ada .*/\1/p' | tr -d ',')
    if [ -z "$ada" ]; then
        print_fail "Could not parse an ada amount from title: '$title'"
        return 1
    fi
    lovelace_from_title=$(awk -v a="$ada" 'BEGIN{ printf "%.0f", a*1000000 }')
    if [ "$lovelace_from_title" != "$onchain" ]; then
        print_fail "Title amount ${ada} ada = ${lovelace_from_title} lovelace, but on-chain value is ${onchain}"
        return 1
    fi
    print_pass "Title/on-chain amount match: ${ada} ada (${onchain} lovelace)"
    return 0
}

ok=0; failed=()
for f in "${jsonld_files[@]}"; do
    print_section "$(basename "$f")"
    file_ok=1

    if ! "$SCRIPTS_DIR/metadata-validate.sh" "$f" --cip108 --cip169 --intersect-schema ${draft:+$draft} ${passthrough[@]+"${passthrough[@]}"}; then
        file_ok=0
    fi
    if ! budget_crosscheck "$f"; then
        file_ok=0
    fi

    if [ "$file_ok" -eq 1 ]; then
        ok=$((ok + 1))
    else
        failed+=("$(basename "$f")")
    fi
done

print_section "Summary"
print_pass "Validated ${ok}/${#jsonld_files[@]} file(s)"
if [ "${#failed[@]}" -gt 0 ]; then
    print_fail "${#failed[@]} file(s) failed:"
    for f in "${failed[@]}"; do print_hint "$f"; done
    exit 1
fi
