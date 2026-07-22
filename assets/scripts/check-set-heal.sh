#!/usr/bin/env bash
# check-set-heal — normalize `check_set` at the REFINERY BOUNDARY, so an anchor
# that never ran the formula's normalization cannot merge ungated (tk-i48ca).
#
# THE BUG. A hand-RECOVERED work bead reaches the refinery WITHOUT the merge-push
# step ever running, so its `check_set` was never normalized. It arrives carrying
# an empty (or absent) check_set, merge-skill.sh reads empty as "declares NO
# gates", and the PR lands on CI + human approval alone — with NO codex review
# ever dispatched. Observed on shutupandlisten 2026-07-22: anchor su-lou.10.5,
# a `recovered: true` bead handed off by gc-toolkit.furiosa after a prior polecat
# died between commit and handoff, reached the refinery with check_set="" while
# the formula's declared default is `codex`. PR #30 would have merged un-reviewed;
# a human caught it and hand-dispatched the review. That was a manual save, not
# the system working. THIS PASS IS THAT SAVE, AUTOMATED.
#
# WHY #200 DID NOT ALREADY FIX IT. #200 (tk-4na1b.3) fixed the formula RENDER, so
# the normal polecat path is sound: the merge-push step recovers the declared
# default and stamps it. But the recovery path bypasses the formula render
# entirely — a bead reconstructed by hand, or by a salvage agent, never runs the
# normalization step at all. Fixing the render cannot reach a bead that never
# renders.
#
# WHY THE FIX HAS TO BE HERE, NOT IN THE MERGE SKILL. merge-skill.sh reading an
# empty check_set as "no gates" is the DELIBERATE #163/#182 fix: the code before
# it held merges unconditionally on a missing signoff marker even when no gate was
# required, stranding human-approved CLEAN PRs forever. Making the merge skill
# fail-closed on empty was considered and explicitly NOT approved. So the repair
# stays strictly UPSTREAM of the merge loop — this pass fixes what is STAMPED,
# never how the stamp is READ. It runs immediately BEFORE merge-skill.sh in the
# refinery's find-work idle loop, so a bypassed anchor is normalized before the
# merge skill ever enumerates it.
#
# THE DISCRIMINATOR (the other half of this fix, in mol-refinery-patrol.toml). The
# formula used to collapse the `none`/`off` opt-out sentinel to the empty string,
# which made "gateless by choice" and "never normalized" the SAME value on the
# anchor — nothing downstream could tell them apart, so nothing could safely
# repair either. The formula now stamps the canonical `none` instead, so EVERY
# formula-normalized anchor carries a NON-EMPTY check_set. An empty one here is
# therefore an unambiguous "this bead never ran normalization" signal.
#
#   check_set canonicalizes to...      this pass...
#   -------------------------------    ------------------------------------------
#   a gate list (codex, "lint,codex")  leaves it alone (already normalized)
#   `none` / `off`                     leaves it alone (EXPLICIT opt-out, tk-4na1b)
#   empty / absent / whitespace / ","  HEALS: stamps the declared default
#
# FAIL-CLOSED ORDER: STAMP FIRST, THEN DISPATCH. The stamp is what HOLDS the merge
# (a gate with no green marker cannot merge), so it is applied before the review is
# dispatched. Stamping first and failing leaves the anchor HELD and retried next
# pass; dispatching first and failing leaves it UNGATED and merged. Delay is the
# acceptable failure here; an un-reviewed merge is not. This inverts the formula's
# own ordering (which verifies the link BEFORE stamping) on purpose: there the
# anchor is not yet detached into gating so nothing can merge it meanwhile, whereas
# here the anchor is ALREADY gating and one un-held pass is a merge.
#
# NOT STRANDING THE GATE. Arming `codex` on an anchor with no review bead would
# hold the merge forever on a marker nothing can stamp — trading a silent-bypass
# bug for a silent-strand bug. So after stamping, this pass ensures the gate is
# SATISFIABLE: it reuses an in-flight review, respects an already-green marker,
# and otherwise dispatches a codex signoff exactly as the merge-push step does
# (task_kind=review + check_name + anchor_bead + a BLOCKS edge), then verifies the
# anchor link persisted. A dispatch that fails is retried next idle pass (the
# lookup dedups), and the anchor stays held meanwhile.
#
# Idempotent + convergent: a healed anchor carries a non-empty check_set, so the
# next pass classifies it "already normalized" and does nothing.
#
# Enumerated by BEAD (like merge-skill.sh / pre-open-resolve.sh), across BOTH
# gating sub-states: `pull_request` is where the un-gated merge happens, and
# `pre_open_gate` gets the same repair so a bypassed pre-open anchor (held by
# pre-open-resolve.sh on a codex marker no one was dispatched to stamp) is
# unstuck rather than left waiting forever.
#
# NOT set -e: best-effort, must never abort the patrol's idle loop. Any tool error
# skips the anchor and retries next idle pass.
set -uo pipefail

