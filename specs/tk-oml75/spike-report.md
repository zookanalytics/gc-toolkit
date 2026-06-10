# Spike report: per-bead resume fidelity across a drain (`tk-oml75`)

**Bead:** `tk-oml75` — *Spike: prove per-bead resume fidelity across a drain*
(child of epic `tk-q4xaj`, *Bead-Universe Operating Model v1 — implementation*)
**Branch:** `polecat/tk-oml75`
**Polecat:** `gc-toolkit/gc-toolkit.furiosa` (session `lx-wisp-k7wzdv`)
**Design source (durable):** the A2/A3 criteria, the Open Question, and the
cold-by-default constraint are durably captured in the bd ledger — spike bead
`tk-oml75`, epic `tk-q4xaj`, decision `tk-yrio` — and restated below under
**Design context (inlined for durability)**, so this report is auditable on its
own. *Working* design artifact (untracked, **not in the repo**):
`.designs/bead-universe/design-doc.md` in the `coord-bead-universe` worktree
(Phase 0; Risks §1–2; Open Q §2).
**Surveyed at:** 2026-06-06
**Status:** **PRELIMINARY analysis + operator confirmatory checklist — the
Phase-0 gate is NOT closed by this PR.** The spike bead prescribed a *per-bead*
probe (spawn a host aliased to a bead, mark it, suspend, wake, recall) plus its
wake-to-recall wall clock. Those two measurements side-effect the live city and
are **deferred to the operator** (§B precedent; verbatim script in §C). What
follows is the evidence that makes A2 the **recommended** outcome and the
checklist to confirm it — a recommendation pending confirmation, not a closed
decision.

---

## TL;DR — Recommendation (preliminary)

**Recommended outcome: A2 (binding is the cheap assembly); do NOT pull the
durable-state store (A3) into Phase 1.** This is a *recommendation*, not a
closed Phase-0 decision — it is confirmed only when the operator runs and
records the per-bead probe in §C.

`wake_mode=resume` carries the conversation across a full suspend/reap/wake
cycle. This is shown **in production today** for a *long-lived thread*: a live
`mayor-thread` resumed its conversation across a **14.7-hour cold gap** in a
single provider session — coherent throughout. The resume mechanism
(provider-transcript replay keyed by the stable session identity) is
**role-agnostic**: a per-bead host is mechanically identical to that thread
except for its alias and prompt, neither of which touches the resume path. So
the fidelity finding is *expected* to transfer to the bead-host — but the bead
explicitly asked for the *per-bead* label, "not just a long-lived city thread,"
and that literal probe is deferred (below), so the transfer is an **argument,
not yet a measurement.**

**Measurement status against the bead's three asks:**

| Bead ask | Status in this PR |
|---|---|
| (1) Fidelity — *per-bead* recall across suspend/wake | **Deferred** to operator probe (§C). Read-only production evidence (§1) makes A2 likely, but it is a long-lived *thread*, not the prescribed per-bead host. |
| (2) Token cost of one universe-load | **Recorded** (§2): ~506 tok for real epic `tk-q4xaj`. |
| (3) Wall-clock to materialize / resume | **Partly recorded** (§3): slice rebuild sub-second (measured); per-bead runtime wake-to-recall **deferred** to §C step 3. |

The **residual risk** that even a passing probe cannot settle is the
*provider-transcript retention TTL for very long suspends* (days/weeks) —
design Open Question #2 — a retention question, not a fidelity one. The design
already carries the cheap A3 hook (`session_lineage`) and a logged-`fresh`-
re-prime degraded fallback, so adopting A3 later (if steady-state TTL proves
too short) stays cheap. **A2 is the recommendation; A3 stays a contingency.**

The gating per-bead probe is **deferred to the operator** (per the `tk-k9s0k`
precedent: *a polecat must not spawn/reset agents in the live city*) — scripted
verbatim in §C. It is *expected* to confirm A2: the production evidence below
is a *stronger* fidelity signal than the minimal probe the spike prescribed
(15 h cold gap vs. a minutes-long suspend). But until it is run and recorded,
**the Phase-0 gate stays open.**

---

## Provenance

