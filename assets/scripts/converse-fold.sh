#!/usr/bin/env bash
# converse-fold.sh — resolve what a fresh visit's sitting is about and who
# holds it, so the caller can fold a duplicate into a live sibling instead of
# opening a second sitting on one topic.
#
# A standing scope (task_kind=triage-subject) carries one visit per distinct
# item under a single continuation group, so the group is a bucket, not a
# topic. Keying the fold on the group alone folds unrelated sittings together
# (one lost) or folds two live sittings into each other (both lost). The item
# is the visit's own stall_root; the TOPIC that decides sameness is the
# stall_root, else a `key:`-prefixed escalation_key, else the subject; and the
# lowest-id tiebreak plus the tracks-edge recovery of an empty group stamp are
# each load-bearing. assets/scripts/converse-fold-scope.test.sh runs this
# against every one of those shapes.
#
# Inputs (environment, or positional fallback):
#   VISIT    the visit bead just claimed (required; $1)
#   SUBJECT  its continuation group; may be empty and recovered here ($2)
# Output: four key=value lines on stdout —
#   SUBJECT=<recovered-or-passed group>
#   ITEM=<the bead step 5 writes to>
#   TOPIC=<what decides sameness>
#   HOLDER=<$VISIT when you hold it, another visit's id to fold into it,
#           EMPTY when the listing did not read (hold, do not fold)>
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

VISIT="${VISIT:-${1:-}}"
SUBJECT="${SUBJECT:-${2:-}}"

[ -n "$VISIT" ] || { echo "converse-fold: a visit id is required (\$VISIT or arg 1)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "converse-fold: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "converse-fold: gc is required" >&2; exit 2; }

V=$(gc bd show "$VISIT" --json | scrub)
ITEM=$(printf '%s' "$V" | jq -r '.[0].metadata.stall_root // ""')
# The claim reports the gc.continuation_group STAMP, and the stamp lands
# empty on a minority of visits while the `tracks` edge filed alongside
# it still carries the subject. Recover it from the edge before using it
# as a filter — every predicate below keys on it.
if [ -z "$SUBJECT" ]; then
  SUBJECT=$(printf '%s' "$V" | jq -r '
    [ ((.[0].dependencies // [])[]?
        | select((((.type // .dependency_type // "") | tostring))=="tracks")
        | ((.depends_on_id // .id // "") | tostring)) ]
    | map(select(. != "")) | .[0] // ""')
fi
ITEM="${ITEM:-$SUBJECT}"
# The item is a bead, because step 5 writes to it. The TOPIC is what
# decides sameness, and it is not always a bead: an escalate.sh visit
# names no target and carries its situation in escalation_key, which is
# the only stamp that tells two findings of one bucket apart. The `key:`
# prefix keeps a key and a bead id from ever comparing equal.
TOPIC=$(printf '%s' "$V" | jq -r '.[0].metadata
  | (.stall_root // "") as $r | (.escalation_key // "") as $k
  | if $r != "" then $r elif $k != "" then "key:" + $k else "" end')
TOPIC="${TOPIC:-$SUBJECT}"
if [ -z "$SUBJECT" ]; then
  # Neither recording resolved. With an empty $s every predicate below
  # degenerates to matching every empty-group visit — an unstamped visit's
  # topic falls back to $s and matches as well — and the lowest-id
  # tiebreak would fold this sitting into one about an unrelated subject.
  # You are the holder.
  HOLDER="$VISIT"
else
  HOLDER=$(gc bd list --status=in_progress --json --limit=0 \
    | scrub \
    | jq -r --arg s "$SUBJECT" --arg t "$TOPIC" --arg v "$VISIT" '
        def topic($fallback):
          (.metadata.stall_root // "") as $r
          | (.metadata.escalation_key // "") as $k
          | if $r != "" then $r
            elif $k != "" then "key:" + $k
            else $fallback end;
        [ .[]
          | select((.metadata.task_kind // "")=="visit")
          | . as $c
          # a sibling wears the same flaky stamp: read ITS group the same way
          | (if (($c.metadata // {})["gc.continuation_group"] // "") != ""
             then (($c.metadata // {})["gc.continuation_group"] // "")
             else ([ ($c.dependencies // [])[]?
                     | select((((.type // .dependency_type // "") | tostring))=="tracks")
                     | ((.depends_on_id // .id // "") | tostring) ]
                   | map(select(. != "")) | .[0] // "") end) as $cg
          | select($cg==$s)
          | select(topic($s)==$t)
          | select((.assignee // "")!="")
          | .id ]
        + [$v] | unique | .[0]')
fi

printf 'SUBJECT=%s\n' "$SUBJECT"
printf 'ITEM=%s\n' "$ITEM"
printf 'TOPIC=%s\n' "$TOPIC"
printf 'HOLDER=%s\n' "$HOLDER"
