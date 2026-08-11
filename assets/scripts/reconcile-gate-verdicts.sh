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
# WHAT THIS PASS IS FOR — two gates that hold FOREVER with nothing to raise them:
#
#   R11  bounded remediation exhaustion. A gate that has burned its remediation
#        rounds keeps filing rework children that keep not converging. The signoff
#        round cap (template-fragments/polecat-non-impl-done.template.md,
#        `signoff-round-cap`) already stops the SPAWNING at the cap and routes the
#        anchor to a human — but it records no verdict, so the anchor's own state
#        never says WHY it is held, and the cap only fires on a round that actually
#        reaches a reviewer. This pass records the verdict, and reaches the rounds
#        the fragment never saw.
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
# So the bound is counted the way the shipped round cap counts it — remediation
# children of the anchor, all statuses, because a closed child is a COMPLETED round
# — and it is the ESCALATION that is head-bound, which is what the doc's
# one-per-head rule is actually protecting against (notification spam). The head is
# still stamped alongside the count, so `attempts=<n>@<sha>` reads as "n rounds
# spent, observed at this head".
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
  printf '%s\n' "$ROSTER" | grep -qxF -- "$1"
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

examined=0; recorded=0; exceptions=0; escalated=0; held=0; skipped=0

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

  # The anchor's remediation children — every round spent on this gate, all
  # statuses, because a CLOSED child is a COMPLETED round. This is the bound the
  # shipped signoff round cap counts, read from the same edge and the same marker
  # (`source_review_bead`, stamped on every rework child the signoff files).
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
    | jq '[.[] | select(.metadata.source_review_bead != null)] | length' 2>/dev/null)
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

      # R12b — a dispatched review whose worker is GONE. Open/in_progress, untouched
      # for longer than the deadline, and assigned to an address no live session
      # answers to. All three are required: an unassigned or freshly-touched review is
      # in flight, and a live assignee is a slow reviewer, not a dead one. Disabled
      # outright when the roster could not be read.
      #
      # The clock is `heartbeat_at` where the bead carries one, falling back to
      # updated_at then created_at. A claimed bead's heartbeat is stamped by the
      # session holding it, so its age measures how long since the WORKER was last
      # alive — which is the question. `updated_at` moves only when the bead is
      # WRITTEN, so a reviewer thinking hard about a large diff looks identical to a
      # reviewer whose session died an hour ago. Both are kept because a review that
      # was never claimed carries no heartbeat at all, and it must still be timed
      # rather than exempted.
      if [ -z "$reason" ] && [ -n "$ROSTER_READABLE" ]; then
        lost=$(printf '%s' "$reviews" | jq -r --arg g "$gate" '
          .[]
          | select(((.status // "") | ascii_downcase) != "closed")
          | select(((.metadata.check_name // "codex")) == $g)
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
          reason="worker-lost: review $rid held by '$rassignee' (no live session answers it) and untouched for ${age}s > ${GATE_DEADLINE}s deadline"
          break
        done <<EOF
$lost
EOF
      fi

      # R11 — bounded remediation exhaustion. The rounds are spent and the gate is
      # still not green, so re-spawning again is the non-convergent move this bound
      # exists to rule out.
      if [ -z "$reason" ] && [ "$attempts" -ge "$MAX_ATTEMPTS" ] && [ "$MAX_ATTEMPTS" -gt 0 ]; then
        reason="attempts-exhausted: $attempts remediation round(s) spent against a cap of $MAX_ATTEMPTS with check.$gate still not green"
      fi

      if [ -z "$reason" ]; then
        # Not an exception. Record the non-terminal verdict so the gate's state is a
        # pure read rather than an inference from open children — but ONLY where it
        # is true: `fixable` means the skill found addressable problems and
        # remediation is in flight, which is observable as an open child. With no
        # open child the gate is UNEVALUATED (never run, or re-armed by a head move),
        # and stamping fixable there would assert a finding nobody made — and would
        # tell check-set-heal.sh that a gate with nothing in flight needs no
        # dispatch, which is the indefinite hold this file exists to end.
        if [ "$open_kids" -gt 0 ] && [ "$marker" != "$GATE_VERB_FIXABLE@$head" ]; then
          if apply "record check.$gate=fixable@$head on $id ($open_kids open remediation child(ren))" \
               "$id" --set-metadata "check.$gate=$GATE_VERB_FIXABLE@$head"; then
            echo "reconcile-gate-verdicts: $id — check.$gate recorded fixable@$head ($open_kids open remediation child(ren), $attempts round(s) spent)"
            recorded=$((recorded + 1))
          fi
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

echo "reconcile-gate-verdicts: $examined anchor(s) examined, $recorded fixable verdict(s) recorded, $exceptions exception(s) recorded, $escalated escalated, $held held, $skipped skipped"
exit 0
