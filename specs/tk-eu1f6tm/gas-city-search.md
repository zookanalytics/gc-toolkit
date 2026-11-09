---
name: Gas City search for gc's writes into a home worktree-setup.sh is adding
description: Use when you judge how worktree-setup.sh adds a home that gc writes into during the setup, such as when it fetches, its retry of the add and the pause before it, or its signal traps, or when you re-verify the agent home provisioning warrant's differences from Gas Town's copy.
---

# Gas City search for gc's writes into a home worktree-setup.sh is adding

Read on 2026-11-08 at `gastownhall/gascity` main 27a4857eabd5 and
`gastownhall/gascity-packs` main 2a3b142e3fbd. The change it records makes
`assets/scripts/worktree-setup.sh` survive gc re-creating a home that is not yet
a worktree while the script adds it.

## What the search looked for

- **A Gas City owner for an agent's home.** None. `gc worktree ensure`
  provisions a tree for a bead, not for an agent, as the agent home provisioning
  warrant in [docs/warrants.md](../../docs/warrants.md#agent-home-provisioning)
  records.
- **A way to hold gc's writes into a work dir while that session's `pre_start`
  runs.** None. A real desired-state build stages overlays, installs hooks,
  creates the work dir, projects Claude settings and writes skill snapshots in
  each agent's work dir (the comment on `buildDesiredStatePreview` in
  `cmd/gc/build_desired_state.go`). `writeSkillSnapshotFile`
  (`cmd/gc/skill_integration.go`, called from `cmd/gc/template_resolve.go`)
  creates `<workDir>/.gc/tmp` with `os.MkdirAll` and writes the snapshot again
  on each call, because the catalog can drift between ticks. So a build
  re-creates a home the script has emptied.
- **How gc stops a `pre_start`.** `runSetupCommand`
  (`internal/runtime/tmux/adapter.go`) runs each command as `sh -c` under
  `execgrace.Apply`. At the deadline it sends SIGTERM to the command's process
  group, and it kills the group when a grace runs out. The grace is
  `setupCommandWaitDelay`, 2 s, or `setupCancelGrace`, 10 s, when
  `[session] setup_max_timeout` is set. Its comment names this script's restore
  of what it staged as what the grace is for.
- **Gas Town's copy.** `gastown/assets/scripts/worktree-setup.sh`, last changed
  on 2026-10-03 (f709abe5d0c6), empties the home, then prunes, fetches and adds.
  It fails the start when the add fails, so it has the same window. The upstream
  finding for it is tk-d6fto8s.

## What the failed homes showed

The failed starts of 2026-11-07 left two homes, for tk-kz6jl3a and tk-a9fckm0,
whose files keep sub-second mtimes. In the first, the start's
`.gc/settings.json` is at 00:45:19.499 MST, and the rewrite's
`.claude/settings.json` and skill snapshot are at 19.954 and 20.196. In the
second, the start's files are at 00:45:46.542, and the rewrite's
`.codex/hooks.json` and snapshot are at 46.984 and 47.041. So the rewrite began
about 0.45 s after the start's own writes and took 60 to 240 ms. The one-second
pause before another add outlasts it.

## How the change differs from Gas Town's copy

Each row is a difference this change adds, in the form of the table in
[specs/tk-1tfzr71.10/gas-city-search.md](../tk-1tfzr71.10/gas-city-search.md#how-this-copy-differs-from-gas-towns).

| This script | Gas Town's | Why | Ends when |
|---|---|---|---|
| Prunes, names the branch, reads the default ref and fetches before it empties the home | Empties the home first | Nothing between the emptying and the add then waits on the network, so a build is less likely to land there | Gas City holds its writes into a work dir while that session's `pre_start` runs, or Gas Town's script takes the same order |
| A failed add that finds the home back with no `.git` stages what the home holds as another set and adds again after a one-second pause, up to three adds, then merges every set back newest first | Restores the home and fails the start | A build can still land between the emptying and the add | The same, or Gas Town's script takes the same retry |
| HUP, INT and TERM restore what was staged and end the run | Restore it and carry on | gc kills a `pre_start` 2 s after it stops it, so that time goes to the restore and not to another add | Gas Town's script takes the same traps |

## Not built

Any change to Gas City's writes into a work dir, which are Gas City's behaviour.
