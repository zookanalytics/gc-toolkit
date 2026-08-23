Formula: mol-witness-patrol
Description: Witness patrol loop. Poured as a root-only wisp on startup:

  gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='{{binding_prefix}}' --var event_timeout='{{event_timeout}}' --var escalation_cooldown='{{escalation_cooldown}}'
  gc bd update $WISP --assignee=$GC_AGENT

Pass EVERY declared var on that pour, not just binding_prefix. `--root-only`
materializes no defaults, so a var the pour omits reaches the wisp
unrendered and the cycle runs on whatever fallback its consumer happens to
have. The startup and crash-recovery pours live in the witness agent
template (`template-fragments/layered-startup-discovery.template.md`,
markers `patrol-wisp-vars` / `patrol-wisp-fallback`), which reads the
defaults back out of this file via `gc formula show --json` rather than
retyping them; `next-iteration` forwards them for every cycle after the
first.

Those are TWO writes, and the gap between them is load-bearing: a wisp
poured but not assigned belongs to nobody, so it never reaches a hook and
no assignee-scoped query can ever find it again. Guard the assign wherever
you pour (see `next-iteration`), and reconcile by TITLE rather than by
assignee so an orphan from an interrupted pour is still collectable
(tk-fj56a).

A `--root-only` pour materializes no formula defaults, so this bootstrap is
where any NON-DEFAULT var (`event_timeout`, `escalation_cooldown`) has to be
set — add it as another `--var` here. From then on `next-iteration` forwards
every declared var to the wisp it pours, which is what keeps the setting
alive past the first cycle.

Each wisp is ONE iteration: check for work, patrol, pour the next
iteration. On crash, re-read the formula steps and determine where
you left off from context (bead state, mail state, last action).

Formula steps are NOT materialized as child beads. Work through them in
order, reading each step's description as you reach it — one step at a
time, not the whole formula up front.

The loop mechanism: EVERY step is one leg of the same wisp. Never exit
the wisp from an intermediate step — either continue to the next step
or jump directly to `next-iteration` to pour and burn. Exiting without
burning leaks wisps (see #1884). The prompt only bootstraps the first
wisp.

## Witness Role

The witness is the rig's work-health monitor. It does NOT manage processes
(the controller handles start/stop/restart/zombie detection). The witness
monitors the WORK layer:

1. **Orphaned bead recovery** — beads assigned to agents that won't spawn
   (pool max changed, agent removed from config). This is the core job.
2. **Refinery queue health** — work beads assigned to refinery, staleness.
3. **Polecat health** — detect stuck polecats, file warrants for dog pool.
4. **Help mail** — triage HELP/escalation requests from polecats.
5. **Completed-workflow quiesce** — retire the dead step beads of finished
   mol-polecat-work molecules so the pool stops re-offering them (tk-p9ji9).

Gate checks and convoy/swarm completion are town-wide concerns handled by
the deacon, not the per-rig witness.

## Canonical Work Chain

```
worktree → (push) → branch → (merge) → target branch
```

Each transition moves the canonical location of the work. Once moved,
the previous location is disposable:
- After push: worktree disposable (branch is canonical)
- After merge: branch disposable (target is canonical)

The witness's core recovery job: when a bead is orphaned (agent won't
come back), ensure the work reaches the branch (push), then clean up
the worktree. This makes the work schedulable again.

## What the witness does NOT do

- Zombie detection (controller reconcile loop handles this)
- Process start/stop (controller handles this)
- Code implementation (polecats do this)
- Gate checks (deacon handles town-wide)
- Convoy/swarm completion (deacon handles cross-rig)
- Kill stuck agents directly (files warrant, dog pool runs shutdown dance)

## Escalation discipline — read this before ANY `gc mail send`

This applies to every step, not just the one that documents an escalation
command.

