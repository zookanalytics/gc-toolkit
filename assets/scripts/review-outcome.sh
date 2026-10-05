#!/usr/bin/env bash
# review-outcome.sh — the WRITE side of a review lane's approve-outcome bead.
# lane-state.sh READS these beads to derive a lane's green; this writes them, so
# the validator can make a lane green or send it back to unreviewed without ever
# touching a stored check.<lane> marker.
#
# The approve backing is a first-class review-outcome bead, the same shape
# gate-ensure.sh files at dispatch and signoff.sh closes on an approve verdict —
# exactly what lane-state.sh's green derivation reads:
#
#   task_kind        review
#   anchor_bead      the gating anchor
#   check_name       the lane it backs (absent resolves to correctness, as elsewhere)
#   reviewed_oid     the head the validator ruled converged (a dispatch pin, read
#                    by no check as a claim about a commit)
#   signoff_verdict  approve
#   gc.outcome       recorded, or superseded once the validator retires it
#
# The two verbs are the two review-outcome writes the validator's third decision
# makes (specs/tk-ztapg/review-cycle-architecture.md, "The validator" and "What
# moves a lane backwards"):
#
#   back-lane       Rule "no further full review is warranted": ensure a closed,
#                   non-superseded approve backing exists for the lane, so it
#                   derives green once nothing else holds it. Idempotent — a lane
#                   already backed gets no second bead. The backing is filed
#                   closed with every stamp in a single write, and an outcome an
#                   earlier write left stamped but open is closed, not filed again.
#   supersede-lane  Rule "a fresh whole-diff review is warranted": stamp
#                   gc.outcome=superseded on the lane's standing review(s) — the
#                   approve backing(s) lane-state.sh reads for green, and any
#                   recorded request-changes verdict gate-ensure.sh's per-head bar
#                   reads — the same stamp signoff.sh writes to retire a review
#                   whose pin left the branch. The lane then owes a full review
#                   again, and the per-head bar lets the fresh one through at the
#                   unmoved head. A bare request-changes lane has no approve
#                   backing, so retiring only backings would leave its verdict
#                   standing and the bar blocking the re-review this rules for.
#   supersede-anchor  The anchor-wide form of supersede-lane, for a human
#                   feedback batch (check_name=human) the validator ruled has not
#                   converged. A batch rules the whole diff, so it supersedes the
#                   approve backing of EVERY lane the anchor's check_set declares —
#                   not the check_name=human pseudo-lane no check reader derives
#                   green from. This is what returns the real checks to unreviewed
#                   so a fresh whole-diff review is dispatched and holds the merge.
#
# A must-fix finding still open holds the lane at `fixing` and the merge on its
# `blocks` edge; this writes no finding and reads none. Backing a lane whose
# must-fix set is not yet closed is correct: the lane derives green only when
# those close, which the merge predicate and the board resolve, never this.
#
# Callers: the validator (formulas/mol-validate.toml). Exit 0 on success; 2 when
# the store would not read or a write did not read back.
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
warn() { echo "review-outcome: $*" >&2; }

ALL_STATUSES="open,in_progress,blocked,deferred,hooked,pinned,closed"

usage() {
  cat >&2 <<'USAGE'
usage:
  review-outcome.sh back-lane --anchor <id> --lane <lane> --oid <oid> [--batch <id>] [--reason <r>]
  review-outcome.sh supersede-lane --anchor <id> --lane <lane> [--reason <r>]
  review-outcome.sh supersede-anchor --anchor <id> [--reason <r>]
USAGE
}

