---
name: Scope and architectural-drift detection in the review check-selection path
description: Design for tk-6bji7k.11. How the refinery's check-selection recognizes the rare change where a standing approval no longer applies — a workflow rewrote the bead's scope after it was reviewed, or a rebase/rework grew into an architectural change larger than what was approved — and re-arms the right review lane, while ordinary commits keep an approval alive. Supersedes the retired materiality approach (tk-6bji7k.6 / PR 870).
---

# Scope and architectural-drift detection in check-selection

A human approval means the same thing wherever it is given: merge what is
presented into this pull request's base. It survives the ordinary commits that
follow — rebases, fixups, base-merges — because the machine lanes are
commit-agnostic and GitHub's own approval persists across pushes
(`docs/state-machine.md`, "Green survives new commits"). That is the right
default, and it is what almost every change wants.

A narrow set of changes breaks it. When a change stops being the one that was
approved — because its stated scope was rewritten, or because a rebase or rework
turned into an architectural change larger than what a reviewer read — the
standing approval covers work that no longer exists, and the change can merge on
it. This design gives check-selection a way to recognize those two cases and ask
for the review they now need, without touching the commit-agnostic default that
serves everything else.

## What is true in the code today

The review a change needs is selected by `assets/scripts/gate-ensure.sh` (arm 1
of the merge cadence). An anchor declares its gates in `check_set`, a comma list
of lane names; the default is `codex`, a single whole-diff review lane
(`gate-ensure.sh` `DEFAULT_CHECK_SET`, stamped from
`REFINERY_RECONCILE_CHECK_SET` via `refinery-reconcile.sh` and by
`mol-refinery-patrol` on every transition into a gating state). For each declared
lane, gate-ensure asks whether the lane is green; a green lane is settled and it
dispatches nothing, and a lane that is neither green nor in flight gets one
`mol-review` dispatch pinned to the live head.

A lane's green is derived, never stored (`assets/scripts/lane-state.sh`). It
holds when a closed `task_kind=review` bead backs the lane — `signoff_verdict=approve`,
carrying a `reviewed_oid`, not `gc.outcome=superseded` — **or** when the anchor's
pull request carries any `APPROVED` GitHub review. That GitHub-approval fallback
(`lane-state.sh` `github_approved`) checks no commit: an approval "names no gate,
so it backs every lane," and nothing compares it to a head. An open review bead
for the lane is the one thing that forces not-green, by the in-flight precedence
that keeps green from co-existing with a live review.

There are two human-approval mechanisms and they bind to a commit differently:

- The **lane** green above is commit-agnostic. A human `APPROVED` on the pull
  request greens `codex` and keeps greening it however far the branch advances.
- The **`approval` gate** in `assets/scripts/merge.sh` is head-pinned: it counts
  an `APPROVED` review only where `commit_id == live head`. But it is armed only
  when `check_set` names `approval`, or the city's own review was dismissed
  (`merge.sh` `needs_approval`). The default `codex` set does not name it.

Re-review is triggered today by exactly two things, neither of which is scope or
architecture. A rewrite that takes the `reviewed_oid` off the branch makes
`signoff.sh` refuse the verdict and close the review `gc.outcome=superseded`, so
gate-ensure pours a fresh review at the live head. And for a lane that is not
green, the per-head bar (`gate-ensure.sh` `reviewed_at_head`) lifts once a fixup
moves the head to a new oid. A change that keeps its `reviewed_oid` reachable and
carries a standing approval merges commit-agnostically, and nothing reads what
the change since approval actually did.

There is no snapshot of a bead's scope at approval time, and no measure of a
diff's size or shape: a search of the tree for `approved_scope`, `scope_hash`,
diff-stat thresholds, or an architectural classifier finds none. So the two
cases below are undetected today.

## Why the retired approach was the wrong shape

tk-6bji7k.6 / PR 870 (closed, never landed) added `materiality.sh` and wired it
into `merge.sh`'s **approval arm**. Three things made it the wrong shape, and the
operator ruled it retired (converse visit tk-l26xp9):

- It hooked the **head-pinned `approval` gate**, which the default `codex` set
  never arms. So for the default path — where the commit-agnostic lane green (and
  its `github_approved` fallback) is what a change actually rides to merge — a
  changed diff still lands on a stale approval, and 870 did not close that.
- It **held the merge** with a bespoke gate rather than driving the logic that
  selects reviews. A held merge is a dead end for a person to clear; a selected
  review is work the city does.
- It triggered on **any material diff**, not on scope or architecture
  specifically, so it re-asked the operator for the ordinary changes the default
  is meant to carry — and then deferred the actual judgment to a later bead, which
  is why the rule read as plumbing with no logic in it.

The correction is to put the detection where reviews are selected, make it fire
only on the two narrow cases, and respond by selecting the review the change now
needs.

