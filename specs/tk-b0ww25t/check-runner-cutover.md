---
name: Every check-runner cut over to gctk rig, as built
description: What cutting the rig-check call sites over to `gctk rig` and retiring `self_review_passed_sha` settled beyond the bead. Covers why the self-review exit condition reads three records and a note of setup and build, the pre-existing mark that stands in for the disposition field the gate dropped and holds the record it judged, the transitional read of the retired stamp, how each caller finds the binary, and the refinery's exit-4 and time bounds.
---

# Every check-runner cut over to `gctk rig`, as built

The bead (tk-b0ww25t) carries out the ruling of sitting tk-gxh5whl (tk-kpanfqm)
as reshaped by the PR#1256 ruling (sitting tk-qjc4uaa), which made `gctk rig` a
pure executor: a caller passes the command and declares the run
([specs/tk-1hazlo2/rig-checks.md](../tk-1hazlo2/rig-checks.md), "What the
cutover inherits"). This records what the build decided on top of those.

## The call sites

| Caller | Checks it runs through the gate | Records land at |
|---|---|---|
| `mol-polecat-work` workspace-setup | setup | nothing is recorded |
| `mol-polecat-work` preflight-tests | typecheck, lint, test as the full suite | the base commit, shared by every polecat on that base |
| `mol-polecat-work` self-review | setup, typecheck, lint, build, then test: the affected subset, else the full suite, else a pass that ran nothing | the branch HEAD, published to the work bead, which also notes what setup and build did there |
| `mol-refinery-patrol` run-tests | setup, typecheck, lint, build, and test as the full suite when `run_tests` is true | the merged head the reviews are pinned to |
| the correctness method's review-test-evidence | reads `test --check`, and runs the suites the diff touches through the gate only when there is no record | the pinned commit |

The quorum's synthesis runs what the method runs, so it takes the evidence
block as it stands. `self-review-check.sh` reads the records with `--check`.

## The exit condition reads three records and a note of setup and build

The bead named `gctk rig test --check`. The stamp it replaces certified every
declared check: an iteration stamped only once lint, typecheck and build were
green too. A condition that read the test record alone would pass a lint
failure on to the refinery, the hop-later bounce the loop exists to stop. So
`self-review-check.sh` reads test, lint and typecheck at HEAD, and the
self-review records a pass that ran nothing (`--nothing-declared`) for a check
the rig declares no command for, so each check has a record to read.

setup and build record nothing, by the gate's design: setup leaves environment
state behind, and a build makes itself current. The first build took that to
mean the condition could not gate them, and the correctness review of
fde3f9212 showed a failing build converging the loop, because the block ran on
past the build's fail and the three records passed. So the block notes what
setup and build did on the work bead, `self_review_setup_build` =
`{"commit", "setup", "build"}`, each `pass`, `fail` or `none`, and the
condition converges only on a note naming the live HEAD with neither one
failed, whatever the records say. The block writes the note only on a tree
with no uncommitted change, since a build over such changes says nothing about
HEAD. A note an earlier iteration wrote at the same HEAD still answers, as a
record there does.

## A pre-existing failure is a mark beside the record

The pivot dropped `--pre-existing` and the record's disposition and tracker
fields, and left any annotation of a pre-existing fail to the cutover. Two
readers need one:

- **The self-review loop.** The old step let an agent stamp past a failure
  already red on the base, because the stamp was the agent's word. A record is
  the command's own exit, so with nothing beside it, a failure the diff did not
  cause would hold the loop until its budget ran out.
- **A correctness review at the merged head**, after the refinery merged on red,
  which the ruling keeps supported.

The mark is `rig_check_pre_existing.<check>` = `{"commit", "record",
"trackers"}`, and `assets/scripts/rig-check-pre-existing.sh` is its one writer.
It sits on a bead, beside the published copies (`rig_check.<check>`), so no
store was added beside the records. The writer reads the record itself, with
`--check` in the caller's worktree, and refuses unless it is a fail at the
commit the caller names. A call that declares another command or scope at that
commit runs and replaces the record, and its fail is not the one judged: a
changed formula var, or a full suite run where the affected subset failed. So
each reader honors a mark only while `--check` reads the very record it holds,
and a mark answers for neither another commit nor another run at its own. The
first build held only commit and trackers, and the correctness review of
fde3f9212 showed a replacement fail passing on the old tracker. A bead-keyed
stamp lacked the commit half of that property, which is why commit-keyed
records replaced it. The self-review writes the mark on the work bead, which
its condition reads. The refinery writes it on the anchor (the work
bead's `anchor_bead`, else the work bead), which the reviews read, so a rework
round's merged head is covered too. A mark names at least one tracker, so the
judgment can be audited.

## Runs poured before the cutover

A molecule keeps the step text it was poured with, while its exit condition runs
the rig checkout's current script (`gc.check_path` on the ralph control bead).
A run poured before the cutover stamps `self_review_passed_sha` and records
nothing, so the new condition alone would read nothing at HEAD on every
iteration and exhaust the run's budget. Seven molecules were in self-review or
before it when this was built. So `self-review-check.sh` takes the stamp, when
it names the live HEAD, in place of records only when nothing at all is
recorded there. Such a run notes no setup and build either, and its stamp
certified them, so the stamp naming HEAD stands in for that note too, also
where another run's records answer at the same HEAD. No pour writes the stamp
after the cutover, so the fallback answers for those runs alone. tk-57ormgo
removes it once a census finds none of them left in self-review. Until then
the key has one reader and no writer in the pack, and the registry marks it
RETIRED.

## Finding the binary

`gctk-resolve.sh` resolves for a bridge and execs, and its last step,
`gc service list`, can fail where the exit condition runs. Every direct caller
sets `GCTK` by one line instead: `$GCTK_BIN`, else the city's build under
`$GC_CITY_PATH`. gascity's condition env sets `GC_CITY_PATH`
(`internal/convergence/condition.go`, through
`citylayout.CityRuntimeEnvForRuntimeDir`). Formula text has no include
mechanism, so each copy sits in a `gctk-bin` block, and `gctk-bin.test.sh`
holds them to one line. The correctness method names no pack path (the STANDARDS
section of `review-method.test.sh`), so the review frame sets `GCTK` in its
`review-workspace-add` block, which the quorum's synthesis also runs.

## The refinery's bounds

- **Exit 4 says nothing about the code.** The gate exits 4 when a check stopped
  short of a verdict, ahead of any failure, and run-tests starts it once more.
  The checks that passed then answer from their records. A second stop at the
  same head takes the branch-caused path with `gctk rig`'s line as the reason,
  so the work goes to its author and not to ops, as the inheritance list asks.
- **Time.** `gate.sh` gives each check a `--timeout` that ends 7080 seconds into
  the gate, inside the wait's 7200-second limit, and starts no check with less
  than a minute left.
- **Stops.** Every stop and wait the patrol makes on the gate passes
  `DETACHED_JOB_STOP_GRACE=20`, above the ten seconds `gctk rig` takes to stop a
  command's group, so no command outlives a stop.
- **No publish.** The refinery publishes no record to a bead. The record
  answers `--check`, and the reviews read it there.

## Step size

Measured with PR #1217's renderer (formula defaults only, so an empty rig var
renders empty), before and after: `mol-polecat-work.self-review` 7,356 to
9,476, `preflight-tests` 11,377 to 12,338, `workspace-setup` 26,275 to 26,661;
`mol-refinery-patrol.run-tests` 11,283 to 13,349 and `handle-failures` 9,601 to
11,171. Each step that grew carries a heredoc per command it hands the gate and
the gate's exit handling, the self-review and handle-failures carry the
pre-existing mark, and the self-review notes setup and build. The self-review
stays under the 10,000-character hook cap with gc-toolkit's own commands
rendered in, at 9,657; handle-failures crosses it.
