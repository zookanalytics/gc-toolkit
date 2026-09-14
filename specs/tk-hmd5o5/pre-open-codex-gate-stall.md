---
name: Pre-open codex-gate lifecycle-progression stall — findings and prevention proposal
description: Why work anchors stall at merge_result=pre_open_gate/check_set=codex in three modes (findings never routed, never reviewed, reviewed-not-advanced), with per-mode root cause and file:line, a pack-vs-core split, and a proposed prevention design. Read alongside the fix bead tk-w73r2q.
---

# Pre-open codex-gate lifecycle-progression stall

An anchor at `merge_result=pre_open_gate` with `check_set=codex` should self-drive
to an open PR: the merge cadence dispatches a codex review, the review passes,
and the PR opens. When it does not, the anchor sits with no automated actor
moving it. This spec locates the transition that owns each stall mode, cites the
code that fails to fire it, splits each cause into pack (fixable in gc-toolkit)
or core (gascity, an upstream/fork matter), and proposes a design in which the
stall cannot arise. It does not implement the fixes; it is the convergence input
for the fix bead **tk-w73r2q**.

## Summary

| Mode | Transition that should fire | Owner | Root cause | Pack / core |
|---|---|---|---|---|
| findings-open-never-routed | findings → routed rework child | `signoff.sh` (request-changes) | A rework child is created and blocks the anchor before its route is guaranteed; a failed pour leaves it unrouted, and `gate-ensure` then reads that unrouted child as "fix in flight" and dispatches no replacement review | **Pack** |
| never-reviewed | gate demand → codex review + a seat to run it | `gate-ensure.sh` (dispatch) + gascity demand/spawn | The anchor is parked unrouted and the poured review bead's route is retired to `gc.execution_routed_to`, which the demand counter does not read; demand rests on the poured worker step, and a cold `min_active_sessions=0` codex pool never spawns without it | **Both — decisive gap core** |
| reviewed-not-advanced | review-clean → open PR | `pr-open.sh` (arm 2) | The PR opens only when a lane derives green from a closed `signoff_verdict=approve` review; a review that closes any other way (superseded on head rewrite, closed without a verdict, review-swept) never greens the lane, and an open validated must-fix finding or a second un-green lane also holds `pr-open` | **Pack** |

Cross-cutting: the backstop `gate-ensure` defers its runaway shapes to —
`liveness-sweep.sh`'s stale-gate pass — fires only for `pull_request` anchors,
so no automated actor escalates a stuck pre-open anchor. A false-empty
enumeration under store pressure (tracked on tk-10690, observed live while
writing this spec) makes every cadence arm skip anchors silently, and a
pre-open anchor wrongly flipped to `status=in_progress` drops out of the
`--status=open` enumeration all cadence arms use.

## The pre-open codex gate lifecycle

The anchor state is `status` × `merge_result` (`lifecycle/lifecycle.toml:8-48`).
`pre_open_gate` means "branch pushed, gates armed, no PR yet"
(`lifecycle/lifecycle.toml:55-57`); its only forward edge is to `pull_request`,
written by `assets/scripts/pr-open.sh` (`lifecycle/lifecycle.toml:122-125`).

A polecat's submit hands the work bead to the refinery, which runs the
`merge-push` step of `formulas/mol-refinery-patrol.toml`. With no PR recorded
and `gh` available, `PRE_OPEN=1` (`mol-refinery-patrol.toml:623-626`) and the
step transitions the anchor to `pre_open_gate` through `lifecycle.sh`, parked
unassigned and unrouted (`mol-refinery-patrol.toml:723`;
`lifecycle/lifecycle.toml:28-36` `detached_states`).

From there the merge cadence drives it. The cadence is an order, not the patrol
formula: `orders/refinery-reconcile.toml` runs `assets/scripts/refinery-reconcile.sh`
every 60s per rig. Its arms, in order (`refinery-reconcile.sh:181-266`):

1. `gate-ensure.sh` — dispatch a codex review for each unsettled lane.
2. `pre-open-rebase.sh` — the conflict observer for pre-open anchors.
3. `pr-open.sh` — `pre_open_gate → pull_request`.
4. `pr-facts.sh --posture-only`, `merge.sh`, `pr-facts.sh`, `convoy-graduate.sh`,
   `review-sweep.sh`, `duplicate-sweep.sh`, `pr-stack.sh`.

