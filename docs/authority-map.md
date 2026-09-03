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
| Merge a PR | `assets/scripts/merge.sh` (cadence arm 4) | full authorization set re-read immediately pre-merge; every gate reads `green`; `--match-head-commit` | merge on an empty `check_set`, a hold, or an unclosed child |
| Write a gate verdict (`check.<g>`) | `assets/scripts/signoff.sh` | the review bead still open; the marker written is the bare lane state (`green` on approve), and `reviewed_oid` is the dispatch pin and posted-artifact audit label — bound to no marker and compared to no head, but written back to the review bead and read back before the marker is stamped, since a closed review bead carrying it is what `check-gate-marker-provenance` resolves the lane against; pre-open, the verdict body read back off the same bead; the dispatch pin still an ancestor of the branch (a rewrite — rebase, amend, force-push, never a fast-forward — refuses both verdicts, clears the pin, and closes the review bead `gc.outcome=superseded` for gate-ensure to re-pour); the closed bead stamped `signoff_verdict=<approve\|request-changes>` | `--approve` a PR (the city never approves its own); write a verdict for a check it did not run; record a verdict on a closed review bead; stamp `green` over a marker still carrying the pre-migration `exception@` shape; stamp a marker the review bead records no reviewed commit for — since the city posts no approval, nothing else could resolve it; pre-open, stamp a marker or file a rework child when the verdict body did not land on the review bead, whose notes are the only copy of it |
| Clear a gate marker (`check.<g>`) | `signoff.sh` (its own lane, on REQUEST_CHANGES); `pr-facts.sh` (every declared gate, when the PR is retargeted); `gate-ensure.sh` (a marker that both falls outside the lane vocabulary and names a gate `check_set` does not declare) | the clearing condition above, read-back verified | `gate-ensure.sh`: clear a well-formed lane state — a clear withdraws evidence and cannot assert it |
| Retire a signoff round cap | `pr-facts.sh` (cadence arm 5) on a batch of operator feedback; `signoff.sh reset <anchor> --reason <why>` on a ruling | a batch id no floor already names, or a recorded reason; a rework ledger that reads, naming at least one round for the floor to come from; the cap's own pairing still standing — `merge_hold` reading exactly the literal string `signoff_cap` AND a non-empty `signoff_cap=<gate>` beside it; no live demand (`gc.demand_for=<anchor>`) — never the presence of `gc.takeaway`, which outlives the sitting that stamped it; every key it wrote read back, the retired dispatch tally included | retire a park no `signoff_cap` claims, or one a sitting is still waiting on a person for; read a takeaway as a hold; lift the hold without advancing `signoff_round_floor` (the next pass re-caps); treat an operator's own `merge_hold=true` as the cap's to retire — only the `merge_hold=signoff_cap` pairing is |
| Widen an anchor's `check_set` | `signoff.sh --add-gates`, on a `triage` review's approve verdict; a human by hand on a named anchor (the default itself is stamped by `mol-refinery-patrol` and `gate-ensure.sh`, neither of which reads the diff) | signoff: every added gate declared on the gate menu of the `docs/review-charter.md` the reviewed commit carries, one `--justification` line per gate, and the union write plus that note both read back before the green stamp. Human: the reason recorded in the anchor's notes in the same act | drop a gate the set already declares (the write is a union); accept the flags from any gate but `triage`, or on a request-changes verdict; widen an anchor carrying the `none`/`off` opt-out; widen unjustified |
| Narrow an anchor's `check_set` | nobody removes a declared gate: `signoff.sh --waive-gates` records a triage non-add, and the `none`/`off` gateless opt-out is a human's, on a named anchor | waiver: a charter row at the reviewed commit marking that gate waivable, a `--justification`, and the gate not already declared. `none`: the reason recorded in the anchor's notes in the same act, and only once the PR is open | waive without a readable charter, or waive a gate the charter does not mark waivable; be derived from the diff by any dispatcher, formula, or reviewer other than `triage` (`specs/2026-08-review-gates/scope.md`) |
| Close a work bead (anchor) | `merge.sh` after a verified merge; a human otherwise | recorded `merged_sha` (or `unverified:` sentinel) | be closed by its own polecat |
| Reopen a wrongly-closed anchor | `lifecycle.sh reopen`, invoked by a human or on operator direction | bead closed while `merge_result` is a non-closed state (the I5 violation shape) | reopen a legitimately-closed (`merged`) or open bead; run from an automated caller |
| Close a review bead | `signoff.sh` after a verdict; `assets/scripts/review-sweep.sh` (cadence arm 7) when there is no verdict to give | signoff: the verdict recorded and read back. sweep: the anchor closed AND `review_branch` missing from a branch listing that was actually read | close a review whose anchor still gates, or whose branch is still on origin; write a gate marker or file a rework child while disposing of one |
| Close a step bead | the session executing it, via `assets/scripts/step-close.sh` | `(assignee, gc.step_ref)` ownership proof | close another session's step; close `workflow-finalize` |
| Close a visit | converse, at the end of a sitting | outcome recorded (`gc.outcome`) | close the subject it tracks |
| Close-with-successor (disposition) | `assets/scripts/bead-rehome.sh` callers (mechanik, converse, `duplicate-sweep.sh`) | every caller: `gc.superseded_by` + store stamped and read back. `duplicate-sweep.sh`, per bead: the `duplicate_of` successor resolves in this store and is closed or shipped; the duplicate recorded no work, proved by `work_outcome=no-op` or by carrying no work-product key at all; nobody else owns it: unassigned, not `in_progress`, not a review bead, not a step bead or workflow root, not already pointed at a different successor | bare-close a re-homed bead; `duplicate-sweep.sh`: dispose on the `duplicate_of` stamp alone, or judge a successor that lives in another store |
| File a demand (what a person owes) | `assets/scripts/gc-helm.sh demand` (converse at a hold; operators by hand) | the gated bead resolves; the `blocks` edge read back off it | file the demand as a descendant of the bead it gates; report success on an edge that did not land; write a prose hold instead |
| Close a demand | the sitting that holds it, once the person has answered in the thread | the answer recorded to the subject's notes (converse step 6) | close a demand that names an assignee — that one is its assignee's; close the bead the demand gates |
| Route work (`gc.routed_to`) | `gc sling` (runtime); direct stamp only where a bare sling would be hijacked (documented at each site). CLEARING it is the release half of a handoff, not a routing decision: every terminal arm of `mol-polecat-work` — refinery handoff, `auto_push=false` halt, store-only exit — clears it in the same exit that unassigns the bead | a clear rides a terminal exit that has already recorded where the work went: a branch handed to the refinery, a branch left ready, or a note naming what was filed | route across rig stores; clear the route on a bead this session does not hold, or on one it is still working |
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
