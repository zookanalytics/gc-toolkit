#!/usr/bin/env bash
# submit-and-exit — the mechanics of mol-polecat-work's terminal step: hand the
# pushed branch to the refinery (or release a run whose whole product is store
# work), close this session's step chain, and drain.
#
#   submit-and-exit.sh handoff --bead <work-bead> --base <base-branch> --refinery <address>
#                              --note "<what was implemented>" [--step-bead <id>]
#                              [--summary-file <file>] [--title "<anchor title>"]
#   submit-and-exit.sh store-only --bead <work-bead> --base <base-branch>
#                                 --record "<bead ids filed or routed>" --note "<what closes the bead>"
#                                 [--step-bead <id>]
#   submit-and-exit.sh anchor --bead <work-bead>
#
# `handoff` runs the stages in order and stops at the first that refuses:
#
#   branch-gate     CURRENT_BRANCH must equal metadata.branch (polecat/<bead> when
#                   unset, which it then records). The refinery merges
#                   metadata.branch, so a push from any other branch strands the bead.
#   target          the landing branch: a caller-set metadata.target wins, base
#                   fills in for fresh work, and a bead that names neither (or
#                   whose base is the branch being pushed) halts before the push.
#   auto-push-halt  metadata.auto_push=false releases the bead branch-ready, with
#                   no push and no handoff, and is a terminal exit.
#   push            push HEAD, verify origin holds it, then run the bring-current
#                   guard, which acts only on a merge-in child.
#   anchor          the open bead on this branch carrying a merge_result, when it
#                   is not the claimed bead: a rework or rebase child's PR is read
#                   off its anchor, so the summary and a retitle go there.
#   consume         the refinery handoff in three writes (below).
#   wake            wake and nudge the refinery.
#   chain-close     close this session's step beads forward.
#   release         detach and delete the local branch, after every durable write.
#
# Each stage also runs alone as a subcommand of the same name, taking the inputs
# the stages before it would have produced as options (--target, --anchor).
#
# The handoff takes three `gc bd update` calls. A single update that reassigns
# the bead off this session while it still holds it in_progress is refused by
# bd's claim guard (AssigneeNotStolen), and the refusal rolls back everything
# batched into the call. So the writes are: metadata and notes, which bypass the
# guard and clear the route while the status is still in_progress; then
# --status=open, accepted from the holder; then the plain --assignee, accepted
# once the bead is no longer in_progress. The state after the second write is
# open, still assigned here, and unrouted, which no pool's offer predicate sees.
# The same three writes release a bead at the auto_push=false halt and at the
# store-only exit, with an empty assignee.
#
# Every write that lets go of the bead also removes the claim's gc.session_id and
# gc.session_name. The witness resolves a bead's owner from gc.session_id ahead
# of the assignee, and the runtime's detached-handoff orphan sweep recovers a
# pool route from a pin left on an open, unassigned, unrouted bead that carries a
# branch record, so a pin left behind makes a handed-off or released bead read as
# orphaned work.
#
# The summary and a retitle are addressed to the anchor, which is not always the
# claimed bead. Written to a separate anchor they land before the handoff, on a
# bead this session does not hold, and a failure costs the PR a current body or
# title, never the handoff. On fresh work the summary rides the first handoff
# write and a retitle is a write of its own ahead of it, so a title bd refuses
# cannot roll the handoff back.
#
# The chain close runs only at a terminal exit (the handoff, the auto_push=false
# halt, the store-only exit) and closes forward, because each step blocks the
# next and bd refuses to close a blocked issue. It never closes
# workflow-finalize, which the control-dispatcher closes once submit-and-exit,
# its only blocker, closes last. The branch release runs after both the handoff
# and the chain close: it destroys the branch shape the gate asserts, so a death
# between the two would leave the submit step open with a write still owed.
#
# A missing step-close.sh stops every terminal exit before its drain, so the
# session stays up with the chain open rather than draining past it.
#
# Refusals that a human must answer go through escalate-hold-drain.sh, which
# files the visit, holds the submit-and-exit step, and drains, each only after
# the one before it landed.
#
# env: GC_ESCALATE_HOLD_DRAIN_TOOL, GC_STEP_CLOSE_TOOL and
#      GC_BRING_CURRENT_GUARD_TOOL replace the sibling scripts.
# exit: 0 handed off, halted branch-ready, or released (each drained) · 1 refused
#       (held and drained where a hold landed) · 2 usage
set -uo pipefail

