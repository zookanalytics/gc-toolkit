---
name: Gas City search for a demo capture sandbox that only some rigs get
description: The search the arch check asks for on letting the app_reads_city setting decide which rigs' demo captures and app copies run in the capture sandbox. Read it when deciding whether that switch, or the sandbox it turns on, can move onto something Gas City ships.
---

# Gas City search for a demo capture sandbox that only some rigs get

A demo capture, and the copy of a rig's app that `gctk rig serve` runs, now
run in the capture sandbox only for a rig whose `app_reads_city` counts as
`"true"`. A capture of any other rig runs as an ordinary process, without the
variables that point a command at the city. The change adds no key, no verb and
no state: it gives an existing setting, the formula var `app_reads_city`, the
decision of whether the sandbox applies, inside the one library that already
reads it (`demo-engine-lib.sh`, `_demo_engine_reads_city`). The arch check asks
what Gas City ships for that decision ([review-arch.md](../../docs/review-arch.md)).

## Where the search looked

Read on 2026-11-18 at upstream `gastownhall/gascity` `main` 3764de45ea: `docs/`,
`engdocs/`, `cmd/` and `internal/`, for `sandbox`, `isolation`, `seatbelt`,
`sandbox-exec`, `formula_vars` and the fields of `[[rigs]]`, then each hit in
its context.

## What Gas City ships near the need

- **A rig's own settings.** A city sets a value for one rig among the rig's
  `[rigs.formula_vars]` in `city.toml`, and `gc formula show --rig` reads it
  ([Gas City Configuration](https://docs.gascity.com/reference/config#rig),
  `docs/reference/config.md`). This is the primitive the setting already uses
  ([the setting's search](../tk-vd66j1.14/gas-city-search.md)), and the change
  composes it as it is: the switch is the same value, read the same way.
- **The trust model.**
  [Trust Boundaries](https://docs.gascity.com/reference/trust-boundaries)
  (`docs/reference/trust-boundaries.md`) says Gas City runs the commands a city
  configures as "a feature, not a sandbox". So Gas City runs a rig's own
  commands as ordinary processes, which is what a capture of a rig with no
  sandbox now does.
- **The gate environment.** `gateSandboxEnv` in `cmd/gc/doctor_gate_sandbox.go`
  reproduces the environment convergence hands a gate command,
  `convergence.ConditionEnv`: HOME set to the city and a whitelist of
  variables. It covers a convergence gate's command and nothing a rig starts,
  and no setting turns it on or off for a rig.
- **Session runtimes.** An exec session provider can run an agent's session in
  another runtime, such as a micro-VM
  ([Configuring an Agent](https://docs.gascity.com/guides/configuring-an-agent),
  `docs/guides/configuring-an-agent.md`, and
  [Exec Session Provider](https://docs.gascity.com/reference/exec-session-provider),
  `docs/reference/exec-session-provider.md`).
  It places a whole session, not one process a capture starts, and says nothing
  of which rigs need one.

Gas City ships no sandbox for a process an agent starts, and no rule that names
which rigs need one. The capture sandbox stays the pack's, and the rule that
picks the rigs it covers is a rig formula var, which Gas City does ship.
