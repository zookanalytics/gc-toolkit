---
name: Decision record — where each Bead-Universe v1 citation points after the sweep
description: The per-site ruling for the eight live artifacts that cited specs/bead-universe/design-doc.md as design authority — which keep citing v1, which was repointed to v2, and why the fix was annotation rather than rewriting. Read when asking why a header still names a superseded design, or before changing one of these citations again.
---

# Decision: repointing the Bead-Universe v1 citations (tk-mcyd1)

Eight live (non-`specs/`) artifacts named `specs/bead-universe/design-doc.md`
as their design authority; a broader sweep for the design's *name* found two
more that cite it without the path. That document is Bead-Universe **v1**; its binding
and lifecycle were superseded on 2026-07-29 by `specs/tk-h9pq5/design-doc.md`
(v2, Conversation-as-Continuation-Group), and v1 carried no forward pointer to
it. This record is the per-site ruling and the reasoning behind the instrument.

## The instrument: annotate, do not rewrite

Both design docs are **local-tier** docs (`docs/file-structure.md`, "Two tiers"):
historical record of what was thought, not authority for what is true now. The
no-archiving rule follows from that — a superseded record is not archived,
edited away, or restated. So neither doc's body was rewritten. What was added:

- **v1** gets YAML frontmatter (mandatory on local spec docs per
  `docs/file-structure.md`) plus a supersession banner directly under its H1,
  carrying a retired-vs-stands map by phase and a provenance line for the brief
  that commissioned it (`tk-yrio`, closed 2026-08-22 with
  `gc.superseded_by = tk-mcyd1`).
- **v2** gets an `## Amendments` section recording the three clause-level
  deltas already decided elsewhere, plus two inline markers at the clauses a
  reader could act on.

Once v1 carries the banner, following *any* of the eight citations lands the
reader on the map. The per-site edit therefore only has to add what the banner
cannot know: which phase the site implements, and whether that phase survived.

## What v2 actually superseded

v2 scopes itself to the **binding and lifecycle**. It retires v1's Phase 1 /
Key Components 1–2 — `agents/bead-host/*`, the per-bead session, the
`hosts_bead`/`host_session`/`gc.session_lineage` link, warm-while-live
grounding — and replaces them with `gc.continuation_group = <subject-bead-id>`
plus a filed bead per turn, run by `agents/converse/`. It **rewires** Phase 3
(the board survives; pick-a-row files-or-attaches a visit instead of resuming a
host). It does **not** touch Phase 2 (the universe slice) or Phase 4
(proactive-via-slung-mol).

## Per-site ruling

| Site | Implements | Ruling |
|---|---|---|
| `agents/proactive/PROVENANCE.md` | Phase 4 / KC 5–6 | **Keeps v1** + supersession pointer |
| `agents/proactive/agent.toml` | Phase 4 / KC 5–6 | **Keeps v1** + supersession pointer |
| `formulas/mol-first-reaction.toml` | Phase 4 / KC 5–6 | **Keeps v1** + supersession pointer |
| `tools/gc-proactive.sh` | Phase 4 / KC 5–6 | **Keeps v1** + supersession pointer |
| `tools/proactive-first-reaction-fixture.sh` | Phase 4 gate | **Keeps v1** + supersession pointer |
| `tools/gc-bd-universe.sh` | Phase 2 / KC 3 + Data Model | **Keeps v1** + supersession pointer, and names v2 as the reason its consumer is a converse session |
| `tools/bead-universe-reachability-fixture.sh` | Phase 2 gate | **Keeps v1** + supersession pointer |
| `tools/helm-surface-fixture.sh` | Phase 3 surface | **Repointed to v2** — v1 named as origin only |
| `assets/scripts/tmux-bindings.sh` † | Phase 3 surface | **Repointed to v2**, and the retired mechanism it described corrected |
| `assets/scripts/tmux-pick-helm.sh` † | Phase 3 surface | **Repointed to v2**, and the retired mechanism it described corrected |

† **Two sites beyond the eight.** The audit found its eight by grepping the
doc *path*; these two cite the same design by name, phase and Key Component
without the path, so the grep missed them. They are worse than a stale
citation — both described v1's retired mechanism as live behavior ("pick a row
and it resumes-or-materializes that bead's resident host"), and
`tmux-bindings.sh` still listed the removed *flagged* anchor kind. The live
verb files a visit and the board has six anchor kinds
(`assets/scripts/gc-helm.sh`). Fixed here because leaving them would let this
sweep report that no live artifact traces to a retired authority while two
still did.

## What was found but deliberately not fixed

`assets/scripts/tmux-pick-helm.sh` does not merely *describe* the retired
per-bead host — it **branches on it**. The picker reads a `live`
(hot/warm/cold) field that `gc-helm.sh` explicitly no longer emits ("There is
no `live` … host field — the visit/converse spine is the only conversation
mechanism, and `held` is its one glyph fact"), so `.live//"cold"` always reads
cold: every row opens in the background and the `●`/`◐` glyph branches are
unreachable.

That is a behavior question, not a citation one — which rows deserve a
foreground attach under group-shaped liveness, and whether the glyph should be
driven by `held`, is a UX call the sweep has no standing to make. Filed as
**tk-5cy6g**; the dead branch is annotated in place and left running, because
backgrounding is the safe arm.

Seven keep v1 because v1 is still the design that governs them; citing a live
implementation to a superseded doc is only wrong when the *cited part* was
superseded. The eighth is the one site whose cited part was rewired: the
fixture already asserts visit presence for the held glyph — a v2 mechanism —
so v2, not v1, is what it scores against.

`tools/helm-surface-fixture.sh` also lost its v1 flag scenarios outright: the
`gc.attention` flag was removed by operator decision 2026-08-08
(`specs/2026-08-fresh-start/attention-flag-removal.md`), which that sweep
already applied to the file's body. Only the header still pointed at v1.

## Why the v2 amendments include more than `gc.attention`

The bead asked for one correction in v2 — the `gc.attention` clause. An
`## Amendments` section that recorded only that would read as a complete list
of the doc's deltas while omitting deltas already on the record, so two more
were folded in, each a decision made elsewhere and cited to it, with no new
judgment:

1. **`gc.attention` flag removed** (2026-08-08). Supersedes Key Component 6's
   "the flag … is unchanged" clause; the hand-raise is now a filed visit. The
   board itself survived, so the doc's four other `gc.attention board`
   mentions are a stale *name* for a live surface, not a wrong direction.
2. **No reaper-skip clause was built** (`specs/2026-08-fresh-start/spine-port.md`
   D4, which asks in its own text for Q1's resolution to be rewritten to that
   ground truth).
3. **"turn" is now "visit"**, and "conversation" was demoted from the technical
   vocabulary (same record's 2026-08-08 addendum; glossary in
   `docs/gascity-human-engagement.md`). v2's body says "turn" throughout.

## The cost this closes

`specs/tk-z9nln/divergence-record.md` (D1) records the measured failure: that
audit censused v1 artifact-by-artifact, found each absent, and concluded the
model was outlived — then had to spend its opening effort overturning its own
premise. The capabilities had shipped under other names because a pack cannot
add subcommands to the `gc` Go binary (`gc attention open`, `gc bd universe
--slice`, `gc bead-host` became `tools/`-level scripts) and because v2
deliberately renamed the lifecycle. That inference — v1 name absent, therefore
capability absent — is now refused explicitly in v1's banner.