## The design

### The approved baseline

When a lane converges green, the state that green stands for is captured on the
anchor as the lane's **approved baseline**, two facts bound to that lane:

- `approved_oid` — the commit the approval stands on. For a city verdict this is
  the review bead's `reviewed_oid`, which `signoff.sh` already writes. For a
  human GitHub approval it is the latest external `APPROVED` review's own
  `commit_id`, the commit that reviewer actually read. `pr-facts.sh` takes that from the pull request's
  reviews endpoint (`repos/{repo}/pulls/{n}/reviews`), where each review carries
  its own `.commit_id`; it already reads that endpoint, and already filters
  reviews on `.commit_id` to dismiss superseded blocks. The `approved_oid` is
  deliberately not the oid in `pr_posture=approved@<oid>`. That posture pins to
  the live `headRefOid`, and `reviewDecision` stays `APPROVED` across the ordinary
  pushes that follow an approval, so the posture re-records `approved@<new head>`
  on every pass. Reading the posture oid as the approved commit would set
  `approved_oid` to the drifted head, making `base...approved_oid` and
  `base...head` the same range; the classifier would then compare the change
  against itself and always return `stands`, which is the drift it exists to
  catch.
- `approved_scope_digest` — a digest of the bead's scope-bearing content at that
  moment: its title and the requirements body of its description, normalized
  (whitespace-collapsed, trailing operational sections excluded). The bead's
  appended notes are excluded on purpose — dispatch notes, breadcrumbs, and
  routing diagnosis are operational churn, not scope.

The baseline is written by whichever writer records a fresh approval. `signoff.sh`
writes it when it stamps an approving verdict. `pr-facts.sh` writes it when a new
external `APPROVED` review appears on the reviews endpoint, identified by a review
id and `commit_id` it has not already captured. The trigger is a new sign-off
event, not the aggregate `reviewDecision` still reading `APPROVED` at a later
head. A standing approval that `pr-facts.sh` re-observes after an ordinary push
must not recapture: doing so would move the baseline forward to the drifted head
and erase the very drift the classifier exists to catch, before it ever runs.
Both writers already write at the instant a fresh approval lands, so this adds a
field to an existing write, not a new pass. A lane that has no recorded baseline —
approved before this ships, or never approved — has no drift by definition; the
baseline is captured the next time a fresh approval lands, so the rule applies
going forward and re-reviews nothing retroactively.

### Detection: two conditions, read in check-selection

A new shared helper, `assets/scripts/approval-drift.sh` (verb
`classify --anchor <id> --lane <lane>`), answers one question for a lane that
would otherwise read green: does the approved baseline still apply? It is the
drift counterpart to `lane-state.sh`, and gate-ensure consults it at the same
point it asks whether a lane is green. It returns one of `stands`, `scope`,
`arch`, or — when it cannot read what it needs — `stands` (see "Preserving the
default"). It reads the baseline written above and compares it to the live state.

**Scope drift (`scope`).** The bead's current scope digest differs from
`approved_scope_digest`. This is the case the operator named as "a workflow
modifies the bead after it is ready and changes its scope": an automated writer
rewrote the requirements the review approved. Because the digest covers only the
title and requirements body and excludes appended notes, an operational append
does not trip it, and a genuine requirements rewrite does. Scope extension a
person adds as a pull-request comment is already handled elsewhere —
`pr-facts.sh` routes operator feedback into a validation pass — so this condition
targets the workflow-write case that path does not see.

**Architectural drift (`arch`).** The change since the approved commit has grown
beyond the envelope the reviewer read. The reviewed envelope is the diff
`base...approved_oid`; the live change is `base...head`. The condition holds when
the live change expands the reviewed envelope by a structural signal, not merely
a larger one:

- it touches a top-level module or directory absent from the reviewed file set
  (new structural surface, distinct from more edits inside reviewed files); or
- its magnitude exceeds the reviewed envelope by a configured factor (guarding
  the small-review-then-large-rewrite shape).

Ordinary change clears both. A pure rebase reproduces the reviewed net diff — the
same files at a similar magnitude — so it adds no new path and no magnitude
blow-up. A fixup edits files already in the reviewed set at small magnitude, so
it stays inside the envelope. This is deliberately narrow: it is the "rebase or
rework that turns into an extensive architectural change rather than what was
approved," not "any material diff."

### Response: re-arm the right lane, never hold the merge

On `scope` or `arch`, gate-ensure treats the lane as **not settled even though it
derives green**, and dispatches a fresh review through its existing path. The
dispatch creates an open review bead for the lane, which by `lane-state.sh`'s
in-flight precedence immediately holds the lane out of green — so `merge.sh` will
not merge until the re-review resolves, with no bespoke merge hold and no second
writer of a gate verdict. This is the whole difference in shape from 870: the
merge is held as a consequence of a selected review, not by a gate bolted onto
the approval arm.

The level of the re-review is the lane it re-arms:

- **`scope` re-runs the change's own lane** (the general review — `codex` by
  default): the reviewer re-reads the rewritten requirements against the diff and
  approves or files rework. A workflow that narrowed or clarified scope clears on
  a fresh read; one that broadened it gets the review the broadening earns.
