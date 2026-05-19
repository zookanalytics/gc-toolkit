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

## Session title column

Each session row can carry a meaningful title in a right-side column,
separated by a `│` divider:

    [<rig>]<pad>  *▣  <pack>.<role>                              ← no title
    [<rig>]<pad>  *▣  <pack>.<role><pad2>  │ <session title>     ← with title

Layout details:

- The divider is a Unicode `│` (U+2502). Adjacent rows that carry a
  title align their dividers; rows without one end at `<pack>.<role>`
  and do NOT pad out to the divider column.
- `MAX_DISPLAY` is computed across S rows that carry a title. It's
  the max length of `<pack>.<role>` in that subset. The same display
  on a non-titled row is not padded — only titled rows participate.
- Titles longer than 40 chars truncate to 39 chars + `…` (40 visible
  cells total). Mirrors the pane-title truncation pattern, slightly
  wider for full session titles.

### Boring-title suppression

Many sessions have a title equal to their derived display name plus
a `<rig>/` prefix — e.g., the picker shows `gc-toolkit.refinery` but
the gc title is `gc-toolkit/gc-toolkit.refinery`. That's not new
information; rendering it would add visual noise.

The rule: strip a leading `<rig>/` from the title (matching the
picker's derived rig for that row) before comparing. If the
normalized title equals the display, suppress the entire ` │ <title>`
suffix. The boring case renders exactly as it did before this
feature was added.

The strip only kicks in for non-city rigs — `city` rows have no
`<rig>/` prefix in the display, so no normalization is needed.

### Data source and join

The picker fetches the title map from:

    timeout 3 gc session list --json | jq -r '.sessions[]? | …'

The join key is `session_name` — present on both the tmux side
(`#{session_name}`) and the gc session record. jq sanitizes the
title (strips `\t\r\n`) so it's safe to embed in the awk pipeline's
TSV channel.

### Graceful fallback

`gc session list --json` is a subprocess against the data plane and
can fail in several ways. The picker MUST still render in every
case — no titles, no broken layout, no missing menu.

- Bound the call with `timeout 3`. A wedged Dolt cannot block the
  picker beyond 3s.
- Non-zero exit (gc errors, command-not-found, timeout): the `|| true`
  trailer reduces the failure to an empty `TITLES` string.
- Malformed JSON: jq errors are suppressed (`2>/dev/null`) and produce
  empty output.
- Empty output / no session_name+title pairs: the awk title map stays
  empty.

In every failure mode, every row renders as if the feature were
disabled. `MAX_DISPLAY` falls back to 0; the `if [ -n "$stitle" ]`
guard in the shell ensures no row tries to render a divider.

### Mode coverage

Titles render in **both** default collapsed mode and `--all` mode.
The most title-rich rows today are force-spawn polecats, which are
hidden in default mode and only visible under `--all` — so the
operator gains the most visibility there. Coordinator threads with
custom titles also benefit in default mode.

### Worked example

`--all` mode with a mix of boring, meaningful, and truncated titles:

    [city]         ▣  gc-toolkit.mayor
    [city]         ▣  gc-toolkit.mayor-thread-adhoc-93f76e17c4  │ gc-toolkit.mayor-thread
    [gascity]         gc-toolkit.polecat-adhoc-aaa              │ Force-spawn: PR21 doc-ref fix
    [gascity]         gc-toolkit.polecat-adhoc-bbb              │ Very long title that should definitely…
    [gc-toolkit]      gc-toolkit.furiosa
    [gc-toolkit]  *   gc-toolkit.nux
    [gc-toolkit]      gc-toolkit.refinery

Notes:

- `gc-toolkit.mayor` has no gc title set → no divider.
- `gc-toolkit.nux` / `gc-toolkit.refinery` carry the boring default
  title (`gc-toolkit/gc-toolkit.nux` etc.) → suppressed.
- Polecat-adhoc rows show their force-spawn intent; the second one
  truncated to 39 + `…`.
- `MAX_DISPLAY` here is 40 (the mayor-thread row), so the dividers
  on shorter polecat displays pad out to that width.

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

## Per-rig grouped headers

In the **default collapsed view** (`ALL=0`) the picker anchors each
rig's sessions under a header row:

    ── city ──
    [city]       *▣  gc-toolkit.mechanik
    [city]       *   gc-toolkit.mayor

    ── gascity • 3 polecats ──
    [gascity]    *▣  gc-toolkit.refinery
    [gascity]        gc-toolkit.witness

    ── gc-toolkit ──
    [gc-toolkit]     gc-toolkit.deacon

    ── signal-loom • 1 polecat ──
    [signal-loom]    gc-toolkit.witness

    [ show all ]

Rules:

- Header always rendered per rig group that has at least one visible
  session row. Rigs with all sessions filtered out get NO header (no
  dangling group).
- Polecat-count suffix only when count > 0. Singular `1 polecat`,
  plural `N polecats`.
- Headers are disabled tmux `display-menu` rows (leading `-` on the
  name — tmux strips it and renders the rest dim and non-selectable).
- Blank separator line (empty menu entry `"" "" ""`) between groups,
  not before the first group.
- The `--all` mode keeps the flat layout — no headers, no
  separators — because polecats are visible there and the extra
  framing would be noise.

### Polecat detection

A session counts as a polecat iff its `session_name` contains the
substring `polecat`. This mirrors the existing collapsed-mode filter
rule, so it catches every variant by convention:

- `polecat-adhoc-*` (claude pool)
- `polecat-codex-adhoc-*` (codex pool)
- `polecat-<bead-id>` (named-pool dispatches: slit, furiosa, rictus, nux)
- future agent-provider prefixes (`polecat-gemini-*`, …)

The count covers ALL polecat sessions in the rig — visible AND
hidden. The currently-attached session is always shown but still
counts.

### Why headers are disabled rows, not separators

tmux `display-menu` treats `""` as a horizontal-rule separator (no
text) and `-<name>` as a non-selectable item (renders, ignored on
pick). Headers carry the rig name + polecat count, so they're
disabled items. The blank between groups uses the separator form.

### MAX_RIG width

Header rows put the rig name in the same field 2 that S/P rows use
for the `[rig]` column. The width calculation is unchanged — the rig
name in a header has the same length as the rig name in its session
rows, so `MAX_RIG` stays correct without a special case.

## Hotkey allocation

Per-row hotkeys come from `abcdefghijklmnopqrstuvwxyz0123456789` (36
slots). Each **session or pane row** consumes one slot in order.
Header rows and blank separators do **not** consume slots. Beyond row
36, rows still render and remain pickable via arrow-Enter, but get no
hotkey letter (existing behavior, preserved).

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

`ACTIVE_IDX` counts every emitted menu item — sessions, panes,
headers, blank separators — so it still points at the session row,
not at the header above it.

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
- mail-counts, bead IDs, current-claimed-bead inline in the row
  (session title is now in scope — see "Session title column" above
  for what it covers and what it deliberately does not)
- auto-updating the session title from current work / claimed bead.
  Titles are set at session creation (`--title`, `--title-hint`) or
  via `gc session rename`; the picker only renders what's already
  there.
- changing the `prefix+S` binding line in `~/.tmux.conf`
- per-rig grouped headers in `--all` mode
- richer per-rig status in the header (windows count, attached-state
  rollup, mail counts) — only the polecat count is rendered today
