# gc-next

**Brand:** the gc-toolkit core pack rebuilt from the ground up on bare Gas
City primitives — a native roster, no example-pack import, conversations as
continuation groups, patrols as self-continuing chains on disposable
sessions.

This tree is the Phase-3 implementation of the rethink recorded in
[`specs/2026-08-rethink/`](../../specs/2026-08-rethink/) (read `outcome.md`
for what this pack must deliver and `spec.md` for the design it implements;
`implementation-notes.md` records the trace table, port status, and
deviations). The beliefs it serves are
[`docs/foundation.md`](../../docs/foundation.md); the composition rules it
obeys are [`docs/architecture.md`](../../docs/architecture.md).

## The roster (six roles, zero residents)

| Role | Brand |
|---|---|
| `wright` | Builds one bead's output on its own branch and hands off to gating; it never lands, never closes a unit that merges. |
| `lander` | The single writer of merged-truth: drives every gating anchor through its check-set and performs the merge, and is the only thing that targets the protected boundary. |
| `sentry` | Runs one health-patrol cycle — orphans, queues, sessions, stores — files what it finds, executes bounded repairs, files the next cycle, and drains. |
| `converse` | Holds a subject bead's conversation for the operator: rebuilds the slice, preps, holds, writes the outcome to the subject, closes only the turn. |
| `outrider` | Meets a newly filed bead before the operator does: reads its universe, writes the first-reaction card, flags it onto the board, and drains. |
| `thread-ops` | An operator-spawned parallel line of judgment — it acts and dispatches on the operator's behalf but owns no inbox, no patrol cadence, and no system-of-record identity. |

## Installing (staging)

A rig opts in explicitly; nothing in the live gc-toolkit pack loads this
tree:

```toml
[rigs.imports.gc-next]
source = "<path-to-gc-toolkit-checkout>/packs/gc-next"
```

Then verify with `gc doctor` (the `check-nx-*` suite) and confirm the
chain-anchor order seeded the patrol chains. Cutover stages, including when
this pack takes the `gc-toolkit` name, are `specs/2026-08-rethink/spec.md`
§9.

## Ports in progress

Carried doctrine whose mechanical port from the live pack is still pending
is enumerated in `assets/scripts/PORTS.md` and
`specs/2026-08-rethink/implementation-notes.md` — nothing is lost silently
(outcome O5); the sources live in this same repository until cutover
stage 5.
