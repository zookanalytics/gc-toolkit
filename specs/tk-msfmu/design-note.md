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

`assets/scripts/converse-claim.sh` claims, and **puts every foreign turn the
claim assigned back** before telling the session to drain. The release is what converts the hazardous
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

**The turn named on that path is one still HELD, which is not always the claimed
one** (added on the second pre-open re-gate of this branch). The release runs the
named turn first, so the ordinary vacuum failure is "named turn released cleanly,
sibling stuck". Reporting `.bead_id` there handed the sitting a bead the script
had just reopened and unassigned — claimable by another session concurrently —
while the actually-held sibling stayed assigned and unworked: a strand and a race
from one line, on the very path that exists to prevent stranding. The reported
turn is now the FIRST that failed to release, which is still the claimed turn
whenever the claimed turn is the stuck one, so the single-turn `(FAILSAFE)`
contract is unchanged. Residual: only one turn can be named, so if several stay
held the rest are reported on stderr but not worked — the same one-turn ceiling
the caller always had. Pinned by `(VACUUM-HELD-NAMED)`, `(VACUUM-HELD-FIRST)`
and `(VACUUM-HELD-LATER)`.

**One claim can assign more than one turn** (added on the pre-open re-gate of
this branch; the first version released only `.bead_id`). `gc hook --claim`
preassigns the claimed bead's continuation-group siblings onto the same session
in the same call — `preassignHookContinuationGroup` in
`cmd/gc/cmd_hook_claim.go`, which assigns every open, unassigned, route-matching
sibling sharing the bead's `gc.root_bead_id` and `gc.continuation_group` — and
reports them as `continuation_assigned`. Releasing only the named turn therefore
drained with the vacuumed siblings still `in_progress` on a dying session: the
strand this script exists to prevent, reached through the door next to the one
it was watching. It is not a rare shape — a live `gc hook --claim` on
2026-08-22 returned five siblings in one call.

Every id in that set is in the claimed turn's group by construction, so when the
named turn is foreign they all are, and the whole set goes back through the same
three ordered writes and the same read-back. Absent the key the set is just the
named turn, which is the previous behaviour. The set is taken from the claim
result rather than from a query for "everything assigned to this session",
because the claim is what did the assigning and names its own work exactly,
whereas a session-wide sweep would also catch turns from the session's OWN
group — not this script's to return. Residual, and legible rather than silent:
if `gc` fails part way through the preassign it exits non-zero having already
assigned some siblings and prints no JSON, so no release list reaches the
script at all. The upstream `--continuation-group` filter retires that along
with the round trip. Pinned by `(VACUUM)`, `(VACUUM-ORDER)`, `(VACUUM-SPLIT)`,
`(VACUUM-NOROUTE)`, `(VACUUM-FAILSAFE)`, `(VACUUM-HELD-NAMED)`,
`(VACUUM-HELD-FIRST)`, `(VACUUM-HELD-LATER)` and `(VACUUM-ABSENT)`.

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

`assets/scripts/converse-signoff.test.sh` — 128 passed, 0 failed. New section
"the claim boundary is scoped to the continuation group": `(NOWORK)` `(FIRST)`
`(SAME)` `(NOGROUP)` `(FOREIGN)` `(SPLIT)` `(ORDER)` `(NOROUTE)` `(FAILSAFE)`
and, for the vacuumed set, `(VACUUM)` `(VACUUM-ORDER)` `(VACUUM-SPLIT)`
`(VACUUM-NOROUTE)` `(VACUUM-FAILSAFE)` `(VACUUM-HELD-NAMED)`
`(VACUUM-HELD-FIRST)` `(VACUUM-HELD-LATER)` `(VACUUM-ABSENT)`, plus static assertions
that the prompt no longer carries the broadened sentence and that the wake nudge
names the claimer (the nudge is read before step 1, so a stale nudge re-teaches
the unscoped claim whatever the prompt says).

Each guard was mutation-tested and each fails its own assertion when removed:
dropping the group comparison, batching the release into one update, moving the
session-pointer unset after the assignee clear, also clearing `gc.routed_to`,
and trusting the writes instead of re-reading.

The `VACUUM` guards were verified the same way, against the pre-fix script in a
parallel tree rather than by removal: the new assertions fail 6 of 122 on the
version that released only `.bead_id`, and the two that pass there vacuously —
`(VACUUM-SPLIT)` and `(VACUUM-NOROUTE)`, which have no sibling writes to judge —
were mutated on the fixed script (batching a sibling's status+assignee into one
update, and clearing a sibling's `gc.routed_to`) and each then failed.

`bash -n`, `shellcheck -s sh assets/scripts/converse-claim.sh` (clean) and
`shellcheck -s bash assets/scripts/converse-signoff.test.sh` (info-level only,
all of them shapes already present in the file). Adjacent suites unchanged:
`converse-fold-scope.test.sh` 22/0, `liveness-recheck.test.sh` 67/0,
`doctor/check-operator-next-step-wiring/run.test.sh` 14/0.

The `VACUUM-HELD` guards were verified the same way. Against the pre-fix script
(`c221f8c`, which reported `.bead_id` on the unreleasable path) in a parallel
tree, `(VACUUM-HELD-NAMED) the held sibling is worked` and `(VACUUM-HELD-LATER)
the one stuck turn is named even when it is last` both FAIL — they are the two
that catch the defect. `(VACUUM-HELD-FIRST)` passes there because it pins
behaviour the fix does not change, so it was mutation-tested on the fixed script
instead: dropping the first-wins guard (`HELD_TURN` overwritten on every failure,
i.e. last failure wins) makes it the ONLY failing case, which is what proves it
load-bearing rather than decorative. The two fixture guards under
`(VACUUM-HELD-NAMED)` were mutated by removing `tk-sib1` from the held list, so
the fixture no longer produces the released/held split at all: the guard fails
loudly instead of letting the verdict assertion go vacuously green.

One harness defect surfaced and was fixed here: `bad` interpolated `$2`
unconditionally under `set -u`, so a one-argument call aborted the run and every
assertion after it went unreported — a truncated suite that reads as a pass. The
detail argument is now optional.