| Artifact surveyed | Source | Read at |
|---|---|---|
| Spike spec | bd `tk-oml75` | 2026-06-06 |
| A2/A3 decision criteria + Open Q #2 + cold-by-default (durable) | bd `tk-oml75` body + epic `tk-q4xaj` body (bd ledger) — inlined in "Design context" below | 2026-06-06 |
| Design doc — mechanism claims, A2/A3, Open Qs (*working artifact, **untracked**, not committed to the repo*) | `coord-bead-universe` worktree: `.designs/bead-universe/design-doc.md` | 2026-06-06 |
| `consult-host` shape (the shape to clone) | `agents/consult-host/agent.toml` + `prompt.template.md` | 2026-06-06 |
| `mayor-thread` shape (`wake_mode=resume` reference) | `agents/mayor-thread/agent.toml` | 2026-06-06 |
| **Production resume evidence** | session `lx-wisp-twghx` transcript `c30cacb0-…jsonl` | 2026-06-06 |
| Token cost | `gc bd show` over real epic `tk-q4xaj` + 5 children | 2026-06-06 |
| Precedent for operator-deferral | `specs/tk-k9s0k/spike-report.md` §B–§C | 2026-06-06 |
| Consult prior art (resume direction history) | `specs/2026-04-consult-design/consult-session-feasibility.md` | 2026-06-06 |

---

## Design context (inlined for durability)

The cited design doc is an untracked working artifact in the
`coord-bead-universe` worktree, **not committed to the repo** — so the claims
this recommendation rests on are restated here, and are independently durable in
the bd ledger (spike `tk-oml75`, epic `tk-q4xaj`, decision `tk-yrio`).

**A2 vs A3** (design "Trade-offs and Decisions"; spike `tk-oml75` acceptance):

