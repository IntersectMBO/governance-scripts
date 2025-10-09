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
    echo "  --governance-action-type <info|treasury>      Type of governance action (info, treasury, etc.)"
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
  echo -e "${RED}Error: --deposit-return-addr is required for treasuryWithdrawals${NC}" >&2
  usage
fi

echo -e " "
echo -e "${YELLOW}Creating a governance action metadata file from a markdown file${NC}"
echo -e "${CYAN}This script assumes a basic structure for the markdown file${NC}"
echo -e "${CYAN}This script uses Intersect's governance action schemas (extended CIP108)${NC}"

# Generate output filename: same directory and name as input, but with .jsonld extension
input_dir=$(dirname "$input_file")
input_basename=$(basename "$input_file")
input_name="${input_basename%.*}"
FINAL_OUTPUT_JSON="$input_dir/$input_name.jsonld"

echo " "
echo -e "${CYAN}Converting $input_basename to CIP108+ (Intersect schema) metadata...${NC}"

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
  awk "/^${label}\$/,/^### References\$/" "$TEMP_MD" | sed "1d" \
    | jq -Rs .
}

# Extract references from References section
extract_references() {
  awk '
  BEGIN {
    in_refs = 0
    ref_count = 0
  }

  /^### References$/ { in_refs = 1; next }
  /^### Authors$/ { in_refs = 0; next }

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

# Generate onChain property for treasury governance action
generate_treasury_onchain() {
  # Extract withdrawal amount from the title
  WITHDRAWAL_AMOUNT_RAW=$(echo "$TITLE" | jq -r . | tr -d '\n' | sed -n 's/.*₳\([0-9,]*\).*/\1/p')  
  # If no amount found, prompt user
  if [ -z "$WITHDRAWAL_AMOUNT_RAW" ]; then
    read -p "No withdrawal amount found in title. Please enter amount in ADA: " WITHDRAWAL_AMOUNT_RAW
  fi

  # Remove commas and add 6 zeros (convert to lovelace)
  WITHDRAWAL_AMOUNT=$(echo "$WITHDRAWAL_AMOUNT_RAW" | tr -d ',' | sed 's/$/000000/')
  
  # Validate withdrawal amount
  if [[ ! "$WITHDRAWAL_AMOUNT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Invalid withdrawal amount: $WITHDRAWAL_AMOUNT${NC}" >&2
    exit 1
  fi
  
  # Prompt user for withdrawal address
  echo -e "Withdrawal amount detected: ${YELLOW}₳$WITHDRAWAL_AMOUNT_RAW${NC}"
  read -p "Please enter the desired withdrawal address (bech32): " withdrawal_address
  
  # Validate the withdrawal address format
  if [[ ! "$withdrawal_address" =~ ^(stake1|stake_test1)[a-zA-Z0-9]{50,60}$ ]]; then
    echo -e "${RED}Error: Invalid bech32 stake address format${NC}" >&2
    exit 1
  fi
  
  echo -e "Withdrawal address: ${YELLOW}$withdrawal_address${NC}"
  echo -e "Withdrawal amount: ${YELLOW}₳$WITHDRAWAL_AMOUNT_RAW${NC} (${WITHDRAWAL_AMOUNT} lovelace)"

  read -p "Do you want to proceed with this withdrawal address and amount? (yes/no): " confirm_withdrawal
  if [ "$confirm_withdrawal" != "yes" ]; then
    echo -e "${RED}Withdrawal address and amount not confirmed by user, exiting.${NC}"
    exit 1
  fi
  
  cat <<EOF
{
  "governanceActionType": "treasuryWithdrawals",
  "depositReturnAddress": "$deposit_return_address",
  "withdrawals": [
    {
      "withdrawalAddress": "$withdrawal_address",
      "withdrawalAmount": $WITHDRAWAL_AMOUNT
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
    *)
      echo "null"
      ;;
  esac
}

# use helper functions to extract sections
echo -e "Extracting sections from Markdown"

TITLE=$(get_section "## Title" "## Abstract")
ABSTRACT=$(get_section "## Abstract" "## Motivation")
MOTIVATION=$(get_section "## Motivation" "## Rationale")
RATIONALE=$(get_section_last "## Rationale")

# Generate onChain property based on governance action type
echo -e "Generating onChain property for $governance_action_type"
ONCHAIN_PROPERTY=$(generate_onchain_property "$governance_action_type")

# Generate references JSON
REFERENCES_JSON=$(extract_references)

# Replace the cat <<EOF section (around line 249) with:
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

echo -e " "
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
echo " "