PROG="submit-and-exit"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
EHD="${GC_ESCALATE_HOLD_DRAIN_TOOL:-$SCRIPTS_DIR/escalate-hold-drain.sh}"
STEP_CLOSE="${GC_STEP_CLOSE_TOOL:-$SCRIPTS_DIR/step-close.sh}"
BRING_CURRENT_GUARD="${GC_BRING_CURRENT_GUARD_TOOL:-$SCRIPTS_DIR/bring-current-guard.sh}"
STEP_REF="mol-polecat-work.submit-and-exit"
CHAIN_STEPS="load-context workspace-setup preflight-tests implement submit-and-exit"

usage() {
  cat >&2 <<'USAGE'
usage: submit-and-exit.sh handoff --bead <id> --base <branch> --refinery <address> --note <text>
                                  [--step-bead <id>] [--summary-file <file>] [--title <text>]
       submit-and-exit.sh store-only --bead <id> --base <branch> --record <ids> --note <text> [--step-bead <id>]
       submit-and-exit.sh anchor --bead <id>
       submit-and-exit.sh branch-gate|target|auto-push-halt|push|consume|wake|chain-close|release [options]

options: --bead --base --refinery --note --step-bead --summary-file --title --record
         --target (the landing branch the target stage resolves)
         --anchor (the gating anchor the anchor stage resolves)
USAGE
}

CMD="${1:-}"
[ -n "$CMD" ] || { usage; exit 2; }
shift
BEAD=""; BASE=""; REFINERY=""; NOTE=""; STEP_BEAD=""; SUMMARY_FILE=""; TITLE=""; RECORD=""
LANDING_TARGET=""; GATING_ANCHOR=""; CURRENT_BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bead|--base|--refinery|--note|--step-bead|--summary-file|--title|--record|--target|--anchor)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; usage; exit 2; }
      case "$1" in
        --bead)         BEAD="$2" ;;
        --base)         BASE="$2" ;;
        --refinery)     REFINERY="$2" ;;
        --note)         NOTE="$2" ;;
        --step-bead)    STEP_BEAD="$2" ;;
        --summary-file) SUMMARY_FILE="$2" ;;
        --title)        TITLE="$2" ;;
        --record)       RECORD="$2" ;;
        --target)       LANDING_TARGET="$2" ;;
        --anchor)       GATING_ANCHOR="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 2 ;;
    *) echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ -n "$BEAD" ] || { echo "$PROG: --bead is required" >&2; usage; exit 2; }

# hold_and_drain <key> <message> <reason> — the visit, the hold, the drain.
hold_and_drain() {
  "$EHD" --step "$STEP_REF" --bead "$STEP_BEAD" --reason "$3" \
         --subject "$BEAD" --key "$1" --message "$2"
}

