#!/bin/bash
#
# budget-metadata-build-all.sh
#
# Build unsigned treasury-withdrawal metadata for every proposal listed in
# proposals.json by calling budget-metadata-build.sh for each.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUDGET_DIR="$SCRIPT_DIR"
# shellcheck source=../lib/messages.sh
source "$SCRIPTS_DIR/lib/messages.sh"

DEFAULT_PROPOSALS="$BUDGET_DIR/proposals.json"
DEFAULT_OUT_DIR="$BUDGET_DIR/output"

usage() {
    printf '%s%sBuild unsigned metadata for all 2026 budget proposals%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s [%s--proposals%s <file>] [%s--out-dir%s <dir>]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "[--proposals <file>]" "Proposals list (default: $(fmt_path "$DEFAULT_PROPOSALS"))"
    print_usage_option "[--out-dir <dir>]"    "Output directory (default: $(fmt_path "$DEFAULT_OUT_DIR"))"
    print_usage_option "-h, --help"           "Show this help message and exit"
    exit 1
}

proposals_file="$DEFAULT_PROPOSALS"
out_dir="$DEFAULT_OUT_DIR"
while [[ $# -gt 0 ]]; do
    case $1 in
        --proposals) if [ -n "${2:-}" ]; then proposals_file="$2"; shift 2; else print_fail "--proposals requires a value"; usage; fi ;;
        --out-dir)   if [ -n "${2:-}" ]; then out_dir="$2"; shift 2; else print_fail "--out-dir requires a value"; usage; fi ;;
        -h|--help)   usage ;;
        *)           print_fail "Unexpected argument: $1"; usage ;;
    esac
done

[ -f "$proposals_file" ] || { print_fail "Proposals file not found: $(fmt_path "$proposals_file")"; exit 1; }
if ! jq -e 'type == "array"' "$proposals_file" >/dev/null 2>&1; then
    print_fail "$(fmt_path "$proposals_file") must contain a JSON array of {id, name} objects (an optional 'title' is allowed for readability and ignored)."
    exit 1
fi

count=$(jq 'length' "$proposals_file")
print_banner "Building metadata for $count proposal(s)"

# Filesystem-safe slug (matches budget-metadata-build.sh) — used here only to detect
# filename collisions up front so same-named proposals don't silently overwrite.
slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

ok=0; failed=(); seen_stems=""
# Read entries as TSV so values with spaces survive intact.
while IFS=$'\t' read -r id name; do
    [ -z "$id" ] && continue
    [ "$id" = "null" ] && { print_fail "An entry is missing 'id' in $(fmt_path "$proposals_file")"; failed+=("<missing-id>"); continue; }
    [ "$name" = "null" ] && name=""

    # Resolve the output filename stem and disambiguate collisions (e.g. one proposer
    # with several projects all slugging to the same name) instead of overwriting.
    base="$(slugify "$name")"; [ -z "$base" ] && base="$id"
    prior=$(printf '%s\n' "$seen_stems" | grep -cxF -- "$base" || true)
    seen_stems="${seen_stems}${base}"$'\n'
    if [ "${prior:-0}" -gt 0 ]; then
        stem="${base}-$((prior + 1))"
        print_warn "Duplicate output name for '${name:-$id}' -> using '${stem}'. Give it a distinct name in proposals.json to avoid the suffix."
    else
        stem="$base"
    fi

    print_section "Proposal $id (${name:-$id}) -> ${stem}"
    args=("$id" --out-dir "$out_dir" --file-name "$stem")
    [ -n "$name" ] && args+=(--name "$name")

    if "$SCRIPT_DIR/budget-metadata-build.sh" "${args[@]}"; then
        ok=$((ok + 1))
    else
        print_fail "Build failed for proposal $id (${name:-$id})"
        failed+=("$id (${name:-$id})")
    fi
done < <(jq -r '.[] | [.id, (.name // "null")] | @tsv' "$proposals_file")

print_section "Summary"
print_pass "Built ${ok}/${count} metadata file(s) into $(fmt_path "$out_dir")"
if [ "${#failed[@]}" -gt 0 ]; then
    print_fail "${#failed[@]} failed:"
    for f in "${failed[@]}"; do print_hint "$f"; done
    exit 1
fi
print_next "Validate them (pre-signing):" \
           "  ./scripts/budget-2026/budget-metadata-validate-all.sh"
