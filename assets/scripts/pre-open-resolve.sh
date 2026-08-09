#!/usr/bin/env bash
# pre-open-resolve — open the PR for a PRE-OPEN-gated anchor once codex is green
# (the second half of the pre-open codex gate, tk-6d0vb.1.8). It is the mirror of
# the merge skill one step earlier in the lifecycle: the merge skill lands a ready
# PR; this pass CREATES the PR — but only after codex has vetted the branch, so a
# PR that becomes visible is codex-green at birth.
#
# Background. mol-refinery-patrol's merge-push step, when `codex` is a check-set
# member and there is no PR yet, does NOT open the PR. It dispatches the codex
# signoff against the BRANCH compare-range and parks the anchor in the
# `pre_open_gate` sub-state (open, assignee="", gc.routed_to="", merge_result=
# pre_open_gate, branch/merged_target set, NO pr_url/pr_number). The codex
# reviewer stamps `check.codex=green@<branch-head>` on the anchor (or files a
# rework child on REQUEST_CHANGES). THIS pass then opens the non-draft PR at that
# reviewed head and flips the anchor to `merge_result=pull_request`, handing it to
# the normal merge gate (merge-skill.sh) unchanged.
#
# Preserves #163 (the PR still opens NON-draft — no draft phase is reintroduced)
# and #185 (comment-only — the recorded codex verdict is replayed as a plain PR
# comment, never an approval; GitHub approval stays exclusively human/external).
#
# Per anchor, in order:
#   PR already open for the branch  -> flip THIS anchor to pull_request (record
#                                      pr_url/pr_number). Convergence: a sibling
#                                      anchor on the same branch (e.g. the original
#                                      convoy left in pre_open_gate after a pre-open
#                                      rework filed a child) becomes closeable on
#                                      merge instead of leaking open. Never opens a
#                                      second PR for a branch that already has one.
#   no PR + merge_hold/rebase_hold  -> HOLD (operator gate). Nothing is opened for a
#                                      held anchor; see the gate in the loop.
#   no PR + check.codex green@head  -> open the non-draft PR at the reviewed head,
#                                      replay the codex verdict as a comment, flip
#                                      to pull_request.
#   no PR + check.codex not green   -> HOLD (codex not done, or the head advanced
#                                      past the reviewed commit so the marker is
#                                      stale — a rework's review re-stamps the new
#                                      head; convergent, retried next idle pass).
#
# The gate here is codex-only, by design: pre-open moves ONLY the codex member
# ahead of PR-creation (CI + approval stay post-open). The FULL check-set is still
# enforced at merge time by merge-skill.sh, unchanged.
#
# Enumerated by BEAD (like merge-skill.sh / reconcile-merged-prs.sh) — but a bead
# names its PR by BRANCH, and a branch name does not name a repository any more
# than a PR number does: `gh pr list --head <branch>`, `gh pr create`, `gh pr view`
# and `gh api repos/{owner}/{repo}/...` all resolve in whatever repository gh
# considers CURRENT, which `gh repo set-default`, GH_REPO, GH_HOST or a different
# cwd all move. Branch names collide across repositories even more freely than
# numbers do (every fork of this repo can carry `polecat/<bead>`). So this script
# asks the same question merge-skill.sh and reconcile-merged-prs.sh ask, of the one
# source gh cannot move: what this checkout pushes to (review tk-jc66l).
#
# The stakes here are the mirror of the merge path's. Uncertified, a foreign
# same-branch PR flips THIS anchor from merge_result=pre_open_gate to
# pull_request with a foreign pr_url/pr_number — and pre_open_gate is the ONLY
# state that retries PR-open, so the anchor leaves it having never opened its PR.
# The hardened merge/reconcile passes then correctly hold or skip the foreign
# identity, and the real PR is never opened by anything. Fail closed instead: an
# uncertifiable answer opens nothing and stamps nothing, and the anchor stays
# pre_open_gate for the next idle pass.
#
# AND A PULL REQUEST IN THE RIGHT REPOSITORY IS STILL NOT THIS ANCHOR'S (review
# tk-j0q41). Pinning the read to the origin repository answers where the ANSWER came
# from; it says nothing about which branch, in which repository, the pull request is
# opened FROM. A fork's PR *into* this repository has one of OUR urls and one of
# THEIR branches, so a url-only check passes on it — and `--head` filters on the
# branch NAME alone, so it is listed alongside ours with nothing but arrival order
# separating them. Every candidate — existing, discovered after a create race, or
# just created — is therefore certified on all four halves of its identity (url
# repository, head branch, HEAD REPOSITORY, base) before it can become this anchor's
# pr_url/pr_number, and the branch's PR is CHOSEN from the certified rows rather than
# taken from the top of the list. See `certify_pr_row` / `find_certified_pr` below;
# `certify_pr_identity` in check-set-heal.sh is the by-number sibling of the same
# check, and merge-skill.sh / reconcile-merged-prs.sh carry it too — keep them in
# step.
#
# NOT set -e: best-effort, must never abort the patrol's idle loop. A PR is opened
# ONLY on an authoritative check.codex=green@<live-head>; any tool error skips the
# anchor and retries next idle pass.
set -uo pipefail

# gh is the only way to read branch/PR state and open the PR here. Without it
# there is nothing to do (the anchor simply waits for a synced pack, like the
# other passes).
command -v gh >/dev/null 2>&1 || exit 0