"Green" is a lane state derived from the review-outcome graph, not a stored
marker: `assets/scripts/lane-state.sh` is the one helper `merge.sh`, `pr-open.sh`
and `gate-ensure.sh` all derive through. A lane is green when a closed
`task_kind=review` bead backs it — `signoff_verdict=approve`, not superseded,
carrying a `reviewed_oid` (`lane-state.sh:108-119`) — or the PR has a GitHub
APPROVED review (`lane-state.sh:62-79`), and no review for the lane is open
(`lane-state.sh:99-106`). The `check.codex=green@<oid>` equality gate against a
live head that earlier designs used no longer exists; `migrate-lane-states.sh`
rewrites `green@<oid>` to a bare `green`, and no reader compares a marker to a
head (`lane-state.sh:5-8`). A moved-forward head therefore cannot, by itself,
strand a clean review.

## Method

Static reading of the current pack (`assets/scripts`, `formulas`,
`lifecycle/lifecycle.toml`) at `origin/main` 99c403a2 and of gascity core at
41da519d8, plus the standing evidence recorded on tk-7i77rv and tk-w73r2q (17
live pre-open anchors on 2026-09-12, 13 untouched more than three days). Every
file:line below was read in the version cited. The live store returned
intermittent false-empty reads throughout (see cross-cutting §D); reads were
retried until they resolved.

## Mode 1 — findings-open-never-routed

**Should fire:** a request-changes verdict files findings and puts a rework
child in flight, routed to a fix pool, blocking the anchor until the fix lands.

**Owner:** `assets/scripts/signoff.sh`, the request-changes path.
`review-outcome.sh` is approve-only and files no rework (`review-outcome.sh:36`),
and `mol-review.toml:396` forbids the reviewer from filing rework itself —
signoff owns it.

**What happens now.** signoff files the objections as findings first
(`signoff.sh:911-913`, via `finding.sh upsert`), then proves the fix pool
resolves to a live agent *before* creating the child (`signoff.sh:924-929`,
`pool-route.sh`), which closes the create-without-a-pool gap. It then creates the
child (`signoff.sh:951`), stamps the work order including `source_review_bead`
(`signoff.sh:960-970`), and makes the child **block the anchor**
(`signoff.sh:975`). Only after all that does it route, by a pour, not a bare
stamp: `gc sling <fix-pool> <child> --on mol-polecat-work` (`signoff.sh:1023`),
verified by reading back `gc.execution_routed_to=<fix-pool>` (`signoff.sh:1024`).

**Root cause (the deadlock).** If that pour does not read back — a partial pour
that started the workflow but failed to stamp the route, or a pool that did not
take it — signoff deliberately refuses a bare `gc.routed_to` fallback (to avoid
a double-dispatch) and exits (`signoff.sh:1028-1030`). The child now exists,
**blocks the anchor**, and carries `source_review_bead`, but has empty
`gc.routed_to` and empty `gc.execution_routed_to`. Nothing in the pack recovers
it, and one reader makes it self-perpetuating:

- `gate-ensure`'s quiescence counts *any* live blocks-child carrying
  `source_review_bead` as a fix unit in flight — it does not require the child
  to be routed, poured, or claimed (`gate-ensure.sh:154-165` `open_rework_child`;
  clause (b) at `gate-ensure.sh:207-208`). So it dispatches no replacement
  review (`gate-ensure.sh:656-659`). The unrouted orphan holds the merge and
  suppresses the very re-review that would re-file it.
- The stranded-rework re-routers that exist cover only *conflict* rework and
  never match a findings child: `pre-open-rebase.sh:333` / `:383` (bare-stamp
  re-route, matched on branch/head conflict) and `pr-facts.sh:823-825`
  (post-open CONFLICTING arm, matched on `head <oid>` in the rejection reason).
- `gate-ensure` re-slings only stranded *reviews* (`gate-ensure.sh:596-639`),
  never rework children, and on retry `signoff` creates *another* child
  (`signoff.sh:951`) with no lookup of the existing unrouted one, piling up
  orphans rather than healing the first.

