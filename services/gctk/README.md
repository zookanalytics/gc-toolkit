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
| `epic` | actions taken on an epic: filing one with its contract, each field in its own key, refused when the epic has no hypothesis and its parent is not an epic | `gctk epic --help`, `internal/cli/epic.go` |
| `lifecycle` | anchor lifecycle transitions over the state machine `lifecycle/lifecycle.toml` declares. It parses its own verbs and flags | `gctk lifecycle`, `internal/cli/lifecycle.go`, `internal/lifecycle` |
| `merge` | arm 2 of the merge cadence, the single writer of merged truth | `internal/cli/merge.go` |
| `pr compose` | a PR's title and body as the bead that owns it says they should be: its title with the conventional-commit type a repository's title check requires, and its body's managed summary region and branch-beads section, each read by its markers and kept current while the text people add stays as it is | `gctk pr compose --help`, `internal/cli/prcompose.go`, `pr` |
| `pr summary` | the account of what a change does, for its PR: the bead's PR summary and the change's subject line as its title, recorded in one write whose exit decides, or the summary recorded, printed for a reader of the PR's text | `gctk pr summary --help`, `internal/cli/prsummary.go`, `pr` |
| `pr status` | a PR's status (working, merging, needs-review or needs-attention), the one derivation the `status:` label and the helm board share, and the open human gates that hold it, which `gc-helm engage` offers; for a PR on Gas Town's pending record, the pr domain's evaluator decides it, and each condition not met follows it | `gctk pr status --help`, `internal/cli/prstatus.go`, `prstatus`, `pr` |
| `pr record` | the refinery's record of the PR a bead owns as pending until its merge is verified, in Gas Town's two writes under the store's record lock, each guarded on the status and assignee it read, so a bead that a close or a release reached first gets no record | `gctk pr record --help`, `internal/cli/prland.go`, `pr`, `pr/record` |
| `pr reconcile` | one run of the landing order over the store's pending records, the least recently checked first, each under the store's record lock: a ready PR merged with its head pinned, a bead closed once its merge commit is on the target, a changed head sent back to the refinery, and each exception kept blocked behind a human gate | `gctk pr reconcile --help`, `internal/cli/prland.go`, `pr`, `pr/record` |
| `rig` | actions taken on the rig: running its checks and recording each result against the commit | `gctk rig --help`, `internal/cli/rig.go`, `internal/rig` |
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

`assets/scripts/pr-open.sh` and the refinery's merge-push step
(`refinery-publish.sh`, `refinery-land.sh`) take a PR's title and body from
`gctk pr compose`, so an opened PR and a later refresh read one composer.
Each finds the binary through `gctk-resolve.sh`'s `gctk_path`, and with no
binary, or one too old to carry the verb, it opens no PR and edits no body or
title that pass.

`assets/scripts/pr-reconcile.sh`, the landing order's script
(`orders/pr-reconcile.toml`), names the rig's refinery from the roster and execs
`gctk pr reconcile` through `gctk-resolve.sh`. With no binary to run, it refuses
the run with exit 1, and the order's next run tries again.

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
internal/gcbd/       the store adapter: bead reads and writes through `gc bd` and the
                     supervisor API, the store's listing, and its blocked set
internal/gcbd/fake/  the store adapter's in-memory fake, for the domains' tests
internal/daemon/     finding the supervisor API the store adapter's reads go through
internal/git/        the git subprocess seam: one git command per call, in a named directory
internal/gh/         the GitHub adapter: one `gh api` call per read, paged to its end
internal/gh/fake/    the GitHub adapter's in-memory fake, for the domains' tests
internal/feedback/   the pack's one definition of feedback, pr-post.sh's feedback-def, run
                     through jq
internal/rig/        rig's runner and its commit-keyed record store
pr/                  the pr domain: whether the PR a bead owns is ready to merge at its
                     current revision, from the store, GitHub and the definition of
                     feedback; the account of the change its author records, the PR
                     summary; and what the PR's title and body say: its title, and its
                     body's managed summary region and branch-beads section, with the
                     renders they replaced pinned under testdata
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
cd services/gctk && GCTK_STORE_ACCEPTANCE=1 go test ./internal/gcbd -run TestStoreAcceptance -v   # the city's bd on a scratch store
bash assets/scripts/lifecycle.test.sh      # lifecycle through its bridge
bash assets/scripts/merge.test.sh          # merge through its bridge
bash assets/scripts/epic.test.sh           # epic through its bridge
bash assets/scripts/gctk-resolve.test.sh   # which binary a bridge runs
```

A shell suite that reaches `lifecycle.sh`, `merge.sh` or `epic.sh` builds the
binary from the checkout itself, and fails if it cannot.
