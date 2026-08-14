---
name: Operator-facing agent audit for operator-next-step-trailing
description: Why the operator-reply rule reached three agents and not the refinery — the derivation of the operator-facing roster, the wiring landed for each agent, and the recorded decision on tk-l1pj6's second cause (enforcement) including the constraint that blocks it.
---

# Operator-facing agent audit (tk-l1pj6)

`operator-next-step-trailing` (`template-fragments/`) governs how an agent
ends a reply to the operator. Its load-bearing sentence is a prohibition,
added by tk-fc28x:

> Routine flows they already own and monitor (PR approval, merges) do not
> qualify anywhere in the reply — not as an action, and not as status, a
> recap line, or a brief item; omit them.

tk-l1pj6 reports the rule still being violated daily and asks *why*, naming
two causes: **distribution** (the refinery never received it) and
**enforcement** (agents that have it still violate it). This document records
the audit behind the distribution fix and the decision taken on enforcement.

## 1. What the audit found

Before this change the fragment reached three agents — mayor (`pack.toml`),
mayor-thread (`agent.toml`), mechanik (inline `{{ template }}` call) — plus
mechanik-thread, which inherits it by rendering mechanik's prompt. Two agents
that a human reads did not have it: **refinery** and **converse**.

### The cause was a written mis-classification

The omission was not a forgotten name. `agents/mayor-thread/PROVENANCE.md`
recorded, as the reason for excluding those roles from the thread model:

> The deacon, witness, and refinery are intentionally excluded: they are
> patrol / automation roles, not operator-facing.

That sentence is correct about **thread-spawnability** and was then read as a
roster for a different question. Two tests were collapsed into one:

| Question | Decides | Refinery |
|---|---|---|
| Does the operator *converse* with this role? | whether it gets an operator-spawnable thread | **no** |
| Does a human read this role's *prose as a report*? | whether operator-reply doctrine binds it | **yes** |

The refinery is exactly where the two answers diverge, which is why the
mistake produced the worst possible miss: nobody holds a sitting with the
refinery, and it is nonetheless the city's single largest producer of "a PR is
waiting on you" traffic — it holds the human-approval merge gate, so its whole
subject matter is work waiting on the operator.

The provenance sentence has been corrected in place. The thread exclusion it
justifies still stands; what changed is that it no longer states a roster it
was never derived to state.

### Evidence per agent

The test applied: *does a human read this agent's prose as a report or a
request?*

**Operator-facing — must carry the fragment**

| Agent | Evidence |
|---|---|
| `mayor` | the operator's primary interlocutor; coordination replies are read as they are written |
| `mayor-thread` | operator-spawned conversational thread of mayor — same replies, same reader |
| `mechanik` | the city's interactive builder role; the operator converses with it directly |
| `mechanik-thread` | operator-spawned conversational thread of mechanik |
| `converse` | its entire contract is the sitting: "post your framing and wait in place for the operator to reply" (`agents/converse/prompt.template.md`) |
| `refinery` | holds the human-approval merge gate (`formulas/mol-refinery-patrol.toml` `check_set` → `approval`); narrates that queue into a pane the operator watches; parks beads with `gc.routed_to=human`; tk-l1pj6's live case is ~7h of exactly this on 2026-08-13 |

**Not operator-facing — exempt, with the reason recorded**

| Agent | Why |
|---|---|
| `boot` | deacon watchdog: one judgement per wake; consumers are the deacon and the controller |
| `deacon` | town patrol; escalates to mayor, which is itself bound by the rule; subject is town mechanics |
| `witness` | rig health monitor; escalates to mayor; subject is agent and session health |
| `polecat` | worker — output is commits, beads and PRs, and its own doctrine forbids waiting on human input |
| `polecat-codex` | worker (codex signoff pool); same output surfaces |
| `proactive` | worker (first-reaction pool); writes a card to bead notes and files a visit — the *visit* is what reaches a human |

