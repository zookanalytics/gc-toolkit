---
name: Screenshot modality — what tk-vd66j1.7 decided
description: What tk-vd66j1.7 decided when it built the demo check's screenshot modality for three kinds of surface (an app page, a command's output, a rendered PR comment), why every kind captures through the SprintShow engine's own screenshot command, and the live captures that prove each kind on the macOS host.
---

# The screenshot modality

The demo check could pick a screenshot but had no way to produce one. Four demo
reviews from 2026-10-13 picked a screenshot and delivered none. They wanted the
helm board's held dismiss (PR 1240), deferred-dispatch's held-arm lines
(PR 1239), the `gc-helm.sh unplaced` report (PR 1243), and the collapsed review
comment (PR 1251). The operator's ruling in visit tk-9duzkhg widened this bead
from "the rig's app" to the three kinds of surface those four show.
`assets/scripts/demo-screenshot.sh` now captures each kind as a PNG, and
`demo-deliver.sh` delivers it.

## Decisions

**One script, with a subcommand per kind.** `page`, `terminal` and `markdown`
each take the input their surface needs, and all three end in the same PNG
check and the same last line. One call makes one PNG, because one delivery
attaches one file.

**SprintShow takes the screenshot.** The engine's `sprintshow screenshot`
command takes every PNG. It drives a demo script's steps in the engine's
headless browser through `runStep`, the one step runner the engine's videos
use, so a proof means the same thing in a screenshot as in a video. It draws no
caption, needs neither ffmpeg nor a narration key, and saves the viewport, the
whole page or one element. A page capture hands it the script and the app
target a video takes. A terminal or markdown surface has no app to drive, so
`demo-screenshot.mjs` draws it as one HTML page with no script. The engine
serves that page from a directory of the capture's own and captures its
`#surface` element with `--transparent`, through a one-step script whose proof
is that the surface is drawn. Every capture runs at `--scale 2`, so its text
stays sharp at the width of a PR comment.

The first build drove the engine's browser through a driver of the pack's own,
because the engine had no still capture that fit. Its proof mode burns a
caption into each frame, assembles an MP4, which needs ffmpeg, and keeps its
frames only when a step fails or `--keep` is passed. Playwright's own
`screenshot` command cannot click, so it cannot reach a state like PR 1240's
held dismiss, and it cannot crop to an element. The demo agent's Playwright MCP
launches Google Chrome, which this host does not have (tk-qrga4h5). So the
driver loaded the engine's library and ran a copy of proof mode's step: its
prove-then-fail-if order, its reason strings, its manual marker and log lines,
and the engine's `joinUrl` and `PROVE_TIMEOUT`. Reviewing PR 1266, the operator
asked why SprintShow did not capture the screenshot instead of the pack
duplicating its logic. While the copy existed, a screenshot checked the same
proofs as a video only as long as the two copies agreed. So the still capture
went into the engine (ss-pc8t, sprintshow PR 3), and the pack's copy, its
browser launch and its free-port probe went. The operator's question set the
terminal kind aside. It rendered through the same pack-side browser launch as
markdown, though, and keeping that launch for one kind would have kept a second
browser path, so the terminal kind captures through the engine too.

**An engine without the command is refused.** The sprintshow rig checkout can
lag sprintshow's main, and the published package is not on npm (ss-rck). So
before a command runs or GitHub renders anything, `demo-screenshot.sh` reads
the engine's own `sprintshow help`. An engine whose help lists no
`sprintshow screenshot` stops the capture with exit 1 and a message naming the
engine. A help that fails is reported as a CLI that did not run, with its
error.

**One engine policy for both captures.** The arch review at fb0bd76f found
that the screenshot had copied the video's engine lookup, package-name guard,
dependency install and browser provisioning, so a fix to any of them needed the
same edit in two scripts (finding tk-xrxhtxy). `assets/scripts/demo-engine-lib.sh`
is the one definition of that policy, and both captures source it. Once both
captures ran the engine's CLI, the library took that over too
(`demo_engine_cli`). A checkout's CLI runs under node from its TypeScript
source, as the engine's own package scripts run it. The video had run it
through `npx tsx`, and tsx is not an engine dependency, so npx resolved it
against the registry on every call, at 5 to 7 s a call on this host against
1.3 s under node. The library holds Node to the engine's floor of 22.18 before
anything is installed, for both captures. Each capture keeps what only it
needs. The video fetches ffmpeg for a checkout and records a clip with the
CLI's `run`. The screenshot reads the CLI's help for `screenshot` and saves a
PNG with it. `demo-engine-lib.test.sh` checks the policy through both captures.
It fails when either capture stops sourcing the library, stops running the
engine through it, or runs one of its steps itself. It also fails when any
other script in `assets/scripts` finds the engine, provisions its browser,
reads Node's version or names the CLI's entry. The finding named the two
scripts. `skills/demo-capture/SKILL.md` still spells its own steps out for an
agent working the engine by hand at a shell.