# The closed review beads that currently back this lane green — the approve half
# lane-state.sh reads, minus its in-flight test: a closed task_kind=review bead
# for (anchor, lane) carrying reviewed_oid, either signoff_verdict=approve and
# not superseded, or a legacy no-verdict gc.outcome=recorded. Ids on stdout, one
# per line; exit 2 when the store would not read so a caller never mistakes an
# unreadable store for "nothing backs the lane".
backing_ids() { # <anchor> <lane>
  local anchor="$1" lane="$2" rows
  rows=$(gc bd list --metadata-field anchor_bead="$anchor" --status="$ALL_STATUSES" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$rows" | jq -r --arg lane "$lane" '
    [ .[] | (.metadata // {}) as $m
          | select((($m.task_kind // "") | tostring) == "review")
          | select(((($m.check_name // "") | tostring) | if . == "" then "correctness" else . end) == $lane)
          | select(((.status // "") | tostring | ascii_downcase) == "closed")
          | select((($m.reviewed_oid // "") | tostring) != "")
          | (($m.signoff_verdict // "") | tostring) as $sv
          | (($m["gc.outcome"] // "") | tostring) as $oc
          | select(($sv == "approve" and $oc != "superseded") or ($sv == "" and $oc == "recorded")) ]
    | .[].id' 2>/dev/null
}

# Close every approve outcome back-lane filed for this lane that is stamped but
# still open, so it becomes the backing it was filed to be. lane-state.sh reads
# an open review for the lane as one in flight and holds the lane out of green
# while it stays open, and backing_ids reads closed beads only, so a retry that
# deduped against backings alone would file a twin and leave this one holding
# the lane. The match is back-lane's own shape: its exact title on this anchor
# and lane, carrying reviewed_oid, signoff_verdict=approve and
# gc.outcome=recorded. signoff.sh writes a reviewer's verdict in the update that
# closes the review, so an open approve under any other title is not this
# writer's to close. Returns 2 when the store would not read or a close was
# refused.
finish_stranded() { # <anchor> <lane> <title>
  local anchor="$1" lane="$2" title="$3" rows ids id
  rows=$(gc bd list --metadata-field anchor_bead="$anchor" --status="$ALL_STATUSES" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { warn "could not read review outcomes on $anchor to find an open $lane approve outcome"; return 2; }
  ids=$(printf '%s' "$rows" | jq -r --arg lane "$lane" --arg title "$title" '
    [ .[] | (.metadata // {}) as $m
          | select(((.status // "") | tostring | ascii_downcase) != "closed")
          | select(((.title // "") | tostring) == $title)
          | select((($m.task_kind // "") | tostring) == "review")
          | select(((($m.check_name // "") | tostring) | if . == "" then "correctness" else . end) == $lane)
          | select((($m.reviewed_oid // "") | tostring) != "")
          | select((($m.signoff_verdict // "") | tostring) == "approve")
          | select((($m["gc.outcome"] // "") | tostring) == "recorded") ]
    | .[].id' 2>/dev/null)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    gc bd update "$id" --status=closed \
      --append-notes "validator: closed this $lane approve outcome, which an earlier write left open" >/dev/null 2>&1 \
      || { warn "could not close the open approve outcome $id for lane $lane on $anchor"; return 2; }
  done <<EOF
$ids
EOF
}

# The closed reviews a supersede must retire — a strict superset of the backings
# above. It keeps every approve backing (so superseding still un-greens the lane)
# and adds any recorded verdict: gate-ensure.sh's per-head bar reads
# gc.outcome=recorded at the head, so a bare request-changes lane, which has no
# approve backing, would otherwise keep its verdict standing and the bar blocking
# the re-review the validator ruled for. Retiring it stamps the superseded state
# the bar already excludes. Ids on stdout, one per line; exit 2 when the store
# would not read so a caller never mistakes an unreadable store for "nothing stands".
superseding_review_ids() { # <anchor> <lane>
  local anchor="$1" lane="$2" rows
  rows=$(gc bd list --metadata-field anchor_bead="$anchor" --status="$ALL_STATUSES" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$rows" | jq -r --arg lane "$lane" '
    [ .[] | (.metadata // {}) as $m
          | select((($m.task_kind // "") | tostring) == "review")
          | select(((($m.check_name // "") | tostring) | if . == "" then "codex" else . end) == $lane)
          | select(((.status // "") | tostring | ascii_downcase) == "closed")
          | (($m.signoff_verdict // "") | tostring) as $sv
          | (($m["gc.outcome"] // "") | tostring) as $oc
          | select(($sv == "approve" and $oc != "superseded") or ($oc == "recorded")) ]
    | .[].id' 2>/dev/null
}

# Supersede every live review standing for one lane — the write that returns the
# lane to unreviewed and lifts the per-head bar. Echoes the count retired on
# success; returns 2 (fail closed) when the store would not read, a supersede
# write is refused, or a review still reads live afterward. The note is passed in
# so the per-lane and anchor-wide callers each phrase their own reason. Shared by
# supersede-lane and supersede-anchor so the two cannot drift on what "retire the
# lane's standing review" means.
supersede_lane_reviews() { # <anchor> <lane> <note>
  local anchor="$1" lane="$2" note="$3" ids rc id n=0 still
  ids=$(superseding_review_ids "$anchor" "$lane"); rc=$?
  [ "$rc" -eq 2 ] && { warn "could not read reviews on $anchor; nothing superseded"; return 2; }
  # Nothing stands for the lane: it already owes a fresh review, so there is
  # nothing to retire. Report the no-op and succeed — the validator's intent
  # already holds.
  [ -n "$ids" ] || { echo 0; return 0; }
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    gc bd update "$id" --set-metadata gc.outcome=superseded --append-notes "$note" >/dev/null 2>&1 \
      || { warn "could not supersede review $id on lane $lane"; return 2; }
    n=$((n + 1))
  done <<EOF
$ids
EOF
  # Prove the supersede landed: a review that still reads live would leave the
  # lane green (an approve backing) or the per-head bar armed (a recorded
  # request-changes verdict) when the validator ruled it must be re-reviewed.
  still=$(superseding_review_ids "$anchor" "$lane") || { warn "could not read back the $lane reviews after supersede"; return 2; }
  [ -z "$still" ] || { warn "lane $lane still has a live review after supersede: $still"; return 2; }
  echo "$n"
}

cmd_back_lane() {
  local anchor="" lane="" oid="" batch="" reason=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --oid) oid="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --batch) batch="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] && [ -n "$lane" ] && [ -n "$oid" ] \
    || { warn "back-lane needs --anchor, --lane, --oid"; exit 1; }

  local title desc note
  title="lane $lane converged: validator ruled no further review — anchor $anchor"
  desc=$(printf 'The validator ruled lane %s converged on anchor %s at %s: no further whole-diff review is warranted. This closed approve outcome is what lane-state.sh reads to derive green once nothing else holds the lane. The reviewed_oid is a dispatch pin, not a claim that green is bound to that commit.%s' \
    "$lane" "$anchor" "$oid" "${batch:+ Batch: $batch.}")
  note="validator: lane $lane converged at $oid"
  [ -n "$reason" ] && note="$note — $reason"

  # An outcome an earlier write left stamped but open holds the lane in flight,
  # and a fresh one filed beside it would be its twin, so it is finished first.
  finish_stranded "$anchor" "$lane" "$title" || exit 2

  # Idempotent: a lane already backed by a live approve outcome earns no second
  # bead — a push does not stale a backing, so re-ruling convergence at a new
  # head is a no-op, not a new record.
  local existing rc
  existing=$(backing_ids "$anchor" "$lane"); rc=$?
  if [ "$rc" -eq 2 ]; then
    warn "could not read review outcomes on $anchor to dedup the $lane backing; nothing filed"
    exit 2
  fi
  if [ -n "$existing" ]; then
    printf '%s\n' "$existing" | head -n1
    return 0
  fi

  # Atomic birth: the outcome is created closed, carrying every stamp
  # lane-state.sh keys on and the note, in one write. A refused create leaves
  # nothing behind, and a create whose reply is lost has still filed a whole
  # backing, so no attempt leaves a bare bead that a retry cannot find.
  local meta id
  meta=$(jq -nc --arg ab "$anchor" --arg ln "$lane" --arg oid "$oid" \
    '{task_kind: "review", anchor_bead: $ab, check_name: $ln, reviewed_oid: $oid,
      signoff_verdict: "approve", "gc.outcome": "recorded"}' 2>/dev/null)
  [ -n "$meta" ] || { warn "could not compose the approve outcome for lane $lane on $anchor"; exit 2; }
  id=$(gc bd create "$title" -t task -d "$desc" --metadata "$meta" --status=closed --notes "$note" --json 2>/dev/null \
    | scrub | jq -r '.id // .[0].id // empty' 2>/dev/null)

  # Read back the shape lane-state.sh keys on: a bead that did not close, or lost
  # a metadata key, would leave the lane silently ungreen.
  local got
  got=$(backing_ids "$anchor" "$lane") || { warn "could not read back the $lane backing on $anchor"; exit 2; }
  [ -n "$got" ] || { warn "the approve outcome for lane $lane on $anchor did not land${id:+ ($id)}: nothing reads back as a backing"; exit 2; }
  # The read, not the reply, says what landed. A reply that would not parse loses
  # only the id, so the backing the read found is reported in its place.
  if [ -z "$id" ]; then
    printf '%s\n' "$got" | head -n1
    return 0
  fi
  case " $(printf '%s' "$got" | tr '\n' ' ') " in
    *" $id "*) printf '%s\n' "$id" ;;
    *) warn "approve outcome $id did not read back as a $lane backing (got '$got')"; exit 2 ;;
  esac
}

cmd_supersede_lane() {
  local anchor="" lane="" reason=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] && [ -n "$lane" ] || { warn "supersede-lane needs --anchor and --lane"; exit 1; }

  local note="validator: superseded — a fresh whole-diff review is warranted"
  [ -n "$reason" ] && note="validator: superseded — $reason"
  local n
  n=$(supersede_lane_reviews "$anchor" "$lane" "$note") || exit 2
  echo "$n"
}

cmd_supersede_anchor() {
  local anchor="" reason=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reason) reason="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "supersede-anchor needs --anchor"; exit 1; }

  # A human feedback batch rules the whole diff, so its non-convergence returns
  # every lane the anchor's check_set declares to unreviewed. The lanes are read
  # from the anchor here rather than passed in: the pass carries check_name=human,
  # a pseudo-lane no check_set names, and superseding it moves nothing a check
  # reader derives green from. Fail closed if the anchor or its check_set will not
  # read — a silent no-op here leaves the merge open on a review the validator
  # required.
  local arow checkset
  arow=$(gc bd show "$anchor" --json 2>/dev/null | scrub)
  printf '%s' "$arow" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { warn "could not read anchor $anchor to resolve its check_set; nothing superseded"; exit 2; }
  checkset=$(printf '%s' "$arow" | jq -r '.[0].metadata.check_set // empty' 2>/dev/null)
  [ -n "$checkset" ] \
    || { warn "anchor $anchor declares no check_set; refusing to treat that as no gating lane"; exit 2; }

  # Drop the non-lane check_set tokens, the same list merge.sh and pr-open.sh
  # apply: none/off is checkless by choice and approval is met by a GitHub review,
  # not a lane derivation. A check_set naming only those has no lane to move, so a
  # deliberately checkless anchor is a zero no-op, not an error.
  local lanes
  lanes=$(printf '%s' "$checkset" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d' | grep -Eiv '^(none|off|approval)$')
  [ -n "$lanes" ] || { echo 0; return 0; }

  local note="validator: superseded (anchor-wide human batch) — a fresh whole-diff review is warranted"
  [ -n "$reason" ] && note="validator: superseded (anchor-wide human batch) — $reason"
  local lane total=0 c
  while IFS= read -r lane; do
    [ -n "$lane" ] || continue
    c=$(supersede_lane_reviews "$anchor" "$lane" "$note") || exit 2
    total=$((total + c))
  done <<EOF
$lanes
EOF
  echo "$total"
}

[ $# -ge 1 ] || { usage; exit 1; }
VERB="$1"; shift
case "$VERB" in
  back-lane)        cmd_back_lane "$@" ;;
  supersede-lane)   cmd_supersede_lane "$@" ;;
  supersede-anchor) cmd_supersede_anchor "$@" ;;
  *) warn "unknown verb '$VERB'"; usage; exit 1 ;;
esac
