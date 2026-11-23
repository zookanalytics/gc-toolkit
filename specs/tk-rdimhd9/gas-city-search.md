---
name: Gas City search for naming each of gc's writes in a rig's local excludes
description: Use when you judge which paths worktree-setup.sh hides from git in a rig's exclude file, such as a file gc starts writing into a home, a skill sink, or the block each run rewrites, or when you re-verify the agent home provisioning warrant's differences from Gas Town's copy in what it excludes.
---

# Gas City search for naming each of gc's writes in a rig's local excludes

Read on 2026-11-23 at `gastownhall/gascity` main dfd5200c3ee3,
`gastownhall/gascity-packs` main 44b9db7168f6 and `gastownhall/gastown` main
94cc82289d2e. The change it records narrows the block
`assets/scripts/worktree-setup.sh` keeps in each rig's `.git/info/exclude`. The
block named whole provider directories, and it now names each path gc and the
pack write.

## What the search looked for

- **A Gas City rule that hides what gc writes into a work dir or a rig
  checkout.** None. gc adds ignore lines only to a scope root's tracked
  `.gitignore`. `ensureGitignoreEntries` (`cmd/gc/gitignore.go`) appends
  `cityGitignoreEntries` at `gc init`, `rigGitignoreEntries` at `gc rig add` and
  on the API's rig path, and each MCP target's entry through
  `ensureMCPGitignoreBestEffort` (`cmd/gc/mcp_integration.go`). No Go file
  outside the test environment names `info/exclude`.
  [gastownhall/gascity#6736](https://github.com/gastownhall/gascity/issues/6736),
  open, proposes that gc keep a delimited block of its own in the exclude file,
  for its machine-local `.beads` files and `.gc/`. It names neither the skill
  links nor the provider files.
- **A record of what gc wrote into a work dir.** The skill materializer keeps an
  ownership manifest in each sink, naming each link it put there
  (`ownershipManifestFile`, `internal/materialize/skills.go`). The sinks are
  `vendorSinks` in the same file: `.claude/skills`, `.agents/skills` for codex
  and pi, `.gemini/skills`, `.opencode/skills` and `.mimocode/skills`. The
  script reads the manifest in every sink. `InstalledWorkDirPaths`
  (`internal/hooks/hooks.go`) lists the files the hook installer writes for a
  set of providers, but its only caller is the desired-state build
  (`cmd/gc/build_desired_state.go`), and no command prints it.
- **What gc writes under a provider's directory in a home.** For claude, the
  hook installer writes nothing into the work dir (`workDirOverlayProvider`,
  `internal/hooks/hooks.go`). A claude home's `.claude/` holds the pack's
  overlays, which overlay staging (`StageProviderOverlayDir`,
  `internal/runtime/staging.go`) writes into the work dir, merging
  `.claude/settings.json` (`mergeablePaths`, `internal/overlay/merge.go`), and
  the skill links. For codex, the installer writes the one file under the core
  pack's `overlay/per-provider/codex/`, which is `.codex/hooks.json`.
- **Gas Town's copy.** `install_local_excludes` in
  `gastown/assets/scripts/worktree-setup.sh`, last changed on 2026-10-03
  (f709abe5d0c6), appends `.claude/`, `.codex/`, `.agents/skills/`, `.gemini/`
  and `.opencode/` whole, and never removes a line. Gas Town's own rig setup
  ignores all of `.claude/` (`gasTownIgnorePatterns`, `internal/rig/overlay.go`
  in `gastownhall/gastown`), and its comment gives the reason: Cursor creates
  files under `.claude/` in a worktree at runtime. No agent in this city runs
  Cursor.

## What the city showed

A read-only census ran the changed script's list over every checkout of the
city's six rigs on 2026-11-23 at about 11:40Z. That is 772 checkouts: the
agents' homes, the rig checkouts and the per-bead trees. It compared what
`git ls-files --others` lists today with what it lists under the new block,
once every manifest has been read.

- No home's start fails under the new list. In no linked worktree does the
  sync's check find an untracked file it does not find today.
- One entry newly shows, in one rig checkout. It is an untracked `rigs/`
  directory holding a `.codex/hooks.json` that gc wrote a level down on
  2026-11-11, which the unanchored `.codex/` line hid. Nothing the pack runs
  reads a rig checkout's untracked files, except the report a stalled
  reconcile files.
- 1,143 entries are newly hidden. Each is a link gc made under `.claude/skills/`
  in a checkout of the one rig whose `.gitignore` re-includes that directory,
  where they show today. An exact name in the exclude file hides a file the
  re-include does not name itself.
- In this repository's own checkouts, every entry under `.claude/skills/` is a
  link its sink's manifest names, or the manifest. So the `.gitignore` line the
  change drops hides nothing a manifest misses.

## How the change differs from Gas Town's copy

Each row is a difference this change adds, in the form of the table in
[specs/tk-1tfzr71.10/gas-city-search.md](../tk-1tfzr71.10/gas-city-search.md#how-this-copy-differs-from-gas-towns).

| This script | Gas Town's | Why | Ends when |
|---|---|---|---|
| Names each file gc and the pack write under a provider's directory, and each skill link and manifest in every sink | Excludes `.claude/`, `.codex/`, `.agents/skills/`, `.gemini/` and `.opencode/` whole | A rig commits commands, skills, agents and prompts there, and a whole-directory line hides a new one from `git status` and `git add -A` | Gas City hides what it writes into a work dir, as gastownhall/gascity#6736 proposes for its other files |
| Rewrites its block on each run, between a start and an end marker, and keeps what a person writes outside it | Appends each line it lacks | A line the list drops must leave every rig's exclude file | Gas Town's script keeps the same block |
| Excludes `/worktrees/` at a home's root, and none of `.logs/`, `__pycache__/`, `state.json` or copilot's files | Excludes `worktrees/` at any depth, and those paths | The per-bead trees sit at a home's root, and nothing in this city writes the others into a home or a rig checkout | A writer of one of them appears |

## Not built

A line for a provider no agent in this city runs. A home of such a provider
holds files of its own, such as gemini's `.gemini/settings.json`, so its first
start fails and is reported, naming the directory, until `GC_WRITES` names
them.
