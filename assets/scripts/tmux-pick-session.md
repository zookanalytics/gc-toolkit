# tmux-pick-session — design notes

The Gas City session picker, bound to `prefix+S` in tmux:

    run-shell /home/zook/loomington/rigs/gc-toolkit/assets/scripts/tmux-pick-session.sh

This is the operator's primary jumper between Gas City agent
sessions — documented here for both the script's maintainers and the
agents pointed at these notes by the mechanik Agent Brief.

## Who this is for

The operator triaging Gas City agent sessions. A Gas City has many tmux
sessions per rig (mayor, mechanik, deacon, witness, refinery,
polecat-*, …) and the operator needs to jump between them quickly,
with the noisy populations (polecat-*, control-dispatcher, deacon,
witness, dog, boot) hidden by default.

It is **not** trying to be a full tmux-feature-parity picker. No
preview pane. No fzf. No mail-counts / agent-metadata / last-bead in
the row. It is a scoped, fast picker tuned for our rig topology.

## Implications for agents

The mechanics live in the rest of this file; what follows is the
judgment those mechanics force on agents.

- **Drained sessions are invisible.** The picker enumerates live
  tmux sessions (`tmux list-sessions`). A drained `on_demand`
  session has no pane, so it does not appear in the menu and is not
  counted in its rig header — unreachable by the operator's
  pick-by-title navigation. This is the documented root of the
  pin-vs-attach friction and the keeper "always-materialize"
  decision. When making session-lifecycle or materialization calls
  (`always` vs `on_demand`, pin vs attach), account for picker
  visibility: an agent the operator needs to reach by title should
  be materialized, not drained.

- **Titles are the operator's scannability surface.** The gc session
  title an agent sets (`--title`, `--title-hint`, `gc session
  rename`) is what renders in the title column, boring titles
  suppressed (see "Session title column"). This is why the
  canonical-self-rename doctrine
  (`template-fragments/canonical-self-rename.template.md`) matters:
  an un-renamed session is a needle in the role column.

- The companion `prefix+a` binding (installed by
  `tmux-bindings.sh`, runs `tmux-spawn-thread.sh`) spawns a thread
  of the current pane's role.

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

The two fixed bottom entries use punctuation keys *outside* this
keyspace — `,` (keeper pin/unpin) and `.` (filter toggle) — so they
stay stable regardless of how many rows precede them and never collide
with a per-row letter.

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

## Keeper pin/unpin entry

A fixed entry sits just above `[ show all ]`: `[ ⚡ pin keeper ]` when the
gascity-keeper is unpinned, `[ ✕ unpin keeper ]` when it is pinned, and a
neutral `[ keeper… ]` when the pin state cannot be read in time. It is a
standalone menu action, **not** a per-session row — the keeper runs
`on_demand`, so when drained it has no pane (no row to hang a per-row action
on), yet the operator still needs a surface to bring it up.

Both the pin-state detection and the pin/unpin call live in the sibling
`tmux-keeper-toggle.sh` (one shared helper). The picker calls it in `state`
mode to choose the label. The label tracks the **real durable pin** — the
keeper session bead's `metadata.pin_awake` — not tmux liveness: an
on_demand keeper materializes for any durable wake reason (most commonly
work on its hook), so a live pane does not imply a pin, and a
liveness-derived label would offer "unpin" on a keeper the operator never
pinned. Neither the `gc session list --json` rows nor the supervisor
sessions API expose pin state, so the helper makes a two-step gc/beads
read — resolve the keeper's session bead ID by alias from one
`gc session list --json` call, then read `pin_awake` via `gc bd show` —
with each step wall-clock bounded so a slow or wedged beads backend
cannot stall the picker open: on timeout/failure the label degrades to
the neutral `[ keeper… ]` instead of guessing. Selecting the entry runs
the helper's `toggle` via `run-shell -b`, so a slow `gc session pin`
cannot freeze the server; `toggle` re-reads the pin state itself (under a
more generous bound, since it runs backgrounded) and refuses to act while
it is unknown — so the neutral entry stays actionable. Its hotkey is `,`
— a fixed punctuation slot (like `.` for the filter toggle), outside the
`a-z0-9` per-row keyspace so it never collides. See `gascity-agents.md` →
"The gascity-keeper front-door" for the operator-facing model.

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
- `tmux-keeper-toggle.sh` — the keeper pin/unpin helper the picker shells
  out to for the fixed `[ pin/unpin keeper ]` entry (state + toggle)

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
