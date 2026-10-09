---
name: conflicting-pr-unengaged-threads-root-cause
description: Why PR #1117's operator review went unrouted after its branch took a merge-in, what of that gap survived on main, and why the fix routes unengaged review threads before the conflict arm acts.
---

# PR #1117: operator review threads unrouted across a merge-in

## What happened

The operator ran a code review of PR #1117 (anchor tk-88bhv5o) from a Claude
Code session that posted under the city's account, `zook-bot`. GitHub's record
of the PR shows two COMMENTED reviews at head `e0867966`: a nit at
18:23:21Z and three change requests at 18:25:03Z, each an inline thread, none
carrying a city mark.

The anchor recorded `pr_posture=commented@e0867966…@2026-10-06T18:28:54Z`, so
the posture pass saw the threads and held the merge. Nothing routed them. The
PR had conflicted with main since #1108 landed at 16:02:54Z; the merge-in's
notes name #1108's edit to `formulas/mol-refinery-patrol.toml` as the
conflict. At 19:04:10Z pr-facts' conflict arm filed the merge-in rework
tk-q6zi78e, under that arm's own title. Its polecat merged main in as
`72eda24d` at 19:08 and wrote in its notes that the three threads were
"outside this merge-in and nothing tracks them yet". At 19:14 the operator
asked why the PR was moving slowly (visit tk-bkltj9c). That conversation found
the review unrouted and hand-filed the rework tk-2gzxix4, which answered the
threads.

## Mechanism

Read against `assets/scripts/pr-facts.sh` as it stood on main during the
incident (commit `02522b0c`).

1. **The review was not arm-7 feedback.** Arm 7 counted only posts under a
   login other than the city's, so `unanswered` stayed 0.
2. **The unengaged-thread backstop caught it.** `unengaged_holds` found
   unresolved threads holding unmarked city-login comments, every check lane
   green and nothing in flight. It set `UT_COUNT` and folded the posture into
   `commented`. That is the 18:28:54Z posture. Every post on the PR at that
   head was the city login's, so no arm-7 batch could have set it.
3. **The visit that hold stands for is filed at the tail of the full pass.**
   That arm sat after the CONFLICTING arm. On a full pass with no unanswered
   batch, every path through the CONFLICTING arm ends the anchor's visit with
   `continue`. The early routing pass stopped before the arm. While the PR
   conflicted, the arm that files the visit never ran.
4. **The CONFLICTING arm read only `unanswered` as feedback owed.** Its gate
   was `[ "$unanswered" != 1 ]`. The `commented` posture had two causes, and
   the arm saw one of them. With `unanswered=0` it filed the merge-in child.
   A merge-in child brings the branch current and answers nothing.
5. **The live merge-in child then suppressed detection.** The backstop's
   first-detection path stands down while any live bead carries
   `anchor_bead=<anchor>`, on the premise that such a child owns the
   follow-up. A merge-in child does not.

Steps 3 and 4 are the defect. Step 5 is a delay, not a loss. Once the child
closes, the next read at the new head finds nothing in flight and files the
visit.

### What the record cannot settle

