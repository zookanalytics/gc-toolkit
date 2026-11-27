---
name: review-triage
description: Use when you hold triage's step of a review run, or when asked which review checks a diff warrants.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Review triage

You are classifying, not judging. Whether the change is correct is the
`correctness` check's question, not yours. Yours is narrower:
**which specialist checks does this diff warrant?** The usual honest answer is
none.

## What it reads

Triage judges one change, at the head the formula you run under names. A review
run's formula runs it at every head the run judges: the run's first head and
each head its own repair pushes.

Three inputs, in this order.

1. **The check index** — the pack's checks, with the rows of the
   `review-checks.toml` the commit under review carries laid over them. It
   declares the checks you may add. Read it first; it is the one place the
   available checks are declared.
2. **The PR's bead**, which states what the change was for, and the rig's
   guidance for triage, the head's `docs/review-triage.md`, which the run's read
   printed when the head carries one. A rig steers
   triage there in words, such as never adding a check, or adding one only for
   one kind of change: advice you weigh beside your own reading of the diff.
3. **The change, at the head** — the run's read prints the change at its head: none at a head that already passed into the run's
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
can change a pack check's purpose for that rig. The pack's index sits
beside the pack's scripts, which `gc <binding> scripts-dir` finds from any rig:
it prints the directory holding them. `<binding>` is the name the city
imports the pack under, which gc puts in front of this skill's name:
`gc-toolkit` in `gc-toolkit.review-triage`. `gc skill list` prints it in this
skill's FROM column. The rig's rows come out of `<head>`, the head you judge, not off disk —
the tree you stand in is your own worktree, not the commit you are classifying,
and a branch may change the index it is judged against:

```bash
# >>> triage-index-read
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
GCTK_SCRIPTS_DIR="$(gc <binding> scripts-dir)" "$GCTK" review checks --show --at "<head>"
# <<< triage-index-read
```

Each row gives you the check and one line of purpose. When a check applies is
a judgment its method states, so read the method: the skill
`<binding>.review-<check>` in your catalog. A check of the rig's own has no
skill, and its purpose is the whole of what it judges. There is no
applies-when column in the index.

A commit that carries no index of its own still has the pack's checks, so
every review has a menu. A non-zero exit is an index nobody read: a commit the
checkout cannot read, a head the block was not given, or a scripts dir gc
cannot print. Stop and say so rather than classify with no menu.

### A merge resolved by hand

Bringing the branch current means merging its base in. When that took
resolution by hand, the worker wrote what collided and what it decided, and the
run's read prints the account: each merge commit in the change, which you read
with `git show --remerge-diff <commit>`, showing exactly the hunks resolved by
hand, and its message, where the worker wrote the account.

## What it judges

The check index is closed: you may add any check it declares and you may not
invent one. For each check the index declares, read its method and ask whether
the diff you skimmed warrants it. Add the check when the answer is yes. Two
rules bound the judgment:

- **A check's method may name paths that make it mandatory.** When the diff
  touches such a path, the check is added whatever the rest of the method would
  argue. Nothing re-derives the diff behind you, so a miss here is a check the
  head never gets.
- **Adding nothing is the expected common case.** A one-file fix to one
  component's internals, a test addition, a typo fixed in a doc, a
  formula-poured mechanical change — none earns a specialist review. Each
  check you add costs a lane's session at the head, and the feedback distiller
  watches the add-rate for exactly that drift.

**Whether the change is material** is also yours to rule. A change is material
when it made a call that is the operator's to make: it changed what the PR
does, by inferring one side's intent or by choosing between two live designs.
A change that only alters how the approved behavior is achieved is not
material. A review run asks this at every head, and at a material one the
formula's withdrawal call withdraws the approvals given before that head,
naming the call, what it means for the PR, and where to look, before you write
the output, which the output check refuses until that withdrawal is filed.

## What blocks

Nothing. Triage never blocks: its output carries no verdict. Triage files no
findings, so it has no findings block.

- It never judges correctness, and it never files findings about the code. A
  defect you notice while skimming belongs in the `correctness` review, not here;
  say so in the verdict body and let that check hold it.
- It never fixes anything, and it never touches the PR's bead other than
  through the calls its formula names.

## The verdict

The verdict goes where the formula you run under says. A review run's triage
writes it as its step's output: the head it judged, each check it picks as one
`{"check", "head"}`, which the run bonds as a lane at that head, with nothing
picked the common case, and whether the change is `material`. Pick these
checks whatever the change:

- At the PR's first judged head, the rig's first check, `correctness`.
- Each check an ask the run can take sends back.
- Each check the run so far names on a finding fixed in the PR's title or
  summary. The finding's ruling reads `<check> finding <id>: must-fix in the
  PR's summary`, or `must-fix by <commit> and in the PR's summary`. A reason
  the run has not passed reads `<check> finding <id> was fixed in the PR's
  summary in iteration <n>, and <check> has not run since`.

At a head that already passed into the run's target, the read says there is no
change to judge. Pick only the checks the list's last two items name there.
When they name none, pick nothing.
