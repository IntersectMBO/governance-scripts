#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

WHITE=$'\033[1;37m'
[ -z "${NC}" ] && WHITE=''

##################################################
# Default schema URLs
CIP_100_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0100/cip-0100.common.schema.json"
CIP_108_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0108/cip-0108.common.schema.json"
CIP_119_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0119/cip-0119.common.schema.json"
CIP_136_SCHEMA="https://raw.githubusercontent.com/cardano-foundation/CIPs/refs/heads/master/CIP-0136/cip-136.common.schema.json"

# temp, until CIP-169 is merged
CIP_169_SCHEMA="https://raw.githubusercontent.com/Ryun1/CIPs/refs/heads/cip-governance-metadata-extension/CIP-0169/cip-0169.common.schema.json"
# temp, until CIP-116 PR is merged
CIP_116_CONWAY_SCHEMA="https://raw.githubusercontent.com/Ryun1/CIPs/refs/heads/cip-116-increase-cost-model-max/CIP-0116/cardano-conway.json"

INTERSECT_TREASURY_SCHEMA="https://intersectmbo.github.io/governance-actions/v1.0.0/schemas/treasury-withdrawals/common.schema.json"
INTERSECT_INFO_SCHEMA="https://intersectmbo.github.io/governance-actions/v1.0.0/schemas/info/common.schema.json"
INTERSECT_PPU_SCHEMA="https://intersectmbo.github.io/governance-actions/v1.0.0/schemas/parameter-changes/common.schema.json"

# Default aspell dictionary (fetched at runtime so users don't need a local copy)
CARDANO_ASPELL_DICT_URL="https://raw.githubusercontent.com/IntersectMBO/governance-scripts/refs/heads/main/scripts/cardano-aspell-dict.txt"

# Default schema values
DEFAULT_USE_CIP_100="false"
DEFAULT_USE_CIP_108="false"
DEFAULT_USE_CIP_119="false"
DEFAULT_USE_CIP_136="false"
DEFAULT_USE_CIP_169="false"
DEFAULT_USE_INTERSECT="false"
##################################################

# Check if cardano-signer is installed
if ! command -v cardano-signer >/dev/null 2>&1; then
  print_fail "cardano-signer is not installed or not in your PATH."
  exit 1
fi

# Check if ajv is installed
if ! command -v ajv >/dev/null 2>&1; then
  print_fail "ajv is not installed or not in your PATH."
  exit 1
fi

set -euo pipefail

# Global variables for cleanup
TMP_JSON_FILE=""
TMP_SCHEMAS_DIR="/tmp/schemas"
TMP_DICT_FILE=""

# Cleanup function
cleanup() {
    # Clean up temporary JSON file if it exists
    if [ -n "$TMP_JSON_FILE" ] && [ -f "$TMP_JSON_FILE" ]; then
        rm -f "$TMP_JSON_FILE" 2>/dev/null || true
    fi
    # Clean up temporary schemas directory if it exists
    if [ -d "$TMP_SCHEMAS_DIR" ]; then
        rm -rf "$TMP_SCHEMAS_DIR" 2>/dev/null || true
    fi
    # Clean up downloaded aspell dictionary
    if [ -n "$TMP_DICT_FILE" ] && [ -f "$TMP_DICT_FILE" ]; then
        rm -f "$TMP_DICT_FILE" 2>/dev/null || true
    fi
}

# Set up trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

# Usage message

