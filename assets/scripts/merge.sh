#!/usr/bin/env bash
# merge — arm 2 of the merge cadence: the single writer of merged truth.
# For each open pull_request anchor: pinned `gh pr view`, identity gates (right
# repo, not a fork), live anchor re-read (still open, still gating on
# pull_request, still naming this PR by number, url and head branch), then
# either the record for a PR already merged — landing and recording are two
# writes, and a pass killed between them leaves an anchor that says
# pull_request over a PR that landed — or, for an OPEN non-draft PR, the
# merge: validate in order: merge_hold; unanswered review comments (pr_posture,
# read OFF THE ANCHOR, never re-derived from GitHub here); one-anchor-per-PR
# (hold + escalate once —
# fail-closed defense; the structural check is doctor's); non-empty check_set
# (empty is never the 'none' opt-out — an unnormalized anchor holds);
# base == merged_target;
# every declared lane DERIVES green through lane-state.sh (no stored marker; a
# lane with no local review bead is backed by an operator's GitHub approval on
# the PR, the shared fallback); approval (a UNIVERSAL merge rule armed for every
# PR, not a check_set member — satisfied only by a latest APPROVED from an
# account other than the city's, given at any commit, because an approval stands
# across later pushes until it is dismissed; dismissed reviews are dropped before
# each reviewer's latest is taken, so a dismissed approval does not count and a
# dismissed CHANGES_REQUESTED does not hide its author's older approval; a
# standing CHANGES_REQUESTED from any other account vetoes); no unclosed
# rework/review child or open must-fix finding (metadata keys naming this PR AND
# dependency edges, the finding held by its own blocks edge; unreadable holds);
# mergeStateStatus CLEAN (UNSTABLE decided on required contexts only; an UNKNOWN,
# which is GitHub still computing it, read again within one budget per pass);
# generated/seed-audit current at the MERGE RESULT (its inputs re-hashed in the
# tree `git merge-tree` writes, so a render clobbered by a base that moved holds
# and escalates rather than landing). The FULL
# anchor-local authorization set is re-read immediately before the merge; any
# mismatch holds. `gh pr merge --squash --match-head-commit`, then ONE
# lifecycle.sh transition --to merged --close. A failed record exits non-zero
# loudly and the anchor is recovered by the already-merged arm above on a later
# pass — that arm is here, and not left to pr-facts.sh alone, because the arms
# are ordered and a killed pass loses the later ones. A record that keeps
# failing is bounded rather than retried forever: record-failure-cap.sh counts
# the failures on the anchor and escalates past the cap, so a cause no later
# pass can clear reaches a person instead of one stderr line per pass.
# Visit order: anchors whose PR has left the open list, or could land this pass
# by everything read without a per-PR call (draft flag, anchor-local holds,
# approval, the merge state the posture arm recorded), are visited first and
# never paced; --deadline and --cursor pace the rest through a rotation
# (pace-lib.sh).
# Caller: refinery-reconcile.sh, with BEADS_ACTOR projected to the refinery
# identity.
set -u

PROG="merge"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# THE SHELL BELOW IS THE FALLBACK. `gctk merge` (services/gctk) is the ported
# implementation and answers whenever the build order has published a binary;
# this script runs when it has not — a fresh city, a build that failed, a rig
# checkout ahead of the deployed binary. Both must stay correct while the
# fallback stands, so merge.test.sh runs its whole body against both.
# gctk-resolve.sh decides which one answers.
# shellcheck source=gctk-resolve.sh
. "$SCRIPTS_DIR/gctk-resolve.sh" || { echo "$PROG: cannot source gctk-resolve.sh beside this script" >&2; exit 1; }
gctk_resolve merge "$@"

LIFECYCLE="$SCRIPTS_DIR/lifecycle.sh"
# The composable "may this anchor be finalized?" precondition set. An open visit
# tracking the anchor holds its merge — subject-scoped via the anchor's incoming
# tracks edge, never a cascading blocks edge (docs/finalize-gate.md).
FINALIZE_GATE="$SCRIPTS_DIR/finalize-gate.sh"

ESCALATE="$SCRIPTS_DIR/escalate.sh"
# The merged-record retry cap. Both record arms below retry every pass with no
# memory of the last one, so a cause the retry cannot clear needs a writer that
# remembers; this is that writer, shared with pr-facts.sh so the two arms of the
# same repair count against one budget.
RECORD_CAP="$SCRIPTS_DIR/record-failure-cap.sh"
RENDERER="$SCRIPTS_DIR/render-seed-audit.sh"
# The one shared helper every reader derives a lane's green state through, so
# merge and publish never drift on which lane is green (a second implementation
# of the predicate is how two actors come to disagree about one anchor).
LANE_STATE="$SCRIPTS_DIR/lane-state.sh"
# The one resolver of the check index: the merge gate asks it for every declared
# lane (`--through merge` spans all phases), which drops the non-lanes none/off
# and the approval merge rule in one place instead of merge.sh re-deriving it.
REVIEW_CHECKS="$SCRIPTS_DIR/review-checks.sh"
# A missing resolver would make every anchor read as having no lanes — merge's
# fail-open. Require it, so a pack-integrity gap holds the merge rather than passing it.
[ -x "$REVIEW_CHECKS" ] || { echo "$PROG: the check resolver is missing ($REVIEW_CHECKS); merge held" >&2; exit 1; }
# The repository this pass merges into, resolved through git so a run with no
# checkout under it simply has no committed artifact to keep current.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
# Where the freshness probe parks the two commits it needs. Its own namespace,
# so nothing here can move a branch or a remote-tracking ref.
GATE_REF="refs/gc-toolkit/merge-gate"

# --deadline <epoch-secs> and --cursor <file> pace the anchors that cannot land
# this pass (see the visit order below); the ones that can are never paced.
DEADLINE=""; CURSOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --deadline) DEADLINE="${2:-}"; shift 2 ;;
    --cursor)   CURSOR="${2:-}"; shift 2 ;;
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
  # A wrong merge cannot be retried away; merging nothing costs one pass.
  echo "$PROG: cannot resolve this checkout's origin repository; NOTHING is merged this pass" >&2
  exit 0
fi
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"
gh_api_origin() { gh api --hostname "$ORIGIN_HOST" "$@"; }

# Used only to exclude our own reviews; unresolved holds the approval gate.
SELF_LOGIN=$(gh_api_origin user --jq '.login' 2>/dev/null)
if [ -z "$SELF_LOGIN" ]; then
  # Approval is universal, so every PR needs an APPROVED review from an account
  # other than the city's. With no acting login the city cannot tell an external
  # approver from its own review, so the approval gate holds every anchor this
  # pass (fail-closed, below).
  echo "$PROG: WARN acting login unresolved; cannot distinguish an external approver from the city's own review, so the universal approval gate holds every PR this pass" >&2
fi

url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}
canon_pr_url() {
  printf '%s' "${1:-}" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##'
}
is_held() { case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac; }

# reviewThreads is GraphQL-only (gh pr view has no such field), so it is read
# apart from the pinned pr view, in the one arm that needs it. Paginated to
# exhaustion: a count read from a truncated connection decides wrongly.
THREADS_QUERY='query($owner:String!,$repo:String!,$num:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){pullRequest(number:$num){
    reviewThreads(first:100,after:$endCursor){
      pageInfo{hasNextPage endCursor} nodes{isResolved}}}}}'