branch_gate() {
  CURRENT_BRANCH=$(git branch --show-current)
  local bead_row metadata_branch expected gate_source pushed_ref halt_head halt_assignee
  bead_row=$(gc bd show "$BEAD" --json)
  metadata_branch=$(printf '%s' "$bead_row" | jq -r '.[0].metadata.branch // empty')
  if [ -n "$metadata_branch" ]; then
    expected="$metadata_branch"
    gate_source="metadata.branch"
  else
    expected="polecat/$BEAD"
    gate_source="polecat/<bead-id> convention (metadata.branch unset)"
  fi
  if [ -z "$CURRENT_BRANCH" ] || [ "$CURRENT_BRANCH" != "$expected" ]; then
    echo "BRANCH SHAPE GATE FAILED"
    echo "  current branch:  ${CURRENT_BRANCH:-<detached HEAD>}"
    echo "  expected branch: $expected"
    echo "  gate source:     $gate_source"
    echo "Refinery handoff merges metadata.branch; proceeding would strand the work."
    pushed_ref=$(git ls-remote origin "refs/heads/$expected" 2>/dev/null | awk '{print $1}')
    halt_head=$(git rev-parse HEAD 2>/dev/null || echo unknown)
    halt_assignee=$(printf '%s' "$bead_row" | jq -r '.[0].assignee // empty')
    if [ -n "$metadata_branch" ]; then
      echo "This bead already names its branch — check out '$expected' at the pushed head, then re-run submit-and-exit."
      echo "  origin/$expected: ${pushed_ref:-absent}"
      echo "  local HEAD:              $halt_head"
      echo "  bead assignee:           ${halt_assignee:-<unset>}"
    else
      echo "Re-run workspace-setup: create '$expected' from origin/$BASE, cherry-pick your commits, re-run submit-and-exit."
    fi
    hold_and_drain polecat-branch-shape \
      "Branch shape gate on $BEAD: on ${CURRENT_BRANCH:-detached HEAD}, expected $expected ($gate_source). The refinery merges metadata.branch, so the commits must be moved onto $expected before handoff. Held at submit-and-exit; nothing was pushed or closed." \
      "branch shape gate: on ${CURRENT_BRANCH:-detached HEAD}, expected $expected ($gate_source); move the commits onto $expected, then re-offer this molecule"
    return 1
  fi
  if [ -z "$metadata_branch" ]; then
    gc bd update "$BEAD" --set-metadata branch="$CURRENT_BRANCH"
  fi
}

resolve_target() {
  [ -n "$CURRENT_BRANCH" ] || CURRENT_BRANCH=$(git branch --show-current)
  local existing
  existing=$(gc bd show "$BEAD" --json | jq -r '.[0].metadata.target // empty')
  if [ -n "$existing" ]; then
    LANDING_TARGET="$existing"
  elif [ -n "$BASE" ] && [ "$BASE" != "$CURRENT_BRANCH" ]; then
    LANDING_TARGET="$BASE"
  else
    echo "TARGET RESOLUTION FAILED"
    echo "  metadata.target: <unset>"
    echo "  base_branch:     ${BASE:-<empty>}"
    echo "  current branch:  $CURRENT_BRANCH"
    echo "Nothing names a landing branch, and base_branch is empty or the branch being pushed — recording it would be a self-merge."
    echo "Set it, then re-run submit-and-exit:  gc bd update $BEAD --set-metadata target=<landing-branch>"
    hold_and_drain polecat-no-landing-target \
      "No landing branch for $BEAD: metadata.target is unset and base_branch is ${BASE:-empty}, so recording a target would be a self-merge. Set target on $BEAD. Held at submit-and-exit; nothing was pushed or closed." \
      "no landing branch: metadata.target is unset and base_branch is ${BASE:-empty}; set target on $BEAD, then re-offer this molecule"
    return 1
  fi
  echo "landing target: $LANDING_TARGET"
}

# require_target <where> — the consumers of LANDING_TARGET refuse to write an
# empty one: an empty metadata value round-trips as set-but-empty, its own strand.
require_target() {
  [ -n "$LANDING_TARGET" ] && return 0
  echo "LANDING_TARGET unset — run the target stage before $1."
  hold_and_drain polecat-landing-target-unset \
    "submit-and-exit reached $1 with LANDING_TARGET unset on $BEAD; the target stage did not run. Held at submit-and-exit; nothing was pushed or closed." \
    "submit-and-exit reached $1 with LANDING_TARGET unset; the target stage did not run"
  return 1
}

