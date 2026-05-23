---
name: session-title
description: Use when the operator explicitly asks to set, view, suggest, or rotate a title for the current session — thread or canonical. Triggers include "rename this session", "rename this thread", "rename mechanik", "rename mayor", "set my title", "set the title to X", "what's my title", "what's my session title", "suggest a title".
---

# Session Title

Set, view, suggest, or auto-rotate the title for the current session.
Applies to both **threads** (mayor-thread, mechanik-thread, …) and
**canonical agents** (mayor, mechanik, deacon). The title shows up in
`gc session list`, the operator's session popup, the dashboard, and
(once the consumer side lands — tk-ki46h) the tmux footer, so a
descriptive title helps the operator and other agents see at a glance
what the session is on.

> **Operator-initiated only.** Do not invoke this skill unless the
> operator asks for it. The agent's own judgment that the title is
> stale or noisy is not a trigger; surface the suggestion in
> conversation and let the operator decide.
>
> The convention side of self-renaming — threads renaming when focus
> crystallizes, canonicals rotating as focus shifts — is documented
> in template fragments (`thread-role`, `canonical-self-rename`),
> not gated by this skill.

## Detect the form

This skill has four forms. Pick one based on what the operator typed:

- **Auto-rename** (default no-args) — `/session-title` with no args,
  or a bare "rename this session" / "rename this thread" /
  "rename mechanik" with no value supplied. Propose nothing — pick
  a forward-focus title from recent context and **apply it
  directly**.
- **Set** — `/session-title <text>`, or "rename this session to
  <text>", "set the title to <text>", "rename mechanik to <text>".
  Apply the operator's text verbatim.
- **View** — `/session-title --view`, or "what's my title",
  "what's my session title". Return the current title; do not
  rename.
- **Suggest** — `/session-title --suggest`, or "suggest a title",
  "what should this session be called?". Propose a title from
  recent context and **wait** for the operator to confirm, edit, or
  skip before applying.

The distinction between Auto-rename and Suggest is the friction
level: Auto-rename is the bread-and-butter operator gesture and must
be frictionless; Suggest is opt-in for when the operator wants to see
the proposal first.

## Auto-rename

No-args is the default. Look at recent context (see
[Title generation](#title-generation) below), choose a forward-focus
title, and apply it directly:

```bash
gc session rename "$GC_SESSION_ID" "<title text>"
```

Then echo a single line of confirmation so the operator doesn't have
to re-query:

> *Title set to "<text>".*

No proposal step, no permission prompt. If recent context is too thin
to choose a focused title, say so rather than guessing — and fall back
to Suggest behavior (propose and wait) so the operator can supply
direction.

## Set

```bash
gc session rename "$GC_SESSION_ID" "<title text>"
```

Use the operator's text verbatim. Don't add quotes, prefixes, or
status decoration. Don't truncate — render-side surfaces (footer,
dashboard) handle width budgets themselves.

After the rename completes, echo the new title back as a single line
so the operator sees confirmation without having to re-query:

> *Title set to "<text>".*

## View

```bash
gc session list --json \
    | jq -r --arg id "$GC_SESSION_ID" \
        '.sessions[]
         | select(.id == $id)
         | (.agent_name | sub("-adhoc-.*$"; "")) as $role
         | (if .title == .agent_name or .title == $role
              then "(no title set)"
              else (.title // "(no title set)")
            end)'
```

The `title` field is plumbed end-to-end in gascity but defaults to the
agent name (e.g. `gc-toolkit.polecat`) when no operator or agent has
refined it. For thread agents — whose `agent_name` includes an
`-adhoc-<hex>` suffix — gascity strips that suffix when assigning the
default, so `gc-toolkit.mayor-thread-adhoc-6d0c0eb30f` gets the
default title `gc-toolkit.mayor-thread`. The jq above collapses both
forms to `(no title set)` so the report reflects whether a
*meaningful* title exists, not whether the field happens to be
populated. Canonical sessions don't carry the `-adhoc-*` suffix; the
same jq still handles them correctly because the role-default check
covers both shapes.

## Suggest

Generate a title using [Title generation](#title-generation), then
**propose, don't auto-apply**. Surface the proposal and wait for the
operator to confirm, edit, or decline:

> *Proposed title: "<text>". Apply, edit, or skip?*

- **Apply** — run the Set form with the proposed text.
- **Edit** — use the operator's revised text and run the Set form.
- **Skip** — leave the current title; do not re-propose unless asked.

If recent context is thin (the session just started, or the
conversation has wandered without a clear focus), say so rather than
guessing: *"I don't have enough context yet to propose a focused
title — try again once the session has converged, or set one
manually."*

## Title generation

Used by both Auto-rename and Suggest. Look at the most recent
operator turns in your own context window — roughly the last ~10 user
messages and the agent replies they prompted — and pick a short title
(3-8 words) that describes the **focus** of the session: what the
operator and agent are *currently working on*, not what's been
finished or what state the work is in. Do not pull from older session
beads, bead descriptions, or unrelated transcripts — the title should
reflect the live session the operator is asking about.

**Forward focus, not historical summary.** A title that names a
decision already made or work already shipped is stale the moment
it's applied. Name what's still ahead.

> **Bad:** *"Evaluate gc-8p3dnt options and trade-offs"* — when the
> evaluation is already done and the session has moved on to
> shipping the follow-ups. The title locks the popup to a question
> that's already answered.
>
> **Good:** *"ship gc-8p3dnt doc + codex review"* — names the work
> still ahead. Operator scanning `gc session list` sees what this
> session is actually on.

This guidance applies to both Auto-rename (where you apply directly)
and Suggest (where you propose and wait). Both must look ahead, not
behind.

## Title style

Optimize for **future-self at a glance**:

- Verb + noun phrase, lowercase. "fix login redirect loop", "audit
  refinery handoff path", "spec convoy-id naming".
- 3-8 words. Long enough to be specific, short enough to fit a
  footer column.
- Topic, not status. "debugging X" or "wip X" is noise — every live
  session is in progress. "X" alone says more.

## When to self-rename (without being asked)

This is the **convention side** of the skill, not a trigger to invoke
it. Both modes below are documented in their respective template
fragments; this section cross-references rather than duplicating.

### Thread mode

Threads set a title early and change it rarely. The starting title is
either the role-name default or a short hint auto-seeded at spawn
time; once the conversation converges, the agent runs a single
`gc session rename` (no skill invocation) to lock in a concrete
focus — typical shapes are `<repo> PR #123` or a verb-noun phrase
naming the focus. See the `thread-role` template fragment for the
full convention.

### Canonical mode

Canonical agents (mayor, mechanik, deacon) **rotate** their title as
focus shifts. Unlike threads, the canonical's role-name default
(`mayor`, `mechanik`, `deacon`) gives the operator no signal beyond
"this agent is alive." A rotating focus title — `skill rename
audit`, `signal-loom landing convoy`, `tk-jct1gk PR triage` — makes
`gc session list` and the session popup scannable: the operator
sees what each canonical is currently on without having to peek.

The rotation is a single `gc session rename` per focus shift, run by
the agent itself (not the operator). See the
`canonical-self-rename` template fragment for the trigger and the
cadence.
