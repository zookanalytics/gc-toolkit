---
name: Investigation — the open+unassigned+unrouted signature
description: Enumerates every consumer that reads the open + null-assignee + empty-routed_to bead surface, establishes which produce a false positive, and judges the three candidate remedies against the refinery's own enumerations. Read before proposing a lifecycle change for approval-gated beads.
---

# The three-field signature: who reads it, and what they conclude

## What this investigates

tk-5ib0r reports that a work bead parked at the human-approval gate is
surface-identical to a bead dropped on the floor: both read `status=open`,
`assignee=null`, `gc.routed_to=""`. It asks three things before any fix is
proposed — (1) enumerate the consumers of that signature and establish which
produce a false positive, (2) decide where the wait belongs in the lifecycle,
judging three named candidates rather than assuming one, and (3) hold any remedy
to a single-field read rather than a metadata join. A correction note on the bead
adds a fourth: does anything reconcile open review threads against a green
check-set marker.

All findings below are from static reading of this repository at
`5719554`. Nothing here was established against the live city.

## Summary of findings

1. **The signature spans seven meanings, not three.** The bead names three
   (pre-open gate, post-open approval wait, stranding). Four more are load-bearing
   and one of them — *a polecat actively implementing* — is the most common state
   in the city.
2. **Exactly one consumer produces a false positive today, and it is the
   operator-facing one.** `gc-helm`, the board a human glances at to find what is
   stuck, reads `merge_result` **zero times** and ranks an approval-waiting convoy
   **HIGH / "stranded"** with the hint **"decomposed, idle — assign or visit"**.
   Every script-side consumer already discriminates correctly.
3. **Candidate (a) — `status=blocked` — is refuted, not merely risky.** All five
   refinery passes that move a gating anchor enumerate `--status=open` *exactly*.
   Moving the anchor to `blocked` removes it from the merge skill, the PR opener,
   the observer, the verdict arm and the heal pass **simultaneously**, so the PR
   could never merge. The repo has already paid for this exact failure from the
   other side (sl-jcr4, below).
4. **The single-field discriminator the bead asks for already exists.** It is
   `merge_result`, and six passes already key on it. The gap is not a missing
   field; it is two consumers that do not read the field that is already there.
5. **Nothing anywhere reconciles review threads against a green marker** —
   confirmed by absence. This is a real defect but a *different* one, and it
   should not be folded into the bead-surface fix.

## 1. The signature's seven meanings

`status=open` + `assignee` empty + `gc.routed_to` empty is reached by all of:

| # | Meaning | Distinguishing field | Health |
|---|---|---|---|
| 1 | **Filed, never routed** — created, never slung | *none* | the genuine defect |
| 2 | **In-flight implementation** — a polecat is working it right now | `work_dir` + `branch`, no `merge_result`; a live session behind the molecule | healthy |
| 3 | **Pre-open gating** — codex runs against the branch, no PR yet | `merge_result=pre_open_gate` | healthy |
| 4 | **Post-open gating** — PR open, awaiting CI/approval | `merge_result=pull_request` | healthy |
| 5 | **Stranded** — branch pushed, nothing owns the next move | `branch`, no `merge_result`, no PR ref, no live session | the defect tk-f69ay names |
| 6 | **Operator-parked from the board** | `gc.takeaway` non-empty | healthy |
| 7 | **Operator hold** | `triage.hold` non-empty | healthy |

Meaning 2 is the one the bead does not name and the one that most constrains any
remedy. `recover-stranded-branches.sh:59-66` establishes it directly:

> a work bead is `open` with `assignee=null` and no `gc.routed_to` for the WHOLE
> time its polecat is working it — mol-polecat-work assigns the polecat to the
> STEP beads, never to the anchor. So "unassigned" does not distinguish a stranded
> bead from a healthy in-flight one.

So the signature is not merely ambiguous between healthy-wait and stranding; it is
the **resting shape of an anchor for its entire life**, from dispatch to merge.
That is why no remedy can work by making the healthy waits louder — the
overwhelming majority of beads wearing this signature at any instant are neither
waiting nor stranded, they are being worked. Meanings 6 and 7 confirm the pattern
is already established: both were solved by adding a *marker*, never by moving the
status.

