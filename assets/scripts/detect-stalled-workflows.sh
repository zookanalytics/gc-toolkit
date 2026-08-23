#!/usr/bin/env bash
# detect-stalled-workflows — signal a graph.v2 workflow whose frontier has stopped
# advancing and which nothing in the city can pick up (tk-xesf6).
#
# THE GAP THIS FILLS. A workflow that stops advancing emits nothing. No alarm, no
# escalation, no board entry — every existing consumer keys on BEADS, and a stalled
# workflow's beads are individually healthy:
#
#   mol-liveness-sweep       candidates come from `gc bd ready`, and a workflow ROOT
#                            is blocked by its own workflow-finalize step, so no root
#                            is ever a candidate. Its STEPS do reach the candidate
#                            set — and are then dropped by the class-2(i)(c) edge
#                            check, because every graph.v2 step `tracks` its still-
#                            open root. That edge is true of every step of every
#                            workflow, moving or not (verified on sl-um8j).
#   witness recover-orphaned assignee + dead session — scoped to ASSIGNED beads, and
#                            a stalled frontier is unassigned by construction
#   recover-stranded-branches requires metadata.branch — a workflow that stalled
#                            before its worktree step pushed nothing
#   quiesce-completed-workflows judges the ANCHOR, and de-routes; it never asks
#                            whether a live workflow is moving
#   deacon / refinery patrols key on session queues and the merge queue; a stalled
#                            workflow has neither an assignee nor a merge handoff
#
# Each is right about its own question. The unasked one is whether the workflow is
# still MOVING — visible only in the time derivative, which nothing computed.
#
# WHAT COUNTS AS STALLED. Four conditions, all of them, for at least --stall-minutes:
#
#   1. SILENT      no bead of the workflow has been written — the root or any bead
#                  carrying `gc.root_bead_id=<root>`, in ANY status.
#   2. UNHELD      no live session stands behind it (the root's `gc.session_name`,
#                  or any member's assignee, in the live roster).
#   3. STARTED     the graph closed at least one step, so it demonstrably moved and
#                  then stopped. See the husk note below — this is the whole of what
#                  keeps this pass from reporting every molecule in the rig.
#   4. UNCLAIMABLE its frontier — the EXECUTABLE members `gc bd ready` returns, i.e.
#                  whose blockers are all closed, less graph.v2's own inert descriptor
#                  beads (see is_executable_kind) — is non-empty and EVERY frontier
#                  bead is unassigned AND unrouted. No pool can be offered it and no
#                  session holds it, so no actor in the city can advance it.
#
# WHY (3) IS THE HUSK GUARD, AND WHY IT IS NOT THE ANCHOR. The obvious husk test —
# "the anchor is terminal", the predicate quiesce-completed-workflows.sh uses — is
# WRONG here, and the two live instances this bead was filed on are why. The anchor
# describes the WORK, and one anchor carries several molecules over its life: a
# rework molecule is poured against an anchor that ALREADY wears `merge_result=
# pull_request` from the round being reworked, and mol-scoped-work stamps that marker
# at its own submit step, before its graph finishes. So a terminal anchor is not
# evidence that THIS workflow is done — it exempted both live stalls, and (bead
# tk-8m8d4, filed separately) it is what created one of them.
#
# "Closed at least one step" is the workflow's own evidence, and it happens to split
# the population exactly where it should: mol-polecat-work runs its steps INLINE and
# closes NONE of them (tk-p9ji9), so every husk of the city's most common formula has
# zero closed members and is exempt here, deliberately and by construction. The cost
# is stated plainly: a workflow that stalls before closing anything is invisible to
# this pass. That case is not silent in the same way — a polecat that died mid-run
# leaves an assigned bead for orphan recovery, and one that pushed leaves a branch
# for recover-stranded-branches — and reporting it would mean reporting every
# stranded husk in the rig, which is the escalation noise tk-jbv0r and tk-76jxq are
# already about.
#
# WHAT IS EXEMPT, AND WHY EACH WAIT HAS A NAME:
#
#   live session      somebody is working it. Implementation routinely outlasts any
#                     wall-clock threshold, so this is the guard, not the timer.
#   routed frontier   demand exists and the pool has simply not gotten to it. A quiet
#                     pool is a real wait with an owner (the deacon's queue-starvation
#                     pass); it is NOT this detector's business. This pass finds
#                     workflows nobody CAN work, never ones nobody HAS worked yet.
#   assigned frontier a session holds it. If that session is dead, the bead is an
#                     ORPHAN and the witness's own recovery pass owns it.
#   empty frontier    `gc bd ready` returns nothing for this workflow, so something
#                     is blocking every member — an external dependency, a human
#                     gate, a blocked-status cascade. That wait has a name in the
#                     graph, which is precisely what P3 asks of it.
#   descriptor-only   the only ready members are the inert descriptor beads graph.v2
#     frontier        pours alongside its steps (gc.kind=spec/scope). Every EXECUTABLE
#                     member is still blocked, so this is the empty-frontier wait
#                     wearing a disguise — not a workflow nobody can work.
#   operator hold     `triage.hold` or `gc.takeaway` on the root: a human decided
#                     this waits, and the value is the reason (mol-liveness-sweep
#                     class 4(c)/(d) — same fields, same absent-vs-empty tri-state).
#                     ONE exception, and only for the takeaway (tk-2cyxo): one whose
#                     RECORDED WAIT — its `blocks` edges and its children — has fully
#                     closed names a wait that ENDED, and stops muting. `triage.hold`
#                     never does: it names its wait in prose, with no edge to
#                     discharge, so nothing can say it is over.
#   suspended rig     needs no test: this pass runs FROM the rig's own witness patrol,
#                     so a rig that is stopped runs no patrol and emits no signal.
#
# ONE SIGNAL PER STALLED WORKFLOW, NOT ONE PER PASS. Two independent guards, because
# the marker alone was self-defeating (tk-1g9yw):
#
#   visit-already-open  the PRIMARY guarantee. Before filing, this pass skips a root
#                       that already has an OPEN visit naming it (stall_root=<root>),
#                       exactly as mol-liveness-sweep and mol-triage-recurrence skip a
#                       subject whose visit is already live. One open visit per stalled
#                       root, however many passes run and however the frontier shifts. A
#                       visit may sit open indefinitely — the operator gets to it — so
#                       this guard, not any timer, is what bounds the converse fleet.
#   stall_flagged       the BACKSTOP, for after a visit has been closed. Keyed to the
#                       OBSERVATION — the sorted frontier bead-id set — the way
#                       recover-stranded-branches.sh keys `stranded_branch_flagged` to
#                       `<branch>@<tip>`. A workflow that stays stuck keeps the same
#                       frontier and is never re-reported; one that advances and stalls
#                       again has a DIFFERENT frontier and is reported once more.
#
# The marker was ORIGINALLY keyed to the root's last-touch (max updated_at over the root
# and its members), and that was a self-defeating key: stamping the marker is a `bd
# update`, every update sets updated_at = now, so the dedup WRITE bumped the very field
# the dedup KEY was read from. One stall window later the recomputed last-touch no longer
# matched the stored marker, the SAME workflow was re-flagged, and a fresh visit — and a
# fresh converse session — was minted, forever. That is the amplifier tk-1g9yw was filed
# on. The frontier set is not in the last-touch computation, so stamping the root cannot
# invalidate it. The patrol runs continuously, so a per-pass signal would be a per-minute
# signal.
#
# NOT set -e: best-effort, must never abort the witness patrol mid-pass. Any tool
# error skips that root and retries next cycle. FAIL-SAFE DIRECTION throughout: a
# fact that cannot be established REPORTS NOTHING rather than guessing, because every
# input here is one that, misread, turns a healthy workflow into an escalation — an
# unread session roster makes every running polecat look dead, and an unreadable
# ready listing makes every frontier look unclaimable.
set -uo pipefail

