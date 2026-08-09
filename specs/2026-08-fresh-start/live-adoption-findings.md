---
name: Findings — live adoption of the fresh-start branch (validator run, 2026-08-08)
description: Numbered findings from running specs/2026-08-fresh-start/live-adoption-runbook.md steps 1–4 against branch claude/gc-toolkit-fresh-start-ehvljb in the gc-next test city, with the before/after doctor delta, the Phase 0 self-rename verdict, and an ADOPT/ADAPT/BLOCK recommendation.
---

# Findings — live adoption, fresh-start branch

**Branch:** `claude/gc-toolkit-fresh-start-ehvljb` @ `a295fb7`
("feat(cutover): retire bead-host — the visit spine is the only conversation mechanism")
**City:** `/Users/zook/Code/gc-next` (test city), rigs `gc-toolkit` (tk) and `signal-loom` (sl)
**Host:** darwin 25.6.0 (macOS, arm64), `gc version` = `edge`, dolt 2.2.3, bd 1.1.0 (dev)
**Run:** 2026-08-08 22:00–23:05Z. Runbook steps 1–4; step 5 (intake default) deliberately skipped.
**Recommendation: ADAPT.** Reasons in §Recommendation.

**Headline:** the design's one unproven integration works. A pool-spawned
converse session self-renames to its subject on claim, and does it again on
every re-claim (F-07). The spine's failures are all in the *plumbing around*
that mechanism, not the mechanism itself — and two of them (F-06, F-11) stop a
visit from ever reaching a session at all.

Nothing was pushed to any git remote. One local commit was made by an agent,
not by me — see F-14.

---

## What I could not test

Stated up front so nothing below reads as broader than it is.

- **Step 1 expectations 4 and 5** (warm same-group vacuum; cold fresh session
  reconstituting from the record) were **not cleanly isolated**. Both converse
  slots stayed occupied for the whole window, and the sessions kept finding
  cross-group visits to claim, so neither an empty-group drain nor a cold
  respawn ever occurred. What I *did* see is reported as F-09/F-10 and is
  weaker evidence than the runbook asks for.
- **The triage-recurrence "file a visit on a ripe subject" path** never ran
  (F-18). I saw only the no-op path. The skip-because-visit-is-open path was
  also not reached.
- **Step 5 / `GC_PROACTIVE_ENABLED=1`** was skipped per instruction, so F-19 is
  a code-read finding, not a runtime one. It is the one finding here I have not
  personally executed.
- **`gc-helm.sh board` on a stock macOS host** cannot run at all (F-15). Every
  board observation below (F-16, F-17) was made through a hand-written `timeout`
  shim. They are evidence about the board's *logic*, not about it working on
  this host.
- Both rigs were repointed at the new pack (see F-01), so signal-loom results
  are a second data point, not a control.

---

## Step 0 — adoption and the doctor delta

### F-01 — The pack moved to the repo root; every importing city.toml needs a rename, not just a repoint. **DEVIATION (unpredicted by the runbook)**

**Expected:** runbook step 0 — "Check out `claude/gc-toolkit-fresh-start-ehvljb`
in the gc-toolkit rig checkout … the branch is self-contained."

**Observed:** the branch ships the pack at the **repo root** (`agents/`,
`formulas/`, `orders/`, `doctor/`), where the prior branch shipped it at
`packs/gc-next/`. The city could not load at all:

```
gc status: expanding packs: rig "signal-loom" import "gc-next": loading pack.toml:
  open /Users/zook/Code/gc-toolkit/packs/gc-next/pack.toml: no such file or directory
```

Repointing `source` is not sufficient — the **import binding key must also be
renamed** to `gc-toolkit`, because the new orders name the bare pool
`gc-toolkit.polecat` and `mol-visit`'s `binding_prefix` defaults to
`"gc-toolkit."`. A city that keeps the old `[rigs.imports.gc-next]` key and
merely repoints `source` will load, register the roster, and then have both
orders route to a pool that does not exist under that name.

Applied (both rigs):

```toml
[rigs.imports.gc-toolkit]
source = "/Users/zook/Code/gc-toolkit"
```

Also removed as dead on this branch: `[agent_defaults] default_sling_formula =
"mol-nx-work"` (gc-next formula, absent here). `default_branch` on the
gc-toolkit rig was moved to the new branch.

**Verdict: DEVIATION** — in the runbook, not the pack. Step 0 should carry the
binding-key rename explicitly; it is a silent mis-wire otherwise.

### F-02 — `check-liveness-sweep-wired` passes; no new failures attributable to the branch. **CONFIRMED**

**Expected:** "the new `check-liveness-sweep-wired` passes; no new failures."

**Observed:**

| | before (prior branch) | after (fresh-start, settled) |
|---|---|---|
| passed | 98 | 104 |
| warnings | 7 | 10 |
| failed | **1** | **1** |

