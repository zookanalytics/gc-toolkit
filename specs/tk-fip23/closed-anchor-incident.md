---
name: The 2026-08-23 stranded merge queue — what closed eight anchors, and what the repair is
description: Incident record for tk-fip23. Establishes who closed the eight anchors, corrects the bead's claim that the escalation filed nothing, and explains why the fix lands in check-set-heal's reopen arm rather than in the observer's anchorless detector.
---

# The 2026-08-23 stranded merge queue

Work record for bead tk-fip23. The bead asked for three things; this file
records what was determined about each, including the two places the bead's
filed premises turned out to be wrong.

## The incident, as verified

Eight gc-toolkit anchors were closed in a 19-second span on 2026-08-23:

| anchor | PR | closed at |
|---|---|---|
| tk-yhwfv.1 | 431 | 03:49:31Z |
| tk-vie5k | 427 | 03:49:34Z |
| tk-03wjb | 430 | 03:49:38Z |
| tk-yhwfv.2 | 429 | 03:49:40Z |
| tk-2cy79 | 426 | 03:49:43Z |
| tk-jj2ad | 432 | 03:49:45Z |
| tk-wvrga | 428 | 03:49:47Z |
| tk-mcyd1 | 425 | 03:49:50Z |

Every one carried `merge_result=pull_request`, `pr_number`, `pr_url`,
`branch`, `check_set=codex` and `check.codex=green@<oid>` — and the `<oid>`
was the PR's live head, verified against `gh pr view --json headRefOid` on
#425, #426 and #432. The operator approved all eight between 04:56Z and
05:16Z; all eight read APPROVED + CLEAN + MERGEABLE. None landed. They were
the repository's entire open-PR set, so the rig's merge queue was dead.

## 1. Who closed them (the bead's SECONDARY question)

**The refinery agent, by hand.** `tk.events` attributes every one of the
eight `closed` rows to actor `gc-toolkit/gc-toolkit.refinery`. The Dolt
commit log shows only `bd: close <id>` under the `beads` committer, which is
why the bead could not name the actor from `dolt_log` alone — the attribution
is in `tk.events`, not in the commit trailer.

The bead is right that the close reason — *"PR #<n> created (mr strategy),
checks green, awaiting human review/merge"* — appears in no pack script, no
`gc` source and no `gc` binary. It was composed by the agent. Its shape is
the tell: `mol-refinery-patrol.toml:32` says *"Stock GasTown closes at
PR-creation; this pack keeps the bead open so `closed` always means landed."*
That reason is a stock-GasTown close, written by a session that fell back to
the upstream behaviour its charter explicitly overrides.

**No instruction was missing.** The formula states the contract three times
(`:29`, `:465`, `:2068`), each time naming the gc-toolkit delta against stock
behaviour. Adding a fourth statement is the definition of an
instruction-dependent fix, and it would fail silently the same way. The
correction filed for this half is an observation bead against standing
refinery behaviour, per the feedback-observation contract; the load-bearing
fix is in code, below.

## 2. The escalation DID file a bead — the bead's premise is wrong here

The bead states: *"No bead exists for this condition (searched the whole
store, all statuses). The escalation is a log line in a pack-state file
nobody reads."*

That is not what happened. `reconcile-merged-prs.sh` mailed all eight
escalations, and they exist:

```
lx-wisp-qbsa  ESCALATION: anchorless open PR#432 (bead tk-jj2ad is closed)   05:03:08
lx-wisp-65nk  ESCALATION: anchorless open PR#431 (bead tk-yhwfv.1 is closed) 05:03:11
lx-wisp-dsi6  ESCALATION: anchorless open PR#430 (bead tk-03wjb is closed)   05:03:14
lx-wisp-g63l  ESCALATION: anchorless open PR#429 (bead tk-yhwfv.2 is closed) 05:03:17
lx-wisp-xtxc  ESCALATION: anchorless open PR#428 (bead tk-wvrga is closed)   05:03:20
lx-wisp-p69s  ESCALATION: anchorless open PR#427 (bead tk-vie5k is closed)   05:03:23
lx-wisp-f6ke  ESCALATION: anchorless open PR#426 (bead tk-2cy79 is closed)   05:03:26
lx-wisp-g2oh  ESCALATION: anchorless open PR#425 (bead tk-mcyd1 is closed)   05:03:29
```

