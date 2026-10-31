---
name: review-demo
description: The method for the demo check, the visual review. Decide whether a change needs a visual to be understood and, when it does, pick the cheapest modality that conveys it (a visual the repo already carries, a screenshot, or a narrated video), deliver it to the PR inline and uncommitted, and record the decision on one signoff verdict. Use when you hold a review bead whose check is demo, or when triage asks whether a diff warrants the demo check.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# The demo check

The demo check decides whether a change needs a visual to be understood, and
delivers the right one when it does. Need comes first: would a reviewer
understand this change better by seeing it than by reading the diff? Modality
comes second: what is the cheapest visual that shows it? When no visual helps,
the check approves with a one-line note and attaches nothing.

This check holds the specialist stance: load `gc-toolkit.specialist-stance`
before you judge. This file is the visual lens. Whether the change is correct
is the `correctness` check's. Whether it is the right thing to ship, and
presents itself so the operator can decide, is the `pm` check's.

## What it reads

The anchor `<anchor_bead>` for what the change is for, then the diff at
`<reviewed_oid>`, in `<worktree>`: `git diff origin/<review_base>...HEAD`. The
draft PR, `<review_pr_url>`, and its preview where the rig's host deploys one.
The rig's guidance for this check, the reviewed commit's `docs/review-demo.md`,
which the review formula printed when the commit carries one: a rig names its
own visual surfaces there, and how to serve its app for a capture.

### When it runs

The check index places `demo` at the `open-as-draft` phase. Triage adds it before
the PR exists, the refinery opens the PR as a draft, and this check runs against
that draft. Where the rig's host deploys previews for pull requests, the draft
has one. The PR does not leave draft for human review until every pre-open and
open-as-draft check reads green, this one included.

## What it judges

### When triage adds it

Triage adds `demo` when the diff changes a surface a person looks at:

- a rendered page, component, board, or dashboard;
- a layout or styling change;
- a new or changed interactive flow;
- output a person reads in a terminal, such as a command's report;
- markdown the city posts on GitHub, such as a review comment or a PR body.

Logic, refactors, internal plumbing, tests, and docs read as text need no
visual, and triage adds nothing for them. That is the common case. The default
check set is the baseline, `correctness,triage`, so under it `demo` runs only on
a diff triage added it to.

### Decide need

Triage made a coarse call when it saw a surface in the diff. Yours is the fine
call: does seeing the change explain it better than reading it? A change to a
page's source that alters nothing the page renders, or a style change too small
to notice in a capture, needs no visual.

An explicit request for a visual, in the anchor or from a human on the PR,
settles need: a visual is needed.

When no visual helps, approve with a one-line note that says why, attach
nothing, and record `--visual none`.

### Pick the modality

When a visual helps, pick the cheapest one that conveys the change.

| Modality | What it shows | Pick it when |
|---|---|---|
| `repo-artifact` | a visual the repo already carries: a diagram, an image, or a clip in the diff or named by the change | a committed visual already shows what changed, so nothing needs capturing |
| `screenshot` | one rendered state of an app page, of a command's output in a terminal, or of markdown as GitHub renders it | a single frame carries the change: a page or a board, a report a command prints, a comment the city posts |
| `video` | motion, or a flow across several steps, with narration | the change happens over time: an interaction or a sequence |

Prefer the cheaper modality unless the change needs the richer one. A static
layout change is a screenshot, not a video. A new multi-step flow is a video.

### Produce it and deliver it

The pack's scripts named here sit in the directory `gc <binding> scripts-dir`
prints, where `<binding>` is the name in front of this skill's: `gc-toolkit` in
`gc-toolkit.review-demo`. A capture takes minutes, so it runs under the
claim-lease keepalive the review formula names, from the review workspace, the
directory that holds `<worktree>`, so the engine's working files stay out of
the reviewed tree.

Every modality reaches the PR the same way. `demo-deliver.sh --file <path>
--subject <anchor_bead>` resolves the PR from the anchor and attaches the file
to it in a comment, inline and uncommitted. It refuses a PR outside the rig's
origin and exits non-zero when it cannot attach. `doctor/check-demo-toolchain`
reports whether the `gh` it needs is present.

