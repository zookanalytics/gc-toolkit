---
name: Phase model for review checks — spike report
description: Design proposal for modeling each review check's phase as a first-class fact, so the pre-open / draft-to-ready / merge transitions read a check's phase from the check index instead of the seven hardcoded none/off/approval drops. Decision-grade; to be ratified in an operator conversation before any implementation.
---

# Phase model for review checks — spike report

This spike answers one question: what would let a stage transition (create the
PR, mark it ready for review, merge it) decide which checks it must wait on by
reading a declared fact about each check, rather than by re-deriving the same
hardcoded rule in seven places? The answer is a **phase** on each check — the
stage-transition by which the check must be green. This report proposes the
phase model, resolves the four sub-questions the operator named, and recommends
a concrete schema and migration. It does not implement any of it.

## Recommendation

1. **Give each check a `phase`** in the check index (`review-checks.toml`): the
   transition by which it must be green. The four phases are ordered
   `pre-open < open-as-draft < ready-for-review < merge`. This revisits the
   tk-3h9mzz "no judgment in the index" choice, and the revisit is narrow and
   defensible: a check's phase is a mechanical fact about what the check needs
   as input, not the per-diff *applies-when* judgment that choice kept in prose.
2. **Bound the phase with an intrinsic floor.** A check declares the earliest
   phase it may occupy, grounded in its inputs (correctness needs only the diff,
   so its floor is `pre-open`; demo needs the deployed preview, so its floor is
   `open-as-draft`). Triage may move a check's effective phase later than its
   declared default but never earlier than its floor. This is what makes "triage
   cannot put CI pre-open" a checked invariant rather than a convention.
3. **Take `approval` out of `check_set` and make it a merge rule.** It is
   already enforced separately in `merge.sh` from GitHub's own review state and
   already takes no lane marker, so this is a relocation, not new behavior. It
   removes `approval` from every drop list at a stroke.
4. **Centralize the sentinel and phase logic in the one parser.** Give
   `review-checks.sh` a resolver that takes an anchor's `check_set` and a
   target transition and returns the checks that gate it. The seven copies of the
   `none|off|approval` drop collapse into that one resolver, which is the only
   thing that knows `none`/`off` are sentinels.
5. **Introduce the draft-first flow only where an `open-as-draft` check
   exists.** A repo whose checks are all `pre-open` (gc-toolkit today) keeps
   opening its PR ready immediately; the draft state appears only when a demo or
   CI check needs the open PR to run. This preserves current behavior for every
   repo that has no such check.

The rest of this document is the evidence and the mechanics behind these five
decisions.

## The problem

