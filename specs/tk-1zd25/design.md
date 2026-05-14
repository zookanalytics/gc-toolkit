# Per-role threads: smart binding, first-prompt seed, scope match (`tk-1zd25`)

**Bead:** `tk-1zd25` (child of epic `tk-j2vir`)
**Branch:** `polecat/tk-1zd25-per-role-threads`
**Polecat:** `gc-toolkit/gc-toolkit.furiosa`
**Surveyed at:** 2026-05-13

Builds on the `mechanik-thread` spike (`tk-k9s0k` / PR #9) by
generalizing the Role+Thread primitive to a second interactive role
(`mayor-thread`), fixing a scope-mismatch bug on the existing
`mechanik-thread`, and wiring `Ctrl-B + a` to spawn a thread of the
*current pane's* canonical role.

## Change set

| File | Change | Why |
|---|---|---|
| `agents/mechanik-thread/agent.toml` | `scope = "rig"` → `scope = "city"`; fragment renamed `mechanik-thread-role` → `thread-role`; new `[env] RoleName = "mechanik"` | Match canonical mechanik's city scope; share generic fragment |
| `agents/mechanik-thread/PROVENANCE.md` | Reflect city scope + generic fragment | Track the cutover |
| `agents/mayor-thread/agent.toml` | new, symmetric to mechanik-thread | Operator wants a mayor-thread too |
| `agents/mayor-thread/PROVENANCE.md` | new | Provenance discipline |
| `template-fragments/thread-role.template.md` | new, generic, parameterized by `{{ .RoleName }}` | Single fragment for all role-threads |
| `template-fragments/mechanik-thread-role.template.md` | deleted | Replaced by `thread-role` |
| `assets/scripts/tmux-spawn-thread.sh` | new | `Ctrl-B + a` handler — detects current agent, spawns matching thread |
| `assets/scripts/tmux-bindings.sh` | `Ctrl-B + a` repointed: `tmux-spawn-scratch.sh` → `tmux-spawn-thread.sh` | Threads supersede scratches for the role-as-conversation pattern |
| `assets/scripts/tmux-spawn-scratch.sh` | **deleted** | Replaced by threads; no callers after the bindings update |
| `template-fragments/scratch-clone-guard.md` | **deleted** | Companion fragment for the deleted scratch script |
| `agents/{mayor,architect,concierge,gascity-keeper}/prompt.template.md` | "scratch notes" / "scratchpads" → "working notes" / "drafts" | Drop residual user-facing "scratch" terminology |
| `template-fragments/operational-awareness.template.md` | "scratchpads" → "throwaway notes" | Same |
| `docs/gas-city-reference.md` | "scratch windows" dropped from `gc session reset` warning | Stale after scratch removal |

Scratch removal was originally scoped as a follow-up (see "Out of
scope" below pre-amendment), but operator feedback during smoke-test
loading was that leaving the dead script/fragment in tree adds
confusion: threads now directly replace scratches, so the cleanup is
bundled into this bead.

## Design — what makes this clean

### 1. Generic role fragment via the `env` channel

`promptFuncMap` (`gascity/cmd/gc/prompt.go:263`) registers only three
template functions: `cmd`, `session`, `basename`. There is no string-
manipulation built-in — no `trimSuffix`, no `regexReplace`. So
parameterizing a fragment by the canonical role name needs a different
mechanism than template tricks alone.

`PromptContext.Env` (`gascity/cmd/gc/prompt.go:39`) is the relevant
escape hatch. `buildTemplateData` (`gascity/cmd/gc/prompt.go:215`)
merges agent.toml `[env]` keys into the template-data map *before*
SDK fields. So:

```toml
[env]
RoleName = "mechanik"
```

makes `{{ .RoleName }}` available in the agent's prompt template **and
in any fragment appended via `append_fragments`**, because fragments
execute against the same `td` map (`prompt.go:118`). The fragment
itself is a single file:

```
{{ define "thread-role" }}
You are a **{{ .RoleName }}-thread** ...
The canonical {{ .RoleName }} (`{{ .BindingName }}.{{ .RoleName }}`) ...
{{ end }}
```

Adding a third thread (e.g., `concierge-thread`) is one new agent.toml
with one new `RoleName` value — no new template-fragment file.

### 2. Scope correction

The mechanik-thread spike shipped `scope = "rig"`. Canonical mechanik
is `scope = "city"` (so its QualifiedName is `gc-toolkit.mechanik`, no
rig prefix). The thread should mirror that or it can't address the
canonical via `BindingName.RoleName` cleanly. Fixed: both threads now
`scope = "city"`.

Verified via test city render:

```
$ gc --city <test> prime --strict mayor-thread | grep "canonical mayor"
The canonical mayor (`gc-toolkit.mayor`) handles routed mail and routed work.
```

(Pre-fix this would have been `gc-toolkit/gc-toolkit.mayor` — wrong.)

### 3. `Ctrl-B + a` spawn-thread script

`tmux-spawn-thread.sh` mirrors the agent-detection pattern from
`tmux-spawn-scratch.sh:34-42` (focused-client session → `show-environment GC_AGENT`
→ fallback derive from session name). Then it diverges:

**Role mapping (idempotent):**

```
gc-toolkit.mayor             -> mayor-thread
gc-toolkit.mechanik          -> mechanik-thread
gc-toolkit.mechanik-thread   -> mechanik-thread       (already a thread, spawn sibling)
gc-toolkit.mechanik-thread-1 -> mechanik-thread       (pool instance, spawn sibling)
gc-toolkit/gc-toolkit.polecat-1 -> polecat-thread     (no template, soft-fail)
```

Implementation: strip everything up to and including the last `.`
(rig-prefix / binding stripped), then strip a trailing `-<digits>`
(pool suffix), then strip a trailing `-thread` (idempotence). Append
`-thread`. Single `sed` chain; unit-tested in-line during dev.

**Template existence probe:**

`gc prime --strict <template>` exits 1 with
`gc prime: agent "X" not found in city config` when the template
doesn't exist. The script uses this as the missing-template signal —
no need to parse `gc config show`.

**First-message capture:**

`tmux command-prompt -p` is the shipped primitive. Bindings install:

```sh
gcmux bind-key a command-prompt -p "thread msg (Enter; blank = no seed):" \
    "run-shell '$CONFIGDIR/assets/scripts/tmux-spawn-thread.sh $CONFIGDIR \"%%\"'"
```

The operator gets a single-line bottom-bar prompt; Enter submits and
substitutes the input into `%%`. Blank Enter is allowed and means
"spawn without seeding a first message." The script's `$2` is the
operator's input (may be empty), and the spawn-vs-spawn+nudge fork
keys on `[ -n "$THREAD_SPAWN_MESSAGE" ]`.

Two earlier approaches were tried and dropped:

1. `display-popup -E` running `IFS= read -r msg` inside the popup's
   shell. The popup's terminal line discipline didn't reliably
   deliver Enter to `read`, so the operator couldn't submit.

2. `display-popup -E` running `${EDITOR:-vi}` on a tempfile, then
   re-execing the script with `THREAD_SPAWN_MESSAGE_FILE` pointing at
   the tempfile (two-phase script keyed on that env var). Multi-line
   drafting was natural but the editor cold-start + popup overhead
   made the common case — short first prompt — feel like ceremony.
   Operator feedback after the queue-nudge fix landed (efbb1c8) was
   that the residual ~15s wait wasn't the nudge; it was `gc session
   new`. Backgrounding the spawn (see next subsection) plus a
   `command-prompt` instead of an editor popup brought the operator's
   pane back sub-second.

The cost of `command-prompt`: tmux's `%%` substitution is **textual
with no shell quoting**. If the operator's input contains an
unescaped `"` or `\`, the resulting `run-shell` argument re-parses
incorrectly and the spawn breaks. This is documented in the script
header and acknowledged as a known limitation. The script treats
`$2` as the raw message; the responsibility for safe characters
sits with the operator (or with a follow-up that switches the
input path to tmux `set-buffer` + `save-buffer` + `cat` of a
tempfile, which sidesteps the quoting hazard at the cost of more
moving parts).

A note on tmux `-1`: `command-prompt -1` means "accept one key
press" (i.e., the input is a single character), not "single-line."
`command-prompt` is always a single-row bottom-bar prompt; the
default behavior is the one we want — arbitrary text terminated by
Enter. So this binding intentionally omits `-1`.

**Async spawn:**

`gc session new` is the throughput bottleneck on the operator's
key-to-prompt-return loop: controller cold-start + worktree setup +
session bead create sums to ~15s. The script wraps the spawn + nudge
logic in a backgrounded subshell so the foreground returns immediately
after the template probe; the operator's pane unblocks sub-second.
Spawn outcomes (success, spawn failure, nudge failure) surface
asynchronously via `tmux display-message` at the status bar.

```sh
(
    SPAWN_OUT=$(gc session new "$THREAD_TEMPLATE" --no-attach 2>&1)
    SESSION_ID=$(printf '%s\n' "$SPAWN_OUT" \
        | sed -n 's/^Session \([^ ]*\) created.*/\1/p' | head -1)
    if [ -n "$THREAD_SPAWN_MESSAGE" ]; then
        gc session nudge --delivery=queue "$SESSION_ID" "$THREAD_SPAWN_MESSAGE"
    fi
    gcmux display-message "spawned ..."
) &
```

The template probe (`gc prime --strict`) stays inline because it's
fast (no provider start) and a missing-template should fail before
backgrounding anything — otherwise the operator gets no signal that
their key press did nothing useful.

`--delivery=queue` durably enqueues the nudge keyed on the canonical
session ID and returns immediately. The supervisor-side dispatcher
(`gascity/cmd/gc/nudge_dispatcher.go:115`) scans open session beads
each pass and delivers the queued message as soon as the new thread's
provider is observed running — `obs.Running` is the only state gate,
so a target still in `creating` at enqueue time is fine. Skipping
the nudge call entirely when `$THREAD_SPAWN_MESSAGE` is empty is the
blank-input path — the thread spawns and the operator gets a
no-seed status message.

Earlier iterations chained `gc session new` + a default-delivery
nudge inline in the script's foreground. `wait-idle` would have
blocked the operator's pane on claude cold-start (~20-30s); the
queue-mode nudge fixed that for the nudge portion (efbb1c8), but
`gc session new` itself still blocked for the controller bring-up.
Backgrounding the whole spawn + nudge block makes both bottlenecks
invisible to the operator's pane.

`--alias` is intentionally **not** passed: the runtime prefixes any
operator-supplied alias with the active binding namespace (e.g.
`thread-abc` → `<binding>.thread-abc`), and the un-prefixed value
would not resolve in the nudge call. We route on the canonical
session ID printed by `gc session new` to its stdout
(`gascity/cmd/gc/cmd_session.go:316`) instead.

**Scope handling:**

The script uses bare-name resolution end-to-end (`gc prime --strict
<role>-thread` to probe; `gc session new <role>-thread` to spawn).
`resolveSessionTemplate` (`gascity/cmd/gc/cmd_session.go:539`) falls
back to `Name` match when the input has no `/`, regardless of whether
the matched agent is city- or rig-scoped — so this works for both
scope flavors as long as the `<role>-thread` name is unique in the
city's agent set. The current targets (`mayor`, `mechanik`) are both
city-scoped, but a future rig-scoped thread would Just Work without
script changes.

## Acceptance & verification

- [x] `agents/mayor-thread/agent.toml` exists, `scope = "city"`
- [x] `agents/mechanik-thread/agent.toml` scope corrected to `"city"`
- [x] Single `template-fragments/thread-role.template.md` parameterized
      by `RoleName`; both threads append it; old fragment removed
- [x] `assets/scripts/tmux-spawn-thread.sh` exists and is executable;
      detects current agent via `GC_AGENT`, maps role idempotently,
      probes template existence, reads the first message from `$2`
      (supplied by tmux `command-prompt` substitution), backgrounds
      spawn + seed via queue nudge for instant operator-pane return,
      treats blank input as "spawn without seed," fails soft on
      missing template
- [x] `assets/scripts/tmux-bindings.sh:15` repointed at the new script
- [x] This design doc
- [ ] Live `Ctrl-B + a` test from mayor / mechanik / mechanik-thread
      panes — **deferred to operator** (polecat cannot spawn
      live-city sessions; mirrors the spike's §C operator checklist)
- [ ] `gc session list` post-spawn shows `gc-toolkit.mayor-thread`
      and `gc-toolkit.mechanik-thread` (no rig prefix) — same deferral

### Test-city verification (polecat-runnable)

A throwaway test city under `/tmp/` with a clean `[imports.gc-toolkit]`
in `pack.toml` was used to verify config resolution. Reproduce by:

```bash
CITY=$(mktemp -d)
mkdir "$CITY/rigs"
cp -r <worktree-path>/{agents,template-fragments,assets,pack.toml} "$CITY/rigs/test-gc/"
cat > "$CITY/pack.toml" <<'EOF'
[pack]
name = "test-city"
schema = 2
[imports]
[imports.gc-toolkit]
source = "rigs/test-gc"
EOF
cat > "$CITY/city.toml" <<'EOF'
[workspace]
provider = "claude"
[[rigs]]
name = "test-gc"
prefix = "tg"
[rigs.imports]
[rigs.imports.gc-toolkit]
source = "rigs/test-gc"
EOF
gc rig add "$CITY/rigs/test-gc" --name test-gc --prefix tg

gc --city "$CITY" config show \
    | grep -B1 -A4 'name = "mayor-thread"\|name = "mechanik-thread"'
gc --city "$CITY" prime --strict mayor-thread     | tail -50
gc --city "$CITY" prime --strict mechanik-thread  | tail -50
```

The render is expected to contain `(`gc-toolkit.mayor`)` /
`(`gc-toolkit.mechanik`)` — note the no-rig-prefix binding form,
which is the scope-correctness signal.

## Out of scope / follow-ups

- **Multi-line first messages.** `command-prompt` is single-row.
  Operators wanting multi-line input can paste with newlines
  escaped, or we revisit the popup-editor approach as a separate
  binding (e.g. `prefix + A` for "ask, long form").
- **Quote- and backslash-safe first messages.** Today's binding
  fails to spawn if the operator's message contains `"` or `\`
  (tmux `%%` substitution is unquoted). A `set-buffer %% \;
  save-buffer -b 0 /tmp/...` chain plus a tempfile read in the
  script would sidestep this; revisit if operators hit the
  limitation in practice.
- **Auto-switch into the new thread.** `Ctrl-B + S` picker is the
  current path; revisit if friction.
- **deacon-thread / witness-thread / refinery-thread.** Patrol /
  automation roles, not interactive — no operator-facing thread case.
- **polecat-thread.** Polecats are transient; threading isn't
  meaningful.
- **Rig-scoped thread templates.** Not needed yet; the bare-name
  resolution in the script (and `resolveSessionTemplate` upstream)
  picks up either scope so no script change is required when one
  is added. The only real follow-up is a new `<role>-thread`
  `agent.toml` for whatever rig-scoped role wants it.
