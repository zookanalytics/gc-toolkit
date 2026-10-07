---
name: PR #977 review-thread dispositions at the gate-only pare-down (tk-isd5sa)
description: How each of the ten review threads open on PR #977 at 213cb356 was answered by the rework that pared the epic steward to the gate-only v1 (tk-lkf7ani) — three fixed in the retained gate and doctor check, one answered by the vocabulary change, six moot with the removed steward arms.
---

# PR #977 review-thread dispositions

Ten threads were open on PR #977 at head 213cb356, all from the 2026-10-06 code
review. The rework tk-lkf7ani, ruled at sitting tk-089mt7x, removed the
proactive steward (`orders/epic-steward.toml`, `assets/scripts/epic-steward.sh`)
and kept the finalize-gate clause and the I14 doctor check, renamed to the
continue/shift/close ruling. A thread on a removed arm is moot. A thread on the
retained gate, the doctor check, or the vocabulary was fixed or answered in the
rework. Each thread is replied to and resolved on the PR.

| Thread | Finding | Disposition |
|---|---|---|
| finalize-gate.sh:99 (r4192945487) | PROBE 2 reads through the memoized `bd_list`, so merge.sh's terminal re-assert can be served the first check's rows | **Fixed.** `finalize_gate_check` runs every clause with `GC_RECONCILE_BD_CACHE` off. finalize-gate.test.sh case 21 files a stamped visit between two checks under one pass cache and asserts the re-assert holds; with the fix removed, the re-assert passes and the case fails. |
| finalize-gate.sh:176 (r4192945668) | the disposition exemption means the clause can hold no real close path, while the docs claim it holds bead-rehome | **Answered; claims corrected.** The exemption is intended: the operator's directive names "a stewarded epic (carries a hypothesis, not disposed)". The clause comment, docs/finalize-gate.md, docs/epic-stewardship.md, and the design record now say that neither wired path reaches an undisposed epic, and that I14 sees every close. The per-finalize `gc bd show` stays; taking the type from the caller would widen the gate's interface across merge.sh, its gctk port, and bead-rehome.sh. |
| epic-steward.sh:220 (r4192945864) | the ruling visit is not retracted when units go back in flight | **Moot.** The ruling arm is removed. |
| epic-steward.sh:158 (r4192946122) | the contract arm gates on the hypothesis alone | **Moot.** The contract arm is removed. It had also been fixed earlier, in a2660453. |
| doctor/check-epic-closed-implies-ruled/run.sh:138 (r4192946370) | the remedy `lifecycle.sh reopen` is always refused for an epic | **Fixed.** The finding names `gc bd --db <store> update <id> --set-metadata epic_ruling=close --set-metadata epic_ruling_reason=...` and bd's own `reopen`. run.test.sh asserts the new remedy and the absence of `lifecycle.sh reopen`. |
| epic-steward.sh:115 (r4192946550) | a failed retract is swallowed | **Moot.** No visit is filed or retracted in v1. |
| epic-steward.sh:253 (r4192946780) | two to three `escalate.sh` calls per epic per pass starve the tail | **Moot.** The pass is removed. |
| epic-steward.sh:187 (r4192947031) | any valid ruling, persevere included, is treated as terminal, so a stale persevere satisfies the gate | **Fixed by the vocabulary change.** Only close, with its outcome in `epic_ruling_reason`, satisfies the gate or I14. A continue or shift ruling holds the epic, and each ruling overwrites the last. The re-ask half is moot, because the arm is removed. |
| epic-steward.sh:156 (r4192947255) | the floor arm has no pre-stewardship exemption | **Moot.** The floor arm is removed. The gate and I14 keep the exemption for an epic with no hypothesis. |
| epic-steward.sh:171 (r4192947429) | the floor and contract arms ignore the ruling | **Moot.** Both arms are removed. |
