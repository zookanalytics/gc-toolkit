---
name: Gas City search — a ruling that retires a PR on the pending record
description: The search behind the landing order's close of a bead whose PR a ruling retired, as AGENTS.md requires. It names each Gas Town, Gas City and bd primitive searched, at gastownhall/gascity-packs 7f86098c04ea, gastownhall/gascity 192fa2d39407 and bd v1.3.4, what the change composes, and why none covers the rest. Read it to judge the change's divergence from Gas City, or before changing how a PR on the pending record retires.
---

# Gas City search for tk-1tfzr71.89

Read on 2026-11-16 at `gastownhall/gascity-packs` 7f86098c04ea, the commit
the pack's landing order follows, from a clone of that commit; at
`gastownhall/gascity` main 192fa2d39407, through the upstream remote of the
city's gascity checkout; and at `github.com/steveyegge/beads` v1.3.4, the bd
that commit's `go.mod` names, from the module cache. Gas Town is cited by path
and symbol, and Gas City and bd by symbol.

The need: a ruling that a PR on Gas Town's pending record will not land is
carried out in one act. The PR closes, nothing merges it meanwhile, and the bead
that owns it closes onto the bead that carries the work now, or onto the
evidence that ruled it out, with nothing left for a person to answer.

The surface the change grows is the landing order, `gctk pr reconcile`: it
reads the disposition `pr-dispose.sh` already records before it closes a PR,
requests no merge of such a PR, and once the PR has closed it runs the pack's
disposition writer, `bead-rehome.sh`, as the refinery. Its output gains one
outcome, `disposed`, and `pr_state` one value, `closed`. The writer gains three
flags that name a caller's judgment of the bead, `--if-status`, `--if-assignee`
and `--if-ruled`, which the landing order passes because it judges the bead
under the store's record lock and runs the writer once that lock is free. The
change adds no script, order, metadata key, bead kind or lifecycle state.

## Searched

- **Gas Town's landing reconcile.** `reconcile_one` in
  `gastown/commands/pr-merge-reconcile/run.sh` reads the PR by its number, and
  its `CLOSED` arm calls `quarantine_terminal_pr` for every close: the bead is
  blocked at `merge_result=pull_request_closed_unmerged` with
  `pr_state=closed_unmerged`, its marker cleared, and the mayor mailed an
  escalation. It reads no record of why the PR closed, so a ruling's close and
  an accident end in the same quarantine, which a person must answer. The
  pack's landing order follows this command, and its exception gate under
  `pull_request_closed_unmerged` is that quarantine's.
- **bd's `gh:pr` gate.** `checkGHPRWithRunner` in `cmd/bd/gate.go` resolves the
  gate when the PR merged and escalates it when the PR closed without merging,
  whatever closed it. A gate is a wait on the PR, not a close of the bead that
  owns it, and it too reads every unmerged close as a failure.
- **Gas City's PR monitor.** `pullRequestsQuery` in
  `internal/githubmonitor/client.go` lists only open PRs
  (`pullRequests(..., states: OPEN, ...)`), and the monitor's answer for a PR is
  a repair bead. Nothing in `internal/githubmonitor` or `cmd/gc/cmd_github.go`
  reads a closed PR or closes the bead that owns one.
- **bd's disposition commands.** bd records a successor with its own
  `supersedes` and `duplicates` edges, which `bead-rehome.sh` already writes and
  reads back before its checked close. The change reuses that writer, so no bd
  command is composed here that the pack does not already compose.
- **bd's update guards.** `updateGuardsFromFlags` in `cmd/bd/update.go` reads
  two guards, `--if-assignee`, where an empty value means unassigned, and
  `--if-status`, and the update applies only while the bead still has them.
  The command's flags in that file's `init` declare no guard on a metadata
  value and no other fence. `bead-rehome.sh`'s close already rides both guards,
  set from its own read of the bead. The new `--if-status` and `--if-assignee`
  name the same two values as the landing order read them under the lock, and
  the writer compares them with its own read under the same lock, so the
  guarded close holds the landing order's judgment to the end.
- **Gas City's conditional writes.** `CloseIfMatch` and
  `CompareAndSetMetadataKey` in `internal/beads/bdstore_conditional.go` close a
  bead, or set a metadata key, only while the bead's revision still matches,
  over bd's `--if-revision` fence. They are methods of `gc`'s own store, which
  no pack script reaches through `gc bd`, and the fence needs a bd whose
  `update` and `close` take `--if-revision`, which bd v1.3.4 does not
  declare, so on the city's bd Gas City answers them with
  `ErrConditionalWriteUnsupported`.

## Why none covers the need

No primitive closes a bead because a ruling retired its PR: Gas Town's
reconcile and bd's gate both read an unmerged close as a failure for a person,
and Gas City's monitor never reads a closed PR. The change composes what the
pack already has instead: the disposition `pr-dispose.sh` records, which the old
path's reconcile (`pr-facts.sh`) already consummates the same way, and
`bead-rehome.sh`, the one writer of a close with a successor. The landing order
is where the city reads a pending PR's close, so it is where the recorded
disposition is read.

The writer's close keeps bd's guards on status and assignee, now set to what
the landing order judged. No guard covers the ruling, since bd has no value
guard on metadata and Gas City's compare-and-set needs a revision fence the
city's bd does not take. The writer therefore compares the recorded ruling on
its own read, under the record lock that `pr-dispose.sh` takes for its stamp,
so no stamp lands between that read and the close. The comparison stays in
`bead-rehome.sh` rather than in gctk, because it has to sit inside the writer's
own hold of the lock, between its read of the bead and its close, and a check
gctk made before the call would leave the window open.
