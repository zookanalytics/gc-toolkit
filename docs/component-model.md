---
name: Component model — the primitives and the invariant→check binding
description: The design authority of gc-toolkit — the short list of primitives every component must justify itself against, the anchor lifecycle's shape as counts and writers, every invariant bound to the doctor check that fails when it stops being true, and the index placing every component in one of the six workflows. Read it before adding a component, a state, or a metadata key.
---

# Component model

The primitive set, the anchor lifecycle's shape, the invariant→check
binding, and where every component sits. This is the document a new component
must justify itself against; the 2026-08 rewrite
(`specs/2026-08-rewrite/plan.md`) implements §1–§3.

## Scope

**Mandate.** Which primitives the pack is built from, the lifecycle's
single-writer discipline stated as counts, every invariant bound to its
mechanical check, and which workflow each component belongs to.

**Boundaries.** It does not draw the lifecycle — [state-machine.md](state-machine.md)
owns the diagram, the transition table, and the check vocabulary. It does not
narrate the merge cadence ([refinery-merge-cadence.md](refinery-merge-cadence.md))
or the human surface ([gascity-human-engagement.md](gascity-human-engagement.md)),
and it does not compose the lifecycles —
[lifecycle-composition.md](lifecycle-composition.md) owns the seam.

## The one rule this document is held to

> **Every invariant below names the mechanical check that fails when it stops
> being true.** An invariant with no named checker is marked **UNCHECKED** and
> filed as a bead. Prose is what rots.

---

## 1. Primitives

Each earns its place by answering the second column. Anything that cannot is
in the discard list below it.

