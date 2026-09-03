---
name: Assessment of the city's hold mechanisms against the convergence rule
description: Judges every mechanism in inventory.md against the rule that a bead is either ready or blocked on a named bead by an edge, verifies the three structural constraints against the running binaries rather than the claims, and separates the legitimate mechanisms from the redundant ones and from the same idea under several names.
---

# Assessment

Judged against the rule the bead states:

> A bead is either ready, and therefore moving, or blocked on a named bead by
> an edge. There is no parked state. What a person owes is itself a bead, and
> closing it makes the dependent work ready.

The verdict on the rule itself comes first, because it decides how much of the
rest is a redesign and how much is enforcement of a decision already taken.

## 1. The rule is already this pack's doctrine

It is not a new proposal. Three documents in `docs/` state it, and one states
it almost word for word.

`docs/lifecycle-composition.md` opens its rule section with "A wait is a graph
edge, re-derived on every read. A conclusion is prose, stored once and never
cleared. Never the reverse," and gives the reason: "A sentence freezes at the
moment it is written and is never true again."

`docs/component-model.md` §1 lists the graph edge as a primitive and states
the cost of not having it as "a wait becomes a sentence, and nothing can
re-evaluate a sentence." Its discard list rejects "free-form metadata as the
state space" and "prose-carried design."

`docs/component-model.md` §3 carries the rule as invariant **I1**: "Every
dependency is recorded in the bead graph — no wait lives only in prose or a
metadata string." I1 is marked **PARTIAL**, and the remainder is tracked on
`tk-5r1a12`, a bead that proposes the missing `check-wait-is-an-edge`.

So the rule stands, and the question this bead was filed to answer is narrower
than it looks: not whether to adopt it, but why a rule the pack already
publishes is false on 91% of its own held beads.

The answer the measurements give is that I1 has no check. Every other
component-model invariant names a doctor check that fails when it stops being
true, and §3 says so in its one rule: "An invariant with no named checker is
marked UNCHECKED and filed as a bead. Prose is what rots." I1 and I9 are the
two without one. I9 has since acquired `doctor/check-pour-text-current`. I1 is
alone.

One refinement to the rule, and one addition, are argued in §5.

## 2. The three constraints, verified

The bead asks that these be weighed rather than assumed away, and that the
third be checked against the current binary rather than trusted. All three
were run against the live tools on 2026-08-26: `bd` v1.2.2
(`62d211937bd3`), `gc` v1.4.1 (`6a013fc272a8`), in a throwaway store, never
the live city.

### Constraint 1 — beads refuses a `blocks` edge from a parent to its own descendant

**Confirmed, and the refusal is the rule being enforced rather than an
obstacle to it.**

```
$ bd dep add pb-jf2 pb-6py -t blocks
Error: pb-jf2 cannot be blocked by its descendant pb-6py: blocked status
cascades to descendants, so pb-6py would inherit the block and never close
```

The message names the mechanism. The blocked flag cascades **down**
`parent-child` edges, so a parent that blocks on its own child strands that
child, and the child can then never close, so the parent can never unblock.
The refusal is beads declining to build a deadlock.

That matters more than the refusal itself, because the deadlock does not need
the refused edge to happen. Verified separately: a child of an open,
**unblocked** parent is offered normally; the moment the parent acquires a
`blocks` edge to anything at all, the child leaves `bd ready` and appears in
`bd blocked` attributed to its parent.

So the constraint generalises past the case the bead names:

> **A bead that will ever carry a `blocks` edge must have no `parent-child`
> children.** Containers do not block; blockers do not parent.

Any proposal that keeps routed work as a child of a subject that will ever
wait is wrong whether or not the edge that expresses the wait is accepted.
This is a stronger reason for the replacement shape than the refusal is.

The replacement shape was verified end to end. With a container `G` and two
children `S` and `W`, the edge `S` blocked-by `W` is accepted, `W` stays
ready, `bd blocked` names the blocker, and closing `W` returns `S` to `bd
ready` with nothing else written.

### Constraint 2 — `gc sling` pours immediately and reads no `blocks` deps

