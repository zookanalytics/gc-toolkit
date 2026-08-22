---
name: Spec — the gate snippet, the liveness sweep, and triage recurrence
description: Implementation spec for the three pieces that realize P3 and the batched-triage design on common patterns — the canonical gate-turn snippet (marker-delimited, test-extracted), the unnamed-wait sweep (order + v1 formula that normalizes idle beads into turns), and triage-subject recurrence (order + formula filing a turn only when warranted) — plus the city-side adoption list and what stays out of scope.
---

# Spec: gate snippet · liveness sweep · triage recurrence

> **Vocabulary addendum (2026-08-08, post-green-light):** implemented as
> written, then renamed in the same PR by operator decision — "turn" is
> now **visit** throughout the live surfaces: `mol-turn.toml` →
> `mol-visit.toml`, `gate-turn` markers/test → `gate-visit`,
> `task_kind=conversation` → `task_kind=visit`. This spec is kept as the
> green-lit record; read its "turn"/"gate-turn" as "visit"/"gate-visit".

> **Sweep addendum (2026-08-08, operator review):** §2's per-bead
> normalization and epic exclusion are superseded in the implementation:
> normalization is **batched** (one standing "unnamed waits" triage
> subject per rig; one visit per pass listing all candidates — N idle
> beads cost one conversation, not N, per the P3 batching resolution),
> and the epic special-case is replaced by the type-agnostic
> **waiting-on-structure** class (open children or blockers = named
> wait; an epic with all children closed is a first-class unnamed wait
> needing a "what comes next?" exploration). The per-pass filing cap is
> superseded by a per-visit listing cap.

> **Recurrence addendum (2026-08-10, operator decision — visit su-aib6):**
> §3's ripeness pre-check is superseded in the implementation. The machine
> hint alone is not ripeness: the check is the hint **and** a set-delta
> against the candidate set the last filed visit was built from
> (`triage.last_seen` on the subject bead). Motivating case: a
> **park-shaped** subject — one whose scope matches exactly the beads
> parking puts into it, e.g. `label:parked-debt` — never drains, so a
> non-empty-scope test re-asks the same already-answered question every
> cooldown forever; three fired at once on 2026-08-10, each on a set
> unchanged from the day before. The gap §3 left is that ripeness was
> written for a subject triage moves beads OUT of; parks invert it (beads
> move in and stay), and they always carry a hint, so the "else" staleness
> arm never applied to them. The visit body now names which ids entered
> and which left. The delta is symmetric, so §3's "no candidates → no
> turn" holds only for a scope that was ALREADY empty: a subject whose
> recorded set was non-empty and now matches nothing files one final
> visit naming what left, then goes quiet. Deliberately still uncovered:
> a purely strategic change that moves no ids — the operator files that
> visit by hand.

