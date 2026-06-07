# Human Review — Decisions & Corrections (AUTHORITATIVE)

Operator's answers at the PRD gate, 2026-06-06. **Where this conflicts with prd-draft.md
or prd-review.md, this file wins. Read it first.**

---

## Correction to the PRD review — read before trusting prd-review.md

**`consult-host` is NOT a production prototype.** It was an idea that has been **abandoned.**
The feasibility leg over-weighted it ("the Pillar-1 prototype already in production"; "build
the seam from consult-host") and the synthesis amplified that. Treat `consult-host` as — at
most — a loose prior sketch. **Do not weight toward it; do not propose building on it as if it
were vetted.** Any "reconstruct the universe from durable state" idea must stand on its own
merits, not on consult-host's supposed production status.

---

## The v1 shape after the gate

**Q1 — Proactivity is deferred as a resident loop. "Proactive" work is done by slinging mols.**
v1 does **not** build an always-running, self-waking per-bead loop. Anything "proactive" reuses
the existing dispatch: a mol is *slung* against a bead to advance it. The design must still
**materially work out how proactive-via-slung-mol behaves** — what triggers the sling, what the
mol does, how its output returns to the bead. This defers the *mechanism*, not the *goal*.

**Q2 — Scope the cheap first reaction.**
The valuable thing a freshly-engaged agent does is a cheap *first reaction*: e.g. basic research
written into a spec document, or simply an LLM reading the bead's prompt and articulating what it
thinks the bead means. **Key fact: a bead often already carries a "body" (its description/prompt)
that seeds this first reaction.** (This very run — idea→plan on a decision bead — is itself an
instance of "research → spec document.") Scope what these first reactions are; that is the
concrete content of "proactive" work in v1.

**Q3 — Binding is 1:1 for v1.** One bead ↔ one LLM. Defer 0..N.

**Q4 — Capture intent only; do not build measurement architecture.**
State the intent (optimize human time). Do **not** change the architecture to measure a
human-time unit, pick a unit, or build baseline capture — that can be added later. Acceptance =
the mechanical Definition of Done (binding + reachability demonstrably work), not a measured
human-time number.

---

## Defaults — operator's rulings

**D1 — Keep the refinery (merge gate stays).** **Open, active design question: how are the mayor
and mechanik engaged, conceptually, in this model?** Genuinely unsettled — treat it as a live
question, do not assume today's roles.

**D2 — A node-LLM CAN act on its subtree; this is not a concern.** Slinging an *unslung* bead is
fair game. Creating a bead is fine. (The earlier "read-only subtree" framing was wrong.) The only
thing out of scope is the **declarative-control engine** — continuous *parent-validates-children
reconciliation* — which is a different beast from one-shot sling/create. Node-LLMs use the normal
primitives (sling, create) on their subtree freely.

**D3 — Capability, not deployment.** *Any* bead can get an LLM on demand; *not every* bead has
one. No whole-tree materialization.

**D4 — "context-reachable" is the right framing.** Rename context-complete → context-reachable.
Summarization (parent/child rollups) is a later addition; v1's parent↔child relationship is
fields-on-demand, no summarization.

---

## How to write the rest

The operator found the PRD review and gate questions hard to read. For the design doc and all
operator-facing output: **lead with the answer, use plain language, keep a followable
through-line, don't stack jargon.** Clarity is a deliverable here.

---

## Round-2 feedback (2026-06-06, after re-reading the review) — AUTHORITATIVE

**Drop "single-writer-per-node rule."** The review raised it; the operator rejects it: it is
unclear what is even being *written* at a node that would conflict. There is no concrete
write-contention in the 1:1-binding + slung-mol model, so this is not a v1 concern. Do not carry it.

**Drop the "four conflated humans / seat the payer" framing.** The stakeholders leg *invented* a
"payer" stakeholder that appears nowhere in the source brief — it is review over-reach, not a real
requirement. This is N=1 (one operator who is every role). Do not separate stakeholders; do not
treat cost-ownership as a v1 design concern.

**The core pieces the design must deliver (operator's crystallization — this is the spine):**
1. **A conversation tied to a bead, with create / suspend / resume lifecycle.** A bead-bound
   conversation that can be created, suspended, and later *resumed* — not drained-and-gone.
2. **The prompt/context that conversation gets** (on create and on resume). What goes into the
   prompt = the bead's reachable context (the bead "body" + the scoped fed slice). This IS the
   context-reachable question, stated concretely.
3. **See what's available** — the gc-attention.sh evolution (rank what needs attention →
   pick-a-row → create/resume that bead's conversation). This is the piece that needs net work.

Everything else (proactive-via-slung-mol, mayor/mechanik re-engagement) hangs off this spine and
is secondary. Keep the design centered on these three.
