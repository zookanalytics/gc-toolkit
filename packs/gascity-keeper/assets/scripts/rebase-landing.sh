#!/usr/bin/env bash
# rebase-landing.sh — a finished gascity rebase lands by the operator's own
# force-push, which a human gate asks for, and a check once the gate clears
# records what the push did. No agent force-pushes the fork's main.
#
#   rebase-landing.sh ask    (--convoy <id> | --bead <id>)
#   rebase-landing.sh finish (--convoy <id> | --bead <id>)
#
# The bead is the rebase bead mol-upstream-gc-rebase worked: the one bead the
# run's input convoy tracks, or the bead --bead names. Its metadata carries what
# both verbs read, all stamped by that run: branch and target, pre_rebase_tip,
# and rebase_onto_sha, which only ask reads. The repository is the gascity rig's
# checkout, resolved the way the rebase run's workspace-setup resolves it.
#
# ask files the human gate on the bead, under the key rebase-landing, that asks
# the operator to land the rebase, assigns it to them, and arms the bead to run
# mol-upstream-gc-rebase-finish once the gate clears (await-ruling.sh). The
# gate's message carries the two commands the operator runs in the rig
# checkout: a range-diff that shows each fork commit beside its rebased form, and
# the push, whose lease is pinned to pre_rebase_tip resolved to a SHA, so git
# refuses a push onto a main that moved after the rebase.
#
# finish fetches origin in the rig checkout and compares origin/<target> with
# <branch>, the local branch the gate's push sends:
#   - the same commit: the rebase landed. The rig checkout is reset to it only
#     when it is on <target>, clean, still at the pre-rebase tip, and holds no
#     file git does not track where the landed tree puts one, and is otherwise
#     left alone with the reason in rig_update_result. The bead
#     closes with Gas City's work record of a landing (gc.work_outcome=shipped,
#     gc.work_commit, gc.work_branch) and rig_update_result in the same write,
#     and the keeper is mailed what landed.
#   - origin/<target> still at the pre-rebase tip: the push has not run, so the
#     operator is asked again, as ask asks.
#   - any other commit: main moved after the rebase, so the lease refused the
#     push or something else was pushed. The bead goes back to the keeper that
#     requested the rebase, else the rig's own keeper: assigned to it, with
#     aborted_at=race-loss and the three commits in its notes, and the keeper is
#     mailed with --notify, which requests its turn.
#
# gc-toolkit's scripts are read from the pack this sub-pack sits in, as
# rebase-check.sh reads run-lib.sh: the city imports this sub-pack from inside
# that pack's tree.
#
# Exit: 0 the outcome is recorded (ask: the gate asks and the bead is armed;
#       finish: the bead closed, is asked about again, or went to the keeper, or
#       it was closed already) · 1 a read, the fetch or a write did not land,
#       and nothing that landed needs undoing, since a re-run converges · 2 usage
set -uo pipefail

PROG="rebase-landing"
KEY="rebase-landing"
FINISH_FORMULA="mol-upstream-gc-rebase-finish"
RIG="gascity"
OPERATOR="human"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: rebase-landing.sh ask    (--convoy <id> | --bead <id>)
       rebase-landing.sh finish (--convoy <id> | --bead <id>)

  ask      file the gate that asks the operator to land the rebase, and arm
           the bead to run mol-upstream-gc-rebase-finish once it clears
  finish   check what the operator's push did, then close the bead, ask
           again, or hand the bead back to the keeper
  --convoy the run's input convoy, which tracks the rebase bead
  --bead   the rebase bead

exit: 0 the outcome is recorded · 1 a read, the fetch or a write did not land · 2 usage
USAGE
  exit 2
}

[ $# -eq 3 ] || usage
VERB=$1
case "$VERB" in ask|finish) ;; *) usage ;; esac
case "$2" in --convoy|--bead) ;; *) usage ;; esac
case "$3" in
  ''|*[!A-Za-z0-9._-]*)
    echo "$PROG: $2 takes one id of [A-Za-z0-9._-]; '$3' was passed" >&2; exit 2 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/../../../../assets/scripts" 2>/dev/null && pwd)" \
  || { echo "$PROG: gc-toolkit's scripts are not at $HERE/../../../../assets/scripts" >&2; exit 1; }
