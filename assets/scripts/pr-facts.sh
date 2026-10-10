#!/usr/bin/env bash
# pr-facts — arm 7 of the merge cadence: record EXTERNAL facts about each open
# pull_request anchor. No merge authority. Same enumeration and pinned identity
# read as merge.sh; per anchor, in order: PR MERGED (out-of-band, or a record
# that died after merge.sh landed it) -> lifecycle transition to merged, with
# a failure counted against the same record-failure-cap.sh budget merge.sh
# spends, since both are attempts at the one repair;
# CLOSED-unmerged -> if the anchor carries a pre-recorded disposition
# (gc.pr_close_disposition_*, stamped by pr-dispose.sh), auto-dispose it through
# bead-rehome.sh and retire any stale rework-or-close visit; otherwise abandoned
# + escalate.sh visit; base moved -> retargeted +
# escalate (check markers cleared: a review of the pre-retarget diff proves
# nothing about the new base); CONFLICTING with no feedback owed, on an APPROVED
# PR (review-verdict.sh, the rule merge.sh lands on; an unapproved one records
# its posture and files nothing) -> file ONE
# merge-in rework child while none is in flight, to the fix pool that brings the
# branch current by MERGE (no branch shape is
# rebased or force-pushed), stamped prepare_mode=merge and counted as
# dispatched only once that stamp AND the route itself read back (dedup: a LIVE
# rework child on this branch, in flight or parked; a closed one is a finished
# round and does not stand the dispatch down, so a still-dirty branch with
# nothing in flight re-dispatches, not only on the PR's first head; an unstamped
# orphan is adopted by title and an unrouted one re-routed, never twinned; an
# operator's hold, rebase_hold, or a live demand dispatches nothing this pass,
# since rebasing is one horn of what a demand asks;
# dismissal of our OWN superseded CHANGES_REQUESTED (the city's own by
# gc_city_own, never a review that is feedback; signoff_dismissed read back
# FIRST; skipped under native auto-merge).
# No arm here re-reviews a moved head: a lane state is a state of the lane, and
# gate-ensure dispatches on the lane, not on the commit under it. A merged record never carries an
# empty merged_sha — an unreadable mergeCommit records
# merged_sha=unverified:PR#<n>, loudly.
# Every OPEN non-draft anchor also gets its POSTURE recorded before any dispatch
# arm runs (lifecycle/lifecycle.toml [posture]): pr_posture (dated) and pr_merge_state
# pinned to the live head, written only when the value changes, so merge.sh can
# answer "is a human waiting on this?" off the bead instead of re-deriving it.
# --posture-only exits non-zero when any anchor is left without a current
# posture and nothing standing already holds it: the caller holds merge.sh for
# that pass rather than let it validate against a fact from an earlier tick.
# --posture-only with --seen <file> reads every open PR in one batched GraphQL
# call, merge state included, and keeps in <file> the facts each anchor's
# posture was derived from, once two derivations a pass apart agree on them. An
# anchor whose facts all read the same, and whose bead still carries that
# posture at that head, keeps it without the per-PR reads; any other anchor is
# read as before.
# Unanswered review feedback routes to something — a fix-pool rework child
# carrying the review bodies and inline comments verbatim, or a visit when a
# human already holds the anchor — with the watermarks advancing only once that
# routing reads back. Feedback is decided by provenance, not by author: every
# review, inline comment and conversation comment that is not the city's own post
# (pr-post.sh's gc_city_own: marked by pr-post.sh, or under the city's login
# before the anchor's provenance cutover, pr_provenance_since) is feedback,
# whoever posted it, so a model review run under the city's own account routes
# like a person's. This runs even while the anchor still conflicts: the rework
# child is prepare_mode=merge, so it brings the branch current as it answers, and
# the CONFLICTING arm above stands down when feedback is owed rather than filing a
# redundant merge-in child. It routes under posture `commented` and equally under a
# human `changes_requested`, which holds the merge but answers nothing; a
# dismissed review is in neither state, so a dismissal takes it and the inline
# comments under it out of the batch. An unmarked review posted under our own
# login before the cutover is read as the city's own, so its unresolved finding
# threads are never counted by that arm. The posture pass folds such an unengaged
# thread into `commented` — the merge-hold has to be recorded before merge.sh
# runs — and the full pass files the one visit it stands for.
# A required check that has terminally FAILED, on a PR every arm above waved
# through (no conflict, feedback answered, no unresolved-thread block), files ONE
# rework child per head the same way — dedup keyed on anchor_bead, so an
# in-flight review stands it down as well as a rework. It reads the same required
# set merge.sh holds on (required_contexts_for) but routes on a terminal failure
# only: a pending or missing required check has not failed, so it is left for a
# later pass.
# Such a batch also ensures a live check_name=human validation pass on the
# anchor: it is review the branch has never been answered against, so it enters
# the graph as a task_kind=validation bead from which gate-ensure's quiescence
# holds a fresh whole-diff review off the anchor while the validator rules the
# batch. The pass is opened unrouted here and dispatched to mol-validate by
# gate-ensure. One live human-lane pass rules every open human finding on the
# anchor, so the dedup reuses that pass while it stays open and a later batch
# watermarks behind it rather than opening another; a pass on another lane never
# rules the human findings.
# After the dispatch arms, a write-back sweep shows the operator, where they are
# already reading, which comments the city looked at, which wait on a person, and
# which are handled. An anchor carrying pr_comment_disposition has a bead covering
# its comments, so every comment at or below the recorded watermark gets an EYES
# reaction. The mark is cumulative, so each id space keeps a ledger of the batches
# routed under it (pr_comment_batch, pr_review_batch, pr_issue_comment_batch), and
# a comment's batch names the bead that answers it. A comment whose batch went to
# a visit that is still open gets a reply leading with a question mark that names
# the visit. Once the batch's bead closes (the rework child landed, or the visit
# closed) and the comment's own finding, if it has one, has closed, the comment is
# resolved: a reply leading with a check mark says what resolved it, and its EYES
# reaction is traded for THUMBS_UP. An inline comment is answered in its thread,
# which is then resolved. A review body or a Conversation comment has no thread,
# so a PR comment linking to it carries its answer. A needs-you finding waits on
# a person through its own owed reply, and a declined or deferred one is handled
# by its owed reply, so the batch never answers over either. Feedback the routing
# arm left out of a batch because its review threads had already answered it sits
# inside that batch's range all the same; it is acknowledged, and the batch's
# bead never answers or marks it. The reactions are written first, and a pass
# that cannot finish them posts no answer, so no comment is answered before it
# is acknowledged. A thread a human answered after the city's reply is left
# open, and so is one holding a comment above the mark: no batch covers that
# comment, so nothing has answered it yet.
# The sweep also closes the human review loop. A human CHANGES_REQUESTED stands
# as GitHub's own blocking signal until someone clears it; once every finding a
# particular human review raised has closed — a must-fix fixed and landed, a
# decline replied and resolved, or a deferral's follow-up filed and its id
# replied — that review is answered in full, so the sweep dismisses it (clearing
# the block) and re-requests its author, per-review via finding.review_id so one
# reviewer clears independently of another. A needs-you finding is the exception
# that holds the review open on purpose: it stays open until the operator rules
# its visit, so the review it belongs to is never auto-dismissed meanwhile. The
# confidence is the validator's, carried by the finding's closure, never a commit
# oid, so a later push does not reopen it. A dismissal is not an approval: the
# merge still gates on an explicit one.
# The sweep also carries each machine-lane finding ruled worth fixing (must-fix
# or deferred) to the PR, where the merge is decided: a file-level review
# comment when the finding's locus begins with a file the diff touches, a
# Conversation comment otherwise. Once the finding closes, the comment is
# answered with how it closed, the commit carrying the fix or the deferral's
# follow-up, and its thread is resolved unless a post that is not the city's own
# has come after it.
# A human finding already sits on the PR where its raiser wrote it and is
# answered there, so it is never posted again. A posted finding holds nothing:
# a must-fix holds the merge through its own blocks edge. Its comments go
# through pr-post.sh and carry the city's mark, so no feedback reader takes one
# for feedback, and the BLOCKED arm does not count a thread holding only the
# city's finding comments.
# Idempotence is read off GitHub, so a repeat pass writes nothing and a failed
# write retries.
# Args: --fix-pool <pool>; --posture-only (the cheap pre-merge arm: record
# posture and stop); --route-comments-only (the early arm that routes
# operator feedback and stops after it, skipping the write-back sweep and every
# non-feedback arm, so a pass killed before the full arm has still picked the
# feedback up); --deadline <epoch-secs> and --cursor <file> pace the per-anchor
# walk of the feedback and full modes, and the full mode's write-back sweep on a
# cursor of its own (pace-lib.sh): each walk is a rotation that starts no new
# anchor past the deadline, and visits first the anchors that need action. The
# posture-only mode is never paced, because merge.sh needs every posture
# current; --seen <file> is its record of what it read. Caller:
# refinery-reconcile.sh (BEADS_ACTOR projected to the refinery identity).
# Fail-closed on identity.
set -u

PROG="pr-facts"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# The single writer of the workflow-owned `status:` PR label. The full pass is its
# authoritative reconcile: it runs for every open anchor and already mutates the
# PR, so a label a signoff or open event missed self-heals here. Every mode also
# re-derives the label for an anchor when it records a new posture value or routes
# a feedback batch into live work, so a review moves the label in the arm that
# records it rather than waiting for the full pass.
PR_STATUS_LABEL="$SCRIPTS_DIR/pr-status-label.sh"
LIFECYCLE="$SCRIPTS_DIR/lifecycle.sh"
ESCALATE="$SCRIPTS_DIR/escalate.sh"
# The one resolver of the check index: the two merge-readiness all-green reads
# below ask it for every declared lane (`--through merge` spans all phases),
# which drops the non-lanes none/off and the approval merge rule in one place.
REVIEW_CHECKS="$SCRIPTS_DIR/review-checks.sh"
[ -x "$REVIEW_CHECKS" ] || { echo "$PROG: the check resolver is missing ($REVIEW_CHECKS); cannot reconcile" >&2; exit 1; }
# The merged-record retry cap, shared with merge.sh: this arm and merge.sh's two
# record arms perform the same repair on the same anchor, so their failures
# count against one budget rather than each keeping a private tally.
RECORD_CAP="$SCRIPTS_DIR/record-failure-cap.sh"
# The sanctioned terminal close for a disposed (non-landed) anchor. A close arm
# below consummates a pre-recorded PR-close disposition through it rather than
# abandoning + filing a rework-or-close visit; it stamps gc.superseded_by, the
# explicit terminal state doctor/check-closed-implies-landed accepts.
REHOME="$SCRIPTS_DIR/bead-rehome.sh"
# The guarded visit close. Both visit retires below go through it, so a retired
# visit carries gc.outcome and gc.outcome_reason, the board's outcome and headline
# for a sitting that left no takeaway, and both stamps read back before the close.
# pr-facts holds none of the visits it retires, and bd's close verb refuses a bead
# assigned to another actor, so both pass --force. visit-close.sh still tries the
# plain close first, so an unassigned visit closes without the override.
VISIT_CLOSE="$SCRIPTS_DIR/visit-close.sh"
# The dispatch note a validation-pass bead carries, naming mol-validate as its
# method. The human-feedback arm opens such a pass below; a validator that
# claims the bead reads this note to know the pass is a mol-validate pour.
VALIDATE_BODY="$SCRIPTS_DIR/validate-dispatch-body.sh"
# The finding primitive. The human-feedback arm files each unanswered item as a
# task_kind=finding bead through it, so the validation pass it opens has a finding
# set to rule (specs/tk-ztapg/review-cycle-architecture.md, "Findings").
FINDING="$SCRIPTS_DIR/finding.sh"
# The single writer of the city's PR posts, and the owner of the mark that tells
# them from feedback. Every reply and comment this script posts goes through it,
# and every read that separates feedback from the city's own output asks its
# definition (gc_city_own), so the writer and the readers cannot drift apart. A
# rework child names this absolute path to its fixer: the polecat works in its
# own rig's checkout, where a pack-relative path names nothing.
PR_POST="$SCRIPTS_DIR/pr-post.sh"
[ -x "$PR_POST" ] || { echo "$PROG: the PR posting helper is missing ($PR_POST); cannot tell the city's own posts from feedback" >&2; exit 1; }
CITY_OWN_DEF=$("$PR_POST" own-def) && [ -n "$CITY_OWN_DEF" ] \
  || { echo "$PROG: the PR posting helper did not print its provenance definition; cannot tell the city's own posts from feedback" >&2; exit 1; }

FIX_POOL=""; POSTURE_ONLY=0; ROUTE_ONLY=0; DEADLINE=""; CURSOR=""; SEEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix-pool)            FIX_POOL="${2:-}"; shift 2 ;;
    --posture-only)        POSTURE_ONLY=1; shift ;;
    --route-comments-only) ROUTE_ONLY=1; shift ;;
    --deadline)            DEADLINE="${2:-}"; shift 2 ;;
    --cursor)              CURSOR="${2:-}"; shift 2 ;;
    --seen)                SEEN="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ "$POSTURE_ONLY" = 1 ] && { DEADLINE=""; CURSOR=""; }
[ "$POSTURE_ONLY" = 1 ] || SEEN=""

command -v gh >/dev/null 2>&1 || exit 0

ORIGIN_HOST=""; ORIGIN_REPO=""; ORIGIN_REPO_Q=""
u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
if [ -z "$ORIGIN_REPO" ]; then
  echo "$PROG: cannot resolve this checkout's origin repository; recording NOTHING this pass" >&2
  exit 0
fi
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"
gh_api_origin() { gh api --hostname "$ORIGIN_HOST" "$@"; }
SELF_LOGIN=$(gh_api_origin user --jq '.login' 2>/dev/null)

