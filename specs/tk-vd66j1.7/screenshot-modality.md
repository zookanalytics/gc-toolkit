---
name: Screenshot modality — what tk-vd66j1.7 decided
description: What tk-vd66j1.7 decided when it built the demo check's screenshot modality for three kinds of surface (an app page, a command's output, a rendered PR comment), why it drives the capture engine's own browser through a driver of its own, and the live captures that prove each kind on the macOS host.
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

**The engine's browser, through a driver of the pack's own.** The demo agent's
Playwright MCP launches Google Chrome, which this host does not have
(tk-qrga4h5). The SprintShow engine's Playwright launches the
chromium-headless-shell build that the video capture already provisions, so the
screenshot uses the same engine and the same browser. Two shorter paths were set
aside:

- The engine's proof mode burns a caption into each frame, assembles an MP4,
  which needs ffmpeg, and keeps its frames only when a step fails or `--keep`
  is passed.
- Playwright's own `screenshot` command cannot click, so it cannot reach a state
  like PR 1240's held dismiss, and it cannot crop to an element.

So `demo-screenshot.mjs` loads Playwright and the engine library from the engine
directory. For a page it uses the engine's script parser, server seam, action
runner and assertion checks. A page screenshot takes the script and the app
target a video takes, and checks the same proofs.

**One engine policy for both captures.** The arch review at fb0bd76f found
that the screenshot had copied the video's engine lookup, package-name guard,
dependency install and browser provisioning, so a fix to any of them needed the
same edit in two scripts (finding tk-xrxhtxy). `assets/scripts/demo-engine-lib.sh`
is now the one definition of that policy, and both captures source it. Each
capture keeps what only it needs. The video fetches ffmpeg for a checkout and
runs the engine's CLI. The screenshot holds Node to its driver's floor before
anything is installed, and runs its driver. `demo-engine-lib.test.sh` checks
the policy through both captures. It fails when either capture stops sourcing
the library or runs one of its steps itself, and when any other script in
`assets/scripts` finds the engine or provisions its browser. The finding named
the two scripts; `skills/demo-capture/SKILL.md` still spells the same steps out
for an agent working the engine by hand at a shell.

**Terminal output.** The command runs with bash from `--cwd`, with stdout and
stderr captured together and stdin closed. Its exit status is reported, not
judged, because a failing command can still print the surface. The driver keeps
ANSI SGR colour and weight, drops every other escape, keeps what a carriage
return's last redraw shows, honours tab stops, wraps at `--columns` (default
120), and cuts at `--max-lines` (default 200) with a line that counts what it
hid.

**Markdown through GitHub's own renderer.** GitHub's markdown API, in gfm mode
with the rig's origin as context, returns the HTML GitHub renders: collapsed
`<details>`, tables, task lists, and linked `#123` and `@name` references. The
driver draws that HTML in a comment box with GitHub's comment styles. An alert
(`> [!NOTE]`) placed inside a `<details>` came back as a plain blockquote, while
the same alert at the top level came back as alert markup. GitHub does not
render an alert nested in another element, on github.com either, so the API's
HTML is drawn as it stands. `--expand` opens every `<details>`.

**A port of the capture's own.** `--serve-dir` serves on a free port unless
`--port` names one. Reviews capture side by side on one host, and the engine's
default port is 5173 for every one of them.

**This rig's surfaces.** gc-toolkit now carries `docs/review-demo.md`, which the
dispatch note appends to every demo review here. It names this rig's surface of
each kind and how to capture it without touching the live city. The helm board
is served from the reviewed commit's committed build with fixture files at the
paths it reads, because a running helm service's verbs file, dispatch and close
visits for real.

## Proof

These captures ran through `demo-screenshot.sh` on the macOS host, with the
local sprintshow engine (Playwright 1.63.0, `chromium_headless_shell-1243`).
Each PNG was opened and judged.

| Surface | Kind | Exit | What the PNG showed |
|---|---|---|---|
| The helm board: main's build, served with `board.fixture.json` as `helm` | page | 0 | The viewport: the board's header, its owed summary, pack builds and anchors table, rendered from the fixture with no service running (2560x1800 px). |
| PR 1240's held dismiss: its build at f02847d2, the fixture board at `helm/index.html`, a held answer at `helm/dismiss` | page, one click on Dismiss, `--selector .drill-conversation` | 0 | "Dismiss is held" with the gate's question, Resolve, Leave open, and a disabled Confirm dismissal (2396x152 px). |
| PR 1243's report: `assets/scripts/gc-helm.sh unplaced`, run against the live city | terminal | 0 | Eleven unplaced beads, tab-aligned and wrapped at 120 columns, after the `$` prompt (1948x1132 px). The command took most of the run's 72 s. |
| A triage verdict written by hand in the shape PR 1251's summary describes | markdown, then `--expand` | 0, 0 | The first line, two collapsed `<details>` blocks and the anchor line; expanded, the table and trail inside them (1604x334 px, 1604x588 px). |
| The engine's sample app, its own demo script with one assertion made false | page, `--selector '#board'` | 3 | The board reading "3 tasks · 1 done" against a script that asserted 2 done (1280x658 px). |

`demo-screenshot.test.sh` runs the script's cases under `env -i` with stubs for
node, npm, gc and gh, and the driver's renderers in a real node. Each mutant of
the two scripts turns it red, among them a dropped stale-PNG removal, an open
stdin, a lost stderr, a skipped PNG check, a lost engine argument, a missing
repository context, a greedy `--expand`, a carriage return that ends a line
read as an empty redraw, and SGR sub-parameters read as parameters.

`demo-engine-lib.test.sh` runs the shared engine policy through both captures,
under the same kind of stubs. Each mutant made when the library was extracted
turned a suite red. The mutants dropped the package-name guard, skipped or
stopped checking the dependency install and either browser install, sent an
installer's output to stdout, and removed the npx check. They also made a
capture run one of the library's steps itself or define its own resolver, ran a
capture on the wrong engine, checked the screenshot's Node floor only after
installing, broke the video's ffmpeg fetch, and added a script that provisions
the browser on its own. A script that only names a provisioning command in a
comment stays green. After the extraction, two captures ran live through the
library on this host, both on the local engine checkout: a terminal screenshot,
and a proof-mode video of the engine's sample app, six steps held.

**Not proven live: the attach.** No PNG has been attached to a real PR in this
city. `demo-deliver.sh` is unchanged, and the gh on this host (2.102.0)
documents `--attach` for images: an attached file the body does not reference is
appended to the comment inline, with the file's name as its alt text. The first
engaged review that picks a screenshot makes the first live attach, as the
video modality's does for a clip.

## What a review session needs

- Node 22.18 or later, and the sprintshow rig checkout with its `node_modules`.
  The published package is not on npm (`npm view @zookanalytics/sprintshow`
  answered 404), so the npx fallback the two captures share works only once it
  is published.
- gh, for the markdown kind's renderer and for delivery.
- No ffmpeg and no `OPENAI_API_KEY`.
- The browser's provisioning runs on every capture. With the build already
  installed it took about 12 s on this host.
