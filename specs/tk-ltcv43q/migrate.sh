#!/usr/bin/env bash
# migrate.sh — the cut-over for tk-ltcv43q. Each feedback pattern that still
# needs a decision gets one of the three states the distiller leaves a pattern
# in (formulas/mol-feedback-distiller.toml, judge-and-cluster §7): closed once
# resolved, waiting on its follow-up, or deferred with a date. It writes nothing
# without --apply.
#
#   migrate.sh [--apply] [--rig <name>] [--repo <path>] [--defer-days <n>]
#
# --rig names the store that holds the patterns (gc-toolkit). --repo is the
# gc-toolkit checkout whose origin/main the adopted-rule inventory is read from
# (the one holding this script). --defer-days is the distiller's
# pattern_defer_days (90).
#
# A pattern needs a decision when `bd ready` lists it, which leaves out one
# already closed, deferred or waiting. A pattern with a follow-up that could not
# be read, or that is open in another store, where an edge would hold nothing,
# is reported and left for the distiller's next run, even when another
# follow-up is open in its own store: an edge onto that one alone would release
# the pattern while the other is still open. Any other is decided by the first
# rule that fits:
#   1. waiting: a follow-up it spawned (proposal_bead, eng_bead) is open in its
#      own store. It gets a blocks edge onto each such follow-up.
#   2. resolved: its id is in the adopted-rule inventory on origin/main, or every
#      follow-up it spawned has closed. It closes with that reason.
#   3. dismissed: it is a discard bucket, named below, whose observations the
#      distiller judged not to be feedback. It closes as dismissed.
#   4. held: it gathers evidence. It is deferred until --defer-days after its
#      last_seen. When that date has passed, it is deferred for 12 hours, and
#      the first distiller run after that to judge every pending observation
#      dismisses it unless one of them is its recurrence.
#
# Every close stamps gc.work_outcome=no-op first, because a pattern ships no
# commit of its own and the runtime's work-record gate reads that key.
#
# Prints one line per pattern and a count per outcome. Exit 0 when every read
# answered and every write exited 0, 1 otherwise.
set -uo pipefail

APPLY=""; RIG="gc-toolkit"; DAYS=90
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel 2>/dev/null)"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)      APPLY=1; shift ;;
    --rig)        RIG="${2:?--rig needs a name}"; shift 2 ;;
    --repo)       REPO="${2:?--repo needs a path}"; shift 2 ;;
    --defer-days) DAYS="${2:?--defer-days needs a number}"; shift 2 ;;
    -h|--help)    sed -n '2,37p' "$0"; exit 0 ;;
    *) echo "migrate: unknown argument '$1'" >&2; exit 64 ;;
  esac
done
case "$DAYS" in ''|*[!0-9]*) echo "migrate: --defer-days takes a whole number" >&2; exit 64 ;; esac
[ -n "$REPO" ] && [ -x "$REPO/assets/scripts/learning-recurrence.sh" ] \
  || { echo "migrate: no gc-toolkit checkout at '$REPO'; pass --repo" >&2; exit 64; }

# The discard buckets: patterns the distiller stamps discarded observations
# onto. Each closes as dismissed and stays closed as discards arrive, because a
# discard reopens nothing.
BUCKETS='{
  "tk-l6kezee": "dismissed: a discard bucket for outside posts that show no review miss, which the distiller judges not to be feedback",
  "tk-xnawmfo": "dismissed: a discard bucket for outside posts read long after they were written, which the distiller judges history, not feedback"
}'

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

FAILED=0
fail() { echo "migrate: $*" >&2; FAILED=1; }

# The patterns that need a decision.
READY=$(gc bd --rig "$RIG" ready --metadata-field task_kind=feedback-pattern --json --limit 0 2>/dev/null | scrub)
printf '%s' "$READY" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || { echo "migrate: the ready patterns in $RIG could not be read; nothing decided" >&2; exit 1; }

# The adopted rules: one inventory row per anchored entry on origin/main.
git -C "$REPO" fetch origin main --quiet 2>/dev/null || echo "migrate: fetch failed; reading the last-known origin/main" >&2
INVENTORY=$("$REPO/assets/scripts/learning-recurrence.sh" --inventory --repo "$REPO" --ref origin/main) \
  || { echo "migrate: the adopted-rule inventory could not be read; nothing decided" >&2; exit 1; }
ADOPTED=$(printf '%s\n' "$INVENTORY" | awk -F'\t' '$2 != "-" && $2 != "" { print $2 "\t" $1 }' \
  | jq -R 'split("\t") | {(.[0]): .[1]}' | jq -s 'add // {}')

