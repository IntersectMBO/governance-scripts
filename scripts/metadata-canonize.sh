#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    printf 'Usage: %s <jsonld-file>\n' "$0"
    exit 1
fi

# Input file
input_file="$1"

# Enforce .jsonld extension
if [[ "$input_file" != *.jsonld ]]; then
    print_fail "Input file $(fmt_path "$input_file") must be a JSON-LD metadata file with a .jsonld extension."
    print_hint "This script produces a blake2b-256 hash of the canonized body for author-signature workflows."
    exit 1
fi

# Check if the file exists
if [ ! -f "$input_file" ]; then
    print_fail "Anchor file $(fmt_path "$input_file") not found"
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
print_section "Canonized body hash"
print_kv "File" "$(fmt_path "$input_file")"
print_kv "Hash" "$hash"
