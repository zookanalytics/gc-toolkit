---
name: Retiring reconcile-refinery-handoffs.sh — what actually covered its residue (2026-08-23)
description: Execution record for consolidation-plan Target 3. The plan named two existing checks as covering the retired pass's set; both provably exclude it, so the downgrade was implemented as one operator in refinery-reconcile.sh's fresh-handoff detector. Read this before assuming a named detector covers a set you are about to delete the owner of.
---

# Retiring `reconcile-refinery-handoffs.sh`

Executes Target 3 of `specs/tk-z9nln/consolidation-plan.md`. Removes 955
lines of code and adds 62 (this record aside).

## The precondition held

The plan's void condition was that the repair arm must not have fired since
the formula fix. Re-measured 2026-08-23 across every `refinery-reconcile`
pass log on all four rigs:

| rig | passes | passes with a non-zero result |
|---|---|---|
| gascity | 117 | 0 |
| gc-toolkit | 73 | 0 |
| shutupandlisten | 125 | 0 |
| signal-loom | 95 | 0 |

All 410 lines read `0 repaired, 0 reported (not rewritten), 0 failed`.

**The bead's reproduce command does not reproduce.** It globs `~/.gc`; the
logs are under `$GC_CITY/.gc` (`/home/zook/loomington/.gc`). As written it
returns nothing, and nothing is indistinguishable from "no pass ever fired" —
the same shape as the finding it was meant to confirm. Anyone re-checking
this should point the `find` at the town root and confirm the line count is
non-zero before reading the zeros as evidence.

## The plan's stated coverage was wrong

Target 3 says "do not simply drop the guard" and names two checks that
already cover the residue. Both were read; **neither can see this set.**

The set is: an OPEN bead, `metadata.branch` pushed, no `merge_result` and no
`pr_url`, whose assignee is a near-miss refinery address and whose
`gc.routed_to` is empty.

| Named check | What it enumerates | Why it misses this set |
|---|---|---|
| `doctor/check-routed-work-claimable` | `--status open --no-assignee --has-metadata-key gc.routed_to` | Excludes assigned beads *and* exactly-empty routes **by design** (its own lines 77–80: "an assignee is its own reachability"; "clearing the route is how the done sequence hands a bead to an assignee"). A near-miss handoff is both at once. |
| `check-set-heal.sh` non-canonical assignee arm | rows of GATING anchors — those carrying `pr`/`pr_url`/`merge_result` | A pre-PR handoff has none of the three, so it is not in that row set. The retired script's own header says so, and says why the split is deliberate (tk-wsxd0): on an anchor the assignee is a visibility wart because bead-keyed passes still land it; here the assignee is the *only* path by which the bead is ever processed. |

The `refinery-reconcile.sh` fresh-handoff detector — the one pass that
already enumerates exactly this shape — also missed it, because its filter
required `assignee == ""`.

So deleting the pass as filed would have restored the tk-0nn3f blind spot
for the residue the plan itself flags as still possible ("a hand-composed
assignee can still be wrong"), with nothing reporting it.

## What was done instead

The downgrade was implemented where detection already runs. The detector's
predicate was generalized from "nobody owns it" to **"nobody polls it"**:

```diff
-                 or (((.metadata["gc.routed_to"] // "") == "") and ((.assignee // "") == "")))
+                 or (((.metadata["gc.routed_to"] // "") == "") and ((.assignee // "") != $me)))
```

Two pollers exist — a pool offers on exact `gc.routed_to` equality, and the
refinery's find-work filters on exact `assignee == $me`. An unrouted bead
assigned to anything other than this refinery is therefore read by nobody,
and that set is a strict superset of the old one (`"" != $me` always holds).

Properties preserved: a bead routed to a pool is still excluded (a pool
polls it); a correctly-addressed handoff is still excluded (find-work polls
it); the origin-branch gate still keeps live WIP out; the per-id dedup file
still holds ids, so it survives the upgrade.

It **reports**, and does not repair. That is the same call `check-set-heal`
makes on its own set — an identity is a routing decision, and a wrong
automatic rewrite moves a live bead out from under whoever holds it. The
761-line pass existed to repair; the repair is what 410 passes proved
unnecessary. Detection is what remains cheap and still worth having.

## Removed

| Artifact | Lines |
|---|---|
| `assets/scripts/reconcile-refinery-handoffs.sh` | 420 |
| `assets/scripts/reconcile-refinery-handoffs.test.sh` | 341 |
| `doctor/check-refinery-handoff-reconcile/` (run.sh + doctor.toml) | 113 |
| `formulas/mol-witness-patrol.toml` — `check-refinery` Step 0 | 41 |
| `assets/scripts/refinery-reconcile.sh` — the `(a-addr)` arm | 8 |

The plan's table counts only the first two. The doctor check and the witness
arm are **owner-of-concern sites**: the check asserts the script "stays
shipped and wired" and fails `gc doctor` city-wide the moment it does not,
and the witness arm calls the script by path. Deleting the script without
them leaves the tree self-contradicting — a name sweep finds them, which is
why the sweep is by concept, not by the file being deleted.

## Knowledge relocated, not dropped

The tk-0nn3f incident rationale lived in the deleted script's header and in
the deleted doctor check. It now sits on the detector that owns the set, in
`refinery-reconcile.sh`, including the four-way blindness list and the 1h07m
live case. The witness's `check-refinery` "Empty queue" bullet — which read
"idle is fine *after Step 0 has run*" — now points at the cadence's
`FRESH HANDOFF` line instead of the deleted step.

Five dangling `as reconcile-refinery-handoffs.sh does` citations in
`reconcile-gate-verdicts.sh` and `recover-stranded-branches.sh` were
repointed at siblings that carry the same pattern (the rig pin, the
two-source roster fail-safe); one detector-table row naming the deleted pass
was removed.

## Verification

- `refinery-reconcile.test.sh` — 54 passed, 0 failed. Two new cases: (51) a
  near-miss-addressed bead IS reported; (52) a correctly-addressed handoff is
  not.
- **Mutation control**: reverting only `!= $me` to `== ""` fails (51) with
  `missing 'tk-nearmiss'` and nothing else — so the case tests the change and
  not the fixture.
- `recover-stranded-branches.test.sh` 116/0; `reconcile-gate-verdicts.test.sh`
  110/0; `doctor/check-refinery-merge-cadence/run.test.sh` 75/0.
- `shellcheck -S warning` clean on all four changed shell files;
  `mol-witness-patrol.toml` parses; `check-formula-shell-portability` OK.
- No doctor check asserts the pass count or the `(a-addr)` arm, so removing
  it breaks no other gate.

Remaining references to the deleted name are all under `specs/` — historical
bead-keyed records (tk-svgtz's cadence audit, tk-f69ay, and this plan), which
are preserved as written, not rewritten.
