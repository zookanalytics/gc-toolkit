---
name: Refinery cycle-recycle missed-MERGE_READY diagnostic
description: Root-cause analysis of the v4 mol-refinery-patrol cycle-recycle gap that leaves work beads routed to the refinery sitting open across `/clear` rotations; comparison to gastown v3 and to the deacon startup-adopt advice; fix options ranked with placement recommendation.
---

# Refinery cycle-recycle missed-MERGE_READY diagnostic (tk-fyzvk)

Read-only diagnostic for the bug filed in `tk-fyzvk`. The deliverable
is this document; implementation is out of scope and lives in a
follow-up bead.

## Provenance

| Doc-type or artifact | Producer | Source location (path + commit SHA) | Surveyed at |
|---|---|---|---|
| gc-toolkit refinery formula (v4) | gc-toolkit pack | `rigs/gc-toolkit/formulas/mol-refinery-patrol.toml` @ `6888c41` | 2026-05-08 |
| gc-toolkit refinery prompt | gc-toolkit pack | `rigs/gc-toolkit/agents/refinery/prompt.template.md` @ `6888c41` | 2026-05-08 |
| gastown refinery formula (v3) | gascity examples/gastown pack | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-refinery-patrol.toml` @ `cddc5b96` | 2026-05-08 |
| gastown refinery prompt (v3) | gascity examples/gastown pack | `rigs/gascity/examples/gastown/packs/gastown/agents/refinery/prompt.template.md` @ `67de5b41` | 2026-05-08 |
| gc-toolkit deacon formula | gc-toolkit pack | `rigs/gc-toolkit/formulas/mol-deacon-patrol.toml` @ `2a3cb43a` | 2026-05-08 |
| gc-toolkit deacon prompt | gc-toolkit pack | `rigs/gc-toolkit/agents/deacon/prompt.template.md` @ `8412dca8` | 2026-05-08 |
| gastown deacon formula / prompt | gascity examples/gastown pack | `rigs/gascity/examples/gastown/packs/gastown/{formulas/mol-deacon-patrol.toml,agents/deacon/prompt.template.md}` @ `429427df` | 2026-05-08 |
| cycle-recycle template fragment | gc-toolkit pack | `rigs/gc-toolkit/template-fragments/cycle-recycle.template.md` @ `8412dca8` | 2026-05-08 |
| propulsion template fragment | gc-toolkit pack | `rigs/gc-toolkit/template-fragments/propulsion.template.md` @ `8412dca8` | 2026-05-08 |
| Deacon startup-adopt advice (auto-memory) | overseer (zook) memory | `~/.claude/projects/-home-zook-loomington/memory/feedback_deacon_pickup_open_wisps.md` (not in git) | 2026-05-08 |
| Observed instances | live bd ledger | `tk-mpnnc`, `tk-i1t2u` (gc-toolkit), `gc-8zdml1` (gascity) | 2026-05-08 |
| Live deployed gascity refinery formula | gascity rig | `rigs/gascity/.beads/formulas/mol-refinery-patrol.toml` (v4 — same as gc-toolkit, not v3) | 2026-05-08 |

Note on gascity versions: the **upstream example pack** under
`rigs/gascity/examples/gastown/packs/gastown/` is **v3** and has not
adopted the cycle-recycle policy. The **live gascity rig** under
`rigs/gascity/.beads/formulas/` runs **v4** (vendored from gc-toolkit),
so the bug reproduces there too — that is what the `gc-8zdml1`
instance shows.

## 1. Cycle-recycle exit path and new-session startup path

### 1.1 The v4 cycle-recycle exit path

`mol-refinery-patrol.toml` v4, step `check-inbox`, lines 80–112:

```text
**1. Cycle-recycle check (FIRST — before any work):**

Apply the cycle-recycle policy. Recycle if either trigger has fired:

- You have **closed 3+ patrol wisps** in this session.
- You have done **4+ consecutive empty `gc events --watch` waits**
  (~30 min idle).

To recycle:
    gc handoff "context cycle: <reason>"

Then sit idle and surface the handoff message — the operator will
`/clear` and the next session resumes from the HANDOFF bead.
```

`template-fragments/cycle-recycle.template.md` lines 24–48 (the
authoritative policy doc) confirms: after `gc handoff`, the agent
**sits idle**, **does not start the next cycle**, and **waits for
`/clear`**. No fresh wisp is poured. The current wisp stays
`status=in_progress`.

This deviates from the formula's normal exit pattern. Every other
exit path (rebase failure step, handle-failures step, merge-push's
`block_existing_pr`, next-iteration's success path) follows
"**pour next iteration BEFORE burning current**" — see the explicit
comment block at `mol-refinery-patrol.toml:185-189, 257-261, 320-321,
663-664`. Cycle-recycle is the **only exit path that breaks this
invariant**. It leaves a wisp in_progress with no successor poured.

### 1.2 The new-session startup path

After the operator `/clear`s, the new session reads the refinery
prompt. The startup block at `agents/refinery/prompt.template.md:50-58`:

```bash
# Check for an in-progress patrol wisp
gc bd list --assignee="$GC_ALIAS" --status=in_progress

# If none found, pour one (root-only — no child step beads) and assign it
WISP=$(gc bd mol wisp mol-refinery-patrol --root-only ...)
gc bd update "$WISP" --assignee="$GC_ALIAS"
```

The fragment in the propulsion template (`propulsion.template.md:181-205`,
`define "propulsion-refinery"`) reinforces this:

```text
**Your startup behavior:**
1. Check for an in-progress patrol wisp
2. If found -> Resume where you left off (read formula steps, determine current position)
3. If none -> Pour a new wisp and assign it to yourself
```

**Two structural gaps** appear in the new-session path:

**Gap A — startup query is `--status=in_progress` only.** It does not
check `--status=open`. If the previous wisp's status was flipped to
open or it was burned (any race or partial recovery), the query
returns nothing, the agent pours a fresh wisp, and the previous
wisp's pending state is lost. **Routed work beads are never
explicitly queried at startup** — the prompt assumes the wisp is the
sole source-of-truth for "is there work."

**Gap B — resume semantics are loose.** When the in_progress wisp IS
found, the prompt says only "Resume where you left off (read formula
steps, determine current position)." After `/clear`, the agent's
context is empty. There is no recorded position; the agent has to
infer from git/bead state. Without an explicit "start from check-
inbox" instruction, behavior is LLM-dependent and the failure mode
the bead reports — **agent goes idle at the prompt** — is what
happens when the inference path breaks down.

### 1.3 Where the routed work beads sit

A polecat's done-sequence reassigns the work bead like this (per
`CLAUDE.md` guidance, identical to `mol-polecat-work.toml:194-209`):

```bash
REFINERY_TARGET="${GC_RIG:+$GC_RIG/}{{binding_prefix}}refinery"
gc bd update {{issue}} --status=open --assignee="$REFINERY_TARGET" \
  --set-metadata gc.routed_to="$REFINERY_TARGET"
```

So the routed bead has `status=open`, `assignee=<rig>/<binding>refinery`,
`metadata.gc.routed_to=<rig>/<binding>refinery`, plus
`metadata.branch` and `metadata.target`.

The formula's `find-work` step (lines 122–144) uses:

```bash
WORK=$(gc bd list --assignee=$GC_AGENT --status=open \
  --exclude-type=epic --limit=1 --json | jq -r '.[0].id // empty')