A fresh finding is `finding.disposition=unvalidated` and takes no blocking edge
(`finding.sh:169-173`; the blocks edge is added only at `must-fix`,
`finding.sh:199-207`), so in Mode 1 the merge hold comes from the rework child,
not the finding — which is why an unrouted child is load-bearing.

**Pack or core:** **pack**, entirely in `signoff.sh` and `gate-ensure.sh`. Core
`gc` only supplies the `sling` primitive whose partial-pour hazard signoff
guards against; handling that hazard is pack responsibility, and the pack drops
it here.

**Live evidence:** tk-9ntg93 carries three open findings (tk-8gcjbn,
tk-iwrm3i, tk-rb8cce) and an open pre-open rework child tk-7nwg8a — a child that
exists but has not driven the fix.

**Related tracked work:** tk-xrrz7n (the round cap fires instead of filing the
rework child its guard requires), tk-9ymanb (polecat recovery clears
`gc.routed_to` on a claimed rework, stranding it — a core runtime bug of the
same class), tk-epi4kx (post-open review comments trigger no rework), tk-j5wrs
(the anchor's in-flight set has no canonical definition — four dispatchers, four
membership tests).

## Mode 2 — never-reviewed

**Should fire:** an unsettled codex lane draws a codex review, and a codex-pool
seat spawns to run it.

**Owner of dispatch:** `assets/scripts/gate-ensure.sh`. It enumerates open
`pre_open_gate`/`pull_request` anchors (`gate-ensure.sh:400-409`), and for an
unsettled lane creates the review bead (`gate-ensure.sh:692-693`), stamps
`task_kind=review`/`anchor_bead`/`review_branch`/`review_pool`/`reviewed_oid`
(`gate-ensure.sh:707-715`), blocks the anchor (`gate-ensure.sh:716`), and pours
it: `gc sling <review-pool> <review> --on mol-review` (`gate-ensure.sh:728`).
The review pool is `<rig>/<prefix>polecat-codex` (`refinery-reconcile.sh:59`).
There is no dispatch ceiling any more; quiescence replaces it
(`gate-ensure.sh:24-29`, `:665-673`).

**The dispatch is fire-and-forget.** It is not conditional on a codex session
existing. The only liveness gesture is a best-effort `gc session wake`
(`gate-ensure.sh:733`), which pokes an idle session but does not spawn one.

**Root cause (why no seat runs it).** `polecat-codex` is a demand-driven pool
with `min_active_sessions=0`, `max_active_sessions=2`
(`agents/polecat-codex/agent.toml:24-26`); no `city.toml` patch raises the
minimum. A cold pool spawns only when the demand controller counts a bead routed
to it. By core design it counts none for a pre-open review:

- The **anchor** is parked unrouted at `pre_open_gate`
  (`mol-refinery-patrol.toml:723`), so it emits no demand.
- The **review bead**'s route is retired by the pour. `restampWorkBeadRouting`
  "clears `gc.routed_to` and stamps `gc.execution_routed_to`"
  (gascity `internal/sling/sling_core.go:812`), and the demand counter reads
  `gc.routed_to` only, never `gc.execution_routed_to`
  (gascity `cmd/gc/work_routing_metadata.go:27-37`, consumed by
  `build_desired_state.go` demand serving; topology roots excluded by
  `demand_serve_predicate.go`).
- Demand therefore rests entirely on the poured mol-review workflow's routed
  worker **step**. If that step lands without a route — the gc-rfxju silent-stall
  class, where every worker step resolves to a nameless pool binding — the pool
  sees nothing and the pour still reports success. gascity now guards that pour
  (`internal/sling/sling.go` `ensureGraphWorkflowHasClaimableStep`), which
  surfaces to the pack only as `gate-ensure`'s `pour_ok` read-back failing
  (`gate-ensure.sh:729-732`) and the merge staying held.

So the demand-count, the route-retirement, and the cold-pool spawn all live in
gascity. A cold `min=0` pool with a review whose only demand-bearing route is a
worker step is one dropped route away from never spawning, and nothing in the
pack can raise the minimum or change what the counter reads.

**Two pack contributors sit on top of the core gap:**

