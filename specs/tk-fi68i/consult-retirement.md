# Consult-host / concierge cluster retirement (tk-fi68i)

**Decision (operator, 2026-06-10):** the consult-host / concierge family
is dead — not in production, not staying. The bead-universe surface no
longer depends on it; PR #104 replaced the last live tie
(`consult-attach.sh`) with `assets/scripts/tmux-switch-to-session.sh`.

This bead inventoried every reference to `consult-host`, `concierge`,
`consult-attach`, and `mol-consult-host`, then removed the self-contained
cluster. Inventory found **335 references across 31 files** — far broader
than the five listed targets — so this report records what was removed,
what was deliberately left, and why.

## Removed

| Path | Kind | Note |
| --- | --- | --- |
| `agents/concierge/` | agent dir | listed target |
| `agents/consult-host/` | agent dir | listed target |
| `formulas/mol-consult-host.toml` | formula | listed target |
| `assets/scripts/consult-attach.sh` | script | listed target (replaced by `tmux-switch-to-session.sh`) |
| `specs/2026-04-consult-design/` | design doc | listed target |
| `agents/architect/consult-layer.md` | dead satellite | only `consult-host` read it at runtime (`LAYER=.../agents/$SPECIALIST/consult-layer.md`); the architect's own prompt never `{{ template }}`-includes it, so it is dead once `consult-host` is gone |
| `template-fragments/mayor-concierge-redirect.template.md` | dead satellite | invoked **only** by the deleted `agents/concierge/example-city.toml` (`append_fragments = ["mayor-concierge-redirect"]`); not wired by gc-toolkit's own `pack.toml` mayor patch nor by any live `city.toml` |
| `pack.toml` (comment) | wiring | dropped `concierge, consult-host` from the native-agents list comment |

The two satellites are not in the original five-item target list but are
unambiguous cluster artifacts whose only consumers were the deleted
agents. Removing them is the only way to clear those references without
touching the governed architect prompt below.

## Load-safety verification (why this does not break the engine)

- **No live deployment.** Neither the city root `city.toml`
  (`/home/zook/loomington/city.toml`) nor any rig wires `concierge` /
  `consult-host` as a `[[named_session]]`, and nothing appends
  `mayor-concierge-redirect`. The cluster shipped in the pack but was
  **never deployed** in any running city, so deleting it stops no
  running agent.
- **No load-time references.** No surviving `agent.toml` names these
  agents or `mol-consult-host` as a formula/pour; no `orders/` entry
  references them; no `append_fragments` / `inject_fragments_append`
  references the deleted fragment outside the deleted concierge example.
  The pack auto-discovers agents/formulas by directory, so deleting the
  dirs is sufficient — `gc` loads with no missing-agent / missing-formula
  error.

## Deliberately left in place (STOP-and-report)

Per this bead's Step 1 ("if a reference is load-bearing — would break
`gc` pack load, another live agent, or a keybinding — STOP and report
rather than ripping it out"), the following references were **not**
removed. None breaks pack load (verified above); each is either a
governed live-agent surface or a historical record.

### 1. `agents/architect/prompt.template.md` — governed live agent

The **architect is a live agent that stays** (not in the target list).
Its prompt weaves `concierge` into its core consult-surfacing
engagement model: "Concierge pushes; you file" (≈L70), the filing bar
(≈L90), the kick-back behavior (≈L103), the `Concierge` collaborator
subsection (≈L341), the `gc mail send concierge` / `gc session nudge
concierge` push channels (≈L410), and the session-end checklist (≈L425).

Crucially, the architect prompt itself states (≈L401) that **architect
role/prompt updates are "proposed via mechanik"** — they are governed,
not unilaterally editable by a polecat. Removing concierge from the pack
makes these references stale (the push now targets a removed agent, but
since concierge was never deployed the push was already a no-op, so
nothing actively breaks).

**Recommended follow-up:** a mechanik-proposed change to the architect
prompt to redesign how the architect surfaces consults to the overseer
now that the concierge push channel is retired (push the overseer
directly? rely on bead polling?). That is a design decision for the
architect owner, not mechanical dead-code deletion.

### 2. `docs/roadmap.md` — vision narrative

The gc-toolkit roadmap describes the consult-surfacing channel as a
"Decided" pillar and a landed "Near-term" milestone, and links to the
now-deleted `specs/2026-04-consult-design/` (those links now dangle).
Rewriting the roadmap's forward-looking review-leg / architect vision to
represent the retirement is a roadmap/product decision beyond a
dead-code deletion. **Recommended follow-up:** a roadmap-update pass
(doc-keeper / mechanik) to mark consult-surfacing retired and fix the
dangling spec links.

### 3. `packs/gascity-keeper/` — separate opt-in sub-pack

`agents/keeper/prompt.template.md` (a "Concierge / consult-host —
neither of these apply" contrast disclaimer), `agents/keeper/PROVENANCE.md`
(design-lineage history), and `formulas/mol-upstream-gc-pr-prep.toml`
(an agent-name example list) name the cluster as prose / provenance /
example references. This is a gascity-fork-specific sub-pack imported
only by the gascity rig; the references are non-load-bearing and largely
historical. Left for a separate sub-pack-scoped cleanup if desired.

### 4. Historical specs — `specs/tk-*/` (10 files)

`tk-1zd25`, `tk-3pr5t`, `tk-my4za`, `tk-px5od` (5 files), `tk-rw0cb`,
`tk-yiwfz.3`, `tk-yw3zb.1` are immutable historical design docs that
mention the cluster in the context of past work. These are the
"intentionally-kept historical mention[s]" the verify allows; scrubbing
a word from a past design record rewrites history to no benefit.

## Net result

Inventory references dropped from **335 across 31 files** to **49 across
16 files** — all 16 are in the four call-out categories above. The
self-contained cluster (agents, formula, script, design doc, and its two
orphaned satellites) is gone; the pack loads clean with no live
consult-host / concierge deployment remaining.
