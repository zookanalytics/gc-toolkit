#!/usr/bin/env bash
# pr-open — arm 3 of the merge cadence: pre_open_gate -> pull_request.
# For each pre_open_gate anchor: adopt an existing OPEN or MERGED PR for the
# branch (never open a twin) — an OPEN PR's body is first refreshed from the
# anchor's current pr_summary, so a rework's restamp reaches the published merge
# surface, while a MERGED PR is a landed record and is flipped untouched; a
# CLOSED-unmerged-only PR is a headstone — open a fresh PR noting the superseded
# one (unless the dead head IS the live head: that close was a decision about
# this exact commit).
# Otherwise: holds gate the create path; require every pre-open lane the
# anchor's check_set declares at the head to DERIVE green (lane-state.sh, the
# same helper merge.sh asks) and no must-fix finding on the anchor to be open
# (finding.sh); `gh pr create` pinned to origin — a draft when the check_set
# names an open-as-draft check, ready otherwise — body summarizing the polecat's
# `pr_summary` with the dispatch text demoted (the description only when no
# summary was carried), read back BY NUMBER, refuse a moved head, replay the
# recorded verdict as a COMMENT (never an approval);
# then ONE lifecycle.sh transition to pull_request carrying
# pr_url/pr_number/merged_target. Every failure leaves pre_open_gate.
# A second arm flips a draft the refinery opened to ready once its pre-open and
# open-as-draft gates read green.
# The composed body lives in a delimited region (compose_managed, between the
# gc:pr-summary markers), so an adoption re-splices a fresh region while keeping
# text an operator or a later arm (pr-stack) added; the region writes its own
# `## Summary` heading, so a stored pr_summary that repeats one is de-duplicated.
# Args: [--deadline <epoch-secs>] [--cursor <file>] pace the walk (pace-lib.sh):
# anchors gate-ensure last recorded as settled, and whose rows carry no hold
# this arm applies, are visited first and the rest after them, each group in a
# rotation of its own, and no new anchor starts past the deadline. The
# draft-to-ready arm's walk is paced the same way, on a rotation of its own.
# Caller: refinery-reconcile.sh. Fail-closed on identity; not set -e.
set -u

PROG="pr-open"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=pace-lib.sh
. "$SCRIPTS_DIR/pace-lib.sh" || { echo "$PROG: cannot source pace-lib.sh beside this script" >&2; exit 1; }
DEADLINE=""; CURSOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --deadline) DEADLINE="${2:-}"; shift 2 ;;
    --cursor)   CURSOR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
LIFECYCLE="$SCRIPTS_DIR/lifecycle.sh"
# The two shared readers of the review graph: lane-state derives a lane's green
# state (the same helper merge.sh asks, so publishing and merging never
# disagree), and finding reads the anchor's open must-fix findings.
LANE_STATE="$SCRIPTS_DIR/lane-state.sh"
FINDING="$SCRIPTS_DIR/finding.sh"
# The one resolver of the check index: given a check_set and a transition, it
# names the checks that gate it (dropping the non-lanes none/off/approval). Each
# anchor's gates are resolved once, at the head, and that one answer feeds the
# create gate, the draft decision and the published body. Without it nothing can
# be gated, so nothing opens.
REVIEW_CHECKS="$SCRIPTS_DIR/review-checks.sh"
[ -x "$REVIEW_CHECKS" ] || { echo "$PROG: the check resolver is missing ($REVIEW_CHECKS); NOTHING is opened or readied this pass" >&2; exit 1; }
# The single writer of the workflow-owned PR labels. A PR is born check-green with
# no review yet, so its initial status is needs-review; reconcile derives that (and
# self-heals an adopted PR mid-rework). mark-base stamps the standing `base:` marker
# on an integration-targeted checkpoint, the PR-list counterpart to the body banner.
PR_STATUS_LABEL="$SCRIPTS_DIR/pr-status-label.sh"
# The single writer of the city's PR posts. The verdict replay and the
# superseded notice go through it so they carry the city's mark, which is what
# keeps pr-facts.sh from reading them back as feedback.
PR_POST="$SCRIPTS_DIR/pr-post.sh"
# The managed `## Summary` region (markers, composer and splice helpers) and the
# title composer (cc_title), shared with pr-stack.sh so an opened PR and a
# post-open refresh never diverge.
# shellcheck source=pr-summary-region.sh
. "${GC_PR_SUMMARY_LIB:-$SCRIPTS_DIR/pr-summary-region.sh}" \
  || { echo "$PROG: cannot source pr-summary-region.sh beside this script" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || exit 0

# The repository every read and the create are pinned to — from the origin
# remote, never from gh (gh's current repo is the movable source this distrusts).
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
  echo "$PROG: cannot resolve this checkout's origin repository; NOTHING is opened this pass" >&2
  exit 0
fi
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"

url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}
pr_url_canon() {
  printf '%s\n' "${1:-}" \
    | grep -Eo '[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+/pull/[0-9]+' | tail -1
}
# is_held asks whether an operator hold marker (merge_hold, rebase_hold) is set
# to a truthy value; is_set is the truthiness rule it reads by. Empty and the
# standard false spellings do not hold.
is_set() {
  case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac
}
is_held() { is_set "${1:-}"; }

