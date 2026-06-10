# Consult-host / concierge cluster retirement (tk-fi68i)

**Decision (operator, 2026-06-10):** the consult-host / concierge family
is dead — not in production, not staying. The bead-universe surface no
longer depends on it; PR #104 replaced the last live tie
(`consult-attach.sh`) with `assets/scripts/tmux-switch-to-session.sh`.

This bead inventoried every reference to `consult-host`, `concierge`,
`consult-attach`, and `mol-consult-host`, then removed the self-contained
cluster. Inventory found **335 references across 31 files** — far broader
than the five listed targets — so this report records what was removed,
what was updated, what was deliberately left, and why.

PR #106's substantive changes are two commits: the cluster removal
(`b044f1d`) and a follow-up (`9dcb69d`) that — addressing the first codex
review — retired the remaining live-surface references in
`agents/architect/prompt.template.md` and `docs/roadmap.md`. Later commits
re-sync this audit report with the PR head as subsequent reviews land
(this paragraph's own correction among them), so they touch no shipped
code. This report reflects the current PR head.

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
agents. Removing them in the cluster commit cleared those references
without editing the governed architect prompt — which the follow-up
commit then retired separately (see *Updated in place* below).

## Updated in place (follow-up commit `9dcb69d`)

The first codex review flagged two non-historical references as blocking:
the live architect prompt still routed to `concierge`, and the roadmap
still presented the channel as current with links to deleted paths. Both
are the references the original pass had left for follow-up; the
follow-up commit retired them.

| Path | Change | Refs |
| --- | --- | --- |
| `agents/architect/prompt.template.md` | Dropped all routing to the deleted `concierge` agent — the "Concierge pushes; you file" framing, the `Concierge` collaborator subsection, the `gc mail send` / `gc session nudge concierge` push channels, and the concierge session-end checklist item; reworded the filing-bar / kick-back prose. Consults now surface via the bead queue — the model the prompt already declares authoritative ("open/closed bead state is the state"). | 12 → 0 |
| `docs/roadmap.md` | Marked the consult-surfacing channel **retired (2026-06-10)** in all three locations (narrative pillar, Settled decision, Near-term milestone 5) and removed the dangling links to deleted paths (`specs/2026-04-consult-design/`, `template-fragments/mayor-concierge-redirect.template.md`, `agents/concierge/example-city.toml`); points readers to this report instead. | 10 → 5 |

The architect-prompt edit stayed within mechanical retirement: it removes
routing to a now-absent agent and leans on the bead-queue surfacing the
prompt already declared authoritative, rather than redesigning the
consult model. The roadmap's surviving five references are now past-tense
retirement notes that document this removal (and point here) — the
"intentionally-kept historical mention" the verify criteria allow.

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
rather than ripping it out"), the references below were **not** removed.
None breaks pack load (verified above); each is a non-load-bearing
sub-pack reference or an immutable historical record. (The two live
surfaces originally listed here — the architect prompt and the roadmap —
were retired by the follow-up commit; see *Updated in place* above.)

### 1. `packs/gascity-keeper/` — separate opt-in sub-pack

`agents/keeper/prompt.template.md` (a "Concierge / consult-host —
neither of these apply" contrast disclaimer), `agents/keeper/PROVENANCE.md`
(design-lineage history), and `formulas/mol-upstream-gc-pr-prep.toml`
(an agent-name example list) name the cluster as prose / provenance /
example references. This is a gascity-fork-specific sub-pack imported
only by the gascity rig; the references are non-load-bearing and largely
historical. Left for a separate sub-pack-scoped cleanup if desired.

### 2. Historical specs — `specs/tk-*/` (11 files)

`tk-1zd25`, `tk-3pr5t`, `tk-my4za`, `tk-px5od` (5 files), `tk-rw0cb`,
`tk-yiwfz.3`, `tk-yw3zb.1` are immutable historical design docs that
mention the cluster in the context of past work. These are the
"intentionally-kept historical mention[s]" the verify allows; scrubbing
a word from a past design record rewrites history to no benefit.

## Net result

Inventory references dropped from **335 across 31 files** at branch start
to **49 across 16 files** after the cluster removal, then to **32 across
15 files** at the PR head once the follow-up retired the architect-prompt
and roadmap references. The remaining 32 fall in three non-load-bearing
buckets:

- **`docs/roadmap.md`** (5) — past-tense retirement notes documenting
  this removal and pointing here.
- **`packs/gascity-keeper/`** (3, across 3 files) — opt-in sub-pack:
  prose / provenance / example mentions.
- **historical specs** (24, across 11 files) — immutable design records.

No live `consult-host` / `concierge` surface remains: the self-contained
cluster (agents, formula, script, design doc, and its two orphaned
satellites) is deleted, the architect prompt no longer routes to a
removed agent, and the roadmap marks the channel retired. The pack loads
clean with no consult-host / concierge deployment.
