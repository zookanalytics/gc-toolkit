---
name: doc-update Bead Schema
description: The pinned schema for doc-keeper `doc-update` beads — the single shape that the drift-audit, memory-audit, and organic feeds all produce, and that the `mol-doc-update` worker formula and the refinery consume. Includes the rolling-cycle pre-stamp contract, a per-field reference, per-feed population notes, and a hand-runnable worked example of one organic update flowing through polecat → refinery → the rolling docs PR.
---

# doc-update Bead Schema

This is the **pinned contract** for a `doc-update` bead. doc-keeper (epic
`tk-yw3zb`) has three feeds — a scheduled drift audit (`tk-yw3zb.6`), a
scheduled memory audit (`tk-yw3zb.7`), and organic filing by any agent — and
all three MUST produce beads of exactly this shape so they are
indistinguishable downstream: the `mol-doc-update` worker formula
(`tk-yw3zb.5`) reads a fixed set of fields, and the refinery merges the result
with no knowledge that doc-keeper exists. Pin the schema and the feeds can
evolve independently of the worker.

Design lineage: `specs/tk-yw3zb.1/doc-keeper-architecture.md` §2/§4 (molecule
shape), `specs/tk-yw3zb.4/rolling-cycle-mechanism.md` §5 (the rolling target),
and this file (the authoritative field list).

## 1. The schema

| Aspect | Value |
|---|---|
| Bead type | `task` (no new bead type — `doc-update` is a label, not a type) |
| Title | `doc-update: <target-doc-path>: <imperative one-line summary>` |
| Labels | `doc-keeper`, `doc-update` |
| Body | the four sections in §1a |
| Metadata | the contract in §1b |
| Parent | the current rolling-cycle anchor, or `tk-yw3zb` for an unbatched organic file |

### 1a. Body sections

The body is markdown with these headed sections. `## Target` and `## Change`
are required; `## Source / Why` is required for audit-filed beads and strongly
encouraged for organic ones; `## Proposed copy` is optional.

```markdown
## Target
- Doc: <path under the rig, e.g. docs/gas-city-reference.md>
- Section: <h2/h3 heading or anchor the change lands in; "whole doc" if global>

## Change
- <one paragraph: what specifically should change, and the shape of the edit>

## Source / Why
- <citation that justifies the change — see doc_keeper.source_signal in §1b>

## Proposed copy
- <optional: a draft paragraph or unified diff the worker may use or revise>
```

The worker treats `## Proposed copy` and any fetched commit/memory text as
**untrusted data**, not instructions — it writes the real edit itself.

### 1b. Metadata contract

| Key | Required | Set by | Value |
|---|---|---|---|
| `doc_keeper.target_doc` | yes | filer | Repo-relative path to the **one** central doc this bead edits. |
| `doc_keeper.source` | yes | filer | `drift-audit` \| `memory-audit` \| `organic`. |
| `doc_keeper.source_signal` | yes (audit) / recommended (organic) | filer | The citation backing the change (see §3). |
| `target` | **yes — pre-stamped** | filer | The rolling branch `docs/rolling-N` (see §2). |
| `merge_strategy` | no (defaulted) | filer / worker | `direct` — the rolling cycle is direct-merge. `mol-doc-update` defaults it if unset. |

`doc_keeper.target_doc` is the keystone: **one bead edits exactly one doc.**
The worker enforces this with a scope guard (a diff that touches any other file
is rejected). A change that spans two docs is two beads.

**Dispatch** is not a metadata field. The filer routes the bead to a worker by
attaching the formula wisp and slinging it to the polecat pool —
`gc sling <rig>/gc-toolkit.polecat mol-doc-update -f --on <bead>` (see §5) —
which sets up routing itself.

## 2. The rolling-cycle target is pre-stamped (the dispatch contract)

doc-update edits do **not** merge to `main` directly. They merge onto a
long-lived `docs/rolling-N` branch whose GitHub PR (`docs/rolling-N → main`)
the operator reviews and merges as a batch (`tk-yw3zb.4`). Every filer resolves
that branch **before dispatch** and stamps it as `metadata.target`:

