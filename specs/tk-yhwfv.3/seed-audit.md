---
name: Seed audit — what was built, what it cannot see, and the fidelity measurement
description: Design record for generated/seed-audit/ and assets/scripts/render-seed-audit.sh — why the render runs against a pinned synthetic city rather than the live one, how a stale render is caught by rendering the merge, the measured fidelity against live gc prime, and three limitations found while building it (gc prime ignores rig scope; formula list over-reports vs formula show; a missing prompt template renders a generic prompt with exit 0). Read before changing the renderer or trusting the artifact's coverage.
---

# Seed audit

- **Bead:** tk-yhwfv.3 — "Materialize the agent seed as a versioned audit artifact"
- **Epic:** tk-yhwfv — Context budget: audit and reduce always-on prompt context
- **Siblings:** tk-23wdf (per-agent ledger), tk-yhwfv.1 (leg 2 cuts), tk-yhwfv.2 (harness floor)
- **Built:** 2026-08-23, city `/home/zook/loomington`, `gc` 1.4.1, git 2.55.0
- **Author:** gc-toolkit/gc-toolkit.nux (polecat, claude provider)

## Scope

**Mandate.** Why `generated/seed-audit/` is generated the way it is, what it
provably covers, and what it provably does not. The record of a design
decision and three measurements, not a description of the artifact — that
lives in `generated/seed-audit/INDEX.md`.

**Boundaries.** Tier 1 only: the deterministic, repo-owned half of the seed.
The ~26k-token harness layer is tier 2 and is deliberately not wired to any
gate; `specs/tk-yhwfv.2` owns it.

## What it is made of

| File | Role |
|---|---|
| `assets/scripts/render-seed-audit.sh` | Renders every agent prompt and formula recipe. `--check` re-renders a checkout, `--check-merge` renders a merge result, `--sizes` prints byte and token counts, `--install-hook` wires the hook |
| `assets/hooks/pre-commit` | Regenerates the artifact when a staged path is a seed input |
| `doctor/check-seed-audit-current/` | Reports an absent artifact or an unwired hook, and renders nothing |
| `generated/seed-audit/` | The artifact: one file per agent prompt and per formula recipe, and an `INDEX.md` that links them and carries the resolved fragment composition |

No size is committed. `render-seed-audit.sh --sizes [<base-rev>]` prints each
render's bytes and estimated tokens, and their change since a base revision
when one is named. A total restated in a committed file is stale by the next
fragment edit, and a per-agent size row moves with every edit to its agent's
prompt, so two pull requests that touch two different agents conflict on
neighbouring rows.

## Decision: render against a pinned synthetic city, not the live one

The bead's premise was that both halves already render deterministically via
`gc prime <agent>` and `gc formula show <formula>`. They do — but not into
anything a golden file can hold, because **`gc prime` renders against whatever
city is in scope, and a city contributes prompt text of its own.**

`/home/zook/loomington/city.toml` carries:

```toml
[agent_defaults]
default_sling_formula = "mol-polecat-work"
append_fragments = ["command-glossary", "operational-awareness"]
```

Those two fragments are **6,773 B — 19% — of the polecat seed**. Measured:
`gc prime polecat` renders 29,289 B against a pack-only city and 36,062 B
against loomington; the entire delta is `## Operational Awareness` and the
command glossary, and neither is in this repo.

That leaves two candidate render bases, and only one of them can be committed:

- **Live city.** Reproduces the real seed, but the bytes are a function of a
  file this repo does not contain. The artifact would move whenever the
  operator edited `city.toml`, with no commit here to explain it, and the check
  would fail for reasons nobody controls. That is precisely the failure the
  bead scoped tier 2 out to avoid — importing it into tier 1 would be worse,
  because tier 1 is the half that is supposed to be enforceable.
- **Synthetic city built from the repo.** Reproducible anywhere the `gc` binary
  and its pack cache exist, but blind to the city-level layer above — a 19%
  under-report, which is the exact blind spot the bead exists to close.

The resolution is to keep the second and remove its blind spot by **pinning the
city-level scenario inside the renderer**: the throwaway city declares the same
`[agent_defaults]`, the same providers, and two rig shapes matching the two that
exist in loomington. The scenario is repo content, so it is reviewed and diffed
like anything else, and the artifact stays a pure function of the repo.

