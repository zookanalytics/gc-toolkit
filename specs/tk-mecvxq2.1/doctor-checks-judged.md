---
name: Every doctor check and standing doctor failure, judged
description: For A clean doctor (tk-mecvxq2), as of 2026-11-26, keep, fix or remove for each doctor check the pack ships, and for each doctor tracker open in the gc-toolkit store, whether it names a live problem and what clears it. Read it to rule on the proposals, or to find why a check stays.
---

# Every doctor check and standing doctor failure, judged

This document proposes one outcome for each of the 24 doctor checks the pack
ships, and for each of the 27 doctor trackers open in the gc-toolkit store, for
A clean doctor (tk-mecvxq2). It builds nothing. Once the operator approves it,
each fix and removal is filed as the epic's work, and each tracker it proposes
to close is closed.

The proposals:

- Remove `check-cadence-live`, `check-claim-advancing`, `check-config-bound`,
  `check-cycle-recycle-hook`, `check-epic-closed-implies-ruled`,
  `check-hq-marooned-work`, `check-session-store-scope` and
  `check-step-terminal`. The operator ruled the store-scope check's removal on
  2026-11-25. Each row in the first table says what covers the check's fault
  instead, or what goes uncovered.
- Fix `check-blocked-work-armed`, `check-demo-toolchain`,
  `check-po-queue-only` and `check-wait-is-an-edge`. All but the demo
  toolchain's fix are already placed.
- Keep the other nine checks, each with its reason in its row. Three more
  retire with the deletion plan and get no work here.
- Accept Gas City's `dolt-noms-size` warning in `doctor/accepted.toml`, which
  also hides its 20 GB error. The entry works around a Gas City check, so the
  change that adds it carries the record AGENTS.md asks of an accommodation,
  with a gascity bead for the fix at the source.
- Close the trackers whose finding no longer fires.

The removals and the three retirements take 53 s of the 129 s the pack's checks
add to each doctor run. No proposal adds a check, a mode or a key, so none
carries a Gas City search.

## How each column was measured

- **Fired.** The doctor order's 137 hourly runs from 2026-11-19T23:24Z to
  2026-11-25T23:08Z, each recorded as a `gc-toolkit.doctor.ran` event
  (`gc events --type gc-toolkit.doctor.ran --since 168h`). A check fired in a
  run when that run's event lists it as failing.
- **Run time.** Each check's `run.sh` at main fe028fe64, run alone and one
  after another at about 2026-11-26T00:00Z, in the environment Gas City gives a
  pack check, at a load average of 26 to 37. The 24 took 129 s together. Gas
  City runs doctor checks one after another (`Run` in
  `internal/doctor/doctor.go`), so each check's time adds to every doctor run.
  A whole run at 00:04Z took 158 s, and the week's runs took 103 to 389 s, with
  a median of 149 s. Two doctor runs start each hour, the doctor order's and the
  deacon's sweep, which tk-1tfzr71.174 retires.
- **Live today.** A `gc doctor --json --verbose` run at 2026-11-26T00:04Z.
- **Last real catch that led to a fix.** A finding that named a real fault in
  the city, followed by a change or a repair by hand that removed it. A fix to
  the check itself is not a catch. It is read from the 179 doctor trackers the
  store has held (found by metadata `finding.key`), their notes, the doctor
  cleanup of 2026-11-24 (tk-felrt44) and git history.

## The pack's checks

