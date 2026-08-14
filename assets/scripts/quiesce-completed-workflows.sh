#!/usr/bin/env bash
# quiesce-completed-workflows — stop the pool (and the affine hand-back) from
# re-offering the dead step beads of a graph.v2 molecule whose inline execution
# has already finished (tk-p9ji9).
#
# WHICH MOLECULES: every graph.v2 formula, identified by the contract below and
# not by name (tk-q5r65) — mol-polecat-work, mol-scoped-work, and whatever is
# poured next. The row filter is the membership test; see it below for why
# widening it removes no guard.
#
# Background. A graph.v2 formula (mol-polecat-work materializes 7 such steps)
# materializes step beads, but the polecat executes them INLINE in one session
# and no step closes its own bead.
# The step graph is chained (load-context blocks workspace-setup blocks ...), so
# while load-context stays open it is the ONLY ready step — and it still carries
# `gc.routed_to=<rig>/<prefix>polecat`. Open + ready + routed is exactly the
# pool's offer predicate, so every idle polecat is handed the same dead step,
# forever: ~1 wisp per 4-5 min for the entire human-approval wait on the PR. The
# molecule cannot finalize itself either, because under close-on-land its anchor
# stays OPEN until the refinery lands the PR.
#
# The witness has been containing this BY HAND, molecule by molecule (ten of them
# as of 2026-07-22). This pass is that containment, automated.
#
# TWO re-offer shapes, two different levers — clearing `gc.routed_to` alone fixes
# only the first (verified live: `gc hook <pool-agent>` returns open, UNASSIGNED,
# routed, ready beads only, so an assigned step never rides the pool path):
#
#   unassigned shape  assignee empty + gc.routed_to set
#                     -> the POOL offers it. Clearing gc.routed_to removes it.
#   assigned shape    assignee=<polecat session> + gc.session_affinity=require
#                     -> already invisible to the pool; it is handed back on the
#                        ASSIGNED-work path, keyed on the assignee. Clearing
#                        gc.routed_to here is a NO-OP; the assignee must go too.
#
# The two keys are cleared in TWO SEPARATE calls, ROUTE FIRST, then the assignee
# (tk-z27pw). Every part of that shape is load-bearing:
#
#   WHY NOT ONE CALL. bd's claim guard refuses `--assignee ""` on an in_progress
#   step still held by a live session. Batched into a single `gc bd update`, that
#   rejection rolls the WHOLE update back — so `gc.routed_to` is not cleared
#   either, even though unsetting routing alone needs no claim at all. The step
#   stays fully re-offerable, the pass logs "update failed; retries next patrol"
#   every cycle forever, and (before this fix) still exited 0. Splitting the calls
#   means the half that can always land, always lands.
#
#   WHY ROUTE FIRST. The race the single-call design guarded against is real, but
#   it is an ORDER hazard, not a call-count one: clearing the assignee first leaves
#   the bead briefly open + unassigned + routed — the exact pool-offer shape —
#   racing a fresh polecat into the husk we are retiring. Clearing the route first
#   inverts that. The intermediate state is open + assigned + unrouted, which is
#   invisible to the pool, and the assigned hand-back it still rides is simply the
#   state the bead was already in. The window exposes nothing new.
#
#   AND THE ASSIGNEE HALF IS GATED ON IT (tk-d553m). Order alone only rules out
#   the pool-offer shape while the route clear SUCCEEDS. If it is refused and the
#   assignee clear runs anyway, that shape stops being a window and becomes the
#   step's resting state — strictly worse than the assigned+routed husk we found.
#   So a failed route clear skips the assignee clear: the step is left untouched
#   and counted failed, and the next patrol retries it whole.
#
#   WHY --force ON THE ASSIGNEE. We only reach this point when is_terminal_anchor()
#   says the anchor is DONE — i.e. the step graph is SPENT. A REQUEST_CHANGES
#   verdict dispatches rework as a STANDALONE bead (no `gc.step_ref`) sourced from
#   the review bead; it never re-walks the molecule's step graph. So no holder can
#   resume a step of a terminal molecule: the claim is abandoned in exactly the
#   sense --force is reserved for, even while the holding session is alive and
#   looks busy (it is busy re-deriving "already done"). That terminal-anchor check
#   is ONE of exactly TWO gates on --force; the other is the absent-root arm below,
#   which reaches the same "no holder can advance this" conclusion by a different
#   route. Never use --force where neither gate has passed.
#
#   The guard --force overrides is NOT liveness-aware — verified against bd
#   v1.1.1-0.20260729113304: `bd update <id> --assignee ""` is refused on any
#   in_progress bead with an assignee ("cannot reassign …: held by …"), including
#   one held by a session that ended hours ago. So --force is load-bearing rather
#   than belt-and-braces: without it the assigned shape — the one that actually
#   burns polecats — can never be cleared by either gate.
#
#   WHY BARE `bd` FOR THAT ONE CALL. `gc bd` rejects --force in its bead-ID safety
#   pre-check ("cannot safely verify bead IDs (unrecognized flag in args)") and
#   exits 1, so through the wrapper the clear can never land at all. Bare `bd` is
#   the same binary on the same store — it honors the BEADS_DIR the agent env
#   already pins. The pre-check the wrapper adds guards substring resolution of a
#   PARTIAL id; every id here comes verbatim from `gc bd list`, so it is exact.
#
# WHAT THIS PASS NEVER DOES — closing a step bead is the footgun this bug exists
# to prevent. Closing load-context unblocks workspace-setup and walks the next
# polecat forward onto a branch that is ALREADY green-gated and PR'd; any push
# there moves the head, stales the anchor's `check.<gate>=green@<oid>` marker and
# BLOCKS the open PR from merging. There is deliberately no close path in this
# script. It never touches `status`, and never touches the `workflow-finalize`
# step (routed to the control dispatcher — that is the path that finalizes the
# graph, and it must keep its route). On the anchor it writes exactly ONE key,
# `quiesce.terminal_since` — the observation stamp described below, additive,
# read by nothing but this pass, and never a lifecycle field.
#
# Quiescing is containment, not finalization: the molecule is left stranded-but-
# quiet, which is what the witness's manual sweep achieves today. Finalizing the
# step graph at submit-and-exit time is the durable upstream fix (gascity core /
# gastown formula) and is deliberately out of scope here.
#
# THE ANCHOR IS NOT THE MOLECULE (tk-8m8d4). Every predicate below reads the
# ANCHOR, but the question the pass has to answer is about the MOLECULE, and an
# anchor OUTLIVES its molecules: it carries the original, then one more per rework
# round. `merge_result` describes the WORK, not the molecule standing in front of
# it, so on its own it cannot tell "this molecule's run produced that PR" from
# "this molecule exists to fix it". Read as the former, the pass de-routed and
# un-assigned the frontier step of a LIVE rework molecule 87 seconds after a
# polecat claimed it, and that molecule never moved again (signal-loom sl-xhfl /
# step sl-um8j, anchor sl-ew4w wearing `merge_result=pull_request` from PR #533 —
# the very PR the rework existed to fix; verified in dolt_history_issues, route
# cleared 19:19:09Z and assignee 19:19:10Z, this pass's exact two-write signature).
# That is the harm the fail-closed rule above exists to prevent, reached THROUGH
# the gate that was supposed to be the guard.
#
# TWO GUARDS, because the marker can be wrong in two independent directions.
#
#   GUARD 1 — THE MARKER PREDATES THE MOLECULE. If the anchor was already terminal
#   when this molecule was materialized, no run of THIS molecule produced that
#   state. Nothing on a bead records when `merge_result` was written (surveyed:
#   no companion timestamp, `updated_at` is rewritten by every patrol that touches
#   the anchor, `started_at` moves with the anchor's latest claim, and
#   `bd history --json` snapshots carry no metadata at all), so the pass has to
#   build the date itself, out of its own observations, in `quiesce.terminal_since`
#   on the anchor. That key holds this pass's LAST OBSERVATION of the anchor, and
#   takes exactly two shapes:
#
#     live      the anchor was observed NON-terminal. Written (idempotently) on
#               every live verdict — it both discards a previous episode's date and
#               is the record that this pass had eyes on the anchor before the
#               episode that follows.
#     <ISO ts>  the anchor was observed terminal, having been observed `live`
#               immediately before. THAT is what makes the timestamp a bound on the
#               transition rather than a guess: the marker was written between the
#               previous pass and this one.
#
#   A molecule materialized after a dated transition provably postdates the terminal
#   state — a rework by construction — and is left alone.
#
#   AN UNDATED EPISODE IS NOT EVIDENCE OF ANYTHING (tk-fotoi). The key is ABSENT
#   whenever this pass has never seen the anchor live: at rollout, after a witness
#   outage, on an anchor first met mid-episode, or when the stamp write is refused.
#   In that state the pass cannot tell a husk (molecule poured, then its own work
#   made the anchor terminal) from the sl-xhfl shape (anchor terminal for hours,
#   rework molecule poured against it) — BOTH have a molecule older than anything
#   we know, and both wear the zero-closed signature guard 2 reads. An earlier cut
#   of this guard stamped `now` on first sighting and swept in the same pass, on the
#   reasoning that "every molecule that already exists predates the stamp". It does
#   — and that is exactly why the stamp proves nothing about them. So for the
#   ambiguous reasons the undated path is NON-DESTRUCTIVE: the root is left alone
#   and counted `undated`. Only `closed` and `merged` — the two states no live
#   molecule wears at all — are swept without a dated transition.
#
#   Nothing is written on that path either. A date invented on first sighting is a
#   guess, and the next pass would read it back as evidence and sweep on it; leaving
#   the key absent keeps the pass honestly ignorant until it earns an observation.
#
#   AND THE STAMP IS READ BACK before it is trusted (tk-fotoi). `gc bd update` can
#   report success on a write that never lands, and a stamp that does not persist
#   turns every subsequent pass back into a first sighting — the failure mode above,
#   repeating forever under an anchor whose episode looks freshly dated each cycle.
#   So the transition write is re-read from the store, and a value that does not
#   come back is treated as the undated episode it actually is.
#
#   THE COST, stated plainly: an anchor that is already terminal when this pass
#   first meets it is never swept for an ambiguous reason. Its husk keeps burning
#   wisps until the anchor lands (`closed`/`merged`, swept unconditionally) or is
#   repooled (seen live, which arms the dating), and the witness's manual sweep is
#   the fallback in between. That is the rollout population, once. Every episode
#   that BEGINS under patrol coverage is dated from its own transition and swept
#   normally, one cycle later.
#
#   The residual window is one patrol cycle at the head of a dated episode — a
#   rework dispatched between the live observation and the terminal one is swept.
#   The pre-open gate makes that implausible in practice (a review round is many
#   minutes), and it is bounded by the patrol interval rather than by how long the
#   anchor has been parked.
#
#   GUARD 2 — THE MARKER ARRIVED MID-FLIGHT. Not every graph.v2 formula executes
#   inline. mol-scoped-work drives its steps ONE AT A TIME (each attempt bead is
#   dispatched, run, and CLOSED before the next is ready), and its anchor is
#   stamped at the submit step — while `cleanup-worktree` and `workflow-finalize`
#   still have to run. The anchor is terminal and the molecule is mid-flight, both
#   at once. De-routing there strands the root forever: the escape path is a CHAIN,
#   and protecting only its last link does not save it (signal-loom sl-jnjd, whose
#   `cleanup-worktree.attempt.1` sl-wmf1 was left unrouted and never claimed).
#
#   So the molecule's own evidence gates the ambiguous states: a graph that has
#   CLOSED a step is being driven step by step and its open steps are pending work,
#   not husks. This is the same discrimination detect-stalled-workflows.sh makes
#   from the other side (tk-xesf6): `closed` and `merge_result=merged` are the only
#   two anchor states no live molecule wears, and every other state this pass calls
#   terminal is one a live molecule can be wearing right now. Those two stay
#   unconditional here; the rest require the husk signature — zero closed steps,
#   which is what mol-polecat-work produces by construction and what the pass was
#   built for.
#
# Both guards fail CLOSED: an unreadable stamp, an unparseable timestamp, a stamp
# that will not persist, an episode we never saw begin, or an unreadable closed-step
# listing all leave the root alone, exactly like an unresolved anchor.
#
# THE ONE UNRESOLVED SHAPE WE ACT ON: A DELETED ROOT (tk-7g37t). Anchor resolution
# runs through the ROOT bead (root -> gc.input_convoy_id -> the convoy's single
# member). If the root ROW IS GONE from the store, that read yields nothing, the
# anchor is empty, and the fail-closed skip below fires — forever. Nothing else
# retires those steps either: gc-helm.sh's quiesce_release_molecule_steps()
# resolves the anchor exactly the same way, and core.control-dispatcher cannot
# finalize a graph whose root it cannot read. So the husk keeps its route +
# assignee + gc.session_affinity, `gc hook --claim` re-offers it every cycle, and
# each restart burns a fresh full-context polecat that re-derives "already done"
# and drains. Observed on root tk-wea42 (six surviving steps), which `--dry-run`
# reported as `anchor unresolved (convoy 'none'); skipped` in the same pass that
# quiesced tk-dg1oa — a DUPLICATE dispatch over the very same anchor. The only
# difference between the two was that one root row still existed.
#
# WHY THIS IS NOT A HOLE IN THE FAIL-CLOSED RULE. That rule protects against one
# thing: quiescing a LIVE molecule strips the assignee off steps a running polecat
# still has to claim. That hazard needs a molecule that can still RUN. A molecule
# whose root row is absent cannot be finalized by anything — the dispatcher closes
# the finalize step AND the root, and there is no root — so its steps are dead by
# construction. Absent-root is the one unresolved shape where quiescing is
# strictly safer than skipping. It is emphatically NOT the same as an unresolvable
# convoy on a root that DOES exist (a shape we genuinely do not understand): that
# one still skips.
#
# AND IT LICENSES --force, by a different route than the terminal-anchor gate. A
# root is never deleted by the machinery — finalize CLOSES it, leaving the row in
# place — so an absent root is the trace of a deliberate cleanup, and the claim it
# overrides can never reach a terminal state regardless of who holds it. The
# residual case, a root deleted out from under a still-running polecat, costs the
# step's assignee and nothing else: graph.v2 steps are executed INLINE in one
# session (the premise this whole script rests on), no step closes its own bead,
# and the polecat's hand-off — push the branch, stamp metadata, reassign — runs
# entirely off the ANCHOR bead. There is no step claim a running session depends
# on, so there is no work to strand.
#
# HOW "ABSENT" IS TOLD APART FROM "THE READ FAILED" — the distinction the arm
# lives or dies by, since treating an outage as absence is a way to quiesce LIVE
# molecules wholesale. `gc bd show <id> --json` answers the two cases differently:
#
#   absent bead    exit 1, and stdout carries a JSON envelope
#                  {"error": "no issues found matching the provided IDs", …}
#   failed read    exit 1, and stdout is EMPTY — no envelope at all (verified by
#                  pointing --db at a nonexistent path)
#   live bead      exit 0, stdout is the usual JSON array
#
# So the arm keys on the envelope, not on a non-zero exit and not on empty output.
# The message is matched EXACTLY. That is deliberately brittle in the safe
# direction: if beads ever rewords it, the match stops firing and the root falls
# through to the fail-closed skip — i.e. back to the pre-fix behavior, a noisy
# husk, never a wrongly-quiesced live molecule.
#
# One more thing makes the verdict trustworthy: we only reach it because
# `gc bd list` returned live step beads from THIS SAME store moments earlier. A
# misconfigured BEADS_DIR (the case where every id would read as absent) exits at
# the top with "no open work beads" and never reaches a root read at all.
#
# NOT set -e: best-effort, must never abort the witness patrol mid-pass. Any tool
# error skips that root and retries next patrol cycle.
#
# But the pass EXITS NON-ZERO when any step update failed (tk-z27pw). Every root
# is still attempted first — the exit code is a verdict on the whole pass, not an
# abort. A blanket exit 0 over failed writes is what hid this bug for a day: the
# script printed "-> cleared" for three steps, then "0 steps quiesced", and still
# reported success. The patrol's call site already treats a non-zero exit as
# non-fatal ("pass failed (non-fatal); retries next cycle"), so telling the truth
# costs the patrol nothing.
set -uo pipefail

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) shift ;;
  esac
