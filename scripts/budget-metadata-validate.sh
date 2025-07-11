#!/bin/bash


######################################################

# Can change if you want!

AUTHOR_CHECK="true"
IPFS_CHECK="true"

######################################################

# Usage message
usage() {
    echo "Usage: $0 <file|directory> [--no-author] [--no-ipfs]"
    echo "Run 2025 Intersect budget treasury withdrawal checks on CIP108 metadata files."
    echo "Check "
    echo "  "
    echo "Options:"
    echo "  <file|directory>         Path to your CIP108 file or directory."
    echo "  --no-author              Skip author witness checks (default check author: $AUTHOR_CHECK)"
    echo "  --no-ipfs                Skip IPFS checks (default check ipfs: $AUTHOR_CHECK)"
    echo "  -h, --help               Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_path=""
check_author="$AUTHOR_CHECK"
check_ipfs="$IPFS_CHECK"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-author)
            check_author="false"
            shift
            ;;
        --no-author)
            check_ipfs="false"
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

echo " "
echo "Running budget metadata validation for: $input_path"

if [ -d "$input_path" ]; then
    # get all .jsonld files in the directory
    jsonld_files=("$input_path"/*.jsonld)
    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        echo "Error: No .jsonld files found in directory '$input_path'."
        exit 1
    fi
    # for each .jsonld file in the directory, go over it
    for file in "${jsonld_files[@]}"; do
        if [ -f "$file" ]; then
            if [ "$check_author" = "true" ]; then
                echo "Author witnesses will be checked..."
                echo " "
                echo "Running validation $file"
                ./scripts/metadata-validate.sh "$file" --intersect-budget
                echo " "
                echo "Checking author for $file"
                ./scripts/author-verify-witness.sh "$file"
                echo " "
            fi
        else
            echo "Error: '$file' is not a valid file."
            exit 1
        fi
    done
else
    echo "Error: '$input_path' is not a valid file or directory."
    exit 1
fi