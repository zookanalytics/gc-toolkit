---
name: Personas prior-art surveys (provenance)
description: Provenance-stamped index of the five prior-art surveys behind the persona/agent model — the systems surveyed, what each contributed, and sources — so the patterns adopted into docs/personas.md stay auditable.
---

# Prior-art surveys — provenance

Five prior-art surveys informed the persona/agent model adopted in
[`docs/personas.md`](../../../docs/personas.md). This file is the
**provenance-stamped index**: the systems surveyed, the pattern each
contributed, and the sources. The full survey write-ups were produced in the
mechanik-thread design session (2026-06-13); this index persists the sourced
provenance so the adopted patterns stay auditable.

## 1. OpenHands / OpenClaw

OpenHands microagents and OpenClaw's `IDENTITY.md` + `SOUL.md` split, plus a
heartbeat daemon for a standing agent.

- [OpenHands docs](https://docs.openhands.dev)
- [OpenClaw docs](https://docs.openclaw.ai)
- [openclaw/openclaw](https://github.com/openclaw/openclaw)

## 2. MetaGPT / ChatDev

MetaGPT's `Role` class (SOP-as-actions, path-constants × `ProjectRepo`) and
ChatDev's `RoleConfig` / `PhaseConfig` / `ChatChain`.

- [FoundationAgents/MetaGPT](https://github.com/FoundationAgents/MetaGPT)
- [OpenBMB/ChatDev](https://github.com/OpenBMB/ChatDev)

## 3. CrewAI / AutoGen / LangGraph

CrewAI's `Agent` (role / goal / backstory, output declared on the `Task`),
AutoGen's `system_message` vs `description` split, and LangGraph's nodes +
reducers.

- [CrewAI docs](https://docs.crewai.com)
- [AutoGen docs](https://microsoft.github.io/autogen)
- [LangGraph docs](https://docs.langchain.com/langgraph)

## 4. Roo Code / Cline / Cursor / Aider

Roo Code custom modes (`fileRegex` edit-fence), Cline, Cursor inclusion modes,
and Aider's read-only vs. editable file distinction.

- [Roo Code docs](https://docs.roocode.com)
- [Cline docs](https://docs.cline.bot)
- [Cursor docs](https://docs.cursor.com)
- [Aider](https://aider.chat)

## 5. Claude Code / Kiro / Amazon Q

Claude Code subagents + skills, Kiro steering (inclusion: always / fileMatch /
manual), and Amazon Q resources globs.

- [Claude Code docs](https://code.claude.com/docs)
- [Kiro docs](https://kiro.dev/docs)
- [Amazon Q docs](https://docs.aws.amazon.com)

## Key cross-cutting findings

- The **identity / owns split** is validated prior art (CrewAI, MetaGPT).
- Treating **"owns" as a maintained-artifact contract** is novel — no surveyed
  system has it.
- **Knows-inclusion** is borrowable from Kiro / Cursor.
- **Persona-adoption == skill-loading** — this is *why* a persona is a skill.
