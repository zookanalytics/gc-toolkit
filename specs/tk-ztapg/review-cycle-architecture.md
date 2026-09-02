---
name: Review-cycle architecture
description: The ruled design for the PR review cycle — per-reviewer lane states that survive new commits, a validator that judges convergence, a quiescence predicate held by one authority, and the component-by-component change list that carries it. Ruled by the operator 2026-09-01 on visit tk-hrapej; implementation is carved under epic tk-bw184o.
---

# Review-cycle architecture

A gate closes when new findings stop arriving, and a validator judges that.
Convergence is judged, not pinned to a commit and not counted in rounds.

## Scope

**Mandate.** The state a PR's reviews carry, who may change it, and what has
to be true before a PR merges. That covers the lane state machine, the
validator's decisions, the quiescence rule that serialises dispatch, what moves
a lane backwards, and the change each existing component takes.

**Boundaries.** The reviewers' own methods are out: what a reviewer reads,
how it words a finding, and which severity vocabulary it uses belong to the
review skills and to `specs/2026-08-review-gates/scope.md`. So is the value
of the fix-now threshold, which this design gives a home and deliberately
leaves unset. Merge mechanics past the gate predicate — squash strategy,
convoy graduation, rebase preparation — stay with `docs/refinery-merge-cadence.md`.

## The problem this replaces

The measured basis, from the sitting on visit tk-hrapej, is 392 gate reviews
spent on 98 anchors in the 8 days after the gc-toolkit rewrite landed.

| Reviews | What they were |
|---|---|
| 98 | the floor: one per anchor |
| 211 | re-read a new head, because the branch grew a commit |
| 83 | re-read a head already reviewed, because two actors disagreed about what was in flight |

Both surpluses come from the same decision: the unit of review state is a
commit oid. `signoff.sh` writes `check.<gate>=green@<oid>`, `merge.sh` holds
until every declared gate reads `green@<live head>`, so every push invalidates
every gate at once and buys a fresh whole-diff review. That accounts for the
211. The 83 are the oid race: a review pinned to a commit the branch has since
rewritten, arriving as a finding against a commit that no longer exists.

Removing the pin retires the 211. One authority plus quiescence retires the 83.

## Lane states

A **lane** is one reviewer, named by one entry in the anchor's `check_set`. An
anchor with `check_set=codex,arch` has two lanes and merges when both are
green.

A lane's state is a state of the lane itself, never a claim about a commit:

| State | Means |
|---|---|
| `unreviewed` | this lane owes a full review |
| `reviewing` | a full review is in flight |
| `validating` | a finding set is in hand and a validation pass is in flight |
| `fixing` | must-fix findings from this lane are open and work is out on them |
| `green` | converged |

**Green survives new commits.** This is the load-bearing rule and the one
reversal from the current design. A push does not move a lane out of `green`,
does not stale it, and does not buy a review. A green lane returns to
`unreviewed` only when the validator rules a fresh whole-diff review warranted,
which is a judgement rather than a trigger.

The state lives on the anchor under the same key the marker uses today,
`check.<lane>`, with a new grammar: one bare state word, no `@<oid>` suffix.
`check_set` continues to declare which lanes exist, and `none` continues to
mean an anchor gated by no lane.

### Two ways a lane goes green

A. **The reviewer found nothing.** The lane passes by definition and no
   validation pass runs. `unreviewed` to `reviewing` to `green`.

B. **The validator ruled no further full review is needed.** The validator may
   still have created must-fix findings. The lane goes green when those close,
   with no re-review. `unreviewed` to `reviewing` to `validating` to `fixing`
   to `green`, where the `fixing` leg is skipped when the validator's must-fix
   set is empty. A human feedback batch joins this path at `validating`, from
   `green` as readily as from `reviewing`, and is ruled on the same way.

There is no third path. In particular there is no path where a commit landing
on the branch changes a lane's state.

### There is no sixth state for a human

A finding that cannot be fixed and needs a person does not park the lane. It
holds the lane at `fixing` and reaches a human through the finding's own
escalation, which is what target 5 asks for. The operator's own hold on an
anchor stays `merge_hold`, which `gate-ensure.sh` already honours and which is
independent of any lane.

