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
binary when one resolves. Resolution is explicit — `$GCTK_BIN`, else the city
named by `$GC_CITY_PATH`, `$GC_CITY` or `$GC_CITY_ROOT` — and never a walk up
from the script's own path, because the hermetic suites run from a tree inside
a live city and a filesystem hunt would find that city's binary and silently
stop testing the script. `GCTK_BIN=none` forces the shell.

`GC_CITY_PATH` leads because it is the variable a supervisor puts in an agent
session, where the other two are absent: a chain without it leaves every agent
on the fallback, which is the shape most callers run in.
`doctor/check-cadence-live` resolves the same way and reports the same binary.

**Build and deploy.** `orders/gctk-build.toml` +
`assets/scripts/gc-gctk-build.sh`, on the helm-build pattern: cooldown,
staleness by `find -newer` **and** by the recorded `binary_rev`, atomic publish
by rename, never a build in a caller's path. The city comes from the env chain
first, so a hand run publishes where its operator meant, and from
`gc service list --json`'s `city_path` otherwise — `gc supervisor run`, which
spawns the cooldown order, carries no city variable at all, so a scheduled tick
has no other route and would refuse on every pass while the order arms above
reported the cadence healthy. The second test is not redundant:
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
directly: build, delete a source, commit, re-run, against the script before and
after the fix.

`check-cadence-live`'s suite reaches arm 3, which resolves a gctk binary
through the ambient city when `GCTK_BIN` is unset. Every order case therefore
runs through the `run_check` helper, which pins `GCTK_BIN` at a path that does
not exist. A case that writes its own `bash "$CHECK"` silently loses the pin
and starts reading the operator's deployed binary; the suspended-rig case did,
and failed against a city carrying a deployed gctk while passing everywhere
else. Vary an input through the helper instead.

## The port tracks a moving script

`lifecycle.sh` is not frozen while it is being replaced. Between the port's
first cut and its landing, the script grew a `held` state with transitions in
both directions, `LIFECYCLE_HUMAN_STATES` with the refusal of an EMPTY route
into a human state, the park sentinel's refusal without a takeaway,
`--takeaway` writing the text/at/by triple capped at 140 codepoints with the
settled-key cleared beside it, `--set-dated` with the compare-and-preserve rule
for the `@<since>` component, and the detached-state clear of the assignee on a
bead still at `status=open`. The port carries all of them.

The two-arm suite is what makes that a bounded job rather than a reading
exercise: every case the script gained ran against the port and failed, so the
work was enumerated by the suite rather than by inspection. It is also why the
port reproduces the idle-transition write elision in the same position and
under the same conditions the script applies it. A caller cannot tell which
implementation answered, so eliding on one side and writing on the other is a
divergence in what a cadence pass costs, whichever side is "better".

The cap on `--takeaway` is a rendering bound rather than machine state, so it
is not in `lifecycle.toml` and the drift assertion cannot reach it there.
`--dump-machine` prints it, the gctk arm holds it against
`LIFECYCLE_TAKEAWAY_MAX`, and the shell arm already holds that against
`gc-helm.sh`'s `TAKEAWAY_MAX` — the two writers of the board's NEEDS cell are
chained rather than independently correct.

**One assertion is red in both arms.** `lifecycle.test.sh` ends 420 passed, 2
failed, and both failures are the same case — the idle re-assertion that issues
one `bd update` where the block's contract is zero. It reproduces on
`origin/main` in a detached control worktree (207 passed, 1 failed), so the
port did not cause it; it appears twice here only because the suite runs its
body once per arm. It is filed as tk-oxsct1 (tk-ivums8 duplicates it), with the
cause recorded there: the elision requires `ASSIGNEE_SET=0`, and the
detached-state assignee clear sets that flag on exactly the fixture the case
uses.

## Two artifacts named build-status

`gc-helm-build.sh` writes both, and they answer different questions.
`<state_root>/build-status` is one line — `ok`, `unreadable`, `unprobed`,
`failed` — and reports whether the binary can READ the city's bead stores;
`write_status` writes it and `gc-helm-svc.test.sh` asserts on its kinds.
`<state_root>/build-status.json` is the record this bead added, and reports
what the component is SERVING against what the sources say; `write_record`
writes it and the board's PACK rows read it. `gc-gctk-build.sh` writes only the
second — gctk reads no stores, so it has nothing to probe.

Collapsing them was considered and rejected: readability is a property of the
running binary that only a probe can answer, and revision currency is a
property of the build that only the build order knows. One record carrying both
would report a field it cannot always fill.

## Not landed, and why

Six subcommand ports: `merge` (tk-ccux9e), `gate-ensure` (tk-lw5z4y), `pr-open`
(tk-1fv2tn), `pr-facts` (tk-9asn2v), `convoy-graduate` (tk-7y1y67), `signoff`
(tk-tyopvq). Each bead carries the bar the lifecycle port set. `signoff` is
last and owns the teardown: delete the seven scripts, drop the fallback blocks,
remove the shell mirror from the drift test.

`liveness-sweep` stays shell; the spec lists it as "later, if warranted" and
nothing has warranted it.

## One divergence from the script, stated

`lifecycle.sh` loops forever when a flag is given without its value (`shift 2`
fails at `$# = 1` and the `while` condition never advances). The port treats a
missing value as the empty string and ends the scan, which reaches the existing
"transition needs --to <state>" refusal. No test covers the input; a hang is
not a contract worth reproducing.
