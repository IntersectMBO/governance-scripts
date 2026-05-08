#!/bin/bash

##################################################

# Default configuration values
INTERSECT_SCHEMAS_BASE="https://intersectmbo.github.io/governance-actions/v1.0.0/schemas"

resolve_context_url() {
  case "$1" in
    info)     echo "${INTERSECT_SCHEMAS_BASE}/info/common.jsonld" ;;
    treasury) echo "${INTERSECT_SCHEMAS_BASE}/treasury-withdrawals/common.jsonld" ;;
    ppu)      echo "${INTERSECT_SCHEMAS_BASE}/parameter-changes/common.jsonld" ;;
    *)        print_fail "No @context mapping for --governance-action-type '$1'"; exit 1 ;;
  esac
}

# Governance action deposit in lovelace (CIP-116 UInt64, encoded as a JSON string).
GOV_ACTION_DEPOSIT="100000000000"
##################################################

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

# Check if pandoc cli is installed
if ! command -v pandoc >/dev/null 2>&1; then
  print_fail "pandoc is not installed or not in your PATH."
  exit 1
fi

# Check if cardano-cli is installed (needed for deposit querying)
if ! command -v cardano-cli >/dev/null 2>&1; then
  print_warn "cardano-cli is not installed. Deposit amount will need to be provided manually."
fi

# Usage message
usage() {
    printf '%s%sCreate JSON-LD metadata from a Markdown file%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<.md-file> --governance-action-type%s <info|treasury|ppu> %s--deposit-return-addr%s <stake-address> [%s--inline-context%s]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<.md-file>"                                  "Path to the .md file as input"
    print_usage_option "--governance-action-type <info|treasury|ppu>" "Type of governance action"
    print_usage_option "--deposit-return-addr <stake-address>"        "Stake address for deposit return (bech32)"
    print_usage_option "[--inline-context]"                           "Embed the full @context object in the document instead of referencing the URL"
    print_usage_option "-h, --help"                                   "Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_file=""
governance_action_type=""
deposit_return_address=""
inline_context="false"

# Create temporary files in /tmp/
TEMP_MD=$(mktemp /tmp/metadata_create_md.XXXXXX)
TEMP_OUTPUT_JSON=$(mktemp /tmp/metadata_create_temp.XXXXXX)
TEMP_CONTEXT=$(mktemp /tmp/metadata_create_context.XXXXXX)
TEMP_TITLE=$(mktemp /tmp/metadata_create_title.XXXXXX)
TEMP_ABSTRACT=$(mktemp /tmp/metadata_create_abstract.XXXXXX)
TEMP_MOTIVATION=$(mktemp /tmp/metadata_create_motivation.XXXXXX)
TEMP_RATIONALE=$(mktemp /tmp/metadata_create_rationale.XXXXXX)
TEMP_REFERENCES=$(mktemp /tmp/metadata_create_references.XXXXXX)
TEMP_ONCHAIN=$(mktemp /tmp/metadata_create_onchain.XXXXXX)

# Cleanup function to remove temporary files
cleanup() {
  rm -f "$TEMP_MD" "$TEMP_OUTPUT_JSON" "$TEMP_CONTEXT" \
        "$TEMP_TITLE" "$TEMP_ABSTRACT" "$TEMP_MOTIVATION" \
        "$TEMP_RATIONALE" "$TEMP_REFERENCES" "$TEMP_ONCHAIN"
}

# Set trap to cleanup on any script
trap cleanup EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --governance-action-type)
            if [ -n "${2:-}" ]; then
                governance_action_type="$2"
                shift 2
            else
                print_fail "--governance-action-type requires a value"
                usage
            fi
            ;;
        --deposit-return-addr)
            if [ -n "${2:-}" ]; then
                deposit_return_address="$2"
                shift 2
            else
                print_fail "--deposit-return-addr requires a value"
                usage
            fi
            ;;
        --inline-context)
            inline_context="true"
            shift
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

# Enforce .md extension — the script parses Markdown H2 sections (## Title, ## Abstract, ...)
if [[ "$input_file" != *.md ]]; then
  print_fail "Input file $(fmt_path "$input_file") must be a Markdown file with a .md extension."
  print_hint "This script expects a Markdown document structured with H2 sections (## Title, ## Abstract, ## Motivation, ## Rationale, ## References, ## Authors)."
  exit 1
