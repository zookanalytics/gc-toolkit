---
name: gctk — promote the merge-cadence cluster from shell to one Go binary
description: How gctk began. lifecycle and merge moved from shell into one Go binary beside services/helm, built and deployed the way helm-svc is. The port contract this record once scoped, one subcommand per script behind an identical CLI, is replaced by docs/gctk-architecture.md, which states the shape gctk is built to and which pack logic moves into it.
---

# gctk: the compiled data plane

Status: **port contract replaced.**
[docs/gctk-architecture.md](../../docs/gctk-architecture.md) states the shape
gctk is built to, which pack logic moves into it, and the rules a move follows.
A move carries only an intent that survives the migration onto Gas City,
deletes the shell it replaces, and keeps no test that holds two copies equal,
so the remaining one-subcommand-per-script ports this record scoped are not
built. The
build and deploy pattern below is still how the binary is built and served.

`services/gctk` is the binary's source, and `services/gctk/README.md` carries
the operating detail and states everything the binary holds.

`lifecycle` and `merge` moved into the binary, and neither keeps a shell
fallback. `lifecycle.sh` and `merge.sh` only exec the binary, and a call with no
binary to run exits 1 naming the `gctk-build` order. The two rules the merge
shares with shell readers, the required-check set (`pr-facts.sh`) and the
approval rule (`review-verdict.sh`), are held to gctk merge's own by
`merge.test.sh`, which runs both over the same fixtures.

## Build and deploy

Same pattern as helm-svc, same lessons, same script: a `gctk-build` city order
runs the builder helm-build runs (`assets/scripts/gc-build.sh gctk`), with its
cooldown, staleness by `find -newer` and by the recorded revision, atomic
publish, and no build in the exec path. The launcher resolves the prebuilt
binary. With no binary to run, `lifecycle.sh` and `merge.sh` refuse the call
and name the build order, and a build that fails keeps the last good binary
answering.

**Failure-mode tradeoff, stated:** a script edit is live from the working
tree instantly; a gctk change rides the build order (~5m) and a broken build
keeps the *last good* binary serving the cadence. Slower iteration, but no
accidental live surgery on merge logic — `doctor/check-cadence-live` already
catches a cadence that stops firing, and a `gctk version` mismatch row is
added to it.

**Surfacing the seam (operator ask, 2026-08-24):** the build order writes a
small status file under the service state root (`built_at`, `source_rev`,
`binary_rev`, `last_build_rc`, `restart_pending`), and `helm-svc` reads it
per render into a pack-health status row on the board — so a stale or broken
build is visible where the operator already looks, not only in a doctor run.
The same file covers the helm binary itself (the dashboard-staleness problem
that has bitten before). Cheap: one JSON file written atomically by the
build order, one read in the gather, one row in the web UI and `board` CLI.

## Why Go and not Python

The repo already carries the Go precedent (services/helm), the build-order
pattern, and a static binary answers host variance. Python keeps the
stringly-typed CLI seams, adds interpreter/venv variance to every order exec,
and answers neither the sharing problem nor deploy as cleanly.

## Out of scope

Linking the beads library directly (changes the observability and permission
surface); porting anything agents paste; a shared shell library (rejected by
measured decision, unchanged); rewriting services/helm.

The helm and gctk builders are not a shared library. They are one script,
`assets/scripts/gc-build.sh`, parameterised by component, so the build logic
they have in common exists once and no library carries it.
