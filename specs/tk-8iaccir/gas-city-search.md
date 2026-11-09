---
name: Gas City search for the sign-off's validating closer
description: The arch check asks a change that adds pack surface to show why Gas City does not already cover it. Read this when checking whether converse-signoff.sh still needs --close-brief and its closer arm, or whether Gas City or bd now checks and closes a bead once the work it waits on lands.
---

# Gas City search for the sign-off's validating closer

A converse sitting can send new work and sign off with
`converse-signoff.sh --ruled yes --waiting-on <work>`. The headline that sign-off
writes gives the subject a `blocks` edge onto the work. When the work closes, the
edge stops holding the subject, and the subject reads ready with nothing to send
it anywhere. The change has the sign-off also write the subject's close brief,
which the sitting gives with the new `--close-brief`, and arm
`mol-validate-close` on the subject through the pack's deferred dispatch. Once
the work lands, the closer checks the brief against what landed, then closes the
subject or puts it to the operator. The arch check asks what Gas City already
ships for this ([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City and bd hold a bead on its blocker and tell a dependent's owner when the
blocker closes. Neither checks a bead and closes it once its blocker lands, and
neither pours a formula on a bead when it becomes ready. So the change composes
what they ship for the hold, the `blocks` edge the headline already writes, with
the two parts the pack already runs for the rest: the deferred-dispatch arm, the
sling on unblock that the migration keeps under a warrant because Gas City ships
none (tk-1tfzr71.16), and `mol-validate-close`, the check the first reaction's
close exit and the waits skill already arm.

## The surface and the need

The change adds one flag, `--close-brief "<text>"`, to `converse-signoff.sh`,
and two writes to the sign-off: the brief, appended to the subject's notes under
`## Close brief (held on <work>, <time>)`, the heading `mol-validate-close`
already reads, and the arm, the `gc.dispatch_when_ready` keys that
`deferred-dispatch.sh arm` already writes. It adds no metadata key, bead kind or
lifecycle state, so it adds no pack noun and needs no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2).

On 2026-11-09 the operator answered "yes on both fronts" to a sitting's
recommendation that a sign-off which leaves a bead waiting on work also arrange
a check that closes the bead once that work lands. Holding that takes four
things:

1. Something acts on the subject once the work it waits on closes, without a
   person noticing the subject first.
2. What acts is a check of the subject against what landed, not a close on the
   word of the blocker's close: a blocker can close without the fix it promised.
3. It runs in the subject's own rig, whose checkout holds the code the check
   reads.
4. It never acts while the work is still open.

## Where the search looked

Each was read on 2026-11-09 (UTC):

- Gas City at upstream main `e35c1602d936`: `gc sling`'s flags
  (`cmd/gc/cmd_sling.go`), the close-triggered autoclose
  (`cmd/gc/autoclose_sweep.go`, and `beadCloseAutoclose` in
  `cmd/gc/api_state.go`), the `core` pack's `cascade-nudge-on-blocker-close`
  order and its script (`internal/bootstrap/packs/core/orders/` and
  `assets/scripts/`), `gc session wait` (`cmd/gc/cmd_wait.go`), the orders
  tutorial's trigger types (`docs/tutorials/07-orders.md`), and the check that
  refuses a second launch on a bead (`checkLegacySourceWorkflowConflict` in
  `internal/sling/sling_core.go`, `liveConvoyTrackedWorkflowRoots` in
  `internal/sling/sling_attachment.go`, and `ConflictError` in
  `internal/sourceworkflow/sourceworkflow.go`). The tree was also
  searched for a pending or deferred sling and for a sling or pour on
  readiness.
- bd at upstream main `3282b97145dc`: its dependency types
  (`internal/types/types.go`) and every reader of the `until`, `validates` and
  `delegated-from` types.

## What Gas City and bd ship

**A `blocks` edge holds a bead out of ready work until its blocker closes.** bd
lists `blocks` among the "Workflow types (affect ready work calculation)"
(`internal/types/types.go`). This is the hold the change keeps: the headline's
`--waiting-on` writes it, and the closer's arm waits behind it.

**No sling waits for a bead to become ready.** At `e35c1602d936`, `gc sling`
takes `--formula`, `--nudge`, `--force`, `--title`, `--merge`, `--no-convoy`,
`--owned`, `--reassign`, `--on`, `--dry-run`, `--no-formula`, `--stdin`,
`--scope-kind`, `--scope-ref` and `--json`, and none of them defers the pour.
Nothing in the tree records a pending sling or pours on readiness. A formula
slung at a blocked bead pours at once, so it cannot stand in for the arm.

**The `core` pack nudges a dependent's owner when its blocker closes, and pours
nothing.** `cascade-nudge-on-blocker-close` fires on `bead.closed` and nudges
each open or deferred dependent "at its assignee when one holds the bead, else at
its gc.routed_to target". The subject a sitting leaves waiting carries neither,
so the nudge reaches no one. Routing the subject to a pool, so that a nudge
would reach it, makes the pool claim it on the pool's default formula, which
cannot close it: the shape tk-zfslpir reported.

**Gas City's autoclose closes containers on store state, with no check.** Its
close-triggered autoclose, backstopped by the autoclose sweep, covers "a convoy
with every member terminal, a closed parent's open attachments, a molecule with
every step terminal" (`cmd/gc/autoclose_sweep.go`). A report waiting on a
sibling through a `blocks` edge is none of these. A close made on store state
alone is also the shape the operator retired from the pack on 2026-11-05
(gc-toolkit PR #1390): the pack's `until` auto-close closed a bead on any close
of the bead it waited on, whether or not that bead's fix had landed.

**bd's `until`, `validates` and `delegated-from` edges are labels.** bd
describes `until` as "Active until target closes", `validates` as an
"Approval/validation relationship" and `delegated-from` as "Work delegated from
parent; completion cascades up". At `3282b97145dc` their only readers are
`cmd/bd/dep_relation.go` and `cmd/bd/show_refs.go`, which print them. Nothing in
bd closes or dispatches on any of them, and Gas City reads none of them.

**An event order fires on every close, and selects none.** An order with
`trigger = "event"` and `on = "bead.closed"` "fires whenever the named event
appears on the bus" (`docs/tutorials/07-orders.md`, "Trigger types"), and the
event trigger reads no field but `on`. Such an order would fire on every close in
the city and would have to find the subjects waiting behind the closed bead,
which is the reconcile the pack's deferred-dispatch order already runs.

**A session can wait on beads, but the wait wakes a session and pours nothing.**
`gc session wait --on-beads` registers "a dependency wait for a session", which
wakes it with a reminder note once the watched beads close. A sitting's session
ends at its sign-off, and a pool session lives for one claim, so no session is
there to wake when the work lands days later.

**Gas City pours no second run of a formula over a bead that a live run of it
works.** `checkLegacySourceWorkflowConflict` refuses a launch of a formula on a
bead while a live root of the same formula works that bead through its input
convoy, since "distinct formulas concurrently targeting one bead are
legitimate, only relaunching the same one while its root is still live is the
duplicate". The refusal is a `ConflictError`, which "the CLI maps ... to exit
code 3". Once the deferred-dispatch pass has sent the closer, it retires the
arm, and the closer's run, a root over an input convoy that tracks the subject,
is all that records it. A second arm made then would be refused at every pass
until the arm's retry cap asked a person.

## What the change composes

- The hold is the `blocks` edge the headline already writes.
- The pour on unblock is `deferred-dispatch.sh arm`, the pack's residual for the
  sling on readiness that Gas City does not ship. tk-1tfzr71.16 keeps that
  residual under a warrant, and when Gas City ships a sling that waits on
  readiness, this arm moves with the pack's other arms.
- The check is `mol-validate-close`, which already validates a bead held on the
  landing that ends its job, closes it with `gc.work_outcome=no-op`, and puts any
  doubt to the operator through a human gate.
- A closer already sent is read from the run that works the subject, through
  the pack's one reader of that link (`run-lib.sh`), so the sign-off arms no
  second closer while a live `mol-validate-close` run works the subject.
- The rig is the subject's own, named by the pack's one read of the rig map
  (`rig-map.sh`), since the closer's pool and the deferred-dispatch pass are per
  rig. The city's own store runs neither, so the sign-off refuses a subject there
  and a person closes it on a human gate.
