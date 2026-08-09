---
name: Follow-ups — captured from the PR #259 review and validator runs
description: Deferred design items the operator explicitly tabled or raised as future work during review, each with enough of an initial read that the eventual sitting can start at depth rather than from zero. Candidates for beads at intake.
---

# Follow-ups (captured, not committed)

Each entry: the operator's raise, plus the initial read banked so the
future conversation starts warm.

1. **Proactive outcomes beyond hand-to-human** (review, proactive
   prompt). A first reaction currently has one terminal shape: card +
   visit. The operator notes more outcomes exist (e.g. clearly
   executable → route to work; duplicate → link and close-candidate;
   needs decomposition → planning mol). Initial read: this is triage
   disposition inside the reaction — the same route/gate/park/kill
   vocabulary the sweep sitting uses; the mr-only and never-close
   invariants must survive any extension.
2. **Prompt sections as on-demand skills** (review, converse prompt).
   Load procedure at the moment of use (end of context) instead of in
   the seed prompt. Gas City supports pack-shipped skills invoked per
   agent (`gc skill list --agent`). Initial read: the gate-visit filing
   block, record-stewardship, and formula-routing guidance are the
   natural extractions; the loop itself stays in the seed. Verify skill
   invocation works for pool-spawned sessions before restructuring.
3. **Time-driven refresh of open items** (review, operating-principles).
   Time changes conclusions: a bead's first-read card rots; something
   blocked yesterday may be workable today. Initial read: the liveness
   sweep already re-*classifies* on every pass (a newly-unblocked bead
   enters the ready set and surfaces), so state-refresh exists; what
   does not exist is content-refresh — re-running a stale first
   reaction, re-dating a census line. A `refreshed_at` stamp plus a
   sweep clause ("candidate's card older than N days → note it stale in
   the census") is the minimal shape.
4. **Idea capture without obligation** (review, same thread). A way to
   record general ideas with their initial reads that does not demand
   action — the nursery. Initial read: a triage subject with scope
   `label:idea` + a convention that idea beads get a baseline first
   reaction but are held-by-design (not unnamed waits) — needs a
   held-by-design marker or label the sweep's classifier respects.
5. **Mol discovery surface** (review, converse prompt). Agents need a
   listable menu of formulas with when-to-use guidance. Current answer:
   formula `description` fields read from the rig checkout (or
   `gc formula list` where available). Candidate improvement: a doctor
   check asserting every formula description opens with a when-to-use
   sentence, so the menu stays legible by construction.
6. **F-28** (validator round 1): unexplained pre-filled input in held
   sessions — operator-side investigation before unattended overnight
   use.
7. **Claim-path group affinity** (validator F-11): the structural fix
   for two-sessions-one-subject is upstream (`gc.session_affinity`
   momentum); the converse fold-guard is the standing mitigation.
   Revisit when upstream's affinity read-side lands.
8. **Upstream contribution filing**: seven ready-to-file drafts in
   `upstream-contrib-drafts.md`.
