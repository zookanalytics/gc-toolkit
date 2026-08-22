#!/usr/bin/env bash
# backfill-operator-origin — stamp `gc.origin=operator` on the subjects that were
# filed before the key existed (tk-2cyxo).
#
# WHY THERE IS ANYTHING TO BACKFILL. `gc-visit-open.sh` is the operator-origin
# intake front door, and until now it recorded that origin only as PROSE, appended
# to the subject's description:
#
#     Operator-origin intake, filed by `gc-visit-open` on 2026-08-22T03:42:21Z.
#
# Prose is a fine thing to show a human and a bad thing to select on, so the origin
# is now also a metadata key. This script carries the beads written before that
# change across, once, so the new key describes the whole population rather than
# only what was filed after it shipped.
#
# WHY THE MATCH IS ANCHORED, AND WHY THE REGEX LIVES HERE AND NOWHERE ELSE. The
# consumer of the key — assets/scripts/detect-parked-dispositions.sh — files a visit
# and spawns a conversation, so a false positive costs a session. Measured on this
# rig, 2026-08-22: `bd list --desc-contains "Operator-origin intake"` returns 13
# beads, and THREE of them merely discuss the sentence rather than carry it —
# tk-hgmob writes a different sentence that starts the same way ("Operator-origin
# intake tk-yps55; sitting held by …"), and tk-2cyxo and tk-4ojka QUOTE the source
# line while specifying this very change. A fourth (tk-6v7nm) carries a variant an
# agent typed by hand, which no pattern for the script's output should match.
#
# So `--desc-contains` is used only to NARROW the read, and the decision is made by
# an anchored line match requiring both parts a quotation does not reproduce: the
# backticked program name, and a machine-written ISO-8601 stamp. A bead the pattern
# refuses is not lost — it is simply not auto-stamped, and stamping one by hand is
# one `bd update`.
#
# NON-CLOSED BEADS ONLY, deliberately. A stamp is a `bd update` and every update
# bumps `updated_at`. detect-stalled-workflows.sh dates a workflow by the MAXIMUM
# updated_at over its members INCLUDING the closed ones, so backfilling a closed
# bead would read as that workflow having just moved and would silence a real stall
# for a window. The key is only ever read on live subjects, so there is nothing to
# buy for that risk.
#
# Idempotent: a bead that already carries `gc.origin` is left exactly as it is,
# whatever the value — this backfill establishes an origin, it never overrules one.
#
# Usage:
#   backfill-operator-origin.sh [--dry-run] [--rig <rig>]
#
# Exit codes: 0 = done (or nothing to do), 1 = a read or a write failed.
set -uo pipefail

PROG="backfill-operator-origin"

DRY_RUN=0
RIG_PIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --rig) RIG_PIN="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

bd_pinned() {
  if [ -n "$RIG_PIN" ]; then
    gc bd --rig "$RIG_PIN" "$@"
  else
    gc bd "$@"
  fi
}

# Control characters in a bead's notes break jq (tk-6kf6r).
scrub() { tr -d '\000-\010\013\014\016-\037'; }

# The one pattern, in one place. Anchored at both ends of a line.
# shellcheck disable=SC2016  # the backticks are LITERAL text in the bead's body,
# not a command substitution — single quotes are what keeps them literal
INTAKE_RE='^Operator-origin intake, filed by `[A-Za-z0-9_.-]+` on [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\.$'

CAND=$(bd_pinned list --desc-contains "Operator-origin intake" --status=open,in_progress,blocked,deferred,pinned,hooked \
  --brief --limit=0 --json 2>/dev/null)
if [ -z "$CAND" ] || ! printf '%s' "$CAND" | scrub | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "$PROG: the candidate listing did not return a readable array; nothing stamped" >&2
  exit 1
fi

IDS=$(printf '%s' "$CAND" | scrub | jq -r '.[] | select(((.metadata // {})["gc.origin"] // "") == "") | .id // empty' 2>/dev/null)
SKIPPED_HAVE=$(printf '%s' "$CAND" | scrub | jq -r '[.[] | select(((.metadata // {})["gc.origin"] // "") != "")] | length' 2>/dev/null)
[ -n "$SKIPPED_HAVE" ] || SKIPPED_HAVE=0

if [ -z "$IDS" ]; then
  echo "$PROG: nothing to stamp ($SKIPPED_HAVE already carry gc.origin)"
  exit 0
fi

stamped=0; refused=0; failed=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  DESC=$(bd_pinned show "$id" --json 2>/dev/null | scrub | jq -r 'if type == "array" then (.[0].description // "") else "" end' 2>/dev/null)
  if [ -z "$DESC" ]; then
    echo "$PROG: $id — description unreadable; not stamped" >&2
    failed=$((failed + 1)); continue
  fi
  # A here-string, never `printf ... | grep -q`: `grep -q` exits at its first match
  # and SIGPIPEs the writer, and pipefail promotes that 141 to the pipeline's status —
  # a MATCH read as a miss. It is a race on how much the writer flushed, so it hides
  # at small payloads and fires as descriptions grow, which is exactly the input here.
  if ! grep -qE "$INTAKE_RE" <<< "$DESC"; then
    # The narrowing read matched a bead that only DISCUSSES the intake line.
    echo "$PROG: $id — matched the substring but not the intake line itself; left alone"
    refused=$((refused + 1)); continue
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "$PROG: (dry-run) would stamp gc.origin=operator on $id"
    stamped=$((stamped + 1)); continue
  fi
  if ! bd_pinned update "$id" --set-metadata "gc.origin=operator" >/dev/null 2>&1; then
    echo "$PROG: $id — the stamp did not stick" >&2
    failed=$((failed + 1)); continue
  fi
  # Read it back: a --set-metadata that exits 0 and persists nothing is the failure
  # a migration must not report as done.
  GOT=$(bd_pinned show "$id" --json 2>/dev/null | scrub | jq -r 'if type == "array" then (.[0].metadata["gc.origin"] // "") else "" end' 2>/dev/null)
  if [ "$GOT" != "operator" ]; then
    echo "$PROG: $id — stamp exited 0 but read back as '${GOT:-empty}'" >&2
    failed=$((failed + 1)); continue
  fi
  echo "$PROG: stamped gc.origin=operator on $id"
  stamped=$((stamped + 1))
done <<< "$IDS"

MODE=""
[ "$DRY_RUN" -eq 1 ] && MODE="(dry-run) "
echo "$PROG: ${MODE}${stamped} stamped, $refused matched the substring but not the intake line, $SKIPPED_HAVE already had an origin, $failed failed"
[ "$failed" -eq 0 ] || exit 1
exit 0
