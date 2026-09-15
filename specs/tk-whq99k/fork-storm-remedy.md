---
name: gc-toolkit fork storm — where the durable remedy lives and the first increment
description: Maps the per-command gc→bd fork surface behind the doctor fork-rate advisory, places both named durable remedies in upstream binaries outside this rig, and scopes the one ownable first increment — porting gctk's gcbd read seam to the in-process beads library that helm already ships.
---

# gc-toolkit fork storm remedy (tk-whq99k)

**Bead:** `tk-whq99k` — doctor `fork-rate` advisory, filed by the deacon-findings patrol (`finding.key=doctor-fork-rate`).
**Surveyed:** 2026-09-15.
**Status:** One ownable first increment recommended and filed as `tk-qsp74l`. The larger levers are mapped and left for the operator to fund, because both durable remedies live upstream and the dominant in-repo fork source is a large program, not a single increment.

## Recommendation

The two remedies the finding names — an embedded DoltLite backend and an in-process bead store — both live in binaries this rig consumes but does not build (`bd`/`github.com/steveyegge/beads`, and the gascity `gc` supervisor). gc-toolkit cannot land either from its own tree.

What gc-toolkit does own, and what `services/helm` has already proven, is the in-process beads library. The bounded first step toward the in-process store is to move gctk's read seam (`internal/gcbd.Show`) off `gc bd show` and onto an in-process `beads.OpenFromConfig` read, mirroring `services/helm/internal/source/beads.go`. Its direct fork reduction is small — gctk forks `gc bd` at exactly two sites — so its value is not the fork count. It is a beachhead that establishes the in-process store in gctk behind an existing seam, and it forces one measurement the operator needs before funding anything larger: what the Dolt / go-mysql-server dependency stack costs a binary that today has zero dependencies.

Everything past that increment — the 377-site shell surface, the two upstream remedies — is named below and deferred.

## What the finding reports

The `fork-rate` check is advisory and warns at 100 forks/s. This bead recorded 240 forks/s at first sight and 955 forks/s on its one recurrence about an hour later. The check's own diagnosis: a high fork rate, not CPU work, inflates the load average, because the load average counts runnable and uninterruptible tasks; a fork storm reads as high load while the CPU is far from saturated.

The finding attributes the storm to the per-command data plane and asserts that `gc`, `bd`, and `dolt` dominate the fork count while the agents are a rounding error. That per-source split is not derived here: confirming which process forks how often needs a root `bpftrace` on `sched:sched_process_fork`, deferred to the operator checklist below. What the code does establish is the direction — every bead operation in this rig forks a `gc` process — and the shape of the surface that produces it.

One correction to the finding's wording. It says "gc forks bd.real per command." `bd.real` does not exist anywhere in this repository; the bd/bd.real shim convention is not used here. The in-repo mechanism is `gc bd`: a compiled subcommand of the external gascity `gc` binary, which resolves the store and then reaches `bd` (`github.com/steveyegge/beads`), which connects to a long-lived per-rig Dolt server.

## The fork surface, from the code

Every bead read or write in this rig goes through `gc bd`. A linter enforces it (`tools/lint-learned.d/raw-bd-invocation.sh`: a shell script reaches the store through `gc bd`, never by running `bd` itself). The surface has two very different halves.

**The shell half is the storm.** 377 `gc bd` call sites across 54 non-test scripts in `assets/scripts/` alone, before counting `tools/`, `packs/`, and the doctor checks that loop `gc bd` per rig. The heaviest single scripts are `gc-helm.sh` (79), `pr-facts.sh` (34), `signoff.sh` (27), `gate-ensure.sh` (20), and `finding.sh` (18). Each site is a fork of `gc`, and the hot ones run on every patrol, sweep, and review. This half is the dominant fork generator, and no in-process Go library reduces it: a shell script forks a process to read a bead no matter what gctk links.

**The gctk Go half is tiny.** The entire `services/gctk` tree has exactly two `exec.Command` calls, both in `internal/gcbd/gcbd.go`: `Show` runs `gc bd show <id> --json` (`gcbd.go:111`) and `Update` runs `gc bd update <id> …` (`gcbd.go:133`). Every gctk bead operation funnels through this one package; its callers are all in `internal/cli/lifecycle.go` (`Show` at :97, :369, :532, :642, :673; `Update` at :524, :666). The package header calls itself "the `gc bd` subprocess seam" and states the original intent: gctk shells out to `gc` exactly as the shell scripts it replaces did, rather than linking the beads library.

**bd talks to a long-lived Dolt server, not a fresh Dolt per call.** The store runs a managed per-rig `dolt sql-server` in server mode (`.beads/config.yaml` carries `dolt.mode: server`, the standing state that `tk-4lxad` documents). `bd` connects to it over the AD-04 port chain. A cold store auto-spawns a server, but in steady state the Dolt process is persistent, so the reducible per-command forks are the `gc` and `bd` processes, not `dolt`.

## Both named durable remedies live upstream

- **Embedded DoltLite backend (no per-city dolt sql-server).** This is a backend of the beads library / `bd` (`github.com/steveyegge/beads`), which this rig consumes as an external binary and pins only in helm's `go.mod`. Changing bd's backend is an upstream change.
- **In-process bead store (no gc→bd fork per command).** For the shell callers, the `gc` process they fork would have to read beads in-process instead of reaching `bd`. That is the gascity `gc` binary. `services/helm/internal/source/beads.go:31-34` states the same boundary from the other side: of the two sanctioned data paths, only the in-process library is buildable from this repository, because "the supervisor is the `gc` binary, which lives in the `gascity` rig."

