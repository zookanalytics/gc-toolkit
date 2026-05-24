---
name: Gas Town Molecule Catalog
description: Per-source survey of Gas Town's mol-*.toml ecosystem (formulas) and adjacent pack artifacts, for the gc-toolkit ecosystem-skills audit (tk-1k0fay).
---

# Gas Town Molecule Catalog

| Doc-type or artifact | Producer (skill / concept / workflow step that emits it upstream) | Source location (URL or repo path + commit SHA) | Surveyed at |
|---|---|---|---|
| Pack manifest | `pack.toml` at pack root — declares pack name, imports, global hooks, named_session templates | `rigs/gascity/examples/gastown/packs/gastown/pack.toml@9a01227` | 2026-05-24 |
| Molecule formula (work lifecycle, polecat feature-branch variant) | `mol-polecat-work` — extends `mol-polecat-base`, poured by `gc sling` onto polecat agents | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-polecat-work.toml@9a01227` | 2026-05-24 |
| Molecule formula (deacon patrol loop) | `mol-deacon-patrol` — poured as root-only wisp by deacon agent at startup; self-pours next iteration | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-deacon-patrol.toml@9a01227` | 2026-05-24 |
| Molecule formula (witness patrol loop) | `mol-witness-patrol` — poured as root-only wisp by witness agent per rig | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-witness-patrol.toml@9a01227` | 2026-05-24 |
| Molecule formula (refinery patrol loop) | `mol-refinery-patrol` — poured as root-only wisp by refinery agent per rig | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-refinery-patrol.toml@9a01227` | 2026-05-24 |
| Molecule formula (digest generation) | `mol-digest-generate` — periodic formula dispatched by deacon `periodic-formulas` step on cooldown, executed by dog pool | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-digest-generate.toml@9a01227` | 2026-05-24 |
| Molecule formula (idea-to-plan pipeline) | `mol-idea-to-plan` — coordinator-poured planning workflow that fans out review legs | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-idea-to-plan.toml@9a01227` | 2026-05-24 |
| Molecule formula (generic review-leg) | `mol-review-leg` — dispatched by `mol-idea-to-plan` (or any coordinator) via `gc sling ... --on mol-review-leg` | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-review-leg.toml@9a01227` | 2026-05-24 |
| Agent definition (mayor) | `agent.toml` + `prompt.template.md` — city-scope coordinator | `rigs/gascity/examples/gastown/packs/gastown/agents/mayor/@9a01227` | 2026-05-24 |
| Agent definition (deacon) | `agent.toml` + `prompt.template.md` — city-scope patrol | `rigs/gascity/examples/gastown/packs/gastown/agents/deacon/@9a01227` | 2026-05-24 |
| Agent definition (boot) | `agent.toml` + `prompt.template.md` — city-scope watchdog | `rigs/gascity/examples/gastown/packs/gastown/agents/boot/@9a01227` | 2026-05-24 |
| Agent definition (witness) | `agent.toml` + `prompt.template.md` — rig-scope work-health monitor | `rigs/gascity/examples/gastown/packs/gastown/agents/witness/@9a01227` | 2026-05-24 |
| Agent definition (refinery) | `agent.toml` + `prompt.template.md` — rig-scope merge processor | `rigs/gascity/examples/gastown/packs/gastown/agents/refinery/@9a01227` | 2026-05-24 |
| Agent definition (polecat) | `agent.toml` + `prompt.template.md` + `namepool.txt` — rig-scope worker pool | `rigs/gascity/examples/gastown/packs/gastown/agents/polecat/@9a01227` | 2026-05-24 |
| Slash command (status) | `commands/status/` — `help.md` + `run.sh`; invoked as `gc gastown status` | `rigs/gascity/examples/gastown/packs/gastown/commands/status/@9a01227` | 2026-05-24 |
| Doctor check (check-scripts) | `doctor/check-scripts/run.sh` — verifies pack scripts are executable | `rigs/gascity/examples/gastown/packs/gastown/doctor/check-scripts/run.sh@9a01227` | 2026-05-24 |
| License | MIT License, Copyright (c) 2025 Steve Yegge | `rigs/gascity/LICENSE@9a01227` | 2026-05-24 |

## License

MIT License, Copyright (c) 2025 Steve Yegge (per
`rigs/gascity/LICENSE@9a01227`). Permissive license; molecules and
other pack artifacts in `examples/gastown/packs/gastown/` inherit
MIT terms from the repo root LICENSE. README confirms MIT badge.

## Molecule format / schema

A molecule is a TOML file under `formulas/` (filename convention
`mol-<name>.toml`). Top-level keys observed across the seven Gas
Town molecules:

- `description` (triple-quoted multiline string): authoring intent,
  contract notes, role description, failure-mode tables, variable
  tables. Always present.
- `formula` (string): canonical formula name — must match the
  filename stem (e.g., `mol-polecat-work`). Always present.
- `version` (integer): formula version (used by the runtime to
  detect incompatible changes). Observed values: `1`-`14`.
- `extends` (array of strings, optional): inherit steps and
  variables from a base molecule (e.g., `mol-polecat-work` extends
  `mol-polecat-base`).
- `contract` (string, optional): contract identifier (e.g.,
  `"graph.v2"`). Present on `mol-refinery-patrol`,
  `mol-digest-generate`, `mol-idea-to-plan`.
- `[vars]` table: per-variable subtable `[vars.<name>]` with keys
  `description` (string), `default` (string), `required` (bool,
  optional). Defaults can be empty strings (meaning "skip"
  semantics for commands).
- `[[steps]]` array-of-tables: ordered step DAG. Each step has:
  - `id` (string): step identifier, referenced by other steps'
    `needs`.
  - `title` (string): short human-readable name.
  - `needs` (array of strings, optional): step IDs this step
    depends on; omitted for the first step.
  - `description` (multiline string): full step body —
    instructions, shell snippets, exit criteria, variable
    substitutions like `{{base_branch}}`, `{{issue}}`,
    `{{binding_prefix}}`.

Verbatim excerpt (first ~40 lines of `mol-polecat-work.toml`):

```toml
description = """
Polecat work lifecycle — feature-branch variant.

Extends mol-polecat-base with feature-branch workspace setup and
refinery-based submission. The polecat creates a feature branch,
implements the work, then pushes and reassigns to the refinery for
merge review.

## Polecat Contract (Self-Cleaning Model)

1. Receive work (molecule poured with this formula, assigned to you)
2. Follow steps in order (read descriptions, execute, move to next)
3. Submit: push branch, set metadata on work bead, assign to refinery, exit
4. You are GONE — Refinery merges, closes the bead

**No MR beads.** Work beads flow directly: pool → polecat → refinery → closed.
...
"""
formula = "mol-polecat-work"
extends = ["mol-polecat-base"]
version = 10

