#!/bin/bash

##################################################
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
WHITE='\033[1;37m'

##################################################
# Default schema URLs
CIP_100_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0100/cip-0100.common.schema.json"
CIP_108_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0108/cip-0108.common.schema.json"
CIP_119_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0119/cip-0119.common.schema.json"
CIP_136_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0136/cip-136.common.schema.json"
CIP_169_SCHEMA="https://raw.githubusercontent.com/elenabardho/CIPs/refs/heads/cip-governance-metadata-extension-schema/cip-governance-metadata-extension/cip-0169.common.schema.json"
INTERSECT_TREASURY_SCHEMA="https://raw.githubusercontent.com/IntersectMBO/governance-actions/refs/heads/main/schemas/treasury-withdrawals/common.schema.json"
INTERSECT_INFO_SCHEMA="https://raw.githubusercontent.com/IntersectMBO/governance-actions/refs/heads/main/schemas/info/common.schema.json"
INTERSECT_PPU_SCHEMA="https://raw.githubusercontent.com/IntersectMBO/governance-actions/refs/heads/main/schemas/parameter-changes/common.schema.json"

# Default schema values
# CIP-169 is the default as it extends CIP-100 with on-chain effects verification
# When CIP-169 is used, CIP-116 is automatically included for reference resolution
DEFAULT_USE_CIP_100="false"
DEFAULT_USE_CIP_108="false"
DEFAULT_USE_CIP_119="false"
DEFAULT_USE_CIP_136="false"
DEFAULT_USE_CIP_169="false"
DEFAULT_USE_INTERSECT="false"
##################################################

# Check if cardano-signer is installed
if ! command -v cardano-signer >/dev/null 2>&1; then
  echo -e "${RED}Error: cardano-signer is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Check if ajv is installed
if ! command -v ajv >/dev/null 2>&1; then
  echo -e "${RED}Error: ajv is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

set -euo pipefail

# Global variables for cleanup
TMP_JSON_FILE=""
TMP_SCHEMAS_DIR="/tmp/schemas"

# Cleanup function
cleanup() {
    # Clean up temporary JSON file if it exists
    if [ -n "$TMP_JSON_FILE" ] && [ -f "$TMP_JSON_FILE" ]; then
        rm -f "$TMP_JSON_FILE" 2>/dev/null || true
    fi
    # Clean up temporary schemas directory if it exists
    if [ -d "$TMP_SCHEMAS_DIR" ]; then
        rm -rf "$TMP_SCHEMAS_DIR" 2>/dev/null || true
    fi
}

# Set up trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

# Usage message

usage() {
    local col=50
    echo -e "${UNDERLINE}${BOLD}Validate a JSON-LD metadata file${NC}"
    echo -e "\n"
    echo -e "Syntax:${BOLD} $0 ${GREEN}<jsonld-file> ${NC}[${GREEN}--cip108${NC}] [${GREEN}--cip100${NC}] [${GREEN}--cip136${NC}] [${GREEN}--intersect-schema${NC}] [${GREEN}--schema ${NC}URL] [${GREEN}--dict ${NC}FILE]"
    printf "Params: ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "<jsonld-file>" "- Path to the JSON-LD metadata file"
    printf "       ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--cip100]" "- Compare against CIP-100 schema (default: $DEFAULT_USE_CIP_100)"
    printf "       ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--cip108]" "- Compare against CIP-108 Governance actions schema (default: $DEFAULT_USE_CIP_108)"
    printf "       ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--cip119]" "- Compare against CIP-119 DRep schema (default: $DEFAULT_USE_CIP_119)"
    printf "       ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--cip136]" "- Compare against CIP-136 CC vote schema (default: $DEFAULT_USE_CIP_136)"
    printf "       ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--cip169]" "- Compare against CIP-169 Governance metadata schema (default: $DEFAULT_USE_CIP_169, includes CIP-116)"
    printf "       ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--intersect-schema]" "- Compare against Intersect governance action schemas (default: $DEFAULT_USE_INTERSECT)"
    printf "       ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--schema URL]" "- Compare against schema at URL"
    printf "       ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--dict FILE]" "- Use custom aspell dictionary file (optional)"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "-h, --help" "- Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_file=""
use_cip_108="$DEFAULT_USE_CIP_108"
use_cip_100="$DEFAULT_USE_CIP_100"
use_cip_119="$DEFAULT_USE_CIP_119"
use_cip_136="$DEFAULT_USE_CIP_136"
use_cip_169="$DEFAULT_USE_CIP_169"
use_intersect_schema="$DEFAULT_USE_INTERSECT"
user_schema_url=""
user_schema="false"
custom_dict_file=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cip108)
            use_cip_108="true"
            shift
            ;;
        --cip100)
            use_cip_100="true"
            shift
            ;;
        --cip119)
            use_cip_119="true"
            shift
            ;;
        --cip136)
            use_cip_136="true"
            shift
            ;;
        --cip169)
            use_cip_169="true"
            shift
            ;;
        --intersect-schema)
            use_intersect_schema="true"
            shift
            ;;
        --schema)
            user_schema_url="$2"
            user_schema="true"
            shift 2
            ;;
        --dict)
            if [ -n "${2:-}" ]; then
                custom_dict_file="$2"
                shift 2
            else
                echo -e "${RED}Error: --dict requires a file path${NC}" >&2
                usage
            fi
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_file" ]; then
                input_file="$1"
            fi
            shift
            ;;
    esac
