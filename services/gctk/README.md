# gctk — the compiled data plane

`gctk` is the pack's compiled data plane as one Go binary: the merge cadence's
logic, plus the PR-status tri-state that the `status:` label and the helm board
must share. It is a port, not a redesign: each subcommand keeps the
byte-identical CLI of the script it replaces, so no formula, order, prompt, or
doctor check changes when a port lands.

Scope and rationale: `specs/2026-08-review-gates/gctk-promotion.md`.

## The language rule

> Shell for anything an agent pastes, anything that must read as documentation,
> or anything under ~150 lines. The compiled tool for data-plane logic that
> writes ledger state.

Shell stays the pack's lingua franca. Formula steps and prompt fragments can
only carry shell, and it fits the small glue that remains. The merge-cadence
cluster is the exception: highest stakes, pure data-plane, no cross-media
sharing, and its callers already treat it as an opaque CLI. `pr-status` is
compiled for the opposite reason: the `status:` label (shell) and the helm
board (Go) must derive the tri-state from one code path, and only a shared
compiled package keeps them from diverging.

## Ported so far

| Subcommand | Replaces | State |
|---|---|---|
| `lifecycle` | `assets/scripts/lifecycle.sh` | ported; the script only execs the binary, with no fallback — a call with no binary to run is refused |
| `pr-status` | `pr-status-label.sh`'s `derive_value` | ported; no fallback — the label is left unchanged when the binary is absent or stale |

Still shell: `gate-ensure`, `pr-open`, `merge`, `pr-facts`, `convoy-graduate`,
`signoff`. The spec's port order is `lifecycle` first (everything else calls
it), then `merge`, then the rest — one subcommand per PR.

`pr-status` is not a cadence port: it is the working | needs-review |
needs-attention tri-state that `pr-status-label.sh` and the helm board share
(`services/gctk/prstatus`). The label writer stays in shell, the derivation
lives in gctk, and it has no shell fallback (see below).

`refinery-reconcile.sh` stays a thin shell driver: identity discovery, arm
ordering, the rc=3 interlock. The cadence has to remain readable as a script.

## Subprocess seams, not a linked library

gctk shells out to `gc`, `bd` and `gh` exactly as the scripts do. Linking the
beads library would change the observability surface, the permissions surface,
and the test surface all at once. Keeping the seams means the scripts' existing
`.test.sh` stub harnesses drive the binary unchanged — the stubs are ordinary
executables on `PATH`, and a Go `exec.Command("gc", …)` finds them the same way
a shell does.

That is why `assets/scripts/lifecycle.test.sh`, which drives the binary through
`lifecycle.sh`, is the port's acceptance bar, and why the port needs no test
suite of its own.

## Resolution, and a missing binary

`lifecycle.sh` resolves the binary explicitly — `$GCTK_BIN`, else the
`.gc/services/gctk/bin/gctk` under `$GC_CITY_PATH`, `$GC_CITY` or
`$GC_CITY_ROOT`, else the `city_path` that `gc service list --json` reports —
and `exec`s it. That precedence is the one the rest of the pack reads, and
`GC_CITY_PATH` leads it because that is the variable a supervisor puts in an
agent session. The listing is what the cadence itself needs: the order runner
that execs `refinery-reconcile.sh` carries no city variable at all, so an
env-only chain would refuse every order-driven transition.
`doctor/check-cadence-live` resolves by the same env chain.

Resolution is never a walk up from the script's own path. The hermetic suites
run from a tree that lives inside a live city, and a filesystem hunt would find
that city's binary instead of the one a suite built from the tree under test.
A suite whose scripts reach `lifecycle.sh` builds the binary from the checkout
first, with `harness_build_gctk` in `assets/scripts/test-harness.sh`.

`lifecycle` has no shell fallback. When there is no binary to exec,
`lifecycle.sh` exits 1, writes nothing, and names the `gctk-build` order that
publishes the binary:

- **A fresh city** refuses lifecycle transitions until the order's first build
  publishes the binary. The merge cadence's arms read the refusal as a failed
  transition and retry it on their next pass.
