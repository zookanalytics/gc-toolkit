---
name: gc-toolkit demo-capture — the SprintShow consumer wiring
description: How gc-toolkit consumes the SprintShow engine for narrated video demos — engine resolution, the slimmed demo:capture skill, the demo-gated Playwright MCP, the demo-toolchain doctor check — and the end-to-end proof that produced a narrated clip. Records tk-vd66j1.3, the continuation of the foundation story tk-vd66j1.1.
---

# The consumer wiring

The reusable video-demo capability splits in two: a mechanical engine that
parses a demo script, drives a browser, narrates, and assembles an MP4; and the
Gas City layer that consumes it. The engine is `@zookanalytics/sprintshow`
(AGPL-3.0), built and reviewed on its own rig (`sprintshow`). This bead is the
consumer layer in gc-toolkit. The foundation story `tk-vd66j1.1` holds the full
design record and every operator ruling that led here; this file records what
the consumer wiring is and why it took the shape it did.

## What the engine gives, and what gc-toolkit keeps

The engine owns everything app-agnostic: the markdown demo-script DSL and
linter, browser driving over Playwright, on-screen captions, OpenAI TTS
narration with a silent-captioned fallback, and ffmpeg assembly. gc-toolkit
keeps only the Gas-City-coupled layer:

- `skills/gc-demo-script` — authors a demo script from a Gas City bead. Unchanged
  here beyond dropping a stale toolchain reference.
- `skills/demo-capture` (`demo:capture`) — the thin consumer that resolves the
  engine and shells out to it. It carries no capture, encode, or narration code.
- `agents/demo` + `agents/demo/mcp/playwright.toml` — a demo-gated session that
  can drive the browser itself.
- `doctor/check-demo-toolchain` — reports whether the toolchain is provisioned.

## Engine resolution: local checkout first, published package as fallback

Operator ruling (2026-09-29, converse tk-e7monz): during the get-it-working
phase, consume the engine from the **local `sprintshow` rig checkout**, not the
published npm package. Publishing needs the operator's npm credentials and would
force a republish per iteration, so it is deferred until the capability is
proven.

The skill resolves the checkout by rig name — `gc rig list --json | jq
'.rigs[] | select(.name=="sprintshow") | .path'`, the same name→path shape
`gc-helm.sh` uses — and guards it by reading `package.json` `.name`. The host
has npm but not pnpm, and the engine builds to `dist/` it does not commit, so
the skill runs the TypeScript source directly through `npx tsx` against an
absolute path to `src/cli.ts`. An absolute path means the caller's working
directory is unchanged, so the caller-relative `demo.md` and `--serve-dir` paths
resolve as written, while Node still resolves `playwright` from the checkout's
own `node_modules`. First use runs `npm install`; a host `ffmpeg` is used when
present, otherwise `npm run provision:ffmpeg` fetches `ffmpeg-static`'s binary
(npm ≥ 12 blocks its automatic install script). When no local checkout exists —
the eventual any-rig path — the skill falls back to `npx @zookanalytics/sprintshow`.

## The slimmed skill drops a toolchain that no longer exists

The prior skill required ImageMagick (`magick`) for text overlays and assumed a
per-repo `scripts/assembleDemoVideo.ts` assembler that existed nowhere in the
city. The engine uses DOM/live overlays and ships its own assembler, so both
requirements are gone. The skill now documents the engine CLI (`sprintshow run
<demo.md> --serve-dir <app>`, `lint`, `assemble`), both capture modes
(walkthrough and proof), the demo-script format, and the toolchain, and points
at the engine's own `README.md`, `demos/sample.md`, and `examples/` as the
authority for the format and the agent/MCP path.

The engine writes `demos/<script-name>.mp4` and reports whether the clip is
narrated (a run line and a `narrated` result flag); there is no separate
`-narrated.mp4` file. A demo MP4 is an artifact, not a committed file — the
engine's linter warns when the output path is not covered by an LFS filter — so
captures are written outside the pack's tracked tree.

## Demo-gating is directory-scoped, so it needs a demo agent

`gc` builds a session's MCP set from `mcp/*.toml` convention dirs. A file in the
pack-root `mcp/` loads for **every** agent; a file under `agents/<name>/mcp/`
loads only when that agent is composed. There is no flag, session profile, or
`check.demo` gate — the directory is the only scoping primitive. A browser-driving
MCP in every polecat is a real footprint the operator ruled against (Dec3:
demo-gated), so the Playwright MCP lives at `agents/demo/mcp/playwright.toml`,
under a dedicated `demo` agent that is opened by hand (`gc session new demo`,
`min_active_sessions = 0`) like the converse sittings. Ordinary polecats never
load it. The server config mirrors the engine's `examples/agent-mcp/mcp.json`
and Playwright's `init-agents --loop` shape: `npx @playwright/mcp@latest`,
headless, isolated, `1280,900`, screenshots to `.captures/agent-run`. How a demo
session gets opened from PR triage is the sibling `.2` story's scope, not this
one's.

## The doctor check is a readiness heads-up, warn-only

`doctor/check-demo-toolchain` probes the host for the four things a narrated
capture needs — Node ≥ 22.18, a Chromium build (the Playwright cache or one on
PATH), ffmpeg (host, `FFMPEG_BIN`, or the engine's `ffmpeg-static`), and
`OPENAI_API_KEY` (the environment or `~/.gc/secrets.env`, presence only, never
the value). Every gap is a warning, never an error: a missing browser or ffmpeg
fails a capture until provisioned, and a missing key downgrades it to the
documented silent-captioned clip. It is the one non-invariant check in the pack —
a readiness report, not a structural property — and goes green once all four
resolve.

## The proof

Captured one narrated clip end-to-end inside Gas City against the engine's
bundled sample: `sprintshow run demos/sample.md --serve-dir examples/sample-app
--mode proof`, engine consumed from the rig checkout via `npx tsx`, chromium
from the Playwright cache, ffmpeg from `ffmpeg-static`, `OPENAI_API_KEY` from
`~/.gc/secrets.env`. All six step proofs held; the run reported a narrated demo;
`ffprobe` confirmed the MP4 carries both an h264 video stream (1280×900) and an
AAC audio track — a genuinely narrated clip, not a silent fallback.

## Boundaries

- **npm publish is out of scope** — deferred to the operator, who holds the
  credentials.
- **The host baseline (Dec1) is a separate, non-blocking track.** The Playwright
  browser and ffmpeg as general host packages, via the loomington server-setup
  repo, are a host/town change this bead does not make. The engine self-provisions
  both for its own use, which is what let the proof run with no host ffmpeg
  present; the doctor check names the gap rather than committing a host change
  from here.
