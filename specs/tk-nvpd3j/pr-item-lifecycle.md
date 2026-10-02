---
name: PR-item lifecycle — identify, address, validate
description: Design-first proposal (pending operator review) for one reusable, form-agnostic lifecycle every PR item moves through — a review finding or an operator comment, fixed by a commit or by a PR artifact. Gives stage 3 (validate-addressed, resolve, mark) a single owner, normalizes every addressing form to one "addressed" signal, and supersedes PR#925's re-approval close. Folds in the reaction vocabulary and per-batch ledger of tk-fspfp2. Once ruled, its contract folds into specs/tk-ztapg/review-cycle-architecture.md.
---

# PR-item lifecycle — identify, address, validate

**Status: design-first, pending operator review. Nothing here is built or ruled.**

## The decision

Every PR item — an operator comment or a machine review finding — moves through
three stages: **identify** a change is needed, **address** it, **validate** it was
addressed and mark it resolved. Today stage 3 has no single owner: whether an item
closes is inferred per *form* by three separate verbs, and one whole form (a PR
artifact, such as a demo) has no close path at all. That gap left PR#887's demo
objection open ~13h after the demo was delivered, holding the merge, until a human
closed it by hand (visit tk-026mkj).

This design makes stage 3 **one rule, applied the same way regardless of form**:

- **One addressed-signal.** Every addressing form normalizes to the same signal —
  *the fix unit answering the item is closed*. A commit closes it by landing
  (merge-push, today). An artifact closes it by being delivered: `demo-deliver.sh`
  closes the fix unit it answers on successful attach. The delivering action
  becomes the closing action, so the untracked out-of-band delivery that wedged
  #887 cannot happen.
- **One owner.** `gate-ensure.sh` — already the per-pass authority that closes a
  finding when its fix unit lands — becomes the sole owner of stage-3 resolution.
  It resolves every stage-1 item from the one addressed-signal, and marks it
  resolved, uniformly.

This **supersedes PR#925** (tk-umkk4d). #925 keyed objection-close off the human's
*re-approval* of the PR. The operator rejected that (review 5375369005): the demo
being **added** should resolve the ask, not the approval — re-approval is a proxy
for addressing, not the addressing action. #925 was also a fourth form-specific
patch; this is the reusable rule that makes the per-form patches unnecessary.

**What approving this commits to**, in order (each a tracked bead, none dispatched
until you rule here):

1. The artifact bridge — `demo-deliver.sh` closes its fix unit on attach. Smallest
   change, closes the live #887 wedge on its own.
2. The unified stage-3 owner — consolidate resolution under `gate-ensure.sh`; no
   re-approval close is built.
3. The visible marks and the ledger they need — tk-fspfp2, sequenced after 1–2 as
   the lifecycle's output.

Then the ruled contract folds into `specs/tk-ztapg/review-cycle-architecture.md`.

## Scope

**Mandate.** The lifecycle a single PR item travels from the moment a change is
identified to the moment it is marked resolved: the stages, the signal that
advances each, who owns the advance, and the visible mark each stage leaves on the
raising comment — held as one rule across every item form (human or machine
source; commit or artifact fix).

**Boundaries.** How a reviewer *words* a finding and how the validator *rules* its
disposition (must-fix / deferred / declined / needs-you) are the review skills' and
`formulas/mol-validate.toml`'s, unchanged here. The lane state machine, quiescence,
and the merge predicate are `specs/tk-ztapg/review-cycle-architecture.md`'s; this
design extends its fix-unit and validator sections and changes nothing else in it.
The exact GitHub glyph or reply for each mark is tk-fspfp2's mechanism choice,
which the operator has said is tunable.

## The lifecycle — the reusable rule

| Stage | What happens | Signal that advances it | Visible mark on the comment |
|---|---|---|---|
| **1. Identify** | A change is needed — an operator comment, or a machine review finding. A `finding` bead is filed. | A finding exists on the anchor for this comment. | picked-up (`EYES`) |
| **2. Address** | A worker delivers the fix in some form — a code commit, or a PR artifact. A fix unit carries the work. | A fix unit answering the finding is in flight. | being-fixed ("done") |
| **3. Validate** | The owner confirms the item was addressed, closes the finding, and marks it. | The fix unit answering the finding is **closed** (addressed), **or** the finding is moot (its lane re-reviewed clean). | resolved — or awaiting-a-human when the item routed to an open operator visit |

