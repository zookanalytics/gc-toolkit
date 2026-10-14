---
name: gctk rig check gate, as built
description: What building the gctk rig gate settled beyond its bead. Covers which formula the check vars resolve through and why that matches a polecat pour, the decisions the bead left open, the measured cost of a record write and a --check read, and what the call-site cutover inherits.
---

# The `gctk rig` check gate, as built

The bead (tk-1hazlo2) and its ruling (tk-kpanfqm, sitting tk-gxh5whl) fix the
gate's surface and its record. This records what the build had to find out or
decide on top of them. The gate's reference is the "The check gate" section of
`services/gctk/README.md`.

## Var resolution

The gate resolves the six check vars through **mol-polecat-work**, with one
`gc formula show mol-polecat-work --rig <rig> --json` per run. It takes the
rig's own value when the rig sets one, even an empty one, and the formula's
default otherwise. No vars-only read exists. `gc config show --json` carries a
rig's raw `formula_vars`, but not the formula's defaults, which a pour also
pastes.

**Why that is what a polecat pour renders.** Read in gascity at 3dd7ad20a:

- A pour builds its var map with the precedence `--var` > the rig's
  `formula_vars` > routing-injected vars > the formula's default
  (`internal/sling/sling.go:1152`). The vars a sling adds itself are
  `issue`, `rig_name`, `binding_name`, `binding_prefix`, and `base_branch` or
  `target_branch` (the same function, from line 1170), and none of them is a
  check var's name. So for a check var a pour takes the rig's value, else the
  default, unless the sling carried a `--var` for it.
- `gc formula show` prints `rig_default` from a `*string`
  (`cmd/gc/cmd_formula.go:368`, set at 594-597), so a rig that sets a var to
  `""` answers `"rig_default": ""`. "Present wins, even empty" therefore reads
  the same value the pour takes.
- A pour renders `{{name}}` with one `regexp.ReplaceAllStringFunc` pass
  (`internal/formula/parser.go:555`, `Substitute` at 615). A placeholder inside
  a var's value is pasted as written and never rendered. The gate runs the
  value as written too, so `origin/{{base_branch}}` inside a rig's command
  would be literal in both places.
- A sling-time `--var` override lives on the poured molecule's root bead
  (`gc.graphv2_vars.v1`). The gate reads no bead, so it cannot see one.

**No daemon.** `newFormulaShowCmd` resolves the city, loads its config, scopes
the rig (`rigFormulaVarsForScope`, `cmd/gc/cmd_formula.go:1389`) and compiles
the formula from its search paths. It opens no bead store and makes no API
call. It can wait on the machine-wide repo-cache lock while a
`gc import install` holds it.

**The rig is always passed as `--rig`.** The gate takes it from `--rig`, else
`$GC_RIG`, and hands it to gc as `--rig`, never through gc's own `$GC_RIG`
lookup. Probed on the running gc, 2026-10-13:

| call | answer |
|---|---|
| `--rig gc-toolkit` | `ok: true`, `rig_default` on `affected_tests_command` and `lint_command` |
| `--rig no-such-rig` | `ok: false`, exit 1, "rig is not registered in any city" |
| `GC_RIG=no-such-rig`, no `--rig` | `ok: true`, no `rig_default` at all |

The last row would read as a rig that declares no checks, and would record
vacuous passes. Through `--rig` an unknown rig is an error, which is a machine
failure (exit 4). When the rig comes from `$GC_RIG` and `$GC_RIG_ROOT` names its
clone, the gate also requires the checkout's git common directory to be that
clone's. One rig's commands are then never run against another rig's checkout
and recorded there.

**The base of the affected diff.** A pour sets `base_branch` from the bead's
own target, its convoy's, or the rig's default branch. The gate reads no bead,
so `--base` names it. A caller that has `{{base_branch}}` rendered passes it.
Without `--base` the gate takes the rig's own `base_branch` when the rig sets
one (a rig value outranks the routed one in a pour), else the branch
`origin/HEAD` names, else the formula's default.

## Decisions the bead left open

- **A pass with method `none`.** When the rig declares nothing to run, or
  `--affected` meets an empty diff and no full suite is declared, the gate
  records a pass whose method is `none` and whose command is empty. Without it,
  `--check` could never pass for a rig with no test command. `--check` reads no
  vars, by the ruling, so it cannot tell that rig from a commit nobody tested.
  A `none` record answers `--check` only. Every other call works out what to
  run again, so a command the rig declares later runs, and a `none` never
  replaces the record of a real run at the same commit.
- **Tree equivalence is test-only.** Only a full-suite test pass answers for
  another commit with the same tree. An affected pass does not, and neither
  does lint. This rig's `lint_command` lints the files in the diff against
  `origin/main`, so two commits with one tree can lint different files. The
  ruling's own phrase was "for a full-suite record". A full-suite fail
  withdraws the tree's entry, so the last write wins for the tree as well as
  for the commit.
