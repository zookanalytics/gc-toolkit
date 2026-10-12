---
name: Steering — how the operator steers the city's work
description: How new work reaches a work pool under the operator's steering. It states the intake rule for which beads may be routed or armed to a pool, the placement=pending marker that holds every other bead, the writers that follow the rule, how an emergency is checked, the placement sitting's queue (gc-helm.sh unplaced), and how the sitting places a bead. Read it before writing anything that files, routes or arms new work.
---

# Steering

The operator steers the city's capacity by deciding which work runs. New work
reaches a work pool once the operator has placed it, and not on its own.

## Scope

**Mandate.** Which beads may enter a work pool and what holds the rest: the
intake rule, the `placement=pending` marker and the writers that set it, the
emergency check, the placement sitting's queue, and how a bead is placed.

**Boundaries.** The design that decides how work is steered by epic, with the
units that build it, is
[specs/tk-rl8gz4b.2/steer-by-epic.md](../specs/tk-rl8gz4b.2/steer-by-epic.md);
this page states what runs. What an epic is, and what it carries, is
[epics.md](epics.md). How a pool claims routed work is
[gascity-routing-model.md](gascity-routing-model.md). The first reaction's
method is `agents/proactive/prompt.template.md`, and who may route, arm or hold
a bead is [authority-map.md](authority-map.md).

## The intake rule

A bead may be routed or armed to a work pool only when one of these holds:

- it is a member of an epic, which means it has a parent-child parent;
- it is PR-finishing work of an anchor, which means it carries `anchor_bead`;
- it is an emergency, a red main or a broken gate, checked rather than asserted;
- the operator routed it, through a sitting, a hand sling or an Accept.

Every other bead waits for placement. A bead held this way carries
`placement=pending` and no route and no arm, so no pool is offered it.

## The writers that hold new work

Three writers file or dispose new work, and each follows the rule.

- **The first reaction** (`assets/scripts/first-reaction-dispose.sh`). It still
  reacts to every finding, because its card is the placement sitting's triage.
  Its actionable exit routes a member, PR-finishing work or a confirmed
  emergency. It marks any other bead `placement=pending` and releases it with no
  route. The blocked exit's `--then-route` arms a dispatch only for a bead the
  rule admits. Any other bead it marks, and arms nothing, while its wait still
  lands as a `blocks` edge. The close exit keeps its validating closer, because a
  close shrinks the queue. Work that is a named agent's own (`--assign`,
  `--then-assign`) is not pool work, so the rule does not read it.
- **The witness** files mail about a pack defect as a bug marked
  `placement=pending` and routed to no pool (`formulas/mol-witness-patrol.toml`,
  the `bug-file` block).
- **The feedback distiller** files each prompt-update and engineering bead
  marked `placement=pending` and routed to no pool
  (`formulas/mol-feedback-distiller.toml`, the file-and-dispatch step). The
  operator still reviews each one at its PR once a polecat builds it.

No held bead is ever readable without its marker. The witness and the
distiller write it in the create, and the first reaction writes it and reads
it back before the release.

## The emergency check

The first reaction claims an emergency with `--emergency`, on the actionable
exit or on the blocked exit with `--then-route`. The claim is checked against
the head of the default branch of the subject's repository, read from GitHub
through the rig checkout's origin. A check run there that concluded `failure`,
`timed_out` or `startup_failure`, or a commit status of `failure` or `error`,
confirms it. A run still going, or one cancelled by a newer push, does not.

A confirmed emergency is written P0, the priority is read back, and then the
bead is routed or armed. A claim the check does not confirm, including one the
check cannot run, is held for placement like any other bead, and the note it
leaves on the bead says what the check found. A broken gate counts when it shows
as a failing check on main. A latent hazard, a doctor finding marked blocking,
or a failure on one PR's branch does not.

## The placement sitting's queue

`gc-helm.sh unplaced` lists the queue, and `--json` prints it for a caller. It
reads every rig store the city has, skips a suspended rig's store and says so,
and orders the beads by priority, then age. It writes nothing. When a store
does not answer, it names that store and exits 4 after printing the rest.

`assets/scripts/placement.sh` is the one definition of a bead in the queue: it
carries `placement=pending`, and nothing has placed it since. A parent, a route,
an arm, an assignee or a live pour each places a bead, whether or not the marker
was cleared. The same definition serves two other readers:

- the liveness sweep names such a bead's wait, so it does not report the bead as
  an unnamed wait;
- `doctor/check-blocked-work-armed` owes such a bead no arm, because its
  dispatch is the route the sitting gives it.

## Placing a bead

For each bead in the queue, the sitting does one of three things.

- **Place it under an epic.** Give it the epic as its parent
  (`gc bd update <bead> --parent <epic>`), then route it to its pool
  (`gc sling <rig>/<rig>.polecat <bead>`). A park on the epic holds it from then
  on, through bd's parent-child cascade.
- **Route it on its own.** Route it to its pool with no parent.
- **Close it**, when the work is not wanted.

A placed bead leaves the queue as soon as it has a parent or a route. Clearing
the marker (`gc bd update <bead> --unset-metadata placement`) keeps the bead's
record honest, and nothing waits on it.