This is why `exception@<oid>` retires along with the oid pin. Its one live
purpose was to park an anchor the round cap gave up on, and the round cap goes
with the judged-convergence ruling.

## Findings

A finding is a bead, not a line in a review body. It carries identity
independent of whatever resolves it, because the cardinality is many findings
to one dispatch unit: one work bead may cover three related findings, and when
that worker completes, all three are answered.

| Key | Value |
|---|---|
| `task_kind` | `finding` |
| `anchor_bead` | the gating anchor |
| `finding.lane` | the lane whose review raised it, or `human` |
| `finding.key` | the lane's name plus a normalized locus and message; the dedup handle |
| `finding.disposition` | `unvalidated`, `must-fix`, `deferred`, or `declined` |
| `finding.source` | `machine:<lane>` or `human:<login>` |

`finding.key` is what keeps a re-raised objection from becoming a second bead.
`tk-elc0x` names this shape, and the design it cites is
`specs/tk-zgse0.2/merge-gate-exception-lifecycle.md`, which the rewrite deleted
and which survives only in git history at
`9a6b86ae^:specs/tk-zgse0.2/merge-gate-exception-lifecycle.md`. Its definition
holds: the key is the reviewer's name plus a normalized locus and message, and
re-evaluating a gate that already carries a finding for a key creates no
duplicate. Idempotency is by key, never by evaluation count.

**The interlock is an edge, and the disposition picks its type.** Invariant I1
in `docs/component-model.md` requires that much: no wait lives only in prose or
a metadata string. A merge held by a metadata query alone is a wait the graph
cannot see.

`blocks` is the hold this interlock uses, and not because it is the only edge
that blocks. Three types hold a bead out of `bd ready` — `blocks`, `waits-for`
and `conditional-blocks` — and any of the three would hold the anchor's close,
since `bd` refuses to close a blocked issue. `blocks` is the one that also
holds the merge, because `merge.sh` reads exactly `blocks` downward: a finding
attached by either of the other two would leave the PR free to land with the
finding still open. I1's own detector, `doctor/check-wait-is-an-edge`, counts
only `blocks` as well, but the contrast it draws there is with `tracks` and
`parent-child`, which record a relationship and hold nothing.

| Disposition | Edge | Effect |
|---|---|---|
| `must-fix` | anchor `blocks` on the finding | holds the merge and the anchor's close |
| `deferred` | finding `discovered-from` the anchor | records where it came from, holds nothing |
| `declined` | none | closed with the validator's reason |

A `must-fix` blocker needs no new merge code. `merge.sh` already reads every
live `blocks` blocker of the anchor into its in-flight hold, through a
`gc bd dep list --direction=down -t blocks` probe, and its own comment gives
the rule: a dep-edge holder holds regardless, because the edge is the claim.
`bd` separately refuses to close a blocked issue. An open must-fix finding
therefore stops the anchor closing as well as the PR merging, which is what
makes the merge predicate structural instead of a rule each reader has to
remember.

`deferred` needs an edge outside both sets. `merge.sh` reads `blocks` downward
and `parent-child` upward, and `discovered-from` is neither ready-blocking nor
read by either probe, so a deferred finding stays open across the merge holding
nothing.

The earlier design's mistake was the shape, not the edge. It attached the
finding to the anchor with `parent-child`, which states decomposition and
cascades the anchor's blocked state down onto the finding. I1's shape law is
the general form: a bead that will ever carry a `blocks` edge must have no
`parent-child` children. An anchor blocking on a must-fix finding strands any
parent-child child it has, so the work that answers a finding is filed beside
it and never under the anchor.

### The fix unit

A finding states an objection and holds the merge. It is never dispatched. The
bead that is dispatched is a separate one, the **fix unit**, and the route
lives there. `gc.routed_to` is the pool-offer predicate, so a routed bead is by
construction the thing a worker claims; routing the finding would make every
finding its own claim and contradict the many-to-one cardinality above.

A fix unit carries two `blocks` edges, and each buys something distinct.

