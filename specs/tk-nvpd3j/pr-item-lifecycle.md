---
name: PR-item lifecycle — identify, address, validate
description: Design-first proposal (pending operator review) for one reusable, form-agnostic lifecycle every PR item moves through — a review finding or an operator comment, fixed by a commit or by a PR artifact. Gives stage 3 (validate-addressed, resolve, mark) a single owner, normalizes every addressing form to one "addressed" signal, and supersedes PR#925's re-approval close. Folds in the reaction vocabulary and per-batch ledger of tk-fspfp2. Once ruled, its contract folds into specs/tk-ztapg/review-cycle-architecture.md.
---

# PR-item lifecycle — identify, address, validate

**Status: design-first, pending operator review. Nothing here is built or ruled.**

## The decision

Every PR item — an operator comment or a machine review finding — moves through
three stages: **identify** a change is needed, **address** it, and **validate** the
addressing happened, then resolve the item and mark it. Two beads carry an item
through those stages, and keeping them distinct is what the rest of this design
turns on:

- **The finding** is the item (`task_kind=finding`). It opens at stage 1 and holds
  the merge. It closes — is *resolved* — at stage 3, and never before.
- **The fix unit** is the addressing work (a `task_kind=rework` child). It opens at
  stage 2, carries a `blocks` edge onto the finding, and closes when its addressing
  action completes — a commit by landing, an artifact by delivery.

The two closes are ordered by the graph, not a flag: the fix unit `blocks` the
finding, and `bd` refuses to close a blocked issue, so the finding cannot resolve
until its fix unit closes. There is no "ready to close" state between them — "ready"
is "unblocked", which is "the fix unit closed", which `gate-ensure.sh` reads.

Today stage 3 has no single owner: whether a finding resolves is inferred per *form*
by separate verbs, and one whole form — a PR artifact, such as a demo — has no close
path at all. That gap left PR#887's demo objection open ~13h after the demo was
delivered, holding the merge, until a human closed it by hand (visit tk-026mkj).

This design makes stage 3 **one rule, applied the same way regardless of form**:

- **One addressed-signal.** Every addressing form normalizes to the same signal —
  *the fix unit is closed*. A commit closes the fix unit by landing (merge-push,
  today). An artifact closes the fix unit by being delivered: `demo-deliver.sh`
  closes the fix unit it answers on successful attach. The delivering action becomes
  the fix unit's closing action, so the untracked out-of-band delivery that wedged
  #887 cannot happen.
- **One owner.** `gate-ensure.sh` — already the per-pass authority that resolves a
  finding when its fix unit closes — becomes the sole owner of stage-3 resolution.
  It resolves every stage-1 finding from the one addressed-signal, uniformly, and
  drives the mark. What stage 3 does and does not re-check is "One owner" below; the
  short version is that it confirms the addressing *happened* and is not a second
  reviewer of whether the fix is *right*.

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
3. The visible marks and the ledger they need — tk-fspfp2, the lifecycle's output.
   It is scoped here but sits behind its own open operator discussion (tk-sl8sq7),
   so approving this does not dispatch it; it waits on that discussion.

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

Each stage opens or closes one of the two beads; the mark column is the visible
write-back reaction the bead state drives, not a third state the beads carry.

| Stage | What happens | Bead transition | Visible mark on the comment |
|---|---|---|---|
| **1. Identify** | A change is needed — an operator comment, or a machine review finding. | The **finding** opens. | picked-up (`EYES`) |
| **2. Address** | A worker delivers the fix in some form — a code commit, or a PR artifact. | The **fix unit** opens, blocking the finding; it closes when its addressing action completes (commit lands, artifact delivered). | being-fixed ("done") |
| **3. Validate** | `gate-ensure.sh` confirms the addressing happened and resolves the item. | The **finding** closes — because its fix unit closed (addressed), or because its lane re-reviewed clean and the finding was moot. | resolved — or awaiting-a-human when the finding is `needs-you` with an open operator visit |

The finding carries no intermediate stored state: it is open or closed, and the
`blocks` edge from its fix unit is what forbids it closing early. The invariant:
**every item that reached stage 1 is resolved by one owner from one normalized
signal, the same way regardless of form. A fixed item cannot stay open**, because
resolving it is an owned act keyed on the addressing action actually completing —
not an assumption, and not a proxy such as a re-approval.

Stage 3 confirms the addressing *happened*; it does not re-judge whether the fix is
*correct*. That judgement is the validator's convergence call, under "One owner".

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
derivation with no new resolution verb: once the fix unit closes, the existing owner
resolves the finding. This is a resolution keyed on the addressing action completing,
not a re-judgement of the fix — "One owner" states what that does and does not buy.

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

**What stage 3's validation is, and what it is not.** Stage 3 confirms the
*addressing action completed* — that a tracked fix unit for this finding actually
closed — and resolves the finding off that fact. That confirmation has teeth the
pre-design state lacked: a finding cannot resolve unless a fix unit answering it
exists and has closed, so the untracked delivery that left #887 open is no longer a
path, and no proxy — a re-approval, or an assumption that a commit probably fixed it
— can stand in for it. What stage 3 does **not** do is re-read the delivered fix to
re-judge whether it is correct. That is the ruled cycle's design, not this spec's
shortcut: `specs/tk-ztapg/review-cycle-architecture.md` makes fix-correctness a
*convergence judgement* the validator holds, not a per-fix re-read ("there is no path
where a commit landing on the branch changes a lane's state",
review-cycle-architecture.md:168–169). The validator decides whether another
whole-diff review is warranted; if it is, that fresh review re-reads the changed diff
and files a new finding when the fix fell short; if it is not, the lane goes green
when the must-fix set closes, with no re-review. Stage 3 resolves off that ruling and
the fix unit's close. It is the resolution owner, not a second validator.

