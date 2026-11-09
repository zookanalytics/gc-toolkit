---
name: waits
description: Use when something must not go yet because it has to wait for other work to land, or for a person to decide or act, such as making a bead wait on another (blocked by, depends on), a bead that is done or moot once that work lands and is checked then instead of coming back to triage, asking a person for an answer, an approval, an action or a conversation (filing a human gate and wiring the bead that waits to it, a blocker only a person can clear, its resolution), arming a deferred dispatch so work starts once its wait clears, or removing an edge or disarming. To send work that is free to go, use work; to hold a pull request's merge, use prs.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Waits: when work can go

A wait is an edge onto a bead, and there is no parked state. What a person owes
is a human gate and what a pool owes is a work bead. A bead that still has work
to do once that bead closes is blocked by it: a `blocks` edge keeps it out of
`bd ready` until that bead closes, and then it is ready. A bead whose whole job
ends when that bead closes is blocked by it too, and armed to the validating
closer, which checks it once that bead has closed and closes it or asks a
person. Never write `triage.hold`, and never leave a stamped, still bead as the
record of a wait.

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

Writer: `gc bd dep add <waiting-bead> <blocker> --type=blocks`, its exit saying
whether the edge landed. Write it only when both ids carry the same prefix, the
text before the first `-`, which names the store that holds the bead, because a
link across two stores prints success and holds nothing. When the prefixes
differ, the blocker is in another rig's store, so write no edge and make the
bead wait on a human gate in its own store that names the blocker (below),
which the operator clears once the blocker lands.

- The two are never parent and child. bd refuses a `blocks` edge from a parent
  to its own descendant, so never file the blocker under the bead that waits
  on it (the work skill).
- A pull request's anchor that waits on an open bead cannot merge until that
  bead closes. When a follow-up needs the PR on main, make the follow-up wait
  on the anchor, never the anchor on the follow-up.

## Have a bead checked and closed once other work lands

The message is that this bead's whole job ends once that one closes: when that
work lands, nothing should be left to do here, and someone must check that
nothing is. bd holds the bead out of `bd ready` until the blocker closes. Then
the deferred-dispatch order's reconcile pass slings the validating closer
(`mol-validate-close`) on it, which checks the close brief against what landed
and closes the bead, or puts it to a person when the landing did not end the
job. Nothing closes the bead unchecked, because the blocker can close without
the fix it promised.

Writers, in order: the close brief the closer checks, the edge, then the arm.
Write the edge only when `<bead>` and `<blocker>` carry the same id prefix, as
above.

```bash
gc bd update <bead> --append-notes "## Close brief (held on <blocker>, $(date -u +%Y-%m-%dT%H:%M:%SZ))
<what <blocker>'s landing fixes here, and what to check once it has>"
gc bd dep add <bead> <blocker> --type=blocks
"$(gc <binding> scripts-dir)/deferred-dispatch.sh" arm <bead> --target <rig>/gc-toolkit.polecat --sling-arg --on --sling-arg mol-validate-close --reason "waits for <blocker>; the validating closer checks it once that closes"
```

Arm only once the add exits 0. When the prefixes differ, the blocker is in
another rig's store, where an edge would hold nothing, so write no edge, arm
nothing, and ask a person to close the bead once the blocker lands (a human
gate, below).

- `<rig>` is the bead's own rig, whose polecat pool runs the closer, and the
  arm needs the bead open with no route. A first reaction writes the brief, the
  edge and the arm in one exit, its close exit with `--waiting-on <blocker>`.
- bd keeps one edge type per pair of beads and refuses a second, so a bead that
  already carries another edge type onto the blocker needs that edge removed
  first with `gc bd dep remove <bead> <blocker>`.
- bd also defines an `until` edge type. Nothing in the pack acts on one, so an
  `until` edge holds no bead and closes none.
- A converse sign-off writes the brief and the arm for its subject when the
  ruling leaves the subject waiting on work the sitting sent, after the
  headline writes the edge (`--waiting-on <work> --close-brief "<…>"`, the
  converse-settle step).

## Wait on a person

The message is that a person owes an answer, an approval or an action before
this bead goes. It is a human gate on the bead that waits: the gate blocks
that bead, which leaves `bd ready` and the pool's offer until a person clears
the gate, and the gate's title and message say what they must clear. The
operator sees it on the bead's row of the board and answers it there or in a
sitting.

Writer: the helper, when one open gate per bead and situation key matters,
however often you hit the situation, or when a recurring detector declares a
quiet period after a `moot` or `benign` answer:
`"$(gc <binding> scripts-dir)/human-gate.sh" --subject <bead> --key <situation-key> --message "<what is owed, at most 140 characters>"`.
The message's first line is the gate's title, and the whole message its
description. `--quiet-window <seconds>` keeps that period, and only a call
site that re-detects one persisting condition every pass declares it. When the
situation clears by itself, the same call with `--retract` resolves your own
gate as moot. A one-off wait needs no helper, and the native call files the
same gate:
`gc bd gate create --type=human --blocks <bead> --await-id <situation-key> --title "<what is owed, at most 140 characters>" --reason "<the detail>"`.

