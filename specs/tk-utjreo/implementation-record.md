---
name: gctk — what tk-utjreo landed, and what it deliberately did not
description: The scope decision behind the first gctk PR — why one subcommand rather than seven, what the build/deploy/status machinery covers, and the follow-up beads carrying the rest. Read it before starting another port.
---

# tk-utjreo: the first gctk increment

The bead reads "Implement gctk per `specs/2026-08-review-gates/gctk-promotion.md`,
including the helm build-status row." This records what that came to mean and
why, so the next port starts from a stated position rather than re-deriving one.

## The scope decision

The spec the bead points at prescribes its own delivery shape:

> Port order: `lifecycle` first (everything else calls it), then `merge`, then
> the rest; **one subcommand per PR**, deleting its script in the same PR.

Seven subcommands is 2,233 lines of shell, each with a stub-harness suite that
must keep passing. Landing them together would contradict the instruction in
the document being implemented and produce a diff no reviewer could hold in
their head. So this PR delivers the first port plus everything the later ports
reuse, and the remaining six are filed as beads — which is also the operator's
standing rule from the cutover runbook: scoped follow-ups become slung work,
not doc notes.

The helm build-status row is here in full. The bead singles it out as part of
the deliverable rather than a follow-on, and it is the piece with no dependency
on how many subcommands have been ported.

## Landed

**`services/gctk`** — a stdlib-only Go module. `cmd/gctk` dispatches and
answers `version`; `internal/lifecycle` holds the state machine;
`internal/gcbd` is the `gc bd` subprocess seam; `internal/cli` carries one file
per ported subcommand.

**`gctk lifecycle`** — the contract-preserving port of `lifecycle.sh`. Same
verbs, flags, exit codes and stdout grammar, down to the `--json` object's
field order. `--dump-machine` prints the declared machine for the drift test,
which is the comparison the spec asks for in place of the shell-constant
mirror.

**The fallback.** `lifecycle.sh` keeps its shell implementation and `exec`s the
binary when one resolves. Resolution is explicit — `$GCTK_BIN`, else
`$GC_CITY_ROOT`/`$GC_CITY` — and never a walk up from the script's own path,
because the hermetic suites run from a tree inside a live city and a filesystem
hunt would find that city's binary and silently stop testing the script.
`GCTK_BIN=none` forces the shell.

**Build and deploy.** `orders/gctk-build.toml` +
`assets/scripts/gc-gctk-build.sh`, on the helm-build pattern: cooldown,
staleness by `find -newer` **and** by the recorded `binary_rev`, atomic publish
by rename, never a build in a caller's path. The second test is not redundant:
`find -newer` can only compare files that still exist, so a deletion-only
commit leaves nothing newer than the binary and the mtime test alone would
record the new revision for a binary built from the old one. No restart step — gctk is a command, not a service.

**The build-status record and the board rows.** Every build order writes
`<state_root>/build-status.json`; `services/helm` reads them all into
`Board.PackHealth`, bands each row once in the model, and renders it in both
views. Details in `services/helm/README.md`.

**`doctor/check-cadence-live` arm 3.** `gctk version` against the checkout's
HEAD. Warns, never errors: the build order's lag is by design and self-heals.

## The acceptance argument

The spec makes the replaced script's own `.test.sh` the acceptance suite. That
is taken literally: `lifecycle.test.sh` runs its whole assertion body twice,
once per implementation, with no assertion text changed. The suite builds the
binary itself and FAILS when it cannot — a run that could not exercise the port
has not run the acceptance bar.

The suite was mutation-tested rather than trusted:

| mutation | caught by |
|---|---|
| an edge dropped from the Go table | the `--dump-machine` drift assertion |
| the port writing two `bd update`s instead of one | "exactly ONE gc bd update carried the whole transition" |
| the preference wiring broken, so arm 2 silently ran shell | "lifecycle.sh execs the binary when GCTK_BIN resolves" |
| a failed build claiming the revision it could not build | `(STATUSFAIL) binary_rev stays on what is still serving` |
| the no-op tick writing no record | `(STATUSNOOP) checked_at advanced` |
| a deletion-only commit leaving a stale binary marked current | `(STATUSDEL) the deleted input forces a rebuild` |

The third one is the load-bearing case: without it, a two-arm suite that has
quietly collapsed into one arm still reports every assertion green.

The build-status rows in that table come from `gc-helm-svc.test.sh`. Both
builders decide staleness with the same two tests and write the record through
the same no-op path, so that suite is where the shared pattern is pinned;
`gc-gctk-build.sh`'s copy was checked by running the deletion-only sequence
directly — build, delete a source, commit, re-run — against the script before
and after the fix.

## Not landed, and why

Six subcommand ports: `merge` (tk-ccux9e), `gate-ensure` (tk-lw5z4y), `pr-open`
(tk-1fv2tn), `pr-facts` (tk-9asn2v), `convoy-graduate` (tk-7y1y67), `signoff`
(tk-tyopvq). Each bead carries the bar the lifecycle port set. `signoff` is
last and owns the teardown: delete the seven scripts, drop the fallback blocks,
remove the shell mirror from the drift test.

`liveness-sweep` stays shell; the spec lists it as "later, if warranted" and
nothing has warranted it.

`tools/lint-learned.sh` reports five `stale-reference` findings in files this
diff touches. All five predate this bead — verified against the `origin/main`
blobs, not the working tree — and are tracked as tk-7zlg3w. The preflight
doctrine is to report pre-existing failures rather than fix them, and rewriting
five accepted comments would mix prose churn into a port diff.

## One divergence from the script, stated

`lifecycle.sh` loops forever when a flag is given without its value (`shift 2`
fails at `$# = 1` and the `while` condition never advances). The port treats a
missing value as the empty string and ends the scan, which reaches the existing
"transition needs --to <state>" refusal. No test covers the input; a hang is
not a contract worth reproducing.
