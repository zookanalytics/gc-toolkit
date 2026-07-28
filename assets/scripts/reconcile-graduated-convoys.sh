#!/usr/bin/env bash
# reconcile-graduated-convoys — system-auto convoy graduation: the convoy half
# of close-on-land, one level up. When an OWNED integration convoy's members
# are ALL closed, assign the convoy bead to the refinery as an ordinary mr-mode
# work bead (branch=integration/<id>, target=<main>, merge_strategy=mr). The
# next find-work iteration picks it up and walks it through the SAME work-bead
# machine -> a human-approved PR integration->main -> merge -> closed. No
# coordinator (mayor/mechanik) sits in this loop; `gc convoy land` remains a
# manual bead-state-flip primitive but is NOT the driver.
#
# THE INTERLOCK: a convoy child closes ONLY on merge to its integration branch
# (close-on-land). So "all members closed" == "all members MERGED": the
# integration branch already contains every child's work before this pass ever
# fires. Graduation can never assemble a half-built branch. An abandoned child
# stays OPEN (escalated by reconcile-merged-prs.sh, not closed), so it keeps the
# convoy incomplete and blocks graduation until a human resolves it.
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
# OPERATOR GATES: graduation is not a passive label — it makes the convoy bead
# actionable mr-mode work, so the very next refinery pass REBASES the integration
# branch onto the target and opens a PR. That is exactly the developer/conflict
# work an operator holds a graduation to prevent, so this pass honors the same
# hold markers the merge and rebase paths do (merge-skill.sh, reconcile-merged-
# prs.sh). Two vetoes, both fail-closed:
#
#   (a) the convoy bead itself carries merge_hold or rebase_hold — the operator
#       gated THIS graduation;
#   (b) any LIVE bead names the same integration branch in metadata.branch — a
#       held graduation/rebase bead (veto: operator gate) or an unheld one (veto:
#       something already owns graduating this branch, and a second assignment
#       would duplicate its PR).
#
# (b) is keyed on the BRANCH, not on the convoy bead, because the branch is what
# a graduation actually acts on: the operator's hold commonly lives on a SEPARATE
# rebase bead naming the branch, which a convoy-bead-only check cannot see. The
# observed failure (gc-8g41r, 2026-06-30) was exactly this — held rebase bead
# gc-1g2p1 carried merge_hold=operator-gated-graduation for integration/input-
# area-state with PR#60 open and CONFLICTING, and this pass auto-graduated the
# convoy anyway because it read neither the marker nor the sibling bead.
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

# Every non-closed status, enumerated. A bead an operator NEUTRALISED by BLOCKING
# it is still the owner of its branch and its hold is still binding, so reading
# only `open` here would make the standard operator move invisible and graduate
# straight past it — "treating not-open as gone" is the core error of this bead
# class (tk-gajop). This is the COMPLEMENT of `closed` over `bd statuses`, spelled
# positively because --status takes a positive list; `hooked` and `pinned` are as
# branch-owning as `blocked`. Re-derive if `bd statuses` grows a new status.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# Truthy in the operators' sense: set, and not one of the explicit "off"
# spellings. Mirrors merge-skill.sh's reading of merge_hold exactly, so a marker
# that holds a merge there cannot fail to hold a graduation here.
is_held() {
  case "${1:-}" in
    ""|false|False|FALSE|0|null) return 1 ;;
    *) return 0 ;;
  esac
}