**Terminal output.** The command runs with bash from `--cwd`, with stdout and
stderr captured together and stdin closed. Its exit status is reported, not
judged, because a failing command can still print the surface. The renderer
keeps ANSI SGR colour and weight, drops every other escape, keeps what a
carriage return's last redraw shows, honours tab stops, wraps at `--columns`
(default 120), and cuts at `--max-lines` (default 200) with a line that counts
what it hid.

**Markdown through GitHub's own renderer.** GitHub's markdown API, in gfm mode
with the rig's origin as context, returns the HTML GitHub renders: collapsed
`<details>`, tables, task lists, and linked `#123` and `@name` references. The
renderer draws that HTML in a comment box with GitHub's comment styles. An
alert (`> [!NOTE]`) placed inside a `<details>` came back as a plain
blockquote, while the same alert at the top level came back as alert markup.
GitHub does not render an alert nested in another element, on github.com
either, so the API's HTML is drawn as it stands. `--expand` opens every
`<details>`.

**A comment github.com finishes in the browser is refused.** The API's HTML is
not the finished comment for every block. The correctness review at 903b29df5
(finding tk-xf1prdl) captured a mermaid fence: the capture exited 0, and its PNG
showed the fence's source and a "Loading" spinner where github.com draws the
diagram. A mermaid, geojson, topojson or stl fence comes back as a section
marked `js-render-needs-enrichment` that holds the fence's source and the
spinner, and math comes back as its TeX inside a `<math-renderer>`. github.com's
page script finishes both. Finishing them here is not possible as GitHub does
it: the section names its renderer at viewscreen.githubusercontent.com, whose
content security policy (`frame-ancestors 'self' https://github.com
https://*.github.com`) lets no local page frame it. Drawing the diagram or the
math with another library would show what that library draws, not what GitHub
shows. So the renderer refuses a comment holding such a block. It exits 1,
writes no page, and names each block, and the review takes the fallback its
method gives for a surface none of these captures renders. The refusal covers
every section carrying the enrichment marker, whatever its type, and every
custom element except the two wrappers GitHub's renderer puts around markup
that draws on its own: `markdown-accessiblity-table` (GitHub's spelling) around
a table, and `themed-picture` around a picture. A block GitHub finishes with a
script it adds later is refused too, not drawn unfinished. A block inside a
collapsed `<details>` is refused as well, because the same comment captured
with `--expand` would show it. `docs/architecture.md` and
`docs/state-machine.md` carry mermaid fences, so a demo review that captures
either one rendered reaches the refusal.

**A port of the capture's own.** The engine serves a `--serve-dir` on a free
port unless `--port` names one, so reviews capturing side by side on one host
never share a server. The engine used to listen on 5173 for every one of them,
and the first build probed for a free port itself until ss-pc8t moved the
choice into the engine. That server listens on every network interface while a
capture runs (ss-tbv5, open in sprintshow). An app page served with
`--serve-dir` was already exposed that way. A terminal or markdown page is now
exposed too, on its random port, for the seconds its capture takes.

**This rig's surfaces.** gc-toolkit now carries `docs/review-demo.md`, which the
dispatch note appends to every demo review here. It names this rig's surface of
each kind and how to capture it without touching the live city. The helm board
is served from the reviewed commit's committed build with fixture files at the
paths it reads, because a running helm service's verbs file, dispatch and close
visits for real.

## Proof

These captures ran through `demo-screenshot.sh` on the macOS host, through the
engine's screenshot command, on the local sprintshow engine at b8f9a45
(Playwright 1.63.0, `chromium_headless_shell-1243`). Each PNG was opened and
judged. With the browser's provisioning included, the engine sample's page
capture took 7 s and the `git log` terminal capture 4 s.

| Surface | Kind | Exit | What the PNG showed |
|---|---|---|---|
| The helm board: the reviewed commit's build, served with `board.fixture.json` as `helm` | page | 0 | The viewport: the board's header, its owed summary, pack builds and anchors table, rendered from the fixture with no service running (2560x1800 px). |
| PR 1240's held dismiss: its build at f02847d2, the fixture board at `helm/index.html`, a held answer at `helm/dismiss` | page, one click on Dismiss, `--selector .drill-conversation` | 0 | "Dismiss is held" with the gate's question, Resolve, Leave open, and a disabled Confirm dismissal (2396x152 px). |
| PR 1243's report: `assets/scripts/gc-helm.sh unplaced`, run against the live city | terminal | 0 | Fifty-one unplaced beads, tab-aligned and wrapped at 120 columns, after the `$` prompt, captured whole though it runs far past the viewport (1948x5096 px). |
| `git log --oneline --decorate -8 origin/main` with colour forced | terminal | 0 | The hashes in yellow and the ref names in red and green, as git coloured them, in a window titled gc-toolkit (1948x876 px). |
| A triage verdict written by hand in the shape PR 1251's summary describes | markdown, then `--expand` | 0, 0 | The first line, two collapsed `<details>` blocks and the anchor line; expanded, the table and the trail inside them, with `#1266` linked (1604x408 px, 1604x708 px). |
| The engine's sample app, its own demo script, and again with its last assertion made false | page, `--selector '#board'` | 0, 3 | The board reading "3 tasks · 1 done"; the second run counted the one step that asserted 2 done as failed (1280x658 px each). |
| The engine at 0368d41, before its screenshot command, standing in as the rig checkout | terminal | 1 | No PNG. The message named the engine that lacks the command, and the command it was given did not run. |
| A comment holding one mermaid fence, `graph LR` with `A[Claim work] --> B[Review]`, at 903b29df5 and again with the refusal | markdown | 0, 1 | At 903b29df5, the fence's source and a "Loading" spinner where github.com draws the diagram (1604x276 px). With the refusal, no PNG, and the message named the block: mermaid (1). |
| A comment of ordinary markup with the refusal in place: a heading, a table, a task list, an emoji, an @mention, two `#` references, a footnote, an alert, a collapsed `<details>` and a code fence | markdown, `--title` | 0 | Each drawn as GitHub returned it, the table inside GitHub's wrapper element and both references linked (1604x1424 px). |

After the library took over the engine's CLI, a proof-mode clip of the engine's
sample app ran through `rig-demo-capture.sh` on it: six steps held, and a
silent 33.6 s clip at 1280x900 was written.

`demo-screenshot.test.sh` runs the script's cases under `env -i` with stubs for
node, npm, gc and gh. Its node stub hands the checkout's CLI to an engine stub,
and its renderer cases import `demo-screenshot.mjs` into a real node. Each
mutant of the script or its renderer turned it red. The mutants dropped the
help probe or moved it after the command runs, ignored a help that failed,
dropped `--transparent` or `--scale 2`, drew a page transparent, served a page
other than the renderer's, dropped the surface's proof or its `id`, printed from
the renderer, ignored a renderer that failed, read exit 3 as a failure, and
dropped the stale-PNG removal. The first build's mutants still turn it red: an
open stdin, a lost stderr, a greedy `--expand`, a missing repository context,
and a carriage return that ends a line read as an empty redraw.

The refusal's cases run on HTML GitHub's markdown API returned, kept verbatim
in the suite: a mermaid section, the opening tags of the geojson, topojson and
stl sections, math inline and on lines of its own, and markup that draws on its
own (GitHub's table and picture wrappers, an issue link, and code that names
the markers as text). The suite also runs the script end to end on that HTML,
its node stub handing the renderer to a real node. The mermaid comment exits 1
with nothing captured, and the ordinary one is drawn and captured. Each mutant
of the refusal turned it red. The mutants dropped the refusal, refused only under
`--expand`, dropped the math check or the section's type, drew every custom
element, refused only mermaid, matched a marker in the comment's text, dropped
either wrapper from the elements drawn from their markup, dropped the counts
from the message, and ignored a renderer that failed.

`demo-engine-lib.test.sh` runs the shared engine policy through both captures,
under the same kind of stubs. Each mutant turned it red. The mutants put the
library's runner back on `npx tsx`, dropped the Node floor, lowered it to 22.0,
checked it only after a browser install, gave the video a runner or a node
check of its own, and gave the screenshot a published-package runner of its
own. Of the mutants made when the library was extracted, a dropped package-name
guard, an installer writing to stdout and a dropped npx check still turn it
red, and `rig-demo-capture.test.sh` still catches a dropped ffmpeg fetch.

**Not proven live: the attach.** No PNG has been attached to a real PR in this
city. `demo-deliver.sh` is unchanged, and the gh on this host (2.102.0)
documents `--attach` for images: an attached file the body does not reference is
appended to the comment inline, with the file's name as its alt text. The first
engaged review that picks a screenshot makes the first live attach, as the
video modality's does for a clip.

## What a review session needs

- Node 22.18 or later, and the sprintshow rig checkout at a commit whose
  `sprintshow help` lists `sprintshow screenshot`, with its `node_modules`. The
  published package is not on npm (`npm view @zookanalytics/sprintshow`
  answered 404), so the npx fallback the two captures share works only once a
  release with the screenshot command is published.
- gh, for the markdown kind's renderer and for delivery.
- No ffmpeg and no `OPENAI_API_KEY`.
- The browser's provisioning runs on every capture, and skips a build that is
  already installed.
