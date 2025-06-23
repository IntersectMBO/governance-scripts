#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    exit 1
    echo "Usage: $0 <directory-or-jsonld-files>"
fi

INPUT_DIR="$1"

if [ -d "$INPUT_DIR" ]; then
    # get all .jsonld files in the directory
    jsonld_files=("$INPUT_DIR"/*.jsonld)
    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        echo "Error: No .jsonld files found in directory '$INPUT_DIR'."
        exit 1
    fi
    # for each .jsonld file in the directory, go over it
    for file in "${jsonld_files[@]}"; do
        if [ -f "$file" ]; then
            echo " "
            echo "Running validation $file"
            ./scripts/validate-json.sh "$file"
            echo " "
            echo "Checking author for $file"
            ./scripts/verify-author-witness.sh "$file"
            echo " "
        else
            echo "Error: '$file' is not a valid file."
            exit 1
        fi
    done
else
    echo "Error: '$INPUT_DIR' is not a valid file or directory."
    exit 1
fi