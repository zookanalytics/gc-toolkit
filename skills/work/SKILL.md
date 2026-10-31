---
name: work
description: Use when you have to say that something needs doing, carry out a decision about who does it, or change work already asked for, such as filing new work or a follow-up in the right rig and under the right parent or epic, routing, slinging or dispatching a bead to a pool on a formula, releasing a held bead, assigning it to an agent, choosing a formula or taking a recommended formula, stopping or redirecting work in flight, or closing or retiring a duplicate or a bead that needs no work. Not for doing the work yourself. To make work wait for something first, use waits; for a change that is already a pull request, use prs.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Work: what needs doing, and who does it

These are the ways to say that a bead needs work, who should do it, or that it
needs none. Each option says what the message means, who acts on it, and the
one writer that sends it. The writer's `--help` carries its flags. Doing the
work is a molecule's job, so nothing here changes a repo.

The writers are the gc-toolkit pack's own scripts.
`gc <binding> scripts-dir` prints their directory in the pack as gc loaded it,
so each example calls the pack's copy inside the command itself, and runs in a
fresh shell. `<binding>` is the name the city imports the pack under, which gc
puts in front of this skill's name: `gc-toolkit` in `gc-toolkit.work`.
`gc skill list` prints it in this skill's FROM column.

## File new work

A new bead says that work needs doing. Filing it starts nothing: send it, make
it wait, or leave it for placement.

- **A dependency goes beside the bead it came from, never under it.** Work
  that bead waits on is a dependency, and this is the default. bd refuses a
  `blocks` edge from a parent to its own descendant, so a child could never
  gate the bead it came from. Work already filed under the bead it came from
  stays where it is.
- **Work that genuinely decomposes an epic is a member of that epic.** A story
  or task that is part of the epic's work is filed with `--parent <that epic>`,
  even when the epic is the bead it came from. Nothing makes the epic wait on
  it with a `blocks` edge, because containment already carries that wait.
- **Give it a parent only when one applies.** A parent makes the bead a member
  of that epic: a park on the epic holds it, and the epic's priority ranks it.
  The parent of the bead it came from applies only when the new work serves the
  same epic. This prints that parent, or an empty line:
  `"$(gc <binding> scripts-dir)/converse-parent.sh" <bead>`. When no epic
  applies, give the bead no parent.
- **File it in the store of the pool that will work it.** A pool reads only its
  own rig's store, so a city-scoped session names the rig:
  `gc bd --rig <rig> create`.
- **Send it now when intake admits it, and hold only the rest.** Epics are how
  the operator steers which work runs, and membership is one of four ways in
  (`docs/steering.md`). A bead goes to a pool now when it is a member of an
  epic, when it is PR-finishing work carrying `anchor_bead`, when it is an
  emergency, or when the operator routed it in a sitting, by hand or by Accept.
  An emergency is a red main or a broken gate, confirmed by a check that failed
  on the default branch's head. Critical work the operator wants run now goes
  through the operator's own routing. Any other bead carries
  `placement=pending` in its create and no route or arm, and the operator's
  placement sitting places it.

Writer:

```bash
gc bd create "<title>" -t task -d "<what needs doing, why, and what done looks like>" --json
```

Add `--parent <epic>` when an epic applies, and
`--metadata '{"placement":"pending"}'` when intake holds the bead. The
description is the contract the worker reads.

## Send a bead to a pool on a formula

The message is that this pool does this work by this method. The pool's
workers claim the workflow the sling pours, and the formula's steps are their
plan.

Writer: `gc sling <rig>/<pool> <bead> --on <formula>`. With no `--on` it pours
the target's `default_sling_formula`, which for a polecat pool is
`mol-polecat-work`.

- **One dispatch, never two.** A sling pours a workflow and stamps
  `gc.execution_routed_to` on the bead. A raw route, `gc.routed_to=<pool>`,
  which a sitting's sign-off `--route <pool>` also writes when it releases a
  held subject, has the pool claim the bead itself. Send it one way. Both start
  two workers on one branch.
  An arm (`deferred-dispatch.sh arm`) is a sling the deferred-dispatch pass makes
  once nothing holds the bead. An armed subject keeps its arm through a sitting's
  hold and never reads `held`, so the sign-off releases nothing and writes no
  route, whatever `--route` says, and the gate's resolution lets the arm send it.
  When the ruling sends it as it was armed, send it nothing more. When it sends
  it some other way, or not at all, disarm it before the sign-off
  (`deferred-dispatch.sh disarm <bead>`).
- **Release its wait first.** A worker's first step builds nothing that still
  waits. It re-arms a bead with an open blocker to be sent again when the
  blocker closes, and it ends the run on a bead that carries a `merge_result`,
  `held` included, as finished. Release the wait (the waits skill), then send.
- **A named agent takes an assignee.** The mechanik, deacon, witness,
  refinery and keeper are named agents, and the assignee is what the
  controller and the pack's notice read to give one a turn
  (docs/deferred-dispatch.md). Send one of them a bead with
  `gc bd update <bead> --assignee <qualified-name>`, the name `gc agent list`
  prints, then tell it with
  `"$(gc <binding> scripts-dir)/deferred-dispatch.sh" notify <bead> --agent <qualified-name>`.

In a sitting, the sign-off's `--route` says where the subject itself goes once
its wait is released (the converse-settle step), so first decide which bead
carries the work:

- **The subject is the work.** Sign off with `--ruled yes --route human --no-wait`,
  then send the subject: `gc sling <rig>/<pool> <subject> --on <formula>`. The
  sling clears that human route. `--route <rig>/<pool>` would route the
  subject raw as well, a second dispatch.