They are **wisps**, in the `lx` store, addressed to the mayor. `bd list`
cannot see wisps at all, in any store, at any status — so a search of "the
whole store, all statuses" finds nothing and correctly concludes nothing was
filed. The escalation was durable, carried the PR, named the anchor, and
listed every closed bead naming it. It was simply invisible to the tool the
reporter searched with.

**What survives of the complaint.** Two real defects, both fixed here:

- The arm stamps `anchorless_flagged` *before* it mails and **swallowed the
  send's exit status**. A failed send left the bound in place, so every later
  pass took the "already escalated" branch — one dropped mail bought
  permanent silence, and the pass printed "routed to operator + escalated"
  while nothing was sent. Fixed by rolling the stamp back on a failed send
  (the `escalation-gate.sh` pattern), with the peer-stamp guard that pattern
  carries.
- "already escalated" said nothing about *where*. It now names the mailbox
  and warns that `bd list` cannot see it — which is exactly the search that
  produced this bead's false premise.

Filing a second, `bd`-visible escalation bead was considered and rejected:
the notice already exists and is already bounded, and a second channel for
the same condition is two records to keep in sync. The fix is to make the
existing one findable and to stop losing it silently.

## 3. Where the repair belongs (the bead's PRIMARY ask)

The bead asks the *anchorless arm* to gain a remedy. The remedy already
exists, one script over: `check-set-heal.sh` **phase 0a**
(closed-but-not-landed, tk-vnlll) reopens a closed anchor whose PR is still
open, and carries every guard such a repair needs — ambiguity, incumbent
anchor, operator holds, `tracking_only`, PR-identity certification, and a
two-stage flap marker. Duplicating that into the observer would mint a second
writer for one repair.

It did not fire because its signature required `merge_result` **absent**:

> A closed bead carrying **any** merge_result has a disposition recorded by a
> pass that knew what it was doing, and is left alone.

That is true of `merged`, `abandoned` and `retargeted`. It is false of
`pull_request`, which is not a disposition at all — it is the refinery's
in-flight handoff marker, and the exact value `merge-skill.sh`'s gating
enumeration keys on because it means *still to do*. `pre_open_gate` is the
same kind of fact one step earlier.

So `merge_result` spells a **handoff** and a **completion** with one key, and
the arm read the handoff spelling as the completion spelling. This is the
pathology tk-16f29 was opened about, one layer down: there `gc.takeaway` meant
both "waiting on X" and "done, needs nothing", and the second reading muted the
stall detector. A state that encodes a handoff must not be spelled the same way
as a state that encodes completion.

**The fix** narrows the test from "merge_result present" to "merge_result is a
*disposition*", written as an allow-list of the non-terminal spellings —
absent, `pull_request`, `pre_open_gate` — so that a marker no pass here knows
reads as a disposition and is left alone. An allow-list is what keeps the
widening fail-closed; a deny-list of the known terminal values would reopen a
bead wearing a marker invented later.

Reopening lands nothing by itself. It restores the bead's visibility to the
merge skill, which then re-evaluates approval, mergeability and `check.*` at
the live head on live state. For the eight anchors that is a no-op check —
their `check.codex` already pins the live head — so they land on the next
pass.

## What was NOT changed, and why

- **No landing from the observer.** `reconcile-merged-prs.sh` is detect-only
  by charter and its tests pin that (`INV`: it never calls `gh pr merge`).
  Giving it merge authority to fix a visibility bug is the wrong layer.
- **No prompt edit for the refinery's close behaviour.** See §1: the
  instruction already exists three times over. Filed as an observation.
- **No hand-landing of the eight PRs.** They are the operator's to merge, and
  the repair arm reopens their anchors on the next refinery pass regardless.
  This work is itself a PR in the same stranded queue — the self-sealing
  property the bead names — so the first landing still needs one human action.
