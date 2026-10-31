---
name: Gas City search for the demo capture sandbox
description: The search the arch check asks for on a demo capture's sandbox and on mol-rig-demo's app worktree. Read it when deciding whether either can move onto something Gas City ships, or when Gas City ships a way to contain one command.
---

# Gas City search for the demo capture sandbox

A demo capture runs one engine command inside a session that goes on working
with the city. This change keeps that one command, and everything it starts,
away from the live city, so a screenshot or a video shows the reviewed commit on
fixture data. That adds operational surface, so the arch check asks what Gas City
already ships for it
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships no way to contain one command. What it ships for containment holds
a whole session, and a session's store stays reachable by design, which is the
one thing a capture's command must not reach. So `demo_engine_cli` runs the
engine under macOS `sandbox-exec`, the tool Gas City's own release smoke test
uses on macOS, and the pack supplies the profile and the refusals around it.

The search moved one read onto Gas City. The cities to deny come from
`gc cities --json`, where the first draft parsed the registry file with `sed`.
The change adds no metadata key, bead kind or lifecycle state, so it carries no
warrant, and no warrant in [warrants.md](../../docs/warrants.md) names a path it
touches.

## The surface

1. **The sandbox.** `demo_engine_cli` in `assets/scripts/demo-engine-lib.sh` runs
   the engine under a generated profile. It denies the contents of the city's
   directories, every loopback port but the capture's own server's, every Unix
   socket but the system resolver's, and signals to any process outside the
   sandbox. It drops `GC_*`, `GT_*`, `BEADS_*`, `BD_*`, `DOLT_*`, `TMUX` and
   `TMUX_PANE`. It refuses a run before the engine starts when a directory the
   run names holds the city's or lies in it outside any rig worktree, when a
   city registry or a known city's rig map does not read, when a server already
   answers on the capture's port, when `--base-url` names this host, when the
   profile cannot quote a path or `--port` is no port, and on a host without
   `sandbox-exec`.
2. **The app's worktree.** The `rig-demo-app-root` block in
   `formulas/mol-rig-demo.toml` is a new caller of `review-workspace.sh add`,
   because the sandbox refuses a rig's own checkout, which holds its store.
3. **`--cwd`.** In `rig-demo-capture.sh`, a relative `--serve-dir` resolves
   against `--cwd`, and an empty `--cwd` is refused.
4. **The port.** `demo_engine_free_port` moves the port pick out of
   `demo-screenshot.sh` into the library, and a `--serve-dir` given no `--port`
   now takes a port from it, because the sandbox opens only a port it knows.
5. **The doctor item.** `doctor/check-demo-toolchain` reports `sandbox-exec`.

## Where the search looked

Read on 2026-10-31 at upstream `main`, with each pin taken from
`internal/config/public_packs.go` at the Gas City commit:

- `gastownhall/gascity` d1a150cac8f8: `docs/`, `engdocs/`, the bundled `core`
  pack at that commit and at its pin e38ce9cc55d1, and the Go source.
- `gastownhall/gascity-packs` 0b0d96250f66, every pack directory, and the bundled
  pins of `gastown` (cb6a612882b8) and `gascity` (5bf643ca55bd).
- `gastownhall/beads` 4a92834d575f.

The terms were `sandbox`, `sandbox-exec`, `seatbelt`, `bubblewrap`, `bwrap`,
`firejail`, `nsjail`, `landlock`, `seccomp`, `chroot`, `cgroup`, `systemd-run`,
`mount namespace`, `isolat`, `docker`, `podman`, `NetworkPolicy`, `firewall`,
`env -i`, `scrub`, `firecracker`, `e2b`, `daytona`, `playwright`, `screenshot` and
`ffmpeg`, then `one_shot` and the verbs of `gc session` and `gc runtime`, then the
callers of `gc worktree`, `git worktree add` and `bd worktree`, then each hit in
its context. Pages are cited by title and link, and source by package and symbol
at those commits.

## What Gas City ships near a contained command

The need has one shape. A reviewer's session takes a capture and then records its
verdict through `signoff.sh`, and `mol-rig-demo`'s session takes a capture and
then files a visit or closes its bead. Each stays on the store. Only the engine's
process tree is cut off from it.

