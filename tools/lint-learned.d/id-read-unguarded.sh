#!/usr/bin/env bash
# id-read-unguarded.sh — hardened learned rule: the id in a bd answer is read
# type-guarded, never as an alternative between the object read and the array
# read (`.id // .[0].id`, in either order).
#
# bd answers a create with the bead as an object, other verbs with an array
# holding the bead, and a refused create with a bare {"error": ...} object.
# The alternative looks as if it covers both shapes and covers neither: jq
# 1.8's `//` does not catch an error raised on its left, so an array answer
# dies at `.id`, and a refusal reaches the right arm and dies at `.[0]`. Under
# 2>/dev/null either crash reads as "no id", even for a bead that was filed.
# Without it, the reader sees "Cannot index object with number" where bd's
# reason should be. The guarded read takes either shape and yields nothing for
# a refusal, whose .error the caller then reports:
#   jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end'
#
# Scanned: the lines that run. In *.sh that is every line but a whole-line
# comment. In *.toml and *.md it is the lines inside ``` fences, where formula
# steps, skills and prompt fragments keep the commands an agent runs; prose
# outside a fence may quote the shape. Skipped: this directory, specs/ (dated
# records) and generated/ (renders of files scanned at their source).
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 when a file could
# not be scanned.

set -uo pipefail

# Either order. Each arm ends at a non-identifier byte, so a longer key such as
# `.idx` is not read as `.id`.
ALT='\.id[[:space:]]*//[[:space:]]*\.\[0\]\.id([^[:alnum:]_]|$)|\.\[0\]\.id[[:space:]]*//[[:space:]]*\.id([^[:alnum:]_]|$)'
FIX="read it type-guarded: jq -r 'if type == \"array\" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null, and report the answer's .error when no id comes back (learned rule: id-read-unguarded)"
MSG="reads a bd answer's id as an object-or-array alternative — an array answer crashes jq at \`.id\` and a refused create ({\"error\": ...}) crashes it at \`.[0]\`, so the crash stands in for bd's reason; $FIX"

scope=()
for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */base-snapshots/* | */specs/* | specs/* | */generated/* | generated/*) continue ;;
        *.sh | *.toml | *.md) scope+=("$f") ;;
    esac
done
[ "${#scope[@]}" -gt 0 ] || exit 0

# One grep over the whole scope names the files worth a closer look. Exit 1 is
# "no file has the shape"; anything past it is a file that could not be read.
candidates="$(grep -lE -- "$ALT" "${scope[@]}")"; rc=$?
[ "$rc" -eq 1 ] && exit 0
if [ "$rc" -ne 0 ]; then
    echo "id-read-unguarded: grep exited $rc reading the scanned files — detector cannot scan them" >&2
    exit 2
fi

found=0

while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
        *.sh)
            if ! lines="$(awk '{ print FNR ":" $0 }' "$f")"; then
                echo "id-read-unguarded: could not number the lines of $f — detector cannot scan it" >&2
                exit 2
            fi ;;
        *)
            # A fence opens or closes on a line that starts with ``` or ~~~.
            if ! lines="$(awk '/^[ \t]*(```|~~~)/ { fence = !fence; next } fence { print FNR ":" $0 }' "$f")"; then
                echo "id-read-unguarded: could not read the fenced lines of $f — detector cannot scan it" >&2
                exit 2
            fi ;;
    esac

    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        no="${hit%%:*}"; body="${hit#*:}"
        # A whole-line comment states the shape rather than runs it.
        trimmed="${body#"${body%%[![:space:]]*}"}"
        case "$trimmed" in '#'*) continue ;; esac
        echo "$f:$no: $MSG"
        found=1
    done < <(printf '%s\n' "$lines" | grep -E -- "$ALT")
done <<< "$candidates"

[ "$found" -eq 0 ]
