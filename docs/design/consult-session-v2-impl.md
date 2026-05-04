# Session-per-Consult v2 — As-Built Implementation

**Status:** implemented. Shape A (direct tmux attach, brand
evaporates in-session).
**Beads:** tk-7ky (this implementation), tk-bek (feasibility study),
tk-89y (v1 conversational concierge — prerequisite, merged in tk-1pf).
**Audience:** overseer, mechanik, architect; future consult-producing
specialists; future maintainers reading why this shape and not
another.

This document describes what shipped. It is **not** a redesign of the
feasibility study (`docs/design/consult-session-feasibility.md`); it
records the implementation choices made within the shape that study
proposed and the overseer approved. Read the feasibility doc first if
you need the *why*; read this doc to understand what's in the pack
today.

## 1. What this changes

The v1 concierge (shipped in tk-1pf) is the consult-surfacing surface:
push on create, pull on engagement, hold the conversation in its own
context, write the resolution to the bead. v2 splits the work:

- **Concierge keeps** push-on-create, the consult query, triage
  conversations ("what's open?", "let's look at the review queue"),
  filing-bar gatekeeping, mayor-redirect, and ambiguity policy.
- **Concierge no longer** carries the resolution conversation. When
  the overseer commits to resolving a specific consult, concierge
  spawns a `consult-host` session for that bead and switches the
  overseer's tmux client into it.
- **Consult-host** (a new city-scoped agent template) loads the bead
  in full, composes an opening orientation message, hosts the
  back-and-forth with the overseer directly, files sub-beads when
  side-quests appear, and writes the closing note (or pause note) on
  exit. It is short-lived — fresh spawn every engagement, drains on
  decision or detach.

The v1 design's commitments stay intact: bead-as-conversation-record,
push-on-create cadence, ambiguity policy, mayor-redirect. v2 adds a
session boundary inside the resolution conversation that did not
exist in v1.

## 2. Files in this implementation

| Path | Purpose |
|------|---------|
| `formulas/mol-consult-host.toml` | Three-step formula for the host lifecycle (load-context, host-conversation, capture-decision) |
| `agents/consult-host/agent.toml` | City-scoped, fresh-wake, on-demand-spawn template |
| `agents/consult-host/prompt.template.md` | Generic consult-host prompt: how to read the bead, host the conversation, file sub-beads, capture decisions |
| `agents/architect/consult-layer.md` | Specialist layer fragment for architect-filed consults — adjusts host register, points at central knowledge |
| `agents/concierge/prompt.template.md` | Edited: Engagement Flow now hands off on by-ID resolution; Conversation Guidelines scoped to triage; Resolution section now describes receiving the host's nudge |
| `agents/concierge/example-city.toml` | Adds the `consult-host` named-session stanza |
| `assets/scripts/consult-attach.sh` | Tmux switch-client helper concierge runs after spawning a host |

## 3. Shape A — direct tmux attach

The feasibility study described three relay shapes:

- A — direct tmux attach, brand evaporates in-session
- B — concierge as relay (concierge stays as the surface, submits text
  back-and-forth into the host)
- C — concierge hands off, then gets out of the way (hybrid; needs a
  controlled handoff CLI primitive)

