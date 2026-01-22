#!/bin/bash

##################################################
DEFAULT_NEW_FILE="false" # default to false, to the script overwrites the input file
##################################################

# Exit immediately if a command exits with a non-zero status, 
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BRIGHTWHITE='\033[0;37;1m'
NC='\033[0m'
UNDERLINE='\033[4m'
BOLD='\033[1m'
GRAY='\033[0;90m'

# check if user has exiftool cli installed
if ! command -v exiftool >/dev/null 2>&1; then
  echo -e "${RED}Error: exiftool cli is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# check if user has qpdf cli installed
if ! command -v qpdf >/dev/null 2>&1; then
  echo -e "${RED}Error: qpdf cli is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Usage message
usage() {
    local col=50
    echo -e "${UNDERLINE}${BOLD}Remove all metadata from a PDF file and set the Title metadata to the filename${NC}"
    echo -e "\n"
    echo -e "Syntax:${BOLD} $0 ${GREEN}<pdf-file>${NC} [${GREEN}--new-file${NC}]"
    printf "Params: ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "<pdf-file>" "- Path to your PDF file"
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--new-file]" "- Create a new file with the signed metadata (default: $DEFAULT_NEW_FILE)"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "-h, --help" "- Show this help message and exit"
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

if [ "$new_file" = "true" ]; then
    output_new_file="$input_path-new-metadata.pdf"
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