Three mechanical requirements follow, and all are load-bearing:

- **The renderer is itself an input.** Pinning the scenario inside the
  script makes the script part of the audited surface: when this was built,
  editing one line of the embedded `[agent_defaults]` moved 13 agent prompts.
  So `assets/hooks/pre-commit`'s `INPUT_RE` carries the renderer's path, and a
  comment-only edit costs one re-render. `--check-merge` renders each tree with
  the renderer that tree carries, so a change to the scenario is judged by the
  scenario it ships.

- **Every `gc` call is `env -i`.** Not tidiness. An inherited `GC_CITY` points
  the render at the operator's live city; inherited `GC_RIG`/`GC_AGENT` leak the
  *caller's* identity into the output — a polecat running the renderer by hand
  otherwise writes its own agent name and worktree path into the committed
  artifact. Measured: with the ambient environment intact the render emitted
  `Working directory: /home/zook/loomington/.gc/worktrees/.../gc-toolkit.nux`.
- **Machine paths are normalized** to `[[PACK-ROOT]]`, `[[CITY-ROOT]]`,
  `[[HOME]]`, longest-needle-first. Twelve agents cite the city root; mechanik
  and keeper cite their own pack dir via `{{.ConfigDir}}`.

`gc init` was tried for building the throwaway city and rejected: it reaches for
the beads store and, on a host with a live Dolt server, talks to it
(`exec beads init: warning: database 'hq' missing bd schema; re-initializing`).
The scenario is hand-written instead, and the required builtin `core`/`bd`
imports are spelled with the `//subpath` form that resolves from the binary's
pre-seeded cache. Without them the formula roster comes back at 14 of 28.

## Fidelity — measured, not assumed

The bead asked for the rendered polecat prompt to match a live polecat seed
within ~1%. The result is far tighter, and it holds across the roster.

Method: render each agent in the live loomington city with the same scrubbed
environment and the same path normalization, then diff against the committed
artifact.

```bash
cd /home/zook/loomington/rigs/gc-toolkit
env -i PATH="$PATH" HOME="$HOME" TERM=dumb NO_COLOR=1 \
    gc --city /home/zook/loomington prime polecat \
  | sed -e "s|/home/zook/loomington/rigs/gc-toolkit|[[PACK-ROOT]]|g" \
        -e "s|/home/zook/loomington|[[CITY-ROOT]]|g" \
        -e "s|/home/zook|[[HOME]]|g" \
  | diff - docs/seed-audit/agents/polecat.md
```

Measured against base `origin/main` at `faeb7a4`, with the rig checkout
verified to be at that same commit. The base is what to stamp here, not the
branch head: the head moves on every rebase while these numbers do not, and a
stamp that rots is the P2 defect this spec already collected once.

Both columns must read the SAME inputs, and that is not automatic: the `live B`
column renders from the rig checkout at `rigs/<rig>/`, which lags `main` by
however long it has been since the last land. Check
`git -C rigs/gc-toolkit rev-parse HEAD` against the branch's base before
believing a delta — a lagging checkout shows up here as a fidelity regression
that is really just checkout drift.

| agent | live B | artifact B | Δ | differing lines |
|---|---:|---:|---:|---:|
| polecat | 35,968 | 35,984 | +16 | 1 |
| refinery | 34,292 | 34,292 | 0 | **0** |
| mayor | 38,255 | 38,255 | 0 | **0** |
| witness | 39,274 | 39,290 | +16 | 1 |
| deacon | 29,873 | 29,873 | 0 | **0** |
| converse | 38,554 | 38,554 | 0 | **0** |
| mechanik | 36,222 | 36,222 | 0 | **0** |
| proactive | 12,902 | 12,902 | 0 | **0** |
| keeper | 61,850 | 61,850 | 0 | **0** |

Seven of nine are **byte-identical**. The two that differ do so on one line
each, and it is the same line in both — the rig checkout path:

```
live:     rig repo at `[[PACK-ROOT]]`
artifact: rig repo at `[[CITY-ROOT]]/rigs/gc-toolkit`
```

