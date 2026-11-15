# gc-toolkit

This repository is the pack every rig in the city runs, and it is also a rig of
its own. What it ships as the pack, such as its skills, formulas, scripts, agent
prompts and template fragments, runs in every rig
([architecture.md](docs/architecture.md#what-the-pack-supplies-and-what-a-rig-supplies)),
so a rule that binds only work on this repository is never written there. The
rule goes here when every session working on the repository needs it, and
otherwise into the doc or the check that owns it. Every session that works in a
gc-toolkit worktree loads this file.

A docs page is a right place for such a rule, even though the polecats' standard
keeps other guidance for an agent out of docs pages.

## Code the deletion plan retires gets no new work

The plan is the deletion schedule in
[built-once-target.md](docs/built-once-target.md#the-deletion-schedule), and the
page's rule 1 links the whole files each scheduled bead retires. A problem found
in that code is not a new fix. Append it to the notes of the bead that retires
the code, so the retirement carries it. A problem that already has a bead of its
own waits on that retirement and is sent nowhere else: give it a close brief, a
`blocks` edge onto the retiring bead, and an arm for the validating closer, which
checks it once the retirement lands and closes it or asks a person:

```bash
gc bd update <bead> --append-notes "## Close brief (held on <retiring-bead>, $(date -u +%Y-%m-%dT%H:%M:%SZ))
<what the retirement removes, and what to check once it lands>"
gc bd dep add <bead> <retiring-bead> --type=blocks
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
"$GCTK" bead arm <bead> --target gc-toolkit/gc-toolkit.polecat --on mol-validate-close --reason "waits for <retiring-bead>; the validating closer checks it once that closes"
```

Write the edge only when both beads carry one id prefix, and arm it only once
the add exits 0, as the `gc-toolkit.waits` skill says. A
first reaction does the same through its close exit, with
`--waiting-on <retiring-bead>`. A bead that carries `hold:mayor` keeps its arm
until the hold lifts, so once the arm lands, lift the hold: list its labels
(`gc bd label list <bead>`) and remove each one that spells `hold:mayor` in any
case, one `--remove-label` each
(`gc bd update <bead> --remove-label hold:mayor`), because bd removes a label
only by its exact text. A problem that hurts the operator now gets the smallest
stopgap that stops the harm, and no new test suite.

An epic is held to the plan as well. When you file an epic for this repository
or review one, read its boundaries against the schedule, because a scheduled
bead can already retire code the epic would change. The epic gives that code no
new work, so its boundaries name the code as work the epic is not, along with
the bead that retires it. At a review, boundaries that do not name such code
are a gap, and the change you propose names it.

## A change that adds operational surface shows its Gas City search

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

The arch check's divergence lens sends back a change without this record.
[review-arch.md](docs/review-arch.md) holds its method, the evidence it accepts
and its other checks.

## New pack code is written in Go, in gctk

New logic the pack runs is written in Go, in gctk, in the shape
[gctk-architecture.md](docs/gctk-architecture.md) sets, and a change adds no
new script for it. An order names gctk in its `exec` line, and a new file that
a caller requires, such as the `run.sh` Gas City runs for a doctor check, does
nothing but call gctk. Tooling that runs only on this repository, such as its
lint detectors and its test runner, is outside this rule.

A script that already exists takes a fix in place, where a fix corrects what
the script does and adds no verb, mode or key to it. Anything more is new code.
An intent moves into gctk whole, by the
[rules a domain move follows](docs/gctk-architecture.md#the-rules-a-domain-move-follows),
so a change that needs more from a script moves the intent it extends into
gctk, or waits on a bead that already moves that intent. Code the deletion plan
retires takes neither, because it
[gets no new work](#code-the-deletion-plan-retires-gets-no-new-work).

A design that would add a script, or grow one past a fix, says why gctk cannot
hold the logic, and a review sends back a change that does either without that
reason.

## A change to the pack's behavior names the foundation belief or goal it serves

This applies to a change that alters what an agent must do, or what reaches the
operator, through a skill, a formula, an agent prompt, a template fragment or a
doc that binds agents. Its PR summary names, in one sentence, the belief or goal
the change serves: one of the Core Beliefs in
[foundation.md](docs/foundation.md), or one of its goals.
