---
name: Design — a first reaction is a run slung on its subject, and each exit a native write
description: The design for tk-1tfzr71.105, the design child of initiative tk-1tfzr71.17, taken at main 653da3c4f and checked against Gas City upstream main 297772b4c3, the city's gc build 6589a7df45 and bd 1.3.4. It states how a first reaction starts and why not through the work query, what records that a subject has had one, each exit's native writes with the code each retires, what the replacement keeps from the subject's notes and its answer to each held bug, what changes in cost and cadence, how every rig cuts over, and the units and cut-over beads the implementation child files. Read it to approve the design at its gate, or to build one of its units.
---

# Design: a first reaction is a run slung on its subject

This is the design record for tk-1tfzr71.105, the design child of the
initiative tk-1tfzr71.17. The pack was read at main 653da3c4f, the commit
`integration/tk-1tfzr71.17` was cut from, and every line number is at that
commit. Each Gas City fact is cited by symbol at upstream main 297772b4c3
(2026-11-14), and every symbol cited is also in the city's gc build,
6589a7df45; section 9 names the files that are byte-identical at both. The
store counts were read on 2026-11-14 between 09:00Z and 10:00Z.

## What the operator approves

Today a new bead gets its first reaction from a reaction bead that the pack
files beside it and routes to the proactive pool by writing the route itself.
The worker that claims the reaction bead reads the subject, writes its card,
takes one of five exits through `first-reaction-dispose.sh`, stamps
`gc.reacted_by` on the subject and closes the reaction bead. Approving this
design makes a first reaction a run of a new formula, `mol-first-reaction`,
slung on the subject itself. The run's step is the leased unit of work, so the
reaction bead, its keys and the pool's own work query retire, and so does the
per-sweep sling cap. The five exits, the card and the cases that put a bead to
you do not change. The implementation child files the units of section 7 on the
integration branch, a cut-over bead for the mechanik that runs once the landing
merges, and the bead that removes the cut-over's one leftover clause.

These calls carry a cost either way:

1. **A reaction is a run slung on its subject, not a claim from the work
   query.** Gas City's claim takes only a candidate routed to the claiming pool
   (section 1), so a work query cannot hand a worker a subject nobody routed.
   Routing the subject itself to the pool would leave the worker holding a bare
   bead, which nothing native stops, the case call 4 of the approved dispatch
   design asks this member not to leave. A run gives the lease, Gas City's run cancel as the stop,
   `gc sling`'s refusal of a second live reaction, and the retirement of a
   reaction whose subject closed before a worker took it. The cost: each
   reaction writes a root, a step, a finalize step and an input convoy where it
   wrote one bead and one edge, and the subject keeps that convoy's edge until
   it closes, as every poured bead does.
2. **The scan order stays, and slings the run.** Nothing in Gas City starts
   work on a bead nobody slung. An order can fire on `bead.created`, but its
   script is told no bead, so it would be this scan run on every create.
   Findings and your requests sling at once through the same verb, so its
   refusals hold on every path. The cost: each rig's scan still reads its ready
   set every 15 minutes. Slinging only where beads are filed would miss every
   bead filed by a plain create.
3. **No new record of a reaction.** While a reaction runs, the run is the
   record, and `gc sling` refuses a second. Afterwards the state the exit wrote
   keeps the subject out of the scan, and the headline every exit writes keeps
   it out once that state ends. You can still ask for another reaction on any
   bead. The cost: a bead whose wait ends with nothing dispatched keeps its
   headline and gets no second reaction unless someone asks. A label on every
   reacted bead would be a pack state that needs a warrant.
4. **The per-sweep cap goes, and the linking waits for its own build.** The cap
   delays reactions and saves none, because the pool runs two at a time and a
   slung run waits for a slot at no cost. A sweep still stops before its order's
   timeout and leaves the rest to the next one (section 1). You ruled on
   2026-09-20 that it goes
   (gate tk-b8fylm, recorded on tk-georjc). The linking you ruled the same day,
   to the epic, to similar beads and to likely duplicates, adds reads and
   writes to every reaction, and your direction of 2026-10-14, recorded there
   too, asks for its how to be redone at build time, so tk-georjc's validating
   closer asks you about it once this lands. The cost of the cap's
   end: lifting the city's override in the one other rig whose scan is off
   reacts to its 71 waiting beads, about $128 at the measured rate.
5. **One rig first.** When the landing merges, the mechanik pauses the scan in
   three of the four rigs where it runs, so the new path's scan runs in one
   pilot rig alone, the one of the four with the most reactions in the week
   measured (section 5). Once the pilot's first ten reactions on the new path are
   checked against its last ten on the old one, the pause lifts. Requests and
   findings take the new path in every rig at once. The cost: at most about 20
   beads a week across the three paused rigs, their whole reaction count since
   2026-11-07, wait for a reaction until the pause lifts. Cutting every rig over
   at once drops the pause and leaves a revert of the landing as the fallback.

Approving the design as it stands ships the first option of each. Section 4
answers each held bug and each constraint in the subject's notes.

## 1. How a first reaction starts

### The run

