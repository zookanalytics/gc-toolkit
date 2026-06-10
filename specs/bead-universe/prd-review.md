# PRD Review: The Bead-Universe Operating Model (gc-toolkit)

> ⚠️ **READ `.plan-reviews/bead-universe/human-clarifications.md` FIRST — it is authoritative and
> overrides this review where they conflict.** In particular: **`consult-host` is NOT a production
> prototype** (it was an abandoned idea); ignore this review's claims that it is "the Pillar-1
> prototype already in production" and that you should "build the seam from consult-host." The
> operator also reshaped v1 at the gate (proactivity = slung mols, 1:1 binding, intent-only
> measurement, node-LLMs may act on their subtree) — the clarifications file has the details.

*Synthesis of 6 parallel PRD-review legs (requirements, gaps, ambiguity, feasibility, scope, stakeholders), run as polecat sessions against tk-yrio rev 3 + prd-draft.md. Leg reports live in bead notes: tk-d1gt, tk-6g8e, tk-3j8b, tk-g5ah, tk-s8pi, tk-zcnq.*

## Executive Summary

The model is **conceptually strong and unusually well-grounded** — every leg independently verified the PRD's "inventory + verify FIRST" claims against the code and they hold (binding is convention-only ✓; `gc-attention.sh` ranks the described signals ✓; the on_demand lifecycle and its sharp edges are real ✓). The feasibility leg found the strongest asset the brief under-credits: **`consult-host` is effectively the Pillar-1 prototype already in production** — a session spawned *per bead* (`--alias consult-<bead-id>`) that reaches its bead's universe on demand and treats the bead as the durable record. The model is an evolution of shipping primitives, not green-field.

It is **not yet buildable or gateable as written.** Four structural findings recur across legs:

1. **Proactivity (G4) rests on a substrate that cannot support it as written, and is the deepest, most-deferrable cut.** The named runtime — the on_demand session lifecycle — is *pull-shaped* (materialize on nudge/routed-work) and an on_demand named session **cannot self-restart**; proactivity is *push-shaped* and needs a net-new **budgeted waking loop** plus durable state. (ambiguity CG2 "contradiction", feasibility "single riskiest assumption", gaps CG-1 "no runner/wake-reason", scope Gap-1 "THE scope decision", requirements CG3.)
2. **Binding is under-rated — it is the load-bearing build, not "a tech validation."** Today's link is lossy by design (`consult-host`: "the bead is the state; the host is ephemeral"). G4's promise to "carry the richer conversation already in progress" depends on durable, replayable per-bead state the lossy notes-binding does not provide. Plus an unresolved **cardinality contradiction**: "*the* resident LLM" / "a thread per bead" (1:1) vs. Q1 "0..N per bead." (feasibility CG3, gaps CG-3, ambiguity CG1, scope Gap-7.)
3. **The success metric (G6/Q7) is unfalsifiable.** No unit; it *contradicts the mechanism* (Pillar 2 exists to surface **more**, so "fewer escalations" is the wrong sign); no baseline; N=1. And there are **zero acceptance conditions** anywhere — no "v1 is done when…". (requirements CG1/CG2, ambiguity direction-ambiguity, scope Gap-2.)
4. **Autonomy ships without a payer, a security/trust owner, or a successor to the crew's safety functions.** Proactive bead-LLMs ingest untrusted content (PR text, CI logs) then "act" while the human is elsewhere — a prompt-injection surface with no threat model, no action allowlist, no kill-switch, no accountability log; and "Gastown mostly leaveable" silently dissolves the refinery merge-gate + the only impl-bead closer. (stakeholders CG1–CG6, gaps CG-4, requirements CG5.)

The central tension ("context-complete without context-overload") is correctly owned by the **design** process — and the legs gave it a crisp acceptance shape: it reduces to **two numbers, recall (100% on a fixture) AND fed-slice ≤ a token ceiling.** "context-complete" is a misnomer for the model's own mechanic (feed scoped core, make the rest fetchable) — it should be **context-*reachable*.**

Net: closing the questions below — above all a ruling on **proactivity's v1 status**, a **bound on proactive action**, a **binding scope**, and a **real acceptance definition** — converts a compelling brief into a buildable, gateable v1.

## Before You Build: Critical Questions

*(For the human gate. Four genuine forks that need an operator ruling, then four defaults I will carry into design unless vetoed. Recommended defaults given so you can answer fast.)*

