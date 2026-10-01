---
name: Visual review — design
description: Design for generalizing the `demo` review check into a visual-review decision — judge whether a change needs a visual, pick the cheapest modality (committed artifact, screenshot, narrated video), and deliver it uncommitted to the PR. Records the architecture and work breakdown for tk-vd66j1.5.
---

# Visual review

The `demo` review check decides whether a change's surface was recorded and
delivers a narrated video. This leg generalizes it. The one check decides
whether a change needs a visual to be understood, and delivers the cheapest
modality that conveys it: a visual already committed to the repo, a screenshot,
or the narrated video the check already produces. When no visual helps, the
check approves with a note and attaches nothing. There is one check, not two.

This records the design and the work breakdown for tk-vd66j1.5, the review-check
leg of epic tk-vd66j1. The direction is the operator ruling in visit tk-t6lcqm:
the capability is a review check that judges visual-need and modality, not an
option to produce a video.

## One check, generalized — not a new one

A new visual check and the existing `demo` check would judge the same thing:
does a user-visible change need to be shown, and if so, show it. `demo` already
does this for one modality, the narrated video. A second check beside it would
hand triage two overlapping tokens for one decision and split the method across
two homes. So this leg generalizes `demo` rather than declaring a sibling:

- Need. `demo` today asks whether the recorded surface does the thing. It now
  asks the prior question as well: does this change need a visual at all? A
  refactor or a pure-logic change needs none, and the check approves with a
  note.
- Modality. When a visual helps, the check picks the cheapest one that conveys
  the change — a committed repo artifact, a screenshot, or the narrated video.
  Video is the modality it already produces.

The index keeps one entry for the check. Its `purpose` broadens from "was the
surface recorded" to "does this change need a visual, and is the right one
delivered." The seam is unchanged: triage engages the one check, and one
`signoff.sh` verdict records the decision.

Naming: whether to rename the index token `demo` to `visual` is a review-gates
decision, not this leg's. The token is shared with in-flight review-gates work
(the phase model below, and its rollout under tk-cwkmt2), so the rename belongs
in that one place if it happens. This design generalizes the check under
whatever token the index carries.

## What already exists

- The `demo` review check. `review-checks.toml` declares it, triage engages it
  through `signoff.sh --add-gates`, `assets/scripts/review-dispatch-body.sh`
  carries its method arm, and `gate-ensure.sh` pours it generically for every
  token in `check_set`. It sits outside the baseline set
  (`DEFAULT_CHECK_SET="correctness,triage"`), so a change triage does not flag
  never runs it. `demo` and `pm` are the specialist checks that follow this
  pattern today.
- Video capture. `skills/demo-capture` drives the SprintShow engine (Playwright,
  on-screen captions, TTS, ffmpeg) to produce a narrated MP4 (tk-vd66j1.3).
- Delivery. `assets/scripts/demo-deliver.sh --file <path> --subject <bead>`
  attaches a file to the bead's PR inline and uncommitted, pins the rig's own
  origin, refuses a foreign PR, and fails closed on a missing or old `gh`
  (tk-vd66j1.4). It requires a resolvable PR and will not deliver before one
  exists.

The capture path for video and the delivery path for any file both work. The
new work is the need-and-modality decision and the two new modalities,
screenshot and repo-artifact.

## When the check runs: the phase model owns it

The check needs the open PR, and for a rendered modality a deployed preview:
`demo-deliver.sh` attaches to a PR and refuses without one, and a screenshot or
a video is captured against the running app. So the check cannot run before the
PR exists. Today's machinery has no way to express that. Triage engages a check
at `pre_open_gate`, and `pr-open.sh` holds the PR closed until every engaged
lane reads green, so a check triage adds is expected to pass before the PR it
needs to produce its artifact.

Closing that gap is not this leg's to design. The review-gates phase model
(tk-yx2oqr.1) makes each check's phase a first-class fact declared in the index,
and places this check at the `open-as-draft` phase: triage decides pre-open that
the change needs the check, `pr-open.sh` opens the PR as a draft so a preview
deploys, the check runs against that preview and greens its lane, and the
draft-to-ready transition surfaces the PR for human review once the check is
green. That model also settles the preview-needs-a-PR case: a draft PR is an
open PR, so the providers that build previews deploy for it.

