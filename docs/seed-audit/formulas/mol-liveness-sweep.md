Formula: mol-liveness-sweep
Description: mol-liveness-sweep — the P3 enforcement pass: no idle beads. Every open
bead must be worked, gated (by structure or by a gating state),
conversing, or held-by-design; anything else is an UNNAMED WAIT
(specs/2026-08-fresh-start/operating-principles.md P3;
specs/2026-08-fresh-start/liveness-and-triage-spec.md §2).

Normalization is BATCHED, not per-bead: the sweep owns a standing
"unnamed waits" triage subject per rig and files ONE visit per pass —
a large backlog costs one conversation, never one per idle bead.
Per-bead visits emerge only from that sitting's decisions.

Reporting is DELTA, not census: a pass names the candidates that are NEW
since the previous pass and files nothing when none are. "Unnamed" is
the resting state of any filed-but-not-active bead, so the full
population is approximately the whole backlog — re-listing it every pass
re-litigates a stable set and buries the one bead that actually changed.
The baseline lives in `sweep.reported` on the standing subject; its
failure mode is to re-report, never to hide (operator decision
2026-08-10, bead tk-snnpp) — and that bias governs every check added
since: a probe that cannot be read excludes nothing.
`assets/scripts/liveness-sweep-delta.test.sh` extracts the nine marked
blocks below and executes them, so the delta split, the class filters
(machine convoy, landed-anchor husk, worked-via-convoy, takeaway, gating
state, operator hold, and the root fold that keeps this sweep out of a
conversation another formula is already having), the live-visit guard and
the classify→normalize handoff cannot drift from what an agent actually
runs. The re-file guard is extracted with them.

The visit body is a SNAPSHOT of the pass, and a sitting reads it whenever
the visit is claimed — a day or more later, by which time a routed
candidate may have merged and deployed (bead tk-gvas6: 60% of one body
was wrong on arrival, its headline P0 included). So the pass stamps the
census as machine state on the visit — `sweep.new_ids`,
`sweep.carried_ids`, `sweep.pass_at`, and a `visit.recheck` naming
`assets/scripts/liveness-recheck.sh` — and the claim-time re-check
re-derives every listed id's class from two batched reads. The census the
sitting works from is therefore current; the body is its provenance.
`assets/scripts/liveness-recheck.test.sh` pins that seventh marked block
and the re-check itself.

A mechanical PRECHECK decides whether this formula runs at all (bead
tk-7h51d). `orders/liveness-sweep.toml` is a condition order whose check is
`assets/scripts/liveness-sweep-precheck.sh` — three batched bead reads and a
jq, about three seconds, no session and no network — run on the rig's 6h
cadence. Every pass used to spend a polecat session reaching the conclusion
"nothing new", which made the common case the expensive one. The precheck
applies a deliberately SMALLER filter than classify below: every exclusion it
makes, classify also makes, and it omits the three that are not locally
decidable (worked-via-convoy, the open-PR intersection, the pre-open gate
verdicts). Its survivors are therefore a SUPERSET of this step's candidates,
so it may end the pass when the NEW set is provably empty, and anything else
— including any unreadable probe, a missing subject, or its own abort — runs
the pass unchanged.

One consequence of the class 0(b) exclusion lands HERE rather than in
classify, and is deliberate (bead tk-st143). A landed husk is not
locally decidable — telling it from a live step needs the root, its
convoy and the anchor — so the precheck cannot exclude it, and it must
not try: excluding more than classify does is the one direction that
breaks the superset guarantee, and the bead it would hide is a genuinely
stalled step. So husks keep the precheck firing: they never enter
`sweep.reported` any more, they never close on their own, and the
precheck therefore reads them as new on every pass and runs a pass that
now files nothing. That is a session for no visit — a strictly better
trade than the visit it replaces, which spent an operator sitting on
work that did not exist, but it is residue and not a fix. What ends it
is the reaper `sweep.husk_roots` exists to feed.

Two consequences for whoever is reading this because they are RUNNING it.
Reaching this step means only that the cheap half could not PROVE the board
empty; it is not evidence that there is something to file, and classify below
remains the authority on that. And nothing upstream has been decided on your
behalf: the precheck writes no bead, never advances `sweep.reported`, and
never creates the standing subject.

Graph-liveness only: the witness patrol owns SESSION-liveness (dead
assignees, orphan recovery); this sweep never touches assigned work.
Fired by orders/liveness-sweep.toml on cooldown.

Contract: graph.v2 — the compiled workflow root is Ready-visible, so a
scale-from-zero pool wakes for it (a v1 molecule root is NOT
Ready-visible, so a cold pool would never wake). Each step closes its own
step bead with gc.outcome before the graph advances. classify hands its
survivor set and both liveness words to normalize as metadata on the shared
ROOT bead — NOT as shell state, which a separate normalize step bead claimed
by a fresh session does not inherit (bead tk-7uvm9). Both step beads carry
gc.root_bead_id, so the handoff needs no knowledge of the other step's id.
The normalize step is fail-closed on that handoff, and distinguishes a
classify that failed from one whose output is unreadable.


Variables:
  {{list_cap}}: Max NEW candidates ENUMERATED INDIVIDUALLY in the batch visit body; new candidates beyond the cap are still included, grouped into labelled cohorts (the cap bounds line-by-line detail, not coverage). Carried candidates are never enumerated individually — they are a count plus a bare id list. (default=20)

Steps (3):
  ├── mol-liveness-sweep.classify: Classify every open bead; isolate the unnamed waits
  ├── mol-liveness-sweep.normalize: One batch visit on the sweep's triage subject — new candidates only, never per-bead [needs: mol-liveness-sweep.classify]
  └── mol-liveness-sweep.workflow-finalize: Finalize workflow [needs: mol-liveness-sweep.normalize]