fi

# Ensure the input file actually exists
if [ ! -f "$input_file" ]; then
  print_fail "Input file $(fmt_path "$input_file") not found."
  exit 1
fi

# If no governance action type provided, show usage
if [ -z "$governance_action_type" ]; then
  print_fail "--governance-action-type is required"
  usage
fi

# If no deposit return address provided, show usage
if [ -z "$deposit_return_address" ]; then
  print_fail "--deposit-return-addr is required"
  usage
fi

# Validate deposit return address as a Bech32 stake address (mainnet or testnet).
# Cardano stake addresses are 53-54 chars after the prefix; we accept any bech32-ish tail
# and let downstream tooling reject malformed payloads.
if [[ ! "$deposit_return_address" =~ ^(stake1|stake_test1)[a-zA-Z0-9]+$ ]]; then
  print_fail "--deposit-return-addr must be a Bech32 stake address (e.g. stake1... or stake_test1...). Got: $(fmt_path "$deposit_return_address")"
  exit 1
fi

print_banner "Creating a governance action metadata file from a markdown file"
print_info "This script assumes a basic structure for the markdown file, using H2 headers"
print_info "This script uses CIP169 governance metadata extension with CIP-116 ProposalProcedure format"

# Generate output filename: same directory and name as input, but with .jsonld extension
input_dir=$(dirname "$input_file")
input_basename=$(basename "$input_file")
input_name="${input_basename%.*}"
FINAL_OUTPUT_JSON="$input_dir/$input_name.jsonld"

# Copy the markdown file to temp location for processing
cp "$input_file" "$TEMP_MD"

# Clean up escaped characters in markdown
# Usable sed (for macOS + Linux)
portable_sed() {
  # If this returns 0, sed is GNU (Linux); if not, it's BSD (macOS)
  if sed --version >/dev/null 2>&1; then
    # GNU(linux)
    sed -E -i "$1" "$2"
  else
    # BSD(macOS)
    sed -E -i '' "$1" "$2"
  fi
}
# Remove extra backslashes before special characters that don't need escaping in JSON
portable_sed 's/\\-/-/g' "$TEMP_MD"
portable_sed 's/\\_/_/g' "$TEMP_MD"
portable_sed 's/\\\./\./g' "$TEMP_MD"
portable_sed 's/\\\?/\?/g' "$TEMP_MD"
portable_sed 's/\\\+/\+/g' "$TEMP_MD"
portable_sed 's/\\\^/\^/g' "$TEMP_MD"
portable_sed 's/\\\$/\\$/g' "$TEMP_MD"
# Fix common markdown escaping issues
portable_sed 's/\\\&/\&/g' "$TEMP_MD"
portable_sed 's/\\\#/#/g' "$TEMP_MD"
portable_sed 's/\\\:/:/g' "$TEMP_MD"
portable_sed 's/\\\;/\;/g' "$TEMP_MD"
# Handle asterisks - only remove backslash if not part of markdown formatting
portable_sed 's/\\\*([^*])/\*\1/g' "$TEMP_MD"

extract_section() {
  local start="$1"
  local next="$2"
  awk "/^${start}\$/,/^${next}\$/" "$TEMP_MD" | sed "1d;\$d"
}

get_section() {
  local label="$1"
  local next="$2"
  extract_section "$label" "$next" \
    | jq -Rs .
}

get_section_last() {
  local label="$1"
  awk "/^${label}\$/ {found=1; next} /^## References$/ {found=0} found" "$TEMP_MD" | jq -Rs .

}

# Preflight: every section the schema marks as required must appear as an H2 in the
# Markdown source. Without this, get_section silently returns an empty string and
# downstream validation fails far from the cause.
require_sections() {
  local missing=()
  local section
  for section in "$@"; do
    if ! grep -qE "^${section}\$" "$TEMP_MD"; then
      missing+=("$section")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    print_fail "Markdown source is missing required H2 section(s): ${missing[*]}"
    print_hint "Each required section must appear on its own line, exactly as: ## Title / ## Abstract / ## Motivation / ## Rationale"
    exit 1
  fi
}