- **A verb or a step key that contains a command: none.**
  [Command Execution Trust Boundaries](https://docs.gascity.com/reference/trust-boundaries)
  opens "Gas City intentionally runs operator-configured commands. Those commands
  are a feature, not a sandbox." No page of `docs/` names a containment key for a
  command or a step. Neither formula specification uses the word `sandbox`, and
  the v1 specification's "containment" is a step's parent-child edge.
- **Session runtimes are the nearest primitive, and they hold a whole session.**
  [Configuring an Agent](https://docs.gascity.com/guides/configuring-an-agent),
  Axis 5, says a runtime "is selected city-wide via the `[session]` block (or the
  `GC_SESSION` environment variable), not per-agent", and that `exec:<script>` is
  "how sandbox / micro-VM runtime packs plug in". An agent's `session` key selects
  "a **transport**, not a backend", `acp` or `tmux`
  ([herdr Session Provider](https://docs.gascity.com/reference/herdr-provider)).
  The hybrid provider's `remote_match` sends sessions whose names hold a pattern to
  Kubernetes and keeps the rest on tmux
  ([SessionConfig](https://docs.gascity.com/reference/config#sessionconfig)), so it
  can move one agent's sessions, each of them whole. The
  [Exec Session Provider](https://docs.gascity.com/reference/exec-session-provider)
  `exec` op runs a command in a session's box, the box the session lives in, and
  its `provision` op makes a box for the controller to launch an agent in. No `gc`
  verb offers either op to a step or a script, and `gc runtime check` and
  `gc runtime conformance` only test a runtime. Package runtimecapability's
  `probeLedger`, which `gc runtime conformance --env` runs on a runtime that
  declares `env.ledger`, says "`bd ready` inside the session must succeed", and it
  names "a sandbox->host tunnel for a remote runtime" as the way there. The engdoc
  `worker-runtime-transport-v0`, a proposal, keeps that split (`LedgerRuntime`).
  So a box that lets the session file its verdict lets a command in that box read
  the store. Moving captures onto a runtime would set the city's session provider
  for one command. In the packs repository `runtime-cloudflare` holds the only
  `[runtimes.*]` table, and the Gas City repository's `scripts/gc-session-docker`
  takes per-agent network and docker flags and mounts the city into the container
  read-write. Package guard's provider makes a `gc` process inside a worker site's
  box refuse every runtime operation, and worker-site mode keeps that `gc` from
  reading controller-local state (package main, `control_plane.go`). Both bind a
  `gc` that obeys them, and a command that names a path still reads it.
- **A one-shot agent is a session of its own, and its store stays in reach.** An
  agent's `start_command` with `lifecycle = "one_shot"`
  ([config reference](https://docs.gascity.com/reference/config#agent)) runs a
  command "expected to do bounded work and exit cleanly", so a capture could run
  apart from the session that files its verdict, and its box would hold only that
  command. On tmux it shares the host's files, loopback and sockets. Its
  environment names the store either way (package main, `resolveTemplate`).
  `remote_match` could send it to Kubernetes, where a pod gets the managed Dolt
  host (package runtime/k8s, `podManagedDoltHost`) and Gas City's tree holds no
  `NetworkPolicy`. It would also turn one command of a step into a dispatch the
  step has to wait on.
- **The agent slice governs resources.**
  [Tmux Agent Slice](https://docs.gascity.com/reference/tmux-agent-slice) wraps
  every pane of the tmux provider in a systemd user scope so that resource weights
  apply. It is a host-level setting for every pane, and it denies no path or port.
- **A provider's own sandbox is a flag on the whole provider session.** The
  [Agents tutorial](https://docs.gascity.com/tutorials/02-agents) says `suggest`
  "maps to `--ask-for-approval on-request --sandbox read-only`, Codex's Read Only
  preset", and its note names writing a file as what crosses that boundary. Package
  worker/builtin's `profiles.go` also gives Codex `network-off` and Antigravity a
  plain `--sandbox`. Each option is its provider's and covers everything that
  session runs, so the session that files a verdict runs under it too.
- **The gate environment keeps the store.** Package convergence's
  `ConditionEnv.Environ` gives a gate command "Only whitelisted variables", with
  HOME at the city "to sandbox gate scripts from the controller's home directory",
  and its list includes the "Dolt/Beads connection env". A formula's `check` step
  (package dispatch, `ralph.go`) and `gc converge test-gate` run one script under
  it, which makes it the nearest thing to a per-command setting. Package main's
  `gateSandboxReadCheck` exists to verify "that a bead read succeeds inside the
  gate sandbox". It sets a command's environment and working directory, and a
  capture needs the store unreadable.
- **The dashboard's runner is about its own reads.** Package dashboardbff's
  `execRunner`, whose comments call its subprocess sandboxed, bounds concurrency
  and output and runs its own commands shell-free under a clean environment.
- **Environment stripping works key by key.** The same trust page's Secret
  Propagation section strips keys that look secret-bearing, such as `TOKEN` and
  `API_KEY`, from orchestrator-side helpers. Package git's `SanitizedEnv` strips
  the variables that would point a git subprocess at a parent repository. Package
  beads/exec's `stripExecEnvKey` comes nearest: it drops `GC_CITY`, `GC_CITY_PATH`,
  `GC_RIG`, `BEADS_*`, `GC_DOLT_*` and others for an exec store's script. An order's
  `[order.env]` adds variables for an exec order's script and cannot override the
  keys the controller owns, `BEADS_DIR` among them (package orders,
  `IsReservedExecEnvKey`). A hosted-onboarding plan in `engdocs` describes a
  `scrubbedEnv` for `gc run` that scrubs `GC_*` and `BEADS_*`, and no Go at this
  commit holds it. None of them drops a variable for a command a pack runs, and a
  command that names the store's path still reads it. So the library drops those
  names itself, and the profile shuts the paths.
- **bd's flags leave reads open.** At bd 4a92834d575f, `--sandbox` is "Sandbox
  mode: disables Dolt auto-push" and `--readonly` is "Read-only mode: block write
  operations (for worker sandboxes)"
  ([CLI reference](https://beads.gascity.com/cli-reference)). Each is bd's own
  setting, from a flag, from config for `readonly`, or from bd's own detection for
  `sandbox`, and only bd obeys it. The capture method's old rule, run only a command
  that reads, had the same gap: a read is what put the live board on a public pull
  request.
- **The API read gate covers one surface of a whole city.** `read_auth_verify_key`
  ([APIConfig](https://docs.gascity.com/reference/config#apiconfig)) makes a typed
  per-city read carry a signed grant, and it "does NOT cover other surfaces on the
  same listener".
  [Operate a Direct Hardened City](https://docs.gascity.com/runbooks/remote-hardened-city)
  warns that a hardened city "exposes a **fully unauthenticated read plane**; the
  network front is not optional". The gate binds every client of that API, and it
  leaves the stores, files and sockets as they are. The sandbox shuts the port for
  the capture alone.
- **The export list filters a copy.** `gc runtime workdir-export` and
  `work_dir_exclude` ([CLI](https://docs.gascity.com/reference/cli#gc-runtime-workdir-export),
  [Exec Session Provider](https://docs.gascity.com/reference/exec-session-provider))
  name the orchestrator-local state a runtime must not copy
  (package citylayout, `WorkDirExportExcludes`, "a floor, not the complete set"),
  and "A script that runs the agent in place on the orchestrator's filesystem
  ignores it". A capture runs in place, so the list shuts nothing off.
- **Upstream's own analog is a repository script.** `scripts/smoke-macos.sh`, which
  CONTRIBUTING.md describes, runs `gc` "inside a `sandbox-exec` jail that denies
  network access and restricts filesystem writes to a temp directory". It is a
  release check, not a `gc` command or a pack, and it denies writes and the whole
  network where a capture needs reads and most of loopback denied. It shows the
  same operating-system tool in use for containment on macOS.
- **The packs repository has no such tool.** At 0b0d96250f66 and at both pins, none
  of `sandbox-exec`, `seatbelt`, `bubblewrap`, `bwrap`, `landlock`, `nsjail`,
  `firejail` or `chroot` appears. Where the word `sandbox` appears at 0b0d96250f66,
  it names a worktree, a provider's flag, a harness's refusal, an agent's separate
  data space or a product playground, and `slack-full`'s design prose uses it for
  the box an agent runs in. `playwright` and `screenshot` appear only in gstack, and
  `ffmpeg` nowhere. gstack's `qa` skill drives a `browse` binary the pack does not
  ship, which it looks for under `.claude/skills/gstack`, from the agent's shell, and
  it tries `http://localhost:3000` among the local ports for a running app. The
  nearest thing by purpose is test code: `oversight-rig`'s `test_order_scopes.py`
  filters `GC_*`, `BEADS_*` and `XDG_*` from a child because such a key "can point
  the CLI at a live city's store", and gastown's
  `test_review_check_scripts_gc_ready.sh` runs a script under `env -i` with a stub
  `gc`. Both set environment and PATH, so a command that names the store's path
  still reads it. At the pins of `gastown` and `gascity`, and in the bundled packs
  at Gas City's commit and its core pin, no capture tool appears. `sandbox` there
  names agents' worktrees in gastown's mayor prompt, verification inside a worktree
  in gascity's do-work `implement` asset, and a test's PATH directory in the bundled
  dolt pack's doctor test, and `isolat` names no limit on what a command reads.
- **Fixture sources redirect and shut nothing.** `GC_BEADS=file`
  ([FAQ](https://docs.gascity.com/getting-started/faq),
  [Troubleshooting](https://docs.gascity.com/getting-started/troubleshooting)), the
  `fake` session provider ([SessionConfig](https://docs.gascity.com/reference/config#sessionconfig))
  and `GC_HOME` choose a backend or a home for a process that obeys them, and
  `GC_ISOLATED=1` seeds that home a private supervisor config (package supervisor,
  `shouldSeedIsolatedSupervisorConfig`). A command that names the live store's path
  still reads it. They are candidate sources of fixture data for a capture's
  command, and this search did not run them inside the sandbox. The method's recipe
  stays a `gc` stub on PATH, which is prose in `docs/review-demo.md` and outside the
  lens.

## What the sandbox composes from Gas City

The profile is the pack's. Everything it names as the city's comes from Gas City:

- `gc cities --json` ([CLI](https://docs.gascity.com/reference/cli#gc-cities);
  package main, `doCities`, which reads package supervisor's `RegistryPath` under
  `GC_HOME` or `~/.gc`) lists the registered cities. The library asks it once for
  the home the environment names and once for the user's own, so a session with a
  private `GC_HOME` still denies the host's real city.
- `gc rig list --json`, through the pack's `rig-map.sh`, lists the rig checkouts of
  the one city it resolves. On a host with several cities, another city's rig whose
  checkout lies outside that city's directory stays readable.
- `GC_HOME`, `GC_CITY_PATH`, `GC_CITY`, `GC_RIG_ROOT`, `GC_BEADS_SCOPE_ROOT`,
  `BEADS_DIR` and `GC_CITY_RUNTIME_DIR` name the rest, as far as a session carries
  them. A city-scoped session's `GC_RIG_ROOT` and `BEADS_DIR` are empty, and the rig
  map names its rigs. None of them names a SQLite store bound at an absolute path
  outside the city
  ([StorageBindingConfig](https://docs.gascity.com/reference/config#storagebindingconfig)),
  so the sandbox leaves such a store readable.

The first draft parsed `cities.toml` with `sed`, which reads only a double-quoted
`path` line. A registry written with a TOML literal string read as no city, so
that city went undenied with no word said. `gc` parses the file as the supervisor
does. On the host, with `path = '<dir>'`, `gc cities --json` lists the city and
the `sed` read finds nothing. The `sed` read also took a `path` line from any other
table in the file, and `gc cities` lists only cities. Outside tests nothing at this
commit writes the registry's `[[rigs]]` table (package supervisor, `RegisterRig`,
`ReconcileRigs`), and a `[[pending_city_requests]]` entry only correlates a request
while the supervisor sets a city up. The swap also adds one refusal: a home whose
registry `gc` cannot read, or a host with a registry and no `gc`, now refuses every
capture, because the cities to deny are then unknown. The first draft carried on. A
home with no registry asks `gc` for nothing.

`assets/scripts/run-cancel.sh` and `assets/scripts/tmux-pick-session.sh` still
parse the registry themselves to learn a city's name. This change leaves them
alone, and tk-g897p1q carries them.

## The app's worktree

The block needs a directory the sandbox allows, holding what the rig commits at
its HEAD, with no branch of its own, removed after the demo whatever the app wrote
into it.

- **`gc worktree` requires a branch and a clean tree.** The
  [CLI reference](https://docs.gascity.com/reference/cli#gc-worktree) says it
  leaves "the bead's uniquely named branch checked out on an attached HEAD (never
  detached)", at a direct child of a per-rig root. `gc worktree cleanup` "refuses
  dirty worktrees" and has "no force mode", and package worktree's
  `CleanupErrorDirty` counts "staged, unstaged, or untracked work", as
  `git status --porcelain` reports it. A demo would add a branch to the rig's
  repository for a read, and a `serve_cmd` can write into this tree what the rig does
  not ignore. No core formula, and no pack at 0b0d96250f66 or at either pin, calls
  `gc worktree`.
- **`bd worktree create` makes a branch.** At bd 4a92834d575f it takes
  `<name> [--branch=<branch>]`, with the branch defaulting to the name.
- **The closed-bead reaper does not reach this tree.**
  `auto_reap_closed_bead_worktrees`
  ([DaemonConfig](https://docs.gascity.com/reference/config#daemonconfig)) defaults
  to false and takes "Only worktrees with a clean working tree". Package main's
  `reapClosedBeadWorktrees` acts only on worktrees under the rig's worktree root, and
  this tree lies in `$TMPDIR`.
- **Plain git is the native idiom.** Core's `mol-scoped-work` and
  `mol-polecat-commit` run `git worktree add "$WORKTREE_PATH" --detach`, gastown's
  `mol-refinery-patrol` runs `git worktree add --detach`, and pr-review's
  `review-pr` skill adds detached worktrees in its run directory for the base and
  the head it reads. `review-workspace.sh add` is the pack's wrapper of that call,
  keyed to a bead, and the hourly `review-workspace-reap` order removes it once the
  bead closes. Neither behaves differently here. The block is one call of a script
  the pack already has, so it adds no capability, and the path it hands the script
  comes from the `gc rig list --json` read the step already made.

## The rest of the surface

- **`--cwd`.** Gas City ships no capture, so it has no such option. The option is
  the engine's working directory, passed through, and resolving a relative
  `--serve-dir` against it needs one line of the script. The empty refusal sends a
  worktree that could not be made into the capture step's existing visit and
  cancel.
- **The port.** The [CLI reference](https://docs.gascity.com/reference/cli) offers
  no verb that prints a free port, and the hidden `gc dolt-state allocate-port` picks
  Dolt's. Upstream's primitive for this need is Go a pack cannot call: package
  loopbackport's `Reserve` hands out a port "for a server that a child process binds
  later", and its comment says "The usual listen-on-":0"-then-close reservation is a
  race on a shared host". `demo_engine_free_port` is that usual reservation, in one
  line of node, moved from `demo-screenshot.sh`. On macOS `Reserve` holds no lease
  either, because "Other platforms have no namespace-scoped name to lease". A
  `--serve-dir` that loses the race cannot bind, and the capture stops. A `--serve`
  that loses it would capture the other process's server, and the knock on the port
  just before the run narrows that window and does not close it.
- **The doctor item composes the primitive.**
  [Set Up a Multi-Agent Engineering Environment](https://docs.gascity.com/guides/multi-agent-engineering-environment#encode-known-mistakes-as-doctor-checks)
  makes a doctor check a directory under `doctor/` with a `run.sh`, and
  `doctor/check-demo-toolchain` is one (package doctor, `PackScriptCheck`). The
  nearest declarations are for other things: `[[pack.requires]]`
  ([Pack Spec](https://docs.gascity.com/reference/specs/pack-spec)) "declares an
  agent that must exist after loading", and the `pack-runtimes` doctor check tests
  that a pack-declared runtime is installed and answers the protocol handshake.

## What would change the answer

- Gas City ships a verb or a formula step key that runs one command contained from
  the city. `demo_engine_cli` then moves onto it, and the profile goes.
- Gas City ships a runtime or a transport that holds one command apart from its
  session, in a box the ledger does not reach. Today the `exec` op runs in the
  session's own box, `env.ledger` is a capability of a whole box, and `remote_match`
  moves whole sessions.
- Gas City lets one agent take a runtime of its own on this host, with the store out
  of reach. A capture could then be a one-shot session of its own.
- `gc worktree` takes a detached HEAD and can remove a tree holding whatever the app
  wrote, ignored by the rig or not. The `rig-demo-app-root` block, and
  `review-workspace.sh` with it, then have a native owner to compare against.