# THE REPOSITORY EVERY READ AND THE PR-CREATE ARE PINNED TO. Two forms, both
# needed: `<host>/<owner>/<repo>` is what `--repo` pins with (`[HOST/]OWNER/REPO`,
# host filled from GH_HOST when omitted — `gh help environment`) and what a
# pull-request URL carries, so a hostless pin cannot be re-hosted underneath us;
# the bare `<owner>/<repo>` plus `--hostname` is what `gh api` takes, since a
# `repos/{owner}/{repo}` path is resolved against gh's current repository exactly
# like a bare PR number is.
#
# It comes from the origin remote, NEVER from `gh`: gh's current repository is the
# very thing a foreign same-branch PR arrives through, so asking gh to name the
# expectation would make the check vacuous.
#
# Same parse and same fail-closed rule as check-set-heal.sh's
# resolve_origin_repo/resolve_origin_repo_q, which is the reference
# implementation; these scripts are standalone by design (the patrol resolves and
# runs each one independently, and an importer rig may be running an older pack),
# so the helper is duplicated rather than sourced. Keep them in step.
ORIGIN_HOST=""
ORIGIN_REPO=""
origin_url=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$origin_url" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$origin_url" \
      | sed -e 's#^ssh://git@github.com/##' -e 's#^git@github.com:##' \
            -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
