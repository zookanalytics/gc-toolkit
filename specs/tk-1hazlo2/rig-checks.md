---
name: gctk rig checks, as built
description: What building gctk rig's checks settled beyond the bead. Covers the pure-executor design the PR#1256 review ruled (callers pass the command and declare the run, and a record answers only the run it records), why rig sits in gctk, the decisions the bead left open, the measured cost of a record write and a --check read, and what the call-site cutover inherits.
---

# `gctk rig` checks, as built

The bead (tk-1hazlo2) and its first ruling (tk-kpanfqm, sitting tk-gxh5whl) set
the checks' surface and their record. The operator's review of PR#1256 (review
5518499124) and the sitting that ruled it (tk-qjc4uaa, 2026-10-14) made `rig` a
pure executor. This records that design, why `rig` sits in gctk, what the build
decided on top of the rulings, the measured cost, and what the cutover
inherits. The behavior's reference is `gctk rig --help` and the doc comments in
`services/gctk/internal/cli/rig.go` and `services/gctk/internal/rig`.

## Why rig sits in gctk

gctk is gc-toolkit's command-line interface, the surface through which agents
act on a city (`services/gctk/README.md`), and `rig` holds the actions gctk
takes on a rig. Its checks are the first of them. They write ledger state: a
later call at the commit answers from the record instead of running the check.
The record is machine truth, the exit status of a command `rig` ran itself,
where the self-review stamp the cutover retires holds an agent's word that its
checks passed. A caller pastes one call and reads its exit code, or the one
JSON line `--check` prints.

## A pure executor

The reviewed `rig` resolved its own inputs. It read the rig's six check vars
with one `gc formula show mol-polecat-work --rig <rig> --json`, took the
affected subset's diff against `origin/<base>` itself, and fell back to the
full suite, or to a pass that ran nothing, when that diff named no file. A
record answered for its commit whatever command it had run. The sitting
established three facts that made that shape wrong:

- The check commands are city configuration: `[rigs.formula_vars]` in the
  town's `city.toml`, with the precedence `--var` at sling, then `city.toml`,
  then the formula's default, frozen into a molecule's steps at pour. A changed
  command is a commit in another repo, so a record keyed to the rig's commit
  could not notice it.
- The var contract's "Empty = run full test_command" governs the var, and the
  formula bodies implement that fallback themselves. No contract defines what
  happens when the diff names no file: the diff belongs to the command. For
  gc-toolkit, the reviewed empty-diff rule recorded a pass that ran nothing
  where the formula path runs every suite, and its `origin/<base>` diff
  disagreed with gc-toolkit's command, which hard-codes `origin/main`, on any
  branch whose base is not main.
- The condition sandbox where `--check` is to run puts `gc` on PATH, but `gc`
  can fail there: a cold pack cache, blinded store reads. So `--check` stays a
  probe that needs no command and calls nothing but git.

The ruling: callers pass the command and declare the run. Formula steps have
the vars rendered at pour and pass them, and the refinery resolves its vars in
its own flow and passes them the same way. `rig` reads no formula var and makes
no `gc` call for a run. `--publish-bead` alone writes through `gc bd`, and a
publish that fails changes no exit.

- `test`, `lint` and `typecheck` take `--command`. `test` also takes
  `--scope full|affected`, which says which test run the command is: the whole
  suite, whose result is a property of the tree, or the subset the commit's
  diff selects, which the command works out itself.
- `--nothing-declared` records a pass that ran nothing (scope `none`), for a
  caller whose rig declares no command for the check. `rig` never infers it.
- A record answers only a call that declares the same run: the same command
  line, byte for byte, and the same scope. A call that declares another run
  runs, and its result replaces the record. So a changed command runs again,
  and an affected pass never answers a call for the full suite.
- Tree identity is the only reuse across commits. A full-scope test pass
  answers for every commit with the same tree, when the call passes the same
  command with scope full.
- `--check` reports whatever is recorded at HEAD, needs no command, and calls
  nothing but git.

Deleted with the var reads: `--rig` and its check of `$GC_RIG_ROOT` against
the checkout, `--affected` with its own diff and fallback, `--base`, the
inference of a pass that ran nothing, and `--pre-existing` with the record's
`disposition` and `tracker` fields. The cutover designs any annotation of a
pre-existing fail beside the refinery caller that needs it.

## Decisions the bead left open

- **Scope is test's alone.** Only test has two commands to tell apart, and the
  var contract names them: `test_command` runs the suite, and
  `affected_tests_command` runs the subset the diff selects. Lint and typecheck
  have one command each and no contract on what it covers, and gc-toolkit's
  `lint_command` lints the files in its diff against `origin/main`. So a lint
  or typecheck run records no scope, and its record answers only its own
  commit, because two commits with one tree need not share the diff such a
  command reads.