- **A2 — resume-binding (the design's chosen path).** A bead's 1:1 host is
  reconstructed on demand and the conversation is carried by the provider's
  native resume; the bead↔session link is metadata only. Phase 1 is then the
  cheap metadata-link assembly.
- **A3 — durable conversation-state store.** A separate store duplicating what
  the provider already persists (and adding Dolt load). The design pulls A3 into
  v1 **only if** the spike shows resume fidelity is too short; the cheap hook
  (`gc.session_lineage`) is carried either way, so a later flip stays cheap.
- **Decision rule** (spike `tk-oml75` acceptance, design Phase 0): good fidelity
  ⇒ A2 (binding is the cheap assembly in Phase 1); poor fidelity ⇒ pull A3 into
  Phase 1, *proven before paying for it*.

**Open Question #2 — provider-transcript retention window** (design "Open
Questions" #2): the spike measures one suspend/wake cycle; the steady-state
retention TTL is what sets whether A3 is ever needed. It is a *retention*
property, not a *fidelity* one — the sole input that could later flip A2→A3.

**Cross-cutting constraint under test** (epic `tk-q4xaj`): *cold-by-default —
suspend/resume, not warm.* The measurements below test exactly that bet.

---

## The mechanism (why the question is mostly already answered)

`wake_mode` is the knob. Two shipped shapes bracket the probe:

| Field | `consult-host` (per-bead, abandoned) | `mayor-thread` (resume, in prod) | **bead-host probe** |
|---|---|---|---|
| `wake_mode` | `fresh` (discards conversation each wake) | **`resume`** | **`resume`** |
| `idle_timeout` | `30m` | `8h` | `8h` (suspend-don't-die) |
| binding | alias = bead id | per-thread name | **alias = bead id** |

The bead-host probe is exactly `consult-host`'s per-bead shape with
`wake_mode` flipped to `resume` and a long `idle_timeout` — the two changes the
design doc's Key Component #1 calls for.

**Resume is provider-transcript replay keyed by the stable session identity**
(design doc §"single most important finding"; Data Model §"Binding" — and
proven empirically below in §1, not merely asserted). The key
property for this spike: that replay path is **independent of what the session
is *about*.** The provider session is keyed by session identity +
`continuation_epoch`, not by role, prompt, or alias. A `mayor-thread` and a
bead-host run the *same* resume code; they differ only in (a) the alias and
(b) the rendered prompt. Neither feeds the transcript-replay machinery.

So "does resume carry the conversation for a *per-bead* host?" reduces to "does
`wake_mode=resume` carry the conversation across a runtime restart?" — which is
answerable from the resume-mode sessions already running.

---

## §1 — Measurement: FIDELITY ⇒ resume carries the conversation

**Method (read-only).** Inspected the live `wake_mode=resume` sessions
(`gc session list --json`, template `gc-toolkit.mayor-thread`) and the provider
transcript of the longest-lived one, `lx-wisp-twghx`
(alias `mayor-thread-adhoc-3025832b60` — the thread that *filed this very
spike bead* and titled itself "bead-universe operating model — exhaustive
design").

**Transcript facts** (`…/mayor-thread-adhoc-3025832b60/c30cacb0-e7f6-4475-bbc1-e247fca153cb.jsonl`):

- **One provider `sessionId`** (`c30cacb0-…`) across the entire file —
  633 JSONL entries, 2.2 MB.
- **Span:** `2026-06-06T06:23:24Z` → `2026-06-06T23:29:37Z` ≈ **17 h 06 m**.
- **Inter-entry gaps** (a reaped/suspended runtime shows up as a large gap,
  then continuation in the *same* sessionId):
  - **884 min (14.7 h)** gap, ending `21:35:51Z` — far longer than `idle_timeout=8h`;
    the runtime was unquestionably suspended/reaped, not held warm.
  - 57 min gap ending `23:25:13Z`; 11 min gap ending `22:18:47Z`.
- After each gap the conversation **continues coherently in the same
  session** — at `23:29` it is reasoning about *this* spike
  (`"P0 is running (polecat lx-wisp-k7wzdv claimed it, actively working the
  spike)"`), referencing context established 17 h earlier.

**Finding.** `wake_mode=resume` **carries the conversation across a full cold
gap** (here ~15 h, dwarfing any controller drain) with a single, continuous
provider session. Because the resume path is role-agnostic (above), this is
*expected* to be the bead-host's resume behaviour too. **Fidelity: PASS for the
resume *mechanism* — production-proven on a long-lived thread.** The *per-bead*
label the bead explicitly asked for is **not yet measured**: that is the
deferred operator probe (§C), and the Phase-0 gate stays open until it is run
and recorded.

**What this does NOT prove** (honest scoping):

1. The *per-bead* label, empirically. Mechanically identical, but the literal
   "spawn a host aliased to a bead, mark it, suspend, wake, recall" loop is the
   operator confirmatory probe (§C). Expected to confirm.
2. **Retention TTL for *very long* suspends.** The 14.7 h gap is a *lower
   bound* on the transcript-retention window. A cold-by-default bead-host may
   be revisited after days/weeks; if the provider/disk evicts the transcript
   first, resume degrades to a cold `fresh` re-prime. This is the genuine
   residual (design Open Q #2) and the only input that could later flip
   A2→A3. It is a *retention* property, not a *fidelity* one.

---

## §2 — Measurement: token cost of one universe-load

**Method.** Built the "fed slice" the design doc specifies (bead core
fields + a one-line `id — title — status` manifest of direct neighbours +
notes tail) for the **real epic `tk-q4xaj`** (5 phase children), and compared
it to the heavy alternative (`gc bd show` with full child bodies inline).
Bytes measured with `wc -c`; tokens estimated at ~4 chars/token (no provider
tokenizer available — heuristic stated explicitly).

| Load | Bytes | ~Tokens (4 ch/tok) |
|---|---|---|
| **Fed slice** (epic core + 5-child manifest + counts; 0 notes) | **2,024** | **~506** |
| Full subtree (epic + 5 children, bodies+notes inline) | 9,788 | ~2,447 |
| **Saving** | — | **~4.8× smaller** |

**Finding.** The fed slice for a real 5-child epic is **~506 tokens — well
under the design's proposed ≤ ~2k-token fed-core ceiling** (Phase 2 gate), and
~5× smaller than the heavy inline subtree. A *leaf* bead's slice is smaller
still. The fed slice scales with fanout **as titles**, not **as bodies**.

*Why the ratio differs from the design doc's 35× (190 vs 6,730 tok):* that
measurement was a different epic shape (small body, large/many children →
small fed core, big subtree). `tk-q4xaj` has a large body (1,359 ch, always
fed) and only 5 children, so both the absolute fed core and the ratio land
differently. The robust, shape-independent conclusions hold either way: the
fed slice is **small in absolute terms** and **well under the ceiling**, and
the fed/fetchable split materially cuts context cost.

---

## §3 — Measurement: wall-clock to materialize / resume

Two distinct costs:

- **Materialize the universe slice (rebuild):** building `tk-q4xaj`'s slice via
  6 separate `gc bd show` calls took **1.79 s** — an *upper bound* (each call
  re-pays gc-binary startup + a Dolt round-trip). `gc bd show <epic>` already
  returns the children embedded in one payload, so the Phase-2
  `gc bd universe --slice` projection is **one read ⇒ sub-second**, consistent
  with the design doc's "<1 s" claim. The "on resume, recompute a fresh fed
  slice" half of the lifecycle is therefore cheap.
- **Resume the runtime (process warm-up):** not precisely measurable read-only
  (the transcript only logs once the runtime is up). The consult feasibility
  study estimates **~2–10 s** spawn/warm-up; the 884-min-gap resume above
  confirms a fully-reaped runtime *does* come back. **Precise per-bead resume
  wall-clock (wake-request → first coherent recall) is the operator probe's
  timing line (§C step 3).**

**Finding.** Slice rebuild is sub-second; runtime resume is seconds. Both are
cheap enough to validate **cold-by-default (suspend/resume, not warm)** — the
design's core lifecycle bet. No reason to hold context warm for a ~500-token
saving against a fragile Dolt.

---

## Recommendation: A2 vs A3 (pending the operator probe)

> A2 = resume-binding works ⇒ Phase 1 is the cheap metadata-link assembly.
> A3 = resume fidelity too short ⇒ pull a durable conversation-state store into Phase 1.

**Recommended: A2 — pending confirmation.** Resume fidelity is proven at the
*mechanism* level and demonstrated in production across a 15-hour cold gap (on
a long-lived *thread*, not the prescribed per-bead host); binding is
metadata-only (settled in the design, no migration); the universe slice is tiny
(~506 tok) and rebuilds sub-second. On this evidence there is no fidelity-driven
reason to build a durable-state store for v1 — so A2 is the recommendation. **It
is not yet a closed decision:** the Phase-0 gate this bead defines closes only
when the operator runs §C and records the per-bead fidelity + wake-to-recall
measurements. A failing probe would re-open A2-vs-A3 (see §C pass criteria).

**A3 stays a contingency, not Phase-1 scope.** The single thing that could
flip the decision is the steady-state **transcript-retention TTL** for
long-suspended bead-hosts (Open Q #2) — measured by re-running §C after a
multi-day suspend, in steady state, not pre-built against. The design already
de-risks a later flip cheaply:

- carry `gc.session_lineage` from day one (free; the A3 hook), and
- on transcript-evicted, fire a **logged** `fresh` re-prime from the bead body
  (degraded, not silent) rather than failing.

So even the worst case is a logged degrade with a pre-wired upgrade path —
which is why A2 is the **low-regret recommendation**: adopting it keeps Phase 1
cheap, and a later flip to A3 (if the operator probe or steady-state TTL forces
it) stays cheap too.

---

## §A — The throwaway probe config (the "one config file")

Not committed as a shippable agent (Phase 1 builds the real
`agents/bead-host/agent.toml`). Recorded here verbatim so the operator probe
(§C) is reproducible. It is `consult-host` + the two design-specified changes,
plus operator-only guards so the probe never claims pool work.

**Placement (explicit).** This is a **city-scoped convention agent**:
`gc agent add --name bead-host-probe` scaffolds it under `agents/bead-host-probe/`
(per `gc agent add` — "schema-2 convention agents are city-scoped"), matching
the `scope = "city"` below. It is therefore launched by its **bare template
name** (`gc session new bead-host-probe`, mirroring the local `consult-host`
precedent) — *not* the slash-qualified `gc-toolkit/bead-host-probe` form, which
addresses imported binding agents and will not resolve for this city scaffold.

`agents/bead-host-probe/agent.toml`:

```toml
scope = "city"
wake_mode = "resume"        # the knob under test (consult-host ships "fresh")
idle_timeout = "8h"         # long: suspend-don't-die (consult-host ships "30m")
work_dir = ".gc/agents/bead-host-probe/{{.AgentBase}}"
min_active_sessions = 0
max_active_sessions = 10
nudge = "Run gc hook; the alias names the bead you host."
# Purely interactive host: never claim pool work, never a sling target.
work_query = "printf '[]'"
sling_query = "echo 'bead-host-probe is operator-spawned only; not a sling target' >&2; exit 1"
```

`agents/bead-host-probe/prompt.template.md` (minimal — prime from the bead, wait):

```markdown
# Bead-host probe

The alias names the bead you host. On start:

    gc bd show "$GC_ALIAS"
    gc bd show "$GC_ALIAS" --json | jq '.[0].metadata'

Load that universe, summarize it in ONE line, then wait for the operator.
Do NOT modify the bead. Do NOT claim other work. You exist to prove the
conversation survives suspend/wake — when asked to recall something, recall it.
```

---

## §B — Why the live probe is operator-deferred (precedent)

`specs/tk-k9s0k/spike-report.md` (a structurally identical agent-config spike
by this same rig) established the governing rule and was accepted on it:

> *"The … verifications … require side-effecting operations on the running
> loomington city. As a polecat I should not spawn / reset agents in the live
> city. The following commands are what the operator (or mechanik in review)
> should run after PR merge."*

Three reasons it applies here, more strongly:

1. Registering the probe template + `gc reload` is a **town-wide** action (20+
   active sessions at survey time).
2. The town is currently busy with the **mayor/mechanik threads designing this
   very epic**; spawning a host aliased to a real epic mid-design risks
   interference/confusion.
3. The fidelity question is already answered by **stronger** read-only
   production evidence (§1) than the minimal probe would produce.

The probe is therefore a *confirmation*, run at the operator's convenience.

---

## §C — Operator confirmatory probe (copy-paste)

```bash
cd /home/zook/loomington

# 0. Register the throwaway probe template (city-scoped), then let the
#    controller pick it up. Remove it in step 5.
gc agent add --name bead-host-probe          # then paste §A agent.toml + prompt
gc reload

# 1. Create the host on a real epic, no attach. The probe is a city-scoped
#    convention agent (step 0), so it launches by its BARE template name —
#    NOT the slash-qualified `rig/agent` form (that addresses imported binding
#    agents and will not resolve for a city scaffold).
BEAD=tk-q4xaj
gc session new bead-host-probe --alias "$BEAD" --no-attach
sleep 15; gc session peek "$BEAD" --lines 20   # expect: one-line universe summary

# 2. Advance once with a distinctive marker.
MARK="PURPLE-NARWHAL-$$"                        # any unguessable token
gc session nudge "$BEAD" "Remember this codeword verbatim for later: $MARK. Acknowledge."
sleep 20; gc session peek "$BEAD" --lines 20   # expect: acknowledgement

# 3. Suspend (kills the runtime = the drain), then TIME the resume + recall.
gc session suspend "$BEAD"
sleep 5
t0=$(date +%s)
gc session wake "$BEAD"
gc session nudge "$BEAD" "What was the codeword I asked you to remember? Quote it exactly."
sleep 25; t1=$(date +%s)
gc session peek "$BEAD" --lines 25             # PASS iff it quotes $MARK verbatim
echo "resume wall-clock (wake->recall answer): $((t1-t0))s"   # measurement §3

# 4. Harder drain (optional): force-kill the runtime instead of a clean suspend.
gc session kill "$BEAD"; gc session wake "$BEAD"
gc session nudge "$BEAD" "Recall the codeword again, exactly."
sleep 25; gc session peek "$BEAD" --lines 25

# 5. Cleanup — close the session and remove the throwaway template, then reload.
gc session close "$BEAD"
#   delete agents/bead-host-probe/ (or `gc agent` removal) ; gc reload

# 6. Retention TTL (Open Q #2): repeat steps 1-3 but leave the host suspended
#    for DAYS before waking. PASS = still recalls $MARK; FAIL (cold/blank) =>
#    that suspend exceeds the transcript-retention window; record the duration.
```

**Pass criteria:** step 3 (and 4) recall `$MARK` verbatim ⇒ confirms A2.
A blank/"I don't recall" ⇒ resume did not carry; re-open the A2/A3 question and
attach the transcript.

---

## §D — Open follow-ups (not in this spike)

- **Transcript-retention TTL** (Open Q #2) — the one residual; measured by §C
  step 6 in steady state. Sole potential A2→A3 trigger.
- **`continuation_epoch` semantics across `gc reload`/config-drift drains** —
  design Risk §"Config-drift drain"; binding assertion 3 (Phase 1) covers it.
  Not re-measured here.
- **Resume-reflects-reality** (a change made *during* suspend appears in the
  resumed host's fed slice) — Phase 1 binding assertion 5; out of scope for the
  fidelity spike but cheap to fold into §C (mutate the bead between suspend and
  wake, check the slice).
