---
name: Raw-route first reaction
description: How the proactive first reaction works now — a raw-routed subject a pool worker claims and reacts to from its prompt, and where close-with-successor evidence lives. Read it to understand why there is no mol-first-reaction formula and no gc.proactive_reaction or duplicate_of marker.
---

# Raw-route first reaction

The proactive pool does first-level triage: it routes a bead to a worker, the
worker reads it, writes a card, and disposes of it. That flow no longer pours a
workflow. The pool routes the subject bead RAW — `gc.routed_to` and nothing
else — a worker claims it with `gc hook --claim`, and the worker's prompt is the
reaction method. Closing a bead with a successor is one writer's job for every
actor, gated by evidence that writer re-establishes itself.

## Why raw route rather than a formula

Core's dispatch model is one workflow per bead. A pour stamps
`gc.execution_routed_to` on the work bead and core never clears it from a work
bead (`restampWorkBeadRouting`, gascity `internal/sling/sling_core.go`). A first
reaction is a workflow on a bead that is NOT that bead's work, and then wants the
bead dispatchable again — which core has no verb for. Every piece of machinery
around the old reaction faked one: a re-offer guard, a second marker, a
route-stamp instead of a sling to dodge the double-convoy guard, three step beads
plus `workflow-finalize` and a drain choreography per reaction, and phantom
demand from orphaned steps.

The route half already worked without a formula: a bare `gc.routed_to` stamp is
what a pool's find-work offers, and `agents/proactive/agent.toml`'s `work_query`
and `scale_check` are already `gc bd ready --metadata-field "gc.routed_to=$target"
--unassigned` queries that drop graph.v2 structural beads — topology roots and
formula steps — so a plain task/bug/feature/spike passes. So the reaction becomes
a raw-route worker and all the pour machinery retires.

## The model, and where each part rests

- **Entry.** `tools/gc-proactive.sh sling <bead>` issues `gc sling --no-formula
  <rig>/gc-toolkit.proactive <bead> --reassign` — Lane 1, `gc.routed_to` only
  (`tools/gc-proactive.sh` `cmd_sling`, the `set -- … --no-formula` line).
  `--no-formula` is load-bearing: the city's `default_sling_formula` is
  `mol-polecat-work`, so a bare sling would pour that formula instead of leaving
  a raw routed claim. `sling_first_reaction_guard` refuses a bead already
  carrying `gc.first_reaction` (`tools/gc-proactive.sh` `sling_first_reaction_guard`).

- **Claim + reaction.** The pool worker's `gc hook --claim` returns the subject
  (assignee = the worker, `in_progress`), and `agents/proactive/prompt.template.md`
  is the method: read `gc bd show` + `tools/gc-bd-universe.sh slice`, fetch on
  demand inside the `⟦ UNTRUSTED DATA … ⟧` fence, write the CARD (Understanding ·
  Found · Proposal · Decision needed · Disposition) to notes, dispose through
  `first-reaction-dispose.sh`, drain. Kept: one bead per reaction, the ≤140-char
  takeaway, mr-only for any code, `gc.origin=operator` forces `ruling`. Two
  re-offer cases: a subject whose notes carry a `# First reaction` card but no
  `gc.first_reaction` (a session died before disposing) is disposed per the
  card's `## Disposition` line without a second card; a subject already carrying
  `gc.first_reaction` is released untouched and drained.

- **Dispose.** `assets/scripts/first-reaction-dispose.sh` has four exits, each a
  release write plus one core operation. `actionable` releases to a pool;
  `blocked` writes a `blocks` edge and optionally arms a deferred dispatch;
  `ruling` files the gate-visit routed to `human`; `superseded` (the fourth,
  `--successor <id> [--kind fixed-upstream|duplicate]`) runs `bead-rehome.sh
  --check` FIRST (the `CHECK_ERR="$("$REHOME" --check …` line), and on refusal
  exits 4 with the reason and no writes so the reaction takes `ruling` instead;
  on pass it records `gc.first_reaction*`, releases with `--no-wait` and no route,
  then closes through `bead-rehome.sh` (the `"$REHOME" --origin … --kind … --note`
  line). Only `fixed-upstream` and `duplicate` are offered here; the judgment
  kinds are a `ruling`.

