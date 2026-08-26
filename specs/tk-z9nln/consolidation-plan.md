---
name: Consolidation plan — take the 66k-line shell surface and make it simpler (2026-08-23)
description: The future-state half of the tk-z9nln audit. Four ordered consolidation targets with measured lines-removed, the bug class each eliminates, risk, and sequence — plus two of the brief's own targets dropped on measurement. Read it to decide what to simplify next; it is a plan with a finite life, not a grounding doc.
---

# Consolidation plan: make the shell surface simpler

**Measured 2026-08-23 against `origin/main` at `da63241`.** Every number
below carries the command that produces it. The surface moves ~3,300 shell
lines a day, so **re-run the commands before acting** — several of the
brief's own figures had already moved when this was written, and one of
its four targets dissolved on measurement.

## Scope

**Mandate.** What to merge, delete, or leave alone in gc-toolkit's shell
surface, in what order, and why. It is the future-state half of the
`tk-z9nln` audit, following `specs/tk-z9nln/divergence-record.md`
(current state) and `docs/lifecycle-composition.md`.

**Boundaries.** It proposes; it implements nothing. Each surviving target
should be filed as its own bead from this document. It is **not** a freeze,
a line budget, a new gate, or a review step — tactical fixes keep flowing
per the operator's constraint (*"the city needs to work"*). It does not
propose a rewrite, a language migration, or a new abstraction layer.

---

## The one screen

Ordered by (lines removed × brittleness removed) / risk. Do them in this order.

<!-- plan-targets -->