usage() {
    printf '%s%sValidate a JSON-LD metadata file%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<jsonld-file>%s [%s--cip169%s] [%s--cip108%s] [%s--cip100%s] [%s--cip136%s] [%s--intersect-schema%s] [%s--schema%s URL] [%s--no-spell-check%s] [%s--no-link-check%s] [%s--draft%s]\n' \
        "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<jsonld-file>"        "Path to the JSON-LD metadata file"
    print_usage_option "[--cip100]"           "Compare against CIP-100 schema (default: $DEFAULT_USE_CIP_100)"
    print_usage_option "[--cip108]"           "Compare against CIP-108 Governance actions schema (default: $DEFAULT_USE_CIP_108)"
    print_usage_option "[--cip119]"           "Compare against CIP-119 DRep schema (default: $DEFAULT_USE_CIP_119)"
    print_usage_option "[--cip136]"           "Compare against CIP-136 CC vote schema (default: $DEFAULT_USE_CIP_136)"
    print_usage_option "[--cip169]"           "Compare against CIP-169 Governance metadata schema (default: $DEFAULT_USE_CIP_169, includes CIP-116)"
    print_usage_option "[--intersect-schema]" "Compare against Intersect governance action schemas (default: $DEFAULT_USE_INTERSECT)"
    print_usage_option "[--schema URL]"       "Compare against schema at URL"
    print_usage_option "[--no-spell-check]"   "Skip aspell-based spell check on body.title/abstract/motivation/rationale (default: enabled; dictionary fetched from IntersectMBO/governance-scripts main)"
    print_usage_option "[--no-link-check]"    "Skip URI reachability check on body URIs and prose markdown links (default: enabled; IPFS gateway via \$IPFS_GATEWAY_URI, falls back to https://ipfs.io)"
    print_usage_option "[--draft]"            "Treat the file as a pre-signing draft: downgrade the empty-authors check to a warning instead of an error."
    print_usage_option "-h, --help"           "Show this help message and exit"
    exit 1
}

# Initialize variables with defaults
input_file=""
use_cip_108="$DEFAULT_USE_CIP_108"
use_cip_100="$DEFAULT_USE_CIP_100"
use_cip_119="$DEFAULT_USE_CIP_119"
use_cip_136="$DEFAULT_USE_CIP_136"
use_cip_169="$DEFAULT_USE_CIP_169"
use_intersect_schema="$DEFAULT_USE_INTERSECT"
user_schema_url=""
user_schema="false"
check_links="true"
check_spelling="true"
is_draft="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cip108|--cip-108)
            use_cip_108="true"
            shift
            ;;
        --cip100|--cip-100)
            use_cip_100="true"
            shift
            ;;
        --cip119|--cip-119)
            use_cip_119="true"
            shift
            ;;
        --cip136|--cip-136)
            use_cip_136="true"
            shift
            ;;
        --cip169|--cip-169)
            use_cip_169="true"
            shift
            ;;
        --intersect-schema)
            use_intersect_schema="true"
            shift
            ;;
        --schema)
            user_schema_url="$2"
            user_schema="true"
            shift 2
            ;;
        --no-link-check)
            check_links="false"
            shift
            ;;
        --no-spell-check)
            check_spelling="false"
            shift
            ;;
        --draft)
            is_draft="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_file" ]; then
                input_file="$1"
            fi
            shift
            ;;
    esac
done

# Require at least one schema source. Without it the downstream "no schemas downloaded"
# branch would fail anyway, but that happens after length/spell/URI checks run pointlessly.
if [ "$use_cip_100" = "false" ] && [ "$use_cip_108" = "false" ] && \
   [ "$use_cip_119" = "false" ] && [ "$use_cip_136" = "false" ] && \
   [ "$use_cip_169" = "false" ] && [ "$use_intersect_schema" = "false" ] && \
   [ "$user_schema" = "false" ]; then
    print_fail "At least one schema flag is required."
    print_hint "Pass one or more of: --cip100 / --cip108 / --cip119 / --cip136 / --cip169, or --intersect-schema, or --schema <URL>"
    usage
fi

# Welcome message
print_banner "Governance Metadata Validation Script"
print_info "This script validates JSON-LD governance metadata files against CIP standards and or Intersect schemas"

# If the file ends with .jsonld, create a temporary .json copy (overwrite if exists)
if [[ "$input_file" == *.jsonld ]]; then
    if [ ! -f "$input_file" ]; then
        print_fail "File $(fmt_path "$input_file") does not exist."
        usage
        exit 1
    fi
    TMP_JSON_FILE="/tmp/metadata.json"
    cp -f "$input_file" "$TMP_JSON_FILE"
    JSON_FILE="$TMP_JSON_FILE"
