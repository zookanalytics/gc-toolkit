#!/usr/bin/env bash
# reconcile-gate-verdicts — the merge-gate VERDICT arm (WS4 of tk-zgse0; design
# specs/tk-zgse0.2/merge-gate-exception-lifecycle.md, merged as PR #219).
#
# The shipped check-set core gives a gate two outcomes made concrete as bead
# metadata on the gating anchor: OK (`check.<name>=green@<sha>`) and fixable (no
# green marker; findings become child work-beads that hold the merge). This pass
# adds the THIRD outcome — `exception` — and records the two non-OK verdicts
# explicitly instead of leaving them as the mere ABSENCE of a green marker.
#
#   check.<name>=green@<sha>      OK        merges iff <sha> is the live head
#   check.<name>=fixable@<sha>    fixable   remediation in flight; holds the merge
#   check.<name>=exception@<sha>  exception held for an operator; never auto-fixed
#
# THE MERGE SKILL IS UNCHANGED, and that is the whole trick. merge-skill.sh's
# `checkset_hold_gate` holds while any declared gate is `!= "green@" + <live head>`,
# so a new marker VERB already holds the merge — a stale green, an absent marker,
# and a non-green verb are one and the same to it. WS4 therefore ships as a verdict
# vocabulary plus this one reconcile arm: no new writer of merged-truth, no new
# blocking driver, no change to the merge condition.
#
# WHAT THIS PASS IS FOR — gates that hold FOREVER with nothing to raise them:
#
#   R11  bounded remediation exhaustion. A gate that has burned its remediation
#        rounds keeps filing rework children that keep not converging. The signoff
#        round cap (template-fragments/polecat-non-impl-done.template.md,
#        `signoff-round-cap`, and its refinery mirror in
#        formulas/mol-refinery-patrol.toml) already stops the SPAWNING at the cap
#        and routes the anchor to a human — but it records no verdict, so the
#        anchor's own state never says WHY it is held, and the cap only fires on a
#        round that actually reaches a reviewer. This pass records the verdict, and
#        reaches the rounds the fragment never saw.
#
#        THE CAP ARMS WRITE NO MARKER; THIS PASS IS THE SINGLE WRITER OF THE
#        VERDICT. Both of them used to ALSO `--unset-metadata check.<name>` on the
#        same event this arm records as `exception@<head>` — one cap, two opposite
#        terminal states, and pass ordering deciding which survived (tk-mf3em;
#        su-uzy9.5 and sl-ew4w caught the two orderings in production). Worse than
#        a tie-break: the cap arms sit in the patrol's merge-push step and this
#        pass in find-work, so a single wake stamped then cleared, and
#        check-set-heal.sh — which dispatches on an ABSENT marker and skips on
#        `exception@*` — re-dispatched codex every wake against a gate that had
#        already given up. The clear is gone from both arms; if a third writer of
#        `check.<name>` ever appears, this is the note that says why it must not.
#
#   R12  infrastructure failure. The check-skill crashed, ran past its deadline, or
#        produced output no contract could map. This is the arm with NO coverage
#        today and it is the live gap: a review bead whose worker died sits OPEN and
#        in_progress forever, and every existing pass reads it as healthy work in
#        flight — check-set-heal.sh skips the dispatch ("a review is already in
#        flight"), the stale-gate arm in reconcile-merged-prs.sh never fires (it
#        keys on a stale GREEN marker, and a first review that died stamped no
#        marker at all), and merge-skill.sh holds on the missing marker. Nothing
#        anywhere times it out. The PR is held indefinitely and silently.
#
#        ...and the dead review is RETIRED when it is condemned, which is the half
#        that makes the escape real. A review bead carries no record of the head it
#        was dispatched for, so left open it answers this scan again at EVERY later
#        head: the operator fixes the branch, the head moves, `gate_verdict` reads
#        the old marker as unevaluated exactly as designed — and then the same dead
#        review condemns the new head before the re-arm below can clear anything.
#        The exception is not "terminal until the input changes", it is terminal
#        FULL STOP, and the escape the design promises does not exist. Worse
#        post-open: once reconcile-merged-prs.sh dispatches a fresh re-review, the
#        old dead review can stamp exception over a real review in flight. So a
#        condemned review is marked (`gate_verdict_condemned=<head>`, so it can
#        never spend a second condemnation) and CLOSED (so check-set-heal.sh stops
#        reading it as a signoff already in flight and can dispatch the replacement
#        that actually raises the gate). Marking alone would fix the re-condemnation
#        and leave the gate un-dispatchable — the same silent hold, one step along.
#
#   RE-ARM (pre-open). The mirror image of R12, and the same silent hold from the
#        other end: a verdict marker left behind by a head that has since MOVED.
#        check-set-heal.sh skips its dispatch on `green@*` and `exception@*` (and,
#        since review tk-i688b, on any marker naming no verb at all) and resolves no
#        head, so it cannot tell a live verdict from residue.
#        Post-open, reconcile-merged-prs.sh's stale-marker arm reads the live PR
#        head and re-dispatches; PRE-open there is no PR and that arm enumerates
#        `merge_result=pull_request` only, so nothing re-arms the gate — the
#        operator fixes the branch, the head advances, and the fix has no effect
#        because the stale marker still reads as authoritative to the only pass
#        that dispatches. This pass already resolves the pre-open head to bind its
#        own verdicts, so it clears the residue and the gate re-arms to
#        Unevaluated, which is the transition the design specifies for a head move
#        anyway. Clearing can only hold harder: an absent marker is green at no
#        head.
#
# THIS PASS NEVER WRITES `green` AND NEVER MERGES. Every write it makes either
# holds the merge or keeps it held, so no failure mode of this script can land
# work. That is deliberate: it is an OBSERVER arm in the sense
# docs/work-bead-state-machine.md means — it reads state, liveness and time, and it
# files/records; the merge skill remains the single writer of merged-truth.
#
# CONVERGENCE comes from the same two properties as the stale-base arm it is
# modelled on (docs/work-bead-state-machine.md §"Stale base"):
#
#   * The gating marker stays INTACT. merge_result is never touched, so the anchor
#     remains the single gating locus and the merge skill remains its only lander.
#     Flipping it off would strand a later-green PR with nothing to land it.
#   * ONE ACTION PER HEAD. `check.<name>.exception_escalated=<head at escalation>`
#     bounds the operator notification to one per head, so a held exception does not
#     re-mail on every idle wake. A head move is a genuinely new subject: every
#     head-bound datum goes stale at once and the gate re-arms to Unevaluated,
#     which is how an exception CLEARS — the operator fixes the branch, the head
#     advances, the gate re-evaluates fresh. No reopen dance, no manual flag reset.
#
# WHY THE ROUND COUNT IS NOT RESET PER HEAD (a deliberate divergence from the
# design doc's literal wording, recorded here because it inverts the requirement's
# effect). The doc describes `check.<name>.attempts` as "remediation rounds spent
# on this head". Taken literally the counter resets whenever the head moves — but a
# rework round that does any work AT ALL moves the head by construction, so the
# bound would reset every single round and R11's "convert to exception rather than
# re-spawning again" could never fire. The runaway this requirement exists to stop
# (one PR reached 15 rounds) is precisely a sequence of rounds across MOVING heads.
# So the bound is counted over the same population the shipped signoff round cap
# counts — the anchor's remediation children, keyed by `source_review_bead` — and
# it is the ESCALATION that is head-bound, which is what the doc's one-per-head
# rule is actually protecting against (notification spam). The head is still
# stamped alongside the count, so `attempts=<n>@<sha>` reads as "n rounds spent,
# observed at this head".
#
# THE PRICE OF THAT DIVERGENCE, and what pays it. A count that never resets is
# permanently past the cap, so R11 would re-fire at EVERY later head and re-stamp
# the exception on the exact wake meant to re-arm it — the design's operator
# escape ("fix the branch, let the head move") silently would not exist. R11 is
# therefore suppressed while the marker is an exception bound to an OLDER head,
# exactly as R12b is and for the same reason: let the re-arm run first, and judge
# the new head on its own evidence. The count still is not reset, so a head move
# buys one evaluation rather than a clean slate, and the bound bites again as soon
# as that round closes (tk-mf3em).
#
# COMPLETED rounds only, which is where this count and the signoff cap's differ.
# The signoff cap asks the question at ONE instant — immediately before it files
# the next child — and at that instant nothing is in flight, so open-vs-closed
# cannot change its answer. This pass asks on every idle wake, including in the
# middle of a round, and there the difference is the whole finding: an open child
# counted as spent brings the cap forward a full round and converts a state a
# worker is actively fixing into an exception, which is terminal until an operator
# acts. The design fixes the increment on the child's CLOSE ("when a remediation
# child closes unresolved, the gate increments attempts"), and a rework child does
# close at hand-back, as landed-on-branch (docs/work-bead-state-machine.md
# §"Rework is a new child"), so the bound still bites — one wake later, on a gate
# with nothing left coming.
#
# SCOPE: both phases of the gate, because a gate holds in both.
#   * post-open (`merge_result=pull_request`) — the gate decides whether the PR
#     MERGES. The live head is the PR head.
#   * pre-open (`merge_result=pre_open_gate`) — the gate decides whether the PR
#     OPENS at all (tk-6d0vb.1.8). There is no PR; the live head is the branch head.
# An anchor in neither state is not gating and is not examined.
#
# Exit codes: 0 = pass ran (including "nothing to do"); non-zero = the pass could
# not complete. Call sites treat non-zero as non-fatal and retry next idle wake.
#
# NOT set -e: best-effort, must never abort the patrol mid-pass. Any tool error
# skips that anchor and retries next cycle.
set -uo pipefail

