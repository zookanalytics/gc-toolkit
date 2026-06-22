# Core convoy mechanics + convoy / workflow / v2-formula-DAG taxonomy — which is our delivery wrapper under close-on-merge?

**Bead:** tk-zflam (research for epic thread tk-6d0vb.1, child of research tk-6d0vb.1) · **Status:** findings only — NO code change, NO PR.
**Author:** polecat gc-toolkit.furiosa · **Date:** 2026-06-22
**Builds on:** tk-mt1ey (`specs/tk-6d0vb.1/why-close-at-submit.md`), which established the direction
(CLOSE-ON-MERGE: a PR-owning work bead closes when its PR *merges*, pack-only, refinery executes the
merge post-approval) and left open *"where does PR/delivery state sit"* and *"what is the wrapper."*

Core source root for all `file:line` citations: **`/home/zook/loomington/rigs/gascity`** (the gascity
`gc` core, built `+dirty` from this checkout). Every load-bearing line was read first-hand.

---

## TL;DR

- **The convoy IS our delivery wrapper. The workflow / v2-formula-DAG is NOT** — it is the formula
  *execution* graph (control beads, source beads, the dispatch subsystem), a structurally disjoint
  construct. `gc workflow` is a **hidden, deprecated alias** of `gc convoy` that exposes only the
  dispatch subcommands (`cmd_convoy_dispatch.go:47-56`).
- **"Land when all children MERGED" falls out of close-on-merge for free — zero core change.** The
  convoy's completion predicate is purely bead-status (`IsTerminalStatus` = `closed`/`tombstone`,
  `internal/convoy/membership.go:18-20`). It has **no merge awareness whatsoever** (no PR field, no
  git, no merge check anywhere in `internal/convoy/` or in `check`/`autoclose`/`land`). So
  "all children closed" *means* "all children merged" **iff** close-on-merge makes a child close ==
  its PR merge. The convoy inherits the semantic entirely; it never verifies the merge itself.
- **Use OWNED convoys for gated delivery.** A non-owned convoy self-closes the instant its last child
  closes — the bd on-close hook `autocloseConvoyIfComplete` fires on *every* child close
  (`cmd_convoy.go:1894-1924`). The `"owned"` label exempts the convoy from **both** auto-closers
  (`gc convoy check` `:1521-1523`; the on-close hook `:1927`), keeping the wrapper open through the
  review→approve→merge window until an explicit `gc convoy land` — which has a built-in
  "all-children-terminal" gate (`:1781-1788`), `--dry-run`, `--force`, and `convoy.notify`.
- **Three wiring gotchas to get right** (all pack/usage-level, no core fork):
  1. **Target inheritance follows parent-child ONLY, not `tracks`** (`internal/sling/sling.go:875`),
     but convoy membership IS a `tracks` dep (`membership.go:24-32`). So children do **not** inherit
     the convoy's target branch. → For a one-branch aggregate (S2), stamp `metadata.target` on each
     child directly. For a many-PR tracker (S1), you don't need inheritance at all.
  2. **Never stamp `gc.routed_to` on the convoy bead.** Convoy is a `containerType` but is **not** in
     `readyExcludeTypes` (`internal/beads/beads.go:148-187`), and the pool-demand probe only excludes
     `epic` (`internal/config/config.go:3413`). Today convoys carry no `gc.routed_to`, so an open
     wrapper creates **zero** spurious demand — keep it that way.
  3. **The "id has no default" auto-convoy bug is a Dolt schema defect (now fixed + regression-tested),
     not a convoy design limit** (`internal/sling/sling_test.go:2968-2972`). Verify the adopted build
     carries the migration-0043 fix, else *all* `DepAdd` (hence all convoy membership) fails silently.
- **S1 (many-PR tracker) is the natural fit**, not S2 (one aggregate branch): a convoy carries no
  branch/PR identity of its own, and `tracks` membership gives progress / autoclose / land / stranded
  for free without needing the (broken-for-tracks) target inheritance.

---

## (A) Convoy mechanics — the six answers