**Confirmed at source.** In the gascity tree the running `gc` is built from,
`internal/sling/` contains no read of blocker state in any non-test file. The
only occurrence of the word "blocked" outside tests is a comment about the
workflow root's own finalize dependency. The only dependency-graph walk on the
sling path is `DetectCycle` (`internal/sling/sling_core.go:114`).

The scope of this constraint is narrower than it is usually quoted, and the
narrowing is what makes the proposal cheap.

An edge does not gate the **pour**. An edge does gate the **claim**: Tier 3 is
a `bd ready` read, and a routed bead with an open blocker is not offered and
does not count as pool demand. Verified against the exact Tier-3 predicate,
`--exclude-label` flags included.

So "an edge does not hold work" is true only of the formula-dispatch path,
where the routed record is a freshly minted workflow root that carries none of
the work bead's dependencies. On the stamp-a-route path, the edge is the gate
and it already works.

### Constraint 3 — "`bd ready` returns only parentless beads"

**False as reported.** `bd ready` returns children.

| Parent state | The child |
|---|---|
| open, unblocked | is returned by `bd ready` |
| blocked by an unrelated open bead | is not returned, and `bd blocked` lists it with the parent named as its blocker |
| unblocked again by that bead closing | is returned by `bd ready` again, with nothing else written |

The true rule is the one `docs/gascity-routing-model.md` already documents:
having a parent is not disqualifying, having a **blocked** ancestor is. A
closed parent does not exclude; an open, unblocked parent does not exclude; a
deferred parent excludes its children by a separate path.

This is not a third structural reason edges are insufficient for children, and
it should not be carried into the proposal as one. The real constraint is
Constraint 1's generalisation, which is about the cascade, not about parentage.

## 3. Judgment, mechanism by mechanism

Four verdicts. **Legitimate**: a wait a machine can resolve. **Redundant**:
correct, but a second name for a mechanism already in the list. **Prose**: a
watcher persisted to the database, requiring a person to return and read a
sentence. **Residue**: no writer, or no registry.

