#!/bin/bash

##################################################
DEFAULT_AUTHOR_NAME="Intersect"
DEFAULT_USE_CIP8="false" # default to false, to the script uses Ed25519
DEFAULT_NEW_FILE="false" # default to false, to the script overwrites the input file
##################################################

# This is just a script for testing purposes.

# This script needs a signing key to be held locally
# most setups should and will not have this.

##################################################

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

# Check if cardano-signer is installed
if ! command -v cardano-signer >/dev/null 2>&1; then
  print_fail "cardano-signer is not installed or not in your PATH."
  exit 1
fi

# Usage message
usage() {
    printf '%s%sSign metadata files with author witness using cardano-signer%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<jsonld-file|directory> <signing-key>%s [%s--author-name%s NAME] [%s--use-cip8%s] [%s--new-file%s]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<jsonld-file|directory>" "Path to JSON-LD file or directory to sign"
    print_usage_option "<signing-key>"           "Path to the signing key"
    print_usage_option "[--author-name NAME]"    "Specify the author name (default: $DEFAULT_AUTHOR_NAME)"
    print_usage_option "[--use-cip8]"            "Use CIP-8 signing algorithm (default: $DEFAULT_USE_CIP8)"
    print_usage_option "[--new-file]"            "Create a new file with the signed metadata (default: $DEFAULT_NEW_FILE)"
    print_usage_option "-h, --help"              "Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_path=""
input_key=""
author_name="$DEFAULT_AUTHOR_NAME"
use_cip8="$DEFAULT_USE_CIP8"
new_file="$DEFAULT_NEW_FILE"

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
        --new-file)
            new_file="true"
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
                print_fail "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

# Check for required arguments
if [ -z "$input_path" ] || [ -z "$input_key" ]; then
    print_fail "Missing required arguments"
    usage
fi

print_banner "Creating author witness for metadata files"
print_info "This script signs JSON-LD metadata files using cardano-signer"

# Check if the key input file exists
if [ ! -f "$input_key" ]; then
    print_fail "Signing key file $(fmt_path "$input_key") not found"
    exit 1
fi

print_info "Using signing key: $(fmt_path "$input_key")"
print_info "Author name: ${YELLOW}${author_name}${NC}"
print_info "Algorithm: ${YELLOW}$([ "$use_cip8" = "true" ] && echo "CIP-8" || echo "Ed25519")${NC}"
print_info "Output mode: ${YELLOW}$([ "$new_file" = "true" ] && echo "New file (.authored.jsonld)" || echo "Overwrite original")${NC}"

sign_file() {
    local file="$1"
    local use_cip8="$2"
    local new_file="$3"

    print_section "Signing $(basename "$file")"

    if [ "$new_file" = "true" ]; then
        print_info "Creating a new file with the signed metadata..."
        extension=".authored.jsonld" # New file will have .authored.jsonld extension
    else
        print_info "Overwriting the original file with the signed metadata..."
        extension=".jsonld"
    fi

    if [ "$use_cip8" = "true" ]; then
        print_info "Signing with CIP-8 algorithm..."

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

        print_info "Using public key hash: ${YELLOW}${public_key_hash}${NC}"
        cardano-signer sign --cip100 \
            --data-file "$file" \
            --secret-key "$input_key" \
            --author-name "$author_name" \
            --address "$public_key_hash" \
            --out-file "${file%.jsonld}$extension"
    else
        print_info "Signing with Ed25519 algorithm..."
        cardano-signer sign --cip100 \
            --data-file "$file" \
            --secret-key "$input_key" \
            --author-name "$author_name" \
            --out-file "${file%.jsonld}$extension"
    fi

    print_pass "Successfully signed: $(fmt_path "${file%.jsonld}$extension")"
}

# Use cardano-signer to sign author metadata

if [ -d "$input_path" ]; then
    # If input is a directory: sign all .jsonld files (including subdirectories)
    print_section "Processing directory $(basename "$input_path")"
    print_info "Path: $(fmt_path "$input_path")"

    # Get all .jsonld files in the directory and subdirectories
    jsonld_files=()
    while IFS= read -r -d '' file; do
        jsonld_files+=("$file")
    done < <(find "$input_path" -type f -name "*.jsonld" -print0)

    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        print_fail "No .jsonld files found in directory (including subdirectories): $(fmt_path "$input_path")"
        exit 1
    fi

    print_info "Found ${YELLOW}${#jsonld_files[@]}${NC} .jsonld files to process"

    # for each .jsonld file in the directory, sign it
    for file in "${jsonld_files[@]}"; do
        # skip for the first file
        if [ "$file" != "${jsonld_files[0]}" ]; then
            print_info "The next file is: $(fmt_path "$file")"
            if ! confirm "Continue with the next file?"; then
                print_fail "Cancelled by user"
                exit 1
            fi
        fi
        sign_file "$file" "$use_cip8" "$new_file"
    done

    print_section "Summary"
    print_pass "All ${#jsonld_files[@]} files processed successfully"

elif [ -f "$input_path" ]; then
    # Input is a single file — enforce .jsonld extension
    if [[ "$input_path" != *.jsonld ]]; then
        print_fail "Input file $(fmt_path "$input_path") must be a JSON-LD metadata file with a .jsonld extension."
        print_hint "This script adds an author witness to CIP-100/CIP-108 governance metadata."
        exit 1
    fi
    print_section "Processing single file $(basename "$input_path")"
    sign_file "$input_path" "$use_cip8" "$new_file"
    print_section "Summary"
    print_pass "File processed successfully"
else
    print_fail "$(fmt_path "$input_path") is not a valid file or directory."
    exit 1
fi
