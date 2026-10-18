---
name: Review coverage earns approval — contract, rulings and Feature cut
description: The elaboration of the epic tk-qjdt90g, "Review coverage earns approval". It records the contract the operator ratified at visit tk-laelooy on 2026-10-17, the operator's rulings, and the Feature cut, which gives each unit's bead and what it waits on, places the prose-review bead tk-wigtu9 and names the later Features and deferred items. It also commits the research behind the units: gc-toolkit's review as main carries it, the evidence that the city misses what /code-review finds, the Claude Code review recipe, the superpowers pointers, and what gc-toolkit already does better. Read it to build one of the epic's units or to judge its first checkpoint.
---

# Review coverage earns approval

The operator runs Claude Code's `/code-review` by hand on nearly every PR before
approving, because it keeps finding legitimate issues the city's `correctness`
review did not raise. The epic tk-qjdt90g exists so that the city's automated
review reaches the same bar and the operator can approve on the city's verdict
alone. Adopting the command is not the goal.

The comparison behind the epic found gc-toolkit's review stronger than the
comparators on process integrity: pinned commits, dispatch that is not
authority, a validator, finding beads and a learning loop. It found the review
weaker on what decides finding quality: how the reviewer hunts, how a finding is
proven before it blocks, and how much of the work is re-read each round.

The research comes from the operator's brief of 2026-10-17, kept in the city at
`.gc/agents/mechanik/review-coverage-epic/brief-2026-10-17.md`. Facts about
gc-toolkit's files are read at main `d13df88ca` unless a line names another
commit.

## Scope

**Mandate.** The pack's correctness method, written for any repository. That is
`skills/review-correctness/SKILL.md` and its `rubric-ledger.md`, including how a
correctness review uses finder and verifier subagents. It also covers capturing
review feedback from outside the city so the learning loop reads it as a set. As
later Features the operator has not prioritized, it covers the author-side
self-review and the shape of a rework-round review. The focus is the pack.
gc-toolkit's own `docs/review-correctness.md` is in scope as the proof that the
pack method stays generic.

