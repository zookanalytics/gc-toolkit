# GROUND-TRUTH map — Convoy + Refinery + Bead, as the code/formulas/help text actually define them

**Bead:** tk-uy7tc (research for tk-6d0vb.1) · **Author:** polecat gc-toolkit.furiosa · **Date:** 2026-06-22
**Method:** READ-ONLY. Every load-bearing line was read first-hand in the source. ZERO inference, ZERO
recommendations. Where a behavior is not determined by code/formula text, it is listed under
**UNKNOWN / SILENT** rather than filled in.

This deliberately supersedes the inference in the prior study (tk-zflam,
`specs/tk-6d0vb.1/convoy-workflow-mechanics.md`), whose **core convoy-mechanics citations are accurate**
but which (a) **recommended** a usage model ("S1 many-PR tracker is the natural fit") and (b) **never read
the refinery formula**, where the integration-branch + graduation flow actually lives. This map reports
that flow as-is.

## Source layers (three, not two)

The bead asked for `[CORE]` vs `[GASTOWN]`. Ground truth requires splitting the pack layer in two,
because the integration-branch/graduation behavior is defined partly in the base pack and partly in this
town's local delta. Tags used below:

| Tag | What | Root read | Pin / HEAD |
|---|---|---|---|
| `[CORE]` | the `gc` binary (Go) | `/home/zook/loomington/rigs/gascity` | git HEAD `fad2c2580` |
| `[GASTOWN-BASE]` | imported base gastown pack | `/home/zook/.gc/system/packs/gastown` | `sha:4212acb7046c11f6f633df73307006493185233a` (from `pack.toml [imports.gastown]`) |
| `[GC-TOOLKIT]` | this town's pack (this repo) | the gc-toolkit pack repo | refinery formula `formulas/mol-refinery-patrol.toml` (1172 lines), `template-fragments/` |

`[GASTOWN-BASE]` + `[GC-TOOLKIT]` together are the bead's "[GASTOWN]" (pack-layer) usage. The bead's
line hints (`mol-refinery-patrol.toml` ~:465-469, ~:1126-1142) resolve to the **`[GC-TOOLKIT]`** 1172-line
formula, not the 777-line base formula.

---

## 1. BEAD lifecycle `[CORE]`

### 1.1 Statuses

- **The `gc` Bead model carries 3 statuses.** `[CORE]` `internal/beads/beads.go:53` —
  `Status string \`json:"status"\` // "open", "in_progress", "closed"`. The Bead doc comment is
  `internal/beads/beads.go:48-49` ("Everything is a bead: tasks, mail, molecules, convoys").
- **The underlying bd ledger has a wider set, projected down to those 3.** `[CORE]`
  `internal/beads/bdstore.go:753-765` `mapBdStatus`: comment states *"bd uses: open, in_progress,
  blocked, review, testing, closed. Gas City uses: open, in_progress, closed."* The switch returns
  `closed`→`closed`, `in_progress`→`in_progress`, **everything else →`open`** (`:762-763 default`).
- **The bd-layer "open/ready" statuses enumerated in core.** `[CORE]`
  `internal/beads/native_dolt_store.go:56-64` `nativeDoltOpenReadyStatuses = { StatusOpen, StatusBlocked,
  StatusDeferred, "pinned", "hooked", "review", "testing" }` — i.e. `blocked/deferred/pinned/hooked/
  review/testing` are bd statuses that the native store treats within the open/ready projection.
- **Terminal predicate for convoy completion.** `[CORE]` `internal/convoy/membership.go:18-20`
  `func IsTerminalStatus(status string) bool { return status == "closed" || status == "tombstone" }`.

### 1.2 Transitions

- **No state machine / no transition validation found in the core beads layer.** Status is written
  directly. The update surface is an arbitrary string pointer: `[CORE]` `internal/beads/beads.go`
  `UpdateOpts.Status *string` (set status; nil = no change). See **UNKNOWN/SILENT**.

### 1.3 What `closed` means; `tombstone`