query_governance_state_prev_actions() {
  # Check if cardano-cli is available
  if ! command -v cardano-cli >/dev/null 2>&1; then
    print_warn "cardano-cli not found. Cannot query deposit from chain."
    echo "null"
    return 1
  fi

  # Check if node socket path is set
  if [ -z "${CARDANO_NODE_SOCKET_PATH:-}" ]; then
    print_warn "CARDANO_NODE_SOCKET_PATH not set. Cannot query deposit from chain."
    echo "null"
    return 1
  fi

  # Check if network id is set
  if [ -z "${CARDANO_NODE_NETWORK_ID:-}" ]; then
    print_warn "CARDANO_NODE_NETWORK_ID not set. Cannot query deposit from chain."
    echo "null"
    return 1
  fi

  # Determine network flag
  local network_flag=""
  if [ "$CARDANO_NODE_NETWORK_ID" = "764824073" ] || [ "$CARDANO_NODE_NETWORK_ID" = "mainnet" ]; then
    network_flag="--mainnet"
  else
    network_flag="--testnet-magic $CARDANO_NODE_NETWORK_ID"
  fi

  # Query previous governance state
  local gov_state

  gov_state=$(cardano-cli conway query gov-state | jq -r '.nextRatifyState.nextEnactState.prevGovActionIds')

  if [ -z "$gov_state" ] || [ "$gov_state" = "null" ] || [ "$gov_state" = "" ]; then
    print_warn "Could not query governance state from chain."
    echo "null"
    return 1
  fi

  echo "$gov_state"
  return 0
}
# Extract references from References section
extract_references() {
  awk '
  BEGIN {
    in_refs = 0
    ref_count = 0
  }

  /^## References$/ { in_refs = 1; next }
  /^## Authors$/ { in_refs = 0; next }

  in_refs {
    # Skip empty lines
    if ($0 ~ /^\s*$/) next

    # Check for markdown link format: * [label](url)
    if ($0 ~ /^\* \[.*\]\(.*\)/) {
      # Extract label from markdown link [label](url)
      label = $0
      sub(/^\* \[/, "", label)
      sub(/\]\(.*\).*$/, "", label)

      # Extract URL from markdown link
      uri = $0
      sub(/^.*\(/, "", uri)
      sub(/\).*$/, "", uri)

      # Clean up quotes in label and URI
      gsub(/"/, "\\\"", label)
      gsub(/"/, "\\\"", uri)

      # Add reference
      refs[ref_count++] = "      {\n        \"@type\": \"Other\",\n        \"label\": \"" label "\",\n        \"uri\": \"" uri "\"\n      }"
    }
  }

  END {
    print "    ["
    for (i = 0; i < ref_count; i++) {
      printf "%s", refs[i]
      if (i < ref_count - 1) print ","
      else print ""
    }
    print "    ]"
  }
  ' "$TEMP_MD"
}

# Generate onChain property for info governance action (CIP-116 ProposalProcedure format)
generate_info_onchain() {
  cat <<EOF
{
  "deposit": "$GOV_ACTION_DEPOSIT",
  "reward_account": "$deposit_return_address",
  "gov_action": {
     "tag": "info_action"
  }
}
EOF
}

# Generate onChain property for ppu governance action (CIP-116 ProposalProcedure format)
generate_ppu_onchain() {
  prev_gov_actions=$(query_governance_state_prev_actions)

  # Note: protocol_param_update field is required for parameter_change_action
  # This is a placeholder - full implementation would require protocol parameter update details
  cat <<EOF
{
  "deposit": "$GOV_ACTION_DEPOSIT",
  "reward_account": "$deposit_return_address",
  "gov_action": {
    "tag": "parameter_change_action",
    "gov_action_id": "TODO: get it from user input as well as from chain",
    "protocol_param_update": {}
  }
}
EOF
}