```
✓ gc-toolkit:check-liveness-sweep-wired — OK: liveness sweep + triage recurrence wired
  (orders bare-pool/rig-scope; formulas fail-safe with marked gate-visit copies)
```

The single failure, `order-firing-current`, **was already failing before** the
branch and is a controller-uptime artifact (`dolt-health: last fired 2m ago,
expected every 1m`), not a branch regression.

Checks that appeared (all gc-toolkit pack checks, all passing except as noted):
`gastown:check-scripts`, `check-base-artifact-collision` (⚠, skipped —
"gastown base pack not materialized (import-cache model); see gc-xdzml"),
`check-cycle-recycle-hook`, `check-keeper-repour-reassign`,
`check-keeper-resume-handoff-token`, `check-liveness-sweep-wired`,
`check-merge-gate-drop`, `check-pr-prep-single-commit-unchanged`,
`check-rebase-exceptions-through-keeper`, `check-rebase-worktree-branch-reuse`,
`check-startup-discovery`.

Checks that disappeared: `gc-next:check-nx-lander-single-writer`,
`gc-next:check-nx-patrol-chain-liveness` (expected — the gc-next pack is gone),
and `rig-pack-coverage` (stops reporting because the new pack declares no
rig-scoped `named_session`; benign).

Warning deltas: `codex-hooks-drift` cleared. `config-refs` (+3, see F-03),
`config-semantics` (+2, refinery `idle_timeout`/`sleep_after_idle` overlap —
inherited from the imported gastown roster, pre-existing shape),
`session-model` (+5, see F-22) appeared. `events-log-size` grew during the run.

**Verdict: CONFIRMED.**

### F-03 — `gastown//agents/...` prompt_template does not resolve; two agents silently render a 16-line stub. **DEVIATION**

**Expected:** `agents/polecat-codex/agent.toml` states the contract in its own
comment — *"an unknown pack fails config load rather than silently falling back
to the default agent prompt."*

**Observed:** the opposite. Doctor:

```
⚠ config-refs — 3 config reference issue(s)
  agent "signal-loom/gc-toolkit.polecat-codex": prompt_template
    "/Users/zook/Code/gc-toolkit/gastown/agents/polecat/prompt.template.md" not found
  agent "gc-toolkit/gc-toolkit.polecat-codex": prompt_template … not found
  agent "gc-toolkit.mayor-thread": prompt_template
    "/Users/zook/Code/gc-toolkit/gastown/agents/mayor/prompt.template.md" not found
```

The `<pack>//<subpath>` form is being resolved against the **pack directory**
(`<pack-root>/gastown/…`) rather than the imported gastown **cache** dir. Under
the retired-materialization model that path never exists. Config loads anyway
and the agents fall back to the generic Gas City stub. Rendered prompt sizes:

```
gc-toolkit/gc-toolkit.polecat        1540 lines   (correct — patched gastown polecat)
gc-toolkit.mayor                      442 lines   (correct)
gc-toolkit/gc-toolkit.converse         73 lines   (correct — pack-local prompt)
gc-toolkit/gc-toolkit.proactive       121 lines   (correct — pack-local prompt)
gc-toolkit/gc-toolkit.polecat-codex    16 lines   ← STUB
gc-toolkit.mayor-thread                16 lines   ← STUB
```

The stub is *"You are an agent in a Gas City workspace. Claim available work and
execute it."* — a codex polecat rendering that would claim real work with none
of the convoy, non-impl-done, or file-work-records doctrine.

Note this survives `gc import install` (which *did* fix F-04), so it is not a
lock-state problem. Not caused by the visit spine, but it is exposed by adopting
this pack and it is a silent correctness failure, not a warning-and-degrade.

**Verdict: DEVIATION.**

### F-04 — `packv2-import-state` fails until `gc import install` is run. **ENVIRONMENT**

**Observed:** first doctor after adoption added a second failure:

```
✗ packv2-import-state — 1 import state issue(s)
  missing-lock-entry | rig:gc-toolkit:gc-toolkit/gastown |
    https://github.com/gastownhall/gascity-packs/tree/main/gastown |
    declared remote import is not present in packs.lock
```

`gc import install` resolved it ("Installed 5 remote import(s)"; check → ok).
Recording because the runbook's step 0 is `gc doctor` alone, and a reader
following it literally will see a failure the runbook says not to expect.

**Verdict: ENVIRONMENT** — one documented command short in step 0.

---

## Step 1 — spine smoke (the core evidence)

### F-05 — The runbook's own step-1 snippet stamps a pool that never routes. **DEVIATION (runbook defect, high impact)**

**Expected:** running the runbook's step-1 block as the operator files a visit
that a converse session claims.

**Observed:** nothing spawned for 5 minutes. The snippet is

```sh
POOL="${GC_RIG:+$GC_RIG/}gc-toolkit.converse"
```