DRY_RUN=0
STALL_MINUTES=120
RIG_PIN=""
CONVERSE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --stall-minutes) STALL_MINUTES="${2:-120}"; shift 2 ;;
    --rig) RIG_PIN="${2:-}"; shift 2 ;;
    --converse) CONVERSE="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

case "$STALL_MINUTES" in
  ''|*[!0-9]*)
    echo "detect-stalled-workflows: --stall-minutes must be a whole number of minutes (got '$STALL_MINUTES')" >&2
    exit 1 ;;
esac

# The conversation pool a stall is surfaced to, same address mol-liveness-sweep
# files its batch visit to. Resolved from the env when not given.
[ -n "$CONVERSE" ] || CONVERSE="${GC_RIG:+$GC_RIG/}gc-toolkit.converse"

# ── Is a takeaway's named wait SPENT? (tk-2cyxo) ─────────────────────────────
# The predicate has ONE implementation — detect-parked-dispositions.sh, which also
# files the visit back when a parked subject's routed work lands — and this pass
# ASKS it rather than growing a second copy. A mirrored predicate in two scripts is
# two things to keep in step, and the failure of that is silent on both sides.
#
# FAIL-CLOSED, and the direction matters: no sibling script, not executable, an
# unreadable read, or a wait that was never recorded all answer "not spent", which
# leaves the takeaway muting exactly as it did before this carve-out existed. A rig
# that has not synced the sibling script keeps the old behaviour rather than losing
# the mute.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SPENT_TOOL="${GC_PARKED_DISPOSITIONS_TOOL:-$SCRIPT_DIR/detect-parked-dispositions.sh}"
wait_spent() { # <bead-id>
  [ -n "${1:-}" ] || return 1
  [ -x "$SPENT_TOOL" ] || return 1
  if [ -n "$RIG_PIN" ]; then
    "$SPENT_TOOL" --rig "$RIG_PIN" --wait-spent "$1" >/dev/null 2>&1
  else
    "$SPENT_TOOL" --wait-spent "$1" >/dev/null 2>&1
  fi
}

bd_pinned() { # <bd-subcommand> [args...]
  if [ -n "$RIG_PIN" ]; then
    gc bd --rig "$RIG_PIN" "$@"
  else
    gc bd "$@"
  fi
}

# Control characters in a bead's notes break jq (tk-6kf6r); strip the range that
# cannot appear in valid JSON string content, sparing TAB/LF/CR.
scrub() { tr -d '\000-\010\013\014\016-\037'; }

NOW=$(date -u +%s)
THRESHOLD=$((STALL_MINUTES * 60))

# Epoch seconds for an ISO-8601 timestamp, empty when it cannot be parsed. A bead
# whose timestamp does not parse is SKIPPED rather than dated to the epoch, which
# would read as infinitely stale and report every such workflow.
epoch_of() {
  [ -n "${1:-}" ] || { printf ''; return; }
  date -u -d "$1" +%s 2>/dev/null || printf ''
}

