---
name: review-triage
description: Use when you hold a review bead whose check is triage, or when asked which review checks a diff warrants.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Review triage

You are classifying, not judging. Whether the change is correct is the
`correctness` check's question and it is already dispatched. Yours is narrower:
**which specialist checks does this diff warrant?** The usual honest answer is
none.

## What it reads

Three inputs, in this order.

1. **The check index** — the pack's checks, with the rows of the
   `review-checks.toml` the commit under review carries laid over them. It
   declares the checks you may add. Read it first; it is the one place the
   available checks are declared.
2. **The anchor** — `<anchor_bead>`, which states what the change was for, and
   the rig's guidance for triage, the reviewed commit's `docs/review-triage.md`,
   which the review formula printed when the commit carries one. A rig steers
   triage there in words, such as never adding a check, or adding one only for
   one kind of change: advice you weigh beside your own reading of the diff.
3. **The diff, at the reviewed commit** — in `<worktree>`,
   `git diff --stat origin/<review_base>...HEAD` first, then a skim of the
   files the stat names. A skim is the method here; reading every hunk is the
   specialist reviewer's job, not yours.

### The index

Read the index through the pack's resolver rather than eyeballing a file. It
has two layers. The pack's own index declares every check the pack ships a
skill for, so every rig has them. The reviewed repo's `review-checks.toml` at
the commit under review, when it keeps one, adds checks of the rig's own and
can change a pack check's purpose or phase for that rig. The resolver is the
pack's own copy, which `gc <binding> scripts-dir` finds from any rig: it prints
the directory holding the pack's scripts. `<binding>` is the name the city
imports the pack under, which gc puts in front of this skill's name:
`gc-toolkit` in `gc-toolkit.review-triage`. `gc skill list` prints it in this
skill's FROM column. The rig's rows come out of `<reviewed_oid>`, not off disk —
the tree you stand in is your own worktree, not the commit you are classifying,
and a branch may change the index it is judged against:

```bash
# >>> triage-index-read
"$(gc <binding> scripts-dir)/review-checks.sh" --show --at "<reviewed_oid>"
# <<< triage-index-read
```

Each row gives you the check, one line of purpose, and its phase — the stage
transition by which it must read green. When a check applies is a judgment its
method states, so read the method: the skill `<binding>.review-<check>` in your
catalog. A check of the rig's own has no skill, and its purpose is the whole of
what it judges. The phase is fixed per check and not triage's to choose, and
there is no applies-when column in the index.

A commit that carries no index of its own still has the pack's checks, so
every review has a menu. A non-zero exit is an index nobody read: a commit the
checkout cannot read, a reviewed commit the block was not given, or a scripts
dir gc cannot print. Stop and say so rather than classify with no menu. A row
the resolver refuses, a phase outside the ordered set, is left off the menu and
named on stderr. That row is the index gap.

### The index gap

A rig row the resolver refuses is your first finding. File it as an
observation and classify over the rows the menu shows. Filing is recording,
not proposing: the distiller judges it and a reviewed PR writes the index.

```bash
# >>> triage-index-gap
OBS_META=$(jq -nc --arg scope "repo:${GC_RIG:-unknown}" --arg prov "bead:<anchor_bead>:turn:$(date -u +%Y-%m-%d)" \
  '{task_kind: "observation", "obs.category": "review-index-gap", "obs.scope": $scope,
    "obs.source": "self", "obs.directive": "standing", "obs.provenance": $prov,
    "gc.outcome": "recorded", "gc.work_outcome": "no-op"}')
OBS_JSON=$(gc bd create "obs: check index row refused (bead:<anchor_bead>)" \
  -t task -l learning -l observation --metadata "$OBS_META" --status=closed -d "## Statement
<the row the resolver refused, and why>

## Quote
Triage on <anchor_bead> at <reviewed_oid>.

## Proposed norm
<draft — explicitly non-binding>" --json)
OBS=$(printf '%s' "$OBS_JSON" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
[ -n "$OBS" ] || { CREATE_ERR=$(printf '%s' "$OBS_JSON" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null); echo "observation not filed${CREATE_ERR:+: $CREATE_ERR}" >&2; exit 1; }
# <<< triage-index-gap
```

### A bring-current round that conflicted

Bringing the branch current means merging its base in. When that took
resolution by hand, the worker wrote one audit entry per conflicted file and
per edit beyond the merge, `bring-current-guard.sh` stored the entries on the
anchor beside its own diff evidence, and it reopened this lane. So the anchor's
`bring_current_record` holds a conflicted round with no `triage` ruling, the
reason the review formula prints says so, and your verdict also rules on that
round. `signoff.sh` refuses the verdict without the ruling.

Read the round first:

```bash
# >>> triage-round-read
"$(gc <binding> scripts-dir)/bring-current-audit.sh" render --anchor "<anchor_bead>" --as comment   # the account
"$(gc <binding> scripts-dir)/bring-current-audit.sh" show --anchor "<anchor_bead>"                  # the raw record
# <<< triage-round-read
```

The account gives a routine entry one line. The raw record keeps what that
line leaves out: what collided, what to check, and git's evidence.

