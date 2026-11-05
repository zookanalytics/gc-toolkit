---
name: Commit conventions on gc-toolkit
description: Use when you write a commit subject or a PR title on this repository and have to decide its scope.
---

# Commit conventions on gc-toolkit

## Scope

**Mandate.** How commits and PR titles are named on this repository.

**Boundaries.** This page binds work on this repository only, so the pack's
content never carries it. The rules every rig shares are the
`gc-toolkit.commit-conventions` skill's, and that skill sends an author here.

## A scope is a subsystem the size comment names

Here the scope in a commit subject or a PR title, which the
`gc-toolkit.commit-conventions` skill has you decide, is a subsystem name from
`tools/measure.sh`. Those are the names each PR's size comment prints, so there
is no second list to keep. `shared` and `unplaced` name no area, so neither is
ever a scope.

Read the area off the diff with `tools/measure.sh --pr origin/<target> HEAD`. Its
table has one row for each subsystem the change touches, the most net lines
first. Take the one the change is mostly about, which is usually the first row,
though a rewrite's net lines can place it lower. Write no scope when the table
prints no row, as for a change only to docs, tooling or records, when `shared` or
`unplaced` holds most of the change, or when no one row does.