done

# Anchor states that mean "the workflow's inline execution is DONE".
#
#   pre_open_gate  polecat handed off; codex is reviewing the BRANCH, no PR yet
#   pull_request   PR open, parked in the merge gate awaiting human approval
#   merged         PR landed; the anchor closes on the refinery's reconcile pass
#
# `merged` and a CLOSED anchor (handled separately below) are strictly-later
# lifecycle states than `pull_request`: if the steps are dead at pull_request they
# are dead afterwards too. A closed anchor is the safest case of all — the work
# bead itself is finished.
#
# The three merge_result values above are all stamped BY THE REFINERY, which is a
# beat behind the polecat's own hand-off. That leaves a window those predicates
# miss (tk-yxlqb): between the polecat's done sequence (push, reassign the anchor
# to the refinery) and the refinery's first stamp, the anchor reads
#
#     status=open   merge_result=<absent>   assignee=<rig>/<prefix>refinery
#
# — which looks "still live" while the molecule is already dead, so the husk keeps
# burning polecats for the whole window. Observed on tk-2l13a: ~17 minutes, two
# sessions consumed re-deriving "already done". A periodic pass that happens to run
# mid-window leaves the husk armed until the next cycle, so the window is not
# self-healing. The assignee closes it exactly: an anchor handed to the refinery is
# by definition past polecat work, stamped or not.
#
# Matching is on the assignee's final dotted component, after dropping the optional
# `<rig>/` qualifier — the live shapes are `<rig>/gc-toolkit.refinery` and
# `<rig>/gastown.refinery`, and a bare `refinery` is the un-prefixed binding. The
# match is deliberately anchored rather than a loose `*refinery*` substring: a false
# positive here quiesces a LIVE molecule (see the fail-closed note below), so only
# an assignee that IS a refinery may satisfy it.
#
# AND A FOURTH SHAPE, the longest-lived of them all (tk-rlm94): an anchor PARKED
# FOR A HUMAN DECISION — a refinery hold, a duplicate disposition, an escalation.
# It reads
#
#     status=blocked   merge_result=<absent>   assignee=<empty>   gc.routed_to=human
#
# and all three predicates above miss it, each for its own reason:
#
#   - `blocked` is not `closed`;
#   - merge_result was NEVER stamped, because the refinery held the bead BEFORE
#     dispatching a review or opening a PR (deliberately: reviewing a branch that
#     cannot land burns a signoff round). The tk-yxlqb assignee fallback was built
#     for exactly this "the refinery has not stamped yet" case, but it covers only
#     the beat BEFORE the stamp, not a hold that never reaches one;
#   - the assignee is EMPTY, because parking to a human clears it — the `*.refinery`
#     match needs the refinery to still HOLD the bead, and a held bead has been
#     handed onward.
#
# So the husk stayed armed, and unlike the earlier gaps — windows measured in
# minutes — this one lasts as long as a human takes to decide. Observed on root
# tk-i3noh / anchor tk-8d9u9: the same dead load-context step (tk-vgxlu) was
# re-offered five times in ~40 minutes, one fresh full-context polecat per session
# restart, each re-deriving "already done, take no action".
#
# CONJOINED, never bare `blocked`. That conjunction is what keeps this fail-closed,
# and the script's own warning is why: a false positive strips the assignee off
# steps a running polecat still has to claim and drains it mid-implementation. Bare
# `blocked` is reachable TRANSIENTLY by a live session — the escalation path sets
# blocked before it drains — whereas `blocked` + routed-to-human is only ever
# written by a pass that has already routed the work OFF the pool. `human` is
# matched exactly, the one spelling every writer uses (reconcile-merged-prs.sh,
# check-set-heal.sh, mol-refinery-patrol.toml); an unrecognized variant simply
# leaves the husk armed, which is the cheap failure.
#
# AND A FIFTH SHAPE, an anchor RE-CLAIMED BY ANOTHER SESSION (tk-nv3qr). When the
# refinery REJECTS a branch it clears the handoff and re-pools the anchor, and the
# next polecat claims it as a bare bead — exactly like the REQUEST_CHANGES rework
# path in the header (:56-63), it never re-walks this molecule's step graph. The
# anchor then reads
#
#     status=in_progress   merge_result=<absent>   assignee=<another polecat session>
#
# which satisfies none of the four predicates above: not closed, never re-stamped,
# not a refinery, and not parked for a human. So the husk stays armed for as long as
# the new owner holds the bead — and for the next owner after that, if it is rejected
# too. Observed on root tk-gonyp: its own load-context step was handed back to session
# lx-x3bt four minutes after lx-o9k2 claimed the anchor out of the pool.
#
# This clause and the park clause above were written in parallel against the same
# function. PR#272 (tk-rlm94) landed first and took $4 for gc.routed_to; this one
# was written against $4/$5 for the session pair and renumbered to $5/$6 when it was
# rebased onto that. Both are live and they are semantically independent — a
# re-claimed anchor is not parked (it is in_progress under a session, not blocked
# and routed off the pool), and a parked one is held by nobody at all.
#
# Those steps are dead by construction: `gc.session_affinity=require` binds them to
# the molecule's original session, and the work they describe now belongs to another
# one. No holder can ever advance them.
#
# BOTH conjuncts below are what keep this fail-closed, and neither is optional:
#
#   - the assignee must EQUAL the anchor's recorded session, which proves that
#     session is the CURRENT holder. `gc.session_name` is stamped at claim time and
#     is not cleared on release, so a bare "recorded session != molecule session"
#     test would also fire on a leftover from an earlier claim while the molecule's
#     own polecat is still running — stripping the assignee off steps that polecat
#     has yet to claim and draining it mid-implementation, the precise hazard the
#     fail-closed note below is about.
#   - all three values must be non-empty, so an anchor held under an agent or pool
#     name rather than a session name (no `gc.session_name` to compare) is left
#     alone rather than guessed at.
#
# It also NAMES the shape it matched, in TERMINAL_REASON. The name is what decides
# whether guard 2 applies (`closed` and `merged` are the two states no live
# molecule wears; every other shape here is one a live molecule can be wearing
# right now), and it is what the log line reports, so a hand review of a quiesce
# verdict can see which clause fired without re-deriving it from the field dump.
TERMINAL_REASON=""

