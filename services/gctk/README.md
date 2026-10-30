# gctk — gc-toolkit's CLI

`gctk` is gc-toolkit's command-line interface, built as one Go binary: the
documented, structured surface through which agents act on a city. Agents are
its users. A person can run any command and it should make sense, but no
command is shaped for ad-hoc human use. A command's usage text and its code's
doc comments state what it does and how; this README is the map to them.

gctk links no beads library: it reaches beads through `gc bd` and the
supervisor's API (`internal/gcbd`).

## Commands

| Command | What it does | Documented in |
|---|---|---|
| `lifecycle` | anchor lifecycle transitions over the state machine `lifecycle/lifecycle.toml` declares | `internal/cli/lifecycle.go`, `internal/lifecycle` |
| `merge` | arm 2 of the merge cadence, the single writer of merged truth | `internal/cli/merge.go` |
| `pr-status` | a PR's status tri-state (working, needs-review or needs-attention), the one derivation the `status:` label and the helm board share | `internal/cli/prstatus.go`, `prstatus` |
| `rig` | actions taken on the rig: running its checks and recording each result against the commit | `gctk rig --help`, `internal/cli/rig.go`, `internal/rig` |
| `version` | the revision the binary was built from | `cmd/gctk` |

Logic gctk does not hold runs as shell scripts. Among them are the rest of the
merge cadence (`gate-ensure`, `pr-open`, `pr-facts`, `signoff`) and
`refinery-reconcile.sh`, the driver that runs the cadence's arms.
[docs/gctk-architecture.md](../../docs/gctk-architecture.md) states which pack
logic moves into gctk and the shape it takes there.

## Bridges

A shell script that only execs a gctk command is a bridge for callers that do
not call gctk yet, and it goes away once they do. A bridge is not a contract
gctk keeps: matching a script's flags and output byte for byte is not a goal,
and neither are tests that pin usage text. `assets/scripts/lifecycle.sh` execs
`gctk lifecycle`, and `assets/scripts/merge.sh` execs `gctk merge`. Both find
the binary through `assets/scripts/gctk-resolve.sh`, which states the
resolution chain, and neither has a shell fallback. With no binary to run, a
bridge refuses the call with exit 1 and names the `gctk-build` order that
publishes the binary. The merge cadence reads a refused transition as a failed
one and a refused merge pass as `merge rc=1`, and retries both on its next
pass. A fresh city has no binary until that order's first build, and a city
whose build failed keeps serving the last good binary.

`assets/scripts/pr-status-label.sh` writes the `status:` label in shell and
takes the value from `gctk pr-status derive`. It resolves the binary the same
way, and when there is none, or the binary is too old to carry `pr-status`, it
leaves the label unchanged.

## rig

`gctk rig` holds the actions gctk takes on a rig, and checks are the first of
them. `test`, `lint` and `typecheck` run the command their caller passes and
record the result against the commit it ran at. `setup` and `build` run their
command and record nothing. In a checkout they find clean, they put back what
the command changes, other than files git ignores, so the recorded checks that
follow in the same checkout can run. The caller passes every input: the
command, which test run it is, and, when the rig declares no command for a
check, that there is nothing to run. gctk reads no formula var and works out no
diff.

Every place that runs a rig's declared checks calls it, passing the command
from the rig's formula vars: `mol-polecat-work`'s workspace-setup, its
preflight-tests at the base commit and its self-review, the refinery's
run-tests at the merged head, and the correctness review when the pinned
commit has no record to read. `assets/scripts/self-review-check.sh`, the
self-review's exit condition, and `assets/scripts/review-evidence.sh`, which
every review's gather runs, read the records with `--check`. Each caller finds
the binary by one line, the `gctk-bin` block, which takes `$GCTK_BIN` or else
the city's build and calls no `gc`, because `self-review-check.sh` runs where
`gc` can fail.

The records live under the rig clone's git common directory, which every
worktree of the clone shares and which outlives any one of them:

| Path under the git common directory | What it holds |
|---|---|
| `gc-rig-checks/<check>/commits/<commit>.json` | the check's record for that commit |
| `gc-rig-checks/test/trees/<tree>.json` | the full-suite test pass every commit with that tree reads |

`--publish-bead <bead>` copies a record onto the bead's `rig_check.<check>` key,
which `lifecycle/lifecycle.toml` registers. A record says what a command did at
a commit and never whose failure it is: a caller that judges a recorded fail
pre-existing writes that judgment on a bead with
`assets/scripts/rig-check-pre-existing.sh`. `gctk rig --help` states the flags,
which record answers a call, and the exit codes. `specs/tk-1hazlo2/rig-checks.md`
records the design and its measured cost.

## Build and deploy

`orders/gctk-build.toml` runs `assets/scripts/gc-build.sh gctk --deploy` on a
five-minute cooldown, and `gc-build.sh` states when it builds and what it
writes. It publishes the binary under `<city>/.gc/services/gctk`, and nothing
builds in a caller's path, so a gctk change goes live when the order next
publishes it, while a script edit is live from the working tree at once. The
bridges run whatever binary the order last published.
`doctor/check-cadence-live` and the board's PACK rows report a deployed binary
built from sources other than the checkout's.

## Layout

```
cmd/gctk/            dispatch and `version`
internal/cli/        the commands, each with its usage text, flags and exit codes
internal/lifecycle/  the lifecycle state machine, which lifecycle/lifecycle.toml declares
internal/gcbd/       bead reads and writes, through `gc bd` and the supervisor API
internal/daemon/     finding the supervisor API the gcbd reads go through
internal/git/        the git subprocess seam: one git command per call, in a named directory
internal/rig/        rig's runner and its commit-keyed record store
prstatus/            the PR status derivation, exported for the helm board
```

## Running the tests

```bash
cd services/gctk && go test ./...          # every package
bash assets/scripts/lifecycle.test.sh      # lifecycle through its bridge
bash assets/scripts/merge.test.sh          # merge through its bridge
bash assets/scripts/gctk-resolve.test.sh   # which binary a bridge runs
```

A shell suite that reaches `lifecycle.sh` or `merge.sh` builds the binary from
the checkout itself, and fails if it cannot.
