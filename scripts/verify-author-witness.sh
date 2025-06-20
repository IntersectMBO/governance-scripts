#!/bin/bash

######################################################
# using permalink to reduce likelihood of breakage, or ability for it to change
INTERSECT_AUTHOR_PATH="https://raw.githubusercontent.com/IntersectMBO/governance-actions/b1c5603fb306623e0261c234312eb7e011ac3d38/intersect-author.json"
######################################################

# Check if cardano-signer is installed
if ! command -v cardano-signer >/dev/null 2>&1; then
  echo "Error: cardano-signer is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <jsonld-file|directory>"
    exit 1
}

# Check correct number of arguments
if [ "$#" -lt 1 ]; then
    usage
fi

input_path="$1"

# Check if the key input file exists
if [ ! -f "$input_path" ]; then
    echo "Error: JSON file '$input_path' not found!"
    exit 1
fi

# Get Intersect author public key
# echo " "
# echo "Fetching Intersect author public key from $INTERSECT_AUTHOR_PATH"
intersect_author_key=$(curl -s "$INTERSECT_AUTHOR_PATH" | jq -r '.publicKey')
# echo " "

# Use cardano-signer to verify author witnesses
# https://github.com/gitmachtl/cardano-signer?tab=readme-ov-file#verify-governance-metadata-and-the-authors-signatures
verify_author_witness() {
    local file="$1"
    cardano-signer verify --cip100 \
        --data-file "$file" \
        --json-extended | jq '{workMode, result, errorMsg, authors, canonizedHash, fileHash}'
}

# Give the user a warning if the author isn't Intersect
check_if_intersect_author() {
    local file="$1"
    author_count=$(jq '.authors | length' "$file")
    
    # Iterate over all author pubkeys present
    for i in $(seq 0 $(($author_count - 1))); do
        author_key=$(jq -r ".authors[$i].witness.publicKey" "$file")
        
        if [ "$author_key" == "$intersect_author_key" ]; then
            echo "Author public key matches Intersect's known public key."
        else
            echo "Warning: Author public key does NOT match Intersect's known public key."
            echo "Author public key: $author_key"
            echo "Intersect's known public key: $intersect_author_key"
        fi
        echo " "
    done
}

if [ -d "$input_path" ]; then
    # If input is a directory: verify all .jsonld files
    shopt -s nullglob
    jsonld_files=("$input_path"/*.jsonld)
    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        echo "Error: No .jsonld files found in directory '$input_path'."
        exit 1
    fi
    # for each .jsonld file in the directory, go over it
    for file in "${jsonld_files[@]}"; do
        verify_author_witness "$file"
        check_if_intersect_author "$file"
    done
elif [ -f "$input_path" ]; then
    # Input is a single file
    verify_author_witness "$input_path"
    check_if_intersect_author "$input_path"
else
    echo "Error: '$input_path' is not a valid file or directory."
    exit 1
fi