The origin is operator intake tk-7h5l3m. Its core sentence: *"Checks should be
flexible with one place saying what checks are landed, some worker knowing what
checks they handle, and stage transitions being able to read on the bead
whether all their checks are completed."* The foundation that landed under
tk-3h9mzz (PR #876) built the first two: the check index is the one place that
declares the checks, and each reviewer knows its check by `check_name`. The
third — a stage transition reading whether *its* checks are done — is only half
built. A transition today reads whether *every* check in `check_set` is green,
with three names dropped by a rule each script re-implements. It has no notion
that different checks belong to different transitions.

That missing notion blocks a concrete case the operator named. A demo check
records the operator-watched surface doing the thing, and it can only run
against a deployed preview, which most providers build only for an open pull
request. Put `demo` in `check_set` today and `pr-open.sh` refuses to open the
PR until `demo` reads green, but `demo` cannot read green until the PR is open.
The current model cannot express a check that must run *after* the PR exists but
*before* the change is surfaced for human review. The phase model exists to
express exactly that.

## Current machinery (what the phase model replaces)

### The check index carries no phase

`review-checks.toml` (repo root) declares each check with exactly two fields,
`method` and `purpose` (`review-checks.toml:11-21`). `assets/scripts/review-checks.sh`
is the sole parser; its awk reads only those two keys and emits one TSV row per
check, `name<TAB>method<TAB>purpose` (`review-checks.sh:42-57`). Any other key
in a `[checks.*]` table is silently ignored, so a `phase` field is greenfield:
no schema, loader, or reader consumes one today. The absence is deliberate —
tk-3h9mzz kept *when a check applies* in the check's method prose, which triage
reads, so the index would "stay a small data file rather than a document a
parser must interpret" (`specs/tk-3h9mzz/review-gates-foundation.md:61-64`).

### Both transitions read one list, minus three names

An anchor declares its checks in `check_set`, a comma list. Three names are not
review checks, and every reader knows them by name: `none` and `off` are the
gateless sentinel, and `approval` is met by an external GitHub review
(`docs/state-machine.md:161-167`). Pre-open and merge read the same list and drop
the same three: `pr-open.sh` publishes once every surviving check reads green,
and `merge.sh` merges under the same condition (`docs/state-machine.md:180-188`).

The drop is one rule — `none|off|approval` — copied seven times across the six
scripts in three syntactic shapes:

| Script | Site | Shape | Transition it serves |
|---|---|---|---|
| `pr-open.sh` | `:87-91` (`gates_of`) | `grep -Eiv '^(none\|off\|approval)$'` | create the PR |
| `merge.sh` | `:208-212` (`lanes_of`) | `grep -Eiv '^(none\|off\|approval)$'` | merge |
| `review-outcome.sh` | `:245-251` (inline) | `grep -Eiv '^(none\|off\|approval)$'` | supersede lane backing on a failed feedback batch |
| `gate-ensure.sh` | `:671-676` (inline) | `case … none\|off\|approval) continue` | dispatch reviews (both transitions) |
| `liveness-sweep.sh` | `:317-323` (`pre_open_all_green`) | jq `map(select(≠ none, off, approval))` | census: classify a pre-open anchor as gated |
| `pr-facts.sh` | `:670` (`unengaged_holds`) | `case … none\|off\|approval) continue` | facts: every gate green (a green gate hides findings) |
| `pr-facts.sh` | `:1954` (dismiss arm) | `case … none\|off\|approval) continue` | facts: dismiss our own stale CHANGES_REQUESTED when green |

`gate-ensure.sh` also collapses `none`/`off` to the sentinel in two more places
(`:92-97`, `:622`). The stage difference between pre-open and merge is not in the
drop list — it is a second hardcoded fact: a pre-open lane read passes
`--no-remote` so no GitHub approval can back it before the PR exists
(`pr-open.sh:531-537`, `gate-ensure.sh:702-706`), and the two literal stages
`pre_open_gate` and `pull_request` are enumerated together at
`gate-ensure.sh:473`.

Any field that says "this check gates this transition" has to replace all seven
drop sites and the `--no-remote` split. That is the surface area of the change.

### `approval` is already a merge rule wearing a check's clothes

`approval` is not an index entry and not a lane derived through `lane-state.sh`.
It is a `check_set` token that arms a requirement `merge.sh` enforces on its own
(`merge.sh:582-632`): an external `APPROVED` review from another account at the
live head, with a standing `CHANGES_REQUESTED` as a hard veto. The same
requirement is armed by two other conditions that are already not check_set
tokens — a `signoff_dismissed` marker and the city's own dismissed review — so
the enforcement is already decoupled from the token. `approval` takes no
`check.approval` marker; the lifecycle registry records that rule
(`lifecycle.toml:193-195`, `approval_member = "approval"`). The default
`check_set` is `correctness,triage` (`lifecycle.toml:185`), so approval is
opt-in, not universal.

A separate, related fact: a GitHub `APPROVED` review also backs *any* lane that
has no local review bead (`lane-state.sh:22-27, 65-82, 127-129`) — "an approval
names no gate, so it backs every lane." This is why the pre-open read is
`--no-remote`. This fallback is about lane derivation and is out of scope for the
phase model; the merge rule (`merge.sh:582-632`) is the part that relocates.

### Triage widens `check_set`, monotonically, over the index

Triage classifies a diff and records which specialist checks it warrants by one
`signoff.sh --add-gates` call. `signoff.sh` is the sole writer; only a triage
approve may widen (`signoff.sh:200-203`), the index is closed so a check must be
declared to be added (`signoff.sh:613-657`), and the write is a set union read
back so a widen that did not persist leaves the check owed (`signoff.sh:661-670`).
The phase model plugs into this exact seam: placing a check's phase is the same
shape of operation as adding a check, validated the same way against the index.

## The phase model

### Four phases

A **phase** is the stage transition by which a check must read green. The four
are ordered:

1. **pre-open** — the check needs only the diff. It runs before the PR exists.
   Correctness and triage are here: a city-controlled reviewer reads the diff
   and rules.
2. **open-as-draft** — the check needs the open PR or a deployed preview, and
   must finish before the change is surfaced for human review. Demo is here; a
   CI check that a provider triggers only on an open PR is here.
3. **ready-for-review** — the state in which a human reviews a change whose
   city checks are all green. No check is authored here today; it is the ceiling
   for automated checks and the state dialogue happens in. Reserved.
4. **merge** — the final transition. The human-approval merge rule is here, and
   the merge re-verifies that every check from every earlier phase is still green.

A check declares its phase (values `pre-open` or `open-as-draft` for real checks
today; `ready-for-review` reserved). The approval merge rule sits at `merge` and
is not a check.

### The three gated transitions

The four phases mark three transitions a script must gate. Each gate is
idempotent: it reads markers, never a "did the previous gate run" flag, so a
crash between gates costs nothing.

| Transition | Gate predicate | Owner |
|---|---|---|
| **create PR (draft)** | every `pre-open` check in `check_set` reads green | `pr-open.sh` |
| **draft → ready** | every `pre-open` and `open-as-draft` check reads green, and GitHub CI is green | a `pr-open.sh` / `pr-facts.sh` arm |
| **ready → merged** | every check in `check_set` (all phases) reads green, the approval merge rule is satisfied, no holds, GitHub CLEAN, base equals target | `merge.sh` |

"Opens when ready for review" is the **draft → ready** flip, not the mechanical
`gh pr create`. The PR is *created* (as a draft) at the first transition so a
preview can deploy; it is *surfaced* to the human at the second, once its
pre-ready checks are green. A ready PR has, by construction, no city check still
running — which is the operator's "do not surface ready PRs that still have city
checks running," made structural.

### The empty-phase collapse preserves today's behavior

When an anchor's `check_set` has no `open-as-draft` check — every check
gc-toolkit declares today is `pre-open` — the PR is never opened as a draft, so
there is no draft → ready flip to gate: the create gate opens it ready
immediately, and GitHub CI stays a merge-time concern (the merge gate's CLEAN
requirement) exactly as today. The draft state appears only for a repo that has
an `open-as-draft` check to wait on. No repo without a demo or preview-CI check
changes behavior; `pr-open.sh` keeps opening non-draft (`pr-open.sh:13, 578`)
exactly as it does now.

### Forward gates, with the merge gate as the backstop

Phases gate forward transitions only. If a check un-greens after its phase — a
re-review supersedes a correctness approve after the PR is already ready — the
PR does not fall back to draft. The merge gate's all-phases-green requirement is
the backstop that catches it: the change simply cannot merge until the check is
green again. Reversing a ready PR to draft on an un-green is deliberately not
proposed; it is churn the merge gate already prevents the harm of.

## Where phase is declared: the index, not prose

This is the decision that touches the tk-3h9mzz choice, so it earns its own
argument.

That choice rejected an **applies-when** column: whether a given diff warrants a
given check is a per-diff judgment, and putting it in the index would make the
index a document a parser must interpret. Phase is a different axis. *Applies-when*
asks whether the check runs at all for this diff; **phase** asks, given that it
runs, which transition it gates. Applies-when varies with the diff and stays a
triage judgment. Phase is fixed by what the check consumes: correctness reads a
diff whether the diff is one line or ten thousand, and demo needs a preview
whatever the change. Phase is a mechanical fact about the check, the same kind of
fact as its `method` pointer, so it belongs in the index the same way `method`
does. Declaring phase does not reopen the applies-when judgment the index was
right to exclude.

The alternative — inferring phase from the method's prose, the way applies-when
is read — fails the origin requirement. The origin asks for *one place* a
transition can read. Prose a human interprets is not a place a shell transition
reads; the whole point is to stop each transition re-deriving the rule. Phase
must be a field a parser emits.

Concretely, the index gains one or two keys per check:

```toml
[checks.correctness]
method = "formulas/mol-review.toml"
purpose = "Is the change correct and safe as merged?"
phase = "pre-open"

[checks.demo]
method = "skills/gc-demo-script/SKILL.md + skills/demo-capture/SKILL.md"
purpose = "Was the operator-watched surface recorded doing the thing?"
phase = "open-as-draft"
```

`phase` is the check's effective default. An optional `phase_floor` states the
intrinsic earliest phase; absent, it defaults to `phase`, so a check with a
single legal phase writes only `phase`. The awk parser gains these columns and
the resolver below reads them.

## Triage within intrinsic bounds

The operator's constraint: triage may decide a check's phase, but cannot put
human approval or CI pre-open. Define the bounds.

The bound is a **floor**: the earliest phase a check may occupy, set by what the
check needs as input.

| Check / rule | Intrinsic floor | Why |
|---|---|---|
| correctness, triage | `pre-open` | needs only the diff |
| demo | `open-as-draft` | needs the deployed preview, which needs the open PR |
| a preview-triggered CI check | `open-as-draft` | the provider builds only for an open PR |
| human approval (merge rule) | `merge` | needs a human to have reviewed the ready PR |

Triage sets a check's *effective* phase within `[floor, merge]`: never earlier
than the floor, never later than merge (everything must be green to merge). For
a check whose declared `phase` equals its floor and which needs no latitude —
every check in the index today — triage has nothing to decide and the common case
is untouched. Latitude matters for a future specialist check that *could* run at
more than one phase: an arch check reads only the diff, so its floor is
`pre-open`, but the operator might want it to run at `ready-for-review` for a
large change and `pre-open` for a small one. There, triage picks, bounded below
by the floor.

Two of the operator's constraints fall out of this without a special case:

- **Triage cannot put CI pre-open**, because a preview-triggered CI check
  declares `phase_floor = "open-as-draft"` and the resolver refuses a phase
  below the floor — exactly as `signoff.sh` refuses a check the index does not
  declare (`signoff.sh:640-641`).
- **Triage cannot put human approval anywhere**, because approval is not a
  check. It is a merge rule (next section), so it is not in the table triage can
  widen or re-phase at all.

The mechanism mirrors `--add-gates`: a `signoff.sh --set-phase <check>=<phase>`
capability, writable only by a triage approve, validated against the index floor
by the one parser, recorded as a `triage-phase:` note beside the `triage-add:`
notes, and read back so an unpersisted write leaves the default in force. Whether
to build `--set-phase` at all in the first implementation is an open question:
if no first-wave specialist check needs latitude, the floor can equal the
declared phase everywhere and `--set-phase` waits for the check that needs it.

## Approval as a merge rule

This is feasible end to end, and most of it is already true.

`merge.sh` already enforces approval without reading a `check.approval` marker:
it reads GitHub's review state and requires an external `APPROVED` at the live
head (`merge.sh:573-632`). The token's only jobs are to *arm* that enforcement
and to be *dropped* from every lane-derivation list so it is not mistaken for a
lane. Both jobs move cleanly off the token:

1. **Arming** moves to a merge rule. Add a `[merge]` section to
   `lifecycle.toml`, or a per-anchor attribute the refinery stamps the way it
   stamps `check_set`, that says this anchor requires human approval. `merge.sh`
   reads that instead of scanning `check_set` for `approval`. The two other
   arming conditions (`signoff_dismissed`, the self-dismissed review) are already
   merge rules in everything but name and stay as they are. Because the default
   `check_set` never included `approval` (`lifecycle.toml:185`), approval stays
   opt-in; the rule is per-anchor, carrying the same opt-in the token carried.
2. **Dropping** disappears. With `approval` no longer a `check_set` member,
   nothing has to drop it. Every drop list shrinks to `none|off`, and those are
   the sentinel the resolver owns — so the drop lists disappear entirely from the
   six scripts.

End to end, the surfaces are: the index and `check_set` stop mentioning
`approval`; `lifecycle.toml` declares the merge rule where `approval_member`
sits today; `merge.sh`'s approval block reads the rule rather than the token; and
`pr-open.sh`, `review-outcome.sh`, `gate-ensure.sh`, `liveness-sweep.sh`, and
`pr-facts.sh` stop special-casing the name because it is gone from the namespace
they read. The
migration also needs a one-shot rewrite of live anchors carrying `approval` in
`check_set` into the new rule, on the pattern of the `migrate-*` scripts
tk-3h9mzz already ships.

"Approval as a check sounds stupid" is right for a concrete reason: a check
produces a review bead and a lane marker, and approval produces neither. It has
always been a merge rule; the token was a way to carry it in the one field the
refinery already stamped. The phase model gives the refinery a cleaner place to
stamp it.

## The draft → ready flow for demos

The sequence a demo change moves through:

1. Pre-open checks (correctness, triage) go green on the branch, before any PR.
2. `pr-open.sh` creates the PR **as a draft**. A draft PR is an open PR, so the
   preview provider deploys a preview for it.
3. The preview URL reaches the demo check; the demo records the operator-watched
   surface against it and `signoff.sh` greens the demo lane.
4. Once every `open-as-draft` check is green and GitHub CI is green, the
   **draft → ready** arm flips the PR out of draft. It is now surfaced for human
   review with all city checks green.
5. Human review, then the merge gate: approval merge rule plus all-phases-green.

The draft state is the machinery's name for "the PR exists so previews and CI can
run, but it is not yet the human's to review." That is precisely the
`open-as-draft` phase.

### The Vercel / preview-needs-a-PR question

The sub-question: some providers cannot build a preview without an open PR. The
draft-first flow answers it directly — a draft PR *is* an open PR, and Vercel and
the common CI providers deploy previews and run checks on draft PRs. Opening as a
draft is what buys the preview the demo needs, so the provider constraint is
satisfied by construction for the mainstream case.

The residual case is a provider that refuses to build even for a draft PR (it
requires a non-draft PR to deploy). Options, in preference order:

- **Prefer providers that build on draft PRs.** This is the default posture and
  covers Vercel, Netlify, and GitHub Actions preview jobs.
- **For a provider that truly needs non-draft**, open the PR non-draft but hold
  the *surfacing* signal separately: the PR is non-draft so the preview builds,
  but the human-review-ready marker (the `status:` label the pack already writes,
  `pr-status-label.sh`) is not set to `needs-review` until the `open-as-draft`
  checks pass. This decouples "the PR is non-draft so CI runs" from "a human
  should look," at the cost of a second readiness signal beside the draft flag.
  It is more moving parts and is proposed only as the fallback.

Recommendation: design for draft-first, and treat the non-draft-preview provider
as a documented fallback rather than a shape the core model must carry. The
draft flag stays the primary readiness boundary.

## Dialogue stays a visit

Human dialogue on a PR is handled by a visit, independent of PR state, and is
not modeled as a phase in this proposal. The review-cycle machinery already
enters operator feedback into the finding and validation graph
(`docs/state-machine.md:228-247`) without reference to a phase, and that path is
untouched. Modeling dialogue as a phase is a larger change with no demand behind
it yet; this spike deliberately leaves it out and flags it as a later question if
one arises.

## Retiring the seven hardcoded drops

The centralization that makes the drops go away: one resolver in the one parser.

`review-checks.sh` gains a mode that answers the question every stage transition
asks — given this anchor's `check_set` and this transition, which checks gate it?

```
review-checks.sh --resolve --check-set "<check_set>" --through <phase> --file <index>
```

It tokenizes `check_set`, drops `none`/`off` (the only place that knows they are
sentinels), looks up each remaining check's effective phase in the index, and
emits the checks whose phase is at or before `<phase>`. Each transition calls it:

- **`pr-open.sh`** (create gate) calls `--through pre-open`, reads each returned
  lane `--no-remote` (no PR yet), and creates the draft when all are green. Its
  `gates_of` function is deleted.
- **A `pr-open.sh` / `pr-facts.sh` arm** (ready gate) calls
  `--through open-as-draft`, reads each lane with remote allowed, checks GitHub
  CI, and flips draft to ready when all are green.
- **`merge.sh`** (merge gate) calls `--through merge`, reads each lane, applies
  the approval merge rule and the other merge conditions. Its `lanes_of` function
  is deleted; its approval block reads the merge rule.
- **`gate-ensure.sh`** dispatches a review for each returned lane that owes one;
  its inline `none|off|approval` `case` and its `--no-remote` split both read the
  resolver and the transition instead of re-deriving.
- **`review-outcome.sh`** supersedes the backing of each returned lane; its
  inline drop is deleted.
- **`pr-facts.sh`** carries two more copies today — the `unengaged_holds`
  finding-hold (`:670`) and the self-dismissal arm (`:1954`), each computing
  all-gates-green for merge readiness. Both call `--through merge`, and their
  inline `none|off|approval` `case`s are deleted.
- **`liveness-sweep.sh`** classifies a pre-open anchor by asking the resolver for
  its `pre-open` gating set. This also fixes the outlier noted below.

`liveness-sweep.sh` is the one reader that today evaluates green by reading the
stored `check.<g>=green` marker directly (`liveness-sweep.sh:317-323`) rather than
deriving through `lane-state.sh` like the other four. Routing it through the
resolver is the moment to unify it, so all readers compute the gating set the
same way even if the census keeps its own fast marker read for the green check
itself.

After this, the `none|off|approval` rule exists once (the resolver's `none|off`
drop plus approval's departure from the namespace), and each transition's
phase-specific set is a call, not a copied loop. That is the origin requirement
met: one place says what checks exist and their phases, each reviewer knows its
check, and a transition reads whether its checks are done by asking the one
resolver.

## What this spike does not decide

- **Implementation.** Everything here is a proposal to ratify in conversation
  before any code moves. No production behavior changes from this spike beyond
  this document.
- **The per-rig rollout** of the index and the phase declarations, and the
  rig-agnostic naming write-up — tracked separately under tk-cwkmt2.
- **The helm board's pre-open-stall deriver** (tk-263hr9), which recognizes the
  pre-open gate by its own hardcoded match. It reads the same shape this proposal
  changes and should adopt the resolver, but it is an owned Go component tracked
  on its own bead.
- **Reversing ready to draft** on a check that un-greens after its phase. Left
  out on purpose; the merge gate is the backstop.
- **`--set-phase` for triage.** Proposed as the mechanism for phase latitude, but
  whether the first implementation builds it depends on whether any first-wave
  specialist check needs a floor below its declared phase.

## Open questions for the ratification conversation

1. **Two keys or one?** Ship `phase` alone now (fixed phase per check, no triage
   latitude), and add `phase_floor` plus `--set-phase` only when a specialist
   check needs to run at more than one phase? The current three checks need only
   `phase`.
2. **Where does the approval merge rule live** — a new `lifecycle.toml [merge]`
   section, or a per-anchor attribute the refinery stamps, or both (a rig default
   the refinery reads onto each anchor)? The per-anchor form preserves today's
   opt-in most directly.
3. **Is CI a `check_set` member or the existing GitHub-CLEAN signal?** This
   proposal treats CI as GitHub-native and consumes it at the ready gate. If the
   operator wants CI modeled as a first-class city check with an index row, that
   is a larger change to scope.
4. **The non-draft-preview provider.** Is the documented fallback enough, or does
   a provider in the city's actual use need the second readiness signal built now?
