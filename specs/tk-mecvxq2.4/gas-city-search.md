---
name: Gas City search for accepting the dolt-noms-size warning
description: The record AGENTS.md asks of a change that accommodates Gas City, for tk-mecvxq2.4's dolt-noms-size entry in doctor/accepted.toml. It covers the settings searched for, the reason Gas City gives for the check's fixed 2 GB and 20 GB lines, that reason tested against this city's stores, and the fix at the source with the finding that carries it. Read it to judge the entry, or to take the entry out once Gas City lets a city set the lines.
---

# Gas City search for accepting the dolt-noms-size warning

Gas City is read in a checkout of `gastownhall/gascity` at 77143ecd18
(2026-11-25T23:01Z) and at main 6dce31bbb6 (2026-11-27T05:51Z). A path with no
repository named is Gas City's. The gc the city runs, 1.4.3 built on
2026-11-26, carries the same constants. Each measurement below says what was
counted, how and when.

## The behavior the entry accommodates

The `dolt-noms-size` check (`DoltNomsSizeCheck` in `internal/doctor/checks.go`)
measures each managed Dolt store's `.dolt` directory with `du -sk`. It warns
when the largest store, or the sum of all the stores, reaches
`doltNomsWarnBytes`, which is 2 GiB, and errors when either reaches
`doltNomsErrorBytes`, which is 20 GiB. Both are constants, at lines 2002 and
2003 at 77143ecd18 and at 6dce31bbb6. The check, the constants and the recovery
guide below came in one commit, 885d07c223 (gastownhall/gascity PR #1132).

The entry names the check, and `gctk doctor run` accepts a failing result by
its name whatever its status (`measure` in `services/gctk/doctor/doctor.go`).
So the entry hides the 20 GB error as well as the 2 GB warning.

## Searched

- **A setting for the two lines.** `DoctorConfig` (`internal/config/config.go`)
  lets a city set the worktree size lines, `worktree_rig_warn_size` and
  `worktree_rig_error_size`, which `WorktreeRigWarnBytes` and
  `WorktreeRigErrorBytes` read. It holds nothing for this check, and the check
  reads no environment variable for its lines. Not covered.
- **A way to quiet one check.** `gc doctor` takes `--fix`, `--verbose`,
  `--json`, `--check-timeout` and `--check` (`newDoctorCmd` in
  `cmd/gc/cmd_doctor.go`), and none of them mutes a check or sets a line. Not
  covered.
- **The check's skip.** The check reads OK as skipped when `GC_DOLT=skip` is set
  or the city's stores are not managed and local (`managedDoltOpsCheckSkip` in
  `cmd/gc/cmd_doctor.go`). That skip covers every managed Dolt check, the ones
  that report a failing collection among them, so it hides far more than this
  check. Not covered.

