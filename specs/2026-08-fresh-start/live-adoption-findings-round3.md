---
name: Findings round 3 — delta smoke of the operator-review commits (2026-08-09)
description: Narrow delta report against a3d5003, covering only what changed since 2d6c12a — the rewritten converse contract, the triage file-a-visit path (exercised live for the first time), and the converse pool 2→6. The converse close sequence passes end to end; the triage path files correctly once, then stacks a second visit on the next run; the `unrouted` scope token is unimplementable as written.
---

# Findings round 3 — delta smoke

**Branch:** `claude/gc-toolkit-fresh-start-ehvljb` @ `a3d5003`
(was `2d6c12a` in round 2; four new commits `8d4361f`, `579eb35`, `5d8b65b`,
`a3d5003` — 44 files, +744 / −329)
**City:** `/Users/zook/Code/gc-next`, rig `gc-toolkit` (tk)
**Host:** darwin 25.6.0, `gc version` = `edge`
**Run:** 2026-08-09 04:50–05:35Z. Branch pulled in the rig checkout, `gc reload`
("No config changes detected" — the local-path import is read live, so the pack
is already current at reload time), then `gc restart` to force fresh sessions
onto the new prompt.

This is a **delta smoke, not a runbook pass**. Only the three areas that changed
since `2d6c12a` were exercised. Read against `live-adoption-findings-round2.md`.

**Headline:** the rewritten converse contract does exactly what it says — the
new stamp → verify → close sequence ran verbatim, the hold format is correct,
and only the visit closed. The triage file-a-visit path, exercised live for the
first time on this branch, works on the first run and **breaks on the second**:
it stacks a second visit on a subject whose visit is being held (R3-05). Its
`unrouted` scope token matches zero beads as written and both executing agents
silently invented a normalization to get past it (R3-06).

---

## What I did not test this round

- Cold continuity, the liveness sweep, `gc doctor`, and the proactive intake
  default. Out of the delta and explicitly out of scope for this pass.
- The `skipped-no-candidates` outcome. The only machine-scoped subject in the
  store had 148–149 candidates on both runs; an empty scope was never produced.
- Whether R3-02 (converse drained mid-prep) reproduces on an idle city. This
  city was not quiesced — the mayor, deacon, refinery, witness and an unrelated
  polecat were all live and competing for session slots.

---

## 1. Rewritten converse contract

### R3-01 — The full loop, claim through close. **PASS, end to end**

Filed `tk-tyf7n` on `tk-22byl` (a healthy open P1, unblocked, un-arrested)
using the runbook's raw step-1 lines verbatim, pool hard-coded rig-qualified.

Every clause of the rewritten prompt held:

| prompt clause | observed |
|---|---|
| step 1 claim + concurrent-hold check | claimed via `gc hook --claim`; ran the `--status=in_progress` sibling query, reported "Only my own visit — no fold needed" |
| step 2 self-title | session renamed itself to `tk-22byl — spine smoke r3` |
| step 3 prime | rebuilt subject state from `gc bd show` + the mayor's consolidation comment, then re-ran `gc lint` on three trees to test the bead's own claim |
| step 4 hold | final line exactly `Next (yours): tell me whether to launch mol-scoped-work on both halves together, on one half only, or to first re-lint pristine main…` — **nothing below it** |
| operator turn | `gc session submit gn-hhfj "…"`; the session executed the decision rather than just recording it |
| step 5 record | appended to the subject; notes 2 995 → 5 521 chars |
| step 6 stamp/verify/close | ran verbatim, in order (below) |
| "only the visit" | `tk-tyf7n` → `closed`, `gc.outcome=baselined`; `tk-22byl` still `open` |

The close sequence as actually executed by the session:

```
gc bd update tk-tyf7n --set-metadata "gc.outcome=baselined"
gc bd show tk-tyf7n --json | jq -e -r '.[0].metadata["gc.outcome"] // empty' && echo "STAMP VERIFIED"
gc bd close tk-tyf7n
```