[vars]
[vars.binding_prefix]
description = "Import binding prefix for gastown agent identities, including trailing dot when bound."
default = ""

[vars.affected_tests_command]
description = "Shell-safe affected-tests command. Must read `git diff --name-only origin/{{base_branch}}...HEAD` and run the matching test subset. From rig `formula_vars` or empty to run full test_command."
default = ""

[[steps]]
id = "workspace-setup"
title = "Set up worktree and feature branch"
needs = ["load-context"]
description = """
Ensure you have an isolated git worktree and a clean feature branch.
...
"""
```

Variable substitution syntax is Go template-style `{{var}}`.
Variables resolve from (in order): explicit `--var` on `gc bd mol
wisp`, the rig's `formula_vars` block in city.toml, then the
molecule's declared `default`.

## Molecule catalog

| name | 1-line purpose | path | trigger / when-poured | step count | adoptable as-is by gc-toolkit? (Y/N + note) |
|---|---|---|---|---|---|
| `mol-polecat-work` | Polecat work lifecycle — worktree setup, implementation, self-review w/ affected tests, push, reassign to refinery, exit | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-polecat-work.toml@9a01227` | Poured by `gc sling` onto a polecat for a work bead | 3 steps in this file (`workspace-setup`, `self-review`, `submit-and-exit`) overriding/extending parent `mol-polecat-base` | Partial — generic to the polecat→refinery work model, but depends on parent `mol-polecat-base` (not present in this directory) and assumes Gastown's `metadata.branch` / `metadata.target` conventions and `${GC_RIG}/{{binding_prefix}}refinery` assignee shape |
| `mol-deacon-patrol` | Deacon patrol loop — context+inbox, orphan-process cleanup, work-layer health, queue-starvation check, utility-agent health, Dolt health, system diagnostics, self-pour next wisp | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-deacon-patrol.toml@9a01227` | Poured as root-only wisp on deacon startup; each iteration self-pours next | 8 steps | N — `dolt-health` step embeds Dolt data-plane assumptions; `utility-agent-health` and warrants target `{{binding_prefix}}dog` pool from Gastown's maintenance pack |
| `mol-witness-patrol` | Witness patrol — inbox triage, orphaned-bead recovery via session-ID liveness, refinery queue health, polecat health, self-pour next wisp | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-witness-patrol.toml@9a01227` | Poured as root-only wisp on witness startup per rig; each iteration self-pours next | 5 steps | Partial — orphan-recovery logic is generic to any pool+refinery model, but assignee classifier hardcodes `<rig>/{{binding_prefix}}<suffix>` and warrant payloads target Gastown's dog pool |
| `mol-refinery-patrol` | Refinery patrol — validate identity, inbox, find assigned work, rebase, test, merge (direct or PR), patrol summary, self-pour next wisp | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-refinery-patrol.toml@9a01227` | Poured as root-only wisp on refinery startup per rig; each iteration self-pours next | 7 steps | Partial — merge mechanics, rebase, PR validation are generic to git-flow merge processors; but rejection-path assignee `${GC_RIG:+$GC_RIG/}{{binding_prefix}}polecat` and rig/binding-prefix variable names are Gastown-specific |
| `mol-digest-generate` | Periodic activity digest — determine period, collect rig+town data, generate markdown, mail to mayor, archive as bead | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-digest-generate.toml@9a01227` | Periodic — deacon's `periodic-formulas` step dispatches on cooldown (interval e.g. 24h); executed by dog pool | 3 steps | Partial — periodic-digest pattern is generic; mail destination (`mayor/`) and digest sections (rig list, warrants, escalations) follow Gastown's role taxonomy |
| `mol-idea-to-plan` | Full idea→PRD→design→plan pipeline with parallel review legs, human gate, alignment rounds, beads-DAG creation | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-idea-to-plan.toml@9a01227` | Coordinator-poured (mayor or crew worker) one-shot | 12 steps | Partial — pipeline structure (PRD→review→design→rounds→beads) is generic, but dispatch step assumes `$GC_RIG/{{binding_prefix}}polecat` review target and uses `gc convoy` commands |
| `mol-review-leg` | Generic review-leg helper — load assignment, perform analysis, store full report in bead notes, mail coordinator, close+drain | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-review-leg.toml@9a01227` | Dispatched by coordinators via `gc sling <target> <bead> --on mol-review-leg` (e.g., from `mol-idea-to-plan`) | 3 steps | Y — no rig/binding-prefix variables, no agent-role hardcoding; relies only on bead metadata (`coordinator`, `review_id`, `review_phase`, `review_leg`) and standard `gc bd`/`gc mail`/`gc runtime` primitives |