That is a fact about loomington, not about rendering: there the rig checkout
*is* the pack directory (`[rigs.imports.gc-toolkit] source = "rigs/gc-toolkit"`),
so `RigRoot` and the pack root coincide. In the scenario they are different
directories. Worst case 0.04%.

Re-run this table after any change to the renderer's scenario. A widening delta
means the pinned scenario has drifted from the city it is supposed to model —
which is the drift the bead asked to keep detectable.

## Three limitations found while building this

### 1. `gc prime` ignores rig scope entirely

`gc prime <agent> --rig <rig>` renders the **city-scope** agent. Rig-scoped
`[[rigs.patches]]` do not reach it, and neither does the qualified name form.

Reproduced in a scratch city with two rigs, one of which appends two fragments
to `polecat`:

```
gc config show   → rig agent resolves with
                   [... "learned-conventions-polecat", "rebase-conventions", "polecat-patterns"]
gc prime polecat --rig <patched rig>   → 36,346 B
gc prime polecat --rig <plain rig>     → 36,346 B   (identical)
```

Confirmed against the live city too: `polecat` renders 36,062 B for all four of
`gc-toolkit`, `signal-loom`, `gascity`, `shutupandlisten`, and
`gascity/gc-toolkit.polecat`, `gc-toolkit/gc-toolkit.polecat` and bare `polecat`
all render the same bytes — while `gc config show` reports gascity's polecat and
refinery carrying `rebase-conventions` + `polecat-patterns` /
`refinery-rebase-handling` that the others do not.

