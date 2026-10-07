#!/usr/bin/env bash
# merge-tail-report.sh — file a durable finding when the PREVIOUS refinery-reconcile
# pass ended without completing its merge decision, leaving gating anchors
# unmerged with no reason on the board.
#
# refinery-reconcile stamps a per-pass merge-decision marker as it runs: `started`
# before the arms, `reached` just before the merge arm, then `decided` once merge
# returns — or `held`, which is a recorded decision (a same-pass interlock held
# merge), not a drop. A pass the controller kills at its budget runs no at-exit
# code, but the phase it wrote before the kill survives. This reads that marker at
# the NEXT pass's start — the driver calls it holding the pass lock, so the pass
# that wrote the marker is already dead — and when the marker never reached
# `decided`/`held` while gating anchors are still open, files one deduped
# patrol-finding naming them. That finding is the board-visible trace a silent
# skip left nothing of: fully-green approved anchors passed over with no reason,
# indistinguishable from a healthy wait.
#
# It keys on the pass failing to finish its merge decision, never on how long an
# anchor has waited: it stays silent while CI legitimately runs long and fires
# only when a pass actually dropped its tail. It self-clears — it names only
# anchors open right now, so a tail the next pass lands leaves nothing to name.
#
#   merge-tail-report.sh --marker <path> --rig <rig>
#
# Caller: assets/scripts/refinery-reconcile.sh (pass start, under the pass lock).
# Exit: always 0 — a reporting helper must never fail the pass it reports on.
set -uo pipefail

PROG="merge-tail-report"
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PATROL_FINDING="${GC_PATROL_FINDING_TOOL:-$HERE/patrol-finding.sh}"

# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 0; }

# One anchor per line is legible; a runaway tail is capped so the finding body
# stays a bead, not a dump. The count in the title is always the true total.
LIST_CAP="${MERGE_TAIL_REPORT_LIST_CAP:-20}"
case "$LIST_CAP" in ''|*[!0-9]*) LIST_CAP=20 ;; esac

MARKER=""; RIG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --marker) MARKER="${2:-}"; shift 2 ;;
    --rig)    RIG="${2:-}"; shift 2 ;;
    *) echo "$PROG: unknown argument: $1" >&2; shift ;;
  esac
done

[ -n "$MARKER" ] || { echo "$PROG: --marker is required" >&2; exit 0; }
# No marker file means no prior pass wrote one (first pass ever, or a state dir
# that was never writable). Nothing prior to judge.
[ -f "$MARKER" ] || exit 0

# The marker is one TSV line the driver writes atomically: <phase> <tick> <head>.
# `|| true` keeps the fields a read at a newline-less EOF still populated; the
# phase case below is what decides, and an empty phase falls through to no-op.
phase=""; tick=""; head=""
{ IFS=$'\t' read -r phase tick head; } < "$MARKER" 2>/dev/null || true
case "$phase" in
  decided|held) exit 0 ;;   # the prior pass reached its merge decision and made it
  started|reached) ;;       # reached the arms / the merge arm but never decided — a candidate drop
  *) exit 0 ;;              # empty or unrecognized — nothing to assert
esac

# The prior pass never recorded a completed merge decision. Name the gating
# anchors still open now — the same set merge.sh enumerates (open anchors carrying
# merge_result=pull_request). A read that fails is not proof the tail is empty, so
# it does not file; an empty tail means the drop self-cleared (the next pass, or a
# merge that completed after the marker's last write, landed them) — nothing to
# report either way.
anchors_json=$(bd_list --status=open --metadata-field merge_result=pull_request) || {
  echo "$PROG: could not enumerate gating anchors for rig ${RIG:-?}; not filing (a failed read is not proof the tail is empty)" >&2
  exit 0
}
count=$(printf '%s' "$anchors_json" | jq -r 'length' 2>/dev/null)
case "$count" in ''|*[!0-9]*) count=0 ;; esac
[ "$count" -gt 0 ] || exit 0

detail=$(printf '%s' "$anchors_json" | jq -r --argjson cap "$LIST_CAP" '
  [ .[] | "  - \(.id // "?")  PR#\((.metadata // {}).pr_number // "?")  posture=\((.metadata // {}).pr_posture // "none")" ] as $lines
  | ($lines[:$cap][]),
    (if ($lines | length) > $cap
       then "  - (+\(($lines | length) - $cap) more not shown)"
       else empty end)
' 2>/dev/null)
[ -n "$detail" ] || detail="  - (anchor list could not be rendered; $count open anchor(s) carry merge_result=pull_request)"

case "$phase" in
  started) when="was killed before it reached the merge arm" ;;
  reached) when="was killed inside the merge arm, before it finished deciding its candidates" ;;
esac

TITLE="refinery-reconcile dropped its merge tail: $count approved-candidate anchor(s) left unmerged${RIG:+ (rig $RIG)}"

MESSAGE="The reconcile pass that started at ${tick:-an unrecorded time} (rig ${RIG:-?}, head ${head:-unknown}) $when, so its merge decision never completed (marker phase '$phase', never 'decided').

These open anchors carry merge_result=pull_request — the merge candidates that pass would have decided — and were left unmerged with no reason on the board. The pass did not hold them (a hold is recorded as such); it stopped before reaching them:

$detail

This is not a wait keyed on elapsed time: it fires because a pass failed to finish its merge decision, not because an anchor waited, so slow-but-legitimate CI never trips it. If these are approved and clean, the next pass should land them and this finding stops recurring — it names only anchors still open. A finding that keeps recurring means the merge arm is being starved before it can decide its tail, the failure mode that leaves approved-clean PRs unmerged for hours, and the pass structure needs the arm-ordering/budget treatment its root cause calls for."

if [ ! -x "$PATROL_FINDING" ]; then
  echo "$PROG: cannot find patrol-finding.sh (looked at $PATROL_FINDING); the dropped merge tail for rig ${RIG:-?} went unrecorded ($count anchor(s))" >&2
  exit 0
fi

key_rig=$(printf '%s' "${RIG:-unknown}" | tr -c 'A-Za-z0-9._-' '-')
KEY="reconcile-merge-tail-dropped-$key_rig"

pf_args=(--key "$KEY" --title "$TITLE" --message "$MESSAGE"
         --scope refinery-findings --type bug --priority 1)
[ -n "$RIG" ] && pf_args+=(--rig "$RIG")

"$PATROL_FINDING" "${pf_args[@]}" \
  || echo "$PROG: patrol-finding.sh did not record the dropped merge tail for rig ${RIG:-?}; it will be retried next pass" >&2

exit 0