# Certify one PR row as this anchor's: right repo url, right head branch, OUR
# head repository (fork gap), not cross-repo, right base. 0=ours, 1=not ours,
# 2=unreadable (the caller must do nothing for the branch). CERT_IS_DRAFT and
# CERT_AUTHOR carry the row's draft state and author login when it lists them.
CERT_NUM=""; CERT_URL=""; CERT_STATE=""; CERT_HEAD_OID=""; CERT_MERGED_AT=""; CERT_IS_DRAFT=""; CERT_AUTHOR=""
certify_row() { # <id> <row-json> <branch> <target> [<want-num>]
  local id="$1" row="$2" br="$3" tgt="$4" want="${5:-}"
  local num url state base head hrepo cross goturl
  CERT_NUM=""; CERT_URL=""; CERT_STATE=""; CERT_HEAD_OID=""; CERT_MERGED_AT=""; CERT_IS_DRAFT=""; CERT_AUTHOR=""
  num=$(printf '%s' "$row" | jq -r '.number // "" | tostring' 2>/dev/null)
  url=$(printf '%s' "$row" | jq -r '.url // ""' 2>/dev/null)
  state=$(printf '%s' "$row" | jq -r '.state // ""' 2>/dev/null)
  base=$(printf '%s' "$row" | jq -r '.baseRefName // ""' 2>/dev/null)
  head=$(printf '%s' "$row" | jq -r '.headRefName // ""' 2>/dev/null)
  hrepo=$(printf '%s' "$row" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  cross=$(printf '%s' "$row" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)
  CERT_MERGED_AT=$(printf '%s' "$row" | jq -r '(.mergedAt // "") | tostring' 2>/dev/null)
  CERT_HEAD_OID=$(printf '%s' "$row" | jq -r '(.headRefOid // "") | tostring' 2>/dev/null)
  CERT_IS_DRAFT=$(printf '%s' "$row" | jq -r 'if .isDraft == true then "true" else "false" end' 2>/dev/null)
  CERT_AUTHOR=$(printf '%s' "$row" | jq -r '(.author.login // "") | tostring' 2>/dev/null)
  if [ -z "$url" ] || [ -z "$state" ] || [ -z "$base" ] || [ -z "$head" ] \
     || [ -z "$hrepo" ] || [ -z "$cross" ] || [ -z "$num" ] || [ -n "${num//[0-9]/}" ]; then
    echo "$PROG: $id branch '$br' — PR identity unreadable (num='$num' url='$url' state='$state' base='$base' head='$head' headrepo='$hrepo' cross='$cross'); NOTHING done this pass" >&2
    return 2
  fi
  goturl=$(pr_url_canon "$url")
  [ "$(url_repo_q "$goturl")" = "$ORIGIN_REPO_Q" ] || { echo "$PROG: $id PR#$num lives in '$(url_repo_q "$goturl")', not '$ORIGIN_REPO_Q'; not ours" >&2; return 1; }
  [ -z "$want" ] || [ "$num" = "$want" ] || { echo "$PROG: $id asked for PR#$want, PR#$num answered; not certified" >&2; return 1; }
  [ "$head" = "$br" ] || { echo "$PROG: $id PR#$num is opened from '$head', not '$br'; not ours" >&2; return 1; }
  [ "$hrepo" = "$ORIGIN_REPO" ] || { echo "$PROG: $id PR#$num head is in FORK '$hrepo'; the branch name matches, the work does not" >&2; return 1; }
  [ "$cross" = "false" ] || { echo "$PROG: $id PR#$num head identity contradicts itself (cross='$cross'); unreadable, NOTHING done" >&2; return 2; }
  [ "$base" = "$tgt" ] || { echo "$PROG: $id PR#$num targets '$base', not '$tgt'; not ours" >&2; return 1; }
  CERT_NUM="$num"; CERT_URL="$goturl"; CERT_STATE="$state"
  return 0
}

# The branch's PR among the certified rows: 0=adoptable (OPEN/MERGED in CERT_*),
# 1=none, 2=refuse (unreadable/collision), 3=dead only (DEAD_* set).
DEAD_NUM=""; DEAD_HEAD=""
find_pr() { # <id> <branch> <target>
  local id="$1" br="$2" tgt="$3" json rc row disp best_rank=99 bn="" bu="" bs="" bh="" bd="" ba=""
  DEAD_NUM=""; DEAD_HEAD=""
  json=$(gh pr list --head "$br" --state all --repo "$ORIGIN_REPO_Q" \
    --json number,url,state,mergedAt,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,isDraft,author \
    --limit 100 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$json" ] \
     || ! printf '%s' "$json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$PROG: $id could not read the PRs for '$br' (rc=$rc); not the same as none existing — NOTHING done" >&2
    return 2
  fi
  local n; n=$(printf '%s' "$json" | jq 'length' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) return 2 ;; esac
  while IFS= read -r row; do
    [ -n "${row:-}" ] || continue
    certify_row "$id" "$row" "$br" "$tgt"
    case $? in 0) : ;; 2) return 2 ;; *) continue ;; esac
    case "$CERT_STATE" in
      OPEN)   disp=0 ;;
      MERGED) disp=1 ;;
      CLOSED)
        # mergedAt promotes CLOSED to merged (GitHub's REST shape for a landing).
        if [ -n "$CERT_MERGED_AT" ] && [ "$CERT_MERGED_AT" != "null" ]; then disp=1; else
          if [ -z "$DEAD_NUM" ] || [ "$CERT_NUM" -gt "$DEAD_NUM" ]; then
            DEAD_NUM="$CERT_NUM"; DEAD_HEAD="$CERT_HEAD_OID"
          fi
          continue
        fi ;;
      *) echo "$PROG: $id PR#$CERT_NUM reports unmodeled state '$CERT_STATE'; NOTHING done" >&2; return 2 ;;
    esac
    if [ "$disp" -lt "$best_rank" ] || { [ "$disp" -eq "$best_rank" ] && [ "$CERT_NUM" -gt "${bn:-0}" ]; }; then
      best_rank="$disp"; bn="$CERT_NUM"; bu="$CERT_URL"; bs="$CERT_STATE"; bh="$CERT_HEAD_OID"
      bd="$CERT_IS_DRAFT"; ba="$CERT_AUTHOR"
    fi
  done <<ROWS
$(printf '%s' "$json" | jq -c '.[]' 2>/dev/null)
ROWS
  if [ -z "$bn" ]; then
    [ -n "$DEAD_NUM" ] && return 3
    if [ "$n" -gt 0 ]; then
      echo "$PROG: $id branch '$br' matched $n PR(s) and none is ours (name collision); NOTHING done" >&2
      return 2
    fi
    return 1
  fi
  CERT_NUM="$bn"; CERT_URL="$bu"; CERT_STATE="$bs"; CERT_HEAD_OID="$bh"; CERT_IS_DRAFT="$bd"; CERT_AUTHOR="$ba"
  return 0
}

flip() { # <id> <url> <num> <target> [<opened-as-draft-oid>] — ONE atomic lifecycle transition
  # A non-empty 5th arg stamps opened_as_draft on the same transition: the PR was
  # opened or adopted as a draft the refinery owns the ready-flip of, which the
  # draft-to-ready arm and gate-ensure read as the open-as-draft stage.
  "$LIFECYCLE" transition "$1" --to pull_request --expect pre_open_gate \
    --set "pr_url=$2" --set "pr_number=$3" --set "merged_target=$4" \
    ${5:+--set "opened_as_draft=$5"} \
    >/dev/null 2>&1
}