## Representative molecules

### `mol-polecat-work` — work lifecycle (feature-branch variant)

- **Variables:** `binding_prefix` (import-binding prefix, default
  `""`), `affected_tests_command` (shell-safe affected-tests
  command, default `""`). Inherits additional vars from parent
  `mol-polecat-base` referenced via `extends` — including
  `base_branch`, `setup_command`, `typecheck_command`,
  `lint_command`, `build_command`, `test_command`, and `issue`
  (mentioned in step bodies but declared in parent).
- **Steps in this file (3 explicit; parent `mol-polecat-base`
  supplies `load-context` and `implement` referenced by `needs`):**
  1. `workspace-setup` — `needs=["load-context"]`. Fetches origin,
     resolves `metadata.work_dir` or creates `worktrees/{{issue}}`
     worktree, resolves `metadata.branch` (existing/rejection-
     resumption or fresh from `origin/{{base_branch}}`), runs
     `setup_command`. Idempotent (safe after crash).
  2. `self-review` — `needs=["implement"]`. Reviews diff against
     `origin/{{base_branch}}`, runs setup/typecheck/lint/build,
     then conditional `affected_tests_command` else full
     `test_command`. Refuses to push on local failure.
  3. `submit-and-exit` — `needs=["self-review"]`. Final clean-state
     check, `git push origin HEAD`, branch metadata + target on
     bead, reassigns to `${GC_RIG:+$GC_RIG/}{{binding_prefix}}refinery`
     with `gc.routed_to` update, wakes/nudges refinery, runs `gc
     runtime drain-ack` and exits.