## 2. The consumers, and what each concludes

| Consumer | Selection predicate | On a parked approval wait | FP? |
|---|---|---|---|
| `merge-skill.sh:993` | `--status=open` + `merge_result=pull_request` | acts on it — this *is* the merge gate | no |
| `pre-open-resolve.sh:465` | `--status=open` + `merge_result=pre_open_gate` | n/a (pre-open only) | no |
| `reconcile-merged-prs.sh:697` (observer) | `--status=open` + `merge_result=pull_request` | acts on it | no |
| `reconcile-gate-verdicts.sh:390,392` | `--status=open` + either marker | acts on it | no |
| `check-set-heal.sh:1382` | `--status=open` + metadata key | acts on it | no |
| `recover-stranded-branches.sh:218-221` | assignee `""` **and** routed_to `""` **and** `branch` **and** `merge_result==""` **and** no PR ref **and** no live session **and** min-age | **excluded by `merge_result`** | no |
| witness `recover-orphaned-beads` | `select((.assignee // "") != "")` | **never in the candidate set** | no |
| `quiesce-completed-workflows.sh` | `is_terminal_anchor` — five arms, incl. both markers | de-routes the husk's dead steps | no |
| `doctor/check-routed-work-claimable` | requires `gc.routed_to` **non-empty** | never sees it | no |
| `mol-liveness-sweep.classify` | class 2(ii): `merge_result=pull_request` ∩ **live** open PR | excluded — correctly | narrow gap |
| **`gc-helm.sh:862,875,893,902`** | `$open>0 and $inprog_live==0 and not $held` — **no `merge_result` read at all** | **HIGH · "0 in-progress (stranded)" · "decomposed, idle — assign or visit"** | **yes** |

### The one real false positive: the board

`gc-helm.sh` contains zero references to `merge_result`, `pr_url` or `pr_number`
(verified by count). Its severity band is decided at line 862 and its
human-readable hint at line 893, both on the same three facts: children exist,
none is live-in-progress, no visit is open. A convoy whose single child is parked
at the approval gate satisfies all three, so it renders as:

```
severity  HIGH
frontier  1 open · 0 in-progress (stranded)
NEEDS     decomposed, idle — assign or visit
```

This is the incident. The board does not merely fail to distinguish a healthy wait
from a strand — it sorts the healthy wait into the **top band** and instructs the
operator to *visit* it, which is exactly what the operator then did. The
misclassification the bead reports was not a reader's error; it was the board's
documented output.

Two properties make this the highest-value fix. It is the only surface a human
consults for "what is stuck", so it is where a false positive costs a sitting; and
it is a pure display decision — nothing downstream acts on the band, so changing
it cannot break a merge.

### The narrow gap: pre-open in the liveness sweep

`mol-liveness-sweep` class 2(ii) covers `merge_result=pull_request` intersected
against live open PRs, and deliberately does not cover `pre_open_gate`, on the
stated grounds that "the review bead holding a pre-open gate carries a `blocks`
edge onto the anchor, so `gc bd ready` drops it before it can reach the candidate
set" (lines 145-150). That reasoning holds only while the review bead is **open**.
Between the review closing green and the next `pre-open-resolve.sh` pass opening
the PR, the anchor has `merge_result=pre_open_gate`, no open blocker and no PR —
so `bd ready` returns it and it classifies as an unnamed wait. The same window
opens wider on the `exception@` verb, which is terminal until an operator acts.

The formula anticipates this and says what to do: "If that ever stops being true,
it is a distinct discriminator with a distinct liveness test — file it rather than
widening this one." That instruction should be followed rather than reinterpreted.

## 3. Where the wait belongs — the three candidates judged

### (a) `status=blocked` with a `blocked_reason` — refuted

The bead calls this "the cheapest and reuses existing machinery" and asks that it
be verified against the refinery's find-work queries and the merge gate first. It
does not survive that check.