In an operator shell `GC_RIG` is **unset**, so this expands to the *bare*
`gc-toolkit.converse`. The read side is exact-match
(`docs/gascity-routing-model.md` §the-read-side), so the visit is never offered.
Inside a formula step this is correct — agents have `GC_RIG` set — so the bug is
confined to the operator-facing copy in the runbook. `gc-helm.sh open` gets it
right independently (F-17).

Proven directly rather than by absence — two visits on the same healthy subject,
created seconds apart, differing only in the routed_to form:

```
$ gc hook gc-toolkit/gc-toolkit.converse   # 3 runs, 10s apart
run1: F/bare(tk-wcn2x)=0   G/qualified(tk-lgxlg)=1
run2: F/bare(tk-wcn2x)=0   G/qualified(tk-lgxlg)=1
run3: F/bare(tk-wcn2x)=0   G/qualified(tk-lgxlg)=1
```

`gc doctor`'s `v2-routed-to-namespace` check reports **ok** for the bare value,
so nothing catches this.

**Verdict: DEVIATION.** The runbook should hard-code the rig-qualified form (or
tell the operator to `export GC_RIG=<rig>` first). This is the first thing a
new adopter runs and it fails silently.

### F-06 — A visit on a blocked/arrested subject is never claimable: the parent-child edge transmits the subject's block. **DEVIATION (design-level, high impact)**

**Expected:** the canonical `gate-visit` snippet files a claimable visit on any
subject bead.

**Observed:** the smoke visit `tk-rvdb0` on subject `tk-dinqt` never entered
`gc bd ready`, and therefore was never offered, even after F-05 was corrected.
`tk-dinqt` is arrested (park-arrest dep edge, `blocked_reason` naming the
credential outage). The visit inherits it through the `gc bd dep add "$VISIT"
"$SUBJECT" --type=parent-child` line.

Isolated with a 2×2 (all four visits identical except the two variables):

| probe | subject | `--type=parent-child` edge | in `bd ready` |
|---|---|---|---|
| PROBE-B `tk-ub2mq` | `tk-2zmwe` (healthy) | no | **yes** |
| PROBE-B after edge added | `tk-2zmwe` (healthy) | yes | **yes** (re-checked at +5/+15/+30/+60s) |
| PROBE-D `tk-p1s72` | `tk-dinqt` (arrested) | no | **yes** |
| PROBE-E `tk-v21nd` | `tk-dinqt` (arrested) | yes | **no** |
| smoke `tk-rvdb0` | `tk-dinqt` (arrested) | yes | **no** |

So the edge is harmless on a healthy subject and fatal on a blocked one.

Why this matters more than it looks: an arrested, gated, or blocked bead is
*precisely* the bead an operator most wants to talk about — `tk-dinqt` is
arrested behind a credential outage that only a human can clear, and the spine's
answer to "I want to talk about this" is the one thing that cannot be filed on
it. `gc-helm.sh open` on such a bead reports success and files a visit that will
never be claimed.

Both open visits in that group (`tk-rvdb0`, `tk-v21nd`) are still sitting open
and unclaimed at the end of the run.

**Verdict: DEVIATION.** Not a fix I made; the shape of the fix (drop the edge,
use a non-blocking edge type such as `tracks`, or exempt `task_kind=visit` from
blocker inheritance) is the author's call and touches the canonical snippet in
three copies plus `gc-helm.sh`.

### F-07 — Expectation 2: the pool-spawned session **does** self-rename to its subject on claim. **CONFIRMED — and replicated**

This is tk-h9pq5 Phase 0, the one unproven integration. It works.

A converse session spawned from pool demand with no keystroke from me, claimed
the visit, and renamed itself:

```
ID       TEMPLATE                        TARGET                            TITLE
gn-u1ry  gc-toolkit/gc-toolkit.converse  gc-toolkit/gc-toolkit.converse-1  tk-2zmwe — probe pool-spa...
```

Stronger than the runbook asks for: **the rename repeats on every re-claim and
rotates correctly across subjects.** `gn-u1ry` renamed itself three times over
the run as it worked three different groups:

```
tk-2zmwe — probe pool-spa...   (claim 1, visit tk-ly61i)
tk-dinqt — lease/heartbea...   (claim 2, visit tk-p1s72)
tk-yw3zb — converse visit      (claim 3, visit tk-24a6m)
```

and `gn-324y` independently did the same (`tk-2zmwe …` → `tk-uorin — visit`).

The session itself verified the safety property and recorded it on the subject:
*"rename moves `TITLE` only; `TARGET` and assignee are untouched, verified at
field level. Self-titling cannot orphan an agent from its hook."*

**Verdict: CONFIRMED.** Neither §Q2 fallback is needed. This is the finding the
run was for, and it lands on the primary mechanism.

### F-08 — Expectation 3: the session holds `in_progress` with the subject's state and a trailing "Next (yours):" line. **CONFIRMED**