| Mechanism | Verdict | Reasoning |
|---|---|---|
| A1 `blocks` edge | **Legitimate.** The reference mechanism | Converges with no person; every reader honours it; `bd blocked` explains it |
| A2 `parent-child` cascade | **Legitimate as an effect, never as a hold** | It is not a wait the bead declared. Using it deliberately is the stamp-and-parent deadlock |
| A3 `deferred` + `defer_until` | **Legitimate**, narrow | The clock is a machine. Correct only when the wait really is time |
| A4 `status=blocked` stored | **Prose in a status field** | Verified not to clear when its cause clears. It is `blocked_reason` with better camouflage |
| A5 empty `gc.routed_to` | **Legitimate as absence of a decision; prose when used as a hold** | Nothing distinguishes "not yet routed" from "deliberately withheld" |
| A6 `gc.routed_to=human` | **Prose** | Names a role, never a person, never a task, and nothing closes a role |
| A7 `assignee` | **Legitimate for a live claim; prose for a stale one** | Session death is recovered. A live-but-idle holder is indistinguishable from a working one |
| A8 `hold:mayor` / `hold:external` | **Not this pack's mechanism** | Gascity-binary claim-predicate terms (`beadmeta.DispatchHoldLabels`). No mayor agent exists here, this install's `gc` predates their arrival in the predicate, and one closed bead city-wide has ever carried either. See §6 |
| A9 `triage.hold` | **Prose.** The clearest case in the city | 30 live beads, zero with an edge. Its own disposition list at `liveness-sweep.sh:371` offers "park (the edge IS the park; prose parks nothing)" one item above it |
| A10 `gc.takeaway` | **Legitimate as a conclusion, prose when used as a hold** | The 140-character authored headline is the right primitive and should be kept. `--waiting-on` is the half that converges, and it is optional |
| A11 `gc.dispatch_when_ready` | **Legitimate** | The one mechanism built specifically to converge, and in live use. See specs/tk-gtgn0/verification.md |
| A12 `gc.session_affinity` | **Legitimate**, runtime-owned | Not a wait about the work |
| B1 `green@` stale | **Legitimate** | Head-bound by construction: a head move stales every verb at once, so a fixed branch re-evaluates fresh |
| B2 `fixable@` | **Legitimate** | Same head-binding, plus a child in flight, which is B9 |
| B3 `exception@` | **Legitimate in shape, prose in effect** | Head-bound like B1: a head move re-arms it. But the cap exists precisely to stop dispatching the work that would move the head, so nothing automated ever produces the move |
| B4 `dispatch_count` at the ceiling | **Prose** | A separate bound from B3: it counts dispatches that left no verdict, where B3 counts attempted rework. It holds the merge and only an operator unsetting the tally ends it |
| B5 `blocked_reason` | **Prose**, and correctly so as a record | It is a conclusion, and `lifecycle-composition.md` says a conclusion is prose and is never cleared. Its defect is being the *only* record of the wait |
| B6 human `merge_result` states | **Prose by declaration** | `lifecycle.toml` names `human` as the writer of every outbound edge. Honest, and unbounded |
| B7 `merge_hold`, B8 `rebase_hold` | **Prose**, and the same class as B5 | Five fail-closed readers, no writer in any pack: every value was set ad hoc by an agent, and the readers distinguish only empty from non-empty. 2 open, 16 closed. See §6 |
| B9 unclosed rework or review child | **Legitimate** | An edge, honoured by `merge.sh`, converging on close |
| B10 `tracking_only`, B14 `signoff_dismissed` | **Not holds.** Correctly classified out | Scoping markers |
| B11 `auto_push=false` halt | **Prose** | `branch_ready` plus `halt_reason` describe a state, name no successor, and nothing reads them |
| B12 `false_completion_suspected` | **Prose** | A finding, not a wait |
| B13 convoy graduation gate | **Legitimate** | Derived from member state per pass |
| C1 escalation visit on a `tracks` edge | **Legitimate demand, missing its gate** | The bead exists, is routed, is deduped, and holds nothing |
| C5 `notes` prose | **Prose**, and currently load-bearing | Recommended by `docs/gascity-routing-model.md` as the durable mitigation for a graph.v2 dispatch, because that path reads no edges |
| D1 `quiesce.terminal_since` | **Residue** | Writer deleted at PR #465; six live beads still carry it |
| D2 seven unregistered keys | **Residue** | `docs/component-model.md` §4 says an unregistered key is not pack state. Nothing enumerates them |

## 4. Redundancy: which of these are one idea

The list is shorter than it looks. Five clusters cover almost every prose row.

**"A person owes something and nothing names what."** A6 `gc.routed_to=human`,
A9 `triage.hold`, A10 `gc.takeaway` used as a hold, B5 `blocked_reason`, B6 the
four human `merge_result` states, B11 `halt_reason`, B12
`false_completion_suspected`. Seven mechanisms, one shape: a string on the
waiting bead describing a demand that is not itself a bead.

**"The review loop gave up."** B3 `exception@` and B4 `dispatch_count`. Two
bounds on the same loop, in two vocabularies, on the same bead, by two scripts.
They were one number until `signoff.sh` stopped reading `dispatch_count` and
each bound got its own ceiling, which is the right split: a review that leaves
no verdict is a different failure from a rework that does not converge. What
remains shared is the ending. Both terminate in a held merge that only a person
resumes, and neither names what is waited on.

**"Do not dispatch this yet."** A4 stored `blocked`, A5 cleared route, A8 hold
labels, A11 arming, and a `blocks` edge. Five ways to fall out of the claim
predicate. Only two converge, and one of those two has zero uses.

**"The operator pulled a brake."** B7 and B8. Genuinely one mechanism at two
scopes.

**"A conclusion was reached."** A10's takeaway text and B5's `blocked_reason`.
Both are prose, both should stay prose, and neither should be the record of the
wait. This cluster is legitimate and is not a target.

## 5. Two refinements to the rule

The rule as stated is right. Two things it does not say need saying, because
both were measured and both would defeat a literal reading.