# Whether an adopted draft PR is one the refinery owns the ready-flip of: a draft
# the city opened as a draft, which nobody has converted back to draft since. Its
# author is the city's own login, and its timeline carries no convert_to_draft
# (the refinery never re-drafts a PR, so any conversion is someone parking it).
# 0 = the refinery's draft; 1 = someone else's, which is adopted without the
# marker so its ready flip stays with whoever parked it; 2 = the acting login or
# the timeline is unreadable, which the caller holds on rather than guess.
SELF_LOGIN=""
city_draft() { # <num> <author-login>
  local conv
  [ -n "${2:-}" ] || return 2
  [ -n "$SELF_LOGIN" ] || SELF_LOGIN=$(gh api --hostname "$ORIGIN_HOST" user --jq '.login' 2>/dev/null)
  [ -n "$SELF_LOGIN" ] || return 2
  [ "$2" = "$SELF_LOGIN" ] || return 1
  conv=$(gh api --hostname "$ORIGIN_HOST" --paginate "repos/$ORIGIN_REPO/issues/$1/timeline?per_page=100" \
    --jq '.[] | select(.event == "convert_to_draft") | .event' 2>/dev/null) || return 2
  [ -z "$conv" ] || return 1
  return 0
}

# --- branch heads: one fetch for the pass ----------------------------------------
# The create gate resolves its check index at the head the PR opens at, so an
# anchor's head is read before its lanes are judged. One glob fetch of origin's
# branches into a private namespace — the way pre-open-rebase.sh observes branches
# — answers every anchor's head from a local ref, so an anchor parked on a red lane
# pays no API read for its head, and each head's commit is already here for the
# resolver's --at read. It runs once, for the first anchor that needs a head. A
# failed fetch, or a branch it did not bring, falls back to the API read. A head
# the fetch answered is confirmed against the API before a create (below), so the
# PR still opens at the head the gate judged.
HEADS_REF="refs/gc-toolkit/pr-open"
HEADS_FETCHED=""
fetched_head() { # <branch> -> sha from the pass fetch, or nothing
  if [ -z "$HEADS_FETCHED" ]; then
    if git fetch --prune --quiet --no-tags origin "+refs/heads/*:$HEADS_REF/heads/*" >/dev/null 2>&1; then
      HEADS_FETCHED=yes
    else
      HEADS_FETCHED=no
      echo "$PROG: could not fetch origin's branches; each head is read from the API this pass" >&2
    fi
  fi
  [ "$HEADS_FETCHED" = yes ] || return 0
  git rev-parse --verify --quiet "$HEADS_REF/heads/$1^{commit}" 2>/dev/null
}
api_head() { # <branch> -> sha from the API, or nothing
  gh api --hostname "$ORIGIN_HOST" "repos/$ORIGIN_REPO/commits/$1" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null
}

# --- PR body: one delimited region, composed once and re-splice-able ------------
# The markers (PRS_MARK_OPEN/CLOSE), the composer (compose_managed) and the region
# read-modify-write helpers (prs_current_section, prs_marker_state,
# prs_splice_in_place, prs_establish_region) live in pr-summary-region.sh, sourced
# above and shared with pr-stack.sh so an opened body and a post-open refresh never
# diverge.

# Refresh an OPEN PR's published body from the anchor's current pr_summary before
# the adoption flip, the read-modify-write pr-stack.sh uses: read the body
# \r-stripped, then bring the managed region current. A well-formed marker pair has
# what is between the markers replaced, leaving operator edits and pr-stack's section
# in place. A markerless body carrying the shape a create wrote before these markers
# (## Summary … ## Refinery handoff) has the region established over that legacy
# prefix, keeping whatever follows — the stale-body case adoption exists to close. A
# body with no managed region — empty, hand-written, or a malformed marker shape —
# has no stale MANAGED summary to republish and is adopted as it stands. 0 = current,
# refreshed, established, or carries no managed region; proceed to the flip. 1 = the
# reworked summary could not be proven onto a MANAGED body: a missing head oid, an
# unreadable or unparseable body, a scratch or compose failure, or a failed edit —
# hold at pre_open_gate and retry rather than flip a managed body known to be behind,
# the miss the refresh exists to close. <phased> is the anchor's gate set resolved
# at <head_oid>, which the composed handoff bullets name.
refresh_pr_body() { # <id> <num> <row> <branch> <target> <head_oid> <phased>
  local id="$1" num="$2" row="$3" branch="$4" target="$5" head_oid="$6" phased="${7:-}"
  local summary desc checkset body_json CUR SECTION NEW ms rc
  if [ -z "$head_oid" ]; then
    echo "$PROG: $id PR#$num head oid unknown from the PR row; body refresh cannot be composed, anchor stays pre_open_gate (retry next pass)" >&2
    return 1
  fi
  summary=$(printf '%s' "$row" | jq -r '.metadata.pr_summary // empty')
  [ -n "$(printf '%s' "$summary" | tr -d '[:space:]')" ] || summary=""
  desc=$(printf '%s' "$row" | jq -r '.description // empty')
  checkset=$(printf '%s' "$row" | jq -r '.metadata.check_set // ""')
  body_json=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json body </dev/null 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$body_json" ]; then
    echo "$PROG: $id PR#$num body unreadable; anchor stays pre_open_gate (retry next pass)" >&2
    return 1
  fi
  CUR=$(mktemp "${TMPDIR:-/tmp}/gctk-pr-open-cur.XXXXXX") \
    || { echo "$PROG: $id PR#$num scratch file unavailable; anchor stays pre_open_gate (retry next pass)" >&2; return 1; }
  SECTION=$(mktemp "${TMPDIR:-/tmp}/gctk-pr-open-sec.XXXXXX") \
    || { rm -f "$CUR"; echo "$PROG: $id PR#$num scratch file unavailable; anchor stays pre_open_gate (retry next pass)" >&2; return 1; }
  NEW=$(mktemp "${TMPDIR:-/tmp}/gctk-pr-open-new.XXXXXX") \
    || { rm -f "$CUR" "$SECTION"; echo "$PROG: $id PR#$num scratch file unavailable; anchor stays pre_open_gate (retry next pass)" >&2; return 1; }
  # Read the current body into scratch and compose its replacement. A payload that
  # slipped past the read check but does not parse, or a compose that writes
  # nothing, is a render failure that holds rather than flips a body it could not
  # rebuild. The parse is proven first — jq is the last stage of its own pipeline,
  # so its status stands without pipefail — then the body is spliced as before.
  if ! printf '%s' "$body_json" | jq -e . >/dev/null 2>&1; then
    rm -f "$CUR" "$SECTION" "$NEW"
    echo "$PROG: $id PR#$num published body did not parse; anchor stays pre_open_gate (retry next pass)" >&2
    return 1
  fi
  printf '%s' "$body_json" | jq -r '.body // ""' 2>/dev/null | tr -d '\r' > "$CUR"
  if ! compose_managed "$summary" "$desc" "$id" "$branch" "$target" "$checkset" "$head_oid" "" "" open "$phased" > "$SECTION" \
     || [ ! -s "$SECTION" ]; then
    rm -f "$CUR" "$SECTION" "$NEW"
    echo "$PROG: $id PR#$num refreshed body could not be composed; anchor stays pre_open_gate (retry next pass)" >&2
    return 1
  fi
  prs_marker_state "$CUR"; ms=$?
  if [ "$ms" = 0 ]; then
    # A well-formed region: replace what is between the markers, no-op when the
    # render already matches so no edit is spent.
    if [ "$(prs_current_section "$CUR")" = "$(cat "$SECTION")" ]; then
      rm -f "$CUR" "$SECTION" "$NEW"; return 0
    fi
    prs_splice_in_place "$CUR" "$SECTION" "$NEW"
  elif [ "$ms" = 1 ] && prs_establish_region "$CUR" "$SECTION" "$NEW"; then
    # A markerless body carrying the shape a create wrote before these markers
    # (## Summary … ## Refinery handoff) IS the stale-body case adoption exists to
    # close: establish the region over that legacy prefix, keeping what follows.
    # prs_establish_region fails for a markerless body WITHOUT that prefix, which falls
    # through to the leave-alone arm below.
    :
  else
    # No managed region to refresh: the markers are absent and the body is not a
    # legacy managed prefix (an empty or hand-written body), or they are malformed
    # (a lone marker, a second pair). There is no stale MANAGED summary to
    # republish, and rewriting a body the arm did not compose would clobber an
    # operator's own text, so adopt it as it stands.
    rm -f "$CUR" "$SECTION" "$NEW"
    echo "$PROG: $id PR#$num body carries no managed gc:pr-summary region to refresh; adopted as it stands"
    return 0
  fi
  if gh pr edit "$num" --repo "$ORIGIN_REPO_Q" --body-file "$NEW" </dev/null >/dev/null 2>&1; then
    rm -f "$CUR" "$SECTION" "$NEW"
    echo "$PROG: $id PR#$num body refreshed from the anchor's current pr_summary"
    return 0
  fi
  rm -f "$CUR" "$SECTION" "$NEW"
  echo "$PROG: $id PR#$num body refresh failed to land; anchor stays pre_open_gate (retry next pass)" >&2
  return 1
}