`gc sling <rig>/gc-toolkit.proactive <S>` pours `mol-first-reaction` over the
subject S. The proactive agent's `agent.toml` sets
`default_sling_formula = "mol-first-reaction"`, and Gas City applies an agent's
default sling formula as `--on` unless `--no-formula` is given
([config reference](https://github.com/gastownhall/gascity/blob/main/docs/reference/config.md),
the Agent table). So a bare sling to the pool pours the reaction, and a sling or
arm aimed at the pool can no longer pour `mol-polecat-work` there, which the
town's `[agent_defaults]` gives every agent today.

The verb itself names the formula with `--on`. When only the target's default
supplies the formula and a live classic molecule holds the bead, Gas City skips
the pour, routes the bare bead to the pool and exits 0, where an explicit `--on`
refuses (attachFormulaToBead, `internal/sling/sling_core.go`). A person's bare
sling of the pool can still take that path, so a worker whose claim is the bare
subject rather than a step hands it back unrouted and stands down.

The formula has one work step, `react`, routed to the pool at the pour. Gas
City's default work query offers a routed, unassigned, ready step, so the pool's
own `work_query` and `scale_check` (`agents/proactive/agent.toml:28-58`) go, and
so does their mirror in `tools/gc-proactive.sh`. A worker claims the step
through `gc hook --claim`, reads S as the run's input convoy's one member, runs
the check in section 2, writes its card, takes one exit, closes its step with
`claim-close.sh` and drains. The control dispatcher finalizes the run.

What the run gives that a hand-routed bead does not:

- **The lease.** The hook claims the step with its compare-and-swap, as it
  claims every step, and core's `orphan-sweep` order returns a dead holder's
  claim to the pool, so a worker that dies mid-reaction leaves the step for the
  next.
- **The stop.** Gas City's run cancel
  (`POST /v0/city/{cityName}/runs/{run_id}/cancel`,
  `internal/api/huma_handlers_runs.go`) closes a run's open steps and
  interrupts their holder. A person's takeaway release on S ends the run
  beneath it this way (`gc-helm.sh:1306-1308`), and a reaction that stands down
  ends its own run through `decline.sh`.
- **One live reaction per subject.** A sling of a formula whose root on the
  same bead is still live fails with exit 3 (checkLegacySourceWorkflowConflict,
  `internal/sling/sling_core.go`; liveConvoyTrackedWorkflowRoots,
  `internal/sling/sling_attachment.go`), and two slings at once serialize on a
  per-bead launch lock (withGraphV2SourceWorkflowLock). A run of another formula
  is not refused: "distinct formulas targeting the same bead are legitimate
  concurrent work".
- **No reaction to a closed subject.** The pour refuses a target whose status is
  terminal (CreateSingleItemInputConvoy, `internal/graphv2/invocation.go`). A
  run whose input closed after the pour, or was handed to an assignee outside
  the run, is retired when a worker would claim its step: the root and its open
  steps close as skipped (retireDoneWorkflowCandidates and
  hookRetireIfInputSettled, `cmd/gc/cmd_hook_claim.go`).
- **Priority.** The pour copies the subject's priority, and the pool claims in
  bd's priority order
  ([life of a bead](https://github.com/gastownhall/gascity/blob/main/engdocs/architecture/life-of-a-bead.md),
  the pool-demand tier), which the pool's board-ranked query approximates today.

Why not the work query. A `work_query` is run verbatim to find candidates, but
`gc hook --claim` claims a candidate only when its `gc.routed_to` names one of
the session's route targets (hookCandidateClaimable and hookClaimMatchesRoute,
`cmd/gc/cmd_hook_claim.go`). A query that selects subjects with no reaction
would offer beads that no claim can take. Making them claimable means routing
each one to the pool, and the worker would then claim and hold S itself. S
would read as routed pool work for the whole reaction, every exit would first
release the worker's own claim, and a person who rules on S meanwhile could not
stop the worker, because Gas City stops the holders of a run and no holder of a
bare bead (specs/tk-1tfzr71.54/design.md, call 4 and tk-ks7yjzo).

While a reaction runs, its subject reads in flight to `gctk bead holds`, since
steering.md's third clause counts a live run that has passed load-context and
`mol-first-reaction` has no such step. `gc-helm.sh place` (`:2300-2308`) and
`doctor/check-po-queue-only` each take a live run as a dispatch. A held exit
writes `hold:mayor` seconds before its run ends, so in that window place would
lift the hold without a sling and the check could report the bead. Unit 1 makes
both readers pass over a run of `mol-first-reaction`, because a reaction
triages a bead and does no work on it.

### What starts it

Every path calls one verb, `tools/gc-proactive.sh sling <S>`. It applies the
refusals section 2 names, then runs
`gc sling <rig>/gc-toolkit.proactive <S> --on mol-first-reaction` and passes its
exit 3 through.

- **The scan order**, `orders/proactive-scan-sling.toml`, every 15 minutes in
  each rig whose override leaves it on. Its exec becomes
  `$PACK_DIR/tools/gc-proactive.sh scan --sling`, and the script that wrapped it,
  `assets/scripts/proactive-scan-sling.sh` with its test, goes, its
  `deliverable` gate moving into the scan. Gas City ends an exec order at its
  timeout by signalling the order's whole process group (shellExecRunner,
  `cmd/gc/order_dispatch.go`), which would cut short a pour in progress, and
  a sweep with no cap can outlast the order's 300 seconds. So the order's
  `[order.env]` gives the sweep that timeout, beside the order's own `timeout`,
  since an override can change both and cannot change the exec line, and the
  sweep starts no sling once less time is left than its slowest sling so far
  has taken. The beads it leaves wait for the next sweep. The order keeps its
  name, so the city's overrides that switch it off in gc-toolkit and one other
  rig keep applying through the landing: Gas City reports an override that
  names no order as an error
  ([orders tutorial](https://github.com/gastownhall/gascity/blob/main/docs/tutorials/07-orders.md),
  "Overrides"), and a new order could not be shipped off by default and
  switched on per rig, because a definition's `enabled = false` drops the order
  before overrides apply (`internal/orders/scanner.go`).
- **A patrol finding**, at filing: `patrol-finding.sh` slings the bead it filed,
  as it does today.
- **A request**: `gc-helm.sh react` from the board or the operator, and
  `operator-intake.sh` through react.

No Gas City primitive covers the scan's job. An order fires on `bead.created`
(`internal/events/events.go`, BeadCreated), but an exec order's script is told
no event. Its environment names its order's directory, its pack, its store and
rig, and carries its `[order.env]`
([orders tutorial](https://github.com/gastownhall/gascity/blob/main/docs/tutorials/07-orders.md),
"Formula orders vs. exec orders"; `cmd/gc/order_store.go`), and an order that
fires on its own gets no arguments (`cmd/gc/order_dispatch.go`, "Auto-triggered
orders carry no args channel"). So it would scan to learn which bead was
filed, and in a city where every pour creates beads it would scan on nearly
every patrol pass. A formula order pours a formula with no subject. Core's
orders and formulas include none that triages a new bead
(`internal/bootstrap/packs/core`).

### The comment above `cmd_sling`, re-verified

`tools/gc-proactive.sh:1038-1044` says a reaction bead carries its own route,
"so the un-clearable-execution-route pain of pouring a workflow onto a bead
that is not that workflow's work never arises". Against the build the city
runs:

- The fork's 29f4f2137 (2026-10-16) is not an ancestor of 6589a7df45, since the
  fork was rebased onto upstream after it. Upstream's restampWorkBeadRouting
  (`internal/sling/sling_core.go`) does at the attach what that commit did: it
  clears `gc.routed_to` and `gc.run_target` on the bead and stamps
  `gc.execution_routed_to`.
- The stamp is cleared at the bead's next plain sling (clearGraphTakeoverRoute)
  and overwritten at its next pour. The takeaway release unsets it in its park
  (`gc-helm.sh:1725`), and every exit but the close goes through that release.
  The close exit's pour of the validating closer overwrites it, at once or when
  its arm starts. A reaction that declines leaves the stamp until the bead's
  next sling or pour.
- No queue reads the stamp (`assets/scripts/dispatch-path.sh:8-9`). Gas City's
  detached-orphan sweep reads it only to leave the bead alone
  (isDetachedHandoffOrphanCandidate, `cmd/gc/pool_detached_orphan_sweep.go`).
- `gc workflow delete-source` and `gc workflow reopen-source` find a bead's
  workflows by `gc.source_bead_id`, which the root of a graph.v2 run slung with
  `--on` never carries (the pour sets its source to none,
  `internal/sling/sling.go`; the lookup in
  `internal/sourceworkflow/sourceworkflow.go`), so neither sees a reaction's
  run. Delete-source clears only `workflow_id` and leaves the stamp.
  Reopen-source clears the stamp, but it reopens the bead and routes it to a
  pool (cmdWorkflowReopenSource, `cmd/gc/cmd_convoy_dispatch.go`), which a
  reaction must never do. The run ends by its own step's close, so it needs
  neither.

So the pain the comment names does not arise, and the comment goes with the
reaction bead's create.

## 2. What records that a subject has had its first reaction

The reaction bead was the record while a reaction ran, and `gc.reacted_by` was
the record after. No key or bead kind of the pack's replaces them:

- **While it runs**, the run is the record. The scan drops S, since its
  in-flight filter (scan_drop_inflight, through `run-lib.sh`) drops every bead a
  live run works, and the verb refuses S for the same run. Two slings in the
  same instant both pass those reads, and `gc sling` refuses the second, which
  closes the input convoy it minted. So two sweeps, a sweep and a finding, or
  two requests start one reaction.
- **Once it ends**, the state its exit wrote keeps S out of every candidate
  read: a route or a live run (actionable, close), an assignee (a named agent), a
  `blocks` edge or a human gate (blocked, recommend, ruling), and `hold:mayor`
  (held for placement). The scan reads only ready, unassigned beads with no
  dispatch path and no hold (scan_precision_filter).
- **Once that state ends with nothing dispatched**, the headline keeps S out.
  Every exit writes `gc.takeaway` through `gc-helm.sh takeaway`, and the scan
  already drops a bead that carries one (`tools/gc-proactive.sh:841-842`), as it
  drops a bead a sitting ruled on. The cases are a blocked bead nobody takes
  whose blocker lands, a gate answered with no dispatch, and a hold lifted with
  no placement. The close exit writes its headline before it dispatches the
  closer, so its headline no longer depends on a best-effort write after the
  sling (`first-reaction-dispose.sh:1066-1068`).
- **None is missed.** The scan reads every ready bead in its rig each sweep, with
  no cap and no page (section 5), so a bead nothing slung is slung by the next
  sweep with time left for it (section 1). A sling that fails before its pour
  leaves the bead a candidate for the next sweep, and a bead blocked when it is
  filed is read once its wait lifts.
- **A pour cut short.** A sling killed part way through its pour, or one whose
  failed pour Gas City could not clean up, leaves the reaction's root open as an
  unfinished pour: the root carries `molecule_failed=true`, or it or its step is
  still fenced by `gc.instantiating` (markFailed and fenceGraphWorkflowBead,
  `internal/molecule/molecule.go`). The fence holds the step's route back, and
  marking the pour failed does not restore it, so no worker is offered the
  step. Gas City's conflict check counts every root that is not closed, so each
  later sling on S exits 3 while the root stands. The verb's live-run read and
  the scan's in-flight filter therefore read an unfinished pour, as gctk's
  deferred-dispatch start defines one (pours, `services/gctk/arm/start.go`), as
  no run, so the next sweep reaches S. When the verb's
  sling then exits 3 on that root, the verb files a human gate on S that names
  the root and the remedy the start names, `gc convoy delete <root> --force`,
  and exits 5, as for any bead a gate holds. Clearing the gate returns S to the
  scan.
- **Asking again.** A request does not read the headline, so the operator or a
  patrol can ask for another reaction on any bead the refusals below allow.

The beads reacted to before the cut-over already carry a headline: every one of
the 143 open beads with `gc.reacted_by` or `gc.proactive_reaction=1`, across
the city's six stores, carries `gc.takeaway`. So the scan reads them as reacted
with no migration. Thirteen more are deferred upstream findings that carry no
headline. Neither the old scan nor the new one reads the reaction keys, so
either path reacts to them again once they reopen. On every bead reacted to
before the cut-over, the reaction keys stay as inert residue, registered as
retired in `lifecycle/lifecycle.toml`, the registry's default for a key whose
residue leaves nothing undone.

### The refusals, read at both ends

`gc-proactive.sh sling` refuses a subject and exits with a code its callers
branch on. It writes nothing on a refusal but the gate on an unfinished pour:

| Refusal | Read from | Exit |
|---|---|---|
| a live run of `mol-first-reaction` | `run-lib.sh`, and `gc sling`'s own conflict when two slings meet | 3 |
| an open conversation that tracks S, the live owner `gc.reaction_owned` marks today | S's `tracks` dependents, judged by `conversation.sh`'s shape | 3 |
| a live run of another formula | `run-lib.sh` | 4 |
| a route or an arm, `hold:mayor` or `hold:external`, an assignee, a status other than open | the row: its status and assignee, and `dispatch-path.sh` for the route, the arm and the hold | 5 |
| an open human gate | `gctk bead holds` | 5 |
| an unfinished pour of `mol-first-reaction`, named by `gc sling`'s exit 3 | the root's `molecule_failed` and `gc.instantiating` marks, read after the sling; the verb files the gate of section 2 first | 5 |
| a standing record, or a feedback pattern, which the distiller dispatches | `standing-kinds.sh`; `task_kind=feedback-pattern` | 6 |

`gc sling` itself refuses a bead no store holds (MissingBeadError,
`internal/sling/sling.go`), a pool that does not read the bead's store
(CrossStoreRouteError, validateBuiltInRouteStoreReachable in
`internal/sling/sling_core.go`) and a target the city does not configure
(`cmd/gc/cmd_sling.go`). The verb reports each as an error, which
`subject_present_guard` reports today.

The reaction reads the same refusals as its first act, through
`gc-proactive.sh sling <S> --check --run <root>`, which writes nothing. Its own
run is not counted, and neither is a first-reaction gate whose message names
that run, so a reaction re-offered after it filed its gate resumes rather than
stands down. Any refusal ends the reaction with `decline.sh --step
mol-first-reaction.react --reason "<the refusal>"`, which declines with no
gate: it cancels the run and drains. So the refusals hold on every path, a
person's bare `gc sling` of the pool included, with the one exception below,
and one definition answers both ends.

A route is the one refusal the reaction cannot read. The pour clears S's
`gc.routed_to` and `gc.run_target` (restampWorkBeadRouting, section 1), so a
route S carried when it was poured is gone before its reaction reads S. The verb
reads S just before it slings, so on its path only a route written in that gap
is lost this way. A person who slings a routed bead to the pool by hand takes it
off its route, as any pour onto a routed bead does.

## 3. Each exit as native writes

Each exit stays one call to `first-reaction-dispose.sh`, so every worker takes
the writes in the same order and none assembles them (foundation.md, test 3).
The writes are Gas City's and bd's; the script holds their order, the intake
rule, the emergency check and the forms a named agent takes work in.

| Exit | Native writes, in order | Code it retires | Stays as judgment in the prompt |
|---|---|---|---|
| every exit | the card, guarded `gc bd update S --if-status open --append-notes`; the step's close, `claim-close.sh` | the reaction bead: `--reaction-bead`, close_reaction (`:501-517`), the reaction bead's stand-down (`:519-546`) and re-offer guard (`:548-560`), stamp_landed and its calls (`:923-941`, `:1069-1070`, `:1209-1210`). The molecule-era path: the `gc.proactive_reaction` proof (`:561-571`) and `--after-workflow` (`:257-258`, `:346-354`, and its part of `:1028-1045`), since no run of the old molecule is open in any store | whether S is work, a wait, a no-op or a question |
| actionable, admitted to a pool | for a confirmed emergency, P0 and its note; `gc-helm.sh takeaway --release --route <rig>/<pool> --no-wait`, whose park is a compare-and-swap and whose route is `gc sling --no-formula --no-convoy` (tk-1tfzr71.61) | nothing beyond the first row; the `deliverable` probe stays (`:743-765`) | the pool, the emergency claim and the failing check it names, the headline and the reason |
| actionable, held for placement | `takeaway --release --no-wait`, then `gc bd set-state S hold=mayor --reason ...` and the intake note | the order of the two writes flips (`:1113-1148` writes the hold before the release), so the hold is the last write and a re-offered reaction finishes the exit | as above |
| actionable, to a named agent | `takeaway --release --assign` for the refinery or the keeper, or the release then `gc sling <rig>/<agent> S --no-formula --no-convoy` for the mechanik; `gc bd ready` read; `gc session nudge` when ready | nothing; hand_over (`:943-991`) and the `assignable` probe stay | which agent's own work it is |
| recommend | clear an earlier `gc.recommended_formula`; withdraw any open first-reaction gate whose brief is not this exit's; file or reuse the gate (`human-gate.sh`, which runs `gc bd gate create --type=human --blocks S --await-id first-reaction`); stamp `gc.recommended_formula`; `takeaway --release --waiting-on <gate>` | the title-only supersession test (`:1093-1098`) | the action, its formula, the caveat, the headline |
| ruling | the gate; `takeaway --release --waiting-on <gate>` | as recommend, for the gate | the fork, the irreversible act or the policy call |
| blocked | file a missing wait with `gc bd create`; `takeaway --release --waiting-on` each wait; `gctk bead holds S` must name no `foreign` edge; then `gctk bead arm S --target <pool>` when intake admits the bead and a pool takes it, or the named agent's form, or `hold:mayor` when intake holds it | the store check of `--waiting-on` (`:380-384`) and the `gc.blocker_key` dedup (`:846-860`), replaced by reusing a wait S already has, as `gctk bead holds` lists it | what S waits on, and who takes it once the wait lifts |
| close | append the close brief; write the headline; then `gc sling <rig>/<pool> S --on mol-validate-close`, or for `--waiting-on` a `blocks` edge onto each bead and `gctk bead arm S --target <pool> --on mol-validate-close` | the exit-3 reading keyed on a reaction bead (`:1052-1064`), now keyed on a live closer; the store check of `--waiting-on` (`:355-359`) | why there is no work, the counter-case, and the bead whose landing ends the job |

The checks that a wait lives in S's store go from the script, as the subject's
rule 1 note directs (census D27 of specs/tk-ssm8qns.2/blocked-census.md):
bd accepts an edge onto a bead its store does not hold and the edge holds
nothing, so the exit asks `gctk bead holds`, whose `foreign` field names such an
edge, and the arm refuses a bead that has one. No exit computes a wait.

What `tools/gc-proactive.sh` retires:

- `subject_present_guard` (`:170-200`), since `gc sling` refuses a bead no store
  holds and a pool that cannot read it;
- `reaction_absent_guard` (`:202-289`), since `gc sling` refuses a second live
  reaction, and a conversation's own edge marks a live owner;
- the reaction bead's create and its `tracks` edge (`:1110-1171`), with
  `REACTION_KIND` (`:46-48`) and `rig_store_ref` (`:162-168`);
- `cmd_demand`, `board_rank` and `exclude_graph_structural` (`:414-439`,
  `:702-739`), since the pool uses Gas City's default query;
- the per-sweep cap, `GC_PROACTIVE_SLING_CAP`, and the page a sweep slings from
  (`:39-44`, `:965-967`, `:1006-1009`, `:1031-1035`);
- the opt-in read of `gc.proactive=1` (`:908-922`), which reads a subset of the
  movable-forward read beside it, and `patrol-finding.sh`'s stamp of the key
  (`:560`);
- the precision filter's reaction-bead and `gc.reaction_owned` clauses (`:829`,
  `:838`).

It keeps the scan's precision filter otherwise, its in-flight filter, the
dispatch-path and live-workflow guards, `deliverable` and `assignable`. The
sweep counts a dispatch only when the verb slung, so a skip whose cause it does
not name no longer counts as one (`:1022`).

### A re-offered reaction

A worker can die between its exit's writes and its step's close, and the step
then comes back to the pool. The next worker runs the check before anything
else, and each exit orders its writes so that the check stands the worker down
only once the exit has dispatched S:

- An exit that dispatched S, held it or gated it leaves a refusal, and the
  worker declines. The one exception is the gate the run filed, which the check
  passes over so the recommend and ruling exits finish their writes.
- An exit cut off before its dispatching write, or a blocked exit that has
  written only its waits, leaves S a subject the check passes, since a wait on
  another bead is no refusal. The card names the run in its heading, so the
  worker finds the card it wrote, writes no second one and re-runs the same
  exit, whose writes repeat harmlessly: a gate under the same key and brief is
  reused, a `blocks` edge between the same pair is kept once, an arm already on
  the bead for the same target and formula writes nothing
  (`gctk bead arm --help`), a release compares and swaps on the status and
  assignee it read, and `gc sling` refuses a second live closer.

So no key on S proves that an exit landed. The release that once yanked a bead
a downstream worker had claimed is not re-run, because the claim is a refusal.

## 4. What the replacement keeps

- **A standing record takes no reaction on any path.** The verb refuses one with
  exit 6, reading the kinds from `assets/scripts/standing-kinds.sh`, and the
  reaction's check refuses one too, so a person's bare sling of the pool stands
  down at once. `gc-helm.sh react` re-raises exit 6 as its own exit 8, and
  `operator-intake.sh` answers 8 by filing the conversation directly, the
  starting design #1495 carried (tk-wdwjhzl's ruling). `standing-kinds.sh`'s
  list of its readers names the sling beside the scan.
- **Feedback patterns are the distiller's.** The scan selects no
  `task_kind=feedback-pattern` bead and the verb refuses one with exit 6, since
  the distiller decides every pattern `bd ready` lists (the note from
  tk-ltcv43q's submit).
- **The recommend exit keeps its order and its cases.** It clears an earlier
  recommendation before anything else, files or reuses the gate, and stamps
  `gc.recommended_formula` only after that, so no recommendation is older than
  the newest first-reaction gate, the order `gc-helm.sh accept` and the board's
  Accept read (readAcceptance, `services/helm/internal/board/human.go`; the
  note from tk-pchr4j2's validation). `first-reaction-dispose.test.sh` keeps
  its RECO and RECOORDER cases.
- **Waits are read, never computed.** The blocked exit and the check read
  `gctk bead holds`, and the verb's gate refusal moves from `HUMAN_GATE_JQ`
  over raw rows to the same read.
- **tk-qgocr1g, a newer recommendation keeping an older gate's brief.** The
  gate's message names the recommended formula and the run that filed it. The
  exit reuses an open first-reaction gate only when its whole brief, title and
  description, is this exit's. Any other open first-reaction gate is withdrawn before the new one is
  filed. A new case runs two recommends with one headline and two formulas, and
  checks that the one open gate names the second formula and so does
  `gc.recommended_formula`.
- **tk-i829bzv, a reaction to a closed subject.** Gas City refuses the pour on a
  closed subject and retires the run of a subject that closed before its step
  was claimed. The check refuses a status other than open, and the card's write
  is guarded on that status, so a close that lands while the worker reads S
  stops the reaction before any exit with nothing written. The exit reads the
  status again before its first write. Between that read and the write a close
  can still land; the release's compare-and-swap and `gc sling`'s refusal cover
  the writes they make, and no other write type takes a guard. New cases cover
  a subject closed before the check and one closed between the card and the
  exit.
- **tk-52oz0ts, the closer's notes.** The close exit keeps `mol-validate-close`
  as its closer, so unit 2 changes the two note blocks of its
  validate-and-resolve step (`formulas/mol-validate-close.toml:150` and
  `:165`) to pass the closer's text as printf's argument from a quoted heredoc,
  never inside its format. The unit runs each edited block once with a percent
  sign, an apostrophe, a dollar sign and a backtick in the text, and adds no
  block-extraction test (built-once-target.md, rule 2).

The subject's other notes:

- The topology comments the tk-1tfzr71.28 note asked to correct sit above the
  pool's `work_query` and in `exclude_graph_structural` and the fixture tool,
  all of which go, so nothing restates those facts.
- The order's description says a bead that needs a ruling "files a visit"
  (tk-u4uo3wb's note). Unit 1 rewrites it with the exec.
- A placement takes `hold:mayor` and no gate, as the native-hold design settled
  (tk-rl8gz4b.30's note). The exits keep that write and the refusal of the po's
  address that tk-rl8gz4b.32 built.
- No create carries a route, and the reaction is a poured run, as the dispatch
  design asks of this member (tk-1tfzr71.55's note). The actionable exit
  releases through the takeaway release that unit 2 of that effort rebuilt, and
  the recommend and ruling exits wait on a gate.
- `tools/proactive-first-reaction-fixture.sh` fails one assertion on main (the
  note from tk-ltcv43q's build). The fixture is not a suite, and every machine
  it checks is retired or covered by a suite, so unit 1 deletes it.

## 5. Cost and cadence

The cost basis is mechanik's measurement, quoted on tk-hok6w and in the subject's
notes: a first reaction is about 3.2M tokens and $1.80 at Gas City's list price
for Opus 5.5 (152 sessions, 21 days to 2026-10-31), and a batch sort about $0.17 a
bead (190 beads, 2026-10-30).

What the design changes:

- **A reaction costs what it cost.** The session's reading and judgment are the
  cost, and the run swaps one bead and one edge for a few more store writes,
  which cost no tokens.
- **Fewer reactions read a closed subject.** A subject closed before its sling
  gets no run, so no session starts for it. A run whose subject closed, or was
  handed to another assignee, before a worker took it is retired by the next
  claim that reaches its step, so no worker reads or judges that subject. A
  session can still start for that run, because Gas City's pool demand counts a
  ready, routed step without reading its input, and only a running worker's
  `gc hook --claim` retires the run (section 9). When no other step waits, that
  session retires the run in its claim and drains, so the run costs a session's
  start but none of a reaction's reading and judgment. Of the three cases
  tk-i829bzv records, each of which spent a session, one would start none,
  since its subject closed before its reaction was filed. One closed before a
  worker claimed its reaction, so a session could still start for it but would
  read nothing. The third closed while its worker read it, so it still spends a
  session, and the card's guarded write (section 4) stops that reaction with
  nothing written.
- **The cap goes, and the spend does not move.** The cap delays a reaction to a
  later sweep and prevents none, and two sessions a rig still run at once. The
  measured steady state is small: when this design read the stores, no bead
  waited for a reaction in the four rigs where the scan runs, and 6 waited in
  gc-toolkit and 71 in the one other rig where the city's overrides keep it
  off. The reactions of the 7.4 days to 2026-11-14 were 58, about $104: 24 in
  gc-toolkit from findings and requests, 13 in the pilot rig of section 6, 20 in
  the three rigs it pauses (9, 6 and 5), and 1 in the other rig the overrides
  keep off.
- **The cadence stays.** The order's 15-minute interval is unchanged, and so are
  the pool's model and its two sessions.

What the design leaves alone: the held queue. 493 open beads carry `hold:mayor`,
381 of them in gc-toolkit. The scan drops a held bead, so none takes a first
reaction. The po works the queue with you in its refinement sitting, in pieces,
which the native-hold design built on your words of 2026-10-31: "I feel like 187
being done one at a time is going to consume quite a bit of tokens", and "maybe
that's just a visit that I work through piece by piece". Whether gc-toolkit's
own scan comes back stays your call, as tk-hok6w records.

The linking is left to tk-georjc's validating closer, which finds the cap gone
and the linking absent once this lands and asks you about the rest. The card's
Found section already names related beads and likely duplicates. Writing
edges to them adds a discovery read to every reaction, the cost you asked to
explore lowering, and your 2026-10-14 note on tk-georjc asks for its how to be
redone at build time.

## 6. Rollout: how every rig cuts over

Every rig in this city imports the pack by path from the gc-toolkit rig's
checkout (`gc import list`), so every rig takes the new code at the checkout's
first sync after the landing merges (`orders/reconcile-rig-checkouts.toml`,
every 15 minutes). A rig differs only in whether its scan runs, which the
city's overrides decide. A city that imports the pack from git takes it at its
next pack update, and its overrides keep applying because the order keeps its
name.

The stores need no migration. When this design read them, no reaction bead was
open in any rig's store, and no run of the old `mol-first-reaction` molecule was
open: gc-toolkit holds 700 roots of it and four other stores 305 between them,
all closed. The residue of the old keys is inert (section 2).

One window remains. Until the checkout syncs, the old code still files reaction
beads, and a session that claimed one under the old prompt calls scripts that
change at the sync, so its dispose fails on the flag the new script dropped and
leaves the bead open until that session ends. The pool's new query offers such a
bead to a worker running the new prompt. So the new prompt carries one clause
for a claim that is a reaction bead (`task_kind=reaction`): close it as a no-op,
and re-sling its subject through `gc-proactive.sh sling` unless the subject
carries that bead's `gc.reacted_by`, which says its exit landed. The clause is a
compatibility path. Only beads the old code filed reach it, and at the week's
rate of 58 reactions in 7.4 days a 15-minute window holds about 0.08 of one, so a
leftover bead is unlikely but possible. The cut-over bead below confirms none is
left before a polecat removes the clause.

- **C, the cut-over, once the landing merges.** The mechanik adds overrides that
  switch the scan off in the three rigs call 5 pauses, beside the city's two
  overrides that keep it off today. The cut-over bead names the rigs. Until the
  mechanik adds them, those rigs' scans may run once on the new path, which is
  the same path the pilot runs. Once the checkout has synced and
  no session that started before the sync still runs in a proactive pool, it
  checks that no reaction bead is open in any store, and treats any it finds as
  the clause does. Once the pilot's first ten reactions on the new path have
  landed, it reads each one: the run's step closed after its exit, the exit's
  writes present (the route or run, the gate or hold, and `gctk bead holds` for
  a wait), no subject reacted to twice, and nothing written to a closed one. It
  compares the mix of exits with the pilot's last ten on the old path, which
  the subjects' cards record, and writes both on its notes. If the reads hold,
  it removes the overrides it added. If one does not, it files a human gate that
  names what failed, and the remedy is to revert the landing's squash commit,
  which restores the old path at the next sync.
- **The clause's removal, after C.** A polecat removes the prompt's clause for a
  reaction bead, since C found none left and no code files one.

## 7. The units

Each unit lands on `integration/tk-1tfzr71.17`, keeps the suite green and leaves
the city working.

| Unit | What it does | Waits on | Answers |
|---|---|---|---|
| 1. The scan and every request sling a run | `formulas/mol-first-reaction.toml`; `agents/proactive/agent.toml` (Gas City's default query, `default_sling_formula`, the nudge); `tools/gc-proactive.sh` (`sling` through `gc sling` with the refusals and `--check --run`, an unfinished pour read as no run and gated when `gc sling` exits 3 on it, the scan with no cap, no page and no opt-in read, ending before the order's timeout, the retirements in section 3); the order's exec, its `[order.env]` deadline and its description; `proactive-scan-sling.sh` and its test deleted; `patrol-finding.sh` without `gc.proactive`; `gc-helm.sh` react's exit 8, `create_subject` without `gc.reaction_owned`, and place passing over a reaction's run; `operator-intake.sh`'s exit 8; `doctor/check-po-queue-only` passing over a reaction's run; `tools/proactive-first-reaction-fixture.sh` deleted; the suites of each | nothing | call 1, call 2, call 4's cap, the standing record and pattern refusals, the sling side of tk-i829bzv |
| 2. The reaction runs in the step and disposes through native writes | `agents/proactive/prompt.template.md` (claim the step, read S, the check, a card that names its run, the exit, the step's close, the decline, the hand-back of a claim that is the bare subject, and the cut-over's clause for a reaction bead) and `PROVENANCE.md`; `first-reaction-dispose.sh` with the retirements and write orders of section 3; `formulas/mol-validate-close.toml`'s two note blocks; `first-reaction-dispose.test.sh`, with the RECO and RECOORDER cases kept and the new cases of section 4 | unit 1 | call 3's exit side, tk-qgocr1g, tk-i829bzv, tk-52oz0ts |
| 3. The reaction bead's keys and pages retire | `lifecycle/lifecycle.toml` registers `gc.reacted_by`, `gc.reaction_kind`, `gc.reaction_subject`, `gc.reaction_subject_store`, `gc.proactive_reaction`, `gc.reaction_owned`, `gc.proactive` and `gc.blocker_key` as retired, and its proactive group stops describing the reaction bead; `bead-context.sh`'s `reacted_by` field; `tools/helm-surface-fixture.sh`; the pages that state the old model (human-engagement.md, component-model.md, steering.md, authority-map.md, deferred-dispatch.md, bead-store-resolution.md, review-correctness.md), and `doctor/check-claim-advancing`'s description and comment, which list first-reaction beads among the bare beads a pool claims; built-once-target.md's lane B row and its trade line, and the rows `tools/deletion-plan.tsv` gives this member, which the order's file leaves while its script and test go | units 1 and 2 | the subject's done condition |

The cut-over bead of section 6 is the mechanik's and changes the town repo's
`city.toml`, no file here. The clause's removal is a polecat's change to the
prompt, aimed at the default branch.

## 8. Edges and notes the implementation child adds

The implementation child (tk-1tfzr71.106) files the units under the effort's
epic (tk-1tfzr71) with `target=integration/tk-1tfzr71.17` in each
create. The landing bead (tk-1tfzr71.17) and the summary task (tk-1tfzr71.107)
each wait on every unit through a `blocks` edge, and each unit waits on the
units its row names and is armed to dispatch when they close. Before it files,
the child surveys the open branches against each unit's files again, since they
move.

It files the cut-over bead in the gc-toolkit store with a `blocks` edge onto
the landing bead, names in it the pilot rig and the three rigs call 5 pauses,
which this design's bead records in its notes, and sends it to the mechanik with
`gc sling gc-toolkit/gc-toolkit.mechanik <bead> --no-formula --no-convoy`, the
form the mechanik takes work in. Gas City's routed tier offers it once the
landing closes, and core's `cascade-nudge-on-blocker-close` order nudges the
mechanik then. It files the clause's removal with `target=main`, a `blocks`
edge onto the cut-over bead, and an arm for the polecat pool, so it starts once
the cut-over closes.

It appends a note to each bead below:

- **tk-georjc.** This member ends the per-sweep cap and leaves the linking out,
  so its closer finds the cap gone and the linking absent.
- **tk-qgocr1g, tk-i829bzv and tk-52oz0ts.** The unit that answers each, and
  what its closer reads to check it.
- **tk-1tfzr71.24.** The scan reads `gc.takeaway` as the record that a bead was
  triaged, so a change that retires the takeaway fields gives the scan another
  record. `gc-helm.sh` place passes over a run of `mol-first-reaction`.
- **tk-1tfzr71.25.** Unit 3 registers the reaction keys as retired, and the
  registry's retirement takes those entries with the others.

## 9. Gas City facts, and the search behind the surface

Upstream is 297772b4c3. Of the Gas City files this record cites, these are
byte-identical there and in the installed build 6589a7df45:
`internal/sling/sling_core.go`, `internal/sling/sling_attachment.go`,
`internal/graphv2/invocation.go`, `internal/beadmeta/hold_labels.go`,
`internal/orders/scanner.go`, `cmd/gc/demand_serve_predicate.go`, the core
pack's `template-fragments/claim-protocol.template.md` and
`engdocs/architecture/life-of-a-bead.md`. The rest differ between the two:
`cmd/gc/cmd_hook_claim.go`, `cmd/gc/build_desired_state.go`,
`cmd/gc/cmd_sling.go`, `cmd/gc/cmd_convoy.go`, `cmd/gc/cmd_convoy_dispatch.go`,
`cmd/gc/order_dispatch.go`, `cmd/gc/order_store.go`,
`cmd/gc/pool_detached_orphan_sweep.go`, `cmd/gc/wisp_gc.go`,
`internal/sling/sling.go`, `internal/molecule/molecule.go`,
`internal/sourceworkflow/sourceworkflow.go`,
`internal/api/huma_handlers_runs.go`, `internal/events/events.go`, the core
pack's orders, `docs/tutorials/07-orders.md` and `docs/reference/config.md`.
Each symbol and sentence cited from them is in both.

| Fact | Evidence |
|---|---|
| A claim takes only a candidate whose route names the session's pool | hookCandidateClaimable, hookClaimMatchesRoute (`cmd/gc/cmd_hook_claim.go`) |
| A custom work query is run verbatim to find candidates | life-of-a-bead.md, "The hook mechanism"; config.md, `work_query` |
| An agent's default sling formula is applied as `--on` | config.md, the Agent table's `default_sling_formula` |
| A formula only the default supplies gives way to a plain route when a live classic molecule holds the bead, and an explicit `--on` refuses instead | slingDefaultFormula and attachFormulaToBead (`internal/sling/sling_core.go`); checkNoMoleculeChildren (`internal/sling/sling_attachment.go`) |
| A pour mints an input convoy tracking the bead, refuses a terminal target, and stamps `gc.execution_routed_to` while clearing `gc.routed_to` and `gc.run_target` | CreateSingleItemInputConvoy (`internal/graphv2/invocation.go`); restampWorkBeadRouting (`internal/sling/sling_core.go`) |
| A second live run of one formula on a bead is refused with exit 3, and one of another formula is not | checkLegacySourceWorkflowConflict; liveConvoyTrackedWorkflowRoots; `cmd/gc/cmd_sling.go`, the conflict's `return 3` |
| A pour cut short leaves its root open, marked failed or still fenced; the fence holds a bead's route back and marking the pour failed does not restore it; the conflict check counts any root that is not closed | markFailed, fenceGraphWorkflowBead and deferBeadRouting (`internal/molecule/molecule.go`); closeFailedGraphV2Roots (`internal/sling/sling.go`); liveConvoyTrackedWorkflowRoots, which skips only a terminal root |
| An exec order that outlasts its timeout is ended by signalling its whole process group | shellExecRunner and cancelShellExecProcessGroup (`cmd/gc/order_dispatch.go`) |
| A claim retires a run whose input is terminal or handed off, and nothing else retires it | retireDoneWorkflowCandidates, hookRetireIfInputSettled (`cmd/gc/cmd_hook_claim.go`), reached only from the claim |
| The pool's default demand counts a ready, routed step without reading its input, and a worker runs its claim only once its session has started | defaultScaleCheckCountsAndDemand (`cmd/gc/build_desired_state.go`); demandServableForTemplates and demandRowServable (`cmd/gc/demand_serve_predicate.go`); core's claim protocol (`internal/bootstrap/packs/core/template-fragments/claim-protocol.template.md`) |
| A plain sling clears the execution route; reopen-source re-routes the bead; neither source command finds a run slung with `--on` | clearGraphTakeoverRoute; cmdWorkflowReopenSource, cmdWorkflowDeleteSource (`cmd/gc/cmd_convoy_dispatch.go`); the graph.v2 pour's empty source (`internal/sling/sling.go`) and the lookup by `gc.source_bead_id` (`internal/sourceworkflow/sourceworkflow.go`) |
| A convoy closes only once every member is terminal | closeCompletedConvoyAcross (`cmd/gc/cmd_convoy.go`) |
| Run cancel closes a run's open steps and interrupts the turn of each session holding one, without stopping the session | `POST /v0/city/{cityName}/runs/{run_id}/cancel` (`internal/api/huma_handlers_runs.go`) |
| `hold:mayor` and `hold:external` keep a bead out of the hook's claim tiers and its result | DispatchHoldLabels, HasDispatchHold (`internal/beadmeta/hold_labels.go`) |
| An event order's script is told no event; an override naming no order is an error; a definition's `enabled = false` drops the order before overrides | 07-orders.md, "Trigger types", "Formula orders vs. exec orders", "Overrides"; `internal/orders/scanner.go` |
| A sling refuses a missing bead, a pool that cannot read its store and a target the city does not configure | MissingBeadError, CrossStoreRouteError (`internal/sling/sling.go`); validateBuiltInRouteStoreReachable (`internal/sling/sling_core.go`); the target check in `cmd/gc/cmd_sling.go` |
| Core ships no order or formula that triages a new bead | `internal/bootstrap/packs/core/orders` and `formulas` |
| bd's update compare-and-swap writes nothing on a mismatch and exits 13 | `gc bd update --help` (bd 1.3.4), `--if-status` and `--if-assignee` |
| bd's human gate blocks a bead until a person resolves it | `gc bd gate create --help`, `--type=human --blocks` |

The subject's description read its upstream facts on 2026-10-19. Each, as found
now:

| As read on 2026-10-19 | As found on 2026-11-14 |
|---|---|
| a per-agent `work_query` scopes claims, so it could select unreacted subjects | it scopes candidates only; the claim requires a route (above) |
| a reaction can be a formula slung on the subject | holds, and the pour's dedup, stop and closed-subject handling come with it |
| each exit is one or two native writes, and a placement is a gate | holds, except that a placement is `hold:mayor` with no gate (tk-rl8gz4b.30's note) |
| the pack dropped its formula because a pour leaves a route it cannot clear | does not hold for this reaction (section 1) |
| the recommend and ruling exits file a gate through `gc-helm demand`, converted to a visit | they file a native human gate through `human-gate.sh`; the converter retired with the visits (tk-1tfzr71.4, tk-1tfzr71.46) |
| work outside the intake rule waits as `placement=pending` | it carries `hold:mayor` (tk-rl8gz4b.28) |

The surface the change adds or grows, and the search behind each:

- **`formulas/mol-first-reaction.toml`.** Searched: Gas City's work query and
  claim, the routed tier, and core's formulas. A claim needs a route, and no
  core formula triages, so the reaction is a formula of the pack's, slung
  through `gc sling`.
- **The pool's `default_sling_formula`.** Gas City's own agent key, set in the
  pack's agent config.
- **`gc-proactive.sh sling`'s exit 6 and `--check --run`, and `gc-helm.sh`
  react's exit 8.** Searched: `gc sling --dry-run`, which answers only its own
  refusals, and the hook's claim-time retirement, which covers a closed or
  handed-off subject and no pack refusal. No Gas City primitive answers whether
  a bead may take a first reaction, a rule of the pack's.
- **The scan order, kept.** Searched: event orders on `bead.created`, formula
  orders, and core's orders, none of which starts work on a bead nobody slung.
- **The sweep's deadline, an `[order.env]` key of the scan order.** Searched:
  the environment Gas City gives an exec order, which carries no deadline
  (07-orders.md, "Formula orders vs. exec orders"; the exec environment built in
  `cmd/gc/order_store.go`), and the order runner, which ends a run that
  outlasts its timeout by signalling its process group. An override can set an
  order's `timeout` and `env` but not its exec (07-orders.md, "Overrides"), so
  the deadline sits in `env`.
- **The gate on an unfinished pour.** Searched: Gas City's own cleanup of a
  failed pour, which runs only inside the sling that failed
  (closeFailedGraphV2Roots), and its sweep of abandoned roots
  (closeAbandonedRoots, `cmd/gc/wisp_gc.go`), which closes a root only once
  every bead under it is terminal, or a root with none under it only once no
  live source bead is attached to it, and which only logs unless it is
  enforced. Neither ends an unfinished pour on an open subject, so the verb asks
  a person, as gctk's deferred-dispatch start does for an armed bead.

What retires: the reaction bead kind, its keys and `gc.blocker_key`, the
pool's custom query and `cmd_demand`, the cap, `proactive-scan-sling.sh`,
`first-reaction-dispose.sh`'s `--reaction-bead`, `--stand-down`,
`--after-workflow` and `--blocker-key`, and the fixture tool. No key, bead kind
or lifecycle state is added.
