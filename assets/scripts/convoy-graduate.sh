#!/usr/bin/env bash
# convoy-graduate — arm 5 of the merge cadence: graduate a complete OWNED
# integration convoy into an ordinary mr-mode work bead for the refinery.
# Conditions, all fail-closed: owned convoy targeting integration/*, all
# members closed, at least one bead in the ledger records a MERGE onto that
# branch (merged_target=<branch> + merge_result=merged — "all closed" alone is
# vacuously true for a convoy whose members landed nothing), no merge_hold /
# rebase_hold on the convoy bead or on any live bead naming the branch, and no
# live bead already owning the branch. Then: assignee=$GC_AGENT (the refinery),
# branch=<integration branch>, target=$TARGET, merge_strategy=mr,
# graduation=true. Idempotent via the convoy bead's own metadata.branch.
# Args: --target <branch> (default main). Caller: refinery-reconcile.sh with
# GC_AGENT projected; an unreadable probe skips (retry next pass), never acts.
set -u

PROG="convoy-graduate"
scrub() { tr -d '\000-\010\013\014\016-\037'; }

TARGET_BRANCH="main"
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET_BRANCH="${2:-main}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
    *) shift ;;
  esac
done

# Graduation assigns the convoy bead; without an identity it would strand at
# assignee="". Skip rather than strand.
if [ -z "${GC_AGENT:-}" ]; then
  echo "$PROG: GC_AGENT unset; skip" >&2
  exit 0
fi

# Every non-closed status still owns its branch (a blocked/hooked/pinned bead
# is parked, not gone); closed alone releases it.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
ALL_STATUSES="$LIVE_STATUSES,closed"

is_held() { case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac; }

