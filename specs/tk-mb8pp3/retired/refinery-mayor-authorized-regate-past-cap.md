---
name: refinery-mayor-authorized-regate-past-cap
description: "A rework hand-back carrying regate_authorized=mayor-<date> for an anchor whose codex gate is EXHAUSTED (attempts>=cap, exception recorded/escalated) needs a MANUAL cap-bypass dispatch — the field is not machine-consumed and a polecat's new commit can never self-clear the cap."
metadata: 
  node_type: memory
  type: project
  originSessionId: 09de5240-e819-449c-9f79-d9b968349635
  modified: 2026-08-13T00:13:55.551Z
---

**Trigger:** a rework hand-back bead (own branch, `merge_strategy=mr`, `source_anchor_bead=<anchor>`, `regate_authorized=mayor-<date>`) routed to the refinery, whose anchor is a `pre_open_gate` with `check.codex=exception@<head>`, `check.codex.attempts=N@<head>` (N>=cap 3), `check.codex.exception_escalated=<head>`, and a `blocked_reason` about "signoff did not converge after N rounds". Live case tk-prcqq → anchor tk-z4aka (7 rounds, mayor-2026-08-12; the fix was a test-harness LIVETTL race, "NOT a product defect").

**Why a polecat push can't self-clear it.** `reconcile-gate-verdicts.sh` counts `attempts` NOT head-bound but over the anchor's CLOSED parent-child children carrying `source_review_bead` (script deliberately diverges from the design doc's "head-bound reset", `assets/scripts/reconcile-gate-verdicts.sh` ~562). With `open_kids==0` and `attempts>=MAX`, R11 (~726) re-records `exception@<newhead>` on EVERY head move — so the polecat pushing a fix (moving 15a0d21→e7d9f2d) just gets re-excepted, never re-armed. The PRE-OPEN re-arm that would clear a stale marker (~756) is unreachable because R11 fires first. This is the terminal state the cap exists to force; only an operator breaks it.

**`regate_authorized` is a durable AUDIT record, NOT machine-consumed** — grep finds it in no formula/script. The mayor's authorization means the REFINERY manually dispatches past the cap that would otherwise route-to-human (merge-push step 4 cap arm, mol-refinery-patrol ~1843).

**Do it (verified working):**
1. Dispatch a fresh codex review at the CURRENT branch head — do NOT rebase/move the head first. Moving it makes `exception@<old>` stale for the new head and R11 re-exceptions + re-escalates (one noise mail). Keeping the head means `exception@<head>` stays MATCHED, so gate-verdicts on the already-excepted-at-this-head path stays quiet (no re-record, no re-escalate, live review not retired). A 1-behind-main doc-only lag is fine — squash-merge is disjoint; self-heals via the stale-base arm if it ever matters.
2. Mint the review the formula-exact way (see [[refinery-pre-open-regate-strand]] for the shape): `task_kind=review, check_name=codex, review_branch, review_base, anchor_bead=<anchor>, review_pool + gc.routed_to=<rig>/…polecat-codex, fix_target_pool`, `--blocks <anchor>`, body from `review-dispatch-body.sh`. Run the open/in_progress dedup FIRST. `bd show --json` of a review bead breaks jq on control chars in the body — verify metadata via server-side `--metadata-field` filters or `tr -d '\000-\037'` ([[bd-show-json-invalid-breaks-done-gates]]).
3. Do NOT clear `check.codex` manually — clearing it makes verdict!=ok while attempts>=cap so gate-verdicts RE-records the exception + re-escalates. Leave `exception@<head>`; codex's `green@<head>` overwrites it (green is checked before the cap). DO clear the stale `blocked_reason` and stamp `regate_authorized` on the anchor for the trail.
4. Close the rework bead landed-on-branch (one-anchor-per-PR terminal arm, [[refinery-rework-handback-one-anchor]]): NEVER stamp `merge_result` on it; `--set-metadata gc.work_outcome=shipped --set-metadata gc.work_commit=<sha>` (warn-only gate wants the commit) then `gc bd close --force` (actor-identity mismatch [[bd-close-actor-identity-mismatch]]).

**Pool pickup:** `gc session wake <rig>/…polecat-codex` FAILS "session not found" when the scale-from-zero pool is at zero — harmless. The routed `gc.routed_to` alone scales it up; the review flips to `in_progress` under a spawned `…polecat-codex-lx-*` within ~2min (confirmed tk-4710k → lx-04r4).