else
    JSON_FILE="$input_file"
fi

# Check if the file exists
if [ ! -f "$JSON_FILE" ]; then
    print_fail "File $(fmt_path "$JSON_FILE") does not exist."
    usage
    exit 1
fi

# Check if the file is valid JSON
if ! jq empty "$JSON_FILE" >/dev/null 2>&1; then
    print_fail "$(fmt_path "$JSON_FILE") is not valid JSON."
    exit 1
fi

# Length checks for title (max 80) and abstract (max 2500) — only for fields that are present
LENGTH_CHECK_FAILED=0
LENGTH_CHECK_HEADER_SHOWN=0
check_length() {
    local field="$1"
    local max="$2"
    local text len
    text=$(jq -r ".body.$field // empty" "$JSON_FILE")
    if [ -z "$text" ]; then
        return
    fi
    if [ "$LENGTH_CHECK_HEADER_SHOWN" -eq 0 ]; then
        print_section "Checking field length limits"
        LENGTH_CHECK_HEADER_SHOWN=1
    fi
    len=${#text}
    if [ "$len" -gt "$max" ]; then
        print_fail "'$field' is $len chars, exceeds max of $max."
        LENGTH_CHECK_FAILED=1
    else
        print_pass "'$field' length: ${len} / ${max}"
    fi
}
check_length title 80
check_length abstract 2500
if [ "$LENGTH_CHECK_FAILED" -ne 0 ]; then
    exit 1
fi

# Basic spell check on key data fields (requires 'aspell' installed)
if [ "$check_spelling" = "true" ]; then
    print_section "Applying spell check"

    # Fetch the upstream Intersect dictionary so users don't need a local copy
    print_info "Fetching Cardano aspell dictionary from ${YELLOW}${CARDANO_ASPELL_DICT_URL}${NC}"
    TMP_DICT_FILE=$(mktemp /tmp/cardano-aspell-dict.XXXXXX)
    if ! curl --silent --show-error --fail --location --max-time 10 \
              -o "$TMP_DICT_FILE" "$CARDANO_ASPELL_DICT_URL"; then
        print_fail "Failed to download aspell dictionary from $CARDANO_ASPELL_DICT_URL."
        print_hint "Pass --no-spell-check to skip the spell check, or retry when online."
        exit 1
    fi
    PERSONAL_DICT_ARG="--personal=$TMP_DICT_FILE"

    # This hardcoded for CIP108
    # todo fix for other schemas
    SPELL_OUTPUT=""
    for field in title abstract motivation rationale; do
        text=$(jq -r ".body.$field // empty" "$JSON_FILE")
        if [ -n "$text" ]; then
            while IFS= read -r word; do
                [ -n "$word" ] && SPELL_OUTPUT+="  ${BLUE}'$field': ${YELLOW}$word${NC}"$'\n'
            done < <(echo "$text" | aspell list $PERSONAL_DICT_ARG | sort -u)
        fi
    done

    if [ -n "$SPELL_OUTPUT" ]; then
        print_warn "Possible misspellings:"
        printf '%b' "$SPELL_OUTPUT"
    else
        print_pass "No misspellings found."
    fi
fi

# URI reachability check — every URI (structured + markdown-embedded in prose fields)
# is HEAD-checked (with GET fallback). Duplicates are intentionally re-checked.
# Skip with --no-link-check. IPFS gateway from $IPFS_GATEWAY_URI or https://ipfs.io.
URI_CHECK_FAILED=0
if [ "$check_links" = "true" ]; then
    print_section "Checking URI reachability"
    IPFS_GATEWAY="${IPFS_GATEWAY_URI:-https://ipfs.io}"
    IPFS_GATEWAY="${IPFS_GATEWAY%/}"

    uris=()

    # 1. Structured URIs anywhere under .body with a key named uri/url (case-insensitive)
    while IFS= read -r u; do
        [ -n "$u" ] && uris+=("$u")
    done < <(jq -r '
        .body
        | [.. | objects | to_entries[]
            | select((.key | ascii_downcase) == "uri" or (.key | ascii_downcase) == "url")
            | .value | select(type == "string")]
        | .[]
    ' "$JSON_FILE")

    # 2. Markdown-embedded / bare URLs in prose fields
    for field in title abstract motivation rationale; do
        text=$(jq -r ".body.$field // empty" "$JSON_FILE")
        if [ -n "$text" ]; then
            while IFS= read -r u; do
                [ -n "$u" ] && uris+=("$u")
            done < <(printf '%s' "$text" | perl -0777 -ne '
                while (/\[[^\]]*\]\((https?:\/\/[^)\s]+|ipfs:\/\/[^)\s]+)\)/g) { print "$1\n" }
                while (/<(https?:\/\/[^>\s]+|ipfs:\/\/[^>\s]+)>/g) { print "$1\n" }
                while (/(?<![\w\/:])(https?:\/\/[^\s)\]<>"'"'"'\\]+)/g) { print "$1\n" }
                while (/(?<![\w\/:])(ipfs:\/\/[A-Za-z0-9\/._\-]+)/g) { print "$1\n" }
            ')
        fi
    done

    total_count=${#uris[@]}
    failed_count=0

    if [ "$total_count" -eq 0 ]; then
        print_warn "No URIs found to check."
    else
        for raw_uri in "${uris[@]}"; do
            # Trim trailing punctuation that regex may have grabbed
            uri="$raw_uri"
            while :; do
                case "$uri" in
                    *.|*,|*\;|*\!|*\?|*\)|*\]|*\>|*\"|*\'|*\`) uri="${uri%?}" ;;
                    *) break ;;
                esac
            done

            # Skip non-HTTP(S)/IPFS and fragment-only
            case "$uri" in
                mailto:*|tel:*) continue ;;
                \#*) continue ;;
            esac
            if [[ ! "$uri" =~ ^(https?|ipfs):// ]]; then
                continue
            fi

            # Normalize ipfs:// to configured gateway
            check_url="$uri"
            if [[ "$uri" == ipfs://* ]]; then
                check_url="$IPFS_GATEWAY/ipfs/${uri#ipfs://}"
            fi

            http_code=$(curl --silent --location \
                             --max-time 10 --retry 1 --retry-delay 1 \
                             --head -o /dev/null -w '%{http_code}' "$check_url" 2>/dev/null || true)
            [ -z "$http_code" ] && http_code="000"

            if [ "$http_code" = "405" ] || [ "$http_code" = "000" ]; then
                http_code=$(curl --silent --location \
                                 --max-time 10 --retry 1 --retry-delay 1 \
                                 --request GET --range 0-0 \
                                 -o /dev/null -w '%{http_code}' "$check_url" 2>/dev/null || true)
                [ -z "$http_code" ] && http_code="000"
            fi

            if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
                if [ "$uri" != "$check_url" ]; then
                    print_pass "$uri ($http_code via $check_url)"
                else
                    print_pass "$uri ($http_code)"
                fi
            else
                failed_count=$((failed_count + 1))
                if [ "$uri" != "$check_url" ]; then
                    print_fail "$uri ($http_code via $check_url)"
                else
                    print_fail "$uri ($http_code)"
                fi
            fi
        done

        if [ "$failed_count" -gt 0 ]; then
            print_fail "$failed_count of $total_count URIs unreachable."
            print_hint "Re-run with --no-link-check to skip this check (e.g. if offline)."
            URI_CHECK_FAILED=1
        else
            print_pass "All $total_count URIs reachable."
        fi
    fi
fi

print_section "Applying schema check(s)"

# Create a temporary directory for schema(s)
mkdir -p "$TMP_SCHEMAS_DIR"

# Download the schemas as needed
if [ "$use_cip_100" = "true" ]; then
    print_info "Downloading CIP-100 Governance Metadata schema..."
    TEMP_CIP_100_SCHEMA="$TMP_SCHEMAS_DIR/cip-100-schema.json"
    curl -sSfSL "$CIP_100_SCHEMA" -o "$TEMP_CIP_100_SCHEMA"
fi

if [ "$use_cip_108" = "true" ]; then
    print_info "Downloading CIP-108 Governance Actions schema..."
    TEMP_CIP_108_SCHEMA="$TMP_SCHEMAS_DIR/cip-108-schema.json"
    curl -sSfSL "$CIP_108_SCHEMA" -o "$TEMP_CIP_108_SCHEMA"
fi

if [ "$use_cip_119" = "true" ]; then
    print_info "Downloading CIP-119 DRep schema..."
    TEMP_CIP_119_SCHEMA="$TMP_SCHEMAS_DIR/cip-119-schema.json"
    curl -sSfSL "$CIP_119_SCHEMA" -o "$TEMP_CIP_119_SCHEMA"
fi

if [ "$use_cip_136" = "true" ]; then
    print_info "Downloading CIP-136 Constitutional Committee Vote schema..."
    TEMP_CIP_136_SCHEMA="$TMP_SCHEMAS_DIR/cip-136-schema.json"
    curl -sSfSL "$CIP_136_SCHEMA" -o "$TEMP_CIP_136_SCHEMA"
fi

CARDANO_CONWAY_REF=""
if [ "$use_cip_169" = "true" ]; then
    print_info "Downloading CIP-169 Governance Metadata Extension schema..."
    TEMP_CIP_169_SCHEMA="$TMP_SCHEMAS_DIR/cip-169-schema.json"
    curl -sSfSL "$CIP_169_SCHEMA" -o "$TEMP_CIP_169_SCHEMA"

    echo -e "${WHITE}Downloading CIP-116 cardano-conway types (referenced by CIP-169)...${NC}"
    # Filename intentionally avoids the "*-schema.json" suffix so the glob below
    # does not pick it up as a top-level schema to validate against.
    CARDANO_CONWAY_REF="$TMP_SCHEMAS_DIR/cardano-conway.json"
    curl -sSfSL "$CIP_116_CONWAY_SCHEMA" -o "$CARDANO_CONWAY_REF"
fi

# Determine which Intersect schema to use based on the CIP-116 gov_action.tag discriminator.
if [ "$use_intersect_schema" = "true" ]; then
    gov_action_tag=$(jq -r '.body.onChain.gov_action.tag // "null"' "$JSON_FILE")

    case "$gov_action_tag" in
        info_action)
            print_info "Downloading Intersect ${YELLOW}info${NC} schema..."
            INTERSECT_SCHEMA_URL="$INTERSECT_INFO_SCHEMA"
            ;;
        treasury_withdrawals_action)
            print_info "Downloading Intersect ${YELLOW}treasuryWithdrawals${NC} schema..."
            INTERSECT_SCHEMA_URL="$INTERSECT_TREASURY_SCHEMA"
            ;;
        parameter_change_action)
            print_info "Downloading Intersect ${YELLOW}parameterChanges${NC} schema..."
            INTERSECT_SCHEMA_URL="$INTERSECT_PPU_SCHEMA"
            ;;
        *)
            print_fail "Unknown body.onChain.gov_action.tag '$gov_action_tag' in $(fmt_path "$JSON_FILE")."
            print_hint "Expected one of: info_action, treasury_withdrawals_action, parameter_change_action."
            exit 1
            ;;
    esac
    TEMP_INT_SCHEMA="$TMP_SCHEMAS_DIR/intersect-schema.json"
    curl -sSfSL "$INTERSECT_SCHEMA_URL" -o "$TEMP_INT_SCHEMA"
        # Under --draft the authors array may legitimately be empty (not yet signed).
    # The Intersect schema enforces minItems:1 on authors at the JSON Schema level,
    # which AJV would fail on its own, bypassing the --draft logic entirely.
    # Remove that constraint so AJV defers the empty-authors check to the structural
    # integrity block below, where --draft correctly downgrades it to a warning.
    if [ "$is_draft" = "true" ]; then
        jq 'del(.definitions.authors.minItems)' "$TEMP_INT_SCHEMA" > "${TEMP_INT_SCHEMA}.tmp" \
            && mv "${TEMP_INT_SCHEMA}.tmp" "$TEMP_INT_SCHEMA"
    fi