| Edge | What it buys |
|---|---|
| fix unit `blocks` every finding it answers | the many-to-one relation, and the ordering: `bd` refuses to close a blocked issue, so no finding closes before the work answering it does |
| fix unit `blocks` the anchor | the route the merge readers already look for |

The second edge is why the progress and quiescence readers take no change.
`merge.sh` records the anchor `progressing` only when some live `blocks`
blocker names a `gc.routed_to` that is neither empty nor `human`, and the fix
unit is exactly that blocker. A finding names no route, so an anchor whose only
must-fix blocker has no fix unit yet reads as a demand nothing is acting on,
which is the true reading. Quiescence asks the same graph one question further
out: a fix unit in flight is a live bead blocking a finding on this anchor.

Closing runs the edges backwards. When the fix unit closes, the findings it
blocked become unblocked, and `gate-ensure.sh`, which already owns lane state
and computes quiescence, closes each finding whose blockers have all closed.
The lane leaves `fixing` when the anchor carries no open must-fix finding.

Today's rework child is already a fix unit in this shape. `signoff.sh` writes
it a `blocks` edge onto the anchor and routes it to the fix-target pool, while
the `pr_number` and `existing_pr` it also stamps name which PR to resume rather
than holding anything. What it lacks is a finding bead on the other side of it,
so the edge it already has is the one this design wants and nothing existing
moves.

The same model absorbs human PR comments. A human comment becomes a finding
with `finding.source=human:<login>`, which is what closes the gap `tk-zina89`
reports: today only machine findings produce work, so a PR converges to
codex-green with the operator's objections untouched.

**Merge is blocked while any must-fix finding is open**, in addition to every
lane being green. Nothing is left as prose asserting a fix should happen
someday, which is the rule `tk-6lgxp` and `tk-ee7bu` both ask for.

## The validator

The validator is the component that does not exist today. It runs one pass per
review batch, where a batch is the finding set one lane's review produced in
one run, and it holds three decisions.

1. **Which findings must be fixed before merge.** The operator's stated
   preference is to fix things when we find them. Deferral is the exception
   and needs a reason, and the ruled reason is that fixing now introduces risk
   or might break something.
2. **Which findings become a tracked bead that does not block the PR** and
   needs fresh implementation once the PR lands.
3. **Whether another full review is warranted** once the must-fix set closes.
   A no here is the second path to green.

Decision 3 is what makes convergence judged. The operator's shape: a first
whole-diff review flags several P1s, a second flags one, a third flags only
minor items. That decay is the signal, and nothing about it is expressible as
a commit marker or a round counter.

Any actual change now takes two agents saying yes, which is target 3: the
reviewer raises, the validator rules must-fix, and only then does work go out.

### Where the threshold lives

The fix-now versus defer threshold is **one knob in one place**: a declared
variable on the validator formula, rendered into the validator's step text at
pour.

The alternative was an environment variable read by a script and defaulted in
code, matching `GC_MAX_REVIEW_ROUNDS` and `GC_MAX_REVIEW_DISPATCHES`. It is
the wrong home here, because the threshold is not a number a script compares
against — it is the policy sentence the validator reasons with. A formula
variable keeps it settable per rig without editing a prompt, and keeps it
visible to anyone running `gc formula show`. A prose paragraph inside the
validator's prompt would be neither.

The value of that variable is deliberately out of scope. Build the surface,
leave the tuning.

## Quiescence

**No full review is dispatched while anything is acting on the anchor.**
Concretely, a lane may not be dispatched while any of these hold:

- a must-fix finding on this anchor is open, on any lane
- a fix unit resolving a finding on this anchor is in flight
- a validation pass on this anchor is in flight
- a full review on this lane is in flight

The fourth clause is what retires the 83: two actors disagreeing about whether
a review was already out is exactly how the same head got read twice, and one
computer of the set cannot disagree with itself.

The first three are anchor-wide for a different reason. They keep a review from
reading a diff that is mid-change. A lane that re-reads while a sibling lane's
fix is half-applied produces findings against a state no one intended to ship,
and the rework that answers them is the no-op kind the declination texts are
full of.

