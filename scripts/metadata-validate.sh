#!/bin/bash

##################################################
# Default schema values
CIP_100_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0100/cip-0100.common.schema.json"
CIP_108_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0108/cip-0108.common.schema.json"
INTERSECT_TREASURY_SCHEMA="https://raw.githubusercontent.com/IntersectMBO/governance-actions/refs/heads/main/schemas/treasury-withdrawals/common.schema.json"

# Default schema values
DEFAULT_USE_CIP_100="false"
DEFAULT_USE_CIP_108="true"
##################################################

# Check if cardano-signer is installed
if ! command -v cardano-signer >/dev/null 2>&1; then
  echo "Error: cardano-signer is not installed or not in your PATH." >&2
  exit 1
fi

# Check if ajv is installed
if ! command -v ajv >/dev/null 2>&1; then
  echo "Error: ajv is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <jsonld-file> [--cip108] [--cip100] [--schema URL]"
    echo "Options:"
    echo "  --cip108              Compare against CIP-108 schema (default: $DEFAULT_USE_CIP_108)"
    echo "  --cip100              Compare against CIP-100 schema (default: $DEFAULT_USE_CIP_100)"
    echo "  --schema URL          Compare against schema at URL"
    exit 1
}

# Initialize variables with defaults
input_file=""
use_cip_108="$DEFAULT_USE_CIP_108"
use_cip_100="$DEFAULT_USE_CIP_100"
user_schema_url=""
user_schema="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cip108)
            use_cip_108="true"
            shift
            ;;
        --cip108)
            use_cip_108="true"
            shift
            ;;
        --schema)
            user_schema_url="$2"
            user_schema="true"
            shift 2
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

# If the file ends with .jsonld, create a temporary .json copy (overwrite if exists)
TMP_JSON_FILE=""
if [[ "$input_file" == *.jsonld ]]; then
    if [ ! -f "$input_file" ]; then
        echo "Error: File '$input_file' does not exist."
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
    echo "Error: File '$JSON_FILE' does not exist."
    [ -n "$TMP_JSON_FILE" ] && rm -f "$TMP_JSON_FILE"
    exit 1
fi

# Check if the file is valid JSON
if ! jq empty "$JSON_FILE" >/dev/null 2>&1; then
    echo "Error: '$JSON_FILE' is not valid JSON."
    [ -n "$TMP_JSON_FILE" ] && rm -f "$TMP_JSON_FILE"
    exit 1
fi

# Download the schemas as needed
if [ "$use_cip_108" = "true" ]; then
    TEMP_CIP_108_SCHEMA="/tmp/cip-108-schema.json"
    curl -sSfSL "$CIP_108_SCHEMA" -o "$TEMP_CIP_108_SCHEMA"
fi

if [ "$use_cip_100" = "true" ]; then
    TEMP_CIP_100_SCHEMA="/tmp/cip-100-schema.json"
    curl -sSfSL "$CIP_100_SCHEMA" -o "$TEMP_CIP_100_SCHEMA"
fi

if [ "$user_schema" = "true" ]; then
    TEMP_USER_SCHEMA="/tmp/user-schema.json"
    curl -sSfSL "$use_schema_url" -o "$TEMP_USER_SCHEMA"
fi

# Pull the schema from the URL
TMP_SCHEMA="/tmp/cip-108-schema.json"
curl -sSfSL "$SCHEMA_URL" -o "$TMP_SCHEMA"

# Check if the schema was retrieved and is valid JSON
if [ ! -s "$TMP_SCHEMA" ] || ! jq empty "$TMP_SCHEMA" >/dev/null 2>&1; then
    echo "Error: Failed to retrieve or parse schema from $SCHEMA_URL"
    rm -f "$TMP_SCHEMA"
    [ -n "$TMP_JSON_FILE" ] && rm -f "$TMP_JSON_FILE"
    exit 1
fi

# Basic spell check on key data fields (requires 'aspell' installed)
if command -v aspell >/dev/null 2>&1; then
    echo " "
    echo "Spell check warnings:"
    # List of fields to check
    for field in title abstract motivation rationale; do
        # Extract field text
        text=$(jq -r ".body.$field // empty" "$JSON_FILE")
        if [ -n "$text" ]; then
            # Use aspell to check spelling, output only misspelled words
            echo "$text" | aspell list | sort -u | while read -r word; do
                if [ -n "$word" ]; then
                    echo "  Possible misspelling in '$field': $word"
                fi
            done
        fi
    done
else
    echo "Warning: aspell not found, skipping spell check."
fi

echo " "
echo "Validating JSON file against schema '$SCHEMA_URL'..."
echo " "

# Validate JSON against the schema
ajv validate -s "$TMP_SCHEMA" -d "$JSON_FILE" --all-errors --strict=true
AJV_EXIT_CODE=$?

# Clean up temporary files
rm -f "$TMP_SCHEMA"
rm -f "$TMP_JSON_FILE"

echo " "
echo "Validation complete."
echo " "

exit $AJV_EXIT_CODE