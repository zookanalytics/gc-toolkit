# Session-per-Consult — Feasibility Study

**Status:** feasibility analysis, not approved. Parallel track to v1
conversational concierge (tk-89y). The v1 design does **not** depend on
this; this study informs whether a later upgrade is worth scoping.
**Bead:** tk-bek.
**Audience:** overseer, mechanik, architect.

## 1. The radical primitive, stated concretely

Today's approved v1 (tk-89y): a persistent concierge agent holds the
consult conversation in its own context. It loads the bead on overseer
engagement and carries the back-and-forth through bead notes and its
own in-session memory.

Proposed future: when a consult is picked up for conversation, the
machinery **spawns a dedicated session** — the way pool-workers spawn
for dispatched work today. That session's system prompt is the
*specialist's* prompt (or a consult-register variant of it), seeded
with the consult bead's full context. The overseer holds the
conversation against this session. On decision, the session writes the
note back to the bead and drains. Re-engagement a day later spawns a
fresh session seeded with current bead state.

Pointed differently: **consult-as-conversation mirrors polecat-as-task.**
The consult bead is durable; the conversation-session is ephemeral;
the specialist's prompt is the role the session plays.

## 2. Does existing session-dispatch machinery fit?

**Mostly yes.** The primitives already in place do more than half the
work:

- **Template-based spawning.** `gc session new <template>` creates a
  session from an agent template. The pool-worker pattern (routed_to
  metadata → reconciler spawns instance → instance finds its bead)
  already exists and is exactly the shape we'd need.
- **Bead-context injection.** Pool-workers receive context via the
  same two-layer model we'd use here: a static prompt template baked
  in at session start, plus a "go `bd show <id>` and read your work"
  step in that prompt. No pre-loading of bead content into the prompt
  itself — the session reads on startup. That is already how
  `mol-do-work` and the polecat formulas operate.
- **Session lifecycle.** `gc runtime drain-ack` ends a session
  cleanly. `gc session reset` restarts a session fresh while
  preserving its bead — this is the "re-engage with current bead
  state" primitive. `gc session suspend`/`resume` preserve conversation
  state across a pause.
- **Dependency waits.** `gc session wait --on-beads <id> --sleep`
  registers a dependency wait so the session drains to sleep and the
  reconciler wakes it when the watched bead closes. This is the
  *exact* primitive sub-bead nesting needs.
- **Input routing into a running session.** `gc session nudge` and
  `gc session submit` push text into a running session as user input.
  `gc session attach` lets a human tmux-attach and type directly.

**What's missing or awkward.** Two real gaps and one ergonomic one:

- **No "specialist-as-consult-host" template variant.** The architect's
  prompt today is written for the full specialist role. A consult
  conversation is a different register — narrower scope, human as the
  primary interlocutor, exit on decision. Running the specialist's
  prompt verbatim inside a consult session works, but it's a poor fit:
  the spawned session will try to do architect-scope work, not hold a
  consult. We need either a variant template per specialist
  (`agents/<specialist>/consult-prompt.template.md`) or a fragment-overlay
  that converts any specialist prompt into consult-host mode. Gastown
  has fragment/overlay machinery already; this would lean on it.
- **No conversation-relay primitive.** The session-spawn model has a
  fork: does the overseer attach the session directly (tmux), or does
  concierge stay as a gateway that relays text between the overseer
  and the session? Both are technically possible with today's
  primitives (`session attach` for the first, `session submit` + mail
  readback for the second), but neither is blessed as a pattern. The
  choice has brand consequences (see §3) and picking one is a design
  call, not an engineering one.
- **Ergonomic: cold-start latency.** Spawn-on-engagement means a
  2–10s warm-up between "overseer says 'let me discuss X'" and "the
  specialist-context session is ready to respond." Manageable, but it
  changes the feel of the interaction. A pre-warmed session pool per
  specialist would mitigate; the complexity delta of doing that is
  non-trivial.

**Net:** the primitives are 70–80% there. The missing pieces are the
specialist-consult template variant and a blessed relay vs. attach
pattern. Neither requires new engines — they are new conventions on
top of existing ones.

## 3. Human as participant, not dispatcher

This is the single hardest design question and it has no free answer.

Polecats receive work from beads and emit output (commits, bead notes,
mail). A consult-session has the *overseer* as the primary input
channel — back-and-forth is the point. Three routing shapes are
buildable on current primitives:

**Shape A — direct tmux attach.** Concierge notifies ("consult ready
in session `arc-42`"). Overseer runs `gc session attach arc-42` and
talks to the specialist session directly. On decision, the session
writes the note and drains.

- Pros: zero relay overhead; full specialist register reaches the
  overseer unfiltered.
- Cons: concierge's brand evaporates — the overseer is now talking to
  a different surface each consult (architect, refinery-reviewer,
  witness). The "branded channel" primitive fails at the surface
  level; concierge becomes a pure notifier. Also: tmux-attach as a UX
  is heavy; the overseer must remember session IDs.

**Shape B — concierge as relay.** Concierge stays as the surface.
Overseer talks to concierge. On engagement, concierge spawns the
session, reads its first "opening" message (via `gc session logs` or
a mail-back), and presents it to the overseer as if speaking for the
specialist. Overseer replies to concierge; concierge `submit`s the
reply into the session. Session replies via mail or log; concierge
reads and relays.

- Pros: preserves the single-channel brand; the overseer's surface is
  stable across specialties.
- Cons: concierge's context grows with every consult it relays. Full
  specialist context still doesn't reach the overseer unfiltered —
  concierge is a translator. The "full specialist context in the
  conversation" promise of the primitive gets thinned.

**Shape C — concierge hands off, then gets out of the way.** Concierge
notifies, overseer engages ("let's do the auth ADR"), concierge
spawns the specialist session, writes one transition message ("you're
now in a consult session with the architect — the bead is tk-…"),
and *attaches the overseer* to the session. When the session drains,
control returns to concierge. This is a hybrid of A and B.

- Pros: brand stays intact at initiation; specialist context reaches
  the overseer unfiltered during the conversation; concierge resumes
  the role afterward.
- Cons: attach/detach transitions are fragile (tmux session swaps,
  terminal re-drawing). Requires a controlled handoff primitive that
  does not exist today as a single command.

**Feasibility verdict.** A and B are buildable on current primitives
immediately. C needs a small CLI addition (something like
`gc session handoff <from-session> <to-session>`) plus a prompt
convention. B is the most conservative and the least technically risky;
A is the most "true to the primitive" but costs the brand; C is the
design the primitive probably wants once operating experience justifies
the complexity.

## 4. Specialist context loading

The question is: how does the spawning machinery get the specialist's
prompt *plus* the bead's content into the session?

- **Prompt side.** Already solved by the template system. An
  `agents/<specialist>/consult-prompt.template.md` variant, plus a
  `gc session new architect-consult` invocation, gives the session a
  specialist-as-consult-host system prompt at start.
- **Bead content side.** Also solved by the existing pattern. The
  prompt template includes instructions like "your consult bead is
  `$GC_CONSULT_BEAD`; run `bd show $GC_CONSULT_BEAD` to read the
  context, then `bd mol current $MOL` if the bead has a molecule."
  The session reads on startup; no pre-loading required.
- **Prior art.** `mol-do-work` and `mol-polecat-work` already do this:
  the session's startup step is "load context" (read bead, read
  dependencies, verify assignment). A consult formula,
  `mol-consult-host`, would follow the same shape — load-context,
  converse, capture-decision, drain.

The delta over v1 is small here: v1 has concierge reading the bead
into *its* context on engagement; session-per-consult has a fresh
session reading the bead into *its* context on spawn. Same read, new
container.

## 5. Session lifecycle

**Spawn trigger.** Lazy, on first overseer engagement. Eager (spawn at
consult-create time) wastes sessions on consults the overseer may not
engage with for hours or days, and the warm-up-latency argument for
eager is weak (engagement is usually typed, not latency-critical).

**Who spawns.** Concierge. It's already the engagement-handler in v1;
in the session-per-consult future, it additionally calls
`gc session new <specialist>-consult --alias consult-<bead-id>`.

**Termination.** Three natural exit conditions:
1. Decision written to bead, `bd close <consult-id>` succeeds,
   session drains.
2. Overseer disengages without decision — concierge writes a
   "session paused" note to the bead, calls `gc session suspend`
   (or drain with a resumable flag). Re-engagement respawns fresh.
3. Idle timeout (~30min–1h) — session auto-suspends; state on bead.

**Re-engagement semantics.** Fresh spawn is the simpler default. The
consult bead carries the conversation record as notes, so a fresh
session reading the bead on spawn has full history. Suspend/resume
is available as a cheaper path when re-engagement is within minutes,
but making it the default creates two different session states
(fresh vs. resumed) that the overseer has to distinguish. Keep it
simple: fresh spawn every engagement, bead is the source of truth.

This matches the "conversation record on bead, state machine in
session" split the v1 design doc already commits to.

## 6. Decision capture

The spawned session writes the decision note on close, same way a
polecat writes final bead notes on submit-and-exit. The formula step
`mol-consult-host.capture-decision` is the mandatory last step before
`drain-ack`, patterned exactly on `mol-polecat-work.submit-and-exit`.

No new primitive needed. The guarantee that the note gets written is
the same guarantee polecats give today for their submission step: the
formula step exists, the prompt says "do this before drain," and a
refinery-style reviewer (here, concierge) verifies the note exists
before marking the consult closed.

Edge case: session crashes mid-conversation before decision. Concierge
can detect (no close, no fresh note in N minutes) and file a follow-up
or prompt the overseer to re-engage. Same crash-recovery shape as any
other session.

## 7. Sub-bead interaction

The most promising fit with existing primitives.

**Scenario.** Overseer, in consult-session for the auth ADR, says
"before I decide, I need you to check what the current rate-limit
middleware does with token refresh." The session should file a sub-bead,
pause, and resume when the sub-bead closes with the research.

**Buildable today.** The session:
1. `bd create "research: rate-limit / token refresh interaction" -t
    task --parent <consult-id>` — files the sub-bead.
2. `gc sling <rig>/claude <sub-bead-id>` — routes the research to a
    polecat.
3. `gc session wait --on-beads <sub-bead-id> --sleep --note "research
   returned; resume with the consult"` — session drains to sleep.
4. Reconciler wakes the session when the sub-bead closes. The wake
   nudge delivers the reminder note. Session reads the closed sub-bead
   and resumes the conversation with the overseer.

**Parallel sub-beads.** For research that doesn't block the
conversation (overseer wants to keep discussing while research runs),
the session files the sub-bead *without* calling `session wait`.
Concierge watches the sub-bead's close event and nudges the consult
session when the research lands. This is two separate primitives
stitched together; the glue is concierge, and concierge already owns
the "watch for state changes" register.

**Gap.** There is no primitive for "mid-conversation session suspends
and another agent picks up the same consult to do something else."
Unlikely to be needed for consults — they are specialist-scoped — but
flagging because the architect doc mentions nested consults, and a
nested consult inside a consult-session would need its own spawn.
Doable (`gc session new <other-specialist>-consult` from within the
parent session), just recursive.

## 8. Cost / complexity delta over v1

**v1 concierge (tk-89y approved model).** Estimated 1 polecat, ~1
week. Deliverables: concierge agent skeleton, specialist prompt edits
(push-on-create, reply handling), consult protocol documented,
mayor↔concierge awareness paragraphs, example `city.toml` wiring. All
on existing primitives; no new CLI or engine work.

**Session-per-consult as successor.** Estimated 2–4 polecats, 2–3
weeks, assuming v1 already shipped. Deliverables on top of v1:

| Work | New / Reuse |
| --- | --- |
| Specialist-consult prompt variants (per producer) | New prompt per specialist; ~same-cost as specialist full prompts |
| `mol-consult-host` formula | New; patterned on `mol-do-work` |
| Concierge learns to spawn sessions + relay (Shape B) or handoff (Shape C) | New convention; C needs a small CLI addition |
| Session pool routing (optional, for warm-starts) | Reuses existing pool routing by `gc.consult_type` metadata |
| Sub-bead nesting pattern documented + example | Zero new primitives; documentation only |
| Re-engagement semantics (fresh vs. resume) | Documentation + prompt behavior |

**Shared infrastructure.** High. Sub-bead nesting, session waits,
template spawning, drain-ack, mail relay — all exist. The new work is
concept-level (a new pattern for what a session *is*) and
convention-level (a new kind of template, a new formula).

**Biggest single cost.** The per-specialist consult prompt variants.
Every specialist that wants session-per-consult needs one. The
alternative — a generic consult-host prompt fragment that overlays any
specialist prompt — is technically possible but prompt-engineering
uncertain; it may not land full specialist context at the quality the
primitive promises. This is the item most likely to surprise on
implementation.

**Is it "one good polecat's work"?** For the *core* machinery, yes —
concierge learns to spawn, one specialist gets a consult variant,
`mol-consult-host` is minted, sub-bead nesting is documented. ~1
polecat to get a working single-specialist proof. Generalizing across
specialists is then linear per specialist.

## 9. Recommendation

**Build after v1 proves out. Target 3–6 months post-v1 ship, or
earlier if v1 exposes a specific pain that session-per-consult solves.**

### Why not "build now"

- The approved v1 design is explicitly *forward-compatible* with
  session-per-consult: bead-as-conversation-record is exactly the
  durable shape a spawned session would read back in. Shipping v1
  first does not paint us into a corner.
- Two of the three biggest design choices (relay vs. attach vs.
  handoff; fresh vs. resume on re-engagement; generic fragment vs.
  per-specialist prompt) have no clear *a priori* answer. V1 operating
  data — how many consults per week, how deep are the conversations,
  does the overseer ever want specialist context unfiltered — is what
  lets us choose well. Building now bakes in guesses.
- The complexity delta (2–4× v1) is real and the payoff is
  speculative until v1 reveals what the actual pain is. If v1
  concierge handles consult volume with the overseer's full
  satisfaction, the session-per-consult upgrade is pure engineering
  for no user-visible win.

### Why not "never build"

- The primitive fit is genuinely good. Pool-workers + sessions +
  waits + drain-ack compose cleanly into consult-as-conversation.
  This is not a force-fit.
- Full specialist context in the conversation is a real quality win
  when consults get deep (architectural decisions, multi-bead
  dependency analysis). V1 concierge's summary-style context is a
  known bottleneck at the upper end of consult complexity.
- Sub-bead nesting is the killer feature. The `session wait` primitive
  existing already means side-quest research *without breaking the
  conversation thread* is buildable; v1 concierge can mimic this with
  its own context, but loses fidelity when the research is substantive.
- The architecture maturity signal matters. Session-per-consult would
  be the second "live interactive session" pattern (after polecats),
  and the design discipline of generalizing from one to two is what
  forces the pool/template/lifecycle primitives to stabilize.

### Build signal — revisit when any of these appears

- v1 concierge context exhaustion from accumulated consult conversations.
- Overseer dissatisfaction with concierge summaries — requests for
  "raw specialist voice" on specific consults.
- Consult sub-beads being filed ad-hoc instead of as a first-class
  pattern, suggesting the conversation-pause ergonomics of v1 are too
  loose.
- Third or fourth consult-producing specialist coming online, each
  with distinct register — concierge flattening all of them into one
  voice becomes the bottleneck.

### Minimum scope when the time comes

Filed as a prospective follow-up bead (not filed yet; deferred to
build-signal). Scope sketch:

- Pick one specialist (almost certainly architect, already the only
  consult producer) for the proof.
- `agents/architect/consult-prompt.template.md` — new variant.
- `formulas/mol-consult-host.toml` — three-step formula: load-context,
  host-conversation, capture-decision-and-drain.
- Concierge prompt edit: "on engagement, spawn consult session via
  `gc session new architect-consult --alias consult-<bead>`; relay per
  chosen shape (B or C); detect close and resume own surface."
- Pick Shape B or C explicitly — if C, that's one small CLI feature
  (`gc session handoff`) filed as a prerequisite bead.
- Sub-bead nesting example: document the `session wait --on-beads`
  pattern in the concierge and consult-host prompts.
- Example `city.toml` wiring.

**Explicit non-goals for the first proof:**

- Multi-specialist generalization. One specialist, end-to-end, first.
- Warm session pools. Lazy spawn only; measure cold-start latency
  before optimizing.
- Cross-rig or remote surface (Slack, etc.). Local tmux + mail only.

## 10. Open questions (residual, for the overseer when build-signal hits)

1. **Shape A, B, or C?** — direct attach, concierge-relay, or
   hand-off. The doc's lean is C eventually, B as the pragmatic start,
   A if brand doesn't matter. Needs overseer call informed by v1
   operating data.
2. **Per-specialist prompts vs. consult-host fragment?** — duplication
   cost vs. prompt-engineering uncertainty. The doc's lean is
   per-specialist, at the cost of one prompt per consult-producing
   specialist.
3. **Fresh vs. suspend/resume on re-engagement?** — default is fresh;
   confirm once operating data shows how often the overseer re-engages
   within minutes vs. hours.
4. **Warm pool or lazy spawn?** — default is lazy; revisit only if
   cold-start latency turns out to hurt the engagement feel.

## References

- `tk-bek` — this feasibility bead.
- `tk-89y` — parallel v1 doc revision (conversational concierge).
- `tk-uac` — original consult-surfacing design (now v1 model).
- `tk-a4t` — architect skeleton; source of consult protocol.
- `tk-6s5` — gc-toolkit strategic direction.
- `docs/design/consult-surfacing.md` — v1 design doc on
  `origin/polecat/tk-uac-consult-surfacing-design` (to be revised on
  tk-89y).
- `.gc/system/packs/core/assets/prompts/pool-worker.md` — existing
  template-spawn-and-run pattern referenced throughout.
- `formulas/mol-do-work`, `formulas/mol-polecat-work` — prior art for
  bead-context-loaded session lifecycle.
- `gc session wait --on-beads` — the sub-bead nesting primitive.
