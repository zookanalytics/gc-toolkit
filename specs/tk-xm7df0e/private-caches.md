---
name: Caches of a capture's own — tk-xm7df0e
description: Where a demo capture in the sandbox keeps npm's and Go's caches, what that costs a copy's start as measured on the city's host, why a capture that keeps the sandbox refuses an iOS app, what the change leaves, and the Gas City search behind the surface it adds. Read it when judging the sandbox's cache rules, a copy's cold start, or the iOS refusal.
---

# Caches of a capture's own

Bead: `tk-xm7df0e`. It builds on the sandbox profile of PR #1636
(`tk-m3pdftm`), which shut the home folders to a capture but opened npm's cache,
the engine's (`~/Library/Caches/sprintshow`) and Go's module and build caches
there for writing. The agents' own builds and tools read those caches outside
the sandbox, and on the city's host every agent home links `Library/Caches` and
`.npm` to the user's, so one capture could plant code that a later build or
`npx` outside the sandbox runs.

## What a cold start costs

Measured on the city's host on 2026-11-23, at load 12 to 45, before anything
was built:

| Run | Warm shared caches | Empty private caches |
|---|---|---|
| The gc-toolkit board's copy: `go build ./services/helm/cmd/helm-fixture`, which needs no module outside the repository | 1 s | 4 to 5 s, 115M of build cache |
| Gas City's `gc`: `go build ./cmd/gc` with brew's icu4c in `CGO_CPPFLAGS` | 33 s | 57 s, 2.3G of build cache; modules over the network add about 6 s and 1.9G |
| The published engine: `npx --yes @zookanalytics/sprintshow --help` | 1 s | 4 s, 82M |
| A whole page capture of the board through this branch's library and gctk, with `--serve` | | 13 s at load 24 |

The shared Go build cache was 316G in 1.1M files, so seeding a run's cache by
copying it is out. Seeding Go's module cache read-only through
`GOPROXY=file://<shared>/cache/download` saved about 6 s on `gc`, and would
open the agents' module cache, private modules included, to every capture, so
the change does not seed.

## What the change does

- A run inside the sandbox keeps npm's and Go's caches in a directory of its
  own, which `npm_config_cache`, `GOCACHE` and `GOMODCACHE` name, in place of
  any value the session gives them. The directory lies under `TMPDIR`, which
  the profile does not shut, and the library refuses one that lies in a home
  folder or one of the city's directories.
- `demo_engine_cli` makes the directory and removes it once the run ends.
  `demo_engine_sandboxed` cannot, because the shell becomes the command, so
  `gctk rig serve`'s leader makes one for each copy, names it in
  `DEMO_ENGINE_CACHE_DIR`, and removes it once the copy's group has ended. It
  makes each directory writable first, since Go leaves its module cache
  read-only, and follows no symbolic link.
- The profile opens no cache in a home folder: not npm's, not Go's, not the
  engine's. A run still reads each Node on `PATH`, Playwright's browsers, and
  Go's root and settings there.
- A capture that keeps the sandbox refuses an iOS app, before Appium is
  provisioned. The engine drives one through the Appium it keeps in its cache,
  and Appium 3.9, the version the engine pins, refuses to start from a home it
  cannot write ("must be writeable for the current user account"), measured
  under a profile that denied writes there. Its manifest, which it writes in that
  home, names the path each driver loads from, so no write into that home is
  safe while captures with no sandbox, such as an iOS rig's, run the same Appium.
  Only gc-toolkit and Gas City keep the sandbox in this city, and neither has an
  iOS app.

## What it leaves

- A run or a copy killed before it can remove its directory leaves it under
  `TMPDIR`, as any killed run leaves a templated temp name, for the host's own
  cleanup (docs/scratch-reclaim.md, "What it does not touch").
- The temp folders stay open to every run in the sandbox, so one capture can
  write into another's caches while both run. What it plants there runs only
  inside the sandbox.
- Other processes' arguments and environment stay readable, as
  docs/demo-capture-sandbox.md says. The operator's choice on that is
  `tk-cqr413h`.

## Gas City search

The change adds one key to the contract between `gctk rig serve` and the
pack's sandbox library: `DEMO_ENGINE_CACHE_DIR`, the directory a copy's caches
go in. It adds no metadata key, bead kind, lifecycle state, order or formula
step.

Gas City ships no sandbox for a command and no directory of its own for a
process's caches. At `gastownhall/gascity` 97c0c9b3b1 (2026-11-23),
`docs/reference/trust-boundaries.md` says the commands it runs "are a feature,
not a sandbox". The private `HOME` and `TMPDIR` it gives bd's inventory walk
(`bdWalkScratchDir` in `cmd/gc/bd_inventory_trust.go`) is internal to that walk,
with no surface a pack composes. A copy's lifetime is already `gctk rig serve`'s
own, and the orphan sweep that ends a copy whose session has ended
(`sweepProcessTableOrphans` in `cmd/gc/session_beads.go`) ends the leader with
it. So the leader owns the directory.

The library's new input stays in shell because the library composes the
sandbox's profile and the environment the sandboxed tools start with, which is
configuration of other tools, sandbox-exec, npm and Go, of the kind AGENTS.md
holds gctk inappropriate for. The directory's lifetime for a copy is in gctk, in
Go.
