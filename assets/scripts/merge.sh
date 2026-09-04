#!/usr/bin/env bash
# merge — arm 3 of the merge cadence: the single writer of merged truth.
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
# every check_set gate green; approval (armed by the check_set
# member, signoff_dismissed, or a DISMISSED review of our own — satisfied only
# by a latest APPROVED from another account at the live head; a standing
# CHANGES_REQUESTED from any other account vetoes); no unclosed rework/review
# child (metadata keys naming this PR AND dependency edges; unreadable holds);
# mergeStateStatus CLEAN (UNSTABLE decided on required contexts only);
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
# Caller: refinery-reconcile.sh, with BEADS_ACTOR projected to the refinery
# identity.
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

# The signoff round cap, mirrored from signoff.sh: past it no further rework is
# filed, which is what turns a standing veto from a hold into a wedge.
MAX_REVIEW_ROUNDS="${GC_MAX_REVIEW_ROUNDS:-3}"
case "$MAX_REVIEW_ROUNDS" in ''|*[!0-9]*) MAX_REVIEW_ROUNDS=3 ;; esac
ESCALATE="$SCRIPTS_DIR/escalate.sh"
# The merged-record retry cap. Both record arms below retry every pass with no
# memory of the last one, so a cause the retry cannot clear needs a writer that
# remembers; this is that writer, shared with pr-facts.sh so the two arms of the
# same repair count against one budget.
RECORD_CAP="$SCRIPTS_DIR/record-failure-cap.sh"
RENDERER="$SCRIPTS_DIR/render-seed-audit.sh"
# The repository this pass merges into, resolved through git so a run with no
# checkout under it simply has no committed artifact to keep current.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
# Where the freshness probe parks the two commits it needs. Its own namespace,
# so nothing here can move a branch or a remote-tracking ref.
GATE_REF="refs/gc-toolkit/merge-gate"

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

# Record the machine axis this pass reached, at the head it was read at. Every
# hold below already decides it and spends the answer on a log line; this keeps
# it, so a reader learns whether an anchor is moving without re-implementing
# these predicates. lifecycle.sh owns the @<since> component and preserves it
# across a pass that reaches the same verdict at the same head.
#
# --route carries the anchor's own route back: recording a verdict is an
# observation, not a routing decision, and an omitted --route would let a
# detached state's default clear a route this pass never looked at.
record_machine() { # <anchor-id> <value> <head-oid> <current-route>
  [ -n "${3:-}" ] || return 0
  "$LIFECYCLE" transition "$1" --to pull_request --expect pull_request \
    --route "${4:-}" --set-dated "pr.machine=$2@$3" >/dev/null 2>&1 && return 0
  echo "$PROG: WARN $1 machine axis '$2@$3' did not record; the board reads it as unknown until the next pass" >&2
}

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

