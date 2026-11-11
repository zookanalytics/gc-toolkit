---
name: Gas City search — a converse sitting's change and a copy of a rig's UI
description: The search behind the operational surface the design for tk-rymdhac adds, as AGENTS.md requires. It names, for each piece, the Gas City, Gas Town or bd primitive searched, cited at gastownhall/gascity 34485296 and gastownhall/gascity-packs 7f86098c, and says which the design composes and why none covers the rest. Read it to judge the design's divergence from Gas City, or before building unit 1 or unit 4.
---

# Gas City search for tk-rymdhac

Gas City is cited at `gastownhall/gascity` 34485296 (2026-11-10), by page under
`docs/` or by symbol. Gas Town is cited at `gastownhall/gascity-packs` 7f86098c
(2026-11-10), by path and line. The design is [design.md](design.md).

The surface the design adds:

- `--held-by <conversation>` on `work-setup.sh` and `work-submit.sh` (unit 1), a
  mode on two existing scripts.
- Under call 1(a), the pack's script that starts, publishes and stops a copy of
  a rig's UI, and the city's two environment values it calls (unit 4).

The design adds no metadata key, bead kind, lifecycle state, order or formula
step. The skill and the prompt text are not surface.

## The model: who may change a repository

- **Gas Town's crew changes the repository.** A crew worker is the overseer's
  persistent, user-managed workspace with no witness watching it
  (`gastown/assets/prompts/crew.template.md:19-30`). It pushes straight to
  `main`, with no feature branch and no PR, while a polecat runs the done
  sequence and the refinery merges (`crew.template.md:145`, `:150-152`). Its one
  branch is cross-rig work in a `git worktree`, which it submits to that rig's
  refinery as soon as it is done (`crew.template.md:187-194`, `:193`).
- **Gas Town's mayor fixes directly when that is fastest.** "You CAN and SHOULD
  edit code when it's the fastest path", for "a quick fix (< 5 minutes, won't
  eat context)", and never in place of work it tried to route and could not
  (`gastown/agents/mayor/prompt.template.md:16`, `:44`, `:55-56`).
- **Gas City leaves the distinction to the pack.** "Crew and polecats are
  operating modes, not types ... a pack can adopt, relax, or replace it"
  (`docs/getting-started/coming-from-gastown.md:119`).

The design takes the crew's own exception as its shape for every change a
sitting makes: a branch in a worktree, submitted to the refinery. The one
difference from Gas Town's crew is the one the initiative named: the change
lands through the refinery and review, not by a push to `main`, because this
city's `main` takes changes only through a PR, and the operator ruled that the
pipeline's checks are the checks. The mayor's limit, never in place of failed
routing, is the line's own (design, section 1).

## The change's tree

**Searched.**

- **A session's own worktree.** An agent's `work_dir` is its sessions' working
  directory, and Gas City says to give a role a separate one when "the role
  mutates a repo and needs an isolated worktree"
  (`docs/getting-started/coming-from-gastown.md:125-131`; `work_dir` in
  `docs/reference/config.md`, Agent). Each converse template already has one, a
  home per conversation. The pack syncs that home to the default branch at
  each start, so it is the session's, not a change's.
- **`gc worktree`.** It ensures, verifies and cleans up a worktree bound to one
  work bead, with its provenance in the tree's private git dir
  (`docs/reference/cli.md`, `gc worktree`). `Spec.validate` refuses a path
  inside a registered worktree (`rejectRegisteredWorktreeAncestor` in
  `internal/worktree/worktree.go`, called at line 234), so it cannot make a
  tree inside a sitting's home, where the pack keeps every per-bead tree.
  `Cleanup` refuses a tree whose HEAD is not merged into its base
  (`internal/worktree/worktree.go`, lines 490-496), so it cannot release a tree
  at the hand-off, before the merge, which is when Work's hand-off removes it.
- **A session started in a managed worktree.** A pool session does not claim
  routed work whose managed worktree is not its own, and the controller starts
  a session inside that worktree instead (`docs/reference/cli.md`, `gc hook`,
  lines 2213-2224). That serves routed pool work. A sitting is a manual session
  the operator engages on a conversation, and its change is held off every
  pool's offer, so there is nothing for that path to route.
