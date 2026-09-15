---
name: tk-45jao — gc hook --claim false no_work on an unreachable store
description: Why tk-45jao's fix lives in the gascity binary (gc-9o705), the corroborated mechanism, and why there is no gc-toolkit-side code remedy.
---

# gc hook --claim false no_work/drain on an unreachable store

tk-45jao reports that `gc hook --claim --json` answers

    {"schema_version":"1","ok":true,"command":"hook","action":"drain","reason":"no_work"}

when the beads store is unreachable. A polecat that honours it runs
`gc runtime drain-ack` — every done-sequence's terminal — and the reconciler
reaps the session, stranding any remaining step beads pinned by
`gc.session_affinity=require`. The response carries `ok:true` and an
affirmative `reason=no_work`, so there is nothing to shape-validate: a caller
cannot tell "the pool is empty" from "the store could not be read."

## The fix is in the gascity binary, not this pack

`gc hook --claim` is a Go command in the gascity repo
(`github.com/zookanalytics/gascity`). gc-toolkit carries Go modules of its own
under `services/` (`services/gctk`, `services/helm`), but no gc-toolkit code
or behavior surface decides the `gc hook --claim` response, so there is no
pack-local code remedy. The binary-side fix is filed as **gascity gc-9o705**,
which carries the full mechanism, the patch sites by symbol, and the missing
test.

The polecat's *reaction* to the response is governed by the agent doctrine, a
prompt, not code. tk-45jao states plainly that an agent distrusting the answer
"is not a control," so the doctrine is not the fix either.

## Mechanism (summary; full detail in gc-9o705)

The reachable-vs-empty decision is made purely on the work-query subprocess
exit code. Read at gascity f09d38557:

- `shellWorkQueryWithEnv` (cmd/gc/cmd_hook.go:901-936) returns `(string(out),
  nil)` for any exit-0; when stdout is empty that becomes `("", nil)`, and the
  child's stderr is discarded on the success path.
- `workQueryHasReadyWork` (cmd/gc/cmd_hook.go:1003-1024) maps empty / `[]` /
  `null` to "no ready work."
- `bestStoreWithWork` (cmd/gc/hook_cross_store.go) returns a nil error when the
  primary answered exit-0-empty, so `claimHookWorkWithRunner` skips its
  protected error branch (cmd_hook.go:678-688) and falls through to
  `writeHookClaimNoWork` (cmd_hook.go:727).

So an unreachable store that answers exit-0-empty — a bd client printing the
breaker message to stderr while exiting 0, or the disk-full bd shape (exit 0,
empty stdout and stderr) — mints a false `no_work` drain. The
`federatedPrimaryFailed` guard (hook_cross_store.go:380-382) and the
returned-error path are already fail-closed; they only miss the exit-0-empty
shape. The store-unavailability sentinel `isBreakerOpenError`
(cmd/gc/beads_provider_lifecycle.go:90-97) exists but is never reached from the
hook path, and `doRuntimeDrainAck` (cmd/gc/cmd_runtime_drain.go:778-804) acts
unconditionally.

## Distinct from the sibling reports

- **tk-d8q7s** — a disk-full `bd` returns empty stdout with a success-shaped
  exit. That is the bd-side root; it is one of the ways an exit-0-empty read
  reaches the hook, and a reachability probe on the hook's empty path (proposed
  in gc-9o705) would also close it there.
- **gc-jkxrc** — the work query *times out*; a timeout surfaces as a Go error,
  which the returned-error path already handles. Different failure shape.
- **gc-ycww6** — `existing_assignment` answers with identifiers only. Same
  family (a hook negative a status-only caller cannot classify), different
  branch.

## Why there is no gc-toolkit regression gate

The honest pack-side deliverable here is this record plus gc-9o705, not a test.
A pack test that asserts the fixed behavior would fail until gc-9o705 lands, and
`tools/run-tests.sh` auto-discovers every tracked `*.test.sh`, so a
red-until-fixed test breaks the suite for everyone. No gc-toolkit surface
decides the hook response, so there is nothing pack-local to defend in code.