The invariant: **stage 3 re-checks every item that reached stage 1, from one
normalized signal, the same way regardless of the item's form. A fixed item cannot
stay open**, because closing it is an owned act keyed on the addressing action, not
an assumption and not a proxy.

## What already holds — the substrate this reuses

The primitives exist; this design wires them, it does not rebuild them.
(Line numbers orient; re-verify at head.)

- **An item is a `finding` bead** (`assets/scripts/finding.sh`). `finding.source`
  is `machine:<lane>` or `human:<login>`, so one primitive already spans both
  item origins; `finding.comment_id` names the GitHub comment the write-back
  answers into.
- **An addressing action is a `rework` fix unit** (`finding.sh` header; the fix
  unit). It carries a `blocks` edge onto each finding it answers and one onto the
  anchor — the live blocker `merge.sh` reads.
- **One GitHub write-back owner** — `pr-facts.sh`. Stage 1 is live: it stamps
  `WB_REACTION="EYES"` (`pr-facts.sh:318`) on human review bodies, inline threads,
  and top-level Conversation comments. Its resolve/reply sweep keys on the batch's
  rework child being **closed** (`wbrecs`, `pr-facts.sh:2404–2420`).
- **`gate-ensure.sh` already closes a must-fix finding when its fix unit lands**
  (`gate-ensure.sh:669` → `finding.sh close-answered`), run per pass before the
  lane-state and quiescence reads. Its own comment names this "the close
  review-cycle-architecture.md assigns here." It is already the per-pass finding-
  closure authority — the natural, and already-chosen, home for stage 3.

## The gap — what is not codified

Stage 3 is inferred per *form* by separate verbs, with no single owner, and one
form has no path at all. Each claim below was read at head.

- **`close-answered`** (`finding.sh`; called by `gate-ensure.sh:669`) resolves a
  must-fix finding when its fix unit(s) have **landed a commit**. Form: a commit.
- **`close-unvalidated`** (`finding.sh`; called by `signoff.sh:711` on an approve
  verdict) closes an approving lane's still-`unvalidated` findings. Form: a clean
  re-review. This resolution lives in `signoff.sh`, not in the owner.
