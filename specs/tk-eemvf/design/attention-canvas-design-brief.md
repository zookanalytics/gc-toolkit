# Attention Canvas — design brief

> Input for a Claude Design visual-exploration session.
> Companion files in this folder: `attention-board-sample.json` (real data the
> tiles render) and `how-to.md` (how to run the session).
>
> You may have zero context on "Gas City." You don't need it. You need to
> understand one human, one scarce resource, and one idea about how a surface
> should treat that resource. Read this slowly. By the end you should *feel*
> why this thing has to exist and what would make it good — not just what
> fields to put on a card.

---

## 1. The one idea, first

There is a person who runs a small army of AI agents. At any moment a dozen
separate streams of work are alive: code being written, branches waiting to
merge, decisions only a human is allowed to make, investigations halfway done.
Each stream has its own state, its own history, its own "where was I."

The machines are not the bottleneck. They are cheap and abundant — you can
spawn another, run ten in parallel, have them critique each other, throw the
bad ones away. **The bottleneck is the one human's attention.** It is scarce,
it is context-bound, and — this is the cruel part — it does not restart on
demand. You cannot spin up a second copy of the operator's focus.

So the governing principle of this whole system, written into its foundation,
is: **human attention is the budget.** Everything is designed to spend it as
slowly as possible and to make every unit of it pay off.

The Attention Canvas is the operator's window into all of that work. Its entire
reason to exist is **attention conservation**. Hold that thought above every
other requirement in this document. A feature that costs the operator attention
to save the machine effort is backwards here. We have the effort to burn. We do
not have the attention.

---

## 2. What this is NOT (read this before you sketch anything)

