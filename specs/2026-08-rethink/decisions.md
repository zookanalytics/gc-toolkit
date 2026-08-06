# Operator rulings — 2026-08-05

The phase-3 branch walk-through put ten areas to the operator; the rulings
below are binding on the branch and on cutover planning. Each names what
changed on the branch because of it (or why nothing did).

1. **Migration premise — ratified, with the PR as the gate.** Planning
   accepted; the operator reads the final PR, and a full cutover "to test
   it out" is on the table. See ruling 8, which sharpens this.
2. **Zero-resident patrols — ratified.** "Bold and using Gas City for Gas
   City is great." No change.
3. **Mayor/mechanik dropped as residents — ratified.** "They get confused
   and side-tracked all the time; fine with seeing what happens without."
   No change.
4. **Cross-provider validation — strong requirement, direction is MORE.**
   Target on the record: roughly **a third of token spend goes to other
   agents validating work**. Change: `agents/wright-codex/` ships in
   staging (was a stage-6 decision bead); every signoff-gate review routes
   to it, so the pre-open gate keeps the provider independence the live
   pack has today. The one-third target is a standing direction for future
   check-set members (a second reviewer, adversarial legs), not a quota
   any single pool must hit.
5. **Dog drop — ratified**, on the same worth-exploring grounds as 2; the
   plan for how warrants ride wright/sentry stands.
6. **Health-city deferral (D6) — acknowledged**; revisit only if the
   incremental path is chosen over all-or-nothing (ruling 8 makes that
   unlikely, and a fresh city wires the city-level import at creation,
   dissolving D6).
7. **Helm — copies are fine**; the live helm is frozen while this path is
   explored. Change: `nx-helm.sh` ships as a full copy with the
   pick-a-row/release rewire implemented (reversing the D2 port-row
   compromise); the Go sidecar remains a port row. Side direction noted:
   less bash over time.
8. **Cutover strategy — leaning all-or-nothing.** Stand up a fresh city
   importing gc-next, copy critical beads, same rigs; the current city
   can be shut down. Change: spec §9 records the fresh-city path as the
   primary strategy (it collapses stages 4–5 into one migration event and
   dissolves the overlap-window machinery into insurance); the staged
   per-rig flip remains documented as the conservative fallback.
9. **Smaller calls:**
   - **Role names** — keep for now; **flagged for operator review at PR
     time** (recorded in the review checklist below).
   - **Keeper** — keep, but the operator is "not opposed to losing it;
     seems weird with the rest of the approach." Recorded as an open
     lean: the keeper's residency is re-argued (or retired onto
     chains/turns) as a cutover-era bead, not silently perpetuated.
   - **Intake/seeding** — the operator's question "without an always-
     present agent, how do I seed anything to work on?" is answered in
     the README's "Seeding work" section: three front doors (file a
     routed bead, open a conversation with `mol-nx-turn`/the board,
     spawn `thread-ops`), all existing mechanisms — still no bespoke
     intake surface (the non-goal holds).
   - **Recycle-mid-hold** — accepted pending detail; the design is D3 in
     implementation-notes.md (deterministic hook trigger, role-executed
     record-then-drain, cost recorded).
   - **First-reaction as separate outrider pool** — ratified.
10. **Stage-1 verification list — deferred to PR time** / staging, as
    listed in implementation-notes.md.

## Addendum — 2026-08-05 follow-up observations (operator, still reading)

- **Outrider flagging.** The operator questions "flags it onto the board"
  — reading the architecture as moving away from proactive flagging. The
  ratified design (tk-h9pq5) keeps the flag as the *cheap* raise-hand (a
  board row costs no session or slot; a turn spawns a holding converse),
  but its OQ4 leaves turn-vs-flag open. Candidate reconciliation, not yet
  ruled: **graduated proactivity** — outrider flags by default and files
  a proactive turn only when its card's "Decision needed" is concrete,
  which is exactly architecture's event-driven trigger ("an event drives
  a formula, which decides an engagement is warranted"). Decide at PR
  time.