So the whole-storm fix is upstream advocacy plus a large in-repo shell-to-Go migration. Neither is a single fundable increment, which is why the bounded deliverable is the beachhead below.

## The in-process bead store already ships — in helm

`services/helm/internal/source/beads.go` reads bead state through the in-process beads library, opening each rig's `.beads` store the way the `bd` CLI does, with no fork of `bd`:

- It imports `github.com/steveyegge/beads` (`beads.go:16`) and opens the store with `beads.OpenFromConfig(ctx, beadsDir)` in `openLibraryStore` (`beads.go:141`), the library's config-respecting entry point that honours the rig's Dolt server-mode settings.
- Handles are opened lazily and kept for the process lifetime (`beads.go:50-57`): reconnecting to Dolt on every read would be slow and needless churn against a store the whole city shares.
- It honours the data-access contract — reads go through the library, never raw Dolt: "There is no `sql.Open("mysql")` and no `JSON_EXTRACT` here — the library owns the connection, exactly as it does for every `bd` invocation" (`beads.go:43-46`).
- The test seam is a Go fake, not a PATH stub: `beadStore` is narrowed to four methods "to keep the seam testable with a fake" and the opener is injectable via `withStoreOpener` (`beads.go:88-104`).

The cost is visible in the module graph. helm's `go.mod` carries 172 require lines including `dolthub/go-mysql-server`, `dolthub/dolt/go`, and `dolthub/driver/v2`; helm's own README records that the module "went from zero dependencies to ~170 (the Dolt / go-mysql-server stack)." gctk's `go.mod`, by contrast, declares the module, `go 1.26.5`, and nothing else — no `require` block, no `go.sum`.

## First increment: port gctk's gcbd read seam in-process (tk-qsp74l)

Move `gcbd.Client.Show` off `gc bd show` and onto an in-process `beads.OpenFromConfig` read, behind the unchanged `Show(id) *Bead` signature, mirroring helm's `openLibraryStore` and its process-lifetime handle cache. Keep `Update` forking `gc bd` for now: the wrapper adds `BD_EXPORT_AUTO=false`, an rc=4 auto-import-fallback signal, and a bead-id allowlist that blocks `--force`, so the write path is a separate increment with its own care. Move the tests from the PATH stub to an injectable fake, as helm does.

This is the "smallest first increment toward the in-process bead store" the finding's disposition asked for, and it is de-risked by a working sibling. Be honest about what it is and is not:

- It removes both the `gc` and `bd` forks for gctk's own read path, but that path is two low-frequency call sites, not the storm.
- Its real product is the measurement that gates every larger step: gctk binary-size delta, `go build` wall-time delta, module-count delta, and a before/after fork count on the read path. Those numbers tell the operator whether a zero-dependency binary should take the Dolt stack, which is the same question any future in-process migration of the shell surface must answer first.

`tk-qsp74l` carries the scoped task and its acceptance evidence.

## The larger levers (named, not filed)

The bounded deliverable is one increment, so these are mapped here rather than filed as half-formed beads:

- **De-fork the shell surface.** The 377-site shell half is the dominant source. Removing its forks means either a long-lived bead-read daemon the hot scripts query over a socket, or migrating the hottest paths (`gc-helm.sh`, `pr-facts.sh`, `signoff.sh`) into in-process Go services on the gctk/helm pattern. Both are large and unproven; the tk-qsp74l measurement is the input that decides whether the Go-migration path is worth it.
- **Embedded DoltLite backend (upstream).** A `bd`/beads-library change, an upstream send, not a gc-toolkit bead.
- **In-process gc→bd for shell callers (upstream).** A gascity `gc` change so the forked `gc` reads beads in-process, not by reaching `bd`.

## Adjacent work, and why this does not overlap it

- `tk-8x93ae` (owned): a durable no-fork drift-exemption for standing conversational sessions. A different fork source — the periodic drift check on long-lived agents, not the per-command data plane.
- `tk-4u0ybr`: cutting the fork-bound hermetic test long poles. Test-suite runtime, not production load. It corroborates the cost model from the other side: it measured, with a call counter, that each doctor check invocation makes about seven `gc` calls, each a bash-and-jq fork chain.
- `tk-4lxad`: `dolt.mode: server` written into the tracked `.beads/config.yaml`. Its own subject is the auto-fast-forward guard, but it confirms the standing per-rig Dolt server this spec relies on.
- `tk-x89rn` (helm): the bead whose need first put the in-process beads library into helm. The precedent this increment copies.

## Confirming per-source attribution (operator, needs root)

The claim that `gc`, `bd`, and `dolt` dominate the fork count is the finding's, not re-derived here, and it needs root. To confirm which processes fork and at what rate on a host showing the advisory:

```
sudo bpftrace -e 'tracepoint:sched:sched_process_fork { @[comm] = count(); }'
```

Let it run for a fixed window under normal city load, then read the `@[comm]` histogram. A dominant `gc`/`bd` count against a negligible agent count confirms the diagnosis and the direction of this spec; a different shape would redirect the remedy.