# shellcheck source=../../../../assets/scripts/bd-lib.sh
. "$KIT/bd-lib.sh" || { echo "$PROG: cannot source $KIT/bd-lib.sh" >&2; exit 1; }

if [ "$2" = --bead ]; then
  ISSUE=$3
else
  # The bead a run works is the one bead its input convoy tracks, which is how
  # Gas City hands a step its bead.
  CONVOY_JSON=$(gc convoy status "$3" --json </dev/null 2>/dev/null | scrub) \
    || { echo "$PROG: could not read convoy $3" >&2; exit 1; }
  ISSUE=$(printf '%s' "$CONVOY_JSON" | jq -r 'if (.children | length) == 1 then .children[0].id else empty end' 2>/dev/null)
  [ -n "$ISSUE" ] || { echo "$PROG: convoy $3 does not track exactly one bead" >&2; exit 1; }
fi

ROW=$(bd_json show "$ISSUE") || ROW=""
STATUS=$(printf '%s' "$ROW" | jq -r 'if type == "array" and length == 1 then (.[0].status // "") else empty end' 2>/dev/null)
[ -n "$STATUS" ] || { echo "$PROG: could not read $ISSUE" >&2; exit 1; }
BRANCH=$(row_meta "$ROW" branch)
TARGET=$(row_meta "$ROW" target)
PRE_TIP=$(row_meta "$ROW" pre_rebase_tip)
ONTO_TIP=$(row_meta "$ROW" rebase_onto_sha)
BACKUP=$(row_meta "$ROW" backup_ref)
KEEPER=$(row_meta "$ROW" requesting_keeper)
[ -n "$KEEPER" ] || KEEPER="$RIG/gascity-keeper.keeper"

short() { printf '%.12s' "$1"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# commit_of <rev> — the full sha of a commit in the rig checkout, or nothing.
commit_of() { git -C "$RIG_ROOT" rev-parse --verify --quiet "$1^{commit}" 2>/dev/null; }

need_facts() { # <what reads them> <names...>
  local who=$1 name missing=""
  shift
  for name in "$@"; do
    case "$name" in
      branch) [ -n "$BRANCH" ] || missing="$missing branch" ;;
      target) [ -n "$TARGET" ] || missing="$missing target" ;;
      pre_rebase_tip) [ -n "$PRE_TIP" ] || missing="$missing pre_rebase_tip" ;;
      rebase_onto_sha) [ -n "$ONTO_TIP" ] || missing="$missing rebase_onto_sha" ;;
    esac
  done
  [ -z "$missing" ] && return 0
  echo "$PROG: $ISSUE carries no${missing} in its metadata, which the rebase run stamps and $who reads; nothing was written" >&2
  exit 1
}

resolve_rig() {
  RIG_ROOT=$("$KIT/rig-root.sh" --rig "$RIG") && [ -n "$RIG_ROOT" ] \
    || { echo "$PROG: no single rig called $RIG resolves in gc rig list --json; nothing was written" >&2; exit 1; }
}

# ask_operator [<line>] — the landing gate and the arm behind it. A line given
# opens the message's body, after the title.
ask_operator() {
  local pre onto message gate
  pre=$(commit_of "$PRE_TIP") \
    || { echo "$PROG: pre_rebase_tip $PRE_TIP is no commit in $RIG_ROOT; nothing was written" >&2; exit 1; }
  onto=$(commit_of "$ONTO_TIP") \
    || { echo "$PROG: rebase_onto_sha $ONTO_TIP is no commit in $RIG_ROOT; nothing was written" >&2; exit 1; }
  commit_of "refs/heads/$BRANCH" >/dev/null \
    || { echo "$PROG: $RIG_ROOT has no branch $BRANCH for the operator to push; nothing was written" >&2; exit 1; }
  message="Land gascity rebase $ISSUE: review its range-diff, then force-push $BRANCH onto $TARGET
${1:+$1

}$ISSUE rebased the fork's $TARGET onto upstream at $(short "$onto"), passed its checks, and pushed the result to origin as $BRANCH.

Review it, each fork commit beside its rebased form:
  git -C $RIG_ROOT range-diff $onto $pre $BRANCH

Land it:
  git -C $RIG_ROOT push --force-with-lease=$TARGET:$pre origin $BRANCH:$TARGET

Then clear this gate. $ISSUE waits on it, and clearing it runs the landing check, which closes $ISSUE once $TARGET is the rebased tip and brings the rig checkout's $TARGET along when that is safe.

A refused push means $TARGET moved after the rebase. Clear this gate anyway: the landing check then hands $ISSUE back to the keeper, to redo the rebase or drop it.

To drop the rebase instead, do not clear this gate: run $KIT/stand-down.sh $ISSUE --key $KEY --ruling '<why>'."
  gate=$("$KIT/human-gate.sh" --subject "$ISSUE" --key "$KEY" --message "$message" | tail -n 1) && [ -n "$gate" ] \
    || { echo "$PROG: human-gate.sh filed no landing gate on $ISSUE" >&2; exit 1; }
  # The push is the operator's alone, so the gate is assigned to them (the
  # waits skill: an action only a named person performs).
  gc bd update "$gate" --assignee "$OPERATOR" </dev/null >/dev/null 2>&1 \
    || { echo "$PROG: gate $gate asks for the landing of $ISSUE, but the store refused its assignment to $OPERATOR" >&2; exit 1; }
  "$KIT/await-ruling.sh" "$ISSUE" --key "$KEY" --formula "$FINISH_FORMULA" >/dev/null \
    || { echo "$PROG: gate $gate asks for the landing of $ISSUE, but the arm behind it did not land" >&2; exit 1; }
  echo "$PROG: $ISSUE waits on gate $gate, assigned to $OPERATOR, for the push; clearing it runs $FINISH_FORMULA"
}