# --- enumerate ------------------------------------------------------------------
ANCHORS=$(bd_list --status=open --metadata-field merge_result=pre_open_gate) || {
  echo "$PROG: could not enumerate pre-open anchors; failing loudly rather than reporting a false all-clear" >&2
  exit 1
}
[ "$ANCHORS" != "[]" ] || echo "$PROG: no pre-open anchors to open; the draft-to-ready arm still runs"

# --- visit order: the anchors most likely to open first, each group in rotation
# The walk's cost grows with the pre-open set, so a deadline can stop it. An
# anchor gate-ensure last recorded as settled (every pre-open lane green and
# nothing owed) is visited first, unless its own row carries a hold the gate
# below applies: an operator's merge_hold or rebase_hold, or no check_set.
# gate-ensure settles a green anchor whatever holds it, and a held anchor in the
# first group spends a visit an openable one needs. Opening an anchor takes it
# out of this set, so a pass the deadline stops still opened what it reached.
# An anchor in the first group can still be held, by a PR a human closed at
# this head or by a lane that left green after gate-ensure last visited it, so
# the group rotates on a cursor of its own: in a fixed order the same held
# anchors would lead every pass and the deadline would keep the ones behind
# them from ever opening. The grouping only orders the walk; every anchor still
# meets the full gate below. The others rotate after the arm's own cursor
# (pace-lib.sh).
pace_start "$CURSOR" "$DEADLINE"
first_rows=""; rest_rows=""
while IFS=$'\x1f' read -r machine mhold rhold cs arow; do
  [ -n "${arow:-}" ] || continue
  if [ "${machine#settled@}" != "$machine" ] && ! is_held "$mhold" && ! is_held "$rhold" \
     && [ -n "$(printf '%s' "$cs" | tr -d '[:space:],')" ]; then
    first_rows="$first_rows$arow"$'\n'
  else
    rest_rows="$rest_rows$arow"$'\n'
  fi