**Q1 — Proactivity in v1: defer, or keep-but-bound? [THE scope decision]**
The Rough Approach commits v1 to "a two-pillar system *coupled by proactivity*," and G4 frames proactivity as "the model's sharpest expression of foundation — not a bolt-on." But proactivity strictly *depends on* reachability already working, is the most token-expensive property, needs an unbuilt waking-loop + the unbuilt Q8 budget, and the brief itself concedes "threads already prove the [reactive] mechanism."
- **(a) Defer to v1.5** — v1 = the *reactive* bead-universe (land in a universe, reach everything on demand). Risk: a reactive-only v1 may feel close to today's thread-per-bead + the merged board.
- **(b) Keep in v1 but BOUND it** — make Q8's budget a *named v1 deliverable*, cap proactive compute to a single subtree, propose-only. Risk: larger v1.
*The legs split and steelmanned both. You must rule because the brief frames proactivity as the point.* (My lean: (b)-bounded **if** you feel reactive-only ≈ today; else (a).)

**Q2 — Proactive action blast-radius. [trust gate]**
Confirm v1 proactive work is **propose/explore-only — read + draft, NO side-effects (no pushes, PRs, reassigns, child-closes) until human-ratified** — plus a **global** proactive-compute budget with a hard kill-switch and minimal **action-accountability logging** (what each node-mayor touched/changed; distinct from the out-of-scope v2 audit loop). *Recommended: yes to all four.* Without this, "speculative work (accepted or not)" is not cheap to discard — rejected work already changed the world.

**Q3 — Binding scope for v1. [cost vs. fidelity]**
Confirm v1 binding = **one durable interactive attachment per bead, reconstruct-from-notes (the `consult-host` shape)**, deferring 0..N + autonomous-transcript + true-durable-session-state. *And greenlight the cheap de-risking spike first:* clone `consult-host` into a one-bead **`bead-host` probe** on one real epic, do one proactive advance, re-spawn, and measure (1) fidelity — does it "carry the conversation," or feel cold? (2) token cost of one universe-load+cycle, (3) wall-clock to materialize. ~hours, zero new infra. Poor fidelity ⇒ binding richness is the real v1 build, proven *before* paying for it. *Recommended: yes + run the spike.*

**Q4 — v1 acceptance + the human-time unit. [what does "done" mean]**
Confirm we (a) **demote "fewer escalations over time" to a lagging, non-gating** indicator; (b) **gate v1 on mechanical binding+reachability fixtures + a checkable Definition of Done** (e.g. *"from the board, a human picks a flagged bead, lands in its resident-LLM universe, and that LLM correctly answers questions requiring on-demand reach into the bead's children/deps/history, for one real subtree"*); (c) **pick a human-time unit + capture a pre-rollout baseline.** *Which unit* — operator session-minutes, context-switches/day, decisions-per-hour, time-to-decision? Or is N=1 a "just write the intent down" case? *Recommended: yes to (a)/(b); you pick the unit in (c).*

**Defaults I will carry into the design legs unless you veto:**
- **D1 (safety functions retained):** v1 **keeps** the refinery (verified-merge gate + impl-bead closure) and witness/deacon (health + orphan/runaway-session watch). "Gastown mostly leaveable" = the *dispatch/persona* machinery (pour/burn/sling, fixed-crew), **not** the safety gates.
- **D2 (node-mayor authority):** v1 node-mayor = **read-only reachability into its subtree**; *command/coordination over children* (parent-acts-on-children) is deferred — it is the out-of-scope declarative-control engine. Cross-tree coherence stays with a **retained root/city-mayor** (the topology is a forest of per-rig DAGs + an HQ root, not one tree).
- **D3 (scope of "bead"):** "nearly every bead has an LLM" is read as a **capability** ("any bead *can* have a resident LLM on demand"), not whole-tree materialization; with an **eligibility predicate** (e.g. *open AND (has-children OR needs-decision OR is-frontier)*). "bead" = **work beads**, not mail/molecule-step/convoy beads.
- **D4 (framing/naming):** rename "context-complete" → **"context-reachable"**; the parent↔child relationship is **fields-on-demand (no summarization** — summarization machinery is v2); the central tension stays owned by the design legs, with **recall-vs-footprint** as its acceptance shape.

## Important But Non-Blocking

