#!/usr/bin/env bash
# shellcheck shell=bash
#
# Usage:
#     SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#     source "$SCRIPT_DIR/lib/messages.sh"
#
# Output rules:
#   - Errors and warnings go to stderr; everything else to stdout.
#   - Color is auto-disabled when both stdout and stderr are non-TTY, and
#     when NO_COLOR is set (https://no-color.org).

if [ "${__GOV_SCRIPTS_MESSAGES_LOADED:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi
__GOV_SCRIPTS_MESSAGES_LOADED=1

if [ -z "${NO_COLOR:-}" ] && { [ -t 1 ] || [ -t 2 ]; }; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    BRIGHTWHITE=$'\033[0;37;1m'
    GRAY=$'\033[0;90m'
    BOLD=$'\033[1m'
    UNDERLINE=$'\033[4m'
    NC=$'\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BRIGHTWHITE=''
    GRAY=''
    BOLD=''
    UNDERLINE=''
    NC=''
fi

# Top-of-script title line.
print_banner() {
    printf '\n%s%s%s\n' "$YELLOW" "$1" "$NC"
}

# Section header: blank line then "=== Title ===" in cyan.
print_section() {
    printf '\n%s=== %s ===%s\n' "$CYAN" "$1" "$NC"
}

# Plain informational line, no tag.
print_info() {
    printf '%s\n' "$1"
}

print_pass() {
    printf '  %s[PASS]%s %s\n' "$GREEN" "$NC" "$1"
}

print_warn() {
    printf '  %s[WARN]%s %s\n' "$YELLOW" "$NC" "$1" >&2
}

print_fail() {
    printf '  %s[FAIL]%s %s\n' "$RED" "$NC" "$1" >&2
}

# Follow-up hint, indented to align under the message text of a [FAIL]/[WARN].
print_hint() {
    printf '         %sHint:%s %s\n' "$GRAY" "$NC" "$1" >&2
}

# Aligned key/value row inside a summary block. Indented to align with [PASS]/etc message column.
print_kv() {
    printf '         %-12s %s\n' "$1:" "$2"
}

# "Next step:" footer for end-of-script summaries. Each argument is one
# command/instruction line, indented to align under the [PASS] message column.
print_next() {
    printf '%sNext step:%s\n' "$BOLD" "$NC"
    local line
    for line in "$@"; do
        printf '         %s\n' "$line"
    done
}

# Single-quoted, colored path; suitable for inlining in other messages.
fmt_path() {
    printf "'%s%s%s'" "$YELLOW" "$1" "$NC"
}

# Single help row, replacing ad-hoc col=50 printf blocks.
print_usage_option() {
    printf '        %s%-42s%s %s%s%s\n' "$GREEN" "$1" "$NC" "$GRAY" "$2" "$NC"
}

# (Y/n) confirmation prompt. Enter accepts. Returns 0 on yes, 1 on no.
# Prefers /dev/tty so the prompt works inside command substitution; falls
# back to stdin when no terminal is attached (e.g. piped input).
confirm() {
    local prompt="$1" ans=""
    if { exec 9</dev/tty; } 2>/dev/null; then
        printf '%s (Y/n): ' "$prompt" >/dev/tty
        IFS= read -r ans <&9 || ans=""
        exec 9<&-
    else
        printf '%s (Y/n): ' "$prompt" >&2
        IFS= read -r ans || ans=""
    fi
    [[ -z "$ans" || "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}