| # | Target | Lines out | What stops happening | Risk | Bead |
|---|---|---|---|---|---|
| **1** | **Close the graph.v2 step chain** in the local `mol-polecat-work.toml` mirror; retire the quiesce sweeper | **2,099** | 461 stranded beads (62% of this rig's open ledger), growing ~40/day; every polecat's husk-classification toll | Medium | `tk-zab6q` (step chain), `tk-eh0r3m` (sweeper) |
| **2** | **Finish the helm consolidation** — `gc-helm.sh`'s board half becomes a thin renderer | **~2,370** | "fixed on one board, not the other" — already recorded 3× | Low-Med | `tk-clvkf6` |
| **3** | **Retire `reconcile-refinery-handoffs.sh`** — its root cause was fixed in the formula | **761** | A repair pass for a defect the writer can no longer produce | Low | `tk-qf2l0j` |
| **4** | **One control-char scrubber** — 7 definitions, 3 names, 2 incompatible byte sets | ~10 | Silent disagreement about whether TAB survives a bd read | Very low | `tk-fdjufq` |
| — | ~~Merge the `reconcile-*` family~~ | **0** | **Dropped — already done.** `refinery-reconcile.sh` is the driver | — | none — dropped, already done |
| — | ~~Add a shared library~~ | **~180** | **Dropped — not worth it.** The duplicates are one-liners | — | none — dropped, not worth it |

Target 1 needs two beads because it is two deletions, and separating them is
what let the second one go unfiled for a day: `tk-zab6q` landed the close path
in PR #443, while every one of the target's 2,099 lines lives in the sweeper
that `tk-eh0r3m` retired. The Bead column and `doctor/check-plan-targets-filed`
were added by `tk-dks4kk` after that gap; `docs/file-structure.md` carries the
rule.

**Total: ~5,235 lines, ~85% of it in the top two.**

**The finding that should change what you do first.** Target 1 has been
believed unfixable in this repo since 2026-08-17. It is not. Both
`specs/tk-y389z/step-close-root-cause.md` (§6, §9) and the divergence
record (D6) state that the fix lives upstream in `gastownhall/gascity-packs`,
"which is why it has not landed here." **PR #385 landed a gc-toolkit mirror
of `mol-polecat-work.toml` on 2026-08-18** — the day after the spec was
written, four days before the divergence record — and that mirror's own
header says it "is what every polecat in the city actually runs." The
highest-value consolidation available has been blocked for five days by a
repo-ownership claim that was already false when it was last repeated.

---

## The reframe: line count is the wrong unit

Before the targets, three measurements that change how to read every number
in the brief.

### 1. Implementation shell is 44% code. Half of it is comments.

```bash
git ls-files '*.sh' | grep -vE '(test|tests)' | while read -r f; do
  printf '%s %s %s\n' "$(wc -l < "$f")" "$(grep -cE '^[[:space:]]*#' "$f")" "$(grep -cE '^[[:space:]]*$' "$f")"
done | awk '{t+=$1;c+=$2;b+=$3} END{printf "total=%d comment=%d (%d%%) blank=%d code=%d (%d%%)\n",t,c,c*100/t,b,t-c-b,(t-c-b)*100/t}'
# total=35401 comment=17676 (49%) blank=2061 code=15664 (44%)
```

Per-file it is starker: `check-set-heal.sh` is 3,291 lines and **1,148 lines
of code** (61% comment). `quota-park-nudge.sh` is 64% comment.

Those comments are not padding — each names the bug it closes, the live case
that reproduced it, and the exclusions that are hazards rather than caution.
They are why a 3,291-line healer is maintainable at all. **A plan that
optimises the line count will delete the design record and leave the
machinery.** Every figure below is therefore given as total lines (what you
would see disappear) with the understanding that ~44% of an impl file is
executable.

### 2. The dead code is already gone; the complexity is live

The brief measured 335 lines of dead code. Nothing meaningful has
accumulated since. There is no janitorial win here — every target below
removes *working* code, which is why each one needs a root-cause argument
rather than a deletion list.

### 3. The ledger is in worse shape than the source tree

```bash
bd list --status open --limit 0 --json | tr -d '\000-\037' \
  | jq '[length, ([.[] | select(.metadata["gc.root_bead_id"] != null)] | length)]'
# [749, 461]
```

**461 of 749 open beads (62%) are stranded graph.v2 step beads.** The
divergence record measured 238 of 471 (50.5%) on 2026-08-22. One day later
the absolute count has **nearly doubled**. This is the same defect as Target
1, and it is the reason Target 1 outranks everything else in this document
despite removing fewer lines than the brief's headline target.

---

## Target 1 — close the graph.v2 step chain

**Removes 2,099 lines. Stops a 461-bead husk population growing ~40/day.
Risk: medium. Do this first.**

### What is wrong

A graph.v2 step advances only by closing its own bead. `mol-polecat-work`
contains no close path — it says the opposite:

```bash
grep -n 'NEVER CLOSE BEADS' formulas/mol-polecat-work.toml
# 51:**NEVER CLOSE BEADS.** You must not run `bd close` or set status=closed.
```

So every completed polecat run strands its whole seven-step chain plus a
`workflow-finalize` that can never become ready:

```bash
bd list --status open --limit 0 --json | tr -d '\000-\037' \
  | jq -r '[.[] | select(.metadata["gc.root_bead_id"] != null) | .metadata["gc.step_id"]]
           | group_by(.) | map({s:.[0],n:length}) | sort_by(-.n) | .[] | "\(.n)\t\(.s)"' | head -7
# 62  mol-polecat-work.implement
# 62  mol-polecat-work.preflight-tests
# 62  mol-polecat-work.self-review
# 62  mol-polecat-work.submit-and-exit
# 62  mol-polecat-work.workflow-finalize
# 61  mol-polecat-work.workspace-setup
# 39  mol-polecat-work.load-context
```

Open `workflow-finalize` beads by creation day — the rate, not just the stock:

```bash
bd list --status open --limit 0 --json | tr -d '\000-\037' \
  | jq -r '[.[] | select((.metadata["gc.step_id"] // "") | endswith("workflow-finalize"))
           | .created_at[0:10]] | group_by(.) | map({d:.[0],n:length}) | .[] | "\(.d)  \(.n)"'
# 2026-08-17  2 · 2026-08-19  4 · 2026-08-20  6 · 2026-08-21  6 · 2026-08-22  39 · 2026-08-23  8
```

`assets/scripts/quiesce-completed-workflows.sh` (877) + its test (1,222)
exist solely to stop those husks being re-offered. It **contains the
containment and refuses the cure on purpose** — its header says finalizing
the chain "is the durable upstream fix … and is deliberately out of scope
here."

### Why the ruling that blocked it is stale

`specs/tk-y389z/step-close-root-cause.md` §6 splits the seven steps across
two upstream repos and concludes the terminal `submit-and-exit` sits in
`gastownhall/gascity-packs`, which has no rig in this city. That was true on
2026-08-17. It stopped being true the next day:

```bash
git log --format='%h %cs %s' --diff-filter=A -- formulas/mol-polecat-work.toml
# 4146a2e 2026-08-18 mol-polecat-work submit gate rejects the rework path ... (tk-3yj8g) (#385)

sed -n '4,12p' formulas/mol-polecat-work.toml
# ## gc-toolkit MIRROR of the gastown formula of the same name
# This file SHADOWS `gastown/formulas/mol-polecat-work.toml`: the pack search
# order resolves `rigs/gc-toolkit/formulas` after `gastown/formulas`, so this
# copy is what every polecat in the city actually runs.

grep -nE '^\s*id\s*=' formulas/mol-polecat-work.toml
# 92:id = "workspace-setup"   267:id = "self-review"   350:id = "submit-and-exit"
```

The mirror is one of the five deliberate shadows documented in
`docs/gascity-packs.md` §7a. It owns `submit-and-exit` — the step §6
identifies as "the one that unblocks finalize". Confirmed live: this
document's own molecule root carries
`gc.formula_source = /home/zook/loomington/rigs/gc-toolkit/formulas/mol-polecat-work.toml`.

### Why the tooling is already here

§5 of the spec names the trap — `GC_BEAD_ID` is unset in a pool polecat and
`GC_TRIGGER_BEAD_ID` is spawn-fixed, so the obvious patch is a silent no-op —
and names the correct resolution: by the `(assignee, gc.step_ref)` pair.
gc-toolkit already ships exactly that, and it already handles the second
constraint §5 raises (a step bead executes at `open`, never `in_progress`):

```bash
sed -n '/^usage()/,/^}/p' assets/scripts/step-close.sh | sed -n '3p;18,21p'
# usage: step-close.sh --step <formula.step-id> [--outcome <v>] [--bead <id>] [--dry-run]
# session's for this step is closed at status `in_progress` or `open` — a
# graph.v2 step is assigned by the graph rather than by the claim, so it
# executes at `open` and never reaches in_progress (tk-jww3y). `in_progress`
# is resolved first; `open` only if that finds nothing.
grep -c 'step-close' formulas/*.toml | grep -v ':0'
# mol-feedback-distiller:20 · mol-doc-keeper-memory-audit:11 · mol-doc-keeper-drift-audit:9 · mol-feedback-miner:8
```

Four sibling formulas in this repo self-finalize through it across 48 call
sites and strand nothing. The pattern is proven in-repo; `mol-polecat-work`
is the formula that does not use it.

### What comes out

| Artifact | Lines |
|---|---|
| `assets/scripts/quiesce-completed-workflows.sh` | 877 |
| `assets/scripts/quiesce-completed-workflows.test.sh` | 1,222 |
| **Total** | **2,099** |

Not counted, and worth more than the lines: the 461 stranded beads, the
~40/day regrowth, and the per-polecat toll the divergence record documents —
every polecat that claims a husk must classify and de-route it, *and a
misclassification is destructive* because `workspace-setup` rebuilds a branch
that may be parked under a live review.

### The bug class eliminated

Work that is finished but whose graph never says so — re-offered forever,
indistinguishable from real work at the point of claim.

### Risk: medium — and where it actually sits

The design question is **which steps `submit-and-exit` closes and in what
order**, not whether the fix is reachable.

- Closing `load-context` *mid-flight* is the destructive move the quiesce
  header warns about: it unblocks `workspace-setup` and walks the next
  polecat onto a branch that is already green-gated and PR'd, where a push
  stales `check.<gate>=green@<oid>` and blocks the open PR. Closing the whole
  chain **at submit time, in dependency order**, is a different operation —
  that is what the four sibling formulas do.
- Three of the seven steps (`load-context`, `preflight-tests`, `implement`)
  are `mol-polecat-base`'s, upstream in `gastownhall/gascity` (a rig exists
  here). `step-close.sh` resolves by identity, so one session can close every
  step it owns — but whether the mirror *should* close steps it does not
  declare is the call to make deliberately, not by default.
