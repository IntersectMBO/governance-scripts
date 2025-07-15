#!/bin/bash

##################################################

# Default configuration values

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
    echo "Usage: $0 <.docx-file> --deposit-return-addr <stake-address>"
    echo "Options:"
    echo "  <.docx-file>                                    Path to the .docx file as input"
    echo "  --deposit-return-addr <stake-address>           Stake address for deposit return (bech32)"
    echo "  -h, --help                                      Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_file=""
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

# If no deposit return address provided, show usage
if [ -z "$deposit_return_address" ]; then
  echo -e "${RED}Error: --deposit-return-addr is required${NC}" >&2
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
echo -e "Converting $input_basename to markdown temporarily"

# First convert DOCX to Markdown, as we want markdown styling in our CIP108 metadata
pandoc "$input_file" -t markdown --wrap=none -o "$TEMP_MD"

# Tidy up the Markdown file, remove junky formatting
# Remove [[text]{.style}]
sed -E -i '' 's/\[\[([^]]+)\]\]\{\.([a-zA-Z0-9_-]+)\}/\1/g' "$TEMP_MD"
# Remove [text]{.style}
sed -E -i '' 's/\[([^]]+)\]\{\.([a-zA-Z0-9_-]+)\}/\1/g' "$TEMP_MD"
# Fix broken markdown-style links [[Label]](url) change to [Label](url)
sed -E -i '' 's/\[\[([^\]]+)\]\]\(([^)]+)\)/[\1](\2)/g' "$TEMP_MD"
# Normalize ₳ formatting
sed -E -i '' 's/\[₳\]\{\.mark\}/₳/g' "$TEMP_MD"
sed -E -i '' 's/₳[[:space:]]*/₳/g' "$TEMP_MD"
# Normalize section headers: ## **Title** changes to ## Title
sed -E -i '' 's/^## \*\*(.*)\*\*$/\1/' "$TEMP_MD"

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
  awk "/^${label}\$/,/^References\$/" "$TEMP_MD" | sed "1d" \
    | awk 'BEGIN{ORS=""; RS=""} {gsub(/\n/, " "); print $0 "\n\n"}' \
    | sed 's/[[:space:]]\+$//' \
    | jq -Rs .
}

# Extract label/URL pairs from References section
extract_references() {
  awk '
  BEGIN {
    in_refs = 0
    label = ""
    ref_count = 0
  }

  /^References$/ { in_refs = 1; next }
  /^Authors$/ { in_refs = 0 }

  in_refs {
    if ($0 ~ /^\s*$/) next

    if ($0 ~ /^- \[/ || $0 ~ /^- ipfs:\/\//) {
      uri = ""

      if (index($0, "(") > 0 && index($0, ")") > 0) {
        # Extract URL from markdown link
        uri = $0
        sub(/^.*\(/, "", uri)
        sub(/\).*$/, "", uri)
      } else if ($0 ~ /- ipfs:\/\//) {
        split($0, parts, "- ")
        uri = parts[2]
      }

      gsub(/"/, "\\\"", label)
      gsub(/"/, "\\\"", uri)

      refs[ref_count++] = "  {\"@type\": \"Other\", \"label\": \"" label "\", \"uri\": \"" uri "\"}"
      label = ""
    } else {
      label = $0
    }
  }

  END {
    print "["
    for (i = 0; i < ref_count; i++) {
      printf "%s", refs[i]
      if (i < ref_count - 1) print ","
      else print ""
    }
    print "\n]"
  }
  ' "$TEMP_MD"
}

# this search term can be changed to match the expected pattern
extract_withdrawal_address() {
  local rationale_text="$1"
  echo "$rationale_text" | jq -r . | grep -oE "With the confirmed withdrawal address being:\s*(stake_test1[a-zA-Z0-9]{53}|stake1[a-zA-Z0-9]{53})" | sed -E 's/.*being:\s*//'
}

# use helper functions to extract sections
echo -e "Extracting sections from Markdown"

TITLE=$(get_section "Title" "Abstract")
ABSTRACT=$(get_section "Abstract" "Motivation")
MOTIVATION=$(get_section "Motivation" "Rationale")
RATIONALE=$(get_section_last "Rationale")
REFERENCES=$(extract_references)

echo -e "Extracting withdrawal amount from the title"
WITHDRAWAL_AMOUNT_RAW=$(echo "$TITLE" | sed -n 's/.*₳\([0-9,]*\).*/\1/p' | tr -d '"')
# Remove commas and add 6 zeros (convert to lovelace)
WITHDRAWAL_AMOUNT=$(echo "$WITHDRAWAL_AMOUNT_RAW" | tr -d ',' | sed 's/$/000000/')

# Extract withdrawal address from the rationale section
echo -e "Extracting withdrawal address from the rationale"
WITHDRAWAL_ADDR=$(extract_withdrawal_address "$RATIONALE")

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
        "@context": {
          "onChain": {
            "@id": "intersectSpec:onChain",
            "@context": {
              "governanceActionType": "intersectSpec:governanceActionType",
              "depositReturnAddress": "intersectSpec:depositReturnAddress",
              "@context": {
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
  "authors": [],
  "hashAlgorithm": "blake2b-256",
  "body": {
    "title": $TITLE,
    "abstract": $ABSTRACT,
    "motivation": $MOTIVATION,
    "rationale": $RATIONALE,
    "references": $REFERENCES,
    "onChain": {
      "governanceActionType": "treasuryWithdrawals",
      "depositReturnAddress": "$deposit_return_address",
      "withdrawals": [
        {
          "withdrawalAddress": "$WITHDRAWAL_ADDR",
          "withdrawalAmount": $WITHDRAWAL_AMOUNT
        }
      ]
    }
  }
}
EOF

echo -e " "
echo -e "${CYAN}Cleaning up the formatting on the JSON output...${NC}"

jq . "$TEMP_OUTPUT_JSON" > "$FINAL_OUTPUT_JSON"

echo -e "${GREEN}JSONLD saved to $FINAL_OUTPUT_JSON${NC}"
