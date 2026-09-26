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
# Output: four eval-able assignments on stdout, each value single-quoted so a
# caller can `eval` them without a metacharacter in the data becoming syntax —
#   SUBJECT=<recovered-or-passed group>
#   ITEM=<the bead step 5 writes to>
#   TOPIC=<what decides sameness>
#   HOLDER=<$VISIT when you hold it, another visit's id to fold into it,
#           EMPTY when the listing did not read (hold, do not fold)>
set -u

# The one definition of what subject a visit covers (its tracks-edge identity,
# gc.continuation_group stamp as fallback), shared with gc-helm.sh and the
# sweeps. Exposes $VISIT_IDENTITY_JQ. stall_root stays this script's TOPIC/item
# discriminator below — it is not the identity.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=visit-identity.sh
. "$HERE/visit-identity.sh" || { echo "converse-fold: cannot source visit-identity.sh from $HERE" >&2; exit 3; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# >>> eval-safe-quote
# The caller evals the SUBJECT/HOLDER assignments below, and SUBJECT is a
# continuation group recovered from claim/metadata, so it can carry any byte.
# Single-quote every emitted value so eval reads it as one literal string: a
# group like `g;rm -rf x` stays data, never shell syntax. An embedded single
# quote becomes the '\'' idiom.
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# <<< eval-safe-quote

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
  SUBJECT=$(printf '%s' "$V" | jq -r "$VISIT_IDENTITY_JQ"'(.[0] // {}) | visit_subject')
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
    | jq -r --arg s "$SUBJECT" --arg t "$TOPIC" --arg v "$VISIT" "$VISIT_IDENTITY_JQ"'
        def topic($fallback):
          (.metadata.stall_root // "") as $r
          | (.metadata.escalation_key // "") as $k
          | if $r != "" then $r
            elif $k != "" then "key:" + $k
            else $fallback end;
        [ .[]
          | select((.metadata.task_kind // "")=="visit")
          # a sibling wears the same flaky stamp: read ITS subject the shared way
          | (visit_subject) as $cg
          | select($cg==$s)
          | select(topic($s)==$t)
          | select((.assignee // "")!="")
          | .id ]
        + [$v] | unique | .[0]')
fi

printf 'SUBJECT=%s\n' "$(shq "$SUBJECT")"
printf 'ITEM=%s\n' "$(shq "$ITEM")"
printf 'TOPIC=%s\n' "$(shq "$TOPIC")"
printf 'HOLDER=%s\n' "$(shq "$HOLDER")"