> **Staleness addendum (2026-08-14, bead tk-gvas6):** §2's visit body is
> a SNAPSHOT of the pass, and the sitting reads it whenever the visit is
> claimed. Measured on visit 8 of tk-hok6w (visit tk-3qeq0): the pass cut
> 2026-08-12T00:10Z, the sitting read it ~41.5 hours later, and five of
> the ten new candidates had merged AND deployed in between (#316, #322,
> #325, #328, #332 — the last one the headline P0). 60% of that body was
> wrong on arrival, including all three items it called "worth deciding
> first"; three of the five had closed within two and a half hours of the
> pass. A sitting that TRUSTS such a body routes already-merged work and
> burns a polecat on a no-op, which this scope had already paid for once
> (visit 4 routed tk-yjtf, closed as a no-op 30 minutes later). The
> implementation now re-validates at CLAIM time rather than narrowing the
> window: the pass stamps the census as machine state on the visit
> (`sweep.new_ids`, `sweep.carried_ids`, `sweep.pass_at`) plus a
> `visit.recheck` path, and `assets/scripts/liveness-recheck.sh`
> re-derives every listed id's class from two batched reads (0.34s for
> that pass's 115 ids). The sweep's classification is unchanged. Naming
> the timestamp in the body was considered and rejected — that body
> already named it. Two properties are load-bearing and pinned by
> `assets/scripts/liveness-recheck.test.sh`: the re-check reads BEAD
> state only, so a `merge_result` marker is flagged rather than acted on
> (PR liveness is never re-checked here), and every failure path leaves a
> bead VISIBLE — a re-check that hid a bead on a signal it had not
> verified would be worse than the staleness, since a hidden bead gets no
> next pass. `visit.recheck` is a general visit contract, not sweep
> machinery: any filer whose body can go stale may stamp one.

Realizes P1–P4 ([operating-principles.md](operating-principles.md)) on
existing patterns only. Three repo pieces, one city-side list, one
explicitly deferred design. Vehicle per operator discussion: repo pieces
implement in this PR with their tests; city-side runs live, city idle.

## 1. The canonical gate-turn snippet

**What:** the four turn-filing lines plus the blocking edge — the gate
pattern's whole mechanical content:

```bash
# file a turn on <subject> and gate <blocked-bead> on it
POOL="${GC_RIG:+$GC_RIG/}gc-toolkit.converse"
TURN=$(gc bd create -t task --title "turn: <subject> — <visit>" -d "<visit>" --json | jq -r '.id // .[0].id')
gc bd update "$TURN" --set-metadata "gc.routed_to=$POOL" \
  --set-metadata "gc.continuation_group=<subject>" \
  --set-metadata "task_kind=conversation"
gc bd dep add "$TURN" "<subject>" --type=parent-child
gc bd dep add "$TURN" --blocks "<blocked-bead>"   # omit when nothing waits
```

**How it stays reusable without new machinery:** formula bodies are
plain string substitution (no include mechanism — a known trap), so the
pack's precedent applies: a **marker-delimited canonical copy**
(`# >>> gate-turn` / `# <<< gate-turn`) lives in `formulas/mol-turn.toml`
(the canonical spelling's home), consumers copy it, and a regression test
(`assets/scripts/gate-turn.test.sh`, the host-bead-skip pattern) extracts
the canonical copy, syntax-checks it, and asserts the known consumers'
copies match modulo their substitutions. Consumers at ship: `mol-turn`
itself, `mol-first-reaction` step 3, the sweep (§2), triage recurrence
(§3).

## 2. The liveness sweep (P3 enforcement)

**Home:** its own order + v1 formula (`orders/liveness-sweep.toml` →
`formulas/mol-liveness-sweep.toml`), not a witness-patrol step. Reasons:
the witness owns *session*-liveness (dead assignees); this sweep owns
*graph*-liveness (unnamed waits) — different failure classes, different
cadences (witness each cycle; sweep hourly-to-daily), and an 892-line
patrol should not grow a second mandate. Same fail-safe discipline
copied from witness: an unreadable listing aborts the cycle loudly —
never normalize on partial data.

**The classification (one jq pass over open beads, per rig):** every
open bead must be one of —

1. **worked** — assigned, or `gc.routed_to` non-empty (demand exists);
2. **gated** — an open blocking dependency, an open `type=human` gate,
   or gating-state markers (refinery sub-states count);
3. **conversing** — an open turn in its continuation group, or it *is*
   a turn;
4. **held-by-design** — `task_kind=triage-subject` beads; beads a triage
   scope covers, where *covers* means a real dependency edge onto the
   scope bead, which makes them blocker-blocked and drops them from
   `gc bd ready` (the edge is the whole park — there is no
   membership-by-name; see the amendment below); and beads carrying a
   `gc.takeaway` stamp, which is a human holding the bead awaiting their
   own answer (they wait on their triage conversation, §3);
5. **unnamed** — none of the above: the defect.

**The action:** ONE batch visit per pass on the sweep's standing
"unnamed waits" triage subject, listing the candidates that are NEW
since the previous pass — never one turn per idle bead, and never the
full population. Idempotent (no second visit while one is live, open or
held), so the backlog costs at most one conversation. Every filing
logged to the sweep's own notes.
**Doctor check:** `check-liveness-sweep-wired` asserts the order exists,
enabled, and the formula parses — the sweep watches beads; the doctor
watches the sweep.

**Amendment, 2026-08-10 (operator decision on bead tk-snnpp).** As
first written, class 4 promised more than the sweep could perform and
the report was a census rather than a delta. Three corrections, now
shipped in `formulas/mol-liveness-sweep.toml` and pinned by
`assets/scripts/liveness-sweep-delta.test.sh`:

- **Report the delta, not the population.** "Unnamed" is the resting
  state of any filed-but-not-active bead, so a full report returns
  roughly the whole backlog — measured at 93 of 113 open beads on
  gc-toolkit. A stable set re-listed every pass buries the one bead that
  changed. Each pass now names only what is new since the last one,
  against a baseline (`sweep.reported`) stamped on the standing subject,
  and files nothing when nothing is new. Carried candidates ride along
  as a count and a bare id list so none is hidden.
- **A park is an edge, not a sentence.** The generated visit body no
  longer offers "park into a named scope", which the formula cannot
  perform: a bead parked in prose was a candidate again on the next
  pass. The menu now spells the mechanism — `gc bd dep add <bead>
  <scope>` onto a `task_kind=triage-subject` bead — and says the edge is
  load-bearing, because deleting it, or closing the scope bead,
  un-parks everything silently.
- **A `gc.takeaway` stamp is a named wait.** It marks a bead a human is
  already holding, and it carries no structural edge, so without an
  explicit filter the sweep re-litigated exactly the beads a human
  touched most recently.

Deliberately NOT adopted: scope membership by name (a scope naming its
members via the `triage.scope` token schema, §3). Delta reporting
delivers the benefit at a fraction of the cost; if membership-by-name is
ever wanted, those tokens are where it starts.

**Amendment, 2026-08-11 (operator ruling on bead tk-yyfjv).** Class 2
above was written as "an open blocking dependency, an open `type=human`
gate, or gating-state markers (refinery sub-states count)"; the shipped
formula implemented only the first clause, under the name
*waiting-on-structure*. Both halves now ship, pinned by the same
`liveness-sweep-delta.test.sh`:

- **Class 2 has its gate half back.** A bead whose work is done,
  pushed, codex-green and parked on an OPEN pull request awaiting a
  human approval has no open blocker and no bd-level gate, so
  `gc bd ready` returns it and it classified as *unnamed* — the defect
  class. Measured on signal-loom (sweep of 2026-08-09T23:55Z): six of
  the ten unnamed waits were PR-parked, so 60% of that sitting was one
  condition the classifier could not see, and nothing about those beads
  could change until a human acted. The marker is
  `merge_result=pull_request`, and the marker is explicitly **not** the
  test — the check intersects against the live open PRs, because a
  "carries `merge_result`, skip it" rule would hide REJECTED work
  permanently. **merged** (finishable — surface it for close-out) and
  **closed-unmerged** (rejected — it needs a sitting) both stay
  visible. The read is one `gh pr list` per repository the candidates'
  own beads name, keyed on host + owner/repo + number so a PR number,
  which names nothing on its own, cannot match another repository's.
  Every unreadable case reports rather than hides, and the pass tells
  the sitting when PR liveness was `unverified`.
- **Class 4 gained a fourth shape: `triage.hold`.** A bead the operator
  has deliberately held had no machine-readable marker at all, so
  classify saw it as unnamed and re-surfaced it every pass forever —
  tk-0tln5's hold existed only as the word HELD in its title. The
  value is the REASON for the hold, with `triage.hold_at` /
  `triage.hold_by` recording who and when, and an empty stamp is a
  cleared hold (the same absent-vs-empty tri-state as `gc.takeaway`).
  It is a stamp and **not** a park edge: the park was rejected for this
  scope by the same ruling, because parking is scope membership while a
  hold is a per-bead decision that only the operator reverses, and an
  edge is something a later tidy-up of "stray" edges can silently
  delete. `gc.takeaway` was not reused either — that field is the helm
  surface's "what this bead needs from a human" and is spent as the
  board's NEEDS sentence. The visit menu now offers **hold** alongside
  route / gate / kill / park; offering *park* for a bead the operator
  simply wanted held was itself part of the defect.

Still open in the same classify pass, deliberately not folded in here:
the class-1 convoy discriminator (bead tk-8rm3q — a work bead reads as
unnamed for the whole time its molecule runs, because `mol-polecat-work`
stamps `assignee`/`gc.routed_to` on the molecule, never on the work
bead).

**Amendment, 2026-08-14 (bead tk-7h51d).** The pass is now gated by a
mechanical precheck, so an empty board costs no agent session. As
written above, every pass spent a polecat session — ~4/day/rig, ~16/day
across four rigs — and the common case, an empty board, was the case
that cost the most relative to what it produced. Worse, the price of
concluding "nothing" was O(open beads), so it grew with the backlog.

`orders/liveness-sweep.toml` is therefore a `condition` order whose
check is `assets/scripts/liveness-sweep-precheck.sh`: three batched bead
reads and a jq, ~3s, no session and no network, on the same 6h cadence.
The formula, the bare pool and the rig scope are unchanged, so a pass
that does run is dispatched by exactly the path that dispatched it
before — single-flight open-work gate included. Only the CLOCK moved: a
condition trigger has no `interval`, so the window lives in the script
and is stamped per rig — keyed by `GC_RIG`, because the state directory
it is built from (`GC_PACK_STATE_DIR`) is city+pack scoped while the
order is rig-scoped. Without that key the first rig through the check
would stamp a window shared by every importing rig and silence the rest
for six hours, which is the one failure mode the whole design is
arranged to avoid: a sweep that looks quiet because it never ran.

**Why skipping is provably safe.** The precheck applies a strictly
SMALLER filter than classify. It excludes only on locally-decidable
grounds — assignee, `gc.routed_to`, `task_kind` (visit /
triage-subject), a live visit's continuation group, `gc.takeaway`,
`triage.hold`, and the class-2(i) structural edges to non-closed beads
— and omits the three exclusions that are not local: worked-via-convoy,
the open-PR intersection, and the pre-open gate verdicts. Since its
exclusions are a subset, its survivors are a SUPERSET of the true
candidates, so *zero new locally* implies *zero new really*. The
converse never has to hold: a non-empty local set simply runs the pass.
The PR half is excluded for a second reason on top of locality — that
read is NON-MONOTONE, and the amendment above records why a naive
"carries `merge_result`, skip it" rule hides rejected work.

**Why the failure mode needed explicit handling.** Every check added
since tk-snnpp obeys "a probe that cannot be read excludes nothing". A
programmatic short-circuit INVERTS that: a script that silently returns
empty on a bad jq or a degraded store files nothing and looks perfectly
healthy, and there is no agent left to find the result strange. So the
precheck concludes empty only from positively verified reads — every
read required to exit 0 AND validate as a JSON array, one guarded
assignment as the only path to "skip", and an exit trap that turns any
abort into a run. Both halves of the read check are load-bearing: a
failed call can still print a well-formed array, and `[]` from a dead
store is byte-identical to `[]` from an idle board, so a shape-only
test would read an outage as "nothing to report" (tk-zydg6). Its
`check_timeout` is held above the script's own worst case, because a
condition check killed by that deadline reads as NOT DUE, which is
precisely the silent skip being designed out. It writes no bead: in
particular it never advances `sweep.reported`, so a skipped pass leaves
the baseline exactly as a pass that never ran would.

Pinned by `assets/scripts/liveness-sweep-precheck.test.sh`, whose
containment case runs the precheck's filter and the formula's
`classify-candidates` block — extracted verbatim — over one fixture and
asserts the superset relation, with positive controls so a pass cannot
mean "both sets were empty".

**Doctor check (extended):** `check-liveness-sweep-wired` now also
asserts the precheck is shipped executable, that the order's `check`
names it, that no inert `interval` key has crept back in, and that
`check_timeout` exceeds the script's worst case. That half is guarded
hardest because it fails worst: a broken precheck makes the condition
check fail, a failing condition check reads as not due, and the sweep
retires itself on every rig with every other file still correct.

**Amendment, 2026-08-22 (bead tk-st143).** The sweep was nominating work
that did not exist and filing conversations another conversation was
already having. Three corrections, shipped in
`formulas/mol-liveness-sweep.toml` and pinned by the same
`liveness-sweep-delta.test.sh`.

- **A landed workflow's step beads are teardown, not waits (class 0(b)).**
  `mol-polecat-work` runs its steps inline and closes none of them, ever,
  so when its anchor lands the whole step chain stays open, stays ready,
  and arrives as unnamed waits on every subsequent pass. The classifier
  read each step's own edges and never asked whether the workflow it
  belongs to had finished. Measured on shutupandlisten 2026-08-13:
  sixteen step beads across two dead roots (su-zu1j, anchor su-uzy9.4, PR
  #57 merged; su-vc8n, anchor su-uzy9.5, PR #58 merged), every one of them
  nominated, none of them work anybody could do — routing such a bead
  re-implements landed work on a branch whose PR already merged. The new
  `landed-husks` block resolves root → input convoy → anchor once per
  ROOT and drops every step of a landed root at once. **Landed is
  `status=closed` OR `merge_result=merged` and deliberately only that
  pair**, because every other terminal-looking marker is a state a live
  molecule wears mid-flight — `pull_request` is what a rework anchor
  carries from the round being reworked. The sibling implementation of
  this same test in `assets/scripts/detect-stalled-workflows.sh` learned
  that the expensive way, and this one inherits its rule and its reason.
  Like the machine convoys of class 0(a) these owe a reaper rather than a
  sitting, so the pass excludes them and stamps the root ids as
  `sweep.husk_roots` — exclusion first, the reaper follows.

- **Visits dedupe by `gc.root_bead_id`, not only by continuation group
  (class 3).** A root-scoped stall visit
  (`detect-stalled-workflows.sh`, stamping `stall_root`) hangs off the
  stalled-workflows subject and this sweep's batch visit off the
  unnamed-waits subject, so the sibling dedupe keyed on
  `gc.continuation_group` could never fold them: both filed about one
  frozen workflow, and on 2026-08-13 the operator was holding three
  concurrent sittings on a single shape. A candidate whose root a live
  visit already names is now class 3. **The precedence is deliberate and
  one-directional**: the root-scoped visit is a diagnosis of one workflow
  and this sweep's contribution is one line of a batch census, so the
  census folds into the diagnosis and never the reverse — which is why
  `detect-stalled-workflows.sh` still does not read this sweep's visits.

- **An agenda a sitting already dispositioned is not re-filed.** The
  step-3 skip deliberately does not advance `sweep.reported`, and a
  baseline can be lost or reset, so the same NEW set can come round again
  after a sitting has worked it — su-qoma was a verbatim re-file of
  su-7j8b, closed two days earlier with `gc.outcome=dispositioned`. The
  guard compares the id SET rather than the title, which is a pair of
  counts that collide by accident, and fires only on
  `gc.outcome=dispositioned`: a visit closed `cut-short` ran out of time
  with its agenda un-worked and re-filing it is correct. Suppression
  advances the baseline, which is what makes the guard terminate rather
  than fire forever. Because that pairing is the one path here that
  retires an agenda without anyone seeing it, suppression rests on a read
  that actually SUCCEEDED: the closed-visit listing's exit status is
  captured apart from its output, and a non-zero read is unreadable
  whatever it printed. A failure that emits a partial page emits valid
  JSON, so shape alone cannot tell the two apart.

One consequence is accepted rather than fixed. A landed husk is not
locally decidable, so the precheck of the amendment above cannot exclude
it and must not try — excluding more than classify does is the direction
that breaks the superset guarantee. Husks therefore never enter
`sweep.reported`, never close on their own, and keep the precheck reading
them as new: a pass runs every cadence and files nothing. That trades one
operator sitting on work that does not exist for one session that
produces no visit, which is the better trade but is residue, not a cure.
The reaper that `sweep.husk_roots` feeds is what ends it. Measured on
gc-toolkit 2026-08-22: 16 of the 21 root-bearing ready candidates were
husks — including one whose anchor was closed with no `merge_result` at
all, and, as the negative control, one live anchor carrying
`merge_result=pull_request` that the rule correctly left visible.

All three keep the report-don't-hide bias every other check here obeys:
a failed root, convoy or anchor read contributes no husk and leaves the
bead visible (with `sweep.husk_liveness=unverified` disclosed in the
body), and an unreadable closed-visit listing files rather than
suppresses.

## 3. Triage recurrence

**The subject:** an ordinary bead, `task_kind=triage-subject`, body =
the scope in prose (authoritative, evaluated by the converse session at
turn time) plus one optional machine hint `triage.scope=<bd-ready
filter args>` for the cheap pre-check. Created in the city, not the
repo; near-disjoint scopes by operator convention.

**Recurrence:** `orders/triage-recurrence.toml` (daily cooldown,
per-rig) → `formulas/mol-triage-recurrence.toml` (v1, one step): for
each `task_kind=triage-subject` bead — skip if an open turn already
exists in its group; else run the cheap ripeness pre-check (the machine
hint if present, else "any held bead untouched since the last triage
turn closed"); if ripe, file the gate-turn ("triage visit: N candidates
look ripe — promote, park, or kill"). No candidates → no turn → no
board row: pull-only holds. *(Superseded — see the Recurrence addendum
above: the pre-check is the hint AND a set-delta against the last filed
visit, because a hint-only test nags park-shaped subjects forever.)* The
deep evaluation (which five, what
ranking) is the converse session's prep at turn time — the scope is the
lens, the chassis does the work.

## 4. City-side (live, city idle — the whole list)

1. Point the rig at this branch; `gc doctor` clean.
2. Spine smoke (spine-port.md's four raw lines): converse spawns,
   self-titles, holds → Phase 0/1 evidence.
3. Create 1–2 triage subjects (e.g. "triage: held ideas, gc-toolkit").
4. Enable both orders; watch one sweep cycle and one recurrence
   evaluation; react to what they file.
5. Optionally enable the P2 intake default (`GC_PROACTIVE_ENABLED=1`)
   now that first-reaction files turns.

Each step is one command plus observation; I write the exact runbook
when the repo pieces are merged-ready.

## Out of scope, deliberately

- **The build-factory ratification graft** — wrapping/patching another
  pack's v2 formula is its own design spike (wrap vs. fork vs. an
  upstream PR adding a gate hook to build-base; the third may be the
  right ecosystem move). Separate increment.
- **Board rendering of turns/gates as anchor kinds** — the board works
  without any of this (operator constraint); its turn-awareness is a
  later, additive change.
- **Retiring bead-host config** — orthogonal cleanup, its own small PR.
