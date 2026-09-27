---
name: Review-gates foundation — the check index, composed methods, correctness at birth
description: The settled model for the re-landed review-gates machinery — the mechanical check index that replaces the charter/menu, the compose-don't-override method model, the check/review/reviewer vocabulary with correctness named at birth, the forced correctness,triage baseline, and the reference-docs convention the specialist checks will use.
---

# Review-gates foundation

This foundation re-lands the review-gates machinery on `main`, corrected. It
adds the pieces main does not yet have — the triage check, a widenable
`check_set`, a declared index of available checks, and a composition model for
check methods — and it names the standing correctness review `correctness`
from the start. It builds on main's derived lane-state model (a lane's green is
computed from the review-bead graph, never from a stored per-head marker) and
main's dispatch-topology axis (single-agent `mol-review` or the two-provider
`mol-review-quorum-signoff`), and regresses neither.

The concrete deliverable is the machinery below plus the tests that hold it.
Three specialist checks are armed behind this bead and are out of scope here:
the arch check (tk-e4zrc5), the PM check (tk-f4i3rf), and the per-rig index
rollout with the central naming write-up (tk-cwkmt2). This foundation leaves
the seams those need open; it does not build them.

## Vocabulary

A **check** is one requirement in an anchor's `check_set` — a concern that must
be reviewed before merge. A **review** is the work bead that satisfies one
check for one anchor. A **reviewer** is the session that holds a review bead.

"Gate" is a verb: checks gate a merge, and GitHub branch protection is a gate.
It is not a noun. The thing in `check_set` is a check, not a gate; the bead is
a review, not a gate.

The standing correctness review is the check named `correctness`. `codex` named
a tool, not the concern the check verifies, so it does not name the check. The
tool keeps its name where it is a tool: the `polecat-codex` pool, the
`converse-codex` agent, and the `codex` provider id in the quorum are unchanged.

The declared set of available checks is the **check index**. "Charter",
"menu", and "policy" are not used for it.

## The check index

`review-checks.toml`, at the repo root, declares the checks a repo makes
available to review. It holds mechanical facts only: for each check, the check
name, a pointer to the method that governs it, and one line of purpose.

```toml
[checks.correctness]
method = "formulas/mol-review.toml"
purpose = "Is the change correct and safe as merged?"

[checks.triage]
method = "skills/review-triage/SKILL.md"
purpose = "Which specialist checks does this diff warrant?"

[checks.demo]
method = "skills/gc-demo-script/SKILL.md + skills/demo-capture/SKILL.md"
purpose = "Was the operator-watched surface recorded doing the thing?"
```

It carries no judgment. There is no applies-when column and no mandatory-paths
column: when a check applies is a judgment the check's method states in prose,
which triage reads and evaluates. Keeping judgment out of the index is what
lets it stay a small data file rather than a document a parser must interpret.

The index is read from the commit under review, never from the working tree —
`git show <reviewed_oid>:review-checks.toml` — so a branch is judged against the
index it carries. A repo with no index offers only the forced baseline (below);
its absence is a finding the reviewer files, not an error that stops the review.

`assets/scripts/review-checks.sh` is the one parser of this grammar. It reads
the TOML index and emits one TSV row per check — `name<TAB>method<TAB>purpose`
— with `--check <name>` narrowing to one row. Every reader of the index goes
through it, so the triage method, `signoff.sh`, and the index-agreement test
read the same rows. Its exit codes are 0 (rows emitted), 1 (no readable index,
or `--check` not declared), 2 (usage).

`signoff.sh --add-gates` validates each added check name against the index by
membership: it calls `review-checks.sh --check <name>` and reads the exit code,
never the method pointer. A name the index does not declare is refused; a repo
with no index at the reviewed commit accepts the widening unvalidated, because
widening is always safe. Validating by membership rather than by resolving the
method keeps the one parser the only thing that understands the format.

## Composed methods

