#!/usr/bin/env bash
# recover-stranded-branches — recover COMPLETED work that reached origin and then
# stopped, because nothing anywhere owns its next move (tk-f69ay).
#
# THE SHAPE, RECOVERED BY HAND (mayor, 2026-08-11, bead tk-0981e). A polecat
# implemented, committed and PUSHED `polecat/tk-0981e` (36/36 regression pass,
# doctor clean), then DIED before the "Submit work to refinery and exit" step. What
# it left behind:
#
#   work bead     status=open, assignee EMPTY, gc.routed_to EMPTY, no merge_result
#   branch        on origin, 1 clean commit ahead of main, merges CLEAN
#   PR            none
#   workflow root in_progress, its steps already unrouted (a husk)
#
# No data was lost — but only because a human happened to look. Nothing in the city
# would ever have picked it up.
#
# WHY EVERY EXISTING DETECTOR STEPS OVER IT — the same "invisible to all of them at
# once" property that made tk-0nn3f cost an hour, one stage earlier:
#
#   pool demand                  the root is in_progress, so `bd ready` never
#                                returns the bead; and it carries no gc.routed_to,
#                                so it is not pool demand either way
#   refinery find-work           exact `--assignee=$GC_AGENT`; nobody is the assignee
#   reconcile-refinery-handoffs  requires an assignee that LOOKS like a refinery —
#                                this bead has none at all
#   check-set-heal / observer    enumerate on pr_url / pr_number / merge_result;
#                                the bead has none of the three, no PR was opened
#   witness recover-orphaned     scoped to "beads assigned to agents that will never
#                                process them" and keyed on the assignee — an
#                                UNASSIGNED bead is not in its candidate set
#   witness salvage cases C/D/E  all reason about UNCOMMITTED work at risk inside a
#                                worktree. Here the work is committed AND pushed, so
#                                Case E ("nothing to salvage") is literally correct
#   quiesce-completed-workflows  de-routes the dead STEPS of a husk; it never asks
#                                what became of the work bead
#
# Every one of those is right about its own question. The question none of them asks
# is the one that matters here: the canonical chain is
# `worktree -> (push) -> branch -> (PR) -> target`, and this bead is safely on the
# branch with NOTHING that will ever carry it further. Work safely on origin with no
# owner is not salvaged — it is STRANDED, and the strand is unbounded.
#
# WHAT THIS PASS SELECTS. The complement of every scan above, and nothing else:
#
#   open/in_progress   still live work
#   assignee EMPTY     no agent, pool or refinery owns it
#   gc.routed_to EMPTY no pool will be offered it (empty and ABSENT are the same
#                      thing here — see the note on the filter below)
#   metadata.branch    it claims a branch
#   no merge_result    it never reached the merge gate
#   no PR field        no pr_url / pr_number / existing_pr / fork_pr recorded
#   branch ON ORIGIN and AHEAD of its target      the work really is published
#   no PR for that head, in any state             nothing will land it
#   no LIVE session behind its molecule           nobody is about to submit it
#   older than --min-age-minutes                  not merely mid-handoff
#
# WHY THE LIVENESS GATE IS AN "AND", NOT THE "OR" THE BUG REPORT SUGGESTED. The
# report proposed `(assignee empty OR the owning workflow root is a husk)`. Taken
# literally that fires on EVERY molecule in the city: verified live on tk-f69ay
# itself, a work bead is `open` with `assignee=null` and no `gc.routed_to` for the
# WHOLE time its polecat is working it — mol-polecat-work assigns the polecat to the
# STEP beads, never to the anchor. So "unassigned" does not distinguish a stranded
# bead from a healthy in-flight one; only "no live session stands behind it" does,
# and the two conditions have to hold together. Getting this wrong would hand a
# running polecat's branch to the refinery mid-implementation.
#
# WHY IT REPAIRS BY HANDING OFF, RATHER THAN RE-DISPATCHING A POLECAT. The bug
# report suggested re-dispatching to the pool "to resume at submit-to-refinery".
# That names the missing action exactly — and the missing action is a metadata
# write. submit-and-exit pushes the branch (already done), stamps `branch` and
# `target`, sets the bead back to `open` and reassigns it to the refinery; there is
# nothing else in it. So this pass performs it directly instead of pouring a fresh
# molecule to spend a full-context session re-deriving the same three fields.
#
# ALL FOUR FIELDS ARE THE HANDOFF, and each is READ BACK before the handoff counts.
# `gc bd update` reporting success is not proof that a write is durable, and each
# write here is best-effort, so success and failure are otherwise indistinguishable:
#
#   branch/target  what the refinery MERGES BY. Stamped and verified BEFORE the
#                  assignee, because an assignee that sticks over a target that did
#                  not takes the bead out of this pass's candidate set (it is no
#                  longer unassigned) and hands the refinery a branch to rebase onto
#                  a missing or stale base — an integration member onto main. That is
#                  the un-retryable wrong handoff, so the assignee is not written at
#                  all until the fields it depends on read back.
#   status=open    what makes the bead VISIBLE to the refinery. Its find-work step
#                  polls `--assignee=$GC_AGENT --status=open`
#                  (formulas/mol-refinery-patrol.toml), and the candidate scan admits
#                  in_progress beads — a strand wears that status whenever a partial
#                  quiesce cleared the assignee without resetting the status. Handed
#                  over as in_progress, the bead is assigned to an actor that will
#                  never poll it AND no longer unassigned, so this pass will not
#                  retry it either: a strictly worse strand than the one it found.
#   assignee       WHO owns the next move. Written last, verified with the rest.
#
# A post-write mismatch RELEASES our own assignee (its own single-flag update — a
# claim guard can roll back a batched release, losing both writes), which restores
# the candidate shape so the next cycle retries the whole handoff.
#
# That is not a shortcut past review. The refinery takes the branch through the
# ordinary pre-open codex gate and the PR still needs external human approval, so a
# branch pushed by a polecat that died MID-implementation cannot merge on the
# strength of this pass — it gets reviewed, and a REQUEST_CHANGES verdict files the
# rework child exactly as it would have anyway. The failure this fixes is the bead
# never entering that pipeline at all.
#
# FAIL-SAFE DIRECTION, everywhere: when a fact cannot be established — the session
# roster did not read, the bead listing did not parse, `gh` could not answer, the
# target branch is unknown — the pass SKIPS the bead and says so. An un-repaired
# strand is the status quo this pass improves on; a wrong handoff creates a new one.
#
# NOT set -e: best-effort, must never abort the witness patrol mid-pass. Any tool
# error skips that bead and retries next cycle. The pass DOES exit non-zero when a
# handoff it decided on could not be verified — the call site treats that as
# non-fatal and retries, and a silent exit 0 over a failed write is how this whole
# class of bug hides.
set -uo pipefail

