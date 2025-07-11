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
    echo "Usage: $0 <directory> [--no-author] [--no-ipfs]"
    echo "Run 2025 Intersect budget treasury withdrawal checks on metadata files."
    echo "Check "
    echo "  "
    echo "Options:"
    echo "  <directory>              Path to your metadata files."
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

# If no input file provided, show usage
if [ -z "$input_path" ]; then
    echo -e "${RED}Error: No path specified${NC}" >&2
    usage
fi

check_field() {
    local field_name="$1"
    local field_value="$2"
    
    if [ -z "$field_value" ] || [ "$field_value" = "null" ]; then
        echo -e "${RED}Error: Required field '$field_name' not found in metadata${NC}" >&2
        exit 1
    fi
}

if [ -d "$input_path" ]; then
    # get all .jsonld files in the directory
    jsonld_files=("$input_path"/*.jsonld)
    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        echo -e " "
        echo -e "${RED}Error: No .jsonld files found in directory: ${YELLOW}$input_path${NC}" >&2
        exit 1
    fi
    
    # for each .jsonld file in the directory, go over it
    for file in "${jsonld_files[@]}"; do
        if [ -f "$file" ]; then

            if [ "$check_author" = "true" ]; then
                echo -e " "

                echo -e " "
                echo -e "${CYAN}Checking author for ${YELLOW}$file${NC}"
                echo -e "Using ./scripts/author-validate.sh"
                echo -e " "
                ./scripts/author-validate.sh "$file"
                echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            fi

            if [ "$check_ipfs" = "true" ]; then
                echo -e " "
                echo -e "${CYAN}Checking IPFS status for ${YELLOW}$file${NC}"
                echo -e "Using ./scripts/ipfs-check.sh"
                ./scripts/ipfs-check.sh "$file"
                echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            fi

            echo -e " "
            echo -e "${CYAN}Running schema and spell check on: ${YELLOW}$file${NC}"
            echo -e "Using ./scripts/metadata-validate.sh"
            ./scripts/metadata-validate.sh "$file" --intersect-budget
            echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

            echo -e " "
            echo -e "${CYAN}Running budget metadata checks on: ${YELLOW}$file${NC}"

            # get content from the file for budget specific checks
            # exit if null for any of these
            echo -e "Checking the existence of required fields"

            title=$(jq -r '.body.title' "$file")
            check_field "title" "$title"
            ga_type=$(jq -r '.body.onChain.governanceActionType' "$file")
            check_field "governanceActionType" "$ga_type"
            deposit_return=$(jq -r '.body.onChain.depositReturnAddress' "$file")
            check_field "depositReturnAddress" "$deposit_return"
            withdrawal_amount=$(jq -r '.body.onChain.withdrawals[0].withdrawalAmount' "$file")
            check_field "withdrawalAmount" "$withdrawal_amount"
            withdrawal_address=$(jq -r '.body.onChain.withdrawals[0].withdrawalAddress' "$file")
            check_field "withdrawalAddress" "$withdrawal_address"

            # ensure the correct governance action type
            if [ "$ga_type" = "treasuryWithdrawals" ]; then
                echo "Metadata has correct governanceActionType"
            else
                echo "Metadata does not have the correct governanceActionType"
                echo "Expected: treasuryWithdrawals found: $ga_type"
                exit 1
            fi

        else
            echo -e " "
            echo -e "${RED}Error: file is not a valid file: ${YELLOW}$file${NC}" >&2
            exit 1
        fi
    done
else
    echo -e " "
    echo -e "${RED}Error: Input is not a valid directory: ${YELLOW}$input_path${NC}" >&2
    exit 1
fi