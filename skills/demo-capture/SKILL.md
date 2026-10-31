---
name: demo:capture
description: Records a narrated, captioned MP4 demo of a rig's app with the SprintShow engine — a demo-script drives the browser, each step is proof-checked against the live DOM, and ffmpeg assembles the clip
---

# Demo Capture (SprintShow engine)

Produce a narrated, captioned MP4 that **proves features work** — each step is
checked against the live DOM, so the video shows verified behaviour, not a
screen tour.

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
read none of the city's stores, configuration or API; the library's header says
what the sandbox denies and what it refuses. Source it from the pack gc loaded
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
demo_engine_cli run demo.md --serve "npm run dev" --port 5173   # spin up a dev server, tear it down
demo_engine_cli run demo.md --base-url https://<preview-host>   # drive a deployed preview
```

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
  ( --serve-dir <dir> | --serve "<cmd>" | --base-url <url> ) [--mode proof] [--no-narrate]
```

`mol-rig-demo` runs that call as a pool workflow against any rig. It turns the
scenario into a script (a ready one, or one written from a bead with
`gc-demo-script`), captures, delivers the clip to a PR or records its path, and
closes the bead it was poured on. `gc formula show mol-rig-demo` prints the
pour line and every input. A pour must set exactly one app target
(`serve_dir`, `serve_cmd`, or `base_url`), because nothing in the toolkit maps
a rig to its app. The `demo` review check makes the call inside the review
instead of pouring the mol (`gc-toolkit.review-demo`).

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
`README.md`. Read it in the engine the library resolves, so the script you
write is one that engine reads. After `demo_engine_find`, that README is
`$DEMO_ENGINE_DIR/README.md` when the city has the engine's source as a rig,
and the one the published package ships otherwise. The engine's
`demos/sample.md` is a worked example.

The `gc-demo-script` skill writes a script in the generic `demo:capture`
dialect from a Gas City bead. The README's format section says how the engine
reads that dialect and how such a script is sharpened.

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
