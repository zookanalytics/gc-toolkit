---
name: subject-lines
description: Use when you are about to write a commit subject or a PR title, such as choosing its conventional-commit type and scope, or naming a branch on the bead title its PR takes.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Subject lines

A commit subject and a PR title are one kind of line: `<type>(<scope>): <what
changes>`. The squash merge makes the PR title the commit subject on the target,
so that line is the change's name in the history.

Where a rig sets its own commit rules, its rules come first. Read them before you
choose: `docs/subject-lines.md` in the repository the change is in, when it has
that page, and any commit rules its `AGENTS.md`, `CLAUDE.md` or `CONTRIBUTING.md`
states or names.

**The type says what the diff does**, never what kind of bead asked for it. A
task can be a `fix`, and a bug's branch can be only a `test`. A title for a whole
branch takes the type of its purpose, so a fix with its test is a `fix`. A
prompt, a formula step or a skill is behavior: changing what an agent does is a
`fix` or a `feat`, not `docs`.

| Type | The diff |
|---|---|
| `fix` | corrects behavior that was wrong |
| `feat` | adds behavior, or changes what a working feature does |
| `refactor` | restructures or removes code and changes no behavior |
| `perf` | does the same work faster or cheaper |
| `test` | adds or corrects tests, and nothing they test |
| `docs` | changes documentation or records, and nothing that runs |
| `build` | changes the toolchain, dependencies or CI |
| `ops` | changes how a deployment runs: infrastructure, backups, recovery |
| `security` | closes a security exposure |
| `style` | changes formatting only |
| `revert` | undoes an earlier commit |
| `chore` | is upkeep no other row describes |

A formula step that lists fewer types does not narrow this table.

**The scope says where in the system the change sits**, and it is yours to decide,
as the type is. Where the rig's rules name scopes, use the one the change is
mostly about, as in `fix(api): ...`. With no list, or for a change that spans the
whole system, write none, as in `fix: ...`, and never coin a name of your own.

**The words name what changes rather than how**, as an imperative phrase that
starts in lowercase, at most 72 characters with the type and scope: `fix: keep an
open PR's title current after a rework`, not `fix: re-read the title in pr-stack's
loop`. The symptom, the reason and the detail go in the body and in `pr_summary`.
A bead's title is a label filed before the work, so reuse its words only where
they name what the diff does.

A `!` before the colon marks a change that breaks a caller.
