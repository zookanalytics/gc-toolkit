---
name: Findings round 2 — re-validation of the fix commits (2026-08-08)
description: Delta report re-running the live-adoption validation against 2d6c12a, verifying each round-1 finding the three fix commits claim to close. F-06 confirmed fixed end-to-end; three fixes are claimed in a commit message but absent from the diff; F-18 is half-fixed and the sweep diagnosed the other half itself.
---

# Findings round 2 — re-validation

**Branch:** `claude/gc-toolkit-fresh-start-ehvljb` @ `2d6c12a`
(was `a295fb7` in round 1; three fix commits `c32c7a8`, `0a88909`, `2d6c12a`)
**City:** `/Users/zook/Code/gc-next`, rigs `gc-toolkit` (tk) and `signal-loom` (sl)
**Host:** darwin 25.6.0, `gc version` = `edge`
**Run:** 2026-08-08 23:15–00:35Z. City stopped, round-1 visits cleared, restarted clean on the new pack.
**Recommendation: ADOPT, with two carve-outs** — see §Recommendation.

Read against `live-adoption-findings.md`; this is a delta, not a re-statement.

**Headline:** the round-1 blocker is genuinely dead. A visit on the same
arrested subject that was permanently unclaimable in round 1 now goes ready →
offered → claimed → held → closed (R2-06). Nine of the fourteen claimed fixes
verify. But **three fixes named in `c32c7a8`'s message were never written**
(R2-01), and F-18 is fixed in one direction only, which the sweep worked out on
its own (R2-02).

---

## What I could not test this round

- **F-24 (`open` twice dedup)** and the **held-glyph render** were not re-run.
  Neither was touched by the fix commits except through the shared gate-visit
  edge change, which R2-06 covers.
- **Cold-continuity** (fresh session answering from the record) again not
  isolated — same reason as round 1, and the runbook now documents that nuance
  rather than promising it (F-10 fix, verified as prose).
- **F-26** (torn JSON) did not recur this round. Absence over ~80 minutes is not
  evidence it is gone; it is logged upstream as draft #7.
- The store changed between rounds (I closed six round-1 visits; agents filed
  new beads), so raw census counts are not directly comparable. R2-02 leans on
  the sweep's own funnel arithmetic, not on 66-vs-67.

---

## R2-01 — Three fixes are claimed in the commit message but absent from the diff. **DEVIATION (new, serious)**

`c32c7a8`'s message states:

> F-09: converse must read the outcome stamp back before closing.
> F-11: converse folds when another live session holds a sibling of its group.
> F-14: converse writes no files and never commits to the rig checkout.

All three are converse **prompt** behaviours. The only file that could carry
them is `agents/converse/prompt.template.md`. It was never touched:

```
$ git diff --name-only a295fb7..HEAD | grep -c 'agents/converse'
0
$ git diff --stat a295fb7 HEAD -- agents/converse/
(empty — byte-identical)
```

The full file list of all three fix commits contains no converse file
(`agents/proactive/*`, `assets/scripts/{gate-visit.test.sh,gc-helm.sh}`,
`doctor/check-agent-prompt-integrity/*`, `formulas/mol-{first-reaction,
liveness-sweep,triage-recurrence,visit}.toml`, four `specs/*`,
`tools/helm-surface-fixture.sh`).

Searching the entire diff for the behaviours turns up only my own findings file
being added:

```
$ git diff a295fb7..HEAD | grep -iE '^\+.*(never commit|writes no files|read .*stamp back|folds?|sibling)'
+  scale" clause specifies. It correctly folded in the *other* session's visit
+with you attached"; siblings vacuum onto the live session.
+**Observed:** two sibling visits in group `tk-2zmwe` were claimed by two
…all from live-adoption-findings.md
```

**None of F-09, F-11, F-14 is implemented.** The commit message is the record a
reader will trust, and it says otherwise.

**What the live run showed** (and why this matters more than it looks — the
behaviours *happened* to be fine this round, which is exactly how this stays
hidden):