Out of scope: `dog` (gastown owns that pool outright and gc-toolkit expresses no
opinion on it — see the `pack.toml` header) and `_polecat-gemini` (disabled by
its `_` prefix; gascity's agent discovery skips it, and so does the check).

A note on the exempt column: deacon and witness *do* escalate, but they escalate
**to the mayor**, which carries the rule. Their prose is agent-addressed. That
is the line drawn here — it is a judgement, which is why every row above is
recorded with its reason rather than left to be re-derived.

## 2. What was landed

- `pack.toml` — the refinery patch appends `operator-next-step-trailing`.
- `agents/converse/prompt.template.md` — inline `{{ template }}` call, the
  idiom for an agent carrying its own prompt (matching mechanik).
- `agents/mayor-thread/PROVENANCE.md` — the mis-classification corrected, with
  a pointer to where the roster now lives.
- `doctor/check-operator-next-step-wiring/` — the mechanism (below), with a
  hermetic 13-case test.

Cost: the fragment is 491 B rendered
(`specs/tk-23wdf/context-budget-ledger.md`, which rates it **KEEP** —
"small, and the operator-facing agents act on it every reply"). Two more
agents is under 1 KB.

## 3. The mechanism, and why it is a classification and not a list

`doctor/check-operator-next-step-wiring` asserts that every agent the pack
governs carries an **explicit verdict with a reason**, and that every agent
judged operator-facing resolves the fragment through one of four wiring
surfaces:

1. `pack.toml` `[[patches.agent]]` → `inject_fragments_append` (imported agents)
2. `agents/<a>/agent.toml` → `append_fragments` / `inject_fragments`
3. `agents/<a>/prompt.template.md` → an inline `{{ template }}` call
4. inherited — `prompt_template` pointing at another prompt *in this pack* that
   carries (3). A pack-qualified reference (`gastown//…`) is deliberately not
   followed: those resolve to upstream base prompts that carry no gc-toolkit
   fragment, and accepting them would be a false green.

**An unclassified agent is an ERROR, not a pass.** This is the whole point. A
check that merely confirmed the six known names would go green on the seventh
agent — which is precisely how the refinery was missed. Requiring a verdict
converts "who reports to the operator" from something someone derived once into
something every new agent must answer.

## 4. Cause 2 (enforcement) — recorded decision: not shipped here

tk-l1pj6's second cause is that the mayor **has** the fragment and violated the
rule three times in one session anyway — "a correctly-worded instruction with
nothing enforcing it", the same shape as tk-76jxq. The bead says a mechanical
assist is *worth considering*, since stronger wording is what already exists and
is what failed.

It was considered. It is not shipped in this change, for the reasons below —
but note first that **one of the two channels has already been closed
mechanically, by a sibling bead, while this one was in flight.**

### 4a. What tk-76jxq already closed

tk-l1pj6 cites tk-76jxq as "open, same instruction-without-mechanism shape".
It closed on 2026-08-14 (`b1f7a8a`, PR #346). It routes every bead-scoped
escalation in `mol-refinery-patrol` through the shared
`assets/scripts/escalation-gate.sh`, gating **per anchor** with a 24h cooldown
(`[vars.escalation_cooldown]`), and the first of its four gated sites is the
find-work idle-loop held-anchor escalation — the exact path that produced
tk-l1pj6's "two escalations".

So the refinery's *escalation* channel is now mechanically rate-limited rather
than instruction-governed. That is the assist cause 2 asks for, delivered for
one channel. What it does not touch is composition: a gated escalation still
says whatever it says, and the gate has no view of the agent's prose at all.

Two surfaces therefore remain unenforced, and they are the two tk-l1pj6
actually describes:

- the refinery's **narration** — "repeated clock-refresh narration over ~7h",
  which is pane output, not mail, and passes no gate;
- the mayor's **reply composition** — pending approvals surfaced as an action
  item, then again as status, then again as a handoff carry-forward. The mayor
  sends no escalation here; it is answering the operator.

### 4b. The candidate mechanisms

**(A) Blocking `Stop` hook.** Scan the turn's final assistant message for
operator-approval-queue phrasing; on a match return `decision: block` with the
rule as the reason, honouring `stop_hook_active` so it fires at most once per
turn. Strongest lever — it acts on the output, which is where the violation
lives. Its cost falls hardest on the agent least able to absorb it: `converse`
posts its framing and then *waits in place* for the operator, so an extra
unsolicited message is a direct harm to the interaction the rule exists to
protect. It also breaks the stance the pack's existing Stop hook takes
explicitly ("ALWAYS exit 0 so the Stop event is never blocked").

**(B) Just-in-time `PostToolUse` reminder.** Fire when the agent reads the
operator's approval queue and inject the prohibition as `additionalContext` at
that moment — the proven-safe idiom (`overlays/work-context/`), non-blocking,
and timed to when compliance actually decays (the fragment was read at spawn,
tens of thousands of tokens earlier). Weaker, but it cannot interrupt anything.

(B) is the better shape. What stops it from being shippable *as designed here*
is that its trigger cannot be specified from static analysis: the commands that
surface the operator's queue are too varied to enumerate (`gh pr list` with
assorted filters, `gh pr status`, merge-skill output, bead rows routed to
`human`), and matching on tool *output* instead trades missed violations for
tokens burned on every false hit. Neither rate can be measured from this bead —
it needs observation against live mayor and refinery sessions.

### 4c. The structural blocker

`overlay_dir` is a single value per agent (`Agent.OverlayDir`, a `*string` that
patches *replace*; gascity `internal/config/patch.go`). Five of the six
operator-facing agents have a free slot. **The refinery does not** — its slot is
committed to `overlays/cycle-recycle`, which carries the landed 200K context
recycle (tk-g8pfg) and is asserted by `doctor/check-cycle-recycle-hook`.

Covering the refinery therefore means restructuring the pack's overlay topology
across six agents and rewriting a doctor check that guards a different bead's
fix. That is its own change with its own review. Landing it as a side effect of
a fragment-wiring fix is how an unreviewed topology change gets merged — and
shipping the guard onto only the five agents with free slots would repeat this
bead's own failure shape: a mechanism applied to the agents whose wiring
happened to be convenient, silently skipping the one that produces the traffic.

### 4d. What this change does instead

Distribution is now mechanically closed, and it is closed by code rather than by
wording: the check fails on an unclassified agent, so the *class* of error that
produced cause 1 cannot recur silently. Cause 2 is filed as **tk-2uyoh**, carrying
§4b and §4c in full, so the runtime guard is specified and blocked rather than
forgotten.

## References

- tk-fc28x — authored the rule (commit `84a5d40`, PR #340)
- tk-1u8mi — earlier correction to the same fragment (PR #316)
- tk-76jxq — closed 2026-08-14 (PR #346); the per-anchor escalation gate that
  closed the refinery's mail channel (§4a)
- tk-2uyoh — this bead's follow-up: enforcement on the two surfaces that gate
  cannot see
- tk-g8pfg — the cycle-recycle Stop hook that owns the refinery's overlay slot
- tk-osf13 — `overlays/work-context/`, the non-blocking hook idiom cited as (B)
- tk-t41dq — the precedent for a silently-unwired fragment, and the
  `check-polecat-fragment-sync` check this one is modelled on
- `specs/tk-23wdf/context-budget-ledger.md` §7 — the fragment's measured cost
