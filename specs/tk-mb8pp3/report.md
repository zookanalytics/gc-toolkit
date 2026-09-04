---
name: Auto-memory index compaction (tk-mb8pp3)
description: What the one-time gc-toolkit auto-memory compaction retired and why, the verification behind each retirement, and the reversibility record for a store with no backup.
---

# Auto-memory index compaction (tk-mb8pp3)

Move 2 of the durable-memory spike (`specs/tk-1co/spike-report.md`, on branch
`polecat/tk-1co`): a one-time pass over the gc-toolkit auto-memory corpus at
`~/.claude/projects/-home-zook-loomington-rigs-gc-toolkit/memory/`. The corpus
is not in git and has no backup, so the verbatim text of every retired file is
committed under `retired/` here. That is the only thing that makes the
retirement reversible.

## The bead's premise had already moved when work started

The bead was filed against a 263-line `MEMORY.md` where 63 of 256 entries fell
past the 200-line read cap and were invisible at session start. By the time a
polecat claimed it (2026-09-03 16:34Z), the live index was **101 lines** and
every entry was reachable: a concurrent writer had re-packed the index to four
titles per line. That closes the headline defect, but by shortening lines, not
by removing entries — the index carried **more** entries than at the spike
(269 vs 256), and the corpus had grown to 270 files.

Re-packing is the lever the index's own header disparages ("compaction means
merging related memory files rather than shortening lines"). It leaves the
stale content in place. So this pass does the part the re-pack did not: retire
the entries whose subject the pack deleted, restore the one unreachable file,
and commit the backups. Line count was never the remaining problem; corpus
health was.

## Method

Two levers from the bead, applied conservatively because the store is shared,
unversioned, and has no backup — when a memory's lesson survives the deletion
it names, it is kept.

1. **Retire what depends on deleted machinery.** 70 memories cite an artifact
   PR #465 (2026-08-25) removed. A citation is not proof the memory is wrong:
   most name the artifact only as an illustration of a lesson that still holds
   (a `bd`/`jq`/shell behavior, a general refinery pattern). Each candidate was
   read, and retired only when its **core claim** is about a deleted artifact's
   behavior with no surviving general lesson.
2. **Self-declared obsolescence.** 33 memories carry a `SUPERSEDED`/`RETIRED`/
   `RESOLVED`-with-date marker. Most mark one section and keep a live residual,
   or use the word in their own content. Retired only when the whole file is
   dead.

### Verification

Every retirement rests on the artifact being confirmed **absent from
`origin/main`**, not on the spike's list. The scripts
(`check-set-heal.sh`, `reconcile-merged-prs.sh`, `reconcile-gate-verdicts.sh`,
`quiesce-completed-workflows.sh`, `recover-stranded-branches.sh`,
`escalation-gate.sh`) and formulas (`mol-doc-keeper-*`, `mol-liveness-sweep`,
`mol-triage-recurrence`) are all gone. #465 replaced them with a redesign
(`refinery-reconcile.sh` and siblings), not a rename. A system-wide grep
settled the borderline cases: the gate markers `fixable@`, `exception@`,
`green@`, and `stale-gate` **survived** (they moved into `gate-ensure.sh`,
`merge.sh`, `signoff.sh`, `pr-facts.sh`), while the round/`signoff_cap`,
`regate`, and `check-set-heal` dispatch concepts are **gone**. A memory keyed
on a surviving concept was kept; one keyed on a removed mechanism was retired.

## Retired (11) — not merged

Nothing was merged. These are deletions of dead content; each row names where a
surviving general lesson already lives, or "none" when the whole memory is moot.

