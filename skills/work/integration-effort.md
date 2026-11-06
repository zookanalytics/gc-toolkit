# Stand up an integration effort

The `work` skill's section of the same name points here.

A PR comes from one bead, which owns it and its rework until it merges, so
`closed` always means landed. A lone bead needs nothing else: filed in its rig's
store and slung, it opens its own PR into main.

Work the operator reviews as one PR is an **integration effort**. Its beads land
on one integration branch with no PR of their own, and one **landing bead**
carries the branch to main through that PR. A bead of the effort the operator
asks to review on its own is a **stage**, slung `--merge mr`, whose PR goes into
the branch.

A city-scoped session's `gc bd` resolves to the city store unless it names a
rig. A dispatch bead left there is invisible to the rig's polecat pool, which
reads only the rig store, so it maroons, claimable by no one. Name the rig with
`--rig <rig>` on every dispatch create and on every link between dispatch beads:
the same `<rig>` you sling to. bd holds nothing on an edge between two stores,
so every bead of an effort is filed in its rig's store. `<rig>/<binding>.refinery`
and `<rig>/<binding>.polecat` are the rig's refinery and polecat pool, as
`gc agent list` prints them, and `<binding>` is the name the city imports the
pack under, as in the skill.

Stand an effort up with a landing bead, one push, three writes per bead and a
summary task, reading each write back before the next step. Nothing goes to the
refinery or to a pool until every wait of the effort reads back:

```bash
# 1. The landing bead: an ordinary task titled for what the effort delivers,
# whose description says what it is to deliver, under the effort's epic when it
# has one (drop --parent when it has none).
LANDING=$(gc bd --rig <rig> create "<what the effort delivers>" -t task -d "<what the effort is to deliver>" --parent <epic> --json | jq -r '.id // empty')
BRANCH="integration/$LANDING"

# 2. Its branch, cut from the default branch origin/HEAD names (main when it
# names none) with one create-only push from the rig's checkout, after a fetch.
# The push sends a ref and moves no checkout. Its empty lease refuses a branch
# that already exists, so a resumed recipe that finds the branch on origin goes
# on. mol-design-convoy cuts its subject's branch with the same marked blocks.
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

# 3. Record the branch, and the default branch as the target, on the landing
# bead, and read both back.
gc bd --rig <rig> update "$LANDING" --set-metadata branch="$BRANCH" --set-metadata target="$BASE" \
  && gc bd --rig <rig> show "$LANDING" --json | jq -e --arg b "$BRANCH" --arg t "$BASE" '.[0].metadata | .branch == $b and .target == $t' >/dev/null \
  || { echo "$LANDING does not read back its branch and target; stopping" >&2; exit 1; }

# 4. File each bead of the effort with its target in its create and the landing
# bead's wait on it, and read both back. Nothing is slung yet.
WORK=$(gc bd --rig <rig> create "<task>" -t task -d "<what to build>" --parent <epic> \
  --metadata "$(jq -nc --arg t "$BRANCH" '{target: $t}')" --deps "blocks:$LANDING" --json | jq -r '.id // empty')
[ -n "$WORK" ] \
  && gc bd --rig <rig> show "$WORK" --json | jq -e --arg b "$BRANCH" '.[0].metadata.target == $b' >/dev/null \
  && gc bd --rig <rig> dep list "$LANDING" --direction=down -t blocks --json | tr -d '[:cntrl:]' | jq -e --arg w "$WORK" 'any(.[]; .id == $w)' >/dev/null \
  || { echo "${WORK:-the bead} does not read back its target and the landing bead's wait; stopping" >&2; exit 1; }

# 5. The summary task, once every bead of the effort is filed: no target, under
# the effort's epic, its description naming the landing bead. It waits on each
# bead of the effort and the landing bead waits on it, all read back.
SUMMARY=$(gc bd --rig <rig> create "summary: the PR for <what the effort delivers>" -t task \
  -d "Write the pr_summary of $LANDING once every bead this task waits on has landed, by the polecat doctrine's paragraph on integration branches." \
  --parent <epic> --deps "<each bead of the effort, comma-separated>,blocks:$LANDING" --json | jq -r '.id // empty')
[ -n "$SUMMARY" ] || { echo "no summary task filed; stopping" >&2; exit 1; }
WAITS=$(gc bd --rig <rig> dep list "$SUMMARY" --direction=down -t blocks --json | tr -d '[:cntrl:]' | jq -r '[.[].id] | join(" ")')
for B in <each bead of the effort>; do
  case " $WAITS " in *" $B "*) ;; *) echo "$SUMMARY does not wait on $B; stopping" >&2; exit 1 ;; esac
done
gc bd --rig <rig> dep list "$LANDING" --direction=down -t blocks --json | tr -d '[:cntrl:]' | jq -e --arg s "$SUMMARY" 'any(.[]; .id == $s)' >/dev/null \
  || { echo "$LANDING does not wait on $SUMMARY; stopping" >&2; exit 1; }

# 6. Hand the landing bead to the refinery, at the address gc agent list prints,
# with the notice that assignment owes. It waits on every bead of the effort and
# on the summary task, so the refinery takes it only once they have all closed.
gc bd --rig <rig> update "$LANDING" --assignee <rig>/<binding>.refinery \
  && "$(gc <binding> scripts-dir)/deferred-dispatch.sh" notify "$LANDING" --agent <rig>/<binding>.refinery \
  || { echo "$LANDING is not handed to the refinery; dispatching nothing" >&2; exit 1; }

# 7. Dispatch the work: sling each bead of the effort, or arm it when it waits
# on other work (a stage is slung with --merge mr), then arm the summary task
# on mol-polecat-report.
gc sling <rig>/<binding>.polecat "$WORK"
"$(gc <binding> scripts-dir)/deferred-dispatch.sh" arm "$SUMMARY" --target <rig>/<binding>.polecat \
  --sling-arg --on --sling-arg mol-polecat-report --reason "writes the pr_summary of $LANDING once the effort's beads land"
```