REFINERY_ID=""
DRY_RUN=0
MIN_AGE_MINUTES=30
REPO_SLUG=""
REPO_ROOT=""
# WHICH LEDGER this pass reads and writes, exactly as reconcile-refinery-handoffs.sh
# pins it: an unpinned `gc bd` resolves to whatever ledger is ambient, which in an
# imported rig is not the one whose work this pass was handed.
RIG_PIN="${GC_RIG:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --refinery)          REFINERY_ID="${2:-}"; shift 2 ;;
    --refinery=*)        REFINERY_ID="${1#--refinery=}"; shift ;;
    --rig)               RIG_PIN="${2:-}"; shift 2 ;;
    --rig=*)             RIG_PIN="${1#--rig=}"; shift ;;
    --min-age-minutes)   MIN_AGE_MINUTES="${2:-}"; shift 2 ;;
    --min-age-minutes=*) MIN_AGE_MINUTES="${1#--min-age-minutes=}"; shift ;;
    --repo)              REPO_SLUG="${2:-}"; shift 2 ;;
    --repo=*)            REPO_SLUG="${1#--repo=}"; shift ;;
    --root)              REPO_ROOT="${2:-}"; shift 2 ;;
    --root=*)            REPO_ROOT="${1#--root=}"; shift ;;
    --dry-run)           DRY_RUN=1; shift ;;
    *)                   shift ;;
  esac
done

case "$MIN_AGE_MINUTES" in
  ''|*[!0-9]*) MIN_AGE_MINUTES=30 ;;
esac

bd_pinned() { # <bd-subcommand> [args...]
  if [ -n "$RIG_PIN" ]; then
    gc bd --rig "$RIG_PIN" "$@"
  else
    gc bd "$@"
  fi
}

# The identity a recovered handoff is addressed to. Without it there is nothing to
# hand off TO, and inventing one is how a bead moves from one dead address to
# another (the failure reconcile-refinery-handoffs.sh refuses for the same reason).
if [ -z "$REFINERY_ID" ]; then
  echo "recover-stranded-branches: no --refinery identity given; skipping (nothing to hand a recovered branch to)" >&2
  exit 0
fi

# --- candidate enumeration -------------------------------------------------
# Runs FIRST, before the roster and molecule maps below, because the common case is
# zero candidates and everything after this is only paid when there is something to
# decide.
#
# `gc.routed_to` is tested as EMPTY-OR-ABSENT, deliberately. Both forms occur live
# and they mean the same thing: the done sequence and the refinery's park write the
# empty string on purpose — an open, unassigned bead with `gc.routed_to=""` is the
# documented "detached from both queues" marker (docs/work-bead-state-machine.md,
# docs/gascity-routing-model.md) — while a bead that was never routed simply has no
# such key. A filter that distinguished them would miss half the strands.
RAW=$(bd_pinned list --status=open,in_progress --has-metadata-key=branch \
  --exclude-type=epic --limit=0 --json 2>/dev/null)
RC=$?
if [ "$RC" -ne 0 ] || [ -z "$RAW" ] \
   || ! printf '%s' "$RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "recover-stranded-branches: WARN the branch-carrying bead enumeration did not return a readable result (rc=$RC); nothing examined this pass, retries next cycle" >&2
  exit 0
fi