chain_close() {
  if [ ! -x "$STEP_CLOSE" ]; then
    echo "$PROG: step-close.sh not found at $STEP_CLOSE; close each step by its (gc.root_bead_id, gc.step_ref) pair, never by an id read from the environment" >&2
    return 1
  fi
  local step
  for step in $CHAIN_STEPS; do
    "$STEP_CLOSE" --step "mol-polecat-work.$step" --outcome pass || echo "step-close: mol-polecat-work.$step was not this session's to close — left for the finalizer"
  done
}

# Returns 0 when the bead does not opt out of the push. On auto_push=false it
# releases the bead branch-ready, closes the chain and drains: a terminal exit.
auto_push_halt() {
  local auto_push branch
  auto_push=$(gc bd show "$BEAD" --json | jq -r '.[0].metadata | if has("auto_push") then (.auto_push | tostring) else "" end')
  [ "$auto_push" = "false" ] || return 0
  echo "auto_push=false: halting at branch-ready (no push, no refinery handoff)"
  require_target "the auto_push halt arm" || exit 1
  branch=$(git branch --show-current)
  gc bd update "$BEAD" --set-metadata branch="$branch" --set-metadata target="$LANDING_TARGET" --set-metadata branch_ready=true --set-metadata halt_reason=auto_push_false --set-metadata gc.routed_to="" --unset-metadata gc.session_id --unset-metadata gc.session_name --append-notes "Branch ready: auto_push=false (no push, no refinery handoff)"
  gc bd update "$BEAD" --status=open
  gc bd update "$BEAD" --assignee=""
  chain_close || exit 1
  gc runtime drain-ack
  exit 0
}

push_branch() {
  [ -n "$CURRENT_BRANCH" ] || CURRENT_BRANCH=$(git branch --show-current)
  local pre_push_head remote_ref local_head
  # The origin head before this push: where the bring-current guard starts
  # reading when no resume recorded a start of its own.
  pre_push_head=$(git ls-remote origin "refs/heads/$CURRENT_BRANCH" 2>/dev/null | awk '{print $1}')
  if ! git push origin HEAD; then
    echo "PUSH FAILED — bead stays with polecat. A non-fast-forward rejection means the branch moved under you; re-fetch, MERGE origin in, and retry — never force-push (branches are brought current by merge, never rebase)."
    gc runtime drain-ack
    return 1
  fi
  remote_ref=$(git ls-remote origin "refs/heads/$CURRENT_BRANCH" 2>/dev/null | awk '{print $1}')
  local_head=$(git rev-parse HEAD)
  if [ -z "$remote_ref" ] || [ "$remote_ref" != "$local_head" ]; then
    echo "PUSH VERIFICATION FAILED: origin/$CURRENT_BRANCH (${remote_ref:-absent}) != local HEAD ($local_head). Aborting handoff."
    gc runtime drain-ack
    return 1
  fi
  if [ ! -x "$BRING_CURRENT_GUARD" ]; then
    echo "$PROG: bring-current-guard.sh not found at $BRING_CURRENT_GUARD; a merge-in child is not handed off without its guard" >&2
    gc runtime drain-ack
    return 1
  fi
  if ! "$BRING_CURRENT_GUARD" guard --bead "$BEAD" --to "$local_head" --from "${pre_push_head:-}"; then
    echo "BRING-CURRENT GUARD DID NOT FINISH: the push stands, but $BEAD is NOT handed off. It stays open, which holds any merge it gates, and the session that re-runs submit-and-exit retries the guard."
    gc runtime drain-ack
    return 1
  fi
}

