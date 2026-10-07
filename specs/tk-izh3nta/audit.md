---
name: PR status label responsiveness — audit
description: Why a PR's status label stayed on needs-review for hours or days after the operator reviewed it, which writers set the label and when, what tk-izh3nta changed, and what it leaves to other beads. Record of work on tk-izh3nta.
---

# PR status label responsiveness: audit

## Answer

A human's review on a PR (an approval, a comment, or a change request) reached
the PR's `status:` label only through the full `pr-facts.sh` arm, which runs near
the end of the refinery pass. Two rigs rarely finish that arm, so their
labels went stale for hours or days. The city records the review much earlier in
the same pass, in the posture arm and the feedback arm. This bead makes those two
arms re-derive the label for the PRs whose review they record, so the label
leaves `needs-review` in the pass that records the review. The full arm still
re-derives every PR, as the self-heal for everything else.

## How the label is written

As of 2026-10-06T00:40Z, main at `54fa2a3d`:

- `assets/scripts/pr-status-label.sh` is the only writer. It asks
  `gctk pr-status derive` for the value and sets it on the PR.
- It had three callers. `pr-open.sh` sets the label when a PR opens.
  `signoff.sh` flips it after the city's own review verdicts. The full
  `pr-facts.sh` pass, arm 7 of `refinery-reconcile.sh`, re-derives it for every
  open PR.
- The derivation reads only the anchor bead: its holds, its recorded posture and
  merge state, and the live beads anchored to it. An approval moves the label to
  `working` through the recorded posture. A comment or a change request moves it
  to `working` through the live work the feedback arm files for it: a rework
  child or a visit, findings, and a validation pass. A recorded
  `changes_requested` with nothing filed yet still derives `needs-review`.
- The pass records the posture in arm 2 (`pr-facts.sh --posture-only`) and
  routes feedback in arm 3 (`pr-facts.sh --route-comments-only`). Neither wrote
  the label. It waited for arm 7, which runs after the merge, pre-open-rebase and
  pr-open arms.

## What the lag looked like

- Arm 7 rarely finishes on two rigs (refinery-reconcile `pass.log`, read
  2026-10-06T00:53Z). gc-toolkit reached arm 7 in 76 of 253 logged passes since
  2026-10-02T18:30Z and got past it in 31. The last pass to get past it started
  2026-10-04T09:51Z. signal-loom reached arm 7 in 321 of 335 passes since
  2026-10-03T05:42Z and got past it in 37, the last in the pass that started
  2026-10-05T13:08Z. gascity, shutupandlisten and sprintshow got past arm 7 in
  every logged pass.
- A pass killed inside arm 7 re-derives only the labels of the PRs it reaches
  before the kill.
- The operator approved PRs #1000, #1003 and #1006 between 15:37Z and 15:40Z on
  2026-10-04, and pr-facts recorded each approval on its anchor by 15:56Z. At
  00:37Z on 2026-10-06 all three still read `status: needs-review` while the
  derivation answered `working`.
- Across all 90 open gc-toolkit PRs at 00:50Z, 8 labels disagreed with the
  derivation. Three were these approved PRs. Five read `working` while the
  derivation answered `needs-review`: PRs whose rework had finished and that
  were waiting on the operator (#1060, #1056, #1052, #1011, #986).

## The change

`pr-facts.sh` re-derives a PR's label, in every mode, at the two points where a
review changes the label's inputs:

1. when the posture block records a new posture value, which is where an
   approval, a comment, a change request or a dismissal lands;
2. when the feedback arm records a routed batch, which then stands on the anchor
   as live work.

Both go through the existing writer. The full pass keeps its per-PR re-derive as
the self-heal for every other input.

A merge state or head that moves under an unchanged posture value does not
trigger a re-derive in the early arms. GitHub reports `UNKNOWN` while it computes
a PR's mergeability, and that churn is most posture writes. In the gc-toolkit log
above, 981 of 1,268 posture writes changed only the merge state, in bursts of 25
to 77 writes in one arm. 84 changed the value, and 141 were the first write the
log shows for that PR.
One derivation costs about 0.85s, so keying on the value adds about one
derivation per pass. Keying on every write would add up to a minute in a burst
arm.

Tests in `assets/scripts/pr-facts.test.sh` run the real writer over the real
derivation and read the label back off the PR fixture. They cover an approval
recorded by the posture arm, a change request routed by the feedback arm, a
merge-state move that the early arm leaves alone, and the full pass re-deriving
after its own posture write.

## What it does not fix

- The speed of the early arms on a slow rig. In the gc-toolkit pass that started
  2026-10-05T23:49Z, arm 2 began 27 to 31 minutes in and arm 3 began 42 to 46
  minutes in. A review there now moves the label within about one pass, where it
  used to wait for an arm 7 that had not finished since 2026-10-04. Making the
  pass faster is tracked by tk-6eu35j, tk-93y5d53, tk-a51cvab and tk-q1n2r3r.
- The opposite direction. When the city's own work on a PR closes, the label
  should return to `needs-review`, and only arm 7 re-derives it then. That is
  tk-wqjhde7, filed from this audit.
- Which value the label should show in each state, such as an approved PR
  waiting to merge. That is tk-blloeo.
- Labels that were already stale. The eight above were re-derived by hand
  through `pr-status-label.sh reconcile` at 2026-10-06T00:51Z, the same writer
  call arm 7 makes.