It is very easy to read "operator dashboard for many concurrent workstreams"
and reach for the familiar monitoring-dashboard vocabulary: tiles of charts,
red/green health, a notification bell with a number on it, toasts sliding in
from the corner, an activity feed you scroll. **Resist all of it.** That genre
answers a different question ("is the system healthy right now?") for a
different consumer (a machine's metrics, watched passively). It works by
*competing for your eyes* — by interrupting.

This surface is the opposite on the two axes that matter:

- **Pull, never push.** Nothing here ever interrupts. No badge, no toast, no
  ping, no buzz, no count climbing in a tray. The operator comes to the surface
  when *they* choose to. The surface's job is not to summon attention; it is to
  *reward* a visit by making it maximally efficient. An agent that needs the
  human does not poke the human — it raises its own hand *on the board* and
  waits to be seen (more on this "hand-raise" in §6). Escalation is inverted:
  the work surfaces itself onto a calm board, instead of a notification
  surfacing itself onto the human.

- **Perceptual + spatial grounding, not text to re-read.** The expensive thing
  about switching between a dozen workstreams is *reloading context* — paging
  the whole mental model of "stream #7" back into your head. The way a human
  beats that cost in the physical world is **place**: you walk back into a
  familiar room and your sense of what you were doing there reinstates *before
  you've read a single word*, because the room looks the way it looked. This
  surface manufactures that effect on purpose. Every workstream lives in a
  **durable place** on a canvas, with a **durable color** and **durable
  imagery**, so that a single glance at that place reinstates the operator's
  whole model of that stream. The context trigger is **the look of the place**,
  not a sentence describing the stream.

If you take one thing from this section: a notifications-and-dashboards tool
*pushes information at a passive watcher*. This *is a place the operator walks
back into*, that *re-loads their own context for them*, and that they read by
**glance**, not by reading.

---

## 3. The operating loop we are designing for

Because context is reinstated by place, the operator can do something that's
normally exhausting: **hold many topics in flight and switch between them
cheaply.** The intended rhythm:

1. The operator looks at the board (a visit, on their schedule).
2. In one sweep of the eyes they take in *everything alive* — what's moving,
   what's stuck, what's done, and the few things that need *them*.
3. They land on the one or two places that earned their attention.
4. Because the place reinstated the context, they read **only the state-delta**
   — what changed since they last looked here — not the whole history.
5. They act (ratify a result, redirect, dive in), and leave. The handled thing
   leaves the board. The queue shrinks.

Step 4 is the soul of it. Watch how it works in the **real data** shipped with
this brief. The `su-lou` tile carries this one line from its own agent:

> "NEEDS your MERGE: PR#11 (mic-fix) + #12 (U4-STT), both verified. On
> merge+reopen I dispatch ONNX/U5 + live-mic feel-test. Drained between visits."

That single sentence *is* the state-delta. The operator reads it and knows
exactly what is being asked, why it's safe, and what happens next — **without
opening anything.** Contrast `tk-eemvf`, which has no such line yet and falls
back to a terse mechanical state: *"decomposed, idle — assign or host."* The
difference between those two tiles is the difference between a surface that
respects attention and one that merely displays status. **A great tile lets the
operator finish a thought without drilling in at all.** Drilling in is the
fallback, not the default.

---

## 4. Who this is for

**One operator.** Not a team, not a feed of stakeholders — a single human
coordinating many concurrent agent workstreams across several independent
projects ("rigs": you'll see `gascity`, `gc-toolkit`, `shutupandlisten`,
`signal-loom` in the sample). They are technical, they live in a terminal, and
their dominant, recurring cost is **context-switching** between streams. They
are not watching this surface all day; they visit it, triage, dive into one
thing, and leave. Design for the *returning* visitor reloading context, not for
the passive monitor.

Single-operator also means: no permissions model, no multi-user states, no
social features, no "who else is looking." Spend that saved complexity on the
glance.

---

## 5. The four jobs

The operator comes to this surface to do exactly four things. Every design
decision should make at least one of these faster and none of them slower.

1. **See the work in flight** — one place that shows *all* the live
   workstreams across every project at once. Not one project's view; the whole
   portfolio, side by side.
2. **See status at a glance** — for each stream, instantly: is it moving, is it
   stuck, is it done and waiting, is it empty? Without reading. By *look*.
3. **See what needs the human** — the few items that cannot advance without an
   operator decision or ratification must be *unmissable* — yet (the hard part)
   the surface must stay calm while making them so. Calm and unmissable at once.
4. **Dive in** — from any stream, one move to either (a) drop into a **live
   terminal** in that work's running conversation, or (b) read its **latest
   output / snapshot** without disturbing it.

---

## 6. The canvas idiom

The chosen form is **one persistent, zoomable, spatial canvas** — think
Figma / tldraw / Excalidraw / a node-graph board — not a list, not a grid of
cards that reflows, not stacked OS windows. The spatiality is not decoration;
it *is* the attention-conservation mechanism. Specifically:

- **Durable place.** Each anchor (each workstream) has a stable position the
  operator chooses or the layout keeps. It does not jump around between visits.
  Stability is the whole point: muscle memory and spatial memory are what make
  the glance reinstate context. A tile that moves loses its "room."
- **Durable color + imagery.** Each anchor carries a persistent visual signature
  — a color, an icon/illustration/landmark — so it's recognized the way you
  recognize a building on your street: pre-verbally, from across the canvas.
  Color and imagery are free bandwidth; use them to encode identity (which
  stream) and possibly state (how it's doing).
- **Peek at rest, live on focus.** A tile at rest shows a **snapshot** — a calm
  peek of the work's current state (its headline, its progress, a frozen glimpse
  of its last output). When the operator **focuses** a tile (zoom in / open it),
  it can become **live** — an embedded terminal attached to that work's actual
  running session, real and interactive. The canvas is therefore not a wall of
  pictures; it's a wall of *windows*, most showing a still frame, any one of
  which you can step through into the live room.
- **Zoom as level-of-detail.** Zoomed out: the whole portfolio as colored
  places, severity legible from altitude. Zoomed in: one stream's full detail,
  up to and including its live terminal. The zoom *is* the navigation and the
  triage gesture.

---

## 7. The data each tile renders

Every tile is one **anchor** — a top-level unit of work. The board is produced
by a real tool (`gc-attention`) whose `--json` output is the live contract; a
representative **real** snapshot is in `attention-board-sample.json` (11 tiles).
Open it alongside this section. Here is what the fields *mean* (grouped by what
they're for, not alphabetically):

**Identity & place**
- `id` — stable unique id (e.g. `su-lou`, `tk-eemvf`). The anchor's durable
  identity; tie place/color/imagery to this.
- `rig` — which project it belongs to (`gascity`, `gc-toolkit`, …). A natural
  grouping/coloring axis.
- `kind` — one of `epic` (a durable big-thread of work), `convoy` (a floating
  bundle of related units), `decision` (a human-only choice), `flagged` (see
  below). Different kinds may want different shapes.
- `title` — the human name of the work.

**Urgency (how much it wants the human) — already computed for you**
- `severity` — the headline band, *pre-ranked*: `FLAGGED` > `HIGH` >
  `ELEVATED` > `NORMAL` > `LOW`. This is the single most important field for
  the visual hierarchy. What each band means:
  - `FLAGGED` — **a hand was raised.** An agent (or the operator) explicitly
    raised *its own* bead onto the board because it needs a human. This is the
    escalation-inversion from §2 — the dual of an agent messaging its boss. It
    floats to the very top, its own band. *(Note: the current real snapshot
    happens to contain no flagged tile — they're deliberately rare. Design the
    band anyway; it is the loudest thing the board can say. A flagged tile
    additionally carries `reason` and `flagged_at`.)*
  - `HIGH` — **stranded.** Work is decomposed and open but *nothing is moving*
    on it and no one is home — it needs a human to unstick it. (Also: an
    orphaned bundle with no owner.) See `gc-k8r4y`, `su-lou`, `tk-eemvf`.
  - `ELEVATED` — a human-gated `decision`; or something gone stale; or work
    that's moving but has a stuck child to recover. See the two `decision`
    tiles.
  - `NORMAL` — **healthy and active.** Someone is in the conversation or live
    work is in progress. Calm. See `tk-6d0vb` (note `live: "hot"`).
  - `LOW` — **done or empty.** All children closed and awaiting graduation, or
    an empty shell. Quiet. See `gc-8g41r` (all 9 closed), `sl-yqslv` (empty).
- `rank_score` / `weight` — the deterministic numeric ranking behind the band
  (subtree size + priority + cross-rig blast radius). Use for sort/size if you
  want finer ordering than the five bands.
- `priority` — P1…P4 importance.

**Liveness (is anyone home in this conversation?)**
- `live` — `hot` (an active session — focusing *attaches instantly*), `warm`
  (a suspended session — focusing *resumes* it), or `cold` (no session —
  focusing *materializes* one). This is the peek-vs-live signal: a hot tile can
  go straight to a live terminal; a cold one will spin one up. It's a prime
  candidate for motion/pulse encoding (a hot tile could feel subtly alive).

**Frontier facts (the at-a-glance progress of the work)**
- `n_closed` / `m_total` — children done over total (e.g. `4/6`). The natural
  progress meter. `decision`/`flagged` have none (—).
- `open`, `in_progress`, `in_progress_live`, `in_progress_dead`, `assigned` —
  the live breakdown of the open frontier. `in_progress_dead` / `dead_owner`
  mean a child was being worked but its worker died — a stuck-and-unknown state
  worth surfacing.
- `stranded` (bool) — decomposed, open, nothing moving, no one home → the HIGH
  trigger. The canonical "this needs you" shape.
- `complete` (bool) — all children closed, awaiting graduation/close.
- `empty` (bool) — a shell with no children yet.

**The headline (what to actually show on the face of the tile)**
- `takeaway` — *the* field to feature when present. An **LLM-authored** one-line
  headline, written by the work's own resident agent, saying what it concluded
  or what it needs. This is the state-delta from §3 made literal — see
  `su-lou`, `gc-k8r4y`, `tk-6d0vb`, `gc-8g41r`. When this exists, the operator
  may not need to drill in at all. It can be `null` (the agent hasn't authored
  one) — see `tk-eemvf`, `tk-aezem4`.
- `frontier` — a terse mechanical one-liner of the same state ("3 open · 0
  in-progress (stranded)", "2 open · in conversation"). Always present; the
  deterministic fallback.
- `needs` — the single best one-glance answer for the human: it *is* the
  `takeaway` when one exists, otherwise a short deterministic state phrase
  ("operator decision", "decomposed, idle — assign or host", "all 9 closed —
  graduate"). If a tile face shows exactly one sentence, this is it.

**Freshness & provenance**
- `updated_at`, `stale_days` — how long since this moved. Staleness is itself a
  signal (a NORMAL thing gone stale becomes ELEVATED). `tk-aezem4` is 42 days
  stale; `tk-6d0vb` is 0.
- `takeaway_at` / `takeaway_by` — when/by whom the headline was authored
  (`host` = the resident agent, `proactive` = a one-shot reaction).
- `cross_rig_refs` — other projects this work blocks/touches; blast radius.

A design north star for the tile face: **`severity` drives the visual weight,
`needs`/`takeaway` is the one sentence, `n_closed/m_total` is the progress,
`live` is the pulse.** Everything else is detail for focus/zoom.

---

## 8. Medium & constraints

- **Web app**, single operator, reached privately over a Tailscale network
  (think: a personal URL only the operator can hit). No public internet, no
  multi-tenant concerns.
- **Stack is settled** (you don't need to honor it in a prototype, but it tells
  you what's cheap to build later, so lean toward it): **Vite + React + TS +
  Tailwind** SPA. The zoomable canvas is a mature JS canvas lib
  (tldraw / xyflow / Excalidraw class). The embedded terminal is **xterm.js**.
- **Three data planes** feed the surface — useful to keep distinct in your head:
  1. **Board tiles** — the array in `attention-board-sample.json`, refreshed by
     polling (it's an expensive cross-project aggregation with its own cache; it
     does not stream). This is the canvas content.
  2. **Drill-in + liveness** — richer per-stream detail and live session state,
     available on focus, including a push/stream channel so an open tile can
     update live.
  3. **Embedded terminal** — the real interactive session, attached when the
     operator dives into a hot/warm tile.
- The existing plain Gas City dashboard already establishes a house visual
  language (colors, type) you can echo or deliberately depart from — see
  `how-to.md` for where to find it and the live URL to capture.

Constraints that flow from the soul: **no notification chrome** (no bell, no
toast, no unread badge). **Stable layout** (tiles keep their place across
refreshes — never reflow the whole board on a poll). **Legible from altitude**
(severity readable zoomed-out). **Calm by default** (the resting state of a
healthy board should feel quiet, even with twenty tiles on it).

---

## 9. What "good" feels like (the bar)

You'll know a direction is right when:

- **A glance reinstates context.** The operator looks at a place and their
  whole model of that stream comes back *before* they read — from position,
  color, imagery, shape. Returning feels like walking into a familiar room.
- **Switching is nearly free.** Moving attention from stream #3 to stream #9
  costs almost nothing, because #9's place did the remembering. The operator can
  hold a dozen streams without holding them in their head.
- **"Needs the human" is unmissable yet calm.** The two or three things that
  actually need a decision are impossible to overlook in a single sweep — and
  the surface achieves that *without shouting*. Nothing flashes for attention it
  hasn't earned. The loud thing is loud because it's rare, not because it's
  aggressive.
- **You can finish a thought without drilling in.** For most tiles, the face
  (the one `needs`/`takeaway` sentence + progress + pulse) is enough to decide.
  Drilling in is for when you've *chosen* to engage, not a tax to learn status.
- **Nothing shouts.** A healthy, busy board is *calm*. Activity is not anxiety.
  The surface's emotional default is quiet competence, not urgency.

If a prototype is pretty but the operator's eyes have to *hunt* — hunt for
what's stuck, hunt for what changed, hunt for what needs them — it has missed.
The whole game is to make the eyes *not hunt*.

---

## 10. Open design questions (leave room — these are yours to explore)

These are deliberately unsettled. Strong, opinionated, *different* answers are
exactly what the exploration is for.

- **Encoding severity & liveness.** Across color, motion, size, position,
  imagery, border, glow — what carries `severity`? What carries `live`
  (hot/warm/cold)? Should a hot tile literally feel alive (a slow pulse, a
  cursor blink in its peek)? How do you keep five severity bands legible at a
  glance without a rainbow?
- **Making "needs the human" unmissable yet calm.** This is the central tension
  (§5 job 3, §9 bar 3). Is it placement (a gravity well the flagged/HIGH tiles
  drift toward)? A band/region? A halo? Restraint elsewhere so the one loud
  thing is loud by contrast? Find the answer that doesn't become a klaxon.
- **Spatial layout & memory.** What organizes the canvas? By `rig` (project
  neighborhoods)? By `severity` (a worry-axis — urgent things near, calm things
  far)? Freeform with the operator placing tiles and the layout *remembering*?
  A hybrid? How do new anchors enter without disturbing existing places (the
  durability requirement)?
- **Imagery.** What *is* the per-anchor imagery, concretely? A generated icon? A
  per-rig motif? An operator-chosen landmark? A live thumbnail of the terminal?
  How does it stay recognizable yet informative?
- **Zoom semantics & level-of-detail.** What appears/disappears as you zoom?
  Where's the threshold from "peek snapshot" to "live terminal"? Does zooming
  out cluster, summarize, or just shrink?
- **Peek → live transition.** What does focusing a tile feel like — a tile that
  unfolds into a terminal in place, a zoom-through, a modal? How do you preserve
  the operator's sense of *where they are* on the canvas as they dive and
  surface?
- **The resting board.** What does a calm, healthy board *look like* with twenty
  tiles and nothing urgent? (If that state isn't beautiful and quiet, the
  surface will feel stressful in normal use.)

---

*Bottom line for the designer: you are not building a dashboard that reports
status. You are building a **place** a single overloaded human walks back into a
dozen times a day, that **reinstates their context by look**, lets them read
**only what changed**, makes the rare "I need you" **unmissable but never
loud**, and lets them **step through any tile into the live work** — all while
staying, at rest, completely calm. Conserve their attention. That is the
entire job.*
