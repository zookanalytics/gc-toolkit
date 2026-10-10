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

Consume the engine from the local `sprintshow` rig checkout when the city has
one, and fall back to the published npm package otherwise. Both are driven the
same way once resolved.

```bash
# Prefer the local rig checkout; the guard confirms it is the engine before use.
SS_DIR=$(gc rig list --json 2>/dev/null | jq -r '.rigs[] | select(.name=="sprintshow") | .path // empty')
if [ -n "$SS_DIR" ] && [ "$(jq -r '.name // empty' "$SS_DIR/package.json" 2>/dev/null)" = "@zookanalytics/sprintshow" ]; then
  # First use installs the engine's deps (playwright, ffmpeg-static). The host
  # has npm but not pnpm, so run the TypeScript source through `npx tsx` — no
  # build step, and an absolute path to cli.ts means the caller's cwd stays put
  # so relative demo-script and --serve-dir paths resolve as written.
  [ -d "$SS_DIR/node_modules" ] || ( cd "$SS_DIR" && npm install )
  # A host ffmpeg on PATH is used when present; otherwise fetch ffmpeg-static's
  # binary once (npm >= 12 blocks its automatic install script).
  command -v ffmpeg >/dev/null 2>&1 || [ -x "$SS_DIR/node_modules/ffmpeg-static/ffmpeg" ] || ( cd "$SS_DIR" && npm run provision:ffmpeg )
  sprintshow() { npx tsx "$SS_DIR/src/cli.ts" "$@"; }
else
  # Any-rig path: the published package, run through npx.
  sprintshow() { npx --yes @zookanalytics/sprintshow "$@"; }
fi
```

## Lint before you capture

A script can parse and run yet capture nothing worth watching. Lint it first —
the linter reads a script exactly as the driver will and reports what the
driver would silently ignore:

```bash
sprintshow lint demo.md          # --strict makes warnings non-zero
```

## Capture — the engine drives (default)

Point the engine at the app and let it drive the browser, check each step, and
assemble the MP4:

```bash
sprintshow run demo.md --serve-dir ./public          # serve a static directory
sprintshow run demo.md --serve "npm run dev" --port 5173   # spin up a dev server, tear it down
sprintshow run demo.md --base-url http://localhost:3000    # drive a server already running
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
engine, lint, capture) as one call. It exits non-zero when anything stops the
capture, including a run that leaves no MP4 behind. It carries no bead or
routing logic, so a shell and a formula step drive it the same way. Its
`--help` lists every flag:

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
a rig to its app.

## Capture — you drive over Playwright MCP

When the session is demo-gated and carries the `playwright` MCP server (the
`demo` agent's `agents/demo/mcp/playwright.toml`), an agent can drive the
browser itself: screenshot each
step into a captures directory with a `manifest.json`, then hand the frames to
the engine to assemble. This is the Gas City path, where the agent already
holds the browser.

```bash
sprintshow assemble .captures/agent-run -o demos/board.mp4
```

`manifest.json` is the contract `assemble` reads — one entry per frame with
`file`, `narration` (the caption and the spoken line), `duration`, optional
`observation`, `proof` (`passed` | `adapted` | `failed`), and `severity`
(`error` | `warning` | `null`). The engine's `examples/agent-mcp/` documents
the manifest shape and the MCP wiring; `examples/seed-test/` shows the
seed-test bootstrap for a demo that first needs a login or seeded data.

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
machine-checkable directives, so one file both documents and drives the demo:

```markdown
# Demo: <title>

**Start:** `/path?query`          ← joined onto the server origin

<free prose → the cover subtitle>

## Steps

1. **<caption shown on screen, spoken as narration>**
   `<action>`                     ← 0+ backtick directives, run in order
   <free prose → step description>
   _Prove:_ <human prose> `<assertion>`
   _Fail if:_ <human prose> `<assertion>`

## Scrutiny                        ← optional; a closing card
- <what a viewer should check critically>
```

Actions: `goto` · `wait <ms>` · `waitFor <selector>` ·
`waitForText <selector> ~ <substring>` · `click <selector>` ·
`type <selector> ~ <text>` · `scroll <selector>`. Assertions (in `_Prove:_` /
`_Fail if:_`): `visible` · `hidden` · `count <sel> <op> <n>` · `text <sel> ~
<matcher>` · `eval <js>`. `_Prove:_` must hold (polled); `_Fail if:_` fails the
step when it matches.

A script drafted in the generic `demo:capture` dialect — an `**Auth:**` line, a
`## Scrutiny` section, and prose-only `_Prove:_`/`_Fail if:_` — parses and runs
unedited, recording *manual* proofs; sharpening it is additive (add actions and
assertions, never restructure). The `gc-demo-script` skill generates a script
in this dialect from a Gas City bead. The engine's `demos/sample.md` is a
worked example, and its `README.md` is the full format reference.

## Narration

With `OPENAI_API_KEY` set, each step is voiced (`tts-1`/`nova`; override with
`DEMO_TTS_MODEL` / `DEMO_TTS_VOICE`) and mixed in. Without a key — or on any
synthesis failure — the MP4 is silent and captioned. Narration is best-effort
and never breaks the video.

## Toolchain

The capture needs Node ≥ 22.18, a Chromium build, and ffmpeg; narration also
needs `OPENAI_API_KEY`. Each is fetched on demand rather than assumed:

- **Chromium** — `npx playwright install chromium-headless-shell` (add
  `--with-deps` on a bare host). A host-provided browser is used when present.
- **ffmpeg** — a host `ffmpeg` on `PATH` (or `FFMPEG_BIN`) is used when present;
  otherwise the engine's bundled `ffmpeg-static` provides it.
- **`OPENAI_API_KEY`** — read from the environment; the host places it in
  `~/.gc/secrets.env`, merged into the session environment.

The `doctor/check-demo-toolchain` check reports which of these are resolvable,
so a session knows before it captures whether the clip will be narrated or
silent, and whether the browser and ffmpeg are in place.
