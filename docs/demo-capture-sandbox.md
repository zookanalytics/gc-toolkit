---
name: The demo capture sandbox
description: Use when you need to know which rigs' demo captures run in the capture sandbox, what a capture or a copy of a rig's app that gctk rig serve runs can and cannot reach on the city's host, or what a capture of any other rig reaches, such as before you set a rig's app_reads_city or rule on a change to the sandbox.
---

# The demo capture sandbox

## Scope

**Mandate.** What the sandbox around a demo capture does on the city's host,
which rigs' captures run in it, and what it does not stop. That covers every
capture the pack runs, and the copy of a rig's app that `gctk rig serve` runs
for a capture or a sitting.

**Boundaries.** The rule that decides a run's sandbox, the sandbox's rules one
by one, and the cases a run is refused in before it starts are in the header of
[`demo-engine-lib.sh`](../assets/scripts/demo-engine-lib.sh), which writes the
profile. How a rig's start command brings its app up is the start contract in
the [`gc-toolkit.demo-capture`](../skills/demo-capture/SKILL.md#the-rigs-start-command)
skill. The browser the demo agent drives over MCP runs outside this sandbox.

## Which rigs get it

A rig's captures run in the sandbox when `city.toml` sets its
`app_reads_city`, among the rig's `[rigs.formula_vars]`, to anything but
`"false"`. A city sets it to `"true"` for a rig whose app reads the city, such
as a rig that develops code for a city. The rig that holds the pack's own
source keeps the sandbox whatever its setting says, and so does a rig whose
setting does not read. Every other rig's captures, and the copies of its app,
run as ordinary processes. The setting lives in `city.toml`, outside the rig's
repository, so no change the rig reviews can turn its sandbox off.

A capture is judged by the checkout it captures from: the checkout a copy of
the app runs from, the worktree a server on this host that it captures works
in, the directory it serves, or the one a terminal capture's shell starts in.
A capture that names none of those is judged by the directory it runs from. A
capture from a directory no rig holds, or from the city's own repository, keeps
the sandbox.

## What runs inside it

For a rig that keeps the sandbox:

- The capture engine, SprintShow, and every process it starts: the headless
  browser, a terminal script's shell and its commands, the engine's own file
  server, and the Appium that drives an iOS app.
- A copy of the rig's app, which `gctk rig serve` runs from a checkout: the
  rig's start command and every process it starts.

macOS's `sandbox-exec` applies one profile, which the pack writes for the run,
to the first process and to every process that one starts. A host without
`sandbox-exec` runs no capture, of any rig.

A copy runs as its rig's setting read when the copy started, until it stops,
and `gctk rig serve` reports which way it runs. So a copy that started while
the setting read `"false"` still runs as an ordinary process once the rig keeps
the sandbox, and a capture of the rig refuses it, whether `--serve` finds it
running or a `--base-url` names it. A copy whose report does not say how it
runs counts as one that runs without the sandbox. The capture leaves a copy it
found running, since the copy may serve someone else. `gctk rig serve --stop`,
run from the copy's checkout, ends it, and the rig's next copy starts inside
the sandbox.

## What it guarantees

A process inside the sandbox:

- cannot list or read the contents of the city's directories, or write in
  them. Those are gc's home, each city gc lists there, the city, rig and store
  the session's environment names, and every rig's checkout. It reads and
  writes the rig worktree it runs from and the directories the capture names,
  and it reads the engine's checkout.
- cannot list or read the contents of the home folders, or write in them, but
  for the parts its tools need. The home folders are the session's own and the
  user's, which the system's user record names and which holds the home of
  each agent a host keeps inside it. Tools keep their credentials there, such
  as the GitHub CLI's token, an agent's sign-in, SSH keys and the supervisor's
  service file. A process reads each Node on its `PATH`, Playwright's browsers
  and Go's own files, and it reads and writes the caches of npm, the engine and
  Go. Its git reads none of the user's settings. Of the directories and files
  the capture names, it reaches one in a home folder only when it lies in a rig
  worktree.
- cannot connect to a loopback port it was not given, so the supervisor's API,
  the Dolt server and every agent session's own port do not answer it. A run is
  given its own port, or the three an iOS app run's servers use. A copy is
  given its own port, and a capture of the copy is given the same one.
- cannot connect to a Unix socket except the system's name resolver, so tmux
  and every other program's socket do not answer it.
- cannot send a signal to a process outside the sandbox.
- starts with none of the variables that point a command at the city:
  `GC_*`, `GT_*`, `BEADS_*`, `BD_*`, `DOLT_*`, `TMUX` and `TMUX_PANE`.

A capture also refuses, before anything starts, a run it cannot keep to those
rules. Examples are a working directory that holds the city's or a home folder,
an output or a `--cwd` that lies in a home folder outside any rig worktree, a
server already listening on the port it would open, a `--base-url` on this
host that neither a copy nor a worktree of a rig whose `app_reads_city` is
`"false"` serves, and a copy that runs outside the sandbox its rig now keeps.
The library's header lists every such refusal.

## What it lets through

- **The internet.** Any remote host answers, such as the package registries a
  start command installs from, GitHub, and the speech service a narrated clip
  uses.
- **Files outside the city's directories and the home folders.** A process can
  read and write the rest of the disk the session's user can, such as the
  system's temporary folders.
- **The tools' caches in the home folders.** A process writes the caches of
  npm, the engine and Go, which the session's own tools read later.
- **Keys in its own environment.** The engine, a terminal capture's commands
  and a copy's serve command start with the environment of the session that
  runs the capture, less the variables that point at the city, so they hold
  keys the supervisor hands sessions, such as the speech service's.
- **Other processes' arguments and environment.** macOS gives a process those
  of every process its user runs, through `sysctl`'s `KERN_PROCARGS2`, under
  any sandbox profile, and `launchctl print` shows it the environment launchd
  gives a job, such as the supervisor's. So a capture can read the environment
  of the engine, of the city's own `gc` processes and of every agent session,
  with the keys they carry: those the supervisor hands sessions, the Dolt
  server's password and the sessions' own tokens.
- **The system's services.** What macOS reaches through Mach and XPC stays open,
  such as the simulator service that runs an iOS app outside the sandbox.

## A capture of any other rig

A capture of a rig whose `app_reads_city` is `"false"` runs the engine, the
browser it launches, a terminal capture's shell and the copy of the rig's app
as ordinary processes. It reaches what the rig's own tests and builds reach on
this host. That includes the live city when the rig's app or its demo script
calls it, such as through the supervisor's loopback API or by reading the
city's files, because nothing refuses either. An app made of several local
servers comes up as it does for its tests, since nothing refuses its other
ports or its sockets.

Such a capture still starts without the variables that point a command at the
city, so nothing in its environment names this session's city, store or tmux.
It takes each refusal the library's header lists for a run with no sandbox: a
`--base-url` on this host must still name a copy, or a server a worktree of a
rig whose `app_reads_city` is `"false"` serves.

## Look for yourself

Any command runs in a copy's sandbox, with the loopback port it may reach as
the first argument, from a directory that holds none of the city's, holds no
home folder and that no rig holds, such as `/tmp`. This one lists `~/.ssh` from
inside it:

```bash
cd /tmp && bash -c '. "$(gc gc-toolkit scripts-dir)/demo-engine-lib.sh" && demo_engine_sandboxed 5999 "$PWD" "$@"' _ ls ~/.ssh
```

A read the sandbox refuses prints `Operation not permitted`, as the listing of
`~/.ssh` and `cat` of the city's `city.toml` do there. Run from a worktree of a
rig whose `app_reads_city` is `"false"`, with that worktree in place of `/tmp`,
the same call says the command runs as an ordinary process, the listing shows
`~/.ssh`, and `cat` prints `city.toml`.