This is the honest limit to name: on the convergence path the validator can rule a
lane green against the pre-fix head, and the finding then closes when its fix unit
lands, so the delivered fix itself is never re-read against the finding — its
adequacy rests on the fix worker and the validator's convergence bet. If a per-item
re-reading validation is wanted instead — stage 3 re-reads the fix and judges it
against the finding before resolving — that is **Option B** under Open questions, and
it reopens the ruled "no re-review" convergence model. It is left out here on the
operator's steer (visit tk-hpjrr0); it is named as the operator's call, not silently
adopted or discarded.

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
attached comment's URL, which `gh pr comment --attach` returns on stdout) on the fix
unit, then close it once the attach returns success. The record is what lets the
write-back cite the artifact: with it on the fix unit, `pr-facts.sh` replies with
the artifact for an artifact fix unit and keeps "Addressed in `<head>`" only for a
commit one, so a resolved thread never claims a commit the fix did not make.

Addressing runs through the fix unit, which is how work on the PR closes the work
that was requested — the same path a commit takes. A demo delivered as its fix unit
closes that fix unit on attach, exactly as a commit closes its fix unit on landing.

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

**Per-thread answer vs. the holistic all-clear.** The per-thread reply stays with
the fix unit: a commit answers how it answered the thread, a demo answers a demo ask,
a "we did X" answers a requested change — stage 2's output, posted when the fix unit
closes. Stage 3 adds the *collective* signal: when the last finding on the anchor
resolves and every lane derives green, the write-back posts one holistic comment —
the actions taken, everything resolved, the PR ready — the single statement that
stage 3 completed for the whole PR. This builds on the write-back's existing
all-findings-closed arm, which already dismisses a human CHANGES_REQUESTED review and
re-requests the author once every finding of that review closes (`pr-facts.sh`), and
it is tk-fspfp2's to drive. It can start as one comment and grow richer over time;
the design fixes that the signal exists and when, not its final wording.

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
graph edge, not a later manual sling. Beads 1 (`tk-6mt7li`) and 2 (`tk-5u0ok8`) are
**blocked-by** this design bead and each carries an **armed deferred dispatch** to
the polecat pool: when this design lands and `bd` reports the bead ready, the arm
slings it on `mol-polecat-work`, with no human needed to remember the sling. Bead 3
(`tk-fspfp2`, marks + ledger) does not auto-dispatch on this approval: it is
blocked-by beads 1 and 2 and also by `tk-sl8sq7`, an open operator discussion of its
direction, and it is routed to human rather than armed. It becomes ready for the
pool only when the operator settles that gate and beads 1 and 2 have landed. It is
scoped here as the lifecycle's mark-driving half, not promised as part of the
auto-dispatched sequence.

1. **Artifact bridge** (`tk-6mt7li`) — `demo-deliver.sh` closes its fix unit on
   attach, so the existing owner resolves the finding. Smallest change; closes the
   #887 wedge on its own.
2. **Unified stage-3 owner** (`tk-5u0ok8`) — consolidate resolution under
   `gate-ensure.sh` (move `close-unvalidated`'s trigger to the derived lane state;
   keep `close-answered`); `signoff.sh` becomes a pure verdict-recorder; no
   re-approval close.
3. **Marks + ledger** (`tk-fspfp2`, after 1–2 and behind operator gate `tk-sl8sq7`)
   — extend `pr_comment_batch` to the review and issue-comment id spaces, drive
   being-fixed / resolved / awaiting-a-human, and post the holistic all-clear when
   the anchor's findings all resolve and every lane is green. Routed to human and
   not auto-dispatched; it waits on the operator settling `tk-sl8sq7`.
4. **Doctrine fold-in** — apply the two edits above to review-cycle-architecture.md
   (carried by beads 1–2 as each lands its half).

**Cost of waiting.** Until bead 1 lands, every artifact-form fix unit repeats the
#887 wedge: it holds its anchor's merge open until a human closes it by hand. Until
beads 2–3 land, resolution stays split across `signoff.sh` and `gate-ensure.sh`, a
re-approval close keeps being tempting for each new form, and the board cannot tell
an item being fixed from one awaiting a person.

## Open questions

- **A per-item re-reading validation (Option B).** Stage 3 as designed confirms the
  addressing happened; it does not re-read the delivered fix to judge it against the
  finding. A validation pass that did — re-reading the PR and ruling whether the fix
  answers the comment before resolving — would give stage 3 that second check, at the
  cost of a re-reading agent pass the ruled convergence model deliberately avoids
  ("no path where a commit landing changes a lane's state"). It reopens that ruling,
  so it is the operator's call; left out here on the operator's steer (visit
  tk-hpjrr0).
- **The "being-fixed" glyph.** Whether stage 2's mark is a reaction, a reply, or
  nothing until resolution is tk-fspfp2's mechanism choice; this design fixes the
  state and its derivation, not the glyph.