- **A city whose build failed** keeps serving the last good binary, because a
  failed build leaves the published one untouched. A city whose builds have
  never succeeded has no binary, and refuses transitions the same way a fresh
  city does. The refusal names the order's `build-status.json`, which records
  why the last build failed.

`GCTK_BIN=none` names no binary, so every `lifecycle.sh` call under it is
refused. For the other cadence subcommands the fallback still stands: each
script answers until its subcommand's port is deployed. A port's suite cannot
force that fallback with `GCTK_BIN=none`, because that also leaves
`lifecycle.sh` nothing to exec. The scripts are deleted when the last port
lands.

`pr-status` has no fallback either. Its derivation lives only in gctk — the helm
board (Go) has no shell to fall back to, so a shell copy would be the divergence
the shared package exists to remove. `pr-status-label.sh` resolves the binary
the same way `lifecycle.sh` does (`$GCTK_BIN`, else the city's deployed build).
When the binary is missing — `GCTK_BIN=none`, unset with no deployed build, or
not executable — `derive_value` warns and returns 2 without deriving. When it is
stale — too old to carry `pr-status` — the unknown subcommand exits non-zero,
which reads the same way. Either way `gctk pr-status derive`'s exit-2 grammar
leaves each best-effort caller's label unchanged, so a city without a current
gctk gets a stale-but-safe label, never a wrong one.

## Build and deploy

`orders/gctk-build.toml` runs `assets/scripts/gc-gctk-build.sh --deploy` on a
5-minute cooldown: build if a source is newer than the binary or the last
record shows the binary was built from another revision, publish by atomic
rename, write a build-status record. The revision is the services/gctk
SUBTREE's tree hash at HEAD (`git rev-parse HEAD:./` from the module), not the
repo commit: it moves exactly when a committed input of this module changes,
so a docs-only merge republishes nothing, and the build stamps the same value
into the binary (`gctk version`). A tick with nothing to build needs no Go
toolchain. A tick with something to build and no toolchain is a failed build:
it records `last_build_rc=1`, so the board's PACK row shows it, because a city
that cannot build the binary leaves `lifecycle.sh` nothing to exec. It finds the city by the env chain above
and, failing that, by `gc service list --json`'s `city_path` — the order runner
carries no city variables at all, so the listing is the only route a scheduled
tick has. Both tests are needed — `find -newer`
cannot see an input a commit deleted. Nothing builds in a caller's path — a build inside the cadence would put a Go toolchain
between a merge and its ledger write.

The module is stdlib-only, so a cold build is seconds. There is no service to
restart: a published gctk is serving the moment it lands.

**The tradeoff, stated.** A script edit is live from the working tree
instantly; a gctk change rides the build order. A broken build keeps the last
good binary serving the cadence. That is slower iteration in exchange for no
accidental live surgery on merge logic, and two things make the lag visible:
`doctor/check-cadence-live` compares `gctk version` against the checkout's
services/gctk subtree, and the board's PACK rows carry the same comparison
where the operator already looks. lifecycle.sh makes no such comparison. It has
no other implementation to prefer, so it runs the binary the order last
published, and the order's lag is never a refused transition.

## The state table lives once

`lifecycle/lifecycle.toml` stays the human- and doctor-readable declaration.
`internal/lifecycle` is the executable copy, and `gctk lifecycle
--dump-machine` prints it for the drift test in `lifecycle.test.sh`, which holds
it against the TOML.

## Layout

```
cmd/gctk/            dispatch and `version`
internal/lifecycle/  the state machine — states, classifications, edges
internal/cli/        one file per subcommand, each a contract-preserving port
internal/gcbd/       the `gc bd` subprocess seam and its jq-equivalent accessors
```

`internal/gcbd`'s accessors reproduce the jq expressions the scripts used,
corners included: `(.x // "") | tostring` treats both null and false as absent,
so a metadata value of `false` reads as the empty string here too. Matching the
scripts is the contract; improving on them silently is how a port diverges.

## Running the tests

```bash
cd services/gctk && go test ./...          # the units
bash assets/scripts/lifecycle.test.sh      # the acceptance bar
```

Each shell suite that reaches `lifecycle.sh` builds the binary itself and fails
if it cannot: a run that could not exercise the port has not run the acceptance
bar.
