#!/bin/bash
#
# Enumerate all proposals in a hydra budget vote and write a CANDIDATE proposals.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUDGET_DIR="$SCRIPT_DIR"
# shellcheck source=../lib/messages.sh
source "$SCRIPTS_DIR/lib/messages.sh"

CONFIG_FILE="$BUDGET_DIR/config.sh"
DEFAULT_OUT="$BUDGET_DIR/proposals.candidate.json"
MAX_PAGES=100

for dep in curl jq; do
  command -v "$dep" >/dev/null 2>&1 || { print_fail "$dep is not installed or not in your PATH."; exit 1; }
done

usage() {
    printf '%s%sFetch a budget vote'\''s proposals into a candidate proposals.json%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s [%s--vote%s <vote-id>] [%s--out%s <file>] [%s--force%s]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "[--vote <vote-id>]" "Hydra vote/cycle id (default: \$HYDRA_VOTE_ID from config.sh)"
    print_usage_option "[--out <file>]"     "Output file (default: $(fmt_path "$DEFAULT_OUT"))"
    print_usage_option "[--force]"          "Overwrite the output file if it already exists"
    print_usage_option "-h, --help"         "Show this help message and exit"
    exit 1
}

vote_id=""
out_file="$DEFAULT_OUT"
force="false"
while [[ $# -gt 0 ]]; do
    case $1 in
        --vote)  if [ -n "${2:-}" ]; then vote_id="$2"; shift 2; else print_fail "--vote requires a value"; usage; fi ;;
        --out)   if [ -n "${2:-}" ]; then out_file="$2"; shift 2; else print_fail "--out requires a value"; usage; fi ;;
        --force) force="true"; shift ;;
        -h|--help) usage ;;
        *) print_fail "Unexpected argument: $1"; usage ;;
    esac
done

[ -f "$CONFIG_FILE" ] || { print_fail "Config not found: $(fmt_path "$CONFIG_FILE")"; exit 1; }
# shellcheck source=config.sh
source "$CONFIG_FILE"
[ -z "$vote_id" ] && vote_id="${HYDRA_VOTE_ID:-}"
[ -z "$vote_id" ] && { print_fail "No vote id (pass --vote or set HYDRA_VOTE_ID in config.sh)"; exit 1; }

if [ -e "$out_file" ] && [ "$force" != "true" ]; then
    print_fail "Output file already exists: $(fmt_path "$out_file")"
    print_hint "Use --force to overwrite, or --out <file> to write elsewhere."
    exit 1
fi

print_banner "Fetching proposals for vote $vote_id"

PAGES_DIR=$(mktemp -d /tmp/budget_pages.XXXXXX)
cleanup() { rm -rf "$PAGES_DIR"; }
trap cleanup EXIT

page=1
total="?"
while [ "$page" -le "$MAX_PAGES" ]; do
    url="${HYDRA_API_BASE%/}/proposals?vote=${vote_id}&page=${page}"
    if ! curl -sSfL "$url" -o "$PAGES_DIR/page-$(printf '%03d' "$page").json"; then
        print_fail "Failed to fetch $url"
        exit 1
    fi
    pfile="$PAGES_DIR/page-$(printf '%03d' "$page").json"
    if ! jq -e '.data | type == "array"' "$pfile" >/dev/null 2>&1; then
        print_fail "Unexpected response shape on page $page (expected .data array)."
        exit 1
    fi
    total=$(jq -r '.meta.total // "?"' "$pfile")
    got=$(jq -r '.data | length' "$pfile")
    print_info "page ${page}: ${got} proposal(s)"
    [ "$(jq -r '.meta.hasNextPage // false' "$pfile")" = "true" ] || break
    page=$((page + 1))
done

# Merge all pages and derive a concise name from each title:
#   strip from the first ':' or en/em dash (or ' - '), then trim; fall back to the
#   full title when nothing remains.
jq -s '
  [ .[].data[] ]
  | map({
      id: ._id,
      name: ( ( .title
                | gsub("–|—"; ":")
                | split(":")[0]
                | sub("\\s+-\\s.*$"; "")
                | gsub("^\\s+|\\s+$"; "") ) as $n
              | if ($n | length) > 0 then $n else .title end ),
      title: .title
    })
' "$PAGES_DIR"/page-*.json > "$out_file"

written=$(jq 'length' "$out_file")

print_section "Overview (id — budget ADA — title)"
jq -rs '[ .[].data[] ] | .[] | "  \(._id)  \(.metaData.totalBudget // "?")\tADA  \(.title)"' "$PAGES_DIR"/page-*.json

print_section "Summary"
print_pass "Wrote ${written} candidate proposal(s) to $(fmt_path "$out_file")"
print_info "Vote total reported by API: ${total}"
print_warn "This is EVERY submission — the API has no 'successful' filter."
