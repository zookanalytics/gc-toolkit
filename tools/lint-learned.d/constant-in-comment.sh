#!/usr/bin/env bash
# constant-in-comment.sh — hardened learned rule: a comment must not
# duplicate the literal value of a nearby constant.
#
# HEURISTIC DETECTOR. Language-agnostic, so it works from shape, not syntax:
#   1. find assignment-like lines —  NAME = value | NAME := value, with
#      optional declaration keywords (const/final/static/export/…) in front —
#      where value is a number or a short quoted string;
#   2. flag any comment within ±3 lines (including a trailing comment on the
#      assignment line itself) that repeats that same literal as a distinct
#      token.
# A comment that restates the value ("# retry 5 times" above RETRIES = 5)
# goes silently wrong when the constant changes; the comment should carry
# intent, not the number.
#
# Tuned to PREFER FALSE NEGATIVES over false positives:
#   • trivial literals are skipped — 0, 1, -1, 0.0, 1.0, empty and
#     single-character strings — they appear everywhere and prove nothing;
#   • quoted strings longer than 24 chars are skipped (long strings in
#     comments are usually quoted prose, not a duplicated constant);
#   • the literal must appear token-bounded inside the COMMENT PORTION of a
#     line only — matches in code are never findings.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

# Assignment shape: optional declaration keywords, NAME, = or :=, value.
kw='(export|const|final|static|let|var|readonly|local|val|def|public|private|protected|declare|-r|-i)'
assign_re="^[[:space:]]*(${kw}[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(=|:=)[[:space:]]*(.*)$"
num_re='^(-?[0-9]+(\.[0-9]+)?)([^0-9A-Za-z_.].*)?$'
dq_re='^"([^"]*)"'
sq_re="^'([^']*)'"

# Escape a literal for use inside an extended regex.
ere_escape() {
    # shellcheck disable=SC2016 # the $ is a literal ERE metachar, not expansion
    printf '%s' "$1" | sed -e 's/[][\.|$(){}?+*^\\/]/\\&/g'
}

found=0

for f in "$@"; do
    [ -f "$f" ] || continue
    # Skip binaries cheaply: grep -qI exits 1 on binary data.
    grep -qI . -- "$f" 2>/dev/null || continue

    mapfile -t lines < "$f"
    n="${#lines[@]}"
    declare -A flagged=()

    for ((i = 0; i < n; i++)); do
        [[ "${lines[$i]}" =~ $assign_re ]] || continue
        name="${BASH_REMATCH[3]}"
        rest="${BASH_REMATCH[5]}"

        # Extract a number or short quoted string; skip everything else.
        lit=""
        kind=""
        if [[ "$rest" =~ $num_re ]]; then
            lit="${BASH_REMATCH[1]}"
            kind="num"
        elif [[ "$rest" =~ $dq_re ]] || [[ "$rest" =~ $sq_re ]]; then
            lit="${BASH_REMATCH[1]}"
            kind="str"
        fi
        [ -n "$lit" ] || continue

        # Trivial-literal skip: 0/1/-1 (and float forms) for numbers,
        # empty or single-character content for strings — too common to
        # mean anything. Long strings are quoted prose, not constants.
        if [ "$kind" = "num" ]; then
            case "$lit" in
                0 | 1 | -1 | 0.0 | 1.0) continue ;;
            esac
        else
            [ "${#lit}" -lt 2 ] && continue
        fi
        [ "${#lit}" -gt 24 ] && continue

        lit_re="$(ere_escape "$lit")"
        if [ "$kind" = "num" ]; then
            # `.` and `-` are non-boundaries for numbers so 30 never
            # matches inside 30.5 or -30.
            hit_re="(^|[^[:alnum:]_.-])${lit_re}([^[:alnum:]_.-]|$)"
        else
            hit_re="(^|[^[:alnum:]_])${lit_re}([^[:alnum:]_]|$)"
        fi

        lo=$((i - 3)); [ "$lo" -lt 0 ] && lo=0
        hi=$((i + 3)); [ "$hi" -ge "$n" ] && hi=$((n - 1))

        for ((j = lo; j <= hi; j++)); do
            [ -n "${flagged[$j]:-}" ] && continue
            line="${lines[$j]}"

            # Isolate the comment portion: text after the LEFTMOST comment
            # leader, or a block-comment continuation line (leading `*`).
            comment=""
            best=${#line}
            for l in '#' '//' '/*' '<!--'; do
                pre="${line%%"$l"*}"
                if [ "$pre" != "$line" ] && [ "${#pre}" -lt "$best" ]; then
                    best="${#pre}"
                    comment="${line:$((best + ${#l}))}"
                fi
            done
            if [ -z "$comment" ] && [[ "$line" =~ ^[[:space:]]*\*+[[:space:]](.*)$ ]]; then
                comment="${BASH_REMATCH[1]}"
            fi
            [ -n "$comment" ] || continue

            if printf '%s' "$comment" | grep -qE "$hit_re"; then
                echo "$f:$((j + 1)): comment repeats the literal '$lit' assigned to $name on line $((i + 1)) — say why, not what; the value will drift (learned rule: constant-in-comment)"
                flagged[$j]=1
                found=1
            fi
        done
    done
    unset flagged
done

[ "$found" -eq 0 ]
