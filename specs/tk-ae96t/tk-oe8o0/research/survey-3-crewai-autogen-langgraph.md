---
name: Prior-art survey 3 — CrewAI, AutoGen & LangGraph
description: Full primary-source survey — CrewAI's Agent/Task identity-vs-output split, AutoGen's system_message vs description two-field identity, and LangGraph's reducers as artifact-ownership contracts. Persisted from the mechanik-thread design session (2026-06-13); indexed by prior-art.md.
---

# Persona-System Prior-Art Survey: CrewAI, AutoGen, LangGraph

## Provenance

| System | Mechanism / artifact | Source (URL + repo/path) | Surveyed at |
|---|---|---|---|
| CrewAI | `Agent` (role/goal/backstory/tools) + `Task` (output_file/output_pydantic/context) | docs.crewai.com/en/concepts/agents ; .../concepts/tasks ; repo `crewAIInc/crewAI` | 2026-06-13 |
| Microsoft AutoGen | `ConversableAgent`/`AssistantAgent` — `system_message` + `description` (v0.2); v0.4 `autogen_agentchat.agents` | microsoft.github.io/autogen/0.2/docs/reference/agentchat/conversable_agent ; .../stable/reference/python/autogen_agentchat.agents.html ; repo `microsoft/autogen` | 2026-06-13 |
| LangGraph | `StateGraph` nodes (functions) + `Annotated`/reducers; prebuilt `create_react_agent` → `create_agent` | docs.langchain.com/oss/python/langgraph/graph-api ; reference.langchain.com/python/langgraph.prebuilt/.../create_react_agent | 2026-06-13 |

**Verification honesty:** CrewAI raw source files (`src/crewai/agent.py` etc.) returned 404 to raw fetch (repo restructured/blocked), so CrewAI field-level claims rest on the official docs attribute tables, not the class source. AutoGen v0.2 reference is legacy-but-canonical; I cross-checked the current v0.4 `autogen_agentchat` reference and note where they diverge. LangGraph prebuilt page moved; `create_react_agent` params confirmed from the LangChain API reference, which also flags its deprecation in favor of `create_agent`.

---

## CrewAI — `Agent`

- **Definition format:** Both a Python class (`Agent(...)`) and a declarative `agents.yaml` schema (recommended), wired via `@agent`/`@CrewBase` decorators where YAML method names must match Python.
- **Portable identity:** **Yes, strong.** `role`, `goal`, `backstory` are required identity fields; `tools`, `llm`, `memory`, `knowledge_sources`, `embedder`, and prompt templates are optional. The Agent is defined independently of any task and composed into a crew by reference — the closest analog to your "portable identity" of the three.
- **Owned/managed files:** **No — and this is the key finding.** Output ownership lives on the **`Task`**, not the Agent: `output_file`, `output_json`, `output_pydantic`, `create_directory`, `markdown`, `guardrail`. The Task binds a worker via its `agent` field. So "who I am" and "what I emit" are split across two objects.
- **Known/context files:** Partially at the Agent level via `knowledge_sources` (declared readable knowledge) + `embedder`/RAG tools. Task-to-task inputs are declared on the Task via `context` (list of upstream Tasks), not on the Agent.
- **Processes:** Indirect. The Agent does not enumerate its methods; `Task`s reference the Agent, and the crew's `process` (sequential/hierarchical) drives execution.
- **Instantiation:** Mostly transient/composed, but addressable: `Agent.kickoff()` lets an agent run directly without a task/crew, and `memory` gives it persistence within a crew. Not a long-lived network-addressable service.
- **Closeness to our model:** Closest overall — explicit reusable role identity, declared knowledge inputs, transient-by-default with a direct-invoke escape hatch.
- **Worth borrowing:** The **identity/output split** (persona = portable role; *owns* artifacts declared elsewhere and resolved per deployment) — CrewAI independently arrived at exactly your (a)-vs-(b) separation by putting `output_file` on Task, not Agent.

---

## Microsoft AutoGen — `ConversableAgent` / `AssistantAgent`

