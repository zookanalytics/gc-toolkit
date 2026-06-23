{{ define "polecat-non-impl-done" }}
## Non-impl done sequence override

**This section supersedes the FINAL REMINDER, the "ABSOLUTE
RESTRICTION: No Bead Closing", and the "CRITICAL: Never Close
Beads" prohibition for tasks that produce no commits** — PR
reviews, research syntheses, and investigations that end in bead
notes.

The "no closing" rules exist because impl-task closure must come
from the refinery after a verified merge; non-impl tasks have
nothing for the refinery to verify, so the polecat closes the
bead itself.

### Why an override is needed

The unconditional impl done sequence (push branch, set
`metadata.branch`/`target`, hand to refinery) strands non-impl
beads: refinery sees a branch with no commits ahead of the target,
rejects the merge, and the bead loiters open until a human closes
it.

### Detect at done time

A bead is non-impl if ANY of the following match. Check in priority
order — explicit signals from the spawner are the most reliable;
the zero-commit check is the durable structural fallback that
catches tasks the spawner didn't label.

1. **Explicit PR signal** — `metadata.pr_number` or `metadata.pr_url`
   is set. Review-task formulas stamp these.
2. **Title convention** — bead title matches `^Review PR#\d+`.
3. **Explicit task-kind label** — `metadata.task_kind` is `review`,
   `research`, or `investigation`. (The spawner may not set this
   today; this is the future-friendly hook.)
4. **Zero-commit fallback** — `git rev-list <target>..HEAD --count`
   is `0`. Structural catch for unlabeled tasks; also catches the
   case where a review touched a config file in passing but didn't
   actually produce mergeable work.

```bash
META=$(gc bd show <work-bead> --json | jq -c '.[0]')
TARGET=$(echo "$META" | jq -r '.metadata.target // "{{ .DefaultBranch }}"')
COMMITS=$(git rev-list "origin/$TARGET..HEAD" --count 2>/dev/null || echo 0)

NON_IMPL=""
[ -n "$(echo "$META" | jq -r '.metadata.pr_number // .metadata.pr_url // empty')" ] && NON_IMPL=1
echo "$META" | jq -r '.title // ""' | grep -qE '^Review PR#[0-9]+' && NON_IMPL=1
echo "$META" | jq -r '.metadata.task_kind // ""' | grep -qE '^(review|research|investigation)$' && NON_IMPL=1
[ "$COMMITS" -eq 0 ] && NON_IMPL=1
```

If `NON_IMPL` is set: run the non-impl done sequence below. Otherwise:
run the impl done sequence in the FINAL REMINDER above. The "Never
Close Beads" prohibition is lifted for the non-impl case — polecats
close non-impl beads themselves because there is nothing for the
refinery to merge.

### Non-impl done sequence

Do NOT set `metadata.branch`, `metadata.target`, or route to
refinery — there is nothing for the refinery to merge. Post the
artifact yourself before closing; one of the recurrences this
override exists to fix was a review bead whose review never
reached GitHub.

```bash
# 1. Post the artifact if it isn't already posted.
#    - Review tasks (pr_number/pr_url set): submit the verdict via
#      `gh pr review <num>` with the body and verdict flag. BEFORE
#      posting, check whether an earlier attempt already submitted
#      a review under your handle — don't double-post:
#        gh api repos/<owner>/<repo>/pulls/<num>/reviews \
#          | jq '.[] | select(.user.login == "<your-handle>") | .submitted_at'
#      A recent submission means skip the post step.
#    - Research/investigation tasks: ensure findings live in the
#      bead via `gc bd update <work-bead> --notes "..."` before close.
gh pr review <pr-num> ...   # or: gc bd update <work-bead> --notes "..."

# 2. Stamp task-specific metadata (review_id, pr_url, verdict, etc.)
gc bd update <work-bead> --set-metadata <task-specific fields>

# 3. Close the bead with a reason describing the task kind.
gc bd close <work-bead> --reason "<review|research|investigation> complete"

# 4. Drain and exit.
gc runtime drain-ack
exit
```

### Fix-target dispatch (pre-publish review gate)

