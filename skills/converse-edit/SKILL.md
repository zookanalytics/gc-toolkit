---
name: converse-edit
description: Converse's edit of a change the operator rules a sitting make with them, and its hand-off to review.
---

# Editing a change with the operator

The operator can rule, in this sitting, that you make a change with them. This
skill carries that change from the ruling to the refinery. The steps keep their
own skills: the hold still records what the operator owes, each hand-back is
still recorded before you post it, and the sign-off still closes the
conversation. Each tool call starts a fresh shell, so set `CONV`,
`CONVERSATION` and `SUBJECT` literally, from what step 1 found, at the top of
every call below, and `CHANGE` and `TREE` too once the calls below have printed
them.

## The line

You change a repository only when the operator rules, in this sitting, that you
make the change, and only a change whose next step is their reaction:

- a document's wording or a screen's look, which they react to as it takes
  shape;
- a small fix agreed here, whose spec would take as long to write as the
  change.

The ruling licenses the edit, so you never edit on your own judgment, and the
line is how you judge what to propose. Work whose spec can be written down and
sent goes to a pool on a formula (the converse-settle step): you hold the
operator while you work, so work that needs no reaction would spend their
attention for nothing. When the operator asks for an edit outside the line, say
so and recommend sending it, and their ruling decides.

Whatever the ruling, you never:

- hold more than one change in flight in this conversation, so a second waits
  until the first is handed off or dropped;
- change a repository other than your own rig's, the rig your conversation is
  filed in. The hold below is a `blocks` edge, which holds only between two
  beads in one store, so a change to another rig's repository goes to that
  rig's pool;
- edit in your home, whose start syncs it to the default branch and refuses a
  start that finds an edit or a commit there;
- push to a target branch, merge, or force a push: the hand-off pushes the
  change's own branch, and the refinery lands it;
- edit an open PR's branch (below);
- cut an integration effort's branch, which stays the mechanik's recipe or
  `mol-design-convoy`'s step.

## An open PR takes a rework

You edit no open PR's branch. The branch takes one writer at a time, the PR's
rework child, which a polecat runs, and the review machinery keys on that
child: no review is dispatched while it is open, and a ruling's rework returns
every lane to unreviewed. A push of your own would bypass both. So a ruling
that changes what an open PR's branch must contain sends a rework through the
sign-off's `--rework` (the converse-settle step). When more than one call
stands between the PR's text and what the operator wants, settle them in the
thread first (the `converse-iterate-document` step).

## File the change and hold it, before the first edit

First read who holds the subject: its assignee, its route and a run in flight,
which step 4's prime showed and `"$CONV/bead-context.sh" "$SUBJECT"` shows
again. When a pool, a run or the refinery already holds it, tell the operator,
and their ruling decides whether that work stops (the `work` skill, stopping
work already sent) before you file anything. That reading informs the operator
and never picks the bead.

Every change is a bead you file in your own rig's store, as you file work for a
pool (the `work` skill, filing new work): beside the subject, or as its member
when the subject is an epic. Its target goes in the create: the rig's default
branch, or the integration branch of an effort the change belongs to. It
carries no route and no `hold:mayor`, because the operator routed it here. Its
description records the ruling: the operator's words, quoted, with the date and
this conversation, and the scope of the change, so a reviewer sees where its
decisions came from. A bead you file carries only what you wrote. The subject
can carry a gate, a route, an arm, a hold, an earlier branch and a description
written before the ruling, which Work's writers would meet and reviewers would
judge the change against.

The create, the hold and the record on the subject run in one call, each only
once the one before it has landed. Add `--parent "$SUBJECT"` to the create when
the subject is an epic:

```bash
CHANGE=$(gc bd create "<what the change does>" -t task --metadata '{"target":"<the target>"}' \
    -d "Made with the operator in conversation $CONVERSATION, on their ruling of $(date -u +%Y-%m-%d): \"<their words>\"
Scope: <what the change covers>" --json | jq -er '.id') \
  && echo "CHANGE=$CHANGE" \
  && gc bd dep add "$CHANGE" "$CONVERSATION" --type=blocks \
  && gc bd update "$SUBJECT" --append-notes "$(date -u +%Y-%m-%d): the operator ruled that this sitting make a change with them: \"<their words>\". $CHANGE carries it." \
  && echo "filed and held"
```

No `filed and held` line means a write did not land: repair what printed
before the first edit. The `blocks` edge onto the conversation is the hold.
While the conversation is open, bd counts the change blocked, so no pool is
offered it, and Work's writers take the edge as the proof that this sitting
holds the change.

## Make the subject wait on the change

