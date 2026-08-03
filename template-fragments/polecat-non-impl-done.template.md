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
#    - Review tasks (pr_number/pr_url set): post the signoff as a
#      NON-BLOCKING COMMENT — always `gh pr review --comment`, NEVER
#      `gh pr review --approve`. COMMENT-only is BY DESIGN, not a
#      permission fallback: at this phase the city never approves a PR —
#      approval is EXTERNAL (a human, on GitHub). Codex is a review GATE,
#      and the merge is held by the recorded `check.<gate>=green@<head>`
#      marker (stamped in the signoff-gate section below) plus that
#      external approval — never by a GitHub approval from the bot.
#      Commenting (not approving) keeps correctness independent of whether
#      the bot actor happens to hold GitHub approve permission. BEFORE
#      posting, check whether an earlier attempt already submitted a
#      review under your handle — don't double-post:
#        gh api --hostname <host> repos/<owner>/<repo>/pulls/<num>/reviews \
#          | jq '.[] | select(.user.login == "<your-handle>") | .submitted_at'
#      A recent submission means skip the post step. Take <host> and
#      <owner>/<repo> from the review bead's own metadata.pr_url — NOT from
#      whatever repository gh happens to be pointed at, and not from $GH_HOST,
#      which supplies the host for any `gh api` call that omits `--hostname`.
#      Every GitHub call in this fragment is pinned that way; see the
#      PR_REPO/PR_HOST derivation in the signoff-gate section.
#    - PRE-OPEN review tasks (`metadata.review_branch` set, NO `pr_number` —
#      the pre-open codex gate, tk-6d0vb.1.8): there is NO PR yet. Review the
#      BRANCH compare-range instead of a PR, and record the verdict in THIS
#      review bead's notes — the refinery replays it as the opening PR comment
#      when pre-open-resolve.sh opens the PR. Do NOT `gh pr review` (no PR):
#        RB=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.review_branch')
#        RBASE=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.review_base // "main"')
#        git fetch origin "$RBASE" "$RB"
#        REVIEWED_OID=$(git rev-parse "origin/$RB")   # PIN the commit you review
#        git diff "origin/$RBASE...$REVIEWED_OID"     # review THAT exact commit
#      Record BOTH the verdict (notes) AND the reviewed commit (reviewed_oid), so
#      the pass arm below stamps the gate at the commit you actually reviewed and
#      never a head that moved after — the same stale-head guard the post-open arm
#      gets from the reviews API `.commit_id`:
#        gc bd update <work-bead> --set-metadata reviewed_oid="$REVIEWED_OID" \
#          --notes "<verdict + findings>"
#      Then set VERDICT=COMMENT (pass) or VERDICT=REQUEST_CHANGES; the
#      fix-target dispatch below stamps check.codex at reviewed_oid (pass) or
#      files a rework child against the branch (changes).
#    - Research/investigation tasks: ensure findings live in the
#      bead via `gc bd update <work-bead> --notes "..."` before close.
gh pr review <pr-num> --comment --body "<verdict + notes>"   # POST-OPEN signoff PASS: COMMENT only, never --approve
# changes needed → gh pr review <pr-num> --request-changes --body "<blocking findings>"
# PRE-OPEN (review_branch set): NO gh pr review — record the verdict in notes instead:
#   gc bd update <work-bead> --notes "<verdict + findings>"
# (research/investigation instead: gc bd update <work-bead> --notes "...")

# 2. Stamp task-specific metadata (review_id, pr_url, verdict, etc.)
gc bd update <work-bead> --set-metadata <task-specific fields>

# 3. Close the bead with a reason describing the task kind.
#    UNLESS the signoff-gate section below could not record its gate marker: it
#    sets SIGNOFF_UNRECORDED and re-routes THIS bead for a retry, and closing it
#    anyway would leave the anchor held with no marker and no open child to raise
#    it — a PR stranded with no signal anywhere. An unrecorded gate keeps the
#    review open; only the close is skipped, the drain below still runs.
[ -n "${SIGNOFF_UNRECORDED:-}" ] \
  || gc bd close <work-bead> --reason "<review|research|investigation> complete"

