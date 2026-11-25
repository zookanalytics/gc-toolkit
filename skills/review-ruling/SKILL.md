---
name: review-ruling
description: Use when you hold a review run's rule-and-repair step, or when asked how a review run rules a lane's finding, a person's comment or an ask, and which fixes its round makes.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Review ruling

You rule every finding a lane raised at the head the round judged and every ask
triage left you, and you make the round's fixes. The step that rules is the
step that fixes, so a ruling is what you change. A point ruled must-fix gets a
commit, a fix in the PR's title or summary, or both. A point ruled declined,
deferred, answered or put to a person gets no change at all. Each point is
ruled by the rule its source carries, below, and each ruling carries its
reason, which the head's comment shows the operator as that point's answer.

Triage answers a person's post that needs only an answer before you read the
round, and your read lists each ask it answered under triage and leaves it out
of yours: its answer is on the PR, and you do not rule it again. When triage
left you nothing, no lane and no ask, the read says so, and the step closes
with nothing written.

The method for a lane's own check is not yours to apply again. A lane already
judged its finding by its method. You decide what the round does about it.

## A lane's finding

Rule it by that lane's own rule for what blocks: the What blocks section of its
method, the skill `<binding>.review-<check>`, where `<binding>` is the name in
front of this skill's own. Read the lane's evidence first, in its part of the
run's workspace, which the round's read lists: its worktree, its trail, and any
capture it made. A finding of a check the pack ships no method for is ruled by
the purpose its row in the check index states.

- **A blocking finding** is must-fix, unless the lane's own rule shows it does
  not hold. Then it is declined, and the reason names what in the evidence
  shows it.
- **A fix is the simplest change that removes the cause.** A design in which
  the failure cannot happen comes before code that detects the failure and
  repairs it. Weigh what one occurrence costs and how likely it is, as the
  finding's failure scenario states them, against the code the fix adds for
  every later change to carry. When the only fix in reach is heavier than the
  failure warrants, build nothing: put a blocking finding to a person (A
  question only a person can answer, below), and decline one that does not
  block.
- **A finding that rule does not block** is ruled as the rule says. On the
  correctness method's scale, a P2 of a lane that requested changes is must-fix
  when its fix is low-risk and net-positive and declined when it is risky or
  marginal, and a P2 of a lane that approved is answered and not fixed.
- **Every finding is ruled**, so a finding you do not act on is still answered
  where the PR shows its lane's verdict.

## Each fix is a commit of its own

Fix each point you rule must-fix with a commit of its own in the run's
worktree, whose message names the point, and name that commit in its ruling.
Two points never share a commit, and no point is answered by a fix made for
another point or by another lane's fix. A point fixed only in the PR's title
or summary needs no commit, as the next section says.

For each must-fix point, find the other sites in the change that share its
cause, and fix them in the same round. Name them in the ruling's reason, so the
next lane need not raise each one in turn.

An ask to bring the branch current, such as a conflict with the target, is
answered by merging the PR's target into the run's worktree. When git needs your
help with that merge, its message carries the account the next round's triage
reads beside `git show --remerge-diff`: commit it with `git commit -F <file>`,
the file holding git's first line, then one paragraph for each file you resolved
by hand, naming what collided, what you kept or wrote and why, and what a
reviewer should check.

A conflict goes to a person only when the target deleted code the branch edits,
or defines a name the branch also adds, because whether the branch still has
work to do is then the person's call. Abort the merge with `git merge --abort`
and put it to them as A question only a person can answer says, naming the
change on the target and the branch's code it meets. A rewrite of code the
branch edits is no such question: resolve it, and its paragraph of the account
says what the target changed there and how the branch's edit applies to it.

## A fix in the PR's title or summary

The bead that owns the PR records the PR's title and summary. The round's read
names that bead beside the PR. The calls below take it as `<pr-bead>`.

Fix a point on the title or the summary on that bead, whether a lane's finding
or an ask raised it. Rule the point must-fix with `"summary": true` in its
ruling:

- When the fix changes only the title or the summary, the ruling names no
  commit.
- When the fix also changes code, the ruling names that commit too.

Record the summary again whenever the round leaves it untrue:

- when the round rules a point on the title or the summary must-fix;
- when the round's commits or questions change what the summary states, such
  as a fix's cost or what stands before the merge.

Read the summary `<pr-bead>` records:

```bash
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
"$GCTK" pr summary <pr-bead>
```

Write it again whole, to the standard the `<binding>.commit-conventions` skill
holds for a PR's summary, in a file in the repair's part of the run's
workspace. Record it from that file:

```bash
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
"$GCTK" pr summary <pr-bead> --file "<the summary file>"
```

Add `--title "<the subject line>"` to that call when the PR's title changes.

Then push as the step says, even when the round has no commits to push.

## A fix outside the reviewed diff

A fix that reaches outside the diff the operator reviews, such as code the PR
does not touch, goes to a bead of its own: `review-run.sh defer` files it
waiting on the PR's bead, armed to start once the PR lands, with the PR's
target as its own. Rule the point deferred, and name the bead in the reason.
The PR stays the change the operator reviewed.