Verbatim tail of the hold (`gc session peek gn-u1ry`):

```
  Next (yours): ratify the probe as renamed (or send it to signal-loom), name
  <SUBJ>, and say whether the heartbeat bug gets filed — then I'll apply the
  stamps, write gate-evidence.md, and route the filing.
```

Nothing below it. It had rebuilt the subject's slice, found that
`plans/conversation-spine/build/` does not exist, and said so rather than
inventing state: *"I grounded AC-0a in specs/tk-h9pq5/design-doc.md §Q2
instead."* The prep was real, not a restatement of the visit body.

**Verdict: CONFIRMED.**

### F-09 — The close contract holds on outcome-to-subject and close-only-the-visit; `gc.outcome` was stamped on 2 of 3 closed visits. **DEVIATION (partial)**

I played the operator via `gc session submit gn-u1ry "…"` and watched the four
contract clauses.

Polled result (30s interval):

```
t+150s visit=in_progress outcome=-                     subject=open notes=18499
t+180s visit=in_progress outcome=-                     subject=open notes=23591
t+210s visit=closed      outcome=ratified-and-recorded subject=open notes=23591
```

- **Outcome appended to the subject's notes** — CONFIRMED. 18499 → 23591 chars.
  It is a genuine outcome, not a log dump, and it refreshed the rolling summary
  block at the top of the notes exactly as the prompt's "Record stewardship at
  scale" clause specifies. It correctly folded in the *other* session's visit
  ("Folds in visit 2's summary delta").
- **`gc.outcome` stamped on the visit** — **2 of 3**. `tk-ly61i` =
  `ratified-and-recorded`, `tk-p1s72` = `probed-and-recorded`, but `tk-ub2mq`
  closed at 22:49:32Z with **no `gc.outcome` key at all**, despite having
  appended its outcome to the subject (notes 23591 → 26622). Same role, same
  prompt, same city, one of three missed it.
- **Only the visit closed** — CONFIRMED. Subject `tk-2zmwe` remained `open`
  throughout; no subject was closed by any converse session all run.
- **Session drains when the group is empty** — NOT OBSERVED, see F-10.

**Verdict: DEVIATION** on the stamp. Three of four clauses confirmed. An
unstamped closed visit is invisible to anything keying on `gc.outcome`, and
nothing in the run would have told me it happened.

### F-10 — Empty-group drain never occurred; sessions keep claiming cross-group visits instead. **NOT OBSERVED (behaviour is per the prompt)**

**Expected:** "An empty continuation group after your close is a hard session
boundary — drain."

