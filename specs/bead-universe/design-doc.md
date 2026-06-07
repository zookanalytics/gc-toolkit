# Design: The Bead-Universe Operating Model (v1)

*Synthesis of 6 design-exploration legs (api, data, ux, scale, security, integration), each
grounded in the gc-toolkit codebase, against the operator-converged brief tk-yrio and the gate
decisions in `.plan-reviews/bead-universe/human-clarifications.md`. Leg reports: tk-0iva (api),
tk-5v69 (data), tk-u2x8 (ux), tk-cnv6 (scale), tk-weuc (security), tk-ozb0o (integration).*

---

## Executive Summary

**The whole design is three pieces, and they are mostly assembly of primitives that already
ship:**

1. **A conversation bound to a bead, that you can create, suspend, and resume.** This is a
   per-bead session (the `consult-host` shape: alias = bead id) running in **resume mode** (the
   `mayor-thread` shape: `wake_mode=resume`), plus **one new thing**: a durable, reverse-resolvable
   link between a work bead and the session hosting it.
2. **The context that conversation is primed with.** A bead's "universe" = the bead's own body +
   its one-hop neighborhood *as counts and titles* + the tail of its notes (**fed**), with
   everything else — full child/dep bodies, PR text, CI status, history — **reached on demand**.
3. **A way to see what needs you.** The existing `gc-attention.sh` board, evolved with a
   pick-a-row launcher (`gc attention open`) that creates-or-resumes the bead's conversation, and a
   flag verb (`gc attention flag`) so a bead's own LLM can raise its hand.

**The single most important finding:** the binding **link** is cheap and settled — it is
metadata-only, no schema migration. And **resume is provider-native**: `wake_mode=resume` replays
the actual provider transcript (keyed by `metadata.session_key`), which **`mayor-thread` runs in
production today** — so "carry the conversation" is a *proven mechanism*, not the lossy
notes-reconstruction build the PRD review feared. **The one thing still to prove** (and the only
reason Phase 0 exists) is whether that resume carries the conversation for a *per-bead* host
**suspended and re-woken across a drain** — not just for a long-lived city thread. The spike settles
that before we build. (The abandoned `consult-host` used the same per-bead shape but with
`wake_mode=fresh`, which discards the conversation each wake; we treat it only as a loose prior
sketch — not as vetted proof of why it was abandoned.)

