---
name: Collaborative UI — asymmetric multiplayer and the commentable surface
description: Vision memo. Why gc-toolkit's collaboration model is asymmetric multiplayer, and the core bet that the bead, the conversation, and every artifact are one commentable surface. Exploratory — records what was thought, not a build commitment.
---

# Collaborative UI: the commentable surface

## Status

Vision memo. Captures a design conversation (2026-06) about what a more
*collaborative* gc-toolkit looks like, taking the cue from how Google Docs
and Figma shifted work from private files passed around to a shared surface
you meet inside. Broad strokes for posterity — not adopted, not a build
commitment, not yet true. Filed in `specs/` as historical record of what
was thought. The pieces it leans on (`bead-universe`, the attention board,
review legs, branded channels) are real; the synthesis here is a direction,
not a plan.

## The frame: asymmetric multiplayer

Docs and Figma are remembered for "real-time collaboration," but the deeper
change was *where the work lives*. Work stopped being a private payload
mailed around and became a shared place you go to. You don't send the doc;
you meet **in** it. Comments anchor to the text. History is ambient.
Presence is visible without anyone being summoned.

A literal port of that to gc-toolkit would be a mistake, because Docs and
Figma assume their collaborators are **symmetric and abundant** — a roomful
of roughly-equal humans, all potentially co-present. `docs/foundation.md`
asserts the opposite: agents are abundant and always-on; the human is
scarce, context-bound, and not restartable on demand. Manufacturing
co-presence (live cursors, "3 viewing now," activity that invites hovering)
would spend exactly the budget the foundation tells us to protect.

So the target is not "more collaborative" but **asymmetric multiplayer**.
Three models, only the third is ours:

| Model | Shape | Effect on attention |
|---|---|---|
| **Individual / handoff** | Agent works, stops, hands a deliverable over, waits. Human is a terminal reviewer. | Bottlenecks the human at the end, full context-reload each time. |
| **Naive collaborative** (literal Figma) | Co-presence, live cursors, hovering. | Burns the scarce budget inviting the human to always be present. |
| **Asymmetric multiplayer** (ours) | Agents collaborate continuously on a living shared surface. The human is a privileged, intermittent collaborator who drops in at the grain they choose, every drop-in primed so re-entry is free. The surface holds state, so simultaneity is never required. | Spends attention only on judgment, and never twice. |

`bead-universe` already carries most of this: land in a bead, the universe
is reachable, the board brings you there, ratify-or-redirect in one move.
That *is* "the artifact is the meeting place." This memo is about the
interaction grain *inside* that frame.

## What this is not (corrections from the conversation)

- **Not spectating.** An earlier draft proposed a "spectate rung" —
  read-only attach to watch an agent work — as a starting point. Demoted.
  Watching an agent make progress is really just *seeing that a thing is
  owned and moving*; `gc peek` in gascity already covers it, and it's a
  surface you'd reach for rarely. It is not core to the collaborative
  experience and is not where to start.
- **Not co-presence.** No live cursors, no "agents active now" motion, no
  activity firehose. Presence belongs on the board as *state*
  (`· cold`, `✓ advanced (12m)`, `⚠ stale`), never as a feed competing for
  the same attention the board is trying to protect.
- **Test for any "live" feature:** does it still work, with zero
  degradation, if the human shows up six hours later? If not, it's the
  handoff model wearing a multiplayer costume.

## The core bet: comments live where the work is

The center of the experience is the Docs/Figma move that comments anchor to
the work — and the realization that **the agent↔human conversation is the
same kind of thing as a comment.** "Just like the conversation" becomes
literal: replying to an agent and pinning a margin note on a doc are the
same act, aimed at different targets.

So the bet is one primitive everywhere:

> A **comment** is a threaded, attributed, resolvable conversation pinned to
> an **anchor**. The anchor names what it is about. Same object, same
> lifecycle (open → thread → resolve → recoverable), wherever it lands.

### One primitive, three (or N) anchor kinds

| Anchor | "About this…" | Example |
|---|---|---|
| **Bead** | the whole unit of work | "the framing of this task is off" |
| **Conversation span** | a specific agent turn or claim | "this assumption, right here, is wrong" |
| **Artifact region** | a line range, a mockup frame, a code hunk | "this section / this button / this function" |

The radical part is the collapse: the agent dialogue, comments-on-the-doc,
and notes-on-the-bead are not three channels. They are one primitive aimed
at different anchors. The conversation **is** comments; comments **are** the
conversation.

### Why this collapses the retired consult problem