From the filing on, the subject waits on the change, so no pool takes the
subject while you edit, and a dismiss leaves it waiting on the change. First
withdraw the subject's arm and pool route, as the sign-off's case **New work
carries it** does (the converse-settle step). The block keeps a `human` route,
which sends the subject to no pool, and prints its last line only once each
write has exited 0:

```bash
WHY="the operator ruled that conversation $CONVERSATION make the change that carries it"
ROW=$(gc bd show "$SUBJECT" --json) \
  && ARM=$(printf '%s\n' "$ROW" | jq -er --arg s "$SUBJECT" 'if type == "array" and length == 1 and .[0].id == $s then (.[0].metadata["gc.dispatch_when_ready"] // "") | tostring else error("unread") end') \
  && ROUTE=$(printf '%s\n' "$ROW" | jq -er '(.[0].metadata["gc.routed_to"] // "") | tostring') \
  && { [ -z "$ARM" ] || "$CONV/deferred-dispatch.sh" disarm "$SUBJECT" --reason "$WHY"; } \
  && { [ -z "$ROUTE" ] || [ "$ROUTE" = human ] || gc bd update "$SUBJECT" --unset-metadata gc.routed_to; } \
  && echo "$SUBJECT carries no arm and no pool route"
```

An epic subject takes no edge, brief or arm: it already waits on its member, bd
refuses the edge, and its members carry its close. Nor does a subject the
sign-off arms no closer for take the brief or the arm, as the sign-off says when
it refuses a `--close-brief`: an anchor, a bead assigned to someone, one routed
to `human`, which the block above keeps and the arm refuses, or one at a status
other than open. Such a subject takes the edge alone:
`gc bd dep add "$SUBJECT" "$CHANGE" --type=blocks`.

Any other subject takes the wait the `waits` skill gives a bead that is checked
and closed once other work lands: the close brief, the `blocks` edge and the
validating closer's arm, each only once the one before it has landed. Write the
brief as the claim the closer tests, what the change's landing settles on the
subject and what to check once it has, and keep its text, because the sign-off
names it again:

```bash
gc bd update "$SUBJECT" --append-notes "## Close brief (held on $CHANGE, $(date -u +%Y-%m-%dT%H:%M:%SZ))
<what the change's landing settles on the subject, and what to check once it has>" \
  && gc bd dep add "$SUBJECT" "$CHANGE" --type=blocks \
  && "$CONV/deferred-dispatch.sh" arm "$SUBJECT" --target "$GC_RIG/gc-toolkit.polecat" --sling-arg --on --sling-arg mol-validate-close --reason "waits for $CHANGE, the change conversation $CONVERSATION makes; the validating closer checks it once that lands" \
  && gc bd label list "$SUBJECT"
```

The deferred-dispatch pass sends no arm while `hold:mayor` holds the subject,
so remove each label it lists that spells `hold:mayor`, in any case, one
`--remove-label` each, because bd removes a label only by its exact text:
`gc bd update "$SUBJECT" --remove-label hold:mayor`.

## Resume a change a sitting filed

The one bead you edit that this sitting did not file is a change an earlier
sitting filed and a dismiss left open, which the operator engages to resume. It
is then this conversation's subject. You know it for a change by its own record,
the ruling its description holds, never by who holds it now. Its original
subject has waited on it since it was filed, and that wait stands. Add only your
hold, and append this sitting's ruling to the change, which as the subject also
takes your outcome record:

```bash
gc bd dep add "$SUBJECT" "$CONVERSATION" --type=blocks \
  && gc bd update "$SUBJECT" --append-notes "$(date -u +%Y-%m-%d): resumed in conversation $CONVERSATION on the operator's ruling: \"<their words>\". <what is left to do>" \
  && echo "held and recorded"
```

`CHANGE` is the subject from here on. Write no close brief, no closer's arm and
no edge that makes the change wait on itself, before the first edit or at the
sign-off.

## Read the polecat class's standards before the first edit

Your prompt carries the standards for what a sitting writes. The standards for
changing a repository are the polecat class's, in their fragments, so read them
before the first edit, as the mechanik reads its own, when they are not in your
context:

```bash
cat "$CONV"/../../template-fragments/work-quality-polecats.template.md "$CONV"/../../template-fragments/learned-conventions-polecat.template.md
```

## Set up the tree

Work's setup cuts the change's tree under your home, at
`worktrees/<the change>`, on `polecat/<the change>` fresh from its target, and
records `work_dir` and `branch` on the change, as it does for a polecat's work.
Under `--held-by` it takes your hold as the proof that you hold the change:

```bash
"$CONV/work-setup.sh" --bead "$CHANGE" --held-by "$CONVERSATION"
```