# 4. Drain and exit.
gc runtime drain-ack
exit
```

### Fix-target dispatch (pre-publish signoff gate)

When `metadata.fix_target_pool` is set, the review is a **signoff gate** — one
member of the gating anchor's check-set (see docs/work-bead-state-machine.md).
There are two shapes, discriminated by `metadata.review_branch`:

- **POST-OPEN** (`pr_number` set): the refinery published the PR (non-draft) and
  is waiting on your verdict; the signoff holds the merge, not draft state.
- **PRE-OPEN** (`review_branch` set, no `pr_number` — the pre-open codex gate,
  tk-6d0vb.1.8): there is NO PR yet. Your signoff gates whether the PR OPENS at
  all — `pre-open-resolve.sh` opens the non-draft PR only once you stamp
  `check.codex` green at the branch head, so the PR is codex-green at birth
  (preserving #163 non-draft and #185 comment-only). Pass stamps the marker on
  the branch head; changes file a rework child against the branch (no PR yet to
  reopen).

Either way the **anchor** stays OPEN as the PR's gating bead; it closes later, on
merge, via the refinery's reconcile pass — never here. Resolve the anchor as the
bead this review gates — the dependent of the `blocks` dep the refinery attached
(`gc bd dep <review> --blocks <anchor>`):

- **COMMENT (signoff pass)** — the signoff passes on the **current** head. The
  verdict is a non-blocking COMMENT, never an APPROVE (see step 1: the city never
  approves — approval is external/human); post-open it is a `gh pr review
  --comment`, pre-open it is recorded in this bead's notes and replayed at
  PR-open. Stamp the gate green at the head you signed off as
  `check.<gate>=green@<head>` on the anchor (the gate name comes from the review
  bead's `metadata.check_name`, default `codex`). The `green@<sha>` value folds
  "this gate passed" and "title + body validated at this commit" into one: a
  later commit moves the head, so the marker no longer matches and the gate
  re-gates. Post-open the PR is already non-draft; pre-open the marker lets
  pre-open-resolve.sh open it.
  **Post-open, a pass ALSO retracts our own superseded CHANGES_REQUESTED**
  (tk-5niup). A COMMENT does not supersede the same reviewer's earlier
  CHANGES_REQUESTED, so without this the PR keeps `reviewDecision=CHANGES_REQUESTED`
  and `mergeStateStatus=BLOCKED` forever — pinned to a dead commit — while the
  bead reads green: the bead side and the GitHub side diverge and the PR can
  never land. Retraction is guarded (only after the fresh gate marker is
  confirmed recorded; our own review only, never a human's; superseded commits
  only; only while the reviewed commit is still the live head, re-checked
  immediately before each dismissal; and never while native auto-merge is armed)
  and is paired with `signoff_dismissed` on the anchor, which makes
  `merge-skill.sh` require a real external approving review **at the live head**
  — because removing a GitHub-side block is merge-triggering on a repo that does
  not require reviews. For the same reason it is skipped entirely while the
  anchor carries an operator `merge_hold`: retraction is pipeline work on a PR
  the operator has parked, and the next re-gate performs it once the hold lifts.
  If the gate marker cannot be recorded at all (the write does not read back, or
  no anchor resolves), the review bead is **not closed** — it is re-routed to its
  own pool for a retry, because a closed review over an unmarked anchor strands
  the PR with nothing left to raise the gate.
- **REQUEST_CHANGES** — file a **new rework child** against the anchor (rework
  is a new child, never the same bead reopened and never a cleared marker; see
  docs/work-bead-state-machine.md). Clear `check.<gate>` so the now-unvalidated
  head cannot be merged (pre-open: so pre-open-resolve.sh does not open a PR).

After posting the verdict via `gh pr review` (step 1 above) and BEFORE closing
the REVIEW bead (step 3 above), act on it:

```bash
# This review bead's own id, held in a variable: the signoff-gate step below has
# to write to the REVIEW bead (not just the anchor) when it cannot record the
# gate, and it names it by variable because that arm runs verbatim in the
# regression tests. Substitute your bead id for <work-bead> as everywhere else.
REVIEW_BEAD=<work-bead>
FIX_POOL=$(gc bd show "$REVIEW_BEAD" --json | jq -r '.[0].metadata.fix_target_pool // empty')
PR_NUMBER=$(gc bd show "$REVIEW_BEAD" --json | jq -r '.[0].metadata.pr_number // empty')
# WHICH REPOSITORY that number names, derived from THIS review bead's own pr_url.
#
# A PR number is meaningless on its own: every repository has a #246. Every GitHub
# call below used to leave the repository to gh — `repos/{owner}/{repo}/...` REST
# paths, and bare `gh pr view "$PR_NUMBER"` — and gh answers those from its AMBIENT
# context (the cwd's remote, or $GH_REPO). A polecat runs this in a worktree, and
# the review bead it is acting on was dispatched by a pass that may have been
# nowhere near that worktree, so "the repository gh currently thinks it is in" is
# not a fact about the PR being reviewed. This block is the post-open path that
# STAMPS the local anchor and, on a superseded round, DISMISSES a review — a repo
# drift there leaves the real PR blocked while a stranger's review is retracted
# (review tk-78ty5 finding #4).
#
# Derived from the bead, so it names the same pull request the verdict was written
# against. `PR_REPO_Q` is host-qualified (`<host>/<owner>/<repo>`, what `--repo`
# wants — a hostless pin would be filled in from $GH_HOST and name a DIFFERENT
# repository on a different host); `PR_REPO` is the hostless form the REST paths
# want. Empty means the bead names no parseable PR url, and every GitHub call below
# is skipped rather than run unpinned: an unstamped gate just re-gates next pass,
# but a dismissal in the wrong repository cannot be undone.
#
# `PR_HOST` is the third form, and it is NOT optional: `gh api` takes a REST path,
# which carries `<owner>/<repo>` and no host, so `repos/$PR_REPO/...` pins only
# HALF the identity and gh fills the other half from $GH_HOST. `<owner>/<repo>`
# names one repository PER HOST — another host's identically-named repository has
# a PR #<n>, its own reviews, and its own review ids — so a half-pinned dismissal
# is still a dismissal in a repository nobody named (review tk-5knqi finding #1).
# Every `gh api` call below carries `--hostname "$PR_HOST"` for that reason.
# >>> signoff-repo-pin
PR_URL=$(gc bd show "$REVIEW_BEAD" --json | jq -r '.[0].metadata.pr_url // empty')
PR_REPO_Q=$(printf '%s' "$PR_URL" \
  | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p')
PR_REPO="${PR_REPO_Q#*/}"
PR_HOST="${PR_REPO_Q%%/*}"
# <<< signoff-repo-pin
# Which check-set gate this review satisfies — the per-gate marker key is
# check.<CHECK_NAME>. The dispatch stamps check_name=codex; default to codex for
# an older review bead created before the field existed.
CHECK_NAME=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.check_name // "codex"')
# Pre-open discriminator (tk-6d0vb.1.8): a PRE-OPEN review carries review_branch
# (the compare-range it diffed) and NO pr_number; POST-OPEN carries pr_number.
# The arms below stamp/rework against the branch (pre-open) or the PR (post-open).
REVIEW_BRANCH=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.review_branch // empty')
REVIEW_BASE=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.review_base // "main"')

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

# ONE retry-release path, shared by BOTH strands that end with the gate unrecorded
# (the check.<gate> stamp did not stick, and no anchor resolved at all). Both owe
# the review bead the identical treatment, and both used to open-code it — which is
# how they drifted apart and how each of them ended up trusting a best-effort write.
#
# What "release" has to mean: the session running this drains moments later, so a
# review left in_progress and still ASSIGNED to it is not offered to any pool. It is
# not merely un-retried, it is INVISIBLE — the gate is owed to nobody, and the PR (or
# the pre-open branch) strands exactly as if the review had been closed, only more
# quietly. So the retry is only real once the bead is open, unassigned, and routed.
#
# Which is why every write here is READ BACK before the caller may treat the retry as
# re-offered: `gc bd update` reporting success is not proof the write is durable (the
# same reason guard 0 reads check.<gate> back rather than trusting an exit status),
# and each of these writes is `|| true`, so success and failure are indistinguishable
# downstream. One retry follows a failed read-back — a dropped write is usually
# transient — and a second failure is reported loudly with the hand-repair command,
# because at that point the gate is owed and nothing can claim it.
#
# Ordering is load-bearing and unchanged: reason first, route second, assignee LAST.
# A claim guard can roll back a batched route+release, and a bead that becomes
# claimable before it is routed can be picked up unrouted.
# SIGNOFF_RETRY_POOL is the resolved pool, exported for the callers' warnings.
# The markers let the regression test extract and exercise this exact snippet
# (assets/scripts/signoff-supersede-dismiss.test.sh).
# >>> signoff-retry-release
signoff_retry_release() {
  # $1 = signoff_retry reason (metadata), $2 = note appended to the review bead.
  local reason="$1" note="$2" attempt=0 row got_status got_assignee got_route got_pool
  local signoff_retry_live
  # WHERE the retry lands, resolved in fallback order: the DURABLE copy first.
  # review_pool is what the dispatch stamps as the pool this review belongs to
  # (mol-refinery-patrol.toml, reconcile-merged-prs.sh) and it exists for exactly
  # this read. gc.routed_to is WORKING state — a claim consumes it, a re-route
  # rewrites it — so by now it is at best spent and at worst WRONG: a stale or
  # clobbered live route names a pool that never owed this gate, and preferring it
  # would re-offer the review there and report the retry successfully re-offered
  # while the gate stays owed by nobody (tk-5niup). Reading the durable copy first
  # also REPAIRS that split: the release below writes SIGNOFF_RETRY_POOL back over
  # gc.routed_to, so a disagreeing live route is corrected rather than inherited.
  # The live route stays as a FALLBACK only — for a legacy review bead dispatched
  # before review_pool was stamped, where it is the sole record of the pool.
  # A route is not decoration: the pool offer predicate is
  # open + unassigned + gc.routed_to, so an UNROUTED review is offered to nobody.
  # Releasing without one produces a bead that looks perfectly healthy and that no
  # polecat is ever handed — the gate stays owed and the PR (or the pre-open
  # branch) sits held, which is the same silent strand this helper exists to end,
  # one step further along. So a route is REQUIRED for the retry to count as
  # re-offered; with none, the release still runs (see below) but the caller is
  # told loudly, with the repair command, rather than being handed a success.
  row=$(gc bd show "$REVIEW_BEAD" --json 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037')
  SIGNOFF_RETRY_POOL=$(printf '%s' "$row" \
    | jq -r '.[0].metadata.review_pool // empty' 2>/dev/null)
  signoff_retry_live=$(printf '%s' "$row" \
    | jq -r '.[0].metadata["gc.routed_to"] // empty' 2>/dev/null)
  [ -n "$SIGNOFF_RETRY_POOL" ] || SIGNOFF_RETRY_POOL="$signoff_retry_live"
  # Both present and DISAGREEING is a split route — the live offer points somewhere
  # the dispatch never sent this review. The durable copy wins (that is the repair),
  # but say so: a route that drifted is worth an operator's attention even though
  # the retry recovers from it.
  if [ -n "$signoff_retry_live" ] && [ -n "$SIGNOFF_RETRY_POOL" ] \
     && [ "$signoff_retry_live" != "$SIGNOFF_RETRY_POOL" ]; then
    echo "Signoff retry: review $REVIEW_BEAD has a SPLIT route (live gc.routed_to=$signoff_retry_live, durable review_pool=$SIGNOFF_RETRY_POOL); releasing to the durable pool $SIGNOFF_RETRY_POOL" >&2
  fi
  # The reason + note are written ONCE (--append-notes would duplicate the note on
  # a retry); only the route + release are re-issued, and both are idempotent.
  gc bd update "$REVIEW_BEAD" \
    --set-metadata signoff_retry="$reason" \
    --append-notes "$note" >/dev/null 2>&1 || true
  while [ "$attempt" -lt 2 ]; do
    attempt=$((attempt + 1))
    # An empty pool is never written back: it would ERASE whatever route the bead
    # still has, and an unrouted bead is exactly the invisibility being fixed.
    #
    # BOTH halves are written, the same pair the three dispatch sites stamp. Writing
    # only the live gc.routed_to is enough for THIS re-offer and strands the NEXT
    # one: on a LEGACY bead the pool was resolved from gc.routed_to precisely
    # because review_pool was never stamped, and the pool that claims this re-offer
    # CONSUMES gc.routed_to — so a second retry finds neither field and has nothing
    # to reconstruct the route from. It then releases the review open, unassigned
    # and UNROUTED: offered to nobody, gate owed forever. Persisting the durable
    # copy here is what makes the fallback survive its own success, and it upgrades
    # a legacy bead to the modern shape on first contact
    # (review tk-nwi06 finding #2).
    if [ -n "$SIGNOFF_RETRY_POOL" ]; then
      gc bd update "$REVIEW_BEAD" \
        --set-metadata gc.routed_to="$SIGNOFF_RETRY_POOL" \
        --set-metadata review_pool="$SIGNOFF_RETRY_POOL" >/dev/null 2>&1 || true
    fi
    gc bd update "$REVIEW_BEAD" --status=open --assignee="" >/dev/null 2>&1 || true
    row=$(gc bd show "$REVIEW_BEAD" --json 2>/dev/null \
      | tr -d '\000-\010\013\014\016-\037')
    got_status=$(printf '%s' "$row" | jq -r '.[0].status // empty' 2>/dev/null \
      | tr '[:upper:]' '[:lower:]')
    got_assignee=$(printf '%s' "$row" | jq -r '.[0].assignee // ""' 2>/dev/null)
    got_route=$(printf '%s' "$row" | jq -r '.[0].metadata["gc.routed_to"] // ""' 2>/dev/null)
    got_pool=$(printf '%s' "$row" | jq -r '.[0].metadata.review_pool // ""' 2>/dev/null)
    # A ROUTE is part of the success condition, not a nicety: without one the bead
    # matches no pool's offer predicate. Read the route back for real (not just
    # "matches what we tried to write") so an empty resolved pool cannot pass by
    # short-circuit — that was the strand-reported-as-success this guard removes.
    #
    # The DURABLE copy is read back on the same terms and for the same reason. The
    # live route alone proves only that THIS re-offer is claimable; the pool that
    # claims it consumes that field, so if review_pool did not also land, the next
    # retry has nothing left to resolve from. Reporting success on the live half
    # alone would hand back exactly the one-shot route this write exists to make
    # durable — a strand one cycle further along, wearing a success message.
    if [ "$got_status" = "open" ] && [ -z "$got_assignee" ] && [ -n "$got_route" ] \
       && { [ -z "$SIGNOFF_RETRY_POOL" ] \
            || { [ "$got_route" = "$SIGNOFF_RETRY_POOL" ] \
                 && [ "$got_pool" = "$SIGNOFF_RETRY_POOL" ]; }; }; then
      echo "Signoff retry re-offered: review $REVIEW_BEAD reads back open and unassigned, routed to $got_route (durable review_pool='${got_pool:-<none>}') — a pool can claim it and re-run the gate" >&2
      return 0
    fi
  done
  # Two distinct failures, and they need different repairs. No pool RESOLVED means
  # the route cannot be reconstructed from the bead at all, so name that plainly
  # and make the operator supply one — a repair command that silently omits
  # gc.routed_to would reproduce the same unclaimable bead.
  if [ -z "$SIGNOFF_RETRY_POOL" ]; then
    echo "WARN: signoff retry for review $REVIEW_BEAD has NO pool to route it to (neither gc.routed_to nor metadata.review_pool is recorded on the bead; read back status='${got_status:-unreadable}' assignee='${got_assignee:-}' route='${got_route:-}'). The claim WAS released — an in-progress bead held by this draining session is strictly worse — but open + unassigned + UNROUTED matches no pool's offer predicate, so NOBODY is ever handed this review and the signoff gate stays owed while the PR/branch sits held. Repair by hand, naming the review pool on BOTH fields (gc.routed_to is the live offer a claim CONSUMES; review_pool is the durable copy the next retry reconstructs the route from — setting only the live one rebuilds this same dead end one claim later): gc bd update $REVIEW_BEAD --status=open --assignee=\"\" --set-metadata gc.routed_to=<review-pool> --set-metadata review_pool=<review-pool>" >&2
    return 1
  fi
  echo "WARN: signoff retry for review $REVIEW_BEAD did NOT persist after $attempt attempts (read back status='${got_status:-unreadable}' assignee='${got_assignee:-}' route='${got_route:-}' review_pool='${got_pool:-}'; want open + unassigned + $SIGNOFF_RETRY_POOL on BOTH route fields). The gate is owed but the bead is either claimable by NOBODY or claimable only once — a live route with no durable review_pool cannot be restored after the next claim consumes it. Repair by hand: gc bd update $REVIEW_BEAD --status=open --assignee=\"\" --set-metadata gc.routed_to=$SIGNOFF_RETRY_POOL --set-metadata review_pool=$SIGNOFF_RETRY_POOL" >&2
  return 1
}
# <<< signoff-retry-release

if [ -n "$FIX_POOL" ]; then
  case "$VERDICT" in
    # Signoff pass. Codex posts COMMENT by design (step 1: never --approve — the
    # city does not approve PRs; approval is external/human). APPROVE is matched
    # only defensively for a legacy/stray verdict; codex never emits it. Either
    # way the pass action is identical: stamp the per-gate marker.
    COMMENT|APPROVE)
      # Record the gate green at the head the signoff validated, as the per-gate
      # marker check.<CHECK_NAME>=green@<reviewed-oid>. The merge skill merges
      # only while that marker still equals green@<live-head>; any later commit
      # makes it stale and re-gates the merge. Best-effort; a miss just defers the
      # merge to the next signoff round, it never merges prematurely.
      if [ -n "$ANCHOR" ]; then
        if [ -n "$REVIEW_BRANCH" ]; then
          # PRE-OPEN: no PR/review API to attach the reviewed commit to, so use the
          # reviewed_oid you PINNED at diff time (step 1) — NOT a re-derived live
          # head. The branch can advance between the review and this stamp (a
          # recovery polecat resuming the branch, an operator fixup); stamping the
          # live head would certify an UNREVIEWED commit as gate-green — exactly the
          # stale-head hazard the post-open arm avoids via .commit_id. If
          # reviewed_oid is absent (step 1 did not pin it), stamp NOTHING: the
          # resolver then holds until a re-review, a safe no-merge — never an
          # unreviewed merge.
          REVIEWED_OID=$(gc bd show <work-bead> --json 2>/dev/null \
            | jq -r '.[0].metadata.reviewed_oid // empty')
        else
          # POST-OPEN: stamp the EXACT commit the signoff reviewed, read from the
          # reviews API (.commit_id) — NOT the PR's live head. The head can advance
          # between the review and this stamp; stamping the live head would mark an
          # UNREVIEWED commit as gate-green and let it merge, defeating the
          # stale-head guard. GitHub attaches the review to the head at submission,
          # so .commit_id is exactly what was reviewed. Take the latest review
          # under your own handle (the one just submitted). PAGINATE explicitly:
          # GitHub pages this endpoint (30/page), and on a PR with several review
          # rounds the review you just submitted is on the LAST page — an
          # unpaginated read would silently `last` an OLDER review of yours and
          # stamp the gate green at a commit you did not just review.
          # Pinned to the bead's own HOST: an account name is host-scoped, so an
          # unpinned `gh api user` under a drifted $GH_HOST names a different
          # host's account, and the filter below would then look for reviews by a
          # handle that never wrote any.
          REVIEW_HANDLE=$(gh api --hostname "$PR_HOST" user -q .login 2>/dev/null)
          # PINNED to the bead's own repository AND host (see PR_REPO/PR_HOST
          # above). Unpinned, this reads a same-numbered PR wherever gh happens to
          # point and stamps THAT PR's head onto our anchor as gate-green.
          REVIEWED_OID=$(gh api --hostname "$PR_HOST" --paginate "repos/$PR_REPO/pulls/$PR_NUMBER/reviews?per_page=100" --jq '.[]' 2>/dev/null \
            | jq -rs --arg h "$REVIEW_HANDLE" \
                '[.[] | select(.user.login == $h)] | sort_by(.submitted_at) | last | .commit_id // empty' 2>/dev/null)
        fi
# >>> signoff-supersede-dismiss
        # Stamp the gate green — and REMEMBER whether it actually stuck. The
        # dismissal below trades a GitHub-side block away for this marker, so it
        # must run only against a marker that is really recorded. `|| true` keeps
        # a failed write non-fatal (correct: a missed stamp just re-gates), but it
        # also makes success and failure indistinguishable to everything after —
        # hence the explicit read-back rather than a bare exit status: a write can
        # report success and still not be durable.
        #
        # The extraction marker opens HERE, above the stamp, and not at the
        # dismissal below: GATE_STAMPED is guard 0 of the retraction, so a snippet
        # that started after it would import the guard as an undefined variable
        # from the harness and the regression test could never exercise the
        # check-marker write it is meant to pin.
        GATE_STAMPED=""
        if [ -n "$REVIEWED_OID" ]; then
          gc bd update "$ANCHOR" \
            --set-metadata "check.$CHECK_NAME=green@$REVIEWED_OID" >/dev/null 2>&1 || true
          READBACK=$(gc bd show "$ANCHOR" --json 2>/dev/null \
            | jq -r --arg k "check.$CHECK_NAME" '.[0].metadata[$k] // empty' 2>/dev/null)
          if [ "$READBACK" = "green@$REVIEWED_OID" ]; then
            GATE_STAMPED=1
          else
            echo "WARN: check.$CHECK_NAME did not stick on anchor $ANCHOR (read back '${READBACK:-}', want 'green@$REVIEWED_OID'); the gate will re-run — not dismissing any GitHub review on an unrecorded gate" >&2
          fi
        fi
        # An UNRECORDED gate must not be closed over. The stamp is best-effort by
        # design ("a miss just re-gates"), but that is only true while something
        # still re-runs the gate — and nothing does: the anchor keeps check_set,
        # so merge-skill.sh holds the merge (pre-open, pre-open-resolve.sh never
        # opens the PR), while check-set-heal.sh repairs an EMPTY check_set, not a
        # missing marker under a normal one. Close the review here and the anchor
        # is held forever with no open child to raise it — the PR strands with no
        # signal anywhere. So the review does NOT close: leave it OPEN, put it
        # back in its own pool, and let the next signoff round re-run it. An open
        # review child is also what HOLDS the merge post-open, so the same act
        # that keeps the retry visible keeps the PR from landing ungated.
        SIGNOFF_UNRECORDED=""
        if [ -z "$GATE_STAMPED" ]; then
          SIGNOFF_UNRECORDED=1
          # The shared retry-release helper (reason, route, release — each read
          # back). Its return value is deliberately not fatal: a failed release is
          # already reported with the hand-repair command, and the close is skipped
          # either way, so there is nothing further this step can do about it.
          signoff_retry_release \
            "check.$CHECK_NAME unrecorded on anchor ${ANCHOR:-unresolved}" \
            "Signoff NOT recorded: check.$CHECK_NAME did not stick on anchor ${ANCHOR:-unresolved} (reviewed $REVIEWED_OID). Review left OPEN for a retry — closing it would strand the anchor with no gate marker and no open child." || true
          # "re-routed" is claimed ONLY when a pool actually resolved — with none,
          # the helper has already warned that the bead is unroutable and printed
          # the repair command, and repeating "re-routed" here would talk over it.
          echo "WARN: signoff gate check.$CHECK_NAME is NOT recorded on anchor ${ANCHOR:-unresolved}; review $REVIEW_BEAD left OPEN${SIGNOFF_RETRY_POOL:+ and re-routed to $SIGNOFF_RETRY_POOL} for a retry — do NOT close it (an unmarked anchor with no open review child strands the PR)" >&2
        fi
        # Reconcile the GitHub side with the bead side, in the SAME step that
        # stamped green (tk-5niup). A COMMENT review does NOT supersede the same
        # reviewer's earlier CHANGES_REQUESTED, so a PR that took a changes round
        # keeps reviewDecision=CHANGES_REQUESTED and mergeStateStatus=BLOCKED
        # forever — pinned to a commit that no longer exists — while check.<gate>
        # reads green on the bead. merge-skill.sh requires CLEAN, so the PR can
        # never land no matter how many green re-gates run. That divergence
        # between "green on the bead" and "red on GitHub" IS the bug; retracting
        # our own superseded review is what closes it. Eight guards, all required:
        #   0. The gate marker actually STUCK (GATE_STAMPED, read back above).
        #      The whole trade is "give up a GitHub-side block, keep a recorded
        #      approval requirement" — with no marker recorded there is nothing on
        #      the other side of the trade, and dismissing would drop the block AND
        #      the requirement at once. The stamp is best-effort by design, so this
        #      cannot be assumed; it must be checked.
        #   1. POST-OPEN only — pre-open has no PR and no reviews to retract.
        #   2. Only reviews authored by the account we just signed off as. NEVER
        #      a human's: an operator's CHANGES_REQUESTED is a real veto, and
        #      dismissing it would erase their block. Operator changes-requests
        #      DO occur on this rig's PRs, so this guard is load-bearing, not
        #      theoretical — filter on the author, never on "is it stale".
        #   3. Only reviews pinned to a commit OTHER than the one we reviewed —
        #      those, and only those, are superseded. A CHANGES_REQUESTED at the
        #      reviewed commit means we both blocked and passed the same head:
        #      contradictory, so retract nothing and let the block stand.
        #   4. Only while the commit we reviewed is still the LIVE head. If the
        #      head moved after the signoff, the block must stay — removing it
        #      would unblock an UNREVIEWED commit.
        #   5. Only while native auto-merge is DEFINITELY not armed. Armed, the
        #      dismissal merges the PR server-side on the spot, before
        #      merge-skill.sh can apply the approval requirement recorded here —
        #      the requirement binds our own skill, never GitHub. A probe that
        #      cannot be READ counts as armed: an API or parse failure is
        #      indistinguishable from a genuine "off", so only a definite
        #      "disarmed" clears this guard.
        #   6. Re-read the live head immediately before EACH dismissal, not just
        #      once before the listing. Between the two, the head can move and a
        #      FRESH block can be posted on the new head; against a stale
        #      REVIEWED_OID guard 3 reads it as superseded and retracts a live veto.
        #      Guard 5 is re-probed in the same place and for the same reason:
        #      auto-merge can be armed inside that window too.
        #   7. Only while the ANCHOR IS STILL WHAT THIS ARM DECIDED ABOUT: open,
        #      not under an operator merge_hold, parked on a published PR
        #      (merge_result=pull_request), claiming THIS pr_number, and green at
        #      the reviewed head (check.<gate>=green@REVIEWED_OID). A retraction is
        #      pipeline work on a PR an operator may have deliberately parked, and
        #      it is merge-TRIGGERING work at that: dropping the last GitHub-side
        #      block is exactly what a hold says not to do — and equally wrong
        #      once the anchor has closed, un-parked, moved to another PR, or had
        #      its gate cleared by a re-gate, because then the block would come
        #      off a PR this anchor no longer gates as validated.
        #      reconcile-merged-prs.sh requires that whole set before its own
        #      retraction; this step runs in the same anchor state and must make
        #      the same call. Held is not a failure — the next re-gate reads the
        #      anchor again and retracts once it is releasable. RE-READ immediately
        #      before each dismissal, exactly like guards 5 and 6: the up-front
        #      read is a snapshot, and all five facts can change inside the window
        #      it leaves open. An UNREADABLE anchor counts as held, for the same
        #      reason an unreadable auto-merge probe counts as armed — it cannot
        #      prove the PR is free to move.
        # Dismissal removes a GitHub-side merge block, so it is MERGE-TRIGGERING
        # on a repo with no review requirement (there, CLEAN folds nothing and
        # the stale review may be the only hold). It is therefore paired with
        # signoff_dismissed on the anchor, which makes merge-skill.sh demand a
        # real EXTERNAL approving review before landing this PR. Stamp that
        # marker FIRST, READ IT BACK, and dismiss only if it really stuck (and
        # never at all while the anchor is under an operator merge_hold). KEEP THE
        # GUARD SEQUENCE IN SYNC with the observer's superseded-review arm
        # (assets/scripts/reconcile-merged-prs.sh): it retracts the same block from
        # the other end — this step at re-gate time, that one as the convergence
        # backstop — so a guard added or tightened in either belongs in both.
        # Marker-then-dismiss can only over-hold (requirement recorded, block
        # still up), while dismiss-then-marker loses BOTH the block and the
        # requirement if the write fails. The read-back is what makes "if it
        # stuck" mean anything — a `gc bd update` can report success and still
        # not be durable, exactly as for the check.<gate> stamp above, and an
        # exit status cannot tell the two apart. The marker's value is
        # provenance for the most recent
        # retraction; the gate triggers on its PRESENCE, and stays sticky because
        # a dismissal is permanent — a later head re-gates the markers but never
        # restores the review we dismissed.
        # The markers below let the regression test extract and exercise this
        # exact snippet (assets/scripts/signoff-supersede-dismiss.test.sh).
        # Guard 7: the operator's merge_hold on the anchor. Read it only on the
        # post-open path (pre-open retracts nothing, so the extra bead read would
        # be pure noise). Truthiness matches merge-skill.sh's own reading of the
        # field: set and not empty/false/0 holds; unset or explicitly-false does
        # not, so a stale `merge_hold=false` never freezes the re-gate.
        ANCHOR_HOLD=""
        if [ -z "$REVIEW_BRANCH" ] && [ -n "$PR_NUMBER" ]; then
          ANCHOR_HOLD=$(gc bd show "$ANCHOR" --json 2>/dev/null \
            | jq -r '.[0].metadata.merge_hold // empty' 2>/dev/null)
          case "$ANCHOR_HOLD" in ""|false|False|FALSE|0|null) ANCHOR_HOLD="" ;; esac
          [ -z "$ANCHOR_HOLD" ] || echo "WARN: anchor $ANCHOR carries merge_hold=$ANCHOR_HOLD (operator gate); NOT dismissing any superseded review on PR#$PR_NUMBER while held — retraction is merge-triggering pipeline work, and the next re-gate retracts once the hold is released" >&2
        fi
        # $PR_REPO_Q is a REQUIRED condition, not a nicety: this arm ends in an
        # irreversible dismissal, and without a repository derived from the bead
        # every call below would be resolved by gh's ambient context. Refusing here
        # costs one re-gate; guessing costs a review retracted on a stranger's PR
        # while ours stays blocked (review tk-78ty5 finding #4).
        if [ -z "$REVIEW_BRANCH" ] && [ -n "$PR_NUMBER" ] && [ -z "$PR_REPO_Q" ]; then
          echo "WARN: review bead $REVIEW_BEAD records no parseable pr_url, so PR#$PR_NUMBER cannot be pinned to a repository; NOT reading or dismissing any review (an unpinned dismissal can retract a review on another repository's same-numbered PR). Repair metadata.pr_url and re-run." >&2
        fi
        if [ -z "$REVIEW_BRANCH" ] && [ -n "$PR_NUMBER" ] && [ -n "$REVIEWED_OID" ] \
           && [ -n "$GATE_STAMPED" ] && [ -z "$ANCHOR_HOLD" ] && [ -n "$PR_REPO_Q" ]; then
          [ -n "${REVIEW_HANDLE:-}" ] || REVIEW_HANDLE=$(gh api --hostname "$PR_HOST" user -q .login 2>/dev/null)
          LIVE_HEAD=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" --json headRefOid -q .headRefOid 2>/dev/null)
          # Guard 5: native auto-merge. If `gh pr merge --auto` is armed on this
          # PR, dropping the last block does not merely ALLOW the merge — GitHub
          # performs it immediately, server-side, before merge-skill.sh ever reads
          # signoff_dismissed. The approval requirement below is enforced only by
          # our own skill, so it cannot hold a server-side merge. Fail closed:
          # leave the review standing and let a human disarm auto-merge or approve.
          #
          # The probe answers THREE ways — armed / disarmed / unknown — and only a
          # definite "disarmed" clears the guard. A bare
          # `gh pr view --json autoMergeRequest | jq -r '.autoMergeRequest // empty'`
          # collapses an API error, an auth failure, a rate-limit, and a jq parse
          # error into the SAME empty string a genuinely disarmed PR produces, so a
          # probe that FAILED reads as proof that auto-merge is off — fail-OPEN on
          # the one field whose entire job is to stop a server-side merge. Demand a
          # parseable object that actually CARRIES the key; anything else is unknown,
          # and unknown is treated as armed.
          automerge_state() {
            local raw
            raw=$(gh pr view "$1" --repo "$PR_REPO_Q" --json autoMergeRequest 2>/dev/null) \
              || { printf 'unknown\n'; return; }
            printf '%s' "$raw" \
              | jq -e 'type == "object" and has("autoMergeRequest")' >/dev/null 2>&1 \
              || { printf 'unknown\n'; return; }
            if printf '%s' "$raw" | jq -e '.autoMergeRequest != null' >/dev/null 2>&1; then
              printf 'armed\n'
            else
              printf 'disarmed\n'
            fi
          }
          AUTO_MERGE=$(automerge_state "$PR_NUMBER")
          case "$AUTO_MERGE" in
            disarmed) ;;
            armed)
              echo "WARN: PR#$PR_NUMBER has native auto-merge ARMED; NOT dismissing the superseded review (it would trigger an immediate server-side merge past the approval requirement). Disarm with 'gh pr merge --disable-auto $PR_NUMBER' or land it deliberately." >&2
              REVIEW_HANDLE="" ;;
            *)
              echo "WARN: PR#$PR_NUMBER native auto-merge state is UNREADABLE (the autoMergeRequest probe failed or returned a malformed payload); NOT dismissing the superseded review. An unreadable probe cannot prove auto-merge is off, and a wrong guess here merges server-side past the approval requirement — so it counts as armed. Re-run once 'gh pr view $PR_NUMBER --json autoMergeRequest' answers." >&2
              REVIEW_HANDLE="" ;;
          esac
          if [ -n "$REVIEW_HANDLE" ] && [ -n "$LIVE_HEAD" ] && [ "$LIVE_HEAD" = "$REVIEWED_OID" ]; then
            # PAGINATE: GitHub pages this endpoint (30/page). A PR that took a
            # changes round — the only kind this arm fires on — is exactly the PR
            # whose reviews spill past page one, so an unpaginated read would miss
            # the very review it must retract and leave the PR stranded.
            # FETCH and REDUCE are SEPARATE steps, each with its own status check —
            # the same split merge-skill.sh makes for reviews_raw/reviews_rc. Fused
            # into one assignment tested only for emptiness, a read that fails PART
            # WAY THROUGH is indistinguishable from a complete one: `gh --paginate`
            # streams the pages it did get, jq reduces them without complaint, and
            # the result is a well-formed answer computed from a TRUNCATED history
            # that this step then dismisses from as though it had seen all of it.
            # The same silence covers a read that fails OUTRIGHT — an expired
            # token, a rate limit — which renders as "no superseded review to
            # retract" and strands the PR permanently and invisibly, since nothing
            # distinguishes it from a PR with nothing to retract. ANY failure skips
            # the retraction and says so: the gate marker is already stamped, so the
            # next re-gate reads a settled history and retracts then.
            REVIEWS_RAW=$(gh api --hostname "$PR_HOST" --paginate "repos/$PR_REPO/pulls/$PR_NUMBER/reviews?per_page=100" \
              --jq '.[]' 2>/dev/null); REVIEWS_RC=$?
            STALE_REVIEWS=""
            if [ "$REVIEWS_RC" -ne 0 ]; then
              echo "WARN: PR#$PR_NUMBER reviews history read FAILED (gh rc=$REVIEWS_RC); NOT dismissing any superseded review — a partial page set cannot be told apart from a complete one and the dismissal is irreversible. The gate is stamped; the next re-gate retries." >&2
            else
              STALE_REVIEWS=$(printf '%s' "$REVIEWS_RAW" \
                | jq -r --arg h "$REVIEW_HANDLE" --arg oid "$REVIEWED_OID" \
                    'select((.user.login // "") == $h)
                     | select(.state == "CHANGES_REQUESTED")
                     | select((.commit_id // "") != $oid) | .id' 2>/dev/null); REDUCE_RC=$?
              if [ "$REDUCE_RC" -ne 0 ]; then
                echo "WARN: PR#$PR_NUMBER reviews history is UNREADABLE (reduce rc=$REDUCE_RC); NOT dismissing any superseded review" >&2
                STALE_REVIEWS=""
              fi
            fi
            while IFS= read -r RID; do
              [ -n "$RID" ] || continue
              # Re-read the live head immediately before the irreversible call.
              # The listing is a snapshot; if the head moved since, a review in it
              # may be a FRESH block on the NEW head rather than a superseded one,
              # and the commit_id filter cannot tell them apart once REVIEWED_OID
              # is stale. Abandon the retraction — a later re-gate re-reads.
              # ONE read, four fields: the head this guard has always compared, and
              # the base/branch/url the anchor's identity is checked against below.
              # Folding them into the existing round trip keeps the added guard
              # free, and — more importantly — makes every comparison speak about
              # the SAME observation of the PR.
              NOW_PR=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" \
                --json headRefOid,baseRefName,headRefName,url 2>/dev/null)
              NOW_HEAD=$(printf '%s' "$NOW_PR" | jq -r '.headRefOid // ""' 2>/dev/null)
              NOW_BASE=$(printf '%s' "$NOW_PR" | jq -r '.baseRefName // ""' 2>/dev/null)
              NOW_REF=$(printf '%s' "$NOW_PR" | jq -r '.headRefName // ""' 2>/dev/null)
              NOW_URL=$(printf '%s' "$NOW_PR" | jq -r '.url // ""' 2>/dev/null)
              if [ "$NOW_HEAD" != "$REVIEWED_OID" ]; then
                echo "WARN: PR#$PR_NUMBER head moved ($REVIEWED_OID -> ${NOW_HEAD:-unknown}) mid-step; NOT dismissing review $RID (it may block the new head)" >&2
                break
              fi
              # Guard 5 again, per dismissal and AFTER the head re-read: the
              # up-front probe is a snapshot too. An operator can arm auto-merge in
              # the window between it and this irreversible PUT — and then the
              # dismissal merges the PR server-side. Same three-valued reading;
              # break rather than continue, since the state is PR-wide, so if it is
              # unsafe for this review it is unsafe for every later one.
              AM_NOW=$(automerge_state "$PR_NUMBER")
              if [ "$AM_NOW" != "disarmed" ]; then
                echo "WARN: PR#$PR_NUMBER native auto-merge state is '$AM_NOW' immediately before dismissing review $RID; NOT dismissing (an armed — or unreadable, hence assumed armed — auto-merge merges server-side past the approval requirement)" >&2
                break
              fi
              # Guard 7 again, per dismissal, in the same place and for the same
              # reason as guards 5 and 6 — but over the anchor's FULL identity,
              # not merge_hold alone. Every bead-side fact this arm is acting on
              # was read BEFORE the reviews listing: ANCHOR_HOLD once, up front,
              # and the gate marker at stamp time. Inside that window the anchor
              # can change in four more ways, each of which makes the retraction
              # wrong and none of which a merge_hold re-read can see:
              #   - it CLOSES (it no longer gates anything),
              #   - it UN-PARKS from merge_result=pull_request (it no longer
              #     speaks for a published PR),
              #   - its pr_number moves to a DIFFERENT PR (the block we are about
              #     to remove is on a PR this anchor no longer claims),
              #   - check.<gate> is cleared or moved off the reviewed head by a
              #     re-gate (the head is no longer validated at all).
              # In every one of them this step would still drop the last
              # GitHub-side block on a PR nothing else is holding — the single
              # most merge-triggering thing it can do. The observer's retraction
              # arm (assets/scripts/reconcile-merged-prs.sh) already requires the
              # full set before its dismissal; the two arms retract the SAME block
              # from opposite ends, so a guard in one belongs in the other.
              #
              # Fail-closed on an unreadable read, exactly like the auto-merge
              # probe: `select(...)` (not `// {}`) keeps a missing row or missing
              # metadata EMPTY rather than rendering it as an all-default anchor
              # that would satisfy every condition below. Break rather than
              # continue: every condition here is anchor- or PR-wide, so what
              # stops this review stops every later one on the same PR.
              # The PR number comes from EVERY key a bead names a PR with, not
              # `pr_number` alone — the same `pr_nums_here` rule merge-skill.sh and
              # reconcile-merged-prs.sh resolve an anchor's own identity by. An
              # anchor keyed only by `fork_pr`/`fork_pr_url` (the fork-sync shape,
              # which stamps no pr_number at all) reads as pr='' under the narrow
              # rule, which this guard cannot tell apart from "the anchor moved off
              # this PR" — so the retraction never runs and the PR stays blocked on
              # a dead commit forever, which is the exact strand this whole step
              # exists to clear (review tk-5knqi finding #2). EXACTLY ONE number or
              # nothing: several do not answer which PR the anchor gates, and an
              # ambiguous anchor must hold rather than have one picked for it. A
              # `fork_pr_url` naming ANOTHER repository is dropped ($repo is this
              # PR's own, from the bead's pr_url); a bare number names no
              # repository and is kept, the same fail-closed wildcard the scripts
              # use.
              ANCHOR_NOW=$(gc bd show "$ANCHOR" --json 2>/dev/null \
                | tr -d '\000-\010\013\014\016-\037' \
                | jq -c --arg gate "check.$CHECK_NAME" --arg repo "$PR_REPO_Q" '
                     def pr_nums_here($o):
                       ( [ (.metadata.pr_number // empty), (.metadata.fork_pr // empty) ] | map(tostring) )
                       + ( ((.metadata.fork_pr_url // "") | tostring)
                           | [ capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<r>[^/]+/[^/]+)/pull/(?<n>[0-9]+)") ]
                           | .[0]
                           | if . == null then []
                             elif ($o == "" or (.h + "/" + .r) == $o) then [ .n ]
                             else [] end )
                       | map(select(test("^[0-9]+$"))) | unique;
                     .[0] | select(. != null) | select(.metadata != null)
                     | (pr_nums_here($repo)) as $ns
                     | {status: ((.status // "") | ascii_downcase),
                        hold: ((.metadata.merge_hold // "") | tostring),
                        result: (.metadata.merge_result // ""),
                        pr: (if ($ns | length) == 1 then $ns[0] else "" end),
                        target: (.metadata.merged_target // ""),
                        prurl: (.metadata.pr_url // ""),
                        branch: (.metadata.branch // ""),
                        mark: (.metadata[$gate] // "")}' 2>/dev/null)
              if [ -z "$ANCHOR_NOW" ]; then
                echo "WARN: anchor $ANCHOR metadata is UNREADABLE immediately before dismissing review $RID; NOT dismissing (an unreadable anchor cannot prove it is still open, unheld, parked on PR#$PR_NUMBER and green at the reviewed head, and a wrong guess drops the last block on a PR nothing else holds)" >&2
                break
              fi
              A_STATUS=$(printf '%s' "$ANCHOR_NOW" | jq -r '.status' 2>/dev/null)
              HOLD_NOW=$(printf '%s' "$ANCHOR_NOW" | jq -r '.hold' 2>/dev/null)
              A_RESULT=$(printf '%s' "$ANCHOR_NOW" | jq -r '.result' 2>/dev/null)
              A_PR=$(printf '%s' "$ANCHOR_NOW" | jq -r '.pr' 2>/dev/null)
              A_MARK=$(printf '%s' "$ANCHOR_NOW" | jq -r '.mark' 2>/dev/null)
              A_TARGET=$(printf '%s' "$ANCHOR_NOW" | jq -r '.target' 2>/dev/null)
              A_PRURL=$(printf '%s' "$ANCHOR_NOW" | jq -r '.prurl' 2>/dev/null)
              A_BRANCH=$(printf '%s' "$ANCHOR_NOW" | jq -r '.branch' 2>/dev/null)
              # Truthiness matches merge-skill.sh's reading of merge_hold: set and
              # not empty/false/0 holds, so a stale `merge_hold=false` never
              # freezes the re-gate.
              A_HELD=""
              case "$HOLD_NOW" in
                ""|false|False|FALSE|0|null) : ;;
                *) A_HELD=1 ;;
              esac
              if [ -n "$A_HELD" ]; then
                echo "WARN: anchor $ANCHOR carries merge_hold=$HOLD_NOW (operator gate) immediately before dismissing review $RID; NOT dismissing — the hold was set after this step's up-front check, and retraction is merge-triggering pipeline work. The next re-gate retracts once the hold is released." >&2
                break
              fi
              if [ "$A_STATUS" != "open" ] || [ "$A_RESULT" != "pull_request" ] \
                 || [ "$A_PR" != "$PR_NUMBER" ] || [ "$A_MARK" != "green@$REVIEWED_OID" ]; then
                echo "WARN: anchor $ANCHOR changed mid-step (status='$A_STATUS' merge_result='$A_RESULT' pr_number='$A_PR' check.$CHECK_NAME='$A_MARK'; want open + pull_request + PR#$PR_NUMBER + green@$REVIEWED_OID); NOT dismissing review $RID — the block would come off a PR this anchor no longer gates as validated" >&2
                break
              fi
              # The rest of the anchor's identity, compared against the LIVE PR
              # read above rather than against anything read earlier in this step.
              # merged_target, pr_url and branch authorize the dismissal as
              # directly as the gate marker does, and NONE of them moves the head —
              # so the head re-read cannot catch a mid-step retarget, an identity
              # repair (check-set-heal backfilling a certified pr_url), or a
              # corrected branch. A field the anchor does not record is governed by
              # the pinned read alone; only a value that DISAGREES is a mismatch.
              A_REASON=""
              if [ -n "$A_TARGET" ] && [ -n "$NOW_BASE" ] && [ "$A_TARGET" != "$NOW_BASE" ]; then
                A_REASON="anchor was retargeted mid-step (merged_target='$A_TARGET', PR base '$NOW_BASE')"
              elif [ -n "$A_PRURL" ] && [ -n "$NOW_URL" ] \
                   && [ "$(printf '%s' "$A_PRURL" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##')" \
                        != "$(printf '%s' "$NOW_URL" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##')" ]; then
                A_REASON="anchor now records pr_url '$A_PRURL', which is not the PR#$PR_NUMBER just read ('$NOW_URL')"
              elif [ -n "$A_BRANCH" ] && [ -n "$NOW_REF" ] && [ "$A_BRANCH" != "$NOW_REF" ]; then
                A_REASON="anchor now records branch '$A_BRANCH' but PR#$PR_NUMBER is opened from '$NOW_REF'"
              fi
              if [ -n "$A_REASON" ]; then
                echo "WARN: $A_REASON; NOT dismissing review $RID — the bead and the PR no longer describe the same work" >&2
                break
              fi
              # Record the pairing marker, then READ IT BACK before trading the
              # GitHub block away for it. `gc bd update` reporting success is not
              # proof the write is durable — the same reason guard 0 reads
              # check.<gate> back instead of trusting its exit status — and this
              # marker is the ONLY thing standing in for the block about to be
              # removed: merge-skill.sh demands a real external approving review
              # because signoff_dismissed is PRESENT. Dismiss on an unverified
              # write and both the block and the requirement are gone at once,
              # which is the one combination that can land unreviewed work.
              gc bd update "$ANCHOR" \
                --set-metadata signoff_dismissed="$RID@$REVIEWED_OID" >/dev/null 2>&1 || true
              PAIRED=$(gc bd show "$ANCHOR" --json 2>/dev/null \
                | jq -r '.[0].metadata.signoff_dismissed // empty' 2>/dev/null)
              if [ "$PAIRED" = "$RID@$REVIEWED_OID" ]; then
                gh api --hostname "$PR_HOST" -X PUT "repos/$PR_REPO/pulls/$PR_NUMBER/reviews/$RID/dismissals" \
                  -f message="Superseded by the re-gate at $REVIEWED_OID: the findings this review raised were addressed and the $CHECK_NAME gate is green at the live head. Approval remains external." \
                  -f event=DISMISS >/dev/null 2>&1 \
                  || echo "WARN: could not dismiss superseded review $RID on PR#$PR_NUMBER; PR stays blocked, retry next re-gate" >&2
              else
                echo "WARN: signoff_dismissed did not stick on anchor $ANCHOR (read back '${PAIRED:-}', want '$RID@$REVIEWED_OID'); NOT dismissing review $RID (dismissing without a durable marker would drop the approval requirement)" >&2
              fi
            done <<< "$STALE_REVIEWS"
          fi
        fi
# <<< signoff-supersede-dismiss
      else
# >>> signoff-no-anchor-retry
        # No anchor resolved: neither the blocks edge nor metadata.anchor_bead
        # answered, so there is nowhere to record the gate — the same strand as an
        # unrecorded stamp, and it must be handled the same way. Keep the review
        # OPEN so the gate is still owed to someone, and say so loudly.
        #
        # "Left OPEN" is not enough on its own, and this arm mirrors the
        # unrecorded-stamp retry above for the same reason: skipping the close
        # leaves the bead in_progress and still ASSIGNED to this session, which
        # drains immediately after. An in-progress bead held by a dead session is
        # not offered to any pool — nothing re-runs the gate and the branch/PR
        # strands exactly as if the review had been closed, only more quietly.
        # So run the full release through the SAME helper the unrecorded-stamp arm
        # uses (reason first, route second, assignee LAST — a claim guard can roll
        # back a batched route+release, and a bead that becomes claimable before it
        # is routed can be picked up unrouted — with every write read back).
        SIGNOFF_UNRECORDED=1
        signoff_retry_release \
          "no anchor resolved for check.$CHECK_NAME" \
          "Signoff NOT recorded: no gating anchor resolved (no blocks edge, no metadata.anchor_bead). Review left OPEN and re-routed for a retry — link the anchor and re-run the gate." || true
        # As above: only claim "re-routed" when a pool actually resolved.
        echo "WARN: no gating anchor resolved for review $REVIEW_BEAD; the $CHECK_NAME gate could not be recorded anywhere — review left OPEN${SIGNOFF_RETRY_POOL:+ and re-routed to $SIGNOFF_RETRY_POOL} for a retry (do NOT close it) and the PR/branch stays ungated until an anchor is linked" >&2
# <<< signoff-no-anchor-retry
      fi
      # POST-OPEN the PR is already non-draft; PRE-OPEN the stamp lets
      # pre-open-resolve.sh open the (codex-green) PR. Either way the check.<gate>
      # marker is the only action: the merge skill merges the PR once every
      # check-set gate is green at the still-live head.
      ;;
    REQUEST_CHANGES)
      # Rework is a NEW child of the anchor, not the same anchor reopened and not
      # a flag toggled back on it. The child resumes the SAME branch via the
      # rejection-resume flow (never a fresh one). Linking it parent-child to the
      # anchor keeps the dep graph honest and — because the anchor cannot complete
      # while a child is open — holds the merge (post-open) or the PR-open
      # (pre-open) until the rework lands. The anchor's merge_result marker is LEFT
      # INTACT; the PR (or the pre_open_gate) still exists, so the anchor's state
      # must keep saying so. See docs/work-bead-state-machine.md.
      if [ -n "$REVIEW_BRANCH" ]; then
        # PRE-OPEN: no PR yet. The child resumes the BRANCH; NO existing_pr /
        # pr_number. When it hands back, the refinery re-dispatches codex on the
        # (new) branch head via the pre-open path — the PR still never opens until
        # codex is green. review_base is the intended landing target.
        FIX_BEAD=$(gc bd create "Rework branch $REVIEW_BRANCH: address pre-open signoff findings" -t task --json | jq -r .id)
        gc bd update "$FIX_BEAD" \
          --set-metadata branch="$REVIEW_BRANCH" \
          --set-metadata target="$REVIEW_BASE" \
          --set-metadata rejection_reason="pre-open signoff requested changes on branch $REVIEW_BRANCH; see review bead notes for findings" \
          --set-metadata source_review_bead=<work-bead> \
          --set-metadata merge_strategy=mr \
          --set-metadata gc.routed_to="$FIX_POOL"
      else
        # POST-OPEN: the PR exists. The child resumes the EXISTING PR branch and
        # carries existing_pr so the fix reworks the SAME PR (never a fresh one).
        # PINNED like every other call here: these three reads decide the branch a
        # polecat will CHECK OUT and force-push, so reading them from a drifted
        # repository dispatches rework onto a stranger's branch name.
        PR_HEAD=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" --json headRefName -q .headRefName)
        PR_BASE=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" --json baseRefName -q .baseRefName)
        PR_URL_FOR_FIX=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" --json url -q .url)
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
      fi
      # Attach as a child of the anchor (visibility + completion interlock).
      # Best-effort: a failed edge must not strand the rework, so warn only.
      if [ -n "$ANCHOR" ]; then
        gc bd dep add "$FIX_BEAD" "$ANCHOR" --type=parent-child \
          || echo "WARN: could not link rework $FIX_BEAD under anchor $ANCHOR" >&2
        # The head is no longer gate-validated — clear the gate marker to re-gate
        # (pre-open: so pre-open-resolve.sh will not open a PR on unreviewed work).
        gc bd update "$ANCHOR" --unset-metadata "check.$CHECK_NAME" >/dev/null 2>&1 || true
      else
        echo "WARN: no gating anchor resolved for review <work-bead>; rework $FIX_BEAD filed unlinked" >&2
      fi
      gc session wake "$FIX_POOL" || true
      ;;
  esac
fi
```

`$VERDICT` is the verdict you decided: post-open you submitted it via `gh pr
review`; pre-open (no PR yet) you recorded it in the review bead notes and set
`$VERDICT` yourself. Codex emits only `COMMENT` (the signoff pass — a non-blocking
comment, **never** `APPROVE`; the city does not approve PRs, approval is
external/human) or `REQUEST_CHANGES` (rework needed). `COMMENT` is non-blocking:
the merge is held by the recorded `check.<gate>=green@<head>` marker plus external
approval — not by a GitHub approval from the bot. Pre-open, that same marker is
also what lets `pre-open-resolve.sh` open the PR (codex-green at birth).

After this step, close the review bead as in the existing flow
(step 3 of the Non-impl done sequence above) — unless the pass arm set
`SIGNOFF_UNRECORDED`, which means the gate marker could not be recorded on the
anchor. Then the review bead stays OPEN and re-routed for a retry: skip the
close, drain, and let the next signoff round re-run the gate.
{{ end }}