```

If find-work runs, it **does** match the routed bead. The gap is not
in find-work itself — it is that **the formula doesn't run** because
the agent doesn't move past startup after `/clear`. Empirical
evidence supports this: the observed instances sit untouched until a
manual `gc session nudge`, which simply wakes the agent enough to
re-enter the formula loop.

**Bonus subtlety in find-work.** `--exclude-type=epic` does not
exclude `molecule`. Patrol wisps are `issue_type=molecule`
(verified live: `tk-wisp-fqws.issue_type == "molecule"`). If a wisp
is currently assigned to the same alias as the work bead, the query
could in principle return the wisp before the work bead, depending on
sort order. The formula then fails the
`metadata.branch` requirement and stalls. This is a
pre-existing gap (also present in v3), but it intersects with the
v4 cycle-recycle gap because cycle-recycle leaves a wisp
in_progress and the same agent's next find-work query may collide
with it.

### 1.4 The exact answer to the bead's question

> Identify whether startup queries for `routed_to=<self> AND status=OPEN`
> before pouring a fresh wisp.

**No.** Neither the prompt's startup block nor the propulsion-refinery
template fragment queries for `gc.routed_to=<self> AND status=open`.
The startup queries only `--status=in_progress` against `$GC_ALIAS`.
Routed work beads are reachable only via `find-work` inside the
formula, and `find-work` only runs if the agent enters the formula
loop after startup.

## 2. Comparison to gastown v3

### 2.1 What v3 does instead

`examples/gastown/packs/gastown/formulas/mol-refinery-patrol.toml` v3
(@`cddc5b96`), step `check-inbox`, lines 76–103:

```text
**1. Context check (FIRST — before any work):**
    RSS=$(ps -o rss= -p $$ | tr -d ' ')
    RSS_MB=$((RSS / 1024))

If RSS > 1500 MB or context feels heavy, request a restart:
    gc runtime request-restart

This sets `GC_RESTART_REQUESTED` metadata on the session and blocks
forever. The controller will kill and restart the session on the next
reconcile tick. The current wisp stays assigned and the new session
... re-reads formula steps and resumes from context.
```

v3 uses `gc runtime request-restart`, which is a **controller-mediated
restart**. The controller kills the process and respawns it. There is
no operator `/clear` step. The wisp stays in_progress; the new
controller-spawned session inherits the same alias, runs the prompt's
startup query, finds the in_progress wisp, and resumes.

### 2.2 Why v3 doesn't trip on this gap

Three reasons:

1. **Restart is controller-driven**, not operator-driven. There is no
   indeterminate idle window between handoff and resume — the
   controller stops and starts the process under its own clock.
2. The wisp **continues being assigned to the same alias** through
   restart, so the in_progress query reliably finds it.
3. **No new wisp is poured during restart.** The same wisp resumes;
   the formula re-enters from the top step (check-inbox). No risk of
   wisp accumulation or alias mismatch.

The cycle-recycle template fragment explicitly calls this out at
lines 80–86: "`request-restart` silently no-ops for on-demand named
sessions because the controller cannot restart user-attended
processes. `gc handoff` always writes a HANDOFF bead, so the next
session has clean resume state regardless of whether a controller
restart, an operator `/clear`, or a PreCompact hook restarted it."

But the policy *added* a new failure mode that v3's RSS-trigger path
did not have: **the operator-`/clear` window**. During that window,
on-demand named sessions are idle by design but their startup
contract is not strong enough to handle a fresh-from-`/clear` resume.

### 2.3 So is v3 affected?

The gastown v3 example pack is **not affected** by the cycle-recycle
gap because cycle-recycle does not exist in v3. v3 has the same
"startup-only-checks-in_progress" prompt and the same find-work
query, so it would have an analogous gap *if* it added cycle-recycle
or an operator-driven restart path — but in its current shipped form,
v3's only context-management trigger is `gc runtime request-restart`,
which is controller-driven.

The **live gascity rig** runs v4 (per
`rigs/gascity/.beads/formulas/mol-refinery-patrol.toml`, version=4),
so it inherits the gap. `gc-8zdml1` is a confirmed instance.

## 3. Comparison to deacon's startup-adopt fix

### 3.1 What was actually done vs. what the memory said

The bead's hypothesis cites `feedback_deacon_pickup_open_wisps.md`
(2026-05-07, originSessionId `088cdeec…`) which **proposed** a
startup-adopt fix:

> At deacon startup, after the `--status=in_progress` check, also run
> `gc bd list --assignee=$GC_ALIAS --status=open`. If any patrol
> wisps already exist, adopt the most recent one as the current cycle
> and close the older ones with a "orphaned cross-rotation" reason.
> Only create a fresh wisp if none exist.

**Verification (this diagnostic, 2026-05-08):** that advice was **not
applied to the deacon prompt**. Both
`rigs/gc-toolkit/agents/deacon/prompt.template.md` (@`8412dca8`) and
`rigs/gascity/examples/gastown/packs/gastown/agents/deacon/prompt.template.md`
(@`429427df`) still only check `--status=in_progress` at startup
(lines 60–72 in both):

```bash
# Step 1: Check for assigned work
gc bd list --assignee="$GC_ALIAS" --status=in_progress

