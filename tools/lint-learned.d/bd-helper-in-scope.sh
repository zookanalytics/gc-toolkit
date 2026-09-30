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
# Scanned: *.sh, command position only. String literals are blanked and
# whole-line comments skipped, so a name in prose or a string is not a finding;
# a command substitution keeps its code, so a call inside "$(bd_list ...)" is. A
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

# strip_quoted <line> — blanks quoted STRING content so a name inside a string
# literal cannot read as a command, while keeping command substitutions ($(...)
# and `...`) as code: a helper called inside "$(bd_list ...)" runs at runtime
# even though it sits within double quotes, so its bytes must survive the scan.
# Single-quoted spans expand nothing and stay fully blanked; backslash escapes
# consume the character they protect.
strip_quoted() {
    local s="$1" out="" ch nx i n=${#1}
    # Context stack, top last: S single-quote, D double-quote, C $(...), B `...`.
    # An empty stack is unquoted code. Each C frame carries a paren depth in `pd`
    # so a nested ( ) or a $(( )) closes on its own matching ), not the first one.
    local -a st=() pd=()
    local top si pi
    for (( i = 0; i < n; i++ )); do
        ch="${s:i:1}"
        top=""; [ "${#st[@]}" -gt 0 ] && top="${st[${#st[@]}-1]}"

        # Single quote: everything literal until the closing '.
        if [ "$top" = S ]; then
            out+=" "
            [ "$ch" = "'" ] && { si=$(( ${#st[@]} - 1 )); unset "st[$si]"; }
            continue
        fi

        # Double quote: literal text, but $( and ` open live command subs.
        if [ "$top" = D ]; then
            if [ "$ch" = "\\" ]; then out+="  "; i=$((i + 1)); continue; fi
            if [ "$ch" = '"' ]; then out+=" "; si=$(( ${#st[@]} - 1 )); unset "st[$si]"; continue; fi
            if [ "$ch" = '`' ]; then out+='`'; st+=(B); continue; fi
            if [ "$ch" = '$' ]; then
                nx="${s:i+1:1}"
                [ "$nx" = '(' ] && { out+='$('; st+=(C); pd+=(1); i=$((i + 1)); continue; }
            fi
            out+=" "
            continue
        fi

        # Code contexts: unquoted, C $(...), or B `...`.
        if [ "$ch" = "\\" ]; then out+="  "; i=$((i + 1)); continue; fi
        case "$ch" in
            "'") out+=" "; st+=(S); continue ;;
            '"') out+=" "; st+=(D); continue ;;
            '`')
                if [ "$top" = B ]; then out+='`'; si=$(( ${#st[@]} - 1 )); unset "st[$si]"
                else out+='`'; st+=(B); fi
                continue ;;
            '$')
                nx="${s:i+1:1}"
                if [ "$nx" = '(' ]; then out+='$('; st+=(C); pd+=(1); i=$((i + 1)); continue; fi
                out+='$'; continue ;;
            '(')
                out+='('
                [ "$top" = C ] && { pi=$(( ${#pd[@]} - 1 )); pd[pi]=$(( pd[pi] + 1 )); }
                continue ;;
            ')')
                out+=')'
                if [ "$top" = C ]; then
                    pi=$(( ${#pd[@]} - 1 )); pd[pi]=$(( pd[pi] - 1 ))
                    if [ "${pd[pi]}" -le 0 ]; then
                        si=$(( ${#st[@]} - 1 )); unset "st[$si]"; unset "pd[$pi]"
                    fi
                fi
                continue ;;
            *) out+="$ch"; continue ;;
        esac
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
