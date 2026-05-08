#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/messages.sh
source "$SCRIPT_DIR/lib/messages.sh"

##################################################
# supported versions for scripts v1.0.0
# Exact known-good versions. If the installed version differs in any
# component, preflight WARNs (never fails) — these are advisory, not hard
# requirements. Leave blank to skip the version check for a tool.

cardano_cli_version="cardano-cli 10.8.0"
cardano_signer_version="cardano-signer 1.27.0"
jq_version="1.7.1"
curl_version="8.7.1"
ipfs_version="0.38.2"
pandoc_version="3.7.0.1"
ajv_version=""
b2sum_version=""
aspell_version=""
perl_version=""
awk_version=""
sed_version=""
node_version=""
jsonld_pkg_version=""
qpdf_version=""
exiftool_version=""
bc_version=""
base64_version=""


##################################################

# Checks that the environment is set up to run the other scripts in this
# directory: required/optional binaries on PATH, .env file, and Cardano node
# env vars. Prints a grouped report; exits 1 if any required check FAILs.

set -u

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

record() {
    case "$1" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    esac
}

# Inline tag emitter — preflight prints tag + name + value on a single line
# (column-aligned table), so it can't use lib's print_pass/warn/fail which
# emit complete lines. Colors come from the lib.
tag() {
    case "$1" in
        PASS) printf '  %s[PASS]%s ' "$GREEN" "$NC" ;;
        WARN) printf '  %s[WARN]%s ' "$YELLOW" "$NC" ;;
        FAIL) printf '  %s[FAIL]%s ' "$RED" "$NC" ;;
    esac
}

# Extract the first dotted version number (e.g. "10.8.0.0") from a string.
extract_version_number() {
    printf '%s\n' "$1" | grep -oE '[0-9]+(\.[0-9]+)+' | head -1
}

