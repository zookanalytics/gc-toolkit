---
name: Component model — the primitives and the invariant→check binding
description: The design authority of gc-toolkit — the short list of primitives every component must justify itself against, the anchor lifecycle's shape as counts and writers, and every invariant bound to the doctor check that fails when it stops being true. Read it before adding a component, a state, or a metadata key.
---

# Component model

The primitive set, the anchor lifecycle's shape, and the invariant→check
binding. This is the document a new component must justify itself against; the
2026-08 rewrite (`specs/2026-08-rewrite/plan.md`) implements §1–§3.

## Scope

**Mandate.** Which primitives the pack is built from, the lifecycle's
single-writer discipline stated as counts, and every invariant bound to its
mechanical check.

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
- **One merge writer** — `merge.sh`, which re-reads the full authorization set
  immediately before merging. `--match-head-commit` pins the merge to a
  commit, but the anchor-local authorization set — `check.*`, `merge_hold`,
  `merged_target` — does not move the head; the pre-merge re-read is what
  catches a mid-pass write to any of them.

---

## 3. Invariants

Propositions, each true or false, each with the check that catches it going
false. **UNCHECKED** means the check does not exist and is filed as a bead.

| # | Proposition | Check |
|---|---|---|
| **I1** | Every dependency is recorded in the bead graph — no wait lives only in prose or a metadata string. | **PARTIAL.** Takeaway waits are edges (`gc-helm.sh takeaway --waiting-on`) and the liveness sweep re-derives stalled waits from the graph (`liveness-sweep.sh`); gate waits are head-bound markers by design. No total check; remainder tracked on tk-wz4igt. |
| **I2** | The state space is closed: every `merge_result` value and status combo is declared in `lifecycle/lifecycle.toml`, and a bead in a declared detached state rests unheld and offered to no pool. | `doctor/check-state-space` |
| **I3** | Every routed bead is claimable: route AND assignee name a live target, routed work is in `bd ready` or in `bd blocked`, and rig-scoped orders are bound. | `doctor/check-routed-work-claimable` |
| **I4** | Every PR has exactly one owning anchor, and every gating anchor is open. | `doctor/check-one-anchor-per-pr` (structural); `merge.sh` also refuses on sight, fail-closed |
| **I5** | No bead is closed while the work it represents is unlanded: closed anchor ⇒ `merged` + `merged_sha`, or an explicit terminal state. | `doctor/check-closed-implies-landed` |
| **I6** | Every gating anchor declares a non-empty `check_set`, and every marker is well-formed `verb@oid`. | `doctor/check-gate-integrity` |
| **I7** | A gate verdict was written by the one audited writer, `signoff.sh` — narrowed from the old provenance question by making the writer singular. | `doctor/check-gate-integrity` (marker form); the single-writer property is held by construction: `signoff.sh` contains the only code that sets a `check.*` value. The two other components that touch the key ([authority-map.md](authority-map.md)) only clear it, which cannot forge a verdict |
| **I8** | Every step bead reaches a terminal state: no open step under a closed root, no frontier stalled past its bound. | `doctor/check-step-terminal` |
| **I9** | A molecule executes the formula text that is current when it runs. | `doctor/check-pour-text-current` (tk-5w3boh): a checkout lagging past the reconciler's self-heal window, an unfetched remote-tracking ref (the fail-open case, where the naive behind-count reads 0), and a live molecule poured before its formula last changed. Detection, not prevention — step descriptions still freeze at pour while the rig checkout advances on a 15-minute cooldown. |
| **I10** | Every pack order fires within its declared interval. | `doctor/check-cadence-live` |
| **I11** | Every claimed step is being advanced: a step in a claimed state is held by a running session that is still producing output. | `doctor/check-claim-advancing` (tk-beecuu): reported when nothing can be advancing it — no assignee, an assignee naming no session, a holder that is not running, or a holder whose `last_active` is past the bound. Holder-clocked, so it is silent for a session that is genuinely working however long the step takes. I8 is the complement: bead-clocked, holder-blind, and scoped to open steps. |

Two further checks guard structure that is not an anchor invariant:
`doctor/check-config-bound` (every prompt, overlay, and fragment the pack names
resolves in the composed config) and `doctor/check-seed-audit-current`
(generated-artifact freshness; warn-only when absent). That is the whole set:
**11 checks, each asserting a live structural property** — none greps the
source for a past fix.

---

## 4. How to use this

- **Adding a component** — it must answer column 3 of §1. If it cannot, it is
  a repair pass for a writer that should be fixed instead.
- **Adding a state** — declare it in `lifecycle/lifecycle.toml`, name its
  writer in [state-machine.md](state-machine.md)'s table, or it does not
  exist.
- **Adding a metadata key** — it is state. Register it in `lifecycle.toml`, or
  accept that nothing downstream can be proven exhaustive over it.
- **Adding an invariant** — name its check in the same PR.
- **Divergence** — there is no divergence section: the running system is
  generated from the declarations this model requires, so divergence is zero
  by construction. If you find the ledger disagreeing with this document, one
  of the ten checks is missing a case; fix the check, not the prose.
