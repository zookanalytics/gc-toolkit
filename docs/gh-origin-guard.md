---
name: gh origin guard
description: The PreToolUse hook that refuses agent-typed gh writes aimed outside a repository we own — which verbs it covers, how it resolves the target, what it deliberately does not cover. Read it before changing the guard or adding an agent.
---

# gh origin guard

One bot account backs every agent's `gh` token, so any agent can write to any
repository that token reaches. Filing an issue, opening a PR, or leaving a
comment on someone else's repository spends a stranger's attention. That
decision belongs to the operator, and the guard is where the boundary is
enforced rather than requested.

The implementation is a Claude Code `PreToolUse` hook at
`assets/scripts/gh-origin-guard.sh`, registered for every claude-provider agent
by the overlays in `pack.toml`.

## What it refuses

Five write verbs: `gh issue create`, `gh issue comment`, `gh pr create`,
`gh pr comment`, and `gh pr review`. Each is refused when the repository it
targets is not one the session owns.

Reads are untouched. `gh issue view`, `gh pr view`, `gh pr diff`, `gh search`
and the rest reach any repository normally, so research on an upstream project
keeps working.

A refusal names the repository it stopped, names the repositories the session
may write to, and points at the prepare-a-command path so the agent learns the
route instead of only meeting a wall.

## The boundary is an origin, not an organization

The allowed repository is resolved from a rig's own `origin` remote. This is
the same shape `assets/scripts/pr-open.sh` already proves, where every read and
the create are pinned to `ORIGIN_REPO_Q` derived from `git remote get-url
origin`.

An organization-keyed rule would be wrong in both directions. The
`shutupandlisten` rig's origin is `suandl/shutupandlisten`, outside the
operator's org, so an org allowlist would refuse that rig's entire PR flow.
Meanwhile an unrelated repository inside the org is still not a repository that
rig should write to.

## How a target is resolved

The guard resolves the target the way `gh` itself does, in the same order:

1. An explicit `--repo` or `-R` on the command.
2. `GH_REPO`, whether inline on the command or ambient in the environment.
3. The `origin` remote of the working directory.

Step 3 is the one that matters most. `gh` with no `--repo` writes to whatever
repository the working directory belongs to, so an agent standing in a clone of
someone else's project sends there with no flag to inspect. A guard that read
only the explicit flag would wave that through.

The working directory is not always the one the hook is told about. A `cd`
earlier on the same command line moves where `gh` resolves, so the guard follows
it: `cd ../their-clone && gh issue create` is measured against `their-clone`,
not against the directory the session was sitting in. A destination the guard
cannot expand, such as `cd "$SOMEWHERE"`, resolves to no repository and is
refused.

Host, owner, and name are all compared, lowercased. The host is part of the
identity, because dropping it would let the same owner and name on a different
forge read as a repository we own.

## What the session owns

`GC_RIG_ROOT` is authoritative and narrow. A rig agent is measured against its
own rig even while standing in a checkout of something else, and another rig in
the same city is still someone else's repository for it.

City-scope agents such as the deacon and mechanik carry no rig root and
legitimately work across rigs, so for them the owned set is the origin of every
rig under `$GC_CITY_PATH/rigs`. The working directory is the last resort, used
only when neither a rig root nor a city resolves.

Resolving to the working directory earlier would make the guard vacuous exactly
where it is needed, since a checkout of someone else's repository would then
authorize its own writes.

## Failing closed

A write verb whose target cannot be established is refused. If no repository we
own can be resolved, or the target resolves to nothing, there is no way to show
the write lands somewhere we own, and "outside" is the safe reading.

The cost of that choice is small. Every `gh` write in this repo lives inside a
script, and those scripts run in a rig checkout where the origin resolves.

## What it does not cover

The hook inspects the command an agent types into Bash. These are outside it:

- **`gh` inside a script.** Running `assets/scripts/pr-open.sh` shows the hook
  that command, not the `gh` calls the script makes. Those scripts already pin
  `--repo` to an origin they resolve themselves.
- **`gh api`.** The REST endpoints reach the same writes. The ruling names the
  five porcelain verbs and the guard implements exactly those.
- **Codex agents.** `dog` and `polecat-codex` never read
  `.claude/settings.json`, so no `.claude` hook reaches them.
- **A missing `jq`.** The hook parses its payload with `jq` and stays silent
  without it.
- **A determined bypass.** `bash -c`, a wrapper script, or a here-doc all reach
  `gh` without matching. This guards reach by accident, and it is not a sandbox.

## Wiring

An agent takes exactly one `overlay_dir`. Agents that already ship a hook get
the guard registered inside their own overlay's `settings.json`, and the rest
take `overlays/gh-origin-guard`:

| Overlay | Agents |
|---|---|
| `overlays/work-context` | polecat |
| `overlays/cycle-recycle` | refinery, witness, deacon |
| `overlays/gh-origin-guard` | converse, mechanik, proactive |

Every registration runs the same command, which resolves the script from
`$GC_RIG_ROOT` and then from `$GC_CITY_PATH/rigs/gc-toolkit`. Both are set by
gc. The working directory is deliberately not consulted: the guard is a
security control, and resolving it out of whatever repository an agent happens
to stand in would let that repository supply the code deciding whether its own
writes are allowed.

## Tests

`assets/scripts/gh-origin-guard.test.sh` runs the shipped script against local
repositories with fabricated remotes. It asserts both directions, because a
guard that refuses everything and a guard that refuses nothing are equally
broken and equally quiet.

`assets/scripts/gh-origin-guard-wiring.test.sh` enumerates `agents/` and fails
when a claude-provider agent is left uncovered. An unwired agent is invisible at
runtime, since it looks exactly like one whose writes were all legitimate.