- `gate-ensure` and `pr-open` enumerate `--status=open`
  (`gate-ensure.sh:401`, `pr-open.sh:199`). A `pre_open_gate` anchor should rest
  at `status=open`, but an out-of-band claim flips it to `in_progress`, and then
  no cadence arm sees it. **Live evidence:** tk-or0ha2 (visit tk-5g1wrq) is
  `merge_result=pre_open_gate`, `check_set=codex`, unassigned, but
  `status=in_progress`, and no bead carries `anchor_bead=tk-or0ha2` — never
  enumerated, never reviewed.
- The dispatch has no reviewer-liveness backstop, and the one it defers to does
  not cover pre-open (cross-cutting §A).

**Pack or core:** **both, and the decisive gap is core.** The pack half
(fire-and-forget dispatch, the `--status=open` blind spot) is fixable here; the
demand-not-counted / cold-pool-not-spawned half is a gascity/fork matter.

**Related tracked work:** tk-9ymanb, tk-gnrhr (a saturated pool turns queued
rework into a salvage candidate), tk-j5wrs, tk-10690 (false-empty enumeration).

## Mode 3 — reviewed-not-advanced

**Should fire:** every declared lane derives green, so `pr-open` opens the PR
and flips `pre_open_gate → pull_request`.

**Owner:** `assets/scripts/pr-open.sh`, arm 2 of the cadence
(`refinery-reconcile.sh:201`). It enumerates open `pre_open_gate` anchors
(`pr-open.sh:199`), holds unless every check_set lane derives green via
`lane-state.sh --no-remote` (`pr-open.sh:266-276`), holds on an open must-fix
finding (`pr-open.sh:282`), needs the live head to open at (`pr-open.sh:293-298`),
then flips through `lifecycle.sh transition --to pull_request`
(`pr-open.sh:192-196`, `:392`).

The green-stamp on the approve side: `signoff.sh` on `--verdict approve` stamps
a bare `green` marker (`signoff.sh:742`) and closes the review
`signoff_verdict=approve`, `gc.outcome=recorded`, `reviewed_oid=<head>`
(`signoff.sh:679-680`). mol-review decides approve vs request-changes by finding
severity (`mol-review.toml:372-374`), so codex posting its approval as a GitHub
COMMENT (bots cannot self-APPROVE) still reaches signoff as `--verdict approve`.

**Root causes (a review closes but the anchor does not advance):**

- **Supersede on head rewrite.** If the reviewed commit is rebased, amended, or
  force-pushed off the branch, signoff refuses the verdict and closes the review
  `gc.outcome=superseded` with no marker and no round spent
  (`signoff.sh:573`, `:606`). `lane-state.sh:117` excludes superseded, so the
  lane never greens, and `gate-ensure` pours a fresh review next pass. A branch
  that keeps being rewritten supersedes each review in turn and loops at
  `pre_open_gate` forever. **Pack** (`signoff.sh`). This is the real "head moved"
  mechanism, distinct from the retired equality gate.
- **Review closed without a recorded verdict.** A reviewer that closes its
  workflow chain without calling signoff leaves the review with no
  `signoff_verdict`; `gate-ensure` detects the spent workflow and escalates it as
  wedged (`gate-ensure.sh:335-376` `judge_pour_liveness`), but until then the
  lane has no backing and `pr-open` holds. A review closed by `review-sweep.sh`
  or superseded reads the same way. **Pack.**
- **Open validated must-fix finding after an approve.** approve closes only
  *unvalidated* findings (`signoff.sh:749`), so a validated must-fix from an
  earlier round stays open and `pr-open.sh:282` holds even on a clean current
  review. **Pack.**
- **A second un-green lane** in a multi-lane check_set holds `pr-open.sh:273`.
  **Pack.**
- **Head unresolved.** `pr-open.sh:295` skips when `gh` cannot resolve the branch
  head; a flaky `gh` defers the open. **Pack/infra.**

**Latent drift:** `gate-ensure.sh:135` matches a review's `check_name` literally
(absent ≠ codex) while `lane-state.sh:102,112` defaults an absent `check_name` to
`codex`. A review bead with no `check_name` counts for lane codex in one reader
and not the other. `gate-ensure` stamps `check_name` at dispatch
(`gate-ensure.sh:709`), so it rarely fires, but it is a real disagreement between
the two readers of the review graph. **Pack.**

