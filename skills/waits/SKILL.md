---
name: waits
description: Use when something must not go yet because it has to wait for other work to land, or for a person to decide or act. Covers making a bead wait on another (blocked by, depends on, after that lands), asking a person for a decision, a task or a conversation (a demand gate, a visit, escalating a blocker), having work start by itself once its wait clears (arming a deferred dispatch), and releasing a wait (resolving a demand, removing an edge, disarming). To send work that is free to go, use work; to hold a pull request's merge, use prs.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Waits: when work can go

A wait is an edge onto a bead, and a bead is either ready or blocked. There is
no parked state. What a person owes is a demand bead and what a pool owes is a
work bead, and either way the thing waiting carries a `blocks` edge to it, which
keeps it out of `bd ready` until that bead closes. Never write `triage.hold`,
and never leave a stamped, still bead as the record of a wait.

Each option says what the message means, who acts on it, and the one writer
that sends it. The writer's `--help` carries its flags. The writers are the
gc-toolkit pack's own scripts. `gc gc-toolkit scripts-dir` prints their
directory in the pack as gc loaded it, so each example calls the pack's copy
inside the command itself, and runs as written in a fresh shell.

## Make a bead wait on other work

The message is that this bead does not go until that one closes. bd acts on
it: the waiting bead stays out of `bd ready`, and once the blocker closes a
routed bead is offered to its pool again. A waiting bead with no route needs an
arm (below), or nothing sends it.

Writer: `gc bd dep add <waiting-bead> <blocker> --type=blocks`. Read the edge
back with `gc bd dep list <waiting-bead> --direction=down -t blocks`, because a
link across two stores prints success and lands nothing.

- The two are never parent and child. bd refuses a `blocks` edge from a parent
  to its own descendant, so file the blocker beside the bead (the work skill).
- A pull request's anchor that waits on an open bead cannot merge until that
  bead closes. When a follow-up needs the PR on main, make the follow-up wait
  on the anchor, never the anchor on the follow-up.

## Wait on a person

The message is that a person owes something before this bead goes. A decision
is filed unassigned. A task only a person can perform is assigned to them.

Writer: `"$(gc gc-toolkit scripts-dir)/gc-helm.sh" demand <bead> "<what is owed, at most 140 characters>"`,
with `--assignee <who>` for a task and `--body "<detail>"` for the rest. It
files the demand as a human gate beside the bead, blocks the bead on it, and
fails unless that edge reads back.

Who acts: an unassigned demand reaches the operator. The gate-visit sweep files
one visit for it, the operator engages that visit from the board, and the
sitting that settles the question resolves the gate. An assigned demand is that
person's to perform and close, and no visit is filed for it.

Write what is owed so the person can answer it in about a minute: the plain
stake and what each option costs, with ids only as references. In a sitting,
the hold step files the demand the conversation waits on.

## Ask for a sitting on another bead (a visit)

The message is that a bead needs a conversation with the operator. A visit
parks on the helm board until the operator engages it, which starts a converse
sitting on that bead.

Writer: `"$(gc gc-toolkit scripts-dir)/gc-helm.sh" open <bead> --reason "<what this visit needs>" --body "<the brief the sitting reads>"`.
`open` files one visit per bead. While a visit on the bead is open, it files
nothing and your brief goes nowhere, so append what you need to the bead's
notes (the records skill), where the sitting reads it.

For a blocker only a person can answer, escalate instead. It keeps one open
visit per bead and situation key, however often you hit it:
`"$(gc gc-toolkit scripts-dir)/escalate.sh" --subject <bead> --key <situation-key> --message "<what you hit, what you tried, what unblocks it>"`.
When the situation clears by itself, the same call with `--retract` closes
that visit, unless someone has already engaged it.

A visit keeps nothing out of `bd ready`. While it is open it holds only its
own subject's finalization: the subject's PR does not merge and the subject
does not close (`docs/finalize-gate.md`). To make other work wait on the
conversation, add a `blocks` edge from that work onto the visit.

## Have work start by itself when its wait clears (an arm)

The message is that once nothing holds this bead, it goes to this pool. The
deferred-dispatch order's reconcile pass slings it as soon as nothing holds it,
and retires the arm if the bead closes first.

Writer: `"$(gc gc-toolkit scripts-dir)/deferred-dispatch.sh" arm <bead> --target <rig>/<pool> --reason "waits for <blocker>"`.
Add `--sling-arg --on --sling-arg <formula>` to send it on a formula other than
the default. The bead must be open and carry no route.

Arm a blocked bead rather than leave it for someone to route once its blocker
lands: a blocked work bead with no route and no arm is the debt
`doctor/check-blocked-work-armed` reports. The intake rule that limits routing
limits arming too (the work skill).

## Release a wait

- **Work waiting on work** needs nothing: closing the blocker releases it. To
  drop a wait that no longer applies, `gc bd dep remove <waiting-bead> <blocker>`.
- **A decision a person owed** is released by the answer:
  `gc bd gate resolve <gate> --reason "<the answer>"`. In a sitting, the
  sign-off's `--ruled yes` resolves the demands its hold filed and releases a
  `held` bead (the converse-settle step).
- **An arm no longer wanted:** `"$(gc gc-toolkit scripts-dir)/deferred-dispatch.sh" disarm <bead> --reason "<why>"`.
- **A park** (`gc-helm.sh park`) is released by closing its gate, or for one
  bead by `gc bd dep remove <bead> <gate>` (`docs/steering.md`).

Release a bead's wait before you send it (the work skill): a worker builds
nothing that still waits.