is_terminal_anchor() {
  TERMINAL_REASON=""
  case "$1" in                       # $1 = anchor status
    closed) TERMINAL_REASON=closed; return 0 ;;
  esac
  case "$2" in                       # $2 = anchor metadata.merge_result
    pre_open_gate|pull_request|merged) TERMINAL_REASON="$2"; return 0 ;;
  esac
  case "${3##*/}" in                 # $3 = anchor assignee, minus any <rig>/ prefix
    refinery|*.refinery) TERMINAL_REASON=refinery; return 0 ;;
  esac
  case "$4" in                       # $4 = anchor metadata["gc.routed_to"]
    human) [ "$1" = blocked ] && { TERMINAL_REASON=human; return 0; } ;;
  esac
  # $5 = anchor metadata.gc.session_name, $6 = this molecule's root gc.session_name
  if [ -n "$3" ] && [ -n "${5:-}" ] && [ -n "${6:-}" ] \
     && [ "$3" = "${5:-}" ] && [ "${5:-}" != "${6:-}" ]; then
    TERMINAL_REASON=reclaim
    return 0
  fi
  return 1
}

# The two anchor states that are unambiguous: the work this molecule existed to do
# is finished AND landed, and no live molecule wears either. Guard 2 exempts them —
# a step-driven molecule under a closed or merged anchor really is spent, and a
# husk can also ACQUIRE a closed step (somebody closes load-context by hand to stop
# the churn), so the closed-step signature alone would let those slip through.
# Every other shape is gated. See the header for why this is the same two-state
# line detect-stalled-workflows.sh draws.
is_unambiguous_reason() {
  case "$1" in
    closed|merged) return 0 ;;
  esac
  return 1
}

