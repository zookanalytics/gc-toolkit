---
name: Inventory of every mechanism that represents work not moving
description: Every hold mechanism found in the gc-toolkit pack and the running runtime, with its writer, its clearer, whether it can clear without a person, the surface that displays it, and its owner. Measured against the live city on 2026-08-26. Read with assessment.md, which judges these rows, and proposal.md, which acts on them.
---

# Inventory of every mechanism that represents work not moving

Grounded in code and config read on 2026-08-26, and in a census of all five
bead stores in the `loomington` city taken the same day: 899 open or
in-progress beads, 637 of them non-step work beads.

"Not moving" means the bead is open and no worker will take it until something
outside the bead changes. Three questions separate the rows: what falsifies the
claim ("what clears it"), whether anything but a person can falsify it, and
whether any surface shows it.

## Method

The starting set came from the bead. It was checked against three enumerations
that are meant to be exhaustive and are not the same list:

- `lifecycle/lifecycle.toml` `[metadata.*]`, which the component model calls
  the registry of every key the pack writes (`docs/component-model.md` §4).
- The claim predicate in `docs/gascity-routing-model.md`, which is the read
  side: a mechanism holds a bead only by falsifying one of its terms.
- A live metadata-key histogram over all five stores, which finds keys no
  document lists.

The three disagree, and the disagreements are findings rather than noise.

## A. Dispatch holds — the bead is open and no worker is offered it

| # | Mechanism | Written by | Cleared by | Clears without a person? | Surface | Owner |
|---|---|---|---|---|---|---|
| A1 | `blocks` edge to an open bead | any actor, `bd dep add <blocked> <blocker>` | closing the blocker | **Yes.** Verified: `is_blocked` recomputes on close and the bead re-enters `bd ready` and the Tier-3 pool query in the same pass | `bd ready`, `bd blocked`, `merge.sh` blocker probe, helm `waitingEdges` | bd |
| A2 | `parent-child` edge under a **blocked** ancestor | any actor | unblocking the ancestor | **Yes**, but it is a cascade, not a wait this bead declared | `bd blocked` attributes the parent; nothing routes it | bd |
| A3 | `status=deferred` + `defer_until` | by hand | the clock | **Yes** | `bd ready` excludes; children of a deferred parent are dropped directly | bd |
| A4 | `status=blocked`, stored | by hand | **by hand only** | **No.** Verified with a paired control: with the identical `blocks` edge, the bead left `open` re-enters `bd ready` when its blocker closes and the bead set to `blocked` does not (`tk-puh9d`, open since 2026-08-02) | `bd list`; no board surface | nobody |
| A5 | `gc.routed_to` empty or absent | `gc sling`, the graph.v2 pour, `lifecycle.sh --route`, `gc-helm.sh takeaway --release`, the release path's step quiesce | any router stamping a route | **Yes** | `liveness-sweep.sh` classifies `routed-and-claimable` on its presence; `doctor/check-routed-work-claimable` | runtime, stamped by the pack |
| A6 | `gc.routed_to=human` | `lifecycle.sh` for the four human states (`assets/scripts/lifecycle.sh:172-174`), `signoff.sh` round-cap arm (`:308`) | **a person, by hand** | **No** | Helm board `human` anchor kind | pack |
| A7 | `assignee` held by a session | `gc hook --claim`, hand-doling | the worker's own done sequence; witness patrol on session death | **Partly.** A dead holder is recovered; a live-but-idle holder is not | `gc hook` Tiers 1 and 2, `liveness-sweep.sh` `worked` | runtime |
| A8 | `hold:mayor` / `hold:external` label | `bd set-state <bead> hold=mayor\|external` | `bd set-state` again | **No** | Every `gc hook` path in the gascity **source**, including `--claim`; the Tier-3 offer and the pool demand count. Not on this install, whose `gc` predates the commit that added the labels to the predicate | runtime, upstream (`beadmeta.DispatchHoldLabels`). No mayor agent exists in this city |
| A9 | `triage.hold` (+ `_at`, `_by`) | an agent or human at triage disposition (`assets/scripts/liveness-sweep.sh:371`) | **by hand** | **No** | `liveness-sweep.sh` classifies `held-by-design`; `liveness-recheck.sh:198` | pack convention |
| A10 | `gc.takeaway` (+ `_at`, `_by`) | `gc-helm.sh takeaway` | never cleared, by design | **No for the key.** The board re-derives around it from `blocks` edges instead | Helm `parked` and `ruled` rows | pack |
| A11 | `gc.dispatch_when_ready` (+ `_args`, `_armed_by`, `_armed_at`, `_reason`) | `deferred-dispatch.sh arm` | the `deferred-dispatch` reconcile order, once `bd list --ready` reports the bead ready; or `disarm` | **Yes** | `deferred-dispatch.sh list` | pack |
| A12 | `gc.session_affinity=require` | the graph.v2 pour | the release-path quiesce (`gc-helm.sh:220`) | Partly | none | runtime |