# The declared check-set default, passed in by the formula as the RENDERED
# {{check_set}} — never hand-substituted from raw TOML here (that hand-substitution
# is the tk-4na1b bug this whole mechanism exists to contain). The literal fallback
# below matches `[vars.check_set] default` in mol-refinery-patrol.toml; the
# regression test asserts the two stay in lockstep, so the fallback cannot rot into
# recovering a stale value.
DEFAULT_CHECK_SET=""
REVIEW_POOL=""
FIX_POOL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --default)     DEFAULT_CHECK_SET="${2:-}"; shift 2 ;;
    --review-pool) REVIEW_POOL="${2:-}"; shift 2 ;;
    --fix-pool)    FIX_POOL="${2:-}"; shift 2 ;;
    *)             shift ;;
  esac
done

# Canonical form used for every check_set decision: lowercase, with whitespace and
# separators removed. Mirrors the formula's `_cs_canon`, so "  NONE  ", "none" and
# "off" all collapse to a sentinel, and "", "   ", ",,," all collapse to empty (a
# separator-only value NAMES no gates, so it is as un-gated as an empty one and
# must heal too — otherwise it is the same bypass wearing a mask).
cs_canon() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:],'; }

# Normalize the declared default itself, exactly as the formula does. A rig that
# declares `none` is gateless BY CONFIG: healing its anchors stamps the sentinel,
# which keeps them ungated — the repair restores the rig's declared intent, it does
# not impose codex on a rig that opted out.
case "$(cs_canon "$DEFAULT_CHECK_SET")" in
  '')       DEFAULT_CHECK_SET="codex" ;;
  none|off) DEFAULT_CHECK_SET="none" ;;
esac

# Is `codex` a member of the healed set? Split on comma, trim, whole-line match —
# the SAME normalization merge-skill.sh enforces and the formula dispatches on, so
# a spaced "lint, codex" is recognized here too and dispatch never diverges from
# enforcement (tk-aj4ua).
has_codex() {
  printf '%s' "${1:-}" | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qxF codex
}

# Is anything already in flight against this anchor that would RAISE or re-raise
# its gate? A signoff review, or a rework child whose landing re-dispatches one.
# Dispatching past either would mint a twin review; the reviewer dedup upstream
# keys on narrower fields, so this is the broad check.
#
# Deliberately over-inclusive: a false "in flight" only DELAYS the dispatch by a
# pass while the anchor stays HELD (its gate is armed but unmet), whereas a false
# "nothing in flight" mints a duplicate review. Held is the safe direction, so the
# lookup errs toward finding something.
inflight_for() { # <anchor-id> <pr-number> <branch>
  local aid="$1" pnum="${2:-}" br="${3:-}" found=""
  if [ -n "$pnum" ]; then
    found=$(gc bd list --metadata-field pr_number="$pnum" \
      --status=open,in_progress --limit=0 --json 2>/dev/null \
      | jq -r --arg a "$aid" '[.[] | select(.id != $a)] | .[0].id // empty' 2>/dev/null)
  fi
  if [ -z "$found" ]; then
    found=$(gc bd list --metadata-field anchor_bead="$aid" \
      --status=open,in_progress --limit=0 --json 2>/dev/null \
      | jq -r --arg a "$aid" '[.[] | select(.id != $a)] | .[0].id // empty' 2>/dev/null)
  fi
  if [ -z "$found" ] && [ -n "$br" ]; then
    found=$(gc bd list --metadata-field branch="$br" \
      --status=open,in_progress --limit=0 --json 2>/dev/null \
      | jq -r --arg a "$aid" '[.[] | select(.id != $a)] | .[0].id // empty' 2>/dev/null)
  fi
  printf '%s' "$found"
}

