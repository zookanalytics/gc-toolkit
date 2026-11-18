---
name: review-ruling
description: Use when you hold a review run's rule-and-repair step, or when asked how a review run rules a lane's finding, a person's comment or an ask, and which fixes its round makes.
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
---

# Review ruling

You rule every finding a lane raised at the head the round judged and every ask
the round can take, and you make the round's fixes. The step that rules is the
step that fixes, so a ruling is what you change: a point ruled must-fix gets a
commit, and a point ruled declined, deferred, answered or put to a person gets
no change at all. Each point is ruled by the rule its source carries, below,
and each ruling carries its reason, which the head's comment shows the operator
as that point's answer.

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
- **A finding that rule does not block** is ruled as the rule says. On the
  correctness method's scale, a P2 of a lane that requested changes is must-fix
  when its fix is low-risk and net-positive and declined when it is risky or
  marginal, and a P2 of a lane that approved is answered and not fixed.
- **Every finding is ruled**, so a finding you do not act on is still answered
  where the PR shows its lane's verdict.

## A failure partway through the change's own steps

The correctness method's section of that name says what such a failure is, and
the fix it takes: the shape in which the failure cannot happen or cannot last.
A point of this kind, a lane's finding or a person's comment, is ruled by its
own rule as any point is, and these decide what the head carries for it:

- **Its fix is that shape.** Make it when the point's rule makes the point
  must-fix. When the shape reaches outside the reviewed diff, a blocking point
  is deferred, as any such fix is.
- **Code that repairs the act is a person's call.** Code whose only job is to
  find, remember or repair the change's own half-done act is written only on a
  person's ruling, such as an ask that carries one or the answer to a question
  put to them.
- **A point no such shape can fix gets no code.** A blocking one is put to a
  person (A question only a person can answer, below), because keeping the gap
  or building its repair is theirs to decide. A non-blocking one is declined.
- **A point that holds and gets no fix records its gap.** Its reason says where
  the gap is, what one occurrence costs and what would show that one happened.
- **A gap in a round's own fix is not fixed again.** A point of this kind raised
  against code that an earlier round wrote as its fix is ruled as one no such
  shape can fix.
  `git log --format='%h %B' origin/<the PR's target>..HEAD -- <the locus's file>`
  lists the branch's commits to that file with their messages. A round's fix
  commit names in its message the point it fixed, and `git show <commit>` shows
  whether it wrote the code the locus names.

## Each fix is a commit of its own

Fix each point you rule must-fix with a commit of its own in the run's
worktree, whose message names the point, and name that commit in its ruling.
Two points never share a commit, and no point is answered by a fix made for
another point or by another lane's fix.

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

## A fix outside the reviewed diff

A fix that reaches outside the diff the operator reviews, such as code the PR
does not touch, goes to a bead of its own: `review-run.sh defer` files it
waiting on the PR's bead, armed to start once the PR lands, with the PR's
target as its own. Rule the point deferred, and name the bead in the reason.
The PR stays the change the operator reviewed.

## A person's comment

A person's comment reaches the run as an ask. Grade it on the scale the
correctness method gives a reviewer's finding, in its What blocks, and apply
that scale's rule for the grade: a P0 or a P1 is fixed; a P2 is fixed when its
fix is low-risk and net-positive and declined when it is risky or marginal;
and a nit, a preference that no grade covers, is answered and not fixed. The
reason names the grade. A comment that raises a failure partway through the
change's own steps is fixed only as the section of that name above says.

A batch of a person's comments reaches the run as one ask, and each comment in
it is a human finding naming that ask as its fix unit, which the round's read
lists under the ask. Rule each comment by its grade, as above, and record that
ruling on its finding as well as in the round's output, so the comment is
answered on the PR once the ask closes:

```bash
"$(gc <binding> scripts-dir)/review-run.sh" finding --finding <finding> --ruling <must-fix|declined|deferred|answered|question> --reason "<the answer, naming the grade>"
```

A question also names its gate, `--gate <gate>`. A deferred comment's follow-up
bead is filed by this call, waiting on the PR's bead and taking the PR's target,
so file no second one with `review-run.sh defer`. The call prints the follow-up,
which the ruling's reason names.

An ask that carries a ruling the operator made, as a sitting's send-back does,
is applied as ruled and not graded again.

## A question only a person can answer

Put it to a human gate on the PR's bead with `review-run.sh question`, rule it
question, and name the gate. The round goes no further on that point, and the
run records no passed result while the gate is open. The next run starts from
the answer.

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
answer the operator reads. A must-fix point's answer is the commit that fixes
it, which the head the round pushed carries. Any other point's answer says why
the head carries no change for it. A reason never says a point is fixed that
the head does not carry the fix for.
