---
name: work
description: Use when you have to say that something needs doing, carry out a decision about who does it, or change work already asked for, such as filing new work or a follow-up in the right rig and under the right parent or epic, routing, slinging or dispatching a bead to a pool on a formula, releasing a held bead, assigning it to an agent, choosing a formula or taking a recommended formula, stopping or redirecting work in flight, or closing or retiring a duplicate or a bead that needs no work. Not for doing the work yourself. To make work wait for something first, use waits; for a change that is already a pull request, use prs.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Work: file it, send it, stop it, or close it

Use this skill to file new work, send a bead to a pool or a named agent, stand
up an integration effort, take a recommended formula, choose a formula, stop or
redirect work in flight, or close a bead that needs no work. The pool or agent
you send a bead to does the work.

Commands call the gc-toolkit pack's scripts as
`"$(gc <binding> scripts-dir)/<script>"`, and only that way. The call looks up
the pack gc loaded inside the command, so it runs no checkout's copy and needs
nothing an earlier call set. `<binding>` is the name the city imports the pack
under, which gc puts in front of this skill's name: `gc-toolkit` in
`gc-toolkit.work`. `gc skill list` prints it in this skill's FROM column. A
script's `--help` lists its flags.

## File new work

File a bead for the work. Its description is the contract the worker reads:

```bash
gc bd create "<title>" -t task -d "<what needs doing, why, and what done looks like>" --json
```

Add `--parent <epic>` when an epic applies, and
`--metadata '{"placement":"pending"}'` when intake holds the bead (below).
Filing starts nothing: afterwards, send the bead, make it wait (the waits
skill), or leave it for the operator to place.

- **File it in the store of the pool that will work it.** A pool reads only its
  own rig's store, so a city-scoped session names the rig:
  `gc bd --rig <rig> create`.
- **A dependency goes beside the bead it came from, never under it.** A
  dependency is work the bead it came from waits on, and it is the default. bd
  refuses a `blocks` edge from a parent to its own descendant, so a child could
  never gate the bead it came from. Leave work already filed under the bead it
  came from where it is.
- **Work that genuinely decomposes an epic is a member of that epic.** File it
  with `--parent <that epic>`, even when the epic is the bead it came from. Add
  no `blocks` edge that makes the epic wait on it: an epic already waits on its
  members.
- **Give it a parent only when one applies.** A parent makes the bead a member
  of its epic: a park on the epic holds the bead, and the epic's priority ranks
  it. The parent of the bead it came from applies only when the new work serves
  the same epic. Find it with
  `"$(gc <binding> scripts-dir)/converse-parent.sh" <bead>`.
  This prints that parent, or the nearest open bead above it once that parent
  has closed, or an empty line when none is open. Never file under a closed
  parent: work there follows no priority and sits under no open row. A non-zero
  exit means a bead on the way could not be read, not that there is no parent.
  When no epic applies, give the bead no parent.
- **Under an epic, file it in the open Delivery whose aim covers it.** A
  Delivery is a child epic that lands a bounded step toward its epic's
  hypothesis, and its description opens with an `Aim:` line (`docs/epics.md`).
  Before filing under an epic, list its open Deliveries and read each aim:
  `gc bd list --parent <epic> -t epic --limit 0 --json`. A list that errors is
  not an empty answer. File work an open Delivery's aim covers under that
  Delivery, and other work under the epic itself, where the epic's next
  checkpoint gathers it into a Delivery or leaves it. Check a Delivery that
  `converse-parent.sh` prints the same way: when its aim does not cover the
  work, file under its epic. A Delivery whose Stories, the beads under it, have
  all closed has landed. It stays open until its checkpoint, and until then
  takes only work its aim covers, such as a follow-up that finishes one of its
  Stories.
- **Send it now only when intake admits it.** Intake admits a member of an
  epic, PR-finishing work carrying `anchor_bead`, an emergency, and work the
  operator routed in a sitting, by hand or by Accept. An emergency is a red main
  or a broken gate, confirmed by a check that failed on the default branch's
  head. Critical work the operator wants run now goes through the operator's
  own routing. File any other bead with `placement=pending` in its create and
  no route or arm: the operator's placement sitting places it.

### File a Delivery

A Delivery is filed only by the decision that aims it, and that decision is the
operator's:

- the sitting that elaborates an epic and aims its first Delivery;
- the approval of a design whose units deliver it, after which the units are
  filed as its Stories;
- an Epic Checkpoint's continue or shift ruling that aims the next one.

A product area, a theme or a wish to find work on the board files none. List
the epic's open Deliveries first, and file a new one only once the list has
succeeded and no open Delivery's aim already covers the work. Start its title
with `Delivery: `, and open its description with the `Aim:` and `Done when:`
lines. Send it to no pool: its Stories are the work.

