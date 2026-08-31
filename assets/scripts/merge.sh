#!/usr/bin/env bash
# merge — arm 3 of the merge cadence: the single writer of merged truth.
# For each open pull_request anchor: pinned `gh pr view`, identity gates (right
# repo, not a fork, right head branch, OPEN non-draft), live anchor re-read,
# then validate in order: merge_hold; unanswered review comments (pr_posture,
# read OFF THE ANCHOR, never re-derived from GitHub here); one-anchor-per-PR
# (hold + escalate once —
# fail-closed defense; the structural check is doctor's); non-empty check_set
# (empty is never the 'none' opt-out — an unnormalized anchor holds);
# base == merged_target;
# every check_set gate green@<live head>; approval (armed by the check_set
# member, signoff_dismissed, or a DISMISSED review of our own — satisfied only
# by a latest APPROVED from another account at the live head; a standing
# CHANGES_REQUESTED from any other account vetoes); no unclosed rework/review
# child (metadata keys naming this PR AND dependency edges; unreadable holds);
# mergeStateStatus CLEAN (UNSTABLE decided on required contexts only). The FULL
# anchor-local authorization set is re-read immediately before the merge; any
# mismatch holds. `gh pr merge --squash --match-head-commit`, then ONE
# lifecycle.sh transition --to merged --close. A failed record exits non-zero
# loudly (pr-facts records it next pass). Caller: refinery-reconcile.sh, with
# BEADS_ACTOR projected to the refinery identity.
set -u

PROG="merge"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LIFECYCLE="$SCRIPTS_DIR/lifecycle.sh"
ESCALATE="$SCRIPTS_DIR/escalate.sh"

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
  # Bounded fail-open: with no login, an own DISMISSED review cannot arm the
  # approval requirement from the GitHub side this pass. The signoff_dismissed
  # marker (stamped before any dismissal) still arms it, and an armed approval
  # gate still holds below.
  echo "$PROG: WARN acting login unresolved; own-dismissed-review approval arming is unavailable this pass (signoff_dismissed still arms it)" >&2
fi

url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}
canon_pr_url() {
  printf '%s' "${1:-}" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##'
}
is_held() { case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac; }

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

