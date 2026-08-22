---
name: Design note — scoping the converse claim to its continuation group
description: Why the fix is a claim-then-release wrapper rather than a prompt edit or a binary change, the bd claim-guard behaviour it is built on (verified live), and what was routed upstream instead.
---

# A claim outside the group is not yours to work

Work record for `tk-msfmu`. The behaviour that ships is described in
`agents/converse/prompt.template.md` step 1, `assets/scripts/converse-claim.sh`,
and `docs/gascity-human-engagement.md`; this note records the reasoning and the
measurements behind them.

## The defect

`agents/converse/agent.toml` names `specs/tk-h9pq5/design-doc.md` as the design
authority. That document states the v2 loop in one sentence: the role
"records the outcome on the subject bead, closes the turn, then **re-claims
within the group and drains when the group is dry**".

The shipped prompt said the opposite in two places — step 1's "a claim is
authoritative even when it names a different subject than your last one — work
it the same way", and step 8's unscoped "Claim again (step 1)". On 2026-08-22 a
converse session finished a sitting about the helm board UI (subject tk-3a176)
and then claimed an unrelated merge-skill visit and began prepping it in the
same thread. The operator: *"How'd we get here? I thought we were talking about
the helm UI?"*

## Where the drift came from

Not invention. `docs/gascity-human-engagement.md` records the upstream
`gc-role-worker` contract as two clauses:

> an empty continuation group after close is a hard session boundary; a
> successful claim is authoritative even across groups

The pack carried the second and dropped the first. They are not actually in
conflict — the first governs whether to **make** a cross-group claim, the second
what a claim **already in hand** is worth — and the fix honours both.

## Why the preferred remedy could not land here

The bead's preferred remedy is a group filter on `gc hook --claim`. That is the
right fix and it is not in this repo: `gc hook`'s whole option set is `--claim`,
`--drain-ack`, `--inject`, `--json` (verified against the running binary), and
the binary lives upstream. Routed as **`gc-nn2ex`** in the gascity rig, with the
release ordering below attached so whoever takes it knows what the workaround
costs.

The bead's second remedy — prompt-only, drain on an out-of-group claim — is
marked "do not ship this half alone", correctly: the claim has already assigned
the turn to a session about to die, and the reconciler's reassign path refuses a
held visit by design, so draining strands it until witness patrol or lease
expiry.

## What shipped, and why it is not that hazardous half

`assets/scripts/converse-claim.sh` claims, and **puts a foreign turn back**
before telling the session to drain. The release is what converts the hazardous
remedy into a safe one, so it is the part that had to be verified rather than
assumed.

**The claim guard refuses the obvious release.** Measured live against the
running bd on 2026-08-22, on a scratch bead held by this session:

    $ gc bd update tk-dr5wm --status=open --assignee=""
    Error: 1 of 1 issues failed to update
      tk-dr5wm: cannot reassign tk-dr5wm: held by "gc-toolkit__polecat-lx-mazpg"
      (in_progress); coordinate with the holder ...

Note *held by the caller's own live session* — being the holder does not exempt
you. And the refusal is atomic over the whole update, so batching the clears
loses the ones that needed no claim at all (the tk-z27pw shape).

**Split and ordered, the same clears need no `--force`:**

1. `--unset-metadata gc.session_id --unset-metadata gc.session_name` — metadata
   writes bypass the claim guard, and this runs FIRST so the turn never becomes
   offerable while still naming a dead session;
2. `--status=open` — the guard keys on `in_progress`, so this opens the gate;
3. `--assignee=""` — now permitted.

Verified end to end on the scratch bead: final state `open`, no assignee, no
session pointer, `gc.routed_to` intact — the pool's offer shape. The scratch
bead was deleted.

**`gc.routed_to` is deliberately untouched.** It is the offer predicate; clearing
it would *park* the turn rather than return it — the same failure by another
route. Pinned by `(NOROUTE)`.

**The read is trusted over the writes.** Every update can exit 0 and the bead
still be held, so the script re-reads the bead and only drains on a confirmed
`open` + unassigned. An unreleasable turn is **worked** with
`reason=unreleasable` rather than stranded — which is also where upstream
clause 2 applies: a claim in hand is authoritative. Pinned by `(FAILSAFE)`.

## Rejected

- **Editing only the prompt.** Instruction-dependent fixes fail silently, and
  this one would strand turns while doing so.
- **A `release` verb on `gc-helm.sh`.** It already has `takeaway --release`,
  which *parks* a bead — the opposite operation. Two verbs named release, one
  returning work to the pool and one removing it, is a trap.
- **Keeping the claim and merely announcing the switch.** That is the narrower
  point on observation tk-w0ily, and the bead notes it misdiagnosed the cause.
  The announcement survives here only on the `unreleasable` path, where the
  switch genuinely cannot be avoided.

## Verification

`assets/scripts/converse-signoff.test.sh` — 110 passed, 0 failed. New section
"the claim boundary is scoped to the continuation group": `(NOWORK)` `(FIRST)`
`(SAME)` `(NOGROUP)` `(FOREIGN)` `(SPLIT)` `(ORDER)` `(NOROUTE)` `(FAILSAFE)`,
plus static assertions that the prompt no longer carries the broadened sentence
and that the wake nudge names the claimer (the nudge is read before step 1, so a
stale nudge re-teaches the unscoped claim whatever the prompt says).

Each guard was mutation-tested and each fails its own assertion when removed:
dropping the group comparison, batching the release into one update, moving the
session-pointer unset after the assignee clear, also clearing `gc.routed_to`,
and trusting the writes instead of re-reading.
