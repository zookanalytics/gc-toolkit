#!/usr/bin/env bash
# pr-facts — arm 4 of the merge cadence: record EXTERNAL facts about each open
# pull_request anchor. No merge authority. Same enumeration and pinned identity
# read as merge.sh; per anchor, in order: PR MERGED (out-of-band, or a record
# that died after merge.sh landed it) -> lifecycle transition to merged, with
# a failure counted against the same record-failure-cap.sh budget merge.sh
# spends, since both are attempts at the one repair;
# CLOSED-unmerged -> abandoned + escalate.sh visit; base moved -> retargeted +
# escalate (gate markers cleared: a review of the pre-retarget diff proves
# nothing about the new base); CONFLICTING -> classify the head branch
# (allowlist: only polecat/* may be rewritten, and never a graduation) and file
# ONE rework child per head to the fix pool, stamped prepare_mode and counted as
# dispatched only once that stamp AND the route itself read back (dedup: a rework
# child naming this branch whose rejection_reason names this head; an unstamped
# orphan is adopted by title and an unrouted one re-routed, never twinned; an
# operator's hold, rebase_hold, or a live demand dispatches nothing this pass,
# since rebasing is one horn of what a demand asks — except the round cap's own
# park (merge_hold=signoff_cap paired with signoff_cap), which is not an
# operator's hold to begin with: it falls through instead of blocking outright,
# so operator feedback below can still retire it even on a conflicting PR);
# dismissal of our OWN superseded CHANGES_REQUESTED (never a
# human's; signoff_dismissed read back FIRST; skipped under native auto-merge).
# No arm here re-reviews a moved head: a lane state is a state of the lane, and
# gate-ensure dispatches on the lane, not on the commit under it. A merged record never carries an
# empty merged_sha — an unreadable mergeCommit records
# merged_sha=unverified:PR#<n>, loudly.
# Every OPEN non-draft anchor also gets its POSTURE recorded before any dispatch
# arm runs (lifecycle/lifecycle.toml [posture]): pr_posture (dated) and pr_merge_state
# pinned to the live head, written only when the value changes, so merge.sh can
# answer "is a human waiting on this?" off the bead instead of re-deriving it.
# --posture-only exits non-zero when any anchor is left without a current
# posture and nothing standing already holds it: the caller holds merge.sh for
# that pass rather than let it validate against a fact from an earlier tick.
# Unanswered review feedback routes to something — a fix-pool rework child
# carrying the review bodies and inline comments verbatim, or a visit when a
# human already holds the anchor — with the watermarks advancing only once that
# routing reads back. It routes under posture `commented` and equally under a
# human `changes_requested`, which holds the merge but answers nothing; a
# dismissed review is in neither state, so a dismissal takes it and the inline
# comments under it out of the batch.
# Such a batch also resets signoff.sh's review-round cap, once per batch: it is
# review the branch has never been answered against, not a round of the loop the
# cap measures. The reset retires the dispatch tally with it, and the cap's own
# park (its merge_hold, blocked_reason and human route) when signoff_cap and the
# standing hold still agree it was the cap that wrote them.
# After the dispatch arms, a write-back sweep gives the operator an
# acknowledgement trail where they are already reading. An anchor carrying
# pr_comment_disposition has a bead covering its comments, so every comment at
# or below the recorded watermark gets an EYES reaction. Once that bead closes,
# each thread holding one of the comments it answers gets one reply naming the
# commit and is then resolved; the mark is cumulative, so that batch is bounded
# below by pr_comment_batch and an earlier batch's unresolved thread is left
# alone. The reactions are written first, and a pass that cannot finish them
# replies to and resolves nothing, so no thread is answered over a comment still
# awaiting its acknowledgement. A thread a human answered after the city's reply
# is left open, and so is one holding a comment above the mark: no batch covers
# that comment, so nothing has answered it yet.
# Idempotence is read off GitHub, so a repeat pass writes nothing and a failed
# write retries.
# Args: --fix-pool <pool>. Caller: refinery-reconcile.sh
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
# The merged-record retry cap, shared with merge.sh: this arm and merge.sh's two
# record arms perform the same repair on the same anchor, so their failures
# count against one budget rather than each keeping a private tally.
RECORD_CAP="$SCRIPTS_DIR/record-failure-cap.sh"

FIX_POOL=""; POSTURE_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fix-pool)     FIX_POOL="${2:-}"; shift 2 ;;
    --posture-only) POSTURE_ONLY=1; shift ;;
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
# The round cap's own park pairs merge_hold=signoff_cap (the literal string,
# never `true`) with a non-empty signoff_cap naming the gate. That ONE pairing
# is the cap's park — is_held(merge_hold) alone is not enough, since an
# operator can set merge_hold=true for an unrelated freeze (a release hold,
# say) while an orphaned signoff_cap stamp still sits on the anchor from an
# earlier park the operator already lifted by hand (signoff.sh leaves
# signoff_cap in place on purpose; see signoff.test.sh's "a signoff_cap
# standing beside no hold retires nothing"). Both the CONFLICTING arm and the
# operator-feedback reset arm below key on this same predicate.
is_cap_park() { [ "${1:-}" = "signoff_cap" ] && [ -n "${2:-}" ]; }

