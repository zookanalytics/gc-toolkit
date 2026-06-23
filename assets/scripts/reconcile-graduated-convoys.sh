#!/usr/bin/env bash
# reconcile-graduated-convoys — system-auto convoy graduation: the convoy half
# of close-on-merge, one level up. When an OWNED integration convoy's members
# are ALL closed, assign the convoy bead to the refinery as an ordinary mr-mode
# work bead (branch=integration/<id>, target=<main>, merge_strategy=mr). The
# next find-work iteration picks it up and walks it through the SAME work-bead
# machine -> a human-approved PR integration->main -> merge -> closed. No
# coordinator (mayor/mechanik) sits in this loop; `gc convoy land` remains a
# manual bead-state-flip primitive but is NOT the driver.
#
# THE INTERLOCK (why this ships WITH close-on-merge, tk-6d0vb.1.1): a convoy
# child closes ONLY on merge to its integration branch (close-on-merge). So
# "all members closed" == "all members MERGED": the integration branch already
# contains every child's work before this pass ever fires. Graduation can never
# assemble a half-built branch. An abandoned child stays OPEN (escalated by
# reconcile-merged-prs.sh, not closed), so it keeps the convoy incomplete and
# blocks graduation until a human resolves it. Before close-on-merge a child
# closed at PR-CREATION, so "all closed" could mean "nothing merged" and
# graduation would fire on an empty branch — that is the bug the two beads
# close together.
#
# SCOPE: OWNED integration convoys in THIS rig only.
#   - Owned-ness + member progress live in ConvoyFields, surfaced ONLY by
#     `gc convoy list` (NOT in `gc bd show` metadata). `gc convoy list` is
#     city-wide and ignores --rig, so its candidates are intersected with the
#     rig-scoped convoy ledger to avoid graduating another rig's convoy into
#     this refinery.
#   - Non-owned auto-convoys (the per-sling tracking bundles) are NEVER touched:
#     they are not `owned`, carry no integration/* target, and auto-close on
#     their own.
#
# IDEMPOTENT + CONVERGENT: graduation sets metadata.branch on the convoy bead,
# retained through the gating phase; this pass skips any convoy whose bead
# already carries branch, so it never double-assigns. Once graduated the convoy
# bead closes (merge to main) and drops off `gc convoy list`. Best-effort: any
# tool error skips that convoy and is retried next idle pass.
#
# The refinery patrol runs this on each idle wake, folded into the find-work
# step's sleep loop AFTER reconcile-merged-prs.sh — so the wake that closes a
# convoy's last merged child immediately graduates the now-complete convoy.
#
# NOT set -e: best-effort, must never abort the patrol's idle loop.
set -uo pipefail

TARGET_BRANCH="main"
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      TARGET_BRANCH="${2:-main}"
      if [ $# -ge 2 ]; then shift 2; else shift; fi
      ;;
    *) shift ;;
  esac
done

# Graduation assigns the convoy bead to this refinery agent; without an identity
# the assignment would strand the bead (assignee=""). Skip rather than strand.
if [ -z "${GC_AGENT:-}" ]; then
  echo "reconcile-graduated-convoys: GC_AGENT unset; skip" >&2
  exit 0
fi

# Owned-ness + member completion come ONLY from `gc convoy list` (ConvoyFields,
# not bead metadata). City-wide by construction — scoped to this rig below.
CONVOYS=$(gc convoy list --json 2>/dev/null)
[ -n "$CONVOYS" ] || { echo "reconcile-graduated-convoys: convoy list unavailable"; exit 0; }

# Candidate = owned + integration/* target + has members + ALL members closed.
# progress.total>0 guards an empty convoy; closed==total is the completion gate
# (== all-merged, per the interlock above).
CANDS=$(printf '%s' "$CONVOYS" | jq -r '
  .convoys[]?
  | select(.owned == true)
  | select((.fields.target // "") | startswith("integration/"))
  | select(.progress.total > 0 and .progress.closed == .progress.total)
  | "\(.id)\t\(.fields.target)"' 2>/dev/null)
[ -n "$CANDS" ] || { echo "reconcile-graduated-convoys: no complete owned integration convoys"; exit 0; }

# This rig's open convoy ledger (rig-scoped). The intersection scopes graduation
# to convoys owned by THIS refinery's rig — `gc convoy list` is city-wide.
RIG_CONVOYS=$(gc bd list ${GC_RIG:+--rig="$GC_RIG"} --type=convoy --status=open \
  --limit=200 --json 2>/dev/null | jq -r '.[].id' 2>/dev/null)

graduated=0; skipped=0
while IFS="$(printf '\t')" read -r cid ctarget; do
  [ -n "${cid:-}" ] || continue

  # Rig scope: only graduate convoys present in this rig's ledger. -F (fixed
  # string) because convoy IDs contain dots (e.g. tk-6d0vb.1.2) — an unescaped
  # dot in a regex match would be a wildcard and could cross-match another id.
  printf '%s\n' "$RIG_CONVOYS" | grep -qxF "$cid" || { skipped=$((skipped + 1)); continue; }

  # Idempotency: a convoy already set up for graduation carries metadata.branch
  # (set below, retained through gating). Its presence means "already
  # initiated" — never re-assign. A failed/empty show SKIPS (retry next pass)
  # rather than falling through to assign — never risk re-grabbing a convoy
  # that is mid-gating (assignee cleared, branch still set) on a transient read.
  CMETA=$(gc bd show "$cid" ${GC_RIG:+--rig="$GC_RIG"} --json 2>/dev/null)
  if [ -z "$CMETA" ] || [ "$CMETA" = "[]" ]; then skipped=$((skipped + 1)); continue; fi
  existing_branch=$(printf '%s' "$CMETA" | jq -r '.[0].metadata.branch // ""' 2>/dev/null)
  if [ -n "$existing_branch" ]; then skipped=$((skipped + 1)); continue; fi

  # Assign the convoy bead to the refinery as an ordinary mr-mode work bead:
  #   branch         = the integration branch to merge (source)
  #   target         = <main> (destination) — overwrites the child-inheritance
  #                    target; all children are closed, none remain to inherit it
  #   merge_strategy = mr  -> the integration->main merge is gated by a normal
  #                    human-approved PR (never a direct FF that bypasses review)
  #   graduation     = true (forensic marker; distinguishes a graduation anchor)
  if gc bd update "$cid" ${GC_RIG:+--rig="$GC_RIG"} \
       --assignee="$GC_AGENT" \
       --set-metadata branch="$ctarget" \
       --set-metadata target="$TARGET_BRANCH" \
       --set-metadata merge_strategy=mr \
       --set-metadata graduation=true >/dev/null 2>&1; then
    graduated=$((graduated + 1))
    echo "reconcile-graduated-convoys: graduating $cid — $ctarget -> $TARGET_BRANCH (mr; human-approved PR)"
  else
    skipped=$((skipped + 1))
    echo "reconcile-graduated-convoys: $cid assign failed; retry next pass" >&2
  fi
done <<< "$CANDS"

echo "reconcile-graduated-convoys: $graduated graduating, $skipped skipped"
exit 0