**A cross-store edge is accepted, reported as success, and holds nothing.**
`bd dep add` on a target in another rig's store returns
`✓ Added dependency`, exit 0. The row is stored, but the bead stays in
`bd ready`, and `bd dep list --json` omits the edge entirely, so every stdout
parser sees no wait. A warning about a target with no row in this database may
still be printed, on stderr, in both the human-readable and the `--json` form;
it is not on the channel a consumer reads. Every automated consumer, including
`gc-helm.sh takeaway --waiting-on` and the helm board's `waitingEdges`, sees
no edge at all. So the rule holds **within a store**, and a cross-store demand
needs a different representation or a demand bead filed in the waiting bead's
own store. This is live: `tk-gdtgvr` repairs gascity beads from a gc-toolkit
agent, and the city-scope mayor ledger sits in a different store from every
rig.

**An edge-blocked bead leaves the only pass that audits for stranded work.**
`liveness-sweep.sh` classifies over `gc bd ready --unassigned`, so a bead with
an open blocker is not in its funnel at all and can never be reported as an
unnamed wait. Today that is correct: an edge-blocked bead has named its wait.
Under the target model it becomes the dominant state, and a demand nobody ever
answers would be invisible to the one mechanism that exists to notice
stranded work. The rule needs a companion clause: **a demand bead is itself
subject to the sweep, and an unanswered demand ages.** Converting holds to
edges without this trades a visible stall for an invisible one.

## 6. The question that turned out not to be one

Every judgment above follows from code or from a measurement. One was drafted
from an assumption instead, and the assumption was wrong.

B7 `merge_hold` and B8 `rebase_hold` were judged **legitimate as an operator
brake**, on the reading that the operator sets them by hand to stop a merge.
The operator's answer at PR #485 was that they do not, and the code agrees:
five readers, no writer. The pack reads the keys at `merge.sh:206`,
`gate-ensure.sh:402-406`, `pr-open.sh:188-191`, `pr-facts.sh:289-294` and
`convoy-graduate.sh:96` / `:112-116`, registers them at
`lifecycle/lifecycle.toml:183`, and sets them nowhere. Gascity's pack does not
mention either key at all. Every value present was written ad hoc by an agent.

The values say what the mechanism really is. Eighteen beads have carried one
across the five stores, sixteen closed and two open, and the set of distinct
values is `true`, `false`, `operator-gated-graduation`,
`rework-anchor-gate-bypass`, `signoff-cap-reached`, and a paragraph on
`tk-aezem4` ending "Held by refinery pending operator disposition of visit
tk-4g98t". Every reader treats `""`, `false`, `0` and `null` as not held and
anything else as held, so the only machine-readable content in the field is
whether it is empty. The rest is a sentence for a person to read.

The corrected verdict is **prose**, the same class as B5 `blocked_reason`, and
it is a good example of the defect this evaluation is about: `tk-aezem4` names
its successor in the text, and no reader can act on the name. B7 and B8 need
the conversion every prose hold needs, not an exemption. The five fail-closed
readers are worth keeping either way.

A8's `hold:mayor` and `hold:external` are a different matter and are not this
pack's mechanism. They are `beadmeta.DispatchHoldLabels` in the gascity binary
(`internal/beadmeta/hold_labels.go`), terms of the gascity claim predicate. No
mayor agent exists in this city, and this install's `gc` predates the commit
that added the labels to the predicate, so they exclude nothing here today
(`docs/gascity-routing-model.md:41`). Across the five stores exactly one bead
has ever carried either label, `gc-vbkys` in gascity, closed, and no open bead
carries one. Their widest-coverage property is real upstream and dormant
locally.

So no operator ruling is owed by this evaluation. The decision bead it filed,
`tk-shxtwm`, is withdrawn, and `tk-whufad` is rescoped and unblocked.
`proposal.md` §4 records the disposition.

## 7. Verdict

Not a redesign. The rule is the pack's published doctrine, the converging
mechanism exists and is proven, the demand-bead primitive exists and is filed
54 times over, and the shape constraint has a verified answer.

What is missing is that nothing requires the edge. Every path that files a
demand offers the edge as an option and defaults to prose:
`gc-helm.sh takeaway --waiting-on` is a flag, `mol-visit.toml`'s blocking edge
is a comment, `deferred-dispatch.sh arm` is opt-in at every call site. Optional
convergence is what 87 prose holds and 54 gateless demands measure.