# Guarded reads: non-zero = "I cannot tell", never "there is nothing there" —
# an error object on stdout with rc=0 must not read as an empty result.
bd_list() {
  local raw rc
  raw=$(gc bd list ${GC_RIG:+--rig="$GC_RIG"} "$@" --limit=0 --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
convoy_meta() { # <id> -> {hold, rhold, branch}; non-zero = unreadable
  local raw rc out
  raw=$(gc bd show "$1" ${GC_RIG:+--rig="$GC_RIG"} --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || return 1
  out=$(printf '%s' "$raw" | jq -c '.[0] | {hold: (.metadata.merge_hold // ""),
    rhold: (.metadata.rebase_hold // ""), branch: (.metadata.branch // "")}' 2>/dev/null) || return 1
  printf '%s\n' "$out"
}

# Owned-ness + member completion live only in `gc convoy list` (city-wide;
# intersected with this rig's convoy ledger below).
CONVOYS=$(gc convoy list --json 2>/dev/null)
[ -n "$CONVOYS" ] || { echo "$PROG: convoy list unavailable"; exit 0; }
CANDS=$(printf '%s' "$CONVOYS" | scrub | jq -r '
  .convoys[]?
  | select((.fields.target // "") | startswith("integration/"))
  | select(.progress.total > 0 and .progress.closed == .progress.total)
  | select(.owned == true)
  | "\(.id)\t\(.fields.target)"' 2>/dev/null)
[ -n "$CANDS" ] || { echo "$PROG: no complete owned integration convoys"; exit 0; }

RIG_CONVOYS=$(gc bd list ${GC_RIG:+--rig="$GC_RIG"} --type=convoy --status=open \
  --limit=0 --json 2>/dev/null | scrub | jq -r '.[].id' 2>/dev/null)

graduated=0; skipped=0; held=0; vacuous=0
while IFS="$(printf '\t')" read -r cid ctarget; do
  [ -n "${cid:-}" ] || continue
  # -F, here-string: convoy ids contain dots, and grep -q in a pipe SIGPIPEs.
  grep -qxF -- "$cid" <<< "$RIG_CONVOYS" || { skipped=$((skipped + 1)); continue; }

  if ! cmeta=$(convoy_meta "$cid"); then
    echo "$PROG: $cid — convoy bead read failed; not graduated (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  # Operator gate (a): a hold on the convoy bead itself. Graduation causes both
  # a rebase and a landing, so either marker vetoes.
  if is_held "$(printf '%s' "$cmeta" | jq -r '.hold')" \
     || is_held "$(printf '%s' "$cmeta" | jq -r '.rhold')"; then
    echo "$PROG: $cid — merge_hold/rebase_hold set on the convoy (operator gate); not graduated"
    held=$((held + 1)); continue
  fi
  # Idempotency: metadata.branch on the convoy bead means "already initiated".
  if [ -n "$(printf '%s' "$cmeta" | jq -r '.branch')" ]; then
    skipped=$((skipped + 1)); continue
  fi

  # Operator gate (b): who else is on this branch? The hold commonly lives on a
  # SEPARATE bead naming the branch; a live unheld owner means a graduation is
  # already in flight and a second assignment would duplicate its PR.
  if ! probe=$(bd_list --metadata-field "branch=$ctarget" --status "$LIVE_STATUSES"); then
    echo "$PROG: $cid — branch probe on '$ctarget' failed; not graduated (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  frozen=$(printf '%s' "$probe" | jq -r '
    [ .[] | select([((.metadata.merge_hold // "") | tostring), ((.metadata.rebase_hold // "") | tostring)]
        | map(ascii_downcase) | any(. != "" and . != "false" and . != "0" and . != "null"))
      | .id ] | .[0] // empty' 2>/dev/null)
  if [ -n "$frozen" ]; then
    echo "$PROG: $cid — $frozen holds branch '$ctarget' with merge_hold/rebase_hold (operator gate); not graduated"
    held=$((held + 1)); continue
  fi
  inflight=$(printf '%s' "$probe" | jq -r --arg cid "$cid" \
    '[ .[] | select(.id != $cid) | .id ] | .[0] // empty' 2>/dev/null)
  if [ -n "$inflight" ]; then
    echo "$PROG: $cid — $inflight already owns branch '$ctarget'; not graduated (would duplicate its PR)"
    skipped=$((skipped + 1)); continue
  fi

  # Non-vacuous completion: the ledger must record at least one merge ONTO the
  # branch. Closed beads count (close-on-land closes them at that merge).
  if ! landed_raw=$(bd_list --metadata-field "merged_target=$ctarget" --status "$ALL_STATUSES"); then
    echo "$PROG: $cid — landing probe on '$ctarget' failed; not graduated (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  landed=$(printf '%s' "$landed_raw" | jq -r '
    [ .[] | select(((.metadata.merge_result // "") | tostring | ascii_downcase) == "merged") | .id ]
    | .[0] // empty' 2>/dev/null)
  if [ -z "$landed" ]; then
    echo "$PROG: $cid — no bead records a merge onto '$ctarget' (merged_target + merge_result=merged); its members closing proves nothing about the branch, not graduated (land deliberately with \`gc convoy land\` if it is complete)"
    vacuous=$((vacuous + 1)); continue
  fi

  if gc bd update "$cid" ${GC_RIG:+--rig="$GC_RIG"} \
       --assignee="$GC_AGENT" \
       --set-metadata branch="$ctarget" \
       --set-metadata target="$TARGET_BRANCH" \
       --set-metadata merge_strategy=mr \
       --set-metadata graduation=true >/dev/null 2>&1; then
    graduated=$((graduated + 1))
    echo "$PROG: graduating $cid — $ctarget -> $TARGET_BRANCH (mr; human-approved PR)"
  else
    skipped=$((skipped + 1))
    echo "$PROG: $cid assign failed; retry next pass" >&2
  fi
done <<< "$CANDS"

echo "$PROG: $graduated graduating, $skipped skipped, $held held, $vacuous vacuous"
exit 0