A check's method has two layers. The **generic method** is gc-toolkit pack
content: the per-check arm in `assets/scripts/review-dispatch-body.sh` and, for
correctness, the steps of `formulas/mol-review.toml`. Every rig that installs
the pack gets it.

A rig **may** add a local **extension** — `docs/review-<check>.md` in its own
repo — that the dispatch note appends to the generic method text. The extension
adds; it never replaces. `review-dispatch-body.sh` reads it from the commit
under review (`git show <reviewed_oid>:docs/review-<check>.md`) and degrades
gracefully when it is absent: no extension is the common case, and its absence
changes nothing about the generic method.

Reading the extension from the reviewed commit, not from disk, is the same
discipline the index follows: the method a reviewer holds a diff against is the
method that diff's own commit declared. A rig tightening a check's method
tightens it for the commits made after the change, not retroactively.

This composition is why the method lives in a plain file rather than a skill. A
skill loads from the installed catalog, not from the diff's commit, so it cannot
express a per-rig method pinned to the reviewed commit. The pack's generic arms
carry the baseline; the reviewed repo's own files extend it.

## Two dispatch axes

A review dispatch answers two orthogonal questions, and both axes survive.

The **check-name axis** is which concern is verified and which method governs
it. `review-dispatch-body.sh --check-name <check>` selects the generic method
section and names the check the review satisfies; `gate-ensure.sh` stamps
`check_name` on the review bead so lane-state derivation and the marker both
know which check the review belongs to.

The **formula axis** is the dispatch topology. `gate-ensure.sh --review-formula`
(default `mol-review`) and its repeatable `--sling-var` choose between the
single-agent `mol-review` and the two-provider `mol-review-quorum-signoff`,
which fans out to two reviewer lanes on different providers and synthesizes one
verdict. The quorum is opt-in through `REFINERY_RECONCILE_REVIEW_FORMULA` and
inert unless selected.

The axes compose because a check produces exactly one review bead whatever the
topology: under the quorum the synthesizer makes the single `signoff.sh` call
and the lanes never do. A dispatch carries both a `check_name` (which method)
and a formula (which topology); neither constrains the other.

## The forced baseline

The default `check_set` is `correctness,triage`. Correctness is the standing
review of whether the change is right; triage decides what else the change
needs. Both run on every anchor that does not opt out.

Triage only ever adds. It cannot remove a check, and no dispatcher, formula, or
other reviewer may pre-set or shrink `check_set` — `signoff.sh` is the sole
writer and only a triage verdict reaches the widening path. The single opt-out
is `check_set=none`, which is human-only: an operator sets it to review a change
by hand, and triage refuses to widen it.

## Triage

Triage classifies; it does not judge. It reads the index at the reviewed
commit, skims the diff, and decides which specialist checks the change warrants
from the checks the index declares. Adding nothing is the expected common case.

It records the decision on one `signoff.sh` call — `--verdict approve
--add-gates <check>[,<check>]` — which both greens the triage check and widens
the anchor's `check_set`. The write is a set union with read-back: `signoff.sh`
reads `check_set` back after the write and refuses to green the review unless
every added check is present, so a widening that did not persist leaves the
check still owed. Each added check is recorded on the anchor as a `triage-add:`
note, so the add-rate the feedback loop watches stays countable. An index
missing at the reviewed commit is triage's first finding, filed as an
observation; triage then widens nothing and correctness still runs.

## Integration with the derived lane-state model

Main computes a lane's green state from the review-bead graph
(`assets/scripts/lane-state.sh`): a lane is green when a non-superseded closed
approve review backs it — or an operator's GitHub approval does — and nothing is
in flight on it. A new commit creates and closes no bead the derivation reads,
so a push does not un-green a lane; only the validator superseding an approve
bead, or a human feedback batch opening a validation pass, moves a lane
backward. `merge.sh` and `pr-open.sh` derive every check in `check_set` through
this one helper and hold the merge until each is green.

