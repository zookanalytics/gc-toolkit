# gc-toolkit

This repository is the pack every rig in the city runs, and it is also a rig of
its own. What it ships as the pack, such as its skills, formulas, scripts, agent
prompts and template fragments, runs in every rig
([architecture.md](docs/architecture.md#what-the-pack-supplies-and-what-a-rig-supplies)),
so a rule that binds only work on this repository is never written there. The
rule goes here only when a session can need it at any turn, before it could
think to load anything, and otherwise into the doc or the check that owns it. A
role's prompt and the fragments it composes meet the same bar: text one moment
needs, even a moment every run reaches, goes in a formula step or a skill that
step names. Every session that works in a gc-toolkit worktree loads this file.

A docs page is a right place for such a rule, even though the polecats' standard
keeps other guidance for an agent out of docs pages.

## Code the deletion plan retires gets no new work

The plan is the deletion schedule in
[built-once-target.md](docs/built-once-target.md#the-deletion-schedule), and the
page's rule 1 links the whole files each scheduled bead retires. A problem found
in that code is not a new fix. Append it to the notes of the bead that retires
the code, so the retirement carries it. A problem that already has a bead of its
own is folded into the retiring bead and sent nowhere else, by a session that
may close a bead as folded (the Close-with-successor row of
[authority-map.md](docs/authority-map.md)). Append the problem to the retiring
bead's notes, then close the bead as folded into it:

```bash
gc bd update <retiring-bead> --append-notes "## Folded in: <bead> ($(date -u +%Y-%m-%dT%H:%M:%SZ))
<the problem>. When this retirement lands, confirm it is gone with the code. If it survives into the replacement, it goes back to the queue as its own bead." \
  && "$(gc gc-toolkit scripts-dir)/bead-rehome.sh" --origin <bead> --successor <retiring-bead> --kind folded --note "it lives in <file>, which <retiring-bead> retires"
```

A session that may not, such as a first reaction or a polecat, holds the bead on
the retiring bead instead, as the `gc-toolkit.waits` skill's "Have a bead
checked and closed once other work lands" says. A problem that hurts the
operator now gets the smallest stopgap that stops the harm, and no new test
suite.

An epic is held to the plan as well. When you file an epic for this repository
or review one, read the schedule for code the epic's own work would change,
because a scheduled bead can already retire it. The epic gives that code no new
work, so its boundaries name the code as work the epic is not, in a clause that
says how the epic's work would change it and which bead retires it. Retiring
code the epic's work would not change gets no line, and an epic with none
carries no line about the schedule. At a review, both are gaps: retiring code
the epic's work would change that the boundaries leave out, and a line that
names retiring code without saying how the epic's work would change it. The
change you propose names the code with its connection, or removes a line that
has none.

## A change that adds operational surface or accommodates Gas City shows its Gas City search

This applies to a change that adds
[operational surface](docs/review-arch.md#when-the-lens-applies), such as a
script, a service or one of its commands, an order, a cluster of formula steps,
a metadata key, a bead kind or a lifecycle state. It also applies to a change
that grows existing surface with a new verb, mode or key, such as a script's new
flag, a new key in its output or a new diagnostic in a doctor check. Tests,
prompts, skills and a formula's prose are not surface.

Before building the surface, look for the Gas City or bd primitive that covers
the need, and compose that primitive when one does. When none does, name the
primitive you searched for and say why it does not cover the need, in the change
itself: in a commit message, in a spec such as
`specs/<bead-id>/gas-city-search.md`, or in a warrant the change adds. Cite it
by upstream page, or by symbol at a named upstream commit. A fork of Gas City
and the pack's own pages about Gas City are not evidence, and a commit body that
only explains the design shows no search.

A change that accommodates a behavior of Gas City, such as avoiding one of its
routes, mirroring one of its skips or working around one of its faults, shows
this record whether or not it adds surface. Its record also holds two things,
gathered before the accommodation is built:

1. The reason Gas City gives for the behavior, cited the same way and tested
   against this city's own setup and data. Show the measurement: what was
   counted, how and when, and the result, such as a census of the writes a
   store took while Gas City skipped it. A fault Gas City gives no reason for
   is measured by how often it fires here.
2. Where the behavior is a fault, or its reason does not hold here, the fix at
   the source, its size, and the bead that carries it, filed where the
   `gc-toolkit.external-issue` skill sends a problem in software this rig does
   not own.

The arch check's divergence lens sends back a change without this record.
[review-arch.md](docs/review-arch.md) holds its method, the evidence it accepts
and its other checks.

## New pack code is written in Go, in gctk

New logic the pack runs is written in Go, in gctk, in the shape
[gctk-architecture.md](docs/gctk-architecture.md) sets, unless gctk cannot hold
it or is inappropriate for it. Where gctk holds the logic, an exec order names
gctk in its `exec` line, and a new file that a caller requires, such as the
`run.sh` Gas City runs for a doctor check, does nothing but call gctk. The helm
board's own code, such as its web page and its ranking, stays in its service,
under [the board's composition](docs/gctk-architecture.md#compositions) in
gctk-architecture.md. Tooling that runs only on this repository, such as its
lint detectors and its test runner, is outside this rule.

A script that already exists takes a fix in place, where a fix corrects what
the script does and adds no verb, mode or key to it. A change that needs more
from a script grows it only where gctk cannot hold the growth or is
inappropriate for it. Otherwise the change moves the intent it extends into
gctk whole, by the
[rules a domain move follows](docs/gctk-architecture.md#the-rules-a-domain-move-follows),
or waits on a bead that already moves that intent. Code the deletion plan
retires takes neither a fix nor growth, because it
[gets no new work](#code-the-deletion-plan-retires-gets-no-new-work).

Logic gctk cannot hold includes the build that produces its own binary, and
logic it is inappropriate for includes code that only configures another tool,
such as the tmux key bindings each agent session installs. A change that adds a
script, or grows one past a fix, says in a sentence of its design or its PR
summary why gctk cannot hold that logic or is inappropriate for it. A review
sends the change back when the sentence is missing or gives only a preference,
such as bash being quicker to write, and asks for nothing more.

## A change to the pack's behavior names the foundation belief or goal it serves

This applies to a change that alters what an agent must do, or what reaches the
operator, through a skill, a formula, an agent prompt, a template fragment or a
doc that binds agents. Its PR summary names, in one sentence, the belief or goal
the change serves: one of the Core Beliefs in
[foundation.md](docs/foundation.md), or one of its goals.