**Pack or core:** **pack**, across `signoff.sh`, `lane-state.sh`,
`gate-ensure.sh`, `pr-open.sh`, and `lifecycle.sh`. gascity stores `merge_result`
as an opaque string and imposes no green gate or state-machine guard on the
`pre_open_gate → pull_request` transition.

**Related tracked work:** tk-w73r2q (the fix bead, whose evidence samples
tk-wx5ybh, tk-ww19bz, tk-5g85ft as "reviews closed, never advanced"),
tk-0haj8b (a stale-gate re-review fixture missing its sling call).

## Cross-cutting failure surfaces

**A. The pre-open backstop does not exist.** `gate-ensure` says its residual
runaway shapes — a reviewer that dies after claim, a fix unit filed with its
edge reversed — are "caught by liveness-sweep.sh's stale-gate pass"
(`gate-ensure.sh:26-29`, `:670-673`). But `liveness-sweep.sh`'s `stale-gate`
class is reached only for `merge_result=pull_request` with a stale open PR
(`liveness-sweep.sh:357-360`). A `pre_open_gate` anchor is classed `gated` if
its stored `check.<g>` markers are all green (`liveness-sweep.sh:361`), classed
`gated` if any live child tracks it (`:363-364`), and otherwise `unnamed`
(batched into the standing unnamed-waits escalation). It never becomes
`stale-gate`, so no automated actor escalates a stuck pre-open anchor per-anchor,
and a dead-but-open review child even makes it read as `gated` /
`routed-and-claimable` (`liveness-sweep.sh:349`), silencing it. The backstop
every mode relies on is absent for the state most wedged anchors are in
(`lifecycle/lifecycle.toml:309-310`).

**B. Two representations of green.** `signoff.sh` writes a stored `check.<g>`
marker, and `liveness-sweep.sh`'s `pre_open_all_green` reads that stored marker
(`liveness-sweep.sh:310-316`), while `merge.sh`, `pr-open.sh` and `gate-ensure`
derive green from the review graph through `lane-state.sh` and ignore the marker.
The two can disagree, and the classifier the operator's board reads is the one
using the weaker source. This is why the surfacing bead tk-7i77rv reports these
anchors as routine rather than stalled.

**C. Status invisibility.** All cadence arms enumerate `--status=open`. A
`pre_open_gate` anchor flipped to `in_progress` (an out-of-band claim; the
lifecycle clears an assignee only at transition time and only at `status=open`,
`lifecycle/lifecycle.toml:28-35`) drops out of every arm at once — no review, no
open, no posture. tk-or0ha2 is a live instance.

**D. False-empty enumeration.** Every cadence arm enumerates via
`gc bd list ... | jq`; under store pressure a temp-file failure prints an
empty result and exits 0, so the arm sees no anchors and does nothing, silently
(tracked on tk-10690). This was live while writing this spec: `gc bd show` on a
bead present in the store returned "no issues found" on one call and the full row
on the next, non-deterministically, with disk at 75%. A false-empty
`gate-ensure` enumeration dispatches no reviews; a false-empty `pr-open`
enumeration opens no PRs — a systemic contributor to all three modes.

## Prevention design

The target is that each transition self-drives and no pre-open anchor can rest
with no live review and no route. Human-facing surfacing is tk-7i77rv's job; the
remedies here make the machine advance.

