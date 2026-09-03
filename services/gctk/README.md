# gctk — the compiled data plane

`gctk` is the merge cadence's data-plane logic as one Go binary. It is a port,
not a redesign: each subcommand keeps the byte-identical CLI of the script it
replaces, so no formula, order, prompt, or doctor check changes when a port
lands.

Scope and rationale: `specs/2026-08-review-gates/gctk-promotion.md`.

## The language rule

> Shell for anything an agent pastes, anything that must read as documentation,
> or anything under ~150 lines. The compiled tool for data-plane logic that
> writes ledger state.

Shell stays the pack's lingua franca. Formula steps and prompt fragments can
only carry shell, and it fits the small glue that remains. The merge-cadence
cluster is the exception: highest stakes, pure data-plane, no cross-media
sharing, and its callers already treat it as an opaque CLI.

## Ported so far

| Subcommand | Replaces | State |
|---|---|---|
| `lifecycle` | `assets/scripts/lifecycle.sh` | ported; the script remains as the fallback |

Still shell: `gate-ensure`, `pr-open`, `merge`, `pr-facts`, `convoy-graduate`,
`signoff`. The spec's port order is `lifecycle` first (everything else calls
it), then `merge`, then the rest — one subcommand per PR.

`refinery-reconcile.sh` stays a thin shell driver: identity discovery, arm
ordering, the rc=3 interlock. The cadence has to remain readable as a script.

## Subprocess seams, not a linked library

gctk shells out to `gc`, `bd` and `gh` exactly as the scripts do. Linking the
beads library would change the observability surface, the permissions surface,
and the test surface all at once. Keeping the seams means the scripts' existing
`.test.sh` stub harnesses drive the binary unchanged — the stubs are ordinary
executables on `PATH`, and a Go `exec.Command("gc", …)` finds them the same way
a shell does.

That is why `assets/scripts/lifecycle.test.sh` runs its whole body twice, once
against each implementation, and why the port needs no test suite of its own.

## The fallback, and when it goes away

Until a subcommand's binary is deployed, its script answers. `lifecycle.sh`
resolves the binary explicitly — `$GCTK_BIN`, else the
`.gc/services/gctk/bin/gctk` under `$GC_CITY_PATH`, `$GC_CITY` or
`$GC_CITY_ROOT` — and `exec`s it when one is there. `GCTK_BIN=none` forces the
shell implementation. That precedence is the one the rest of the pack reads,
and `GC_CITY_PATH` leads it because that is the variable a supervisor puts in
an agent session: a chain without it answers from the fallback in the shape
most callers run in. `doctor/check-cadence-live` resolves the same way, for the
same reason.

Resolution is never a walk up from the script's own path. The hermetic suites
run from a tree that lives inside a live city, and a filesystem hunt would find
that city's binary and quietly stop testing the script.

The scripts are deleted when the last port lands and the fallback drops.

## Build and deploy

`orders/gctk-build.toml` runs `assets/scripts/gc-gctk-build.sh --deploy` on a
5-minute cooldown: build if a source is newer than the binary or the last
record shows the binary was built from another revision, publish by atomic
rename, write a build-status record. It finds the city by the env chain above
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
`doctor/check-cadence-live` compares `gctk version` against the checkout, and
the board's PACK rows carry the same comparison where the operator already
looks.

## The state table lives once

`lifecycle/lifecycle.toml` stays the human- and doctor-readable declaration.
`internal/lifecycle` is the executable copy, and `gctk lifecycle
--dump-machine` prints it for the drift test. While the shell fallback exists
there is a second mirror in its `lifecycle-state-table` block; the suite holds
both against the TOML, and that mirror goes when the fallback does.

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
bash assets/scripts/lifecycle.test.sh      # the acceptance bar, both arms
```

The shell suite builds the binary itself and fails if it cannot: a run that
could not exercise the port has not run the acceptance bar.