The conversation read the posture as `commented@e0867966` after the merge-in
closed at 19:18, with the head at `72eda24d` since 19:08. Every completed run
of the posture code predicts a write in that window. While the merge-in was
live it predicts a posture other than `commented`, from step 5. After the
merge-in closed it predicts `commented@72eda24d`. So no posture write landed
for this anchor between 19:04 and that read. That fits a pass that did not
reach the anchor, or a read that failed and left the standing `commented` in
place. The incident window's evidence does not survive on this host. The city
event log starts 2026-10-06T23:54Z, the refinery pass log holds only recent
passes, and the anchor's history in the bead store starts 2026-10-08T09:43Z.
So this is not asserted. Pass starvation was addressed separately (#1145).

## The two questions the bead asked

**Does a head move invalidate the owed or unengaged read?** Arm 7's read does
not move with the head. Its watermarks are review and comment ids. The
unengaged read is keyed to the head: `pr_unengaged_threads=<head>` and the
visit key `pr-unengaged-threads.<pr>.<head>`. So a push re-runs detection.
While any bead carrying the anchor's `anchor_bead` is live, the re-run answers
"no hold" and the posture drops `commented`. The open unengaged visit carries
that stamp too, so a visit filed at an earlier head suppresses a second one.
It also keeps holding the merge through the finalize gate's open-visit clause.
With nothing live, the re-run reads the threads and files at the new head only
if they are still unengaged. A head move therefore delays the read and drops
nothing. The loss came from the conflict arm acting before the read was
routed.

**Should the merge-in carry the pending feedback forward?** For arm-7
feedback it already does, by not being filed. Since tk-f9x2nb the conflict
arm stands down while a batch is unanswered. The batch's rework child is
`prepare_mode=merge`, so it brings the branch current as it answers. Unengaged
threads cannot ride a merge-in. The backstop files a visit, not rework, by
design: telling a finding from the city's own answer off a raw thread read
would loop on the city's replies. So the threads have to be routed first.

## What changed on main between the incident and the fix

- **#1131, provenance (2026-10-07).** An unmarked post under the city's login
  is feedback when it was published after the anchor's provenance cutover
  (`pr_provenance_since`, stamped the first time pr-facts reads the PR). An
  operator-run review posted today is therefore arm-7 feedback, and it routes
  on a conflicting PR. The backstop now covers only posts from before the
  cutover, and passes where the cutover could not be read.
- **#1147, approval gate (2026-10-09).** The conflict arm brings only an
  approved PR current. For an approved PR the incident's path was unchanged:
  the merge-in was filed over the threads. For an unapproved PR, as #1117 was,
  the remaining gap became a deadlock. The conflict waits for an approval, the
  operator waits for an answer to the review, and the visit that would ask for
  one is never filed.

On 2026-10-09 no open gc-toolkit PR anchor was exposed. The scan applied both
halves of the backstop's predicate to each of the 29, against its recorded
cutover. 27 have no unmarked city-login comment from before their cutover.
PR #995 has one and PR #977 has 26, but neither has an unresolved thread
without a city-marked post. Run against PR #1117 with an incident-time
cutover, the first half counts the operator's four comments. Its threads are
resolved now, each behind a marked reply. The gap was latent on main, with no
live instance.

## The fix

One flag, `owed`, now says "feedback nothing covers yet" for every dispatch
arm. It is set by an unrouted arm-7 batch (`unanswered`), or by unengaged
threads with no visit standing for them (`UT_COUNT`, set only on a read that
found none).

- The CONFLICTING arm gates on `owed` in both of its places: the merge-in
  dispatch, and the guard on a missing branch or fix pool. A conflicting PR
  that owes either kind of feedback falls through to the arm that routes it.
- The unengaged visit arm moved up to sit beside the feedback arm, ahead of
  the `--route-comments-only` stop. Both routing passes file it before any arm
  can end the anchor's visit. It ends the visit once it routes, the way the
  feedback arm does.
- Once the visit stands, `UT_COUNT` stays empty, so nothing is owed. The next
  pass brings an approved branch current while the open visit holds the merge.

Arm 7's routing, the posture derivation and the visit's head-keyed dedup are
unchanged.

### Verification

`assets/scripts/pr-facts.test.sh`, part `checks`, adds four cases:

- an approved conflicting PR gets the visit and no merge-in child;
- the next pass files the merge-in and still has one visit;
- an unapproved conflicting PR gets the visit rather than the approval wait;
- `--route-comments-only` files the visit for a conflicting PR.

Three mutants show each half of the change is needed, each run on its own copy
of the tree:

| Mutant | New-case assertions failing |
|---|---|
| main's whole script | 13 of 17 |
| this fix, conflict gate reverted to `unanswered` | 11 of 17; the routing-pass case passes |
| this fix, visit arm back at the tail | 2 of 17, both in the routing-pass case |

Under main's script the second pass also shows step 5. The posture reads
`approved` while the merge-in child is in flight.