- **A record answers only its own command and scope.** The ruling compares
  command text, and the scope is compared too, so a record answers exactly the
  run that made it. When a rig's affected and full commands are the same text,
  a call for the full suite runs once more and writes the tree's entry.
- **A run of nothing is a run like any other.** A `--nothing-declared` call
  over the record of a real run replaces it, as a call with another command
  would. Its record is a pass with scope `none` and no command, so `--check`
  reads a pass, and the scope says that nothing ran.
- **Tree entries.** A full-scope fail withdraws the tree's entry, so the last
  write wins for the tree as well as for the commit. The entry changes before
  the commit's record is written, and a pass's entry is withdrawn again when
  the commit's record cannot be written. So a write the store does not take
  leaves no record of its result, unless that withdrawal fails too, and
  `rig`'s line then says so.
- **Exit codes.** 0 pass, 1 fail, 2 usage, 3 nothing recorded (`--check`), 4
  machine failure, 128+N stopped by signal N. A fresh run exits 1 on any fail,
  whatever status the command exited with. The status itself is kept in the
  record's `exit_code`.
- **What counts as a machine failure.** A checkout with changes HEAD does not
  hold. A command `bash -n` cannot parse, which would otherwise record a fail
  at every commit for a typo in `city.toml`. Exits 126 and 127, which the shell
  gives a command it cannot execute or find. A command ended by a signal,
  killed outright or 128+N from its shell, so an OOM kill under load never
  records a fail that sticks. A timeout. A command that moved HEAD or changed
  a tracked file, pass or fail, and a checkout `rig` cannot read after the
  run. A result the record store does not take, pass or fail: `rig`'s answer
  is its record, so a result with no record behind it neither sets the exit
  nor is published. A suite that exits 126, 127 or 129-192 on its own is
  misread as a machine failure. That costs a re-run, never a false record.
- **`--timeout`, default two hours.** The refinery stops its detached gate at
  two hours. Without a bound, a wedged suite under the lease heartbeat would
  hold its pool slot indefinitely. A timeout sends SIGTERM to the group, then
  SIGKILL after ten seconds.
- **A dirty tree is refused in every recorded mode**, `--check` and
  `--nothing-declared` included. A pass reported for a dirty tree would certify
  content no record saw. `setup` and `build` record nothing, so they run in a
  dirty tree. Untracked files count in `--check` too, though it certifies
  nothing new. Letting `--check` pass them would not unstall a self-review
  whose suite leaves an artifact behind: `self-review-check.sh` refuses the
  same files with its own clean-worktree check, and the next run call in that
  checkout refuses them as well. So the cutover requires check commands that
  leave none behind.
- **The checkout is checked before the run and after it.** Before the run,
  any change HEAD does not hold refuses the call. After the run, a moved HEAD
  or a changed tracked file, staged or not, records nothing, pass or fail. A
  test script that commits or checks out has run against another commit, and
  a `lint_command` that fixes files and exits 0 would otherwise record a pass
  at a commit whose own content fails lint. Untracked files the run left
  behind do not count. A suite's artifacts, such as `cover.out`, `.coverage`
  or build output that is not ignored, change no file the commit holds. The
  run names them in a WARN line, because the next call in that checkout
  refuses them.
- **Publishing.** `--publish-bead` writes the record as one JSON value on
  `rig_check.<check>` (registered in `lifecycle/lifecycle.toml`) through
  `gcbd.Client.Update`, and reads it back with `ShowDirect`. gcbd's writes fork
  `gc bd update`, so the publish does too. `rig` publishes the record that
  answered the call, whether it ran or read it, so it publishes only a record
  the store holds.
- **The runner.** Each command runs as `bash -c '<command>'` at the checkout's
  top level, with stdin closed and the caller's environment, leading a process
  group of its own. The group and the signal relay follow `gitIn` in
  `internal/cli/lifecycle.go`. A relayed signal stops the group the way a
  timeout does, and `Run` returns only once the command has been waited for.
  An agent runs the same line in its own shell tool: zsh for a Claude session
  on this host, and `/bin/zsh -lc` for Codex. gc-toolkit's declared lines use
  `$(...)`, `$?`, `;`, `&&` and `[ ]`, which zsh and bash read the same way,
  and the scripts they call run under their own `#!/usr/bin/env bash`.
- **The git helpers** live in `internal/git`, which every gctk command can
  share. `internal/cli/lifecycle.go` and `internal/cli/merge.go` still call git
  through helpers of their own, and move onto `internal/git` with the CLI
  library (tk-s8bvzal).

## Measured cost