# The "first declared gate not green" predicate (none/off/approval dropped),
# shared between hold_gate() and the terminal re-read below so the two jq
# filters can never drift on which gate is red. Takes check_set as $cs and a
# metadata object as $m.
FIRST_RED_GATE_DEF='
  def first_red_gate($cs; $m):
    (($cs // "") | split(",") | map(gsub("[[:space:]]"; "")) | map(select(length > 0))
       | map(select((. | ascii_downcase) as $g | $g != "none" and $g != "off" and $g != "approval"))) as $gates
    | (first($gates[] | select((($m["check." + .]) // "") != "green"))) // "";
'

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

# First declared gate NOT green; non-zero = markers unreadable, which the
# caller must hold on, never read as all-green. The lane is compared to no
# head: green is a state of the lane, and a commit landing on the branch
# neither clears it nor buys a review.
hold_gate() { # <check_set> <row>
  printf '%s' "${2:-}" | jq -re --arg cs "${1:-}" \
    "$FIRST_RED_GATE_DEF"'
    (.meta // {}) as $m
    | first_red_gate($cs; $m)' 2>/dev/null
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

merged=0; recovered=0; held=0; skipped=0; record_failed=0
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
         --set "merged_sha=$merge_oid" --unset rejection_reason \
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
  dismissed=$(printf '%s' "$fresh" | jq -r '.meta.signoff_dismissed // ""')
  checkset=$(printf '%s' "$fresh" | jq -r '.meta.check_set // ""')
  posture=$(printf '%s' "$fresh" | jq -r '.meta.pr_posture // ""')
  aroute=$(printf '%s' "$fresh" | jq -r '.meta["gc.routed_to"] // ""')

  # --- validate, in order -------------------------------------------------------
  # Empty/absent check_set is NEVER "no gates": the declared gateless opt-out is
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
  # the structural check). An "other" anchor of this pr_number is a duplicate
  # unless its own pr_url names a DIFFERENT repository: the repo key is the same
  # one the in-flight holder filter uses (REPO_Q_DEF), so a foreign same-number
  # anchor is dropped while one whose pr_url is absent or unparseable names no
  # repository ("?") and still holds. A duplicate holds EVERY anchor of the PR.
  dups=$(bd_list --status=open --metadata-field merge_result=pull_request) || {
    echo "$PROG: PR#$num duplicate-anchor read failed; merge held (anchor $id)"
    held=$((held + 1)); continue
  }
  others=$(printf '%s' "$dups" | jq -r --arg id "$id" --arg num "$num" --arg repo "$ORIGIN_REPO_Q" \
    "$REPO_Q_DEF"'
    ($repo | ascii_downcase) as $ours
    | [ .[] | select(.id != $id)
        | select(((.metadata.pr_number // "") | tostring) == $num)
        | (.metadata.pr_url | repo_q) as $rq
        | select($rq == $ours or $rq == "?")
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
  if ! hg=$(hold_gate "$checkset" "$fresh"); then
    echo "$PROG: PR#$num check-set markers unreadable on anchor $id; merge held"
    held=$((held + 1)); continue
  fi
  if [ -n "$hg" ]; then
    have=$(printf '%s' "$fresh" | jq -r --arg k "check.$hg" '.meta[$k] // "unreviewed"')
    # A lane short of green is one a review is due to raise. The cap's park is
    # not reached here: it holds above, on merge_hold.
    record_machine "$id" "progressing" "$head_oid" "$aroute"
    echo "$PROG: PR#$num check '$hg' is '$have', not green; merge held (anchor $id)"
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
        | "\(.id) (\($st))" ]
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
    [ -n "$pool_holder" ] && record_machine "$id" "progressing" "$head_oid" "$aroute"
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
    # Whether anything will ANSWER it is the round count: signoff.sh files a
    # rework child per round and stops at the cap, so a veto standing past the
    # cap is one nothing will act on. signoff.sh owns that count, and reading it
    # any other way records the wedge over work it would still send back: its
    # cap measures rounds since the operator's last feedback, so the total is
    # wrong by exactly the floor that feedback sets. Both halves come off reads
    # this pass already has — the blockers, and the anchor row re-read above.
    # The floor's stamp is signoff's alone; nothing here writes it.
    total=$(printf '%s' "$blockers" | jq -r '
      [ .[] | select(type == "object")
        | select(((.metadata.source_review_bead // "") | tostring) != "") ] | length' 2>/dev/null)
    case "$total" in ''|*[!0-9]*) total=0 ;; esac
    floor_raw=$(printf '%s' "$fresh" | jq -r '(.meta.signoff_round_floor // "") | tostring')
    case "$floor_raw" in
      *@*) floor="${floor_raw%%@*}"; floor_batch="${floor_raw#*@}" ;;
      *)   floor=""; floor_batch="" ;;
    esac
    case "$floor" in ''|*[!0-9]*) floor=0; floor_batch="" ;; esac
    # Feedback signoff has not answered yet retires every round filed before it:
    # the next verdict writes the floor at the total and files rework. Holding
    # the older floor here would wedge the anchor for the whole window between
    # the feedback and that verdict, which is as long as a review takes.
    reset_batch=$(printf '%s' "$fresh" | jq -r '(.meta.signoff_rounds_reset // "") | tostring')
    if [ -n "$reset_batch" ] && [ "$reset_batch" != "$floor_batch" ]; then
      floor="$total"
    fi
    rounds=$((total - floor))
    [ "$rounds" -ge 0 ] || rounds=0
    if [ "$rounds" -ge "$MAX_REVIEW_ROUNDS" ]; then
      record_machine "$id" "wedged-veto" "$head_oid" "$aroute"
    else
      record_machine "$id" "progressing" "$head_oid" "$aroute"
    fi
    echo "$PROG: PR#$num reviewer '$veto' has a standing CHANGES_REQUESTED; merge held (anchor $id, rework rounds $rounds/$MAX_REVIEW_ROUNDS)"
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
      # Every declared gate is green at the live head and no pool-routed blocker
      # is open: the cadence is done and the pull request is waiting on a person.
      # That is `settled`, and the approval clause of the owed rule is what makes
      # the row the operator's rather than nobody's.
      record_machine "$id" "settled" "$head_oid" "$aroute"
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
      # The cadence has nothing left to do; GitHub is not ready. Still `settled`.
      record_machine "$id" "settled" "$head_oid" "$aroute"
      echo "$PROG: PR#$num not mergeable yet (mergeStateStatus='${merge_state:-unknown}'); merge held (anchor $id)"
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
    --arg base "$base" --arg url "$live_url" --arg ref "$head_ref" --arg dis "$dismissed" \
    "$FIRST_RED_GATE_DEF"'
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
    | first_red_gate($fcs; $m) as $red
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
      elif $red != "" then "check \($red) is no longer green"
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
$(printf '%s' "$ANCHORS" | jq -c '.[]' 2>/dev/null)
ROWS_EOF

echo "$PROG: $merged merged, $recovered recovered, $held held, $skipped skipped, $record_failed record-failed"
[ "$record_failed" -eq 0 ] || exit 1
exit 0