# Count of unresolved review threads on <pr-number>, echoed as a non-negative
# integer. Returns non-zero without output when the connection could not be
# read — an unreadable connection is never zero, and a BLOCKED diagnosis has to
# say which it is.
unresolved_threads() { # <pr-number>
  local raw n
  raw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate -f query="$THREADS_QUERY" \
    -f owner="${ORIGIN_REPO%%/*}" -f repo="${ORIGIN_REPO#*/}" -F num="$1" 2>/dev/null) || return 1
  [ -n "$raw" ] || return 1
  n=$(printf '%s' "$raw" | scrub | jq -s '
    ([ .[] | .data.repository.pullRequest.reviewThreads ] | map(select(. != null))) as $rt
    | if ($rt | length) == 0 then error("no reviewThreads in response")
      else [ $rt[].nodes[]? | select((.isResolved // false) == false) ] | length end' 2>/dev/null) || return 1
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$n"
}

# Branch-protection facts for <branch>, read from its active rules: whether an
# unresolved review thread blocks a merge (required_review_thread_resolution)
# and how many approving reviews are required. Sets PROT_STATE=known|unknown;
# when known, PROT_THREAD_REQ=true|false and PROT_APPROVALS to the required
# count. An unreadable read is `unknown`, never a zero requirement — naming a
# BLOCKED cause off `unknown` would be a guess.
review_gates_for() { # <branch>
  local b="$1" rules rrc
  PROT_STATE=""; PROT_THREAD_REQ="false"; PROT_APPROVALS="0"
  rules=$(gh_api_origin "repos/$ORIGIN_REPO/rules/branches/$b" 2>/dev/null); rrc=$?
  if [ "$rrc" -ne 0 ] || ! printf '%s' "$rules" | jq -e 'type == "array"' >/dev/null 2>&1; then
    PROT_STATE="unknown"; return 0
  fi
  PROT_THREAD_REQ=$(printf '%s' "$rules" | jq -r '
    [ .[] | select(type == "object") | select((.type // "") == "pull_request")
      | .parameters.required_review_thread_resolution // false ] | any')
  PROT_APPROVALS=$(printf '%s' "$rules" | jq -r '
    [ .[] | select(type == "object") | select((.type // "") == "pull_request")
      | .parameters.required_approving_review_count // 0 ] | max // 0')
  case "$PROT_THREAD_REQ" in true|false) : ;; *) PROT_THREAD_REQ="false" ;; esac
  case "$PROT_APPROVALS" in ''|*[!0-9]*) PROT_APPROVALS="0" ;; esac
  PROT_STATE="known"
}

# Record the machine axis this pass reached, at the head it was read at. Every
# hold below already decides it and spends the answer on a log line; this keeps
# it, so a reader learns whether an anchor is moving without re-implementing
# these predicates. lifecycle.sh owns the @<since> component and preserves it
# across a pass that reaches the same verdict at the same head.
#
# --route carries the anchor's own route back: recording a verdict is an
# observation, not a routing decision, and an omitted --route would let a
# detached state's default clear a route this pass never looked at.
#
# Every non-blocked verdict clears pr.machine_reason: the reason belongs only
# beside a `blocked` verdict (record_blocked writes the pair), so a stale one
# never lingers under a settled or progressing row, where the board would not
# read it anyway.
record_machine() { # <anchor-id> <value> <head-oid> <current-route>
  [ -n "${3:-}" ] || return 0
  "$LIFECYCLE" transition "$1" --to pull_request --expect pull_request \
    --route "${4:-}" --set-dated "pr.machine=$2@$3" --unset pr.machine_reason >/dev/null 2>&1 && return 0
  echo "$PROG: WARN $1 machine axis '$2@$3' did not record; the board reads it as unknown until the next pass" >&2
}

# Record a `blocked` verdict AND the sentence naming its cause, in one write. A
# blocked anchor cannot merge without a person and is not waiting on a review, so
# the board owes it to the operator as needs-attention rather than folding it
# into the settled tail. The reason is plain, not dated: the board reads it only
# while the verdict is `blocked`, and record_machine clears it on any other one.
record_blocked() { # <anchor-id> <head-oid> <current-route> <reason>
  [ -n "${2:-}" ] || return 0
  "$LIFECYCLE" transition "$1" --to pull_request --expect pull_request \
    --route "${3:-}" --set-dated "pr.machine=blocked@$2" --set "pr.machine_reason=$4" >/dev/null 2>&1 && return 0
  echo "$PROG: WARN $1 machine axis 'blocked@$2' did not record; the board reads it as unknown until the next pass" >&2
}

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=pace-lib.sh
. "$_bd_lib_dir/pace-lib.sh" || { echo "cannot source pace-lib.sh beside this script" >&2; exit 1; }
anchor_row() { # live {status, meta}; empty = unreadable, never an all-default row
  gc bd show "$1" --json 2>/dev/null | scrub \
    | jq -c '.[0] | select(. != null) | select(.metadata != null)
             | {status: (.status // ""), meta: .metadata}' 2>/dev/null
}

# The repository an anchor's pr_url names, case-folded, "?" when the url is
# absent or unparseable (mirrors url_repo_q). Shared between the duplicate-
# anchor guard and the in-flight holder filter so the two repo-qualified keys
# cannot drift: "?" is the fail-closed wildcard, so an anchor that names no
# repository still collides with every anchor of its number.
REPO_Q_DEF='
  def repo_q: # "?" = names no repository
    [ ((. // "") | tostring | gsub("[[:space:]]";"") | ascii_downcase)
      | capture("^[a-z][a-z0-9+.-]*://(?<h>[^/]+)/(?<o>[^/]+/[^/]+)/pull/[0-9]") ]
    | .[0] | if . == null then "?" else (.h + "/" + .o) end;
'

# The three anchor-local holds the merge validates first, as jq: an operator's
# merge_hold, review comments nothing has answered (the posture pr-facts.sh
# records), and a check_set never normalized. Shared by the visit order and the
# terminal re-read, so the two read each hold the same way.
ANCHOR_HOLDS_DEF='
  def hold_set: ((. // "") | tostring) as $v
    | (["", "false", "False", "FALSE", "0", "null"] | index($v)) == null;
  def comments_unanswered: ((. // "") | tostring) | startswith("commented@");
  def no_check_set: ((. // "") | tostring | gsub("[[:space:],]"; "")) == "";
'

# The approval rule over a list of reviews in the REST shape, REVIEW_VERDICT_DEF:
# review_verdict($self) yields {veto, approver}, each the first such login or
# empty. Shared by the approval gate and the visit order, so the two never
# disagree on approval, and with pr-facts.sh, whose conflict arm brings only an
# approved PR current.
# shellcheck source=review-verdict.sh
. "$_bd_lib_dir/review-verdict.sh" || { echo "cannot source review-verdict.sh beside this script" >&2; exit 1; }

# The first declared lane that does not DERIVE green, through lane-state.sh.
# Prints that lane; empty stdout with a zero exit means every declared lane is
# green. A non-zero exit is a lane the store would not read, which the caller
# holds on and never reads as all-green. The derivation is the shared one every
# reader uses: a lane greens from its own local approve-review bead, or, when it
# has none, from an operator's GitHub approval on the anchor's PR (an approval
# names no check, so it backs every lane). The lane is compared to no head: green
# is a state of the lane, and a commit landing on the branch neither clears it
# nor buys a review. The human approval the merge separately requires is the
# universal approval rule enforced below, required of every PR.
first_notgreen_lane() { # <anchor-id> <check_set>
  local anchor="$1" cs="$2" lane lanes
  # The resolver's exit status is load-bearing. A resolver that dies mid-run
  # prints nothing, and an empty lane list reads as "every lane green" — the
  # merge would then proceed on approval alone. Capture the status and fail
  # closed (unreadable, the caller holds) rather than reading a crash as a pass.
  lanes=$("$REVIEW_CHECKS" --resolve --check-set "$cs" --through merge 2>/dev/null) || return 2
  while IFS= read -r lane; do
    [ -n "$lane" ] || continue
    "$LANE_STATE" green --anchor "$anchor" --lane "$lane"
    case $? in
      0) ;;                                   # green; next lane
      1) printf '%s\n' "$lane"; return 0 ;;   # not green; hold, name it
      *) return 2 ;;                          # unreadable; the caller holds
    esac
  done <<LANES
$lanes
LANES
  return 0
}

# Which status checks actually gate <branch>: rulesets + classic protection via
# the branch object (the protection endpoint needs admin and 404s ambiguously).
# pr-facts.sh's red-check arm routes on the same gating set this holds on, so it
# carries a byte-identical copy between the markers below; a test proves the two
# never drift.
REQ_STATE=""; REQ_CONTEXTS=""
# >>> required-contexts-for
required_contexts_for() { # <branch>
  local b="$1" rules branch rrc brc
  REQ_STATE=""; REQ_CONTEXTS=""
  rules=$(gh_api_origin "repos/$ORIGIN_REPO/rules/branches/$b" 2>/dev/null); rrc=$?
  branch=$(gh_api_origin "repos/$ORIGIN_REPO/branches/$b" 2>/dev/null); brc=$?
  if [ "$rrc" -ne 0 ] || ! printf '%s' "$rules" | jq -e 'type == "array"' >/dev/null 2>&1 \
     || [ "$brc" -ne 0 ] || ! printf '%s' "$branch" | jq -e 'type == "object" and has("name")' >/dev/null 2>&1; then
    REQ_STATE="unknown"; return 0
  fi
  REQ_CONTEXTS=$( { printf '%s' "$rules" | jq -r '
      [ .[] | select(type == "object") | select((.type // "") == "required_status_checks")
        | (.parameters.required_status_checks // [])[] | (.context // empty) ] | .[]' 2>/dev/null
    printf '%s' "$branch" | jq -r '
      [ (.protection.required_status_checks.contexts // [])[],
        ((.protection.required_status_checks.checks // [])[] | (.context // empty)) ] | .[]' 2>/dev/null
  } | sed '/^$/d' | sort -u)
  REQ_STATE="known"
}
# <<< required-contexts-for

ANCHORS=$(bd_list --status=open --metadata-field merge_result=pull_request) || {
  echo "$PROG: could not enumerate gating anchors; failing loudly rather than merging on a partial view" >&2
  exit 1
}
[ "$ANCHORS" != "[]" ] || { echo "$PROG: no gating anchors"; exit 0; }

# --- visit order: what can land this pass first, the rest in rotation ---------
# This arm's cost grows with the PR set, and the pass that runs it has a budget,
# so a deadline or a kill can stop it part-way. What it must never defer is a
# landing. So every anchor is visited first, and the deadline never stops that
# group, unless something read without a per-PR call already rules its merge
# out this pass:
#   - its PR is a draft, or the acting login is unresolved (the approval gate
#     then holds every PR);
#   - one of the three anchor-local holds stands (ANCHOR_HOLDS_DEF);
#   - the approval rule (REVIEW_VERDICT_DEF), applied to each account's latest
#     APPROVED or CHANGES_REQUESTED review, finds a veto or no approval;
#   - the merge state pr-facts.sh recorded at the PR's live head, in the
#     posture arm that runs right before this one, is one the merge below never
#     proceeds on: anything but CLEAN, UNSTABLE, or UNKNOWN, the state GitHub
#     reports until it has computed one.
# Those anchors are visited in id order after the cursor, wrapping
# (pace-lib.sh), until the deadline: a visit there refreshes a verdict and
# nothing lands. An anchor whose PR has left the open list (merged, which owes
# the record, or closed) is visited first. A PR whose state moves after these
# reads keeps the group they gave it until the next pass reads it again.
# One paginated GraphQL read answers every open PR's draft flag, head and
# latest reviews. It asks for no merge state, because GitHub computes that per
# PR on request, and asked for a hundred PRs at once it times out. When the read
# fails, every anchor joins the first group and the pass is not paced at all.
OPEN_PRS_QUERY='query($owner:String!,$repo:String!,$endCursor:String){
  repository(owner:$owner,name:$repo){
    pullRequests(states:OPEN,first:100,after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{number isDraft headRefOid
        latestOpinionatedReviews(first:100){nodes{state submittedAt databaseId author{login}}}}}}}'
landing_rows=$(printf '%s' "$ANCHORS" | jq -c '.[]' 2>/dev/null)
rest_rows=""
open_raw=$(gh api graphql --hostname "$ORIGIN_HOST" --paginate -f query="$OPEN_PRS_QUERY" \
  -f owner="${ORIGIN_REPO%%/*}" -f repo="${ORIGIN_REPO#*/}" 2>/dev/null) || open_raw=""
if OPEN_PRS=$(printf '%s' "$open_raw" | scrub | jq -sc '
       [ .[] | .data.repository.pullRequests ] as $pages
       | if ($pages | length) == 0 or ([ $pages[] | select(. == null) ] | length) > 0
         then error("no pullRequests in response") else [ $pages[].nodes[]? ] end' 2>/dev/null) \
   && split_rows=$(printf '%s' "$ANCHORS" | jq -r --argjson open "$OPEN_PRS" --arg self "$SELF_LOGIN" \
        "$ANCHOR_HOLDS_DEF$REVIEW_VERDICT_DEF"'
        ($open | map({key: (.number | tostring), value: .}) | from_entries) as $pr
        | .[] | (.metadata // {}) as $m
        | (($m.pr_number // "") | tostring) as $n
        | (($m.pr_merge_state // "") | tostring | split("@")) as $ms
        | (if ($pr | has($n) | not) then "landing"
           elif $self == "" or ($pr[$n].isDraft // false) then "rest"
           elif ($m.merge_hold | hold_set) or ($m.pr_posture | comments_unanswered)
                or ($m.check_set | no_check_set) then "rest"
           elif ([ $pr[$n].latestOpinionatedReviews.nodes[]?
                   | { user: { login: (.author.login // "") }, state,
                       submitted_at: (.submittedAt // ""), id: (.databaseId // 0) } ]
                 | review_verdict($self) | .veto != "" or .approver == "") then "rest"
           elif ($ms[1] // "") != "" and $ms[1] == ($pr[$n].headRefOid // "")
                and (["CLEAN", "UNSTABLE", "UNKNOWN"] | index($ms[0])) == null then "rest"
           else "landing" end) + "\t" + tojson' 2>/dev/null); then
  landing_rows=$(printf '%s\n' "$split_rows" | awk -F'\t' '$1 == "landing" { print $2 }')
  rest_rows=$(printf '%s\n' "$split_rows" | awk -F'\t' '$1 == "rest" { print $2 }' | pace_order "$CURSOR")
else
  echo "$PROG: WARN open-PR list unreadable; every anchor is visited this pass, unpaced" >&2
fi
landing_n=$(printf '%s' "$landing_rows" | awk 'NF { n++ } END { print n + 0 }')
rest_n=$(printf '%s' "$rest_rows" | awk 'NF { n++ } END { print n + 0 }')

merged=0; recovered=0; held=0; skipped=0; record_failed=0
pace_start "$CURSOR" "$DEADLINE"
while IFS= read -r tagged; do
  [ -n "${tagged:-}" ] || continue
  group="${tagged%%$'\t'*}"
  row="${tagged#*$'\t'}"
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '(.metadata.pr_number // "") | tostring')
  [ -n "$id" ] || continue
  case "$num" in ''|*[!0-9]*) skipped=$((skipped + 1)); continue ;; esac
  pace_visit "$group" "$id"; case $? in 1) continue ;; 2) break ;; esac

  # --- pinned PR read --------------------------------------------------------
  PR_JSON=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json "$PR_FIELDS" 2>/dev/null)
  if [ -z "$PR_JSON" ]; then
    echo "$PROG: PR#$num view failed; merge held (anchor $id, retry next pass)"
    held=$((held + 1)); continue
  fi
  state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
  is_draft=$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')
  base=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // ""')
  head_ref=$(printf '%s' "$PR_JSON" | jq -r '.headRefName // ""')
  head_oid=$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // ""')
  merge_state=$(printf '%s' "$PR_JSON" | jq -r '.mergeStateStatus // ""')
  live_url=$(canon_pr_url "$(printf '%s' "$PR_JSON" | jq -r '.url // ""')")
  head_repo=$(printf '%s' "$PR_JSON" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  head_cross=$(printf '%s' "$PR_JSON" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)

  # --- identity gates ---------------------------------------------------------
  if [ "$(url_repo_q "$live_url")" != "$ORIGIN_REPO_Q" ]; then
    echo "$PROG: PR#$num answered from '$(url_repo_q "$live_url")', not '$ORIGIN_REPO_Q'; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  if [ -z "$head_repo" ] || [ -z "$head_cross" ]; then
    echo "$PROG: PR#$num head identity unreadable; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  if [ "$head_repo" != "$ORIGIN_REPO" ] || [ "$head_cross" != "false" ]; then
    echo "$PROG: PR#$num is opened from '$head_repo' (cross=$head_cross), not this repository's own branch; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # Closed-unmerged and draft PRs are pr-facts.sh's to record; this arm merges
  # an OPEN non-draft PR and records one already merged.
  if [ "$state" != "MERGED" ]; then
    [ "$state" = "OPEN" ] || { skipped=$((skipped + 1)); continue; }
    [ "$is_draft" != "true" ] || { skipped=$((skipped + 1)); continue; }
  fi

  # --- live anchor re-read: identity, ahead of either write -------------------
  # The enumerated row is a snapshot taken before the PR read, and a write
  # landing in that gap can leave the anchor on a different PR. Both arms below
  # write merged truth about THIS PR onto this anchor, so both stand on the
  # same check: still open, still gating on pull_request, and still naming this
  # PR by number, url and head branch. None of that is covered by --expect,
  # which sees only the state.
  fresh=$(anchor_row "$id")
  if [ -z "$fresh" ]; then
    echo "$PROG: anchor $id re-read failed; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  fstatus=$(printf '%s' "$fresh" | jq -r '.status | ascii_downcase')
  fresult=$(printf '%s' "$fresh" | jq -r '.meta.merge_result // ""')
  fpr=$(printf '%s' "$fresh" | jq -r '(.meta.pr_number // "") | tostring')
  if [ "$fstatus" != "open" ] || [ "$fresult" != "pull_request" ] || [ "$fpr" != "$num" ]; then
    echo "$PROG: anchor $id changed since enumeration (status='$fstatus' merge_result='$fresult' pr='$fpr'); skip" >&2
    skipped=$((skipped + 1)); continue
  fi
  prurl=$(printf '%s' "$fresh" | jq -r '.meta.pr_url // ""')
  abranch=$(printf '%s' "$fresh" | jq -r '.meta.branch // ""')
  if [ -n "$prurl" ] && [ "$(canon_pr_url "$prurl")" != "$live_url" ]; then
    echo "$PROG: anchor $id records pr_url '$prurl' but PR#$num is '$live_url'; merge held — operator must repair"
    held=$((held + 1)); continue
  fi
  if [ -n "$abranch" ] && [ "$head_ref" != "$abranch" ]; then
    echo "$PROG: anchor $id records branch '$abranch' but PR#$num is opened from '$head_ref'; merge held — operator must repair"
    held=$((held + 1)); continue
  fi

  # --- a PR already merged: the record, not the merge -------------------------
  # Landing and recording are two writes with a gap between them, and a pass
  # killed at its timeout can fall in that gap: the PR is merged, the anchor
  # still says pull_request, and the bead reads as in flight forever. This arm
  # carries the repair rather than delegating it, because the arms are ordered
  # and a killed pass loses the later ones — a recovery downstream of the merge
  # is reached least often exactly when it is needed most. Here it is reached
  # whenever the merge that strands a record is, and it costs one `gh pr view`
  # on the anchors that need it.
  #
  # It stands on the identity gates and the re-read above; --expect closes what
  # is left of the window, re-reading the anchor and refusing anything that has
  # moved off pull_request. $base is the branch the PR actually landed on,
  # which is the fact to record.
  if [ "$state" = "MERGED" ]; then
    merge_oid=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json mergeCommit 2>/dev/null \
      | scrub | jq -r '.mergeCommit.oid // ""')
    if [ -z "$merge_oid" ]; then
      # Never record an empty merged_sha (I5: closed anchor => merged+merged_sha).
      echo "$PROG: WARN PR#$num is MERGED but the mergeCommit read came back empty; recording merged_sha=unverified:PR#$num" >&2
      merge_oid="unverified:PR#$num"
    fi
    case "$merge_oid" in
      unverified:*) short="$merge_oid" ;;
      *) short=$(printf '%.8s' "$merge_oid") ;;
    esac
    if "$LIFECYCLE" transition "$id" --to merged --expect pull_request --close \
         --set "merged_sha=$merge_oid" \
         --unset merge_record_failures \
         --append-notes "Merged to $base at $short (record recovered by merge)"; then
      recovered=$((recovered + 1))
      echo "$PROG: recovered $id — PR#$num was already merged to $base at $short; the record had not landed"
    else
      echo "$PROG: PR#$num is MERGED but the record failed for $id; retry next pass" >&2
      record_failed=$((record_failed + 1))
      [ -x "$RECORD_CAP" ] && "$RECORD_CAP" "$id" "$num" "$merge_oid" "$base" || true
    fi
    continue
  fi

  # --- the rest of the anchor-local authorization set, off the same row -------
  # Only the merge consults these; the record above needs none of them.
  target=$(printf '%s' "$fresh" | jq -r '.meta.merged_target // ""')
  hold=$(printf '%s' "$fresh" | jq -r '.meta.merge_hold // ""')
  checkset=$(printf '%s' "$fresh" | jq -r '.meta.check_set // ""')
  posture=$(printf '%s' "$fresh" | jq -r '.meta.pr_posture // ""')
  aroute=$(printf '%s' "$fresh" | jq -r '.meta["gc.routed_to"] // ""')

  # --- validate, in order -------------------------------------------------------
  # Empty/absent check_set is NEVER "no checks": the declared checkless opt-out is
  # the 'none' sentinel; empty means never normalized (gate-ensure stamps the
  # default). Fail closed rather than merge ungated.
  if [ -z "$(printf '%s' "$checkset" | tr -d '[:space:],')" ]; then
    echo "$PROG: PR#$num anchor $id has no normalized check_set (empty is never the 'none' opt-out); merge held"
    held=$((held + 1)); continue
  fi
  if is_held "$hold"; then
    # signoff.sh's cap parks an anchor with merge_hold=signoff_cap (the
    # literal string) and stamps signoff_cap beside it. That pairing —
    # shared with gate-ensure.sh's identical predicate — is ungreenable by
    # anything the cadence will do — the release is a person's — so it alone
    # is the wedge. An operator's own hold (merge_hold=true) is not, even
    # beside a stale orphan signoff_cap left over from an earlier park.
    if [ "$hold" = "signoff_cap" ] && [ -n "$(printf '%s' "$fresh" | jq -r '.meta.signoff_cap // ""')" ]; then
      record_machine "$id" "wedged-exception" "$head_oid" "$aroute"
    fi
    echo "$PROG: PR#$num merge_hold set (operator gate); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # pr-facts.sh records the posture; this reads it and never asks GitHub. What
  # makes that read current is the cadence: refinery-reconcile runs
  # `pr-facts.sh --posture-only` immediately before this arm, and holds this one
  # for the pass when that arm could not make a posture current. An ABSENT
  # posture therefore never holds here — the hold sits in the driver, which is
  # the only place that can tell "no comment" from "could not read". The value
  # is not head-matched on purpose: a comment survives a head move.
  case "$posture" in
    commented@*)
      echo "$PROG: PR#$num carries review comments nothing has answered ($posture); merge held (anchor $id, pr-facts routes them)"
      held=$((held + 1)); continue ;;
  esac
  # One-anchor-per-PR: fail-closed defense (doctor/check-one-anchor-per-pr is
  # the structural check). This anchor and each same-number "other" are both
  # keyed by the repository their OWN pr_url names (repo_q, shared with the
  # in-flight holder filter). A pr_url that is absent or unparseable names no
  # repository ("?") and is a wildcard on EITHER side: this anchor's own missing
  # url makes it collide with every same-number anchor, just as a URL-less other
  # collides with it. Two anchors that name DIFFERENT concrete repositories are
  # distinct PRs and do not collide. A match, or a "?" on either side, is a
  # duplicate that holds EVERY anchor of the PR.
  dups=$(bd_list --status=open --metadata-field merge_result=pull_request) || {
    echo "$PROG: PR#$num duplicate-anchor read failed; merge held (anchor $id)"
    held=$((held + 1)); continue
  }
  others=$(printf '%s' "$dups" | jq -r --arg id "$id" --arg num "$num" --arg ourl "$prurl" \
    "$REPO_Q_DEF"'
    ($ourl | repo_q) as $ours
    | [ .[] | select(.id != $id)
        | select(((.metadata.pr_number // "") | tostring) == $num)
        | (.metadata.pr_url | repo_q) as $rq
        | select($ours == "?" or $rq == "?" or $rq == $ours)
        | .id ] | join(",")' 2>/dev/null)
  if [ -n "$others" ]; then
    echo "$PROG: PR#$num is claimed by more than one open anchor ($id + $others); merge held — close/demote the duplicate (doctor check-one-anchor-per-pr owns the structure)"
    [ -x "$ESCALATE" ] && "$ESCALATE" --subject "$id" --key "one-anchor-per-pr.$num" \
      --message "PR#$num ($live_url) is claimed by multiple open anchors ($id, $others); every anchor of this PR is held until exactly one remains." >/dev/null 2>&1 || true
    held=$((held + 1)); continue
  fi
  if [ -n "$target" ] && [ -n "$base" ] && [ "$target" != "$base" ]; then
    echo "$PROG: PR#$num base '$base' != merged_target '$target' (retargeted); merge held (anchor $id, pr-facts escalates)"
    held=$((held + 1)); continue
  fi
  if ! ng=$(first_notgreen_lane "$id" "$checkset"); then
    echo "$PROG: PR#$num lane state unreadable on anchor $id; merge held"
    held=$((held + 1)); continue
  fi
  if [ -n "$ng" ]; then
    # A lane short of green is one a review is due to raise. The cap's park is
    # not reached here: it holds above, on merge_hold.
    record_machine "$id" "progressing" "$head_oid" "$aroute"
    echo "$PROG: PR#$num lane '$ng' does not derive green; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- unclosed rework/review children: metadata keys AND dependency edges ------
  by_pr=$(bd_list --metadata-field pr_number="$num" --status="$LIVE_STATUSES") || {
    echo "$PROG: PR#$num referencing-bead read failed; merge held (anchor $id)"
    held=$((held + 1)); continue
  }
  # A probe that exited non-zero is unreadable whatever it printed — bd_list's
  # contract for the list reads, since a failed read can print an empty array.
  children=$(gc bd dep list "$id" --direction=up -t parent-child --json 2>/dev/null) || children=""
  blockers=$(gc bd dep list "$id" --direction=down -t blocks --json 2>/dev/null) || blockers=""
  children=$(printf '%s' "$children" | scrub)
  blockers=$(printf '%s' "$blockers" | scrub)
  if ! printf '%s' "$children" | jq -e 'type == "array"' >/dev/null 2>&1 \
     || ! printf '%s' "$blockers" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$PROG: PR#$num dependency probe unreadable; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # A pr_number holder is qualified by the repository its own pr_url names: bd
  # matches the bare number, so a bead naming that number in ANOTHER repository
  # would otherwise hold this merge. Unknown is not foreign — a row whose url is
  # absent or unparseable names no repository and still holds; only a url that
  # resolves elsewhere is dropped. pr_number holders also drop other anchors
  # (the dup guard's business) and explicit tracking_only opt-outs; a dep-edge
  # holder holds regardless — the edge is the claim, and it is local by
  # construction.
  if ! inflight=$(printf '%s\n%s\n%s' "$by_pr" "$children" "$blockers" | jq -sr --arg id "$id" --arg live "$LIVE_STATUSES" --arg repo "$ORIGIN_REPO_Q" \
    "$REPO_Q_DEF"'
    ($live | split(",")) as $ls
    | ($repo | ascii_downcase) as $ours
    | [ (.[0][] | . + {via: "pr"}), (.[1][] | . + {via: "dep"}), (.[2][] | . + {via: "dep"}) ]
    | [ .[] | select(.id != $id)
        | ((.status // "open") | ascii_downcase) as $st
        | select(($ls | index($st)) != null)
        | ((.metadata.merge_result // "") | tostring) as $mr
        | ((.metadata.tracking_only // "") | tostring | ascii_downcase) as $t
        | (.metadata.pr_url | repo_q) as $rq
        | select(.via == "dep" or ($mr == "" and ((["","false","0","null"] | index($t)) != null)
                                   and ($rq == "?" or $rq == $ours)))
        | ((.metadata.task_kind // "") | tostring) as $tk
        | ((.metadata["finding.disposition"] // "") | tostring) as $fd
        | (if $tk == "finding" then (if $fd != "" then "\($fd) finding" else "finding" end)
           else "unclosed rework/review bead" end) as $kind
        | "\($kind) \(.id) (\($st))" ]
    | .[0] // empty' 2>/dev/null); then
    echo "$PROG: PR#$num in-flight holder filter unreadable; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  if [ -n "$inflight" ]; then
    # An open blocker is only `progressing` when a POOL is behind it. The route
    # is the discriminator: a rework or review child carries one and will be
    # claimed, while an ordinary prerequisite and the demand bead that makes an
    # anchor `asking` carry none and no automated actor will touch them.
    pool_holder=$(printf '%s' "$blockers" | jq -r --arg live "$LIVE_STATUSES" '
      ($live | split(",")) as $ls
      | [ .[] | select(type == "object")
          | select((((.status // "open") | ascii_downcase) as $st | ($ls | index($st)) != null))
          | ((.metadata["gc.routed_to"] // "") | tostring) as $r
          | select($r != "" and $r != "human")
          | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$pool_holder" ]; then
      record_machine "$id" "progressing" "$head_oid" "$aroute"
    else
      # No pool is behind it. A human-routed blocker is the demand the board
      # already surfaces as `asking` from the edge itself, so leave the axis alone
      # there. An UNROUTED open blocker is the gap: no automated actor will claim
      # it and no `asking` edge names it, so the merge is stuck until a person
      # clears it. Record `blocked` naming the holder, so the board stops reading
      # it as awaiting-review.
      stuck_holder=$(printf '%s' "$blockers" | jq -r --arg live "$LIVE_STATUSES" '
        ($live | split(",")) as $ls
        | [ .[] | select(type == "object")
            | select((((.status // "open") | ascii_downcase) as $st | ($ls | index($st)) != null))
            | select(((.metadata["gc.routed_to"] // "") | tostring) == "")
            | .id ] | .[0] // empty' 2>/dev/null)
      [ -n "$stuck_holder" ] && record_blocked "$id" "$head_oid" "$aroute" \
        "held by $inflight — an unrouted blocker no automated actor will clear"
    fi
    echo "$PROG: PR#$num held by $inflight; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- open visit on this anchor: a person owes a conversation before finalize ---
  # Subject-scoped via the anchor's incoming tracks edge; a visit is non-blocking,
  # so this holds THIS anchor's merge without touching its children or readiness.
  # Fail-closed: an unreadable probe holds, like every probe above.
  if ! fg_reason=$("$FINALIZE_GATE" check "$id" 2>/dev/null); then
    echo "$PROG: PR#$num ${fg_reason:-finalize gate refused (fail-closed)}; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- approval ------------------------------------------------------------------
  reviews=$(gh_api_origin --paginate "repos/$ORIGIN_REPO/pulls/$num/reviews?per_page=100" \
    --jq '.[]' 2>/dev/null); rrc=$?
  if [ "$rrc" -ne 0 ]; then
    echo "$PROG: PR#$num reviews history read failed; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # The approval rule (REVIEW_VERDICT_DEF): each non-self reviewer's latest
  # APPROVED or CHANGES_REQUESTED review, dismissed reviews dropped first.
  rstate=$(printf '%s' "$reviews" | jq -cs --arg self "$SELF_LOGIN" "$REVIEW_VERDICT_DEF"'
    review_verdict($self)' 2>/dev/null)
  if [ -z "$rstate" ]; then
    echo "$PROG: PR#$num reviews history unreadable; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  veto=$(printf '%s' "$rstate" | jq -r '.veto // ""')
  if [ -n "$veto" ]; then
    # A human's standing NO holds every candidate, whatever the check_set says.
    # The in-flight arm above already held every anchor a finding, fix unit,
    # review, or blocker is still moving, so reaching here means the cadence has
    # run dry under a veto GitHub keeps standing across pushes and the city never
    # dismisses. That settled tail is the operator's to clear by re-reviewing:
    # record `settled`, whose owed rule reads the posture axis's standing
    # changes_requested and puts the row on their queue. A veto with a fix unit
    # still in flight never reaches here — the in-flight arm holds it at
    # `progressing`.
    record_machine "$id" "settled" "$head_oid" "$aroute"
    echo "$PROG: PR#$num reviewer '$veto' has a standing CHANGES_REQUESTED and the cadence has run dry; merge held for re-review (anchor $id)"
    held=$((held + 1)); continue
  fi
  # Approval is a UNIVERSAL merge rule: every PR requires a standing external
  # APPROVED review by an account other than the city's, enforced here in
  # city merge logic (GitHub branch protection is an extra layer only, not the
  # authority). No check_set token arms it and none opts out — the token that used
  # to arm it per-anchor left integration-branch PRs robot-merging on green, the
  # hole this closes. A designated agent approving certain PRs is a later
  # extension; today the approver is any non-city login.
  if [ -z "$SELF_LOGIN" ]; then
    echo "$PROG: PR#$num approval required but the acting login is unresolved; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  approver=$(printf '%s' "$rstate" | jq -r '.approver // ""')
  if [ -z "$approver" ]; then
    # Every declared check is green and no pool-routed blocker is open: the
    # cadence is done and the pull request is waiting on a person.
    # That is `settled`, and the approval clause of the owed rule is what makes
    # the row the operator's rather than nobody's.
    record_machine "$id" "settled" "$head_oid" "$aroute"
    echo "$PROG: PR#$num no external APPROVED review stands (approval is a universal merge rule); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- UNKNOWN: GitHub has not computed this PR against its current base -------
  # A merge this arm makes moves the base under every later candidate on that
  # base, so their pinned reads answer UNKNOWN. The pinned read started the
  # computation, so read it again before deciding, within the pass's re-read
  # budget (gh_pr_view_settled, bd-lib.sh). Every read here comes after the
  # latest merge this pass made, because merges happen only at the end of an
  # iteration. A computed answer is judged below like any pinned
  # one, so BEHIND and DIRTY keep their own handling. Every pinned field outside
  # the mergeability facts was validated above, so a re-read that changes one is
  # a different PR from the one those gates passed. A re-read that fails is held
  # like a failed pinned read and records nothing.
  unknown_note=""
  if [ "$merge_state" = "UNKNOWN" ] && [ "$MERGE_STATE_REREADS" -gt 0 ]; then
    gh_pr_view_settled "$num" "$ORIGIN_REPO_Q" "$PR_FIELDS" "$PR_JSON"; rr=$?
    case "$rr" in
      0) PR_JSON="$PR_REREAD_JSON"; merge_state="$PR_REREAD_STATE"
         echo "$PROG: PR#$num answered UNKNOWN on the pinned read and $merge_state on re-read $PR_REREADS (anchor $id)" ;;
      2) echo "$PROG: PR#$num changed between the pinned read and re-read $PR_REREADS of its UNKNOWN merge state ($PR_REREAD_CHANGED); merge held (anchor $id)"
         held=$((held + 1)); continue ;;
      3) echo "$PROG: PR#$num view failed on re-read $PR_REREADS of its UNKNOWN merge state; merge held (anchor $id, retry next pass)"
         held=$((held + 1)); continue ;;
      *) if [ "$PR_REREADS" -gt 0 ]; then
           unknown_note=" after $PR_REREADS re-read(s); the pass's re-read budget is spent"
         else
           unknown_note="; not re-read, the pass's re-read budget is spent"
         fi ;;
    esac
  fi

  # --- mergeStateStatus: CLEAN, or UNSTABLE decided on required contexts only ----
  case "$merge_state" in
    CLEAN) : ;;
    UNSTABLE)
      required_contexts_for "$base"
      if [ "$REQ_STATE" != "known" ]; then
        echo "$PROG: PR#$num is UNSTABLE and the required-check set for '$base' is unreadable; merge held (anchor $id)"
        held=$((held + 1)); continue
      fi
      if [ -n "$REQ_CONTEXTS" ]; then
        rollup=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json statusCheckRollup 2>/dev/null)
        req_json=$(printf '%s\n' "$REQ_CONTEXTS" | jq -Rs 'split("\n") | map(select(length > 0))' 2>/dev/null)
        notgreen=$(printf '%s' "$rollup" | jq -r --argjson req "${req_json:-[]}" '
          def name_of: (.name // .context // "");
          def green:
            if ((.conclusion // "") | tostring | length) > 0
              then ((.conclusion | ascii_upcase) as $c | $c == "SUCCESS" or $c == "NEUTRAL" or $c == "SKIPPED")
            elif ((.state // "") | tostring | length) > 0 then ((.state | ascii_upcase) == "SUCCESS")
            else false end;
          (.statusCheckRollup // []) as $r
          | [ $req[] as $c
              | ([ $r[] | select(type == "object") | select(name_of == $c) ]) as $hits
              | if ($hits | length) == 0 then "\($c)(MISSING)"
                elif ([ $hits[] | select(green | not) ] | length) > 0 then "\($c)(RED)"
                else empty end ]
          | join(" ")' 2>/dev/null)
        if [ -z "$rollup" ] || [ -z "$req_json" ]; then
          echo "$PROG: PR#$num is UNSTABLE and the check rollup is unreadable; merge held (anchor $id)"
          held=$((held + 1)); continue
        fi
        if [ -n "$notgreen" ]; then
          echo "$PROG: PR#$num is UNSTABLE and a REQUIRED check is not green at $head_oid: $notgreen; merge held (anchor $id)"
          held=$((held + 1)); continue
        fi
      fi
      echo "$PROG: PR#$num is UNSTABLE but no required check on '$base' is red (the rest are advisory); proceeding (anchor $id)" ;;
    BLOCKED)
      # Branch protection holds a PR whose city-side checks (checked above) are
      # all green. The blocking condition is read from the branch's own rules:
      # an unresolved review thread is the gate only where thread resolution is
      # required (required_review_thread_resolution), otherwise a missing
      # approval is. reviewDecision cannot name it alone — it reads EMPTY while
      # threads are unresolved and resolves only once they clear. The merge stays
      # held whatever the cause; the log names it, and the machine axis records
      # `blocked` for the causes a person must clear — an unresolved required
      # thread, a rule that could not be named — so the board shows needs-attention,
      # while the ordinary approval wait stays `settled` (the review tail).
      review_decision=$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // ""')
      review_gates_for "$base"
      if [ "$PROT_STATE" != "known" ]; then
        record_blocked "$id" "$head_oid" "$aroute" "BLOCKED by branch protection; the rules for '$base' could not be read to name the cause"
        echo "$PROG: PR#$num is BLOCKED by branch protection but the rules for '$base' could not be read to name the cause (reviewDecision='${review_decision:-empty}'); merge held (anchor $id)"
      else
        bcause=""; bu=0
        if [ "$PROT_THREAD_REQ" = "true" ]; then
          if bu=$(unresolved_threads "$num"); then
            [ "$bu" -gt 0 ] && bcause="threads"
          else
            bu=0; bcause="threads-unreadable"
          fi
        fi
        if [ -z "$bcause" ]; then
          if [ "$PROT_APPROVALS" -ge 1 ] && [ "$review_decision" != "APPROVED" ]; then bcause="approval"; else bcause="other"; fi
        fi
        case "$bcause" in
          threads)
            record_blocked "$id" "$head_oid" "$aroute" "$bu unresolved review thread(s) must be resolved before this PR can merge"
            echo "$PROG: PR#$num is BLOCKED by branch protection: $bu unresolved review thread(s) hold required_review_thread_resolution (reviewDecision='${review_decision:-empty}'); merge held (anchor $id)" ;;
          threads-unreadable)
            record_blocked "$id" "$head_oid" "$aroute" "a required review thread's resolution state could not be read"
            echo "$PROG: PR#$num is BLOCKED by branch protection: review-thread resolution is required but its reviewThreads could not be read to count them (reviewDecision='${review_decision:-empty}'); merge held (anchor $id)" ;;
          approval)
            # The ordinary review wait, not a block: the settled tail's owed rule
            # already puts it on the operator's queue as awaiting-review.
            record_machine "$id" "settled" "$head_oid" "$aroute"
            echo "$PROG: PR#$num is BLOCKED by branch protection: waiting on an approving review ($PROT_APPROVALS required, reviewDecision='${review_decision:-empty}'); merge held (anchor $id)" ;;
          other)
            record_blocked "$id" "$head_oid" "$aroute" "branch protection holds it by a rule other than an unresolved required thread or a missing approval"
            echo "$PROG: PR#$num is BLOCKED by branch protection by a rule other than an unresolved required thread or a missing approval (thread-resolution required=$PROT_THREAD_REQ, approvals required=$PROT_APPROVALS, reviewDecision='${review_decision:-empty}'); merge held (anchor $id)" ;;
        esac
      fi
      held=$((held + 1)); continue ;;
    *)
      # The cadence has nothing left to do; GitHub is not ready. Two unready states
      # a person — or the merge-in cadence — must clear reach here with no automated
      # actor already behind them, since the in-flight arm above held every anchor a
      # live rework or blocker is moving; both need the branch brought current and
      # no review verdict does that, so record `blocked` and the board shows
      # needs-attention rather than a merge in progress:
      #   BEHIND — peers merged ahead and the base moved under this PR;
      #   DIRTY  — the branch conflicts with the base.
      # pr-facts.sh files a prepare_mode=merge rework to perform the bring-current;
      # once that child is in flight the in-flight arm records `progressing` instead,
      # so this `blocked` names the window where the branch is dirty with nothing
      # moving it. Every other unready state (GitHub still computing mergeability,
      # say) owes a person nothing and stays `settled`.
      if [ "$merge_state" = "BEHIND" ]; then
        record_blocked "$id" "$head_oid" "$aroute" "the base branch '$base' moved ahead; bring '$head_ref' current with '$base' before it can merge"
      elif [ "$merge_state" = "DIRTY" ]; then
        record_blocked "$id" "$head_oid" "$aroute" "the branch conflicts with '$base' and no merge-in rework is in flight; bring '$head_ref' current with '$base' before it can merge"
      else
        record_machine "$id" "settled" "$head_oid" "$aroute"
      fi
      echo "$PROG: PR#$num not mergeable yet (mergeStateStatus='${merge_state:-unknown}'$unknown_note); merge held (anchor $id)"
      held=$((held + 1)); continue ;;
  esac
  if [ -z "$head_oid" ]; then
    echo "$PROG: PR#$num live head unresolved; cannot head-match the merge; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- generated-artifact freshness AT THE MERGE RESULT --------------------------
  # generated/seed-audit is a function of the whole source tree but is committed
  # per branch, so two PRs that touch no common file still clobber it: one moves a
  # prompt input without re-rendering, the other lands a render made at a base
  # without that input, and both merge cleanly. assets/hooks/pre-commit is
  # branch-local and exits quietly where `gc` is absent, a rebase replays commits
  # without running it at all, `-diff` in .gitattributes keeps the clobber out of
  # the PR diff, and doctor/check-seed-audit-current reports it only once the
  # landing branch is already wrong. This is the one place that sees the merge
  # before it happens, and it re-hashes the inputs rather than rendering, so the
  # cost is hashes. The probe asks the repository, not the working tree: a host holding
  # no checkout, and a repository carrying no rendered audit, have nothing to
  # protect, while the trees compared come from the refs fetched below, so a
  # checkout lagging its own main decides nothing. Base movement is not
  # anchor-local, so the terminal re-read cannot carry this; the window it leaves
  # is one pass of the base moving under a validated PR, which the next pass sees.
  if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/pack.toml" ] \
     && [ -f "$REPO_ROOT/generated/seed-audit/INDEX.md" ] && [ -f "$RENDERER" ]; then
    if ! git fetch --quiet --no-tags origin \
         "+refs/heads/$base:$GATE_REF/base" "+refs/heads/$head_ref:$GATE_REF/head" 2>/dev/null; then
      echo "$PROG: PR#$num could not fetch '$base' and '$head_ref' to check what the merge would land; merge held (anchor $id)"
      held=$((held + 1)); continue
    fi
    fetched_head=$(git rev-parse --verify --quiet "$GATE_REF/head" 2>/dev/null)
    if [ "$fetched_head" != "$head_oid" ]; then
      echo "$PROG: PR#$num head moved during the freshness probe (fetched '${fetched_head:-none}', validated '$head_oid'); merge held (anchor $id)"
      held=$((held + 1)); continue
    fi
    sa_out=$(bash "$RENDERER" --root "$REPO_ROOT" --check-merge "$GATE_REF/base" "$GATE_REF/head" 2>&1); sa_rc=$?
    if [ "$sa_rc" -ne 0 ]; then
      if [ "$sa_rc" -eq 1 ]; then
        sa_why="would land a stale generated/seed-audit"
      else
        sa_why="generated-artifact freshness could not be determined"
      fi
      echo "$PROG: PR#$num $sa_why; merge held (anchor $id)"
      printf '%s\n' "$sa_out" | head -6 | sed 's/^/  /'
      # Held, not routed: rework dispatch belongs to pr-facts.sh, so the door out
      # of this hold is a visit a human claims. First line is the visit headline.
      [ -x "$ESCALATE" ] && "$ESCALATE" --subject "$id" --key "seed-audit-merge-gate.$num" \
        --message "PR#$num $sa_why; the merge is held.

generated/seed-audit is rendered from the whole source tree and committed per
branch, so a branch carrying a render made at an older base lands over prompt
inputs it never saw. Bring the head branch current with '$base', run
assets/scripts/render-seed-audit.sh, commit generated/seed-audit, and push.

$sa_out" >/dev/null 2>&1 || true
      held=$((held + 1)); continue
    fi
  fi

  # --- terminal re-read: the FULL anchor-local authorization set ----------------
  # --match-head-commit binds the commit; none of these fields move the head, so
  # a mid-pass write to any of them would otherwise sail through.
  final=$(anchor_row "$id")
  if [ -z "$final" ]; then
    echo "$PROG: PR#$num anchor $id unreadable immediately before the merge; merge held"
    held=$((held + 1)); continue
  fi
  freason=$(printf '%s' "$final" | jq -r --arg num "$num" \
    --arg base "$base" --arg url "$live_url" --arg ref "$head_ref" "$ANCHOR_HOLDS_DEF"'
    (.meta // {}) as $m
    | (.status | ascii_downcase) as $st
    | ((($m.merge_result // "") | tostring)) as $mr
    | ((($m.pr_number // "") | tostring)) as $pn
    | ((($m.merged_target // "") | tostring)) as $t
    | ((($m.pr_url // "") | tostring | gsub("[[:space:]]";"") | sub("(?<p>/pull/[0-9]+).*"; .p))) as $pu
    | ((($m.branch // "") | tostring)) as $br
    | if $st != "open" then "status is now \($st)"
      elif $mr != "pull_request" then "merge_result is now \($mr)"
      elif $pn != $num then "anchor now claims PR#\($pn)"
      elif ($m.merge_hold | hold_set) then "merge_hold was set after validation"
      elif ($m.pr_posture | comments_unanswered) then "review comments went unanswered after validation"
      elif ($t != "" and $t != $base) then "retargeted after validation (merged_target=\($t))"
      elif ($pu != "" and $pu != $url) then "pr_url changed after validation"
      elif ($br != "" and $br != $ref) then "branch changed after validation"
      elif ($m.check_set | no_check_set) then "check_set emptied after validation"
      else "OK" end' 2>/dev/null); frc=$?
  # The lane term the marker read used to carry, now derived: no declared lane
  # may have left green between validation and the merge. A lane's backing bead
  # can change without moving the head, so this re-derivation is the one guard
  # --match-head-commit does not already provide. It runs only when every stored
  # field above still reads OK, so a field mismatch keeps its own reason.
  if [ "$frc" -eq 0 ] && [ "$freason" = "OK" ]; then
    fcs=$(printf '%s' "$final" | jq -r '.meta.check_set // ""' 2>/dev/null)
    if ! rg=$(first_notgreen_lane "$id" "$fcs"); then
      freason="lane state unreadable before the merge"
    elif [ -n "$rg" ]; then
      freason="lane $rg is no longer green"
    fi
  fi
  # Explicit sentinel: "OK" is the only authorization. An empty result or a
  # non-zero jq means the comparison itself failed — hold, never merge blind.
  if [ "$frc" -ne 0 ] || [ -z "$freason" ]; then
    freason="terminal re-read comparison unreadable"
  fi
  # A visit is a subject-local bead filed without moving the PR head, so
  # --match-head-commit does not catch one raised between validation and here.
  # Re-assert the finalize gate in the terminal window, same fail-closed terms.
  if [ "$freason" = "OK" ] && ! fg_final=$("$FINALIZE_GATE" check "$id" 2>/dev/null); then
    freason="${fg_final:-open visit or unreadable visit probe (fail-closed)}"
  fi
  if [ "$freason" != "OK" ]; then
    echo "$PROG: PR#$num anchor $id changed between validation and the merge — $freason; merge held"
    held=$((held + 1)); continue
  fi

  # --- merge, then record via ONE lifecycle transition ---------------------------
  MERR=$(gh pr merge "$num" --repo "$ORIGIN_REPO_Q" --squash \
    --match-head-commit "$head_oid" 2>&1); mrc=$?
  if [ "$mrc" -ne 0 ]; then
    echo "$PROG: PR#$num merge attempt failed (rc=$mrc): $MERR; merge held (anchor $id)" >&2
    held=$((held + 1)); continue
  fi
  merge_oid=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json mergeCommit 2>/dev/null \
    | scrub | jq -r '.mergeCommit.oid // ""')
  if [ -z "$merge_oid" ]; then
    # Never record an empty merged_sha (I5: closed anchor => merged+merged_sha).
    echo "$PROG: WARN PR#$num merged but the mergeCommit read came back empty; recording merged_sha=unverified:PR#$num" >&2
    merge_oid="unverified:PR#$num"
  fi
  case "$merge_oid" in
    unverified:*) short="$merge_oid" ;;
    *) short=$(printf '%.8s' "$merge_oid") ;;
  esac
  if "$LIFECYCLE" transition "$id" --to merged --expect pull_request --close \
       --set "merged_sha=$merge_oid" \
       --unset merge_record_failures \
       --append-notes "Merged to ${target:-$base} at ${short:-merge}"; then
    merged=$((merged + 1))
    echo "$PROG: merged + recorded $id — PR#$num squashed to ${target:-$base} at ${short:-?}"
  else
    # The PR HAS landed; a silent record failure is the false-durable-record
    # class. Exit non-zero at the end; pr-facts records it next pass, and
    # record-failure-cap.sh escalates the anchor the retries never reach.
    echo "$PROG: PR#$num MERGED but the lifecycle record FAILED for $id; pr-facts records it next pass" >&2
    record_failed=$((record_failed + 1))
    [ -x "$RECORD_CAP" ] && "$RECORD_CAP" "$id" "$num" "$merge_oid" "${target:-$base}" || true
  fi
done <<ROWS_EOF
$(printf '%s\n' "$landing_rows" | awk 'NF { print "exempt\t" $0 }')
$(printf '%s\n' "$rest_rows" | awk 'NF { print "rest\t" $0 }')
ROWS_EOF
pace_end

if [ -n "$PACE_RESUME_AT" ]; then
  echo "$PROG: visited $landing_n landing-first and $PACE_VISITED of $rest_n other anchors before the deadline; the next pass resumes at $PACE_RESUME_AT"
else
  echo "$PROG: visited $landing_n landing-first and $PACE_VISITED of $rest_n other anchors"
fi
echo "$PROG: $merged merged, $recovered recovered, $held held, $skipped skipped, $record_failed record-failed"
[ "$record_failed" -eq 0 ] || exit 1
exit 0