# sync_rig — bring the rig checkout's <target> to the landed commit when that
# discards nothing, into RIG_SYNC. A checkout with any change git status lists,
# or whose status cannot be read, is left for the operator, and so is a HEAD
# other than the pre-rebase tip, which can hold commits that were never pushed.
# git status lists no ignored file, and no untracked one under
# status.showUntrackedFiles=no, so the move is a checkout that refuses to
# overwrite any file git does not track, an ignored one included. It runs with
# hooks off, so it changes only the tree and the branch, and a post-checkout
# hook's exit cannot make a move that happened read as refused.
sync_rig() {
  local branch changes dirty=0 head refusal
  branch=$(git -C "$RIG_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
  if ! changes=$(git -C "$RIG_ROOT" status --porcelain 2>/dev/null); then
    RIG_SYNC="error: git status failed in $RIG_ROOT (operator must sync)"
    return 0
  fi
  [ -z "$changes" ] || dirty=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
  head=$(commit_of HEAD) || head=""
  if [ "$branch" != "$TARGET" ] || [ "$dirty" != 0 ]; then
    RIG_SYNC="skipped: branch=${branch:-unknown} dirty=$dirty (operator must sync)"
  elif [ "$head" = "$MAIN" ]; then
    RIG_SYNC="current: already at $(short "$MAIN")"
  elif [ "$head" != "$PRE" ]; then
    RIG_SYNC="skipped: HEAD=$(short "$head") does not match pre_rebase_tip=$(short "$PRE") (operator must sync)"
  elif ! refusal=$(git -C "$RIG_ROOT" -c core.hooksPath=/dev/null checkout -q --no-overwrite-ignore -B "$TARGET" "$MAIN" 2>&1 >/dev/null); then
    # git's error lines and the paths it names, on one line, without its advice.
    refusal=$(printf '%s\n' "$refusal" | awk '/^(Please |Aborting$|hint:)/ || NF == 0 { next } { $1 = $1; printf "%s%s", (n++ ? " " : ""), $0 }')
    RIG_SYNC="skipped: git checkout of origin/$TARGET refused in $RIG_ROOT: ${refusal:-git gave no reason} (operator must sync)"
  else
    # Only the records of worktrees whose directories are gone; a live worktree
    # finishes on its own base.
    git -C "$RIG_ROOT" worktree prune >/dev/null 2>&1
    RIG_SYNC="reset: $(short "$PRE") -> $(short "$MAIN") (worktree prune ran)"
  fi
}

landed() {
  sync_rig
  # Gas City's close gate reads the work record on the write that closes a task
  # bead, and finds the commit on origin/<target> in the rig checkout, which the
  # fetch above brought current.
  gc bd update "$ISSUE" --set-metadata gc.work_outcome=shipped --set-metadata gc.work_commit="$MAIN" \
    --set-metadata gc.work_branch="$TARGET" --set-metadata rig_update_result="$RIG_SYNC" \
    --status=closed --append-notes "Landed ($(now)): origin/$TARGET is $MAIN, the tip of $BRANCH, force-pushed by the operator with a lease on the pre-rebase tip $PRE. Rig checkout: $RIG_SYNC." \
    </dev/null >/dev/null 2>&1 \
    || { echo "$PROG: $ISSUE landed at $MAIN, but the store refused its landing record and close; rig checkout: $RIG_SYNC" >&2; exit 1; }
  # The close and its notes are the record, so a mail that fails changes nothing.
  gc mail send "$KEEPER" -s "gascity rebase $ISSUE landed" \
    -m "origin/$TARGET is $MAIN, the tip of $BRANCH, pushed by the operator. Rig checkout: $RIG_SYNC. $ISSUE is closed." \
    </dev/null >/dev/null 2>&1 \
    || echo "$PROG: the mail to $KEEPER about the landing of $ISSUE failed; the close and its notes are the record" >&2
  echo "$PROG: $ISSUE landed at $(short "$MAIN") and is closed; rig checkout: $RIG_SYNC"
}

race_loss() {
  gc bd update "$ISSUE" --status=open --assignee="$KEEPER" --set-metadata aborted_at=race-loss \
    --append-notes "Not landed ($(now)): once the landing gate cleared, origin/$TARGET was $MAIN, which is neither the tip of $BRANCH ($TIP) nor the pre-rebase tip ($PRE). $TARGET moved after the rebase, so the leased push was refused or something else was pushed, and $BRANCH is no longer landable as it is.
Backup ref (pre-rebase tip): ${BACKUP:-none}
Options: re-pour the rebase atop the new origin/$TARGET, drop it if what landed supersedes it, or take it by hand." \
    </dev/null >/dev/null 2>&1 \
    || { echo "$PROG: origin/$TARGET moved before $ISSUE landed, but the store refused its hand-back to $KEEPER" >&2; exit 1; }
  # The assignment and aborted_at are what the keeper's sweep reads, so a mail
  # that fails changes nothing.
  gc mail send "$KEEPER" --notify -s "gascity rebase $ISSUE: $TARGET moved before it landed" \
    -m "origin/$TARGET is $(short "$MAIN"), not the rebased tip of $BRANCH, so the rebase did not land. $ISSUE is assigned to you, and its notes say why." \
    </dev/null >/dev/null 2>&1 \
    || echo "$PROG: the mail to $KEEPER about $ISSUE failed; its assignment and aborted_at=race-loss are the record" >&2
  echo "$PROG: origin/$TARGET moved to $(short "$MAIN") before $ISSUE landed; it is assigned to $KEEPER"
}

case "$VERB" in
  ask)
    need_facts ask branch target pre_rebase_tip rebase_onto_sha
    resolve_rig
    ask_operator
    ;;
  finish)
    case "$STATUS" in
      closed) echo "$PROG: $ISSUE is closed already; nothing to finish"; exit 0 ;;
      open) ;;
      *) echo "$PROG: $ISSUE is $STATUS, so something holds it; nothing was checked" >&2; exit 1 ;;
    esac
    need_facts finish branch target pre_rebase_tip
    resolve_rig
    git -C "$RIG_ROOT" fetch --prune origin </dev/null >/dev/null 2>&1 \
      || { echo "$PROG: git fetch origin failed in $RIG_ROOT; nothing was checked" >&2; exit 1; }
    PRE=$(commit_of "$PRE_TIP") \
      || { echo "$PROG: pre_rebase_tip $PRE_TIP is no commit in $RIG_ROOT; nothing was checked" >&2; exit 1; }
    MAIN=$(commit_of "refs/remotes/origin/$TARGET") \
      || { echo "$PROG: $RIG_ROOT has no origin/$TARGET after the fetch; nothing was checked" >&2; exit 1; }
    TIP=$(commit_of "refs/heads/$BRANCH") \
      || { echo "$PROG: $RIG_ROOT has no branch $BRANCH; nothing was checked" >&2; exit 1; }
    if [ "$MAIN" = "$TIP" ]; then
      landed
    elif [ "$MAIN" = "$PRE" ]; then
      need_facts finish rebase_onto_sha
      ask_operator "Asked again: when the last landing gate cleared, origin/$TARGET was still at the pre-rebase tip, so the push had not run."
    else
      race_loss
    fi
    ;;
esac
exit 0
