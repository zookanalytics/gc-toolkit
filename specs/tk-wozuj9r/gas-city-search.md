---
name: Gas City search — a start command that reports its app's URL, and an iOS app's capture
description: The search behind the operational surface tk-wozuj9r adds, as AGENTS.md requires, cited at gastownhall/gascity 5f7cd988a6. Read it to judge the change's divergence from Gas City, or before adding another ready signal to gctk rig serve or another kind of run to the capture's sandbox.
---

# Gas City search for tk-wozuj9r

Gas City is cited at `gastownhall/gascity` 5f7cd988a6 (upstream main,
2026-11-16), by page under `docs/` or by symbol. The capture engine is cited at
`zookanalytics/sprintshow` main b4d0b82.

The surface the change adds:

- `gctk rig serve` takes a second ready signal: a copy is up once its serve
  command prints the URL of the app it brought up on a line of its standard
  output, as well as once it answers on its port. Its report gains the key
  `app_url`, where a running copy's app is.
- `demo-engine-lib.sh` runs an iOS app run: `demo_engine_cli` gives a run whose
  `--base-url` names an iOS app on a simulator three free loopback ports, opens
  exactly those in the capture's sandbox, hands them to the engine as `--port`,
  and first provisions Appium through the engine's own command. The library
  gains `demo_engine_ios_app`, the test of such a URL.

The change adds no metadata key, bead kind, lifecycle state, order or formula
step.

## A ready signal printed on a line

**Searched.**

- **An agent's readiness.** An agent or a provider declares
  `ready_prompt_prefix`, "the string prefix that indicates the agent is ready
  for input", and `ready_delay_ms` (`docs/reference/config.md`, Agent at lines
  105-106 and the provider's at lines 774-775). Gas City reads them on the
  sessions it starts for agents. A copy is a process a session starts from a
  worktree, which no agent or provider config describes.
- **A service's readiness.** A `proxy_process` service declares `health_path`,
  which "is probed on the local listener before the service is marked ready"
  (`docs/reference/config.md`, ServiceProcessConfig at line 866). It is a probe
  of a port, on a declared service, one supervised process per name, which
  tk-rymdhac's search found a copy cannot be
  ([its search](../tk-rymdhac/gas-city-search.md#a-copy-of-a-rigs-ui)). An iOS
  app on a simulator answers on no port of the copy's.
- **A simulator.** Nothing in Gas City names `simctl`, a simulator or an
  `ios-simulator://` URL (`git grep -i -E 'simctl|ios-simulator|xcrun'` finds
  nothing at 5f7cd988a6).

**Composed.** The capture engine's own form of an app's URL and its reading of
one on a line of a start command's standard output (`findSimulatorUrl` and
`simulatorUrl` in `src/simulator.ts`, read by `serveIosApp` in `src/server.ts`),
which is the contract a rig's iOS start command is written to and the form the
engine takes as `--base-url`. gctk's copy reads the line by that rule, so the
pack and the engine read one command alike.

## The loopback ports of an iOS app run

**Searched.**

- **A port for a process a session starts.** Gas City allocates none, as
  tk-rymdhac's search found. Nothing in its `docs/` picks a loopback port for a
  caller at 5f7cd988a6.
- **A sandbox for one command.** Gas City's only use of `sandbox-exec` is still
  the macOS smoke test of a release (`scripts/smoke-macos.sh`, "macOS smoke
  test" in `CONTRIBUTING.md`).

**Composed.** The engine's `--port` for an iOS app run, which names a port for
Appium's server, WebDriverAgent's and its stream of the screen's frames, in that
order, after which the run listens on and connects to no other loopback port
(the engine's README, "iOS app demos", Ports). The pack's capture sandbox opens
exactly those three.

## Appium's provisioning

**Searched.** Gas City installs no tool a session's command needs. The engine's
own `provision appium` installs Appium, its XCUITest driver and the runner app
the driver installs on a device, each once per version, into the user's cache
(`provisionAppium` in `src/appium.ts`, `provisionRunnerApp` in
`src/webdriveragent.ts`).

**Composed.** The engine's provision command, run before every iOS app run, as
the capture already runs the engine's Playwright installer before every run.

## Where the growth lives

The ready signal and `app_url` are in gctk, in Go. The iOS app run grows
`demo-engine-lib.sh`, because its ports are allow rules in the capture
sandbox's profile and an argument to the engine's CLI, which that file composes,
and gctk's own copies run inside the same profile through it (the host adapter
in `docs/gctk-architecture.md`). That is code that configures other tools,
`sandbox-exec` and the engine, which AGENTS.md names as logic gctk is
inappropriate for.