- **Dependencies:** Linear DAG within this file (`workspace-setup`
  → `implement` (parent) → `self-review` → `submit-and-exit`).
- **Outputs / artifacts:** Pushed feature branch on origin; bead
  `metadata.branch`, `metadata.target`, `metadata.work_dir` set;
  bead reassigned to refinery; agent session drained.

### `mol-witness-patrol` — patrol loop

- **Variables:** `binding_prefix` (default `""`), `event_timeout`
  (sleep seconds between cycles, default `"60"`).
- **Steps (5):**
  1. `check-inbox` — RSS context check (request-restart if >1500
     MB); reads `gc mail inbox`; classifies messages by category
     table (Emergency/Failed/Blocked/Decision/Lifecycle/General);
     escalates to `mayor/` only when warranted; archives processed
     mail.
  2. `recover-orphaned-beads` — `needs=["check-inbox"]`. Core job.
     Lists in-progress and open beads with assignees, resolves each
     assignee via session list + session-bead metadata, classifies
     (active/asleep/orphaned), salvages work from worktree (5 cases
     A-E), pushes branch if unpushed, verifies merge-to-main before
     reset, cleans worktrees, returns bead to pool, marks
     `metadata.recovered=true`.
  3. `check-refinery` — `needs=["recover-orphaned-beads"]`. Reviews
     refinery queue depth and wisp freshness; nudges or mails
     mayor.
  4. `check-polecat-health` — `needs=["check-refinery"]`. Looks for
     in_progress polecat work with stale `UpdatedAt`; files warrant
     bead with `gc.routed_to: "{{binding_prefix}}dog"` for stuck
     polecats.
  5. `next-iteration` — `needs=["check-polecat-health"]`. Context
     check; pours next wisp via `gc bd mol wisp mol-witness-patrol
     --root-only`; assigns to self; sleeps `event_timeout`; burns
     current wisp via `gc bd mol burn <id> --force`.
- **Dependencies:** Strict linear DAG (one step → next).
  Intermediate steps explicitly forbidden from exiting the wisp —
  only `next-iteration` may pour-and-burn.
- **Outputs / artifacts:** Orphaned beads recovered (worktree-
  salvage commits pushed; `metadata.branch` set;
  `metadata.recovered=true`); warrants filed for stuck agents;
  mayor mail on orphan-recovery/stale queues; next wisp poured;
  current wisp burned.

### `mol-idea-to-plan` — one-shot planning pipeline

- **Variables:** `binding_prefix` (default `""`), `problem` (raw
  idea, required), `context` (additional constraints, default
  `""`), `review_target` (agent/pool for review legs; empty derives
  `$GC_RIG/{{binding_prefix}}polecat`), `review_formula` (default
  `"mol-review-leg"`).