treasury_collect_inputs() {
  # Prompt & read address from the TTY
  printf 'Please enter withdrawal address: ' >&2
  IFS= read -r T_WITHDRAWAL_ADDRESS </dev/tty

  # Validate address
  if [ -z "$T_WITHDRAWAL_ADDRESS" ]; then
    print_fail "Withdrawal address cannot be empty"
    exit 1
  fi
  if [[ ! "$T_WITHDRAWAL_ADDRESS" =~ ^(stake1|stake_test1)[a-zA-Z0-9]{50,60}$ ]]; then
    print_fail "Invalid bech32 stake address format"
    exit 1
  fi
  print_pass "Withdrawal address valid format!" >&2

  # Try to extract amount from TITLE
  print_info "Attempting to extract withdrawal amount from metadata title..." >&2
  local _title
  _title=$(echo "$TITLE" | jq -r . | tr -d '\n')

  T_RAW_ADA=$(echo "$_title" | sed -n -E 's/.*[₳]([0-9,]+).*/\1/p')
  if [ -z "$T_RAW_ADA" ]; then
    T_RAW_ADA=$(echo "$_title" | sed -n -E 's/.* ([0-9,]+) ADA.*/\1/p')
  fi
  if [ -z "$T_RAW_ADA" ]; then
    T_RAW_ADA=$(echo "$_title" | sed -n -E 's/.* ([0-9,]+) ada.*/\1/p')
  fi

  # If amount not found in title ask the user
  if [ -z "$T_RAW_ADA" ]; then
    print_warn "No withdrawal amount found in title."
    printf 'Please enter withdrawal amount in ada: ' >&2
    IFS= read -r T_RAW_ADA </dev/tty
  fi

  if [ -z "$T_RAW_ADA" ]; then
    print_fail "Withdrawal amount cannot be empty"
    exit 1
  fi

  # Convert ADA -> lovelace
  local _lovelace
  _lovelace=$(echo "$T_RAW_ADA" | tr -d ',' | awk '
    BEGIN{ ok=1 }
    {
      if ($0 !~ /^[0-9]*\.?[0-9]+$/) ok=0;
      amt=$0+0;
      if (amt<=0) ok=0;
      if (ok==1) printf("%.0f", amt*1000000);
    }
    END{ if (ok==0) exit 1 }')
  if [ $? -ne 0 ] || [ -z "$_lovelace" ] || [[ ! "$_lovelace" =~ ^[0-9]+$ ]]; then
    print_fail "Invalid withdrawal amount: ${T_RAW_ADA}"
    exit 1
  fi
  T_LOVELACE="$_lovelace"

  print_info "Final confirmation:" >&2
  print_info "  Amount: ${YELLOW}₳${T_RAW_ADA}${NC} (${T_LOVELACE} lovelace)" >&2
  print_info "  Address: ${YELLOW}${T_WITHDRAWAL_ADDRESS}${NC}" >&2

  # confirm with user
  if ! confirm "Is this correct?"; then
    print_fail "Cancelled by user"
    exit 1
  fi
}

generate_treasury_onchain() {
  # Collect inputs and log to stderr
  treasury_collect_inputs

  # Emit ONLY JSON to stdout (CIP-116 ProposalProcedure format)
  # Convert withdrawals to rewards array with key-value pairs
  cat <<EOF
{
  "deposit": "$GOV_ACTION_DEPOSIT",
  "reward_account": "$deposit_return_address",
  "gov_action": {
    "tag": "treasury_withdrawals_action",
    "rewards": [
      {
        "key": "$T_WITHDRAWAL_ADDRESS",
        "value": "$T_LOVELACE"
      }
    ]
  }
}
EOF
}

# Generate onChain property based on governance action type
generate_onchain_property() {
  local action_type="$1"

  case "$action_type" in
    "info")
      generate_info_onchain
      ;;
    "treasury")
      generate_treasury_onchain
      ;;
    "ppu")
      generate_ppu_onchain
      ;;
    *)
      echo "null"
      ;;
  esac
}

# use helper functions to extract sections
print_section "Extracting sections from Markdown"

require_sections "## Title" "## Abstract" "## Motivation" "## Rationale"

TITLE=$(get_section "## Title" "## Abstract")

# clean newlines from title
TITLE=$(echo "$TITLE" | jq -r . | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -Rs .)
print_info "Title extracted: ${YELLOW}${TITLE}${NC}"

ABSTRACT=$(get_section "## Abstract" "## Motivation")
MOTIVATION=$(get_section "## Motivation" "## Rationale")
RATIONALE=$(get_section_last "## Rationale")

# Generate onChain property based on governance action type
print_info "Generating onChain property for $governance_action_type"
ONCHAIN_PROPERTY=$(generate_onchain_property "$governance_action_type")