```bash
gc bd list --parent <epic> -t epic --limit 0 --json
gc bd create "Delivery: <what it lands>" -t epic --parent <epic> \
  -d "Aim: <the portion of the epic's hypothesis its landing tests>
Done when: <what lands>" --json
```

## Send a bead to a pool on a formula

Choose the formula (below), then sling the bead to the pool:

```bash
gc sling <rig>/<pool> <bead> --on <formula>
```

With no `--on`, the sling pours the target's `default_sling_formula`, which for
a polecat pool is `mol-polecat-work`.

- **One dispatch, never two.** A sling pours a workflow and stamps
  `gc.execution_routed_to` on the bead. A raw route, `gc.routed_to=<pool>`,
  which a sitting's sign-off `--route <pool>` also writes when it releases a
  held subject, has the pool claim the bead itself. An arm
  (`deferred-dispatch.sh arm`) has the deferred-dispatch pass sling the bead
  once nothing holds it. Send it one way, and disarm an armed bead before you
  send it another. Any two start two workers on one branch.
- **Release its wait first.** A worker's first step builds nothing that still
  waits. It re-arms a bead with an open blocker to be sent again when the
  blocker closes, and it ends the run on a bead that carries a `merge_result`,
  `held` included, as finished. Release the wait (the waits skill), then send.

### In a sitting, decide which bead carries the work

The sign-off's `--route` says where the subject itself goes once its wait is
released (the converse-settle step). Sign off by the case that fits:

- **The subject is the work.** Sign off with
  `--ruled yes --route human --no-wait`, then send the subject:
  `gc sling <rig>/<pool> <subject> --on <formula>`. The sling clears that human
  route. Never sign off with `--route <rig>/<pool>` here: it routes the subject
  raw as well, a second dispatch. When the formula is the one the subject
  recommends, add `--accept` to the same sign-off and send nothing yourself
  (Take a recommendation, below).
- **New work carries it, and the subject waits for it.** File the work, send
  it, and sign off with `--ruled yes --route human --waiting-on <the work>`.
  Never sign off with `--route <rig>/<pool>` here: that pool would claim the
  subject itself once the work lands, with nothing left on it to build.
- **New work decomposes an epic subject.** File it as the subject's member,
  with `--parent <subject>`, send it, and sign off with
  `--ruled yes --route human --no-wait`. Leave it out of `--waiting-on`, which
  names a dependency only: the epic already waits on its members, and bd
  refuses a `blocks` edge from a parent to its own descendant. When the sitting
  also sent a dependency, name that one with `--waiting-on` in place of
  `--no-wait`.

## Send a bead to a named agent

The mechanik, deacon, witness, refinery and keeper are named agents. Assign the
bead to the agent by the qualified name `gc agent list` prints, then notify it,
because the notice is what gives an idle named agent a turn on the bead
(`docs/deferred-dispatch.md`):

```bash
gc bd update <bead> --assignee <qualified-name> \
  && "$(gc <binding> scripts-dir)/deferred-dispatch.sh" notify <bead> --agent <qualified-name>
```

## Stand up an integration effort

Stand one up when several beads must reach the default branch as one PR the
operator reviews. A lone bead needs none: slung to a pool, it opens its own PR.

The procedure is the recipe in `integration-effort.md`, beside this file, which
the mechanik runs. It also covers adding a bead to a standing effort and
bringing the effort's branch current. The recipe pushes the effort's branch,
and a converse sitting never pushes, so a sitting does not run it. A sitting
sends the effort on:

- When the subject's recommendation is `mol-design-convoy`, the sign-off's
  `--accept` takes it (Take a recommendation, below), and that formula's run
  cuts the branch.
- Any other effort goes to the mechanik. File a bead in the effort's rig whose
  description names the effort's beads and what the effort delivers:
  `gc bd --rig <rig> create "<title>" -t task -d "<description>" --json`. Then
  send it to the mechanik (Send a bead to a named agent, above).

## Take a recommendation

A first reaction that cannot send a bead itself records the formula it
recommends as `gc.recommended_formula` and asks the operator in a human gate on
the bead, under the key `first-reaction`. Take the recommendation only on the
operator's go, and only through `gc-helm.sh accept`, the writer the board's
Accept runs:

- **Outside a sitting:** `"$(gc <binding> scripts-dir)/gc-helm.sh" accept <bead>`.
- **In a sitting:** pass `--accept` on the sign-off, or on the `--answer` call
  of a turn that does not sign off. It hands the recommendation's gate to
  Accept's writer once the ruling's other writes have landed, every other gate
  it answers included (the converse-settle step). A var the operator settles
  for the dispatch rides beside it as `--var <key>=<value>`; the formula's own
  description names the vars it takes.