This is exactly the question `tk-j5wrs` raised as unowned — "what is currently
acting on this anchor" — now given a purpose and a single owner. It gets one
definition because one authority computes it. That authority is
`gate-ensure.sh`, arm 1 of the `refinery-reconcile` order, which already holds
the per-rig lock that makes single-flight true.

The three rival dispatchers `tk-j5wrs` catalogued are gone: `check-set-heal.sh`,
`reconcile-gate-verdicts.sh` and `reconcile-merged-prs.sh` are absent from the
checkout. Consolidating dispatchers is not the remaining work, because the
rewrite already did it. The remaining work is the predicate itself, and there
is a specific reason to believe that: **the city had one, and the rewrite
deleted it.**

`tk-vie5k` implemented exactly this — one canonical in-flight membership block,
shared by all five readers, with `anchor_authority()` making `anchor_bead`
authoritative and a drift test that extracted every copy and diffed it against
the canonical one. It landed on 2026-08-23. The canonical copy lived in
`check-set-heal.sh`, and the rewrite deleted that file, its drift test
`assets/scripts/inflight-membership.test.sh`, and every reader that shared the
block, on 2026-08-25. Neither name appears anywhere in the checkout now.

The redundancy rate rose from 1% to 22% across that same boundary. That is
correlation, not a proof of cause, but it is the only structural change to the
in-flight question in the window, and it points the same way the design does:
what is missing is the predicate, not fewer dispatchers.

## What moves a lane backwards

Two things move a lane backwards, and nothing else does. A commit does not, a
rebase does not, a force-push does not, and a sibling lane's finding does not.

**A human feedback batch moves every lane on the anchor to `validating`.** The
batch does not itself buy a full re-review. It is a finding set like a
reviewer's, so it enters the lane where a reviewer's findings enter it, and the
validator's three decisions apply to it unchanged. A comment reporting a
misspelling becomes a must-fix finding, the lane goes to `fixing`, and it
returns to `green` when the fix lands without a whole-diff read being spent on
it. A comment that overturns an assumption the diff rests on is what decision 3
answers yes to.

**The validator ruling a fresh whole-diff review warranted returns that lane to
`unreviewed`.** It is the only path back to `unreviewed`, for human input and
machine input alike, which is the judged-convergence ruling applied to both.

The signal already exists and is already deduped. `pr-facts.sh` records a
`commented` posture against `pr_comment_watermark` and `pr_review_watermark`,
counting only ids authored by a login other than the city's own, and it
advances those watermarks only once the routing it does has read back. A
reconcile every two minutes therefore sees one batch once.

Today that detection resets `signoff.sh`'s review-round cap, by writing
`signoff_rounds_reset=<max_review>.<max_comment>` and letting the next verdict
re-baseline `signoff_round_floor`. The detection is right and the thing it
resets is wrong. **Re-point the same write at the lane states**: set every
`check.<lane>` on the anchor to `validating`, keyed on the same batch id, in
the same single `lifecycle.sh transition` call. The comments in the batch
become findings on the same pass, since a lane sent to `validating` with no
finding set to rule on would stall there.

Open must-fix findings are unaffected by a batch. They were true before it
arrived and they still hold the merge.

## Merge predicate

`merge.sh`'s `hold_gate` becomes two conditions:

1. every lane declared in `check_set` reads `green`
2. no `must-fix` finding on the anchor is open

Condition 1 loses its head comparison, which is the whole of the 211. Condition
2 is not new code. A must-fix finding blocks the anchor by a `blocks` edge and
the in-flight probe already holds the merge on any live blocker, so the graph
enforces it rather than `hold_gate`. It is what makes target 4 true: a PR is
not mergeable until every finding ruled fix-needed has been fixed.

## Component map

Six components carry the design. For each, what it does today and what changes.

