#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

# Usage message
usage() {
    printf '%s%sGenerate BLAKE2b-256 hash of a file%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<jsonld-file>%s\n' "$BOLD" "$0" "$GREEN" "$NC"
    print_usage_option "<jsonld-file>" "Path to the file to hash"
    print_usage_option "-h, --help"    "Show this help message and exit"
    exit 1
}

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

# Input file
input_file="$1"

# Check if the file exists
if [ ! -f "$input_file" ]; then
    print_fail "Anchor file $(fmt_path "$input_file") not found"
    exit 1
fi

# hash of the input file using b2sum
b2sum_hash=$(b2sum -l 256 "$input_file" | awk '{print $1}')

# hash of the input file using cardano-cli
cardano_cli_hash=$(cardano-cli hash anchor-data --file-text "$(realpath "$input_file")")

# Output the result
print_section "Anchor file hash"
print_kv "File"   "$(fmt_path "$input_file")"
print_kv "b2sum"  "$b2sum_hash"
print_kv "cli"    "$cardano_cli_hash"