- The formula's own `NEVER CLOSE BEADS` prose must be reconciled with the
  step-close contract in the same change, or the next reader correctly
  follows the rule and reintroduces the defect. **The work bead stays
  untouchable; the step bead must close.** `doctor/check-step-close-owns-bead`
  guards the wrong-close idiom and will not object.

Keep the sweeper until a full cycle finalizes cleanly, then delete it.

---

## Target 2 — finish the helm consolidation

**Removes ~2,370 lines. Risk: low-medium. Already the operator's decision.**

PR #406 ("one board, two views", merged 2026-08-22T05:30Z) was filed to stop
`gc-helm.sh` being a second implementation, and cited it at 1,532 lines. What
happened after it merged:

```bash
git log --format='%h %cI %s' -8 -- assets/scripts/gc-helm.sh | while read -r h w s; do
  printf '%6s  %s  %s\n' "$(git show "${h}:assets/scripts/gc-helm.sh" | wc -l)" "$w" "${s:0:58}"
done
# 1966  2026-08-22T17:10  fix(helm): a parked row rolls up its children ...
# 1866  2026-08-22T16:46  helm board: gc.takeaway averages 597 chars ...
# 1816  2026-08-22T16:31  gc-helm/gc-visit-open: enumerate_rigs reported four ...
# 1749  2026-08-22T14:49  helm board: colID=11 truncates 12-char ids ...
# 1741  2026-08-22T11:13  live-visit guards key only on gc.continuation_group ...
# 1712  2026-08-22T10:35  helm/converse: a routed subject's wait is free text ...
# 1532  2026-08-21T19:55  helm board reports active work as stranded ...   <- PR #406's number
```

