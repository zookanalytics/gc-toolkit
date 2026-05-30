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

Each row joins the tmux session list with the supervisor sessions API on
`session_name` and renders the gc session title in a right-side column:

    [<rig>]<pad>  *▣  <pack>.<role>                              ← no title (boring or no match)
    [<rig>]<pad>  *▣  <pack>.<role><pad2>  │ <40-char title>     ← with title

The title is the operator-meaningful label set at session creation
(`--title`, `--title-hint`) or via `gc session rename`. Example titles
that already exist in the corpus today:

    Force-spawn: PR21 doc-ref fix
    Force-spawn polecat #2 for rework queue
    Rework iteration one
    Review PR#8

### Boring-title suppression

Many sessions carry a default title that matches the picker's derived
display (e.g. `gc-toolkit/gc-toolkit.refinery` for a session the
picker already labels `gc-toolkit.refinery`). Rendering those would be
pure noise. Suppression rule:

- Strip a leading `<rig>/` prefix from the title before comparing.
  Titles like `gc-toolkit/gc-toolkit.refinery` collapse to
  `gc-toolkit.refinery` for the comparison — matching the picker's
  rig-prefix-collapsed display column.
- If the (stripped) title equals the display, omit the entire
  ` │ <title>` suffix. The row renders exactly as it did before this
  feature shipped.

When suppressed, the row does NOT pad out to the divider column. Only
rows that actually carry a title pay for the alignment.

### Truncation

`MAX_TITLE = 40` bytes (awk `length()` semantics; mostly ASCII in
practice). Titles longer than 40 are truncated to 39 bytes + `…`,
mirroring the pane-title truncation style already in the script
(`cut -c1-30…`), one char wider to fit full session titles.

### Divider alignment

`MAX_DISPLAY` is computed across the row set as the max display
width among S rows that carry a non-empty title. The shell loop pads
the display column out to `MAX_DISPLAY` before emitting ` │ <title>`,
so the divider lines up vertically across rows that have titles.
Rows without titles end at `<pack>.<role>` and do not pad.

### Graceful fallback

Titles come from a `curl` call to the supervisor sessions API, bounded
with `curl --max-time 3` so a wedged data plane cannot block the
picker. Any failure — non-zero exit (including the cold-cache 503
swallowed by `curl -f`), missing `curl`, missing `jq`, parse error,
timeout — yields an empty `TITLES` and the picker renders without any
titles. The call is skipped entirely when no city resolves. The menu
must always open; titles are strictly optional adornment.

### Data source

```
GET <api-base>/v0/city/<city>/sessions
```

Returns `{items: [{session_name, title, …}, …]}`. The picker's
existing `#{session_name}` key from `tmux list-sessions` joins
directly to `.items[].session_name`, with no name translation. The
script resolves `<api-base>` (supervisor port) and `<city>` via its
`gc_api_base` / `gc_city_name` helpers — see their comment block for
the `~/.gc/supervisor.toml` port and `~/.gc/cities.toml`
city-resolution detail.

### --all mode

Titles render in both default and `--all` modes. The most
title-rich sessions today are force-spawn polecats (hidden in
default mode), so `--all` is where the change is most visible. But
mechanik-thread, mayor-thread, and other sessions with non-default
titles also benefit in default mode.

### Why not strip the rig prefix from the rendered title

The comparison strips `<rig>/` only to detect boringness. When the
title is shown, it is shown verbatim. A title that survived the
boring check carries information the operator chose to put there —
the toolkit does not second-guess what part of it is "redundant."

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

- Header always rendered per rig group with at least one tmux session,
  regardless of whether any session survives the default filter. A rig
  whose body is fully filtered renders as a bare `── <rig> ──` (or
  `── <rig> • N polecats ──`) with no selectable rows beneath. That is
  the intended UX: "this rig exists, hit `.` to see what's hidden."
  Rationale: the operator's primary use of the picker is topology
  awareness, not just session-jumping. A rig existing-but-currently-quiet
  — especially one whose only sessions are hidden polecats — is
  information worth surfacing. Without this rule the polecat count
  (the surfacing mechanism for hidden polecats) is itself hidden when
  every other session in the rig also matches the default filter.
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
- mail counts, agent metadata, last-bead inline in the row
- auto-updating the session title from the current claimed bead.
  Titles are set at session creation (`--title`, `--title-hint`) or
  via `gc session rename` — that machinery exists already and is not
  the picker's concern.
- a separate "current bead" column distinct from title
- changing the `prefix+S` binding line in `~/.tmux.conf`
- per-rig grouped headers in `--all` mode
- richer per-rig status in the header (windows count, attached-state
  rollup, mail counts) — only the polecat count is rendered today