| Component | Today | Changes to |
|---|---|---|
| **Reviewer lane** — `formulas/mol-review.toml` | Three steps: pin the dispatch, read the diff, hand one verdict to `signoff.sh`. The verdict decides the gate. | Emits findings as beads and stops deciding green. `approve` becomes "I found nothing", which is path A; anything else is a finding set handed to the validator. `mol-review-quorum` (city `.beads/formulas/`) is the already-built two-lane fan-out for the composability target. |
| **Validator** — new | Does not exist. | New formula and new dispatch. One pass per review batch, the three decisions above, writes `finding.disposition` on each finding and the lane's next state on the anchor. |
| **Gate authority** — `assets/scripts/gate-ensure.sh` | Canonicalizes `check_set`, classifies each `check.<g>` against the live head, dispatches a review per unsettled gate, and backstops runaway dispatch with `GC_MAX_REVIEW_DISPATCHES`. | Reads lane state instead of comparing markers to a head. Enforces quiescence before any dispatch. Drops `live_head_for` from the gate classification, drops `already_answered` (a prior verdict at a commit is no longer the question), and drops the dispatch ceiling, whose only job was to proxy convergence. |
| **Verdict writer** — `assets/scripts/signoff.sh` | The single audited writer of `check.<g>=<verb>@<oid>`. Also files the rework child, counts rounds, and stamps `exception@` at the cap. | Stays the single writer, of lane state and validator dispositions. The round cap, `signoff_round_floor`, `signoff_rounds_reset`, `signoff_cap` and the `reset` verb all retire with judged convergence. The oid-length guard and the moved-head refusal retire with the pin. |
| **Merge predicate** — `assets/scripts/merge.sh` `hold_gate` | First declared gate not `green@<head>`, else merge. | Every lane `green`. The must-fix half takes no change: the existing blocker probe already holds on the finding's `blocks` edge. |
| **Feedback detector** — `assets/scripts/pr-facts.sh` | Detects a human feedback batch by watermark, routes the comments, and resets the round cap once per batch. | Same detection, same watermarks, same once-per-batch dedup. Files the batch's comments as findings and moves every lane to `validating` instead. |

### Beyond the six

Three more places read the marker grammar, and a carve that misses them ships
a design that fails its own integrity checks on the first pass.

- **`assets/scripts/pr-open.sh`** holds a pre-open anchor until
  `check.<g> == green@<head_oid>` for every declared gate, by direct string
  comparison. It takes the same grammar change as `merge.sh`.
- **`doctor/check-gate-integrity`** asserts the marker grammar is
  `green|fixable|exception@<40-hex>`. Its surface clause changes to the lane
  vocabulary.
- **`doctor/check-gate-marker-provenance`** asserts that a green marker names a
  commit some recorded verdict covers. Its entire premise is the oid binding.
  Under this design a green lane names no commit, so the check becomes: a green
  lane names a recorded verdict, and either that verdict found nothing or a
  validator disposition closed its findings.

`check_set` itself needs no new structure. It is already a list, `merge.sh`
already holds until every entry is green, and the reason it is always one
element is that `gate-ensure.sh` is the only writer of the field and stamps a
single declared default, `codex` unless the cadence passes another. No second
lane has ever been stamped, so the multi-lane machinery below has never had one
to exercise it. Populating it is the triage design in
`specs/2026-08-review-gates/scope.md`, which is scoped, unimplemented, and
compatible with this one: triage is a lane like any other, and monotonic
widening is orthogonal to how a lane converges.

## Migration

Existing anchors carry the old grammar. The mapping:

| Existing marker | Becomes |
|---|---|
| `green@<oid>` | `green` |
| `fixable@<oid>` | `fixing` |
| absent | `unreviewed` |
| `exception@<oid>` | `merge_hold` plus a visit carrying the park's reason |

Nothing writes `fixable@` any more — the only writer was
`reconcile-gate-verdicts.sh`, and `gate-ensure.sh` merely reads it — so that
row exists for residue, not for a live path.

Existing rework children stay direct blockers of their anchors. Such a child
already satisfies the shape law and already holds the merge, and the objections
it answers were never separated into beads, so back-filling them would invent
findings carrying no `finding.key` and no validator disposition. The
finding-plus-fix-unit shape starts with the first round the validator runs, and
children in flight at the cutover drain as they are.

## What this retires

Both measured failure modes, and the apparatus built to compensate for them.