**Six defect fixes, +434 lines, +28%, in the twelve hours after the PR that
argued for deleting the file.** (Note the `${h}:` braces — under zsh an
unbraced `"$h:path"` is mangled by the colon modifier and every count reads 0.)

The duplication is still there and still self-documented:

```bash
grep -n 'helm service\|helm-svc' assets/scripts/gc-helm.sh
# 97   # This mirrors the Go helm service's gather (services/helm/README.md,
# 734  #   `length`/`rpad`, and helm-svc's []rune) ...
# 1504 # helm-svc board derives the same two widths (services/helm/cmd/helm-svc/board.go).
# 1741 # This mirrors the Go helm service's gather (services/helm/README.md
grep -nE '^gather_|^resolve_waiting_status' assets/scripts/gc-helm.sh
# 1533 gather_anchors · 1648 gather_open_beads · 1681 gather_visits
# 1744 gather_meta_anchors · 1847 resolve_waiting_status · 1910 gather_inflight
git ls-files 'services/helm/cmd/*'    # only helm-svc — the thin CLI cmd/ was never created
```

### What comes out

The file splits cleanly. Lines 1–1053 are `takeaway`, `open`, `react` and
helpers — separate verbs, not board rendering, and they stay.
Lines 1054–1957 are `cmd_board` plus every `gather_*`: the duplicated half.

