# tmux-pick-session — design notes

The Gas City session picker, bound to `prefix+S` in tmux:

    run-shell /home/zook/loomington/rigs/gc-toolkit/assets/scripts/tmux-pick-session.sh

This is the operator's primary jumper between Gas City agent sessions.

## Who this is for

The operator triaging Gas City agent sessions. A Gas City has many tmux
sessions per rig (mayor, mechanik, deacon, witness, refinery,
polecat-*, …) and the operator needs to jump between them quickly,
with the noisy populations (polecat-*, control-dispatcher, deacon,
witness, dog, boot) hidden by default.

It is **not** trying to be a full tmux-feature-parity picker. No
preview pane. No fzf. No mail-counts / agent-metadata / last-bead in
the row. It is a scoped, fast picker tuned for our rig topology.

## Why display-menu, not choose-tree

`tmux choose-tree -Zs` would, at first glance, give pane drill-down
plus a preview window for free. We **cannot** use it because:

- `choose-tree -F <fmt>` only governs the trailing metadata block of
  each row.
- The leading `session: window: pane:` triplet is **hardcoded** in
  tmux source — see `window-tree.c`. It cannot be substituted with
  our `<rig>  <pack>.<role>` display name.

We rely on the rig-aware label as the operator's primary visual
anchor, so losing the leading column rules out `choose-tree`. The
fallback is `display-menu`, which gives us full control of every
row's label.

Future readers: please don't re-derive this. Read `window-tree.c`.

## Inline pane expansion (vs sub-menu, vs popup)

When a session has more than one pane, the script emits one menu row
per pane, indented under the session row, in the **same**
`display-menu`. Layout:

    [<rig>]<pad>  *▣  <pack>.<role>           ← session row
    [   ] <pad>      • ↳ <name>:<w>.<p> <cmd>  <title>   ← pane sub-row
    [   ] <pad>        ↳ <name>:<w>.<p> <cmd>  <title>   ← pane sub-row

Alternatives considered and rejected:

- **Chained sub-menu** (pick session → opens new menu of panes): adds
  a click-step. The operator usually knows which pane they want
  before opening the picker. One flat menu = faster.
- **`display-popup -E fzf …`**: more powerful, but adds an external
  dependency and reflows the whole interaction model. Out of scope
  for now.

Pane row command:

    switch-client -t <session> ; \
        select-window -t <session>:<window> ; \
        select-pane -t <session>:<window>.<pane>

Picking a session row (the parent) still does plain
`switch-client -t <session>` — i.e., lands on whatever pane the
session was last on. Existing behavior preserved.

## Multi-window indicator (▣)

A session with more than one tmux window gets a `▣` glyph adjacent to
the existing `*` attached marker on its row. Single-window sessions
get a space in the same column.

Semantically, in our setup this maps to **interactive vs
non-interactive**:

- Single-window sessions are agent runtime sessions: one
  claude/codex/gemini in pane `:^.0`, plus optional helper panes the
  agent manages itself. The operator does not normally edit these.
- Multi-window sessions are richer working environments — operator
  hand-built shells, `crew/` workspaces, etc. — places where the
  operator actively works across multiple viewports.

The `▣` glyph (a square containing a square) hints "more inside."
It is **separate** from the inline pane expansion: a single-window,
multi-pane session gets the inline pane sub-rows but **not** the `▣`.
The two markers answer different questions.

## Hotkey allocation

Per-row hotkeys come from `abcdefghijklmnopqrstuvwxyz0123456789` (36
slots). Each row consumes one slot in order — session rows AND pane
sub-rows alike. Beyond row 36, rows still render and remain pickable
via arrow-Enter, but get no hotkey letter (existing behavior,
preserved).

This means a city with many multi-pane sessions can run out of
hotkey letters faster than before. We accept this — the alphabet is
bounded, and arrow-keys still work. If it becomes a real problem in
practice, two natural fixes:

- skip pane rows when allocating hotkeys (sessions only),
- or allocate a separate keyspace (e.g., uppercase letters) to panes.

Defer until a real complaint.

## Active-row default cursor

The menu opens with the cursor on the **session row** of the
currently-attached session. Pane sub-rows do NOT change cursor
placement. Picking the parent session row from this position is a
no-op (`switch-client -t` to where you already are), but the cursor
gives spatial context for "where am I in the list."

## Filter toggle

Default mode hides session names matching `polecat`,
`control-dispatcher`, `deacon`, `witness`, `dog`, `boot`. The
currently-attached session is always shown regardless of the filter.

The last menu row is `[ show all ]` (or `[ show fewer ]` while in
`--all`), bound to `.`. Picking it re-runs the script with the
toggled flag. Pane sub-rows obey the same filter — they only render
beneath sessions that survive the filter pass.

## Files

- `tmux-pick-session.sh` — the script
- `tmux-pick-session.md` — this doc

## Out of scope

- preview pane / live `capture-pane` tail
- fzf or `display-popup -E` rewrite
- mail-counts, agent metadata, last-bead inline in the row
- changing the `prefix+S` binding line in `~/.tmux.conf`