bd_list() { # guarded array read; non-zero = "could not tell"
  local raw rc
  raw=$(gc bd list "$@" --limit=0 --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
anchor_row() { # live {status, meta}; empty = unreadable, never an all-default row
  gc bd show "$1" --json 2>/dev/null | scrub \
    | jq -c '.[0] | select(. != null) | select(.metadata != null)
             | {status: (.status // ""), meta: .metadata}' 2>/dev/null
}

# First declared gate NOT green@<head> (none/off/approval dropped); non-zero =
# markers unreadable, which the caller must hold on, never read as all-green.
hold_gate() { # <check_set> <row> <head>
  printf '%s' "${2:-}" | jq -re --arg cs "${1:-}" --arg head "${3:-}" '
    (.meta // {}) as $m
    | (($cs // "") | split(",") | map(gsub("[[:space:]]"; "")) | map(select(length > 0))
       | map(select((. | ascii_downcase) as $g | $g != "none" and $g != "off" and $g != "approval"))) as $gates
    | (first($gates[] | select((($m["check." + .]) // "") != ("green@" + $head)))) // ""' 2>/dev/null
}

# Which status checks actually gate <branch>: rulesets + classic protection via
# the branch object (the protection endpoint needs admin and 404s ambiguously).
REQ_STATE=""; REQ_CONTEXTS=""
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

ANCHORS=$(bd_list --status=open --metadata-field merge_result=pull_request) || {
  echo "$PROG: could not enumerate gating anchors; failing loudly rather than merging on a partial view" >&2
  exit 1
}
[ "$ANCHORS" != "[]" ] || { echo "$PROG: no gating anchors"; exit 0; }

merged=0; held=0; skipped=0; record_failed=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '(.metadata.pr_number // "") | tostring')
  [ -n "$id" ] || continue
  case "$num" in ''|*[!0-9]*) skipped=$((skipped + 1)); continue ;; esac

  # --- pinned PR read --------------------------------------------------------
  PR_JSON=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" \
    --json state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,reviewDecision,url 2>/dev/null)
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
  # Merged/closed/draft PRs are pr-facts.sh's to record; the skill only merges.
  [ "$state" = "OPEN" ] || { skipped=$((skipped + 1)); continue; }
  [ "$is_draft" != "true" ] || { skipped=$((skipped + 1)); continue; }

  # --- live anchor re-read (the enumeration predates the PR read) --------------
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
  target=$(printf '%s' "$fresh" | jq -r '.meta.merged_target // ""')
  hold=$(printf '%s' "$fresh" | jq -r '.meta.merge_hold // ""')
  dismissed=$(printf '%s' "$fresh" | jq -r '.meta.signoff_dismissed // ""')
  checkset=$(printf '%s' "$fresh" | jq -r '.meta.check_set // ""')
  posture=$(printf '%s' "$fresh" | jq -r '.meta.pr_posture // ""')
  if [ -n "$prurl" ] && [ "$(canon_pr_url "$prurl")" != "$live_url" ]; then
    echo "$PROG: anchor $id records pr_url '$prurl' but PR#$num is '$live_url'; merge held — operator must repair"
    held=$((held + 1)); continue
  fi
  if [ -n "$abranch" ] && [ "$head_ref" != "$abranch" ]; then
    echo "$PROG: anchor $id records branch '$abranch' but PR#$num is opened from '$head_ref'; merge held — operator must repair"
    held=$((held + 1)); continue
  fi

  # --- validate, in order -------------------------------------------------------
  # Empty/absent check_set is NEVER "no gates": the declared gateless opt-out is
  # the 'none' sentinel; empty means never normalized (gate-ensure stamps the
  # default). Fail closed rather than merge ungated.
  if [ -z "$(printf '%s' "$checkset" | tr -d '[:space:],')" ]; then
    echo "$PROG: PR#$num anchor $id has no normalized check_set (empty is never the 'none' opt-out); merge held"
    held=$((held + 1)); continue
  fi
  if is_held "$hold"; then
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
  # the structural check). Keyed on pr_url so a foreign same-number anchor never
  # holds ours; a duplicate holds EVERY anchor of the PR.
  dups=$(bd_list --status=open --metadata-field merge_result=pull_request) || {
    echo "$PROG: PR#$num duplicate-anchor read failed; merge held (anchor $id)"
    held=$((held + 1)); continue
  }
  others=$(printf '%s' "$dups" | jq -r --arg id "$id" --arg u "$live_url" '
    [ .[] | select(.id != $id)
      | select(((.metadata.pr_url // "") | tostring
                | gsub("[[:space:]]";"") | sub("(?<p>/pull/[0-9]+).*"; .p)) == $u)
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
  if ! hg=$(hold_gate "$checkset" "$fresh" "$head_oid"); then
    echo "$PROG: PR#$num check-set markers unreadable on anchor $id; merge held"
    held=$((held + 1)); continue
  fi
  if [ -n "$hg" ]; then
    have=$(printf '%s' "$fresh" | jq -r --arg k "check.$hg" '.meta[$k] // "none"')
    echo "$PROG: PR#$num check '$hg' not green at live head (have '$have', want 'green@$head_oid'); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- unclosed rework/review children: metadata keys AND dependency edges ------
  by_pr=$(bd_list --metadata-field pr_number="$num" --status="$LIVE_STATUSES") || {
    echo "$PROG: PR#$num referencing-bead read failed; merge held (anchor $id)"
    held=$((held + 1)); continue
  }
  children=$(gc bd dep list "$id" --direction=up -t parent-child --json 2>/dev/null | scrub)
  blockers=$(gc bd dep list "$id" --direction=down -t blocks --json 2>/dev/null | scrub)
  if ! printf '%s' "$children" | jq -e 'type == "array"' >/dev/null 2>&1 \
     || ! printf '%s' "$blockers" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$PROG: PR#$num dependency probe unreadable; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # pr_number holders drop other anchors (the dup guard's business) and explicit
  # tracking_only opt-outs; a dep-edge holder holds regardless — the edge is the claim.
  if ! inflight=$(printf '%s\n%s\n%s' "$by_pr" "$children" "$blockers" | jq -sr --arg id "$id" --arg live "$LIVE_STATUSES" '
    ($live | split(",")) as $ls
    | [ (.[0][] | . + {via: "pr"}), (.[1][] | . + {via: "dep"}), (.[2][] | . + {via: "dep"}) ]
    | [ .[] | select(.id != $id)
        | ((.status // "open") | ascii_downcase) as $st
        | select(($ls | index($st)) != null)
        | ((.metadata.merge_result // "") | tostring) as $mr
        | ((.metadata.tracking_only // "") | tostring | ascii_downcase) as $t
        | select(.via == "dep" or ($mr == "" and ((["","false","0","null"] | index($t)) != null)))
        | "\(.id) (\($st))" ]
    | .[0] // empty' 2>/dev/null); then
    echo "$PROG: PR#$num in-flight holder filter unreadable; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  if [ -n "$inflight" ]; then
    echo "$PROG: PR#$num has unclosed rework/review bead $inflight; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- approval ------------------------------------------------------------------
  reviews=$(gh_api_origin --paginate "repos/$ORIGIN_REPO/pulls/$num/reviews?per_page=100" \
    --jq '.[]' 2>/dev/null); rrc=$?
  if [ "$rrc" -ne 0 ]; then
    echo "$PROG: PR#$num reviews history read failed; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # Latest state-bearing review per non-self reviewer (DISMISSED shadows its
  # author's older rows); approvals count only at the live head.
  rstate=$(printf '%s' "$reviews" | jq -cs --arg self "$SELF_LOGIN" --arg head "$head_oid" '
    ([ .[] | select((.user.login // "") != $self)
       | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED") ]
     | group_by(.user.login // "") | map(sort_by((.submitted_at // ""), (.id // 0)) | last)) as $latest
    | { veto: ([ $latest[] | select(.state == "CHANGES_REQUESTED") | (.user.login // "") ] | .[0] // ""),
        approver: ([ $latest[] | select(.state == "APPROVED")
                     | select((.commit_id // "") == $head) | (.user.login // "") ] | .[0] // ""),
        self_dismissed: ([ .[] | select($self != "") | select((.user.login // "") == $self)
                           | select(.state == "DISMISSED") ] | length) }' 2>/dev/null)
  if [ -z "$rstate" ]; then
    echo "$PROG: PR#$num reviews history unreadable; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  veto=$(printf '%s' "$rstate" | jq -r '.veto // ""')
  if [ -n "$veto" ]; then
    # A human's standing NO holds every candidate, whatever the check_set says.
    echo "$PROG: PR#$num reviewer '$veto' has a standing CHANGES_REQUESTED; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  needs_approval=""
  case ",$(printf '%s' "$checkset" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')," in
    *",approval,"*) needs_approval=1 ;;
  esac
  [ -n "$dismissed" ] && needs_approval=1
  sd=$(printf '%s' "$rstate" | jq -r '.self_dismissed // 0')
  [ "${sd:-0}" != "0" ] && needs_approval=1
  if [ -n "$needs_approval" ]; then
    if [ -z "$SELF_LOGIN" ]; then
      echo "$PROG: PR#$num approval required but the acting login is unresolved; merge held (anchor $id)"
      held=$((held + 1)); continue
    fi
    approver=$(printf '%s' "$rstate" | jq -r '.approver // ""')
    if [ -z "$approver" ]; then
      echo "$PROG: PR#$num no external APPROVED review at the live head $head_oid (approval armed by: check_set/signoff_dismissed/own dismissed review); merge held (anchor $id)"
      held=$((held + 1)); continue
    fi
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
    *)
      echo "$PROG: PR#$num not mergeable yet (mergeStateStatus='${merge_state:-unknown}'); merge held (anchor $id)"
      held=$((held + 1)); continue ;;
  esac
  if [ -z "$head_oid" ]; then
    echo "$PROG: PR#$num live head unresolved; cannot head-match the merge; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- terminal re-read: the FULL anchor-local authorization set ----------------
  # --match-head-commit binds the commit; none of these fields move the head, so
  # a mid-pass write to any of them would otherwise sail through.
  final=$(anchor_row "$id")
  if [ -z "$final" ]; then
    echo "$PROG: PR#$num anchor $id unreadable immediately before the merge; merge held"
    held=$((held + 1)); continue
  fi
  freason=$(printf '%s' "$final" | jq -r --arg num "$num" --arg head "$head_oid" \
    --arg base "$base" --arg url "$live_url" --arg ref "$head_ref" --arg dis "$dismissed" --arg cs "$checkset" '
    (.meta // {}) as $m
    | (.status | ascii_downcase) as $st
    | ((($m.merge_result // "") | tostring)) as $mr
    | ((($m.pr_number // "") | tostring)) as $pn
    | ((($m.merge_hold // "") | tostring)) as $h
    | ((($m.signoff_dismissed // "") | tostring)) as $d
    | ((($m.merged_target // "") | tostring)) as $t
    | ((($m.pr_url // "") | tostring | gsub("[[:space:]]";"") | sub("(?<p>/pull/[0-9]+).*"; .p))) as $pu
    | ((($m.branch // "") | tostring)) as $br
    | ((($m.check_set // "") | tostring)) as $fcs
    | (($fcs | split(",") | map(gsub("[[:space:]]";"")) | map(select(length > 0))
        | map(select((. | ascii_downcase) as $g | $g != "none" and $g != "off" and $g != "approval")))) as $gates
    | ((first($gates[] | select((($m["check." + .]) // "") != ("green@" + $head)))) // "") as $red
    | if $st != "open" then "status is now \($st)"
      elif $mr != "pull_request" then "merge_result is now \($mr)"
      elif $pn != $num then "anchor now claims PR#\($pn)"
      elif (["","false","0","null","False","FALSE"] | index($h)) == null then "merge_hold was set after validation"
      elif ((($m.pr_posture // "") | tostring) | startswith("commented@")) then "review comments went unanswered after validation"
      elif $d != $dis then "signoff_dismissed changed after the approval gate ran"
      elif ($t != "" and $t != $base) then "retargeted after validation (merged_target=\($t))"
      elif ($pu != "" and $pu != $url) then "pr_url changed after validation"
      elif ($br != "" and $br != $ref) then "branch changed after validation"
      elif ($fcs | gsub("[[:space:],]"; "")) == "" then "check_set emptied after validation"
      elif $red != "" then "check \($red) is no longer green at \($head)"
      else "OK" end' 2>/dev/null); frc=$?
  # Explicit sentinel: "OK" is the only authorization. An empty result or a
  # non-zero jq means the comparison itself failed — hold, never merge blind.
  if [ "$frc" -ne 0 ] || [ -z "$freason" ]; then
    freason="terminal re-read comparison unreadable"
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
       --set "merged_sha=$merge_oid" --unset rejection_reason \
       --append-notes "Merged to ${target:-$base} at ${short:-merge}"; then
    merged=$((merged + 1))
    echo "$PROG: merged + recorded $id — PR#$num squashed to ${target:-$base} at ${short:-?}"
  else
    # The PR HAS landed; a silent record failure is the false-durable-record
    # class. Exit non-zero at the end; pr-facts records it next pass.
    echo "$PROG: PR#$num MERGED but the lifecycle record FAILED for $id; pr-facts records it next pass" >&2
    record_failed=$((record_failed + 1))
  fi
done <<ROWS_EOF
$(printf '%s' "$ANCHORS" | jq -c '.[]' 2>/dev/null)
ROWS_EOF

echo "$PROG: $merged merged, $held held, $skipped skipped, $record_failed record-failed"
[ "$record_failed" -eq 0 ] || exit 1
exit 0