- **`close-resolved`** — PR#925's proposed verb, keyed on the anchor reading
  **approved at the live head** (the human's re-approval). Form: human re-approval.
  **Rejected** by the operator and absent from main.
- **The artifact form has no close path.** `demo-deliver.sh` attaches the clip and
  **closes no bead** (`demo-deliver.sh:142–151`). An artifact-only fix unit lands
  no commit, so merge-push never closes it, so `close-answered` never fires, so the
  finding sits open holding the merge. This is the #887 wedge (diagnosed in visit
  tk-026mkj: finding `tk-kljbvk` / rework `tk-vsq605` on anchor `tk-vd66j1.3` /
  PR#887, open ~13h until closed by hand).
- **`mol-validate` is the wrong component for stage 3.** Its hard rule
  (`mol-validate.toml:23–25`) is "This pass RULES; it does not re-review," and it
  reads only `unvalidated` findings. It rules a *new* finding's disposition on
  arrival; it never re-checks an item *after* addressing. Stage 3 is a different
  act, and `gate-ensure.sh` already owns it for the commit form.

## The design

### One addressed-signal: the fix unit is closed

Separate the per-form detection of "addressing happened" from the resolution act,
and make every form emit the **same** signal: *the fix unit answering the finding
is closed*. The owner reads one signal; the forms differ only in what closes the
fix unit.

| Fix form | What closes the fix unit (the addressing action) | New work? |
|---|---|---|
| Commit | merge-push closes the rework child when its commit lands on the branch | none |
| Artifact (e.g. demo) | `demo-deliver.sh` closes the fix unit on successful attach | **the artifact bridge**, plus a write-back evidence edit |

This is the symmetry the design rests on: **the addressing action is the closing
action**, whatever the form. A commit's landing is its merge; an artifact's landing
is its delivery. An artifact fix unit carries no commit, so the refinery cannot
close it on merge-push — its delivery is its landing, and the delivery closes it.

Because `close-answered` already reads the fix unit's *closed* status without caring
*how* it closed, the commit and artifact forms collapse into one resolution
derivation with no new resolution verb: once the artifact fix unit closes, the
existing owner resolves the finding.

The write-back that answers the thread, however, is not yet form-agnostic.
`pr-facts.sh` keys its reply off the rework child closing and names the PR's current
head commit as the evidence: it sets the landed OID to the live head for every
closed rework child (`pr-facts.sh:2415`) and posts "Addressed in `<head>` on this
PR" (`pr-facts.sh:2595`). An artifact fix unit lands no commit, so that reply would
attribute the resolution to a commit that did not make it. The artifact form
therefore needs two edits, not one: `demo-deliver.sh` records durable delivery
evidence and closes the fix unit, and `pr-facts.sh` cites that evidence for an
artifact fix unit in place of the head commit.

### One owner: `gate-ensure.sh` runs stage-3 resolution

`gate-ensure.sh`, per reconcile pass, is the sole owner of resolution. It runs one
resolution sweep over the anchor's findings, from two derivations:

1. **Addressed → resolved.** A finding whose fix unit is closed resolves —
   commit or artifact, identically. (This is today's `close-answered`, now reading
   the artifact-closed fix unit too, with no code change to the verb.)
2. **Moot → resolved.** A still-`unvalidated` finding on a lane that now derives
   green (the lane re-reviewed clean, nothing in flight) resolves as moot. (This is
   today's `close-unvalidated`, moved out of `signoff.sh` and triggered by the
   derived lane state, so resolution has exactly one home.)

PR#925's third derivation — resolve on re-approval — is **not built**. Re-approval
is the human's reaction to addressing, not an addressing action; keying on it
resolves an item nothing was shown to have done. The operator's own re-approval,
when it matters, is already a GitHub approval the lane reads for *green*; it is not
a resolution signal for an individual item.

Moving `close-unvalidated` into the owner costs one reconcile pass of latency (a
clean lane's stale findings close on the next `gate-ensure` pass rather than inline
at the approve verdict) and makes `signoff.sh` a pure verdict-recorder with no
finding-resolution logic. This matches the architecture's standing principle that
the reader which computes quiescence is the one that releases it, so the two cannot
disagree (`finding.sh:604–609`).

### The artifact bridge

`demo-deliver.sh` closes the fix unit it delivers for, on successful attach. It
already resolves and pins the origin repo, validates the PR against it, and fails
closed on a bad attach; the additions are: when invoked for a fix unit (a
`task_kind=rework` subject), record the delivered artifact's durable evidence (the
attached comment's URL, which `gh pr comment --attach` returns) on the fix unit,
then close it once the attach returns success. The record is what lets the
write-back cite the artifact: with it on the fix unit, `pr-facts.sh` replies with
the artifact for an artifact fix unit and keeps "Addressed in `<head>`" only for a
commit one, so a resolved thread never claims a commit the fix did not make.

**Residual gap (open question, below): a demo attached by hand** — not through the
fix unit — still closes nothing. The supported path (a worker delivers the artifact
*as* its fix unit) closes cleanly; the hand-attach remains the exception, and
catching it is Option B (a re-reading validation pass), left out of this design on
the operator's steer in visit tk-hpjrr0.

### The visible marks — folding in tk-fspfp2

The per-stage marks are this lifecycle's output. tk-fspfp2 scoped the vocabulary
and the ledger it needs; it is **sequenced here**, as the mark-driving half of the
same rule.

Per raising comment, derived from its finding's batch record:

| Mark | Derivation | Stage |
|---|---|---|
| picked-up (`EYES`) | a finding exists for the comment | identify (live) |
| being-fixed ("done") | a fix unit answering it is in flight (open) | address |
| resolved | the fix unit closed, or the finding is moot | validate |
| awaiting-a-human | the finding is `needs-you` with an open visit | validate (escape) |

GitHub's reaction set has no check or question glyph, so "resolved" and
"awaiting-a-human" are a mechanism choice (a reaction, a short reply, or thread
resolution) — tk-fspfp2's to make, and tunable.

**The ledger extension is the real work in tk-fspfp2.** The write-back drives
reply/resolve off `pr_comment_batch`, a `<disposition>|<floor>|<mark>` record per
batch — but recorded **only in the inline-comment id space** (written at
`pr-facts.sh:1933`, reconstructed at `~2343`). Reviews and top-level Conversation
comments carry only cumulative watermarks (`pr_review_watermark`,
`pr_issue_comment_watermark`) and the single latest `pr_comment_disposition`, with
no per-batch ranges. So a resolved/awaiting-a-human mark on an issue comment cannot
tell which batch it belonged to, and a coarse "apply the current disposition to
every comment below the mark" would flip an older, resolved comment back to the live
state. Driving the marks on reviews and issue comments therefore requires extending
the per-batch ledger to those id spaces — the change tk-fspfp2 already scoped.

## The fold-in into review-cycle-architecture.md

Once ruled, the contract becomes doctrine in `specs/tk-ztapg/review-cycle-architecture.md`,
not per-path code. Two edits, carried by the implementation beads, not applied here
(that doc is ruled; this proposal is not):

- **"The fix unit" section.** State the normalized addressed-signal: a fix unit
  closes when its addressing action completes — a commit by merge-push, an artifact
  by delivery — and the finding resolves off that one signal regardless of form.
  Record that an artifact fix unit's delivery is its landing, and that it carries
  durable delivery evidence so the write-back cites the artifact rather than a
  commit.
- **"The validator" section (stage-3 resolution).** State that `gate-ensure.sh`
  owns stage-3 resolution for every form, from the one addressed-signal plus the
  moot-lane derivation, and that no item resolves on a proxy such as re-approval.

## Implementation sequence — tracked

Design-first: nothing dispatches until the operator approves this spec. Approval is
this design landing — merging the PR closes `tk-nvpd3j` — so the gated hand-off is a
graph edge, not a later manual sling. Each follow-up bead is **blocked-by** its
prerequisite and carries an **armed deferred dispatch** to the polecat pool: when
the prerequisite closes and `bd` reports the bead ready, the arm slings it on
`mol-polecat-work`. Beads 1 (`tk-6mt7li`) and 2 (`tk-5u0ok8`) are blocked-by this
design bead; bead 3 (`tk-fspfp2`) is blocked-by beads 1 and 2, so it waits for both
to land. No bead is routed while its prerequisite is open, and none waits on a human
to remember to sling it.

1. **Artifact bridge** (`tk-6mt7li`) — `demo-deliver.sh` closes its fix unit on
   attach, so the existing owner resolves the finding. Smallest change; closes the
   #887 wedge on its own.
2. **Unified stage-3 owner** (`tk-5u0ok8`) — consolidate resolution under
   `gate-ensure.sh` (move `close-unvalidated`'s trigger to the derived lane state;
   keep `close-answered`); `signoff.sh` becomes a pure verdict-recorder; no
   re-approval close.
3. **Marks + ledger** (`tk-fspfp2`, sequenced after 1–2) — extend `pr_comment_batch`
   to the review and issue-comment id spaces, then drive being-fixed / resolved /
   awaiting-a-human.
4. **Doctrine fold-in** — apply the two edits above to review-cycle-architecture.md
   (carried by beads 1–2 as each lands its half).

**Cost of waiting.** Until bead 1 lands, every artifact-form fix unit repeats the
#887 wedge: it holds its anchor's merge open until a human closes it by hand. Until
beads 2–3 land, resolution stays split across `signoff.sh` and `gate-ensure.sh`, a
re-approval close keeps being tempting for each new form, and the board cannot tell
an item being fixed from one awaiting a person.

## Open questions

- **A hand-attached artifact.** The bridge closes a fix unit delivered *through* the
  fix unit; a demo an operator attaches by hand closes nothing. Option B — a
  validation pass that re-reads the PR and judges whether an attached artifact
  answers the comment — would catch it, at the cost of a re-reading agent pass the
  current validator deliberately avoids. Deferred unless the operator wants the
  hand-attach case covered.
- **The "being-fixed" glyph.** Whether stage 2's mark is a reaction, a reply, or
  nothing until resolution is tk-fspfp2's mechanism choice; this design fixes the
  state and its derivation, not the glyph.