CANDIDATES=$(printf '%s' "$RAW" | tr -d '\000-\010\013\014\016-\037' | jq -c '
  .[]
  | ((.metadata // {})) as $m
  | select((((.assignee // "") | tostring)) == "")
  | select(((($m["gc.routed_to"] // "") | tostring)) == "")
  | select(((($m.branch // "") | tostring)) != "")
  | select(((($m.merge_result // "") | tostring)) == "")
  | select(((($m.pr_url // "") | tostring)) == "")
  | select(((($m.pr_number // "") | tostring)) == "")
  | select(((($m.existing_pr // "") | tostring)) == "")
  | select(((($m.fork_pr // "") | tostring)) == "")
  | select(((($m.fork_pr_url // "") | tostring)) == "")
  # Deliberately parked work is not stranded work. `duplicate_of` / `hold_reason`
  # are set by the refinery when it blocks a bead for a human decision, and
  # merge_hold is the operator gate; each of them means somebody DECIDED this
  # branch should not move, which is the opposite of nobody owning it.
  | select(((($m.duplicate_of // "") | tostring)) == "")
  | select(((($m.hold_reason // "") | tostring)) == "")
  | select(((($m.merge_hold // "") | tostring)) as $h
           | $h == "" or $h == "false" or $h == "False" or $h == "FALSE" or $h == "0")
  # Non-impl work produces no commits to land, so it never belongs to this pass.
  | select(((($m.task_kind // "") | tostring)) as $k
           | $k != "review" and $k != "research" and $k != "investigation")
  | {id: .id,
     status: ((.status // "") | ascii_downcase),
     branch: ((($m.branch // "") | tostring)),
     target: ((($m.target // "") | tostring)),
     updated: ((.updated_at // "") | tostring),
     flagged: ((($m.stranded_branch_flagged // "") | tostring)),
     recovered: ((($m.stranded_branch_recovered // "") | tostring))}' 2>/dev/null)

if [ -z "$CANDIDATES" ]; then
  echo "recover-stranded-branches: no unowned branch-carrying work beads"
  exit 0
fi

# --- repository -------------------------------------------------------------
# The rig repo the branches were pushed to. $GC_RIG_ROOT first (the agent env names
# it), then the enclosing worktree. Both are checked for being a real repo, because
# every git answer below decides whether work is published.
if [ -z "$REPO_ROOT" ]; then
  for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)"; do
    [ -n "$cand" ] || continue
    if git -C "$cand" rev-parse --git-dir >/dev/null 2>&1; then REPO_ROOT="$cand"; break; fi
  done
fi
if [ -z "$REPO_ROOT" ] || ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "recover-stranded-branches: WARN no rig git repository resolved (\$GC_RIG_ROOT='${GC_RIG_ROOT:-}'); cannot verify that any branch is published, so nothing is handed off this pass" >&2
  exit 0
fi

git_pinned() { git -C "$REPO_ROOT" "$@"; }

# WHICH REPOSITORY the PR lookup answers about. Derived from the rig repo's own
# `origin`, never left to gh's ambient context: this pass runs from a patrol
# worktree, and a `gh pr list` resolved against the wrong repository would report
# "no PR" for a branch that has one — and then hand a live PR's branch to the
# refinery a second time. Host-qualified for the same reason the signoff gate pins
# it: `<owner>/<repo>` names one repository PER HOST.
if [ -z "$REPO_SLUG" ]; then
  ORIGIN_URL=$(git_pinned remote get-url origin 2>/dev/null)
  REPO_SLUG=$(printf '%s' "$ORIGIN_URL" | sed -n \
    -e 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/]*@\)\{0,1\}\([^/]*\)/\(.*\)$#\2/\3#p' \
    -e 's#^[^/@]*@\([^:]*\):\(.*\)$#\1/\2#p' | sed -e 's#\.git$##' -e 's#/*$##')
fi
if [ -z "$REPO_SLUG" ]; then
  echo "recover-stranded-branches: WARN could not derive owner/repo from the rig's origin remote; the PR lookup cannot be pinned to a repository, so nothing is handed off this pass" >&2
  exit 0
fi

# The repo's default branch, used only when neither the bead nor its convoy records
# a target. Read from origin's own HEAD so it is the remote's answer, not a local
# checkout's.
DEFAULT_BRANCH=$(git_pinned symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="main"

# --- session roster: who is actually alive ----------------------------------
# Same two sources, and the same fail-safe, as reconcile-refinery-handoffs.sh: the
# LIVE roster is the only thing that can prove a session dead, and a roster that did
# not read makes every molecule look husked — which here would hand a running
# polecat's branch to the refinery. Both blobs reach jq on STDIN, never --argjson on
# argv (session `command` fields overflow ARG_MAX on a busy city).
SESSIONS_JSON=$(gc session list --state=all --json 2>/dev/null); SESSIONS_RC=$?
SESSION_BEADS_JSON=$(bd_pinned list --type=session --label=gc:session --include-infra \
  --include-gates --all --json --limit=0 2>/dev/null) || SESSION_BEADS_JSON=""

SESSION_COUNT=$(printf '%s' "$SESSIONS_JSON" | jq -r '(.sessions // []) | length' 2>/dev/null)
[ -n "$SESSION_COUNT" ] || SESSION_COUNT=0

ROSTER_OK=1
ROSTER_WHY=""
if [ "$SESSIONS_RC" -ne 0 ]; then
  ROSTER_OK=0
  ROSTER_WHY="the live session roster could not be READ (gc session list --state=all --json exited $SESSIONS_RC)"
elif ! printf '%s' "$SESSIONS_JSON" \
     | jq -e 'type == "object" and has("sessions") and (.sessions | type == "array")' \
       >/dev/null 2>&1; then
  ROSTER_OK=0
  ROSTER_WHY="the live session roster did not PARSE as {\"sessions\": [...]}"
elif [ "$SESSION_COUNT" -eq 0 ]; then
  ROSTER_OK=0
  ROSTER_WHY="the live session roster is EMPTY (0 sessions listed) while this pass is itself running in one, so it is not a census of who is alive"
fi

# Every identifier form of every session that is NOT closed or archived. `drained`,
# `asleep`, `suspended` and `quarantined` all still have an owner — the same
# classification the witness's own liveness recipe applies, so the two passes cannot
# disagree about who exists.
ALIVE_IDS=$(printf '%s' "$SESSIONS_JSON" | jq -r '
  (.sessions // [])[]
  | select(((.closed // false) | not))
  | select((((.state // "") | ascii_downcase)) as $s | $s != "closed" and $s != "archived")
  | [.id, .name, .session_name, .alias, .agent_name][]
  | select(. != null and . != "")' 2>/dev/null)

ALIVE_NAMED=$(printf '%s' "$SESSION_BEADS_JSON" | jq -r '
  .[]?
  | select(((.status // "") | ascii_downcase) != "closed")
  | select(((((.metadata // {}).state // "") | ascii_downcase)) as $s
           | $s != "closed" and $s != "archived")
  | ((.metadata // {}).configured_named_identity // empty)
  | select(. != "")' 2>/dev/null)

if [ -n "$ALIVE_NAMED" ]; then
  ALIVE_IDS="${ALIVE_IDS:+$ALIVE_IDS
}$ALIVE_NAMED"
fi

if [ "$ROSTER_OK" = 1 ] && [ -z "$ALIVE_IDS" ]; then
  ROSTER_OK=0
  ROSTER_WHY="the session roster produced no identities at all ($SESSION_COUNT session(s) listed)"
fi
if [ "$ROSTER_OK" != 1 ]; then
  echo "recover-stranded-branches: FAIL-SAFE $ROSTER_WHY; NOT handing off any bead this pass — a molecule can only be proved husked against a live roster that was actually read, and an unread one makes every running polecat look dead. Reporting only; retries next cycle" >&2
fi

# Membership test against the roster. A here-string, never `... | grep -qxF`:
# `set -o pipefail` is on and `grep -q` exits at its first match, SIGPIPEing the
# writer and reporting 141 — a true answer read as false.
is_alive() {
  [ -n "${1:-}" ] || return 1
  [ "$ROSTER_OK" = 1 ] || return 1
  grep -Fxq -- "$1" <<< "$ALIVE_IDS"
}

# --- molecule map: which convoys still have a LIVE session behind them -------
# Built from ONE bulk listing. Workflow roots carry `gc.input_convoy_id` and appear
# in the ordinary open/in_progress listing (verified live: 21 roots, matching the 21
# distinct `gc.root_bead_id` values on the live step beads), so root -> convoy needs
# no per-root read.
#
# A molecule counts as LIVE when either the root records a session that is alive, or
# any of its live step beads is held by a session that is alive. Two signals because
# each covers a different moment: a root's `gc.session_name` is stamped when the
# molecule is poured, while a step's assignee is what a re-claimed or re-nudged
# molecule carries.
#
# ROOT_ROWS / STEP_ROWS / MOLECULE_OK are initialized BEFORE the branch that fills
# them: `set -u` is on, and a variable first assigned inside one arm kills the whole
# pass the first time the other arm runs.
ROOT_ROWS=""
STEP_ROWS=""
MOLECULE_OK=0
LIVE_BEADS=$(bd_pinned list --status=open,in_progress --limit=0 --json 2>/dev/null)
LIVE_BEADS_RC=$?
if [ "$LIVE_BEADS_RC" -ne 0 ] || [ -z "$LIVE_BEADS" ] \
   || ! printf '%s' "$LIVE_BEADS" | jq -e 'type == "array"' >/dev/null 2>&1; then
  MOLECULE_OK=0
  echo "recover-stranded-branches: FAIL-SAFE the live bead listing did not return a readable result (rc=$LIVE_BEADS_RC); NOT handing off any bead this pass — without it no molecule can be proved husked. Reporting only; retries next cycle" >&2
else
  MOLECULE_OK=1
  # convoy_id<TAB>root_id<TAB>root_status<TAB>root_session
  ROOT_ROWS=$(printf '%s' "$LIVE_BEADS" | tr -d '\000-\010\013\014\016-\037' | jq -r '
    .[]
    | ((.metadata // {})) as $m
    | select(((($m["gc.input_convoy_id"] // "") | tostring)) != "")
    | [(($m["gc.input_convoy_id"] | tostring)),
       (.id // ""),
       ((.status // "") | ascii_downcase),
       ((($m["gc.session_name"] // "") | tostring))]
    | @tsv' 2>/dev/null)
  # root_id<TAB>assignee, for every live step bead that names a root
  STEP_ROWS=$(printf '%s' "$LIVE_BEADS" | tr -d '\000-\010\013\014\016-\037' | jq -r '
    .[]
    | ((.metadata // {})) as $m
    | select(((($m["gc.root_bead_id"] // "") | tostring)) != "")
    | select((((.assignee // "") | tostring)) != "")
    | [(($m["gc.root_bead_id"] | tostring)), ((.assignee | tostring))]
    | @tsv' 2>/dev/null)
fi

# Is any molecule whose input convoy is $1 still held by a live session?
convoy_is_live() { # <convoy-id>
  local convoy="$1" root status session assignee
  [ -n "$convoy" ] || return 1
  while IFS=$'\t' read -r c root status session; do
    [ "$c" = "$convoy" ] || continue
    [ "$status" = "closed" ] && continue
    is_alive "$session" && return 0
    while IFS=$'\t' read -r r assignee; do
      [ "$r" = "$root" ] || continue
      is_alive "$assignee" && return 0
    done <<< "$STEP_ROWS"
  done <<< "$ROOT_ROWS"
  return 1
}

# --- per-bead helpers -------------------------------------------------------
# The remote tip of a branch, by EXACT ref. `ls-remote` is the identity (no local
# state, so a concurrent fetch in the same repo cannot substitute another sha) and
# the fetch that follows only makes the objects readable.
remote_sha() { # <branch>
  git_pinned ls-remote origin "refs/heads/$1" 2>/dev/null \
    | awk -v r="refs/heads/$1" '$2 == r { print $1; exit }'
}

have_commit() { # <sha>
  git_pinned cat-file -e "${1}^{commit}" 2>/dev/null
}

fetch_commit() { # <branch> <sha>
  have_commit "$2" && return 0
  git_pinned fetch --quiet origin "refs/heads/$1" >/dev/null 2>&1
  have_commit "$2"
}

# The whole handoff, read in ONE call: the two fields the refinery merges by, the
# status that decides whether it ever polls the bead, and who owns it. One read so
# every comparison speaks about the same observation of the bead.
#
# One field PER LINE, each read with `IFS= read -r`, rather than one @tsv line split
# on tabs: a tab is an IFS *whitespace* character, so `IFS=$'\t' read a b c d` folds
# runs of tabs together and drops leading ones — a bead with an empty status would
# silently shift `branch` into `$a`, and every comparison below would then be made
# against the wrong field. An empty line stays an empty field.
handoff_state() { # <id> -> status, assignee, branch, target — one per line
  bd_pinned show "$1" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037' \
    | jq -r '.[0] | select(. != null)
             | ((.status // "") | ascii_downcase),
               ((.assignee // "") | tostring),
               (((.metadata // {}).branch // "") | tostring),
               (((.metadata // {}).target // "") | tostring)' 2>/dev/null
}

# Read $1's handoff into HS_STATUS / HS_ASSIGNEE / HS_BRANCH / HS_TARGET. All four
# are cleared first: an unreadable bead produces no lines at all, and every read
# then hits EOF, which must read as four empty values that mismatch everything —
# the fail-safe direction — rather than as the previous bead's answer.
read_handoff() { # <id>
  HS_STATUS=""; HS_ASSIGNEE=""; HS_BRANCH=""; HS_TARGET=""
  {
    IFS= read -r HS_STATUS
    IFS= read -r HS_ASSIGNEE
    IFS= read -r HS_BRANCH
    IFS= read -r HS_TARGET
  } <<< "$(handoff_state "$1")"
}

NOW=$(date +%s 2>/dev/null || echo 0)
MIN_AGE_SECONDS=$((MIN_AGE_MINUTES * 60))

recovered=0; reported=0; skipped=0; failed=0

# Report a bead we decline to hand off, ONCE per (branch, tip) it was seen at. The
# marker records what provoked the warning, so a genuinely stuck bead is named once
# rather than every cycle forever — and a bead that MOVES is reported again.
#
# The marker also records the refusal's ESCALATION CLASS, and suppression is by
# class rather than by tip alone. Nearly every refusal here is a read that did not
# answer — a dep listing, a convoy bead, a `gh pr list` — and they all write the
# same `branch@tip`; exactly one, an unresolvable target, additionally summons a
# human. Suppressing on the tip alone lets a transient failure SILENCE that summons:
# one cycle marks `branch@tip` because the dep list did not answer, the next cycle
# reads it fine and discovers the target branch is missing, and the escalating
# refusal returns at the suppression check having mailed nobody. The branch is then
# left stranded behind a summary count with no human-facing signal anywhere — the
# exact outcome the escalating arm exists to prevent, produced by an unrelated blip.
#
# So a quiet marker never suppresses a loud refusal: an escalating refusal is
# suppressed only by a previous ESCALATION at the same tip, while a non-escalating
# one is suppressed by either class — a human has already been summoned to this
# tip, and a quieter warning about the same commit adds noise without signal.
# Escalating once per (branch, tip) is deliberate: the mail asks an operator to look
# at the branch, and a second reason to look at the same commit needs no second mail.
#
# A bead flagged by an earlier revision of this pass carries a bare `branch@tip`
# even where an escalation did fire, so the first escalating refusal after this
# change may re-mail once for such a bead. That is the right direction to err: the
# other reading of an ambiguous marker is silence about a stranded branch.
ESCALATED_SUFFIX='#escalated'
report_only() { # <id> <tip-marker> <already-flagged> <escalate 0|1> <message>
  local id="$1" tip="$2" flagged="$3" escalate="$4" message="$5"
  local marker="$tip" loud="$tip$ESCALATED_SUFFIX"
  if [ "$escalate" = 1 ]; then marker="$loud"; fi
  reported=$((reported + 1))
  # Already reported at this tip, at a class at least as loud as this one.
  if [ "$flagged" = "$marker" ] || [ "$flagged" = "$loud" ]; then return 0; fi
  echo "recover-stranded-branches: WARN $id $message" >&2
  [ "$DRY_RUN" = 1 ] && return 0
  if [ "$escalate" = 1 ]; then
    gc mail send mayor/ -s "STRANDED BRANCH: $id has no landing path" \
      -m "Bead $id carries a published branch and no way to land it: $message

Nothing in the city will pick it up — it is unassigned (so orphan recovery and the refinery's queue both step over it), unrouted (so it is not pool demand), and carries no PR or merge_result (so every bead-keyed reconcile pass is blind to it). This pass could not repair it automatically for the reason above.
Action needed: an operator decision on the branch (tk-f69ay)." >/dev/null 2>&1 || true
  fi
  bd_pinned update "$id" --set-metadata stranded_branch_flagged="$marker" >/dev/null 2>&1 || true
}

while IFS= read -r row; do
  [ -n "$row" ] || continue
  ID=$(printf '%s' "$row" | jq -r '.id // empty' 2>/dev/null)
  BRANCH=$(printf '%s' "$row" | jq -r '.branch // empty' 2>/dev/null)
  TARGET=$(printf '%s' "$row" | jq -r '.target // empty' 2>/dev/null)
  UPDATED=$(printf '%s' "$row" | jq -r '.updated // empty' 2>/dev/null)
  FLAGGED=$(printf '%s' "$row" | jq -r '.flagged // empty' 2>/dev/null)
  [ -n "$ID" ] && [ -n "$BRANCH" ] || continue

  # --- gate 1: age. The window between a polecat's `git push` and its handoff is
  # seconds wide but it is REAL, and inside it the bead wears this exact shape. A
  # minimum age keeps the pass off work that is merely mid-submission. It is a
  # backstop, not the guard — the liveness gate below is what actually protects a
  # running polecat, because implementation routinely outlasts any age threshold.
  UPDATED_EPOCH=$(printf '%s' "$UPDATED" | jq -rR '
    (try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch empty) // empty' 2>/dev/null)
  if [ -n "$UPDATED_EPOCH" ] && [ "$NOW" -gt 0 ] \
     && [ $((NOW - UPDATED_EPOCH)) -lt "$MIN_AGE_SECONDS" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  # --- gate 2: the branch is really on origin.
  HEAD_SHA=$(remote_sha "$BRANCH")
  if [ -z "$HEAD_SHA" ]; then
    # Recorded a branch that origin does not have. Unpushed work is the witness's
    # salvage domain (cases C/D), not this pass's — and with no assignee there is
    # no worktree owner to salvage from either. Report, never guess.
    report_only "$ID" "$BRANCH@missing" "$FLAGGED" 0 \
      "records branch '$BRANCH', which does not exist on origin — nothing is published under that name, so this pass has nothing to hand off (unpushed work belongs to the witness's worktree salvage)"
    continue
  fi

  # --- gate 3: a target to land on. The bead's own `target` first; then the input
  # convoy's (an owned convoy lands its members on an integration branch, not main);
  # then the repository default. Stamping the wrong target would rebase the work onto
  # the wrong base, so an unresolvable one skips the bead.
  #
  # The dependency list is READ-CHECKED, not merely mined for ids. `gc bd dep list`
  # answers a failure with a JSON object carrying `error` and rc=1, and `.[]?.id`
  # reduces that to the SAME empty string a genuinely dep-less bead produces. Read as
  # "no upstream convoy" it fails OPEN in two places at once: here, where the
  # repository default is then stamped over an owned convoy's integration branch —
  # the un-retryable wrong handoff, an integration member recovered into a main PR
  # past the convoy boundary, and the readback below only proves that the WRONG
  # target stuck — and at gate 6, where an empty convoy list leaves nothing to test
  # for liveness, so the live molecule standing behind the bead becomes invisible and
  # a running polecat's branch is handed to the refinery mid-implementation. Both are
  # facts this pass must establish rather than assume, so an unreadable list skips.
  DEPS_RAW=$(bd_pinned dep list "$ID" --direction=up --json 2>/dev/null); DEPS_RC=$?
  if [ "$DEPS_RC" -ne 0 ] || [ -z "$DEPS_RAW" ] \
     || ! printf '%s' "$DEPS_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
    report_only "$ID" "$BRANCH@$HEAD_SHA" "$FLAGGED" 0 \
      "its upstream dependency list could not be read (gc bd dep list rc=$DEPS_RC); an unread list is not proof that there is no convoy, and guessing one would both land a convoy member on '$DEFAULT_BRANCH' and hide any live molecule standing behind the bead"
    continue
  fi
  CONVOYS=$(printf '%s' "$DEPS_RAW" | tr -d '\000-\010\013\014\016-\037' \
    | jq -r '.[]?.id // empty' 2>/dev/null)
  # Both initialized BEFORE the branch that fills them, in the same style and for the
  # same reason as ROOT_ROWS/STEP_ROWS above: `set -u` is on, and a variable first
  # assigned inside a conditional arm kills the whole pass the first time the other
  # arm runs. CROW_RC additionally must not carry over from the previous candidate.
  CONVOY_UNREADABLE=""
  CROW_RC=0
  if [ -z "$TARGET" ]; then
    while IFS= read -r cid; do
      [ -n "$cid" ] || continue
      # The same distinction one level down, and it is the one that actually bites:
      # an unreadable convoy bead and a convoy that records no target both leave $CT
      # empty, and only the second of them means "land on the default". Require a row
      # that really READ — rc, an array, and an object at [0] — before believing its
      # answer. rc alone is not enough (a malformed payload can arrive with rc=0),
      # and an empty array is `bd` declining to return the bead at all, which is an
      # unestablished fact, not a convoy without a target.
      CROW=$(bd_pinned show "$cid" --json 2>/dev/null); CROW_RC=$?
      CROW=$(printf '%s' "$CROW" | tr -d '\000-\010\013\014\016-\037')
      if [ "$CROW_RC" -ne 0 ] \
         || ! printf '%s' "$CROW" | jq -e 'type == "array" and (.[0] | type == "object")' \
              >/dev/null 2>&1; then
        CONVOY_UNREADABLE="$cid"
        break
      fi
      CT=$(printf '%s' "$CROW" | jq -r '.[0].metadata.target // empty' 2>/dev/null)
      if [ -n "$CT" ]; then TARGET="$CT"; break; fi
    done <<< "$CONVOYS"
  fi
  if [ -n "$CONVOY_UNREADABLE" ]; then
    report_only "$ID" "$BRANCH@$HEAD_SHA" "$FLAGGED" 0 \
      "its upstream convoy '$CONVOY_UNREADABLE' could not be read (rc=$CROW_RC), so whether that convoy lands its members on an integration branch is unknown; falling back to '$DEFAULT_BRANCH' on an unread convoy is how integration work gets rebased onto the wrong base"
    continue
  fi
  TARGET_SOURCE="bead/convoy"
  if [ -z "$TARGET" ]; then TARGET="$DEFAULT_BRANCH"; TARGET_SOURCE="repository default"; fi

  BASE_SHA=$(remote_sha "$TARGET")
  if [ -z "$BASE_SHA" ]; then
    report_only "$ID" "$BRANCH@$HEAD_SHA" "$FLAGGED" 1 \
      "would land on '$TARGET' ($TARGET_SOURCE), which does not exist on origin — the branch cannot be compared against a base that is not there"
    continue
  fi

  # --- gate 4: the branch actually carries work. Objects are fetched only to answer
  # this; nothing local is written beyond the object store.
  if ! fetch_commit "$BRANCH" "$HEAD_SHA" || ! fetch_commit "$TARGET" "$BASE_SHA"; then
    report_only "$ID" "$BRANCH@$HEAD_SHA" "$FLAGGED" 0 \
      "branch '$BRANCH' is on origin at $HEAD_SHA but its commits could not be fetched into ${REPO_ROOT}; cannot tell whether it is ahead of '$TARGET'"
    continue
  fi
  # The second half of the age gate, and the one that cannot be defeated by this
  # pass's own writes: the tip's commit time is immutable, while a bead's
  # `updated_at` is bumped by the very marker `report_only` writes below. Neither is
  # the real guard (gate 6 is) — together they simply keep the pass off work that is
  # visibly still in motion.
  TIP_EPOCH=$(git_pinned log -1 --format=%ct "$HEAD_SHA" 2>/dev/null)
  case "${TIP_EPOCH:-x}" in
    ''|*[!0-9]*) TIP_EPOCH="" ;;
  esac
  if [ -n "$TIP_EPOCH" ] && [ "$NOW" -gt 0 ] \
     && [ $((NOW - TIP_EPOCH)) -lt "$MIN_AGE_SECONDS" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  AHEAD=$(git_pinned rev-list --count "$BASE_SHA..$HEAD_SHA" 2>/dev/null)
  case "${AHEAD:-x}" in
    ''|*[!0-9]*)
      report_only "$ID" "$BRANCH@$HEAD_SHA" "$FLAGGED" 0 \
        "could not count commits on '$BRANCH' ahead of '$TARGET'"
      continue ;;
  esac
  if [ "$AHEAD" -eq 0 ]; then
    # Already contained in the target: there is nothing left to land, so the bead is
    # not stranded in this pass's sense. Closing it belongs to the refinery (it is
    # the only actor that closes work beads after verifying a merge), and the
    # witness's own orphan scan already closes the assigned form of this case.
    skipped=$((skipped + 1))
    echo "recover-stranded-branches: $ID branch '$BRANCH' is 0 commits ahead of '$TARGET' — already landed or empty; left for the refinery to reconcile"
    continue
  fi

  # --- gate 5: nothing is already carrying it. ANY pull request for this head, in
  # any state, means a landing path exists or an operator deliberately closed one —
  # neither is this pass's business. Fail closed: an unreadable answer is not "no PR".
  PR_JSON=$(gh pr list --repo "$REPO_SLUG" --head "$BRANCH" --state all \
    --json number,state --limit 10 2>/dev/null); PR_RC=$?
  if [ "$PR_RC" -ne 0 ] || ! printf '%s' "$PR_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
    report_only "$ID" "$BRANCH@$HEAD_SHA" "$FLAGGED" 0 \
      "the pull-request lookup for '$BRANCH' in $REPO_SLUG failed (gh rc=$PR_RC); a failed read is not proof that no PR exists, so the branch is left alone"
    continue
  fi
  PR_COUNT=$(printf '%s' "$PR_JSON" | jq -r 'length' 2>/dev/null)
  if [ "${PR_COUNT:-0}" -gt 0 ]; then
    skipped=$((skipped + 1))
    echo "recover-stranded-branches: $ID branch '$BRANCH' already has $(printf '%s' "$PR_JSON" | jq -r 'map("#\(.number) \(.state)") | join(", ")') — a landing path exists, leaving it alone"
    continue
  fi

  # --- gate 6: no live session is behind it. THE guard (see the header): an
  # unassigned anchor is what every in-flight molecule looks like, so this is the
  # only thing separating a strand from a polecat that is still working.
  if [ "$ROSTER_OK" != 1 ] || [ "${MOLECULE_OK:-0}" != 1 ]; then
    skipped=$((skipped + 1))
    continue
  fi
  MOLECULE_LIVE=0
  while IFS= read -r cid; do
    [ -n "$cid" ] || continue
    if convoy_is_live "$cid"; then MOLECULE_LIVE=1; break; fi
  done <<< "$CONVOYS"
  if [ "$MOLECULE_LIVE" = 1 ]; then
    skipped=$((skipped + 1))
    continue
  fi

  # --- stranded. Perform the handoff the dead polecat never reached.
  if [ "$DRY_RUN" = 1 ]; then
    recovered=$((recovered + 1))
    echo "recover-stranded-branches: DRY-RUN would hand $ID to '$REFINERY_ID' (branch '$BRANCH' @ ${HEAD_SHA:0:12}, $AHEAD commit(s) ahead of '$TARGET' from $TARGET_SOURCE, no PR, no live molecule)"
    continue
  fi

  # Metadata FIRST, assignee last — the same order the done sequence uses, so the
  # refinery never sees the bead before the fields it merges by are on it.
  bd_pinned update "$ID" \
    --set-metadata branch="$BRANCH" \
    --set-metadata target="$TARGET" >/dev/null 2>&1 || true

  # Verify what the refinery MERGES BY *before* handing it the bead. The write above
  # is best-effort and a reported success is not a durable one, so a metadata write
  # that silently did not stick — paired with an assignee write that did — would
  # both remove the bead from this pass's candidate set and hand the refinery a
  # branch to rebase onto a missing or stale target. Refusing here leaves the bead
  # unassigned, i.e. still a candidate, and costs one cycle.
  read_handoff "$ID"
  if [ "$HS_BRANCH" != "$BRANCH" ] || [ "$HS_TARGET" != "$TARGET" ]; then
    failed=$((failed + 1))
    echo "recover-stranded-branches: WARN $ID the fields the refinery merges by did NOT stick (branch read back '${HS_BRANCH:-}' want '$BRANCH'; target read back '${HS_TARGET:-}' want '$TARGET'; bead reads status='${HS_STATUS:-}' assignee='${HS_ASSIGNEE:-}'); NOT assigning it to '$REFINERY_ID' — an assigned bead with an unstamped target leaves this pass's candidate set and would be rebased onto the wrong base. Still stranded; retries next cycle" >&2
    continue
  fi

  # status=open AND the assignee together, exactly as the done sequence writes them.
  # The scan admits in_progress beads, but the refinery's find-work step polls
  # `--assignee=$GC_AGENT --status=open`, so an in_progress bead handed over is
  # assigned to an actor that will never see it — and, being assigned, is no longer
  # a candidate for this pass either.
  bd_pinned update "$ID" --status=open --assignee="$REFINERY_ID" >/dev/null 2>&1 || true

  read_handoff "$ID"
  if [ "$HS_ASSIGNEE" != "$REFINERY_ID" ] || [ "$HS_STATUS" != "open" ] \
     || [ "$HS_BRANCH" != "$BRANCH" ] || [ "$HS_TARGET" != "$TARGET" ]; then
    failed=$((failed + 1))
    echo "recover-stranded-branches: WARN $ID handoff did NOT stick (read back status='${HS_STATUS:-}' assignee='${HS_ASSIGNEE:-}' branch='${HS_BRANCH:-}' target='${HS_TARGET:-}'; want open + '$REFINERY_ID' + '$BRANCH' + '$TARGET'); the branch is still stranded — retries next cycle" >&2
    # Put the bead back in the candidate set rather than leaving it held by an
    # actor that cannot act on it. ONLY our own assignee is released — a different
    # one means another actor took the bead between the write and this read, and
    # clearing that is stealing a live claim. Its own single-flag update: a claim
    # guard can roll back a batched release and lose both writes.
    if [ "$HS_ASSIGNEE" = "$REFINERY_ID" ]; then
      bd_pinned update "$ID" --assignee="" >/dev/null 2>&1 || true
      read_handoff "$ID"
      if [ -n "$HS_ASSIGNEE" ]; then
        echo "recover-stranded-branches: WARN $ID could not be released back to unassigned (reads status='${HS_STATUS:-}' assignee='$HS_ASSIGNEE' branch='${HS_BRANCH:-}' target='${HS_TARGET:-}'); it is now held by '$REFINERY_ID' with an incomplete handoff and no longer matches this pass's candidate shape, so nothing retries it. Repair by hand: gc bd update $ID --status=open --set-metadata branch='$BRANCH' --set-metadata target='$TARGET'" >&2
      fi
    fi
    continue
  fi

  recovered=$((recovered + 1))
  echo "recover-stranded-branches: RECOVERED $ID -> '$REFINERY_ID' (branch '$BRANCH' @ ${HEAD_SHA:0:12}, $AHEAD commit(s) ahead of '$TARGET', no PR, no live molecule) — completed work that was pushed but never submitted (tk-f69ay)"
  bd_pinned update "$ID" \
    --set-metadata stranded_branch_recovered="$BRANCH@$HEAD_SHA" \
    --append-notes "recover-stranded-branches: branch '$BRANCH' was published at $HEAD_SHA with $AHEAD commit(s) ahead of '$TARGET' ($TARGET_SOURCE) and no pull request, while the bead was unassigned, unrouted, unstamped, and no live session stood behind its molecule — the polecat pushed and then died before its submit step, leaving completed work with no landing path. Handed to '$REFINERY_ID' with target='$TARGET'; the branch content was NOT touched. If the implementation is incomplete, the codex gate will say so and file rework as usual (tk-f69ay)." \
    >/dev/null 2>&1 || true
  # This is the "work was nearly lost" row of the witness's own escalation table —
  # a crash that cost a submit step is worth a human knowing about, and the marker
  # written above bounds it to once per bead.
  gc mail send mayor/ -s "STRANDED BRANCH RECOVERED: $ID" \
    -m "Bead $ID carried a published branch with no landing path and has been handed to the refinery.

Branch: $BRANCH @ $HEAD_SHA ($AHEAD commit(s) ahead of $TARGET, target resolved from $TARGET_SOURCE)
Was: open, unassigned, unrouted, no merge_result, no PR, no live session behind its molecule — invisible to pool demand, to the refinery queue, to every PR-keyed reconcile pass, and to the witness's worktree salvage (the work was already committed and pushed, so there was nothing 'at risk' to salvage).
Now: assigned to $REFINERY_ID with branch/target stamped, i.e. the submit step its polecat died before reaching.
Worth a look: the branch was reviewed by nobody before this pass, so if the polecat died MID-implementation the codex gate is what will catch it (tk-f69ay)." >/dev/null 2>&1 || true
done <<< "$CANDIDATES"

# Prompt the refinery only when we are not it — from its own idle loop the nudge is
# pointless, since its find-work re-check picks the bead up in the same cycle.
if [ "$recovered" -gt 0 ] && [ "$DRY_RUN" != 1 ] && [ "${GC_AGENT:-}" != "$REFINERY_ID" ]; then
  gc session nudge "$REFINERY_ID" "Stranded branch(es) recovered and handed off; run 'gc prime' and check the queue." >/dev/null 2>&1 || true
fi

echo "recover-stranded-branches: $recovered recovered, $reported reported (not handed off), $skipped skipped, $failed failed"
[ "$failed" -eq 0 ]