# Exactly `<owner>/<repo>`, or nothing: a half-parsed value would pin the read to
# a repository nobody named.
case "$ORIGIN_REPO" in
  */*/*|/*|*/) ORIGIN_REPO="" ;;
  */*)         : ;;
  *)           ORIGIN_REPO="" ;;
esac
[ -n "$ORIGIN_REPO" ] || ORIGIN_HOST=""
ORIGIN_REPO_Q=""
[ -n "$ORIGIN_REPO" ] && ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"
if [ -z "$ORIGIN_REPO_Q" ]; then
  # FAIL CLOSED. Unresolvable origin means every branch below would be looked up —
  # and a PR CREATED — in a repository this script cannot name. Opening a PR is not
  # a read that can be retried away: a PR opened in the wrong repository is a
  # published artifact, and its URL would then be stamped on this anchor as its
  # identity. Opening nothing this pass costs one idle wake.
  echo "pre-open-resolve: cannot resolve this checkout's origin repository (no origin remote, or not a github.com <owner>/<repo> URL); a branch name would be resolved in whatever repository gh considers current, so NOTHING is opened this pass" >&2
  exit 0
fi

# The repository a pull-request URL names, host-qualified — one definition for
# every place identity is compared. Byte-identical to merge-skill.sh's and
# check-set-heal.sh's url_repo_q; keep them in step.
url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}

# The same question of a COMMIT URL, for certifying the branch-head read. `gh api`
# has no `--repo`, so the pin is the path plus `--hostname`; the commit object's
# own html_url is what says where the answer actually came from.
#
# Only `<host>/<owner>/<repo>` is extracted, so the trailing segment is required
# to be present but is otherwise unconstrained: the question asked here is which
# repository answered, never what a revision identifier looks like.
commit_url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/commit/[^/][^/]*$#\1/\2#p'
}

# The pull-request URL an answer names, normalized to
# `<scheme>://<host>/<owner>/<repo>/pull/<n>` — the durable identity form, and the
# form the certification and the number-extraction below both read. Picks the URL
# out of surrounding output (`gh pr create` prints a URL line) and drops any
# `/files` or `#discussion` tail, so one canonical value is compared and stamped.
pr_url_canon() {
  printf '%s\n' "${1:-}" \
    | grep -Eo '[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+/pull/[0-9]+' \
    | tail -1
}

# How many branch-name matches are read before the answer is treated as possibly
# TRUNCATED. `--head` filters on the NAME ALONE, so the rows are "every pull request
# in this repository opened from a branch called this" — ours, plus one per fork that
# reused the name. 100 is far past any real branch's PR count; a full page is treated
# as "I cannot see all of them" rather than as a complete answer, because the
# caller's fall-through on "no PR of ours" is to OPEN one, and a twin PR is a
# published artifact no retry can take back.
PR_LIST_LIMIT=100

# certify_pr_row <bead-id> <pr-json-object> <want-branch> <want-target> <want-number> <action>
#
# "Is this row really THIS anchor's pull request?" — asked of a PR that arrived by
# BRANCH NAME, the weakest identifier this script handles. `gh pr list --head` and
# `gh pr view <branch>` filter on the name alone, and a branch name is owned by
# nobody: every fork of this repository can open a pull request INTO it from a branch
# called exactly `polecat/<bead>`. Such a PR lives in THIS repository, so it carries
# one of OUR urls — and the url check, all this pass used to have, passes on it while
# its head is a stranger's (review tk-j0q41). The head repository is the half a
# same-repo url cannot answer, and it is exactly the half a fork differs in.
#
# So every half of the identity is asked:
#   url          the PR belongs to this checkout's origin repository, host-qualified
#   head branch  it is opened from the branch this anchor records (the right work)
#   head repo    ...and that branch is OURS, not a fork's branch of the same name
#   base         it targets the branch this anchor is landing on
#   number       when the caller already has one — the row is the PR it just created,
#                not whatever else answered
#
# THREE answers, because the caller's disposition differs by kind. Collapsing the two
# failures into one is what makes a fork PR either block us forever or, worse, be
# mistaken for "no PR exists" when the truth was "I could not read the row":
#   0  CERTIFIED  -> CERT_NUM / CERT_URL / CERT_STATE / CERT_BASE hold trusted fields
#   1  NOT OURS   -> a fully readable row that is definitively somebody else's. The
#                    caller keeps scanning: our PR may be further down the same list.
#   2  UNREADABLE -> a field is absent, null, or the row will not parse. "I cannot
#                    tell" is NOT "not ours" — the caller must refuse the whole branch,
#                    because the fall-through from "no PR of ours" OPENS one.
CERT_NUM=""
CERT_URL=""
CERT_STATE=""
CERT_BASE=""
certify_pr_row() {
  local id="$1" row="$2" wantbranch="$3" wanttarget="$4" wantnum="$5" action="$6"
  local num url state base head hrepo cross goturl live_repo_q
  CERT_NUM=""; CERT_URL=""; CERT_STATE=""; CERT_BASE=""

  [ -n "$row" ] && printf '%s' "$row" | jq -e 'type == "object"' >/dev/null 2>&1 || {
    echo "pre-open-resolve: $id branch '$wantbranch' — a pull-request row did not parse as an object; cannot certify it before $action, so NOTHING is done for this branch this pass (retry next pass)" >&2
    return 2
  }
  num=$(printf '%s' "$row"   | jq -r '.number // "" | tostring' 2>/dev/null)
  url=$(printf '%s' "$row"   | jq -r '.url // ""' 2>/dev/null)
  state=$(printf '%s' "$row" | jq -r '.state // ""' 2>/dev/null)
  base=$(printf '%s' "$row"  | jq -r '.baseRefName // ""' 2>/dev/null)
  head=$(printf '%s' "$row"  | jq -r '.headRefName // ""' 2>/dev/null)
  # `<owner>/<repo>` of the branch the PR is opened FROM, assembled defensively: gh
  # returns these as objects that are NULL when the head repository was deleted, and a
  # half-resolved "owner/" would compare unequal by luck rather than by design. Either
  # both halves are present or the value is empty — and empty is UNREADABLE, not
  # foreign. Compared BARE: a PR's head repository is always on the PR's own host, so
  # gh reports it hostless, and the host half of the identity is carried by the url.
  hrepo=$(printf '%s' "$row" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  # GitHub's own answer to "is the head somewhere else?", kept alongside the
  # owner/repo comparison rather than instead of it. Defence in depth on the one
  # check whose failure binds this anchor to a stranger's pull request: the explicit
  # comparison catches a wrong repository, this catches a head this script failed to
  # resolve into one. Read as a string so a missing field is empty, not "false".
  cross=$(printf '%s' "$row" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)

  # A partial or schema-shifted response leaves the identity UNCERTIFIED, which is
  # exactly what must not be acted on: `gh` answering is not the same as `gh`
  # answering the question.
  # The number is required to READ AS ONE as well as to be present: it is compared and
  # ranked numerically below, and a non-numeric value would make those comparisons
  # error rather than decide.
  if [ -z "$url" ] || [ -z "$state" ] || [ -z "$base" ] || [ -z "$head" ] \
     || [ -z "$hrepo" ] || [ -z "$cross" ] \
     || [ -z "$num" ] || [ -n "${num//[0-9]/}" ]; then
    echo "pre-open-resolve: $id branch '$wantbranch' — pull-request identity is unreadable (number='$num' url='$url' state='$state' base='$base' head='$head' headrepo='$hrepo' cross='$cross'); cannot certify it before $action, so NOTHING is done for this branch this pass (retry next pass)" >&2
    return 2
  fi

  goturl=$(pr_url_canon "$url")
  live_repo_q=$(url_repo_q "$goturl")
  if [ -z "$goturl" ] || [ -z "$live_repo_q" ]; then
    echo "pre-open-resolve: $id branch '$wantbranch' — PR#$num answered with url '$url', which is not a parseable pull-request url; cannot certify which repository it belongs to before $action, so NOTHING is done for this branch this pass (retry next pass)" >&2
    return 2
  fi
  # `--repo` pinned the read, so this should be a tautology — and it is kept precisely
  # because it should be: a gh that ignores the flag, a redirect after a repository
  # transfer or rename, or a re-hosted `<owner>/<repo>` surfaces HERE as a refusal
  # instead of as a flip.
  if [ "$live_repo_q" != "$ORIGIN_REPO_Q" ]; then
    echo "pre-open-resolve: $id branch '$wantbranch' matched PR#$num at '$live_repo_q', not this checkout's '$ORIGIN_REPO_Q'; that is another repository's pull request — not $action" >&2
    return 1
  fi
  if [ -n "$wantnum" ] && [ "$num" != "$wantnum" ]; then
    echo "pre-open-resolve: $id branch '$wantbranch' — asked for PR#$wantnum and PR#$num answered; the read did not return the pull request it was pinned to — not $action" >&2
    return 1
  fi
  if [ "$head" != "$wantbranch" ]; then
    echo "pre-open-resolve: $id records branch '$wantbranch' but PR#$num is opened from '$head'; the anchor and the pull request describe different work — not $action" >&2
    return 1
  fi
  # THE FORK GAP. A branch name matches; a repository is what makes it ours. A pull
  # request opened INTO this repository FROM a fork's `polecat/<bead>` passes every
  # check above — same repository url, same head branch NAME — and differs only here.
  if [ "$hrepo" != "$ORIGIN_REPO" ]; then
    echo "pre-open-resolve: $id records branch '$wantbranch' and PR#$num is opened from a branch of that name — but in FORK '$hrepo', not '$ORIGIN_REPO'; the branch name matches by coincidence, the work does not — not $action" >&2
    return 1
  fi
  # ...and GitHub's own answer must agree with that comparison. A row claiming OUR
  # head repository while also reporting itself cross-repository is not a tie to
  # break in either direction: an identity that contradicts itself has not been
  # established, so it is UNREADABLE rather than "not ours".
  if [ "$cross" != "false" ]; then
    echo "pre-open-resolve: $id PR#$num reports head repository '$hrepo' (this checkout's own) and cross-repository='$cross' at the same time; the two halves of the head identity disagree, so it is not certified before $action — NOTHING is done for this branch this pass (retry next pass)" >&2
    return 2
  fi
  if [ "$base" != "$wanttarget" ]; then
    echo "pre-open-resolve: $id lands on '$wanttarget' but PR#$num targets '$base'; the anchor and the pull request describe different work — not $action" >&2
    return 1
  fi

  CERT_NUM="$num"
  CERT_URL="$goturl"
  CERT_STATE="$state"
  CERT_BASE="$base"
  return 0
}

# find_certified_pr <bead-id> <branch> <target> <action>
#
# THE branch's pull request in this repository, or a reasoned refusal. Replaces the
# old "take the first `--head` match and check its url": `--head` is a NAME filter, so
# the first row is not the anchor's PR by any property except arrival order — a fork
# row can sort ahead of the real one (review tk-j0q41). Every row is certified and the
# winner is chosen among those that pass.
#
#   0  found      -> CERT_* hold the certified PR
#   1  none       -> the read was complete and clean and NOTHING is opened from a
#                    branch of this name here. The ONLY answer on which the caller may
#                    go on to open one.
#   2  refuse     -> the read failed, may be truncated, a row was unreadable, or rows
#                    matched the name and NOT ONE of them certified. The caller must do
#                    NOTHING for this branch. "I could not see it" and "it is not
#                    there" differ by exactly one twin pull request — and so do "no
#                    pull request is open from this branch" and "the only ones open
#                    from a branch of this name are somebody else's". A name collision
#                    is a state an operator must look at, not one to open a pull
#                    request into.
find_certified_pr() {
  local id="$1" branch="$2" target="$3" action="$4"
  local json rc n row rank best_rank=99 best_num="" best_url="" best_state="" best_base=""
  CERT_NUM=""; CERT_URL=""; CERT_STATE=""; CERT_BASE=""

  # --state ALL (not just open): a sibling PR that already MERGED or closed must still
  # flip this anchor onto the pull_request scan the observer watches — otherwise a
  # parent left in pre_open_gate after a pre-open rework, whose sibling PR merged,
  # would strand open forever (reconcile-merged-prs.sh scans only pull_request).
  json=$(gh pr list --head "$branch" --state all --repo "$ORIGIN_REPO_Q" \
    --json number,url,state,baseRefName,headRefName,headRepository,headRepositoryOwner,isCrossRepository \
    --limit "$PR_LIST_LIMIT" 2>/dev/null)
  rc=$?
  # A FAILED READ IS NOT AN EMPTY ONE. Three guards, because a read that DIED AFTER
  # EMITTING arrives as a well-formed short array and passes any one of them alone:
  # the command's own exit status, output at all, and the shape. Read as "no PR
  # exists", any of these opens a SECOND pull request for a branch that already has
  # one — the twin this whole path exists to prevent.
  if [ "$rc" -ne 0 ] || [ -z "$json" ] \
     || ! printf '%s' "$json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "pre-open-resolve: $id could not read this repository's pull requests for branch '$branch' (gh rc=$rc); that is not the same as there being none, and acting on it would open a twin — not $action (retry next pass)" >&2
    return 2
  fi
  # The row COUNT is load-bearing twice below — the truncation guard, and telling a
  # clean "nothing is open from this branch" from "nothing of OURS is". A count that
  # will not read as a number leaves both unanswerable, so it is a refusal too.
  n=$(printf '%s' "$json" | jq 'length' 2>/dev/null)
  case "$n" in
    ''|*[!0-9]*)
      echo "pre-open-resolve: $id could not count this repository's pull requests for branch '$branch'; 'no pull request of ours' cannot be concluded from an answer that will not count — not $action (retry next pass)" >&2
      return 2 ;;
  esac
  # A FULL PAGE IS NOT A COMPLETE ANSWER. Refuse rather than conclude "no PR of ours"
  # from a list that may have been cut short of the row that says otherwise.
  if [ "$n" -ge "$PR_LIST_LIMIT" ]; then
    echo "pre-open-resolve: $id branch '$branch' matched $n pull requests, the whole page this pass reads; the list may be truncated, so 'no pull request of ours' cannot be concluded from it — not $action (operator must repair)" >&2
    return 2
  fi

  while IFS= read -r row; do
    [ -n "${row:-}" ] || continue
    certify_pr_row "$id" "$row" "$branch" "$target" "" "$action"
    case $? in
      0) : ;;
      2) return 2 ;;
      *) continue ;;
    esac
    # Rank by what the anchor needs from the PR, not by arrival order. OPEN is the
    # live pull request the merge gate will act on; MERGED is the one the observer
    # closes the anchor on; a CLOSED-unmerged PR is dead and binds last, so it can
    # never outrank a real one. Higher number breaks a tie within a rank: the later
    # pull request is the current attempt.
    case "$CERT_STATE" in
      OPEN)   rank=0 ;;
      MERGED) rank=1 ;;
      *)      rank=2 ;;
    esac
    if [ "$rank" -lt "$best_rank" ] \
       || { [ "$rank" -eq "$best_rank" ] && [ "$CERT_NUM" -gt "${best_num:-0}" ]; }; then
      best_rank="$rank"; best_num="$CERT_NUM"; best_url="$CERT_URL"
      best_state="$CERT_STATE"; best_base="$CERT_BASE"
    fi
  done <<< "$(printf '%s' "$json" | jq -c '.[]' 2>/dev/null)"

  if [ -z "$best_num" ]; then
    CERT_NUM=""; CERT_URL=""; CERT_STATE=""; CERT_BASE=""
    # NOTHING MATCHED vs NOTHING OF OURS MATCHED. The first is the clean "this branch
    # has no pull request", on which the caller opens one. The second is a NAME
    # COLLISION — every pull request open from a branch of this name belongs to
    # somebody else — and it is not a licence to open one: the refusals above have
    # already said which half of the identity each row failed, and an operator can act
    # on that. Opening a pull request is a published artifact no retry takes back, so
    # the ambiguous case costs one idle wake instead.
    if [ "$n" -gt 0 ]; then
      echo "pre-open-resolve: $id branch '$branch' matched $n pull request(s) in '$ORIGIN_REPO_Q' and NONE of them is this anchor's (see the refusals above); a branch name is not a claim on it — not $action (operator must repair)" >&2
      return 2
    fi
    return 1
  fi
  CERT_NUM="$best_num"; CERT_URL="$best_url"
  CERT_STATE="$best_state"; CERT_BASE="$best_base"
  return 0
}

# flip_to_pull_request <bead-id> <pr-url> <pr-number> <target> <what-happened>
#
# Hand the anchor to the normal merge gate — in the one ORDER that survives a partial
# write. `merge_result=pull_request` is not one field among four: it is the VISIBILITY
# SWITCH. `pre_open_gate` is the only sub-state that opens (or re-adopts) a PR, and
# `pull_request` is the sub-state merge-skill.sh and reconcile-merged-prs.sh act on. Both
# were written in a SINGLE `gc bd update` alongside pr_url/pr_number/merged_target, so a
# write that persisted the switch but dropped any dependent field left the anchor having
# LEFT the only state that would ever open its PR and ENTERED the states that act on a
# pr_url/pr_number it does not have — where both passes skip it on `[ -z "$num" ]` and
# nothing routes it back. That is the invisible-anchor failure tk-wsxd0 exists to end,
# reached from the other side: an anchor whose PR is open and whose bead is inert
# (review tk-pka2d finding #1).
#
# So: the dependent fields are written FIRST, VERIFIED BY RE-READ, and only then is the
# switch flipped — the same "verified by re-read" rule check-set-heal.sh applies to its
# own check_set stamp, for the same reason: a `gc bd update` that returns is not a ledger
# that holds it.
#
# EVERY failure direction leaves the anchor in `pre_open_gate`, which is the idempotent,
# self-healing one: the next pass takes the "a PR already exists for this branch" arm,
# re-certifies that same PR (never opening a twin) and retries the whole sequence.
#
#   0  flipped  -> identity fields persisted AND merge_result=pull_request stamped
#   1  held     -> nothing durable changed the anchor's state; it stays pre_open_gate
flip_to_pull_request() {
  local id="$1" url="$2" num="$3" target="$4" what="$5"
  local meta got_url got_num got_target got_mr

  # 1. The dependent fields, WITHOUT the switch. An anchor still in pre_open_gate that
  #    carries a pr_url is harmless: no other pass reads pre_open_gate, and this one
  #    re-derives and re-certifies the PR from the branch on every pass regardless.
  gc bd update "$id" \
    --set-metadata pr_url="$url" \
    --set-metadata pr_number="$num" \
    --set-metadata merged_target="$target" >/dev/null 2>&1

  # 2. Did the ledger actually take them? All three are checked, because each is what a
  #    later pass needs to act on this PR at all: pr_number is how both passes find it,
  #    pr_url is the identity they re-certify it against, merged_target is the branch the
  #    observer's retarget guard compares the live base to.
  meta=$(gc bd show "$id" --json 2>/dev/null)
  got_url=$(printf '%s' "$meta"    | jq -r '.[0].metadata.pr_url // empty' 2>/dev/null)
  got_num=$(printf '%s' "$meta"    | jq -r '.[0].metadata.pr_number // "" | tostring' 2>/dev/null)
  got_target=$(printf '%s' "$meta" | jq -r '.[0].metadata.merged_target // empty' 2>/dev/null)
  if [ "$got_url" != "$url" ] || [ "$got_num" != "$num" ] || [ "$got_target" != "$target" ]; then
    echo "pre-open-resolve: $id PR#$num $what, but its identity fields did NOT persist (pr_url='${got_url:-<empty>}' want '$url'; pr_number='${got_num:-<empty>}' want '$num'; merged_target='${got_target:-<empty>}' want '$target'); merge_result is NOT flipped — the anchor stays pre_open_gate, where the next pass re-adopts this same PR and retries. Flipping now would make it visible to the merge and observer passes with no PR identity for them to act on, and nothing would route it back." >&2
    return 1
  fi

  # 3. ONLY NOW the visibility switch, on its own. A failure HERE is the safe half of the
  #    split: the anchor keeps its (correct, verified) identity fields and stays
  #    pre_open_gate, so the existing-PR arm re-certifies and re-flips next pass.
  gc bd update "$id" --set-metadata merge_result=pull_request >/dev/null 2>&1
  got_mr=$(gc bd show "$id" --json 2>/dev/null | jq -r '.[0].metadata.merge_result // empty' 2>/dev/null)
  if [ "$got_mr" != "pull_request" ]; then
    echo "pre-open-resolve: $id PR#$num $what and its identity fields persisted, but merge_result is still '${got_mr:-<empty>}'; the anchor stays pre_open_gate and the next pass re-adopts the same PR (no twin — the existing-PR arm certifies it before adopting)" >&2
    return 1
  fi
  return 0
}

# Truthy in the operators' sense: set, and not one of the explicit "off" spellings.
# Mirrors merge-skill.sh's merge_hold_truthy exactly, so a marker that holds a merge
# there cannot fail to hold a PR-OPEN here — which is the stronger claim of the two,
# because a merge that is deferred can be performed next pass and a pull request that
# was opened cannot be un-published. Duplicated rather than sourced for the same
# reason as url_repo_q above (the patrol runs each script independently, and an
# importer rig may be on an older pack); keep them in step with
# reconcile-merged-prs.sh's and reconcile-graduated-convoys.sh's is_held.
is_held() {
  case "${1:-}" in
    ""|false|False|FALSE|0|null) return 1 ;;
    *) return 0 ;;
  esac
}

# Open pre-open-gated anchors in this rig's ledger.
ANCHORS=$(gc bd list --status=open \
  --metadata-field merge_result=pre_open_gate \
  --limit=200 --json 2>/dev/null)
[ -n "$ANCHORS" ] && [ "$ANCHORS" != "[]" ] \
  || { echo "pre-open-resolve: no pre-open anchors"; exit 0; }

# One compact JSON row per anchor. Built into a variable (not piped into the loop)
# so the loop runs in THIS shell and the counters below survive the pipe boundary.
ROWS=$(printf '%s' "$ANCHORS" \
  | jq -c '.[] | {
      id,
      branch: (.metadata.branch // ""),
      target: (.metadata.merged_target // .metadata.target // ""),
      title:  (.title // ""),
      desc:   (.description // ""),
      notes:  (.notes // ""),
      itype:  (.issue_type // "task"),
      prio:   (.priority // ""),
      codex:  (.metadata["check.codex"] // ""),
      hold:   ((.metadata.merge_hold // "") | tostring),
      rhold:  ((.metadata.rebase_hold // "") | tostring)
    }' 2>/dev/null)
[ -n "$ROWS" ] || { echo "pre-open-resolve: no pre-open anchors"; exit 0; }

created=0; flipped=0; held=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  branch=$(printf '%s' "$row" | jq -r '.branch // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  if [ -z "$id" ] || [ -z "$branch" ]; then
    skipped=$((skipped + 1)); continue
  fi
  [ -n "$target" ] || target="main"

  # --- A PR already exists for this branch (any state)? ------------------------
  # If a sibling anchor's resolve (or a post-open rework) already opened it, flip
  # THIS anchor to pull_request so it becomes visible to the merge skill + the
  # merged-close observer (never open a twin). The flip stamps NO gate marker, so
  # the merge skill still re-gates before any merge.
  #
  # Every candidate is CERTIFIED before it can become this anchor's identity, and a
  # refusal is the fail-closed direction: flipping on a foreign pull request would
  # move this anchor OUT of pre_open_gate — the only state that retries PR-open —
  # and stamp a stranger's pr_url/pr_number as its identity, so the real PR would
  # never be opened by anything. Holding leaves the anchor exactly where the next
  # pass can still open it.
  find_certified_pr "$id" "$branch" "$target" \
    "flipped to pull_request, anchor stays pre_open_gate"
  case $? in
    0)
      if flip_to_pull_request "$id" "$CERT_URL" "$CERT_NUM" "$target" \
           "was already open for branch '$branch'"; then
        flipped=$((flipped + 1))
        echo "pre-open-resolve: $id branch '$branch' already has PR#$CERT_NUM; flipped to pull_request"
      else
        skipped=$((skipped + 1))
      fi
      continue ;;
    2)
      # "I cannot tell" — never fall through to the create path on it. Every
      # certification failure has already named itself on stderr.
      skipped=$((skipped + 1)); continue ;;
  esac
  # rc=1: this repository has no pull request of OURS for this branch. The only
  # answer this pass may open one on.

  # --- Operator hold, checked before anything is published. ---------------------
  # merge_hold/rebase_hold on the anchor are explicit operator gates, and until
  # tk-3j0ob this pass honored NEITHER: a hold stopped a held anchor from MERGING
  # (merge-skill.sh) while the open side walked straight past it and PUBLISHED a
  # pull request against it. The failure was silent in the worst way — the operator
  # sees a hold in place and a new PR appear anyway.
  #
  # Checked FIRST among the create-path gates, and on fields already in hand: it is
  # the cheapest gate (no further I/O) and the highest priority (an intentional
  # operator block, independent of branch and codex state), so a held anchor
  # short-circuits before the branch-head read — the same ordering merge-skill.sh
  # gives it among its validate gates.
  #
  # DELIBERATELY AFTER the existing-PR arm above, which is not a publishing action:
  # it adopts a pull request that ALREADY exists and hands the anchor to gates that
  # honor these same markers themselves (merge-skill.sh holds on merge_hold;
  # reconcile-merged-prs.sh holds its rebase dispatch on either). Holding the flip
  # too would buy nothing and would COST the convergence it exists for —
  # pre_open_gate is invisible to the merged-close observer, which scans only
  # pull_request, so a held anchor whose sibling PR merged would leak open forever.
  # The hold belongs on the irreversible half: opening a pull request publishes an
  # artifact no retry takes back, while a deferred open costs one idle wake.
  #
  # Either marker vetoes, for distinct reasons. merge_hold is "do not land this
  # yet", and opening the PR is what arms the landing. rebase_hold is the narrower
  # "do not rebase/force-push this branch" — which is exactly the branch this pass
  # would publish a pull request FROM, and this pass's whole contract is that a PR
  # is codex-green AT BIRTH: a branch the operator has frozen for rewriting is one
  # whose reviewed head is expected to move, so the PR would be born green and be
  # stale moments later, over a comment asserting a signoff at a commit that has
  # left the branch. Same reading as reconcile-graduated-convoys.sh, which vetoes
  # on either for the same "publishes something the operator froze" reason.
  hold=$(printf '%s' "$row" | jq -r '.hold // empty')
  rhold=$(printf '%s' "$row" | jq -r '.rhold // empty')
  if is_held "$hold"; then
    echo "pre-open-resolve: $id branch '$branch' merge_hold set (operator gate); no PR opened"
    held=$((held + 1)); continue
  fi
  if is_held "$rhold"; then
    echo "pre-open-resolve: $id branch '$branch' rebase_hold set (operator gate); no PR opened"
    held=$((held + 1)); continue
  fi

  # --- No PR yet: gate on check.codex=green@<live branch head>. -----------------
  # The reviewed OID is the branch head the pre-open signoff validated. Read the
  # LIVE head via gh (no local checkout needed). If codex is not green at that
  # exact head — reviewer not done, or a rework advanced the head so the marker is
  # stale — HOLD; a rework's fresh review re-stamps the new head next pass.
  #
  # PINNED to this checkout's repository: `{owner}/{repo}` is a placeholder gh
  # fills from its CURRENT repository, so the old form asked another repository
  # for the head of its own same-named branch — and that head is what the codex
  # marker is then compared against, deciding whether a PR opens at all. `gh api`
  # has no `--repo`, so the pin is the explicit path plus `--hostname`.
  HEAD_JSON=$(gh api --hostname "$ORIGIN_HOST" "repos/$ORIGIN_REPO/commits/$branch" 2>/dev/null)
  head_oid=$(printf '%s' "$HEAD_JSON" | jq -r '.sha // empty' 2>/dev/null)
  if [ -z "$head_oid" ]; then
    echo "pre-open-resolve: $id branch '$branch' head unresolved; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  # And did the answer come from this repository? The commit object names where
  # it lives; a gh wrapper or a redirect that served another repository's branch
  # head surfaces here as a skip rather than as a PR opened at a head this
  # branch never had. An html_url that does not parse is not a pass.
  head_repo_q=$(commit_url_repo_q "$(printf '%s' "$HEAD_JSON" | jq -r '.html_url // empty' 2>/dev/null)")
  if [ "$head_repo_q" != "$ORIGIN_REPO_Q" ]; then
    echo "pre-open-resolve: $id branch '$branch' head answered from '${head_repo_q:-<unparseable>}', not this checkout's '$ORIGIN_REPO_Q'; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  codex_mark=$(printf '%s' "$row" | jq -r '.codex // empty')
  if [ "$codex_mark" != "green@$head_oid" ]; then
    echo "pre-open-resolve: $id branch '$branch' codex not green at live head (have '${codex_mark:-none}', want 'green@$head_oid'); held"
    held=$((held + 1)); continue
  fi

  # --- Open the non-draft PR at the reviewed head. -----------------------------
  # Body mirrors merge-push: full description (the "why") + polecat notes (the
  # "what") + a handoff footer. --body-file avoids multi-line quoting hazards.
  title=$(printf '%s' "$row" | jq -r '.title // empty')
  desc=$(printf '%s'  "$row" | jq -r '.desc // empty')
  notes=$(printf '%s' "$row" | jq -r '.notes // empty')
  itype=$(printf '%s' "$row" | jq -r '.itype // "task"')
  prio=$(printf '%s'  "$row" | jq -r '.prio // empty')

  PR_BODY_FILE=$(mktemp)
  {
    echo "## Summary"
    echo
    if [ -n "$desc" ]; then printf '%s\n' "$desc"; else
      printf 'Refinery handoff for `%s` (no bead description recorded).\n' "$id"; fi
    if [ -n "$notes" ]; then
      echo; echo "## Implementation notes"; echo; printf '%s\n' "$notes"; fi
    echo
    echo "## Refinery handoff"
    echo
    printf -- '- Issue: `%s` (%s%s)\n' "$id" "$itype" "${prio:+, P$prio}"
    printf -- '- Source branch: `%s`\n' "$branch"
    printf -- '- Target: `%s`\n' "$target"
    printf -- '- Codex signed off pre-open at `%.8s`; PR opened codex-green.\n' "$head_oid"
  } > "$PR_BODY_FILE"

  # PINNED like every read above: the PR must be created in the repository whose
  # branch head was just certified, not in whatever repository gh considers
  # current at this instant.
  CREATED_URL=$(pr_url_canon "$(gh pr create \
    --repo "$ORIGIN_REPO_Q" \
    --base "$target" \
    --head "$branch" \
    --title "$title ($id)" \
    --body-file "$PR_BODY_FILE" 2>/dev/null || true)")
  rm -f "$PR_BODY_FILE"

  PR_URL=""; PR_NUMBER=""
  if [ -z "$CREATED_URL" ]; then
    # A create race (a concurrent open) is not fatal — discover the PR instead. The
    # discovery is the SAME certified branch scan as the top of the loop, never
    # `gh pr view <branch>`: resolving a pull request by branch NAME is the very gap
    # this pass is closing, and a race-winner discovered that way could be a fork's
    # same-named branch (review tk-j0q41). Re-scanning also re-answers "does a PR of
    # ours now exist" with all three dispositions intact.
    find_certified_pr "$id" "$branch" "$target" \
      "stamped as this anchor's pull request, anchor stays pre_open_gate"
    case $? in
      0) PR_URL="$CERT_URL"; PR_NUMBER="$CERT_NUM" ;;
      1) # Not a race after all: nothing is open from this branch, so the create
         # failed for a reason of its own (no commits between base and head, a
         # permissions or protection rule). Nothing to adopt, nothing to stamp.
         echo "pre-open-resolve: $id branch '$branch' PR create/discover failed; skip (retry next pass)" >&2
         skipped=$((skipped + 1)); continue ;;
      *) # Something is open from a branch of this name and it could not be certified
         # as ours (the scan has already said which half failed). Adopting it is
         # exactly the mistake this pass exists to refuse.
         echo "pre-open-resolve: $id branch '$branch' PR create produced nothing and the discovery could not be certified (see above); NOTHING stamped, anchor stays pre_open_gate (operator must repair)" >&2
         skipped=$((skipped + 1)); continue ;;
    esac
  else
    # THE ANSWER IS CERTIFIED BEFORE IT BECOMES THIS ANCHOR'S IDENTITY. Everything
    # downstream — the comment, the pr_url/pr_number stamp, and every later pass that
    # reads them — trusts this URL. A pin that was ignored or a redirect must not be
    # stamped: that is precisely how the anchor would leave pre_open_gate (the only
    # PR-open-retrying state) pointing at a stranger's pull request. The url half is
    # checked FIRST, because it is the only half a create answer carries on its own.
    pr_repo_q=$(url_repo_q "$CREATED_URL")
    if [ "$pr_repo_q" != "$ORIGIN_REPO_Q" ]; then
      echo "pre-open-resolve: $id branch '$branch' PR create/discover answered '$CREATED_URL' in '${pr_repo_q:-<unparseable>}', not this checkout's '$ORIGIN_REPO_Q'; NOTHING stamped, anchor stays pre_open_gate (operator must repair)" >&2
      skipped=$((skipped + 1)); continue
    fi
    # Read the number off the certified URL rather than asking gh for it: the URL
    # already carries it, and a lookup BY NAME would be one more branch-name
    # resolution to distrust.
    PR_NUMBER=$(printf '%s' "$CREATED_URL" | sed -n 's#.*/pull/\([0-9][0-9]*\)$#\1#p')
    if [ -z "$PR_NUMBER" ]; then
      echo "pre-open-resolve: $id opened '$CREATED_URL' but PR number unresolved; skip (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    # A URL IS NOT AN IDENTITY EITHER. `gh pr create` prints where it landed and
    # nothing else, so a create that silently attached to a DIFFERENT head — a
    # `--head` gh resolved in a fork it has push access to, an existing same-branch
    # pull request it adopted instead of creating — answers with a url in this
    # repository and passes the check above. So the created pull request is read back
    # PINNED BY NUMBER (never by branch name) and put through the same certification
    # every discovered row faces: right repository, right head branch, OUR head
    # repository, right base, and the number we were just given.
    NEW_JSON=$(gh pr view "$PR_NUMBER" --repo "$ORIGIN_REPO_Q" \
      --json number,url,state,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository 2>/dev/null)
    if [ -z "$NEW_JSON" ]; then
      echo "pre-open-resolve: $id opened PR#$PR_NUMBER for '$branch' but reading it back failed; NOTHING stamped, anchor stays pre_open_gate (the existing-PR arm adopts it next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if ! certify_pr_row "$id" "$NEW_JSON" "$branch" "$target" "$PR_NUMBER" \
           "stamped as this anchor's pull request; NOTHING stamped, anchor stays pre_open_gate (operator must repair)"; then
      skipped=$((skipped + 1)); continue
    fi
    # AND IT MUST BE AT THE COMMIT CODEX ACTUALLY REVIEWED. `--head` names a MUTABLE
    # ref: the gate above compared check.codex to the branch head read moments ago,
    # but `gh pr create` opens the PR at whatever that ref points to WHEN IT RUNS. A
    # recovery polecat resuming the branch, or an operator fixup landing in that
    # window, publishes a NON-DRAFT PR at an UNREVIEWED commit — the residual risk
    # review tk-pka2d named. The merge gate still holds it (check.codex=green@<old>
    # no longer equals the live head), so nothing lands un-reviewed; but this pass's
    # whole contract is that a PR is codex-green AT BIRTH, and the comment it is about
    # to post says so by commit. Refuse instead: stamp nothing, post nothing, and let
    # the anchor stay pre_open_gate. The next pass adopts this PR through the
    # existing-PR arm (no twin) and the advanced head re-gates through the normal
    # rework path, which is exactly what a moved head is supposed to do.
    new_head_oid=$(printf '%s' "$NEW_JSON" | jq -r '.headRefOid // ""' 2>/dev/null)
    if [ -z "$new_head_oid" ] || [ "$new_head_oid" != "$head_oid" ]; then
      echo "pre-open-resolve: $id opened PR#$PR_NUMBER for '$branch' but it is at head '${new_head_oid:-<unreadable>}', not the reviewed '$head_oid' — the branch moved between the codex gate and the create, so the PR is NOT codex-green at birth; NOTHING stamped, anchor stays pre_open_gate (the existing-PR arm adopts it next pass and the moved head re-gates)" >&2
      skipped=$((skipped + 1)); continue
    fi
    PR_URL="$CERT_URL"; PR_NUMBER="$CERT_NUM"
  fi

  # Replay the recorded codex verdict as a NON-blocking PR comment (#185: never an
  # approval — the city does not approve; approval is human/external). Best-effort:
  # the review bead (anchor_bead=$id, task_kind=review) carries the verdict in its
  # notes; the most recent one under this anchor is the signoff that just passed.
  REVIEW_ID=$(gc bd list \
    --metadata-field task_kind=review \
    --metadata-field anchor_bead="$id" \
    --status=closed,open,in_progress --limit=10 --json 2>/dev/null \
    | jq -r 'sort_by(.updated_at // .created_at) | last | .id // empty' 2>/dev/null)
  VERDICT=""
  [ -n "$REVIEW_ID" ] && VERDICT=$(gc bd show "$REVIEW_ID" --json 2>/dev/null \
    | jq -r '.[0].notes // ""' 2>/dev/null)
  # PINNED: a bare number here would post this anchor's codex verdict onto a
  # stranger's same-numbered pull request.
  if [ -n "$VERDICT" ]; then
    gh pr comment "$PR_NUMBER" --repo "$ORIGIN_REPO_Q" --body "$(printf 'Codex signoff (pre-open, comment-only — not an approval):\n\n%s' "$VERDICT")" \
      >/dev/null 2>&1 || true
  else
    gh pr comment "$PR_NUMBER" --repo "$ORIGIN_REPO_Q" --body "Codex signed off pre-open at \`${head_oid:0:8}\` (comment-only — not an approval)." \
      >/dev/null 2>&1 || true
  fi

  # Flip to the normal gating sub-state. check.codex is already green@head (the PR
  # is born at exactly the reviewed head), so merge-skill.sh merges once CI +
  # approval + CLEAN. Identity fields first, verified, THEN the visibility switch —
  # see flip_to_pull_request: a partial write of that one `gc bd update` used to be
  # able to make the anchor visible with no PR to be visible ABOUT. A failed flip
  # leaves the anchor in pre_open_gate and next pass takes the "PR already open"
  # branch above (idempotent).
  if flip_to_pull_request "$id" "$PR_URL" "$PR_NUMBER" "$target" \
       "was opened for branch '$branch'"; then
    created=$((created + 1))
    echo "pre-open-resolve: $id opened PR#$PR_NUMBER for '$branch' at ${head_oid:0:8} (codex-green); flipped to pull_request"
  else
    # The PR IS open — a published artifact, and the reason the anchor must not be
    # left able to open a second one. It is not lost: the anchor is still
    # pre_open_gate, so the existing-PR arm above re-certifies and re-adopts exactly
    # this PR next pass. Named here so the opened PR appears in the pass output even
    # though the anchor did not complete.
    echo "pre-open-resolve: $id opened PR#$PR_NUMBER for '$branch' at ${head_oid:0:8} (codex-green) but did NOT reach pull_request (see above); anchor stays pre_open_gate and re-adopts this PR next pass" >&2
    skipped=$((skipped + 1))
  fi
done <<< "$ROWS"

echo "pre-open-resolve: $created opened, $flipped flipped, $held held, $skipped skipped"
exit 0
