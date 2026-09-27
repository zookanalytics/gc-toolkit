#!/usr/bin/env bash
# backfill-visit-outcomes — stamp gc.outcome on legacy closed visits that
# predate outcome recording, so the board can report them and
# doctor/check-visit-outcome-recorded goes quiet.
# DISPOSABLE: delete this script, its test, and specs/tk-sht9nq/ once every
# store reads clean and the operator has ratified the outcome word.
#
# Scope is the exact set doctor/check-visit-outcome-recorded flags: a bead with
# task_kind=visit, status=closed, and an empty or absent gc.outcome. Every
# going-forward close path already stamps the outcome — visit-close.sh, the
# gc-helm dismiss inline copy, and pr-facts.sh's atomic retire-close — so this
# finds only the standing legacy backlog, and a second --apply run finds none.
#
# The stamp is two keys the board reads (services/helm/internal/source/facts.go):
#   gc.outcome        the one-word class, default "unrecorded" — these closes
#                     never recorded a disposition, so the word states that
#                     rather than inventing moot/benign/folded.
#   gc.outcome_reason the bead's own close_reason, which carries the disposition
#                     its closer wrote and the board renders as the HEADLINE. A
#                     visit whose close_reason is empty gets a factual fallback.
#
# DEFAULT IS DRY-RUN: reports what it would stamp, per store. --apply writes,
# reads both keys back, and counts a visit done only when they read back. A
# metadata write bypasses bd's close-authority guard, so an already-closed
# visit takes the stamp.
#
# Usage: backfill-visit-outcomes.sh [--apply] [--rig <name>] [--db <path>]
#          [--outcome <word>]
#   --apply     write; without it, report only.
#   --rig       limit to one rig by name (default: every non-suspended rig).
#   --db        stamp one explicit .beads store, bypassing rig discovery.
#   --outcome   the word to stamp (default: unrecorded).
# Exit: 0 = clean (dry-run listed, or --apply stamped and every write read
#       back); 1 = a store was unreadable or a write did not read back.
set -u