# Which status checks actually gate <branch>. The red-check arm routes on the
# same set merge.sh holds a merge on, so this is a byte-identical copy of
# merge.sh's function between the markers below; a test proves the two never
# drift.
REQ_STATE=""; REQ_CONTEXTS=""
# >>> required-contexts-for
required_contexts_for() { # <branch>
  local b="$1" rules branch rrc brc
  REQ_STATE=""; REQ_CONTEXTS=""
  rules=$(gh_api_origin "repos/$ORIGIN_REPO/rules/branches/$b" 2>/dev/null); rrc=$?
  branch=$(gh_api_origin "repos/$ORIGIN_REPO/branches/$b" 2>/dev/null); brc=$?
  if [ "$rrc" -ne 0 ] || ! printf '%s' "$rules" | jq -e 'type == "array"' >/dev/null 2>&1 \
     || [ "$brc" -ne 0 ] || ! printf '%s' "$branch" | jq -e 'type == "object" and has("name")' >/dev/null 2>&1; then
    REQ_STATE="unknown"; return 0
  fi
  REQ_CONTEXTS=$( { printf '%s' "$rules" | jq -r '
      [ .[] | select(type == "object") | select((.type // "") == "required_status_checks")
        | (.parameters.required_status_checks // [])[] | (.context // empty) ] | .[]' 2>/dev/null
    printf '%s' "$branch" | jq -r '
      [ (.protection.required_status_checks.contexts // [])[],
        ((.protection.required_status_checks.checks // [])[] | (.context // empty)) ] | .[]' 2>/dev/null
  } | sed '/^$/d' | sort -u)
  REQ_STATE="known"
}
# <<< required-contexts-for

url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}
canon_pr_url() {
  printf '%s' "${1:-}" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##'
}
is_held() { case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac; }

# >>> takeaway-hold-discriminator
# Whether a person still owes an answer on this anchor. `gc.takeaway` cannot
# say: it is one field a sitting stamps when it begins and REPLACES with its
# outcome when it signs off, and nothing clears it, so its presence dates the
# last sitting instead of naming a live wait. Read as a hold, it parks an
# anchor from its first conversation onward.
#
# The wait itself is a human gate. `gc-helm.sh demand` files what a person
# owes as a native gate (issue_type=gate, await_type=human) stamped
# gc.demand_for=<anchor> and blocking the anchor on it, and a sitting resolves
# that gate (gc bd gate resolve) with the ruling that answers it. A live
# demand is a live hold; none, and the takeaway records a sitting that ended.
#
# Only demands count. Rework children and `--waiting-on` edges are work in
# flight, which the merge already holds on, and reading `blocks` at large would
# restore the same permanence one indirection out. The `held` lifecycle state
# is not read either: it is entered only from `unanchored`.
#
# demand_gate_state reads the demand ledger for an anchor in three:
#   0  a live demand holds the anchor
#   1  the ledger read cleanly and no demand holds
#   2  the ledger would not read — the list failed or returned a non-array
# gc.demand_for names the demand's anchor.
demand_gate_state() { # <anchor-id>
  local rows
  # --include-gates: the demand is a human gate (issue_type=gate), which
  # `bd list` hides by default; without it a held anchor reads released.
  rows=$(bd_list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --include-gates --metadata-field "gc.demand_for=${1:-}") || return 2
  printf '%s' "$rows" | jq -e --arg a "${1:-}" \
    '[ .[] | select(((.metadata["gc.demand_for"] // "") | tostring) == $a) ] | length > 0' \
    >/dev/null 2>&1 && return 0
  return 1
}
# Fails CLOSED — a ledger that will not read answers "held", because releasing an
# anchor a person is holding hands their decision back to a pool.
takeaway_is_holding() { # <anchor-id>; 0 = a person owes an answer here
  local st; demand_gate_state "${1:-}"; st=$?
  [ "$st" -ne 1 ]
}
# <<< takeaway-hold-discriminator

# >>> anchor-foreign-blocker-guard
# The stale-base rework dispatch brings a conflicted branch current, which is
# routine hygiene only when the anchor is otherwise heading to merge. An anchor a
# live blocker holds is not: a plain depends-on edge on another PR, an in-flight
# review, a demand a person owes. Rebasing under one performs work the merge is
# already held on ("a dep-edge holder holds regardless" — merge.sh), one horn of a
# decision the operator has not made, or a head moved out from under a live
# review. takeaway_is_holding catches the demand; a closed demand on an anchor
# still blocked by an ordinary prerequisite does not read there, and this reads
# that gap — every blocker merge.sh would hold the merge on.
#
# The arm's OWN children are the mechanism, not a hold: each blocks its anchor so
# the merge waits for the fix, and the dedup below re-routes a stranded one or
# adopts an orphaned one, so none may suppress the dispatch. So a blocker is
# foreign unless the dispatch below would recognize it as its own — by the same
# three signals it uses: it is on this branch (the dedup key), OR it carries this
# anchor's rework marker (task_kind=rework, anchor_bead=<anchor>), OR it keeps the
# deterministic dispatch title the orphan adoption matches. Any one survives a
# half-landed stamp that drops the others, so the guard never reads a child whose
# stamp partly failed as a foreign freeze. Prints the holding
# ids; fails CLOSED — an unreadable edge list holds the dispatch, the safe side
# for a rewrite.
anchor_foreign_blocker() { # <anchor-id> <own-branch> <own-title>; prints foreign live blocker ids; 0 = at least one holds
  local rows out
  rows=$(gc bd dep list "${1:-}" --direction=down -t blocks --json 2>/dev/null) || return 0
  rows=$(printf '%s' "$rows" | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 0
  out=$(printf '%s' "$rows" | jq -r --arg a "${1:-}" --arg b "${2:-}" --arg t "${3:-}" --arg live "$LIVE_STATUSES" '
    ($live | split(",")) as $ls
    | [ .[]
        | select(((.status // "open") | ascii_downcase) as $st | ($ls | index($st)) != null)
        | select( (($b != "") and ((.metadata.branch // "") == $b)) | not )
        | select( ((.metadata.task_kind // "") == "rework" and (.metadata.anchor_bead // "") == $a) | not )
        | select( (($t != "") and (((.title // "") | contains($t)))) | not )
        | .id ] | join(" ")' 2>/dev/null)
  printf '%s' "$out"
  [ -n "$out" ]
}
# <<< anchor-foreign-blocker-guard

# >>> anchor-decision-guard
# A dispatch arm stands down when a person owes a decision on this anchor's
# reconciliation. takeaway_is_holding answers that for a demand filed on the
# anchor, but a base-supersession or reconcile decision is filed on the in-flight
# rework it concerns instead (gc.demand_for=<child>), and anchor_foreign_blocker
# excludes those children as the arm's own mechanism — so a demand on one reaches
# no arm without this. The anchor and its live rework children share one branch,
# so a demand a converse sitting owns on either holds the merge: bringing the
# branch current under it performs one horn of the pending question by fait
# accompli, the same reason a demand on the anchor holds it. Reads the demand
# ledger for the anchor and for each live rework child (task_kind=rework,
# anchor_bead=<anchor>) through the shared discriminator, which excludes the cap's
# own demand and fails closed; an unreadable child list holds too, the safe side
# for a branch rewrite. 0 = a person owes a decision here.
anchor_decision_held() { # <anchor-id>
  local kids kid
  takeaway_is_holding "${1:-}" && return 0
  kids=$(bd_list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --metadata-field "anchor_bead=${1:-}") || return 0
  for kid in $(printf '%s' "$kids" | jq -r '.[] | select(((.metadata.task_kind // "") | tostring) == "rework") | .id' 2>/dev/null); do
    [ -n "$kid" ] || continue
    takeaway_is_holding "$kid" && return 0
  done
  return 1
}
# <<< anchor-decision-guard

# >>> pr-posture-vocabulary
# Mirrors lifecycle/lifecycle.toml [posture]; pr-facts.test.sh fails on drift.
# Listed in the precedence the derivation applies, strongest human signal first.
PR_POSTURES="changes_requested commented approved review_required none"
# <<< pr-posture-vocabulary
# >>> pr-writeback-contract
# The trail the operator reads in the PR. EYES marks a comment the city picked
# up, and THUMBS_UP replaces it once the comment is resolved, so a handled
# comment never still reads as merely looked at. GitHub's reaction set has no
# check mark and no question mark, so the other two states are glyphs leading a
# reply: a check mark for resolved, a question mark for awaiting a person.
# The marker identifies our own reply, so a later pass can tell one it already
# posted from a human's, and every reply carries it. A state reply also carries
# a mark line naming its state (resolved, or awaiting:<visit>) and, on the
# Conversation tab where no thread holds the comments it answers, their tokens
# (r<review id>, i<issue comment id>). A finding's owed reply carries a line
# naming the finding. Idempotence is read back off GitHub (viewerHasReacted,
# these markers, isResolved) and never off a bead key, so a write that failed is
# retried and a write that landed is never repeated.
WB_REACTION="EYES"
WB_RESOLVED_REACTION="THUMBS_UP"
WB_MARKER="<!-- gc-writeback -->"
WB_GLYPH_RESOLVED="✅"
WB_GLYPH_AWAITING="❓"
# A ruled machine finding the city posts to the PR carries
# `<!-- gc-finding:<id> -->`, and the answer it posts once the finding closes
# carries `<!-- gc-finding:<id>:answered -->`. A later pass finds the finding's
# comment by it, and the BLOCKED arm reads the shared prefix to tell a thread the
# write-back resolves itself from one a person has to. Both posts also carry the
# city's mark, which pr-post.sh appends. Neither carries WB_MARKER, so the
# reply-and-resolve plan never reads a finding's thread as one the city already
# answered.
WB_FINDING_MARKER="<!-- gc-finding:"
# A first activation over every open PR would otherwise post each one's backlog
# of ruled findings in a single pass, at the tail of a pass the arms after it
# share a deadline with: each post costs a ledger read and a stamp, and GitHub
# rate-limits a token that creates comments too quickly. Posts and answers past
# the cap wait for the next pass.
WB_FINDING_CAP=10
# A first activation over a long-running PR would otherwise post one reaction per
# outstanding comment in a single pass. It holds the batch's replies and
# resolves back with the comments it defers, since a thread answered before its
# comment is acknowledged claims the city acted on something it never showed it
# had picked up. A swap owed on a comment answered in an earlier pass draws on
# the same cap. PR_FACTS_REACT_CAP overrides the cap. Anything but a positive
# integer written without a leading zero keeps 50, because a cap of 0 would
# hold every batch's answers forever.
WB_REACT_CAP="${PR_FACTS_REACT_CAP:-50}"
case "$WB_REACT_CAP" in *[!0-9]*|0*) WB_REACT_CAP=50 ;; esac
# <<< pr-writeback-contract
# >>> comment-batch-ledger
# Each comment id space keeps a ledger of the batches routed under it:
# pr_comment_batch for inline comments, pr_review_batch for review bodies, and
# pr_issue_comment_batch for Conversation comments. A ledger is one
# `<disposition>|<exclusive floor>|<inclusive mark>` record per batch, oldest
# first, joined by ";". The spaces draw ids from unrelated ranges, so a comment's
# batch is looked up in its own space's ledger only. A routed batch extends the
# newest record when it names the same disposition, and otherwise appends one
# whose floor is the mark it replaces.
WB_LEDGER_JQ='
  def ledger_num: if test("^[0-9]+$") then tonumber else error("malformed record") end;
  def ledger_records: [ split(";")[] | select(length > 0)
    | split("|") | if length == 3 then . else error("malformed record") end
    | { disp: .[0], lo: (.[1] | ledger_num), hi: (.[2] | ledger_num) } ];
  def ledger_string: [ .[] | "\(.disp)|\(.lo)|\(.hi)" ] | join(";");
  def ledger_route($disp; $lo; $hi):
    if length > 0 and .[-1].disp == $disp
    then .[0:-1] + [ .[-1] | .hi = ([ .hi, $hi ] | max) ]
    else . + [ { disp: $disp, lo: $lo, hi: ([ $lo, $hi ] | max) } ] end;'
# The review and Conversation ledgers record a batch only when it carries a
# comment in their space; a malformed ledger exits non-zero.
ledger_route_space() { # <ledger> <disposition> <floor> <mark>
  jq -rn --arg batch "$1" --arg disp "$2" --argjson lo "$3" --argjson hi "$4" "$WB_LEDGER_JQ"'
    $batch | ledger_records | (if $hi > $lo then ledger_route($disp; $lo; $hi) else . end)
    | ledger_string' 2>/dev/null
}
# The records of a ledger at the kept indices. Exits 0 only when that drops a
# record, so the caller writes a ledger only when it changed.
ledger_keep() { # <ledger> <comma-joined indices, or "-">
  local kept
  [ -n "$2" ] && [ "$2" != "-" ] || return 1
  kept=$(jq -rn --arg batch "$1" --arg keep "$2" '
    ($keep | split(",") | map(tonumber)) as $ks
    | [ $batch | split(";") | map(select(length > 0)) | to_entries[]
        | select(.key as $k | ($ks | index($k)) != null) | .value ] | join(";")' 2>/dev/null) || return 1
  [ -n "$kept" ] && [ "$kept" != "$1" ] || return 1
  printf '%s' "$kept"
}
# <<< comment-batch-ledger

gh_graphql() { # <query> [gh -f/-F args...]; non-zero = "could not tell"
  local q="$1"; shift
  local raw rc
  raw=$(gh api graphql --hostname "$ORIGIN_HOST" -f query="$q" "$@" 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  printf '%s' "$raw" | scrub
}
# >>> review-threads-read
# Every review thread on a PR, read once per anchor visit and shared by the
# readers that ask about threads: the BLOCKED arm's unresolved count, the
# unengaged-thread count and the answered-comment read are jq projections over
# the same nodes. Paginated to exhaustion: a projection over a truncated
# connection decides wrongly. A thread carries its first 100 comments, and each
# projection says which way a longer thread's cut errs. A comment's id is read as
# fullDatabaseId, a BigInt GitHub serializes as a string: databaseId is a 32-bit
# Int GitHub has deprecated for that reason, and review-comment ids already pass
# 2^31. Each comment also carries its creation instant and its review's
# submission, the facts gc_city_own dates a post by.
REVIEW_THREADS_QUERY='query($owner:String!,$repo:String!,$num:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){pullRequest(number:$num){
    reviewThreads(first:100,after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{isResolved comments(first:100){nodes{fullDatabaseId author{login} body createdAt
        pullRequestReview{submittedAt}}}}}}}}'
RT_NUM=""; RT_NODES=""
# Loads <pr-number>'s threads into RT_NODES, one JSON array of thread nodes, and
# returns 0; a second call for the same PR reuses them. Returns non-zero with
# RT_NODES empty when the connection could not be read, and an unreadable read is
# never an empty one. Call it in the current shell, never inside $(...), or the
# read does not outlive the call.
review_threads_load() { # <pr-number>
  [ -n "$RT_NUM" ] && [ "$RT_NUM" = "${1:-}" ] && return 0
  local raw nodes
  RT_NUM=""; RT_NODES=""
  raw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate -f query="$REVIEW_THREADS_QUERY" \
    -f owner="${ORIGIN_REPO%%/*}" -f repo="${ORIGIN_REPO#*/}" -F num="$1" 2>/dev/null) || return 1
  [ -n "$raw" ] || return 1
  nodes=$(printf '%s' "$raw" | scrub | jq -sc '
    ([ .[] | .data.repository.pullRequest.reviewThreads ] | map(select(. != null))) as $rt
    | if ($rt | length) == 0 then error("no reviewThreads in response")
      else [ $rt[].nodes[]? ] end' 2>/dev/null) || return 1
  [ -n "$nodes" ] || return 1
  RT_NUM="$1"; RT_NODES="$nodes"
}
# Count of unresolved review threads in RT_NODES, as a non-negative integer. A
# thread holding only the city's own finding comments is not counted: the
# write-back resolves it once its finding closes, so it is no cause to ask a
# person for. A human who writes in one makes it a thread like any other. The
# comment cut does not touch the count: the city writes at most a finding's post
# and its answer into a thread, so a thread cut at 100 comments holds someone
# else's. Non-zero without output on a projection that does not yield one, and
# the BLOCKED arm below must not escalate a guessed cause.
unresolved_threads() {
  local n
  n=$(printf '%s' "$RT_NODES" | jq --arg self "$SELF_LOGIN" --arg since "$PSINCE" --arg fm "$WB_FINDING_MARKER" "$CITY_OWN_DEF"'
    def finding_only: (.comments.nodes // []) as $cs
      | ($cs | length) > 0
        and all($cs[]; gc_city_own($self; $since) and ((.body // "") | contains($fm)));
    [ .[] | select((.isResolved // false) == false) | select(finding_only | not) ] | length' 2>/dev/null) || return 1
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$n"
}
# <<< review-threads-read
# Branch-protection facts for <branch>, read from its active rules: whether an
# unresolved review thread blocks a merge (required_review_thread_resolution)
# and how many approving reviews are required. Sets PROT_STATE=known|unknown;
# when known, PROT_THREAD_REQ=true|false and PROT_APPROVALS to the required
# count. An unreadable read is `unknown`, never a zero requirement — escalating
# a BLOCKED cause named off `unknown` would be a guess.
review_gates_for() { # <branch>
  local b="$1" rules rrc
  PROT_STATE=""; PROT_THREAD_REQ="false"; PROT_APPROVALS="0"
  rules=$(gh_api_origin "repos/$ORIGIN_REPO/rules/branches/$b" 2>/dev/null); rrc=$?
  if [ "$rrc" -ne 0 ] || ! printf '%s' "$rules" | jq -e 'type == "array"' >/dev/null 2>&1; then
    PROT_STATE="unknown"; return 0
  fi
  PROT_THREAD_REQ=$(printf '%s' "$rules" | jq -r '
    [ .[] | select(type == "object") | select((.type // "") == "pull_request")
      | .parameters.required_review_thread_resolution // false ] | any')
  PROT_APPROVALS=$(printf '%s' "$rules" | jq -r '
    [ .[] | select(type == "object") | select((.type // "") == "pull_request")
      | .parameters.required_approving_review_count // 0 ] | max // 0')
  case "$PROT_THREAD_REQ" in true|false) : ;; *) PROT_THREAD_REQ="false" ;; esac
  case "$PROT_APPROVALS" in ''|*[!0-9]*) PROT_APPROVALS="0" ;; esac
  PROT_STATE="known"
}

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
ALL_STATUSES="$LIVE_STATUSES,closed"

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=pace-lib.sh
. "$_bd_lib_dir/pace-lib.sh" || { echo "cannot source pace-lib.sh beside this script" >&2; exit 1; }
# The approval rule merge.sh lands on, REVIEW_VERDICT_DEF; the conflict arm
# brings only an approved PR current.
# shellcheck source=review-verdict.sh
. "$_bd_lib_dir/review-verdict.sh" || { echo "cannot source review-verdict.sh beside this script" >&2; exit 1; }
escalate() { # <subject> <key> <message> — best-effort; escalate.sh dedups the situation
  [ -x "$ESCALATE" ] || return 0
  "$ESCALATE" --subject "$1" --key "$2" --message "$3" >/dev/null 2>&1 || true
}
# Re-derive one anchor's status: label through its single writer. cur_labels is
# the anchor's label list from this pass's pinned PR read, which spares the writer
# a read of its own; a call can change those labels, so the list is dropped after
# it and a later call on the same anchor reads the PR afresh. Best-effort: a label
# that does not land is left for the full pass's reconcile.
reconcile_status_label() { # <anchor> <pr-number>
  "$PR_STATUS_LABEL" reconcile --anchor "$1" --pr "$2" \
    --repo "$ORIGIN_REPO_Q" --host "$ORIGIN_HOST" --current-labels "${cur_labels:-}" \
    >/dev/null 2>&1 || true
  cur_labels=""
}
# The escalation keys this script files on an anchor to hold its PR's merge
# until a person answers, for PR number $n: rework or close (pr-abandoned), a
# moved base (pr-retargeted), feedback nothing routed (pr-comments), review
# threads nobody engaged (pr-unengaged-threads), threads branch protection
# requires resolved (merge-blocked-threads), and red checks parked to a person
# (pr-fix-noncode, pr-fix-capped). A PR closed with a pre-recorded disposition
# has no merge left to hold, so the disposition arm retires these visits. An arm
# that files a new merge-holding visit adds its key here.
MERGE_PATH_KEYS_JQ='
  def merge_path_key($n):
    test("^pr-(abandoned|retargeted|fix-noncode|fix-capped)\\." + $n + "$")
    or test("^pr-(comments|unengaged-threads)\\." + $n + "\\.")
    or . == "merge-blocked-threads";'
visit_for() { # <subject> <key> — the LIVE visit escalate.sh keeps for this situation
  # Both stamps are re-checked here as well as queried: this id gets pr_number
  # written onto it, so a row that came back for another subject would stamp a
  # stranger's bead and hold the wrong merge.
  local rows
  rows=$(bd_list --status="$LIVE_STATUSES" --metadata-field "escalation_key=$2" \
           --metadata-field "gc.continuation_group=$1") || return 1
  printf '%s' "$rows" | jq -r --arg s "$1" --arg k "$2" '
    [ .[] | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
          | select(((.metadata.escalation_key // "") | tostring) == $k)
          | .id ] | .[0] // empty' 2>/dev/null
}
# retract_dispose_visits <anchor> <num> <reading> — conclude the disposition
# arm's refused-close report once the close it asked for has landed. Every visit
# filed under pr-dispose-failed.<num> for the anchor is retracted moot through
# escalate.sh's retract verb, which leaves one a person is engaged in to them.
# Each visit is read back and reported. A visit still open and unengaged is
# retried by the next full pass's sweep below.
retract_dispose_visits() {
  local a="$1" key="pr-dispose-failed.$2" reading="$3" vids v row st who
  vids=$(gc bd list --status="$LIVE_STATUSES" --metadata-field "escalation_key=$key" \
           --metadata-field "gc.continuation_group=$a" --limit=0 --json 2>/dev/null | scrub \
         | jq -r --arg k "$key" --arg s "$a" '.[]
             | select(((.metadata.escalation_key // "") | tostring) == $k)
             | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s) | .id' 2>/dev/null) || vids=""
  [ -n "$vids" ] || return 0
  [ -x "$ESCALATE" ] && "$ESCALATE" --retract --subject "$a" --key "$key" --message "$reading" >/dev/null 2>&1 </dev/null
  for v in $vids; do
    row=$(gc bd show "$v" --json 2>/dev/null | scrub)
    st=$(printf '%s' "$row" | jq -r '.[0].status // ""' 2>/dev/null)
    who=$(printf '%s' "$row" | jq -r '.[0] | ((.assignee // "") | tostring) as $w
      | ((.metadata["gc.session_name"] // "") | tostring) as $n
      | if $w != "" then $w elif $n != "" then "session " + $n else "" end' 2>/dev/null)
    if [ "$st" = "closed" ]; then
      echo "$PROG: $a — retracted its own pr-dispose-failed visit $v as moot (the close landed)"
    elif [ "$st" = "in_progress" ] || [ -n "$who" ]; then
      echo "$PROG: $a — closed, but its own pr-dispose-failed visit $v is engaged (${who:-$st}); it is theirs to conclude" >&2
    else
      echo "$PROG: $a — closed, but its own pr-dispose-failed visit $v is still ${st:-unreadable}; a full pass retracts it while it is open and unengaged" >&2
    fi
  done
}
# refresh_dispose_visits <anchor> <num> <message> <kids-note> — keep the
# disposition arm's refused-close report current. escalate.sh files the visit
# once and dedups every later refusal onto it, so a close refused for a new
# reason would leave the visit naming an obstruction that has already cleared.
# Each open visit under pr-dispose-failed.<num> for the anchor that nobody is
# engaged in takes this pass's message as its description when that differs.
# The note naming the parked children an earlier pass disposed is carried
# forward: they are closed by now, so this pass names none, and the note is how
# an operator who reverses the disposition knows what to restore.
refresh_dispose_visits() {
  local a="$1" key="pr-dispose-failed.$2" msg="$3" kids="$4" rows v old want
  local kids_lead=" The branch's parked rework/rebase children ("
  rows=$(gc bd list --status=open --metadata-field "escalation_key=$key" \
           --metadata-field "gc.continuation_group=$a" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 0
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    old=$(printf '%s' "$rows" | jq -r --arg v "$v" '.[] | select(.id == $v) | (.description // "")' 2>/dev/null)
    want="$msg$kids"
    if [ -z "$kids" ]; then
      case "$old" in *"$kids_lead"*) want="$msg$kids_lead${old#*"$kids_lead"}" ;; esac
    fi
    [ "$old" = "$want" ] && continue
    if gc bd update "$v" --description "$want" >/dev/null 2>&1; then
      echo "$PROG: $a — refreshed its pr-dispose-failed visit $v with this pass's refusal"
    else
      echo "$PROG: $a — could not refresh its pr-dispose-failed visit $v; it still names an earlier refusal" >&2
    fi
  done <<REFRESH_EOF
$(printf '%s' "$rows" | jq -r --arg k "$key" --arg s "$a" '.[]
    | select(((.metadata.escalation_key // "") | tostring) == $k)
    | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
    | select(((.assignee // "") | tostring) == "" and ((.metadata["gc.session_name"] // "") | tostring) == "")
    | .id' 2>/dev/null)
REFRESH_EOF
}
mint_rework_child() { # <reuse-id|""> <title> <anchor> <branch> <target> <reason> <mode> <pr-url> <pr-number>
  # Atomic birth for a rework child: every identity key lands together, or the
  # child is not left behind to be misread. A child stamped with only some of its
  # keys can still veto a merge (an open bead with a blocks-dep on the anchor is
  # enough) yet be impossible to rescue (the stranded re-route matches on
  # rejection_reason naming the head), adopt (needs an empty branch/anchor_bead),
  # or reap — the silent wedge this guards against. `gc bd create --metadata`
  # writes the whole payload in one insert; a reused strand/orphan takes one
  # all-or-nothing --set-metadata. mint_rework_verify reads the write back IN FULL
  # — the role marker, rejection_reason (the rescue key), and the handoff-critical
  # merge_strategy and PR identity (existing_pr/pr_url/pr_number) that keep the
  # refinery on an mr-mode hand-back instead of a direct push to target — and a
  # newborn that will not verify is closed rather than left half-stamped. Prints the
  # fully-formed, dep-attached, UNROUTED child id and returns 0; the caller stamps
  # gc.routed_to last, so only a complete child becomes claimable. Prints nothing
  # and returns 1 when the caller should retry next pass.
  local reuse="$1" title="$2" anchor="$3" branch="$4" target="$5" reason="$6" mode="$7" prurl="$8" prnum="$9"
  local meta fix ok
  meta=$(jq -nc --arg ab "$anchor" --arg br "$branch" --arg tg "$target" --arg rr "$reason" \
    --arg pm "$mode" --arg ep "$prurl" --arg pn "$prnum" \
    '{task_kind:"rework", anchor_bead:$ab, branch:$br, target:$tg, rejection_reason:$rr, prepare_mode:$pm, merge_strategy:"mr", existing_pr:$ep, pr_url:$ep, pr_number:$pn}' 2>/dev/null)
  [ -n "$meta" ] || return 1
  if [ -n "$reuse" ]; then
    fix="$reuse"
    gc bd update "$fix" --set-metadata task_kind=rework --set-metadata anchor_bead="$anchor" \
      --set-metadata branch="$branch" --set-metadata target="$target" \
      --set-metadata rejection_reason="$reason" --set-metadata prepare_mode="$mode" \
      --set-metadata merge_strategy=mr --set-metadata existing_pr="$prurl" \
      --set-metadata pr_url="$prurl" --set-metadata pr_number="$prnum" >/dev/null 2>&1 || true
  else
    fix=$(gc bd create "$title" -t task --metadata "$meta" --json 2>/dev/null | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
  fi
  [ -n "$fix" ] || return 1
  # The child now exists in the store (freshly created, or reuse-restamped); drop
  # the per-pass bd_list cache so a later anchor's "does a child already exist?"
  # probe refetches and cannot mint a duplicate on a stale "no child". The verify
  # and husk-close below read with gc bd show, which does not repopulate the
  # cache, so the next bd_list sees whatever final state they leave. No-op outside
  # a reconcile pass.
  bd_cache_clear
  ok=$(mint_rework_verify "$fix" "$anchor" "$branch" "$target" "$reason" "$mode" "$prurl" "$prnum")
  if [ "$ok" != "true" ]; then
    # One retry: the write is all-or-nothing, so re-applying the whole payload
    # either lands it or leaves the prior state untouched — it cannot add a key.
    gc bd update "$fix" --set-metadata task_kind=rework --set-metadata anchor_bead="$anchor" \
      --set-metadata branch="$branch" --set-metadata target="$target" \
      --set-metadata rejection_reason="$reason" --set-metadata prepare_mode="$mode" \
      --set-metadata merge_strategy=mr --set-metadata existing_pr="$prurl" \
      --set-metadata pr_url="$prurl" --set-metadata pr_number="$prnum" >/dev/null 2>&1 || true
    ok=$(mint_rework_verify "$fix" "$anchor" "$branch" "$target" "$reason" "$mode" "$prurl" "$prnum")
  fi
  if [ "$ok" != "true" ]; then
    # The write did not fully land. Close the child ONLY if what did land makes
    # it a husk: able to veto (a branch, or a pr_number) yet missing its rescue
    # key (rejection_reason). A child with neither veto vector is an inert orphan
    # the adoption path reuses next pass, and a strand keeps its own
    # rejection_reason (a dropped write leaves the prior value in place), so
    # neither is unmade here — only the veto-without-rescue husk is.
    local snap rr_now br_now pn_now
    snap=$(gc bd show "$fix" --json 2>/dev/null | scrub)
    rr_now=$(printf '%s' "$snap" | jq -r '.[0].metadata.rejection_reason // ""' 2>/dev/null)
    br_now=$(printf '%s' "$snap" | jq -r '.[0].metadata.branch // ""' 2>/dev/null)
    pn_now=$(printf '%s' "$snap" | jq -r '.[0].metadata.pr_number // ""' 2>/dev/null)
    if [ -z "$rr_now" ] && { [ -n "$br_now" ] || [ -n "$pn_now" ]; }; then
      gc bd update "$fix" --status=closed --set-metadata gc.outcome=abandoned \
        --append-notes "Unmade by $PROG: a partial stamp left it able to veto (branch/pr_number) but with no rejection_reason to be rescued by, so it is closed rather than left as a half-stamped husk (atomic birth)." >/dev/null 2>&1 || true
    fi
    return 1
  fi
  gc bd dep "$fix" --blocks "$anchor" >/dev/null 2>&1 \
    || echo "$PROG: WARN could not attach rework $fix as a blocks-dep of $anchor" >&2
  printf '%s' "$fix"
  return 0
}

mint_rework_verify() { # <bead> <anchor> <branch> <target> <reason> <mode> <pr-url> <pr-number> — echoes "true" iff the full identity read back
  # rejection_reason is verified alongside the role marker: a child carrying the
  # marker but not the reason is the husk a role-marker-only re-stamp produced.
  # merge_strategy and the PR identity (existing_pr/pr_url/pr_number) are handoff-
  # critical too: a child that keeps its rescue keys but drops these hands the
  # refinery a rework of no PR, which it resolves to merge_strategy=direct and a
  # push straight to the target branch — the same partial-write wedge one field
  # over. merge_strategy is always minted "mr"; the PR keys must read back the
  # values this child was minted with. pr_number is compared as a string: the
  # create payload stores it as one, and a --set-metadata re-stamp stores it as
  # a number.
  gc bd show "$1" --json 2>/dev/null | scrub | jq -r \
    --arg ab "$2" --arg br "$3" --arg tg "$4" --arg rr "$5" --arg pm "$6" --arg ep "$7" --arg pn "$8" '
    (.[0].metadata // {}) as $m
    | (($m.task_kind // "") == "rework" and ($m.anchor_bead // "") == $ab
       and ($m.branch // "") == $br and ($m.target // "") == $tg
       and ($m.rejection_reason // "") == $rr and ($m.prepare_mode // "") == $pm
       and ($m.merge_strategy // "") == "mr"
       and ($m.existing_pr // "") == $ep and ($m.pr_url // "") == $ep
       and (($m.pr_number // "") | tostring) == $pn) | tostring' 2>/dev/null
}

gh_rows() { # <api path> — one paginated endpoint re-collected into ONE array
  # `gh --paginate` emits one array per PAGE; --jq '.[]' flattens the pages and
  # jq -s makes the whole read an array again. Non-zero = "could not tell".
  local raw rc
  raw=$(gh_api_origin --paginate "$1" --jq '.[]' 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] || return 1
  printf '%s' "$raw" | scrub | jq -sc '.' 2>/dev/null
}
# >>> unanswered-feedback-body
# The work order carries the feedback itself, not a link to it. A polecat has
# to know what was asked without a second GitHub read, and a review BODY is not
# on the /files page its inline comments live on, so an objection stated in the
# body alone reaches a page-pointing work order as nothing at all.
feedback_body() { # <reviews-json> <comments-json> <review-mark> <comment-mark> <issue-comments-json> <issue-mark> — markdown on stdout
  # The JSON lists go in on stdin, never as --argjson: one that exceeds the OS
  # per-argument limit (Linux MAX_ARG_STRLEN, 128 KiB) makes jq fail to exec, and
  # a busy PR's comment list clears it. `input` reads them back in printed order.
  { printf '%s\n' "$1"; printf '%s\n' "$2"; printf '%s\n' "$5"; } | \
  jq -nr --argjson rmark "$3" --argjson cmark "$4" --argjson imark "$6" \
         --arg self "$SELF_LOGIN" --arg since "$PSINCE" "$CITY_OWN_DEF"'
    def clip($n): if (length) > $n then (.[0:$n] + "\n\n_(truncated — the rest is on the PR)_") else . end;
    def body: ((.body // "") | tostring);
    (input) as $revs | (input) as $cmts | (input) as $icmts |
    ([ $revs[] | select(gc_city_own($self; $since) | not)
              | (((.state // "") | tostring)) as $st
              | select((["COMMENTED", "CHANGES_REQUESTED"] | index($st)) != null)
              | select((body | gsub("[[:space:]]"; "")) != "")
              | select(((.id // 0) | tonumber) > $rmark) ] | sort_by(.id)) as $R
  | ([ $cmts[] | select(gc_city_own($self; $since) | not)
              | select(((.id // 0) | tonumber) > $cmark) ] | sort_by(.id)) as $C
  | ([ $icmts[] | select(gc_city_own($self; $since) | not)
              | select(((.id // 0) | tonumber) > $imark) ] | sort_by(.id)) as $I
  | ((if ($R | length) > 0 then ["## Review bodies"]
        + [ $R[] | "### \(.user.login // "?") — \(.state // "?") (review \(.id))\n\n\(body | clip(4000))" ]
      else [] end)
   + (if ($C | length) > 0 then ["## Inline comments"]
        + [ $C[] | "### \(.path // "?")\(if ((.line // .original_line) != null) then ":\(.line // .original_line)" else "" end) — \(.user.login // "?") (comment \(.id))\n\n\(body | clip(2000))" ]
      else [] end)
   + (if ($I | length) > 0 then ["## Conversation comments"]
        + [ $I[] | "### \(.user.login // "?") (comment \(.id))\n\n\(body | clip(2000))" ]
      else [] end)
   | join("\n\n")) | clip(16000)' 2>/dev/null
}
# The same batch feedback_body renders, one finding record per objection, for the
# finding beads the validator rules (specs/tk-ztapg/review-cycle-architecture.md,
# "Findings"). A review body, an inline comment, and a Conversation comment each
# carry their own locus — the review, the file the comment sits on, or the
# Conversation — and finding.sh keys the dedup on lane plus a normalized locus and
# message. The line an inline comment sits on rides the locus for a reader;
# finding.sh normalizes it out of the key, so a rebase that renumbers the file
# does not re-raise the finding. An empty body is no objection and is dropped, so
# a bodyless CHANGES_REQUESTED contributes only through its inline comments.
feedback_findings() { # <reviews> <comments> <review-mark> <comment-mark> <issue-comments> <issue-mark> — JSON array of {login,locus,message,comment_id,review_id}
  # comment_id is the GitHub databaseId of the row that raised the objection.
  # For an INLINE review comment it is also the databaseId the reviewThread
  # carries, so the write-back can find the thread and post a declined finding's
  # owed reply into it; a review-body or Conversation comment has no thread, so
  # its id matches none and the write-back answers those on the PR itself.
  # review_id is the databaseId of the PR review the objection belongs to — its
  # own id for a review body, the parent review's for an inline comment — so the
  # write-back groups an anchor's human findings by review and dismisses one when
  # all of its findings clear. A Conversation comment belongs to no review, so it
  # carries none and holds no review's dismissal.
  { printf '%s\n' "$1"; printf '%s\n' "$2"; printf '%s\n' "$5"; } | \
  jq -nc --argjson rmark "$3" --argjson cmark "$4" --argjson imark "$6" \
         --arg self "$SELF_LOGIN" --arg since "$PSINCE" "$CITY_OWN_DEF"'
    def body: ((.body // "") | tostring);
    def has_body: ((body | gsub("[[:space:]]"; "")) != "");
    (input) as $revs | (input) as $cmts | (input) as $icmts |
    ([ $revs[] | select(gc_city_own($self; $since) | not)
              | (((.state // "") | tostring)) as $st
              | select((["COMMENTED", "CHANGES_REQUESTED"] | index($st)) != null)
              | select(has_body)
              | select(((.id // 0) | tonumber) > $rmark)
              | { login: ((.user.login // "?") | tostring), locus: "PR review", message: body,
                  comment_id: ((.id // 0) | tostring), review_id: ((.id // 0) | tostring) } ])
  + ([ $cmts[] | select(gc_city_own($self; $since) | not)
              | select(has_body)
              | select(((.id // 0) | tonumber) > $cmark)
              | { login: ((.user.login // "?") | tostring),
                  locus: (((.path // "PR conversation") | tostring)
                          + (if ((.line // .original_line) != null) then ":" + ((.line // .original_line) | tostring) else "" end)),
                  message: body, comment_id: ((.id // 0) | tostring),
                  review_id: ((.pull_request_review_id // "") | tostring) } ])
  + ([ $icmts[] | select(gc_city_own($self; $since) | not)
              | select(has_body)
              | select(((.id // 0) | tonumber) > $imark)
              | { login: ((.user.login // "?") | tostring), locus: "PR conversation", message: body,
                  comment_id: ((.id // 0) | tostring), review_id: "" } ])' 2>/dev/null
}
# The ids in <rows-json> that are feedback, as a JSON array: every row that is
# not the city's own post (gc_city_own), whoever wrote it. The comment and
# Conversation spaces count feedback by this one rule, so the read that decides
# whether to ask the threads, the marks that record what they answered, and the
# count that routes cannot disagree about which comment is feedback.
foreign_ids() { # <rows-json>
  printf '%s' "$1" | jq -c --arg self "$SELF_LOGIN" --arg since "$PSINCE" "$CITY_OWN_DEF"'
    [ .[] | select(gc_city_own($self; $since) | not) | (.id // 0) ]' 2>/dev/null
}
# The ids of the reviews in <reviews-json> whose body counts as feedback, as a
# JSON array: not the city's own post (gc_city_own), COMMENTED or
# CHANGES_REQUESTED, and carrying a body. An unmarked review under our own login
# after the provenance cutover is a model or operator review run on the city's
# account, and is feedback like any other. A review with an empty body carries
# only its inline comments, which the comment space already sees; counting it
# would leave a posture no comment id can ever answer. CHANGES_REQUESTED counts
# beside COMMENTED: an operator uses it to mean "change this", and it is the
# feedback the loop most has to answer. A dismissed review is in neither state,
# so a dismissal takes its ids out of the batch.
counted_review_ids() { # <reviews-json>
  printf '%s' "$1" | jq -c --arg self "$SELF_LOGIN" --arg since "$PSINCE" "$CITY_OWN_DEF"'
    [ .[] | select(gc_city_own($self; $since) | not)
      | (((.state // "") | tostring)) as $st
      | select((["COMMENTED", "CHANGES_REQUESTED"] | index($st)) != null)
      | select(((.body // "") | tostring | gsub("[[:space:]]"; "")) != "")
      | (.id // 0) ]' 2>/dev/null
}
# The highest id in a one-line JSON id array on stdin, or 0. Read in the shell: it
# runs on every anchor of every pass, and the array is the flat `[1,2,3]` the two
# readers above print.
max_id() {
  local ids="" i n=0
  IFS= read -r ids || true
  ids=${ids#\[}; ids=${ids%\]}
  local IFS=,
  for i in $ids; do
    case "$i" in ''|*[!0-9]*) continue ;; esac
    [ "$i" -gt "$n" ] && n="$i"
  done
  printf '%s' "$n"
}
max_foreign_id() { foreign_ids "$1" | max_id; } # <rows-json>
max_counted_review_id() { counted_review_ids "$1" | max_id; } # <reviews-json>
# The ids in the JSON id array <ids-json> above <lo> and at or below <hi>.
ids_within() { # <ids-json> <lo> <hi>
  printf '%s' "$1" | jq -c --argjson lo "$2" --argjson hi "$3" \
    '[ .[] | select(. > $lo and . <= $hi) ]' 2>/dev/null
}
# How far the review threads have answered past <mark>: walking the ids in
# <ids-json> above the mark in order, the last one reached before the first id
# not in <answered-json>, or <mark> itself when the first is not answered. The
# feedback through that id is all answered, so a later pass whose newest feedback
# sits at or below it has nothing for the threads to say.
answered_through() { # <mark> <ids-json> <answered-json>
  { printf '%s\n' "$2"; printf '%s\n' "$3"; } | jq -nr --argjson mark "$1" '
    (input) as $ids | (input) as $ans
    | (reduce $ans[] as $a ({}; .[$a | tostring] = true)) as $done
    | reduce ([ $ids[] | select(. > $mark) ] | sort)[] as $i ({m: $mark, open: true};
        if .open and $done[$i | tostring] == true then .m = $i else .open = false end)
    | .m' 2>/dev/null
}
# The reviews whose bodies the review threads have answered, as a JSON array of
# ids: each carries at least one inline comment, and every one of those is in
# <answered-ids>. A review's body frames the inline comments it carries, so a
# sitting that answered each of them in its thread has answered the review. Only
# the thread read confirms a comment here. A comment the watermark already passed
# is not taken as answered on the mark's word, so a review submitted late over
# such comments still routes. A review with no inline comment has no thread to
# answer it and is never listed. The lists go in on stdin, the way
# feedback_body takes them.
answered_review_ids() { # <reviews-json> <comments-json> <answered-ids-json>
  { printf '%s\n' "$1"; printf '%s\n' "$2"; printf '%s\n' "$3"; } | jq -nc '
    (input) as $revs | (input) as $cmts | (input) as $ans
    | (reduce $ans[] as $a ({}; .[$a | tostring] = true)) as $done
    | (reduce $cmts[] as $c ({};
        (($c.pull_request_review_id // "") | tostring) as $r
        | if $r == "" then . else .[$r] += [ (($c.id // 0) | tostring) ] end)) as $by
    | [ $revs[] | (.id // 0) as $id | ($by[$id | tostring] // []) as $mine
        | select(($mine | length) > 0 and all($mine[]; $done[.] == true)) | $id ]' 2>/dev/null
}
# <rows-json> less every row whose id is in <ids-json>.
drop_ids() { # <rows-json> <ids-json>
  { printf '%s\n' "$1"; printf '%s\n' "$2"; } | jq -nc '
    (input) as $rows | (input) as $ids
    | (reduce $ids[] as $i ({}; .[$i | tostring] = true)) as $gone
    | [ $rows[] | select($gone[(.id // 0) | tostring] != true) ]' 2>/dev/null
}
# A comment outlives the review that carried it: GitHub keeps the inline rows of
# a dismissed review on /pulls/N/comments, so a dismissal that takes the body
# out of the batch leaves the comments under it routing. A dismissal is the only
# thing that retires them. The review space's filter is narrower than that and
# cannot stand in for this one: it also drops an APPROVED review, whose inline
# comments are live feedback, and a PR green everywhere else would merge over
# them. A comment naming no review, or naming one the review list does not
# carry, is standalone and stays.
# Each kept comment is stamped with its review's submission instant as
# gc_review_submitted_at, the instant gc_city_own dates an inline comment by: a
# comment drafted in a pending review is published when the review is submitted,
# so a review drafted before the provenance cutover and submitted after it reads
# as feedback whole, never its body as feedback and its comments as the city's.
live_comments() { # <reviews-json> <comments-json> — comments no dismissal retired
  { printf '%s\n' "$1"; printf '%s\n' "$2"; } | \
  jq -nc '
    (input) as $revs | (input) as $cmts |
    ([ $revs[]
       | select(((.state // "") | tostring) == "DISMISSED")
       | ((.id // 0) | tostring) ]) as $retired
  | ([ $revs[]
       | select(((.submitted_at // "") | tostring) != "")
       | { key: ((.id // 0) | tostring), value: ((.submitted_at) | tostring) } ]
     | from_entries) as $submitted
  | [ $cmts[]
      | (((.pull_request_review_id // "") | tostring)) as $parent
      | select(($retired | index($parent)) == null)
      | if ($submitted[$parent] // "") != ""
        then . + { gc_review_submitted_at: $submitted[$parent] } else . end ]' 2>/dev/null
}
# A batch names the reviews it answers, the way a signoff-sourced child names
# its review bead. An empty-bodied CHANGES_REQUESTED is named here even though
# the body filter above keeps it out of the watermark: it is the review holding
# the merge, and its inline comments are what the child has to answer.
feedback_reviews() { # <reviews-json> <review-mark> — comma-joined review ids
  printf '%s\n' "$1" | \
  jq -nr --argjson rmark "$2" --arg self "$SELF_LOGIN" --arg since "$PSINCE" "$CITY_OWN_DEF"'
    (input) as $revs |
    [ $revs[] | select(gc_city_own($self; $since) | not)
              | select(((.id // 0) | tonumber) > $rmark)
              | select((((.state // "") | tostring) == "CHANGES_REQUESTED")
                       or ((((.state // "") | tostring) == "COMMENTED")
                           and (((.body // "") | tostring | gsub("[[:space:]]"; "")) != "")))
              | (.id | tostring) ] | sort | join(",")' 2>/dev/null
}
# <<< unanswered-feedback-body

# >>> unengaged-threads-body
# The gap the provenance cutover leaves open. arm 7 reads an unmarked post under
# our own login from before the anchor's cutover as the city's own
# (unanswered-feedback-body), so a review posted that way — an outside review
# agent, an operator-run review, a reviewer using the automation's credential —
# sets no `unanswered` and routes nowhere, and the check stays green across it
# (lane-state reads the finding and review-outcome beads, never a thread), so
# nothing re-reviews it. This reads the review THREADS instead. A thread counts
# as an unengaged finding when it is unresolved, carries a comment with no city
# mark, and holds no marked post of the city's: a thread the city replied into,
# whether through the write-back or a pr-post.sh reply from a fixer or a
# sitting, is arm 7's or the write-back's to finish, a thread of marked city
# posts holds no finding, and a resolved one is done.
# The thread read caps a thread at its first 100 comments, so a thread longer
# than that whose only marked reply sits past the cap reads as unengaged — a
# dismissable visit, never a dropped finding.
unengaged_thread_count() { # count over RT_NODES on stdout; non-zero = could not tell
  printf '%s' "$RT_NODES" | jq "$CITY_OWN_DEF"'
    [ .[]
      | (.comments.nodes // []) as $cs
      | select((.isResolved // false) == false)
      | select([ $cs[] | select(gc_city_marked | not) ] | length > 0)
      | select([ $cs[] | select(gc_city_marked) ] | length == 0)
    ] | length' 2>/dev/null
}
# Does an unengaged thread hold this PR's merge right now? merge.sh
# reads posture off the bead and never reads threads, so this is decided in the
# pre-merge posture pass and folded into `commented`; the visit it warrants is
# the full pass's. Answers in three, because a read that will not run is not
# proof of zero unengaged threads — the caller keeps the posture uncurrent on the
# third so the merge holds for the pass rather than reading a stale one:
#   0  an unengaged thread holds the merge (caller folds into `commented`)
#   1  the reads ran and none holds
#   2  a read would not run — the in-flight ledger or the thread API did not answer
# On the FIRST pass that reads the threads it sets UT_COUNT so the full pass files
# the one visit without a second read; a later pass holds off the standing visit
# and leaves UT_COUNT empty.
# UH_CANDIDATE is 1 once the cheap pre-gate below finds such a post. Past it the
# answer also turns on bead state (the lane markers, the standing visit, the
# children in flight), which the PR's own facts do not show, so the posture arm
# keeps no basis for that anchor and reads it whole every pass.
UT_COUNT=""
UH_CANDIDATE=0
unengaged_holds() { # <id> <num> <head-oid> <row-json> <live-comments-json>
  local id="$1" num="$2" head="$3" row="$4" cmts="$5" sf g m grn=1 stamp inflight utc
  UH_CANDIDATE=0
  [ -n "$head" ] && [ -n "$num" ] && [ -n "$SELF_LOGIN" ] && [ -n "$cmts" ] || return 1
  # Cheap pre-gate off the comments already fetched: the gap is an unmarked
  # comment under OUR OWN login that arm 7 read as the city's own, which only a
  # post from before the cutover can be (or any such post, while no cutover is
  # known). Absent any, no thread here is a finding we own the miss on.
  sf=$(printf '%s' "$cmts" | jq --arg self "$SELF_LOGIN" --arg since "$PSINCE" "$CITY_OWN_DEF"'
    [ .[] | select(gc_city_own($self; $since)) | select(gc_city_marked | not) ] | length' 2>/dev/null)
  case "$sf" in ''|*[!0-9]*) sf=0 ;; esac
  [ "$sf" -gt 0 ] || return 1
  UH_CANDIDATE=1
  # Only a green check hides findings: a red lane is already re-reviewing. The one
  # resolver names the declared lanes and drops the non-lanes; the marker read is
  # the census's own fast green check, kept. The resolver's exit status is
  # load-bearing: a crash prints nothing, and an empty check list would leave grn=1
  # (vacuously "all green") and flag a hold with no basis. If it cannot name the
  # checks, this probe cannot establish its own precondition — return no hold here;
  # merge.sh's lane gate holds on an unreadable resolver independently.
  local utgates
  if ! utgates=$("$REVIEW_CHECKS" --resolve --check-set "$checkset" --through merge 2>/dev/null); then
    return 1
  fi
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    m=$(printf '%s' "$row" | jq -r --arg k "check.$g" '(.metadata[$k] // "") | tostring')
    [ "$m" = "green" ] || grn=0
  done <<UTGATES
$utgates
UTGATES
  [ "$grn" = 1 ] || return 1
  stamp=$(printf '%s' "$row" | jq -r '(.metadata.pr_unengaged_threads // "") | tostring')
  if [ "$stamp" = "$head" ]; then
    # This head was flagged already. The hold stands while its visit is open, and
    # the operator's close of it releases the merge; a new commit re-runs the
    # detection below. Cheap and self-clearing — no thread read.
    [ -n "$(visit_for "$id" "pr-unengaged-threads.$num.$head")" ] && return 0
    return 1
  fi
  # First detection. A review or rework child already open on this anchor owns the
  # follow-up and holds the merge by its own blocks edge; do not stack a second
  # one. A ledger that will not read is not proof nothing is in flight, so it holds
  # the merge for the pass (return 2) rather than waving the anchor through; only a
  # clean, empty read spends the thread count.
  inflight=$(bd_list --status="$LIVE_STATUSES" --metadata-field anchor_bead="$id") || return 2
  [ "$(printf '%s' "$inflight" | jq 'length' 2>/dev/null)" = 0 ] || return 1
  # A thread read that did not answer, or answered with no usable count, is the
  # gap this function exists to close: return 2 so the caller holds, never 1.
  review_threads_load "$num" || return 2
  utc=$(unengaged_thread_count) || return 2
  case "$utc" in ''|*[!0-9]*) return 2 ;; esac
  [ "$utc" -gt 0 ] || return 1
  UT_COUNT="$utc"
  return 0
}
# <<< unengaged-threads-body

# >>> answered-threads-body
# The comment path reads "unanswered" off max_c exceeding the comment watermark,
# and that watermark advances only when arm 7 routes (the lifecycle transition
# below). A comment answered by any other path, such as a sitting that replies
# in-thread and resolves the thread, never moves the watermark, so it reads
# unanswered on every pass and files a visit carrying pr_number that holds the
# merge. A resolved review thread holding a reply of ours is the answered signal,
# whichever path posted the reply and whoever resolved the thread. A reply of
# ours is a post that is the city's own (gc_city_own): marked by pr-post.sh, or
# under our login from before the provenance cutover. An unmarked post under our
# login after it is feedback, an operator's or a model's, and answers nothing.
# A thread is answered through the last reply of ours in it, and only once it is
# resolved. A bare reply is not enough: unengaged_holds counts exactly the
# unresolved threads a reply of ours left open, so reading a reply here would only
# move the hold from one arm to the other. A comment after our last reply stays
# outstanding. A reply does not reopen a resolved thread, and GitHub records no
# resolution time to place that comment before or after the resolve; the
# write-back likewise reads a post after its own as a live conversation.
# A thread resolved with no reply of ours answers nothing here, so a hand
# resolution alone still routes. The write-back's awaiting answer (its mark line
# names awaiting:<visit>) says only that the comments before it wait on a
# person, so it is not a reply here either. Only inline comments sit on a
# thread; a review body and a Conversation comment carry none and stay on the
# mark.
# The ids of the inline comments RT_NODES shows answered, as a JSON array of
# numbers on stdout, comparable with the REST rows' `id`: in each resolved thread,
# every comment up to and including the last reply of ours. The thread read's
# 100-comment cut can hide only a later reply of ours, so it answers less, never
# more. Non-zero without output on a projection that does not yield one, and the
# caller then counts the batch unfiltered rather than dropping an objection — the
# direction live_comments fails in too.
answered_comment_ids() {
  printf '%s' "$RT_NODES" | jq -c --arg self "$SELF_LOGIN" --arg since "$PSINCE" "$CITY_OWN_DEF"'
    [ .[] | select((.isResolved // false) == true)
      | (.comments.nodes // []) as $cs
      | ([ $cs | to_entries[] | select(.value | gc_city_own($self; $since))
           | select((.value.body // "") | contains("<!-- gc-writeback-mark:awaiting:") | not)
           | .key ] | max) as $last
      | select($last != null)
      | $cs[0:($last + 1)][] | (.fullDatabaseId // empty) | tonumber ]
    | unique' 2>/dev/null
}
# <<< answered-threads-body

ANCHORS=$(bd_list --status=open --metadata-field merge_result=pull_request) || {
  echo "$PROG: could not enumerate gating anchors; failing loudly rather than reporting a false all-clear" >&2
  exit 1
}

# --- retire the merge-blocked-approval visit category (a required review is state) --
# An open PR awaiting its required approving review is a notification in itself.
# It sits in the operator's review queue, the state the board's review section
# surfaces, so the city does no proactive work to flag it: this cadence files no
# merge-blocked-approval visit, and the category holds no actionable escalation.
# Retire any that are open, closing each moot through the same close the
# pre-recorded-disposition arm uses. The board keeps the PR as state regardless.
# This runs before the no-anchors early-exit so a rig whose PRs have all merged
# still clears its visits, and in every rig's cadence so each store cleans its own.
# Fail closed on an unreadable subject: a visit whose anchor cannot be read this
# pass is left for the next, never retired on a read that did not land.
# The early arms (--posture-only, --route-comments-only) write nothing here.
if [ "$POSTURE_ONLY" != 1 ] && [ "$ROUTE_ONLY" != 1 ]; then
  if av_visits=$(bd_list --status=open --metadata-field "escalation_key=merge-blocked-approval"); then
    while IFS="$(printf '\t')" read -r avid avsubj; do
      [ -n "${avid:-}" ] || continue
      avstate=""
      if [ -n "$avsubj" ]; then
        avstate=$(gc bd show "$avsubj" --json 2>/dev/null | scrub | jq -r '.[0].status // empty' 2>/dev/null)
        if [ -z "$avstate" ]; then
          echo "$PROG: visit $avid — subject $avsubj unreadable this pass; left for the next" >&2
          continue
        fi
      fi
      if "$VISIT_CLOSE" --visit "$avid" --outcome moot --force \
           --reason "Retired by pr-facts: a required approving review is state (the board's review section), not an escalation; this cadence files no merge-blocked-approval visits. Subject ${avsubj:-<none>} is ${avstate:-none-recorded}." >/dev/null; then
        echo "$PROG: retired stale merge-blocked-approval visit $avid (subject ${avsubj:-<none>} ${avstate:-none-recorded})"
      else
        echo "$PROG: could not retire stale merge-blocked-approval visit $avid; leaving it for the operator" >&2
      fi
    done <<AV_EOF
$(printf '%s' "$av_visits" | jq -r '.[]? | [.id, ((.metadata["gc.continuation_group"]) // "")] | @tsv' 2>/dev/null)
AV_EOF
  else
    echo "$PROG: merge-blocked-approval visit sweep skipped — could not list visits (retry next pass)" >&2
  fi
fi

# --- retract the disposition arm's refused-close reports whose close landed ------
# The disposition arm files a pr-dispose-failed.<num> visit when bead-rehome
# refuses an anchor's close, and retracts it once a later pass's close lands. A
# retract that does not land then is not retried by the arm, because the closed
# anchor leaves the enumeration. So every full pass also reads the open visits
# filed under that key family and retracts each whose subject now reads closed
# with its disposition pointer (gc.superseded_by) recorded: the close the visit
# asked for has landed. A subject closed without the pointer is left alone, since
# its disposition is not on record. A visit someone is engaged in is theirs to
# conclude, and a subject that does not read this pass leaves its visit for the
# next. Like the sweep above, this runs before the no-anchors early-exit.
if [ "$POSTURE_ONLY" != 1 ] && [ "$ROUTE_ONLY" != 1 ]; then
  if df_visits=$(bd_list --status=open --has-metadata-key=escalation_key); then
    while IFS="$(printf '\t')" read -r dfsubj dfnum; do
      [ -n "${dfsubj:-}" ] || continue
      dfrow=$(gc bd show "$dfsubj" --json 2>/dev/null | scrub)
      dfst=$(printf '%s' "$dfrow" | jq -r '.[0].status // empty' 2>/dev/null)
      if [ -z "$dfst" ]; then
        echo "$PROG: pr-dispose-failed.$dfnum — subject $dfsubj unreadable this pass; its visit is left for the next" >&2
        continue
      fi
      dfsucc=$(printf '%s' "$dfrow" | jq -r '.[0].metadata["gc.superseded_by"] // empty' 2>/dev/null)
      [ "$dfst" = "closed" ] && [ -n "$dfsucc" ] || continue
      retract_dispose_visits "$dfsubj" "$dfnum" \
        "PR#$dfnum's pre-recorded disposition is consummated: $dfsubj closed (-> $dfsucc) once the obstruction this visit reported cleared."
    done <<DF_EOF
$(printf '%s' "$df_visits" | jq -r '[ .[]? | select((.metadata.task_kind // "") == "visit")
    | ((.metadata.escalation_key // "") | tostring) as $k
    | select($k | test("^pr-dispose-failed\\.[0-9]+$"))
    | ((.metadata["gc.continuation_group"] // "") | tostring) as $g
    | select($g | test("^[A-Za-z0-9._-]+$"))
    | select(((.assignee // "") | tostring) == "" and ((.metadata["gc.session_name"] // "") | tostring) == "")
    | [$g, ($k | ltrimstr("pr-dispose-failed."))] ] | unique | .[] | @tsv' 2>/dev/null)
DF_EOF
  else
    echo "$PROG: pr-dispose-failed visit sweep skipped — could not list visits (retry next pass)" >&2
  fi
fi

[ "$ANCHORS" != "[]" ] || { echo "$PROG: no gating anchors"; exit 0; }

# --- the open PRs, in one read -----------------------------------------------------
# One paginated GraphQL read lists every open PR with the facts that move when a
# person or a push acts on it: the head, the base, the draft flag, the review
# decision, and the count and newest id of its reviews and of its Conversation
# comments. An inline comment arrives inside a review of its own, so it moves the
# review count too. updatedAt alone would not do: GitHub can leave it at the
# first of several reviews submitted seconds apart, so a later one does not move
# it. OPEN_ACT holds each PR's activity mark, the facts joined in one line, and a
# PR missing from a read that answered has left the open list.
# The posture arm asks for the merge state as well. GitHub computes that per PR
# on request and times out on about a hundred at once, so that read pages 25 PRs
# at a time.
OPEN_PR_FIELDS='number isDraft headRefOid baseRefName reviewDecision updatedAt
  reviews(last:1){totalCount nodes{databaseId}} comments(last:1){totalCount nodes{databaseId}}'
POSTURE_PR_FIELDS='state url headRefName isCrossRepository headRepository{name}
  headRepositoryOwner{login} mergeStateStatus'
declare -A OPEN_PR=() OPEN_ACT=() OPEN_UPD=()
OPEN_READ=0
open_prs_read() { # <extra node fields> <page size>; fills OPEN_PR, OPEN_ACT, OPEN_UPD; non-zero = could not tell
  local q raw lines n act upd node
  q='query($owner:String!,$repo:String!,$endCursor:String){
  repository(owner:$owner,name:$repo){
    pullRequests(states:OPEN,first:'"$2"',after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{'"$OPEN_PR_FIELDS $1"'}}}}'
  raw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate -f query="$q" \
    -f owner="${ORIGIN_REPO%%/*}" -f repo="${ORIGIN_REPO#*/}" 2>/dev/null) || return 1
  lines=$(printf '%s' "$raw" | scrub | jq -rs '
    def v: ((. // "") | tostring | gsub("[[:space:]]"; "_")) as $s | if $s == "" then "-" else $s end;
    [ .[] | .data.repository.pullRequests ] as $pages
    | if ($pages | length) == 0 or ([ $pages[] | select(. == null) ] | length) > 0
      then error("no pullRequests in response") else $pages[].nodes[]? end
    | select((.number // null) != null)
    | ([ (.headRefOid | v), (.baseRefName | v), ((.isDraft // false) | tostring), (.reviewDecision | v),
         "\(.reviews.totalCount // 0):\(.reviews.nodes[0].databaseId // 0)",
         "\(.comments.totalCount // 0):\(.comments.nodes[0].databaseId // 0)" ] | join("|")) as $act
    | "\(.number) \($act) \(.updatedAt | v) \(tojson)"' 2>/dev/null) || return 1
  while IFS=' ' read -r n act upd node; do
    [ -n "$n" ] && [ -n "$node" ] || continue
    OPEN_PR["$n"]="$node"; OPEN_ACT["$n"]="$act"; OPEN_UPD["$n"]="$upd"
  done <<< "$lines"
  OPEN_READ=1
}

recorded=0; flagged=0; reworked=0; dismissed_n=0; skipped=0; disposed_n=0
postured=0; answered=0; unpostured=0; reaped=0; pkept=0; pread=0
# The anchor's provenance cutover, set per anchor below and read by every
# gc_city_own call the anchor's arms make.
PSINCE=""
pace_start "$CURSOR" "$DEADLINE"

# --- the posture basis: what each anchor's posture was last derived from -------
# The posture is derived from the PR's head, review decision, reviews and
# comments, the anchor's watermarks and provenance cutover, the acting login,
# and this script, and from nothing else while no unengaged-thread candidate is
# in play. The basis joins those facts as the batched read gives them, and
# --seen keeps it beside the posture it produced. An anchor whose basis reads the
# same this pass, and whose bead still carries that posture at the read's head,
# keeps the posture without the per-PR reads. A posture of `commented` keeps no
# basis, because a routing or a visit can release it with nothing on the PR
# moving. A visit that keeps or earns no basis records "-", which matches
# nothing, so the next pass reads that anchor whole.
# The batched read and the per-PR reads are separate requests, and GitHub can
# answer one of them from a moment ahead of the other, so one derivation can
# read lists older than the basis it would be kept under. A derivation therefore
# records its basis as a candidate, "?<posture>#<basis>", which keeps no
# posture. The next pass derives the posture again, and only a derivation that
# reads the same basis and derives the same posture as the candidate confirms it.
PF_CODE_FP="$(cksum < "$0" 2>/dev/null | cut -d' ' -f1)-$(printf '%s' "$CITY_OWN_DEF" | cksum | cut -d' ' -f1)"
if [ "$POSTURE_ONLY" = 1 ] && [ -n "$SEEN" ]; then
  open_prs_read "$POSTURE_PR_FIELDS" 25 \
    || echo "$PROG: WARN the batched open-PR read did not answer; every posture is read per PR this pass" >&2
  pace_seen_start "$SEEN"
else
  pace_seen_start "${CURSOR:+$CURSOR.seen}"
fi

# --- visit order: the anchors that need action first, the rest in rotation -------
# A paced walk visits first what its arm can act on, then rotates through the
# rest after its cursor (pace-lib.sh), so an idle anchor is still reached. The
# feedback arm puts first an anchor whose recorded posture is `commented`
# (feedback no routing has answered yet) or a `changes_requested` whose PR
# changed since this arm last visited it, since that posture alone cannot say
# whether its feedback is routed. The full walk puts first an anchor whose PR
# left the open list (a merge or a close to record), an approved PR the posture
# arm recorded as DIRTY at its head with no rework child in flight (it owes a
# merge-in), and any PR that changed since this walk last visited it (a review,
# a comment, a push, a new base, a draft flip). An approved conflicting PR under
# a merge_hold, a rebase_hold or an armed re-dispatch owes no merge-in, because
# the conflict arm stands down on each, so it rotates with the rest until the
# hold lifts. First anchors rotate on
# <cursor>.first, the rest on <cursor>, and <cursor>.seen holds each anchor's
# activity mark as the walk last saw it. A walk with no marks yet records them
# all and puts nothing first for a change, so its first pass is the plain
# rotation plus the anchors that owe something now. Unpaced, the walk keeps the
# enumerated order.
first_rows=""; rest_rows=""; first_n=0
declare -A KIDS_REWORK=()
if [ -n "$CURSOR" ]; then
  open_prs_read "" 100 \
    || echo "$PROG: WARN the open-PR list did not answer; this walk orders by what the anchors record" >&2
  if [ "$ROUTE_ONLY" != 1 ]; then
    if kid_lines=$(bd_live_children); then
      while IFS=$'\t' read -r ka _kids krw; do
        [ -n "$ka" ] && KIDS_REWORK["$ka"]="$krw"
      done <<< "$kid_lines"
    else
      echo "$PROG: WARN the anchors' live children did not read; an approved conflicting PR is not put first this pass" >&2
      KIDS_REWORK["*"]=unreadable
    fi
  fi
  while IFS=$'\x1f' read -r cid cnum cpost cms chold crhold carmed arow; do
    [ -n "${arow:-}" ] || continue
    grp=rest
    cact="${OPEN_ACT[$cnum]-}"
    if [ "$ROUTE_ONLY" = 1 ]; then
      case "${cpost%%@*}" in
        commented) grp=first ;;
        changes_requested) [ -n "$cact" ] && pace_seen_changed "$cid" "$cact" && grp=first ;;
      esac
    else
      cphead="${cpost#*@}"; cphead="${cphead%%@*}"
      if [ "$OPEN_READ" = 1 ] && [ -z "$cact" ]; then
        grp=first
      elif [ "${cpost%%@*}" = approved ] && [ "${cms%%@*}" = DIRTY ] && [ "${cms#*@}" = "$cphead" ] \
           && { [ -z "$cact" ] || [ "${cact%%|*}" = "$cphead" ]; } \
           && ! is_held "$chold" && ! is_held "$crhold" && [ -z "$carmed" ] \
           && [ -z "${KIDS_REWORK["*"]-}" ] && [ "${KIDS_REWORK[$cid]-0}" != 1 ]; then
        grp=first
      elif [ -n "$cact" ] && pace_seen_changed "$cid" "$cact"; then
        grp=first
      fi
    fi
    if [ "$PACE_SEEN_FRESH" = 1 ] && [ -n "$cact" ]; then pace_seen_put "$cid" "$cact"; fi
    if [ "$grp" = first ]; then
      first_rows="$first_rows$arow"$'\n'; first_n=$((first_n + 1))
    else
      rest_rows="$rest_rows$arow"$'\n'
    fi
  done <<SPLIT_EOF
$(printf '%s' "$ANCHORS" | jq -r '
    .[] | . as $row | (.metadata // {}) as $m
    | [ (.id // ""), ($m.pr_number // ""), ($m.pr_posture // ""), ($m.pr_merge_state // ""),
        ($m.merge_hold // ""), ($m.rebase_hold // ""), ($m["gc.dispatch_when_ready"] // "") ]
    | map(tostring | gsub("[\u001f\n]"; " ")) + [ $row | tojson ] | join("\u001f")' 2>/dev/null)
SPLIT_EOF
  first_rows=$(printf '%s' "$first_rows" | pace_order "$PACE_FIRST_CURSOR")
  rest_rows=$(printf '%s' "$rest_rows" | pace_order "$CURSOR")
else
  rest_rows=$(printf '%s' "$ANCHORS" | jq -c '.[]' 2>/dev/null)
fi

while IFS= read -r tagged; do
  [ -n "${tagged:-}" ] || continue
  group="${tagged%%$'\t'*}"
  row="${tagged#*$'\t'}"
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '(.metadata.pr_number // "") | tostring')
  [ -n "$id" ] || continue
  case "$num" in ''|*[!0-9]*) skipped=$((skipped + 1)); continue ;; esac
  # The mark this visit records: the posture arm's starts as "-" and earns its
  # basis only at the end; a paced walk records the PR's activity mark.
  vmark="${OPEN_ACT[$num]-}"
  [ "$POSTURE_ONLY" != 1 ] || vmark="-"
  pace_visit "$group" "$id" "$vmark"; case $? in 1) continue ;; 2) break ;; esac
  RT_NUM=""; RT_NODES=""
  branch=$(printf '%s' "$row" | jq -r '.metadata.branch // ""')
  target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // ""')
  prurl=$(printf '%s' "$row" | jq -r '.metadata.pr_url // ""')
  checkset=$(printf '%s' "$row" | jq -r '.metadata.check_set // ""')
  hold=$(printf '%s' "$row" | jq -r '.metadata.merge_hold // ""')
  rhold=$(printf '%s' "$row" | jq -r '.metadata.rebase_hold // ""')
  # deferred-dispatch's arm marker (deferred-dispatch.sh): the pool this work
  # re-offers to once it reads bd-ready, set while the anchor waits and cleared
  # when the reconcile pass slings it. While set, the anchor is deliberately
  # parked and this PR's branch is superseded by the pending re-dispatch, so the
  # dispatch arms below stand down on it as they do for a merge_hold or a live
  # demand: a rework minted against a branch about to re-pour is non-hand-offable,
  # so a polecat can only refuse it and the pool re-offers the refusal until a
  # human clears it.
  armed=$(printf '%s' "$row" | jq -r '.metadata["gc.dispatch_when_ready"] // ""')

  # --- the posture basis, as this pass's batched read shows it -----------------
  # SHORT=1 when the confirmed basis --seen kept for this anchor reads the same
  # now and the bead still carries the posture it produced at the read's head:
  # the batched read then stands in for the pinned read, and the posture below is
  # kept rather than derived again. A candidate's "?<posture>" names no posture
  # the case below accepts, so a candidate keeps nothing.
  SHORT=0; SHORT_P=""; PFP=""; UH_CANDIDATE=0; MARKS_UNRECORDED=0; b_seen=""
  if [ "$POSTURE_ONLY" = 1 ] && [ -n "${OPEN_PR[$num]-}" ]; then
    IFS=$'\x1f' read -r b_since b_rwm b_cwm b_iwm b_have <<< "$(printf '%s' "$row" | jq -r '
      (.metadata // {}) as $m
      | [ $m.pr_provenance_since, $m.pr_review_watermark, $m.pr_comment_watermark,
          $m.pr_issue_comment_watermark, $m.pr_posture ]
      | map((. // "") | tostring | gsub("[\u001f\n]"; " ")) | join("\u001f")' 2>/dev/null)"
    PFP="$PF_CODE_FP|$SELF_LOGIN|$b_since|$b_rwm|$b_cwm|$b_iwm|${OPEN_UPD[$num]-}|${OPEN_ACT[$num]-}"
    b_seen=$(pace_seen_get "$id")
    SHORT_P="${b_seen%%#*}"
    if [ -n "$b_since" ] && [ -n "$SELF_LOGIN" ] && [ "${b_seen#*#}" = "$PFP" ]; then
      case "$SHORT_P" in
        approved|review_required|none|changes_requested)
          case "$b_have" in "$SHORT_P@${OPEN_ACT[$num]%%|*}@"?*) SHORT=1 ;; esac ;;
      esac
    fi
  fi

  # --- pinned identity read (merge.sh's field set, plus labels) -----------------
  if [ "$SHORT" = 1 ]; then
    PR_JSON="${OPEN_PR[$num]}"
  else
    PR_JSON=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json "$PR_FIELDS,labels" 2>/dev/null)
  fi
  if [ -z "$PR_JSON" ]; then
    echo "$PROG: PR#$num view failed; NOTHING recorded for $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
  is_draft=$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')
  base=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // ""')
  head_ref=$(printf '%s' "$PR_JSON" | jq -r '.headRefName // ""')
  head_oid=$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // ""')
  merge_state=$(printf '%s' "$PR_JSON" | jq -r '.mergeStateStatus // ""')
  mergeable=$(printf '%s' "$PR_JSON" | jq -r '.mergeable // ""')
  rd=$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // ""')
  live_url=$(canon_pr_url "$(printf '%s' "$PR_JSON" | jq -r '.url // ""')")
  head_repo=$(printf '%s' "$PR_JSON" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  head_cross=$(printf '%s' "$PR_JSON" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)
  if [ "$(url_repo_q "$live_url")" != "$ORIGIN_REPO_Q" ] \
     || { [ -n "$prurl" ] && [ "$(canon_pr_url "$prurl")" != "$live_url" ]; } \
     || [ -z "$head_repo" ] || [ "$head_repo" != "$ORIGIN_REPO" ] || [ "$head_cross" != "false" ] \
     || { [ -n "$branch" ] && [ "$head_ref" != "$branch" ]; }; then
    echo "$PROG: PR#$num identity did not certify for $id (url/head/fork mismatch); NOTHING recorded" >&2
    skipped=$((skipped + 1)); continue
  fi
  [ -n "$target" ] || target="$base"

  # --- PR merged (out-of-band, or a died record): record it ----------------------
  # Reconciliation is the full pass's; the early arms (--posture-only,
  # --route-comments-only) reconcile no terminal state, so a MERGED or CLOSED
  # anchor falls through to the OPEN filter.
  if [ "$state" = "MERGED" ] && [ "$POSTURE_ONLY" != 1 ] && [ "$ROUTE_ONLY" != 1 ]; then
    merge_oid=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json mergeCommit 2>/dev/null \
      | scrub | jq -r '.mergeCommit.oid // ""')
    if [ -z "$merge_oid" ]; then
      # Never record an empty merged_sha (I5: closed anchor => merged+merged_sha).
      echo "$PROG: WARN PR#$num is MERGED but the mergeCommit read came back empty; recording merged_sha=unverified:PR#$num" >&2
      merge_oid="unverified:PR#$num"
    fi
    case "$merge_oid" in
      unverified:*) short_oid="$merge_oid" ;;
      *) short_oid=$(printf '%.8s' "$merge_oid") ;;
    esac
    if "$LIFECYCLE" transition "$id" --to merged --expect pull_request --close \
         --set "merged_sha=$merge_oid" \
         --unset merge_record_failures \
         --append-notes "Merged to $target at $short_oid (recorded by pr-facts)"; then
      recorded=$((recorded + 1))
      echo "$PROG: recorded $id — PR#$num is MERGED ($short_oid)"
    else
      echo "$PROG: PR#$num is MERGED but the record failed for $id; retry next pass" >&2
      skipped=$((skipped + 1))
      [ -x "$RECORD_CAP" ] && "$RECORD_CAP" "$id" "$num" "$merge_oid" "$target" || true
    fi
    continue
  fi

  # --- PR closed unmerged: out-of-band close ------------------------------------
  if [ "$state" = "CLOSED" ] && [ "$POSTURE_ONLY" != 1 ] && [ "$ROUTE_ONLY" != 1 ]; then
    # A deliberate supersede/not-planned close records its disposition on the
    # still-open anchor before the PR closes (assets/scripts/pr-dispose.sh):
    # the bead-rehome kind, the successor, and an optional store. When it is
    # present and well-formed, consummate it through bead-rehome.sh — the
    # sanctioned terminal close that stamps gc.superseded_by, the explicit
    # terminal state doctor/check-closed-implies-landed accepts — rather than
    # re-asking the decision the closer already made as a rework-or-close
    # visit. A missing or malformed marker falls through to the default.
    #
    # Read the marker from a FRESH anchor read, not from $row: pr-dispose.sh
    # stamps it immediately before it closes the PR, which can fall AFTER this
    # pass captured $row at enumeration. The stale $row would miss a marker set
    # in that window and abandon a deliberately-disposed anchor. If the re-read
    # fails, skip and retry — never abandon from a marker's absence in a read
    # that did not land.
    fresh=$(gc bd show "$id" --json 2>/dev/null | scrub)
    if ! printf '%s' "$fresh" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
      echo "$PROG: $id — PR#$num is CLOSED but re-reading the anchor failed; skipping rather than abandoning a possibly-disposed anchor (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    disp_kind=$(printf '%s' "$fresh" | jq -r '.[0].metadata["gc.pr_close_disposition_kind"] // ""')
    disp_succ=$(printf '%s' "$fresh" | jq -r '.[0].metadata["gc.pr_close_disposition_successor"] // ""')
    disp_store=$(printf '%s' "$fresh" | jq -r '.[0].metadata["gc.pr_close_disposition_successor_store"] // ""')
    case "$disp_kind" in re-homed|folded|fixed-upstream|duplicate|not-needed)
      if [ -n "$disp_succ" ]; then
        STORE_ARG=(); [ -n "$disp_store" ] && STORE_ARG=(--successor-store "$disp_store")
        # Dispose the branch's parked rework/rebase children BEFORE the anchor's
        # own close below, not after it. A rework child holds a `blocks` edge on
        # the anchor, so while one is open bead-rehome's non-force close of the
        # anchor is refused and the anchor strands OPEN with its pointer already
        # stamped — the whole failure this arm exists to prevent. Closing the
        # children first clears that hold, so the anchor's close below succeeds in
        # the same pass. These children exist only to carry this branch to a merge
        # the now-closed PR will never reach; left open they re-offer to the fix
        # pool, which re-derives the close one claim at a time. Dispose each
        # through the same sanctioned terminal close the anchor takes —
        # bead-rehome.sh, pointed at the anchor's successor — so the branch leaves
        # no husk. A child here is a PARKED (open, so unclaimed) bead on this
        # branch that carries a rework resume (prepare_mode) and is not itself an
        # anchor (no merge_result): a child a worker holds is in_progress and left
        # alone, and a review bead on the branch carries no prepare_mode and is
        # left to signoff. A rebase_hold is an operator's freeze on the branch, so
        # a held child is reported, never closed out from under them.
        # Track the children disposed below. They are closed BEFORE the anchor's
        # own close (to clear their blocks-hold), so a refused anchor close past
        # this point leaves them already gone — the pr-dispose-failed escalation
        # names them, or an operator who reverses the disposition finds them
        # disposed with nothing saying so.
        disposed_kids=""
        anchor_branch=$(printf '%s' "$fresh" | jq -r '.[0].metadata.branch // ""')
        if [ -n "$anchor_branch" ]; then
          if kids=$(bd_list --status=open --metadata-field branch="$anchor_branch"); then
            while IFS=$'\t' read -r kid khold; do
              [ -n "$kid" ] || continue
              if is_held "$khold"; then
                echo "$PROG: $id — parked child $kid on '$anchor_branch' is frozen (rebase_hold); left for the operator" >&2
                continue
              fi
              if [ -x "$REHOME" ] && "$REHOME" --origin "$kid" --successor "$disp_succ" --kind not-needed \
                   ${STORE_ARG[@]+"${STORE_ARG[@]}"} \
                   --note "Parked rework child of $id on '$anchor_branch'; moot once PR#$num closed $disp_kind" >/dev/null 2>&1; then
                echo "$PROG: $id — dropped parked child $kid ('$anchor_branch' is moot once the PR is disposed)"
                disposed_kids="${disposed_kids:+$disposed_kids }$kid"
              else
                echo "$PROG: $id — could not drop parked child $kid; dispose it by hand: bead-rehome.sh --origin $kid --successor $disp_succ --kind not-needed" >&2
              fi
            done <<CHILDREN_EOF
$(printf '%s' "$kids" | jq -r --arg a "$id" --arg succ "$disp_succ" '
  .[] | select(.id != $a) | select(.id != $succ)
      | select(((.metadata.merge_result // "") | tostring) == "")
      | select(((.metadata.prepare_mode // "") | tostring) != "")
      | [ .id, ((.metadata.rebase_hold // "") | tostring) ] | @tsv')
CHILDREN_EOF
          else
            echo "$PROG: $id — could not enumerate parked children on '$anchor_branch'; any are left for the operator" >&2
          fi
        fi
        # Retire this script's merge-path visits on the anchor BEFORE its close,
        # not after. Each was filed to hold PR#$num's merge until a person
        # answered it (MERGE_PATH_KEYS_JQ), possibly before the disposition marker
        # was set, and each tracks the anchor, so bead-rehome's finalize gate would
        # otherwise hold the close on a merge that no longer exists. The marker on
        # the anchor, not the visit, is what drives a retry, so retiring them here
        # is safe even if the close below does not land this pass. What a visit
        # raised stays on the PR. A visit someone is engaged in is theirs to
        # conclude and keeps holding the close, with one exception: the
        # rework-or-close visit, whose question the pre-recorded disposition
        # itself answers. The sitting that recorded the disposition can still
        # hold it, so that one is retired over the claim. This arm's own
        # pr-dispose-failed visit asks whether this close lands, so it is not
        # retired here: the retry below excepts it at the gate.
        mp_rows=$(gc bd list --status="$LIVE_STATUSES" --metadata-field "gc.continuation_group=$id" \
                    --limit=0 --json 2>/dev/null | scrub)
        if printf '%s' "$mp_rows" | jq -e 'type == "array"' >/dev/null 2>&1; then
          while IFS=$'\t' read -r mpvid mpkey mpheld; do
            [ -n "$mpvid" ] || continue
            mpforce=()
            if [ "$mpkey" = "pr-abandoned.$num" ]; then
              mpforce=(--force)
              mpwhy="the rework-or-close decision is made."
            elif [ -n "$mpheld" ]; then
              echo "$PROG: $id — visit $mpvid ($mpkey) is engaged ($mpheld); it holds the close until its holder concludes it" >&2
              continue
            else
              mpwhy="PR#$num is closed, so the merge this visit held is gone; what it raised stays on the PR."
            fi
            if "$VISIT_CLOSE" --visit "$mpvid" --outcome moot ${mpforce[@]+"${mpforce[@]}"} \
                 --reason "Auto-resolved: $id disposed ($disp_kind -> $disp_succ) via its pre-recorded PR-close disposition; $mpwhy" >/dev/null; then
              echo "$PROG: $id — retired stale visit $mpvid ($mpkey; disposition was pre-recorded)"
            else
              echo "$PROG: $id — could not retire stale visit $mpvid; leaving it for the operator" >&2
            fi
          done <<MP_EOF
$(printf '%s' "$mp_rows" | jq -r --arg s "$id" --arg n "$num" "$MERGE_PATH_KEYS_JQ"'
    .[] | select((.metadata.task_kind // "") == "visit")
        | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
        | ((.metadata.escalation_key // "") | tostring) as $k
        | select($k | merge_path_key($n))
        | ((.assignee // "") | tostring) as $who
        | ((.metadata["gc.session_name"] // "") | tostring) as $sess
        | [.id, $k, (if $who != "" then $who elif $sess != "" then "session " + $sess
                     elif (.status // "") == "in_progress" then "claimed" else "" end)] | @tsv' 2>/dev/null)
MP_EOF
        else
          echo "$PROG: $id — could not list the visits on the anchor; any merge-path visit is left for the operator" >&2
        fi
        # This arm's own escalation from an earlier refused close tracks the
        # anchor too, and it asks for exactly this retry: "clear the obstruction
        # and the next refinery pass retries". If the finalize gate held the
        # retry on it, the anchor could not close even after that obstruction
        # cleared. So the retry names the arm's key to the gate, which excepts
        # every visit filed under it for this anchor that nobody is engaged in,
        # and those visits are retracted moot once the close lands. A visit a
        # person has engaged still holds the close and is theirs to conclude. A
        # refused close leaves the visit open, so a standing obstruction keeps
        # its one visit and nothing is re-filed.
        EXCEPT_ARG=(--except-key "pr-dispose-failed.$num")
        if [ -x "$REHOME" ]; then
          rout=$("$REHOME" --origin "$id" --successor "$disp_succ" --kind "$disp_kind" \
                   ${STORE_ARG[@]+"${STORE_ARG[@]}"} ${EXCEPT_ARG[@]+"${EXCEPT_ARG[@]}"} \
                   --note "PR#$num closed $disp_kind (disposition pre-recorded before the close)" 2>&1); rrc=$?
        else
          rout="bead-rehome.sh is not executable at $REHOME"; rrc=127
        fi
        if [ "$rrc" -eq 0 ]; then
          disposed_n=$((disposed_n + 1))
          echo "$PROG: $id — PR#$num closed out-of-band; auto-disposed ($disp_kind -> $disp_succ), no visit filed"
          retract_dispose_visits "$id" "$num" \
            "PR#$num's pre-recorded disposition is consummated: $id closed ($disp_kind -> $disp_succ) once the obstruction this visit reported cleared."
          continue
        elif [ "$rrc" -eq 4 ]; then
          # Pointer would not stick — transient. Keep merge_result=pull_request
          # so the anchor is re-enumerated and the next pass retries.
          echo "$PROG: $id — PR#$num disposition recorded but bead-rehome could not stamp the pointer (transient); retry next pass" >&2
          skipped=$((skipped + 1)); continue
        else
          # Close refused, a conflicting successor, or a bad invocation — a human
          # is needed. Surface THAT, under its own key, and leave the anchor open
          # carrying the marker; still never the generic rework-or-close visit.
          # The parked children were disposed above, before this close — so a
          # refusal here has already closed them. Say which, so an operator who
          # reverses the disposition knows what to restore rather than finding
          # them gone.
          echo "$PROG: $id — PR#$num disposition recorded but bead-rehome refused (rc=$rrc); escalating, anchor left open" >&2
          printf '%s\n' "$rout" >&2
          kids_disposed_note=""
          [ -n "$disposed_kids" ] && kids_disposed_note=" The branch's parked rework/rebase children ($disposed_kids) were ALREADY disposed (closed not-needed -> $disp_succ) before this close, to clear their blocks-hold on the anchor; if the disposition is wrong, restore them by hand."
          dmsg="PR#$num ($live_url) was closed with a pre-recorded disposition ($disp_kind -> $disp_succ), but bead-rehome.sh could not consummate it (rc=$rrc): $(printf '%s' "$rout" | tr '\n' ' ' | cut -c1-300). The anchor is left OPEN carrying the marker; clear the obstruction and the next refinery pass retries, or dispose it by hand."
          escalate "$id" "pr-dispose-failed.$num" "$dmsg$kids_disposed_note"
          refresh_dispose_visits "$id" "$num" "$dmsg" "$kids_disposed_note"
          skipped=$((skipped + 1)); continue
        fi
      fi ;;
    esac
    # Default: an out-of-band close with no recorded disposition -> abandoned,
    # routed to human, and a rework-or-close visit.
    if "$LIFECYCLE" transition "$id" --to abandoned --expect pull_request \
         --assignee "" \
         --set "blocked_reason=PR#$num closed out-of-band without merging" \
         --takeaway "PR#$num was closed without merging — rework the branch, or close this bead as not-planned"; then
      flagged=$((flagged + 1))
      escalate "$id" "pr-abandoned.$num" \
        "PR#$num ($live_url) was closed out-of-band without merging. The anchor is left OPEN, routed to human (merge_result=abandoned). Decide: rework it, or close it as not-planned."
      echo "$PROG: $id — PR#$num closed out-of-band; abandoned, routed to human, escalated"
    else
      echo "$PROG: $id abandoned transition failed; retry next pass" >&2
      skipped=$((skipped + 1))
    fi
    continue
  fi
  [ "$state" = "OPEN" ] || { skipped=$((skipped + 1)); continue; }

  # --- provenance cutover: when this PR's city posts started carrying the mark --
  # Every city post is marked by pr-post.sh, and anything unmarked is feedback.
  # The PR's older posts carry no mark, because they predate the marking, so a
  # post under our own login from before this instant stays the city's own
  # (gc_city_own). Stamped once, the first time any arm reads the open PR, drafts
  # included, so a PR opened later records an instant before anyone could post on
  # it unmarked. An unrecorded stamp leaves PSINCE empty, and gc_city_cutover
  # reads a malformed one as empty too; either way every post under our login
  # reads as the city's own for the pass: the routing this arm had before
  # marking, never a burst of the city's own notices as feedback. The stamp is
  # passed on as found, so the shape test lives in the definition alone, and a
  # malformed one is named here for a person to fix.
  PSINCE=$(printf '%s' "$row" | jq -r '(.metadata.pr_provenance_since // "") | tostring')
  if [ -z "$PSINCE" ]; then
    pnow=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
         --set "pr_provenance_since=$pnow" >/dev/null; then
      PSINCE="$pnow"
    else
      echo "$PROG: $id — PR#$num provenance cutover did not record; every post under our login reads as the city's own this pass (retry next pass)" >&2
    fi
  elif [ -z "$(jq -rn --arg s "$PSINCE" "$CITY_OWN_DEF"'gc_city_cutover($s)' 2>/dev/null)" ]; then
    echo "$PROG: $id — PR#$num pr_provenance_since '$PSINCE' is not a UTC instant; every post under our login reads as the city's own" >&2
  fi

  # --- status label: project the human-attention axis onto the PR list ----------
  # Above the draft-skip on purpose: the label projects the city's workflow state,
  # which a draft-early PR (specs/tk-6bji7k.1's future half) needs as much as an
  # open one, so this seam stays independent of the draft gate below. Best-effort
  # and idempotent — pr-status-label.sh derives working/needs-review/needs-attention
  # from the anchor's own state and writes only on a change. This sweep is the full
  # pass's alone: it costs a derivation per anchor, which the early arms spend
  # only where they change one of the label's inputs (the posture record and the
  # feedback routing below).
  cur_labels=$(printf '%s' "$PR_JSON" | jq -r '[.labels[]?.name] | join(",")' 2>/dev/null)
  if [ "$POSTURE_ONLY" != 1 ] && [ "$ROUTE_ONLY" != 1 ]; then
    reconcile_status_label "$id" "$num"
  fi

  [ "$is_draft" != "true" ] || { skipped=$((skipped + 1)); continue; }

  # --- posture: record what the PR is doing (a record, never a dispatch) --------
  # Placed ahead of every dispatch arm below so an anchor one of them claims
  # still gets its posture written; merge.sh reads the result off the bead
  # rather than asking GitHub. Written only when the value changes: this runs
  # for every anchor every 60s and an unchanged re-write is pure ledger churn.
  posture=""; max_c=0; max_r=0; max_i=0; pinned=0; unanswered=0; unengaged=0; unengaged_unreadable=0; UT_COUNT=""
  revs_raw=""; revs_open=""; cmts_raw=""; cmts_live=""; cmts_open=""; icmts_raw=""
  cwm=$(printf '%s' "$row" | jq -r '(.metadata.pr_comment_watermark // "") | tostring')
  rwm=$(printf '%s' "$row" | jq -r '(.metadata.pr_review_watermark // "") | tostring')
  iwm=$(printf '%s' "$row" | jq -r '(.metadata.pr_issue_comment_watermark // "") | tostring')
  obatch=$(printf '%s' "$row" | jq -r '(.metadata.pr_comment_batch // "") | tostring')
  orbatch=$(printf '%s' "$row" | jq -r '(.metadata.pr_review_batch // "") | tostring')
  oibatch=$(printf '%s' "$row" | jq -r '(.metadata.pr_issue_comment_batch // "") | tostring')
  case "$cwm" in ''|*[!0-9]*) cwm=0 ;; esac
  case "$rwm" in ''|*[!0-9]*) rwm=0 ;; esac
  case "$iwm" in ''|*[!0-9]*) iwm=0 ;; esac
  if [ -z "$head_oid" ]; then
    echo "$PROG: $id — PR#$num live head unresolved; posture not recorded (a posture pins to a head or says nothing)" >&2
  elif [ -z "$SELF_LOGIN" ]; then
    # Without the acting login no post reads as the city's own (gc_city_own
    # keys on it), so every notice the city ever posted would count as feedback,
    # and a weaker posture written here would clear a standing `commented` that
    # is holding the merge. Record nothing; hold what stands.
    echo "$PROG: $id — PR#$num posture not recorded: the acting login is unresolved" >&2
  elif [ "$SHORT" = 1 ]; then
    # Nothing the posture was derived from has moved since: no review, comment
    # or push, the same review decision, watermarks and cutover. Deriving it
    # again would read the same lists and answer the same value.
    posture="$SHORT_P"
    pkept=$((pkept + 1))
  else
    [ "$POSTURE_ONLY" != 1 ] || pread=$((pread + 1))
    revs_raw=$(gh_rows "repos/$ORIGIN_REPO/pulls/$num/reviews?per_page=100") || revs_raw=""
    cmts_raw=$(gh_rows "repos/$ORIGIN_REPO/pulls/$num/comments?per_page=100") || cmts_raw=""
    # The Conversation tab is a third feedback space in its own id range: operator
    # direction posted there is neither a review nor an inline comment. An empty
    # read of it holds the posture the same way the other two do, or a clean
    # posture written here would let merge.sh through over unread direction.
    icmts_raw=$(gh_rows "repos/$ORIGIN_REPO/issues/$num/comments?per_page=100") || icmts_raw=""
    if [ -z "$revs_raw" ] || [ -z "$cmts_raw" ] || [ -z "$icmts_raw" ]; then
      # A standing CHANGES_REQUESTED is settled by reviewDecision alone, so the
      # posture is still recorded; only the dispatch below needs the lists, and
      # it holds for a pass that can read them.
      if [ "$rd" = "CHANGES_REQUESTED" ]; then
        posture="changes_requested"
        echo "$PROG: $id — PR#$num feedback history unreadable; posture read from the review decision, the feedback under it not routed (retry next pass)" >&2
      else
        echo "$PROG: $id — PR#$num feedback history unreadable; posture not recorded (retry next pass)" >&2
      fi
    else
      # The comment space drops what a dismissal retired before anything counts
      # it, so the two spaces agree about what a dismissal takes out. A filter
      # that cannot run counts the unfiltered list: over-routing costs a rework
      # round an operator can close, dropping the batch costs the objection
      # itself.
      cmts_live=$(live_comments "$revs_raw" "$cmts_raw")
      if [ -z "$cmts_live" ]; then
        echo "$PROG: $id — PR#$num could not filter retired reviews out of the comment list; counting it unfiltered" >&2
        cmts_live="$cmts_raw"
      fi
      # Drop the feedback the review threads have answered, so feedback answered
      # off the watermark stops reading as unanswered and holding the merge: an
      # inline comment its thread answered, and a review whose every inline
      # comment was. Nothing routes answered feedback, so nothing moves a
      # watermark past it, and the threads would be re-read on every pass until
      # the PR merged. A read records how far the threads have answered past each
      # watermark (cam, cwm's answered mark; ram, rwm's), and a pass whose newest
      # feedback sits at or below both marks skips the read and drops what they
      # cover. A read that cannot answer drops only what the marks cover: an
      # unreadable read never drops an objection. A mark is a confirmation the way
      # a watermark is a routing, so a thread unresolved after the mark passed its
      # comment routes nothing until a new comment brings the read back, the same
      # as an unresolve under the watermark, and a reply always carries a new id
      # above the mark. cmts_live stays whole for unengaged_holds, which reads it
      # below.
      cmts_open="$cmts_live"; revs_open="$revs_raw"
      c_ids=$(foreign_ids "$cmts_live"); r_ids=$(counted_review_ids "$revs_raw")
      raw_max_c=$(printf '%s' "$c_ids" | max_id); raw_max_r=$(printf '%s' "$r_ids" | max_id)
      max_c="$raw_max_c"; max_r="$raw_max_r"
      if [ "$raw_max_c" -gt "$cwm" ] || [ "$raw_max_r" -gt "$rwm" ]; then
        cam=$(printf '%s' "$row" | jq -r '(.metadata.pr_comment_answered // "") | tostring')
        ram=$(printf '%s' "$row" | jq -r '(.metadata.pr_review_answered // "") | tostring')
        case "$cam" in ''|*[!0-9]*) cam=0 ;; esac
        case "$ram" in ''|*[!0-9]*) ram=0 ;; esac
        [ "$cam" -ge "$cwm" ] || cam="$cwm"
        [ "$ram" -ge "$rwm" ] || ram="$rwm"
        ans_c=$(ids_within "$c_ids" "$cwm" "$cam"); ans_r=$(ids_within "$r_ids" "$rwm" "$ram")
        if [ "$raw_max_c" -gt "$cam" ] || [ "$raw_max_r" -gt "$ram" ]; then
          if review_threads_load "$num" && read_c=$(answered_comment_ids) \
             && read_r=$(answered_review_ids "$revs_raw" "$cmts_live" "$read_c"); then
            ans_c="$read_c"; ans_r="$read_r"
            cam_new=$(answered_through "$cwm" "$c_ids" "$ans_c")
            ram_new=$(answered_through "$rwm" "$r_ids" "$ans_r")
            case "$cam_new" in ''|*[!0-9]*) cam_new="$cam" ;; esac
            case "$ram_new" in ''|*[!0-9]*) ram_new="$ram" ;; esac
            marks=()
            [ "$cam_new" = "$cam" ] || marks+=(--set "pr_comment_answered=$cam_new")
            [ "$ram_new" = "$ram" ] || marks+=(--set "pr_review_answered=$ram_new")
            if [ "${#marks[@]}" -gt 0 ] && ! "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
                 "${marks[@]}" >/dev/null; then
              MARKS_UNRECORDED=1
              echo "$PROG: $id — PR#$num answered marks did not record; the threads are read again next pass" >&2
            fi
          else
            echo "$PROG: $id — PR#$num review-thread resolution unreadable; counting the feedback above the answered marks unfiltered" >&2
          fi
        fi
        if c_kept=$(drop_ids "$cmts_live" "$ans_c") && [ -n "$c_kept" ] \
           && r_kept=$(drop_ids "$revs_raw" "$ans_r") && [ -n "$r_kept" ]; then
          cmts_open="$c_kept"; revs_open="$r_kept"
          max_r=$(max_counted_review_id "$revs_open")
          max_c=$(max_foreign_id "$cmts_open")
        else
          echo "$PROG: $id — PR#$num could not drop answered feedback; counting the batch unfiltered" >&2
        fi
      fi
      # An issue comment carries no review state and no inline path; every one
      # that is not the city's own post is feedback the loop has to answer, the
      # same test the inline space uses. Its ids are a separate range, so it
      # earns its own watermark rather than sharing max_c's.
      max_i=$(max_foreign_id "$icmts_raw")
      # The routing transition writes these three back as the watermarks, and a
      # mark only rises. A count can fall below its mark: the threads drop the
      # comments they answered, a dismissal retires a review and its comments, and
      # a comment can be deleted. Written back, a fallen mark would re-route every
      # comment under it that its thread later lost, and the next batch's floor
      # would overlap the ranges already recorded in pr_comment_batch.
      [ "$max_c" -ge "$cwm" ] || max_c="$cwm"
      [ "$max_r" -ge "$rwm" ] || max_r="$rwm"
      [ "$max_i" -ge "$iwm" ] || max_i="$iwm"
      if [ "$max_c" -gt "$cwm" ] || [ "$max_r" -gt "$rwm" ] || [ "$max_i" -gt "$iwm" ]; then unanswered=1; fi
      # An unmarked review posted under OUR OWN login before the cutover leaves
      # unresolved finding threads arm 7 never counts — it reads them as the city's
      # own — so `unanswered` stays 0 while the check stays green, and the posture
      # would read review_required/none. merge.sh
      # reads posture off the bead and never reads threads, and the full pass that
      # would file the visit runs after merge, so the hold has to be recorded HERE,
      # in the pre-merge pass. Fold a confirmed hold into `commented`; a read that
      # would not run (rc 2) is not proof of zero, so it leaves the posture
      # uncurrent below and the merge holds for the pass. The visit is dispatched
      # below.
      if [ "$rd" != "CHANGES_REQUESTED" ] && [ "$unanswered" != 1 ]; then
        unengaged_holds "$id" "$num" "$head_oid" "$row" "$cmts_live"; uh_rc=$?
        if [ "$uh_rc" = 0 ]; then unengaged=1
        elif [ "$uh_rc" = 2 ]; then unengaged_unreadable=1
        fi
      fi
      # The posture is what merge.sh reads, and a standing CHANGES_REQUESTED
      # outranks the batch underneath it: the veto stands whether or not that
      # feedback has been routed yet. What routes is `unanswered`, below.
      if [ "$rd" = "CHANGES_REQUESTED" ]; then posture="changes_requested"
      elif [ "$unanswered" = 1 ] || [ "$unengaged" = 1 ]; then posture="commented"
      elif [ "$unengaged_unreadable" = 1 ]; then
        # The thread read did not answer. Recording review_required/none here would
        # be current and let merge.sh through on a fact we do not have; leave the
        # posture uncurrent so --posture-only holds the merge, and retry next pass.
        echo "$PROG: $id — PR#$num unengaged-thread read did not answer; posture not recorded (retry next pass)" >&2
      elif [ "$rd" = "APPROVED" ]; then posture="approved"
      elif [ "$rd" = "REVIEW_REQUIRED" ]; then posture="review_required"
      else posture="none"
      fi
    fi
  fi
  case " $PR_POSTURES " in
    *" $posture "*) : ;;
    *) [ -z "$posture" ] || { echo "$PROG: $id — refusing to record undeclared posture '$posture'" >&2; posture=""; } ;;
  esac
  have_p=$(printf '%s' "$row" | jq -r '(.metadata.pr_posture // "") | tostring')
  if [ -n "$posture" ]; then
    want_p="$posture@$head_oid"; want_m="${merge_state:-UNKNOWN}@$head_oid"
    have_m=$(printf '%s' "$row" | jq -r '(.metadata.pr_merge_state // "") | tostring')
    # pr_posture is a dated key: its review_required value starts an owed clock,
    # so the recorded value carries the instant as a third component and
    # lifecycle.sh preserves it while the posture and the head both hold. Only a
    # value already in that shape can be current — one still carrying the bare
    # <value>@<oid> has no instant, and one pass writing it is how it gains one.
    have_pv=""
    case "$have_p" in *@*@*) have_pv="${have_p%@*}" ;; esac
    if [ "$have_pv" = "$want_p" ] && [ "$have_m" = "$want_m" ]; then
      pinned=1
    elif "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
           --set-dated "pr_posture=$want_p" --set "pr_merge_state=$want_m" >/dev/null; then
      pinned=1
      postured=$((postured + 1))
      echo "$PROG: $id — PR#$num posture $want_p, merge state $want_m"
      # The posture value is where a review on the PR lands: an approval, a
      # comment, a change request, or a dismissal. A pass that changes it
      # re-derives the status: label now rather than leaving it for the full
      # pass's reconcile. A moved head or merge state alone does not. GitHub
      # reports UNKNOWN while it computes a PR's mergeability, so most posture
      # writes are a merge state moving into or out of UNKNOWN, often for dozens
      # of open PRs in one arm. Keying on them would buy a derivation per PR in
      # that arm, and the full pass reconciles those.
      [ "${have_p%%@*}" = "$posture" ] || reconcile_status_label "$id" "$num"
    else
      echo "$PROG: $id posture record failed for PR#$num; retry next pass" >&2
    fi
  fi
  # merge.sh validates the posture recorded here and never asks GitHub, so an
  # anchor this pass could not make current is one it would clear against a
  # fact from an earlier tick. A standing `commented@` is already holding that
  # merge; every other shape is the gap, and --posture-only reports it in its
  # exit code so refinery-reconcile can hold the merge arm for the pass.
  if [ "$pinned" != 1 ]; then
    case "$have_p" in
      commented@*) : ;;
      *) unpostured=$((unpostured + 1))
         echo "$PROG: $id — PR#$num posture is not current; merge must not read it this pass" >&2 ;;
    esac
  fi
  # The basis a current posture earns, kept by --seen: only one the batched read
  # describes (the head this posture is pinned to), and only a value the PR's own
  # facts decide. A `commented` posture, or one an unengaged-thread candidate had
  # a say in, can change with nothing on the PR moving, so it keeps none. Nor
  # does a derivation whose answered marks did not record: the marks are what let
  # the next derivation drop answered feedback without reading the threads, so
  # until they land the threads are read again, and a basis would skip that read.
  # A derivation confirms the candidate the last pass recorded when it reads the
  # same basis and derives the same posture; otherwise it records its own
  # candidate. A posture kept on a confirmed basis keeps that basis.
  if [ "$POSTURE_ONLY" = 1 ] && [ "$pinned" = 1 ] && [ -n "$PFP" ] \
     && [ "$head_oid" = "${OPEN_ACT[$num]%%|*}" ]; then
    case "$posture" in
      approved|review_required|none|changes_requested)
        if [ "$SHORT" = 1 ] || { [ "$UH_CANDIDATE" != 1 ] && [ "$MARKS_UNRECORDED" != 1 ] && [ "$b_seen" = "?$posture#$PFP" ]; }; then
          pace_seen_mark "$posture#$PFP"
        elif [ "$UH_CANDIDATE" != 1 ] && [ "$MARKS_UNRECORDED" != 1 ]; then
          pace_seen_mark "?$posture#$PFP"
        fi ;;
    esac
  fi

  # merge.sh reads posture off the bead and never asks GitHub, so the record has
  # to be no older than the merge arm that reads it. --posture-only is the
  # pre-merge pass: it writes the posture and stops here.
  # --route-comments-only runs on into the feedback-routing arm below (and stops
  # after it), so operator feedback is picked up ahead of the slow arms rather
  # than waiting for the full pass at the tail; every other dispatch arm is the
  # full pass's.
  [ "$POSTURE_ONLY" != 1 ] || continue

  # --- base moved: retargeted + visit; a pre-retarget review proves nothing ------
  rec_target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // ""')
  if [ -n "$rec_target" ] && [ -n "$base" ] && [ "$rec_target" != "$base" ]; then
    # An early arm defers retarget handling to the full pass. A retargeted
    # anchor does not merge this pass, and its feedback is not routed while it
    # sits on the wrong base, so the early feedback arm skips it.
    [ "$ROUTE_ONLY" != 1 ] || continue
    UNSETS=()
    while IFS= read -r g; do
      [ -n "$g" ] && UNSETS+=(--unset "check.$g")
    done <<GATES
$(printf '%s' "$checkset" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d')
GATES
    if "$LIFECYCLE" transition "$id" --to retargeted --expect pull_request \
         --assignee "" ${UNSETS[@]+"${UNSETS[@]}"} \
         --set "blocked_reason=PR#$num retargeted: base '$base' != expected target '$rec_target'" \
         --takeaway "PR#$num sits on a base other than its expected target — retarget it back, or update merged_target"; then
      flagged=$((flagged + 1))
      escalate "$id" "pr-retargeted.$num" \
        "PR#$num ($live_url) was retargeted: base '$base' != expected '$rec_target'. Retarget it back and reset merge_result=pull_request to re-engage, or update merged_target if the new base is intentional."
      echo "$PROG: $id — PR#$num retargeted (base '$base' != '$rec_target'); routed to human, check markers cleared, escalated"
    else
      echo "$PROG: $id retargeted transition failed; retry next pass" >&2
      skipped=$((skipped + 1))
    fi
    continue
  fi

  # --- SELF-HEAL: reap a rework child whose premise the branch has outrun -------
  # A rework child filed against a past head is moot once the branch has moved on
  # and the current head is clean and green: the fix it asked for is no longer
  # owed, yet nothing retracts it. It sits open, holding the anchor through its
  # blocks-dep, until a person clears it — the merge-lane analogue of the
  # self-heal the reconcile lane already does for its own orphaned visits. Reap
  # ONLY a provably-dead premise: fire on the CONJUNCTION of head-moved-past-the-cited-head AND a
  # current head that is mergeable with every required check green; leave anything
  # unprovable OPEN (fail closed); never touch a child a worker holds
  # (in_progress). Idempotent: a child still citing the live head, or a head not
  # provably green, matches nothing.
  if [ "$state" = "OPEN" ] && [ -n "$head_oid" ]; then
    reap_kids=$(bd_list --metadata-field anchor_bead="$id" --status=open 2>/dev/null) || reap_kids=""
    # open, unclaimed rework children of this anchor, as "<id>\t<reason>" rows.
    # Only a conflict or red-check child has a premise that "mergeable + green"
    # falsifies (no longer conflicting; the check passed). A comment-rework child's
    # premise is unanswered feedback, which a moved head and a green check do not
    # settle, so it is never a reap candidate — its own anchor_bead-keyed dedup
    # owns its lifecycle.
    reap_rows=$(printf '%s' "$reap_kids" | jq -r --arg id "$id" '
      .[]? | select(((.metadata.task_kind // "") | tostring) == "rework")
      | select(.id != $id)
      | select(((.status // "open") | ascii_downcase) == "open")
      | select(((.assignee // "") | tostring) == "")
      | ((.metadata.rejection_reason // "") | tostring) as $rr
      | select(($rr | test("conflicts with")) or ($rr | test("Required check")))
      | [ .id, ($rr | gsub("[\n\t]"; " ")) ] | @tsv' 2>/dev/null)
    if [ -n "$reap_rows" ]; then
      # A child whose CITED head — the "head <oid>" both dispatch arms embed in the
      # reason — the current head has left behind. No cited head is ambiguous, and
      # a child still at the live head is not moot: both are left OPEN.
      reap_targets=""
      head_lc=$(printf '%s' "$head_oid" | tr 'A-Z' 'a-z')
      while IFS="$(printf '\t')" read -r kid krr; do
        [ -n "$kid" ] || continue
        cited=$(printf '%s' "$krr" | grep -oiE 'head [0-9a-f]{7,40}' | head -1 | awk '{print $2}' | tr 'A-Z' 'a-z')
        [ -n "$cited" ] || continue
        [ "$cited" != "$head_lc" ] || continue
        reap_targets="$reap_targets $kid"
      done <<REAP_EOF
$reap_rows
REAP_EOF
      if [ -n "${reap_targets# }" ]; then
        # Green-proof the current head once, before closing anything: it must be
        # mergeable AND every required context must read back a positive SUCCESS.
        # An empty or unreadable rollup, a pending or missing context, or an
        # unknown required set is "cannot prove" — which reaps nothing.
        reap_green=0
        if [ "$mergeable" = "MERGEABLE" ]; then
          required_contexts_for "$base"
          if [ "$REQ_STATE" = "known" ] && [ -n "$REQ_CONTEXTS" ]; then
            reap_req_json=$(printf '%s\n' "$REQ_CONTEXTS" | jq -Rs 'split("\n") | map(select(length > 0))' 2>/dev/null)
            reap_rollup=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json statusCheckRollup 2>/dev/null)
            reap_ok=$(printf '%s' "$reap_rollup" | jq -r --argjson req "${reap_req_json:-[]}" '
              def name_of: (.name // .context // "");
              def green:
                if ((.conclusion // "") | tostring | length) > 0 then ((.conclusion | ascii_upcase) == "SUCCESS")
                elif ((.state // "") | tostring | length) > 0 then ((.state | ascii_upcase) == "SUCCESS")
                else false end;
              (.statusCheckRollup // []) as $r
              | [ $req[] as $c
                  | ([ $r[] | select(type == "object") | select(name_of == $c) ]) as $m
                  | (($m | length) > 0 and ($m | all(green))) ]
              | (length > 0 and all)' 2>/dev/null)
            [ "$reap_ok" = "true" ] && reap_green=1
          fi
        fi
        if [ "$reap_green" = "1" ]; then
          for kid in $reap_targets; do
            if gc bd update "$kid" --status=closed --set-metadata gc.outcome=moot \
                 --append-notes "Reaped moot by $PROG: filed against a stale head of PR#$num, but the current head $head_oid is mergeable with required checks green, so the rework it asked for is no longer owed." >/dev/null 2>&1; then
              echo "$PROG: $id reaped moot rework child $kid (PR#$num advanced past its cited head to a green $head_oid)"
              reaped=$((reaped + 1))
            else
              echo "$PROG: WARN $id could not reap moot rework child $kid (retry next pass)" >&2
            fi
          done
        fi
      fi
    fi
  fi

  # --- CONFLICTING: bring the branch current, or route its feedback -------------
  # A conflicting anchor holds the merge. The operator-gate skip guards below — a
  # hold, a live demand, an armed re-dispatch, a foreign blocker — defer the whole
  # anchor, feedback included, because each parks the review by design and lifts
  # on its own; the next pass routes the feedback then. A missing head branch or
  # fix pool is not such a gate: it blocks only the merge-in dispatch, so an
  # anchor owing feedback still falls through to the feedback arm, whose visit
  # fallback dispositions the unresolved-branch and no-fix-pool cases. Past those
  # guards the anchor is dispatchable, and what it owes decides how: with
  # unanswered feedback it falls through to the feedback arm below (whose
  # prepare_mode=merge child brings the branch current as it answers); otherwise
  # this arm files the one merge-in child, once the PR is approved. The gate that
  # splits the two, and the approval gate after it, sit just above the dedup.
  if [ "$mergeable" = "CONFLICTING" ] || [ "$merge_state" = "DIRTY" ]; then
    if is_held "$rhold"; then
      echo "$PROG: $id — PR#$num conflicts but a hold is set (operator gate); no rework dispatched"
      skipped=$((skipped + 1)); continue
    fi
    if is_held "$hold"; then
      echo "$PROG: $id — PR#$num conflicts but a hold is set (operator gate); no rework dispatched"
      skipped=$((skipped + 1)); continue
    fi
    # A live demand is the same freeze. `gc-helm.sh demand` files what a person
    # owes as a human gate on this anchor, and "rebase it onto the base" is
    # routinely one horn of the question being asked. A child dispatched under
    # one performs that horn as routine branch hygiene, which answers the
    # decision by fait accompli and leaves the person ruling on work already
    # done. The demand may sit on the anchor or on the live rework child that is
    # reconciling its branch; anchor_decision_held reads both, because a decision
    # on the child gates the one branch they share. The anchor's own gc.routed_to
    # is not read here: the human route sits on the demand gate, not on what it
    # gates, and a freeze on the anchor's route would hold the merge with nothing
    # defined to lift it. Resolving the demand gate lifts this one, which is what
    # the demand's own text asks for.
    if anchor_decision_held "$id"; then
      echo "$PROG: $id — PR#$num conflicts but an open demand holds it for a person's decision; no rework dispatched"
      skipped=$((skipped + 1)); continue
    fi
    if [ -n "$armed" ]; then
      echo "$PROG: $id — PR#$num conflicts but the anchor is armed to re-dispatch when ready (gc.dispatch_when_ready=$armed); no rework dispatched"
      skipped=$((skipped + 1)); continue
    fi
    fix_branch="${head_ref:-$branch}"
    # fix_branch and FIX_POOL are needed only to DISPATCH the merge-in child, so
    # this guard fires under the same condition as that dispatch (below). An anchor
    # that owes unanswered feedback — or a --route-comments-only pass — does not
    # dispatch one here; it falls through to the feedback arm, whose visit fallback
    # dispositions exactly these cases (an unresolved head branch, no configured
    # fix pool). Skipping the whole anchor would strand that feedback with no
    # visit, no finding beads, and no validation pass.
    if [ -z "$fix_branch" ] || [ -z "$FIX_POOL" ]; then
      if [ "$unanswered" != 1 ] && [ "$ROUTE_ONLY" != 1 ]; then
        echo "$PROG: $id — PR#$num conflicts but branch/fix-pool unavailable; merge stays held (operator must repair)" >&2
        skipped=$((skipped + 1)); continue
      fi
    fi
    # --- HOW the child is told to bring this branch current. ----------------------
    # >>> stale-base-dispatch-mode
    # This arm dispatches the bring-current rather than performing it. It makes the
    # same choice as mol-refinery-patrol's `shared-branch-merge-mode`, deliberately
    # restated where the second actor is chosen rather than a second discriminator
    # invented here: every branch shape is brought current by MERGING origin/$base
    # in, never by a rebase. A rebase rewrites history and forces a --force-with-lease
    # push, which resets the PR's "changes since last review" and drifts its
    # line-anchored review comments; a merge keeps both, and no shape rewriting means
    # none can force-push. Classified on fix_branch, the branch the child is told to
    # bring current, not on the anchor's recorded branch.
    # See specs/tk-yu4sng/merge-in-for-all-branches.md.
    prepare_mode=merge
    FIX_TITLE="Merge $base into PR#$num (branch $fix_branch):"
    fix_instruction="Resume in prepare_mode=merge: bring '$fix_branch' current by MERGING origin/$base IN (git merge --no-edit origin/$base), resolve conflicts, and push as a fast-forward. Do NOT rebase it and do NOT force-push it: a rewrite resets the PR's review view, and on a shared branch it also orphans the already-merged PRs the branch carries (tk-a0hva)."
    # <<< stale-base-dispatch-mode
    # Do not bring the branch current while the anchor is held for a reason other
    # than the rework itself. anchor_foreign_blocker reads every live blocker on
    # the anchor and excludes this arm's own children (this branch, this anchor's
    # rework marker, or the dispatch title the orphan adoption below matches), so
    # a covering child still dedups and a stranded or orphaned one is still
    # re-routed — while a sibling PR it depends on, a live review, or a demand a
    # closed one left standing holds the dispatch.
    fblockers=$(anchor_foreign_blocker "$id" "$fix_branch" "$FIX_TITLE"); fbrc=$?
    if [ "$fbrc" -eq 0 ]; then
      echo "$PROG: $id — PR#$num conflicts but the anchor is held by ${fblockers:-an unreadable blocker} (a merge is held on it); no rework dispatched"
      skipped=$((skipped + 1)); continue
    fi
    # Past the skip guards, the anchor is dispatchable. When it also owes
    # unanswered feedback, or on an early routing pass (--route-comments-only),
    # this arm files no merge-in child: the feedback arm below dispatches a
    # prepare_mode=merge child that brings this same branch current (a MERGE of
    # origin/$base on resume) as it answers, so a merge-in child here would only
    # twin it on the branch. Fall through to route the feedback. Only a full-pass
    # conflict with no feedback owed dispatches this arm's own merge-in child,
    # and only on an approved PR.
    if [ "$unanswered" != 1 ] && [ "$ROUTE_ONLY" != 1 ]; then
      # >>> conflict-arm-approval-gate
      # The merge-in is filed only for an approved PR: a standing APPROVED review
      # from an account other than the city's and no standing CHANGES_REQUESTED,
      # by the same rule merge.sh lands on (review-verdict.sh).
      # Each bring-current costs a polecat round and a fresh CI run, and it goes
      # stale again whenever main moves, while a PR nobody approved cannot land
      # however current its branch is. So its conflict waits for the approval,
      # with its posture already recorded above. A merge-in child already open on
      # the branch is left as it is. Reviews that did not read, or an unresolved
      # acting login, prove no approval: nothing is filed and the next pass
      # retries.
      approval=""
      if [ -n "$SELF_LOGIN" ] && [ -n "$revs_raw" ]; then
        approval=$(printf '%s' "$revs_raw" | jq -r --arg self "$SELF_LOGIN" "$REVIEW_VERDICT_DEF"'
          review_verdict($self)
          | if .veto != "" then "veto:" + .veto elif .approver != "" then "approved" else "none" end' 2>/dev/null)
      fi
      case "$approval" in
        approved) : ;;
        veto:*)
          echo "$PROG: $id — PR#$num conflicts but '${approval#veto:}' has a standing CHANGES_REQUESTED; no merge-in filed, the branch is brought current once the PR is approved"
          skipped=$((skipped + 1)); continue ;;
        none)
          echo "$PROG: $id — PR#$num conflicts but no external approval stands; no merge-in filed, the branch is brought current once the PR is approved"
          skipped=$((skipped + 1)); continue ;;
        *)
          echo "$PROG: $id — PR#$num conflicts but its reviews could not be read to prove an approval; no merge-in filed (retry next pass)" >&2
          skipped=$((skipped + 1)); continue ;;
      esac
      # <<< conflict-arm-approval-gate
      # Dedup on a LIVE child on this branch, in flight or parked — the child's own
      # metadata, no bookkeeping key on the anchor. A non-closed child owns the
      # branch: a live one is already bringing it current and a second would race
      # its push, and one parked for a person (the `held` lifecycle state,
      # merge_result=held) still holds it. A CLOSED child does NOT stand the
      # dispatch down — its round is over — so a branch still CONFLICTING with
      # nothing in flight re-dispatches, on every head it conflicts at rather than
      # only the PR's first; this is what stops an approved PR gone dirty after its
      # round from wedging unseen when nothing is left in flight. A rework child of
      # THIS anchor counts even when it carries a merge_result, because the held
      # state carries one yet still owns the branch, so the merge_result test alone
      # would drop it and re-mint a twin.
      kids=$(bd_list --metadata-field branch="$fix_branch" --status="$ALL_STATUSES") || {
        echo "$PROG: $id — PR#$num conflicts but the rework probe failed; no rework dispatched (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      }
      # A child of a prior pass whose route stamp exited 0 without writing. The
      # route is what makes it reachable — neither `bd ready` nor a pool claim can
      # see it without one — and the dedup below matches it, so nothing retries it.
      # Narrow to open/unassigned/unrouted at THIS head: a metadata write ignores
      # bd's claim guard, so re-stamping a child someone holds stomps live work.
      stranded=$(printf '%s' "$kids" | jq -r --arg id "$id" --arg h "$head_oid" '
        [ .[] | select(.id != $id)
          | select(((.status // "open") | ascii_downcase) == "open")
          | select(((.assignee // "") | tostring) == "")
          | select(((.metadata["gc.routed_to"] // "") | tostring) == "")
          | select(((.metadata["gc.execution_routed_to"] // "") | tostring) == "")
          | select(((.metadata.merge_result // "") | tostring) == "")
          | select(($h != "") and (((.metadata.rejection_reason // "") | tostring) | contains("head " + $h)))
          | .id ] | .[0] // empty' 2>/dev/null)
      # A strand is open, so it matches the live arm below and would veto its own
      # rescue; it is excluded from its own dedup and from nothing else. Any OTHER
      # match still vetoes — a second routed child would race the force-push the
      # first one already owns.
      dup=$(printf '%s' "$kids" | jq -r --arg id "$id" --arg s "$stranded" --arg live "$LIVE_STATUSES" '
        ($live | split(",")) as $ls
        | [ .[] | select(.id != $id) | select(.id != $s)
            | select(((.metadata.merge_result // "") | tostring) == ""
                     or (((.metadata.task_kind // "") == "rework")
                         and (((.metadata.anchor_bead // "") | tostring) == $id)))
            | ((.status // "open") | ascii_downcase) as $st
            | select(($ls | index($st)) != null)
            | .id ] | .[0] // empty' 2>/dev/null)
      if [ -n "$dup" ]; then
        # $dup is treated as already dispatched and never flows through the stamp
        # below, so a covering child minted before this marker existed — or one
        # whose marker write half-landed — would sit on the anchor's own branch
        # with no role marker, indistinguishable from the anchor by metadata.
        # Re-stamp only an UNCLAIMED dup that lacks it. A metadata write ignores
        # bd's claim guard, so writing under a live holder is what this arm refuses
        # elsewhere; and the creation path's route read-back now refuses to route an
        # unmarked child, so a CLAIMED one can only predate this stamp and is
        # backfilled out of band, never minted unmarked here. A closed dup is
        # dispositioned and read by no live gate; an unreadable probe re-stamps
        # nothing.
        dneed=$(gc bd show "$dup" --json 2>/dev/null | scrub | jq -r --arg id "$id" '
          .[0] as $x
          | if (($x | type) != "object") then "ok"
            elif ((($x.status // "") | ascii_downcase) == "closed") then "ok"
            elif ((($x.assignee // "") | tostring) != "") then "ok"
            elif ((($x.metadata.task_kind // "") == "rework") and (($x.metadata.anchor_bead // "") == $id)) then "ok"
            else "restamp" end' 2>/dev/null)
        if [ "$dneed" = "restamp" ]; then
          # `gc bd update` returns 0 without writing (the claim guard is one such
          # path), so the exit code cannot prove the marker landed — and a covering
          # child left unmarked on the anchor's own branch is the misread this stamp
          # exists to stop. Read both keys back and re-stamp once, claiming the
          # re-stamp only when it persists; the next pass reaches this same block to
          # try again rather than report an unmarked child as marked.
          gc bd update "$dup" --set-metadata task_kind=rework --set-metadata anchor_bead="$id" >/dev/null 2>&1 || true
          dgot=$(gc bd show "$dup" --json 2>/dev/null | scrub | jq -r '.[0].metadata | ((.task_kind // "") + "|" + (.anchor_bead // ""))')
          if [ "$dgot" != "rework|$id" ]; then
            gc bd update "$dup" --set-metadata task_kind=rework --set-metadata anchor_bead="$id" >/dev/null 2>&1 || true
            dgot=$(gc bd show "$dup" --json 2>/dev/null | scrub | jq -r '.[0].metadata | ((.task_kind // "") + "|" + (.anchor_bead // ""))')
          fi
          if [ "$dgot" = "rework|$id" ]; then
            echo "$PROG: $id re-stamped role marker on covering rework $dup (task_kind=rework, anchor_bead=$id)"
          else
            echo "$PROG: WARN could not re-stamp role marker on covering rework $dup (retry next pass)" >&2
          fi
          # The re-stamp changed $dup's role marker; drop the per-pass bd_list cache
          # so a later same-branch anchor's dedup reads the new marker. No-op outside
          # a reconcile pass.
          bd_cache_clear
        fi
        echo "$PROG: $id — PR#$num conflicts; rework $dup already covers branch '$fix_branch' at this head, no new child${stranded:+ (unrouted sibling $stranded is redundant and holds the anchor)}"
        skipped=$((skipped + 1)); continue
      fi
      # Any rebase_hold on a bead naming this branch is an operator freeze.
      frozen=$(printf '%s' "$kids" | jq -r '
        [ .[] | ((.metadata.rebase_hold // "") | tostring | ascii_downcase) as $h
          | select($h != "" and $h != "false" and $h != "0" and $h != "null") | .id ] | .[0] // empty' 2>/dev/null)
      if [ -n "$frozen" ]; then
        echo "$PROG: $id — PR#$num conflicts but $frozen holds branch '$fix_branch' with rebase_hold (operator gate); no rework dispatched"
        skipped=$((skipped + 1)); continue
      fi
      reuse=""
      if [ -n "$stranded" ]; then
        reuse="$stranded"
        echo "$PROG: $id re-routing stranded rework $reuse for PR#$num (a prior pass's route stamp did not land)"
      else
        # Orphan adoption BEFORE create: a child a prior pass created but could not
        # stamp carries the deterministic title but no branch metadata — invisible
        # to the branch dedup above, so re-creating would mint a twin every pass.
        # The title is a pure function of the PR number and head branch. An
        # unreadable probe dispatches nothing (retry next pass).
        if ! forphans=$(bd_list --status=open --title-contains "$FIX_TITLE"); then
          echo "$PROG: $id — PR#$num conflicts but the orphan probe failed; no rework dispatched (retry next pass)" >&2
          skipped=$((skipped + 1)); continue
        fi
        reuse=$(printf '%s' "$forphans" | jq -r '
          [ .[] | select(((.metadata.branch // "") | tostring) == "") | .id ] | .[0] // empty' 2>/dev/null)
        [ -n "$reuse" ] && echo "$PROG: $id adopting unstamped rework orphan $reuse for PR#$num (created by a prior pass whose stamp failed)"
      fi
      # Atomic birth: form the child fully — every identity key plus the blocks-dep
      # — or not at all, so a child that can veto a merge but cannot be rescued or
      # reaped is never left behind. mint_rework_child reads the whole identity back
      # (rejection_reason included) and unmakes a newborn it cannot complete. The
      # route is stamped LAST, on the id it returns, so only a complete child ever
      # becomes claimable; a route that does not land leaves a rescuable child the
      # stranded arm re-routes next pass, never a husk.
      FIX=$(mint_rework_child "$reuse" "$FIX_TITLE base rewritten, PR conflicts" "$id" "$fix_branch" "$base" \
        "stale base at head $head_oid: PR#$num conflicts with '$base'. $fix_instruction Do NOT open a new PR — this reworks PR#$num." \
        "$prepare_mode" "$live_url" "$num")
      if [ -z "$FIX" ]; then
        echo "$PROG: $id could not form the rework child for PR#$num; retry next pass" >&2
        skipped=$((skipped + 1)); continue
      fi
      gc bd update "$FIX" --set-metadata gc.routed_to="$FIX_POOL" >/dev/null 2>&1 || true
      rgot=$(gc bd show "$FIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata["gc.routed_to"] // empty')
      if [ "$rgot" != "$FIX_POOL" ]; then
        echo "$PROG: WARN rework $FIX formed but not routed to $FIX_POOL; left unrouted, the stranded arm re-routes it next pass" >&2
        skipped=$((skipped + 1)); continue
      fi
      gc session wake "$FIX_POOL" >/dev/null 2>&1 || true
      reworked=$((reworked + 1))
      echo "$PROG: $id — PR#$num conflicts with '$base'; filed $prepare_mode-mode rework $FIX routed to $FIX_POOL"
      continue
    fi
  fi

  # --- unanswered review feedback routes to something ---------------------------
  # Reached for any anchor with unanswered feedback, a conflicting one included:
  # the CONFLICTING arm above stands down when there is feedback to route, so the
  # review loop runs while the branch conflicts rather than waiting for a merge-in
  # child to land first. The retarget (base-moved) arm still ends its own anchors
  # before here. Whatever this
  # routes to holds the merge until it closes, and the watermarks move only once
  # the routing has read back — feedback nothing answered can never fall below
  # the mark.
  # The batch is the same whether the posture reads `commented` or
  # `changes_requested`. A CHANGES_REQUESTED holds the merge on its own, and a
  # hold is not an answer: objections nothing routes converge to correctness-green
  # untouched, while the commits landing meanwhile read as rework that addressed
  # them.
  if [ "$unanswered" = 1 ]; then
    fix_branch="${head_ref:-$branch}"
    routed=$(printf '%s' "$row" | jq -r '(.metadata["gc.routed_to"] // "") | tostring')
    # Read once: the routing choice below turns on whether a person or a sitting
    # is holding this anchor, and each answer costs a ledger read. The demand may
    # sit on the anchor or on the live rework child reconciling its branch;
    # anchor_decision_held reads both.
    holding=""; anchor_decision_held "$id" && holding=1

    # A human already holding this anchor gets the comments; filing work under a
    # live human decision fights it, and a child told to answer comments may have
    # to bring the branch current, which rebase_hold forbids. Absent any of that,
    # and with a pool to route to, the comments become work.
    why=""
    [ -n "$fix_branch" ] || why="the PR head branch is unresolved"
    [ -n "$FIX_POOL" ]   || why="no fix pool is configured"
    is_held "$rhold"        && why="rebase_hold freezes the branch"
    is_held "$hold"         && why="merge_hold is set"
    [ "$routed" = "human" ] && why="the anchor is already routed to a human"
    [ -n "$holding" ]       && why="a sitting is holding it for an operator ruling"
    [ -n "$armed" ]         && why="the anchor is armed to re-dispatch when ready"
    if [ -n "$why" ]; then choice="visit"; else choice="rework"; fi
    CSRC=$(feedback_reviews "$revs_open" "$rwm")
    DISP=""
    if [ "$choice" = "rework" ]; then
      # Same choice as the CONFLICTING arm's `stale-base-dispatch-mode`: the child
      # may have to bring the branch current before it can push a fix, and every
      # branch shape is brought current by MERGE, never a rebase/force-push.
      prepare_mode=merge
      # Deterministic per batch: the same outstanding feedback names the same
      # child, a later batch names a different one. Both halves of the probe
      # matter — a fully stamped hit means this batch was already dispatched and
      # only the watermark write failed, an unstamped hit is an orphan from a
      # pass whose stamp dropped, and re-creating either mints a twin. The title
      # IS that probe's key, so rewording it strands every child in flight under
      # the old one.
      # The issue-comment coordinate joins the key only when there is one, so a PR
      # with no Conversation feedback keeps the exact title a child already in
      # flight was filed under, and only a batch that actually carries an issue
      # comment gets the wider key.
      CTITLE="Address review comments on PR#$num (through review $max_r, comment $max_c)"
      [ "$max_i" -gt 0 ] && CTITLE="Address review comments on PR#$num (through review $max_r, comment $max_c, issue $max_i)"
      CBODY=$(feedback_body "$revs_open" "$cmts_open" "$rwm" "$cwm" "$icmts_raw" "$iwm")
      [ -n "$CBODY" ] || CBODY="Unanswered review feedback on PR#$num (through review $max_r, comment $max_c, issue $max_i). The bodies could not be rendered; read them at $live_url."
      CBODY="## Unanswered review feedback on PR#$num

$live_url — head $head_oid${CSRC:+, review $CSRC}

Answer every item below: a fix, or a reply on the PR saying why not. Post a
reply through $PR_POST (\`reply\` into an inline thread, \`comment\` on the
conversation): it marks the reply as the city's own, and a reply posted any
other way reads as new feedback on the PR. One that asks for a decision you
cannot make is an escalation, never a silent close.

$CBODY"
      if ! ckids=$(bd_list --status="$ALL_STATUSES" --title-contains "$CTITLE"); then
        echo "$PROG: $id — PR#$num comment dedup probe failed; nothing dispatched (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      CFIX=$(printf '%s' "$ckids" | jq -r --arg id "$id" '
        [ .[] | select(((.metadata.anchor_bead // "") | tostring) == $id) | .id ] | .[0] // empty' 2>/dev/null)
      if [ -n "$CFIX" ]; then
        echo "$PROG: $id — PR#$num comment rework $CFIX already covers this batch; re-checking its route before the watermark"
      else
        # Live-only, unlike the batch probe above: a CLOSED orphan would take the
        # stamp and the route, hold nothing, and still let the watermark advance
        # past a comment no one ever read.
        CFIX=$(printf '%s' "$ckids" | jq -r --arg live "$LIVE_STATUSES" '
          ($live | split(",")) as $ls
          | [ .[] | select(((.metadata.anchor_bead // "") | tostring) == "")
                  | ((.status // "open") | tostring | ascii_downcase) as $st
                  | select(($ls | index($st)) != null)
                  | .id ] | .[0] // empty' 2>/dev/null)
        if [ -n "$CFIX" ]; then
          echo "$PROG: $id adopting unstamped comment-rework orphan $CFIX for PR#$num (created by a prior pass whose stamp failed)"
        else
          CFIX=$(printf '%s\n' "$CBODY" | gc bd create "$CTITLE" -t task --body-file - --json 2>/dev/null \
                   | jq -r '.id // empty' 2>/dev/null)
        fi
        if [ -z "$CFIX" ]; then
          echo "$PROG: $id could not file the comment rework for PR#$num; retry next pass" >&2
          skipped=$((skipped + 1)); continue
        fi
        CSRCSET=(); [ -z "$CSRC" ] || CSRCSET=(--set-metadata "source_review=$CSRC")
        gc bd update "$CFIX" \
          --set-metadata task_kind=rework \
          --set-metadata anchor_bead="$id" \
          --set-metadata branch="$fix_branch" \
          --set-metadata target="$base" \
          --set-metadata rejection_reason="Review feedback on PR#$num is unanswered at head $head_oid. This bead's description carries it verbatim; $live_url is the live copy. Answer every item — a fix, or a reply on the PR saying why not, posted through $PR_POST so it is not read back as new feedback — then push to '$fix_branch'. Do NOT open a new PR: this reworks PR#$num. A comment asking for a decision you cannot make is an escalation, never a silent close." \
          ${CSRCSET[@]+"${CSRCSET[@]}"} \
          --set-metadata prepare_mode="$prepare_mode" \
          --set-metadata merge_strategy=mr \
          --set-metadata existing_pr="$live_url" \
          --set-metadata pr_url="$live_url" \
          --set-metadata pr_number="$num" >/dev/null 2>&1 \
          || echo "$PROG: WARN comment rework $CFIX created but not fully stamped; route it to $FIX_POOL by hand" >&2
        gc bd dep "$CFIX" --blocks "$id" >/dev/null 2>&1 \
          || echo "$PROG: WARN could not attach comment rework $CFIX as a blocks-dep of $id" >&2
        # The comment-rework child now exists (created or adopted, then stamped);
        # drop the per-pass bd_list cache so the title/anchor_bead dedup probe reads
        # it on the next anchor and does not twin it. The gc bd show reads below do
        # not repopulate the cache. No-op outside a reconcile pass.
        bd_cache_clear
        # anchor_bead is the dedup key the probe above reads; an unstamped child
        # is invisible to it, so routing one would twin on the next pass.
        agot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.anchor_bead // empty')
        if [ "$agot" != "$id" ]; then
          echo "$PROG: WARN comment rework $CFIX did not record anchor_bead=$id; left unrouted (retry next pass)" >&2
          skipped=$((skipped + 1)); continue
        fi
      fi
      # An unrouted child still holds the merge through its blocks edge, but no
      # pool can claim it, and the mark would retire the only signal that could
      # re-file it. A CLOSED child is already dispositioned, so refusing on one
      # could never converge. Only a definitively closed status skips the check;
      # an unreadable one still demands both stamps.
      cst=$(gc bd show "$CFIX" --json 2>/dev/null | scrub \
        | jq -r '(.[0].status // "") | tostring | ascii_downcase' 2>/dev/null)
      if [ "$cst" != "closed" ]; then
        # prepare_mode is stamped merge and the resume path defaults to merge, so a
        # child routed without it still merges rather than rewriting. Re-stamp for
        # metadata completeness rather than refuse: a batch already covered skips
        # the create block, so a child stranded by a dropped stamp could take one
        # nowhere else.
        mgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.prepare_mode // empty' 2>/dev/null)
        if [ "$mgot" != "$prepare_mode" ]; then
          gc bd update "$CFIX" --set-metadata prepare_mode="$prepare_mode" >/dev/null 2>&1 || true
          mgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.prepare_mode // empty' 2>/dev/null)
        fi
        if [ "$mgot" != "$prepare_mode" ]; then
          echo "$PROG: WARN comment rework $CFIX did not record prepare_mode=$prepare_mode; left unrouted and NOT watermarking (route only a fully-stamped child)" >&2
          skipped=$((skipped + 1)); continue
        fi
        # task_kind=rework is the role marker. The create-path read-back proves
        # anchor_bead (the dedup key), but never this, and a recheck of a child
        # that already covers the batch skips that read-back entirely — so a
        # create that half-landed without task_kind would leave a routed comment
        # rework on the anchor's own branch with no marker. anchor_bead is already
        # proven (it is how this child was found); re-stamp task_kind the same way
        # as the mode, before the watermark advances past the comments it answers.
        kgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.task_kind // empty' 2>/dev/null)
        if [ "$kgot" != "rework" ]; then
          gc bd update "$CFIX" --set-metadata task_kind=rework >/dev/null 2>&1 || true
          kgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.task_kind // empty' 2>/dev/null)
        fi
        if [ "$kgot" != "rework" ]; then
          echo "$PROG: WARN comment rework $CFIX did not record task_kind=rework; left unmarked and NOT watermarking" >&2
          skipped=$((skipped + 1)); continue
        fi
        rgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata["gc.routed_to"] // empty' 2>/dev/null)
        if [ "$rgot" != "$FIX_POOL" ]; then
          gc bd update "$CFIX" --set-metadata gc.routed_to="$FIX_POOL" >/dev/null 2>&1 || true
          rgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata["gc.routed_to"] // empty' 2>/dev/null)
        fi
        if [ "$rgot" != "$FIX_POOL" ]; then
          echo "$PROG: WARN comment rework $CFIX is NOT routed to $FIX_POOL; NOT watermarking (an unclaimable child with the mark moved past its comments is the silence this arm exists to stop)" >&2
          skipped=$((skipped + 1)); continue
        fi
        gc session wake "$FIX_POOL" >/dev/null 2>&1 || true
      fi
      DISP="rework:$CFIX"
    else
      # Same conditional coordinate as the child's title: a batch with no issue
      # comment keeps the key an open visit was filed under.
      VKEY="pr-comments.$num.$max_r.$max_c"
      [ "$max_i" -gt 0 ] && VKEY="pr-comments.$num.$max_r.$max_c.$max_i"
      escalate "$id" "$VKEY" \
        "PR#$num ($live_url) carries review feedback nothing has answered (highest: review $max_r, comment $max_c, issue $max_i; answered through review $rwm, comment $cwm, issue $iwm${CSRC:+; reviews $CSRC}), and the city cannot route work for it because $why. Answer it on the PR, file the rework by hand, or close this visit once it is addressed — the merge is held until then."
      VID=$(visit_for "$id" "$VKEY") || VID=""
      if [ -z "$VID" ]; then
        echo "$PROG: $id — PR#$num has unanswered comments but no visit could be filed or found; NOTHING dispositioned (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      # A blocks edge would close a cycle: escalate.sh already files the visit
      # DEPENDING on its subject (tracks), so an edge back is a two-node loop bd
      # refuses. pr_number is what merge.sh's in-flight-holder probe reads, and
      # it holds the merge until a human closes the visit. anchor_bead is safe
      # beside it — every consumer of that key filters on task_kind=review.
      gc bd update "$VID" \
        --set-metadata anchor_bead="$id" \
        --set-metadata pr_url="$live_url" \
        --set-metadata pr_number="$num" >/dev/null 2>&1 \
        || echo "$PROG: WARN visit $VID not stamped with PR#$num; it will NOT hold the merge — stamp it by hand" >&2
      vgot=$(gc bd show "$VID" --json 2>/dev/null | scrub | jq -r '.[0].metadata.pr_number // empty')
      if [ "$vgot" != "$num" ]; then
        echo "$PROG: WARN visit $VID did not record pr_number=$num; NOT watermarking (a mark past an unheld comment is the silence this arm exists to stop)" >&2
        skipped=$((skipped + 1)); continue
      fi
      DISP="visit:$VID"
    fi

    # --- operator feedback ensures a validation pass on the anchor ---------------
    # The batch just routed to a fix or a visit above; it also ensures a live
    # check_name=human validation pass on the anchor. A human feedback batch is
    # review the branch has never been answered against, so it enters the graph
    # the way a reviewer's findings do: gate-ensure.sh's quiescence reads the open
    # pass and holds a fresh whole-diff review off the anchor while the validator
    # rules the batch, so the batch buys no re-review of its own
    # (specs/tk-ztapg/review-cycle-architecture.md, "What moves a lane backwards").
    # This arm does not touch an operator's own hold.
    #
    # The pass is a task_kind=validation bead anchored to $id — the shape
    # gate-ensure.sh's open_validation_pass reads — carrying check_name=human and
    # the head the batch was produced at. check_name is the lane the validator
    # rules: mol-validate selects findings by finding.lane == check_name, and
    # review-outcome.sh backs or supersedes that one exact lane. A human batch's
    # findings carry finding.lane=human, so the pass names human. The whole
    # check_set is wrong here: a multi-lane value like correctness,arch is one synthetic
    # lane no finding carries and no anchor declares, so the validator would match
    # no findings and back a lane that does not exist. It is left unrouted: a
    # validating lane is dispatched to mol-validate by gate-ensure.sh, so the bead
    # is opened here and armed there. The dedup is the live
    # human-lane pass: it selects a task_kind=validation bead carrying
    # check_name=human, not any validation bead. gate-ensure's quiescence
    # (open_validation_pass) reads any lane, so a correctness pass on this anchor holds
    # the merge but never rules the human findings; counting it here would
    # watermark the batch with no human-lane pass behind it. One live human pass
    # rules every open human finding on the anchor, so a second reconcile over the
    # same anchor reuses that pass and opens none. Opening it fails closed like the routing
    # above: a probe or write that cannot complete warns and skips the watermark so
    # the batch retries next pass, and the routing's own dedup re-adopts the child
    # it already filed rather than twinning it. The routing above already holds the
    # merge, so the retry costs nothing.
    if ! vpass_rows=$(bd_list --metadata-field anchor_bead="$id" --status="$LIVE_STATUSES"); then
      echo "$PROG: WARN $id — PR#$num validation-pass probe unreadable; nothing opened or watermarked (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    else
      # The batch coordinate the title, note and log lines render, widened to name
      # the Conversation-tab comment only when the batch carries one — the same
      # conditional shape the comment-rework arm's title uses.
      vcoord="review $max_r, comment $max_c"
      [ "$max_i" -gt 0 ] && vcoord="$vcoord, issue $max_i"
      VPASS=$(printf '%s' "$vpass_rows" | jq -r '
        [ .[] | select(((.metadata.task_kind // "") | tostring) == "validation")
              | select(((.metadata.check_name // "") | tostring) == "human") | .id ] | .[0] // empty' 2>/dev/null)
      if [ -n "$VPASS" ]; then
        echo "$PROG: $id — PR#$num already carries a human-lane validation pass $VPASS; re-checking its shape before watermarking"
      else
        vtitle="Validate PR#$num feedback (through $vcoord)"
        # Reclaim a same-anchor half-stamped pass before minting. A prior pass may
        # have created THIS anchor's human pass and had the task_kind or check_name
        # half of its one shaping write drop; the bead then carries anchor_bead=$id
        # — so the probe above lists it — but the human-lane selector skips it
        # because task_kind is not "validation", or check_name is unset. It is this
        # anchor's pass by title, distinct from a real correctness-lane pass (check_name
        # set to another lane), so reclaim only a title match whose lane is unset or
        # already human and let the shape gate below repair the missing key, rather
        # than mint a twin that would double-block the anchor.
        VPASS=$(printf '%s' "$vpass_rows" | jq -r --arg t "Validate PR#$num feedback" '
          [ .[] | select(((.title // "") | tostring) | startswith($t))
                | select(((.metadata.check_name // "") | tostring) as $l | $l == "" or $l == "human")
                | .id ] | .[0] // empty' 2>/dev/null)
        if [ -n "$VPASS" ]; then
          echo "$PROG: $id reclaiming half-stamped validation pass $VPASS for PR#$num (a prior pass's shaping write half-landed)"
        else
          # A prior pass that created the bead but failed to stamp anchor_bead left
          # an orphan the probe above cannot see; adopt it by title rather than mint
          # a twin. Live-only: a closed orphan is already dispositioned.
          if vorphans=$(bd_list --title-contains "$vtitle" --status="$LIVE_STATUSES"); then
            VPASS=$(printf '%s' "$vorphans" | jq -r '
              [ .[] | select(((.metadata.anchor_bead // "") | tostring) == "") | .id ] | .[0] // empty' 2>/dev/null)
          fi
          if [ -n "$VPASS" ]; then
            echo "$PROG: $id adopting unstamped validation-pass orphan $VPASS for PR#$num"
          else
            vbody=""
            [ -x "$VALIDATE_BODY" ] && vbody=$("$VALIDATE_BODY" --note "This validation pass rules a human feedback batch on PR#$num (through $vcoord; $live_url). The findings to rule are the open task_kind=finding beads on anchor $id." 2>/dev/null) || vbody=""
            if [ -n "$vbody" ]; then
              VPASS=$(printf '%s' "$vbody" | gc bd create "$vtitle" -t task --body-file - --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
            else
              echo "$PROG: WARN validate-dispatch note unavailable ($VALIDATE_BODY); opening a title-only validation pass" >&2
              VPASS=$(gc bd create "$vtitle" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
            fi
          fi
        fi
        if [ -z "$VPASS" ]; then
          echo "$PROG: WARN $id — PR#$num could not open a validation pass; nothing watermarked (retry next pass)" >&2
          skipped=$((skipped + 1)); continue
        fi
      fi
      # Watermark only once the pass the validator will actually consume carries
      # the shape mol-validate reads: task_kind=validation is the key the
      # validator-path selectors read — gate-ensure's open_validation_pass keys its
      # quiescence on it, and gate-ensure's validation-pass dispatch selects the
      # passes it slings mol-validate onto by it — anchor_bead scopes the findings,
      # check_name is the lane it selects them by (a missing one defaults to correctness,
      # so the human findings would go unruled), and reviewed_oid is the pin it
      # needs to back the lane. The one write below stamps all four together, so any
      # can be the half that drops; a pass missing task_kind still matches an
      # anchor_bead probe and still blocks the anchor by its edge, yet
      # open_validation_pass cannot see it, so it would watermark the batch behind a
      # pass no validator-path selector reads. Every source of $VPASS reaches this
      # one check — the probe's existing pass, a reclaimed half-stamped pass, an
      # adopted orphan, a freshly minted bead — so it is re-read and repaired here,
      # not trusted on the probe's word. Repair a field the pass lacks, read them
      # all back, and skip the watermark unless each holds — a proxy check on
      # anchor_bead alone would mark the batch handled behind a pass the validator
      # cannot rule. Skipping holds the batch to retry; the rework child is already
      # filed, so it costs nothing. reviewed_oid is only ADDED when absent, never
      # overwritten: head_oid is the live PR head, not a per-batch constant, and a
      # live human pass adopted across batches keeps the head it was opened at so a
      # validator mid-rule does not have its back-lane pin moved under it.
      vmeta=$(gc bd show "$VPASS" --json 2>/dev/null | scrub)
      v_kind=$(printf '%s' "$vmeta" | jq -r '.[0].metadata.task_kind // empty')
      v_anchor=$(printf '%s' "$vmeta" | jq -r '.[0].metadata.anchor_bead // empty')
      v_lane=$(printf '%s' "$vmeta" | jq -r '.[0].metadata.check_name // empty')
      v_oid=$(printf '%s' "$vmeta" | jq -r '.[0].metadata.reviewed_oid // empty')
      vfix=()
      [ "$v_kind" != "validation" ] && vfix+=(--set-metadata task_kind=validation)
      [ "$v_anchor" != "$id" ] && vfix+=(--set-metadata anchor_bead="$id")
      [ "$v_lane" != "human" ] && vfix+=(--set-metadata check_name=human)
      [ -z "$v_oid" ] && [ -n "$head_oid" ] && vfix+=(--set-metadata reviewed_oid="$head_oid")
      if [ "${#vfix[@]}" -gt 0 ]; then
        gc bd update "$VPASS" "${vfix[@]}" >/dev/null 2>&1
        vmeta=$(gc bd show "$VPASS" --json 2>/dev/null | scrub)
        v_kind=$(printf '%s' "$vmeta" | jq -r '.[0].metadata.task_kind // empty')
        v_anchor=$(printf '%s' "$vmeta" | jq -r '.[0].metadata.anchor_bead // empty')
        v_lane=$(printf '%s' "$vmeta" | jq -r '.[0].metadata.check_name // empty')
        v_oid=$(printf '%s' "$vmeta" | jq -r '.[0].metadata.reviewed_oid // empty')
      fi
      # The validation pass was created/adopted and its shape repaired above; drop
      # the per-pass bd_list cache so a later anchor's anchor_bead/title probe reads
      # it and does not twin it. The reads above are gc bd show, which does not
      # repopulate the cache. No-op outside a reconcile pass.
      bd_cache_clear
      if [ "$v_kind" != "validation" ] || [ "$v_anchor" != "$id" ] || [ "$v_lane" != "human" ] || { [ -n "$head_oid" ] && [ -z "$v_oid" ]; }; then
        echo "$PROG: WARN $id — PR#$num validation pass $VPASS did not record the batch shape (want task_kind=validation anchor_bead=$id check_name=human${head_oid:+ reviewed_oid set}; got task_kind=${v_kind:-<absent>} anchor_bead=${v_anchor:-<absent>} check_name=${v_lane:-<absent>} reviewed_oid=${v_oid:-<absent>}); nothing watermarked, the batch retries next pass" >&2
        skipped=$((skipped + 1)); continue
      fi
      echo "$PROG: $id — PR#$num human-lane validation pass $VPASS carries the feedback batch shape ($vcoord)"
      # The pass must HOLD the anchor, not merely sit beside it. merge.sh reads
      # every live blocks blocker of the anchor into its in-flight hold and bd
      # refuses to close a blocked anchor, so a blocks edge from the pass keeps an
      # already-green anchor from merging or closing while the batch is unruled;
      # the validator releases it by closing the pass. The interlock is an edge,
      # never a metadata string (specs/tk-ztapg/review-cycle-architecture.md,
      # "Findings"): lane-state.sh, merge.sh and pr-open.sh do not read validation
      # beads, so absent the edge the pass holds nothing. Idempotent — a re-adopted
      # or already-open pass keeps its one edge — and fail-closed like the
      # anchor_bead stamp above: an edge that cannot be attached and read back is a
      # pass that holds nothing, so warn and skip the watermark to retry rather
      # than mark past a batch nothing holds.
      if ! vblk=$(gc bd dep list "$id" --direction=down -t blocks --json 2>/dev/null | scrub) \
         || ! printf '%s' "$vblk" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo "$PROG: WARN $id — PR#$num validation-pass blocker probe unreadable; nothing watermarked (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      if ! printf '%s' "$vblk" | jq -e --arg v "$VPASS" 'any(.[]?; (.id // "") == $v)' >/dev/null 2>&1; then
        if ! gc bd dep "$VPASS" --blocks "$id" >/dev/null 2>&1 \
           || ! gc bd dep list "$id" --direction=down -t blocks --json 2>/dev/null | scrub \
                | jq -e --arg v "$VPASS" 'any(.[]?; (.id // "") == $v)' >/dev/null 2>&1; then
          echo "$PROG: WARN $id — PR#$num validation pass $VPASS did not record a blocks edge on the anchor; nothing watermarked (retry next pass)" >&2
          skipped=$((skipped + 1)); continue
        fi
      fi
    fi

    # --- the batch's items become findings the validator rules ------------------
    # A human comment is a finding like a reviewer's, so it enters the graph the
    # same way (specs/tk-ztapg/review-cycle-architecture.md, "Findings"): one
    # task_kind=finding bead per item, finding.lane=human, finding.source the login
    # that raised it. The validation pass opened above rules them, and a pass with
    # no finding set to rule on would stall, so the findings and the pass are one
    # behaviour: neither the findings nor the watermark land unless every item
    # filed. finding.sh dedups on lane plus a normalized locus and message, so a
    # retry after a mid-batch failure re-adopts the findings already filed rather
    # than twinning them. A batch routed to a rework child records that child on
    # each finding (finding.fix_unit), the one fix unit a must-fix ruling may hang
    # the finding's close-ordering edge on. The anchor's other rework children —
    # an earlier batch's, a stale-base merge-in, a red-check rework — never carried
    # this batch, and a finding wired to one closes as answered when it lands. A
    # finding a later batch re-raises records that batch's child instead.
    FFU=(); case "$DISP" in rework:?*) FFU=(--fix-unit "${DISP#rework:}") ;; esac
    if [ ! -x "$FINDING" ]; then
      echo "$PROG: WARN $id — PR#$num finding tool not found ($FINDING); NOT watermarking (the batch has no findings for the validator to rule)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if ! frecs=$(feedback_findings "$revs_open" "$cmts_open" "$rwm" "$cwm" "$icmts_raw" "$iwm") \
       || ! printf '%s' "$frecs" | jq -e 'type == "array"' >/dev/null 2>&1; then
      echo "$PROG: WARN $id — PR#$num could not render the feedback findings; NOT watermarking (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    ffail=""
    while IFS= read -r frec; do
      [ -n "$frec" ] || continue
      flogin=$(printf '%s' "$frec" | jq -r '.login // "?"')
      flocus=$(printf '%s' "$frec" | jq -r '.locus // empty')
      fmsg=$(printf '%s' "$frec" | jq -r '.message // empty')
      fcid=$(printf '%s' "$frec" | jq -r '(.comment_id // "") | tostring')
      frid=$(printf '%s' "$frec" | jq -r '(.review_id // "") | tostring')
      [ -n "$flocus" ] && [ -n "$fmsg" ] || continue
      if fid=$("$FINDING" upsert --anchor "$id" --lane human --source "human:$flogin" --locus "$flocus" --message "$fmsg" ${FFU[@]+"${FFU[@]}"} 2>/dev/null) && [ -n "$fid" ]; then
        # Record which GitHub row and review raised it. finding.comment_id lets the
        # write-back post a declined finding's owed reply into that thread;
        # finding.review_id groups the finding under its review, so the write-back
        # dismisses that review once all of its findings clear. Best-effort: a
        # missing comment id drops the decline reply back to a PR-level answer and a
        # missing review id drops only this review's auto-dismissal, never the merge
        # hold, so neither gates the batch the way the finding filing above does.
        case "$fcid" in ''|0) : ;; *) gc bd update "$fid" --set-metadata finding.comment_id="$fcid" >/dev/null 2>&1 || true ;; esac
        case "$frid" in ''|0) : ;; *) gc bd update "$fid" --set-metadata finding.review_id="$frid" >/dev/null 2>&1 || true ;; esac
      else
        ffail=1; break
      fi
    done < <(printf '%s' "$frecs" | jq -c '.[]?')
    if [ -n "$ffail" ]; then
      echo "$PROG: WARN $id — PR#$num could not file every feedback finding; NOT watermarking (retry next pass; finding.sh re-adopts the ones already filed)" >&2
      skipped=$((skipped + 1)); continue
    fi
    # The rework child's edge onto a newly filed finding is NOT hung here. The
    # finding is still unvalidated, and a fix unit that blocked one the validator
    # later declines would refuse that finding's close (bd will not close a
    # blocked issue) and stall the validator's triage. The close-ordering edge
    # onto a finding is hung as the validator rules it must-fix (finding.sh
    # set-disposition, from the finding.fix_unit recorded above), so the fix unit
    # blocks only the findings it must answer. A re-raised finding already ruled
    # must-fix is not ruled again, so upsert hangs this batch's child onto it as
    # it re-adopts it. A visit-routed batch has no fix unit and a human answers
    # it. The child's own blocks edge onto the anchor, wired at dispatch, is what
    # holds the merge in the meantime
    # (specs/tk-ztapg/review-cycle-architecture.md, "The fix unit").

    # The batch boundary goes down WITH the disposition that names it. Derived
    # later, off the disposition, it can be lost: a pass that exits after this
    # stamp leaves the next one free to route a newer batch, and with no record
    # of this one the write-back reads a single range running back to zero and
    # answers these comments from the newer bead. The floor is the mark this
    # transition replaces, which is exactly the span this disposition covers.
    NBATCH=$(jq -rn --arg batch "$obatch" --arg disp "$DISP" \
      --argjson lo "$cwm" --argjson hi "$max_c" "$WB_LEDGER_JQ"'
      $batch | ledger_records | ledger_route($disp; $lo; $hi) | ledger_string' 2>/dev/null) || NBATCH=""
    if [ -z "$NBATCH" ]; then
      echo "$PROG: WARN $id — PR#$num comment batch history is unreadable; NOT watermarking (a mark past a batch whose range was never recorded lets a later disposition answer these comments)" >&2
      skipped=$((skipped + 1)); continue
    fi
    # The review bodies and the Conversation comments keep ledgers of their own,
    # written in this same transition. Only a batch that carries comments in a
    # space adds a record there, and the write-back marks no comment it cannot
    # place in a batch.
    xbatch=()
    if ! NRBATCH=$(ledger_route_space "$orbatch" "$DISP" "$rwm" "$max_r") \
       || ! NIBATCH=$(ledger_route_space "$oibatch" "$DISP" "$iwm" "$max_i"); then
      echo "$PROG: WARN $id — PR#$num review or Conversation batch history is unreadable; NOT watermarking (a mark past a batch whose range was never recorded lets a later disposition answer these comments)" >&2
      skipped=$((skipped + 1)); continue
    fi
    [ "$NRBATCH" = "$orbatch" ] || xbatch+=(--set "pr_review_batch=$NRBATCH")
    [ "$NIBATCH" = "$oibatch" ] || xbatch+=(--set "pr_issue_comment_batch=$NIBATCH")
    if "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
         --set "pr_comment_watermark=$max_c" --set "pr_review_watermark=$max_r" \
         --set "pr_issue_comment_watermark=$max_i" \
         --set "pr_comment_batch=$NBATCH" ${xbatch[@]+"${xbatch[@]}"} \
         --set "pr_comment_disposition=$DISP" >/dev/null; then
      answered=$((answered + 1))
      echo "$PROG: $id — PR#$num review comments routed to $DISP (watermark: review $max_r, comment $max_c, issue $max_i)"
      # The batch now stands on the anchor as live work: its rework child or
      # visit, its findings, and its validation pass. The label derives from that
      # work, so it is re-derived in the pass that routed the batch.
      reconcile_status_label "$id" "$num"
    else
      echo "$PROG: WARN $id — PR#$num comments routed to $DISP but the watermark did NOT record; the same batch re-dispatches next pass onto $DISP" >&2
      skipped=$((skipped + 1))
    fi
    continue
  fi

  # --route-comments-only stops here: routing operator feedback above is the whole
  # of its mandate. Every arm below (BLOCKED, superseded-CHANGES_REQUESTED
  # dismissal, unengaged review threads, red required checks) and the write-back
  # sweep are the full pass's, which runs after merge.
  [ "$ROUTE_ONLY" != 1 ] || continue

  # --- BLOCKED: escalate an unresolved-thread block; a pending approval is not one ----
  # A PR whose city-side feedback is all routed can still sit on branch
  # protection. The one cause this cadence escalates is an unresolved review
  # thread where thread resolution is required (required_review_thread_resolution),
  # read from the branch's own rules. A missing approving review is NOT escalated:
  # a PR waiting on a required approving review is the operator's own review queue,
  # state the board's review section already surfaces from the posture recorded
  # above (pr_posture), not a conversation a visit should open. Anything else — a
  # rule this cadence does not model, unreadable rules, or a thread count that
  # could not be read — escalates nothing rather than a guess; the next reconcile
  # retries. CHANGES_REQUESTED is active feedback the arms above and the dismissal
  # below own; an operator merge_hold is their own gate; leave both.
  if [ "$merge_state" = "BLOCKED" ] && ! is_held "$hold" && [ "$rd" != "CHANGES_REQUESTED" ]; then
    review_gates_for "$base"
    bcause="unnameable"; bthreads=0
    if [ "$PROT_STATE" = "known" ] && [ "$PROT_THREAD_REQ" = "true" ]; then
      if review_threads_load "$num" && bthreads=$(unresolved_threads); then
        [ "$bthreads" -gt 0 ] && bcause="threads"
      else
        bthreads=0   # unreadable — name no cause on a guess
      fi
    fi
    case "$bcause" in
      threads)
        escalate "$id" "merge-blocked-threads" \
          "PR#$num ($live_url) is BLOCKED by branch protection: $bthreads unresolved review thread(s) must be resolved before it can merge (required_review_thread_resolution is on). Resolve the thread(s), or say why the block should lift."
        echo "$PROG: $id — PR#$num BLOCKED on $bthreads unresolved review thread(s); escalated (merge-blocked-threads)"
        flagged=$((flagged + 1)); continue ;;
    esac
    # bcause=unnameable: the cause is not one this cadence escalates — an unmodeled
    # rule, unreadable rules, or a pending approving review (state, not a visit) —
    # so escalate nothing; merge.sh logs it and the next reconcile retries. Fall
    # through, leaving the dismissal arm below to act if it applies.
  fi

  # --- dismiss our OWN superseded CHANGES_REQUESTED when the check is green -------
  # Only when every declared check reads green but GitHub is still red on our own
  # block, left at a commit other than the live head. Our own is a review
  # gc_city_own reads as the city's: one pr-post.sh marked, or one under our login
  # from before the provenance cutover. An unmarked review under our login after
  # it is feedback, the same as a human's, and is never dismissed here. Skipped
  # when native auto-merge is armed (the dismissal would hand GitHub the landing).
  all_green=1
  # The resolver's exit status is safety-critical here: a crash prints nothing, and
  # an empty check list would leave all_green=1 and dismiss the city's OWN standing
  # CHANGES_REQUESTED block — removing a merge veto — with the checks possibly not
  # green. Fail closed: a resolver that cannot name the checks cannot prove them
  # green, so the block stands.
  if ! dgates=$("$REVIEW_CHECKS" --resolve --check-set "$checkset" --through merge 2>/dev/null); then
    all_green=0; dgates=""
  fi
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    m=$(printf '%s' "$row" | jq -r --arg k "check.$g" '(.metadata[$k] // "") | tostring')
    [ "$m" = "green" ] || all_green=0
  done <<GATES
$dgates
GATES
  if [ "$all_green" = 1 ] && [ -n "$head_oid" ] && [ "$rd" = "CHANGES_REQUESTED" ] \
     && [ -n "$SELF_LOGIN" ]; then
    auto=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json autoMergeRequest 2>/dev/null \
      | jq -r 'if (.autoMergeRequest // null) == null then "off" else "armed" end' 2>/dev/null)
    if [ "$auto" != "off" ]; then
      echo "$PROG: $id — PR#$num has a stale block of ours but native auto-merge is armed (or unreadable); not dismissing"
      skipped=$((skipped + 1)); continue
    fi
    reviews=$(gh_api_origin --paginate "repos/$ORIGIN_REPO/pulls/$num/reviews?per_page=100" \
      --jq '.[]' 2>/dev/null) || reviews=""
    stale_rid=$(printf '%s' "$reviews" | jq -sr --arg self "$SELF_LOGIN" --arg since "$PSINCE" \
      --arg head "$head_oid" "$CITY_OWN_DEF"'
      [ .[] | select(gc_city_own($self; $since))
        | select(.state == "CHANGES_REQUESTED")
        | select((.commit_id // "") != $head) | (.id // empty) ] | .[0] // empty' 2>/dev/null)
    if [ -n "$stale_rid" ]; then
      # Record signoff_dismissed FIRST and read it back: the dismissal cannot be
      # undone, and the marker is its record on the anchor, so a dismissal never
      # lands unrecorded.
      gc bd update "$id" --set-metadata signoff_dismissed="$stale_rid@$head_oid" >/dev/null 2>&1
      got=$(gc bd show "$id" --json 2>/dev/null | scrub | jq -r '.[0].metadata.signoff_dismissed // empty')
      if [ "$got" != "$stale_rid@$head_oid" ]; then
        echo "$PROG: $id — signoff_dismissed marker did not persist; NOT dismissing review $stale_rid" >&2
        skipped=$((skipped + 1)); continue
      fi
      if gh_api_origin -X PUT "repos/$ORIGIN_REPO/pulls/$num/reviews/$stale_rid/dismissals" \
           -f message="Superseded: checks are green at the live head $head_oid; this block was pinned to a commit that is no longer the head." >/dev/null 2>&1; then
        dismissed_n=$((dismissed_n + 1))
        echo "$PROG: $id — dismissed our own superseded CHANGES_REQUESTED (review $stale_rid) on PR#$num; signoff_dismissed recorded"
      else
        echo "$PROG: $id — dismissal of review $stale_rid failed; marker stays recorded, retry next pass" >&2
        skipped=$((skipped + 1))
      fi
    fi
  fi

  # --- unengaged review-thread findings: the visit the posture hold stands for --
  # The merge-hold itself is the `commented` posture the section above records in
  # the pre-merge pass — merge.sh reads posture off the bead and never reads
  # threads, and this full pass runs after merge. This is the dispatch that hold
  # is for: when the posture pass first read the threads it set UT_COUNT, so file
  # ONE visit and watermark the head. The hold then stands off that open visit
  # until it closes; the watermark keeps a closed visit from re-raising until a
  # new commit. It files a visit, not rework — telling a finding from our own
  # answer well enough to drive an auto-fix loop is arm 7's watermark machinery,
  # and running that off a raw thread read would loop on our own replies.
  if [ -n "$UT_COUNT" ] && [ "$UT_COUNT" -gt 0 ]; then
    UTKEY="pr-unengaged-threads.$num.$head_oid"
    escalate "$id" "$UTKEY" \
      "PR#$num ($live_url) carries $UT_COUNT unresolved review-thread finding(s) that nothing picked up. They were posted under the automation's own login with no city mark, before this PR's provenance cutover (an outside review agent, or an operator-run review), so the comment-routing arm read them as the city's own and the green check triggered no re-review. Answer each on the PR, file rework, or resolve the threads — the merge is held until this visit closes."
    UTVID=$(visit_for "$id" "$UTKEY") || UTVID=""
    if [ -z "$UTVID" ]; then
      echo "$PROG: $id — PR#$num carries $UT_COUNT unengaged review thread(s); posture holds the merge but no visit could be filed (retry next pass)" >&2
      skipped=$((skipped + 1))
    else
      gc bd update "$UTVID" \
        --set-metadata anchor_bead="$id" \
        --set-metadata pr_url="$live_url" \
        --set-metadata pr_number="$num" >/dev/null 2>&1 \
        || echo "$PROG: WARN visit $UTVID not stamped with PR#$num — stamp it by hand" >&2
      utvgot=$(gc bd show "$UTVID" --json 2>/dev/null | scrub | jq -r '.[0].metadata.pr_number // empty')
      if [ "$utvgot" != "$num" ]; then
        echo "$PROG: WARN $id — PR#$num visit $UTVID did not record pr_number; NOT watermarking the head (it re-raises next pass, deduped on the same visit)" >&2
        skipped=$((skipped + 1))
      elif "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
             --set "pr_unengaged_threads=$head_oid" >/dev/null; then
        flagged=$((flagged + 1))
        echo "$PROG: $id — PR#$num has $UT_COUNT unengaged review-thread finding(s); filed visit $UTVID (merge held)"
      else
        echo "$PROG: WARN $id — PR#$num visit $UTVID filed and stamped, but the head watermark did not record; it re-raises next pass (deduped on the same visit)" >&2
      fi
    fi
  fi

  # --- red required check: file ONE rework child --------------------------------
  # Reached only when every arm above waved this anchor through: no conflict, no
  # unanswered feedback, no unresolved-thread block. A required check that has
  # FAILED still holds the merge, so this arm routes it: ONE rework child to fix
  # the failing check(s), deduped so a reconcile every couple of minutes files one.
  #
  # merge.sh holds a merge on the same required set (its UNSTABLE arm), but its
  # `green` test also holds on a PENDING or MISSING check — right for a gate,
  # wrong for a dispatch. A check still running has not failed, and a required
  # context with no run yet cannot be told from one not started; a code-fix
  # rework for either sends a polecat to fix nothing. So this routes on a
  # TERMINAL failure only (a completed check concluded failure, or a status
  # context in state failure/error) and leaves pending/missing to the next pass,
  # which sees the failure once it lands.
  #
  # Two safety rails sit on the dispatch. The attempt cap stops it churning
  # fixers at a genuinely stuck PR: once RC_FIX_ATTEMPT_CAP distinct red heads
  # have each drawn a fixer without the PR reaching green, the anchor is parked
  # to a human instead of dispatching another. The non-code exclusion keeps a
  # code-fixer off a failure no code change can clear — a timeout, a
  # cancellation, a startup failure, an action-required gate, or a deploy/preview
  # platform (matched by name) — which is likewise parked. Both parks write the
  # stand-down this arm already honors, gc.routed_to=human, through lifecycle.sh
  # in one update with the takeaway the board shows as what the person owes, so
  # the next pass stands the anchor down on its own and the fixer is never
  # re-offered.
  RC_FIX_ATTEMPT_CAP=3
  RC_DEPLOY_CHECK_RE="vercel|netlify|deploy"
  case "$merge_state" in
    UNSTABLE|BLOCKED)
      rc_fix_branch="${head_ref:-$branch}"
      rc_why=""
      [ -n "$rc_fix_branch" ] || rc_why="the PR head branch is unresolved"
      [ -n "$FIX_POOL" ]      || rc_why="no fix pool is configured"
      is_held "$rhold"          && rc_why="rebase_hold freezes the branch"
      is_held "$hold"           && rc_why="merge_hold is set"
      [ "$(printf '%s' "$row" | jq -r '(.metadata["gc.routed_to"] // "") | tostring')" = "human" ] \
        && rc_why="the anchor is already routed to a human"
      anchor_decision_held "$id" && rc_why="a sitting holds it for an operator ruling"
      [ -n "$armed" ]           && rc_why="the anchor is armed to re-dispatch when ready"
      # A held or human-steered anchor is theirs; file nothing under it, exactly
      # as the conflict and feedback arms stand down on the same gates. The
      # decision may be filed on the anchor or on the live rework child
      # reconciling its branch; anchor_decision_held reads both.
      if [ -z "$rc_why" ]; then
        required_contexts_for "$base"
        if [ "$REQ_STATE" = "known" ] && [ -n "$REQ_CONTEXTS" ]; then
          rc_rollup=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json statusCheckRollup 2>/dev/null)
          rc_req_json=$(printf '%s\n' "$REQ_CONTEXTS" | jq -Rs 'split("\n") | map(select(length > 0))' 2>/dev/null)
          # One entry per failing required check, tagged { name, url, code }.
          # `failed` is the superset that holds the merge (any terminal failure);
          # `code` narrows it to a genuine code failure a polecat can fix — a
          # conclusion FAILURE, or a status context in state FAILURE/ERROR — and
          # NOT a deploy-type check (matched by name, so a deploy FAILURE reads as
          # non-code too). Everything else failing (timeout, cancellation,
          # startup failure, action-required, deploy) is a non-code cause no code
          # change clears. The split below routes a fixer only when a code
          # failure is present and parks otherwise. A CheckRun carries detailsUrl,
          # a StatusContext targetUrl; either may be absent.
          rc_fail_json=$(printf '%s' "$rc_rollup" | jq -c --argjson req "${rc_req_json:-[]}" --arg deploy "$RC_DEPLOY_CHECK_RE" '
            def name_of: (.name // .context // "");
            def failed:
              if ((.conclusion // "") | tostring | length) > 0
                then ((.conclusion | ascii_upcase) as $c
                      | $c == "FAILURE" or $c == "TIMED_OUT" or $c == "CANCELLED"
                        or $c == "ACTION_REQUIRED" or $c == "STARTUP_FAILURE")
              elif ((.state // "") | tostring | length) > 0
                then ((.state | ascii_upcase) as $s | $s == "FAILURE" or $s == "ERROR")
              else false end;
            def code_failed:
              if ((.conclusion // "") | tostring | length) > 0
                then ((.conclusion | ascii_upcase) == "FAILURE")
              elif ((.state // "") | tostring | length) > 0
                then ((.state | ascii_upcase) as $s | $s == "FAILURE" or $s == "ERROR")
              else false end;
            (.statusCheckRollup // []) as $r
            | [ $req[] as $c
                | ($c | ascii_downcase | test($deploy)) as $isdeploy
                | ( [ $r[] | select(type == "object") | select(name_of == $c) ] ) as $runs
                | ( [ $runs[] | select(failed) ] ) as $bad
                | if ($bad | length) > 0
                  then { name: $c,
                         url: (($bad[0].detailsUrl // $bad[0].targetUrl // "") | tostring),
                         code: ((([ $runs[] | select(code_failed) ] | length) > 0) and ($isdeploy | not)) }
                  else empty end ]' 2>/dev/null)
          rc_nfail=$(printf '%s' "$rc_fail_json" | jq 'length' 2>/dev/null)
          case "$rc_nfail" in ''|*[!0-9]*) rc_nfail=0 ;; esac
          rc_code_json=$(printf '%s' "$rc_fail_json" | jq -c '[ .[] | select(.code) ]' 2>/dev/null)
          rc_ncode=$(printf '%s' "$rc_code_json" | jq 'length' 2>/dev/null)
          case "$rc_ncode" in ''|*[!0-9]*) rc_ncode=0 ;; esac
          # Route only on a positively-read failure: an empty or unreadable rollup
          # is "cannot tell", which stands the anchor down rather than dispatching.
          if [ -n "$rc_rollup" ] && [ -n "$rc_req_json" ] && [ "$rc_nfail" -gt 0 ]; then
            if [ "$rc_ncode" -eq 0 ]; then
              # Non-code exclusion: every failing required check is a cause no
              # code change can clear (timeout, cancellation, startup failure,
              # action-required, or a deploy-type check). Park the anchor to a
              # human rather than send a polecat to fix nothing.
              rc_allnames=$(printf '%s' "$rc_fail_json" | jq -r 'map(.name) | join(" ")' 2>/dev/null)
              if "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
                   --route human \
                   --takeaway "PR#$num has a required check failing for a non-code cause — re-run it or fix the infrastructure, then clear gc.routed_to" >/dev/null; then
                escalate "$id" "pr-fix-noncode.$num" \
                  "PR#$num ($live_url) has failing required check(s) ($rc_allnames) that are non-code causes — a timeout, cancellation, startup failure, or a deploy-type check — which no code change can fix. Parked to a human: re-run the check or fix the infrastructure, then clear gc.routed_to to re-engage the auto-fixer, or merge once it is green."
                flagged=$((flagged + 1))
                echo "$PROG: $id — PR#$num required check(s) failing ($rc_allnames) for a non-code cause; parked to human (no fixer dispatched)"
              else
                echo "$PROG: WARN $id — PR#$num non-code required-check failure, but parking the anchor to human did not land (retry next pass)" >&2
                skipped=$((skipped + 1))
              fi
              continue
            fi
            rc_names=$(printf '%s' "$rc_code_json" | jq -r 'map(.name) | join(" ")' 2>/dev/null)
            rc_urls=$(printf '%s' "$rc_code_json" | jq -r '[ .[] | .url | select(. != "") ] | join(" ")' 2>/dev/null)
            # Dedup like the conflict arm, but keyed on anchor_bead so it also
            # stands down for an in-flight REVIEW child (a re-review that will move
            # the head), not only a rework: any LIVE child of this anchor means
            # work already covers it, and any child (closed included) whose
            # rejection_reason names THIS head means this head was already routed —
            # re-dispatching it would loop on a head nothing moved.
            rc_kids=$(bd_list --metadata-field anchor_bead="$id" --status="$ALL_STATUSES") || {
              echo "$PROG: $id — PR#$num has a red required check but the child probe failed; nothing dispatched (retry next pass)" >&2
              skipped=$((skipped + 1)); continue
            }
            # A strand: MY OWN prior red-check child, open/unclaimed/unrouted at
            # this head, whose route stamp exited 0 without landing. It matches the
            # live dedup below and would veto its own rescue, so exclude it from
            # its own dedup and re-route it instead of twinning.
            rc_stranded=$(printf '%s' "$rc_kids" | jq -r --arg id "$id" --arg h "$head_oid" '
              [ .[] | select(.id != $id)
                | select(((.status // "open") | ascii_downcase) == "open")
                | select(((.assignee // "") | tostring) == "")
                | select(((.metadata["gc.routed_to"] // "") | tostring) == "")
                | select(((.metadata.merge_result // "") | tostring) == "")
                | select(($h != "") and (((.metadata.rejection_reason // "") | tostring) | contains("head " + $h)))
                | .id ] | .[0] // empty' 2>/dev/null)
            rc_dup=$(printf '%s' "$rc_kids" | jq -r --arg id "$id" --arg s "$rc_stranded" --arg h "$head_oid" --arg live "$LIVE_STATUSES" '
              ($live | split(",")) as $ls
              | [ .[] | select(.id != $id) | select(.id != $s)
                  | ((.status // "open") | ascii_downcase) as $st
                  | ((.metadata.rejection_reason // "") | tostring) as $rr
                  | select((($ls | index($st)) != null)
                           or (($h != "") and ($rr | contains("head " + $h))))
                  | .id ] | .[0] // empty' 2>/dev/null)
            if [ -n "$rc_dup" ]; then
              echo "$PROG: $id — PR#$num required check(s) failing ($rc_names); child $rc_dup already covers this head, no new child"
              skipped=$((skipped + 1)); continue
            fi
            # Attempt cap. Each red-check child names the head it was sent to fix
            # twice: in the title it is minted with ("$RC_TITLE required check red
            # at head <oid>") and in its rejection_reason ("... at head <oid>").
            # Two writers unset rejection_reason: resuming a rework
            # (mol-polecat-work's rejected-branch-resume block) and the refinery's
            # landed-on-branch close (mol-refinery-patrol's
            # one-anchor-per-pr-terminal). A child that has been worked keeps its
            # head only in the title, so both are read. The distinct hex heads
            # across this anchor's children (any status), less this head, are the
            # PRIOR attempts. At the cap, stop churning fixers at a stuck PR and
            # park it to a human. A stranded child (rescued below) is this head's
            # attempt whose route failed to land, not a new one, so it is never
            # capped. Nothing lowers the count, so once an anchor reaches the cap
            # every later red head parks it again, including the first pass after
            # a person clears the route.
            RC_TITLE="Fix failing required check(s) on PR#$num:"
            rc_attempts=$(printf '%s' "$rc_kids" | jq -r --arg id "$id" --arg h "$head_oid" --arg t "$RC_TITLE" '
              [ .[] | select(.id != $id)
                | ( ((.title // "") | tostring | select(startswith($t))),
                    ((.metadata.rejection_reason // "") | tostring | select(test("Required check"))) )
                | scan("head ([0-9a-fA-F]{7,40})"; "i") | .[0] | ascii_downcase ]
              | unique | map(select(. != ($h | ascii_downcase))) | length' 2>/dev/null)
            case "$rc_attempts" in ''|*[!0-9]*) rc_attempts=0 ;; esac
            if [ -z "$rc_stranded" ] && [ "$rc_attempts" -ge "$RC_FIX_ATTEMPT_CAP" ]; then
              if "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
                   --route human \
                   --takeaway "PR#$num is still red after $rc_attempts auto-fix attempts — fix the failing check by hand; no more fixers will be sent" >/dev/null; then
                escalate "$id" "pr-fix-capped.$num" \
                  "PR#$num ($live_url) has drawn $rc_attempts auto-fix attempts across successive red heads without reaching green on required check(s) ($rc_names); the attempt cap ($RC_FIX_ATTEMPT_CAP) is reached. Parked to a human rather than dispatch another fixer: take it over and fix the check(s) by hand, or merge once it is green. No further fixer is dispatched for this PR, so clearing gc.routed_to while it is still red parks it again."
                flagged=$((flagged + 1))
                echo "$PROG: $id — PR#$num red-check fix attempts ($rc_attempts) reached the cap ($RC_FIX_ATTEMPT_CAP); parked to human (no new fixer dispatched)"
              else
                echo "$PROG: WARN $id — PR#$num red-check attempt cap reached, but parking the anchor to human did not land (retry next pass)" >&2
                skipped=$((skipped + 1))
              fi
              continue
            fi
            # Same choice as the conflict arm's stale-base-dispatch-mode: a child
            # fixing a red check may first bring the branch current, and every
            # branch shape is brought current by MERGE, never a rebase/force-push.
            rc_prepare=merge
            RC_REASON="Required check(s) failing on PR#$num at head $head_oid: $rc_names.${rc_urls:+ Run log(s): $rc_urls.} Fix the failing check(s) and push to '$rc_fix_branch'. Do NOT open a new PR: this reworks PR#$num."
            reuse=""
            if [ -n "$rc_stranded" ]; then
              reuse="$rc_stranded"
              echo "$PROG: $id re-routing stranded red-check rework $reuse for PR#$num (a prior pass's route stamp did not land)"
            else
              # Adopt a created-but-unstamped orphan (title set, anchor_bead never
              # landed) before minting, or a prior pass twins one per cycle.
              if ! rc_orphans=$(bd_list --status=open --title-contains "$RC_TITLE"); then
                echo "$PROG: $id — PR#$num has a red required check but the orphan probe failed; nothing dispatched (retry next pass)" >&2
                skipped=$((skipped + 1)); continue
              fi
              reuse=$(printf '%s' "$rc_orphans" | jq -r '
                [ .[] | select(((.metadata.anchor_bead // "") | tostring) == "") | .id ] | .[0] // empty' 2>/dev/null)
              [ -n "$reuse" ] && echo "$PROG: $id adopting unstamped red-check rework orphan $reuse for PR#$num (created by a prior pass whose stamp failed)"
            fi
            # Atomic birth (see the conflict arm): form the child fully or not at
            # all, verifying rejection_reason as well as the role marker, and route
            # last so only a complete child becomes claimable.
            RCFIX=$(mint_rework_child "$reuse" "$RC_TITLE required check red at head $head_oid" "$id" "$rc_fix_branch" "$base" \
              "$RC_REASON" "$rc_prepare" "$live_url" "$num")
            if [ -z "$RCFIX" ]; then
              echo "$PROG: $id could not form the red-check rework for PR#$num; retry next pass" >&2
              skipped=$((skipped + 1)); continue
            fi
            gc bd update "$RCFIX" --set-metadata gc.routed_to="$FIX_POOL" >/dev/null 2>&1 || true
            rc_rgot=$(gc bd show "$RCFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata["gc.routed_to"] // empty')
            if [ "$rc_rgot" != "$FIX_POOL" ]; then
              echo "$PROG: WARN red-check rework $RCFIX formed but not routed to $FIX_POOL; left unrouted, the stranded arm re-routes it next pass" >&2
              skipped=$((skipped + 1)); continue
            fi
            gc session wake "$FIX_POOL" >/dev/null 2>&1 || true
            reworked=$((reworked + 1))
            echo "$PROG: $id — PR#$num required check(s) failing ($rc_names); filed $rc_prepare-mode rework $RCFIX routed to $FIX_POOL"
            continue
          fi
        fi
      fi ;;
  esac
done <<ROWS_EOF
$(printf '%s\n' "$first_rows" | awk 'NF { print "first\t" $0 }')
$(printf '%s\n' "$rest_rows" | awk 'NF { print "rest\t" $0 }')
ROWS_EOF
pace_end
if [ -n "$CURSOR$DEADLINE" ]; then
  paced="visited $PACE_VISITED of $(printf '%s' "$ANCHORS" | jq 'length' 2>/dev/null) PR anchors ($first_n needing action first)"
  if [ -n "$PACE_RESUME_AT" ] || [ "$PACE_FIRST_SKIPPED" -gt 0 ]; then
    paced="$paced before the deadline"
    [ -z "$PACE_RESUME_AT" ] || paced="$paced; the next pass resumes at $PACE_RESUME_AT"
    [ "$PACE_FIRST_SKIPPED" -eq 0 ] || paced="$paced; $PACE_FIRST_SKIPPED needing action wait for the next pass"
  fi
  echo "$PROG: $paced"
fi


# --- PR write-back: acknowledge on pickup, reply and resolve on landing --------
# The operator reads the PR, so the PR is where the city answers them.
#
# This sweeps after the dispatch arms rather than inside them, which keeps the
# acknowledgement keyed to durable state instead of to one arm's control flow. A
# comment routed earlier in this same pass is still acknowledged in this pass,
# because the sweep re-reads the anchors. A write that failed is retried by the
# next pass, which an inline one-shot could not be.
#
# pr_comment_disposition is the honesty gate. It is written only once the routing
# has read back, so an anchor carrying it has a bead that really does cover these
# comments. An anchor without one costs a single ledger read and no GitHub call,
# unless its PR is owed a ruled finding's post or answer (below).
# The plan decides over WHOLE threads: it finds the city's own marker in one and
# then asks whether a human has written since. A connection left at its first
# page answers that from a fragment — it can miss a comment the city routed, and
# it can resolve a thread a human replied to past the page boundary. So every
# connection here is read to exhaustion. `gh --paginate` follows exactly one
# cursor, so the reviews and the threads are separate reads rather than one
# nested query, and neither carries a second cursor for it to choose between.
# Every node carries its author, body and creation instant, and a thread comment
# its review's submission: the facts gc_city_own reads to tell the city's own
# post from feedback. A thread comment also names its review, which ties a review
# body to the inline comments it carries.
#
# Those reads cost at least four GitHub calls an anchor, so the sweep is paced
# like the walk above (pace-lib.sh): the same deadline, a rotation on a cursor
# of its own (<cursor>.writeback), and one anchor visited even on a pass whose
# walk spent the deadline. The batch history below is reconciled on every
# anchor ahead of the pacing, because it reads no GitHub.
WB_REVIEWS_QUERY='query($owner:String!,$repo:String!,$num:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$num){
      reviews(first:100,after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{id databaseId state body url author{login} submittedAt createdAt
          reactionGroups{content viewerHasReacted}}}}}}'
# The Conversation tab is a third top-level connection, the same single-cursor
# shape as the reviews read. Its comments carry no thread to resolve, so a review
# body or a Conversation comment is answered by a comment of our own here, which
# links to the one it answers; the bodies are read so a later pass finds the
# mark lines of the answers already posted. A ruled finding whose locus names no
# file in the diff is posted here too, and the marker in its body is how a later
# pass finds it again.
WB_ISSUE_COMMENTS_QUERY='query($owner:String!,$repo:String!,$num:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$num){
      comments(first:100,after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{id databaseId body url author{login} createdAt
          reactionGroups{content viewerHasReacted}}}}}}'
# A thread's own comments stay nested: one read covers every thread short enough
# to fit, which is nearly all of them. Truncation is read off the COUNT rather
# than a nested pageInfo — a thread with more than a page returns exactly a full
# one — so this query holds a single cursor and the top-up below is asked for
# only the threads that need it.
WB_THREADS_QUERY='query($owner:String!,$repo:String!,$num:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$num){
      reviewThreads(first:100,after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{id isResolved viewerCanResolve
          comments(first:100){nodes{id databaseId author{login} body createdAt
            pullRequestReview{databaseId submittedAt}
            reactionGroups{content viewerHasReacted}}}}}}}}'
WB_THREAD_COMMENTS_QUERY='query($id:ID!,$endCursor:String){
  node(id:$id){... on PullRequestReviewThread{
    comments(first:100,after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{id databaseId author{login} body createdAt
        pullRequestReview{databaseId submittedAt}
        reactionGroups{content viewerHasReacted}}}}}}'
# The nested `first:` above, named. A thread that comes back holding this many
# comments is one the top-up has to re-read; change either without the other and
# the long threads quietly stop being paged.
WB_PAGE=100

acked=0; replied=0; resolved=0; posted=0; swapped=0; fposted=0; fanswered=0; wfwrites=0; wfheld=0
# The write-back's replies and answers post through these two: a reply into a
# review thread, and a comment on the PR's Conversation tab. Both go through
# pr-post.sh, which marks each answer as the city's own, so the routing arm never
# reads one back as feedback. The ruled-finding arm below also calls pr-post.sh
# directly, for the two posts whose new comment id it reads back (file-comment,
# comment) and for the edit that answers a Conversation post in place.
wb_thread_reply() { # <thread-id> <body>
  "$PR_POST" reply --host "$ORIGIN_HOST" --thread "$1" --body "$2" >/dev/null 2>&1
}
wb_pr_comment() { # <pr-number> <body>
  "$PR_POST" comment --repo "$ORIGIN_REPO_Q" --pr "$1" --body "$2" >/dev/null 2>&1
}
# Trade a resolved comment's EYES for THUMBS_UP: <node-id>:<add>:<remove>,
# comma-joined, or "-". THUMBS_UP goes on first, so a pass that stops between the
# two writes leaves both reactions on the comment, never neither.
wb_swaps() {
  local sw sid add rm
  [ "${1:--}" != "-" ] || return 0
  for sw in $(printf '%s' "$1" | tr ',' ' '); do
    sid="${sw%%:*}"; add="${sw#*:}"; rm="${add#*:}"; add="${add%%:*}"
    if [ "$add" = 1 ] && ! gh_graphql 'mutation($id:ID!,$c:ReactionContent!){addReaction(input:{subjectId:$id,content:$c}){clientMutationId}}' \
         -f id="$sid" -f c="$WB_RESOLVED_REACTION" >/dev/null; then
      echo "$PROG: $wid — PR#$wnum could not mark $sid resolved; retry next pass" >&2
      continue
    fi
    if [ "$rm" = 1 ] && ! gh_graphql 'mutation($id:ID!,$c:ReactionContent!){removeReaction(input:{subjectId:$id,content:$c}){clientMutationId}}' \
         -f id="$sid" -f c="$WB_REACTION" >/dev/null; then
      echo "$PROG: $wid — PR#$wnum could not retire the pickup reaction on $sid; retry next pass" >&2
      continue
    fi
    swapped=$((swapped + 1))
  done
}
# The early arms answer for the merge arm (--posture-only) or route feedback
# early (--route-comments-only) and write nothing to GitHub; the full pass that
# follows them carries the write-back.
if [ "$POSTURE_ONLY" = 1 ] || [ "$ROUTE_ONLY" = 1 ]; then
  WB_ANCHORS=""
elif ! WB_ANCHORS=$(bd_list --status=open --metadata-field merge_result=pull_request); then
  echo "$PROG: write-back sweep skipped — could not re-read the anchors" >&2
  WB_ANCHORS=""
fi
# The ruled machine findings each anchor still owes its PR, read once for the
# whole sweep: one store-wide read costs what a single anchor's read does, and a
# pass already running against its deadline cannot spend one per open PR. A
# finding is owed a post when it is ruled must-fix or deferred and carries no
# finding.pr_comment, and owed an answer once it has been posted and has closed
# and carries no finding.pr_answered. Each stamp is written only after the
# GitHub write it records, so an anchor whose findings are all settled costs no
# GitHub call. A finding records its locus as the first line of its body
# (finding.sh upsert), and the objection follows it.
WB_FOWED="[]"
if [ -n "$WB_ANCHORS" ] && [ "$WB_ANCHORS" != "[]" ]; then
  if wbf_rows=$(bd_list --metadata-field task_kind=finding --status="$ALL_STATUSES"); then
    wbf_ids=$(printf '%s' "$WB_ANCHORS" | jq -c '[ .[].id ]' 2>/dev/null) || wbf_ids="[]"
    WB_FOWED=$(printf '%s' "$wbf_rows" | jq -c --argjson a "${wbf_ids:-[]}" '
      def m($k): ((.metadata[$k] // "") | tostring);
      [ .[]
        | select(m("task_kind") == "finding")
        | select(m("finding.lane") != "" and m("finding.lane") != "human")
        | m("anchor_bead") as $ab
        | select(($a | index($ab)) != null)
        | m("finding.disposition") as $d
        | (((.status // "open") | tostring | ascii_downcase) == "closed") as $closed
        | (if m("finding.pr_comment") == ""
           then (if $d == "must-fix" or $d == "deferred" then "post" else "" end)
           elif $closed and m("finding.pr_answered") == "" then "answer"
           else "" end) as $act
        | select($act != "")
        | ((.description // "") | tostring) as $desc
        | { act: $act, id: .id, anchor: m("anchor_bead"), lane: m("finding.lane"), disp: $d, closed: $closed,
            locus: ($desc | split("\n")[0] | if startswith("Locus: ") then .[7:] else "" end),
            message: ($desc | if startswith("Locus: ") then sub("^Locus: [^\n]*\n*"; "") else . end
                            | sub("\n*Raised by [^\n]* reviewing anchor [^\n]*$"; "")),
            title: ((.title // "") | tostring | sub("^finding\\[[^]]*\\]: "; "")),
            follow_up: m("finding.follow_up"), reply: m("finding.reply") } ]' 2>/dev/null) || WB_FOWED="[]"
    [ -n "$WB_FOWED" ] || WB_FOWED="[]"
  else
    echo "$PROG: finding write-back skipped — could not read the findings (retry next pass)" >&2
  fi
fi
# A posted finding's comment: who it is from, what it was ruled, and the
# objection in the reviewer's own words, carrying the marker a later pass finds
# it by. $ans is the answer when the finding has already closed: it takes the
# place of what the ruling holds, and its own marker records the finding
# answered, so a finding fixed before its PR opened is never shown as still
# holding the merge.
WB_FINDING_BODY='def clip($n): if length > $n then .[0:$n] + " [truncated]" else . end;
  "**Finding from the \(.lane) review, ruled \(.disp)** (\(.id))\n"
  + (if $ans != "" then "**Outcome:** \($ans)\n"
     elif .disp == "must-fix" then "The merge waits for this to be fixed on the branch.\n"
     elif .disp == "deferred" then "Not fixed in this PR; "
       + (if .follow_up != "" then "follow-up \(.follow_up) carries it.\n" else "it is tracked as follow-up work.\n" end)
     else "" end)
  + (if .locus != "" then "Locus: `" + (.locus | gsub("`"; "")) + "`\n" else "" end)
  + "\n" + ((if .message != "" then .message else .title end) | clip(8000))
  + "\n\n" + $mk + .id + " -->"
  + (if $ans != "" then "\n" + $mk + .id + ":answered -->" else "" end)'
# The answer a closed finding is owed: for a must-fix, the head that carries the
# fix and the fix units that landed it; for a deferral, its follow-up.
WB_FINDING_ANSWER='if .disp == "must-fix" then "Addressed in \($head[0:8]) on this PR"
    + (if $fus != "" then " (\($fus))" else "" end) + "."
  elif .disp == "deferred" then
    (if .reply != "" then .reply
     elif .follow_up != "" then "Deferred: follow-up \(.follow_up) carries this after the merge."
     else "Deferred: it is tracked as follow-up work after the merge." end)
  elif .disp == "declined" then "Declined on review; no change was made."
    + (if .reply != "" then " " + .reply else "" end)
  else "Closed" + (if .disp != "" then " (\(.disp))" else "" end) + "." end'
finding_answer() { # <owed-record-json> <head> — the answer text on stdout; empty = could not compose
  local fus=""
  if [ "$(printf '%s' "$1" | jq -r '.disp // ""' 2>/dev/null)" = "must-fix" ]; then
    # The fix units that answered it are the beads blocking it.
    fus=$(bd_json dep list "$(printf '%s' "$1" | jq -r '.id' 2>/dev/null)" --direction=down -t blocks \
      | jq -r 'if type == "array" then [ .[]? | (.id // empty) ] | join(", ") else "" end' 2>/dev/null)
  fi
  printf '%s' "$1" | jq -r --arg head "$2" --arg fus "$fus" "$WB_FINDING_ANSWER" 2>/dev/null
}
WB_CURSOR="${CURSOR:+$CURSOR.writeback}"
# The anchors the sweep reads GitHub for: those carrying a routed batch, and
# those whose PR is owed a finding post or answer.
wb_fanchors=$(printf '%s' "$WB_FOWED" | jq -c '[ .[].anchor ] | unique' 2>/dev/null) || wb_fanchors="[]"
wb_due=$(printf '%s' "${WB_ANCHORS:-[]}" | jq --argjson fa "${wb_fanchors:-[]}" '
  [ .[]? | select(((.metadata.pr_comment_disposition // "") | tostring) != ""
                  or (.id as $i | ($fa | index($i)) != null)) ] | length' 2>/dev/null)
pace_start "$WB_CURSOR" "$DEADLINE"
pace_seen_start "${WB_CURSOR:+$WB_CURSOR.seen}"
# --- write-back visit order: an anchor with something new to answer first --------
# The sweep owes a write when a batch is routed (the disposition or a watermark
# moves) or when work answering one closes (a rework child, a visit, a finding,
# a validation pass leaves the anchor's live children). Its mark joins the
# disposition, the three watermarks and the live child ids, so an anchor whose
# mark moved since the sweep last visited it goes first, on
# <cursor>.writeback.first, and the rest rotate on <cursor>.writeback.
# <cursor>.writeback.seen holds the marks. A sweep with no marks yet records
# them and puts nothing first; a child list that does not read leaves the sweep
# a plain rotation that records no marks. An anchor with no disposition is here
# only for the ruled findings its PR is owed. It records no mark and rotates
# with the rest, so a backlog of finding posts never queues ahead of an anchor
# whose routed comments moved.
wb_first=""; wb_rest=""; wb_first_n=0
declare -A WB_MARK=()
if [ -n "$WB_CURSOR" ] && [ -n "$WB_ANCHORS" ]; then
  declare -A WB_KIDS=()
  wb_kids_ok=0
  if kid_lines=$(bd_live_children); then
    wb_kids_ok=1
    while IFS=$'\t' read -r ka kids _krw; do
      [ -n "$ka" ] && WB_KIDS["$ka"]="$kids"
    done <<< "$kid_lines"
  else
    echo "$PROG: WARN the anchors' live children did not read; the write-back sweep rotates without putting any anchor first" >&2
  fi
  while IFS=$'\x1f' read -r wcid wcdisp wcfields arow; do
    [ -n "${arow:-}" ] || continue
    grp=rest
    if [ "$wb_kids_ok" = 1 ] && [ -n "$wcdisp" ]; then
      WB_MARK["$wcid"]="$wcdisp|$wcfields|${WB_KIDS[$wcid]-}"
      pace_seen_changed "$wcid" "${WB_MARK[$wcid]}" && grp=first
      [ "$PACE_SEEN_FRESH" != 1 ] || pace_seen_put "$wcid" "${WB_MARK[$wcid]}"
    fi
    if [ "$grp" = first ]; then
      wb_first="$wb_first$arow"$'\n'; wb_first_n=$((wb_first_n + 1))
    else
      wb_rest="$wb_rest$arow"$'\n'
    fi
  done <<WB_SPLIT_EOF
$(printf '%s' "$WB_ANCHORS" | jq -r '
    .[] | . as $row | (.metadata // {}) as $m
    | [ (.id // ""), ($m.pr_comment_disposition // ""),
        ([ $m.pr_comment_watermark, $m.pr_review_watermark, $m.pr_issue_comment_watermark ]
         | map((. // "") | tostring) | join("|")) ]
    | map(tostring | gsub("[\u001f\n]"; " ")) + [ $row | tojson ] | join("\u001f")' 2>/dev/null)
WB_SPLIT_EOF
  wb_first=$(printf '%s' "$wb_first" | pace_order "$PACE_FIRST_CURSOR")
  wb_rest=$(printf '%s' "$wb_rest" | pace_order "$WB_CURSOR")
else
  wb_rest=$(printf '%s' "${WB_ANCHORS:-[]}" | jq -c '.[]?' 2>/dev/null)
fi
while IFS= read -r wtagged; do
  [ -n "${wtagged:-}" ] || continue
  wgroup="${wtagged%%$'\t'*}"
  wrow="${wtagged#*$'\t'}"
  wid=$(printf '%s' "$wrow" | jq -r '.id // empty')
  [ -n "$wid" ] || continue
  disp=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_comment_disposition // "") | tostring')
  wfown=""
  if [ "$WB_FOWED" != "[]" ]; then
    wfown=$(printf '%s' "$WB_FOWED" | jq -c --arg a "$wid" '[ .[] | select(.anchor == $a) ]' 2>/dev/null) || wfown=""
    [ "$wfown" != "[]" ] || wfown=""
  fi
  # An anchor without a disposition has no human batch to acknowledge or answer,
  # so it is here only for the ruled findings its PR is owed, and every arm below
  # that answers a batch stands down on it.
  [ -n "$disp" ] || [ -n "$wfown" ] || continue
  wnum=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_number // "") | tostring')
  case "$wnum" in ''|*[!0-9]*) continue ;; esac
  wcwm=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_comment_watermark // "0") | tostring')
  wrwm=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_review_watermark // "0") | tostring')
  wiwm=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_issue_comment_watermark // "0") | tostring')
  case "$wcwm" in ''|*[!0-9]*) wcwm=0 ;; esac
  case "$wrwm" in ''|*[!0-9]*) wrwm=0 ;; esac
  case "$wiwm" in ''|*[!0-9]*) wiwm=0 ;; esac
  # The same provenance cutover the routing arm read: what it routed as feedback
  # is what this sweep acknowledges and answers. Unrecorded or malformed reads
  # every post under our login as the city's own, as it does there; the shape
  # test is gc_city_cutover's, so the stamp is passed on as found.
  wsince=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_provenance_since // "") | tostring')

  # The watermark is cumulative and pr_comment_disposition holds one batch at a
  # time, so a thread an earlier batch left unresolved still sits at or below the
  # mark. Something routed that thread, so its reaction is honest. No commit of
  # THIS batch answered it, so a reply saying one did is not. The bead that does
  # answer it may not have closed yet, so the batch it covers has to outlive the
  # disposition that named it.
  # The batch ledgers are that history (comment-batch-ledger above). Each record
  # is written by the transition that routes its batch, so the range is durable
  # before any later pass can route over it. What is left here is reconciling
  # the inline ledger: extend the standing record when the mark has moved under
  # the same disposition, and mint one for an anchor whose disposition predates
  # the history, whose single batch runs from zero. The review and Conversation
  # ledgers are read and never reconciled, because only the routing transition
  # knows which of their comments a batch carried; a comment they do not place
  # is acknowledged and never marked. A record is dropped once its batch has
  # nothing left owing, and the newest is kept whatever it owes, because its mark
  # is the next batch's floor. The value is read back before it is trusted, the
  # same shape as signoff_dismissed above, and an anchor whose history did not
  # record reacts and answers nothing. It is written ahead of every GitHub read,
  # so an unreadable PR cannot let a batch pass unobserved and leave the floor
  # behind the mark.
  wbatch=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_comment_batch // "") | tostring')
  wbwant=$(jq -rn --arg batch "$wbatch" --arg disp "$disp" --argjson cwm "$wcwm" "$WB_LEDGER_JQ"'
    ($batch | ledger_records) as $rs
    | $rs | ledger_route($disp; ([ 0, ($rs[] | .hi) ] | max); $cwm) | ledger_string' 2>/dev/null) || wbwant=""
  wrbatch=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_review_batch // "") | tostring')
  wibatch=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_issue_comment_batch // "") | tostring')
  wbatch_ok=1
  if [ -z "$disp" ]; then
    wbatch_ok=0
  elif [ -z "$wbwant" ] || ! jq -n --arg r "$wrbatch" --arg i "$wibatch" "$WB_LEDGER_JQ"'
       [ ($r, $i) | ledger_records ]' >/dev/null 2>&1; then
    wbatch_ok=0
    echo "$PROG: $wid — PR#$wnum comment batch history is unreadable; acknowledging only, nothing replied or resolved this pass" >&2
  elif [ "$wbatch" != "$wbwant" ]; then
    gc bd update "$wid" --set-metadata pr_comment_batch="$wbwant" >/dev/null 2>&1
    wbgot=$(gc bd show "$wid" --json 2>/dev/null | scrub | jq -r '.[0].metadata.pr_comment_batch // empty')
    if [ "$wbgot" != "$wbwant" ]; then
      wbatch_ok=0
      echo "$PROG: $wid — PR#$wnum comment batch range did not record; acknowledging only, nothing replied or resolved this pass" >&2
    fi
  fi

  [ -n "$SELF_LOGIN" ] || {
    echo "$PROG: $wid — PR#$wnum write-back skipped: the acting login is unresolved (every write keys off telling our own comments from a human's)" >&2
    continue
  }
  pace_visit "$wgroup" "$wid" "${WB_MARK[$wid]-}"; case $? in 1) continue ;; 2) break ;; esac
  wbranch=$(printf '%s' "$wrow" | jq -r '.metadata.branch // ""')
  wprurl=$(printf '%s' "$wrow" | jq -r '.metadata.pr_url // ""')

  # Same fail-closed identity read as the dispatch loop: writing to a PR this
  # anchor does not own puts the city's name on a stranger's review thread.
  WPR_JSON=$(gh pr view "$wnum" --repo "$ORIGIN_REPO_Q" \
    --json state,isDraft,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,url 2>/dev/null)
  [ -n "$WPR_JSON" ] || { echo "$PROG: $wid — PR#$wnum view failed; nothing written back (retry next pass)" >&2; continue; }
  wstate=$(printf '%s' "$WPR_JSON" | jq -r '.state // ""')
  wdraft=$(printf '%s' "$WPR_JSON" | jq -r '.isDraft // false')
  whref=$(printf '%s' "$WPR_JSON" | jq -r '.headRefName // ""')
  whead=$(printf '%s' "$WPR_JSON" | jq -r '.headRefOid // ""')
  wurl=$(canon_pr_url "$(printf '%s' "$WPR_JSON" | jq -r '.url // ""')")
  wrepo=$(printf '%s' "$WPR_JSON" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  wcross=$(printf '%s' "$WPR_JSON" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)
  if [ "$(url_repo_q "$wurl")" != "$ORIGIN_REPO_Q" ] \
     || { [ -n "$wprurl" ] && [ "$(canon_pr_url "$wprurl")" != "$wurl" ]; } \
     || [ -z "$wrepo" ] || [ "$wrepo" != "$ORIGIN_REPO" ] || [ "$wcross" != "false" ] \
     || { [ -n "$wbranch" ] && [ "$whref" != "$wbranch" ]; }; then
    echo "$PROG: $wid — PR#$wnum identity did not certify for the write-back; NOTHING written" >&2
    continue
  fi
  [ "$wstate" = "OPEN" ] || continue
  [ "$wdraft" != "true" ] || continue

  # What answers each batch, and has it closed? Every record is asked for
  # itself, so a batch superseded before its bead closed is still answered by
  # that bead. A rework child answers once it lands. An artifact fix unit (one
  # demo-deliver closed on attach) carries its delivery evidence and lands no
  # commit, so that evidence is what the answer cites; a commit fix unit lands at
  # the PR head. The artifact flag keeps the answer from truncating a URL or
  # claiming a commit the fix never made. A visit answers once the person closes
  # it, and while it is open its comments wait on that person. A bead that does
  # not read back is neither open nor closed, so its comments are acknowledged
  # and nothing more. Answering on the filing rather than the landing would mark
  # a comment resolved while its fix is still unwritten.
  wled='{"c":[],"r":[],"i":[]}'
  if [ "$wbatch_ok" = 1 ]; then
    wbeads='{}'
    while IFS= read -r wd; do
      [ -n "$wd" ] || continue
      wbk="${wd%%:*}"; wbid="${wd#*:}"; wbst="unknown"; wbland=""; wbart=""; wbout=""
      case "$wbk" in rework|visit) : ;; *) wbk="" ;; esac
      if [ -n "$wbk" ] && [ -n "$wbid" ] && wbj=$(gc bd show "$wbid" --json 2>/dev/null | scrub) && [ -n "$wbj" ]; then
        wbst=$(printf '%s' "$wbj" | jq -r --arg live "$LIVE_STATUSES" '
          ((.[0].status // "") | tostring | ascii_downcase) as $s
          | if $s == "closed" then "closed" elif ($live | split(",") | index($s)) != null then "open" else "unknown" end' 2>/dev/null) || wbst="unknown"
        if [ "$wbst" = "closed" ] && [ "$wbk" = "rework" ]; then
          wbland=$(printf '%s' "$wbj" | jq -r '.[0].metadata.artifact_url // ""' 2>/dev/null)
          if [ -n "$wbland" ]; then wbart="1"; else wbland="$whead"; fi
        elif [ "$wbst" = "closed" ]; then
          wbout=$(printf '%s' "$wbj" | jq -r '(.[0].metadata["gc.outcome"] // "") | tostring' 2>/dev/null)
        fi
      fi
      wbnew=$(printf '%s' "$wbeads" | jq -c --arg d "$wd" --arg k "$wbk" --arg b "$wbid" --arg s "$wbst" \
        --arg l "$wbland" --arg a "$wbart" --arg o "$wbout" \
        '.[$d] = { kind: $k, bead: $b, state: $s, landed: $l, artifact: $a, outcome: $o }' 2>/dev/null) \
        && wbeads="$wbnew"
    done <<WB_RECORDS
$(printf '%s;%s;%s' "$wbwant" "$wrbatch" "$wibatch" | tr ';' '\n' | cut -d'|' -f1 | sort -u)
WB_RECORDS
    wled=$(jq -cn --arg c "$wbwant" --arg r "$wrbatch" --arg i "$wibatch" --argjson beads "$wbeads" "$WB_LEDGER_JQ"'
      def placed: map(. + ($beads[.disp] // { kind: "", bead: "", state: "unknown", landed: "", artifact: "", outcome: "" }));
      { c: ($c | ledger_records | placed), r: ($r | ledger_records | placed), i: ($i | ledger_records | placed) }' 2>/dev/null) \
      || wled='{"c":[],"r":[],"i":[]}'
  fi
  # A comment's own finding has the last word over its batch. A finding ruled
  # needs-you waits on a person through its own owed reply. A declined or
  # deferred one is answered by its own owed reply. An open one is not yet
  # validated as resolved. In none of those does the batch's bead answer the
  # comment. A finding names the comment that raised it (finding.comment_id) and,
  # through finding.review_id, the space it sits in: a review body's finding
  # carries its own id there, an inline comment's carries its parent review's, and
  # a Conversation comment's carries none. Findings that cannot be read leave
  # every comment acknowledged and nothing marked this pass. The list reaches the
  # plan as one jq argument, under the OS per-argument limit, so it carries
  # whether a finding owes a reply and never the reply's text.
  wfnd="[]"; wfnd_ok=0
  if [ "$wbatch_ok" = 1 ] && wfrows=$(bd_list --metadata-field anchor_bead="$wid" --status="$ALL_STATUSES"); then
    wfnd=$(printf '%s' "$wfrows" | jq -c '[ .[]?
        | select(((.metadata.task_kind // "") | tostring) == "finding")
        | select(((.metadata["finding.lane"] // "") | tostring) == "human")
        | select(((.metadata["finding.comment_id"] // "") | tostring) != "")
        | { cid: ((.metadata["finding.comment_id"]) | tostring),
            rid: ((.metadata["finding.review_id"] // "") | tostring),
            open: (((.status // "") | tostring | ascii_downcase) != "closed"),
            disp: ((.metadata["finding.disposition"] // "") | tostring),
            reply: (((.metadata["finding.reply"] // "") | tostring) != ""),
            posted: ((.metadata["finding.reply_posted"] // "") | tostring) } ]' 2>/dev/null) \
      && [ -n "$wfnd" ] && wfnd_ok=1 || wfnd="[]"
  fi
  if [ "$wbatch_ok" = 1 ] && [ "$wfnd_ok" != 1 ]; then
    echo "$PROG: $wid — PR#$wnum findings unreadable; acknowledging only, nothing marked this pass" >&2
  fi

  wowner="${ORIGIN_REPO%%/*}"; wname="${ORIGIN_REPO#*/}"
  wrraw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate -f query="$WB_REVIEWS_QUERY" \
    -f owner="$wowner" -f repo="$wname" -F num="$wnum" 2>/dev/null) || wrraw=""
  wtraw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate -f query="$WB_THREADS_QUERY" \
    -f owner="$wowner" -f repo="$wname" -F num="$wnum" 2>/dev/null) || wtraw=""
  wiraw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate -f query="$WB_ISSUE_COMMENTS_QUERY" \
    -f owner="$wowner" -f repo="$wname" -F num="$wnum" 2>/dev/null) || wiraw=""
  if [ -z "$wrraw" ] || [ -z "$wtraw" ] || [ -z "$wiraw" ]; then
    echo "$PROG: $wid — PR#$wnum review threads unreadable; nothing written back (retry next pass)" >&2
    continue
  fi
  # --paginate emits one document per page; slurp all three reads into one view.
  # An empty connection is still a document, so an absent read is a failure, not
  # an empty Conversation, and the guard above holds the pass for it.
  wview=$(printf '%s\n%s\n%s' "$wrraw" "$wtraw" "$wiraw" | scrub | jq -sc '{
      reviews: [ .[].data.repository.pullRequest.reviews.nodes[]? ],
      threads: [ .[].data.repository.pullRequest.reviewThreads.nodes[]? ],
      issue_comments: [ .[].data.repository.pullRequest.comments.nodes[]? ]
    }' 2>/dev/null) || wview=""
  if [ -z "$wview" ] || [ "$wview" = "null" ]; then
    echo "$PROG: $wid — PR#$wnum review threads unreadable; nothing written back (retry next pass)" >&2
    continue
  fi

  # Top up the threads that came back full: those are the ones with more
  # comments than a page, and the plan has to see all of them. A thread that
  # cannot be read to the end leaves the whole anchor to the next pass, because
  # a partial thread is exactly what decides wrongly.
  wtop_ok=1
  while IFS= read -r wtid; do
    [ -n "${wtid:-}" ] || continue
    wcraw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate \
      -f query="$WB_THREAD_COMMENTS_QUERY" -f id="$wtid" 2>/dev/null) || wcraw=""
    wfull=$(printf '%s' "$wcraw" | scrub \
      | jq -sc '[ .[].data.node.comments.nodes[]? ]' 2>/dev/null) || wfull=""
    case "$wfull" in ''|null|'[]') wtop_ok=0; break ;; esac
    wview=$(printf '%s' "$wview" | jq -c --arg t "$wtid" --argjson cs "$wfull" \
      '.threads = [ .threads[] | if .id == $t then .comments = { nodes: $cs } else . end ]' \
      2>/dev/null) || { wtop_ok=0; break; }
    [ -n "$wview" ] || { wtop_ok=0; break; }
  done <<WB_LONG_THREADS
$(printf '%s' "$wview" | jq -r --argjson page "$WB_PAGE" \
   '.threads[]? | select(((.comments.nodes // []) | length) >= $page) | .id' 2>/dev/null)
WB_LONG_THREADS
  if [ "$wtop_ok" != 1 ]; then
    echo "$PROG: $wid — PR#$wnum has a review thread that could not be read to its end; nothing written back (retry next pass)" >&2
    continue
  fi

  # One jq pass decides everything, so the shell below only performs writes.
  # Every comment the city routed (a foreign comment at or below its space's mark)
  # is in one of three states, read from its own finding first and then from its
  # batch:
  #   awaiting  its batch went to a visit that is still open, or its finding was
  #             ruled needs-you and is still open
  #   resolved  its batch's bead closed and its finding, if it has one, closed;
  #             or its finding was declined or deferred and its owed reply answers it
  #   looked    anything else: routed and acknowledged, not yet answered
  # The routing arm leaves out of its batch what the review threads already
  # answered: an inline comment in a resolved thread with a later reply of the
  # city's, and a review body whose every inline comment is one. Such a comment
  # sits inside the batch's range, but the batch's bead never saw it. Unless a
  # finding names it, it stays looked when that later reply is not one of these
  # answers.
  # The lines it emits:
  #   R <node-id>                       react EYES: routed, carrying neither reaction
  #   T <thread> <reply> <why> <body> <swaps>
  #                                     a thread whose routed comments are all
  #                                     resolved. reply is 1 when one of them sits
  #                                     after our last resolved answer, and body is
  #                                     the answer naming the beads that resolved
  #                                     them. why is ok, live (a human answered
  #                                     after us), norights (cannot resolve), or
  #                                     resolved (already, so only answered).
  #   Q <thread> <visit> <body>         the awaiting answer for one open visit
  #   P <mark> <tokens> <swaps> <body>  a Conversation-tab answer for the review
  #                                     bodies and Conversation comments one bead
  #                                     answers, or one open visit holds
  #   S <swap>                          a resolved comment whose answer is posted
  #   K <comment> <review> <issue>      per ledger, the records still owing a write
  # A swap is <node-id>:<add THUMBS_UP>:<remove EYES>, comma-joined. Every field is
  # non-empty, with "-" for none, because read collapses an empty tab field.
  # A comment ABOVE the watermark was never routed and earns nothing: reacting to
  # it would teach the operator that the mark means something it does not. It is
  # still outstanding in the thread it sits in, so that thread waits, and is not
  # answered or resolved over a request nothing has addressed.
  # A thread is answered once every routed comment in it is resolved, in one
  # reply naming each bead that answered by that bead's own landing form. A
  # thread already carrying our answer stays in scope whatever its ids: we
  # claimed it, and a resolve that failed behind a reply still has to be retried.
  # A resolved comment posted after our last answer earns an answer of its own,
  # and anyone who wrote after it otherwise makes the thread live, which is the
  # reason reported for leaving it open. Foreign is the routing arm's own test: a
  # post that is not the city's own (gc_city_own), whoever wrote it. A pass that
  # could not read the findings reacts and marks nothing else.
  wplan=$(printf '%s' "$wview" | jq -r \
    --arg self "$SELF_LOGIN" --arg since "$wsince" --arg reaction "$WB_REACTION" --arg handled "$WB_RESOLVED_REACTION" \
    --arg marker "$WB_MARKER" --arg gres "$WB_GLYPH_RESOLVED" --arg gwait "$WB_GLYPH_AWAITING" \
    --argjson cwm "$wcwm" --argjson rwm "$wrwm" --argjson iwm "$wiwm" \
    --argjson led "$wled" --argjson fnd "$wfnd" --argjson marking "$wfnd_ok" "$CITY_OWN_DEF"'
    def rg($rgs; $c): [ ($rgs // [])[] | select(.content == $c and .viewerHasReacted) ] | length > 0;
    def foreign: gc_city_own($self; $since) | not;
    def ours: ((.author.login // "") == $self) and ((.body // "") | contains($marker));
    # The mark lines one of our answers carries: its state, and on the
    # Conversation tab the tokens of the comments it answers.
    def marks: [ (.body // "") | scan("<!-- gc-writeback-mark:([^ >]+)((?: [ri][0-9]+)*) -->")
      | { st: .[0], toks: (.[1] | split(" ") | map(select(length > 0))) } ];
    # A reply of ours carrying neither a mark line nor a finding line answered
    # the thread it sits in.
    def legacy: ours and (((.body // "") | test("<!-- gc-writeback-(mark|finding):")) | not);
    # A post that answers the comments above it in a resolved thread, as the
    # routing arm reads them: a post of the city (gc_city_own), and not one of
    # our own answers, whose mark lines say what they answered.
    def covers: (foreign | not) and (ours | not);
    def rec_at($s; $d): first($led[$s] | to_entries[] | select(.value.lo < $d and $d <= .value.hi) | .key) // null;
    def fspace: if .rid != "" and .rid == .cid then "r" elif .rid != "" then "c" else "ci" end;
    def finding_at($s; $d): ($d | tostring) as $k
      | first($fnd[] | select(.cid == $k)
              | select(fspace as $f | $f == $s or ($f == "ci" and ($s == "c" or $s == "i")))) // null;
    # $off: the routing arm read this comment as already answered in its threads,
    # so a batch whose range holds it did not carry it unless a finding names it.
    def cstate($s; $d; $off):
      finding_at($s; $d) as $f | rec_at($s; $d) as $ri
      | (if $ri == null then null else $led[$s][$ri] end) as $r
      | if $f != null and $f.open and $f.disp == "needs-you" then { st: "awaiting", by: "finding", ri: $ri }
        elif $f != null and ($f.open | not) and ($f.disp == "declined" or $f.disp == "deferred") and $f.reply
          then { st: "resolved", by: "finding", posted: ($f.posted == "1"), ri: $ri }
        elif $r == null or ($f == null and $off) then { st: "looked", ri: null }
        elif $r.kind == "visit" and $r.state == "open" then { st: "awaiting", by: "batch", visit: $r.bead, ri: $ri }
        elif $r.state == "closed" and ($r.kind == "visit" or $r.landed != "") and ($f == null or ($f.open | not))
          then { st: "resolved", by: "batch", disp: $r.disp, ri: $ri }
        else { st: "looked", ri: $ri } end;
    # One clause per form and landing, naming the beads that answered: a commit fix
    # unit by the head it landed at, an artifact fix unit by its delivered URL, and
    # a visit by its close. A mixed-form answer thus never claims a commit a demo
    # made, nor a demo a commit made.
    def resolved_text($rs):
      [ $rs | unique_by(.disp) | group_by([ .kind, .artifact, .landed ])[]
        | ([ .[].bead ] | join(", ")) as $who | .[0] as $h
        | if $h.kind == "visit"
          then "Resolved: " + ([ .[] | "visit " + .bead + " closed"
                 + (if .outcome != "" then " (" + .outcome + ")" else "" end) ] | join(", ")) + "."
          elif $h.artifact == "1" then "Resolved by the demo delivered on this PR: " + $h.landed + " (" + $who + ")."
          else "Resolved in " + ($h.landed[0:8]) + " on this PR (" + $who + ")." end ]
      | $gres + " " + join(" ");
    def awaiting_text($v): $gwait + " Awaiting a person — visit " + $v + ".";
    def ref: if .url != "" then .url elif .s == "r" then "review " + (.d | tostring) else "comment " + (.d | tostring) end;
    # Add THUMBS_UP unless it is there; remove EYES when it is there, or when an R
    # line adds it this pass (a comment carrying neither reaction).
    def swap: .id + ":" + (if rg(.rgs; $handled) then "0" else "1" end) + ":"
      + (if rg(.rgs; $reaction) or (rg(.rgs; $handled) | not) then "1" else "0" end);
    def swaps: [ .[] | swap | select(endswith(":0:0") | not) ] | if length > 0 then join(",") else "-" end;
    . as $v
    # What the routing arm read as already answered in its threads, and so left
    # out of the batch whose range holds it: an inline comment in a resolved
    # thread with a covering post after it, and a review body whose every inline
    # comment is one.
    | (reduce ($v.threads[] | select(.isResolved // false) | (.comments.nodes // []) as $cs
         | ([ $cs | to_entries[] | select(.value | covers) | .key ] | max) as $last
         | select($last != null) | $cs[0:$last][] | (.databaseId // 0) | select(. > 0))
         as $d ({}; .[$d | tostring] = true)) as $offc
    | ([ $v.threads[] | (.comments.nodes // [])[]
         | { r: ((.pullRequestReview.databaseId // 0) | tostring), d: ((.databaseId // 0) | tostring) }
         | select(.r != "0") ]
       | group_by(.r) | map(select(all(.[]; $offc[.d] == true)) | { key: .[0].r, value: true })
       | from_entries) as $offr
    | ([ $v.issue_comments[] | select(ours) | marks[] ]) as $tm
    | ([ 0, ($led.c[] | .hi) ] | max) as $mark
    | [ $v.threads[] | . as $t | ($t.comments.nodes // []) as $cs
        | ([ $cs | to_entries[] | select(.value | ours)
             | select((.value | marks | any(.st == "resolved")) or (.value | legacy)) | .key ] | max) as $mres
        | (if $mres == null then 0
           else [ $cs | to_entries[] | select(.key > $mres) | select(.value | foreign) ] | length end) as $after
        | ($t.isResolved // false) as $tres | (($t.viewerCanResolve // false) == true) as $canres
        | [ $cs | to_entries[] | .key as $k | .value
            | select(foreign) | select((.databaseId // 0) > 0 and .databaseId <= $cwm)
            | { id, s: "c", d: .databaseId, k: $k, rgs: (.reactionGroups // []),
                mres: $mres, tres: $tres, canres: $canres, after: $after } + cstate("c"; .databaseId; ($offc[.databaseId | tostring] == true)) ] as $fc
        | { id: $t.id, fc: $fc, held: [ $fc[] | select(.ri != null) ], mres: $mres, after: $after,
            res: $tres, canres: $canres, sts: [ $cs[] | select(ours) | marks[] | .st ],
            unr: ([ $cs[] | select(foreign) | select((.databaseId // 0) > $mark) ] | length) } ] as $T
    | ([ $v.reviews[] | select(foreign)
         # the states max_r watermarks (COMMENTED + CHANGES_REQUESTED): a body-only
         # veto advances pr_review_watermark and routes a child, so acknowledge it too
         | select((.state // "") | IN("COMMENTED", "CHANGES_REQUESTED"))
         | select(((.body // "") | gsub("[[:space:]]"; "")) != "")
         | select((.databaseId // 0) > 0 and .databaseId <= $rwm)
         | { id, s: "r", d: .databaseId, url: (.url // ""), rgs: (.reactionGroups // []) } ]
       + [ $v.issue_comments[] | select(foreign)
         | select((.databaseId // 0) > 0 and .databaseId <= $iwm)
         | { id, s: "i", d: .databaseId, url: (.url // ""), rgs: (.reactionGroups // []) } ]
       | map(. + cstate(.s; .d; (.s == "r" and $offr[.d | tostring] == true)) + { tok: (.s + (.d | tostring)) })) as $tops
    | ([ $T[] | .fc[] ] + $tops) as $items
    | def tmarked($st; $tok): any($tm[]; .st == $st and ((.toks | index($tok)) != null));
      # Is the answer that resolves this comment already posted?
      def answered: if .by == "finding" then .posted
        elif .s == "c" then (.mres != null and .k < .mres)
        else tmarked("resolved"; .tok) end;
      def final: .st == "resolved" and answered and rg(.rgs; $handled) and (rg(.rgs; $reaction) | not)
        and (.by == "finding" or .s != "c" or .tres or .after > 0 or (.canres | not));
    ( [ $items[] | select((rg(.rgs; $reaction) or rg(.rgs; $handled)) | not) | "R\t" + .id ]
    + (if $marking != 1 then [] else
        [ $T[] | . as $x
          | [ $x.held[] | select(.st == "resolved" and .by == "batch") ] as $bres
          | (($x.held | length) > 0 and all($x.held[]; .st == "resolved") and ($bres | length) > 0) as $ready
          | (($x.res | not) and ($x.held | length) == 0 and $x.mres != null and ($led.c | length) > 0
             and ($led.c[-1] | .state == "closed" and (.kind == "visit" or .landed != ""))) as $claimed
          | select($ready or $claimed)
          | [ $bres[] | select($x.mres == null or .k > $x.mres) ] as $pend
          | (if ($pend | length) > 0 then 1 else 0 end) as $reply
          # A resolved thread is answered only for a comment no answer covers yet,
          # and is never resolved again.
          | select(($x.res | not) or $reply == 1)
          | (if $reply == 1 then 0 else $x.after end) as $after
          | select($after > 0 or $x.unr == 0)
          | (if $x.res then "resolved" elif $after > 0 then "live"
             elif ($x.canres | not) then "norights" else "ok" end) as $why
          | "T\t" + $x.id + "\t" + ($reply | tostring) + "\t" + $why
            + "\t" + (if $reply == 1 then resolved_text([ $pend[] | $led.c[.ri] ]) else "-" end)
            + "\t" + ($pend | swaps) ]
      + [ $T[] | . as $x
          | [ $x.held[] | select(.st == "awaiting" and .by == "batch") | .visit ] | unique[]
          | select(("awaiting:" + .) as $m | ($x.sts | index($m)) == null)
          | "Q\t" + $x.id + "\t" + . + "\t" + awaiting_text(.) ]
      + [ [ $tops[] | select(.st == "awaiting" and .by == "batch") | select(tmarked("awaiting:" + .visit; .tok) | not) ]
          | group_by(.visit)[]
          | "P\tawaiting:" + .[0].visit + "\t" + ([ .[].tok ] | join(" ")) + "\t-\t"
            + awaiting_text(.[0].visit) + " In reply to " + ([ .[] | ref ] | join(", ")) + "." ]
      + [ [ $tops[] | select(.st == "resolved" and .by == "batch") | select(tmarked("resolved"; .tok) | not) ]
          | group_by(.disp)[]
          | "P\tresolved\t" + ([ .[].tok ] | join(" ")) + "\t" + swaps + "\t"
            + resolved_text([ .[] | $led[.s][.ri] ]) + " In reply to " + ([ .[] | ref ] | join(", ")) + "." ]
      + [ $items[] | select(.st == "resolved") | select(answered) | swap | select(endswith(":0:0") | not) | "S\t" + . ]
      + [ "K\t" + ([ "c", "r", "i" ] | map(. as $s | ($led[$s] | length) as $n
          | if $n == 0 then "-" else
              [ range(0; $n) | . as $k
                | select($k == $n - 1 or any($items[]; .s == $s and .ri == $k and (final | not)))
                | tostring ] | join(",") end) | join("\t")) ]
      end)
    ) | .[]' 2>/dev/null) && wplan_ok=1 || { wplan=""; wplan_ok=0; }

  # The reaction is what shows the operator a comment was picked up. A pass that
  # cannot finish the batch's reactions leaves every answer to the pass that can,
  # so no comment is answered before it is acknowledged.
  wreacts=$(printf '%s' "$wplan" | grep -c '^R	' 2>/dev/null) || wreacts=0
  case "$wreacts" in ''|*[!0-9]*) wreacts=0 ;; esac
  wtees=$(printf '%s' "$wplan" | grep -c '^[TQP]	' 2>/dev/null) || wtees=0
  case "$wtees" in ''|*[!0-9]*) wtees=0 ;; esac
  wack_ok=1
  if [ "$wreacts" -gt "$WB_REACT_CAP" ]; then
    wack_ok=0
    echo "$PROG: $wid — PR#$wnum has $wreacts comments awaiting a pickup reaction; acknowledging $WB_REACT_CAP this pass, the rest on the next" >&2
  fi
  wdone=0
  while IFS="$(printf '\t')" read -r act a1 a2 a3; do
    [ "${act:-}" = "R" ] || continue
    [ "$wdone" -lt "$WB_REACT_CAP" ] || continue
    wdone=$((wdone + 1))
    if gh_graphql 'mutation($id:ID!,$c:ReactionContent!){addReaction(input:{subjectId:$id,content:$c}){clientMutationId}}' \
         -f id="$a1" -f c="$WB_REACTION" >/dev/null; then
      acked=$((acked + 1))
    else
      wack_ok=0
      echo "$PROG: $wid — PR#$wnum could not react to $a1; retry next pass" >&2
    fi
  done <<WB_REACTIONS
$wplan
WB_REACTIONS

  if [ "$wack_ok" != 1 ] && [ "$wtees" -gt 0 ]; then
    echo "$PROG: $wid — PR#$wnum still has comments awaiting their pickup reaction; nothing replied or resolved this pass" >&2
  fi
  # Each answer is posted with the marker and its mark line on lines of their
  # own. A resolved answer's comments trade EYES for THUMBS_UP once it lands.
  while IFS="$(printf '\t')" read -r act a1 a2 a3 a4 a5; do  # a2: reply; a3: ok|live|norights|resolved; a4: body; a5: swaps
    [ "${act:-}" = "T" ] || continue
    [ "$wack_ok" = 1 ] || continue
    if [ "$a2" = "1" ]; then
      if wb_thread_reply "$a1" "$a4
$WB_MARKER
<!-- gc-writeback-mark:resolved -->"; then
        replied=$((replied + 1))
        wb_swaps "$a5"
      else
        echo "$PROG: $wid — PR#$wnum could not reply on thread $a1; NOT resolving it (retry next pass)" >&2
        continue
      fi
    fi
    # A human who answered our reply is still using the thread; resolving it
    # would close a live conversation, which is theirs to end, not ours.
    case "$a3" in
      resolved) continue ;;
      live) echo "$PROG: $wid — PR#$wnum thread $a1 has a reply after ours; left unresolved"; continue ;;
      norights) echo "$PROG: $wid — PR#$wnum thread $a1 is not resolvable by this identity; left unresolved" >&2; continue ;;
    esac
    if gh_graphql 'mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
         -f t="$a1" >/dev/null; then
      resolved=$((resolved + 1))
    else
      echo "$PROG: $wid — PR#$wnum could not resolve thread $a1; retry next pass" >&2
    fi
  done <<WB_PLAN
$wplan
WB_PLAN
  # An awaiting answer leaves its thread open: the person it names still owes
  # the ruling.
  while IFS="$(printf '\t')" read -r act a1 a2 a3; do  # a1: thread; a2: visit; a3: body
    [ "${act:-}" = "Q" ] || continue
    [ "$wack_ok" = 1 ] || continue
    if wb_thread_reply "$a1" "$a3
$WB_MARKER
<!-- gc-writeback-mark:awaiting:$a2 -->"; then
      replied=$((replied + 1))
    else
      echo "$PROG: $wid — PR#$wnum could not post the awaiting answer on thread $a1; retry next pass" >&2
    fi
  done <<WB_AWAITING
$wplan
WB_AWAITING
  while IFS="$(printf '\t')" read -r act a1 a2 a3 a4; do  # a1: mark; a2: tokens; a3: swaps; a4: body
    [ "${act:-}" = "P" ] || continue
    [ "$wack_ok" = 1 ] || continue
    if wb_pr_comment "$wnum" "$a4
$WB_MARKER
<!-- gc-writeback-mark:$a1 $a2 -->"; then
      posted=$((posted + 1))
      wb_swaps "$a3"
    else
      echo "$PROG: $wid — PR#$wnum could not post the $a1 answer for $a2; retry next pass" >&2
    fi
  done <<WB_POSTS
$wplan
WB_POSTS
  # A comment whose answer is already posted but which still carries EYES or
  # lacks THUMBS_UP: its swap failed, or its answer was posted without one.
  # These are reaction writes like the pickup's, so they draw on the same
  # per-pass cap, and the comments it defers are swapped by the next pass.
  while IFS="$(printf '\t')" read -r act a1; do
    [ "${act:-}" = "S" ] || continue
    [ "$wack_ok" = 1 ] || continue
    [ "$wdone" -lt "$WB_REACT_CAP" ] || continue
    wdone=$((wdone + 1))
    wb_swaps "$a1"
  done <<WB_SWAPS
$wplan
WB_SWAPS

  # --- a human objection owes its raiser an answer on the PR -------------------
  # Every ruling a human finding takes, bar an open must-fix the fix unit answers
  # in code, owes its raiser a visible answer stamped as finding.reply against the
  # row it answers (finding.comment_id): a declined finding's overrule, a deferred
  # finding's follow-up id, or a needs-you finding's visit id. This posts that
  # answer into the raiser's thread, or, for a review body or a Conversation
  # comment, onto the Conversation tab with a link to the comment it answers. A
  # declined or deferred finding is settled: its answer leads with the check mark,
  # the thread is resolved behind it, and no open thread holds the merge. A
  # needs-you finding is NOT settled, since the operator still owes a ruling: its
  # answer leads with the question mark, its thread is left unresolved, and the
  # review holds the merge until they give it. The operator re-raises a decline
  # by re-reviewing — the content key re-adopts the closed finding as a fresh one
  # and pr-facts re-opens the human validation pass — so resolving forecloses no
  # re-raise. Idempotent: finding.reply_posted marks a finding answered, and an
  # answer carrying this finding's line, or a reply of ours carrying neither a
  # mark line nor a finding line, is never doubled. Only a pass that read the threads cleanly
  # acts, the same $wplan_ok gate the plan above turns on. Reads live + closed,
  # because a needs-you finding owes its reply while still open.
  if [ -n "$disp" ] && [ "$wplan_ok" = 1 ] && wdf=$(bd_list --metadata-field anchor_bead="$wid" --status="$ALL_STATUSES"); then
    wdrows=$(printf '%s' "$wdf" | jq -rc '.[]?
        | select(((.metadata.task_kind // "") | tostring) == "finding")
        | select(((.metadata["finding.lane"] // "") | tostring) == "human")
        | (((.metadata["finding.disposition"] // "") | tostring)) as $disp
        | select($disp == "declined" or $disp == "deferred" or $disp == "needs-you")
        | select(((.metadata["finding.reply"] // "") | tostring) != "")
        | select(((.metadata["finding.reply_posted"] // "") | tostring) == "")
        | { id: .id, cid: ((.metadata["finding.comment_id"] // "") | tostring),
            rid: ((.metadata["finding.review_id"] // "") | tostring),
            reply: ((.metadata["finding.reply"]) | tostring), disp: $disp } | @base64' 2>/dev/null)
    while IFS= read -r wdrow; do
      [ -n "$wdrow" ] || continue
      wdj=$(printf '%s' "$wdrow" | base64 -d 2>/dev/null) || continue
      wdfid=$(printf '%s' "$wdj" | jq -r '.id // empty')
      [ -n "$wdfid" ] || continue
      wdcid=$(printf '%s' "$wdj" | jq -r '.cid // empty')
      wdrid=$(printf '%s' "$wdj" | jq -r '.rid // empty')
      wddisp=$(printf '%s' "$wdj" | jq -r '.disp // empty')
      wdglyph="$WB_GLYPH_RESOLVED"; [ "$wddisp" = "needs-you" ] && wdglyph="$WB_GLYPH_AWAITING"
      wdreply="$wdglyph $(printf '%s' "$wdj" | jq -r '.reply')"
      wdline="<!-- gc-writeback-finding:$wdfid -->"
      # The thread whose originating comment is the one this finding answers. An
      # inline comment's databaseId is the reviewThread's; a review-body or
      # Conversation objection matches none, and is answered on the PR itself.
      wdtid=$(printf '%s' "$wview" | jq -r --arg c "$wdcid" '
        [ .threads[] | select((.comments.nodes // []) | any(((.databaseId // 0) | tostring) == $c)) | .id ] | .[0] // empty' 2>/dev/null)
      if [ -z "$wdtid" ]; then
        # A review body's finding carries its own id as finding.review_id; any
        # other finding no thread holds was raised in the Conversation.
        wdref=$(printf '%s' "$wview" | jq -r --arg c "$wdcid" --arg r "$wdrid" '
          (if $r != "" and $r == $c then .reviews else .issue_comments end)
          | [ .[]? | select(((.databaseId // 0) | tostring) == $c) | (.url // "") | select(. != "") ] | .[0] // empty' 2>/dev/null)
        [ -z "$wdref" ] || wdreply="$wdreply In reply to $wdref."
        if printf '%s' "$wview" | jq -e --arg self "$SELF_LOGIN" --arg l "$wdline" '
             any(.issue_comments[]?; ((.author.login // "") == $self) and ((.body // "") | contains($l)))' >/dev/null 2>&1; then
          gc bd update "$wdfid" --set-metadata finding.reply_posted=1 >/dev/null 2>&1 || true
        elif wb_pr_comment "$wnum" "$wdreply
$WB_MARKER
$wdline"; then
          gc bd update "$wdfid" --set-metadata finding.reply_posted=1 >/dev/null 2>&1 || true
          replied=$((replied + 1))
        else
          echo "$PROG: $wid — PR#$wnum could not post the owed reply for $wdfid; retry next pass" >&2
        fi
        continue
      fi
      # Already answered on this thread? This finding's line there means a prior
      # pass replied but did not get to mark or resolve; pick up where it stopped.
      wdreplied=0
      if printf '%s' "$wview" | jq -e --arg t "$wdtid" --arg self "$SELF_LOGIN" --arg m "$WB_MARKER" --arg l "$wdline" '
           [ .threads[] | select(.id == $t) | (.comments.nodes // [])[]
             | select((.author.login // "") == $self) | (.body // "")
             | select(contains($l) or (contains($m) and (test("<!-- gc-writeback-(mark|finding):") | not))) ]
           | length > 0' >/dev/null 2>&1; then
        wdreplied=1
      fi
      if [ "$wdreplied" = 0 ]; then
        if wb_thread_reply "$wdtid" "$wdreply
$WB_MARKER
$wdline"; then
          replied=$((replied + 1)); wdreplied=1
        else
          echo "$PROG: $wid — PR#$wnum could not reply the decline for $wdfid on thread $wdtid; retry next pass" >&2
          continue
        fi
      fi
      # A needs-you reply posts the visit id but leaves the thread UNRESOLVED: the
      # operator still owes a ruling and the open finding holds the review until
      # they give it, so resolving would tell the reader the objection is answered
      # when it is not. Mark it posted so the reply is not doubled, and move on.
      if [ "$wddisp" = "needs-you" ]; then
        gc bd update "$wdfid" --set-metadata finding.reply_posted=1 >/dev/null 2>&1 || true
        continue
      fi
      # Resolve behind the reply so the answered thread no longer holds the merge.
      # A thread this identity cannot resolve, or one already resolved, needs no
      # write; either way the finding is answered and is marked so.
      wdres_ok=1
      wdcanres=$(printf '%s' "$wview" | jq -r --arg t "$wdtid" '[ .threads[] | select(.id == $t) | (.viewerCanResolve // false) ] | .[0] // false')
      wdisres=$(printf '%s' "$wview" | jq -r --arg t "$wdtid" '[ .threads[] | select(.id == $t) | (.isResolved // false) ] | .[0] // false')
      if [ "$wdisres" != "true" ] && [ "$wdcanres" = "true" ]; then
        if gh_graphql 'mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' -f t="$wdtid" >/dev/null; then
          resolved=$((resolved + 1))
        else
          wdres_ok=0
          echo "$PROG: $wid — PR#$wnum replied the decline for $wdfid but could not resolve thread $wdtid; retry next pass" >&2
        fi
      fi
      [ "$wdres_ok" = 1 ] && { gc bd update "$wdfid" --set-metadata finding.reply_posted=1 >/dev/null 2>&1 || true; }
    done <<WB_DECLINES
$wdrows
WB_DECLINES
  fi

  # --- dismiss a human review and re-request its author once all of its findings
  #     clear ------------------------------------------------------------------
  # A human CHANGES_REQUESTED holds the merge and is GitHub's own blocking signal.
  # It stands until someone clears it, and the person who reads the PR reads that
  # signal, so a review answered in full but left standing tells them the opposite
  # of the truth. Once every finding one review raised has closed — a must-fix
  # fixed and landed, or a decline replied and resolved by the arms above — that
  # review is answered, so dismiss it (clearing CHANGES_REQUESTED) and re-request
  # its author, putting the reviewer back in their review-requested queue to judge
  # the result. Per-review, keyed on finding.review_id: one reviewer clears
  # independently of another on the same PR. The confidence is the validator's,
  # carried by the finding's closure (the validator ruled it and the fix landed or
  # the decline was answered), never a commit oid — a later push does not reopen
  # this. Dismissal is not approval: the merge still gates on an explicit one. Only
  # a pass that read the threads cleanly acts, the same $wplan_ok gate the reply
  # and resolve arms above turn on.
  if [ -n "$disp" ] && [ "$wplan_ok" = 1 ]; then
    # Every finding on this anchor that names a review, open and closed, grouped by
    # that review. A review is answered when every one of its findings is closed and
    # every declined or deferred finding has had its owed reply posted
    # (finding.reply_posted=1). Such a finding closes when the validator rules it,
    # which is before the reply arm above delivers that answer, so closure alone does
    # not mean answered. A needs-you or still-unvalidated finding is open, so its
    # review is not yet clear — a needs-you finding deliberately holds the review
    # changes-requested until the operator rules its visit.
    if wrf=$(bd_list --metadata-field anchor_bead="$wid" --status="$ALL_STATUSES"); then
      wrev_ready=$(printf '%s' "$wrf" | jq -rc '
          [ .[] | select(((.metadata.task_kind // "") | tostring) == "finding")
                | select(((.metadata["finding.review_id"] // "") | tostring) != "")
                | { rid: ((.metadata["finding.review_id"]) | tostring),
                    open: (((.status // "") | tostring) != "closed"),
                    disp: ((.metadata["finding.disposition"] // "") | tostring),
                    lane: ((.metadata["finding.lane"] // "") | tostring),
                    reply: ((.metadata["finding.reply"] // "") | tostring),
                    reply_posted: ((.metadata["finding.reply_posted"] // "") | tostring),
                    title: ((.title // "") | tostring) } ]
          | group_by(.rid)
          | [ .[] | { rid: .[0].rid,
                      ready: (all(.[];
                                  (.open == false)
                                  and (( .lane == "human" and (.disp == "declined" or .disp == "deferred")
                                         and .reply != "" and .reply_posted != "1" ) | not))),
                      lines: [ .[] | "- " + (.title | sub("^finding\\[[^]]*\\]: "; "")) + ": "
                                 + (if .disp == "declined" then "resolved by an accepted decline"
                                    elif .disp == "deferred" then "tracked as a follow-up for after the merge"
                                    elif .disp == "must-fix" then "addressed by a change"
                                    else "resolved" end) ] } ]
          | .[] | select(.ready) | @base64' 2>/dev/null)
      while IFS= read -r wrr; do
        [ -n "$wrr" ] || continue
        wrrj=$(printf '%s' "$wrr" | base64 -d 2>/dev/null) || continue
        wrid=$(printf '%s' "$wrrj" | jq -r '.rid // empty')
        [ -n "$wrid" ] || continue
        # The live review this id names. Only a feedback CHANGES_REQUESTED is this
        # arm's to clear: our own superseded block (gc_city_own) is the reconcile
        # arm's, above; an already-DISMISSED or otherwise non-blocking review needs
        # nothing, and its DISMISSED state is the idempotency — a repeat pass finds
        # nothing to do.
        wrstate=$(printf '%s' "$wview" | jq -r --arg r "$wrid" \
          '[ .reviews[]? | select(((.databaseId // "") | tostring) == $r) ] | .[0].state // empty' 2>/dev/null)
        wrlogin=$(printf '%s' "$wview" | jq -r --arg r "$wrid" \
          '[ .reviews[]? | select(((.databaseId // "") | tostring) == $r) ] | .[0].author.login // empty' 2>/dev/null)
        wrown=$(printf '%s' "$wview" | jq -r --arg r "$wrid" --arg self "$SELF_LOGIN" --arg since "$wsince" "$CITY_OWN_DEF"'
          [ .reviews[]? | select(((.databaseId // "") | tostring) == $r) ] | .[0] // {} | gc_city_own($self; $since)' 2>/dev/null)
        [ "$wrstate" = "CHANGES_REQUESTED" ] || continue
        [ -n "$wrlogin" ] && [ "$wrown" = "false" ] || continue
        # A review under our own login that is feedback (a model review run on the
        # city's account, unmarked, after the cutover) has no reviewer to re-queue:
        # the account it would re-request is the one making the request, and
        # GitHub refuses a re-request of the PR's author. That review is dismissed
        # without one, so a re-request that can never land does not hold its
        # dismissal on every pass.
        wrrequeue=1
        [ "$wrlogin" = "$SELF_LOGIN" ] && wrrequeue=0
        wrlines=$(printf '%s' "$wrrj" | jq -r '.lines[]?' 2>/dev/null)
        if [ "$wrrequeue" = 1 ]; then
          wrhead="Every comment from this review has been addressed on PR #$wnum, so its changes-requested block is dismissed and a fresh review is requested."
        else
          wrhead="Every comment from this review has been addressed on PR #$wnum, so its changes-requested block is dismissed. It was posted under the city's own account, so no fresh review is requested from it."
        fi
        wrmsg="$wrhead

$wrlines

Dismissal does not mark approval; the merge still gates on an explicit approving review."
        # Re-request the author FIRST, so a re-queue that cannot land holds the
        # dismissal with it: both are in scope, and a dismissal alone would drop
        # the reviewer instead of re-queuing them. Re-requesting a past reviewer is
        # allowed, so the retry after a failed dismiss repeats it harmlessly.
        if [ "$wrrequeue" = 1 ] && ! gh_api_origin -X POST "repos/$ORIGIN_REPO/pulls/$wnum/requested_reviewers" \
             -f "reviewers[]=$wrlogin" >/dev/null 2>&1; then
          echo "$PROG: $wid — PR#$wnum could not re-request $wrlogin for review $wrid; NOT dismissing (retry next pass)" >&2
          continue
        fi
        if gh_api_origin -X PUT "repos/$ORIGIN_REPO/pulls/$wnum/reviews/$wrid/dismissals" \
             -f message="$wrmsg" >/dev/null 2>&1; then
          dismissed_n=$((dismissed_n + 1))
          if [ "$wrrequeue" = 1 ]; then
            echo "$PROG: $wid — PR#$wnum dismissed human review $wrid and re-requested $wrlogin (its findings all cleared)"
          else
            echo "$PROG: $wid — PR#$wnum dismissed review $wrid, posted under our own login, with no re-request (its findings all cleared)"
          fi
        elif [ "$wrrequeue" = 1 ]; then
          echo "$PROG: $wid — PR#$wnum re-requested $wrlogin but could not dismiss review $wrid; retry next pass" >&2
        else
          echo "$PROG: $wid — PR#$wnum could not dismiss review $wrid; retry next pass" >&2
        fi
      done <<WB_REVIEW_CLEARS
$wrev_ready
WB_REVIEW_CLEARS
    fi
  fi

  # --- a ruled machine finding is posted where the operator reads the PR --------
  # Each finding this anchor owes (WB_FOWED, above) is posted once and answered
  # once it closes, and each write is stamped after it lands. It is posted as a
  # file-level review comment when its locus begins with a file the PR's diff
  # touches, the only path GitHub anchors a review comment to, and as a
  # Conversation comment otherwise. Its answer names the commit carrying the fix
  # or the deferral's follow-up. A finding that has already closed is posted with
  # its answer in place, so nothing on the PR shows it still holding the merge.
  # One that closes after it was posted is answered by a reply in its thread, or,
  # since a Conversation comment has no thread, by an edit that puts the answer
  # in place. An answered thread is resolved unless a post that is not the
  # city's own has come after it, which leaves that conversation to whoever
  # wrote it. The markers are read back before any write, so a post whose stamp
  # did not land is recorded rather than repeated, and a thread opened this pass
  # is resolved by the next one, which can read it back. A posted finding whose
  # comment is gone from the PR has nothing left to answer. Only a pass that read
  # the threads cleanly acts.
  if [ -n "$wfown" ] && [ "$wplan_ok" = 1 ] && [ -n "$whead" ]; then
    wffiles=""; wffiles_rc=""
    while IFS= read -r wfrow; do
      [ -n "$wfrow" ] || continue
      wfj=$(printf '%s' "$wfrow" | base64 -d 2>/dev/null) || continue
      wfid=$(printf '%s' "$wfj" | jq -r '.id // empty' 2>/dev/null)
      wfact=$(printf '%s' "$wfj" | jq -r '.act // empty' 2>/dev/null)
      [ -n "$wfid" ] && [ -n "$wfact" ] || continue
      # Where the finding already sits: the city's own comment carrying its
      # marker, in a review thread or the Conversation. A post after it that is
      # not the city's own is someone writing in the thread, whoever wrote it,
      # the same test the plan above reads a thread's later replies by.
      wfat=$(printf '%s' "$wview" | jq -c --arg self "$SELF_LOGIN" --arg since "$wsince" \
          --arg m "$WB_FINDING_MARKER$wfid -->" --arg am "$WB_FINDING_MARKER$wfid:answered -->" "$CITY_OWN_DEF"'
        def mine($k): gc_city_own($self; $since) and ((.body // "") | contains($k));
        ( [ .threads[] | . as $t | ($t.comments.nodes // []) as $cs
            | ([ $cs | to_entries[] | select(.value | mine($m)) | .key ] | first) as $at
            | select($at != null)
            | { kind: "thread", db: (($cs[$at].databaseId // 0) | tostring), thread: $t.id,
                resolved: ($t.isResolved // false), canres: ($t.viewerCanResolve // false),
                answered: any($cs[]; mine($am)),
                after: ([ $cs | to_entries[] | select(.key > $at)
                          | select(.value | gc_city_own($self; $since) | not) ] | length) } ]
        + [ .issue_comments[] | select(mine($m))
            | { kind: "issue", db: ((.databaseId // 0) | tostring), answered: mine($am) } ] )
        | .[0] // { kind: "" }' 2>/dev/null) || wfat=""
      if [ -z "$wfat" ]; then
        echo "$PROG: $wid — PR#$wnum could not tell whether finding $wfid is on the PR; nothing written for it (retry next pass)" >&2
        continue
      fi
      wfkind=$(printf '%s' "$wfat" | jq -r '.kind // ""')
      wfdb=$(printf '%s' "$wfat" | jq -r '.db // ""')
      wfanswered=$(printf '%s' "$wfat" | jq -r '.answered // false')
      case "$wfact" in
        post)
          if [ -n "$wfkind" ]; then
            gc bd update "$wfid" --set-metadata finding.pr_comment="$wfdb" >/dev/null 2>&1 \
              || echo "$PROG: $wid — PR#$wnum finding $wfid is on the PR but its stamp did not record; retry next pass" >&2
            continue
          fi
          if [ "$wfwrites" -ge "$WB_FINDING_CAP" ]; then wfheld=$((wfheld + 1)); continue; fi
          # The files the diff touches, names only. A file the PR removes is left
          # out: GitHub anchors no review comment to it, and a post refused every
          # pass would never land.
          if [ -z "$wffiles_rc" ]; then
            if wffiles=$(gh_api_origin --paginate "repos/$ORIGIN_REPO/pulls/$wnum/files?per_page=100" \
                 --jq '.[] | select((.status // "") != "removed") | .filename' 2>/dev/null); then
              wffiles=$(printf '%s' "$wffiles" | jq -Rsc 'split("\n") | map(select(length > 0))' 2>/dev/null)
              [ -n "$wffiles" ] && wffiles_rc=0 || wffiles_rc=1
            else
              wffiles_rc=1
            fi
          fi
          if [ "$wffiles_rc" != 0 ]; then
            echo "$PROG: $wid — PR#$wnum file list unreadable; finding $wfid not posted (retry next pass)" >&2
            continue
          fi
          # The longest diff path the locus begins with, ending where a path cannot.
          wfpath=$(printf '%s' "$wffiles" | jq -r --arg l "$(printf '%s' "$wfj" | jq -r '.locus // ""')" '
            ($l | sub("^[\\s`]+"; "")) as $l
            | [ .[]? | tostring | select(. != "") | . as $p
                | select(($l | startswith($p))
                         and (($l | length) == ($p | length)
                              or ($l[($p | length):(($p | length) + 1)] | test("^[^A-Za-z0-9._/-]")))) ]
            | max_by(length) // empty' 2>/dev/null)
          wfans=""
          if [ "$(printf '%s' "$wfj" | jq -r '.closed')" = "true" ]; then
            wfans=$(finding_answer "$wfj" "$whead")
            [ -n "$wfans" ] || continue
          fi
          wfbody=$(printf '%s' "$wfj" | jq -r --arg mk "$WB_FINDING_MARKER" --arg ans "$wfans" "$WB_FINDING_BODY" 2>/dev/null)
          [ -n "$wfbody" ] || continue
          wfwrites=$((wfwrites + 1))
          # Through pr-post.sh, like every city post: its mark is what keeps the
          # finding's own comment from reading back as feedback. The new comment's
          # id comes back in gh's output, the created comment for a file and the
          # comment's URL for the Conversation.
          if [ -n "$wfpath" ]; then
            wfwhere="on $wfpath"
            wfout=$("$PR_POST" file-comment --repo "$ORIGIN_REPO_Q" --pr "$wnum" --commit "$whead" \
              --path "$wfpath" --body "$wfbody" 2>/dev/null); wfrc=$?
            wfnew=$(printf '%s' "$wfout" | jq -r '.id // empty' 2>/dev/null)
          else
            wfwhere="to the Conversation"
            wfout=$("$PR_POST" comment --repo "$ORIGIN_REPO_Q" --pr "$wnum" --body "$wfbody" 2>/dev/null); wfrc=$?
            wfnew=$(printf '%s\n' "$wfout" | grep -Eo '#issuecomment-[0-9]+' | tail -1 | tr -cd '0-9')
          fi
          if [ "$wfrc" != 0 ]; then
            echo "$PROG: $wid — PR#$wnum could not post finding $wfid $wfwhere; retry next pass" >&2
            continue
          fi
          fposted=$((fposted + 1))
          echo "$PROG: $wid — PR#$wnum posted finding $wfid $wfwhere"
          case "$wfnew" in
            ''|*[!0-9]*)
              echo "$PROG: $wid — PR#$wnum finding $wfid posted, but its comment id did not read back; the next pass records it off its marker" >&2
              continue ;;
          esac
          # A Conversation comment posted with its answer in place owes nothing
          # more; a thread still owes its resolve.
          if [ -n "$wfans" ] && [ -z "$wfpath" ]; then
            gc bd update "$wfid" --set-metadata finding.pr_comment="$wfnew" --set-metadata finding.pr_answered=1 >/dev/null 2>&1
          else
            gc bd update "$wfid" --set-metadata finding.pr_comment="$wfnew" >/dev/null 2>&1
          fi || echo "$PROG: $wid — PR#$wnum finding $wfid posted but its stamp did not record; the next pass reads the marker back" >&2
          ;;
        answer)
          if [ -z "$wfkind" ]; then
            echo "$PROG: $wid — PR#$wnum finding $wfid was posted, but its comment is gone from the PR; nothing left to answer"
            gc bd update "$wfid" --set-metadata finding.pr_answered=gone >/dev/null 2>&1 || true
            continue
          fi
          wfans=""
          if [ "$wfanswered" != "true" ]; then
            if [ "$wfwrites" -ge "$WB_FINDING_CAP" ]; then wfheld=$((wfheld + 1)); continue; fi
            wfans=$(finding_answer "$wfj" "$whead")
            [ -n "$wfans" ] || continue
          fi
          wfwrote=0
          if [ "$wfkind" = "thread" ]; then
            wftid=$(printf '%s' "$wfat" | jq -r '.thread // ""')
            if [ -n "$wfans" ]; then
              wfwrites=$((wfwrites + 1))
              if ! wb_thread_reply "$wftid" "$wfans
$WB_FINDING_MARKER$wfid:answered -->"; then
                echo "$PROG: $wid — PR#$wnum could not answer finding $wfid on thread $wftid; NOT resolving it (retry next pass)" >&2
                continue
              fi
              wfwrote=1
            fi
            if [ "$(printf '%s' "$wfat" | jq -r '.after // 0')" != "0" ]; then
              echo "$PROG: $wid — PR#$wnum thread $wftid has a reply after finding $wfid; answered, left unresolved"
            elif [ "$(printf '%s' "$wfat" | jq -r '.resolved')" != "true" ] \
                 && [ "$(printf '%s' "$wfat" | jq -r '.canres')" = "true" ]; then
              if gh_graphql 'mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
                   -f t="$wftid" >/dev/null; then
                resolved=$((resolved + 1)); wfwrote=1
              else
                echo "$PROG: $wid — PR#$wnum answered finding $wfid but could not resolve thread $wftid; retry next pass" >&2
                continue
              fi
            fi
          elif [ -n "$wfans" ]; then
            wfbody=$(printf '%s' "$wfj" | jq -r --arg mk "$WB_FINDING_MARKER" --arg ans "$wfans" "$WB_FINDING_BODY" 2>/dev/null)
            [ -n "$wfbody" ] || continue
            wfwrites=$((wfwrites + 1))
            if ! "$PR_POST" edit --repo "$ORIGIN_REPO_Q" --comment "$wfdb" --body "$wfbody" >/dev/null 2>&1; then
              echo "$PROG: $wid — PR#$wnum could not answer finding $wfid on its Conversation comment; retry next pass" >&2
              continue
            fi
            wfwrote=1
          fi
          [ "$wfwrote" = 0 ] || fanswered=$((fanswered + 1))
          gc bd update "$wfid" --set-metadata finding.pr_answered=1 >/dev/null 2>&1 \
            || echo "$PROG: $wid — PR#$wnum finding $wfid answered but its stamp did not record; the next pass reads the answer back" >&2
          ;;
      esac
    done <<WB_FINDINGS
$(printf '%s' "$wfown" | jq -r '.[] | @base64' 2>/dev/null)
WB_FINDINGS
  fi

  # The plan is this pass's own read of GitHub, so a plan that could not be built
  # retires nothing. Its K line names, per ledger, the records to keep: the
  # newest, and every one covering a comment whose final state that read did not
  # show (answered, THUMBS_UP on, EYES off, its thread done). A record whose
  # last write lands this pass is retired by the next pass's read.
  wkeep=$(printf '%s\n' "$wplan" | awk -F'\t' '$1 == "K" { print $2 "\t" $3 "\t" $4; exit }')
  if [ "$wbatch_ok" = 1 ] && [ "$wplan_ok" = 1 ] && [ -n "$wkeep" ]; then
    IFS="$(printf '\t')" read -r wkc wkr wki <<WB_KEEP
$wkeep
WB_KEEP
    wkset=()
    wbkeep=$(ledger_keep "$wbwant" "$wkc") && wkset+=(--set-metadata "pr_comment_batch=$wbkeep")
    wbkeep=$(ledger_keep "$wrbatch" "$wkr") && wkset+=(--set-metadata "pr_review_batch=$wbkeep")
    wbkeep=$(ledger_keep "$wibatch" "$wki") && wkset+=(--set-metadata "pr_issue_comment_batch=$wbkeep")
    [ "${#wkset[@]}" -eq 0 ] || gc bd update "$wid" "${wkset[@]}" >/dev/null 2>&1
  fi
done <<WB_ROWS
$(printf '%s\n' "$wb_first" | awk 'NF { print "first\t" $0 }')
$(printf '%s\n' "$wb_rest" | awk 'NF { print "rest\t" $0 }')
WB_ROWS
pace_end
if [ -n "$CURSOR$DEADLINE" ] && [ "$POSTURE_ONLY" != 1 ] && [ "$ROUTE_ONLY" != 1 ]; then
  wpaced="write-back visited $PACE_VISITED of ${wb_due:-?} anchors with routed comments or owed findings ($wb_first_n with something new first)"
  if [ -n "$PACE_RESUME_AT" ] || [ "$PACE_FIRST_SKIPPED" -gt 0 ]; then
    wpaced="$wpaced before the deadline"
    [ -z "$PACE_RESUME_AT" ] || wpaced="$wpaced; the next pass resumes at $PACE_RESUME_AT"
    [ "$PACE_FIRST_SKIPPED" -eq 0 ] || wpaced="$wpaced; $PACE_FIRST_SKIPPED with something new wait for the next pass"
  fi
  echo "$PROG: $wpaced"
fi
[ "$wfheld" -eq 0 ] || echo "$PROG: $wfheld finding post(s) or answer(s) wait for the next pass (cap $WB_FINDING_CAP per pass)" >&2

if [ "$POSTURE_ONLY" = 1 ]; then
  echo "$PROG: posture-only — $postured postures recorded, $unpostured not current, $skipped skipped; $pkept unchanged since the basis they were derived from, $pread read per PR"
  # Only this mode's exit code gates anything: refinery-reconcile runs it
  # immediately before merge.sh and holds the merge arm on a non-zero. The full
  # pass runs after merge, where the same rc would gate nothing.
  [ "$unpostured" -eq 0 ] || exit 1
elif [ "$ROUTE_ONLY" = 1 ]; then
  # The early feedback arm, run after merge and pr-open and ahead of the slow
  # arms, so operator feedback is routed on the tick the posture is stamped
  # instead of waiting for the full pass at the tail. Its rc holds nothing:
  # routing is best-effort and the full pass re-runs it idempotently, so
  # refinery-reconcile reports a non-zero but never holds merge on it.
  echo "$PROG: route-comments-only — $postured postures recorded, $answered comment batches routed, $skipped skipped"
else
  echo "$PROG: $recorded recorded, $postured postures recorded ($unpostured not current), $flagged flagged-to-human, $disposed_n auto-disposed, $reworked reworks filed, $reaped moot reworks reaped, $answered comment batches routed, $dismissed_n reviews dismissed, $acked comments acknowledged, $replied threads replied, $resolved threads resolved, $posted conversation answers posted, $swapped comments marked resolved, $fposted findings posted, $fanswered findings answered, $skipped skipped"
fi
exit 0
