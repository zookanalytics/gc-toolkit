# How to run the Attention Canvas design session

This folder is the **input bundle** for a visual-exploration session in
**Claude Design**. Three files:

- `attention-canvas-design-brief.md` — the heart: purpose, soul, jobs, the
  canvas idiom, the data, the bar, and the open questions. **Read this first.**
- `helm-board-sample.json` — a **real** captured snapshot of the data the
  tiles render: 11 anchors across four rigs, covering four of the five severity
  bands (`HIGH`, `ELEVATED`, `NORMAL`, `LOW` — no `FLAGGED`) and two of the
  three liveness states (`cold`, `hot` — no `warm`). It captures the **current**
  `gc-helm --json` output: a top-level ranked **array** of tiles (the
  bash-PoC contract). The planned Helm **service** (plan U1/U4) serves
  those same tiles inside a typed **envelope** `{generated_at, total, tiles[]}`,
  so the **per-tile** field shape is what's stable across both — prototype
  against the tiles. Mock more in the same shape for volume, including the two
  rare states this snapshot lacks (a `FLAGGED` hand-raised tile, a `warm`
  suspended-host tile) — the brief asks you to design those bands anyway.
- `how-to.md` — this file.

---

## The two-loop method (keep them separate)

This project runs as **two loops that do not blur into each other**:

1. **Exploration loop — Claude Design (you are here).** Produce *live,
   clickable prototypes* on the **mock/sample data** in this folder. The goal is
   not code that ships; it's to find a visual direction by *reaction*. The
   **operator's perceptual reaction is the oracle** — the test of a direction is
   whether, when the operator looks at it, the context reinstates, the eyes
   don't hunt, and "needs the human" lands as unmissable-yet-calm (see the brief
   §9, "What good feels like"). Iterate on feel, not on plumbing. Explore
   *several genuinely different* directions before converging — the open
   questions in brief §10 are the search space.

2. **Implementation loop — Claude Code / agents (later, elsewhere).** Real code,
   real live data, the embedded terminal, tests, code review. This loop is
   **entered from the exploration loop's output**, not started from scratch.

**The boundary is firm:** Claude Design produces **prototypes + a handoff
bundle**, *not* the deployable app. Don't try to build the real data wiring or a
production app in the exploration loop — prototype the experience, capture the
direction, hand it off.

---

## What to bring back

The session is done when you can hand the operator:

1. **A chosen direction** — the recommended visual/interaction approach, with
   enough of the explored alternatives shown that the choice is legible (why
   this one, what was tried, what was rejected). Concretely answer as many of
   the brief's §10 open questions as the exploration settled: how severity &
   liveness are encoded, how "needs the human" is made unmissable-yet-calm, how
   the canvas is spatially organized and how places stay durable, what the
   imagery is, the zoom semantics, and the peek→live transition.
2. **The handoff bundle** — the artifact that *feeds the implementation loop*:
   the prototype(s), the design decisions/spec, tokens (color, type, spacing,
   motion), component intentions, and any assets. This is the input a Claude
   Code / agent session turns into the real Vite + React + TS + Tailwind app.

The operator then records the chosen direction back onto the design epic
(`tk-eemvf`) as decisions, files implementation beads under it, and dispatches
them. You don't need to do that filing — just deliver the direction + bundle.

---

## Useful references for web-capture (the existing visual language)

You have repo access and a live URL. Two things are worth capturing so a chosen
direction can either **echo** the house style or **deliberately depart** from
it:

- **The live Gas City dashboard** (current operator surface, different genre —
  panels/lists, not a canvas — but the real colors, type, and density in use):
  `https://ai-development.tail72658e.ts.net`
  Capture it for the existing visual language and to feel what's there today.
  *(Private Tailscale origin — reachable only from the operator's network.)*

- **The stock dashboard source** (the house design tokens and component
  vocabulary, in code):
  `rigs/gascity/cmd/gc/dashboard/web/` — a Vite + TS SPA. Most useful files:
  - `src/palette.ts` — the current color palette / visual language.
  - `src/panels/` — how today's surface composes its views (activity, issues,
    convoys, crew, mail, …).
  - `src/api.ts`, `src/sse.ts`, `src/generated/` — how it talks to the backend
    (a typed client + a server-sent-events stream). Relevant later for the
    live-data planes, not for the exploration's mock-data prototypes.
  Note the new app **adds** React + Tailwind + a zoomable-canvas lib +
  xterm.js on top of this same Vite/TS foundation; the stock dashboard is the
  *visual-language* reference, not the structural template.

- **The data contract**, if you want to regenerate or extend the sample:
  `rigs/gc-toolkit/assets/scripts/gc-helm.sh` (its header documents every
  `--json` field). Re-capture a fresh snapshot with:
  `bash rigs/gc-toolkit/assets/scripts/gc-helm.sh board --json`
  (run from the city root, `/home/zook/loomington`).

---

## One reminder before you start

Re-read brief §2 ("What this is NOT") before the first sketch. The gravitational
pull toward a notifications-and-charts dashboard is strong and it is the wrong
genre here. This is a **calm, spatial place** the operator walks back into — a
surface that *conserves attention*, pulls instead of pushes, and reinstates
context by **look**. Keep that as the standing acceptance test for every
direction you explore.
