---
name: waits
description: Use when something must not go yet because it has to wait for other work to land, or for a person to decide or act. Covers making a bead wait on another (blocked by, depends on, after that lands), having a bead close by itself when the work that resolves it lands, instead of coming back to triage (an until edge, for a bead that is done or moot once that lands), asking a person for a decision, a task or a conversation (a demand gate, a visit, escalating a blocker), having work start by itself once its wait clears (arming a deferred dispatch), and releasing a wait (resolving a demand, removing an edge, disarming). To send work that is free to go, use work; to hold a pull request's merge, use prs.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Waits: when work can go

A wait is an edge onto a bead, and there is no parked state. What a person owes
is a demand bead and what a pool owes is a work bead. A bead that still has work
to do once that bead closes is blocked by it: a `blocks` edge keeps it out of
`bd ready` until that bead closes, and then it is ready. A bead whose whole job
ends when that bead closes carries an `until` edge to it instead, and is closed
once that bead has closed. Never write `triage.hold`, and never leave a
stamped, still bead as the record of a wait.

Each option says what the message means, who acts on it, and the one writer
that sends it. The writer's `--help` carries its flags. The writers are the
gc-toolkit pack's own scripts. `gc <binding> scripts-dir` prints their
directory in the pack as gc loaded it, so each example calls the pack's copy
inside the command itself, and runs in a fresh shell. `<binding>` is the name
the city imports the pack under, which gc puts in front of this skill's name:
`gc-toolkit` in `gc-toolkit.waits`. `gc skill list` prints it in this skill's
FROM column.

## Make a bead wait on other work

The message is that this bead does not go until that one closes. bd acts on
it: the waiting bead stays out of `bd ready`, and once the blocker closes a
routed bead is offered to its pool again. A waiting bead with no route needs an
arm (below), or nothing sends it.

Writer: `gc bd dep add <waiting-bead> <blocker> --type=blocks`. Read the edge
back with `gc bd dep list <waiting-bead> --direction=down -t blocks`, because a
link across two stores prints success and holds nothing. When it does not read
back, the blocker is in another rig's store, so remove that edge and make the
bead wait on a demand in its own store that names the blocker (below), which
the operator resolves once the blocker lands.

- The two are never parent and child. bd refuses a `blocks` edge from a parent
  to its own descendant, so never file the blocker under the bead that waits
  on it (the work skill).
- A pull request's anchor that waits on an open bead cannot merge until that
  bead closes. When a follow-up needs the PR on main, make the follow-up wait
  on the anchor, never the anchor on the follow-up.

## Have a bead close by itself when other work lands

The message is that this bead's whole job ends once that one closes: when that
work lands, nothing is left to do here. The deferred-dispatch order's reconcile
pass acts on it. Once every `until` target of the bead has closed, the pass
closes the bead through `bead-rehome.sh`, pointing it at the target that closed
last (`gc.superseded_by`), instead of letting it come back to triage as fresh
work.

Writer: `gc bd dep add <bead> <target> --type=until`. Read the edge back with
`gc bd dep list <bead> --direction=down -t until`. When it does not read back,
the target is in another rig's store, where the pass cannot see it close, so
remove that edge and ask a person to close the bead once the target lands (a
demand, below).

- bd keeps one edge type per pair of beads and refuses a second, so the bead
  carries `until` to its target and not `blocks` as well. To turn a `blocks`
  wait into this one, remove that edge first with
  `gc bd dep remove <bead> <target>`.
- `until` does not block, so the bead reads as ready while its target is open.
  Give it no route and no arm: a pool takes a routed bead that is ready, the
  next pass sends an armed one, and the pass never closes a bead that has
  either. Disarm an arm it has (below).
- The pass closes only a pure wait: an open, unassigned bead that no open
  `blocks` blocker of its own holds and that carries no live work. Live work
  includes a route or an arm, a branch or a PR, a `task_kind`, an open child, a
  convoy that tracks the bead, and an issue type other than task, bug, feature,
  chore or spike. `assets/scripts/live-work.sh` defines every mark. The pass
  leaves a resolved bead with live work open, and
  `doctor/check-until-resolved-owed` reports it as a decision for a person.
- A headline on the bead (the records skill) takes `--no-wait`, because
  nothing holds it: `--waiting-on` writes a `blocks` edge, which bd refuses
  beside the `until` one.

## Wait on a person

The message is that a person owes something before this bead goes. A decision
is filed unassigned. A task only a person can perform is assigned to them.

Writer: `"$(gc <binding> scripts-dir)/gc-helm.sh" demand <bead> "<what is owed, at most 140 characters>"`,
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

Writer: `"$(gc <binding> scripts-dir)/gc-helm.sh" open <bead> --reason "<what this visit needs>" --body "<the brief the sitting reads>"`.
`open` files one visit per bead. While a visit on the bead is open, it files
nothing and your brief goes nowhere, so append what you need to the bead's
notes (the records skill), where the sitting reads it.

For a blocker only a person can answer, escalate instead. It keeps one open
visit per bead and situation key, however often you hit it:
`"$(gc <binding> scripts-dir)/escalate.sh" --subject <bead> --key <situation-key> --message "<what you hit, what you tried, what unblocks it>"`.
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

Writer: `"$(gc <binding> scripts-dir)/deferred-dispatch.sh" arm <bead> --target <rig>/<pool> --reason "waits for <blocker>"`.
Add `--sling-arg --on --sling-arg <formula>` to send it on a formula other than
the default. The bead must be open and carry no route.

Arm a blocked bead rather than leave it for someone to route once its blocker
lands: a blocked work bead with no route and no arm is the debt
`doctor/check-blocked-work-armed` reports. The intake rule that limits routing
limits arming too (the work skill).

## Release a wait

- **Work waiting on work** needs nothing: closing the blocker releases it. To
  drop a wait that no longer applies, `gc bd dep remove <waiting-bead> <blocker>`.
- **A bead other work resolves** needs nothing: the pass closes it. To keep it,
  remove the edge: `gc bd dep remove <bead> <target>`.
- **A decision a person owed** is released by the answer:
  `gc bd gate resolve <gate> --reason "<the answer>"`. In a sitting, the
  sign-off's `--ruled yes` resolves the demands its hold filed and releases a
  `held` bead (the converse-settle step).
- **An arm no longer wanted:** `"$(gc <binding> scripts-dir)/deferred-dispatch.sh" disarm <bead> --reason "<why>"`.
- **A park** (`gc-helm.sh park`) is released by closing its gate,
  `gc bd close <gate>`, or for one bead by `gc bd dep remove <bead> <gate>`
  (`docs/steering.md`).

Release a bead's wait before you send it (the work skill): a worker builds
nothing that still waits.