# Every live bead whose metadata.branch names <branch>, as compact rows of the id
# and its two hold markers. --limit=0 so the probe sees the whole set, not a page
# of it: a truncated page could hide the one held bead that must veto.
#
# Returns NON-ZERO on a failed ledger read, which the caller MUST treat as "I
# cannot tell" and NOT as "nobody holds this branch". Non-empty stdout alone does
# not mean success — `gc ... --json` reports its own failures as a non-empty JSON
# *object* on stdout (`{"error": ...}`), which survives an emptiness test, yields
# zero rows through the projection, and so fails OPEN in the one direction that
# auto-lands past an operator gate. A genuinely empty result is the literal "[]",
# which returns zero with no rows.
probe_branch_beads() {
  local raw rc out
  raw=$(gc bd list ${GC_RIG:+--rig="$GC_RIG"} --metadata-field "branch=$1" \
    --status "$LIVE_STATUSES" --limit=0 --json 2>/dev/null)
  rc=$?
  # (1) The command's own verdict, checked even when it wrote to stdout.
  [ "$rc" -eq 0 ] || return 1
  # (2) No output at all — a broken `gc bd list`, as distinct from "[]". Strictly
  #     an early-out: (3) also rejects empty input (`jq -e` exits non-zero on it),
  #     so no test pins this line alone. Kept because it states the ""-vs-"[]"
  #     contract this helper is built on, where a reader looks for it.
  [ -n "$raw" ] || return 1
  # (3) The payload must be the ARRAY of beads we asked for. Rejects an error
  #     object that arrived with a ZERO exit status.
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  # (4) The projection's own status, captured first: emitted straight to stdout,
  #     jq's failure would be discarded by the caller's `probe=$(...)` capture.
  out=$(printf '%s' "$raw" \
    | jq -c '.[] | {id, hold: (.metadata.merge_hold // ""), rhold: (.metadata.rebase_hold // "")}' 2>/dev/null) \
    || return 1
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

# Owned-ness + member completion come ONLY from `gc convoy list` (ConvoyFields,
# not bead metadata). City-wide by construction — scoped to this rig below.
CONVOYS=$(gc convoy list --json 2>/dev/null)
[ -n "$CONVOYS" ] || { echo "reconcile-graduated-convoys: convoy list unavailable"; exit 0; }

# Candidate = targets the integration boundary AND all members closed (== all
# merged, per the interlock above) AND has members. The graduation predicate is
# the target + completion, not ownership per se; `owned` is the core label that
# carries the integration target, kept as the underlying mechanism that scopes
# this to integration convoys (per-sling auto-convoys are un-owned and carry no
# integration/* target). progress.total>0 guards an empty convoy; closed==total
# is the completion gate.
CANDS=$(printf '%s' "$CONVOYS" | jq -r '
  .convoys[]?
  | select((.fields.target // "") | startswith("integration/"))
  | select(.progress.total > 0 and .progress.closed == .progress.total)
  | select(.owned == true)
  | "\(.id)\t\(.fields.target)"' 2>/dev/null)
[ -n "$CANDS" ] || { echo "reconcile-graduated-convoys: no complete owned integration convoys"; exit 0; }

# This rig's open convoy ledger (rig-scoped). The intersection scopes graduation
# to convoys owned by THIS refinery's rig — `gc convoy list` is city-wide.
RIG_CONVOYS=$(gc bd list ${GC_RIG:+--rig="$GC_RIG"} --type=convoy --status=open \
  --limit=200 --json 2>/dev/null | jq -r '.[].id' 2>/dev/null)

graduated=0; skipped=0; held=0
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

  # Operator gate (a): the marker is on the convoy bead itself. Checked FIRST —
  # it is the cheapest gate (metadata already in hand) and the highest priority
  # (an intentional operator block, independent of every other condition), and
  # naming it in the log is what makes a deliberately-held convoy diagnosable
  # rather than indistinguishable from an idempotency skip. merge_hold is "do not
  # land this yet"; rebase_hold is the narrower "do not rebase/force-push this
  # branch". Either vetoes: graduation causes BOTH — the refinery rebases the
  # integration branch and then lands it.
  if is_held "$(printf '%s' "$CMETA" | jq -r '.[0].metadata.merge_hold // ""' 2>/dev/null)"; then
    echo "reconcile-graduated-convoys: $cid — merge_hold set on the convoy (operator gate); not graduated"
    held=$((held + 1)); continue
  fi
  if is_held "$(printf '%s' "$CMETA" | jq -r '.[0].metadata.rebase_hold // ""' 2>/dev/null)"; then
    echo "reconcile-graduated-convoys: $cid — rebase_hold set on the convoy (operator gate); not graduated"
    held=$((held + 1)); continue
  fi

  existing_branch=$(printf '%s' "$CMETA" | jq -r '.[0].metadata.branch // ""' 2>/dev/null)
  if [ -n "$existing_branch" ]; then skipped=$((skipped + 1)); continue; fi

  # Operator gate (b): who else is already on this integration branch? The hold
  # commonly lives on a SEPARATE bead — the operator files/holds a graduation or
  # rebase bead for the branch (gc-1g2p1) rather than annotating the convoy — and
  # that bead is invisible to every check above. FAIL CLOSED on an unreadable
  # probe: a failed ledger read is indistinguishable from "nobody holds this
  # branch", and reading it optimistically graduates precisely when we cannot
  # verify a freeze. A deferred graduation costs one idle pass; an unapproved
  # rebase of a branch a keeper froze is not recoverable by retry.
  if ! probe=$(probe_branch_beads "$ctarget"); then
    echo "reconcile-graduated-convoys: $cid — branch probe on '$ctarget' failed; not graduated (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi

  # A hold ANYWHERE on this branch is the operator's freeze on the work this
  # graduation would set in motion.
  #
  # `tostring` before the comparison because a marker is not always a STRING: a
  # writer that stores JSON (`merge_hold: true`) yields a boolean, and
  # `ascii_downcase` on a boolean ABORTS the jq program — whose error this call
  # deliberately discards, so the veto would evaporate into an empty `frozen` and
  # graduate straight past the gate. jq's `//` already folds a boolean `false`
  # (and null) to "", the off answer, so only the truthy side needs the cast.
  frozen=$(printf '%s\n' "$probe" \
    | jq -r 'select([(.hold // ""), (.rhold // "")] | map(tostring | ascii_downcase)
             | any(. != "" and . != "false" and . != "0" and . != "null")) | .id' 2>/dev/null \
    | head -1)
  if [ -n "$frozen" ]; then
    echo "reconcile-graduated-convoys: $cid — $frozen holds branch '$ctarget' with merge_hold/rebase_hold (operator gate); not graduated"
    held=$((held + 1)); continue
  fi

  # Unheld, but something live already names this branch: a graduation is already
  # in flight for it (a prior anchor whose convoy marker was cleared, a rework
  # child of its PR, a hand-filed graduation bead). Assigning a second one races
  # it and duplicates its PR. Keyed on the branch, so it catches an owner this
  # convoy's own metadata never mentions; the convoy itself is excluded by id.
  inflight=$(printf '%s\n' "$probe" | jq -r --arg cid "$cid" 'select(.id != $cid) | .id' 2>/dev/null | head -1)
  if [ -n "$inflight" ]; then
    echo "reconcile-graduated-convoys: $cid — $inflight already owns branch '$ctarget'; not graduated (would duplicate its PR)"
    skipped=$((skipped + 1)); continue
  fi

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

echo "reconcile-graduated-convoys: $graduated graduating, $skipped skipped, $held held"
exit 0