- **F-09** — the single visit closed with `gc.outcome=decided-and-routed`
  correctly stamped. 1/1 this round vs 2/3 in round 1. With no prompt clause
  added, nothing structurally prevents the round-1 miss recurring; this is
  model compliance varying, not a fix.
- **F-11** — only one visit existed per group all round, so the concurrent-hold
  race had no opportunity to fire. Not reproduced ≠ fixed.
- **F-14** — no new commits appeared in the rig root this round
  (`git log origin/…..HEAD` empty). But converse still has no worktree, still
  has `work_dir = .gc/agents/converse/{{.AgentBase}}`, and still carries no
  instruction against writing files. The round-1 session only committed because
  it decided evidence was worth committing; a session that decides that again
  has nothing stopping it.

**Verdict: DEVIATION.** Either write the three clauses, or amend the record so
F-09/F-11/F-14 stay open. Right now the branch reads as having closed them.

## R2-02 — F-18 is fixed in one direction only; the sweep diagnosed the other half itself. **PARTIALLY FIXED**

The fix added tracks to class 2, and the funnel now shows it explicitly:

```
  282  open beads store-wide
 -196  not in ready+unassigned -> assigned, blocker-blocked, or gated
   86  ready + unassigned
  -11  worked (gc.routed_to non-empty)
   -0  conversing (0 open visits store-wide)
   -2  held-by-design (task_kind=triage-subject)
   73  candidates into the per-candidate edge check
   -6  waiting-on-structure (2 open children, 4 open tracks parent)
   67  UNNAMED WAITS -> this visit
```