| Artifact | Lines | Note |
|---|---|---|
| `gc-helm.sh` board half (1054–1957) | 904 | becomes a thin renderer over `helm-svc` |
| `services/helm/cmd/helm-svc/contract_parity_test.go` | 668 | exists only to police this duplication |
| Board cases in `gc-helm.test.sh` (~472–end) | ~793 | ARGVCAP, PROJSHAPE, INFLIGHT, HUSK, PARKED, PKIDS … |
| **Total** | **~2,365** | |

**One brief correction.** The brief counts 1,294 lines of parity test by
pairing the above with `services/helm/web/contract_parity_test.go` (626).
That second file does **not** go away — it guards the Go↔TypeScript seam
(`src/contract.ts`), which survives this change untouched. There is also a
third, `internal/server/open_parity_test.go` (99), guarding the parser
against `gc-helm.sh`'s *printed sentences*; it shrinks with the `open` verb,
which is not in scope here. Only the 668-line file is a duplication tax.

### The bug class eliminated

"Fixed on one board, not the other" — already recorded as `tk-2v08m` and
`tk-fkeft` and named as a standing caveat in `docs/lifecycle-composition.md`.

### Risk: low-medium

The board is the operator's front door, and a thin renderer inherits the
service's availability: `gc-helm.sh` today answers from a cache when the
gather is slow, and the replacement must keep a degraded-but-useful mode
rather than printing an error. Verify the file has not moved again first —
it gained 434 lines in twelve hours.

---

## Target 3 — retire `reconcile-refinery-handoffs.sh`

**Removes 761 lines. Risk: low.**

The script recovers merge handoffs stranded by a near-miss refinery address
(`shutupandlisten/refinery` where the canonical identity is
`shutupandlisten/gc-toolkit.refinery`). `tk-0nn3f`'s own notes name the
root-cause site — the formula computing `REFINERY_TARGET` without the binding
prefix. **That site is fixed:**

```bash
grep -rn 'REFINERY_TARGET=' --include='*.toml' --include='*.md' . | grep -v '\.test\.'
# agents/_polecat-gemini/prompt.template.md:204:  ...{{ .BindingPrefix }}refinery"
# formulas/mol-polecat-work.toml:579:            ...{{binding_prefix}}refinery"
# formulas/mol-polecat-work.toml:601:            ...{{binding_prefix}}refinery"
```

Every automated writer now emits the qualified form. The pass is a repair
arm for a defect its writer can no longer produce.

**Downgrade before deleting.** A hand-composed assignee can still be wrong,
so do not simply delete the guard:

1. `doctor/check-routed-work-claimable/run.sh` already reports unclaimable
   routes, and `check-set-heal.sh` already flags a non-canonical assignee on
   a gating anchor (`reconcile-refinery-handoffs.sh:40` says so).
2. Confirm the repair arm has not fired since the formula fix before removing
   it — if it has, the writer set is wider than the formula and this target
   is void.

| Artifact | Lines |
|---|---|
| `assets/scripts/reconcile-refinery-handoffs.sh` | 420 |
| `assets/scripts/reconcile-refinery-handoffs.test.sh` | 341 |
| **Total** | **761** |

### The bug class eliminated

A healer outliving its disease — the pass still runs every refinery cycle
(`refinery-reconcile.sh` arm `a-addr`), costs a scan, and reads to a
maintainer as evidence the defect is still live.

---

## Target 4 — one control-character scrubber

**Removes ~10 lines. Fixes a real disagreement. Risk: very low.**

Not a line win; a correctness one. Seven definitions, three names, **two
incompatible byte sets**:

```bash
grep -rn '^scrub()\|^strip_ctrl()\|^strip_ctl()' --include='*.sh' . | grep -v '\.test\.'
# scrub()      tr -d '\000-\010\013\014\016-\037'   (keeps TAB, LF, CR)   x3
# strip_ctrl() tr -d '\000-\010\013\014\016-\037'   (keeps TAB, LF, CR)   x2
# strip_ctl()  tr -d '\000-\011\013-\037'           (DELETES TAB, keeps LF only)  x2
```

