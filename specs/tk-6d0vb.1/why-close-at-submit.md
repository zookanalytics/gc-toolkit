# Why does the refinery close the work bead at PR-submit — and is close-on-merge a pack change or a core fork?

**Bead:** tk-mt1ey (research for epic tk-6d0vb.1) · **Status:** findings only — NO code change, NO PR.
**Author:** polecat gc-toolkit.furiosa · **Date:** 2026-06-21

## TL;DR

- **Close-at-submit is a gascity FORMULA convention, not core behavior.** The work bead is
  closed by a literal `gc bd close $WORK` call inside a *step body* of
  `formulas/mol-refinery-patrol.toml`. The gascity `gc` binary never auto-closes a refinery
  work bead; it only exposes the generic `bd close` primitive.
- **The locus is pack-owned, not a core fork.** `formulas/mol-refinery-patrol.toml` is an
  **allowlisted deliberate mirror** that gc-toolkit already vendors and re-reconciles against
  gastown base (collision doctor). Changing the close timing = editing one already-maintained
  formula step. **No gascity-core fork. Lands local.**
- **Core is agnostic to *when* we close — with one operational coupling.** Core's pool-demand
  / scale-from-zero logic treats `open + unassigned + gc.routed_to=<pool>` beads as demand. An
  anchor bead that stays **open but *assigned*** (or with `gc.routed_to` cleared) does **not**
  read as fresh demand. The "core would re-dispatch it" risk is real but **trivially avoidable**
  by managing assignee/routing — it is not a hard core dependency.
- **Recommendation:** close-on-merge is the right call for us and is a *pack-scoped, bounded-cost*
  change. The only genuinely new work is a **merge-detection pass** that flips the open anchor
  → closed when its PR merges, plus keeping the anchor assigned/unrouted while open. Direct-merge
  beads already behave correctly (close == merged) and need no change.

---

## (a) Why gascity closes the work bead at PR-submit

The rationale is documented in the formula header itself, not in a separate design doc.

> `formulas/mol-refinery-patrol.toml:17` — "Work beads flow directly: pool → polecat →
> refinery → **closed**. No separate MR beads."
>
> `formulas/mol-refinery-patrol.toml:22-28` — "Merge strategy is per-work-bead metadata:
> `direct` … `mr`/`pr` … In `mr` mode, refinery treats **PR publication as the terminal
> handoff** for the direct-bead workflow: it records the PR URL on the work bead and **closes
> the bead once the PR is verified**."

So the design intent is a **simple, bounded, single-owner bead lifecycle**: the refinery's job
is to perform *one* handoff per work bead and then be done with it.

- **Direct strategy:** handoff = fast-forward merge to target. Close means *merged*
  (`formulas/mol-refinery-patrol.toml:738-756`, close at line 756, gated on a verified push to
  `$TARGET`).
- **mr/pr strategy:** handoff = publish a GitHub PR. Close means *PR submitted & verified* — **not
  merged** (`formulas/mol-refinery-patrol.toml:1022-1069`, close at line 1069
  `gc bd close $WORK --reason "Pull request ready: $PR_URL"`).

**What close-at-submit BUYS (the deliberate upside):**

1. **Bounded refinery loop.** Each patrol wisp is "one iteration: check for work, merge one
   branch, pour the next" (`:7`). The refinery never holds a long-lived open bead waiting on an
   external (human/GitHub) merge it cannot control. The work-bead lifecycle closes inside the
   loop that owns it.
2. **Clean pool/queue accounting.** The "merge queue" is virtual — it is just
   `status=open/in_progress + assignee=refinery + metadata.branch`. Closing the bead dequeues it
   (core `bd ready` filters `status=="open"`, `internal/beads/beads.go:230`). The reconciler's
   pool-demand count stays honest (`internal/config/config.go:3412-3413`).
3. **A `closed != merged` convention that is forensically traceable.** The close is chained with
   metadata so a closed mr-bead still records `pr_url`/`pr_number`/`merged_target`
   (`:1063-1069`); a closed direct-bead records `merged_sha`/`merged_target` (`:751-756`). The
   reason string ("Pull request ready: …" vs "Merged to … at …") disambiguates the two.

