---
name: Context Budget Ledger — per-agent prompt measurement and fragment dispositions
description: What every gc-toolkit agent actually pays in always-on prompt bytes, measured live from /proc, attributed to base pack / gc-toolkit / city.toml / harness, with a disposition for every fragment. Read before proposing any context-reduction work under tk-yhwfv.
---

# Context Budget Ledger

- **Bead:** tk-23wdf — "Measure the context budget: per-agent ledger + fragment dispositions"
- **Epic:** tk-yhwfv — Context budget: audit and reduce always-on prompt context
- **Kind:** RESEARCH + INVENTORY. No fragment, `pack.toml`, or `city.toml` was edited.
- **Author:** gc-toolkit/gc-toolkit.nux (polecat, claude provider)
- **Measured:** 2026-08-10 19:16Z, city `/home/zook/loomington`
- **Status:** Measurement complete; dispositions proposed for implementation beads

---

## Provenance

| Artifact | Producer | Source location | Surveyed at |
|---|---|---|---|
| Rendered agent prompts (9 roles) | live agent processes | `/proc/<pid>/cmdline`, largest NUL-delimited argv element | 2026-08-10 19:16Z |
| gc-toolkit pack | this repo | `polecat/tk-23wdf` @ `3a9c336` (= `origin/main`) | 2026-08-10 19:15Z |
| Base gastown pack | gascity-packs repo | `/home/zook/.gc/cache/repos/2f0a295d…/` @ `33d3a430a67d1782ad364556cb566bdb01d0afe3` (the pin in `pack.toml:[imports.gastown]`) | 2026-08-10 19:20Z |
| City config | operator | `/home/zook/loomington/city.toml` (8,052 B) | 2026-08-10 19:18Z |
| Provider skill sinks | gc skill materialization | `<work_dir>/.claude/skills/`, `<work_dir>/.codex/skills/` | 2026-08-10 19:29Z |
| Bead caseload counts | beads/Dolt | `bd list --db rigs/<rig>/.beads --status closed --limit 0` | 2026-08-10 19:26Z |
| Review-bead description census (60 beads, F2) | beads/Dolt | `gc bd list --metadata-field task_kind=review --status=open,closed --limit 60 --json` | 2026-08-10 19:48Z |
| `review-dispatch-body.sh` call sites (F2) | this repo | `grep -rn review-dispatch-body --include='*.sh' --include='*.toml'` @ `3a9c336` | 2026-08-10 19:47Z |
| Auto-memory index | Claude Code | `~/.claude/projects/-home-zook-loomington-rigs-gc-toolkit/memory/MEMORY.md` | 2026-08-10 19:28Z |

---

## 1. Headline

**A polecat's rendered agent prompt is 102,550 bytes. 74,099 of them (72.3%) are
gc-toolkit fragments, and 70,043 of those (68.3% of the whole prompt) are the
single fragment `polecat-non-impl-done`.**

The epic asked what fraction we actually control. On the polecat the answer is
uncomfortable in our favour: we control almost all of it. The base gastown pack
contributes 28,387 bytes (27.7%); everything else is ours.

**That fragment governs a path the claude `polecat` pool takes 2.3% of the time.**
Across four rigs the claude pool closed 908 implementation beads and 21 non-impl
beads. The `polecat-codex` pool closed 626 non-impl beads and 0 implementation
beads. The fragment is correctly placed on the codex pool and almost entirely
wasted on the claude pool — which is the pool that does the implementation work.

This confirms the epic's predicted headline finding, with the denominator it was
missing.

---

## 2. Per-agent context ledger

Live captures, one row per role gc-toolkit spawns. All figures are exact bytes of
the rendered prompt; every row's columns sum to its total.

| Agent (rig) | Total | Base gastown pack | gc-toolkit | city.toml patches | gc skills appendix | gc header |
|---|---:|---:|---:|---:|---:|---:|
| **polecat** (gc-toolkit) | **102,550** | 28,387 | **74,099** | 0 | 0 *(disabled)* | 64 |
| **polecat-codex** (gc-toolkit) | **102,611** | 28,402 | **74,099** | 0 | 0 *(disabled)* | 110 |
| **polecat** (gascity) | **119,620** | 28,389 | 74,099 | **17,067** | 0 *(disabled)* | 65 |
| **refinery** (gascity) | **63,337** | ~27,7xx | ~3,7xx | **24,764** | ~2,8xx | 163 |
| **witness** (gc-toolkit) | **39,130** | 25,387 | 10,742 | 0 | 2,840 | 161 |
| **refinery** (gc-toolkit) | **34,447** | 27,739 | 3,704 | 0 | 2,841 | 163 |
| **mechanik** (city) | **33,786** | 6,892 | **23,889** | 0 | 2,830 | 175 |
| **mayor** (city) | **32,703** | 25,901 | 3,829 | 0 | 2,827 | 146 |
| **deacon** (city) | **29,593** | 21,209 | 5,408 | 0 | 2,828 | 148 |
| **converse** (gc-toolkit) | **13,972** | 6,892 | 4,166 | 0 | 2,843 | 71 |