- **Definition format:** Python class instantiation. `ConversableAgent(name=..., system_message=..., description=..., llm_config=...)`; `AssistantAgent`/`UserProxyAgent` are subclasses with preset defaults. (v0.4 AgentChat: same shape, `model_client` replaces `llm_config`.)
- **Portable identity:** **Yes, but prose-only.** Identity is the free-text `system_message` ("You are a helpful AI Assistant." by default). It is reusable and task-independent, but unstructured — no role/goal/backstory decomposition. Notably AutoGen splits identity into **two fields**: `system_message` (steers the model) and `description` (a short capability blurb other agents/the `GroupChatManager` read to decide *when to call this agent*). That description field is a clean analog to a persona's externally-advertised, addressable interface.
- **Owned/managed files:** **No.** No owned-output declaration. Code-execution agents reference a `work_dir`, but that's executor config, not an agent-level artifact contract.
- **Known/context files:** **No declared file inputs.** Context enters as conversation history (`chat_messages`/carryover), not as declared context files.
- **Processes:** Strong, but conversational rather than artifact-based. Behavior binds via `register_reply` (trigger→reply-fn), `initiate_chat`, and team/`GroupChat` membership. v0.4 adds `handoffs` and `run()`/`run_stream()`.
- **Instantiation:** **Standing and addressable** — the most "agent-like." Instances are stateful (`chat_messages`, `send`/`receive`, `on_messages`, `save_state`/`load_state`, `on_reset`), uniquely named, and referenced by name in multi-agent chats.
- **Closeness to our model:** Captures (a) identity and the standing/addressable end-state well; weak on (b)/(c) — no declared owned/known *files*, only message state.
- **Worth borrowing:** The **two-field identity** — separate the model-facing self-description from the **externally-advertised `description` used for routing/selection.** Maps directly onto "loaded transiently … becomes addressable to gate work": the `description` is what a coordinator reads to decide whether to stand the persona up.

---

## LangGraph — nodes + typed `State`

- **Definition format:** Graph-centric. `StateGraph(StateSchema)` with nodes added via `add_node(name, fn)`; nodes are plain functions `(state, config) -> partial-state-update`. State is a `TypedDict`/dataclass/Pydantic schema.
- **Portable identity:** **No, at the core layer.** Docs are explicit: "Nodes: Functions that encode the logic of your agents" — there is no agent/role identity object; `StateGraph` is parameterized by *state schema only*. Identity exists only as a named function inside one graph. **The prebuilt layer adds it:** `create_react_agent(model, tools, prompt=..., name=...)` (now deprecated → `langchain.agents.create_agent` with middleware) produces a reusable, named, portable agent that can itself be embedded as a node/subgraph in a larger graph. So portability is opt-in via the prebuilt factory, absent in raw LangGraph.
- **Owned/managed files:** **No file ownership; field-level *state* ownership instead.** This is LangGraph's distinctive contribution: each State key declares a **reducer** via `Annotated[type, reducer]` (e.g. `add_messages`) governing how concurrent writes merge (default = overwrite/last-write-wins). Ownership is by merge-rule, not by file path.
- **Known/context files:** No declared file inputs. Nodes implicitly read the shared `State`; docs note nodes "do not declare which keys they read or write" — read/write sets are implicit. **Subgraphs** can keep **private channels** outside the parent I/O schema (a "knows internally vs exposes" boundary), with a streaming-leak caveat.
- **Processes:** The graph *is* the process — edges/`Command(goto=...)`/conditional routing are first-class; the workflow is the primary artifact, agents secondary.
- **Instantiation:** Nodes are named and addressable as graph members (`add_edge("a","b")`) but execution is transient per super-step; no standing service. Persistence is the *graph's* checkpointer, not a per-agent identity.
- **Closeness to our model:** Furthest from a persona model at its core (workflow-first, identity-thin), yet it uniquely formalizes **artifact ownership semantics** that your *owns* clause leaves implicit.
- **Worth borrowing:** **Reducers as ownership contracts** — when two personas touch the same owned artifact, a declared merge function (append / last-write / custom) resolves contention deterministically. Also the **subgraph private-channel** pattern for *knows*-internal vs externally-visible context.

---

## Cross-cutting takeaways for your model

1. **Identity-vs-output split is validated prior art, not a quirk:** CrewAI puts identity on `Agent` and outputs on `Task` — independent confirmation of your (a) portable-identity / (b) owns separation. Borrow it: keep the persona's *owns* as references resolved per deployment, not baked into identity.
2. **Two-tier identity for the transient→addressable transition:** AutoGen's `system_message` (self) + `description` (advertised, routing-facing) is the cleanest match to "transiently loaded, becomes addressable to gate work." A coordinator reads the `description`-equivalent to decide when to stand the persona up.
3. **No surveyed system declares *known/context input files* on the role** the way your *knows* clause does — closest is CrewAI's `knowledge_sources` (agent-level) and Task `context` (task-level). This is a genuine gap your model fills; it's a differentiator, not a missing-homework item.
4. **Ownership semantics are under-specified everywhere except LangGraph.** If personas can co-write artifacts, adopt LangGraph-style per-artifact reducers to make *owns* contention deterministic.
