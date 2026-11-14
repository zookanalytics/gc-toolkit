# gctk — gc-toolkit's CLI

`gctk` is gc-toolkit's command-line interface, built as one Go binary: the
documented, structured surface through which agents act on a city. Agents are
its users. A person can run any command and it should make sense, but no
command is shaped for ad-hoc human use. The command tree is cobra's, and a
command's generated help (`gctk <noun> <verb> --help`) and its code's doc
comments state what it does and how; this README is the map to them.

gctk links no beads library: its store adapter (`internal/gcbd`) reaches beads
through `gc bd` and the supervisor's API.

## Commands

| Command | What it does | Documented in |
|---|---|---|
| `bead holds` | what holds each bead named, from one read of the store: one status (blocked, held, unjudged or clear) with the waits behind it and whether each is the bead's own or an ancestor's, its own pending waits and when the last landed, why it is in flight, its arm, and its wait edges into another store, one JSON object per line, read from the store `--db` names or the one gc routes the first bead to | `gctk bead holds --help`, `internal/cli/bead.go`, `waits` |
| `bead arm`, `bead disarm` | arm a bead to start by itself once nothing holds it, on a formula through a pool, or remove its arm, each in one write under the bead's dispatch lock | `gctk bead arm --help`, `gctk bead disarm --help`, `arm` |
| `bead start-armed` | the deferred-dispatch order's pass: retire the arm of each closed or delivered bead, and start each armed bead the pool's own serve rule would serve and nothing bd cannot judge holds, exactly once, printing one JSON line per arm; `--dry-run` writes nothing | `gctk bead start-armed --help`, `arm`, [docs/deferred-dispatch.md](../../docs/deferred-dispatch.md) |
| `epic` | actions taken on an epic: filing one with its contract, each field in its own key, refused when the epic has no hypothesis and its parent is not an epic | `gctk epic --help`, `internal/cli/epic.go` |
| `lifecycle` | anchor lifecycle transitions over the state machine `lifecycle/lifecycle.toml` declares. It parses its own verbs and flags | `gctk lifecycle`, `internal/cli/lifecycle.go`, `internal/lifecycle` |
| `merge` | arm 2 of the merge cadence, the single writer of merged truth | `internal/cli/merge.go` |
| `pr status` | a PR's status (working, merging, needs-review or needs-attention), the one derivation the `status:` label and the helm board share, and the open human gates that hold it, which `gc-helm engage` offers | `gctk pr status --help`, `internal/cli/prstatus.go`, `prstatus` |
| `rig` | actions taken on the rig: running its checks and recording each result against the commit, and running a copy of its UI from a checkout for a demo capture or a person | `gctk rig --help`, `internal/cli/rig.go`, `internal/cli/rig_serve.go`, `internal/rig` |
| `session` | actions taken on a session: giving it a title its Gas City record and its terminal both show, made of the bead it is about (`--subject`), the pull request it is about (`--pr`) and its topic (`--topic`). A Claude Code or Codex terminal takes the title at the session's next boundary, a few seconds after the turn ends | `gctk session --help`, `internal/cli/session.go` |
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
`gctk lifecycle`, `assets/scripts/merge.sh` execs `gctk merge`, and
`assets/scripts/epic.sh` execs `gctk epic` for the work skill, whose examples
call every writer through the pack command. Each finds the binary through
`assets/scripts/gctk-resolve.sh`, which states the resolution chain, and none
has a shell fallback. With no binary to run, a bridge refuses the call with
exit 1 and names the `gctk-build` order that publishes the binary. The merge
cadence reads a refused transition as a failed one and a refused merge pass as
`merge rc=1`, and retries both on its next pass. A fresh city has no binary
until that order's first build, and a city whose build failed keeps serving the
last good binary.

`assets/scripts/pr-status-label.sh` writes the `status:` and `held:` labels in
shell and takes their values from `gctk pr status`. It resolves the
binary the same way, and when there is none, or the binary is too old to carry
`pr status` or its `--json`, it leaves the labels unchanged. `gc-helm.sh` engage
lists what holds a bead from the reasons in the same verb's `--json` answer, and
the helm board imports the package behind it, `prstatus`, so the labels, engage
and the board read one definition of what holds a PR.

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
a key rig declares through the ledger, in one write that nothing reads back. A record says what a command did at
a commit and never whose failure it is: a caller that judges a recorded fail
pre-existing writes that judgment on a bead with
`assets/scripts/rig-check-pre-existing.sh`. `gctk rig <check> --help` states the
flags, which record answers a call, and the exit codes. `specs/tk-1hazlo2/rig-checks.md`
records the design and its measured cost.

