---
name: Gas City search — the ports and sockets of an app that runs as several local processes
description: The search behind the operational surface tk-f9yepdn adds, as AGENTS.md requires, cited at gastownhall/gascity 1bcfacdca3. Read it to judge the change's divergence from Gas City, or before widening what a copy of a rig's app or a capture of it reaches.
---

# Gas City search for tk-f9yepdn

Gas City is cited at `gastownhall/gascity` 1bcfacdca3 (upstream main,
2026-11-18), by page under `docs/` or by symbol. The capture engine is cited at
`zookanalytics/sprintshow` main 34e169e.

The surface the change adds:

- The formula var `ui_serve_extra_ports`, which `mol-rig-demo` declares with the
  default `"0"`: how many loopback ports beyond `$PORT` a rig's app listens on.
- `gctk rig serve` reads that var for the rig whose clone holds the checkout. A
  start hands the command that many more free loopback ports as `$PORT_1` and
  on, and a TMPDIR of the copy's own. It counts the copy up only once its own
  processes listen on each port. Its report gains the key `extra_ports`, and a
  number that is not one from 0 to 16 fails the start with the new reason
  `bad-extra-ports`.
- `demo-engine-lib.sh`: `demo_engine_sandboxed` takes its ports as one port or
  several joined by commas, and reads `DEMO_ENGINE_SOCKET_DIR`, the one directory
  under which the command may connect to a Unix socket. A capture of a copy opens
  the `extra_ports` the copy's check names.

The change adds no metadata key, bead kind, lifecycle state, order or formula
step.

## A rig's setting for its app

**Searched.** Where Gas City lets a city give one rig a value that a pack's
code reads.

**Composed.** Rig-scoped formula vars. A rig's `formula_vars` "provides
rig-scoped defaults for formula vars. Keys match var names declared in formula
`[vars.<name>]` blocks" (`docs/reference/config.md`, Rig). `gc formula show
--rig` shows them "alongside each applicable var" (`docs/reference/cli.md`, "gc
formula show"). The count sits beside `ui_serve_command`, which the pack already
declares there, and `gctk rig serve` reads it through `gc formula show
mol-rig-demo --rig <rig> --json`, as `demo-engine-lib.sh` reads
`app_reads_city`.

## Loopback ports for an app a session starts

**Searched.**

- **A port Gas City picks for a caller.** Gas City picks none. Its own Dolt
  server's port is "hashed from city path" when unset (`docs/reference/config.md`,
  the Dolt `port`), so it is fixed per city.
- **A supervised service.** A `proxy_process` service is "a controller-supervised
  local process that is reverse-proxied under /svc/{name}", one process per
  name, whose `health_path` "is probed on the local listener"
  (`docs/reference/config.md`, ServiceProcessConfig). A copy runs from a
  worktree, one per checkout, and its app here has several listeners. The search
  for the copy itself found the same ([its search](../tk-rymdhac/gas-city-search.md#a-copy-of-a-rigs-ui)).
- **The engine.** The engine gives a page app one port: "`--serve` waits on port
  5173 unless `--port` names the port its command binds". Several ports, as
  `--port a,b,c`, are only for an iOS app run's own servers (the engine's README,
  "Run a demo" and "iOS app demos").

**Built.** gctk picks the ports, as it picks the copy's own, and the sandbox
opens only those, which keeps the rule the operator accepted for an iOS capture:
the sandbox opens only loopback ports the pack chooses before the run.

## A sandbox around one command

**Searched.** "Gas City intentionally runs operator-configured commands. Those
commands are a feature, not a sandbox" (`docs/reference/trust-boundaries.md`,
"Command Execution Trust Boundaries"). Its only use of `sandbox-exec` is still
the macOS smoke test of a release (`scripts/smoke-macos.sh`, and "inside a
`sandbox-exec` jail" in `CONTRIBUTING.md`).

**Composed.** macOS `sandbox-exec`, as the capture's sandbox already does
([its search](../tk-r9wui2m/gas-city-search.md)). Its profile language takes a
Unix socket filter by path: `(allow network-outbound (remote unix-socket
(subpath "<dir>")))` let a socket under the directory connect, and kept one
outside it refused. This was measured through the real `sandbox-exec` on the
city's host, in the order the profile writes its rules, on eight sets of free
ports, and `demo-engine-lib.test.sh` keeps that run.

## A temporary directory of a process's own

**Searched.** Gas City makes one for its own bd walks: `bdWalkScratchDir`
"creates the walk's HOME, cwd and TMPDIR" so "bd never sees the caller's TMPDIR"
(`cmd/gc/bd_inventory_trust.go`). That is gc's own code for its own child, not a
call a pack can make for a command it starts.

**Built.** The copy's leader makes the directory with Go's `os.MkdirTemp`,
hands it to the command as `TMPDIR` and to the sandbox as the socket directory,
and removes it once the copy's group has ended.

## Where the growth lives

The count's read, the port pick, the readiness rule, the report key and the
temporary directory are in gctk, in Go. The port list and the socket directory
grow `demo-engine-lib.sh`, because they are allow rules in the capture
sandbox's profile and arguments of the engine's CLI, which that file composes,
and gctk's copies run inside the same profile through it (the host adapter in
`docs/gctk-architecture.md`). That is code that configures other tools,
`sandbox-exec` and the engine, which AGENTS.md names as logic gctk is
inappropriate for.