## What it judges

The check index is closed: you may add any check it declares and you may not
invent one. For each check the index declares, read its method and ask whether
the diff you skimmed warrants it. Add the check when the answer is yes. Two
rules bound the judgment:

- **A check's method may name paths that make it mandatory.** When the diff
  touches such a path, the check is added whatever the rest of the method would
  argue. Nothing re-derives the diff behind you, so a miss here is a check the
  anchor never gets.
- **Adding nothing is the expected common case.** A one-file fix inside one
  component, a test addition, a doc correction, a formula-poured mechanical
  change — none earns a specialist review. Widening costs a cadence hop and a
  session per anchor, and the feedback distiller watches the add-rate for exactly
  that drift.

A round that conflicted is also yours to rule on. Each entry says what collided
(the two intents), what the worker decided and why, what a reviewer should
check, and the worker's rating: `routine` for an adjacent-line collision, an
overlapping comment edit or an obvious composition, and `judgment` for an
informed decision, such as an inferred intent, a side chosen on substance, or
something new written. The rating is the worker's, and it gates nothing; the
guard's evidence beside each entry says what git could and could not merge on
its own. An item listed with no entry from the worker comes from a resume that
asked for no audit, and only the guard's evidence describes it, so read the
merged code there yourself. Look at the merged code where an entry tells you
to, then decide what the round reopens:

- **Nothing** (`--reopen none`). The resolution preserved both intents in a way
  a reader can confirm from the account, and nothing reviewed before the round
  is now in doubt.
- **Lanes run again** (`--reopen correctness`, or any lane the anchor already
  declares, such as `arch`, or `demo` when what a person sees changed). The
  merged code needs a fresh look in that lane. A check the anchor does not yet
  declare is added the usual way, with `--add-gates`, and it runs on the merged
  code too.
- **The approval is lifted** (`--dismiss-approval`). The round made a call
  that is the operator's to make: it changed what the PR does, by inferring
  one side's intent or by choosing between two live designs. A round that only
  changed how the approved behavior is achieved does not lift: reopen the lanes
  that can check it, and the approval stands. A lift names its decision in
  `--round-reason`: the call, what it means for the PR, and where to look. That
  text opens your posted verdict and the dismissal note. When you cannot name
  such a call, do not lift. No approval given at or before the round counts
  toward the merge from then on, and a new approval lands the PR.

Lanes and the lift combine. Say why in `--round-reason`, one line a person can
act on; on a lift it is the decision above. Never give the approval predating
the round as the reason for a lift: every round postdates the approval it would
lift, so that tells the operator nothing.

## What blocks

Nothing. Triage never blocks: its verdict is always `approve`, the classifying
pass that derives the triage lane green and lets the rest of the cadence
proceed. Triage files no findings, so it has no findings block.

- It never judges correctness, and it never files findings about the code. A
  defect you notice while skimming belongs in the `correctness` review, not here;
  say so in the verdict body and let that check hold it.
- It never fixes anything, and it never touches the anchor other than through
  `signoff.sh`.
- It never re-runs because the branch grew. Its verdict binds the lane to no
  commit: an appended commit does not re-stale the triage lane, and no pass
  re-classifies the grown diff. Two things reopen the lane: a rewrite that takes
  the reviewed commit off the branch supersedes the review, and a bring-current
  round that conflicted reopens it to rule on that round. gate-ensure then pours
  a fresh triage at the live head.

## The verdict

The formula's one `signoff.sh` call carries the verdict and the widening
together, `approve` with these flags:

- **`--add-gates`** takes the checks you add, one or several, comma-separated,
  as in `--add-gates demo,arch`. Adding nothing needs no flag: approve on its
  own is the full verdict. Widening is monotonic and `signoff.sh` enforces it.
  The write is a set union with read-back: nothing you pass can remove a check
  already declared, only a triage verdict may add one, and no dispatcher,
  formula, or other reviewer may pre-set or shrink `check_set`. The
  checks-needed decision lives here, in one place a human can audit.
  `signoff.sh` validates the add against the same effective index at the
  reviewed commit, and records every added check on the anchor's notes as a
  `triage-add:` line, so the add-rate the distiller watches stays countable.
- **`--reopen`**, **`--round-reason`** and **`--dismiss-approval`** carry the
  ruling on a conflicted round, as in
  `--reopen correctness --round-reason "<why>" --dismiss-approval --add-gates arch`.
  `signoff.sh` hands the ruling to the guard, which records it in the anchor's
  record and sends each reopened lane back to unreviewed. On a lift it first
  stores the round's time on the anchor as `bring_current_lifted_at`, the line
  the approval rule reads, then re-requests each approver and dismisses the
  approvals the line covers.

The verdict body is the triage trail, collapsed under the line `signoff.sh`
opens the comment with: what you read, and each check you added or left out
and why, naming what in the diff warranted each one you added. On a ruling,
the verdict opens with your decision on a lift, and the round's account sits
collapsed under that line, rendered from the record the same way whether or
not you lifted: what collided, what was decided, and what reopened.
