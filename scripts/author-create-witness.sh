#!/bin/bash

##################################################
DEFAULT_AUTHOR_NAME="Intersect"
DEFAULT_USE_CIP8="false" # default to false, to the script uses Ed25519
##################################################

# This is just a script for testing purposes.

# This script needs a signing key to be held locally
# most setups should and will not have this.

##################################################

# Check if cardano-signer is installed
if ! command -v cardano-signer >/dev/null 2>&1; then
  echo "Error: cardano-signer is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <jsonld-file|directory> <signing-key> [--author-name NAME] [--use-cip8]"
    echo "Options:"
    echo "  --author-name NAME    Specify the author name (default: $DEFAULT_AUTHOR_NAME)"
    echo "  --use-cip8            Use CIP-8 signing algorithm (default: $DEFAULT_USE_CIP8)"
    exit 1
}

# Initialize variables with defaults
input_path=""
input_key=""
author_name="$DEFAULT_AUTHOR_NAME"
use_cip8="$DEFAULT_USE_CIP8"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --author-name)
            author_name="$2"
            shift 2
            ;;
        --use-cip8)
            use_cip8="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_path" ]; then
                input_path="$1"
            elif [ -z "$input_key" ]; then
                input_key="$1"
            else
                echo "Error: Unexpected argument '$1'"
                usage
            fi
            shift
            ;;
    esac
done

# Check for required arguments
if [ -z "$input_path" ] || [ -z "$input_key" ]; then
    echo "Error: Missing required arguments"
    usage
fi

# Check if the key input file exists
if [ ! -f "$input_key" ]; then
    echo "Error: Signing key file '$input_key' not found!"
    exit 1
fi

sign_file() {
    local file="$1"
    local use_cip8="$2"

    if [ "$use_cip8" = "true" ]; then
        echo "Signing with CIP-8 algorithm..."

        temp_vkey=$(mktemp)
        temp_hash=$(mktemp)

        # Generate verification key from the provided secret key
        cardano-cli key verification-key \
            --signing-key-file "$input_key" \
            --verification-key-file "$temp_vkey"

        # hash the verification key to get the public key hash
        public_key_hash=$(cardano-cli address key-hash --payment-verification-key-file "$temp_vkey")

        # Clean up temporary files
        rm "$temp_vkey"
        rm "$temp_hash"

        echo "Signing with CIP8 algorithm..."
        cardano-signer sign --cip100 \
            --data-file "$file" \
            --secret-key "$input_key" \
            --author-name "$author_name" \
            --address "$public_key_hash" \
            --out-file "${file%.jsonld}.authored.jsonld"
        return
    else
        echo "Signing with Ed25519 algorithm..."
        cardano-signer sign --cip100 \
            --data-file "$file" \
            --secret-key "$input_key" \
            --author-name "$author_name" \
            --out-file "${file%.jsonld}.authored.jsonld"
        return
    fi
}

# Use cardano-signer to sign author metadata

if [ -d "$input_path" ]; then
    # If input is a directory: sign all .jsonld files
    shopt -s nullglob
    jsonld_files=("$input_path"/*.jsonld)
    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        echo "Error: No .jsonld files found in directory '$input_path'."
        exit 1
    fi
    # for each .jsonld file in the directory, sign it
    for file in "${jsonld_files[@]}"; do
        sign_file "$file" "$use_cip8"
    done
elif [ -f "$input_path" ]; then
    # Input is a single file
    sign_file "$input_path" "$use_cip8"
else
    echo "Error: '$input_path' is not a valid file or directory."
    exit 1
fi