**Boundaries.** The epic is cut on the review method, not the review machinery.
Two narrow machinery changes are in scope because the method needs them. First,
the findings file and the verdict writer carry the finding contract and the P2
rule. Second, the shared review formula drops its no-subagents line and keeps
only the guardrails every check shares: subagents are read-only, one agent
writes the verdict, and no subagent calls `signoff.sh`. Not the structure of the
review path (what the dispatch records, how a check's skill is loaded), owned by
the review-path redesign (tk-febol6c). Not the merge cadence or gate mechanics
([refinery-merge-cadence.md](../../docs/refinery-merge-cadence.md)). Not the
validator's disposition policy (`formulas/mol-validate.toml`, `defer_policy`),
beyond the P2 rule settled at the contract sitting. Not the pipeline metrics
system, which is its own epic; this epic defines and hand-counts only its own
indicators. Not the demo check's scope (one agent or split), deferred to a
separate discussion. Not the cutover of check-runners to the gctk rig gate,
owned by the gctk rig work (tk-kpanfqm). Not other repositories' review
guidance, which lives in each rig's `docs/review-correctness.md`.

## The contract

The operator ratified each field at the contract sitting, visit tk-laelooy, on
2026-10-17. The epic's `epic_*` metadata carries the same text, stamped as the
operator confirmed each field ([epic-stewardship.md](../../docs/epic-stewardship.md)).
Where this section and the metadata differ, the metadata is the contract.

**Handle.** Review coverage earns approval.

**Hypothesis.** For the operator approving PRs, a correctness review that hunts
with named angles and proves each blocking finding before it blocks makes the
city's verdict trustworthy enough that an independent review of a PR the city
approved finds no blocking issue the city missed.

**Closure condition.** Each check fails today, and the operator can run each one
without opening a child.

1. Running `/code-review high` on the heads of the last ten PRs the city
   approved yields no blocking-grade finding the city's verdict did not raise.
2. Every P0 or P1 in a recent `findings.json` carries a concrete failure
   scenario (the input or state, then the wrong output) and a verification line
   naming the evidence, readable on the posted verdict. On a recent PR whose
   review raised a P0 or P1, its P2s were ruled alongside them.
3. The correctness skill reads as method. It holds the hunting method, the
   finding contract and the verdict shape, and no command in it works out a
   commit, a path or test evidence.
4. Review feedback posted on a PR from outside the city appears as a condensed
   observation bead, and the distiller's pending queue shows it has read them as
   a set.
5. The pack method names no single repository's pitfalls, and gc-toolkit's own
   `docs/review-correctness.md` exists and carries its shell and jq guidance.

**Leading indicators.**

1. **Missed issues.** At each checkpoint, run `/code-review high` on the heads of
   the last ten PRs the city approved. The count of blocking-grade findings the
   city's verdict did not raise trends toward zero.
2. **Precision.** The validator's must-fix share of blocking findings holds or
   rises as finding volume rises, so precision is not traded for recall.
3. **Cost guard, with no target.** Reviews and rework rounds per anchor are read
   against a baseline re-measured when Feature 1 starts. A rise that comes with
   fewer missed issues is the expected price. A rise without it means the new
   passes cost more than they find.

The brief's draft of the third indicator read against the baseline in
[review-cycle-architecture.md](../tk-ztapg/review-cycle-architecture.md): 392
gate reviews on 98 anchors in the 8 days after the gc-toolkit rewrite landed. As
ratified, the indicator has no target, and its baseline is re-measured when
Feature 1 starts.

## The operator's rulings

### From the brief

The operator made these rulings in the brief, and the contract sitting did not
reopen them.

- **Subagents inside a review are allowed.** The "single honest pass, no
  subagents, no persona reviewers" rule in `mol-review` and the "No fan-out"
  line in the dispatch body are to be relaxed. Focused finder and verifier
  passes with clean context are wanted where they add unbiased feedback or
  reduce total tokens. What stays: one verdict per claim, one writer of the
  verdict, every subagent read-only in the review workspace, and no subagent
  ever calls `signoff.sh`. The two-provider quorum formula remains the
  multi-lane shape, and a lane may itself fan out.
- **Generic in the pack, specific in the rig.** The hunting method is written
  for any repository. Language or toolchain specifics go in the reviewed
  repository's `docs/review-correctness.md`.
- **Feedback from outside the city is captured, condensed.** Any review feedback
  added to a PR that the city did not generate becomes an observation, condensed
  rather than the whole record. The capture does not classify the miss. The
  distiller reads the set of tens to a hundred holistically and proposes method
  changes. Small tactical fixes per observation are not the point.
- **The review method is the first Feature.** The author-side self-review and
  the rework-round shape are candidates for later Features and are not
  prioritized now. The brief assumed no order between the capture work and the
  method work, and the contract sitting set one ([below](#at-the-contract-sitting)).
- **Model escalation is wanted, not constant frontier use.** The operator picks
  a model by problem complexity when reviewing by hand, and any selection is
  designed so the city does the same. The brief left its place in the Feature
  cut to this spec, and [Where model escalation lands](#where-model-escalation-lands)
  places it.
- **Metrics are a separate epic.** This epic defines its indicators and builds
  no pipeline.
- **The demo check's scope is deferred.** It is not redesigned under this epic.
- **No capability is deleted to move a measure.** The validator, the finding
  beads, the quorum and the learning loop stay.

### At the contract sitting

The operator ruled these at visit tk-laelooy on 2026-10-17, over two rounds. The
epic's notes carry each ruling as it was made.

- **Where the method lives.** Belongs names the correctness skill and its
  ledger, including how correctness uses subagents. The shared review formula
  keeps only the guardrails every check shares. Since #1262 (tk-2ftpwgr) the
  method lives in the skill and `mol-review.toml` carries the lifecycle. On
  main, `assets/scripts/review-method.test.sh` holds that split. The review-path
  redesign retires the test, and the method-only skill unit carries its guard
  from then on ([below](#what-the-method-units-build-on)).
- **Closure check 3** names the result, a correctness skill that reads as
  method, and no prep script, because the review-path redesign moves the
  gathering of commits, paths and test evidence into the formula's
  load-dispatch step.
- **The hypothesis's signal** is an independent review of a PR the city
  approved that finds no blocking issue the city missed. The brief's draft
  signal, outside feedback that stops arriving, is also met when fewer outside
  reviews happen.
- **The rounds indicator** stays as a cost guard with no target. A goal to cut
  review rounds was ruled invalid on 2026-09-29 (tk-h2s7hj.2), and Feature 1
  can move rounds either way.
- **The guidance boundary** excludes other repositories' review guidance, since
  a unit writes gc-toolkit's own.
- **The gctk cutover** (tk-b0ww25t under tk-kpanfqm, PR #1278) stays a boundary,
  not a member, and lands first.
- **The P2 rule.** A P2 is done when the PR is going back for a rework round
  anyway, and nothing sends a PR back when only P2s remain. In the first case
  its P2s are filed with the blocking findings, and the validator rules each
  one. A low-risk, net-positive P2 is must-fix in that round. A risky or
  marginal one is declined, never deferred, because a follow-up PR for a minor
  improvement costs the operator an approval. When only P2s remain, the review
  approves, and the P2s are recorded in the verdict and `findings.json` but
  neither filed nor fixed. The operator called this "a good balance".
- **The finding contract's storage.** The scenario, the verification line, the
  category and the severity are separate `findings.json` fields. The verdict
  writer carries them onto the finding outside its dedup key. That key is the
  lane plus a hash of the normalized locus and message
  (`assets/scripts/finding.sh:216-228`), so a scenario carried inside the
  message would change the key every round and file a twin of each re-raised
  objection.
- **Outside feedback** is classified by the mark first, then by login. A post
  carrying the city's mark is the city's, and the mark is any marker that
  `gc_city_marked` in `assets/scripts/pr-post.sh` matches
  ([below](#gc-toolkits-review-as-main-carries-it)). A post from any login
  other than zook-bot is outside. An unmarked zook-bot post is outside only
  when it is `/code-review` output signed by Claude. Any other unmarked zook-bot
  post is the city's: it is skipped, and flagged when it is recent. The
  operator runs `/code-review` as johnzook almost always and can keep it that
  way. The rule differs on purpose from `gc_city_own` (`pr-post.sh:83`), the
  definition `pr-facts.sh` uses to find the feedback a PR owes an answer.
  `gc_city_own` decides an unmarked post under the city's login by when it was
  posted: the city's own before the PR's provenance cutover, and feedback after
  it. The ruling decides that post by what it is, `/code-review` output or not.
  So the capture classifies a post by `gc_city_marked`, the login and the
  `/code-review` signature, and uses `gc_city_own`'s cutover test only to tell
  which unmarked city post is recent enough to flag.
- **The back-fill** is one run over the last 30 days with the per-run cap
  lifted, and one condensed observation per outside comment. The operator
  accepted that unit as the sitting framed it (round 1, item 14, on the epic's
  notes). Its reason is the dedup key, which is an observation's provenance
  and its category. The provenance names the comment, and the capture
  classifies nothing, so every observation it files from one comment would
  carry the same key. Dedup would keep the first of them and drop the rest
  unread, which is the loss tk-wsg12v describes. One observation that condenses
  the whole comment and links it leaves dedup nothing to drop. Within a
  pattern, a comment that raises eight findings counts as one occurrence
  whichever unit the capture files, because the distiller counts a pattern's
  occurrences by distinct provenance (`formulas/mol-feedback-distiller.toml`,
  step 3).
- **The verifier** is a subagent or a separate pass, whichever the reviewing
  provider supports. Reviews run on the polecat-codex pool
  (`assets/scripts/refinery-reconcile.sh:89`), so the verify-or-demote unit
  checks what codex offers.
- **Sequencing.** The method units wait for the review-path redesign (design
  convoy tk-gaklsnk) to reach main, because it reshapes the same files.
  gc-toolkit's own guidance and the outside-feedback capture start at once,
  because main already appends a rig's `docs/review-<check>.md`, read at the
  reviewed commit (`assets/scripts/review-dispatch-body.sh:199-215`). The gctk
  cutover lands first.
- **#1217** (tk-gfb2hbq) is on the operator's hold until things are stable, and
  the operator will then have it update itself. This epic neither folds it in
  nor drops it.
- **Membership.** tk-wigtu9 moves into this epic from the parked review-gates
  epic tk-yx2oqr, and this spec places it. tk-mzevki5, the miner reading the
  upstream repository instead of origin, folds into the capture unit: it carries
  an `until` edge onto tk-qjdt90g.3 and closes when that lands.
- **Priority** is P1.

### Open, and not this epic's to answer

The operator tabled one question in mechanik's chat on 2026-10-17: is a branch
that edits a method skill reviewed under its own method or under main's? It
bears on the units that edit the correctness skill, and it stays with the
operator.

## The Feature cut

### Feature 1: the review hunts and proves

Every unit is a filed member of the epic. Each one not routed now is armed: it
has a `blocks` edge onto each bead it waits on, and a deferred dispatch to the
polecat pool that slings it once nothing holds it. That is the operator's
condition for landing this spec ahead of the units it describes.

| Bead | Short name | Brief's unit | What it changes | Waits on | Answers |
|---|---|---|---|---|---|
| tk-qjdt90g.1 | review-coverage elaboration | | This spec. | nothing | |
| tk-qjdt90g.2 | gc-toolkit review guidance | U1.7 | gc-toolkit's own `docs/review-correctness.md`: its shell and jq pitfalls, the shell blocks in formula prose, and the marker-fenced block convention, each grounded where it bit or where a guard exists for it. | nothing, and routed now | closure check 5 |
| tk-qjdt90g.3 | outside feedback capture | U1.8 | The feedback miner files one condensed observation per review comment from outside the city, classified as ruled above, and every city writer is checked for its mark. The distiller gains the rule that reads these observations as a set. A one-time 30-day back-fill runs. tk-mzevki5 folds in. | nothing, and routed now | closure check 4 |
| tk-qjdt90g.4 | finding contract | U1.1 | Every finding carries a failure scenario, every blocking one a verification line, and each its category and severity, as `findings.json` fields that `signoff.sh` carries outside the finding key. The P2 rule lands in `signoff.sh`'s filing and the validator's ruling text. | the redesign, the elaboration, the gctk cutover, the method-only skill | closure check 2 |
| tk-qjdt90g.5 | hunting angles | U1.2 | The single Correctness bullet becomes named angles: line-by-line with the enclosing function read, a removed-behavior audit, the cross-file tracer, a language-pitfall specialist fed by the rig's guidance, and wrapper and delegate correctness. The ledger anchors the angles move are amended. | the redesign, the elaboration, the finding contract | closure checks 1 and 5 |
| tk-qjdt90g.6 | verify or demote | U1.3 | A clean-context verifier checks each candidate P0 or P1 and returns CONFIRMED, PLAUSIBLE or REFUTED, and a refutation quotes the line that proves it. A refuted candidate does not block, and its refutation stays in the trail. | the redesign, the elaboration, hunting angles, the subagent policy | closure checks 1 and 2 |
| tk-qjdt90g.7 | fresh-eyes sweep | U1.4 | One fresh pass after dedup looks only for what the first passes missed: moved code that dropped a guard, setup and teardown asymmetry in tests, flipped config defaults, and second-tier footguns. | the redesign, the elaboration, hunting angles, verify or demote | closure check 1 |
| tk-qjdt90g.8 | subagent policy | U1.5 | No review text forbids subagents. The correctness skill says when a finder or verifier adds unbiased feedback or saves tokens, and that it receives the diff and the relevant files, not the reviewer's whole context. The shared formula and the quorum lanes keep only the shared guardrails. | the redesign, the elaboration, hunting angles | the second machinery change in Boundaries |
| tk-qjdt90g.9 | method-only skill | U1.6 | Whatever mechanics the correctness skill still carries move into the gathering the redesign puts in place, building on the values the pour fills in. Its test also carries the guard the redesign retires: it fails when either review formula names a test or a suite, a grade, the Verification line or a What to check dimension. | the redesign, the elaboration, the gctk cutover | closure check 3 |
| tk-wigtu9 | prose terminus | | The correctness method says what blocks on a prose deliverable, and what the test evidence is when a diff touches no suite ([below](#tk-wigtu9-the-prose-terminus)). | the redesign, the elaboration, the gctk cutover, the finding contract, verify or demote, the fresh-eyes sweep | indicator 2, on prose diffs |

"The redesign" is design convoy tk-gaklsnk reaching main. Its design, tk-zif1d8u,
is PR #1277 onto `integration/tk-gaklsnk`, and its build, tk-nuctjl8, waits on
that design. "The elaboration" is this spec. "The gctk cutover" is tk-b0ww25t,
PR #1278, reaching main. The other names in the column are units of this table.

Every method unit rewrites `skills/review-correctness/SKILL.md`, so they land
one at a time. Each waits on the one before it, in this order:

1. The method-only skill. It goes first so that its guard on the split holds
   while the other units edit the skill and the review formula.
2. The finding contract. Every later unit is written in its fields.
3. Hunting angles. Each finding names the angle that found it in the
   contract's category field.
4. The subagent policy. It lifts the no-subagents rule and sets the guardrails
   that verify or demote and the sweep run under.
5. Verify or demote. It checks the candidates the angles raise.
6. The fresh-eyes sweep. It runs after the angles' output is deduped, and its
   findings go through the contract and the verifier.
7. The prose terminus. It is stated in the terms of the contract and the
   verifier.

Verify or demote and the sweep also wait on hunting angles directly, so the
angles land first even when a unit between them is closed without landing.

The Feature's checkpoint reads the missed-issue sample, the validator's must-fix
share, and three posted verdicts against the new contract.

#### What the method units build on

The redesign changes the files the method units edit. Its design names each
overlap in section 9 of `specs/tk-zif1d8u/review-path.md`, which is on PR
#1277's branch and not yet on main:

- It deletes `assets/scripts/review-dispatch-body.sh`, with its "No fan-out"
  line, and writes no subagent text of its own. The subagent policy unit then
  relaxes one rule, `mol-review`'s, and adds what the quorum lanes lack.
- Every review step names the values the pour fills in, and load-dispatch
  gathers the anchor, the PR, the worktree and the rig's guidance. The
  method-only skill unit builds on those values rather than deriving them again.
- The check skills get uniform headings, so the finding contract, the angles,
  verify or demote and the sweep edit the correctness method under headings
  that do not move again.
- A rig's `docs/review-<check>.md` is read at the reviewed commit by
  `review-checks.sh --extension`. That read is the delivery half of the
  gc-toolkit guidance unit.
- It retires `assets/scripts/review-method.test.sh` (section 8 of the design).
  That test's (NEUTRAL) cases are what fail today when a test or a suite, a
  grade, the Verification line or a What to check dimension comes back into
  either review formula, and none of the design's new tests checks for those.
  The method-only skill unit carries that guard in its own test. It is the
  first method unit to land, so the guard is back before any other unit edits
  the skill or the formula.

The gctk cutover, PR #1278, rewrites the correctness skill's
`review-test-evidence` block and the prose around it to read the gctk rig
record at the pinned commit, and retires the `self_review_passed_sha` stamp
that the block reads today. It also adds the gctk binary to `mol-review`'s
workspace block, and moves the setup, pre-flight and self-review runs of
`mol-polecat-work` onto `gctk rig`. The method-only skill unit starts from the
block as the cutover leaves it. That unit, the finding contract and the prose
terminus each wait on the cutover reaching main, so the cutover lands ahead of
the method units even when the redesign reaches main before it.

### tk-wigtu9: the prose terminus

**The gap.** `correctness` is in the forced baseline of every anchor that does
not opt out (the `review-checks.toml` header), and
`assets/scripts/refinery-reconcile.sh:95` sets the default check set to
`correctness,triage`. So every docs-only or spec-only change is graded by the
correctness method, and that grading is shaped for code. Until the gctk
cutover (#1278) lands, Settle the test evidence counts the anchor's self-review
stamp only when it names the reviewed commit and the rig declares a test
command, and otherwise runs the suites the diff touches. Once it lands, the
step reads the gctk rig record at the reviewed commit, and with no record, or
with a pass that ran nothing, it runs the suites the diff touches. A prose diff
may touch no suite, and then the step yields no evidence either way, and the
skill does not say what the Verification line records. What to check opens
with Intent, and its first dimension of substance is Correctness: bugs,
reachable edge cases, error handling. P1 is "wrong behavior on a reachable
input", and on a document about work that is not built, every interleaving a
reader imagines meets that definition. The grading has no point at which it
runs out of findings.

**What the gap costs now.** When tk-wigtu9 was filed on 2026-08-26, two
signal-loom docs-only branches, sl-bgmuy (PR#552) and sl-kg9z6.1.2 (PR#559), had
exhausted a round cap of 3, whose terminal action was an operator ticket. The
round counter has since been retired. The
[review-cycle architecture](../tk-ztapg/review-cycle-architecture.md) of
2026-09-02 gave convergence to the validator, and since #825 (2026-09-21) each
machine request-changes batch opens a validation pass, whose ruling that no
further review is warranted ends the lane (`assets/scripts/signoff.sh:670-682`).
PR #1220, a gc-toolkit spec, shows the current shape: correctness raised findings
over several rounds, the validator ruled each one must-fix, and the lane
converged on the validator's ruling. So a prose review now ends, but on the
validator's judgment rather than on the method's own grading. What the gap still
costs is each finding the method raises on prose and should not: it takes a
validator ruling, and one ruled must-fix takes a rework round and another
review.

**The direction.** The bead's first reaction, on 2026-10-04, offered three
directions: a terminus fix in the shared rubric now, a prose home in triage
later, or a second `mol-review` mode. Read against main, only the first stands.

- **A terminus in the correctness method, in Feature 1.** Since #1262 the
  grading lives in `skills/review-correctness/SKILL.md`, which Feature 1
  rewrites, so the terminus fix is a change to the correctness method. The
  finding contract and verify or demote carry most of it. On a prose
  deliverable, a blocking finding's failure scenario names the text, the reader
  who acts on it, and the wrong action or false belief that follows on the tree
  as merged. The verifier confirms or refutes it by reading the tree. The unit
  writes what those two leave open, along these lines:
  - What blocks on prose: a claim about the tree that the tree contradicts, an
    instruction that does the wrong thing when followed as written, and a
    behavior the text commits to that fails on a reachable case.
  - What does not: a failure that depends on how work the text leaves open is
    later built. That is a P2 at most, or a note for the unit that builds it.
  - The test evidence for a diff that touches no suite: there is nothing to run,
    and the Verification line says so.
- **A second `mol-review` mode** has nothing to switch. `mol-review` carries no
  grading since #1262. On main, the (NEUTRAL) case of
  `assets/scripts/review-method.test.sh` fails if a grade or a What to check
  dimension comes back into it. The redesign retires that test, and the
  method-only skill unit, the first method unit to land, carries the same guard
  in its own test ([above](#what-the-method-units-build-on)).
- **A prose home in triage** needs a way for triage to take `correctness` off
  an anchor, and main has none. Triage only widens `check_set`, and the triage
  waiver that [the review-gates scope](../2026-08-review-gates/scope.md)
  allowed for checks marked waivable was never built. The one narrowing main
  has is a `check_set` of `none` or `off`, which only a person sets and which
  opts the anchor out of every review
  (`assets/scripts/bring-current-guard.sh:56-58`). Building one for triage is
  the structure of the review path, which the epic's boundaries leave to the
  review-path redesign.

The direction keeps the constraint of the 2026-08-24 ruling that the bead names:
nothing selects a review mode by reading the diff in a dispatcher. There is no
mode. One method grades prose and code, each finding against its own failure
scenario.

**Placement.** tk-wigtu9 is in Feature 1, because the gap is in the grading,
which Feature 1 changes. The later Feature on rounds changes what a re-review
reads, and would leave a fresh whole-diff review of prose as open-ended as it is
now. tk-wigtu9 waits on what the other method units wait on, the redesign and
this spec. It waits on the gctk cutover too, because it says what the test
evidence is when a diff touches no suite, and the cutover rewrites how that
evidence is read. It also waits on the finding contract (tk-qjdt90g.4) and
verify or demote (tk-qjdt90g.6), because its terminus is stated in their terms,
and it is the last method unit to land, after the fresh-eyes sweep
(tk-qjdt90g.7). Like the other method units, it is armed to the polecat pool.
Its title, description and takeaway carry this direction, and its filed body is
in the bead's history.

### Where model escalation lands

The brief left this to the spec. It lands in the later Features below, not in
Feature 1. In *Rounds cost what they change*, the depth triage records selects
the reviewer's model tier, and in *The author catches it first*, the last
self-review attempt escalates. Feature 1 reviews on the model the review pool
runs today, because its checkpoint reads the missed-issue count against a change
of method alone. A model change in the same Feature would leave that count
unable to say whether the method or the model moved it.

### Later Features, not prioritized and not filed

They are filed as children only when the operator asks.

- **The author catches it first.** A bug fix carries a regression test that
  fails on the pre-change code, a red-green rule in implement. Self-review gains
  spec compliance against the bead (Missing, Extra, Misunderstood) and writes a
  verification record on the work bead that the reviewer reads as unverified
  claims. The last self-review attempt escalates to a stronger model or the
  other provider instead of handing back to the witness. The superpowers
  task-reviewer and re-review prompts are the model.
- **Rounds cost what they change.** A rework round's review receives the open
  finding beads and the fix diff from the previous `reviewed_oid`. It rules each
  finding ADDRESSED or NOT ADDRESSED with evidence, and reviews only the fix
  diff for new breakage. Triage records a depth on the anchor from diff size and
  paths, and the depth selects the angle count, verify, the sweep and the model
  tier, with the frontier model for a deep review and for any round after a
  failed one.

### Deferred, named so they are not lost

- The demo check's scope: visual review and analysis in one agent, or split.
- Retried-then-passed test runs, recorded as observations.
- A "no suite names this changed script" self-review finding, using the
  affected mapper in `tools/run-tests.sh` (`--affected`).
- Consuming gctk rig records in the correctness arm. PR #1278 (tk-b0ww25t) does
  this, since it rewrites the `review-test-evidence` block to read
  `gctk rig test --check` at the pinned commit. Once it lands, nothing of this
  item is left deferred.

## What waiting costs

This spec lands ahead of most of its units, which is legitimate while a filed,
armed bead carries each one. Until the units land:

- **The operator reviews by hand.** Nearly every approval still costs a
  `/code-review` run, because the city's verdict alone does not reach the bar.
- **A blocking finding need not prove itself.** Nothing requires it to name a
  failure scenario or a verification, so the validator and the operator
  re-derive whether it is real.
- **A P2 beside a blocking finding goes unruled.** A P2 rides on the verdict as
  a non-blocking note and is never filed
  (`skills/review-correctness/SKILL.md:144-147`), so the round it rides into
  neither fixes it nor declines it on purpose.
- **Outside feedback reaches the learning loop only by chance.** The miner drops
  ordinary review of the diff (`formulas/mol-feedback-miner.toml:170-176`), and
  an operator's `/code-review` finding is written about the diff. One reaches
  the loop only when the miner reads a standing lesson into it anyway, or when
  the worker answering it files an observation of its own. The evidence behind
  tk-0rhvews came both ways: the miner filed tk-jijs5mc from an inline finding
  the operator posted on #964, and the worker answering #1117 filed tk-zcv9gp3.
  This lasts until the capture unit lands, and that unit runs now.
- **A prose review ends only on the validator's ruling.** Each finding the
  method raises on prose and should not costs a validator ruling, and one ruled
  must-fix costs a rework round, until tk-wigtu9 lands.
- **The method units wait on the redesign and the gctk cutover.** They start
  once tk-gaklsnk's build and tk-b0ww25t reach main. Building them first would
  have the redesign reshape a skill they had just rewritten, and would leave the
  method-only skill unit deriving values that the redesign's step text carries.
- **The method units land one at a time.** Feature 1 takes one review cycle per
  method unit, in sequence. Building them side by side would have several
  branches rewrite one skill at once, some of them written against structure an
  earlier unit had not yet defined.
- **The split goes unguarded for a while.** From the redesign reaching main
  until the method-only skill unit lands, nothing fails when a grade or a What
  to check dimension comes back into a review formula. No other method unit
  runs in that time.

## The research behind the units

The brief's research was done in a separate session against the gc-toolkit
checkout, the obra/superpowers repository and the review recipe bundled inside
Claude Code. Its facts about gc-toolkit are re-read below at `d13df88ca`, since
the tree has moved after the brief was written. The Claude Code recipe is
re-read from the binary, as its section says. The other comparator appendices
are carried as the brief recorded them.

### gc-toolkit's review as main carries it

- **The correctness method** is `skills/review-correctness/SKILL.md`. It reads
  the whole diff, settles the test evidence with the `review-test-evidence`
  block (`:24-54`), and works What to check (`:56-132`): Intent, Correctness,
  Contract, Testing, Readiness, Comments, the PR as published, and the
  work-quality standards. It grades every finding P0, P1 or P2 (`:134-147`) and
  shapes the verdict body, which ends with the Verification line (`:149-158`).
  The Testing dimension already has the reviewer run each new case against the
  pre-change code (`:76-80`). `rubric-ledger.md` beside it holds the anchors of
  the adopted review-rubric amendments.
- **The review formula**, `formulas/mol-review.toml`, carries the lifecycle every
  check shares: the pins, the workspace, `findings.json` and the one
  `signoff.sh` call. A finding out of scope for the diff is filed as a bug after
  a duplicate probe (`:226-231`). Its hard rules include the single honest pass,
  with no subagents doing the review and no persona reviewers, and name the
  two-provider quorum as the multi-lane form (`:31-36`).
  `assets/scripts/review-method.test.sh` holds the split: its (NEUTRAL) case
  fails if a test, a grade, the Verification line or a What to check dimension
  comes back into either review formula. The redesign retires that test
  ([What the method units build on](#what-the-method-units-build-on)).
- **The dispatch note**, `assets/scripts/review-dispatch-body.sh`, composes the
  reviewer's prompt. For `mol-review` it prints "One agent, single pass. No
  fan-out" (`:79-81`). It names the check's skill for each declared check
  (`:153-155`), and appends the rig's `docs/review-<check>.md` read from the
  commit under review (`:199-215`). gc-toolkit carries no
  `docs/review-correctness.md`.
- **The check index**, `review-checks.toml`, declares correctness, triage, demo,
  arch and pm. Its header puts correctness and triage in the forced baseline of
  every anchor that does not opt out, and lets triage widen `check_set` to any
  declared check and invent none. Triage widens `check_set` and chooses no
  depth and no model (`skills/review-triage/SKILL.md`).
- **The findings file** is a JSON array with one object per blocking finding,
  each a rebase-stable `locus` and a `message`, and `[]` on approve
  (`assets/scripts/signoff.sh:104-110`). On request-changes `signoff.sh` files
  each one through `finding.sh upsert` under the check's lane (`:235-253`),
  deduped on its finding key (see the finding contract's storage, under
  [At the contract sitting](#at-the-contract-sitting)). A P2 is not filed.
- **The validator**, `formulas/mol-validate.toml`, rules each finding must-fix,
  deferred, declined, needs-you or restates (`:200`), and judges whether a fresh
  whole-diff review is warranted. It does not re-read the diff (`:28-30`).
  Must-fix is the default for a real finding, and a cosmetic, already-handled or
  mistaken one is declined, never deferred (`:66-71`). It carries its own
  single-pass rule, one agent with no subagents (`:31-32`), and no unit of this
  epic changes that rule. The subagent policy relaxes the review's rule, not
  the validator's, and the finding contract adds the P2 rule to the validator's
  ruling text.
- **The quorum**, `formulas/mol-review-quorum-signoff.toml`, runs two lanes on
  two providers, each writing a `review-quorum.lane.v1` object, and a synthesis
  that makes the single `signoff.sh` call (`:16`, `:207`). The lanes carry no
  subagent rule.
- **The feedback miner**, `formulas/mol-feedback-miner.toml`, reads the inline
  review comments, issue comments and review bodies of the PRs merged or closed
  in its window, with each author's login (`:157-162`), and filters on no
  author. Its window defaults to 3 days (`:38-41`), and it files at most 10
  observations a run (`:43-46`). It keeps only corrective feedback about
  standing behavior and drops ordinary review of the diff (`:170-176`).
  Observations dedup on provenance and category.
- **The city's mark** is any marker that `gc_city_marked` in
  `assets/scripts/pr-post.sh` matches (`:72-76`). One is `<!-- gc:city -->`,
  which pr-post.sh writes on every post it makes (`:57`). The others are
  purpose markers only the city writes: `<!-- gc-writeback -->` on a write-back
  reply (`assets/scripts/pr-facts.sh:496`) and `<!-- gc:visit:` on a visit
  comment (`assets/scripts/pr-visit-comment.sh:147`). `gc_city_own` (`:83`)
  adds the login and the PR's provenance cutover to that test to pick out the
  city's own posts, and `pr-post.sh own-def` prints both definitions for a
  reader to prepend.
- **The learning loop's review-rubric carrier** amends What to check in
  `skills/review-correctness/SKILL.md`, one dimension per amendment, anchored in
  `rubric-ledger.md` (`skills/learning-distill/SKILL.md:123`, `:159`).
- **Self-review**, the `self-review` step of `formulas/mol-polecat-work.toml`, is
  a check loop of fresh sessions, three attempts in all (`:1253-1260`). It
  stamps the passing head as `self_review_passed_sha` (`:1228`), which the
  correctness method reads as test evidence. The implement step has no
  test-writing rule.
- **Review routing.** The merge cadence routes review beads to the polecat-codex
  pool (`assets/scripts/refinery-reconcile.sh:89`).
- **Rework.** A request-changes verdict files a rework child and opens a
  validation pass on its lane (`assets/scripts/signoff.sh:670-682`). The next
  round is a fresh whole-diff review of the new head, once the validator rules
  that one is warranted.
- **gctk rig checks** record each check run against the commit it ran at, and a
  record answers only a later call that declares the same run
  ([rig-checks.md](../tk-1hazlo2/rig-checks.md)). The cutover, tk-b0ww25t in PR
  #1278, moves every check-runner onto those records and retires
  `self_review_passed_sha`.

### How the units moved from the brief's candidates

The brief proposed Feature 1's units before the tree moved. The filed units
differ where main or the sitting did:

- The brief's U1.6 was a review prep script that would package the review's
  mechanics. The redesign puts that gathering in the formula's load-dispatch
  step and the values the pour fills in, so U1.6 is the method-only skill, which
  moves whatever mechanics remain into that gathering.
- U1.5 named the dispatch body's "No fan-out" paragraph. The redesign deletes the
  dispatch body, so U1.5 rewrites `mol-review`'s rule, writes how the
  correctness skill uses subagents, and gives the quorum lanes the guardrails.
- U1.1 carried P2s into `findings.json` with dedup unchanged. The sitting made
  the scenario, the verification line, the category and the severity separate
  fields outside the finding key, and added the P2 rule.
- U1.8 back-filled "as far as the miner's window allows", which is 3 days. The
  sitting made the back-fill one 30-day run with the cap lifted.

### Evidence that the city misses what /code-review finds

- The contract sitting's brief cites tk-sc8fqnt and tk-9f6c7k0, which address
  `/code-review` findings the city's review missed on #1076 (merge.sh's UNKNOWN
  re-read) and #1077 (the reconcile arm's pacing).
- tk-0rhvews records an operator-run review of #1117, posted under the city's
  account, in which three of the four `merge.test.sh` cases the PR added passed
  against the pre-change `merge.sh`. The city's pre-open signoff had approved
  the same commit. Its rule is the Testing anchor in `rubric-ledger.md`. That
  review is also the case the outside-feedback rule's `/code-review` clause
  covers: an unmarked zook-bot post of a Claude Code review.

### The Claude Code review recipe, condensed

Taken from the `/code-review` skill bundled inside the Claude Code binary,
which has no file on disk, and read from the text embedded in Claude Code
2.1.302 on 2026-10-18. Which phases a tier runs depends on the session's model
family, so the phases are described in their fullest form, and the tiers say
where each one runs. The brief adds that the hosted Code Review service and
ultrareview follow the same shape with an independent reproduce step, which the
local binary does not show.

- **Phase 0.** Gather the diff: the committed range plus the working tree.
- **Phase 1, finders.** Independent angles, each emitting candidates with
  `file`, `line`, `summary` and `failure_scenario`. Finders must pass every
  candidate with a nameable failure scenario; silently dropping half-believed
  candidates is named as the dominant cause of misses. The angles: A,
  line-by-line with the enclosing function; B, the removed-behavior auditor; C,
  the cross-file tracer (callers and callees); D, the language-pitfall
  specialist; E, wrapper and proxy correctness; then reuse, simplification,
  efficiency, altitude (root cause at the right depth), and conventions (quote
  the exact CLAUDE.md rule and the exact line). The eight-angle tiers leave out
  D and E.
- **Phase 2, verify.** Dedup on the same defect, the same location and the same
  reason. One verifier per candidate returns CONFIRMED (it can name the
  trigger), PLAUSIBLE (the mechanism is real and the trigger uncertain, which
  high makes the default for races and rare paths), or REFUTED (factually wrong
  with the line quoted, provably impossible, already guarded in this diff, or
  pure style). CONFIRMED and PLAUSIBLE are kept. Only a tier that runs its
  finders as subagents verifies. A tier built to run its angles in one context
  dedups only, and keeps every candidate that survives the dedup.
- **Phase 3, sweep** (xhigh and max). One fresh finder with the list so far
  looks only for gaps: moved code that dropped a guard, second-tier footguns,
  setup and teardown asymmetry in tests, and flipped config defaults.
- **Effort tiers.** low is one pass over the diff's hunks with a hunk-only bug
  taxonomy and no verify, and on every family but Opus 4.8 it skips test files.
  max, on every family, runs the ten angles as subagents with up to eight
  candidates each, the verify and the sweep. medium, high and xhigh depend on
  the family:

  | Model family | medium | high | xhigh |
  |---|---|---|---|
  | Sonnet 5 | eight angles as subagents, up to six candidates each, verify, precision | the same angles and candidates, biased to recall, with a verify biased to recall too | ten angles as subagents, up to eight candidates each, verify, the sweep, recall |
  | Opus 4.8, and any model without a recipe of its own | eight angles in sequence in one context, dedup with no verify, erring toward surfacing, up to eight findings; a model without a recipe of its own runs the high recipe here | eight angles in one context, dedup with no verify, biased to recall, up to ten findings | ten angles in one context, dedup with no verify, the sweep in the same context |
  | Opus 5 | one careful diff pass, with no angles | the same | as on Opus 4.8 |

  A subagent tier that finds no subagent tool works its angles in one context
  and checks its own candidates in place of the verify. On Sonnet 5, high, xhigh
  and max size the finder count to the diff, about one finder per 150 lines,
  between two and eight.
- **Output.** Ranked most severe first and capped per tier. A review that
  reports through its findings tool gives each finding a summary of at most
  sixty characters and a category slug. Correctness outranks cleanup when the cap
  forces a cut. Some tiers set a floor on the finding count, and report fewer
  when fewer are genuine.

So the bar in closure check 1 and indicator 1 is whichever recipe the
operator's model gets at the Claude Code version that runs it. The
`/code-review` run behind the review of this spec's PR (#1282) reported the
one-context recipe for high: eight angles without D or E, and no verify step. A
Claude Code release or a different model can change that recipe between two
checkpoints.

### The superpowers pointers

Repository: <https://github.com/obra/superpowers>. Each path below exists at its
commit `bb92a7774141`, read on 2026-10-17.

- `skills/requesting-code-review/code-reviewer.md`: the whole-branch reviewer
  prompt. "The spec is a vision document", the "Declined to judge" list, a
  read-only review, severity calibration, and the output shape.
- `skills/subagent-driven-development/task-reviewer-prompt.md`: the task-scoped
  review. Part 1 is spec compliance (Missing, Extra, Misunderstood) and Part 2
  quality, with "Do not trust the report", and tests as evidence that is not
  re-run.
- `skills/subagent-driven-development/re-review-prompt.md`: the scoped
  re-review. Each finding is ADDRESSED or NOT ADDRESSED, new breakage is sought
  in the fix diff only, and out-of-scope observations are parked.
- `skills/subagent-driven-development/SKILL.md`: the loop. Five fix rounds:
  rounds one to three resume the implementer, and rounds four and five dispatch
  a fresh implementer on a more capable model. The model is selected by task
  risk.
- `skills/subagent-driven-development/scripts/review-package`: the commits, the
  stat and the diff at ten lines of context, written to a file the reviewer
  reads once.
- `skills/test-driven-development/SKILL.md` and
  `skills/verification-before-completion/SKILL.md`: red-green, and "no
  completion claims without fresh verification evidence".
- `skills/receiving-code-review/SKILL.md`: verify before implementing feedback,
  push back with technical reasoning, and no performative agreement.

### What gc-toolkit already does better

These are not gaps, and the epic keeps them.

- A pinned commit, a detached worktree, and a refusal to guess a base.
- Dispatch context is not authority, and contradicting it is written down.
- The reviewer runs regression tests against the pre-change code.
- Out-of-scope findings are filed as deduped bugs rather than dropped or
  ledgered.
- Finding beads survive a rebase and dedupe across rounds.
- A validator stands as a second agent between finding and work.
- A two-provider quorum, and review routed to a pool other than the author's.
- The feedback-learning loop amends the review rubric with anchored,
  operator-gated rules.
- A hermetic test suite extracts and executes the shell blocks in formula prose,
  and learned lints graduate from the same loop.