| Primitive | What it is | Cost of not having it |
|---|---|---|
| **Bead** | one durable row: id, status, assignee, metadata, notes | state lives in agent context and dies with the session |
| **Graph edge** | typed relation between two beads (`blocks`, `parent-child`, `tracks`, …) | a wait becomes a sentence, and nothing can re-evaluate a sentence |
| **Anchor** | the single open bead that owns a PR and carries its checks | N claimants on one PR ⇒ the weakest check-set decides the merge |
| **Convoy** | tracked set with one landing target | no unit larger than a bead can land, and integration branches cannot graduate |
| **Formula + step bead** | a workflow materialised as beads | a crashed session resumes by reconstructing intent from prose |
| **Check-set + check lane** | the merge preconditions an anchor declares in `check_set`, one lane per check. A lane's `check.<g>` marker carries one bare state word that names no commit, and the reviewed commit is recorded on the review bead as `reviewed_oid`. `lane-state.sh` derives a lane's green from its reviews. [state-machine.md](state-machine.md#checks) owns the vocabulary. | merges depend on whoever remembers to look |
| **Pool + route** | demand addressed to a role, not to a session | dispatch names a mortal process |
| **Order** | controller-owned recurring pass, no LLM | cadence becomes an invisible daemon |
| **Agent session** | one mortal executor with an identity | nothing can be claimed, and nothing can be recycled |
| **Worktree + `polecat/<bead>` branch** | per-bead isolation | concurrent writers stomp one checkout |
| **Visit / subject** | the human's queue | results propagate as a colour change on a board nobody opens |

### Discard list

Dropping these is as much the design as keeping the list above.

| Discard | Why it is not a primitive |
|---|---|
| `merge_result` as a *second* status field | one state per bead. The key name survives for ledger continuity, but the enum is closed in `lifecycle/lifecycle.toml` and only `lifecycle.sh` writes it — a declared machine, not a second field. |
| `gc.routed_to` as a field distinct from `assignee` | route and owner are one question asked twice |
| `in_progress` as a status | it means *claimed*, which the assignee already says |
| free-form metadata as the state space | an unregistered key is an accumulation; `lifecycle.toml` enumerates every pack-written key |
| the healer passes, **as a category** | each repaired a writer that did not always run; atomic transitions remove the need |
| prose-carried design | a rule a reader must extract from a paragraph is not enforced |

### What kind of bead this is

A bead's kind is `metadata.task_kind`. Every reader that branches on kind
reads that key and nothing else — `visit`, `review`, `triage-subject`,
`observation` and the standing kinds are all resolved this way, in the
liveness sweeps, the gate scripts, the doctor checks, and `helm`'s visit
filter. The standing kinds name a record that is open, unrouted and unassigned
by design and never closes. Their one definition is
`assets/scripts/standing-kinds.sh`, which a reader sources for the list and
for the `is_standing_kind` test.

A label naming the same word is **not** the kind. It is a listing narrowing:
`gc bd list -l observation` is cheaper than reading every bead's metadata, and
that is the whole of its job. Two rules follow, and together they are the
labels-vs-metadata stance:

- **A label may narrow a query; it may never decide one.** A reader that
  narrows with `-l <kind>` re-filters the result on `task_kind`, because the
  label is free text and any bead may carry it. The narrowing decides what the
  reader *sees*; `task_kind` decides what it *counts*.
- **Which kinds carry a label is per-kind, not uniform.** It is a property of
  that kind's writers, and a kind earns a `-l` narrowing only once every writer
  of it sets the label. Kinds written by the learning loop carry one, though
  only `observation` is narrowed by a reader today; `review`, `visit` and
  `triage-subject` do not, and no reader wants one there —
  back-filling labels nothing reads would buy a migration and no property.

The second rule is what makes the first one safe, and it is the half a reader
can get wrong silently: narrow on a label some writer of the kind omits and
the query is quietly short, with no error to report. I12 is that proposition.

The `task_kind` **key** is registered in `lifecycle/lifecycle.toml`; its
**values** are not a closed enum, and the live store carries kinds no pack code
writes.

---

## 2. The lifecycle, as counts

The machine itself — states, transitions, writers, checks — is drawn once, in
[state-machine.md](state-machine.md), from the declaration in
`lifecycle/lifecycle.toml`. What this document holds it to:

- **~12 transitions** (down from 19 pre-rewrite), **0 performed by repair
  passes** (down from 7). Every transition is one atomic `lifecycle.sh` write
  by the component that caused the change; the only reactive writers respond
  to external facts — `pr-facts.sh` to GitHub events, witness orphan recovery
  to session death.
- **One transition writer** — `lifecycle.sh`: validate → one `bd update`
  carrying every field of the transition → read back. A single `bd update` is
  atomic ([gascity-routing-model.md](gascity-routing-model.md)); the old
  healer passes existed because writers split transitions across calls.
- **One check-verdict writer** — `signoff.sh`. Clearing a marker is a separate
  power from writing one: a clear withdraws evidence where a verdict asserts
  it, so no clearer can make a check pass. Three components hold that power,
  each under one condition stated in [authority-map.md](authority-map.md).
- **One posture writer** — `pr-facts.sh`, which records what the PR is doing
  (`pr_posture`, `pr_merge_state`, the comment watermarks) so every consumer
  reads it off the anchor instead of re-deriving it from GitHub. It runs twice
  per cadence pass, `--posture-only` before the merge arm and in full after it,
  because a reader that never asks GitHub needs the record to be no older than
  the decision it feeds. The pre-merge run's exit code carries the other half of
  that: an anchor it could not make current holds the merge arm for the pass, so
  the reader is never handed a stale fact in place of a fresh one. Both runs are
  the same writer, and the write is idempotent.
- **One merge writer** — `merge.sh`, which re-reads the full authorization set
  immediately before merging. `--match-head-commit` pins the merge to a
  commit, but the authorization set — `merge_hold`, `pr_posture`,
  `merged_target`, and every declared lane's derived green — does not move
  the head; the pre-merge re-read, which re-derives each lane through
  `lane-state.sh`, is what catches a mid-pass change to any of them.

---

## 3. Invariants

Propositions, each true or false, each with the check that catches it going
false. **UNCHECKED** means the check does not exist and is filed as a bead.

| # | Proposition | Check |
|---|---|---|
| **I1** | Every dependency is recorded in the bead graph — no wait lives only in prose or a metadata string. The shape it asserts is [I1 in full](#i1-in-full-the-hold-the-demand-and-the-shape-law) below. | `doctor/check-wait-is-an-edge`: a LIVE bead carrying one of the hold markers declared in `lifecycle/lifecycle.toml` `[holds]` must also carry a `blocks` edge to a bead still live in the same store. Live is every non-closed status, because claiming or parking a bead does not answer the hold it states. Only `blocks` counts: it is the one edge type that holds a bead out of `bd ready`, so a `tracks` or `parent-child` record leaves the hold as unanswerable as the marker did. Only the same store counts, because a cross-store `bd dep add` reports success and holds nothing. Two degrees are reported apart, since their remedies differ: a bead with no `blocks` edge at all needs one filed, and a bead whose every blocker has closed, or names another store, needs its disposition instead. The markers are read from the declaration and never parsed out of prose, because a conclusion is prose by design and no list of wait verbs finishes, so every phrase one missed would report a clean pass. One marker can be answered by its own writer instead: `settled_keys` pairs `gc.takeaway` with `gc.takeaway_settled`, which `gc-helm.sh takeaway --no-wait` stamps beside the headline where the sitting settled its subject, and a headline without it stays a hold. That is the same refusal to read prose from the other side — every sign-off stamps a headline, only the writer knows whether it parked anything, and the key is where it says so. Each writer of the marker rewrites the key with it, so a settled sitting cannot answer for the park that follows it. The terminal end of a wait is exempt outright: a demand bead — the thing dependent work blocks ON — carries the hold's headline but can hold no forward `blocks` edge of its own, so `terminal_wait_key` (`gc.demand_for`, stamped by `gc-helm.sh demand`) names it in the declaration and a live bead carrying it is skipped rather than filed. `hold_severity` in the same declaration sets how findings are reported: a warning while the standing backlog of marker-only holds is converted, an error once it is. Takeaway holds are written as edges by `gc-helm.sh takeaway --waiting-on`, which warns when it could wire only the string; a first reaction's blocked disposition writes one (`first-reaction-dispose.sh`); gate holds stay head-bound markers by design. |
| **I2** | The state space is closed: every `merge_result` value and status combo is declared in `lifecycle/lifecycle.toml`, and a bead in a declared detached state rests unheld and offered to no pool. | `doctor/check-state-space` |
| **I3** | Every routed bead is claimable: route AND assignee name a live target, routed work is in `bd ready` or in `bd blocked`, and rig-scoped orders are bound. | `doctor/check-routed-work-claimable` |
| **I4** | Every PR has exactly one owning anchor, and every gating anchor is open. | `doctor/check-one-anchor-per-pr` (structural); `merge.sh` also refuses on sight, fail-closed |
| **I5** | No bead is closed while the work it represents is unlanded: closed anchor ⇒ `merged` + `merged_sha`, or an explicit terminal state. | `doctor/check-closed-implies-landed` |
| **I6** | Every gating anchor declares a non-empty `check_set`, and every marker is a bare lane-state word. | `doctor/check-gate-integrity` |
| **I7** | A check verdict was written by the one audited writer, `signoff.sh` — narrowed from the old provenance question by making the writer singular. | `doctor/check-gate-integrity` (marker form); the single-writer property is held by construction: `signoff.sh` contains the only code that sets a `check.*` value. The two other components that touch the key ([authority-map.md](authority-map.md)) only clear it, which cannot forge a verdict. `doctor/check-gate-marker-provenance` (tk-iljtmq) carries the depth half in two arms. Green is derived from the outcome graph (`lane-state.sh`), so its **outcome arm** audits that graph markerlessly: every CLOSED `task_kind=review` bead that backs a lane on an open gating anchor — `signoff_verdict=approve` carrying a non-empty `reviewed_oid`, the local backing `lane-state.sh` derives green from — must record `gc.outcome=recorded` (a live backing) or `gc.outcome=superseded` (retired); an approve carrying any other outcome still derives the lane green (`lane-state.sh` excludes only `superseded`) while standing on a verdict no writer recorded, and is the finding. Because `gate-ensure.sh` still reads `check.<lane>` and skips dispatch on `green`, a **marker arm** is kept during the transition: a `check.<lane>=green` on such an anchor that resolves to no backing — no closed `signoff_verdict=approve` review bead for that lane carrying a `reviewed_oid`, no APPROVED GitHub review on its `pr_number` — is the wedge (gate-ensure raises no review while `lane-state.sh` holds the merge), an error, or an undetermined warning when the GitHub path could not run. It reads no commit oid. An operator's APPROVED GitHub review passes both arms. A closed review with no `signoff_verdict` backs no lane, because `signoff.sh` stamps `gc.outcome=recorded` on every close and `recorded` names no verdict. The outcome arm never fetches such a bead, and a green marker resting on such a bead alone resolves only through an APPROVED GitHub review. The sanctioned writers (`signoff.sh` close, `review-outcome.sh back-lane`) record only `recorded` or `superseded`, so a clean store has no findings — it stays a forward regression detector. The marker arm is removed once the last marker consumer reads `lane-state.sh`. Moving the stamp out of `template-fragments/polecat-non-impl-done.template.md` into the pass that observes the review is tk-eh6xhf, and this check does not replace it. |
| **I8** | Every step bead reaches a terminal state: no offerable step under a closed root, no frontier stalled past its bound. A step under a closed root is offerable when its own status is open and every blocking dependency has closed; one parked at `status=blocked`, or still waiting on a live blocker, is inert residue and reported as a note, because no pool can hand it out. | `doctor/check-step-terminal` |
| **I9** | A molecule executes the formula text that is current when it runs. | `doctor/check-pour-text-current` (tk-5w3boh): a checkout lagging past the reconciler's self-heal window, an unfetched remote-tracking ref (the fail-open case, where the naive behind-count reads 0), and a live molecule poured before its formula last changed. Detection, not prevention — step descriptions still freeze at pour while the rig checkout advances on a 15-minute cooldown. |
| **I10** | Every pack order fires within its declared interval. | `doctor/check-cadence-live` |
| **I11** | Every step a pool is meant to run is being run: a claimed step is held by a running session that is still producing output, and an offered step has been claimed at all. | `doctor/check-claim-advancing` (tk-beecuu, tk-08i70x). Claimed: reported when nothing can be advancing it — no assignee, an assignee naming no session, a holder that is not running, or a holder whose `last_active` is past the bound. Unclaimed: an open step `bd ready` is offering, routed, with no assignee and no `gc.claimed_at` ever stamped, is reported only when the agent its route names has a running session holding nothing; a suspended pool, a pool with `max` 0, a pool scaled to zero, and a pool whose every session is busy are all notes, because a queue behind them is backpressure rather than starvation. Held on purpose: a non-empty `gc.takeaway` or `hold_reason`, on the step or on the root `gc.root_bead_id` names, takes a step out of both arms as a note whose remedy is `status=blocked` — releasing a held step to `open` hands it to the pool its route still names, which is what the hold exists to prevent. Holder-clocked, so it is silent for a session that is genuinely working however long the step takes. I8 is the complement: bead-clocked, holder-blind, and scoped to open steps at 48h. |
| **I12** | A bead's kind is `metadata.task_kind`, and no reader decides a kind from a label ([what kind of bead this is](#what-kind-of-bead-this-is)). Where a reader narrows a listing with `-l <kind>` it re-filters on `task_kind`, and every writer of that kind sets the label — a narrowing on a label some writer omits returns a quietly short answer. | **UNCHECKED** (tk-0i90x5). The reader half is held by construction and by test: every kind branch in the pack reads `task_kind`, and `learning-recurrence.test.sh` pins the one script that narrows by label against a bead carrying the label without the kind. The writer half — for each kind a reader narrows on, no live bead carries the `task_kind` without the label — is the check that does not exist; only `observation` is narrowed on by a reader today, and it is clean at filing, so the check would ship as a forward regression detector. |
| **I13** | Every started workflow root is still advancing or reachable: an in_progress `gc.kind=workflow` root whose owning session is gone and whose work has not landed does not sit behind an executable frontier that is unclaimable — unrouted AND unowned — which no pool can be offered and no orphan recovery reaches. | `doctor/check-root-advancing` (tk-d12vam): a graph.v2 molecule runs its continuation-group steps inline in one pool session, and those steps carry no owner and no route by construction, so a drain landing mid-molecule strands them past both recovery paths — the witness's orphan recovery keys on an assignee, and no route means no pool is offered them. Reported STRANDED (error) only when all four hold, each a distinct healthy shape it must not report: SILENT (root or any member, a close included, untouched past the bound — default 120m, `GC_DOCTOR_ROOT_STALL_MINUTES`); UNHELD (no live session behind the root's `gc.session_name` or any member's assignee, `gc.session_id` or `gc.session_name` — the affinity slot a restart reuses counts, so a live slot exempts); STARTED (at least one step has closed, so it moved then stopped, AND its input convoy is still open, since a convoy closes when its one work bead lands); UNCLAIMABLE (a non-empty executable frontier — the `bd ready` members minus the inert `workflow`/`scope`/`spec` topology kinds poured alongside steps — every member unassigned AND carrying neither `gc.routed_to` nor `gc.execution_routed_to`, so the execution route a recovery fix stamps reads as reachable). A non-empty `gc.takeaway` or `hold_reason` on the root or a member is a note. It is the root-level complement to I8 (closed roots) and I11 (claimed or routed steps), neither of which fires here. Fails toward silence: an unread roster declines the run, and an unread store, convoy or closed-step listing leaves that unit unjudged rather than flagged. |
| **I14** | A refinery whose queue holds work is cycling its patrol: once a bead has waited in its find-work queue past the bound, a `mol-refinery-patrol` wisp assigned to that refinery was written within the bound. | `doctor/check-refinery-patrol-live`: the agent half of the refinery, where I10 asserts the cadence half. Each patrol iteration takes one bead from the queue and pours its successor wisp before it burns itself, so a refinery working a queue renews its wisp once per bead. A refinery that stops cycling halts intake: no handoff in its queue is gated or landed, and no handed-back rework closes. The queue is the set find-work selects from: open, assigned to the refinery, carrying `metadata.branch`, not an epic, and with no `merge_result`. Reported STALLED (error) only when both halves hold, because each alone is a healthy shape. An empty queue ends the turn and leaves the wisp resting, so an old wisp alone is an idle refinery. A queue whose oldest bead is younger than the bound (default 60m, `GC_DOCTOR_REFINERY_PATROL_STALL_MINUTES`) holds work the refinery has not yet had the bound to take. Waits are aged by `updated_at`, which any later write resets, so the check errs toward silence. A suspended refinery or rig is a note, and an unread roster, queue or wisp listing warns. |

Further checks guard structure that is not an anchor invariant:
`doctor/check-config-bound` (every prompt, overlay, and fragment the pack names
resolves in the composed config), `doctor/check-seed-audit-current`
(generated-artifact freshness; warn-only when absent),
`doctor/check-recycle-capable` (cycle-recycle can fire at all: a Stop event
reaches the hook with its stdin intact, the hook's own measurement reads the
context size a transcript carries, and no refinery's git-op defer guard has
been latched past a bound), `doctor/check-cycle-recycle-hook` (the cycle-recycle
Stop hook and its no-consent doctrine name the same roles: every agent carrying
`overlay_dir = "overlays/cycle-recycle"` injects the `heartbeat-no-consent-ui`
fragment and every agent injecting it carries the overlay, so no role recycles
with nothing telling it not to prompt and none holds that doctrine while the hook
never recycles it; static, reads `pack.toml` and the resolved agent prompts),
`doctor/check-wisp-cascade-intact` (every bead
store's schema enforces the wisp auxiliary cascade — the constraint both
removes a deleted wisp's auxiliary rows on the bulk delete path and refuses a
write naming a wisp that does not exist, so a store without it accumulates
rows no wisp reaches and reports nothing), and `doctor/check-session-store-scope` (a live
agent's store environment names its own scope: the running pane process is read
for the store keys, which must agree with the rig in the session's own
identity, and the session environment is read for the warm-respawn half, where
`respawn-pane` takes no env argument and a store key the tmux server holds
globally reaches the next process unless the session marks it removed), and
`doctor/check-blocked-work-armed` (the complement to `check-wait-is-an-edge`: a
blocked, unassigned, plainly-work bead — an allowlisted work issue_type, not a
review/step/workflow/demand bead or a merge anchor — must carry a dispatch path,
`gc.routed_to` or a `gc.dispatch_when_ready` arm, or it strands when its blocker
closes and no pool is offered it; a bead a live molecule drives is exempt on a
liveness check, warn-only), and `doctor/check-visit-outcome-recorded` (a CLOSED
visit records the outcome it closed on: the board projects `gc.outcome` onto a
finished sitting's OUTCOME, so a visit closed with none is a sitting the board
cannot report and a correct dedup close reads identical to a dropped need;
warn-only while the legacy backlog stands), and `doctor/check-armed-dispatch-owed`
(the complement to `check-cadence-live`: a bead armed with `gc.dispatch_when_ready`
whose own `blocks` edges have all closed is slung by the deferred-dispatch reconcile
order within its cadence, so one that has stayed armed and open past that window — or
one armed at a non-open status `bd ready` never answers — is a dispatch silently not
firing; the is_blocked flag cascades down parent-child edges, so such an arm appears in
`bd blocked` under an ancestor and `check-blocked-work-armed` cannot see it; warn-only),
and `doctor/check-feedback-routing-owed` (the complement to the merge cadence's
feedback arm: a cheap pre-merge arm records a PR's review posture on the anchor and
a separate arm routes the feedback under it, so an OPEN anchor whose `pr_posture` is
`commented`/`changes_requested` with no `pr_comment_disposition` past the owed
window is operator feedback that reads as consumed while nothing has routed it; a
`pr_unengaged_threads` marker at the same head is a tracked hold and exempt;
warn-only), and `doctor/check-hq-marooned-work` (no rig-workable bead sits
unclaimed in the HQ (city / lx) store: a city-scoped role running with GC_RIG
unset files a bare `bd create` into the HQ store, which no pool reads, so an
open unassigned task/bug/defect there — unrouted or routed to a pool — is
marooned by construction; the operator-queue decisions routed to human, daily
digests, and doctor and tech-debt advisories that legitimately live there are
exempt).
Another non-invariant check, `doctor/check-demo-toolchain`, reports readiness
rather than structure: whether the demo:capture toolchain — Node, a Chromium
build, ffmpeg, and `OPENAI_API_KEY` — is resolvable, warn-only, so a demo
session learns before it captures whether the clip will narrate or degrade to a
silent, captioned one.
That is the whole set: every check asserts a live structural property or reports
toolchain readiness, and none greps the source for a past fix.

### I1 in full: the hold, the demand, and the shape law

The rule is three sentences:

> A bead is either ready, and therefore moving, or blocked on a named bead by
> an edge. There is no parked state. What a person owes is itself a bead, and
> closing it makes the dependent work ready.

**The hold** is a `blocks` edge from the waiting bead to an open bead in the
same store. Closing the blocker recomputes `is_blocked`, and the bead re-enters
`bd ready` and the pool's Tier-3 offer on the next read, with nothing to
remember to clear. Two limits are load-bearing. The blocker must be in the same
store. A `bd dep add` naming a bead in another rig's store returns `✓ Added
dependency` and exit 0, and holds nothing. `bd dep list --json` omits the row,
so every consumer reading stdout sees no wait and the bead stays ready; a
warning may still be printed on stderr, which is not the channel anything
reads. A wait on work in another rig is filed as a demand bead in the waiting
bead's own store, naming the foreign bead in its body. And the status stays `open`:
setting `status=blocked` by hand does not converge, because when the blocker
closes the stored status is still `blocked`.

**The demand** is that what a person owes is a bead, and the dependent work
blocks on it. A ruling only the operator can give is `issue_type=decision`; a
task only a named human can perform is a bead assigned to them; a question that
needs a conversation is the visit `escalate.sh` files. Filing the demand
without wiring the edge is the common failure, and a demand that gates nothing
is a note.

**The shape law** is that a bead which will ever carry a `blocks` edge must
have no `parent-child` children. Containers do not block; blockers do not
parent.

The reason is what `parent-child` means. It is decomposition: the child is part
of the parent's work, so the parent's blocked state cascades down to it. That
cascade is the correct reading of containment and is not a defect to route
around. It does damage only where the edge has been used for something that is
not decomposition, and whether routed work is that case depends on what the work
is. Work `W` a sitting hands out on subject `S` is a dependency by default: `S`
is waiting for it and does not contain it, so `W` is not a part of `S`. Filing
that `W` as a child of `S` would state a containment that is not true, and the
stranding would follow from the false statement rather than from the cascade;
filed as the graph is, `W` sits beside `S` and `S` blocks on `W`, which reads
correctly and keeps `W` claimable. The exception is work that genuinely
decomposes an epic subject — a story or task that is part of the epic. That `W`
is a member, a `parent-child` child, and it carries no `blocks` edge back to the
subject: the completion-wait is implicit in containment, and beads refuses a
parent→descendant `blocks` edge in any case. "The subject is an epic" is the
indicator that tells the two apart, and the shape law decides the mechanism
either way — a dependency sibling carries the `blocks` edge, a member child
never does (`specs/tk-xgj2ko/membership-mechanics.md`). beads enforces the
sharpest case directly, refusing an edge that would make a parent wait on its
own descendant. Where a container is wanted for roll-up, it is a bead that never
blocks.

Two boundaries. A conclusion is prose, stored once and never cleared, and it
does not become a wait by being written down; that seam is
[lifecycle-composition.md](lifecycle-composition.md). Which query term each
mechanism falsifies is [gascity-routing-model.md](gascity-routing-model.md),
which also carries the one dispatch path that reads no edges at all. `gc sling
--on <formula>` pours a workflow root carrying none of the work bead's
dependencies, so a blocked bead dispatched that way is held by nothing. On that
path the pending dispatch is recorded with `deferred-dispatch.sh arm` instead.

I1 is PARTIAL because no pass ages a demand. `check-wait-is-an-edge` asserts
the hold half, so a live bead whose only hold is a marker is a finding — unless
the bead is itself the terminal end of the wait, a demand others block on, which
carries the headline but has no forward edge to file and is exempt
(`terminal_wait_key`). What
nothing catches is a demand that is correctly edged and then owed for a month:
`liveness-sweep.sh` classifies over `bd ready`, so an edge-blocked bead is
outside its funnel. Until that lands, converting a hold to an edge makes it
quieter than the prose it replaced, not louder.

The census of every mechanism the pack had accreted, the measurements behind
each judgment, and the migration are `specs/tk-s4fg87/`.

---

## 4. Where each component sits

Design rule 1 of `specs/2026-08-rewrite/plan.md` holds that every component
belongs to one of six workflows (work, review, merge, visit, feedback, patrol)
or is a declared shared primitive. Below is that assignment for the tree as it
stands: every order, formula, service, and `assets/scripts` entry a running
city executes, with nothing unplaced and no row carrying any other value.

**What the index does not place.** Three exclusions, each mechanical:

- `*.test.sh` and the fixture library they source,
  `assets/scripts/test-harness.sh`. Test code is run by a developer, never by
  a city: no order, formula, or `test_command` invokes it.
- `doctor/check-*`. §3 places each check against the invariant it asserts.
- `tools/`. The command surface a human drives, including the
  `gc-proactive.sh` entry point that `gc-helm.sh` and `gc-visit-open.sh` shell
  out to on a human's action.

**The placement rule.** A component belongs to the workflow whose product it
advances, not the one whose name it carries. `mol-refinery-patrol` is merge
because what it produces is merge decisions. `gate-ensure.sh` is review even
though it runs as arm 6 of the merge cadence, because what it produces is a
raisable check and a routed review bead. Patrol is the workflow whose product
is a fleet that can still run the other five.

**Shared primitive** means more than one workflow calls it for the same
reason. A component only one workflow calls belongs to that workflow, however
general it looks.

The table is maintained by hand. A doctor check asserting the property needs a
machine-readable component list, which does not exist yet; this index is its
prerequisite, and the four exclusions above are what such a check encodes.

| Component | Workflow | Why it sits there |
|---|---|---|
| `formulas/mol-polecat-work.toml` | work | The work lifecycle: claim, worktree, implement, push, hand to the refinery. |
| `orders/deferred-dispatch.toml` | work | Routes work whose blockers have closed. |
| `assets/scripts/deferred-dispatch.sh` | work | The pass that order runs: a pending dispatch is a fact about the work, so it lives on the work bead. |
| `formulas/mol-review.toml` | review | The review method: claim, pin, judge, one `signoff.sh` verdict, drain. |
| `assets/scripts/gate-ensure.sh` | review | Makes every declared check raisable and routes the review bead. Runs as arm 6 of the merge cadence. |
| `assets/scripts/review-dispatch-body.sh` | review | Emits the dispatch note a review bead carries. |
| `assets/scripts/signoff.sh` | review | The single writer of check verdicts (I7). |
| `assets/scripts/review-workspace.sh` | review | A review's directory on disk, named for its review bead: makes the worktree the review tests in, removes the directory at the verdict step, and, as the review-workspace-reap order's pass, removes the directories of reviews that closed some other way. |
| `assets/scripts/finding.sh` | review | The finding-bead primitive: files a review objection as a bead with a rebase-stable `finding.key`, rules its disposition (must-fix `blocks` the anchor; deferred files a claimable follow-up that the anchor `blocks` and that is `discovered-from` the finding, then closes; declined closes; needs-you files a visit and stays open), wires the fix unit's two `blocks` edges, and reads whether a must-fix finding is open. |
| `assets/scripts/lane-state.sh` | review | Derives a lane's `green` from the review-outcome graph — a closed approve-verdict review bead, non-superseded — so every check reader agrees without a stored `check.<lane>` marker. |
| `formulas/mol-validate.toml` | review | The validator method: one pass per review batch that rules each finding's disposition (must-fix, deferred, declined, or needs-you — decisions 1 and 2) and whether a fresh whole-diff review is warranted (decision 3), so convergence is judged rather than counted. The `{{defer_policy}}` variable carries the fix-now-versus-defer threshold. It writes no `check.<lane>` marker. A ruling that a fresh whole-diff review is warranted also runs `approval-withdraw.sh`, whose note is the one write the anchor takes from the pass. |
| `assets/scripts/validate-dispatch-body.sh` | review | Emits the dispatch note a validation-pass bead carries. |
| `assets/scripts/review-outcome.sh` | review | The write side of a lane's approve outcome, the bead lane-state.sh reads: `back-lane` files the closed approve outcome that greens a lane, `supersede-lane` stamps it superseded to return the lane to `unreviewed`. |
| `orders/refinery-reconcile.toml` | merge | The merge cadence: one pass per rig, every 60s. |
| `orders/reconcile-rig-checkouts.toml` | merge | Landed is not live until the `rigs/*` checkout syncs; this fast-forwards it. |
| `formulas/mol-refinery-patrol.toml` | merge | The cadence's judgment half. The cadence itself is the order. |
| `assets/scripts/refinery-reconcile.sh` | merge | Drives one cadence pass over this rig's queue. |
| `assets/scripts/pace-lib.sh` | merge | The visit order and time budget of a cadence arm that walks the gating set: visit in id order after the anchor the last pass finished, wrapping, and start no new anchor past the arm's deadline. It also keeps each walk's seen marks, what it saw of each anchor at its last visit, so an arm can put first the anchors that changed since. The paced arms source it, and `gctk merge` carries the same rotation. |
| `assets/scripts/merge.sh` | merge | Arm 2: the single writer of merged truth. |
| `assets/scripts/review-verdict.sh` | merge | The approval rule as one jq definition: each outside account's latest approving or change-requesting review decides. `merge.sh` lands on it, `pr-facts.sh` brings only an approved PR's branch current by it, and `bring-current-guard.sh` reads the approvals a judgment-laden bring-current dismisses. |
| `assets/scripts/bring-current-guard.sh` | merge | Keeps an approval from covering code it never saw. Run at a merge-in child's handoff, it classifies the bring-current as mechanical, which leaves the approval standing, or as judgment, which files a visit on the anchor and dismisses the approval. |
| `assets/scripts/approval-withdraw.sh` | merge | Keeps an approval from covering a change the validator ruled needs a fresh whole-diff review. `mol-validate` runs it on that ruling: it notes the judgment on the anchor, records the reviews on the validation pass, and dismisses every outside approval not yet dismissed, which it reads from `review-verdict.sh`. |
| `assets/scripts/record-failure-cap.sh` | merge | The memory the record arms lack: counts consecutive failures to record a merged PR on the anchor, and files one visit past the cap. Called by `merge.sh` and `pr-facts.sh`, which spend one budget between them. |
| `assets/scripts/pre-open-rebase.sh` | merge | Arm 5: asks git whether a pre-open anchor's branch still merges, and dispatches the rebase child no PR-fact arm can. No merge authority. |
| `assets/scripts/pr-open.sh` | merge | Arm 3: `pre_open_gate` to `pull_request`. |
| `assets/scripts/pr-facts.sh` | merge | Arm 7: records external PR facts. No merge authority. |
| `assets/scripts/convoy-graduate.sh` | merge | Arm 8: graduates a complete owned integration convoy. |
| `assets/scripts/review-sweep.sh` | merge | Arm 9: closes a dispatched review with no reviewable surface left. No merge authority. |
| `assets/scripts/scaffolding-sweep.sh` | merge | Arm 10: retires a disposed anchor's machine review scaffolding (`task_kind=validation\|finding\|rework`) so it can finalize; leaves reviews, human visits, and the anchor itself alone. No merge authority. |
| `assets/scripts/duplicate-sweep.sh` | merge | Arm 11: disposes of verified no-op duplicate dispatches, and of never-dispatched rework twins whose same-review sibling landed, via `bead-rehome.sh`. No merge authority. |
| `assets/scripts/pr-stack.sh` | merge | Arm 12: keeps each open PR current with its anchor — the branch-beads section, the `pr-summary` region a rework moved past, and the title composed from the anchor's. Writes only PR bodies and titles. No merge authority. |
| `assets/scripts/reconcile-rig-checkouts.sh` | merge | The pass that order runs. Fast-forward only; divergence escalates. |
| `formulas/mol-visit.toml` | visit | Files one visit on a subject bead, parked on the helm board (`gc.routed_to=human`) for an operator to engage. |
| `formulas/mol-first-reaction.toml` | visit | One cheap reaction slung at a bead from the board picker or `tools/gc-proactive.sh`, ending in one of five dispositions: route the bead to a pool, recommend an action for the operator to trigger, hold it on an edge, route it to a validating closer, or put it to the operator as a human gate for their judgment. It sits in visit because its product is a bead the human no longer has to triage. |
| `assets/scripts/first-reaction-dispose.sh` | visit | Performs that disposition and records which one and why. The only writer of `gc.first_reaction*`. It never closes a bead: the close disposition slings the bead to a validating closer. |
| `formulas/mol-validate-close.toml` | visit | The validating closer a `close` disposition routes to: a capable pool re-checks the no-work conclusion against live state and closes the subject (`gc.work_outcome=no-op`) when it holds, or files a visit when it does not. The one bead-closer outside the refinery, gated on its own confident check. |
| `orders/helm-build.toml` | visit | Keeps the served board binary current with `services/helm`. |
| `services/helm` | visit | The board. Derives every row per render from the ledger. |
| `assets/scripts/gc-helm.sh` | visit | The board's write verbs: takeaway, open, engage, react, dismiss, demand. |
| `assets/scripts/gc-helm-build.sh` | visit | Builds `helm-svc`, out of band from the launcher. |
| `assets/scripts/gc-helm-svc.sh` | visit | The `proxy_process` launcher for the board backend. |
| `assets/scripts/gc-visit-open.sh` | visit | Operator-origin visit intake in one command. |
| `orders/converse-reap.toml` | visit | Fires the converse sitting reaper every five minutes, city-wide. |
| `assets/scripts/converse-reap.sh` | visit | The pass that order runs: closes each unattached converse session whose visit reads closed or gone. A sign-off or a `gc-helm dismiss` closes the visit and leaves the manual session running, so this pass is the teardown both endings rely on ([gascity-human-engagement.md](gascity-human-engagement.md)). It leaves an attached session alone, because attachment is the only signal the pack has that someone is at the pane. It sits in visit, not in patrol with the other reapers, because it completes a visit's ending the way `reconcile-rig-checkouts` completes a merge's effect. |
| `assets/scripts/converse-claim.sh` | visit | Claims one turn for a continuation group, and puts back a turn belonging to another. |
| `assets/scripts/bead-rehome.sh` | visit | Closes a bead with a legible successor pointer. Callers are converse dispositions, operator re-homes, and `duplicate-sweep.sh`. |
| `assets/scripts/pr-dispose.sh` | visit | Records a deliberate supersede/not-planned PR-close disposition on the open anchor and closes the PR, so `pr-facts.sh` consummates it through `bead-rehome.sh` instead of filing a rework-or-close visit. The PR side of the same disposition doctrine, with the same callers: converse dispositions and operator close-outs. |
| `assets/scripts/gc-terminal-attach.sh` | visit | The city web terminal's attach target. |
| `assets/scripts/tmux-visit-prompt.sh` | visit | `prefix + a`: type a message, get a durable conversation. |
| `assets/scripts/tmux-dismiss-sitting.sh` | visit | `prefix + X`: dismiss the converse sitting in view, after a confirm. |
| `assets/scripts/tmux-bindings.sh` | visit | Installs the keybindings that reach the surfaces above. |
| `assets/scripts/tmux-pick-helm.sh` | visit | The board picker. |
| `assets/scripts/tmux-pick-session.sh` | visit | The session picker. |
| `assets/scripts/tmux-keeper-toggle.sh` | visit | Pins or unpins the keeper in the session picker. |
| `assets/scripts/tmux-status-line-override.sh` | visit | Sets the gc-toolkit status bar. |
| `assets/scripts/gc-toolkit-status-line.sh` | visit | Renders what that status bar shows. |
| `assets/scripts/work-outcome.sh` | visit | The one `gc.work_outcome=no-op` stamp a visit gets before it closes, for the work-record gate `gc bd close` runs. Every visit closer sources it: `visit-close.sh`, the `gc-helm.sh` dismiss verb, `bead-rehome.sh` and `converse-claim.sh`. |
| `orders/feedback-miner.toml` | feedback | Fires the sweep of recently merged PR review threads. |
| `orders/feedback-distiller.toml` | feedback | The daily heartbeat that judges pending observations. |
| `formulas/mol-feedback-miner.toml` | feedback | Cold capture: records each corrective-feedback hit as one observation bead. |
| `formulas/mol-feedback-distiller.toml` | feedback | Turns pending observations into reviewed prompt-update proposals. |
| `formulas/mol-witness-patrol.toml` | patrol | Mail triage, orphan recovery, and escalation for one rig. |
| `formulas/mol-deacon-patrol.toml` | patrol | City infrastructure health: Dolt, orphan processes, doctor sweep. |
| `formulas/mol-dog-shutdown-dance.toml` | patrol | Due process for one wedged session, against a claimed warrant. |
| `orders/boot-health.toml` | patrol | Fires the wedged-deacon detector. |
| `orders/convoy-check.toml` | patrol | Fires the convoy sweep hourly, city-wide: closes the convoys the bead-close autoclose missed. |
| `orders/liveness-sweep.toml` | patrol | Condition-triggered: runs the sweep once the precheck proves a delta. |
| `orders/pin-keepalive.toml` | patrol | Condition-triggered, city-scoped: pins standing conversational named sessions (mechanik today) so config-drift restart keeps deferring on them. |
| `orders/quota-park-nudge.toml` | patrol | Fires the quota-park nudge. |
| `orders/scratch-reap.toml` | patrol | Fires the scratch reaper hourly, city-wide. |
| `orders/build-scratch-reap.toml` | patrol | Fires the build/test scratch reaper hourly, city-wide. |
| `orders/worktree-reap.toml` | patrol | Fires the worktree reaper hourly, city-wide. |
| `orders/review-workspace-reap.toml` | patrol | Fires the review-workspace reaper hourly, city-wide. |
| `orders/notification-wisp-reap.toml` | patrol | Fires the notification-wisp reaper hourly, city-wide. |
| `orders/dolt-reclaim.toml` | patrol | Fires the Dolt reclaim pass daily, city-wide: runs `gc dolt compact --gc-only` on each store whose noms size is over the per-database line. |
| `orders/pool-slot-reap.toml` | patrol | Fires the pool-slot reaper every five minutes, city-wide. |
| `assets/scripts/boot-health.sh` | patrol | Mechanical reads: the patrol-wisp ledger, and the deacon's pane only when the wisp is not fresh. Report-only by design ([authority-map.md](authority-map.md)). |
| `assets/scripts/dance-probe.sh` | patrol | The mechanical half of one interrogation round; the formula judges the verdict. |
| `assets/scripts/doctor-sweep.sh` | patrol | Runs `gc doctor` detached, once per interval with one capped retry after a failed or exceeded run, in a scope that outlives both the harness ceiling a foreground call cannot exceed and the patrol session's own teardown, turns a sweep that never finishes into a state carrying its elapsed time and the check it stopped in, and reports a sweep that finished more than an interval before it was collected as stale, never as current findings. |
| `assets/scripts/gc-deacon-ledger.sh` | patrol | The deacon's rolling incident ledger: one open `deacon-ledger` bead, one comment per non-routine action, rotated so it stays skimmable. Reconstructs a shift for an operator or a recycled deacon without a transcript. |
| `assets/scripts/liveness-recheck.sh` | patrol | Re-validates a sweep visit's census at claim time. |
| `assets/scripts/liveness-sweep-precheck.sh` | patrol | The order's condition check: proves a pass has something to say before one runs. |
| `assets/scripts/liveness-sweep.sh` | patrol | Classifies every open bead; unnamed waits batch into one triage visit. An anchor whose gating PR has stopped moving is escalated on its own, deduped by a stamp on the anchor. |
| `assets/scripts/pin-keepalive-precheck.sh` | patrol | The pin-keepalive order's condition check: runs `pin-keepalive.sh --check`, read-only. |
| `assets/scripts/pin-keepalive.sh` | patrol | The pass, and (in `--check` mode) its own condition gate on one predicate: pins every standing conversational named session (`configured_named_session`, provider `claude`) that is not already pinned. |
| `assets/scripts/quota-park-nudge.sh` | patrol | Resumes a session parked behind a provider quota banner. |
| `assets/scripts/scratch-reap.sh` | patrol | Removes the scratch of sessions that have ended, and of sessions inactive past the horizon, so the per-uid tmpfs quota has a floor the pack controls. |
| `assets/scripts/build-scratch-reap.sh` | patrol | Removes build and test scratch (Go toolchain trees, gc.test per-run trees, templated tool temp) that a killed or crashed run left behind, gated on no live holder and — for pid-named trees — a dead pid, so the per-uid tmpfs quota has a floor the pack controls. |
| `assets/scripts/worktree-reap.sh` | patrol | Removes the worktrees of closed work beads, each pinned by an archive tag first, so a landed bead's checkout stops being a permanent floor under the disk. |
| `assets/scripts/notification-wisp-reap.sh` | patrol | Closes a city-store "Human gate awaiting you" notice once its gate is no longer open, and collapses duplicate "ESCALATION" copies to one open notice — the notification wisps core mails and never retires. |
| `assets/scripts/dolt-reclaim.sh` | patrol | Measures each managed Dolt store's noms size and runs `gc dolt compact --gc-only --only-db <db>` on the ones over the per-database line, so a store size-bloated below the flatten commit-threshold is reclaimed on a cadence. Never runs a bare flatten; defers while the data plane is degraded. |
| `assets/scripts/pool-slot-reap.sh` | patrol | Closes an asleep pool session bead that holds a slot with no runtime and no work once it has stayed asleep past a grace window, and records each close in the incident ledger. Core frees a pool slot only for its listed sleep reasons, and `killed` is not one of them, so without this pass a killed pool session that holds no work keeps its pool one short of the cap it reports. |
| `assets/scripts/escalate.sh` | shared primitive | One open visit per situation key — the door to a human, for what only a human can answer. The window is one OPEN visit, so a recurring observation belongs in `patrol-finding.sh` instead. |
| `assets/scripts/patrol-finding.sh` | shared primitive | One durable bead per patrol finding, deduped on `finding.key`. A proactive first reaction disposes it: routed to a pool, held on an edge, or put to the operator as a human gate. |
| `assets/scripts/gc-bd-watch.sh` | shared primitive | Bead-state changes as JSONL, for any agent waiting on work it dispatched. |
| `assets/scripts/lifecycle.sh` | shared primitive | The only writer of a lifecycle transition. |
| `assets/scripts/render-seed-audit.sh` | shared primitive | Renders the text each agent actually receives. `doctor/check-seed-audit-current` reports its freshness in a checkout; its `--check-merge` mode is what `merge.sh` gates a landing on. |
| `assets/scripts/step-close.sh` | shared primitive | A graph.v2 step advances only by closing its own bead, and every formula's steps end here. |
| `assets/scripts/worktree-setup.sh` | shared primitive | Agent `pre_start` worktree creation, for the polecat, polecat-codex, refinery, and proactive templates. |
| `assets/scripts/standing-kinds.sh` | shared primitive | The one definition of the standing kinds: the `task_kind` values of a record that is open, unrouted and unassigned by design and never closes. The liveness sweep and its re-check (patrol) source it, and so does the proactive scan (visit), each to tell a standing record from work or input. The doctor checks `check-blocked-work-armed` and `check-hq-marooned-work` read it the same way. |
| `assets/scripts/dispatch-path.sh` | shared primitive | The one definition of a dispatch path: a `gc.routed_to` route or a `gc.dispatch_when_ready` arm. The proactive scan (visit) sources it to leave alone a bead whose dispatch is already decided. Patrol's doctor sweep runs `check-blocked-work-armed` and `check-step-terminal`, which source it to find work that no pass will dispatch. |
| `assets/scripts/pr-post.sh` | shared primitive | The one writer of the city's PR posts, each carrying the provenance mark, and the owner of the definition that tells the city's own post from feedback. Merge (`pr-open.sh`, `pr-facts.sh`), review (`signoff.sh`) and visit (`pr-visit-comment.sh`, `pr-dispose.sh`, converse sittings) post through it, and `pr-facts.sh` and `signoff.sh` read its definition. |
| `assets/scripts/icu4c-cgo.sh` | shared primitive | The cgo flags every compile of `services/helm` needs on macOS, where Homebrew keeps icu4c off the default search path and Dolt's go-icu-regex needs its headers. Visit sources it for the helm-svc build (`gc-helm-build.sh`), and merge sources it for the go vet in `tools/lint.sh`, the refinery formula's default lint command. |

### The placements worth arguing about

- **The operator surface is visit.** The board, the tmux bindings and pickers,
  the status line, and the web terminal exist so a human can reach the queue
  that subjects and visits hold. `services/helm` and `orders/helm-build.toml`
  sit there for the same reason: the board is the read half of human
  engagement, and the order exists only to keep it current.
- **`reconcile-rig-checkouts` is merge.** A directory-imported pack runs from
  the working tree, so a merged PR does not execute until the checkout syncs.
  The order completes a merge's effect. `doctor/check-pour-text-current` reads
  the same lag from the work side.
- **The dog pool is patrol.** A patrol detector files the warrant and
  `mol-dog-shutdown-dance` executes it. Detection and enforcement are one
  workflow, split across two roles because a kill needs due process
  ([authority-map.md](authority-map.md)).
- **`liveness-sweep` is patrol, not visit.** It replaced two patrol detectors,
  `detect-stalled-workflows.sh` and `detect-parked-dispositions.sh`, and it
  files a batch's unnamed waits as one `escalate.sh` visit. Producing a visit
  does not put a component in the visit workflow. The deacon and witness
  patrols reach a human by a longer road: `patrol-finding.sh` files the bead,
  and the first reaction on it decides whether a human is owed anything at
  all.

---

## 5. How to use this

- **Adding a component** — it must answer column 3 of §1, and it takes a row
  in §4 in the same PR unless it falls under one of §4's four exclusions. If
  it can do neither, it is a repair pass for a writer that should be fixed
  instead.
- **Adding a state** — declare it in `lifecycle/lifecycle.toml`, name its
  writer in [state-machine.md](state-machine.md)'s table, or it does not
  exist.
- **Adding a metadata key** — it is state. Register it in `lifecycle.toml`, or
  accept that nothing downstream can be proven exhaustive over it.
- **Adding an invariant** — name its check in the same PR.
- **Divergence** — there is no divergence section: the running system is
  generated from the declarations this model requires, so divergence is zero
  by construction. If you find the ledger disagreeing with this document, a
  check is missing a case; fix the check, not the prose.
