---
name: Operator review dispositions — visual-review design
description: How each operator review comment on PR#926 (review 5375376105) was addressed in the rework of the visual-review design.
---

# Operator review dispositions

The first design declared a `visual` review check beside the existing `demo`
check. The operator's review rejected that and raised the check's timing. The
rework reframes the design around one check — the `demo` check generalized to
judge visual-need and pick a modality — and defers the timing to the review-gates
phase model. Each comment and its disposition:

| Comment (johnzook) | Subject | Disposition |
|---|---|---|
| isn't there already a demo check … shouldn't create another for the same thing | one check vs two | Fixed. The design no longer declares a `visual` check; it generalizes the one `demo` check to decide need and modality. |
| Open question: does the check evaluate need, or does triage adding it signal need, or two-stage | who decides need | Answered in the design. Triage makes the coarse call and adds the check on a user-visible surface; the check confirms genuine need and picks the modality once engaged. |
| This aligns with what my earlier comment expected | triage engagement | Kept and made explicit. The triage-engagement model is unchanged; it is now stated plainly in "The decision: need, then modality." |
| Still doesn't justify why both should exist | one check vs two | Fixed. There is one check now, so the justification the comment rejected is gone. |
| can't run until the PR exists … a bead is making the phases clearer … preview deployment needs the PR | phase / timing | Fixed. The design depends on the review-gates phase model (tk-yx2oqr.1, rolled out under tk-cwkmt2): the check runs at the `open-as-draft` phase, against the draft PR and its preview. The check bead tk-vd66j1.6 is now blocked on that implementation. |

## What the reframing changed

One check, not two. The `demo` check already decides whether a surface was
recorded and delivers a video; the design generalizes it to decide whether a
change needs a visual at all and to pick the cheapest modality (committed
artifact, screenshot, or the narrated video it already produces). Video is the
modality it already does. The index keeps one entry whose purpose broadens.

Timing is the phase model's. The check needs the open PR and a preview, so it
cannot run before the PR exists. Rather than re-specify that, the design depends
on tk-yx2oqr.1, which places the check at `open-as-draft`: triage decides pre-open
that the check is needed, the PR opens as a draft so a preview deploys, the check
runs against the preview, and the draft-to-ready transition surfaces the PR once
the check is green.

Whether to rename the index token `demo` to `visual` is left to the review-gates
epic that owns the token; the design generalizes the check under whatever token
the index carries.