done

# Welcome message
echo -e " "
echo -e "${YELLOW}Governance Metadata Validation Script${NC}"
echo -e "${CYAN}This script validates JSON-LD governance metadata files against CIP standards and or Intersect schemas${NC}"

# If the file ends with .jsonld, create a temporary .json copy (overwrite if exists)
if [[ "$input_file" == *.jsonld ]]; then
    if [ ! -f "$input_file" ]; then
        echo -e "${RED}Error: File '${YELLOW}$input_file${RED}' does not exist.${NC}">&2
        usage
        exit 1
    fi
    TMP_JSON_FILE="/tmp/metadata.json"
    cp -f "$input_file" "$TMP_JSON_FILE"
    JSON_FILE="$TMP_JSON_FILE"
else
    JSON_FILE="$input_file"
fi

# Check if the file exists
if [ ! -f "$JSON_FILE" ]; then
    echo -e "${RED}Error: File '${YELLOW}$JSON_FILE${RED}' does not exist.${NC}">&2
    usage
    exit 1
fi

# Check if the file is valid JSON
if ! jq empty "$JSON_FILE" >/dev/null 2>&1; then
    echo -e "${RED}Error: '${YELLOW}$JSON_FILE${RED}' is not valid JSON.${NC}"
    exit 1
fi

# Basic spell check on key data fields (requires 'aspell' installed)
echo -e " "
echo -e "${CYAN}Applying spell check...${NC}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine which dictionary to use
if [ -n "$custom_dict_file" ]; then
    # User provided a custom dictionary
    CARDANO_DICT="$custom_dict_file"
    if [ ! -f "$CARDANO_DICT" ]; then
        echo -e "${RED}Error: Custom dictionary file not found at ${YELLOW}$CARDANO_DICT${NC}" >&2
        exit 1
    fi
    echo -e "${WHITE}Using custom dictionary: ${YELLOW}$CARDANO_DICT${NC}"
else
    # Use default dictionary from script directory
    echo -e "${WHITE}Using default spelling dictionary from script directory${NC}"
    CARDANO_DICT="$SCRIPT_DIR/cardano-aspell-dict.txt"
fi

# Check if the dictionary file exists
if [ ! -f "$CARDANO_DICT" ]; then
    echo -e "${YELLOW}Warning: Cardano aspell dictionary not found at ${YELLOW}$CARDANO_DICT${NC}"
    echo -e "${YELLOW}Using default aspell dictionary only.${NC}"
    PERSONAL_DICT_ARG=""
else
    PERSONAL_DICT_ARG="--personal=$CARDANO_DICT"
fi

echo -e "${YELLOW}Possible misspellings:${NC}"
# This hardcoded for CIP108
# todo fix for other schemas
for field in title abstract motivation rationale; do
    # Extract field text
    text=$(jq -r ".body.$field // empty" "$JSON_FILE")
    if [ -n "$text" ]; then
        # Use aspell to check spelling with personal dictionary (if available), output only misspelled words
        echo "$text" | aspell list $PERSONAL_DICT_ARG | sort -u | while read -r word; do
            if [ -n "$word" ]; then
                echo -e "  ${BLUE}'$field': ${YELLOW}$word${NC}"
            fi
        done
    fi
done

echo -e " "
echo -e "${CYAN}Applying schema check(s)...${NC}"

# Create a temporary directory for schema(s)
mkdir -p "$TMP_SCHEMAS_DIR"

# Download the schemas as needed
if [ "$use_cip_100" = "true" ]; then
    echo -e "${WHITE}Downloading CIP-100 Governance Metadata schema...${NC}"
    TEMP_CIP_100_SCHEMA="$TMP_SCHEMAS_DIR/cip-100-schema.json"
    curl -sSfSL "$CIP_100_SCHEMA" -o "$TEMP_CIP_100_SCHEMA"
