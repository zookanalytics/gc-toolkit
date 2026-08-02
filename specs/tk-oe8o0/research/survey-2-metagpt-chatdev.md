---
name: Prior-art survey 2 — MetaGPT & ChatDev
description: Full primary-source survey — MetaGPT's Role class (typed identity fields, SOP-as-actions, path-constants × ProjectRepo, _watch/cause_by typed handoff) and ChatDev's RoleConfig / PhaseConfig / ChatChain JSON split. Persisted from the mechanik-thread design session (2026-06-13); indexed by prior-art.md.
---

# Persona-System Prior Art: MetaGPT & ChatDev

## Provenance

| System | Mechanism / artifact | Source (URL + repo/path) | Surveyed at |
|---|---|---|---|
| MetaGPT | `Role` base class (identity fields) | `FoundationAgents/MetaGPT@main` · [`metagpt/roles/role.py`](https://github.com/FoundationAgents/MetaGPT/blob/main/metagpt/roles/role.py) | 2026-06-13 |
| MetaGPT | Concrete roles (PM / Architect / Engineer / QA) | `metagpt/roles/{product_manager,architect,engineer,qa_engineer}.py` | 2026-06-13 |
| MetaGPT | Artifact path constants (owned files) | [`metagpt/const.py`](https://github.com/FoundationAgents/MetaGPT/blob/main/metagpt/const.py) (`PRDS_FILE_REPO="docs/prd"`, etc.) | 2026-06-13 |
| MetaGPT | SOP as actions | `metagpt/actions/{write_prd,design_api,project_management,write_code,write_test}.py` | 2026-06-13 |
| MetaGPT | Paper (SOP-as-prompt thesis) | [arXiv 2308.00352](https://arxiv.org/html/2308.00352v6) | 2026-06-13 |
| ChatDev (classic "chat chain") | `RoleConfig.json` / `PhaseConfig.json` / `ChatChainConfig.json` | `OpenBMB/ChatDev@chatdev1.0` · [`CompanyConfig/Default/*.json`](https://github.com/OpenBMB/ChatDev/tree/chatdev1.0/CompanyConfig/Default) | 2026-06-13 |
| ChatDev (classic) | Phase / ComposedPhase / ChatChain engine | `chatdev/{phase,composed_phase,chat_chain,chat_env}.py` (branch `chatdev1.0`) | 2026-06-13 |
| ChatDev 2.0 (current `main`) | Graph/node config rewrite (NOT the chat chain) | `OpenBMB/ChatDev@main` · `entity/configs/node/agent.py`, `graph_config.py` | 2026-06-13 |

**Caveat worth flagging up front:** ChatDev's repo `main` was rewritten into a 2.0 "graph of nodes" zero-code platform; the classic role/phase/chat-chain design the question targets now lives on branch **`chatdev1.0`** (and tags ≤ v1.1.6). I surveyed `chatdev1.0` as primary. Everything below is from primary source files; where a fetch summary gave a shaky count I say so rather than assert it.

---

## MetaGPT

**Definition format.** Python class. Each role subclasses `Role` (a Pydantic `BaseModel`); newer ones subclass `RoleZero` (which subclasses `Role`). Identity is **class attributes**; behavior is wired in `__init__` via method calls. E.g. `ProductManager(RoleZero)` sets `name="Alice"`, `profile="Product Manager"`, `goal="Create a Product Requirement Document..."`, `constraints="utilize the same language as the user requirements..."`.

**Portable identity (your `a`).** Strong and explicit. `Role` defines `name`, `profile`, `goal`, `constraints`, `desc` — all **project-agnostic strings** baked into the class, injected into the LLM system prompt. They carry zero project specifics (no paths, no IDs); the same class drops into any run. This is close to your "portable identity that travels with the persona."

**Owned/managed files (your `b`).** Yes, but **indirectly** — ownership is expressed as *which Action a role runs*, and the Action writes to a **fixed, project-relative path constant** in `const.py`, resolved under the active `ProjectRepo` (the deployment root). So:
- ProductManager → `WritePRD` → `PRDS_FILE_REPO = "docs/prd"`
- Architect → `WriteDesign` → `SYSTEM_DESIGN_FILE_REPO = "docs/system_design"` (+ `resources/data_api_design`, `resources/seq_flow`)
- ProjectManager → `WriteTasks` → `TASK_FILE_REPO = "docs/task"`
- Engineer → `WriteCode` → source tree via `self.repo.srcs.save()`; summaries to `docs/code_summary`
- QAEngineer → `WriteTest`/`RunCode`/`DebugError` → `tests/`, `test_outputs/`

The role doesn't *declare* "I own `docs/prd`" in its own body — the binding is `role → action → path-constant`, paths globally defined and re-rooted per deployment via `ProjectRepo`. Functionally equivalent to your "owns project-relative artifacts, resolved per deployment," but the declaration is split across three files, not co-located on the persona.

**Known/context files (your `c`).** Expressed as **action-level subscriptions, not file inputs.** A role calls `self._watch([...Action types...])`; it then consumes the *messages those actions emitted* (each `Message` carries `cause_by`). Architect `_watch({WritePRD})`; Engineer `_watch({WriteTasks, SummarizeCode, WriteCode, WriteCodeReview, FixBug, WriteCodePlanAndChange})`. So "knows" = "the upstream artifacts named by the actions I watch," dereferenced through the shared repo — typed by *producing action*, not by literal path.

**Processes (your `d`).** This is MetaGPT's thesis: **SOP encoded as prompts.** Each role's method is a sequence of `Action` objects (`set_actions([...])`), and reaction strategy is declared (`rc.react_mode`: `REACT` think-act loop, `BY_ORDER` sequential, or `PLAN_AND_ACT`). The PM runs `[PrepareDocuments, WritePRD]` `BY_ORDER`. The Action subclass holds the structured prompt + an output schema (`WritePRD` demands Product Goals, User Stories, Competitive Analysis, Requirement Pool). The paper frames the whole system as "SOPs encoded as prompt sequences," with two parts: *role specialization* + *workflow across agents*.

**Instantiation.** **Standing and addressable** within a run. Roles are long-lived objects hired into a `Team`/`Environment` (`company.hire([ProductManager(), Architect(), ProjectManager(), Engineer()])`), each with a personal message buffer, addressed via `name`/`addresses` routing tags. They idle until a watched message arrives, then react. Handoff = publish a message tagged by `cause_by`; the downstream role's `_watch` picks it up — a **typed pub/sub over a shared file repo**, not direct calls. This differs from your "loaded transiently, becomes standing only to gate/patrol" — MetaGPT roles are standing by default for the whole job.

**Closeness to your model:** High — clean separation of portable identity (class attrs) from per-deployment artifacts (path-constants × `ProjectRepo`), with explicit owns/knows/process.
**Worth borrowing:** The `role → action → path-constant`-rooted-at-deployment indirection (your "owns, resolved per deployment") and **typed artifact handoff via `cause_by` + `_watch`** instead of free-form chat — directly models your owns/knows as a producer/consumer graph.

---

## ChatDev (classic "chat chain", branch `chatdev1.0`)

**Definition format.** **JSON config, not code.** Three decoupled files under `CompanyConfig/<Company>/`: `RoleConfig.json` (who), `PhaseConfig.json` (how, per step), `ChatChainConfig.json` (order). Agents are instantiated by the engine (`chatdev/role_play` via the CAMEL `RolePlaying` substrate) from these configs — you customize a "company" by editing JSON, no subclassing.

**Portable identity (your `a`).** Present but **thin and prompt-only.** `RoleConfig.json` maps each role name → an **array of prompt strings** (the role's "inception" system prompt). The default ships 9 roles: Chief Executive Officer, Chief Product Officer, Counselor, Chief Technology Officer, Chief Human Resource Officer, Programmer, Code Reviewer, Software Test Engineer, Chief Creative Officer. Example (CEO) literally: `["{chatdev_prompt}", "You are Chief Executive Officer. Now, we are both working at ChatDev...", "Your main responsibilities include being an active decision-maker...", "Here is a new customer's task: {task}.", ...]`. It *is* portable (project enters only via `{task}`/`{modality}` placeholders), but identity = a static prompt blob with **no goal/constraints schema, no knowledge beyond the prose**. Weaker and less structured than your "core role/knowledge" or MetaGPT's typed fields.

**Owned/managed files (your `b`).** **Not declared per role.** Roles don't own artifacts. Artifacts (code, manual, requirements, env doc) accumulate in a shared mutable blackboard — `ChatEnv` (`chatdev/chat_env.py`) — and are flushed to a single project directory. No `architect → architecture.md` style ownership binding exists; *phases* mutate shared state, roles don't hold files. This is the **biggest divergence** from your model: ChatDev has no per-persona owned-artifact concept.

**Known/context files (your `c`).** **Not declared.** A phase reads from and writes to the shared `ChatEnv` (whole prior code/requirements/designs in scope as prompt context); there's no per-role declared input set. "Knowledge" is whatever the phase prompt template injects via placeholders (`{task}`, `{description}`, `{modality}`, `{language}`, `{ideas}`, `{gui}`, `{codes}`, `{unimplemented_file}`).

**Processes (your `d`).** **The strongest, most explicit part — but it lives on the *phase/chain*, not the persona.** Process is a two-level pipeline:
- `ChatChainConfig.json` → ordered `chain`: `DemandAnalysis → LanguageChoose → Coding → CodeCompleteAll → CodeReview → Test → EnvironmentDoc → Manual`. Each entry has `phaseType` (`SimplePhase` = one dialogue, or `ComposedPhase` = looped, e.g. `CodeReview` cycleNum 3, `Test` cycleNum 3, `CodeCompleteAll` cycleNum 10), `max_turn_step`, `need_reflect`.
- `PhaseConfig.json` → each phase binds **exactly two roles** (`assistant_role_name`, `user_role_name`) + a `phase_prompt` template. E.g. `Coding`: assistant `Programmer`, user `Chief Technology Officer`. The SOP is the *sequence of two-agent role-plays*, not a method attached to any one agent.

**Instantiation.** **Transient and pairwise.** No standing addressable roster — for each phase the engine spins up a CTO↔Programmer (etc.) `RolePlaying` dialogue, runs ≤`max_turn_step` turns (optionally a `Counselor`↔`CEO` *reflection* sub-chat), writes results to `ChatEnv`, and tears the pairing down. Roles are summoned per phase. Handoff is **implicit via shared `ChatEnv` state** advanced by the chain — not messages, not typed subscriptions. This is *closer* to your "loaded transiently" intuition than MetaGPT, but there's no "becomes standing to gate/patrol" path at all.

**Closeness to your model:** Moderate-low — excellent declarative *process* (chain/phase) and portable-ish prompt identity, but **no owns/knows per persona** (artifacts live on a shared blackboard) and roles are transient phase-pairings.
**Worth borrowing:** The **3-file split (identity / step-method / ordering)** and especially the **`ComposedPhase` loop primitive** (`cycleNum`, reflection) — a clean, data-driven way to express your "processes" and the "gate work / patrol continuously" iterative-review modes without code.

---

## Cross-cutting read for your design

- **Identity (`a`):** Both keep identity project-agnostic and prompt-injected. MetaGPT's *typed* fields (`profile`/`goal`/`constraints`) are the better template for "portable identity + core knowledge" than ChatDev's prose blob.
- **Owns (`b`):** Only MetaGPT has anything like it, and it's **emergent** (`role → action → path-constant`, re-rooted by `ProjectRepo`) rather than a first-class `owns:` declaration on the persona. **Neither system has your clean "persona declares the project-relative artifacts it maintains."** That's a genuine gap your model fills — worth making first-class.
- **Knows (`c`):** Neither declares file inputs literally. MetaGPT types inputs by *producing action* (`_watch` + `cause_by`); ChatDev gives whole shared state. MetaGPT's typed-producer approach is the more borrowable basis for declared inputs.
- **Processes (`d`):** MetaGPT binds method **to the persona** (`set_actions` + `react_mode`); ChatDev binds it **to the pipeline** (chain + phase JSON). Your "processes it applies" leans MetaGPT-shaped (per-persona), but ChatDev's externalized chain is the better model if you want the *workflow* to be reconfigurable independent of personas.
- **Instantiation (`b`/standing-vs-transient):** Your "transient by default, standing only to gate/patrol" matches **neither** cleanly — MetaGPT roles are standing-for-the-run; ChatDev roles are transient phase-pairings with no standing mode. Your hybrid (transient load + promotable to addressable gatekeeper/patrol) is novel relative to both.

**Honesty notes:** PhaseConfig key count came back ambiguous (12 vs 13 in fetch summaries) — I report only the chain-level phase order, which I verified directly, and don't assert an exact PhaseConfig key count. Concrete-role file contents (PM/Architect/Engineer) are verified from source; the QA role's exact attrs I inferred from the established `_watch`/`set_actions` pattern + action filenames rather than a full file read, so treat QA specifics as pattern-level, not line-verified.