MAX_ATTEMPTS="${GC_MAX_REVIEW_ROUNDS:-3}"
# How long a dispatched gate may go untouched before a DEAD worker is called dead
# (R12). Deliberately generous: a codex review of a large diff legitimately takes
# tens of minutes, and the cost of calling a live worker dead (a spurious exception
# + one operator mail) is worse than the cost of waiting another wake. The rule
# below also requires the assignee to be answered by NO live session, so the
# deadline alone never condemns a working reviewer.
GATE_DEADLINE="${GC_GATE_DEADLINE:-14400}"
RIG_PIN="${GC_RIG:-}"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --max-attempts)   MAX_ATTEMPTS="${2:-}"; shift 2 ;;
    --max-attempts=*) MAX_ATTEMPTS="${1#--max-attempts=}"; shift ;;
    --gate-deadline)   GATE_DEADLINE="${2:-}"; shift 2 ;;
    --gate-deadline=*) GATE_DEADLINE="${1#--gate-deadline=}"; shift ;;
    --rig)     RIG_PIN="${2:-}"; shift 2 ;;
    --rig=*)   RIG_PIN="${1#--rig=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *)         shift ;;
  esac
done

case "$MAX_ATTEMPTS" in
  ''|*[!0-9]*)
    echo "reconcile-gate-verdicts: --max-attempts must be a non-negative integer (got '${MAX_ATTEMPTS}'); pass skipped" >&2
    exit 1 ;;
esac
case "$GATE_DEADLINE" in
  ''|*[!0-9]*)
    echo "reconcile-gate-verdicts: --gate-deadline must be a non-negative integer of seconds (got '${GATE_DEADLINE}'); pass skipped" >&2
    exit 1 ;;
esac

# EVERY bead read and write goes through this — never a bare `gc bd`. A bare call
# resolves to whatever ledger is ambient (BEADS_DIR, or the cwd's rig), and this
# pass runs from a patrol worktree whose ambient ledger is not necessarily the rig
# whose anchors it was asked about. Same pin, same reason, as
# reconcile-refinery-handoffs.sh.
bd_pinned() { # <bd-subcommand> [args...]
  if [ -n "$RIG_PIN" ]; then
    gc bd --rig "$RIG_PIN" "$@"
  else
    gc bd "$@"
  fi
}

# WHICH REPOSITORY this checkout is, host-qualified. Every head read below is
# pinned to it. Same parse and same fail-closed rule as check-set-heal.sh's
# resolve_origin_repo_q and reconcile-merged-prs.sh's; these scripts are standalone
# by design, so it is duplicated rather than sourced. Keep them in step.
ORIGIN_REPO_Q=""
origin_url=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$origin_url" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_REPO_Q=$(printf '%s' "$origin_url" \
      | sed -e 's#^ssh://git@github.com/##' -e 's#^git@github.com:##' \
            -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO_Q" in
  */*/*|/*|*/) ORIGIN_REPO_Q="" ;;
  */*)         ORIGIN_REPO_Q="github.com/$ORIGIN_REPO_Q" ;;
  *)           ORIGIN_REPO_Q="" ;;
esac
if [ -z "$ORIGIN_REPO_Q" ]; then
  # FAIL CLOSED. An unnameable repository means every head below would be read
  # wherever gh happens to point, and a head read from the wrong repository would
  # bind a verdict — and an operator escalation — to a commit this branch never
  # had. Recording nothing costs one idle wake.
  echo "reconcile-gate-verdicts: cannot resolve this checkout's origin repository (no origin remote, or not a github.com <owner>/<repo> URL); heads would be read wherever gh points — pass skipped" >&2
  exit 0
fi
ORIGIN_REPO="${ORIGIN_REPO_Q#*/}"
ORIGIN_HOST="${ORIGIN_REPO_Q%%/*}"

