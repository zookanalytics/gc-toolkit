---
name: gctk — promote the merge-cadence cluster from shell to one Go binary
description: Scope for porting the data-plane scripts (lifecycle, the five cadence arms, signoff) behind their existing CLI contracts into a single Go binary beside services/helm. Shell remains the pack's lingua franca everywhere else. Scoped 2026-08-24; lifecycle ported and the build/deploy/status machinery landed 2026-08-26 (tk-utjreo); the remaining subcommands follow one PR at a time.
---

# gctk: the compiled data plane

Status: **in progress**. Follow-up to the rewrite; independent of the
review-gates work (same specs dir because both were scoped from the same
operator conversation).

Landed 2026-08-26 (tk-utjreo): `services/gctk`, the `lifecycle` port, the
build/deploy pattern below, the fallback wiring, the build-status file, and its
board rows. `services/gctk/README.md` carries the operating detail.

Remaining, one subcommand per PR in this order: `merge`, `gate-ensure`,
`pr-open`, `pr-facts`, `convoy-graduate`, `signoff`. Each is filed as its own
bead. The shell scripts and the driver's fallback drop when the last one
lands.

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
| `gate-ensure`, `pr-open`, `merge`, `pr-facts`, `convoy-graduate` | doctor checks, order predicates |
| `signoff` | `escalate.sh`, `step-close.sh`, `deferred-dispatch.sh` (small, agent-legible) |
| (later, if warranted) `liveness-sweep` | tmux surface, helm verbs, worktree-setup, tools/ |

`refinery-reconcile.sh` stays a thin shell driver (identity discovery + arm
ordering + the rc=3 interlock) calling `gctk <arm>` — the cadence remains
readable as a script.

## Contract-preserving port

- Each subcommand keeps the **byte-identical CLI** of the script it replaces
  (flags, exit codes 0/1/2, stdout grammar). No formula, order, prompt, or
  doctor check changes.
- The existing `.test.sh` stub-harness suites are the **acceptance suite**:
  each port must pass the replaced script's tests unmodified (the stubs fake
  `gc`/`bd`/`gh`, which gctk shells out to exactly as the scripts do —
  keeping subprocess seams rather than linking the beads library is
  deliberate: same observability, same stubs, same permissions surface).
- `lifecycle/lifecycle.toml` stays the human/doctor-readable declaration; the
  state table lives once in a typed package, and the drift test compares the
  TOML against `gctk lifecycle --dump-machine` (replacing the shell-constant
  mirror).
- Port order: `lifecycle` first (everything else calls it), then `merge`,
  then the rest; one subcommand per PR, deleting its script in the same PR.

## Build and deploy

Same pattern as helm-svc, same lessons: a `gctk-build` city order (cooldown,
staleness by `find -newer` and by the recorded revision, atomic publish, never
build in the exec path),
launcher resolves the prebuilt binary. Until the binary exists at the
deployed path, the shell scripts remain — the driver prefers `gctk` when
present, falls back to the script during migration, and drops the fallback
when the last port lands.

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