done <<SPLIT_EOF
$(printf '%s' "$ANCHORS" | jq -r '
    .[] | . as $row | (.metadata // {}) as $m
    | [ ($m["pr.machine"] // ""), ($m.merge_hold // ""), ($m.rebase_hold // ""), ($m.check_set // "") ]
    | map(tostring | gsub("[\u001f\n]"; " ")) + [ $row | tojson ] | join("\u001f")' 2>/dev/null)
SPLIT_EOF
first_rows=$(printf '%s' "$first_rows" | pace_order "$PACE_FIRST_CURSOR")
rest_rows=$(printf '%s' "$rest_rows" | pace_order "$CURSOR")
first_n=$(printf '%s' "$first_rows" | awk 'NF { n++ } END { print n + 0 }')
rest_n=$(printf '%s' "$rest_rows" | awk 'NF { n++ } END { print n + 0 }')

opened=0; flipped=0; held=0; skipped=0
# The body file is removed after each create; the trap covers the window
# a signal can land in, which is the whole `gh pr create` call.
BODY=""
trap 'rm -f "$BODY" 2>/dev/null' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
while IFS= read -r tagged; do
  [ -n "${tagged:-}" ] || continue
  group="${tagged%%$'\t'*}"
  row="${tagged#*$'\t'}"
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  branch=$(printf '%s' "$row" | jq -r '.metadata.branch // empty')
  target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // .metadata.target // empty')
  [ -n "$target" ] || target="main"
  if [ -z "$id" ] || [ -z "$branch" ]; then skipped=$((skipped + 1)); continue; fi
  pace_visit "$group" "$id"; case $? in 1) continue ;; 2) break ;; esac

  SUP_NUM=""; SUP_HEAD=""
  find_pr "$id" "$branch" "$target"
  case $? in
    0)
      # Adoption is not a publish, so the create-path gates do not re-run here;
      # but an OPEN PR's published body must catch up to a reworked pr_summary
      # before the flip, or the merge surface stays stale. A refresh that cannot
      # land holds the anchor at pre_open_gate for the next pass rather than
      # flipping a body it knows to be behind. A MERGED PR is a landed record and
      # is flipped untouched. An OPEN PR's gates are resolved once, at its head,
      # for both the body refresh and the draft decision below; an unreadable set
      # holds the adoption this pass.
      adopt_draft=""
      if [ "$CERT_STATE" = OPEN ]; then
        acs=$(printf '%s' "$row" | jq -r '.metadata.check_set // ""')
        if [ -z "$CERT_HEAD_OID" ]; then
          echo "$PROG: $id PR#$CERT_NUM head oid unknown from the PR row; its gates cannot be resolved nor its body composed, anchor stays pre_open_gate (retry next pass)" >&2
          skipped=$((skipped + 1)); continue
        fi
        if ! APHASED=$(prs_resolve_phased "$acs" "$CERT_HEAD_OID" "$REVIEW_CHECKS"); then
          echo "$PROG: $id PR#$CERT_NUM gate set unreadable at its head ${CERT_HEAD_OID:0:8}; anchor stays pre_open_gate (retry next pass)" >&2
          skipped=$((skipped + 1)); continue
        fi
        if ! refresh_pr_body "$id" "$CERT_NUM" "$row" "$branch" "$target" "$CERT_HEAD_OID" "$APHASED"; then
          skipped=$((skipped + 1)); continue
        fi
        # Record whether this adopted PR is a draft the refinery owns the ready-flip
        # of: an OPEN draft the city opened as a draft and nobody has re-drafted
        # since (city_draft), whose check_set names an open-as-draft check at its
        # head. Without the marker the draft-to-ready arm never surfaces it, which
        # is right for any other draft: an operator's parked PR stays parked. A
        # ready or MERGED PR takes none.
        if [ "$CERT_IS_DRAFT" = true ] && [ -n "$(prs_band "$APHASED" open-as-draft)" ]; then
          city_draft "$CERT_NUM" "$CERT_AUTHOR"
          case $? in
            0) adopt_draft="$CERT_HEAD_OID" ;;
            1) echo "$PROG: $id PR#$CERT_NUM is a draft the refinery did not open as one (author '${CERT_AUTHOR:-?}', or re-drafted since); adopted without opened_as_draft, so its ready flip stays with whoever parked it" ;;
            *) echo "$PROG: $id PR#$CERT_NUM draft ownership unreadable (acting login or PR timeline); anchor stays pre_open_gate (retry next pass)" >&2
               skipped=$((skipped + 1)); continue ;;
          esac
        fi
      fi
      if flip "$id" "$CERT_URL" "$CERT_NUM" "$target" "$adopt_draft"; then
        flipped=$((flipped + 1))
        # Adopting an existing PR: reconcile its label from the anchor's current
        # rework state rather than assuming ready. Best-effort.
        "$PR_STATUS_LABEL" reconcile --anchor "$id" --pr "$CERT_NUM" \
          --repo "$ORIGIN_REPO_Q" --host "$ORIGIN_HOST" >/dev/null 2>&1 || true
        # Standing base marker: an integration-targeted checkpoint is labelled so the
        # PR list never reads it as a merge to main. Best-effort; a no-op off integration/.
        "$PR_STATUS_LABEL" mark-base --pr "$CERT_NUM" --target "$target" \
          --repo "$ORIGIN_REPO_Q" --host "$ORIGIN_HOST" >/dev/null 2>&1 || true
        echo "$PROG: $id branch '$branch' already has PR#$CERT_NUM ($CERT_STATE); flipped to pull_request"
      else
        echo "$PROG: $id PR#$CERT_NUM adoption transition failed; anchor stays pre_open_gate (retry next pass)" >&2
        skipped=$((skipped + 1))
      fi
      continue ;;
    2) skipped=$((skipped + 1)); continue ;;
    3) SUP_NUM="$DEAD_NUM"; SUP_HEAD="$DEAD_HEAD" ;;  # dead only: create path
    *) : ;;  # none: create path
  esac

  # Operator holds gate the create (publishing) path only — adoption above is
  # not a publish, and downstream gates honor the same markers.
  hold=$(printf '%s' "$row" | jq -r '.metadata.merge_hold // empty')
  rhold=$(printf '%s' "$row" | jq -r '.metadata.rebase_hold // empty')
  if is_held "$hold" || is_held "$rhold"; then
    echo "$PROG: $id branch '$branch' held (merge_hold='$hold' rebase_hold='$rhold'); no PR opened"
    held=$((held + 1)); continue
  fi

  # The gate: no open must-fix finding on the anchor, then every pre-open lane
  # the anchor's check_set declares DERIVES green through lane-state.sh (the same
  # helper merge.sh asks). green is a state of the lane, not a claim about a commit.
  checkset=$(printf '%s' "$row" | jq -r '.metadata.check_set // ""')
  # Empty is never the checkless opt-out: that is the 'none' sentinel. Empty
  # means never normalized, and gate-ensure stamps the declared default when it
  # reaches the anchor. Publishing under it would open the PR ungated.
  if [ -z "$(printf '%s' "$checkset" | tr -d '[:space:],')" ]; then
    echo "$PROG: $id branch '$branch' has no normalized check_set (empty is never the 'none' opt-out); no PR opened — gate-ensure stamps the default"
    held=$((held + 1)); continue
  fi
  # No PR over an unfixed must-fix finding — the same finding graph merge.sh's
  # blocker probe holds on, read through the shared helper. It is row-local and
  # judged BEFORE the head read, so an anchor the city has ruled must change never
  # reads a head. open-must-fix exits 0 naming the open must-fix findings, 1
  # when there are none, 2 when the store would not read; 0 and 2 both hold rather
  # than publish blind.
  MUSTFIX=$("$FINDING" open-must-fix --anchor "$id"); mfrc=$?
  if [ "$mfrc" -eq 0 ]; then
    echo "$PROG: $id branch '$branch' has an open must-fix finding ($(printf '%s' "$MUSTFIX" | tr '\n' ' ' | sed 's/ *$//')); held"
    held=$((held + 1)); continue
  elif [ "$mfrc" -ne 1 ]; then
    echo "$PROG: $id branch '$branch' must-fix finding read unreadable (rc=$mfrc); held"
    held=$((held + 1)); continue
  fi
  # The head the PR opens at, read here — before the gate — because the create
  # gate resolves its check index at that head, the same commit gate-ensure
  # dispatch resolves against: a branch whose head index differs from the
  # refinery's working tree (one that moves a check's phase, or adds a new
  # open-as-draft check) is gated by its own index. The pass fetch answers it
  # locally (fetched_head), so an anchor parked on a red lane pays no API read
  # for its head; the API answers when the fetch could not. A held,
  # unnormalized, or must-fix-held anchor returned above reads no head at all.
  head_oid=$(fetched_head "$branch"); head_src=fetch
  if [ -z "$head_oid" ]; then head_oid=$(api_head "$branch"); head_src=api; fi
  if [ -z "$head_oid" ]; then
    echo "$PROG: $id branch '$branch' head unresolved; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  # The anchor's gates, resolved ONCE at the head: the pre-open band is the create
  # gate, the open-as-draft band decides whether the PR opens as a draft, and the
  # whole set is what the published body names. One answer feeds all three, so
  # the gate, the draft decision and the body cannot disagree. An unreadable set
  # holds.
  if ! PHASED=$(prs_resolve_phased "$checkset" "$head_oid" "$REVIEW_CHECKS"); then
    echo "$PROG: $id branch '$branch' gate set unreadable at ${head_oid:0:8}; held"
    held=$((held + 1)); continue
  fi
  PREOPEN_GATES=$(prs_band "$PHASED" pre-open)
  DRAFT_GATES=$(prs_band "$PHASED" open-as-draft)
  # The create gate waits only on the PRE-OPEN checks — the ones that read the
  # diff and must be green before the PR exists. open-as-draft checks (demo) run
  # against the open PR and gate the draft->ready flip, not the create.
  # --no-remote on the lane read: at pre-open there is no PR yet, so no GitHub
  # approval can back a lane here. A lane derives green, does not, or the store
  # would not read; the last two both hold, so an unreadable lane is never
  # published as green.
  UNGREEN=""
  while IFS= read -r g; do
    [ -n "${g:-}" ] || continue
    "$LANE_STATE" green --anchor "$id" --lane "$g" --no-remote && continue
    UNGREEN="$g"; break
  done <<GATES