Never send a recommended formula with a sling of your own. Under the bead's
acceptance lock, Accept clears the recommendation's gate and nothing else,
sends the formula, and records the dispatch. It refuses while another human
gate blocks the bead, because a worker builds nothing that still waits. When an
Accept stopped after its sling, run it again: it finds the run it sent by the
token in that run's title and only records it, where a sling of your own sends
the work a second time once that run has finished.

## Choose the formula

Read the formulas the rig can run now, rather than recall them:

```bash
gc formula list --rig <rig>               # every formula the rig can run
gc formula show <formula> --rig <rig>     # what one does, the variables that tune it, and its steps
```

Choose by what done looks like for the work:

1. **Nothing to build.** A judgment or a decision the operator owns has nothing
   to send. Ask the operator (the waits skill).
2. **A change to a repository that lands as one pull request.** Send it to a
   polecat pool with no `--on`: the pool's default formula builds that.
3. **Any other kind of done**, such as findings with no change, a design
   settled and reviewed before the build, or a demo. Read the descriptions of
   the formulas whose names fit, and send it on the one whose description says
   it produces that and fits work like this.

Never send new work on a patrol, review or validation formula: the city's
orders and review cadence pour those. Set a formula's variables with
`--var <name>=<value>` on the sling. When you put the choice to the operator,
name the formula and why you chose it.

## Stop or redirect work in flight

- **Stop it.**
  `"$(gc <binding> scripts-dir)/gc-helm.sh" takeaway <bead> "<why it stops>" --release --no-wait`
  stops the run beneath the bead and leaves the bead open, unassigned and
  routed to no pool, with that sentence as its headline. It leaves a
  deferred-dispatch arm in place, and an armed bead goes out again once nothing
  holds it, so disarm it first (the waits skill). When the bead now waits on
  something, pass `--waiting-on <bead>` in place of `--no-wait`.
- **Send it elsewhere.** Name where it goes in the same release:
  `"$(gc <binding> scripts-dir)/gc-helm.sh" takeaway <bead> "<where it goes now, and why>" --release --no-wait --route <rig>/<pool>`.
  For a named agent, pass `--assign <named-agent>` in place of
  `--route <rig>/<pool>`, then notify it:
  `"$(gc <binding> scripts-dir)/deferred-dispatch.sh" notify <bead> --agent <named-agent>`.
- **Withdraw a recommendation** the bead should not take, keeping the bead open
  for discussion:
  `SUBJECT=<bead> CONVERSATION=<conversation> "$(gc <binding> scripts-dir)/converse-invalidate-recommendation.sh" "<why it no longer holds>"`.
  It strips `gc.recommended_formula`, so the board stops offering Accept, and
  leaves the gate that put the recommendation to the operator open until it is
  answered. When the bead itself should go, close it instead (below).

Retire a pull request in flight instead of stopping it (the prs skill).

## Close a bead that needs no work

Record the no-op, then close through `bead-rehome.sh`, which runs only once the
record landed:

```bash
gc bd update <bead> --set-metadata gc.work_outcome=no-op \
  && "$(gc <binding> scripts-dir)/bead-rehome.sh" --origin <bead> --successor <successor> --kind not-needed --note "<why, one sentence>"
```

Name a successor under every kind. Under `not-needed` it is the evidence that
ruled the work out, such as the conversation where it was decided. Under
`duplicate`, `folded`, `re-homed` and `fixed-upstream` it is the bead that
carries the work now. The script stamps the pointer, reads it back and only
then closes, so never close the bead by hand: a close that names no successor
reads as a careless one. On a bead already closed by hand, the same call adds
the missing pointer. An open human gate that blocks the bead holds the close:
the script records the pointer and exits 5, and the same call closes the bead
once each such gate is cleared.

Before you run it:

- Check that the bead has no work in flight: it is unassigned, has no branch or
  PR still in flight to a pool, and is not a review, step or workflow bead.
  Check it yourself, because the doctor skips a bead closed this way and
  nothing checks it again. Retire a bead with an open PR instead (the prs
  skill), which closes the PR too: a bare `gc bd close` on a bead whose
  `merge_result` is not a closed state leaves its PR unlanded.
- Disarm an armed bead, so a wait released before the close lands cannot send
  it: `"$(gc <binding> scripts-dir)/deferred-dispatch.sh" disarm <bead> --reason "<why>"`.
- In a sitting, close a subject only on the operator's agreement, and only
  after the sign-off, which answers the gates the ruling settles.

When a person rules that work a human gate holds will not go on, one call does
all of this in order (the waits skill):
`"$(gc <binding> scripts-dir)/stand-down.sh" <bead> --key <situation-key> --ruling "<the ruling, one sentence>"`.
In a sitting it runs before the sign-off, with `--successor <conversation>`
(the converse-settle step).

A bead that needs no work only once another bead lands is not closed now. Make
it wait on that bead and arm the validating closer for when it closes (the
waits skill), which checks it then and closes it or asks a person.
