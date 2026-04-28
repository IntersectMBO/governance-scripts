#!/bin/bash

######################################################

# Can change if you want!

# Default behavior is to not check if file is discoverable on IPFS
CHECK_TOO="false"
JUST_JSONLD="false"

# Pinning services to host the file on IPFS
DEFAULT_HOST_ON_LOCAL_NODE="true"
DEFAULT_HOST_ON_NMKR="true"
DEFAULT_HOST_ON_BLOCKFROST="true"
DEFAULT_HOST_ON_PINATA="true"

# HOST_ON_STORACHA_STORAGE="true"
# https://docs.storacha.network/faq/

######################################################

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail if any command in a pipeline fails
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

# check if user has ipfs cli installed
if ! command -v ipfs >/dev/null 2>&1; then
  print_fail "ipfs cli is not installed or not in your PATH."
  exit 1
fi

# Usage message
usage() {
    printf '%s%sPin files to local IPFS node and via Blockfrost, NMKR and Pinata%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<file|directory>%s [%s--check-too%s] [%s--no-local%s] [%s--no-pinata%s] [%s--no-blockfrost%s] [%s--no-nmkr%s]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<file|directory>"  "Path to your file or directory containing files"
    print_usage_option "[--just-jsonld]"   "If a directory is provided, only .jsonld files will be processed (default: $JUST_JSONLD)"
    print_usage_option "[--check-too]"     "Run a check if file is discoverable on ipfs, only pin if not discoverable (default: $CHECK_TOO)"
    print_usage_option "[--no-local]"      "Don't try to pin file on local ipfs node (default on: $DEFAULT_HOST_ON_LOCAL_NODE)"
    print_usage_option "[--no-pinata]"     "Don't try to pin file on pinata service (default on: $DEFAULT_HOST_ON_PINATA)"
    print_usage_option "[--no-blockfrost]" "Don't try to pin file on blockfrost service (default on: $DEFAULT_HOST_ON_BLOCKFROST)"
    print_usage_option "[--no-nmkr]"       "Don't try to pin file on NMKR service (default on: $DEFAULT_HOST_ON_NMKR)"
    print_usage_option "-h, --help"        "Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_path=""
check_discoverable="$CHECK_TOO"
just_jsonld="$JUST_JSONLD"
local_host="$DEFAULT_HOST_ON_LOCAL_NODE"
pinata_host="$DEFAULT_HOST_ON_PINATA"
blockfrost_host="$DEFAULT_HOST_ON_BLOCKFROST"
nmkr_host="$DEFAULT_HOST_ON_NMKR"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check-too)
            check_discoverable="true"
            shift
            ;;
        --just-jsonld)
            just_jsonld="true"
            shift
            ;;
        --no-local)
            local_host="false"
            shift
            ;;
        --no-pinata)
            pinata_host="false"
            shift
            ;;
        --no-blockfrost)
            blockfrost_host="false"
            shift
            ;;
        --no-nmkr)
            nmkr_host="false"
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

# If no input path provided, show usage
if [ -z "$input_path" ]; then
    print_fail "No file or directory specified"
    usage
fi

# Ensure the input is an actual file or directory
if [ ! -e "$input_path" ]; then
    print_fail "$(fmt_path "$input_path") is not a valid file or directory."
    exit 1
fi

print_banner "IPFS File Pinning Service"
print_info "This script pins files to IPFS using multiple pinning services"

# if pinata is enabled ensure the API key is set
if [ "$pinata_host" = "true" ]; then
    if [ -z "${PINATA_API_KEY:-}" ]; then
        print_fail "PINATA_API_KEY environment variable is not set, but pinning to Pinata is enabled."
        exit 1
    fi
fi

# if blockfrost is enabled ensure the API key is set
if [ "$blockfrost_host" = "true" ]; then
    if [ -z "${BLOCKFROST_API_KEY:-}" ]; then
        print_fail "BLOCKFROST_API_KEY environment variable is not set, but pinning to Blockfrost is enabled."
        exit 1
    fi
fi

# if nmkr is enabled ensure the API key and user id is set
if [ "$nmkr_host" = "true" ]; then
    if [ -z "${NMKR_API_KEY:-}" ]; then
        print_fail "NMKR_API_KEY environment variable is not set, but pinning to NMKR is enabled."
        exit 1
    fi
    if [ -z "${NMKR_USER_ID:-}" ]; then
        print_fail "NMKR_USER_ID environment variable is not set, but pinning to NMKR is enabled."
        exit 1
    fi
fi

