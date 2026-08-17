---
name: Why mol-polecat-work never finalizes
description: Root-cause determination for the workflow-finalize husks that regrow ~1 per completed polecat workflow — which of the two candidate causes it is, why the naive port of the known fix would be a silent no-op, and which repository each half of the real fix has to land in.
---

# Why mol-polecat-work never finalizes

Root-cause record for bead tk-y389z. The bead posed a binary question and
deferred the answer to a work session:

> Code cause: confirm whether this is the tk-qnsqhv race or a step-close
> regression (footgun #2, PR#169 was the fix); if a regression, that is the
> real bug.

This document answers it, states the evidence, and locates the fix. It does
not contain the fix: every file that has to change belongs to a repository
this rig does not own. Section 6 says which, and section 5 records the trap
that makes the obvious patch fail silently.

## 1. The verdict

**It is footgun #2 — a step that never closes its own bead. It is not the
tk-qnsqhv double-dispatch race, and it is not a regression of PR#169.**

`mol-polecat-work` and the `mol-polecat-base` it extends contain **no step-close
instruction of any kind**, in any step, on any exit path. They never have. A
graph.v2 step advances by *closing* its bead, so the entire chain —
`load-context` → `workspace-setup` → `preflight-tests` → `implement` →
`self-review` → `submit-and-exit` — stays open for the life of the city. The
synthesized `workflow-finalize` control bead `blocks`-depends on
`submit-and-exit`, so it is never ready, and the control-dispatcher correctly
skips it forever. One husk chain per completed workflow, exactly as reported.

Nothing regressed. PR#169 fixed a *different set of formulas*, and the ones in
front of us were never in its scope.

## 2. The formulas close nothing

Two files compile into the six agent-executed steps:

| Step | Defined in | Repo |
|---|---|---|
| `load-context` | `core/formulas/mol-polecat-base.toml` | gascity |
| `workspace-setup` | `gastown/formulas/mol-polecat-work.toml` (override) | gascity-packs |
| `preflight-tests` | `mol-polecat-base.toml` | gascity |
| `implement` | `mol-polecat-base.toml` | gascity |
| `self-review` | `mol-polecat-work.toml` (override) | gascity-packs |
| `submit-and-exit` | `mol-polecat-work.toml` | gascity-packs |

`workflow-finalize` appears in neither file — the graph.v2 compiler synthesizes
it and routes it to the control dispatcher.

Grepped across both files for every spelling of a close:

- `bd close` — **no matches.**
- `--status=closed` / `--status closed` as a *write* — **no matches.**
  `mol-polecat-work.toml:20` matches on prose that *forbids* closing
  ("**NEVER CLOSE BEADS.**"); `mol-polecat-base.toml:301` matches a
  `--status closed` **query** filter inside a duplicate-search. Neither is a
  close.
- `step-close.sh` — **no matches.**
- `gc.outcome` — **no matches.**
- `hook --claim` — **no matches** (no per-step re-claim loop; the steps run
  inline in one session under `gc.session_affinity=require`).
- `drain-ack` — **10 sites** in `mol-polecat-work.toml`, **1** in
  `mol-polecat-base.toml`. Every terminating path drains without closing.

That is the whole defect. The formula's blanket "NEVER CLOSE BEADS" rule is
correct and load-bearing for the **work** bead — under close-on-land only the
refinery closes it after a verified merge — but it is written broadly enough to
swallow the graph.v2 **step**-close contract, which is a different obligation on
a different class of bead. One rule, stated at the wrong altitude, suppresses
the other.

## 3. What the machinery actually requires

The sibling formula in the same builtin pack states the contract plainly. Its
terminal step is titled *"Close drain step and signal completion"*:

```bash
if [ -n "${GC_BEAD_ID:-}" ]; then
  gc bd update "$GC_BEAD_ID" --set-metadata gc.outcome=pass --status=closed --notes "Drain acknowledged."
fi
gc runtime drain-ack
```

`mol-polecat-work.submit-and-exit` performs the second line and not the first.

The failure this produces was already written down, verbatim, in gc-toolkit's
own history — the PR#169 commit message (`7d53fe4`):

> A graph.v2 step advances by CLOSING its bead; a drain-acking session that
> still owns an open assigned step bead is parked and re-pooled, so a fresh
> worker re-wakes on the entry step forever and the kind=workflow root never
> reaches workflow-finalize.

That is a description of the present bug, written two months before this bead
was filed, about different formulas.

## 4. Ruling out the two rival explanations

### Not the tk-qnsqhv race

tk-qnsqhv is the double-dispatch race: the reconciler re-pools a bead whose
worker is still alive. Its predictions and the observations diverge on every
axis that distinguishes them:

| | race predicts | observed |
|---|---|---|
| Incidence | sporadic — only when a re-pool lands mid-flight | every workflow, including the one that produced this document |
| Steps left open | the one step that was in flight | **all six**, from `load-context` down |
| Mechanism needed | a concurrent second claimant | none — a single uncontended session leaks the whole chain |

A sampled husk chain (root `tk-bydo5`), walked from its finalize bead back
along the `blocks` edges, has all six steps `open` with `closed_at` unset. No
re-pool race leaves a chain in that shape; only "nothing ever closes anything"
does.

### Not a PR#169 regression

PR#169 (`7d53fe4`, gc-toolkit) made the **doc-keeper** audit formulas
graph-native — `mol-doc-keeper-memory-audit` and `mol-doc-keeper-drift-audit`,
both gc-toolkit-owned files. `mol-polecat-work` is an upstream pack formula and
was not touched by it, before or since. There is no earlier state in which
these steps closed, so nothing regressed; the fix simply never reached here.

## 5. The trap: the obvious patch is a silent no-op

Anyone fixing this will reach for the idiom PR#169 used and the one
`mol-do-work.drain` still uses. **On `mol-polecat-work` it does nothing at
all**, for two independent reasons.

**`GC_BEAD_ID` is unset in a pool-polecat session.** Verified directly from the
environment of the session that wrote this document — a pool polecat executing
`mol-polecat-work`. The variable is a control-dispatcher per-step facility;
pool-routed workers do not get it. The guard `[ -n "${GC_BEAD_ID:-}" ] && …`
therefore short-circuits: nothing is written, nothing is logged, exit status 0.
It fails *closed* and invisibly.

**`GC_TRIGGER_BEAD_ID` is not a substitute.** It is fixed when the session is
spawned and is not refreshed by `gc hook --claim`. In this session it held
`tk-8kp7k` — the `load-context` step — for the whole run. Because
`mol-polecat-work` executes all six steps inline in one session, that value
names the *first* step and never the one currently executing. Closing on it
fails *open*: it either re-closes an already-closed step (silent no-op) or, when
the session was spawned on another molecule's bead, closes a live step belonging
to someone else. gc-toolkit's `doctor/check-step-close-owns-bead` exists to
reject exactly this idiom, and documents an observed cross-molecule corruption.

**The correct resolution is by identity, not by environment.** A step bead is
named uniquely by the pair (`assignee`, `metadata."gc.step_ref"`), which cannot
go stale across a claim. gc-toolkit already ships the helper that does this —
`assets/scripts/step-close.sh --step <formula>.<step-id> --outcome pass` — and
uses it at 26 invocation sites across its four graph.v2 formulas. Whatever lands
upstream needs the same resolution strategy, not the same source line.

One further constraint: a step bead a session owns is usually `status=open`, not
`in_progress`. Only the *first* step arrives through the pool tier, where the
claim assigns the bead and flips it to `in_progress`; the rest are pre-assigned
up front under `gc.session_affinity=require` and claim as `ready_assignment`,
which flips no status. Confirmed live in the session that wrote this document:
its `load-context` bead was `in_progress`, while `workspace-setup` and
`submit-and-exit` sat at `open` already carrying its assignee. A close path that
filters on `in_progress` will miss every step but the first — including the only
one that matters here.

## 6. Where the fix has to land

The two files were split across repositories by gascity `5a23df317`
("Consume the gastown pack as a Go module dependency (drop vendored copy)").

| File | Repository | Rig in this city? |
|---|---|---|
| `internal/bootstrap/packs/core/formulas/mol-polecat-base.toml` | `gastownhall/gascity` | **yes** — `gascity`, prefix `gc` |
| `gastown/formulas/mol-polecat-work.toml` | `gastownhall/gascity-packs` (Go module dep, pinned `v0.3.1-0.20260617013242-33d3a430a67d`) | **no** |

Three of the six leaking steps (`load-context`, `preflight-tests`, `implement`)
are gascity's and can be fixed in a rig that exists here. The other three —
including the terminal `submit-and-exit`, the one the finalize bead actually
blocks on — are in `gascity-packs`, which has no rig in this city; that change
also needs a module bump in gascity to take effect.

Because the chain is linear, **fixing only the gascity half changes nothing
observable**: `submit-and-exit` would still hold the chain open. The
gascity-packs half is the one that unblocks finalize.

## 7. What gc-toolkit can and cannot do about it

gc-toolkit has already taken this as far as it goes locally, and the existing
choices are deliberate rather than gaps to be filled:

- **`assets/scripts/quiesce-completed-workflows.sh` contains the containment,
  and refuses the cure on purpose.** It clears `gc.routed_to` and the assignee
  so dead steps stop being re-offered, and its header states the boundary
  explicitly: *"There is deliberately no close path in this script … Finalizing
  the step graph at submit-and-exit time is the durable upstream fix (gascity
  core / gastown formula) and is deliberately out of scope here."* The reasoning
  is sound and should not be reopened casually: closing `load-context` unblocks
  `workspace-setup` and walks the next polecat forward onto a branch that is
  already green-gated and PR'd, where any push moves the head, stales the
  anchor's `check.<gate>=green@<oid>` marker, and blocks the open PR from
  merging.
- **`assets/scripts/detect-stalled-workflows.sh` is a detector with no repair
  arm** — it only reads.
- **`doctor/check-step-close-owns-bead` catches the wrong-close defect, not this
  one.** It asserts that no pack file closes a bead on an id read from the
  environment. A formula with *no* close at all passes it cleanly. The
  complementary assertion — that every graph.v2 formula has a close path — would
  catch this class, but as specified it would fire permanently on upstream
  formulas gc-toolkit cannot patch; that trade-off is a design decision, not a
  detail, and is left open here rather than settled.

Consequence: the husks are cleared by hand. That clearing is worth being able to
recognise, because a swept chain and a healthy one are indistinguishable
afterwards — both end up fully closed with a finalize carrying
`gc.outcome=pass`, so a spot check of closed workflows reads as "the machinery
works."

The tell is **elapsed time**. A sweep closes the steps in dependency order,
`load-context` first, each close unblocking the next, 5–11 seconds apart — the
whole six-step chain inside about half a minute. Root `tk-9fqq7` closed
`load-context` at 18:07:25Z and `submit-and-exit` at 18:07:57Z on 2026-08-17:
thirty-two seconds to traverse `implement` and `self-review`, which is not a
polecat doing the work. A neighbouring `mol-scoped-work` chain (`tk-ylpgo`) was
swept in the same window on the same cadence.

A secondary tell: `gc.outcome` is **unset** on every swept step. The documented
close idiom stamps `gc.outcome=pass` as it goes, so a formula-driven close
leaves it set; only the dispatcher's finalize carries it here.

## 8. State at the time of writing

2026-08-17, gc-toolkit: **19 open `workflow-finalize` beads**, created between
2026-08-09 and 2026-08-17 — the backlog the bead reports as cleared has fully
regrown, and the count includes `tk-uy24z`, the finalize bead of the very
workflow that produced this document. It will still be open when this lands.

The bug is contained, not fixed: quiescing means no polecat spin and no wisp
burn, so the cost is a slowly growing population of stranded molecules and the
manual sweeps that keep it bounded.

## 9. Follow-up this record does not perform

Two changes are needed and neither is landable from a gc-toolkit polecat branch;
they are named here so routing them is a decision someone makes on purpose:

1. `gastownhall/gascity-packs` — `mol-polecat-work.toml`: close
   `workspace-setup`, `self-review`, and `submit-and-exit` by resolved identity
   per section 5, then bump the module pin in `gastownhall/gascity`. This is the
   one that unblocks finalize.
2. `gastownhall/gascity` — `mol-polecat-base.toml`: same treatment for
   `load-context`, `preflight-tests`, and `implement`. A rig for this exists in
   the city.

Both must also reconcile the "NEVER CLOSE BEADS" prose with the step-close
contract, or the next reader will correctly follow the rule and reintroduce the
defect — the work bead stays untouchable, the step bead must close.
