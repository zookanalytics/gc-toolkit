#!/usr/bin/env bash
# review-cutover.sh — closes the old review path's scaffolding on a bead that a
# rig's cutover has moved onto Gas Town's pending-through-merge record.
#
# On the record, one review run per head judges the PR whole, so the bead's open
# review beads, validation passes and machine findings have nothing left to
# settle. The evaluator would still hold the PR on each of them, because it reads
# every open bead whose anchor_bead names the PR's bead as work in flight
# (anchoredTo in services/gctk/pr/pr.go). Each one closes superseded in one
# write, bd's checked close, which carries gc.outcome=superseded, the runtime's
# work record (gc.work_outcome=no-op, since it ships no commit) and a note that
# names the move.
#
# These are left as they are:
#   - a human finding (finding.source human:<login>), which the review run's
#     rule-and-repair step reads with its fix unit and rules;
#   - an open rework child (task_kind=rework), which finishes on the branch as it
#     does today: the refinery takes it before its anchor, and the landing order
#     pours no run while it works the branch;
#   - a machine finding that an open rework child of the bead still blocks. bd
#     refuses that close while the child is open, and finding.sh close-answered
#     closes the finding once the child lands, in the record step of the run the
#     landing order pours then;
#   - any other bead whose anchor_bead names the bead, which is no review
#     scaffolding.
#
# It refuses a bead whose merge_result is pull_request or pre_open_gate. The old
# path's merge cadence still reads such a bead, and gate-ensure.sh would file
# its reviews again, so the script runs after the bead's move.
#
# The bead's store is the one its id prefix names (bead-store.sh --db), so the
# script runs from any directory. It exists for each rig's cutover and goes with
# the old review path. Test: review-cutover.test.sh.
#
# Exit: 0 every review bead, validation pass and machine finding on the bead is
#       closed or left by the rules above · 1 refused: the bead is not found, is
#       still on the old path, or a close is held by something other than an open
#       rework child of the bead, each named · 2 usage · 3 the store did not
#       answer, so nothing more is known and the call can be run again.
set -uo pipefail

PROG="review-cutover"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  echo "usage: $PROG --bead <bead>" >&2
  exit 2
}

BEAD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead) [ -n "${2:-}" ] || usage; BEAD="$2"; shift 2 ;;
    -h|--help) echo "usage: $PROG --bead <bead>"; exit 0 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
[ -n "$BEAD" ] || usage

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"

DB=$("$HERE/bead-store.sh" --db "$BEAD"); rc=$?
case "$rc" in
  0) : ;;
  1) echo "$PROG: no rig's store carries $BEAD; nothing closed" >&2; exit 1 ;;
  *) echo "$PROG: the store for $BEAD did not resolve; nothing closed, so run it again" >&2; exit 3 ;;
esac

# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 3; }
# Every read and write goes to the bead's own store. The memo keys an entry by
# the cwd and the arguments, never the pin, so it stays off.
_bd_call() { gc bd --db "$DB" "$@"; }
unset GC_RECONCILE_BD_CACHE

LIVE="open,in_progress,blocked,deferred,hooked,pinned"

ROW=$(_bd_call show "$BEAD" --json </dev/null 2>/dev/null | scrub)
if ! printf '%s' "$ROW" | jq -e --arg id "$BEAD" 'type == "array" and length > 0 and (.[0].id // "") == $id' >/dev/null 2>&1; then
  if printf '%s' "$ROW" | jq -e 'type == "array" or (type == "object" and has("error"))' >/dev/null 2>&1; then
    echo "$PROG: $DB holds no bead $BEAD; nothing closed" >&2
    exit 1
  fi
  echo "$PROG: $BEAD did not read from $DB; nothing closed, so run it again" >&2
  exit 3
fi
MR=$(printf '%s' "$ROW" | jq -r '(.[0].metadata.merge_result // "") | tostring' 2>/dev/null)
case "$MR" in
  pull_request|pre_open_gate)
    echo "$PROG: $BEAD is at merge_result=$MR, which the old path's merge cadence still reads, so gate-ensure.sh would file its reviews again. Move it onto the record first; nothing closed" >&2
    exit 1 ;;