**This behavior is gascity's, inherited verbatim.** It was vendored into the pack in commit
`8412dca8` ("Lane C: vendor gastown roster into gc-toolkit (own the picture)", from
gascity@669586546a). The live gastown base at the currently-adopted pin still closes at submit
(verified: `…/.gc/agents/mayor/.gc/system/packs/gastown/formulas/mol-refinery-patrol.toml:881`,
identical header `:26-28`); the captured base-snapshot's close lines match the live base.

---

## (b) What depends on close-at-submit

| Dependent | Kind | What it relies on | Effect of close-on-merge |
|---|---|---|---|
| **Core pool-demand / scale_check** | CORE (Go) | `bd ready … gc.routed_to=$target **--unassigned**` (`config.go:3413`); `bd ready` requires `status=="open"` (`beads.go:230`) | An open anchor bead **must stay assigned (or unrouted)** or it re-reads as pool demand and over-provisions polecats. **Avoidable** — keep it assigned to refinery/host, `gc.routed_to` cleared. |
| **Convoy auto-land** | PACK (formula) | "if **ALL children are closed**, assign the convoy bead for graduation" (`mol-refinery-patrol.toml:1123-1142`) | Graduation trigger shifts from *children PR-submitted* → *children PR-merged*. **More correct** (don't graduate an integration branch before its child PRs actually merge), but verify it doesn't stall graduation when PRs sit in review. |
| **work_bead pointer pattern** | PACK (formula) | Refinery stamps `work_bead=$WORK` on the review bead it creates *before* closing (`:1055`); codex fix beads then re-link two-hop via `source_review_bead` → review bead → `work_bead`. | **Largely retired.** With the anchor open, review/rework attach as deps directly; no backward pointer needed. |
| **Attention board** | PACK (script) | Collects only **OPEN** anchors — epic / owned-convoy / decision / flagged (`assets/scripts/gc-attention.sh`). Plain work beads are not anchors unless flagged. | A closed work bead is invisible to every open-bead view. An open anchor restores graph visibility (and the board, if the anchor is flagged/an anchor type). |
| **Witness / mayor / `gc events`** | CORE | No status-based visibility filter; `BeadClosed` is recorded (`events.go:24`) but does not gate any view. | No change required in core. |
| **`closed != merged` convention** | PACK (doc/convention) | Encoded only in the formula header + reason strings; core has no knowledge. | The convention *inverts* to the more intuitive `closed == merged` for the mr path. |

**Net:** the only *core* coupling is pool-demand accounting, and it is satisfied by keeping the
open anchor assigned/unrouted. Everything else that "depends on" close-at-submit is pack-level
and is either improved by close-on-merge (visibility, convoy correctness) or made unnecessary by
it (work_bead pointer).

---

## (c) Locus — pack vs. core (the cost crux), with file:line evidence

**The close is a FORMULA STEP. It is pack-controllable. It is NOT a core codepath.**

- **mr/PR close (the close-at-submit being challenged):**
  `formulas/mol-refinery-patrol.toml:1022-1069` — step `merge-push`, mr block, sub-step 4
  "Record PR metadata and close the work bead":
  ```
  1063  gc bd update $WORK --set-metadata merge_result=pull_request --set-metadata pr_url=… \
  1069  gc bd close $WORK --reason "Pull request ready: $PR_URL"
  ```
- **direct close (already close==merged):** `:738-756`, close at `:756`.
- **GATE invariant:** `:1092` — "Bead closure only happens after the selected handoff is confirmed."

**Core only provides the generic primitive — it never decides *when*:**

- `internal/beads/beads.go:314-316` — `Close(id string) error` is documented as "sets a bead's
  status to closed … Closing an already-closed bead is a no-op." No merge/PR awareness.
- No core "merge queue" structure; the queue is virtual (beads assigned to the refinery agent).
- `gc bd close` invoked from the formula is the *only* place a refinery work bead is closed.

**The pack already owns this formula as a maintained mirror:**

- `formulas/mol-refinery-patrol.toml` is **44 KB / 1172 lines** in the pack vs **984 lines** in
  base — the pack carries ~188 lines of intentional local deltas (codex review-gate `:1038-1061`,
  `auto_ff_rig_main` `:766-806`, `default_merge_strategy` normalization, protected-branch
  auto-promote).
- The collision doctor explicitly allowlists it as a deliberate mirror:
  `doctor/check-base-artifact-collision/run.sh` — "*formulas/mol-refinery-patrol.toml — base +
  default_merge_strategy + auto_ff_rig_main + review_gate + protected-branch auto-promote +
  integration-branch INFO local deltas.*" The check WARNs (not errors) when base advances, with a
  documented reconcile-and-refresh-snapshot workflow.

**Conclusion:** close-on-merge edits an *already-forked, already-maintained* formula step. It is a
**pack change that lands local. There is no gascity-core fork and no new upstream-divergence
surface** — it adds one more delta to a mirror gc-toolkit already re-reconciles.

---

## (d) Options

| # | Approach | Effort | Upstream-divergence cost | What it buys |
|---|---|---|---|---|
| **1** | **Close-on-merge** — in the mr path, keep `$WORK` **open** (assigned, `gc.routed_to` cleared), record `pr_url`; add a refinery pass that **closes on PR-merge**. Direct path unchanged. | **Medium** — edit `:1063-1069`; add a merge-detection step (poll open PR-anchor beads → close merged). Manage assignee/routing. | **Low.** No new allowlist entry; one more delta on the already-mirrored `mol-refinery-patrol.toml`. No core change. Marginal reconcile cost when base's mr-close step advances. | The review→rework→merge phase stays bead-represented; "who is on this PR" = open deps under the anchor; collisions become detectable; `closed == merged` becomes honest; retires the work_bead-pointer burden. |
| **2** | **Status quo — work_bead pointer** (do nothing). | **Zero** (exists). | **Zero.** | Backward link from review/fix beads to the closed work bead — enough to *route* a rework. Does **not** give cross-agent visibility or collision detection; per-bead pointer maintenance (codex path is fragile two-hop via `source_review_bead`). |
| **3** | **Separate durable PR-anchor bead** — close `$WORK` at submit as today, but spawn a new long-lived anchor bead that stays open until merge; attach review/rework to it. | **Medium** | **Low** (formula-only). | Visibility without changing close timing — but creates a **second bead per PR**, i.e. exactly the "two beads on one PR" footgun the epic warns about, and forks the work bead's history. More moving parts than #1 for the same win. |
| **4** | **PR-body stamp alone** — write the bead id into the PR body/metadata at publish. | **Low** | **Minimal** (formula-only). | A forensic PR→bead breadcrumb. Keeps nothing open; no graph visibility, no collision detection. Complements but does not solve. |

---

## (e) Recommendation & open questions

**Recommendation: adopt close-on-merge (Option 1).** It is the right call for us and the cost is
bounded:

- The locus is a **pack-owned, allowlisted formula step** — not a core fork. It lands local with
  **no new upstream-divergence surface**.
- **Core is agnostic to close timing.** Its only coupling (pool-demand counting) is satisfied by
  keeping the open anchor *assigned/unrouted* — a one-line discipline, not a redesign.
- It directly delivers the epic's goal (`tk-6d0vb.1`): the contended review→merge phase stays on
  the bead graph, "who is on this PR" falls out of the deps, and the **work_bead pointer
  maintenance burden** (the thing that bit PR#140 across three review rounds) goes away.
- It also makes the existing **convoy auto-land** trigger more correct (graduate on children
  *merged*, not children *submitted*).

The genuinely new engineering is the **merge-detection pass** (flip open anchor → closed when the
PR merges) and keeping the anchor assigned/unrouted while open. Everything else is editing one
already-maintained step.

**Open questions for the operator (decide before implementation):**

1. **Anchor home while open.** Who holds the open anchor during review — refinery, a dedicated
   PR-host, or the original polecat? (Must stay *assigned* with `gc.routed_to` cleared so it
   doesn't re-read as pool demand: `config.go:3413` requires `--unassigned`.)
2. **Merge-detection trigger.** A new refinery patrol pass that polls open PR-anchor beads for
   merged PRs (natural home, mirrors the existing draft-PR reconcile pass), or an external
   webhook/cron? What is the cadence?
3. **Single-anchor collision** (two independent beads on one PR — dogfooded on PR#116). The epic
   *de-escalated* this (2026-06-15) to an implementation-time bug-fix, not a decide-now
   reject-vs-auto-attach fork. Confirm we resolve it during the build, not now.
4. **Convoy auto-land.** Confirm shifting the children-closed trigger to children-**merged** is
   desired and won't stall graduation when PRs sit in review (`:1123-1142`).
5. **Scope.** Direct-merge already closes == merged (`:756`); close-on-merge only touches the
   mr/pr path (`:1069`). Confirm we leave direct mode untouched.
6. **Codex review gate.** It currently runs *after* PR-publish and *before* the close
   (`:1038-1061`). With the bead open, the review bead can fold into the anchor's dep graph
   instead of carrying `work_bead` back to a closed bead — confirm the desired shape.

---

## Evidence appendix (file:line)

**Pack formula** — `formulas/mol-refinery-patrol.toml`
- `:7` one-iteration loop · `:17` pool→polecat→refinery→closed flow · `:22-28` merge-strategy + "terminal handoff" rationale
- `:738-756` direct close step (close `:756`, gated on verified push)
- `:1022-1069` mr/PR close step (close `:1069`); codex review-gate `:1038-1061`; `work_bead=$WORK` stamp `:1055`
- `:1092` GATE — "Bead closure only happens after the selected handoff is confirmed"
- `:1123-1142` convoy auto-land (children-closed graduation trigger)

**Base (gastown upstream)**
- live pin `…/.gc/agents/mayor/.gc/system/packs/gastown/formulas/mol-refinery-patrol.toml:651` (direct), `:881` (mr), header `:26-28` — snapshot == live (verified)
- snapshot `doctor/check-base-artifact-collision/base-snapshots/formulas/mol-refinery-patrol.toml`

**Collision doctor (pack-vs-base ownership)**
- `doctor/check-base-artifact-collision/run.sh` — allowlist policy; `mol-refinery-patrol.toml` allowlisted as deliberate mirror; WARN-on-base-advance + reconcile/refresh workflow
- `doctor/check-base-artifact-collision/doctor.toml` — "artifacts … don't silently shadow gastown base — allowlisted mirrors WARN when base advances"
- vendoring commit `8412dca8` (gascity@669586546a)

**Core (`/home/zook/loomington/rigs/gascity`)**
- `internal/beads/beads.go:314-316` — generic `Close()` primitive, no merge logic
- `internal/beads/beads.go:230` — `bd ready` requires `b.Status == "open"`
- `internal/config/config.go:3412-3413` — `bdReadyPoolDemandShell`: `gc.routed_to=$target --unassigned --exclude-type=epic`
- `internal/beads/query.go:163-164` — list excludes closed unless `IncludeClosed`
- `internal/events/events.go:24` — `BeadClosed` event recorded; no visibility gate

**Incident & intent**
- Epic `tk-6d0vb.1` — close-on-merge direction; "ONE open anchor bead per PR; who-is-on-this = what's open under the anchor"; enforcement de-escalated 2026-06-15 (single-anchor = impl-time bug-fix). Dogfooded collision on PR#116; un-dep-linked twins tk-exj9y / tk-q4xaj.3.1.
- PR#140: work bead `tk-6d0vb.3.3` closed "PR ready for codex … @ 05c8e1f"; **three review rounds** → `tk-dmyiv` (codex r1, via `source_review_bead`), `tk-ci7yx` (codex r2, via `source_review_bead`), `tk-2c0o8` (operator trim, carries `work_bead=tk-6d0vb.3.3` directly).
- Precedent: the proactive/first-reaction agent **deliberately never closes** the work bead — it "advances" it (`agents/proactive/prompt.template.md:104`) — an existing in-pack acknowledgement that closing ejects a thread.