- `video`: record it in this review with `rig-demo-capture.sh --script demo.md
  --output demo.mp4 <app target>`, the rig-demo mol's capture core. Do not pour
  `mol-rig-demo` for it. A pour runs later in another session, so this verdict
  could not judge its clip, and by then the reviewed worktree is gone.
  The skill `gc-toolkit.gc-demo-script` writes the `demo:capture` script from
  the anchor and the diff. Keep the script and the clip in the review workspace.

  The app target is the draft's preview, `--base-url <url>`, where one
  deploys. Otherwise serve the reviewed worktree, so the clip shows the
  reviewed commit: `--serve-dir <worktree>/<dir>` for a static build, or
  `--serve "<command>" --cwd <worktree>` for a dev server. Exit 0 is a clip
  in which every step's proof held, exit 3 is a clip in which at least one
  step failed its proof, and exit 1 is no clip. The last line names the clip
  and says whether it is narrated. Narration needs `OPENAI_API_KEY` in the
  session. Without it the clip is silent and captioned, and it still shows the
  change. `doctor/check-demo-toolchain` reports which parts of the capture
  toolchain resolve in this session.

  A video's `--serve` command chooses its own port, because the SprintShow
  engine sets no `$PORT` for it. The engine waits for the command on the port
  `--port` names, or on 5173 when none is named, and it refuses `--port 0`. So
  `--port` names the port the command binds, and two captures side by side each
  need a different port.
- `repo-artifact`: list the visuals the reviewed commit already carries.

  ```bash
  "$(gc <binding> scripts-dir)/demo-repo-artifact.sh" candidates --base "origin/<review_base>" --oid "<reviewed_oid>" --anchor "<anchor_bead>" --repo "<worktree>"
  ```

  Each line gives a reason and a path. `changed` is a visual the diff adds or
  edits. `named` is one whose path appears in a line the diff adds or in the
  anchor. `near` is one in a directory close to a changed file's, nearest
  first. Exit 3 means the commit carries no such visual, so this modality does
  not fit. Open an image candidate at `<worktree>/<path>` before you pick it.
  A committed visual shows what its author recorded, not a run of the reviewed
  commit. Pick one that matches what the diff does, because one that shows a
  state the reviewed commit no longer produces would mislead the human.
  Deliver the one you pick with `demo-repo-artifact.sh deliver --path <path>
  --base origin/<review_base> --oid <reviewed_oid> --subject <anchor_bead>
  --repo <worktree>`. It attaches the file as the reviewed commit stores it,
  through `demo-deliver.sh`. The comment says where the visual came from:
  whether this change adds, edits, moves or copies it, or leaves it unchanged,
  and the commit that last changed it. The delivery's last line says the
  same, and the verdict body repeats it.
- `screenshot`: render the one state that shows the change and capture it with
  `demo-screenshot.sh`. It saves the PNG with the SprintShow engine's screenshot
  command, in the headless browser the video capture drives, and checks each
  step's proof as a video does. Its subcommand is the kind of surface the change
  affects: `demo-screenshot.sh page --script shot.md --output <name>.png <app
  target>` for an app page a demo:capture script drives to the state,
  `demo-screenshot.sh terminal --command "<command>" --cwd <worktree> --output
  <name>.png` for a command's output as a terminal shows it, and
  `demo-screenshot.sh markdown --file comment.md --output <name>.png` for
  markdown, such as a comment the city posts, as GitHub shows it. The markdown
  render takes no keepalive.

  For a page, write the script as you would for a video
  (`gc-toolkit.gc-demo-script`). Its steps drive the app to the state, the
  capture is the state the last step leaves, and the app target is the one a
  video takes. `demo-screenshot.sh` adds what the engine lacks for a `--serve`
  command. It puts the port `--port` names in the command's `$PORT`, and it
  turns `--port 0` into a free port first, so two screenshots side by side each
  get a server of their own. With no `--port`, the command gets no `$PORT` and
  the engine waits on 5173, as for a video.
  `--selector <css>` captures one element instead of the viewport, and
  `--full-page` captures the whole page. For a terminal, the engine types the
  command at a bash prompt in a terminal of its own, whose shell starts in
  `--cwd`, so a relative path runs the reviewed commit's script. The capture
  shows the command after a `$` prompt, then what it printed, or the screen a
  full-screen program it starts draws. A command that waits for input is no
  capture, and one that pages a long output in a terminal, such as `git log`,
  waits in its pager, so run it with the pager off (`git --no-pager log`). The
  capture is as tall as the session, so bound a long output with the command's
  own limit. Run only a command that reads, because one that files, routes or
  closes anything does it in the live city. `--text <file>` shows output
  captured earlier, which the terminal prints with `cat`. For markdown, write
  the markdown the reviewed commit composes to the
  file. GitHub's own markdown renderer turns it into HTML in the context of the
  rig's origin, so the capture shows it as the PR would. github.com's page
  script finishes some blocks after that renderer returns, such as a mermaid
  diagram or math, and the capture has no such script. So markdown holding one
  exits 1 with no capture and names each such block, and that comment is a
  surface none of these captures renders. GitHub shows a `<details>` block
  collapsed, and `--expand` opens every one, for a second capture of what the
  collapsed blocks hold.

  Write the PNG in the review workspace and name it for what it shows, because
  the file's name is the image's alt text on the PR. Exit 0 is a capture. For a
  page, exit 3 is a capture in which at least one step failed its proof. Exit 1
  is no capture. The last line names the PNG and its size, and for a command it
  says how the command ended: its exit status, or that it took over the screen
  and was still running. Open the PNG before you deliver it with
  `demo-deliver.sh --file <name>.png --subject <anchor_bead> --body "<what it
  shows, and what it was rendered from>"`.