`gc convoy` registers ten lifecycle subcommands (`cmd_convoy.go:71-82`:
create/list/status/target/add/close/check/stranded/**autoclose**(hidden hook)/land) **plus** the
dispatch subcommands spliced in at `:83`. Create flags (`:139-145`): `--owner`, `--notify`,
`--merge` (`direct`/`mr`/`local`), `--target` *"target branch inherited by child work beads"*,
`--owned` *"mark convoy as owned (manual lifecycle, no auto-close)"*.

### A1 — Lifecycles: auto-close vs OWNED; which fits gated delivery

The **only** mechanical difference between the two lifecycles is the `"owned"` label and what it
gates. Both enforce the *same* completion predicate (all children terminal); owned just moves the
trigger from automatic → explicit and adds `--force`/`--dry-run`.

**(a) AUTO-CLOSE (default, non-owned)**
- **Begins:** `gc convoy create <name>` without `--owned` (label slice empty, `cmd_convoy.go:308-311`),
  or any plain `gc sling` (auto-convoy `sling-<beadID>`, no label — see A6). Bead is `Type:"convoy"`.
- **Terminates automatically**, two paths, identical predicate:
  1. `gc convoy check` — scans open convoys, closes any whose children are all terminal
     (`doConvoyCheckAcrossStoresJSON`, `:1512-1565`). **Skips owned:** `if hasLabel(item.bead.Labels,
     "owned") { continue }` (`:1521-1523`).
  2. **bd on-close hook** `autocloseConvoyIfComplete` — fires every time *any* child bead closes,
     reaching the convoy via the closed bead's parent (`:1905-1911`) **and** its tracking convoys
     (`TrackingConvoysForItem`, `:1913-1923`). **Skips owned:** `... || hasLabel(convoy.Labels,
     "owned") { return }` (`:1927`).
  Both close via `convoyAutocloseReason = "convoy autoclose: all children closed"` (`:1540`, `:1941`).
- `gc convoy land` **refuses** a non-owned convoy (`:1753-1756`).

**(b) OWNED (manual)**
- **Begins:** `gc sling --owned` or `gc convoy create --owned` → convoy bead carries label `"owned"`
  (`cmd_convoy.go:310`; sling path `internal/sling/sling_core.go:563-571`).
- **Terminates only by explicit command** — both automatic closers skip it. The intended terminator
  is `gc convoy land <id>` (`doConvoyLandJSON`, `:1737-1823`): requires `Type=="convoy"` (`:1749`)
  and the `"owned"` label (`:1753-1756`); idempotent if already terminal (`:1759-1765`); **gates on
  open children** — `if len(openChildren) > 0 && !opts.Force` prints each and errors *"Use --force to
  land anyway"* (`:1774-1788`); `--dry-run` previews (`:1791-1798`); else closes via
  `convoyLandCloseReason = "convoy land: completed owned convoy"` (`:1801`), records `ConvoyClosed`
  (`:1806-1810`), surfaces `convoy.notify` (`:1813-1821`). (The manual `gc convoy close` can close
  *any* convoy regardless of children — operator override.)

> **`land` does NO git / worktree / PR / merge work** — despite "terminate + cleanup" wording in its
> help, the body only closes the bead, records the event, and reports notify (`:1800-1821`, read in
> full). The *actual* merges are the refinery's job; `land` is purely a bead-state terminator with a
> children-closed gate.

**Which fits gated delivery** (work delivered → operator approval → refinery merges each PR → wrapper
lands only when all merged): **OWNED.** Under close-on-merge a child bead stays *open* until its PR
merges. A non-owned wrapper would be torn down opportunistically by the best-effort on-close hook the
moment the last child closes — with no operator step, and the hook *swallows all errors* (`:1896`).
Owned suppresses exactly that (`:1521-1523`, `:1927`), keeping the wrapper open and under deliberate
control, and `land` gives the refinery one explicit, auditable terminal action whose all-children gate
(`:1781`) succeeds without `--force` *precisely* when every PR has merged. (Non-owned auto-close is
*viable* if you want zero-ceremony teardown — it never closes early in the all-merged sense — but you
lose the gate, the dry-run, and the notify-on-land.)

### A2 — Target branch; 1:1 to a PR? aggregate (S2) vs tracker (S1)

`gc convoy target <id> <branch>` (`newConvoyTargetCmd`, `:1130-1145`) sets the convoy's `target`
**metadata** (`doConvoyTargetJSON` → `setConvoyFields`). Help: *"Child work beads can inherit this
target branch when slung with feature-branch formulas such as mol-polecat-work"* (`:1137-1138`). The
key is deliberately **unprefixed** (`"target"`, not `convoy.target`) *"so work beads can read their
own value directly, while still inheriting it from convoy ancestors during sling"*
(`internal/convoy/convoy_fields.go:30-32`).

**A convoy does NOT map 1:1 to a branch/PR.** There is **no PR/branch object on the convoy at all** —
no PR number, no branch creation, no merge anywhere in `internal/convoy/` or `land`. The convoy holds
at most one `target` *branch-name string* plus a set of `tracks` edges to children.

- **(S2) one aggregate integration branch:** *possible by convention but weakly wired.* There is **no
  `integration/<convoy-id>` auto-derivation in code** (grep across `cmd/`+`internal/`: zero matches;
  the string is help-text only at `cmd_convoy.go:113`). The generic inheritance that exists is the
  sling target walk (`BeadMetadataTarget`, `sling.go:851-878`) → but it is broken for `tracks`
  membership (A3). To run S2 you must stamp each child's own `metadata.target = integration/<id>` and
  add a separate integration→main graduation bead.
- **(S1) tracker over many independent PRs:** *the natural fit, nothing precludes it.* The convoy has
  no branch identity; children are arbitrary beads joined by additive `tracks` edges that "do not
  disturb" each child's own parent/epic (`sling_core.go:576-581`). Each child owns its own PR to its
  own target. Progress is pure bead-status aggregation (`convoyProgressFromChildren` /
  `list` / `status`), i.e. a many-PR progress + gating view.

### A3 — Membership / deps: the propagation gotcha and the correct wiring

A bead joins a convoy via a **`tracks` dependency**: `TrackingDepType = "tracks"`
(`membership.go:11-12`); `TrackItem` does `store.DepAdd(convoyID, itemID, "tracks")` *"without
changing itemID's parent-child relationship"* (`:22-32`). `Members` reads both tracks and *legacy*
parent-child children (`:64-92`).

**The gotcha is CONFIRMED, and it is an asymmetry:**

| Mechanism | Follows `tracks`? | Follows parent-child? | Evidence |
|---|---|---|---|
| Progress / **autoclose** / **stranded** / **land** (completion detection) | **YES** | yes | `autocloseConvoyIfComplete` via `TrackingConvoysForItem` (`cmd_convoy.go:1913`); `Members` (`membership.go:68-92`) |
| **Target / routing inheritance** (sling target walk) | **NO** | yes (only) | `BeadMetadataTarget` advances via `beadID = b.ParentID` only (`sling.go:875`); accepts a convoy ancestor's `target` only on that parent chain (`:870-873`) |

So the convoy *sees* its tracked children for completion, but a tracked child does **not** inherit the
convoy's `target` (the walk never traverses the `tracks` edge to reach the convoy). `BeadMetadataTarget`
feeds `SlingFormulaTargetBranch` as resolution priority #1, so a tracks-only child silently falls
through to the rig default branch instead of the convoy's target.

**Correct wiring** (given the asymmetry):
- For a **many-PR tracker (S1)** — you don't need target inheritance; plain `tracks` membership
  (`gc convoy add` / auto-convoy) is correct and clean. Completion/land work over `tracks`.
- For a **one-branch aggregate (S2)** — **stamp `metadata.target` directly on each child bead**
  (`bd update <child> --set-metadata target=integration/<id>`). The `beadID == rootID` branch
  (`sling.go:871`) returns the bead's *own* target with no ancestor walk — exactly the "read their own
  value directly" path the convoy_fields comment intends. (Re-parenting children under the convoy
  would also work but evicts their epic parent and corrupts epic rollups — which is *why* auto-convoy
  uses `tracks`, `sling_core.go:576-580`.)

### A4 — Completion semantics: does auto-close == "all merged"?

The "all children closed" test is identical in all three closure paths and tests **bead status only**:

```
allClosed := true
for _, ch := range children {
    if !convoycore.IsTerminalStatus(ch.Status) { allClosed = false; break }
}
```
(`gc convoy check` `cmd_convoy.go:1532-1538`; on-close hook `:1935-1939`; `land`'s open-children
collection `:1774-1779`). Children come from `listConvoyChildren(..., true)` (includes closed);
empty convoys are guarded (`:1529-1531`). The predicate is `IsTerminalStatus(status) = status ==
"closed" || status == "tombstone"` (`membership.go:18-20`); unresolved/dangling tracks get synthetic
status `"unknown"` → **non-terminal**, so a convoy with a dangling member never auto-closes.

**Under close-on-merge, does that mean "all children MERGED"?** The convoy code has **no concept of
merged-vs-delivered** — no PR field, no merge check (verified across `internal/convoy/` and
`check`/`autoclose`/`land`). The equivalence "convoy complete == all children merged" therefore holds
**iff** close-on-merge guarantees a child reaches `closed` exactly when its PR merges. The convoy
inherits that meaning entirely from *how/when children are closed*; if a child is closed for any other
reason (abandoned, deduped, manually closed) the convoy still counts it complete and auto-closes/lands.
**This is the load-bearing dependency:** the "land when all merged" guarantee rests entirely on the
close-on-merge discipline (the merge-detection pass from tk-mt1ey), not on the convoy.

### A5 — Dispatch interaction: stranded, and does the wrapper create pool demand?

**`gc convoy stranded`** (`doConvoyStrandedAcrossStoresJSON`, `:1607-1643`) — *"finds open convoys with
open children that have no assignee."* Predicate: for each open convoy (`collectOpenConvoys`), each
child that is **not** an unresolved tracked item (`:1636`) and is `!IsTerminalStatus && Assignee == ""`
(`:1639-1640`) is reported. It is a **read-only report**, not a scheduler input — it does not spawn
workers.

**Does an OPEN convoy bead read as pool demand?** The scale-from-zero / pool-demand probe is
`bdReadyPoolDemandShell` (`internal/config/config.go:3412-3413`):
```
bd ready ... --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic --json ...
```
Three filters decide membership: `gc.routed_to == <pool>`, `--unassigned`, `--exclude-type=epic`
(plus `bd ready` ⇒ open + not-blocked).

- **The convoy bead itself: NO demand.** Neither `gc convoy create` nor the sling auto-convoy ever
  stamps `gc.routed_to` on the convoy bead (`gc.routed_to` is set only on the slung *work* bead). The
  convoy simply doesn't match the `gc.routed_to=$target` selector — **regardless of open/closed
  status.** This is the decisive filter, so keeping a wrapper convoy open is safe.
- **The hazard to design around:** `--exclude-type=epic` will **not** save you if a convoy ever *were*
  routed. Convoy is a `containerType` (`beads.go:148-152`, batch-expansion grouping) but is **absent
  from `readyExcludeTypes`** (`:173-187` lists merge-request/gate/molecule/step/message/session/
  agent/role/rig — *not* convoy). So a routed, open, unassigned convoy would read as spurious demand
  and could trigger a phantom scale-from-zero spawn. **Rule: never stamp `gc.routed_to` on the
  wrapper convoy.** (If a future design must route the convoy, add `convoy` to the exclude set first.)
- **The open children create demand exactly as intended** — each carries its own `gc.routed_to` once
  slung. The wrapper does not interfere.

### A6 — Auto-convoy on sling, and the "id no default" bug

**Every plain (`!IsFormula`) sling auto-creates a convoy** unless `--no-convoy`
(`internal/sling/sling_core.go:544-589`): it `Create`s a `Type:"convoy"` bead titled `sling-<beadID>`
(`:567-571`), adds the `"owned"` label iff `--owned` (`:563-566`), and links via a **`tracks`** dep
(`TrackItem`, `:581`) — *"instead of parent-child so the bead's existing parent (e.g. its epic) is
preserved"* (`:576-580`). The id is the real store-generated `convoy.ID`, printed only when non-empty
(`cmd_sling.go:700`, `if result.ConvoyID != ""`).

**The "id no default" bug** is real, but it is a **Dolt schema defect, now fixed + regression-tested —
not a convoy design property.** Per the regression test
(`internal/sling/sling_test.go:2968-2972`): *"`Field 'id' doesn't have a default value` on
`dependencies.id`: Dolt strips `DEFAULT (uuid())` when migration 0043 runs via PREPARE/EXECUTE,
causing every `DepAdd` to fail silently via MetadataErrors."* Because it breaks **all** `DepAdd`, it
took out the auto-convoy's tracks link → empty `ConvoyID` (soft failure appended to `MetadataErrors`,
sling still succeeds; `sling_core.go:581-587`, and the failure-injection test `:2950-2965`).
`TestFinalizeAutoConvoyTracksDepCreated` (`:2973-3008`) now asserts the dep is created with no metadata
errors.

**Does it impede deliberate convoy use?** No, *given the fix is in your build* — and it never was
convoy-specific (it hit every dependency). **Verify the adopted `gc` build carries the migration-0043
fix.** The one genuine friction for deliberate convoy use is unrelated: a plain work-bead sling
*always* spins up a throwaway `sling-<bead>` auto-convoy in addition to any convoy you explicitly
manage. Pass `--no-convoy` on those slings and attach children to your explicit convoy via `gc convoy
add`, or accept a second (inert) convoy per bead.

---

## (B) Taxonomy resolved: convoy vs workflow vs v2-formula-DAG

| | **Convoy** | **Workflow** (= "v2-formula DAG") |
|---|---|---|
| What it is | A grouping of **work beads** toward an optional target branch, with a close/land lifecycle | The compiled bead **execution graph** of a v2 formula, driven by control beads |
| Bead identity | First-class `Type:"convoy"` bead (`cmd_convoy.go:308`, type-guarded `:1749`) | A bead marked `gc.kind=workflow` **or** `gc.formula_contract=graph.v2` (`internal/sourceworkflow/sourceworkflow.go:73-76`); members share `gc.root_bead_id`; traces to `gc.source_bead_id` |
| Membership edge | `tracks` dep (`membership.go:11-12,24-32`) | compiled dep graph (`blocks`/`waits-for`/…) under a root |
| Managed by | lifecycle subcommands: create/list/status/target/add/close/check/stranded/land | dispatch subcommands: control/delete/delete-source/reopen-source |
| Created by | `gc convoy create` / sling auto-convoy | pouring a `contract="graph.v2"` formula |

**Is `gc workflow` a real command?** It is a **registered-but-HIDDEN, DEPRECATED alias of
`gc convoy`** — wired into root at `cmd/gc/main.go:289` (`newWorkflowCmd`, alongside `newConvoyCmd`
at `:268`), defined at `cmd_convoy_dispatch.go:47-56`: `Use:"workflow"`, `Short:"Alias for gc convoy
(deprecated)"`, `Hidden:true`. It is a **partial** alias — it attaches *only* the dispatch
subcommands (`convoyDispatchSubcommands(...)`, `:54` / `:37-45` = control/poke/delete/delete-source/
reopen-source), **not** the convoy lifecycle subcommands. So `gc workflow control|delete|…` exist;
`gc workflow create|land|…` do not. (The *concept* "workflow" is not deprecated — only the command
spelling. Internally `gc.kind=workflow` is itself the "legacy" marker relative to
`gc.formula_contract=graph.v2`, `sourceworkflow.go:68-72`.)

**What is a workflow / v2-formula-DAG concretely?** A v2 formula (`Contract = "graph.v2"`) compiles,
when slung, into a bead DAG whose root is a *workflow root* (`IsWorkflowRoot`, `sourceworkflow.go:73-76`).
The DAG is advanced by **control beads** (kinds `check`/`drain`/`fanout`/`retry-eval`/`scope-check`/
`workflow-finalize`/`retry`/`ralph` — `internal/graphroute/graphroute.go:60-69`), processed by the
control dispatcher (`gc convoy control [--serve]`, `cmd_convoy_dispatch.go:58-91`), not by an agent.
A **source bead** is the originating request the workflow was spawned from (`gc.source_bead_id`);
`delete-source`/`reopen-source` operate on it.

**How they relate: DISJOINT.** A workflow does **not** wrap convoys and a convoy does **not** compile
into a workflow — different bead type, different membership edge, different lifecycle, different
command family. The convoy help asserts it (*"The convoy lifecycle subcommands … do not operate on
workflow roots; the dispatch subcommands … manage workflow trees"*, `cmd_convoy.go:54-60`) and the
code enforces it: lifecycle ops type-guard on `Type=="convoy"` (`:1749`, etc.) so they cannot touch a
workflow root (which is not convoy-typed); dispatch ops resolve via `IsWorkflowRoot`/`gc.root_bead_id`
and never via the `tracks`/convoy machinery. The only contact point is data-level (a `drain` step may
take an input convoy and emit per-item "unit convoys") — a workflow *consuming/producing* convoys, not
nesting.

---

## (C) Recommendation

**Our delivery wrapper under close-on-merge is the OWNED CONVOY. Do not use the workflow/DAG** — it is
the formula-execution graph, orthogonal to delivery, and `gc workflow` is a deprecated alias anyway.

This composes cleanly with the tk-mt1ey close-on-merge model: that work keeps each **per-PR anchor**
(the work bead) open until its PR merges; the **convoy** is the higher-level grouping *across* those
anchors that "lands when all merged." Critically, **the convoy needs NO core change** to deliver
"land when all merged" — the semantic is produced by close-on-merge (child close == PR merge) flowing
through the convoy's existing children-closed predicate (A4). This keeps the whole effort
**pack/usage-scoped with no gascity-core fork**, consistent with tk-mt1ey's conclusion.

**Mechanics to rely on:**
- **Owned lifecycle** (`--owned` → `gc convoy land`): exempt from both auto-closers (`:1521`, `:1927`),
  stays open through review/merge, lands via one explicit gated action (`:1781`) with dry-run + notify.
  The refinery is the natural lander (it already owns the merges) — `land` after its last merge closes
  the wrapper, and its all-children gate is a free correctness check that every PR merged.
- **`tracks` membership** for progress/autoclose/stranded/land (works over tracks).
- **Completion = bead-status only** (`IsTerminalStatus`) — lean on it, but know the integrity of "all
  merged" lives in the close-on-merge merge-detection pass, not the convoy.

**Gotchas / wiring to get right:**
1. **Target inheritance is broken for `tracks` membership** (parent-chain only, `sling.go:875`). Pick
   the shape deliberately: **S1 many-PR tracker** (recommended — each child → own PR → main; no
   inheritance needed) or **S2 one integration branch** (stamp `metadata.target` per child + add a
   graduation bead). Do **not** assume a tracked child inherits the convoy's `target`.
2. **Never route the wrapper:** keep `gc.routed_to` off the convoy bead (it is not epic-excluded,
   `beads.go:177-187`). Open wrapper = zero spurious demand today; preserve that invariant.
3. **Verify the migration-0043 / `dependencies.id` Dolt fix** is in the adopted build, else convoy
   membership (`DepAdd`) silently no-ops into `MetadataErrors` (`sling_test.go:2968-2972`).
4. **Suppress per-sling auto-convoys** (`--no-convoy`) when you manage an explicit convoy, or accept a
   second inert `sling-<bead>` convoy per work bead.
5. **`land` does no merging** — wire the actual merges through the refinery; treat `land` purely as the
   gated terminal bead-state flip + notify.

**Recommended default:** an **owned convoy as a many-PR tracker (S1)**, children added via `tracks`,
each child a close-on-merge per-PR anchor, the refinery calling `gc convoy land` after its final merge.
S2 (one integration branch) only when the deliverable genuinely needs a single aggregate PR — and then
budget the per-child target stamping + graduation bead.

---

## Evidence appendix (file:line — core root `/home/zook/loomington/rigs/gascity`)

**Convoy command & flags** — `cmd/gc/cmd_convoy.go`
- `:51-60` help (convoy = tracks-graph; "distinct from workflows"); `:71-83` subcommand registration
- `:139-145` create flags (`--merge` direct/mr/local `:141`; `--target` "inherited by child work beads" `:142`; `--owned` "manual lifecycle, no auto-close" `:143`)
- `:308-311` create: `Type:"convoy"`; `if opts.Owned { b.Labels = []string{"owned"} }`
- `:1130-1138` `target` cmd ("Child work beads can inherit this target branch … mol-polecat-work")

**Auto-close (non-owned)** — `cmd/gc/cmd_convoy.go`
- `:1512-1565` `gc convoy check`; skip owned `:1521-1523`; empty guard `:1529-1531`; predicate `:1532-1538`; close `:1540`
- `:1894-1924` bd on-close hook `doConvoyAutocloseWith` (parent `:1905-1911` + tracking convoys `:1913-1923`)
- `:1926-1939` `autocloseConvoyIfComplete`: skip non-convoy/terminal/**owned** `:1927`; per-child terminal check `:1935-1939`

**Owned / land** — `cmd/gc/cmd_convoy.go`
- `:1737-1823` `doConvoyLandJSON`: require convoy `:1749`; require owned `:1753-1756`; idempotent `:1759-1765`; open-children gate `:1774-1788`; dry-run `:1791-1798`; close `:1801`; event `:1806-1810`; notify `:1813-1821` — **no git/merge**
- `:1607-1643` `stranded` (open convoy + non-terminal child + empty assignee; read-only report)

**Membership / completion / target** — `internal/convoy/`
- `membership.go:11-12` `TrackingDepType="tracks"`; `:18-20` `IsTerminalStatus` (closed||tombstone); `:22-32` `TrackItem` (tracks dep, preserves parent); `:64-92` `Members` (tracks + legacy parent-child)
- `convoy_fields.go:16-17` `Merge`/`Target` fields; `:30-32` target unprefixed (own-value + ancestor inherit)

**Sling: target walk, auto-convoy, the Dolt bug** — `internal/sling/`
- `sling.go:851-878` `BeadMetadataTarget` — parent-chain walk; accept `:870-873`; `beadID = b.ParentID` `:875` (the gotcha)
- `sling_core.go:544-589` auto-convoy (cond `:545`; owned `:563-566`; create `:567-571`; tracks `:576-581`; soft-fail `:581-587`)
- `sling_test.go:2968-2972` "id no default" Dolt migration-0043 defect (all `DepAdd` fail); `:2973-3008` fix regression test; `:2950-2965` failure-injection test
- `cmd/gc/cmd_sling.go:700` "Auto-convoy %s" printed only when `ConvoyID != ""`

**Pool-demand / dispatch** — `internal/config/config.go`, `internal/beads/beads.go`
- `config.go:3412-3413` `bdReadyPoolDemandShell` (`gc.routed_to=$target --unassigned --exclude-type=epic`); `:3424-3425` legacy migration shell
- `beads.go:148-152` `containerTypes{"convoy":true}` (batch-expansion); `:173-187` `readyExcludeTypes` (**no convoy**)

**Workflow / dispatch taxonomy**
- `cmd/gc/main.go:268` `newConvoyCmd`, `:289` `newWorkflowCmd` (both root-registered)
- `cmd/gc/cmd_convoy_dispatch.go:37-45` `convoyDispatchSubcommands`; `:47-56` hidden deprecated `workflow` alias (dispatch subcommands only); `:58-91` `control [--serve]`
- `internal/sourceworkflow/sourceworkflow.go:68-76` `IsWorkflowRoot` (`gc.kind=workflow` OR `gc.formula_contract=graph.v2`; legacy-marker note)
- `internal/graphroute/graphroute.go:60-69` `IsControlDispatcherKind` (control-bead kinds)

**Prior research** — `specs/tk-6d0vb.1/why-close-at-submit.md` (tk-mt1ey): close-on-merge is a pack
formula change, not a core fork; only core coupling is pool-demand (keep open anchor assigned/unrouted).