# Both gating sub-states, in one row stream. `has("check_set")` is folded into the
# emitted value: an ABSENT key and an empty one are the same "never normalized"
# condition, so both canonicalize to empty below.
ROWS=""
for MR_STATE in pull_request pre_open_gate; do
  RAW=$(gc bd list --status=open \
    --metadata-field merge_result="$MR_STATE" \
    --limit=200 --json 2>/dev/null)
  [ -n "$RAW" ] && [ "$RAW" != "[]" ] || continue
  PART=$(printf '%s' "$RAW" | jq -c --arg st "$MR_STATE" '.[] | {
      id,
      state:    $st,
      checkset: (.metadata.check_set // ""),
      pr:       (.metadata.pr_number // ""),
      prurl:    (.metadata.pr_url // ""),
      branch:   (.metadata.branch // ""),
      target:   (.metadata.merged_target // .metadata.target // ""),
      title:    (.title // ""),
      codex:    (.metadata["check.codex"] // ""),
      healed:   (.metadata.check_set_healed // ""),
      flagged:  (.metadata.check_set_heal_flagged // "")
    }' 2>/dev/null)
  [ -n "$PART" ] || continue
  if [ -z "$ROWS" ]; then ROWS="$PART"; else ROWS="$ROWS
$PART"; fi
done
[ -n "$ROWS" ] || { echo "check-set-heal: no gating anchors"; exit 0; }

healed=0; dispatched=0; normal=0; optout=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  [ -n "$id" ] || { skipped=$((skipped + 1)); continue; }
  checkset=$(printf '%s' "$row" | jq -r '.checkset // empty')
  canon=$(cs_canon "$checkset")
  healedmark=$(printf '%s' "$row" | jq -r '.healed // empty')

  # --- classify -----------------------------------------------------------
  # A PREVIOUSLY healed anchor (check_set_healed recorded) keeps flowing into the
  # satisfiability check below even though its check_set now reads normal. That is
  # what makes "retry next pass" true: the stamp is what reclassifies the anchor,
  # so without this the very first successful stamp would hide the anchor from
  # every later pass — and a dispatch that failed after the stamp would strand the
  # armed gate forever with nothing to raise it.
  needs_stamp=0
  case "$canon" in
    '')
      needs_stamp=1 ;;                      # never normalized -> heal
    none|off)
      optout=$((optout + 1)); continue ;;   # EXPLICIT opt-out — leave it alone
    *)
      [ -n "$healedmark" ] || { normal=$((normal + 1)); continue; } ;;
  esac

  state=$(printf '%s' "$row" | jq -r '.state // empty')
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  prurl=$(printf '%s' "$row" | jq -r '.prurl // empty')
  branch=$(printf '%s' "$row" | jq -r '.branch // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  title=$(printf '%s' "$row" | jq -r '.title // empty')
  marker=$(printf '%s' "$row" | jq -r '.codex // empty')
  flagged=$(printf '%s' "$row" | jq -r '.flagged // empty')
  [ -n "$target" ] || target="main"

  # --- stamp FIRST (fail closed) ------------------------------------------
  # check_set_healed is the durable audit trail: it distinguishes an anchor whose
  # gate was repaired at the boundary from one the formula stamped normally, so
  # the bypass stays VISIBLE after the repair rather than being silently papered
  # over. It is ALSO the flag that keeps this anchor flowing through the
  # satisfiability check on later passes. Verified by re-read — a stamp that did
  # not persist must not be reported as a heal, and must not stop the retry.
  EFFECTIVE="$checkset"
  if [ "$needs_stamp" = 1 ]; then
    echo "check-set-heal: $id ($state${num:+ PR#$num}) has NO normalized check_set (bypassed the formula — recovery path); applying declared default '$DEFAULT_CHECK_SET'"
    gc bd update "$id" \
      --set-metadata check_set="$DEFAULT_CHECK_SET" \
      --set-metadata check_set_healed="$DEFAULT_CHECK_SET" \
      --append-notes "check-set-heal: check_set was absent/empty (bead reached the refinery without formula normalization — recovery path); stamped the declared default '$DEFAULT_CHECK_SET' so the merge cannot land ungated (tk-i48ca)." \
      >/dev/null 2>&1
    RECORDED=$(gc bd show "$id" --json 2>/dev/null | jq -r '.[0].metadata.check_set // empty')
    if [ "$RECORDED" != "$DEFAULT_CHECK_SET" ]; then
      # The ledger write did not stick. Do NOT count it as healed; the anchor is
      # still ungated and the merge skill may land it this pass. Flag ONCE so the
      # noise is bounded, and let the next idle pass retry the whole heal.
      echo "check-set-heal: WARN $id check_set stamp did NOT persist (have '${RECORDED:-<empty>}', want '$DEFAULT_CHECK_SET'); anchor is still UNGATED — retrying next pass" >&2
      if [ -z "$flagged" ]; then
        gc bd update "$id" --set-metadata check_set_heal_flagged=1 >/dev/null 2>&1 || true
      fi
      skipped=$((skipped + 1)); continue
    fi
    healed=$((healed + 1))
    EFFECTIVE="$DEFAULT_CHECK_SET"
  fi

  # --- then make the gate SATISFIABLE -------------------------------------
  # Reached by a freshly-healed anchor AND by one healed on an earlier pass whose
  # gate still has nothing to raise it. The gates enforced are the anchor's LIVE
  # check_set (an operator may have edited it since the heal), not the default.
  #
  # Only codex is dispatchable from here (it is the only check-set member this
  # city knows how to raise). A non-codex gate name is left to whatever raises it.
  if ! has_codex "$EFFECTIVE"; then
    [ "$needs_stamp" = 1 ] || normal=$((normal + 1))
    continue
  fi

  # Already green: a review ran for this anchor at some point and stamped the
  # marker — the gate is satisfiable (green at the live head merges; green at a
  # stale head re-gates through the normal rework path). Nothing to dispatch.
  if [ -n "$marker" ]; then
    [ "$needs_stamp" = 1 ] && echo "check-set-heal: $id already carries check.codex='$marker'; gate is satisfiable, no dispatch"
    [ "$needs_stamp" = 1 ] || normal=$((normal + 1))
    continue
  fi

  # Reuse whatever is already in flight rather than dispatching a twin: an open
  # signoff review, or a rework child whose hand-back re-dispatches the review.
  EXISTING_REVIEW=$(inflight_for "$id" "$num" "$branch")
  if [ -n "$EXISTING_REVIEW" ]; then
    [ "$needs_stamp" = 1 ] && echo "check-set-heal: $id already has in-flight $EXISTING_REVIEW; gate will be raised by it, no dispatch"
    [ "$needs_stamp" = 1 ] || normal=$((normal + 1))
    continue
  fi

  # No review pool configured (the formula always passes one; a bare invocation
  # may not). Stamping without a dispatch would arm a gate nothing can stamp, so
  # say so LOUDLY — the anchor is held, not merged, which is the safe side.
  if [ -z "$REVIEW_POOL" ]; then
    echo "check-set-heal: WARN $id gate '$DEFAULT_CHECK_SET' armed but no --review-pool given; no signoff dispatched (merge is HELD until one is)" >&2
    continue
  fi

  # Dispatch the signoff, mirroring the merge-push step's shape so the reviewer's
  # done-sequence finds exactly the fields it expects: pre-open reviews the BRANCH
  # compare-range (review_branch/review_base, no PR yet), post-open reviews the PR.
  REVIEW_BEAD=""
  if [ -n "$num" ]; then
    REVIEW_BEAD=$(gc bd create "Review PR#$num: $title" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
  else
    REVIEW_BEAD=$(gc bd create "Review branch $branch -> $target: $title" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
  fi
  if [ -z "$REVIEW_BEAD" ]; then
    echo "check-set-heal: WARN $id could not create the signoff bead; merge stays HELD, retrying next pass" >&2
    continue
  fi

  # Stamp the review's fields BEFORE routing it. gc.routed_to is what makes the
  # bead claimable, so it is written LAST, in its own call: a codex polecat that
  # claimed a half-stamped review would have no anchor_bead to stamp the gate on.
  if [ -n "$num" ]; then
    gc bd update "$REVIEW_BEAD" \
      --set-metadata task_kind=review \
      --set-metadata check_name=codex \
      --set-metadata pr_url="$prurl" \
      --set-metadata pr_number="$num" \
      --set-metadata anchor_bead="$id" >/dev/null 2>&1
  else
    gc bd update "$REVIEW_BEAD" \
      --set-metadata task_kind=review \
      --set-metadata check_name=codex \
      --set-metadata review_branch="$branch" \
      --set-metadata review_base="$target" \
      --set-metadata anchor_bead="$id" >/dev/null 2>&1
  fi
  if [ -n "$FIX_POOL" ]; then
    gc bd update "$REVIEW_BEAD" --set-metadata fix_target_pool="$FIX_POOL" >/dev/null 2>&1
  fi

  # Gate-as-dep: the review BLOCKS the anchor. Best-effort (anchor_bead is the
  # durable fallback the signoff resolves through when the edge is missing).
  gc bd dep "$REVIEW_BEAD" --blocks "$id" >/dev/null 2>&1 \
    || echo "check-set-heal: WARN could not attach review $REVIEW_BEAD as a gate-dep of $id (anchor_bead fallback persists the link)" >&2

  # Verify the link the signoff needs to find its way back, BEFORE routing it.
  # Without it the review cannot stamp check.codex on this anchor and the armed
  # gate would never clear. Unrouted, the bead is inert and the next pass's dedup
  # (open + task_kind=review) reuses it rather than minting a twin.
  RECORDED_ANCHOR=$(gc bd show "$REVIEW_BEAD" --json 2>/dev/null \
    | jq -r '.[0].metadata.anchor_bead // empty')
  if [ "$RECORDED_ANCHOR" != "$id" ]; then
    echo "check-set-heal: WARN review $REVIEW_BEAD did not record anchor_bead=$id; signoff cannot stamp the gate — merge stays HELD, retrying next pass" >&2
    continue
  fi

  gc bd update "$REVIEW_BEAD" --set-metadata gc.routed_to="$REVIEW_POOL" >/dev/null 2>&1
  gc session wake "$REVIEW_POOL" >/dev/null 2>&1 || true
  gc session nudge "$REVIEW_POOL" "Review bead $REVIEW_BEAD for recovered anchor $id" >/dev/null 2>&1 || true
  dispatched=$((dispatched + 1))
  echo "check-set-heal: $id dispatched signoff $REVIEW_BEAD to $REVIEW_POOL (gate '$DEFAULT_CHECK_SET' is now satisfiable)"
done <<< "$ROWS"

echo "check-set-heal: $healed healed, $dispatched signoffs dispatched, $normal already normalized, $optout explicit opt-out, $skipped skipped"
exit 0