- **New work carries it, and the subject waits for it.** File the work, send
  it, and sign off with `--ruled yes --route human --waiting-on <the work>`.
  The board shows the subject as a ruling in flight until the work lands, then
  as settled. A `--route <rig>/<pool>` here would have that pool claim the
  subject itself once the work lands, a conversation seed no worker can close.
- **New work decomposes an epic subject.** It is the subject's member: file it
  with `--parent <subject>`, send it, and sign off with
  `--ruled yes --route human --no-wait`. `--waiting-on` names a dependency
  only, because bd refuses a `blocks` edge from a parent to its own
  descendant, and containment already carries the wait. When the sitting also
  sent a dependency, name that one with `--waiting-on` in place of `--no-wait`.

## Take a recommendation

A first reaction that cannot route a bead itself records the formula it
recommends as `gc.recommended_formula`, and the operator decides. Take it only
on the operator's go. The pool on that formula acts.

Release the wait that put it to the operator (in a sitting, the sign-off for a
subject that is the work, above), send it on that formula, then record the
dispatch in one update, which runs only once the sling succeeded:

```bash
gc sling <rig>/<pool> <bead> --on <the recommended formula> \
  && gc bd update <bead> --set-metadata gc.recommended_formula_dispatched=<the formula> --unset-metadata gc.recommended_formula
```

The marker records the dispatch, and the strip stops a later visit from
offering Accept for work that already ran. Written over a failed sling, the
marker would record work that never went. The board's Accept reads the marker
as a dispatch already sent, so it would never send the work either. Outside a
sitting, the board's Accept is the operator's own form of this act, and it
refuses a visit that a sitting has engaged.

## Choose the formula

A formula is the method a pool's worker follows. Formulas are added and
improved over time, so read the current set rather than recall it:

```bash
gc formula list --rig <rig>               # every formula the rig can run
gc formula show <formula> --rig <rig>     # what one does, the variables that tune it, and its steps
```

Weigh what done looks like for the work:

1. **Nothing to build.** A judgment or a decision the operator owns has
   nothing to dispatch. Ask for a visit (the waits skill).
2. **A change to a repository that lands as one pull request.** That is what
   a polecat pool's default formula builds, so send it with no `--on`.
3. **Any other kind of done**, such as findings with no change, a design
   settled and reviewed before the build, or a demo. Read the descriptions of
   the formulas whose names fit, and send it on the one whose description says
   it produces that and fits work like this.

Patrol, review and validation formulas are the city's own machinery, poured
by its orders and its review cadence, not methods for new work. A formula's
variables are set with `--var <name>=<value>` on the sling. Name the formula
you chose, and why, when you put the choice to the operator.

## Stop or redirect work in flight

The message is that work already sent should stop, or go somewhere else.

- **Stop it.**
  `"$(gc <binding> scripts-dir)/gc-helm.sh" takeaway <bead> "<why it stops>" --release --no-wait`
  stops the run beneath the bead and leaves the bead open, unassigned and
  routed to no pool, with that sentence as its headline. When the bead now
  waits on something, pass `--waiting-on <bead>` in place of `--no-wait`.
- **Send it elsewhere.** The same release names where it goes, in one write:
  `"$(gc <binding> scripts-dir)/gc-helm.sh" takeaway <bead> "<where it goes now, and why>" --release --no-wait --route <rig>/<pool>`.
  For a named agent, pass `--assign <named-agent>` in place of
  `--route <rig>/<pool>`, then tell it with
  `"$(gc <binding> scripts-dir)/deferred-dispatch.sh" notify <bead> --agent <named-agent>`.
- **Withdraw a recommendation** the bead should not take, while the bead stays
  open for discussion:
  `SUBJECT=<bead> VISIT=<visit> "$(gc <binding> scripts-dir)/converse-invalidate-recommendation.sh" "<why it no longer holds>"`.
  It strips `gc.recommended_formula`, so the board stops offering Accept once
  no sitting holds the visit. When the bead itself should go, close it instead.

A pull request in flight is retired, not stopped (the prs skill).

## Close a bead that needs no work

The message is that nothing will be built for this bead. The writer closes it,
and nothing downstream picks it up. In a sitting, close a subject only on the
operator's agreement. The sitting's own open visit holds that close: the
writer records the pointer and exits 5, and the same call closes the subject
once the visit is closed.

Record the no-op, then close through the disposition writer, which runs only
once the record landed:

```bash
gc bd update <bead> --set-metadata gc.work_outcome=no-op \
  && "$(gc <binding> scripts-dir)/bead-rehome.sh" --origin <bead> --successor <successor> --kind not-needed --note "<why, one sentence>"
```

Under `not-needed` the successor is the evidence that ruled the work out, such
as the visit where it was decided. Under `duplicate`, `folded`, `re-homed` and
`fixed-upstream` it is the bead that carries the work now. The writer stamps
the pointer, reads it back and only then closes, so never close the bead by
hand: a close that names no successor reads as a careless one. On a bead
already closed by hand, the same writer adds the missing pointer.

- It fits a bead with no work in flight: unassigned, no branch or PR still in
  flight to a pool, and not a review, step or workflow bead. A bead with an open
  PR is retired instead (the prs skill), which closes the PR too. A bare
  `gc bd close` on a bead whose `merge_result` is not a closed state leaves its
  PR unlanded. Check the shape yourself: the doctor exempts a disposed bead, so
  nothing downstream checks it again.
- Disarm an armed bead first, so a wait released before the close lands cannot
  send it: `"$(gc <binding> scripts-dir)/deferred-dispatch.sh" disarm <bead> --reason "<why>"`.
- A bead that needs no work only once another bead lands is not closed now.
  Give it an `until` edge to that bead instead (the waits skill), and it is
  closed once that bead closes.

`docs/state-machine.md` ("Disposition") is the doctrine.