# Timestamps are compared as STRINGS, so both sides must first be reduced to the
# one shape that makes that valid: `YYYY-MM-DDTHH:MM:SS`, UTC, no fraction. bd
# emits `2026-08-11T19:16:41Z` and `date -u` is told to match it, but a fractional
# second from either side would sort BEFORE a whole one at the same instant ('.' <
# 'Z'), so the seconds field is where both are cut. Anything that does not match
# the shape returns 1 and the caller fails closed rather than comparing garbage.
normalize_ts() {
  case "${1:-}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*)
      printf '%s' "${1:0:19}" ;;
    *) return 1 ;;
  esac
}

# How many of this molecule's step beads have CLOSED — the husk signature guard 2
# reads (zero = inline execution, nothing ever closes; more = a graph being driven
# step by step). Same listing the sibling stall detector uses, keyed on the same
# metadata field, so the two passes agree on what "the graph moved" means.
#
# Echoes a count on success and NOTHING on failure, with a non-zero return: an
# unreadable listing must not be read as "closed nothing", which is precisely the
# husk verdict and would hand the pass a live molecule to strip.
molecule_closed_step_count() {
  local _out _n
  # Assigned on their own lines, never as `local _x=$(…)`: `local` reports ITS own
  # exit status and would swallow the failure of the command substitution.
  _out=$(gc bd list --status=closed --metadata-field "gc.root_bead_id=$1" \
    --limit=0 --json 2>/dev/null) || return 1
  [ -n "$_out" ] || return 1
  _n=$(printf '%s' "$_out" | jq -r 'if type == "array" then length else empty end' 2>/dev/null) || return 1
  [ -n "$_n" ] || return 1
  printf '%s' "$_n"
}

