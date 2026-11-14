# Stand up an integration effort

The mechanik runs this recipe. It stands up an integration effort: beads that
land on one integration branch, each with no PR of its own, and reach the
default branch together through one PR the operator reviews. The landing bead
records the branch, and the refinery opens that PR from it. A stage is a bead
of the effort the operator asks to review on its own: slung `--merge mr`, its
PR goes into the branch. The summary task records the landing bead's PR
summary once the effort's beads have landed.

A converse sitting does not run the recipe: step 2 is a push from the rig's
checkout, and a sitting pushes only the branch of a change the operator rules
it make, through Work's hand-off. The work skill says where a sitting sends an
effort instead.

File every bead of the effort in its rig's store, and pass `--rig <rig>`, the
rig you sling to, on every `gc bd` call, as the recipe does. A city-scoped
session's `gc bd` otherwise writes to the city store, where the rig's polecat
pool never sees the bead, and bd blocks nothing on an edge between two stores.
`<rig>/<binding>.refinery` and `<rig>/<binding>.polecat` are the rig's refinery
and polecat pool as `gc agent list` prints them, and `<binding>` is the name
the city imports the pack under, as in the work skill.

Fill in each placeholder and run the steps in order. Steps 2 to 6 stop when a
write fails.

```bash
# 1. The landing bead, under the effort's epic (drop --parent when it has
# none). The branch is named for it, so a branch has one landing bead.
LANDING=$(gc bd --rig <rig> create "<what the effort delivers>" -t task -d "<what the effort is to deliver>" --parent <epic> --json | jq -r '.id // empty')
BRANCH="integration/$LANDING"

# 2. Cut the branch from the default branch, the one origin/HEAD names or main
# when it names none, with one create-only push from the rig's checkout. The
# push moves no checkout. Its empty lease refuses a branch origin already
# carries, so a resumed recipe that finds the branch there goes on.
RIG_ROOT=$(gc rig list --json | jq -r --arg r <rig> '.rigs[] | select(.name == $r) | .path')
[ -n "$LANDING" ] && [ -d "$RIG_ROOT" ] || { echo "no landing bead, or no checkout of <rig>; stopping" >&2; exit 1; }
# >>> effort-default-branch
git -C "$RIG_ROOT" fetch --prune origin || { echo "git fetch failed in $RIG_ROOT" >&2; exit 1; }
DEFAULT_REF=$(git -C "$RIG_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
BASE="${DEFAULT_REF#refs/remotes/origin/}"
[ -n "$BASE" ] && [ "$BASE" != "$DEFAULT_REF" ] || BASE=main
# <<< effort-default-branch
# >>> effort-branch-push
git -C "$RIG_ROOT" show-ref --verify --quiet "refs/remotes/origin/${BASE}" || { echo "origin/${BASE} not found to cut $BRANCH from" >&2; exit 1; }
if ! git -C "$RIG_ROOT" push origin "refs/remotes/origin/${BASE}:refs/heads/${BRANCH}" --force-with-lease="refs/heads/${BRANCH}:"; then
  git -C "$RIG_ROOT" fetch origin "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}" || true
  git -C "$RIG_ROOT" show-ref --verify --quiet "refs/remotes/origin/${BRANCH}" || { echo "the push of $BRANCH failed and origin does not carry it" >&2; exit 1; }
  echo "origin already carries $BRANCH, so an earlier pass cut it"
fi
# <<< effort-branch-push

# 3. Record the branch, and the default branch as its target, on the landing
# bead.
gc bd --rig <rig> update "$LANDING" --set-metadata branch="$BRANCH" --set-metadata target="$BASE" \
  || { echo "$LANDING did not record its branch and target; stopping" >&2; exit 1; }

# 4. File each bead of the effort with the branch as its target, in its create,
# and the landing bead's wait on it. A bead filed without its target branches
# from main and lands there through a PR of its own, outside the effort, and
# nothing stops it before it is built. Sling nothing yet, so a recipe that
# stops before step 7 leaves no bead sent to a pool.
WORK=$(gc bd --rig <rig> create "<task>" -t task -d "<what to build>" --parent <epic> \
  --metadata "$(jq -nc --arg t "$BRANCH" '{target: $t}')" --deps "blocks:$LANDING" --json | jq -r '.id // empty')
[ -n "$WORK" ] || { echo "no bead filed, with its target and the landing bead's wait; stopping" >&2; exit 1; }

# 5. Once every bead of the effort is filed, the summary task: no target, under
# the effort's epic, waiting on each bead of the effort, with the landing bead
# waiting on it.
SUMMARY=$(gc bd --rig <rig> create "summary: the PR for <what the effort delivers>" -t task \
  -d "Write the PR summary of $LANDING once every bead this task waits on has landed, by the polecat doctrine's paragraph on integration branches." \
  --parent <epic> --deps "<each bead of the effort, comma-separated>,blocks:$LANDING" --json | jq -r '.id // empty')
[ -n "$SUMMARY" ] || { echo "no summary task filed; stopping" >&2; exit 1; }

# 6. Assign the landing bead to the refinery. Its patrol finds its work by the
# beads assigned to it, and the landing bead waits on the effort's beads, so
# the assignee alone hands it over: Gas City nudges the refinery when the last
# of them closes. The refinery takes it once nothing it waits on is open, so
# assign it only after every wait above is written: then it cannot reach the
# default branch before every bead of the effort and the summary task has
# closed.
gc bd --rig <rig> update "$LANDING" --assignee <rig>/<binding>.refinery \
  || { echo "$LANDING is not handed to the refinery; dispatching nothing" >&2; exit 1; }

# 7. Sling each bead of the effort, or arm it when it waits on other work, and
# sling a stage with --merge mr. Arm the summary task on mol-polecat-report: it
# runs once the effort's beads have landed, and once it closes, the refinery
# takes the landing bead and opens the PR with the summary it wrote.
gc sling <rig>/<binding>.polecat "$WORK"
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
"$GCTK" bead arm "$SUMMARY" --target <rig>/<binding>.polecat --on mol-polecat-report \
  --reason "writes the PR summary of $LANDING once the effort's beads land"
```