The branch is named for the bead that lands it, so an integration branch has one
landing bead. Every bead is filed and waited on before any is slung, and the
landing bead goes to the refinery only once it waits on all of them and on the
summary task, so no bead can land while the landing bead waits on fewer than all
of them. The summary task is dispatched once the effort's beads have landed, and
its close releases the landing bead to the refinery, which opens the one PR with
the summary the task wrote.

A bead that joins the effort later takes step 4's writes, and a summary task's
wait on it, before it is slung. The summary task waits on the bead and never the
reverse, because the summary must read the branch after the bead has landed. The
effort's summary task is the landing bead's wait whose title begins `summary:`,
the newest when there are several. While it still carries its arm and no
dispatch marker, and a bead it waits on is still open, no dispatch pass can
sling it, and its own wait on the bead is enough:

```bash
# The summary task's wait on a bead that joins later, after step 4's writes.
# dep add's second id is the bead that is waited on.
gc bd --rig <rig> show "$SUMMARY" --json | tr -d '[:cntrl:]' | jq -e '.[0] | (.metadata | (.["gc.dispatch_when_ready"] // "") != "" and (.["gc.dispatch_when_ready_slung"] // "") == "") and any(.dependencies[]?; .dependency_type == "blocks" and .status != "closed")' >/dev/null \
  && gc bd --rig <rig> dep add "$SUMMARY" "$WORK" --type=blocks \
  && gc bd --rig <rig> dep list "$SUMMARY" --direction=down -t blocks --json | tr -d '[:cntrl:]' | jq -e --arg w "$WORK" 'any(.[]; .id == $w)' >/dev/null \
  || { echo "$SUMMARY may already be dispatched, or does not wait on $WORK; file a fresh summary task by step 5" >&2; exit 1; }
```

A summary task that has been dispatched may already have read the branch. One
whose beads have all closed may still be slung by a pass that read it as ready
before the wait was added, because a pass slings from the readiness it read
when it started. Either way a fresh summary task waits on the bead instead:
filed and read back by step 5 with the bead among its waits, which makes the
landing bead wait on it too, and armed as in step 7. Then sling the bead. Once
the refinery has taken the landing bead, work for its branch rides the PR as a
rework or a supplement.

A **shared input artifact** (a decisions doc, a spec several beads need before
any produce mergeable work) is the effort's first bead. It lands on the branch
like any bead, and the beads that need it wait on it with a `blocks` edge.

A bead that builds on work reaching main after the branch was cut needs the
branch brought current first. That is a hand-off to the mechanik, not a bead of
the effort: a task assigned to the mechanik that waits on the outside work by a
`blocks` edge, with the notice `deferred-dispatch.sh` records for an assignment.
The bead that needs the branch current waits on the hand-off by a `blocks` edge
and is armed to dispatch when the hand-off closes. Once notified, the mechanik
brings the branch current from a disposable worktree: a fast-forward to main
when the branch holds nothing main lacks, and a merge of main into it when it
does. It pushes the result and closes the hand-off. A merge that conflicts is
not mechanical: the mechanik pushes nothing and puts it to the operator with a
human gate on the hand-off, which then waits on it:
`"$(gc <binding> scripts-dir)/human-gate.sh" --subject <hand-off> --key
bring-current-conflict --message "<what collided, and the decision the merge
needs>"`.

An effort is ranked and parked through its epic. A convoy may still track an
effort's beads for status, and carries nothing they read.

Per-dispatch override: `gc sling <target> <bead> --var base_branch=<ref>` points
one pour at any ref; explicit `--var` wins over the auto-compute. It sets only
the pour it starts, so a bead that lands on another branch carries that branch
as its own `target`, written in its create, where every later pour reads it.

**Anti-pattern:** a bead filed for an effort without its `target`. It branches
from main and lands on main through a PR of its own, outside the effort's PR,
and nothing declines it before it is built.
