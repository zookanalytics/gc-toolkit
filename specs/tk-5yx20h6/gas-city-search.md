---
name: Gas City search for the blocked-work check's warning when refinery-lib.sh does not load (tk-5yx20h6)
description: The search the arch check asks for on the one diagnostic doctor/check-blocked-work-armed gains with its exemption for an ask on a PR, the warning it gives when assets/scripts/refinery-lib.sh cannot be sourced, read at gastownhall/gascity upstream main 77143ecd18ff. Read it when reviewing that warning, or before a pack doctor check reports a library it cannot load in some other way.
---

# Gas City search: a doctor check that cannot load a library it reads

`doctor/check-blocked-work-armed` sources `assets/scripts/refinery-lib.sh` for
`refinery_ask`, the shell definition of an ask on a PR, so that it can exempt an
ask that waits on other work. When that library cannot be sourced, the check
exits 1 with the message "cannot determine whether blocked work carries a
dispatch path" and one detail line that names the library. That warning is the
one diagnostic this change adds. The check gives the same warning, each with its
own detail line, when `standing-kinds.sh`, `dispatch-path.sh`, `bd-lib.sh` or
`run-lib.sh` cannot be sourced.

Gas City is read at gastownhall/gascity upstream main `77143ecd18ff`
(2026-11-25T23:01Z).

## What Gas City ships near the need

- **The pack doctor protocol.** `gc doctor` runs a pack check as a script and
  reads only its exit status and its output. Exit 0 is OK, 1 is a warning and
  any other status is an error. The first line of output is the message, and
  the remaining lines are details (`PackScriptCheck.Run` and
  `parseScriptOutput` in `internal/doctor/pack_checks.go`). The pack spec lays
  out the check's directory the same way (`docs/reference/specs/pack-spec.md`,
  section 1.2.11, "Doctor Directory"). The warning composes this protocol as it
  is: an exit 1, a message and one detail line.
- **A script that cannot run.** When the check's script is missing or cannot be
  executed, `PackScriptCheck.Run` reports an error whose message starts "script
  error:" (same file). It knows the script, not the files the script sources.
- **The check's manifest.** `doctor.toml` takes `description`, `run`, `fix` and
  `warmup` (`doctorManifest` in `internal/config/doctor_discovery.go`, and the
  pack spec's table in the same section). None of them names a file a check
  needs.

## Why none covers the need

Gas City gives a pack check no way to declare a file it reads, and its runner
learns that a sourced library failed to load only from the script's own exit
status and output. So the check reports that failure itself, through the
protocol Gas City ships, as its other library guards do, and the change builds
no mechanism of its own for it.
