#!/bin/bash
# Fetch each pinned upstream CIP example, re-canonize it, and confirm the
# body hash still matches the golden recorded in sources.tsv.
#
# This is a canonicalization-drift detector: if cardano-signer is upgraded,
# if the perl control-char escape behaves differently, or if the pinned
# upstream file somehow returns different bytes, the hash will drift and CI
# will fail. ALL of those are worth investigating.
#
# Drives the CI workflow at .github/workflows/ci.yml; can also be run locally
# (requires cardano-signer, jq, curl, perl on PATH).

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SOURCES="$SCRIPT_DIR/sources.tsv"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cip-fixtures.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

if [ -t 1 ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'
else
    RED=""; GREEN=""; CYAN=""; NC=""
fi

fail_count=0
total_count=0

while IFS=$'\t' read -r id safemode url golden_hash; do
    case "$id" in ""|\#*) continue ;; esac
    total_count=$((total_count + 1))

    echo
    echo "${CYAN}=== $id ===${NC}"
    echo "  safemode: $safemode"
    echo "  source:   $url"

    fixture="$WORK_DIR/$id.jsonld"
    if ! curl --silent --show-error --fail --location --max-time 30 \
              -o "$fixture" "$url"; then
        echo "${RED}[FAIL] could not download fixture${NC}"
        fail_count=$((fail_count + 1))
        continue
    fi

    # cardano-signer is invoked directly (not via metadata-canonize.sh) because
    # that wrapper hardcodes safe mode, and CIP-119 + some CIP-136 docs need
    # --disable-safemode to canonize at all under cardano-signer 1.27.0.
    safemode_arg=""
    [ "$safemode" = "no" ] && safemode_arg="--disable-safemode"
    actual_hash=$(cardano-signer canonize \
                    --data-file "$fixture" --cip100 $safemode_arg \
                    --json-extended --out-file /dev/stdout 2>/dev/null \
                  | perl -pe 's/([\x00-\x1f])/sprintf("\\u%04x",ord($1))/ge' \
                  | jq -r '.canonizedHash')

    if [ "$actual_hash" = "$golden_hash" ]; then
        echo "${GREEN}[OK]${NC}   $actual_hash"
    else
        echo "${RED}[FAIL] canonize hash drift${NC}"
        echo "  expected (golden): $golden_hash"
        echo "  actual:            $actual_hash"
        echo "  Possible causes: cardano-signer version drift, perl-escape behavior drift,"
        echo "  the pinned upstream file changed under the same SHA (should not be possible),"
        echo "  or a wrapper-script change. Investigate before bumping the golden."
        fail_count=$((fail_count + 1))
    fi
done < "$SOURCES"

echo
if [ "$fail_count" -ne 0 ]; then
    echo "${RED}$fail_count of $total_count fixtures failed.${NC}"
    exit 1
fi
echo "${GREEN}All $total_count fixtures canonize to their golden hash.${NC}"
