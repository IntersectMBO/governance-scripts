#!/bin/bash

######################################################
# using permalink to reduce likelihood of breakage, or ability for it to change
INTERSECT_AUTHOR_PATH="https://raw.githubusercontent.com/IntersectMBO/governance-actions/b1c5603fb306623e0261c234312eb7e011ac3d38/intersect-author.json"
CHECK_INTERSECT_AUTHOR="true"
######################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

# Check if cardano-signer is installed
if ! command -v cardano-signer >/dev/null 2>&1; then
  print_fail "cardano-signer is not installed or not in your PATH."
  exit 1
fi

# Usage message
usage() {
    printf '%s%sVerify metadata files with author witness using cardano-signer%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<jsonld-file|directory>%s [%s--no-intersect%s]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<jsonld-file|directory>" "Path to JSON-LD file or directory to verify"
    print_usage_option "[--no-intersect]"        "Don't compare author's public key against Intersect's known key"
    print_usage_option "-h, --help"              "Show this help message and exit"
    exit 1
}

# Check correct number of arguments
if [ "$#" -lt 1 ]; then
    usage
fi

# Parse command line arguments
input_path=""
check_intersect="$CHECK_INTERSECT_AUTHOR"

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-intersect)
            check_intersect="false"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_path" ]; then
                input_path="$1"
                shift
            else
                print_fail "Unknown argument: $1"
                usage
            fi
            ;;
    esac
done

# Check if the metadata input file exists
if [ ! -f "$input_path" ]; then
    print_fail "JSON file $(fmt_path "$input_path") not found"
    exit 1
fi

print_banner "Validating the authors within given governance metadata"

# Get Intersect author public key
if [ "$check_intersect" == "true" ]; then
    print_section "Fetching Intersect author public key"
    print_info "Source: ${YELLOW}${INTERSECT_AUTHOR_PATH}${NC}"
    author_key=$(curl -s "$INTERSECT_AUTHOR_PATH" | jq -r '.publicKey')
    print_info "Intersect author public key: ${YELLOW}${author_key}${NC}"
else
    print_info "Not comparing author's against Intersect's known public key"
fi

# Use cardano-signer to verify author witnesses
# https://github.com/gitmachtl/cardano-signer?tab=readme-ov-file#verify-governance-metadata-and-the-authors-signatures
verify_author_witness() {
    local file="$1"
    local raw_output

    raw_output=$(cardano-signer verify --cip100 \
        --data-file "$file" \
        --json-extended)

    # read exit code of last command
    if [ $? -ne 0 ]; then
        print_fail "cardano-signer command failed while verifying file $(fmt_path "$file")."
        exit 1
    fi

    # cardano-signer's --json-extended can emit unescaped control chars (e.g. raw newlines in body.abstract), which jq rejects. Escape them.
    local output
    output=$(printf '%s' "$raw_output" | perl -pe 's/([\x00-\x1f])/sprintf("\\u%04x",ord($1))/ge' | jq '{result, errorMsg, authors, canonizedHash, fileHash}')

    print_kv "Result"          "$(echo "$output" | jq -r '.result')"
    print_kv "Error Messages"  "$(echo "$output" | jq -r '.errorMsg')"
    print_kv "Authors"         "$(echo "$output" | jq -c '.authors')"
    print_kv "Canonized Hash"  "$(echo "$output" | jq -r '.canonizedHash')"
    print_kv "File Hash"       "$(echo "$output" | jq -r '.fileHash')"

    local result
    result=$(echo "$output" | jq -r '.result')
    if [ "$result" != "true" ]; then
        print_fail "Verification failed with result: $result"
        exit 1
    fi
}

# Give the user a warning if the author isn't Intersect
check_if_correct_author() {
    local file="$1"
    author_count=$(jq '.authors | length' "$file")

    # Iterate over all author pubkeys present
    for i in $(seq 0 $(($author_count - 1))); do
        file_author_key=$(jq -r ".authors[$i].witness.publicKey" "$file")
        print_section "Checking author index $i public key against Intersect's keys"

        # if author's public key matches Intersect's public key
        if [ "$file_author_key" == "$author_key" ]; then
            # and if author name is intersect
            if [ "$(jq -r ".authors[$i].name" "$file")" == "Intersect" ]; then
                print_pass "Author pub key and name is correctly set to 'Intersect'."
            else
                print_warn "Author name is NOT set to 'Intersect' but public key matches Intersect's key."
                print_kv "Author name"       "$(jq -r ".authors[$i].name" "$file")"
                print_kv "Author public key" "$file_author_key"
            fi

        else
            print_warn "Author public key is not Intersect's key."
            print_kv "Author name"       "$(jq -r ".authors[$i].name" "$file")"
            print_kv "Author public key" "$file_author_key"
        fi
    done
}

if [ -d "$input_path" ]; then
    # If input is a directory: verify all .jsonld files
    shopt -s nullglob
    jsonld_files=("$input_path"/*.jsonld)
    # check if any .jsonld files were found
    if [ ${#jsonld_files[@]} -eq 0 ]; then
        print_fail "No .jsonld files found in directory $(fmt_path "$input_path")."
        exit 1
    fi
    # for each .jsonld file in the directory, go over it
    for file in "${jsonld_files[@]}"; do
        print_section "Verifying signature on $(basename "$file")"
        verify_author_witness "$file"
        if [ "$check_intersect" == "true" ]; then
            check_if_correct_author "$file"
        fi
    done
elif [ -f "$input_path" ]; then
    # Input is a single file
    print_section "Verifying signature on $(basename "$input_path")"
    verify_author_witness "$input_path"
    if [ "$check_intersect" == "true" ]; then
        check_if_correct_author "$input_path"
    fi

else
    print_fail "$(fmt_path "$input_path") is not a valid file or directory."
    exit 1
fi