`strip_ctl` deletes TAB; the other two preserve it. Both feed jq parsing bd
output. Any pipeline that splits on TAB behaves differently depending on
which scrubber the author happened to copy — and nothing tests that they
agree, because they are not treated as one thing.

Pick one byte set, give it one name, and apply the pack's existing
marked-block + drift-test pattern (below) so the copies cannot diverge again.
Settle deliberately whether TAB survives: it is a field separator in several
of these pipelines.

---

## Dropped: merge the `reconcile-*` family

**The brief's Target 2. Already done — 0 lines available.**

The hypothesis was six independent passes that could become one driver plus
six predicates. They are already one driver plus predicates:

```bash
grep -n 'run_pass ' assets/scripts/refinery-reconcile.sh
# (a-addr) reconcile-refinery-handoffs · (a-norm) check-set-heal · (a-pre) pre-open-resolve
# (a0) merge-skill · (a1) reconcile-merged-prs · (a2) reconcile-gate-verdicts
# (b) reconcile-graduated-convoys
```

`refinery-reconcile.sh` (347 lines) is the driver, wired as one rig-scoped
order (`orders/refinery-reconcile.toml`), and **it is the merge cadence** —
the ordering between arms is load-bearing, not incidental (`check-set-heal`
must run before `merge-skill`; `reconcile-merged-prs` before
`reconcile-gate-verdicts`). The seventh, `reconcile-rig-checkouts.sh` (65
lines), is a city-scoped order doing an unrelated job (`git merge --ff-only`
per rig).

The shared name is the only thing these have in common. Their bodies answer
genuinely different questions and merging them would replace seven readable
passes with one script full of mode flags. **Do not force this merge.**

---

## Dropped: add a shared library

**The brief's Target 4. ~180 lines available — not worth the coupling.**

The duplicate-definition count is real and has grown:

```bash
git ls-files '*.sh' | grep -vE '(test|tests)' | xargs grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' \
  | sed 's/()//' | sort | uniq -c | sort -rn | awk '$1>1'
# 414 definitions, 313 distinct names -> 101 duplicate definitions across 45 names
```

But the *line* cost is not. Measuring each definition brace-balanced rather
than counting names:

| helper | defs | total lines | duplicated |
|---|---|---|---|
| `run_bounded` | 9 | 80 | 72 |
| `bd_pinned` | 6 | 42 | 35 |
| `sq` | 5 | 15 | 12 |
| `is_held` | 5 | 13 | 11 |
| `url_repo_q` | 4 | 16 | 12 |
| `is_alive` | 3 | 14 | 10 |
| `gcmux`, `die`, `scrub`, `print_lines`, … | 7–2 each | 1–2 each | ~28 |
| **Total** | | | **~180** |

Most are one-liners. `usage` (15 definitions) and `cleanup` (7) are
per-script by nature and not shareable at all.

Against that, three costs:

1. **There is no sourcing pattern in this pack, by design.** No
   `assets/scripts/*.sh` sources a sibling — verified: every apparent match
   is jq's `. as $b`. Adding one makes 43 standalone scripts depend on a
   resolvable library path across the sandboxed order-exec PATH, the doctor
   harness, and the step worktree.
2. **The readers span three media.** `check-set-heal.sh:553` states the
   constraint: readers are shell scripts, TOML formula bodies, and markdown
   template fragments. A TOML formula body cannot source a shell library.
3. **The pack already answers this**, at scale, with marked blocks plus a
   drift test that extracts every copy and fails on divergence — 79 marked
   sites, 31 drift tests:

```bash
grep -rn '^\s*#\s*>>>' --include='*.sh' --include='*.toml' --include='*.md' . | wc -l   # 79
git ls-files '*.test.sh' | xargs grep -ln '>>>' | wc -l                                  # 31
```