# ---------------------------------------------------------------------------
# The verdict output contract (R5, R20).
#
# A gate is a reference to a skill plus a THIN OUTPUT CONTRACT, and the contract is
# a TOTAL function from what is observable about that skill's run to exactly one
# verdict. Totality is the point: `exception` is defined as everything the other
# two arms cannot claim, so there is no observable state with no verdict — which is
# what makes "the gate is still thinking about it" impossible to confuse with "the
# gate died". Kept as one extractable block so the regression exercises the exact
# code the pass runs, and so a second gate implementation can lift it verbatim.
# ---------------------------------------------------------------------------
# >>> gate-verdict-contract
# The three verbs. `green` is spelled as it shipped — the OK verb predates this
# vocabulary and merge-skill.sh compares against the literal string — so the enum
# generalizes it rather than renaming it.
GATE_VERB_OK="green"
GATE_VERB_FIXABLE="fixable"
GATE_VERB_EXCEPTION="exception"

# Split a marker value into its verb and its oid. A marker is `<verb>@<oid>`; the
# oid is a git object id and cannot contain "@", so the FIRST "@" separates them.
#
# A marker that does not parse is NOT silently treated as absent: absent means
# "never evaluated" (a fresh dispatch raises it) while unparseable means the gate
# recorded something nobody can read, which is the R12 "output the contract cannot
# map" case and must reach an operator. The caller distinguishes them by the empty
# verb + non-empty raw marker.
gate_marker_verb() { # <marker>
  case "${1:-}" in
    "")     printf '' ;;
    *@*)    case "${1%%@*}" in
              "$GATE_VERB_OK"|"$GATE_VERB_FIXABLE"|"$GATE_VERB_EXCEPTION")
                printf '%s' "${1%%@*}" ;;
              *) printf '' ;;
            esac ;;
    *)      printf '' ;;
  esac
}

gate_marker_oid() { # <marker>
  case "${1:-}" in
    *@*) printf '%s' "${1#*@}" ;;
    *)   printf '' ;;
  esac
}

# The verdict of a gate, as a pure read of its marker against the LIVE head. This
# is the function the design calls a total map from marker to verdict; every caller
# in this pass and every future gate implementation should classify through it
# rather than re-deriving the comparison.
#
#   ok            green at the live head — the ONLY mergeable answer
#   fixable       fixable at the live head — remediation in flight, merge held
#   exception     exception at the live head — held for an operator, merge held
#   unevaluated   no marker at all, or a marker bound to some OTHER head. A head
#                 move drops every verdict back to unevaluated; that single rule is
#                 what re-arms OK, fixable and exception alike.
#   unmappable    a marker exists but names no verb this contract knows. R12.
gate_verdict() { # <marker> <live-head>
  local marker="${1:-}" head="${2:-}" verb oid
  [ -n "$marker" ] || { printf 'unevaluated'; return; }
  verb=$(gate_marker_verb "$marker")
  oid=$(gate_marker_oid "$marker")
  [ -n "$verb" ] || { printf 'unmappable'; return; }
  # An empty head is not a match for anything: without a live head to compare
  # against, no marker can be shown current, and "unevaluated" is the answer that
  # holds rather than the one that merges.
  if [ -z "$head" ] || [ -z "$oid" ] || [ "$oid" != "$head" ]; then
    printf 'unevaluated'; return
  fi
  case "$verb" in
    "$GATE_VERB_OK")        printf 'ok' ;;
    "$GATE_VERB_FIXABLE")   printf 'fixable' ;;
    "$GATE_VERB_EXCEPTION") printf 'exception' ;;
  esac
}

# The declared gates of a check_set, one per line, with the two members that are
# NOT satisfied by a `check.<name>` marker dropped: the `none`/`off` sentinel (a
# deliberate no-gates opt-out) and `approval` (evidenced by GitHub review state).
# Byte-for-byte the membership rule merge-skill.sh's `checkset_hold_gate` applies,
# because a gate this pass records a verdict for but the merge skill does not read
# — or the reverse — is a gate whose verdict means nothing.
#
# Case is PRESERVED, deliberately: merge-skill.sh keys each gate's marker as
# "check." + the gate name as written, so a `CODEX` gate is satisfied only by
# `check.CODEX`. Folding case here would record verdicts under a key the merge
# never reads.
#
# Whitespace is stripped PER TOKEN, never from the whole string at once: a gate
# name cannot contain any, but the separator this function produces is a newline —
# which is itself whitespace — so a blanket `tr -d '[:space:]'` would delete the
# separators along with the padding and fuse the whole check_set into a single
# nonsense gate.
gate_members() { # <check_set>
  printf '%s\n' "${1:-}" | tr ',' '\n' \
    | while IFS= read -r g; do
        g=$(printf '%s' "$g" | tr -d '[:space:]')
        [ -n "$g" ] || continue
        case "$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')" in
          none|off|approval) continue ;;
        esac
        printf '%s\n' "$g"
      done
}
# <<< gate-verdict-contract

# ---------------------------------------------------------------------------
# Live session roster: who actually answers to an address. Two sources, exactly as
# reconcile-refinery-handoffs.sh and the witness's liveness recipe use them — the
# live roster, plus the session BEADS, because a configured named session that is
# not currently spawned (scale-from-zero) is absent from the live roster while its
# configured identity still owns the queue.
#
# This roster is the half of R12 that keeps a SLOW reviewer safe: the deadline
# alone never condemns anyone, only a deadline passed by an assignee nobody answers
# to. If the roster cannot be read at all, the R12 worker-lost arm is DISABLED for
# the pass rather than guessed at — an unreadable roster makes every assignee look
# dead, and this arm mails an operator.
# ---------------------------------------------------------------------------
ROSTER=""
ROSTER_READABLE=""
SESSIONS_JSON=$(gc session list --state=all --json 2>/dev/null); SESSIONS_RC=$?
SESSION_BEADS_JSON=$(bd_pinned list --type=session --label=gc:session --include-infra \
  --include-gates --all --json --limit=0 2>/dev/null) || SESSION_BEADS_JSON=""