# Generate references JSON
REFERENCES_JSON=$(extract_references)

# Resolve the @context URL for this governance action type.
print_section "Resolving @context URL"
CONTEXT_URL=$(resolve_context_url "$governance_action_type")
print_info "Using @context: ${YELLOW}${CONTEXT_URL}${NC}"

# Stage the @context payload. By default we leave a JSON `null` sentinel in
# TEMP_CONTEXT and the final jq emits the URL string. With --inline-context, we
# fetch the canonical document and write its inner @context object so the final
# jq embeds it verbatim.
if [ "$inline_context" = "true" ]; then
  print_info "Inlining @context (fetching ${YELLOW}${CONTEXT_URL}${NC})"
  if ! curl -sSfL "$CONTEXT_URL" | jq -e '."@context"' > "$TEMP_CONTEXT"; then
    print_fail "Failed to fetch or parse @context from $CONTEXT_URL"
    exit 1
  fi
else
  echo 'null' > "$TEMP_CONTEXT"
fi

# Build the metadata JSON-LD with CIP-116 ProposalProcedure format onChain property
# Write each value to a temp file to avoid "Argument list too long" with large markdown.
# --slurpfile reads the file from disk and binds it as a 1-element array,
# which is why every variable below is dereferenced with [0].
printf '%s' "$TITLE"            > "$TEMP_TITLE"
printf '%s' "$ABSTRACT"         > "$TEMP_ABSTRACT"
printf '%s' "$MOTIVATION"       > "$TEMP_MOTIVATION"
printf '%s' "$RATIONALE"        > "$TEMP_RATIONALE"
printf '%s' "$REFERENCES_JSON"  > "$TEMP_REFERENCES"
printf '%s' "$ONCHAIN_PROPERTY" > "$TEMP_ONCHAIN"

jq --arg       context_url "$CONTEXT_URL" \
   --slurpfile context     "$TEMP_CONTEXT" \
   --slurpfile title       "$TEMP_TITLE" \
   --slurpfile abstract    "$TEMP_ABSTRACT" \
   --slurpfile motivation  "$TEMP_MOTIVATION" \
   --slurpfile rationale   "$TEMP_RATIONALE" \
   --slurpfile references  "$TEMP_REFERENCES" \
   --slurpfile onchain     "$TEMP_ONCHAIN" \
   '{
     "@context": (if $context[0] == null then $context_url else $context[0] end),
     "authors": [],
     "hashAlgorithm": "blake2b-256",
     "body": {
       "title": $title[0],
       "abstract": $abstract[0],
       "motivation": $motivation[0],
       "rationale": $rationale[0],
       "references": $references[0],
       "onChain": $onchain[0]
     }
   }' <<< '{}' > "$TEMP_OUTPUT_JSON"

print_info "Formatting JSON output"

# Use jq to format the JSON output
jq . "$TEMP_OUTPUT_JSON" > "$FINAL_OUTPUT_JSON"

# Clean up extra newlines at start and end of string fields
print_info "Cleaning up extra newlines"
jq '
  .body.title = (.body.title | gsub("^\\n+"; "") | gsub("\\n+$"; "")) |
  .body.abstract = (.body.abstract | gsub("^\\n+"; "") | gsub("\\n+$"; "")) |
  .body.motivation = (.body.motivation | gsub("^\\n+"; "") | gsub("\\n+$"; "")) |
  .body.rationale = (.body.rationale | gsub("^\\n+"; "") | gsub("\\n+$"; ""))
' "$FINAL_OUTPUT_JSON" > "$TEMP_OUTPUT_JSON" && mv "$TEMP_OUTPUT_JSON" "$FINAL_OUTPUT_JSON"

print_section "Summary"
print_pass "JSON-LD metadata created"
print_kv "Input"    "$(fmt_path "$input_file")"
print_kv "Output"   "$(fmt_path "$FINAL_OUTPUT_JSON")"
print_kv "Type"     "$governance_action_type"
print_kv "@context" "$CONTEXT_URL"
print_next "Validate the document (still pre-signing, so use --draft):" \
           "  ./scripts/metadata-validate.sh '$FINAL_OUTPUT_JSON' --cip108 --cip169 --draft"