$PREOPEN_GATES
GATES
  if [ -n "$UNGREEN" ]; then
    echo "$PROG: $id branch '$branch' lane '$UNGREEN' does not derive green; held"
    held=$((held + 1)); continue
  fi
  # A head the pass fetch answered may have moved since; confirm it against the API
  # before publishing, so the PR opens at the head the gate judged. A moved branch
  # re-gates at its new head next pass.
  if [ "$head_src" = fetch ]; then
    live=$(api_head "$branch")
    if [ -z "$live" ]; then
      echo "$PROG: $id branch '$branch' head unconfirmed before the create; skip (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if [ "$live" != "$head_oid" ]; then
      echo "$PROG: $id branch '$branch' moved since the pass fetch (${head_oid:0:8} -> ${live:0:8}); skip — the new head re-gates next pass"
      skipped=$((skipped + 1)); continue
    fi
  fi

  # A dead PR closed at EXACTLY this head was a decision about this commit;
  # reopening it would repeat every pass. An unreadable dead head refuses too.
  if [ -n "$SUP_NUM" ]; then
    if [ -z "$SUP_HEAD" ]; then
      echo "$PROG: $id branch '$branch' has only closed PR#$SUP_NUM and its head is unreadable; NOTHING opened (operator must repair)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if [ "$SUP_HEAD" = "$head_oid" ]; then
      echo "$PROG: $id branch '$branch' — PR#$SUP_NUM was closed unmerged at this same head ($head_oid); not reopening a human's decision" >&2
      skipped=$((skipped + 1)); continue
    fi
  fi

  # --- create, pinned; a draft when an open-as-draft check gates the PR ----------
  title=$(printf '%s' "$row" | jq -r '.title // empty')
  kind=$(printf '%s' "$row" | jq -r '.issue_type // empty')
  desc=$(printf '%s' "$row" | jq -r '.description // empty')
  # The summary is the polecat's account of the diff, carried in pr_summary by
  # the refinery handoff. The anchor's description is dispatch text — what the
  # work was asked to do, addressed to the agent that did it and never revised
  # once the diff exists — so it is demoted to a collapsed section and stands
  # in as the summary only when the handoff carried no account. Whitespace is
  # the absent case, as it is for check_set above.
  summary=$(printf '%s' "$row" | jq -r '.metadata.pr_summary // empty')
  [ -n "$(printf '%s' "$summary" | tr -d '[:space:]')" ] || summary=""
  BODY=$(mktemp "${TMPDIR:-/tmp}/gctk-pr-open.XXXXXX") || { echo "$PROG: cannot create a temp file for the PR body" >&2; exit 1; }
  {
    printf '%s\n' "$PRS_MARK_OPEN"
    compose_managed "$summary" "$desc" "$id" "$branch" "$target" "$checkset" "$head_oid" "$SUP_NUM" "$SUP_HEAD" open "$PHASED"
    printf '%s\n' "$PRS_MARK_CLOSE"
  } > "$BODY"
  # The bead id stays in the title so a PR is traceable to its anchor; the
  # type prefix goes ahead of it so the conventional-commit check passes.
  pr_title="$(cc_title "$title" "$kind") ($id)"
  # Open as a DRAFT when the check_set names an open-as-draft check (demo): that
  # check runs against the open PR, so the PR must exist for a preview to deploy,
  # but it is not surfaced for human review until the draft->ready arm below flips
  # it once the open-as-draft gates are green. A check_set of only pre-open checks
  # (gc-toolkit today) has no draft gate and opens ready at once — the empty-phase
  # collapse, current behavior unchanged.
  create_args=(--repo "$ORIGIN_REPO_Q" --base "$target" --head "$branch" --title "$pr_title" --body-file "$BODY")
  # OPENED_DRAFT, set to the reviewed head when a draft gate exists, both adds
  # --draft and is stamped as opened_as_draft at the flip, so the draft-to-ready
  # arm and gate-ensure know the open-as-draft stage without re-resolving it.
  OPENED_DRAFT=""
  [ -n "$DRAFT_GATES" ] && { create_args+=(--draft); OPENED_DRAFT="$head_oid"; }
  CREATED_URL=$(pr_url_canon "$(gh pr create "${create_args[@]}" 2>/dev/null || true)")
  rm -f "$BODY"
  if [ -z "$CREATED_URL" ]; then
    echo "$PROG: $id branch '$branch' PR create produced nothing; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  if [ "$(url_repo_q "$CREATED_URL")" != "$ORIGIN_REPO_Q" ]; then
    echo "$PROG: $id create answered '$CREATED_URL' outside '$ORIGIN_REPO_Q'; NOTHING stamped" >&2
    skipped=$((skipped + 1)); continue
  fi
  PR_NUMBER=$(printf '%s' "$CREATED_URL" | sed -n 's#.*/pull/\([0-9][0-9]*\)$#\1#p')
  # Read the created PR back BY NUMBER and certify it; refuse a moved head — the
  # contract is that a PR is check-green at birth.
  NEW_JSON=$(gh pr view "$PR_NUMBER" --repo "$ORIGIN_REPO_Q" \
    --json number,url,state,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository 2>/dev/null)
  if [ -z "$NEW_JSON" ] || ! certify_row "$id" "$NEW_JSON" "$branch" "$target" "$PR_NUMBER"; then
    echo "$PROG: $id opened PR#$PR_NUMBER but could not certify it; NOTHING stamped, anchor stays pre_open_gate (adopted next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  if [ "$CERT_HEAD_OID" != "$head_oid" ]; then
    echo "$PROG: $id opened PR#$PR_NUMBER at head '${CERT_HEAD_OID:-?}', not the reviewed '$head_oid' (the branch moved); NOTHING stamped — the moved head re-gates" >&2
    skipped=$((skipped + 1)); continue
  fi

  # Replay the recorded verdict as a COMMENT — the city never approves (#185).
  REVIEW_ID=$(bd_list --metadata-field task_kind=review --metadata-field anchor_bead="$id" \
    --status=closed,open,in_progress \
    | jq -r 'sort_by(.updated_at // .created_at) | last | .id // empty' 2>/dev/null)
  VERDICT=""
  [ -n "$REVIEW_ID" ] && VERDICT=$(gc bd show "$REVIEW_ID" --json 2>/dev/null | scrub \
    | jq -r '.[0].notes // ""' 2>/dev/null)
  if [ -n "$VERDICT" ]; then
    "$PR_POST" comment --repo "$ORIGIN_REPO_Q" --pr "$PR_NUMBER" \
      --body "$(printf 'Pre-open signoff (comment-only — not an approval):\n\n%s' "$VERDICT")" >/dev/null 2>&1 || true
  else
    "$PR_POST" comment --repo "$ORIGIN_REPO_Q" --pr "$PR_NUMBER" \
      --body "Pre-open checks signed off at \`${head_oid:0:8}\` (comment-only — not an approval)." >/dev/null 2>&1 || true
  fi
  [ -n "$SUP_NUM" ] && "$PR_POST" comment --repo "$ORIGIN_REPO_Q" --pr "$SUP_NUM" \
    --body "Superseded by #$PR_NUMBER: branch \`$branch\` was re-implemented and re-gated at \`${head_oid:0:8}\`." >/dev/null 2>&1 || true

  if flip "$id" "$CERT_URL" "$CERT_NUM" "$target" "$OPENED_DRAFT"; then
    opened=$((opened + 1))
    # Born check-green: seed the initial status label (and its group). Best-effort
    # — a label failure never unwinds an opened PR; pr-facts.sh reconciles it.
    "$PR_STATUS_LABEL" reconcile --anchor "$id" --pr "$CERT_NUM" \
      --repo "$ORIGIN_REPO_Q" --host "$ORIGIN_HOST" >/dev/null 2>&1 || true
    # Standing base marker for an integration checkpoint (no-op off integration/).
    "$PR_STATUS_LABEL" mark-base --pr "$CERT_NUM" --target "$target" \
      --repo "$ORIGIN_REPO_Q" --host "$ORIGIN_HOST" >/dev/null 2>&1 || true
    echo "$PROG: $id opened PR#$PR_NUMBER for '$branch' at ${head_oid:0:8} (check_set '$checkset' green)${SUP_NUM:+, superseding closed PR#$SUP_NUM}; flipped to pull_request"
  else
    echo "$PROG: $id opened PR#$PR_NUMBER but did NOT reach pull_request; anchor stays pre_open_gate and adopts this PR next pass" >&2
    skipped=$((skipped + 1))
  fi
