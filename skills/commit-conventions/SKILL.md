---
name: commit-conventions
description: Use when you are about to write a commit subject, a PR title or a PR's summary, such as choosing its conventional-commit type and scope, naming a branch on the bead title its PR takes, or composing the summary a PR publishes.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Commit conventions

A commit subject and a PR title are one kind of line: `<type>(<scope>): <what
changes>`. The squash merge makes the PR title the commit subject on the target,
so that line is the change's name in the history.

Where a rig sets its own commit rules, its rules come first. Read them before you
choose: `docs/commit-conventions.md` in the repository the change is in, when it has
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
loop`. The symptom, the reason and the detail go in the body and in the PR summary.
A bead's title is a label filed before the work, so reuse its words only where
they name what the diff does.

A `!` before the colon marks a change that breaks a caller.

## A PR's summary

`pr-open.sh` publishes the summary recorded on the branch's anchor, the bead its PR
is composed from, as the PR's `## Summary`. With none it falls back to the anchor's
description: the dispatch text, written before the diff existed and addressed to
the agent doing the work, not to a reviewer. You are the one who has read the
diff, so say what changed and why, for a reviewer who was not in the conversation
the work came from.

**The summary opens with a brief the operator can answer in about a minute**,
because they accept or reject a PR from its summary. The brief is in plain words,
with any identifier in parentheses. It says what approving changes and what that
costs, and names anything approving sets in motion or has to wait for, such as a
build that starts on merge or a branch that must not deploy before another lands.
A branch that asks the operator to decide something more, such as a design doc's
decision for them or a call the branch made for them that costs something either
way, opens on that decision: the stake, every option and what it costs, which
option the branch takes, and what happens if they do not decide. Leave out what
does not apply, so a small change's brief can be a sentence or two.

**The account of the diff follows the brief**: the behavior before, the behavior
now, and the shape of the change, in a short paragraph or a few bullets of
markdown. Anything that would take the open text past one screen goes in a
collapsed section.

**The summary describes the branch, not the pass that writes it.** On a rework or
a rebase the PR publishes the whole branch, so an account of only the fix you just
made describes something no reviewer is looking at. Every stamp owes the same
brief, a restamp as much as the first composition, and a summary stamped earlier
stands only if it opens with one. Rewrite the brief to the branch's current state
instead of extending it, put a new qualification of its headline beside the
headline, and put the round's mechanics in the account.
