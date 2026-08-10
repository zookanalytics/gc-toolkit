---
name: Fleet Memory — a live lesson layer with git export (Option C)
description: Design for a runtime learning system — agents read a capped, structured
  fleet-memory surface at session start so review feedback becomes standing behavior
  within hours without a PR cycle; git receives a periodic exported snapshot for the
  evolution trail, and a ratify-or-expire TTL keeps fast application from becoming
  slow entrenchment. Composes existing gc-toolkit primitives (orders, formulas,
  template fragments, beads, the doc-keeper audits) with no new dependencies.
---

# Fleet Memory — live lesson layer with git export

## The problem, restated

Review feedback ("stop citing files as 'historical artifact'", "this comment
restates the code — delete it", "that boilerplate header doesn't apply here")
dies today unless someone hand-carries it into a versioned prompt via the full
bead → polecat → refinery → PR cycle. That path is correct for *doctrine* but
too slow and too heavy for *lessons*: by the time the PR lands, three more
polecats have made the same mistake. The other failure mode is worse: an
unversioned scratch note becomes de-facto law with no evidence, no expiry, and
no trail — one strong operator reaction on a Tuesday is gospel by Friday.

Option C's claim: **learning is a runtime concern first and a versioning
concern second.** Agents read a fast-changing memory surface at session start;
git gets a snapshot for audit and a ratification path for the few lessons that
deserve to become permanent doctrine.

Consistency-test trace (docs/architecture.md): foundation's *Agents improve* +
*Decisions have a home*, made concrete on existing primitives — beads carry
candidates, an order + formula distills, a template fragment is the read path,
and the doc-keeper pipeline is the ratification path. No new machinery class.

## 1. The substrate: structured files on the city host (with beads as the intake)

Three candidates evaluated:

**(a) Shared fleet-memory directory — RECOMMENDED.** Extend the pattern the
memory-audit already reads (mechanik's auto-memory, per the
`memory_dir` var in `formulas/mol-doc-keeper-memory-audit.toml`) into a
*shared, structured* directory on the city host, outside any rig checkout:

```
$CITY_ROOT/.gc/fleet-memory/
  lessons/
    all/            # every role reads these
    polecat/        # role-scoped: pool workers
    converse/       # role-scoped: conversation sessions
    mechanik/  ...  # one dir per role that has earned lessons
  candidates/       # agent-filed, not yet live (distiller input)
  events.jsonl      # append-only: cites, hits, challenges, promotions
  archive/          # expired + retracted lessons, kept for the export
```

One lesson = one markdown file with YAML frontmatter:

```markdown
---
id: fm-7k2ma
status: hot            # hot | active | retracted | expired
roles: [polecat]
created: 2026-08-10
expires: 2026-08-24    # TTL — mandatory, no exceptions
source: operator       # operator | distilled
evidence:
  - bead: tk-abc12
  - pr: gc-toolkit#214 review comment
hits: 0                # maintained by the distiller from events.jsonl
---
Never describe an existing file or decision as a "historical artifact" in
PR comments or docs. State what it is now; link the bead if the history
matters.
```

Plain files: greppable, diffable, legible to the operator at a glance,
snapshot-able into git verbatim, zero dependencies. This is the operator's
stated lean and it is the right call at this scale.

**(b) External memory service (mem0, Letta, MCP memory server, SQLite+CLI).**
What it buys: semantic query ("what do we know about PR comments?"), built-in
decay curves, atomic counters, multi-host sync. What it costs: a new dependency
in every agent's spawn path (an outage becomes a fleet-wide spawn hazard), an
opaque store the operator can't `cat`, and a second identity/config surface.
At the realistic scale — tens of active lessons, not tens of thousands —
querying is `ls` and decay is a TTL field. Rejected for now; the frontmatter
schema above is deliberately flat enough to migrate into SQLite or mem0 later
if the lesson count ever makes `ls` insufficient. Revisit past ~100 active
lessons or a second city (§6).

**(c) Beads as the memory.** Tempting — beads already have routing, labels,
dedup, and an audit trail. But the read surface fits badly: a bead's state
carries *one* meaning (open = unlanded, closed = landed, per
docs/architecture.md), and a "learning bead" held open forever corrupts that
semantic and pollutes every `bd ready` queue it touches. Query-at-every-spawn
also puts the bead store on the hot path of all session starts. **Verdict:
beads are the intake, files are the surface.** Candidates travel as beads
(§3) — that part of the bead machinery is exactly right — and the distiller
closes them when merged, preserving open=pending/closed=processed.

## 2. Read path: a shared prime fragment, capped hard

The mechanism already exists: `pack.toml` injects shared fragments into role
prompts via `inject_fragments_append` (the layered-startup-discovery fragment
works exactly this way). Add one fragment,
`template-fragments/fleet-memory-prime.template.md`:

> At session start (and after `gc prime` following compaction or /clear), read
> `$CITY_ROOT/.gc/fleet-memory/lessons/all/` and `lessons/<your-role>/`. These
> are standing lessons — apply them as if they were in this prompt. If one is
> wrong for your current task, proceed and append a `challenge` line to
> `events.jsonl` with your bead id.

Inject it into polecat, converse, mechanik, mayor, and deacon prompts.
Patrol/audit formulas whose `load-context` steps already run `gc prime` (e.g.
both doc-keeper formulas) pick it up with one added line in the step body. No
new spawn machinery, no new config block — enablement is the pack import,
exactly like the doc-keeper orders (doc-keeper brief §6).

**Token budget is the anti-bloat enforcement, not a nicety.** Hard caps,
checked by the distiller and by a `doctor/` check at pack-validate time:

- max **7 active lessons per role dir**, max **5 in `all/`**;
- max **80 words** of body per lesson (frontmatter excluded);
- worst-case surface for any session ≈ 12 lessons ≈ 1,200 words — small
  enough to never crowd real context.

A full role dir means the distiller must demote something before promoting
anything: curation is forced by the data structure, which is precisely the
"REMOVING guidance" requirement. Guidance bloat cannot accrete because there
is nowhere for it to accrete.

## 3. Write path and trust tiers

Nothing self-promotes silently. Three tiers:

**Tier 0 — operator, immediate.** "Learn this" in any conversation: the agent
(usually mechanik or a converse session) writes the lesson file directly with
`status: hot`, `source: operator`, TTL 14 days, and the triggering PR/bead as
evidence. Live for every session spawned after that moment — with pool workers
spawning on demand and sessions being disposable by design, propagation is
hours, not days. Reversal is `status: retracted` (file moves to `archive/`
on the next distill). Mechanik's Principle 6 ("dispatch gc-toolkit edits,
don't make them") is not violated: fleet-memory lives on the city host beside
`city.toml` and mechanik's home directory, which are already direct-edit
surfaces — it is explicitly *not* pack versioned content.

**Tier 1 — agents, mediated.** An agent that receives correction (a review
comment, an operator aside, a repeated failure) files a candidate: a standard
`task` bead, `task_kind=lesson-candidate`, label `fleet-memory`, evidence
links in the body, routed nowhere — it waits for the distiller. Filing is
cheap and unbounded; *surfacing* is what's capped.

**Tier 2 — the distiller, daily.** A new order + formula pair on the
doc-keeper pattern (`orders/fleet-memory-distill.toml` →
`mol-fleet-memory-distill`, `trigger = "cooldown"`, `interval = "24h"`,
pool `gc-toolkit.polecat`, `scope = "rig"`, top-level `phase = "vapor"` per
the pool-wake prerequisite). Each run:

1. sweeps open `lesson-candidate` beads + `candidates/`;
2. dedupes against active lessons — a **repeat increments the existing
   lesson's counter and extends its TTL** instead of minting a twin (repeated
   feedback is a strong signal, and the counter is where that signal lives);