`serve` runs a copy of the rig's UI from the checkout it is called in: the serve
command its caller passes, with bash at the checkout's top, on a free loopback
port it is given as `$PORT`, inside the sandbox that
`assets/scripts/demo-engine-lib.sh` defines for a demo capture, which
`GCTK_SCRIPTS_DIR` names. A demo capture's `--serve` starts one with no address
and points the engine at its port. The `converse-edit` skill starts one with the
city's publish command and address pattern for the operator. Each caller reads
the rig's `ui_serve_command`, and the city's `ui_publish_command` and
`ui_address_pattern`, from the rig's formula vars and passes them. A copy is a
process group led by a detached gctk, `rig serve --lead`, which ends the group
when the serve command ends, and Gas City's orphan sweep ends it once the
session that started it has ended. Starts and stops of one checkout take turns
under a lock beside the copy's record, so two starts that find a copy that died
run one copy in its place, and two that ask to publish a running copy run one
publish command. The record and the lock live beside the check records:

| Path under the git common directory | What it holds |
|---|---|
| `gc-rig-serve/<hash of the checkout's path>/` | a copy's port, its commands, its leader's pid and start, and its logs |
| `gc-rig-serve/<hash of the checkout's path>.lock` | the file a start or a stop of that checkout's copy holds an flock on while it runs, which the kernel releases if the call dies |

`gctk rig serve --help` states the flags, the states a call reports and the
exit codes. `specs/tk-rymdhac/gas-city-search.md` records what Gas City offers
for it.

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
cmd/gctk/            the binary's entry point, and the revision `version` prints
internal/cli/        the command tree, each command with its help, flags and exit codes
internal/lifecycle/  the lifecycle state machine, which lifecycle/lifecycle.toml declares
internal/ledger/     typed bead records: each key's declaration, one write per act
                     whose exit decides, snapshots, and a pass that reads each bead once
internal/host/       the host adapter: the processes gctk starts and signals, the process
                     table, and the loopback ports and their listeners
internal/host/fake/  the host adapter's in-memory fake, for the domains' tests
internal/gascity/    the runtime adapter: gc sling, an agent's default formula from the city's
                     config, the city's root, and the pack's scripts that ask a person
internal/gascity/fake/  the runtime adapter's fake, which records each call and answers as a test says
internal/gcbd/       the store adapter: bead reads and writes through `gc bd` and the
                     supervisor API, the store's listing, and its blocked set
internal/gcbd/fake/  the store adapter's in-memory fake, for the domains' tests
internal/daemon/     finding the supervisor API the store adapter's reads go through
internal/git/        the git subprocess seam: one git command per call, in a named directory
internal/rig/        rig's runner, its commit-keyed record store, and a copy of the rig's UI
arm/                 the arm's verbs and its start: what arm refuses, the dispatch lock, and the
                     steps that send each armed bead once
arm/record/          the arm's keys, which it owns, the arm they decode to, and every write to them
prstatus/            the PR status derivation, exported for the helm board
listing/             one pass's read of a store for the helm board: every live bead, the
                     closed beads under a parent, the keys it decodes, and waits' and
                     prstatus's answers from the same rows
waits/               what holds a bead, from one snapshot: the rule by where the work is, the
                     in-flight test, the run link's copy and the keys it reads, read-only
queue/               the order work is expected to land in, for the helm board: bd graph's
                     execution layers over waits' answers, then the pool's claim order,
                     each bead's row and waits read through the Store a listing implements
key-registry.json    every declared key, generated from the declarations
```

## Running the tests

```bash
cd services/gctk && go test ./...          # every package
cd services/gctk && go test ./cmd/gctk -run TestKeyRegistry -update   # write key-registry.json again
cd services/gctk && GCTK_STORE_ACCEPTANCE=1 go test ./internal/gcbd ./arm -run TestStoreAcceptance -v   # the city's bd on a scratch store
bash assets/scripts/lifecycle.test.sh      # lifecycle through its bridge
bash assets/scripts/merge.test.sh          # merge through its bridge
bash assets/scripts/epic.test.sh           # epic through its bridge
bash assets/scripts/gctk-resolve.test.sh   # which binary a bridge runs
```

A shell suite that reaches `lifecycle.sh`, `merge.sh` or `epic.sh` builds the
binary from the checkout itself, and fails if it cannot.
