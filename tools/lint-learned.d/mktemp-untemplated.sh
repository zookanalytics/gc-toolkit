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
#
# A finding is a real command position. Quoted strings and here-doc bodies are
# data fed to a command, not commands, so a `mktemp` inside one is left alone;
# an executable wrapper (`command`, `env`, `exec`, `nohup`, `time`, `timeout`)
# runs what follows, so the wrapped call is seen through. No exception list: a
# template is always available, and a path built from a variable counts.
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
# its own segment, so each `mktemp` is judged against only its own argument
# list. Single- then double-quoted spans collapse to one word first, so a
# separator or a `mktemp` inside a string is data, not a command; `$(…)` and
# `` `…` `` are split out before the double-quote pass so a substitution that
# runs inside double quotes stays a command position.
split_commands() {
    printf '%s' "$1" \
        | sed -E "s/'[^']*'/_/g" \
        | sed -E 's/\$\(/\n/g; s/`/\n/g' \
        | sed -E 's/"[^"]*"/_/g; s/[;&|]/\n/g; s/[(){}!]/\n/g; s/(^|[[:space:]])(if|elif|then|else|while|until|do)([[:space:]]+)/\1\n/g'
}

# Peel assignment-word prefixes and executable wrappers so the wrapped command
# is examined, not the wrapper. `command mktemp`, `env VAR=x mktemp`, `time
# mktemp`, `exec mktemp`, `nohup mktemp` and `timeout N mktemp` all run mktemp.
# `command -v NAME` / `command -V NAME` look a name up without running it, so
# the operand is data and this prints nothing. An option that takes a separate
# word is not modelled: leaving that word makes the call read as something
# other than mktemp, a miss rather than a false finding.
resolve_command() {
    local restore_f="" w=""
    case $- in *f*) ;; *) restore_f=1 ;; esac
    set -f
    # shellcheck disable=SC2086
    set -- $1
    [ -z "$restore_f" ] || set +f
    while [ "$#" -gt 0 ]; do
        case "$1" in
            [A-Za-z_]*=*) shift; continue ;;
        esac
        case " command env exec nohup time timeout " in
            *" $1 "*) ;;
            *) break ;;
        esac
        if [ "$1" = command ]; then
            case "${2:-}" in -v|-V) return 0 ;; esac
        fi
        w="$1"; shift
        while [ "$#" -gt 0 ]; do
            case "$1" in -?*) shift ;; *) break ;; esac
        done
        [ "$w" = timeout ] && [ "$#" -gt 0 ] && case "$1" in [0-9]*) shift ;; esac
    done
    printf '%s' "$*"
}

scan_line() { # <file> <lineno> <body> <context-message>
    local f="$1" no="$2" body="$3" ctx="$4" seg args
    is_comment "$body" && return
    case "$body" in *mktemp*) ;; *) return ;; esac
    while IFS= read -r seg || [ -n "$seg" ]; do
        # A segment begins at a command position. Peel any assignment-word
        # prefix (`VAR=val …`, as in `TMPDIR=/x mktemp`) and executable wrapper
        # so the command name comes first, then read whether that command is
        # mktemp. The trailing-char class keeps a name like `mktemp_tracked`, a
        # stub path, or the word as data (`command -v mktemp`) from reading as
        # a call.
        seg="$(resolve_command "$seg")"
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

# Lines of a *.sh file that hold a real command, paired with their line number.
# A here-doc body is the data a command reads, not commands, so the lines from
# an opener to its terminator are dropped; `<<-` strips leading tabs on the
# terminator, and `<<<` is a here-string, which opens no body.
sh_command_lines() {
    awk '
        hd != "" {
            t = $0
            if (dash) sub(/^\t+/, "", t)
            if (t == hd) hd = ""
            next
        }
        {
            if (match($0, /(^|[^<])<<-?[[:space:]]*[^[:space:]<>;&|()]+/)) {
                m = substr($0, RSTART, RLENGTH)
                dash = (m ~ /<<-/)
                sub(/^[^<]*<<-?[[:space:]]*/, "", m)
                gsub(/["'\''\\]/, "", m)
                hd = m
            }
            if ($0 ~ /mktemp/) print NR":"$0
        }
    ' "$1" 2>/dev/null
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
            done < <(sh_command_lines "$f")
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