# Re-read guard 1's observation key straight from the store (tk-fotoi). `gc bd
# update` reporting success is not proof the value landed, and a stamp that did not
# land makes the NEXT pass a first sighting again — the undated episode, dressed up
# as a freshly dated one, every cycle. So the transition write is read back and only
# a value that comes back is allowed to license a sweep.
#
# Echoes whatever the store holds, and NOTHING when the read itself fails — which
# the caller must treat exactly like an absent stamp, since a read it could not make
# is not evidence that a write it could not verify succeeded.
anchor_stamp() {
  gc bd show "$1" --json 2>/dev/null \
    | jq -r --arg k "$STAMP_KEY" '.[0].metadata[$k] // ""' 2>/dev/null
}

# Did the store DEFINITIVELY answer "no such bead", as opposed to failing to
# answer at all? See the header for why the difference is the whole safety of the
# absent-root arm, and for the three observed response shapes.
#
# Every condition below is a fail-closed one — anything unrecognized returns 1 and
# the caller keeps skipping the root:
#   * a zero exit means the read SUCCEEDED, so whatever it returned, it is not an
#     absence verdict;
#   * empty stdout is the signature of a read that never got an answer (wedged
#     store, unreachable db), not of an answer meaning "not here";
#   * a payload that is not a JSON OBJECT is not an error envelope — a successful
#     read returns an array — and unparseable output fails the jq call itself;
#   * and the message must match exactly, so a DIFFERENT error carried in the same
#     envelope shape (a connection failure, a permission error) is never read as
#     absence.
root_row_absent() {
  # $1 = raw stdout of `gc bd show <id> --json`, $2 = its exit status
  local _err
  [ "${2:-0}" -ne 0 ] || return 1
  [ -n "${1:-}" ] || return 1
  # Assigned on its own line, never as `local _err=$(…)`: `local` would report ITS
  # own exit status and swallow a jq failure, turning unparseable output into a
  # silent empty string.
  _err=$(printf '%s' "$1" \
    | jq -r 'if type == "object" then (.error // "") else "" end' 2>/dev/null) || return 1
  [ "$_err" = "no issues found matching the provided IDs" ]
}

STEPS=$(gc bd list --status=open,in_progress --json --limit=0 2>/dev/null)
[ -n "$STEPS" ] && [ "$STEPS" != "[]" ] \
  || { echo "quiesce-completed-workflows: no open work beads"; exit 0; }

