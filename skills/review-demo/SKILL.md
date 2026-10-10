---
name: review-demo
description: The method for the demo check, the visual review. Decide whether a change needs a visual to be understood and, when it does, pick the cheapest modality that conveys it (a visual the repo already carries, a screenshot, or a narrated video), deliver it to the PR inline and uncommitted, and record the decision on one signoff verdict. Use when you hold a review bead whose check_name is demo, or when triage asks whether a diff warrants the demo check.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# The demo check

The demo check decides whether a change needs a visual to be understood, and
delivers the right one when it does. Need comes first: would a reviewer
understand this change better by seeing it than by reading the diff? Modality
comes second: what is the cheapest visual that shows it? When no visual helps,
the check approves with a one-line note and attaches nothing.

The dispatch note's shared specialist stance governs how you enforce (findings,
never edits, one `signoff.sh` verdict). This file is the visual lens. Whether the
change is correct is the `correctness` check's. Whether it is the right thing to
ship, and presents itself so the operator can decide, is the `pm` check's.

## When triage adds it

Triage adds `demo` when the diff changes a surface a person looks at:

- a rendered page, component, board, or dashboard;
- a layout or styling change;
- a new or changed interactive flow;
- output a person reads in a terminal, such as a command's report.

Logic, refactors, internal plumbing, tests, and docs read as text need no
visual, and triage adds nothing for them. That is the common case. The default
check set is the baseline, `correctness,triage`, so under it `demo` runs only on
a diff triage added it to.

## When it runs

The check index places `demo` at the `open-as-draft` phase. Triage adds it before
the PR exists, the refinery opens the PR as a draft, and this check runs against
that draft. The review bead carries `review_branch`, `review_base` and the pinned
`reviewed_oid`; the anchor carries the PR (`pr_number`, `pr_url`). Where the
rig's host deploys previews for pull requests, the draft has one. The PR does
not leave draft for human review until every pre-open and open-as-draft check
reads green, this one included.

## Decide need

Read the anchor for what the change is for, then the diff at the pinned commit.
Triage made a coarse call when it saw a surface in the diff. Yours is the fine
call: does seeing the change explain it better than reading it? A change to a
page's source that alters nothing the page renders, or a style change too small
to notice in a capture, needs no visual.

An explicit request for a visual, in the anchor or from a human on the PR,
settles need: a visual is needed.

When no visual helps, approve with a one-line note that says why, attach
nothing, and record `--visual none`.

## Pick the modality

When a visual helps, pick the cheapest one that conveys the change.

| Modality | What it shows | Pick it when |
|---|---|---|
| `repo-artifact` | a visual the repo already carries: a diagram, an image, or a clip in the diff or named by the change | a committed visual already shows what changed, so nothing needs capturing |
| `screenshot` | one rendered state | a single frame carries the change: a page, a board, a layout |
| `video` | motion, or a flow across several steps, with narration | the change happens over time: an interaction or a sequence |

Prefer the cheaper modality unless the change needs the richer one. A static
layout change is a screenshot, not a video. A new multi-step flow is a video.

## Produce it and deliver it

Every modality reaches the PR the same way. `assets/scripts/demo-deliver.sh
--file <path> --subject <anchor>` resolves the PR from the anchor and attaches
the file to it in a comment, inline and uncommitted. It refuses a PR outside the
rig's origin and exits non-zero when it cannot attach. `doctor/check-demo-toolchain`
reports whether the `gh` it needs is present.

- `video`: `skills/gc-demo-script/SKILL.md` writes a `demo:capture` script from
  the anchor and the diff. `skills/demo-capture/SKILL.md` records that script
  against the running app and assembles the narrated MP4. The app is the
  draft's preview where one deploys, and otherwise the app served from the
  reviewed commit. Write the clip outside the tracked tree.
  `doctor/check-demo-toolchain` reports whether the capture toolchain resolves
  in this session.
- `screenshot` and `repo-artifact`: this pack has no production path for either.
  Record the modality you picked and approve with the note that it fits and was
  not delivered.

When the modality that fits cannot be produced here, a cheaper one that still
shows the change is the fallback where it can be produced. Otherwise the note
stands.

A rig can name its own visual surfaces, and how to serve its app for a capture,
in `docs/review-demo.md`. The dispatch note appends that file from the reviewed
commit when the rig carries one.

## Judge what it shows

The visual is evidence: judge what it shows, not what the diff claims. A capture
in which the surface errors, a flow breaks, or a step fails against what the
change claims is a finding against the change. Request changes, and name the
visual as the evidence.

A capture that cannot run for a reason outside the change is not a finding. The
capture toolchain may not resolve, the rig may have no app to serve, or no
preview may deploy. Each of those is the note below.

## The verdict

One `signoff.sh` call records the verdict and the decision. `--visual` carries
the decision: `none` when no visual is needed, otherwise the modality you
picked. It sits beside the flags the review formula's verdict step passes:

```bash
signoff.sh --review-bead "$REVIEW_BEAD" --verdict approve --visual screenshot \
  --reviewed-oid "$REVIEWED_OID" --notes-file findings.md --findings-file findings.json
```

`signoff.sh` refuses a demo verdict without `--visual`, and refuses `none` with
`request-changes`, because a check that found no visual needed has nothing to
block on. It stamps the decision on the review bead as `visual` and names it on
the posted comment.

The verdict body states the reasons, one sentence each: the need decision; when
a visual helps, the modality and why it is the cheapest that conveys the change;
and where the visual was delivered, or what stopped it.

- **No visual needed.** Approve with `--visual none` and a one-line note. Attach
  nothing.
- **Delivered, and it shows the change working.** Approve with its modality.
- **Delivered, and it shows the change failing.** Request changes with its
  modality. The finding goes in `findings.json`.
- **The fitting visual cannot be produced here.** Approve with its modality, and
  say that a visual is warranted and what stopped it: no production path in this
  pack, a capture toolchain that does not resolve, or no running app to capture.
  This never blocks. A rework child cannot build the city's capture capability,
  and a red lane would keep the PR in draft, away from the human who would judge
  it.
- **A human asked for the visual and it cannot be produced.** Approve the same
  way, naming the request and what would meet it. The verdict posts on the PR the
  human reads, and the merge still waits on a human approval.
