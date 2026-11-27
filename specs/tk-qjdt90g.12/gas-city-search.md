---
name: Gas City search for the pre-existing mark's move into gctk
description: The Gas City and bd primitives read for `gctk rig pre-existing`, which marks a recorded check fail as red on the target too and answers whether the mark holds, and for `gctk bead carrier`, which follows a closed bead's disposition edges to the open bead that carries its work, what each covers at a named upstream commit, and the measurement behind reading the store through gc where the self-review's exit condition asks. Read it to review either verb's surface, or before changing where the mark's question reads the store.
---

# Gas City search for the pre-existing mark's move into gctk

Read on 2026-11-26 at `gastownhall/gascity` main d38ec7842f8d,
`gastownhall/gascity-packs` main 44b9db7168f6, and bd v1.3.4, the release the
city runs. The change adds two verbs and moves five existing keys,
`rig_check_pre_existing.<check>`, from shell into gctk's rig domain. The mark
itself is not new: [specs/tk-23q3ytl/gas-city-search.md](../tk-23q3ytl/gas-city-search.md)
searched for a primitive that records a judged fail, at earlier commits, and
found none. This search re-reads what that one rests on at the heads above,
and adds the two needs the move brings: whether a tracker is still open, and
which store a check loop's condition can read.

## A recorded fail marked pre-existing

Nothing upstream records that one failing check at one commit is a known
failure of the target, for a later run at that commit to read. `core`'s
`mol-polecat-base` (`internal/bootstrap/packs/core/formulas/mol-polecat-base.toml`,
lines 174-180 and 281) judges a failure on the base "not yours" in the run that
meets it and files a `Pre-existing failure:` bug by title. `gastown`'s
`mol-refinery-patrol` (`gastown/formulas/mol-refinery-patrol.toml`, lines
601-662) diagnoses "branch regression or pre-existing on target?" and merges
once such a bug is filed or found. Neither writes which fail its judgment
covered, so a self-review's exit condition, or a review at the same commit,
cannot tell a judged fail from a new one. Gas City's check loop
(`internal/convergence/condition.go`, `RunCondition`) runs a condition script
and reads its exit, and holds no record of a check.

So the pack keeps its key and moves it beside the check records it excuses:
`gctk rig pre-existing` writes it and answers whether it holds.

## Whether a tracker is still open

The mark holds only while a tracker it names is open, and a tracker that a
fold closed carries its failure on through the bead the fold names. bd writes
that edge and reads it one hop at a time. `bd duplicate --of` and
`bd supersede --with` add a `duplicates` or `supersedes` edge and close the bead
(`runDuplicate` and `runSupersede` in `cmd/bd/duplicate.go`, lines 60-198).
`bd show --refs` prints the beads that point at one, each edge under its own
heading (`cmd/bd/show_refs.go`), and a listing's tree names the edge
`duplicates` or `superseded-by` (`cmd/bd/list_tree_deps.go`). `bd duplicates`
groups beads by identical content, which is another question. No bd read
follows a chain of such edges to the bead that carries the work now: bd's other
uses of the two types label them for display (`cmd/bd/dep_relation.go`).
Nothing in Gas City reads either type. At d38ec7842f8d the only string literal
in its Go outside tests that names one is `"duplicates"`, a bd verb in
`cmd/gc/bd_split_allowlist.go`'s list, which
`git grep -F -e '"duplicates"' -e '"supersedes"' d38ec7842f8d -- '*.go' ':!*_test.go'`
finds. Elsewhere in its Go the two words occur only in prose, such as
comments, and no script, formula or skill of its packs names either type.

So `gctk bead carrier` follows the chain, one read of each bead's listing row,
which carries an edge into another store where a `bd show` row leaves it out.
It is the walk `preexisting-failure.sh` made in shell, moved with its rules,
and the mark reads each tracker by the same walk.

## Where the self-review's exit condition reads the store

`self-review-check.sh` reads beads through bd alone, because its header holds
that `gc` can fail to start in the condition environment, where Gas City runs
it with `HOME` at the city (`internal/convergence/condition.go`,
`ConditionEnv.Environ`). The mark's question is gctk's, and gctk's store
adapter runs `gc bd`, so the move had to settle whether the question needs a
read through bd alone there. It does not, by this measurement, made on
2026-11-26:

- The review loop's condition, `review-passed-check.sh`, runs in the same
  environment and execs `gctk review passed`, which reads and writes through
  `gc bd` (`storeOf` in `services/gctk/internal/cli/review.go`). Of the 408
  review-loop controls in the gc-toolkit store, all created from 2026-11-17
  on, 335 passed, 22 failed, 46 were skipped, 2 were cancelled and 3 had no
  outcome yet. That counts `gc.outcome` over the rows of
  `gc bd --rig gc-toolkit list --metadata-field gc.kind=ralph --metadata-field gc.step_id=review-loop --all --include-infra --include-ephemeral --json --limit 0`,
  and the same read at 09:06Z gave 410 controls, 337 of them passed.
- No self-review or review-loop control in that store carries an error in
  `gc.controller_error`. At 09:06Z the same read gave 1,729 self-review
  controls (`gc.step_id=self-review`) and 410 review-loop controls. Of them,
  1,538 and 364 hold the key empty, and the rest do not hold it.
- `gc bd show` answered under the condition environment's `PATH` (the
  `~/.gc/run/gate-tools` link directory first), `HOME` at the city, `GC_HOME`
  and `BEADS_DIR` set as `ConditionEnv.Environ` sets them, twice.

A read through bd alone would accommodate a fault that does not fire here, so
the question reads through `gc bd` like every other gctk read, and gc routes
each bead it reads to the store its id names, a tracker in another rig's store
included. When gc does not start, the question answers that it could not read,
and the exit condition fails the check with gctk's reason, as it fails any read
it cannot make. Its own resolution, which does not ask the question, stays on
bd.
