#!/usr/bin/env bash
# converse-parent.sh — the parent that new work serving a subject's epic takes:
# the subject's nearest parent-child ancestor that is not closed. Everything a
# sitting files lands BESIDE the subject rather than under it: beads refuses a
# `blocks` edge from a parent to its own descendant, so a gate or work bead
# filed under the subject could never gate it. A closed parent is skipped,
# because work filed under a closed bead follows no priority and sits under no
# open row (docs/steering.md, Priority). So a Story under a Delivery that its
# checkpoint has closed gives the epic above that Delivery.
#
# A parent-child edge is stored on the child, and `gc bd show` prints each
# parent's status beside its edge, so the walk reads the subject and then only
# the closed parents it climbs past. It climbs one level at a time: a parent
# that is not closed wins over every bead above it, and within a level the first
# such parent in the order bd prints them wins.
#
# Prints the ancestor's id, or an empty line when no ancestor is open. A bead
# that cannot be read on the way is not an empty answer: the script prints
# nothing on stdout and exits 1.
#
# Input (environment, or positional fallback):
#   SUBJECT  the subject bead ($1)
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

SUBJECT="${SUBJECT:-${1:-}}"

[ -n "$SUBJECT" ] || { echo "converse-parent: a subject id is required (\$SUBJECT or arg 1)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "converse-parent: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "converse-parent: gc is required" >&2; exit 2; }

# parents_of <id> — the parent-child parents of <id>, one "<parent> <status>"
# line each, in the order bd prints them. Fails when gc cannot show <id>, when
# what it shows is not <id>, or when a parent's row carries no id or status.
parents_of() {
    local json
    json=$(gc bd show "$1" --json) || return 1
    printf '%s' "$json" | scrub | jq -r --arg id "$1" '
      if ((.[0].id // "") | tostring) != $id then error("gc bd show did not return \($id)") else . end
      | [ .[0].dependencies[]? | select(((.dependency_type // "") | tostring) == "parent-child") ]
      | if any(.[]; ((.id // "") | tostring) == "" or ((.status // "") | tostring) == "")
        then error("a parent row of \($id) carries no id or status") else . end
      | .[] | "\(.id | tostring) \(.status | tostring)"'
}

LEVEL=$SUBJECT
SEEN=" $SUBJECT "
while [ -n "$LEVEL" ]; do
    NEXT=""
    for ID in $LEVEL; do
        ROWS=$(parents_of "$ID") || { echo "converse-parent: cannot read the parents of $ID" >&2; exit 1; }
        while read -r PARENT STATUS; do
            [ -n "$PARENT" ] || continue
            case "$SEEN" in *" $PARENT "*) continue ;; esac
            [ "$STATUS" = closed ] || { printf '%s\n' "$PARENT"; exit 0; }
            SEEN="$SEEN$PARENT "
            NEXT="$NEXT $PARENT"
        done <<EOF
$ROWS
EOF
    done
    LEVEL=$NEXT
done
printf '\n'
