# gc-toolkit

This repository is the pack every rig in the city runs, and it is also a rig of
its own. The skills, formulas, agent prompts and template fragments it ships run
in every rig
([architecture.md](docs/architecture.md#what-the-pack-supplies-and-what-a-rig-supplies)),
so a rule that binds only work on this repository never goes into them. It goes
here when every session working on the repository needs it, and otherwise into
the doc or the check that owns it. Every session that works in a gc-toolkit
worktree loads this file.

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