The two polecat pools are byte-for-byte the same prompt apart from the agent's
own name: diffing the claude and codex renders past their headers shows a single
divergence, at the `## Your Role: POLECAT (Worker: …)` line. `polecat-codex`
shares the base prompt by reference (`prompt_template = "gastown//agents/polecat/…"`)
and mirrors the four fragments by hand in `agents/polecat-codex/agent.toml:41`,
and the measurement confirms the mirror is currently exact.

"Base gastown pack" folds the agent's own `prompt.template.md` together with the
base template-fragments it pulls in; both are upstream content we inherit. For
`mechanik` and `converse` — gc-toolkit-native agents — the prompt template is
*ours*, so it sits in the gc-toolkit column and the base column holds only
`command-glossary` + `operational-awareness`.

### Roles not captured live, and why

| Role | Why not captured | Source-measured weight |
|---|---|---|
| `keeper` (gascity-keeper sub-pack) | asleep at capture time (`min_active_sessions = 0`) | `agents/keeper/prompt.template.md` = **50,480 B** — the pack's second-heaviest always-on artifact |
| `boot` | retired to `mode = "on_demand"` (city.toml:191, lx-8bb1); 0 live sessions | would add `layered-startup-discovery-boot` = 7,798 B if revived |
| `mayor-thread`, `mechanik-thread` | operator-spawned only (`work_query = "printf '[]'"`); 0 live | `thread-role` = 2,992 B |
| `proactive` | default-disabled (`GC_PROACTIVE_ENABLED` gate); 0 live | polecat-shaped |
| `_polecat-gemini` | disabled by `_` prefix (agent discovery skips it) | polecat-shaped |

The keeper figure is the only number here that matters at scale and was not
measured live. It is labelled as source-measured, per this bead's instruction.
The headline polecat number **was** captured live.

### Byte breakdown of the polecat prompt (exact)

| Span | Origin | Content |
|---:|---|---|
| 64 | gc | session header line |
| 92 | base | polecat prompt: intro |
| 2,249 | base | frag `approval-fallacy-polecat` |
| 2,547 | base | polecat prompt: three CRITICAL sections |
| 3,799 | base | frag `propulsion-base` + `propulsion-polecat` |
| 1,213 | base | frag `capability-ledger-work` |
| 224 | base | polecat prompt: Your Role |
| 481 | base | frag `architecture` |
| 2,607 | base | polecat prompt: metadata contract + work protocol |
| 1,060 | base | frag `following-mol` |
| 7,225 | base | polecat prompt: startup → command quick-reference |
| 825 | **tk** | frag `polecat-convoys` |
| 2,583 | **tk** | frag `polecat-append-notes` |
| **70,043** | **tk** | **frag `polecat-non-impl-done`** |
| 648 | **tk** | frag `file-work-records` |
| 128 | base | frag `command-glossary` |
| 6,762 | base | frag `operational-awareness` |
| **102,550** | | **total** |

### Amplification: `gc prime` re-pays the whole thing

