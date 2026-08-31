---
name: Gas City and human engagement
description: Local supplement tracking how Gas City is evolving to support human engagement — the shipping primitives, the live upstream investments, and the trajectory — with the seam gc-toolkit rides at each, and the pack's two-noun vocabulary (subject / visit). Companion to architecture.md's "How agents exist and converse"; every claim carries its verification date.
---

# Gas City and human engagement

**Vocabulary.** The pack's model has two
technical nouns. A **subject** is the durable thing a dialogue is about —
the bead; its id is the continuation-group identity; its notes and visit
history are the dialogue's record, spanning its whole life (an epic may
see hundreds of visits). A **visit** is a filed request for one bounded
sitting of that dialogue: a child bead the converse role claims, whose
outcome is recorded to the subject and which closes when it resolves —
out loud, with a sign-off, if it was ever *held*; silently against its
subject if its premise died or it turned out to need no human, in which
case it never becomes a sitting at all. At most one sitting is live per
subject (the continuation-group vacuum serializes pending visits into
it). "Conversation" is deliberately **not** a technical term in this
pack — it reverts to plain speech, which also leaves upstream's extmsg
"conversation" (an external channel thread) unambiguous.

gc-toolkit's conversation model is a bet on Gas City's own momentum: the
runtime is steadily growing the primitives a human conversation needs, and
the pack composes those primitives rather than inventing beside them
([architecture.md](architecture.md), "How agents exist and converse"). That
bet only pays if the pack actually tracks where upstream is going — so this
document is the ledger of Gas City's conversation-relevant direction: what
ships today, what is moving, and the exact seam gc-toolkit rides at each.

## Scope

**Mandate.** The single place gc-toolkit records how Gas City supports —
and is evolving to support — human conversation: the primitives, their
verified status, upstream's own investments in the space, and the boundary
where gc-toolkit's model meets them. When upstream moves, this file is
where the movement lands first, and the pack's machinery re-derives from
it.

**Boundaries.** It records upstream facts and the seams we build on; it
does not design gc-toolkit's conversation system (that is
[architecture.md](architecture.md) and its design specs) and does not
duplicate upstream reference material
([gascity-reference.md](gascity-reference.md) indexes that). Facts here
are dated; an undated claim is a bug.

## The principle

When Gas City ships a primitive that covers something the pack built
bespoke, the pack re-derives its machinery on the primitive and retires
the bespoke part. The conversation model itself is the standing example:
`gc.continuation_group` is a live core primitive that carries the whole
subject-visit binding for free, so the visit/converse spine
(`specs/tk-h9pq5/`) rides it rather than a bespoke per-bead binding.
Expect the same trade wherever upstream covers bespoke ground; that is
what riding an ecosystem means.

## Shipping primitives the conversation model rides

Each entry: the upstream fact, its verification status, and the seam.