Its last line is the tree, `TREE` from here on. Run again, after a restart or
in a later sitting, it re-enters the tree the change records, wherever that is.
Exit 1 is a refusal, and its message says why (When a writer refuses, below).

Never enter the tree with this shell, because the hand-off removes it. Edit its
files by their full paths under the tree, and run git there as
`git -C "$TREE"`.

## Edit with the operator, a commit per agreed step

Make each step with the operator, and commit it once they agree to it, so the
tree holds nothing a later sitting cannot read. The commits stay local until
the hand-off pushes them. Commit with no identity flags: your session's own git
configuration signs the commit and names its author, as a polecat's does. The
subject and body follow the `gc-toolkit.commit-conventions` skill, with the
change's id at the end of the subject:

```bash
git -C "$TREE" add <the files> \
  && git -C "$TREE" commit -m "<type>(<scope>): <what this step changes> ($CHANGE)" -m "<why: the ruling, and what this step does>"
```

After the first commit, read its signature:

```bash
git -C "$TREE" log -1 --format=%G?
```

`G` is a good signature. Anything else means this session's commits carry no
signature the rig can verify, and a rig that requires verified signatures
refuses the push at the hand-off. Tell the operator now, while the change is
one commit.

## Show the operator a copy of the UI

When the change is to a rig's UI, the operator reacts to a copy of it: a live
page served from the tree on fixture data, at an address of its own that they
open in their own browser. Start one once the tree is set up:

```bash
"$CONV/ui-copy.sh" start --tree "$TREE" --rig "$GC_RIG" --publish
```

It prints `key=value` lines: `address=` is the address to give the operator,
and `port=` is the copy's port on this host. A tree has one copy, so start is
safe to run again, after a restart too. It reports the copy that runs, or starts
one, and publishes again a copy that has lost its address.
`"$CONV/ui-copy.sh" status --tree "$TREE"` says whether the copy runs and still
has its address. The copy runs what its serve command built when it started, so
an edit the command does not reload shows only once you stop the copy and start
it again, which gives it a new port and address to give the operator.

A rig that declares no serve command offers no copy, so its look cannot be
shown live: start exits 1 with `reason=no-serve-command`. Say so, and recommend
sending the change on a formula (the converse-settle step), and the operator's
ruling decides.

Where `address=` is empty, `detail=` says why. A copy whose publish command
ended gets its address back when you run start again. Where the city can give no
address, the operator cannot open the copy: stop it, and show them screenshots
instead. Capture each look from the
tree with `demo-screenshot.sh`, which serves the tree with the rig's serve
command in a sandbox where the live city cannot be reached. Drive the app to
the look with a script in the `gc-toolkit.demo-capture` skill's format, keep
each image outside the tree and your home, and read each one yourself before you
describe it to the operator:

```bash
SERVE=$(gc formula show mol-rig-demo --rig "$GC_RIG" --json | jq -r '[.vars[] | select(.name == "ui_serve_command")][0].rig_default // empty')
"$CONV/demo-screenshot.sh" page --script "<the script>" --serve "$SERVE" --port 0 --cwd "$TREE" --output "<the image>"
```

The operator sees the images on GitHub once the change has a PR. After the
hand-off, once the change records a `pr_number`, attach each image there:

```bash
"$CONV/demo-deliver.sh" --file "<the image>" --subject "$CHANGE"
```

Stop the copy at the hand-off, at a drop and at the sign-off, as those sections
say. A copy left running ends once your session has ended, because Gas City's
orphan sweep ends a process that carries an ended session's id.

## Run the rig's checks

Before you ask for the go, run the checks a polecat's self-review runs, with
the commands the rig declares for it. They run through `gctk rig` in the tree,
which records each result at the commit it ran at, so the pass is recorded at
the head you hand off, and the correctness review reads it there as it reads a
polecat's. Commit first, because a check refuses a tree with changes its commit
does not hold:

```bash
VARS=$(gc formula show mol-polecat-work --rig "$GC_RIG" --json) \
  && printf '%s' "$VARS" | jq -e '.ok == true and (.vars | type == "array")' >/dev/null \
  || { echo "the rig's declared checks did not read, so none ran" >&2; exit 1; }
cmd() { printf '%s' "$VARS" | jq -r --arg n "$1" '[.vars[] | select(.name == $n)][0] | if . == null then "" elif .rig_default != null then .rig_default else (.default // "") end'; }
"$CONV/rig-checks.sh" self-review --bead "$CHANGE" --setup "$(cmd setup_command)" --typecheck "$(cmd typecheck_command)" \
  --lint "$(cmd lint_command)" --build "$(cmd build_command)" --affected "$(cmd affected_tests_command)" --test "$(cmd test_command)"
```