esac

ROWS=$(bd_anchor_children "$BEAD" "$LIVE") || {
  echo "$PROG: the beads anchored on $BEAD did not read; nothing closed, so run it again" >&2
  exit 3
}

# One line per child: its id, what the cutover does with it, and its kind.
PLAN=$(printf '%s' "$ROWS" | jq -r --arg bead "$BEAD" '
  .[] | select((.id // "") != $bead) | (.metadata // {}) as $m
  | (($m.task_kind // "") | tostring) as $k
  | (($m["finding.source"] // "") | tostring) as $src
  | if $k == "review" then [.id, "close", "review bead"]
    elif $k == "validation" then [.id, "close", "validation pass"]
    elif $k == "finding" and ($src | startswith("machine:")) then [.id, "close", "machine finding"]
    elif $k == "finding" then [.id, "leave", "human finding; the review run rules it"]
    elif $k == "rework" then [.id, "rework", "open rework child; it finishes on the branch, and the landing order pours no run while it works there"]
    else [.id, "leave", "a " + (if $k == "" then "bead with no task_kind" else $k + " bead" end) + ", which is no review scaffolding"] end
  | @tsv' 2>/dev/null) || {
  echo "$PROG: the beads anchored on $BEAD did not parse; nothing closed, so run it again" >&2
  exit 3
}

REWORK=" $(printf '%s\n' "$PLAN" | awk -F'\t' '$2 == "rework" { printf "%s ", $1 }')"
NOTE="Superseded at the rig's cutover (review-cutover.sh): $BEAD moved onto the pending-through-merge record, where one review run per head judges the PR whole."
RC=0 CLOSED=0 LEFT=0

# open_blockers <id> — the open beads that block <id>, space-joined. Non-zero
# when the read did not answer.
open_blockers() {
  local raw
  raw=$(_bd_call dep list "$1" --direction=down -t blocks --json </dev/null 2>/dev/null | scrub) || return 1
  printf '%s' "$raw" | jq -r 'if type == "array"
      then [ .[] | select(((.status // "open") | tostring | ascii_downcase) != "closed") | .id ] | join(" ")
      else error("unread") end' 2>/dev/null
}

while IFS=$'\t' read -r id act what; do
  [ -n "$id" ] || continue
  case "$act" in
    leave|rework)
      echo "$PROG: left $id ($what)"
      LEFT=$((LEFT + 1))
      continue ;;
  esac
  if _bd_call update "$id" --status=closed --set-metadata gc.outcome=superseded \
       --set-metadata gc.work_outcome=no-op --append-notes "$NOTE" </dev/null >/dev/null 2>&1; then
    echo "$PROG: closed $id ($what, superseded)"
    CLOSED=$((CLOSED + 1))
    continue
  fi
  if ! held=$(open_blockers "$id"); then
    echo "$PROG: $id ($what) did not close, and its blockers did not read; run it again" >&2
    RC=3
    continue
  fi
  read -r -a blockers <<<"$held"
  if [ "${#blockers[@]}" -eq 0 ]; then
    echo "$PROG: $id ($what) did not close, with nothing holding it; run it again" >&2
    RC=3
    continue
  fi
  others=0
  for b in "${blockers[@]}"; do
    case "$REWORK" in *" $b "*) : ;; *) others=$((others + 1)) ;; esac
  done
  if [ "$what" = "machine finding" ] && [ "$others" -eq 0 ]; then
    echo "$PROG: left $id ($what held by open rework child ${blockers[*]}; finding.sh close-answered closes it once that child lands)"
    LEFT=$((LEFT + 1))
    continue
  fi
  echo "$PROG: $id ($what) is held by ${blockers[*]}; bd refuses its close, so a person decides what releases it" >&2
  [ "$RC" -eq 3 ] || RC=1
done <<EOF
$PLAN
EOF

echo "$PROG: $BEAD: closed $CLOSED, left $LEFT"
exit "$RC"