done <<ANCHORS_EOF
$(printf '%s\n' "$first_rows" | awk 'NF { print "first\t" $0 }')
$(printf '%s\n' "$rest_rows" | awk 'NF { print "rest\t" $0 }')
ANCHORS_EOF
pace_end

paced="visited $PACE_VISITED of $((first_n + rest_n)) pre-open anchors ($first_n settled and unheld first)"
if [ -n "$PACE_RESUME_AT" ]; then
  echo "$PROG: $paced before the deadline; the next pass resumes at $PACE_RESUME_AT"
elif [ "$PACE_FIRST_SKIPPED" -gt 0 ]; then
  echo "$PROG: $paced before the deadline; $PACE_FIRST_SKIPPED settled and unheld anchors wait for the next pass"
else
  echo "$PROG: $paced"
fi

# --- arm: draft -> ready -------------------------------------------------------
# A PR the refinery opened or adopted as a draft — recorded as opened_as_draft at
# the flip — is surfaced for review once every pre-open AND open-as-draft check
# reads green. The candidate set is one metadata prefilter over the enumeration,
# no API and no resolver fork per anchor: an anchor with no opened_as_draft opened
# ready and has no draft to flip; one carrying draft_readied was already surfaced,
# and is never re-read or re-flipped — which is also what keeps this arm off a PR
# an operator converted back to draft after it was readied. Only an un-readied,
# undisposed candidate pays the PR read below, and that read is spent once per
# ready PR: a ready PR records draft_readied whatever holds it, so the arm never
# reads it again and gate-ensure dispatches its later phases. A store that would
# not enumerate fails the arm loudly (exit 1 after the summary), the way the
# pre-open arm does, rather than report nothing to ready.
# This walk runs after the pre-open walk, under the same deadline, and rotates on
# a cursor of its own (pace-lib.sh). A draft this arm holds stays a candidate (an
# operator's hold, a must-fix finding, a gate not yet green), so in a fixed order
# the same drafts would lead every pass while the deadline kept the drafts behind
# them waiting. One draft is always visited, so this walk still makes progress on
# a pass whose pre-open walk reached the deadline.
READY_FAILED=""
if ! READY_ANCHORS=$(bd_list --status=open --metadata-field merge_result=pull_request); then
  echo "$PROG: could not enumerate pull_request anchors; the draft-to-ready arm did not run, failing loudly rather than reporting nothing to ready" >&2
  READY_FAILED=1; READY_ANCHORS="[]"
