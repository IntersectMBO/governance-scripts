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
    echo "Usage: $0 <directory> [--no-author] [--no-ipfs] [--deposit-return-addr <stake address>] [--withdrawal-addr <stake address>]"
    echo "Run 2025 Intersect budget treasury withdrawal checks on metadata files."
    echo "Check "
    echo "  "
    echo "Options:"
    echo "  <directory>                            Path to your metadata files directory."
    echo "  --no-author                            Skip author witness checks (default check author: $AUTHOR_CHECK)"
    echo "  --no-ipfs                              Skip IPFS checks (default check ipfs: $AUTHOR_CHECK)"
    echo "  --deposit-return-addr <stake address>  Stake address for deposit return (bech32)"
    echo "  --withdrawal-addr <stake address>      Stake address for withdrawal (bech32)"
    echo "  -h, --help                             Show this help message and exit" 
    exit 1
}

# Initialize variables with defaults
input_path=""
check_author="$AUTHOR_CHECK"
check_ipfs="$IPFS_CHECK"
deposit_return_address_input=""
withdrawal_address_input=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-author)
            check_author="false"
            shift
            ;;
        --no-ipfs)
            check_ipfs="false"
            shift
            ;;
        --deposit-return-addr)
            if [ -n "${2:-}" ]; then
                deposit_return_address_input="$2"
                shift 2
            else
                echo -e "${RED}Error: --deposit-return-addr requires a value${NC}" >&2
                usage
            fi
            ;;
        --withdrawal-addr)
            if [ -n "${2:-}" ]; then
                withdrawal_address_input="$2"
                shift 2
            else
                echo -e "${RED}Error: --withdrawal-addr requires a value${NC}" >&2
                usage
            fi
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
    # get all .jsonld files in the directory and subdirectories
    jsonld_files=()
    while IFS= read -r -d '' file; do
        jsonld_files+=("$file")
    done < <(find "$input_path" -type f -name "*.jsonld" -print0)
    
    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        echo -e " "
        echo -e "${RED}Error: No .jsonld files found in directory (including subdirectories): ${YELLOW}$input_path${NC}" >&2
        exit 1
    fi
    
    # for each .jsonld file in the directory, go over it
    for file in "${jsonld_files[@]}"; do

        # ask user if they want to continue with the next file
        # skip for the first file
        if [ "$file" != "${jsonld_files[0]}" ]; then
            echo -e " "
            echo -e "${CYAN}The next file is: ${YELLOW}$file${NC}"
            read -p "Do you want to continue with the next file? (y/n): " choice
            case "$choice" in
                y|Y ) echo -e "${GREEN}Continuing with the next file...${NC}";;
                n|N ) echo -e "${YELLOW}Exiting...${NC}"; exit 0;;
                * ) echo -e "${RED}Invalid choice, exiting...${NC}"; exit 1;;
            esac
        fi

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
            abstract=$(jq -r '.body.abstract' "$file")
            check_field "abstract" "$abstract"
            motivation=$(jq -r '.body.motivation' "$file")
            check_field "motivation" "$motivation"
            rationale=$(jq -r '.body.rationale' "$file")
            check_field "rationale" "$rationale"
            references=$(jq -r '.body.references' "$file")
            check_field "references" "$references"
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

            # ensure that the term 'ada' is not used in the title
            # this was a common mistake in the past
            if [[ "$title" == *"ada"* ]]; then
                echo -e "${RED}Error: The term 'ada' is not allowed in the title!" >&2
                exit 1
            else
                echo "Title does not contain the term 'ada'"
            fi

            if [[ "$abstract" == *".mark"* ]] || [[ "$motivation" == *".mark"* ]] || [[ "$rationale" == *".mark"* ]]; then
                echo -e "${RED}Error: The term '.mark' is not allowed in the title or abstract!" >&2
                exit 1
            else
                echo "no Marks !!!"
            fi

            # ensure that title is less than 81 characters
            if [ ${#title} -gt 80 ]; then
                echo -e "${RED}Error: Title is too long, must be less than 80 characters" >&2
                exit 1
            else
                echo "Title length is acceptable"
            fi

            # ensure that the abstract is less than 2501 characters 
            if [ ${#abstract} -gt 2500 ]; then
                echo -e "${RED}Error: Abstract is too long, must be less than 2500 characters" >&2
                exit 1
            else
                echo "Abstract length is acceptable"
            fi

            # check that withdrawal amount is in the title
            withdrawal_amount_raw=$(echo "$title" | sed -n 's/.*₳\([0-9,]*\).*/\1/p' | tr -d '"')
            withdrawal_amount_from_title=$(echo "$withdrawal_amount_raw" | tr -d ',' | sed 's/$/000000/')

            if [ "$withdrawal_amount_from_title" != "$withdrawal_amount" ]; then
                echo -e "${RED}Error: Withdrawal amount in the title does not match the withdrawal amount in the metadata!" >&2
                echo -e "Title withdrawal amount: ${YELLOW}$withdrawal_amount_from_title${NC}"
                echo -e "Metadata withdrawal amount: ${YELLOW}$withdrawal_amount${NC}"
                exit 1
            else
                echo "Withdrawal amount in the title matches the metadata"
            fi

            # Check if deposit address is provided
            # and if provided, check if it matches the one in the metadata
            if [ -n "$deposit_return_address_input" ]; then
                if [ "$deposit_return_address_input" != "$deposit_return" ]; then
                    echo -e "${RED}Error: Deposit return address does not match the one in the metadata!${NC}" >&2
                    echo -e "Provided deposit return address: ${YELLOW}$deposit_return_address_input${NC}"
                    echo -e "Metadata deposit return address: ${YELLOW}$deposit_return${NC}"
                    exit 1
                else
                    echo "Deposit return address matches the metadata"
                fi
            fi

            # Check if withdrawal address is provided
            # and if provided, check if it matches the one in the metadata
            if [ -n "$withdrawal_address_input" ]; then
                if [ "$withdrawal_address_input" != "$withdrawal_address" ]; then
                    echo -e "${RED}Error: Withdrawal address does not match the one in the metadata!${NC}" >&2
                    echo -e "Provided withdrawal address: ${YELLOW}$withdrawal_address_input${NC}"
                    echo -e "Metadata withdrawal address: ${YELLOW}$withdrawal_address${NC}"
                    exit 1
                else
                    echo "Withdrawal address matches the metadata"
                fi
            fi
            
            # Check all IPFS references are accessible

            if [ "$check_ipfs" = "true" ]; then
                echo -e " "
                echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
                echo -e " "
                echo -e "${CYAN}Checking all IPFS references are accessible in: ${YELLOW}$file${NC}"
                echo -e "Using ./scripts/ipfs-check.sh"
                reference_uris=$(jq -r '.body.references[].uri' "$file")
                for reference in $reference_uris; do
                    # if reference is a ipfs URI
                    if [[ "$reference" == ipfs://* ]]; then
                        ipfs_hash=$(echo "$reference" | cut -d '/' -f 3)
                        ./scripts/ipfs-check.sh "$ipfs_hash"
                    fi
                done
            fi
            echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            echo -e " "
            echo -e "${GREEN}All checks passed for: ${YELLOW}$file${NC}"
            echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

            # todo add check ekkelisia link in references matches

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