# Function to pin a single file
pin_single_file() {
    local file="$1"

    print_section "Processing $(basename "$file")"
    print_info "Path: $(fmt_path "$file")"

    # Generate CID from the given file
    print_info "Generating CID for the file..."

    # use ipfs add to generate a CID
    # use CIDv1
    ipfs_cid=$(ipfs add -Q --cid-version 1 "$file")
    print_info "CID: ${YELLOW}${ipfs_cid}${NC}"

    # If user wants to check if file is discoverable on IPFS
    if [ "$check_discoverable" = "true" ]; then
        print_info "Using ./scripts/ipfs-check.sh to check if file is discoverable on IPFS..."
        # check if file is discoverable on IPFS
        if ! ./scripts/ipfs-check.sh "$file"; then
            print_warn "File is not discoverable on IPFS. Proceeding to pin it."
        else
            print_pass "File is already discoverable on IPFS. No need to pin it."
            return 0
        fi
    else
        print_info "Skipping discoverability check"
    fi

    print_info "Pinning to enabled services..."

    # Pin on local node
    if [ "$local_host" = "true" ]; then
        print_info "Pinning file on local IPFS node..."
        if ipfs pin add "$ipfs_cid"; then
            print_pass "File pinned successfully on local IPFS node."
        else
            print_fail "Failed to pin file on local IPFS node."
            return 1
        fi
    else
        print_info "Skipping pinning on local IPFS node."
    fi

    # Pin on Pinata
    if [ "$pinata_host" = "true" ]; then
        print_info "Pinning file to Pinata..."
        if [ -z "$PINATA_API_KEY" ]; then
            print_fail "PINATA_API_KEY environment variable is not set."
            return 1
        fi
        response=$(curl -s -X POST "https://uploads.pinata.cloud/v3/files" \
                    -H "Authorization: Bearer ${PINATA_API_KEY}" \
                    -F "file=@$file" \
                    -F "network=public" \
                )
        # Check response for errors
        if echo "$response" | grep -q '"errors":'; then
            print_fail "Error in Pinata response:"
            echo "$response" | jq . >&2
            return 1
        fi

        print_pass "Pinata upload successful"
    else
        print_info "Skipping pinning on Pinata."
    fi

    # Pin on Blockfrost
    if [ "$blockfrost_host" = "true" ]; then
        print_info "Pinning file to Blockfrost..."
        if [ -z "$BLOCKFROST_API_KEY" ]; then
            print_fail "BLOCKFROST_API_KEY environment variable is not set."
            return 1
        fi
        response=$(curl -s -X POST "https://ipfs.blockfrost.io/api/v0/ipfs/add" \
                    -H "project_id: $BLOCKFROST_API_KEY" \
                    -F "file=@$file" \
                )
        # Check response for errors
        if echo "$response" | grep -q '"errors":'; then
            print_fail "Error in Blockfrost response:"
            echo "$response" | jq . >&2
            return 1
        fi

        print_pass "Blockfrost upload successful"
    else
        print_info "Skipping pinning on Blockfrost."
    fi

    # Pin on NMKR
    if [ "$nmkr_host" = "true" ]; then
        print_info "Pinning file to NMKR..."
        if [ -z "$NMKR_API_KEY" ]; then
            print_fail "NMKR_API_KEY environment variable is not set."
            return 1
        fi
        if [ -z "$NMKR_USER_ID" ]; then
            print_fail "NMKR_USER_ID environment variable is not set."
            return 1
        fi

        # base64 encode the file because NMKR API requires it
        base64_content=$(base64 -i "$file")

        response=$(curl -s -X POST "https://studio-api.nmkr.io/v2/UploadToIpfs/${NMKR_USER_ID}" \
            -H 'accept: text/plain' \
            -H 'Content-Type: application/json' \
            -H "Authorization: Bearer ${NMKR_API_KEY}" \
            -d @- <<EOF
{
    "fileFromBase64": "$base64_content",
    "name": "$(basename "$file")",
    "mimetype": "application/json"
}
EOF
        )
        # Check response for errors
        if echo "$response" | grep -q '"errors":'; then
            print_fail "Error in NMKR response:"
            echo "$response" | jq . >&2
            return 1
        fi

        print_pass "NMKR upload successful"
    else
        print_info "Skipping pinning on NMKR."
    fi

    print_pass "File pinning completed: $(fmt_path "$file")"
    print_kv "CID" "$ipfs_cid"
}

# Main processing logic
if [ -d "$input_path" ]; then
    # If input is a directory: pin files (optionally only .jsonld files) including subdirectories
    print_section "Processing directory $(basename "$input_path")"
    print_info "Path: $(fmt_path "$input_path")"

    # if just jsonld is true, only process .jsonld files
    files_to_process=()
    if [ "$just_jsonld" = "true" ]; then
        # Only .jsonld files
        while IFS= read -r -d '' file; do
            files_to_process+=("$file")
        done < <(find "$input_path" -type f -name "*.jsonld" -print0)
    else
        # else do all files
        while IFS= read -r -d '' file; do
            files_to_process+=("$file")
        done < <(find "$input_path" -type f -print0)
    fi

    # check if any files were found
    if [ ${#files_to_process[@]} -eq 0 ]; then
        if [ "$just_jsonld" = "true" ]; then
            print_fail "No .jsonld files found in directory (including subdirectories): $(fmt_path "$input_path")"
        else
            print_fail "No files found in directory (including subdirectories): $(fmt_path "$input_path")"
        fi
        exit 1
    fi

    print_info "Found ${YELLOW}${#files_to_process[@]}${NC} files to process"

    # for each file in the directory, pin it
    for file in "${files_to_process[@]}"; do
        # ask user if they want to continue with the next file
        # skip for the first file
        if [ "$file" != "${files_to_process[0]}" ]; then
            print_info "The next file is: $(fmt_path "$file")"
            if ! confirm "Continue with the next file?"; then
                print_fail "Cancelled by user"
                exit 1
            fi
        fi
        pin_single_file "$file"
    done

    print_section "Summary"
    print_pass "All ${#files_to_process[@]} files processed successfully"

elif [ -f "$input_path" ]; then
    # Input is a single file
    pin_single_file "$input_path"
    print_section "Summary"
    print_pass "File processed successfully"
else
    print_fail "$(fmt_path "$input_path") is not a valid file or directory."
    exit 1
fi
