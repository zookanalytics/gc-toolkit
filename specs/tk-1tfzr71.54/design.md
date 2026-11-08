---
name: Design — dispatch only through gc sling and a named agent's assignment
description: The design for tk-1tfzr71.54, the design child of initiative tk-1tfzr71.15, taken at main cbf5fca0f and checked against Gas City upstream main e40616cfd, the installed gc build cb80c5354 and gascity-packs main 2a3b142e. It states the one dispatch rule; what each route write, park, assignment and clear in the pack becomes, and which member converts it; how work that may still be blocked is dispatched; which checks and compensations retire here and which go with the members that delete their files; why nothing replaces the route check but its order-scope finding; the answer to each held problem; the doctrine once the hand-written routes are gone; and the six units the implementation child files. Read it to approve the design at its gate, or to build one of its units.
---

# Design: dispatch only through gc sling and a named agent's assignment

This is the design record for tk-1tfzr71.54, the design child of the
initiative tk-1tfzr71.15. The pack's code was read at main cbf5fca0f, the
commit `integration/tk-1tfzr71.15` was cut from. Each Gas City fact is cited by
symbol at upstream main e40616cfd, and every symbol cited is also present in the
installed gc build, cb80c5354; section 9 names the files that are byte-identical
at both. The store counts were read on 2026-11-08 at about 06:40Z.

## What the operator approves

Today the pack hands work to a pool by writing the route key, `gc.routed_to`,
itself at several sites. It parks a bead for you by writing `human` into that
key beside the human gate it already files. It keeps a doctor check of 1,175
lines (I3) to catch the strings those writes get wrong. Approving this design
moves every pool dispatch onto Gas City's own `gc sling`, gives a named agent
work by assignment alone, makes the human gate the only record that you owe
something, and deletes that check. What reaches you changes only as call 1
says. The implementation child then files six units on the integration branch,
and the members waiting on this one start once the effort lands.

Four calls carry a cost either way:

1. **Your wait becomes the human gate alone, and the `human` route retires.**
   Every move of an anchor into a parked state already files a gate on the
   bead, so the route is a second record of one wait. Unit 5 moves the 38 open
   beads parked on the route today onto gates. The 29 of them with no gate get
   one, so they show in your gate list instead of as routed-to-you rows.
   Keeping `human` as a park value builds nothing, but keeps two records of one
   wait, and keeps the readers that key on a value only this pack interprets.
2. **A self-review loop that runs out of attempts asks you, through a gate.**
   Today it assigns the bead to the witness and nudges it. Nothing in the
   witness's formula or prompt reads a bead assigned to it or the loop's
   exhaustion mark, so the work waits on whatever the witness makes of one
   nudge. No bead is in that state now, in any rig. The other way is to keep
   the witness and give its patrol a duty for this case, which the patrol
   member (tk-1tfzr71.19) would then carry into its rewrite.
3. **The route check is deleted, and only its check of order scopes survives,
   moved into the config check.** Its route findings can only come from a
   hand-written route, and `gc sling` itself refuses an unknown target and a
   route into another store. The order-scope finding catches a pack order meant
   for each rig that would run once, in the city store. Dropping it too saves
   about 20 lines and leaves that mistake silent.