- **Exit codes.** 0 pass, 1 fail, 2 usage, 3 nothing recorded (`--check`, and
  `--pre-existing` with no fail to mark), 4 machine failure, 128+N stopped by
  signal N. A fresh run exits 1 on any fail, whatever status the command
  exited with. The status itself is kept in the record's `exit_code`.
- **What counts as a machine failure.** A dirty tree, vars that cannot be
  read, and a command that `bash -n` cannot parse, which would otherwise record
  a fail at every commit for a typo in city.toml. Exits 126 and 127, which the
  shell gives a command it cannot execute or find. A command ended by a
  signal: killed outright, or 128+N from its shell, so an OOM kill under load
  never records a sticky fail. A timeout. A suite that exits 126, 127 or
  129-192 on its own is misread as a machine failure. That costs a re-run,
  never a false record.
- **`--pre-existing <tracker>`.** It annotates the fail recorded at HEAD with
  `disposition: pre-existing` and the tracker, and runs nothing. The cutover
  (tk-b0ww25t) makes no gate changes, and the refinery's pre-existing-failure
  path needs a way to write the annotation, so the hook ships here.
- **`--timeout`, default two hours.** The refinery stops its detached gate at
  two hours. Without a bound, a wedged suite under the lease heartbeat would
  hold its pool slot indefinitely. A timeout sends SIGTERM to the group, then
  SIGKILL after ten seconds.
- **A dirty tree is refused in every recorded mode, `--check` included.** A
  pass reported for a dirty tree would certify content no record saw. `setup`
  and `build` record nothing, so they run in a dirty tree.
- **The tree is checked before the run, not after.** A command that rewrites
  tracked files, such as a formatter that writes, still records against the
  commit it started from. Refusing on a tree the run dirtied would also refuse
  every suite that leaves an untracked artifact behind.
- **Publishing.** `--publish-bead` writes the record as one JSON value on
  `rig_check.<check>` (registered in `lifecycle/lifecycle.toml`) through
  `gcbd.Client.Update`, and reads it back with `ShowDirect`. gcbd's API path
  is for reads only. Its writes fork `gc bd update`, so the publish does too.
  The gate publishes the record that answered the call, whether it ran or read
  it. A failed publish warns and changes no exit.
- **The process group and the relay** follow `gitIn` on PR #1212 (Setpgid,
  TERM to the group, SIGTERM/SIGINT relayed, exit 128+N). That PR is unmerged,
  so the runner lives in `internal/rig`, and no package-level name in
  `internal/cli` collides with that branch's. A writer that is not a file is
  fed through a pipe whose wait `WaitDelay` bounds. The CLI hands its own
  stdout and stderr files to the command directly, so a child the command
  leaves running cannot hold the gate open.

## Measured cost

Apple M5 Pro (18 cores) at load average 40-47, 2026-10-13. In-process figures
come from `go test -bench`, three runs of 2000 iterations each. End-to-end
figures come from the built binary in a full clone of gc-toolkit (1085 tracked
files), timed with bash `EPOCHREALTIME`.

| what | cost |
|---|---|
| one record write: a full-suite pass, which writes the commit file and the tree entry (`Store.Put`) | 2.1-2.4 ms |
| one record read that finds the record (`Store.Lookup`) | 63-104 µs |
| `gctk version`, the process floor | median 27 ms (min 9) |
| `git rev-parse` for the checkout's four facts | median 42 ms (min 10) |
| `git status --porcelain` | median 53 ms (min 30) |
| `gctk rig test --check`, end to end | median 182 ms (min 53), n=31 |
| `gctk rig test --force` with command `true`, end to end | median 308 ms (min 224), n=11 |

A `--check` costs about one gctk start, one `git rev-parse` and one
`git status`, and the record read adds under a tenth of a millisecond. The gate
adds about a third of a second around any command it runs: those git calls plus
`gc formula show`, `bash -n` and the record write.

## What the cutover inherits

- **self-review-check.sh** runs in the condition sandbox, where `gc` can fail.
  It has to resolve the binary the way `gctk-resolve.sh` does
  (`$GCTK_BIN`, else the city's `.gc/services/gctk/bin/gctk`) without the
  `gc service list` step, and pass the loop only on `--check` exit 0. Exit 3
  is a commit nobody recorded, and exit 4 includes a dirty worktree.
- **review-test-evidence** reads `--check`'s one JSON line. `result`, `method`
  and `disposition` give the three branches the cutover names. A pass with
  method `none` certifies no tests.
- **The refinery** calls `--pre-existing <tracker>` after its tracker path. It
  should keep the gate's `--timeout` under its detached job's two-hour bound,
  so the job's own stop does not race the gate's.
- **The self-review** passes `--affected --base {{base_branch}}` and
  `--publish-bead $WORK_BEAD_ID`.
- **docs/component-model.md §4** places what a running city executes. Nothing
  calls `gctk rig` yet, so no row is owed here, and the cutover owes it once
  call sites run it.
- **The Go unit tests** under `services/gctk` run in no CI job (tk-gk06jad).
  `assets/scripts/gctk-resolve.test.sh` builds the binary and reaches
  `gctk rig` in CI, but the gate's semantics are proved only by `go test ./...`
  run by hand.
