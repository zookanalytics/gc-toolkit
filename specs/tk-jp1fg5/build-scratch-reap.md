---
name: Build and test scratch reclaim — tk-jp1fg5
description: Why the build and test scratch that killed or crashed runs leave behind needs its own reaper, and why that reaper gates on a live holder and a dead pid rather than on age or size. The design record for the build-scratch-reap order.
---

# Build and test scratch reclaim

Bead: `tk-jp1fg5`. It delivers `orders/build-scratch-reap.toml`,
`assets/scripts/build-scratch-reap.sh`, and the script's co-located test.

A build or test run writes scratch into the host's shared temp: the Go
toolchain's `go-build*` and `go-link*` trees, the gascity `gc.test` binary's
per-run trees (`gct<pid>-<n>`, `gct-<pid>-<n>`), the build scripts' Go scratch
(`run.<pid>` under `/var/tmp/gotmp`), and the templated tool temp every pack
script allocates (`gctk-<producer>.XXXXXX`). A run that exits normally removes
its own on an EXIT trap. A run that is killed or crashes skips that trap, and
its scratch is left behind.

Nothing else reclaims it. The accumulation is a standing floor under the per-uid
tmpfs quota, and exhausting that quota is a city-wide outage, not a disk
problem: past it every command that prints fails with empty output while silent
ones still succeed, so the host loses its shells at once and nothing in the
failure names the cause. This reaper is the backstop. It is complementary to any
change that routes temp off tmpfs onto `/var/tmp`: that moves the leak to the
root filesystem rather than ending it, and the reaper covers whichever directory
the temp path resolves to.

## The safety model: a live holder, never age or size

An entry is removed only when nothing holds it. A single `lsof` snapshot of
every open path on the host — file descriptors and working directories — decides
it: an entry is held if a process has it open, has a file inside it open, or has
its working directory inside it. For the pid-named forms (`gct<pid>-<n>`,
`gct-<pid>-<n>`, `run.<pid>`) a dead pid is also required, `/proc/<pid>` gone.
Both gates are re-checked against a fresh snapshot immediately before the remove,
because the gap between proving an entry dead and removing it is a race.

Age and size are never a signal. A multi-gigabyte `gc.test` tree minutes into a
live run holds a lock file and is kept; a tiny tree whose owner died is reaped.
Trusting size or age would eventually remove a large, slow, live run.

The pid parse fails closed. A name that looks pid-encoded but whose pid is empty
or not all digits is unparseable and is left alone — reading `/proc` with an
empty pid names the `/proc` directory itself, which exists, and would class every
entry as alive. Only our own entries are considered: an entry owned by another
uid is not ours to reclaim, and bounding to our uid is also what makes an empty
`lsof` result mean idle rather than unreadable. An `lsof` that returns nothing at
all is a broken probe, not an idle host, and the pass refuses to remove anything.

## What the reaper does

`orders/build-scratch-reap.toml` runs `assets/scripts/build-scratch-reap.sh`
hourly, `scope = "city"`, no LLM and no agent. The scratch roots are per-uid and
shared by every rig on the host, so one pass serves them all; the script takes a
per-uid `flock` as well, so a second dispatcher cannot double the sweep. Nothing
it removes belongs to a bead, so a pass skipped, cut short, or run twice costs
only the reclaim the next pass takes instead.

The default roots are `$TMPDIR`, `/tmp`, `/var/tmp`, and `/var/tmp/gotmp`,
de-duplicated and skipped when absent. The build scripts already sweep their own
`run.<pid>` on each build; this reaper is the backstop for when builds go quiet.

## What it does not touch

Rebuild-cost caches — `/tmp/.pnpm-store`, `/tmp/node-compile-cache` — are left
alone: they match none of the scratch patterns and are excluded by name as well.
Evicting them under quota pressure is not implemented; the reaper reclaims dead
scratch, which is the accumulating cost. The Claude Code session scratch under
`claude-<uid>` belongs to `scratch-reap.sh` (docs/scratch-reclaim.md), which ages
it by session liveness, a different model from this reaper's holder gate.

## Operating it

```bash
assets/scripts/build-scratch-reap.sh --dry-run   # the plan, remove nothing
assets/scripts/build-scratch-reap.sh             # reap, one summary line
assets/scripts/build-scratch-reap.sh --verbose   # name each entry and why
assets/scripts/build-scratch-reap.sh --root DIR  # scan DIR (repeatable)
```

`BUILD_SCRATCH_REAP_LOCK_DIR` overrides the lock location (default
`$XDG_RUNTIME_DIR/gc-build-scratch-reap` or `/tmp/gc-build-scratch-reap.<uid>`),
and `--no-lock` skips the lock for a one-off run.
`assets/scripts/build-scratch-reap.test.sh` is the regression suite, hermetic
against a synthetic root in a tempdir with real `lsof` and `/proc` — no city, no
network, no `gc`.