- **The reapers.** `auto_reap_closed_bead_worktrees` removes a per-bead
  worktree once its bead closes, when the tree is clean and removing it orphans
  no commit (`docs/reference/config.md`, line 377). It lists a rig's trees from
  the rig's own repository, acts only on those under `.gc/worktrees/<rig>/` at
  any depth, and names a tree's bead by its directory
  (`reapClosedBeadWorktrees` in `cmd/gc/bead_worktree_reaper.go`), so it finds
  a tree under a sitting's home as it finds one under a polecat's.
  `auto_prune_worker_dir` removes a pool session's worker dir once its session
  closes (`docs/reference/config.md`, line 382), and a sitting is not a pool
  session.

**Composed.** The reaper is the removal for a tree whose sitting ended before
its hand-off, as it is for a polecat's. The tree itself is Work's, cut by
`work-setup.sh` where it cuts a polecat's, for the reasons the pack's warrant
"The work formula's overrides" records (`docs/warrants.md`).

## The hold

**Composed, no surface.** bd's `blocks` edge holds the change while the
conversation is open: bd counts a bead blocked while a bead it depends on
through `blocks` is open, which keeps it out of `bd ready` and every pool's
offer. The pack already holds an open PR's merge with the same edge onto a
conversation.

## The hand-off for a caller with no run

**Searched.**

- **Gas Town's refinery intake.** "Work beads flow directly: pool → polecat →
  refinery → closed. No separate MR beads. The polecat sets metadata (branch,
  target) on the work bead and assigns it to the refinery"
  (`gastown/formulas/mol-refinery-patrol.toml:30-32`). The hand-off is a
  contract on the bead, with no writer of its own to call.
- **Gas City's core formulas.** `mol-polecat-base` leaves the terminal step to
  each variant ("then add a terminal step (submit, commit, etc)",
  `internal/bootstrap/packs/core/formulas/mol-polecat-base.toml:8`), and each
  variant's step runs inside its run. No core formula or command hands a branch
  to a refinery for a session that holds no run.
- **The crew's submission.** Gas Town's crew submits cross-rig work to a rig's
  refinery (`crew.template.md:193`), and a submission is the done sequence that
  creates the refinery's work (`crew.template.md:152`, `:169`). The crew prompt
  names that sequence and gives no command of its own for it.

**Why the mode.** The pack's Work writer, `work-submit.sh`, is the one
implementation of that contract, and the refinery the pack runs reads exactly
what it writes. It ends a run on every exit, which a sitting cannot take,
because the sitting must outlive its hand-off and the operator is in it to hear
a refusal. `--held-by` keeps one writer for both callers and takes the
sitting's claim from bd's own edge and `gc hook current`, rather than a key of
the pack's.

## A copy of a rig's UI

**Searched.**

- **Workspace services.** A `[[service]]` of kind `proxy_process` runs a
  controller-supervised process that the supervisor reverse-proxies under
  `/svc/{name}` (`docs/reference/config.md`, Service and ServiceProcessConfig,
  lines 840-862). A service is declared in the city's config, one process per
  name, and a page it serves shares the supervisor's origin. The board's client
  reads the supervisor's API relative to its page's origin, under a
  `connect-src 'self'` policy (`services/helm/web/src/drill/origin.ts` in this
  repository), so a copy served there would read the live city. A copy needs an
  origin of its own.
- **Publication.** A service's `publication` declares its visibility and a
  hostname label, and "the platform decides whether and how that intent
  becomes a public route" (`docs/reference/config.md`, Service's
  `publication` at line 850, and ServicePublicationConfig at line 863). It
  applies to declared services, not to a process a sitting starts.
- **Session runtimes and images.** Gas City runs sessions in pods, over SSH or
  in an exec sandbox, a runtime "selected city-wide via the `[session]` block"
  (`docs/guides/configuring-an-agent.md`, "Axis 5 — Runtime", lines 285-299),
  and `gc build-image` builds an agent's container image
  (`docs/reference/cli.md`). Each isolates a session, not an app instance a
  session runs.
- **An agent's environment.** An agent's `env` sets environment variables for
  its process, and a city patches it per agent (`docs/reference/config.md`,
  Agent at line 109 and AgentPatch).

**Composed.** The agent's `env` carries the city's publish and withdraw
commands to the converse templates. The pack's demo tools pick a copy's free
port (`demo-screenshot.sh --port 0`) and capture screenshots in a sandbox where
the live city cannot be reached.

**Why the script.** No primitive starts one app instance from a worktree on a
free port, publishes it on an origin of its own and stops it with the session
that started it, so unit 4's script does that, and nothing more. The
publication itself is the city's command, because how an operator reaches a
host is the city's, here a `tailscale serve` HTTPS port.
