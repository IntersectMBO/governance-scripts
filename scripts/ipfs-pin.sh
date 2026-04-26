#!/bin/bash

######################################################

# Can change if you want!

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

# Colors
#BLACK='\033[0;30m'
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

# check if user has ipfs cli installed
if ! command -v ipfs >/dev/null 2>&1; then
  echo -e "${RED}Error: ipfs cli is not installed or not in your PATH.${NC}" >&2
  exit 1
fi

# Auth-header tmp file plumbing. We pass the API key to curl via `-H @file`
# (header-file syntax, curl >= 7.55) so the secret never appears in this
# process's argv, where it would otherwise be visible to any user on the
# system via `ps`. Files are mktemp'd with mode 600 and removed on exit.
SECRET_TMP_FILES=()
cleanup_secret_files() {
    local f
    for f in "${SECRET_TMP_FILES[@]:-}"; do
        [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
    done
}
trap cleanup_secret_files EXIT INT TERM

# Create a 0600 tmp file containing one HTTP header line and emit its path on
# stdout. The caller passes that path to `curl -H @path`. Track it for cleanup.
write_auth_header_file() {
    local header_line="$1"
    local f
    f=$(mktemp "${TMPDIR:-/tmp}/ipfs-pin-auth.XXXXXX")
    chmod 600 "$f"
    printf '%s\n' "$header_line" > "$f"
    SECRET_TMP_FILES+=("$f")
    printf '%s' "$f"
}

# Usage message
usage() {
    local col=50
    echo -e "${UNDERLINE}${BOLD}Pin files to local IPFS node and via Blockfrost, NMKR and Pinata${NC}"
    echo -e "\n"
    echo -e "Syntax:${BOLD} $0 ${GREEN}<file|directory>${NC} [${GREEN}--directory${NC}] [${GREEN}--no-local${NC}] [${GREEN}--no-pinata${NC}] [${GREEN}--no-blockfrost${NC}] [${GREEN}--no-nmkr${NC}]"
    printf "Params: ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "<file|directory>" "- Path to your file or directory containing files"
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--directory]" "- REQUIRED if the path is a directory. Without this flag, a directory path is rejected to prevent accidental bulk uploads (e.g. pointing at a project root and pinning every file in it). Treat this as the equivalent of rm's '-r'."
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--just-jsonld]" "- If --directory is set, only .jsonld files will be processed (default: $JUST_JSONLD)"
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--no-local]" "- Don't try to pin file on local ipfs node (default: $DEFAULT_HOST_ON_LOCAL_NODE)"
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--no-pinata]" "- Don't try to pin file on pinata service (default: $DEFAULT_HOST_ON_PINATA)"
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--no-blockfrost]" "- Don't try to pin file on blockfrost service (default: $DEFAULT_HOST_ON_BLOCKFROST)"
    printf "        ${GREEN}%-*s${NC}${GRAY}%s${NC}\n" $((col-8)) "[--no-nmkr]" "- Don't try to pin file on NMKR service (default: $DEFAULT_HOST_ON_NMKR)"
    printf "        ${GREEN}%-*s${GRAY}%s${NC}\n" $((col-8)) "-h, --help" "- Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_path=""
just_jsonld="$JUST_JSONLD"
allow_directory="false"
local_host="$DEFAULT_HOST_ON_LOCAL_NODE"
pinata_host="$DEFAULT_HOST_ON_PINATA"
blockfrost_host="$DEFAULT_HOST_ON_BLOCKFROST"
nmkr_host="$DEFAULT_HOST_ON_NMKR"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --directory)
            allow_directory="true"
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
    echo -e "${RED}Error: No file or directory specified${NC}" >&2
    usage
fi

# Ensure the input is an actual file or directory
if [ ! -e "$input_path" ]; then
    echo -e "${RED}Error: '${YELLOW}$input_path${RED}' is not a valid file or directory.${NC}" >&2
    exit 1
fi

echo -e " "
echo -e "${CYAN}IPFS File Pinning Service${NC}"
echo -e "${CYAN}This script pins files to IPFS using multiple pinning services${NC}"