`gc prime` emits **102,486 bytes** — the agent prompt again, near-verbatim. The
`PreCompact` hook (`gc handoff --auto`) and the documented recovery step ("Run
`gc prime` after compaction, clear, or new session") mean a long-running polecat
pays the always-on cost **once per spawn plus once per compaction**, not once per
session. Any per-spawn saving is multiplied by the compaction count.

---

## 3. Method (reproducible)

Re-run these after any change to re-measure. Every number above came from one of
them.

### 3.1 Capture a live agent's rendered prompt

There is no `gc agent render` and no `gc pack show` (`gc pack` has only
fetch/list/registry/release). The rendered prompt is passed to the provider as a
**positional argv element**, not `--append-system-prompt`, so read it from
`/proc` and split on NUL only — never on newline, or the prompt shreds into
hundreds of fragments:

```bash
for p in $(pgrep -f 'claude|codex|gemini'); do
  [ -r "/proc/$p/cmdline" ] || continue
  alias=$(tr '\0' '\n' < "/proc/$p/environ" | sed -n 's/^GC_ALIAS=//p' | head -1)
  python3 -c "
import sys
d=open('/proc/$p/cmdline','rb').read().split(b'\0')
open(sys.argv[1],'wb').write(max(d,key=len) if d else b'')" \
    "/tmp/prompts/$(printf '%s' "${alias:-pid$p}" | tr '/' '_').prompt.txt"
done
```

Filter to processes whose cmdline exceeds ~5 KB to skip helper processes. The
provider binary differs per pool (`claude` / `codex` / `node`); a codex pool
shows two processes with the same prompt — count either, not both.

**A polecat must be live.** At capture time four claude polecats and two codex
polecats were running, so no waiting was needed; if none is running, wait for a
spawn rather than substituting an estimate.

### 3.2 Attribute the bytes

Segment by anchor: take the first rendered line of each fragment `define` as a
boundary, sort boundaries by byte offset, and let each span run to the next
boundary. Spans then sum exactly to the file size, which is the check that the
attribution is complete — if it does not sum, a boundary is missing.

Two traps:

- **Anchor on a distinctive line.** `operator-next-step-trailing` and
  `thread-role` both begin with `---`, which matches early in any prompt and
  over-captures by ~15 KB. Use the first *heading*, not the first literal line.
- **Rendered ≠ source.** Template variables expand: `propulsion-polecat` is 1,319
  source bytes but 2,477 rendered, because `{{ .AssignedInProgressQuery }}`
  substitutes a ~1.1 KB shell one-liner. Always measure the rendered side.

### 3.3 Locate the base pack

The base gastown pack is **embedded in the `gc` binary**, not checked out in the
gascity rig. Two materializations exist and they disagree:

- `/home/zook/.gc/system/packs/gastown` — **stale** (May 25). Its polecat prompt
  does not contain text that is in the live render. Do not measure from it.
- `/home/zook/.gc/cache/repos/<hash>/` — the `gascity-packs` git cache, which
  **does** carry the pinned commit as a real object. This is authoritative.

Find it by asking which cache repo holds the pin from `pack.toml`:

```bash
PIN=33d3a430a67d1782ad364556cb566bdb01d0afe3   # [imports.gastown] version
for d in /home/zook/.gc/cache/repos/*/; do
  git -C "$d" cat-file -t "$PIN" >/dev/null 2>&1 && echo "$d"
done
# then, with BRACES around the variable:
git -C "$R" show "${PIN}:gastown/agents/polecat/prompt.template.md"
```

`${PIN}` must be braced. In zsh, `$PIN:gastown/...` is parsed as a history
modifier — `:ga` is silently eaten and the path becomes
`…afe3stown/agents/…`, which fails with a confusing "ambiguous argument" error.

### 3.4 Caseload split (impl vs non-impl)

```bash
bd list --db rigs/<rig>/.beads --status closed --limit 0 --json \
 | tr -d '\000-\010\013\014\016-\037' \
 | jq -r 'def pool: (.metadata.review_pool // .metadata["gc.routed_to"] // ""); …'
```

`tr -d` is required — control characters in bead notes break `jq`. Classify a
bead as non-impl by `task_kind` ∈ {review, research, investigation} or a title
matching `^Review (PR#|branch )`; as impl by `metadata.branch ~ ^polecat/`.
Resolve the pool as `review_pool // gc.routed_to` in that order: `gc.routed_to`
is consumed on claim, so on a closed bead it is often gone, while `review_pool`
is the durable copy.

**Do not classify by `pr_number`/`pr_url` presence** (see §5, finding F4).

---

## 4. Skill-discovery prerequisites (mechanik's dispatch note)

The note asked three questions. All three are answered, and the conclusion
differs from the one the note anticipated.

### (a) Can a polecat invoke a skill it was never told about by gc? — **Yes. Proven in this session.**

All four polecat pools set `inject_assigned_skills = false` (city.toml:124, 136,
147, 153, 158, 164, 169). That flag suppresses **gc's** appendix, and the
suppression is real: the captured polecat and polecat-codex prompts contain no
`## Skills available to this session` section, while refinery, witness, mayor and
deacon all do.

But gc's appendix is not the only index. The **provider harness enumerates the
sink directory itself.** This session — a claude polecat with the flag off —
received a skills listing in its system prompt covering all 13 skills in
`<work_dir>/.claude/skills/`, and invoked `gc-toolkit.filing-documentation` from
it while producing this document. Discoverability is not switched off for
polecats; it is served by a different mechanism than the one the flag controls.

### (b) What would re-enabling the appendix cost? — **~2,830 bytes, nearly all duplicate.**

Measured on the four sibling agents in this city that still have it enabled:
2,827 B (mayor), 2,828 B (deacon), 2,840 B (witness), 2,841 B (refinery), for the
same 13 skills. The harness's own index costs about **2,125 B** for those same
skills (sum of `- name: description` lines from SKILL.md frontmatter).

So re-enabling gc's appendix would add ~2,830 B of standing cost to restate an
index the polecat already has. **Recommendation: leave the flag disabled.** It is
not a prerequisite for any MIGRATE, because the discovery it provides is already
provided.

For scale: 2,125 B of index buys access to **90,526 B** of skill bodies — a 42:1
leverage ratio, and the clearest quantitative statement of why the skill path is
cheaper than the fragment path.

### (c) Is skill delivery a prerequisite for MIGRATE? — **Yes, but the blocker is the sink, not the flag.**

The two provider sinks disagree:

| Sink | Skills | Last refreshed |
|---|---|---|
| `polecats/gc-toolkit.nux/.claude/skills/` | 13 | 2026-08-09 |
| `polecat-codex/gc-toolkit.hicks/.codex/skills/` | 10 | 2026-08-03 |

The codex sink is missing `gc-toolkit.signoff-review`, `filing-documentation`,
`demo-capture`, and `gc-demo-script`. `signoff-review` landed on 2026-08-08
(`16ff68b`, tk-wghh1) — **after** the codex sink was last written.

This matters because **the codex pool runs 100% of reviews.** The pool that most
needs the review skill is the one that does not have it. Any migration that
assumes a skill is present in the codex sink is wrong today, and flipping
`inject_assigned_skills` would not fix it: the flag governs whether the prompt
lists skills, not whether they are materialized.

What works instead — on the paths where it is actually wired — is described next,
and it is the model for every MIGRATE below.

---

## 5. Findings

**F1 — `polecat-non-impl-done` is 68.3% of the polecat prompt and is used 2.3% of the time by the pool it costs most.**

| Pool | impl beads | non-impl beads | non-impl share |
|---|---:|---:|---:|
| claude `.polecat` (4 rigs) | 908 | 21 | **2.3%** |
| codex `.polecat-codex` (4 rigs) | 0 | 626 | **100%** |

Per rig: gc-toolkit 579/17 (2.8%), gascity 222/4 (1.7%), shutupandlisten 59/0,
signal-loom 48/0. Review beads route to the codex pool essentially without
exception — in gc-toolkit, 435 of 466 review beads name `polecat-codex` as their
pool and exactly **one** names `.polecat`.

**F2 — the mechanical-trigger pattern exists in `review-dispatch-body.sh`, but it is wired into 2 of the 3 dispatch paths, and the one it is missing from mints most review beads.**

The epic's hard constraint says a migration needs a mechanical trigger, not an
instruction. gc-toolkit already built one. `assets/scripts/review-dispatch-body.sh`
emits the review bead's *description*, and that description (i) names the
`signoff-review` skill, (ii) forbids substituting any other review method, and
(iii) **inlines the skill's text verbatim** so the bead is self-contained for a
reviewer whose catalog lacks it. It is gate-asserted by
`review-dispatch-body.test.sh`, including that both modes name the skill and its
path.

The trigger is a property of the **bead**, not of the agent's prompt or catalog.
That is the pattern every MIGRATE below should copy.

**Coverage, measured — and it is partial.** The emitter has exactly two callers:
`assets/scripts/check-set-heal.sh:183` (the empty-check-set repair) and
`assets/scripts/reconcile-merged-prs.sh:176` (the stale-gate re-review). Both are
*repair* paths. The path that mints a review bead in the normal case — the
refinery's own first-round signoff dispatch at
`formulas/mol-refinery-patrol.toml:1693` — calls bare
`gc bd create "$REVIEW_TITLE" -t task --json`, with no `--body-file`, and so
dispatches a **title-only** bead carrying no method at all.

The census agrees. Of the 60 most recent review beads (`task_kind=review`, open
and closed), **45 (75%) have an empty description**; the 15 that carry one begin
with the emitter's own first line, `## Method: the signoff-review skill`. This
ledger's own signoff is an instance: review bead `tk-p7fcn`, the pre-open gate on
this branch, has description length 0 — the reviewing polecat was handed a title
and chose its own method.

Note what a title-only bead rules in. `check-set-heal.sh:2435` mints a pre-open
review under the *same* title shape as the patrol, so the title alone does not
identify the producer — but heal and reconcile both attach the body and only omit
it on their loudly-warned fail-soft path. So an empty description means either the
first-round patrol dispatch (which never attaches one) or a repair path whose
emitter could not be resolved. Both are delivery failures for the method; only the
first is by construction, and it is the one that explains 45 beads.

So the pattern is right and the channel is real, but it does not yet reach the
dispatch that matters. Any disposition that assumes review beads "already carry
their method" is describing a quarter of them. What that costs the MIGRATE
verdicts is recorded in §6; the remedy — wiring the first-round dispatch and
gate-asserting it — is remediation, and therefore out of scope for this bead.

The same caveat applies to F1's disposition in the other direction: the residual
non-impl work on the claude pool also arrives as a dispatched bead, so the
channel is *available* there too — but available is not wired, and no emitter
fills it for research/investigation beads today (§6, second MIGRATE row).

The skill itself already draws the boundary explicitly: *"Everything past this
point — which marker lands on the anchor, how a rework child is filed, when the
review bead closes — belongs to the non-impl done sequence in your prompt. That
is its source of truth; this skill does not restate it."* The fragment and the
skill are complementary halves, not duplicates. Moving the gate mechanics into
the same delivery channel closes the split.

**F3 — `operational-awareness` is the only fragment in literally every agent.**

6,762–6,764 B in all nine captured roles. With 22 gc agent sessions live at
capture time that is ~148,800 B of the same text resident across the city at one
moment. It comes from `[agent_defaults] append_fragments` in city.toml but the
content is **base-pack** (`gastown/template-fragments/operational-awareness.template.md`,
6,803 B at the pin). Per the epic's non-goals and pack principle 1, this is
recorded as a finding, not proposed for upstream change.

**F4 — the fragment's own non-impl detector misfires on rework children.**

Detection rule 1 is "`metadata.pr_number` or `metadata.pr_url` is set → non-impl".
The `REQUEST_CHANGES` arm of the same fragment files rework children stamped with
`pr_url`, `pr_number` **and** `existing_pr` at creation. A rework child is an
implementation bead that produces commits, yet it satisfies rule 1 at done time
and would take the non-impl path — closing itself and never reaching the refinery.

145 beads in gc-toolkit carry a `polecat/*` branch together with both a PR
reference and `existing_pr`/`rejection_reason`. The pipeline has not stranded
them, which is itself informative: **the 70 KB block is not mechanically
executed, it is read and judged.** That weakens the "always-on is a guarantee"
argument for this specific fragment — the guarantee it buys is already
conditional on the agent's judgement.

**Now latent, not live (noted by tk-n7dg4).** Rework children are dispatched to
`metadata.fix_target_pool`, which is the claude polecat pool — verified on review
bead `tk-ukji9`, whose `fix_target_pool = gc-toolkit/gc-toolkit.polecat`. Candidate
1 (tk-0981e, PR #299) has since dropped `polecat-non-impl-done` — and with it this
misfiring detector — from that pool, so a rework child no longer carries the
detector at done time; the misfire bites only if the fragment is ever restored to
the claude pool. Still worth its own bead so the rule is correct if that happens
(cross-reference `tk-4dvem`); the correct rule is almost certainly "`pr_number` set
**and** `task_kind = review`", or the zero-commit fallback alone.

**F5 — three defines render zero live bytes today, and none is a clean delete: one is pinned by live references, two are dormant agents.**

- `cycle-recycle` (117 B) — **zero live bytes, but not a free delete.** The
  define is named by no `inject_fragments_append` list, so it renders into zero
  prompts, and the behaviour it once carried now ships as a Claude `Stop` hook in
  `overlays/cycle-recycle/` (`.claude/settings.json` + `hooks/cycle-recycle.sh`).
  But the *file* `template-fragments/cycle-recycle.template.md` is still cited as
  the canonical policy source by two live artifacts — `heartbeat-no-consent-ui`
  (a fragment injected into deacon+witness) and `skills/handoff/SKILL.md` — plus
  the overlay-wiring comments in `pack.toml`. Deleting the file would dangle those
  pointers, so it is removable only after they are repointed (a follow-up, out of
  scope for this bead); until then it stays. The define is dead weight; the file is
  load-bearing.
- `layered-startup-discovery-boot` (7,798 B) — **dormant, not dead**. Still named
  in `pack.toml`'s boot patch, but boot is retired to `mode = "on_demand"` and
  has no `work_query`, so it never spawns (0 live sessions). Costs 0 live bytes
  today; costs 7,798 B/spawn the moment boot is reverted to `mode = "always"`.
- `thread-role` (2,992 B) — **dormant**. `mayor-thread`/`mechanik-thread` are
  operator-spawned only (`work_query = "printf '[]'"`). Real agents, currently
  unspawned.

The distinction matters for the shortlist: none of the three is a live-byte
saving. Deleting a dormant define saves **no live bytes** — the cost is
counterfactual, paid only if the agent is revived — and `cycle-recycle`, though it
too renders zero live bytes, is not even a clean delete, because its file is
pinned by the live references above. There is no free hygiene delete in this group.

**F6 — the mechanik carries the heaviest gc-toolkit-authored surface after the polecat.**

23,889 B of gc-toolkit content (70.7% of its 33,786 B prompt): native prompt
8,566 B across three spans, `watch-dispatched-work` 6,152 B,
`upstream-engagement` 5,335 B, `convoy-integration-branch-mayor` 2,721 B,
`canonical-self-rename` 624 B, `operator-next-step-trailing` 491 B. Single
long-lived session, so per-spawn cost is paid rarely — but `wake_mode = "fresh"`
means every drain re-pays it.

**F7 — city.toml `[[rigs.patches]]` is a real and unbudgeted line item for one rig.**

The gascity rig's two patches add **17,067 B to every polecat spawn**
(`rebase-conventions` 11,102 + `polecat-patterns` 5,965) and **24,764 B to every
refinery spawn** (`rebase-conventions` + `refinery-rebase-handling`). That makes
the gascity polecat the heaviest agent in the city at 119,620 B. These live in
`packs/gascity-keeper/template-fragments/` and are in the epic's scope.

**F8 — out-of-pack context is smaller than the pack's own, but not negligible.**

Measured: auto-memory index `MEMORY.md` **16,721 B** (112 memory files, 446,569 B
on disk, of which only the index is standing); harness skills listing **2,125 B**;
`gc prime --hook` SessionStart injection **2,345 B**; `gc bd prime` **5,901 B**
when invoked. **No `CLAUDE.md` exists** at the rig root, city root, user level, or
in the polecat work dir — that source is zero here.

Not measurable from disk: the provider's own system preamble and tool schemas.
These are the epic's declared out-of-scope-for-remediation, and no honest number
can be given for them without provider introspection; they are excluded rather
than estimated.

Even taking only what is measurable, the controllable fraction is decisive: of
~123,400 B of measurable standing context for a polecat, **74,099 B (60%) is
gc-toolkit fragments** and 70,043 B is one file.

---

## 6. Candidate table — dispositions

Every gc-toolkit fragment, with a verdict. "Live bytes" is the rendered cost in
prompts that actually spawn today.

| Fragment (define) | Live B/spawn | Injected into | Disposition | Reason | Est. saving |
|---|---:|---|---|---|---:|
| `polecat-non-impl-done` | 70,043 | polecat, polecat-codex | **NARROW** (drop from `polecat`, keep on `polecat-codex`) | 2.3% use on the claude pool vs 100% on codex (F1) | **70,043 B/spawn** on the pool running 97.7% of impl work |
| ↳ same, codex pool | 70,043 | polecat-codex | **KEEP — measured non-saving** | the codex pool runs the non-impl path on 100% of spawns (F1), so relocating the procedure into the bead description moves the same bytes into the same context window by another route — a transfer, not a cut (see §7, candidate 2). The prerequisite this row once blocked on has since landed (tk-dy7sb / PR #304), so a "BLOCKED" verdict would now misread as "ready to proceed" | **0 (relocation, not elimination)** |
| `layered-startup-discovery-witness` | 9,177 | witness | **KEEP** | supersedes a live base-pack bug (ephemeral wisp reads, tk-1waw2); witness spawns are patrol-rate | — |
| `layered-startup-discovery-boot` | **0** | boot *(never spawns)* | **DELETE** | dormant since lx-8bb1; `mode = "on_demand"`, no `work_query` (F5) | 0 live B; 7,798 B/spawn avoided if boot is ever revived |
| `watch-dispatched-work` | 6,152 | mechanik | **COMPRESS** | procedure-shaped ("### The ritual", "### Event grammar"); one long-lived agent, so migration gains little, but the prose is compressible | ~2,000 B |
| `upstream-engagement` | 5,335 | mechanik | **KEEP** | gascity-fork-specific doctrine the mechanik acts on continuously | — |
| `layered-startup-discovery-refinery` | 3,704 | refinery | **KEEP** | same base-pack-bug supersession as the witness slice | — |
| `layered-startup-discovery-deacon` | 3,226 | deacon | **KEEP** | as above | — |
| `convoy-integration-branch-mayor` | 2,721 ×2 | mayor, mechanik, mayor-thread | **KEEP** | both injectees dispatch convoys and can act on it | — |
| `polecat-append-notes` | 2,583 | polecat, polecat-codex | **KEEP** | corrects a destructive default (`--notes` replaces) in the sequence *every* polecat runs; 100% hit rate — the anti-case to `polecat-non-impl-done` | — |
| `thread-role` | **0** | mayor-thread, mechanik-thread *(unspawned)* | **KEEP** | dormant, not dead; real agents, operator-spawned (F5) | 0 |
| `heartbeat-no-consent-ui` | 1,565 | deacon, witness | **KEEP** | small, and both are patrol agents that act on it | — |
| `polecat-convoys` | 825 | polecat, polecat-codex | **KEEP** | small; applies to any polecat under an owned convoy | — |
| `file-work-records` | 648 | polecat, polecat-codex | **KEEP — reference implementation** | 648 B of always-on text that *names* a 2,148 B on-demand skill. This is the shape the epic wants; do not migrate it, copy it | — |
| `canonical-self-rename` | 617 | deacon, mayor, mechanik | **KEEP** | small, identity hygiene | — |
| `operator-next-step-trailing` | 491 | mayor, mechanik, mayor-thread | **KEEP** | small, and the operator-facing agents act on it every reply | — |
| `cycle-recycle` | **0** | *nothing (define uninjected; file referenced)* | **KEEP — referenced** | define renders zero live bytes, but its file is cited as policy by `heartbeat-no-consent-ui` (deacon+witness) and `skills/handoff`; repoint those before any delete (F5) | 0 live B (not a clean delete) |
| *(city.toml)* `rebase-conventions` | 11,102 / 11,102 | gascity polecat + refinery | **NARROW** | ~⅓ of it is refinery-only force-push/re-pour policy a polecat cannot act on | ~4,000 B/spawn, gascity only |
| *(city.toml)* `polecat-patterns` | 5,965 | gascity polecat | **KEEP** | rig-specific and polecat-actionable | — |
| *(city.toml)* `refinery-rebase-handling` | ~13,600 | gascity refinery | **KEEP** | refinery acts on it every rebase | — |
| *(base pack)* `operational-awareness` | 6,762 | **every agent** | **FINDING ONLY** | base-pack content; epic non-goal forbids proposing an upstream change (F3) | — |
| *(sub-pack)* `keeper/prompt.template.md` | 50,480 *(source)* | keeper *(asleep)* | **COMPRESS** | second-heaviest artifact in the pack; unmeasured live | unquantified until captured |

### MIGRATE dispositions and their mechanical triggers

Per the epic's hard constraint, every MIGRATE must name the trigger that fires it.

| Migration | Mechanical trigger | Status |
|---|---|---|
| `polecat-non-impl-done` → review-method delivery for the **codex** pool | the review bead's *description*, emitted by `assets/scripts/review-dispatch-body.sh`; the first-round dispatch at `formulas/mol-refinery-patrol.toml:1693` now emits it too (tk-dy7sb / PR #304), so the channel is fully wired | **KEEP — measured non-saving.** The prerequisite this row once blocked on has landed, but wiring does not make the migration worth doing: the codex pool needs the procedure on 100% of spawns (F1), so moving it into the description relocates the bytes into the same window rather than eliminating them, and codex sessions almost never compact (`continuation_epoch=1` for 37 of 38 sampled sessions) so no meaningful multiplier applies. Demoted to *explicitly not recommended* — see §7, candidate 2 |
| `polecat-non-impl-done` → residual non-impl work on the **claude** pool (research/investigation, 21 beads) | none today. These are slung by the mayor/mechanik with a free-text description; no emitter guarantees the method is named | **BLOCKED** — needs a `research-dispatch-body.sh` sibling, or the disposition reduces to NARROW-only with the claude pool losing the procedure for ~2% of its beads |

**The two rows differ now.** The claude row (residual research/investigation work)
is still BLOCKED, and its blocker is not an opinion: per the epic's rule an
instruction-only remedy does not count, and no emitter fills a research bead's
description today. The codex row is no longer blocked — its emitter is now wired
into the first-round dispatch (tk-dy7sb / PR #304) — but wiring it revealed that
the saving was never there to bank: on a pool that reads the procedure on 100% of
spawns, the dispatch body relocates the bytes rather than eliminating them (F1;
§7, candidate 2). So the codex row is recorded as KEEP — measured non-saving, and
the claude row as BLOCKED. Neither is blocked on skill discovery — §4(a) settles
that — and neither is fixable by flipping `inject_assigned_skills`.

This codex row has been corrected twice. An earlier draft of this ledger read the
emitter's existence as coverage and marked it READY; that was wrong because the
emitter was not yet wired into the first-round dispatch, where three of every four
review beads came from — a trigger that exists somewhere is not a trigger that
fires on the path in question. That wiring has since been done (tk-dy7sb /
PR #304), which removes the original blocker — but it does not make the migration
worth doing, because the saving it was ranked for is relocation, not elimination
(§7, candidate 2). The lesson stands in a sharper form: even a trigger that fires
on the right path relocates rather than eliminates when the pool reads the content
on every spawn.

---

## 7. Ranked shortlist

In expected-saving order. Risks stated plainly.

**1. Drop `polecat-non-impl-done` from the `polecat` patch in `pack.toml`; keep it on `polecat-codex`.**
Saving: **70,043 B/spawn (~17.5k tokens)** on the pool that runs 97.7% of
implementation work — a 68% cut to the polecat prompt, 102,550 → 32,511 B.
Multiplied again by every compaction (§2).
Risk: **real but bounded.** ~2.3% of claude-pool beads are non-impl and would
lose the done-sequence procedure. They would fall back to the impl done sequence
and hand a zero-commit branch to the refinery — the exact failure the fragment's
own preamble describes. Mitigate by accepting that ~21 beads over the measured
window need a human nudge — **not** by "landing candidate 2 first": candidate 2
is now explicitly not recommended (its prerequisite landed, but its saving is
relocation, not elimination — see below), and in any case it delivers the
procedure through *review* dispatch, while the claude pool's residual non-impl
beads are research/investigation. Their remedy is the `research-dispatch-body.sh`
sibling (§6, second MIGRATE row), which nobody has written.
Cross-check before landing: `doctor/check-polecat-fragment-sync` compares the two
inject lists and errors on divergence — this change makes them diverge *on
purpose*, so that check must be taught the exception or it will fail the build.

**2. — Withdrawn; moved to *Explicitly not recommended* (below).**
Formerly "wire the first-round dispatch, extend the payload, then drop the fragment
from `polecat-codex` too", ranked at ~69,400 B/spawn. Its blocking prerequisite has
since landed (tk-dy7sb / PR #304) — but that unblocks nothing to bank: the promised
saving is relocation, not elimination, because the codex pool reads the procedure
on 100% of its spawns. Full reasoning and the reproduction command are under
*Explicitly not recommended*.

**3. File the rework-child misdetection (F4) as its own bug bead.**
Saving: 0 bytes. Listed here because the audit surfaced it and it is a live
correctness hazard in the most-quoted block in the pack — and because it is
evidence for candidate 1's premise that the block is judged, not executed.
Risk: none to fix; the risk is leaving it.

**4. Narrow `rebase-conventions` so the polecat slice excludes refinery-only policy.**
Saving: ~4,000 B/spawn, gascity rig only.
Risk: low. Requires splitting one fragment into two defines; the force-push and
re-pour sections are already separately headed.

**5. Compress `watch-dispatched-work` and the keeper prompt.**
Saving: ~2,000 B/spawn (mechanik) and unquantified (keeper).
Risk: low, but the keeper number should be measured live before anyone spends
effort — capture it the next time the keeper wakes.

**6. Do not delete `cycle-recycle` outright — repoint its references first (follow-up).**
Saving: 0 live bytes.
The define renders into no prompt, but the file
`template-fragments/cycle-recycle.template.md` is cited as the canonical policy
source by `heartbeat-no-consent-ui` (injected into deacon+witness) and
`skills/handoff/SKILL.md`, so deleting it dangles two live references. Removing it
cleanly means first repointing those citations — worth a follow-up bead, not the
one-line hygiene delete an earlier draft assumed (F5).
Risk: deleting as-is breaks the two references; leaving the file costs nothing.

### Explicitly not recommended

- **Do not re-enable `inject_assigned_skills` for polecats.** It would add ~2,830
  B/spawn to duplicate an index the harness already supplies (§4a, §4b).
- **Do not delete `layered-startup-discovery-boot` or `thread-role` for savings.**
  Both render zero live bytes; deleting them is inventory hygiene at best, and
  `thread-role` backs agents that are merely unspawned, not retired.
- **Do not touch `file-work-records` or `polecat-append-notes`.** They are the two
  fragments whose always-on placement is clearly earned — one is a pointer to a
  skill, the other corrects a destructive default on a path every polecat takes.
- **Do not drop `polecat-non-impl-done` from `polecat-codex` (former candidate 2).**
  It was ranked #2 at ~69,400 B/spawn on the assumption that delivering the
  procedure through the review bead's description would remove it from the prompt.
  It would not, for four reasons. **(1) Relocation, not elimination:** the codex
  pool runs the non-impl signoff path on 100% of its spawns (F1), so the procedure
  must reach the context window on every spawn no matter the channel — routing it
  through the description instead of the system prompt moves the same bytes into
  the same window. This is the exact inverse of candidate 1, whose saving was real
  precisely because 97.7% of claude-pool beads never reach that path. **(2) No
  compaction multiplier:** codex polecat sessions almost never compact — in a
  38-session sample (2026-08-11, via the command below) 37 carried
  `continuation_epoch=1` and one had compacted once (epoch 2) — so they typically
  wake, run one review, and drain at epoch 1, and the per-spawn cost is essentially
  never re-paid (the amplification that would rescue the number, §2, is ~0 here).
  **(3) Net-negative on storage:** at ~27 review beads/day
  (28 on 08-11, 31 on 08-10, 21 on 08-09) a ~70 KB payload per description is
  ~2 MB/day of new Dolt description rows, permanently, against the city's standing
  guidance to keep bead volume down. **(4) Highest correctness risk on the list:**
  the relocated content is the gate machinery that stamps `check.<gate>=green@<oid>`,
  dismisses superseded reviews, pins the PR repository from `pr_url`, files rework
  children, and enforces the round cap — §7 already rated it "a correctness risk,
  not a cost one." The wiring prerequisite it once blocked on has since landed
  (tk-dy7sb / PR #304), which is exactly why leaving it marked "BLOCKED" would now
  read as "ready to proceed" — the opposite of the conclusion. Reproduce reason (2)
  — codex session beads are ephemeral (not returned by `gc bd list`, which is why an
  earlier draft's `gc bd list --status=closed … .metadata.template` reproducer
  silently returned nothing), so reach them through the closed review beads they
  produced, each recording its producing session in `metadata."gc.session_id"`, then
  read each session's epoch directly:
  ```bash
  gc bd list --metadata-field task_kind=review --status=closed --limit 40 --json \
    | jq -r '[.[].metadata."gc.session_id" // empty] | unique | .[]' \
    | while read -r sid; do
        gc bd show "$sid" --json \
          | jq -r '.[0] | select((.metadata.template // "") | test("polecat-codex"))
                   | .metadata.continuation_epoch'
      done | sort | uniq -c
  # 2026-08-11 sample → "37 1" and "1 2": 37 of 38 codex sessions never compacted
  # (epoch 1), one had compacted once (epoch 2). Change the jq tail to emit
  # "\(.id) epoch=\(.metadata.continuation_epoch)" to list each session by id.
  ```

---

## 8. What this changes about the epic's premises

The epic's measured baseline listed `polecat-non-impl-done` at 70,103 B and asked
what fraction of polecat spawns reach the non-impl path. Both are now settled:
70,043 B rendered, and 2.3% on the claude pool / 100% on the codex pool. The
epic's guess that this is "the headline finding" is confirmed.

Two premises need adjusting:

1. **The epic assumed skill discovery might be off for polecats.** It is not. The
   provider harness indexes the sink directory independently of gc's appendix, and
   this session proved a polecat can invoke a skill from it. The real delivery
   risk is a **stale sink** on the codex pool, which no prompt-side flag affects.

2. **The epic framed migration as fragment → skill.** The pattern that actually
   works in this pack is fragment → **dispatch body**, because the dispatch body
   is a property of the bead and therefore mechanical, while a skill invocation is
   a property of the agent and therefore a hope. `review-dispatch-body.sh` is the
   precedent, and it hedges by inlining the skill rather than relying on it.
   Migrations under this epic should target that channel — subject to two tests a
   candidate must pass before it is ranked. **First, the channel counts only where
   it is wired:** the emitter that fills the bead description has to run on the
   dispatch path in question, not merely exist somewhere in the pack. The codex row
   was blocked on exactly this until the first-round dispatch was wired (tk-dy7sb /
   PR #304). **Second — and this holds even once the channel is wired — relocating
   always-on content saves nothing on a pool that already reads it on every spawn.**
   Moving the content into the dispatch body just delivers the same bytes into the
   same context window by another route. A real saving comes only from spawns that
   never reach the content (the claude pool, 97.7% of whose beads never take the
   non-impl path — the basis of candidate 1) or from compaction re-payment
   (`gc prime` re-emitting the whole prompt after every compaction); **both effects
   must be measured, not assumed.** The codex-pool migration (candidate 2) now
   passes the first test but fails the second — it runs the non-impl path on every
   spawn and its sessions almost never compact (`continuation_epoch=1` for 37 of 38
   sampled sessions) — which is why it is *explicitly not recommended* (§7) despite
   its prerequisite having landed.