It exits 0 when every check passes, 1 when one fails, and 4 when a check could
not say, which `gctk rig`'s line explains. A suite can pin a prompt's or a
skill's wording, so a wording change can fail it, and the operator is here to
decide whether the pin or the wording changes. Fix a failure with them, commit,
and run the checks again. The hand-off does not wait on a pass, because the
PR's checks are the change's checks: the refinery's gate, the review checks, CI
and the operator's approval. A failure you hand off goes in the summary, with
why.

## Write the summary and the title

You hold the rulings, so you write the PR's summary, to the standard the
`gc-toolkit.commit-conventions` skill holds for a PR's summary. It quotes the
ruling and says that the change was made with the operator in a sitting. Write
it to a file outside the tree and outside your home, such as the one
`mktemp "${TMPDIR:-/tmp}/summary.XXXXXX"` prints, and the hand-off removes the
file once it has used it. The title is the change's subject line, by the same
skill, with its type and scope and no bead id.

## Hand it off on the operator's go

Ask for the operator's go once the steps they agreed are in. They can give it
when they rule the edit, which leaves the moment to you. After the hand-off
every further change waits a review round, so the go is the operator saying
they have finished reacting.

The hand-off is the polecat's submit under `--held-by`: the same branch gate,
push and check of origin's ref, summary and title on the anchor, three
hand-off writes, wake of the refinery, and removal of the tree with its local
branch. Its last write removes your hold, once the refinery holds the change.
The change is then the anchor, as a polecat's fresh work is: one bound for the
default branch reaches a PR, and one in an effort lands on the effort's branch.
Stop the copy of the UI first, because the tree it serves goes too:
`"$CONV/ui-copy.sh" stop --tree "$TREE"`, which exits 0 when no copy runs. Run
the hand-off in a subshell that enters the tree, so your own shell stays in its
home when the tree goes:

```bash
( cd "$TREE" && "$CONV/work-submit.sh" --bead "$CHANGE" --held-by "$CONVERSATION" \
    --notes "Handed off from conversation $CONVERSATION on the operator's go: <what the change does>" \
    --summary-file "<the summary file>" --title "<the subject line>" ) \
  && gc bd comment "$CONVERSATION" "Made a change with the operator and handed it to review: <what it does, in plain words>"
```

Exit 0 is handed off, and the comment records the hand-off as one of the
visit's actions, which the comment on the subject's pull request lists once the
visit ends. Exit 3 means you owe something first, such as a file left
uncommitted: do it, and run the hand-off again. Exit 1 is a refusal or a stop,
below.

## When a writer refuses

Under `--held-by` neither writer files a gate, cancels anything or drains: each
stop exits 1 with its reason, because the operator is here to hear it. A
refusal of the proof writes nothing. Read the reason, tell the operator, and
answer it:

- **The refinery holds the change** (`it is assigned to` the refinery). The
  hand-off assigned it, in a run that stopped after the assignment, or the
  refinery took it another way. Either way the change is the refinery's now.
  Remove your edge if it still stands, because it would hold the change until
  the conversation closes, and wake the refinery the refusal names, as the
  hand-off does:

  ```bash
  gc bd dep list "$CHANGE" --direction=down --type blocks --json \
      | jq -e --arg c "$CONVERSATION" 'any(.[]; .id == $c)' >/dev/null \
    && gc bd dep remove "$CHANGE" "$CONVERSATION"
  gc session wake <the refinery>; gc session nudge <the refinery> "Run 'gc prime' to check merge queue and begin processing."
  ```

  Gas City's reaper removes the tree once the change closes.
- **Someone else holds it**: it is assigned to another holder, a run works it,
  or it is routed to a pool. Remove your edge the same way, because it would
  hold their work until the conversation closes, and tell the operator who
  holds the change.
- **The hold is missing.** `gc hook current` names another bead when this
  session does not hold its conversation, and step 1's claim takes it again.
  When the missing `blocks` edge onto the conversation is the only reason, add
  it as the filing does. Then run the call again.
- **A hand-off cut short**: a write refused, or the call cut off, before the
  refinery was assigned. The change is unassigned and your edge stands, so run
  the hand-off again. It writes nothing the first run did not reach, beyond its
  note appended again.
- **The push refused**, such as a commit the rig refuses unsigned. Nothing is
  handed off, and the change stays with you. Tell the operator what the push
  said.

## Drop a change