**Observed:** after closing `tk-ly61i` (group `tk-2zmwe`), `gn-u1ry` did not
drain — it re-claimed `tk-p1s72` from group `tk-dinqt`, then `tk-24a6m` from
group `tk-yw3zb`. This is *literally correct* per prompt step 7 ("A successful
claim is authoritative even if it names a different subject's group: work it"),
but it means the empty-group boundary is only reached when **no visit is
claimable anywhere in the rig** — not when the session's own group empties. In a
rig with any visit backlog, a converse session is effectively resident.

Consequence for the runbook: expectations 4 and 5 (warm vacuum, then cold
respawn after drain) are not reachable in a rig with a non-empty visit queue,
which is exactly the state the liveness sweep creates on first run. I could not
test them (see §What I could not test).

**Verdict: NOT OBSERVED.** Flagging the tension between prompt step 7 and the
runbook's expectations 4/5 rather than calling either wrong.

### F-11 — Two converse sessions held the **same** continuation group concurrently. **DEVIATION**

**Expected:** the design's "the subject's dialogue is … a continuation group
with you attached"; siblings vacuum onto the live session.

**Observed:** two sibling visits in group `tk-2zmwe` were claimed by two
different sessions at the same time:

```
tk-ly61i  in_progress  group=tk-2zmwe  gc-toolkit/gc-toolkit.converse-1  sess=gn-u1ry
tk-ub2mq  in_progress  group=tk-2zmwe  gc-toolkit/gc-toolkit.converse-2  sess=gn-324y
```

Both sessions titled themselves `tk-2zmwe — …`. Both then did full independent
prep on the same subject, both asked me nearly the same three questions, and
both wrote outcomes to the same subject's notes. The claim predicate has no
group affinity — nothing prefers the session already attached to the group, and
nothing prevents a second slot from taking a sibling.

It degraded gracefully here only because the second session noticed the first's
work in the notes and folded rather than duplicated. That is the LLM being
careful, not the mechanism being safe.

Related: `mol-triage-recurrence`'s own step log flagged the same shape unbidden
— *"three open visits stacked on one group is the shape the skip-if-visit-open
guard exists to prevent, and nothing here would catch it."*

**Verdict: DEVIATION.**

### F-12 — Warm reuse of a live session does happen (weaker form). **PARTIAL**

Both later visits (`tk-24a6m`, filed by `gc-helm.sh open`; `tk-7f7kk`, filed by
the sweep) were picked up by the two **already-running** sessions with no new
spawn, and each session re-titled to the new subject. So "an existing session
absorbs new visits rather than spawning" is confirmed; "a *same-group* sibling
vacuums onto the *same* session" is not, and F-11 shows it demonstrably does not
always hold.

**Verdict: PARTIAL.**

### F-13 — Pool cap behaves; excess visits queue rather than spawn. **CONFIRMED**

`max_active_sessions = 2` held. With both slots busy, `tk-lgxlg` (correctly
routed) sat `open` and unclaimed rather than spawning a third session. A held
visit never occupied an impl slot — polecats ran concurrently in their own pool
throughout.

**Verdict: CONFIRMED.**

### F-14 — A converse session committed into the rig **root** working tree, which is also the live pack import source. **DEVIATION**

**Observed:** `gn-u1ry`, during its hold, wrote and committed evidence:

```
$ git -C /Users/zook/Code/gc-toolkit log --oneline -2
325142d docs(spine): record AC-0a Phase 0 probe evidence
a295fb7 feat(cutover): retire bead-host — the visit spine is the only conversation mechanism
```

New file `plans/conversation-spine/build/gate-evidence.md`, committed **on the
branch under test, in the rig root**, not in a worktree. `converse`'s
`work_dir` is `.gc/agents/converse/{{.AgentBase}}` — a scratch dir with no
worktree and no `pre_start` worktree setup — so a converse session that decides
to write a file has nowhere to put it but the rig root.

This breaks the invariant the self-hosting import relies on, stated in the
city.toml comment I inherited: *"workers build in `.gc/worktrees/`, never in the
rig root, so the live source only changes when something merges here."* Here the
rig root **is** the live pack import source, so a converse commit mutates live
pack config for the whole city.

Not pushed. Left in place — it is the author's to judge, and the evidence file
itself is good work.

**Verdict: DEVIATION.** Either converse should get a worktree, or the prompt
should forbid writing files (its "you never land or close implementation work
yourself" clause evidently does not read as "do not commit").

---

## Step 2 — triage subjects

### F-15 — A hand-created triage subject is inert, as specified. **CONFIRMED**

Created `tk-so3um` ("triage: held ideas (gc-toolkit)") with
`task_kind=triage-subject` per the runbook. Nothing happened — no visit, no
board row, no session. Correct.

Separately, the sweep created its own standing subject `tk-uorin` with both
markers stamped (`task_kind=triage-subject`, `triage.scope=unnamed-waits`), so
the idempotency key the formula searches on is present and a second pass will
not duplicate it.

**Verdict: CONFIRMED.**

---

## Step 3 — the liveness sweep

### F-16 — The sweep fired unforced on `gc` start, in both rigs, and produced exactly one batch visit each. **CONFIRMED**

I did not have to force it — it fired within ~3 minutes of `gc start`:

```
ORDER            RIG          BEAD          EXECUTED
liveness-sweep   signal-loom  sl-cc77       2026-08-08T22:21:08Z
liveness-sweep   gc-toolkit   tk-lcd03      2026-08-08T22:18:12Z
```

Both rigs: standing subject created on first run, **one** visit filed, a converse
session holding it.

```
gc-toolkit:  tk-uorin  "triage: unnamed waits (this rig)"
             tk-7f7kk  "visit: tk-uorin — unnamed waits: 66 candidates to disposition"
signal-loom: sl-k7wk   "triage: unnamed waits (this rig)"
             sl-g0jc   "visit: sl-k7wk — unnamed waits: 6 candidates to disposition"
```

**First-census volume: 66 candidates (gc-toolkit), 6 (signal-loom) — one
conversation each.** The runbook predicted a long list; 66 out of 279 open beads
is that, and it cost exactly one visit. The batching decision is vindicated: the
per-bead form would have filed 66 conversations.

The census body is high quality — it shows its work as a funnel
(279 open → 85 ready → 68 after filtering → 2 dropped by the children check →
66), names the two beads dropped by the children check, and states
"No 'epic what-comes-next' candidates this pass" rather than omitting the class.

**Verdict: CONFIRMED.**

### F-17 — `list_cap` is honoured for the enumerated list, then exceeded by cohort. **DEVIATION (minor, arguably an improvement)**

**Expected:** "files ONE batch visit listing every genuinely idle bead (up to 20
lines)"; `list_cap` default `20`.

**Observed:** a 133-line body with **all 66** present — 20 enumerated
individually under "## The 20 enumerated — plain work beads, P1 first then
oldest", then the remaining 46 grouped into five labelled cohorts (A–E) with
every id still listed.

I think this is better than the spec, but it is not what the spec says, and a
consumer sizing the visit body on `list_cap` would be wrong by 3×. The cap
should either say what it caps (individually-enumerated lines) or the formula
should stop at 20.

**Verdict: DEVIATION (minor).**

### F-18 — The sweep's own output identifies a real classification gap: class 2 ignores `tracks` edges. **DEVIATION (found by the sweep, not by me)**

Quoted from the batch visit body:

> 22 of the 66 are not really idle; they are waiting on a `tracks` edge, and the
> sweep's class 2 counts only `blocks` and `parent-child`. Convoys carry their
> members with `tracks`.

Cohorts A (12 convoys) and B (10 "Step spec for …" beads) are both this. So
**a third of the first census is false-positive** — beads that are
waiting-on-structure by construction but classed as unnamed waits because the
edge type is not in the spec's class-2 definition.

Worth taking seriously precisely because it costs the sweep its credibility on
first contact: the operator's first sitting is a 66-line list of which 22 are
noise.

**Verdict: DEVIATION.**

---

## Step 4 — triage recurrence

### F-19 — First pass: correct no-op with the fail-safe intact. **CONFIRMED**

Forced with `gc sling gc-toolkit/gc-toolkit.polecat mol-triage-recurrence
--formula`. Step `tk-t8igz` closed with:

```
Fail-safe: PASSED (gc bd list --status=open --limit=0 returned an array of 278).
Result: NO-OP. Zero open beads carry task_kind=triage-subject, so the per-subject loop
had no iterations: nothing skipped, nothing evaluated for ripeness, no visit filed.
```

It ran before the sweep had created `tk-uorin`, so zero subjects was the truth,
and it filed nothing — pull-only, no board row. Exactly the specified shape. It
also logged what it deliberately did *not* do (no ripeness heuristic run, no
`triage.scope` hint interpreted), which is the right kind of honesty for a
formula that is allowed to be silent.

**Verdict: CONFIRMED** for the no-op path only. The skip-because-open and the
file-a-visit paths were not exercised (F-20).

### F-20 — A second forced recurrence never got claimed; both new formulas' roots are not Ready-visible. **DEVIATION**

`gc sling` accepted the second dispatch but warned:

```
formula "mol-triage-recurrence" root is a molecule container, not Ready-visible work;
scale-from-zero pools will not wake for this wisp. Convert the formula to
phase="vapor"/root-only or formulas v2 before routing it to a pool
```

The wisp `tk-qetpk` then sat `open`, unassigned, for **20+ minutes** while the
polecat pool was at 1 of 5 slots — i.e. with capacity, but no wake. The first
dispatch had succeeded only because three polecats happened to be warm.

The same warning applies to `mol-liveness-sweep`. Both orders (`liveness-sweep`
6h, `triage-recurrence` 24h) target `gc-toolkit.polecat`, a `min_active_sessions
= 0` pool. On a quiet city — which is the normal state between cooldowns, and
the exact state a 6h/24h cadence assumes — there may be no warm polecat to wake.
The sweeps fired here because `gc start` had just warmed the pool.

I could not therefore reach the "skip: visit already open" or "file: scope is
ripe" branches of step 4.

**Verdict: DEVIATION.** This is the finding most likely to make the machinery
quietly stop working a day after adoption, when nobody is watching.

---

## The board

### F-21 — `gc-helm.sh` cannot run on macOS: it requires GNU `timeout`. **DEVIATION (hard, host-blocking)**

```
$ ./assets/scripts/gc-helm.sh board
./assets/scripts/gc-helm.sh: line 230: [: : integer expression expected
jq: invalid JSON text passed to --argjson
```

Root cause: `timeout` does not exist on stock macOS (nor `gtimeout` here).

```
$ command -v timeout gtimeout
(no output)
```

`gc-helm.sh` calls it at 5 sites, load-bearing at line 228:

```sh
rigs_raw=$(timeout "${TIMEOUT:-10}" gc rig list --json 2>/dev/null || true)
```

`timeout` not found → `rigs_raw` empty → `RIGS` empty → the `-eq 0` guard
throws instead of taking the "could not enumerate rigs" exit-3 path → execution
continues into `jq --argjson` with garbage. So the failure mode is not even a
clean error; the intended guard is bypassed.

`core:check-binaries` checks `jq` and `gh` but not `timeout`, so doctor is
green while the board is dead.

Everything below (F-22, F-23) was obtained through a hand-written `timeout` shim
placed on `PATH` for the validation only. **Nothing was changed in the pack.**

**Verdict: DEVIATION.** Either vendor a portable timeout helper, degrade
gracefully when it is absent, or add it to `check-binaries` so adoption fails
loudly on darwin instead of silently.

### F-22 — The board caches a failed gather as "0 anchors" and serves it. **DEVIATION**

The run immediately after the broken (pre-shim) invocation returned:

```
2026-08-08T22:28:29Z · 3 rigs · 0 anchors (cached 45s)
No open anchors need attention. (Nothing floats.)
```

That is a false all-clear — there were 5 anchors. `--refresh` produced them
immediately. A transient gather failure is therefore indistinguishable from a
genuinely quiet board for the cache TTL, on the one surface whose whole job is
to tell a human whether anything needs them.

**Verdict: DEVIATION.**

### F-23 — Board renders correctly with no flag/FLAGGED anywhere, and the held glyph works. **CONFIRMED**

Before opening a visit:

```
  SEV      ID         RIG          KIND     N/M    FRONTIER                            NEEDS
  HIGH     tk-yw3zb   gc-toolkit   epic     0/11   11 open · 0 in-progress (stranded)  decomposed, idle — assign or visit
  ELEVATED tk-tqk96   gc-toolkit   decision —      human-gated decision                operator decision
  …
Legend: HIGH=stranded/unowned · ELEVATED=decision/stale/stuck · NORMAL=active · LOW=empty/complete
Held: ● an open visit holds this anchor's conversation (attach via the sessions picker) · blank = none
open <id> to file a visit · react <id> to advance a takeaway-less row.
```

After `open tk-yw3zb`:

```
● ELEVATED tk-yw3zb   gc-toolkit   epic     0/12   12 open · in conversation           open to join
```

Held glyph present, severity dropped HIGH → ELEVATED, FRONTIER and NEEDS both
re-derived from the conversation. **No `FLAGGED` severity band, no flag verb, no
`gc.attention` anywhere** in the board, the legend, or the usage text. The
`gc.attention` removal is clean on this surface.

**Verdict: CONFIRMED.**

### F-24 — `open` twice on the same bead files once, then dedups. **CONFIRMED**

```
########## OPEN #1 ##########
✓ Updated issue: tk-24a6m — visit: tk-yw3zb — operator pick from the board
✓ Added dependency: tk-24a6m … depends on tk-yw3zb … (parent-child)
gc-helm: visit tk-24a6m filed on tk-yw3zb (pool gc-toolkit/gc-toolkit.converse) —
       a converse session will spawn (cold) or vacuum it (warm).

########## OPEN #2 ##########
gc-helm: visit tk-24a6m is already open for tk-yw3zb — a converse session holds it
       (or will spawn/vacuum it).
```

Exactly as specified. Note it stamps the **rig-qualified** pool
`gc-toolkit/gc-toolkit.converse` — `gc-helm.sh` gets right what the runbook's
step-1 snippet gets wrong (F-05).

**Verdict: CONFIRMED.**

---

## `gc.attention` removal

### F-25 — `agents/proactive/prompt.template.md` still instructs the removed `flag` verb. **DEVIATION**

`specs/2026-08-fresh-start/attention-flag-removal.md` lists a sweep inventory
covering `gc-helm.sh`, `services/helm/`, `tools/helm-surface-fixture.sh`,
`mol-first-reaction.toml`, `tools/gc-proactive.sh`, `agents/proactive/
PROVENANCE.md`, and two docs. **`agents/proactive/prompt.template.md` is not in
that list**, and it still carries the flag step:

```
 9:   is, write that as a card on the bead, and flag it onto the Helm —
64: 4. **Flag the bead onto the board** so it surfaces as *advanced*:
66:      ATTN="$(git rev-parse --show-toplevel)/assets/scripts/gc-helm.sh"
67:      "$ATTN" flag <id> --reason "advanced: first reaction ready — accept or redirect"
```

The verb is gone from the dispatcher:

```sh
case "${1:-}" in
    open) … react) … takeaway) … board) … -h|--help|help) …
    *)  echo "$PROG: unknown verb '$1' (try: board, open, react, takeaway, help)" >&2
        usage; exit 2 ;;
```

So a proactive worker following its prompt hits `exit 2` at step 4 and never
reaches step 5 (`takeaway --release`), which is what reopens and releases the
bead. `mol-first-reaction.toml` itself was converted correctly — the prompt and
the formula now disagree, and the prompt is what the agent reads first.

`agents/proactive/PROVENANCE.md` lines 12 and 64 also still describe flagging,
though the spec lists that file as swept.

This only bites under `GC_PROACTIVE_ENABLED=1` (runbook step 5), which I skipped
— so this is read, not run. It is the finding I am least able to vouch for
empirically and the easiest to confirm.

**Verdict: DEVIATION.**

---

## Environment findings the runbook did not predict

### F-26 — `gc bd ready --json` intermittently emits invalid JSON. **ENVIRONMENT**

Twice within a minute, under concurrent agent writes:

```
jq: parse error: Invalid string: control characters from U+0000 through U+001F
must be escaped at line 33, column 249
```

Not reproducible on demand — five consecutive runs afterwards were clean and
byte-identical (305558 bytes, 85 items), and the same payload redirected to a
file parsed fine. So it is a transient torn read under write pressure, not a
poison bead.

Consequence for this branch: `mol-liveness-sweep`'s and `mol-triage-recurrence`'s
fail-safe (`jq -e 'type=="array"'`) would trip and **abort the pass, filing
nothing** — which is the designed and correct behaviour, and worth noting as a
point in the fail-safe's favour. But on a 6h/24h cadence, a pass silently lost
to a transient is a pass lost for 6h/24h.

### F-27 — `session-model` warning appeared during the run: 5 mayor wisps orphaned. **ENVIRONMENT**

```
⚠ session-model — 5 session model finding(s)
  missing-bead-owner: gn-wisp-rxnh9 is assigned to missing session bead gc-toolkit.mayor
  … ×5
```

Mayor-related, not spine-related; appeared after the city restart, not present
in the before-doctor. Recording it so it is not later mistaken for spine damage.

### F-28 — Unexplained: both converse sessions showed an unsent, operator-shaped line pre-filled in their input box. **UNEXPLAINED**

`gc session peek` on both held sessions showed a draft I did not type:

```
❯ accept gc-toolkit, use tk-2zmwe as SUBJ, file the heartbeat bug          (gn-u1ry)
❯ accept the gc-toolkit result, subject is tk-2zmwe, file the lease bug    (gn-324y)
```

Each is a plausible reply to that session's own three questions, and each was
present *before* I submitted anything. My best guess is a provider-side
suggested-reply affordance rendered in the input box rather than a real
submission — no `gc.outcome` or notes changed until I actually submitted — but I
could not confirm it, and if it *is* a real injection path into a held session
that matters a great deal. Flagging it as unexplained rather than guessing.

### F-29 — Legacy cleanup performed on the city (not on the branch)

For the record, since it changes what a re-run would see: `city.toml` was
rewritten (F-01) — `[rigs.imports.gc-next]` → `[rigs.imports.gc-toolkit]`
pointing at the repo root for **both** rigs, `default_branch` moved to the
fresh-start branch, and the dead `default_sling_formula = "mol-nx-work"`
removed. The build-factory trial hold (`[[rigs.patches]] agent =
"implementation-worker", suspended = true`) was left **untouched** — it is a
deliberate operator hold and not mine to lift. The prior branch's uncommitted
working tree was preserved as commit `e5476d8` on
`claude/gas-city-pack-architecture-1uyfq2` before checkout; nothing was
discarded.

---

## Recommendation: **ADAPT**

Not ADOPT, not BLOCK.

**Why not BLOCK.** The thing that could have killed the design didn't. F-07 is
unambiguous: a pool-spawned session self-renames to its subject on claim, does
it on every re-claim, rotates cleanly across subjects, and provably does not
disturb `TARGET` or assignee. tk-h9pq5's §Q2 fallbacks can be dropped. The
batching decision in the sweep is vindicated by real numbers (F-16): 66 idle
beads cost one conversation, and the census it produced is better than what a
human would have written. The `gc.attention` removal is clean on the board
(F-23). The close contract mostly holds (F-09) and the record-stewardship
summary-block behaviour works on a 26KB notes field. This is a working spine.

**Why not ADOPT.** Three findings each independently prevent a visit from
reaching a session, and all three are silent:

1. **F-05** — the runbook's own first command files an unroutable visit. Every
   new adopter hits this before anything else works.
2. **F-06** — a visit on a blocked/arrested subject is never claimable. This
   removes conversation from exactly the beads that most need it, and
   `gc-helm.sh open` reports success while doing it.
3. **F-20** — both new formulas' roots are not Ready-visible, so the 6h/24h
   orders may not wake a cold polecat pool. The machinery works today because
   `gc start` warmed the pool; that is not the steady state.

Plus one host-level blocker (**F-21**, the board does not run on macOS at all)
and one correctness leak (**F-03**, two agents silently rendering a 16-line
stub) that adopting this pack exposes.

**What I would sequence first**, if it helps: F-05 and F-21 are one-line and
near-one-line fixes that unblock the whole runbook for the next person. F-06 and
F-20 are the two that need a design call from the author — F-06 because the fix
touches the canonical `gate-visit` snippet in three copies plus `gc-helm.sh`,
and F-20 because it may be a formula-shape change (`phase="vapor"` / formulas
v2) rather than a wiring change. F-11 (two sessions, one group) and F-14
(converse commits into the rig root) are real but degraded gracefully in this
run; they are the ones I would want fixed before an unattended overnight.

Per instruction, **no deviation was fixed.** The only changes made were to the
city's own `city.toml` (F-29) and a throwaway `timeout` shim on `PATH` outside
the repo. The probe beads (`PROBE-A`…`PROBE-G`, ids `tk-ly61i`, `tk-ub2mq`,
`tk-p1s72`, `tk-v21nd`, `tk-wcn2x`, `tk-lgxlg`) and the smoke visit `tk-rvdb0`
are left in the tk store as evidence; `tk-rvdb0` and `tk-v21nd` are the two that
will sit open forever until F-06 is resolved.
