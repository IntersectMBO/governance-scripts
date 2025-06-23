#!/bin/bash

# Function to extract fields from the JSON-LD file
extract_jsonld_data() {
    local jsonld_file=$1

    # Extract the data fields using jq
    local title=$(jq -r '.body.title // empty' "$jsonld_file")
    local abstract=$(jq -r '.body.abstract // empty' "$jsonld_file")
    local motivation=$(jq -r '.body.motivation // empty' "$jsonld_file")
    local rationale=$(jq -r '.body.rationale // empty' "$jsonld_file")
    local authors=$(jq '.authors[] // empty' "$jsonld_file")

    # Extract the references and format them
    local references=$(jq -r '.body.references[] | "- [\(.label)](\(.uri))" // empty' "$jsonld_file")

    # Output to a markdown file
    local output_file="${jsonld_file}.md"

    # Create markdown content
    cat > "$output_file" <<EOF
# Title

$title

# Abstract

$abstract

# Motivation

$motivation

# Rationale

$rationale

# References

$references

# Authors

$authors
EOF

    echo "Markdown file generated: $output_file"
}

# Check if a file or directory is passed as an argument
if [ $# -eq 0 ]; then
    echo "Usage: $0 <file or directory>"
    exit 1
fi

# If the argument is a directory, process each JSON-LD file
if [ -d "$1" ]; then
    for jsonld_file in "$1"/*.jsonld; do
        extract_jsonld_data "$jsonld_file"
    done
elif [ -f "$1" ]; then
    # If it's a single file, process it
    extract_jsonld_data "$1"
else
    echo "Invalid input. Please provide a valid file or directory."
    exit 1
fi