# Every follow-up's status, read in its own store: gc bd routes an id by its
# prefix, so each prefix is one read.
FOLLOWUPS=$(printf '%s' "$READY" | jq -r '.[] | (.metadata // {}) | (.proposal_bead // ""), (.eng_bead // "")
  | split(",")[] | gsub("^\\s+|\\s+$"; "") | select(. != "")' | sort -u)
STATUS='{}'
for prefix in $(printf '%s\n' "$FOLLOWUPS" | sed -n 's/-.*//p' | sort -u); do
  ids=$(printf '%s\n' "$FOLLOWUPS" | grep "^$prefix-")
  # shellcheck disable=SC2086  # one id per word
  if st=$(gc bd show $ids --json 2>/dev/null | scrub \
        | jq -ce 'if type == "array" then ([.[] | {(.id): .status}] | add // {}) else error end' 2>/dev/null); then
    STATUS=$(jq -cn --argjson s "$STATUS" --argjson t "$st" '$s + $t')
  else
    fail "the follow-ups with prefix $prefix could not be read"
  fi
done

# One decision per pattern, as TSV: id, outcome, the follow-ups to wait on, the
# deferral date, the reason.
TODAY_S=$(date -u +%s)
PLAN=$(printf '%s' "$READY" | jq -r --argjson adopted "$ADOPTED" --argjson status "$STATUS" \
  --argjson buckets "$BUCKETS" --argjson days "$DAYS" --argjson now "$TODAY_S" '
  def prefix: split("-")[0];
  .[] | . as $p | ($p.metadata // {}) as $m | ($p.id | prefix) as $pre
  | ([($m.proposal_bead // ""), ($m.eng_bead // "")] | map(split(",")[] | gsub("^\\s+|\\s+$"; ""))
     | map(select(. != "")) | unique) as $f
  | ([$f[] | select($status[.] == null)]) as $unread
  | ([$f[] | select(($status[.] // "closed") != "closed")]) as $open
  | ([$open[] | select(prefix != $pre)]) as $there
  | (($m.last_seen // "") | tostring) as $last
  | (if ($last | length) >= 10
     then ((($last[0:10]) + "T00:00:00Z") | fromdateiso8601) + $days * 86400 else null end) as $until
  | (($m.promotion_hold // "") | if . == "" then "the recurrence its evidence waits for" else . end) as $hold
  | if ($unread | length) > 0 then
      [$p.id, "left", "-", "-", ("a follow-up could not be read: " + ($unread | join(",")))]
    elif ($there | length) > 0 then
      [$p.id, "left", "-", "-", ("its open follow-ups are " + ($open | join(", "))
        + "; in another store, where an edge would hold nothing: " + ($there | join(", ")))]
    elif ($open | length) > 0 then
      [$p.id, "waiting", ($open | join(",")), "-", ("waits on " + ($open | join(", ")))]
    elif $adopted[$p.id] != null then
      [$p.id, "resolved", "-", "-", ("resolved: rule adopted in " + $adopted[$p.id])]
    elif ($f | length) > 0 then
      [$p.id, "resolved", "-", "-", ("resolved: follow-ups " + ($f | join(", ")) + " closed")]
    elif $buckets[$p.id] != null then
      [$p.id, "dismissed", "-", "-", $buckets[$p.id]]
    elif $until == null then
      [$p.id, "left", "-", "-", "no last_seen to date a deferral from"]
    elif $until > $now then
      [$p.id, "deferred", "-", ($until | strftime("%Y-%m-%d")),
       ("held on " + $hold + ": deferred " + ($days | tostring) + " days past its last evidence on "
        + $last[0:10] + "; a recurrence before then is judged on its next run")]
    else
      [$p.id, "deferred", "-", "+12h",
       ("held on " + $hold + ": its window of " + ($days | tostring) + " days past its last evidence on "
        + $last[0:10] + " has passed, so once this deferral ends, the first distiller run to judge every"
        + " pending observation dismisses it unless one is its recurrence")]
    end
  | @tsv') || { echo "migrate: the decisions could not be computed; nothing decided" >&2; exit 1; }

declare -A COUNT=()
while IFS=$'\t' read -r id outcome waits until reason; do
  [ -n "$id" ] || continue
  COUNT[$outcome]=$(( ${COUNT[$outcome]:-0} + 1 ))
  [ "$until" != "-" ] || until=""
  case "$reason" in
    "$outcome:"*) echo "$id $reason" ;;
    *)            echo "$id $outcome${until:+ until $until}: $reason" ;;
  esac
  [ -n "$APPLY" ] || continue
  case "$outcome" in
    waiting)
      for f in ${waits//,/ }; do
        gc bd --rig "$RIG" dep add "$id" "$f" --type=blocks >/dev/null 2>&1 || fail "$id: the blocks edge onto $f did not land"
      done ;;
    resolved|dismissed)
      if ! { gc bd --rig "$RIG" update "$id" --set-metadata gc.work_outcome=no-op >/dev/null 2>&1 \
             && gc bd --rig "$RIG" close "$id" --reason "$reason" >/dev/null 2>&1; }; then
        fail "$id: the close did not land"
      fi ;;
    deferred)
      gc bd --rig "$RIG" defer "$id" --until "$until" --reason "$reason" >/dev/null 2>&1 \
        || fail "$id: the deferral did not land" ;;
  esac
done <<< "$PLAN"

for o in waiting resolved dismissed deferred left; do
  printf '%s %s\n' "$o" "${COUNT[$o]:-0}"
done
[ -n "$APPLY" ] || echo "dry run: nothing written; pass --apply to write"
[ "$FAILED" -eq 0 ]