- **Seeding UX.** Front door #3 (thread-ops) is what the operator will
  actually use; #2 (conversation against a bead) is solid; **#1 (file
  work directly) will not happen without a material helper — a single
  command or UI.** Direction recorded: the README should lead with
  thread-ops, and a one-command seed helper (`nx-seed "<what I want>"` →
  files the bead, routes it, optionally opens the conversation) is a
  wanted early bead, without violating the no-bespoke-intake non-goal's
  spirit (it is a wrapper over front door #1, not a new surface class).

## Addendum — 2026-08-06 observations (operator, on the practice flows)

11. **One entry, no surface-choosing.** "Just do it" and "here's what I
    want" must share the same entry process — the operator states intent
    and the *system* classifies (single task → route it; initiative →
    brief + `mol-nx-plan`; question → conversation). Choosing between
    doors is the machine's job, not the operator's. This supersedes the
    README's presentation of three doors as peer choices: the
    conversation surface (thread-ops-shaped) is *the* front door; direct
    filing and formula invocation are machinery behind it. **Named bead:
    `nx-entry`** — the unified intake triage: one utterance in, the
    right shape out, capturing the necessary data without interrogating
    the operator. (This deliberately re-opens the intake area with a
    thin design; the "no bespoke intake surface" non-goal is amended to
    "no *heavy* intake machinery — the front door is a conversation
    plus classification, built from shipped pieces.")
12. **"What's going on with X" — same entry, two resolutions.** X is
    either deterministic (a PR, a bead id, a branch — resolve directly
    to the subject bead and open its conversation) or vague ("that epic
    on XYZ" — resolve by search over titles/records, disambiguating *in*
    the conversation only when genuinely ambiguous). Subject resolution
    is part of the `nx-entry` bead, not a separate door.
13. **Delta re-gating.** Head-pinned checks are right as a default, but
    forcing a full re-review or fresh human approval for a minor cleanup
    is overkill. **Named bead: `nx-delta-regate`** — a re-gate process
    that reviews the *range* `green@old..live-head` rather than the
    whole change, with per-member policy: an automated member may
    re-stamp on a certified-trivial delta; the human-approval member may
    define what class of delta carries an existing approval forward
    (with the state machine's stale-approval hazard as the boundary —
    the design must not reintroduce the merged-commit-nobody-approved
    case it exists to prevent). Design-first bead; the current strict
    behavior stands until it lands.
14. **Operator surfaces speak human, never handles.** Nobody remembers
    `s7`; people think in titles and purposes, and a six-item labeled
    list is too much state to carry. Ruling folded into the
    `mol-nx-plan` spec: handles are machine-internal (plan block and
    manifest only); every operator-facing surface — the ratification
    turn, diffs, flags — uses story titles and purpose, and converse
    translates the operator's natural phrasing back to handles. Diffs
    are framed at the level of what needs a decision, not the full tree.
15. **Arrive-advanced is universal.** Scenario 4's property — work meets
    the operator already advanced — is confirmed as the intent for
    *every* operator touchpoint (it is "agents earn every interaction"
    applied everywhere): converse preps before every hold, plan turns
    lead with framed diffs, first-reaction cards precede board picks.
    Not a new mechanism; recorded so no future surface ships without it.

## Addendum — 2026-08-06, the liveness invariant (operator ratified)

16. **The liveness invariant** (zero-cruft policy, adapted): every open
    bead either creates demand (routed or assigned) or is blocked —
    transitively, through its blocker graph — by an open bead that does.
    A chain that terminates in an unrouted, unassigned, unblocked bead
    is cruft, and cruft gets exactly one disposition: route it, block it
    on a real name, or decision-close it (safe because the record
    survives closure and `mol-nx-plan` re-plans can resurrect scope
    deliberately). "Tabled/delayed" without a wake condition is an
    unclosed decision — a deliberate amendment to the state machine's
    "first-class honest open states" language, made on the record per
    the consistency test. The machine recommends dispositions but never
    closes on its own.
    **Named bead: `nx-liveness`** — and its taxonomy answer: it is a
    *bead* (design + implementation work), not an agent, mol, or skill.
    It ships as (a) the state-machine doc amendment, (b) a sweep arm in
    `mol-nx-patrol-health` (molecule steps — the invariant is a bd
    query, so enforcement is patrol work; no three-hats case for an
    agent), (c) a batched **disposition turn** the sweep files (cards
    with recommendations, titles not IDs, one conversation → N calls),
    and (d) a doctor check asserting the sweep runs. A skill would be
    wrong (nothing invokes this on demand; it is standing doctrine) and
    an agent would be wrong (nothing here needs residency).

17. **A human question is a bead, its canonical form is a turn, and
    question-beads block dependents.** Ratifying the operator's
    synthesis: Gas City already holds all three pieces — the escalation
    lane parks a bead for a human (`gc.routed_to=human`), architecture
    says a human approval "is just a check nothing non-human can yet
    satisfy," and a check is a blocking dependency. gc-next unifies
    them: **any bead needing human input gets a turn** (a turn IS a
    routed bead, so it creates demand — converse preps and holds it,
    which is what makes the wait live rather than parked); a bare
    `gc.routed_to=human` bead has no claim contract driving it and is
    exactly the unnamed wait the liveness sweep hunts, so the sweep
    normalizes strays into turns (the raw lane survives only as the
    observer's low-level escape hatch). And because questions are
    beads, **wiring them as blockers is the sanctioned pattern** — the
    signoff gate already blocks its convoy, the plan's ratification
    turn already blocks its reconcile step; the state machine's
    explore → *choose* → implement example is this shape. Folded into
    `mol-nx-plan`: a story may be `kind: decision`.

## PR-time review checklist (operator)

- [ ] Role names: wright / lander / sentry / converse / outrider /
      thread-ops / wright-codex (ruling 9).
- [ ] The fresh-city cutover sequence in spec §9 (ruling 8).
- [ ] The one-third validation direction realized so far (wright-codex
      only) — decide the next validation leg (ruling 4).
- [ ] Keeper residency lean (ruling 9).
- [ ] Stage-1 verification list (implementation-notes.md).
