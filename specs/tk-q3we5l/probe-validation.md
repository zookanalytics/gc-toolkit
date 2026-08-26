---
name: Review-wedge probe — live-city validation
description: The bead shapes gate-ensure's pour-liveness probe reads, and the live-city observations each rule was derived from. Read before changing pour_roots/pour_spent or the graph.v2 pour linkage they walk.
---

# Review-wedge probe: live-city validation

`gate-ensure.sh` escalates a poured review whose workflow can no longer
produce a verdict. The bead that asked for it (tk-q3we5l) recorded that
stub-based tests could not pin the probe, because it depends on live step and
convoy semantics. This is what those semantics turned out to be, and what was
observed to establish them.

## The wedge

A review is dispatched as `gc sling <pool> <review-bead> --on mol-review`.
The pour retires `gc.routed_to` and stamps `gc.execution_routed_to` in its
place, so the poured workflow becomes the only thing that can raise the gate.
`mol-review` closes the review bead through `signoff.sh` on a verdict, and its
failure arm instead closes the step chain and then restores `gc.routed_to` so
the pool can re-claim the bead.

An agent that dies between those two writes leaves the review bead open with
no route, no assignee, and a closed step chain. `inflight_review` counts the
exec stamp as reach and reports the review as in flight, so `gate-ensure`
dispatches nothing. The anchor holds forever and nothing is open to say why.

## What distinguishes a wedge from a live review

Session liveness does not answer it. The reviewing agents observed here are
named sessions (`hicks`, `ripley`), not ephemeral pool workers, and a named
session's record survives the run that held the review. Asking whether the
session is alive would report "alive" for a run that ended hours ago.

The step chain answers it. A graph.v2 step advances only by closing its own
bead, and nothing re-offers a closed step, so a chain with no live step other
than `workflow-finalize` has reached its terminal step. If no verdict came out
of it, none is coming. An open step is the opposite reading: either a live
claim, or a husk the re-offer path will pick up. Neither is this arm's
business.

`workflow-finalize` is excluded because it belongs to the control-dispatcher,
not to the reviewing agent, and it is routinely still open when the reviewer
has finished.

## The linkage the probe walks

There is no forward pointer from a review bead to its workflow. The path runs
through the tracking convoy the pour mints:

1. `gc bd dep list <review> --direction=up -t tracks` returns the input
   convoy, one row per pour.
2. The workflow root carries `gc.input_convoy_id=<convoy>`, so
   `bd list --metadata-field gc.input_convoy_id=<convoy>` resolves it.
3. Each step bead carries `gc.root_bead_id=<root>` and `gc.step_ref`, so
   `bd list --metadata-field gc.root_bead_id=<root>` enumerates the chain.

Both list reads must pass a status list that includes `closed`, since the
spent chain is recognised by its closures. One repeated `--status` flag keeps
only the last value, so both halves ride a single comma-separated list.

A re-pour mints a second convoy and a second root. All roots are judged, and
one live root keeps the review in flight however many spent siblings sit
beside it.

## Live observations, 2026-08-26

Five real `mol-review` molecules in the gc-toolkit rig. The probe functions
were extracted verbatim from `gate-ensure.sh` and run read-only against the
live store.

| Review | Chain at the time | Probe | Correct |
|---|---|---|---|
| tk-2e3pck | all four steps open, unassigned (poured, never claimed) | still driven | yes, it later produced a verdict |
| tk-gu933s | load-dispatch closed, review in progress under hicks | still driven | yes, it later produced a verdict |
| tk-84d1kf | every step closed | spent, root tk-n4t318 | yes |
| tk-88ar15 | every step closed | spent, root tk-5ikh9q | yes |
| tk-gu933s | every step closed (same molecule, after it finished) | spent, root tk-blgz1p | yes |

Both reviews that were in flight during the run went on to stamp
`check.codex=green@<oid>` and close, which is the negative control that
matters: the probe declined to escalate the exact two reviews a
liveness-blind check would have had to guess about.

The three spent readings are all on **closed** review beads. That is the
normal successful ending, and `inflight_review` filters to live statuses
before the probe is ever called, so the arm cannot reach them. A spent pour is
only a wedge when the review bead is still open.

A read-only replay of the whole arm over every live gating anchor escalated
nothing, which is correct: the city held no wedge.

## The second sighting

`mol-review`'s failure arm closes its chain before it restores the route, so a
single read can catch a recovery mid-write. The arm stamps
`wedge_seen_root=<root>` on the first sighting and escalates only when a later
pass finds the same root still spent. Stamping the root rather than a flag
means a re-pour starts the count again, since the new root does not match the
recorded one.

## What the stub suite pins

`gate-ensure.test.sh` builds these shapes as fixtures and drives the real
script through them: the spent chain held one pass and then escalated once,
the live chain never escalated, a chain whose only live step is
`workflow-finalize` counted as spent, a live root beside a spent one counted
as in flight, an unreadable or empty enumeration escalated nothing, and a
failed escalation retried on the next pass without failing the pass.

## Each guard is load-bearing

The arm stays quiet for five separate reasons, and two guards in series can
mask each other: a fixture that trips the second one never proves the first.
Each was mutated out of `gate-ensure.sh` in turn, and the suite is required to
fail:

| Guard removed | Suite |
|---|---|
| the exec-ONLY qualification, so any reach reads as poured | 6 fail |
| the live-step check, so every pour reads as spent | 5 fail |
| the second-sighting hold, so a first sighting escalates | 4 fail |
| the `workflow-finalize` exclusion, so the finalizer counts as live | 7 fail |
| the empty-enumeration guard, so a root with no steps reads as spent | 2 fail |

The first pass of this exercise found the exec-only qualification masked: the
routed fixture carried no workflow at all, so removing the qualification only
moved the decision onto the unreadable-linkage guard and the suite stayed
green. The routed and claimed fixtures now carry a spent chain, which makes
the qualification the only thing holding the escalation back.
