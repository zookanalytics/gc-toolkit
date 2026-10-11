---
name: gctk — promote the merge-cadence cluster from shell to one Go binary
description: Scope for porting the data-plane scripts (lifecycle, the five cadence arms, signoff) behind their existing CLI contracts into a single Go binary beside services/helm. Shell remains the pack's lingua franca everywhere else. Scoped 2026-08-24; lifecycle ported and the build/deploy/status machinery landed 2026-08-26 (tk-utjreo); lifecycle's shell fallback dropped 2026-10-05 (tk-crzvfv); porting model revised 2026-10-11 — ports are written against typed in-process clients with fakes, not as transliterations, and lane-state is the first port under the new model; the remaining subcommands follow one PR at a time.
---

# gctk: the compiled data plane

Status: **in progress**. Follow-up to the rewrite; independent of the
review-gates work (same specs dir because both were scoped from the same
operator conversation). As of 2026-10-11 the porting model changed: a port is
written against typed in-process clients with fakes, not as a transliteration
of the script. `lane-state` is the first port under the new model.

Landed 2026-08-26 (tk-utjreo): `services/gctk`, the `lifecycle` port, the
build/deploy pattern below, the fallback wiring, the build-status file, and its
board rows. `services/gctk/README.md` carries the operating detail.

Landed 2026-10-05 (tk-crzvfv): `lifecycle`'s shell fallback dropped, ahead of
the teardown, once the build order had published a current binary through
eight days of clean ticks. `lifecycle.sh` now only execs the binary, and a call
with no binary to run exits 1 naming the `gctk-build` order. The fallback still
stands for the other subcommands.

Remaining, one PR each, in this order: (1) the bead-store interface in
`internal/gcbd` and its fake, carried by (2) `lane-state` as `internal/lane`
and `gctk lane-state`, with `gctk merge` calling the package in-process;
(3) `pr-facts`, the largest and most call-dense arm, run every tick — its
11-part test file is the behavioural spec; (4) `gate-ensure`, consuming the
lane package; (5) retiring `merge.sh`'s shell arm once `gctk merge` is the only
path; then `pr-open`, `convoy-graduate`, `signoff`. Each is filed as its own
bead. Reapers, sweeps and gc-helm are out of this pass: idle-bound, and
`services/helm` is the Go surface for the board. The remaining shell scripts
and their fallbacks drop when the last one lands.

## The language rule (add to the review charter when it lands)

> Shell for anything an agent pastes, anything that must read as
> documentation, or anything under ~150 lines. The compiled tool for
> data-plane logic that writes ledger state.

Shell is partly forced (formula steps and prompt fragments can only carry
shell) and genuinely fits the small glue that remains. The exception is the
merge-cadence cluster: highest stakes, pure data-plane, no cross-media
sharing — its callers already treat it as an opaque CLI, so the language
behind the command is invisible to them.

## What ports, and what does not

| Ports to `gctk` (subcommand) | Stays shell |
|---|---|
| `lifecycle` (transition/state) | every formula/prompt shell block |
| `lane-state`, `gate-ensure`, `pr-open`, `merge`, `pr-facts`, `convoy-graduate` | doctor checks, order predicates |
| `signoff` | `escalate.sh`, `step-close.sh`, `deferred-dispatch.sh` (small, agent-legible) |
| (later, if warranted) `liveness-sweep` | tmux surface, helm verbs, worktree-setup, tools/ |

`refinery-reconcile.sh` stays a thin shell driver (identity discovery + arm
ordering + the rc=3 interlock) calling `gctk <arm>` — the cadence remains
readable as a script.

## Port model (revised 2026-10-11)

The three ports landed before this date (`lifecycle`, `merge`, `pr-status`)
are transliterations: they kept every subprocess seam the scripts had (fork
`gc`/`gh`/`git`, exec the sibling shell scripts) and are covered behaviourally
only by the shell stub suites. From `lane-state` on, a port is written against
typed in-process clients with fakes. The CLI contract does not move.

- Each subcommand keeps the **byte-identical CLI** of the script it replaces
  (flags, exit codes 0/1/2, stdout grammar). No formula, order, prompt, or
  doctor check changes. Unchanged from the original scope.
- Gas City is the abstraction over beads — rigs, store resolution, the
  controls around them — so every bead read and write goes through Gas City:
  the supervisor API or `gc`. The beads library is never linked. That is the
  standing rule, not a deferral. The bead store is read and written through
  **one Go interface** in `internal/gcbd`, which `*gcbd.Client` implements as
  a client of that Gas City contract: the daemon API for reads, `gc` exec for
  writes and for the read fallback. No port re-implements a read. The two
  contracts `bd-lib.sh` encodes travel with the interface: the C0-byte scrub
  before parsing, and "non-zero exit or non-array = could not tell, never =
  none".
- A port's logic is a package, `internal/<name>`, that takes the interfaces;
  the `cli` subcommand is a thin adapter over it. Another Go subcommand that
  needs the rule calls the package in-process, never execs the sibling shell
  script. First instance: `lane-state` as `internal/lane`, called in-process
  by `gctk merge`. Today `merge.go` execs `lane-state.sh`, which sources
  `bd-lib.sh`, which forks `gc` — per lane, per anchor.
- Fakes: one in-process fake per interface (the bead store now; GitHub and
  git later). The bead-store fake fakes the Gas City contract, not bead
  internals. Each fake expresses every scenario the corresponding shell stub
  in `assets/scripts/test-harness.sh` expresses (the `STUB_*` knobs become
  fake methods) and records every call, so a test asserts reads and writes
  the way the shell suites read `STUB_GC_LOG`. `go test` runs against the
  fakes: no bash, no jq, no subprocess.
- Acceptance: the replaced script's `*.test.sh` suite keeps running against
  the Go binary through the existing stubs until every assertion in it has a
  Go test that fails when the behaviour it pins is removed. The PR that drops
  a shell suite maps assertions to Go tests explicitly; "covered in spirit"
  does not count. A port that cannot pass the shell suite through the stubs
  is wrong; the suite is not. Parts of a suite that test shell-only mechanics
  stay in shell indefinitely.
- Each port PR states the measured before and after: the component's shell
  suite wall time, and the city-side call it replaces (forks per call, ms per
  call).
- `lifecycle/lifecycle.toml` stays the human/doctor-readable declaration; the
  state table lives once in a typed package, and the drift test compares the
  TOML against `gctk lifecycle --dump-machine` (replacing the shell-constant
  mirror).

## Build and deploy

Same pattern as helm-svc, same lessons: a `gctk-build` city order (cooldown,
staleness by `find -newer` and by the recorded revision, atomic publish, never
build in the exec path),
launcher resolves the prebuilt binary. Until the binary exists at the
deployed path, the shell scripts remain — the driver prefers `gctk` when
present, falls back to the script during migration, and drops the fallback
when the last port lands. `lifecycle` dropped its fallback early (tk-crzvfv):
with no binary to run, `lifecycle.sh` refuses the call and names the build
order, and a build that fails keeps the last good binary answering.

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

Linking the beads library, under the standing rule above: Gas City is the
abstraction over beads, so writes and the read fallback still go through `gc`
and reads through the supervisor API, and the permissions surface and the
logs are unchanged. What changed on 2026-10-11 is that the read path and the
rule packages are shared Go code behind interfaces, not shell execs. Also out:
porting anything agents paste; a shared shell library (rejected by measured
decision, unchanged); rewriting services/helm.
