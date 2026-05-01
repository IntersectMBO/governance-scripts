# `governance-scripts` user-facing message style

This is the contributor reference for user-facing output across the shell
scripts in this repo. The conventions below are enforced by the helpers in
[`scripts/lib/messages.sh`](../scripts/lib/messages.sh) — call those helpers
instead of writing raw `echo -e "${COLOR}..."` lines.

The migration plan that introduced this is in
[`messaging-standardization-plan.md`](messaging-standardization-plan.md).

## Status tags

Three tags. Use them everywhere — both for individual checks (e.g. one URI
in a list) and for terminal outcomes (e.g. "action file created"):

| Tag      | Helper        | Meaning                                                |
|----------|---------------|--------------------------------------------------------|
| `[PASS]` | `print_pass`  | A check passed, or a step completed successfully.      |
| `[WARN]` | `print_warn`  | Something is unusual but the script can keep going.    |
| `[FAIL]` | `print_fail`  | A check failed or an operation aborted. Always stderr. |

Don't invent new tags (`[OK]`, `[ERROR]`, `[INFO]`, etc.).

## Confirmation prompts

Always `(Y/n)` with **Enter accepts**. Use the `confirm` helper:

```bash
if ! confirm "Do you want to proceed with this deposit return address?"; then
    print_fail "Cancelled by user"
    exit 1
fi
```

The cancellation message is always `[FAIL] Cancelled by user` and the script
exits 1. Cancellation looks like a failure to CI by design.

## File paths

Always single-quoted, always colored. Use `fmt_path`:

```bash
print_pass "Action file created at $(fmt_path "$action_file")"
# →   [PASS] Action file created at 'metadata.jsonld.action'
```

This makes paths with spaces unambiguous and keeps a consistent visual.

## Streams

| What                                    | Goes to |
|-----------------------------------------|---------|
| `print_pass`, `print_info`, banners, sections, summary, `print_kv`, `print_next` | stdout  |
| `print_fail`, `print_warn`, `print_hint` | stderr  |

If you call a helper that writes to stdout from inside a function whose
stdout is being captured (i.e. inside `$( ... )`), redirect that call to
`>&2` explicitly. `treasury_collect_inputs` in `metadata-create.sh` is the
canonical example.

## Color and TTY

Never emit raw ANSI escapes. Always go through the lib. The lib auto-disables
color when:

- both stdout and stderr are non-TTY (piped/redirected/CI), or
- `NO_COLOR` is set in the environment ([no-color.org](https://no-color.org)).

This means CI logs and `script.sh > out.log` files come out clean by default.

## Hints

When a `[FAIL]` has an actionable next step, follow it with `print_hint`:

```bash
print_fail "Failed to download aspell dictionary from $url"
print_hint "Pass --no-spell-check to skip the spell check, or retry when online."
```

Output:

```
  [FAIL] Failed to download aspell dictionary from <url>
         Hint: Pass --no-spell-check to skip the spell check, or retry when online.
```

`print_hint` writes to stderr and indents under the `[FAIL]`/`[WARN]` message
column.

## Sections, banners, and summary

- **Banner** at the top of the script (one yellow line): `print_banner`.
- **Section header** for each phase: `print_section "..."` produces
  `=== Title ===` in cyan with a leading blank line.
- **Summary** at the end of long scripts:

  ```bash
  print_section "Summary"
  print_pass "Info governance action created"
  print_kv "Input"  "$(fmt_path "$input_file")"
  print_kv "Action" "$(fmt_path "$action_file")"
  print_next "Include the action file in a transaction:" \
             "  cardano-cli latest transaction build \\" \
             "    --proposal-file '$action_file'"
  ```

  `print_next` takes one argument per line; the first is usually a short
  description, the rest are the literal command(s) to run.

## Help / usage text

Use `print_usage_option` instead of hand-rolled `printf "%-*s"` blocks:

```bash
usage() {
    printf '%s%sCreate an Info action from a given JSON-LD metadata file%s\n\n' "$UNDERLINE" "$BOLD" "$NC"
    printf 'Syntax:%s %s %s<jsonld-file>%s [%s--deposit-return-addr%s <stake address>]\n' "$BOLD" "$0" "$GREEN" "$NC" "$GREEN" "$NC"
    print_usage_option "<jsonld-file>"                              "Path to the JSON-LD metadata file"
    print_usage_option "[--deposit-return-addr <stake address>]"    "Optional check that metadata deposit return address matches provided one (Bech32)"
    print_usage_option "-h, --help"                                 "Show this help message and exit"
    exit 1
}
```

The helper aligns to a 42-char flag column. If a flag is longer than that,
just let it overflow — wrapping isn't worth the complexity.

## Before / after

```bash
# BEFORE — raw echo, color block in every script
RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'; NC='\033[0m'

if [ ! -f "$input_file" ]; then
    echo -e "${RED}Error: Input file not found: $input_file${NC}" >&2
    exit 1
fi

if [[ "$input_file" != *.jsonld ]]; then
    echo -e "${RED}Error: Input file '${YELLOW}$input_file${RED}' must be a JSON-LD metadata file with a ${YELLOW}.jsonld${RED} extension.${NC}" >&2
    echo -e "${YELLOW}This script expects a CIP-108 metadata document...${NC}" >&2
    exit 1
fi

read -p "Proceed? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo -e "${RED}Cancelled by user, exiting.${NC}"
    exit 1
fi

echo -e "${GREEN}Action file created at \"$input_file.action\"${NC}"
```

```bash
# AFTER — uses lib, conventions enforced
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/messages.sh"

if [ ! -f "$input_file" ]; then
    print_fail "Input file not found: $(fmt_path "$input_file")"
    exit 1
fi

if [[ "$input_file" != *.jsonld ]]; then
    print_fail "Input file $(fmt_path "$input_file") must be a JSON-LD metadata file with a .jsonld extension."
    print_hint "This script expects a CIP-108 metadata document..."
    exit 1
fi

if ! confirm "Proceed?"; then
    print_fail "Cancelled by user"
    exit 1
fi

print_pass "Action file created at $(fmt_path "$action_file")"
```

## Migration status

All shell scripts under `scripts/` have been migrated to use `lib/messages.sh`.
`preflight.sh` keeps its own inline `tag()` emitter because it prints
tag + name + value on a single column-aligned line; it sources the lib for
its color variables so NO_COLOR / non-TTY behavior is consistent.
