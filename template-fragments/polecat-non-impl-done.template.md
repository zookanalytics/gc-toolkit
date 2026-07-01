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

### Fix-target dispatch (pre-publish signoff gate)

When `metadata.fix_target_pool` is set, the review is a **signoff gate** — one
member of the gating anchor's check-set (see docs/work-bead-state-machine.md).
The refinery published the PR (non-draft) and is waiting on your verdict; the
signoff holds the merge, not draft state. The **anchor** stays OPEN as the PR's
gating bead; it closes later, on merge, via the refinery's reconcile pass —
never here. Resolve the anchor as the bead this review gates — the dependent of
the `blocks` dep the refinery attached (`gc bd dep <review> --blocks <anchor>`):

- **APPROVE/COMMENT** — the signoff passes on the **current** head. Stamp the
  gate green at the head you signed off as `check.<gate>=green@<head>` on the
  anchor (the gate name comes from the review bead's `metadata.check_name`,
  default `codex`). The `green@<sha>` value folds "this gate passed" and "title +
  body validated at this commit" into one: a later commit moves the head, so the
  marker no longer matches and the gate re-gates. The PR is already non-draft;
  nothing else to publish.
- **REQUEST_CHANGES** — file a **new rework child** against the anchor (rework
  is a new child, never the same bead reopened and never a cleared marker; see
  docs/work-bead-state-machine.md). Clear `check.<gate>` so the now-unvalidated
  head cannot be merged.

After posting the verdict via `gh pr review` (step 1 above) and BEFORE closing
the REVIEW bead (step 3 above), act on it:

```bash
FIX_POOL=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.fix_target_pool // empty')
PR_NUMBER=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.pr_number')
# Which check-set gate this review satisfies — the per-gate marker key is
# check.<CHECK_NAME>. The dispatch stamps check_name=codex; default to codex for
# an older review bead created before the field existed.
CHECK_NAME=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.check_name // "codex"')

# Resolve the anchor (the bead this review gates) two ways, in order:
#   1. the BLOCKS edge, walked upward — the primary, dep-graph-honest path;
#   2. metadata.anchor_bead on THIS review bead — a durable fallback the
#      dispatch stamps atomically with the review's routing fields.
# The edge is attached best-effort at dispatch (a failed edge must not strand
# the PR). But if the edge is dropped and we resolve ONLY via it, ANCHOR is
# empty, the gate marker check.<gate> is never stamped, and the merge skill holds
# the merge forever ("no signoff yet") — nothing re-dispatches the review, so
# the PR is stuck. The anchor_bead fallback survives a lost edge. The markers
# below let the regression test extract and exercise this exact snippet
# (assets/scripts/signoff-anchor-resolution.test.sh).
# >>> signoff-anchor-resolve
ANCHOR=$(gc bd dep list <work-bead> --direction=up -t blocks --json 2>/dev/null \
  | jq -r '.[0].id // empty')
[ -z "$ANCHOR" ] && ANCHOR=$(gc bd show <work-bead> --json 2>/dev/null \
  | jq -r '.[0].metadata.anchor_bead // empty')
# <<< signoff-anchor-resolve

if [ -n "$FIX_POOL" ]; then
  case "$VERDICT" in
    APPROVE|COMMENT)
      # Record the gate green at the head the signoff validated, as the per-gate
      # marker check.<CHECK_NAME>=green@<reviewed-oid>. The merge skill merges
      # only while that marker still equals green@<live-head>; any later commit
      # makes it stale and re-gates the merge. Best-effort; a miss just defers the
      # merge to the next signoff round, it never merges prematurely.
      if [ -n "$ANCHOR" ]; then
        # Stamp the EXACT commit the signoff reviewed, read from the reviews API
        # (.commit_id) — NOT the PR's live head. The head can advance between the
        # review and this stamp; stamping the live head would mark an UNREVIEWED
        # commit as gate-green and let it merge, defeating the stale-head guard.
        # GitHub attaches the review to the head at submission, so .commit_id is
        # exactly what was reviewed: a commit pushed afterward leaves
        # check.<gate> = green@<old-head> != green@<live-head> and correctly
        # re-gates the merge. Take the latest review under your own handle (the
        # one just submitted).
        REVIEW_HANDLE=$(gh api user -q .login 2>/dev/null)
        REVIEWED_OID=$(gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/reviews" 2>/dev/null \
          | jq -r --arg h "$REVIEW_HANDLE" \
              '[.[] | select(.user.login == $h)] | sort_by(.submitted_at) | last | .commit_id // empty' 2>/dev/null)
        [ -n "$REVIEWED_OID" ] && gc bd update "$ANCHOR" \
          --set-metadata "check.$CHECK_NAME=green@$REVIEWED_OID" >/dev/null 2>&1 || true
      fi
      # The PR is already non-draft (drafts are retired). The check.<gate> stamp
      # above is the only action: it lets the merge skill merge the PR once every
      # check-set gate is green at the still-live head.
      ;;
    REQUEST_CHANGES)
      # Rework is a NEW child of the anchor, not the same anchor reopened and
      # not a flag toggled back on it. The child resumes the EXISTING PR branch
      # via the rejection-resume flow, so a fix polecat reworks the same PR
      # (never a fresh one). Linking it parent-child to the anchor keeps the dep
      # graph honest about who is on this PR and — because the anchor cannot
      # complete while a child is open — holds the merge until the rework lands.
      # The anchor's gating marker (merge_result) is LEFT INTACT; the PR still
      # exists, so the anchor's state must keep saying so. See
      # docs/work-bead-state-machine.md.
      PR_HEAD=$(gh pr view "$PR_NUMBER" --json headRefName -q .headRefName)
      PR_BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q .baseRefName)
      PR_URL_FOR_FIX=$(gh pr view "$PR_NUMBER" --json url -q .url)
      FIX_BEAD=$(gc bd create "Rework PR#$PR_NUMBER: address signoff findings" -t task --json | jq -r .id)
      gc bd update "$FIX_BEAD" \
        --set-metadata branch="$PR_HEAD" \
        --set-metadata target="$PR_BASE" \
        --set-metadata rejection_reason="signoff requested changes on PR#$PR_NUMBER; see PR review comments for findings" \
        --set-metadata source_review_bead=<work-bead> \
        --set-metadata merge_strategy=mr \
        --set-metadata existing_pr="$PR_URL_FOR_FIX" \
        --set-metadata pr_url="$PR_URL_FOR_FIX" \
        --set-metadata pr_number="$PR_NUMBER" \
        --set-metadata gc.routed_to="$FIX_POOL"
      # Attach as a child of the anchor (visibility + completion interlock).
      # Best-effort: a failed edge must not strand the rework, so warn only.
      if [ -n "$ANCHOR" ]; then
        gc bd dep add "$FIX_BEAD" "$ANCHOR" --type=parent-child \
          || echo "WARN: could not link rework $FIX_BEAD under anchor $ANCHOR" >&2
        # The head is no longer gate-validated — clear the gate marker to re-gate.
        gc bd update "$ANCHOR" --unset-metadata "check.$CHECK_NAME" >/dev/null 2>&1 || true
      else
        echo "WARN: no gating anchor resolved for review <work-bead>; rework $FIX_BEAD filed unlinked" >&2
      fi
      gc session wake "$FIX_POOL" || true
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
