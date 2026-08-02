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
# Idempotent + convergent: a healed anchor carries a non-empty check_set, so it is
# never re-stamped. It does stay VISIBLE to the satisfiability retry (via
# check_set_healed, or check_set_heal_flagged if that mark was lost), which is what
# lets a failed dispatch be retried — but once its gate is satisfiable, every later
# pass reads it as already normalized and does nothing.
#
# Enumerated by BEAD (like merge-skill.sh / pre-open-resolve.sh), across BOTH
# gating sub-states: `pull_request` is where the un-gated merge happens, and
# `pre_open_gate` gets the same repair so a bypassed pre-open anchor (held by
# pre-open-resolve.sh on a codex marker no one was dispatched to stamp) is
# unstuck rather than left waiting forever.
#
# TWO PHASES, IN ORDER (phase 0 added by tk-wsxd0):
#
#   phase 0  merge_result recovery — can this anchor be SEEN at all?
#   phase 1  check_set normalization — is what we see GATED? (everything above)
#
# Phase 1 and every other pass enumerate anchors on the `merge_result` field, so an
# anchor missing `merge_result` ENTIRELY is invisible to all of them at once — a
# silent, unbounded stall (shutupandlisten PR#37 sat open 6 days with zero
# escalations). Phase 0 is the repair that cannot key on the damaged field: it finds
# beads the refinery already canonicalized a PR onto (`pr_url`/`pr_number`) but that
# carry no `merge_result`, and restores it. Ordering the phases this way is what
# makes an anchor recovered in phase 0 also GATED in phase 1, on the same pass,
# before merge-skill.sh runs. See the phase 0 block for its exclusions.
#
# NOT set -e: best-effort, must never abort the patrol's idle loop. Any tool error
# skips the anchor and retries next idle pass.
set -uo pipefail

# EXIT-CODE CONTRACT with the refinery formula (mol-refinery-patrol.toml,
# heal-gates-merge). Almost every failure here is best-effort and exits 0: the
# anchor is left HELD (gate armed, no green marker) or INVISIBLE (no merge_result),
# and retried next idle pass — both of which merge-skill.sh already treats safely.
#
# UNSAFE_RC names exactly ONE condition, in one sentence: an anchor is VISIBLE to
# merge-skill.sh this pass while its check_set is still empty, which merge-skill.sh
# reads as "declares no gates" and would land un-reviewed IN THE SAME PASS. Three
# distinct failures reach it, and the formula's diagnostics must describe them:
#
#   1. a check_set stamp that did NOT persist on an already-visible anchor
#      (tk-i48ca / review tk-z4u2e finding #1);
#   2. an anchor PHASE 0 made visible this pass that phase 1 then did not gate —
#      either because the gating enumeration came back empty, or because the anchor
#      was not reached in it. Phase 0 is what created that exposure, so it is phase 0
#      that must hold the merge (tk-zl932 / review tk-ej3wq finding #2); and
#   3. a gating enumeration that could not be READ at all. The other two are KNOWN
#      exposures; this one is an UNVERIFIABLE one, and it is held for the same reason
#      rather than a weaker one. merge-skill.sh runs immediately after this pass on
#      the standing guarantee that it normalized every visible anchor's check_set —
#      an empty one is ungated there BY DESIGN, and this is the boundary that repairs
#      it. A pass that could not read the gating set cannot make that guarantee about
#      any anchor, including one that arrived hand-recovered and empty since the last
#      pass. Cost of holding: one deferred pass. Cost of not holding: the un-reviewed
#      merge this exit code exists for (review tk-thvbq finding #1).
#
# A merge_result stamp that fails is NOT this condition — an invisible anchor cannot
# be merged either — so it exits 0 and retries. A LOST check_set_healed mark is
# likewise NOT this case: the gate is armed, so the merge is already held, and
# holding every OTHER anchor's merge over it would be collateral. That half is
# repaired in-pass instead (review tk-nwi06 finding #1). On UNSAFE_RC the formula
# HOLDS merge-skill.sh for the pass. The formula's HEAL_UNSAFE_RC must equal this
# value; the regressions drive the real script to this exit for every cause and
# assert the merge is held.
readonly UNSAFE_RC=3

# The declared check-set default, passed in by the formula as the RENDERED
# {{check_set}} — never hand-substituted from raw TOML here (that hand-substitution
# is the tk-4na1b bug this whole mechanism exists to contain). The literal fallback
# below matches `[vars.check_set] default` in mol-refinery-patrol.toml; the
# regression test asserts the two stay in lockstep, so the fallback cannot rot into
# recovering a stale value.
DEFAULT_CHECK_SET=""
REVIEW_POOL=""
FIX_POOL=""
REFINERY_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --default)     DEFAULT_CHECK_SET="${2:-}"; shift 2 ;;
    --review-pool) REVIEW_POOL="${2:-}"; shift 2 ;;
    --fix-pool)    FIX_POOL="${2:-}"; shift 2 ;;
    --refinery)    REFINERY_ID="${2:-}"; shift 2 ;;
    *)             shift ;;
  esac
done

# The METHOD carried by every signoff this pass dispatches (tk-jufvl). A review
# bead created with a title and nothing else names no method, so the reviewing
# polecat picks its own by catalog description-match — the drift that ran a
# 6-persona fan-out at ~4.7M tokens per review. review-dispatch-body.sh is the
# ONE source of that prose, shared with reconcile-merged-prs.sh's stale-gate
# re-review so the two dispatches cannot say different things.
#
# FAIL-SOFT. A missing or failing emitter must never block a dispatch: an
# un-dispatched signoff leaves the armed gate unsatisfiable and HOLDS the merge
# forever, which is strictly worse than a title-only bead. So a body that cannot
# be produced degrades to today's behaviour, loudly.
# Resolved through a symlink on purpose: this city DOES symlink shared assets
# across rigs (all four rigs' mol-refinery-patrol.toml is one gc-toolkit file), so
# a symlinked deploy of this script whose real directory we failed to resolve
# would find no emitter, take the fail-soft path, and silently dispatch title-only
# reviews everywhere — this fix regressing invisibly behind one stderr line.
# readlink -f is coreutils; where it is absent the plain dirname still works for
# the normal non-symlinked deploy.
_cshself="${BASH_SOURCE[0]}"
_cshreal="$(readlink -f "$_cshself" 2>/dev/null || true)"
[ -n "$_cshreal" ] && _cshself="$_cshreal"
REVIEW_BODY_EMITTER="$(cd "$(dirname "$_cshself")" && pwd)/review-dispatch-body.sh"

# create_review_bead <title> — mint the signoff bead carrying the method, echo its
# id (empty on failure, exactly as the bare `gc bd create` it replaces).
create_review_bead() {
  local title="$1" body=""
  if [ -x "$REVIEW_BODY_EMITTER" ]; then
    body=$("$REVIEW_BODY_EMITTER" 2>/dev/null) || body=""
  fi
  if [ -z "$body" ]; then
    echo "check-set-heal: WARN review method unavailable ($REVIEW_BODY_EMITTER); dispatching a TITLE-ONLY review — the reviewer will have to pick its own method (tk-jufvl)" >&2
    gc bd create "$title" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null
    return
  fi
  printf '%s' "$body" \
    | gc bd create "$title" -t task --body-file - --json 2>/dev/null \
    | jq -r '.id // empty' 2>/dev/null
}

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