So the city rules the warning accepted in the pack's accepted file, as it does
for `hold-label-routed-to` and `dolt-compact-state`
([tk-1tfzr71.158's search](../tk-1tfzr71.158/gas-city-search.md#doctoracceptedtoml)).

## The reason Gas City gives, tested here

Gas City gives its reason in `docs/troubleshooting/dolt-bloat-recovery.md`
(77143ecd18). Dolt reclaims chunks only by garbage collection, so a store that
bloated once "sits at its peak size indefinitely". The guide's recovery is a
full GC, after which "dolt-noms-size should now be OK". So the lines stand for
bloat that a full collection reclaims.

That reason does not hold for this city's stores. Measured on 2026-11-28:

- **Every run warned.** The doctor order records each hourly run as a
  `gc-toolkit.doctor.ran` event. All 164 completed runs from 2026-11-21T02:37Z
  to 2026-11-28T08:35Z (`gc events --type gc-toolkit.doctor.ran --since 240h`)
  list `dolt-noms-size` as failing, at warning. In those runs the largest
  store's lowest reading was 3.15 GB and its highest 6.56 GB.
- **The sizes now.** `du -sk` of each store's `.dolt`, as the check measures
  it, at 09:06:56Z: this rig's store held 5.66 GB, the city's HQ store 5.59 GB,
  and the other five stores 2.07 GB together, 13.32 GB in all. The figures are
  GiB, which the check prints as GB.
- **What a collection leaves.** Dolt 2.7.7 ran `dolt gc --full
  --archive-level=0` from 09:18Z to 09:21Z on APFS clones (`cp -c`) of the two
  largest stores, so the live stores were not touched. It took this rig's store
  from 5.64 to 5.22 GB. That store holds 26,263 commits, and a full GC keeps the
  chunks of every one. It took the HQ store from 5.66 to 3.34 GB. That store
  holds 1,630 commits, because Gas City's compactor flattened it at
  2026-11-24T03:38Z, the date of its flatten commit, and the full GC that
  follows a flatten has not run on it since. On a second clone of this rig's
  store, Gas City's flatten followed by the full GC left 2.74 GB. The flatten
  ran `DOLT_RESET('--soft', <root commit>)` and then `DOLT_COMMIT('-Am', ...)`.
  That is the flatten `examples/bd/dolt/commands/compact/run.sh` runs on this
  store, because it resets to the commit the store's `gc-compact-base` tag
  names, and this store's tag names its root commit.

So even the most Gas City's compaction does to these two stores leaves each over
the 2 GB line, and the warning cannot clear while the stores keep what they
keep. A store kept under the line would have to hold less than these stores
hold now, which is a design of its own. The operator accepted the warning
instead, in the ruling the entry names.

The 20 GB line keeps its meaning here, and the entry hides it. Gas City's
compaction runs no full GC on a store that sessions are connected to, a gate
the upstream finding tk-z17uh59 records. Its compactor has run no full GC on
either of the two largest stores since its pass at 2026-11-24T03:38Z. Each
store's pending-GC marker, which the compactor clears only once that GC runs,
has stood in every hourly doctor run since 04:11Z that day
(`dolt-compact-state`). On 2026-11-28, `order-outcome-healthy` counted 45
failed compactor passes in a row, the last of them skipping the GC on both
stores for connected sessions. The daily reclaim's log shows the GC skipped on
both the same way at each pass from 2026-11-24 to 2026-11-27. In that time this
rig's store grew from 3.28 GB, which the reclaim's log read at
2026-11-24T20:55Z, to 5.66 GB, about 0.7 GB a day. While the entry stands, the
doctor still reports the collection it lacks: `order-outcome-healthy` lists the
compactor's failed passes, and `dolt-compact-state` lists the full GCs owed.

## The fix at the source

In the sitting that accepted the warning, on PR #1726 on 2026-11-28, the
operator said: "Noms I get, although I still think it's overly aggressive on
the Gas City side without a good means to either adjust or to give more insight
into where the 2GB is going." The sitting read the sentence as two asks, and the
reading is the sitting's. Gas City gives a city a way to set the warning and
error lines, and the check says where a store's size is going.

The shape Gas City already uses for the worktree lines fits the first ask: two
`[doctor]` keys, parsed the way `worktree_rig_warn_size` is and defaulting to 2
GB and 20 GB, which the check reads through `NewDoltNomsSizeCheckForConfig`,
since that constructor already receives the city's config. For the second, the
check's details give each store's chunk journal, newgen table files and
`oldgen`. The two largest stores show why the split matters. At 09:13Z, `du
-sk` read this rig's 5.67 GB as 5.61 GB of `oldgen` and a 0.06 GB journal.
`oldgen` holds the chunks a collection kept. By the clone runs above, about
2.5 GB of them are history that only a flatten drops, because a full GC kept
5.22 GB of the store and the flatten followed by a full GC left 2.74 GB. At the
same time, `du -sk` read the HQ store's 5.62 GB as a 2.22 GB journal, 3.33 GB of
newgen table files and 0.08 GB of `oldgen`. The check's message reports only
the total. The fix is tens of lines and their tests.

The upstream finding tk-qqyuqwz carries both asks, in the operator's list of
upstream findings. Once a Gas City build that holds them runs here, the entry
comes out, and the city sets its own lines in `city.toml`.