| Check | Catches | Last real catch that led to a fix | Cost | Proposal |
|---|---|---|---|---|
| `check-armed-dispatch-owed` | An armed bead the deferred-dispatch order should have started, still armed past the order's cadence window. | 2026-09-29: the order's pass overran its budget, so no arm fired (tk-gy90ha), fixed by d4877ccf1 (#890). That code was deleted when arms moved into gctk on 2026-11-14, and no tracker since 2026-10-04 has named a fault. | 8.4 s. Fired in 0 of 137 runs. | Keep. An arm left unsent strands blocked work with no other signal, and the check reads the start's own dry run, so it holds no rule of its own. Its warrant in `docs/warrants.md` retires it once Gas City holds a poured workflow until its input is ready. |
| `check-blocked-work-armed` | Blocked work with no route and no arm, which nothing dispatches once its blocker closes. | 2026-11-24: 40 of its 44 findings were blocked beads nothing would dispatch, armed by hand (tk-felrt44). The validating closer, which left some of them, is being fixed (tk-6khs329). | 6.8 s. Fired in 136 of 137 runs. At 00:04Z, 9 of its 10 findings were review asks, which are not pool work. | Fix. It reports a review ask that waits on a bead and tells the reader to arm it, which would start a second worker on the PR's branch. tk-5yx20h6 carries the fix. |
| `check-cadence-live` | A pack order with no live registration, or one that has not fired within its cadence window. Two more arms report a deployed gctk binary that is missing or built from other sources than the checkout's, and flock(1) missing, which refinery-reconcile's pass lock needs. | 2026-11-24T05:30Z: refinery-reconcile had not run since a host crash left its tracking bead open, cleared by hand (tk-b6hthse). Gas City's `order-firing-current` reported stale orders in the same run. The last catch that led to a code change was 2026-10-02 (#949). | 15.7 s, the second most costly. Fired in 2 of 137 runs: that stall, and a broken pipe in the check itself. | Remove. Gas City's `order-firing-current` judges every scheduled order, the pack's included, and its `order-dispatch-floor` covers the cadence floor this check computes. Its `order-outcome-healthy` reports an order that fails three runs in a row, as refinery-reconcile does without flock and pr-reconcile does without a gctk binary. Two faults go uncovered: a pack order that never registers at all, and a gctk binary left behind its sources by a build that keeps failing. gctk-build is a condition order, and `order-firing-current` and `order-outcome-healthy` judge only cron and cooldown orders. |
| `check-claim-advancing` | A step nothing is running: its holder is dead, missing or stalled, or it sits unclaimed while an idle session could take it. | 2026-08-27: 23 steps in progress with no assignee, swept and retired by hand (tk-d0j3r7). No catch since has led to a fix. | 11.0 s. Fired in 17 of 137 runs, each on nothing wrong: the holders of the claimed steps it named were working, and the unclaimed steps were claimed later. | Remove. Gas City's work ladder nudges and escalates a claim that stops advancing, and escalated both steps this check named this week. Core's orphan-sweep resets a dead holder's claim every five minutes, and `pool-idle-routed-work` asks the unclaimed arm's question. The target design makes the molecule checks one (`docs/built-once-target.md`, Doctor), and `check-root-advancing` is the one this leaves. |
| `check-closed-implies-landed` | A closed PR anchor whose PR has not landed, or a landed one with no merged sha. | 2026-10-18 to 10-24: eight anchors closed by hand without the successor pointer it accepts, recorded by hand on 2026-10-26 (tk-8a0dcw). The last that led to a code change was 2026-09-03 (tk-f90c80, #1132). | 11.7 s. Fired in 0 of 137 runs. | Keep. A bead closed while its PR is open loses the work with no other signal, and nothing else reads a closed anchor against its PR's record. |
| `check-config-bound` | A prompt template, fragment or overlay directory in the resolved config that does not resolve, or a rig-scoped order registered with no rig. | None it drove. Its one real finding, a city config that would not load on 2026-09-18, had been reverted by hand six minutes before it fired (tk-anylyj). | 2.1 s. Fired in 0 of 137 runs. | Remove. Gas City's `config-refs` reports a prompt template or overlay directory that does not exist, and `gc lint`, which `tools/lint.sh` runs on every change, reports a fragment that does not resolve. Its order-scope arm has no Gas City equivalent and has never fired. |
| `check-cycle-recycle-hook` | The roles carrying the cycle-recycle overlay differ from the roles whose prompt forbids a consent prompt. | None found since it was first added on 2026-06-25. | 0.5 s. Fired in 0 of 137 runs. | Remove. It reads only the pack's own files, which change only by a landed commit, so if the pairing is still wanted, a test of those files holds it at every change. The roles are changing: the deacon retires with tk-1tfzr71.174, and tk-1tfzr71.242 may drop the refinery's recycle. |
| `check-demo-toolchain` | A demo capture's toolchain not in place: Node, ffmpeg, gh, sandbox-exec, the narration key and the Vercel bypass key. | 2026-10-18: the narration key did not reach sessions, so captures would be silent, fixed by hand (tk-602zp5e). On 2026-10-08 ffmpeg was missing on the new host, and was provisioned (tk-saq1lg6). | 1.0 s. Fired in 137 of 137 runs, each on nothing wrong. The doctor order's environment lacks the two keys that sessions carry, and the check reads OK in this session and in the deacon's sweep. | Fix. Drop the two key items, which judge the environment of whatever runs the check rather than a session's, and keep the host items. A key that stops reaching sessions then shows only as a silent capture. |
| `check-epic-closed-implies-ruled` | A closed epic with no close ruling and outcome, and no disposition onto a successor. | None found. Its one tracker was budget overruns, and no epic was found closed without its ruling (tk-f1ouz56). | 2.5 s. Fired in 0 of 137 runs. | Remove. `finalize-gate.sh` refuses that close when it is made, which leaves only a raw `bd close` uncovered. |
| `check-feedback-routing-owed` | An open PR anchor whose operator review was stamped and never routed. | None it drove. Its two real findings, on 2026-09-28 and 2026-10-06, had each been found first another way. | 8.4 s. Fired in 0 of 137 runs. | No work here. tk-1tfzr71.21 retires it, and has already deleted it on its integration branch. |
| `check-gate-integrity` | An open gating anchor with no check_set. | 2026-08-26: a malformed gate marker held an anchor silently, fixed by eb68ab34f (#489), in a clause removed on 2026-10-15. The check_set clause that remains has led to no fix. | 2.3 s. Fired in 0 of 137 runs. | No work here. tk-1tfzr71.122 retires it. The reader it protected, `merge.sh`, was deleted on 2026-11-20. |
| `check-gate-marker-provenance` | A lane derived green from a closed review whose outcome no writer recorded. | 2026-09-02: green lanes with no review behind them on two PRs (tk-vnk6ai), fixed by 0b44ad5f5 (#606), in an arm removed on 2026-10-15. | 2.3 s. Fired in 0 of 137 runs. | No work here. tk-1tfzr71.122 retires it. Two of the readers it protects, `merge.sh` and `pr-open.sh`, were deleted on 2026-11-20. |
| `check-hq-marooned-work` | Open, unassigned work in the city's own store, which no pool reads. | None it drove. Its one real catch, on 2026-10-03, was a duplicate, closed on the operator's ruling with no fix (tk-3pvm3m). | 0.9 s. Fired in 0 of 137 runs. | Remove. Of the city-scoped roles it was built for, the dog is gone, the deacon retires with tk-1tfzr71.174, the city runs no mayor and the po now runs per rig. A bead the mechanik files without a rig goes uncovered. |
| `check-one-anchor-per-pr` | Two or more open beads owning the same PR. | 2026-08-31: PR #522 had two open anchors after a rework hand-back, fixed by 4b937d397 (#550). | 2.3 s. Fired in 0 of 137 runs. | Keep. A PR has one owning bead, whose record the landing order acts on, so a second open anchor is a bead nothing lands or closes. |
| `check-po-queue-only` | Anything reaching the po other than its queue of held new work. | None yet. It was added on 2026-11-09, and its findings of 2026-11-23 cleared with no fix (tk-t8zihzz). Since 2026-11-24 it has reported a real fault: the po's hold written over a gascity bead's older dispatch arm (tk-pxbnhjl), whose fix waits on #1710. | 8.7 s. Fired in 46 of 137 runs, at error. | Fix. A held bead has no arm under the intake rule in `docs/steering.md`. The check's message names two ways an arm comes to sit under a hold, a placement that stopped before its lift and an arm set while the bead was held. It leaves out the way its live finding came about, a hold written over an older arm. tk-pxbnhjl adds that cause to the message, and makes the po's and the work skill's holds disarm first. |
| `check-pour-text-current` | A rig checkout behind its remote, or one whose fetch has failed, so runs pour stale pack text. | 2026-11-11 to 11-16: three rigs' checkouts could not fast-forward, cleared by hand on 2026-11-16 and 11-17 (tk-edah4kz). The reconciler's own bead and `check-recycle-capable` reported it too. | 1.4 s. Fired in 16 of 137 runs, mostly from the arm about poured runs that #1700 removed on 2026-11-25. | Keep. The pack each rig runs is its checkout, and a checkout whose fetch fails runs stale text that nothing else reports, since the reconciler reports only a checkout it cannot fast-forward. |
| `check-recycle-capable` | The cycle-recycle Stop hook unable to fire: not wired, unable to measure, or held off by a refinery's git-op guard latched past a day. | 2026-11-12: three rigs' refineries could never recycle, because a tracked file that Gas City rewrites latched their guard. Fixed in each rig's repository and landed on 2026-11-17 (tk-cfz4ep). | 1.9 s. Fired in 0 of 137 runs. | Keep. The hook exits 0 on every uncertainty, so a recycle that can never fire looks like an idle one from outside, and only this check tells them apart. |
| `check-root-advancing` | A started molecule that stopped, whose frontier no session holds and no route reaches. | 2026-09-27: three first-reaction runs stranded mid-run (tk-osdwdw), fixed by 2026-10-10 through tk-gkb81g and #942. That bead was filed a day before the check fired. | 4.7 s. Fired in 0 of 137 runs. | Keep. A stranded root advances no further and nothing re-offers it, no Gas City check covers it, and #1564 relies on this check to report a pour whose session died. It is the one molecule check the target design asks for. |
| `check-seed-audit-current` | `generated/seed-audit/` missing, or the pre-commit hook that regenerates it not wired in the rig's checkout. | 2026-10-08: the host move left the hook unwired. It was wired by hand on 2026-10-26, and the city's setup now installs it (tk-b6lnaw). | 0.2 s. Fired in 0 of 137 runs. | Keep. A checkout that loses its hook wiring, as one did in the host move, commits without regenerating the audit, and this check is the one place that cause shows. |
| `check-session-store-scope` | A live agent whose store environment names another rig's store. | None found. Every tracker was the check's own misread, and for about three weeks it read no agent on macOS. | 3.0 s. Fired in 4 of 137 runs, all on 2026-11-24, each a partial read. In the doctor order's runs it reads no agent at all, because it reads tmux's default server and not the city's. | Remove, as the operator ruled on 2026-11-25. tk-1tfzr71.245 deletes it (PR #1713). |
| `check-state-space` | An open bead whose merge_result is a value no pack writer writes, or a live bead still carrying a key the registry retired. | 2026-08-31: the PR #522 case in the row for `check-one-anchor-per-pr`, fixed by #550. Its latest finding, retired keys on open beads on 2026-11-01, was cleared by a migration already planned. | 5.4 s. Fired in 0 of 137 runs. | Keep. An anchor state no writer knows is a merge nothing acts on, and the check is how a metadata migration shows it is done, as the cut-over of 2026-11-08 did. |
| `check-step-terminal` | A step still offered under a closed molecule root, where it would run against a dead molecule, or one stalled past 48 hours under an open root. | 2026-09-15: steps left open under four closed molecules, which a later read found inert (tk-t6023b), cleared by the dispose sweep that #942 extended. No catch since 2026-09-16. | 4.6 s. Fired in 0 of 137 runs. | Remove. The closes that left those steps open stopped when stopping a run moved to Gas City's run cancel, which closes every unfinished step (#1249), and each finding since has been a misread. A step left offered under a root someone closes with a raw `bd close` goes uncovered. |
| `check-wait-is-an-edge` | A live bead with a hold marker and no pending wait edge of its own. | 2026-09-15: `gc-helm.sh` let a takeaway park a bead on prose alone, fixed by e34412804 (#732). Its last drain, on 2026-11-24, wrote no edge: none of its 33 findings waited on live work, and clearing them meant holding 15 beads for their po and rewriting 29 headlines (tk-felrt44). | 21.2 s, the most costly. Fired in 106 of 137 runs. | Fix. It reports a bead held for placement once the wait its headline names has landed, so its findings come back after every drain. tk-snd449h carries the fix. tk-1tfzr71.216 would also drop `gc.takeaway` from its markers. |
| `check-wisp-cascade-intact` | A bead store whose wisp tables lack their ON DELETE CASCADE foreign keys. | 2026-09-03: the city's own store lacked all four keys, a fault found just before the check shipped with its fix (#610). The check reported the store every cycle until it was repaired by hand with the operator's approval (tk-w5xn9d). | 2.4 s. Fired in 0 of 137 runs. | Keep. Gas City's bd-schema check reads the migration records, which on that store said the migration had applied, and the refinement of 2026-11-23 closed the upstream migration bug as covered by this check (tk-fgr3xi). |

## The open doctor trackers

Live today means the finding fires in the doctor run of 2026-11-26T00:04Z.
Each row proposes one of the epic's four outcomes: fix the cause, fix the
check, remove the check, or Gas City's own with the gascity bead that carries
the fix. Some rows need one of two outcomes the epic did not list. Close is for
a tracker whose finding no longer fires: if it fires again, the patrol files a
new tracker, which is the signal the epic wants. Accept is for a Gas City check
this city cannot clear.

| Tracker | Check | Live today | Proposal |
|---|---|---|---|
| tk-2yyrn4 | `check-blocked-work-armed` | Yes. Of its 10 findings, 9 are review asks that wait on a bead, which the PR's review run takes once that bead closes. 1 is a bug in another rig's store with no route and no arm. | Fix the check: tk-5yx20h6. |
| tk-ez2kgo | `check-cadence-live` | No. It fired twice this week, both on 2026-11-24: the stall after the host crash, which Gas City's `order-firing-current` also reported, and a broken pipe in the check. | Remove the check. |
| tk-g1u9js | `check-claim-advancing` | No. It last fired at 2026-11-25T19:38Z in the deacon's sweep, and this week's findings named working sessions and steps that were claimed later. | Remove the check. |
| tk-9le3q2n | `check-closed-implies-landed` | No. Its one occurrence, 2026-11-24T04:06Z, was the check running out of time at a load peak. Run alone, it passed in 8 s. | Close it. |
| tk-htfltge | `check-gate-integrity` | No. Its one occurrence, 2026-11-24T04:07Z, was a timeout. Run alone, it passed in 3 s. | Close it. The check gets no work, because tk-1tfzr71.122 retires it. |
| tk-1kb14e | `check-gate-marker-provenance` | No. Its 41 occurrences were a stale read on 2026-09-16 and then timeouts, the last on 2026-11-24. | Close it. The check gets no work, because tk-1tfzr71.122 retires it. |
| tk-pxbnhjl | `check-po-queue-only` | Yes. Its one finding is a gascity bead the po held for placement over a dispatch arm six weeks older than the hold. A held bead has no arm under the intake rule, and the hold instructions the po follows do not disarm first. | Fix the cause: this bead makes the po's and the work skill's holds disarm first, and adds that cause to the check's message. It waits on tk-uki5019 (PR #1710), which rewrites the same hold lines. The gascity bead itself is the gascity po's to place or disarm. |
| tk-utr04p | `check-pour-text-current` | No. This week's findings were mostly the arm about poured runs that #1700 removed on 2026-11-25, and one checkout not refreshed on 2026-11-24. | Close it. The check stays. |
| tk-t6023b | `check-step-terminal` | No. It last fired on 2026-11-09, on a run parked behind an open gate, which 7ed46e378 stopped reporting that day. | Remove the check. |
| tk-t1xvt2 | `check-wait-is-an-edge` | No. It fired in 106 of the week's runs, the last at 2026-11-25T20:06Z, and its findings come back after each drain. | Fix the check: tk-snd449h. |
| tk-r05k0v | `agent-sessions` | Yes, and its list is the pools and per-conversation templates that run only when there is work or a sitting (gc-ji8u6z's reading). | Gas City's own: gc-ji8u6z, held for placement. |
| tk-cxvk1y | `agent-token-telemetry` | No. The running gc has no such check: none of the 223 results at 00:04Z names it. It last fired at 2026-11-24T01:09Z. | Close it. |
| tk-ws070gq | `codex-hooks-drift` | Yes. Six managed Codex hook files in the Codex polecats' homes need an upgrade. | Gas City's own: gc-und66b, which waits on gc-6qxw2v, parked since 2026-11-13. |
| tk-ey1cpsq | `config-semantics` | Yes, and nothing is wrong. All 42 warnings are the converse templates setting idle_timeout "0" beside sleep_after_idle on purpose: with the timeout off, the sleep applies. | Gas City's own: gc-p993jw, held for placement. |
| tk-71n2il3 | `dolt-compact-state` | Yes. Four stores carry a pending-GC marker from 2026-11-24, because the compactor skips the full GC on a store with live sessions, so its next pass never clears the marker. | Fix the cause: tk-0bxcur0, the call on whether this city runs Dolt GC on stores with live sessions. |
| tk-0k49i9 | `dolt-noms-size` | Yes, and nothing the city does clears it. The largest store is 4.00 GB against a fixed 2 GB line, and what the stores keep after a full collection is already over it (tk-pado8uq). | Accept it in `doctor/accepted.toml`, tk-pado8uq's option 1. The entry also hides the check's 20 GB error. Gas City sets both lines as constants (`doltNomsWarnBytes` and `doltNomsErrorBytes` in `internal/doctor/checks.go` at 77143ecd18), and gives bloat that a full collection reclaims as their reason (`docs/troubleshooting/dolt-bloat-recovery.md`), which does not hold for stores still over the line after one. So the change that adds the entry carries AGENTS.md's record for an accommodation, with the fix at the source filed in the gascity rig, where no bead carries one yet. |
| tk-2emcyj7 | `executor-identity-residue` | No. It passes, and last fired on 2026-10-24. | Close it. |
| tk-050xux | `nudge-unconfirmed` | Yes. Of its 23 sessions, live working ones are flagged, the session that wrote this document among them. gc-3c4m0k found the log is written for nudges that were delivered and is never cleared. | Gas City's own: gc-3c4m0k, held for placement. |
| tk-lktfavr | `order-dispatch-floor` | No. It has passed since the city raised its order dispatch budget to 96 a pass at 2026-11-24T04:13Z (tk-0y8qrgf). | Close it: its cause was fixed. |
| tk-ou35ed | `order-firing-current` | Off and on: it fired in 10 of the week's runs, the last at 2026-11-25T23:08Z, and was OK at 00:04Z. Its recent findings name gate-sweep and dolt-health, which have a 30 s cooldown and ran 60 s apart in their last eight runs. Since the budget change the check calls them overdue once 45 s have passed. | Gas City's own, with no bead yet: file one in the gascity rig, for the check or for the scheduler that runs a 30 s order every 60 s. This cause is read from the order history and the check's code (`classifyOrderFiring` in `internal/doctor/checks_order_firing.go`), and not yet tested. |
| tk-ascz5ab | `order-outcome-healthy` | Yes. mol-dog-compactor has failed 18 passes in a row: it skips the full GC on a store with live sessions and exits non-zero. | Fix the cause: tk-0bxcur0. |
| tk-2lor8sg | `order-tracking-retention` | No. It fired in 7 of the week's runs. Its first reaction read retention as current, and the check as counting the beads a 7-day retention keeps against a fixed 500. | Gas City's own, with no bead yet: file one in the gascity rig. |
| tk-dysptt | `pool-idle-routed-work` | Yes, and nothing is wrong. None of the 63 beads it counts in 3 pools can be claimed: 59 workflow-finalize beads wait on their steps, and the 4 routed to the mechanik each wait on an open blocker. | Gas City's own: gc-pu8i98, held for placement. |
| tk-ujz8d10 | `skill-dangling-sink` | No. It passes, and last fired on 2026-11-11. | Close it. |
| tk-a7qhii | `v2-routed-to-namespace` | No. It passes, and last fired on 2026-10-24. | Close it. |
| tk-b7kehx | `worktree-disk-size` | No. It has passed since the cleanup of 2026-11-24 removed 582 homes of closed conversations (tk-felrt44). Before that it warned in 80 of the week's runs and timed out in 22. | Fix the cause: tk-6lctp3w, which turns on for the conversation agents the setting gc-7jt7fb adds to Gas City, so a sitting's home is removed when its session closes. It waits for the gc build that carries the setting. |
| tk-1vdtaza | none: the deacon's doctor sweep did not complete | No. Deacon restarts killed two sweeps, the last on 2026-11-18. | Close it. The sweep retires with tk-1tfzr71.174, and the doctor order records every run it makes. |

## Counts

- The checks: 9 kept, 4 fixed, 8 removed, and 3 retired by the deletion plan
  with no work here.
- The trackers: 10 closed, 2 cleared by fixing their check, 3 by removing their
  check, 4 by fixing their cause, 1 accepted, and 7 Gas City's own. Two of the
  seven have no gascity bead yet, and are filed with the epic's work.
