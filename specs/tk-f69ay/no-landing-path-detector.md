---
name: Detecting published work with no landing path
description: Why the stranded-branch detector gates on molecule liveness rather than on an empty assignee, why it repairs by handing off instead of re-dispatching, and why the report's `gc.routed_to=""` aside was deliberately NOT implemented.
---

# Detecting published work with no landing path

Design record for `assets/scripts/recover-stranded-branches.sh` and the witness
patrol step that runs it (bead tk-f69ay).

## The gap

The canonical work chain is `worktree -> (push) -> branch -> (PR) -> target`. Every
existing detector watches one link of it and none watches the join between the
second and the third:

| Pass | Keyed on | Why it misses a stranded branch |
|---|---|---|
| pool demand | `gc.routed_to` + ready | the bead is unrouted, and its root is in_progress |
| refinery find-work | exact `--assignee` | the bead has no assignee at all |
| `reconcile-refinery-handoffs.sh` | a refinery-shaped assignee | same — there is none to near-miss |
| `check-set-heal.sh`, `reconcile-merged-prs.sh` | `pr_url` / `pr_number` / `merge_result` | the bead has none of the three |
| witness `recover-orphaned-beads` | assignee + dead session | scoped to ASSIGNED beads by construction |
| witness salvage cases C/D/E | uncommitted work in a worktree | the work is committed AND pushed, so "nothing to salvage" is correct |
| `quiesce-completed-workflows.sh` | dead step beads | de-routes the husk; never asks what became of the work bead |

Each is right about its own question. The unasked one is whether a **landing path**
exists. Live instance recovered by hand on 2026-08-11 (tk-0981e): branch on origin,
one clean commit ahead of main, merging cleanly, bead `open` + unassigned +
unrouted + unstamped, no PR. Nothing would ever have picked it up.

## Why liveness is an AND, not the report's OR

The bug report proposed selecting on
`(assignee empty OR the owning workflow root is a husk)`.

Taken literally that fires on every molecule in the city. Verified live on tk-f69ay
itself while it was being implemented:

```
{"id":"tk-f69ay","status":"open","assignee":null,"routed":"ABSENT"}
```

`mol-polecat-work` assigns the polecat to the **step** beads and never to the
anchor, so an open, unassigned, unrouted work bead is what work-in-progress looks
like for its entire lifetime. "Unassigned" therefore separates nothing; only "no
live session stands behind its molecule" does, and the two conditions have to hold
together. The pass resolves the bead's input convoy (`gc bd dep list <id>
--direction=up`), finds the workflow root that owns that convoy (roots carry
`gc.input_convoy_id` and appear in the ordinary open/in_progress listing, so the
map costs one bulk read), and treats the molecule as live if the root records a
live session **or** any of its live steps is held by one.

The age gate (`--min-age-minutes`, default 30) is a backstop for the seconds-wide
window between a polecat's `git push` and its handoff, not the guard. Implementation
routinely outlasts any age threshold; liveness is what protects a running polecat.

## Why the repair is the handoff itself

The report suggested re-dispatching to the pool "to resume at submit-to-refinery".
That names the missing action exactly — and the missing action is a metadata write:
stamp `branch` and `target`, set the bead back to `open`, reassign it to the
refinery. Pouring a fresh molecule would spend a full-context session re-deriving
four fields.

**All four are the handoff, and each is read back.** `gc bd update` reporting success
is not proof that a write is durable, and every write here is best-effort (`|| true`,
so the pass never aborts the patrol), which makes success and failure otherwise
indistinguishable:

| field | what it decides | when it is verified |
|---|---|---|
| `branch` / `target` | what the refinery MERGES BY | **before** the assignee is written at all |
| `status=open` | whether the refinery ever POLLS the bead | with the assignee, after |
| `assignee` | who owns the next move | with the rest, after |

`branch`/`target` are verified first because the two failures compound: an assignee
that sticks over a target that did not takes the bead out of this pass's candidate
set (it is no longer unassigned, so nothing retries it) *and* hands the refinery a
branch to rebase onto a missing or stale base — an owned-convoy member onto `main`.
Refusing before the assignee write costs one cycle; proceeding is un-retryable.

`status=open` is not cosmetic. The refinery's find-work step polls
`--assignee=$GC_AGENT --status=open` (`formulas/mol-refinery-patrol.toml`), and the
candidate scan admits `in_progress` beads — a strand wears that status whenever a
partial quiesce cleared the assignee without resetting the status. Handed over as
`in_progress`, the bead is assigned to an actor that will never poll it and is no
longer unassigned, so this pass cannot retry it either: strictly worse than the
strand it started from. It is written in the same update as the assignee, exactly as
the polecat done sequence writes it.

A post-write mismatch **releases our own assignee** (its own single-flag update — a
claim guard can roll back a batched release and lose both writes), restoring the
candidate shape so the next cycle retries the whole handoff. Only our own: a
different assignee means another actor took the bead in the window, and clearing
that is stealing a live claim.

This is not a shortcut past review. The refinery still takes the branch through the
pre-open codex gate, and the PR still needs external human approval, so a branch
pushed by a polecat that died *mid*-implementation is reviewed exactly as it would
have been; a REQUEST_CHANGES verdict files the rework child as usual. The failure
being fixed is the bead never entering that pipeline at all.

The pass never closes a bead — only the refinery does that, after verifying a merge.
`open` is the only status it ever writes.

## The `gc.routed_to=""` aside: deliberately not implemented

The report also flagged, as worth fixing independently:

> Also worth fixing independently: `gc.routed_to = ""` (empty string). An empty
> routed_to is always a bug — it reads as "routed nowhere" while being present, and
> it defeats metadata-field queries that test for absence.

**It is not a bug, and changing it would break a documented contract.** The empty
string is the shipped marker for "detached from both queues":

- `docs/work-bead-state-machine.md` — the PRE-OPEN GATING and GATING states are
  defined as `open . assignee="" . gc.routed_to="" . merge_result=...`, with
  `gc.routed_to=""` listed explicitly "so an open, unassigned bead is not read as
  pool demand".
- `docs/gascity-routing-model.md` — `gc.routed_to=""` "drops the bead out of Tier 3",
  and `assignee="" + gc.routed_to="", status still open` is named as the detached
  state.
- It is written on purpose by `mol-refinery-patrol.toml` (the park), by the polecat
  done sequence, and it is what `pre-open-resolve.sh` documents as the
  `pre_open_gate` shape.

Nothing in the pack currently tests `gc.routed_to` for *absence*: every reader —
`reconcile-refinery-handoffs.sh` included — normalizes with `// ""` and so treats
empty and absent identically. Converting the writers to `--unset-metadata` would
change no reader's behavior while invalidating three documents and the state
machine's vocabulary.

