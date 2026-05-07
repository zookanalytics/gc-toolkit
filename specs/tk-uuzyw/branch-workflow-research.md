---
name: Branch-based dispatch workflow — research
description: Survey of how polecat work currently flows through branches in gc-toolkit, gascity, and signal-loom; canonical pattern, gaps, and ranked lightweight adoption recommendations grounded in the 2026-05-06 shortcut incident (commit 7453fa4).
---

# Branch-based dispatch workflow — research (tk-uuzyw)

Foundation research for the adoption follow-up bead. Decision context: parent
`tk-w7mjt` (closed 2026-05-07) adopted **Option A** — cross-bead data sharing
flows through branches, squash-merged to main only when a unit of work is
ready, never via shortcut commits to main. Operator note: gc-toolkit holds an
intentionally low CI/pre-merge bar; adoption should be lightweight (docs +
small capability fixes), not heavy CI gates.

## Terminology addendum (added during adoption, 2026-05-07, tk-jkesf)

The original research used the new term **"dispatch branch"** with the
naming convention `dispatch/<convoy-or-bead-id>-<slug>`. Implementing
the recommendations surfaced an existing primitive the survey missed:
`gc convoy create --owned --target integration/<convoy-id>` is the
canonical CLI for the exact pattern this doc describes, and
`mol-refinery-patrol` already uses the term **"integration branch"**
with `integration/<convoy-id>` naming (see `integration_branch_auto_land`,
`gc convoy target`, and the refinery prompt's "Landing integration
branches" line).

Adoption therefore uses the existing term and convention. **Where this
doc says "dispatch branch" or `dispatch/<convoy-id>`, the implementation
reads "integration branch" or `integration/<convoy-id>`** — the pattern
itself survives unchanged. R5's proposed `gc dispatch …` subcommand is
also redundant with `gc convoy create --owned` and should stay deferred
on those grounds, not just cost grounds. The §2.2 search that found
"zero branches matching `dispatch/*`, `anchor/*`, `mechanik/*`, or
`convoy/*`" did not check `integration/*`; in practice, very few
convoys had exercised the path before this adoption, so the absence is
unsurprising regardless of naming.

## Provenance

| Doc-type or artifact | Producer (skill / formula / rig component) | Source location (path + commit SHA, or URL) | Surveyed at |
|---|---|---|---|
| `gc sling` dispatch command (Go source) | gc CLI (`cmd/gc`) | `/home/zook/gascity/cmd/gc/cmd_sling.go` @ `e937a08` | 2026-05-07 |
| Sling-time formula variable resolution | gc CLI internal sling package | `/home/zook/gascity/internal/sling/sling.go`, `internal/sling/sling_core.go` @ `e937a08` | 2026-05-07 |
| `mol-polecat-work` formula (TOML) | gastown pack formulas | `/home/zook/gascity/examples/gastown/packs/gastown/formulas/mol-polecat-work.toml` @ `e937a08` | 2026-05-07 |
| `mol-refinery-patrol` formula (TOML) | gastown pack formulas | `/home/zook/gascity/examples/gastown/packs/gastown/formulas/mol-refinery-patrol.toml` @ `e937a08` | 2026-05-07 |
| Bead metadata model (Go struct) | `internal/beads/beads.go` | `/home/zook/gascity/internal/beads/beads.go` @ `e937a08` | 2026-05-07 |
| Incident commit (the shortcut) | gc-toolkit rig main | `git show 7453fa4` in `rigs/gc-toolkit` (local `main` only — never reached `origin/main`) | 2026-05-07 |
| Parent decision (Option A adoption) | bead | `tk-w7mjt` (closed 2026-05-07) | 2026-05-07 |
| gc-toolkit rig contents | rig | `/home/zook/loomington/rigs/gc-toolkit/` @ `7453fa4` (local) | 2026-05-07 |
| gascity rig contents | rig | `/home/zook/loomington/rigs/gascity/` @ `c7cd79f` | 2026-05-07 |
| signal-loom rig contents | rig | `/home/zook/loomington/rigs/signal-loom/` @ `4019694` | 2026-05-07 |
| Recent gc-toolkit polecat branches (`tk-yiwfz.{4,6,7}`) | refinery (squash merges) | gc-toolkit `git log` (`7bdde6c`, `2f8840f`, `744e853`) | 2026-05-07 |

---

## 1. Current state — how dispatch flows today

### 1.1 The core flow

A polecat work item travels: **caller → bead → sling → polecat → refinery → main**.

1. **Caller** (mechanik, mayor, witness, operator) creates or queues a work bead.
2. **`gc sling`** (`cmd/gc/cmd_sling.go:53-141`) routes the bead to a target
   pool/agent. If the work needs a formula, sling pours the molecule with
   variables computed at sling time.
3. **Polecat** receives the bead, runs `mol-polecat-work`, sets up a worktree
   on a feature branch from the base, implements, then reassigns the bead to
   the refinery.
4. **Refinery** runs `mol-refinery-patrol`, rebases the polecat branch onto
   the merge target, and merges (or rejects with `rejection_reason`).

### 1.2 Where the base branch comes from

The base branch a polecat lands on is chosen by `gc sling` at pour time, not
by the polecat. The resolution order, codified in
`internal/sling/sling.go:788-796` (`SlingFormulaTargetBranch`):

1. `metadata.target` on the work bead, if set;
2. `metadata.target` on a convoy ancestor (root bead or any convoy parent)
   — see `BeadMetadataTarget` at `internal/sling/sling.go:725-750`;
3. otherwise the rig repo's default branch (`deps.Branches.DefaultBranch(...)`).

The resolved value is bound into the formula as the `{{base_branch}}`
template variable. The polecat then reads it from the molecule, does
`git worktree add ... origin/{{base_branch}}`, and records the new branch
in `metadata.branch` for crash recovery and refinery handoff
(`mol-polecat-work.toml:39-161`, `workspace-setup`).

### 1.3 Per-dispatch overrides — what exists and how it's used

`gc sling` accepts `--var key=value` to set formula variables, and for
`base_branch` the override **does work** — but is silently undocumented.

In `cmd/gc/cmd_sling.go:875-915` (`buildSlingFormulaVars`) and the
mirrored `internal/sling/sling.go:798-839` (`BuildSlingFormulaVars`), the
construction order is:

1. User `--var key=value` entries populate `vars` first
   (`cmd_sling.go:879-883`).
2. Auto-fill via `addVar(key, autoValue)` only writes if the key is
   *not* already explicitly set (`cmd_sling.go:884-892`):
   ```go
   if _, explicit := vars[key]; explicit {
       return
   }
   ```
3. Auto-fill computes `autoBranch :=
   slingFormulaTargetBranch(beadID, deps, a)` (the convoy-aware walk)
   and calls `addVar("base_branch", autoBranch)` —  which is a no-op
   when the user already supplied `base_branch`.

The function-level comment is explicit
(`cmd_sling.go:876-877`):

> // buildSlingFormulaVars merges caller-provided vars with the runtime context
> // needed by common work formulas. **Explicit --var entries always win.**

Concretely, a dispatcher has **two** levers, each with different
ergonomics:

- **Bead-level (sticky):** set `metadata.target` on the work bead or a
  convoy ancestor before slinging. The value persists, follows the bead
  through retries, and is the same field the polecat carries to the
  refinery as merge target.
- **Sling-level (per-invocation):** `gc sling … --var base_branch=<ref>`.
  This wins over the auto-compute, but it does **not** write to the
  bead's `metadata.target`. The polecat will branch from `<ref>` at
  workspace-setup; at submit, however, the polecat sets `metadata.target
  = {{base_branch}}` (`mol-polecat-work.toml:196`), so the merge target
  ends up matching the dispatch base anyway. Net effect: equivalent
  outcome, no pre-sling metadata write needed.

So the canonical Option-A mechanism is operational. The actual gap is
**discoverability**: nothing in `gc sling --help`, in mechanik's
prompt, or in any rig README mentions the `--var base_branch=…` lever
or even names the bead-level `metadata.target` lever. It's findable
only by reading the formula source or the sling internals — see §3.

### 1.4 Submit handoff and refinery merge target

On the polecat side (`mol-polecat-work.toml:164-237`, `submit-and-exit`),
the polecat sets `metadata.target = {{base_branch}}` on the work bead before
reassigning to the refinery, so the merge target is explicit even if the
caller never set it. The polecat's `metadata.branch` is set during
`workspace-setup` and not changed at submit unless a rebase renamed it.

The refinery (`mol-refinery-patrol.toml:142-147`) reads the merge target
from the bead:

```bash
TARGET=$(gc bd show $WORK --json | jq -r '.[0].metadata.target // "{{target_branch}}"')
```

So the refinery does **not** unconditionally merge to main; it merges to
whatever `metadata.target` says. Default fallback `{{target_branch}}` is
"main" (`mol-refinery-patrol.toml:62`). Rejection sets
`metadata.rejection_reason` and routes back to the polecat pool with the
branch intact (`mol-refinery-patrol.toml:168-170`, `:237-240`).

### 1.5 Bead metadata fields driving base-branch selection

Inferred lifecycle, from sling/formula/refinery source:

| Field | Set by | Read by | Notes |
|---|---|---|---|
| `metadata.target` | caller (optional pre-sling) → polecat at submit | sling (`SlingFormulaTargetBranch`) → refinery (merge target) | The single field that drives both dispatch base branch and merge target. Convoy ancestor `target` is also honored. |
| `metadata.branch` | polecat (`workspace-setup`) | refinery (`mol-refinery-patrol.toml:145`), polecat on rejection-resume | Source branch the refinery rebases and merges. |
| `metadata.work_dir` | polecat (`workspace-setup`) | polecat recovery, witness | Worktree path; not part of branch routing. |
| `metadata.rejection_reason` | refinery (on conflict/test fail) | polecat (`load-context` skips preflight, resumes branch) | Closes the rejection-aware loop. |
| `metadata.existing_pr` / `pr_url` / `pr_number` | caller / refinery (mr mode) | refinery validation | Only relevant when `merge_strategy=mr`. |
| `gc.routed_to` | sling and refinery | reconciler (pool membership) | Independent of branch routing. |

The takeaway: **`metadata.target` is the bead-level knob that drives
both dispatch-time base branch and merge-time target**. The sling-level
`--var base_branch` lever (§1.3) bypasses the bead at dispatch time but
the polecat re-anchors `metadata.target = {{base_branch}}` at submit, so
both levers converge on the same merge-target instruction to the
refinery. Useful as design economy: one bead field for two related
roles, with two equivalent ways to set it.

---

## 2. Existing canonical pattern — what already works

The operator's framing is correct: a reasonable workflow already exists in
the formula and CLI code. It is:

> A dispatcher sets `metadata.target` on the work bead (or its convoy
> parent) before slinging. The polecat branches from `origin/<target>`,
> implements, and submits. The refinery rebases onto and merges into
> the same `<target>`. Branches and PRs do all the heavy lifting; main
> is touched only when a complete unit of work squash-merges in.

### 2.1 Where the pattern lives

- `mol-polecat-work.toml:39-52` documents the resolution order in a
  comment block and uses the resolved `{{base_branch}}` in
  `workspace-setup`.
- `mol-polecat-work.toml:196-208` documents that the polecat sets
  `metadata.target` at submit so the refinery has an explicit instruction.
- `mol-refinery-patrol.toml:142-147` documents that the refinery reads
  `metadata.target` for the merge target.
- `internal/sling/sling.go:725-750` codifies the convoy-aware
  parent-walk for `metadata.target`.

### 2.2 What makes it discoverable — and what doesn't

Discoverable signals:

- The `mol-polecat-work` formula's preamble (`mol-polecat-work.toml:1-52`)
  explains the contract clearly — *if* a reader opens the TOML file.
- The polecat's CLAUDE.md ("Work Bead Metadata Contract" section) lists
  the field semantics for `target`, `branch`, etc.

What's not discoverable from a dispatcher's seat:

- There is **no documentation in the gc CLI help, mechanik prompt, or any
  rig README** describing either lever from the caller side. A dispatcher
  has to read `mol-polecat-work.toml` to learn that `metadata.target`
  is the bead-level knob, and read `cmd_sling.go` (or
  `internal/sling/sling.go`) to learn that `--var base_branch=<ref>`
  is the per-invocation knob.
- `gc sling --help` (`cmd_sling.go:71-88`, the cobra `Long` text)
  documents the surface flags and gives examples for `--formula`,
  `--stdin`, etc., but says nothing about branch targeting at all.
- There is no example in any rig of a non-polecat agent setting up a
  named "dispatch branch" and pointing N polecats at it. A search of all
  three rigs surfaced **zero** branches matching `dispatch/*`, `anchor/*`,
  `mechanik/*`, or `convoy/*`. Every polecat branch surveyed branched
  directly from main.

### 2.3 The pattern works in practice for the simple case

Recent gc-toolkit dispatches confirm the simple-case path is healthy:

- `polecat/tk-yiwfz.4-document-spec-synthesis` → squash `7bdde6c`
- `polecat/tk-yiwfz.6-survey-spec-kit` → squash `2f8840f`
- `polecat/tk-yiwfz.7-kiro-survey` → squash `744e853`

Each branched from main, did its work, and squashed back to main via the
refinery. The pattern **only breaks** when a dispatcher needs to share
data across N polecat dispatches before any of them have produced work
worth merging — which is the tk-yiwfz v2 synthesis case the incident
arose from.

---

## 3. Gaps

The 2026-05-06 incident (`7453fa4`) is the lead example. The gaps below
are ordered from most-load-bearing to least.

### 3.1 Gap A — No supported way for a dispatcher to share an input artifact

This is the gap that produced the incident.

**Symptom** (`7453fa4`): mechanik needed `specs/tk-yiwfz/decisions.md`
visible to three v2 synthesis polecats (`tk-yiwfz.{8,9,10}`). The
canonical-pattern path (push the artifact to a `dispatch/...` branch,
point the polecats at it via either lever from §1.3) is operational
but invisible:

1. The branch has to *exist* somewhere reachable to the polecats. Nothing
   in gc creates dispatch branches — this is dispatcher manual work.
2. The dispatcher has no tool support to push the artifact to a named
   branch and update bead metadata (or set `--var base_branch`) in
   one motion.
3. Both levers exist in code but are undocumented from the caller side
   (Gap B): the dispatcher has no obvious knob to "send these N
   polecats to a non-default base branch."

Faced with that friction, mechanik took the shortcut: a single commit to
main (`7453fa4`, 357 lines, single new file). Polecats branch from main,
so the file is visible. **The shortcut works mechanically but violates
the principle decided in tk-w7mjt**: it puts bead-local content (the
"local-tier" historical record per the document spec) on the
authoritative reference branch.

The incident commit never reached `origin/main` (it lives on the local
`main` ref of the gc-toolkit rig checkout only — `git merge-base
--is-ancestor 7453fa4 origin/main` returns false). So the production
state is clean; the incident is an "on-machine" shortcut that *would*
have polluted main if pushed. Either way, the principle violation is the
same.

### 3.2 Gap B — Override mechanism is undocumented; dispatchers don't know it exists

The `gc sling --var base_branch=<ref>` lever **works** (see §1.3), but
nothing surfaces this to the dispatcher:

- `gc sling --help` (`cmd_sling.go:71-88`, the cobra command's `Long`
  text) describes the surface flags and gives examples for `--formula`,
  `--stdin`, etc., but says nothing about `base_branch` as a
  recognised variable, nor about the bead-level `metadata.target`
  lever.
- The function comment in `buildSlingFormulaVars` ("Explicit --var
  entries always win") lives in source, not in any user-facing doc.
- The formula's own preamble (`mol-polecat-work.toml:39-52`) describes
  the resolution order from the polecat's perspective but not the
  dispatcher's: it tells you where `{{base_branch}}` comes from, not
  how a caller can set it from outside the bead.

Consequence: a dispatcher who needs to share an artifact across N
polecats sees no obvious dispatch-time knob. Pre-mutating
`metadata.target` on every bead works but is N writes; the
single-`--var` path is invisible. With the friction unclear, the
shortcut to main looks easier than it should — exactly what happened
on 2026-05-06.

### 3.3 Gap C — No documented dispatcher-side recipe

Beyond the discoverability of individual levers (Gap B), there's no
end-to-end recipe for the "share artifact across N polecats"
workflow. The pattern lives implicitly in formula source. Mechanik's
prompt does not currently describe a dispatch-branch pattern, nor do
any rig READMEs. A dispatcher who hits this case for the first time —
as mechanik did on 2026-05-06 — has nothing to read that says "create
a `dispatch/...` branch, push the artifact, sling the polecats with
`--var base_branch=…` (or set `metadata.target` on the convoy),
graduate via a follow-up bead."

### 3.4 Gap D — No detection signal for shortcut commits

There is no light-touch nudge anywhere in the system to flag a shortcut
like `7453fa4`. The refinery only sees branch-based work; commits made
directly on main bypass it entirely. There is no pre-commit hook, no
post-commit witness check, no nudge from the deacon. Operator review is
the only line of defence today, and the shortcut's violation is
semantic (right kind of file, wrong branch) — easy to miss.

This is **not** a request for a heavy CI gate. gc-toolkit's bar is
intentionally low (signal-loom is the heavier-bar reference; see §3.5).
But "the system is silent when the principle is violated" is a real gap
worth a lightweight signal.

### 3.5 Cross-rig context — pattern is identical, bar height differs

All three rigs use the same direct-from-main polecat branching pattern
in practice (no dispatch branches anywhere). What differs is the bar
that protects main from accidental shortcuts:

| Rig | CI bar | Pre-commit | Conventional commits | Squash-merge enforced |
|---|---|---|---|---|
| gc-toolkit | None (pack; no `.github/workflows/`) | None | Not enforced | Not enforced |
| gascity | Moderate (fmt, lint, vet, unit + integration; `Makefile`, `scripts/pre-commit`) | Format auto-fix only | Embedded by convention `(gc-XXX)` | Not enforced |
| signal-loom | Heavy (`pnpm check`: prettier, eslint, cspell, actionlint, type-check, audit; Playwright/E2E; `pr-title.yml`) | husky `pnpm pre-commit` (`lint-staged && type-check`) | **Enforced** by `pr-title.yml` | **Enforced** |

Implication: signal-loom's bar would *probably* have caught a 7453fa4
analogue (the squash-merge + PR-title enforcement makes a single direct-
to-main commit awkward). gc-toolkit's bar gives zero signal. This is by
design and not in scope to change here, but it does mean **gc-toolkit's
adoption story has to lean on docs and small capability fixes rather
than gate-style enforcement.**

---

## 4. Adoption recommendations

Ranked by leverage (highest first). Each cites the gap it closes.
Lightweight only — gc-toolkit's intentionally low CI/pre-merge bar is
preserved.

### R1 — Document the dispatcher-side recipe in mechanik's prompt (closes Gap C; partially Gap A)

**What:** Add a "Sharing input artifacts across N polecat dispatches"
section to the mechanik agent prompt. Spell out the canonical recipe:

1. Create a dispatch branch (`dispatch/<convoy-or-bead-id>-<slug>`),
   commit the artifact, push.
2. Set `metadata.target = dispatch/<branch>` on the convoy bead (or each
   work bead if no convoy).
3. Sling polecats normally — they'll branch from the dispatch branch.
4. Refinery merges polecat work back to the dispatch branch; when the
   convoy is ready, a follow-up bead squash-merges the dispatch branch
   to main.
5. Anti-pattern callout: "Do not commit bead-local artifacts directly
   to main. See tk-w7mjt and the 7453fa4 incident."

**Why this is highest leverage:** The incident happened because there
was no documented recipe, not because the underlying machinery is
broken. A dispatcher who reads the recipe before slinging gets it right
the first time.

**Effort:** ~50-100 line prompt edit. No code changes.

### R2 — Surface the existing `--var base_branch=…` override in `gc sling --help` and mechanik's prompt (closes Gap B; supports R1)

**What:** The override path already works (§1.3). Make it visible:

- Extend `gc sling`'s cobra `Long` text (`cmd_sling.go:71-88`) with a
  short "Branch targeting" subsection describing both levers
  (bead-level `metadata.target`, dispatch-level `--var
  base_branch=<ref>`) and the precedence rule ("explicit `--var`
  always wins").
- Add a corresponding example to mechanik's prompt next to the
  dispatch-branch recipe from R1: `gc sling polecat <bead-id> --var
  base_branch=dispatch/<convoy-id>-<slug>`.
- Optionally add a one-liner to `mol-polecat-work.toml`'s preamble
  reminding the dispatcher of the lever (the formula already documents
  the polecat side; this would document the caller side in the same
  spot).

**Why second:** Without this, R1's recipe forces N metadata writes for
the N-polecat fan-out case. With this, the dispatcher can sling each
polecat with `--var base_branch=…` and skip the metadata mutation
entirely. The capability is already there; only the visibility is
missing.

**Effort:** Three small doc edits. **Zero code changes.** No test
surface required.

**Caveat:** The `--var` lever sets `base_branch` *on the molecule*,
not `metadata.target` *on the bead* — but the polecat's
`submit-and-exit` step writes `metadata.target = {{base_branch}}` at
submit time (`mol-polecat-work.toml:196`), so the refinery still picks
up the right merge target. Worth calling out in the help text so
dispatchers know both levers converge on the same end-state.

### R3 — Add an explicit "Dispatch branches" section to the polecat/refinery contract docs (closes Gap C residual)

**What:** In the polecat CLAUDE.md ("Work Bead Metadata Contract") and
the refinery CLAUDE.md, add a small subsection naming the dispatch-
branch pattern and how `metadata.target` carries through. Keep it
short — a paragraph and an example.

**Why third:** Polecats and refinery already do the right thing
mechanically; the doc gap is for *readers* (humans, future agents)
trying to understand the system without reading TOML. This codifies the
pattern as a first-class concept, not an emergent one.

**Effort:** Two small doc edits, no code changes.

### R4 — Add a lightweight refinery hint when `metadata.target` points to a dispatch branch (closes Gap D, light-touch)

**What:** In `mol-refinery-patrol`, when `metadata.target` matches a
`dispatch/*` pattern, emit an informational note in the refinery's
mail/log: *"Merging to dispatch branch <name>; this is not main. A
follow-up bead is required to graduate this work to main."* Not a gate,
not a block — just a visibility nudge so operators see the convoy lifecycle.

**Why fourth:** Cheap to add, raises the signal that dispatch-branch
work is in flight, helps reviewers spot the moment a convoy is ready
to graduate.

**Effort:** A handful of lines in the refinery formula. No new
infrastructure.

### R5 — Optional, defer: dispatch-branch lifecycle helper (`gc dispatch …`)

**What:** A new `gc dispatch begin <bead-id> --artifact <path>` /
`gc dispatch end <bead-id>` pair that scripts the R1 recipe: creates
the dispatch branch, commits the artifact, sets `metadata.target` on
the convoy, and (on `end`) opens the graduate-to-main follow-up bead.

**Why deferred:** Higher implementation cost, and R1+R2 together cover
~80% of the friction. Defer until the dispatch-branch pattern has been
in use for a few convoys and the rough edges are concrete.

**Effort:** Medium Go work (a new subcommand). Not blocking the
follow-up bead.

### Out of scope

Per the bead and parent decision context, this research **does not**:

- Re-decide the principle (Option A is settled in tk-w7mjt).
- Propose CI gates, signing, or pre-merge bars beyond what already
  exists (gc-toolkit's intentionally low bar is preserved).
- Prescribe any change to signal-loom's heavier bar.
- Implement the recommendations — that is the follow-up bead, blocked
  by this one.

---

## Summary

The canonical branch-based dispatch workflow already exists end-to-end
in the formula and CLI code: sling resolves the base via
`metadata.target` *or* an explicit `--var base_branch=…` (caller wins,
per `cmd_sling.go:884-892`), the polecat branches accordingly, the
refinery rebases and merges to the same target, with the
convoy-ancestor walk built in (`sling.go:725-750`). The 2026-05-06
incident (`7453fa4`) is the natural failure mode of an
*operational-but-invisible* canonical pattern: the levers exist, but
nothing in `gc sling --help`, mechanik's prompt, or any rig README
points to them — and there is no detection signal when the principle
is violated. Closing the gap is **almost entirely documentation**
(R1, R2, R3 are all docs/prompt edits; R4 is a small refinery formula
nudge; R5 is deferred). No code is required to make the canonical
path discoverable, and no heavy CI gate is needed.