# One compact row per live graph.v2 step bead. Built into a variable (not piped
# into the loop) so the loop runs in THIS shell and the counters survive.
#
# SELECTED BY CONTRACT, NOT BY FORMULA NAME (tk-q5r65). This filter used to read
# `startswith("mol-polecat-work.")`, which made every OTHER graph.v2 formula
# invisible to the pass — dropped here, before any anchor verdict, so its husks
# appeared in neither list of the summary and re-offered their never-closed
# load-context step forever. That is the exact burn this script exists to stop,
# and the prefix meant it could not see it. Verified live on mol-scoped-work, a
# CORE pack formula: root tk-917ov's husk kept 28 live steps and consumed ~1
# fresh full-context polecat per session restart, sub-5-minute cadence, while
# `--dry-run` reported the root nowhere at all.
#
# The header's rationale is stated in CONTRACT terms — graph.v2 materializes step
# beads, the polecat executes them inline, no step closes its own bead, the chain
# leaves load-context open and routed — and every graph.v2 formula satisfies it
# identically. The prefix was an accident of which formula existed when the pass
# was written.
#
# WHAT KEEPS THIS SAFE is not the filter; it is the fail-closed anchor gate below
# (root -> gc.input_convoy_id -> the convoy's SINGLE tracked member -> readable
# status -> is_terminal_anchor). That gate already refuses everything it does not
# understand: no convoy, a convoy with any member count but one, an unreadable
# anchor, and a live anchor all skip the root untouched. Widening the row filter
# hands it more candidates to refuse; it removes no guard. A non-graph.v2 bead
# carries no `gc.step_ref` at all and is never a candidate in the first place, so
# the predicate below is the whole membership test.
#
# The root requirement is BELT-AND-BRACES, and deliberately so. It changes no
# behavior today: a step with no `gc.root_bead_id` is already excluded from ROOTS
# by that reduction's own `select(. != "")`, and the per-root row match below can
# never equal an empty root either. It is stated here so the row set means
# exactly one thing — "a graph.v2 step that could be anchor-verified" — rather
# than leaving that to be inferred from two downstream reductions. With the
# formula name no longer carrying the membership rule, this filter is where the
# rule should be legible.
ROWS=$(printf '%s' "$STEPS" | jq -c '
  .[]
  | select((.metadata["gc.step_ref"] // "") != "")
  | select((.metadata["gc.root_bead_id"] // "") != "")
  | {
      id,
      step:     (.metadata["gc.step_ref"] // ""),
      root:     (.metadata["gc.root_bead_id"] // ""),
      routed:   (.metadata["gc.routed_to"] // ""),
      assignee: (.assignee // "")
    }' 2>/dev/null)
[ -n "$ROWS" ] \
  || { echo "quiesce-completed-workflows: no live graph.v2 workflow steps"; exit 0; }

ROOTS=$(printf '%s\n' "$ROWS" | jq -r -s 'map(.root) | map(select(. != "")) | unique | .[]' 2>/dev/null)
[ -n "$ROOTS" ] \
  || { echo "quiesce-completed-workflows: no resolvable workflow roots"; exit 0; }

quiesced=0; roots_done=0; roots_live=0; already=0; unresolved=0; failed=0; orphaned=0
postdated=0; advanced=0; undated=0

# Guard 1's observation key (see header): the key on the ANCHOR recording this
# pass's LAST OBSERVATION of it — the `live` sentinel while it is non-terminal, and
# the instant of the transition once it goes terminal under our eyes. NOW_TS is the
# instant every stamp in this pass is dated with — one reading for the whole sweep,
# so two roots sharing an anchor cannot date it differently.
STAMP_KEY="quiesce.terminal_since"
SEEN_LIVE="live"
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
# An unusable clock disables the WRITE, never the comparison: stamps already on
# anchors stay authoritative and keep protecting the molecules they cover, while a
# new episode goes undated rather than being dated with an empty value — which
# round-trips, reads back as "never observed", and would re-stamp every cycle. An
# undated episode is the fail-closed state (see guard 1), so a broken clock costs
# husks left noisy, never a live molecule stripped.
normalize_ts "$NOW_TS" >/dev/null 2>&1 \
  || { echo "quiesce-completed-workflows: clock unusable ('${NOW_TS:-empty}'); terminal episodes cannot be dated this pass" >&2; NOW_TS=""; }

# The assignee half needs `bd ... --force`, which `gc bd` refuses (see header).
# Resolve the binary once, so a rig without `bd` on PATH says so plainly instead
# of surfacing as N opaque per-step failures.
BD_BIN=$(command -v bd 2>/dev/null || true)
[ -n "$BD_BIN" ] || echo "quiesce-completed-workflows: bd not on PATH; assigned-shape steps cannot be cleared (gc bd refuses --force)" >&2

# Batched per ROOT, deliberately: a rig with several husks is ~6 `gc bd update`
# calls per root, and sweeping every bead in one flat pass has blown a 2-minute
# tool timeout in practice. Per-root batching also keeps a partial pass coherent to
# read: one anchor verdict, then that root's step lines. It does NOT make a root
# atomic — a single step can land its route clear and still be refused the assignee
# clear, which counts as failed (not quiesced) so the next patrol resumes from
# whichever key is still set.
while IFS= read -r root; do
  [ -n "${root:-}" ] || continue

  # Resolve the anchor the way the formula itself does: root -> input convoy ->
  # its single tracked member. Both mol-polecat-base and mol-scoped-work require
  # exactly one member (each refuses to run otherwise), so anything else is a
  # shape we do not understand — and, with the row filter selecting by contract
  # rather than by formula name, this is also the gate that turns away a graph.v2
  # formula built on some other anchoring shape. Refusing it costs a husk that
  # stays noisy; guessing costs a live molecule drained mid-implementation.
  #
  # One read, two values: the convoy, and the session this molecule's steps are
  # bound to (`gc.session_affinity=require`). The session is what the re-claim
  # predicate compares the anchor's current holder against; an empty one simply
  # means the molecule was never claimed, and the predicate fails closed on it.
  # Clear the whole anchor-resolution scope up front. The absent-root arm below
  # skips that resolution entirely, so without this every one of these would still
  # hold the PREVIOUS root's values while the shared step loop runs. Nothing after
  # the branch reads them today; this is here so that stays true by construction
  # rather than by luck, since the failure it prevents — an orphan root logged
  # against some earlier root's anchor — would read as correct output.
  convoy=""; rsession=""; rcreated=""; anchor=""; adesc=""
  astatus=""; amerge=""; aassignee=""; arouted=""; asession=""; astamp=""
  reason=""; rcreated_n=""; astamp_n=""; closed_steps=""; episode_ts=""

  # Capture the root read RAW, rather than piping it straight into jq: the absent-
  # root verdict needs the exit status and the error envelope, and a pipeline
  # discards the first and jq turns the second into an empty string
  # indistinguishable from a failed read.
  rootjson=$(gc bd show "$root" --json 2>/dev/null); rootshow_rc=$?

  # THE ROOT ROW IS GONE (tk-7g37t). Not an anchor we failed to resolve — a
  # molecule that provably cannot be finalized by anything, because finalization
  # runs through a root that no longer exists. Dead by construction, so quiescing
  # is safe where guessing at any other unresolved shape is not. See the header for
  # the full argument, for why this is the second gate on --force, and for how an
  # absence verdict is told apart from a failed read.
  if root_row_absent "$rootjson" "$rootshow_rc"; then
    echo "quiesce-completed-workflows: root $root — ROOT ROW ABSENT from store; molecule can never finalize; quiescing steps"
    orphaned=$((orphaned + 1))
  else
    # `created_at` rides along with the other two (tk-8m8d4): it is when this
    # molecule was MATERIALIZED, and guard 1 compares it against the anchor's
    # observation stamp. Reading it from the same call keeps the three values one
    # observation of one bead rather than three that might disagree.
    rootinfo=$(printf '%s' "$rootjson" \
      | jq -r '.[0] | "\(.metadata["gc.input_convoy_id"] // "")|\(.metadata["gc.session_name"] // "")|\(.created_at // "")"' 2>/dev/null)
    convoy=""; rsession=""; rcreated=""
    IFS='|' read -r convoy rsession rcreated <<< "$rootinfo"
    anchor=""
    [ -n "$convoy" ] && anchor=$(gc convoy status "$convoy" --json 2>/dev/null \
      | jq -r 'if ((.children // []) | length) == 1 then (.children[0].id // empty) else empty end' 2>/dev/null)

    # FAIL CLOSED on an unresolved anchor. Quiescing a LIVE molecule would strip the
    # assignee off the steps a running polecat still has to claim, draining it
    # mid-implementation and stranding real work. An un-quiesced husk only wastes
    # wisps — the cheaper failure by far, and the witness still catches it by hand.
    # The root that is merely ABSENT was handled above; everything still reaching
    # here is a root the store CAN read, whose anchor we could not resolve — a
    # shape we do not understand, and still the cheap skip.
    if [ -z "$anchor" ]; then
      echo "quiesce-completed-workflows: root $root — anchor unresolved (convoy '${convoy:-none}'); skipped" >&2
      unresolved=$((unresolved + 1)); continue
    fi

    # ONE read, six fields. `gc.routed_to` rides along in the same call the first
    # three already come from (tk-rlm94), `gc.session_name` alongside it (tk-nv3qr),
    # and guard 1's `quiesce.terminal_since` stamp with them (tk-8m8d4) — the park
    # predicate needs the first, the re-claim predicate the second, the provenance
    # guard the third, and reading any of them separately would let the halves of
    # one verdict describe two different observations of the anchor.
    ainfo=$(gc bd show "$anchor" --json 2>/dev/null \
      | jq -r --arg k "$STAMP_KEY" '.[0] | "\(.status // "")|\(.metadata.merge_result // "")|\(.assignee // "")|\(.metadata["gc.routed_to"] // "")|\(.metadata["gc.session_name"] // "")|\(.metadata[$k] // "")"' 2>/dev/null)
    astatus=""; amerge=""; aassignee=""; arouted=""; asession=""; astamp=""
    IFS='|' read -r astatus amerge aassignee arouted asession astamp <<< "$ainfo"
    # Every real bead carries a status, so an empty one means the READ failed (bead
    # gone, jq error, Dolt hiccup) rather than "an anchor with no status". Fail
    # closed on it, same as an unresolved anchor.
    if [ -z "$astatus" ]; then
      echo "quiesce-completed-workflows: root $root — anchor $anchor unreadable; skipped" >&2
      unresolved=$((unresolved + 1)); continue
    fi

    # The session pair is appended only when it is actually recorded, so the log line
    # for the four older shapes is unchanged — but a re-claim verdict has to say WHICH
    # two sessions it compared, since that is the whole basis for the call and this
    # pass is meant to be reversible by hand.
    adesc="status=$astatus merge_result=${amerge:-none} assignee=${aassignee:-none} routed_to=${arouted:-none}"
    [ -z "$asession" ] || adesc="$adesc session=$asession"
    [ -z "$rsession" ] || adesc="$adesc molecule_session=$rsession"
    if ! is_terminal_anchor "$astatus" "$amerge" "$aassignee" "$arouted" "$asession" "$rsession"; then
      # A LIVE anchor does two things to guard 1's key, and ONE write of the `live`
      # sentinel does both (tk-8m8d4, tk-fotoi).
      #
      #   It ENDS any terminal episode we had dated. Leave the old date and the NEXT
      #   episode — a rework's PR, after a repool cleared merge_result — inherits the
      #   PREVIOUS one's date, which is a date before the rework molecule existed:
      #   guard 1 would then wave through exactly the molecule it exists to protect.
      #
      #   And it ARMS the next episode's dating. A timestamp only bounds a transition
      #   if we saw the anchor live on the near side of it; without this record the
      #   next terminal sighting is undatable and guard 1 has to fail closed. An
      #   earlier cut UNSET the key here, which discarded the stale date correctly
      #   and threw away the observation with it.
      #
      # Idempotent, so a long-lived anchor costs one write and not one per cycle:
      # written only when the stored value is something other than the sentinel.
      if [ "$astamp" != "$SEEN_LIVE" ] && [ "$DRY_RUN" -eq 0 ]; then
        gc bd update "$anchor" --set-metadata "$STAMP_KEY=$SEEN_LIVE" >/dev/null 2>&1 \
          || echo "quiesce-completed-workflows: anchor $anchor — $STAMP_KEY live mark failed; the next terminal episode will be undatable until a later pass records it" >&2
      fi
      echo "quiesce-completed-workflows: root $root — anchor $anchor still live ($adesc); left alone"
      roots_live=$((roots_live + 1)); continue
    fi
    reason="$TERMINAL_REASON"
    adesc="$adesc terminal=$reason"

    # GUARD 1 — is this molecule's terminal anchor a PREVIOUS round's (tk-8m8d4)?
    # Three shapes of the observation key, and only the middle one licenses a sweep
    # on an ambiguous reason. See the header for why an undated episode is not
    # evidence and why a first sighting must not date itself.
    if [ "$astamp" = "$SEEN_LIVE" ]; then
      # TRANSITION OBSERVED. The previous pass had this anchor live, so the marker
      # was written between then and now: `now` bounds it. Record the date for the
      # passes that follow — and READ IT BACK (tk-fotoi), because a write that
      # reports success and does not land turns every later pass into a first
      # sighting again, which is the undated episode wearing a fresh date.
      if [ "$DRY_RUN" -eq 1 ]; then
        # Nothing is written in dry-run, so nothing can be read back. Report the
        # verdict the real pass would reach at this observation rather than the
        # undated one its own no-op would produce — a dry run that described the
        # effect of dry-running is worth nothing to the operator reading it.
        episode_ts="$NOW_TS"
      elif [ -n "$NOW_TS" ] \
           && gc bd update "$anchor" --set-metadata "$STAMP_KEY=$NOW_TS" >/dev/null 2>&1 \
           && [ "$(anchor_stamp "$anchor")" = "$NOW_TS" ]; then
        episode_ts="$NOW_TS"
      else
        echo "quiesce-completed-workflows: anchor $anchor — $STAMP_KEY transition stamp did not persist; this episode stays undated" >&2
      fi
    elif [ -n "$astamp" ]; then
      # DATED EPISODE, from a transition an earlier pass watched happen.
      rcreated_n=$(normalize_ts "$rcreated") || rcreated_n=""
      astamp_n=$(normalize_ts "$astamp") || astamp_n=""
      if [ -z "$rcreated_n" ] || [ -z "$astamp_n" ]; then
        echo "quiesce-completed-workflows: root $root — cannot date the molecule against the anchor (root created_at '${rcreated:-none}', $STAMP_KEY '${astamp:-none}'); skipped" >&2
        unresolved=$((unresolved + 1)); continue
      fi
      if [ "$rcreated_n" \> "$astamp_n" ]; then
        echo "quiesce-completed-workflows: root $root — anchor $anchor was ALREADY terminal at $astamp_n when this molecule was materialized at $rcreated_n ($adesc); its terminal state belongs to a PREVIOUS round, not this molecule; left alone"
        postdated=$((postdated + 1)); continue
      fi
      episode_ts="$astamp_n"
    fi

    # UNDATED EPISODE — never seen live, or the transition stamp would not persist.
    # We cannot say whether the marker predates this molecule, and for the ambiguous
    # reasons the two possibilities are a spent husk and a live rework wearing the
    # identical signature (sl-xhfl). Nothing is written: a date invented here is a
    # guess the next pass would read back as evidence. `closed` and `merged` are the
    # two states no live molecule wears at all, so they still sweep undated.
    if [ -z "$episode_ts" ] && ! is_unambiguous_reason "$reason"; then
      echo "quiesce-completed-workflows: root $root — anchor $anchor reads $reason, but this pass has no dated transition for it (${STAMP_KEY} '${astamp:-unset}'), so its terminal state cannot be placed before or after this molecule ($adesc); left alone"
      undated=$((undated + 1)); continue
    fi

    # GUARD 2 — did the marker arrive while this molecule was still mid-flight
    # (tk-8m8d4)? Only `closed` and `merged` are unambiguous; every other shape is
    # one a live molecule can be wearing, and a graph that has CLOSED a step is
    # being driven step by step rather than executed inline, so its open steps are
    # pending work. mol-polecat-work closes none, ever, so the pass's own population
    # is untouched by this.
    if ! is_unambiguous_reason "$reason"; then
      closed_steps=$(molecule_closed_step_count "$root") || closed_steps=""
      if [ -z "$closed_steps" ]; then
        echo "quiesce-completed-workflows: root $root — closed-step listing unreadable; skipped (an unread listing must not pass for the zero-closed husk signature)" >&2
        unresolved=$((unresolved + 1)); continue
      fi
      if [ "$closed_steps" -gt 0 ]; then
        echo "quiesce-completed-workflows: root $root — anchor $anchor reads $reason, but this molecule has closed $closed_steps step(s), so it is being driven step by step and its open steps are still pending work; left alone"
        advanced=$((advanced + 1)); continue
      fi
    fi

    echo "quiesce-completed-workflows: root $root — anchor $anchor DONE ($adesc); quiescing steps"
    roots_done=$((roots_done + 1))
  fi

  while IFS= read -r row; do
    [ -n "${row:-}" ] || continue
    sid=$(printf '%s'   "$row" | jq -r '.id // empty')
    step=$(printf '%s'  "$row" | jq -r '.step // empty')
    routed=$(printf '%s' "$row" | jq -r '.routed // empty')
    who=$(printf '%s'   "$row" | jq -r '.assignee // empty')
    [ -n "$sid" ] || continue

    # NEVER touch the finalize step: it is routed to the control dispatcher, which
    # is the machinery that actually closes the graph out. De-routing it would
    # remove the molecule's only escape path. Guarded twice — by step id and by
    # route — because losing this one is unrecoverable without a hand repair.
    case "$step" in *.workflow-finalize) continue ;; esac
    case "$routed" in *control-dispatcher*) continue ;; esac

    # Idempotent: nothing left to clear means a previous pass (or the witness by
    # hand) already quiesced this step.
    if [ -z "$routed" ] && [ -z "$who" ]; then
      already=$((already + 1)); continue
    fi

    # Snapshot the prior values into the patrol log — this action is meant to be
    # reversible by hand, so the log has to say what was there. It says "clearing",
    # not "cleared": the writes below can still be refused, and a line that claims
    # the past tense before the fact is half of what made this pass lie.
    echo "  $sid ($step): routed='${routed:-none}' assignee='${who:-none}' -> clearing"
    if [ "$DRY_RUN" -eq 1 ]; then
      quiesced=$((quiesced + 1)); continue
    fi

    # TWO calls, route first — see the header on order, on --force, and on why a
    # single batched update cannot work. Only the keys actually present are
    # touched, so sibling metadata stays intact and status is never rewritten.
    # Each half is tracked separately: a step whose route cleared but whose
    # assignee did not is a PARTIAL clear, and counts as a failure, not a success.
    step_ok=1
    route_ok=1

    # Pool channel. No claim is involved, so this half needs no --force — but it
    # can still be refused by the store (a wedged write, a transient error), and
    # the half below is gated on whether it landed.
    if [ -n "$routed" ]; then
      if ! gc bd update "$sid" --unset-metadata gc.routed_to >/dev/null 2>&1; then
        echo "quiesce-completed-workflows: $sid route clear failed; retries next patrol" >&2
        step_ok=0; route_ok=0
      fi
    fi

    # Affine hand-back channel. Needs --force past the claim guard, hence bare bd.
    # GATED ON THE ROUTE CLEAR (tk-d553m): route-first is only a safety barrier
    # while the assignee clear cannot outlive a route that survived. Clear the
    # assignee on a step whose gc.routed_to is still set and the result is open +
    # unassigned + routed — the pool-offer shape the ordering exists to prevent,
    # and now a durable state rather than a momentary window. So a refused route
    # clear skips this half entirely: the step is left exactly as it was, already
    # counted failed above, and the next patrol retries both keys from a shape it
    # understands.
    if [ -n "$who" ] && [ "$route_ok" -eq 1 ]; then
      if [ -z "$BD_BIN" ] \
         || ! "$BD_BIN" update "$sid" --assignee "" --force >/dev/null 2>&1; then
        echo "quiesce-completed-workflows: $sid assignee clear failed; retries next patrol" >&2
        step_ok=0
      fi
    elif [ -n "$who" ]; then
      echo "quiesce-completed-workflows: $sid assignee clear skipped (route clear failed; clearing it now would leave the step open+unassigned+routed); retries next patrol" >&2
    fi

    if [ "$step_ok" -eq 1 ]; then
      quiesced=$((quiesced + 1))
    else
      failed=$((failed + 1))
    fi
  done <<< "$(printf '%s\n' "$ROWS" | jq -c --arg r "$root" 'select(.root == $r)' 2>/dev/null)"
done <<< "$ROOTS"

MODE=""
[ "$DRY_RUN" -eq 1 ] && MODE="(dry-run) "
# `orphaned` is reported separately from `roots_done` rather than folded into it:
# a root-deleted molecule was never a normal completion, and a summary that said so
# would hide the one shape an operator may want to go look at.
#
# The guard slots are likewise their own (tk-8m8d4, tk-fotoi), and not folded into
# `still live`: a molecule held back by guard 1 or 2 sits under an anchor this pass
# DID read as terminal, so counting it as a live anchor would describe the opposite
# of what happened and hide the only lines that say a terminal verdict was
# overruled. `undated` is split from `postdating` for the same reason one step in:
# postdating is a verdict this pass REACHED about the ordering, undated is the
# absence of one, and an operator watching a rollout drain needs to see which of the
# two is holding a husk back.
echo "quiesce-completed-workflows: ${MODE}${quiesced} steps quiesced across $roots_done completed and $orphaned orphaned (root-deleted) workflow(s); $roots_live still live, $postdated postdating the anchor's terminal state, $undated under an undated terminal episode, $advanced still advancing, $already already quiet, $unresolved unresolved, $failed failed"

# Failed WRITES make the pass dishonest if swallowed; an unresolved anchor does
# not — that one is a deliberate fail-closed skip, already reported, and correct.
# So only $failed decides the exit code.
[ "$failed" -eq 0 ] || exit 1
exit 0
