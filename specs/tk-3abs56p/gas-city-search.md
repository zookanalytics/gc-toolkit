---
name: Gas City search for a copy's record of how its serve command runs
description: The search the arch check asks for on recording, for a copy of a rig's app that gctk rig serve runs, whether its serve command runs inside the capture sandbox, and on the report key and the variable that carry that record. Read it when deciding whether the record can move onto something Gas City ships.
---

# Gas City search for a copy's record of how its serve command runs

A copy of a rig's app that `gctk rig serve` runs decides once, as its serve
command starts, whether the command runs inside the capture sandbox. A capture
that keeps the sandbox for the copy's checkout now refuses a copy that does not
run inside it. The change adds three pieces of surface for that:

- `sandboxed`, a file in the copy's record directory, which `gctk rig serve`
  keeps under the clone's git common directory. `demo_engine_sandboxed` in
  `demo-engine-lib.sh` writes `true` or `false` into it before the serve
  command starts.
- `sandboxed`, a key in the line `gctk rig serve` prints for a running copy,
  which carries that file's value.
- `DEMO_ENGINE_SANDBOX_RECORD`, the variable through which gctk's host adapter
  names that file to `demo_engine_sandboxed`.

The record has to come from the run that decides, and it has to exist before
the copy can be up, because the setting the decision reads can change while the
copy starts. The arch check asks what Gas City ships for such a record
([review-arch.md](../../docs/review-arch.md)).

## Where the search looked

Read on 2026-11-19 at upstream `gastownhall/gascity` `main` 7b5614ac70:
`docs/`, `engdocs/`, `cmd/` and `internal/`, for `sandbox`, `isolation`,
`seatbelt` and `sandbox-exec`, and for the metadata a runtime keeps on what it
runs, then each hit in its context. The sandbox search of
[tk-0u56zqw](../tk-0u56zqw/gas-city-search.md), read at 3764de45ea, still
holds. Of the 8 commits since, the one whose diff names a sandbox adds a gate's
evidence note about Bazel's test sandboxing.

## What Gas City ships near the need

- **Session metadata.** `runtime.Provider`'s `SetMeta`, `GetMeta` and
  `RemoveMeta` keep "runtime-owned state keyed by session name"
  (`internal/runtime/runtime.go`, and the Runtime Operations and Invariants of
  `engdocs/architecture/session.md`). It is the record for a session a runtime
  provider starts. A copy is no session: gctk's leader starts it on the host,
  as a process group of its own, for a capture or a sitting, and it has no
  session name to key a value by. Running each copy as a session would hand
  the controller a process that no agent config declares and nothing
  reconciles.
- **Bead metadata.** A bead carries keys, which `gc bd update --set-metadata`
  writes (the Beads entry of [API](https://docs.gascity.com/reference/api),
  `docs/reference/api.md`). A copy has no bead. Its record is one host's
  process state, kept beside its pid, port and app URL, and a stop removes it
  with the copy. A bead would keep, in a store that outlives the copy, a value
  that is true only while the copy runs.
- **Events.** `gc events` reflects the supervisor's event API
  ([gc events Output Formats](https://docs.gascity.com/reference/events),
  `docs/reference/events.md`). An event says that something happened. A
  capture would have to find the copy's last event to learn what the copy's own
  record holds, and no event ends when its copy ends.
- **The orphan sweep.** `sweepProcessTableOrphans` in `cmd/gc/session_beads.go`
  reads a process's environment to end it once its session has ended, and a
  copy already composes it (the header of
  [serve.go](../../services/gctk/internal/rig/serve.go)). It reads nothing of
  how a process runs.
- **The trust model.**
  [Trust Boundaries](https://docs.gascity.com/reference/trust-boundaries)
  (`docs/reference/trust-boundaries.md`) says Gas City runs the commands a city
  configures as "a feature, not a sandbox". Gas City has no sandbox for such a
  command, so it has no record of one.

Gas City ships no record of how a process that an agent's tool starts runs.
The copy's record stays gctk's, beside the values it already keeps for the
copy, and the decision it records stays the library's
`_demo_engine_keeps_sandbox`, which a capture's own run also makes.