# Step 2: Nothing? Check mail for attached work
gc mail inbox

# Step 3: Still nothing? Create patrol wisp (root-only — no child step beads)
NEW_WISP=$(gc bd mol wisp mol-deacon-patrol --root-only ...)
gc bd update "$NEW_WISP" --assignee="$GC_ALIAS"
```

The memory remains an open recommendation, not an applied fix.

### 3.2 Why the analogy still holds

The shape of the gap is the same:

- **Deacon (per memory):** patrol wisps stay status=open through
  their cycle (assignee-only update, no status flip). Startup query
  for in_progress always returns empty. New session creates a fresh
  wisp; prior-rotation wisps orphan. The fix is to also check
  status=open and adopt newest.

- **Refinery (this bead):** routed *work beads* arrive with
  status=open, assignee=refinery during the cycle-recycle window.
  Startup query for in_progress doesn't surface them. The fix shape
  is the same — **also check status=open, with the right assignee
  filter** — but the *contents* differ: for the deacon the missing
  items are patrol wisps, for the refinery they are routed work
  beads.

There is also a finer-grained refinery-specific shape: the
**previous wisp** itself may be the missing item (in_progress at the
moment of `gc handoff`, but if the agent then idles for a long time
or anything flips its state, the in_progress check misses it). So a
robust startup-adopt for the refinery has to handle **both**
"adopt prior wisp" and "discover routed work bead."

### 3.3 Differences from the deacon case worth flagging

- The deacon memory's observed mechanism was *wisp lifecycle*
  (assignment doesn't transition to in_progress for the deacon,
  per the 2026-05-07 observation). Live data this session shows the
  refinery's wisp `tk-wisp-fqws` *is* in_progress (created
  06:28:35Z, started 06:28:36Z). So the wisp-status mechanism may
  differ between agent types — the refinery's gap is **less about
  wisp lifecycle and more about the cycle-recycle exit path leaving
  state in a place the startup query doesn't look**.
- For the deacon, fix targets are wisps. For the refinery, fix
  targets are **work beads with `metadata.branch`** (routed via
  `gc.routed_to`). The startup-adopt logic must distinguish these
  and route them to the right code paths (resume the wisp;
  process the work bead via the formula).

## 4. Fix options

### Option A — Startup-adopt step in the refinery prompt

Add a discovery step after the in_progress check, before pouring a
fresh wisp:

```bash
# 1. In-progress wisp (existing check)
gc bd list --assignee="$GC_ALIAS" --status=in_progress

# 2. NEW: Routed work beads with branch metadata
gc bd list --assignee="$GC_ALIAS" --status=open \
  --has-metadata-key=branch --exclude-type=epic --json
# If non-empty, enter the formula at find-work directly.