# Is `codex` a member of the healed set? Whole-token match against the
# comma-wrapped list — the SAME normalization merge-skill.sh enforces and the
# formula dispatches on, so a spaced "lint, codex" is recognized here too and
# dispatch never diverges from enforcement (tk-aj4ua).
#
# Matched IN-SHELL, never through a `... | grep -qxF codex` pipeline (tk-tmefn).
# `set -o pipefail` is on and `grep -q` exits at its FIRST match: that closes the
# pipe under the `tr`/`sed` still writing the gates that FOLLOW `codex` in the
# list, they take SIGPIPE, and the pipeline reports 141 — so a check_set that DOES
# name codex reads as one that does not, decided by nothing but how many gates
# happen to come after it. A rig passes on a short check_set and silently loses
# the gate when it grows. merge-skill.sh removed this same class from its
# `approval` detector and its trusted-approver allowlist; this is the same fix,
# here. Whitespace is stripped outright rather than trimmed per token — a gate
# name cannot contain any, so all of it is padding — and the comma wrapping makes
# it a whole-token test, so `codex` matches while `precodex` does not.
has_codex() {
  case ",$(printf '%s' "${1:-}" | tr -d '[:space:]')," in
    *",codex,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- durable-route verification (tk-tmefn) ----------------------------------
# A dispatch counts only once the route it wrote can be READ BACK. Both halves
# are needed and they answer different questions:
#   review_pool   the DURABLE copy of the route. Never consumed, so it is what a
#                 signoff restores the route from when it must put the review
#                 back to be re-offered; without it the release is open,
#                 unassigned and in NO pool (offered to nobody, gate owed
#                 forever).
#   gc.routed_to  the LIVE offer. A claim consumes it, so an empty value is only
#                 a fault when nobody has claimed the bead either.
# `read_route` emits "review_pool|gc.routed_to|assignee", or nothing at all when
# the bead cannot be read — the caller must treat those two as different answers
# ("bad route" vs "no answer"), because only one of them justifies discarding the
# review bead.
read_route() { # <bead-id>
  gc bd show "$1" --json 2>/dev/null \
    | jq -r '.[0] | [(.metadata.review_pool // ""),
                     (.metadata["gc.routed_to"] // ""),
                     (.assignee // "")] | join("|")' 2>/dev/null
}

# The anchor's fallback retry mark, read back from the bead. Same reason the two
# check_set halves are re-read after their stamp: this one is written by an
# equally best-effort update, and it is the ONLY thing keeping an anchor whose
# check_set_healed was lost visible to later passes.
read_flag() { # <anchor-id>
  gc bd show "$1" --json 2>/dev/null \
    | jq -r '.[0].metadata.check_set_heal_flagged // empty' 2>/dev/null
}

# Is that triple a route this pool can actually be reached through? 0 = yes.
# An empty triple (unreadable bead) is NOT ok — unverified is not verified.
#
# The live half is a MATCH against this pool, not a mere non-emptiness test
# (tk-bdfww). `gc.routed_to` is what a hook actually offers the bead through, and
# the two fields are written in one batched update that can persist one and lose
# the other (the same partial-write this whole read-back exists to catch). A
# review left carrying an OLDER gc.routed_to=B while review_pool=A persisted is
# reachable — by pool B, which is not the pool being dispatched to: pre-fix that
# read as verified, so the dispatch was counted, pool A was woken with nothing to
# claim, and pool B was offered a review minted for A. Both pools are wrong and
# the gate is owed either way. A mismatched non-empty route is therefore
# UNVERIFIED, which routes it into the repair-then-remint path below — where a
# genuine partial write is re-stamped and heals on the second read.
#
# An assignee is the one exception, and it is not a relaxation: a claim CONSUMES
# gc.routed_to, so a codex polecat that picked the review up between the write and
# this read legitimately leaves it empty (or, mid-claim, stale). The bead is held
# by a worker in the pool; there is nothing to re-offer and re-routing it would
# hand a claimed review to a second pool. Claimed is reachable.
route_ok() { # <route-state> <pool>
  local state="${1:-}" pool="${2:-}" r_pool r_routed r_assignee
  [ -n "$state" ] || return 1
  IFS='|' read -r r_pool r_routed r_assignee <<< "$state"
  [ "$r_pool" = "$pool" ] || return 1
  [ -n "$r_assignee" ] || [ "$r_routed" = "$pool" ] || return 1
  return 0
}

# ONE guarded ledger read -> the matching beads as a JSON array on stdout, or a
# NON-ZERO exit that every caller must read as "I could not tell" and never as
# "there is nothing there". Same helper, same three guards, and the same
# ""-vs-"[]" contract as reconcile-merged-prs.sh's `pr_bead_read`; these scripts
# are standalone by design, so it is duplicated rather than sourced. Keep them in
# step.
#
# EVERY read below went through a `type == "array"` test alone, which cannot see
# the failure that matters most here: `gc bd list` reporting its verdict in the
# EXIT STATUS while still writing a well-formed array (a read that died after
# emitting, a paged read cut short). That payload passes the shape test, so a
# PARTIAL or empty answer was accepted as a complete scan — and each caller reads
# a short answer as a positive fact: the recovery scan reads it as "no other
# candidate names this PR" (the ambiguity guard is a whole-set property and cannot
# see what it never scanned), the incumbent lookups read it as "no anchor owns this
# PR yet", and phase 1 reads it as the complete gating set. Each of those promotes,
# stamps, or skips on a question the ledger never actually answered
# (review tk-thvbq finding #1).
#
# --limit=0 on every read: a candidate, incumbent or anchor past a page boundary is
# invisible in exactly the same way, and every caller here is a whole-set question.
bd_list_read() {
  local raw rc
  raw=$(gc bd list "$@" --limit=0 --json 2>/dev/null)
  rc=$?
  # (1) The command's own verdict, checked even when it wrote to stdout.
  [ "$rc" -eq 0 ] || return 1
  # (2) No output at all — a broken `gc bd list`, as distinct from "[]".
  [ -n "$raw" ] || return 1
  # (3) The payload must be the ARRAY of beads we asked for. Rejects an error
  #     object that arrived with a ZERO exit status — and an object whose values
  #     are bead-shaped, which `.[]` iterates happily, so only this guard can tell
  #     it was never a bead list.
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
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
#
# ...but "over-inclusive" is only safe while the delay is a DELAY. Two of the three
# lookups below are broad — `pr_number` and `branch` name a bead by a field that is
# not this anchor's identity — and a bead they surface that is NOT about this anchor
# is never going to raise its gate. Suppressing the dispatch on one is not a pass of
# patience, it is the permanent hold: nothing re-examines the decision, so the gate
# stays armed and unmeetable and the merge is held forever, with the pass reporting a
# signoff already in flight (review tk-jza6h finding #2 — the same shape as the
# stranded-route hold below, arrived at through the dedup instead of through a lost
# write). Two mechanically reachable examples:
#
#   another repository's #<n>   pull numbers are unique only within a repository and
#                               this ledger spans rigs with different ones, so a
#                               foreign anchor for `otherhost/o/OTHER#745` answers the
#                               pr_number lookup for THIS repo's #745
#   an unattributable review    a signoff whose anchor_bead write was lost keeps its
#                               pr_number, so it still answers — while nothing can ever
#                               route it (`repair_review_routing` refuses to touch a
#                               review it cannot attribute to this anchor) and no
#                               polecat can claim it
#
# So: the EXACT surface is asked first and trusted outright, and matches from the broad
# surfaces must survive `inflight_candidate_ok` — which rejects a bead that is
# POSITIVELY somebody else's (it names another anchor, or its PR is in a different
# repository) and one that is provably inert (an unattributable review nothing can
# route or claim), and KEEPS SEARCHING rather than stopping at the first row. Anything
# unresolved still counts as in flight: `?` (an unnameable repository) matches
# everything, exactly as it does in phase 0's incumbent guards, so the dedup keeps its
# safety and only a positive disagreement clears the way.

# The validation predicate, as a jq filter over a `gc bd list` array. Kept in one
# variable because both broad lookups must apply exactly the same rule — two copies
# would be two chances to drift, on a decision whose failure mode is silent.
#   $a = this anchor's id, $r = the repository its PR lives in (`?` when unnameable)
INFLIGHT_OK_JQ='[.[]
  | select(.id != $a)
  | ((.metadata // {})) as $m
  | ((($m.anchor_bead // "") | tostring)) as $ab
  | ((($m.task_kind // "") | tostring)) as $tk
  | ((($m["gc.routed_to"] // "") | tostring)) as $rt
  | (((.assignee // "") | tostring) | gsub("[[:space:]]"; "")) as $as
  | ((($m.pr_url // "") | tostring)) as $u
  | ([$u | capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<r>[^/]+/[^/]+)/pull/[0-9]")]
      | .[0]) as $c
  | (if $c == null then "?" else ($c.h + "/" + $c.r) end) as $cr
  | select(
      if $ab == $a then
        # Names THIS anchor: ours by construction, whatever else it is.
        true
      elif $ab != "" then
        # Names ANOTHER anchor: positively not about this one. Its own anchor holds
        # its own merge; holding ours on it is a hold nothing will ever lift.
        false
      elif $tk == "review" and $rt == "" and $as == "" then
        # A review that names no anchor, is routed nowhere and is claimed by nobody.
        # `repair_review_routing` will not route it (it cannot be attributed to any
        # anchor) and no polecat can claim it unrouted, so it can never stamp any
        # gate. It is inert, not in flight — the exact shape a lost anchor_bead write
        # leaves behind, and believing it holds this merge forever.
        false
      else
        # Otherwise it is unattributed but live (a rework child, a claimed or routed
        # bead). Decide on the repository its PR names, fail-closed: `?` on either
        # side matches, so only a parsed disagreement rules it out.
        ($cr == "?" or $r == "?" or $cr == $r)
      end)
] | .[0].id // empty'

# Returns 0 with the in-flight bead's id (or an EMPTY string for "nothing is in
# flight"), and NON-ZERO when the ledger could not answer at all. The caller must
# hold on non-zero rather than dispatch: an unreadable lookup is indistinguishable
# from a clean "nothing in flight", and dispatching on it mints the twin review this
# whole function exists to prevent (review tk-thvbq finding #1).
inflight_for() { # <anchor-id> <pr-number> <branch> <anchor-repo-q>
  local aid="$1" pnum="${2:-}" br="${3:-}" arepo="${4:-}" found="" raw=""
  [ -n "$arepo" ] || arepo="?"

  # EXACT FIRST (review tk-jza6h finding #2). A bead that NAMES this anchor is about
  # this anchor — no identity question left to get wrong — so it is asked before any
  # broad surface can answer with somebody else's bead. Among several, prefer one that
  # is routed or claimed: that one can already raise the gate, and returning it holds
  # the dispatch, whereas returning a stranded sibling would re-route a SECOND
  # claimable review for one anchor.
  raw=$(bd_list_read --metadata-field anchor_bead="$aid" --status=open,in_progress) || return 2
  found=$(printf '%s' "$raw" \
    | jq -r --arg a "$aid" '[.[] | select(.id != $a)]
        | sort_by(if ((((.metadata // {})["gc.routed_to"] // "") | tostring) != "")
                     or ((((.assignee // "") | tostring) | gsub("[[:space:]]"; "")) != "")
                  then 0 else 1 end)
        | .[0].id // empty' 2>/dev/null) || return 2
  [ -n "$found" ] && { printf '%s' "$found"; return 0; }

  # THEN THE BROAD SURFACES, VALIDATED. Each returns the first row that survives
  # `INFLIGHT_OK_JQ`; a rejected row does not end the search, and no survivor in
  # either surface means nothing is in flight and a fresh signoff is dispatched.
  if [ -n "$pnum" ]; then
    raw=$(bd_list_read --metadata-field pr_number="$pnum" --status=open,in_progress) || return 2
    found=$(printf '%s' "$raw" \
      | jq -r --arg a "$aid" --arg r "$arepo" "$INFLIGHT_OK_JQ" 2>/dev/null) || return 2
  fi
  if [ -z "$found" ] && [ -n "$br" ]; then
    raw=$(bd_list_read --metadata-field branch="$br" --status=open,in_progress) || return 2
    found=$(printf '%s' "$raw" \
      | jq -r --arg a "$aid" --arg r "$arepo" "$INFLIGHT_OK_JQ" 2>/dev/null) || return 2
  fi
  printf '%s' "$found"
  return 0
}

# ...but a review that lost its ROUTE is not in flight at all — it is STRANDED, and
# believing the lookup above strands it permanently (review tk-5nxyg finding #3).
#
# `gc.routed_to` is written LAST in the dispatch below and is the single field that
# makes a review claimable. Drop that one write and the bead still exists, still open,
# still carrying task_kind=review and anchor_bead — so `inflight_for` finds it on this
# and every later pass and suppresses the replacement dispatch, while no polecat can
# ever claim it. The gate is armed, nothing can raise it, the merge is held forever,
# and nothing escalates: the dispatch counter says a signoff went out. The
# over-inclusive lookup is what makes this permanent rather than self-correcting.
#
# So the in-flight answer is REPAIRED rather than merely believed. Only the exact
# stranded shape is touched — a review for THIS anchor that is still OPEN, unclaimed
# AND unrouted. A claimed one, an in_progress one, a routed one, or somebody else's
# bead surfaced by the broad branch/pr_number lookups is left strictly alone: the dedup
# keeps its safety, and a live review is never re-routed out from under the polecat
# holding it (re-routing an in_progress bead is how one review gets worked twice). The
# re-route is verified for the same reason the original write now is: an unverified
# repair of an unverified write repairs nothing.
#
# Returns 0 only if a stranded review was found AND is now routed.
repair_review_routing() { # <review-id> <anchor-id> <pool>
  local rid="$1" aid="$2" pool="$3" rjson
  [ -n "$rid" ] && [ -n "$aid" ] && [ -n "$pool" ] || return 1
  rjson=$(gc bd show "$rid" --json 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null)
  [ -n "$rjson" ] || return 1
  printf '%s' "$rjson" | jq -e --arg a "$aid" '
    (.metadata // {}) as $m
    | ((($m.task_kind // "") | tostring) == "review")
      and ((($m.anchor_bead // "") | tostring) == $a)
      and ((($m["gc.routed_to"] // "") | tostring) == "")
      and ((((.assignee // "") | tostring) | gsub("[[:space:]]"; "")) == "")
      and ((((.status // "") | tostring) | ascii_downcase) == "open")' \
    >/dev/null 2>&1 || return 1
  gc bd update "$rid" --set-metadata gc.routed_to="$pool" >/dev/null 2>&1
  [ "$(gc bd show "$rid" --json 2>/dev/null \
        | jq -r '.[0].metadata["gc.routed_to"] // empty' 2>/dev/null)" = "$pool" ] || return 1
  return 0
}

# =============================================================================
# PR IDENTITY CERTIFICATION — asked by BOTH phases (review tk-r11wt finding #1).
# =============================================================================
# `gh pr view <n>` resolves a number in whatever repository gh considers CURRENT — a
# `gh repo set-default`, a GH_REPO in the environment, or simply a different cwd all
# move that — so a PR NUMBER is the weakest possible identifier: the same number names
# a DIFFERENT pull request in every other repository. Anything that acts on a PR
# because of its number alone can therefore act on somebody else's: phase 0 would bind
# an anchor to it, and phase 1 would read its state, refresh the record from it, and
# arm (or withhold) a gate on it.
#
# Certification answers one question — "is the PR that just answered really THIS
# bead's PR?" — and asks it of every half of the identity:
#
#   URL          right repository AND right number — compared against the bead's own
#                pr_url when it has one, normalized to `<host>/<owner>/<repo>/pull/<n>`
#   repository   the PR lives in THIS checkout's origin, not another repo's #37
#   head branch  it is opened from the branch this bead records (the right work)
#   head repo    ...and that branch is OURS. A branch NAME is owned by nobody, so a
#                fork can open a PR from a branch called exactly what the bead records
#
# Fail-closed throughout: an unreadable field, an unresolvable origin, or a mismatch is
# a refusal, never a pass. This function only ANSWERS — each caller decides the
# consequence (defer the recovery / leave the gate alone) — and names which half failed
# so an operator can repair the metadata.

# The repository every certified PR must belong to (review tk-h1ymf finding #1).
# Invariant for the pass, so it is resolved ONCE and memoized — including a FAILED
# resolution, so a pass with several candidates and no answer does not re-ask an
# unanswerable question. Resolved LAZILY (first certification, not startup) so an idle
# pass costs no work.
#
# IT COMES FROM THE CHECKOUT, NEVER FROM `gh` (review tk-5nxyg finding #1). `gh repo
# view` answers for whatever repository gh considers CURRENT — which `gh repo
# set-default`, GH_REPO, or the cwd all move — and that is the SAME source a bare
# `gh pr view <n>` resolves the number in. Asking gh for both the expectation and the
# observation makes the repository half of the identity vacuous by construction: the
# two agree because they came from one place, not because the PR is ours. Reproduced
# with origin=zookanalytics/gc-toolkit and `gh repo set-default cli/cli`: both
# `gh repo view` and `gh pr view 1` answered for cli/cli. On a pr_number-only anchor —
# the shape phase 0 itself produces, since pr_number is a field it BACKFILLS — there is
# no recorded pr_url left to catch the disagreement, so the repo AND head-repo checks
# both pass on a stranger's pull request.
#
# The origin remote is the one source gh cannot move: it is what this checkout pushes
# to, so it is what "this bead's PR" can only mean. An absent or unparseable origin is
# an UNANSWERED question, not a pass — it resolves EMPTY and certification fails closed
# on that, rather than falling back to the source this check exists to distrust.
#
# THE HOST IS PART OF THE REPOSITORY (review tk-47bij finding #1). `<owner>/<repo>` does
# not name a repository — it names one PER HOST, and `gh pr view --repo` takes
# `[HOST/]OWNER/REPO`, filling the host from GH_HOST when it is omitted (`gh help
# environment`). So a hostless `--repo o/r` under a GH_HOST pointing at another GitHub
# host reads THAT host's `o/r`, and every check below still passes: the live URL's
# owner/repo half matches, and the head repository gh reports is `o/r` there too. It is
# the same movable-source hazard as `gh repo view` (tk-5nxyg finding #1), one component
# deeper — so the host is captured from origin, passed WITH the repo to pin the read,
# and compared against the certified URL. Kept as two values on purpose: the qualified
# form is what a URL and `--repo` speak, while `headRepositoryOwner`/`headRepository`
# come back hostless and must be compared bare.
ORIGIN_HOST=""
ORIGIN_REPO=""
ORIGIN_REPO_RESOLVED=0
resolve_origin_repo() {
  if [ "$ORIGIN_REPO_RESOLVED" != 1 ]; then
    ORIGIN_REPO_RESOLVED=1
    local origin_url
    origin_url=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
    case "$origin_url" in
      git@github.com:*|https://github.com/*|ssh://git@github.com/*)
        ORIGIN_HOST="github.com"
        ORIGIN_REPO=$(printf '%s' "$origin_url" \
          | sed -e 's#^ssh://git@github.com/##' -e 's#^git@github.com:##' \
                -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    esac
    # Exactly `<owner>/<repo>`, or nothing. A half-parsed value would fail the
    # comparison below by luck rather than by design, and would report a repository
    # MISMATCH when the truth is an origin this script could not read.
    case "$ORIGIN_REPO" in
      */*/*|/*|*/) ORIGIN_REPO="" ;;
      */*)         : ;;
      *)           ORIGIN_REPO="" ;;
    esac
    [ -n "$ORIGIN_REPO" ] || ORIGIN_HOST=""
  fi
  printf '%s' "$ORIGIN_REPO"
}

# The same repository, HOST-QUALIFIED: `<host>/<owner>/<repo>`, the form `--repo` pins a
# read with and the form a pull-request URL carries. Empty whenever the bare repo is —
# an unresolved origin stays one unanswered question, not two.
#
# `resolve_origin_repo` is called DIRECTLY, never as `$(resolve_origin_repo)`: a command
# substitution runs it in a subshell, where it would set ORIGIN_HOST on a copy of this
# shell and leave the parent reading an empty host — a host-qualified name with no host,
# which fails every comparison it feeds.
resolve_origin_repo_q() {
  resolve_origin_repo >/dev/null
  [ -n "$ORIGIN_REPO" ] || { printf ''; return; }
  printf '%s/%s' "$ORIGIN_HOST" "$ORIGIN_REPO"
}

# The repository a pull-request URL names, host-qualified: `<host>/<owner>/<repo>`, or
# empty when the URL is not a parseable `/pull/<n>` URL. One definition, used by both
# identity surfaces (certification and the incumbent guards) so they cannot key on
# different halves of the same name.
url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}

# certify_pr_identity <bead-id> <pr-number> <bead-pr-url> <bead-branch> <action>
#
# <action> is a gerund naming what the caller is about to do ("restoring
# merge_result", "gating the reopened PR"); it completes every refusal below, so the
# warning says what was NOT done as well as why.
#
# Returns 0 with the certified PR's fields in CERT_STATE / CERT_BASE / CERT_URL (what
# callers need from a PR they may now trust), or 1 having explained the failure.
#
# CERT_URL is the certified identity in its DURABLE form: the normalized
# `<host>/<owner>/<repo>/pull/<n>` this read was pinned to and confirmed against. A
# caller that persists it turns a certification — true only in the process that
# performed it — into a fact the ledger carries, so a LATER process (merge-skill.sh,
# the observer) can re-derive which repository's PR#<n> this bead means without
# re-asking gh, whose idea of the current repository it does not share
# (review tk-sdqwh finding #2).
CERT_STATE=""
CERT_BASE=""
CERT_URL=""
certify_pr_identity() {
  local id="$1" num="$2" wanturl="$3" wantbranch="$4" action="$5"
  local pr_json state base liveurl head hrepo goturl wanturl_norm
  local expect_repo expect_repo_q live_repo_q
  CERT_STATE=""; CERT_BASE=""; CERT_URL=""

  if ! command -v gh >/dev/null 2>&1; then
    echo "check-set-heal: WARN $id needs PR#$num certified but gh is unavailable; not $action — retrying next pass" >&2
    return 1
  fi

  # THE EXPECTED REPOSITORY IS RESOLVED FIRST, AND IT DRIVES THE READ (review tk-5nxyg
  # finding #1). Resolving it before the PR read is not ordering pedantry: it is what
  # lets `--repo` PIN the read to this checkout's repository, so a moved gh default
  # cannot serve a foreign same-numbered PR for the checks below to bless. Unresolved
  # means the question cannot be asked at all — refuse rather than read a number in an
  # unknown repository.
  expect_repo=$(resolve_origin_repo)
  expect_repo_q=$(resolve_origin_repo_q)
  if [ -z "$expect_repo" ] || [ -z "$expect_repo_q" ]; then
    echo "check-set-heal: WARN $id cannot resolve this checkout's origin repository (no origin remote, or not a github.com <owner>/<repo> URL); PR#$num cannot be read in a known repository, let alone certified — not $action, retrying next pass" >&2
    return 1
  fi

  # HOST-QUALIFIED, so GH_HOST cannot supply a host of its own (review tk-47bij
  # finding #1). `--repo` accepts `[HOST/]OWNER/REPO`; passing the host makes the read
  # name one repository in the world rather than one per host.
  pr_json=$(gh pr view "$num" --repo "$expect_repo_q" \
    --json state,baseRefName,url,headRefName,headRepositoryOwner,headRepository 2>/dev/null)
  if [ -z "$pr_json" ]; then
    echo "check-set-heal: WARN $id PR#$num view failed; cannot confirm the PR before $action — retrying next pass" >&2
    return 1
  fi
  state=$(printf '%s' "$pr_json" | jq -r '.state // ""')
  base=$(printf '%s' "$pr_json" | jq -r '.baseRefName // ""')
  liveurl=$(printf '%s' "$pr_json" | jq -r '.url // ""')
  head=$(printf '%s' "$pr_json" | jq -r '.headRefName // ""')
  # `<owner>/<repo>` of the branch the PR is opened FROM. Assembled defensively: gh
  # returns these as objects that are null when the head repository was deleted, and a
  # half-resolved "owner/" would compare unequal by luck rather than by design. Either
  # both halves are present or the value is empty, and empty fails the guard below.
  hrepo=$(printf '%s' "$pr_json" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)

  # A partial or schema-shifted response leaves the identity UNCERTIFIED, which is
  # exactly what must not be acted on — `gh` answering is not the same as `gh`
  # answering the question (review tk-h1ymf testing gap).
  if [ -z "$state" ] || [ -z "$base" ] || [ -z "$liveurl" ] || [ -z "$head" ] \
     || [ -z "$hrepo" ]; then
    echo "check-set-heal: WARN $id PR#$num identity is unreadable (state='$state' base='$base' url='$liveurl' head='$head' headrepo='$hrepo'); cannot certify the PR before $action — retrying next pass" >&2
    return 1
  fi

  # Compare on the canonical `<host>/<owner>/<repo>/pull/<n>` form: trim whitespace,
  # trailing slashes and any sub-path (/files, /commits, #discussion). A bead whose
  # pr_url has no /pull/<n> at all cannot be normalized, so it stays as-is and
  # mismatches — which is the fail-closed direction.
  goturl=$(printf '%s' "$liveurl" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##')
  if [ -n "$wanturl" ]; then
    wanturl_norm=$(printf '%s' "$wanturl" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##')
    if [ "$wanturl_norm" != "$goturl" ]; then
      echo "check-set-heal: WARN $id records pr_url '$wanturl' but PR#$num in this repo is '$liveurl'; the number alone would bind this anchor to a DIFFERENT pull request — not $action, operator must repair the metadata" >&2
      return 1
    fi
  fi

  # The repository half of the identity, both sides of it. Neither is implied by the
  # checks above: the URL comparison is SKIPPED for a bead with no pr_url of its own
  # (a shape phase 0 itself produces, since pr_number is one of the fields it
  # backfills), and the PR's HEAD may live in a fork no matter which repo the PR
  # itself belongs to.
  #
  # `--repo "$expect_repo_q"` above already pinned the READ, so this comparison should
  # now be a tautology — and it is kept precisely because it should be. It asserts that
  # what came back is what was asked for: a gh that ignored the flag, a redirect after
  # a repository transfer or rename, or a URL this script cannot parse all show up HERE
  # as a mismatch instead of silently certifying. Defence in depth on the one check
  # whose failure hands a stranger's PR to merge-skill.
  #
  # Compared HOST-QUALIFIED, for the reason `--repo` is now qualified: `o/r` on another
  # GitHub host is a different repository that this comparison, keyed on owner/repo
  # alone, could not tell from ours — so a gh that ignored the pinned host would slip
  # through the one check meant to catch it (review tk-47bij finding #1).
  live_repo_q=$(url_repo_q "$goturl")
  if [ "$live_repo_q" != "$expect_repo_q" ]; then
    echo "check-set-heal: WARN $id PR#$num resolves to '$liveurl' in repo '${live_repo_q:-<unparseable>}', not this checkout's '$expect_repo_q'; that is another repository's pull request — not $action, operator must repair the metadata" >&2
    return 1
  fi
  if [ "$head" != "$wantbranch" ]; then
    echo "check-set-heal: WARN $id records branch '$wantbranch' but PR#$num is opened from '$head'; the bead and the PR describe different work — not $action, operator must repair the metadata" >&2
    return 1
  fi
  # ...and that branch must be OURS. A branch name is not owned by anybody: a fork can
  # open a PR from a branch called exactly what this bead records, and it would pass
  # every check above. This is the last gap between "a PR that looks like this bead's"
  # and "this bead's PR" (review tk-h1ymf finding #1).
  if [ "$hrepo" != "$expect_repo" ]; then
    echo "check-set-heal: WARN $id records branch '$wantbranch' and PR#$num is opened from a branch of that name — but in FORK '$hrepo', not '$expect_repo'; the branch name matches by coincidence, the work does not — not $action, operator must repair the metadata" >&2
    return 1
  fi

  CERT_STATE="$state"
  CERT_BASE="$base"
  # The normalized URL, not the raw one: it is what a caller persists as this bead's
  # certified identity, and the comparisons downstream must key on the same canonical
  # form this function compared on.
  CERT_URL="$goturl"
  return 0
}

# =============================================================================
# PHASE 0 — MERGE_RESULT RECOVERY: make an INVISIBLE anchor visible (tk-wsxd0).
# =============================================================================
# THE SECOND BUG, one level under the first. Everything below this block — and
# merge-skill.sh, pre-open-resolve.sh, and the observer — enumerates gating anchors
# on the `merge_result` metadata field. So an anchor missing `merge_result` ENTIRELY
# is not merely un-healed: it is INVISIBLE to the very net meant to catch it, and to
# every other pass at once. There is no pass that can see it. The failure is silent
# and unbounded — the machine reports a clean queue while a PR rots.
#
# VERIFIED LIVE CASE. shutupandlisten anchor su-uzy9.1 / PR#37. Hand-recovered, so
# it carried `branch` + `pr_url` but NO merge_result / check_set / pr_number /
# merged_target. Rig-wide the merge_result anchor set was EMPTY — nothing to act on.
# PR#37 sat OPEN for 6 days with zero escalations and would have sat indefinitely.
# Note it was also TRACKED as far as the observer's anchorless PR->bead scan was
# concerned (a live bead named the PR, and it carried `branch`, so it read as
# "owned") — which is why that scan's silence was correct and useless here.
#
# THE PREDICATE MUST SURVIVE THE DAMAGE. The repair cannot key on the field whose
# absence it exists to repair, so this phase enumerates on `--has-metadata-key
# pr_url` / `pr_number` — a bead the refinery already canonicalized a PR onto — and
# keeps only those with NO merge_result. `pr_url`/`pr_number` are stamped by the
# refinery only AFTER it validates the PR, so their presence is durable evidence
# that this bead is past the polecat stage and a PR exists for it. (`existing_pr`
# is deliberately NOT in the predicate: a caller sets it BEFORE dispatch, so it
# proves nothing about the refinery having adopted the PR.)
#
# WHY THIS RUNS FIRST. A merge_result stamped here lands BEFORE the check_set heal
# below enumerates, so a recovered anchor is gated in the SAME pass rather than
# waiting a wake — and before pre-open-resolve, merge-skill and the observer run
# later in the formula's find-work loop. Recovery, gating and disposition converge
# on one pass.
#
# WHAT IT WILL NOT TOUCH (each exclusion is a real hazard, not caution):
#   - a REWORK/REVIEW CHILD. merge-skill.sh's in-flight hold counts exactly "open,
#     references the PR, NO merge_result" — so stamping merge_result on a child
#     would SILENTLY RELEASE the hold and land a PR mid-rework. Children are
#     excluded five ways (anchor_bead / task_kind / source_review_bead /
#     source_anchor_bead / a non-empty gc.routed_to), and then a one-anchor-per-PR
#     guard skips any candidate whose PR is already claimed by another open
#     merge_result-carrying bead (tk-ynz4b). `source_anchor_bead` is the marker
#     reconcile-merged-prs.sh stamps on a STALE-BASE rebase child (branch + pr_url +
#     pr_number + no merge_result — the candidate shape exactly), and routing alone
#     does not exclude it: gc.routed_to is CLEARED when a polecat claims the child,
#     so between a claim and its hand-back the child wears the anchor shape with no
#     routing left to disqualify it (tk-zl932 / review tk-ej3wq finding #3).
#   - AMBIGUITY. Two surviving candidates naming the same PR means we cannot tell
#     which is the anchor; both are skipped and reported. Fail closed — a wrong
#     anchor is worse than a visible stall.
#   - LIVE POLECAT WIP. Pool-routed or polecat-assigned beads are excluded; a bead
#     between hand-off and the refinery's own merge-push step has no pr_url yet, so
#     the predicate never preempts the refinery's own decision.
#   - PRE-OPEN. A pre_open_gate anchor has a branch and no PR, which is
#     indistinguishable from ordinary in-flight work — there is no damage-surviving
#     evidence to key on, so it is out of scope by design rather than guessed at.
#
# A FAILED STAMP IS NOT UNSAFE_RC; A SUCCESSFUL ONE CAN BE. The two directions are
# not symmetric. A merge_result stamp that does NOT persist leaves the anchor
# INVISIBLE, which means merge-skill.sh cannot merge it either — the stalled status
# quo, not an ungated merge — so this phase warns, flags once, and retries. But a
# stamp that DOES persist has handed a live anchor to merge-skill.sh, and if phase 1
# then fails to gate it (a dropped enumeration, a check_set stamp that did not
# stick), the pass has actively CREATED the ungated-merge window it exists to close.
# That case exits UNSAFE_RC, enforced two ways: an empty phase-1 enumeration despite
# a recovery, and a post-loop re-read of every anchor recovered here.
#
# WHICH IS WHY THE WRITE IS ORDERED, NOT ATOMIC. That asymmetry is a rule about ONE
# field, and it generalizes: `merge_result` is the switch that exposes the bead, and
# several OTHER fields are what the passes it exposes the bead to then depend on
# (pr_number, merged_target, merge_result_healed, merge_result_pr_state). A partial
# write that lands the switch but drops a dependent produces a live anchor missing a
# protection that nothing will ever restore — the bead now HAS a merge_result, so it
# is no longer a candidate here. Worst case is merged_target: merge-skill.sh's
# retarget guard SKIPS on an empty value rather than failing on it, so the anchor
# merges with no retarget protection at all. So the dependents are written and
# verified FIRST and visibility is flipped only once they are durable; a dependent
# that will not stick leaves the bead invisible and retried, which is the stall we
# already had rather than a new exposure (tk-b0e5y / review tk-lgpyg findings #1, #4).
recovered=0; recover_skipped=0; noncanon=0
RECOVERED_INERT=""   # ids whose PR is already MERGED/CLOSED — visibility only, no gate
RECOVERED_OPEN=""    # ids made visible THIS pass whose PR is OPEN — phase 1 MUST gate them

# --limit=0 (unbounded). A candidate past a cap is an INVISIBLE anchor that stays
# invisible — exactly the silent, unbounded stall this phase exists to end. Same
# reasoning as the merge skill's in-flight-rework probe, and the same reasoning that
# made phase 1's gating enumeration unbounded too (review tk-47bij finding #3).
#
# EVERY SCAN MUST ANSWER, OR THE PHASE DOES NOT RUN. A scan that FAILED and a scan
# that found NOTHING both yield an empty result, but they mean opposite things, and
# the difference is load-bearing here: the ambiguity guard below is a WHOLE-SET
# property. It can only see that two candidates name the same PR if BOTH are in the
# set. Drop one scan and the set shrinks silently — two merge_result-less candidates
# for one PR (one carrying only pr_url, the other only pr_number) collapse to one
# apparently-unambiguous candidate, and it gets PROMOTED. The incumbent guard does
# not catch this: neither rival carries a merge_result, so neither reads as an
# incumbent anchor. So an unreadable scan skips the WHOLE phase for the pass rather
# than recovering from a partial view — a deferred repair is a stall, a wrong anchor
# on a live PR is not (tk-b0e5y / review tk-lgpyg finding #3).
RECOVER_RAW=""
RECOVER_SCAN_OK=1
for KEY in pr_url pr_number; do
  # Guarded: the exit status counts too. A scan that DIED after emitting a
  # well-formed (short or empty) array passes a shape test and reads as a complete
  # scan, which is exactly the partial candidate set this whole block refuses to act
  # on (review tk-thvbq finding #1).
  if ! R=$(bd_list_read --status=open --has-metadata-key "$KEY"); then
    echo "check-set-heal: WARN the '$KEY' recovery scan did not return a readable result; the candidate set would be PARTIAL and the ambiguity guard cannot see a duplicate it never scanned — skipping merge_result recovery this pass, retrying next" >&2
    RECOVER_SCAN_OK=0
    break
  fi
  [ "$R" != "[]" ] || continue
  if [ -z "$RECOVER_RAW" ]; then RECOVER_RAW="$R"; else RECOVER_RAW="$RECOVER_RAW
$R"; fi
done

CANDS=""
if [ "$RECOVER_SCAN_OK" = 1 ] && [ -n "$RECOVER_RAW" ]; then
  # unique_by(.id) folds the two key queries into one candidate set. Every
  # exclusion below is applied to the METADATA, not the title, so a bead cannot
  # dress its way in or out of the anchor class.
  CANDS=$(printf '%s\n' "$RECOVER_RAW" | jq -s -c '
    ((add // []) | unique_by(.id))[]
    | . as $b | (($b.metadata // {})) as $m
    | select((($m.merge_result // "") | tostring | ascii_downcase | gsub("[[:space:]]"; "")) == "")
    | select(((($m.pr_url // "") | tostring) != "") or ((($m.pr_number // "") | tostring) != ""))
    | select((($m.branch // "") | tostring) != "")
    | select((($m.anchor_bead // "") | tostring) == "")
    | select((($m.task_kind // "") | tostring) == "")
    | select((($m.source_review_bead // "") | tostring) == "")
    | select((($m.source_anchor_bead // "") | tostring) == "")
    | select((($m["gc.routed_to"] // "") | tostring) == "")
    # merged_target/target resolved with an EMPTY-AWARE fallback, never `//`. jq
    # `//` treats only null/false as absent, so a merged_target="" left by a partial
    # write would SHADOW a recorded target and drop the resolution through to the
    # PR live base below — silently blessing a retarget that happened while the
    # anchor was invisible (tk-zl932 / review tk-ej3wq finding #5).
    | ((($m.merged_target // "") | tostring)) as $mt
    | ((($m.target // "") | tostring)) as $tg
    | {
        id,
        assignee: (($b.assignee // "") | tostring),
        title:    (($b.title // "") | tostring),
        pr:       (($m.pr_number // "") | tostring),
        prurl:    (($m.pr_url // "") | tostring),
        branch:   (($m.branch // "") | tostring),
        mtarget:  $mt,
        target:   (if $mt != "" then $mt else $tg end),
        flagged:  (($m.merge_result_heal_flagged // "") | tostring)
      }' 2>/dev/null) || {
    # Same rule as an unreadable scan: a projection that ERRORED yields the same
    # empty string as "no candidates survived the exclusions", and acting on it
    # would evaluate an arbitrary subset of the real candidate set
    # (tk-b0e5y / review tk-lgpyg finding #3).
    echo "check-set-heal: WARN the recovery candidate projection failed; the candidate set is unreliable — skipping merge_result recovery this pass, retrying next" >&2
    CANDS=""
  }
fi

# THIS CHECKOUT'S OWN REPOSITORY, host-qualified — the repository a PR must live in
# when the bead naming it records no pr_url of its own, and therefore the second half
# of every "which PR is this?" answer below.
#
# Resolved ONCE, UNCONDITIONALLY, for the whole pass. Both phases key identity on it —
# phase 0's candidate rows, phase 1's in-flight dedup — so it cannot live inside either
# one's `if`: under `set -u` phase 1 would then die on an unbound variable in any pass
# that found no candidates, and without `set -u` it would silently degrade to the `?`
# wildcard and un-qualify the dedup exactly when phase 0 was quiet.
#
# `resolve_origin_repo_q` is called here rather than per row because the command
# substitutions below run in subshells, where the memoization inside
# `resolve_origin_repo` cannot reach this shell.
PASS_ORIGIN_REPO_Q=$(resolve_origin_repo_q)

# Pass 0a — resolve each candidate's PR number (backfilling it from pr_url when the
# recovery dropped pr_number, as the live case did) and drop the unidentifiable.
# merge-skill.sh SKIPS any anchor with an empty pr_number, so restoring merge_result
# without the number would produce a "visible" anchor that still never merges.
CAND_NORM=""
if [ -n "$CANDS" ]; then
  while IFS= read -r crow; do
    [ -n "${crow:-}" ] || continue
    cid=$(printf '%s' "$crow" | jq -r '.id // empty')
    [ -n "$cid" ] || continue
    cprurl=$(printf '%s' "$crow" | jq -r '.prurl // empty')
    cnum=$(printf '%s' "$crow" | jq -r '.pr // empty')
    if [ -z "$cnum" ]; then
      cnum=$(printf '%s' "$cprurl" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p')
    fi
    if [ -z "$cnum" ]; then
      echo "check-set-heal: WARN $cid has no merge_result and no resolvable PR number; cannot restore visibility" >&2
      recover_skipped=$((recover_skipped + 1)); continue
    fi
    # WHICH REPOSITORY'S PR#<n> THIS CANDIDATE NAMES — resolved HERE, once, and carried
    # on the row, so the ambiguity guard and both incumbent guards below all key on the
    # SAME name and cannot disagree about which PR this candidate is (review tk-jza6h
    # finding #1). From its own pr_url when it has one; otherwise the repository
    # certification will REQUIRE the PR to live in, which is this checkout's origin.
    # Unresolvable on either side is `?`, the fail-closed wildcard: a candidate whose
    # repository cannot be named cannot be shown to be a DIFFERENT PR from anything.
    crepo=$(url_repo_q "$cprurl")
    [ -n "$crepo" ] || crepo="$PASS_ORIGIN_REPO_Q"
    [ -n "$crepo" ] || crepo="?"
    crow=$(printf '%s' "$crow" | jq -c --arg n "$cnum" --arg r "$crepo" '. + {num: $n, repo: $r}' 2>/dev/null)
    [ -n "$crow" ] || { recover_skipped=$((recover_skipped + 1)); continue; }
    if [ -z "$CAND_NORM" ]; then CAND_NORM="$crow"; else CAND_NORM="$CAND_NORM
$crow"; fi
  done <<< "$CANDS"
fi

# Ambiguity guard: the same PR named by more than one surviving candidate. Nothing
# here can tell which is the real anchor, and picking wrong mints a second anchor
# for a live PR (tk-ynz4b). Skip every candidate of such a PR and say so.
#
# KEYED ON REPOSITORY **AND** NUMBER, like every other identity surface in this phase
# (review tk-jza6h finding #1). A pull number is unique only within a repository and
# this city's ledger spans rigs with different ones, so grouping on the bare number
# makes a damaged candidate for `otherhost/o/OTHER#745` a "duplicate" of THIS repo's
# `#745` — and this guard runs FIRST, before `crepo` was even derived and before the
# repository-aware incumbent checks that would have told them apart. Both are then
# skipped every pass, so the real anchor's recovery is blocked indefinitely by a bead
# from another repository: the same false-incumbent stall tk-5nxyg and tk-47bij closed
# on the two incumbent surfaces, still open on this one.
#
# `?` (an unnameable repository) is the wildcard and matches ANY repository — the
# fail-closed direction, and exactly the number-only behaviour it replaces: a candidate
# that MIGHT name the same PR still makes the pair ambiguous. Only a POSITIVE, parsed
# disagreement separates them.
#
# The result is a set of candidate IDs, not numbers: with the key repository-qualified,
# "this number is ambiguous" is no longer a property of the number alone — two rows can
# share a number and still be unambiguous, so each row is judged against the rows it
# actually collides with.
DUP_CAND=""
if [ -n "$CAND_NORM" ]; then
  DUP_CAND=$(printf '%s\n' "$CAND_NORM" \
    | jq -rs '. as $all
        | [ $all[]
            | . as $c
            | select([ $all[]
                       | select(.id != $c.id)
                       | select(.num == $c.num)
                       | select(.repo == "?" or $c.repo == "?" or .repo == $c.repo) ]
                     | length > 0)
            | .id ]
        | .[]' 2>/dev/null) || {
    # Same rule as a failed candidate projection: a collision check that ERRORED yields
    # the same empty string as "nothing collides", and believing it would promote one of
    # two indistinguishable candidates to anchor. The whole recovery defers a pass.
    echo "check-set-heal: WARN the duplicate-candidate check failed; ambiguous candidates cannot be ruled out — skipping merge_result recovery this pass, retrying next" >&2
    CAND_NORM=""
  }
fi

# THE REPOSITORY EVERY RECOVERED PR MUST BELONG TO (review tk-h1ymf finding #1) is
# resolved by `resolve_origin_repo` above, lazily and once per pass, and enforced by
# `certify_pr_identity` — the shared certification both phases call. Phase 0 recreates
# a damaged anchor, so it owes the same identity check the normal post-open validation
# (mol-refinery-patrol.toml) performs, or a recovery binds an anchor to a fork's PR and
# merge-skill later merges somebody else's code under this bead.

# INCUMBENT ANCHORS IDENTIFIED BY URL, NOT ONLY BY NUMBER (review tk-h1ymf finding #2).
# The one-anchor-per-PR guard below asks "does an OPEN anchor already own this PR?" and
# asked it only of `pr_number`. But phase 0 exists precisely because a damaged anchor
# can be missing fields, and `pr_number` is one of the fields it BACKFILLS — so an
# incumbent that kept merge_result and pr_url but lost pr_number is a mechanically
# reachable shape, and it is invisible to a pr_number-keyed lookup. The candidate then
# passes the guard, gets stamped WITH a pr_number, and becomes the only numbered anchor
# merge-skill.sh can see (it skips anchors without one) — a second anchor driving the PR
# while the original is stranded, which is exactly what tk-ynz4b forbids.
#
# So the incumbent lookup uses the SAME identity surface as recovery: number OR
# normalized pr_url. Scanned once per pass; the `/pull/<n>` normalization mirrors pass
# 0a's, so a sub-path URL (/files) resolves identically on both sides. Unreadable scan
# => the question is unanswered => fail closed below.
#
# INDEXED BY REPOSITORY *AND* NUMBER, not by number alone (review tk-5nxyg finding #2).
# A pull number is only unique within a repository, and this city's ledger spans rigs
# with different ones. Keyed on the bare number, an open anchor for
# `https://github.com/o/OTHER/pull/745` blocks recovery of THIS repo's
# `https://github.com/o/r/pull/745` — a false incumbent, refusing a real repair with a
# warning naming a bead that has nothing to do with it, and doing so BEFORE PR identity
# certification (which would have caught the confusion) ever runs. That is the silent
# stall this whole phase exists to end, reintroduced one identity field short.
#
# A URL whose repository cannot be parsed is recorded as `?` and matches ANY repository
# — the fail-closed direction, and exactly the number-only behaviour it replaces: an
# incumbent that might own this PR still blocks. Only a POSITIVE, parsed disagreement
# clears the way.
INCUMBENT_URL_SCAN_OK=1
INCUMBENT_URL_MAP=""
if [ -n "$CAND_NORM" ]; then
  # Guarded (exit status included): a scan that failed after emitting an array
  # would read as "no URL-keyed incumbent exists" and promote a candidate to
  # anchor on a question the ledger never answered (review tk-thvbq finding #1).
  if ! INC_RAW=$(bd_list_read --status=open,in_progress --has-metadata-key pr_url); then
    INCUMBENT_URL_SCAN_OK=0
  else
    INCUMBENT_URL_MAP=$(printf '%s' "$INC_RAW" | jq -r '.[]
      | . as $b | (($b.metadata // {})) as $m
      | select((($m.merge_result // "") | tostring | ascii_downcase | gsub("[[:space:]]"; "")) != "")
      | (($m.pr_url // "") | tostring) as $u
      | ($u | sub("^.*/pull/"; "") | sub("[^0-9].*$"; "")) as $n
      | select($n != "")
      # Host-qualified, matching url_repo_q / resolve_origin_repo_q: `o/r` on another
      # GitHub host is a different repository, and a key that cannot say so would read
      # its PR#<n> as the incumbent for ours (review tk-47bij finding #1).
      | ([$u | capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<r>[^/]+/[^/]+)/pull/[0-9]")]
          | .[0]) as $c
      | (if $c == null then "?" else ($c.h + "/" + $c.r) end) as $r
      | [(($b.id // "") | tostring), $r, $n] | @tsv' 2>/dev/null) || INCUMBENT_URL_SCAN_OK=0
  fi
fi

if [ -n "$CAND_NORM" ]; then
  while IFS= read -r crow; do
    [ -n "${crow:-}" ] || continue
    cid=$(printf '%s' "$crow" | jq -r '.id // empty')
    [ -n "$cid" ] || continue
    cnum=$(printf '%s' "$crow" | jq -r '.num // empty')
    cassignee=$(printf '%s' "$crow" | jq -r '.assignee // empty')
    cbranch=$(printf '%s' "$crow" | jq -r '.branch // empty')
    ctarget=$(printf '%s' "$crow" | jq -r '.target // empty')
    cmtarget=$(printf '%s' "$crow" | jq -r '.mtarget // empty')
    crawpr=$(printf '%s' "$crow" | jq -r '.pr // empty')
    cprurl=$(printf '%s' "$crow" | jq -r '.prurl // empty')
    cflagged=$(printf '%s' "$crow" | jq -r '.flagged // empty')
    # The repository this candidate's PR#<n> lives in — resolved once in pass 0a and
    # carried on the row, so the ambiguity guard below and both incumbent guards ask
    # the same question of the same name. `?` is the unnameable-repository wildcard.
    crepo=$(printf '%s' "$crow" | jq -r '.repo // empty')
    [ -n "$crepo" ] || crepo="?"

    if [ -n "$DUP_CAND" ] && printf '%s\n' "$DUP_CAND" | grep -qxF "$cid"; then
      echo "check-set-heal: WARN PR#$cnum in '$crepo' has MULTIPLE merge_result-less candidates (including $cid); cannot identify the anchor — skipping all, operator must disambiguate" >&2
      recover_skipped=$((recover_skipped + 1)); continue
    fi

    # Not a polecat's live work. An empty assignee is the canonical gating shape;
    # a refinery-ish one is the hand-recovered shape the live case wore. Anything
    # else is somebody's in-flight bead and must not be enrolled as an anchor.
    case "$(printf '%s' "$cassignee" | tr '[:upper:]' '[:lower:]')" in
      "")       : ;;
      *refinery*) : ;;
      *)
        recover_skipped=$((recover_skipped + 1)); continue ;;
    esac

    # One-anchor-per-PR (tk-ynz4b). If another OPEN bead already carries a
    # merge_result for this PR, the anchor exists and this candidate is a child or
    # a duplicate — stamping it would both mint a second anchor AND cancel the
    # in-flight-rework hold that merge-skill.sh derives from its empty merge_result.
    #
    # KEYED ON REPOSITORY **AND** NUMBER, on both incumbent surfaces. Pull numbers are
    # unique only within a repository and this city's ledger spans rigs with different
    # ones, so the bare number is not the identity of a PR. Qualifying only the pr_url
    # surface left this one — the pr_number lookup — reading another repository's #<n>
    # as the owner of ours and refusing a real repair before certification, which would
    # have caught the confusion, ever ran (review tk-47bij finding #2; same defect as
    # tk-5nxyg finding #2, on the surface that fix did not reach).
    #
    # The lookup must FAIL CLOSED. A failed `gc bd list` (or a jq error) yields the
    # same empty string as a clean "no incumbent", so reading emptiness as proof of
    # absence would promote a child to anchor on any transient ledger hiccup — the
    # one-anchor-per-PR guard would silently not apply. `bd_list_read` validates
    # the EXIT STATUS as well as the payload shape: a read that died after emitting
    # a short array is the same unanswered question as one that emitted nothing, and
    # a shape test alone cannot tell them apart (tk-zl932 / review tk-ej3wq testing
    # gap: incumbent-lookup failure; review tk-thvbq finding #1: the rc half).
    if ! INCUMBENT_RAW=$(bd_list_read --metadata-field pr_number="$cnum" \
      --status=open,in_progress); then
      echo "check-set-heal: WARN $cid incumbent-anchor lookup for PR#$cnum failed (ledger unreadable); cannot rule out an existing anchor — skipping, retrying next pass" >&2
      recover_skipped=$((recover_skipped + 1)); continue
    fi
    OTHER_ANCHOR=$(printf '%s' "$INCUMBENT_RAW" \
      | jq -r --arg me "$cid" --arg r "$crepo" '[.[]
          | select(.id != $me)
          | select(((.metadata.merge_result // "") | tostring) != "")
          # The repository of the incumbent itself, read from its pr_url exactly as the
          # candidate repo above was. An incumbent with no pr_url cannot be placed in a
          # repository at all, so it stays `?` and blocks — the fail-closed direction,
          # and the shape phase 0 itself produces before it backfills.
          | ((.metadata.pr_url // "") | tostring) as $u
          | ([$u | capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<r>[^/]+/[^/]+)/pull/[0-9]")]
              | .[0]) as $c
          | (if $c == null then "?" else ($c.h + "/" + $c.r) end) as $ir
          | select($ir == "?" or $r == "?" or $ir == $r)] | .[0].id // empty' 2>/dev/null)
    if [ -n "$OTHER_ANCHOR" ]; then
      recover_skipped=$((recover_skipped + 1)); continue
    fi
    # The other half of the same question, asked of the URL surface. Same fail-closed
    # rule: an unreadable scan cannot rule out a URL-only incumbent, and promoting a
    # candidate on an unanswered question is what mints the second anchor
    # (review tk-h1ymf finding #2).
    if [ "$INCUMBENT_URL_SCAN_OK" != 1 ]; then
      echo "check-set-heal: WARN $cid incumbent-anchor scan by pr_url failed (ledger unreadable); an anchor that owns PR#$cnum by URL alone cannot be ruled out — skipping, retrying next pass" >&2
      recover_skipped=$((recover_skipped + 1)); continue
    fi

    # Same `$crepo` the numbered guard above keyed on — one repository name, asked of
    # both incumbent surfaces, so the two cannot disagree about which PR this is.
    OTHER_URL_ANCHOR=""
    if [ -n "$INCUMBENT_URL_MAP" ]; then
      OTHER_URL_ANCHOR=$(printf '%s\n' "$INCUMBENT_URL_MAP" \
        | awk -F'\t' -v n="$cnum" -v me="$cid" -v r="$crepo" \
            '$3 == n && $1 != me && ($2 == "?" || r == "?" || $2 == r) { print $1; exit }')
    fi
    if [ -n "$OTHER_URL_ANCHOR" ]; then
      echo "check-set-heal: WARN $cid names PR#$cnum in '$crepo' but $OTHER_URL_ANCHOR already anchors it by pr_url (no pr_number of its own); refusing to mint a second anchor (tk-ynz4b)" >&2
      recover_skipped=$((recover_skipped + 1)); continue
    fi

    # CERTIFY THE PR'S IDENTITY BEFORE BINDING AN ANCHOR TO IT (tk-b0e5y / review
    # tk-lgpyg finding #2). Everything above establishes that this BEAD is a plausible
    # candidate; nothing yet establishes that the PR its metadata names is really its
    # PR. Binding wrong is not a stall: the anchor becomes visible, gets gated, and
    # merge-skill merges SOMEBODY ELSE'S PR on this bead's behalf — and the very
    # metadata that named it is, by construction, damaged (that is why merge_result is
    # missing at all). So every half of the identity is confirmed against what `gh`
    # actually returned, fail-closed on any mismatch or unreadable field; an operator
    # repairs the metadata and the next pass recovers normally.
    #
    # This also reads what the repair needs from the certified PR: the base to backfill
    # merged_target (what merge-skill.sh validates the live base against and what the
    # observer's retarget arm compares — restoring merge_result without it would make
    # the anchor visible but unprotected against a retarget), and the state that decides
    # whether the recovered anchor is gated or left for the observer.
    if ! certify_pr_identity "$cid" "$cnum" "$cprurl" "$cbranch" "restoring merge_result"; then
      recover_skipped=$((recover_skipped + 1)); continue
    fi
    cstate="$CERT_STATE"
    cbase="$CERT_BASE"

    echo "check-set-heal: $cid carries PR#$cnum (state $cstate, branch $cbranch) but NO merge_result — INVISIBLE to every heal, merge and reconcile pass; restoring gating visibility (tk-wsxd0)"

    # ---- WRITE 1 of 2: THE DEPENDENTS, BEFORE THE FIELD THAT EXPOSES THE ANCHOR ---
    # `merge_result` is not just another field: it is the SWITCH that makes this bead
    # visible to merge-skill.sh, pre-open-resolve.sh, the observer and phase 1 below.
    # Every other field here is something one of those passes then DEPENDS ON. So the
    # dependents are written and VERIFIED first, and visibility is flipped only once
    # they are durable. Writing them together and hoping is what let a partial write
    # produce a visible anchor with a missing dependent — and the directions are not
    # symmetric: a dependent that fails to land while the bead stays INVISIBLE is the
    # stalled status quo (nothing can merge it), whereas one that fails to land AFTER
    # the switch is thrown is a live anchor missing a protection nobody will restore,
    # because the bead now has a merge_result and is no longer a phase-0 candidate.
    # Ordering the writes converts an unrepeatable exposure into a repeatable retry
    # (tk-b0e5y / review tk-lgpyg findings #1 and #4). Each dependent, and what
    # silently breaks downstream if it is missing:
    #
    #   pr_number             merge-skill.sh SKIPS an anchor without one: visible,
    #                         never merged — the same unbounded stall, one field in.
    #   pr_url                THE CERTIFIED IDENTITY, made durable (review tk-sdqwh
    #                         finding #2). Certification happens HERE, in a process
    #                         whose gh repository context is its own; merge-skill.sh
    #                         and the observer act on the anchor LATER, in processes
    #                         that do not inherit it. A pr_number-only anchor — the
    #                         shape this phase itself produces, since pr_number is a
    #                         field it BACKFILLS — hands them a bare number, which is
    #                         precisely the identifier certification exists to
    #                         distrust: a moved gh default or GH_HOST makes it name a
    #                         stranger's PR again, and nothing downstream would have
    #                         anything to compare against. Backfilling the certified
    #                         URL means the identity this phase established is the
    #                         identity they can re-check, rather than one that expired
    #                         with this process.
    #   merged_target         merge-skill.sh's retarget guard is `[ -n "$target" ] &&
    #                         [ -n "$base" ] && [ "$target" != "$base" ]`, so an EMPTY
    #                         merged_target does not fail the check — it SKIPS it. The
    #                         anchor then merges with no retarget protection at all,
    #                         onto whatever base the PR now points at. This is the one
    #                         dependent whose loss is not a stall but a wrong merge.
    #   merge_result_healed   keeps a recovered anchor in phase 1's satisfiability
    #                         path even when its check_set already reads normal;
    #                         without it the anchor takes the "already normalized"
    #                         exit forever while merge-skill holds on a check.codex
    #                         nothing was ever dispatched to stamp.
    #   merge_result_pr_state persists what `gh` just told us about the PR, so the
    #                         MERGED/CLOSED skip survives the pass instead of living
    #                         only in this run's RECOVERED_INERT; without it a later
    #                         pass arms codex and dispatches a signoff for a PR nobody
    #                         can merge. Phase 1 RE-CHECKS it against live `gh` before
    #                         honouring it, so a REOPENED PR is gated rather than
    #                         suppressed forever by a stale record.
    DEP_ARGS=(--set-metadata merge_result_healed=pull_request
              --set-metadata merge_result_pr_state="$cstate")
    BACKFILLED=""
    if [ -z "$crawpr" ]; then
      DEP_ARGS+=(--set-metadata pr_number="$cnum")
      BACKFILLED="$BACKFILLED, backfilled pr_number=$cnum"
    fi
    # The certified URL, persisted when the anchor has none of its own. Written from
    # CERT_URL — what the pinned read actually returned and every identity half was
    # confirmed against — never assembled from the number and a repository name, which
    # would record a guess in the field downstream passes trust.
    if [ -z "$cprurl" ] && [ -n "$CERT_URL" ]; then
      DEP_ARGS+=(--set-metadata pr_url="$CERT_URL")
      BACKFILLED="$BACKFILLED, backfilled pr_url=$CERT_URL"
    fi
    # merged_target — NOT `target` — is what merge-skill.sh validates the live base
    # against and what the observer's retarget arm compares, so the backfill keys on
    # merged_target being absent even when a plain `target` survived. Prefer that
    # recorded intent over the live base: taking the live base would silently BLESS a
    # retarget that happened while the anchor was invisible, which is precisely the
    # window in which one could have gone unnoticed.
    if [ -z "$cmtarget" ]; then
      FILL="$ctarget"; [ -n "$FILL" ] || FILL="$cbase"
      if [ -n "$FILL" ]; then
        DEP_ARGS+=(--set-metadata merged_target="$FILL")
        BACKFILLED="$BACKFILLED, backfilled merged_target=$FILL"
      fi
    fi
    gc bd update "$cid" "${DEP_ARGS[@]}" >/dev/null 2>&1

    # Verify EVERY dependent, and treat any miss as a failed recovery — not a warning
    # on an anchor that has already been exposed. The bead is still invisible at this
    # point, so a miss costs one more pass of an existing stall and nothing else; the
    # candidate predicate (merge_result absent) still matches, so the next pass simply
    # retries the same idempotent write. That is what "retry until durable" means here
    # (tk-b0e5y / review tk-lgpyg findings #1 and #4).
    VERIFY=$(gc bd show "$cid" --json 2>/dev/null | jq -c '.[0].metadata // {}' 2>/dev/null)
    MISSING=""
    GOT_PR=$(printf '%s' "$VERIFY" | jq -r '.pr_number // empty' 2>/dev/null)
    [ "$GOT_PR" = "$cnum" ] || MISSING="$MISSING pr_number(have '${GOT_PR:-<empty>}')"
    # Verified like every other dependent: an anchor exposed with a bare number is the
    # exact shape that lets a moved gh default serve merge-skill a foreign PR, and
    # nothing repairs it afterwards — the bead is no longer a phase-0 candidate. One
    # more pass of an existing stall is the cheap side of that trade.
    GOT_URL=$(printf '%s' "$VERIFY" | jq -r '.pr_url // empty' 2>/dev/null)
    [ -n "$GOT_URL" ] || MISSING="$MISSING pr_url(unresolved or unwritten)"
    GOT_TGT=$(printf '%s' "$VERIFY" | jq -r '.merged_target // empty' 2>/dev/null)
    [ -n "$GOT_TGT" ] || MISSING="$MISSING merged_target(unresolved or unwritten)"
    GOT_HEALED=$(printf '%s' "$VERIFY" | jq -r '.merge_result_healed // empty' 2>/dev/null)
    [ "$GOT_HEALED" = "pull_request" ] || MISSING="$MISSING merge_result_healed(have '${GOT_HEALED:-<empty>}')"
    GOT_STATE=$(printf '%s' "$VERIFY" | jq -r '.merge_result_pr_state // empty' 2>/dev/null)
    [ "$GOT_STATE" = "$cstate" ] || MISSING="$MISSING merge_result_pr_state(have '${GOT_STATE:-<empty>}')"
    if [ -n "$MISSING" ]; then
      echo "check-set-heal: WARN $cid cannot be restored yet — required field(s) did not persist:$MISSING. Leaving PR#$cnum INVISIBLE rather than visible-without-them (a visible anchor missing merged_target merges with NO retarget guard, one missing pr_number never merges at all, and one missing pr_url reaches merge-skill as a bare NUMBER with no certified identity to check it against) — retrying next pass" >&2
      if [ -z "$cflagged" ]; then
        gc bd update "$cid" --set-metadata merge_result_heal_flagged=1 >/dev/null 2>&1 || true
      fi
      recover_skipped=$((recover_skipped + 1)); continue
    fi

    # ---- WRITE 2 of 2: VISIBILITY. Every dependent is durable; throw the switch. ---
    gc bd update "$cid" --set-metadata merge_result=pull_request \
      --append-notes "check-set-heal: merge_result was ABSENT while the bead carried PR#$cnum, so this anchor was invisible to merge-skill, pre-open-resolve, the observer and this heal alike — no pass could see it. Restored merge_result=pull_request$BACKFILLED so the PR is driven again (tk-wsxd0)." \
      >/dev/null 2>&1

    GOT=$(gc bd show "$cid" --json 2>/dev/null | jq -r '.[0].metadata.merge_result // empty' 2>/dev/null)
    if [ "$GOT" != "pull_request" ]; then
      echo "check-set-heal: WARN $cid merge_result stamp did NOT persist (have '${GOT:-<empty>}'); PR#$cnum stays invisible — retrying next pass" >&2
      if [ -z "$cflagged" ]; then
        gc bd update "$cid" --set-metadata merge_result_heal_flagged=1 >/dev/null 2>&1 || true
      fi
      recover_skipped=$((recover_skipped + 1)); continue
    fi
    recovered=$((recovered + 1))

    # A PR that is already MERGED or CLOSED needs VISIBILITY, not a gate: the
    # observer closes it or escalates the out-of-band close. Arming codex and
    # dispatching a signoff for a PR nobody can merge would be pure noise, so the
    # check_set heal below skips these. RECOVERED_OPEN is the converse and is the
    # stronger claim: this anchor is now VISIBLE to merge-skill.sh with an OPEN PR,
    # so phase 1 MUST reach it and gate it on THIS pass — the post-loop verification
    # holds the merge if it did not (tk-zl932 / review tk-ej3wq finding #2).
    if [ "$cstate" != "OPEN" ]; then
      RECOVERED_INERT="$RECOVERED_INERT$cid
"
    else
      RECOVERED_OPEN="$RECOVERED_OPEN$cid
"
    fi
  done <<< "$CAND_NORM"
fi

if [ "$recovered" -gt 0 ] || [ "$recover_skipped" -gt 0 ]; then
  echo "check-set-heal: merge_result recovery — $recovered anchor(s) restored to visible gating, $recover_skipped skipped"
fi

# Both gating sub-states, in one row stream. `has("check_set")` is folded into the
# emitted value: an ABSENT key and an empty one are the same "never normalized"
# condition, so both canonicalize to empty below. Anchors recovered in phase 0 are
# already stamped, so this enumeration picks them up in the SAME pass.
#
# --limit=0 (unbounded), where this scan once took the first 200. PHASE 0 IS WHAT MADE
# THE CAP UNSAFE (review tk-47bij finding #3). While every anchor here was already
# visible, a bead past the cap was merely DEFERRED to a later pass — a page boundary
# cost latency and nothing else. Phase 0 changed that: an anchor it recovers is visible
# to merge-skill NOW and its signoff is dispatched by THIS enumeration and no other, so
# one past the cap is a live anchor with an armed gate nothing was ever dispatched to
# raise — a held merge with no dispatch and no escalation, the same silent unbounded
# stall one level up. Worse, it is invisible to the post-loop check below when its
# check_set already reads normal (the CSNORMAL shape), which is exactly the shape
# `merge_result_healed` exists to keep flowing. A cap on the recovery scan and no cap
# here would also be incoherent: the set phase 0 can grow would exceed the set phase 1
# can see. So the enumeration is complete, and the reach of every recovered anchor is
# VERIFIED below rather than assumed.
#
# AND EVERY READ MUST ANSWER. An unreadable one yields the same empty/short result
# as "no anchors in this state", and phase 1 would then run to completion over a
# gating set it never actually read — normalizing nothing, dispatching nothing, and
# reporting success. merge-skill.sh runs immediately after on the strength of this
# pass having normalized every anchor's check_set, and an anchor it never saw keeps
# whatever empty check_set it arrived with, which merge-skill reads as "declares no
# gates" and lands once CLEAN. So a failed enumeration holds the merge for the pass
# rather than proceeding on a partial view (review tk-thvbq finding #1).
ROWS=""
ENUM_OK=1
for MR_STATE in pull_request pre_open_gate; do
  if ! RAW=$(bd_list_read --status=open --metadata-field merge_result="$MR_STATE"); then
    echo "check-set-heal: WARN the '$MR_STATE' gating enumeration did not return a readable result; the gating set would be PARTIAL and an anchor it never saw stays un-normalized" >&2
    ENUM_OK=0
    break
  fi
  [ "$RAW" != "[]" ] || continue
  PART=$(printf '%s' "$RAW" | jq -c --arg st "$MR_STATE" '.[]
    | ((.metadata // {})) as $m
    # Same empty-aware fallback as phase 0: a merged_target="" must not shadow a
    # recorded target and silently retarget the review to "main" below
    # (tk-zl932 / review tk-ej3wq finding #5).
    | ((($m.merged_target // "") | tostring)) as $mt
    | ((($m.target // "") | tostring)) as $tg
    | {
      id,
      state:    $st,
      checkset: ($m.check_set // ""),
      pr:       ($m.pr_number // ""),
      prurl:    ($m.pr_url // ""),
      branch:   ($m.branch // ""),
      target:   (if $mt != "" then $mt else $tg end),
      title:    (.title // ""),
      codex:    ($m["check.codex"] // ""),
      healed:   ($m.check_set_healed // ""),
      mrhealed: ($m.merge_result_healed // ""),
      mrstate:  ($m.merge_result_pr_state // ""),
      flagged:  ($m.check_set_heal_flagged // ""),
      assignee: ((.assignee // "") | tostring),
      aflag:    (($m.assignee_noncanonical // "") | tostring)
    }' 2>/dev/null)
  [ -n "$PART" ] || continue
  if [ -z "$ROWS" ]; then ROWS="$PART"; else ROWS="$ROWS
$PART"; fi
done

# An enumeration that could not be READ is the same exposure as one that came back
# empty after a recovery, and worse than it in one way: it is silent about how much
# it missed, so a PARTIAL set (one MR_STATE read, the other unreadable) looks exactly
# like a complete one, and the empty-ROWS guard below never fires on it. Held HERE,
# before the loop consumes the set, because merge-skill.sh runs next either way and
# an anchor missing from this set is one this pass never normalized
# (review tk-thvbq finding #1).
if [ "$ENUM_OK" != 1 ]; then
  echo "check-set-heal: UNSAFE — the gating enumeration could not be read, so this pass cannot show that every visible anchor is gated; an un-normalized check_set reads as 'no gates' to merge-skill and could land un-reviewed. Exiting rc=$UNSAFE_RC so the refinery holds merge-skill this pass" >&2
  exit "$UNSAFE_RC"
fi

# Phase 0 EXPOSES an anchor to merge-skill.sh before phase 1 has gated it, so an
# empty enumeration here is not always the benign "nothing to do" it looks like. If
# this pass just restored a merge_result on an OPEN PR, that anchor is visible NOW
# and MUST appear in the scan above; an empty ROWS means the gc/jq enumeration
# failed, and exiting 0 would let the formula run merge-skill.sh against a freshly
# visible anchor whose check_set may still be empty — which merge-skill reads as "no
# gates" and lands un-reviewed, in this same pass. That is the exact ungated-merge
# condition UNSAFE_RC exists for, so hold the merge instead
# (tk-zl932 / review tk-ej3wq finding #2).
if [ -z "$ROWS" ]; then
  if [ -n "$RECOVERED_OPEN" ]; then
    echo "check-set-heal: UNSAFE — restored merge_result on $(printf '%s' "$RECOVERED_OPEN" | grep -c .) OPEN-PR anchor(s) this pass, but the gating enumeration returned NOTHING; they are visible to merge-skill and possibly ungated. Exiting rc=$UNSAFE_RC so the refinery holds merge-skill this pass" >&2
    exit "$UNSAFE_RC"
  fi
  echo "check-set-heal: no gating anchors"; exit 0
fi

healed=0; dispatched=0; normal=0; optout=0; skipped=0; unsafe=0
UNSAFE_IDS=""   # anchors already counted ungated, so the post-loop sweep cannot double-count one
SEEN_IDS=""     # anchors phase 1 actually REACHED, so the sweep below can verify reach
                # rather than infer it from a non-empty check_set (tk-47bij finding #3)
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  [ -n "$id" ] || { skipped=$((skipped + 1)); continue; }
  # Recorded HERE, before any of the decisions below: every `continue` past this point
  # is phase 1 deciding this anchor's gate (healed, dispatched, in-flight, already
  # green, opt-out), which is what "reached" means. A row whose id will not parse is
  # NOT reached — it is counted skipped above and stays absent from this list.
  SEEN_IDS="$SEEN_IDS$id
"

  # The anchor's own record of which PR and which work it owns. Read up here because
  # the reopen re-check below must certify a PR against them BEFORE trusting anything
  # `gh` says about it, not merely name it by number.
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  prurl=$(printf '%s' "$row" | jq -r '.prurl // empty')
  branch=$(printf '%s' "$row" | jq -r '.branch // empty')

  # The OTHER half of the live case's invisibility (tk-wsxd0): su-uzy9.1 was
  # assigned to "shutupandlisten/refinery" while the canonical identity was
  # "shutupandlisten/gc-toolkit.refinery", so find-work's assignee filter could not
  # see it either — bead-keyed passes and the assignee-keyed one were blind at the
  # same time. Flag it for an operator rather than rewriting: an identity is a
  # routing decision, and a wrong automatic rewrite would move a live bead out from
  # under whoever actually holds it. Bounded by recording the offending value, so
  # the warning repeats only if the assignee CHANGES to another non-canonical one.
  # Skipped entirely without --refinery: with no canonical identity to compare
  # against, every assignee would look wrong.
  assignee=$(printf '%s' "$row" | jq -r '.assignee // empty')
  aflag=$(printf '%s' "$row" | jq -r '.aflag // empty')
  if [ -n "$REFINERY_ID" ] && [ -n "$assignee" ] && [ "$assignee" != "$REFINERY_ID" ] \
     && [ "$aflag" != "$assignee" ]; then
    echo "check-set-heal: WARN $id assignee '$assignee' is not the canonical refinery identity '$REFINERY_ID'; the anchor is invisible to find-work's assignee filter — flagging for an operator (tk-wsxd0)" >&2
    gc bd update "$id" --set-metadata assignee_noncanonical="$assignee" >/dev/null 2>&1 || true
    noncanon=$((noncanon + 1))
  fi

  # The anchor's declared gate, read BEFORE the inert arm below because that arm's
  # fail-closed direction depends on it: "ungated" (an empty, never-normalized
  # check_set) is what merge-skill.sh reads as "declares no gates".
  checkset=$(printf '%s' "$row" | jq -r '.checkset // empty')
  canon=$(cs_canon "$checkset")

  # Recovered with a PR that is not OPEN — by THIS pass's phase 0 (RECOVERED_INERT) or
  # by an earlier one (merge_result_pr_state). Visibility was the whole repair: the
  # observer closes a merged PR or escalates an out-of-band close, and arming a gate on
  # a PR nobody can merge would dispatch a signoff into the void.
  #
  # ONE ARM FOR BOTH, because they differ only in HOW the non-OPEN verdict was
  # remembered — never in what has to be re-asked (review tk-sdqwh finding #1). The
  # pass-local skip used to trust phase 0's certification unconditionally, and that is
  # not the same claim: phase 0 also RESTORED merge_result, so between its read and
  # merge-skill.sh (which runs later in this same patrol pass) the anchor is VISIBLE
  # with an empty check_set — and merge-skill reads an empty check_set as "no gates".
  # A CLOSED PR reopened in that window is then an OPEN PR, visible, ungated, and
  # mergeable un-reviewed on the strength of a state read that was already stale. The
  # persisted arm re-checked live for the mirror-image reason (a CLOSED PR can be
  # REOPENED between passes, and an unconditional skip would suppress a legitimate gate
  # forever — tk-zl932 / review tk-ej3wq finding #4); the pass-local one needs it more,
  # not less, because it is the arm whose own phase 0 created the exposure.
  #
  # An unreadable live state keeps the recorded verdict and arms nothing — an
  # unmergeable PR needs the observer, not a reviewer. But when the anchor's canonical
  # check_set is EMPTY, that deferral is not a safe one, and WHICH PASS recovered the
  # anchor does not change that (review tk-pka2d finding #4).
  #
  # This used to hold with UNSAFE_RC only for a PASS-LOCAL recovery, reasoning that an
  # anchor recovered on an EARLIER pass is the status quo — already visible, already
  # ungated, the observer has had a pass to dispose of it — so holding the whole rig's
  # merge queue on its unreadable state would trade one anchor's deferral for every
  # anchor's. That reasoning holds for a GATED anchor, which cannot merge ungated no
  # matter who is confused about it. It is FALSE for an ungated one. The exposure is
  # not "this pass created it", it is "merge-skill.sh reads an empty check_set as 'no
  # gates'" — and that is true on EVERY pass, not just the one that stamped
  # merge_result. A CLOSED PR recovered three passes ago and REOPENED since is an
  # OPEN, visible, ungated anchor; if this pass cannot certify its live state but
  # merge-skill.sh (which runs later in this same patrol pass, in its own gh context)
  # CAN read it, the PR merges un-reviewed. The recorded merge_result_pr_state is a
  # memory of a past read, and a memory is not a gate.
  #
  # So the hold keys on the EXPOSURE — empty canonical check_set plus an uncertifiable
  # live state — never on its provenance. A GATED anchor still takes the WARN-and-defer
  # path, which is what keeps this from holding the queue on every unreadable read.
  #
  # The re-check RE-CERTIFIES the PR; it does not merely name it by number (review
  # tk-r11wt finding #1). Phase 0 certified this anchor's PR by URL, repository, head
  # branch and head repository before ever binding it — but that certification was
  # performed on the pass that RECOVERED the bead, and this arm runs on every LATER
  # pass, in a process whose gh repository context is not guaranteed to be the same
  # one. Asking `gh pr view <number> --json state` alone re-opens exactly the hole
  # phase 0 closed: in another repo context that number answers for a different pull
  # request, and a foreign OPEN PR would refresh this anchor's record to OPEN and drop
  # it into codex gating — dispatching a signoff for, and releasing a merge on, work
  # that is not this bead's. A foreign non-OPEN one would overwrite the recorded state
  # just as wrongly. Certification failure is treated exactly like an unreadable state:
  # keep the recorded verdict, arm nothing, retry next pass.
  recovered_now=0
  if [ -n "$RECOVERED_INERT" ] && printf '%s' "$RECOVERED_INERT" | grep -qxF "$id"; then
    recovered_now=1
  fi
  mrstate=$(printf '%s' "$row" | jq -r '.mrstate // empty')
  if [ "$recovered_now" = 1 ] || { [ -n "$mrstate" ] && [ "$mrstate" != "OPEN" ]; }; then
    # A pass-local recovery is non-OPEN by construction (RECOVERED_INERT is the
    # `cstate != OPEN` half of phase 0), so an empty mrstate here means the persisted
    # record did not reach this row, not that the PR was open. Name it for the
    # messages; the live re-check below is what actually decides.
    [ -n "$mrstate" ] || mrstate="non-OPEN"
    live_state=""
    if [ -n "$num" ] \
       && certify_pr_identity "$id" "$num" "$prurl" "$branch" "gating the recovered PR"; then
      live_state="$CERT_STATE"
    fi
    if [ -z "$live_state" ]; then
      # `-n "$num"`: the hold is owed only to an anchor merge-skill.sh can actually
      # ACT on. It finds its PR by pr_number and skips any anchor without one
      # outright, so a numberless anchor cannot be landed however empty its
      # check_set is — it is the ordinary stall (an operator repairs it), not the
      # ungated-merge exposure. Holding the whole rig's queue for a merge that
      # cannot happen would trade every anchor's throughput for nothing.
      if [ -z "$canon" ] && [ -n "$num" ]; then
        # VISIBLE AND UNGATED, and it cannot be shown to be inert. Everything else here
        # is a deferral; this one is not, because the exposure is already durable
        # (merge_result is stamped) while the gate is not. merge-skill.sh runs later in
        # this same pass and would read the empty check_set as "no gates" — so if the PR
        # is in fact open, it merges un-reviewed. Hold the merge for the pass instead;
        # the next idle wake re-asks, and either gates it or skips it.
        #
        # Fires for a recovery made on ANY pass. Provenance changes only how the state
        # is described to an operator, never whether the merge may proceed: the anchor
        # is equally visible and equally ungated either way, and an earlier pass's
        # non-OPEN read is a memory, not a gate — the PR may have reopened since.
        if [ "$recovered_now" = 1 ]; then
          when="was restored to visibility THIS pass"
        else
          when="was restored to visibility on an EARLIER pass and its recorded $mrstate state has not been re-confirmed since"
        fi
        echo "check-set-heal: UNSAFE — $id $when on a $mrstate PR, but its live state cannot be certified and its check_set is still empty; merge-skill would read that as 'no gates' and could land it un-reviewed if the PR is open (a PR recorded CLOSED can have been REOPENED since). Holding merge-skill this pass (rc=$UNSAFE_RC)" >&2
        unsafe=$((unsafe + 1))
        UNSAFE_IDS="$UNSAFE_IDS$id
"
      else
        # NOT AN EXPOSURE, for one of two reasons — GATED (check_set is non-empty, so
        # merge-skill.sh holds on the unmet gate no matter what this pass could not
        # read) or UNMERGEABLE (no pr_number, so merge-skill.sh cannot find a PR to
        # land at all). Deferring is safe in both, and it is what keeps one anchor's
        # unreadable state from holding the whole rig's queue.
        if [ -n "$canon" ]; then
          why="its check_set ('$canon') still gates any merge"
        else
          why="it records no pr_number, so merge-skill cannot land it at all"
        fi
        echo "check-set-heal: WARN $id was recovered with a $mrstate PR and its live state is unreadable; $why, so leaving the gate alone (a signoff for a PR nobody can merge is noise) — retrying next pass" >&2
      fi
      skipped=$((skipped + 1)); continue
    fi
    if [ "$live_state" != "OPEN" ]; then
      if [ "$live_state" != "$mrstate" ]; then
        gc bd update "$id" --set-metadata merge_result_pr_state="$live_state" >/dev/null 2>&1 || true
      fi
      echo "check-set-heal: $id restored to visibility but its PR is $live_state; leaving the gate alone for the observer to record"
      skipped=$((skipped + 1)); continue
    fi
    # OPEN — whichever arm brought us here. A pass-local recovery that reopened between
    # phase 0 and now is NOT inert after all: fall through and gate it like any other
    # open anchor, on this pass, before merge-skill runs.
    echo "check-set-heal: $id was recovered with a $mrstate PR that is OPEN again; refreshing the record and gating it normally"
    gc bd update "$id" --set-metadata merge_result_pr_state=OPEN >/dev/null 2>&1 || true
  fi

  # checkset/canon were read above the inert arm, which needs `canon` to tell an
  # ungated exposure from a gated one.
  #
  # An anchor stays in the satisfiability path if EITHER repair marker is present.
  # check_set_healed covers a gate repaired here; merge_result_healed covers one
  # PHASE 0 made visible — whose check_set may ALREADY read normal, because the
  # damage that dropped merge_result need not have dropped check_set too (the
  # `codex` survived, the visibility did not). Without this second marker such an
  # anchor takes the "already normalized" exit below and is skipped forever: no
  # signoff is ever dispatched, while merge-skill.sh holds indefinitely on a
  # check.codex marker nothing exists to stamp. That trades an invisible PR for a
  # permanently stuck one (tk-zl932 / review tk-ej3wq finding #1).
  healedmark=$(printf '%s' "$row" | jq -r '.healed // empty')
  [ -n "$healedmark" ] || healedmark=$(printf '%s' "$row" | jq -r '.mrhealed // empty')

  # --- classify -----------------------------------------------------------
  # A PREVIOUSLY healed anchor (check_set_healed recorded) keeps flowing into the
  # satisfiability check below even though its check_set now reads normal. That is
  # what makes "retry next pass" true: the stamp is what reclassifies the anchor,
  # so without this the very first successful stamp would hide the anchor from
  # every later pass — and a dispatch that failed after the stamp would strand the
  # armed gate forever with nothing to raise it.
  #
  # check_set_heal_flagged keeps it flowing for the SAME reason, from the other
  # side: it is stamped whenever a heal did not fully land, and the shape it exists
  # for is the one where check_set_healed is what failed to persist. Without this
  # arm that anchor is armed, unmarked and INVISIBLE — the two fields are written
  # separately and a repair that depends on the field that was just lost is no
  # repair at all. Two independent marks, either of which keeps the retry alive
  # (review tk-nwi06 finding #1).
  flagged=$(printf '%s' "$row" | jq -r '.flagged // empty')
  needs_stamp=0
  case "$canon" in
    '')
      needs_stamp=1 ;;                      # never normalized -> heal
    none|off)
      optout=$((optout + 1)); continue ;;   # EXPLICIT opt-out — leave it alone
    *)
      [ -n "$healedmark" ] || [ -n "$flagged" ] \
        || { normal=$((normal + 1)); continue; } ;;
  esac

  state=$(printf '%s' "$row" | jq -r '.state // empty')   # num/prurl/branch read above
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  title=$(printf '%s' "$row" | jq -r '.title // empty')
  marker=$(printf '%s' "$row" | jq -r '.codex // empty')
  [ -n "$target" ] || target="main"

  # What a dispatch failure below can honestly promise. The default holds while a
  # durable retry mark is on the bead; the half-landed-stamp arm rewrites it when
  # neither mark persisted, because then there IS no next pass for this anchor.
  RETRY_NOTE="merge stays HELD, retrying next pass"

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
    # Read BOTH halves back. They go out in ONE update but persist independently,
    # and they do DIFFERENT jobs: check_set ARMS the gate (without it the anchor
    # merges ungated), check_set_healed is what keeps this anchor flowing through
    # the satisfiability retry above (:320-345). Verifying only check_set accepts a
    # HALF-landed write — gate armed, retry mark gone — and that shape is a
    # PERMANENT strand, not a deferred pass: check_set now reads normal, so every
    # later pass classifies the anchor "already normalized" and skips it, leaving it
    # codex-gated with no review left to raise check.codex. So both are read back,
    # and each half's failure is handled as the different failure it is
    # (review tk-nwi06 finding #1).
    STAMP_ROW=$(gc bd show "$id" --json 2>/dev/null)
    RECORDED=$(printf '%s' "$STAMP_ROW" | jq -r '.[0].metadata.check_set // empty' 2>/dev/null)
    RECORDED_HEALED=$(printf '%s' "$STAMP_ROW" | jq -r '.[0].metadata.check_set_healed // empty' 2>/dev/null)
    if [ "$RECORDED" = "$DEFAULT_CHECK_SET" ] && [ "$RECORDED_HEALED" != "$DEFAULT_CHECK_SET" ]; then
      # PARTIAL WRITE: the gate landed, the retry mark did not. One repair attempt
      # on just the missing half — a transient write failure is the common case and
      # heals here, and re-stamping a value that is already correct is harmless.
      gc bd update "$id" --set-metadata check_set_healed="$DEFAULT_CHECK_SET" >/dev/null 2>&1
      RECORDED_HEALED=$(gc bd show "$id" --json 2>/dev/null \
        | jq -r '.[0].metadata.check_set_healed // empty' 2>/dev/null)
    fi
    if [ "$RECORDED" != "$DEFAULT_CHECK_SET" ]; then
      # The GATE did not stick. Do NOT count it as healed; the anchor is
      # still ungated and the merge skill may land it this pass. Flag ONCE so the
      # noise is bounded, and let the next idle pass retry the whole heal.
      echo "check-set-heal: WARN $id check_set stamp did NOT persist (have '${RECORDED:-<empty>}', want '$DEFAULT_CHECK_SET'); anchor is still UNGATED — retrying next pass" >&2
      if [ -z "$flagged" ]; then
        gc bd update "$id" --set-metadata check_set_heal_flagged=1 >/dev/null 2>&1 || true
      fi
      # This anchor is still ungated THIS pass: merge-skill.sh would read its empty
      # check_set as "no gates" and land it un-reviewed. Remember it so the pass
      # exits UNSAFE_RC and the formula holds the merge skill for this pass
      # (tk-i48ca / review tk-z4u2e finding #1).
      unsafe=$((unsafe + 1))
      UNSAFE_IDS="$UNSAFE_IDS$id
"
      skipped=$((skipped + 1)); continue
    fi
    if [ "$RECORDED_HEALED" != "$DEFAULT_CHECK_SET" ]; then
      # The gate IS armed, so the merge is HELD (a gate with no green marker cannot
      # land) — this is NOT the ungated hazard and must not raise UNSAFE_RC and stop
      # every other anchor's merge. What is missing is only the mark that brings
      # this anchor back here on a later pass, and its absence is exactly what makes
      # "retrying next pass" UNTRUE: check_set now reads normal, so the classifier
      # above routes the anchor to `normal` and skips it, forever.
      #
      # So do NOT defer. Fall through and make the gate satisfiable NOW — dispatching
      # this pass is precisely what the next pass would have done had the mark
      # landed, and it is the only pass that will ever get the chance. Not counted as
      # healed: the heal is not fully recorded, and reporting one would claim an
      # audit trail that is not on the bead.
      echo "check-set-heal: WARN $id check_set='$DEFAULT_CHECK_SET' landed but check_set_healed did NOT (have '${RECORDED_HEALED:-<empty>}'); the merge is HELD, but later passes will read this anchor as already-normalized and skip it — making the gate satisfiable THIS pass instead of deferring. If the dispatch below also fails, repair by hand: gc bd update $id --set-metadata check_set_healed=$DEFAULT_CHECK_SET" >&2
      # check_set_heal_flagged is the FALLBACK retry mark: with check_set_healed
      # gone it is the only thing that brings this anchor back through the
      # classifier (:320-345). It is written by the same kind of best-effort
      # `gc bd update` that just dropped check_set_healed, so writing it and
      # assuming it landed rebuilds the very hole this arm exists to cover — a
      # dropped write here leaves the anchor armed, unmarked and INVISIBLE to
      # every later pass. So READ IT BACK, with one repair attempt, exactly as
      # the two stamps above are (review tk-y5r1e finding #2).
      if [ -z "$flagged" ]; then
        gc bd update "$id" --set-metadata check_set_heal_flagged=1 >/dev/null 2>&1 || true
        flagged=$(read_flag "$id")
        if [ -z "$flagged" ]; then
          gc bd update "$id" --set-metadata check_set_heal_flagged=1 >/dev/null 2>&1 || true
          flagged=$(read_flag "$id")
        fi
      fi
      if [ -z "$flagged" ]; then
        # NEITHER durable mark persisted. The gate is armed (merge held — still not
        # the ungated hazard, so no UNSAFE_RC), but nothing on the bead will bring
        # this anchor back here: the classifier reads check_set as normal, finds no
        # healed mark and no flag, and skips it on every later pass. So this pass's
        # dispatch below is the ONLY one this anchor will ever get, and if it fails
        # there is no retry to fall back on. Say exactly that — downstream failures
        # stop promising a next pass that will never come.
        RETRY_NOTE="NO durable retry mark persisted (check_set_healed and check_set_heal_flagged both dropped) — later passes will read this anchor as already-normalized and SKIP it, so nothing will retry. Repair by hand: gc bd update $id --set-metadata check_set_healed=$DEFAULT_CHECK_SET"
        echo "check-set-heal: WARN $id $RETRY_NOTE" >&2
      fi
    else
      healed=$((healed + 1))
    fi
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
  # A review found UNCLAIMED AND UNROUTED is not in flight but stranded, and is
  # re-routed here instead of being counted as in flight forever (finding #3).
  #
  # WHICH REPOSITORY'S PR#<n> THIS ANCHOR NAMES is passed with it — the same question
  # phase 0 asks of a candidate row, asked the same way: from the anchor's own pr_url
  # when it has one, else the repository certification would require of it, which is
  # this checkout's origin; `?` when neither can be named. Without it every match from
  # the broad `pr_number`/`branch` surfaces would be repository-UNKNOWN, the fail-closed
  # wildcard would accept all of them, and one foreign bead carrying this number would
  # hold this anchor's signoff forever (review tk-jza6h finding #2). The dedup's safety
  # is unchanged — only a POSITIVE disagreement clears a match.
  AREPO=$(url_repo_q "$prurl")
  [ -n "$AREPO" ] || AREPO="$PASS_ORIGIN_REPO_Q"
  [ -n "$AREPO" ] || AREPO="?"
  # An UNREADABLE lookup is not "nothing in flight". It returns the same empty
  # string, and dispatching on it mints a twin signoff for an anchor that already
  # has one — two claimable reviews for one gate, which is the duplicate-dispatch
  # this dedup exists to prevent. Hold instead: the gate is already armed, so the
  # merge stays HELD (the safe side) and the next pass re-asks (review tk-thvbq
  # finding #1).
  if ! EXISTING_REVIEW=$(inflight_for "$id" "$num" "$branch" "$AREPO"); then
    echo "check-set-heal: WARN $id in-flight signoff lookup failed (ledger unreadable); cannot rule out a signoff already in flight — dispatching none this pass, merge stays HELD, retrying next" >&2
    skipped=$((skipped + 1))
    continue
  fi
  if [ -n "$EXISTING_REVIEW" ]; then
    if [ -n "$REVIEW_POOL" ] \
       && repair_review_routing "$EXISTING_REVIEW" "$id" "$REVIEW_POOL"; then
      gc session wake "$REVIEW_POOL" >/dev/null 2>&1 || true
      gc session nudge "$REVIEW_POOL" "Review bead $EXISTING_REVIEW for anchor $id" >/dev/null 2>&1 || true
      dispatched=$((dispatched + 1))
      echo "check-set-heal: $id had a STRANDED signoff $EXISTING_REVIEW (open, unclaimed, UNROUTED — its routing write was lost); re-routed to $REVIEW_POOL rather than counting it in flight"
      continue
    fi
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
  # The bead carries the review METHOD in its body (create_review_bead) — the title
  # says WHAT to review, the metadata says WHERE, and the body says HOW (tk-jufvl).
  REVIEW_BEAD=""
  if [ -n "$num" ]; then
    REVIEW_BEAD=$(create_review_bead "Review PR#$num: $title")
  else
    REVIEW_BEAD=$(create_review_bead "Review branch $branch -> $target: $title")
  fi
  if [ -z "$REVIEW_BEAD" ]; then
    echo "check-set-heal: WARN $id could not create the signoff bead; $RETRY_NOTE" >&2
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
  # gate would never clear. Unrouted the bead is inert, and the next pass repairs
  # it through `repair_review_routing` rather than minting a twin.
  RECORDED_ANCHOR=$(gc bd show "$REVIEW_BEAD" --json 2>/dev/null \
    | jq -r '.[0].metadata.anchor_bead // empty')
  if [ "$RECORDED_ANCHOR" != "$id" ]; then
    echo "check-set-heal: WARN review $REVIEW_BEAD did not record anchor_bead=$id; signoff cannot stamp the gate — $RETRY_NOTE" >&2
    continue
  fi

  # review_pool is the DURABLE copy of the route, stamped with it — the same pair
  # the other two dispatch sites write (mol-refinery-patrol.toml merge-push,
  # reconcile-merged-prs.sh arm_stale_gate). gc.routed_to is working state that a
  # claim consumes, so when a signoff ends with the gate UNRECORDED and has to put
  # the review back in a pool to be re-offered, this is the only field left that
  # says which pool that was. Without it the review is released open, unassigned
  # and UNROUTED — offered to nobody, gate owed forever
  # (template-fragments/polecat-non-impl-done.template.md).
  gc bd update "$REVIEW_BEAD" \
    --set-metadata gc.routed_to="$REVIEW_POOL" \
    --set-metadata review_pool="$REVIEW_POOL" >/dev/null 2>&1

  # READ THE ROUTE BACK before counting this as a dispatch (tk-tmefn). The write
  # above was best-effort — its status is discarded, and a `gc bd update` can
  # report success on a write that did not land. Counting a dispatch that never
  # routed is not a lost pass, it is a PERMANENT strand: the review bead exists and
  # is open, so the next pass's `inflight_for` dedup reuses it and never mints a
  # replacement, while no pool can ever claim it. The gate stays armed, the anchor
  # stays held, and nothing retries — the one shape this script exists to avoid,
  # rebuilt out of its own repair.
  #
  # The predicate is deliberately not "gc.routed_to is set". That field is WORKING
  # state a claim CONSUMES, so a codex polecat that claimed the review between the
  # write and this read leaves it legitimately empty — re-routing then would offer
  # a claimed review to a second pool. What must hold is:
  #   review_pool == the pool  — the DURABLE copy, never consumed, and the only
  #                              field the signoff can restore the route from when
  #                              it has to put the review back to be re-offered;
  #   routed OR claimed        — the bead is reachable: still offered to the pool,
  #                              or already picked up by it.
  route_state=$(read_route "$REVIEW_BEAD")
  if ! route_ok "$route_state" "$REVIEW_POOL"; then
    # One repair attempt, then re-read. A transient write failure is the common
    # case and heals here. This also re-covers the unreadable case: a read that
    # returned nothing is not proof of a bad route, but re-stamping is harmless
    # (the values are the ones we intended) and the second read may succeed.
    gc bd update "$REVIEW_BEAD" \
      --set-metadata gc.routed_to="$REVIEW_POOL" \
      --set-metadata review_pool="$REVIEW_POOL" >/dev/null 2>&1
    route_state=$(read_route "$REVIEW_BEAD")
  fi
  if ! route_ok "$route_state" "$REVIEW_POOL"; then
    IFS='|' read -r got_pool got_routed got_assignee <<< "${route_state:-||}"
    # Not counted as dispatched either way: the anchor stays held on its armed
    # gate, which is the safe side, and the next pass retries.
    #
    # An UNREADABLE bead (empty route_state — `gc bd show` or jq failed) is NOT
    # the same as one read as unrouted, and must not be closed: the route may be
    # perfectly fine, and a polecat may already hold the bead. Closing a claimed
    # review out from under its reviewer is a worse failure than the strand.
    # Leave it; the next pass re-reads and either reuses it (dedup) or repairs it.
    if [ -z "$route_state" ]; then
      echo "check-set-heal: WARN $id signoff $REVIEW_BEAD route to $REVIEW_POOL could not be VERIFIED (bead unreadable); dispatch NOT counted, $RETRY_NOTE" >&2
      continue
    fi
    # CLAIMED — never close it. `route_ok` rejects the triple on the FIRST half it
    # tests (review_pool == this pool), so a persistently dropped durable copy
    # lands here even when the live half is fine and a codex polecat has already
    # picked the review up. The close below reads "claimed by nobody" from the fact
    # that route_ok failed, but that inference only holds for the unrouted shape:
    # here the read itself shows an assignee. Closing on it would force-close an
    # IN-FLIGHT review (the `--force` retry exists precisely to defeat the
    # ownership check that would otherwise stop it) and erase the only live signoff
    # for an armed gate — the anchor then holds forever on a marker nothing is left
    # to stamp. A claimed review is not dedup poison either: the next pass's
    # `inflight_for` reuses it, which is the correct outcome, because its reviewer
    # is the thing that will raise the gate (review tk-y5r1e finding #1).
    if [ -n "$got_assignee" ]; then
      # Restore the durable copy ONLY when it is absent — that is the dropped-write
      # shape, and the value is the one this pass intended. A non-empty but
      # different review_pool is somebody's deliberate re-route, so leave it. Never
      # touch gc.routed_to on a claimed bead: the claim consumed it, and re-offering
      # a held review is how a second pool gets handed the same work.
      if [ -z "$got_pool" ]; then
        gc bd update "$REVIEW_BEAD" --set-metadata review_pool="$REVIEW_POOL" >/dev/null 2>&1 || true
      fi
      echo "check-set-heal: WARN $id signoff $REVIEW_BEAD route did not verify (review_pool='$got_pool', gc.routed_to='$got_routed') but it is CLAIMED by '$got_assignee' — leaving it OPEN and in flight (closing a claimed review would erase the only signoff for the armed gate); dispatch NOT counted, $RETRY_NOTE" >&2
      continue
    fi
    # Read fine, unclaimed, and genuinely unroutable. LEAVE NOTHING that poisons
    # the next pass's dedup: close the review bead we just minted. It is inert —
    # created this pass, claimed by nobody (the read just showed no assignee),
    # carrying no work — so closing it discards nothing, and it is the only way the
    # next pass gets to mint a review that CAN be claimed.
    CLOSE_REASON="unroutable signoff: route to $REVIEW_POOL did not persist (review_pool='$got_pool', gc.routed_to='$got_routed', assignee='$got_assignee'); re-minted next pass"
    # `--force` on the retry: `gc bd close` can refuse a bead whose recorded actor
    # does not match the closing session's identity, and this bead's actor is
    # whatever minted it a moment ago. A refusal on that ground would leave the
    # unclaimable review OPEN — exactly the dedup poison this close exists to
    # remove — so the ownership check is the one thing worth overriding here.
    # Still best-effort: a failure warns and the next pass retries.
    gc bd close "$REVIEW_BEAD" --reason "$CLOSE_REASON" >/dev/null 2>&1 \
      || gc bd close "$REVIEW_BEAD" --reason "$CLOSE_REASON" --force >/dev/null 2>&1 \
      || echo "check-set-heal: WARN could not close unroutable review $REVIEW_BEAD; it may block the next pass's dedup — close it by hand" >&2
    echo "check-set-heal: WARN $id signoff $REVIEW_BEAD did not durably route to $REVIEW_POOL (review_pool='$got_pool', gc.routed_to='$got_routed', assignee='$got_assignee'); dispatch NOT counted, $RETRY_NOTE" >&2
    continue
  fi
  gc session wake "$REVIEW_POOL" >/dev/null 2>&1 || true
  gc session nudge "$REVIEW_POOL" "Review bead $REVIEW_BEAD for recovered anchor $id" >/dev/null 2>&1 || true
  dispatched=$((dispatched + 1))
  echo "check-set-heal: $id dispatched signoff $REVIEW_BEAD to $REVIEW_POOL (gate '$DEFAULT_CHECK_SET' is now satisfiable)"
done <<< "$ROWS"

# Phase 0 made these anchors visible to merge-skill.sh; phase 1 was supposed to gate
# them on this same pass. VERIFY that rather than assume it — the two phases are
# joined only by an enumeration that can silently drop a row (a jq error, a paging
# edge, a candidate whose merge_result landed after the scan). An anchor left with an
# empty check_set is read by merge-skill as "declares NO gates" and merges
# un-reviewed, so a gap here is the ungated-merge condition, not a cosmetic one. An
# unreadable check_set counts as ungated: we cannot show the anchor is safe, and one
# held pass is cheap next to one un-reviewed merge
# (tk-zl932 / review tk-ej3wq finding #2).
#
# REACH IS VERIFIED, NOT INFERRED FROM check_set (review tk-47bij finding #3). A
# non-empty check_set proves the anchor is GATED; it does not prove phase 1 ever saw
# it, and the two come apart on exactly the shape phase 0 most often produces: an
# anchor whose check_set already read `codex` before the damage. Dropped from the
# enumeration, it passes a check_set-only sweep silently while no signoff was ever
# dispatched — an armed gate nobody can raise, which is a held merge with no
# escalation. So each recovered anchor is checked for BOTH: that phase 1 reached it,
# and that it ended the pass gated.
if [ -n "$RECOVERED_OPEN" ]; then
  while IFS= read -r rid; do
    [ -n "${rid:-}" ] || continue
    # Already counted by the stamp-verification above — same anchor, same defect.
    if [ -n "$UNSAFE_IDS" ] && printf '%s' "$UNSAFE_IDS" | grep -qxF "$rid"; then continue; fi
    REACHED=1
    printf '%s' "$SEEN_IDS" | grep -qxF "$rid" || REACHED=0
    UNREACHED_NOTE=""
    [ "$REACHED" = 1 ] || UNREACHED_NOTE=" and the gating enumeration never reached it"
    RCS=$(gc bd show "$rid" --json 2>/dev/null | jq -r '.[0].metadata.check_set // empty' 2>/dev/null)
    if [ -z "$(cs_canon "$RCS")" ]; then
      echo "check-set-heal: WARN $rid was restored to visibility this pass but is STILL UNGATED (check_set '${RCS:-<empty>}'$UNREACHED_NOTE); merge-skill would read that as 'no gates' and land it un-reviewed" >&2
      unsafe=$((unsafe + 1))
    elif [ "$REACHED" = 0 ]; then
      # Gated, so merge-skill HOLDS it — this is not the ungated-merge condition
      # UNSAFE_RC names, and holding the whole queue for it would trade one anchor's
      # deferral for every anchor's. But it is silent otherwise: nothing was
      # dispatched to raise the armed gate. Say so, and let the durable
      # merge_result_healed marker carry it back into the satisfiability path next
      # pass, where the now-unbounded enumeration reaches it.
      echo "check-set-heal: WARN $rid was restored to visibility this pass but the gating enumeration never reached it; its check_set '$RCS' HOLDS the merge, but no signoff was dispatched to raise that gate — retrying next pass" >&2
      skipped=$((skipped + 1))
    fi
  done <<< "$RECOVERED_OPEN"
fi

echo "check-set-heal: $healed healed, $dispatched signoffs dispatched, $normal already normalized, $optout explicit opt-out, $skipped skipped, $recovered merge_result restored, $noncanon non-canonical assignee"

# Fail-closed to the formula. Either an anchor's check_set stamp did not persist, or
# one this pass made VISIBLE was never gated — in both cases merge-skill.sh would
# read an empty check_set as "no gates" and land the PR un-reviewed this pass. Exit
# UNSAFE_RC so the formula HOLDS merge-skill for the pass; the next idle wake
# re-heals and, once the stamp sticks, the anchor gates normally. Delaying a merge
# one pass is the acceptable failure; an un-reviewed merge is not
# (tk-i48ca / review tk-z4u2e finding #1; tk-zl932 / review tk-ej3wq finding #2).
if [ "$unsafe" -gt 0 ]; then
  echo "check-set-heal: UNSAFE — $unsafe anchor(s) are visible to merge-skill but still ungated; exiting rc=$UNSAFE_RC so the refinery holds merge-skill this pass" >&2
  exit "$UNSAFE_RC"
fi
exit 0
