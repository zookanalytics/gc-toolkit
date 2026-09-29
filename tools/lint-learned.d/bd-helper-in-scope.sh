#!/usr/bin/env bash
# bd-helper-in-scope.sh — hardened learned rule: a shell script that calls a
# consolidated bead-store read helper (bd_json, bd_list) must have it in scope —
# it sources the shared library that defines them (assets/scripts/bd-lib.sh), or
# it defines the helper itself.
#
# These helpers were copy-pasted into a dozen scripts and drifted. Consolidating
# them into bd-lib.sh removes the copies, and this detector is what keeps a
# migrated helper from silently re-drifting: a caller that drops its copy without
# sourcing the library calls a function defined nowhere, and an undefined
# function is a runtime failure — `bash -n` passes and the script dies with
# `command not found` only on the branch that reaches the call.
#
# A file that needs a purpose-built read (a --db/run_bounded store scope, an
# injected --rig) DEFINES the helper itself: that is in scope, no finding. The
# rule is only that a call resolves — never that the definition come from the
# library. So the rule needs no exemptions: define it or source it.
#
# Scanned: *.sh, command position only. Quoted spans are blanked and whole-line
# comments skipped, so a name stated in prose or a string is not a finding. A
# definition `bd_json()` is not a call — the trailing class excludes `(`.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

LIB="bd-lib.sh"
# A call in command position, one regex per helper: after a separator or a
# command-substitution opener, or after a word that takes a command. The
# trailing class is a non-identifier byte other than `(`, so `bd_json` reads as a
# call, `bd_json()` as a definition, and `bd_jsonx` as neither.
JSON_SEP='(^|[;&|(){}]|\$\(|`)[[:space:]]*bd_json([[:space:]]|;|\)|$)'
JSON_WRAP='(^|[^[:alnum:]_./-])(then|do|else|elif|if|while|until|run_bounded|command|exec|env|time|!)[[:space:]]+bd_json([[:space:]]|;|\)|$)'
LIST_SEP='(^|[;&|(){}]|\$\(|`)[[:space:]]*bd_list([[:space:]]|;|\)|$)'
LIST_WRAP='(^|[^[:alnum:]_./-])(then|do|else|elif|if|while|until|run_bounded|command|exec|env|time|!)[[:space:]]+bd_list([[:space:]]|;|\)|$)'
# The two shapes that put a helper in scope: a local definition, or a source of
# the shared library.
DEF_RE='^[[:space:]]*(bd_json|bd_list)[[:space:]]*\(\)'
DEF_FN_RE='^[[:space:]]*function[[:space:]]+(bd_json|bd_list)([[:space:]]|\(|$)'
SRC_RE='^[[:space:]]*(\.|source)[[:space:]].*'"$LIB"
FIX='fix: source bd-lib.sh (. "${GC_BD_LIB:-$DIR/bd-lib.sh}") or define the helper (learned rule: bd-helper-in-scope)'

# strip_quoted <line> — blanks single- and double-quoted spans so a name inside a
# string cannot read as a command. Backslash escapes consume the character they
# protect. Same shape as raw-bd-invocation.sh.
strip_quoted() {
    local s="$1" out="" q="" ch i n=${#1}
    for (( i = 0; i < n; i++ )); do
        ch="${s:i:1}"
        if [ "$ch" = "\\" ]; then i=$((i + 1)); [ -n "$q" ] || out+="  "; continue; fi
        if [ -n "$q" ]; then
            [ "$ch" = "$q" ] && { q=""; out+=" "; continue; }
            out+=" "; continue
        fi
        case "$ch" in "'" | '"') q="$ch"; out+=" "; continue ;; esac
        out+="$ch"
    done
    printf '%s' "$out"
}

found=0

for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */lint-learned.sh | */base-snapshots/*) continue ;;
        *.sh) ;;
        *) continue ;;
    esac
    # One cheap read gates the line scan.
    grep -Eq 'bd_json|bd_list' "$f" 2>/dev/null || continue

    # First pass: what is callable in this file. Sourcing the library defines
    # both; a local definition defines the one it names.
    in_scope_json=0 in_scope_list=0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in *bd_json* | *bd_list* | *"$LIB"*) ;; *) continue ;; esac
        if [[ "$line" =~ $SRC_RE ]]; then in_scope_json=1; in_scope_list=1; break; fi
        if [[ "$line" =~ $DEF_RE ]] || [[ "$line" =~ $DEF_FN_RE ]]; then
            case "$line" in *bd_json*) in_scope_json=1 ;; esac
            case "$line" in *bd_list*) in_scope_list=1 ;; esac
        fi
    done < "$f"
    # Everything the file could call is in scope — no call can dangle.
    [ "$in_scope_json" = 1 ] && [ "$in_scope_list" = 1 ] && continue

    # Second pass: a call to a helper not in scope is the dangling call.
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        case "$line" in *bd_json* | *bd_list*) ;; *) continue ;; esac
        # Whole-line comments only; `cmd  # note` is code.
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in '#'*) continue ;; esac
        code="$(strip_quoted "$line")"

        if [ "$in_scope_json" = 0 ] && { [[ "$code" =~ $JSON_SEP ]] || [[ "$code" =~ $JSON_WRAP ]]; }; then
            echo "$f:$lineno: calls \`bd_json\` but the file neither defines it nor sources $LIB — an undefined function passes bash -n and dies at runtime; $FIX"
            found=1
        fi
        if [ "$in_scope_list" = 0 ] && { [[ "$code" =~ $LIST_SEP ]] || [[ "$code" =~ $LIST_WRAP ]]; }; then
            echo "$f:$lineno: calls \`bd_list\` but the file neither defines it nor sources $LIB — an undefined function passes bash -n and dies at runtime; $FIX"
            found=1
        fi
    done < "$f"
done

[ "$found" -eq 0 ]
