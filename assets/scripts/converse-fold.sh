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
#           EMPTY when no store read (hold, do not fold)>
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

# >>> bounded-store-read
# The HOLDER scan below reads every rig's store, so one slow or hung Dolt
# server would otherwise wedge a converse claim. Bound each read; a store that
# does not answer in time is skipped like an unreadable one. No `timeout` on
# the box means no bound, as the ledger migrations do.
BOUND="${GC_FOLD_SCAN_TIMEOUT:-20}"
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
# <<< bounded-store-read

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
  # The peer scan must see sittings in EVERY store, not just the claiming
  # session's. A subject's visits can be filed into more than one store — the
  # pool that files a visit need not be the pool that claims it — so a
  # single-store scan reads only its own half: both sittings read themselves as
  # the sole holder and the lowest-id tiebreak never runs. Union the
  # in_progress listing across the rigs' stores, then apply the same predicates
  # and the same tiebreak. Store-prefixed ids are totally ordered, so the
  # tiebreak sorts across stores unchanged.
  SCOPES=$(run_bounded gc rig list --json 2>/dev/null | scrub \
    | jq -r '.rigs[]? | select((.path // "") != "")
             | [.path, ((.suspended // false) | tostring)] | join("\u001f")' 2>/dev/null)
  if [ -z "$SCOPES" ]; then
    # gc rig list named no store, so no scan can be proven complete. Resolve
    # EMPTY, which the caller reads as hold — never a fold on an unread listing.
    HOLDER=""
  else
    UNION=""
    READABLE=0
    while IFS=$'\037' read -r rig_path suspended; do
      [ -n "$rig_path" ] || continue
      # A suspended rig has no live session to hold a sitting, and querying its
      # store would auto-start an orphan Dolt server.
      [ "$suspended" = "true" ] && continue
      rows=$(run_bounded gc bd list --db "$rig_path/.beads" --status=in_progress --json --limit=0 2>/dev/null | scrub)
      if printf '%s' "$rows" | jq -e 'type=="array"' >/dev/null 2>&1; then
        READABLE=$((READABLE + 1))
        UNION="$UNION$rows
"
      else
        # A store that did not read cannot be proven free of a peer, but the
        # readable stores still dedup among themselves: a fold only ever targets
        # a readable lower id, so a blip here degrades to the old single-store
        # miss, never a fold into a sitting no one can see.
        echo "converse-fold: store $rig_path/.beads did not read; its in_progress visits are absent from this scan" >&2
      fi
    done <<SCOPES_EOF
$SCOPES
SCOPES_EOF
    if [ "$READABLE" -eq 0 ]; then
      # Not one store read — the same unprovable case as a single unreadable
      # listing, so hold rather than fold.
      HOLDER=""
    else
      HOLDER=$(printf '%s' "$UNION" | jq -s -r --arg s "$SUBJECT" --arg t "$TOPIC" --arg v "$VISIT" "$VISIT_IDENTITY_JQ"'
          def topic($fallback):
            (.metadata.stall_root // "") as $r
            | (.metadata.escalation_key // "") as $k
            | if $r != "" then $r
              elif $k != "" then "key:" + $k
              else $fallback end;
          [ (add // [])[]
            | select((.metadata.task_kind // "")=="visit")
            # a sibling wears the same flaky stamp: read ITS subject the shared way
            | (visit_subject) as $cg
            | select($cg==$s)
            | select(topic($s)==$t)
            | select((.assignee // "")!="")
            | .id ]
          + [$v] | unique | .[0]')
    fi
  fi
fi

printf 'SUBJECT=%s\n' "$(shq "$SUBJECT")"
printf 'ITEM=%s\n' "$(shq "$ITEM")"
printf 'TOPIC=%s\n' "$(shq "$TOPIC")"
printf 'HOLDER=%s\n' "$(shq "$HOLDER")"