- **What it blocks is your choice.** A gate on a bead with open children
  pauses every part of it that has not started, and a child added later
  waits too. When only one member waits, file the gate on that member.
- **An action only a named person can perform**, when work waits on it, is
  such a gate assigned to that person after the create:
  `gc bd update <gate> --assignee <person>`. It is theirs to perform and
  clear. Work a person owes that nothing waits on is an ordinary bead
  assigned to them.
- **A situation with no bead of its own** is a patrol finding
  (`"$(gc <binding> scripts-dir)/patrol-finding.sh"`), because a wisp or a
  session names nothing that can wait and the helper refuses one. A first
  reaction puts the finding to a person as a human gate when it needs one.
- **Work you decline on a ruling** waits on the gate and is sent again once
  the gate is cleared:
  `"$(gc <binding> scripts-dir)/await-ruling.sh" <work-bead> --key <situation-key> --formula <formula>`
  gives the work bead its edge onto the gate and arms its re-sling. Clearing
  the gate is the ruling to proceed. A ruling not to proceed is a stand-down
  (below).

Write what is owed so the person can answer it in about a minute: the plain
stake and what each option costs, with ids only as references. In a sitting,
the hold step files the gate a wait for the operator's answer needs.

## Ask the operator for a conversation

The message is that a bead needs a conversation with the operator. A
conversation is a task that tracks the bead and waits in the operator's queue
until they engage it, which starts a converse sitting on it.

Writer: `"$(gc <binding> scripts-dir)/gc-helm.sh" open <bead> --reason "<what this conversation is about>" --body "<the ask the sitting reads>"`.
While a conversation on the bead waits in the queue, `open` files no second
one: it appends your concern to that conversation's notes, where the sitting
reads it, and a concern the conversation already carries is not appended again,
so a call that asks on every pass leaves one copy.

A conversation keeps nothing out of `bd ready`, and holds no merge and no
close: it blocks nothing, and nothing waits on it. When work must wait for
what the operator decides, file a human gate on that work as well (above).

## Have work start by itself when its wait clears (an arm)

The message is that once nothing holds this bead, it goes to this pool. The
deferred-dispatch order's reconcile pass slings it as soon as nothing holds it,
and retires the arm if the bead closes first.

What holds a bead is the store's own answer, which `gctk bead holds <bead>`
prints, from the gctk the city builds at
`$GC_CITY_PATH/.gc/services/gctk/bin/gctk`. A wait of the bead's own that has
not landed holds it, and so does one on a parent-child ancestor, such as a
parked epic, while its work has not started. Once its work has started, only
its own waits hold it. The answer names each wait behind it, so read it, not
the bead's rows, to learn whether a bead still waits and on what.

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
- **A bead checked once other work lands** needs nothing: the closer checks it
  once the blocker closes. To keep it as work instead, disarm it (below) and
  remove the edge: `gc bd dep remove <bead> <blocker>`.
- **A wait a person owed** is released by the answer:
  `gc bd gate resolve <gate> --reason "ruled: <the answer>"`. The reason opens
  with `ruled:` when the person decided, approved or acted, `moot:` when the
  premise no longer holds, and `benign:` when it holds but needs nobody. In a
  sitting, the sign-off's `--ruled yes` resolves the gates its conversation
  replies to (the converse-settle step), and its `--answer` resolves the gates
  a ruling settles on a turn that does not sign off (the converse-continue
  step).
- **A wait a person owed, when they rule the work will not go on:**
  `"$(gc <binding> scripts-dir)/stand-down.sh" <bead> --key <situation-key> --ruling "<the ruling, one sentence>"`,
  with the gate's `await_id` as the key. It removes the arm, ends the run beneath
  the bead, answers the gate with the ruling and closes the bead. Never answer
  the gate first and close afterwards: an armed bead is sent as soon as its gate
  clears, and bd refuses to close a bead an open gate blocks. A gate that also
  holds another open bead takes no answer here, so pass
  `--successor <the bead that records the ruling>`: this bead leaves the gate, and
  the gate goes on asking about the other one. Never remove that edge yourself
  first, because an armed bead off its gate is sent too. It refuses, writing
  nothing, an open PR (retire it, the prs skill) and a bead anything else holds.
- **An arm no longer wanted:** `"$(gc <binding> scripts-dir)/deferred-dispatch.sh" disarm <bead> --reason "<why>"`.
- **A park** (`gc-helm.sh park`) is released by closing its gate,
  `gc bd close <gate>`, or for one bead by `gc bd dep remove <bead> <gate>`
  (`docs/steering.md`).

Release a bead's wait before you send it (the work skill): a worker builds
nothing that still waits.
