---
name: work
description: Use when you have to say that something needs doing, carry out a decision about who does it, or change work already asked for. Covers filing new work or a follow-up in the right rig, as a sibling of the bead it came from, sending a bead to a pool on a formula (routing, slinging, dispatching, releasing a held bead to a pool, assigning it to an agent, taking a recommended formula), choosing which formula, stopping or redirecting work in flight, and closing or retiring a bead that needs no work (a duplicate, or work no longer needed). Not for doing the work yourself. To make work wait for something first, use waits; for a change that is already a pull request, use prs.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Work: what needs doing, and who does it

These are the ways to say that a bead needs work, who should do it, or that it
needs none. Each option says what the message means, who acts on it, and the
one writer that sends it. The writer's `--help` carries its flags. Doing the
work is a molecule's job, so nothing here changes a repo.

The writers are in the pack's `assets/scripts/`, and the examples call them
through `$S`. Each tool call starts a fresh shell, so run this block in the
same call as the writer. It takes `$CONV` where a converse sitting has set it,
and otherwise finds the directory:

```bash
S=""
for d in "${CONV:-}" "${GC_RIG_ROOT:-}/assets/scripts" "$(git rev-parse --show-toplevel 2>/dev/null)/assets/scripts" "${GC_CITY_PATH:-}/rigs/gc-toolkit/assets/scripts"; do
  [ -x "$d/gc-helm.sh" ] && { S="$d"; break; }
done
: "${S:?no assets/scripts with gc-helm.sh found}"
```

## File new work

A new bead says that work needs doing. Filing it starts nothing: send it, make
it wait, or leave it for placement.

- **File it beside the bead it came from, never under it.** Give it that bead's
  own parent, or no parent when it has none. `"$S/converse-parent.sh" <bead>`
  prints the parent, or an empty line. bd refuses a `blocks` edge from a parent
  to its own descendant, so a child could never gate the bead it came from.
  Work already filed under the bead it came from stays where it is.
- **File it in the store of the pool that will work it.** A pool reads only its
  own rig's store, so a city-scoped session names the rig with `--rig <rig>`.
- **Hold it for placement unless intake admits it.** A bead may be routed or
  armed to a pool only when it is an epic member, PR-finishing work carrying
  `anchor_bead`, a confirmed emergency, or routed by the operator in a sitting,
  by hand or by Accept. Any other bead carries `placement=pending` in its create
  and no route or arm, and the placement sitting places it (`docs/steering.md`).

Writer: `gc bd create "<title>" -t task --parent <parent> -d "<what needs doing, why, and what done looks like>" --json`,
with `--metadata '{"placement":"pending"}'` added when intake does not admit it.
The description is the contract the worker reads.

## Send a bead to a pool on a formula

The message is that this pool does this work by this method. The pool's
workers claim the workflow the sling pours, and the formula's steps are their
plan.

Writer: `gc sling <rig>/<pool> <bead> --on <formula>`. With no `--on` it pours
the city's default sling formula.

- **One dispatch, never two.** A sling pours a workflow and stamps
  `gc.execution_routed_to` on the bead. A raw route, `gc.routed_to=<pool>`,
  which a sitting's sign-off `--route <pool>` also writes when it releases a
  held subject, has the pool claim the bead itself. Send it one way. Both start
  two workers on one branch.
- **Release its wait first.** A worker's first step builds nothing that still
  waits. It re-arms a bead with an open blocker to be sent again when the
  blocker closes, and it ends the run on a bead that carries a `merge_result`,
  `held` included, as finished. Release the wait (the waits skill), then send.
- **A named agent takes an assignee.** The mechanik, deacon, witness,
  refinery and keeper never claim a pool's route. Send one of them a bead with
  `gc bd update <bead> --assignee <qualified-name>`, the name `gc agent list`
  prints.

In a sitting, the sign-off's `--route` says where the subject itself goes once
its wait is released (the converse-settle step), so first decide which bead
carries the work:

- **The subject is the work.** Sign off with `--ruled yes --route human --no-wait`,
  then sling the subject. The sling clears that human route.
  `--route <rig>/<pool>` would route the subject raw as well, a second dispatch.
- **New work carries it, and the subject waits for it.** File the work beside
  the subject, send it, and sign off with `--ruled yes --route human --waiting-on <the work>`.
  The board shows the subject as a ruling in flight until the work lands, then
  as settled. A `--route <rig>/<pool>` here would have that pool claim the
  subject itself once the work lands, a conversation seed no worker can close.

## Take a recommendation

A first reaction that cannot route a bead itself records the formula it
recommends as `gc.recommended_formula`, and the operator decides. Take it only
on the operator's go. The pool on that formula acts.

Release the wait that put it to the operator (in a sitting, the sign-off for a
subject that is the work, above), send it on that formula, then record the
dispatch in one update:

```bash
gc sling <rig>/<pool> <bead> --on <the recommended formula>
gc bd update <bead> --set-metadata gc.recommended_formula_dispatched=<the formula> --unset-metadata gc.recommended_formula
```

The marker records the dispatch, and the strip stops a later visit from
offering Accept for work that already ran. Outside a sitting, the board's
Accept is the operator's own form of this act, and it refuses a visit that a
sitting has engaged.

## Choose the formula

`gc formula list` names the formulas, and `gc formula show <name>` says what
each one does. Name the formula you chose when you put the choice to the
operator. Ask, in order:

1. Is there executable work at all? If not, ask for a visit (the waits skill).
   A judgment or decision the operator owns, with nothing to build, has nothing
   to dispatch.
2. Does the work need a design settled before or beside the build, and is it
   large or high-blast-radius enough that one holistic review beats scattered
   PRs? If so, use a design-convoy (`mol-design-convoy`). It stands up an owned
   integration convoy for the initiative: a design child lands its doc on the
   convoy's branch, implementation builds there, and the whole unit graduates
   to the default branch as one reviewed PR, so a wrong shape is caught at the
   design gate before it is built. If not, send a plain work bead, which lands
   as one PR to the default branch.

`design_gated` defaults to `true`, which holds implementation until the
operator approves the design's PR. `docs/design-convoy.md` describes the gates
and when all-in-one (`--var design_gated=false`) fits.

## Stop or redirect work in flight

The message is that work already sent should stop, or go somewhere else.

- **Stop it.** `"$S/gc-helm.sh" takeaway <bead> "<why it stops>" --release --no-wait`
  stops the run beneath the bead and leaves the bead open, unassigned and
  routed to no pool, with that sentence as its headline. When it now waits on
  something, pass `--waiting-on <bead>` in place of `--no-wait`.
- **Send it elsewhere.** The same release with `--route <rig>/<pool>` hands it
  to a pool, or with `--assign <named-agent>` to a named agent, in one write.
- **Withdraw a recommendation** the bead should not take, while the bead stays
  open for discussion:
  `SUBJECT=<bead> VISIT=<visit> "$S/converse-invalidate-recommendation.sh" "<why it no longer holds>"`.
  It strips `gc.recommended_formula`, so the board stops offering Accept once
  no sitting holds the visit. When the bead itself should go, close it instead.

A pull request in flight is retired, not stopped (the prs skill).

## Close a bead that needs no work

The message is that nothing will be built for this bead. The writer closes it,
and nothing downstream picks it up. In a sitting, close a subject only on the
operator's agreement. The sitting's own open visit holds that close: the
writer records the pointer and exits 5, and the same call closes the subject
once the visit is closed.

Record the no-op, then close through the disposition writer:

```bash
gc bd update <bead> --set-metadata gc.work_outcome=no-op
"$S/bead-rehome.sh" --origin <bead> --successor <successor> --kind not-needed --note "<why, one sentence>"
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
- Disarm an armed bead first, with `"$S/deferred-dispatch.sh" disarm <bead>`,
  so a wait released before the close lands cannot send it.

`docs/state-machine.md` ("Disposition") is the doctrine.