When `metadata.fix_target_pool` is set, the review is a pre-publish gate
(the refinery opened the PR as draft and is waiting on your verdict). Under
close-on-merge the work bead stays OPEN as the PR's gating anchor: on
APPROVE/COMMENT you un-draft the PR (the anchor closes later, on merge, via
the refinery's reconcile pass — not here); on REQUEST_CHANGES you re-route
that SAME anchor back to the implementation pool. After posting the verdict
via `gh pr review` (step 1 above) and BEFORE closing the REVIEW bead (step 3
above), act on it:

```bash
FIX_POOL=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.fix_target_pool // empty')
PR_NUMBER=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.pr_number')

if [ -n "$FIX_POOL" ]; then
  case "$VERDICT" in
    APPROVE|COMMENT)
      # No blocking findings. Un-draft the PR so the operator sees it.
      # Best-effort: if this one-shot fails (transient GraphQL error, a
      # restart mid-flow, a Dolt wedge), do NOT block the review bead or
      # escalate — the refinery patrol's draft-PR reconcile pass converges
      # the PR to ready on its next idle wake.
      gh pr ready "$PR_NUMBER" || echo "un-draft failed; refinery patrol will reconcile this PR's draft state" >&2
      ;;
    REQUEST_CHANGES)
      # Close-on-merge: the work anchor stays OPEN through gating, so rework
      # re-routes the SAME anchor back to the fix pool — NOT a separate fix bead
      # (which would leave two open anchors on one PR). Resolve the anchor as the
      # bead this review gates: the dependent of the blocks-dep the refinery
      # attached (`gc bd dep <review> --blocks <anchor>`). See
      # docs/work-bead-state-machine.md.
      ANCHOR=$(gc bd dep list <work-bead> --direction=up -t blocks --json 2>/dev/null \
        | jq -r '.[0].id // empty')
      if [ -n "$ANCHOR" ]; then
        # Re-open the anchor as fix-pool demand. Its branch + PR metadata are
        # intact from gating, so a fix polecat resumes the EXISTING PR branch
        # via the rejection-resume flow.
        gc bd update "$ANCHOR" \
          --status=open --assignee="" \
          --set-metadata rejection_reason="codex review requested changes on PR#$PR_NUMBER; see PR review comments for findings" \
          --set-metadata gc.routed_to="$FIX_POOL"
        gc session wake "$FIX_POOL" || true
      else
        # Fallback — no gating anchor resolved (a pre-close-on-merge PR, or the
        # gate-dep failed to attach). File a standalone fix bead via the legacy
        # rejection-resume flow so rework never deadlocks; warn so the missing
        # edge is noticed.
        echo "WARN: no gating anchor for review <work-bead>; filing a standalone fix bead" >&2
        PR_HEAD=$(gh pr view "$PR_NUMBER" --json headRefName -q .headRefName)
        PR_BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q .baseRefName)
        PR_URL_FOR_FIX=$(gh pr view "$PR_NUMBER" --json url -q .url)
        FIX_BEAD=$(gc bd create "Address codex findings on PR#$PR_NUMBER" -t task --json | jq -r .id)
        gc bd update "$FIX_BEAD" \
          --set-metadata branch="$PR_HEAD" \
          --set-metadata target="$PR_BASE" \
          --set-metadata rejection_reason="codex review requested changes on PR#$PR_NUMBER; see PR review comments for findings" \
          --set-metadata source_review_bead=<work-bead> \
          --set-metadata merge_strategy=pr \
          --set-metadata existing_pr="$PR_URL_FOR_FIX" \
          --set-metadata pr_url="$PR_URL_FOR_FIX" \
          --set-metadata pr_number="$PR_NUMBER" \
          --set-metadata gc.routed_to="$FIX_POOL"
        gc session wake "$FIX_POOL" || true
      fi
      ;;
  esac
fi
```

`$VERDICT` is whichever verdict you submitted via `gh pr review` —
`APPROVE`, `REQUEST_CHANGES`, or `COMMENT`. Treat `COMMENT` as
non-blocking (operator sees the PR with your notes attached).

After this step, close the review bead as in the existing flow
(step 3 of the Non-impl done sequence above).
{{ end }}
