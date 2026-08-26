#!/usr/bin/env bash
# pr-facts — arm 4 of the merge cadence: record EXTERNAL facts about each open
# pull_request anchor. No merge authority. Same enumeration and pinned identity
# read as merge.sh; per anchor, in order: PR MERGED (out-of-band, or a record
# that died after merge.sh landed it) -> lifecycle transition to merged;
# CLOSED-unmerged -> abandoned + escalate.sh visit; base moved -> retargeted +
# escalate (gate markers cleared: a review of the pre-retarget diff proves
# nothing about the new base); CONFLICTING -> classify the head branch
# (allowlist: only polecat/* may be rewritten, and never a graduation) and file
# ONE rework child per head to the fix pool, stamped prepare_mode and routed only
# once that stamp reads back (dedup: a rework child naming this branch whose
# rejection_reason names this head; an unstamped orphan is adopted by title,
# never twinned); a gate green@ or exception@ a STALE head -> file one
# re-review child per head to the review pool, carrying mol-review via gc
# sling --on (dedup: a live review naming the anchor, or one with
# review_branch=branch and reviewed_oid=<live head>; same orphan adoption),
# stamped with fix_target_pool for the rework path; dismissal of our OWN
# superseded CHANGES_REQUESTED (never a human's; signoff_dismissed read back
# FIRST; skipped under native auto-merge). A merged record never carries an
# empty merged_sha — an unreadable mergeCommit records
# merged_sha=unverified:PR#<n>, loudly.
# Args: --fix-pool <pool> --review-pool <pool>. Caller: refinery-reconcile.sh
# (BEADS_ACTOR projected to the refinery identity). Fail-closed on identity.
set -u

PROG="pr-facts"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LIFECYCLE="$SCRIPTS_DIR/lifecycle.sh"
ESCALATE="$SCRIPTS_DIR/escalate.sh"
BODY_EMITTER="$SCRIPTS_DIR/review-dispatch-body.sh"

FIX_POOL=""; REVIEW_POOL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix-pool)    FIX_POOL="${2:-}"; shift 2 ;;
    --review-pool) REVIEW_POOL="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

command -v gh >/dev/null 2>&1 || exit 0

ORIGIN_HOST=""; ORIGIN_REPO=""; ORIGIN_REPO_Q=""
u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
if [ -z "$ORIGIN_REPO" ]; then
  echo "$PROG: cannot resolve this checkout's origin repository; recording NOTHING this pass" >&2
  exit 0
fi
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"
gh_api_origin() { gh api --hostname "$ORIGIN_HOST" "$@"; }
SELF_LOGIN=$(gh_api_origin user --jq '.login' 2>/dev/null)

url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}
canon_pr_url() {
  printf '%s' "${1:-}" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##'
}
is_held() { case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac; }

# A check_set as one gate per line. Deleting only [:blank:] is load-bearing:
# [:space:] would take the newlines the comma-split just made and fuse
# "codex,triage" into one gate name nothing declares — every marker lookup
# below would then miss, silently.
gate_tokens() { printf '%s' "${1:-}" | tr ',' '\n' | tr -d '[:blank:]' | sed '/^$/d'; }

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
ALL_STATUSES="$LIVE_STATUSES,closed"

