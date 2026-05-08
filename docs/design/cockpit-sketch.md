# Cockpit — observability TUI session sketch

A non-LLM tmux session managed by Gas City's supervisor. Goal: a
keyboard-attachable view of city state (gc status, bd ready, events
tail, session list) that lives next to all the agent sessions and
benefits from the same lifecycle management.

**Status:** sketch. The launcher script lives at
`assets/scripts/cockpit.sh` but no agent template, provider, or
named-session registration is wired into the running city yet. To
activate, apply the snippets below and `gc reload`.

## Why this shape

`gc dashboard serve` is HTTP. We want a tmux-attachable view —
`tmux attach -t cockpit` or `gc session attach cockpit`.

Three options were considered (see conversation notes):

1. **Hand-rolled tmux session** — zero infra, lives outside Gas City.
2. **Custom provider + agent template** — schema-blessed extension
   point, partial fit, supervisor-managed. *This sketch.*
3. **Built-in like control-dispatcher** — special-cased Go code in
   gascity. Out of scope.

control-dispatcher proves Gas City already manages non-LLM tmux
sessions; it just hardcodes the dispatcher in Go. The
`[providers.<name>]` block is the right user-extensible door for the
same pattern.

## Activation — single block in city.toml

The `examples/lifecycle/` pack in gascity ships polecat agents wired
with `start_command` and no provider/prompt_template. That's the
sanctioned non-LLM entrypoint pattern. Add this one block to
`city.toml`:

```toml
# ─── COCKPIT (sketch) — observability TUI singleton ──────────────
# Revert: delete this block + `gc reload`.
[[agent]]
name = "cockpit"
scope = "city"
work_dir = ".gc/agents/cockpit"
start_command = "/home/zook/loomington/rigs/gc-toolkit/assets/scripts/cockpit.sh"
wake_mode = "resume"
min_active_sessions = 1
max_active_sessions = 1
```

`min/max_active_sessions = 1` gives the always-on singleton without
needing `[[named_session]]`. Attach via the generated session ID:

```bash
gc reload
gc session list | grep cockpit
gc session attach <id>
```

### Optional: stable `cockpit` alias

If you want `gc session attach cockpit` instead of a generated ID,
add this second block. **Unverified** — every gascity example puts
`[[named_session]]` in pack.toml, not city.toml. Try it; if
`gc reload` rejects, drop it.

```toml
[[named_session]]
template = "cockpit"
scope = "city"
mode = "always"
```

## Expected wins

- Lifecycle: supervisor restarts cockpit on crash.
- Visibility: appears in `gc session list`, `gc session peek` works.
- Discoverability: `gc session attach cockpit` from anywhere.
- No LLM cost.

## Known unknowns / failure modes to watch

- **Idle suspension.** Cockpit has no ACP traffic, so the supervisor
  may treat it as idle and suspend it on whatever default timeout
  applies. The `[[agent]]` block above omits `idle_timeout`,
  inheriting whatever default applies to start_command agents — the
  lifecycle polecat sets `idle_timeout = "5m"` and gets suspended
  after work, which is the OPPOSITE of what we want. If cockpit
  suspends, set `idle_timeout = "240h"` or look for a "no-suspend"
  flag in the schema.
- **Nudge behavior.** `gc session nudge <id> "..."` will likely
  `tmux send-keys` text into the foreground pane, polluting the
  status display. Treat cockpit's nudge channel as off-limits.
- **Hook installation.** `install_agent_hooks` may try to install
  Claude hooks on the cockpit work_dir. With no LLM running this
  is harmless dead config but could log warnings.
- **Restart loops.** If the script exits cleanly (no `exec` at
  the end) the supervisor may interpret normal exit as crash and
  rapid-restart. The current script ends in `exec sh -c '...'`
  which keeps the foreground process alive indefinitely.
- **Pane re-layout on restart.** The script guards against
  re-splitting via `panes >= 4` check, but a partial split (say,
  3 panes due to a prior failure) would leave the layout in a
  weird state. Consider a stronger guard (named panes via
  `tmux set-option -p @cockpit-pane`) if this becomes a problem.

## Fallback if `start_command` doesn't work

Drop back to option 1 from the conversation: hand-rolled tmux
session via a `make cockpit` target that runs `cockpit.sh`
against a manually-created tmux session. Lose supervisor
management; keep everything else.

## Graduation path

If cockpit becomes a daily-attach tool, the natural next steps are:

1. Replace the shell-loop foreground with a real bubbletea/textual
   TUI binary — same provider config, swap `command`.
2. Add navigation: bead drilldown, session jump, log filtering.
3. If the feature pattern proves out, pitch upstream as a
   first-class "named-process session" concept that doesn't require
   shoehorning through the LLM provider schema. That's the
   "engage" branch of the upstream framework — only after we've
   used cockpit enough to know what shape it should take.