# Compare two dotted version numbers. Echoes: lt | eq | gt
# Missing components are treated as 0, so "1.6" == "1.6.0".
compare_versions() {
    local a="$1" b="$2"
    local IFS=.
    # shellcheck disable=SC2206
    local av=($a) bv=($b)
    local len=${#av[@]}
    if [ "${#bv[@]}" -gt "$len" ]; then len=${#bv[@]}; fi
    local i x y
    for ((i = 0; i < len; i++)); do
        x=${av[i]:-0}
        y=${bv[i]:-0}
        if [ "$x" -lt "$y" ] 2>/dev/null; then echo lt; return; fi
        if [ "$x" -gt "$y" ] 2>/dev/null; then echo gt; return; fi
    done
    echo eq
}

# Run a tool with its version flag; redirect stdin from /dev/null so tools
# like BSD awk that ignore unknown flags and wait for input don't hang.
get_version() {
    local bin="$1"
    local flag="$2"
    local out rc
    # shellcheck disable=SC2086
    out=$("$bin" $flag </dev/null 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "installed (version unknown)"
        return
    fi
    local line
    line=$(printf '%s\n' "$out" | awk 'NF {print; exit}' | tr -d '\r')
    if [ -z "$line" ]; then
        echo "installed"
    else
        echo "$line"
    fi
}

check_binary() {
    local bin="$1"
    local requirement="$2"
    local version_flag="$3"
    local hint="$4"
    local supported="${5:-}"

    if command -v "$bin" >/dev/null 2>&1; then
        local ver installed_num supported_num cmp
        ver=$(get_version "$bin" "$version_flag")

        if [ -n "$supported" ]; then
            installed_num=$(extract_version_number "$ver")
            supported_num=$(extract_version_number "$supported")
            if [ -n "$installed_num" ] && [ -n "$supported_num" ]; then
                cmp=$(compare_versions "$installed_num" "$supported_num")
                if [ "$cmp" != "eq" ]; then
                    tag WARN
                    printf "%-18s %s (supported: %s)\n" "$bin" "$ver" "$supported_num"
                    record WARN
                    return
                fi
            fi
        fi

        tag PASS
        printf "%-18s %s\n" "$bin" "$ver"
        record PASS
        return
    fi

    if [ "$requirement" = "required" ]; then
        tag FAIL
        printf "%-18s not found — %s\n" "$bin" "$hint"
        record FAIL
    else
        tag WARN
        printf "%-18s not found — %s\n" "$bin" "$hint"
        record WARN
    fi
}

# Check that a Node package is resolvable. Resolution chain matches the one
# in metadata-validate.sh's JSON-LD safe-mode check: try the current
# NODE_PATH / CWD first, then fall back to whatever `npm root -g` reports.
# Reports the package's version (read from its package.json) on success.
check_npm_package() {
    local pkg="$1"
    local requirement="$2"
    local hint="$3"
    local supported="${4:-}"

    if ! command -v node >/dev/null 2>&1; then
        if [ "$requirement" = "required" ]; then
            tag FAIL
            printf "%-18s needs node first; then %s\n" "$pkg" "$hint"
            record FAIL
        else
            tag WARN
            printf "%-18s needs node first; then %s\n" "$pkg" "$hint"
            record WARN
        fi
        return
    fi

    local pkg_path
    pkg_path=$(node -e "try { console.log(require.resolve('$pkg/package.json')); } catch (_) {}" 2>/dev/null)
    if [ -z "$pkg_path" ] && command -v npm >/dev/null 2>&1; then
        local global_root
        global_root=$(npm root -g 2>/dev/null || true)
        if [ -n "$global_root" ]; then
            pkg_path=$(NODE_PATH="${NODE_PATH:-}${NODE_PATH:+:}$global_root" \
                node -e "try { console.log(require.resolve('$pkg/package.json')); } catch (_) {}" 2>/dev/null)
        fi
    fi

    if [ -n "$pkg_path" ] && [ -f "$pkg_path" ]; then
        local ver installed_num supported_num cmp
        ver=$(jq -r '.version // empty' "$pkg_path" 2>/dev/null || true)
        if [ -n "$supported" ] && [ -n "$ver" ]; then
            installed_num=$(extract_version_number "$ver")
            supported_num=$(extract_version_number "$supported")
            if [ -n "$installed_num" ] && [ -n "$supported_num" ]; then
                cmp=$(compare_versions "$installed_num" "$supported_num")
                if [ "$cmp" != "eq" ]; then
                    tag WARN
                    printf "%-18s %s (supported: %s)\n" "$pkg" "$ver" "$supported_num"
                    record WARN
                    return
                fi
            fi
        fi
        tag PASS
        printf "%-18s %s\n" "$pkg" "${ver:-installed}"
        record PASS
        return
    fi

    if [ "$requirement" = "required" ]; then
        tag FAIL
        printf "%-18s not found — %s\n" "$pkg" "$hint"
        record FAIL
    else
        tag WARN
        printf "%-18s not found — %s\n" "$pkg" "$hint"
        record WARN
    fi
}

printf '%s%s=== Governance scripts preflight ===%s\n\n' "$BOLD" "$CYAN" "$NC"

printf '%s%sRequired binaries%s\n' "$BOLD" "$CYAN" "$NC"
check_binary cardano-cli    required "--version" "install from https://github.com/IntersectMBO/cardano-node/releases" "$cardano_cli_version"
check_binary cardano-signer required "--version" "install from https://github.com/gitmachtl/cardano-signer/releases" "$cardano_signer_version"
check_binary jq             required "--version" "brew install jq  |  apt install jq"                               "$jq_version"
check_binary curl           required "--version" "brew install curl  |  apt install curl"                           "$curl_version"
check_binary ipfs           required "version"   "install from https://docs.ipfs.tech/install/command-line/"        "$ipfs_version"
check_binary pandoc         required "--version" "install from https://pandoc.org/installing.html"                  "$pandoc_version"
check_binary ajv            required "help"      "npm install -g ajv-cli"                                           "$ajv_version"
check_binary node           required "--version" "install Node.js >= 18 (https://nodejs.org/) — needed for the metadata-validate.sh JSON-LD safe-mode check" "$node_version"
check_npm_package jsonld    required             "npm install -g jsonld — needed for the metadata-validate.sh JSON-LD safe-mode check"                       "$jsonld_pkg_version"
check_binary b2sum          required "--version" "brew install coreutils (macOS)  |  apt install coreutils"         "$b2sum_version"
check_binary aspell         required "--version" "brew install aspell  |  apt install aspell"                       "$aspell_version"
check_binary perl           required "--version" "preinstalled on macOS/Linux; otherwise brew/apt install perl"     "$perl_version"
check_binary awk            required "--version" "preinstalled on macOS/Linux"                                      "$awk_version"
check_binary sed            required "--version" "preinstalled on macOS/Linux"                                      "$sed_version"
echo

printf '%s%sOptional binaries%s\n' "$BOLD" "$CYAN" "$NC"
check_binary qpdf     optional "--version" "needed only by pdf-remove-metadata.sh"       "$qpdf_version"
check_binary exiftool optional "-ver"      "needed only by pdf-remove-metadata.sh"       "$exiftool_version"
check_binary bc       optional "--version" "needed only by action-create-tw.sh"          "$bc_version"
check_binary base64   optional "--version" "needed only by NMKR pinning in ipfs-pin.sh"  "$base64_version"
echo

printf '%s%sEnvironment%s\n' "$BOLD" "$CYAN" "$NC"

ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    tag PASS
    printf "%-32s found at %s\n" ".env file" "$ENV_FILE"
    record PASS
else
    tag WARN
    printf "%-32s missing — copy .env.example to .env or export vars in your shell\n" ".env file"
    record WARN
fi
# Env-var checks below read the current shell only — they do NOT source .env.
# Run `source ./scripts/.env` yourself before preflight to verify the values
# that action-create-* / ipfs-pin scripts will actually see.

sock="${CARDANO_NODE_SOCKET_PATH:-}"
if [ -z "$sock" ]; then
    tag WARN
    printf "%-32s not set — required by action-create-* scripts\n" "CARDANO_NODE_SOCKET_PATH"
    record WARN
elif [ ! -e "$sock" ]; then
    tag FAIL
    printf "%-32s path does not exist: %s\n" "CARDANO_NODE_SOCKET_PATH" "$sock"
    record FAIL
elif [ ! -S "$sock" ]; then
    tag WARN
    printf "%-32s %s (exists but not a socket)\n" "CARDANO_NODE_SOCKET_PATH" "$sock"
    record WARN
else
    tag PASS
    printf "%-32s %s (valid socket)\n" "CARDANO_NODE_SOCKET_PATH" "$sock"
    record PASS
fi

netid="${CARDANO_NODE_NETWORK_ID:-}"
if [ -z "$netid" ]; then
    tag WARN
    printf "%-32s not set — required by action-create-* scripts\n" "CARDANO_NODE_NETWORK_ID"
    record WARN
else
    tag PASS
    printf "%-32s %s\n" "CARDANO_NODE_NETWORK_ID" "$netid"
    record PASS
fi

echo
printf '%s%sIPFS pinning (ipfs-pin.sh)%s\n' "$BOLD" "$CYAN" "$NC"
printf '  %sLocal IPFS pinning works without any keys; each remote service below is optional.%s\n' "$CYAN" "$NC"

check_pin_var() {
    local name="$1"
    local service="$2"
    local value="${!name:-}"
    if [ -z "$value" ]; then
        tag WARN
        printf "%-32s not set — %s pinning will be skipped\n" "$name" "$service"
        record WARN
    else
        tag PASS
        printf "%-32s set (%s pinning available)\n" "$name" "$service"
        record PASS
    fi
}

check_pin_var PINATA_API_KEY     "Pinata"
check_pin_var BLOCKFROST_API_KEY "Blockfrost"
check_pin_var NMKR_API_KEY       "NMKR"
check_pin_var NMKR_USER_ID       "NMKR"

echo
printf '%sSummary:%s %s%d pass%s, %s%d warn%s, %s%d fail%s\n' \
    "$BOLD" "$NC" \
    "$GREEN" "$PASS_COUNT" "$NC" \
    "$YELLOW" "$WARN_COUNT" "$NC" \
    "$RED" "$FAIL_COUNT" "$NC"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