| Retired file | Reason | Surviving lesson lives in |
|---|---|---|
| `check-set-heal-visibility-test-is-slow-not-hung` | its whole subject is a test file that no longer exists | none |
| `doc-keeper-audit-is-self-finalizing-workflow` | `mol-doc-keeper-*` formulas deleted | none |
| `doc-keeper-audit-same-line-overlap` | doc-keeper drift-audit dedup; workflow deleted | none |
| `doc-keeper-drift-audit-exclusions` | exclusion list for a deleted formula | none |
| `doc-keeper-drift-audit-read-origin-main` | drift-audit step behavior; workflow deleted | none |
| `doc-update-source-entry-location` | about doc-keeper `doc-update` beads; source deleted | none |
| `preopen-handback-machinery-dispatches-the-regate` | claim is `reconcile-merged-prs.sh` auto-dispatches the re-review | `dont-move-a-head-under-a-live-review`, `refinery-quiesce-split-update-claim-guard` |
| `refinery-mayor-authorized-regate-past-cap` | mechanism is `reconcile-gate-verdicts.sh` cap counting; that cap model is gone | `refinery-convergence-cap-arm` (current cap), `refinery-pre-open-regate-strand` (dispatch shape) |
| `refinery-stale-gate-self-heal-arm` | claim is `reconcile-merged-prs.sh`'s `--review-pool` self-heal arm | `refinery-merge-gate-human-approval` |
| `refinery-anchorless-open-pr-blindspot` | says the blind spot is "closed by automation" that is now deleted; would mislead | `refinery-orphan-scan-unrouted` |
| `refinery-out-of-band-nondraft-pr-reconcile` | self-declared superseded; its `gh pr ready --undo` re-draft is obsolete | `refinery-close-on-land-model` |

### Notable near-misses kept

- `refinery-convergence-cap-arm` — flagged (says "SUPERSEDED FOR THE POST-#465
  TREE") but actually maintained current: modified 2026-08-28, its body now
  describes the live `signoff.sh`/`gate-ensure.sh` cap. The banner marks one
  old section.
- `refinery-idle-driver-passes-vs-agent-escalation` — its seven-pass list is
  stale, but it carries a durable operator ruling (2026-08-20, tk-qe2tv/PR#401:
  "a PR awaiting human approval is owed zero escalations") not captured
  elsewhere. Kept for that ruling; the pass list is a trim candidate.
- `gate-marker-fixable-does-not-mean-findings` — cites the deleted
  `reconcile-gate-verdicts.sh`, but `fixable@` survived into `gate-ensure.sh`,
  so the lesson still holds.

## Reachability

`refinery-tier2-shortcircuit-orphans-wisps` existed on disk but was in no index
entry (the spike flagged the same file). It is now linked on the
`Orphan scan: unrouted` line.

## Deferred

- **Merging topic clusters** (the ~40 `refinery-*` files, the rebase cluster).
  Deferred: with the index packed four-per-line the cap counts lines, so
  merging no longer buys line headroom, and collapsing distinct hard-won
  lessons risks losing nuance. This is the recurring curator's ongoing job
  (spike Move 2), not a one-time deletion.
- **Trimming partially-superseded memories** to their live residual (e.g.
  `refinery-codex-review-dispatch-procedure`, `refinery-idle-driver-passes-*`).
  Left whole; they are net-useful as they stand.

## Dangling wikilinks

Kept memories carry `[[...]]` links to retired slugs. The memory system
tolerates a link with no target, and done-condition 2 governs the index, not
in-body links, so these are left in place rather than editing ~15 more shared
files under concurrency. The set, for the curator: `dont-move-a-head-under-a-
live-review`, `refinery-pre-open-codex-gate`, `refinery-orphan-scan-unrouted`,
`refinery-rework-prepushed-predrafted`, `cascading-rereviews-file-cumulative-
rework-children`, `refinery-convergence-cap-arm`, `diagnose-stranded-bead-via-
distinct-history-states`, `gate-marker-fixable-does-not-mean-findings`,
`refinery-stale-base-diff-artifact`, `refinery-formula-step-vs-script-
ownership`, `rebase-child-closes-while-original-anchor-stays-open`,
`refinery-close-on-land-model`, `refinery-codex-review-dispatch-procedure`,
`pr-body-placeholder-never-rerendered`, `gascity-agents-doc-source-of-truth`,
`retire-a-component-sweep-by-concept-not-name`,
`double-dispatch-repool-preserve-predecessor-work`,
`mol-polecat-work-graphv2-inline-execution`.

## Concurrency and final state

The corpus has live writers (the swarm wrote `MEMORY.md` at 16:03, 16:47, and
17:05Z while this ran). The index was snapshotted before editing; the edit was
a content-matched transform, not a line-numbered one, and the pre/post diff was
confirmed to be exactly the 11 removals plus the one orphan addition, so no
concurrent write was clobbered. Each file was re-checked byte-identical to its
backup immediately before deletion.

Final reconcile: **261 index links = 261 disk files, 0 broken links, 0 orphans,
`MEMORY.md` at 102 lines.**