4. **Pool work the other members leave raw should become a poured run.** This
   design converts the pack's own raw routes to `gc sling --no-formula`. The raw
   routes in files other members delete (rework children, first-reaction
   beads, warrants, the orphan sweep's re-route) are theirs to replace, and the
   design asks each to pour a run where the work has a formula. Gas City's run
   cancel stops a run's holder, and nothing native stops a session that holds a
   bare bead. Leaving them raw keeps that case possible (tk-ks7yjzo).

Approving the design as it stands ships the first option of each. The rest
costs nothing either way: route clears in a handoff stay (section 1), and
section 5 answers each held problem.

## 1. The dispatch rule

Once the units land, work reaches whoever does it in exactly one of four ways.

1. **A pool gets work through `gc sling`.** `gc sling <rig>/<pool> <bead> --on
   <formula>` pours a run over the bead. `gc sling <rig>/<pool> <bead>
   --no-formula --no-convoy` routes the bead itself, for work that runs with no
   poured formula and whose method the bead carries. Both flags are needed for
   a raw route. The town's `city.toml` sets
   `[agent_defaults] default_sling_formula = "mol-polecat-work"`, which every
   agent but the control dispatcher inherits (`EffectiveDefaultSlingFormula`,
   `internal/config/config.go`), so a bare sling to any pack agent pours
   `mol-polecat-work`. A plain sling also mints a convoy to track the one bead
   unless `--no-convoy` is given ([dispatch
   architecture](https://github.com/gastownhall/gascity/blob/main/engdocs/architecture/dispatch.md),
   "Auto-Convoy"). Upstream's own design for internal dispatch uses the same
   two flags (`engdocs/design/inline-ralph-v0.md`, "Routing Rules").
2. **A named agent gets work by assignment.** `gc bd update <bead> --assignee
   <agent>`, with the notice `deferred-dispatch.sh notify` sends, and no route
   beside it. Gas City wakes a named session that has work assigned to it
   (the `assigned-work` reason in `ComputeAwakeSet`,
   `cmd/gc/compute_awake_set.go`), and its hook offers that work. A named
   session also claims work routed to its own alias (`namedSelfTargetAdmit`,
   `internal/config/workquery.go`, from upstream 358a8c9ef3, #6180, which the
   installed build carries). So a route beside an assignment adds nothing, and
   once the assignee clears it offers the bead to a pool instead of the agent.
3. **A person's wait is a human gate that blocks the bead.** `human-gate.sh`
   files it, and the bead's `blocks` edge keeps it out of every work query until
   the gate is resolved. This is the built-once target's shape ("What a person
   owes is a native human gate on the bead it blocks",
   [built-once-target.md](../../docs/built-once-target.md#human-engagement)).
   tk-1tfzr71.37, filed on the operator's ruling in sitting tk-6cvhb2e
   (2026-10-31), removed the `held` state and the `human` route it wrote, so a
   pre-PR hold is the gate alone (#1426). Applying the same shape to every park,
   the anchor states included, is this design's proposal.
4. **A clear rides the write that hands the bead off, and stays.** A write that
   unassigns a bead or assigns it to a named agent clears its route in the same
   update. Gas Town's polecat does this in each of its exits: the refinery
   handoff is `--status=open --assignee="$REFINERY_TARGET" --set-metadata
   gc.routed_to=""`, and each halt is `--status=open --assignee=""` with the
   same clear (gascity-packs 2a3b142e, `gastown/formulas/mol-polecat-work.toml`
   lines 1224 and 797-798, among others). Its text says why: "named-session
   work should not retain pool-demand metadata". The pack's releases also unset
   `gc.session_id` and `gc.session_name`, because Gas City's detached-handoff
   orphan lane restores a pool route on an open, unassigned, unrouted bead that
   carries a branch and a session pin (`cmd/gc/detached_orphan_lane.go`). A
   release that has ended the bead's run also clears `gc.execution_routed_to`,
   which is what Gas City's own plain re-sling writes when it hands a bead back
   (`clearGraphTakeoverRoute`, `internal/sling/sling_core.go`).

Two things follow. Nothing reads a route back, since `gc sling`'s exit is the
answer. And a route is never written to say something other than "this pool
may claim this bead": the `human` value and every pairing of a route with an
assignment go.

What a sling does that a hand-written route does not, read in
`internal/sling/sling_core.go` and `cmd/gc/cmd_sling.go`: it refuses a target
the city does not configure (`gc sling --dry-run
gc-toolkit/gc-toolkit.no-such-pool tk-1tfzr71.54 --no-formula --no-convoy`
answered "agent ... not found in city.toml", exit 1, on 2026-11-08); it refuses
a route into a store the pool does not read
(`validateBuiltInRouteStoreReachable`); it collapses a pool slot's suffix to the
pool's name (`NormalizePoolRouteTarget`); it clears a graph takeover stamp the
bead no longer needs (`clearGraphTakeoverRoute`); and it pokes the controller.
The nudge is not a difference: core's `nudge-on-route` order fires on any write
of `gc.routed_to` (`internal/bootstrap/packs/core/orders/nudge-on-route.toml`),
and the city runs it (`gc order list`).

## 2. Every writer, and what it becomes

The census started from the bead's command and widened to `gc.execution_routed_to`
and to writes made through helpers, formulas, prompts and skills. Every line
number is at cbf5fca0f. "Plan" names the bead that `tools/deletion-plan.tsv`
gives the whole file to. Code the plan retires gets no new work (AGENTS.md), so
a site in such a file converts with the member that deletes the file, and
section 8 lists the notes that tell each member what its replacement must not
carry.

### Pool routes written by hand

| Site | Writes today | Becomes | Converted by |
|---|---|---|---|
| `formulas/mol-review.toml:183-184`, the failed gather in load-dispatch | `gc.routed_to` from the review's `review_pool`, read after the run's cancel | `gc sling "$GC_TEMPLATE" "{{review_bead}}" --no-formula --no-convoy`, which reads nothing from the store | unit 1 |
| `formulas/mol-review.toml:409-410`, the review step's failure arm | the same, after the step closes | the same | unit 1 |
| `formulas/mol-review-quorum-signoff.toml:523` | prose telling the reader to restore from `review_pool` | the same sling | unit 1 |
| `assets/scripts/bd-lib.sh:880`, `route_finishing`, called at `pr-facts.sh:2956`, `:3176`, `:3959` and `pre-open-rebase.sh:424` | `gc.routed_to=$FIX_POOL` on a rework child | `gc sling "$FIX_POOL" "$child" --no-formula --no-convoy` after the settle. The callers are left as they are, and their read-back still holds, since the sling writes the same value | unit 1 |
| `assets/scripts/gc-helm.sh:1313-1316`, takeaway `--release --route`, with its read-back and repair at `:1361-1374` | the route inside the park write | the park writes no route, the run beneath the bead ends, and then `gc sling <pool> <bead> --no-formula --no-convoy` routes it | unit 2 |
| `skills/work/SKILL.md:144-146` | names a hand-written route as one of three ways to dispatch | `gc sling <rig>/<pool> <bead> --no-formula --no-convoy` | unit 1 |
| `tools/gc-proactive.sh:1117-1139`, the first-reaction bead's create | the route in the create's metadata | the intake member's design, which retires the first-reaction bead | tk-1tfzr71.17 |
| `assets/scripts/file-warrant.sh:134-136`, called by the witness and deacon patrols | a warrant created routed to the dog pool | that member's design | tk-1tfzr71.18 (plan) |
| `assets/scripts/orphan-dispose.sh:348`, `restore_route` | `gc.routed_to` copied from `gc.execution_routed_to` on a source or review bead | core's `orphan-sweep` resets a dead holder's claim, and a run recovers its own steps | tk-1tfzr71.19 (plan) |
| `assets/scripts/gate-ensure.sh:516` and `:536`, the wedged review's gate | tells a person to write the route by hand | goes with the review beads | tk-1tfzr71.22 (plan) |
| `pr-facts.sh:2828-2853`, `:2925-2927`, `:3837-3854`, `:3936-3938`, `:3175-3185`; `pre-open-rebase.sh:253-270`, `:368-387` | re-route a rework child whose route did not land | retire with their files | tk-1tfzr71.21 and tk-1tfzr71.20 (plan) |

The review's return reads its pool from the session, not the store. A pool
session's `$GC_TEMPLATE` is the routed tier's queue key for its pool, shared by
every session of the template (`engdocs/architecture/prompt-templates.md`), so
it names the pool whose step the reviewer claimed, which is the pool the review
was poured to.

### A person's park, the `human` route

| Site | Writes today | Becomes | Converted by |
|---|---|---|---|
| `lifecycle/lifecycle.toml:21-25` (`human_states`) and `:39-46` (`park_route`), with `services/gctk/internal/lifecycle/machine.go:37-58` and `services/gctk/internal/cli/lifecycle.go:561-567` | `gc.routed_to=human` on entering abandoned, retargeted, blocked or refused_false_completion | no route. A human state rests unrouted and unassigned, as a detached state does, and its gate is the park | unit 3 |
| `formulas/mol-refinery-patrol.toml:922`, `:950`, `:1056` | `--route human`, each beside a `human-gate.sh` call | the flag goes. At `:950` and `:1056` the gate is filed first and the transition made only once it reads back, as `:922` already does | unit 3 |
| `pr-facts.sh:2095` and `:2598` | the human state's default route | changes with lifecycle's default, with no edit | unit 3 |
| `pr-facts.sh:3800`, `:3892`, `:3918`, the red-check parks | `--route human`, each beside a gate | the flag goes. That is the smallest edit that lets the lifecycle change land, the edit the approved native-hold design made in the liveness scripts when it deleted `placement.sh` (specs/tk-rl8gz4b.29/native-hold-and-po.md, noted on tk-1tfzr71.19) | unit 3 |
| `assets/scripts/work-setup.sh:156-159`, a stop with no molecule | a hand-back that writes `gc.routed_to=human` and a headline | `await-ruling.sh` onto the gate its ask filed on the anchor, as the molecule case does at `:143-146`. That releases the claim, clears the route and arms the re-sling | unit 4 |
| `assets/scripts/self-review-check.sh:155-233`, the exhausted loop | the route cleared, and the bead assigned to the witness | the loop's last iteration, finding a check still red, declines through `decline.sh` with a gate (key `self-review-exhausted`, re-sling on `mol-polecat-work`), the one call that files the gate, records the wait, ends the run and drains. The condition keeps only its note on the work bead. It runs inside the control dispatcher's judgment of the control bead that a run's end would close (`self-review-check.sh:16-30`), so the ask moves to the session (call 2) | unit 4 |
| `packs/gascity-keeper/formulas/mol-upstream-gc-sync.toml:91-92`, `:145-146`, `:183-184` | assignee and route both set to `notify_recipient`, which is `human` when unset | a human gate on the bead when the owner is a person, and an assignment with its notice when it is a keeper | unit 4 |
| `template-fragments/heartbeat-no-consent-ui.template.md:18`, read by the witness, deacon and refinery | "park the bead with `gc.routed_to=human`" | file a human gate with `human-gate.sh` | unit 4 |
| the 38 open beads that carry the route (gc-toolkit 27, growth-factor 8, gascity 2, signal-loom 1; none an anchor) | stored | a human gate from the bead's headline where no open gate blocks it (29 beads), then the route cleared | unit 5 |

### Assignments to a named agent

| Site | Writes today | Becomes |
|---|---|---|
| `assets/scripts/work-submit.sh:396-412`, the refinery handoff | assignee the refinery, route cleared | stays: Gas Town's handoff |
| `formulas/mol-design-convoy.toml:577`, `skills/work/SKILL.md:180`, `skills/work/integration-effort.md:89`, `template-fragments/watch-dispatched-work.template.md:17` | an assignment and its notice | stays |
| `packs/gascity-keeper/formulas/mol-upstream-gc-pr-prep.toml:105-106`, `:243-244`, `:344-345`, `:400-401`, `:517-518` | assignee and route both the requesting keeper | the assignment alone, with its notice (unit 4) |
| the keeper's other hand-backs, under `packs/gascity-keeper/`: `formulas/mol-upstream-gc-rebase.toml:159`, `:217`, `:672`, `:739`, `:880`, `assets/scripts/rebase-check.sh:325`, `template-fragments/refinery-rebase-handling.template.md:250` | an assignment alone | stays |
| `gc-helm.sh` takeaway `--assign` | assignee, route cleared | stays, with the park's compare-and-swap (unit 2) |
| a conversation: `gc-helm.sh:2378` (filed assigned to `human`), `:4871-4872` (bound to its sitting), `converse-signoff.sh:817` (back to `human`) | an assignee | stays: a conversation is assigned to your queue or its sitting, as the native-gates design settled |
| each patrol's wisp, assigned to itself in the refinery, witness and deacon formulas and prompts | `--assignee=$GC_AGENT` | stays until the patrol member settles the patrols' shape, as the initiative says |
| `first-reaction-dispose.sh`'s `--assign` and `--then-assign` exits | through the takeaway verb and an arm | stays; the intake member reshapes the exits (tk-1tfzr71.17) |
| `skills/waits/SKILL.md:109`, a human gate assigned to the person who must clear it | an assignee on a gate | stays |

### Clears

| Site | Becomes |
|---|---|
| `hand-back.sh:119-120`, and its callers `work-submit.sh:221` and `:340` (store-only and `auto_push=false`) and `decline.sh:156` | stays: each is the release half of a hand-back, guarded on the claim it read |
| `work-submit.sh:396` and `:410`, the refinery handoff's clear | stays |
| the polecat's nudge hand-back, `agents/polecat/agent.toml:33-36` and its codex twin | stays; it writes no route |
| `await-ruling.sh:337-341` | the clears of `gc.routed_to` and `gc.execution_routed_to` and the pin unsets stay. The clears of `gc.deferred_routed_to`, `gc.deferred_execution_routed_to` and `gc.deferred_assignee` go (unit 1): Gas City writes those only on a poured graph node (`deferGraphNodeRouting`, `internal/molecule/graph_apply.go`), and every one of the 70 non-step beads in gc-toolkit's store that carries them holds them empty, which are this script's own writes |
| `skills/converse-settle/SKILL.md:166`, `skills/converse-continue/SKILL.md:46`, a sitting clearing its subject's pool route | stays. Unit 5 drops "and keeps a `human` route" from the text |
| lifecycle's detached states, which clear the route and the assignee (`lifecycle.toml:26-38`) | stays: an anchor the merge cadence drives rests unrouted (section 5, tk-futn21) |
| `rejection-repool.sh:220-221`, `:294`; `orphan-dispose.sh:302-303`; `pr-facts.sh:957` | retire with their files (tk-1tfzr71.20, .19, .21). `pr-facts.sh:957` clears only a `human` route, so it does nothing once unit 5 lands |

## 3. Work that may still be blocked

A raw route can be written while its bead is blocked. Gas City's routed tier
reads `bd ready`, which withholds a blocked bead, and core's
`cascade-nudge-on-blocker-close` order nudges the bead's route target when its
blocker closes. So a site that dispatches raw work slings at once, whatever
holds the bead.

A pour cannot. Nothing on the sling path checks blockers: `preflight` runs only
`DetectCycle`, and only for a plain sling (`internal/sling/sling_core.go`,
`internal/sling/cycle.go`), so a run poured over a blocked bead offers its first
step at once. A site that pours over work that may still be blocked arms the
bead instead (`deferred-dispatch.sh arm`), and the arm's reconcile slings it
once nothing holds it. That arm is the residual the deferred-dispatch member
keeps (tk-1tfzr71.16).

No site this design converts pours over a bead that may be blocked. The review's
return, `route_finishing` and the takeaway's `--route` are raw. The takeaway's
`--route` keeps its refusal of a bead blocked by anything but a human gate,
because the work is then on the blocker and the bead has no method a pool can
perform, which is a different question from readiness. The two waits that
re-pour, `work-setup.sh`'s stop and the exhausted self-review loop, arm through
`await-ruling.sh`, so they are the deferred-dispatch member's to reshape.

## 4. What polices routes, and who removes it

### The route check (I3), arm by arm

`doctor/check-routed-work-claimable` is the plan's one whole-file retirement for
this member. It writes nothing. Each of its findings goes as follows.

- **Address form** (`run.sh:253-291`): a route or an assignee that is not
  byte-equal to a live identity or `human`, judged in jq. After unit 1 a route
  comes only from `gc sling`, which refuses an unknown target and normalizes a
  slot's suffix. An assignee is still written by hand, but each writer derives
  it from config or from its own session. Nothing replaces this arm.
- **Reachability** (`run.sh:293-488`): a routed, unassigned bead in neither
  `bd ready` nor `bd blocked`. The check asks the store for both lists rather
  than computing a wait, as the gctk design's census found (tk-ssm8qns.2,
  census D5). Its cross-store finding cannot arise from `gc sling`. Its
  orphaned-step finding is the one I8 (`doctor/check-step-terminal`) reports for
  an offerable step under a closed root. What remains is a routed bead that a
  status other than open keeps out of both lists, as `bd defer` does on
  purpose, and its status is the record of why it waits. A hold written as a
  marker with no edge is I1's finding (`doctor/check-wait-is-an-edge`). Nothing
  replaces this arm, so no unit waits on `gctk bead holds` (tk-ssm8qns.11). A
  later reader that asks whether a routed bead is held, and by what, asks that
  verb and computes no wait itself, as the initiative's notes require.
- **Order scope** (`run.sh:533-552`): an order registered with no rig whose file
  declares `scope = "rig"`. It has nothing to do with routes. Gas City registers
  an order from a city-level layer rigless whatever its scope field
  (`internal/orderdiscovery/discovery.go`), and runs a rigless order in the city
  store (`resolveOrderStoreTarget`, `cmd/gc/order_store.go`). So a city-level
  import of this pack would run each per-rig order once, in the city store, and
  no upstream check reports it. Unit 6 moves this arm and its cases into
  `doctor/check-config-bound`, which already judges the resolved config's
  addressing (call 3). Of the 36 rigless registrations on 2026-11-08, none
  declares `scope = "rig"`.

`assets/scripts/doctor-parallel-reads.test.sh` uses this check's `run.sh` as the
reference copy of a fenced block shared with `check-armed-dispatch-owed` and
`check-hq-marooned-work`, so unit 6 moves the reference to
`check-armed-dispatch-owed`. The check's other mentions are its rows in
`docs/component-model.md` and `docs/install.md` and the hand-off text in I11
below.

### The claim check (I11)

`doctor/check-claim-advancing` is in no row of the plan, and no part of it
polices a route. Arm 1 judges the holder of an in-progress bead that carries
`gc.step_ref` (`run.sh:291-377`) and reads no route. Arm 2 reads an open step's
route only to find the pool that should claim it (`run.sh:414-416`). The one
part that goes here is arm 2's note for a route that names no agent, which hands
the case to I3 by name (`run.sh:598-599`). After unit 1 such a route can only be
written by a person, and unit 6 rewords the note to say so. Arm 1's scope is
held problem tk-ngm6ewg (section 5).

### Compensations in other members' files

- The stranded-rework rescues in `pr-facts.sh` and `pre-open-rebase.sh` exist
  because a route write could exit 0 without landing. They retire with their
  files (tk-1tfzr71.21, tk-1tfzr71.20), and this member does not edit them.
  Unit 1 changes what they rescue from: `route_finishing` slings, and a sling
  whose write fails exits non-zero.
- `assets/scripts/work-tree-holder.sh` reads no route and writes nothing. It
  reads assignees to find a session's claims (`work-tree-holder.sh:7-11`,
  `:227`), so its retirement (tk-1tfzr71.39) has nothing to do with this
  member.
- `assets/scripts/liveness-classify.sh:154` counts any route as routed and
  claimable, `human` included. It retires with tk-1tfzr71.19.
- `assets/scripts/duplicate-sweep.sh` is gone (#1439).
- `formulas/mol-review.toml` converts here rather than with the review beads.
  The member that retires review beads (tk-1tfzr71.22) waits on two others, and
  the restore's failed read is a defect the initiative's notes put on this
  member.

## 5. The held problems

- **tk-futn21: a route on an anchor offered it to the pool as fresh work.** The
  route came from a hand-written cap reset. After this member no pack site
  writes a route by hand, and none slings an anchor. The takeaway verb is the
  one dispatch a person or a sitting can aim at any bead, so unit 2 makes its
  `--route` and `--assign` refuse a bead whose `merge_result` is a detached
  state: the merge cadence drives it, and work on its branch goes to a child.
  Lifecycle's detached states keep clearing the route and the assignee, and
  `doctor/check-state-space`'s `detachedroute` finding keeps reporting the one
  way the shape can still arise, a person's own `gc sling` of an anchor. That
  finding checks a declared state, not who wrote the route.
- **tk-77b54fz: the release can reopen a bead that closed between its read and
  its write.** Unit 2 writes the park with `--if-status` and `--if-assignee` set
  to what the closed-anchor guard read. A mismatch writes nothing and exits 13
  (`gc bd update --help`). On a refusal the release reads the bead again, takes
  the closed-anchor path when the bead is now closed, and otherwise fails
  without taking the bead from whoever holds it. `gc-helm.test.sh` gets the
  regression the bead names: a close between the read and the write. The guard
  has a second edge, below: bd lets a write that names the holder in
  `--if-assignee` change a claim it would otherwise refuse to touch, so the
  compare-and-swap is made on a claim only once its holder is shown gone.
- **tk-ks7yjzo: the release cannot stop a raw-routed bead a live polecat
  holds.** A plain update that changes another actor's live in-progress claim
  is refused, and bd then writes none of that update. An update whose
  `--if-assignee` names the holder skips that refusal, since such a write is
  how a sanctioned transfer works (`validateIssueReassignable`,
  `cmd/bd/show_unit_helpers.go` and its call in `cmd/bd/update.go`, at bd
  7ef2fd05e, the installed bd 1.3.4). Gas City's run cancel interrupts the
  holders of a run's steps, and nothing native interrupts a session that holds
  a bare bead. So unit 2 releases an in-progress claim only on the rule
  `await-ruling.sh` already applies: the claim is this session's, or its holder
  is one `gc session list` names under none of its names, and then through
  `gc bd release-if-current`, which releases only a claim still held as read
  (`cmd/gc/cmd_bd.go`). On a live holder's bare bead the release writes its
  headline alone, with no status or assignee change, adds any `--waiting-on`
  edge, nudges the holder with the stop and its reason, and exits non-zero
  naming the holder instead of suggesting the bead does not exist. The
  holder's own exit then releases the claim and its route in one guarded
  write. A stop that must hold even if the holder dies first names a gate with
  `--waiting-on`, since readiness withholds a gated bead whatever its route,
  and the work skill's stop path says so. Call 4 removes the case where the
  work has a formula.
- **tk-ngm6ewg: whether I11's arm 1 judges every pool-routed claim.** It keeps
  its step scope, and unit 6 makes its description say why. A claim held by a
  session that no longer exists, on any bead, step or not, is reset by core's
  `orphan-sweep` order every five minutes ("Reset beads assigned to dead
  agents back to the work pool"), which the city runs. A holder that exists
  but is not running, or has stalled, goes unjudged on a bare bead. The bare
  beads a pool claims after this member are the rework children, first-reaction
  beads and warrants, each in a file its member retires, and a review returned
  to its pool, which goes with the review beads (tk-1tfzr71.22). Once those
  members pour runs (call 4), every pool claim is a step that arm 1 already
  judges. Widening arm 1 now would judge pools nobody has measured against its
  stall bound, for shapes that are retiring. The refinery pool design's widening to the refinery's route
  (specs/tk-9w4e8av) is not in the code at cbf5fca0f, and the refinery is a
  named session that takes its work by assignment (`pack.toml:107-110`).
- **The review's return takes a store that does not answer as no pool.** Unit 1
  reads nothing: the pool is the session's `$GC_TEMPLATE`. When the sling itself
  fails, the review stays unrouted, and gate-ensure asks a person about it once
  its run reads spent, which is today's backstop. The step text tells the
  reviewer to note a failed sling on the review bead.

## 6. The doctrine

- **The route row in `docs/authority-map.md`** states the rule of section 1: a
  pool route is written only by `gc sling`, a named agent's work by its
  assignment, a person's wait by a human gate. The clause allowing a direct
  stamp "only where a bare sling would be hijacked" goes, since `--no-formula`
  is the native answer to that hijack. The clause on clears stays as it reads,
  and names Gas Town's handoff as its source.
- **The ROUTE rule in `lifecycle/lifecycle.toml`** (`:400-420`) states that
  lifecycle writes no route on a transition, except the clear of a detached
  state, and that a park is a human gate. Its list of shapes that stamp directly
  goes. `park_route` and the human states' route go with it, and so does the
  park route as a hold marker in `[holds]` (unit 5).
- **`docs/gascity/routing-model.md`**, "A graph.v2 attach routes the workflow
  root", states that upstream now clears the work bead's `gc.routed_to` and
  `gc.run_target` at the attach (`restampWorkBeadRouting`). The fork's
  `retireClaimRoute` and `retireInputConvoyClaimRoutes`, which the section names
  as fork-only, no longer exist at either revision. The sentence that a bead
  meant to be claimed directly must not be slung without `--no-formula` stays,
  since it is a platform fact, and gains `--no-convoy`. The sections this design
  re-read take their new dates.
- **`docs/deferred-dispatch.md`**, "Work assigned to a named agent owes a
  notice", already states rule 2 and keeps it.

## 7. The units

Each unit lands on `integration/tk-1tfzr71.15`, keeps the suite green and leaves
the city working. The writers convert before the check that polices them goes.

| Unit | What it does | Waits on | Answers |
|---|---|---|---|
| 1. Raw routes go through `gc sling` | the review's two returns and the quorum sign-off's prose; `route_finishing`; the work skill's dispatch forms; `await-ruling.sh`'s three dead clears; the routing model's attach section and dates. Tests for each converted write, with `gc sling` stubbed where the suites stub `gc` | nothing at filing | the review's failed read |
| 2. The takeaway release dispatches through `gc sling` | the park writes no route and is a compare-and-swap; `--route` slings after the run's end; the route's read-back and repair go; `--route` and `--assign` refuse a detached anchor; an in-progress claim is released only once its holder is shown gone, through `gc bd release-if-current`, and a live holder's bare bead gets its headline alone and a nudge to its holder; the work skill's stop path; `gc-helm.test.sh` regressions for each | tk-1tfzr71.11, whose PR rewrites this block and takes out its per-key read-backs, and tk-rl8gz4b.28, whose branch rewrites the block's pour-stamp read-back | tk-77b54fz, tk-ks7yjzo, tk-futn21 |
| 3. Lifecycle writes no park route | human states rest unrouted; `park_route` goes from lifecycle.toml, gctk's machine and CLI, and lifecycle.sh's comment; the refinery patrol's three transitions, gate first; pr-facts' three red-check flags; the ROUTE rule's text | tk-1tfzr71.11, whose PR changes lifecycle's route read-back, lifecycle.toml and the refinery patrol | call 1, with units 4 and 5 |
| 4. The other parks file a gate | `work-setup.sh`'s stop with no molecule; the self-review step's last-attempt decline, read from the control bead's `gc.max_attempts` and `gc.attempt_log`, and the condition's hand-back reduced to its note; the keeper's sync aborts and pr-prep hand-backs; the heartbeat fragment | nothing at filing | call 2 |
| 5. The `human` route's last parks move onto gates | a one-off migration, run once and recorded in its spec with no shipped script: in every rig store, each open bead on the route gets a human gate from its headline unless one already blocks it, then its route is cleared, each read back. Then the readers' `human` clauses outside the plan go: `IsPersonBlocker`'s route test (`services/gctk/prstatus/gates.go`), `blocker-holder.sh`, `bead-context.sh`, `pool-route.sh`, `resolve-route.sh`, `pr-stack.sh`, `check-wait-is-an-edge`'s park marker, `check-hq-marooned-work`'s exemption, `check-state-space`'s park exemption, and the converse skills' wording | units 3 and 4 | call 1 |
| 6. The route check retires | `doctor/check-routed-work-claimable` deleted with its plan rows; its order-scope arm moved into `doctor/check-config-bound`; the parallel-reads test's reference moved; I11's note and description; the I3 rows in `docs/component-model.md` and `docs/install.md`; the authority map's route row | units 1 to 4 | tk-ngm6ewg, call 3 |

The readers of `human` that unit 5 leaves are each in code another member owns,
and each does nothing once no bead carries the route: the board's routed-to-you
query and derive (`services/helm/internal/source/beads.go:536`,
`board/derive.go`, `board/state.go`; tk-1tfzr71.24), the orphan and liveness
readers and the witness patrol's skip (tk-1tfzr71.19), and `pr-facts.sh:957` and
`:3647` (tk-1tfzr71.21).

### What each waiting member needs

The members that wait on this one block on the landing bead, tk-1tfzr71.15, so
all four are released together when the effort reaches the default branch. Each
needs these units.

| Member | Needs | Because |
|---|---|---|
| tk-1tfzr71.16, deferred dispatch | units 1 and 4 | it converts raw-route arms to an immediate `gc sling --no-formula`, the form unit 1 fixes, and it reshapes the arm `await-ruling.sh` records, which unit 4's two parks use |
| tk-1tfzr71.17, intake | units 2, 3 and 4 | its actionable exit releases through the takeaway verb unit 2 rebuilds, and its recommend and ruling exits wait on a gate, which units 3 and 4 make the only park |
| tk-1tfzr71.19, patrols | units 5 and 6 | its orphan and liveness readers skip a `human` route no bead then carries, and the doctor set its order runs no longer holds I3 |
| tk-1tfzr71.25, registry and lint | units 5 and 6 | the park route's registry entries and I3's rows are gone |

## 8. Edges and notes the implementation child adds

The implementation child (tk-1tfzr71.55) files the six units under the effort's
epic (tk-1tfzr71) with `target=integration/tk-1tfzr71.15` in each create. The
landing bead and the summary task (tk-1tfzr71.56) each wait on every unit
through a `blocks` edge. Each unit waits on the units and beads its row names,
and is armed to dispatch when they close. Before it files, the child surveys
the open branches against each unit's files again, since they move. At this
design's reading two overlap: tk-1tfzr71.11 (PR #1414, open), which rewrites the
takeaway release and lifecycle's route read-back, for units 2 and 3; and
`integration/tk-rl8gz4b.28` (at its pre-open gate), which also rewrites the
takeaway's pour-stamp read-back that unit 2 removes.

It appends a Rule 1 note to each member below, saying what its replacement must
not carry.

- **tk-1tfzr71.21 and tk-1tfzr71.20.** A rework or rebuild child is dispatched
  by `gc sling`: a poured run where the child's method is `mol-polecat-work`,
  as `rework-child.sh` already does, and otherwise `--no-formula --no-convoy`.
  No route is written by hand, no stranded child is rescued, and no anchor is
  parked on a route; its gate is the park.
- **tk-1tfzr71.19.** No route is restored from `gc.execution_routed_to`: core's
  `orphan-sweep` resets a dead holder's claim and a run recovers its own steps.
  A census does not count a route as an offer by itself, and nothing reads
  `human` as a park.
- **tk-1tfzr71.22.** A wedged review's repair is a sling, `gc sling <pool>
  <review> --no-formula --no-convoy`, or whatever the lanes put in its place,
  never a hand-written route.
- **tk-1tfzr71.18.** A warrant reaches the dog pool through `gc sling`.
- **tk-1tfzr71.17.** A first reaction is slung or claimed through the work
  query, and no create carries a route in its metadata.
- **tk-1tfzr71.24.** The board's routed-to-you query and the derive's reads of
  the `human` route do nothing once unit 5 lands, and the board renders a
  person's wait from the gate.

The held problems tk-77b54fz, tk-ks7yjzo and tk-ngm6ewg already wait on the
landing bead, with the validating closer armed. The child appends to each the
unit that answers it, so the closer knows what to check.

## 9. Gas City facts, and the search behind the surface the units add

Each fact this design rests on, with where it was read. Upstream is e40616cfd.
`internal/sling/sling_core.go`, `internal/sling/cycle.go` and
`internal/config/workquery.go` are byte-identical at e40616cfd and at the
installed build cb80c5354.

| Fact | Evidence |
|---|---|
| A plain sling writes only `gc.routed_to`, normalized, then clears a stale graph takeover stamp, stamps a merge strategy only from `--merge` or the rig's default, mints an auto-convoy unless `--no-convoy`, and pokes the controller | `cliBeadRouter.Route` (`cmd/gc/cmd_sling.go`); `finalizeInStore`, `clearGraphTakeoverRoute` (`internal/sling/sling_core.go`); `SlingMergeStrategy` (`internal/sling/sling.go`). The town's city.toml sets no `default_merge_strategy` |
| An attach clears the work bead's `gc.routed_to` and `gc.run_target` and stamps `gc.execution_routed_to` | `restampWorkBeadRouting` (`internal/sling/sling_core.go`) |
| No sling path checks blockers | `preflight`, `shouldCheckDepCycle`, `DetectCycle`; the cycle walk skips `related` and `tracks` edges (`isCycleSensitiveDep`), so a rework child joined to its anchor by `related` slings |
| A sling refuses an unknown target | the dry run in section 1, against the installed build |
| `--reassign` clears an assignee and reopens an in-progress bead, unguarded | `reopenForReassignInStore` (`internal/sling/sling_core.go`) |
| A named session claims work routed to its alias, and is woken for work assigned to it | `namedSelfTargetAdmit` (`internal/config/workquery.go`, upstream 358a8c9ef3, an ancestor of cb80c5354); `ComputeAwakeSet`'s `assigned-work` reason (`cmd/gc/compute_awake_set.go`) |
| A pool session's `$GC_TEMPLATE` is its pool's queue key | `engdocs/architecture/prompt-templates.md`, the table of identities |
| Core nudges on a route write and on a blocker's close, and resets dead holders' claims | `internal/bootstrap/packs/core/orders/nudge-on-route.toml`, `cascade-nudge-on-blocker-close.toml`, `orphan-sweep.toml`; all three in `gc order list` on 2026-11-08 |
| Gas City restores a pool route from a session pin on a bead whose handoff cleared both halves | `cmd/gc/detached_orphan_lane.go` |
| `gc bd release-if-current` releases only a claim still held as read | `cmd/gc/cmd_bd.go`, the command's help |
| bd refuses a plain update that changes another actor's live claim, and lets one through whose `--if-assignee` names the holder; a status or assignee mismatch on `--if-status` or `--if-assignee` writes nothing and exits 13 | `validateIssueReassignable` (`cmd/bd/show_unit_helpers.go`, called from `cmd/bd/update.go`) at bd 7ef2fd05e, the installed bd 1.3.4; `gc bd update --help` |
| An order from a city-level layer registers rigless whatever its scope, and runs in the city store | `internal/orderdiscovery/discovery.go`; `resolveOrderStoreTarget` (`cmd/gc/order_store.go`) |
| Gas Town's polecat clears the route in every exit that unassigns | gascity-packs 2a3b142e, `gastown/formulas/mol-polecat-work.toml:1224`, `:797-798`, `:936-941`, `:973-978` |

The units add one piece of surface. Unit 6 gives `doctor/check-config-bound` a
new finding, the order-scope arm moved out of I3. The search: Gas City's order
discovery and order store, cited above, register and run the misplaced order
without a word, and upstream's doctor checks judge a named session's scope
(`internal/doctor/checks_rig_coverage.go`) but not an order's. Unit 5's
migration ships no script. Every other change composes `gc sling`, bd's
compare-and-swap, `human-gate.sh` and `await-ruling.sh`, or removes code.
