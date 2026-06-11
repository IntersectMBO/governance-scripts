#!/bin/bash
#
# budget-metadata-build.sh
#
# Build the CIP-108/CIP-169 treasury-withdrawal metadata for ONE 2026 budget
# proposal: fetch the proposal from the hydra voting API, fill the standardised
# template (scripts/budget-2026/template.md), then hand the resulting Markdown to
# the existing metadata-create.sh to produce an unsigned .jsonld.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUDGET_DIR="$SCRIPT_DIR"
# shellcheck source=../lib/messages.sh
source "$SCRIPTS_DIR/lib/messages.sh"

CONFIG_FILE="$BUDGET_DIR/config.sh"
TEMPLATE_FILE="$BUDGET_DIR/template.md"
DEFAULT_OUT_DIR="$BUDGET_DIR/output"
MAX_TITLE_LEN=80

# --- dependencies ---
for dep in curl jq awk; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    print_fail "$dep is not installed or not in your PATH."
    exit 1
  fi
done

usage() {
    printf '%s%sBuild treasury-withdrawal metadata for one 2026 budget proposal%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<proposal-id>%s [%s--name%s <project-name>] [%s--file-name%s <stem>] [%s--out-dir%s <dir>]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<proposal-id>"        "Hydra proposal _id (e.g. 69fdc9b261c4f060e2fef6c9)"
    print_usage_option "[--name <name>]"      "Human-readable project name. Used in the on-chain title (truncated to fit 80 chars) and slugified for output filenames. Defaults to the hydra title / proposal id."
    print_usage_option "[--file-name <stem>]" "Override just the output filename stem (slugified). Defaults to the slug of --name. Useful to disambiguate same-named proposals."
    print_usage_option "[--out-dir <dir>]"    "Output directory (default: $(fmt_path "$DEFAULT_OUT_DIR"))"
    print_usage_option "-h, --help"           "Show this help message and exit"
    exit 1
}

# Filesystem-safe slug from a human-readable name: lowercase, non-alphanumerics to
# hyphens, collapsed and trimmed.
slugify() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# --- args ---
proposal_id=""
proj_name=""
file_name=""
out_dir="$DEFAULT_OUT_DIR"

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            if [ -n "${2:-}" ]; then proj_name="$2"; shift 2; else print_fail "--name requires a value"; usage; fi ;;
        --file-name)
            if [ -n "${2:-}" ]; then file_name="$2"; shift 2; else print_fail "--file-name requires a value"; usage; fi ;;
        --out-dir)
            if [ -n "${2:-}" ]; then out_dir="$2"; shift 2; else print_fail "--out-dir requires a value"; usage; fi ;;
        -h|--help)
            usage ;;
        *)
            if [ -z "$proposal_id" ]; then proposal_id="$1"; else print_fail "Unexpected argument: $1"; usage; fi
            shift ;;
    esac
done

[ -z "$proposal_id" ] && { print_fail "No proposal id specified"; usage; }
[ -f "$CONFIG_FILE" ]   || { print_fail "Config not found: $(fmt_path "$CONFIG_FILE")"; exit 1; }
[ -f "$TEMPLATE_FILE" ] || { print_fail "Template not found: $(fmt_path "$TEMPLATE_FILE")"; exit 1; }

# Output filename stem: explicit --file-name wins, else slug of the project name,
# falling back to the proposal id.
out_name="$proposal_id"
if [ -n "$file_name" ]; then
    out_name="$(slugify "$file_name")"
elif [ -n "$proj_name" ]; then
    out_name="$(slugify "$proj_name")"
fi
[ -z "$out_name" ] && out_name="$proposal_id"

# shellcheck source=config.sh
source "$CONFIG_FILE"

print_banner "Building 2026 budget metadata for proposal $proposal_id"

# Warn (don't block) on un-filled config so dry runs still work.
for var in WITHDRAWAL_ADDR DEPOSIT_RETURN_ADDR TRSC_STAKE_ADDR TRSC_PAYMENT_ADDR PSSC_PAYMENT_ADDR SUCCESSFUL_PROPOSALS_CSV_URL; do
    if [[ "${!var:-}" == *REPLACEME* ]]; then
        print_warn "config.sh: $var still contains a REPLACEME placeholder."
    fi
done

mkdir -p "$out_dir"

# --- fetch ---
print_section "Fetching proposal from hydra"
PROPOSAL_JSON=$(mktemp /tmp/budget_proposal.XXXXXX)
cleanup() { rm -f "$PROPOSAL_JSON"; }
trap cleanup EXIT

api_url="${HYDRA_API_BASE%/}/proposals/$proposal_id"
print_info "GET ${YELLOW}${api_url}${NC}"
if ! curl -sSfL "$api_url" -o "$PROPOSAL_JSON"; then
    print_fail "Failed to fetch proposal from $api_url"
    exit 1
fi
if ! jq empty "$PROPOSAL_JSON" >/dev/null 2>&1; then
    print_fail "Hydra response was not valid JSON."
    exit 1
fi

# --- extract fields ---
FULL_TITLE=$(jq -r '.title // empty' "$PROPOSAL_JSON")
SUMMARY=$(jq -r '.summary // empty' "$PROPOSAL_JSON")
PILLAR=$(jq -r '.metaData.strategyFramework.pillarRationale // empty' "$PROPOSAL_JSON")
total_budget=$(jq -r '.metaData.totalBudget // empty' "$PROPOSAL_JSON")

