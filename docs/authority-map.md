---
name: Authority map — who may act on what
description: The one-page table of destructive and state-bearing powers — which actor may merge, close, kill, transition, or escalate, under what evidence, and what each may never do. Read it before adding any component that writes state or ends anything. Vocabulary glossary at the bottom.
---

# Authority map

Every power in this pack has exactly one holder, and every holder has named
prohibitions. A component that needs a power not granted here is a design
change, not an implementation detail — amend this table in the same PR.

## Powers over beads

| Power | Sole holder | Evidence required | May never |
|---|---|---|---|
| Write a lifecycle transition (`merge_result`) | `assets/scripts/lifecycle.sh` | edge declared in `lifecycle/lifecycle.toml`; atomic write + read-back | invent an undeclared edge |
| Merge a PR | `assets/scripts/merge.sh` (cadence arm 4) | full authorization set re-read immediately pre-merge; every gate `green@<live head>`; `--match-head-commit` | merge on an empty `check_set`, a hold, or an unclosed child |
| Write a gate verdict (`check.<g>`) | `assets/scripts/signoff.sh` | verdict bound to the dispatch-pinned `reviewed_oid`, which must be a full 40-hex oid and must still be on the branch; the review bead still open | `--approve` a PR (the city never approves its own); write a verdict for a check it did not run; stamp an abbreviated oid; write a verdict for a commit a rebase took off the branch; record a verdict on a closed review bead |
| Clear a gate marker (`check.<g>`) | `signoff.sh` (its own gate, on REQUEST_CHANGES); `pr-facts.sh` (every declared gate, when the PR is retargeted); `gate-ensure.sh` (a marker that both fails the grammar and names a gate `check_set` does not declare) | the clearing condition above, read-back verified | `gate-ensure.sh`: clear a well-formed marker, or any `exception@` — that verdict is the operator's to retire |
| Retire a signoff round cap | `pr-facts.sh` (cadence arm 5) on a batch of operator feedback; `signoff.sh reset <anchor> --reason <why>` on a ruling | a batch id no floor already names, or a recorded reason; `signoff_cap` and the standing `exception@` still agreeing; no live `gc.takeaway`; every key read back | retire a park no `signoff_cap` claims, or one a sitting holds; retire the exception without advancing `signoff_round_floor` (the next pass re-caps) |
| Depart from an anchor's default `check_set` | a human, on a named anchor (the default itself is stamped by `mol-refinery-patrol` and `gate-ensure.sh`, neither of which reads the diff) | the reason recorded in the anchor's notes in the same act; a narrowing only once the PR is open | be derived from the diff by any dispatcher, formula, or reviewer (operator ruling 2026-08-24, `specs/2026-08-review-gates/scope.md`) |
| Close a work bead (anchor) | `merge.sh` after a verified merge; a human otherwise | recorded `merged_sha` (or `unverified:` sentinel) | be closed by its own polecat |
| Reopen a wrongly-closed anchor | `lifecycle.sh reopen`, invoked by a human or on operator direction | bead closed while `merge_result` is a non-closed state (the I5 violation shape) | reopen a legitimately-closed (`merged`) or open bead; run from an automated caller |
| Close a review bead | `signoff.sh` after a verdict; `assets/scripts/review-sweep.sh` (cadence arm 7) when there is no verdict to give | signoff: the verdict recorded and read back. sweep: the anchor closed AND `review_branch` missing from a branch listing that was actually read | close a review whose anchor still gates, or whose branch is still on origin; write a gate marker or file a rework child while disposing of one |
| Close a step bead | the session executing it, via `assets/scripts/step-close.sh` | `(assignee, gc.step_ref)` ownership proof | close another session's step; close `workflow-finalize` |
| Close a visit | converse, at the end of a sitting | outcome recorded (`gc.outcome`) | close the subject it tracks |
| Close-with-successor (disposition) | `assets/scripts/bead-rehome.sh` callers (mechanik, converse) | `gc.superseded_by` + store stamped | bare-close a re-homed bead |
| Route work (`gc.routed_to`) | `gc sling` (runtime); direct stamp only where a bare sling would be hijacked (documented at each site) | — | route across rig stores |
| File an escalation | `assets/scripts/escalate.sh` (everyone calls it) | one open visit per `escalation_key` | mail (there is no mayor); duplicate an open key |

## Powers over sessions

| Power | Holder | Evidence required | May never |
|---|---|---|---|
| Spawn / drain / reap sessions | the Gas City runtime (reconciler) | its own ladders: idle timeout, no-wake-reason drain, max-age restart | — (runtime-owned; the pack works around, never against) |
| Nudge a parked session | `assets/scripts/quota-park-nudge.sh` (order) | provider quota banner in the pane, closed signature set | kill, file a warrant, or nudge on any other diagnosis |
| **Kill a wedged session** | **the dog pool** (`agents/dog/`), executing `mol-dog-shutdown-dance` | an open **warrant** bead from a patrol detector, three failed **interrogations** via `dance-probe.sh`, and a quota-park check proving the target is not merely parked | kill without a warrant; kill a quota-parked session; touch the dead session's beads (witness orphan recovery owns them) |
| Recover a dead session's beads | witness patrol (orphan recovery) | session-ID liveness proof | strip `metadata.branch`; recover from a *live* session |
| Detect a wedged deacon | `boot-health` order | mechanical reads only | file a warrant (a false nudge-death diagnosis must not feed the executioner) — REPORT-ONLY by design |

## Detectors vs. actuators

Patrols and orders **detect**; the table above names the only **actuators**.
A detector that wants to act files the appropriate bead (a warrant, a rework
child, a visit) addressed to the actuator — never acts directly. This split
is the rewrite's spine: it is why deleting a detector never orphans a power
and why every destructive act has exactly one auditable code path.

## Glossary (inherited vocabulary, now native)

- **Warrant** — a bead (`warrant.target`, `warrant.reason`,
  `warrant.requester`) filed by a patrol detector against a live-but-wedged
  session, routed to the dog pool. The only path to a kill.
- **Interrogation** — a bounded challenge round (`dance-probe.sh`): nudge the
  target, wait an escalating bound, read the pane. Verdicts: `alive`,
  `silent`, `parked`, `missing`.
- **Pardon** — the dance's outcome when the target proves alive: warrant
  closed `gc.outcome=pardoned`, nothing killed. The dance is pardon-biased:
  one `alive` verdict ends it.
- **Execute** — `gc session kill` after three failed interrogations; the kill
  is the whole act — beads flow to witness recovery.
- **Epitaph** — the evidence record appended to the warrant before it closes,
  plus the `DOG_DONE:` notice to the requester.
- **Gate / marker / check-set** — see [state-machine.md](state-machine.md)
  §Gates.
- **Visit / subject / takeaway** — see
  [gascity-human-engagement.md](gascity-human-engagement.md).