Only **4** beads dropped for an open tracks parent — not the ~22 round 1
predicted. The rule caught the *member* side ("carried by an open parent through
tracks") and not the *container* side. All 12 convoys from round 1's cohort A
are still classed as unnamed waits. Quoting the sweep's own visit body:

> The classification rule catches the *member* side ("carried by an open parent
> through tracks") but not the container side, so they land here as unnamed.

> 1. Waiting-on-structure catches "carried by an open parent through tracks" but
>    not the container side. All 12 of cohort A carry open members and still read
>    as idle — **validator F-18 in mirror image**.
> 2. Waiting-on-structure names "open children" and "open tracks parent" but not
>    "open parent via parent-child" or "tracks an open root". All 18 of cohort B
>    hang off open, routed roots. Note that tracks is used in **BOTH orientations**
>    in this store — convoy-to-member and spec-to-root — so a direction-only
>    reading of the rule is not sufficient.

> Adopting either amendment would cut 67 to 37.

That last line is the measurement worth keeping: **67 → 37**, i.e. 45% of the
current census is still structural noise.

Credit where due — the sweep verified cohort B per bead rather than
extrapolating ("all six roots are open AND routed"), and explicitly refused to
reclassify on its own authority: *"The sweep applied the rule exactly as written
so the count stays reproducible against the formula; reclassifying is this
sitting's call, not the sweep's."* That is the right instinct.

**Verdict: PARTIALLY FIXED.**

## R2-03 — F-03: the detector shipped; the underlying bug is unchanged. **PARTIAL (as designed)**

New check fires on exactly the two affected agents:

```
⚠ gc-toolkit:check-agent-prompt-integrity — 2 agent(s) carry a cross-pack
  prompt_template — stub-fallback exposure (validator F-03)
```

`polecat-codex` and `mayor-thread` still render the 16-line stub — the resolver
bug is filed as upstream draft #6, correctly out of this pack's scope. The
branch now warns instead of failing silently, which was the achievable fix.

**Verdict: PARTIAL, appropriately scoped.**

---

## Fixes verified

### R2-04 — F-05 (bare pool) **CONFIRMED FIXED**

Runbook step 1 now hard-codes the qualified form with the reason inline:

```sh
RIG=gc-toolkit                         # your rig name
POOL="$RIG/gc-toolkit.converse"        # MUST be rig-qualified (F-05)
```

Run verbatim, the visit routed and was claimed (R2-06).

### R2-05 — F-01 / F-04 (adoption) **CONFIRMED FIXED**

Step 0 now carries the binding-key rename ("repointing `source` alone loads but
silently mis-wires the orders' bare pool names"), the `default_sling_formula`
warning, and `gc import install` before `gc doctor`. A fresh adopter following
step 0 verbatim now lands where I had to get to by debugging.

### R2-06 — F-06 (arrested subject) **CONFIRMED FIXED — end to end**

The decisive retest: same subject (`tk-dinqt`, still arrested), same canonical
lines, new `--type=tracks` edge.

```
F-06 retest visit = tk-1hs13 (subject tk-dinqt, arrested)
--- in bd ready? (round 1: NO) ---
1
```

Then the full lifecycle, unforced:

```
visit=open        assignee=-                                 → offered (gc hook: 1)
visit=in_progress assignee=gc-toolkit/gc-toolkit.converse-1   → claimed
session title:    "tk-dinqt — R2 F-06 retest…"                → self-renamed
visit=closed      outcome=decided-and-routed  subject=open    → closed correctly
subject notes:    13606 → 16218 chars                         → outcome recorded
```

All five gate-visit copies carry the tracks edge (`mol-visit`,
`mol-liveness-sweep`, `mol-triage-recurrence`, `mol-first-reaction`,
`gc-helm.sh`), plus the runbook and the proactive prompt. The remaining
`parent-child` uses in the pack are unrelated (doc-keeper epic children,
refinery dep traversal) and correct. `gate-visit.test.sh`: **34 passed, 0
failed**, including "tracks edge (non-blocking lineage)" and "no parent-child
edge" across all four consumers.

This was round 1's most consequential finding. It is closed.

### R2-07 — F-20 (cold-pool wake) **CONFIRMED FIXED**

Round 1:

```
formula "mol-triage-recurrence" root is a molecule container, not Ready-visible
work; scale-from-zero pools will not wake for this wisp. Convert the formula to
phase="vapor"/root-only or formulas v2 before routing it to a pool
```

Round 2, same command:

```
Started workflow tk-03yq2 (formula "mol-liveness-sweep") → gc-toolkit/gc-toolkit.polecat
```

Warning gone. Both formulas now declare `[requires] formula_compiler = ">=2.0.0"`.
The workflow ran as a real v2 graph — steps carried their own assignees and
closed themselves (`tk-gglcn` closed, `tk-2rut2` in_progress → closed,
`tk-04eq4` assigned), where round 1's molecule root sat unassigned for 20+
minutes. Confirmed the 34 `formula-requirements` doctor warnings are all
pre-existing upstream gascity formulas using the deprecated `contract =
"graph.v2"` spelling — none are these.

### R2-08 — F-21 (macOS board) **CONFIRMED FIXED**

```
$ command -v timeout
(nothing)
$ ./assets/scripts/gc-helm.sh board --refresh
gc-helm — cross-rig human-attention board
2026-08-08T23:36:04Z · 3 rigs · 15 anchors (live)
… 15 rows …
EXIT=0
```

Runs unbounded on a host with no `timeout`, exit 0, full board.

### R2-09 — F-22 (false all-clear cache) **CONFIRMED FIXED**

Injected a failing `gc` on `PATH` to force a gather failure:

```
cache anchors BEFORE: 15
gc-helm: could not enumerate rigs (gc rig list returned nothing)
cache anchors AFTER:  15
```

The failure now takes the clean exit-3 path with an explicit error, and — the
point of the fix — **does not write the cache**. Round 1 served "0 anchors
(cached 45s)" as a quiet board for the TTL.

### R2-10 — F-25 (proactive flag verb) **CONFIRMED FIXED**

Step 4 is now the marked gate-visit block, matching `mol-first-reaction`, with
the tracks edge and the reason inline. No `flag` verb remains anywhere in the
prompt. `takeaway` is correctly retained — it is the board headline, a different
concept the removal record explicitly preserved. `PROVENANCE.md` and
`attention-flag-removal.md` both carry dated corrections.

### R2-11 — F-17 (list_cap semantics) **CONFIRMED FIXED**

```toml
description = "Max candidates ENUMERATED INDIVIDUALLY in the batch visit body;
candidates beyond the cap are still included, grouped into labelled cohorts
(validator F-17 semantics: the cap bounds line-by-line detail, not coverage)"
```

The round-2 census matches exactly: 20 enumerated individually, remainder in
labelled cohorts A/B/C with every id listed.

### R2-12 — F-10 / F-12 (drain nuance) **CONFIRMED FIXED as documentation**

The runbook now states the validated behaviour rather than the aspirational one:
*"the session drains only when NO visit is claimable anywhere in the rig — a
successful cross-group claim is authoritative."* Warm continuity is restated as
"an existing session absorbs it and re-titles," which is what F-12 actually
observed.

### R2-13 — Regression check: the round-1 confirmations still hold

- **F-07 self-rename** — worked again on a cold pool-spawned session
  (`tk-dinqt — R2 F-06 retest…`).
- **F-02 `check-liveness-sweep-wired`** — still green.
- **F-16 batching** — the pass filed exactly one visit for 67 candidates.
- **F-13 pool cap** — held at 2.
- **Fail-safe** — classify reported a clean funnel; no spurious abort.

---

## New environment findings

### R2-14 — `v2-routed-to-namespace` now times out. **ENVIRONMENT (new)**

```
✗ v2-routed-to-namespace — timed out after 1m0s and was abandoned
  (outcome unknown); re-run alone or raise --check-timeout (advisory)
```

Passed cleanly in both round-1 runs. Doctor totals moved from 104/10/1 (round-1
final) to **103 passed, 11 warnings, 2 failed, 1 advisory**; the second failure
is this timeout, not a branch regression. `order-firing-current` remains the
same pre-existing failure. `session-model` findings grew 5 → 10 (mayor wisps
assigned to a missing session bead — same class as round 1's F-27).

### R2-15 — Correction to my own round-1 record: the board's "5 anchors" was my instrument, not the pack

Round 1 reported the board rendering 5 anchors. Round 2 on the same store
renders **15**. The difference is my round-1 `timeout` shim, which killed gather
subprocesses at the deadline and silently truncated the anchor set. F-23's
substance (no FLAGGED band, held glyph works, legend correct) is unaffected, but
the count in round 1 was an artefact of the workaround F-21 forced on me. Worth
recording because it is the kind of thing that gets quoted later.

---

## Recommendation: **ADOPT, with two carve-outs**

Round 1 said ADAPT because three silent failures each stopped a visit reaching a
session. All three are now closed and verified live: F-05 (routing), F-06
(arrested subjects — verified end-to-end on the exact bead that failed), F-20
(cold-pool wake). The host blocker F-21 is gone, F-22 no longer serves false
all-clears, and F-25 no longer strands the proactive worker. The spine works.

The two carve-outs, neither of which blocks adoption:

1. **R2-01 — reconcile the record before anyone relies on it.** F-09, F-11 and
   F-14 are advertised as fixed and are not. F-14 is the one I would actually
   write: converse has no worktree, and the rig root is this city's live pack
   import source, so a converse session that decides to commit mutates live
   config. It didn't happen this round; nothing stops it happening next round.
   F-09 and F-11 are lower-stakes but should be reopened rather than left
   reading as closed.

2. **R2-02 — finish F-18 in the other direction.** The sweep did the analysis
   for you and quantified it: 67 → 37. Until then the operator's first sitting
   is still ~45% structural noise, which is what erodes trust in the census.

Everything else I would ship. The quality signal worth naming: the sweep caught
its own rule's incompleteness, verified it per bead rather than extrapolating,
and refused to reclassify on its own authority. That is the machinery working as
designed, and it is why R2-02 is a follow-up rather than a finding I had to dig
out.

No deviation was fixed in this round either. Changes made: round-1 visits closed
to clear state (`tk-lgxlg`, `tk-wcn2x`, `tk-v21nd`, `tk-rvdb0`, and force-closed
`tk-7f7kk`, `tk-24a6m` whose sessions had drained); city stopped and restarted;
a throwaway failing-`gc` stub on `PATH` outside the repo for R2-09 only. The two
round-1 converse commits (`325142d`, `ae362fe`) were **not** carried onto the
refreshed branch — they are preserved locally under tag `validator-round1-local`
if you want the gate-evidence file.