- **Continuation groups — live core, the identity of a conversation.**
  The hook-claim path reads `gc.continuation_group` and vacuums open,
  unassigned sibling work onto the claiming session
  (`internal/beadmeta/keys.go`; verified from source 2026-08-06, clone
  `3e629ad`, and exercised live by this pack's own pool claims; live docs
  2026-08-08 confirm — "the hook atomically claims one ready bead and
  preassigns continuation siblings", tutorials/06-beads). *Seam:*
  the subject bead's id **is** the group; visits filed into the group reach
  a warm session automatically, and a cold session reconstitutes from the
  record. No reverse links, no bespoke binding.

- **Routing — `gc.routed_to` is the sole persisted key.** `gc.run_target`
  is compile-time routing intent the router resolves into `gc.routed_to`
  at dispatch (upstream #2779; verified 2026-08-06; live docs 2026-08-08
  confirm both key roles verbatim, formula-spec-v2). The read side is **exact string match**, so
  direct stamps must be rig-qualified; and under a `default_sling_formula`
  a bare sling is a formula attach that stamps nothing — stamp-don't-sling
  or `--no-formula` ([gascity-routing-model.md](gascity-routing-model.md)).
  *Seam:* a visit is ordinary routed work; pool demand spawns the
  conversation session with no operator keystroke.

- **The worker-role contract — upstream now owns the idiom.** The
  `gc-roles` pack ships a shared `gc-role-worker` contract fragment used
  by all ~12 roles (source-verified 2026-08-06, gascity-packs `0b95742`;
  **source-only** — the roles pack is absent from the public docs and the
  registry showcase as of 2026-08-08, so re-verify against the
  gascity-packs source, not the docs site):
  discovery is claim-only via the `gc gc claim` wrapper; **an empty
  continuation group after close is a hard session boundary; a successful
  claim is authoritative even across groups**. Per-role prompt citations
  older than this are stale.

  *Those two clauses are in tension for a conversation role, and the pack
  read only the second one* (tk-msfmu, 2026-08-22). The converse prompt
  carried "a claim is authoritative even when it names a different subject
  than your last one — work it the same way" and dropped the hard boundary,
  so a session whose group went dry claimed an unrelated subject and prepped
  it in a thread an operator was still reading. The clauses are not actually
  in conflict: the first governs whether to CLAIM across a group, the second
  what a claim already in hand is worth. The pack now honours both —
  `assets/scripts/converse-claim.sh` refuses to *make* the cross-group claim
  (it puts back every turn that claim assigned — the named one and any
  continuation-group siblings the claim vacuumed onto the session with it — and
  drains, per clause 1), and when a turn cannot be released it is worked rather
  than stranded, because clause 2 says a claim in hand is authoritative. The scoping is pack-side only because
  `gc hook --claim` has no group filter — its whole option set is `--claim`,
  `--drain-ack`, `--inject`, `--json` (verified 2026-08-22) — which is the
  upstream ask: a `--continuation-group` filter would make the claim/release
  round trip unnecessary. The pack also now ships
  `requirements-planner` and `task-decomposer` — planning roles adjacent
  to decomposition work. *Seam:* a conversation role is `gc-role-worker`'s
  contract with the execute/close clause replaced by hold-for-operator;
  the delta is expressed against that fragment, not a bespoke prompt. The
  planner roles are a standing adoption question wherever the pack plans
  or decomposes (see the tripwire below).

- **Human waits — the `type=human` gate, with drivers.** Upstream's live
  human-wait primitive is the `type=human` **gate** (`gc bd gate create`):
  excluded from Ready, with core notify/renudge orders that mail the
  escalation recipient (source-verified 2026-08-06; **source-only** — the
  public docs do not cover the human-gate primitive, hold labels, or the
  renudge orders as of 2026-08-08). By contrast
  `gc.routed_to=human` **parks** — no core machinery claims it, the nudge
  order fails silently on it (same verification). The sanctioned hold
  taxonomy is `hold:mayor` / `hold:external` only; a bare `human` hold
  label has no sanctioned upstream meaning. *Seam:* a human question is a bead whose
  canonical form is a visit — the visit is the
  dialogue-carrying refinement of the human gate, never a competitor
  to it; an open human gate is a legitimate named wait. The raw
  `routed_to=human` lane is a trap, not a feature.

- **Questions gate work natively — blocking dependencies.**
  `bd dep <blocker> --blocks <blocked>` creates a blocking edge, and
  blocked work is invisible to work queries (verified 2026-08-06; live
  docs 2026-08-08 confirm both, tutorials/06-beads — "blocked work is
  invisible to work queries"). `bd dep remove` exists in source
  (golden-tested; not covered in the public docs). *Seam:* a
  decision-needed visit can block its dependents with core edges — "a
  human approval is just a check nothing non-human can yet satisfy"
  composes directly, no bespoke gate machinery.

## Upstream's own conversation investment: `extmsg`

Gas City's active investment in human conversation is **`extmsg`** — and
it is provider-generic, not a chat-platform integration: a conversation
is a `(provider, account_id, conversation_id)` tuple, any client
registers via `POST /v0/extmsg/clients` and speaks inbound-POST +
SSE-reply, and upstream ships a `provider: "llm-client"` for direct LLM
clients with no chat platform at all (verified 2026-08-08,
guides/connected-clients). Slack and Discord are adapter packs over that
same API. Bindings attach a conversation to a **session or a configured
agent** — agent bindings survive restarts by cold-waking a session — and
`gc extmsg handoff` rebinds a live conversation to another agent
("pure transport"; the routing judgment lives in the agent's prompt). It is further along than a casual read suggests (live docs
2026-08-08): CLI verbs `gc extmsg bind` / `handoff` / `unbind`; an API
plane with client registration, `POST /v0/extmsg/inbound`, and a
long-lived SSE reply stream per `(provider, account_id,
conversation_id)`; and — the telling detail — **the first inbound turn
implicitly creates the conversation binding**, durable and
reconnect-safe via sequence-number replay (guides/connected-clients).
Slack and Discord ship as first-party packs. The outbound path is
already exercised by the oversight-rig pack's rollup delivery
(`specs/tk-3s5uo/`).

This is a **different plane** from gc-toolkit's beads-as-turns — extmsg
is channel-shaped and session-bound; ours is operator-internal and
record-durable — and the two are complementary, not competing. The
boundary, on the record: **when an external channel arrives, the
subject bead is the natural binding anchor — the two models meet at the
subject bead.** A Slack thread about a piece of work should bind where
that work's conversation already lives, not beside it.

`gc.attention` has zero upstream meaning (verified 2026-08-06), and the
pack does not use it either — there is no flag-for-attention concept.
"An agent believes a human should look at this" has exactly one form —
file a visit on the subject — so the board derives what is
pressing from real state (open visits, human gates, stranded work) rather
than from self-assertions with no lifecycle.

## How questions reach a human today (source-verified 2026-08-08)

Upstream surfaces "a human is needed" at two tiers with sharply different
maturity — the split matters more than any single fact here:

- **Live-session questions (ephemeral) get first-class treatment.** A
  runtime-detected prompt becomes a **pending interaction**
  (`request_id`, `kind`, optional prompt/options), emitted on the
  per-session SSE stream, aggregated city-wide
  (`GET /v0/city/{city}/pending`, concurrent probe with partial-failure
  reporting), answerable via a respond endpoint — and the **dashboard
  ranks it**: a home-view attention queue with closed alert kinds
  (`pending-decision`, `run-needs-operator`, `run-thrashing`,
  `operator-mail`), a single top-ranked "One Mark," and an agents-nav
  "Needs you (N)" section with reasons (awaiting-input / errored /
  rate-limited / stalled) and mapped actions (respond / reset / nudge).
  Upstream is actively building a needs-me surface for *sessions*.
- **Durable human-gate beads (the graph tier) are reachable but have no
  surface identity.** Core's built-in gate watcher skips human gates,
  and `await_type` never crosses the supervisor API — no dashboard or
  API object represents a gate. What core's bundled bootstrap pack ships
  instead is **mail + renudge**: an order that mails on human-gate
  creation (addressee: assignee → `gc.deferred_assignee` →
  `$GC_ESCALATION_RECIPIENT`, default `"human"`) and a sweep that
  re-nudges stale open gates hourly. Plus `gc bd gate list` and an
  indirect projection: a run blocked on a gate shows as "Blocked,
  awaiting operator," and the gate's mail surfaces as an
  `operator-mail` alert. Upstream's own notes call gates "beads with
  metadata" — the primitive is theirs; the *presentation* is not built.
- **Formula-level questions are prose.** The build-factory schemas make
  artifact `status: questions|blocked` machine-readable and require an
  Open Questions section, but individual questions carry no needs-human
  flag; the worker contract forbids asking after a claim; and
  `interaction_mode=interactive` names no mechanism for the ask to
  travel. A question that must survive its session has exactly one
  sound home today: a gate bead in the graph.

*Seam:* gc-toolkit's conversation model is the missing top of this
stack, not a competitor to it — a gate filed as a **visit** gives the
durable tier what the session tier already has (framing, a
conversation, an owner), and the board gives gates the first-class
ranked identity `await_type` lacks. Ride the notify/renudge orders and
the alert model rather than duplicating them.

## How a conversation starts: operator-origin intake (2026-08-14)

Every other visit producer in the pack is **agent-origin** and attaches to a
bead that already exists — `mol-first-reaction` files one after reacting,
`liveness-sweep.sh` files one on a stall, `gc-helm.sh open` files one
on a row the operator picked off the board. None of them answers "I need an
agent on topic X," where X has no bead yet. That affordance existed under the
retired `-thread` model (a keystroke, any moment) and was not carried across
when threads were dropped for converse. Converse supplies the persistence
threads lacked; `assets/scripts/gc-visit-open.sh` supplies the intake:

```sh
gc-visit-open "why does the refinery hold siblings for a full pass?"
gc-visit-open tk-abc12                     # an existing bead is its own subject
gc-visit-open "a gascity topic" --rig gascity
gc-visit-open "just talk to me about X" --no-react
```

It creates the subject bead from the topic string — the string is the durable
**body**, which is what the converse session reads at claim time, and the title
is a one-line label derived from it — and then opens the conversation one of
two ways.

**The topic is a paragraph, and the title is not the topic.** The key exists so
the operator can type as much as they need to (the popup is sized multi-line to
invite it), and `bd create` refuses a title over 500 bytes — so passing the
topic through as the title made the key fail on exactly the input it was built
for: a 579-character paragraph filed nothing at all, and said only that the
create "returned no id" (tk-wp50s). The title is now collapsed to one line and
cut back to a word boundary with an ellipsis if it is long; the body always
carries what was typed, verbatim.

**The default rig is fixed: `gc-toolkit`** (`--rig` overrides,
`GC_VISIT_DEFAULT_RIG` moves the default). Converse is `scope = "rig"` and its
pool name is rig-qualified, so a topic that is not rig-specific still has to
land somewhere. It is deliberately *not* inferred from cwd: the command is
fired from wherever the operator happens to be sitting, and a destination that
varies silently with the shell's directory is the worst failure mode an intake
path can have.

**Two paths, and the choice is not a preference.** The preferred path slings
`mol-first-reaction` at the new subject, and *that formula files the visit*
from its `advance-and-drain` step — so the operator arrives at a framed
conversation with a first-reaction card already written, not a blank one. The
script files nothing on that path; a second visit would split one conversation
into two sittings of the same subject.

The fallback path (`--no-react`, or automatically) files the visit
immediately, through `gc-helm.sh open --reason/--body`. **Visit filing lives
in exactly one place** — that verb's marked `gate-visit` block — and the intake
script calls it rather than copying it, so the metadata shape, the
subject-exists gate, the one-open-visit-per-subject gate and the board cache
bust are inherited. `assets/scripts/gate-visit.test.sh` now sweeps
`assets/scripts/*.sh` as well as `formulas/*.toml`, so that copy is guarded on
the same terms as the formula ones.

**Why the fallback stays.** The react path is fire-and-forget: `gc sling`
routes the subject and returns 0, and the visit appears only when a
proactive session runs the formula. Proactive is always-on
(`max_active_sessions = 2` is its only throttle; routed beads queue until a
slot frees), so a queued reaction is picked up rather than dropped — but the
path is still chosen by asking `tools/gc-proactive.sh deliverable` first
(exit 0/1 plus the reason, printed either way), and the fallback files the
visit directly whenever the answer is no. The seam is fail-safe by design:
if proactive could ever again decline work, an unguarded react path would
leave a routed bead nobody picks up and *no visit at all* — a topic that
looks filed and is silently forgotten, the one outcome this channel exists
to prevent.

Note what is *not* here: there is no mail-to-visit bridge, and no seam for one.
A mailbox whose endpoint spins up a visit per message was considered and
rejected outright (operator ruling, 2026-08-14) — a mail is already a bead and
a visit is already a bead, so the bridge converts bead to bead for an extra hop
and tick of latency, and it puts a background process on the critical path of
"the operator wants to talk about X." If external-origin intake is ever wanted,
gascity has its own external-messaging process and it belongs there.

The key binding that fires this from anywhere is tracked separately (tk-bn1oi).

**The intake also stamps `gc.origin=operator` on the subject** (both paths: a
topic it creates, and an existing bead pointed at — never over an origin
already recorded). The prose line in the body says the same thing to a human
and is not a predicate: it has already drifted across two script generations
plus one an agent typed by hand, and a `--desc-contains` sweep for it matches
beads that merely *quote* it — three of thirteen live hits, including the bead
that specified this change. The key is what the return trip below selects on.
Subjects filed before it existed are carried across by
`assets/scripts/backfill-operator-origin.sh`, which owns the anchored
line-match, once, where a wrong match is visible and re-runnable.

## How a parked conversation comes back (2026-08-22)

A sitting that reaches a conclusion **parks** its subject with a
`gc.takeaway` — one board-visible headline of what was settled or what is
being waited for. That stamp does three unrelated jobs, and two of them
conspired:

1. it parks the board row (`gather_meta_anchors` emits `kind:"parked"`,
   floored at `LOW`, because a conversation that reached a takeaway wants
   nothing and only has to stay findable); and
2. it **mutes the stall detector** — the liveness sweep reads a
   takeaway on a root or its anchor as a wait a human named and owns.

So the one automation in the city that files visits was silenced by the exact
stamp that recorded the wait. A subject that had dispatched work could not be
brought back *by* the system — only by the operator noticing a row. Measured:
`tk-z9nln` parked with *"next sitting when findings land"*; the findings landed
at 17:54Z; the operator found it by eye at 22:13Z, **4h19m** later, and the
audit's headline sat in a merged file, untold.

Two changes close that (tk-2cyxo), and they are deliberately separate:

- **The push.** The liveness sweep (`assets/scripts/liveness-sweep.sh`,
  which absorbed the parked-disposition detector) files one visit back to the
  converse pool when a **parked, operator-origin** subject's routed work has
  **all landed**. It goes through
  `gc-helm.sh open`, so it inherits the canonical `gate-visit` block and the
  one-open-visit-per-subject gate rather than re-deriving them. It writes
  exactly one key — `disposition_flagged`, the sorted id set of the work that
  landed, which is the dedup key for after that visit closes — and it **never
  clears the takeaway**: that stamp is the record of what the sitting
  concluded, and the visit is additive.
- **The un-mute.** A takeaway whose recorded wait has *fully closed* no longer
  exempts a workflow from the stall detection in `liveness-sweep.sh`. One carve-out, not a
  removal: `triage.hold` still mutes unconditionally, because it names its wait
  in prose with no edge to discharge. The predicate lives once, in the sweep
  (`--wait-spent <bead-id>`), and the detector asks it — a mirrored predicate in
  two scripts is two things to keep in step.

**"Routed work" is wider than the board's `disposition_due`, and it has to
be.** The board derives disposition-due from `waiting_on` alone — the `blocks`
edges `gc-helm takeaway --waiting-on` writes. But the canonical converse shape
files routed work as a **child** of the subject, and a parent cannot be blocked
by its own descendant:

```
$ gc bd dep add tk-z9nln tk-wvrga -t blocks
Error: tk-z9nln cannot be blocked by its descendant tk-wvrga:
blocked status cascades to descendants, so tk-wvrga would inherit
the block and never close
```

The guard is correct. The consequence is that the default shape produces zero
`waiting_on` edges, so a readiness test keyed on them can never fire for it —
including for the very subject the incident was measured on. The sweep
therefore reads the **union** of the subject's `blocks` edges and its children
(`bd list --parent`, the only way to ask, since a parent-child edge is stored
on the child). Readiness is: at least one recorded wait exists, and every one
of them is closed.

The two surfaces are knowingly out of step until the board can see children at
all — a parked row currently hardcodes `children:[]` (tk-a9k0l). The board
stays quiet and correct; the sweep is what pushes.

**What is still not covered.** Work routed with *neither* recording — a sibling
bead named only in the takeaway prose — is invisible to both. So is an
agent-origin park, by the ruling's own scope. Both wait for an eye.

## How a held sitting ends (source-verified 2026-08-11; attachment rung reconciled 2026-08-12)

A hold has no timeout *in the pack's doctrine* — but the runtime under it
does end sittings, and every surface that said otherwise was wrong. The
mechanism, verified against the gascity source (rig checkout `7cff88fdc`,
2026-08-11) after an operator lost two threads mid-attention (`tk-bzm86`):

- **`wisp_ttl` is not this, and never was.** `[daemon] wisp_ttl` is how
  long a **closed** wisp — an ephemeral v1 formula-run bead — survives
  before the GC deletes it (`internal/config/config.go`, `WispTTL`;
  enabled only when `wisp_gc_interval` and `wisp_ttl` are both non-zero).
  It reaps *records*, not sessions, and never touches a live held visit.
  Reading the city's `wisp_ttl = "8h"` as the thing that collects
  conversations is a coincidence of two unrelated 8h values.
- **The clock that ends a sitting is the agent's own `idle_timeout`** —
  pack-owned config (`agents/converse/agent.toml`), not core policy.
- **"Idle" means the terminal produced no output.** The reconciler's
  `checkIdle` reads the provider's last activity, which for tmux is the
  most recent per-window `#{window_activity}` (`Tmux.rawSessionActivity`,
  `internal/runtime/tmux/tmux.go`) — pane output and `send-keys`. **An
  operator reading a held thread generates neither**, so activity alone
  cannot tell sustained attention from abandonment. For a **detached**
  reader — watching through the dashboard or scrollback, not connected to
  the pane — that is the whole story, and reading a thread for 8h is what
  gets it collected. (An *attached* terminal is now observed separately and
  defers the reap — see *The core seam, now closed*, below.)
- **Holding work defers the stop, but only briefly.**
  `DecideIdleTimeout` (`internal/session/lifecycle_timers.go`) walks
  blocker → pending interaction → attachment → assigned work → stop, and a
  held visit is assigned work, so the stop defers on the assigned-work rung
  (the attachment rung above it — landed since; see below — is a separate,
  uncapped defer). The reconciler caps the assigned-work streak:
  `assigned_work_defer_limit` (default 3 —
  `defaultAssignedWorkDeferLimit`, `cmd/gc/assigned_work_defer_tracker.go`)
  consecutive same-anchor defers, then `DecideAssignedWorkExhausted`
  forces the stop under its own `assigned_work_exhausted` reason. At
  `patrol_interval = "30s"` the defer buys ~90 seconds, not immortality.
- **The kill erases the evidence.** The stop path calls
  `ClearScrollback` (`cmd/gc/session_reconciler.go`), wiping the pane's
  history, and the converse template's `wake_mode = "fresh"` makes the
  respawn a clean provider session. Contrast `wake_mode = "resume"`,
  which replays the provider transcript across gaps far longer than the
  timeout (measured at ~15h, `specs/tk-oml75/spike-report.md` §1). So a
  reaped converse thread is **unrecoverable, not merely hidden**, and no
  remedy may assume the operator can reopen it.

*Seam:* **nothing pack-owned runs at kill time**, so a warn-before-reap
is not available to us; the pack's only lever is to have already written
the trace. Hence the converse contract stamps the subject's takeaway when
the hold *begins* (not only at close) — a reap then leaves a dated record
of what the sitting was waiting for — and every deliberate close of a
**held** sitting ends with a sign-off block naming the outcome and the
subject to look at next. Longevity is deliberately not the remedy:
raising `idle_timeout` only widens the window in which a dead thread
looks alive.

*The size of that trace (2026-08-22, `tk-9tbbk.1`):* the takeaway is the
board's NEEDS cell — one line in a terminal table — and it is capped at
**140 characters**, which `gc-helm takeaway` now enforces by refusing a
longer text rather than trimming it. While the cap was documentation
alone it ran 22-for-23 against: the stored takeaways averaged
597 characters and were 91% of all the NEEDS text on the board, and
converse wrote all five of the longest. Whatever does not fit is detail,
and detail belongs in the subject's notes or the thread.

*The limit of a written trace, and what closes it (2026-08-22,
`tk-2plde`):* the takeaway is **one string, frozen when it is written**.
That is enough for a reap — the record survives — and not enough for a
wait. A sitting that ROUTES work out of a subject records "routed —
tk-hgmob slung; nothing further needed here" and the subject goes on
saying exactly that after tk-hgmob merges, because nothing in the city
re-reads prose. The operator's framing: *"waiting, holding, those are
graph states, not comments."* So a routed wait is also written as a
**`blocks` edge** — `gc-helm takeaway <subject> "…" --waiting-on
<work-bead>` writes both in one call — and the board re-derives on every
render whether the blocker has closed, promoting the row to *"blocker
landed — dispose or resume"* when it has. Without the edge the wait is
unaskable: tk-yps55 sat parked for 29 hours after its fix merged and
cost a whole sitting to rediscover that it was finished, on a parked
budget where roughly 40% of the reserved rows were already terminal.
Pass `--waiting-on` for every bead a sitting routes work into; a wait
recorded only in prose is a wait nothing will ever re-ask.

*Where that edge cannot be written, and what re-asks the wait instead
(2026-08-22, `tk-a9k0l`):* the canonical converse shape files the routed
work as a **child** of the subject, and beads refuses a `blocks` edge
from a parent to its own descendant — `cannot be blocked by its
descendant: blocked status cascades to descendants` — so `--waiting-on`
is not available for exactly that shape, and no amount of hygiene makes
it available. The relation the board re-asks there is the
**parent-child roll-up**: a `parked` subject with children is banded by
them rather than floored at LOW, so open work under a parked
conversation reads as the frontier it is. Both boards do this
(`assets/scripts/gc-helm.sh`, `services/helm/internal/`). It also
matters that a plain child bead is not an anchor of its own: it reaches
the board ONLY through its parent's roll-up, so while these kinds
carried a hardcoded empty child set, parking a subject deleted its open
children from every surface. Measured on `tk-z9nln`: the row read
`m_total=0`, and the deliverable it was waiting for was open,
unassigned, unrouted and on no board at all. Pushing the operator once
the last child closes is a separate piece of work (`tk-2cyxo`); the
board stays quiet for that state and only stops mis-stating it.

*The converse of that rule (added 2026-08-14, tk-mndjz):* a visit that
never held closes **silently** — no sign-off, no thread output at all,
only the note appended to its subject. That covers a visit folded into a
sibling sitting, and one whose premise died between filing and claiming
or turned out to name a state that needs no human (`gc.outcome=moot` /
`benign`; an open PR awaiting the operator's own review is the canonical
case). The sign-off exists because an unanswered framing left in a
vanishing thread reads as a crash; where no framing was ever posted there
is no question to abandon, and holding a sitting anyway spends the
attention the whole engagement model is trying to conserve.

*The core seam, now closed (landed 2026-08-12):* attachment is observable —
`runtime.Provider.IsAttached` — and the idle ladder now consults it.
gascity merged `gc-rjtk1` (PR #126, commit `c8bff331d`; confirmed in
gascity `origin/main` 809a97f47): the reconciler supplies
`TimerFacts.Attached` from `sp.IsAttached(name)`
(`cmd/gc/session_reconciler.go`), and `DecideIdleTimeout`
(`internal/session/lifecycle_timers.go`) gained an **attachment rung**
between pending interaction and assigned work —
`if f.Attached { return deferDecision("attached", "deferred_attached") }`.
So "an operator is attached to this pane" now defers the reap, and
read-attention on a connected pane finally counts. The rung is
deliberately narrow, so the mechanism above still holds:

- **A defer, not an exemption.** It is re-evaluated every tick and the stop
  resumes the moment the terminal detaches — a forgotten attached pane is
  *not* immortal. Unlike the pending arm it cancels no drain and skips no
  wake pass; it is a plain defer.
- **The *attached* case only.** Idle is still measured from output
  activity, so a **detached** reader (dashboard or scrollback) is still
  indistinguishable from abandonment and still gets collected — attachment
  is a separate signal, not a fix to activity measurement. The pack's
  trace-at-hold-begin lever above therefore still earns its keep.
- **Aligns two subsystems.** `ComputeAwakeSet` already re-wakes an attached
  session via its "attached" wake override, so the old behavior killed a
  watched pane only to bounce it straight back awake — the same
  idle-kill/wake treadmill the assigned-work rung fixed (`ga-3ox7rk`).
- **Idle-timeout only.** `DecideMaxSessionAge` (a health restart, e.g.
  credential expiry) still fires regardless of who is attached.

Design record: `specs/tk-bzm86/design-doc.md`; the cross-rig filing
`gc-rjtk1` is now resolved upstream.

*This section is about a sitting that is still **held**.* A sitting that
has **ended** leaves a live pane with no wake reason, and that pane dies
on a different, much shorter clock — see
*How a pane dies when no sitting is live*, below. Reading this section as
the complete account of how the operator's pane goes is what left the
post-sitting window unguarded.

## How a pane dies when no sitting is live (source-verified 2026-08-20)

The section above answers "what ends a **held** sitting". It is not the
only way the operator's pane goes, and the other way is the one that has
cost them words. Verified against the gascity source and this city's
event/reconciler record after an operator lost an unsubmitted
multi-paragraph reply (`tk-tufrw`); full evidence in
`specs/tk-tufrw/teardown-input-loss.md`.

Once a sitting **ends** — the visit closed, the takeaway stamped, the
sign-off posted — the session still has a live pane, and the thread the
operator is reading is still on screen. What it no longer has is a wake
reason of its own. `ComputeAwakeSet` finds none, and the reconciler's
`if !shouldWake && target.alive` arm (`cmd/gc/session_reconciler.go`)
begins a drain whose reason resolves to the `switch` default,
**`no-wake-reason`**. Measured on 2026-08-20: the tick at 22:03:13Z saw
`state: awake`, the same tick at 22:03:17Z recorded `state: draining`,
and the stop landed at 22:04:15Z — a **~58-second** window.

**What holds the pane up in the meantime is not the operator.** The
converse pool is demand-driven (`min_active_sessions = 0`), so a live
session survives on the pool having open visits at all — anyone's. In
this incident the operator's own visit had closed an hour earlier, and
the pane outlived it only because an unrelated visit (`tk-lrylu`, a
different subject entirely) stayed open; that one closed at 22:02:15Z and
the drain began 58 seconds later. Do not read a still-present pane as
evidence that the system knows you are there. It does not: neither the
operator's attention nor anything they have typed is an input to the
decision.

Three things about that path are worth knowing before trusting a pane:

- **Nothing is typed into the pane; the pane is taken whole.** The drain
  signals through *metadata*, not keystrokes. `beginSessionDrainInfo`
  only records the drain — it takes a `runtime.Provider` and ignores it
  (`_ runtime.Provider`, `cmd/gc/session_wake.go`). One tick later, if
  nothing cancelled, `advanceSessionDrainsWithSessionsTraced` sets
  `GC_DRAIN_ACK=1` on the session, and says so in as many words: the
  reconciler's Phase 1 drain-ack check "calls `sp.Stop()` for a clean
  SIGTERM/SIGKILL — no Ctrl-C keystroke injection into the pane." That
  stop is `Provider.Stop` (`internal/runtime/tmux/adapter.go`) →
  `KillSessionWithProcessesExcluding`
  (`internal/runtime/tmux/tmux.go`): SIGTERM to the pane's whole
  process tree with a grace window, SIGKILL to whatever survives it,
  then `tmux kill-session`. `Provider.Interrupt` — the one API that
  would put a `C-c` in the pane — is not on this path at all; the drain
  code's only interrupt helper, `verifiedInterrupt`, has no caller
  outside its own test. So the composer is never cleared first. The
  draft is still sitting in the pane, intact, for the whole window, and
  then the pane is gone.
- **Attachment protects, but it stops protecting at the ack.**
  Attachment is a wake cause (`WakeCauseAttached`,
  `internal/session/lifecycle_projection.go`), and `ComputeAwakeSet`
  applies it as an override that wakes *even a drained session*
  (`cmd/gc/compute_awake_set.go`), so an *attached* pane does not enter
  this drain, and re-attaching during the first tick of one cancels it
  — `no-wake-reason` is cancellable, so any wake reason that reappears
  clears the ack and drops the drain. Two things eat that protection.
  *First*, this city runs **one tmux client** switched between
  per-agent sessions, so at most one session reports
  `session_attached=1` at a time and every other live pane reads as
  unattached; the idle ladder's attachment rung is on the `idle` path
  only, and `no-wake-reason` never reaches it. *Second*, once
  `GC_DRAIN_ACK` is set, the stop is decided by the
  Phase 1 drain-ack consumer (`cmd/gc/session_reconciler.go`), whose
  cancels are assigned work, a *structured* pending interaction, and a
  config-drift-plus-recently-attached case — plain attachment on a
  `no-wake-reason` ack is not one of them, so attaching late does not
  call the kill off. And typing is not a cancel condition at any point
  on this path: a pending *interaction* is a prompt the agent is blocked
  on, not a half-written reply, and nothing in the decision reads the
  pane's contents.
- **The stop event's wording is misleading here.** It reads
  `"drain acknowledged by agent"` even when the agent never ran
  `gc runtime drain-ack`: the reconciler acks on its behalf
  (`GC_DRAIN_ACK_SOURCE=reconciler`, `cmd/gc/session_wake.go`) and
  `finalizeDrainAckStoppedSession` emits the same string either way. Do
  not read that event as an agent decision.

*Seam:* the same one as the reap — **nothing pack-owned runs at kill
time**, so the pack cannot capture pending input here. Ruled out with
evidence in the determination: tmux `session-closed`/`pane-exited` hooks
(fire after the pane is gone), a Claude Code `SessionEnd` hook (never receives the
composer buffer), a cooldown order (multi-minute cadence against a
~58-second window), and `pipe-pane` logging (a redrawing TUI makes the
volume unusable). The capture has to live in the drain path upstream:
filed as `gc-ze774`, with `gc-8g41r`'s `InputAreaState` — buffered-input
detection over `tmux capture-pane` — as the primitive it should consume.

**The operator's ruling on this (2026-08-20T22:21Z):** *"draining a
session with typed text should be a hard no."* Pending input is a hard
blocker on teardown, not something to capture on the way out — capture
and warning are the fallback for a teardown that happens anyway. That
prohibition is what `gc-ze774` is filed to implement; the pack has no
part of it to build.

**What follows for the pack.** Treat "the sitting ended" as the start of
a short countdown on that pane, not as a quiet state. The existing
lever still applies and is still the only one we own: the record has to
be written before the pane matters — the takeaway stamped at hold time,
the outcome appended as soon as a sitting settles anything, the sign-off
posted at close. Nothing has changed about that. What is new is that the
operator's *own* unsent words have no such protection, and until
`gc-ze774` lands they are not durable anywhere.

## Watch items — moving now, re-verify before building on them

- **`gc.session_affinity`** — **this watch fired; re-derived 2026-08-14.**
  The read side landed. Upstream #4845 (`b02df40bc`, 2026-08-02; reached
  the fork on the 2026-08-14 rebase) makes `gc.session_affinity ==
  "require"` a *necessary* conjunct of the controller's
  stalled-continuation backstop — first in the candidate predicate
  (`cmd/gc/build_desired_state.go:4703`,
  `continuationRowCouldBeCandidate`), then again in the last-moment guard
  before delivery (`cmd/gc/idle_nudge.go:233`,
  `poolContinuationBackstop.revalidate`), where anything but `require`
  resolves to *clear*: the pending nudge is dropped and its pacing marker
  erased. The key therefore now helps decide whether a stalled graph-v2
  continuation step is nudged back to the session already holding it. The
  backstop is deliberately bounded (90-second grace, 3-minute backoff,
  three attempts) and also demands exact
  store/workflow-root/session-identity/session-generation provenance plus
  a non-empty `gc.continuation_group`. The write side the 2026-08-06 pass
  noted is still live and is what populates the readers: the value is
  stamped at route time on pool-routed graph.v2 steps
  (`internal/graphroute/graphroute.go:219`) and by drain on shared-drain
  executable steps (`internal/dispatch/drain.go:1532`) — jointly the
  population this backstop can reach. The separate
  `gc.drain_continuation_group` key also still exists
  (`internal/beadmeta/keys.go:81`), feeding drain's shared-group suffix
  (`internal/dispatch/drain.go:1557`).

  What survives narrowly: **no *routing* path reads it.** The hook vacuum
  still routes on `gc.continuation_group` + `gc.root_bead_id`, and
  affinity cannot send a bead anywhere. Upstream's own comments still say
  exactly that (`internal/beadmeta/keys.go:476`, echoed at
  `cmd/gc/pool_session_name.go:448`) and #4845 did not update them —
  accurate about routing, stale as a description of consumption. **The
  seam:** warm continuity is no longer carried by the group key alone.
  Clearing or rewriting `gc.session_affinity` on a live step now silently
  disables the one path that recovers a stalled continuation, so treat it
  as load-bearing state cleared *only* together with the group
  (`beadmeta.SessionAffinityMetadataKeys` is that list), not as hygiene on
  an advisory field.
- **The roles pack's growth** — every new upstream role is a standing
  question against a hand-authored one here. Recorded tripwire: when
  upstream ships a role covering something the pack hand-authors,
  re-argue adoption for that role specifically (`tk-h9pq5` Q5).
- **Dashboard surface** — upstream ships `gc dashboard` (Vite SPA over
  the supervisor API); the pack's sanctioned augmentation seam is the
  `proxy_process` `/svc/` route (`services/helm/` already uses it). Any
  conversation surface work should land behind that seam, not in new
  bespoke plumbing.
- **Two helm boards — RESOLVED for the gather (2026-08-22, `tk-134d7`),
  still open for retirement.** The board existed **twice**, and the
  operator's two surfaces were not the same program:

  | | reached by | implementation | gather |
  |---|---|---|---|
  | terminal | `prefix+b` (`tmux-pick-helm.sh:52` → `gc-helm.sh --json`) | `assets/scripts/gc-helm.sh`, POSIX sh | its own, direct `gc bd list` per rig |
  | web | the dashboard | `services/helm/`, Go + React | the beads library / supervisor API |

  `services/helm/internal/board` is documented as "ported field-for-field
  from `gc-helm.sh`", and that port is a **snapshot, not a link**: nothing
  keeps the two in step and neither reads the other. The divergence is
  not hypothetical. `tk-2v08m` fixed the visits-invisible defect in the Go
  board alone (every file it touched is under `services/helm/`) and closed
  honestly on that scope; the terminal board — the one behind `prefix+b` —
  still had it eleven days later, along with the false-stranded defect,
  and `tk-fkeft` fixed both there. Each fix was correct and each board was
  right about itself; the operator still spent that window reading a board
  that was wrong in a way the other one no longer was.

  **The operator picked the middle future (2026-08-22): share one gather
  behind a seam.** Of the three that were coherent — keep them
  independent, share one gather, retire one — `tk-134d7` implemented the
  second. `services/helm` now builds `helm-svc board`, a terminal renderer
  over the SAME `internal/source` gather and `internal/board` derivation
  the dashboard serves, and the shared model was widened to carry the
  whole of `gc-helm.sh`'s 34-field `--json` contract. Verified equal on
  live data at the time it landed — identical anchor sets, all 34 fields
  equal on all 55 rows — with the evidence and the three chosen
  divergences in `specs/tk-134d7/parity-and-benchmark.md`.

  **What is still open is retirement, and `prefix+b` still runs the
  bash.** `tmux-pick-helm.sh` was deliberately NOT repointed: `gc-helm.sh`
  keeps verbs (`open`, `react`, `takeaway`) that have no Go equivalent, so
  retiring it is a separate piece of work and still the operator's call.
  Until the script is gone there are still two programs, and the tripwire
  stands — but it is now cheaper to honour, because the field sets are
  pinned against each other by
  `services/helm/cmd/helm-svc/contract_parity_test.go`, which fails when
  either side grows or drops a field.

  **The tripwire, as it now reads:** a change to either board's gather,
  ranking, or anchor kinds is still a standing question against the other
  — the parity test compares field SETS, not values, so a derivation that
  changes meaning without changing shape passes it. Say in the PR which
  board you touched and whether the sibling needs the same change.
  `tk-2v08m` did say so, in as many words, which is the only reason
  `tk-fkeft` was findable.

  **Declared divergence: converse sittings, Go board only (2026-08-26,
  `tk-ghlg1e.1`).** The Go board now carries a conversation record beside
  the ranked list — running sittings plus those closed inside
  `GC_HELM_SITTINGS_WINDOW`, each with the `gc.outcome` it closed on — and
  renders it in both `helm-svc board` and the dashboard
  (`services/helm/README.md`, *Converse sittings*). `gc-helm.sh` has no
  counterpart and needs none to stay in parity: the record rides the
  envelope beside `tiles`, so no `Tile` field and no anchor kind changed
  and the field-set test is untouched. What an operator on `prefix+b` does
  not get is the section itself. Building it in bash is a separate
  decision, in the same class as the bash-only verbs above.

## What upstream does not ship (the pack's actual seam)

Revised 2026-08-08 after the build-factory trial and operator probing —
this is the genuinely native ground, and it is deliberately small. A
definition first, because everything below uses it:

> **A visit** is a filed request for one bounded sitting of a subject's
> dialogue, stored as a bead: a small child of the subject whose body
> says what that sitting would be for ("ratify this plan", "review
> posted — decision needed"), whose metadata routes it to the converse
> pool and names the subject's continuation group, whose `gc.outcome`
> records how it resolved, and which closes when it does (the subject
> never closes this way). A visit that is *held* becomes the sitting it
> asked for, and ends out loud, with a sign-off naming the outcome and
> the subject to look at next, because the ending is the one part of a
> sitting the operator cannot reconstruct from the record ("How a held
> sitting ends", above). A visit that is claimed and found not to need a
> human never becomes a sitting at all: it closes silently against its
> subject, because a visit is a request for attention and the loop has
> to be able to answer it with *no* (tk-mndjz). The sequence of visits
> under a subject is the dialogue's durable spine — board-legible,
> cold-reconstructable, no provider transcript required.
>
> **A visit body is written at FILING time and read at CLAIM time**, and
> those are routinely a day or more apart — a queued visit holds its
> place indefinitely at zero session cost, which is a feature of the
> spine and a hazard for any body that states facts. A body whose claims
> can go stale therefore carries `visit.recheck`: the PATH to an
> executable taking the visit's bead id as its only argument, which the
> converse loop runs during prep and whose corrected output supersedes
> the body. Verified 2026-08-14; the measured failure it answers is bead
> tk-gvas6 — a sweep census claimed 41.5 hours after it was cut, by
> which time five of its ten candidates had merged and deployed.

- **The hold on the gate.** Upstream has the *wait* (human gates,
  `blocks` edges — work durably stops). It has no role that services
  the wait: every upstream role's contract is claim → execute → close;
  none claims a bead and deliberately sits `in_progress` for a human,
  having rebuilt the subject's context and framed the choice, then
  records the answer to the subject and closes only the visit. Gate and
  hold are two halves of one mechanism: the gate makes the work wait;
  the hold (the converse role, on a visit) makes the wait worth arriving
  at instead of a parked bead you cold-start yourself.
- **The board's judgment — as a lens, never a dependency.** Ranking
  what deserves the operator's glance, derived from real graph state
  (open visits, human gates, stranded work), with visual consistency.
  **Constraint (operator, 2026-08-08): everything works without the
  board** — work moves entirely on graph state; the board renders it
  and must never be a mechanism anything depends on.
- **Ratification and record-residency for filed trees.** Upstream's
  build factory *does* decompose brief → requirements → plan → tree of
  beads (corrected after the trial; an earlier revision claimed
  otherwise). What it lacks is the gate — no edge can wait on a human
  before the tree lands — and the record-resident plan (files in
  `plans/`, not rev-pinned on the brief bead, so re-planning re-files
  instead of diffing). The native ground is the gate on the tree, not
  the tree-making.

Everything else in the conversation model is assembly of the primitives
above — which is the point.

## Refresh procedure

Claims here date from a source-level verification of 2026-08-06 (gascity
clone `3e629ad`; gascity-packs `0b95742`), cross-checked against the live
public docs on 2026-08-08 (site index: https://docs.gascity.com/llms.txt;
the site publishes no changelog, so recency must be inferred or diffed
against a docs-source clone). Re-verify before building on any
load-bearing claim: upstream moves fast, and the public docs lag the
source — claims marked **source-only** above are real but invisible to a
docs-site check; "not in the docs" is not "false". Ownership follows
[gascity-reference.md](gascity-reference.md)'s refresh procedure and bar;
the doc-keeper drift audit covers this file like any other central doc.
When a watch item fires or a claim goes stale, update the fact *and* the
seam it carries, and date the change.