You re-derive your triggers from live state each cycle, so a condition
that was true last cycle is usually still true now. Mailing on each is
how ONE stuck PR produced FIVE witness escalations in 2h53m (2026-07-27,
PR #35 / anchor su-lou.10.8; the su refinery added two more). The cost is
not the volume: repeated escalations train the recipient to ignore
escalation mail, which is the one signal that is supposed to be rare, and
each `gc mail send` is a permanent bead plus a Dolt commit for as long as
the item stays stuck.

**Any escalation that is ABOUT A BEAD goes through the gate instead of
straight to `gc mail send`:**

```bash
# >>> escalation-wiring-discipline
SCRIPTS_DIR=""
for cand in "${GC_RIG_ROOT:-}/assets/scripts" "$(git rev-parse --show-toplevel 2>/dev/null)/assets/scripts" "${GC_CITY_PATH:-}/rigs/gc-toolkit/assets/scripts"; do
  if [ -x "$cand/escalation-gate.sh" ]; then SCRIPTS_DIR="$cand"; break; fi
done
BODY="Observation: <what you found>
Recommendation: <what should happen>"
if [ -n "$SCRIPTS_DIR" ]; then
  if ! "$SCRIPTS_DIR/escalation-gate.sh" --anchor "<bead-id>" --state "<what is HOLDING it>" --cooldown "{{escalation_cooldown}}" --subject "<subject>" --body "$BODY"; then
    echo "witness: escalation-gate did not send (see its stderr); NOT falling back to a bare mail. Next cycle retries." >&2
  fi
else
  gc mail send mayor/ -s "<subject>" -m "$BODY" || echo "witness: fallback 'gc mail send' failed; next cycle retries." >&2
fi
# <<< escalation-wiring-discipline
```

It mails the first time, then stays quiet until `--state` changes or the
cooldown elapses. It suppresses REPETITION, never news — with one class it
declines outright rather than deduping: a PR that is mergeable, green on
every check that gates its merge, and merely unapproved is a resting state, and the correct number of escalations
about it is zero, not one (tk-qe2tv). That only applies where the block
names the PR through `--pr`, which the queue-health step does and no
one-shot notice does. A rig that has not synced the script falls back to
mailing directly — the old behavior, not a dropped escalation.

Keep the resolution loop in the SAME shell as the send. Each tool call is
a fresh shell, so a `SCRIPTS_DIR` you resolved earlier is gone, and an
empty one expands to `/escalation-gate.sh` — which fails and sends
nothing. Only the gc-toolkit rig has its own `assets/scripts`; the other
three resolve through the `GC_CITY_PATH` candidate.

A non-zero exit from the gate is NOT fatal and NOT a licence to mail
anyway. A NON-ZERO exit means one thing only — it could not bound the
escalation (unreadable anchor, unwritable stamp) — and mailing past that
is the unbounded storm. Log it, keep patrolling, let the next cycle
retry. That is why the call above is wrapped in `if ! ...; then echo`
rather than run bare: this is a best-effort pass and must reach its
later checks.

**"Next cycle retries" is only true while the TRIGGER survives the pass.**
The gate is re-invoked next cycle because the patrol re-derives the same
condition — a stuck PR is still stuck, a queue is still backed up. That
holds for every RE-DERIVED escalation (`QUEUE_HEALTH`, the example above).
It does NOT hold for a ONE-SHOT recovery notice, where the same pass then
performs the state transition that clears the condition: close the orphan,
or return it to the pool, and nothing re-detects it, so a refused send is
lost for good rather than retried. When you write a new gated block, ask
which kind it is:

- **The transition is yours to withhold** — do that. `ORPHAN_CLOSED` gates
  its `gc bd close` on the notice getting out, so a refusal leaves the
  bead open and the next cycle genuinely retries both.
- **The transition must happen regardless** (recovery is load-bearing and
  the mail is advisory) — then say BEST-EFFORT, and do not print a retry
  promise the code cannot keep. `SALVAGE_REFUSED` and `ORPHAN_RECOVERED`
  are this kind: blocking a husk's recovery on a mail failure would strand
  real work to protect a message.

A refusal message that promises a retry which cannot happen is worse than
one that admits the loss — it reads as handled in the patrol log.

Things that are easy to get wrong:

- **Do not reword your way past it.** Those five PR #35 mails had five
  different subjects — "stranded on human approval", "Codex-green but
  stranded", "fully gate-green", "approval-gated ~88h", "stranded 3d".
  One situation, five framings, because you compose the subject fresh
  each cycle from whatever you just observed. The gate keys on the ANCHOR
  and the channel, never on the message, exactly so rephrasing cannot
  reopen the storm. Reaching for `gc mail send` directly because "this
  framing is new" IS the bug.
- **Put the real hold inputs in `--state`.** Head oid, `reviewDecision`,
  `mergeStateStatus` — whatever would make you say "this is genuinely
  different now". That fingerprint is what lets real news through
  immediately, so a lazy `--state` is what turns the gate into a mute.
- **Sanitize any `gc bd show --json` you build `--state` from:**
  `gc bd show <bead> --json 2>/dev/null | tr -d '[:cntrl:]'`. jq rejects
  every unescaped control character — including a plain tab, which prose
  notes do contain — and a failed parse leaves `--state` EMPTY, which the
  gate reads as "no state tracked" and suppresses real news for a whole
  cooldown. A lost parse must not look like a lost fingerprint.
- **Never pass an EMPTY `--state` when you meant to track state, and never
  substitute a differently-shaped one on the same `--kind`.** Both are the
  same mistake at different depths. Empty is a real fingerprint meaning
  "no state tracked", so it gets stamped durably and the cooldown alone
  governs from then on. A substitute (the bead's fields standing in for a
  PR's, because `gh pr view` failed) compares unequal in BOTH directions,
  so the item mails when the outage starts and again when it ends — a flap
  through the cooldown, driven by an outage rather than by news. When the
  fingerprint you meant to build is unavailable, send that observation on
  its own channel — `--kind witness-degraded`, with a value naming what is
  unavailable and nothing that varies while it is — and leave the real
  channel's stamp alone. Step `check-refinery` does this; copy that shape.
- **Never put a timestamp in `--state` — least of all the anchor's own
  `updated_at`.** The gate stamps `escalated.<kind>` ON THE ANCHOR before
  it mails, and that write bumps the anchor's `updated_at`. A fingerprint
  containing it therefore differs on the very next cycle *because the gate
  ran*, so an unchanged item re-mails forever: the storm, now with a
  dedup step in front of it. Fingerprint only inputs the gate does not
  itself write — `status`, `merge_result`, `branch`, the landing target
  (`merged_target // target`, the pre-open order), the `check.<gate>`
  markers, the PR's own fields.

`--cooldown "{{escalation_cooldown}}"` is passed on every gated call, and
`next-iteration` forwards the var to the wisp it pours — both halves are
needed for a configured value to be honored end to end. The call alone
only honors it for one cycle: a `--root-only` pour materializes no
defaults, so a value the pour drops arrives unrendered at the next wisp
and every later cycle silently runs the script's own 24h default instead.
Where the var was never set at all it still arrives unrendered, and the
script recognizes that shape and falls back to that default rather than
failing the send.

`--force` is for a situation that truly worsened in a way the fingerprint
does not capture. Using it every cycle is the storm again.

Suppressed escalations still print a verdict line — the item is still
stuck, and your log still says so.

**The rule is enforced, not merely documented.**
`witness-escalation-wiring.test.sh` scans this file for every
`gc mail send` and fails on any that is neither inside a gated
`escalation-wiring-*` block nor on this exception list. Exactly two are
exempt, both because there is no bead to key a stamp on:

- the `check-inbox` forward of a polecat HELP mail — it is about an
  AGENT, not a bead, and the message that triggers it is archived once
  handled, so it cannot re-fire every cycle the way a live condition
  does;
- the `recover-orphaned-beads` empty-liveness-map fail-safe — rig-global,
  no anchor exists at all.

Every other escalation in this formula (`SALVAGE_REFUSED`,
`ORPHAN_CLOSED`, `ORPHAN_RECOVERED`, `QUEUE_HEALTH`) is bead-scoped and
gated. Adding a third bare bead-scoped mail fails that test — gate it
instead, or the storm comes back through the new one.

Regression test: `assets/scripts/escalation-gate.test.sh` (hermetic; stubs
`gc`, covers the five-subject drift case, state-change and cooldown
re-opening, stamp-before-mail, and the refuse-to-send-when-unbounded rule).

The WIRING above is covered too, by
`assets/scripts/witness-escalation-wiring.test.sh`: it runs the block
between the `escalation-wiring-*` markers verbatim against stubs, so
dropping `--anchor`/`--state`, hoisting the `SCRIPTS_DIR` resolution out
of the sending shell, or swapping the gated call back to a bare
`gc mail send` fails a test rather than quietly reopening the storm.
Keep the markers when editing these blocks.

Read a step's description immediately before acting on that step — not
all of them at once. Config values override defaults.

Variables:
  {{binding_prefix}}: Import binding prefix for gastown agent identities, including trailing dot when bound. (default=)
  {{escalation_cooldown}}: Seconds before an UNCHANGED situation may be escalated again (see 'Escalation discipline'). A CHANGED state fingerprint always re-escalates immediately, so this bounds repetition only, never news. Default 24h: at the 600s patrol interval that is a 144x reduction on a stuck item, while still resurfacing it daily so it cannot fall silent. Lower it only if a real escalation was noticed too late — not to make the patrol chattier. (default=86400)
  {{event_timeout}}: Seconds to wait before re-checking. Replaces former event-watch loop which hot-spun on cache-reconcile firehose. Spend it with a bounded until-loop, not a standalone sleep (the harness blocks that, which drops all pacing). This value sets patrol frequency, which is the dominant cost term once a cycle is cheap — raise it rather than trimming steps if patrol cost needs to come down. Raised 180 -> 600 (tk-2qa85): the four witnesses were 56.9% of all city model calls over 24h (19,905 of 34,983), and sampled cycles ran ~285-521 s of which only the 180 s wait was compressible, so frequency was the only term that could move without dropping a check. 600 is a CEILING, not a preference: the wait is one bounded tool call and the harness caps a single call at 600 s (a longer one is SIGTERMed mid-wait and silently returns less pacing than configured), so a larger value here would not be honoured without also making the wait resumable across calls. This value reaches the loop ONLY through the startup pour, which reads it from this default via `gc formula show` and forwards it as an explicit --var; city.toml [rigs].formula_vars cannot override it, because mergeRigFormulaVars preserves an explicit --var. (default=600)

Steps (9):
  ├── mol-witness-patrol.check-inbox: Check mail
  ├── mol-witness-patrol.recover-orphaned-beads: Recover orphaned work beads [needs: mol-witness-patrol.check-inbox]
  ├── mol-witness-patrol.recover-stranded-branches: Recover published work with no landing path [needs: mol-witness-patrol.recover-orphaned-beads]
  ├── mol-witness-patrol.check-refinery: Check refinery queue health [needs: mol-witness-patrol.recover-stranded-branches]
  ├── mol-witness-patrol.quiesce-completed-workflows: Quiesce completed workflows [needs: mol-witness-patrol.check-refinery]
  ├── mol-witness-patrol.detect-stalled-workflows: Signal workflows that stopped advancing [needs: mol-witness-patrol.quiesce-completed-workflows]
  ├── mol-witness-patrol.detect-parked-dispositions: Bring a parked conversation back when its routed work lands [needs: mol-witness-patrol.detect-stalled-workflows]
  ├── mol-witness-patrol.check-polecat-health: Check polecat work progress [needs: mol-witness-patrol.detect-parked-dispositions]
  └── mol-witness-patrol.next-iteration: Pour next iteration and loop [needs: mol-witness-patrol.check-polecat-health]
