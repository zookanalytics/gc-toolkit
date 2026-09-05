#!/usr/bin/env bash
# mktemp-untemplated.sh — hardened learned rule: every `mktemp` names its
# template, so a temp path left on disk is attributable to the code that made
# it. `mktemp` and `mktemp -d` with no operand fall back to the libc default
# `/tmp/tmp.XXXXXXXXXX`, a name that says nothing about its producer: an
# orphan under it cannot be traced, and every producer's orphans pile into one
# undifferentiated family that no operator can attribute or safely reclaim.
# A template costs one argument and makes the leak self-identifying.
#
# Scanned: *.sh; fenced code in *.toml (formula descriptions are recipes that
# agents and extraction tests run verbatim); `# >>> name`…`# <<< name`
# marker-fenced snippets in *.md. Prose outside a fence quotes the shape
# rather than running it. Whole-line comments are skipped for the same reason.
# No exception list: a template is always available, and a path built from a
# variable counts.
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

FIX='fix: mktemp -d "${TMPDIR:-/tmp}/gctk-<producer>.XXXXXX" (learned rule: mktemp-untemplated)'

found=0

is_comment() { # whole-line comments only; `cmd  # note` is code
    case "$(printf '%s' "$1" | tr -d '[:space:]')" in '#'*) return 0 ;; esac
    return 1
}

# A call is templated when a producer-named operand survives the option words,
# so each option's arity decides what an operand even is. `-p DIR`,
# `--tmpdir[=DIR]` and `--suffix=SUFF` choose a directory or a suffix and never
# a basename: with no separate TEMPLATE beside them the name is still the libc
# `tmp.XXXXXXXXXX`. `-t` takes no argument of its own, so the word after it is
# the template. `$1` is the text AFTER `mktemp`, already isolated to one command.
is_bare_args() {
    local rest word short="" after="" skip=0
    # Stop at the end of the command: a closing paren, pipe, redirect,
    # separator or logical operator ends the argument list.
    rest="$(printf '%s' "$1" | sed -E 's/[)|;&<>].*//')"
    for word in $rest; do
        if [ "$skip" = 1 ]; then skip=0; continue; fi   # an option's own argument
        case "$word" in
            --suffix) skip=1 ;;   # required argument, taken from the next word
            --*) ;;               # --suffix=SUFF, --tmpdir[=DIR], and the flags
            -*)                   # a short cluster; `p` takes DIR, attached or next
                short="${word#-}"
                if [ "${short%%p*}" != "$short" ]; then
                    after="${short#*p}"
                    [ -n "$after" ] || skip=1
                fi
                ;;
            *) return 1 ;;        # an operand survives: the producer named it
        esac
    done
    return 0
}

# Where a command may start: the head of a line, a command substitution, a
# separator, a subshell/group/negation/case-arm boundary, and the whitespace
# after a compound keyword. Splitting the line at each turns every command into
# its own segment, so each `mktemp` is judged against only its own argument list
# — a templated call no longer vouches for a bare one beside it, and the greedy
# cut that read only the last call on a line is gone.
split_commands() {
    printf '%s' "$1" | sed -E '
        s/\$\(/\n/g
        s/`/\n/g
        s/[;&|]/\n/g
        s/[(){}!]/\n/g
        s/(^|[[:space:]])(if|elif|then|else|while|until|do)([[:space:]]+)/\1\n/g'
}

scan_line() { # <file> <lineno> <body> <context-message>
    local f="$1" no="$2" body="$3" ctx="$4" seg args
    is_comment "$body" && return
    case "$body" in *mktemp*) ;; *) return ;; esac
    while IFS= read -r seg || [ -n "$seg" ]; do
        # A segment begins at a command position. Strip leading blanks and any
        # assignment-word prefix (`VAR=val …`, as in `TMPDIR=/x mktemp`) so the
        # command name comes first, then read whether that command is mktemp.
        # The trailing-char class keeps a name like `mktemp_tracked`, a stub
        # path, or the word as data (`command -v mktemp`) from reading as a call.
        seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; :a; s/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+//; ta')"
        case "$seg" in
            mktemp) args="" ;;
            mktemp[!A-Za-z0-9_.-]*) args="${seg#mktemp}" ;;
            *) continue ;;
        esac
        if is_bare_args "$args"; then
            echo "$f:$no: $ctx; $FIX"
            found=1
            return
        fi
    done < <(split_commands "$body")
}

for f in "$@"; do
    [ -f "$f" ] || continue
    # The detector directory states the shape in its own fix text; the
    # runner does not, and allocates for real, so it is scanned like any file.
    case "$f" in */lint-learned.d/* | */base-snapshots/*) continue ;; esac
    grep -q 'mktemp' "$f" 2>/dev/null || continue
    case "$f" in
        *.sh)
            while IFS= read -r hit; do
                scan_line "$f" "${hit%%:*}" "${hit#*:}" \
                    'bare `mktemp` — the temp path lands in the shared /tmp/tmp.* family and cannot be traced to this script'
            done < <(grep -n 'mktemp' "$f" 2>/dev/null)
            ;;
        *.toml)
            # ``` fences and `# >>>` markers both delimit shell that is run
            # verbatim — by the agent following the recipe, or by the test
            # that extracts it.
            while IFS= read -r line; do
                scan_line "$f" "${line%%: *}" "${line#*: }" \
                    'bare `mktemp` in a recipe — the temp path lands in the shared /tmp/tmp.* family and cannot be traced to this formula'
            done < <(awk '
                /^[[:space:]]*```/            { inf = !inf; next }
                /#[[:space:]]*>>>[[:space:]]/ { inm = 1 }
                /#[[:space:]]*<<<[[:space:]]/ { inm = 0 }
                inf || inm                    { print FNR": "$0 }' "$f" 2>/dev/null)
            ;;
        *.md)
            while IFS= read -r line; do
                scan_line "$f" "${line%%: *}" "${line#*: }" \
                    'bare `mktemp` in an extracted snippet — the temp path cannot be traced to its producer'
            done < <(awk '
                /#[[:space:]]*>>>[[:space:]]/ { inm = 1 }
                /#[[:space:]]*<<<[[:space:]]/ { inm = 0 }
                inm                           { print FNR": "$0 }' "$f" 2>/dev/null)
            ;;
    esac
done

[ "$found" -eq 0 ]