## A red check the target carries

A red-check ask names a required check that fails at the PR's head. The check
is the branch's to fix, unless the PR's target is the rig's default branch and
its own head fails the check for the same reason, such as the same test, which
no change on the branch can fix. The tracker below is the default branch's
alone: `preexisting-failure.sh file` sends a tracker it files with no target,
so its fix branches from the rig's default branch and lands there. A failure
another target carries, such as an effort's integration branch, stays the
branch's to fix, since the PR's merge carries the fix to that target.
`gc rig list --json` names each rig's `default_branch`. Read the target's
checks at its head:

```bash
gh api "repos/<owner>/<repo>/commits/<target>/check-runs" --jq '.check_runs[] | "\(.name) \(.conclusion) \(.html_url)"'
```

When the target carries the failure, send it to its one tracker and leave the
PR waiting on that tracker. `preexisting-failure.sh key` derives the failure's
key from its test function (`--test`), its path (`--target`) or its lint
finding (`--lint`), and `file` prints the tracker it finds under that key, or
the one it files and sends to be fixed. The tracker's message is the failure as
the target's run shows it, with its log, which goes on the lines between the
quoted here-document's delimiters, where every character stays as the log has
it. The ask then waits on the tracker:

```bash
SCRIPTS="$(gc <binding> scripts-dir)"
KEY=$("$SCRIPTS/preexisting-failure.sh" key --test <the failing test function>)
FAILURE=$(cat <<'TARGET_LOG'
<the failure as the target's run shows it, with its log>
TARGET_LOG
)
TRACKER=$("$SCRIPTS/preexisting-failure.sh" file "$KEY" --message "$FAILURE")
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
"$GCTK" review ask <the PR's bead> --source <the red-check ask> --waiting-on "$TRACKER" --reason "Bring '<the PR's branch>' current by merging origin/<target> in once $TRACKER fixes <the check> on '<target>'."
```

Rule the red-check ask declined, and name the tracker and the new ask in its
reason. While that ask is open, the landing order asks no person about the
head staying red, and once the tracker closes, the run that takes the ask
brings the branch current.

## A person's comment

A person's comment reaches the run as an ask. Grade it on the scale the
correctness method gives a reviewer's finding, in its What blocks, and apply
that scale's rule for the grade: a P0 or a P1 is fixed; a P2 is fixed when its
fix is low-risk and net-positive and declined when it is risky or marginal;
and a nit, a preference that no grade covers, is answered and not fixed. The
reason names the grade.

Each comment is its own ask, whose reason names the post and ends with its URL.
Read the post at that URL as it stands, and rule it by its grade, as above. The
round's post answers it where it was made, with the ruling's reason as the
answer, so write the reason to the person who made the comment. A comment owed
no words, such as a thank-you, is ruled answered with `wordless`, and its
answer on the PR is the city's 👍 alone.

An ask that carries a ruling the operator made, as a sitting's send-back does,
is applied as ruled and not graded again.

## A question only a person can answer

Put it to a human gate on the PR's bead with `review-run.sh question`, rule it
question, and name the gate. Its message is what the person reads on the board,
so name in it what it asks about: a person's post by the URL its ask's reason
ends with, and an ask that names no post, such as a conflict, by what its reason
names. The round goes no further on that point, and the run records no passed
result while the gate is open. Each question on the PR is such a gate, under a
`review-question-<slug>` key, and this lists them, each open, or closed with
the person's answer as its `close_reason`:

```bash
gc bd gate list <the bead that owns the PR> --all --json
```

The run after the answer rules the question's own ask, the one the gate's
message names, by that answer.

## A comment made while a question is open

A person may comment while a question the run put to them waits on its gate,
open in that list. When the comment settles the question, or makes it moot,
name the gate in its ask's ruling as `settles`, with `moot` set when the
comment makes the question moot rather than answering it, and rule the
question's own ask by the answer. The round's post closes the gate with the
comment as its answer and says so in its reply. A comment that settles nothing
leaves the gate open, and its reply says the question still stands. Rule the
question's own ask a question again, naming the same gate.

## A decline stands

No round changes code for a point a round of this run declined, deferred,
answered or put to a person. A decline is overruled only by a ruling recorded
where the round reads it: an ask that carries the operator's ruling, which you
rule must-fix as a point of its own. A flag in a commit message or a reason is
no such ruling, and the round's output check refuses a fix for an ask an
earlier round of the run declined.

An ask stays open until the run records its result, so it is ruled again at
each head: answered once the head carries its fix, or once its check ran there.

## Each answer says what the head carries

The head's comment is rendered from your rulings, so write each reason as the
answer the operator reads. A must-fix point's answer names its fix: the commit
the round pushed, the fix in the PR's title or summary, or both. Any other
point's answer says why the head carries no change for it. A reason never says
a point is fixed unless the head or the PR's title or summary carries the fix.