## Add a bead to an existing effort

1. File it by step 4, and sling nothing yet.
2. Make the effort's summary task wait on it, by the block below. The summary
   task is the bead the landing bead waits on whose title begins `summary:`,
   the newest when there are several. It waits on the bead, never the reverse,
   because the summary must read the branch after the bead has landed. The
   block adds the wait only while the summary task is armed and a wait of its
   own is still pending, as `gctk bead holds` answers it, because then the
   deferred-dispatch order cannot sling it first: the order clears an arm once
   it has sent the bead.
3. When the block refuses, file a fresh summary task by step 5 with the bead
   among its waits, which makes the landing bead wait on it too, and arm it as
   in step 7. A summary task that has been dispatched may already have read the
   branch, and one whose beads have all closed may still be slung by a run of
   that order that read it as ready before the wait was added.
4. Then sling the bead.

```bash
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
RIG_ROOT=$(gc rig list --json | jq -r --arg r <rig> '.rigs[] | select(.name == $r) | .path')
# dep add's second id is the bead that is waited on.
"$GCTK" bead holds --db "$RIG_ROOT/.beads" "$SUMMARY" | jq -e '.error == null and (.arm.target // "") != "" and (.pending | length) > 0' >/dev/null \
  && gc bd --rig <rig> dep add "$SUMMARY" "$WORK" --type=blocks \
  || { echo "$SUMMARY may already be dispatched, or the store refused its wait on $WORK; file a fresh summary task by step 5" >&2; exit 1; }
```

Once the refinery has taken the landing bead, send work for its branch to the
PR as a rework or a supplement (the prs skill).

## Share an input among the effort's beads

When several beads need one input before any can produce mergeable work, such
as a decisions doc or a spec, file it as the effort's first bead. It lands on
the branch like any bead. Give each bead that needs it a `blocks` edge on it,
and arm those beads in step 7 rather than sling them.

