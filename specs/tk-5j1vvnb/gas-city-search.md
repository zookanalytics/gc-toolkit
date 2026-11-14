---
name: Gas City search for landing an effort hand-off's merge that changes no file
description: Use when you need the evidence that the refinery's landing of an integration effort's bring-current merge, whose resolution changes no file, composes Gas City, bd and git primitives, which upstream symbol each part uses, or why the merge carries a pack task_kind rather than a Gas City or bd type.
---

# Gas City search: an effort hand-off's merge that changes no file lands

When merging an integration effort's target into the effort's branch
conflicts, the refinery's hand-off (`effort-bring-current.sh`) files the merge
as a task for a polecat, and the polecat lands it on the branch as a
fast-forward. A resolution can keep the branch's side of every file the target
changed. The merge then changes no file, and the refinery's zero-diff guard
(`refinery-land.sh`) refused it as a false completion, which left the hand-off
and the landing bead waiting behind a person.

The change marks the task with `task_kind=effort-bring-current` in the create
that files it. The guard lands a bead of that kind on the direct path once its
head brings in commits of the effort's target that the branch lacks, where the
effort's target is the one the landing bead records. When origin refuses the
fast-forward, the guard parks the merge instead of opening a pull request. The
change adds one bead kind, the `task_kind` value `effort-bring-current`, whose
warrant is "An effort's bring-current merge" in `docs/warrants.md`, and one
landing condition in the guard. It adds no script, metadata key, lifecycle
state, order or bd type. Each primitive searched is below, with what it
covers.

Read at `gastownhall/gascity-packs` main 0f07496d2, `gastownhall/gascity` main
420b7bb65f and `github.com/steveyegge/beads` v1.3.4, the bd module that
`gastownhall/gascity`'s `go.mod` requires at 420b7bb65f, on 2026-11-14.

## What counts as a landing

**Gas Town's refinery refuses a branch with no change, unless its target
already carries it.** Covers every bead but this merge. In
`gastown/formulas/mol-refinery-patrol.toml`, `branch_has_real_change` reads a
branch as empty when `git diff --quiet` finds no change between it and its merge
base with the target ("no diff -> empty -> refuse"). The merge-push step's
"Merge-state gate" then halts it as a false completion: "a branch that
introduces no change vs its merge-base is definitionally not a merge", and
"Legit no-op resolutions use wontfix/duplicate/not-planned, never merged". Its
one exception closes a branch that is an ancestor of its target, with a commit
since its recorded `metadata.fork_sha`, as `already_merged`. The merge task's
branch is ahead of its target, not an ancestor of it, so that exception does not
reach it. The pack keeps the guard for every other bead and adds a landing for
the one case the guard has no answer to: a merge whose deliverable is the
commits it brings into a branch.

**Gas Town's integration branches have no bring-current while their work is in
flight.** The next-iteration step's `integration_branch_auto_land` assigns an
owned convoy's integration branch to the refinery once every child is closed,
and the refinery "merges the integration branch to {{target_branch}} normally".
Nothing in Gas Town's pack brings the integration branch current with its
target before that, so Gas Town has no merge task of this kind to land.

**A merge strategy says how a bead lands, not what counts as its change.**
`gc sling --merge` takes `direct`, `mr` or `local` (`docs/reference/cli.md`,
"gc sling"), `SlingMergeStrategy` in `internal/sling/sling.go` resolves it ahead
of the rig's `default_merge_strategy` (`docs/reference/config.md`), and none of
them says that a bead's change is the commits it brings in. The merge task keeps
`direct`, which its create and its `--merge direct` sling already set, and the
guard lands it only on that strategy, because a pull request lands by squash and
would leave out the commits the merge brings in.

**`gc convoy land` closes a convoy, not a branch.** `newConvoyLandCmd` in
`cmd/gc/cmd_convoy.go`: "Land an owned convoy, verifying all children are
closed", which "closes the convoy bead, and records a ConvoyClosed event". It
reads no git ref, so it cannot verify or land a merge.

## What marks the merge

**bd and Gas City have no type for a merge a pool works.** bd's built-in types
are the work types `bug`, `feature`, `task`, `epic`, `chore`, `decision`,
`spike`, `story` and `milestone`, and the system types `message`, `molecule`,
`gate` and `event` (`AllIssueTypes` and `TypeEvent` in
`internal/types/types.go`). None is a merge. Gas City registers `merge-request`
with every store it provisions (`RequiredCustomTypes` in
`internal/beads/custom_types.go`), but `Ready()` leaves that type out by default
as "processed by automation" (`readyExcludeTypes` in `internal/beads/beads.go`),
so a polecat pool would not be offered a task of that type. The merge stays a
`task`.

**Gas Town's `fork_sha` records where a branch was cut, not what a merge brings
in.** `gastown/formulas/mol-polecat-work.toml` stamps `metadata.fork_sha` with
the base the branch was cut from, which the already-merged exception reads. The
merge task's branch is cut from the effort's branch, so its fork point says
nothing about the effort's target.

**The pack's role marker: `task_kind`.** Composed. `lifecycle/lifecycle.toml`
declares `task_kind` as "the bead's role, the one field a reader decides a kind
from", set once at creation, and the pack's other kinds, such as `rework`,
`review`, `finding` and `validation`, already tell beads of one type apart by
it. The hand-off writes `effort-bring-current` in the create that files the
task, beside the `target` and `merge_strategy` it already writes there, so no
merge is filed without its kind, and a bead of any other kind meets the guard
whole.

## What verifies the merge

**The effort's target: the landing bead's `target`.** Existing pack record,
read where it lives. The landing bead records the effort's `branch` and the
`target` the effort lands on, and `effort-bring-current.sh` reads them to know
what to merge. The guard reads the same record: the open bead on the task's
target that names no other bead as its anchor. When no one target answers, the
merge is parked as before.

**What the merge brings in: git ancestry.** `git rev-list --count <effort
target> --not <task's target>` counts the commits of the effort's target that
the effort's branch lacks, and the same count with the head added after `--not`
counts those the head lacks as well. The difference is what the head brings in.
A merge that brings in none of them is parked as before.

**The landing and its record: the direct path.** Existing pack surface,
unchanged. `direct-merge-push.sh` fast-forwards the target, verifies the push
and records the bead `merged` through `lifecycle.sh`, and its
`direct_landing_sha` stamp still lets a later pass record a landing whose record
failed. Once the task closes, the hand-off is called again, finds the effort's
target already in the branch, and closes, as it does for any branch already
current.