# if pinata is enabled ensure the API key is set
if [ "$pinata_host" = "true" ]; then
    if [ -z "${PINATA_API_KEY:-}" ]; then
        echo -e "${RED}Error: PINATA_API_KEY environment variable is not set, but pinning to Pinata is enabled.${NC}" >&2
        exit 1
    fi
fi

# if blockfrost is enabled ensure the API key is set
if [ "$blockfrost_host" = "true" ]; then
    if [ -z "${BLOCKFROST_API_KEY:-}" ]; then
        echo -e "${RED}Error: BLOCKFROST_API_KEY environment variable is not set, but pinning to Blockfrost is enabled.${NC}" >&2
        exit 1
    fi
fi
    
# if nmkr is enabled ensure the API key and user id is set
if [ "$nmkr_host" = "true" ]; then
    if [ -z "${NMKR_API_KEY:-}" ]; then
        echo -e "${RED}Error: NMKR_API_KEY environment variable is not set, but pinning to NMKR is enabled.${NC}" >&2
        exit 1
    fi
    if [ -z "${NMKR_USER_ID:-}" ]; then
        echo -e "${RED}Error: NMKR_USER_ID environment variable is not set, but pinning to NMKR is enabled.${NC}" >&2
        exit 1
    fi
fi

# Refuse to pin obviously-secret files. Public-IPFS pinning a Cardano signing
# key (.skey) or an .env credentials file would publish it permanently
SENSITIVE_BASENAME_REGEX='\.(skey|vkey|env)$|^\.env(\..*)?$|^id_(rsa|ed25519|ecdsa|dsa)(\.pub)?$|\.(pem|p12|pfx)$'
is_sensitive_filename() {
    local name
    name=$(basename "$1")
    [[ "$name" =~ $SENSITIVE_BASENAME_REGEX ]]
}