This foundation adds checks to that model; it does not change how green is
derived. The `check.<name>` metadata marker stays what main made it — a single
lane-state word, written only as `green` by `signoff.sh` and otherwise derived —
and is not rebound to a commit. Renaming the standing check from `codex` to
`correctness` renames the lane and the marker key together, and the default
lane name that an absent `check_name` resolves to changes with it, so the
derivation, the writer, the dispatcher, and the validator agree on the name.
The one-shot `migrate-codex-to-correctness.sh` rewrites the legacy name on every
live surface that carries it — the `check_set` token, the `check.codex` marker, a
review bead's `check_name`, and a finding bead's `finding.lane` — so no open
anchor loses a green it earned, and no open finding goes invisible to the
correctness validator that selects the findings to rule by their lane.

## What is not carried

The waiver feature is not built: no `--waive-gates`, no `--justification`, no
waivable column. It has no cited use case, and `check_set=none` is the only
narrowing.

The markdown charter and its parser are not carried. `docs/review-charter.md`
and `assets/scripts/review-charter.sh` do not exist here; the index is TOML and
`review-checks.sh` reads it.

The round cap and the dispatch ceiling stay retired. main already judges
convergence through the validator rather than counting rounds; this foundation
adds no `signoff_round`, `signoff_cap`, `dispatch_count`, or
`GC_MAX_REVIEW_DISPATCHES`. The lifecycle records of those retired keys and the
defensive cleanup of anchors parked under the old cap are left as they are.

The `exception@head` lane park is not reintroduced. A finding holds its lane
through the finding graph, not through a sixth lane state.

## Seams left open

Deliberately deferred, each tracked by a bead:

- **The correctness tier** (deferred, tk-3voqke; design in `specs/tk-9tqphn/`).
  Check names stay a flat comma-list of clean names — no dotted
  `correctness.advanced`, which would split into two lanes and review
  correctness twice. Method selection is keyed on the flat check name, and the
  reviewer pool and model are resolved at dispatch, so a future
  `correctness_tier` anchor attribute can select the pool at the one dispatch
  point without touching the check grammar.
- **The arch check** (tk-e4zrc5) and **the PM check** (tk-f4i3rf). A specialist
  check is an index row, a generic method arm, and an optional rig extension.
  The index accepts new rows and `review-dispatch-body.sh` accepts new
  `--check-name` arms without any change to the dispatch or the merge predicate,
  so each specialist lands as content within this model.
- **The helm board's pre-open-stall deriver** (tk-263hr9).
  `services/helm/internal/board/derive.go` recognizes the standing pre-open gate
  by an exact `check_set == "codex"` match and the `check.codex` marker. Under the
  renamed, comma-list `correctness,triage` baseline it matches neither, so the
  board stops surfacing a stalled pre-open correctness gate until that deriver
  moves to comma-list membership on `correctness`. Only the board's stall
  indicator is affected; the merge machinery derives and holds each check
  independently. It is a Go change in the actively-owned board component, kept out
  of this shell/TOML foundation on purpose.

## The reference-docs convention

A specialist check reads reference documentation before it judges — the arch
check reads the architecture docs, the PM check reads what the operator watches.
The convention this foundation sets is light: a check's rig extension is
`docs/review-<check>.md`, read from the reviewed commit, and any longer
reference the method cites is an ordinary repo doc the extension points to. The
central write-up of this convention and the per-rig indexes are tk-cwkmt2's; a
rig's own index and extensions live in that rig's repo under these names.

## Naming convention (proposed)

Review configuration a reviewer reads from the commit under review follows one
rig-agnostic, function-named convention:

- the check index is `review-checks.toml` at the repo root;
- a check's method extension is `docs/review-<check>.md`.

Both are named for what they do and are read pinned to the reviewed commit. The
names avoid "charter", "menu", and "policy", which named the retired markdown
design. tk-cwkmt2 carries this convention into the central docs and rolls the
index out to the other rigs.