# --- bulk reads -------------------------------------------------------------
# Three listings, each fail-safe. ALIVE is LIVE widened by the statuses LIVE omits:
# a member that is blocked, deferred, pinned or hooked is still a member, and its
# updated_at is still evidence the workflow moved. Reading only open+in_progress
# would date a workflow by a subset of itself (the same widening mol-liveness-sweep
# had to add for its edge check, live case tk-dhue).
LIVE=$(bd_pinned list --status=open,in_progress --limit=0 --json 2>/dev/null)
WIDEN=$(bd_pinned list --status=blocked,deferred,pinned,hooked --limit=0 --json 2>/dev/null)
READY=$(bd_pinned ready --limit=0 --json 2>/dev/null)
for pair in "LIVE:$LIVE" "WIDEN:$WIDEN" "READY:$READY"; do
  name="${pair%%:*}"; body="${pair#*:}"
  if [ -z "$body" ] || ! printf '%s' "$body" | scrub | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "detect-stalled-workflows: FAIL-SAFE the $name listing did not return a readable array; reporting NOTHING this pass — a workflow can only be called stalled against listings that were actually read, and an unread one makes every frontier look unclaimable. Retries next cycle" >&2
    exit 0
  fi
done
ALIVE=$(printf '%s\n%s' "$LIVE" "$WIDEN" | scrub | jq -s -c 'add')

# --- session roster: who is actually alive ----------------------------------
# Same two sources and the same fail-safe as recover-stranded-branches.sh, so the
# two passes cannot disagree about who exists. `drained`, `asleep`, `suspended` and
# `quarantined` all still have an owner.
SESSIONS_JSON=$(gc session list --state=all --json 2>/dev/null); SESSIONS_RC=$?
SESSION_BEADS_JSON=$(bd_pinned list --type=session --label=gc:session --include-infra \
  --include-gates --all --json --limit=0 2>/dev/null) || SESSION_BEADS_JSON=""

SESSION_COUNT=$(printf '%s' "$SESSIONS_JSON" | jq -r '(.sessions // []) | length' 2>/dev/null)
[ -n "$SESSION_COUNT" ] || SESSION_COUNT=0

ROSTER_WHY=""
if [ "$SESSIONS_RC" -ne 0 ]; then
  ROSTER_WHY="the live session roster could not be READ (gc session list --state=all --json exited $SESSIONS_RC)"
elif ! printf '%s' "$SESSIONS_JSON" \
     | jq -e 'type == "object" and has("sessions") and (.sessions | type == "array")' >/dev/null 2>&1; then
  ROSTER_WHY="the live session roster did not PARSE as {\"sessions\": [...]}"
elif [ "$SESSION_COUNT" -eq 0 ]; then
  ROSTER_WHY="the live session roster is EMPTY (0 sessions listed) while this pass is itself running in one, so it is not a census of who is alive"
fi

