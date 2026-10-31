---
name: Listing the warrants a branch touches
description: The Gas City and bd search behind tools/warrants-touched.sh, why the list runs through the rig's lint, and its backtest over main's history. Read it when you change the list, or when you ask what it can miss or how often it says too much.
---

# Listing the warrants a branch touches

Four arch reviews sent work back for one missing record: a branch touched what a
warrant covers and did not re-verify it. The authors meant no harm and the
reviewers raised no question about behavior. The page told a change to search it
for the paths in its diff, and nothing did that search until the arch review.

## The Gas City and bd search

Read at `gastownhall/gascity` main d1a150cac8f8 and `gastownhall/beads` main
4a92834d575f, on 2026-10-31.

The need is one read: given a branch, which dated records in this repository name
what the branch changes. No primitive answers it.

- `gc lint <pack>` (`docs/reference/cli.md`, *gc lint*) validates `pack.toml` and
  parses prompt templates. It reads no diff and takes no rule of a pack's own.
- `gc doctor --check` (`docs/reference/cli.md`, *gc doctor*) runs health checks
  on the city, its stores and its sessions. It takes no branch or diff.
- `gc converge` and its `test-gate` (`docs/reference/cli.md`) run and dry-run a
  bounded loop's gate. They hold no mapping from a path to a record.
- `bd preflight` (`docs/cli-reference/preflight.md`) is a fixed checklist for
  bd's own contributors, and it takes no registry and no path.
- `bd lint` (`docs/cli-reference/lint.md`) checks issues for missing sections by
  issue type. It reads beads, not a change.
- A case-insensitive grep of `docs`, `engdocs` and `internal/bootstrap/packs` for
  changed paths, path filters, pathspecs and CODEOWNERS finds CI design notes and
  mentions of GitHub's CODEOWNERS, which routes review by path and keeps no dated
  record.

One primitive does the rest, and the list composes it. A rig declares its lint in
`[rigs.formula_vars]` (`engdocs/architecture/formulas.md`), and core's
`mol-polecat-base.toml` runs `lint_command` at self-review, as the pack's
`mol-polecat-work` does. The city already sets that var for this rig.

## Where the list runs

`tools/lint.sh` runs it, through the `lint_command` the town declares for this
rig. A rig's lint is the rig's own, so the rule stays out of the formulas, skills
and fragments every rig runs, and neither the pack nor the town changes. The
alternatives each cost more: a line in self-review's step text puts a rule of this
repository in pack content, and a new formula var for a rig's own listing adds
pack surface and a town flip for one reader.

The list is advice and fails no lint. A failing lint would also stop the refinery,
which runs the same command at merge, on a list that says too much by design. The
arch review keeps the judgment, as the bead asks.

A run recorded at a commit answers from its record without running again
(`gctk rig`), so a later self-review iteration at an unchanged head prints no
list. The iteration that ran the lint at that head saw it, and a re-verification
makes a new head.

## What the list counts

A file Covers names whole is touched by any change to it. A key or a name is
touched by a changed line of code or config that names it whole. A named block or
table is touched only by a change inside it, which keeps the most-edited files
quiet: `lifecycle/lifecycle.toml` took 82 commits between 2026-10-01 and
2026-10-31, and only the tables Covers names matter. A stale block name counts the
whole file, so a wrong name lists too much rather than nothing.

A file Covers names for one part of it, such as "the `priority` verb of
`assets/scripts/gc-helm.sh`", cannot be narrowed without reading that language, so
it lists on any change to the file and prints the Covers line for the author to
judge. The page now states that such a file is touched only when the change
reaches that part. That sentence is this change's reading, not a ruling anyone
gave: it matches what the arch check has passed (below), and a reviewer who holds
otherwise can say so on the page.

## The backtest

The list ran over each first-parent commit on main since the page landed, from
7ed87f73f to f6965764b, measured against its own parent, with the page and the
tree that commit carried. It covers 51 commits.

- **Recall.** All 12 warrants an author re-dated or added in those commits are on
  that commit's list.
- **The send-backs.** At the commit each arch review read, before the rework, the
  list names the warrant the review named: `polecat/tk-5u2xpan` before c45343824,
  `polecat/tk-r451fjm` before bb2c3bfc1, `polecat/tk-8fajj0n` at 1b7f248c9, and
  `polecat/tk-60i7nl6` before d25cf5c8.
- **How often it speaks.** It lists something on 19 of the 51 commits, 27 entries
  in all: 7 the commit re-dated, 5 it added, and 15 it left alone.

Of those 15, 2 are real touches that shipped without a re-date, and the other 13
are a file named for one part of it, edited elsewhere:

| Listed | Commits | What the edit reached |
|---|---|---|
| Priority following, for `assets/scripts/gc-helm.sh` | 7 | No hunk inside `cmd_priority` |
| Priority following, for `docs/steering.md` | 3 | No hunk inside its `## Priority` |
| Machine axis and Owed status label clear, for `services/gctk/internal/cli/merge.go` | 2 entries on 90d0a84ec | Hunks in `handle` and after `clearStatusLabel` |
| Machine axis, for `services/helm/internal/board/derive.go` | 1 | The epic rollup |
| Priority following, whole | be047f3d0 | `queue-priority.sh`, `priority-lib.sh`, `priority_shift` |
| Prep worktree staging record, whole | ae5c1efcc | `refinery-workspace.sh`, the `prep-staged-work` block, `direct-merge-push.sh` |

Keeping keys out of markdown and tests changed no entry on any list. It only
shortens the lines that name where a key changed.

## What it can miss

The list sees what Covers names. A warrant whose Covers leaves out part of its
surface leaves that part off the list, as gh write containment's did for the
guard's wiring until this change named it. The suite reads the real page and fails
on an entry naming nothing the list reads, or a path, block, table or name the tree
no longer carries.

`tools/lint.sh` measures from `origin/main`, because that is what the rig's
`lint_command` names. On a member of an effort's branch the list therefore also
shows what earlier members touched, which the effort's pull request into main owes
all the same. The list's first line names the base it read.
