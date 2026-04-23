#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <jsonld-file>"
    exit 1
fi

# Input file
input_file="$1"

# Enforce .jsonld extension
if [[ "$input_file" != *.jsonld ]]; then
    echo "Error: Input file '$input_file' must be a JSON-LD metadata file with a .jsonld extension." >&2
    echo "This script produces a blake2b-256 hash of the canonized body for author-signature workflows." >&2
    exit 1
fi

# Check if the file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Anchor file '$input_file' not found!"
    exit 1
fi


# hash of the input file using cardano-cli
# cardano-signer's --json-extended can emit unescaped control chars (e.g. raw newlines in body.abstract), which jq rejects. Escape them.
hash=$(cardano-signer canonize --data-file $input_file --cip100 --json-extended --out-file /dev/stdout | perl -pe 's/([\x00-\x1f])/sprintf("\\u%04x",ord($1))/ge' | jq -r '.canonizedHash')

# Output the result
echo "For anchor file: $input_file"
echo
echo "Hash of canonized body:"
echo "$hash"