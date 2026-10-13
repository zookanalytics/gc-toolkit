---
name: Video modality — the demo check records its clip inside the review
description: What tk-vd66j1.9 decided when it wired the demo review check's video modality to the rig-demo mol. Covers why the review calls the mol's capture core instead of pouring the mol, why the capture core separates a clip with a failed step from no clip, and the live capture proof on the macOS host.
---

# Video modality

tk-vd66j1.9 wires the `demo` review check's video modality to the reusable
rig-demo mol ([its design](../tk-vd66j1.2/design.md)), following
[the visual-review design](../tk-vd66j1.5/design.md) and
[the decision core](../tk-vd66j1.6/visual-decision.md). The method is
[`skills/review-demo/SKILL.md`](../../skills/review-demo/SKILL.md). This records
what the bead decided where the bead and the designs left room.

## The review calls the capture core and does not pour the mol

The bead and both designs say the video modality invokes the rig-demo mol. The
mol has two halves: `formulas/mol-rig-demo.toml`, a pool workflow, and
`assets/scripts/rig-demo-capture.sh`, the capture core the workflow calls. The
review calls the capture core inside its own session and does not pour the
formula. Four facts decide it.

- The verdict judges the clip. The skill treats the visual as evidence, and a
  clip that shows a step failing is a request-changes finding. A pour runs in
  another session once a pool slot frees, so the review would post its one
  verdict before the clip existed.
- The reviewed tree does not outlive the review. The review serves the app from
  its worktree at the reviewed commit, and the verdict step removes that
  workspace (`docs/review-workspace.md`). A pour that ran afterwards would find
  the path gone. Given a relative `serve_dir` instead, the mol resolves it
  against the rig's own checkout, which is on `main` and not at the reviewed
  commit. Either way the clip would not show the change.
- The failure paths differ. The mol escalates every capture failure to a human
  and holds its molecule, which suits a demo an operator asked for. In a
  review, a capture that cannot run is a note in an approve and never a block.
- A review that waited on a pour would hold one pool slot while it waited for
  another slot in the same pool.

So the review keeps the judgment half (the scenario, the app target, and what
the clip shows) and calls the same mechanical half the mol calls. The mol stays
the path for an operator who wants a clip of any rig. Its description had named
this bead as a pourer, and now names the review check as a caller of its
capture core.

## A clip with a failed step is not a failed capture

The engine (`sprintshow run`) exits 1 in two cases. In one it produced no clip.
In the other it produced a clip in which a step failed its proof, and it kept
the clip and its working files. The capture core reported both as a failed
capture with exit 1. A reviewer reading that would take a clip that shows the
change failing for a toolchain failure, which the skill says to approve with a
note, and the evidence would never reach the PR.

The capture core now exits 3 for the second case and names the clip and the
working directory the engine kept. It tells the cases apart by the engine's
closing report, which the engine prints only once a clip is assembled. A
non-zero exit without that report, or with no clip on disk, stays exit 1. The
same report says whether the clip is narrated, and the capture core's last line
carries that, so a verdict can say whether its clip is voiced. The mol treats
exit 3 as it treats every failure, escalating and holding, and its escalation
now says which of the two cases it hit.

## Proof

These runs used the capture core from this branch on the macOS host, in a
directory laid out like a review workspace: the reviewed tree as `wt`, the
script and the clip beside it, and the capture run from the workspace. The app
was the SprintShow engine's bundled sample, served from `wt` with
`--serve-dir`, driven by the engine's `demos/sample.md`.

| Run | Exit | Last line | What it showed |
|---|---|---|---|
| walkthrough, `OPENAI_API_KEY` passed to the command | 0 | `captured …/demo.mp4 (narrated, 688118 bytes)` | All 6 step proofs held. The clip runs 30.9 s, with h264 video at 1280×900 and an AAC narration track. |
| walkthrough, one assertion made false, no key | 3 | `captured …/demo-failing.mp4 (silent), but 1 step(s) failed their proof; the engine kept its working files in …` | The engine named step 6 and the assertion that did not hold, and kept the clip and the raw recording. |
| proof mode, the same false assertion, no key | 3 | the same shape | The kept directory held a screenshot of every step and `issues.json`. Step 6's screenshot shows the board reading 3 tasks and 1 done against a script that asserted 2 done, so a reviewer can see the script was wrong. |

The two walkthrough captures took 217 s and 141 s, on a host whose load average
stood near 50 while other polecats ran their suites. A capture can outlive a
review claim's five-minute lease, so the skill runs it under the review step's
lease keepalive.

Delivery is `demo-deliver.sh`, unchanged since tk-vd66j1.4 and covered by
`demo-deliver.test.sh`. The gh on this host (2.102.0) documents
`gh pr comment --attach` for a video file. No clip has been attached to a real
PR in this city yet. The first engaged review that picks video makes the first
live attach.

## What a review session needs

- The engine, Chromium and ffmpeg resolve on this host. The engine is the local
  `sprintshow` rig checkout with its `node_modules`, Chromium is Playwright's
  `chromium-headless-shell` under `~/Library/Caches/ms-playwright`, and ffmpeg
  is the engine's `ffmpeg-static`.
- Narration needs `OPENAI_API_KEY` in the session's environment. The key is in
  the city's secrets file, `$GC_HOME/secrets.env`, but this session's
  environment did not carry it, so the proof passed it to the narrated capture
  directly. tk-zgctuku records why sessions on this host lack it: the
  supervisor started before the key was placed, and `gc supervisor install` is
  the operator's step that brings it into session environments. Until then a
  review's clip is silent and captioned, and the capture core's last line says
  so.
