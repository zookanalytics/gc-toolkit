# Consult-family retirement (tk-fi68i)

**Decision (operator, 2026-06-10):** the consult-host / concierge family
is dead — not in production, not staying. The bead-universe surface no
longer depends on it; PR #104 replaced the last live tie
(`consult-attach.sh`) with `assets/scripts/tmux-switch-to-session.sh`.

**Decision (operator, 2026-06-10, on PR #106 review):** the `architect`
agent — the consult *producer*, born in the same commit as `concierge`
(`9abc02a agents: add architect + concierge (v1 consult-surfacing)`) and
engaging entirely through consult beads — is retired too, completing the
consult-family retirement. Retiring the surfacer (`concierge`) and host
(`consult-host`) while keeping the producer was incoherent. The architect
was never deployed in any `city.toml`. Operator rationale: the core idea
may be worth revisiting later, but having it committed into core caused
more confusion than it solved; the design is preserved in git history (and
in this report) for any future revisit.

This bead inventoried every reference to `consult-host`, `concierge`,
`consult-attach`, and `mol-consult-host`, then removed the self-contained
cluster; a follow-on round removed the architect agent itself as the
consult producer. Inventory found **335 references across 31 files** at
branch start — far broader than the five listed targets — so this report
records what was removed, what was updated, what was deliberately left, and
why.

PR #106 removed the consult-host / concierge cluster (`b044f1d`), then
retired the architect's remaining live-surface references and the roadmap
mentions (`9dcb69d`, addressing the first codex review), and removed the
architect agent itself — the consult producer — completing the family
retirement. Later commits re-sync this audit report with the PR head as
subsequent reviews land (this paragraph's own correction among them), so
they touch no shipped code. This report reflects the current PR head.

## Removed

| Path | Kind | Note |
| --- | --- | --- |
| `agents/concierge/` | agent dir | listed target |
| `agents/consult-host/` | agent dir | listed target |
| `formulas/mol-consult-host.toml` | formula | listed target |
| `assets/scripts/consult-attach.sh` | script | listed target (replaced by `tmux-switch-to-session.sh`) |
| `specs/2026-04-consult-design/` | design doc | listed target |
| `agents/architect/` (`PROVENANCE.md`, `agent.toml`, `prompt.template.md`) | agent dir | the consult *producer*; removed this round (see lead decision). Never deployed in any `city.toml`; auto-discovered by directory with no load-time wiring (no formula, order, keybinding, or `city.toml` import names it), so deleting it is load-safe. `prompt.template.md` had its concierge routing scrubbed in `9dcb69d` before deletion. The fourth file, `consult-layer.md`, was removed earlier as a dead satellite (next row) |
| `agents/architect/consult-layer.md` | dead satellite | only `consult-host` read it at runtime (`LAYER=.../agents/$SPECIALIST/consult-layer.md`); the architect's own prompt never `{{ template }}`-included it, so it was dead once `consult-host` was gone — removed in the cluster commit, ahead of the agent-dir removal |
| `template-fragments/mayor-concierge-redirect.template.md` | dead satellite | invoked **only** by the deleted `agents/concierge/example-city.toml` (`append_fragments = ["mayor-concierge-redirect"]`); not wired by gc-toolkit's own `pack.toml` mayor patch nor by any live `city.toml` |
| `pack.toml` (comment) | wiring | dropped `concierge, consult-host` in `b044f1d`, then `architect` this round, from the native-agents list comment |

The two satellites are not in the original five-item target list but are
unambiguous cluster artifacts whose only consumers were the deleted
agents. Removing them in the cluster commit cleared those references
without editing the architect prompt — which the follow-up commit then
scrubbed of concierge routing (see *Updated in place* below), and which a
later round removed outright along with the rest of the agent dir (see
*Removed* above).

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

That follow-up edit (`9dcb69d`) stayed within mechanical retirement: it
removed routing to a now-absent agent rather than redesigning the consult
model. The architect prompt has since been removed outright with the rest
of the agent dir (see *Removed* above), so its `9dcb69d` delta is now of
historical interest only. A later round reframed `docs/roadmap.md` again —
marking the architect and the whole consult model retired from core — so
its cluster-term mentions are all past-tense retirement notes that
document this removal and point here, the "intentionally-kept historical
mention" the verify criteria allow.

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
- **The architect removal is load-safe too.** The architect was
  auto-discovered by directory with no load-time wiring — no formula,
  order, keybinding, or `city.toml` import named it — and was never
  deployed in any `city.toml`. Deleting `agents/architect/` removes no
  referenced agent, so `gc` loads with no missing-agent error. The nearest
  keeper, `agents/_polecat-gemini/prompt.template.md`'s
  `{{ template "architecture" . }}`, resolves the `architecture` named
  template from the gastown base pack — not the architect agent — and is
  unaffected.

## Deliberately left in place (STOP-and-report)

Per this bead's Step 1 ("if a reference is load-bearing — would break
`gc` pack load, another live agent, or a keybinding — STOP and report
rather than ripping it out"), the references below were **not** removed.
None breaks pack load (verified above); each is a non-load-bearing
sub-pack reference or an immutable historical record. (The two live
surfaces originally listed here — the architect prompt and the roadmap —
were retired by the follow-up commit; the architect prompt has since been
removed entirely with the agent dir. See *Updated in place* and *Removed*
above.)

### 1. `packs/gascity-keeper/` — separate opt-in sub-pack

`agents/keeper/prompt.template.md` (a "Concierge / consult-host —
neither of these apply" contrast disclaimer), `agents/keeper/PROVENANCE.md`
(design-lineage history), and `formulas/mol-upstream-gc-pr-prep.toml`
(an agent-name example list) name the cluster as prose / provenance /
example references. This is a gascity-fork-specific sub-pack imported
only by the gascity rig; the references are non-load-bearing and largely
historical. Left for a separate sub-pack-scoped cleanup if desired.

### 2. Historical specs — `specs/` design records (16 files)

`tk-1zd25`, `tk-3pr5t`, `tk-husu6`, `tk-my4za`, `tk-oml75`,
`tk-px5od` (4 files), `tk-rw0cb`, `tk-yiwfz.3`, `tk-yw3zb.1`, and the
`specs/bead-universe/` set (`design-doc`, `prd-draft`, `prd-review`,
`human-clarifications`) are immutable historical design docs that
mention the cluster in the context of past work. These are the
"intentionally-kept historical mention[s]" the verify allows; scrubbing
a word from a past design record rewrites history to no benefit.

## Net result

Inventory references dropped from **335 across 31 files** at branch start
to **49 across 16 files** after the cluster removal (`b044f1d`). At the
current PR head — excluding this report's own inventory, which names the
cluster terms throughout by nature — **60 references across 20 files**
remain, all non-load-bearing:

- **`docs/roadmap.md`** (10) — past-tense retirement notes documenting
  this removal and pointing here. The count rose above the cluster-removal
  low because the architect / consult retirement notes added in later
  rounds name `concierge` / `consult-host` while marking them dead; these
  are records, not live wiring.
- **`packs/gascity-keeper/`** (3, across 3 files) — opt-in sub-pack:
  prose / provenance / example mentions.
- **historical specs** (47, across 16 files) — immutable design records
  under `specs/`, spanning the `tk-*` design docs and the
  `specs/bead-universe/` set (§2 above).

These counts are a snapshot of the current head; they shift as this report
and the roadmap notes are reworded, so the durable invariant — not the
number — is what matters: no live `consult-host` / `concierge` / architect
surface remains. The head count is reproducible at any commit via `git grep
-cE 'consult-host|concierge|consult-attach|mol-consult-host' -- .
':!specs/tk-fi68i/consult-retirement.md'` (per-file counts; pipe to `wc -l`
for the line total). The self-contained cluster (agents, formula, script,
design doc, and its two orphaned satellites) is deleted, the architect
agent — the consult producer — is removed in full, and the roadmap marks
the whole consult model retired. The pack loads clean with no
consult-host / concierge / architect deployment.
