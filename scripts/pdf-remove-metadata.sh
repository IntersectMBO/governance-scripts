#!/bin/bash

##################################################
DEFAULT_NEW_FILE="false" # default to false, to the script overwrites the input file
##################################################

# Exit immediately if a command exits with a non-zero status, 
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

# check if user has exiftool cli installed
if ! command -v exiftool >/dev/null 2>&1; then
  echo "Error: exiftool cli is not installed or not in your PATH." >&2
  exit 1
fi

# check if user has qpdf cli installed
if ! command -v qpdf >/dev/null 2>&1; then
  echo "Error: qpdf cli is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <pdf-file> [--new-file]"
    echo "Remove all metadata from a PDF file and set the Title metadata to the filename."
    echo "  "
    echo "Options:"
    echo "  <pdf-file>            Path to your PDF file."
    echo "  --new-file            Create a new file with the signed metadata (default: $DEFAULT_NEW_FILE)"
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
    echo "Error: Could not find PDF file."
    usage
fi

# Extract filename without extension
BASENAME=$(basename "$input_path" .pdf)

# could add some logic here
TITLE=$(echo "$BASENAME")

# We need to create a new PDF, as it is not possible to overwrite the original PDF with exiftool
if [ "$new_file" = "true" ]; then
    output_new_file="${BASENAME}-new-metadata.pdf"
    # remove all metadata from the original PDF and create a new PDF
    exiftool -all= "$input_path" -o "$output_new_file"
    # remove all hidden metadata
    qpdf --linearize "$input_path" --replace-input
    # add the Title metadata to the new PDF
    exiftool -Title="$TITLE" "$output_new_file" -overwrite_original_in_place
    echo "Metadata processing completed. New file: $output_new_file with Title: $TITLE"
else
    # remove all metadata from the original PDF
    exiftool -all= "$input_path" -overwrite_original_in_place
    # remove all hidden metadata from the original PDF
    qpdf --linearize "$input_path" --replace-input
    # add the Title metadata to the original PDF
    exiftool -Title="$TITLE" "$input_path" -overwrite_original_in_place
    echo "Metadata processing completed. Your file: $input_path now only has a Title: $TITLE"
fi