bd_list() { # guarded array read; non-zero = "could not tell"
  local raw rc
  raw=$(gc bd list "$@" --limit=0 --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
escalate() { # <subject> <key> <message> — best-effort; escalate.sh dedups per subject+key
  [ -x "$ESCALATE" ] || return 0
  "$ESCALATE" --subject "$1" --key "$2" --message "$3" >/dev/null 2>&1 || true
}

ANCHORS=$(bd_list --status=open --metadata-field merge_result=pull_request) || {
  echo "$PROG: could not enumerate gating anchors; failing loudly rather than reporting a false all-clear" >&2
  exit 1
}
[ "$ANCHORS" != "[]" ] || { echo "$PROG: no gating anchors"; exit 0; }

recorded=0; flagged=0; reworked=0; regated=0; dismissed_n=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '(.metadata.pr_number // "") | tostring')
  [ -n "$id" ] || continue
  case "$num" in ''|*[!0-9]*) skipped=$((skipped + 1)); continue ;; esac
  branch=$(printf '%s' "$row" | jq -r '.metadata.branch // ""')
  target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // ""')
  prurl=$(printf '%s' "$row" | jq -r '.metadata.pr_url // ""')
  checkset=$(printf '%s' "$row" | jq -r '.metadata.check_set // ""')
  hold=$(printf '%s' "$row" | jq -r '.metadata.merge_hold // ""')
  rhold=$(printf '%s' "$row" | jq -r '.metadata.rebase_hold // ""')
  # A graduation is the integration-to-main case whatever its branch is named, so
  # the CONFLICTING arm classifies on this as well as on the branch.
  grad=$(printf '%s' "$row" | jq -r '.metadata.graduation // ""')

  # --- pinned identity read (same shape as merge.sh) ----------------------------
  PR_JSON=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" \
    --json state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,reviewDecision,url 2>/dev/null)
  if [ -z "$PR_JSON" ]; then
    echo "$PROG: PR#$num view failed; NOTHING recorded for $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
  is_draft=$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')
  base=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // ""')
  head_ref=$(printf '%s' "$PR_JSON" | jq -r '.headRefName // ""')
  head_oid=$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // ""')
  merge_state=$(printf '%s' "$PR_JSON" | jq -r '.mergeStateStatus // ""')
  mergeable=$(printf '%s' "$PR_JSON" | jq -r '.mergeable // ""')
  live_url=$(canon_pr_url "$(printf '%s' "$PR_JSON" | jq -r '.url // ""')")
  head_repo=$(printf '%s' "$PR_JSON" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  head_cross=$(printf '%s' "$PR_JSON" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)
  if [ "$(url_repo_q "$live_url")" != "$ORIGIN_REPO_Q" ] \
     || { [ -n "$prurl" ] && [ "$(canon_pr_url "$prurl")" != "$live_url" ]; } \
     || [ -z "$head_repo" ] || [ "$head_repo" != "$ORIGIN_REPO" ] || [ "$head_cross" != "false" ] \
     || { [ -n "$branch" ] && [ "$head_ref" != "$branch" ]; }; then
    echo "$PROG: PR#$num identity did not certify for $id (url/head/fork mismatch); NOTHING recorded" >&2
    skipped=$((skipped + 1)); continue
  fi
  [ -n "$target" ] || target="$base"

  # --- PR merged (out-of-band, or a died record): record it ----------------------
  if [ "$state" = "MERGED" ]; then
    merge_oid=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json mergeCommit 2>/dev/null \
      | scrub | jq -r '.mergeCommit.oid // ""')
    if [ -z "$merge_oid" ]; then
      # Never record an empty merged_sha (I5: closed anchor => merged+merged_sha).
      echo "$PROG: WARN PR#$num is MERGED but the mergeCommit read came back empty; recording merged_sha=unverified:PR#$num" >&2
      merge_oid="unverified:PR#$num"
    fi
    case "$merge_oid" in
      unverified:*) short_oid="$merge_oid" ;;
      *) short_oid=$(printf '%.8s' "$merge_oid") ;;
    esac
    if "$LIFECYCLE" transition "$id" --to merged --expect pull_request --close \
         --set "merged_sha=$merge_oid" --unset rejection_reason \
         --append-notes "Merged to $target at $short_oid (recorded by pr-facts)"; then
      recorded=$((recorded + 1))
      echo "$PROG: recorded $id — PR#$num is MERGED ($short_oid)"
    else
      echo "$PROG: PR#$num is MERGED but the record failed for $id; retry next pass" >&2
      skipped=$((skipped + 1))
    fi
    continue
  fi

  # --- PR closed unmerged: out-of-band close -> abandoned + visit ----------------
  if [ "$state" = "CLOSED" ]; then
    if "$LIFECYCLE" transition "$id" --to abandoned --expect pull_request \
         --assignee "" \
         --set "blocked_reason=PR#$num closed out-of-band without merging"; then
      flagged=$((flagged + 1))
      escalate "$id" "pr-abandoned.$num" \
        "PR#$num ($live_url) was closed out-of-band without merging. The anchor is left OPEN, routed to human (merge_result=abandoned). Decide: rework it, or close it as not-planned."
      echo "$PROG: $id — PR#$num closed out-of-band; abandoned, routed to human, escalated"
    else
      echo "$PROG: $id abandoned transition failed; retry next pass" >&2
      skipped=$((skipped + 1))
    fi
    continue
  fi
  [ "$state" = "OPEN" ] || { skipped=$((skipped + 1)); continue; }
  [ "$is_draft" != "true" ] || { skipped=$((skipped + 1)); continue; }

  # --- base moved: retargeted + visit; a pre-retarget review proves nothing ------
  rec_target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // ""')
  if [ -n "$rec_target" ] && [ -n "$base" ] && [ "$rec_target" != "$base" ]; then
    UNSETS=()
    while IFS= read -r g; do
      [ -n "$g" ] && UNSETS+=(--unset "check.$g")
    done <<GATES