## B. Merge holds — the branch exists and will not land

| # | Mechanism | Written by | Cleared by | Clears without a person? | Surface | Owner |
|---|---|---|---|---|---|---|
| B1 | `check.<g>=green@<oid>` absent or stale | `signoff.sh` writes it; the head move stales it; `gate-ensure.sh` re-arms | a fresh green verdict at the live head | **Yes** | `merge.sh`, `pr-open.sh`, `doctor/check-gate-integrity` | pack, single writer |
| B2 | `check.<g>=fixable@<oid>` | `signoff.sh` | a head move stales every verb at once | **Yes** | same as B1 | pack |
| B3 | `check.<g>=exception@<oid>` | `signoff.sh` round-cap arm (`:303`) | a head move, which `gate-ensure.sh:391` re-arms into a fresh dispatch. At the cap nothing automated moves the head, because signoff files no rework there | **No in practice** | same as B1 | pack |
| B4 | `dispatch_count` at the dispatch ceiling (`GC_MAX_REVIEW_DISPATCHES`, default 5) | `gate-ensure.sh:636` | an operator unsetting the tally, named in the escalation | **No** | the dispatch-backstop visit and the `dispatch_backstop.<g>` stamp (`gate-ensure.sh:529-574`) | pack |
| B5 | `blocked_reason` | `lifecycle.sh transition --to blocked`, `signoff.sh` cap arm | nothing | **No.** It is prose | Helm row detail | pack |
| B6 | `merge_result` in a human state (`abandoned`, `retargeted`, `blocked`, `refused_false_completion`) | `pr-facts.sh`, `mol-refinery-patrol.toml` | **`human`**, declared as the writer of every outbound transition in `lifecycle/lifecycle.toml` | **No, by declaration** | `doctor/check-state-space`, Helm | pack |
| B7 | `merge_hold` | **no script, in this pack or gascity's.** Every value was set ad hoc by an agent | by hand | **No** | `merge.sh:207`, `pr-open.sh:191`, `gate-ensure.sh:404`, `convoy-graduate.sh:96` | unowned; registered at `lifecycle.toml:183` |
| B8 | `rebase_hold` | **no script, in this pack or gascity's.** Every value was set ad hoc by an agent | by hand | **No** | `pr-facts.sh:294`, `convoy-graduate.sh:112-116` | unowned; registered at `lifecycle.toml:183` |
| B9 | unclosed rework or review child | `signoff.sh`, `pr-facts.sh`, `gate-ensure.sh` | closing the child | **Yes** | `merge.sh:271` | pack |
| B10 | `tracking_only` | the filer of a tracking bead | not a wait — an opt-out that stops a bead counting as an in-flight holder | n/a | `merge.sh:263` | pack |
| B11 | `auto_push=false` producing `branch_ready` + `halt_reason` | the caller sets `auto_push`; `mol-polecat-work.toml:299` writes the halt | a person picking the branch up | **No** | bead notes only | pack |
| B12 | `false_completion_suspected` | `mol-refinery-patrol.toml:401` | nothing | **No** | Helm, via B6 | pack |
| B13 | convoy not graduated | `convoy-graduate.sh` gate: all members closed, at least one merge recorded, no hold and no branch veto | the last member closing | **Yes** | `convoy-graduate.sh` output | pack |
| B14 | `signoff_dismissed` | `signoff.sh:263` | not a wait — it records that a stale GitHub review was dismissed | n/a | none | pack |