# The query asks the branch, not the state name: every state that carries a
# merge_result is an anchor state. An empty branch (a detached HEAD) is never
# sent to --metadata-field, which would match every branchless bead, and an
# unreadable probe resolves to no anchor: degraded to the dispatch-text
# fallback, never stranded.
resolve_anchor() {
  [ -n "$CURRENT_BRANCH" ] || CURRENT_BRANCH=$(git branch --show-current)
  local rows
  GATING_ANCHOR=""
  if [ -n "$CURRENT_BRANCH" ]; then
    rows=$(gc bd list --status=open --metadata-field branch="$CURRENT_BRANCH" --limit=0 --json 2>/dev/null) || rows=""
    GATING_ANCHOR=$(printf '%s' "$rows" | jq -r --arg self "$BEAD" '
        [ .[]? | select(.id != $self)
          | select((((.metadata // {}).merge_result // "") | tostring) != "") ]
        | sort_by(.created_at // .created // .id) | .[0].id // empty' 2>/dev/null) || GATING_ANCHOR=""
  fi
  if [ -n "$GATING_ANCHOR" ]; then
    echo "gating anchor: $GATING_ANCHOR (this bead is a child; the summary goes there)"
  else
    echo "gating anchor: none other on this branch (the claimed bead is the anchor)"
  fi
}

consume() {
  require_target "the handoff" || return 1
  local roster bound pr_summary handoff_ok=0
  local -a handoff_meta
  # An empty binding prefix renders <rig>/refinery, an address no agent holds,
  # and the refinery's find-work is exact-match on assignee, so a bead sent
  # there is never read. The roster check fails closed on an address no agent
  # holds, and hands off unchecked when the roster cannot be read.
  roster=$(gc agent list --json 2>/dev/null | jq -r '.agents[]? | .qualified_name // empty | ., (split("/") | .[-1])' 2>/dev/null) || true
  if [ -z "$roster" ]; then
    echo "roster unreadable — handing off to $REFINERY unchecked"
  elif ! grep -qxF "$REFINERY" <<< "$roster"; then
    bound=$(grep 'refinery$' <<< "$roster" | sort -u | tr '[:space:]' ' ') || true
    echo "REFINERY ADDRESS NAMES NO AGENT: $REFINERY"
    echo "The refinery reads its queue by exact-match assignee, so a bead sent here is never seen and nothing reports it."
    echo "Bound refineries: $bound"
    gc runtime drain-ack
    return 1
  fi
  pr_summary=""
  if [ -n "$SUMMARY_FILE" ] && [ -s "$SUMMARY_FILE" ]; then pr_summary=$(cat "$SUMMARY_FILE"); fi
  handoff_meta=(--set-metadata target="$LANDING_TARGET" --set-metadata gc.routed_to="" --unset-metadata gc.session_id --unset-metadata gc.session_name)
  if [ -n "$pr_summary" ]; then
    if [ -n "$GATING_ANCHOR" ]; then
      gc bd update "$GATING_ANCHOR" --set-metadata pr_summary="$pr_summary" || echo "pr_summary did not reach anchor $GATING_ANCHOR; its PR body falls back to the dispatch text"
    else
      handoff_meta+=(--set-metadata pr_summary="$pr_summary")
    fi
  fi
  if [ -n "$(printf '%s' "$TITLE" | tr -d '[:space:]')" ]; then
    gc bd update "${GATING_ANCHOR:-$BEAD}" --title "$TITLE" || echo "the retitle did not reach ${GATING_ANCHOR:-$BEAD}; the PR title stays composed from the title it has"
  fi
  if gc bd update "$BEAD" "${handoff_meta[@]}" --append-notes "$NOTE" && gc bd update "$BEAD" --status=open && gc bd update "$BEAD" --assignee="$REFINERY"; then handoff_ok=1; fi
  if [ "$handoff_ok" != "1" ]; then
    echo "HANDOFF REFUSED: a gc bd update in the handoff exited non-zero and rolled itself back, so $BEAD is not open, assigned to $REFINERY, and unrouted. The branch is pushed; the step chain is NOT closed."
    hold_and_drain polecat-handoff-refused \
      "Refinery handoff for $BEAD was refused: a gc bd update exited non-zero and rolled back. The branch is pushed but the bead is not open+assigned to the refinery. Held at submit-and-exit; nothing was closed." \
      "refinery handoff refused: a gc bd update exited non-zero and rolled back; the branch is pushed but the bead is not handed off"
    return 1
  fi
  # Handed off, the summary has no further reader.
  [ -n "$SUMMARY_FILE" ] && rm -f "$SUMMARY_FILE"
  return 0
}

wake() {
  gc session wake "$REFINERY" || true
  gc session nudge "$REFINERY" "Run 'gc prime' to check merge queue and begin processing." || true
}

release_branch() {
  local branch
  branch=$(git branch --show-current)
  if [ -n "$branch" ]; then
    git checkout --detach && git branch -D "$branch" || echo "branch release failed: $branch stays checked out here. The handoff is already written, so this costs a held ref, nothing more."
  fi
  return 0
}

# The store-only exit releases the bead the way the halt arm does, minus the
# three fields that describe a branch, and refuses outright when the run has a
# diff to land, so a run that merely forgot to commit cannot park itself as
# store work.
store_only() {
  local ahead dirty pushed
  ahead=$(git rev-list --count "origin/$BASE..HEAD" 2>/dev/null || echo 0)
  dirty=$(git status --porcelain 2>/dev/null || true)
  pushed=$(git ls-remote origin "refs/heads/polecat/$BEAD" 2>/dev/null || true)
  if [ "${ahead:-0}" != "0" ] || [ -n "$dirty" ] || [ -n "$pushed" ]; then
    echo "STORE-ONLY EXIT REFUSED: this run has work to land"
    echo "  commits ahead of origin/$BASE: ${ahead:-0}"
    echo "  uncommitted changes: ${dirty:+yes}"
    echo "  branch already on origin: ${pushed:+polecat/$BEAD}"
    echo "Land it the normal way: submit-and-exit.sh handoff."
    echo "If none of it is yours, you are in the shared rig checkout rather than a per-bead worktree: mail the witness that fact instead of releasing the bead."
    gc runtime drain-ack
    exit 1
  fi
  gc bd update "$BEAD" --set-metadata halt_reason=store_only --set-metadata gc.routed_to="" --unset-metadata gc.session_id --unset-metadata gc.session_name --append-notes "Store-only exit: filed $RECORD. $NOTE"
  gc bd update "$BEAD" --status=open
  gc bd update "$BEAD" --assignee=""
  chain_close || exit 1
  gc runtime drain-ack
  exit 0
}

need() {
  local opt
  for opt in "$@"; do
    case "$opt" in
      --base)     [ -n "$BASE" ] ;;
      --refinery) [ -n "$REFINERY" ] ;;
      --note)     [ -n "$NOTE" ] ;;
      --record)   [ -n "$RECORD" ] ;;
    esac || { echo "$PROG: $CMD requires $opt" >&2; usage; exit 2; }
  done
}

case "$CMD" in
  handoff)
    need --base --refinery --note
    branch_gate || exit 1
    resolve_target || exit 1
    auto_push_halt
    push_branch || exit 1
    resolve_anchor
    consume || exit 1
    wake
    chain_close || exit 1
    release_branch
    gc runtime drain-ack
    ;;
  store-only)
    need --base --record --note
    store_only ;;
  anchor)
    resolve_anchor
    echo "anchor title: $(gc bd show "${GATING_ANCHOR:-$BEAD}" --json 2>/dev/null | jq -r '.[0].title // empty' 2>/dev/null)" ;;
  branch-gate)    branch_gate || exit 1 ;;
  target)         resolve_target || exit 1 ;;
  auto-push-halt) auto_push_halt ;;
  push)           push_branch || exit 1 ;;
  consume)        need --refinery --note; consume || exit 1 ;;
  wake)           need --refinery; wake ;;
  chain-close)    chain_close || exit 1 ;;
  release)        release_branch ;;
  *) echo "$PROG: unknown command '$CMD'" >&2; usage; exit 2 ;;
esac
