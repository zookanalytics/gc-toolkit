---
name: Gas City search for a capture of a rig's own app on this host
description: The search the arch check asks for on demo-capture.toml, the file in which a rig declares that its app never reads the city, and on how a capture tells whose server answers a --base-url on this host. Read it when deciding whether either can move onto something Gas City ships, or when Gas City ships a per-rig setting a script reads, or a command that names the process behind a port.
---

# Gas City search for a capture of a rig's own app on this host

A demo capture can now reach a rig's own app on this host through
`--base-url`, when the rig declares that its app never reads the city. The
capture sandbox otherwise holds every capture to its own server's loopback port.
That adds operational surface: a file a rig declares in, and an allowance in
`demo_engine_cli` with the reads that decide it. So the arch check asks what Gas
City already ships for each
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships no per-rig setting that a rig's own reviewed change writes and a
script reads, and no command that names the process behind a port. So the rig
declares in a file of its own repository, read at its default branch, and the
library asks `lsof`, the tool Gas City uses for the same two reads and lists
among the universal dependencies its doctor checks. The change composes one Gas
City field: the rig map's `hq` entry, which keeps the city's own repository
from ever counting as a declaring rig.

## The surface

1. **The declaration.** `demo-capture.toml` at the root of a rig's repository
   holds the line `app_reads_city = false`, with comments and blank lines and
   nothing else. `demo-engine-lib.sh` reads it at the rig checkout's
   `origin/HEAD`, or at `origin/main` where the checkout records none, so a
   change to it counts once it merges.
2. **The allowance.** `demo_engine_cli` takes a `--base-url` on this host when
   the URL's port is none that a variable pointing at the city names, and every
   process of this user that listens on the port works in a worktree of a rig
   that declares. A rig's checkout, which holds its store, is no such worktree,
   and neither is the city's own repository nor a directory in no rig's
   repository. The sandbox then opens that one port. Every other `--base-url` on
   this host keeps the refusal, which now names why.

The change adds no metadata key, bead kind or lifecycle state, so it carries no
warrant.

## Where the search looked

Read on 2026-11-04 at upstream `main`:

- `gastownhall/gascity` 3203354c33ae: `docs/`, `engdocs/`, `cmd/` and
  `internal/`.
- `gastownhall/gascity-packs` 796d7ecd73cf, every pack directory.

The terms were `formula_vars`, the fields of `[[rigs]]`, `patches`, `env`,
`default_branch`, `hq`, `lsof`, `ListenPort`, `LISTEN`, `cwd`, `preview`,
`base_url`, `base-url`, `dev server`, `localhost:`, `screenshot`, `playwright` and
`sandbox-exec`, then each hit in its context. Pages are cited by title and link,
and source by package and symbol at those commits.

## What Gas City ships near the declaration

- **Rig configuration.**
  [Gas City Configuration](https://docs.gascity.com/reference/config#rig),
  `Rig` (`config.Rig` in `internal/config`). Its fields name the rig's
  checkout, bead prefix, default branch and merge strategy, its suspension, its
  formula layers and pack imports, its session cap and idle sleep, patches to
  its agents, its sling targets, its federation and namespace, its Dolt host and
  port, its store proxy's idle timeout, and `formula_vars`. None states what the
  rig's app reads.
- **`formula_vars`** "provides rig-scoped defaults for formula vars. Keys match
  var names declared in formula `[vars.<name>]` blocks." It fills a formula's
  step text. A capture runs from a review's step, from `mol-rig-demo`'s step and
  from an agent's own shell under the demo:capture skill, so no one formula's
  var reaches every capture, and a script reads a var by naming a formula, as
  `gc formula show <formula> --rig` does
  ([CLI reference](https://docs.gascity.com/reference/cli#gc-formula-show)). Its
  value is written in the city's `city.toml`, while the fact it would record
  belongs to the rig's app, whose repository carries the app's code and is
  reviewed with it.
- **Agent patches' `env`**
  ([AgentOverride](https://docs.gascity.com/reference/config#agentoverride),
  `config.AgentOverride.Env`) put a variable in a session's environment. Any
  command line can set the same variable, so it cannot decide what a capture
  reaches.
- **The rig map.** `gc rig list --json`
  ([CLI reference](https://docs.gascity.com/reference/cli#gc-rig-list);
  `RigListItem` in `cmd/gc/cmd_rig.go`) lists each rig's name, path, prefix,
  default branch, `hq`, suspension, running state, sling targets, federation,
  namespace and store state. It carries nothing a rig declares about its app.
  Its first entry is the city itself, with `hq` true. This change composes that
  field: a server in a worktree of the city's own repository never counts as a
  declaring rig's.

So the rig declares in its own repository. The pack already reads one
rig-declared file that way, `not-for-review.toml`, at the default branch
([not-for-review.md](../../docs/not-for-review.md)), and `demo-capture.toml`
follows it, including the fallback from `origin/HEAD` to `origin/main`. The rig
map's `default_branch` is not that branch's source:
`config.Rig.EffectiveDefaultBranch` returns the field as `city.toml` sets it,
which is empty for a rig that sets none.

## What Gas City ships near the owner of a port

- **No command names the process behind a port, or its working directory.**
  Gas City makes both reads internally. `portsByPIDFromLsof` in
  `cmd/gc/dolt_cleanup_discovery.go` lists listening ports with
  `lsof -nP -iTCP -sTCP:LISTEN` to find Dolt servers for `gc dolt cleanup`, and
  `liveWorktreeCwdEnumerator` in `cmd/gc/bead_worktree_liveness_fallback.go`
  lists each process's working directory with `lsof -a -d cwd -F0pn` to tell
  which worktrees a live process works in. The library makes the same two
  reads. Gas City's doctor checks that `lsof` is installed, among its universal
  dependencies (`doctor.NewBinaryCheck("lsof", ...)` in `cmd/gc/cmd_doctor.go`),
  so a host that runs Gas City has it.
- **A working directory alone does not identify a rig's app.** On the city's
  host, its Dolt server ran with its working directory in one rig's checkout,
  wherever the command that started it ran. So a server counts only from a
  worktree of the rig, never from its checkout, and a port that a variable
  pointing at the city names is refused whoever listens there. A session's
  environment names the Dolt server's port in `GC_DOLT_PORT` and
  `BEADS_DOLT_SERVER_PORT`.
- **Nothing contains one command.** The sandbox's own record,
  [specs/tk-r9wui2m/gas-city-search.md](../tk-r9wui2m/gas-city-search.md),
  found no Gas City primitive that does. This change keeps that sandbox and
  opens one more port in it.

## What gascity-packs ships near it

- gstack's `qa` skill (`gstack/skills/qa/SKILL.md`) drives a local app with its
  own browser, trying `http://localhost:3000`, `:4000` and `:8080`, with no
  sandbox and no check of whose server answers there.
- The `base_url` hits name the supervisor's API (`GC_API_BASE_URL`), not an app
  a capture drives.
- No pack has a rig declare what its app reads.