$(gate_tokens "$checkset")
GATES
    if "$LIFECYCLE" transition "$id" --to retargeted --expect pull_request \
         --assignee "" ${UNSETS[@]+"${UNSETS[@]}"} \
         --set "blocked_reason=PR#$num retargeted: base '$base' != expected target '$rec_target'"; then
      flagged=$((flagged + 1))
      escalate "$id" "pr-retargeted.$num" \
        "PR#$num ($live_url) was retargeted: base '$base' != expected '$rec_target'. Retarget it back and reset merge_result=pull_request to re-engage, or update merged_target if the new base is intentional."
      echo "$PROG: $id — PR#$num retargeted (base '$base' != '$rec_target'); routed to human, gate markers cleared, escalated"
    else
      echo "$PROG: $id retargeted transition failed; retry next pass" >&2
      skipped=$((skipped + 1))
    fi
    continue
  fi

  # --- CONFLICTING: file ONE rework child per head to the fix pool ---------------
  if [ "$mergeable" = "CONFLICTING" ] || [ "$merge_state" = "DIRTY" ]; then
    if is_held "$hold" || is_held "$rhold"; then
      echo "$PROG: $id — PR#$num conflicts but a hold is set (operator gate); no rework dispatched"
      skipped=$((skipped + 1)); continue
    fi
    fix_branch="${head_ref:-$branch}"
    if [ -z "$fix_branch" ] || [ -z "$FIX_POOL" ]; then
      echo "$PROG: $id — PR#$num conflicts but branch/fix-pool unavailable; merge stays held (operator must repair)" >&2
      skipped=$((skipped + 1)); continue
    fi
    # --- WHICH rewrite may be dispatched against this branch. ---------------------
    # >>> stale-base-dispatch-mode
    # This arm dispatches a rewrite rather than performing one, so tk-a0hva's
    # allowlist on the refinery's own prepare step cannot reach it. Same allowlist
    # as mol-refinery-patrol's `shared-branch-merge-mode`, deliberately one shape
    # restated rather than a second discriminator invented here. Only polecat/* is
    # single-author and disposable enough to rewrite; every other shape, including
    # one invented next year, must fail to MERGE, which a denylist could not do.
    # Classified on fix_branch, the branch the child is told to bring current, not
    # on the anchor's recorded branch. See
    # specs/tk-rvspf/dispatch-site-branch-classification.md.
    case "$fix_branch" in
      polecat/*) prepare_mode=rebase ;;
      *)         prepare_mode=merge ;;
    esac
    # Load-bearing only for a graduation carried on a polecat-shaped branch.
    if [ "$grad" = "true" ]; then prepare_mode=merge; fi
    # prepare_mode is what stops the rewrite; mol-polecat-work's
    # `rejected-branch-resume-mode` reads it. The title and instruction are for
    # whoever works the bead by hand, and must not contradict it: a merge-mode
    # child titled "Rebase PR#N" invites exactly what the mode prevents.
    if [ "$prepare_mode" = "merge" ]; then
      FIX_TITLE="Merge $base into PR#$num (shared branch $fix_branch):"
      fix_instruction="Resume in prepare_mode=merge: '$fix_branch' is a SHARED branch, so bring it current by MERGING origin/$base IN (git merge --no-edit origin/$base), resolve conflicts, and push as a fast-forward. Do NOT rebase it and do NOT force-push it: rewriting it orphans the already-merged PRs it carries (tk-a0hva)."
    else
      FIX_TITLE="Rebase PR#$num onto $base:"
      fix_instruction="Resume in prepare_mode=rebase: rebase '$fix_branch' onto origin/$base, resolve conflicts, and force-push with --force-with-lease."
    fi
    # <<< stale-base-dispatch-mode
    # Dedup on branch+head via the child's own metadata (no bookkeeping key on
    # the anchor): a child of ANY status whose rejection_reason names this head
    # means this head was already routed; a LIVE child on the branch means a
    # force-push is already owned — a second one would race it.
    kids=$(bd_list --metadata-field branch="$fix_branch" --status="$ALL_STATUSES") || {
      echo "$PROG: $id — PR#$num conflicts but the rework probe failed; no rework dispatched (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    }
    dup=$(printf '%s' "$kids" | jq -r --arg id "$id" --arg h "$head_oid" --arg live "$LIVE_STATUSES" '
      ($live | split(",")) as $ls
      | [ .[] | select(.id != $id)
          | select(((.metadata.merge_result // "") | tostring) == "")
          | ((.status // "open") | ascii_downcase) as $st
          | ((.metadata.rejection_reason // "") | tostring) as $rr
          | select((($rr | contains("head " + $h)) and ($h != ""))
                   or (($ls | index($st)) != null))
          | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$dup" ]; then
      echo "$PROG: $id — PR#$num conflicts; rework $dup already covers branch '$fix_branch' at this head, no new child"
      skipped=$((skipped + 1)); continue
    fi
    # Any rebase_hold on a bead naming this branch is an operator freeze.
    frozen=$(printf '%s' "$kids" | jq -r '
      [ .[] | ((.metadata.rebase_hold // "") | tostring | ascii_downcase) as $h
        | select($h != "" and $h != "false" and $h != "0" and $h != "null") | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$frozen" ]; then
      echo "$PROG: $id — PR#$num conflicts but $frozen holds branch '$fix_branch' with rebase_hold (operator gate); no rework dispatched"
      skipped=$((skipped + 1)); continue
    fi
    # Orphan adoption BEFORE create: a child this arm created whose stamp then
    # failed carries the deterministic title but no branch metadata — invisible
    # to the branch dedup above, so re-creating would mint a twin every pass. The
    # title is the classifier's, and stays deterministic for a given head: the
    # mode is a pure function of the branch name and the graduation marker.
    # An unreadable probe dispatches nothing (retry next pass).
    if ! forphans=$(bd_list --status=open --title-contains "$FIX_TITLE"); then
      echo "$PROG: $id — PR#$num conflicts but the orphan probe failed; no rework dispatched (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    FIX=$(printf '%s' "$forphans" | jq -r '
      [ .[] | select(((.metadata.branch // "") | tostring) == "") | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$FIX" ]; then
      echo "$PROG: $id adopting unstamped rework orphan $FIX for PR#$num (created by a prior pass whose stamp failed)"
    else
      FIX=$(gc bd create "$FIX_TITLE base rewritten, PR conflicts" -t task --json 2>/dev/null \
        | jq -r '.id // empty' 2>/dev/null)
    fi
    if [ -z "$FIX" ]; then
      echo "$PROG: $id could not file the rework child for PR#$num; retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    # The route is stamped separately, after prepare_mode reads back. A dropped
    # branch or pr_url leaves a child nothing can act on, which is the safe side;
    # a dropped prepare_mode leaves one that is routable AND rewriting, because
    # the resume path treats an absent mode as rebase.
    gc bd update "$FIX" \
      --set-metadata branch="$fix_branch" \
      --set-metadata target="$base" \
      --set-metadata rejection_reason="stale base at head $head_oid: PR#$num conflicts with '$base'. $fix_instruction Do NOT open a new PR — this reworks PR#$num." \
      --set-metadata prepare_mode="$prepare_mode" \
      --set-metadata merge_strategy=mr \
      --set-metadata existing_pr="$live_url" \
      --set-metadata pr_url="$live_url" \
      --set-metadata pr_number="$num" >/dev/null 2>&1 \
      || echo "$PROG: WARN rework $FIX created but not fully stamped; route it to $FIX_POOL by hand" >&2
    gc bd dep "$FIX" --blocks "$id" >/dev/null 2>&1 \
      || echo "$PROG: WARN could not attach rework $FIX as a blocks-dep of $id" >&2
    mgot=$(gc bd show "$FIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.prepare_mode // empty')
    if [ "$mgot" != "$prepare_mode" ]; then
      echo "$PROG: WARN rework $FIX did not record prepare_mode=$prepare_mode; left unrouted (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    gc bd update "$FIX" --set-metadata gc.routed_to="$FIX_POOL" >/dev/null 2>&1 \
      || echo "$PROG: WARN rework $FIX not routed to $FIX_POOL; route it by hand" >&2
    gc session wake "$FIX_POOL" >/dev/null 2>&1 || true
    reworked=$((reworked + 1))
    echo "$PROG: $id — PR#$num conflicts with '$base'; filed $prepare_mode-mode rework $FIX routed to $FIX_POOL"
    continue
  fi

  # --- a head-bound verdict at a STALE head: one re-review child per head -------
  # exception@ rides the same path as green@: both bind a verdict to a commit,
  # and a branch that has moved past either one has had no look at its head.
  stale_gate=""; stale_oid=""; stale_verb=""
  if [ -n "$head_oid" ]; then
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      case "$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')" in none|off|approval) continue ;; esac
      m=$(printf '%s' "$row" | jq -r --arg k "check.$g" '(.metadata[$k] // "") | tostring')
      case "$m" in
        green@*|exception@*)
          o="${m#*@}"
          if [ -n "$o" ] && [ "$o" != "$head_oid" ]; then
            stale_gate="$g"; stale_oid="$o"; stale_verb="${m%%@*}"; break
          fi ;;
      esac
    done <<GATES
$(gate_tokens "$checkset")
GATES
  fi
  if [ -n "$stale_gate" ]; then
    if is_held "$hold"; then
      echo "$PROG: $id — PR#$num check.$stale_gate stale but merge_hold set; no re-review dispatched"
      skipped=$((skipped + 1)); continue
    fi
    if [ -z "$REVIEW_POOL" ]; then
      echo "$PROG: $id — PR#$num check.$stale_gate stale but no --review-pool; merge stays held" >&2
      skipped=$((skipped + 1)); continue
    fi
    # Dedup per head: a live review naming this anchor, or any review child with
    # review_branch=branch and reviewed_oid=<live head> (this arm's own stamp).
    revs=$(bd_list --metadata-field anchor_bead="$id" --status="$LIVE_STATUSES") || {
      echo "$PROG: $id — re-review dedup probe failed; no dispatch (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    }
    live_rev=$(printf '%s' "$revs" | jq -r '
      [ .[] | select(((.metadata.task_kind // "") | tostring) == "review") | .id ] | .[0] // empty' 2>/dev/null)
    byhead=$(bd_list --metadata-field review_branch="${branch:-$head_ref}" --status="$ALL_STATUSES") || byhead="[]"
    head_rev=$(printf '%s' "$byhead" | jq -r --arg h "$head_oid" '
      [ .[] | select(((.metadata.reviewed_oid // "") | tostring) == $h) | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$live_rev" ] || [ -n "$head_rev" ]; then
      skipped=$((skipped + 1)); continue
    fi
    NOTE="Stale-gate re-review: check.$stale_gate was $stale_verb@$stale_oid; the PR head moved to $head_oid with no rework filed. Re-review the live head."
    # Orphan adoption BEFORE create (same shape as the rebase arm): an
    # unstamped re-review carries the deterministic title but no anchor_bead.
    REV_TITLE="Review PR#$num: re-review at live head"
    if ! rorphans=$(bd_list --status=open --title-contains "$REV_TITLE"); then
      echo "$PROG: $id — re-review orphan probe failed; no dispatch (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    RID=$(printf '%s' "$rorphans" | jq -r '
      [ .[] | select(((.metadata.anchor_bead // "") | tostring) == "") | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$RID" ]; then
      echo "$PROG: $id adopting unstamped re-review orphan $RID for PR#$num (created by a prior pass whose stamp failed)"
    else
      body=""
      [ -x "$BODY_EMITTER" ] && body=$("$BODY_EMITTER" --check-name "$stale_gate" --note "$NOTE" 2>/dev/null) || body=""
      if [ -n "$body" ]; then
        RID=$(printf '%s' "$body" | gc bd create "$REV_TITLE" -t task --body-file - --json 2>/dev/null \
          | jq -r '.id // empty' 2>/dev/null)
      else
        RID=$(gc bd create "$REV_TITLE" -t task --json 2>/dev/null \
          | jq -r '.id // empty' 2>/dev/null)
      fi
    fi
    if [ -z "$RID" ]; then
      echo "$PROG: $id could not file the re-review for PR#$num; retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    gc bd update "$RID" \
      --set-metadata task_kind=review \
      --set-metadata check_name="$stale_gate" \
      --set-metadata anchor_bead="$id" \
      --set-metadata review_branch="${branch:-$head_ref}" \
      --set-metadata review_base="$base" \
      --set-metadata reviewed_oid="$head_oid" \
      --set-metadata pr_url="$live_url" \
      --set-metadata pr_number="$num" \
      --set-metadata review_pool="$REVIEW_POOL" \
      ${FIX_POOL:+--set-metadata fix_target_pool="$FIX_POOL"} >/dev/null 2>&1
    gc bd dep "$RID" --blocks "$id" >/dev/null 2>&1 || true
    got=$(gc bd show "$RID" --json 2>/dev/null | scrub | jq -r '.[0].metadata.anchor_bead // empty')
    if [ "$got" != "$id" ]; then
      echo "$PROG: WARN re-review $RID did not record anchor_bead=$id; left unrouted (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    # One sling, no retry (a re-pour mints a second workflow root); the pour
    # retires gc.routed_to and stamps gc.execution_routed_to — the read-back.
    gc sling ${GC_RIG:+--rig "$GC_RIG"} "$REVIEW_POOL" "$RID" --on mol-review >/dev/null 2>&1
    rgot=$(gc bd show "$RID" --json 2>/dev/null | scrub | jq -r '.[0].metadata["gc.execution_routed_to"] // empty')
    if [ "$rgot" != "$REVIEW_POOL" ]; then
      echo "$PROG: WARN re-review $RID pour did not read back; retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    gc session wake "$REVIEW_POOL" >/dev/null 2>&1 || true
    regated=$((regated + 1))
    echo "$PROG: $id — PR#$num check.$stale_gate $stale_verb@$stale_oid is stale (live head $head_oid); filed re-review $RID routed to $REVIEW_POOL"
    continue
  fi

  # --- dismiss our OWN superseded CHANGES_REQUESTED when the gate is green -------
  # Only when every declared gate is green at the LIVE head but GitHub is still
  # red on our own stale block. Never a human's review; skipped when native
  # auto-merge is armed (the dismissal would hand GitHub the landing).
  all_green=1
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')" in none|off|approval) continue ;; esac
    m=$(printf '%s' "$row" | jq -r --arg k "check.$g" '(.metadata[$k] // "") | tostring')
    [ "$m" = "green@$head_oid" ] || all_green=0
  done <<GATES
$(gate_tokens "$checkset")
GATES
  rd=$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // ""')
  if [ "$all_green" = 1 ] && [ -n "$head_oid" ] && [ "$rd" = "CHANGES_REQUESTED" ] \
     && [ -n "$SELF_LOGIN" ]; then
    auto=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json autoMergeRequest 2>/dev/null \
      | jq -r 'if (.autoMergeRequest // null) == null then "off" else "armed" end' 2>/dev/null)
    if [ "$auto" != "off" ]; then
      echo "$PROG: $id — PR#$num has a stale block of ours but native auto-merge is armed (or unreadable); not dismissing"
      skipped=$((skipped + 1)); continue
    fi
    reviews=$(gh_api_origin --paginate "repos/$ORIGIN_REPO/pulls/$num/reviews?per_page=100" \
      --jq '.[]' 2>/dev/null) || reviews=""
    stale_rid=$(printf '%s' "$reviews" | jq -sr --arg self "$SELF_LOGIN" --arg head "$head_oid" '
      [ .[] | select((.user.login // "") == $self)
        | select(.state == "CHANGES_REQUESTED")
        | select((.commit_id // "") != $head) | (.id // empty) ] | .[0] // empty' 2>/dev/null)
    if [ -n "$stale_rid" ]; then
      # Record signoff_dismissed FIRST and read it back: the marker arms the
      # external-approval requirement, and a dismissal without it drops both the
      # block and the requirement.
      gc bd update "$id" --set-metadata signoff_dismissed="$stale_rid@$head_oid" >/dev/null 2>&1
      got=$(gc bd show "$id" --json 2>/dev/null | scrub | jq -r '.[0].metadata.signoff_dismissed // empty')
      if [ "$got" != "$stale_rid@$head_oid" ]; then
        echo "$PROG: $id — signoff_dismissed marker did not persist; NOT dismissing review $stale_rid" >&2
        skipped=$((skipped + 1)); continue
      fi
      if gh_api_origin -X PUT "repos/$ORIGIN_REPO/pulls/$num/reviews/$stale_rid/dismissals" \
           -f message="Superseded: check gates are green at the live head $head_oid; this block was pinned to a commit that is no longer the head." >/dev/null 2>&1; then
        dismissed_n=$((dismissed_n + 1))
        echo "$PROG: $id — dismissed our own superseded CHANGES_REQUESTED (review $stale_rid) on PR#$num; signoff_dismissed recorded"
      else
        echo "$PROG: $id — dismissal of review $stale_rid failed; marker stays recorded, retry next pass" >&2
        skipped=$((skipped + 1))
      fi
    fi
  fi
done <<ROWS_EOF
$(printf '%s' "$ANCHORS" | jq -c '.[]' 2>/dev/null)
ROWS_EOF

echo "$PROG: $recorded recorded, $flagged flagged-to-human, $reworked reworks filed, $regated re-reviews filed, $dismissed_n reviews dismissed, $skipped skipped"
exit 0
