---
name: Reusable rig-demo mol — design and proof
description: Why the rig-demo capability is split into a mechanical capture script plus a thin formula, why the app target is a pour variable rather than a stored per-rig config, and the two-rig proof that the capability runs. Records tk-vd66j1.2.
---

# Reusable rig-demo mol

The capability: capture one narrated video demo of a rig's app, parameterized by
rig and scenario, reusing the demo-capture machinery, runnable against any rig.
It is `formulas/mol-rig-demo.toml` plus `assets/scripts/rig-demo-capture.sh`. The
video review modality (tk-vd66j1.9) pours the formula to produce a clip for a PR
under review; an operator pours it for any rig from a shell.

This records the design decisions and the proof for tk-vd66j1.2, the mol leg of
epic tk-vd66j1. The authoritative how-to is `docs/rig-demo.md`.

## Engine-driven capture, not agent-driven

`skills/demo-capture/SKILL.md` offers two capture paths: the engine drives
Playwright itself (`sprintshow run … --serve…`), or an agent drives the browser
over a Playwright MCP and hands frames to `sprintshow assemble`. The mol pours to
a pool, and a pool session carries no browser MCP — that lives only on the
hand-opened `demo` agent (tk-vd66j1.3). So the mol takes the engine-driven path,
the only one available to it, and the script shells out to `sprintshow run`.

## A mechanical script under a thin formula

The capability splits along the line between mechanical work and judgment.

- `rig-demo-capture.sh` is the mechanical half: resolve the engine, lint the
  script, drive the capture, and fail closed if no MP4 appears. It knows nothing
  of beads, convoys, or routing, so the mol, tk-vd66j1.9, and an operator at a
  shell all drive it the same way. Before this script, the capture path had no
  scripted caller at all — the `demo` review check (`review-dispatch-body.sh`)
  points an agent at the two skills in prose, and `demo-deliver.sh` named "the
  rig-demo mol" as a future caller that did not yet exist.
- `mol-rig-demo.toml` is the judgment half: derive the demo-request bead, resolve
  the scenario into a script (a provided path, or one generated from a bead by
  following `skills/gc-demo-script/SKILL.md`), call the capture script, deliver
  the clip to a PR or report its path, then close the request and drain.

Keeping the engine-resolution and fail-closed logic in one script is what lets
tk-vd66j1.9 reuse it without copying it, and lets it carry a hermetic test
(`rig-demo-capture.test.sh`) the formula body could not.

## The app target is a pour variable

The one genuinely rig-specific fact a capture needs is how to reach the app —
`--serve-dir`, `--serve`, or `--base-url`. Nothing in the toolkit maps a rig to
its app: `gc rig list` gives a name, a path, and a prefix, not an app entrypoint.

The capability threads that fact as a pour-time `--var`, the pattern
`mol-refinery-patrol` already uses for a rig's per-repo commands (test, build,
lint). A relative `serve_dir` resolves against the `rig_name` checkout, because
the app is that rig's. This is enough for the mol to run against any rig and for
the two-rig proof below.

A stored per-rig default — so a caller need not re-specify the serve command each
time — is a real convenience for the epic's "without bespoke setup" goal, but it
is not needed for this mol to work or to meet its acceptance, and it is a
separable concern. It is deferred to a sibling bead (tk-8o3fck) rather than
built here. Cost of waiting: until it lands, every caller — including
tk-vd66j1.9 — passes the app target explicitly; nothing is blocked.

## The clip is an artifact, never committed

No `.gitattributes` LFS filter covers an MP4, and the engine warns when an output
path is not LFS-covered. A clip is delivered to its PR as an inline,
uncommitted user-attachment (`demo-deliver.sh`, tk-vd66j1.4) — the only
inline-playable path — so the capture writes outside the repo tree and the mol
never commits it.

## Proof: the same script, two rigs

The acceptance is that the capability runs against at least two different rigs
from one formula. Proven by driving `rig-demo-capture.sh` against two rigs' apps,
each producing a narrated MP4 whose streams `ffprobe` confirms:

| Rig | App target | Mode | Result |
|---|---|---|---|
| sprintshow | `--serve-dir examples/sample-app` + `demos/sample.md` | walkthrough | 24.4s, h264 1280×900 + AAC narration; all 6 step-proofs held |
| shutupandlisten | `--serve-dir web/dist` + a smoke script | walkthrough | 12.8s, h264 1280×900 + AAC narration; all 5 step-proofs held |

Both clips carry a real video stream and a real narration audio stream, so the
toolchain (engine, Chromium, ffmpeg, `OPENAI_API_KEY`) resolves and the capture
is genuinely narrated, not the silent fallback. The two targets are different
rigs reached the same way, which is what "any rig" rests on: the rig-specific
input is the one serve flag. The demo scripts are per-rig scenario inputs, not
committed pack artifacts — the sprintshow script ships with that engine, and the
shutupandlisten smoke script was written for the proof and lives outside the
tree, the way a generated or hand-written scenario does.

## Boundaries

- Wiring the mol into PR review — triage engaging a visual check, the draft-PR
  phase, the verdict — is the visual-review leg (tk-vd66j1.5 design;
  tk-vd66j1.6–.9). tk-vd66j1.9 consumes this mol; this leg does not wire it.
- The capture toolchain and the TTS key are tk-vd66j1.1. This mol assumes them
  and names the dependency (`doctor/check-demo-toolchain`); it does not provision
  them.
- The SprintShow engine is resolved at runtime from the local `sprintshow` rig
  checkout or the published npm package (`skills/demo-capture`); npm-publishing
  it stays deferred and operator-run, per the epic.