# 3. NEW: Open patrol wisps (cross-rotation orphans / stuck recycle)
gc bd list --assignee="$GC_ALIAS" --status=open --type=molecule \
  --include-infra --json
# If exactly one and it's mol-refinery-patrol: adopt it as the cycle wisp.
# If more than one: adopt newest, burn olders with "orphaned cross-rotation" reason.

# 4. Only if all three return empty: pour a fresh wisp.
```

**Tradeoffs:**
- **(+)** Direct fix for the observed failure mode. Mirrors the deacon
  memory's recommended pattern, expanded to cover work beads as well
  as wisps.
- **(+)** Symmetric with the polecat startup hook (which already does
  multi-stage discovery: in_progress assigned → bd ready assigned →
  routed pool). Brings the refinery's startup contract up to the same
  thoroughness.
- **(+)** Localized change — prompt + propulsion fragment, no formula
  change.
- **(–)** Mixes prompt-level discovery with formula-level execution.
  Risks divergence if the formula's find-work query later changes its
  filter set.
- **(–)** "Adopt newest, burn older" needs careful semantics so it
  doesn't burn a wisp another session is still actively using. The
  deacon memory's wording ("close with orphaned cross-rotation
  reason") is fine for the deacon but for the refinery we'd want the
  burn to be conditional on age and on no observed activity.

### Option B — Pour next wisp in the cycle-recycle path

Modify the cycle-recycle policy in `template-fragments/cycle-recycle.template.md`
(or in each formula's check-inbox step) so the agent **pours next
iteration before idling**, conforming to the formula's "always pour
next before burning" invariant. After `gc handoff`, the new wisp is
already there with `status=in_progress` (or open + assigned)
waiting for the next session.

**Tradeoffs:**
- **(+)** Restores the structural invariant the rest of the formula
  already obeys. Smallest change to the prompt.
- **(+)** No new prompt logic — the existing
  `gc bd list --assignee --status=in_progress` query starts working
  again because there's a fresh wisp to find.
- **(–)** The cycle-recycle template's wording is "Sit idle. Do not
  start the next cycle." Pouring a fresh wisp before idling is a
  cosmetic violation of that rule (the wisp exists but the agent
  isn't running it yet). Needs a clarifying note.
- **(–)** Doesn't address the bead's underlying observation about
  routed *work beads* sitting unprocessed during the operator-`/clear`
  window. A work bead routed *after* the next-wisp pour and *before*
  `/clear` would still depend on find-work catching it — which it
  does, but only once the agent enters the formula loop. So this fix
  is necessary-but-possibly-not-sufficient.
- **(–)** If the trigger fires repeatedly (rare but possible —
  pathological event-watch loop), each cycle adds a new wisp; the
  next-iteration step only burns a wisp it knows about, so orphans
  could accumulate. Mitigation: emit the new wisp ID in the handoff
  message so the next session knows what to inherit.

### Option C — Make the cycle-recycle handoff carry the routed-bead snapshot

In the cycle-recycle template, before `gc handoff`, enumerate
currently-routed work beads and include them in the handoff message:

```bash
ROUTED=$(gc bd list --assignee="$GC_ALIAS" --status=open \
  --has-metadata-key=branch --exclude-type=epic --json \
  | jq -r '.[].id' | tr '\n' ' ')
