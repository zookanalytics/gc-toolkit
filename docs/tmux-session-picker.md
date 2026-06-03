---
name: tmux session picker
description: Agent-facing reference for the Gas City session picker (prefix+S) — bindings, default filter, layout, title column, indicators, and the drained-session visibility implication that constrains session-lifecycle decisions.
---

# tmux session picker

The session picker is the operator's primary jumper between Gas City
agent sessions. It is the only pick-by-title navigation surface, so
its behavior is load-bearing context for any decision about session
lifecycle, materialization, or titling. Read this before reasoning
about those; the deep implementation rationale lives in the design
notes (see [Pointer](#pointer)).

## What it is + bindings

Two keybindings, installed by
[`assets/scripts/tmux-bindings.sh`](../assets/scripts/tmux-bindings.sh)
from `pack.toml`'s `[global] session_live` on every agent session
start (server-wide and idempotent):

- **`prefix+S`** runs `tmux-pick-session.sh` — the picker. Opens a
  `display-menu` titled ` Sessions ` centered on the current client.
- **`prefix+a`** ("ask") runs `tmux-spawn-thread.sh` — spawns a
  thread of the **current pane's role** (e.g. from a `mechanik` pane
  it spawns `mechanik-thread`), prompting for a first-message seed in
  a popup.

The picker baked-in `--city-path` is captured at install time because
the key fires from tmux's bare env, which does not carry Gas City's
session environment.

## Default filter

In the default (collapsed) view the picker hides session names
matching any of: `polecat`, `control-dispatcher`, `deacon`,
`witness`, `dog`, `boot`. The **currently-attached session is always
shown**, even if its name matches. Press **`.`** to toggle
show-all / show-fewer (the last menu row, `[ show all ]` /
`[ show fewer ]`).

## Layout

The collapsed view is grouped under per-rig header rows:

```
── city ──
  [city]        *▣  gc-toolkit.mechanik   │ <title>
  [city]        *   gc-toolkit.mayor

── gascity • 3 polecats ──
  [gascity]     *▣  gc-toolkit.refinery
  [gascity]         gc-toolkit.witness

  [ show all ]
```

- The **`[city]` group sorts first**; other rigs follow
  alphabetically.
- **Polecats sort last within their rig.**
- Rows are labeled `[<rig>]  <pack>.<role>`. The bracketed rig column
  is padded to a common width for alignment.
- Headers carry a **per-rig polecat count** when > 0
  (`── <rig> • N polecats ──`, singular `1 polecat`). A header is
  rendered for every rig with at least one **live** session, even
  when the filter hides all of them — so a quiet rig still surfaces
  for topology awareness. The count covers all polecats in the rig,
  visible and hidden.

## Title column

Each row joins the live tmux session list with that session's
`gc session` title (read from the running supervisor; absent and
silently skipped if the supervisor is unreachable) and renders it in
a right-side ` │ <title>` column. The title is the operator-meaningful
label set via `--title`, `--title-hint`, or `gc session rename`.

Titles that match the picker's derived display name (after stripping a
leading `<rig>/`) are suppressed as **boring** — the row renders
without a title column rather than echoing `gc-toolkit.refinery` back
at itself.

**Implication:** the title an agent sets for itself is the operator's
scannability surface in this menu — a row with no meaningful title is
just `[rig] <pack>.<role>`. This is *why* the
[`canonical-self-rename`](../template-fragments/canonical-self-rename.template.md)
doctrine matters: a self-renamed session is one the operator can find
by title; an un-renamed one is a needle in the role column.

## Indicators

- **`*`** — the session is attached.
- **`▣`** — the session has more than one tmux window. In our setup
  this maps to an **interactive working environment** (operator
  shells, `crew/` workspaces) versus a single-window agent runtime.
- **`•`** — the active pane within its window (only on inline pane
  sub-rows).

A session with more than one pane gets **inline pane sub-rows** in the
same menu (`↳ <name>:<window>.<pane> <cmd>`), indented under its
session row. Multi-pane and multi-window are distinct signals: a
single-window, multi-pane session gets sub-rows but no `▣`.

## Load-bearing implication: drained sessions are invisible

The picker enumerates **live tmux sessions** (`tmux list-sessions`).
A drained `on_demand` session has no tmux pane, so:

> a drained `on_demand` session does **not** appear in the picker, and
> is therefore **unreachable by pick-by-title navigation** — it isn't
> even counted in its rig's header.

This is the root of the pin-vs-attach friction and the keeper
"always-materialize" decision. When choosing a session's
materialization mode (`always` vs `on_demand`) or deciding pin vs
attach, account for picker visibility: an agent the operator needs to
reach by title should be materialized, not drained. See
[gascity-agents.md](gascity-agents.md) for the lifecycle modes
themselves.

## Pointer

Deep design rationale — why `display-menu` and not `choose-tree`,
the inline-pane-vs-sub-menu trade-off, hotkey allocation across the
36-slot alphabet, divider alignment, and boring-title suppression
mechanics — lives in the companion design notes,
[`assets/scripts/tmux-pick-session.md`](../assets/scripts/tmux-pick-session.md).
That file is the source of truth for *how*; this doc is the
agent-facing *what* and *why-it-matters*. Do not duplicate the design
notes here.
