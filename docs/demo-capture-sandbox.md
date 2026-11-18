---
name: The demo capture sandbox
description: Use when you need to know what a demo capture, or a copy of a rig's app that gctk rig serve runs, can and cannot reach on the city's host, such as before you rule on a change that widens it.
---

# The demo capture sandbox

## Scope

**Mandate.** What the sandbox around a demo capture guarantees on the city's
host, and what it lets through. That covers every capture the pack runs and the
copy of a rig's app that `gctk rig serve` runs for a capture or a sitting.

**Boundaries.** The sandbox's rules one by one, and the cases a run is refused
in before it starts, are in the header of
[`demo-engine-lib.sh`](../assets/scripts/demo-engine-lib.sh), which writes the
profile. How a rig's start command brings its app up is the start contract in
the [`gc-toolkit.demo-capture`](../skills/demo-capture/SKILL.md#the-rigs-start-command)
skill. The browser the demo agent drives over MCP runs outside this sandbox.

## What runs inside it

- The capture engine, SprintShow, and every process it starts: the headless
  browser, a terminal script's shell and its commands, the engine's own file
  server, and the Appium that drives an iOS app.
- A copy of a rig's app, which `gctk rig serve` runs from a checkout: the rig's
  start command and every process it starts, such as a web server and the
  database server it starts beside it.

macOS's `sandbox-exec` applies one profile, which the pack writes for the run,
to the first process and to every process that one starts. A host without
`sandbox-exec` runs no capture.

## What it guarantees

A process inside the sandbox:

- cannot list or read the contents of the city's directories, or write in
  them. Those are gc's home, each city gc lists there, the city, rig and store
  the session's environment names, and every rig's checkout. It reads and
  writes the rig worktree it runs from, the directories the capture names, and
  the engine's checkout, which it reads only.
- cannot connect to a loopback port it was not given, so the supervisor's API,
  the Dolt server and every agent session's own port do not answer it. A run is
  given its own port, or the three an iOS app run's servers use. A copy is given
  its own port and the extra ports the city gives its rig (below), and a capture
  of the copy is given the same ports.
- cannot connect to a Unix socket except the system's name resolver and the
  sockets a copy's own processes open in the copy's own temporary directory. So
  tmux and every other program's socket do not answer it.
- cannot send a signal to a process outside the sandbox.
- starts with none of the variables that point a command at the city:
  `GC_*`, `GT_*`, `BEADS_*`, `BD_*`, `DOLT_*`, `TMUX` and `TMUX_PANE`.

A capture also refuses, before anything starts, a run it cannot keep to those
rules. Examples are a working directory that holds the city's, a server already
listening on the port it would open, and a `--base-url` on this host that
neither a copy nor a rig whose `app_reads_city` is `"false"` serves. The
library's header lists every such refusal.

## What it lets through

- **The internet.** Any remote host answers, such as the package registries a
  start command installs from, GitHub, and the speech service a narrated clip
  uses.
- **Files outside the city's directories.** A process can read and write the
  rest of the disk the session's user can, including the home folder of the
  session that runs the capture. That folder holds the credentials tools keep
  there, such as the GitHub CLI's `~/.config/gh/hosts.yml`, Claude Code's
  `~/.claude/.credentials.json` and `~/.ssh`. The other agents' home folders,
  and the files in them, are open to it as well.
- **Other processes' arguments and environment.** macOS lets a process read
  those of every process its user runs, inside the sandbox too, so a capture can
  read the environment of the city's own `gc` process and of every agent
  session.
- **The system's services.** What macOS reaches through Mach and XPC stays open,
  such as the simulator service that runs an iOS app outside the sandbox.

## An app that runs as several local processes

Such an app, such as a web server and the database server it starts beside it,
listens on more loopback ports than its own, and its processes talk to one
another there. The city gives a rig how many ports beyond the copy's own its app
listens on, as `ui_serve_extra_ports` among the rig's `[rigs.formula_vars]` in
`city.toml`. That setting lives outside the rig's repository, so no change the
rig reviews can widen what its copy reaches. For each copy of the rig's app:

- `gctk rig serve` picks that many more free loopback ports before the start
  command runs, and gives them to it as `$PORT_1`, `$PORT_2` and on.
- The copy's sandbox opens those ports beside the copy's own, and nothing else.
- The copy is up only once its own processes listen on every one of them. A
  capture of the copy then opens the same ports for the browser, which reaches
  each of the app's servers, as a page's client reaches its database server.
- The copy's `$TMPDIR` is a directory made for that copy, which goes once the
  copy ends. Its processes may connect to the Unix sockets they open there, and
  to no other but the name resolver's.

A port is free when it is picked, and the app takes it once its server starts.
Another program of the same user that listens on that port in between, such as
an agent session starting, is one the app's processes could reach until the
copy fails to come up, because a copy whose ports another program holds is
never up.

## Look for yourself

Any command runs in a copy's sandbox, with the loopback ports it may reach as
the first argument, from a rig worktree or from a directory that holds none of
the city's, such as `/tmp`. This one lists `~/.ssh` from inside it:

```bash
cd /tmp && bash -c '. "$(gc gc-toolkit scripts-dir)/demo-engine-lib.sh" && demo_engine_sandboxed 5999 "$PWD" "$@"' _ ls ~/.ssh
```

A read the sandbox refuses prints `Operation not permitted`, as `cat` of the
city's `city.toml` does there.
