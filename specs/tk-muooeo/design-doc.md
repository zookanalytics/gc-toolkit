---
name: Rig-scoped coordination agents run in a rig worktree
description: Design record for tk-muooeo. Coordination agents (converse, its per-model variants, witness) resolved gh/git to the city repo because their work_dir was a plain directory under the city .gc tree. The chosen fix is a per-session rig worktree via a worktree-setup.sh pre_start hook — the shape the polecat/proactive/refinery pools already use — rather than a per-agent GH_REPO/GIT_DIR override. Records why the worktree shape wins, why the fix is pack-side (no gascity binary change), which agents change and which are exempt, and the collision/cleanup/disk analysis the operator asked for.
---

# Rig-scoped coordination agents run in a rig worktree

A rig-scoped coordination agent shells `gh`/`git` to inspect the rig it serves.
Those tools resolve the repo from the working directory. When the working
directory is a plain directory under the city `.gc` tree
(`<city>/.gc/agents/<name>/<session>`), it resolves up to the city repo's
`.git`, so the agent answers against the city repo, not its rig: `gh pr view`
reports a rig PR as nonexistent, `git ls-remote` misses a rig branch. The fix
makes the working directory a git worktree of the rig repo, so cwd resolution
lands on the rig with no per-command discipline.

## The mechanism (verified in gascity)

The working directory is not hardcoded in the `gc` binary. It is the agent's
`work_dir` template string, expanded and joined to the city root
(`internal/workdir/workdir.go` `ResolveWorkDirPathStrict`), then carried as the
session's cwd (`tmux new-session -c <workDir>`). The only thing that makes a
directory a *rig* worktree rather than a plain `MkdirAll`ed directory is a
`pre_start` hook that runs `assets/scripts/worktree-setup.sh`, which does
`git worktree add` from the rig root. The polecat, proactive, and refinery pools
already carry exactly this pair; the coordination agents were left on plain
`.gc/agents/` paths.

So the whole city-vs-rig outcome is decided by pack config: the `work_dir`
template and the presence of the worktree-setup `pre_start`. Both live in this
pack. gascity already expands `{{.Rig}}` / `{{.AgentBase}}` / `{{.ConfigDir}}` /
`{{.RigRoot}}` / `{{.WorkDir}}` and runs `pre_start` for these same agents.
**No gascity binary change is needed.**

## The two shapes, and why the worktree wins

The operator named two shapes to weigh: a per-agent rig worktree (as polecats
get) or a per-agent repo override (`GH_REPO` for gh, an explicit git dir/remote
for git).

**Chosen: per-agent rig worktree.**

- It is the proven pattern. polecat, proactive, and refinery — the rig-scoped
  worker pools — already resolve correctly this way, through the same
  `worktree-setup.sh`. The upstream gastown example pack applies it to its
  non-polecat agents (crew, witness, refinery, convoymaster) too; this pack
  simply diverged for these roles.
- It fixes every cwd-resolving tool at once — `gh`, `git`, and anything else
  that reads the repo from the working directory — with zero per-command
  discipline. `branch-context.sh` already treats a `.gc/worktrees/<rig>/` path
  as the owning-rig signal, so the move also makes rig attribution correct.

**Rejected: per-agent repo override.**

- It is hostile to the existing design. There is no `GH_REPO` / `GIT_DIR` /
  `GIT_WORK_TREE` injection anywhere in gascity's session-spawn path; the only
  appearance of those git-locating variables is a blacklist that *strips* them
  (`internal/git/git.go`) so subprocess git uses the intended workdir rather
  than a parent repo. An override shape would need new binary code to inject
  them and would fight the code that removes them.
- `GH_REPO` only covers `gh`. Raw `git` needs `GIT_DIR`/`GIT_WORK_TREE`
  decoupled from cwd, which is error-prone — a subshell or a tool that recomputes
  from cwd still resolves to the city repo.

## Scope: what changes, what does not

Changed to a rig worktree (`.gc/worktrees/{{.Rig}}/<role>/...` + worktree-setup
`pre_start`):

- `converse` and its per-model variants `converse-opus`, `converse-fable`,
  `converse-codex`. These share the converse prompt, which shells bare
  `gh pr view` / `gh api repos/{owner}/{repo}/...` — the reported bug surface.
- `witness`. Its patrol already targets the rig via `git -C "$GC_RIG_ROOT"`, so
  it was not demonstrably broken; the worktree brings its cwd (and the
  `git rev-parse --show-toplevel` fallback its script-lookup uses) onto the rig
  too, and makes the rig-scoped roster uniform. Kept a per-rig singleton (no
  `{{.AgentBase}}`) to preserve its one-tree-per-rig shape.

Left as they are:

- `mechanik`, `deacon`, `dog` are city-scoped: they span rigs and have no single
  `{{.Rig}}` a worktree could resolve to. mechanik already passes the repo
  explicitly (`git -C <rig-root>`); the explicit-repo discipline is the correct
  answer for a city-scoped agent, not a worktree.
- `keeper` (gascity-keeper pack) is rig-scoped but never resolves from cwd — it
  targets the upstream repo explicitly (`gh --repo gastownhall/gascity`,
  `git -C "$RIG_PATH"`), so a rig worktree would be the wrong repo. It carries a
  `# worktree-exempt:` marker naming why.

## Collision, cleanup, disk

- **Collision.** `worktree-setup.sh` names the worktree branch by a hash of the
  worktree path (`gc-<agent>-<hash>`), and the path is per-slot (`{{.AgentBase}}`,
  or the singleton path for witness). No two agents or slots share a branch, and
  none is the rig's main checkout (`rigs/<rig>`) or its refinery home.
- **Disk.** One working tree per *slot*, not per session — `{{.AgentBase}}` is
  the slot identity, bounded by `max_active_sessions` (and by however many slots
  have been allocated over time, as already holds for the polecat/proactive
  pools). Linked worktrees share the object store, so each costs a working tree,
  not a clone. This is the disk model these pools already pay.
- **Cleanup.** `worktree-reap.sh` protects agent-home worktrees by matching the
  roster's `work_dir` template shapes, and it only reaps directories a bead names
  in `metadata.work_dir` — which an agent home never is. So these homes are not
  reaped while their agent is on the roster, exactly as the pool homes are not.

## Regression backstop

`assets/scripts/agent-worktree-wiring.test.sh` holds the invariant across every
agent TOML: a `.gc/worktrees/` work_dir must have a worktree-setup `pre_start`
(and vice versa), and a `scope="rig"` agent must be a rig worktree unless it
declares a `# worktree-exempt:` marker. A rig-scoped agent silently added or
reverted onto a city-tree path fails the test.

## Takes effect on restart

This is agent configuration; a live coordination session keeps its current cwd
until it is restarted. The documented interim mitigation (pass the repo
explicitly) covers the window until each agent recycles onto the new work_dir.