fi

if [ "$use_cip_108" = "true" ]; then
    echo -e "${WHITE}Downloading CIP-108 Governance Actions schema...${NC}"
    TEMP_CIP_108_SCHEMA="$TMP_SCHEMAS_DIR/cip-108-schema.json"
    curl -sSfSL "$CIP_108_SCHEMA" -o "$TEMP_CIP_108_SCHEMA"
fi

if [ "$use_cip_119" = "true" ]; then
    echo -e "${WHITE}Downloading CIP-119 DRep schema...${NC}"
    TEMP_CIP_119_SCHEMA="$TMP_SCHEMAS_DIR/cip-119-schema.json"
    curl -sSfSL "$CIP_119_SCHEMA" -o "$TEMP_CIP_119_SCHEMA"
fi

if [ "$use_cip_136" = "true" ]; then
    echo -e "${WHITE}Downloading CIP-136 Constitutional Committee Vote schema...${NC}"
    TEMP_CIP_136_SCHEMA="$TMP_SCHEMAS_DIR/cip-136-schema.json"
    curl -sSfSL "$CIP_136_SCHEMA" -o "$TEMP_CIP_136_SCHEMA"
fi

if [ "$use_cip_169" = "true" ]; then
    echo -e "${WHITE}Downloading CIP-169 Governance Metadata Extension schema...${NC}"
    TEMP_CIP_169_SCHEMA="$TMP_SCHEMAS_DIR/cip-169-schema.json"
    curl -sSfSL "$CIP_169_SCHEMA" -o "$TEMP_CIP_169_SCHEMA"
fi

# Determine which Intersect schema to use based on governanceActionType property
if [ "$use_intersect_schema" = "true" ]; then
    governance_action_type=$(jq -r '.body.onChain.governanceActionType' "$JSON_FILE")

    if [ "$governance_action_type" = "info" ]; then
        echo -e "${WHITE}Downloading Intersect ${YELLOW}info${WHITE} schema...${NC}"
        INTERSECT_SCHEMA_URL="$INTERSECT_INFO_SCHEMA"

    elif [ "$governance_action_type" = "treasuryWithdrawals" ]; then
        echo -e "${WHITE}Downloading Intersect ${YELLOW}treasuryWithdrawals${WHITE} schema...${NC}"
        INTERSECT_SCHEMA_URL="$INTERSECT_TREASURY_SCHEMA"

    elif [ "$governance_action_type" = "protocolParameterChanges" ]; then
        echo -e "${WHITE}Downloading Intersect ${YELLOW}parameterChanges${WHITE} schema...${NC}"
        INTERSECT_SCHEMA_URL="$INTERSECT_PPU_SCHEMA"
    else
        echo -e "${RED}Error: Unknown governanceActionType '${YELLOW}$governance_action_type${RED}' in '${YELLOW}$JSON_FILE${RED}'.${NC}"
        exit 1
    fi
    TEMP_INT_SCHEMA="$TMP_SCHEMAS_DIR/intersect-schema.json"
    curl -sSfSL "$INTERSECT_SCHEMA_URL" -o "$TEMP_INT_SCHEMA"
fi

if [ "$user_schema" = "true" ]; then
    echo -e "${WHITE}Downloading schema from ${YELLOW}{$user_schema_url}${WHITE}...${NC}"
    TEMP_USER_SCHEMA="$TMP_SCHEMAS_DIR/user-schema.json"
    curl -sSfSL "$user_schema_url" -o "$TEMP_USER_SCHEMA"
fi

# Validate the JSON file against the schemas
schemas=("$TMP_SCHEMAS_DIR"/*-schema.json)

if [ -z "$(ls -A $TMP_SCHEMAS_DIR)" ]; then
    echo -e "${RED}Error: No schemas were downloaded.${NC}"
    exit 1
fi

VALIDATION_FAILED=0

for schema in "${schemas[@]}"; do
    echo -e " "
    echo -e "${CYAN}Validating against schema: ${YELLOW}$schema${NC}"
    if [ -f "$schema" ]; then
        ajv validate -s "$schema" -d "$JSON_FILE" --all-errors --strict=false
        if [ $? -ne 0 ]; then
            VALIDATION_FAILED=1
        fi
    fi
done

# Final result
if [ "$VALIDATION_FAILED" -ne 0 ]; then
    echo -e " "
    echo -e "${RED}One or more validation errors were found.${NC}"
    exit 1
else
    echo -e " "
    echo -e "${GREEN}No validation errors found.${NC}"
    exit 0
fi