This leg depends on that model and does not restate it. The check's phase, the
draft-first flow, and the preview question belong to the phase model. Its
implementation is tracked under tk-yx2oqr.2, which is gated on ratifying the
spike (tk-7h5l3m) before any code moves; the per-rig rollout and the naming
convention are a separate concern under tk-cwkmt2. Until the implementation
lands, the generalized check has no correct phase to run in, which is why the
check bead below is blocked on it.

## The decision: need, then modality

Triage and the check divide the judgment. Triage makes the coarse call on the
diff: a change that touches a user-visible surface warrants the check, and
triage adds it; everything else does not, and the check never pours. Triage
adding the check is the statement that a visual might be needed. The check makes
the fine call once engaged: it confirms the change genuinely reads better shown
than described, and if so picks the modality; if not, it approves with a note.

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
layout change is a screenshot, not a video; a new multi-step flow is a video.

## Modalities

- Screenshot (new). Drive the headless browser already provisioned for the
  demo-gated `agents/demo` session (Playwright) to render the affected app state,
  save a PNG, and deliver it with `demo-deliver.sh`. Owned by tk-vd66j1.7.
- Repo-artifact (new). Locate a committed visual near the diff or named by the
  change, and deliver it inline. A committed-file URL renders only as a link, so
  inline delivery re-attaches the file through `demo-deliver.sh`. Owned by
  tk-vd66j1.8.
- Video (the check's existing behavior). Invoke the reusable rig-demo mol
  (tk-vd66j1.2) over the demo-capture path to produce a narrated MP4, and deliver
  it with `demo-deliver.sh`. Owned by tk-vd66j1.9. It waits on the mol
  (tk-vd66j1.2) and the toolchain/TTS foundation (tk-vd66j1.1).

## Delivery

Every modality delivers through `demo-deliver.sh`, which attaches any file inline
and uncommitted and resolves the PR from the anchor bead. No new delivery work is
needed, so there is no delivery bead in the breakdown below.

## Verdict

The verdict is a COMMENT through `signoff.sh`, as every check in this pack is;
the city does not approve PRs.

- No need: approve with a one-line note, no attachment.
- Need met: deliver the visual, approve, and name the modality in the comment.
- Modality not yet built: approve, and note that a visual is warranted and which
  modality fits but is not yet available. This is non-blocking, on purpose. The
  modalities land incrementally, and a PR must not be blocked because the city
  has not finished building the capability. When the only fitting modality is
  video and tk-vd66j1.2 or tk-vd66j1.1 have not landed, the check degrades to a
  screenshot or a repo-artifact if one fits, and otherwise leaves the note.

The "cannot run before the PR exists" case is not a verdict concern; the phase
model handles it by running the check at `open-as-draft`, after the draft PR and
its preview exist.

The one case that may block is an explicit human request for a visual that
cannot be met, the shape that opened this epic. Whether that rises to
request-changes is left to the check bead, which owns the verdict logic.

## Work breakdown

The remaining work is four beads under epic tk-vd66j1, each armed to the polecat
pool and gated so none starts before the design it depends on has landed.

- tk-vd66j1.6 — generalize the `demo` check: the need-and-modality decision and
  the broadened purpose, reaching a verdict and naming the modality even before
  any new capture is wired. Blocked on this design (tk-vd66j1.5) and on the phase
  model implementation (tk-yx2oqr.2), without which the check has no correct phase
  to run in.
- tk-vd66j1.7 — screenshot modality. Blocked on tk-vd66j1.6.
- tk-vd66j1.8 — repo-artifact modality. Blocked on tk-vd66j1.6.
- tk-vd66j1.9 — video modality. Blocked on tk-vd66j1.6, the rig-demo mol
  (tk-vd66j1.2), and the toolchain/TTS foundation (tk-vd66j1.1).

Cost of waiting: the decision and the two new modalities wait on the phase model
implementation (tk-yx2oqr.2) landing, which is itself gated on ratifying the
spike (tk-7h5l3m), and on nothing else in this epic. The video modality
additionally waits on tk-vd66j1.2 and tk-vd66j1.1.

## Boundaries

- The check's phase, triage engagement, and the draft-first flow are the
  review-gates phase model's: designed in tk-yx2oqr.1, implemented under
  tk-yx2oqr.2, and rolled out per-rig under tk-cwkmt2. This leg consumes them and
  does not re-specify them.
- The reusable rig-demo mol is tk-vd66j1.2. The video modality invokes it; this
  leg does not build it.
- The capture toolchain and the TTS key are tk-vd66j1.1. The video modality
  assumes them and names the dependency; it does not provision them.
- npm-publishing the SprintShow engine stays deferred (operator-run), per the
  epic.
