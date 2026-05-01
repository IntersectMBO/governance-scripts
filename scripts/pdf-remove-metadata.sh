#!/bin/bash

##################################################
DEFAULT_NEW_FILE="false" # default to false, to the script overwrites the input file
##################################################

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

# check if user has exiftool cli installed
if ! command -v exiftool >/dev/null 2>&1; then
  print_fail "exiftool cli is not installed or not in your PATH."
  exit 1
fi

# check if user has qpdf cli installed
if ! command -v qpdf >/dev/null 2>&1; then
  print_fail "qpdf cli is not installed or not in your PATH."
  exit 1
fi

# Usage message
usage() {
    printf '%s%sRemove all metadata from a PDF file and set the Title metadata to the filename%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<pdf-file>%s [%s--new-file%s]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<pdf-file>"   "Path to your PDF file"
    print_usage_option "[--new-file]" "Create a new file with the signed metadata (default: $DEFAULT_NEW_FILE)"
    print_usage_option "-h, --help"   "Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_path=""
new_file="$DEFAULT_NEW_FILE"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
            fi
            shift
            ;;
    esac
done

# Check for required arguments
if [ -z "$input_path" ]; then
    print_fail "Could not find PDF file."
    usage
fi

# Enforce .pdf extension
if [[ "$input_path" != *.pdf ]]; then
    print_fail "Input file $(fmt_path "$input_path") must be a PDF file with a .pdf extension."
    print_hint "This script uses exiftool and qpdf to strip and rewrite PDF metadata."
    exit 1
fi

# Ensure the input file actually exists
if [ ! -f "$input_path" ]; then
    print_fail "Input file $(fmt_path "$input_path") not found."
    exit 1
fi

# Extract filename without extension
BASENAME=$(basename "$input_path" .pdf)

# could add some logic here
TITLE="$BASENAME"

if [ "$new_file" = "true" ]; then
    output_new_file="$input_path-new-metadata.pdf"
    # remove all metadata from the original PDF and create a new PDF
    exiftool -all= "$input_path" -o "$output_new_file"
    # remove all hidden metadata
    qpdf --linearize "$input_path" --replace-input
    # add the Title metadata to the new PDF
    exiftool -Title="$TITLE" "$output_new_file" -overwrite_original_in_place
    print_section "Summary"
    print_pass "PDF metadata replaced (new file)"
    print_kv "Output" "$(fmt_path "$output_new_file")"
    print_kv "Title"  "$TITLE"
else
    # remove all metadata from the original PDF
    exiftool -all= "$input_path" -overwrite_original_in_place
    # remove all hidden metadata from the original PDF
    qpdf --linearize "$input_path" --replace-input
    # add the Title metadata to the original PDF
    exiftool -Title="$TITLE" "$input_path" -overwrite_original_in_place
    print_section "Summary"
    print_pass "PDF metadata replaced (in place)"
    print_kv "File"  "$(fmt_path "$input_path")"
    print_kv "Title" "$TITLE"
fi
