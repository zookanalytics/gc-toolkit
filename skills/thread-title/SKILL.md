---
name: thread-title
description: Use when the operator explicitly asks to set, view, or suggest a title for the current session. Triggers include "rename this thread", "what's my title", "set the title to X", or "suggest a title".
---

# Thread Title

Set, view, or suggest the title for the current session. The title
shows up in `gc session list`, the dashboard, and (once the consumer
side lands — tk-ki46h) the tmux footer, so a descriptive title helps
the operator and other agents see at a glance what the session is
about.

> **Operator-initiated only.** Do not invoke this skill unless the
> operator asks for it. The agent's own judgment that the title is
> stale or noisy is not a trigger; surface the suggestion in
> conversation and let the operator decide.

## Detect the form

This skill has three forms. Pick one based on what the operator typed:

- **View** — `/thread-title` with no args, or "what's my title".
- **Set** — `/thread-title <text>`, or "rename this thread to <text>",
  "set the title to <text>".
- **Suggest** — `/thread-title --suggest`, or "suggest a title",
  "what should this thread be called?". The agent proposes a title
  from recent conversation; the operator confirms before it's
  applied.

If the operator says "rename" or "title" without specifying a value
and without `--suggest`, route to the Suggest form below — propose a
title and let the operator confirm, edit, or skip. Don't ask whether
they have one in mind first; the absence of a value is the signal to
suggest.

## View

```bash
gc session list --json \
    | jq -r --arg id "$GC_SESSION_ID" \
        '.sessions[]
         | select(.id == $id)
         | (if .title == .agent_name
              then "(no title set)"
              else (.title // "(no title set)")
            end)'
```

The `title` field is plumbed end-to-end in gascity but defaults to the
agent name (e.g. `gc-toolkit/gc-toolkit.mayor-thread`) when no
operator or agent has refined it. The jq above collapses the
"`title == agent_name`" sentinel to `(no title set)` so the report
reflects whether a *meaningful* title exists, not whether the field
happens to be populated.

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

## Suggest

Look at the most recent operator turns in your own context window —
roughly the last ~10 user messages and the agent replies they
prompted — and propose a short title (3-8 words) that describes the
**focus** of the thread (what the operator and agent are working on,
not what's been finished or what state the work is in). Do not pull
from older session beads, bead descriptions, or unrelated transcripts
— the title should reflect the live thread the operator is asking
about.

**Propose, don't auto-apply.** Surface the proposal and wait for the
operator to confirm, edit, or decline:

> *Proposed title: "<text>". Apply, edit, or skip?*

- **Apply** — run the set form with the proposed text.
- **Edit** — use the operator's revised text and run the set form.
- **Skip** — leave the current title; do not re-propose unless asked.

If recent context is thin (the thread just started, or the
conversation has wandered without a clear focus), say so rather than
guessing: *"I don't have enough context yet to propose a focused
title — try again once the thread has converged, or set one
manually."*

## Title style

Optimize for **future-self at a glance**:

- Verb + noun phrase, lowercase. "fix login redirect loop", "audit
  refinery handoff path", "spec convoy-id naming".
- 3-8 words. Long enough to be specific, short enough to fit a
  footer column.
- Topic, not status. "debugging X" or "wip X" is noise — every live
  thread is in progress. "X" alone says more.

## When to self-rename (without being asked)

This is the **convention side** of the skill, not a trigger to invoke
it. The thread-role template fragment documents that threads should
self-rename when the focus crystallizes; that rename is a single
`gc session rename` call, not an invocation of this skill. Invoke
this skill only when the operator explicitly asks.