**Shipped: A.** The overseer feedback on the feasibility study
(captured in tk-bek's notes) explicitly approved A on grounds that
concierge's role is *routing*, and what matters when the overseer
attaches is immediate context visibility (project, bead, original
request, trigger), not preserving a brand. Brand evaporation is a
feature here, not a regression.

B was rejected as indirection with no benefit. C was rejected as more
complicated than A for the same outcome — A is cheaper, cleaner, and
buildable on existing primitives without a new handoff CLI.

### How the attach works

```
overseer engages concierge by ID
         │
         ▼
concierge: gc session new consult-host --alias consult-<bead> --no-attach
         │
         ▼
runtime spawns a new consult-host session, alias=consult-<bead>
         │
         ▼
concierge: $GC_CONFIG_DIR/assets/scripts/consult-attach.sh consult-<bead>
         │
         ▼
script: tmux switch-client -t consult-<bead>   (on $GC_TMUX_SOCKET)
         │
         ▼
overseer's tmux client is now attached to the consult-host session
         │
         ▼
host's load-context completes, opening orientation message lands,
host waits for overseer input
```

Cold-start latency: the spawn returns once the runtime accepts it,
but the tmux session may not be registered immediately. The
`consult-attach.sh` helper polls `tmux has-session` for up to 10s
before giving up (40 attempts × 250ms). If it fails, concierge
surfaces the failure; this is preferable to silently leaving the
overseer in concierge while the host waits in the dark.

### Why a switch-client script and not just `gc session attach`

`gc session attach` already exists and works manually (an overseer can
type `gc session attach consult-<bead>` themselves). The script is
about **automation**: concierge runs it inline so the overseer doesn't
have to remember the session alias or type the attach command. The
script is also explicit about waiting for the tmux session to register,
which `gc session attach` does not currently guarantee on a same-tick
spawn.

The manual `gc session attach` path remains available — if the
automatic switch fails or the overseer detached and wants back in,
they can attach by hand. This is the "both" option from the bead:
signal-driven switch for the spawned-and-ready case, CLI for manual.

## 4. Bead context loading and the specialist layer

`mol-consult-host.load-context` is patterned on `mol-do-work` and
`mol-polecat-work`: read the bead with `bd show`, walk dependencies,
read linked artifacts, then proceed. Nothing pre-loaded into the
prompt template; everything read at runtime.

The **specialist layer** is the pack's answer to the feasibility doc's
"per-specialist consult prompt variants" problem. Per the overseer
feedback (no per-specialist variants), the consult-host base prompt
is generic; specialist-specific context lives in
`agents/<specialist>/consult-layer.md`. The host reads the layer if
present:

```bash
SPECIALIST=$(bd show "$CONSULT" --json | jq -r '
    .[0].metadata."gc.consult_filed_by" //
    (.[0].created_by // "" | sub("^.+__"; "") | sub("^.+/"; ""))
')
LAYER="$GC_CONFIG_DIR/agents/$SPECIALIST/consult-layer.md"
[ -n "$SPECIALIST" ] && [ -f "$LAYER" ] && cat "$LAYER"
```

A consult layer is **not** a full specialist prompt. It is a fragment
that adjusts the host's register and points at central knowledge for
that domain (e.g., the architect layer points at `architecture.md`
and `docs/adr/`). The host remains a host; it doesn't adopt the
specialist's full role.

This pack ships one example layer: `agents/architect/consult-layer.md`.
Future consult-producing specialists add their own layer when they
land. The cost-per-specialist is small (one short markdown file); the
"prompt variants per specialist" cost the feasibility doc warned
about is avoided.

## 5. Re-engagement

**Fresh spawn every engagement.** No warm pool, no resumed session
state, no stored context across drains. This applies whether the
overseer comes back in five minutes or five days. The bead is the
source of truth — its notes are the conversation history; a new host
reading the bead has full context.

This also resolves the "single open design question" from the bead
description (re-engagement semantics for both v1 and v2). The same
answer applies on both sides: the bead carries the conversation;
sessions are ephemeral; re-engagement is fresh.

If the overseer detaches mid-conversation without a decision, the
host writes a "Session paused: …" note before draining. The pause
note describes where the conversation left off so the next host
session can pick up.

## 6. Sub-bead nesting

Already a Gas City core primitive — no new machinery in v2. The host
files sub-beads via `bd create … --parent <consult>` and pauses with
`gc session wait --on-beads <sub-bead> --sleep`. The reconciler wakes
the host when the sub-bead closes; the host reads the result and
resumes the conversation.

The host (not concierge) owns the side-quest filing because the host
is the agent in the conversation when the side-quest comes up.
Concierge's prompt edit explicitly redirects mid-conversation
sub-bead filing to the host.

The blocking-vs-parallel choice is presented to the overseer
explicitly, same as the v1 concierge's protocol — only the
*decider* changes (host instead of concierge).

## 7. Decision capture

`mol-consult-host.capture-decision` is the mandatory last step before
`gc runtime drain-ack`. It has two branches:

- **Decision reached.** Host writes a closing note that states the
  resolution explicitly (no inference required from downstream
  readers), runs `bd update <consult> --status=closed`, then nudges
  concierge with the one-line decision before draining.
- **Pause without decision.** Host writes a "Session paused: …" note
  describing where the conversation left off, leaves the bead open,
  nudges concierge that the bead is paused, then drains.

The closing-note shape can be customized per specialist via the
consult layer; `agents/architect/consult-layer.md` proposes a
template (Decision / Rationale / Constraints / Follow-ups) that the
architect's downstream patrol can parse.

The guarantee that the closing note gets written is the same
guarantee polecats give for `submit-and-exit`: the formula step
exists, the prompt makes it the exit criterion, and concierge
verifies on receipt of the close nudge that the bead is closed (or
paused) cleanly.

## 8. What stayed the same

- **Push-on-create cadence.** Concierge still pushes one notification
  per consult on creation. Never more.
- **Filing-bar gatekeeping.** Concierge still rejects below-bar
  consults before they reach the overseer's notification. The host
  inherits a bead that already met the bar.
- **Ambiguity policy.** Concierge still owns ambiguity when the
  overseer's reply could apply to multiple open consults. The host
  only owns one consult, so within-host ambiguity is rare; if the
  overseer's reply seems to be about a different consult, the host
  redirects to concierge.
- **Mayor redirect.** Bidirectional. Unchanged.
- **Bead-as-conversation-record.** Each meaningful turn lands as a
  note. The bead is durable; the session is ephemeral. v2 just moves
  the note-writing into the host instead of concierge.

## 9. What's intentionally not built

- **Concierge-as-relay (Shape B).** Rejected by overseer; not
  implemented. If experience reveals A-attach is too heavy, B can be
  added later by adding a relay branch to concierge's engagement flow
  — but the host primitive stays the same.
- **Controlled handoff CLI (Shape C).** Not built. A `gc session
  handoff` would be needed for C; A doesn't need it. If C ever
  becomes desirable, it's an additive CLI on top of the existing
  host primitive.
- **Warm session pools.** Lazy spawn only. Cold-start latency
  (~2-10s, mitigated by the polling helper) is acceptable in
  exchange for the simpler lifecycle. Revisit if engagement feel
  suffers.
- **Multi-specialist host prompt variants.** No per-specialist host
  prompts. Specialist context is a layer (`consult-layer.md`), not a
  variant.
- **Cross-rig surface (Slack, webhook).** Local tmux + bead notes
  only. Concierge's notification payload remains structured enough
  that a future webhook forwarder can be added downstream.

## 10. Operational notes

- The consult-host template is registered via `[[named_session]]
  template = "consult-host"` (no `mode = "always"`) so it spawns
  on-demand when concierge invokes `gc session new consult-host`.
- `agents/consult-host/agent.toml` sets `min_active_sessions = 0,
  max_active_sessions = 10`. Cities that juggle many parallel
  consults can patch the cap upward; cities that want hard-cap
  throttling can patch it down.
- `idle_timeout = "30m"` is shorter than concierge's 2h: a host that
  has been idle for half an hour without a decision should drain so
  the bead's pause note (or a new fresh spawn) takes over.
- `consult-attach.sh` honors `$GC_TMUX_SOCKET`; same convention as
  the existing `tmux-bindings.sh` and `tmux-pick-session.sh` scripts.

## 11. References

- `docs/design/consult-surfacing.md` — v1 concierge design.
- `docs/design/consult-session-feasibility.md` — v2 feasibility study;
  the *why* behind these choices.
- `formulas/mol-consult-host.toml` — the formula.
- `agents/consult-host/prompt.template.md` — the generic host prompt.
- `agents/architect/consult-layer.md` — the example specialist layer.
- `agents/concierge/prompt.template.md` — the edited concierge prompt.
- `agents/concierge/example-city.toml` — example wiring with v2.
- `assets/scripts/consult-attach.sh` — tmux switch helper.
- `formulas/mol-do-work` and `mol-polecat-work` (gastown pack) —
  reference templates the formula was patterned on.