Closure audit for the window (`closed_at > 04:50Z`): `tk-tyf7n` plus the triage
wisp/step/finalize triple and one witness recovery bead. **No subject was
closed, and the converse session closed nothing but its own visit.**

Bonus confirmation of the F-10 drain nuance: after closing `tk-tyf7n` the same
session immediately claimed a *different* group's visit (`tk-ze0z2`) and
re-titled, rather than draining.

### R3-02 — Converse sessions are drained mid-prep as "orphaned". **DEVIATION (new, serious — runtime, not pack)**

Two of two gc-toolkit converse sessions were killed by the reconciler within
~4 minutes of starting, each while holding an `in_progress` visit and each
several minutes into real prep:

```
Draining session 'gc-toolkit__converse-gn-43e8': orphaned
Draining session 'gc-toolkit__converse-gn-zuxh': orphaned
```

`gn-43e8` lost ~5 minutes of prep on `tk-tyf7n`. Recovery is then not prompt,
because the reconciler tries to *reassign* rather than *reclaim*:

```
releaseOrphanedPoolAssignments: releasing orphaned pool assignment tk-tyf7n:
  cannot reassign tk-tyf7n: held by "gc-toolkit/gc-toolkit.converse-1" (in_progress);
  … pass --force only if their claim is abandoned (crashed agent, expired lease), or use bd reclaim
```

It retried and failed on the same guard every cycle. Meanwhile the pool sees no
*unassigned* demand for that visit, so it spawns nobody to pick it up. The visit
sat wedged for ~14 minutes. `gc bd reclaim --id tk-tyf7n --older-than 0s`
released it instantly — **the lease was already expired**, so the reclaim path
would have worked all along and the reassign path was the wrong tool.

The other stranded visit *was* recovered automatically, by the witness, ~4
minutes in (bead `tk-zp2f5`: `witness: recovered orphaned visit tk-ze0z2 (dead
session…)`). So a recovery path exists; it is just not the one the reconciler
reaches for first, and its latency is not bounded by anything the operator can
see.

This bears directly on the new `agents/converse/agent.toml` comment:

> Open visits outlive sessions either way — a dead session's visit returns to
> the pool and a fresh session resumes it from the record.

True *eventually*. Not true promptly, and not true via the mechanism the
reconciler logs. A held session diagnosed the root cause unprompted, in its own
hold text: **"`gc bd heartbeat` is a no-op on the lease fields."**

### R3-03 — Two minor observations

- One session did step 5 (record to subject) *before* step 4 (hold), announcing
  "the prep turned up something the bead got wrong. Recording the diagnosis to
  the subject before I hold." Harmless — arguably better — but the prompt's step
  order is advisory, not enforced.
- The witness's recovery of `tk-ze0z2` **stripped `gc.continuation_group`**. The
  next session to claim it saw an empty group and had to fall back to parsing
  the subject id out of the title. Anything that reads continuation groups will
  mis-file a recovered visit.

---

## 2. Triage file-a-visit path (never before exercised on this branch)

Setup: created `tk-wyrf8` — `task_kind=triage-subject`,
`triage.scope=unrouted` — with 148 open unrouted beads in scope. Two existing
triage subjects served as controls: `tk-so3um` (prose only, no
`triage.scope`) and `tk-uorin` (the sweep's standing subject,
`triage.scope=unnamed-waits`). Forced with
`gc order run triage-recurrence --rig gc-toolkit`, twice.

### R3-04 — First run: files exactly one visit, logs every subject. **PASS**

`tk-2x7xr` filed for `tk-wyrf8` and nothing else. Metadata correct and complete:

```
gc.routed_to        gc-toolkit/gc-toolkit.converse   ← rig-qualified (F-05 holds in formula context)
gc.continuation_group  tk-wyrf8
task_kind           visit
```

plus the `tracks` edge to the subject. Step bead closed `gc.outcome=pass`.