- **`arch` escalates the level.** An architectural change larger than what was
  approved needs human eyes, so this arms an architectural review that requires a
  fresh human sign-off — the "fresh PR / review" the operator asked for. Mechanically
  it adds an `arch` lane to the anchor's `check_set` (a lane whose reviewer is a
  person) so `merge.sh` holds until that lane greens; equivalently, on a check_set
  that already names `approval`, it negates the standing approval so a fresh
  `APPROVED` at the drifted head is required. Whether `arch` is a distinct named
  lane or a reuse of the `approval` gate is the open decision below.

Because this reads on every anchor and every lane in `gate-ensure.sh`, it closes
the default-path gap 870 left: it does not depend on the `approval` gate being
armed, and it governs the commit-agnostic lane green — the thing a default change
actually rides to merge — directly.

### Preserving the commit-agnostic default

The default is that an approval survives new commits and no re-review is asked,
and this design keeps it the overwhelming path:

- The classifier's answer for the ordinary change — rebase, fixup, base-merge,
  scope unchanged — is `stands`, so `lane-state.sh` green is used exactly as it is
  today. Nothing compares a marker to a head for ordinary growth.
- On an unreadable input — a bead that will not read, a git range that will not
  compute — the classifier returns `stands`, not a re-review. Its two inputs are
  local (the bead and the branch), so an unreadable read is rare; and the
  classifier is a net-new trigger layered over the existing gates, so its failure
  must not manufacture the re-reviews the operator ruled out. This is the opposite
  of `merge.sh`'s fail-closed direction, and it is deliberate: the safe default
  here is the standing approval, which the lane green and posture already guard.
- Each green convergence recaptures the baseline, so a re-review that approves the
  drifted state sets the new baseline and the lane does not re-drift against the
  old one. There is no re-review storm: the per-head bar already prevents a second
  dispatch at an unmoved head, and the recaptured baseline prevents a second
  dispatch after re-approval.

## Answers to the four questions this bead owes

- **Signals that distinguish drift from ordinary change.** Scope: a digest of the
  bead's title and requirements body, excluding appended notes, differs from the
  digest captured at approval. Architecture: the live `base...head` change adds a
  top-level path absent from the reviewed `base...approved_oid` envelope, or
  exceeds its magnitude by a configured factor. Rebases and fixups clear both.
- **Where it hooks.** In `gate-ensure.sh`, at the per-lane settledness decision,
  as a `approval-drift.sh classify` call beside the `lane-state.sh green` call —
  the check-selection path, not the merge gate.
- **The response.** Re-arm the affected lane so gate-ensure dispatches a fresh
  review; the open review holds the lane out of green until it resolves. `scope`
  re-runs the general lane; `arch` escalates to an architectural (human) lane, or
  negates the standing approval on a check_set that names `approval`. The merge is
  never held by a bespoke gate.
- **How the commit-agnostic default is preserved.** The classifier answers
  `stands` for ordinary change and for any unreadable input, so lane green is used
  unchanged; the baseline recaptures on each green convergence; and only the two
  narrow, high-precision conditions ever re-arm.

## Open decisions for review

- **The architectural magnitude factor and whether the path signal alone
  suffices.** The path-expansion signal is the stronger of the two; the magnitude
  factor is a number to pick. The design can ship on the path signal first and add
  magnitude if the path signal proves to miss real cases.
- **`arch` as a named lane versus the `approval` gate.** A distinct `arch` lane is
  explicit and composes with the existing multi-lane machinery; reusing the
  head-pinned `approval` gate is less new surface but couples the response to a
  gate that carries its own semantics. This chooses the response mechanism.
- **The exact scope region hashed.** Title plus the full description body is the
  simplest; excluding a trailing operational section reduces false positives but
  needs a convention for where requirements end. The safer first cut is to hash
  the description as authored and rely on appended notes living outside it.

## What the implementation bead builds

tk-6bji7k.12 implements this against the integration branch after this design
lands: the baseline capture in `signoff.sh` and `pr-facts.sh`, the
`approval-drift.sh` classifier with its two conditions and fail-toward-`stands`
contract, the gate-ensure settledness hook, and the `arch` re-arm path chosen
above — each with the shell tests the review path holds its scripts to. The
concrete scope is set by this design; the open decisions above are the operator's
to settle at the checkpoint review.
