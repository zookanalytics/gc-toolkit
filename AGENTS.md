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
"$(gc gc-toolkit scripts-dir)/deferred-dispatch.sh" arm <bead> --target gc-toolkit/gc-toolkit.polecat --sling-arg --on --sling-arg mol-validate-close --reason "waits for <retiring-bead>; the validating closer checks it once that closes"
```

Write the edge only when both beads carry one id prefix, and arm it only once
the add exits 0, as the `gc-toolkit.waits` skill says. A
first reaction does the same through its close exit, with
`--waiting-on <retiring-bead>`. A problem that hurts the operator now gets the
smallest stopgap that stops the harm, and no new test suite.

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
