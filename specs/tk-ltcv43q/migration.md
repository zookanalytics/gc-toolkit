---
name: Cut-over of the open feedback patterns to the backlog lifecycle
description: How tk-ltcv43q's cut-over gives each feedback pattern that was open as a standing record one of the distiller's three states (closed once resolved, waiting on its follow-up, deferred with a date), the rule that decides each, why it runs only once the change lands and what runs it, and the dry run's figures on 2026-11-12. Read it before running migrate.sh, or when a pattern's close or deferral reason names the cut-over.
---

# Cut-over of the open feedback patterns to the backlog lifecycle

Until this change, a feedback pattern was a standing record: open, never
closed, and skipped by every reader that lists open work. 180 patterns sat open
on 2026-11-12. The distiller now leaves each pattern decided on every run
(`formulas/mol-feedback-distiller.toml`, judge-and-cluster §7), and
[migrate.sh](migrate.sh) gives the patterns already open the decision their
record supports, by the same rules.

## What decides each pattern

The script reads the patterns `bd ready` lists in the gc-toolkit store, the
adopted-rule inventory on origin/main (`learning-recurrence.sh --inventory`),
and the status of each follow-up a pattern spawned (`proposal_bead`,
`eng_bead`), each read in its own store.

A pattern with a follow-up that cannot be read, or that is open in another
store, where an edge would hold nothing, is printed as `left` and decided by the
distiller's next run. That holds even when another of its follow-ups is open in
its own store, because an edge onto that one alone would release the pattern
while the other is still open. For every other pattern, the first rule that
fits decides:

1. **Waiting.** A follow-up is still open in the pattern's own store: the
   pattern gets a `blocks` edge onto each one. A pattern whose rule is adopted
   but whose follow-up is open waits too, because a pattern with follow-up work
   waits on it.
2. **Resolved.** Its rule is adopted, or every follow-up it spawned has closed:
   it closes, and the reason names the carrier file or the follow-ups.
3. **Dismissed, as a discard bucket.** tk-l6kezee (outside posts that show no
   review miss) and tk-xnawmfo (outside posts read long after they were
   written) hold observations the distiller judged not to be feedback. They
   close, and stay closed as discards arrive, because a discard reopens
   nothing.
4. **Held.** Everything else is gathering evidence: deferred for the
   distiller's `pattern_defer_days` (90), with its `promotion_hold` in the
   reason. The window runs from its `last_seen`, not from the cut-over, because
   these holds were judged when their last evidence came, and the distiller
   defers a hold from the run that judges it. When that window has already
   passed, the pattern is deferred for 12 hours (`+12h`). An observation still
   pending may be its recurrence, and only the distiller judges one, so the
   pattern is dismissed by the first distiller run after those 12 hours that
   has judged every pending observation and found none to be its recurrence.
   The distiller's order fires on a 24-hour cooldown, so that run is the
   distiller's next one only when the cut-over runs at least 12 hours before
   it.

Every close first stamps `gc.work_outcome=no-op`, because a pattern ships no
commit of its own.

## When it runs

It runs once this change has landed, through tk-1tfzr71.96, which waits on
tk-ltcv43q through a `blocks` edge and is armed to the polecat pool. Before
then, the distiller looks for existing patterns only among open beads, so a
pattern closed early would draw a duplicate the next time its feedback arrives.
Between the landing and the cut-over, the open patterns are ready beads with no
standing-record skip, which the liveness sweep can count as unnamed waits. The
arm fires on the reconcile pass after tk-ltcv43q closes, which keeps that window
to minutes.

## The dry run on 2026-11-12

Run at 20:46Z against the live store, writing nothing:

| Outcome | Patterns |
|---|---:|
| Waiting on an open follow-up | 20 |
| Resolved | 45 |
| Dismissed | 2 |
| Deferred | 113 |
| Left for the distiller | 0 |

- The 20 waiting are the 16 the sitting counted plus 4 whose rule is adopted
  while a follow-up is open (tk-qenzk6e, tk-v32d2u, tk-b80kkz, tk-prvea). The
  sitting counted those 4 among its 48 resolved. Here 45 resolve: its 48 less
  those 4, and 1 more.
- The 2 dismissed are the discard buckets.
- 108 of the deferred are deferred for their window: the 17 carrying
  `promotion_hold` and 91 with no recorded decision. Their dates run from
  2026-11 to 2027-02, most of them in 2027-01, so the distiller judges them a
  few at a time as they come due.
- The other 5 deferred are holds whose window has passed, because their last
  evidence came on 2026-08-11 to 08-14 (tk-6u3v6, tk-b7q0n, tk-kjeog, tk-ln6za,
  tk-q8a8n). They are deferred for 12 hours, and the first distiller run after
  that to judge every pending observation dismisses each unless one of them is
  its recurrence.

The live run reads the store again, so its figures move with whatever the
distiller has done in between.