Every pass that can move a gating anchor forward enumerates `--status=open`
**exactly**, and `--status` takes a positive list, so `blocked` is not included:

| Pass | Line | Enumeration |
|---|---|---|
| `merge-skill.sh` | 993 | `gc bd list --status=open --metadata-field merge_result=pull_request` |
| `pre-open-resolve.sh` | 465 | `gc bd list --status=open --metadata-field merge_result=pre_open_gate` |
| `reconcile-merged-prs.sh` | 697 | `gc bd list --status=open --metadata-field merge_result=pull_request` |
| `reconcile-gate-verdicts.sh` | 390, 392 | `--status=open` + each marker |
| `check-set-heal.sh` | 1382 | `--status=open --has-metadata-key …` |

A blocked anchor is invisible to all five at once. It would never merge, never
re-gate on a head move, never have its verdict reconciled and never be healed —
and, because the observer is also in that list, **nothing would escalate it**, so
the failure would be silent.

This is not a speculative objection. `check-set-heal.sh:858-880` records the same
failure reached from the other side, where the status that removed the anchor was
`closed` rather than `blocked`:

> merge-skill.sh, pre-open-resolve.sh, the observer and phase 0 itself all
> enumerate open beads, so a closed anchor is invisible to every one of them AT
> ONCE. Nothing escalates, because nothing can see it; the ledger reads "landed"
> while the PR rots.

The live case (signal-loom sl-jcr4) sat open for four days, fully green and
approved, with zero escalations, and needed a hand repair. Candidate (a) would
reproduce that by design, differing only in which non-`open` status caused it.

Widening all five enumerations to `--status=open,blocked` would restore the
machinery, but then the status carries no information those readers may act on —
the change would consist of moving the wait into a field every consumer has to
un-read. And it contradicts the standing rule in
`docs/work-bead-state-machine.md`: "`open` is the **canonical status for unlanded
work**; the machine adds no new top-level status", with gating detached from both
queues *on purpose*.

One narrower reading of (a) does survive and is worth recording: the bead observes
that the round-cap escalation path already sets `status=blocked` when it routes an
anchor to a human. That is a genuinely terminal hand-off — the city will not move
that bead again — whereas an approval wait is one an automated pass must keep
polling. The distinction is exactly the one (a) elides: `blocked` is correct for a
wait the machinery has *abandoned*, and wrong for a wait it is still *servicing*.

### (c) A distinct status — refuted for the same reason, plus one more

Every `--status=open` reader above breaks identically. Additionally, the status
vocabulary is fixed by `bd` itself — `bd list --status` documents
`open, in_progress, blocked, deferred, closed`, with `pinned` and `hooked` also
accepted — so there is no new status to introduce without a change to `bd`, which
puts the remedy outside this pack and behind a binary rollout, for a defect whose
only live symptom is a display band.

### (b) A first-class marker every consumer reads — survives, with a correction

This is the shape that works, and it is already 9/11 built. But the bead's
specific proposal — "make the `approval_escalated` stamp a first-class lifecycle
field" — is wrong in its particulars:

- **`approval_escalated` does not exist in this pack.** A repository-wide grep
  returns zero occurrences. Whatever wrote it on sl-ew4w is not code that lives
  here, so it cannot be promoted from here, and no consumer could be pointed at it
  without first establishing an owner.
- **The field that already carries the meaning is `merge_result`.** It is a single
  metadata key, it is a total discriminator over meanings 3, 4 and 5, and it is
  already the most widely-read lifecycle discriminator in the pack: **ten
  non-test scripts and six formulas** reference it. Promoting a second field would
  give the same state two spellings — the failure mode
  `docs/work-bead-state-machine.md` describes as the reason for one marker per gate
  and never a conflated field.

So the recommendation is (b), re-pointed: **`merge_result` is the lifecycle field;
make the two consumers that ignore it read it.**

## 4. Does a single field read satisfy requirement 3?

