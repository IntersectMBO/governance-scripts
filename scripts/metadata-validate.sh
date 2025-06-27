#!/bin/bash

##################################################
# Default schema values
CIP_100_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0100/cip-0100.common.schema.json"
CIP_108_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0108/cip-0108.common.schema.json"
CIP_136_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0136/cip-136.common.schema.json"
INTERSECT_TREASURY_SCHEMA="https://raw.githubusercontent.com/IntersectMBO/governance-actions/refs/heads/main/schemas/treasury-withdrawals/common.schema.json"

# Default schema values
DEFAULT_USE_CIP_100="false"
DEFAULT_USE_CIP_108="true"
DEFAULT_USE_CIP_136="false"
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
    echo "Usage: $0 <jsonld-file> [--cip108] [--cip100] [--cip136] [--schema URL]"
    echo "Options:"
    echo "  --cip108              Compare against CIP-108 schema (default: $DEFAULT_USE_CIP_108)"
    echo "  --cip100              Compare against CIP-100 schema (default: $DEFAULT_USE_CIP_100)"
    echo "  --cip136              Compare against CIP-136 schema (default: $DEFAULT_USE_CIP_136)"
    echo "  --schema <URL>        Compare against schema at URL"
    exit 1
}

# Initialize variables with defaults
input_file=""
use_cip_108="$DEFAULT_USE_CIP_108"
use_cip_100="$DEFAULT_USE_CIP_100"
use_cip_136="$DEFAULT_USE_CIP_136"
user_schema_url=""
user_schema="false"

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
        --cip136)
            use_cip_136="true"
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

mkdir -p /tmp/schemas

# Download the schemas as needed
if [ "$use_cip_100" = "true" ]; then
    echo "Downloading CIP-100 schema..."
    TEMP_CIP_100_SCHEMA="/tmp/schemas/cip-100-schema.json"
    curl -sSfSL "$CIP_100_SCHEMA" -o "$TEMP_CIP_100_SCHEMA"
fi

if [ "$use_cip_108" = "true" ]; then
    echo "Downloading CIP-108 schema..."
    TEMP_CIP_108_SCHEMA="/tmp/schemas/cip-108-schema.json"
    curl -sSfSL "$CIP_108_SCHEMA" -o "$TEMP_CIP_108_SCHEMA"
fi

if [ "$use_cip_136" = "true" ]; then
    echo "Downloading CIP-136 schema..."
    TEMP_CIP_136_SCHEMA="/tmp/schemas/cip-136-schema.json"
    curl -sSfSL "$CIP_136_SCHEMA" -o "$TEMP_CIP_136_SCHEMA"
fi

if [ "$user_schema" = "true" ]; then
    echo "Downloading schema from {$use_schema_url}..."
    TEMP_USER_SCHEMA="/tmp/schemas/user-schema.json"
    curl -sSfSL "$use_schema_url" -o "$TEMP_USER_SCHEMA"
fi

# Basic spell check on key data fields (requires 'aspell' installed)
echo " "
echo "Spell check warnings:"

# This hardcoded for CIP108
# todo fix for other schemas
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

# Validate the JSON file against the schemas
schemas=(/tmp/schemas/*-schema.json)
for schema in "${schemas[@]}"; do
    echo "Validating against schema: $schema"
    if [ -f "$schema" ]; then
        ajv validate -s "$schema" -d "$JSON_FILE" --all-errors --strict=true
        AJV_EXIT_CODE=$?
    fi
done

# Clean up temporary files
rm -f "$TMP_JSON_FILE"
rm -f /tmp/schemas/*

echo " "
echo "Validation complete."
echo " "

exit $AJV_EXIT_CODE