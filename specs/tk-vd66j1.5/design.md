---
name: Visual review check — design
description: Design for the `visual` PR-triage review check that decides whether a change needs a visual, picks a modality, and delivers it uncommitted to the PR. Records the architecture and work breakdown for tk-vd66j1.5.
---

# Visual review check

A PR-triage review check named `visual` decides whether a change needs a visual
to be understood, selects the modality that fits — a screenshot, a visual
already committed to the repo, or a narrated video demo — and captures and
delivers that visual on the PR, inline and uncommitted. When no visual helps,
the check does nothing. Skipping is the default.

This records the design and the work breakdown for tk-vd66j1.5, the review-check
leg of epic tk-vd66j1. The direction is the operator ruling in visit tk-t6lcqm
(2026-09-29): the capability is a review check that judges visual-need and
modality, not an option to produce a video.

## What already exists

- Video capture runs end-to-end in Gas City. `skills/demo-capture` drives the
  SprintShow engine (Playwright, on-screen captions, OpenAI TTS, ffmpeg) to
  produce a narrated MP4 (tk-vd66j1.3, PR #887).
- Delivery to a PR is a solved primitive. `assets/scripts/demo-deliver.sh
  --file <path> --subject <bead>` attaches a file to the bead's PR with `gh pr
  comment --attach`, which uploads to GitHub's user-attachments CDN and renders
  it inline (a video as a player, an image inline) with no human step
  (tk-vd66j1.4, PR #919). It pins the rig's own origin, refuses a foreign PR,
  and fails closed on a missing or pre-2.99.0 `gh`.

So the check builds on a working capture path for video and a working delivery
path for any file. The new work is the decision (need and modality) and the two
new modalities (screenshot, repo-artifact).

## How the check plugs into the review system

A check in this pack is a declared method, not a script. The seam has four
parts, and `visual` uses all four the way `demo` does.

- The index. `review-checks.toml` declares each check as `[checks.<name>]` with
  a `method` pointer and a one-line `purpose`. `visual` adds one entry.
- The baseline. `gate-ensure.sh` sets `DEFAULT_CHECK_SET="correctness,triage"`
  and pours one `mol-review` bead per gate in an anchor's `check_set`. A check
  absent from the set is never poured, so a check outside the baseline costs
  nothing until something adds it. `visual` stays out of the baseline.
- Engagement. Triage (`skills/review-triage/SKILL.md`) widens `check_set` with
  `signoff.sh --verdict approve --add-gates <check>`, and may add any check the
  index declares. `visual` is engaged when triage sees a diff that touches a
  user-visible surface. Adding nothing stays the common case, so most PRs never
  run `visual`.
- The method and the verdict. `review-dispatch-body.sh` carries a `case
  "$CHECK_NAME"` arm per check; `visual` adds an arm whose note tells the
  reviewer to judge need, then pick a modality. The method itself is a SKILL and
  an optional `docs/review-visual.md` rig-extension read from the reviewed
  commit. The reviewer records one verdict through `signoff.sh`.

No change to `gate-ensure.sh` is needed; it pours generically for every token in
`check_set`.

This mirrors `demo`, which is declared, outside the baseline, engaged by triage,
and binding once engaged. `visual` differs in two ways. Its need-judgment is
finer: triage engages it on a surface heuristic, and the check itself decides
whether a visual genuinely aids understanding. And it is not binding the same
way, as the Verdict section states.

## The decision: need, then modality

The check makes two judgments in order.

Need. Does the diff change something a reviewer understands better by seeing it
than by reading the diff? User-visible surfaces qualify: a rendered page or
component, a board or dashboard, a CLI's output, a layout or styling change, a
new interactive flow. Pure logic, refactors, and internal plumbing do not.
Triage's surface heuristic is the coarse gate; the check confirms a real need
before producing anything.

Modality. When a visual helps, pick the cheapest one that conveys the change.

- Repo-artifact, when a committed visual already illustrates the change. No
  capture.
- Screenshot, when one rendered state carries it: a page, a board, a layout.
- Video, when motion or a multi-step flow carries it, and narration explains it.

Prefer the cheaper modality unless the change needs the richer one. A static
layout change is a screenshot, not a demo; a new multi-step flow is a video.

## Modalities

- Screenshot (new). Drive the headless browser already provisioned for the
  demo-gated `agents/demo` session (Playwright) to render the affected app
  state, save a PNG, and deliver it with `demo-deliver.sh`. Owned by
  tk-vd66j1.7.
- Repo-artifact (new). Locate a committed visual near the diff or named by the
  change, and deliver it inline. A committed-file URL renders only as a link, so
  inline delivery re-attaches the file through `demo-deliver.sh`. Owned by
  tk-vd66j1.8.
- Video (reuses the epic's capture leg). Invoke the reusable rig-demo mol
  (tk-vd66j1.2) over the proven demo-capture path to produce a narrated MP4, and
  deliver it with `demo-deliver.sh`. Owned by tk-vd66j1.9. It waits on the mol
  (tk-vd66j1.2) and the toolchain/TTS foundation (tk-vd66j1.1).

## Delivery

Every modality delivers through `demo-deliver.sh`. It already attaches any file
inline and uncommitted and resolves the PR from the anchor bead. No new delivery
work is needed, which is why there is no delivery bead in the breakdown below.

## Verdict

The verdict is a COMMENT through `signoff.sh`, as every check in this pack is;
the city does not approve PRs.

- No need: approve with a one-line note, no attachment.
- Need met: deliver the visual, approve, and name the modality in the comment.
- Need unmet because the modality is not yet buildable: approve, and note that a
  visual is warranted and why it could not be produced. This is non-blocking, on
  purpose. The modalities land incrementally, and a PR must not be blocked
  because the city has not finished building the capability. When the only
  fitting modality is video and tk-vd66j1.2 or tk-vd66j1.1 have not landed, the
  check degrades to a screenshot or a repo-artifact if one fits, and otherwise
  leaves the note.

The one case that may block is an explicit human request for a visual that
cannot be met, the shape that opened this epic (PR#887). Whether that rises to
request-changes is left to the decision-core bead, which owns the verdict logic.

## Work breakdown

Delivery is done (tk-vd66j1.4). The remaining work is four beads under epic
tk-vd66j1, each armed to the polecat pool and gated so none starts before the
design it depends on has landed.

- tk-vd66j1.6 — the check: declaration, triage engagement, and the need +
  modality decision. The runnable core; it reaches a verdict and names the
  modality even before any capture is wired. Blocked on tk-vd66j1.5 (this
  design).
- tk-vd66j1.7 — screenshot modality. Blocked on tk-vd66j1.6.
- tk-vd66j1.8 — repo-artifact modality. Blocked on tk-vd66j1.6.
- tk-vd66j1.9 — video modality. Blocked on tk-vd66j1.6, the rig-demo mol
  (tk-vd66j1.2), and the toolchain/TTS foundation (tk-vd66j1.1).

Cost of waiting: the check and its two new modalities (screenshot,
repo-artifact) do not wait on anything outside this leg and can land as soon as
the design does. Only the video modality waits on tk-vd66j1.2 and tk-vd66j1.1;
until they land, an engaged check that would pick video falls back or leaves a
note, so the capability is useful before video is wired.

## Boundaries

- The reusable rig-demo mol is tk-vd66j1.2, not this leg. This check invokes it
  for the video modality; it does not build it.
- The capture toolchain and the TTS key are tk-vd66j1.1. This check assumes them
  for video and names the dependency; it does not provision them.
- npm-publishing the SprintShow engine stays deferred (operator-run), per the
  epic.
