---
name: city-scoped-role bare-create audit
description: The full set of bead-creation sites reachable from city-scoped roles (deacon, dog, mechanik), each classified as rig-scoped (safe) or a city-store leak, and the disposition of each. The record behind tk-b10zrc.
---

# City-scoped role bare-create audit

## Mechanism

`gc bd create` and `gc convoy create` choose their store by this order:
`--rig` flag, then the cwd's rig, then `GC_RIG`, otherwise the city store
(confirmed in `gc convoy create --help`). `gc bd` does not refuse an
unresolved rig — it warns and writes to the ambient store.

A **city-scoped** role runs with `GC_RIG` unset from the city path, so an
unqualified create resolves to the city (HQ / `lx-`) store. A **rig-workable**
bead placed there — a task/bug meant for a rig's polecat pool — is unclaimable:
the pool reads only its rig store, so the bead maroons. The two safe forms for a
rig-less caller are to name the rig (`gc bd --rig <rig>`, `gc convoy create
--rig <rig>`) or to route through a helper that binds `GC_RIG` first
(`assets/scripts/patrol-finding.sh`, `assets/scripts/escalate.sh` via
`assets/scripts/escalation-rig.sh`).

Not every city-store create is a leak. A warrant (routed to the city-scoped
`dog` pool), a deacon incident ledger, an operator-review decision, and a
board visit belong in the city store by design. The leak is specifically a
**rig-workable defect or work bead** left unscoped.

## The set: which roles run city-scoped

The scope is declared per agent, and enumerating it — not grepping create
call sites — is the authoritative sweep, because the same `gc bd create` is
safe under a rig-scoped caller and a leak under a city-scoped one. From each
`agents/<role>/agent.toml` and the `[[named_session]]` stanzas in `pack.toml`:

| Role | Scope | Notes |
|---|---|---|
| deacon | city | named singleton, always |
| dog | city | warrant-executor pool |
| mechanik | city | named singleton, always |
| refinery, witness, polecat, polecat-codex, proactive, converse(-*) | rig | GC_RIG bound |

`mayor` is retired: no `agents/mayor/`, no formula, no script. Its former
board duties are the operator's through `assets/scripts/gc-helm.sh`, which is
rig-scoped (it exports `GC_RIG` from the subject bead's rig before any visit
create; e.g. `gc-helm.sh:1615-1621`).

## Site-by-site disposition

### deacon — SAFE

- `formulas/mol-deacon-patrol.toml:241,336,370` — findings via
  `patrol-finding.sh`, each preceded by `ESC_RIG="${GC_RIG:-gc-toolkit}"` and
  invoked `GC_RIG="$ESC_RIG" patrol-finding.sh ...`. `patrol-finding.sh:121-126`
  binds `GC_RIG` (from `--rig`, else the default rig) before its create, so the
  finding lands in a rig store, deduped, and is handed to the first reaction.
- `formulas/mol-deacon-patrol.toml:405` — a **warrant** for the dog. City store
  by design: a warrant is not rig-workable, it is routed to the city-scoped
  `dog` pool (`mol-dog-shutdown-dance.toml:14-17`).
- `assets/scripts/gc-deacon-ledger.sh:153` — the incident ledger. The script
  deliberately `unset GC_RIG` (`:80`) and documents the city store as
  intentional (`:22-28`). The ledger is a city-wide operational record, not a
  rig defect.
- `agents/deacon/prompt.template.md:119,141` — findings via `patrol-finding.sh`
  with `GC_RIG` bound, and an emergency visit via
  `escalation-rig.sh` → `escalate.sh` (rig derived from the subject).

### dog — SAFE (gc-toolkit) / cross-repo (gascity stale-db path)

- `formulas/mol-dog-shutdown-dance.toml:80,156,185` — every escalation binds
  `GC_RIG="$ESC_RIG"` from `escalation-rig.sh` and no-ops rather than filing
  when the rig cannot be derived.
- `formulas/mol-dog-shutdown-dance.toml:17` — a warrant create, shown inside a
  documentation block, not executed; city store by design as above.
- `assets/scripts/dance-probe.sh`, `assets/scripts/boot-health.sh` — the
  dog-invoked scripts. Neither contains any `bd create`; `boot-health.sh` is
  report-only (`gc mail send`), `dance-probe.sh` only interrogates sessions.
- **`mol-dog-stale-db` — the `lx-ja517n` exemplar. Cross-repo; no in-pack fix.**
  This formula lives in the gascity repo
  (`rigs/gascity/examples/bd/dolt/formulas/mol-dog-stale-db.toml`), not in this
  pack, and it contains **no `bd create`**: it reports through `gc event emit`,
  `append_report_note` (a `bd update` on its own work bead), and
  `send_escalation` (escalate.sh or `gc mail send`). `lx-ja517n` was filed by
  the dog pool session as an ad-hoc bug report — a diagnosis of the formula's
  claim-guard close loop — and landed in the city store because the dog runs
  city-scoped. So there is no scripted rig-defect create to rescope here; the
  formula's own bug is tracked by tk-k0zue3, and a rig-less bead marooned by an
  ad-hoc create is what the doctor backstop (tk-ungwb4) is built to catch.

### mechanik — LEAK, fixed here

The mechanik dispatches work to rig polecat pools but runs city-scoped, so its
dispatch-bead creates default to the city store where the target pool cannot
claim them. `agents/mechanik/prompt.template.md`:

- The owned-convoy dispatch doctrine created the convoy and the child work bead
  without naming a rig, then slung the work bead to `<rig>/…polecat`. Fixed:
  both creates now carry `--rig <rig>` (the rig slung to), and the doctrine
  states the store-scoping invariant.
- The scope-miss recovery filed a supplement work bead routed to `<rig>/…polecat`
  without naming a rig. Fixed: the supplement is created with `gc bd --rig <rig>`.
- The `-t decision` create in Communication is left as-is: a decision for
  operator review belongs in the city store.

### Shared helper note

`assets/scripts/finding.sh:230` is a bare `gc bd create` with no rig handling.
It is safe only because every caller is rig-scoped (`signoff.sh`, the validator,
`gate-ensure.sh` — `finding.sh:59-63`); a city-scoped caller routed through it
would leak. Contrast `patrol-finding.sh`, which binds `GC_RIG` and is the
correct entry point for a rig-less caller. No change: no city-scoped role reaches
`finding.sh` today.

## Related beads (converse tk-evszjm)

- tk-k0zue3 — the `mol-dog-stale-db` claim-guard close loop (the `lx-ja517n`
  content bug), re-homed from HQ to gc-toolkit.
- tk-ungwb4 — the doctor backstop that flags any rig-workable bead marooned in
  the city store (the catch-all detector for paths not enumerated here).
- tk-e3uck5 — `escalation-rig.sh` returning a city-store name `GC_RIG` ignores.
- tk-48ru7 — the pattern that the named site is the minimum, not the scope;
  the reason this audit enumerates the whole city-scoped set rather than only
  the dog.
