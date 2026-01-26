#!/bin/bash

##################################################
# Governance Scripts CLI Wrapper
# Provides a unified interface to all governance scripts
##################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
UNDERLINE='\033[4m'
BOLD='\033[1m'
GRAY='\033[0;90m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# Usage message
usage() {
    echo -e "${UNDERLINE}${BOLD}Governance Scripts CLI${NC}"
    echo -e "\n"
    echo -e "Usage: ${BOLD}governance ${GREEN}<command>${NC} [options]"
    echo -e "\n"
    echo -e "${BOLD}Available Commands:${NC}"
    echo -e "  ${GREEN}author-create${NC}           Sign metadata files with author witness"
    echo -e "  ${GREEN}author-validate${NC}         Validate author signatures in metadata"
    echo -e "  ${GREEN}action-info${NC}             Create an Info action from JSON-LD metadata"
    echo -e "  ${GREEN}action-treasury${NC}         Create a Treasury Withdrawal action"
    echo -e "  ${GREEN}metadata-create${NC}         Create JSON-LD metadata from Markdown"
    echo -e "  ${GREEN}metadata-validate${NC}       Validate JSON-LD metadata"
    echo -e "  ${GREEN}metadata-canonize${NC}       Canonize JSON-LD metadata"
    echo -e "  ${GREEN}cip108-human${NC}            Create human-readable CIP-108 format"
    echo -e "  ${GREEN}hash${NC}                    Hash a file"
    echo -e "  ${GREEN}ipfs-check${NC}              Check IPFS pinning status"
    echo -e "  ${GREEN}ipfs-pin${NC}                Pin files to IPFS"
    echo -e "  ${GREEN}pdf-remove-metadata${NC}     Remove metadata from PDF files"
    echo -e "\n"
    echo -e "Use ${BOLD}governance ${GREEN}<command>${NC} ${YELLOW}-h${NC} for more information about a specific command"
    echo -e "\n"
    exit 1
}

# Check if at least one argument is provided
if [ $# -eq 0 ]; then
    usage
fi

# Get the command
COMMAND="$1"
shift

# Map commands to script files
case "$COMMAND" in
    author-create)
        exec "$SCRIPTS_DIR/author-create.sh" "$@"
        ;;
    author-validate)
        exec "$SCRIPTS_DIR/author-validate.sh" "$@"
        ;;
    action-info)
        exec "$SCRIPTS_DIR/action-create-info.sh" "$@"
        ;;
    action-treasury)
        exec "$SCRIPTS_DIR/action-create-tw.sh" "$@"
        ;;
    metadata-create)
        exec "$SCRIPTS_DIR/metadata-create.sh" "$@"
        ;;
    metadata-validate)
        exec "$SCRIPTS_DIR/metadata-validate.sh" "$@"
        ;;
    metadata-canonize)
        exec "$SCRIPTS_DIR/metadata-canonize.sh" "$@"
        ;;
    cip108-human)
        exec "$SCRIPTS_DIR/cip-108-create-human-readable.sh" "$@"
        ;;
    hash)
        exec "$SCRIPTS_DIR/hash.sh" "$@"
        ;;
    ipfs-check)
        exec "$SCRIPTS_DIR/ipfs-check.sh" "$@"
        ;;
    ipfs-pin)
        exec "$SCRIPTS_DIR/ipfs-pin.sh" "$@"
        ;;
    pdf-remove-metadata)
        exec "$SCRIPTS_DIR/pdf-remove-metadata.sh" "$@"
        ;;
    query-actions)
        exec "$SCRIPTS_DIR/query-live-actions.sh" "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo -e "${RED}Error: Unknown command '${COMMAND}'${NC}" >&2
        echo ""
        usage
        ;;
esac