# Function to pin a single file
pin_single_file() {
    local file="$1"

    if is_sensitive_filename "$file"; then
        echo -e " "
        echo -e "${RED}Refusing to pin '${YELLOW}$file${RED}': filename matches a sensitive pattern (signing key / env / private key / cert). Pinning would publish it permanently to public IPFS.${NC}" >&2
        echo -e "${GRAY}If you genuinely intend to pin this file, rename it first or remove it from the directory tree.${NC}" >&2
        return 1
    fi

    echo -e " "
    echo -e "${CYAN}Processing file: ${YELLOW}$file${NC}"

    # Generate CID from the given file
    echo -e "${CYAN}Generating CID for the file...${NC}"
    
    # use ipfs add to generate a CID
    # use CIDv1
    ipfs_cid=$(ipfs add -Q --cid-version 1 "$file")
    echo -e "CID: ${YELLOW}$ipfs_cid${NC}"

    echo -e " "
    echo -e "${CYAN}Pinning file to enabled services...${NC}"
    
    # Pin on local node
    if [ "$local_host" = "true" ]; then
        echo -e " "
        echo -e "${CYAN}Pinning file on local IPFS node...${NC}"
        if ipfs pin add "$ipfs_cid"; then
            echo -e "${GREEN}File pinned successfully on local IPFS node.${NC}"
        else
            echo -e "${RED}Failed to pin file on local IPFS node.${NC}" >&2
            return 1
        fi
    else
        echo -e "${YELLOW}Skipping pinning on local IPFS node.${NC}"
    fi
    
    # Pin on Pinata
    if [ "$pinata_host" = "true" ]; then
        echo -e " "
        echo -e "${CYAN}Pinning file to Pinata...${NC}"
        
        # Check for secret environment variables
        echo -e "${CYAN}Reading Pinata API key from environment variable...${NC}"
        if [ -z "$PINATA_API_KEY" ]; then
            echo -e "${RED}Error: PINATA_API_KEY environment variable is not set.${NC}" >&2
            return 1
        fi
        
        echo -e "${CYAN}Uploading file to Pinata service...${NC}"
        pinata_auth_file=$(write_auth_header_file "Authorization: Bearer ${PINATA_API_KEY}")
        response=$(curl -s -X POST "https://uploads.pinata.cloud/v3/files" \
                    -H "@${pinata_auth_file}" \
                    -F "file=@$file" \
                    -F "network=public" \
                )
        # Check response for errors
        if echo "$response" | grep -q '"errors":'; then
            echo -e "${RED}Error in Pinata response:${NC}" >&2
            echo "$response" | jq . >&2
            return 1
        fi
        
        echo -e "${GREEN}Pinata upload successful!${NC}"
    else
        echo -e "${YELLOW}Skipping pinning on Pinata.${NC}"
    fi
    
    # Pin on Blockfrost
    if [ "$blockfrost_host" = "true" ]; then
        echo -e " "
        echo -e "${CYAN}Pinning file to Blockfrost...${NC}"
        
        # Check for secret environment variables
        echo -e "${CYAN}Reading Blockfrost API key from environment variable...${NC}"
        if [ -z "$BLOCKFROST_API_KEY" ]; then
            echo -e "${RED}Error: BLOCKFROST_API_KEY environment variable is not set.${NC}" >&2
            return 1
        fi
        
        echo -e "${CYAN}Uploading file to Blockfrost service...${NC}"
        blockfrost_auth_file=$(write_auth_header_file "project_id: $BLOCKFROST_API_KEY")
        response=$(curl -s -X POST "https://ipfs.blockfrost.io/api/v0/ipfs/add" \
                    -H "@${blockfrost_auth_file}" \
                    -F "file=@$file" \
                )
        # Check response for errors
        if echo "$response" | grep -q '"errors":'; then
            echo -e "${RED}Error in Blockfrost response:${NC}" >&2
            echo "$response" | jq . >&2
            return 1
        fi
        
        echo -e "${GREEN}Blockfrost upload successful!${NC}"
    else
        echo -e "${YELLOW}Skipping pinning on Blockfrost.${NC}"
    fi
    
    # Pin on NMKR
    if [ "$nmkr_host" = "true" ]; then
        echo -e " "
        echo -e "${CYAN}Pinning file to NMKR...${NC}"
        
        # Check for secret environment variables
        echo -e "${CYAN}Reading NMKR API key from environment variable...${NC}"
        if [ -z "$NMKR_API_KEY" ]; then
            echo -e "${RED}Error: NMKR_API_KEY environment variable is not set.${NC}" >&2
            return 1
        fi
        echo -e "${CYAN}Reading NMKR user id from environment variable...${NC}"
        if [ -z "$NMKR_USER_ID" ]; then
            echo -e "${RED}Error: NMKR_USER_ID environment variable is not set.${NC}" >&2
            return 1
        fi
        
        # base64 encode the file because NMKR API requires it
        echo -e "${CYAN}Encoding file to base64...${NC}"
        base64_content=$(base64 -i "$file")
        
        echo -e "${CYAN}Uploading file to NMKR service...${NC}"
        nmkr_auth_file=$(write_auth_header_file "Authorization: Bearer ${NMKR_API_KEY}")
        # Build the JSON body with jq so the basename and base64 payload are
        # properly escaped
        nmkr_body=$(jq -n \
            --arg b64 "$base64_content" \
            --arg name "$(basename "$file")" \
            '{fileFromBase64: $b64, name: $name, mimetype: "application/json"}')
        response=$(curl -s -X POST "https://studio-api.nmkr.io/v2/UploadToIpfs/${NMKR_USER_ID}" \
            -H 'accept: text/plain' \
            -H 'Content-Type: application/json' \
            -H "@${nmkr_auth_file}" \
            --data-binary @- <<<"$nmkr_body")
        # Check response for errors
        if echo "$response" | grep -q '"errors":'; then
            echo -e "${RED}Error in NMKR response:${NC}" >&2
            echo "$response" | jq . >&2
            return 1
        fi
        
        echo -e "${GREEN}NMKR upload successful!${NC}"
    else
        echo -e "${YELLOW}Skipping pinning on NMKR.${NC}"
    fi
    
    echo -e " "
    echo -e "${GREEN}File pinning completed: ${YELLOW}$file${NC}"
    echo -e "CID: ${YELLOW}$ipfs_cid${NC}"
}