fi

if [ "$user_schema" = "true" ]; then
    print_info "Downloading schema from ${YELLOW}${user_schema_url}${NC}"
    TEMP_USER_SCHEMA="$TMP_SCHEMAS_DIR/user-schema.json"
    curl -sSfSL "$user_schema_url" -o "$TEMP_USER_SCHEMA"
fi

# Validate the JSON file against the schemas
schemas=("$TMP_SCHEMAS_DIR"/*-schema.json)
# In the case where flags are used to not have any schemas download, exit with 1
if [ -z "$(ls -A $TMP_SCHEMAS_DIR)" ]; then
    print_fail "No schemas were downloaded."
    exit 1
fi

VALIDATION_FAILED=0

for schema in "${schemas[@]}"; do
    print_section "Validating against schema: $schema"
    if [ -f "$schema" ]; then
        ajv_args=(validate -s "$schema" -d "$JSON_FILE" --all-errors --strict=false)
        # CIP-169 references CIP-116 cardano-conway types via $ref; supply them.
        if [[ "$schema" == *cip-169-schema.json ]] && [ -n "$CARDANO_CONWAY_REF" ]; then
            ajv_args=(validate --spec=draft2020 -s "$schema" -r "$CARDANO_CONWAY_REF" -d "$JSON_FILE" --all-errors --strict=false)
        fi
        # Drop Ajv's "unknown format X ignored" noise for custom string formats
        # CIP116 defines many custom types that AJV loves to warn us about
        set +e
        ajv "${ajv_args[@]}" 2>&1 \
            | grep -v 'unknown format ".*" ignored in schema at path'
        ajv_status="${PIPESTATUS[0]}"
        set -e
        if [ "$ajv_status" -ne 0 ]; then
            VALIDATION_FAILED=1
        fi
    fi
done

# Structural integrity check beyond what ajv enforces.
# Skipped entirely when only --schema URL is in use
STRUCT_CHECK_FAILED=0
if [ "$use_cip_100" = "true" ] || [ "$use_cip_108" = "true" ] || \
   [ "$use_cip_119" = "true" ] || [ "$use_cip_136" = "true" ] || \
   [ "$use_cip_169" = "true" ] || [ "$use_intersect_schema" = "true" ]; then
    print_section "Applying structural integrity checks"

    # Non-empty authors array. Downgraded to a warning under --draft so the
    authors_count=$(jq -r '(.authors // []) | length' "$JSON_FILE")
    if [ "$authors_count" -eq 0 ]; then
        if [ "$is_draft" = "true" ]; then
            print_warn "authors: array is empty. Acceptable under --draft; re-run without --draft after signing."
        else
            print_fail "authors: array is empty. Governance metadata must declare at least one author for the document to be attestable."
            print_hint "Add a witness or pass --draft for pre-signing validation."
            STRUCT_CHECK_FAILED=1
        fi
    else
        print_pass "authors: $authors_count entr$([ "$authors_count" -eq 1 ] && echo y || echo ies)"
    fi
fi

# Final result
if [ "$VALIDATION_FAILED" -ne 0 ] || [ "$URI_CHECK_FAILED" -ne 0 ] || [ "$STRUCT_CHECK_FAILED" -ne 0 ]; then
    print_fail "One or more validation errors were found."
    exit 1
else
    print_pass "No validation errors found."
    exit 0
fi