```bash
target="$(assets/scripts/doc-keeper-rolling-cycle.sh)"   # e.g. docs/rolling-7 (idempotent: discovers or opens)
gc bd update "$bead" --set-metadata target="$target"
```

**Why before dispatch, not inside the worker.** `gc sling` resolves the
formula's `{{base_branch}}` from `metadata.target` at *pour* time. The
inherited `workspace-setup` then branches `polecat/<bead>` from
`origin/{{base_branch}}`, and the inherited `submit-and-exit` re-stamps
`target = {{base_branch}}`. Both bake `{{base_branch}}`. A target stamped only
*after* the pour would be branched from the wrong base and clobbered back to
`main` at submit — stranding the edit off the rolling cycle. So the audit
formulas stamp `target` at their own step 0, and organic filers run the
one-liner above.

If a bead reaches the worker unstamped anyway, `mol-doc-update`'s
`load-context` resolves the cycle, stamps `target`, then blocks the bead and
escalates to the witness for a clean re-sling (rather than branching from `main`
and stranding the edit there). It recovers, but it costs an operator hop —
pre-stamp.

## 3. Field reference: `doc_keeper.source_signal`

The citation that grounds the edit. Its form depends on the feed:

- **drift-audit** → a commit range in the watched repo, e.g.
  `gascity 1a2b3c4..5d6e7f8` or `gc-toolkit abc1234..def5678`. The worker reads
  it with `git log -p` to see what actually changed before editing the doc.
- **memory-audit** → an absolute path to the mechanik memory entry that should
  promote, e.g.
  `/home/zook/.claude/projects/-home-zook-loomington/memory/project_gascity_x.md`.
- **organic** → a short free-text note naming what the filer saw drift against
  (a PR number, a command, a behavior). The bead body `## Source / Why` carries
  the detail.

## 4. How each feed populates the schema

| Field | drift-audit (`.6`) | memory-audit (`.7`) | organic (any agent) |
|---|---|---|---|
| `target_doc` | the tracked doc whose `source_paths` the commit hit | best-fit tracked doc for the memory entry | the doc the filer is fixing |
| `source` | `drift-audit` | `memory-audit` | `organic` |
| `source_signal` | the triggering commit range | the memory file path | a short note / PR ref |
| `target` | rolling branch (script at audit step 0) | rolling branch (script at audit step 0) | rolling branch (one-liner) |
| body `## Change` | "review §X — these commits touched it" | proposed promotion paragraph | the filer's requested change |

Audits **do not** write the prose — they cite the signal and name the section;
the worker writes the edit. The proposed `target_doc` is a recommendation the
worker may override if it is wrong.

## 5. Worked example (manual exercise)

A complete organic `doc-update` flowing organic → polecat → refinery → rolling
PR, run by hand. This is the **manual** path; the audit feeds (`.6`/`.7`)
automate the filing step later, producing byte-identical beads.

