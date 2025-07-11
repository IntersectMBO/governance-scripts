#!/bin/bash


######################################################

# Can change if you want!

AUTHOR_CHECK="true"
IPFS_CHECK="true"

######################################################

# Exit immediately if a command exits with a non-zero status, 
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

# Colors
#BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BRIGHTWHITE='\033[0;37;1m'
NC='\033[0m'

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
                echo "Checking author for $file"
                ./scripts/author-verify-witness.sh "$file"
            fi

            echo " "
            echo "Running schema and spell check on: $file"
            ./scripts/metadata-validate.sh "$file" --intersect-budget

            if [ "$check_ipfs" = "true" ]; then
                echo " "
                echo "Checking IPFS status for $file"
                ./scripts/ipfs-check.sh "$file"
            fi

            # get content from the file for budget specific checks
            title=$(jq -r '.body.title' "$file")
            ga_type=$(jq -r '.body.onChain.governanceActionType' "$file")
            deposit_return=$(jq -r '.body.onChain.depositReturnAddress' "$file")
            withdrawal_amount=$(jq -r '.body.onChain.withdrawals[0].withdrawalAmount' "$file")
            withdrawal_address=$(jq -r '.body.onChain.withdrawals[0].withdrawalAddress' "$file")

            # ensure the correct type is there
            if [ "$ga_type" = "treasuryWithdrawals" ]; then
                echo "Metadata has correct governanceActionType"
            else
                echo "Metadata does not have the correct governanceActionType"
                echo "Expected: treasuryWithdrawals found: $ga_type"
                exit 1
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