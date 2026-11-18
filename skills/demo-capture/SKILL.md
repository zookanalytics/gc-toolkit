---
name: demo:capture
description: Use when you need to record a narrated, captioned video demo (an MP4) of a rig's app from a demo script, demo a PR, or write the demo guide a rig keeps in its docs/review-demo.md or the start command it declares for its app.
---

# Demo Capture (SprintShow engine)

Produce a narrated, captioned MP4 that **proves features work** — each step is
checked against the live page or terminal, so the video shows verified
behaviour, not a screen tour.

The work is done by the `sprintshow` engine (`@zookanalytics/sprintshow`,
AGPL-3.0): a markdown demo-script DSL and linter, browser driving over
Playwright, on-screen step captions, optional OpenAI TTS narration, and ffmpeg
assembly into an MP4. This skill resolves the engine and shells out to it; it
carries no capture, encode, or narration code of its own.

## Resolve the engine

The pack's `demo-engine-lib.sh` resolves the engine, and the pack's own
captures source it too. It uses the local `sprintshow` rig checkout when the
city has one and the published npm package otherwise. It holds Node to the
engine's floor of 22.18, installs a checkout's dependencies on first use, and
provisions the browser. It runs the engine inside a sandbox from which the
live city cannot be reached, so a server the capture starts and a page it loads
read none of the city's stores, configuration or API.
[The sandbox's page](../../docs/demo-capture-sandbox.md) says what it guarantees
and what it lets through, and the library's header says what it denies and what
it refuses. Source it from the pack gc loaded
and resolve the engine once. A video also needs ffmpeg, which the library
leaves to the capture that assembles one:

```bash
. "$(gc <binding> scripts-dir)/demo-engine-lib.sh" && demo_engine_resolve && {
  # A host ffmpeg on PATH is used when present; otherwise a checkout fetches
  # ffmpeg-static's binary once (npm >= 12 blocks its automatic install script).
  [ -z "$DEMO_ENGINE_DIR" ] || command -v ffmpeg >/dev/null 2>&1 \
    || [ -x "$DEMO_ENGINE_DIR/node_modules/ffmpeg-static/ffmpeg" ] \
    || ( cd "$DEMO_ENGINE_DIR" && npm run provision:ffmpeg )
}
```

`<binding>` is the name the city imports the pack under, which gc puts in
front of this skill's name: `gc-toolkit` in `gc-toolkit.demo-capture`.
`gc skill list` prints it in this skill's FROM column.

`demo_engine_cli <command> <arguments...>` runs the engine's CLI inside the
sandbox, in the current directory, so relative demo-script and `--serve-dir`
paths resolve as written. An app that reads the city fails there, so point the
capture at an app that serves fixture data.
Each tool call starts a fresh shell, which has neither the library nor the
engine it chose. So each engine command below runs after sourcing the library
again and calling `demo_engine_find`, which finds the same engine and installs
nothing:

```bash
. "$(gc <binding> scripts-dir)/demo-engine-lib.sh" && demo_engine_find && demo_engine_cli <command> <arguments...>
```

## The rig's demo guide

A rig says how to demo it in one file, `docs/review-demo.md`, and the demo
paths read it at the commit the demo shows: the `demo` review check, the drafter
`gc-toolkit.gc-demo-script`, which `mol-rig-demo` runs, and
[Demo a PR](#demo-a-pr). The guide is plain text for whoever writes and captures
a script, and no script reads lines out of it. A rig that keeps none is demoed
in the generic shape each path falls back to.

The guide holds these sections, under these headings, so that every path finds
the same thing in the same place:

- `## Surfaces`: each surface a person sees, such as a page, a terminal
  session, markdown the rig posts or a message its app sends, and the files
  that draw it.
- `## Bring the app up`: what the rig's
  [start command](#the-rigs-start-command) serves, and what a capture needs
  beyond it, such as how long the app takes to start, the directory a terminal
  session's commands run in, or how to capture an app the command does not
  serve.
- `## A known state`: how a script puts the app in a known state, such as the
  start path a page script opens on, and the fixture data, seed or scenario
  behind it.
- `## Sign-in`: how a script signs in, or that the app has none.
- `## Worked examples`: scripts and captures the rig keeps, to copy from.

A rig adds sections of its own, such as the design and writing standards the
`demo` check reviews screens against, or how a run shows the messages its app
sends. gc-toolkit's own `docs/review-demo.md` is a worked example of a guide.
Every path reads the guide at the commit it shows, as the pack reads all of a
rig's review guidance, so an edit to the guide counts once it is committed.

## The rig's start command

A rig declares the command that starts its app as `ui_serve_command`, among its
`[rigs.formula_vars]` in the town's `city.toml`, beside its check commands. A
capture of the rig's own app runs it, from `mol-rig-demo`, the `demo` check or
[Demo a PR](#demo-a-pr), and so does a sitting's live copy of the rig's UI. Each
reads it for the rig and passes it on, a capture as
`--serve "$SERVE" --cwd <worktree>`:

```bash
SERVE=$(gc formula show mol-rig-demo --rig <rig> --json | jq -r '[.vars[]? | select(.name == "ui_serve_command")][0].rig_default // empty')
```

`SERVE` is empty for a rig that declares none. A page capture of such a rig
names its app as the guide's `## Bring the app up` says, with `--serve-dir` or
`--base-url`. A terminal script brings up no app, so it takes no start command.

The command runs as a copy that `gctk rig serve` runs, with bash at the top of
the checkout it is started from, such as a worktree at the commit a capture
shows, inside the capture's sandbox. The copy gets a free loopback port of its
own as `$PORT`. It is up once it answers there, or once the command prints the
URL of the app it brought up on a line of its standard output, in the engine's
form, as `ios-simulator://<device UDID>/<bundle id>` names an iOS app it
launched on a simulator. A capture hands the engine the app where the copy
reports it.

An app that runs as several local processes, such as a web server and the
database server it starts beside it, gets a loopback port for each of its other
servers. The city gives the rig how many as `ui_serve_extra_ports`, beside
`ui_serve_command` among its `[rigs.formula_vars]` in `city.toml`, and the copy
gets them as `$PORT_1`, `$PORT_2` and on, free ports `gctk rig serve` picks
before the command starts. Inside the sandbox the app's processes reach one
another on those ports and on `$PORT`, and on no other loopback port, and a
capture's browser reaches each of them too. The copy's `$TMPDIR` is a directory
of its own, which goes with the copy, and the app's processes may connect to
the Unix sockets they open under it, and to no other. So the command:

- changes into the app's directory and installs what it needs, because a
  capture's worktree holds only what the rig commits;
- serves on `$PORT`, so a dev server whose config pins a port takes `$PORT` on
  its command line, such as `cd web && npm ci && npm run dev -- --port $PORT`,
  or prints its app's URL once the app is ready, with its other output on its
  standard error;
- starts each of its app's other servers on one of `$PORT_1` and on, and tells
  each part of the app where the others listen, such as the database server's
  URL the web server and the page connect to. It listens on every one of them,
  because the copy is up only once each has a listener of the app's own;
- hard-codes no port, because each run gets ports of its own;
- keeps a Unix socket its processes connect to under `$TMPDIR`, the one place
  the sandbox lets them connect to one;
- serves the app on fixture data, because the sandbox keeps the live city out
  of reach. An iOS app runs on a simulator, which the system's simulator
  service starts outside the sandbox, so the command gives it fixture data
  itself;
- builds with its toolchain's own sandboxes turned off, because none can start
  inside the capture's, which still holds the build. An Xcode build passes
  `-IDEPackageSupportDisableManifestSandbox=YES` for Swift packages and
  `'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'` for Swift macros;
- is up within ten minutes, as long as a start waits before it stops the copy,
  then runs until it is stopped, and ends within a minute of that, removing
  what it made outside the checkout, such as its simulator device;
- runs a program the repository keeps, so a run starts the app of the commit
  it runs from, as a rig's test command runs the tests of its commit. The rig
  declares one command for all its branches, so it names an entry point every
  branch carries.

## Lint before you capture

A script can parse and run yet capture nothing worth watching. Lint it first —
the linter reads a script exactly as the driver will and reports what the
driver would silently ignore:

```bash
demo_engine_cli lint demo.md          # --strict makes warnings non-zero
```

## Capture — the engine drives (default)

Point the engine at the app and let it drive the browser, check each step, and
assemble the MP4:

```bash
demo_engine_cli run demo.md --serve-dir ./public          # serve a static directory
demo_engine_cli run demo.md --base-url https://<preview-host>   # drive a deployed preview
demo_engine_cli run terminal.md --cwd .                   # a terminal script: no app, its shell starts in --cwd
```

A script that declares `**Terminal:**` drives a bash session in the engine's own
terminal instead of a page, so it brings up no app, and the engine refuses an
app target or a `--port` for it.

An app a command serves, such as a dev server, runs as a copy that
`gctk rig serve` runs from a checkout, inside the same sandbox, and the engine
captures the copy's app where the copy reports it. `rig-demo-capture.sh` and
`demo-screenshot.sh page` do that for `--serve "<command>" --cwd <checkout>`:
they start the copy, capture it and stop it. The engine's own `--serve` is
refused, because the sandbox cannot vouch for the server it would start.

A `--base-url` on this host works for a copy that `gctk rig serve` runs, and for
a rig's own app running in a worktree of that rig, unless `city.toml` sets
`app_reads_city = "true"` for the rig. Otherwise the capture refuses the URL and
says why. Then serve the app as a copy or with `--serve-dir`, or capture a
deployed preview.

A script that declares `**Platform:** iOS` drives an iOS app on a simulator,
named by its `ios-simulator://<device UDID>/<bundle id>` URL as `--base-url`,
or brought up by a rig's start command. Its capture provisions the Appium the
engine drives the app with, and opens three loopback ports, which the engine
gets as `--port`, for the servers it drives the app through. The app itself
runs outside the sandbox, where the system's simulator service starts it.

Two capture modes come from one script:

- **walkthrough** (default) — one continuous recorded take at a human pace with
  a synthetic cursor and live captions. The watchable cut.
- **proof** (`--mode proof`) — one screenshot per step, each with its assertion
  checked and its caption burned in. Deterministic and frame-exact; the shape
  an agent produces when it drives the browser itself.

The MP4 lands at `demos/<script-name>.mp4` by default (`-o` to override). Other
flags: `--no-narrate`, `--music <file>`, `--keep` (keep the `.captures/<run>/`
working dir), `--headed`. Write the output to a path outside the pack's tracked
tree — a demo MP4 is an artifact, not a committed file, and the engine warns
when the output path is not covered by an LFS filter.

## One-call capture and the rig-demo mol

`assets/scripts/rig-demo-capture.sh` runs the three steps above (resolve the
engine, lint, capture) as one call. It exits 1 when anything stops the capture,
including a run that leaves no MP4 behind, and 3 when it recorded a clip in
which at least one step failed its proof. Its last line names the clip and says
whether it is narrated. It carries no bead or routing logic, so a shell and a
formula step drive it the same way. Its `--help` lists every flag:

```bash
assets/scripts/rig-demo-capture.sh --script demo.md --output <out.mp4> \
  [ --serve-dir <dir> | --serve "<cmd>" | --base-url <url> ] [--mode proof] [--no-narrate]
```

A page script needs its app, named with one of the three flags, such as
`--serve "$SERVE" --cwd <worktree>` for the rig's
[start command](#the-rigs-start-command). A terminal script takes none of them,
and its shell starts in `--cwd`. `mol-rig-demo`, the `demo` check and
[Demo a PR](#demo-a-pr) each give a terminal script the root of the worktree
they capture from, so one script runs alike on all three. A script whose
commands run in a directory below the root, which the rig's guide names,
changes into it in its first step, as `run cd <dir>`. A `--serve` command runs
as a copy on a free port of its own, which it gets as `$PORT`, with the ports
beyond it the city gives the rig as `$PORT_1` and on, as a screenshot's command
does.

`mol-rig-demo` runs that call as a pool workflow against any rig. It turns the
scenario into a script (a ready one, or one written from a bead with
`gc-demo-script`), captures, delivers the clip to a PR or records its path, and
closes the bead it was poured on. `gc formula show mol-rig-demo` prints the
pour line and every input. A pour names at most one app target (`serve_dir`,
`serve_cmd`, or `base_url`), and a page script whose pour names none takes the
rig's start command. The sandbox refuses a rig's own checkout, so the app runs
from a detached worktree of it at its HEAD, which holds only what the rig
commits.
The `demo` review check makes the call inside the review
instead of pouring the mol (`gc-toolkit.review-demo`).

## Demo a PR

To show what a PR changes, draft a script from its bead, adapt the draft to the
rig's guide, lint it, capture it, and attach the clip to the PR. The script and
the clip are working files, and neither is committed.

1. **Work from a worktree at the PR's head.** The capture's sandbox refuses a
   rig's own checkout, so make a worktree outside it, at the commit the PR
   heads:

   ```bash
   git -C <checkout> worktree add --detach <worktree> <pr-head>
   ```

   Do there what the guide's `## Bring the app up` says the app needs before
   its command runs. This reports whether the session can narrate a clip,
   assemble it and attach it:

   ```bash
   gc doctor --check <binding>:check-demo-toolchain
   ```

2. **Draft from the bead.** Follow `gc-toolkit.gc-demo-script` on the PR's bead,
   with `--pr <number>`, reading the guide in the worktree. It writes the
   draft's surfaces, start state and sign-in from the guide.
3. **Adapt the draft to the guide.** Adapting is additive. Keep the draft's bold
   captions, which the clip shows and speaks, and its `## Scrutiny`. Add what a
   draft cannot know: the start state that `## A known state` names, the steps
   `## Sign-in` gives, the actions that drive each step, and a machine assertion
   on each `_Prove:_`, and on each `_Fail if:_` that can carry one. The
   assertion is what makes a step prove its caption instead of showing a
   screen. The engine's README gives the grammar, in its "Demo-script format"
   section for a page and its "Terminal demos" section for a terminal, and the
   guide's `## Worked examples` show it on this rig's app.
4. **Lint it** as [Lint before you capture](#lint-before-you-capture) says, and
   fix what it reports. Its warning that no LFS filter covers the MP4 does not
   apply, because the clip is never committed. The linter cannot check a name
   the app defines, such as the scenario a start path arms, so check each one
   against the source the guide names.
5. **Capture it** from the worktree's root, writing the clip outside the
   worktree. A page script takes the rig's
   [start command](#the-rigs-start-command), read into `SERVE` as that section
   shows:

   ```bash
   "$(gc <binding> scripts-dir)/rig-demo-capture.sh" --script <script.md> --output <clip.mp4> --serve "$SERVE" --cwd .
   ```

   On a rig that declares no start command, name the app as the guide's
   `## Bring the app up` says instead. A terminal script takes `--cwd .` alone,
   the worktree's root. When that section says its commands run in a directory
   below the root, the script's first step changes into it, as the draft's
   does. Exit 0 is a clip in which every step's proof held. Exit 3 is a clip in
   which a step failed its proof. Read which step failed and whether the
   change or the script is wrong. Correct a wrong script and capture again, and
   report a change that fails instead of attaching the clip as its demo. Exit 1
   is no clip, exit 2 is a call the capture refused, and the output says why.
6. **Attach it to the PR:**

   ```bash
   "$(gc <binding> scripts-dir)/demo-deliver.sh" --file <clip.mp4> --pr <number> --body "<what it shows, and the commit it was captured from>"
   ```

   [Deliver to the PR](#deliver-to-the-pr) says what the attachment is.

Name the script and the clip for the bead, `<bead-id>-<slug>.md` and
`<bead-id>-<slug>.mp4`, so that a bead leads to its demo. Once the clip is
attached, remove the worktree:

```bash
git -C <checkout> worktree remove <worktree>
```

## Capture — you drive over Playwright MCP

When the session is demo-gated and carries the `playwright` MCP server (the
`demo` agent's `agents/demo/mcp/playwright.toml`), an agent can drive the
browser itself: screenshot each
step into a captures directory with a `manifest.json`, then hand the frames to
the engine to assemble. This is the Gas City path, where the agent already
holds the browser. That browser is the session's own, outside the sandbox the
engine runs in, so it reaches whatever the session reaches, the live city
included. Point it only at an app that serves fixture data.

```bash
demo_engine_cli assemble .captures/agent-run -o demos/board.mp4
```

`manifest.json` is the contract `assemble` reads. The engine's
`examples/agent-mcp/` documents its shape and the MCP wiring, and
`examples/seed-test/` shows the seed-test bootstrap for a demo that first needs
a login or seeded data.

## Deliver to the PR

When the demo is for a PR, producing the MP4 is not the end — a clip left in a
scratch path is gone by review time. Attach it to the PR inline and uncommitted:

```bash
assets/scripts/demo-deliver.sh --file demos/board.mp4 --pr <number>
# or resolve the PR from the work bead that owns it:
assets/scripts/demo-deliver.sh --file demos/board.mp4 --subject <bead-id>
```

`demo-deliver.sh` runs `gh pr comment <pr> --attach <file>`, which uploads the
clip to GitHub's user-attachments CDN and renders it as an inline player with no
browser step. A user-attachments URL is the only inline-playable path — a
committed file, a release asset, or an external URL renders as a link — so the
clip stays out of the repo tree and still plays on the PR. It pins the write to
the rig's own origin and fails closed: a missing or too-old gh (the floor is
2.99.0, which `doctor/check-demo-toolchain` probes), a foreign PR, or a gh error
all exit non-zero rather than leaving the clip undelivered.

## Demo-script format

A demo script is markdown that reads as a walkthrough and carries
machine-checkable directives, so one file both documents and drives the demo.
The engine documents the format in the "Demo-script format" section of its
`README.md`, and a terminal script's in its "Terminal demos" section. Read them
in the engine the library resolves, so the script you write is one that engine
reads. After `demo_engine_find`, that README is `$DEMO_ENGINE_DIR/README.md`
when the city has the engine's source as a rig, and the one the published
package ships otherwise. The engine's `demos/sample.md` is a worked example.

The `gc-demo-script` skill drafts a script from a Gas City bead, against the
rig's guide when the rig keeps one and in the generic `demo:capture` dialect
otherwise. The README's format section says how the engine reads that dialect
and how such a script is sharpened.

## Narration

With `OPENAI_API_KEY` set, each step is voiced (`tts-1`/`nova`; override with
`DEMO_TTS_MODEL` / `DEMO_TTS_VOICE`) and mixed in. Without a key — or on any
synthesis failure — the MP4 is silent and captioned. Narration is best-effort
and never breaks the video.

## Toolchain

The capture needs Node ≥ 22.18, a Chromium build, and ffmpeg; narration also
needs `OPENAI_API_KEY`. Each is fetched on demand rather than assumed:

- **Chromium** — the capture fetches it on demand. It installs the
  `chromium-headless-shell` build through the engine's own Playwright, so the
  build it installs is the one the engine launches, and Playwright's installer
  skips a build that is already installed. The capture does not install the
  browser's system libraries. On a bare Linux host, install them once with
  `npx playwright install-deps chromium-headless-shell`.
- **ffmpeg** — a host `ffmpeg` on `PATH` (or `FFMPEG_BIN`) is used when present;
  otherwise the engine's bundled `ffmpeg-static` provides it.
- **`OPENAI_API_KEY`** — read from the environment. The host places it in
  `$GC_HOME/secrets.env` (`~/.gc/secrets.env` when `GC_HOME` is unset), and
  gascity copies it into the supervisor's service env when
  `gc supervisor install` writes that env, as it does any key with an
  AI-provider prefix. Sessions started after that carry the key.

The `doctor/check-demo-toolchain` check reports which of the others are
resolvable, so a session knows before it captures whether the clip will be
narrated or silent, and whether ffmpeg is in place. It also reports whether
`VERCEL_AUTOMATION_BYPASS_SECRET`, Vercel's Protection Bypass for Automation
key, reaches the session. That key is neither a provider credential nor on
gascity's short allowlist, so it reaches sessions from the secrets file only
when `GC_SUPERVISOR_ENV` names it, and the check names that opt-in when the
file holds the key and the session does not.