Per-subject outcomes were logged to the step bead, and across the two runs all
four documented outcome kinds were exercised:

- `filed` — `tk-wyrf8`, with candidate count and priority histogram in the visit body
- `skipped-open-visit` — `tk-uorin`, run 1 (its visit `tk-ze0z2` was `open` at that moment)
- **`skipped-no-machine-scope` — `tk-so3um`, both runs.** The prose-only subject
  was logged and **never guessed at**: *"triage.scope is empty; no tokens to
  apply, scope prose left for the sitting."* This is the clause working exactly
  as specified.
- `unknown-scope-token` → `skipped-no-machine-scope` — `tk-uorin`, run 2:
  *"`unnamed-waits` is not in the token table, and it is the only token."*

Worth flagging on its own: **the liveness sweep's own standing subject carries a
`triage.scope` value the recurrence formula's schema does not define.** Two
formulas share one metadata key with disjoint vocabularies. Harmless today
(the sweep files that subject's visits itself) but it guarantees a permanent
`unknown-scope-token` line in every recurrence log.

### R3-05 — Second run does not skip; it stacks a second visit. **DEVIATION (serious)**

Step 1 builds the open-visit set from:

```bash
gc bd list --status=open --json --limit=0 > "$OPEN"
CONVGROUPS=$(jq '[.[] | select((.metadata.task_kind // "") == "visit") | …]' "$OPEN")
```

A visit that is **being held** is `in_progress`, not `open`. It is therefore
invisible to `CONVGROUPS`, and the "Skip if a visit is open" branch never fires.

Observed exactly that. By run 2, `tk-2x7xr` had been claimed by a converse
session. The step logged:

> Open visits before this run: 0, so no subject was skipped for an open visit.

and filed `tk-8s15e` on the same subject. Final state:

```
tk-8s15e  open         grp=tk-wyrf8
tk-2x7xr  in_progress  grp=tk-wyrf8
```

Two visits stacked on one subject. The formula's stated invariant — *"Never
stack a second visit on one subject"* — fails **precisely in the case it exists
to prevent**: a sitting already live. The skip only works during the window
between filing and claiming.

Note the first run's polecat avoided this by going beyond the step text on its
own initiative ("checked all statuses, not just open"). The second run followed
the step text as written and stacked. The step text is the defect.

### R3-06 — The `unrouted` scope token matches nothing as specified. **DEVIATION (serious)**

The token schema in `mol-triage-recurrence.toml` step 2 defines:

| token | meaning |
|---|---|
| `unrouted` | `.metadata["gc.routed_to"] == ""` and `.assignee == ""` |

Read literally this matches **zero beads**. Against the live store:

- `.assignee` is JSON `null` on 300 of 301 open beads, never `""`
- 114 of the 149 candidates have **no `gc.routed_to` key at all**, so the lookup
  is `null`, not `""`

Both polecats found this independently and both reported it in the same terms —
run 1: *"the literal reading is structurally dead (assignee is null on all 148,
never `""`)"*; run 2: *"strict `== ""` is structurally dead (assignee is null on
300/301 beads)… as written the token is dead and `tk-wyrf8` would log
`skipped-no-candidates` on every recurrence forever."*

Both then **silently normalized** with `(x // "") == ""` to proceed. That is a
guess — the same class of guess the formula forbids two paragraphs earlier for
unrecognized tokens ("never guessed at"). Two agents happened to converge on the
same normalization; nothing in the formula makes that guaranteed. The other
three tokens (`p<=N`, `label:X`, `kind:X`) were never exercised, so whether they
carry the same literalism is untested.

### R3-07 — The step's self-close idiom is a silent no-op. **DEVIATION**

```bash
[ -n "${GC_BEAD_ID:-}" ] && gc bd update "$GC_BEAD_ID" --set-metadata gc.outcome=pass --status=closed
```