gc handoff "context cycle: <reason>; queued=[$ROUTED]"
```

The new session reads the handoff mail bead, sees the queued IDs, and
processes them.

**Tradeoffs:**
- **(+)** Self-documenting. The handoff mail tells operators and the
  next session exactly what's queued at the moment of recycle.
- **(–)** Snapshot is stale immediately. Beads routed *after* handoff
  (before the operator `/clear`s) are not in the snapshot. The
  observed `gc-8zdml1` instance arrived in this gap — fix doesn't
  cover it.
- **(–)** Creates a parallel discovery channel (mail body parsing) on
  top of the existing find-work query. The right answer is to fix
  discovery, not paper over it.
- **(–)** Most expensive option in terms of prompt complexity for the
  smallest amount of coverage.

### Recommendation

**Option A is primary; pair with Option B for defense-in-depth.**

A is the focused fix for the discovery gap and aligns with the
memory's deacon advice. B costs nothing extra and keeps the formula's
"always pour next" invariant intact, so a future session that misses
the in_progress wisp for any reason still has something to land on.

Option C is **not recommended** as a standalone fix — it's an
attractive nuisance that papers over the root cause without
eliminating the gap.

A polecat's hook
(`sh -c 'for id ...; r=$(bd ready --metadata-field gc.routed_to=... --unassigned ...)'`,
documented in `rigs/gc-toolkit/agents/polecat/prompt.template.md`'s
startup block — re-rendered into this session's CLAUDE.md context) is a
reasonable design pattern to draw from when implementing A. The
refinery's analog is "assigned and routed," not "unassigned routed
pool," so the queries differ, but the *layered-fallback* shape is the
same.

## 5. Upstream-vs-local placement

### 5.1 Where the cycle-recycle policy actually lives

- **gc-toolkit pack** (`rigs/gc-toolkit/`): cycle-recycle is **here
  in v4**. Bumped from v3 to v4 in commit `6888c41` (the file's
  current HEAD); the cycle-recycle template fragment was added in
  the gc-toolkit pack at commit `8412dca8`.
- **gascity examples/gastown pack**
  (`rigs/gascity/examples/gastown/packs/gastown/`): still on **v3**
  (`cddc5b96`). Has not adopted cycle-recycle. Uses the RSS-based
  `gc runtime request-restart` path.
- **gascity live rig** (`rigs/gascity/.beads/formulas/...`): runs
  **v4** (vendored from gc-toolkit). Affected by the gap.

### 5.2 Per the upstream-engagement framework

Two principles to apply:

1. **Fix at the source-of-truth for the affected version.** v4 is
   owned by gc-toolkit. The fix lands there.
2. **Don't backport a fix for a feature that hasn't been adopted.**
   gastown's example pack hasn't adopted cycle-recycle and doesn't
   need the fix in its current shipped form.

### 5.3 Recommendation

- **Primary fix: gc-toolkit only.** Land Option A in
  `rigs/gc-toolkit/agents/refinery/prompt.template.md` and the
  shared `rigs/gc-toolkit/template-fragments/propulsion.template.md`
  (the `propulsion-refinery` define block). If Option B is also
  chosen, edit `rigs/gc-toolkit/template-fragments/cycle-recycle.template.md`
  and the formula's check-inbox step.

- **Live gascity rig:** automatically inherits the fix the next time
  it re-vendors from gc-toolkit. No separate gascity PR needed if
  re-vendoring is the standard path. If the live gascity rig is
  hand-edited rather than vendored, file a follow-up to sync.

- **gascity example pack (v3):** **no upstream PR**. The pack is on
  v3 and does not have the cycle-recycle policy that introduces the
  gap. If/when the pack adopts cycle-recycle (bumps to v4), the fix
  should land alongside the version bump in the same PR — not as a
  separate retro-fit.

- **Regression note for whoever does the gastown→v4 sync later:**
  the cycle-recycle policy change is not safe to ship without
  Option A (or equivalent). Add a checklist item to the sync
  reviewer's notes.

## Out of scope (per bead description)

- **Implementation.** A follow-up implementation bead should be
  filed off this diagnostic.
- **New tests.** The implementation bead can add them.
- **Validating wisp-lifecycle behavior end-to-end** (i.e., does
  `gc bd update --assignee` ever flip status to in_progress on its
  own, or only via `--claim`?). The diagnostic uses the live
  `tk-wisp-fqws` evidence as a sufficient signal that current
  refinery wisps reach in_progress; the precise mechanism is a
  separate question and not load-bearing for this fix.
