---
name: Gas City search for the work record on pack closes that ship nothing (tk-69fbuxr)
description: What tk-69fbuxr read in Gas City before six pack closers began recording gc.work_outcome=no-op on the plain task beads they close, why the reason Gas City gives for its work-record gate holds for those beads, and what the 2026-11-24 census of unrecorded closes found. Read it when judging how a pack closer answers the work-record gate, or a proposal to have Gas City skip such beads instead.
---

# Gas City search for the work record on pack closes that ship nothing

Gas City was read at `gastownhall/gascity` main d6d5784f9c (2026-11-24). Its
work-record gate, `internal/workrecord/gate.go`, has not changed there since
e64788cb84 (2026-10-10), and the city's gc 1.4.3, built from the fork's
03d08fa593, carries the same file. bd is the city's 1.3.4.

## The need

Six pack closers close a plain task bead that ships no commit under its own
id, and none of them recorded `gc.work_outcome`:

- `bead-rehome.sh` closes a bead disposed of onto a successor;
- `effort-bring-current.sh` closes the refinery's hand-off once an integration
  effort's branch is current;
- `reconcile-rig-checkouts.sh` closes a rig's reconcile subject once the rig
  fast-forwards;
- `mol-rig-demo` closes its demo request once the clip is delivered or
  reported;
- the gascity-keeper sub-pack's `mol-upstream-gc-sync` closes its drift report;
- its `mol-upstream-gc-rebase-rework` closes the rework bead under each
  classification.

Gas City's work-record gate warns on each of these closes, and with
`GC_WORK_RECORD_ENFORCE` set it refuses them. At backlog refinement on
2026-11-24 the operator ruled, as tk-69fbuxr's notes record, that the pack
writes `gc.work_outcome=no-op` where it closes a bead that was never work,
rather than waiting for Gas City to skip such beads.

## What was searched

| Primitive | What it gives | How it bears on the need |
|---|---|---|
| `workrecord.Gated` (`internal/workrecord/gate.go:76`) | The gate's population: a bead whose type is empty or `task` and that carries no `gc.kind`, `gc.step_id` or `gc.step_ref` | Each bead above is a plain task with none of those keys, so the gate reads its close. Each exempting key names something these beads are not. `gc.kind` marks a control or structural bead that the dispatch engine closes, and the other two mark a workflow step. Writing one to earn the exemption would misdescribe the bead to every Gas City reader of that key |
| `workrecord.ValidateOnClose` (`gate.go:95`) | The record: `gc.work_outcome` is shipped, no-op, blocked or abandoned, and only shipped needs `gc.work_commit` and `gc.work_branch`. The others "carry their reason in the close-reason" | Gas City's vocabulary already holds the answer for a task that ships nothing, `no-op`, with the close reason or note as its explanation. The change composes it |
| `vetoReadyProjectionWorkOutcomes` (`internal/beads/ready_projection_work_outcome.go:39`) | A blocker closed with `gc.work_outcome=blocked` does not satisfy its dependents | `blocked` would hold whatever waits on the closed bead. So an infeasible rework records `no-op`, and its reason rides its classification and close |
| `bd close` (flags `--reason` and `--reason-file`) and `applyWorkRecordUpdateMetadata` (`cmd/gc/work_record_gate.go:364`) | `bd close` takes no metadata. A `gc bd update` that closes has its own `--set-metadata` arguments applied to the bead before the gate judges it | Where the close is an update, as in `bead-rehome.sh` and `mol-rig-demo`, the record rides that one write. Where a closer keeps `gc bd close` for its close reason, a metadata update just before it writes the record, and the gate reads the stored bead at the close |

## The reason Gas City gives, tested here

`Gated` says the contract "applies to worker-claimable work units — plain task
beads", and the package says a work bead's close "must leave a typed,
machine-checkable record of what the work produced". Each bead these closers
close is a task a worker claims, or one the pack files as a task for a worker
or a person. The hand-off is filed `-t task` and assigned to the refinery
(`skills/work/integration-effort.md`). The reconcile subject is filed `-t task`
by `reconcile-rig-checkouts.sh`. A disposed bead, a demo request, a drift
report and a rework bead are each the work bead of a claim. What each produced
under its own id is nothing, which the vocabulary spells `no-op`. The reason
holds here, these closes show no fault in Gas City, and no fix at the source is
owed for them.

## Measured

On 2026-11-24 at 08:55Z, every bead closed since 2026-11-10 in the city's seven
stores was listed with
`gc bd --rig <rig> list --status=closed --closed-after 2026-11-10 --limit 0 --json`,
and the HQ store with `GC_RIG` unset. The beads in the gate's population that
carry no `gc.work_outcome` were sorted by what each closer leaves on the bead:
a close reason `Brought … current with …` for `effort-bring-current.sh`, a
`Disposition <time>:` note for `bead-rehome.sh`, a `reconcile_rig` key for
`reconcile-rig-checkouts.sh`, a `rig-demo:` note for `mol-rig-demo`, and a
`report_file` key, or a `classification` key beside a `rebase_bead` key, for
the keeper's two formulas.

| Closer | Gated closes with no work record |
|---|---|
| `effort-bring-current.sh` | 30, all in gc-toolkit's store |
| `bead-rehome.sh` | 17: 10 in gc-toolkit's store and 7 in three other rigs' stores |
| `reconcile-rig-checkouts.sh` | 3 |
| `mol-rig-demo` and the keeper's two formulas | 0. None of them ran in the window |

The other unrecorded gated closes in the window come from closers this change
leaves alone:

- 100 are the landing order's close of a merged bead
  (`merge_result=mr_merged`), which the open #1678 gives the shipped record.
- 1,529 are the old review path's reviews (940), findings (405) and validation
  passes (184). tk-1tfzr71.122 retires that code, so AGENTS.md's rule 1 gives
  it no new work, and the retiring beads' notes name each of its closes.
- 12 are closes agents made by hand.
- 2 are Gas City's own: core's `mol-polecat-report` closing an effort's summary
  task, and core's `reaper.sh` closing a stale task. Neither writes a work
  record, so Gas City's gate warns on Gas City's own closes. That gap is
  upstream finding tk-45igtbm.