**Consequence beyond the audit.** `gc prime` is also what an agent runs to
re-prime itself after compaction, and it is the command every prompt in the pack
names for exactly that ("Run `gc prime` after compaction, clear, or new
session"). On a rig with `[[rigs.patches]]`, that re-prime hands the agent a
prompt **missing its rig's doctrine**. The bead's own measurement is consistent
with the divergence being large: a live gascity polecat writes 55,312 fresh
tokens against 35,217 for a gc-toolkit polecat, and the bead already established
the gap "is NOT the pack prompt — it enters at spawn".

Not fixed here: `gc prime` is the gc binary, so a fix belongs in the gascity rig,
not this pack. What this bead does instead is make the divergence *visible* —
the scenario ships both rig shapes, and `INDEX.md`'s fragment-composition table
reads the resolved lists out of `gc config show` and marks `polecat` and
`refinery` **DIVERGES**, naming the extra fragments. Worth filing separately.

### 2. `gc formula list` over-reports relative to `gc formula show`

`gc formula list` answers city-wide and offers every formula in every rig's
import closure. `gc formula show` is scope-strict. The four `mol-upstream-gc-*`
recipes live in the opt-in `gascity-keeper` sub-pack, which only the
gascity-shaped rig imports, so a city-scope `show` reports them
`not found in search paths` immediately after `list` offered them.

The renderer walks scopes (city → each rig shape) and records the resolving
scope per formula in `INDEX.md`. Same shape as the known `gc convoy list`
behaviour of ignoring `--rig`.

### 3. A missing prompt template renders a generic prompt, with exit 0 — even under `--strict`

Remove `agents/mechanik/prompt.template.md` and:

- pack composition **drops** mechanik's `prompt_template` from the resolved
  config (the key is simply absent from its `[[agent]]` block);
- `gc prime mechanik --strict` then exits **0** and emits 4,461 B of the builtin
  `# Graph Worker` prompt instead of mechanik's 36,222 B of doctrine.

`--strict` is not at fault by its own contract — it documents that it "does NOT
error on agents whose config intentionally lacks a prompt_template", and by the
time it looks, that is indistinguishable from this. But it means the failure is
invisible to every caller: nothing on stderr, nothing in the exit status, and
the output is a perfectly plausible prompt.

This is also a *second* fallback, distinct from the 495 B `# Gas City Agent`
stub that `doctor/check-agent-prompt-integrity` documents. A guard that only
matched the stub — which is what this renderer had first — passes straight
through it.

The renderer therefore fails closed twice, and each guard was verified with the
other disabled (two guards in series otherwise mask each other):

1. a preflight asserting that every agent directory in this pack either declares
   `prompt_template` or ships `prompt.template.md` beside its `agent.toml`;
2. a render-time check that no **pack-owned** agent's output matches either
   builtin fallback. Scoped to pack-owned agents because `claude`, `codex`,
   `gemini` and `control-dispatcher` legitimately *are* the builtin worker
   prompt — banning it outright would fail them.

## Where staleness is judged

The bead asked for "CI: regenerate and `git diff --exit-code`". A render needs
the `gc` binary and its pack cache, and the CI runners carry neither, so CI runs
the renderer's hermetic suite against a stub `gc` and renders nothing real. The
audit is judged where a render can run:

- `render-seed-audit.sh --check` re-renders a checkout and compares the result
  with the committed tree, file by file.
- `render-seed-audit.sh --check-merge <base> <head>` is what `merge.sh` runs
  before it lands a pull request. It renders the merge result with the renderer
  that result carries, and judges every file the render writes or the merge
  commits. A file passes when the merge commits it exactly as rendered. A file
  that fails that test still passes when the merge leaves it as the base commits
  it and it renders the same on the base, because the base was already stale
  there and the pull request did not cause it; the check reports it as the
  base's own staleness. Any other file holds the merge. The base is rendered
  only when some file fails the first test.

Rendering is what lets the gate see every input. A file no path list names, or a
`gc` binary that composes prompts differently, moves the render, and no list of
inputs has to be kept in step with what the render reads.
`doctor/check-seed-audit-current` renders nothing: it reports an absent artifact
and an unwired hook, which is what `gc doctor` can afford on every run.

The `gc` version is deliberately not recorded: it is not a function of the repo,
so stamping it into the per-branch artifact drifts with the host binary and drags
host state into unrelated commits. Prompt composition lives in the binary, so an
upgrade can still move the artifact with no commit here to explain it; the commit
that renders the artifact is the record of which `gc` built it.

## Cost — measured

The operator's stated risk was "the CI will fail on any fragment change, so
ideally it's something updated on some form of pre-commit hook cheaply".

| Operation | Cost |
|---|---|
| Commit touching no seed input | **~9 ms** hook contribution (5 commits in 115 ms total, git included) |
| Full render, 16 agents + 28 formulas, `--jobs 8` | 13-23 s wall (44 `gc` invocations) |
| Commit touching a fragment, end to end | 9.4 s |
| `--check-merge`, merge result committed as rendered (one render) | 11-13 s |
| `--check-merge`, base rendered too (two renders) | 22-59 s |

The `--check-merge` rows were measured on 2026-10-10 on the macOS host (18
cores, load averages 41-55); the rows above them on 2026-08-23 on the Debian
host.

Verified end to end in a throwaway clone: an unrelated commit finished in 46 ms
and touched no audit file; editing `template-fragments/polecat-convoys.template.md`
regenerated the artifact and staged exactly `INDEX.md`,
`agents/polecat.md` and `agents/polecat-codex.md` alongside the fragment,
leaving a clean working tree. (`INDEX.md` moved then for its size rows, which it
no longer carries.)

## Known gaps

- **The hook is not installed by cloning.** `core.hooksPath` is local git config
  and cannot travel in a commit, so someone must run
  `assets/scripts/render-seed-audit.sh --install-hook` once per checkout. Until
  they do, `gc doctor` reports a warning naming that command. The installer
  refuses to run if `.git/hooks` already holds a hand-installed hook, because
  `core.hooksPath` replaces that directory rather than layering onto it.
- **The gascity rig sets `core.hooksPath=/dev/null`** deliberately, for host
  capacity. There the hook cannot run at all. Nothing here proposes changing
  that.
- **The renderer reads the working tree, not the index.** Under a partial
  `git add -p` of a fragment, the artifact the hook stages describes the working
  tree rather than the commit. The hook says so on stderr rather than doing it
  quietly, and the two reconcile on the next commit. It deliberately does not
  stash to "fix" this: the stash stack is shared with every other worktree of
  this repo.

---

The fidelity table, the three limitations and the cost rows are measurements,
and each names the base, host or date it was taken on; the paths inside them are
as they were then (`docs/seed-audit/` is now `generated/seed-audit/`). The rest
of this record describes the design as it stands.