The robustness point underneath the aside is real and is honored: **a reader must
treat empty and absent as the same thing**, because both occur live for the same
meaning. This detector's candidate filter does exactly that
(`(.metadata["gc.routed_to"] // "") == ""`), which is why it sees strands left by
the done sequence (empty) and strands on beads that were never routed (absent)
alike. A filter that distinguished them would miss half the cases.

If the empty-vs-absent distinction is ever wanted, the change belongs upstream in
the state-machine doc first and in the writers second — not as a side effect of a
detector bead.

## Fail-safe direction

Every unestablished fact refuses rather than guesses: an unreadable session roster
or bead listing hands off nothing (an unread roster makes every running polecat look
dead); a failed `gh pr list` is not proof that no PR exists; a target branch missing
from origin is escalated to the mayor rather than guessed at; and any bead carrying
`duplicate_of`, `hold_reason` or a live `merge_hold` is left alone because somebody
decided that branch should not move. An un-repaired strand is the status quo this
pass improves on; a wrong handoff creates a new one.

The convoy read is held to the same standard at both of its levels, because both
degrade into silence rather than into an error. A dependency list that did not read
and a bead with no upstream convoy both reduce to an empty id list; an unreadable
convoy bead and a convoy that records no `target` both reduce to an empty string. So
neither read is trusted on its value alone — the listing must arrive as an array and
each convoy row as an object, or the candidate is reported and skipped. Guessing
there is not a cosmetic error in one field: it stamps the repository default over an
owned convoy's integration branch, which recovers an integration member into a `main`
PR past the convoy boundary — and the pre-assign readback cannot catch it, because
all the readback proves is that the *wrong* target stuck. The same empty list also
leaves the liveness gate with no convoy to test, so a live molecule becomes invisible
and a running polecat's branch is handed to the refinery mid-implementation.

The refusal *marker* is held to the same standard, and for the same reason: it is
the one piece of state that can turn a refusal into silence. Every refusal writes
`stranded_branch_flagged=<branch>@<tip>` so a stuck bead is named once rather than
every cycle, but only one of them — the unresolvable target — also mails the mayor.
Keyed on the tip alone, the quiet marker a *transient* read failure leaves would
suppress that mail when a later cycle reads those facts successfully and discovers
the missing target: the escalating refusal returns at the suppression check having
summoned nobody, and the branch stays stranded behind a summary count with no
human-facing signal anywhere. So the marker records the refusal's escalation class
as well as its tip, and a quiet marker never suppresses a loud refusal — while the
mail itself stays bounded to once per `(branch, tip)`, since a second reason to look
at the same commit does not need a second summons.
