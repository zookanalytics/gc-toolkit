---
name: Visual decision — the generalized demo check
description: What tk-vd66j1.6 decided when it generalized the demo review check, beyond the design in specs/tk-vd66j1.5 — where the method lives, how a verdict records the visual decision, the explicit-request case the design left open, and which modalities produce a visual today.
---

# Visual decision

tk-vd66j1.6 generalized the `demo` review check to decide whether a change
needs a visual and to pick its modality, following
[the visual-review design](../tk-vd66j1.5/design.md). The method is
[`skills/review-demo/SKILL.md`](../../skills/review-demo/SKILL.md). This
records what the bead decided where the design left room.

## The method has one home

The index's `demo` row now points `method` at `skills/review-demo/SKILL.md`,
the shape the other specialist checks use (`review-arch`, `review-pm`,
`review-triage`). The old pointer named the two video tools, `gc-demo-script`
and `demo-capture`. Those carry how to produce a video, not whether a change
needs one. The need decision, the modality choice and the verdict rules now sit
in one skill, and the video tools are the video modality's production path
inside it. The dispatch arm in `assets/scripts/review-dispatch-body.sh`
summarizes the skill and shows the verdict call. The `pm` check's boundary text,
in its arm and its skill, moved to match.

## The verdict records the decision mechanically

`signoff.sh` takes `--visual none|repo-artifact|screenshot|video`. The rules:

- It is required on every `demo` verdict and refused on any other check's.
- `none` records with approve only.
- The decision is stamped on the review bead as `visual`, read back before
  anything is posted.
- The posted comment names it on a `Visual:` line.

A decision held only in verdict prose depends on every reviewer remembering to
write it. With the flag, "every demo verdict records its need decision and
modality" is enforced by the one writer of verdicts. The reasons stay in the
verdict body, where a reader wants them: why this modality, and where it was
delivered. The closed review beads become a queryable record of how often a
visual is warranted and which modality fits. List them with
`gc bd list --metadata-field check_name=demo --all` and read `.metadata.visual`.

The flag is keyed on the token `demo`, as `--add-gates` is keyed on `triage`.
The design leaves any rename of the token to the review-gates work, and that
rename carries `VISUAL_GATE` in `signoff.sh` with it.

## An unmet request for a visual does not block

The design left one case to this bead: an explicit human request for a visual
that the check cannot produce. The check approves, naming the request and what
would meet it. Two facts decide it:

- A request-changes verdict files a rework child for the author. No rework can
  build a capture capability the city lacks, so the round would spin.
- A red `demo` lane keeps the PR in draft, because `pr-open.sh` flips a draft
  to ready only when every open-as-draft lane is green. The human who asked
  would never be shown the PR.

The approve posts on the PR, where that human reads it, and the merge still
waits on a human approval. A visual that was produced and shows the change
failing is a different case. That is a finding, and request-changes carries it.

## Which modalities produce a visual today

**Video** keeps the check's existing production path: `gc-demo-script` writes
the script, `demo-capture` records it, and `demo-deliver.sh` delivers it. The
design expected video to wait on the reusable rig-demo mol (tk-vd66j1.2). The
past `demo` reviews show the existing path already captures from a review
session. tk-ms2jt5, tk-tfvnw6, tk-xsr396 and tk-b51aq5 each captured the helm
board change they reviewed, and the last two produced an MP4 through the
SprintShow engine that `demo-capture` drives. None of those clips reached a PR:
each review ran pre-open, before the phase model put the check after the draft
PR opens, and before `demo-deliver.sh` (tk-vd66j1.4) landed. Dropping the path
until the mol lands would leave the check with nothing to deliver. Moving video
onto the mol stays tk-vd66j1.9's.

**Screenshot and repo-artifact** are decided and recorded, but not produced.
The skill says the pack has no production path for either, and the reviewer
approves with a note naming the modality. Building them is tk-vd66j1.7 and
tk-vd66j1.8, both armed to dispatch when this bead closes. Until they land, a
change whose fitting visual is a screenshot or a committed artifact gets a
verdict that names the visual it needs instead of the visual itself. Each
sibling replaces its line under "Produce it and deliver it" in the skill. The
verdict record needs no change, because `--visual` already names the modality.

## What did not change

Triage engages `demo` the same way, through `signoff.sh --add-gates`. The
default check set stays `correctness,triage`, so a diff triage does not engage
never pours the check. The check's phase stays `open-as-draft`.