## C. Attention markers that gate nothing

These are on the list because they are routinely read as holds. None of them
removes a bead from any queue.

| # | Mechanism | What it actually does |
|---|---|---|
| C1 | `escalation_key` + the visit bead | `escalate.sh` files one visit per subject and key, joined to the subject by a **`tracks`** edge (`assets/scripts/escalate.sh:89`). `tracks` is not a readiness-blocking type, so the visit gates nothing. The gate-visit block in `formulas/mol-visit.toml:54` carries the blocking edge as a commented-out suggestion |
| C2 | `sweep.new_ids`, `sweep.carried_ids`, `sweep.pass_at`, `visit.recheck`, `triage.last_seen`, `triage.scope` | liveness-sweep bookkeeping on the visit and the standing subject |
| C3 | `stall_root` | names the workflow root a visit is about; read by `liveness-sweep.sh:234` to classify a step as `conversing` |
| C4 | a `hold`-shaped label that is not one of the two canonical values | `holding`, `parked-conversation`, `parked-debt` are live in the city and are ordinary work to every query |
| C5 | `notes` prose ("do not start until X lands") | `docs/gascity-routing-model.md` calls this "the durable mitigation" for a graph.v2 dispatch, which it is: a worker reads it. No query does |

## D. Keys with no writer, and keys in no registry

| # | Key | Finding |
|---|---|---|
| D1 | `quiesce.terminal_since` | On 6 open beads across three stores. Its writer, `assets/scripts/quiesce-completed-workflows.sh`, was deleted at PR #465. `doctor/check-state-space` flags deleted healer keys but its regex does not cover this one |
| D2 | `promotion_hold`, `hold_reason`, `hold_flagged`, `hold_status_checked`, `triage.hold_superseded`, `gc.blocked_reason`, `check.codex.exception_escalated` | Seven keys on live open beads, none in `lifecycle/lifecycle.toml`. `gc.blocked_reason` is a near-twin of the registered `blocked_reason`. No check enumerates unregistered keys |

## What is actually in use

Counted over the 637 non-step open work beads, all five stores, 2026-08-26.

| Mechanism | Beads carrying it | Of those, also carrying an open `blocks` edge |
|---|---|---|
| `gc.takeaway` | 49 | 9 |
| `triage.hold` | 30 | 0 |
| `gc.routed_to=human` | 25 | 1 |
| `check.<g>=exception@` | 16 | 1 |
| `blocked_reason` | 15 | 1 |
| `dispatch_count` at or past the cap | 15 | 2 |
| `merge_hold` | 2 | 0 |
| `status=blocked` | 0 | — |
| `status=deferred` | 0 | — |
| `hold:mayor` / `hold:external` | 0 | — |
| `gc.dispatch_when_ready` | 0 | — |

96 beads carry at least one hold marker. 87 of them, 91%, carry no open
`blocks` edge at all.

The other direction is worse. The city files demands at scale and gates
nothing with them:

| Bead class | Open | Blocking at least one open bead |
|---|---|---|
| visits (`task_kind=visit`) | 54 | **0** |
| beads carrying `escalation_key` | 54 | **0** |
| `issue_type=decision` | 10 | **1** |

## Three rows that are easy to misread

**A1 converges, and that is measurable rather than assumed.** A work bead
carrying `gc.routed_to=<pool>` and a `blocks` edge to an open decision bead is
withheld from the exact Tier-3 predicate the pool runs. Closing the decision
puts it back in the offer set in the same pass, with nothing else written.

**A4 and A1 look identical and behave oppositely.** Both are "this bead is
blocked". One re-derives, the other is a stored string that outlives its
cause.

**C1 is the target model, missing one line.** `escalate.sh` already files a
demand bead, routes it to a human queue, dedups it by situation key, and joins
it to its subject. Every part of the shape is there except the edge that would
make the wait machine-answerable, and that edge is present in the source as a
comment.