The consult model (retired from core, 2026-06-10) made the conversation a
*separate bead* — a Slack-thread bead that then had to be surfaced, hosted,
and attached. That separation is why it felt heavy: the dialogue lived
*beside* the work, so the whole machinery existed to ferry the human back to
it.

The commentable surface puts the dialogue *on* the work, anchored where it
bites. There is nothing to ferry. **An open, unresolved comment addressed to
the human is itself the surface** — no separate host to spawn, no separate
thread to route. The producer/surfacer/host trio the consult model needed
dissolves into "the comment is open."

This is also why it serves the attention budget directly: the human engages
exactly where judgment is needed (the anchor *is* the location), at the
grain they choose, and never re-orients — the comment carries its own
context because it is pinned to the thing it is about.

## What the UI actually looks like (text-native)

gc-toolkit lives in terminals, markdown, beads, and `gc` commands — not a
web canvas. The Docs/Figma *mechanics* port; the *rendering* is native:

- **Anchored markers in the render.** An artifact renders with inline
  markers where threads are pinned — a superscript `▸` or a gutter glyph,
  `git blame`-gutter meets Docs-margin. Expand a marker to open the thread
  in place: human and agent posts interleaved, attributed, timestamped.
  Resolve collapses it to a faint marker; resolved threads stay recoverable.
- **The thread is the unit, not a chat log.** Each anchor owns its own
  short conversation. Branching work stops fighting a single linear chat
  (the `bead-universe` problem statement) — each thread is the line for
  *its* point, and the points sit where they belong.
- **One board, all anchors.** The attention board gains a single new
  aggregation: **open comments addressed to the human, across every
  anchor** — bead, conversation span, artifact line alike. "Comments that
  need you" is the queue regardless of where they're pinned. Empty board =
  nothing needs you. The board stays the *only* queue; anchored comments
  must never become a second notification stream.
- **Decision-needed is just an open comment.** When an agent needs
  judgment, it opens a comment anchored to the exact spot. The human's
  redirect is a reply; ratify is resolve. The "ratify-or-redirect in one
  move" of the first-reaction card becomes uniform across every target.
- **Resolution graduates to a durable home.** A thread that settled
  something binding promotes to an ADR or the bead's record — "decisions
  have a home," with the home being *where the decision was actually made*,
  then lifted into the durable record. What's written survives.

## Material change to artifacts is a first-class event

The other thing worth seeing — distinct from watching an agent type — is a
**material addition landing**: a new section, an in-progress design mockup,
a reworked function. When an agent makes a substantive change, it
auto-anchors a marker to the *new or changed* region — "added this,"
diff-aware — so the human's eye goes straight to what changed and can
comment right there.

This is the Figma "watch the frame evolve" value *without* live cursors: you
see **what landed**, asynchronously, and react in place. And it is
medium-agnostic — a text span, an image region of a mockup, a code hunk, a
conversation turn are all the same anchor mechanism. That generality is the
natural home for the roadmap's deferred **visual design surfaces**: a mockup
is just another commentable artifact, and "compare 2–4 candidates" becomes
"comment across four anchored frames."

## How it sits on what already exists

- **`bead-universe`** routes serial attention to the right bead and makes
  the universe reachable. The commentable surface is the interaction grain
  *inside* the universe — and the comment-board aggregation is a natural
  evolution of the attention board, not a new surface.
- **Review legs** already emit `suggested-change-for-human`. In this model
  that is a comment anchored to the diff: accept/reject in place — Docs
  suggesting mode, made native.
- **Branded context channels** — each anchor kind is a branded surface; the
  marker pre-loads what you're looking at (a bead-level call vs. a line note
  vs. a flagged assumption) before you read a word.

## Open questions (named, not solved)

- **Anchor stability.** How does a comment stay pinned to a span of
  `architecture.md` as the file changes around it? Content-hash anchors,
  heading anchors, reflowing line ranges — the Docs/GitHub problem, to be
  chosen, not invented.
- **Conversation anchoring.** Can you pin to a specific agent turn, and how
  is that addressed and stored given `wake_mode=resume` replays the
  provider transcript? The conversation-span anchor is the least proven of
  the three.
- **Storage.** Comments as bead metadata vs. a sidecar store. Bead-native
  is the default bias — it inherits the universe slice and board plumbing
  for free.
- **Graduation policy.** Which resolved threads become ADRs, and is that
  promotion curated or automatic.
- **No new firehose.** The board must remain the single attention queue.
  The discipline that keeps anchored comments from degenerating into a
  stream is a design constraint, not an afterthought.