Partly, and the limit is worth stating plainly because it constrains the fix.

`merge_result` distinguishes the **shape** of the wait in one read, with no join —
which is what requirement 3 asks for. It does **not** establish that the wait is
still live, because the marker is not self-invalidating. `mol-liveness-sweep`
(lines 129-137) is explicit:

> The marker alone is NOT the test — the PR must still be LIVE. A naive "carries
> `merge_result`, skip it" rule builds the inverse defect and hides rejected work
> permanently, exactly when it most needs a sitting. The marker outlives the work:
> it stays stamped after the PR closes.

So any consumer whose false-negative is *hiding rejected work* needs the marker
plus a GitHub intersection; a consumer whose output is advisory needs only the
marker. That split decides the two fixes:

- **`gc-helm`** renders a hint and disposes of nothing, so the marker alone is
  sufficient and correct. Worst case a merged-or-rejected PR reads as "awaiting
  approval" until the observer clears the anchor — a stale hint, not a hidden bead.
- **`mol-liveness-sweep`** files sittings, so its existing bias (an unreadable probe
  excludes nothing) must be preserved; a `pre_open_gate` arm needs its own liveness
  test, which is the branch and the open review child rather than a PR.

A remedy that ignores this distinction and applies one rule to both is how
requirement 3 turns into the inverse defect.

## 5. Review threads against a green marker (the correction note's item)

**Nothing reconciles them.** Confirmed by absence: `reviewThreads`, `isResolved`
and `resolvedBy` appear nowhere in the pack outside unrelated prose.
`merge-skill.sh` reads the reviews history for **verdicts** only, and excludes the
one review type that carries inline threads (line 1583): "COMMENTED / PENDING —
carry no verdict AND supersede nothing".

The consequence, for the reported instance: 29 review threads landed on PR #533
after the gates went green. They did not move the head, so `check.codex=green@78ff1b21`
remained green **correctly** by the SHA test; they carried no verdict, so
`reviewDecision` was unchanged; and `mergeStateStatus` is unaffected by unresolved
conversations unless the repository requires their resolution. gc-toolkit's `main`
does not: its `pull_request` rule reads
`required_approving_review_count: 1, required_review_thread_resolution: false`
(read from `repos/zookanalytics/gc-toolkit/rules/branches/main`, 2026-08-11). A PR
can therefore advertise merge-ready on every declared gate while carrying N
unaddressed review conversations, and the one server-side setting that would catch
it is off.

This is a genuine defect and it is **not** the bead-surface defect. It is
readiness defeated by *comments* rather than by a *commit*, which is the framing
the correction note proposes, and it is out of scope for tk-w26b6 (staleness by
SHA) too. It should be filed separately; folding it into a fix for the three-field
signature would produce one change answering two unrelated questions.

## 6. Recommendation

Adopt candidate (b), re-pointed at `merge_result`. Three pieces of work, in
descending value:

1. **Teach `gc-helm` the gating markers** *(fixes the reported incident)*. A
   frontier child carrying `merge_result ∈ {pre_open_gate, pull_request}` is not
   idle. It should leave the HIGH/stranded band and carry a NEEDS that names the
   real wait — "awaiting approval — PR #N" — instead of "decomposed, idle — assign
   or visit". Display-only; nothing downstream consumes the band.
2. **Close the `pre_open_gate` window in `mol-liveness-sweep`**, as a distinct
   discriminator with its own liveness test, exactly as that formula's own note
   instructs. Lower value than (1): the window is short and self-clearing, and the
   sweep's delta reporting already suppresses a stable re-report.
3. **File the review-thread reconciliation separately** (§5). It is the finding
   most likely to cause a bad *merge* rather than a bad *reading*, but it belongs
   to the check-set, not the bead surface.

Explicitly **not** recommended: any change to a work bead's `status`, and any new
lifecycle field alongside `merge_result`.

Both stated exclusions are honoured — nothing here proposes changing what the
refinery escalates or how it batches escalation mail, and the converse-thread
disappearance problem (tk-bzm86) is untouched.