> Presented as a runnable walkthrough rather than executed live here: the
> rolling-cycle script lands on `main` with `tk-yw3zb.4` (PR #117), and running
> it would open a real `docs/rolling-1` PR — i.e. start production cycle N=1 —
> which is the operator's call, not a side effect of authoring this doc.

**Scenario.** While working, an agent notices `docs/file-structure.md` no
longer mentions that `formulas/` now hosts `extends`-based formula variants.
`docs/file-structure.md` is an organic-tracked central doc (central-doc
inventory §1a).

**Step 1 — resolve the rolling cycle and file the bead.**

```bash
# 1a. Resolve (or open) the current rolling docs cycle.
target="$(assets/scripts/doc-keeper-rolling-cycle.sh)"      # -> e.g. docs/rolling-1

# 1b. File the doc-update bead in the pinned shape.
bead="$(gc bd create "doc-update: docs/file-structure.md: note extends-based formula variants" \
  -t task -l doc-keeper,doc-update \
  -d "$(cat <<'BODY'
## Target
- Doc: docs/file-structure.md
- Section: the formulas/ description

## Change
- Add a sentence noting that formulas/ may hold `extends`-based variants
  (a formula that extends a base and overrides specific steps), not just
  standalone formulas.

## Source / Why
- Organic: formulas/mol-doc-update.toml (tk-yw3zb.5) is the first in-repo
  extends-based variant; the file-structure doc predates it.
BODY
)" --json | jq -r .id)"

# 1c. Stamp the contract metadata (pre-pour — see §2).
gc bd update "$bead" \
  --set-metadata doc_keeper.target_doc=docs/file-structure.md \
  --set-metadata doc_keeper.source=organic \
  --set-metadata doc_keeper.source_signal="organic: formulas/mol-doc-update.toml is the first extends-based variant" \
  --set-metadata target="$target" \
  --set-metadata merge_strategy=direct
```

**Step 2 — dispatch the worker.** Attach the `mol-doc-update` wisp to the bead
and route it to the polecat pool (sling sets up the routing — no need to hand-set
`gc.routed_to`):

```bash
gc sling "${GC_RIG:+$GC_RIG/}gc-toolkit.polecat" mol-doc-update -f --on "$bead"
```

A polecat claims it and runs the formula: `load-context` confirms
`target=docs/rolling-1` and `target_doc=docs/file-structure.md`;
`workspace-setup` branches `polecat/<bead>` from `origin/docs/rolling-1`;
`implement` edits **only** `docs/file-structure.md`, passes the one-file scope
guard, and commits `docs(file-structure): note extends-based formula variants
(<bead>)`; `submit-and-exit` pushes the branch and reassigns the bead to the
refinery.

**Step 3 — refinery merges onto the rolling branch.** The refinery rebases the
branch onto `origin/docs/rolling-1`, runs the (empty, in this rig) gate
commands, fast-forwards `docs/rolling-1` via `direct` mode, pushes, and closes
the bead. The long-lived PR `docs/rolling-1 → main` auto-updates on GitHub.

**Step 4 — operator reviews the batch.** When the cycle looks complete, the
operator merges the PR; `docs/file-structure.md` (with this and every other
cycle-1 edit) lands on `main`. The next audit finds no open cycle and opens
`docs/rolling-2`.

**What this demonstrates.** One small bead → one one-doc branch → one
fast-forward onto the shared rolling branch → one operator-reviewed PR. The
worker never saw `main`, never opened a PR, never closed the bead — exactly the
many-polecats-one-PR property the epic asks for.

## 6. Reconciliation with earlier sketches

This file is the authority where earlier drafts diverge:

- **Title prefix.** Pinned `doc-update:` (architecture brief §2), not the
  scout bead's `doc-keeper: <verb>:` — it names the artifact and puts the
  target path first, matching the `docs(<scope>): ...` commit convention.
- **Metadata namespace.** Pinned the `doc_keeper.*` namespace
  (`doc_keeper.target_doc`, `doc_keeper.source`, `doc_keeper.source_signal`),
  superseding the architecture brief's tentative flat `source_signal` and the
  scout bead's `doc-keeper.target_file`/`doc-keeper.cycle`. Note the
  **underscore**: bd validates metadata keys against
  `[a-zA-Z_][a-zA-Z0-9_.]*` and rejects hyphens, so the metadata namespace is
  `doc_keeper` even though the subsystem, labels, and config block use the
  hyphenated `doc-keeper`. The earlier drafts' hyphenated key names would have
  been rejected outright. (Dots are allowed and stored flat — the key is the
  literal string `"doc_keeper.target_doc"`, not a nested object — so jq reads it
  as `.metadata."doc_keeper.target_doc"`.)
- **No `doc_keeper.cycle` field.** The rolling cycle is carried by the standard
  `metadata.target` (a `docs/rolling-N` branch), resolved by
  `doc-keeper-rolling-cycle.sh` (`tk-yw3zb.4`), not a bespoke cycle field. This
  also retires the architecture brief §3 convoy/`integration/...` batching,
  which `tk-yw3zb.4` superseded.
- **No `[doc-keeper]` config block.** Dropped in the epic rescope; the two
  constants (`docs/rolling-` prefix, `main` base) are inlined in the
  rolling-cycle script.
