---
name: Why gc rig list is slow, and the one helper that reads the rig map
description: What tk-8fajj0n measured and traced about the cost of `gc rig list --json` on the city host, the other sources of the rig map it checked and why none can replace the listing, how assets/scripts/rig-map.sh bounds and explains the read, which callers read through it and which do not yet, and what was filed for the rest. Read it to check a number or a claim in docs/bead-store-resolution.md, "Reading the rig map".
---

# Why gc rig list is slow, and the one helper that reads the rig map

## The question

`gc rig list --json` took 19-23 s at host load ~90 and 30 s at load ~95 on
2026-10-26. Callers that bounded it short failed closed: `bead-store.sh` at a
hard 15 s, so `converse-rework.sh` refused a ruled rework in sitting
tk-v7c6973, and `converse-fold.sh` at its 20 s `GC_FOLD_SCAN_TIMEOUT`, so the
fold printed an empty holder with no reason (tk-5x6nt1p). tk-8fajj0n asked
why the listing slows, whether the prefix-to-rig map has a source that does
not, and for one shared read with one time policy.

## Where the time goes

Every figure is from the city host on 2026-10-26, with the installed gc at
e03752646 (fork main, built 2026-10-24). A PATH shim that logs each child
process gave the counts. The shim's own cost is in the times of the runs that
used it.

| load | `gc rig list --json` | `gc rig list` | children of one JSON listing |
|---|---|---|---|
| ~20 (shim) | 1.03 s | 0.17 s | 37: 28 `tmux list-sessions -F #{session_name}`, 1 `tmux list-panes -a`, 2 `ps`, 1 `bd context --json`, 5 `git`. The text listing started 2 `git`. |
| 25-30 (shim) | 1.91-2.25 s | 0.22-0.34 s | 37, 29 of them tmux |
| 36-52 (no shim) | 2.10-2.79 s | 0.31-0.58 s | 32 in a shimmed run, 24 of them tmux |

The text listing skips the `running` flag, and the source says why the JSON
listing pays for it. At e03752646, and unchanged at upstream/main 1036b2cb2
(2026-10-26):

- `doRigList` (cmd/gc/cmd_rig.go) builds a session provider for `--json` only,
  then fills each rig row's `running` with `rigHasRunningAgent`.
- `rigHasRunningAgent` walks every agent scoped to the rig until one is
  running. For a multi-session agent it calls `discoverPoolInstances`
  (cmd/gc/pool.go).
- For an unlimited pool (max < 0), `discoverPoolInstances` calls
  `sp.ListRunning("")`. A bounded pool enumerates static names instead.
- The tmux provider's `ListRunning` (internal/runtime/tmux/adapter.go) calls
  `listSessionNames`, which starts `tmux list-sessions` on every call. Only
  `IsRunning` has a cache, one `tmux list-panes -a` behind a short TTL.

So a rig with no running agent lists the city's sessions once for each of its
unlimited pool agents, and the listing's process count grows with the city's
agent count. On this host every city process runs under the supervisor's
launchd job, which macOS throttles, so load 50-150 is a scheduling queue, and
each process the listing starts waits in it. That is how a listing of a few
dozen processes reaches 20-30 s. The throttle is the mechanik's to lift, in the
town setup scripts (ruled in sitting tk-56yjgxg). The per-agent session listing
is Gas City's, and is filed with Gas City with these figures.

No pack caller reads a rig row's `running`. `city-liveness.sh` reads `running`
on the city's own row, where it is the controller probe, and
`doctor/check-recycle-capable` reads agents' `running` from `gc status`, not
from the rig list.

## Other sources of the map

Each was read on the host on 2026-10-26:

- `gc rig list` without `--json` carries every field the pack reads, but as a
  table for people. Parsing it would bind the pack to a format with no
  contract.
- `gc config show --json` (0.6-1.8 s, 2 `git` children) carries each
  configured rig's `Name`, `Path` and `Prefix`. Its `Suspended` is the
  `city.toml` flag alone, so it read `false` for the three rigs
  `gc rig list` reported suspended, whose suspension lives in
  `.gc/runtime/suspension-state.json`. The city's own row is not among its
  rigs.
- `gc status --json` (1.1-1.4 s, routed to the supervisor) carries each rig's
  name, path and suspension, but no prefix and no row for the city.
