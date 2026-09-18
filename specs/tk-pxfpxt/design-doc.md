---
name: Design — Metadata-first bead identity for converse cards
description: How converse and the Helm board should lead with what a bead IS (date opened, a stored short subject label, kind, origin) before any conclusion, and when the dismiss line should appear. Records the design for tk-pxfpxt and the three schema decisions routed to the operator.
---

# Design: metadata-first bead identity for converse cards

Record of the design work on tk-pxfpxt, the design-first half of operator
critique tk-qwznjf ("rebuild converse cards metadata-first"). It surveys every
surface that shows a bead's identity to the operator, proposes a design for the
two issues the critique raised, and isolates the three decisions the operator
asked to make before any code lands. Implementation is a follow-up gated on
those decisions; see [Status](#status).

## The two issues

The operator filed tk-qwznjf against a real converse card. Both issues, in their
words:

1. **The headline names a conclusion, not the bead.** *"The title, it's a
   summary of what follows, not the bead. I want to know what sl-kg9z6.3.6 is
   about... A bead ID is the key, but is meaningless to me, so I want to know
   what that bead is. Things like whether I filed it, it's an Epic, what's the
   subject."*

2. **The dismiss line prints even when nothing was closed out.** *"It includes
   the closing bash prompt at the end, but nothing about that final conclusion
   was close out. It's clearly a conversation that needs an action / discussion...
   it feels weird seeing it in this context."*

The card in the example led with `sl-kg9z6.3.6 — the real work shipped; one
stranded duplicate is all that's left.` — a conclusion — and closed with a
`! ... dismiss` line under a card that was asking for a GO/no-go decision.

The operator's direction: derive the bead's identity from its own data, not from
prose an agent rewrites each time. Lead the headline with what the bead is —
date opened, a static short subject label, kind, origin — before any conclusion.
Prefer mechanical rendering wherever the fact is derivable, so it cannot regress.

## Where a bead's identity renders today

Six surfaces show a bead's identity to the operator. Most are in this repo; the
gascity engine (the `gc` binary) owns only `gc session list`, the session popup,
and the raw bead store.

| Surface | Where | How | Leads with |
|---|---|---|---|
| Converse message header | `agents/converse/prompt.template.md:350`, `:433` | prompt-driven | `<id> — <short human label>`, a phrase coined per message |
| Board NEEDS + takeaway | `services/helm/internal/board/derive.go:681`, `services/helm/internal/source/beads.go`; written by `assets/scripts/gc-helm.sh` | mechanical render of a converse-authored string | the takeaway (a conclusion) when present |
| Board sittings headline | `services/helm/web/src/App.tsx:374` | mechanical | `takeaway || title` — the conclusion, else the raw title |
| Drill-in card | `services/helm/web/src/drill/DrillPanel.tsx:50` | mechanical | `<id> · <issue_type> · <status>` — no date, no origin |
| Session title | `skills/session-title/SKILL.md`; converse `prompt.template.md:267` | prompt-driven content, mechanical rename | `<subject> — <topic>` |
| Visit title | `assets/scripts/gc-helm.sh:1646`, `formulas/mol-visit.toml:44` | mechanical template, filer-authored tail | `visit: <id> — <what this visit needs>` |

Two facts shape the design:

- **No bead carries a stored short-label / subject / nickname field.** The one
  human-readable "what this is" phrase converse produces (`<short human label>`)
  is invented per message and never persisted, so every surface either coins its
  own or falls back to the raw `title` or the `gc.takeaway` conclusion. There is
  nothing stable to read.
- **The board renderer is in this repo** (`services/helm/`), so the board,
  sittings, and drill-in cards can be made to lead with identity here — this is
  not blocked on a gascity change.

The identity fields the operator named are already derivable, except the label:

- **date opened** — the native `created_at`. Mechanical.
- **kind** — `issue_type` (task/bug/epic); the board also derives
  epic/decision/convoy (`beads.go` `typedAnchorKinds`). Mechanical.
- **origin** — `gc.origin=operator` marks "you filed this"; absence means filed
  another way (`gc-visit-open.sh:319` stamps it, `docs/gascity-human-engagement.md:336`).
  Mechanical, and there is a backfill precedent (`backfill-operator-origin.sh`).
- **static short subject label** — does not exist. This is the new concept.

## The design

### The identity a card leads with

A card's first line states what the bead is, mechanically, before any prose:

```
<id> · <kind> · <origin> · opened <date> — <subject label>
```

- `<kind>` reads `issue_type` (surfacing "epic" where that is the type).
- `<origin>` renders "you filed this" when `gc.origin=operator`, and is omitted
  otherwise (one value exists today; absence is not a second label).
- `opened <date>` formats `created_at`.
- `<subject label>` is the new stored field below; absent, the renderer falls
  back to `title` and says it did, so it degrades and never blanks.

The conclusion — what the sitting found, what is needed — moves to the body,
below this line, where the operator's existing framing already puts it.

### The new stored field: the static short subject label

A short noun phrase naming what the bead is about — the subject — distinct from
`title` (often long or a truncated escalation subject) and from `gc.takeaway` (a
conclusion). For the example bead it would read like "screen-reader settledness
work", not "the real work shipped".

- **Stored as bead metadata**, written once and reused wherever the bead is
  referenced. A renderer reads it; a renderer never writes it, so it cannot
  regress to a conclusion.
- **Editable but static**: refined only by a deliberate write (operator or a
  converse sitting), never on a render pass.

The field name, who writes it and when, and the backfill policy are the operator
decisions in [Open decisions](#open-decisions); the recommendation is there.

### Making the render mechanical

Identity that "cannot drift" means code emits it, not an LLM. The recommended
shape reuses the pack's existing pattern of small `converse-*.sh` helpers:

- **`assets/scripts/converse-identity.sh <bead-id>`** (new) reads the metadata
  and prints the identity line above. The converse prompt (steps 5 and 7)
  instructs the agent to run it and place its output verbatim as the header,
  then write the analysis in the body. The label phrase leaves the free-write
  path entirely.
- **The board** leads its sittings headline and drill-in card with the same
  identity: carry `gc.subject_label`, `created_at`, and `gc.origin` through
  `beads.go` → `model.go` → `contract.ts`, and render identity ahead of the
  takeaway (which stays as the NEEDS "what it needs" cell). `App.tsx:374`'s
  `takeaway || title` becomes identity-led.

### The dismiss line

The `! ... dismiss` close-out is deliberate doctrine: it frees a
`max_active_sessions` slot in one keystroke without a second LLM turn
(`docs/gascity-human-engagement.md:594`), which is why converse puts it at the
foot of every framing. The fix is to stop it reading as "this concluded" on a
card that plainly needs a decision, not to remove it (the operator's own note:
prefer reframing over removing).

Rule: the bare close-out appears only on a **genuine close-out** — a sign-off or
an FYI hand-back with no open decision. On a card carrying an open decision, the
same affordance appears as a **labelled control**, distinct from a conclusion,
for example:

```
If you're done here and want to close without replying:
! <path> dismiss --reason "<why>"
```

The one-keystroke slot-release is preserved on every card; what changes is that
a decision card no longer wears a line that reads like its own sign-off. This is
a converse prompt change plus an update to the sentence in
`docs/gascity-human-engagement.md` that says the line rides every framing.

## Open decisions

Each turns on a commitment that is costly to reverse once beads carry the field,
so each is the operator's, with a recommendation.

1. **The field name and contract.** Recommend `gc.subject_label`, a `gc.`
   metadata string, a short noun phrase (≤ ~60 codepoints), one per bead.
   Reversible only by a rename-and-migrate once beads carry it.

2. **Who writes it, and when.** Recommend **write-once, lazily, seeded at
   intake**: `gc-visit-open.sh` stamps it for operator-filed subjects from the
   same derivation it already uses for the title (beside its existing
   `gc.origin` stamp); for every other bead, converse writes it the first time a
   sitting primes the subject, if absent, and reuses it after. This keeps every
   write point in this repo, follows the `gc.origin` precedent exactly, and is
   self-healing. The alternatives — write at `gc bd create` (a gascity change,
   and most beads are machine-created with no good label), or require the
   operator to author it at filing (friction on a keystroke intake) — are worse
   fits.

3. **Backfill policy.** Recommend **no bulk backfill**: lazy write-once labels
   each bead the first time it is conversed about or shown, so the population
   fills without a migration. If the board should show labels on existing rows
   immediately, an optional one-shot `backfill-subject-label.sh` (modelled on
   `backfill-operator-origin.sh`) can derive labels from title/description — but
   a machine-derived label off a stale title is the low-quality identity this
   work exists to replace, so lazy-on-first-touch is preferred.

## Implementation scope

The surfaces a ratified design touches:

- `agents/converse/prompt.template.md` — header runs `converse-identity.sh`; the
  dismiss-line rule.
- `assets/scripts/converse-identity.sh` (+ `.test.sh`) — the mechanical renderer.
- `assets/scripts/gc-visit-open.sh` — seed `gc.subject_label` beside `gc.origin`.
- `services/helm/internal/source/beads.go`, `internal/board/model.go`,
  `web/src/contract.ts`, `web/src/App.tsx`, `web/src/drill/DrillPanel.tsx` —
  carry and lead with the identity fields.
- `skills/session-title/SKILL.md` / converse step 3 — title from the label.
- `docs/gascity-human-engagement.md` — the identity fields and the dismiss rule.
- Optional, deferred: `assets/scripts/backfill-subject-label.sh`.

## Status

Design only. The three decisions above are routed to the operator; implementation
follows a ruling and lands the code across the scope, through the normal
self-review + refinery + merge gate. tk-pxfpxt stays open until then; tk-qwznjf
waits on it.
