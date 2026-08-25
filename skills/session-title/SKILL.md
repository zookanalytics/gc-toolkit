---
name: session-title
description: Use when the operator explicitly asks to set, view, suggest, or rotate a title for the current session. Triggers include "rename this session", "rename mechanik", "set my title", "set the title to X", "what's my title", "what's my session title", "suggest a title".
---

# Session Title

Set, view, suggest, or auto-rotate the title for the current session.
Applies to **canonical agents** (mechanik, deacon) and to any ad-hoc
session the operator spawns. The title shows up in `gc session list`,
the operator's session popup, and the dashboard, so a descriptive title
helps the operator see at a glance what the session is on.

> **Operator-initiated only.** Do not invoke this skill unless the
> operator asks for it. The agent's own judgment that the title is
> stale or noisy is not a trigger; surface the suggestion in
> conversation and let the operator decide.
>
> The convention side of self-renaming — canonicals rotating as focus
> shifts — lives in each agent's own prompt, not gated by this skill.

## Detect the form

This skill has four forms. Pick one based on what the operator typed:

- **Auto-rename** (default no-args) — `/session-title` with no args,
  or a bare "rename this session" / "rename mechanik" with no value
  supplied. Propose nothing — pick
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
to choose a focused title, say so rather than guessing — explain that
context is thin and ask the operator to supply a phrase, or to use
`--suggest` if they want a proposal first. Do **not** silently fall
through into Suggest; the no-args path is direct-auto-apply by design,
and routing into propose-and-wait breaks that contract. `--suggest`
remains the explicit form when the operator wants to see and approve a
proposal.

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

The `title` field defaults to the agent name when nobody has refined it
(with any `-adhoc-<hex>` suffix stripped when the default is assigned).
The jq collapses both default forms to `(no title set)` so the report
reflects whether a *meaningful* title exists, not whether the field is
populated.

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
decision already made or work already shipped is stale the moment it's
applied. *"Evaluate options and trade-offs"* is bad once the evaluation
is done; *"ship session-title doc + codex review"* names the work still
ahead. Applies to Auto-rename and Suggest alike.

## Title style

Optimize for **future-self at a glance**:

- Verb + noun phrase, lowercase. "fix login redirect loop", "audit
  refinery handoff path", "spec convoy-id naming".
- 3-8 words. Long enough to be specific, short enough to fit a
  footer column.
- Topic, not status. "debugging X" or "wip X" is noise — every live
  session is in progress. "X" alone says more.
- Human-meaningful references, not opaque IDs. `<repo> PR #N`, topic
  names (`session-title`, `signal-loom`), and verb-noun phrases all
  scan. Bare bead IDs (`tk-xxxxx`, `gc-yyyyy`) leave the operator
  with nothing to read at a glance.

## When to self-rename (without being asked)

This is the **convention side** of the skill, not a trigger to invoke
it. The mode below is documented in its template fragment; this
section cross-references rather than duplicating.

### Canonical mode

Canonical agents (mechanik, deacon) **rotate** their title as focus
shifts. The role-name default gives the operator no signal beyond "this
agent is alive"; a rotating focus title — `skill rename audit`,
`gc-toolkit PR #60 review triage` — makes `gc session list` scannable.
Use a human-meaningful reference (a `<repo> PR #N` form or
topic/verb-noun phrase) — a bare bead ID gives nothing to scan.

The rotation is a single `gc session rename` per focus shift, run by
the agent itself (not the operator); each agent's prompt states the
trigger and the cadence.