3. promotes to `active` only candidates with **≥2 independent evidence links**
   or `source: operator`; single-evidence candidates wait, and expire from
   `candidates/` after 30 days unrepeated — one strong reaction gets a
   14-day hot trial at most, never silent tenure;
4. expires lessons past TTL, demotes lessons with unanswered challenges (§5),
   evicts (oldest, lowest-hits first) when a role dir exceeds cap;
5. closes the processed candidate beads and files **one digest visit** —
   `task_kind=visit`, routed to the converse pool per `mol-visit.toml` —
   listing promotions, expiries, and evictions. The operator reviews async
   and can veto anything; a veto is a retraction, applied same day.

Hot path and safety together: operator lessons apply same-day and stay
reversible; agent lessons apply at most one distill cycle after their second
piece of evidence, and the operator sees every promotion in the next digest.

## 4. Git export — audit trail, honestly not a review gate

A weekly order (`orders/fleet-memory-export.toml`) snapshots the entire
fleet-memory tree (lessons, archive, `events.jsonl`) into the repo under
`memory/fleet/` as one small PR via the standard polecat → refinery
`merge_strategy=mr` path — the same pipeline doc-update beads ride, no new
landing machinery, and commit-on-change so quiet weeks cost nothing.

**Is the snapshot review theater? Partly, yes — and the design should say so
rather than pretend.** Approving a snapshot PR cannot un-apply lessons that
have been live for days. Its real value is the *diff trail*: `git log
memory/fleet/` is the evolution record the operator asked for — when a lesson
appeared, what evidence it carried, when it died. Treat that PR as a
bookkeeping merge, not a judgment point.

