#!/bin/bash

##################################################

# Default configuration values
METADATA_COMMON_URL="https://raw.githubusercontent.com/IntersectMBO/governance-actions/refs/heads/main/schemas/common.jsonld"

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

# Check if pandoc cli is installed
if ! command -v pandoc >/dev/null 2>&1; then
  echo "Error: pandoc is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message
usage() {
    echo " "
    echo "Usage: $0 <.md-file> --governance-action-type <info|treasury> --deposit-return-addr <stake-address>"
    echo "Options:"
    echo "  <.md-file>                                    Path to the .md file as input"
    echo "  --governance-action-type <info|treasury|ppu>  Type of governance action (info, treasury, protocol param update, etc.)"
    echo "  --deposit-return-addr <stake-address>         Stake address for deposit return (bech32)"
    echo "  -h, --help                                    Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_file=""
governance_action_type=""
deposit_return_address=""

# Create temporary files in /tmp/
TEMP_MD=$(mktemp /tmp/metadata_create_md.XXXXXX)
TEMP_OUTPUT_JSON=$(mktemp /tmp/metadata_create_temp.XXXXXX)
TEMP_CONTEXT=$(mktemp /tmp/metadata_create_context.XXXXXX)

# Cleanup function to remove temporary files
cleanup() {
  rm -f "$TEMP_MD" "$TEMP_OUTPUT_JSON" "$TEMP_CONTEXT"
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
                echo -e "${RED}Error: --governance-action-type requires a value${NC}" >&2
                usage
            fi
            ;;
        --deposit-return-addr)
            if [ -n "${2:-}" ]; then
                deposit_return_address="$2"
                shift 2
            else
                echo -e "${RED}Error: --deposit-return-addr requires a value${NC}" >&2
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

# If no governance action type provided, show usage
if [ -z "$governance_action_type" ]; then
  echo -e "${RED}Error: --governance-action-type is required${NC}" >&2
  usage
fi

# If no deposit return address provided, show usage
if [ -z "$deposit_return_address" ]; then
  echo -e "${RED}Error: --deposit-return-addr is required${NC}" >&2
  usage
fi

echo -e " "
echo -e "${YELLOW}Creating a governance action metadata file from a markdown file${NC}"
echo -e "${CYAN}This script assumes a basic structure for the markdown file, using H2 headers${NC}"
echo -e "${CYAN}This script uses Intersect's governance action schemas (extended CIP108)${NC}"

# Generate output filename: same directory and name as input, but with .jsonld extension
input_dir=$(dirname "$input_file")
input_basename=$(basename "$input_file")
input_name="${input_basename%.*}"
FINAL_OUTPUT_JSON="$input_dir/$input_name.jsonld"

# Copy the markdown file to temp location for processing
cp "$input_file" "$TEMP_MD"

# Clean up escaped characters in markdown
# Remove extra backslashes before special characters that don't need escaping in JSON
sed -E -i '' 's/\\-/-/g' "$TEMP_MD"
sed -E -i '' 's/\\_/_/g' "$TEMP_MD"
sed -E -i '' 's/\\\./\./g' "$TEMP_MD"
sed -E -i '' 's/\\\?/\?/g' "$TEMP_MD"
sed -E -i '' 's/\\\+/\+/g' "$TEMP_MD"
sed -E -i '' 's/\\\^/\^/g' "$TEMP_MD"
sed -E -i '' 's/\\\$/\\$/g' "$TEMP_MD"
# Fix common markdown escaping issues
sed -E -i '' 's/\\\&/\&/g' "$TEMP_MD"
sed -E -i '' 's/\\\#/#/g' "$TEMP_MD"
sed -E -i '' 's/\\\:/:/g' "$TEMP_MD"
sed -E -i '' 's/\\\;/\;/g' "$TEMP_MD"
# Handle asterisks - only remove backslash if not part of markdown formatting
sed -E -i '' 's/\\\*([^*])/\*\1/g' "$TEMP_MD"

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

# Generate onChain property for info governance action
generate_info_onchain() {
  cat <<EOF
{
  "governanceActionType": "info",
  "depositReturnAddress": "$deposit_return_address"
}
EOF
}

# Generate onChain property for ppu governance action
generate_ppu_onchain() {

  # todo, improve this

  cat <<EOF
{
  "governanceActionType": "protocolParameterChanges",
  "depositReturnAddress": "$deposit_return_address"
}
EOF
}

treasury_collect_inputs() {
  # Prompt & read address from the TTY
  echo -n "Please enter withdrawal address: " >&2
  IFS= read -r T_WITHDRAWAL_ADDRESS </dev/tty

  # Validate address
  if [ -z "$T_WITHDRAWAL_ADDRESS" ]; then
    echo -e "${RED}Error: Withdrawal address cannot be empty${NC}" >&2
    exit 1
  fi
  if [[ ! "$T_WITHDRAWAL_ADDRESS" =~ ^(stake1|stake_test1)[a-zA-Z0-9]{50,60}$ ]]; then
    echo -e "${RED}Error: Invalid bech32 stake address format${NC}" >&2
    exit 1
  fi
  echo -e "${GREEN}Withdrawal address valid format!${NC}" >&2

  # Try to extract amount from TITLE
  echo " " >&2
  echo "Attempting to extract withdrawal amount from metadata title..." >&2
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
    echo -e "${YELLOW}No withdrawal amount found in title.${NC}" >&2
    echo -n "Please enter withdrawal amount in ada: " >&2
    IFS= read -r T_RAW_ADA </dev/tty
  fi

  if [ -z "$T_RAW_ADA" ]; then
    echo -e "${RED}Error: Withdrawal amount cannot be empty${NC}" >&2
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
    echo -e "${RED}Error: Invalid withdrawal amount: ${T_RAW_ADA}${NC}" >&2
    exit 1
  fi
  T_LOVELACE="$_lovelace"

  echo "Final confirmation:" >&2
  echo -e "  Amount: ${YELLOW}₳$T_RAW_ADA${NC} (${T_LOVELACE} lovelace)" >&2
  echo -e "  Address: ${YELLOW}$T_WITHDRAWAL_ADDRESS${NC}" >&2

  # confirm with user
  echo -n "Is this correct? (y/n): " >&2
  IFS= read -r confirm </dev/tty
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted by user.${NC}" >&2
    exit 1
  fi
}

generate_treasury_onchain() {
  # Collect inputs and log to stderr
  treasury_collect_inputs

  # Emit ONLY JSON to stdout
  cat <<EOF
{
  "governanceActionType": "treasuryWithdrawals",
  "depositReturnAddress": "$deposit_return_address",
  "withdrawals": [
    {
      "withdrawalAddress": "$T_WITHDRAWAL_ADDRESS",
      "withdrawalAmount": $T_LOVELACE
    }
  ]
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
echo " "
echo -e "Extracting sections from Markdown"

TITLE=$(get_section "## Title" "## Abstract")

# clean newlines from title
TITLE=$(echo "$TITLE" | jq -r . | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -Rs .)
echo -e "Title extracted: ${YELLOW}$TITLE${NC}"

ABSTRACT=$(get_section "## Abstract" "## Motivation")
MOTIVATION=$(get_section "## Motivation" "## Rationale")
RATIONALE=$(get_section_last "## Rationale")

# Generate onChain property based on governance action type
echo -e " "
echo -e "Generating onChain property for $governance_action_type"
ONCHAIN_PROPERTY=$(generate_onchain_property "$governance_action_type")

# Generate references JSON
REFERENCES_JSON=$(extract_references)

# Replace the cat <<EOF section (around line 249) with:
echo -e " "
echo -e "${CYAN}Downloading context from $METADATA_COMMON_URL...${NC}"
if ! curl -sSfL "$METADATA_COMMON_URL" -o "$TEMP_CONTEXT"; then
    echo -e "${RED}Error: Failed to download context from $METADATA_COMMON_URL${NC}" >&2
    exit 1
fi

jq --argjson context "$(cat "$TEMP_CONTEXT")" \
   --argjson title "$TITLE" \
   --argjson abstract "$ABSTRACT" \
   --argjson motivation "$MOTIVATION" \
   --argjson rationale "$RATIONALE" \
   --argjson references "$REFERENCES_JSON" \
   --argjson onchain "$ONCHAIN_PROPERTY" \
   '{
     "@context": $context,
     "authors": [],
     "hashAlgorithm": "blake2b-256",
     "body": {
       "title": $title,
       "abstract": $abstract,
       "motivation": $motivation,
       "rationale": $rationale,
       "references": $references,
       "onChain": $onchain
     }
   }' <<< '{}' > "$TEMP_OUTPUT_JSON"

echo -e "${CYAN}Formatting JSON output...${NC}"

# Use jq to format the JSON output
jq . "$TEMP_OUTPUT_JSON" > "$FINAL_OUTPUT_JSON"

# Clean up extra newlines at start and end of string fields
echo -e "${CYAN}Cleaning up extra newlines...${NC}"
jq '
  .body.title = (.body.title | gsub("^\\n+"; "") | gsub("\\n+$"; "")) |
  .body.abstract = (.body.abstract | gsub("^\\n+"; "") | gsub("\\n+$"; "")) |
  .body.motivation = (.body.motivation | gsub("^\\n+"; "") | gsub("\\n+$"; "")) |
  .body.rationale = (.body.rationale | gsub("^\\n+"; "") | gsub("\\n+$"; ""))
' "$FINAL_OUTPUT_JSON" > "$TEMP_OUTPUT_JSON" && mv "$TEMP_OUTPUT_JSON" "$FINAL_OUTPUT_JSON"

echo " "
echo -e "${GREEN}JSONLD metadata successfully created! Output: $FINAL_OUTPUT_JSON ${NC}"
echo -e "${GREEN}Output: $FINAL_OUTPUT_JSON ${NC}"
echo " "