- **The close rule: evidence in one writer.** `assets/scripts/bead-rehome.sh` is
  the single close-with-successor writer for every actor and enforces the evidence
  itself (`gates_pass`). For ALL kinds: the pointer (`gc.superseded_by` + `_store`)
  is stamped and read back before the close; the origin carries no unlanded work
  (`merge_result` empty/absent or `merged`); the origin is not a review, step, or
  workflow bead; the origin is not `in_progress` under another actor; and it is
  not already pointed at a different successor. For `fixed-upstream`/`duplicate`
  additionally: the successor resolves in the SAME store and is closed or
  `work_outcome=shipped`, and the origin did no work — `gc.work_outcome=no-op`
  (accepted even beside a rebase/rework twin's leftover branch) or no
  `work_outcome` and none of branch/work_dir/gc.work_dir/pr_number/pr_url/
  merge_result/gc.work_commit. `--check` evaluates those gates and exits 0/1
  writing nothing; the repair path over an already-closed origin skips them.

- **Every actor uses that writer.** A polecat whose subject another bead already
  resolved stamps `gc.work_outcome=no-op` and calls `bead-rehome.sh --kind
  duplicate|fixed-upstream`; on refusal it escalates. A work bead closes only
  through `merge.sh` (recorded `merged_sha`) or `bead-rehome.sh` (the evidence
  above) — `docs/authority-map.md` "Close a work bead (anchor)" and
  "Close-with-successor" carry both.

## What retired

`formulas/mol-first-reaction.toml`; `assets/scripts/duplicate-sweep.sh` and its
test (its evidence gates moved into `bead-rehome.sh`, and its `duplicate_of`
backlog was 0); the `gc.proactive_reaction` marker (`gc.first_reaction` is the
one disposition record, so `gc-helm.sh takeaway --release` no longer stamps a
second one); the `duplicate_of` marker (`pr-stack.sh`'s ledger drops a no-op
duplicate by `gc.work_outcome=no-op` now, the same signal the polecat stamps);
and the merge cadence's duplicate-sweep arm (`refinery-reconcile.sh`, so pr-stack
is arm 7). `gc.disposition_kind` never landed and is introduced nowhere.

## What stays

`gc.first_reaction*` (the one disposition record), `gc.takeaway*`,
`first-reaction-dispose.sh` as the one disposition writer, `deferred-dispatch.sh`,
the scan precision filter, `deliverable`, the operator-origin rule, the
gate-visit block (which moved from the retired formula into the prompt, still
swept by `gate-visit.test.sh`), and `gc-helm.sh takeaway --release`.

## Verified at this head

- `gc sling --no-formula` exists in the running binary ("suppress default
  formula (route raw bead)"), mutually exclusive with `--formula`/`--on`.
  Lane 1 writes `gc.routed_to` and nothing else (`docs/gascity-routing-model.md`).
- `agents/proactive/agent.toml` `work_query`/`scale_check` are raw-route
  `gc bd ready --metadata-field "gc.routed_to=$target" --unassigned` queries,
  dropping graph.v2 structural beads — workflow/scope/spec roots and formula
  steps (any of gc.step_ref/gc.step_id/gc.root_bead_id) — so a plain task/bug
  passes but neither a topology root nor a live molecule step can be claimed as
  a first-reaction subject. `tools/gc-proactive.sh` (`scan_precision_filter`,
  `exclude_graph_structural`) mirrors the same clause.
- Nothing in the pack writes `duplicate_of` (`git grep 'set-metadata duplicate_of'`
  is empty), so retiring its reader strands no live population.
- `agents/converse/prompt.template.md` already requires the same no-work evidence
  before a close (`merge_result` empty/absent or `merged`, `gc.work_outcome=no-op`
  or no work-product key, unassigned, not a review/step/workflow bead), so moving
  the gates into `bead-rehome.sh` matches its documented contract rather than
  changing it.

`specs/tk-diqxx9/first-reaction-triage.md` remains the record of the prior
three-exit triage design; this document is what is true after the raw-route
change.