**What v1 is:** a *reactive* bead-universe — land in a bead, everything is reachable, the board
brings you there — plus *proactive-via-slung-mol* (a mol slung at a bead does a cheap first
reaction and writes it back; no always-on resident loop). **What v1 is not:** a resident proactive
loop, 0..N conversations per bead, automated summarization, a human-time meter, or any new
security machinery. (All deferred per the operator's gate.)

**Cost is not the wall the brief feared.** Measured on a real epic: the fed slice is **35× smaller**
than loading the subtree (190 vs 6,730 tokens) and rebuilds in **under a second**. The genuine
costs are elsewhere — the *board* doesn't scale today (no cache), and *proactive fan-out* spends
whole sessions — so we budget **sessions, not bytes**, and **cache the board**.

**Sequence:** binding → reachability → attention → proactive. Each layer ships and is gated
independently.
**Acceptance is mechanical:** a 4-assertion binding fixture + a recall/footprint reachability
fixture, on one real subtree. No human-time number gates the ship.

---

## Problem Statement

Optimize human time: bring the human's serial, scoped attention to the *right* branch of the work
tree, and once there, make everything already known or reachable. **A conversation is linear; work
is branching** — forcing that branching work through a single conversational line forces a branching
shape into a linear format, each piece fighting the next for the same line. (The problem is *not*
"what to do when a thought branches" — beads already handle that: file a bead, come back to it. The
problem is being able to **engage one piece of work at a time**, fully, in the bead that *is* that
piece.) The fix is to make the unit of engagement a **bead with a resident LLM**, and to route the
human to the bead that needs them. (Full framing: tk-yrio.)

---

## Proposed Design

The operator's three pieces, as one loop:

> The human glances a board of **beads that need them**. They pick a row; that bead's **resident
> LLM is created or resumed**, already **primed with the bead's universe**. They read what it found,
> **ratify or redirect in one move**, and leave. Between visits the conversation is **suspended**,
> not destroyed — re-opening **resumes** it. Ahead of the human, a **slung mol** can advance a bead
> (a cheap first reaction written back to the bead), so the human arrives at advanced work.

Three design commitments shape everything:

- **Reactive-core-first.** Binding and reachability are v1's spine; "proactive" is a mol you sling,
  not a loop that runs. This matches the gate (proactivity deferred as a resident loop) and the
  natural dependency order (you can't work a universe ahead until you can reach it).
- **Cold-by-default.** Because reconstruction is cheap (<1s) and session slots are scarce, a
  bead-host **suspends** between visits and **resumes** on demand rather than staying warm. This is
  exactly what the existing on-demand lifecycle already does — we lean on it.
- **Additive rollout.** A bead-host is *one more pool-agent config*. Today's pools, the canonical
  mayor, and the refinery all keep running unchanged. Any bead *can* get a host; not every bead has
  one (capability, not deployment).

---

## Key Components

**1. The bead-host (binding + lifecycle).** A new agent config `agents/bead-host/agent.toml` =
`consult-host`'s per-bead-session shape with two changes: `wake_mode=resume` (carry the
conversation) and a long/absent `idle_timeout` (suspend, don't die). Hooked by alias = bead id,
which enforces 1:1 for free (alias uniqueness is already one-per-session). `gc session suspend`
holds it indefinitely; `gc session wake`/the launcher resumes it.

**2. The durable link (the one genuinely new piece).** Today a work bead has no durable pointer to
the session hosting it. The v1 source of truth is a **reverse link** — `metadata.hosts_bead` on the
*session* bead — resolved by search ("given a bead, find its host" = `ListByMetadata hosts_bead=<bead>`).
Metadata-only, no schema migration. Choosing a *searchable reverse* over a single forward pointer is
deliberate: it **leaves the 1:0..N door open** (a bead with zero or many hosts is just a different
search result) without committing to it — v1 *behaviour* stays 1:1. A forward `metadata.host_session`
cache on the work bead is **optional** — add it only if reverse-search proves too slow at scale.

**3. The universe slice (the prompt/context).** Three tiers:
- **Fed** (always in context): the bead's `id/title/body/status/type/priority/assignee`, the small
  curated metadata (branch/target/pr_url), neighbor **counts**, a **one-line manifest** of direct
  parent/children/deps (`id — title — status`), and the **last N notes**.
- **Fetchable** (named in the fed core, loaded on demand): full neighbor bodies, full notes/comment
  history, PR text+diff, CI status, the parent's fields.
- **Out**: anything >1 hop (reached by hopping into *that* neighbor's universe), other rigs.
`gc bd show --json` already returns this split; the one concrete build is trimming its heavy default
(full child bodies inline) down to titles — ideally behind a `gc bd universe <id> --slice`
projection so the launcher, the board, and slung mols all share one contract.

**On resume (not just create):** a host suspends while the world moves — new notes land, a PR opens,
CI flips. So resume does **two** things: the provider replays the transcript, *and* the host is
re-injected with a **freshly recomputed fed slice**, so it reflects post-suspend reality rather than
acting on a stale snapshot. (This is spine piece 2's "on resume" half — first-class, not a footnote;
a binding gate asserts it.)

**4. The attention surface.** Evolve `gc-attention.sh` (keep its deterministic ranking as the
legible floor):
- **`gc attention open <bead>`** — the pick-a-row launcher: resolve the bead's `host_session` and
  **resume**, else **create** a bead-host. One keystroke from "I see the row" to "I'm in the
  advanced conversation."
- **`gc attention flag <bead> --reason "…"`** — escalation inversion: a bead's LLM raises its own
  bead onto the board (sets `gc.attention`) instead of mailing the mayor.
- **Board changes:** admit flagged work beads (a 4th anchor kind), **add a cache** (it takes ~12s
  for 8 anchors today and must not live-recompute "every bead"), cap rows, and fold in a liveness
  glyph (`gc session list` join) so a hot bead **attaches** and a cold one **materializes**.

**5. Proactive-via-slung-mol.** No resident loop. A `mol-first-reaction` formula (modeled exactly on
`mol-review-leg` — read the bead body, do the cheap reaction, write to notes) is slung at a bead via
`gc sling … --on mol-first-reaction`, triggered operator/board-initiated or one-shot at
creation/decomposition. The "first reaction" is research→spec or "read the body and articulate what
it means" (this very run is an instance). Results land on the bead notes; the board surfaces the
advanced bead. Budget = a **dedicated small proactive pool** (max 2–3, so it never starves impl
work) + a **city-wide concurrent-session cap** (~8–16), ranked by the board's existing weight.

**6. Roles & safety.** The **refinery stays** as the sole merge gate and impl-bead closer
(node-LLMs dispatch but never merge/close — the polecat invariant carries over). **How the mayor and
mechanik are engaged is a genuinely unsettled question the operator flagged — not a thing this design
settles.** As a *provisional v1 working assumption* (cross-referenced in Open Questions, not a
commitment): the **canonical mayor** plays the root node-mayor (cross-tree concerns, pool dispatch,
routed mail) and **mechanik** stays the root/strategy thread. The reason this is a small bet rather
than a redesign: **mayor-thread / mechanik-thread are already the model's own prototypes** — a
resume-mode thread for a scope, spawned on demand, claiming no routed work; a bead-host is the same
thing scoped to a bead. So whatever the roles settle into, the *machinery* is the same. **Security is
proportionate:** one invariant (proactive slung work stays on the codex-gated `mr`
merge path, never `direct`) + one discipline (tag reached content as untrusted *data*, not
instructions). No allowlist/kill-switch/audit-program — the refinery + existing controls already
cover it.

---

## Interface

| Surface | Change | Built from |
|---|---|---|
| `gc attention open <bead>` | **New** — pick-a-row launcher: resume-or-create the bead-host | `gc session new/attach`, alias=`<bead-id>` |
| `gc attention flag <bead> --reason` | **New** — escalation inversion (sets `gc.attention`) | `gc bd update --set-metadata` |
| `gc bd universe <id> --slice` | **New** — emit the fed core (trims inline dep bodies) | projection over `gc bd show --json` |
| `gc bead-host <id>` | **New** (thin sugar) — spawn-or-resume host + set both links | `gc session new --alias`, metadata writes |
| `agents/bead-host/agent.toml` | **New** — `consult-host` shape + `wake_mode=resume` | `consult-host`, `mayor-thread` configs |
| `mol-first-reaction.toml` | **New** — one cheap first-reaction formula | `mol-review-leg` shape |
| proactive pool + session cap | **New** — small pool + reconciler clamp | pool reconciler, `gc sling` |
| `gc-attention.sh` | **Changed** — 4th anchor (flagged), cache, row cap, liveness glyph | existing gather/rank |
| `gc sling`, `gc bd create/update`, refinery, `gc order`, `gc session suspend/wake` | **Unchanged** — reused | themselves |

**The board loop (UX):** board (sibling key, e.g. `prefix+b`; `prefix+S` stays for live panes) →
pick-a-row → land on a **first-reaction card** (fixed shape: *Understanding · Found (freshness-
stamped) · Proposal · Decision needed*) → **accept** (one keystroke) or **redirect** (one sentence)
→ leave; the handled row leaves the board (a shrinking queue). Every state is named: `· cold`,
`✓ advanced (12m)`, `⚠ advanced·stale`; an empty board is a success ("nothing needs you").

---

## Data Model

- **The bead "body" = the `description` field** — the durable seed/prompt of the first reaction,
  distinct from `notes` (append-only running log, where slung-mol output lands), `design`
  (structured artifacts), and `comments`. Feed the body always + the notes tail; fetch the rest.
- **Binding = a searchable reverse metadata link**, keyed on the **stable** session identity +
  `continuation_epoch` (not the ephemeral tmux name, which goes stale on drain): `hosts_bead` on the
  *session* bead is the source of truth, resolved by search (`ListByMetadata`). A forward
  `host_session` cache on the work bead is *optional* (a perf cache, not the truth). Keeping the
  representation reverse-search-based **lays the door open to 1:0..N** with no schema change, while v1
  behaviour stays 1:1. A partial version already ships (`metadata.gc.session_name`); we formalize it.
  Carry a `gc.session_lineage` list from day one — free, and the hook for future transcript-replay /
  0..N.
- **Metadata-only, no migration.** Beads store metadata as a free-form `map[string]string` JSON
  blob; new keys cost nothing. A new column or join table would be an upstream schema migration —
  avoided.
- **Intra-rig for v1.** `bd` is rig-scoped; cross-rig links are prose-only (no formal edges). A
  universe's reach stops at the rig boundary; cross-rig reachability is out of scope.
- **Pre-work beads:** the universe must distinguish "not yet" (null PR/CI, expected) from
  "unreachable/error," so a host doesn't chase an unborn PR.

---

## Trade-offs and Decisions

- **Resume-binding (chosen) over reconstruct-from-notes or a durable-state store.** Reconstruct-
  from-notes is lossy and is *more* new code (it ignores the working resume primitive). A full
  durable-state store duplicates what the provider already persists and multiplies Dolt load — it
  moves into v1 *only* if the spike shows resume fidelity is too short (it carries the hook either
  way via `session_lineage`).
- **Cold-by-default (suspend/resume) over warm residency.** Reconstruction is cheap and slots are
  scarce; warm sessions hold context windows against a fragile 256-connection Dolt for a ~1k-token
  saving. Invest in slice + resume quality, not warmth.
- **Dedicated proactive pool + global session cap over reusing the impl pool.** Routing proactive
  work into the impl pool would starve real implementation (head-of-line blocking on 2–5 slots).
- **Board-as-primary with liveness folded in over a hard cutover.** The board answers "what needs
  me"; `prefix+S` answers "what's running." Keep both, bind the board to a sibling key, migrate by
  preference — forcing the cutover is the adoption risk.
- **Proportionate security over the stakeholder leg's program.** The model opens no meaningfully
  new attack surface (single-operator, self-to-self), and the highest-consequence path (code to
  `main`) is already gated by a **different-provider** (codex) reviewer. One invariant + one
  discipline; everything else deferred/rejected.
- **Two concerns the operator was right to drop, and *why* they're safe to drop:**
  - *"Single-writer-per-node"* — moot. A node-LLM acts on a descendant by slinging/creating against
    *that descendant's* bead, which has its **own** 1:1 binding; and `gc bd update --claim` is
    already an atomic CAS. Concurrency is handled by existing mechanisms — no new rule.
  - *"Seat the payer / four conflated humans"* — not in the source; review over-reach. N=1, one
    operator. Cost shows up as the session cap, not as a stakeholder model.

---

## Risks and Mitigations

- **[Spike-gated] Resume fidelity for a *per-bead* session across a drain.** Resume is proven for
  long-lived `mayor-thread`; the open question is whether it "carries the conversation" for a
  bead-host suspended and re-woken across a drain. **Mitigation:** the spike below settles it before
  we build; the fallback (provider transcript evicted) is a `fresh` re-prime from the bead body,
  **logged as degraded**, not silent.
- **Provider transcript retention bounds resume.** If the provider/disk evicts the transcript,
  resume degrades to cold-start. **Mitigation:** measure the window in the spike; degraded → logged
  `fresh` re-prime; durable-state store (A3) only if the window proves too short.
- **The board doesn't scale.** ~12s for 8 anchors, no cache; "every bead" would be minutes.
  **Mitigation:** promote the board's deferred caching follow-up to a v1 requirement; cap rows;
  reach individual work beads on pick-a-row, not by pre-ranking all of them.
- **Dolt is a fragile shared SPOF** the model leans on harder. **Mitigation:** a concurrent-host
  ceiling (`max_active_sessions`) + degraded mode (reactive serves last cached slice with a
  staleness banner; proactive sheds first when connection-acquire nears the 5s timeout).
- **Stale proactive worldview.** A mol slung an hour ago acted on a PR/CI snapshot since moved.
  **Mitigation:** freshness-stamp fetched facts in the card; re-fetch on human-engage.
- **Config-drift drain killing a host.** **Mitigation:** links persist on the beads, so the board
  re-summons and resumes; confirm a suspended host re-wakes cleanly after a config-drift cycle
  (binding assertion 3).

---

## Implementation Plan

Sequenced reactive-core-first; each phase independently shippable and gated. This maps to the beads
DAG.

**Phase 0 — The spike (de-risk first, gates everything).** Clone `consult-host` → a one-bead
`bead-host` probe with `wake_mode=resume`. On one real bead: create → advance once (a slung
`mol-first-reaction`, or one interactive exchange with a distinctive marker) → `gc session suspend`
→ `gc session wake`. Measure: (1) fidelity — does it recall the marker / carry the conversation, or
feel cold? (2) token cost of one universe-load. (3) wall-clock to materialize/resume. ~hours, one
new config file, zero new infra. **Outcome:** good fidelity ⇒ binding is the cheap assembly below;
poor fidelity ⇒ pull the durable-state store (A3) into Phase 1, proven *before* paying for it.

**Phase 1 — Binding (the spine).** `agents/bead-host/agent.toml` (resume mode, suspend-don't-die);
the forward+reverse link fields written atomically on host creation; the `gc bead-host <id>`
convenience. **Gate (5 assertions on one real bead):** (1) create + dual-link resolves both ways;
(2) resume carries a distinctive marker across suspend/wake; (3) survives a forced drain/respawn
(links persist; resume carries, *or* the degraded `fresh` re-prime fires + is logged);
(4) reverse-resolvable after drain (given the bead, find and wake its session); (5) **resume reflects
reality** — a change made to the bead *during* suspend (a new note, a status flip) appears in the
resumed host's fed slice, not a stale snapshot. **Honesty note:** assertion (3) passes on *either*
resume-carries *or* the logged-degraded fallback, so it does **not** by itself gate "resume fidelity
across a drain" — that is what the Phase 0 spike measures.

**Phase 2 — Reachability (the prompt).** The `gc bd universe <id> --slice` projection (trim inline
dep bodies to titles; emit the fed core); wire CI status (`gh pr checks`, the one missing fetch); the
fed/fetchable/out tiers; the pre-work null-vs-error distinction. **Gate (dual metric, automatable).**
The fixture is a **seeded subtree + a fixed list of ~10 questions, each with a known ground-truth
answer key**, answerable only by reaching into children/deps/PR/CI/history; the host gets *only* the
fed slice + the fetch tools, scored by **exact-match against the keys** (not an LLM judge). Pass =
**100% recall** AND **fed-slice ≤ the token ceiling**. *The ceiling must exist before this gate
runs:* proposed start **≤ ~2k tokens for the fed core** (from the measured ~190-token slice for a
6-child epic + headroom), **operator-tunable** — the operator/scale owner sets the final number
before Phase 2 gates.

**Phase 3 — Attention surface.** `gc attention open` (launcher → resume-or-create); `gc attention
flag` (+ `gc.attention`); `gc-attention.sh` changes (4th anchor for flagged beads, cache, row cap,
liveness glyph); the board→land→accept/redirect→leave loop + the first-reaction card shape; the
sibling keybinding. **Gate (operator-judged capstone):** from the board, pick a flagged bead → land
in its resumed universe → it correctly answers a **pre-seeded reach-requiring question with a known
answer** (checkable, not pure vibe). This is the human-in-the-loop end-to-end demo.

**v1 Definition of Done (composite):** Phase 1 binding fixture (automated) **+** Phase 2 reachability
dual-metric (automated) **+** Phase 3 end-to-end demo (operator-judged, seeded question). v1 is
"done" when these pass on one real subtree — no human-time number gates the ship.

**Phase 4 — Proactive-via-slung-mol.** `mol-first-reaction.toml` (modeled on `mol-review-leg`); the
proactive sling path; the dedicated proactive pool (max 2–3) + city-wide session cap (~8–16) + the
board-weight ranking; the `merge_strategy=mr` invariant on proactive output; the untrusted-content
provenance-tagging discipline in the slice assembly. **Gate:** a slung first-reaction writes a
verdict card to a bead; the board surfaces it as "advanced"; the human accepts/redirects in one
move; the cap halts proactive at the limit; **and any code-producing proactive output takes the
codex-gated `mr` merge path, never `direct`** (the security invariant — asserted here, not just
stated).

**Cross-cutting (carried through all phases):** intra-rig only; cold-by-default; degraded modes
(board cache fallback, proactive-sheds-first); roles (refinery unchanged; canonical mayor = root
node); measurement = **intent only**, no meter, the "fewer escalations" proxy explicitly non-gating.

---

## Open Questions

These are genuinely open (vs. settled above), and most are best answered by the running system, not
pre-specified:

1. **How are the mayor AND mechanik engaged once coordination distributes to node-LLMs?** (The
   operator's explicit live question — both roles, flagged "do not assume today's roles.")
   - *Mayor:* v1's provisional bet keeps both paths (cross-tree/pool dispatch → mayor; intra-subtree
     → node-LLM; no contention, since each bead's 1:1 binding owns its own writes). How far the
     mayor's dispatch role shrinks as node-LLMs sling their own subtree work is a v1.5 question the
     running system should answer, not one to pre-specify.
   - *Mechanik:* its conceptual engagement is equally unsettled. v1 provisionally keeps it as the
     operator's root/strategy thread (this design run lived in `mechanik-thread`), but whether
     "build Gas City itself" becomes a node-mayor over a meta-subtree, or stays a distinct role, is
     open. Named here so it is deliberately deferred, not silently dropped.
2. **Provider transcript retention window** — the spike measures one cycle; the steady-state TTL
   sets whether the durable-state store (A3) is ever needed.
3. **Suspend-vs-reap policy at scale** — suspended hosts hold identity ~indefinitely; what reaps a
   host that will never be revisited? (Scale concern; binding only needs re-wake to resume.)
4. **Does the first-reaction mol run *as* the bead-host or as a separate polecat?** v1 default:
   separate worker (reuses the polecat/refinery path unchanged; keeps the host purely interactive).
5. **Who sets the link fields — the `gc bead-host` convenience or the launcher?** Either, but they
   must be written atomically with host creation.

---

## Future directions (post-v1, captured so they are not lost)

*Operator notes, 2026-06-06 — explicitly beyond v1 scope; recorded here as the seeds for later.*

- **Contextual re-entry cue (the human's memory, not just the bead's).** On resume we restore the
  *bead's* universe — but we'll also want to trigger the *human's* memory of the conversation. A bead
  ID alone is not enough; titles are one cue that has worked. Cautious optimism that making
  conversations per-bead and durable helps materially here, but the explicit "bring back the human's
  memory" cue is its own future design.
- **The attention board outgrows the shell script.** `gc-attention.sh` stays a shell script for v1 to
  prove points fast; once proven, step back and re-architect (e.g. the `gc attention` Go command the
  api leg sketched). Prove-fast-then-evaluate — do **not** pre-build the robust version.
- **First reaction as a *process*, not only a per-bead flag.** The proactive trigger could be a
  process — polecat-pool-shaped — that scans for "beads able to be updated" (effectively unassigned /
  movable-forward) and applies a first reaction, rather than (or alongside) a per-bead `gc.proactive`
  opt-in. Different rule, same "how do I move this forward?" loop the polecat demand-scan already runs.
  (Refines the P4 trigger.)
