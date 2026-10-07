---
name: Duplicate input convoys and what leaves them open
description: Why beads carried two to four open "input convoy for <bead>" wrappers, with double pours ruled out. Records the two producers found on tk-pxeqkz (workflows that end before their bead, and slings killed by the proactive scan order's deadline), what the pack changed, what went upstream, and the backfill result. Read when open synthetic input convoys pile up again.
---

# Duplicate input convoys and what leaves them open

The bead asked three things. Does the slinger mint a second input convoy
without checking for an existing one? Do two convoys mean two pours? Is the
fix a probe before the mint or a dedup after it?

## What a pour mints

`gc sling` turns a bead target into a fresh synthetic convoy on every pour.
`graphv2.NormalizeInputConvoy` calls `CreateSingleItemInputConvoy`, which
titles it `input convoy for <bead>` and sets `gc.synthetic=true`, and the
workflow root names it in `gc.input_convoy_id`. Nothing looks for an existing
convoy first, and nothing needs to. The convoy is the pour's own input handle.
The relaunch check (`checkLegacySourceWorkflowConflict` in
`internal/sling/sling_core.go`) is what refuses a second live workflow of the
same formula on the same bead. So N slings of a bead mint N convoys, and the
real question is why they stay open.

## Census

The gc-toolkit store at 2026-10-04 22:00Z held these open synthetic input
convoys:

| Class | Count |
|---|---|
| Named only by closed workflow roots (194 of them first reactions) | 237 |
| Named by nothing | 47 |
| Feeding a live workflow | 53 |

48 beads carried two to four of them. No convoy fed more than one root, and no
bead had two live workflows, so these are not double pours. City-wide, the
same rule found 522 convoys no live bead names (gascity 203, gc-toolkit 282,
signal-loom 25, shutupandlisten 6, sprintshow 6) against 95 live ones.

`gc convoy list --json`, the measure the bead cites, did not finish within
150s on 2026-10-04. Joining `gc bd list --type=convoy` to the beads carrying
`gc.input_convoy_id` answers the same question in about ten seconds.

## Producer 1: the workflow ends before its bead

Both closers of a convoy key on the beads it tracks. The controller's
bead-close autoclose (`autocloseConvoyIfComplete`) and `gc convoy check` each
close a convoy once every tracked member is terminal.
`processWorkflowFinalize` closes the root, the rest of the subtree, the spec
sidecars and the source-bead chain, but never the input convoy. A workflow
that ends before its bead therefore leaves its convoy open until the bead
closes. A first reaction leaves its subject open by design, and a polecat
workflow ends at the refinery hand-off. This producer accounts for the 237. On
gc-toolkit, 5 of the 9 graph.v2 roots that closed in one hour left their
convoy open.

## Producer 2: slings killed by the scan order's deadline

The proactive intake scan (`tools/gc-proactive.sh scan --sling`, run by the
`proactive-scan-sling` order with a 300s timeout) judged "not routed" by
`gc.routed_to` alone. A graph.v2 pour moves the bead's route to
`gc.execution_routed_to`, so a bead whose first reaction sat queued in the
proactive pool, or whose polecat workflow was running, stayed a candidate. On
2026-10-04, 24 of the scan's 192 candidates were in that state. The scan ranks
the oldest first, and ten of them filled the top of its 20-row page.

`gc sling` refused the beads whose live workflow was a queued first reaction
("source bead X already has live workflow(s)"). Its relaunch check matches a
live root of the same formula only, so a bead whose live workflow was a
mol-polecat-work was not refused, and a reaction was poured beside it. The
refusal comes after the mint: `prepareGraphV2FormulaInvocation` mints the new
pour's convoy before the check runs, and the refused sling closes it again in a
separate write. A refused sling spends none of the sweep's cap, so a sweep
walked the in-flight beads one refused sling at a time, and on most runs the
deadline killed it before it got past them. The order logged 51 deadline
failures on gc-toolkit in the 24 hours to 2026-10-04T21:40Z, and 37 on gascity
in 48 hours. The killed sling was usually between the mint and the close. For
32 of the 40 never-named convoys minted on gc-toolkit on Oct 3 and 4, a
deadline failure of that order followed the mint within 90s, and its
last-slung bead was the convoy's tracked bead. The candidates below the
in-flight ones went unreached in those sweeps.

## Why neither a probe nor a cadence sweep

A probe for an existing convoy before the mint stops neither producer.
Producer 1's convoys come from pours that run, one convoy each. Producer 2's
come from slings the one-live-workflow check already refuses, and they leak
through the kill between the mint and the cleanup close. Moving that check
ahead of the mint would close the window; a probe for an existing convoy
would not.

A reap on a cadence would be the only thing that ever closes the convoys of
producer 1, whose cause is a missing close at the workflow's end. The operator
rejected that shape for dead workflow roots on PR #992: "an hourly order
that's looking for state that shouldn't exist and then closing it out ...
doesn't fix why that state occurs". The convoy-check order is a different
shape. It backs up an event-driven closer with the same predicate.

## What changed

- **The scan stops offering in-flight beads.** `scan_drop_inflight` in
  `tools/gc-proactive.sh` drops a candidate when a non-closed workflow root
  names a convoy that tracks it, the reverse walk gascity's check uses, so the
  sweep's page and time go to beads with no workflow. tk-qm9ynri (PR #1125)
  landed `sling_live_workflow_guard` in the same file while this branch was in
  review. That guard refuses the sling itself, before `gc sling` runs, which
  removes the pack's source of producer 2 on its own. tk-eui2sgp folds the two
  into one definition.
- **A one-time backfill, not shipped.** A hand-run script applied the
  live-namer gate approved on tk-vc5my. A convoy is dead when no non-closed
  bead names it as `gc.input_convoy_id`, and a 60-minute grace window protects
  a sling between the mint and the pour. It ran once per store. The operator's
  review of PR #1045 asked what structural issue a reaper would be covering.
  The answer is the two producers above, and each has a fix at its source:
  the scan change and the sling guard in the pack, and gc-4by8wa in gascity,
  which closes a convoy where its workflow ends. So the script was dropped
  from the branch before merge. The PR's commit history keeps it, as
  `assets/scripts/input-convoy-reap.sh` at 5285301f.
- **Upstream.** gc-4by8wa asks gascity to close the convoy when its root
  closes, in the controller's bead-close autoclose, and to give `gc convoy
  check` the same predicate as the backstop. On 2026-10-07 it is open at P2,
  routed to the gascity polecat pool and queued behind the operator's new-work
  pause. The comment on gc-zh5fp records the producer 2 mechanism: a sling
  killed after the mint still leaks wherever it is killed, so minting only
  once the pour commits closes that window.

tk-vc5my, the older backlog bead for this reap, is held behind tk-pxeqkz with
`duplicate_of` and closes with it. The backfill covers its backlog half, and
gc-4by8wa covers its at-source half.

## Readers checked

Each place the pack reads an input convoy was checked for whether it needs a
finished workflow's convoy to stay open.

- `gc-helm.sh` (takeaway's molecule resolution), `self-review-check.sh`,
  mol-first-reaction's own root lookup, `doctor/check-root-advancing` and the
  helm facts source resolve from a live root. A live root names its convoy, so
  the gate keeps that convoy open.
- `liveness-sweep.sh` and `doctor/check-blocked-work-armed` resolve coverage
  forward from non-closed namers, so a dead convoy never counted there, and
  the liveness sweep classifies a wrapper as machine residue.
  `dead-molecule-dispose.sh` reads tracks edges, which a closed convoy keeps.
  `tools/gc-polecat-metrics.sh` reads convoys of every status.
- `gate-ensure.sh`'s `tracked_roots` reads the roots of open tracking convoys
  only, on the premise that a finished pour's convoy is closed. Its comment
  says a dead pour must not suppress the stranded re-sling. A stranded review
  whose finished pour left its convoy open therefore finds that pour, judges
  it spent, and is escalated as wedged instead of re-slung. Closing the dead
  convoy restores the re-sling. When the backfill ran, one review bead was
  tracked by a dead convoy, and it was blocked. On 2026-10-07 none was.

## Backfill result

The script ran with `--apply --db <rig>/.beads` once per store on
2026-10-04, between 21:58Z and 22:26Z. Before each apply on gc-toolkit,
gascity and signal-loom, the dry run's dead set matched an independent join
exactly.

| Store | Closed | Workflow finished | Never named | Live, left open |
|---|---|---|---|---|
| gc-toolkit | 282 | 238 | 44 | 54 |
| gascity | 204 | 181 | 23 | 42 |
| signal-loom | 25 | 25 | 0 | 1 |
| shutupandlisten | 6 | 6 | 0 | 0 |
| sprintshow | 6 | 6 | 0 | 0 |

No close was refused, and every close read back as closed. On gc-toolkit,
the number of beads with more than one open wrapper fell from 48 to 3. A dry
run right after the passes found 3 more dead convoys on gc-toolkit and 1 on
gascity. Each had aged past the grace window, or seen its workflow finish,
while the passes ran. Two of the gc-toolkit ones were never named, and they
track tk-hud9fr and tk-mw5029, beads the unpatched scan was still re-slinging.
That is producer 2. The scan kept feeding it until the new-work pause stopped
the scan, and the sling guard keeps it from refiring once the scan resumes.

## Cost of waiting on gc-4by8wa

Producer 1 keeps minting at the rate workflows end before their beads: about
five an hour on gc-toolkit on 2026-10-04. Until gc-4by8wa lands, those
convoys stay open until their bead closes, when convoy-check takes them.

A dry run of the same gate at 2026-10-07T13:40Z, about 63 hours after the
backfill, counted:

| Store | Dead | Workflow finished | Never named | Live |
|---|---|---|---|---|
| gc-toolkit | 111 | 97 | 14 | 14 |
| gascity | 7 | 7 | 0 | 43 |

On gc-toolkit the 111 sit on 98 open beads, 13 of which carry two or more.
None is a review bead, so the gate-ensure case above touches nothing today.
The net regrowth on gc-toolkit, under two an hour, is lower than the rate
measured on 2026-10-04. Over the same window the operator's new-work pause
has held the proactive scan off since its run at 2026-10-05T17:29:55Z.
Thirteen of the 14 never-named convoys were minted before that run ended, one
of them nine seconds before its 300s deadline. The fourteenth was minted at
2026-10-06T00:51Z, after the scan stopped, so a sling outside the pack's scan
can still leak one. That is the window gc-zh5fp's comment describes, and
gc-4by8wa's backstop would close such a convoy once it ages past a grace
window.

What waiting costs is clutter. These convoys show up as a bead's second or
third "input convoy for" wrapper, which is the symptom tk-pxeqkz was filed
on. Of the readers checked above, the only behavior they change is
gate-ensure's stranded-review re-sling.