fi
readied=0
# One jq does the prefilter, the candidates are put in walk order, and a second jq
# pulls the fields, unit-separated so an empty field (an unset hold) keeps its
# place.
READY_CURSOR="${CURSOR:+$CURSOR.ready}"
ready_rows=$(printf '%s' "$READY_ANCHORS" | jq -c '
    .[]?
    | select(((.metadata.opened_as_draft // "") | tostring) != ""
             and ((.metadata.draft_readied // "") | tostring) == "")' 2>/dev/null \
  | pace_order "$READY_CURSOR")
ready_n=$(printf '%s' "$ready_rows" | awk 'NF { n++ } END { print n + 0 }')
pace_start "$READY_CURSOR" "$DEADLINE"
while IFS=$'\x1f' read -r rid rcs rnum rhold rrhold rdisp; do
  [ -n "$rid" ] && [ -n "$rnum" ] || continue
  # A disposed PR is pr-facts.sh's to close; it is never surfaced.
  [ -z "$rdisp" ] || continue
  pace_visit rest "$rid"; case $? in 1) continue ;; 2) break ;; esac
  # It may be a draft: ask GitHub (the one read this arm pays, bounded to
  # un-readied drafts). A closed/merged PR is pr-facts.sh's; an unreadable read
  # retries next pass.
  rview=$(gh pr view "$rnum" --repo "$ORIGIN_REPO_Q" --json isDraft,state,headRefOid 2>/dev/null)
  [ -n "$rview" ] || continue
  [ "$(printf '%s' "$rview" | jq -r '.state // ""')" = "OPEN" ] || continue
  rhead=$(printf '%s' "$rview" | jq -r '.headRefOid // empty')
  [ -n "$rhead" ] || continue
  if [ "$(printf '%s' "$rview" | jq -r '.isDraft // false')" != "true" ]; then
    # Already ready (surfaced externally): record it so the arm stops re-reading
    # this PR and gate-ensure moves the anchor to its ready-for-review stage. A
    # hold does not stop this write: recording that GitHub reads the PR ready
    # surfaces nothing, and skipping it would pin the anchor's dispatch at the
    # draft stage for as long as the hold stands.
    gc bd update "$rid" --set-metadata draft_readied="$rhead" >/dev/null 2>&1 \
      || echo "$PROG: WARN $rid PR#$rnum is ready but draft_readied did not stamp; will re-read next pass" >&2
    continue
  fi
  # The draft is the operator's while they hold it: never surface it.
  if is_held "$rhold" || is_held "$rrhold"; then
    echo "$PROG: $rid PR#$rnum is a draft but held (merge_hold='$rhold' rebase_hold='$rrhold'); not surfacing"
    continue
  fi
  # A draft the refinery owns, unheld: never surface it over an open must-fix
  # finding (the city has ruled the diff must change). open-must-fix exits 0 with
  # findings, 1 with none, 2 unreadable; 0 and 2 both hold the flip.
  "$FINDING" open-must-fix --anchor "$rid" >/dev/null 2>&1; mfrc=$?
  if [ "$mfrc" -ne 1 ]; then
    echo "$PROG: $rid PR#$rnum draft has an open must-fix finding or an unreadable finding read (rc=$mfrc); not surfacing"
    continue
  fi
  # Every pre-open and open-as-draft gate must derive green at the live head,
  # remote allowed — the PR is open, so a GitHub approval can back a lane. An
  # unreadable gate set (a resolver crash) or lane holds the flip.
  if ! RGATES=$("$REVIEW_CHECKS" --resolve --check-set "$rcs" --through open-as-draft --at "$rhead" 2>/dev/null); then
    continue
  fi
  rungreen=""
  while IFS= read -r g; do
    [ -n "${g:-}" ] || continue
    "$LANE_STATE" green --anchor "$rid" --lane "$g" && continue
    rungreen="$g"; break
  done <<RGATESEOF
$RGATES
RGATESEOF
  [ -z "$rungreen" ] || continue
  # All green: surface it, and record draft_readied so this arm never re-reads or
  # re-flips the PR — including after an operator later re-drafts it to park it.
  if gh pr ready "$rnum" --repo "$ORIGIN_REPO_Q" >/dev/null 2>&1; then
    readied=$((readied + 1))
    gc bd update "$rid" --set-metadata draft_readied="$rhead" >/dev/null 2>&1 \
      || echo "$PROG: WARN $rid PR#$rnum readied but draft_readied did not stamp; will re-read next pass" >&2
    "$PR_STATUS_LABEL" reconcile --anchor "$rid" --pr "$rnum" \
      --repo "$ORIGIN_REPO_Q" --host "$ORIGIN_HOST" >/dev/null 2>&1 || true
    echo "$PROG: $rid PR#$rnum draft gates green at ${rhead:0:8}; flipped draft -> ready for review"
  else
    echo "$PROG: $rid PR#$rnum draft gates green but 'gh pr ready' did not land; stays draft (retry next pass)" >&2
  fi
done <<READY_EOF
$(printf '%s\n' "$ready_rows" | jq -r '
    [ (.id // ""), (.metadata.check_set // ""), (.metadata.pr_number // ""),
      (.metadata.merge_hold // ""), (.metadata.rebase_hold // ""),
      (.metadata["gc.pr_close_disposition_kind"] // "") ]
    | map(tostring | gsub("[\u001f\n]"; " ")) | join("\u001f")' 2>/dev/null)
READY_EOF
pace_end
if [ "$ready_n" -gt 0 ]; then
  if [ -n "$PACE_RESUME_AT" ]; then
    echo "$PROG: visited $PACE_VISITED of $ready_n draft PRs before the deadline; the next pass resumes at $PACE_RESUME_AT"
  else
    echo "$PROG: visited $PACE_VISITED of $ready_n draft PRs"
  fi
fi

echo "$PROG: $opened opened, $flipped flipped, $readied readied, $held held, $skipped skipped"
[ -z "$READY_FAILED" ] || exit 1
exit 0
