---
name: review-triage
description: Use when you hold a review bead whose check is triage, triage's step of a review run, or when asked which review checks a diff warrants or whether a person's post on a PR needs only an answer.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Review triage

You are classifying, not judging. Whether the change is correct is the
`correctness` check's question, not yours. Yours is narrower:
**which specialist checks does this diff warrant?** The usual honest answer is
none. On a review run you also answer a person's post that needs only an
answer, by the narrow bar below, and leave every other post to the step that
rules it.

## What it reads

Triage judges one change, at the head the formula you run under names. A review
bead's formula runs it once per review, at the reviewed commit. A review run's
formula runs it at every head the run judges: the run's first head and each
head its own repair pushes.

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
3. **The change, at the reviewed commit** — the formula names the change and
   its base. A review bead's is the whole PR, `git diff --stat
   origin/<review_base>...HEAD` in `<worktree>`. A review run's read prints the
   change at its head: none at a head that already passed into the run's
   target, since the last head that passed, the run's own repair since its
   first head, which you read with the rulings its push answers, or else the
   whole PR. Read its stat first, then skim the files the stat names.
   A skim is the method here; reading every hunk is the specialist reviewer's
   job, not yours.

### The index

Read the index through `gctk review checks` rather than eyeballing a file. It
has two layers. The pack's own index declares every check the pack ships a
skill for, so every rig has them. The reviewed repo's `review-checks.toml` at
the commit under review, when it keeps one, adds checks of the rig's own and
can change a pack check's purpose or phase for that rig. The pack's index sits
beside the pack's scripts, which `gc <binding> scripts-dir` finds from any rig:
it prints the directory holding them. `<binding>` is the name the city
imports the pack under, which gc puts in front of this skill's name:
`gc-toolkit` in `gc-toolkit.review-triage`. `gc skill list` prints it in this
skill's FROM column. The rig's rows come out of `<reviewed_oid>`, not off disk —
the tree you stand in is your own worktree, not the commit you are classifying,
and a branch may change the index it is judged against:

```bash
# >>> triage-index-read
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
GCTK_SCRIPTS_DIR="$(gc <binding> scripts-dir)" "$GCTK" review checks --show --at "<reviewed_oid>"
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

### A merge resolved by hand

Bringing the branch current means merging its base in. When that took
resolution by hand, the worker wrote what collided and what it decided, and the
formula prints the account: on a review run, each merge commit in the change,
which you read with `git show --remerge-diff <commit>`, showing exactly the
hunks resolved by hand, and its message, where the worker wrote the account. On
a review bead, the worker wrote one audit entry per conflicted file and per
edit beyond the merge, `bring-current-guard.sh` stored the entries on the
anchor beside its own diff evidence, and it reopened this lane. So the anchor's
`bring_current_record` holds a conflicted round with no `triage` ruling, the
reason the review formula prints says so, and your verdict also rules on that
round, which its write refuses to record without the ruling.

On a review bead, read the round first:

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
- **Adding nothing is the expected common case.** A one-file fix to one
  component's internals, a test addition, a typo fixed in a doc, a
  formula-poured mechanical change — none earns a specialist review. Widening
  costs a cadence hop and a session per anchor, and the feedback distiller
  watches the add-rate for exactly that drift.

**Whether the change is material** is also yours to rule. A change is material
when it made a call that is the operator's to make: it changed what the PR
does, by inferring one side's intent or by choosing between two live designs.
A change that only alters how the approved behavior is achieved is not
material. A review run asks this at every head, and at a material one the
formula's withdrawal call withdraws the approvals given before that head,
naming the call, what it means for the PR, and where to look, before you write
the output, which the output check refuses until that withdrawal is filed. A
review bead asks it of a conflicted round, below.

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

## A post that needs only an answer

On a review run, each post a person makes on the PR is an ask the run can take,
and the read lists it with the run so far: its reason names the post's kind and
author and ends with the post's URL. When the post needs only an answer, or
nothing, you answer it yourself, and rule-and-repair does no work for it.

- **Answer a post only when it asks for no change to the branch and no
  person's decision**, such as a question about the change, a thank-you or an
  approval's "looks good". Read it first, at the URL its reason ends with.
  The URL's last part names it: `#issuecomment-<id>` reads with
  `gh api 'repos/{owner}/{repo}/issues/comments/<id>' --jq .body`,
  `#discussion_r<id>` with
  `gh api 'repos/{owner}/{repo}/pulls/comments/<id>' --jq '.path, .line, .body'`,
  and `#pullrequestreview-<id>` with
  `gh api 'repos/{owner}/{repo}/pulls/<number>/reviews/<id>' --jq '.state, .body'`,
  each run in your worktree, whose origin gh fills `{owner}/{repo}` from.
- **Leave every other post to rule-and-repair**: one that asks for a change,
  however small, one that asks a person to choose, one whose answer you cannot
  give from the change and the read, and every ask that names no post, such as
  a red check or a conflict. Leaving a post costs a ruling session, and a
  wrong answer costs the person who asked.
- **While a question the run put to a person is open on the PR's bead, answer
  no post.** A post may settle the question, which rule-and-repair rules, and
  an ask filed before such a question was put may be the question's own. The
  output check refuses both and names the question.

Rule each post you answer `answered`, and write its reason as the answer, to
the person who made the post: the reason is what the reply says and what the
head's comment shows. Mark it `wordless` when it is owed no words, as a
thank-you or a "looks good" is: its answer is then the city's 👍 alone. An ask
you answered in an earlier round of the run is still open until the run records
its result, so answer it again at each head while it still meets the bar. The
formula's post call puts your answers on the PR.

## What blocks

Nothing. Triage never blocks: on a review bead its verdict is always `approve`,
the classifying pass that derives the triage lane green and lets the rest of the
cadence proceed, and on a review run its output carries no verdict. Triage files
no findings, so it has no findings block.

- It never judges correctness, and it never files findings about the code. A
  defect you notice while skimming belongs in the `correctness` review, not here;
  say so in the verdict body and let that check hold it. Answering a question
  about the change is not judging it: an answer that would need you to judge
  the change is a post you leave.
- It never fixes anything, and it never touches the anchor other than through
  the calls its formula names.

## The verdict

The verdict goes where the formula you run under says. A review run's triage
writes it as its step's output: the head it judged, each check it picks as one
`{"check", "head"}`, which the run bonds as a lane at that head, with nothing
picked the common case, whether the change is `material`, and its ruling of
each post it answers. At the PR's first judged head the rig's first check,
`correctness`, is picked whatever the diff,
and the checks an ask the run can take sends back are picked whatever the
change. At a head that already passed into the run's target, the read says
there is no change to judge, because its checks ran and their findings were
ruled: pick only the checks an ask the run can take sends back, and nothing
when no ask sends one. The rest of this section is a review bead's verdict, whose
formula's one `signoff.sh` call carries the verdict and the widening together,
`approve` with these flags:

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