- The 211 re-reviews on a new head go, because a commit no longer invalidates
  a lane.
- The 83 same-head duplicates go, because one authority dispatches and
  quiescence forbids a second dispatch while anything is acting.
- The dispatch ceiling stops being a convergence proxy. `GC_MAX_REVIEW_DISPATCHES`
  and its `dispatch_backstop.<g>` escalation exist because a converging PR could
  exhaust its budget on redundant rounds and park on the operator's board as a
  convergence failure that never happened. With the redundancy gone, the
  remaining runaway shapes are reviewer deaths and misfiled children, which are
  liveness problems and belong to the liveness sweep, not to the gate.
- The round cap and its park retire with it, along with the reset verb, the
  floor, and the batch key that re-baselines the floor.

## Deliberately tunable

The fix-now versus defer threshold, the reviewer's severity vocabulary, and the
validator's prompt and guidance. The operator ruled these tunable after the
components are right: "we can tweak the input and guidance for how our validator
acts, how the review agent flags items for possible fix."

## Corrections to the epic's premises

Four claims in epic `tk-bw184o` do not survive checking, and each one changes
what gets carved.

**1. The three identically-titled beads are not duplicate filings.** The epic
cites `tk-gaa5hs`, `tk-p23q7u` and `tk-70vj13` — all titled "Hand the verdict
to signoff.sh — once — then drain", filed across five days — as evidence that
nothing dedupes bug reports, and calls it "the shape of the problem". They are
not bug reports. Each carries `gc.step_ref=mol-review.verdict-and-drain`: they
are **step beads** of three separate `mol-review` pours, and a step bead's title
is the formula step's title, so identical titles are the expected shape. A
fourth bead with the same title, `tk-yqfr1c`, carries the same `gc.step_ref`
under root `tk-1vsoo9`, which is the shape repeating rather than a filing
recurring. Measured 2026-09-02: two of the three roots (`tk-ldjl37`,
`tk-rsxnnz`) were closed with their step chains still open, which is the husk
`tk-1pelsg` already reports and names by id.

The duplicate-filing symptom the epic is built on is a husk-retirement defect
with an open bead of its own.

**2. Three of the four dispatchers are already gone.** `check-set-heal.sh`,
`reconcile-gate-verdicts.sh` and `reconcile-merged-prs.sh` are absent from the
checkout. Every bead whose subject is one of those files describes code that no
longer exists.

**3. Nothing writes `fixable@` any more.** The only writer was
`reconcile-gate-verdicts.sh`. `gate-ensure.sh` reads the verb and treats it as
a gate needing raising; no arm produces it.

**4. The shared in-flight predicate is not missing by omission; it was
deleted.** `tk-ztapg`'s own correction reads the post-rewrite rate rise as
evidence that consolidation was the wrong idea. The stronger reading is in the
"Quiescence" section above: `tk-vie5k` landed one canonical membership block
with a drift test on 2026-08-23, and the rewrite deleted it two days later
along with the file that held it. The rate rose across that boundary. This does
not change the design, which builds the predicate either way, but it changes
how much confidence the design deserves.

## Open questions this design does not answer

- **Who dispatches the validator, and on what trigger?** The natural owner is
  `gate-ensure.sh`, since it already owns quiescence, and the natural trigger
  is a lane entering `validating`. That makes the validator a second dispatch
  shape in the same authority rather than a second authority, which is what the
  one-authority ruling wants. Stated here as the intended shape, not as a ruling.
- **How is a finding's locus normalized?** The recovered design gives the key's
  shape as reviewer name plus normalized locus and message, and the requirement
  this design adds is that the key survives a rebase, which rules out a commit
  oid and a line number. What remains open is what a locus normalizes to when
  the finding is about a file the rework then renames.
- **Does a human feedback batch move a lane whose reviewer the human never
  read?** Whether the batch reaches every lane on the anchor or only the lanes
  whose findings the comment touches is not settled. This spec takes every
  lane, on the ground that a comment batch is input the branch has never been
  answered against, and the cost of the wide read is now one validation pass
  rather than one full review.