if [ "$SESSIONS_RC" -eq 0 ] && [ -n "$SESSIONS_JSON" ]; then
  # Both blobs go to jq on STDIN, never --argjson on argv: on a busy city the
  # session `command` fields overflow ARG_MAX ("argument list too long: jq").
  ROSTER=$(printf '%s\n%s' "${SESSIONS_JSON:-null}" "${SESSION_BEADS_JSON:-null}" \
    | jq -rs '
        (.[0] // {}) as $live | (.[1] // []) as $beads
        | [ ( ($live.sessions // [])[]?
              | select(((.closed // false) | tostring) != "true")
              | (.id // empty), (.name // empty), (.session_name // empty),
                (.alias // empty), (.agent_name // empty) ),
            ( ($beads // [])[]?
              | (.metadata.configured_named_identity // empty),
                (.metadata["gc.session_name"] // empty) ) ]
        | map(select(. != null and . != "")) | unique | .[]' 2>/dev/null)
  [ -n "$ROSTER" ] && ROSTER_READABLE=1
fi
[ -n "$ROSTER_READABLE" ] || echo "reconcile-gate-verdicts: live session roster unreadable (gc session list exited $SESSIONS_RC); the R12 worker-lost arm is disabled this pass — a slow reviewer must never be condemned by a roster that could not be read" >&2

# Does any live session answer to this address?
answered_by_live_session() { # <assignee>
  [ -n "${1:-}" ] || return 1
  grep -qxF -- "$1" <<< "$ROSTER"
}

NOW=$(date +%s 2>/dev/null || echo 0)

# Age in seconds of an ISO-8601 timestamp, or empty when it cannot be read. An
# unreadable timestamp is never treated as "infinitely old": that would condemn a
# gate for a date-parsing failure.
ts_age() { # <iso8601>
  local t="${1:-}" epoch
  [ -n "$t" ] || return 0
  epoch=$(date -d "$t" +%s 2>/dev/null) || epoch=""
  [ -n "$epoch" ] || return 0
  [ "$NOW" -gt 0 ] || return 0
  printf '%s' "$((NOW - epoch))"
}

# ---------------------------------------------------------------------------
# The gating anchors: both phases, one row shape.
# ---------------------------------------------------------------------------
ANCHOR_JQ='
.[]? | {
  id,
  phase:    (.metadata.merge_result // ""),
  checkset: (.metadata.check_set // ""),
  branch:   (.metadata.branch // ""),
  pr:       ((.metadata.pr_number // "") | tostring),
  hold:     ((.metadata.merge_hold // "") | tostring),
  routed:   (.metadata["gc.routed_to"] // ""),
  meta:     (.metadata // {})
}'

POST_OPEN=$(bd_pinned list --status=open --metadata-field merge_result=pull_request \
  --limit=200 --json 2>/dev/null)
PRE_OPEN=$(bd_pinned list --status=open --metadata-field merge_result=pre_open_gate \
  --limit=200 --json 2>/dev/null)

rows_of() { # <anchors-json>
  printf '%s' "${1:-}" | tr -d '\000-\010\013\014\016-\037' \
    | jq -c "$ANCHOR_JQ" 2>/dev/null
}
ROWS=$(printf '%s\n%s' "$(rows_of "$POST_OPEN")" "$(rows_of "$PRE_OPEN")" | grep -v '^$')

if [ -z "$ROWS" ]; then
  echo "reconcile-gate-verdicts: no live gating anchors"
  exit 0
fi

# ---------------------------------------------------------------------------
# Head resolution, pinned to this checkout's repository.
# ---------------------------------------------------------------------------
head_of_pr() { # <pr-number>
  gh pr view "$1" --repo "$ORIGIN_REPO_Q" --json headRefOid -q .headRefOid 2>/dev/null
}
head_of_branch() { # <branch>
  gh api --hostname "$ORIGIN_HOST" "repos/$ORIGIN_REPO/commits/$1" 2>/dev/null \
    | jq -r '.sha // empty' 2>/dev/null
}

# `merge_hold` truthiness, read exactly as merge-skill.sh reads it: set and not
# empty/false/0 holds, so a stale `merge_hold=false` never freezes this pass.
is_held() { # <merge_hold value>
  case "${1:-}" in
    ""|false|False|FALSE|0|null) return 1 ;;
    *) return 0 ;;
  esac
}

# Every write goes through here so --dry-run is total: a dry run that wrote even
# one marker would leave the city in a state the operator did not ask for and, worse,
# would arm a one-per-head guard that suppresses the real pass.
apply() { # <description> <bd args...>
  local what="$1"; shift
  if [ "$DRY_RUN" = 1 ]; then
    echo "reconcile-gate-verdicts: [dry-run] would $what"
    return 0
  fi
  bd_pinned update "$@" >/dev/null 2>&1
}

# Retire the dead reviews the R12b scan collected for one gate (LOST_REVIEWS). A
# review whose worker is gone must be able to condemn AT MOST ONE head, and must not
# — by staying open — suppress the replacement dispatch that would raise the gate at
# the next one. Two writes, neither redundant:
#
#   1. `gate_verdict_condemned=<head>` on the review. The scan skips a review
#      carrying it, so even where the close below is refused by the ledger, this
#      review can never spend a second condemnation.
#   2. CLOSE it. This is the half that re-opens the escape. check-set-heal.sh's
#      in-flight probe asks `--status=open,in_progress` on the EXACT `anchor_bead`
#      surface and trusts a hit outright, so a dead review left open reads as "a
#      signoff is already in flight" on every future pass and the replacement
#      dispatch is suppressed forever.
#
# Closing is the NORMAL terminal state of a review bead, not a novel one invented
# here: every signoff that completes closes itself (the non-impl done sequence), and
# check-set-heal.sh's closed-anchor scan filters out beads carrying `anchor_bead` or
# `task_kind` — which every review carries — so a closed review is inert everywhere
# it is read.
#
# SAFE ONLY BECAUSE THE GATE IS NOT OK, and that is why every call site sits below
# the `verdict = ok` early-continue. Post-open an open review bead is itself a merge
# hold (merge-skill.sh holds on any unclosed rework/review bead for the anchor), so
# closing one RELEASES a hold. Off the OK path this gate's marker is by construction
# not `green@<live head>` — absent, stale, or a non-green verb — so
# `checkset_hold_gate` holds the merge on the marker alone, before, during and
# after, and the pass's never-merges invariant is intact whichever order the writes
# land in. On an OK gate the open review could be the only remaining hold, and this
# pass never touches one.
#
# `--force` on the retry. `bd close` is assignee-gated, and this bead's assignee is
# by construction FOREIGN — a session that no longer exists — so merge-skill.sh's
# identity-ENCODING recovery does not apply and the plain close is refused for the
# one reason that provably does not hold here. That gate protects a LIVE holder's
# work; the two-part test that selected this bead (no live session answers its
# assignee, and it is past the deadline) is the proof there is no live holder, and
# it is the same evidence already trusted to record a terminal verdict and mail an
# operator. Overriding it is strictly less consequential than that.
retire_lost_reviews() { # <anchor> <gate> <head>
  local aid="$1" g="$2" h="$3" rid creason
  for rid in $LOST_REVIEWS; do
    [ -n "$rid" ] || continue
    creason="worker-lost: retired by the merge-gate verdict arm (anchor $aid, gate $g, head $h). No live session answered its assignee and it was untouched past the ${GATE_DEADLINE}s deadline, so it can neither raise this gate nor stand in for the review that will."
    apply "mark review $rid condemned at $h and retire it (R12b)" \
      "$rid" --set-metadata "gate_verdict_condemned=$h" \
      || echo "reconcile-gate-verdicts: WARN could not mark review $rid condemned at $h; it may condemn a later head — repair by hand" >&2
    if [ "$DRY_RUN" = 1 ]; then
      echo "reconcile-gate-verdicts: [dry-run] would close condemned review $rid"
      continue
    fi
    if bd_pinned close "$rid" --reason "$creason" >/dev/null 2>&1 \
       || bd_pinned close "$rid" --reason "$creason" --force >/dev/null 2>&1; then
      echo "reconcile-gate-verdicts: $aid — retired dead review $rid (check.$g, head $h)"
      retired=$((retired + 1))
    else
      echo "reconcile-gate-verdicts: WARN could not close dead review $rid on $aid; check-set-heal.sh will keep reading it as a signoff already in flight and will not dispatch the replacement — close it by hand" >&2
    fi
  done
  LOST_REVIEWS=""
}

examined=0; recorded=0; exceptions=0; escalated=0; held=0; skipped=0; rearmed=0
retired=0

while IFS= read -r row; do
  [ -n "$row" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  [ -n "$id" ] || continue
  phase=$(printf '%s' "$row" | jq -r '.phase // empty')
  checkset=$(printf '%s' "$row" | jq -r '.checkset // empty')
  branch=$(printf '%s' "$row" | jq -r '.branch // empty')
  pr=$(printf '%s' "$row" | jq -r '.pr // empty')
  hold=$(printf '%s' "$row" | jq -r '.hold // empty')
  routed=$(printf '%s' "$row" | jq -r '.routed // empty')

  gates=$(gate_members "$checkset")
  if [ -z "$gates" ]; then
    # A gateless anchor (the `none`/`off` sentinel, or an `approval`-only set) has
    # no marker-backed gate to hold, so there is no verdict to record. NOT an
    # error: gateless-by-choice is a supported configuration, and an EMPTY
    # check_set is check-set-heal.sh's business, not this pass's.
    skipped=$((skipped + 1)); continue
  fi

  # The live head. Post-open it is the PR head; pre-open it is the branch head.
  # Unresolvable means we cannot bind a verdict to anything: skip, retry next wake.
  head=""
  case "$phase" in
    pull_request) [ -n "$pr" ] && head=$(head_of_pr "$pr") ;;
    pre_open_gate) [ -n "$branch" ] && head=$(head_of_branch "$branch") ;;
  esac
  if [ -z "$head" ]; then
    echo "reconcile-gate-verdicts: $id — live head unresolved (phase=$phase, pr='${pr:-none}', branch='${branch:-none}'); skipped (retry next wake)" >&2
    skipped=$((skipped + 1)); continue
  fi

  examined=$((examined + 1))

  # The anchor's remediation children — the rounds spent on this gate, read from
  # the edge and the marker the shipped signoff round cap uses
  # (`source_review_bead`, stamped on every rework child the signoff files).
  #
  # COMPLETED rounds only: a child that is still OPEN is a round IN FLIGHT, and a
  # round in flight has not been spent. The design fixes the increment on the
  # child's CLOSE ("when a remediation child closes unresolved, the gate increments
  # attempts", specs/tk-zgse0.2/merge-gate-exception-lifecycle.md §"The exception
  # arm"), and the operational lifecycle agrees: a rework child closes at hand-back
  # as landed-on-branch (docs/work-bead-state-machine.md §"Rework is a new child"),
  # so every finished round really does close and the bound still bites. Counting
  # an open child as spent brings the cap forward by one whole round — at MAX=3,
  # two closed rounds plus a live third reads as exhausted — and converts a state a
  # worker is actively fixing into an exception, which is TERMINAL until an
  # operator acts. That is the one direction this arm must never fail in: it
  # replaces a converging state with a held one.
  #
  # Unreadable is NOT zero: zero would read as "no rounds spent" and could only
  # ever make this pass quieter, but it also feeds the R11 cap, and a cap fed a
  # wrong count is a verdict recorded on a fiction. Skip the anchor instead.
  kids=$(bd_pinned dep list "$id" --direction=up -t parent-child --json 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037')
  if ! printf '%s' "$kids" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "reconcile-gate-verdicts: $id — child list unreadable; skipped (retry next wake)" >&2
    skipped=$((skipped + 1)); continue
  fi
  attempts=$(printf '%s' "$kids" \
    | jq '[.[] | select(.metadata.source_review_bead != null)
                | select(((.status // "") | ascii_downcase) == "closed")] | length' 2>/dev/null)
  case "$attempts" in ''|*[!0-9]*) attempts=0 ;; esac
  open_kids=$(printf '%s' "$kids" \
    | jq '[.[] | select(((.status // "") | ascii_downcase) != "closed")] | length' 2>/dev/null)
  case "$open_kids" in ''|*[!0-9]*) open_kids=0 ;; esac

  # The gate's own dispatch: the review beads that carry this anchor. Keyed on
  # `anchor_bead`, which every signoff dispatch stamps atomically with the review's
  # routing fields precisely so the anchor is resolvable without walking edges.
  reviews=$(bd_pinned list --metadata-field "anchor_bead=$id" --all --limit=0 --json 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037')
  printf '%s' "$reviews" | jq -e 'type == "array"' >/dev/null 2>&1 || reviews="[]"

  while IFS= read -r gate; do
    [ -n "$gate" ] || continue
    marker=$(printf '%s' "$row" | jq -r --arg k "check.$gate" '.meta[$k] // ""')
    verdict=$(gate_verdict "$marker" "$head")

    # OK at the live head: the merge skill's business, not ours.
    [ "$verdict" = "ok" ] && continue

    # Already recorded as an exception AT THIS HEAD. The verdict is terminal until
    # the head moves, so there is nothing left to decide — but there may still be
    # something OWED: the escalation. The guard below is stamped only when a mail
    # actually goes out, and two ordinary paths leave it unstamped on purpose — a
    # `merge_hold` that suppressed the notification, and a mail that simply failed.
    # Returning here without re-checking it would make both permanent: the anchor
    # would carry a recorded exception that no operator was ever told about, held
    # forever, which is the silent hold this arm exists to end wearing the arm's own
    # marker. So fall THROUGH to the shared escalation block with the reason the
    # earlier pass recorded, and skip only the re-record.
    RECORD_NEEDED=1
    reason=""
    if [ "$verdict" = "exception" ]; then
      RECORD_NEEDED=""
      reason=$(printf '%s' "$row" | jq -r --arg k "check.$gate.reason" '.meta[$k] // ""')
      [ -n "$reason" ] || reason="recorded by an earlier pass (no reason stored)"
    fi

    # An exception marker left over from a PREVIOUS head. The verdict is not
    # `exception` on this path — that case cleared RECORD_NEEDED above — so any
    # exception marker still here is necessarily bound to some other head.
    STALE_EXCEPTION=""
    if [ -n "$RECORD_NEEDED" ]; then
      case "$marker" in
        "$GATE_VERB_EXCEPTION"@*) STALE_EXCEPTION=1 ;;
      esac
    fi

    # -----------------------------------------------------------------------
    # The DEAD REVIEWS behind this gate. Found ONCE, here, and used for two
    # different things: condemnation (R12b below, conditionally) and RETIREMENT
    # (always — see `retire_lost_reviews`).
    #
    # A review is dead when all three hold: it is open/in_progress, its assignee is
    # answered by NO live session, and it has been untouched for longer than the
    # deadline. An unassigned or freshly-touched review is in flight, and a live
    # assignee is a slow reviewer, not a dead one. Disabled outright when the roster
    # could not be read — an unreadable roster makes every assignee look dead, and
    # this arm mails an operator.
    #
    # The clock is `heartbeat_at` where the bead carries one, falling back to
    # updated_at then created_at. A claimed bead's heartbeat is stamped by the
    # session holding it, so its age measures how long since the WORKER was last
    # alive — which is the question. `updated_at` moves only when the bead is
    # WRITTEN, so a reviewer thinking hard about a large diff looks identical to a
    # reviewer whose session died an hour ago. Both are kept because a review that
    # was never claimed carries no heartbeat at all, and it must still be timed
    # rather than exempted.
    #
    # ALL of them, not the first. The scan used to stop at the first match, so a
    # second dead review stayed open and condemned the NEXT head on its own — the
    # same poisoning, one bead over. And a review already carrying
    # `gate_verdict_condemned` is skipped outright: it has had its one condemnation.
    # -----------------------------------------------------------------------
    LOST_REVIEWS=""
    LOST_REASON=""
    if [ -n "$ROSTER_READABLE" ]; then
      lost=$(printf '%s' "$reviews" | jq -r --arg g "$gate" '
        .[]
        | select(((.status // "") | ascii_downcase) != "closed")
        | select(((.metadata.check_name // "codex")) == $g)
        | select(((.metadata.gate_verdict_condemned // "") | tostring) == "")
        | select(((.assignee // "") | length) > 0)
        | [ .id, (.assignee // ""),
            (.heartbeat_at // .updated_at // .created_at // "") ]
        | @tsv' 2>/dev/null)
      while IFS=$'\t' read -r rid rassignee rts; do
        [ -n "$rid" ] || continue
        answered_by_live_session "$rassignee" && continue
        age=$(ts_age "$rts")
        [ -n "$age" ] || continue
        [ "$age" -gt "$GATE_DEADLINE" ] || continue
        LOST_REVIEWS="${LOST_REVIEWS:+$LOST_REVIEWS }$rid"
        [ -n "$LOST_REASON" ] \
          || LOST_REASON="worker-lost: review $rid held by '$rassignee' (no live session answers it) and untouched for ${age}s > ${GATE_DEADLINE}s deadline"
      done <<EOF
$lost
EOF
    fi

    # Already excepted AT THIS HEAD: nothing left to decide, so any dead review
    # still open under it is the residue of that same exception. Retire it now —
    # this is the legacy shape (an exception recorded before this arm retired
    # anything) and leaving it open is what strands the branch after the head
    # finally moves, with check-set-heal.sh reading a corpse as work in flight.
    [ -n "$RECORD_NEEDED" ] || retire_lost_reviews "$id" "$gate" "$head"

    # -----------------------------------------------------------------------
    # Which non-OK verdict is this? Checked in the order the design fixes: the
    # two exception triggers first, because they are TERMINAL and must not be
    # overwritten by the fixable record, and R12 before R11 because a dead worker
    # is a truer account of the hold than an exhausted round count that only
    # LOOKS exhausted because the rounds died rather than converged.
    # -----------------------------------------------------------------------
    if [ -n "$RECORD_NEEDED" ]; then

      # R12a — the marker exists but names no verb this contract knows. The gate
      # recorded something no reader can map: exception by definition of totality.
      [ "$verdict" = "unmappable" ] && reason="unmappable-marker: check.$gate='$marker' names no known verdict verb"

      # R12b — a dispatched review whose worker is GONE, scanned for above.
      #
      # SUPPRESSED while an exception marker from a PREVIOUS head is still on the
      # anchor, and that is the whole of the head-binding this arm can have. A review
      # bead records no dispatch head, so "was this review dispatched FOR the live
      # head?" is not directly answerable — but under a stale `exception@<old>` it is
      # answerable in the negative, and provably so pre-open: check-set-heal.sh's
      # `marker_blocks_dispatch` skips its dispatch on `exception@*`, so nothing can
      # have dispatched a review for the current head while that marker sat there.
      # Such a review is residue of the OLD head's exception. Condemning the new head
      # with it re-stamps `exception@<new>` before the pre-open re-arm below can clear
      # anything — the head move is consumed and the gate never re-arms, so the
      # operator escape the design specifies ("fix the branch, let the head move")
      # silently does not exist. Post-open the same residue can stamp exception over
      # a genuine re-review that reconcile-merged-prs.sh dispatched at the new head.
      #
      # Suppressing only DEFERS: the residue is retired below, so the next wake sees
      # a gate with nothing dead under it and judges it fresh. And the direction is
      # the safe one — an un-recorded exception under-reports a hold that the marker
      # keeps holding anyway, while a wrongly-recorded one is terminal until a human
      # acts.
      if [ -z "$reason" ] && [ -n "$LOST_REASON" ] && [ -z "$STALE_EXCEPTION" ]; then
        reason="$LOST_REASON"
      fi

      # R11 — bounded remediation exhaustion. The rounds are spent and the gate is
      # still not green, so re-spawning again is the non-convergent move this bound
      # exists to rule out.
      #
      # NOTHING IN FLIGHT is part of "spent", and it is a second guard rather than a
      # restatement of the closed-only count above. The count answers "how many
      # rounds finished"; this answers "is one running right now" — and the two come
      # apart in a state that is reachable whenever a child is filed outside the
      # signoff cap's accounting (a hand-filed rework, a re-dispatch that raced it):
      # MAX closed rounds AND an open child. There the count alone says exhausted
      # while a worker is mid-fix, and an exception recorded over live remediation
      # is terminal until an operator acts. Exhaustion is a statement about a gate
      # with nothing left coming; while a child is open something is still coming,
      # so the gate stays `fixable` (recorded below) and the cap bites on the wake
      # after that child closes. Deferring costs one idle wake; firing early costs
      # the round the bound was still allowing.
      #
      # SUPPRESSED UNDER A STALE EXCEPTION, for the same reason R12b is and with
      # the same consequence if it is not (tk-mf3em). The round count is
      # deliberately NOT head-bound (see this file's header), so once it reaches
      # the cap it stays there for every later head — and an unguarded R11 then
      # re-stamps `exception@<new head>` on the very wake that was supposed to
      # re-arm the gate. The `reason` it sets skips the whole `-z "$reason"`
      # block below, which is where BOTH re-arms live: the pre-open clear here,
      # and (post-open) leaving the marker stale so reconcile-merged-prs.sh's
      # stale-gate arm can read it as stale and dispatch a re-review. So the head
      # move is consumed either way and the escape the design specifies —
      # "the operator fixes the branch, the head advances, the gate re-evaluates
      # fresh" (specs/tk-zgse0.2/merge-gate-exception-lifecycle.md, AE-WS4-2) —
      # does not exist: exception becomes terminal FULL STOP rather than
      # terminal-until-operator.
      #
      # Suppressing only DEFERS, and keeps the bound. The count is not reset — a
      # head move buys ONE honest evaluation at the new head, not a clean slate.
      # If that round also fails and closes, `attempts` grows and the marker by
      # then is `fixable@<new head>` or absent rather than a stale exception, so
      # this arm fires normally and the gate is terminal at the new head. Nothing
      # here can loop: past the cap no rework child is filed, so only an operator
      # moves the head.
      if [ -z "$reason" ] && [ -z "$STALE_EXCEPTION" ] && [ "$open_kids" -eq 0 ] \
         && [ "$attempts" -ge "$MAX_ATTEMPTS" ] && [ "$MAX_ATTEMPTS" -gt 0 ]; then
        reason="attempts-exhausted: $attempts remediation round(s) spent against a cap of $MAX_ATTEMPTS with check.$gate still not green"
      fi

      if [ -z "$reason" ]; then
        # No exception will be recorded this pass, so nothing downstream is going to
        # act on the dead reviews found above. Retire them here instead: whether they
        # were suppressed as residue of an older head's exception or simply lost the
        # race to a `fixable` record, leaving one open is what makes check-set-heal.sh
        # read a corpse as a signoff in flight and withhold the dispatch forever.
        retire_lost_reviews "$id" "$gate" "$head"

        # Not an exception. Record the non-terminal verdict so the gate's state is a
        # pure read rather than an inference from open children — but ONLY where it
        # is true: `fixable` means the skill found addressable problems and
        # remediation is in flight, which is observable as an open child. With no
        # open child the gate is UNEVALUATED (never run, or re-armed by a head move),
        # and stamping fixable there would assert a finding nobody made — a verdict
        # standing in for the absence of one, which is what makes the gate's state an
        # inference again rather than the pure read this record exists to give.
        if [ "$open_kids" -gt 0 ] && [ "$marker" != "$GATE_VERB_FIXABLE@$head" ]; then
          if apply "record check.$gate=fixable@$head on $id ($open_kids open remediation child(ren))" \
               "$id" --set-metadata "check.$gate=$GATE_VERB_FIXABLE@$head"; then
            echo "reconcile-gate-verdicts: $id — check.$gate recorded fixable@$head ($open_kids open remediation child(ren), $attempts round(s) spent)"
            recorded=$((recorded + 1))
          fi
          continue
        fi

        # -------------------------------------------------------------------
        # PRE-OPEN RE-ARM. The gate is Unevaluated with nothing in flight, but a
        # marker from a PREVIOUS head is still sitting on the anchor — and two of
        # the verbs it can carry make check-set-heal.sh skip the dispatch that
        # would raise the gate:
        #
        #   green@<old>      "satisfiable, no dispatch from here"
        #   exception@<old>  "terminal until an operator acts"
        #
        # Both readings are true only AT THE HEAD THE MARKER NAMES, and
        # check-set-heal is bead-side: it resolves no head, so it cannot tell a
        # current verdict from residue. Post-open that gap is closed by
        # reconcile-merged-prs.sh's stale-marker arm, which reads the live PR head
        # and files a re-review. Pre-open there IS no PR, that arm enumerates
        # `merge_result=pull_request` only, and no other pass re-arms the gate — so
        # the residue is terminal in the literal sense: check-set-heal skips
        # forever, pre-open-resolve.sh opens only on green@<live branch head> and so
        # never opens, and the branch sits held with nothing left to move it. That
        # is exactly the silent indefinite hold this file exists to end, reached
        # through the verb meant to describe a hold an operator can lift: the
        # operator lifts it — fixes the branch, moves the head — and the lift has no
        # effect, because the datum that was supposed to go stale still reads as
        # authoritative to the one pass that dispatches.
        #
        # So clear it. The design already says this is the state transition: a head
        # move drops OK, fixable and exception alike back to Unevaluated
        # (specs/tk-zgse0.2/merge-gate-exception-lifecycle.md §"The verdict
        # lifecycle"), and Unevaluated with no marker is precisely what check-set-heal
        # dispatches on. The dispatch lands on the NEXT idle wake, because this pass
        # runs after check-set-heal in the patrol — convergent, one wake later.
        #
        # This can only HOLD HARDER, never merge or open: an absent marker is not
        # green at any head, so merge-skill.sh and pre-open-resolve.sh both keep
        # refusing. The pass's safety invariant is intact.
        #
        # Only the two BLOCKING verbs are cleared, and only with nothing in flight:
        #   * `fixable@<old>` does not block check-set-heal, so it strands nothing;
        #     leaving it lets the record above overwrite it at the live head.
        #   * With an open child the fixable record IS the re-arm — it replaces the
        #     stale marker in the same pass — which is why that arm returns above.
        # KEEP THIS VERB LIST IN SYNC with `marker_blocks_dispatch` in
        # check-set-heal.sh: a verb added to that skip list is a verb that strands a
        # pre-open branch when it goes stale, and it belongs here the same day.
        #
        # That predicate blocks a THIRD class this arm deliberately does not clear:
        # an UNMAPPABLE marker (one naming no verb at all), which check-set-heal
        # stops dispatching on as of review tk-i688b so that no review can be queued
        # in the window before this pass records its exception. It needs no clearing
        # here because it can never reach this branch: `gate_verdict` answers
        # `unmappable` for such a marker at EVERY head — the verb is unreadable, so
        # there is no oid comparison to go stale — and that verdict is routed to the
        # exception arm above, which replaces it with `exception@<live head>` in this
        # same pass. From there it is an ordinary stale exception, and the two-verb
        # list above is what re-arms it. So an unmappable marker is terminal for one
        # wake, not forever, and it leaves this file wearing a verb this arm knows.
        #
        # The head-bound COMPANIONS are deliberately left alone. `.exception_escalated`
        # is compared for equality against the live head, so a stale one never
        # matches and re-arms itself; `.reason` is read only on the
        # already-excepted-at-this-head path, which an absent marker cannot reach;
        # and `.attempts` is a record of rounds spent, not a head-bound bound (see
        # the divergence note in this file's header) — clearing it on a head move
        # would reset the very count R11 needs to keep across moving heads.
        if [ "$phase" = "pre_open_gate" ]; then
          case "$marker" in
            "$GATE_VERB_OK"@*|"$GATE_VERB_EXCEPTION"@*)
              if apply "clear stale check.$gate='$marker' on $id (branch head is now $head; re-arms the gate to unevaluated so check-set-heal can dispatch)" \
                   "$id" --unset-metadata "check.$gate"; then
                echo "reconcile-gate-verdicts: $id — check.$gate was '$marker' but the branch head is $head; cleared (pre-open re-arm, gate back to unevaluated for a fresh dispatch)"
                rearmed=$((rearmed + 1))
              else
                echo "reconcile-gate-verdicts: $id — could not clear stale check.$gate='$marker'; the pre-open gate stays blocked, retry next wake" >&2
              fi
              ;;
          esac
        fi
        continue
      fi

      # -----------------------------------------------------------------------
      # EXCEPTION. Three actions, in the order the design fixes them, mirroring the
      # stale-base arm's hold + file-child with "escalate" where it files:
      #   1. RECORD the verdict, with its reason. This is what holds the merge —
      #      the verb is not `green`.
      #   2. HOLD the convoy OPEN. merge_result is untouched, so the anchor stays
      #      the single gating locus and a later green head still has a lander.
      #      There is no auto-fix: an exception has no mechanical remedy, which is
      #      exactly what makes it one.
      #   3. ESCALATE once per head.
      # -----------------------------------------------------------------------
      if ! apply "record check.$gate=exception@$head on $id ($reason)" \
           "$id" \
           --set-metadata "check.$gate=$GATE_VERB_EXCEPTION@$head" \
           --set-metadata "check.$gate.reason=$reason" \
           --set-metadata "check.$gate.attempts=$attempts@$head"; then
        echo "reconcile-gate-verdicts: $id — could not record check.$gate=exception@$head; retry next wake" >&2
        skipped=$((skipped + 1)); continue
      fi
      # READ THE VERDICT BACK before escalating. `gc bd update` reporting success is
      # not proof the write is durable, and an escalation over an unrecorded verdict
      # sends an operator to an anchor whose state does not mention the problem —
      # while the one-per-head guard, stamped next, would suppress every retry.
      if [ "$DRY_RUN" != 1 ]; then
        back=$(bd_pinned show "$id" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037' \
          | jq -r --arg k "check.$gate" '.[0].metadata[$k] // empty' 2>/dev/null)
        if [ "$back" != "$GATE_VERB_EXCEPTION@$head" ]; then
          echo "reconcile-gate-verdicts: $id — check.$gate=exception@$head did not stick (read back '${back:-none}'); NOT escalating over an unrecorded verdict, retry next wake" >&2
          skipped=$((skipped + 1)); continue
        fi
      fi
      exceptions=$((exceptions + 1))
      echo "reconcile-gate-verdicts: $id — check.$gate EXCEPTION at $head ($reason)"

      # RETIRE the dead reviews this verdict was derived from, now that the verdict
      # is recorded and read back. They have spent their one condemnation; leaving
      # one open would let it condemn the NEXT head too — consuming the head move
      # that is supposed to re-arm this exception — and would keep check-set-heal.sh
      # from dispatching the replacement once it does re-arm.
      #
      # AFTER the record, not before, though the safety argument does not depend on
      # the order (see `retire_lost_reviews`: off the OK path the marker holds the
      # merge either way). What the order buys is the RETRY: a record that failed to
      # stick left the loop above via `continue`, so the reviews are still un-retired
      # and the next wake re-derives the same condemnation instead of finding the
      # evidence already swept away.
      retire_lost_reviews "$id" "$gate" "$head"
    fi

    # -----------------------------------------------------------------------
    # ESCALATE ONCE PER HEAD. Reached on BOTH paths — the exception recorded just
    # above, and one an earlier pass recorded that is still current at this head —
    # because the guard is stamped only when a mail actually goes out. Two ordinary
    # paths leave it unstamped (a `merge_hold` that suppressed the notification, and
    # a mail that failed), and both are transient: the hold lifts, the mail
    # succeeds. Only re-checking the guard on every pass lets either recover.
    # -----------------------------------------------------------------------
    esc=$(printf '%s' "$row" | jq -r --arg k "check.$gate.exception_escalated" '.meta[$k] // ""')
    if [ "$esc" = "$head" ]; then
      held=$((held + 1)); continue
    fi
    # An operator gate is a deliberate park. Recording the verdict on a parked
    # anchor is fine — it only holds harder — but MAILING about it is noise the
    # operator already answered by parking it. The next wake after the hold lifts
    # escalates, because the guard below was never stamped.
    if is_held "$hold"; then
      echo "reconcile-gate-verdicts: $id — check.$gate exception recorded but merge_hold is set (operator gate); not escalating"
      held=$((held + 1)); continue
    fi
    # Already routed to a human by another writer (the signoff round cap does this
    # at the cap). The anchor is in front of an operator; a second mail adds noise,
    # not information. The verdict record above is the part that was missing.
    if [ "$routed" = "human" ]; then
      echo "reconcile-gate-verdicts: $id — check.$gate exception recorded; already routed to human by another pass, not re-escalating"
      held=$((held + 1)); continue
    fi

    if [ "$DRY_RUN" = 1 ]; then
      echo "reconcile-gate-verdicts: [dry-run] would escalate $id check.$gate exception to the operator and stamp the one-per-head guard"
      escalated=$((escalated + 1)); continue
    fi

    case "$phase" in
      pull_request) target="PR#$pr" ;;
      *)            target="branch ${branch:-unknown} (pre-open, no PR yet)" ;;
    esac
    if gc mail send mayor/ -s "ESCALATION: merge gate '$gate' held in exception on $id" \
         -m "Anchor: $id
Target: $target
Gate: $gate
Head: $head
Verdict: exception
Reason: $reason
Rounds spent: $attempts (cap $MAX_ATTEMPTS)

The gate cannot be turned into pass-or-fixable by any automated path, so the
anchor is HELD: check.$gate=exception@$head is not green, and merge-skill.sh
merges only while every declared gate is green at the live head. Nothing will
re-spawn remediation for it.

This is terminal until the input genuinely changes. Fix the branch (or the
underlying gate skill/infrastructure) and let the head move: every head-bound
datum — the marker, the round count, this escalation guard — goes stale at
once and the gate re-evaluates fresh against the new head." 2>/dev/null; then
      apply "stamp the one-per-head escalation guard on $id" \
        "$id" --set-metadata "check.$gate.exception_escalated=$head" \
        || echo "reconcile-gate-verdicts: $id — escalated but could not stamp check.$gate.exception_escalated=$head; the next wake may re-mail" >&2
      escalated=$((escalated + 1))
    else
      echo "reconcile-gate-verdicts: $id — could not mail the operator about check.$gate; guard NOT stamped, retry next wake" >&2
    fi
  done <<EOF
$gates
EOF
done <<EOF
$ROWS
EOF

echo "reconcile-gate-verdicts: $examined anchor(s) examined, $recorded fixable verdict(s) recorded, $exceptions exception(s) recorded, $escalated escalated, $held held, $rearmed pre-open gate(s) re-armed, $retired dead review(s) retired, $skipped skipped"
exit 0
