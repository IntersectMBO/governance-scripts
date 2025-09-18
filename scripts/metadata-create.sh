#!/bin/bash

##################################################

# Default configuration values

##################################################

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail if any command in a pipeline fails
# set -euo pipefail

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
    echo "Usage: $0 <.md-file> --governance-action-type <type> [--deposit-return-addr <stake-address>]"
    echo "Options:"
    echo "  <.md-file>                                    Path to the .md file as input"
    echo "  --governance-action-type <info|treasury>      Type of governance action (info, treasury, etc.)"
    echo "  --deposit-return-addr <stake-address>         Stake address for deposit return (bech32) - required for treasuryWithdrawals"
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

# Cleanup function to remove temporary files
cleanup() {
  rm -f "$TEMP_MD" "$TEMP_OUTPUT_JSON"
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

# Generate output filename: same directory and name as input, but with .jsonld extension
input_dir=$(dirname "$input_file")
input_basename=$(basename "$input_file")
input_name="${input_basename%.*}"
FINAL_OUTPUT_JSON="$input_dir/$input_name.jsonld"

echo " "
echo -e "${CYAN}Converting $input_basename to CIP108 metadata...${NC}"

echo " "
echo -e "Processing $input_basename markdown file"

# Copy the markdown file to temp location for processing
cp "$input_file" "$TEMP_MD"

extract_section() {
  local start="$1"
  local next="$2"
  awk "/^${start}\$/,/^${next}\$/" "$TEMP_MD" | sed "1d;\$d" | sed '/^$/d'
}

get_section() {
  local label="$1"
  local next="$2"
  extract_section "$label" "$next" \
    | awk -v ORS="" '
      NF { print $0 "\n" }
      !NF { print "\n" }
    ' \
    | awk '{ printf "%s\n\n", $0 }' \
    | sed -E 's/\n+$//' \
    | jq -Rs .
}

get_section_last() {
  local label="$1"
  awk "/^${label}\$/,/^## References\$/" "$TEMP_MD" | sed "1d" \
    | awk 'BEGIN{ORS=""; RS=""} {gsub(/\n/, " "); print $0 "\n\n"}' \
    | sed 's/[[:space:]]\+$//' \
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

# Extract authors from Authors section
extract_authors() {
  awk '
  BEGIN {
    in_authors = 0
    author_count = 0
  }

  /^### Authors$/ { in_authors = 1; next }
  /^$/ && in_authors { in_authors = 0; next }

  in_authors {
    # Skip empty lines
    if ($0 ~ /^\s*$/) next

    # Check for author lines (starting with * or -)
    if ($0 ~ /^[\*\-] /) {
      author_name = $0
      sub(/^[\*\-] /, "", author_name)
      
      # Clean up quotes in author name
      gsub(/"/, "\\\"", author_name)

      # Only add if we have a name
      if (author_name != "") {
        authors[author_count++] = "  {\"name\": \"" author_name "\"}"
      }
    }
  }

  END {
    print "["
    for (i = 0; i < author_count; i++) {
      printf "%s", authors[i]
      if (i < author_count - 1) print ","
      else print ""
    }
    print "\n]"
  }
  ' "$TEMP_MD"
}

# this search term can be changed to match the expected pattern
extract_withdrawal_address() {
  local rationale_text="$1"
  echo "$rationale_text" | jq -r . | grep -oE "With the confirmed treasury reserve contract address being:[[:space:]]*(stake_test1[a-zA-Z0-9]{53}|stake1[a-zA-Z0-9]{53})" | sed -E 's/.*being:[[:space:]]*//'
}

# Generate onChain property based on governance action type
generate_onchain_property() {
  local action_type="$1"
  
  case "$action_type" in
    "info")
      echo "null"
      ;;
    "treasury")
      # Extract withdrawal amount from the title
      WITHDRAWAL_AMOUNT_RAW=$(echo "$TITLE" | sed -n 's/.*₳\([0-9,]*\).*/\1/p' | tr -d '"')
      # Remove commas and add 6 zeros (convert to lovelace)
      WITHDRAWAL_AMOUNT=$(echo "$WITHDRAWAL_AMOUNT_RAW" | tr -d ',' | sed 's/$/000000/')
      
      # Extract withdrawal address from the rationale section
      WITHDRAWAL_ADDR=$(extract_withdrawal_address "$RATIONALE")
      
      cat <<EOF
{
  "governanceActionType": "treasuryWithdrawals",
  "depositReturnAddress": "$deposit_return_address",
  "withdrawals": [
    {
      "withdrawalAddress": "$WITHDRAWAL_ADDR",
      "withdrawalAmount": $WITHDRAWAL_AMOUNT
    }
  ]
}
EOF
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
AUTHORS=$(extract_authors)

# Generate onChain property based on governance action type
echo -e "Generating onChain property for $governance_action_type"
ONCHAIN_PROPERTY=$(generate_onchain_property "$governance_action_type")

# Generate references JSON
REFERENCES_JSON=$(extract_references)

cat <<EOF > "$TEMP_OUTPUT_JSON"
{
  "@context": {
    "@language": "en",
    "CIP100": "https://github.com/cardano-foundation/CIPs/blob/master/CIP-0100/README.md#",
    "CIP108": "https://github.com/cardano-foundation/CIPs/blob/master/CIP-0108/README.md#",
    "intersectSpec": "https://github.com/IntersectMBO/governance-actions/blob/main/schemas/specification.md#",
    "hashAlgorithm": "CIP100:hashAlgorithm",
    "body": {
      "@id": "CIP108:body",
      "@context": {
        "references": {
          "@id": "CIP108:references",
          "@container": "@set",
          "@context": {
            "GovernanceMetadata": "CIP100:GovernanceMetadataReference",
            "Other": "CIP100:OtherReference",
            "label": "CIP100:reference-label",
            "uri": "CIP100:reference-uri",
            "referenceHash": {
              "@id": "CIP108:referenceHash",
              "@context": {
                "hashDigest": "CIP108:hashDigest",
                "hashAlgorithm": "CIP100:hashAlgorithm"
              }
            }
          }
        },
        "title": "CIP108:title",
        "abstract": "CIP108:abstract",
        "motivation": "CIP108:motivation",
        "rationale": "CIP108:rationale",
        "onChain": {
          "@id": "intersectSpec:onChain",
          "@context": {
            "governanceActionType": "intersectSpec:governanceActionType",
            "depositReturnAddress": "intersectSpec:depositReturnAddress",
            "withdrawals": {
              "@id": "intersectSpec:withdrawals",
              "@container": "@set",
              "@context": {
                "withdrawalAddress": "intersectSpec:withdrawalAddress",
                "withdrawalAmount": "intersectSpec:withdrawalAmount"
              }
            }
          }
        }
      }
    },
    "authors": {
      "@id": "CIP100:authors",
      "@container": "@set",
      "@context": {
        "name": "http://xmlns.com/foaf/0.1/name",
        "witness": {
          "@id": "CIP100:witness",
          "@context": {
            "witnessAlgorithm": "CIP100:witnessAlgorithm",
            "publicKey": "CIP100:publicKey",
            "signature": "CIP100:signature"
          }
        }
      }
    }
  },
  "authors": $AUTHORS,
  "hashAlgorithm": "blake2b-256",
  "body": {
    "title": $TITLE,
    "abstract": $ABSTRACT,
    "motivation": $MOTIVATION,
    "rationale": $RATIONALE,
    "references": $REFERENCES_JSON,
    "onChain": $ONCHAIN_PROPERTY
  }
}
EOF

echo -e " "
echo -e "${CYAN}Formatting JSON output...${NC}"

# Use jq to format the JSON output
jq . "$TEMP_OUTPUT_JSON" > "$FINAL_OUTPUT_JSON"

echo -e "${GREEN}JSONLD saved to $FINAL_OUTPUT_JSON${NC}"
