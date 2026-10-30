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
or the human surface ([human-engagement.md](human-engagement.md)),
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
| **Convoy** | Gas City's status grouping: a bead whose `tracks` edges name a batch, and the input every graph.v2 run is poured over. It carries no branch: an integration effort reaches main through its landing bead, an ordinary bead | a run's steps cannot derive the bead they work, and a batch cannot be followed as one unit |
| **Formula + step bead** | a workflow materialised as beads | a crashed session resumes by reconstructing intent from prose |
| **Check-set + check lane** | the merge preconditions an anchor declares in `check_set`, one lane per check. A lane's state is derived from its reviews and never stored on the anchor: `lane-state.sh` derives a lane's green from the closed review beads that back it, and the reviewed commit is recorded on the review bead as `reviewed_oid`, bound to no lane state. [state-machine.md](state-machine.md#checks) owns the vocabulary. | merges depend on whoever remembers to look |
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

### An anchor's children

A bead that hangs off an anchor (a review, a rework child, a finding, a
validation pass, a visit) names the anchor in `anchor_bead`, and that key is
what makes it a child. The child also has an edge onto the anchor, its
membership edge, and that edge can be of any type. bd keeps one edge per ordered
pair and refuses a second type on it, so an edge the pair already carries is the
membership edge. The pack joins a child whose pair has no edge with a `related`
edge. A visit whose subject is the anchor is usually joined already, because
`escalate.sh` puts a `tracks` edge from the visit onto its subject.

The live children are read by `anchor_bead` over the live statuses. That read
scans only the live beads, and it sees a child whatever filed it, edge or not.
The closed children are read through the edge, one
`gc bd dep list <anchor> --direction=up`, because a
`--metadata-field anchor_bead=<id>` query that covers closed has no index to use
and reads the whole closed ledger. That read takes every dependent whatever its
edge type, so a visit joined by its `tracks` edge is read, and a dependent is a
closed child when its `anchor_bead` names the anchor. A convoy tracking the
anchor is therefore not one, and a bead moved to another anchor leaves the old
one's set with its old edge still in place.

The edge answers for the closed children only in a store marked joined.
`tools/anchor-edges-backfill.sh` joins each anchor's children to it, and
`--mark` records the store joined (`anchor_edges.joined` in `gc bd kv`) after a
run that found no child missing its edge. A store without the mark reads its
closed children by `anchor_bead` too. `assets/scripts/bd-lib.sh` holds the read
(`bd_anchor_children`) and both writes. The helm board makes the same read in Go
for a pre-open anchor's review beads (`services/helm/internal/source/beads.go`),
batched over a rig's anchors because it derives every anchor in one gather. In a
store without the mark it reports those reviews unread rather than read the
closed ledger on every render. A child is created joined to its anchor, the edge
riding the create (`bd_create_child`), and an existing bead is joined before
`anchor_bead` is stamped on it (`bd_anchor_link`), so a marked store stays
joined. `related` holds nothing: it gates neither `bd ready` nor a close, and
the merge hold stays on the `blocks` edges read down from the anchor.

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
  atomic ([gascity/routing-model.md](gascity/routing-model.md)); the old
  healer passes existed because writers split transitions across calls.
- **One check-verdict writer** — `signoff.sh`, which closes the review bead
  with its verdict, the record a lane's green derives from. Returning a lane
  to `unreviewed` is a separate power from writing a verdict: superseding the
  lane's backing reviews (`review-outcome.sh`) withdraws evidence where a
  verdict asserts it, so no superseder can make a check pass. Who holds that
  power, and under which condition, is in [authority-map.md](authority-map.md).
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
| **I1** | Every dependency is recorded in the bead graph — no wait lives only in prose or a metadata string. The shape it asserts is [I1 in full](#i1-in-full-the-hold-the-demand-and-the-shape-law) below. | `doctor/check-wait-is-an-edge`: a LIVE bead carrying one of the hold markers declared in `lifecycle/lifecycle.toml` `[holds]` must also carry a `blocks` edge to a bead still live in the same store. Live is every non-closed status, because claiming or parking a bead does not answer the hold it states. Only `blocks` counts: it is the one edge type that holds a bead out of `bd ready`, so a `tracks` or `parent-child` record leaves the hold as unanswerable as the marker did. Only the same store counts, because a cross-store `bd dep add` reports success and holds nothing. Two degrees are reported apart, since their remedies differ: a bead with no `blocks` edge at all needs one filed, and a bead whose every blocker has closed, or names another store, needs its disposition instead. The markers are read from the declaration and never parsed out of prose, because a conclusion is prose by design and no list of wait verbs finishes, so every phrase one missed would report a clean pass. One marker can be answered by its own writer instead: `settled_keys` pairs `gc.takeaway` with `gc.takeaway_settled`, which `gc-helm.sh takeaway --no-wait` stamps beside the headline where the sitting settled its subject, and a headline without it stays a hold. That is the same refusal to read prose from the other side — every sign-off stamps a headline, only the writer knows whether it parked anything, and the key is where it says so. Each writer of the marker rewrites the key with it, so a settled sitting cannot answer for the park that follows it. The terminal end of a wait is exempt outright: a demand bead — the thing dependent work blocks ON — carries the hold's headline but can hold no forward `blocks` edge of its own, so `terminal_wait_key` (`gc.demand_for`, stamped by `gc-helm.sh demand`) names it in the declaration and a live bead carrying it is skipped rather than filed. `hold_severity` in the same declaration sets how findings are reported: a warning while the standing backlog of marker-only holds is converted, an error once it is. Takeaway holds are written as edges by `gc-helm.sh takeaway --waiting-on`, which warns when it could wire only the string; a first reaction's blocked disposition writes one (`first-reaction-dispose.sh`). |
| **I2** | The state space is closed: every `merge_result` value and status combo is declared in `lifecycle/lifecycle.toml`, and a bead in a declared detached state rests unheld and offered to no pool. | `doctor/check-state-space` |
| **I3** | Every routed bead is claimable: route AND assignee name a live target, routed work is in `bd ready` or in `bd blocked`, and rig-scoped orders are bound. | `doctor/check-routed-work-claimable` |
| **I4** | Every PR has exactly one owning anchor, and every gating anchor is open. | `doctor/check-one-anchor-per-pr` (structural); `merge.sh` also refuses on sight, fail-closed |
| **I5** | No bead is closed while the work it represents is unlanded: closed anchor ⇒ `merged` + `merged_sha`, or an explicit terminal state. | `doctor/check-closed-implies-landed` |
| **I6** | Every gating anchor declares a non-empty `check_set`, or the `none` opt-out. | `doctor/check-gate-integrity` |
| **I7** | A lane's green stands on a verdict a sanctioned writer recorded: a review bead `signoff.sh` closed with its verdict, or the approve outcome `review-outcome.sh back-lane` files for a lane the validator ruled converged. | The writers are singular by construction: `signoff.sh` holds the only code that records a check verdict, and `review-outcome.sh` the only code that files a backing outcome. `doctor/check-gate-marker-provenance` audits the depth half: every CLOSED `task_kind=review` bead that backs a lane on an open gating anchor — `signoff_verdict=approve` carrying a non-empty `reviewed_oid`, the local backing `lane-state.sh` derives green from — must record `gc.outcome=recorded` (a live backing) or `gc.outcome=superseded` (retired); an approve carrying any other outcome still derives the lane green (`lane-state.sh` excludes only `superseded`) while standing on a verdict no writer recorded, and is the finding. It reads no commit oid. An operator's APPROVED GitHub review backs a lane with no bead to audit. A closed review with no `signoff_verdict` backs no lane, because `signoff.sh` stamps `gc.outcome=recorded` on every close and `recorded` names no verdict, and the audit never fetches such a bead. The sanctioned writers record only `recorded` or `superseded`, so a clean store has no findings — it stays a forward regression detector. |
| **I8** | Every step bead reaches a terminal state: no offerable step under a closed root, no frontier stalled past its bound. A step under a closed root is offerable when its own status is open and every blocking dependency has closed; one parked at `status=blocked`, or still waiting on a live blocker, is inert residue and reported as a note, because no pool can hand it out. | `doctor/check-step-terminal` |
| **I9** | A molecule executes the formula text that is current when it runs. | `doctor/check-pour-text-current` (tk-5w3boh): a checkout lagging past the reconciler's self-heal window, an unfetched remote-tracking ref (the fail-open case, where the naive behind-count reads 0), and a live molecule poured before its formula last changed. Detection, not prevention — step descriptions still freeze at pour while the rig checkout advances on a 15-minute cooldown. |
| **I10** | Every pack order fires within its cadence window: three of its intervals, or one trip of the order dispatch rotation when that is longer. | `doctor/check-cadence-live` |
| **I11** | Every step a pool is meant to run is being run: a claimed step is held by a running session that is still producing output, and an offered step has been claimed at all. | `doctor/check-claim-advancing` (tk-beecuu, tk-08i70x). Claimed: reported when nothing can be advancing it — no assignee, an assignee naming no session, a holder that is not running, or a holder whose `last_active` is past the bound. Unclaimed: an open step `bd ready` is offering, routed, with no assignee and no `gc.claimed_at` ever stamped, is reported only when the agent its route names has a running session holding nothing; a suspended pool, a pool with `max` 0, a pool scaled to zero, and a pool whose every session is busy are all notes, because a queue behind them is backpressure rather than starvation. Held on purpose: a non-empty `gc.takeaway` or `hold_reason`, on the step or on the root `gc.root_bead_id` names, takes a step out of both arms as a note whose remedy is `status=blocked` — releasing a held step to `open` hands it to the pool its route still names, which is what the hold exists to prevent. Holder-clocked, so it is silent for a session that is genuinely working however long the step takes. I8 is the complement: bead-clocked, holder-blind, and scoped to open steps at 48h. |
| **I12** | A bead's kind is `metadata.task_kind`, and no reader decides a kind from a label ([what kind of bead this is](#what-kind-of-bead-this-is)). Where a reader narrows a listing with `-l <kind>` it re-filters on `task_kind`, and every writer of that kind sets the label — a narrowing on a label some writer omits returns a quietly short answer. | **UNCHECKED** (tk-0i90x5). The reader half is held by construction and by test: every kind branch in the pack reads `task_kind`, and `learning-recurrence.test.sh` pins the one script that narrows by label against a bead carrying the label without the kind. The writer half — for each kind a reader narrows on, no live bead carries the `task_kind` without the label — is the check that does not exist; only `observation` is narrowed on by a reader today, and it is clean at filing, so the check would ship as a forward regression detector. |
| **I13** | Every started workflow root is still advancing or reachable: an in_progress `gc.kind=workflow` root whose owning session is gone and whose work has not landed does not sit behind an executable frontier that is unclaimable — unrouted AND unowned — which no pool can be offered and no orphan recovery reaches. | `doctor/check-root-advancing` (tk-d12vam): a graph.v2 molecule runs its continuation-group steps inline in one pool session, and those steps carry no owner and no route by construction, so a drain landing mid-molecule strands them past both recovery paths — the witness's orphan recovery keys on an assignee, and no route means no pool is offered them. Reported STRANDED (error) only when all four hold, each a distinct healthy shape it must not report: SILENT (root or any member, a close included, untouched past the bound — default 120m, `GC_DOCTOR_ROOT_STALL_MINUTES`); UNHELD (no live session behind the root's `gc.session_name` or any member's assignee, `gc.session_id` or `gc.session_name` — the affinity slot a restart reuses counts, so a live slot exempts); STARTED (at least one step has closed, so it moved then stopped, AND its input convoy is still open, since a convoy closes when its one work bead lands); UNCLAIMABLE (a non-empty executable frontier — the `bd ready` members minus the inert `workflow`/`scope`/`spec` topology kinds poured alongside steps — every member unassigned AND carrying neither `gc.routed_to` nor `gc.execution_routed_to`, so the execution route a recovery fix stamps reads as reachable). A non-empty `gc.takeaway` or `hold_reason` on the root or a member is a note. It is the root-level complement to I8 (closed roots) and I11 (claimed or routed steps), neither of which fires here. Fails toward silence: an unread roster declines the run, and an unread store, convoy or closed-step listing leaves that unit unjudged rather than flagged. |
| **I14** | A refinery whose queue holds work is cycling its patrol: once a bead has waited in its find-work queue past the bound, a `mol-refinery-patrol` wisp assigned to that refinery was written within the bound. | `doctor/check-refinery-patrol-live`: the agent half of the refinery, where I10 asserts the cadence half. Each patrol iteration takes one bead from the queue and pours its successor wisp before it burns itself, so a refinery working a queue renews its wisp once per bead. A refinery that stops cycling halts intake: no handoff in its queue is gated or landed, and no handed-back rework closes. The queue is the set find-work selects from: open, assigned to the refinery, carrying `metadata.branch`, not an epic, with no `merge_result`, and with nothing holding it by `hold-lib.sh`'s definition, so a refinery whose queue holds only a landing bead still waiting on its effort reads as idle. Reported STALLED (error) only when both halves hold, because each alone is a healthy shape. An empty queue ends the turn and leaves the wisp resting, so an old wisp alone is an idle refinery. A queue whose oldest bead is younger than the bound (default 60m, `GC_DOCTOR_REFINERY_PATROL_STALL_MINUTES`) holds work the refinery has not yet had the bound to take. Waits are aged from the later of `updated_at`, which any later write resets, and the close that released the bead's last hold, so the check errs toward silence. A suspended refinery or rig is a note, and so is a held bead. An unread roster, queue, hold or wisp listing warns, and so does a bead held only by a blocker its store does not return. |
| **I15** | A closed epic was ruled closed: a closed `issue_type=epic` carrying a hypothesis carries `epic_ruling=close` with its outcome (`epic_ruling_reason`), or an explicit disposition pointer (`gc.superseded_by`). It never closes by a silent last-unit auto-close or on a continue or shift ruling, which keep it open ([epics.md](epics.md)). | `doctor/check-epic-closed-implies-ruled` (the after-the-fact backstop); `finalize-gate.sh` `clause_epic_ruling_recorded` applies the same predicate to the close paths that run the gate. |

Further checks guard structure that is not an anchor invariant:
`doctor/check-config-bound` (every prompt, overlay, and fragment the pack names
resolves in the composed config), `doctor/check-seed-audit-current`
(the generated seed audit is present and its pre-commit hook is wired;
warn-only),
`doctor/check-recycle-capable` (cycle-recycle can fire at all: the Stop and
UserPromptSubmit events reach the hook with its stdin intact, the hook's own
measurement reads the context size a transcript carries, its drift check sees
a changed pack file, and no refinery's git-op defer guard has been latched past
a bound), `doctor/check-cycle-recycle-hook` (the cycle-recycle
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
that nothing holds is slung by the deferred-dispatch reconcile order within its
cadence, so one that has stayed armed and open past that window — or one armed at a
non-open status `bd ready` never answers — is a dispatch silently not firing; a hold
is `assets/scripts/hold-lib.sh`'s, so an arm a park holds is not owed; `bd blocked`
lists an arm its parent's hold reaches under the arm's own id, naming the parent, but
`check-blocked-work-armed` asks blocked work only for a dispatch path, and an arm is
one, so it cannot see such an arm; warn-only),
and `doctor/check-until-resolved-owed` (the resolved-by mirror of
`check-armed-dispatch-owed`: the same reconcile order disposes an open, unassigned
bead through `bead-rehome.sh` within its cadence once every one of its own `until`
targets has closed, so one still undisposed past that window, with no open
`blocks` blocker of its own holding it, is a disposition silently not firing; the common
stuck case is an open visit on the bead holding the close. It decides which beads
are owed through the same `until-resolved.sh` the order reads, so a bead the order
leaves open because it carries live work is reported apart from that, as a decision
for a person; warn-only),
and `doctor/check-feedback-routing-owed` (the complement to the merge cadence's
feedback arm: a cheap pre-merge arm records a PR's review posture on the anchor and
a separate arm routes the feedback under it, so an OPEN anchor whose `pr_posture` is
`commented`/`changes_requested` with no `pr_comment_disposition` past the owed
window is operator feedback that reads as consumed while nothing has routed it; a
`pr_unengaged_threads` marker at the same head is a tracked hold and exempt;
warn-only), and `doctor/check-hq-marooned-work` (no rig-workable bead sits
unclaimed in the HQ (city) store: a city-scoped role running with GC_RIG
unset files a bare `bd create` into the HQ store, which no pool reads, so an
open unassigned task/bug/defect there — unrouted or routed to a pool — is
marooned by construction; the operator-queue decisions routed to human, daily
digests, and doctor and tech-debt advisories that legitimately live there are
exempt).
Another non-invariant check, `doctor/check-demo-toolchain`, reports readiness
rather than structure: whether the demo:capture toolchain — Node, ffmpeg,
`OPENAI_API_KEY`, and the `gh` that delivers a clip inline — is resolvable,
warn-only, so a demo session learns before it captures whether the clip will
narrate or degrade to a silent, captioned one. It also reports whether
`VERCEL_AUTOMATION_BYPASS_SECRET` reaches the session, and warns when the
secrets file holds that key and the session does not. The capture installs its
own browser, so the check does not probe for one.
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

**The shape law** is that a blocker on a bead with `parent-child` children
holds every part of it, so such a bead carries a `blocks` edge only for a wait
that belongs to all of its parts. A wait that belongs to one part goes on that
part.

The reason is what `parent-child` means. It is decomposition: the child is part
of the parent's work, so the parent's blocked state cascades down to it. That
cascade is the correct reading of containment and is not a defect to route
around. A wait of the whole is what the cascade carries: a park on an epic
([steering.md](steering.md)), or a prerequisite that all of an epic's work
needs, holds every part that has not started, and the blocker's close releases
them together. The cascade does damage where a wait of one part is put on the
whole, which holds every other part with it, and where the edge has been used
for something that is not decomposition. Whether routed work is that case
depends on what the work is. Work `W` a sitting hands out on subject `S` is a
dependency by default: `S` is waiting for it and does not contain it, so `W` is
not a part of `S`. Filing that `W` as a child of `S` would state a containment
that is not true, and the stranding would follow from the false statement rather
than from the cascade; filed as the graph is, `W` sits beside `S` and `S` blocks
on `W`, which reads correctly and keeps `W` claimable. The exception is work
that genuinely decomposes an epic subject — a story or task that is part of the
epic. That `W` is a member, a `parent-child` child, and it carries no `blocks`
edge back to the subject: the completion-wait is implicit in containment, and
beads refuses a parent→descendant `blocks` edge in any case. "The subject is an
epic" is the indicator that tells the two apart, and the shape law decides the
mechanism either way — a dependency sibling carries the `blocks` edge, a member
child never does (`specs/tk-xgj2ko/membership-mechanics.md`). beads enforces the
sharpest case directly, refusing an edge that would make a parent wait on its
own descendant.

Two boundaries. A conclusion is prose, stored once and never cleared, and it
does not become a wait by being written down; that seam is
[lifecycle-composition.md](lifecycle-composition.md). Which query term each
mechanism falsifies is [gascity/routing-model.md](gascity/routing-model.md),
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
stands: every order, formula, service, pack command, and `assets/scripts`
entry a running city executes, with nothing unplaced and no row carrying any
other value.

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
| `assets/scripts/work-tree-holder.sh` | work | Tells load-context whether a live session is working the bead's tree, the one sign of a run in flight on a work bead the workflow never claims. |
| `assets/scripts/rig-mentions.sh` | work | Lists each place a change names another rig of the city: its name, a bead id from its store, or a path into its checkout. The rigs come from `gc rig list`, so a repository never commits the names it looks for. The self-review runs it on the lines the branch adds, the commit messages no remote has yet, and the title, summary and dispatch text the pull request publishes, and submit-and-exit runs it on the summary it composes. The polecat fixes what it lists, and nothing stops on it. |
| `assets/scripts/await-ruling.sh` | work | Records a work bead's wait for a person's ruling, for a declined run and for a convoy's rebuild child whose landing the refinery holds: a `blocks` edge onto the visit that asks for the ruling, and a deferred-dispatch arm that re-slings the work when the visit closes, after it releases the caller's own claim on the work bead, or one that no live worker holds. |
| `orders/deferred-dispatch.toml` | work | Routes work whose blockers have closed, tells a named agent when bd reports the bead assigned to it ready, and disposes work whose `until` targets have closed. |
| `assets/scripts/deferred-dispatch.sh` | work | The pass that order runs. A pending dispatch is a fact about the work, so it lives on the work bead, and so does a resolution: an `until` edge records that the bead is resolved when another one closes. Its `notify` is the dispatch a named agent's assigned work owes: a mail that wakes the agent for its hook, sent once bd reports the bead ready. The pass slings an armed bead once nothing holds it, and disposes an open, unassigned bead through `bead-rehome.sh` once every one of its `until` targets has closed and no `blocks` blocker of its own is open, unless the bead carries live work (`live-work.sh`). `until-resolved.sh` decides which beads are owed. A `blocks` edge never disposes. |
| `orders/queue-priority.toml` | work | Settles the polecat queue at the priorities its beads follow, for the raw priority and parent edits no writer saw. |
| `assets/scripts/queue-priority.sh` | work | Writes the priority work competes at, under one lock per store: `settle` on one bead and its live workflows, which each creator of PR-finishing work runs before its child can be claimed, the `move` that `gc-helm.sh priority` runs over everything that follows a bead, and the order's pass over the polecat queue ([steering.md](steering.md#priority)). |
| `assets/scripts/priority-lib.sh` | work | The one definition of a bead's priority: the priority of the bead it follows plus its own shift, kept within P0 to P4 at each level, where a member follows its most urgent parent, PR-finishing work its anchor, at P0 once the anchor's PR is approved, and a workflow's convoy, root and steps the bead they were poured for. Its walk reads a generation of followed beads per listing. `queue-priority.sh` sources it, and `pr-facts.sh` sources it for the approval alone, the rank an anchor's PR-finishing work follows. |
| `formulas/mol-review.toml` | review | The review lifecycle every check shares: claim, pin, apply the check's method, one `signoff.sh` verdict, drain. |
| `assets/scripts/gate-ensure.sh` | review | Makes every declared check raisable and routes the review bead. Runs as arm 6 of the merge cadence. |
| `assets/scripts/signoff.sh` | review | The single writer of check verdicts (I7). |
| `assets/scripts/review-workspace.sh` | review | A review's directory on disk, named for its review bead: makes the detached worktree where the review reads its pinned commit and runs any suite its check calls for, removes the directory at the verdict step, and, as the review-workspace-reap order's pass, removes the directories of reviews that closed some other way. |
| `assets/scripts/review-evidence.sh` | review | Prints what `gctk rig` recorded at the commit a review reads, a line per check, and whether the anchor's pre-existing mark holds a recorded fail. Every review's gather runs it, so a check's method reads the evidence and works none of it out. |
| `assets/scripts/finding.sh` | review | The finding-bead primitive: files a review objection as a bead with a rebase-stable `finding.key` and, outside the key, the finding contract its reviewer wrote (grade, category, failure scenario, verification), rules its disposition (must-fix `blocks` the anchor, and a later ruling releases that hold only once it has committed; deferred, which it refuses for a P2, files a claimable follow-up in one create carrying both its edges, the anchor's `blocks` and a `discovered-from` onto the finding, reuses that follow-up when a failed ruling is retried, then closes; declined closes; needs-you files a visit, or names one already open on the anchor's feedback, and stays open until the operator rules that visit, or the one a fold hands its question to, and no fix unit on its lane, nor a ruling's rework child, is in flight; restates closes a human review body that only frames the inline comments of its review round, the reviews its reviewer submitted against one commit), refuses any other ruling of a human finding while an open visit tracks or holds the rework minted for its feedback batch, lists the open visits on an anchor's feedback, wires the fix unit's two `blocks` edges, and reads whether a must-fix finding is open. It records the words a review's living answer shows for a human finding: the label and sentence the validator rules with, and the fix unit's own sentence, flag and notes (`answer`, `fix-notes`). |
| `assets/scripts/lane-state.sh` | review | Derives a lane's `green` from the review-outcome graph — a closed approve-verdict review bead, non-superseded — so every check reader agrees. A GitHub approval backs a lane only when no conflicted bring-current round reopened the lane after the approval was given. |
| `formulas/mol-validate.toml` | review | The validator method: one pass per review batch that rules each finding's disposition (must-fix, deferred, declined, needs-you or restates — decisions 1 and 2) and whether a fresh whole-diff review is warranted (decision 3), so convergence is judged rather than counted. A human finding whose question an open visit on the anchor's feedback already carries is ruled needs-you on that visit, never on its merits, and a human ruling writes the label and sentence the review's living answer shows. The `{{defer_policy}}` variable carries the fix-now-versus-defer threshold, and a P2, filed only when its review sends the PR back, is ruled must-fix or declined, never deferred. A ruling that a fresh whole-diff review is warranted also runs `approval-withdraw.sh`, whose note is the one write the anchor takes from the pass. |
| `assets/scripts/validate-dispatch-body.sh` | review | Emits the dispatch note a validation-pass bead carries. |
| `assets/scripts/review-outcome.sh` | review | The write side of a lane's approve outcome, the bead lane-state.sh reads: `back-lane` files the closed approve outcome that greens a lane, `supersede-lane` stamps it superseded to return the lane to `unreviewed`, and `supersede-anchor` does that for every lane the anchor declares. The validator calls every verb; `converse-rework.sh` calls `supersede-anchor` once an operator ruling's rework is filed; `bring-current-guard.sh` calls `supersede-lane` on each lane a conflicted bring-current round reopens. |
| `assets/scripts/demo-repo-artifact.sh` | review | The demo check's repo-artifact modality: lists the visuals a reviewed commit carries that its change adds, names, or sits beside, and attaches the chosen one to the PR inline, as the commit stores it, through `demo-deliver.sh`. The comment says what the change does to the visual and names the commit that last changed it. |
| `assets/scripts/demo-screenshot.sh` | review | The demo check's screenshot modality: renders one state of the surface a change affects and saves it as a PNG for `demo-deliver.sh` to attach, through the SprintShow engine's screenshot command, which checks each step's proof as the engine's videos do. The surface is an app page a demo:capture script drives to the state, a command's output as a terminal shows it, or markdown as GitHub's own renderer renders a comment. It refuses an engine whose help lists no screenshot command, and markdown holding a block that github.com's page script finishes, such as a mermaid diagram or math. |
| `assets/scripts/demo-screenshot.mjs` | review | The renderer behind `demo-screenshot.sh`'s terminal and markdown kinds. It draws terminal output, or GitHub's HTML for a comment, as one HTML page with no script, whose `#surface` element the engine's screenshot command serves and captures. It refuses a comment holding a block that github.com's page script finishes, which a page with no script would draw unfinished. |
| `assets/scripts/demo-engine-lib.sh` | review | The one definition of how a demo capture finds the SprintShow engine, provisions the browser it launches, and runs its CLI: Node held to the engine's floor of 22.18, then the `sprintshow` rig checkout whose package.json names the engine, with its dependencies installed whenever one its package.json lists is missing and its CLI run under node, or else the published package through npx, and in either case the chromium-headless-shell build that engine's own Playwright installs. The capture cores source it: `rig-demo-capture.sh`, which records a video, and `demo-screenshot.sh`, which saves a PNG. So do the demo:capture skill's examples, from the pack gc loaded through `gc <binding> scripts-dir`. |
| `services/helm/cmd/helm-fixture` | review | Serves the helm board on fixture data for a demo capture: the app the commit embeds, a board file as JSON at the board's own path, and a canned answer for each write verb, or a refusal. It links no bead source and no write tool, so a capture of the board never reads or writes the live city. `docs/review-demo.md` names it as the board's `--serve` command. |
| `orders/refinery-reconcile.toml` | merge | The merge cadence: one pass per rig, every 60s. |
| `orders/reconcile-rig-checkouts.toml` | merge | Landed is not live until the `rigs/*` checkout syncs; this fast-forwards it. |
| `formulas/mol-refinery-patrol.toml` | merge | The cadence's judgment half. The cadence itself is the order. Its run-tests step appends a note to the patrol wisp each time a wait finds the gate still running, so a refinery waiting on a long gate keeps its wisp inside I14's bound. |
| `assets/scripts/refinery-reconcile.sh` | merge | Drives one cadence pass over this rig's queue. |
| `assets/scripts/pace-lib.sh` | merge | The visit order and time budget of a cadence arm that walks the gating set: visit in id order after the anchor the last pass finished, wrapping, and start no new anchor past the arm's deadline. It also keeps each walk's seen marks, what it saw of each anchor at its last visit, so an arm can put first the anchors that changed since. The paced arms source it, and `gctk merge` carries the same rotation. |
| `assets/scripts/merge.sh` | merge | Arm 2: the single writer of merged truth. On the anchor of each open, non-draft PR it visits, it also records how many of the PR's review threads wait on the city's answer (`pr.unanswered_threads`), which the `held:` labels and the board read and the merge does not. |
| `assets/scripts/review-verdict.sh` | merge | The approval rule as one jq definition: each outside account's latest approving or change-requesting review decides, and once a ruling on a bring-current round lifts the approval, no approval submitted at or before the anchor's `bring_current_lifted_at` counts. The merge lands on it, `pr-facts.sh` records an approval the lift line set aside as `review_required` and brings only an approved PR's branch current by it, and `bring-current-guard.sh` and `approval-withdraw.sh` read from it the approvals they dismiss, every outside approval not yet dismissed: the guard on a ruling that lifts the approval a bring-current round outgrew, the withdrawal on a validator ruling that a fresh whole-diff review is warranted. `gctk merge` states the rule natively, and `merge.test.sh` holds the two to one verdict. |
| `assets/scripts/review-dismissal.sh` | merge | What a review dismissal retires, as one jq definition: the inline comments a dismissed review carried stop counting as feedback. `pr-facts.sh` reads the comment space through it, `pr-post.sh`'s rule for a review thread that waits on the city's answer reads a thread's posts through it, and `approval-withdraw.sh` asks it which comments a dismissal would retire before they are routed. It also holds how the two approval dismissers, `approval-withdraw.sh` and `bring-current-guard.sh`, name the PR and the approvals they act on. |
| `assets/scripts/bring-current-guard.sh` | merge | Holds a bring-current round to the worker's audit. Run at every handoff onto a branch that carries a review, it reads what the push merged in: a clean round (git's own merge) is recorded and lands quietly; a conflicted one is handed off only when the audit covers every item git did not produce on its own, or its resume asked for no audit, then stored on the anchor with the guard's diff evidence and routed to triage by reopening its lane. An anchor whose `check_set` declares no triage lane gains it in the same write, so triage rules on its conflicted round, except on the `none` or `off` opt-out, which only a person changes: there the guard rules on the round itself, reopening nothing and lifting the approval. Its `decide`, run by `signoff.sh`, records triage's ruling and carries it out: the lanes that run again, and, when the ruling lifts the approval, the lift line `bring_current_lifted_at` the approval rule reads, then each approver re-requested and the approvals the line covers dismissed. A re-run of the same hand-off carries out again a ruling the guard recorded itself, marked `by: guard`, in the same order. |
| `assets/scripts/bring-current-audit.sh` | merge | The worker's account of a bring-current round and the words every message about it is composed from: `add` records one entry per conflicted file or edit beyond the merge (what collided, what was decided and why, what to check, a routine or judgment rating), `ask` files the visit for a conflict the worker cannot resolve without guessing, and its renderer composes from the anchor's record the round's collapsed account in triage's posted verdict, and the call a lifting ruling asks of the operator, which opens that verdict and is the dismissal note. |
| `assets/scripts/approval-withdraw.sh` | merge | Keeps an approval from covering a change the validator ruled needs a fresh whole-diff review. `mol-validate` runs it on that ruling, before the supersede: it records the reviews on the validation pass, notes the judgment on the anchor once, and dismisses every outside approval not yet dismissed, which it reads from `review-verdict.sh`. |
| `assets/scripts/seed-audit-reaudit.sh` | merge | The one writer of the seed audit's re-audit. `gctk merge` hands it the files `render-seed-audit.sh --check-merge` found the base already stale in, text the `gc` binary moved with no merge behind it, and it slings the one bead that re-renders the default branch and lands that text in a pull request of its own. A base owns at most one live re-audit, and the merge never waits on it. No merge authority. |
| `assets/scripts/record-failure-cap.sh` | merge | The memory the record arms lack: counts consecutive failures to record a merged PR on the anchor, and files one visit past the cap. Called by `gctk merge` and `pr-facts.sh`, which spend one budget between them. |
| `assets/scripts/pre-open-rebase.sh` | merge | Arm 5: asks git whether a pre-open anchor's branch still merges, and dispatches the rebase child no PR-fact arm can. No merge authority. |
| `assets/scripts/branch-supersession.sh` | merge | Asked by arms 5 and 7 before they file a merge-in child. When the conflict comes from a landed change that deleted or rewrote the code the branch edits, it files the operator's `rework-base-supersession` decision instead. No merge authority. |
| `assets/scripts/rejection-repool.sh` | merge | The patrol's rejection: hands a work bead the refinery will not land back to the polecat pool as a fresh `mol-polecat-work` pour, which no hold on the bead's epic reaches, after a release that records why. It never pours a convoy, such as a graduation's anchor, since a run poured onto a convoy works on the beads the convoy tracks: a convoy's rebuild is poured onto its rebuild child, an ordinary task that resumes the convoy's branch and lands on it. A failed sling is armed for a retry, and any other stop files a visit. No merge authority. |
| `assets/scripts/pr-open.sh` | merge | Arm 3: `pre_open_gate` to `pull_request`. |
| `assets/scripts/pr-facts.sh` | merge | Arm 7: records external PR facts. No merge authority. Its write-back is the one writer of each human review round's living answer, the Conversation comment that says what became of every point the round raised. |
| `assets/scripts/review-answer.sh` | merge | What a human review round's living answer shows, as jq definitions sourced by `pr-facts.sh`, its one writer: the round, the reviews one reviewer submitted against one commit however many GitHub reviews carry them, which one comment answers; a point per finding, labelled and answered in the words the validator and the fix unit recorded, sorted into Needs you, Worth a look, In progress and Done, with a declined or deferred point under Needs you while its thread waits on the reviewer; the line such a point and its reply in the thread both end with, and the lookup of a comment's thread and the test for the city's answer in it, which the reply arm reads the thread by too; and the one-line note the review's dismissal carries. |
| `assets/scripts/review-sweep.sh` | merge | Arm 8: closes a dispatched review with no reviewable surface left. No merge authority. |
| `assets/scripts/scaffolding-sweep.sh` | merge | Arm 9: retires a disposed anchor's machine review scaffolding (`task_kind=validation\|finding\|rework`) so it can finalize, and carries a finding that can cite code the target branch already carries forward to a bug bead instead of mooting it. `pr-facts.sh` runs it for one anchor before consummating that anchor's PR-close disposition. Leaves reviews, human visits, operator freezes, and the anchor itself alone. No merge authority. |
| `assets/scripts/duplicate-sweep.sh` | merge | Arm 10: disposes of verified no-op duplicate dispatches, and of never-dispatched rework twins whose sibling answering the same review or ruling landed, via `bead-rehome.sh`. No merge authority. |
| `assets/scripts/pr-stack.sh` | merge | Arm 11: keeps each open PR current with its anchor — the branch-beads section, the `pr-summary` region a rework moved past, and the title composed from the anchor's. Writes only PR bodies and titles. No merge authority. |
| `assets/scripts/reconcile-rig-checkouts.sh` | merge | The pass that order runs. It fast-forwards each checkout, heals a refusal it can prove lossless, and escalates the rest. |
| `assets/scripts/detached-job.sh` | merge | Runs a command that can outlive one tool call in a session of its own, reports a launch that did not happen, and waits for it in bounded foreground calls that end when the command exits, whether or not it recorded an exit code. The refinery's run-tests step runs its gates through it. |
| `assets/scripts/direct-merge-push.sh` | merge | The patrol's direct-mode landing: for a bead and branch the prep worktree records as the ones staged there, stamps the prepared head on the bead, pushes it onto its target as a fast-forward, named by commit id, reads the landing back from origin, and records and closes the bead in one lifecycle transition. Asked to, it then deletes that branch from origin. A landing whose record fails keeps the stamp and the branch, and the next patrol records it. A push refused for branch protection moves the bead to the PR path instead, and a target that moved after the prepare lands nothing and leaves the bead for the next patrol. |
| `assets/scripts/refinery-workspace.sh` | merge | The refinery's directories under a rig's git dir: stages the branch under prep in its detached worktree, recording there which bead and branch it holds, reads that record back for the merge-push step, which acts for the bead it names, checks it for `direct-merge-push.sh` before the landing, tears the worktree down, and empties the checks directory the gate reads, so no block of the patrol removes anything itself. |
| `formulas/mol-visit.toml` | visit | Files one visit on a subject bead, parked on the helm board (`gc.routed_to=human`) for an operator to engage. |
| `assets/scripts/first-reaction-dispose.sh` | visit | Performs a first reaction's disposition — one of its exits (route the bead to a pool or to the named agent whose work it is, which it tells through `deferred-dispatch.sh notify`, recommend an action for the operator to trigger, hold it on an edge, leave it on an `until` edge to close when the bead that ends its job lands, route it to a validating closer, or put it to the operator as a human gate for their judgment) — stamps `gc.reacted_by` on the subject, and closes the reaction bead. A pool route, or a blocked exit's arm, reaches only a bead the intake rule admits: a member of an epic, PR-finishing work, or an emergency whose named check it confirms failing on main, routed at P0. It marks any other bead `placement=pending` and leaves it unrouted for the placement sitting ([steering.md](steering.md)). Its `--stand-down`, which the reaction runs before it reads the subject, closes the reaction bead the same way and writes nothing else when the subject already carries this reaction's `gc.reacted_by` or a live owner's `gc.reaction_owned`. The reaction is its own leased task bead R filed by `tools/gc-proactive.sh`; the prompt is the method. It sits in visit because its product is a bead the human no longer has to triage. It never closes the subject: the close disposition slings it to a validating closer. |
| `formulas/mol-validate-close.toml` | visit | The validating closer a `close` disposition routes to: a capable pool re-checks the no-work conclusion against live state and closes the subject (`gc.work_outcome=no-op`) when it holds, or files a visit when it does not. The one bead-closer outside the refinery, gated on its own confident check. |
| `orders/helm-build.toml` | visit | Keeps the served board binary current with `services/helm`. |
| `services/helm` | visit | The board. Derives every row per render from the ledger. |
| `assets/scripts/gc-helm.sh` | visit | The board's write verbs (takeaway, open, engage, react, dismiss, demand, accept, handback, and the operator's [park](steering.md) and [priority](steering.md#priority), whose writes `queue-priority.sh move` makes) and its read-only verbs: resolve, and unplaced, which lists the placement sitting's queue. |
| `assets/scripts/gc-helm-svc.sh` | visit | The `proxy_process` launcher for the board backend. |
| `assets/scripts/gc-visit-open.sh` | visit | Operator-origin visit intake in one command. |
| `assets/scripts/city-liveness.sh` | visit | The one reading of the liveness flags in `gc rig list --json`: whether a rig is suspended, and whether the city controller is running, where the HQ row's `running=false` counts only when `gc status` does not contradict it. `gc-helm.sh`'s engage refuses on them and `gc-visit-open.sh` notes that a report will wait. |
| `orders/converse-reap.toml` | visit | Fires the converse sitting reaper every five minutes, city-wide. |
| `assets/scripts/converse-reap.sh` | visit | The pass that order runs: closes each converse session whose visit reads closed or gone, whether or not anyone is attached to it. It is the backstop for a session that outlives its closed visit, such as a stop that did not take ([human-engagement.md](human-engagement.md)). It sits in visit, not in patrol with the other reapers, because it completes a visit's ending the way `reconcile-rig-checkouts` completes a merge's effect. |
| `assets/scripts/converse-claim.sh` | visit | Claims the visit a converse sitting works, and names one the session already holds, or one whose close alone is missing, so the sitting neither restarts it nor ends it. |
| `assets/scripts/bead-rehome.sh` | visit | The one evidence-gated close-with-successor writer: it re-establishes the evidence for each close itself, and `--check` evaluates it without writing. After a close it hands the branch the closed bead names to `branch-end.sh`. Callers are converse dispositions, operator re-homes, `duplicate-sweep.sh`, `pr-facts.sh` consummating a pre-recorded PR-close disposition, `scaffolding-sweep.sh` carrying a finding forward, and `deferred-dispatch.sh` disposing a bead its `until` targets resolved. |
| `assets/scripts/pr-dispose.sh` | visit | Records a deliberate supersede/not-planned PR-close disposition on the open anchor and closes the PR, so `pr-facts.sh` consummates it through `bead-rehome.sh` instead of filing a rework-or-close visit. The PR side of the same disposition doctrine, with the same callers: converse dispositions and operator close-outs. |
| `assets/scripts/converse-rework.sh` | visit | Turns a sitting's ruling on an open PR into the rework it owes: it refuses an anchor that is not an open PR, whose rig checkout does not resolve, or whose branch head does not read from that checkout's origin, takes the work order from the anchor, files the child through `rework-child.sh` with the visit as `source_ruling_bead`, and then, in that checkout, returns every lane the anchor declares at that head to `unreviewed` through `review-outcome.sh supersede-anchor`. Its one caller is `converse-signoff.sh --rework`. It sits in visit for the reason `pr-dispose.sh` does. Both carry out a ruling on an open PR, this one as a rework and `pr-dispose.sh` as a close. |
| `assets/scripts/gc-terminal-attach.sh` | visit | The city web terminal's attach target. |
| `assets/scripts/tmux-visit-prompt.sh` | visit | `prefix + a`: type a message, get a durable conversation. |
| `assets/scripts/tmux-dismiss-sitting.sh` | visit | `prefix + X`: dismiss the converse sitting in view, after a confirm. |
| `assets/scripts/tmux-bindings.sh` | visit | Installs the keybindings that reach the surfaces above. |
| `assets/scripts/tmux-pick-helm.sh` | visit | The board picker. |
| `assets/scripts/tmux-pick-session.sh` | visit | The session picker. |
| `assets/scripts/tmux-keeper-toggle.sh` | visit | Pins or unpins the keeper in the session picker. |
| `assets/scripts/work-outcome.sh` | visit | The one `gc.work_outcome=no-op` stamp a visit gets before it closes, for the work-record gate `gc bd close` runs. Every visit closer sources it: `visit-close.sh`, the `gc-helm.sh` dismiss verb, `bead-rehome.sh` and `converse-claim.sh`. |
| `assets/scripts/visit-topic.sh` | visit | The one definition of a visit's topic: its escalation_key, the visit itself when it was filed for a distinct concern (`visit_topic=own`), else its subject. It encodes that decision for the fold's comparison and for the demands a sitting files. `converse-fold.sh`, `converse-hold.sh` and `converse-signoff.sh` source it. |
| `orders/feedback-miner.toml` | feedback | Fires the sweep of recently merged PR review threads. |
| `orders/feedback-distiller.toml` | feedback | The daily heartbeat that judges pending observations. |
| `formulas/mol-feedback-miner.toml` | feedback | Cold capture: records each review post from outside the city as one condensed observation, and each corrective-feedback hit in the city's own posts as another. |
| `assets/scripts/feedback-miner.sh` | feedback | The miner's mechanical half: reads a window's PR review conversations, tells the city's posts, outside ones and notices apart by `pr-post.sh`'s definitions, files the observations the miner's agent condenses, and flags a city post that lacks its mark through `patrol-finding.sh`. It keeps in `gc bd kv` the outside capture's day, from which the capture still owes a read of every PR updated since (`feedback_miner.outside_since.<owner>_<name>`), and each unmarked city post the flag has named, with the finding that names it (`feedback_miner.unmarked_post.<post>`). |
| `formulas/mol-feedback-distiller.toml` | feedback | Turns pending observations into reviewed prompt-update proposals. |
| `formulas/mol-witness-patrol.toml` | patrol | Mail triage, orphan recovery, and escalation for one rig. |
| `formulas/mol-deacon-patrol.toml` | patrol | City infrastructure health: Dolt, orphan processes, doctor sweep. |
| `formulas/mol-dog-shutdown-dance.toml` | patrol | Due process for one wedged session, against a claimed warrant. |
| `orders/boot-health.toml` | patrol | Fires the wedged-deacon detector. |
| `orders/liveness-sweep.toml` | patrol | Condition-triggered: runs the sweep once the precheck proves a delta. |
| `orders/pin-keepalive.toml` | patrol | Condition-triggered, city-scoped: pins standing conversational named sessions (mechanik today) so config-drift restart keeps deferring on them. |
| `orders/quota-park-nudge.toml` | patrol | Fires the quota-park nudge. |
| `orders/scratch-reap.toml` | patrol | Fires the scratch reaper hourly, city-wide. |
| `orders/build-scratch-reap.toml` | patrol | Fires the build/test scratch reaper hourly, city-wide. |
| `orders/worktree-reap.toml` | patrol | Fires the worktree reaper hourly, city-wide. |
| `orders/review-workspace-reap.toml` | patrol | Fires the review-workspace reaper hourly, city-wide. |
| `orders/notification-wisp-reap.toml` | patrol | Fires the notification-wisp reaper hourly, city-wide. |
| `orders/dolt-reclaim.toml` | patrol | Fires the Dolt reclaim pass daily, city-wide: runs `gc dolt compact --gc-only` on each store whose noms size is over the per-database line. |
| `assets/scripts/boot-health.sh` | patrol | Mechanical reads: the patrol-wisp ledger, and the deacon's pane only when the wisp is not fresh. Report-only by design ([authority-map.md](authority-map.md)): it files a cold deacon as a finding through `patrol-finding.sh`, one per deacon, refreshes it while the episode lasts, and records on it the fresh wisp that ends the episode. |
| `assets/scripts/dance-probe.sh` | patrol | The mechanical half of one interrogation round; the formula judges the verdict. |
| `assets/scripts/doctor-sweep.sh` | patrol | Runs `gc doctor` detached, once per interval with one capped retry after a failed or exceeded run, in a scope that outlives both the harness ceiling a foreground call cannot exceed and the patrol session's own teardown, turns a sweep that never finishes into a state carrying its elapsed time and the check it stopped in, and reports a sweep that finished more than an interval before it was collected as stale, never as current findings. |
| `assets/scripts/gc-deacon-ledger.sh` | patrol | The deacon's rolling incident ledger: one open `deacon-ledger` bead, one comment per non-routine action, rotated so it stays skimmable. Reconstructs a shift for an operator or a recycled deacon without a transcript. |
| `assets/scripts/liveness-classify.sh` | patrol | The one liveness classifier: puts every ready bead in a named class, and a bead no class claims is an unnamed wait. A bead held for the placement sitting is a named wait. The sweep runs it with every read it takes. Its precheck runs it with the reads beyond the bead set left empty, so the precheck's survivors contain the sweep's candidates. |
| `assets/scripts/liveness-recheck.sh` | patrol | Re-validates a sweep visit's census at claim time. A bead held for the placement sitting reads as that wait and is not on the visit's live agenda. |
| `assets/scripts/liveness-sweep-precheck.sh` | patrol | The order's condition check: proves a pass has something to say before one runs. |
| `assets/scripts/liveness-sweep.sh` | patrol | Classifies every open bead; unnamed waits batch into one triage visit. |
| `assets/scripts/pin-keepalive-precheck.sh` | patrol | The pin-keepalive order's condition check: runs `pin-keepalive.sh --check`, read-only. |
| `assets/scripts/pin-keepalive.sh` | patrol | The pass, and (in `--check` mode) its own condition gate on one predicate: pins every standing conversational named session (`configured_named_session`, provider `claude`) that is not already pinned. |
| `assets/scripts/quota-park-nudge.sh` | patrol | Resumes a session parked behind a provider quota banner. |
| `assets/scripts/scratch-reap.sh` | patrol | Removes the scratch of sessions that have ended, and of sessions inactive past the horizon, so the per-uid tmpfs quota has a floor the pack controls. |
| `assets/scripts/build-scratch-reap.sh` | patrol | Removes build and test scratch (Go toolchain trees, gc.test per-run trees, templated tool temp) that a killed or crashed run left behind, gated on no live holder and — for pid-named trees — a dead pid, so the per-uid tmpfs quota has a floor the pack controls. |
| `assets/scripts/worktree-reap.sh` | patrol | Removes the worktrees of closed work beads, each pinned by an archive tag first, so a landed bead's checkout stops being a permanent floor under the disk. |
| `assets/scripts/notification-wisp-reap.sh` | patrol | Closes a city-store "Human gate awaiting you" notice once its gate is no longer open, and collapses duplicate "ESCALATION" copies to one open notice — the notification wisps core mails and never retires. |
| `assets/scripts/order-cadence.sh` | patrol | The one definition of an order's cadence window: max(3×interval, one trip of the order dispatch rotation), the trip derived from the live registry and the city's dispatch budget. Patrol's doctor sweep runs `check-cadence-live` (I10), `check-armed-dispatch-owed` and `check-until-resolved-owed`, which all source it, so an owed check never calls owed a gap I10 reads as healthy. |
| `assets/scripts/dolt-reclaim.sh` | patrol | Measures each managed Dolt store's noms size and runs `gc dolt compact --gc-only --only-db <db>` on the ones over the per-database line, so a store size-bloated below the flatten commit-threshold is reclaimed on a cadence. Never runs a bare flatten; defers while the data plane is degraded. |
| `assets/scripts/escalate.sh` | shared primitive | One open visit per situation key — the door to a human, for what only a human can answer. The window is one OPEN visit, so a recurring observation belongs in `patrol-finding.sh` instead. |
| `assets/scripts/patrol-finding.sh` | shared primitive | One durable bead per patrol finding, deduped on `finding.key` and its subject. A new bead that shares either with a live finding in its scope is refused unless the caller passes `--distinct`. A caller that sees the situation end records it with `--cleared`, which sets the live bead's `situation` state with `bd set-state` and files no finding. A proactive first reaction disposes it: routed to a pool, held for the placement sitting, held on an edge, or put to the operator as a human gate. |
| `assets/scripts/gc-bd-watch.sh` | shared primitive | Bead-state changes as JSONL, for any agent waiting on work it dispatched. |
| `assets/scripts/lifecycle.sh` | shared primitive | The only writer of a lifecycle transition. |
| `assets/scripts/render-seed-audit.sh` | shared primitive | Renders the text each agent actually receives. Its `--check` mode re-renders a checkout, and its `--check-merge` mode, which renders the merge result, is what `merge.sh` gates a landing on. With `--base-stale-out` it also names the files the base is already stale in, which the merge hands to `seed-audit-reaudit.sh`. Its `--since` mode, which the pre-commit hook runs, writes only what a change moves, so text the `gc` binary moved rides in no unrelated commit. `doctor/check-seed-audit-current` reports whether the artifact is present and its hook wired. |
| `assets/scripts/step-close.sh` | shared primitive | A graph.v2 step advances only by closing its own bead, and every formula's steps end here. |
| `assets/scripts/claim-context.sh` | shared primitive | The one read a pool session orients from after `gc hook --claim`. It reads the claimed bead and its input convoy and prints the claimed step's `gc.step_ref` and instructions, its workflow root, formula and input convoy, and the work bead's status, assignee, metadata, notes and description. `--no-step` leaves out the instructions when the claim result's `step_reminder` carries them. The polecat prompts' claim contract runs it, so a session working a `mol-polecat-work` step (work) and one working a `mol-review` step (review) orient from it alike. |
| `assets/scripts/preexisting-failure.sh` | shared primitive | One tracker per failure already red on a base branch, keyed on the `failure_key` it derives from the failing test, target or linted file and stamps in the create, so a retitle cannot hide the tracker. A tracker that a fold closed answers through the live bead its failure moved to, so a fold cannot hide it either. The refinery's merge gate (merge) and a polecat's pre-flight (work) look trackers up and file them through it. |
| `services/gctk` (`gctk rig`) | shared primitive | Runs a rig's declared checks with the command its caller passes, and records the result of test, lint and typecheck against the commit it ran at, so a later call at that commit, or a full-suite call at a commit with the same tree, answers from the record. Work runs it in `mol-polecat-work`'s workspace-setup, preflight-tests and self-review, whose exit condition `self-review-check.sh` reads the records at HEAD; merge runs it in the refinery's run-tests at the merged head; review reads the records at the pinned commit through `review-evidence.sh`, which every review's gather runs, and a correctness review runs a suite through it when there is none. |
| `assets/scripts/rig-check-pre-existing.sh` | shared primitive | The one writer of `rig_check_pre_existing.<check>`: a caller's judgment that one recorded fail of a check, which the mark holds, is red on the base too and carried by a tracker. Work writes it in the self-review, so the loop converges past a failure the diff did not cause, and merge writes it in the refinery's handle-failures on the anchor at the merged head, so a review pinned there does not run the known failure again. |
| `assets/scripts/rig-check-lib.sh` | shared primitive | The one definition of whether a recorded fail is judged pre-existing: the bead's mark holds that very record at that commit and names a tracker. `self-review-check.sh` applies it to the work bead and `review-evidence.sh` to the anchor, so both judge a mark by one rule. |
| `assets/scripts/worktree-setup.sh` | shared primitive | Agent `pre_start` worktree creation, for the polecat, polecat-codex, refinery, and proactive templates. |
| `assets/scripts/gh-origin-guard.sh` | shared primitive | The `PreToolUse` hook every agent's provider runs ahead of a shell command: refuses a typed `gh` write aimed outside a repository the session owns, and an unmarked post on one it does own ([gh-origin-guard.md](gh-origin-guard.md)). |
| `assets/scripts/gh-origin-guard-codex.sh` | shared primitive | Agent `pre_start` for the codex-provider templates, polecat-codex, converse-codex and dog: registers the gh origin guard in the Codex home's hooks file, the one every Codex session reads. |
| `commands/scripts-dir` | shared primitive | `gc <binding> scripts-dir`, under the binding the city imports the pack as, prints the directory holding the pack's scripts, read from the pack gc loaded, so an agent calls a pack script as the pack's own copy rather than a checkout's, wherever the city imports the pack from. Every formula step, prompt, template fragment and skill that runs a pack script calls it through this command: a step with the `binding_prefix` it was poured with, a prompt or fragment with the binding it is rendered with, and a skill with `<binding>` for the agent to fill in. The `watch-dispatched-work` fragment writes `<binding>` too, because it renders into the keeper's prompt as well as the mechanik's, and the keeper's own binding names its sub-pack. |
| `assets/scripts/standing-kinds.sh` | shared primitive | The one definition of the standing kinds: the `task_kind` values of a record that is open, unrouted and unassigned by design and never closes. The liveness sweep, its precheck and its re-check (patrol) source it, and so does the proactive scan (visit), each to tell a standing record from work or input. The doctor checks `check-blocked-work-armed` and `check-hq-marooned-work` read it the same way. |
| `assets/scripts/dispatch-path.sh` | shared primitive | The one definition of a dispatch path: a `gc.routed_to` route or a `gc.dispatch_when_ready` arm. The proactive scan and sling (visit) source it to leave alone a bead whose dispatch is already decided. Patrol's doctor sweep runs `check-blocked-work-armed` and `check-step-terminal`, which source it to find work that no pass will dispatch. `placement.sh` asks it too, so every reader of the placement queue sources it. |
| `assets/scripts/placement.sh` | shared primitive | The one definition of a bead that waits for placement: it carries `placement=pending` and has no parent, route, arm, assignee or live pour. Visit lists those beads as the placement sitting's queue (`gc-helm.sh unplaced`), and its proactive scan files no first reaction for them. Patrol's liveness sweep and its precheck name them as a wait through the classifier, the claim-time re-check of a sweep visit names the same wait, and the doctor sweep's `check-blocked-work-armed` owes them no arm ([steering.md](steering.md)). |
| `assets/scripts/hold-lib.sh` | shared primitive | The one definition of a hold: an open `blocks` blocker on a bead or on one of its parent-child ancestors, where a demand gate on an ancestor does not count, and only a blocker of its own holds a bead in flight (one carrying a branch, a merge_result or a rejection_reason). Its walk reads a generation of ancestors per listing, so a reader judges any number of beads in a few reads. Work's deferred-dispatch pass sources it to sling an armed bead only when nothing holds it, and to name the blocker that does. Patrol's doctor sweep runs `check-armed-dispatch-owed`, which sources it so a held arm is not reported owed. Its `hold_annotate` reads the holds of a whole listing in a scratch directory of its own, and through it the refinery's find-work takes no bead something holds, the witness's `check-refinery` counts no held bead as stuck, and `check-refinery-patrol-live` ages no held bead as queue, so a landing bead waits with the refinery until its effort is done. |
| `assets/scripts/run-lib.sh` | shared primitive | The one reader of a workflow run's link to the bead it works: a graph.v2 root names its input convoy, which tracks the one bead the run works, and a classic molecule names its bead in its issue variable. Its verbs give the runs that work a bead, the run a root or an input convoy names, and every run in a store, each with its liveness, and a read that fails fails the verb. Each formula step derives its own bead with `gc convoy status`, Gas City's contract, and the pack's other readers of the link ask this file. `step-close.sh` finds through it the run a step closes in. In work, the work-context hook, the orientation read after a claim (`claim-context.sh`), the self-review check, the tree holder, the priority writer and the until consumer (through `live-work.sh`) read it. So do patrol's liveness sweep and doctor checks, review's gate repair, visit's proactive scan and the board's takeaway release and park survey (`gc-helm.sh`), the gascity-keeper pack's rebase check, and the blocker holder (`blocker-holder.sh`). The helm board's Go copy is tested against its fixture. |
| `assets/scripts/blocker-holder.sh` | shared primitive | Whether an automated actor holds the live blockers an anchor's merge waits on: a route, a claim or a live run (`run-lib.sh`) marks one, and a blocker routed to a person is theirs. Each writer of the machine verdict asks it, merge's `gctk merge` before it records `blocked` with cause `blocker`, and review's `gate-ensure.sh` before it replaces that verdict, so the writers cannot trade the verdict on every pass. |
| `assets/scripts/pr-post.sh` | shared primitive | The one writer of the city's PR posts, each carrying the provenance mark, and the owner of the definitions that tell feedback from the city's own post and from a post not for review ([not-for-review.md](not-for-review.md)), which reads the rig's declared markers from its repository's default branch, and a review thread whose feedback waits on the city's answer. Merge (`pr-open.sh`, `pr-facts.sh`), review (`signoff.sh`) and visit (`pr-visit-comment.sh`, `pr-dispose.sh`, converse sittings) post through it, and `pr-facts.sh`, `gctk merge`, `signoff.sh`, `approval-withdraw.sh`, `feedback-miner.sh` and `gh-origin-guard.sh` read its definitions. |
| `assets/scripts/gc-build.sh` | shared primitive | Builds each of the pack's compiled Go components out of band and records what it serves, so no caller builds in its own exec path. Visit runs it for the board's `helm-svc` through `orders/helm-build.toml`, probing the binary and restarting the service onto it, and merge runs it for `gctk`, the cadence's data plane, through `orders/gctk-build.toml`. |
| `assets/scripts/icu4c-cgo.sh` | shared primitive | The cgo flags every compile of `services/helm` needs on macOS, where Homebrew keeps icu4c off the default search path and Dolt's go-icu-regex needs its headers. Visit sources it for the helm-svc build (`gc-build.sh helm`), and merge sources it for the go vet in `tools/lint.sh`, which the gc-toolkit rig's lint command runs. |
| `assets/scripts/branch-end.sh` | shared primitive | Ends a retired bead's branch on the git remote, the way delete-on-merge ends a landed one: keeps a branch a live bead still names, pins the tip (the PR's `refs/pull/<n>/head`, or an annotated `archive/<branch>@<short-sha>` tag read back on origin), then deletes it at that tip. `bead-rehome.sh` runs it after every disposition close, so it serves that writer's callers for the same reason: converse (visit), and `pr-facts.sh`, `duplicate-sweep.sh` and `scaffolding-sweep.sh` (merge). Its origin write is granted in [authority-map.md](authority-map.md). |
| `assets/scripts/git-lib.sh` | shared primitive | The one read of a branch's head on a repository's origin: one `git ls-remote` for any number of branches, run in the repository the caller names, taking each head from the line for its exact ref, and failing rather than answering nothing when origin does not answer. Review (`gate-ensure.sh`, `signoff.sh`), visit (`converse-rework.sh`) and patrol (`liveness-sweep.sh`) source it for the same reason: the head a review is pinned to, or a branch's gates are resolved at. |
| `assets/scripts/rework-child.sh` | shared primitive | The one writer of a review- or ruling-sourced rework child, the fix unit that blocks an anchor while a worker resumes its branch. Review (`signoff.sh`, on a request-changes verdict) and visit (`converse-rework.sh`, on an operator ruling) file through it for the same reason, each passing its provenance as the child's source key and deciding the work order. The child is born carrying the PR-finishing shift and no parent, and is settled at its priority before it is slung ([steering.md](steering.md#pr-finishing-work)). |
| `assets/scripts/run-cancel.sh` | shared primitive | Ends a molecule's run through gascity's run cancel, which closes the root and every step that is not closed, so no pack script writes a molecule member. Work (`mol-polecat-work`'s declines), review (`mol-validate`'s), visit (`gc-helm.sh takeaway --release`) and patrol (the witness's orphan recovery, for a run whose root already closed) call it for the same reason: a run that should not continue. |
| `assets/scripts/molecule-hold.sh` | shared primitive | The name that step text from an earlier version of a formula calls to decline. A molecule keeps the step text it was poured with, so such a run still requires this script and calls it. It hands the call to `run-cancel.sh --step` unchanged and reads or writes no bead itself. Step text of `mol-polecat-work` (work), `mol-validate` (review) and `mol-rig-demo` calls it for the same reason: a decline. It goes once no open step bead names it. |
| `assets/scripts/live-work.sh` | shared primitive | The definition of live work, which no automated disposal may close: what a bead or its edges record when it is dispatched, worked, owned by another closer, parked, parented by a convoy, or holding an open child, and a live run that works it (`run-lib.sh`). `until-resolved.sh` sources it, so work's deferred-dispatch pass disposes only a pure wait its `until` targets resolved, and patrol's `check-until-resolved-owed` reports such a bead as a decision for a person rather than as a disposal the order failed to make. |
| `assets/scripts/until-resolved.sh` | shared primitive | Which beads an `until` edge has resolved. One listing of a store and one status read decide each open, unassigned candidate as waiting, unresolved, blocked by an open `blocks` blocker of its own, or owed, and a fresh read of one bead says whether it is still owed and free of live work. Work's deferred-dispatch pass disposes the beads it finds owed, and patrol's doctor sweep runs `check-until-resolved-owed`, which reports an owed bead that pass left undisposed, so the check reports what the pass does. |
| `assets/scripts/hand-back.sh` | shared primitive | Gives back a bead the calling session claimed, in one write that reopens it, clears its assignee and removes the session pins, made only while the bead shows that session's claim or none. A refused write leaves the claim as it was. Work hands a bead back through it at `mol-polecat-work`'s stop to ask a person about a bead with no molecule and at its store-only and auto_push=false exits, each with the route the bead rests on in the same write. Review's `mol-review` gives back through it a review held with no workflow whose record is short, clearing the route in the same write. |
| `assets/scripts/rig-map.sh` | shared primitive | The pack's one read of the rig map, `gc rig list --json`. It prints the listing, or exits 3 with the reason the listing did not read, under one bound that only cuts off a `gc` that never answers ([bead store resolution](bead-store-resolution.md#reading-the-rig-map)). The store resolvers, the board's verbs, the reapers and the doctor checks read rig paths, prefixes and suspension through it. |

### The placements worth arguing about

- **The operator surface is visit.** The board, the tmux bindings and pickers,
  and the web terminal exist so a human can reach the queue that subjects and
  visits hold. `services/helm` and `orders/helm-build.toml`
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