Trading ~180 lines for a new coupling across three media, when the pack has a
working answer, is the "abstracting instead of deleting" the brief rules out.
**Use the existing marked-block pattern for the scrubber (Target 4) and stop
there.**

---

## The pattern under all of this

Target 3 is a healer whose disease was cured. Target 1 is a healer whose
disease is curable in this repo and was believed not to be. That is the
mechanism worth naming, because it is what turned 1,604 lines into 67,162 in
ninety days:

**A defect is closed by shipping a compensating pass. The bead closes. The
root cause is never revisited, and the belief about who owns it freezes at
the moment the healer landed.**

Every root-cause bead behind the compensating third is `closed`:

```bash
for b in tk-p9ji9 tk-i48ca tk-f69ay tk-2cyxo tk-xesf6 tk-0nn3f; do
  printf '%-10s ' "$b"; gc bd show "$b" --json | tr -d '\000-\037' \
    | jq -r 'if type=="array" then .[0] else . end | .status'
done      # closed x6
```

Closed by shipping `quiesce-completed-workflows.sh`, `check-set-heal.sh`,
`recover-stranded-branches.sh`, `detect-parked-dispositions.sh`,
`detect-stalled-workflows.sh`, `reconcile-refinery-handoffs.sh` respectively
— **13,116 lines of compensating machinery** (37% of implementation shell):

```bash
git ls-files '*.sh' | grep -vE '(test|tests)' \
  | grep -E 'heal|reconcile|detect|sweep|quiesce|precheck|recover|stale' \
  | xargs wc -l | tail -1     # 13116
```

Not all of it is removable, and this plan does not pretend otherwise:

- `check-set-heal.sh` (3,291 + 5,112 test = **8,403**, the largest unit in
  the repo) guards the refinery boundary against merging ungated. Its root —
  merge-skill reading empty `check_set` as "no gates" — was *also* fixed
  (`tk-i48ca` notes: "merge-skill.sh reads none/off as no-gates"), but the
  pass has since absorbed the pre-open gate, review dispatch and the
  `fixable@` arm. It is now load-bearing architecture, not compensation.
  **Leave it alone.**
- `liveness-sweep-precheck.sh` (587) is not a healer at all — it is the
  cheap condition for `orders/liveness-sweep.toml` (`trigger = "condition"`),
  replacing a whole polecat session per pass with ~2.7s of jq. It is the
  shape this plan wants more of.
- `recover-stranded-branches.sh` (1,047) compensates a polecat dying between
  push and handoff. That handoff is a non-atomic multi-step sequence in the
  dying session's own shell; there is no small fix, and the recovery is real.
- `boot-health.sh` (371) is report-only by measured decision — nudging the
  deacon cost more than the disease.

**The check worth adding is not a line budget.** It is: *when a bead is
closed by shipping a compensating pass, does the root cause still have an
owner?* Targets 1 and 3 are both cases where the answer was "no" and the
compensation outlived its reason — one by five days, one by longer.

---

## Sequence, and what not to do

1. **Target 1** — file it now; it is the only target whose cost is
   compounding daily. Land the close path, watch one full cycle finalize,
   then delete the sweeper.
2. **Target 3** — cheap and independent; can run in parallel with 1.
3. **Target 2** — after 1, because the helm board reads workflow state and
   the husk population is currently distorting what it shows.
4. **Target 4** — fold into whichever of the above touches a scrubber first.

**Do not:** merge the `reconcile-*` family, introduce a sourced shell
library, delete comments to reduce line counts, or add a gate/budget/review
step. Three of those trade clarity for a number, and the fourth is the
process this document was asked not to create.

**Re-measure first.** Every figure here is from `da63241` on 2026-08-23. At
~3,300 shell lines a day, a week makes this document a historical record
rather than a plan — which is what `specs/` is for.