When the operator drops a change, their ruling also says what becomes of the
subject's ask. First withdraw the closer's arm from the subject that waits on
the change, when the filing armed it, so the closer does not put a drop they
ruled back to them. The disposition writer moves no wait under not needed, so
the change's close ends the subject's wait, and a closer still armed would then
be sent. That subject is this conversation's subject, or for a resumed change
the bead an earlier sitting made wait on it, which
`gc bd dep list "$CHANGE" --direction=up --type blocks` lists. Then close the
change through the disposition writer as not needed, with this conversation as
the evidence. Naming the conversation is what lets the close land: bd refuses
to close a bead an open bead blocks, and the writer gives your hold way to its
own edge onto the conversation:

```bash
"$CONV/deferred-dispatch.sh" disarm <the subject that waits on it> --reason "the operator dropped $CHANGE in conversation $CONVERSATION" \
  && gc bd update "$CHANGE" --set-metadata gc.work_outcome=no-op \
  && "$CONV/bead-rehome.sh" --origin "$CHANGE" --successor "$CONVERSATION" --kind not-needed --note "<the operator's ruling, one sentence>"
```

Then stop the copy of the UI, and remove the tree and its local branch with
git, from your home, a worktree of the same repository. Git refuses a tree that
holds uncommitted edits, and those are part of the change the operator dropped,
so run the removal again with `--force` then:

```bash
"$CONV/ui-copy.sh" stop --tree "$TREE"
git -C "${GC_DIR:-$PWD}" worktree remove "$TREE" && git -C "${GC_DIR:-$PWD}" branch -D "polecat/$CHANGE"
```

Once the change has closed, the subject's wait on it holds nothing. Send the
subject on, close it, or leave it waiting on other work, as the operator ruled,
through the sign-off's cases (the converse-settle step).

## A change in flight at a restart, a hand-back or a dismiss

- **The idle sleep** stops a session's process and never touches its disk, and
  it skips a sitting that holds its conversation, so you are not slept while you
  edit.
- **A restart** runs your home's sync, which leaves the tree alone, and step 1's
  restart rule re-opens the sitting at its hold. The conversation's record names
  the change: run Work's setup again, and it re-enters the tree.
- **A sitting that must end with the change in flight**, for low context or
  because it was cut short, commits what the tree holds, records on the
  conversation where the change stands, and hands the conversation back (the
  prompt's low-context path). The conversation stays open, so the change stays
  held, and the next sitting resumes it from the record. A sitting on another
  model has another home, and it enters the tree where the change records it:

  ```bash
  gc bd update "$CONVERSATION" --append-notes "change in flight: $CHANGE at $(git -C "$TREE" rev-parse --short HEAD), its tree at $TREE. In: <the steps agreed and committed>. Left: <what is still to do>."
  ```

- **A dismiss** closes the conversation and so ends the hold. The change stays
  open and unrouted with its tree, its subject keeps waiting on it, and the
  operator engages the change to resume it or drops it.
- **The sign-off** closes the conversation too, so a change still in flight is
  left as a dismiss leaves it. Hand it off or drop it first, unless the operator
  rules that it waits for a later sitting.

## At the sign-off

Stop a copy of the UI that still runs, as one does when the operator rules that
the change waits for a later sitting: `"$CONV/ui-copy.sh" stop --tree "$TREE"`.

Name the subject's wait on the change, `--waiting-on <the change>`, with the
brief's own text as `--close-brief`. The sign-off finds the brief and the arm
you wrote at filing and writes neither again, and bd keeps the headline's edge
as the one edge you wrote, so the subject carries one close brief and one
closer's arm. The converse-settle step carries the rest of the call:

```bash
"$CONV/converse-signoff.sh" --conversation "$CONVERSATION" \
  --outcome "<what this sitting settled or needs next, at most 140 characters>" \
  --ruled yes --ruling "<the ruling, one line>" \
  --waiting-on "$CHANGE" --close-brief "<the brief's own text, as you wrote it at filing>"
```

An epic subject names no wait on its member, because bd refuses that edge, and
a subject that took no brief at filing takes no `--close-brief`. A resumed
change is the subject itself, so its sign-off names no wait on it and passes no
brief.

## After the hand-off

A check's send-back goes where any change's goes, even while this sitting is
open, and it never comes back into the sitting. A failure the branch caused at
the refinery's gate returns the change to the polecat pool with its branch kept
and its rejection reason, and a review that requests changes files a rework
child the pool runs. A polecat resumes your branch, because Work's setup takes
the branch the change records. When the operator wants to react to a finding
live, they engage the change. Its branch then takes a rework once it heads an
open PR (An open PR takes a rework, above), and Work's writers refuse a change a
polecat or the refinery holds.
