---
name: Trigger evidence for the external-issue skill
description: Use when you need to know whether an agent loads the gc-toolkit.external-issue skill from its description alone, now that the polecat prompt carries no section on problems in software the rig does not own, or what a change to the description would have to re-measure.
---

# Trigger evidence for the external-issue skill

The polecat prompt no longer carries a section on problems in software the rig
does not own, so the skill reaches an agent only through its description. The
description this change ships is, word for word, the one a probe measured for
the skill's first draft:

> Use when you have identified a bug, gap or vulnerability in software this rig
> does not own, or when a gh write to such a repository was refused.

The probe's record is `specs/tk-nadehdk/skill-trigger-probe.md` at commit
b6ee2dee1, the head of the retired pull request #1367, kept by
`refs/pull/1367/head` on GitHub. It put a polecat given the prompt without the
section in front of a finding in a dependency, with made-up projects, and
counted the runs that loaded the skill:

| Provider | Runs on a finding in a dependency that loaded it | Control runs that loaded it |
|---|---|---|
| Claude | 58 of 58 | 0 of 19 |
| Codex | 21 of 21 | 0 of 9 |

The finding cases were a bug worked around, the same bug before any commit,
the same bug with the agent wanting the maintainers told, the same bug as an
aside in other work, a vulnerability found in passing, a gap (an option the
dependency lacks), and a `gh issue create` the origin guard refused. The controls were a bug in the rig's own code and a routine dependency
bump. On Claude every load was the run's first tool call.

## What carries and what does not

The load decision reads the name and the description only, and both are
unchanged, so the counts above stand for this change.

The body changed: it records a finding set aside instead of preparing a send.
The probe's other section, four cases that handed a run its lookup results and
read the tool call it prepared, measured the old body and does not carry. What
the new body asks is held by tests instead: `skill-needs.test.sh` pins the
commands it gives and the sends it never drafts, and `gh-origin-guard.test.sh`
runs each of its command blocks through the real guard and checks that every
refusal names the skill.

The probe's note on gaps still applies. With the word "gap" in the
description, runs treat a missing option as a finding, where without it they
did not. Under the old body each such finding cost the operator an ask. Under
this one it costs nothing until the operator opens the list, so the word stays.

A change to the description's words has to be measured again: the probe's
record says how its runs were built and read.
