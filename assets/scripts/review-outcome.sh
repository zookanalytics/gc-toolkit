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
#   check_name       the lane it backs (absent resolves to codex, as elsewhere)
#   reviewed_oid     the head the validator ruled converged (a dispatch pin, read
#                    by no gate as a claim about a commit)
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
#                   already backed gets no second bead.
#   supersede-lane  Rule "a fresh whole-diff review is warranted": stamp
#                   gc.outcome=superseded on the lane's approve backing(s), the
#                   same stamp signoff.sh writes to retire a review whose pin left
#                   the branch, so the approve half no longer holds and the lane
#                   owes a full review again.
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
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
warn() { echo "review-outcome: $*" >&2; }

ALL_STATUSES="open,in_progress,blocked,deferred,hooked,pinned,closed"

usage() {
  cat >&2 <<'USAGE'
usage:
  review-outcome.sh back-lane --anchor <id> --lane <lane> --oid <oid> [--batch <id>] [--reason <r>]
  review-outcome.sh supersede-lane --anchor <id> --lane <lane> [--reason <r>]
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
          | select(((($m.check_name // "") | tostring) | if . == "" then "codex" else . end) == $lane)
          | select(((.status // "") | tostring | ascii_downcase) == "closed")
          | select((($m.reviewed_oid // "") | tostring) != "")
          | (($m.signoff_verdict // "") | tostring) as $sv
          | (($m["gc.outcome"] // "") | tostring) as $oc
          | select(($sv == "approve" and $oc != "superseded") or ($sv == "" and $oc == "recorded")) ]
    | .[].id' 2>/dev/null
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

  local title desc id
  title="lane $lane converged: validator ruled no further review — anchor $anchor"
  desc=$(printf 'The validator ruled lane %s converged on anchor %s at %s: no further whole-diff review is warranted. This closed approve outcome is what lane-state.sh reads to derive green once nothing else holds the lane. The reviewed_oid is a dispatch pin, not a claim that green is bound to that commit.%s' \
    "$lane" "$anchor" "$oid" "${batch:+ Batch: $batch.}")
  id=$(gc bd create "$title" -t task -d "$desc" --json 2>/dev/null | jq -r '.id // .[0].id // empty' 2>/dev/null)
  [ -n "$id" ] || { warn "could not create the approve outcome bead for lane $lane on $anchor"; exit 2; }
  local note="validator: lane $lane converged at $oid"
  [ -n "$reason" ] && note="$note — $reason"
  gc bd update "$id" \
    --set-metadata task_kind=review \
    --set-metadata anchor_bead="$anchor" \
    --set-metadata check_name="$lane" \
    --set-metadata reviewed_oid="$oid" \
    --set-metadata signoff_verdict=approve \
    --set-metadata gc.outcome=recorded \
    --status=closed --append-notes "$note" >/dev/null 2>&1 \
    || { warn "could not stamp/close the approve outcome bead $id for lane $lane"; exit 2; }
  # Read back the shape lane-state.sh keys on: a bead that did not close, or lost
  # a metadata key, would leave the lane silently ungreen.
  local got
  got=$(backing_ids "$anchor" "$lane") || { warn "approve outcome $id did not read back as a $lane backing"; exit 2; }
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

  local ids rc
  ids=$(backing_ids "$anchor" "$lane"); rc=$?
  if [ "$rc" -eq 2 ]; then
    warn "could not read review outcomes on $anchor; nothing superseded"
    exit 2
  fi
  # Nothing backs the lane: it is already not green, so there is nothing to
  # retire. Report the no-op and succeed — the validator's intent (the lane owes
  # a fresh review) already holds.
  [ -n "$ids" ] || { echo 0; return 0; }
  local note="validator: superseded — a fresh whole-diff review is warranted"
  [ -n "$reason" ] && note="validator: superseded — $reason"
  local id n=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    gc bd update "$id" --set-metadata gc.outcome=superseded --append-notes "$note" >/dev/null 2>&1 \
      || { warn "could not supersede approve outcome $id on lane $lane"; exit 2; }
    n=$((n + 1))
  done <<EOF
$ids
EOF
  # Prove the supersede landed: a backing that still reads as live would leave the
  # lane green when the validator ruled it must be re-reviewed.
  local still
  still=$(backing_ids "$anchor" "$lane") || { warn "could not read back the $lane backing after supersede"; exit 2; }
  [ -z "$still" ] || { warn "lane $lane still has a live approve backing after supersede: $still"; exit 2; }
  echo "$n"
}

[ $# -ge 1 ] || { usage; exit 1; }
VERB="$1"; shift
case "$VERB" in
  back-lane)       cmd_back_lane "$@" ;;
  supersede-lane)  cmd_supersede_lane "$@" ;;
  *) warn "unknown verb '$VERB'"; usage; exit 1 ;;
esac