- **Steps (12):**
  1. `init-run` — primes, resolves repo root, derives
     `REVIEW_TARGET`, picks `REVIEW_ID` slug, creates
     `.prd-reviews/$REVIEW_ID/`, `.designs/$REVIEW_ID/`,
     `.plan-reviews/$REVIEW_ID/` directories, writes `state.env`.
  2. `draft-prd` — `needs=["init-run"]`. Writes `prd-draft.md` with
     sections Problem/Goals/Non-Goals/User Stories/Constraints/Open
     Questions/Rough Approach; writes manifest.
  3. `prd-review` — `needs=["draft-prd"]`. Fans out 6 PRD-review
     beads in parallel via `gc bd create` + `gc sling ... --on
     mol-review-leg`; legs: requirements / gaps / ambiguity /
     feasibility / scope / stakeholders; synthesizes
     `prd-review.md`.
  4. `human-clarify` — `needs=["prd-review"]`. Only required human
     gate; presents critical questions in live chat, appends
     answers to PRD draft.
  5. `design-exploration` — `needs=["human-clarify"]`. 6 design
     legs: api / data / ux / scale / security / integration;
     synthesizes `design-doc.md`.
  6. `prd-align-1` — `needs=["design-exploration"]`. 2 legs:
     requirements-coverage / goals-alignment.
  7. `prd-align-2` — `needs=["prd-align-1"]`. 2 legs:
     constraints-compliance / non-goals-enforcement.
  8. `prd-align-3` — `needs=["prd-align-2"]`. 2 legs:
     user-stories-coverage / open-questions-resolution.
  9. `plan-review-1` — `needs=["prd-align-3"]`. 2 legs:
     completeness / sequencing.
  10. `plan-review-2` — `needs=["plan-review-1"]`. 2 legs: risk /
      scope-creep.
  11. `plan-review-3` — `needs=["plan-review-2"]`. 2 legs:
      testability / coherence.
  12. `create-beads` — `needs=["plan-review-3"]`. Creates owned
      convoy via `gc convoy create --owned`, sets integration
      target via `gc convoy target`, creates task beads, adds them
      with `gc convoy add`, wires deps via `gc bd dep add`,
      verifies with `gc bd blocked`; records bead IDs in
      `.plan-reviews/$REVIEW_ID/beads-created.md`.
- **Dependencies:** Strict linear DAG (each step `needs` the
  prior). Each review-leg dispatch step also has an internal
  fan-out → wait-for-completion pattern.
- **Outputs / artifacts:**
  `.prd-reviews/$REVIEW_ID/prd-draft.md`,
  `.prd-reviews/$REVIEW_ID/prd-review.md`,
  `.designs/$REVIEW_ID/design-doc.md`, round logs in
  `.plan-reviews/$REVIEW_ID/`, owned convoy + task beads with
  dependency edges, `.plan-reviews/$REVIEW_ID/beads-created.md` ID
  record.

## Adjacent skill / command artifacts

**Agents** (`agents/`): six subdirectories, one per agent role.
Each contains `agent.toml` (scope / wake_mode / work_dir / nudge /
idle_timeout / max_active_sessions) plus `prompt.template.md` (Go
template-rendered role prompt). Polecat additionally has
`namepool.txt` (random worker names). Agent roles:

| Agent | Scope | Pool / cardinality | Prompt size |
|---|---|---|---|
| mayor | city | 1 | 9947 bytes |
| deacon | city | 1 | 8169 bytes |
| boot | city | 1 | 5218 bytes |
| witness | rig | 1 per rig | 11417 bytes |
| refinery | rig | 1 per rig | 12740 bytes |
| polecat | rig | 0-5 per rig (pool) | 9092 bytes |

`pack.toml` declares `[[named_session]]` entries binding these
templates to scope (`city`/`rig`) and mode (`always`/`on_demand`);
maintenance pack provides the dog pool template imported via
`[imports.maintenance]`.