ALIVE_IDS=$(printf '%s' "$SESSIONS_JSON" | jq -r '
  (.sessions // [])[]
  | select(((.closed // false) | not))
  | select((((.state // "") | ascii_downcase)) as $s | $s != "closed" and $s != "archived")
  | [.id, .name, .session_name, .alias, .agent_name][]
  | select(. != null and . != "")' 2>/dev/null)

ALIVE_NAMED=$(printf '%s' "$SESSION_BEADS_JSON" | scrub | jq -r '
  .[]?
  | select(((.status // "") | ascii_downcase) != "closed")
  | select(((((.metadata // {}).state // "") | ascii_downcase)) as $s | $s != "closed" and $s != "archived")
  | ((.metadata // {}).configured_named_identity // empty)
  | select(. != "")' 2>/dev/null)
if [ -n "$ALIVE_NAMED" ]; then
  ALIVE_IDS="${ALIVE_IDS:+$ALIVE_IDS
}$ALIVE_NAMED"
fi

if [ -z "$ROSTER_WHY" ] && [ -z "$ALIVE_IDS" ]; then
  ROSTER_WHY="the session roster produced no identities at all ($SESSION_COUNT session(s) listed)"
fi
# The roster decides condition (2), and it is the ONE input whose failure mode is a
# wrong ESCALATION rather than a missed one: an unread roster makes every running
# molecule look unheld, so every long implementation becomes a stalled workflow.
if [ -n "$ROSTER_WHY" ]; then
  echo "detect-stalled-workflows: FAIL-SAFE $ROSTER_WHY; reporting NOTHING this pass — a workflow can only be proved unheld against a roster that was actually read. Retries next cycle" >&2
  exit 0
fi

# A here-string, never `... | grep -qxF`: `set -o pipefail` is on and `grep -q`
# exits at its first match, SIGPIPEing the writer and reporting 141 — a true answer
# read as false.
is_alive() {
  [ -n "${1:-}" ] || return 1
  grep -Fxq -- "$1" <<< "$ALIVE_IDS"
}

# --- candidate roots --------------------------------------------------------
# A graph.v2 root carries `gc.input_convoy_id` and appears in the ordinary
# open/in_progress listing. Selected by CONTRACT, not by formula name — the same
# rule quiesce-completed-workflows.sh had to be corrected to (tk-q5r65), so a
# formula poured next is covered without an edit here.
#
# FIELDS ARE JOINED ON US (0x1f), NEVER ON A TAB, and read back with IFS set to the
# same. Tab is IFS *whitespace*: consecutive tabs collapse into one delimiter, so an
# empty interior field shifts every later field left by one. Most of the fields here
# are empty on most beads — `triage.hold`, `gc.takeaway`, `stall_flagged` and a
# member's `assignee`/`gc.routed_to` are absent on almost every row — so with @tsv
# a workflow's TITLE lands in `rhold` and reads as an operator hold, and a member's
# routing lands in `assignee` and reads as claimed. Both misreads are SILENT and both
# suppress a real signal; the first was observed on the live pass that found this.
# A non-whitespace delimiter preserves empty fields exactly. `scrub` strips 0x1f from
# the JSON before jq runs, so no bead value can smuggle one in, and the title's
# newlines are folded because a raw one would split the row.
SEP=$(printf '\037')
ROOT_ROWS=$(printf '%s' "$LIVE" | scrub | jq -r '
  .[]
  | ((.metadata // {})) as $m
  | select((($m["gc.input_convoy_id"] // "") | tostring) != "")
  | [(.id // ""),
     ((.updated_at // "") | tostring),
     (($m["gc.session_name"] // "") | tostring),
     (($m["triage.hold"] // "") | tostring),
     (($m["gc.takeaway"] // "") | tostring),
     (($m.stall_flagged // "") | tostring),
     (($m["gc.input_convoy_id"] | tostring)),
     (((.title // "") | tostring) | split("\n") | join(" "))]
  | join("\u001f")' 2>/dev/null)

if [ -z "$ROOT_ROWS" ]; then
  echo "detect-stalled-workflows: no live graph.v2 workflow roots"
  exit 0
fi

# member rows: root US id US updated_at US assignee US routed_to US kind
MEMBER_ROWS=$(printf '%s' "$ALIVE" | scrub | jq -r '
  .[]
  | ((.metadata // {})) as $m
  | select((($m["gc.root_bead_id"] // "") | tostring) != "")
  | [(($m["gc.root_bead_id"] | tostring)),
     (.id // ""),
     ((.updated_at // "") | tostring),
     ((.assignee // "") | tostring),
     (($m["gc.routed_to"] // "") | tostring),
     (($m["gc.kind"] // "") | tostring)]
  | join("\u001f")' 2>/dev/null)

READY_IDS=$(printf '%s' "$READY" | scrub | jq -r '.[].id // empty' 2>/dev/null)
is_ready() { grep -Fxq -- "$1" <<< "$READY_IDS"; }

# --- what can actually take demand ------------------------------------------
# graph.v2 pours DESCRIPTOR beads alongside its steps — `mol-scoped-work` materialises
# `gc.kind=spec` ("Step spec for <step>") and `gc.kind=scope` ("Worktree body scope").
# They carry `gc.root_bead_id`, so they are members; they go ready the moment their
# blockers close; and they are unassigned and unrouted FOREVER, because nothing is ever
# meant to work them. That is, verbatim, condition (4)'s definition of an unclaimable
# frontier bead — so without this filter a mol-scoped-work graph reads as stalled
# through beads that are doing exactly what they were poured to do.
#
# Measured on the live case (tk-6mccf; visit tk-0o6gw against root tk-s68nh, 2026-08-13):
# of the 8 beads reported as that workflow's frontier, SEVEN were gc.kind=spec and one —
# tk-y8tb3 — was the real step. The report told the operator to give demand to beads that
# cannot take it. Worse than cosmetic, because the frontier set is also the dedup key: it
# was dominated by seven ids that never change, so the real frontier could move and the
# recomputed key would still match stall_flagged and stay silent.
#
# An ALLOW-LIST, not a deny-list on spec/scope. Inertness is what gets STAMPED here —
# `gc.kind` is ABSENT on ordinary step beads (3896 of 4480 beads in this rig, 2026-08-14)
# and present on the descriptors — so naming the executable kinds excludes the next inert
# kind on the day it is poured, instead of letting it silently re-enter reports. The cost
# falls in the direction this file always chooses: a new EXECUTABLE kind is filtered out
# and its stall goes unreported until it is named here, which is a missed signal rather
# than a false escalation.
#
# The list is read off the PRODUCER CONTRACT, not off this rig's ledger. The first cut of
# this filter named the kinds a listing over gc-toolkit actually returned, and a listing
# is a sample, not a vocabulary. The executable control set is `beadmeta.ControlKinds` —
# exactly eight, `rigs/gascity/internal/beadmeta/kindsets.go`, behavior owner the
# one-case-per-member `ProcessControl` switch in `internal/dispatch/runtime.go`, kept in
# lockstep by TestControlKindsExact. Five of those eight (ralph, check, retry-eval,
# fanout, drain) had never been poured in this rig, so the sampled list dropped them —
# and a dropped control kind does not fail loudly here, it reads as INERT: an unrouted
# `check` on the frontier is filtered out, the frontier goes empty, the workflow is
# counted as a descriptor-only wait, and the stall is never reported. An unrouted control
# bead is precisely the missing-route class this pass exists to surface, so the
# sample-derived list hid the case it was written to find (caught in review of tk-6mccf;
# su-pepq is a live `ralph` control bead in the shutupandlisten rig).
#
# WORKER-EXECUTED — an ordinary pool actor claims these:
#   «absent»          ordinary graph.v2 step beads — the whole of mol-polecat-work's graph
#   task              mol-scoped-work's real step (tk-y8tb3 "Load context…", .attempt.2)
#   cleanup           mol-scoped-work.cleanup-worktree (tk-qbpcx, routed to
#                     gc-toolkit/gc-toolkit.polecat). It sits in
#                     beadmeta.StructuralGraphKinds rather than ControlKinds, but that set
#                     is about what ProcessControl dispatches, not about what can take
#                     demand — a worker claims this one.
# CONTROL — beadmeta.ControlKinds in full, dispatched to core.control-dispatcher. Routed
# is their normal state, and a routed frontier exempts at `offerable` anyway; it is the
# UNROUTED one — a control bead nothing can retire — that has to reach the report:
#   retry             a re-poured attempt of a real step (tk-23ka0 "Implement…")
#   ralph             a check-loop controller (su-pepq "Write review report")
#   check             one check-loop iteration's check bead
#   retry-eval        the retry controller's verdict step
#   fanout            engine-minted from [steps.on_complete] (EngineMintedOnlyKinds)
#   drain             the drain control
#   scope-check       "Finalize scope for <step>" (tk-2o7ep)
#   workflow-finalize the machinery's own finalize step (tk-c93ed)
# EXCLUDED — beadmeta.WorkflowTopologyKinds, whose docstring is the contract-level
# statement of the inertness this filter keys on: "Routing never lands on these; agents
# must never claim them."
#   spec              "Step spec for <step>" (tk-1rrpg) — never routed, never assigned
#   scope             "Worktree body scope" (tk-ltus2) — likewise
#   workflow          a ROOT, which is never a member (it carries gc.input_convoy_id, not
#                     gc.root_bead_id) — listed for completeness, it cannot reach here
is_executable_kind() {
  case "${1:-}" in
    # worker-executed
    ''|task|cleanup) return 0 ;;
    # beadmeta.ControlKinds, all eight — core.control-dispatcher's whole vocabulary
    retry|ralph|check|retry-eval|fanout|drain|scope-check|workflow-finalize) return 0 ;;
    *) return 1 ;;
  esac
}

# --- the standing triage subject a stall visit hangs off ---------------------
# One per rig, created on first signal and reused after — the same shape
# mol-liveness-sweep uses for its own scope, so a stall lands in the vocabulary the
# board and the sweep already speak.
SUBJECT=""
resolve_subject() {
  [ -z "$SUBJECT" ] || return 0
  SUBJECT=$(printf '%s' "$LIVE" | scrub | jq -r '[.[]
    | select(((.metadata // {}).task_kind // "") == "triage-subject")
    | select(((.metadata // {})["triage.scope"] // "") == "stalled-workflows")] | (.[0].id // "")' 2>/dev/null)
  [ -z "$SUBJECT" ] || return 0
  SUBJECT=$(bd_pinned create -t task --title "triage: stalled workflows (this rig)" \
    -d "Standing triage scope: graph.v2 workflows that stopped advancing — silent, unheld by any live session, and with a frontier no pool or session can be offered. Filed by assets/scripts/detect-stalled-workflows.sh from the witness patrol, one visit per stalled workflow, deduped by the stall_flagged marker on the root (tk-xesf6)." \
    --json 2>/dev/null | scrub | jq -r '.id // .[0].id // ""' 2>/dev/null)
  [ -n "$SUBJECT" ] && [ "$SUBJECT" != "null" ] || { SUBJECT=""; return 1; }
  bd_pinned update "$SUBJECT" --set-metadata "task_kind=triage-subject" \
    --set-metadata "triage.scope=stalled-workflows" >/dev/null 2>&1 || true
  return 0
}

stalled=0; moving=0; unheld_skip=0; never_started=0; landed=0; held=0; gated=0
claimable=0; already=0; visit_open=0; failed=0; unreadable=0; inert_only=0

while IFS="$SEP" read -r root rupd rsession rhold rtakeaway rflagged rconvoy rtitle; do
  [ -n "${root:-}" ] || continue

  MINE=$(printf '%s\n' "$MEMBER_ROWS" | awk -v FS="$SEP" -v r="$root" '$1 == r')

  # (1) SILENCE, part one: the cheap half. Anything non-closed written recently
  # settles it without the per-root closed-member read below.
  last=$(epoch_of "$rupd")
  if [ -z "$last" ]; then
    echo "detect-stalled-workflows: root $root — updated_at '$rupd' did not parse; skipped" >&2
    unreadable=$((unreadable + 1)); continue
  fi
  while IFS="$SEP" read -r _r _id mupd _a _rt _k; do
    [ -n "${_id:-}" ] || continue
    e=$(epoch_of "$mupd")
    [ -n "$e" ] && [ "$e" -gt "$last" ] && last="$e"
  done <<< "$MINE"
  if [ $((NOW - last)) -lt "$THRESHOLD" ]; then
    moving=$((moving + 1)); continue
  fi

  # (1) SILENCE, part two, and (3) STARTED — one read answers both. Closed members
  # are NOT optional: a step CLOSING is the graph advancing, and it is routinely the
  # workflow's most recent event. Verified on sl-xhfl, whose closed steps were last
  # written at 19:30:06Z while every non-closed member sat at 19:19:10Z — dated by
  # the live members alone, a workflow that had just moved would read as stalled.
  CLOSED=$(bd_pinned list --status=closed --metadata-field "gc.root_bead_id=$root" \
    --limit=0 --json 2>/dev/null)
  if [ -z "$CLOSED" ] || ! printf '%s' "$CLOSED" | scrub | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "detect-stalled-workflows: root $root — closed-member listing unreadable; skipped (a workflow cannot be dated by its live members alone)" >&2
    unreadable=$((unreadable + 1)); continue
  fi
  closed_count=$(printf '%s' "$CLOSED" | scrub | jq -r 'length' 2>/dev/null)
  [ -n "$closed_count" ] || closed_count=0
  closed_max=$(printf '%s' "$CLOSED" | scrub | jq -r '[.[].updated_at // empty] | max // ""' 2>/dev/null)
  e=$(epoch_of "$closed_max")
  [ -n "$e" ] && [ "$e" -gt "$last" ] && last="$e"
  silent_for=$((NOW - last))
  if [ "$silent_for" -lt "$THRESHOLD" ]; then
    moving=$((moving + 1)); continue
  fi

  # (3) STARTED. A workflow that has closed NOTHING is indistinguishable from an
  # inline-execution husk (mol-polecat-work closes no step, ever), which the city
  # manufactures deliberately and leaves stranded-but-quiet. Reporting those would
  # mean reporting most molecules in the rig.
  if [ "$closed_count" -eq 0 ]; then
    never_started=$((never_started + 1)); continue
  fi

  # (3), second half: THE WORK LANDED. A husk can acquire a closed step — somebody
  # closes `load-context` by hand to stop the re-offer churn, and the molecule then
  # wears the "it moved once" signature while being as dead as any other husk.
  # Measured on this rig: three such molecules, all reported by the closed-step test
  # alone, all with anchors CLOSED and MERGED (tk-5eikz/PR#306, tk-0981e/PR#299).
  #
  # So the anchor is consulted, but ONLY for the two states that are unambiguous:
  # `closed` and `merge_result=merged` mean the work this workflow existed to do is
  # finished and landed, and no live molecule wears them. Every other "terminal"
  # state quiesce-completed-workflows.sh recognises is deliberately NOT honoured
  # here — `pull_request`, `pre_open_gate`, a refinery handoff, a human park are all
  # states a live molecule wears mid-flight, and `pull_request` in particular is what
  # a REWORK molecule's anchor already carries from the round being reworked. Taking
  # those as proof of completion is what made both live stalls invisible.
  anchor=""
  [ -n "$rconvoy" ] && anchor=$(gc convoy status "$rconvoy" --json 2>/dev/null \
    | scrub | jq -r 'if ((.children // []) | length) == 1 then (.children[0].id // empty) else empty end' 2>/dev/null)
  if [ -z "$anchor" ]; then
    echo "detect-stalled-workflows: root $root — anchor unresolved (convoy '${rconvoy:-none}'); skipped, so a landed workflow is never reported on a read that did not happen" >&2
    unreadable=$((unreadable + 1)); continue
  fi
  ainfo=$(bd_pinned show "$anchor" --json 2>/dev/null | scrub | jq -r '.[0]
    | [((.status // "") | tostring),
       (((.metadata // {}).merge_result // "") | tostring),
       (((.metadata // {})["triage.hold"] // "") | tostring),
       (((.metadata // {})["gc.takeaway"] // "") | tostring)]
    | join("\u001f")' 2>/dev/null)
  astatus=""; amerge=""; ahold=""; atakeaway=""
  IFS="$SEP" read -r astatus amerge ahold atakeaway <<< "$ainfo"
  # Every real bead carries a status, so an empty one means the READ failed rather
  # than "an anchor with no status".
  if [ -z "$astatus" ]; then
    echo "detect-stalled-workflows: root $root — anchor $anchor unreadable; skipped" >&2
    unreadable=$((unreadable + 1)); continue
  fi
  if [ "$astatus" = "closed" ] || [ "$amerge" = "merged" ]; then
    landed=$((landed + 1)); continue
  fi

  # Operator hold — the wait has a name and a human owns it. Non-empty is the test:
  # an EMPTY stamp is a CLEARED hold, the same tri-state mol-liveness-sweep reads.
  # Checked on the anchor as well as the root, because a hold is placed on the bead a
  # human is looking at, which is the work bead far more often than the workflow root.
  #
  # ONE CARVE-OUT, and only for `gc.takeaway` (tk-2cyxo). The rule above is right in
  # general: a takeaway means a human named the wait and owns it. It is wrong in
  # exactly one case — a takeaway whose recorded wait has FULLY CLOSED, where the
  # named wait has ENDED. A stamp that says "next sitting when the findings land" is
  # a hold until they land and a stale marker afterwards, and this pass treating it
  # as a live hold forever is half of why a parked subject could never be brought
  # back by anything (the other half is that nothing filed the visit; that is the
  # sibling pass). `triage.hold` is deliberately NOT carved out: it names a wait in
  # prose with no edge to discharge, so nothing can say it ended.
  #
  # Asked per bead, because each stamp names its own wait: a spent takeaway on the
  # ROOT does not clear a live one on the ANCHOR.
  if [ -n "$rtakeaway" ] && wait_spent "$root"; then
    rtakeaway=""
    echo "detect-stalled-workflows: root $root — the takeaway's recorded wait has fully closed; it no longer mutes this pass (tk-2cyxo)"
  fi
  if [ -n "$atakeaway" ] && wait_spent "$anchor"; then
    atakeaway=""
    echo "detect-stalled-workflows: root $root — anchor $anchor's takeaway wait has fully closed; it no longer mutes this pass (tk-2cyxo)"
  fi
  if [ -n "$rhold" ] || [ -n "$rtakeaway" ] || [ -n "$ahold" ] || [ -n "$atakeaway" ]; then
    held=$((held + 1)); continue
  fi

  # (2) UNHELD. Two signals, because each covers a different moment: the root's
  # session is stamped when the molecule is poured, a member's assignee is what a
  # re-claimed or re-nudged molecule carries.
  molecule_live=0
  is_alive "$rsession" && molecule_live=1
  if [ "$molecule_live" -eq 0 ]; then
    while IFS="$SEP" read -r _r _id _u massignee _rt _k; do
      [ -n "${massignee:-}" ] || continue
      if is_alive "$massignee"; then molecule_live=1; break; fi
    done <<< "$MINE"
  fi
  if [ "$molecule_live" -eq 1 ]; then
    unheld_skip=$((unheld_skip + 1)); continue
  fi

  # (4) UNCLAIMABLE. The frontier is the members `gc bd ready` returns — every blocker
  # closed, nothing gating them — LESS the inert descriptor beads, which are ready and
  # unroutable by construction and so satisfy the unclaimable test without meaning it
  # (is_executable_kind). An EMPTY frontier means something outside is blocking the whole
  # workflow, which is a named wait, not a stall.
  #
  # The filter runs BEFORE `offerable` too, so claimability is decided by the beads an
  # actor could actually be handed. Routing a descriptor is not a thing that happens, but
  # if it ever did it would exempt the workflow on a bead no pool would work.
  frontier=""
  offerable=0
  inert_seen=0
  while IFS="$SEP" read -r _r mid _u massignee mrouted mkind; do
    [ -n "${mid:-}" ] || continue
    is_ready "$mid" || continue
    if ! is_executable_kind "$mkind"; then
      inert_seen=$((inert_seen + 1)); continue
    fi
    frontier="${frontier:+$frontier }$mid"
    if [ -n "$massignee" ] || [ -n "$mrouted" ]; then offerable=1; fi
  done <<< "$MINE"
  if [ -z "$frontier" ]; then
    # Counted apart because they are different facts about the graph, and the summary
    # line is where an operator reads what this pass decided: a frontier of nothing but
    # descriptors is a workflow whose every EXECUTABLE member is still blocked.
    if [ "$inert_seen" -gt 0 ]; then
      inert_only=$((inert_only + 1))
    else
      gated=$((gated + 1))
    fi
    continue
  fi
  if [ "$offerable" -eq 1 ]; then
    claimable=$((claimable + 1)); continue
  fi

  # A stable per-observation dedup key: the SORTED frontier bead-id set — the FILTERED
  # one, since `frontier` now holds only executable members. That matters as much for the
  # key as for the report: descriptor beads never close, so including them pinned most of
  # the key to constants and a workflow could advance its real frontier while the
  # recomputed key still matched the stored marker and stayed silent. That set is
  # exactly what makes the workflow stalled, it does not change while the workflow sits,
  # and it changes the instant the workflow advances (a ready bead closes, a new one
  # unblocks). Crucially it is NOT the root's updated_at, so stamping stall_flagged on
  # the root — which, like every bd update, bumps updated_at — cannot invalidate the key
  # it just wrote. That self-defeating dependency was the amplifier (tk-1g9yw). Sorted
  # so the key is independent of the order `gc bd ready` happened to return the members.
  frontier_key=$(printf '%s' "$frontier" | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//')

  # Display-only last-movement timestamp, for the log line and the visit body; NEVER the
  # dedup key. Derived from the last-touch, which the marker no longer depends on.
  last_iso=$(date -u -d "@$last" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  [ -n "$last_iso" ] || last_iso="$last"
  hours=$((silent_for / 3600)); mins=$(((silent_for % 3600) / 60))

  # (5) NOT ALREADY UNDER CONVERSATION — the primary one-visit guarantee. If an OPEN
  # visit already names this root (stall_root=$root), the conversation exists and a
  # second visit would just pile another converse session on the same stall: the exact
  # amplifier this pass must not become. Mirrors the visit-already-live guard in
  # mol-liveness-sweep and mol-triage-recurrence, keyed PER ROOT because this pass files
  # one visit per root rather than one batch visit per subject. FAIL-SAFE like every
  # other read here: an unreadable listing cannot prove no visit is open, so it skips
  # rather than risk the duplicate — the same direction (report nothing) the roster and
  # member reads take.
  OPEN_VISITS=$(bd_pinned list --status=open,in_progress --metadata-field "stall_root=$root" \
    --limit=0 --json 2>/dev/null)
  if [ -z "$OPEN_VISITS" ] || ! printf '%s' "$OPEN_VISITS" | scrub | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "detect-stalled-workflows: root $root — open-visit listing unreadable; skipped, so a second visit is never filed on a read that did not happen" >&2
    unreadable=$((unreadable + 1)); continue
  fi
  open_visits_n=$(printf '%s' "$OPEN_VISITS" | scrub \
    | jq -r '[.[] | select(((.metadata // {}).task_kind // "") == "visit")] | length' 2>/dev/null)
  [ -n "$open_visits_n" ] || open_visits_n=0
  if [ "$open_visits_n" -gt 0 ]; then
    visit_open=$((visit_open + 1)); continue
  fi

  # (6) NOT THE SAME OBSERVATION ALREADY SIGNALLED — the backstop for after a visit was
  # closed. A stall whose frontier has not changed keeps the same key and is never
  # re-reported; one that advanced and re-stalled has a different frontier and earns
  # exactly one more signal.
  if [ "$rflagged" = "$frontier_key" ]; then
    already=$((already + 1)); continue
  fi

  stalled=$((stalled + 1))
  echo "detect-stalled-workflows: root $root STALLED ${hours}h${mins}m — frontier [$frontier] is ready, unassigned and unrouted; $closed_count step(s) closed, last movement $last_iso"

  if [ "$DRY_RUN" -eq 1 ]; then
    continue
  fi

  if ! resolve_subject; then
    echo "detect-stalled-workflows: $root — could not resolve or create the stalled-workflows triage subject; NOT stamping the marker so the next pass retries the whole signal" >&2
    failed=$((failed + 1)); continue
  fi

  VISIT=$(bd_pinned create -t task \
    --title "visit: $root — workflow stalled ${hours}h${mins}m with an unclaimable frontier" \
    -d "$(printf '%s\n' \
      "Workflow root: $root — $rtitle" \
      "" \
      "It has been silent for ${hours}h${mins}m: no bead of this workflow — the root or anything carrying gc.root_bead_id=$root, in any status — has been written since $last_iso." \
      "" \
      "It is not waiting on anything with a name:" \
      "  - no live session holds the root or any member (roster read this pass)" \
      "  - $closed_count step(s) have closed, so the graph did move and then stopped" \
      "  - its frontier is [$frontier] — ready (every blocker closed), yet each of those beads is UNASSIGNED and carries no gc.routed_to, so no pool can be offered them and no session holds them" \
      "  - no triage.hold and no gc.takeaway on the root" \
      "" \
      "Nothing in the city can advance this workflow on its own. Dispositions:" \
      "  - route     give the frontier demand: gc bd update <frontier-bead> --set-metadata gc.routed_to=<pool>" \
      "  - unstick   fix whatever cleared or never set that route; the frontier bead's" \
      "              dolt_history_issues rows say what wrote it last" \
      "  - kill      close the workflow out if the work is moot or was redone elsewhere" \
      "  - hold      if this waits on purpose, name the wait so it stops being reported:" \
      "              gc bd update $root --set-metadata 'triage.hold=<the reason>'" \
      "" \
      "Filed once per observation by assets/scripts/detect-stalled-workflows.sh (tk-xesf6)." \
      "While THIS visit stays open it is never re-filed. The root is stamped stall_flagged=$frontier_key (its current frontier); once the visit is closed it is re-reported only if the workflow advances and stalls again with a different frontier.")" \
    --json 2>/dev/null | scrub | jq -r '.id // .[0].id // ""' 2>/dev/null)

  if [ -z "$VISIT" ] || [ "$VISIT" = "null" ]; then
    echo "detect-stalled-workflows: $root — visit create returned no id; NOT stamping the marker so the next pass retries the signal" >&2
    failed=$((failed + 1)); continue
  fi

  # A visit is only a signal once it is ROUTED and TYPED. `gc.routed_to` is what offers
  # it to the converse pool, `task_kind=visit` is what the board and the converse role
  # select on, `gc.continuation_group` is what ties it to the standing subject on the
  # read side (an exact-string match, gc-helm.sh), and `stall_root` is what the
  # visit-already-open guard above matches on next pass — miss it and every later pass
  # files a fresh duplicate for this same root. Miss any of the first three and the bead
  # exists but nothing is ever offered it — a workflow that stopped advancing and
  # emitted no signal, which is the exact defect this pass was built to end.
  #
  # So the write is VERIFIED, not assumed. `|| true` on the update covers only the half
  # that exits non-zero; the half that matters is the write that exits 0 and persists
  # nothing, and the only way to tell those apart from here is to read it back.
  vrc=0
  bd_pinned update "$VISIT" --set-metadata "gc.routed_to=$CONVERSE" \
    --set-metadata "gc.continuation_group=$SUBJECT" \
    --set-metadata "task_kind=visit" \
    --set-metadata "stall_root=$root" >/dev/null 2>&1 || vrc=$?
  # tracks, NOT parent-child: a parent-child edge transmits the subject's blocked
  # state to the visit, making it unclaimable on exactly the beads that need talking
  # about (the same choice mol-liveness-sweep's gate-visit block makes). Lineage only,
  # and deliberately NOT part of the gate below: what carries the visit to a pool is
  # gc.routed_to, and what resolves it back to the subject is gc.continuation_group —
  # both of which are verified. A missing edge costs provenance, not the signal.
  bd_pinned dep add "$VISIT" "$SUBJECT" --type=tracks >/dev/null 2>&1 || true

  vmeta=$(bd_pinned show "$VISIT" --json 2>/dev/null | scrub | jq -r '.[0]
    | ((.metadata // {})) as $m
    | [(($m["gc.routed_to"] // "") | tostring),
       (($m.task_kind // "") | tostring),
       (($m["gc.continuation_group"] // "") | tostring),
       (($m.stall_root // "") | tostring)]
    | join("\u001f")' 2>/dev/null)
  vrouted=""; vkind=""; vgroup=""; vroot=""
  IFS="$SEP" read -r vrouted vkind vgroup vroot <<< "$vmeta"
  if [ "$vrouted" != "$CONVERSE" ] || [ "$vkind" != "visit" ] || [ "$vgroup" != "$SUBJECT" ] || [ "$vroot" != "$root" ]; then
    echo "detect-stalled-workflows: $root — visit $VISIT did not read back as routed, typed and root-tagged (update exited $vrc; gc.routed_to='$vrouted' want '$CONVERSE', task_kind='$vkind' want 'visit', gc.continuation_group='$vgroup' want '$SUBJECT', stall_root='$vroot' want '$root'); NOT stamping the marker so the next pass re-signals. $VISIT is left behind — nothing will be offered it and the guard cannot find it, so dispose of it by hand if this keeps failing" >&2
    failed=$((failed + 1)); continue
  fi

  # The marker is stamped LAST, and only after the visit exists AND reads back routed.
  # In that order a failed create — or a routing write that did not land — leaves the
  # root unflagged and the next pass re-signals; the reverse would retire the stall on
  # a visit nobody ever saw. And if this stamp itself fails, the visit is still open, so
  # next pass the visit-already-open guard catches it before the missing marker ever
  # matters — the marker is only the backstop for after the visit is closed.
  if ! bd_pinned update "$root" --set-metadata "stall_flagged=$frontier_key" >/dev/null 2>&1; then
    echo "detect-stalled-workflows: $root — visit $VISIT filed but the stall_flagged marker did not stick; harmless while the visit stays open (the guard dedupes), a duplicate only if it is closed before the next pass" >&2
    failed=$((failed + 1)); continue
  fi
  echo "  -> visit $VISIT filed on subject $SUBJECT, root stamped stall_flagged=$frontier_key"
done <<< "$ROOT_ROWS"

MODE=""
[ "$DRY_RUN" -eq 1 ] && MODE="(dry-run) "
echo "detect-stalled-workflows: ${MODE}${stalled} stalled workflow(s) signalled; $moving moving, $unheld_skip held by a live session, $never_started never advanced (husk-shaped), $landed already landed, $held on an operator hold, $gated waiting on a blocker, $inert_only with a descriptor-only frontier, $claimable with a claimable frontier, $visit_open already under an open visit, $already already flagged, $unreadable unreadable, $failed failed"

# Only failed WRITES decide the exit code. An unreadable root is a deliberate
# fail-closed skip, already reported on stderr, and correct.
[ "$failed" -eq 0 ] || exit 1
exit 0
