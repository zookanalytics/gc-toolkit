---
name: Gas City search for the session-list-no-api detector
description: The search the arch check asks for before the change adds tools/lint-learned.d/session-list-no-api.sh, the learned-lint detector that fails a pack gc session list call left without GC_NO_API. What Gas City, the packs it bundles and publishes, and bd ship for keeping that read local and for holding a rule over the commands a pack runs, read at named upstream commits, and why the pack's own lint covers what they do not. Read it when checking whether the pack still needs the detector or the per-call setting, or whether Gas City now keeps the read local by itself.
---

# Gas City search for the session-list-no-api detector

The change adds operational surface in
`tools/lint-learned.d/session-list-no-api.sh`. The detector fails a pack
`gc session list` call whose command carries no `GC_NO_API` value that gc reads
as switching the API off. The arch check asks what Gas City already ships for
that ([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City reads `GC_NO_API` in each gc process, and no flag or setting it ships
fixes the route of one command, so the pack sets the variable on each call. Gas
City hands a rig's own lint rules to the rig through the rig's `lint_command`,
and the detector runs inside that seam. Gas City's own checkers are `gc lint`,
whose checks are fixed Go code that no pack adds to, and `gc doctor`, which runs
a pack's checks against the pack the city has already loaded. Neither refuses a
change before it lands. Gas City's repositories hold rules about the commands
their files run as checks each repository owns, and the detector is one more
such check.

## The surface and the need

The change adds one executable to `tools/lint-learned.d/`, which
`tools/lint-learned.sh` runs with the other detectors. It reads `*.sh` files and
the fenced code and marker blocks of `*.toml` and `*.md` files, the surfaces
`pr-post-bypass.sh` reads. It reports the words `session list` in command code
when the command carries no `GC_NO_API` assignment set to 1, true or yes. It adds
no bead kind, lifecycle state or metadata key, so it adds no pack noun and needs
no warrant ([review-arch.md](../../docs/review-arch.md#the-checks), check 2).

The rule it holds has two parts:

1. Every `gc session list` the pack runs reads gc's local rows, the listing whose
   fields the pack parses, whether or not the city's controller answers gc in
   time.
2. A change that adds a call without the setting fails before it lands.

## Where the search looked

Each was read on 2026-10-30 (UTC):

- Gas City at main `adf99aa6c84d`: the CLI reference for `gc session list`,
  `gc ready`, `gc lint` and `gc doctor` and for gc's global flags, the
  configuration reference's `APIConfig`, the `formula_vars` of `Rig` and every
  `env` field, the pack specification's doctor directory, the guide *Set Up a
  Multi-Agent Engineering Environment*, the `core` pack it bundles, and the
  checks its own `make check` runs. Its source was searched for every reader of
  `GC_NO_API`, the route its CLI's API client takes and the controller probes
  that route rests on, the route `gc session list` takes and the row its API
  path prints, the commands that prefer the supervisor, `gc lint`'s checks and
  the doctor's pack checks.
- Every pack in Gas City's packs repository at `0b0d96250f66`: `bmad`, `cass`,
  `compound-engineering`, `contributing-to-gascity`, `discord`, `gascity`,
  `gastown`, `github`, `gstack`, `oversight-rig`, `pr-pipeline`, `pr-review`,
  `profiler`, `runtime-cloudflare`, `slack-channel`, `slack-full`, `slack-mini`
  and `superpowers`, with the repository's own scripts, tests and CI workflow.
  Each was searched for `gc session list` and `GC_NO_API`, and each hit was read.
  Gas City bundles `gastown` from that repository at `cb6a612882b8` and the build
  pack `gascity` at `5bf643ca55bd`, and the same search ran at both.
- bd at main `f7b94653eb89`: `bd lint`.

Each passage cited below from Gas City's and bd's documentation was also found
on the live sites, docs.gascity.com and beads.gascity.com.

## What Gas City ships

### The route a session list takes

**`GC_NO_API` is the one switch, and it reaches a whole gc process.**

- The [CLI reference](https://docs.gascity.com/reference/cli#gc-session-list)
  gives `gc session list` the flags `--json`, `--state` and `--template`, and
  gc's global flags are `--city`, `--rig`, `--context`, `--city-url` and
  `--city-name`. None of them chooses where the rows come from.
- The command takes its client from `localWhenSupervisorHostedAPIClient`
  (package main, `sessionListAPIClient`), which #8331 set (`320b482fc`,
  2026-10-28). That function's comment gives the reason: the local rows "carry
  the fields schemas/session/list/result.schema.json defines (agent_name, closed,
  the summary), which the API's session rows do not". The local row,
  `sessionListJSONRow`, has `provider`, `rig`, `agent_name`, `session_key` and
  `closed`. The API path's row, package api's `SessionView`, has none of them.
- That route renders locally for a supervisor-hosted city only once gc has
  learned that the city is one. `routeAPIClient` asks `probeControllerIdentity`,
  which sends the controller its identify command with 500 ms to dial, 500 ms to
  write and 2 s to read, and falls back to `controllerAlive`'s ping with the same
  timeouts. When neither answers in time, the probe reports no controller, and
  `routeAPIClient` returns the supervisor-managed client, so a city the
  supervisor runs gets the supervisor API's rows. A controller slowed by load can
  miss both, and that is the case the rule exists for.
- `routeAPIClient` returns no client on any route while `GC_NO_API` is 1, true or
  yes (`classifyGCNoAPI`), so the command renders locally whatever the controller
  does. The CLI reference documents the variable only under
  [`gc ready`](https://docs.gascity.com/reference/cli#gc-ready): "GC_NO_API=1
  forces the local read". For `gc session list` it is read in the source only.

**Configuration sets environment for a process, never for one command.** The
[configuration reference](https://docs.gascity.com/reference/config) puts `env`
on [`Workspace`](https://docs.gascity.com/reference/config#workspace) ("applied
to every managed session"), `Agent`, `AgentOverride`, `AgentPatch`,
`ProviderSpec`, `ProviderPatch`, `UpstreamSpec` and
[`OrderOverride`](https://docs.gascity.com/reference/config#orderoverride)
("exported into an exec order's child process"). `GC_NO_API` set in any of them
reaches every gc command that process runs, and `routeAPIClient` then sends none
of them to the API. Gas City sends `gc status`, `gc ready` and `gc maintenance`
to the supervisor on purpose (`supervisorFallthroughAPIClient`). That function's
comment puts `gc status`'s local fallback, which re-opens the local store and
rescans event archives, at about 9.5 s of CPU against about 0.35 s for the
supervisor's cached answer.
[`APIConfig`](https://docs.gascity.com/reference/config#apiconfig)'s `port` does
not reach this route either: `apiClient`'s comment says the supervisor ignores a
hosted city's `[api]` port and serves the city on its own.

**No pack Gas City bundles or publishes keeps the read local.** In `core`,
`orphan-sweep.sh`, `nudge-on-route.sh` and `cascade-nudge-on-blocker-close.sh`
run `gc session list --json` with no `GC_NO_API`. At the packs repository's main,
gastown's `witness-heartbeat-check.sh`, `mol-shutdown-dance` and
`mol-witness-patrol`, oversight-rig's `nudge-project-leads.sh` and the
repository's `scripts/gascity_pack_inference_gate.py` run it the same way.
Neither the repository nor the bundled `gastown` and `gascity` copies name
`GC_NO_API` anywhere.

So the variable on each call is the narrowest control Gas City offers, and
nothing Gas City ships keeps a new call carrying it.

### Where a rig's own lint runs

Gas City hands a rig's lint to the rig. Core's `mol-polecat-base` declares
`lint_command`, a "Command to run linting", as a value from the rig's
`formula_vars`, and runs it in its `preflight-tests` and `self-review` steps.
`mol-scoped-work` declares it and runs it in the same two steps. A rig's
[`formula_vars`](https://docs.gascity.com/reference/config#rig) are its
"rig-scoped defaults for formula vars". This rig's `lint_command` runs
`tools/lint-learned.sh` over the files a change touches, so the detector runs
inside the seam Gas City provides, through the rule runner the pack already has.

### The checkers Gas City ships

**`gc lint` runs a fixed set of checks.** The
[CLI reference](https://docs.gascity.com/reference/cli#gc-lint) describes it as
"Validate a pack before merge": it "validates the pack.toml file, reports
non-fatal loader warnings, and parses prompt templates". `lintPack` runs the
pack loader, `lintNamedSessionPoolConflicts`, `lintFormulaFiles`, which reports
only `formula.GraphV2OutputJSONWarnings`, `lintPrompt`, which parses prompt
templates and scans them for flags bd does not know (package bdflags,
`ScanUnknownFlags`), and `lintClaudeOverlayHookShape`. They are Go functions
that `lintPack` calls in turn. Nothing in a pack or its configuration adds one,
and none of them reads a script.

**`gc doctor` runs a pack's checks against the pack the city loaded.** The
[pack specification](https://docs.gascity.com/reference/specs/pack-spec#1-2-11-doctor-directory)
lets a pack author checks under `doctor/`. The guide *Set Up a Multi-Agent
Engineering Environment* recommends them to a team that "keeps rediscovering the
same mistakes"
([Encode known mistakes as doctor checks](https://docs.gascity.com/guides/multi-agent-engineering-environment#encode-known-mistakes-as-doctor-checks)),
and says that "`gc doctor` runs every check the city's packs supply". That is the
home Gas City names for a known mistake, and the closest primitive to this need.
It does not meet the rule's second part. `PackScriptCheck.Run` (package doctor)
runs a check's script in the pack directory the city loaded, with `GC_CITY_PATH`
and `GC_PACK_DIR` in its environment. A doctor check over the pack's files
therefore reads the pack the city already runs. It would report a call left
without the setting only after the change has landed and the city has picked it
up, and only when someone runs `gc doctor` or `gc start` warms a check marked
`warmup`. No order in `core` runs either. By then the misread it guards against
is live.

**bd has no check of files.**
[`bd lint`](https://beads.gascity.com/cli-reference/lint) checks issues for
missing template sections.

### What Gas City's own repositories do

Gas City's repositories hold rules about the commands their files run as checks
each repository owns:

- The packs repository's `tests/test_shipped_bd_flags_exist.py` holds that
  "Shipped `gc bd` invocations must not use flags or verbs bd rejects", and says
  why the repository needs its own check: "`gc lint` does not report either". Its
  `tests/test_no_gc_sling_wrapper.py` fails a runnable-looking call of a
  `gc-sling` wrapper that does not exist, and `tests/test_no_bare_bd_commands.py`
  fails a bare `bd` command in shipped pack assets, which would "bypass
  store-aware routing". The repository's CI workflow runs them with pytest.
- Gas City's own `make check` runs `scripts/check-routed-test-rows.sh`, a
  "Drift-prevention lint" that holds the tests of the read commands gc routes
  through the API to a matrix of six rows, one of them the `GC_NO_API` escape
  hatch.

These run in each repository's own checks, and neither gc nor a bundled pack
ships them.

## Why the pack's own check covers it

- The rig's `lint_command` runs `tools/lint-learned.sh` over the files a change
  touches. mol-polecat-work's self-review loop releases a change to submit only
  when that check passes at the change's head, a failure the base already
  carries aside (`assets/scripts/self-review-check.sh`). A change that adds a
  call without the setting therefore fails before its hand-off, which is the
  rule's second part.
- A run of the runner over the whole tree fails on such a call anywhere
  ([the detectors' README](../../tools/lint-learned.d/README.md)).
- The detector is one more rule in the runner the pack already has. It adds no
  runner, no order and no pack noun.
- Go code that execs gc is outside its scan. Helm's one exec of
  `gc session list` sets the variable in the command's environment, and its own
  test holds that.

## When this answer changes

- If gc renders `gc session list` locally for a supervisor-hosted city whether
  or not the controller answers its probes, or its API path prints the local
  listing's fields, the per-call setting and the detector retire together. At
  `adf99aa6c84d` gc does neither.
- If `gc lint` takes a rule from a pack, or gc itself checks the route of a
  pack's `gc session list` calls, the rule moves there. At `adf99aa6c84d` gc
  does neither.