Apple M5 Pro (18 cores), 2026-10-14, at load average 4.5-6.5. In-process
figures come from `go test -bench`, three runs of 2000 iterations each,
interleaved with the reviewed code built from 86d22ece5 at the same load.
End-to-end figures come from the built binaries in full clones of gc-toolkit
(1084 tracked files), timed with bash `EPOCHREALTIME`.

| what | this build | reviewed build |
|---|---|---|
| one record write: a full-suite pass, which writes the commit's file and the tree's entry (`Store.Put`) | 0.37-0.43 ms | 0.39-0.46 ms |
| one test lookup that finds the record (`Store.Lookup`) | 32-43 µs | 18-23 µs |
| `gctk rig test --check`, end to end, three rounds of n=21 | median 40-45 ms (min 30) | median 44-46 ms (min 29) |
| `gctk rig test --scope full --command true --force`, end to end, n=11 | median 55 ms (min 46) | |
| `gctk version`, the process floor, n=31 | median 6 ms | |

A test lookup reads the commit's record and the tree's entry, because the
tree can answer a call that the commit's own record does not match. The
reviewed lookup stopped at the commit's record. The second read adds about
15 µs, which the end-to-end `--check` does not show. A `--check` costs about one
gctk start, one `git rev-parse` and one `git status`. A run costs those plus
`bash -n` and the record write around the command itself, and one more
`git rev-parse` and `git status` after it, to check the checkout. It no longer
includes the `gc formula show` the reviewed build ran, which measured median
234 ms at load average 40-47 on 2026-10-13.

The end-to-end figures grow with the host's load. On 2026-10-13 the reviewed
build's `--check` measured median 182 ms at load average 40-47, and median
834 ms at 77-79.

## What the cutover inherits

- **Every run call passes the command and declares the run.** A formula step
  has the var rendered at pour. It reads the var into a shell variable through
  a quoted heredoc, as mol-polecat-work's self-review already does for its
  test command, and passes `--command "$VAR"`, so the quotes inside a rig's
  command reach `rig` whole. A test call adds `--scope affected` for
  `affected_tests_command` and `--scope full` for `test_command`. An empty var
  is `--nothing-declared`.
- **The self-review** runs `test --scope affected` with
  `affected_tests_command`, else `test --scope full` with `test_command`, else
  `test --nothing-declared`, and passes `--publish-bead $WORK_BEAD_ID`.
- **self-review-check.sh** runs in the condition sandbox, where `gc` can fail.
  It has to resolve the binary the way `gctk-resolve.sh` does (`$GCTK_BIN`,
  else the city's `.gc/services/gctk/bin/gctk`) without the `gc service list`
  step, and pass the loop only on `--check` exit 0, which a pass that ran
  nothing gives too. Exit 3 is a commit nobody recorded, and exit 4 includes a
  dirty worktree.
- **A rig's check commands leave no untracked file that git does not
  ignore.** A run that leaves one keeps its record, but the next call in that
  checkout exits 4, `--check` included, and `self-review-check.sh`'s own
  clean-worktree check refuses the file too. Both lines name the paths: the
  run's WARN line and the next call's exit-4 line. The remedy lives in the
  rig, as a `.gitignore` entry or a command that removes its own output. In
  the worktree at hand, removing the named files is enough, because the
  record at HEAD still answers and nothing runs again. A call site does not
  run `git clean`, which would also delete an agent's uncommitted new files.
- **review-test-evidence** reads `--check`'s one JSON line: `result`, and
  `scope`, where `none` certifies no tests and `affected` certifies the subset.
- **The refinery** resolves its vars at run time and passes them, so its
  command text matches a self-review's only while the city's configuration is
  unchanged, and a changed command runs again. It should keep `rig`'s
  `--timeout` under its detached job's two-hour bound, so the job's own stop
  does not race `rig`'s. Any annotation of a fail as pre-existing is designed
  there.
- **A stop does not reach this rig's in-flight suites.** `tools/run-tests.sh`
  runs each suite in a process group of its own under `set -m` and passes no
  stop on to them, so a relayed signal or a timeout ends the runner and leaves
  its runs going until their own timeouts. tk-rq1d2g4 carries the fix in the
  runner, and tk-oaoxi2n gives it an affected mode that works out its own diff.
- **docs/component-model.md §4** places what a running city executes. Nothing
  calls `gctk rig` yet, so no row is owed here, and the cutover owes it once
  call sites run it.
- **The Go unit tests** under `services/gctk` run in no CI job (tk-gk06jad).
  `assets/scripts/gctk-resolve.test.sh` builds the binary and reaches
  `gctk rig` in CI, but `rig`'s semantics are proved only by `go test ./...`
  run by hand.
