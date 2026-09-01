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
owns the diagram, the transition table, and the gate vocabulary. It does not
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
| **Anchor** | the single open bead that owns a PR and carries its gates | N claimants on one PR ⇒ the weakest check-set decides the merge |
| **Convoy** | tracked set with one landing target | no unit larger than a bead can land, and integration branches cannot graduate |
| **Formula + step bead** | a workflow materialised as beads | a crashed session resumes by reconstructing intent from prose |
| **Check-set + gate marker** | declared merge preconditions, each bound to a commit | merges depend on whoever remembers to look |
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

---

## 2. The lifecycle, as counts

The machine itself — states, transitions, writers, gates — is drawn once, in
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
- **One gate-verdict writer** — `signoff.sh`. Clearing a marker is a separate
  power from writing one: a clear withdraws evidence where a verdict asserts
  it, so no clearer can make a gate pass. Three components hold that power,
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
  commit, but the anchor-local authorization set — `check.*`, `merge_hold`,
  `pr_posture`, `merged_target` — does not move the head; the pre-merge
  re-read is what catches a mid-pass write to any of them.

---

## 3. Invariants

Propositions, each true or false, each with the check that catches it going
false. **UNCHECKED** means the check does not exist and is filed as a bead.

| # | Proposition | Check |
|---|---|---|
| **I1** | Every dependency is recorded in the bead graph — no wait lives only in prose or a metadata string. The shape it asserts is [I1 in full](#i1-in-full-the-hold-the-demand-and-the-shape-law) below. | `doctor/check-wait-is-an-edge` (tk-5r1a12): where a LIVE bead states a wait about ITSELF — a dependency-declaring metadata key, or `gc.takeaway`/`*_reason` prose naming a bead — a `blocks` edge must record it in one direction or the other, and a target that has already closed is reported apart as the terminal form. Live is every non-closed status, because claiming or parking a bead does not answer the wait it states. Only `blocks` counts: it is the one edge type that holds a bead out of `bd ready`, so a `tracks` or `parent-child` record leaves the wait as unanswerable as the string did. Free-form notes are out of scope by measurement, not omission: every live bead in this city whose notes carry wait language names a THIRD PARTY as the waiter, so reading them would report the graph as broken where it is correct. Takeaway waits are written as edges by `gc-helm.sh takeaway --waiting-on`, which warns when it could wire only the string; the liveness sweep re-derives stalled waits from the graph (`liveness-sweep.sh`); gate waits stay head-bound markers by design. |
| **I2** | The state space is closed: every `merge_result` value and status combo is declared in `lifecycle/lifecycle.toml`, and a bead in a declared detached state rests unheld and offered to no pool. | `doctor/check-state-space` |
| **I3** | Every routed bead is claimable: route AND assignee name a live target, routed work is in `bd ready` or in `bd blocked`, and rig-scoped orders are bound. | `doctor/check-routed-work-claimable` |
| **I4** | Every PR has exactly one owning anchor, and every gating anchor is open. | `doctor/check-one-anchor-per-pr` (structural); `merge.sh` also refuses on sight, fail-closed |
| **I5** | No bead is closed while the work it represents is unlanded: closed anchor ⇒ `merged` + `merged_sha`, or an explicit terminal state. | `doctor/check-closed-implies-landed` |
| **I6** | Every gating anchor declares a non-empty `check_set`, and every marker is well-formed `verb@oid`. | `doctor/check-gate-integrity` |
| **I7** | A gate verdict was written by the one audited writer, `signoff.sh` — narrowed from the old provenance question by making the writer singular. | `doctor/check-gate-integrity` (marker form); the single-writer property is held by construction: `signoff.sh` contains the only code that sets a `check.*` value. The two other components that touch the key ([authority-map.md](authority-map.md)) only clear it, which cannot forge a verdict. `doctor/check-gate-marker-provenance` (tk-iljtmq) carries the depth half: every green marker on an open gating anchor must name a commit some verdict covers. It resolves against a `task_kind=review` bead whose `anchor_bead`, `reviewed_oid` and `check_name` match the anchor, the marker's commit and the marker's gate, then, for that residue only, against an APPROVED GitHub review on the anchor's `pr_number` sitting at the same oid. It flagged 0 of the 20 in-scope anchors when it shipped, so it is a forward regression detector on a clean baseline. Moving the stamp out of `template-fragments/polecat-non-impl-done.template.md` into the pass that observes the review is tk-eh6xhf, and this check does not replace it. |
| **I8** | Every step bead reaches a terminal state: no open step under a closed root, no frontier stalled past its bound. | `doctor/check-step-terminal` |
| **I9** | A molecule executes the formula text that is current when it runs. | `doctor/check-pour-text-current` (tk-5w3boh): a checkout lagging past the reconciler's self-heal window, an unfetched remote-tracking ref (the fail-open case, where the naive behind-count reads 0), and a live molecule poured before its formula last changed. Detection, not prevention — step descriptions still freeze at pour while the rig checkout advances on a 15-minute cooldown. |
| **I10** | Every pack order fires within its declared interval. | `doctor/check-cadence-live` |
| **I11** | Every step a pool is meant to run is being run: a claimed step is held by a running session that is still producing output, and an offered step has been claimed at all. | `doctor/check-claim-advancing` (tk-beecuu, tk-08i70x). Claimed: reported when nothing can be advancing it — no assignee, an assignee naming no session, a holder that is not running, or a holder whose `last_active` is past the bound. Unclaimed: an open step `bd ready` is offering, routed, with no assignee and no `gc.claimed_at` ever stamped, is reported only when the agent its route names has a running session holding nothing; a suspended pool, a pool with `max` 0, a pool scaled to zero, and a pool whose every session is busy are all notes, because a queue behind them is backpressure rather than starvation. Holder-clocked, so it is silent for a session that is genuinely working however long the step takes. I8 is the complement: bead-clocked, holder-blind, and scoped to open steps at 48h. |
| **I12** | The field vocabulary is closed: every metadata key a live bead carries is one `lifecycle/lifecycle.toml` registers, no key sits one namespace prefix away from a registered one, every route names its rig, and a bead parked for a person records the question it waits on. | `doctor/check-wait-is-an-edge`, vocabulary arm: the registry is the only authority, so an absent or unparseable one reports that the arm could not run rather than judging keys against a vocabulary nothing declares. Keys inside the declared runtime namespace are out of scope rather than registered, being the Gas City binary's to declare on its own release cycle; the exception is a key that becomes a registered key once that prefix is added or removed, which is pack state written one prefix from its reader. Runtime-owned bead types are skipped whole. The registry grades the two backlogs still draining, unregistered keys and questionless parks, as warn or error. Route addresses are `doctor/check-routed-work-claimable`'s on open beads and this arm's shape check on the live statuses that scan does not read. |

Three further checks guard structure that is not an anchor invariant:
`doctor/check-config-bound` (every prompt, overlay, and fragment the pack names
resolves in the composed config), `doctor/check-seed-audit-current`
(generated-artifact freshness; warn-only when absent), and
`doctor/check-recycle-capable` (cycle-recycle can fire at all: the city name
resolves, the supervisor endpoint carries a numeric `input_tokens` for every
awake patrol agent, and no refinery's git-op defer guard has been latched past
a bound). That is the whole set: **14 checks, each asserting a live structural
property** — none greps the source for a past fix.

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
around. It only does damage where the edge has been used for something that is
not decomposition, and routed work is that case. Work `W` handed out by a
sitting on subject `S` is not a part of `S`; it is what `S` is waiting for.
Filing `W` as a child of `S` therefore states a containment that is not true,
and the stranding follows from the false statement rather than from the
cascade. Filed as the graph actually is, `W` sits beside `S` and `S` blocks on
`W`. That reads correctly, and `W` stays claimable. beads enforces the sharpest
case of this directly, refusing an edge that would make a parent wait on its
own descendant. Where a container is wanted for roll-up, it is a bead that
never blocks.

Two boundaries. A conclusion is prose, stored once and never cleared, and it
does not become a wait by being written down; that seam is
[lifecycle-composition.md](lifecycle-composition.md). Which query term each
mechanism falsifies is [gascity-routing-model.md](gascity-routing-model.md),
which also carries the one dispatch path that reads no edges at all. `gc sling
--on <formula>` pours a workflow root carrying none of the work bead's
dependencies, so a blocked bead dispatched that way is held by nothing. On that
path the pending dispatch is recorded with `deferred-dispatch.sh arm` instead.

I1 is PARTIAL for two reasons. `check-wait-is-an-edge` does not exist yet, and
no pass ages a demand: `liveness-sweep.sh` classifies over `bd ready`, so an
edge-blocked bead is outside its funnel and a demand owed for a month is
invisible. Until both land, converting a hold to an edge makes it quieter than
the prose it replaced, not louder.

The census of every mechanism the pack had accreted, the measurements behind
each judgment, and the migration are `specs/tk-s4fg87/`.

---

## 4. Where each component sits

Design rule 1 of `specs/2026-08-rewrite/plan.md` holds that every component
belongs to one of six workflows (work, review, merge, visit, feedback, patrol)
or is a declared shared primitive. Below is that assignment for the tree as it
stands: every order, formula, service, and `assets/scripts` entry a running
city executes, with nothing unplaced and no row carrying any other value.

**What the index does not place.** Four exclusions, each mechanical:

- `*.test.sh` and the fixture library they source,
  `assets/scripts/test-harness.sh`. Test code is run by a developer, never by
  a city: no order, formula, or `test_command` invokes it.
- `assets/scripts/cutover-2026-08.sh`. One-shot tooling that carries its own
  deletion condition in its header: it goes when
  `specs/2026-08-rewrite/cutover-runbook.md` goes.
- `doctor/check-*`. §3 places each check against the invariant it asserts.
- `tools/`. The command surface a human drives, including the
  `gc-proactive.sh` entry point that `gc-helm.sh` and `gc-visit-open.sh` shell
  out to on a human's action.

**The placement rule.** A component belongs to the workflow whose product it
advances, not the one whose name it carries. `mol-refinery-patrol` is merge
because what it produces is merge decisions. `gate-ensure.sh` is review even
though it runs as arm 1 of the merge cadence, because what it produces is a
raisable gate and a routed review bead. Patrol is the workflow whose product
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
| `assets/scripts/gate-ensure.sh` | review | Makes every declared gate raisable and routes the review bead. Runs as arm 1 of the merge cadence. |
| `assets/scripts/review-dispatch-body.sh` | review | Emits the dispatch note a review bead carries. |
| `assets/scripts/signoff.sh` | review | The single writer of gate verdicts (I7). |
| `orders/refinery-reconcile.toml` | merge | The merge cadence: one pass per rig, every 60s. |
| `orders/reconcile-rig-checkouts.toml` | merge | Landed is not live until the `rigs/*` checkout syncs; this fast-forwards it. |
| `formulas/mol-refinery-patrol.toml` | merge | The cadence's judgment half. The cadence itself is the order. |
| `assets/scripts/refinery-reconcile.sh` | merge | Drives one cadence pass over this rig's queue. |
| `assets/scripts/pr-open.sh` | merge | Arm 2: `pre_open_gate` to `pull_request`. |
| `assets/scripts/merge.sh` | merge | Arm 3: the single writer of merged truth. |
| `assets/scripts/pr-facts.sh` | merge | Arm 4: records external PR facts. No merge authority. |
| `assets/scripts/convoy-graduate.sh` | merge | Arm 5: graduates a complete owned integration convoy. |
| `assets/scripts/reconcile-rig-checkouts.sh` | merge | The pass that order runs. Fast-forward only; divergence escalates. |
| `formulas/mol-visit.toml` | visit | Files one visit on a subject bead, routed to the converse pool. |
| `formulas/mol-first-reaction.toml` | visit | One cheap reaction slung at a bead from the board picker or `tools/gc-proactive.sh`. What it produces is something a human reads, not a branch. |
| `orders/helm-build.toml` | visit | Keeps the served board binary current with `services/helm`. |
| `services/helm` | visit | The board. Derives every row per render from the ledger. |
| `assets/scripts/gc-helm.sh` | visit | The board's write verbs: takeaway, open, react. |
| `assets/scripts/gc-helm-build.sh` | visit | Builds `helm-svc`, out of band from the launcher. |
| `assets/scripts/gc-helm-svc.sh` | visit | The `proxy_process` launcher for the board backend. |
| `assets/scripts/gc-visit-open.sh` | visit | Operator-origin visit intake in one command. |
| `assets/scripts/converse-claim.sh` | visit | Claims one turn for a continuation group, and puts back a turn belonging to another. |
| `assets/scripts/bead-rehome.sh` | visit | Closes a bead with a legible successor pointer. Callers are converse dispositions and operator re-homes. |
| `assets/scripts/gc-terminal-attach.sh` | visit | The city web terminal's attach target. |
| `assets/scripts/tmux-visit-prompt.sh` | visit | `prefix + a`: type a message, get a durable conversation. |
| `assets/scripts/tmux-bindings.sh` | visit | Installs the keybindings that reach the surfaces above. |
| `assets/scripts/tmux-pick-helm.sh` | visit | The board picker. |
| `assets/scripts/tmux-pick-session.sh` | visit | The session picker. |
| `assets/scripts/tmux-keeper-toggle.sh` | visit | Pins or unpins the keeper in the session picker. |
| `assets/scripts/tmux-status-line-override.sh` | visit | Sets the gc-toolkit status bar. |
| `assets/scripts/gc-toolkit-status-line.sh` | visit | Renders what that status bar shows. |
| `orders/feedback-miner.toml` | feedback | Fires the sweep of recently merged PR review threads. |
| `orders/feedback-distiller.toml` | feedback | The daily heartbeat that judges pending observations. |
| `formulas/mol-feedback-miner.toml` | feedback | Cold capture: records each corrective-feedback hit as one observation bead. |
| `formulas/mol-feedback-distiller.toml` | feedback | Turns pending observations into reviewed prompt-update proposals. |
| `formulas/mol-witness-patrol.toml` | patrol | Mail triage, orphan recovery, and escalation for one rig. |
| `formulas/mol-deacon-patrol.toml` | patrol | City infrastructure health: Dolt, orphan processes, doctor sweep. |
| `formulas/mol-dog-shutdown-dance.toml` | patrol | Due process for one wedged session, against a claimed warrant. |
| `orders/boot-health.toml` | patrol | Fires the wedged-deacon detector. |
| `orders/liveness-sweep.toml` | patrol | Condition-triggered: runs the sweep once the precheck proves a delta. |
| `orders/quota-park-nudge.toml` | patrol | Fires the quota-park nudge. |
| `assets/scripts/boot-health.sh` | patrol | Three mechanical reads. Report-only by design ([authority-map.md](authority-map.md)). |
| `assets/scripts/dance-probe.sh` | patrol | The mechanical half of one interrogation round; the formula judges the verdict. |
| `assets/scripts/doctor-finding-gate.sh` | patrol | Re-asks doctor at close time, so a merge cannot silently read as a fix. Run by the deacon patrol's doctor sweep. |
| `assets/scripts/liveness-recheck.sh` | patrol | Re-validates a sweep visit's census at claim time. |
| `assets/scripts/liveness-sweep-precheck.sh` | patrol | The order's condition check: proves a pass has something to say before one runs. |
| `assets/scripts/liveness-sweep.sh` | patrol | Classifies every open bead; unnamed waits batch into one triage visit. |
| `assets/scripts/quota-park-nudge.sh` | patrol | Resumes a session parked behind a provider quota banner. |
| `assets/scripts/escalate.sh` | shared primitive | One open visit per situation key. Every workflow's door to a human. |
| `assets/scripts/gc-bd-watch.sh` | shared primitive | Bead-state changes as JSONL, for any agent waiting on work it dispatched. |
| `assets/scripts/lifecycle.sh` | shared primitive | The only writer of a lifecycle transition. |
| `assets/scripts/render-seed-audit.sh` | shared primitive | Renders the text each agent actually receives. `doctor/check-seed-audit-current` reports its freshness in a checkout; its `--check-merge` mode is what `merge.sh` gates a landing on. |
| `assets/scripts/step-close.sh` | shared primitive | A graph.v2 step advances only by closing its own bead, and every formula's steps end here. |
| `assets/scripts/worktree-setup.sh` | shared primitive | Agent `pre_start` worktree creation, for the polecat, polecat-codex, refinery, and proactive templates. |

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
  files its finding through `escalate.sh` the way every patrol does. Producing
  a visit does not put a component in the visit workflow.

---

## 5. How to use this

- **Adding a component** — it must answer column 3 of §1, and it takes a row
  in §4 in the same PR unless it falls under one of §4's four exclusions. If
  it can do neither, it is a repair pass for a writer that should be fixed
  instead.
- **Adding a state** — declare it in `lifecycle/lifecycle.toml`, name its
  writer in [state-machine.md](state-machine.md)'s table, or it does not
  exist.
- **Adding a metadata key** — it is state. Register it in `lifecycle.toml`
  beside the writer that sets it, and define what reads it, what its absence
  means, and how it is cleared. Those three are invisible in a key's value and
  are the whole of what a later reader needs. An unregistered key is reported
  by I12's check wherever it lands on a live bead.
- **Adding an invariant** — name its check in the same PR.
- **Divergence** — there is no divergence section: the running system is
  generated from the declarations this model requires, so divergence is zero
  by construction. If you find the ledger disagreeing with this document, one
  of the fourteen checks is missing a case; fix the check, not the prose.