The genuine review gate is **ratify-or-expire**, and it is the load-bearing
middle ground: a lesson is authoritative in live memory for **at most 45 days
total** (one TTL extension past the initial 14). To survive beyond that, the
distiller files an ordinary `task_kind=doc-update` bead proposing ratification
into the versioned surface — a template fragment, an agent prompt, or a
`docs/gascity-*.md` brief — which rides the existing doc-keeper delivery path
and gets a *real* PR review, because that review decides something that hasn't
happened yet: permanence. On merge, the live lesson is retired to `archive/`
with `ratified: <commit>` in its frontmatter. Not ratified in time → expires.
**Fast to apply, slow to entrench** — the gospel concern, made mechanical.

## 5. Anti-gospel mechanics

- **Evidence or it doesn't exist.** The distiller rejects any candidate
  without at least one bead id or PR link; ratification proposals carry the
  full evidence list as provenance, matching mechanik's existing
  provenance-table discipline for research dispatches.
- **TTL on everything.** No lesson file is valid without `expires`; the
  doctor check fails the surface otherwise. Expiry is the default fate —
  persistence must be earned twice (counter, then ratification).
- **Counters live in the store, not in git.** `events.jsonl` absorbs
  high-frequency appends (cites, hits, challenges) that would be commit noise
  in git; git sees only the weekly rollup. This is the one job files+JSONL do
  better than either git or beads.
- **Challenges from the floor.** Any agent that judges a lesson wrong in
  context proceeds anyway and logs a challenge event (§2 fragment). Two
  unanswered challenges → distiller demotes to `candidates/` and notes it in
  the digest. Lessons stay falsifiable by the population applying them.
- **Challenge audit.** Extend the existing memory-audit cadence with a
  monthly pass that samples active lessons and re-checks their evidence
  (does the cited convention still hold on current `main`?) — the drift-audit
  question, asked of memory instead of briefs.

## 6. Honest weaknesses

- **Two sources of truth.** For up to 45 days a behavior exists only in fleet
  memory while the versioned prompt says otherwise; a reader of the repo alone
  gets an incomplete picture. Bounded by TTL (the states must converge —
  ratify or expire) and by the distiller reconciling against git on each run
  (a lesson whose content now appears in a prompt or brief is auto-retired as
  ratified, preventing double-statement). The window is real; the design
  buys speed with it, knowingly.
- **Single-host locality.** `$CITY_ROOT/.gc/fleet-memory/` is not in any
  checkout. A second city or fresh host starts with only the ratified layer —
  which is arguably correct (unratified lessons are provisional by
  definition) — and can seed from the latest `memory/fleet/` snapshot via a
  documented one-command import, accepting up to a week of staleness. If
  multi-city becomes routine, that is the trigger to revisit substrate
  option (b), not to pre-build sync now.
- **Reduced pre-application review.** A bad Tier-1 lesson can run live for up
  to a day before the digest surfaces it. Blast radius is bounded — 80 words,
  role-scoped, evidence-gated, veto-able, TTL'd — but it is a real trade
  against the pure-git model and should be named in the digest brand so the
  operator reads it as "approve-after," not "FYI."
- **Digest fatigue.** A daily visit nobody reads makes promotions silent in
  practice. Mitigation: the distiller files a digest only when it acted;
  quiet days file nothing.

**Build estimate.** Five routed beads, all ordinary `mol-polecat-work`:
(1) directory layout + doctor check + a small `fleet-memory` helper script in
`assets/scripts/`; (2) the prime fragment + `inject_fragments_append` wiring;
(3) `mol-fleet-memory-distill` + its order; (4) the export order;
(5) the challenge-audit extension to the memory-audit. No new dependencies,
no fork changes; roughly one to two weeks of pipeline throughput, with (1)+(2)
alone already delivering operator Tier-0 learning on day one.