- `<city>/.beads/routes.jsonl` maps each prefix to a path relative to the
  city, written by Gas City for bd's routing. It carries no names and no
  suspension.

None carries the whole map with Gas City's own derivations, so the pack keeps
reading `gc rig list --json` and takes the slowness to Gas City.

## The helper

`assets/scripts/rig-map.sh` is the one read. It runs `gc rig list --json` with
no stdin, scrubs C0 bytes, and prints the listing as one line of JSON whose
`.rigs` is an array. When the listing does not read, it prints nothing on
stdout, writes one reason to stderr and exits 3. Each reason names its cause
and the move it calls for: a bound that ran out, a non-zero exit with gc's
first stderr line or its JSON error message, an empty answer, output that is
not JSON, or JSON with no `.rigs` array. It writes to stderr only then, so a
caller may capture both streams in one. `--city <path>` reads a named city's
map.

The time policy is one bound, `GC_RIG_LIST_TIMEOUT`, 120 s by default. It cuts
off a gc that never answers, and sits far above the 30 s a listing took at
load ~95. `timeout --foreground` keeps gc in the caller's process group, so a
caller's own deadline that signals the group reaches gc as well. Without a
`timeout` command the listing is read unbounded. The scratch file that holds
gc's stderr is optional: without a writable one the listing is still read,
and the reason goes without gc's stderr.

## The callers

These read the map through rig-map.sh:

- `bead-store.sh`, `bead-context.sh`, `bead-rehome.sh`, `branch-end.sh`,
  `converse-fold.sh`, `converse-rework.sh`, `deferred-dispatch.sh`,
  `demo-deliver.sh`, `demo-engine-lib.sh`, `first-reaction-dispose.sh`,
  `gc-helm.sh`, `gc-visit-open.sh`, `learning-recurrence.sh`,
  `notification-wisp-reap.sh`, `pr-visit-comment.sh`, `queue-priority.sh`,
  `reconcile-rig-checkouts.sh`, `review-workspace.sh`,
  `tmux-visit-prompt.sh` and `worktree-reap.sh` under assets/scripts.
- `tools/gc-proactive.sh` and `tools/upstream-gc-sync.sh`.
- Every doctor check that listed the rigs. A check runs the helper under its
  own budget slice and prints the helper's reason as a detail line, after its
  headline, because `gc doctor` reads a check's stdout and stderr as one
  stream whose first line is the message.

The bounds each caller put on the listing went with the switch: bead-store.sh's
15 s, bead-context.sh's 20 s, gc-helm.sh's `GC_HELM_RIG_TIMEOUT` (30 s),
tmux-visit-prompt.sh's `GC_VISIT_INTAKE_TIMEOUT` (300 s) and the fold's 20 s
`GC_FOLD_SCAN_TIMEOUT`. bead-store.sh, bead-context.sh and the fold keep
theirs on their store reads, and the prompt keeps its on the intake.
`converse-rework.sh` no longer discards
bead-store.sh's stderr, which is how the sitting saw "did not resolve" with no
reason. converse-fold.sh, which the native-gates convoy deletes, got the
switch and no other change, as built-once rule 1 and the routing note ask.

These still run `gc rig list --json` themselves, unbounded. They wait rather
than fail closed:

- `direct-merge-push.sh` and `refinery-workspace.sh`, whose roster lookups
  PR #1319 (tk-r5ofy4t, approved) moves onto its new `rig-root.sh`. This
  branch leaves those lines alone so the two branches touch no line in common.
  tk-fqixu93 has rig-root.sh read through rig-map.sh once both are on main,
  and waits on both anchors.
- Formula step text (mol-feedback-distiller, mol-rig-demo, and the rig-root
  lookups in mol-polecat-work, mol-refinery-patrol, mol-review and
  mol-review-quorum-signoff that PR #1319 rewrites), the keeper sub-pack's
  formulas and prompt, and the mechanik's prompt. Built-once rule 2 has
  existing step text change at its own rewrite.

## What stays slow

The helper explains a slow listing and stops callers failing closed under
bounds of their own, but the listing itself is as slow as before. A doctor
check gives it at most half of `gc doctor`'s 60 s per-check budget, so on a
host where the listing takes longer than that, the check still reports that it
could not read the rig map, now with rc 124 and its own budget as the reason.
The cause is the per-agent session listing in Gas City, filed there, and the
pack cannot change it where it arises.
