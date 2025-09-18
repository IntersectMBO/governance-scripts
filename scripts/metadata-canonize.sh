#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <jsonld-file>"
    exit 1
fi

# Input file
input_file="$1"

# Check if the file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Anchor file '$input_file' not found!"
    exit 1
fi


# hash of the input file using cardano-cli
hash=$(cardano-signer canonize --data-file $input_file --cip100 --json-extended --out-file /dev/stdout | jq -r '.canonizedHash')

# Output the result
echo "For anchor file: $input_file"
echo
echo "Hash of canonized body:"
echo "$hash"