- **Staleness surface (under-named in the PRD):** proactivity + reachability interact — proactive work done ahead of time may *cache a worldview* (PR diff, CI, child status) and act on it when facts have moved. Needs freshness/TTL on fetched facts + re-fetch on human-engage. (requirements)
- **Node-mayor overlap:** overlapping subtrees ⇒ two node-mayors can act on a shared descendant (the same class as polecat-vs-polecat races, the #1 churn source today). Needs a single-writer-per-node rule. (requirements)
- **Cross-rig reachability breaks at the rig boundary:** no formal cross-rig dep edges (`cross_rig_refs` is a best-effort prose scan); `bd` is rig-scoped. State whether v1 reachability is **intra-rig only**. (gaps, feasibility)
- **Pre-work beads:** a bead whose PR/CI doesn't exist yet — the universe def must encode "not yet" (null, expected) vs. "unreachable/error." (gaps)
- **`config-drift drain`** is operator-named but the gaps leg could not find its spec in the rig; pin down its trigger and whether proactive sessions are subject to it. (gaps)
- **Dolt is a fragile SPOF the model leans on harder:** "nearly every bead has an LLM" multiplies concurrent Dolt load and raises both outage probability and cost-of-outage; needs a concurrent-session ceiling + a degraded-mode answer (block / back off / cached slice). (gaps)
- **Board cardinality gap:** `gc-attention.sh` ranks 3 *anchor* types (epics, owned convoys, decisions), not arbitrary work beads; expanding the ranked universe to "nearly every bead" has a recompute cost (caching is a deferred follow-up). (gaps)
- **"v1 is single-operator by assumption"** — state it, so multi-operator scoping (whose attention/priorities/budget) is *deliberately* deferred. (stakeholders)

## Observations and Suggestions

- **Build the seam from `consult-host`.** The natural v1 seed is "generalize `consult-host` from consult beads to *any* bead." Reachability primitives mostly exist (children/deps/dependents/PR-url); the only real builds are CI-status (trivial — wire `gh pr checks`) and rich history-by-bead (the binding gap). (feasibility)
- **The central tension has a crisp dual metric:** recall = 100% on a seeded fixture **AND** fed-slice ≤ X tokens. This is the rare case where the hardest conceptual question reduces to two automatable numbers — lean on it for acceptance. (requirements, ambiguity)
- **A tiered measurement plan** beats the single fuzzy proxy: Tier-0 mechanical acceptance (fixtures, gates the ship); Tier-1 leading behavioral indicators (accept/redirect/**ignore** rates, fed-slice footprint, aggregate spend vs. budget, board-rows vs. triage throughput — a rising ignore-rate = drowning); Tier-2 the lagging human-time proxy (repaired, never a gate). (requirements)
- **The attention board structurally retires "picker-blind once drained":** the board ranks *beads*, not live tmux panes, so a drained bead-universe still appears and pick-a-row re-materializes it — *provided binding makes re-materialization resume, not cold-start.* A point in the model's favor. (gaps)
- **Reconcile G4 (maximize ahead-of-human output) with G6 (minimize interruptions):** both hold only if proactivity is *high-precision* — few, high-value surfaced items. That makes cheap-triage + a board cap **load-bearing for the success metric itself**, not polish. (requirements)
- **Separate the four conflated "humans"** (user / payer / security-authority / operator) even if one person fills all four — so the max-proactivity vs. cost-restraint vs. bounded-autonomy trade-offs are made deliberately, not emergently. (stakeholders)

## Confidence Assessment

**High** on the structural findings — they are absences/contradictions verified against the code with citations (no acceptance conditions; the metric's no-unit/wrong-sign/no-baseline defects; the pull-vs-push lifecycle mismatch; the lossy binding; the missing budget/threat-model). The cardinality and proactivity-substrate contradictions are textual (both sides quotable). `consult-host`-as-prototype and the `bead-host` spike are concrete and code-grounded.

**Medium** on exact magnitudes (Dolt load ceiling; token costs — the spike calibrates these) and on whether the *reactive* slice is a meaningful-enough increment over thread-per-bead to ship before proactivity — *that is precisely Q1, which only the operator can rule.*

The remaining uncertainty is **operator intent on scope and risk-appetite** (Q1–Q4), much of which may already be settled from the 6-revision convergence — in which case the fix is "write it down" so the build legs are buildable.

## Next Steps

1. **Human gate (Q1–Q4 + veto D1–D4).** Resolve scope/risk-appetite; pick the human-time unit.
2. **Design-exploration legs** (6, mapped to the open questions): api (attention launcher + escalation surface + command surface), data (universe definition + binding schema + minimal representation), ux (board → pick-a-row → land; the load-bearing adoption risk), scale (selective-proactivity budget + N-node-mayor cost + completeness-at-scale), security (trust boundary + injection-via-reached-content + action allowlist), integration (binding tech validation + the `bead-host` spike + Gastown-retain line + rollout + measurement).
3. Synthesize the design doc; refine over 3 PRD-alignment + 3 plan-review rounds; emit the implementation beads DAG under tk-yrio. **Sequence reactive-core-first** (Binding → reachability → [proactivity per Q1]).
