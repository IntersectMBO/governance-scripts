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

# Stage cardano-signer output through a temp file rather than a pipe, because large canonized outputs can exceed the 64 KB pipe buffer".
TMP_RAW=$(mktemp /tmp/canonize_raw.XXXXXX.json)
TMP_ESCAPED=$(mktemp /tmp/canonize_escaped.XXXXXX.json)
trap 'rm -f "$TMP_RAW" "$TMP_ESCAPED"' EXIT

cardano-signer canonize \
  --data-file "$input_file" \
  --cip100 \
  --json-extended \
  --out-file "$TMP_RAW"

# cardano-signer's --json-extended can emit unescaped control chars (e.g. raw newlines in body.abstract), which jq rejects. Escape them in place.
perl -pe 's/([\x00-\x1f])/sprintf("\\u%04x",ord($1))/ge' "$TMP_RAW" > "$TMP_ESCAPED"

hash=$(jq -r '.canonizedHash' "$TMP_ESCAPED")

# Output the result
echo "For anchor file: $input_file"
echo
echo "Hash of canonized body:"
echo "$hash"