# Main processing logic
if [ -d "$input_path" ]; then
    # Directory uploads must be opted into explicitly
    if [ "$allow_directory" != "true" ]; then
        echo -e "${RED}Error: '${YELLOW}$input_path${RED}' is a directory.${NC}" >&2
        echo -e "${YELLOW}Pass ${GREEN}--directory${YELLOW} to confirm you want to recursively pin its contents (think of this as the equivalent of ${GREEN}rm -r${YELLOW} — it will publish every regular non-symlink, non-VCS, non-sensitive file under the tree to public IPFS, irreversibly).${NC}" >&2
        echo -e "${GRAY}Combine with ${GREEN}--just-jsonld${GRAY} to limit the walk to *.jsonld files.${NC}" >&2
        exit 1
    fi
    echo -e " "
    echo -e "${YELLOW}Warning: ${GREEN}--directory${YELLOW} is set — this will recursively pin files under '${BRIGHTWHITE}$input_path${YELLOW}' to every enabled pinning service. Pinning is publishing: anything uploaded becomes permanently retrievable from public IPFS gateways.${NC}" >&2
    echo -e "${CYAN}Processing directory: ${YELLOW}$input_path${NC}"

    # Pruning rules for the recursive walk:
    # - Skip .git / .svn / .hg metadata directories
    # - Skip symlinks (` ! -type l`)
    PRUNE_EXPR=(
        \( -type d \( -name .git -o -name .svn -o -name .hg \) \) -prune
        -o
    )

    files_to_process=()
    if [ "$just_jsonld" = "true" ]; then
        # Only .jsonld files (still skipping VCS dirs and symlinks)
        while IFS= read -r -d '' file; do
            files_to_process+=("$file")
        done < <(find "$input_path" "${PRUNE_EXPR[@]}" -type f ! -type l -name "*.jsonld" -print0)
    else
        # All files (still skipping VCS dirs and symlinks)
        while IFS= read -r -d '' file; do
            files_to_process+=("$file")
        done < <(find "$input_path" "${PRUNE_EXPR[@]}" -type f ! -type l -print0)
    fi
    
    # check if any files were found
    if [ ${#files_to_process[@]} -eq 0 ]; then
        if [ "$just_jsonld" = "true" ]; then
            echo -e "${RED}Error: No .jsonld files found in directory (including subdirectories): ${YELLOW}$input_path${NC}" >&2
        else
            echo -e "${RED}Error: No files found in directory (including subdirectories): ${YELLOW}$input_path${NC}" >&2
        fi
        exit 1
    fi
    
    echo -e "${CYAN}Found ${YELLOW}${#files_to_process[@]}${NC}${CYAN} files to process${NC}"
    
    # for each file in the directory, pin it
    for file in "${files_to_process[@]}"; do
        # ask user if they want to continue with the next file
        # skip for the first file
        if [ "$file" != "${files_to_process[0]}" ]; then
            echo -e " "
            echo -e "${CYAN}The next file is: ${YELLOW}$file${NC}"
            read -p "Do you want to continue with the next file? (y/n): " choice
            case "$choice" in
                y|Y ) echo -e "${GREEN}Continuing with the next file...${NC}";;
                n|N ) echo -e "${YELLOW}Exiting...${NC}"; exit 0;;
                * ) echo -e "${RED}Invalid choice, exiting...${NC}"; exit 1;;
            esac
        fi
        pin_single_file "$file"
    done
    
    echo -e " "
    echo -e "${GREEN}All files processed successfully!${NC}"
    
elif [ -f "$input_path" ]; then
    if [ "$allow_directory" = "true" ]; then
        echo -e "${RED}Error: ${GREEN}--directory${RED} was set, but '${YELLOW}$input_path${RED}' is a single file. Drop ${GREEN}--directory${RED} for single-file uploads.${NC}" >&2
        exit 1
    fi
    # Input is a single file. Reject symlinks: `[ -f X ]` follows the link.
    if [ -L "$input_path" ]; then
        echo -e "${RED}Error: '${YELLOW}$input_path${RED}' is a symbolic link. Refusing to pin a symlink target — pass the real file path instead.${NC}" >&2
        exit 1
    fi
    echo -e " "
    echo -e "${CYAN}Processing single file: ${YELLOW}$input_path${NC}"
    pin_single_file "$input_path"
    echo -e " "
    echo -e "${GREEN}File processed successfully!${NC}"
else
    echo -e "${RED}Error: '$input_path' is not a valid file or directory.${NC}" >&2
    exit 1
fi