## Bring the effort's branch current

A bead of the effort that builds on work reaching the default branch after the
branch was cut needs the branch brought current first. That is a task for the
rig's refinery, the hand-off below, and not a bead of the effort. A merge that
is clean needs no polecat, so no self-review and no review check reads the
default branch's commits as its change.

1. File the hand-off by the block below. It names the effort's landing bead
   and waits on the outside work by a `blocks` edge. The block assigns it to
   the refinery, as the work skill sends the refinery a bead. It carries no
   `branch`, because the refinery's patrol takes a bead that carries one as a
   branch to land.
2. Make the bead that needs the branch current wait on the hand-off by a
   `blocks` edge, and arm it to dispatch when the hand-off closes (the waits
   skill).
3. Once the outside work has landed, Gas City nudges the refinery with the
   hand-off's id, and the refinery brings the branch current. It fast-forwards the branch to the
   default branch when the branch holds nothing the default branch lacks, and
   otherwise merges the default branch into it. It pushes the result and
   closes the hand-off, which releases the bead.
4. A merge that conflicts goes to a polecat, never to the operator. The
   refinery pushes nothing and files the merge as a bead of the effort, a task
   on its branch that the hand-off and the landing bead wait on. The summary
   task already waits on it, through the bead that waits on the hand-off. The
   refinery sends the task to the rig's polecat pool, and the polecat resolves
   each conflict, asking the operator only when a resolution needs a product
   decision. Unlike a clean merge, the task's merge goes through checks, and
   that is accepted because its resolution is written by hand. The checks of the
   polecat's self-review and of the refinery's gate run on the merged tree,
   and a check that reads a diff reads the default branch's gains as part of
   the task's change. A check that fails the same way at the default branch's
   head is the default branch's own failure, which the task's brief has the
   polecat treat as pre-existing. No review check reads the task, because it
   lands on the effort's branch directly. Once the task lands, the hand-off
   comes back to the refinery, which brings the branch current from where the
   task's merge left it. The refinery's prompt holds the method of steps 3
   and 4.

```bash
# The hand-off, under the effort's epic (drop --parent when it has none).
LANDING=<the landing bead of the effort>
OUTSIDE=<the bead of the outside work>
HANDOFF=$(gc bd --rig <rig> create "Bring integration/$LANDING current once <the outside work, such as its PR> lands" -t task \
  -d "Once $OUTSIDE has landed, bring the branch of $LANDING, the effort's landing bead, current with the target it records. A merge that conflicts goes to a polecat, which resolves it and asks the operator only when a resolution needs a product decision. <What the outside work changes that the bead waiting on this builds on.>" \
  --parent <epic> --deps "$OUTSIDE" --json | jq -r '.id // empty')
[ -n "$HANDOFF" ] || { echo "no hand-off filed, with its wait on the outside work; stopping" >&2; exit 1; }
gc bd --rig <rig> update "$HANDOFF" --assignee <rig>/<binding>.refinery \
  || { echo "$HANDOFF is not handed to the refinery; make nothing wait on it yet" >&2; exit 1; }
```

## Set an effort's priority or park it

Do both on the effort's epic: its beads follow its priority, and parking it
(`gc-helm.sh park`) holds those that have not started. A convoy that tracks the
beads only reports their status, so do neither on the convoy.

## Start a workflow from another branch

`gc sling` starts a `mol-polecat-work` workflow from the bead's `target`, else
the `target` of a convoy among its parents, else the rig's default branch. To
start one workflow from another branch on origin, name it as `base_branch`:
`gc sling <rig>/<pool> <bead> --var base_branch=<branch>`. A tag or a commit id
fails at worktree setup, which starts from `origin/<branch>`.

`base_branch` affects this workflow. The bead's `target` decides where the work
lands and where later slings start. When the bead has no `target`,
`mol-polecat-work` records this workflow's base as its `target` at submit, so
the work lands on `<branch>` and later slings start there too. To land a bead on
another branch from the start, write that branch as its `target` in its create,
as step 4 does.
