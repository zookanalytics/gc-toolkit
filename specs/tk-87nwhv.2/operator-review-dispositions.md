---
name: Operator review dispositions — PR#795 (first-reaction enrichment proposal)
description: How each item of the operator review on PR#795 (review 5259610171) is dispositioned in proposal.md. One row per thread; the pointer names the section that carries the change or answer.
---

# Operator review dispositions — PR#795

Review 5259610171 on `specs/tk-87nwhv.2/proposal.md`. Each thread is answered by
a revision to the proposal or an in-thread answer; the force-push that carried
the revision marks the original threads outdated, so this table is the durable
map. Section names below are headings in `proposal.md`.

## Facet A — enrichment

| Comment | Ask | Disposition | Where |
|---|---|---|---|
| 4056200589 | `mol-validate-close` should validate and act on "close as duplicate" | Fixed. It is no-op-only today (escalates successor closes); the proposal extends its `validate-and-resolve` step with a duplicate arm that re-validates the claim and closes via `bead-rehome.sh --kind duplicate` | Close as duplicate: validate at the disposition, act through bead-rehome |
| 4056203005 | Discovery = scripted rules; intelligent validation = LLM at the close-as-duplicate disposition | Fixed. Split into cheap scripted discovery (candidates only) and LLM validation at the disposition | Discovery is cheap and scripted; the intelligent call is at the disposition |
| 4056207100 | Generalize confirmed-vs-likely edges; what does Gas City support, or just one `related` edge? | Answered. `bd` has no strength/confidence attribute — only `--type` — so one low-commitment `related` edge carries every likely link; hard actions go only through the path that owns their consequence | Confirmed versus likely: one soft edge, hard actions only through their owner |
| 4056209723 | Edge-writing isn't first-reaction-specific | Fixed. Writes go through one shared, store-pinned, same-store-guarded helper (`bead-link.sh`), not a first-reaction script | One shared edge writer, not a first-reaction-specific script |
| 4056219482 | Wire a low-commitment epic edge when confident; defer strong parent-child (not now, not never) | Fixed. Confident epic association wires a `related` edge to the epic; `parent-child` deferred | Epic association: a low-commitment related edge now, parent-child later |
| 4056220376 | Concern: script proliferation between enrich and something else | Fixed. Same shared edge-writer; no existing general writer to collide with — this creates the one | One shared edge writer, not a first-reaction-specific script |
| 4056221564 | Similarity is a candidate net, not the decider | Fixed. Reframed threshold as a tunable net for candidates; the LLM decides at validation | Discovery is cheap and scripted; the intelligent call is at the disposition |

## Facet B — coverage

| Comment | Ask | Disposition | Where |
|---|---|---|---|
| 4056212840 | `GC_PROACTIVE_SLING_CAP` goes away (sling = enqueue) | Fixed. Cap removed; enqueue is free, the pools are the real cap | Three bounds sit in the scan-to-sling path, and only one should stay tight |
| 4056213391 | Pool `max_active_sessions` remains as the processing cap | Fixed. Kept and named as the real processing cap | Three bounds … (bound #2) |
| 4056216381 | `SCAN_LIMIT` is an overload guard: safe batch per cadence | Fixed. Reframed exactly this way; now the single per-sweep bound | Three bounds … (bound #3) |
| 4056212510 | `SCAN_LIMIT` should go away — backlog handled | Answered / reconciled. Reconciled with 4056216381: backlog is fine to process, `SCAN_LIMIT` stays as the overload guard. Confirm-request left as open question 3 | Backlog is fine to process; Open questions (3) |
| 4056220671 | Backlog is fine, process away | Fixed. Backlog-ramp framing dropped; drains through normal cadence | Backlog is fine to process |

## Build plan

| Comment | Ask | Disposition | Where |
|---|---|---|---|
| 4056224506 | Don't split into 4 PRs; land incremental commits on one PR for holistic review | Fixed. Build plan is now incremental commits on one PR; cap-removal noted as separable if preferred | Build plan — incremental commits on one PR |

## Open questions returned for the dialogue

The revision resolves the four original open questions into the design and
raises three narrower ones (formula extension vs sibling, shared-helper home,
and the `SCAN_LIMIT` reading above) in the proposal's "Open questions" section.