[ -z "$FULL_TITLE" ] && { print_fail "Proposal has no 'title' field."; exit 1; }
[ -z "$total_budget" ] && { print_fail "Proposal has no 'totalBudget' field."; exit 1; }
if [[ ! "$total_budget" =~ ^[0-9]+$ ]]; then
    print_fail "totalBudget is not a whole number of ADA: '$total_budget'"
    print_hint "Expected an integer ADA amount; got a non-integer. Verify the proposal data."
    exit 1
fi
[ -z "$SUMMARY" ] && print_warn "Proposal 'summary' is empty (Motivation will be blank)."
[ -z "$PILLAR" ] && print_warn "Proposal 'metaData.strategyFramework.pillarRationale' is empty."

print_kv "Title"        "$FULL_TITLE"
print_kv "Total budget" "${total_budget} ADA"

# --- amount, formatted with thousands separators (kept parseable by metadata-create) ---
format_commas() {
    awk -v n="$1" 'BEGIN{
        len=length(n); out="";
        for(i=1;i<=len;i++){ out=out substr(n,i,1); rem=len-i; if(rem>0 && rem%3==0) out=out","; }
        print out;
    }'
}
AMOUNT=$(format_commas "$total_budget")

# --- compose the on-chain title, truncating the project name to fit 80 chars ---
name_for_title="$FULL_TITLE"
[ -n "$proj_name" ] && name_for_title="$proj_name"

prefix="Withdraw ${AMOUNT} ada for "
suffix=" administered by Intersect"
avail=$(( MAX_TITLE_LEN - ${#prefix} - ${#suffix} ))

TITLE_NAME="$name_for_title"
if [ "$avail" -lt 1 ]; then
    print_warn "Fixed title wording leaves no room for a project name within ${MAX_TITLE_LEN} chars."
    TITLE_NAME=""
elif [ "${#name_for_title}" -gt "$avail" ]; then
    TITLE_NAME="${name_for_title:0:$avail}"
    # prefer a clean word boundary, then trim trailing space/punctuation
    [[ "$TITLE_NAME" == *" "* ]] && TITLE_NAME="${TITLE_NAME% *}"
    TITLE_NAME="$(printf '%s' "$TITLE_NAME" | sed -E 's/[[:space:],:;.-]+$//')"
    print_warn "Title name truncated to fit ${MAX_TITLE_LEN} chars (full title preserved in the abstract)."
fi

composed_title="${prefix}${TITLE_NAME}${suffix}"
if [ "${#composed_title}" -gt "$MAX_TITLE_LEN" ]; then
    print_fail "Composed title is ${#composed_title} chars (> ${MAX_TITLE_LEN}). Set a shorter --name."
    exit 1
fi
print_kv "On-chain title" "$composed_title"

# --- render the template ---
print_section "Rendering template"
md_file="$out_dir/$out_name.md"

export AMOUNT TITLE_NAME FULL_TITLE SUMMARY PILLAR
export PROPOSAL_LINK="${HYDRA_PROPOSAL_URL_BASE%/}/$proposal_id"
export TRSC_STAKE_ADDR TRSC_PAYMENT_ADDR PSSC_PAYMENT_ADDR
export CSV_URL="$SUCCESSFUL_PROPOSALS_CSV_URL"

awk '
    function lrep(s, tok, val,   p, out) {
        out=""
        while ((p=index(s, tok)) > 0) {
            out = out substr(s, 1, p-1) val
            s = substr(s, p+length(tok))
        }
        return out s
    }
    {
        line=$0
        line=lrep(line, "{{WITHDRAW_AMOUNT}}",          ENVIRON["AMOUNT"])
        line=lrep(line, "{{TITLE_NAME}}",               ENVIRON["TITLE_NAME"])
        line=lrep(line, "{{FULL_TITLE}}",               ENVIRON["FULL_TITLE"])
        line=lrep(line, "{{PROJECT_HIGH_LEVEL}}",       ENVIRON["SUMMARY"])
        line=lrep(line, "{{PILLAR_RATIONALE}}",         ENVIRON["PILLAR"])
        line=lrep(line, "{{HYDRA_PROPOSAL_LINK}}",      ENVIRON["PROPOSAL_LINK"])
        line=lrep(line, "{{TRSC_STAKE_ADDR}}",          ENVIRON["TRSC_STAKE_ADDR"])
        line=lrep(line, "{{TRSC_PAYMENT_ADDR}}",        ENVIRON["TRSC_PAYMENT_ADDR"])
        line=lrep(line, "{{PSSC_PAYMENT_ADDR}}",        ENVIRON["PSSC_PAYMENT_ADDR"])
        line=lrep(line, "{{SUCCESSFUL_PROPOSALS_CSV}}", ENVIRON["CSV_URL"])
        print line
    }
' "$TEMPLATE_FILE" > "$md_file"

print_pass "Markdown written to $(fmt_path "$md_file")"

# --- hand off to metadata-create.sh (produces unsigned <name>.jsonld) ---
print_section "Creating JSON-LD via metadata-create.sh"
"$SCRIPTS_DIR/metadata-create.sh" "$md_file" \
    --governance-action-type treasury \
    --deposit-return-addr "$DEPOSIT_RETURN_ADDR" \
    --withdrawal-addr "$WITHDRAWAL_ADDR"

print_section "Summary"
print_pass "Built unsigned metadata for proposal $proposal_id"
print_kv "Markdown" "$(fmt_path "$md_file")"
print_kv "JSON-LD"  "$(fmt_path "$out_dir/$out_name.jsonld")"
print_next "Validate it (pre-signing):" \
           "  ./scripts/budget-2026/budget-metadata-validate-all.sh"