**Mode 1 — make the rework child's route atomic with its hold.** A rework child
must not block the anchor until it is routed, and an unrouted child must not
count as a fix in flight. Two changes make the deadlock impossible: before
creating a child, adopt and re-route any existing unrouted findings-rework child
on the anchor (mirroring `gate-ensure`'s own orphan-review adoption at
`gate-ensure.sh:684-688`); and tighten `open_rework_child` to require the child
be routed, poured, or claimed before it counts as in flight (mirroring
`inflight_review`'s reach test at `gate-ensure.sh:129-145`). A pre-open
findings-rework re-router — a cadence arm analogous to `pre-open-rebase.sh`'s
conflict re-router — then re-routes any child that still slips through.

**Mode 2 — give the codex lane a seat, or make the review count as demand.**
The core gap needs one of: a codex pool with `min_active_sessions ≥ 1` (a
standing seat that claims routed reviews), a demand model that counts a
pre-open review's demand without depending on a single worker-step route, or a
pack backstop that detects "review dispatched N passes ago, no claim, no live
codex session" and escalates or degrades the gate. The demand-count and pool
spawn are gascity's, so this arm converges with the operator and with tk-w73r2q
before anything is built. On the pack side, fix the `--status=open` blind spot
(cross-cutting §C) and add the pre-open backstop below.

**Mode 3 — fail-safe the gate rather than loop.** A review that closes without a
recordable verdict already re-dispatches through `gate-ensure`; bound that so a
run of supersede/rewrite or verdict-less closes on one anchor escalates instead
of looping silently. Reconcile the two green representations (cross-cutting §B)
onto the derived `lane-state` as the single source of truth so the board and the
gate agree. Whether to relocate the codex gate to *after* PR-open — which changes
the PR-open model — is a design question the bead flags as operator-gated; it is
not proposed here, only named.

**The one backstop that covers all three.** Add a stale-pre-open-gate branch to
`liveness-sweep.sh` mirroring its `stale-gate` PR branch: fire on staleness AND
no live review in flight AND no open rework child, and name the reason
(findings-open / never-reviewed / reviewed-not-advanced). It must not fire on the
raw gate state — `pre_open_gate` with an empty route is the correct held shape
and a fresh park is healthy — which is why it keys on staleness plus the absence
of any live actor. This is the backstop `gate-ensure` already assumes exists, and
it is the same signal tk-7i77rv/tk-ju4jfy need, so the visibility and the
self-heal share one detector.

## Fix inventory

Clean pack fixes, ready to file against tk-w73r2q once the approach is accepted:

1. `signoff.sh`: adopt and re-route an existing unrouted findings-rework child
   before creating a new one (Mode 1 dedup + heal).
2. `gate-ensure.sh` `open_rework_child`: require routed/poured/claimed before a
   rework child counts as a fix in flight, so an unrouted orphan cannot suppress
   re-review (Mode 1).
3. A pre-open findings-rework re-router, in `gate-ensure.sh` or a new cadence
   arm, analogous to `pre-open-rebase.sh`'s conflict re-router (Mode 1).
4. `liveness-sweep.sh`: a stale-pre-open-gate escalation branch (backstop for all
   modes; also serves tk-7i77rv / tk-ju4jfy).
5. `gate-ensure.sh` / `pr-open.sh`: close the `--status=open` blind spot for a
   `pre_open_gate` anchor stuck at `in_progress`, or a sweep that re-detaches a
   wrongly-claimed gating anchor (Mode 2/3, cross-cutting §C).
6. Align the `check_name` default between `gate-ensure.sh:135` and
   `lane-state.sh:102,112` (Mode 3 latent drift).

Needs design convergence (do not implement before the operator rules):

- **A.** Mode 2 core: the cold `min=0` codex pool that never spawns on pre-open
  demand — choose `min_active_sessions ≥ 1`, a demand-model change, or a pack
  backstop; the demand-count, route-retirement, and cold-spawn live in gascity
  (fork/upstream). Coordinate with tk-w73r2q.
- **B.** Relocating the codex gate to after PR-open — changes the PR-open model;
  operator-gated (named in the bead).
- **C.** The dual green representation (stored `check.<g>` vs derived
  `lane-state`) — pick one source of truth; affects both this gate and tk-7i77rv.
- **D.** The in-flight-set canonicalization already tracked on tk-j5wrs — the
  membership tests this spec's Mode 1 and Mode 2 both lean on.

## Relationship to existing work

**tk-w73r2q** (P1, "investigate and fix why anchors stall at the pre-open codex
gate after review instead of advancing") references this bead and carries the fix
mandate for all three modes plus the pool question. This spec is its convergence
input; the clean pack fixes above should become its children. tk-hmd5o5 (this
bead, P2, under convoy tk-gq994d "prevent pre-open codex-gate progression
stalls") stops at the proposal by design.

**tk-7i77rv** and **tk-ju4jfy** own the operator-facing surfacing of these
anchors; fix 4 (the pre-open stale-gate detector) serves both.

Existing beads covering individual slices, none to be duplicated by the fixes
above: tk-xrrz7n, tk-9ymanb, tk-gnrhr, tk-epi4kx, tk-nfdq56, tk-j5wrs (Mode 1
and the in-flight-set design), tk-10690 (the false-empty enumeration).
