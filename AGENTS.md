# gc-toolkit

This repository is the pack every rig in the city runs, and it is also a rig of
its own. The skills, formulas, agent prompts and template fragments it ships run
in every rig
([architecture.md](docs/architecture.md#what-the-pack-supplies-and-what-a-rig-supplies)),
so a rule that binds only work on this repository never goes into them. It goes
here when every session working on the repository needs it, and otherwise into
the doc or the check that owns it. Every session that works in a gc-toolkit
worktree loads this file.

A docs page is a right place for such a rule, even though the polecats' standard
keeps other guidance for an agent out of docs pages.

## Code the deletion plan retires gets no new work

The plan is the deletion schedule in
[built-once-target.md](docs/built-once-target.md#the-deletion-schedule), and the
page's rule 1 links the whole files each scheduled bead retires. A problem found
in that code is not a new fix. Append it to the notes of the bead that retires
the code, so the retirement carries it. A problem that already has a bead of its
own waits on that retirement: give it an `until` edge to the retiring bead (the
`gc-toolkit.waits` skill), which closes it once the retirement lands, and send it
nowhere. A first reaction does that through its `until` exit. A problem that
hurts the operator now gets the smallest stopgap that stops the harm, and no new
test suite.

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
