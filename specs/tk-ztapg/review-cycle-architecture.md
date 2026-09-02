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
validator's decisions, the quiescence rule that serialises dispatch, the
reset triggers, and the change each existing component takes.

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
| `unreviewed` | no full review has run on this lane |
| `reviewing` | a full review is in flight |
| `validating` | the reviewer returned findings and a validation pass is in flight |
| `fixing` | must-fix findings from this lane are open and work is out on them |
| `green` | converged |

**Green survives new commits.** This is the load-bearing rule and the one
reversal from the current design. A push does not move a lane out of `green`,
does not stale it, and does not buy a review. The only thing that returns a
green lane to `unreviewed` is a reset trigger, and there is exactly one of
those.

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
   set is empty.

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

**The interlock is the predicate, not an edge.** That earlier design held the
merge with an open parent-child link from the finding to the anchor. This one
does not, and the difference matters. `merge.sh:303-304` reads both a live
`blocks` blocker and a live `parent-child` child of the anchor into the same
in-flight hold, so a finding attached by an edge of either shape deadlocks the
anchor the moment anyone wants that finding tracked past the merge. The merge
predicate below queries the findings by `anchor_bead` and disposition instead,
which lets a `deferred` finding stay open without holding anything.

The same model absorbs human PR comments. A human comment becomes a finding
with `finding.source=human:<login>`, which is what closes the gap `tk-zina89`
reports: today only machine findings produce work, so a PR converges to
codex-green with the operator's objections untouched.

**Merge is blocked while any must-fix finding is open**, in addition to every
lane being green. A `deferred` finding is a tracked bead that does not block;
a `declined` finding is closed with the validator's reason. Nothing is left as
prose asserting a fix should happen someday, which is the rule `tk-6lgxp` and
`tk-ee7bu` both ask for.

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

The first three are anchor-wide on purpose. Full reviews must not cycle while
sub-reviews are still landing, and a lane that re-reads a diff while a sibling
lane's fix is half-applied is buying the 83.

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

## Reset triggers

**A human feedback batch resets every lane on the anchor to `unreviewed`.**
That is the complete list. A commit does not reset a lane, a rebase does not,
a force-push does not, and a sibling lane's finding does not.

The signal already exists and is already deduped. `pr-facts.sh` records a
`commented` posture against `pr_comment_watermark` and `pr_review_watermark`,
counting only ids authored by a login other than the city's own, and it
advances those watermarks only once the routing it does has read back. A
reconcile every two minutes therefore sees one batch once.

Today that detection resets `signoff.sh`'s review-round cap, by writing
`signoff_rounds_reset=<max_review>.<max_comment>` and letting the next verdict
re-baseline `signoff_round_floor`. The detection is right and the thing it
resets is wrong. **Re-point the same write at the lane states**: set every
`check.<lane>` on the anchor to `unreviewed`, keyed on the same batch id, in
the same single `lifecycle.sh transition` call.

Open must-fix findings are unaffected by a reset. They were true before the
comment batch and they still hold the merge.

## Merge predicate

`merge.sh`'s `hold_gate` becomes two conditions:

1. every lane declared in `check_set` reads `green`
2. no `must-fix` finding on the anchor is open

Condition 1 loses its head comparison, which is the whole of the 211. Condition
2 is new, and it is what makes target 4 true: a PR is not mergeable until every
finding ruled fix-needed has been fixed.

## Component map

Six components carry the design. For each, what it does today and what changes.

| Component | Today | Changes to |
|---|---|---|
| **Reviewer lane** — `formulas/mol-review.toml` | Three steps: pin the dispatch, read the diff, hand one verdict to `signoff.sh`. The verdict decides the gate. | Emits findings as beads and stops deciding green. `approve` becomes "I found nothing", which is path A; anything else is a finding set handed to the validator. `mol-review-quorum` (city `.beads/formulas/`) is the already-built two-lane fan-out for the composability target. |
| **Validator** — new | Does not exist. | New formula and new dispatch. One pass per review batch, the three decisions above, writes `finding.disposition` on each finding and the lane's next state on the anchor. |
| **Gate authority** — `assets/scripts/gate-ensure.sh` | Canonicalizes `check_set`, classifies each `check.<g>` against the live head, dispatches a review per unsettled gate, and backstops runaway dispatch with `GC_MAX_REVIEW_DISPATCHES`. | Reads lane state instead of comparing markers to a head. Enforces quiescence before any dispatch. Drops `live_head_for` from the gate classification, drops `already_answered` (a prior verdict at a commit is no longer the question), and drops the dispatch ceiling, whose only job was to proxy convergence. |
| **Verdict writer** — `assets/scripts/signoff.sh` | The single audited writer of `check.<g>=<verb>@<oid>`. Also files the rework child, counts rounds, and stamps `exception@` at the cap. | Stays the single writer, of lane state and validator dispositions. The round cap, `signoff_round_floor`, `signoff_rounds_reset`, `signoff_cap` and the `reset` verb all retire with judged convergence. The oid-length guard and the moved-head refusal retire with the pin. |
| **Merge predicate** — `assets/scripts/merge.sh` `hold_gate` | First declared gate not `green@<head>`, else merge. | Every lane `green`, and no open must-fix finding. |
| **Reset detector** — `assets/scripts/pr-facts.sh` | Detects a human feedback batch by watermark, routes the comments, and resets the round cap once per batch. | Same detection, same watermarks, same once-per-batch dedup. Resets every lane to `unreviewed` instead. |

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
element is that `gate-ensure.sh` stamps the static default `codex`. Every one
of the 16 open beads in this rig carrying a `check_set` reads exactly `codex`,
so the multi-lane machinery below has never had a second lane to exercise it.
Populating
it is the triage design in `specs/2026-08-review-gates/scope.md`, which is
scoped, unimplemented, and compatible with this one: triage is a lane like any
other, and monotonic widening is orthogonal to how a lane converges.

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

Three claims in epic `tk-bw184o` do not survive checking, and each one changes
what gets carved.

**1. The three identically-titled beads are not duplicate filings.** The epic
cites `tk-gaa5hs`, `tk-p23q7u` and `tk-70vj13` — all titled "Hand the verdict
to signoff.sh — once — then drain", filed across five days — as evidence that
nothing dedupes bug reports, and calls it "the shape of the problem". They are
not bug reports. Each carries `gc.step_ref=mol-review.verdict-and-drain`: they
are **step beads** of three separate `mol-review` pours, and a step bead's title
is the formula step's title, so identical titles are the expected shape. Two of
the three roots (`tk-ldjl37`, `tk-rsxnnz`) are closed with their step chains
still open, which is the husk `tk-1pelsg` already reports and names by id. A
fourth, `tk-yqfr1c`, exists as of 2026-09-02 and is a **live** review in
progress under root `tk-1vsoo9`.

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
- **Does a human feedback batch reset a lane whose reviewer the human never
  read?** The ruling says a batch resets the lane. Whether that means every
  lane on the anchor or only the lanes whose findings the comment touches is
  not settled; this spec takes every lane, on the ground that a comment batch is
  input the branch has never been answered against and the cheap read is the
  safe one.