`GC_BEAD_ID` is unset in the polecat session, so the guard short-circuits and
the step closes nothing — while reporting success. The run-2 agent caught it and
closed by explicit bead id instead, noting this is *"live corroboration of open
P1s `tk-uqs2` (pack self-close idiom references `$GC_BEAD_ID`, which no agent
session ever sets, 8 sites) and `tk-xcbs` (10 more sites)"*. This makes
`mol-triage-recurrence.evaluate-and-file` another site carrying the known
defect — it is not new, but this branch adds a copy of it.

### R3-08 — Both agents wrongly blamed `gc bd create --title`. **FALSE POSITIVE, but it changed behaviour**

Run 1's polecat hit a one-off id-extraction failure on the marked
`# >>> gate-visit` block and recovered by looking the bead up by title. Run 2's
polecat pre-emptively concluded:

> There is no `--title` flag — title is positional (`bd create [title]`), so
> that form yields an empty id with no error…

**That is wrong.** Verified directly:

```
$ gc bd create --help | grep -- --title
      --title string    Issue title (alternative to positional argument)

$ id=$(gc bd create -t task --title "PROBE r3 real create" -d "…" --json 2>/dev/null | jq -r '.id // .[0].id')
$ echo "$id"          → tk-jjr6q      (title set correctly)
```

My own operator-shell run of the identical block produced `tk-tyf7n` with the
right title and a clean id. Stdout from `--json` is clean; the `named_session`
warnings go to **stderr** and never enter the pipe.

Reporting it because the false diagnosis had a real effect: **both executing
agents deviated from the marked, fixture-checked block** — one used `--body-file`
plus the positional form. `assets/scripts/gate-visit.test.sh` passes (34/0), so
the fixture cannot see this drift. If the block is going to be copied verbatim
by consumers, its one fragile line (`--json | jq -r '.id // .[0].id'` with no
retry and no error check) is what invites agents to rewrite it.

---

## 3. Pool 2 → 6

### R3-09 — `max_active_sessions = 6` after reload, and nothing else about spawning changed. **PASS**

Config, both rigs, post-reload:

```
name = "converse" / dir = "gc-toolkit"
max_active_sessions = 6
min_active_sessions = 0
idle_timeout = "8h"
wake_mode = "fresh"
```

Not just config — **exercised at runtime**. Three concurrent slots were used
(`converse-1`, `converse-2`, `converse-3`) and the reconciler logged
`poolDesired: gc-toolkit/gc-toolkit.converse = 3`, which was impossible under
the old cap of 2.

`git diff 2d6c12a a3d5003 -- agents/converse/agent.toml` is **only** the
`2 → 6` change plus comment and nudge rewording. `scope`, `wake_mode`,
`work_dir`, `idle_timeout`, `min_active_sessions` are byte-identical; there is
still **no `work_query` and no `scale_check`** on converse, so demand remains
the default routed-pool predicate. Nothing else about spawning changed.

---

## Environment findings (out of delta, noted not chased)

### R3-10 — Startup nudges are delivered but not submitted

Recurring throughout:

```
warning: startup nudge to "gc-toolkit__polecat-gn-n411" delivered but not confirmed:
  nudge: submit Enter delivered to tmux but not confirmed (busy state never observed)
```

Affected sessions sit at the prompt showing *"Press up to edit queued
messages"* and never start work. I had to `gc session submit` manually twice —
once for a converse session, once for the polecat that ran triage run 2 — to
get the pass moving. On a self-driving city this is indistinguishable from an
idle pool.

### R3-11 — `deferred_by_wake_budget` throttled the polecat pool to one live session

For roughly ten minutes the gc-toolkit polecat pool held at
`poolDesired = 2 / scaleCheck = 1` with repeated
`outcome=deferred_by_wake_budget`, while the single live polecat was itself
wedged on an interactive menu from an unrelated bead. The triage run-2 step sat
Ready and unclaimed the whole time.

### R3-12 — The proactive `scale_check` cannot run at all

Every reconcile pass logs:

```
buildDesiredState: agent "proactive": running command "GC_DOLT_PORT='36758' case \"${GC_PROACTIVE_ENABLED:-}\" in …": exit status 2 (using new demand=0)
scaleCheck: PARTIAL — scale_check failed for gc-toolkit/gc-toolkit.proactive,signal-loom/gc-toolkit.proactive
```

The reconciler prefixes `GC_DOLT_PORT='…' ` to the script, whose first token is
`case`. An environment assignment cannot prefix a shell keyword — it is a syntax
error, hence exit 2, hence proactive demand is permanently 0 regardless of
`GC_PROACTIVE_ENABLED`. `agents/proactive/agent.toml`'s `scale_check` is
unchanged in this delta (only comments moved), so **this predates `a3d5003`**
and is out of scope here — but it means step 5 of the runbook cannot work as
written until it is fixed. Moving the `case` behind a no-op first command
(`:` or `true;`) would be enough.

### R3-13 — `gate-visit.test.sh`: 34 passed, 0 failed

Including the four `tracks`-edge assertions and the `no parent-child edge`
assertions in both `mol-visit.toml` and `mol-triage-recurrence.toml`, and the
consumer census (4 marked copies found). The fixture's rename from
"parent-child edge" to "tracks edge" in this delta is accurate.

---

## Summary

| # | area | verdict |
|---|---|---|
| R3-01 | converse claim → hold → record → stamp/verify/close | **PASS** |
| R3-02 | converse sessions drained mid-prep as "orphaned" | **DEVIATION (serious, runtime)** |
| R3-03 | step ordering; recovery strips continuation_group | minor |
| R3-04 | triage: files one visit, logs every subject, never guesses | **PASS** |
| R3-05 | triage: second run stacks instead of skipping | **DEVIATION (serious)** |
| R3-06 | `unrouted` token matches nothing as written | **DEVIATION (serious)** |
| R3-07 | `$GC_BEAD_ID` self-close is a no-op (another site) | **DEVIATION** |
| R3-08 | agents wrongly blame `--title`, deviate from the marked block | false positive, real effect |
| R3-09 | pool = 6, nothing else about spawning changed | **PASS** |
| R3-10–13 | environment | noted |

**On the delta as a whole: the converse rewrite lands.** Every clause the new
prompt added was observed doing what it says, including the two that round 2
found claimed-but-absent (outcome stamp read back before close; fold check on a
concurrent sibling hold). The hold format is right, and the close touches only
the visit.

**The triage path needs two one-line fixes before it can run unattended.**
R3-05 and R3-06 are both in `mol-triage-recurrence.toml` step 1–2 and both are
small: widen the open-visit listing beyond `--status=open`, and write the
`unrouted` predicate with the `// ""` coalescing the rest of the step already
uses. Left as-is, the formula stacks a visit per day on every subject with a
live sitting, and its only shipped token silently matches nothing on a real
store. Neither is a design problem; both are the literal text.

**R3-02 is the one I would not ship without a decision on.** A pool whose whole
purpose is holding long conversations should not have its sessions reaped
mid-sitting, and the reconciler currently reaches for a reassign that the
holder guard is designed to refuse. The lease was expired the whole time — the
tool that works (`bd reclaim`) is right there. Whether that is a gc runtime fix
or a pack-side `heartbeat` obligation on converse is the operator's call, but
`agent.toml`'s comment currently promises a recovery that this run did not
observe within a useful window.

Nothing was fixed this round. Changes made to the store: created triage subject
`tk-wyrf8` and smoke visit `tk-tyf7n` (closed by the converse session);
reclaimed `tk-tyf7n` once with `bd reclaim --older-than 0s` to unwedge R3-02;
created and closed throwaway probe `tk-jjr6q`. **Left in place deliberately as
evidence:** the stacked pair `tk-2x7xr` (held) and `tk-8s15e` (open) on
`tk-wyrf8` — close one of them before the next recurrence or R3-05 compounds.