# >>> takeaway-hold-discriminator
# Whether a person still owes an answer on this anchor. `gc.takeaway` cannot
# say: it is one field a sitting stamps when it begins and REPLACES with its
# outcome when it signs off, and nothing clears it, so its presence dates the
# last sitting instead of naming a live wait. Read as a hold, it parks an
# anchor from its first conversation onward.
#
# The wait itself is a bead. `gc-helm.sh demand` files what a person owes as
# its own bead stamped gc.demand_for=<anchor>, blocking the anchor on it, and
# the sitting closes that bead with the ruling that answers it. A live demand
# is a live hold; none, and the takeaway records a sitting that ended.
#
# Only demands count. Rework children and `--waiting-on` edges are work in
# flight, which the merge already holds on, and reading `blocks` at large would
# restore the same permanence one indirection out. The `held` lifecycle state
# is not read either: it is entered only from `unanchored`, and every anchor a
# round cap parks carries pre_open_gate or pull_request.
#
# Fails CLOSED — a ledger that will not read answers "held", because releasing
# an anchor a person is holding hands their decision back to a pool.
takeaway_is_holding() { # <anchor-id>; 0 = a person still owes an answer here
  local rows
  rows=$(gc bd list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --metadata-field "gc.demand_for=${1:-}" --limit=0 --json 2>/dev/null) || return 0
  rows=$(printf '%s' "$rows" | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 0
  printf '%s' "$rows" | jq -e --arg a "${1:-}" \
    '[ .[] | select(((.metadata["gc.demand_for"] // "") | tostring) == $a) ] | length > 0' \
    >/dev/null 2>&1
}
# <<< takeaway-hold-discriminator

# >>> pr-posture-vocabulary
# Mirrors lifecycle/lifecycle.toml [posture]; pr-facts.test.sh fails on drift.
# Listed in the precedence the derivation applies, strongest human signal first.
PR_POSTURES="changes_requested commented approved review_required none"
# <<< pr-posture-vocabulary
# >>> pr-writeback-contract
# The acknowledgement trail the operator reads in the PR. EYES marks a comment
# the city picked up. The marker identifies our own reply, so a later pass can
# tell one it already posted from a human's. Idempotence is read back off GitHub
# (viewerHasReacted, this marker, isResolved) and never off a bead key, so a
# write that failed is retried and a write that landed is never repeated.
WB_REACTION="EYES"
WB_MARKER="<!-- gc-writeback -->"
# A first activation over a long-running PR would otherwise post one reaction per
# outstanding comment in a single pass. It holds the batch's replies and
# resolves back with the comments it defers, since a thread answered before its
# comment is acknowledged claims the city acted on something it never showed it
# had picked up.
WB_REACT_CAP=50
# <<< pr-writeback-contract

gh_graphql() { # <query> [gh -f/-F args...]; non-zero = "could not tell"
  local q="$1"; shift
  local raw rc
  raw=$(gh api graphql --hostname "$ORIGIN_HOST" -f query="$q" "$@" 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  printf '%s' "$raw" | scrub
}

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
escalate() { # <subject> <key> <message> — best-effort; escalate.sh dedups the situation
  [ -x "$ESCALATE" ] || return 0
  "$ESCALATE" --subject "$1" --key "$2" --message "$3" >/dev/null 2>&1 || true
}
visit_for() { # <subject> <key> — the LIVE visit escalate.sh keeps for this situation
  # Both stamps are re-checked here as well as queried: this id gets pr_number
  # written onto it, so a row that came back for another subject would stamp a
  # stranger's bead and hold the wrong merge.
  local rows
  rows=$(bd_list --status="$LIVE_STATUSES" --metadata-field "escalation_key=$2" \
           --metadata-field "gc.continuation_group=$1") || return 1
  printf '%s' "$rows" | jq -r --arg s "$1" --arg k "$2" '
    [ .[] | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
          | select(((.metadata.escalation_key // "") | tostring) == $k)
          | .id ] | .[0] // empty' 2>/dev/null
}
gh_rows() { # <api path> — one paginated endpoint re-collected into ONE array
  # `gh --paginate` emits one array per PAGE; --jq '.[]' flattens the pages and
  # jq -s makes the whole read an array again. Non-zero = "could not tell".
  local raw rc
  raw=$(gh_api_origin --paginate "$1" --jq '.[]' 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] || return 1
  printf '%s' "$raw" | scrub | jq -sc '.' 2>/dev/null
}
# >>> unanswered-feedback-body
# The work order carries the feedback itself, not a link to it. A polecat has
# to know what was asked without a second GitHub read, and a review BODY is not
# on the /files page its inline comments live on, so an objection stated in the
# body alone reaches a page-pointing work order as nothing at all.
feedback_body() { # <reviews-json> <comments-json> <review-mark> <comment-mark> — markdown on stdout
  jq -nr --argjson revs "$1" --argjson cmts "$2" --argjson rmark "$3" --argjson cmark "$4" \
         --arg self "$SELF_LOGIN" '
    def clip($n): if (length) > $n then (.[0:$n] + "\n\n_(truncated — the rest is on the PR)_") else . end;
    def body: ((.body // "") | tostring);
    ([ $revs[] | select(((.user.login // "") | tostring) != $self)
              | (((.state // "") | tostring)) as $st
              | select((["COMMENTED", "CHANGES_REQUESTED"] | index($st)) != null)
              | select((body | gsub("[[:space:]]"; "")) != "")
              | select(((.id // 0) | tonumber) > $rmark) ] | sort_by(.id)) as $R
  | ([ $cmts[] | select(((.user.login // "") | tostring) != $self)
              | select(((.id // 0) | tonumber) > $cmark) ] | sort_by(.id)) as $C
  | ((if ($R | length) > 0 then ["## Review bodies"]
        + [ $R[] | "### \(.user.login // "?") — \(.state // "?") (review \(.id))\n\n\(body | clip(4000))" ]
      else [] end)
   + (if ($C | length) > 0 then ["## Inline comments"]
        + [ $C[] | "### \(.path // "?")\(if ((.line // .original_line) != null) then ":\(.line // .original_line)" else "" end) — \(.user.login // "?") (comment \(.id))\n\n\(body | clip(2000))" ]
      else [] end)
   | join("\n\n")) | clip(16000)' 2>/dev/null
}
# A comment outlives the review that carried it: GitHub keeps the inline rows of
# a dismissed review on /pulls/N/comments, so a dismissal that takes the body
# out of the batch leaves the comments under it routing. A dismissal is the only
# thing that retires them. The review space's filter is narrower than that and
# cannot stand in for this one: it also drops an APPROVED review, whose inline
# comments are live feedback, and a PR green everywhere else would merge over
# them. A comment naming no review, or naming one the review list does not
# carry, is standalone and stays.
live_comments() { # <reviews-json> <comments-json> — comments no dismissal retired
  jq -nc --argjson revs "$1" --argjson cmts "$2" '
    ([ $revs[]
       | select(((.state // "") | tostring) == "DISMISSED")
       | ((.id // 0) | tostring) ]) as $retired
  | [ $cmts[]
      | (((.pull_request_review_id // "") | tostring)) as $parent
      | select(($retired | index($parent)) == null) ]' 2>/dev/null
}
# A batch names the reviews it answers, the way a signoff-sourced child names
# its review bead. An empty-bodied CHANGES_REQUESTED is named here even though
# the body filter above keeps it out of the watermark: it is the review holding
# the merge, and its inline comments are what the child has to answer.
feedback_reviews() { # <reviews-json> <review-mark> — comma-joined review ids
  jq -nr --argjson revs "$1" --argjson rmark "$2" --arg self "$SELF_LOGIN" '
    [ $revs[] | select(((.user.login // "") | tostring) != $self)
              | select(((.id // 0) | tonumber) > $rmark)
              | select((((.state // "") | tostring) == "CHANGES_REQUESTED")
                       or ((((.state // "") | tostring) == "COMMENTED")
                           and (((.body // "") | tostring | gsub("[[:space:]]"; "")) != "")))
              | (.id | tostring) ] | sort | join(",")' 2>/dev/null
}
# <<< unanswered-feedback-body

ANCHORS=$(bd_list --status=open --metadata-field merge_result=pull_request) || {
  echo "$PROG: could not enumerate gating anchors; failing loudly rather than reporting a false all-clear" >&2
  exit 1
}
[ "$ANCHORS" != "[]" ] || { echo "$PROG: no gating anchors"; exit 0; }

recorded=0; flagged=0; reworked=0; dismissed_n=0; skipped=0
postured=0; answered=0; unpostured=0
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
  # Read once, off this same row, for is_cap_park below: the CONFLICTING arm's
  # cap-park carve-out and the operator-feedback reset arm's park retirement
  # both turn on the identical pairing.
  cap=$(printf '%s' "$row" | jq -r '(.metadata.signoff_cap // "") | tostring')
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
  rd=$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // ""')
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
  # Reconciliation is the full pass's; --posture-only writes a posture and
  # nothing else, so a MERGED or CLOSED anchor falls through to the OPEN filter.
  if [ "$state" = "MERGED" ] && [ "$POSTURE_ONLY" != 1 ]; then
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
         --unset merge_record_failures \
         --append-notes "Merged to $target at $short_oid (recorded by pr-facts)"; then
      recorded=$((recorded + 1))
      echo "$PROG: recorded $id — PR#$num is MERGED ($short_oid)"
    else
      echo "$PROG: PR#$num is MERGED but the record failed for $id; retry next pass" >&2
      skipped=$((skipped + 1))
      [ -x "$RECORD_CAP" ] && "$RECORD_CAP" "$id" "$num" "$merge_oid" "$target" || true
    fi
    continue
  fi

  # --- PR closed unmerged: out-of-band close -> abandoned + visit ----------------
  if [ "$state" = "CLOSED" ] && [ "$POSTURE_ONLY" != 1 ]; then
    if "$LIFECYCLE" transition "$id" --to abandoned --expect pull_request \
         --assignee "" \
         --set "blocked_reason=PR#$num closed out-of-band without merging" \
         --takeaway "PR#$num was closed without merging — rework the branch, or close this bead as not-planned"; then
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

  # --- posture: record what the PR is doing (a record, never a dispatch) --------
  # Placed ahead of every dispatch arm below so an anchor one of them claims
  # still gets its posture written; merge.sh reads the result off the bead
  # rather than asking GitHub. Written only when the value changes: this runs
  # for every anchor every 60s and an unchanged re-write is pure ledger churn.
  posture=""; max_c=0; max_r=0; pinned=0; unanswered=0; revs_raw=""; cmts_raw=""; cmts_live=""
  cwm=$(printf '%s' "$row" | jq -r '(.metadata.pr_comment_watermark // "") | tostring')
  rwm=$(printf '%s' "$row" | jq -r '(.metadata.pr_review_watermark // "") | tostring')
  obatch=$(printf '%s' "$row" | jq -r '(.metadata.pr_comment_batch // "") | tostring')
  case "$cwm" in ''|*[!0-9]*) cwm=0 ;; esac
  case "$rwm" in ''|*[!0-9]*) rwm=0 ;; esac
  if [ -z "$head_oid" ]; then
    echo "$PROG: $id — PR#$num live head unresolved; posture not recorded (a posture pins to a head or says nothing)" >&2
  elif [ -z "$SELF_LOGIN" ]; then
    # Our own comments are indistinguishable from a human's without the acting
    # login, and a weaker posture written here would clear a standing
    # `commented` that is holding the merge. Record nothing; hold what stands.
    echo "$PROG: $id — PR#$num posture not recorded: the acting login is unresolved" >&2
  else
    revs_raw=$(gh_rows "repos/$ORIGIN_REPO/pulls/$num/reviews?per_page=100") || revs_raw=""
    cmts_raw=$(gh_rows "repos/$ORIGIN_REPO/pulls/$num/comments?per_page=100") || cmts_raw=""
    if [ -z "$revs_raw" ] || [ -z "$cmts_raw" ]; then
      # A standing CHANGES_REQUESTED is settled by reviewDecision alone, so the
      # posture is still recorded; only the dispatch below needs the lists, and
      # it holds for a pass that can read them.
      if [ "$rd" = "CHANGES_REQUESTED" ]; then
        posture="changes_requested"
        echo "$PROG: $id — PR#$num review history unreadable; posture read from the review decision, the feedback under it not routed (retry next pass)" >&2
      else
        echo "$PROG: $id — PR#$num review history unreadable; posture not recorded (retry next pass)" >&2
      fi
    else
      # The comment space drops what a dismissal retired before anything counts
      # it, so the two spaces agree about what a dismissal takes out. A filter
      # that cannot run counts the unfiltered list: over-routing costs a rework
      # round an operator can close, dropping the batch costs the objection
      # itself.
      cmts_live=$(live_comments "$revs_raw" "$cmts_raw")
      if [ -z "$cmts_live" ]; then
        echo "$PROG: $id — PR#$num could not filter retired reviews out of the comment list; counting it unfiltered" >&2
        cmts_live="$cmts_raw"
      fi
      # A review with an empty body carries only its inline comments, which the
      # comment read below already sees; counting it here would leave a posture
      # no comment id can ever answer. CHANGES_REQUESTED counts beside
      # COMMENTED: an operator uses it to mean "change this", and it is the
      # feedback the loop most has to answer. A dismissed review is in neither
      # state, so a dismissal takes its ids out of the batch.
      max_r=$(printf '%s' "$revs_raw" | jq -r --arg self "$SELF_LOGIN" '
        [ .[] | select(((.user.login // "") | tostring) != $self)
          | (((.state // "") | tostring)) as $st
          | select((["COMMENTED", "CHANGES_REQUESTED"] | index($st)) != null)
          | select(((.body // "") | tostring | gsub("[[:space:]]"; "")) != "")
          | (.id // 0) ] | max // 0' 2>/dev/null)
      max_c=$(printf '%s' "$cmts_live" | jq -r --arg self "$SELF_LOGIN" '
        [ .[] | select(((.user.login // "") | tostring) != $self) | (.id // 0) ] | max // 0' 2>/dev/null)
      case "$max_r" in ''|*[!0-9]*) max_r=0 ;; esac
      case "$max_c" in ''|*[!0-9]*) max_c=0 ;; esac
      if [ "$max_c" -gt "$cwm" ] || [ "$max_r" -gt "$rwm" ]; then unanswered=1; fi
      # The posture is what merge.sh reads, and a standing CHANGES_REQUESTED
      # outranks the batch underneath it: the veto stands whether or not that
      # feedback has been routed yet. What routes is `unanswered`, below.
      if [ "$rd" = "CHANGES_REQUESTED" ]; then posture="changes_requested"
      elif [ "$unanswered" = 1 ]; then posture="commented"
      elif [ "$rd" = "APPROVED" ]; then posture="approved"
      elif [ "$rd" = "REVIEW_REQUIRED" ]; then posture="review_required"
      else posture="none"
      fi
    fi
  fi
  case " $PR_POSTURES " in
    *" $posture "*) : ;;
    *) [ -z "$posture" ] || { echo "$PROG: $id — refusing to record undeclared posture '$posture'" >&2; posture=""; } ;;
  esac
  have_p=$(printf '%s' "$row" | jq -r '(.metadata.pr_posture // "") | tostring')
  if [ -n "$posture" ]; then
    want_p="$posture@$head_oid"; want_m="${merge_state:-UNKNOWN}@$head_oid"
    have_m=$(printf '%s' "$row" | jq -r '(.metadata.pr_merge_state // "") | tostring')
    # pr_posture is a dated key: its review_required value starts an owed clock,
    # so the recorded value carries the instant as a third component and
    # lifecycle.sh preserves it while the posture and the head both hold. Only a
    # value already in that shape can be current — one still carrying the bare
    # <value>@<oid> has no instant, and one pass writing it is how it gains one.
    have_pv=""
    case "$have_p" in *@*@*) have_pv="${have_p%@*}" ;; esac
    if [ "$have_pv" = "$want_p" ] && [ "$have_m" = "$want_m" ]; then
      pinned=1
    elif "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
           --set-dated "pr_posture=$want_p" --set "pr_merge_state=$want_m" >/dev/null; then
      pinned=1
      postured=$((postured + 1))
      echo "$PROG: $id — PR#$num posture $want_p, merge state $want_m"
    else
      echo "$PROG: $id posture record failed for PR#$num; retry next pass" >&2
    fi
  fi
  # merge.sh validates the posture recorded here and never asks GitHub, so an
  # anchor this pass could not make current is one it would clear against a
  # fact from an earlier tick. A standing `commented@` is already holding that
  # merge; every other shape is the gap, and --posture-only reports it in its
  # exit code so refinery-reconcile can hold the merge arm for the pass.
  if [ "$pinned" != 1 ]; then
    case "$have_p" in
      commented@*) : ;;
      *) unpostured=$((unpostured + 1))
         echo "$PROG: $id — PR#$num posture is not current; merge must not read it this pass" >&2 ;;
    esac
  fi

  # merge.sh reads posture off the bead and never asks GitHub, so the record has
  # to be no older than the merge arm that reads it. --posture-only is that
  # earlier pass: it writes the posture and stops here, leaving every dispatch
  # arm below to the full pass that runs after merge.
  [ "$POSTURE_ONLY" != 1 ] || continue

  # --- base moved: retargeted + visit; a pre-retarget review proves nothing ------
  rec_target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // ""')
  if [ -n "$rec_target" ] && [ -n "$base" ] && [ "$rec_target" != "$base" ]; then
    UNSETS=()
    while IFS= read -r g; do
      [ -n "$g" ] && UNSETS+=(--unset "check.$g")
    done <<GATES
$(printf '%s' "$checkset" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d')
GATES
    if "$LIFECYCLE" transition "$id" --to retargeted --expect pull_request \
         --assignee "" ${UNSETS[@]+"${UNSETS[@]}"} \
         --set "blocked_reason=PR#$num retargeted: base '$base' != expected target '$rec_target'" \
         --takeaway "PR#$num sits on a base other than its expected target — retarget it back, or update merged_target"; then
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
    if is_held "$rhold"; then
      echo "$PROG: $id — PR#$num conflicts but a hold is set (operator gate); no rework dispatched"
      skipped=$((skipped + 1)); continue
    fi
    if is_held "$hold" && ! is_cap_park "$hold" "$cap"; then
      echo "$PROG: $id — PR#$num conflicts but a hold is set (operator gate); no rework dispatched"
      skipped=$((skipped + 1)); continue
    fi
    if is_cap_park "$hold" "$cap"; then
      # The cap's own park is not an operator's hold: signoff.sh's CAP_WHY
      # tells the operator that "new operator feedback on PR#N retires this
      # cap and its park", and a conflicting PR must not make that a lie by
      # wedging the park forever. `continue`ing here the way a person's hold
      # does would end this anchor's iteration before the posture=commented
      # arm below ever runs, so a capped anchor whose PR conflicts could never
      # be released by the very feedback the cap advertises — every pass
      # would print this line and stop, forever.
      #
      # So a cap park alone dispatches no rework THIS pass (merge_hold still
      # reads as the park at the top of this iteration, and the branch is
      # still conflicted), but falls through instead of `continue`ing: if
      # there is new operator feedback, the reset arm below retires the park
      # in this same pass, and the CONFLICTING check runs clean on the NEXT
      # pass — merge_hold actually empty by then — to file the rework.
      # Without feedback, nothing below fires and the anchor stays parked
      # exactly as it does today.
      echo "$PROG: $id — PR#$num conflicts but merge_hold parks the review-round cap (gate $cap); no rework dispatched this pass — operator feedback below can retire the park, and the rework files once merge_hold actually clears on a later pass"
      skipped=$((skipped + 1))
    else
    # A live demand is the same freeze. `gc-helm.sh demand` files what a person
    # owes as its own bead gating this anchor, and "rebase it onto the base" is
    # routinely one horn of the question being asked. A child dispatched under
    # one performs that horn as routine branch hygiene, which answers the
    # decision by fait accompli and leaves the person ruling on work already
    # done. The anchor's own gc.routed_to is not read here: the human route sits
    # on the demand bead, not on what it gates, and a freeze on the anchor's
    # route would hold the merge with nothing defined to lift it. Closing the
    # demand lifts this one, which is what the demand's own text asks for.
    if takeaway_is_holding "$id"; then
      echo "$PROG: $id — PR#$num conflicts but an open demand holds it for a person's decision; no rework dispatched"
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
    # A child of a prior pass whose route stamp exited 0 without writing. The
    # route is what makes it reachable — neither `bd ready` nor a pool claim can
    # see it without one — and the dedup below matches it, so nothing retries it.
    # Narrow to open/unassigned/unrouted at THIS head: a metadata write ignores
    # bd's claim guard, so re-stamping a child someone holds stomps live work.
    stranded=$(printf '%s' "$kids" | jq -r --arg id "$id" --arg h "$head_oid" '
      [ .[] | select(.id != $id)
        | select(((.status // "open") | ascii_downcase) == "open")
        | select(((.assignee // "") | tostring) == "")
        | select(((.metadata["gc.routed_to"] // "") | tostring) == "")
        | select(((.metadata["gc.execution_routed_to"] // "") | tostring) == "")
        | select(((.metadata.merge_result // "") | tostring) == "")
        | select(($h != "") and (((.metadata.rejection_reason // "") | tostring) | contains("head " + $h)))
        | .id ] | .[0] // empty' 2>/dev/null)
    # A strand is open, so it matches the live arm below and would veto its own
    # rescue; it is excluded from its own dedup and from nothing else. Any OTHER
    # match still vetoes — a second routed child would race the force-push the
    # first one already owns.
    dup=$(printf '%s' "$kids" | jq -r --arg id "$id" --arg s "$stranded" --arg h "$head_oid" --arg live "$LIVE_STATUSES" '
      ($live | split(",")) as $ls
      | [ .[] | select(.id != $id) | select(.id != $s)
          | select(((.metadata.merge_result // "") | tostring) == "")
          | ((.status // "open") | ascii_downcase) as $st
          | ((.metadata.rejection_reason // "") | tostring) as $rr
          | select((($rr | contains("head " + $h)) and ($h != ""))
                   or (($ls | index($st)) != null))
          | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$dup" ]; then
      echo "$PROG: $id — PR#$num conflicts; rework $dup already covers branch '$fix_branch' at this head, no new child${stranded:+ (unrouted sibling $stranded is redundant and holds the anchor)}"
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
    if [ -n "$stranded" ]; then
      FIX="$stranded"
      echo "$PROG: $id re-routing stranded rework $FIX for PR#$num (a prior pass's route stamp did not land)"
    else
      # Orphan adoption BEFORE create: a child this arm created whose stamp then
      # failed carries the deterministic title but no branch metadata — invisible
      # to the branch dedup above, so re-creating would mint a twin every pass.
      # The title is the classifier's, and stays deterministic for a given head:
      # the mode is a pure function of the branch name and the graduation marker.
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
    # `gc bd update` returns 0 without having written (the claim guard is one
    # such path), so the exit code does not establish the route, and an unrouted
    # child reported as dispatched is a rework nothing can reach.
    gc bd update "$FIX" --set-metadata gc.routed_to="$FIX_POOL" >/dev/null 2>&1 || true
    rgot=$(gc bd show "$FIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata["gc.routed_to"] // empty')
    if [ "$rgot" != "$FIX_POOL" ]; then
      echo "$PROG: WARN rework $FIX did not record gc.routed_to=$FIX_POOL; left unrouted (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    gc session wake "$FIX_POOL" >/dev/null 2>&1 || true
    reworked=$((reworked + 1))
    echo "$PROG: $id — PR#$num conflicts with '$base'; filed $prepare_mode-mode rework $FIX routed to $FIX_POOL"
    continue
    fi
  fi

  # --- unanswered review feedback routes to something ---------------------------
  # Reached only when the anchor is otherwise clear: the conflict and stale-gate
  # arms above already left a child in flight holding the merge, and the feedback
  # gets its own dispatch on the pass after that child lands. Whatever this
  # routes to holds the merge until it closes, and the watermarks move only once
  # the routing has read back — feedback nothing answered can never fall below
  # the mark.
  # The batch is the same whether the posture reads `commented` or
  # `changes_requested`. A CHANGES_REQUESTED holds the merge on its own, and a
  # hold is not an answer: objections nothing routes converge to codex-green
  # untouched, while the commits landing meanwhile read as rework that addressed
  # them.
  if [ "$unanswered" = 1 ]; then
    fix_branch="${head_ref:-$branch}"
    routed=$(printf '%s' "$row" | jq -r '(.metadata["gc.routed_to"] // "") | tostring')
    # Read once: both the cap retirement below and the routing choice after it
    # turn on the same question, and each answer costs a ledger read.
    holding=""; takeaway_is_holding "$id" && holding=1
    takeaway_by=$(printf '%s' "$row" | jq -r '(.metadata["gc.takeaway_by"] // "") | tostring')

    # --- operator feedback resets the review-round cap ---------------------------
    # signoff.sh's cap bounds the city failing to converge against its own
    # reviewer. This batch is not that loop: the posture above counted only ids
    # authored by a login other than $SELF_LOGIN, so a codex verdict (posted
    # under that login) and a rework hand-back (which posts nothing) can never
    # reach here. It is review the branch has never been answered against, so
    # the rounds spent before it stop counting — signoff.sh re-baselines its
    # floor at the next verdict, keyed on the batch stamped here. The batch
    # coordinates are the dedup: a reconcile every two minutes sees the same
    # comments until they are answered, and a reset per pass would be no cap.
    reset_key="$max_r.$max_c"
    if [ "$(printf '%s' "$row" | jq -r '(.metadata.signoff_rounds_reset // "") | tostring')" != "$reset_key" ]; then
      RSET=(--set "signoff_rounds_reset=$reset_key")
      undo=""; unparked=0; park_note=""
      # The dispatch tally bounds a runaway: reviews that dispatch and leave no
      # verdict. New operator feedback is the evidence this anchor is not that,
      # and the released rounds cannot be dispatched at all while the tally
      # stands at gate-ensure's ceiling. Its backstop stamp goes with it, since
      # it dedups the escalation for a ceiling that no longer stands.
      while IFS= read -r k; do
        [ -n "${k:-}" ] || continue
        RSET+=(--unset "$k"); undo="${undo:+$undo, }$k"
      done <<TALLY
$(printf '%s' "$row" | jq -r '(.metadata // {}) | keys[]?
  | select(. == "dispatch_count" or startswith("dispatch_backstop."))' 2>/dev/null)
TALLY
      # Retire the cap's own park with it. The hold keeps every dispatch arm off
      # the anchor, and a human route sends this very batch to a visit, so a
      # reset leaving either standing would not be one. signoff_cap is the stamp
      # the cap writes with the hold, and both must still stand: a merge_hold a
      # person put there, or one already lifted by hand, is theirs and stays. A
      # sitting still holding this anchor for a ruling outranks the reset the
      # same way. The cap's own gc.takeaway is not such a decision — it is the
      # sentence the board renders for this park — so it retires with the park,
      # and gc.takeaway_by is what tells it from a sitting's, which is left
      # alone.
      #
      # "theirs and stays" above is the shared predicate, not a bare
      # is_held(merge_hold): the cap's own park is the ONE pairing
      # merge_hold==signoff_cap (the literal string) beside a non-empty
      # signoff_cap (`cap`, read at the top of this iteration off the same
      # row). Any OTHER merge_hold value standing beside signoff_cap — set by
      # hand over an orphaned cap stamp, or a fresh freeze like a release hold
      # — is a person's, and this reset must not retire it, or say in its own
      # note that it did.
      if is_cap_park "$hold" "$cap"; then
        if [ -z "$holding" ]; then
          RSET+=(--unset merge_hold --unset blocked_reason --unset signoff_cap --route "")
          undo="${undo:+$undo, }the merge_hold park on gate $cap, blocked_reason and the human route"
          if [ "$takeaway_by" = signoff ]; then
            RSET+=(--unset gc.takeaway --unset gc.takeaway_at --unset gc.takeaway_by)
            undo="${undo:+$undo, }the cap's takeaway"
          fi
          unparked=1
        fi
        # else: a sitting still holding the anchor for a ruling outranks the
        # reset, same as above — nothing further to say here.
      elif [ -n "$cap" ] && is_held "$hold"; then
        park_note=" No park was retired: merge_hold does not carry the cap's own park value, so it is a person's and stays (signoff_cap=$cap stands beside it, unclaimed by this reset)."
      fi
      if "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
           "${RSET[@]}" --append-notes "pr-facts: operator feedback on PR#$num (review $max_r, comment $max_c; answered through review $rwm, comment $cwm) resets the signoff round cap${undo:+, retiring $undo}. That feedback is review this branch has never been answered against, so the rounds spent before it no longer count against a cap that measures non-convergence.${park_note}" >/dev/null; then
        # The row was read before this write, and the routing choice below
        # reads both fields: a park retired here must not still hold as one.
        [ "$unparked" = 1 ] && { routed=""; hold=""; }
        echo "$PROG: $id — PR#$num operator feedback resets the signoff round cap${undo:+, retiring $undo}"
      else
        echo "$PROG: WARN $id — PR#$num cap reset did not record; the cap stands and the comments still route below. The watermark that routing writes retires this batch, so nothing re-reads it: the anchor stays parked until a ruling retires it (signoff.sh reset)." >&2
      fi
    fi

    # A human already holding this anchor gets the comments; filing work under a
    # live human decision fights it, and a child told to answer comments may have
    # to bring the branch current, which rebase_hold forbids. Absent any of that,
    # and with a pool to route to, the comments become work.
    why=""
    [ -n "$fix_branch" ] || why="the PR head branch is unresolved"
    [ -n "$FIX_POOL" ]   || why="no fix pool is configured"
    is_held "$rhold"        && why="rebase_hold freezes the branch"
    is_held "$hold"         && why="merge_hold is set"
    [ "$routed" = "human" ] && why="the anchor is already routed to a human"
    [ -n "$holding" ]       && why="a sitting is holding it for an operator ruling"
    if [ -n "$why" ]; then choice="visit"; else choice="rework"; fi
    CSRC=$(feedback_reviews "$revs_raw" "$rwm")
    DISP=""
    if [ "$choice" = "rework" ]; then
      # Same allowlist as the CONFLICTING arm's `stale-base-dispatch-mode`: the
      # child may have to bring the branch current before it can push a fix, and
      # only polecat/* is disposable enough to rewrite.
      case "$fix_branch" in
        polecat/*) prepare_mode=rebase ;;
        *)         prepare_mode=merge ;;
      esac
      if [ "$grad" = "true" ]; then prepare_mode=merge; fi
      # Deterministic per batch: the same outstanding feedback names the same
      # child, a later batch names a different one. Both halves of the probe
      # matter — a fully stamped hit means this batch was already dispatched and
      # only the watermark write failed, an unstamped hit is an orphan from a
      # pass whose stamp dropped, and re-creating either mints a twin. The title
      # IS that probe's key, so rewording it strands every child in flight under
      # the old one.
      CTITLE="Address review comments on PR#$num (through review $max_r, comment $max_c)"
      CBODY=$(feedback_body "$revs_raw" "$cmts_live" "$rwm" "$cwm")
      [ -n "$CBODY" ] || CBODY="Unanswered review feedback on PR#$num (through review $max_r, comment $max_c). The bodies could not be rendered; read them at $live_url."
      CBODY="## Unanswered review feedback on PR#$num

$live_url — head $head_oid${CSRC:+, review $CSRC}

Answer every item below: a fix, or a reply on the PR saying why not. One that
asks for a decision you cannot make is an escalation, never a silent close.

$CBODY"
      if ! ckids=$(bd_list --status="$ALL_STATUSES" --title-contains "$CTITLE"); then
        echo "$PROG: $id — PR#$num comment dedup probe failed; nothing dispatched (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      CFIX=$(printf '%s' "$ckids" | jq -r --arg id "$id" '
        [ .[] | select(((.metadata.anchor_bead // "") | tostring) == $id) | .id ] | .[0] // empty' 2>/dev/null)
      if [ -n "$CFIX" ]; then
        echo "$PROG: $id — PR#$num comment rework $CFIX already covers this batch; re-checking its route before the watermark"
      else
        # Live-only, unlike the batch probe above: a CLOSED orphan would take the
        # stamp and the route, hold nothing, and still let the watermark advance
        # past a comment no one ever read.
        CFIX=$(printf '%s' "$ckids" | jq -r --arg live "$LIVE_STATUSES" '
          ($live | split(",")) as $ls
          | [ .[] | select(((.metadata.anchor_bead // "") | tostring) == "")
                  | ((.status // "open") | tostring | ascii_downcase) as $st
                  | select(($ls | index($st)) != null)
                  | .id ] | .[0] // empty' 2>/dev/null)
        if [ -n "$CFIX" ]; then
          echo "$PROG: $id adopting unstamped comment-rework orphan $CFIX for PR#$num (created by a prior pass whose stamp failed)"
        else
          CFIX=$(printf '%s\n' "$CBODY" | gc bd create "$CTITLE" -t task --body-file - --json 2>/dev/null \
                   | jq -r '.id // empty' 2>/dev/null)
        fi
        if [ -z "$CFIX" ]; then
          echo "$PROG: $id could not file the comment rework for PR#$num; retry next pass" >&2
          skipped=$((skipped + 1)); continue
        fi
        CSRCSET=(); [ -z "$CSRC" ] || CSRCSET=(--set-metadata "source_review=$CSRC")
        gc bd update "$CFIX" \
          --set-metadata anchor_bead="$id" \
          --set-metadata branch="$fix_branch" \
          --set-metadata target="$base" \
          --set-metadata rejection_reason="Review feedback on PR#$num is unanswered at head $head_oid. This bead's description carries it verbatim; $live_url is the live copy. Answer every item — a fix, or a reply on the PR saying why not — then push to '$fix_branch'. Do NOT open a new PR: this reworks PR#$num. A comment asking for a decision you cannot make is an escalation, never a silent close." \
          ${CSRCSET[@]+"${CSRCSET[@]}"} \
          --set-metadata prepare_mode="$prepare_mode" \
          --set-metadata merge_strategy=mr \
          --set-metadata existing_pr="$live_url" \
          --set-metadata pr_url="$live_url" \
          --set-metadata pr_number="$num" >/dev/null 2>&1 \
          || echo "$PROG: WARN comment rework $CFIX created but not fully stamped; route it to $FIX_POOL by hand" >&2
        gc bd dep "$CFIX" --blocks "$id" >/dev/null 2>&1 \
          || echo "$PROG: WARN could not attach comment rework $CFIX as a blocks-dep of $id" >&2
        # anchor_bead is the dedup key the probe above reads; an unstamped child
        # is invisible to it, so routing one would twin on the next pass.
        agot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.anchor_bead // empty')
        if [ "$agot" != "$id" ]; then
          echo "$PROG: WARN comment rework $CFIX did not record anchor_bead=$id; left unrouted (retry next pass)" >&2
          skipped=$((skipped + 1)); continue
        fi
      fi
      # An unrouted child still holds the merge through its blocks edge, but no
      # pool can claim it, and the mark would retire the only signal that could
      # re-file it. A CLOSED child is already dispositioned, so refusing on one
      # could never converge. Only a definitively closed status skips the check;
      # an unreadable one still demands both stamps.
      cst=$(gc bd show "$CFIX" --json 2>/dev/null | scrub \
        | jq -r '(.[0].status // "") | tostring | ascii_downcase' 2>/dev/null)
      if [ "$cst" != "closed" ]; then
        # An absent prepare_mode resumes as rebase, so a child routed without it
        # rewrites the very branch the classifier above called shared. Re-stamp
        # rather than refuse: a batch already covered skips the create block, so
        # a child stranded by a dropped stamp could take one nowhere else.
        mgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.prepare_mode // empty' 2>/dev/null)
        if [ "$mgot" != "$prepare_mode" ]; then
          gc bd update "$CFIX" --set-metadata prepare_mode="$prepare_mode" >/dev/null 2>&1 || true
          mgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.prepare_mode // empty' 2>/dev/null)
        fi
        if [ "$mgot" != "$prepare_mode" ]; then
          echo "$PROG: WARN comment rework $CFIX did not record prepare_mode=$prepare_mode; left unrouted and NOT watermarking (an absent mode resumes as rebase, which would rewrite '$fix_branch')" >&2
          skipped=$((skipped + 1)); continue
        fi
        rgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata["gc.routed_to"] // empty' 2>/dev/null)
        if [ "$rgot" != "$FIX_POOL" ]; then
          gc bd update "$CFIX" --set-metadata gc.routed_to="$FIX_POOL" >/dev/null 2>&1 || true
          rgot=$(gc bd show "$CFIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata["gc.routed_to"] // empty' 2>/dev/null)
        fi
        if [ "$rgot" != "$FIX_POOL" ]; then
          echo "$PROG: WARN comment rework $CFIX is NOT routed to $FIX_POOL; NOT watermarking (an unclaimable child with the mark moved past its comments is the silence this arm exists to stop)" >&2
          skipped=$((skipped + 1)); continue
        fi
        gc session wake "$FIX_POOL" >/dev/null 2>&1 || true
      fi
      DISP="rework:$CFIX"
    else
      VKEY="pr-comments.$num.$max_r.$max_c"
      escalate "$id" "$VKEY" \
        "PR#$num ($live_url) carries review feedback nothing has answered (highest: review $max_r, comment $max_c; answered through review $rwm, comment $cwm${CSRC:+; reviews $CSRC}), and the city cannot route work for it because $why. Answer it on the PR, file the rework by hand, or close this visit once it is addressed — the merge is held until then."
      VID=$(visit_for "$id" "$VKEY") || VID=""
      if [ -z "$VID" ]; then
        echo "$PROG: $id — PR#$num has unanswered comments but no visit could be filed or found; NOTHING dispositioned (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      # A blocks edge would close a cycle: escalate.sh already files the visit
      # DEPENDING on its subject (tracks), so an edge back is a two-node loop bd
      # refuses. pr_number is what merge.sh's in-flight-holder probe reads, and
      # it holds the merge until a human closes the visit. anchor_bead is safe
      # beside it — every consumer of that key filters on task_kind=review.
      gc bd update "$VID" \
        --set-metadata anchor_bead="$id" \
        --set-metadata pr_url="$live_url" \
        --set-metadata pr_number="$num" >/dev/null 2>&1 \
        || echo "$PROG: WARN visit $VID not stamped with PR#$num; it will NOT hold the merge — stamp it by hand" >&2
      vgot=$(gc bd show "$VID" --json 2>/dev/null | scrub | jq -r '.[0].metadata.pr_number // empty')
      if [ "$vgot" != "$num" ]; then
        echo "$PROG: WARN visit $VID did not record pr_number=$num; NOT watermarking (a mark past an unheld comment is the silence this arm exists to stop)" >&2
        skipped=$((skipped + 1)); continue
      fi
      DISP="visit:$VID"
    fi
    # The batch boundary goes down WITH the disposition that names it. Derived
    # later, off the disposition, it can be lost: a pass that exits after this
    # stamp leaves the next one free to route a newer batch, and with no record
    # of this one the write-back reads a single range running back to zero and
    # answers these comments from the newer bead. The floor is the mark this
    # transition replaces, which is exactly the span this disposition covers.
    NBATCH=$(jq -rn --arg batch "$obatch" --arg disp "$DISP" \
      --argjson lo "$cwm" --argjson hi "$max_c" '
      def num: if test("^[0-9]+$") then tonumber else error("malformed record") end;
      [ $batch | split(";")[] | select(length > 0)
        | split("|") | if length == 3 then . else error("malformed record") end
        | { disp: .[0], lo: (.[1] | num), hi: (.[2] | num) } ] as $rs
      | ( if ($rs | length) > 0 and $rs[-1].disp == $disp
          then $rs[0:-1] + [ $rs[-1] | .hi = ([ .hi, $hi ] | max) ]
          else $rs + [ { disp: $disp, lo: $lo, hi: ([ $lo, $hi ] | max) } ] end )
      | [ .[] | "\(.disp)|\(.lo)|\(.hi)" ] | join(";")' 2>/dev/null) || NBATCH=""
    if [ -z "$NBATCH" ]; then
      echo "$PROG: WARN $id — PR#$num comment batch history is unreadable; NOT watermarking (a mark past a batch whose range was never recorded lets a later disposition answer these comments)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if "$LIFECYCLE" transition "$id" --to pull_request --expect pull_request \
         --set "pr_comment_watermark=$max_c" --set "pr_review_watermark=$max_r" \
         --set "pr_comment_batch=$NBATCH" \
         --set "pr_comment_disposition=$DISP" >/dev/null; then
      answered=$((answered + 1))
      echo "$PROG: $id — PR#$num review comments routed to $DISP (watermark: review $max_r, comment $max_c)"
    else
      echo "$PROG: WARN $id — PR#$num comments routed to $DISP but the watermark did NOT record; the same batch re-dispatches next pass onto $DISP" >&2
      skipped=$((skipped + 1))
    fi
    continue
  fi

  # --- dismiss our OWN superseded CHANGES_REQUESTED when the gate is green -------
  # Only when every declared gate reads green but GitHub is still red on our own
  # block, left at a commit other than the live head. Never a human's review;
  # skipped when native auto-merge is armed (the dismissal would hand GitHub the
  # landing).
  all_green=1
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')" in none|off|approval) continue ;; esac
    m=$(printf '%s' "$row" | jq -r --arg k "check.$g" '(.metadata[$k] // "") | tostring')
    [ "$m" = "green" ] || all_green=0
  done <<GATES
$(printf '%s' "$checkset" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d')
GATES
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


# --- PR write-back: acknowledge on pickup, reply and resolve on landing --------
# The operator reads the PR, so the PR is where the city answers them.
#
# This sweeps after the dispatch arms rather than inside them, which keeps the
# acknowledgement keyed to durable state instead of to one arm's control flow. A
# comment routed earlier in this same pass is still acknowledged in this pass,
# because the sweep re-reads the anchors. A write that failed is retried by the
# next pass, which an inline one-shot could not be.
#
# pr_comment_disposition is the honesty gate. It is written only once the routing
# has read back, so an anchor carrying it has a bead that really does cover these
# comments. An anchor without one costs a single ledger read and no GitHub call.
# The plan decides over WHOLE threads: it finds the city's own marker in one and
# then asks whether a human has written since. A connection left at its first
# page answers that from a fragment — it can miss a comment the city routed, and
# it can resolve a thread a human replied to past the page boundary. So every
# connection here is read to exhaustion. `gh --paginate` follows exactly one
# cursor, so the reviews and the threads are separate reads rather than one
# nested query, and neither carries a second cursor for it to choose between.
WB_REVIEWS_QUERY='query($owner:String!,$repo:String!,$num:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$num){
      reviews(first:100,after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{id databaseId state body author{login}
          reactionGroups{content viewerHasReacted}}}}}}'
# A thread's own comments stay nested: one read covers every thread short enough
# to fit, which is nearly all of them. Truncation is read off the COUNT rather
# than a nested pageInfo — a thread with more than a page returns exactly a full
# one — so this query holds a single cursor and the top-up below is asked for
# only the threads that need it.
WB_THREADS_QUERY='query($owner:String!,$repo:String!,$num:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$num){
      reviewThreads(first:100,after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{id isResolved viewerCanResolve
          comments(first:100){nodes{id databaseId author{login} body
            reactionGroups{content viewerHasReacted}}}}}}}}'
WB_THREAD_COMMENTS_QUERY='query($id:ID!,$endCursor:String){
  node(id:$id){... on PullRequestReviewThread{
    comments(first:100,after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{id databaseId author{login} body
        reactionGroups{content viewerHasReacted}}}}}}'
# The nested `first:` above, named. A thread that comes back holding this many
# comments is one the top-up has to re-read; change either without the other and
# the long threads quietly stop being paged.
WB_PAGE=100

acked=0; replied=0; resolved=0
# wowing collects the records that end an anchor's pass still owing a write, and
# so have to survive into the next one.
owe() { local i; for i in $(printf '%s' "$1" | tr ',' ' '); do
  case " $wowing " in *" $i "*) : ;; *) wowing="$wowing $i" ;; esac
done; }
# --posture-only answers one question for the merge arm and writes nothing to
# GitHub; the full pass that follows it carries the write-back.
if [ "$POSTURE_ONLY" = 1 ]; then
  WB_ANCHORS=""
elif ! WB_ANCHORS=$(bd_list --status=open --metadata-field merge_result=pull_request); then
  echo "$PROG: write-back sweep skipped — could not re-read the anchors" >&2
  WB_ANCHORS=""
fi
while IFS= read -r wrow; do
  [ -n "${wrow:-}" ] || continue
  wid=$(printf '%s' "$wrow" | jq -r '.id // empty')
  [ -n "$wid" ] || continue
  disp=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_comment_disposition // "") | tostring')
  [ -n "$disp" ] || continue
  wnum=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_number // "") | tostring')
  case "$wnum" in ''|*[!0-9]*) continue ;; esac
  wcwm=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_comment_watermark // "0") | tostring')
  wrwm=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_review_watermark // "0") | tostring')
  case "$wcwm" in ''|*[!0-9]*) wcwm=0 ;; esac
  case "$wrwm" in ''|*[!0-9]*) wrwm=0 ;; esac

  # The watermark is cumulative and pr_comment_disposition holds one batch at a
  # time, so a thread an earlier batch left unresolved still sits at or below the
  # mark. Something routed that thread, so its reaction is honest. No commit of
  # THIS batch answered it, so a reply saying one did is not. The bead that does
  # answer it may not have closed yet, so the batch it covers has to outlive the
  # disposition that named it.
  # pr_comment_batch is that history: one `<disposition>|<exclusive floor>|
  # <inclusive mark>` record per batch, oldest first, joined by ";". Each record
  # is written by the transition that routes its batch, so the range is durable
  # before any later pass can route over it. What is left here is reconciliation:
  # extend the standing record when the mark has moved under the same
  # disposition, and mint one for an anchor whose disposition predates the
  # history, whose single batch runs from zero. A record is dropped once its
  # batch has nothing left owing, and the newest is kept whatever it owes,
  # because its mark is the next batch's floor. The value is read back before it
  # is trusted, the same shape as signoff_dismissed above, and an anchor whose
  # history did not record reacts and answers nothing. It is written ahead of
  # every GitHub read, so an unreadable PR cannot let a batch pass unobserved and
  # leave the floor behind the mark.
  wbatch=$(printf '%s' "$wrow" | jq -r '(.metadata.pr_comment_batch // "") | tostring')
  wbwant=$(jq -rn --arg batch "$wbatch" --arg disp "$disp" --argjson cwm "$wcwm" '
    def num: if test("^[0-9]+$") then tonumber else error("malformed record") end;
    [ $batch | split(";")[] | select(length > 0)
      | split("|") | if length == 3 then . else error("malformed record") end
      | { disp: .[0], lo: (.[1] | num), hi: (.[2] | num) } ] as $rs
    | ( [ 0, ($rs[] | .hi) ] | max ) as $floor
    | ( if ($rs | length) > 0 and $rs[-1].disp == $disp
        then $rs[0:-1] + [ $rs[-1] | .hi = ([ .hi, $cwm ] | max) ]
        else $rs + [ { disp: $disp, lo: $floor, hi: ([ $floor, $cwm ] | max) } ] end )
    | [ .[] | "\(.disp)|\(.lo)|\(.hi)" ] | join(";")' 2>/dev/null) || wbwant=""
  wbatch_ok=1
  if [ -z "$wbwant" ]; then
    wbatch_ok=0
    echo "$PROG: $wid — PR#$wnum comment batch history is unreadable; acknowledging only, nothing replied or resolved this pass" >&2
  elif [ "$wbatch" != "$wbwant" ]; then
    gc bd update "$wid" --set-metadata pr_comment_batch="$wbwant" >/dev/null 2>&1
    wbgot=$(gc bd show "$wid" --json 2>/dev/null | scrub | jq -r '.[0].metadata.pr_comment_batch // empty')
    if [ "$wbgot" != "$wbwant" ]; then
      wbatch_ok=0
      echo "$PROG: $wid — PR#$wnum comment batch range did not record; acknowledging only, nothing replied or resolved this pass" >&2
    fi
  fi

  [ -n "$SELF_LOGIN" ] || {
    echo "$PROG: $wid — PR#$wnum write-back skipped: the acting login is unresolved (every write keys off telling our own comments from a human's)" >&2
    continue
  }
  wbranch=$(printf '%s' "$wrow" | jq -r '.metadata.branch // ""')
  wprurl=$(printf '%s' "$wrow" | jq -r '.metadata.pr_url // ""')

  # Same fail-closed identity read as the dispatch loop: writing to a PR this
  # anchor does not own puts the city's name on a stranger's review thread.
  WPR_JSON=$(gh pr view "$wnum" --repo "$ORIGIN_REPO_Q" \
    --json state,isDraft,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,url 2>/dev/null)
  [ -n "$WPR_JSON" ] || { echo "$PROG: $wid — PR#$wnum view failed; nothing written back (retry next pass)" >&2; continue; }
  wstate=$(printf '%s' "$WPR_JSON" | jq -r '.state // ""')
  wdraft=$(printf '%s' "$WPR_JSON" | jq -r '.isDraft // false')
  whref=$(printf '%s' "$WPR_JSON" | jq -r '.headRefName // ""')
  whead=$(printf '%s' "$WPR_JSON" | jq -r '.headRefOid // ""')
  wurl=$(canon_pr_url "$(printf '%s' "$WPR_JSON" | jq -r '.url // ""')")
  wrepo=$(printf '%s' "$WPR_JSON" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  wcross=$(printf '%s' "$WPR_JSON" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)
  if [ "$(url_repo_q "$wurl")" != "$ORIGIN_REPO_Q" ] \
     || { [ -n "$wprurl" ] && [ "$(canon_pr_url "$wprurl")" != "$wurl" ]; } \
     || [ -z "$wrepo" ] || [ "$wrepo" != "$ORIGIN_REPO" ] || [ "$wcross" != "false" ] \
     || { [ -n "$wbranch" ] && [ "$whref" != "$wbranch" ]; }; then
    echo "$PROG: $wid — PR#$wnum identity did not certify for the write-back; NOTHING written" >&2
    continue
  fi
  [ "$wstate" = "OPEN" ] || continue
  [ "$wdraft" != "true" ] || continue

  # Has the work that answers each batch LANDED? Every record is asked for
  # itself, so a batch superseded before its bead closed is still answered by
  # that bead. Only a rework child can name a commit; a visit is a human's to
  # answer, so it earns the pickup reaction and never a reply. Resolving on the
  # filing rather than the landing would close the thread while the fix is still
  # unwritten.
  wbrecs="[]"
  if [ "$wbatch_ok" = 1 ]; then
    while IFS='|' read -r rdisp rlo rhi; do
      [ -n "${rdisp:-}" ] || continue
      rchild=""; rlanded=""
      case "$rdisp" in
        rework:*)
          rchild="${rdisp#rework:}"
          if [ -n "$rchild" ]; then
            rcst=$(gc bd show "$rchild" --json 2>/dev/null | scrub \
              | jq -r '(.[0].status // "") | tostring | ascii_downcase' 2>/dev/null)
            [ "$rcst" = "closed" ] && [ -n "$whead" ] && rlanded="$whead"
          fi ;;
      esac
      wbrecs=$(printf '%s' "$wbrecs" | jq -c --argjson lo "$rlo" --argjson hi "$rhi" \
        --arg child "$rchild" --arg landed "$rlanded" \
        '. + [ { lo: $lo, hi: $hi, child: $child, landed: $landed } ]')
    done <<WB_RECORDS
$(printf '%s' "$wbwant" | tr ';' '\n')
WB_RECORDS
  fi

  wowner="${ORIGIN_REPO%%/*}"; wname="${ORIGIN_REPO#*/}"
  wrraw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate -f query="$WB_REVIEWS_QUERY" \
    -f owner="$wowner" -f repo="$wname" -F num="$wnum" 2>/dev/null) || wrraw=""
  wtraw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate -f query="$WB_THREADS_QUERY" \
    -f owner="$wowner" -f repo="$wname" -F num="$wnum" 2>/dev/null) || wtraw=""
  if [ -z "$wrraw" ] || [ -z "$wtraw" ]; then
    echo "$PROG: $wid — PR#$wnum review threads unreadable; nothing written back (retry next pass)" >&2
    continue
  fi
  # --paginate emits one document per page; slurp both reads back into one view.
  wview=$(printf '%s\n%s' "$wrraw" "$wtraw" | scrub | jq -sc '{
      reviews: [ .[].data.repository.pullRequest.reviews.nodes[]? ],
      threads: [ .[].data.repository.pullRequest.reviewThreads.nodes[]? ]
    }' 2>/dev/null) || wview=""
  if [ -z "$wview" ] || [ "$wview" = "null" ]; then
    echo "$PROG: $wid — PR#$wnum review threads unreadable; nothing written back (retry next pass)" >&2
    continue
  fi

  # Top up the threads that came back full: those are the ones with more
  # comments than a page, and the plan has to see all of them. A thread that
  # cannot be read to the end leaves the whole anchor to the next pass, because
  # a partial thread is exactly what decides wrongly.
  wtop_ok=1
  while IFS= read -r wtid; do
    [ -n "${wtid:-}" ] || continue
    wcraw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate \
      -f query="$WB_THREAD_COMMENTS_QUERY" -f id="$wtid" 2>/dev/null) || wcraw=""
    wfull=$(printf '%s' "$wcraw" | scrub \
      | jq -sc '[ .[].data.node.comments.nodes[]? ]' 2>/dev/null) || wfull=""
    case "$wfull" in ''|null|'[]') wtop_ok=0; break ;; esac
    wview=$(printf '%s' "$wview" | jq -c --arg t "$wtid" --argjson cs "$wfull" \
      '.threads = [ .threads[] | if .id == $t then .comments = { nodes: $cs } else . end ]' \
      2>/dev/null) || { wtop_ok=0; break; }
    [ -n "$wview" ] || { wtop_ok=0; break; }
  done <<WB_LONG_THREADS
$(printf '%s' "$wview" | jq -r --argjson page "$WB_PAGE" \
   '.threads[]? | select(((.comments.nodes // []) | length) >= $page) | .id' 2>/dev/null)
WB_LONG_THREADS
  if [ "$wtop_ok" != 1 ]; then
    echo "$PROG: $wid — PR#$wnum has a review thread that could not be read to its end; nothing written back (retry next pass)" >&2
    continue
  fi

  # One jq pass decides everything, so the shell below only performs writes.
  #   R <node-id>                          react: routed, not yet reacted to
  #   T <thread-id> <reply> <why> <beads>  the thread, once the work of EVERY
  #     <commit> <records>                 batch it holds has landed. why is ok,
  #                                        live (a human answered after us), or
  #                                        norights (cannot resolve).
  # A comment ABOVE the watermark was never routed and earns nothing: reacting to
  # it would teach the operator that the mark means something it does not. It is
  # still outstanding in the thread it sits in, so a thread holding one waits.
  # Answering that thread from an older batch would resolve it over a request
  # nothing has addressed, and a resolved thread is skipped by every later pass.
  # A thread belongs to every record whose range holds one of its comments and
  # whose disposition names a bead, and it is answered only once all of them have
  # landed: one reply, naming each, over a thread with nothing left outstanding.
  # A thread already carrying our reply marker stays in scope whatever its ids:
  # we claimed it, and a resolve that failed behind a reply still has to be
  # retried. A human who wrote after that marker makes the thread live, which is
  # the reason reported for leaving it open.
  wplan=$(printf '%s' "$wview" | jq -r \
    --arg self "$SELF_LOGIN" --arg reaction "$WB_REACTION" --arg marker "$WB_MARKER" \
    --argjson cwm "$wcwm" --argjson rwm "$wrwm" --argjson recs "$wbrecs" '
    def reacted($rg): [ ($rg // [])[] | select(.content == $reaction and .viewerHasReacted) ] | length > 0;
    def foreign: (.author.login // "") != $self;
    ( [ .reviews[]
        | select(foreign)
        # the states max_r watermarks (COMMENTED + CHANGES_REQUESTED): a body-only
        # veto advances pr_review_watermark and routes a child, so acknowledge it too
        | select((.state // "") | IN("COMMENTED", "CHANGES_REQUESTED"))
        | select(((.body // "") | gsub("[[:space:]]"; "")) != "")
        | select((.databaseId // 0) > 0 and (.databaseId // 0) <= $rwm)
        | select(reacted(.reactionGroups) | not)
        | "R\t" + .id ]
    + [ .threads[] | (.comments.nodes // [])[]
        | select(foreign)
        | select((.databaseId // 0) > 0 and (.databaseId // 0) <= $cwm)
        | select(reacted(.reactionGroups) | not)
        | "R\t" + .id ]
    + [ .threads[]
        | . as $t | ($t.comments.nodes // []) as $cs
        | select(($t.isResolved // false) == false)
        | ([ $cs | to_entries[]
             | select((.value.author.login // "") == $self)
             | select(((.value.body // "") | contains($marker)))
             | .key ] | max) as $mine
        | [ $recs | to_entries[] | . as $r
            | select($r.value.child != "")
            | select([ $cs[] | select(foreign)
                       | select((.databaseId // 0) > $r.value.lo
                                and (.databaseId // 0) <= $r.value.hi) ] | length > 0)
            | $r.key ] as $held
        | (if ($held | length) > 0 then $held
           elif $mine != null and ($recs | length) > 0 and $recs[-1].child != ""
           then [ ($recs | length) - 1 ]
           else [] end) as $own
        | select(($own | length) > 0)
        | [ $own[] | $recs[.] ] as $orecs
        | (if $mine == null then 1 else 0 end) as $needreply
        | (if $mine == null then 0
           else [ $cs | to_entries[] | select(.key > $mine)
                  | select((.value.author.login // "") != $self) ] | length
           end) as $after
        | ([ 0, ($recs[] | .hi) ] | max) as $mark
        | (if $after > 0 then 0
           else [ $cs[] | select(foreign) | select((.databaseId // 0) > $mark) ]
                | length end) as $unrouted
        | (if ([ $orecs[] | select(.landed == "") ] | length) > 0 or $unrouted > 0
           then "-" else $orecs[-1].landed end) as $landed
        | (if $after > 0 then "live"
           elif (($t.viewerCanResolve // false) != true) then "norights"
           else "ok" end) as $why
        | "T\t" + $t.id + "\t" + ($needreply | tostring) + "\t" + $why
          + "\t" + ([ $orecs[] | .child ] | join(", "))
          + "\t" + $landed
          + "\t" + ($own | map(tostring) | join(",")) ]
    ) | .[]' 2>/dev/null) && wplan_ok=1 || { wplan=""; wplan_ok=0; }

  # The reaction is what shows the operator a comment was picked up. A pass that
  # cannot finish the batch's reactions leaves every reply and resolve to the
  # pass that can, so no thread is answered over a comment still awaiting one.
  wreacts=$(printf '%s' "$wplan" | grep -c '^R	' 2>/dev/null) || wreacts=0
  case "$wreacts" in ''|*[!0-9]*) wreacts=0 ;; esac
  wtees=$(printf '%s' "$wplan" | awk -F'\t' '$1 == "T" && $6 != "-" { n++ } END { print n + 0 }') || wtees=0
  case "$wtees" in ''|*[!0-9]*) wtees=0 ;; esac
  wowing=""
  wack_ok=1
  if [ "$wreacts" -gt "$WB_REACT_CAP" ]; then
    wack_ok=0
    echo "$PROG: $wid — PR#$wnum has $wreacts comments awaiting a pickup reaction; acknowledging $WB_REACT_CAP this pass, the rest on the next" >&2
  fi
  wdone=0
  while IFS="$(printf '\t')" read -r act a1 a2 a3; do
    [ "${act:-}" = "R" ] || continue
    [ "$wdone" -lt "$WB_REACT_CAP" ] || continue
    wdone=$((wdone + 1))
    if gh_graphql 'mutation($id:ID!,$c:ReactionContent!){addReaction(input:{subjectId:$id,content:$c}){clientMutationId}}' \
         -f id="$a1" -f c="$WB_REACTION" >/dev/null; then
      acked=$((acked + 1))
    else
      wack_ok=0
      echo "$PROG: $wid — PR#$wnum could not react to $a1; retry next pass" >&2
    fi
  done <<WB_REACTIONS
$wplan
WB_REACTIONS

  if [ "$wack_ok" != 1 ] && [ "$wtees" -gt 0 ]; then
    echo "$PROG: $wid — PR#$wnum still has comments awaiting their pickup reaction; nothing replied or resolved this pass" >&2
  fi
  while IFS="$(printf '\t')" read -r act a1 a2 a3 a4 a5 a6; do  # a3: ok | live | norights
    [ "${act:-}" = "T" ] || continue
    # A tab is IFS whitespace, so read collapses runs of it: every field the plan
    # emits has to be non-empty, and "-" is a batch whose work has not landed.
    if [ "$a5" = "-" ] || [ "$wack_ok" != 1 ]; then owe "$a6"; continue; fi
    wshort=$(printf '%.8s' "$a5")
    if [ "$a2" = "1" ]; then
      wbody="Addressed in $wshort on this PR (${a4:-no bead recorded}).
$WB_MARKER"
      if gh_graphql 'mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){clientMutationId}}' \
           -f t="$a1" -f b="$wbody" >/dev/null; then
        replied=$((replied + 1))
      else
        echo "$PROG: $wid — PR#$wnum could not reply on thread $a1; NOT resolving it (retry next pass)" >&2
        owe "$a6"; continue
      fi
    fi
    # A human who answered our reply is still using the thread; resolving it
    # would close a live conversation, which is theirs to end, not ours.
    case "$a3" in
      live) echo "$PROG: $wid — PR#$wnum thread $a1 has a reply after ours; left unresolved"; continue ;;
      norights) echo "$PROG: $wid — PR#$wnum thread $a1 is not resolvable by this identity; left unresolved" >&2; continue ;;
    esac
    if gh_graphql 'mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
         -f t="$a1" >/dev/null; then
      resolved=$((resolved + 1))
    else
      echo "$PROG: $wid — PR#$wnum could not resolve thread $a1; retry next pass" >&2
      owe "$a6"
    fi
  done <<WB_PLAN
$wplan
WB_PLAN

  # The plan is this pass's own read of GitHub, so a plan that could not be built
  # retires nothing.
  if [ "$wbatch_ok" = 1 ] && [ "$wplan_ok" = 1 ]; then
    wbkeep=$(jq -rn --arg batch "$wbwant" --arg owing "$wowing" '
      ( $batch | split(";") | map(select(length > 0)) ) as $rs
      | ( $owing | split(" ") | map(select(length > 0)) ) as $ow
      | [ $rs | to_entries[] | . as $e
          | select($e.key == (($rs | length) - 1) or ($ow | index($e.key | tostring)) != null)
          | $e.value ] | join(";")' 2>/dev/null) || wbkeep=""
    if [ -n "$wbkeep" ] && [ "$wbkeep" != "$wbwant" ]; then
      gc bd update "$wid" --set-metadata pr_comment_batch="$wbkeep" >/dev/null 2>&1
    fi
  fi
done <<WB_ROWS
$(printf '%s' "$WB_ANCHORS" | jq -c '.[]' 2>/dev/null)
WB_ROWS

if [ "$POSTURE_ONLY" = 1 ]; then
  echo "$PROG: posture-only — $postured postures recorded, $unpostured not current, $skipped skipped"
  # Only this mode's exit code gates anything: refinery-reconcile runs it
  # immediately before merge.sh and holds the merge arm on a non-zero. The full
  # pass runs after merge, where the same rc would gate nothing.
  [ "$unpostured" -eq 0 ] || exit 1
else
  echo "$PROG: $recorded recorded, $postured postures recorded ($unpostured not current), $flagged flagged-to-human, $reworked reworks filed, $answered comment batches routed, $dismissed_n reviews dismissed, $acked comments acknowledged, $replied threads replied, $resolved threads resolved, $skipped skipped"
fi
exit 0