When the modality that fits cannot be produced here, a cheaper one that still
shows the change is the fallback where it can be produced. Otherwise the note
stands. The verdict records a delivered fallback as one: `--visual` names the
modality delivered, and `--visual-fallback-from` names the one that fits.

### Judge what it shows

The visual is evidence: judge what it shows, not what the diff claims.

A video capture or a page screenshot that exits 3 recorded a step whose proof
failed. The step lines name that step and the assertion that did not hold. A
video capture run with `--mode proof` also keeps a screenshot of every step in
the working directory its last line names, and a page screenshot shows the
state its steps left. Read them to tell whether the change fails or the script
asserted the wrong thing. A script that asserted the wrong thing is yours to
correct before you capture again.

## What blocks

A capture in which the surface errors, a flow breaks, or a step fails against
what the change claims is a finding against the change. Request changes, and
name the visual as the evidence. A change that fails is that finding, and the
clip or the screenshot is its evidence to deliver.

A capture that cannot run for a reason outside the change is not a finding. The
capture toolchain may not resolve, the rig may have no app to serve, or no
preview may deploy. Each of those is the note below, and it never blocks.

## The verdict

The formula's one `signoff.sh` call records the verdict and the decision, with
the check's two flags. `--visual` carries the decision: `none` when no visual is
needed, otherwise the modality you picked. A fallback adds
`--visual-fallback-from <the modality that fits>`.

`signoff.sh` refuses a demo verdict without `--visual`, and refuses `none` with
`request-changes`, because a check that found no visual needed has nothing to
block on. It stamps the decision on the review bead as `visual` and names it on
the posted comment's `Visual:` line. That line says what kind of visual the
verdict rests on. A `repo-artifact` reads `author-committed` there, because a
committed visual is what an author recorded, not a capture of the reviewed
commit. A fallback is stamped as `visual_fallback_from`, and the line then
reads, for example, `Visual: repo-artifact (author-committed; fallback from
video)`. `signoff.sh` refuses a fallback that is not cheaper than the modality
it stands in for.

The verdict body states the reasons, one sentence each: the need decision; when
a visual helps, the modality and why it is the cheapest that conveys the change;
and where the visual was delivered, or what stopped it. A delivered video's
sentence also says whether the clip is narrated or silent. A delivered
repo-artifact's sentence also says where the visual came from, as its delivery
comment does. A delivered screenshot's sentence also says what it was rendered
from: the reviewed commit, and any fixture that stands in for live data.

- **No visual needed.** Approve with `--visual none` and a one-line note. Attach
  nothing.
- **Delivered, and it shows the change working.** Approve with its modality.
- **Delivered, and it shows the change failing.** Request changes with its
  modality. The finding goes in `findings.json`.
- **Delivered as a fallback.** Judge what it shows the same way. Record the
  modality delivered with `--visual` and the one that fits with
  `--visual-fallback-from`, and say what stopped the one that fits.
- **The fitting visual cannot be produced here.** Approve with its modality, and
  say that a visual is warranted and what stopped it: a surface none of these
  captures renders, a capture toolchain that does not resolve, or no running app
  to capture.
  This never blocks. A rework child cannot build the city's capture capability,
  and a red lane would keep the PR in draft, away from the human who would judge
  it.
- **A human asked for the visual and it cannot be produced.** Approve the same
  way, naming the request and what would meet it. The verdict posts on the PR the
  human reads, and the merge still waits on a human approval.