- `closed` is one of the two statuses `IsTerminalStatus` counts as terminal (`membership.go:18-20`).
- **`tombstone` is recognized as terminal but core has no writer that produces it.** `[CORE]` grep of
  `cmd/` + `internal/` for `"tombstone"` returns only `internal/convoy/membership.go:19` (the predicate
  itself) and test files (`cmd/gc/cmd_convoy_test.go:985`, `internal/convoy/convoy_test.go:177`,
  `cmd/gc/molecule_autoclose_test.go:160`, `internal/api/handler_convoys_test.go:287`). The synthetic
  status for a dangling tracked item is **`"unknown"`, not `tombstone`** — `[CORE]`
  `internal/convoy/membership.go:14` `const trackedStatusUnknown = "unknown"`, returned by
  `unresolvedTrackedItem` (`:117-124`), and `"unknown"` is **non-terminal**.

### 1.4 Who/what can close a bead

- **Store-level close.** `[CORE]` `internal/beads` `Store.Close(id) error` — *"sets a bead's status to
  'closed' … Closing an already-closed bead is a no-op."* `BdStore.Close` resolves a `close_reason` from
  metadata and delegates to a `bd close` subprocess with an honesty re-read guard
  (`internal/beads/bdstore.go` `close()` — re-reads after `bd close` and errors if status is not
  `closed`, citing the gastownhall/beads#3948 import-revert race). `MemStore.Close`
  (`internal/beads/memstore.go`) flips the in-memory status and is idempotent.
- **`gc bd close` CLI path.** `[CORE]` `cmd/gc/cmd_bd.go` recognizes `close` with flags
  `-r/--reason/--reason-file/--session`, `--claim-next/--continue/-f/--force/--no-auto/--suggest-next`.
- **On-close hook chain (controller, not the store).** `[CORE]` `cmd/gc/api_state.go:567-580`
  `runBeadCloseAutoclose` — on a bead.closed event the controller dispatches
  `doConvoyAutocloseWith` + `doWispAutocloseWith` + `doMoleculeAutocloseWith`. Comment: *"Replaces the
  shell on_close hook chain that spawned gc subprocesses per bead write (gastownhall/gascity#3248)."*
  Default dispatch is a background goroutine (`api_state.go` `beadCloseAutocloseDispatch`).
- **No auth/permission gating** on close was found in the core beads layer. See **UNKNOWN/SILENT**.

### 1.5 PR ownership in core

- **Core beads have no PR concept.** `[CORE]` There is no PR field on the `Bead` struct
  (`internal/beads/beads.go:50-`). PR identity exists only as a *metadata key string* used by higher
  layers: `[CORE]` `internal/beadmeta/keys.go` `PRURLMetadataKey = "gc.pr_url"`. No merge-state or
  merge-detection logic exists in `internal/beads`.

---

## 2. CONVOY `[CORE]`

### 2.1 What a convoy IS

- **A first-class bead `Type:"convoy"`.** `[CORE]` created with `Type: "convoy"` by both
  `gc convoy create` (`cmd/gc/cmd_convoy.go:308-310`) and the sling auto-convoy
  (`internal/sling/sling_core.go:567-571`). All lifecycle ops type-guard on `convoy.Type != "convoy"`
  (e.g. `cmd_convoy.go:1749`).
- **`ConvoyFields` — the entire structured metadata of a convoy.** `[CORE]`
  `internal/convoy/convoy_fields.go:12-18`:
  ```
  Owner    string // who manages this convoy
  Notify   string // notification target on completion
  Molecule string // associated molecule ID
  Merge    string // merge strategy: "direct", "mr", "local"
  Target   string // target branch inherited by child work beads
  ```
  Metadata keys (`:26-32`): `convoy.owner`, `convoy.notify`, `convoy.molecule`, `convoy.merge`, and
  **`target` (intentionally UNPREFIXED)** — comment `:30-31`: *"target is intentionally unprefixed so
  work beads can read their own value directly, while still inheriting it from convoy ancestors during
  sling."*
- **There is NO integration-branch field, NO PR field, NO branch-identity field on a convoy.** The only
  branch-related field is `Target` (a branch-name *string*). Verified by reading the full
  `convoy_fields.go`. A convoy carries no PR number and creates no branch.

### 2.2 How beads JOIN a convoy

- **Membership edge = a `tracks` dependency.** `[CORE]` `internal/convoy/membership.go:11-12`
  `const TrackingDepType = "tracks"`. `TrackItem` does `store.DepAdd(convoyID, itemID, "tracks")`
  *"without changing itemID's parent-child relationship"* (`:22-32`).
- **`Members` reads BOTH `tracks` deps AND legacy parent-child children.** `[CORE]`
  `internal/convoy/membership.go:64-115` (legacy `ParentID` children `:69-73`, then `tracks` deps
  `:94-111`). Unresolved tracks deps are returned with status `"unknown"` (`:104-105`, `:117-124`).
- **`TrackingConvoysForItem`** (`:146-175`) walks `up` deps and returns only `Type=="convoy"` trackers
  (type-guard `:167`).

### 2.3 Completion predicate

- **All three closure paths test bead STATUS only**, via `IsTerminalStatus` (closed||tombstone):
  `gc convoy check` (`cmd_convoy.go:1534`), the on-close hook (`:1936`), and `gc convoy land`'s
  open-children scan (`:1776`). Empty convoys are guarded against (no children → not closed). There is
  **no merge awareness** anywhere in `internal/convoy/` or in check/autoclose/land.

### 2.4 The TWO lifecycles

**(a) AUTO-CLOSE (default; convoy with no `"owned"` label).** Two automatic closers, identical predicate:
- **`gc convoy check`** — `[CORE]` `doConvoyCheckAcrossStoresJSON` (`cmd_convoy.go:1512`); **skips owned**
  `if hasLabel(item.bead.Labels, "owned") { continue }` (`:1521`); per-child terminal check (`:1534`);
  closes with reason `convoyAutocloseReason` (`:1540`).
- **bd on-close hook** — `[CORE]` `doConvoyAutocloseWith` (`cmd_convoy.go:1898`) reaches the convoy via
  the closed bead's parent **and** its tracking convoys, then `autocloseConvoyIfComplete` (`:1926`):
  `if convoy.Type != "convoy" || IsTerminalStatus(convoy.Status) || hasLabel(convoy.Labels, "owned") {
  return }` (`:1927`); per-child terminal (`:1936`); close (`:1941`).
- Close reason constant: `[CORE]` `cmd_convoy.go:1469`
  `convoyAutocloseReason = "convoy autoclose: all children closed"`.

**(b) OWNED (`"owned"` label).** Both auto-closers skip it (`:1521`, `:1927`). Terminator is
`gc convoy land`.

### 2.5 EXACTLY what `gc convoy land` does — and does NOT do

`[CORE]` `doConvoyLandJSON` `cmd/gc/cmd_convoy.go:1737-1823` (read in full):
- requires `Type=="convoy"` (`:1749-1752`);
- **requires the `"owned"` label** — refuses non-owned: `"convoy %s is not owned (missing 'owned'
  label)"` (`:1753-1756`);
- idempotent if already terminal (`:1759-1765`);
- **gates on open children** unless `--force`: collects non-terminal children (`:1774-1779`), and
  `if len(openChildren) > 0 && !opts.Force` prints them + *"Use --force to land anyway"* and returns 1
  (`:1781-1788`);
- `--dry-run` previews counts (`:1791-1798`);
- otherwise **closes the convoy bead** via `closeConvoyWithReason(..., convoyLandCloseReason)` (`:1801`;
  reason constant `:1473` = `"convoy land: completed owned convoy"`);
- records `events.ConvoyClosed` (`:1806-1810`);
- emits a notify line from `ConvoyFields.Notify` (`:1813-1821`).

> **`gc convoy land` performs NO git, NO worktree, NO PR, NO merge.** Its entire body is: validate →
> children gate → close the bead → record event → print notify. (`:1737-1823`, read line-by-line.)

### 2.6 The `--owned` exemption & events

- `--owned` adds the `"owned"` label at creation: `gc convoy create --owned`
  (`cmd_convoy.go:143` flag *"mark convoy as owned (manual lifecycle, no auto-close)"*; label applied
  `:308-310`) and `gc sling --owned` (`internal/sling/sling_core.go:563-566`; flag
  `cmd/gc/cmd_sling.go:147` *"mark auto-convoy as owned (skip auto-close)"*).
- The label is checked in exactly the two auto-closers (`:1521`, `:1927`) and required by land (`:1753`).
- Event `events.ConvoyClosed` is recorded on both autoclose and land paths.

### 2.7 Does a convoy have its own branch/PR identity? — NO

No PR number, no branch object, no merge anywhere in `internal/convoy/`, `gc convoy land`, `check`, or
`autoclose`. A convoy holds at most one `Target` *branch-name string* (`convoy_fields.go:17`) plus a set
of `tracks` edges.

### 2.8 Auto-convoy on sling

`[CORE]` `internal/sling/sling_core.go:544-589`:
- **every plain (`!IsFormula`) sling auto-creates a convoy** unless `--no-convoy`, guarded on the bead
  existing locally: `if !opts.NoConvoy && !opts.IsFormula && deps.Store != nil` (`:545`);
- `"owned"` label iff `--owned` (`:563-566`);
- `Create(Type:"convoy", Title: "sling-<beadID>")` (`:567-571`);
- linked via **`tracks`** (`TrackItem`, `:581`), with comment `:576-580`: *"Use a 'tracks' dep … instead
  of parent-child so the bead's existing parent (e.g. its epic) is preserved … the tracks dep is
  additive and does not disturb the epic rollup."*
- CLI guard: `--owned requires a convoy (cannot use with --no-convoy)` (`cmd/gc/cmd_sling.go:120`).

### 2.9 Target inheritance asymmetry (relevant to integration branches)

- **The sling target walk follows the PARENT-CHILD chain only.** `[CORE]`
  `internal/sling/sling.go:853` `func BeadMetadataTarget(...)`, advancing `beadID =
  strings.TrimSpace(b.ParentID)` (`:875`). It does **not** traverse the `tracks` edge.
- Consequence (fact, not inference): a child joined to a convoy by `tracks` (the auto-convoy path,
  `sling_core.go:581`) does not inherit the convoy's `target` via the walk; a child joined by
  **parent-child** does. The `[GC-TOOLKIT]` mayor fragment deliberately links children with
  `gc bd dep add "$WORK" "$CONVOY" --type=parent-child` (`template-fragments/convoy-integration-branch.template.md:26`)
  — see §3/§4.

---

## 3. REFINERY

### 3.1 Is "refinery" CORE or pack?

- **PACK, not core.** `[CORE]` The only functional reference to "refinery" in the `gc` binary is a
  formula-name guard: `internal/sling/sling.go:944` `func SlingFormulaUsesTargetBranch(formulaName
  string) bool { return formulaName == "mol-refinery-patrol" }`. A grep of `cmd/` + `internal/` for
  `refinery` returns 863 hits, but all others are comments/docs/agent-prompt strings — there is **no
  built-in refinery merge engine, no `gc refinery` command, no merge state machine** in core. The
  refinery is the `mol-refinery-patrol.toml` formula run by a refinery agent.

### 3.2 `[GC-TOOLKIT]` refinery formula (`formulas/mol-refinery-patrol.toml`, 1172 lines)

**Merge-strategy resolution** (`:430-462`):
- `MERGE_STRATEGY = metadata.merge_strategy // "{{default_merge_strategy}}"` (`:431`); empty →`direct`
  (`:436`); `pr`→`mr` normalization (`:456-457`); `existing_pr` present forces `mr` (`:459-461`).
- Var `[vars.default_merge_strategy]` default `"direct"` (`:69-71`) — **`[GC-TOOLKIT]` delta**; base
  hardcodes `"direct"` with no var.

**Integration-branch surface** (`[GC-TOOLKIT]` delta, `:464-471`) — comment `:464` literally says
*"gc-toolkit local delta"*:
```
case "$TARGET" in
  integration/*)
    echo "INFO: Merging $WORK to integration branch '$TARGET' (not {{target_branch}}). A graduation
    bead is required to land this work to {{target_branch}}; see 'gc convoy land' and the
    integration_branch_auto_land patrol step."
```
This branch only **prints** an INFO line. It does not change the merge path.

**How child work reaches the target (incl. an integration branch) — depends on merge_strategy:**
- **`direct`**: refinery fast-forward-merges and pushes to `$TARGET`, then **closes the work bead at
  merge**: `--set-metadata merge_result=merged / merged_sha / merged_target` then
  `gc bd close $WORK --reason "Merged to $TARGET at $MERGED_SHORT"` (`:752-756`). When `$TARGET =
  integration/<id>`, that push lands on the integration branch (`:467-471`).
- **`mr`**: `[GC-TOOLKIT]` `:808-811` — *"Refinery does NOT land the branch directly. Instead it
  publishes a pull request and treats PR creation as the terminal handoff for this work bead."* It
  pushes the rebased branch (`:813-816`) and opens a PR **into `$TARGET`**; if `review_gate="codex"` the
  PR is opened **as draft** and a review bead is dispatched (`[GC-TOOLKIT]` delta, `:830-832`). It then
  **closes the work bead at PR creation/ready**: `--set-metadata merge_result=pull_request / pr_url /
  pr_number / merged_target` then `gc bd close $WORK --reason "Pull request ready: $PR_URL"`
  (`:1064-1069`). Top-of-file restatement: *"In `mr` mode, refinery treats PR publication as the terminal
  handoff"* (`:26`).

> **Load-bearing fact for tk-6d0vb.1:** the current formula closes the work bead **at merge in `direct`
> mode** (`:756`) but **at PR creation/ready in `mr` mode** (`:1069`, `:811`, `:26`) — i.e. mr-mode close
> is NOT close-on-merge today; the bead closes when the PR is published, not when it merges.

**GRADUATION / `integration_branch_auto_land`** (`:1116-1144`):
- Var `[vars.integration_branch_auto_land]` default `"false"` (`:77-79`).
- Step text (`:1121-1144`): *"**1. Integration branch check (only if auto_land = "true"):** If the merge
  target was an integration branch, check if the parent owned convoy is now fully closed:
  `gc bd list --type=convoy --status=open` (`:1128`). For each owned convoy with an integration branch:
  if ALL children are closed, assign the convoy bead itself to you with the metadata needed for a merge:
  `gc bd update <convoy-id> --assignee=$GC_AGENT --set-metadata branch=<integration-branch> --set-metadata
  target={{target_branch}}` (`:1134-1136`). The next patrol iteration picks up the convoy like any other
  work bead and merges the integration branch to {{target_branch}} normally (`:1138-1139`)."*
- **FORBIDDEN** (`:1141-1142`): *"Landing integration branches via raw `git merge`/`git push`. The
  convoy bead assignment is the ONLY path."* If `auto_land="false"`: *"skip this entirely"* (`:1144`).
- **The refinery does NOT call `gc convoy land` in this path.** It assigns the convoy bead to itself as
  an ordinary work bead; the convoy bead is then merged + closed by the same merge path as any work bead
  (§3.2 direct/mr). `gc convoy land` is named only in the `:469` INFO echo string.

### 3.3 `[GASTOWN-BASE]` refinery formula (777 lines) — what it shares vs lacks

- **Graduation/integration logic is INHERITED FROM BASE** (not a gc-toolkit invention). `[GASTOWN-BASE]`
  `/home/zook/.gc/system/packs/gastown/formulas/mol-refinery-patrol.toml`: var
  `[vars.integration_branch_auto_land]` (`:72-73`) and the **identical** graduation step —
  `gc bd list --type=convoy --status=open` (`:733`), *"assign the convoy bead itself to you"* (`:736`),
  `gc bd update <convoy-id> --assignee=$GC_AGENT --set-metadata branch=… target=…` (`:739-740`), *"merges
  the integration branch to {{target_branch}} normally"* (`:743-744`), and the same **FORBIDDEN** raw
  merge / "convoy bead assignment is the ONLY path" (`:746-747`).
- **Present only in `[GC-TOOLKIT]` (deltas over base):** the `integration/*` INFO surface (`:464-471`),
  `[vars.default_merge_strategy]` (`:69-71`), `[vars.auto_ff_rig_main]` (`:85-87`), `[vars.review_gate]`
  codex draft-PR gate (`:89-91`, `:830-832`), and protected-branch auto-promotion. (Base hardcodes
  `direct` and opens PRs non-draft.)

---

## 4. COMPOSITION — one unit of work end to end (as defined by code + formula + fragments)

### 4.1 Where convoys are CREATED

- **Auto, on every plain sling** `[CORE]` — a **non-owned** `sling-<beadID>` convoy via `tracks`, unless
  `--no-convoy` (`internal/sling/sling_core.go:544-589`). `--owned` is opt-in.
- **`gc convoy create`** `[CORE]` (`cmd/gc/cmd_convoy.go:139-145`, create `:308-310`); `--owned` opt-in.
- **By the MAYOR, for integration-branch initiatives** `[GC-TOOLKIT]`
  `template-fragments/convoy-integration-branch.template.md` (injected into the mayor per
  `pack.toml [[patches.agent]] name="mayor"`): create `gc convoy create "<initiative>" --owned --target
  "integration/<convoy-id>"` (`:14-16`); push the integration branch with the shared artifact (`:18-22`);
  file child beads and link **parent-child** `gc bd dep add "$WORK" "$CONVOY" --type=parent-child`
  (`:26`); `gc sling` (`:27`). Anti-pattern called out: committing bead-local content directly to main
  (`:42-44`).
- **`[GASTOWN-BASE]`** also instructs owned-convoy creation in `formulas/mol-idea-to-plan.toml` (*"Use
  `gc convoy create "<initiative-name>" --owned`"*, ~`:435`).

### 4.2 OWNED or auto-close, in actual usage?

- **Integration-branch flows use OWNED convoys.** `[GC-TOOLKIT]` mayor fragment (`:11`, `:15`), polecat
  fragment (`template-fragments/polecat-convoys.template.md:2,5-6`), and the running formula's graduation
  step which iterates *"each owned convoy with an integration branch"* (`:1130`). Plain slings produce
  **non-owned** auto-convoys (`sling_core.go:563-566` only labels owned when `--owned`).

### 4.3 The end-to-end trace (integration-branch flow, as written)

1. **Mayor** `[GC-TOOLKIT]`: `gc convoy create --owned --target integration/<id>`; push
   `integration/<id>` with the shared artifact; file children **parent-child** under the convoy; sling
   (`convoy-integration-branch.template.md:14-27`).
2. **Target inheritance** `[CORE]`: children inherit `metadata.target = integration/<id>` via the
   parent-chain sling walk (`sling.go:853,875`) — works because the link is parent-child (§2.9).
3. **Polecat** `[GC-TOOLKIT]`: branches from `origin/integration/<id>`, implements, hands to refinery;
   *"main moves only when the convoy graduates"* (`polecat-convoys.template.md:13-18`).
4. **Refinery** `[GC-TOOLKIT]`: merges each child to its target (`= integration/<id>`) — `direct`
   ff-merge+push (`:752-756`) or `mr` PR-into-integration-branch (`:808-811`, `:1064-1069`) — and closes
   each child bead (at merge in direct, at PR-creation in mr; §3.2).
5. **Graduation** — two distinct described mechanisms; the code/formula define both, and which one runs
   is config-/operator-dependent:
   - **Refinery `auto_land="true"`** `[GASTOWN-BASE]/[GC-TOOLKIT]`: refinery detects the all-children-
     closed owned convoy, **assigns the convoy bead to itself** (`branch=integration/<id>`,
     `target=main`), and the next iteration merges integration→main as an ordinary work bead
     (`:1123-1139` / base `:730-744`). **Does not call `gc convoy land`.**
   - **Mayor/operator path** `[GC-TOOLKIT]`: *"file a graduation bead that squash-merges
     `integration/<convoy-id>` to main, then `gc convoy land <convoy-id>`"*
     (`convoy-integration-branch.template.md:34-35`).
6. **Where the actual git merge happens:** ONLY in the refinery formula (`git merge --ff-only` / `gh pr`
   / `git push`). `[CORE]` `gc convoy land` and the convoy package do NO git (§2.5).
7. **Where the bead close happens:**
   - child work beads → closed by the refinery formula after merge/PR (`:756` / `:1069`);
   - convoy bead → closed by the on-close hook / `gc convoy check` if **non-owned** (`[CORE]` §2.4); by
     `gc convoy land` if owned + mayor path (`[CORE]` §2.5); or by the refinery's normal merge-close when
     the owned convoy bead is assigned as a graduation work bead under `auto_land` (`[*-formula]` §3.2).

### 4.4 convoymaster

- **Not present in the running gastown pack.** `[GASTOWN-BASE]` `/home/zook/.gc/system/packs/gastown/
  agents/` contains only `boot, deacon, mayor, polecat, refinery, witness` — no `convoymaster`.
- It exists only as an **example** under `/home/zook/loomington/rigs/gascity/examples/t3bridge-gastown/
  packs/gastown/agents/convoymaster/` (its prompt opens *"You are a Gas Town convoymaster working through
  T3Code."*). It is not part of the operational system.

---

## 5. CONVOY vs EPIC `[CORE]`

- **Distinct bead types; only `convoy` is a first-class container.** `[CORE]`
  `internal/beads/beads.go:150-152` `var containerTypes = map[string]bool{ "convoy": true }` — `epic` is
  **absent**. `IsContainerType` (`:156-158`) is convoy-only.
- **`epic` is rejected by sling.** `[CORE]` `internal/sling/sling_core.go:1225-1226`:
  `if b.Type == "epic" { return SlingResult{}, fmt.Errorf("bead %s is an epic; first-class support is
  for convoys only", b.ID) }`.
- **`gc graph` demotes epics.** `[CORE]` `cmd/gc/cmd_graph.go:272-274`: *"epic %s is treated as an
  ordinary bead; convoy expansion is first-class"*; container expansion runs only for `IsContainerType`
  (`:275-276`).
- **Pool-demand probe excludes `epic`, not `convoy`.** `[CORE]` `internal/config/config.go:3413`
  `... --exclude-type=epic ...` (and `:3425` for the legacy form). `convoy` is **not** in
  `readyExcludeTypes` (`internal/beads/beads.go:177-187`) and **not** excluded by the probe — a routed,
  open, unassigned convoy would read as pool demand (no core code stamps `gc.routed_to` on a convoy; see
  UNKNOWN/SILENT).
- **Membership models differ.** `[CORE]` convoy = `tracks` deps (+ legacy parent-child) (`membership.go:
  11-12,64-115`); epic = parent-child via `ParentID`. There is **no epic autoclose** — autoclose is
  convoy-typed (`autocloseConvoyIfComplete` guards `convoy.Type != "convoy"`, `cmd_convoy.go:1927`).
- **Docs make the same split.** `[CORE]` glossary `engdocs/architecture/glossary.md:63-65`: *"**Epic**:
  An ordinary bead type used for tracking. Unlike convoy, epics are not first-class containers and are
  not expanded during dispatch. Children may still link via ParentID."*
- **The relationship is flagged OPEN.** `[CORE]` `examples/gastown/FUTURE.md:49`: *"`gc convoy list/
  check/stranded/create/status` — **OPEN:** Convoys sit in the same space as epics — batch coordination
  over related beads. Which layer do they belong in? Bead metadata? Molecules? Separate primitive?"*

---

## UNKNOWN / SILENT (the code/formulas do not determine these)

1. **What sets a bead to `tombstone`** — `[CORE]` no writer found; `tombstone` appears only in
   `IsTerminalStatus` (`membership.go:19`) and tests. The dangling-tracks synthetic status is `"unknown"`
   (non-terminal), not `tombstone`.
2. **Status-transition validation / a state machine** — `[CORE]` none found; status is an arbitrary
   string write (`beads.go UpdateOpts.Status`).
3. **Auth/permission gating on bead close** — `[CORE]` none found in the beads layer.
4. **Whether `integration_branch_auto_land` is ever `"true"` in this town** — both formulas default it to
   `"false"` (`[GC-TOOLKIT]:77-79`, `[GASTOWN-BASE]:72-73`); whether any poured refinery wisp overrides
   it is not determined by the formula text.
5. **Which graduation mechanism is canonical** — the refinery `auto_land` path (assign convoy bead to
   self, no `gc convoy land`) and the mayor path (graduation bead + `gc convoy land`) are BOTH defined;
   nothing read states which is used when, or how they interact if both fire.
6. **Whether a convoy bead ever carries `gc.routed_to`** — no core code stamps it; `convoy` is not in
   `readyExcludeTypes` (`beads.go:177-187`) and the pool probe excludes only `epic` (`config.go:3413`),
   so IF a convoy were routed it would read as demand — but nothing observed routes one.
7. **"Close-on-merge" for `mr` mode** — NOT implemented in the refinery formula read here: `mr` closes
   the work bead at PR creation/ready (`:1069`, `:811`), not at PR merge. Where (if anywhere) a
   close-at-actual-merge pass would live is not present in `[CORE]`, `[GASTOWN-BASE]`, or `[GC-TOOLKIT]`
   as read.
8. **`gc.pr_url` consumers** — `[CORE]` defines the key (`beadmeta/keys.go`) but core has no PR/merge
   logic; consumption is entirely pack/formula-layer.
9. **convoymaster behavior in production** — not applicable; it is example-only and absent from the
   running pack.

---

## Evidence index (roots: `[CORE]` `/home/zook/loomington/rigs/gascity` @ `fad2c2580`; `[GASTOWN-BASE]` `/home/zook/.gc/system/packs/gastown` @ `sha:4212acb`; `[GC-TOOLKIT]` this pack repo)

- **Bead model/status** `[CORE]` `internal/beads/beads.go:48-49,53`; `bdstore.go:753-765` (mapBdStatus);
  `native_dolt_store.go:56-64`; `convoy/membership.go:14,18-20,117-124`.
- **Bead close** `[CORE]` `internal/beads/bdstore.go` `close()`; `memstore.go` `Close`;
  `cmd/gc/cmd_bd.go` (close flags); `cmd/gc/api_state.go:567-580` (on-close autoclose dispatch);
  `internal/beadmeta/keys.go` (`gc.pr_url`).
- **ConvoyFields** `[CORE]` `internal/convoy/convoy_fields.go:12-18,26-32`.
- **Membership** `[CORE]` `internal/convoy/membership.go:11-12,18-20,22-32,64-115,146-175`.
- **Auto-convoy / sling** `[CORE]` `internal/sling/sling_core.go:544-589,1225-1226`;
  `cmd/gc/cmd_sling.go:120,146-147`; target walk `internal/sling/sling.go:853,875,944`.
- **Convoy create/flags** `[CORE]` `cmd/gc/cmd_convoy.go:139-145,308-310`.
- **Auto-close** `[CORE]` `cmd/gc/cmd_convoy.go:1469,1512,1521,1534,1540,1898,1926-1941`.
- **Land** `[CORE]` `cmd/gc/cmd_convoy.go:1473,1737-1823` (require owned `:1753`; children gate `:1781`;
  close `:1801`; event `:1806`; notify `:1813` — no git).
- **Refinery-not-core** `[CORE]` `internal/sling/sling.go:944`.
- **Refinery formula** `[GC-TOOLKIT]` `formulas/mol-refinery-patrol.toml:26,69-71,77-79,85-91,430-471,
  752-756,808-832,1064-1069,1116-1144`; `[GASTOWN-BASE]`
  `/home/zook/.gc/system/packs/gastown/formulas/mol-refinery-patrol.toml:72-73,726-747`.
- **Fragments** `[GC-TOOLKIT]` `template-fragments/convoy-integration-branch.template.md:11-44`;
  `template-fragments/polecat-convoys.template.md:2-18`; wiring `pack.toml [[patches.agent]]`.
- **Convoy vs epic** `[CORE]` `internal/beads/beads.go:150-152,156-158,177-187`;
  `internal/sling/sling_core.go:1225-1226`; `cmd/gc/cmd_graph.go:272-276`;
  `internal/config/config.go:3413`; `engdocs/architecture/glossary.md:63-65`;
  `examples/gastown/FUTURE.md:49`.