APPLY=0; RIG_FILTER=""; DB_OVERRIDE=""; OUTCOME="unrecorded"
PROG="backfill-visit-outcomes"
die() { echo "$PROG: $1" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)   APPLY=1 ;;
    --rig)     shift; [ $# -gt 0 ] || die "--rig needs a value"; RIG_FILTER="$1" ;;
    --db)      shift; [ $# -gt 0 ] || die "--db needs a value"; DB_OVERRIDE="$1" ;;
    --outcome) shift; [ $# -gt 0 ] || die "--outcome needs a value"; OUTCOME="$1" ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown argument '$1'" ;;
  esac
  shift
done
[ -n "$OUTCOME" ] || die "--outcome cannot be empty"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v gc >/dev/null 2>&1 || die "gc is required"

BOUND="${GC_BACKFILL_TIMEOUT:-60}"
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# Read both stamped keys in one show, US-separated. The reason never carries a
# US byte: it was built through gsub("[[:cntrl:]]";" ") or a plain fallback.
read_both() { # <db> <bead> -> "<gc.outcome>\u001f<gc.outcome_reason>"
  run_bounded gc bd show "$2" --db "$1" --json 2>/dev/null | scrub \
    | jq -r 'if type=="array" then ((.[0].metadata["gc.outcome"] // "") + "\u001f" + (.[0].metadata["gc.outcome_reason"] // "")) else "\u001f" end' 2>/dev/null
}

# Resolve the stores to scan: an explicit --db, else every non-suspended rig.
# Emit "<label>\u001f<db-path>" rows.
stores() {
  if [ -n "$DB_OVERRIDE" ]; then
    printf '%s\u001f%s\n' "override" "$DB_OVERRIDE"
    return 0
  fi
  run_bounded gc rig list --json 2>/dev/null | scrub | jq -r --arg f "$RIG_FILTER" '
    .rigs[]? | select((.path // "") != "")
    | select(($f == "") or (.name == $f))
    | select((.suspended // false) == false)
    | [ (.name // "<city>"), (.path + "/.beads") ] | join("\u001f")'
}

total_found=0; total_done=0; total_fail=0; unreadable=0; scanned=0
mapfile -t STORE_ROWS < <(stores)
if [ "${#STORE_ROWS[@]}" -eq 0 ]; then
  die "no stores to scan (rig list failed, or --rig '$RIG_FILTER' matched none, or every rig is suspended)"
fi

for row in "${STORE_ROWS[@]}"; do
  IFS=$'\037' read -r label db <<< "$row"
  [ -n "$db" ] || continue
  raw=$(run_bounded gc bd list --db "$db" --all \
    --has-metadata-key task_kind --include-gates --include-infra --include-templates \
    --json --limit 0 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
    echo "$label: could NOT list beads in $db (rc=$rc) — this store was not backfilled" >&2
    unreadable=$((unreadable + 1)); continue
  fi
  # The miss set: task_kind=visit, closed, empty gc.outcome. Emit id + the
  # close_reason to reuse as the outcome reason (control chars flattened).
  rows=$(printf '%s' "$raw" | scrub | jq -r '
    .[]? | select(((.metadata.task_kind // "") | tostring) == "visit")
         | select(((.status // "") | tostring) == "closed")
         | select(((.metadata["gc.outcome"] // "") | tostring) == "")
         | ((.id // "") | tostring | gsub("[[:cntrl:]]"; " "))
           + "\u001f" + ((.close_reason // "") | tostring | gsub("[[:cntrl:]]"; " "))')
  if [ $? -ne 0 ]; then
    echo "$label: the visit listing from $db could not be parsed — this store was not backfilled" >&2
    unreadable=$((unreadable + 1)); continue
  fi
  scanned=$((scanned + 1))
  [ -n "$rows" ] || { echo "$label: clean (no outcome-less closed visits)"; continue; }

  store_found=0; store_done=0; store_fail=0
  while IFS=$'\037' read -r id close_reason; do
    [ -n "$id" ] || continue
    store_found=$((store_found + 1)); total_found=$((total_found + 1))
    reason="$close_reason"
    [ -n "$reason" ] || reason="closed with no recorded close_reason"
    if [ "$APPLY" -eq 0 ]; then
      echo "  would stamp $id: gc.outcome=$OUTCOME  gc.outcome_reason=\"${reason:0:100}\""
      continue
    fi
    run_bounded gc bd update "$id" --db "$db" \
      --set-metadata "gc.outcome=$OUTCOME" --set-metadata "gc.outcome_reason=$reason" >/dev/null 2>&1 || true
    IFS=$'\037' read -r got_o got_r <<< "$(read_both "$db" "$id")"
    if [ "$got_o" != "$OUTCOME" ] || [ "$got_r" != "$reason" ]; then
      run_bounded gc bd update "$id" --db "$db" \
        --set-metadata "gc.outcome=$OUTCOME" --set-metadata "gc.outcome_reason=$reason" >/dev/null 2>&1 || true
      IFS=$'\037' read -r got_o got_r <<< "$(read_both "$db" "$id")"
    fi
    if [ "$got_o" = "$OUTCOME" ] && [ "$got_r" = "$reason" ]; then
      store_done=$((store_done + 1)); total_done=$((total_done + 1))
    else
      echo "  $id: stamp did NOT read back (gc.outcome='$got_o', gc.outcome_reason did not match) — re-run" >&2
      store_fail=$((store_fail + 1)); total_fail=$((total_fail + 1))
    fi
  done <<< "$rows"

  if [ "$APPLY" -eq 0 ]; then
    echo "$label: $store_found outcome-less closed visit(s) would be stamped"
  else
    echo "$label: stamped $store_done/$store_found (failed $store_fail)"
  fi
done

echo
if [ "$APPLY" -eq 0 ]; then
  echo "DRY-RUN: $total_found outcome-less closed visit(s) across $scanned store(s) would be stamped gc.outcome=$OUTCOME. Re-run with --apply to write."
else
  echo "APPLIED: stamped $total_done/$total_found across $scanned store(s); $total_fail failed read-back."
fi
[ "$unreadable" -eq 0 ] || echo "WARNING: $unreadable store(s) were unreadable and not backfilled." >&2
if [ "$unreadable" -ne 0 ] || [ "$total_fail" -ne 0 ]; then exit 1; fi
exit 0
