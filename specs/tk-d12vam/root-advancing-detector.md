---
name: Detecting a workflow root stranded mid-flight
description: Why a graph.v2 molecule drained mid-execution strands past every recovery path, the four-part predicate that names it without reporting the inline-husk population, why the home is a read-only doctor check, and how it complements the leak-plug recovery fix.
---

# Detecting a workflow root stranded mid-flight

Design record for `doctor/check-root-advancing` (I13, bead tk-d12vam), the
fail-loud safety net for a strand the recovery fix (tk-gkb81g) plugs at the
source. Detection and surfacing only.

## 1. The strand, and why nothing else fires on it

A graph.v2 molecule runs its continuation-group steps INLINE in the single
owning pool session. Those step beads carry no owner and no route by
construction: an inline step is neither claimed through the pool nor routed to
one. Pool sessions recycle routinely, so a drain landing mid-molecule leaves the
forward steps open, unowned and unrouted, and the molecule advances no further —
its `workflow-finalize` waits forever under the control-dispatcher.

Nothing recovers it and nothing reports it:

- the witness's orphan recovery keys on an ASSIGNEE; an inline step has none;
- with no route, no pool is ever offered it;
- `doctor/check-step-terminal` (I8) is scoped to CLOSED roots; this root is
  in_progress;
- `doctor/check-claim-advancing` (I11) reports a CLAIMED step whose holder is
  gone, or an OPEN step that is ROUTED and offered; an unrouted, unowned step is
  in neither arm.

So the gap is real and structural. The recovery half — give inline steps a
route so a fresh worker is re-offered them — is tk-gkb81g. This detector is the
net that makes a strand visible within a witness cycle instead of after weeks,
and does not replace that fix.

## 2. What "stranded" means, and why each gate is load-bearing

A root is reported only when all four hold. Each gate is a distinct healthy
shape the detector must not report, and dropping any one reintroduces a false
positive that has cost real escalations:

- **SILENT** — the max `updated_at` over the root and every member, in any
  status, is past the bound (default 120m). A close is the molecule advancing
  and is routinely its most recent write, so the closed members are read too;
  dated by its open members alone, a molecule that just advanced reads as stalled.
- **UNHELD** — no live session stands behind it: neither the root's
  `gc.session_name` nor any member's assignee, `gc.session_id` or
  `gc.session_name` is in the running roster. The `session_name` is an affinity
  slot a restart reuses for the same molecule, so a live slot exempts — a
  molecule a pinned worker may resume is not stranded.
- **STARTED** — the graph has closed at least one step, AND its work has not
  landed. The closed-step half is what keeps this from reporting the whole rig:
  a molecule that drained before closing any step is indistinguishable from an
  ordinary inline husk, and every husk of the city's most common formula has
  zero closed members. That case is tk-gkb81g's to route, not this one's to
  flag. The landed half reads the input convoy: a convoy closes when its one
  work bead closes on land, so a closed convoy is finished work whose open steps
  are residue, not a strand.
- **UNCLAIMABLE** — its executable frontier is non-empty and every member is
  unassigned AND unrouted. The frontier is the members `bd ready` offers, minus
  the inert topology kinds. A routed or owned frontier is reachable (a pool has
  demand, or a session holds it); an empty frontier is a blocker naming the wait
  in the graph.

The frontier reads `gc.routed_to` OR `gc.execution_routed_to` as a route. The
recovery fix (tk-gkb81g) stamps a durable `gc.execution_routed_to` on the
forward steps at pour, so a molecule that fix has reached reads as reachable
here and drops out. The two are complementary by construction: this detector
fires exactly on the strands the route stamp has not (yet) covered.

### Why the anchor is read for landing, not `is_terminal_anchor`

Only a closed input convoy — work landed — exempts. Not `merge_result` in the
broader `pull_request` / `pre_open_gate` / refinery-handoff sense: those are
states a LIVE molecule wears mid-flight, and a rework molecule's anchor already
carries `pull_request` from the round it exists to fix. Deferring to the anchor's
terminal state would exempt a real strand (this is the tk-8m8d4 defect). The
convoy's own closed status is the honest landed signal and needs only the
`bd list --id` read the check already makes.

### Why the executable-kind narrowing

graph.v2 pours inert descriptor beads alongside its steps — `gc.kind=spec`
("Step spec for <step>") and `gc.kind=scope` — which are ready and unroutable by
construction, so a naive frontier satisfies UNCLAIMABLE forever without meaning
it. The frontier excludes `beadmeta.WorkflowTopologyKinds` (`workflow`, `scope`,
`spec`), whose contract is "routing never lands on these; agents must never claim
them." Excluding the topology kinds (rather than allow-listing executable kinds)
is the robust direction: a new executable kind is included by default, so a stall
carried by one is never hidden.

## 3. Home: a read-only doctor check

The signal is store-wide, read-only, cadenced, and asserts an invariant — the
doctor-check shape, beside I8 and I11 which own the neighbouring invariants.
Adding the directory registers it; no manifest edit. The deacon's doctor-sweep
files a non-`ok` verdict as one canonical finding bead per check (`patrol-finding.sh`,
key `doctor-check-root-advancing`), refreshed rather than re-filed each cycle, and
a proactive first reaction disposes it. The check therefore stays side-effect-free
(the read-only contract every check is held to) and files nothing itself.

This supersedes the earlier design (tk-xesf6, `detect-stalled-workflows.sh` as a
witness-patrol step, since removed): the #465 rewrite moved detection into doctor
checks. The four-part predicate is carried forward from that record; its home is
not.

## 4. Fail-safe direction

Every unestablished fact reports nothing rather than guessing, because each input
misread manufactures an escalation about a healthy molecule: an unread roster
makes every molecule look unheld, an unread frontier makes it look unclaimable,
an unread convoy cannot prove work unlanded. The roster read declines the whole
run (warning, not error); a per-store or per-candidate read that fails warns and
leaves that store or candidate unjudged.

## 5. Known limit, stated rather than found later

A molecule that stalls before closing any step is invisible here, by the STARTED
gate — reporting it would report every inline husk in the rig. Those are
tk-gkb81g's to re-route (a drained assigned bead is the witness's orphan
recovery; a pushed branch is the branch-recovery pass). This detector owns the
molecule that demonstrably moved, then stopped, with no way back.
