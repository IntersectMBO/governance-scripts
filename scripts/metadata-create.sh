#!/bin/bash

##################################################

# Default configuration values
METADATA_169_COMMON_URL="https://raw.githubusercontent.com/Ryun1/CIPs/refs/heads/cip-governance-metadata-extension/cip-governance-metadata-extension/cip169.common.jsonld"
METADATA_108_COMMON_URL="https://raw.githubusercontent.com/Ryun1/CIPs/refs/heads/cip-governance-metadata-extension/CIP-0108/cip-0108.common.jsonld"
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
UNDERLINE='\033[4m'
BOLD='\033[1m'
GRAY='\033[0;90m'

# Check if pandoc cli is installed
if ! command -v pandoc >/dev/null 2>&1; then
  echo -e "${RED}Error: pandoc is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Check if cardano-cli is installed (needed for deposit querying)
if ! command -v cardano-cli >/dev/null 2>&1; then
  echo -e "${YELLOW}Warning: cardano-cli is not installed. Deposit amount will need to be provided manually.${NC}" >&2
fi

# Usage message
usage() {
    local col=50
    echo -e "${UNDERLINE}${BOLD}Create JSON-LD metadata from a Markdown file${NC}"
    echo -e "\n"
    echo -e "Syntax:${BOLD} $0 ${GREEN}<.md-file> --governance-action-type ${NC}<info|treasury|ppu> ${GREEN}--deposit-return-addr ${NC}<stake-address>"
    printf "Params: ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "<.md-file>" "- Path to the .md file as input"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "--governance-action-type <info|treasury|ppu>" "- Type of governance action"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "--deposit-return-addr <stake-address>" "- Stake address for deposit return (bech32)"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "-h, --help" "- Show this help message and exit"
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
echo -e "${CYAN}This script uses CIP169 governance metadata extension with CIP-116 ProposalProcedure format${NC}"

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

# Query governance action deposit from chain (required for CIP-116 ProposalProcedure format)
# Returns the deposit amount in lovelace, or "null" if query fails
query_governance_deposit() {
  # Check if cardano-cli is available
  if ! command -v cardano-cli >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: cardano-cli not found. Cannot query deposit from chain.${NC}" >&2
    echo "null"
    return 1
  fi

  # Check if node socket path is set
  if [ -z "${CARDANO_NODE_SOCKET_PATH:-}" ]; then
    echo -e "${YELLOW}Warning: CARDANO_NODE_SOCKET_PATH not set. Cannot query deposit from chain.${NC}" >&2
    echo "null"
    return 1
  fi

  # Check if network id is set
  if [ -z "${CARDANO_NODE_NETWORK_ID:-}" ]; then
    echo -e "${YELLOW}Warning: CARDANO_NODE_NETWORK_ID not set. Cannot query deposit from chain.${NC}" >&2
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

  # Query deposit amount
  local deposit
  deposit=$(cardano-cli conway query gov-state $network_flag 2>/dev/null | jq -r '.currentPParams.govActionDeposit // empty' 2>/dev/null)

  if [ -z "$deposit" ] || [ "$deposit" = "null" ] || [ "$deposit" = "" ]; then
    echo -e "${YELLOW}Warning: Could not query deposit from chain.${NC}" >&2
    echo "null"
    return 1
  fi

  echo "$deposit"
  return 0
}

# Query governance action deposit from chain (required for CIP-116 ProposalProcedure format)
# Returns the deposit amount in lovelace, or "null" if query fails
query_governance_deposit() {
  # Check if cardano-cli is available
  if ! command -v cardano-cli >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: cardano-cli not found. Cannot query deposit from chain.${NC}" >&2
    echo "null"
    return 1
  fi

  # Check if node socket path is set
  if [ -z "${CARDANO_NODE_SOCKET_PATH:-}" ]; then
    echo -e "${YELLOW}Warning: CARDANO_NODE_SOCKET_PATH not set. Cannot query deposit from chain.${NC}" >&2
    echo "null"
    return 1
  fi

  # Check if network id is set
  if [ -z "${CARDANO_NODE_NETWORK_ID:-}" ]; then
    echo -e "${YELLOW}Warning: CARDANO_NODE_NETWORK_ID not set. Cannot query deposit from chain.${NC}" >&2
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

  # Query deposit amount
  local deposit
  deposit=$(cardano-cli conway query gov-state $network_flag 2>/dev/null | jq -r '.currentPParams.govActionDeposit // empty' 2>/dev/null)

  if [ -z "$deposit" ] || [ "$deposit" = "null" ] || [ "$deposit" = "" ]; then
    echo -e "${YELLOW}Warning: Could not query deposit from chain.${NC}" >&2
    echo "null"
    return 1
  fi

  echo "$deposit"
  return 0
}

query_governance_state_prev_actions() {
  # Check if cardano-cli is available
  if ! command -v cardano-cli >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: cardano-cli not found. Cannot query deposit from chain.${NC}" >&2
    echo "null"
    return 1
  fi

  # Check if node socket path is set
  if [ -z "${CARDANO_NODE_SOCKET_PATH:-}" ]; then
    echo -e "${YELLOW}Warning: CARDANO_NODE_SOCKET_PATH not set. Cannot query deposit from chain.${NC}" >&2
    echo "null"
    return 1
  fi

  # Check if network id is set
  if [ -z "${CARDANO_NODE_NETWORK_ID:-}" ]; then
    echo -e "${YELLOW}Warning: CARDANO_NODE_NETWORK_ID not set. Cannot query deposit from chain.${NC}" >&2
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
    echo -e "${YELLOW}Warning: Could not query governance state from chain.${NC}" >&2
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
  local deposit_amount
  deposit_amount=$(query_governance_deposit)
  
  # If deposit query failed, use null (JSON null, not string)
  local deposit_json
  if [ "$deposit_amount" = "null" ] || [ -z "$deposit_amount" ]; then
    deposit_json="null"
  else
    deposit_json="$deposit_amount"
  fi

  cat <<EOF
{
  "deposit": $deposit_json,
  "reward_account": "$deposit_return_address",
  "gov_action": {
     "tag": "info_action"
  }
}
EOF
}

# Generate onChain property for ppu governance action (CIP-116 ProposalProcedure format)
generate_ppu_onchain() {
  local deposit_amount
  deposit_amount=$(query_governance_deposit)
  
  # If deposit query failed, use null (JSON null, not string)
  local deposit_json
  if [ "$deposit_amount" = "null" ] || [ -z "$deposit_amount" ]; then
    deposit_json="null"
  else
    deposit_json="$deposit_amount"
  fi

  prev_gov_actions=$(query_governance_state_prev_actions)

  # Note: protocol_param_update field is required for parameter_change_action
  # This is a placeholder - full implementation would require protocol parameter update details
  cat <<EOF
{
  "deposit": $deposit_json,
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

  local deposit_amount
  deposit_amount=$(query_governance_deposit)
  
  # If deposit query failed, use null (JSON null, not string)
  local deposit_json
  if [ "$deposit_amount" = "null" ] || [ -z "$deposit_amount" ]; then
    deposit_json="null"
  else
    deposit_json="$deposit_amount"
  fi

  # Emit ONLY JSON to stdout (CIP-116 ProposalProcedure format)
  # Convert withdrawals to rewards array with key-value pairs
  cat <<EOF
{
  "@type": "ProposalProcedure",
  "deposit": $deposit_json,
  "reward_account": "$deposit_return_address",
  "gov_action": {
    "tag": "treasury_withdrawals_action",
    "rewards": [
      {
        "key": "$T_WITHDRAWAL_ADDRESS",
        "value": $T_LOVELACE
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

# Download contexts from both CIP-108 and CIP-169 and merge them
echo -e " "
echo -e "${CYAN}Downloading CIP-108 context from $METADATA_108_COMMON_URL...${NC}"
TEMP_CIP108=$(mktemp /tmp/metadata_create_cip108.XXXXXX)
if ! curl -sSfL "$METADATA_108_COMMON_URL" -o "$TEMP_CIP108"; then
    echo -e "${RED}Error: Failed to download context from $METADATA_108_COMMON_URL${NC}" >&2
    rm -f "$TEMP_CIP108"
    exit 1
fi

echo -e "${CYAN}Downloading CIP-169 context from $METADATA_169_COMMON_URL...${NC}"
TEMP_CIP169=$(mktemp /tmp/metadata_create_cip169.XXXXXX)
if ! curl -sSfL "$METADATA_169_COMMON_URL" -o "$TEMP_CIP169"; then
    echo -e "${RED}Error: Failed to download context from $METADATA_169_COMMON_URL${NC}" >&2
    rm -f "$TEMP_CIP108" "$TEMP_CIP169"
    exit 1
fi

echo -e "${CYAN}Merging CIP-108 and CIP-169 contexts...${NC}"
# Merge contexts: use CIP-108 as base and add/update with contents from CIP-169
# jq -s '.[0] * .[1]' "$TEMP_CIP108" "$TEMP_CIP169" > "$TEMP_CONTEXT"

# Build gov_action context based on governance action type
if [ "$governance_action_type" = "info" ]; then
  GOV_ACTION_CONTEXT='{
    "@id": "CIP116:GovAction",
    "@context": {
      "tag": "CIP116:info_action"
    }
  }'
else
  GOV_ACTION_CONTEXT='{
    "@id": "CIP116:GovAction"
  }'
fi

jq -s --argjson gov_action_ctx "$GOV_ACTION_CONTEXT" '{
  "@context": {
    CIP100: .[0]["@context"].CIP100,
    CIP108: .[0]["@context"].CIP108,
    CIP116: .[1]["@context"].CIP116,
    CIP169: .[1]["@context"].CIP169,
    hashAlgorithm: .[0]["@context"].hashAlgorithm,
    body: {
      "@id": .[0]["@context"].body["@id"],
      "@context": (.[0]["@context"].body["@context"] * {
        onChain: {
          "@id": "CIP169:onChain",
          "@context": {
            deposit: {
              "@id": "CIP116:deposit",
              "@type": "CIP116:UInt64"
            },
            reward_account: {
              "@id": "CIP116:reward_account",
              "@type": "CIP116:RewardAddress"
            },
            gov_action: $gov_action_ctx
          }
        }
      })
    },
    authors: .[0]["@context"].authors
  }
}' "$TEMP_CIP108" "$TEMP_CIP169" > "$TEMP_CONTEXT"

rm -f "$TEMP_CIP108" "$TEMP_CIP169"

# Build the metadata JSON-LD with CIP-116 ProposalProcedure format onChain property
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