**Commands** (`commands/`): one subdirectory:
- `status/` — `help.md` (short description) + `run.sh` (POSIX sh
  script). Invoked as `gc gastown status`. Runs `gc status` if
  available, prints city/pack context. The sole slash-command-style
  artifact in the pack.

**Doctor** (`doctor/`): one subdirectory:
- `check-scripts/run.sh` — pack health check that verifies all
  `assets/scripts/*.sh` are executable. Exit codes 0=OK, 1=Warning,
  2=Error. Prints message on stdout (first line summary, rest
  detail).

## Notable conventions

- **TOML-based formula language vs. Markdown-based SKILL.md.**
  Molecules are structured TOML with declarative `[vars]` and
  ordered `[[steps]]`; step `description` fields are multi-line
  markdown bodies containing both prose and shell snippets. The
  structured layer is the DAG/schema; the unstructured layer is the
  LLM-readable instructions inside each step.
- **Step `needs` ordering for DAG execution.** Steps form an
  explicit dependency graph via `needs = ["<prior-id>"]`. First
  step omits `needs`. Several patrol molecules enforce linear
  chains and explicitly forbid intermediate exit — only the
  terminal `next-iteration` step may pour-and-burn.
- **Variable substitution (`{{var}}`) and rig `formula_vars`
  source.** Variables flow from `--var key=value` on `gc bd mol
  wisp`, then rig-level `formula_vars`, then molecule defaults.
  Empty-string defaults are treated as "skip" semantics (e.g., empty
  `setup_command` is silently skipped).
- **Patrol-vs-on-demand split.** Three molecules are patrol loops
  that self-pour their next iteration before burning the current
  wisp (`mol-deacon-patrol`, `mol-witness-patrol`,
  `mol-refinery-patrol`). Three are one-shot/work-lifecycle
  (`mol-polecat-work`, `mol-idea-to-plan`, `mol-review-leg`). One
  is periodic, dispatched by deacon on cooldown trigger
  (`mol-digest-generate`).
- **Self-cleaning, no-idle contract.** Worker molecules (polecat,
  dog) drain on completion via `gc runtime drain-ack` + `exit`.
  Patrol molecules pour-then-burn so the new wisp is already
  assigned before the old wisp closes — protects against wisp leaks
  on early exit.
- **Wisp-as-iteration pattern.** Each patrol iteration is
  materialized as a "wisp" bead. The molecule's formula text is the
  source of truth; the wisp tracks lifecycle. Formula step
  descriptions are NOT materialized as child beads — agent re-reads
  steps from the formula text on restart.
- **Integration with the gascity agent model.** Molecules embed
  assignee shapes tied to Gastown's roles: polecats (pool), refinery
  (per-rig), witness (per-rig), deacon (city), mayor (city), dog
  (utility pool from maintenance pack). The `{{binding_prefix}}`
  variable allows pack imports to namespace agent identities. The
  `${GC_RIG:+$GC_RIG/}{{binding_prefix}}<role>` shell idiom appears
  across molecules to resolve agent identities both inside and
  outside rig sessions.
- **Metadata-driven work routing.** Work beads carry routing
  metadata: `metadata.branch`, `metadata.target`,
  `metadata.work_dir`, `metadata.rejection_reason`,
  `metadata.existing_pr`, `metadata.merge_strategy`, `merged_sha`,
  `merged_target`, `pr_url`, `pr_number`, `recovered`,
  `gc.routed_to`. Molecules read and write this metadata as a
  coordination protocol between pool/polecat/refinery/witness
  handoffs.
- **`contract = "graph.v2"` declaration.** Three of the seven
  molecules declare this contract string at top level
  (`mol-refinery-patrol`, `mol-digest-generate`,
  `mol-idea-to-plan`). Other four omit it. Likely runtime-version
  selector but not consistently applied across the catalog.
- **Failure-mode tables in `description`.** Several molecules
  (notably `mol-polecat-work`, `mol-witness-patrol`) include
  explicit markdown tables in the formula's top-level `description`
  enumerating situations vs. actions — used as agent-readable
  failure documentation, not parsed by the runtime.
