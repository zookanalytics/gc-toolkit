---
name: Refinery merge cadence
description: The exec orders around a PR's merge — the merge cadence, with its driver and arms, the arm budgets, the single-flight guarantee and how to read what a pass did, the PR watch that saves GitHub's side of each PR the city owns, and the landing order that merges a PR on the pending record. Read it to know what drives merges, and why nothing else may.
---

# Refinery merge cadence

The merge side of the anchor lifecycle is driven by orders, never by an agent.
The landing order merges each PR on the pending record and takes each person's
post on it, its red checks and its conflicts as work
([The landing order](#the-landing-order)), and the merge cadence's arms keep the
old review path's dispatch and sweeps. The cadence's liveness has its own
doctor check (`check-cadence-live`).

## Scope

**Mandate.** What drives the merge-side writers, what each arm of the merge
cadence owns, what a pass of the PR watch reads and saves, what a run of the
landing order does, and the runtime guarantees the arrangement depends on.

**Boundaries.** The states the arms and the landing order move an anchor
through are [state-machine.md](state-machine.md). The refinery *agent*'s steps,
which land, publish, park or send work back, live in
`formulas/mol-refinery-patrol.toml` and the scripts each step calls, and are not
driven by either order. The witness patrol's `check-refinery` step watches
that patrol's queue for a hand-off gone stuck.

## Mechanism

Every 60s, per rig: `orders/refinery-reconcile.toml` (`trigger = "cooldown"`,
`scope = "rig"`) execs `assets/scripts/refinery-reconcile.sh`, the driver,
which runs the arms in order and exits.

| | |
|---|---|
| Cadence | `interval = "60s"`, tunable from city.toml `[[orders.overrides]]` |
| Scope | `scope = "rig"` — one registration per importing rig |
| Working directory | the rig's own root, so `git remote get-url origin` resolves |
| Environment | controller-built: `GC_RIG`, `GC_RIG_ROOT`, `BEADS_DIR`, `GC_BEADS_PREFIX`, `PACK_DIR`, `GC_PACK_STATE_DIR`, the Dolt projection, the `gh` token |
| Timeout | `timeout = "600s"`, tunable per rig from city.toml `[[orders.overrides]]` — it bounds how long a wedged pass holds the per-rig lock. It must cover a whole pass at the slow end of host load and stay under the driver's `REFINERY_RECONCILE_LOCK_STALL_SECS`, and it does *not* fit inside the controller watchdog's 2m tracking-sweep window |
| Pass budget | `REFINERY_RECONCILE_PASS_BUDGET_SECS` (420, below the timeout; 0 = unpaced) bounds the arm that walks a set growing with the queue, listed in `PACED_ARMS` in refinery-reconcile.sh: gate-ensure. Its deadline is what the budget has left when it starts, never under `REFINERY_RECONCILE_ARM_FLOOR_SECS` (20). It visits first the anchors it can act on and then resumes its rotation from its cursor in the pass state dir. Set both per rig through the override's `env` |

Anything per-rig is derived inside the driver from `GC_RIG` / `GC_RIG_ROOT`;
one `[order.env]` serves every registration. The refinery agent does not drive
the cadence — the arms run whether or not any refinery session is awake.

## The arms

Each arm keeps the number the driver logs it under.

- **(6) gate-ensure.sh** — check satisfiability, on the old review path, for an
   anchor at `pre_open_gate` or `pull_request`, which no bead carries; a PR on
   the pending record has a review run instead ([state-machine.md](state-machine.md#checks)). Every gating
   anchor declares a non-empty `check_set` (the default is stamped when absent;
   the `none` sentinel is respected), and every declared check is *raisable*: the lane
   derives `green`, or a live routed review bead is in flight, else dispatch one
   (stamp first, then attach `mol-review` via `gc sling --on`; read the pour
   back). A lane that derives `green` ends the arm's interest however far the
   branch has advanced since — no lane's green compares to a head. An
   operator's own `merge_hold` also ends the arm with no dispatch: gate-ensure
   raises no review under a hold.
   A review whose only reach is the pour stamp is qualified before it counts
   as in flight: if its workflow is spent — every step closed but
   `workflow-finalize`, which belongs to the control-dispatcher — no verdict
   can still be coming, and the arm puts it to a person through `human-gate.sh`
   under the `review-wedge` key rather than holding the anchor in silence. It
   files on the second consecutive sighting, because `mol-review`'s failure arm
   closes its chain before it restores the bead's route. No dispatch goes out
   while anything is acting on the anchor — a fix unit in flight (including the
   one answering an open `must-fix` finding on any lane), a validation pass in
   flight, or a full review already in flight on the lane — which is the
   QUIESCENCE predicate one authority computes so it cannot disagree with itself
   about whether a review was already out. The hold names the actor. A
   `must-fix` finding no fix unit answers is a demand on the anchor, not an
   actor: it holds the merge through its `blocks` edge and keeps the anchor
   `progressing`, but it does not hold the dispatch, and the arm reports it as
   unanswered. The same authority also releases a finding: on the first pass
   after every fix unit answering a `must-fix` finding has closed, it closes the
   finding, so a fix that has landed on the branch stops holding the publish
   and the merge. A review that read a mid-change diff would raise
   only the no-op rework the declination texts are full of. There is no dispatch
   ceiling: quiescence forbids the redundant round a ceiling would have bounded,
   and the runaway shapes left — a reviewer that dies after claim, a fix unit
   filed with its edge reversed, a landed fix whose finding that release missed
   — stop the PR moving rather than spin the dispatcher.
   It visits every gating anchor, so its cost grows with the set. It runs under
   its share of the pass budget. It first visits the
   anchors it can act on: one with no `check_set` (it owes the stamp), one with
   no machine verdict (never visited; a `check_set` of `none` or `off` never
   gets one), and one whose mark moved since this arm last visited it. The mark
   joins `merge_result`, the draft markers and `check_set`, which decide the
   lanes a stage dispatches, `merge_hold`, which holds the anchor's review
   dispatch while it is set, and the ids of the anchor's live children. A hold
   lifting, or a review, validation pass, finding or fix unit opening or
   closing, puts the anchor first; a review this arm opens joins the mark its
   own visit records.
   Then it visits the rest in id order starting after the last one a pass
   finished (`gate-ensure.cursor` in the pass state dir), wrapping, and starts no
   new anchor once its share is spent. The first group rotates on
   `gate-ensure.cursor.first`, and `gate-ensure.cursor.seen` holds the marks. A
   slow walk therefore delays review dispatch for the anchors it has not reached,
   and nothing else, and every anchor is reached within a bounded number of
   passes. Its rc=3 (an anchor whose `check_set` stamp did not persist, or an
   enumeration it could not read) is reported without failing the order or
   holding anything.

- **(8) review-sweep.sh** — cleanup over closed anchors on the old review path, no
   merge authority. A
   dispatched review whose anchor is closed and whose `review_branch` is gone
   from origin has no verdict left to give. Both `signoff.sh` verdicts bind a
   marker to a commit and there is no commit, and `request-changes` would
   additionally file a rework child against work that already landed. The arm
   closes such a review with `gc.outcome=moot` and the reason recorded on the
   bead, and writes nothing to the anchor. Both conditions are required, so a
   branch that is merely unfetched and an anchor that still gates are each
   left alone. Branch existence comes from one `git ls-remote --heads origin`
   per pass, and a listing that could not be read sweeps nothing. The release
   verb lives here rather than as a third `signoff.sh` verdict because the
   residue is filed by more than one dispatcher.
- **(9) scaffolding-sweep.sh** — cleanup over DISPOSED anchors' old review
   scaffolding, no merge authority.
   An anchor withdrawn won't-do or closed not-planned carries a disposition —
   the duplicates or supersedes edge `bead-rehome.sh` records onto its successor,
   or `gc.pr_close_disposition_kind` (the intent `pr-dispose.sh` records) — but its
   machine review scaffolding does not close with it: the validation pass, the
   finding beads, and the rework/fix-unit beads stay open, each holding a
   `blocks` edge on the anchor (a fix unit also blocks the must-fix findings it
   answers), and each holding gate-ensure's quiescence, so the disposed anchor
   stands stuck behind work that will never land. Nothing else retires them on a
   disposal: `close-answered` keys on a fix LANDING, and `review-sweep` on an
   anchor already closed. This arm closes each
   `task_kind=validation|finding|rework` bead whose `anchor_bead` names a
   disposed, non-merged anchor — `gc.outcome=moot`, the reason appended, read
   back — reworks before the findings they block so a finding's close is not
   refused the same pass. A finding is mooted only when it objects to the
   disposed diff. A human review comment on a line the PR left unchanged can
   cite code the target branch already carries, so its finding is carried
   forward to a bug bead of its own through `bead-rehome.sh` instead; the PR's
   inline comments are read once per anchor that carries such a candidate. It
   leaves `task_kind=review` to review-sweep, a human gate or a conversation to
   the human side, and a `rebase_hold` freeze to the operator, and never closes
   the anchor itself: that is `bead-rehome.sh`'s, which the landing order runs
   once the PR has closed, held by `finalize-gate.sh` while a human gate on the
   anchor is open — which clearing the machine scaffolding here lets land once
   none is. A merged anchor is a landing, never a disposal, and is skipped.

## Single-flight: the tracking gate and the pass lock

Two passes writing the same anchors at once is the failure this
arrangement exists to prevent. The controller's open-tracking gate is one half
of the guarantee and a `flock` in the driver is the other, because the gate can
be reopened underneath a pass that is still running.

The gate:

- The tracking bead for a run is created **synchronously before** the run
  launches and closed in a `defer` **after** it returns.
- The dispatcher's first gate skips any order with an open tracking bead.
- That gate keys on `ScopedName()` — `refinery-reconcile:rig:<rig>` — so each
  rig has its own single-flight and co-tenant rigs never serialise against
  each other.

Why that is not sufficient: the controller runs a tracking-sweep watchdog every
30s which closes **any** order's tracking bead older than 2m
(`orderTrackingSweepWatchdogStaleAfter`, gascity `cmd/gc/order_dispatch.go`) —
a separate mechanism from the `order-tracking-sweep` order's own 10m
`--stale-after`, and much shorter. A pass that runs past two minutes has its
gate removed while it is still working, and the next tick dispatches a second
one onto the same anchors. gc-toolkit is where this bites, because it is the
rig whose pass routinely outruns two minutes.

The lock:

- The driver takes a non-blocking exclusive `flock` on
  `<state-dir>/<rig>/pass.lock` before the first arm and records the holder's
  pid and start time in `pass.holder` beside it. It depends on no bead
  surviving. The lock is `bd-lib.sh`'s `take_pass_lock`.
- `<rig>` is the rig name with each byte outside `A-Za-z0-9._-` read as `_`,
  and `rig` for a name of `.` or `..`. Every version of the driver must derive
  it the same way. A deploy can start a new driver while the one it replaces
  is still running a pass, and the two passes stay apart only when both name
  the same lock file. So the key is not `bd-lib.sh`'s `rig_state_key`, which
  cuts a rig name past 64 bytes and adds a checksum to any name it rewrites.
- The driver holds the descriptor, and each arm runs through `bd-lib.sh`'s
  `pass_child`, from a subshell that holds it until the arm exits. So the lock
  is held for exactly as long as a writer is live, and the kernel releases it
  on any exit, `SIGKILL` included.
- The arm itself runs with the descriptor closed, and so does the drop-tail
  report. An arm's store read can bring up a Dolt server, and `gc` hands the
  descriptors it was given to what it starts. A server that kept the descriptor
  would outlive the pass and hold the lock against every later one.
- A tick that finds it held logs one `SKIPPED` line and exits 0 — the cadence
  is firing and the pass in flight is doing the work.
- A holder older than `REFINERY_RECONCILE_LOCK_STALL_SECS` (900s default) is
  not a slow pass, because the order's timeout stops the pass's whole process
  group well before that: a driver run by hand, or an arm still running after
  its driver was killed by itself, holds the lock. That tick exits 1, so
  `order.failed` names the wedge rather than letting a stopped queue look like
  a firing one.
- A tick that cannot take the lock at all runs no arm and exits 1. That covers
  `flock` missing from `PATH` and a lock file the driver cannot create or open.
  Nothing else carries single-flight, so a pass that ran anyway would be the
  second writer.

Two settings must never change, because each would undo the guarantee:

- **Never set `no_work_gate` on this order.** It opts the order out of both
  open-work gates, and the first of them is the tracking gate above.
- **`timeout` bounds how long a wedged pass can hold the lock.** It does not
  keep the pass inside the watchdog window, because no budget that covers a real
  pass fits there, so the lock is what carries single-flight.
  `refinery-reconcile.test.sh` asserts the pair mechanically: a timeout above the
  2m window passes only in a run that also demonstrates one pass running its
  arms across two overlapping ticks. The suite holds the upper bound the same way,
  reading both numbers from the files that set them: a timeout at or above the
  driver's `REFINERY_RECONCILE_LOCK_STALL_SECS` would make a pass that is still
  running read as a wedged one.

Never run a cadence driver out-of-band (by hand, cron, or a daemon). Running
this script by hand at least serialises against the lock; anything else is a
second writer that neither the gate nor the lock can see.

## Reading what a pass did

The controller keeps an exec order's output only on non-zero exit, folding a
bounded tail into the `order.failed` event. So: an unexpected arm failure makes
the driver exit 1 (the failing arm names reach `order.failed`); gate-ensure's
rc=3 is reported but does not fail the order. Every pass logs to
`<GC_PACK_STATE_DIR>/refinery-reconcile/<rig>/pass.log`, trimmed to
`REFINERY_RECONCILE_LOG_KEEP` lines (2000 default) and not subject to bead
retention. Arms append as they run, so the shape of the log is what tells you
how a pass ended:

| Line | Meaning |
|---|---|
| `=== <ts> rig=<rig> refinery=<agent>` | a pass started |
| `-- (<n>) <arm> (started <ts>)` | an arm started; its output follows |
| `-- (<n>) <arm>: done in <s>s (rc=<rc>)` | that arm returned after `<s>` seconds. An arm with a start line and no done line is the one the pass was killed in |
| `<arm>: visited <k> of <n> ...` | how much of its walk the paced arm covered; `the next pass resumes at <id>` follows when the pass budget stopped it. gate-ensure's `<n>` is the size of the gating set its cost grows with. It adds `(<f> needing action first)`, and `<m> needing action wait for the next pass` when the budget left some of that group |
| `END <ts> (<s>s)` | that pass finished after `<s>` seconds; a `FAILED:` line sits above it if any arm failed |
| a `===` with no `END` under it | the pass was killed or hit its timeout — the arms logged above it are how far it got |
| `--- <ts> rig=<rig> SKIPPED: ...` | the tick found a pass already in flight and did nothing |
| `--- <ts> rig=<rig> STALLED: ...` | the lock has been held past the stall bound; the arms have stopped |

**`gc order history` is store-complete only when the read is unbounded.** Any
positive `--limit` — including the default 50, and a limit larger than the row
count — returns runs from the city store alone, printed under a `RIG` column,
so a single-rig answer looks city-wide. Always:

```bash
gc order history refinery-reconcile --since 30m --limit 0
```

Prefer `gc doctor` (`check-cadence-live`) over hand-rolled queries: it asserts
per rig that the order is registered and firing within its interval.

## The PR watch

`orders/pr-poll.toml` asks GitHub every minute whether each PR the rig's beads
own moved, and saves GitHub's side of each PR that did on its bead. Its signs
show what people do on a PR, a push, a comment, a review, a label, a move into
or out of draft, a close, a reopen or a merge, and every check's result, so the
saved read takes such a change within a minute. It is
a rig-scoped cooldown exec order with a 180-second timeout, which runs
`gctk pr poll --db "$GC_RIG_ROOT/.beads"`. `orders/pr-compare.toml`, the net,
reads each of those PRs in full every hour and saves each one that differs from
the read saved on its bead, which catches within the hour the few changes no
cheap sign shows, and clears the city's labels off the PRs no live bead owns
(the net, below). The two are the first of the PR's two loops: they keep each
PR's saved read current, and the landing order, the second, finds and does its
work from that read and the store, reading GitHub first only for a merge,
which has the one-PR update re-read the PR in full
([The landing order](#the-landing-order)).

These two orders and the landing order run at their set intervals, `pr-poll`
and `pr-reconcile` every minute and `pr-compare` every hour, only while the
city's order budget lets each clock-driven order start at its own interval.
Gas City's orders lane runs about one pass each `[daemon] patrol_interval`, 30
seconds by default, and a pass starts at most
`[orders] max_dispatches_per_tick`, 4 by default, of the city's cooldown, cron
and event orders that are due. A due order past the budget waits for a later
pass. When all of those orders are due together, as after a stop longer than
their intervals, the lane starts them a budget's worth at a time, one pass
apart, and an order whose interval is shorter than the time those passes take
starts later than its interval. `gc doctor`'s order-dispatch-floor check warns
of each order whose interval is shorter than that time, and names the budget
that fits. A budget at or above the number of those orders the city runs
starts each of them on the pass that finds it due. The city's `city.toml`
holds the old refinery pass, `refinery-reconcile`, at 5 minutes until the old
review path's retirement deletes it, because one pass of it takes minutes
whatever the order budget, and at its own minute it would run nearly back to
back.

A PR is owned when a live bead names it as its own and is no other bead's
child: an anchor names it in `pr_url` beside a `merge_result`, and a bead the
refinery sent back to the pool names it in `existing_pr`. A bead whose
`anchor_bead` names another bead, such as a rework child, owns nothing. Every
owned PR is asked about, but one that more than one live bead owns, which the
pass reports failed.

**The cheap question.** A pass asks GitHub for each owned PR's signs, with one
aliased `pullRequest(number:)` field for each PR and at most 50 PRs a request,
1 point each. The signs are the PR's state and draft flag, its head, its base
and the base's tip, when GitHub last changed it, its comment, review and
dismissed-review counts, its labels, every one, and its checks at the head
counted by state. It reads no comment, check or thread. A PR whose signs did
not read keeps the signs saved on its bead, the next pass asks again, and the
pass exits 2.

**The one-PR update.** For each PR whose signs differ from the ones saved on its
bead, or whose bead holds no read or one not current for it, the pass runs the
one-PR update, `gctk pr refresh`. It takes those PRs, from every repository it
asked, in a shuffled order, so one whose update is slow or keeps failing holds
no other back, and starts none more than 90 seconds in. The update reads only
what moved:

| What moved | What it reads |
|---|---|
| the labels | nothing more, since the signs are the labels |
| the base's tip or the state | the PR's own facts |
| the draft flag | the PR's own facts with the required check runs at the head, in one request, since a ready transition starts workflows whose check suites no sign shows until they start a job |
| when GitHub last changed the PR | the PR's own facts and its conversation |
| the head, or the checks' rollup, total or counts | the PR's own facts with the required check runs at the head, in one request |
| the comment, review or dismissed count | the conversation, in one request, and the PR's own facts, whose merge state reviews move |
| nothing, but the bead holds no read or one not current for it | everything |

The landing order has the update read every part of a PR, whatever its signs
say, before it requests the PR's merge, and decides the merge on what that read
saved ([The landing order](#the-landing-order)).

It saves what it read on the bead as `pr_github_read`, in four parts: the PR,
its checks, its conversation and its labels. Each part keeps the instant its
read was sent and the signs read with it. Under the store's record lock it
reads the bead again and writes once, guarded on the status and the assignee
it read, with each part whose read was sent after the saved part's: the part
when its facts or signs differ, and its read's instant alone when they are the
same, so an older read never replaces a newer one, even a newer one that found
nothing new. A bead on the
pending record gets `pr_state`, the PR's state lower-cased, and
`pr_last_checked_at` in the same write. An open PR's merge state that GitHub
reads as `UNKNOWN`, which it computes after a push or a base move and which
moves no sign once computed, keeps the PR part due, so each pass reads the part
again until a read finds the state, whether the PR's own signs or only its
checks moved. GitHub reads a merged PR's merge state as `UNKNOWN` for good, so
a PR that is not open is read again only when its signs move. A read that
fails saves nothing. The update is the one writer of these three keys.

The conversation part keeps each post that is feedback the city has not taken:
a review whose message is not blank, an approval's included, an inline comment
no dismissal retired, or a conversation comment, by the definition of feedback
(`pr-post.sh feedback-def`), that carries neither of the city's marks, its
`EYES` once the landing order has filed the post's ask and its `THUMBS_UP`
once the post is owed nothing more. Each such post is kept with what its ask
names it by and the node id the landing order marks it by
([The landing order](#the-landing-order)). A mark is the reading account's own
reaction, so the read takes the marks with the posts. A bead with no
`pr_provenance_since` gets the instant of the conversation's read, to the
second, in the write that saves the first conversation the update reads for
it, and the definition is applied from that instant. A conversation read from
another instant than the one the bead holds when the update writes, as when
another writer stamped one meanwhile, is not saved, and the next pass reads it
again. A conversation part that holds no list of the posts the city has not
taken is read again by the next pass whatever its signs say, since the take and
the evaluator read the list.

The checks part keeps each result of a check run the PR requires at the head,
with the check suite that holds it and its log, and each check suite there:
its status, when GitHub created it, how many check runs it holds, and the
GitHub Actions run behind it with that run's attempt, which a re-run of the
run's failed jobs raises in the same suite. The landing order's red-check acts
read them ([The landing order](#the-landing-order)). A checks part saved with
no suites is read again at the next pass.

`gctk pr refresh --pr <url>` is the same update run alone for one PR, which
reads the PR's signs itself first: the call a webhook's rule can make for the PR
an event names. A PR no live bead owns has nothing to save, and it exits 0.

**The net.** Some changes move no cheap sign: a review thread resolved or
reopened, an edit to a post that left the PR's `updatedAt` as it was, a check
the PR comes to require or stops requiring, and a review decision, merge state
or merge-queue flag that a change of the repository's rules moves.
`orders/pr-compare.toml` reads each owned PR in full every hour for them.
It is a rig-scoped cooldown exec order with a 300-second timeout, which runs
`gctk pr compare --db "$GC_RIG_ROOT/.beads"`.

A pass reads each owned PR with one aliased `pullRequest(number:)` field, at
most 10 PRs a request: the cheap signs, the merge state, the review decision,
both merge-queue flags, each review thread's resolution, the time each
conversation comment, review and inline comment last changed, read through the
review threads 10 a page, the reactions the city's account left on each inline
comment, and the check runs at the PR's last commit, each with whether the PR
requires it. It reads no post's text. A list past its first page is read on
until it ends: the labels, the conversation comments, the reviews, the threads,
a thread's comments and the check runs, these last at the commit the first page
read. A request of up to 9 PRs costs 1 point and one of 10 costs 2.

The net compares what it read with the saved read, and runs the one-PR update
over each part that differs, and over each part the cheap question's table
names:

| What differs | What the update reads |
|---|---|
| the PR's state, draft flag, head, base, merge state or either merge-queue flag | the PR's own facts |
| the commit the checks were read at, or a name or a result among the check runs the PR requires there | the PR's own facts with the required check runs at the head, in one request |
| the review decision, the unresolved threads, the newest post time, the latest time any post changed, or the city's reactions on the inline comments, which answer a thread with no reply | the conversation |

A merge state GitHub reads as `UNKNOWN` differs in nothing, since GitHub reads
an open PR's so until it has computed one, and a merged PR's for good. So a
change no cheap sign shows reaches the saved read within one pass of the net,
within the hour.
A pass in which nothing differs writes no bead. The net takes its updates in a
shuffled order and starts none more than 3 minutes in, and a PR whose read
failed keeps its saved read and fails the pass, as in the cheap question's
pass.

**The labels on PRs no bead owns.** The landing order keeps the labels of the
PRs the beads own ([The landing order](#the-landing-order)), and nothing holds
a PR no live bead owns for it, such as one whose bead closed. So each pass of
the net searches the rig's own repository, the one its clone's origin names,
for the PRs that carry a `status:` or `held:` label the labels' writer names:
`search(type: ISSUE)` over `repo:<owner>/<name> is:pr label:"status:
working",...`, 100 PRs a page for 1 point. It reads on a page at a time until
it has found 20 PRs that no live bead owns or the results end, so a page that
holds only owned PRs hides none behind it, and has the writer,
`pr-status-label.sh clear`, take the city's labels off each. It takes them in a
shuffled order, so a PR whose clear is slow or keeps failing holds no other
back, and starts none past its 3 minutes. The writer reads each PR's labels
itself first. A clear that does not land fails the pass, and the next pass's
search finds the PR again. At 20 a pass and a pass an hour, the net clears
about 20 such PRs an hour in a rig's repository, so the 586 PRs in gc-toolkit's
that carried the city's labels with no live bead owning them on 2026-11-20 take
about 30 hours to clear, each removal showing in that PR's timeline.
The net searches no other repository, since a PR there is owned by the beads
of that repository's rig.

**Reading what a pass did.** A pass in which nothing moved writes no bead but
that of an open PR whose merge state GitHub had not yet computed, which it
reads again, and otherwise costs 1 point for each 50 owned PRs, and Gas City
still writes its run record. Each update prints a line,
`<bead> <url> <action>: <detail>`, where the action is `saved`, `unchanged`
or, for a bead that no longer owns the PR when the update reads it again,
`unowned`. A PR that failed prints `<url> failed: <why>`, one
the 90 seconds left prints `<url> left`, and the last line counts what the pass
asked about. A pass exits 0 when every owned PR was asked and every update
saved, and 2 otherwise. Gas City labels the pass's run record by that exit,
`exec` or `exec-failed`, and its run history
(`GET /v0/city/{city}/orders/history`) lists each record with its labels. The
board reads there when GitHub was last asked. `gc order history pr-poll` lists
the passes without their exits. A pass of the net prints the same lines, its
window being 3 minutes and its last line but one counting the PRs it compared.
Each PR whose labels it cleared prints `<url> cleared`, and its last line says
what the search found: the pages it read, the PRs no live bead owns it found,
and how many it cleared. It exits 0 when every owned PR was read, every update
saved, the search read and every clear landed, and 2 otherwise, and Gas City
labels its run record the same way. `gc order history pr-compare` lists its
passes.

**The cost, and the PRs it is sized for.** The PR watch and the landing order
draw on the city login's GraphQL allowance, 5,000 points an hour, beside every
other reader of GitHub in the city, such as the agents' own `gh` calls. A pass of the cheap question costs 1
point for each 50 PRs a rig owns, and a rig that owns none asks nothing, so it
costs 60 points an hour for each rig that owns a PR. A pass of the net costs 1
or 2 points for each 10 owned PRs, more for a PR whose lists run past a page,
and 1 point for each page of its label search, once an hour. The landing order
reads GitHub to learn nothing: a run in which no record owes an act asks
GitHub nothing, and a merge's re-read costs about 5 points
([The landing order](#the-landing-order)). So a change to a PR costs about 2
points, the one-PR update that saves it, and each merge about 5 more.

On 2026-11-22 the city's account had 20 open PRs, in all 6 of its rigs. Before
any of them changes, that costs about 380 points an hour: about 360 for the
cheap question and about 15 for the net. At 100 open PRs it is about 390 points
an hour, and about 600 when each PR changes about once an hour.

The design is sized for about 100 open PRs across the city. The cost grows
with the rigs that own a PR, with the PRs past each 50 a rig owns, and with how
often they change, and the likely cap is where the allowance runs out: somewhere
around 1,000 to 1,500 open PRs when each changes about once an hour, less what
the city's other readers of GitHub take. More than 100 open PRs is a known
issue, and no code guards it.

## The landing order

`orders/pr-reconcile.toml` merges each PR on the
pending record ([state-machine.md](state-machine.md#the-pending-record)). It is
a rig-scoped cooldown exec order, every minute with a 120-second timeout, run
in the rig's checkout, where it fetches the target.
`assets/scripts/pr-reconcile.sh` names the rig's refinery from the roster and
execs `gctk pr reconcile --refinery <it>`. A roster that does not read runs
nothing and exits 2 for the next tick, and a rig whose roster names no refinery
has no record to read.

A run is the second of the PR's two loops. The PR watch keeps the read saved on
each PR's bead current ([The PR watch](#the-pr-watch)), and a run finds and does
its work from that saved read and the store alone, so it reads GitHub to learn
nothing. It lists the beads that carry the marker `pr_reconcile_pending`, and
every live bead, in one pass over the store. It takes each record, and each
bead on the record with a ruling's disposition on it too, with or without the
marker, an open or blocked one only while it is assigned to nobody or to the
refinery, and writes nothing to a bead someone else works. It decides every
record through that pass, by the evaluator's rule as `gctk pr status` applies
it to the saved read, as the board and the labels derive a PR's status. A
record that owes no act is reported with no write and no read of GitHub. A
record that owes an act, or one whose decision the pass could not make, such as
on a store read that did not answer, is decided again under the record lock,
from a fresh read of its bead, before the act. A record whose bead holds no
saved read of its PR, as before the watch's first pass over it, waits for the
watch's next pass, which reads such a PR whole.

Only the merge checks GitHub before it acts. A merge made in error puts work on
the target, which no run takes back, and GitHub refuses on its own what else
could go wrong with it: a merge pinned to a head that moved, one an approval or
a required check does not cover, and a write by an account without the access.
A record the evaluator finds ready on the saved read has the one-PR update
re-read its PR in full, every part whatever its signs say, with the record lock
free, since the update takes it to save. The act then decides the record again
under the lock, on what that read saved, and requests the merge pinned to the
head the evaluator judged there. So a person's comment made seconds before the
merge holds it,
which the GitHub intake's design relies on, and a ruling that lands during the
re-read is read by the decision under the lock. A re-read that finds the PR
not ready leaves the saved read corrected, so the next run finds no merge to
check. Every other act reads of GitHub only what it changes: a withdrawal
reads the reviews it dismisses and their threads (below), a send-back and a
landing fetch the branch they judge, a restart of a head's checks reads the
PR's returns to draft, and a re-run of its failed jobs the check suites at the
head, before it makes one, and a label write leaves the PR's labels to their
writer, which reads them itself. An exception, a ready transition, a
review run's pour and a retired PR's close read nothing of GitHub first, so a
saved read out of date can delay one or start one a minute early. After a ready
transition or a pour started early, a later run decides the record again on the
read the watch saves. An exception's gate and a retired PR's close stand once
made, so a PR the watch saw closed, and a person reopened before the next run,
still gets its exception, whose gate asks a person what becomes of the work, or,
when a ruling retired the PR, the close of its bead onto the ruling's successor.

So a run reads the store six times whatever its records: the marked records,
every live bead, the beads that carry a ruling's disposition, in one read the
closed beads their blocks edges name, the store's blocked set, and the closed
beads the waits name. It reads GitHub only for a merge's re-read, about 5
points, and for what an act changes. Measured on 2026-11-22, read-only on the
gc-toolkit rig's store, with 10 records, 796 live beads and the saved reads in
the shape the PR watch saves, a run in which no record owed an act took 2.1 to
2.3 seconds, read the store six times and read GitHub not at all, and its
label comparison over the 11 PRs the rig's beads own added a read and about
0.3 seconds, at a load average of about 3.5. It takes the records that owe an
act in a shuffled order, so a record whose act is slow or keeps failing holds
no other back, starts no act more than 45 seconds into the run, and stops each
act at 30 seconds with whatever GitHub call, re-read, fetch, store read or
write, human gate's filing or refinery's wake it is making. A fetch it stops
gets a SIGTERM to git's process group, so git removes the lock files it holds
in the checkout, and a kill only if it still runs 5 seconds later. The stop
ends no review run's pour and no disposition writer. `gc formula cook
--attach` makes the run before it adds the edge that attaches it, and a cook
stopped between the two leaves a run whose steps the pools take and that the
order never reads, so the next run would pour a second. An act starts a pour
only while 10 seconds of its 30 remain, which a pour's few store calls fit
inside, and otherwise leaves it to the next run. The disposition writer a
retired PR's bead goes to once the act frees the lock ends the bead's branch on
the git remote once its close lands, and a stop between the two would leave
the branch of a closed bead that no run reads again. An act that does not
complete records nothing: the record stays as it was, the next run decides it
again, and the run exits 2. A run writes none of GitHub's side itself, since it
reaches a bead only through the one-PR update, the merge's re-read included,
and a record that owes no act gets no write.

| The PR | The run |
|---|---|
| open at the head the refinery validated | marks a draft ready, without waiting for CI, once a review result passed at that head and target, no review run is attached and no ask a run can take is open. Otherwise the evaluator decides on the saved read whether the PR is ready. A ready one is re-read in full by the one-PR update, and on what that read saved GitHub is asked to squash-merge it only while its head is the head the evaluator judged (`mergePullRequest` with `expectedHeadOid`), or to add it to its base's merge queue with that head where the base requires one. The squash lands under the PR title the bead composes to when the act last reads the bead, then the PR's number (`commitHeadline`), and not under the title the PR carries, which the refinery sets only when it publishes. An enqueue takes no subject. One that is not ready gets a review run when no review result passed at that head and target, or an ask nothing holds is open on the bead (below). After a request, a later run decides on the read the watch saves |
| open at another head | records the bead open, as `pull_request_head_changed`, and hands the head to the refinery in the write that assigns it the bead, once no withdrawal and no review run holds the head. Whenever the refinery can take the bead, because nothing holds it or only conversations and asks do, it wakes the refinery after that write and clears the marker only once the wake lands (below). The refinery validates the new head and records it pending again. When it will not land the head as it stands, such as on a conflict with the target, it files the reason as an ask and then records the PR pending at the head its prep read (`refinery-requeue.sh`), so the ask holds the merge before the head is pending, a later run pours the review run that answers it, and its find-work leaves the ask alone. The saved read can lag a push, since the refinery pushes a head before it records it and the watch saves the push at its next pass, and the refinery validates whatever its prep fetched, a branch a person rewrote included, so the act fetches the PR's branch before it sends anything back. A tip at the head the saved read gives confirms it, and the bead goes back at it. When the tip contains the validated head, in the history the rig's clone holds, the saved read lags the branch: nothing is sent back, and a later run decides on the head the watch saves. Any other tip goes back as the head the branch holds, and a fetch or a read that fails sends nothing back until the next run. The refinery's prep takes the branch as it fetches it, so a reset head is the one it validates (`refinery-prep.sh`) |
| merged at the validated head, with the merge commit on the freshly fetched target | records `mr_merged` and closes the bead; when bd refuses that close, for an open child or a live blocker, records the exception `pull_request_merged_close_refused` with the merge's evidence, and files its human gate |
| closed unmerged, merged at another head, or no longer the PR the record names | records the exception, keeps the bead blocked and files a human gate keyed by its value |
| retired by a ruling, whose bead carries the disposition `pr-dispose.sh` records under the record lock before it closes the PR | requests no merge, pours no review run and marks nothing ready while the PR is open. Once the saved read shows the PR closed and no review run is attached, an act closes the asks and the withdrawals still open on the bead, then, with the record lock free, closes the bead onto the ruling's successor through `bead-rehome.sh`, run as the refinery ([state-machine.md](state-machine.md#disposition)). The script closes it only while it still has the status and assignee the act read under the lock and still records the ruling the act read, so a bead reassigned or ruled again once the lock is free goes to the next run, which reads it again. A close the script holds, such as one the ruling's open conversation holds, waits for the next run, which hands it over again, and fails no run. A retired PR that merged all the same lands as any other |
| an act that did not complete: a request GitHub refused or did not answer, a merge's re-read that did not save, a fetch that failed, a merge commit not yet on the target, or an act stopped at its 30 seconds | records nothing: the record stays as it was, the next run decides it again, and the run exits 2, so Gas City's run record holds the failure |

**Withdrawals come first.** While the saved read shows the PR open, a run first carries out each
open withdrawal on the bead, which a review run's triage files when it rules a
head material (`gctk pr withdraw`), on its own read of the PR's reviews. It
waits while an approval it would dismiss carries feedback the city has not
taken, its own message or an inline comment, on its reads of the PR's reviews
and review threads, since a dismissal retires both before the take files their
asks. It dismisses each
approval that stands on a commit that does not contain the withdrawal's head in
the history the rig's clone holds, with the withdrawal's reason and the city's
mark, reads the reviews again, and closes the withdrawal once none stands past
the ones it dismissed, so an approval given during the act keeps the withdrawal
open for a later run. Before it dismisses any, it fetches
the PR's branch into the clone, so an approved commit someone pushed from
outside the city is judged by its own history. A commit the clone still does
not hold, such as one a force-push left behind, contains no head, so its
approval is dismissed. When GitHub refuses a dismissal, it files a human gate
on the bead keyed `approval-withdraw-refused`. A dismissal, or a read of the
review threads or the reviews, that GitHub does not answer, a fetch that fails,
or a read of the clone's history that does not answer, leaves the withdrawal
for the next run. A withdrawal holds the bead from the refinery until it is
carried out, so a changed head stays assigned to nobody and keeps its marker
while one is open, and the order still reads it.

**A person's post.** Each post the saved read keeps untaken becomes an ask on
the bead that owns the PR, which the PR's review run rules. For each PR whose
bead owns it on the record, is open or blocked, is assigned to nobody or to the
refinery and carries none of the old path's receipts (below), while the saved
read shows the PR open and applied the definition of feedback from the bead's
provenance instant, an act under the record lock files the post's ask
(`gctk review ask`'s filing), then marks the post `EYES`.
The ask's reason is one line naming the post: its kind, its author, the PR, an
inline comment's file and the line it was made on, and its URL, where the run
reads the post as it stands. The reason holds no text of the post, and a filing
finds the ask filed before for the same reason, open or closed, so a post whose
mark did not land is marked again with no second ask, and an edit files nothing
new. A post's mark goes only after its ask stands. A reaction moves no sign the
cheap question reads, so once a mark has landed and the lock is free, the act
has the one-PR update read the PR's conversation again, and the saved read
shows the marks before the next run decides. A take is an act like a record's,
in the shuffled order, under the same 45 and 30 seconds, and its line's action
is `taken`. Only that read saves the marks, so once a mark has landed the take
starts no post with less than 10 of its 30 seconds left, and it leaves the
posts it did not reach for the next run, which starts from them (`left`). One
whose filing, mark or read of the conversation did not
complete leaves its posts untaken in the saved read, where each holds the PR's
merge, and the run exits 2. The merge's own re-read applies the same condition,
so a post made seconds before a merge holds it though no saved read held it
yet.

**The old path's receipts.** A bead open when the GitHub intake landed can carry
the old path's receipts: in each id space the highest id it routed (a
watermark) and the highest its review threads had answered past that (an
answered mark), and the batches it routed with the bead each went to (the
batch ledgers and `pr_comment_disposition`). The run converts them into the
city's marks, as an act decided from the bead, and takes no post on the bead
and pours no review run on it while it carries them, so no post the old path
routed is filed twice. When an open human finding, or an open ask a batch went
to, is on the bead, the act waits while a review run is attached to it or
another open bead works its branch, since that run or that writer may rule or
answer them. Otherwise, under the record lock, the act reads the PR's posts and
threads itself. It files the post of each open human finding as its ask, under
the reason the take would give it, and marks the post `EYES` once the ask
stands. It marks `EYES` on each other post the receipts reach that is feedback
carrying neither of the city's marks: an inline comment or a conversation
comment at or below its space's mark, and the message of a comment or a
request for changes at or below the review space's. The old path routed no
approval's message, so no receipt reaches one, and the take files it once the
receipts are gone. A post the old path marked when it routed it is taken
already, and the act leaves it as it is. The act resolves each unresolved
review thread that holds only the city's own posts, the old path's machine
findings, closes each open ask a batch went to, and closes each finding whose
post is no longer on the PR. With the lock free, `bead-rehome.sh`, run as the
refinery, closes each finding the act filed onto the ask of its post, and the
one-PR update reads the PR's conversation again, since a mark and a resolution
move no sign. Last, under the lock again, the act unsets the receipts in one
write guarded on the status and assignee it read, once no open human finding
and no open ask a batch went to is left on the bead and the saved read shows no
post the receipts reach untaken, so the take, which decides from the saved
read, files only the posts the old path never routed. Its line's action is
`converted`. A step that does not complete leaves the receipts on the bead, the
run exits 2, and the next run converts again from where GitHub and the store
then stand.

**A red check or a conflict.** A red check or a conflict on a PR becomes an ask
on its bead, which the PR's review run works as its branch's one writer, and a
human gate only where the city cannot go on. For each PR whose bead owns it on
the record, is open or blocked and is assigned to nobody or to the refinery,
while the saved read shows the PR open with its checks read at its head, an act
under the record lock decides from the saved read and the store. It reads each
required check by its newest result at the head: the result in the check suite
created last that holds one for it, a skip aside.

- Once every required check passes at the head, it withdraws each red-check
  gate open on the bead, `pr-fix-unmoved.<n>`, `pr-fix-capped.<n>`,
  `pr-fix-noncode.<n>` and `pr-check-unreported.<n>` for PR number `<n>`, as
  moot (`human-gate.sh --retract`), whatever holds the bead.
- Every other step waits for the record to be pending at the head the
  refinery validated, and for nothing to hold the bead: a merge or rebase hold
  set by hand, or an open human gate. A conversation on the PR holds only its
  merge, so it holds none of them.
- A PR GitHub reads `DIRTY`, or `BEHIND`, which holds its merge as `DIRTY`
  does, gets an ask to merge its target in once it is approved and no open
  bead other than an ask names its branch, such as a rework child. An
  unapproved one gets nothing, and its label shows the conflict. Its checks
  wait for that merge.
- A required check that failed for a code cause, whose name is not a deploy's,
  gets one ask for the head, naming the PR, the head, the failing checks with
  their logs and the branch. An ask closed at the head while the PR is still
  red there files `pr-fix-unmoved.<n>` in place of a second, unless another
  ask is open on the bead, such as one a review run left waiting on the
  tracker of a failure the target carries, which the run takes before a
  person is asked. A red head after three earlier heads each drew an ask files
  `pr-fix-capped.<n>` in place of a fourth. A deploy's failed check files
  `pr-fix-noncode.<n>`.
- A required check that timed out, was cancelled, failed to start, wants an
  action or went stale has the failed jobs of the GitHub Actions run behind it
  re-run, once per head and only once that run has finished. The head reads
  re-run once a suite there that holds a required check shows its run at an
  attempt above 1, which GitHub raises in the same suite at a re-run, so no key
  records it. The saved read shows a re-run only once the PR watch reads the
  checks again, so the act reads the check suites at the head from GitHub just
  before it asks for one, and asks for none while they show the head re-run,
  whether the city re-ran it in an earlier run or a person did. A failure at a
  head that reads re-run, a failure outside any
  Actions run and a re-run GitHub refuses each file `pr-fix-noncode.<n>`, only
  on an approved PR. An unapproved PR waits for its review, and a refused
  re-run is asked for again at the next run.
- An approved PR whose review passed at the head, which GitHub reads
  `BLOCKED` with no required check reported there but a skip, behind a check
  suite that has stayed queued with no check runs for ten minutes since GitHub
  created it, is returned to draft and marked ready again, which sends the
  `pull_request` event that starts its workflows again. The act first reads
  the PR's returns to draft from its timeline, and one made after the head's
  first suite was created is its own, since a writer of the branch
  returns the PR to draft before it pushes. So it restarts the checks once per
  head, waits ten minutes from its own return to draft, and then files
  `pr-check-unreported.<n>`.

Each gate's message says what the person can do, and that the gate is
withdrawn once every required check passes at the head. The act takes its
place in the shuffled order, under the same 45 and 30 seconds, and its line's
action names its step: `asked`, `rerun`, `restarted`, `gated` or `withdrawn`. A
step that does not complete, such as a re-run GitHub did not answer or a gate
that did not file, records nothing, the next run decides it again, and the run
exits 2.

**The review run.** A run pours a PR's review run, `mol-pr-review`, with
`gc formula cook --attach` onto the bead under the record lock. Its vars are the
record's PR bead, head, target and branch, and the pools and the binding the
refinery's address names (`<rig>/<binding>refinery`): `review_target`
`<rig>/<binding>polecat-codex`, `repair_target` `<rig>/<binding>polecat` and
`binding_prefix` `<binding>`. The review run is the bead's PR-finishing work
([steering.md](steering.md#pr-finishing-work)), which ranks one level sooner
than the bead, and the pour gives every bead it makes the bead's own priority.
So once the act has freed the record lock, the order settles the review run's
root and its steps with `queue-priority.sh settle`, in what is left of the
act's bound. A settle that fails or is stopped is said in the act's line and
fails no act. It pours none while a run is attached to the bead, while another
open bead names the PR's branch, such as a rework child, while the bead carries
the old path's receipts, which their conversion turns into the city's marks
first (above), or while a human gate holds it, unless every gate that holds it
is a question a review run put to a person (`review-question-<key>`) and an ask
the run can take carries a person's post filed after the newest of them, whose
run can settle the question. A conversation on the PR holds its merge and nothing
else, so runs are poured while one is open, and the evaluator's wait holds the
merge until it closes. A run that ended without a result is poured again.
When the last two runs at the validated head both ended without one, counting
only runs that ended after the bead's last `review-run-failed` gate closed, it
files a human gate keyed `review-run-failed` instead, naming both runs and how
each ended ([state-machine.md](state-machine.md#checks)).

**A pour cut short.** The pour is one `gc formula cook --attach`. It writes the
bead's input convoy, then the review run, and last, in a write of its own, the
bead's `blocks` edge onto the run's root (`wireFormulaCookGraphV2AttachRoot`,
gascity `cmd/gc/cmd_formula.go`). A launch that stops between the run's write
and the edge's leaves a review run that no edge of the bead names. bd writes
the run in one transaction, so that run is whole, unless a transient failure
had Gas City write it bead by bead (`Instantiate`, gascity
`internal/molecule/molecule.go`), where a launch that stops partway leaves part
of one. A launch stops there when Gas City
ends the order's run at the order's timeout, which ends the run's process group
and each group the run started, the cook's among them (`shellExecRunner`,
gascity `cmd/gc/order_dispatch.go`), when the host goes down, or when the store
fails the edge's write, on which the cook exits non-zero and leaves the run.
The next run of the order then finds no run attached and pours a second at
that head. That costs one more review of the head, because a review run pushes
only under a lease on the head its round judged, and Gas City's claim retires
the first once the refinery is assigned the bead. Gas City does not promise one
run per bead here: each attach onto a bare bead makes an input convoy of its
own, and "A caller that wants stable grouping or dedupe should create and
target an explicit convoy" (gascity
`engdocs/design/convoy-first-formulas-and-drain-v0.md`). Measured on
2026-11-19, the 49 attaches the order made on 2026-11-17 wrote the edge 6 to 21
seconds after the run's root was created, about 10 on average, and none of the
135 review runs poured from 2026-11-17 to 2026-11-19 lacks its edge. The pack
carries no code for this gap, and nothing in it watches for such a run.

**How the refinery hears of a changed head.** A changed head is the refinery's
to take once no withdrawal is open on the bead and no review run is attached to
it. Until then the bead stays assigned to nobody and keeps its marker, so a
later run carries the withdrawal out or reads the run's end, and no run is ever
attached to a bead the refinery is assigned, which Gas City's claim would read
as handed off ([the search](../specs/tk-1tfzr71.209/gas-city-search.md)). An
assignment alone gives a running refinery no turn: an open bead assigned to the
refinery that the store reads as ready is demand that wakes a stopped refinery,
and nothing tells a running, idle one
([deferred-dispatch.md](deferred-dispatch.md#a-named-agent-hears-through-gas-citys-hand-off)).
A conversation or an ask on the PR holds the bead too, and holds only its
merge, so the refinery's find-work takes the bead past it. So whenever the
refinery can take the bead, because nothing holds it or only conversations and
asks do, the run hands the head over in two writes with the wake between them.
It assigns the bead to the refinery, wakes the refinery and nudges it, with
`gc session wake` and `gc session nudge` as a polecat's hand-off does, and only
then clears the marker, so the find-work the wake starts lists the bead. While
another wait holds the bead, such as a human gate, the refinery cannot take it
yet: the run hands the head over in one write that assigns the bead to the
refinery and clears the marker, and core's `cascade-nudge-on-blocker-close`
order nudges the refinery once that blocker closes with no other still holding
the bead. The wake comes in the run that requeues the head when no withdrawal
or run holds it, and otherwise in the first run after the review run or the
withdrawal ends, since its end changes what the record's decision reads of the
store. A run that comes to the act more than 45 seconds in does
not start it, and leaves the wake to a later run. A wake that does not land
records nothing, as an act that does not complete records nothing: the marker
stays, and the next run wakes the refinery again. A record a dead writer left
half written, which the run sends back to the refinery for its full
validation, is handed over the same way, and its wake says the record is
incomplete. The search for a Gas City primitive that covers the wake is
[specs/tk-1tfzr71.165/gas-city-search.md](../specs/tk-1tfzr71.165/gas-city-search.md).

A merge request binds only the head the evaluator judged on the merge's re-read,
so a push that lands first makes GitHub refuse it, the record stays as it was,
and once the watch saves the moved head, a later run sends it back. The order
turns on no auto-merge, so no permission outlives the decision. A PR that waits
on the operator's approval or on its checks holds no agent: the order carries
the wait.

**One record at a time.** Gas City starts no run while the last one's tracking
bead or work is open, but its watchdog closes a tracking bead two minutes after
it was made whether or not its run still works, so the next tick can start a
second run beside the first. Each act therefore reads its record under the
store's record lock, a `flock` on `pr-record.lock` in the store's `.beads`
directory, from its read of the record to its last write of it, waiting no
longer than its 30 seconds while another writer holds it, and the run leaves
the lock free a moment between two acts so a publication waiting for it takes
it there. Two runs that overlap act on one record one after the other, the
second from the record as the first left it. The refinery's `gctk pr record`,
a review run's `gctk pr withdraw` and `gctk review passed --record`, the PR
watch's `gctk pr refresh`, from its read of the bead to its write of the saved
read, `bead-rehome.sh`'s close and `pr-dispose.sh`'s stamp of a ruling's
disposition take the same lock. So a ruling's disposition lands before an act
reads the bead, or waits until the act's last write of it, and a merge the act
requests comes before the ruling, never after it. The kernel frees the lock of
a run the timeout stops, and the acts it did not reach wait for the
next run. No webhook fires the order, because an order a webhook fires skips
Gas City's gates and each event would start a run of its own.

**What a run acts on.** A run acts only on a bead it reads under the lock as
carrying the marker, or as an open or blocked bead on the record that carries a
ruling's disposition, with or without the marker, and each write is guarded on
the status and assignee it read. A bead's assignee says who works it now:
nobody while its PR waits, and the refinery while it validates a head the PR
moved to. A bead assigned to anyone else is that assignee's while they work
it. A run does not take it, and a run that reads it assigned after taking it
writes nothing to it, requests no merge and pours no review run. The PR's
status names who holds it, and a later run works it once the assignee is gone.
What takes a PR off the record is a write that says so: the refinery's send-back
to the pool clears the marker in the write that reopens the bead, and a ruling
retires the PR. A human gate on the bead holds its merge and its next review
run.

**The labels.** A run keeps each PR's `status:` and `held:` labels equal to
what the store derives, for every PR the rig's live beads own
([state-machine.md](state-machine.md#the-status-label-github-projection)). For
each owned PR whose bead holds the PR watch's read of it, it compares the labels
of the writer's that the read saved with the ones the store derives, as `gctk
pr status` derives them over the run's own listing: the PR's status and held
values while it is open, and none once it merged or closed. Where they differ,
it has the labels' one writer, `pr-status-label.sh`, write them, reading
nothing of the PR first, `reconcile` on a PR the saved read shows open and
`clear` on one it shows merged or closed, handing it no labels, so the writer
reads the PR's labels itself. A label is a view of the saved read and the
store, so one a saved read out of date made wrong is put right once the watch
saves the PR. A label write is an act among the others: it takes its
place in the shuffled order, starts inside the 45 seconds, stops at 30, takes
no lock and writes nothing on the bead. A write that does not land records
nothing, so the next run finds the same difference and writes it again. A PR
whose bead holds no read of it, or a read of another PR, owes no write until
the PR watch saves one, and a PR more than one live bead owns owes none. So a
change on the store's side, such as a gate a person files or clears, reaches
the labels at the next run, and a label a person changes on GitHub is put back
once the PR watch saves it. A PR the run lands has its labels cleared in the
same run when the comparison finds them differing, as it does once the PR
watch has saved the merge. When the saved read still shows the PR open, with
the labels the store derives for it, the run lands it and writes no label, and
once its bead closes, the net clears them ([The PR watch](#the-pr-watch)).

**The seed audit after a landing.** In a rig whose clone carries
`generated/seed-audit`, a run that closes a bead on a merge into the rig's
default branch, the branch `origin/HEAD` names, then checks that branch's seed
audit with the record lock released. It reads the branch at its tip as the run
fetched it to verify the merge, so the check judges that merge and every one
after it, and a tip that one landing in a run has checked is not checked again
in that run. `render-seed-audit.sh --check-merge <tip> <tip>` renders the tip's
tree once and names each file the tip commits other than as rendered, and the
run hands those files to `seed-audit-reaudit.sh`, which slings the one bead that
re-renders the default branch and lands the new text in a pull request of its
own. The writer runs in the rig's clone, whose `origin/HEAD` it reads, and holds
a lock of its own from its read of the live re-renders to its sling, a `flock`
on `seed-audit-reaudit.lock` in the store's `.beads` directory, so two runs that
land on the default branch at once file one re-render between them. A call that
finds the lock held files nothing. The check holds no PR, so until that
re-render lands, a PR's diff can show render lines it did not change. A check
that does not run holds nothing either: when the default branch or its tip does
not read, the render does not complete, the writer dispatches nothing, or the
run has used its 45 seconds, the next landing on the branch checks again. The
landing's line says what the check found.

**Reading what a run did.** Each outcome prints on a line of its own, `<bead>
<action>: <detail>`, where `readied` names a draft the run marked ready,
`poured` a review run it attached, `labeled` a PR whose labels it had written,
`retry` an act that did not complete and `left` an act the run's 45 seconds
left for the next run, or a review run's pour an act left because less than 10
of its 30 seconds remained. A run exits 0 when each record and each PR's labels
it took up were decided and no act it started failed, and 2 when the listing
did not answer, or a record or a PR's labels could not be decided or its act
did not complete. Gas City labels the run's record by that exit, `exec` or
`exec-failed`. `gc order history pr-reconcile` lists the runs and each run's
record bead without the exit, and `gc bd show <bead>` shows a record's labels.

## Adjacent order: rig-checkout sync

The live `rigs/*` checkouts are what the runtime executes, and the landing
order merges PRs on GitHub — so a merged PR is **not live** until
`orders/reconcile-rig-checkouts.toml` (every 15m, city-scoped) fast-forwards
each rig checkout:
`git fetch origin && git merge --ff-only --no-overwrite-ignore origin/<default>`.
`--ff-only` mutates nothing on divergence, on a local change to a path the
incoming commits rewrite, or on untracked content in the way of what they write,
and `--no-overwrite-ignore` makes that include an ignored file, which git
otherwise overwrites. A file the incoming commits delete leaves the working
tree with them when its copy is unmodified, so a change that stops tracking a
file a live checkout still needs, such as machine-local config, removes an
unmodified copy of it there. A checkout whose HEAD is off its default branch is
not fast-forwarded. A refused fast-forward and a checkout off its default
branch each file one idempotent human gate per blocked rig (via
`human-gate.sh`, on the rig's subject bead and carrying what git refused and
`git status`). Once the rig fast-forwards cleanly, the gate is withdrawn
`moot:` and the subject bead closes. The 15-minute window is also the exposure behind
component-model I9, watched by `doctor/check-pour-text-current`.
