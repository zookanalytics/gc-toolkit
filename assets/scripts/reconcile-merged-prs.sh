#!/usr/bin/env bash
# reconcile-merged-prs — close-on-land DETECT-ONLY observer pass. Walk the open
# gating anchors (the bead parked OPEN on a published PR — a convoy graduating to
# main, or any mr-mode bead — marked merge_result=pull_request by
# mol-refinery-patrol merge-push step 4) and reconcile each to its pull request's
# real state. This is the OBSERVER half of close-on-land: it RECORDS merges it
# observes and ESCALATES discrepancies, but it has NO merge authority — the merge
# itself is performed by the merge skill (merge-skill.sh), the single writer of
# merged-truth. See docs/work-bead-state-machine.md "Merge: one writer of
# merged-truth".
#
#   PR merged           -> close the anchor "Merged to <target> at <sha>"
#                          (merge_result=merged, merged_sha) — mirrors direct-mode.
#                          This is the convergent RECORD: the merge skill records
#                          its own merge synchronously, and THIS path is the
#                          backstop for a skill that died between merging and
#                          recording (or a merge that happened out-of-band).
#   PR closed, unmerged -> out-of-band close (the refinery did not do it; it
#                          closes its own abandoned PRs + anchors together).
#                          Flag: merge_result=abandoned, route to human, escalate
#                          once. We lack context, so we never auto-close it.
#   PR open, ready      -> DETECT-ONLY: leave it for the merge skill. The observer
#                          never runs `gh pr merge`. The anchor stays OPEN until
#                          this pass observes an authoritative merge.
#   PR open, CONFLICTING -> stale base: the PR cannot merge and never will on its
#                          own. File a rework child to rebase the branch and route
#                          it to the fix pool. The anchor stays gating.
#   PR open, gate STALE -> the check-set is green@<oid> at a head that has since
#                          MOVED (a direct push to the PR branch filed no rework
#                          bead), so merge-skill.sh holds forever (green@<oid> !=
#                          live head) with nothing re-dispatching the review. File
#                          a codex RE-REVIEW child at the live head, routed to the
#                          review pool; the anchor stays gating. One re-review per
#                          head (stale_gate_head); a poolless hold uses a distinct
#                          stale_gate_nopool_head so a pool configured later still
#                          dispatches. Symmetric with CONFLICTING.
#   PR open, gate GREEN
#   but GitHub RED     -> the INVERSE of the stale gate (tk-5niup): the marker is
#                          green at the LIVE head, and it is GitHub that lags —
#                          our own CHANGES_REQUESTED from an earlier round still
#                          stands, pinned to a dead commit, because a COMMENT
#                          review never supersedes the same reviewer's earlier
#                          one. reviewDecision stays CHANGES_REQUESTED and the PR
#                          stays BLOCKED forever, and the stale-gate arm cannot
#                          reach it (the marker is current). Retract OUR OWN
#                          superseded review — never a human's — and record
#                          signoff_dismissed so merge-skill.sh requires a real
#                          external approval, since removing the block is
#                          merge-triggering where CLEAN folds none — and where
#                          native auto-merge is already ARMED it is merge-
#                          triggering SERVER-side, past any requirement this
#                          script can record, so that case retracts nothing at
#                          all. Converges: once dismissed the decision is no
#                          longer CHANGES_REQUESTED, so the arm does not re-enter.
#   PR open, draft      -> skip (drafts are retired, so the refinery creates no
#                          draft PR; a stray draft is left untouched).
#
#   Open PR, no live bead -> ANCHORLESS: the PR outlived its gating bead, so no
#                          automated path can see it at all. Report it and
#                          escalate once. DETECT + SURFACE ONLY — never merge,
#                          close, or reopen it; disposition is an operator call.
#
#   Open PR, live bead but no gating metadata -> UNOWNED: something names the PR
#                          (so it is not anchorless) but nothing will land it —
#                          no merge_result, no branch/target, no merge_strategy.
#                          Reported on its own line, NOT escalated: the naming
#                          bead is live, so this is a routing gap an operator can
#                          close, not a stranded PR. Kept distinct on purpose —
#                          folding it into "tracked" would make the scan quieter
#                          without making it truer.
#
#   ANY state, retargeted (live base != anchor merged_target) -> never close as
#                          landed (the work would land on the wrong branch), and
#                          the merge skill independently refuses to merge it;
#                          route to human + escalate once.
#
# This is the bead-CLOSER + discrepancy-detector half of close-on-land: an anchor
# stays OPEN from PR-creation until THIS pass observes an authoritative merge.
# `closed` thus always means landed, never handed-off. The merge skill that
# actually lands a ready PR (validate -> merge -> record), and the composable
# check-set that gates it, live in merge-skill.sh and
# docs/work-bead-state-machine.md.
#
# The refinery patrol runs this on each idle wake, folded into the find-work
# step's sleep loop, AFTER the merge skill. Convergent + idempotent: a closed
# anchor leaves the gating set (status), an abandoned/retargeted anchor flips off
# merge_result=pull_request, so neither is re-scanned; a transient failure is
# simply retried next idle pass. Cheap — one `gh pr view` per gating anchor, and
# gating anchors are few (bounded by in-flight PRs).
#
# Reconciled from BOTH sides. The per-anchor pass above walks BEAD -> PR; that
# direction can only ever see PRs a live bead still names — so the anchorless pass
# at the end walks PR -> BEAD, and reports open PRs no live bead points at. Neither
# direction alone covers the state where a PR outlives its anchor.
#
# NEITHER direction may assume a PR number names a PR in THIS repository. It used
# to ("each anchor's pr_number resolves in this repo by construction"), and that
# assumption is unsound: a bead names its PR by NUMBER, and `gh` resolves a number
# in whatever repository it considers current. Both reads are pinned with `--repo`,
# and both then COMPARE the returned URL against the pinned expectation before any
# state is written — because the pin is what a redirect, a rename, an older gh or a
# wrapper defeats, and this pass closes beads, mails escalations and dispatches
# rework children off those reads (review tk-vdlbo P1; merge-skill.sh carries the
# same post-read guard for the same reason).
#
# NOT set -e: best-effort, must never abort the patrol's idle loop. A bead is
# CLOSED only on an authoritative merged=true — any tool error skips the anchor,
# it never closes one.
set -uo pipefail

# Pool the stale-base arm routes its rework children to. Passed by the patrol
# (which alone can render {{binding_prefix}}); an anchor may override per-bead
# with metadata.fix_target_pool. Unresolvable -> that arm escalates to human
# instead of filing an unroutable child.
FIX_POOL_DEFAULT=""
# Pool the stale-GATE arm routes its codex RE-REVIEW children to (the codex pool,
# e.g. <rig>/<rig>.polecat-codex — the SAME source as check-set-heal.sh's
# --review-pool). Unset -> that arm cannot dispatch and leaves the anchor HELD
# (it never hand-stamps the gate green), retrying once a pool is configured.
REVIEW_POOL_DEFAULT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix-pool)
      FIX_POOL_DEFAULT="${2:-}"
      if [ $# -ge 2 ]; then shift 2; else shift; fi
      ;;
    --review-pool)
      REVIEW_POOL_DEFAULT="${2:-}"
      if [ $# -ge 2 ]; then shift 2; else shift; fi
      ;;
    *) shift ;;
  esac
done

# gh is the only way to read PR state here (like the codex gate). Without it
# there is nothing to do.
command -v gh >/dev/null 2>&1 || exit 0

# The METHOD carried by the stale-gate re-review this pass may dispatch
# (tk-jufvl). Shares review-dispatch-body.sh with check-set-heal.sh rather than
# keeping a second hand-maintained copy of the prose: a re-review that described
# the job differently from the first-round review would be exactly the divergence
# this fix exists to remove. FAIL-SOFT for the same reason as there — an
# un-dispatched re-review leaves the stale marker in place and the merge HELD, so
# a body that cannot be produced degrades to a title-only bead, loudly.
# Resolved through a symlink for the same reason as check-set-heal.sh: a
# symlinked deploy that could not find the emitter would degrade every re-review
# to a title-only bead behind one stderr line.
_rmpself="${BASH_SOURCE[0]}"
_rmpreal="$(readlink -f "$_rmpself" 2>/dev/null || true)"
[ -n "$_rmpreal" ] && _rmpself="$_rmpreal"
REVIEW_BODY_EMITTER="$(cd "$(dirname "$_rmpself")" && pwd)/review-dispatch-body.sh"

# create_review_bead <title> [note] — mint the re-review carrying the method, echo
# its id (empty on failure, exactly as the bare `gc bd create` it replaces). The
# note is the dispatch-specific context (which head went stale, and why).
create_review_bead() {
  local title="$1" note="${2:-}" body=""
  if [ -x "$REVIEW_BODY_EMITTER" ]; then
    body=$("$REVIEW_BODY_EMITTER" ${note:+--note "$note"} 2>/dev/null) || body=""
  fi
  if [ -z "$body" ]; then
    echo "reconcile-merged-prs: WARN review method unavailable ($REVIEW_BODY_EMITTER); dispatching a TITLE-ONLY re-review — the reviewer will have to pick its own method (tk-jufvl)" >&2
    gc bd create "$title" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null
    return
  fi
  printf '%s' "$body" \
    | gc bd create "$title" -t task --body-file - --json 2>/dev/null \
    | jq -r '.id // empty' 2>/dev/null
}

# THE REPOSITORY EVERY PR READ BELOW IS PINNED TO, host-qualified
# `<host>/<owner>/<repo>` — the form `--repo` takes (`[HOST/]OWNER/REPO`, host
# filled from GH_HOST when omitted) and the form a pull-request URL carries.
#
# A bead names its PR by NUMBER, and `gh pr view <n>` resolves a number in
# whatever repository gh considers CURRENT — `gh repo set-default`, GH_REPO,
# GH_HOST and cwd all move it. This pass has no merge authority, but it does
# CLOSE anchors as landed and escalate out-of-band closes, so a foreign
# same-numbered PR would close a live bead against a stranger's merge and strand
# the real PR — the same identity hazard check-set-heal.sh certifies against, on
# the surface that acts on the certification afterwards (review tk-sdqwh
# finding #2). It comes from the origin remote, never from `gh`: gh's current
# repository is what the hazard arrives through.
#
# Same parse and same fail-closed rule as check-set-heal.sh's
# resolve_origin_repo_q (the reference implementation); these scripts are
# standalone by design, so it is duplicated rather than sourced. Keep them in
# step.
ORIGIN_REPO_Q=""
origin_url=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$origin_url" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_REPO_Q=$(printf '%s' "$origin_url" \
      | sed -e 's#^ssh://git@github.com/##' -e 's#^git@github.com:##' \
            -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO_Q" in
  */*/*|/*|*/) ORIGIN_REPO_Q="" ;;
  */*)         ORIGIN_REPO_Q="github.com/$ORIGIN_REPO_Q" ;;
  *)           ORIGIN_REPO_Q="" ;;
esac
if [ -z "$ORIGIN_REPO_Q" ]; then
  # FAIL CLOSED, as the merge skill does: an unnameable repository means every
  # number below would be read wherever gh happens to point, and this pass writes
  # terminal state (closes, escalations) off those reads. Recording nothing costs
  # one idle wake.
  echo "reconcile-merged-prs: cannot resolve this checkout's origin repository (no origin remote, or not a github.com <owner>/<repo> URL); PR numbers would be read in whatever repository gh considers current — reconcile skipped this pass" >&2
  exit 0
fi

# The SAME repository, hostless. `gh` reports a pull request's HEAD repository as
# `headRepositoryOwner.login` + `headRepository.name` and nothing else — a PR's head
# is always on the PR's own host, so gh omits it — and the head check in the loop
# compares against that shape. Derived from the host-qualified form rather than
# re-parsed, so the two can never disagree. Mirrors merge-skill.sh's ORIGIN_REPO and
# pre-open-resolve.sh's.
ORIGIN_REPO="${ORIGIN_REPO_Q#*/}"

# And the HOST half. `gh api` takes a REST path, which carries `<owner>/<repo>`
# and no host at all, so the host must travel as a separate `--hostname` flag;
# omit it and that half of the identity falls back to $GH_HOST (`gh help
# environment`) — the movable source `--repo` is pinned to keep out. The reviews
# read and the DISMISSAL below are `gh api` calls on a repo-pinned path, so
# without this they are only half pinned: another host's identically-named
# repository has a PR #<n> too, and the dismissal is irreversible. Mirrors
# merge-skill.sh's ORIGIN_HOST and pre-open-resolve.sh's (review tk-5knqi #1).
ORIGIN_HOST="${ORIGIN_REPO_Q%%/*}"

# Every `gh api` call in this script goes through here, so no REST read or write
# can be re-hosted underneath the `--repo` pins the PR reads carry.
gh_api_origin() { gh api --hostname "$ORIGIN_HOST" "$@"; }

# The repository a pull-request URL names, host-qualified — ONE definition for
# every place identity is compared here (the per-anchor read and the anchorless
# scan's PR list). Mirrors merge-skill.sh's url_repo_q and check-set-heal.sh's;
# these scripts are standalone by design, so it is duplicated rather than sourced.
# Keep them in step. Empty output means "not a pull-request URL", which every
# caller must treat as a refusal, never as a match.
url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}

# A pull-request URL reduced to its canonical `<...>/pull/<n>` form: whitespace
# stripped, a `/files` or `#discussion_r...` suffix and any trailing slash trimmed.
# BOTH sides of every URL comparison go through it, so a cosmetic difference is
# never read as a different pull request. Same normalization merge-skill.sh applies
# inline on both sides of its own comparison.
pr_url_canon() {
  printf '%s' "${1:-}" | tr -d '[:space:]' \
    | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##'
}

# Is <needle> one WHOLE line of the newline-separated <haystack>? An empty needle
# is never a member (it would otherwise match the delimiters themselves).
#
# Matched IN-SHELL, never through a `printf '%s\n' "$hay" | grep -qxF "$needle"`
# pipeline, for the same reason the check-set membership test above is: `set -o
# pipefail` is on and `grep -q` exits at the FIRST match, closing the pipe under
# `printf`, which can then take SIGPIPE and make the whole pipeline report 141. The
# `if` then reads a MATCH as a miss — decided by nothing but how many lines happen
# to follow the one that matched. On the anchorless scan below that inverts the
# arm's entire question: a PR that IS tracked by a live bead is reported ANCHORLESS
# and escalated to the mayor, the one finding this pass sends mail about.
list_has_line() { # <haystack> <needle>
  [ -n "${2:-}" ] || return 1
  case $'\n'"${1:-}"$'\n' in
    *$'\n'"$2"$'\n'*) return 0 ;;
  esac
  return 1
}

# Statuses that still mean "a live bead owns this rework". `closed` is the ONLY
# status that releases a branch; every other one — `blocked` and `deferred` above
# all, which is exactly how an operator parks a runaway child — still owns it.
# The conflict arm's pre-dispatch probe used to ask for open,in_progress only, so
# neutralising a child by BLOCKING it (the standard operator move) made that child
# invisible here and the arm filed a second one on the very next pass, dispatching
# a concurrent force-push onto a branch a human had just frozen (tk-gajop).
#
# This is the COMPLEMENT of `closed` over `bd statuses`, enumerated rather than
# expressed as a negation because --status takes a positive list. Any status
# omitted here is a branch owner this probe cannot see, and an invisible owner is
# a second force-push: `hooked` (a child sitting on an agent's hook) and `pinned`
# are just as branch-owning as `blocked`. Re-derive this list if `bd statuses`
# ever grows a new non-closed status.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# --- Which metadata keys name a pull request? --------------------------------
# `pr_number` is the key the refinery stamps, but it is NOT the only key a live
# bead names its PR with. The fork-sync flow records `fork_pr` / `fork_pr_url`
# and no pr_number at all — gascity's gc-qin3c names PR#100 exactly that way. A
# scan keyed on pr_number alone cannot see such a bead in EITHER direction: its
# PR reads as ANCHORLESS on every single pass (a false finding no action can
# clear, re-triaged from scratch every wake), and the in-flight probes below
# cannot see it holding a branch either.
#
# ONE jq `def`, shared by BOTH directions of the reconcile — the BEAD -> PR
# probes (pr_bead_query) and the PR -> BEAD tracked set (the anchorless scan) —
# so a bead visible to one is visible to the other BY CONSTRUCTION. Widening a
# single direction is the specific hazard: teaching only the tracked set flips a
# fork-keyed PR from "anchorless" to tracked-but-unprobeable, which is quieter
# without being truer. Add a key here and every path learns it at once.
#
# Numbers only: a key holding "" or a non-numeric value is dropped rather than
# matched, so an empty pr_number can never join the tracked set.
#
# AND A NUMBER IS NOT AN IDENTITY. Pull numbers are unique only within a
# repository, and this ledger spans rigs with different ones, while every `gh`
# read here is pinned to $ORIGIN_REPO_Q — so a bare number compares THIS
# repository's pull requests against every repository's beads at once. Both
# directions of the scan below write state off that comparison, and both break:
#
#   a foreign LIVE bead   naming #<n> puts <n> in the tracked set, so THIS repo's
#                         open #<n> reads as tracked (or UNOWNED) and its genuinely
#                         anchorless state is never reported — silence that looks
#                         exactly like health;
#   a foreign CLOSED bead naming #<n> resolves as the dead anchor of THIS repo's
#                         #<n>, so it receives the `anchorless_flagged` stamp and is
#                         named in the escalation mail — a write onto a stranger's
#                         bead, which also bounds the escalation for a PR it never
#                         owned (review tk-thvbq finding #2).
#
# So each ref carries the repository its key names, host-qualified: `pr_number` is
# placed by the bead's own `pr_url`, `fork_pr` by its `fork_pr_url`, and a
# `fork_pr_url` ref by itself. `?` is the FAIL-CLOSED wildcard for a key that names
# no URL at all — the pr_number-only shape almost every legacy bead and every
# freshly-recovered anchor wears — and it matches any repository, so this
# qualification only ever RULES OUT a positive, parsed disagreement. It never turns
# today's silence into a new finding, and never widens what may be written.
#
# Same `?`-wildcard rule, same host-qualified form, as check-set-heal.sh's incumbent
# and in-flight guards and merge-skill.sh's hold guards; these scripts are
# standalone by design, so it is duplicated rather than sourced. Keep them in step.
PR_REF_JQ='
def repo_of:
  ([ capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<r>[^/]+/[^/]+)/pull/[0-9]") ] | .[0])
  | (if . == null then "?" else (.h + "/" + .r) end);
def pr_refs:
  ((.metadata // {})) as $m
  | ((($m.pr_url // "") | tostring) | repo_of) as $ur
  | ((($m.fork_pr_url // "") | tostring)) as $fu
  | ($fu | repo_of) as $fr
  | ( ( [ ($m.pr_number // empty) | tostring ] | map(select(test("^[0-9]+$"))) | map({n: ., r: $ur}) )
    + ( [ ($m.fork_pr // empty)   | tostring ] | map(select(test("^[0-9]+$"))) | map({n: ., r: $fr}) )
    + ( [ $fu | scan("/pull/([0-9]+)") | .[0] ]                                | map({n: ., r: $fr}) ) )
  | unique;
def in_repo($o): [ .[] | select(.r == "?" or $o == "?" or .r == $o) ];
def names_pr($n; $o): (pr_refs | in_repo($o) | any(.n == $n));
'

# Does this bead carry metadata any automated path can ACT on? merge_result marks
# a gating anchor (this pass and the merge skill both enumerate from it);
# branch/target/merge_strategy are the rework-child shape a polecat and the
# refinery land. A bead naming a PR with NONE of them tracks the PR without
# owning it — see the UNOWNED arm in the anchorless scan.
GATING_JQ='
def gating:
  [ (.metadata.merge_result // ""), (.metadata.merge_strategy // ""),
    (.metadata.branch // ""), (.metadata.target // "") ]
  | map(select(. != "")) | length > 0;
'

# The compact row every branch-ownership probe yields: the id, whether the bead
# is an anchor (merge_result set) rather than a rework child, and its
# rebase_hold marker.
PROBE_ROW_JQ='.[] | {id, mres: (.metadata.merge_result // ""), rhold: (.metadata.rebase_hold // "")}'

# One guarded ledger read -> the matching beads as a JSON array on stdout.
# --limit=0 so a probe sees the whole set, not a page of it: a truncated page
# could hide the one held child that must veto.
#
# Returns NON-ZERO on a failed read, which every caller must treat as "I cannot
# tell" and NOT as "nobody holds this branch" — the same ""-vs-"[]" distinction
# the anchorless scan fails closed on. A genuinely empty result is the literal
# "[]" and returns zero.
#
# The guards answer DIFFERENT questions, because the failure they share is
# silent: a probe that reports "no rows" when it actually failed reads as
# "nobody holds this branch" and dispatches the force-push. Non-empty stdout
# alone does NOT mean success — `gc ... --json` reports its own failures as a
# non-empty JSON *object* on stdout (`{"error": ...}`, exit 1), which survives an
# emptiness test, yields zero rows through the projection, and so fails OPEN in
# the one direction that is unrecoverable.
#
# (1), (3) and the projection guard (4) in probe_rows are each mutation-pinned by
# a shape only that guard rejects — see the (23) table in the test suite. Delete
# one and exactly one case goes red.
pr_bead_read() {
  local raw rc
  raw=$(gc bd list "$@" --limit=0 --json 2>/dev/null)
  rc=$?
  # (1) The command's own verdict, checked even when it wrote to stdout.
  [ "$rc" -eq 0 ] || return 1
  # (2) No output at all — a broken `gc bd list`, as distinct from "[]". Strictly
  #     an early-out: (3) also rejects empty input (`jq -e` exits non-zero on it),
  #     so no test pins this line alone. Kept because it states the ""-vs-"[]"
  #     contract this helper is built on, in the one place a reader looks for it,
  #     without spawning jq to say it.
  [ -n "$raw" ] || return 1
  # (3) The payload must be the ARRAY of beads we asked for. Rejects an error
  #     object that arrived with a ZERO exit status — and, more sharply, an object
  #     whose values are bead-shaped: `.[]` iterates those happily, so (4) sees a
  #     clean projection and only this guard can tell it was never a bead list.
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}

# Every bead in <statuses> that names THIS repository's PR #<num>, under ANY key
# pr_refs knows, as ONE id-deduped JSON array.
#
# Three KEYED reads unioned, rather than one unkeyed sweep of the ledger:
# --metadata-field filters server-side, and the URL arm is bounded by
# --has-metadata-key fork_pr_url (a handful of beads city-wide) instead of paging
# the whole store once per anchor. fork_pr_url holds a URL and not a number, so
# it cannot be matched by an exact --metadata-field filter at all — the number and
# its repository are parsed out with the SAME pr_refs the tracked set uses.
#
# Fails closed AS A UNIT: if any one read is unreadable the whole query returns
# non-zero. A partial answer is worse than none here, because the callers read
# "no rows" as "nobody holds this branch" and dispatch a force-push onto it. The
# cost of that choice is that a ledger that cannot answer ANY of the three reads
# defers the conflict/stale-gate arms entirely rather than acting on a partial
# view — one deferred pass, announced in the log, against an unrecoverable
# force-push. Same trade the single-read probe already made.
#
# The keyed reads are unioned RAW and the identity rule is applied ONCE, at the
# end, over the union: `names_pr` is then the single place that decides whether a
# bead names THIS repository's PR #<num>, so the three arms cannot drift apart on
# it. It also filters the unkeyed fork_pr_url arm, which by construction returns
# every bead holding that key regardless of number.
pr_bead_query() {
  local statuses="$1" num="$2" acc part
  acc=$(pr_bead_read --metadata-field "pr_number=$num" --status "$statuses") || return 1
  part=$(pr_bead_read --metadata-field "fork_pr=$num" --status "$statuses") || return 1
  acc=$(printf '%s\n%s' "$acc" "$part" | jq -sc 'add' 2>/dev/null) || return 1
  part=$(pr_bead_read --has-metadata-key fork_pr_url --status "$statuses") || return 1
  printf '%s\n%s' "$acc" "$part" \
    | jq -sc --arg n "$num" --arg o "$ORIGIN_REPO_Q" "$PR_REF_JQ"'
        add | unique_by(.id) | [ .[] | select(names_pr($n; $o)) ]' 2>/dev/null
}

# Project a bead array into the compact probe rows the ownership guards read.
probe_rows() {
  local out
  # (4) The projection's own status. Captured into a variable first: emitted
  #     straight to stdout, jq's failure would be the function's LAST status and
  #     still be discarded by the callers' `probe=$(...)` capture.
  out=$(printf '%s' "$1" | jq -c "$PROBE_ROW_JQ" 2>/dev/null) || return 1
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

# Every non-closed bead whose metadata <field> equals <value> — the `branch`
# dimension, an exact match on a single key.
probe_beads() {
  local raw
  raw=$(pr_bead_read --metadata-field "$1=$2" --status "$LIVE_STATUSES") || return 1
  probe_rows "$raw"
}

# Every non-closed bead naming PR #<num> — the PR dimension, across every key a
# bead can name a PR with. Keyed on pr_number alone this missed fork_pr-keyed
# beads entirely, so a rework already in flight under that keying was invisible
# and the arm dispatched a second force-push over it.
probe_beads_pr() {
  local raw
  raw=$(pr_bead_query "$LIVE_STATUSES" "$1") || return 1
  probe_rows "$raw"
}

# Truthy in the operators' sense: set, and not one of the explicit "off" spellings.
# Mirrors merge-skill.sh's reading of merge_hold exactly, so a marker that holds a
# merge there cannot fail to hold a force-push here.
is_held() {
  case "${1:-}" in
    ""|false|False|FALSE|0|null) return 1 ;;
    *) return 0 ;;
  esac
}

# Native auto-merge state for a PR, as a THREE-valued answer: armed / disarmed /
# unknown. The distinction carries the whole guard. A bare
# `gh pr view --json autoMergeRequest | jq -r '.autoMergeRequest // empty'`
# collapses an API error, an auth failure, a rate-limit, and a jq parse error into
# the SAME empty string a genuinely disarmed PR produces — so a read that FAILED
# is indistinguishable from a definite "no", and the caller fails OPEN on the one
# field whose entire job is to stop a server-side merge. Answer "unknown" unless
# the payload is a parseable object that actually CARRIES the key; callers treat
# anything but "disarmed" as armed, because dismissing a review is irreversible
# and an armed auto-merge merges before merge-skill.sh can enforce anything.
automerge_state() {
  local raw
  raw=$(gh pr view "$1" --repo "$ORIGIN_REPO_Q" --json autoMergeRequest 2>/dev/null) \
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

# Route a stale-gate re-review to the codex pool and, ONLY once that route is
# confirmed to have PERSISTED, arm the one-per-head guard (stale_gate_head) on the
# anchor. The route write is what makes the review claimable — a codex polecat
# cannot heal the gate from an unrouted bead — so it is the step that must succeed
# before the head is recorded "dispatched". Stamping stale_gate_head after an
# UNVERIFIED best-effort route was the tk-3xy37 finding: a dropped route write left
# the review unrouted (inert) yet marked the head dispatched, so the one-per-head
# guard skipped it forever and the merge sat held behind a bead nothing could claim
# — the exact silent hold this arm exists to heal. Read the WHOLE route triple back
# — review_pool (durable), gc.routed_to (live), assignee (claimed) — and require the
# DURABLE copy as well as the live one (tk-bdfww); on a miss return 1 and stamp
# NOTHING, so a later pass re-enters the arm (guard unstamped) and repairs the same
# bead via the in-flight probe. Returns 0 armed, 1 not persisted.
arm_stale_gate() {
  local bead="$1" anchor="$2" head="$3" stale="$4" pool="$5" num="$6" got
  local got_pool got_routed got_assignee
  # An empty pool can never make a bead claimable; never "arm" on one (the callers
  # already gate on a non-empty pool, but fail closed here too).
  [ -n "$pool" ] || return 1
  # review_pool is the DURABLE copy of the route, stamped with it. gc.routed_to is
  # working state — a claim consumes it, a re-route rewrites it — so by the time the
  # signoff's retry-release path needs to put an un-stamped review BACK in a pool
  # (template-fragments/polecat-non-impl-done.template.md), the live route may be
  # gone and there is nothing to restore it to. An open, unassigned, UNROUTED review
  # is offered to nobody: the gate is owed forever and the PR sits held. This field
  # is what that path falls back to.
  #
  # So it is READ BACK too, not just written (tk-bdfww). Both fields go out in ONE
  # batched update, and a partial write that persists gc.routed_to while losing
  # review_pool is exactly the shape this read-back exists to catch — verifying
  # only the live half declared the route durable on the evidence of the field
  # that ISN'T. The damage is deferred rather than absent: the arm stamps
  # stale_gate_head, the one-per-head guard closes behind it, a codex polecat
  # claims the review and CONSUMES gc.routed_to, and then a signoff that ends
  # without stamping the gate has to put the review back — with no review_pool
  # left to reconstruct the route from. The bead is released open, unassigned and
  # unrouted, offered to nobody, and the head is already marked dispatched so
  # nothing re-enters this arm. That is the same terminal strand tk-3xy37 closed
  # on the live half, reached through the durable one.
  #
  # The live half stays a match-or-claimed test, identical to check-set-heal.sh's
  # route_ok: a claim CONSUMES gc.routed_to, so a polecat that picked the review
  # up between the write and this read legitimately leaves it empty, and that bead
  # is reachable — re-routing it would hand a claimed review to a second pool.
  # Returning 1 stamps NOTHING, so a later pass re-enters this arm (guard
  # unstamped) and repairs the same bead through the in-flight probe.
  gc bd update "$bead" \
    --set-metadata gc.routed_to="$pool" \
    --set-metadata review_pool="$pool" >/dev/null 2>&1
  got=$(gc bd show "$bead" --json 2>/dev/null \
    | jq -r '.[0] | [(.metadata.review_pool // ""),
                     (.metadata["gc.routed_to"] // ""),
                     (.assignee // "")] | join("|")' 2>/dev/null)
  [ -n "$got" ] || return 1
  IFS='|' read -r got_pool got_routed got_assignee <<< "$got"
  [ "$got_pool" = "$pool" ] || return 1
  [ -n "$got_assignee" ] || [ "$got_routed" = "$pool" ] || return 1
  gc bd update "$anchor" \
    --set-metadata stale_gate_head="${head:-unknown}" \
    --set-metadata blocked_reason="PR#$num check.codex stale (green@$stale, live head ${head:-?}); re-review $bead routed to $pool" >/dev/null 2>&1
  gc session wake "$pool" >/dev/null 2>&1 || true
  return 0
}

# Open gating anchors in this rig's ledger.
ANCHORS=$(gc bd list --status=open \
  --metadata-field merge_result=pull_request \
  --limit=200 --json 2>/dev/null)

# One compact JSON row per anchor. Built into a variable (not piped into the
# loop) so the loop runs in THIS shell and the counters below survive the
# pipe/subshell boundary.
# The anchor's own PR number comes from EVERY key a bead names a PR with, restricted
# to this repository — the same `pr_refs | in_repo` rule the ownership probes above
# use, and the same rule merge-skill.sh's `pr_nums_here` applies to an anchor's own
# identity (review tk-78ty5 finding #5).
#
# Read from `pr_number` ALONE, as this did, a gating anchor keyed only by
# `fork_pr`/`fork_pr_url` — what the fork-sync flow stamps, and it stamps no
# pr_number at all — yields an empty `pr` and is dropped by the loop's own
# `[ -z "$num" ] && skipped` guard. So a live fork-keyed anchor that was merged
# externally, retargeted, left conflicted, or stale-gated never entered ANY of the
# per-anchor arms: not the merged-close, not the abandon escalation, not the rebase
# dispatch, not the stale-gate re-review. It was invisible here while merge-skill.sh
# — which already reads the widened key set — treated it as a live, mergeable
# anchor, and while the anchorless scan below counted its PR owned and stayed quiet.
# A PR nothing reconciles and nothing reports, from the two passes disagreeing about
# which beads own which PRs.
#
# EXACTLY ONE in-repo number or nothing, which is merge-skill.sh's rule for the same
# question: zero says the bead names no PR here, several says it names more than one
# and neither answers "which PR does this anchor gate". Both fall through the
# existing empty-`pr` skip, so an ambiguous anchor is passed over rather than
# reconciled against a number picked arbitrarily.
#
# NOTE the asymmetry with `pr_refs | in_repo` above, which is deliberate and is why
# this is a SEPARATE definition rather than a reuse. `pr_refs` qualifies a bead's
# pr_number by that bead's OWN pr_url, which is right when asking "does some OTHER
# bead's claim collide with this PR" — a foreign bead's number belongs to its own
# repository. Asked of an anchor about ITSELF it is wrong: an anchor whose pr_url
# disagrees with its pr_number would resolve to NO number and be skipped in silence,
# when that disagreement is exactly the operator-facing finding the identity arm
# below exists to report ("anchor X records pr_url ... which is not PR#N"). So a
# bare pr_number/fork_pr is kept unconditionally and only a number scanned out of
# `fork_pr_url` — the one key that carries a repository in its own value — is
# repo-filtered. Byte-for-byte merge-skill.sh's `pr_nums_here`; these scripts are
# standalone by design, so it is duplicated rather than sourced. Keep them in step.
PR_SELF_JQ='
def pr_nums_here($o):
  ( [ (.metadata.pr_number // empty), (.metadata.fork_pr // empty) ] | map(tostring) )
  + ( ((.metadata.fork_pr_url // "") | tostring)
      | [ capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<r>[^/]+/[^/]+)/pull/(?<n>[0-9]+)") ]
      | .[0]
      | if . == null then []
        elif ($o == "" or (.h + "/" + .r) == $o) then [ .n ]
        else [] end )
  | map(select(test("^[0-9]+$"))) | unique;
'
ROWS=""
if [ -n "$ANCHORS" ] && [ "$ANCHORS" != "[]" ]; then
  ROWS=$(printf '%s' "$ANCHORS" \
    | jq -c --arg o "$ORIGIN_REPO_Q" "$PR_SELF_JQ"'.[] | (pr_nums_here($o)) as $ns | {id, pr: (if ($ns | length) == 1 then $ns[0] else "" end), prurl: (.metadata.pr_url // ""), target: (.metadata.merged_target // ""), checkset: (.metadata.check_set // ""), branch: (.metadata.branch // ""), fixpool: (.metadata.fix_target_pool // ""), staled: (.metadata.stale_base_head // ""), stalegate: (.metadata.stale_gate_head // ""), stalegatenopool: (.metadata.stale_gate_nopool_head // ""), codexmark: (.metadata["check.codex"] // ""), hold: (.metadata.merge_hold // ""), rhold: (.metadata.rebase_hold // "")}' 2>/dev/null)
fi
# No anchors is NOT an early exit: the anchorless pass below walks PR -> BEAD and
# is at its MOST relevant here (zero live anchors + open PRs is precisely the
# stranded state it exists to surface). Returning early on an empty gating set —
# as this did before the anchorless arm — would blind the pass exactly when it
# matters. Only the per-anchor loop is skipped.
[ -n "$ROWS" ] || echo "reconcile-merged-prs: no gating anchors"

# The account this pass acts as. The superseded-review arm retracts ONLY reviews
# authored by it — an operator's CHANGES_REQUESTED is a veto and is never ours to
# clear. Unresolvable => the arm cannot tell ours from theirs and does not run,
# which leaves the PR blocked (the safe side).
#
# Pinned to the origin HOST: an account name is host-scoped, so unpinned under a
# drifted $GH_HOST this names a different host's account, and "ours" would then be
# decided by a name GitHub never attributed these reviews to.
SELF_LOGIN=$(gh_api_origin user -q .login 2>/dev/null)

closed=0; abandoned=0; escalated=0; retargeted=0; rebased=0; rebase_held=0; regated=0; gate_held=0; identity_held=0; skipped=0
# Superseded-review retractions (tk-5niup) get their OWN counters: a retraction
# is not a re-review, so folding it into regated/gate_held would misreport the
# stale-gate arm's throughput in the summary line.
retracted=0; retract_held=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  prurl=$(printf '%s' "$row" | jq -r '.prurl // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  hold=$(printf '%s' "$row" | jq -r '.hold // empty')
  rhold=$(printf '%s' "$row" | jq -r '.rhold // empty')
  if [ -z "$id" ] || [ -z "$num" ]; then
    skipped=$((skipped + 1)); continue
  fi

  # Query `mergedAt`, NOT `merged`: `merged` is not a `gh pr view --json` field
  # on supported gh versions — it errors `Unknown JSON field: "merged"` and,
  # with stderr suppressed, empties PR_JSON, so every anchor is skipped forever
  # and close-on-land never closes anything. A non-null `mergedAt` (state also
  # reaches MERGED) is the authoritative merge signal. The test's gh stub
  # rejects unsupported fields to guard against reintroducing this.
  PR_JSON=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json state,mergedAt,mergeCommit,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeable,mergeStateStatus,reviewDecision,url 2>/dev/null)
  if [ -z "$PR_JSON" ]; then
    echo "reconcile-merged-prs: PR#$num view failed; skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
  merged=$(printf '%s' "$PR_JSON" | jq -r 'if (.mergedAt != null) or (.state == "MERGED") then "true" else "false" end')
  is_draft=$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')
  merge_oid=$(printf '%s' "$PR_JSON" | jq -r '.mergeCommit.oid // ""')
  base=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // ""')
  head_ref=$(printf '%s' "$PR_JSON" | jq -r '.headRefName // ""')
  head_oid=$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // ""')
  # `<owner>/<repo>` of the branch the PR is opened FROM, assembled defensively: gh
  # returns both as objects that are NULL when the head repository has been deleted,
  # and a half-resolved "owner/" would compare unequal by luck rather than by design.
  # Either both halves are present or the value is empty — and empty is UNREADABLE.
  # Compared BARE: a PR's head is always on the PR's own host, so gh reports it
  # hostless and the host half of the identity is carried by the url. Byte-identical
  # to merge-skill.sh's and pre-open-resolve.sh's; keep them in step.
  head_repo=$(printf '%s' "$PR_JSON" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  head_cross=$(printf '%s' "$PR_JSON" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)
  abranch=$(printf '%s' "$row" | jq -r '.branch // empty')
  mergeable=$(printf '%s' "$PR_JSON" | jq -r '.mergeable // ""')
  merge_state=$(printf '%s' "$PR_JSON" | jq -r '.mergeStateStatus // ""')
  # Cheap discriminator for the superseded-review arm below: only a PR whose
  # review decision is CHANGES_REQUESTED can be blocked by a standing review, so
  # this one extra field spares every other anchor the reviews-API round trip.
  review_decision=$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // ""')
  pr_url=$(printf '%s' "$PR_JSON" | jq -r '.url // ""')

  # --- identity: is the PR that answered really THIS anchor's PR? -------------
  # Asked BEFORE any state is derived from the answer, because EVERY arm below
  # writes terminal bead state off this one object — retarget-flag + escalate,
  # merged-close, abandoned-close + escalate, rebase-child dispatch, stale-gate
  # re-review — and two of them COPY pr_url onto a bead they file. A bead names
  # its PR by NUMBER, and numbers collide freely across repositories.
  #
  # `--repo` above already pinned the read, so both checks should now be
  # tautologies — and they are kept precisely because they should be: a gh that
  # ignores the flag, a redirect after a repository transfer or rename, a wrapper,
  # or an unparseable URL surfaces HERE as a refusal instead of as a closed anchor.
  # merge-skill.sh asks exactly this question of exactly this read (review
  # tk-sdqwh finding #2); this pass CLOSES beads and mails escalations off it, so
  # it must ask too, at the same place and in the same words (review tk-vdlbo).
  #
  # Refusing costs one idle wake and is retried next pass. Acting on a stranger's
  # pull request closes a live bead against someone else's merge and strands the
  # real PR in the anchorless blind spot — which is not retried away.
  live_url=$(pr_url_canon "$pr_url")
  live_repo_q=$(url_repo_q "$live_url")
  if [ "$live_repo_q" != "$ORIGIN_REPO_Q" ]; then
    echo "reconcile-merged-prs: PR#$num answered from '${live_repo_q:-<unparseable>}', not this checkout's '$ORIGIN_REPO_Q'; that is another repository's pull request — NO state recorded for anchor $id, operator must repair the metadata"
    identity_held=$((identity_held + 1)); continue
  fi
  # The anchor's own recorded URL, when it has one — the identity check-set-heal.sh
  # certified and persisted, re-checked here by a pass that acts on it. An anchor
  # with no pr_url is governed by the pinned read and the repository check above.
  if [ -n "$prurl" ]; then
    want_url=$(pr_url_canon "$prurl")
    if [ "$want_url" != "$live_url" ]; then
      echo "reconcile-merged-prs: PR#$num resolves to '$live_url' but anchor $id records pr_url '$prurl'; the bead and the PR name different pull requests — NO state recorded, operator must repair the metadata"
      identity_held=$((identity_held + 1)); continue
    fi
  fi
  # --- identity, second half: WHERE DOES THIS PULL REQUEST COME FROM? ---------
  # The checks above establish that PR#$num LIVES in this repository. A pull request
  # opened INTO this repository FROM a fork also lives here: same host, same owner,
  # same repo, same number, one of OUR urls — and it passes every check above while
  # its HEAD is a stranger's (review tk-pka2d finding #3). That matters here more
  # than anywhere except the merge itself, because this pass writes TERMINAL state
  # off the object: it closes the anchor as landed, escalates an out-of-band close,
  # flags a retarget, and — worst — dispatches a rebase child whose `fix_branch` is
  # taken from `head_ref` and force-pushed. Against a fork's head that is a rebase
  # dispatched onto a branch this rig does not own.
  #
  # So the same three halves merge-skill.sh certifies, asked before ANY durable
  # action, and every failure records NOTHING and retries next pass:
  #   head repo    the branch is in THIS repository, not a fork of it
  #   cross-repo   ...and GitHub agrees; a self-contradicting identity is
  #                unestablished, not a tie to break
  #   head branch  it is the branch this anchor recorded. Only checked when the
  #                anchor HAS one — a pr_number-only anchor (check-set-heal.sh's
  #                recovery shape, pre-backfill) has nothing to disagree with.
  if [ -z "$head_repo" ] || [ -z "$head_cross" ]; then
    echo "reconcile-merged-prs: PR#$num head identity is unreadable (headrepo='${head_repo:-<empty>}' cross='${head_cross:-<empty>}'); cannot tell whether it is opened from this repository or a fork of it — NO state recorded for anchor $id, retry next pass"
    identity_held=$((identity_held + 1)); continue
  fi
  if [ "$head_repo" != "$ORIGIN_REPO" ]; then
    echo "reconcile-merged-prs: PR#$num is opened from FORK '$head_repo', not this checkout's '$ORIGIN_REPO'; it lives in our repository but the work is not ours — NO state recorded for anchor $id, operator must repair the metadata"
    identity_held=$((identity_held + 1)); continue
  fi
  if [ "$head_cross" != "false" ]; then
    echo "reconcile-merged-prs: PR#$num reports head repository '$head_repo' (this checkout's own) and cross-repository='$head_cross' at the same time; the two halves of the head identity disagree, so it is not certified — NO state recorded for anchor $id, retry next pass"
    identity_held=$((identity_held + 1)); continue
  fi
  if [ -n "$abranch" ] && [ "$head_ref" != "$abranch" ]; then
    echo "reconcile-merged-prs: anchor $id records branch '$abranch' but PR#$num is opened from '$head_ref'; the bead and the PR describe different work — NO state recorded, operator must repair the metadata"
    identity_held=$((identity_held + 1)); continue
  fi

  # Certified: every arm below acts on THIS repository's PR#$num, opened from THIS
  # repository's branch. The rebase and stale-gate arms stamp pr_url onto the beads
  # they file, so hand them the canonical form that just passed identity rather than
  # the raw field.
  pr_url="$live_url"

  # `target` is the anchor's recorded merged_target — the branch it expects to
  # land on. Keep the raw value for the retarget guard below; fall back to the
  # live base only when the anchor never recorded one (older anchors / direct
  # dispatches have nothing to mismatch against).
  recorded_target="$target"
  [ -n "$target" ] || target="${base:-main}"

  # --- Retarget guard: live base must still match the anchor's expected target.
  # The anchor stamped merged_target at publication. If PR#$num's LIVE base no
  # longer matches it, the PR was retargeted after publication, so a merge would
  # land (or has landed) on the WRONG branch: closing as "Merged to <expected>"
  # would record a landing that never happened. Do not close while mismatched
  # (the merge skill independently refuses to merge across the mismatch). Fires
  # for the merged close path and any open/non-draft PR — NOT open/draft (a
  # stray draft is skipped) and NOT closed/unmerged (handled as
  # abandoned below). Flip the gating marker off pull_request so the anchor
  # leaves this scan: that escalates exactly once (mirroring out-of-band-close
  # handling), routes a human, and clears the now-meaningless per-gate check.*
  # markers (so a re-engaged anchor must re-earn every gate against the new base,
  # never merging on a review of the pre-retarget diff). The anchor stays OPEN —
  # the work has not landed on its target.
  if { [ "$merged" = "true" ] || { [ "$state" = "OPEN" ] && [ "$is_draft" != "true" ]; }; } \
       && [ -n "$recorded_target" ] && [ -n "$base" ] && [ "$recorded_target" != "$base" ]; then
    # Build --unset-metadata flags for each gate the anchor declared in check_set.
    # The markers are dynamic keys (check.<name>), so they cannot be a single
    # static flag; an empty check_set yields no flags at all.
    #
    # An ARRAY, read one jq line per element — not a space-joined string expanded
    # unquoted (tk-bdfww, the security review's deferred item). check_set is
    # operator-supplied text that reaches this line verbatim, and an unquoted
    # expansion is subject to PATHNAME EXPANSION as well as word splitting: a gate
    # named `check-*` would expand against the reconciler's cwd, so the flags
    # actually sent would depend on which files happen to sit next to the script —
    # unsetting markers nobody named, or silently unsetting none of them. Reading
    # NUL-free lines into an array makes each element exactly one jq output token,
    # whatever it contains.
    UNSET_CHECKS=()
    while IFS= read -r _uc; do
      [ -n "$_uc" ] || continue
      UNSET_CHECKS+=("$_uc")
    done < <(printf '%s' "$row" | jq -r '
      ((.checkset // "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))
       | map("--unset-metadata", "check." + .) | .[])' 2>/dev/null)
    # `${arr[@]+"${arr[@]}"}` — an EMPTY array expands to nothing here rather than
    # tripping `set -u` (line 101). Bash 4.4+ treats a bare "${arr[@]}" as empty
    # under -u, but 3.2 (the system bash on macOS, where this pack also runs) does
    # not, and a gateless anchor is the common case — it must not abort the pass.
    gc bd update "$id" \
      --assignee="" \
      --set-metadata merge_result=retargeted \
      --set-metadata gc.routed_to=human \
      --set-metadata blocked_reason="PR#$num retargeted: base '$base' != expected target '$recorded_target'" \
      ${UNSET_CHECKS[@]+"${UNSET_CHECKS[@]}"} >/dev/null 2>&1
    retargeted=$((retargeted + 1))
    if gc mail send mayor/ -s "ESCALATION: PR#$num retargeted ($base != $recorded_target) for $id" \
         -m "Gating anchor $id expects PR#$num to land on '$recorded_target' (merged_target,
stamped at publication), but the PR now targets '$base' — it was retargeted after
the refinery published it. The merge reconciler will NOT close this anchor as
landed, and the merge skill will NOT merge it, while base != expected target:
either would record/produce a landing on the wrong branch. The bead is left OPEN,
routed to human (merge_result=retargeted). Decide: retarget PR#$num back to
'$recorded_target' and reset merge_result=pull_request to re-engage, or update the
anchor's merged_target if the new base is intentional." >/dev/null 2>&1; then
      escalated=$((escalated + 1))
    fi
    echo "reconcile-merged-prs: $id flagged — PR#$num retargeted (base '$base' != target '$recorded_target'); routed to human + escalated"
    continue
  fi

  # --- PR merged: close the anchor (close-FIRST for convergence). -----------
  # If the close fails the anchor stays open + merge_result=pull_request and is
  # retried next pass. The merged_sha/merge_result write is best-effort AFTER
  # the close — the close reason already names the merge commit, so a failed
  # metadata write loses no authority, only a forensic field.
  if [ "$merged" = "true" ]; then
    short=$(printf '%.8s' "$merge_oid")
    if gc bd close "$id" --reason "Merged to $target at ${short:-merge}" >/dev/null 2>&1; then
      # Clear the in-flight blockers too: a landed anchor carrying a stale
      # blocked_reason / stale_base_head reads as still-stuck to a human.
      gc bd update "$id" \
        --set-metadata merge_result=merged \
        --set-metadata merged_sha="$merge_oid" \
        --unset-metadata rejection_reason \
        --unset-metadata blocked_reason \
        --unset-metadata stale_base_head >/dev/null 2>&1 || true
      closed=$((closed + 1))
      echo "reconcile-merged-prs: closed $id — PR#$num merged to $target at ${short:-?}"
    else
      echo "reconcile-merged-prs: $id close failed for merged PR#$num; retry next pass" >&2
      skipped=$((skipped + 1))
    fi
    continue
  fi

  # --- PR closed, unmerged: out-of-band close. -----------------------------
  # This anchor is still OPEN with its gating marker, yet its PR is CLOSED —
  # so the refinery did NOT close it (a refinery abandonment closes the anchor
  # in the same step it closes the PR, and that anchor would no longer be in
  # this open scan). Someone closed it OUT OF BAND — a human, or a process
  # outside Gas City. We have no context for why, so we do not guess: flip off
  # the gating marker (so this pass never re-scans it), route to a human, and
  # escalate once. Leave it OPEN — the work did not land, so closing would
  # falsely read as done. (When *we* abandon, we close our own PR + anchor
  # proactively and never reach here — see docs/work-bead-state-machine.md.)
  if [ "$state" = "CLOSED" ]; then
    gc bd update "$id" \
      --assignee="" \
      --set-metadata merge_result=abandoned \
      --set-metadata gc.routed_to=human \
      --set-metadata blocked_reason="PR#$num closed out-of-band without merging" >/dev/null 2>&1
    abandoned=$((abandoned + 1))
    if gc mail send mayor/ -s "ESCALATION: out-of-band close of PR#$num for $id" \
         -m "Gating anchor $id is parked on PR#$num, which was CLOSED without merging
by something OUTSIDE the refinery (the refinery closes its own abandoned PRs and
their anchors together, so this was not us). The bead is left OPEN, routed to
human (merge_result=abandoned). Decide: reopen for rework (file a fix child with
a rejection_reason) or close as wontfix/duplicate/not-planned. The refinery never
auto-closes an unmerged anchor it did not abandon." >/dev/null 2>&1; then
      escalated=$((escalated + 1))
    fi
    echo "reconcile-merged-prs: $id flagged — PR#$num closed out-of-band; routed to human + escalated"
    continue
  fi

  # --- PR open, CONFLICTING: stale base — route a rebase. -------------------
  # The merge skill holds a conflicted PR and retries (correct: never merge a
  # conflict), but a conflict is NOT transient the way BLOCKED/UNSTABLE/UNKNOWN
  # are: retrying forever never clears it. The common cause is a rewritten base —
  # an upstream-rebase landing force-pushes the target, every open PR's base
  # commit is rewritten out, and every gating anchor goes CONFLICTING at once.
  # Before this arm nothing re-routed them: the anchor sits open, unassigned,
  # gc.routed_to="" (detached from both queues by design), so no polecat is ever
  # dispatched and the work is stranded indefinitely — invisibly, because a
  # gating anchor is only watched by this pass.
  #
  # The remedy is mechanical (rebase the branch onto the current base and
  # force-push), so this routes it instead of escalating: file a rework CHILD of
  # the anchor and hand it to the fix pool. A child — never the anchor reopened —
  # is how rework is filed (docs/work-bead-state-machine.md); it also carries
  # pr_number, so while it is open the merge skill's in-flight-rework gate holds
  # the merge, and on hand-back the patrol's one-anchor-per-PR arm recognizes the
  # shared branch and closes it as landed-on-branch instead of minting a second
  # anchor (tk-ynz4b).
  #
  # The anchor KEEPS merge_result=pull_request — deliberately unlike the
  # retargeted/abandoned arms, which flip it off to leave this scan. Those two
  # need a human decision; this one does not, and flipping the marker would
  # remove the anchor from the merge skill's scan too, so the rebased PR would
  # sit ready with nothing left to land it — trading a visible stall for a silent
  # one. Convergence comes instead from stale_base_head=<head at detection>: the
  # arm fires once per head, and re-arms only when the head moves (a later
  # rewrite conflicting the new head is a genuinely new stall).
  #
  # Bound: ONE auto-rework per head. If the rework closes without moving the head
  # the arm stays quiet — the anchor holds with blocked_reason set and its closed
  # child in the ledger, and the polecat that could not rebase escalates through
  # its own channel. Repeatedly re-filing children at an unchanged head would
  # spin the pool instead.
  #
  # `mergeable` (CONFLICTING) and `mergeStateStatus` (DIRTY) are computed
  # asynchronously by GitHub; UNKNOWN/blank means "still computing" and must NOT
  # fire — only the two definite conflict readings do.
  if [ "$state" = "OPEN" ] && [ "$is_draft" != "true" ] \
     && { [ "$mergeable" = "CONFLICTING" ] || [ "$merge_state" = "DIRTY" ]; }; then
    prior=$(printf '%s' "$row" | jq -r '.staled // empty')
    pool=$(printf '%s' "$row" | jq -r '.fixpool // empty')
    [ -n "$pool" ] || pool="$FIX_POOL_DEFAULT"

    # --- Operator gates, checked before anything is dispatched. ---------------
    # This arm is the most dangerous in the file: it does not merge, it DISPATCHES
    # A FORCE-PUSH (`--force-with-lease` onto the PR's head branch) to a live pool,
    # claimable within minutes. So it must honor every marker that would hold the
    # far gentler merge — anything less and the two scripts disagree about whether
    # an anchor is actionable, which is exactly what happened: merge-skill.sh
    # correctly refused to merge a merge_hold anchor, and seconds later, in the
    # SAME reconcile pass, this arm used that same anchor to dispatch a rebase
    # (tk-gajop).
    #
    # merge_hold is the operator's "do not land this yet"; rebase_hold is the
    # narrower "do not rebase/force-push this branch". Either one vetoes: a hold
    # on landing is necessarily a hold on rewriting the branch underneath it.
    if is_held "$hold"; then
      echo "reconcile-merged-prs: $id — PR#$num conflicted (stale base) but merge_hold set (operator gate); no rebase dispatched"
      rebase_held=$((rebase_held + 1)); continue
    fi
    if is_held "$rhold"; then
      echo "reconcile-merged-prs: $id — PR#$num conflicted (stale base) but rebase_hold set (operator gate); no rebase dispatched"
      rebase_held=$((rebase_held + 1)); continue
    fi

    # The head this pass would route. An unreadable head degrades to the literal
    # "unknown" rather than to "" — an empty marker would never match on the next
    # pass and the arm would re-file on every wake.
    head_key="${head_oid:-unknown}"
    # Already routed at this exact head: nothing changed, do not re-file.
    if [ "$prior" = "$head_key" ]; then
      skipped=$((skipped + 1)); continue
    fi

    # The branch a rebase child would rewrite. Resolved HERE, before the probes,
    # because the branch — not the anchor and not the PR — is what a force-push
    # actually endangers, so it is the right key to ask "is anyone already on
    # this?". `head_ref` is the PR's live head branch and is authoritative over
    # the anchor's recorded branch; the emptiness check stays below with the rest
    # of the filing preconditions.
    fix_branch="$head_ref"
    [ -n "$fix_branch" ] || fix_branch=$(printf '%s' "$row" | jq -r '.branch // empty')

    # --- Who else is already on this branch? ----------------------------------
    # Probe BOTH dimensions and union them; neither subsumes the other:
    #   PR number — a rework child of THIS PR, under ANY key that names a PR
    #               (pr_number, fork_pr, fork_pr_url), including one filed by a
    #               different anchor. The stale_base_head marker above cannot catch
    #               that: it is keyed per-ANCHOR, so a PR carrying two anchors (the
    #               tk-ynz4b double-anchor trap) files one child per anchor, each
    #               blind to the other.
    #   branch    — anything naming the same branch under a different PR number,
    #               which is the unit a force-push actually collides on.
    # FAIL CLOSED on an unreadable probe. A failed ledger read is
    # indistinguishable from "no bead holds this branch", and reading it the
    # optimistic way dispatches a force-push precisely when we cannot verify a
    # freeze — the worst possible time. A deferred rebase costs one pass; a
    # force-push onto a branch a keeper had frozen is not recoverable by retry.
    if ! probe=$(probe_beads_pr "$num"); then
      echo "reconcile-merged-prs: $id — PR#$num conflicted but the rework probe failed; no rebase dispatched (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    if [ -n "$fix_branch" ]; then
      if ! branch_probe=$(probe_beads branch "$fix_branch"); then
        echo "reconcile-merged-prs: $id — PR#$num conflicted but the branch probe on '$fix_branch' failed; no rebase dispatched (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      probe=$(printf '%s\n%s' "$probe" "$branch_probe")
    fi

    # An operator freeze ANYWHERE on this branch — on an existing child, or on a
    # sibling bead naming it — vetoes the dispatch. rebase_hold=true is precisely
    # the marker a keeper sets on a runaway rebase child to stop it being redone;
    # re-dispatching past it re-creates the race the keeper just contained.
    frozen=$(printf '%s\n' "$probe" \
      | jq -r 'select((.rhold // "") as $h | ($h | ascii_downcase) as $l
               | $h != "" and $l != "false" and $l != "0" and $l != "null") | .id' 2>/dev/null \
      | head -1)
    if [ -n "$frozen" ]; then
      echo "reconcile-merged-prs: $id — PR#$num conflicted (stale base) but $frozen holds branch '${fix_branch:-?}' with rebase_hold (operator gate); no rebase dispatched"
      rebase_held=$((rebase_held + 1)); continue
    fi

    # Someone is already reworking this PR or this branch (a signoff
    # REQUEST_CHANGES child, an operator-parked one, or our own from an earlier
    # head). A second rework child would race it — two live children on one branch
    # is a concurrent force-push hazard on its own, independent of any freeze.
    # Beads carrying merge_result are anchors, not rework children, and are
    # excluded; the anchor under consideration is excluded by id.
    inflight=$(printf '%s\n' "$probe" \
      | jq -r --arg anchor "$id" 'select(.id != $anchor) | select(.mres == "") | .id' 2>/dev/null \
      | head -1)
    if [ -n "$inflight" ]; then
      skipped=$((skipped + 1)); continue
    fi
    if [ -z "$pool" ]; then
      # No pool to route to: this would file a child nothing ever claims, so
      # surface it as a human-routed stall instead (the pre-fix behaviour was to
      # surface nothing at all). merge_result is still left intact so the merge
      # skill lands it if a human rebases the branch by hand.
      gc bd update "$id" \
        --set-metadata stale_base_head="${head_oid:-unknown}" \
        --set-metadata gc.routed_to=human \
        --set-metadata blocked_reason="PR#$num conflicts with base '$base' (stale base); no fix pool configured to rebase it" >/dev/null 2>&1
      if gc mail send mayor/ -s "ESCALATION: PR#$num conflicted (stale base) with no fix pool for $id" \
           -m "Gating anchor $id is parked on PR#$num, which cannot merge: it conflicts with its
base '$base' (mergeable='${mergeable:-?}', mergeStateStatus='${merge_state:-?}'), typically
because the base branch was rewritten under it. The remedy is a rebase of branch
'${head_ref:-?}' onto '$base' + force-push, but no fix pool is configured (no
--fix-pool from the patrol, no metadata.fix_target_pool on the anchor), so the
reconciler cannot route it. Rebase it by hand — the anchor stays gating, so the
merge skill lands it once the conflict clears — or configure the pool." >/dev/null 2>&1; then
        escalated=$((escalated + 1))
      fi
      echo "reconcile-merged-prs: $id flagged — PR#$num conflicted (stale base) and no fix pool; routed to human + escalated"
      continue
    fi
    # `fix_branch` (resolved above, before the probes) is what the rework must
    # resume — existing_pr makes the patrol rework THAT PR rather than open a
    # second one. With no branch or no URL the child would have nothing to check
    # out: skip rather than file a dud.
    if [ -z "$fix_branch" ] || [ -z "$pr_url" ]; then
      echo "reconcile-merged-prs: $id — PR#$num conflicted but head branch/url unreadable; skip (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    FIX_BEAD=$(gc bd create "Rebase PR#$num onto $base: base rewritten, PR conflicts" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
    if [ -z "$FIX_BEAD" ]; then
      echo "reconcile-merged-prs: $id could not file rebase bead for PR#$num; retry next pass" >&2
      skipped=$((skipped + 1)); continue
    fi
    # The routing fields ARE the dispatch — an unstamped child is an orphan no
    # pool ever claims. If the write fails, say so loudly and still stamp the
    # anchor below: the marker bounds this to ONE orphan rather than a fresh one
    # every wake, and the log line names the bead a human can route by hand.
    gc bd update "$FIX_BEAD" \
      --set-metadata branch="$fix_branch" \
      --set-metadata target="$base" \
      --set-metadata rejection_reason="stale base: PR#$num conflicts with '$base' (base rewritten under it). Rebase '$fix_branch' onto origin/$base, resolve conflicts, and force-push with --force-with-lease. Do NOT open a new PR — this reworks PR#$num." \
      --set-metadata merge_strategy=mr \
      --set-metadata existing_pr="$pr_url" \
      --set-metadata pr_url="$pr_url" \
      --set-metadata pr_number="$num" \
      --set-metadata source_anchor_bead="$id" \
      --set-metadata gc.routed_to="$pool" >/dev/null 2>&1 \
      || echo "reconcile-merged-prs: WARN rebase $FIX_BEAD for PR#$num created but not stamped; route it to $pool by hand" >&2
    # Parent-child keeps the dep graph honest and makes the rework visible under
    # the anchor. Best-effort: a failed edge must not strand the rebase, which is
    # already routed and independently linked by source_anchor_bead + pr_number.
    gc bd dep add "$FIX_BEAD" "$id" -t parent-child >/dev/null 2>&1 \
      || echo "reconcile-merged-prs: WARN could not link rebase $FIX_BEAD under anchor $id" >&2
    gc bd update "$id" \
      --set-metadata stale_base_head="${head_oid:-unknown}" \
      --set-metadata blocked_reason="PR#$num conflicts with base '$base' (stale base) at head ${head_oid:-unknown}; rebase $FIX_BEAD routed to $pool" >/dev/null 2>&1
    gc session wake "$pool" >/dev/null 2>&1 || true
    rebased=$((rebased + 1))
    echo "reconcile-merged-prs: $id — PR#$num conflicts with '$base' (stale base); filed rebase $FIX_BEAD routed to $pool"
    continue
  fi

  # --- PR open, STALE GATE: check-set green at a head that MOVED. -----------
  # The symmetric twin of the CONFLICTING arm above. A gating anchor whose codex
  # marker went green (check.codex=green@<oid>) and whose PR head then advanced
  # PAST <oid> through a path that filed NO rework bead — a direct push to the PR
  # branch, an operator fixup — sits in a SILENT indefinite hold: merge-skill.sh
  # correctly refuses (its stale-head guard: green@<oid> != live head), but before
  # this arm NOTHING re-dispatched the review, so the anchor was indistinguishable
  # from a healthy PR awaiting approval (WS4 GAP1, su-PR#31 class). check-set-heal.sh
  # heals the DISJOINT empty-check_set case and EXPLICITLY punts on stale-green
  # ("re-gates through the normal rework path") — the exact assumption this bug
  # disproves for the no-rework-bead path, so the two passes are complementary.
  #
  # The remedy is ALWAYS a real review at the live head, NEVER a hand-stamped
  # check.codex=green: stamping green here would certify an UNREVIEWED commit (the
  # tk-4na1b failure mode with a human author). So this files a codex RE-REVIEW
  # CHILD at the live head, routed to the review pool, anchored to the gating anchor
  # (one anchor per PR); the child's COMMENT signoff re-stamps
  # check.codex=green@<live-head> and the merge proceeds. The anchor KEEPS
  # merge_result=pull_request — like the CONFLICTING arm, unlike retarget/abandon —
  # because the PR still exists and still gates; the open review child holds the
  # merge meanwhile, and on hand-back the merge-push one-anchor-per-PR arm closes it
  # as landed-on-branch rather than minting a second anchor.
  #
  # Bound: ONE re-review per head, via stale_gate_head=<head at detection> (the
  # exact shape of stale_base_head). Re-arms only when the head moves again. Between
  # dispatch and signoff the open review child ALSO holds it (the in-flight probe),
  # so the marker is the belt to that suspenders — it still bounds the arm if a
  # review closes without re-stamping (e.g. REQUEST_CHANGES routes a rework instead).
  # A poolless hold uses a DISTINCT marker (stale_gate_nopool_head): stale_gate_head
  # would say "dispatched here" and suppress the dispatch forever once a review pool
  # is configured, so a no-pool pass must not stamp it (tk-v2b0k finding #1). The
  # no-pool marker only short-circuits the busy-loop while STILL poolless.
  #
  # Only `codex` is dispatchable (the sole check-set member this city can raise —
  # mirrors check-set-heal.sh); a non-codex stale gate is left to whatever raises it.
  # Kept self-contained so it ports if this self-heal is later re-housed inside a
  # convergence loop (the tk-zgse0 WS4 direction).
  if [ "$state" = "OPEN" ] && [ "$is_draft" != "true" ]; then
    checkset=$(printf '%s' "$row" | jq -r '.checkset // empty')
    codexmark=$(printf '%s' "$row" | jq -r '.codexmark // empty')
    stalegate=$(printf '%s' "$row" | jq -r '.stalegate // empty')
    # Separate from stalegate (stale_gate_head): this marks a head we HELD purely
    # for lack of a review pool — no review was dispatched. Kept distinct so a pool
    # configured later can still dispatch at that head instead of being suppressed
    # by the "already dispatched here" guard below (tk-v2b0k finding #1).
    stalegate_nopool=$(printf '%s' "$row" | jq -r '.stalegatenopool // empty')
    # fix_target_pool is where a REQUEST_CHANGES rework off this re-review routes.
    # Prefer the anchor's own override; fall back to the patrol's --fix-pool default.
    # Normal gating anchors carry NO fix_target_pool of their own (only the review
    # bead is stamped with one, by the regular codex dispatch) — so without this
    # fallback the re-review child is filed with an EMPTY fix pool, and its signoff
    # completion path (template-fragments/polecat-non-impl-done.template.md, which
    # gates every action on a non-empty fix_target_pool) can neither stamp
    # check.codex on COMMENT nor file a rework child on REQUEST_CHANGES. The review
    # then closes while the anchor keeps the stale check.codex=green@<old> +
    # stale_gate_head, re-creating the exact indefinite hold this arm exists to heal.
    # Symmetric with the CONFLICTING arm's fallback (`[ -n "$pool" ] || pool="$FIX_POOL_DEFAULT"`).
    fixpool=$(printf '%s' "$row" | jq -r '.fixpool // empty')
    [ -n "$fixpool" ] || fixpool="$FIX_POOL_DEFAULT"

    # `codex` must be a declared check-set member (whitespace-insensitive,
    # whole-token — so a spaced "lint, codex" is recognized exactly as
    # merge-skill.sh / check-set-heal.sh recognize it). none/off is not a member,
    # so a gateless rig never enters this arm.
    #
    # Matched in-shell rather than through a `... | grep -qxF codex` pipeline, for
    # the same reason merge-skill.sh's trusted-approver and `approval` tests are:
    # `set -o pipefail` is on (line 101) and `grep -q` exits at the FIRST match,
    # closing the pipe under `tr`/`sed`, which can then take SIGPIPE and make the
    # whole pipeline report 141 — so `&& is_codex_member=1` never runs. A check_set
    # that DOES name `codex` reads as one that does not, decided by nothing but how
    # many gates happen to be listed AFTER it. Both arms below key off this flag, so
    # a rig would silently lose stale-gate re-review AND the superseded-review
    # self-heal as its check_set grows, leaving those PRs blocked indefinitely.
    #
    # Whitespace is stripped outright (a gate name cannot contain any) and the comma
    # wrapping makes it a whole-token match, so `codex` matches while `pre-codex`
    # does not. Deliberately NOT case-folded: merge-skill.sh's gate enumeration
    # keeps each gate's original case in its marker key (`"check." + .`), so a
    # `CODEX` gate is satisfied only by `check.CODEX`. Folding here would dispatch a
    # re-review whose lowercase `check.codex` stamp could never satisfy that gate —
    # a false positive that re-reviews forever. Case-sensitive matches both the
    # previous behaviour and what the merge actually enforces.
    is_codex_member=""
    case ",$(printf '%s' "$checkset" | tr -d '[:space:]')," in
      *",codex,"*) is_codex_member=1 ;;
    esac

    # Stale-green? The marker must be green at a NON-EMPTY oid that is NOT the live
    # head. An empty/absent marker is "never reviewed" (check-set-heal's / the normal
    # dispatch's job, not this bug); green@<live-head> is current (merges normally).
    # Only green@<other-oid> is the head-moved stall this arm heals.
    stale_oid=""
    case "$codexmark" in
      green@*)
        oid="${codexmark#green@}"
        if [ -n "$oid" ] && [ -n "$head_oid" ] && [ "$oid" != "$head_oid" ]; then
          stale_oid="$oid"
        fi ;;
    esac

    if [ -n "$is_codex_member" ] && [ -n "$stale_oid" ]; then
      # Operator hold: merge_hold is "do not land this yet". Re-dispatching a review
      # is pipeline work toward landing, so honor the same gate the merge honors
      # (symmetric with the CONFLICTING arm honoring it before a rebase). When the
      # operator releases the hold, the next pass heals the gate.
      if is_held "$hold"; then
        echo "reconcile-merged-prs: $id — PR#$num check.codex stale (green@$stale_oid != live head ${head_oid:-?}) but merge_hold set (operator gate); no re-review dispatched"
        gate_held=$((gate_held + 1)); continue
      fi
      # One re-review per head: already routed at this exact head -> nothing new.
      gate_key="${head_oid:-unknown}"
      if [ "$stalegate" = "$gate_key" ]; then
        skipped=$((skipped + 1)); continue
      fi
      # Held at this head ONLY for lack of a review pool, and STILL none configured:
      # the hold stands, so short-circuit before the in-flight probe (mirrors the
      # guard above). This reads stale_gate_nopool_head, NOT stale_gate_head — a pool
      # configured since (REVIEW_POOL_DEFAULT now non-empty) fails the `-z` test here,
      # so it falls through and dispatches, recovering the hold at the same head
      # (tk-v2b0k finding #1: a no-pool pass must not suppress a later configured
      # dispatch). The two markers are kept separate for exactly this transition.
      if [ -z "$REVIEW_POOL_DEFAULT" ] && [ -n "$stalegate_nopool" ] \
           && [ "$stalegate_nopool" = "$gate_key" ]; then
        gate_held=$((gate_held + 1)); continue
      fi
      # An open rework/review child already re-raises the gate — the SAME in-flight
      # set merge-skill.sh holds the merge on (pr_number, non-anchor). FAIL CLOSED
      # on an unreadable probe: a twin review is a lesser harm than the CONFLICTING
      # arm's force-push, but the guard errs to "someone's on it" the same way.
      if ! gate_probe=$(probe_beads_pr "$num"); then
        echo "reconcile-merged-prs: $id — PR#$num check.codex stale but the in-flight probe failed; no re-review dispatched (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      inflight=$(printf '%s\n' "$gate_probe" \
        | jq -r --arg anchor "$id" 'select(.id != $anchor) | select(.mres == "") | .id' 2>/dev/null \
        | head -1)
      if [ -n "$inflight" ]; then
        # Normally a healthy in-flight review/rework already re-raises the gate, so
        # skip to avoid a twin (test 26). BUT a re-review left UNROUTED by a failed
        # route write (arm_stale_gate below) is inert — unclaimable by the codex pool
        # — while it still trips this probe, so the gate would sit held forever behind
        # a bead nothing can action. If the in-flight bead is exactly that (a codex
        # review anchored to THIS anchor whose route this pass's arm would refuse)
        # and a review pool is configured, re-route it (repair) rather than skip:
        # heal the head an earlier pass failed to arm. Anything else — properly
        # routed, a rework child, or anchored elsewhere — is left untouched, so
        # twin-avoidance is unchanged for it.
        #
        # A MISSING DURABLE COPY is the same kind of half-written route and is
        # repaired here too (tk-bdfww). arm_stale_gate now refuses to arm on one,
        # so without this the two disagree: the head guard stays unstamped, every
        # later pass re-enters, finds this same bead ROUTED, skips at the twin
        # guard, and review_pool is never restored — the arm spins without ever
        # converging, and the review is one claim away from being unroutable
        # (a claim CONSUMES gc.routed_to, leaving nothing to re-offer it from).
        # The repair predicate must therefore cover exactly what the arming
        # predicate rejects.
        if_json=$(gc bd show "$inflight" --json 2>/dev/null)
        if_kind=$(printf '%s' "$if_json" | jq -r '.[0].metadata.task_kind // ""' 2>/dev/null)
        if_anchor=$(printf '%s' "$if_json" | jq -r '.[0].metadata.anchor_bead // ""' 2>/dev/null)
        if_routed=$(printf '%s' "$if_json" | jq -r '.[0].metadata["gc.routed_to"] // ""' 2>/dev/null)
        if_pool=$(printf '%s' "$if_json" | jq -r '.[0].metadata.review_pool // ""' 2>/dev/null)
        # The ASSIGNEE is read for the same reason arm_stale_gate reads it: a claim
        # CONSUMES gc.routed_to, so "no live route" means unclaimable only while the
        # bead is also unclaimed. Without it the two predicates cannot agree.
        if_assignee=$(printf '%s' "$if_json" | jq -r '.[0].assignee // ""' 2>/dev/null)
        # Repair exactly what arm_stale_gate REFUSES to arm on — the negation of its
        # accept condition (pool matches AND (claimed OR live route matches)), so the
        # two can never disagree (tk-5niup). The old form tested `-z "$if_routed"`,
        # i.e. only an EMPTY live route, which left the SPLIT route uncovered:
        # review_pool=<review pool> with gc.routed_to=<some other pool> and nobody
        # claiming. The arm rejects that (the review is offered to a pool that will
        # never stamp check.codex), the repair skipped it at the twin guard, and the
        # pass spun forever — head never armed, route never healed, merge held behind
        # a bead the codex pool is never offered. Stating it as the negation also
        # stops the inverse over-fire: a CLAIMED review with a spent gc.routed_to is
        # reachable, and re-routing it would hand a claimed review to a second pool.
        if [ -n "$REVIEW_POOL_DEFAULT" ] && [ "$if_kind" = "review" ] \
             && [ "$if_anchor" = "$id" ] \
             && { [ "$if_pool" != "$REVIEW_POOL_DEFAULT" ] \
                  || { [ -z "$if_assignee" ] && [ "$if_routed" != "$REVIEW_POOL_DEFAULT" ]; }; }; then
          if arm_stale_gate "$inflight" "$id" "$head_oid" "$stale_oid" "$REVIEW_POOL_DEFAULT" "$num"; then
            regated=$((regated + 1))
            echo "reconcile-merged-prs: $id — PR#$num re-review $inflight was left unrouted, misrouted, or without its durable review_pool copy by an earlier failed route write; re-routed to $REVIEW_POOL_DEFAULT (stale-gate repair)"
          else
            echo "reconcile-merged-prs: $id — PR#$num re-review $inflight repair route still not persisting; retry next pass" >&2
            skipped=$((skipped + 1))
          fi
          continue
        fi
        skipped=$((skipped + 1)); continue
      fi
      if [ -z "$REVIEW_POOL_DEFAULT" ]; then
        # No review pool: cannot dispatch. Do NOT hand-stamp the gate green (that
        # certifies an unreviewed commit). Record a SEPARATE no-pool hold marker —
        # NOT stale_gate_head. stale_gate_head means "a review WAS dispatched at this
        # head" and the guard above skips it forever; stamping it here would suppress
        # the dispatch even after a pool is configured, re-creating the exact
        # indefinite hold this arm heals (tk-v2b0k finding #1). stale_gate_nopool_head
        # bounds the busy-loop via the short-circuit above WITHOUT blocking the later
        # configured dispatch. Surface it and leave the anchor gating — the merge
        # stays HELD on the stale marker, the safe side.
        gc bd update "$id" \
          --set-metadata stale_gate_nopool_head="${head_oid:-unknown}" \
          --set-metadata blocked_reason="PR#$num check.codex green@$stale_oid is stale (live head ${head_oid:-?}); no review pool configured to re-dispatch the signoff" >/dev/null 2>&1
        echo "reconcile-merged-prs: $id — PR#$num check.codex stale (green@$stale_oid, live head ${head_oid:-?}) but no --review-pool; cannot re-dispatch (merge stays held)" >&2
        gate_held=$((gate_held + 1)); continue
      fi
      # Need a PR url to point the review at (num is non-empty by the loop head).
      if [ -z "$pr_url" ]; then
        echo "reconcile-merged-prs: $id — PR#$num check.codex stale but PR url unreadable; skip (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      # The stale-gate context is BOTH the bead body's dispatch note and the
      # review_note metadata below — one string, so the reviewer reads the same
      # reason wherever they look. The body additionally carries the review METHOD
      # (create_review_bead): title says WHAT, metadata says WHERE, body says HOW.
      STALE_NOTE="Stale-gate self-heal: check.codex was green@$stale_oid; the PR head moved to ${head_oid:-?} with no rework bead filed. Re-review the live head."
      REVIEW_BEAD=$(create_review_bead "Review PR#$num: re-review at live head (stale-gate self-heal)" "$STALE_NOTE")
      if [ -z "$REVIEW_BEAD" ]; then
        echo "reconcile-merged-prs: $id could not file re-review bead for PR#$num; retry next pass" >&2
        skipped=$((skipped + 1)); continue
      fi
      # Mirror the merge-push / check-set-heal.sh review shape so the codex signoff's
      # done-sequence finds exactly the fields it expects (task_kind=review,
      # check_name, pr_url/pr_number for the post-open review, anchor_bead the durable
      # link). fix_target_pool (resolved above: the anchor's own override, else the
      # patrol's --fix-pool default) is where a REQUEST_CHANGES rework routes — the
      # FIX pool, not the review pool. gc.routed_to is written LAST — it is what makes
      # the bead claimable, and a codex polecat that claimed a half-stamped review
      # would have no anchor_bead to stamp the gate on.
      gc bd update "$REVIEW_BEAD" \
        --set-metadata task_kind=review \
        --set-metadata check_name=codex \
        --set-metadata pr_url="$pr_url" \
        --set-metadata pr_number="$num" \
        --set-metadata anchor_bead="$id" \
        --set-metadata review_note="$STALE_NOTE" >/dev/null 2>&1
      [ -n "$fixpool" ] && gc bd update "$REVIEW_BEAD" --set-metadata fix_target_pool="$fixpool" >/dev/null 2>&1
      # The review BLOCKS the anchor (anchor_bead is the durable fallback the signoff
      # resolves through when the edge is missing). Best-effort.
      gc bd dep "$REVIEW_BEAD" --blocks "$id" >/dev/null 2>&1 \
        || echo "reconcile-merged-prs: WARN could not attach re-review $REVIEW_BEAD as a gate-dep of $id (anchor_bead fallback persists the link)" >&2
      # Verify the anchor link persisted BEFORE routing: without it the review cannot
      # stamp check.codex on this anchor and the armed gate never clears. Unrouted, the
      # bead is inert and the next pass's in-flight probe reuses it rather than a twin.
      RECORDED_ANCHOR=$(gc bd show "$REVIEW_BEAD" --json 2>/dev/null | jq -r '.[0].metadata.anchor_bead // empty')
      if [ "$RECORDED_ANCHOR" != "$id" ]; then
        echo "reconcile-merged-prs: WARN re-review $REVIEW_BEAD did not record anchor_bead=$id; leaving unrouted (retry next pass)" >&2
        skipped=$((skipped + 1)); continue
      fi
      # Route the review and arm the one-per-head guard ONLY if the route PERSISTS.
      # A dropped route write must NOT stamp stale_gate_head: that would mark the head
      # "dispatched" while the review sits unrouted and unclaimable, and the
      # one-per-head guard would then skip it forever — the tk-3xy37 finding. On a
      # miss, leave the guard unstamped and skip; the next pass re-enters (guard
      # unstamped) and the in-flight probe above re-routes this same bead.
      if arm_stale_gate "$REVIEW_BEAD" "$id" "$head_oid" "$stale_oid" "$REVIEW_POOL_DEFAULT" "$num"; then
        regated=$((regated + 1))
        echo "reconcile-merged-prs: $id — PR#$num check.codex green@$stale_oid stale (live head ${head_oid:-?}); filed re-review $REVIEW_BEAD routed to $REVIEW_POOL_DEFAULT"
      else
        echo "reconcile-merged-prs: WARN re-review $REVIEW_BEAD route write did not persist the full route (gc.routed_to + review_pool = $REVIEW_POOL_DEFAULT); leaving un-armed (retry/repair next pass)" >&2
        skipped=$((skipped + 1))
      fi
      continue
    fi

    # --- Superseded-review self-heal: the gate is CURRENT but GitHub is still
    # RED (tk-5niup). The exact inverse of the stale-gate arm above: there the
    # bead marker lagged the head; here the marker is green AT the live head and
    # it is the GITHUB side that lags — our own CHANGES_REQUESTED from an earlier
    # round is still standing, pinned to a commit that no longer exists. A
    # COMMENT review does not supersede the same reviewer's earlier
    # CHANGES_REQUESTED, so reviewDecision stays CHANGES_REQUESTED and
    # mergeStateStatus stays BLOCKED forever; merge-skill.sh requires CLEAN, so
    # the PR can never land no matter how many green re-gates run.
    #
    # The re-gate itself now retracts its own superseded review in the step that
    # stamps green (template-fragments/polecat-non-impl-done.template.md), which
    # stops NEW strands. This arm is the convergence half: an anchor already
    # stranded before that shipped has a green marker at the live head, so the
    # stale-gate arm never fires and nothing re-dispatches a review — it would
    # sit BLOCKED forever with no in-band path out.
    #
    # KEEP IN SYNC with that step. The two implement the same guard sequence
    # against the same irreversible act (retracting our own block), from opposite
    # ends — one at re-gate time, one as the backstop — so a guard added or
    # tightened in either belongs in both. They are deliberately not extracted
    # into a shared script: one is a bash script, the other is instruction text a
    # polecat executes, and the pair is covered by two separate regression suites
    # (reconcile-merged-prs.test.sh here, signoff-supersede-dismiss.test.sh there).
    #
    # Same guards as the re-gate, for the same reasons: our own reviews only (an
    # operator's CHANGES_REQUESTED is a veto, never ours to clear), superseded
    # commits only, gate green at the LIVE head, native auto-merge provably OFF
    # (an unreadable probe counts as armed), and the pairing marker recorded AND
    # READ BACK before the dismissal (a dismissal without a durable marker would
    # drop both the block and the approval requirement). The head, the auto-merge
    # state AND the anchor itself are re-read immediately before each irreversible
    # call, since all three can change inside the pass — the anchor row this arm
    # decided from is a snapshot taken before the PR was even read, so a mid-pass
    # merge_hold, a cleared check.codex, or an un-parked anchor would otherwise go
    # unseen. Converges by construction:
    # once dismissed, reviewDecision is no longer CHANGES_REQUESTED and the arm
    # does not re-enter.
    if [ -n "$is_codex_member" ] && [ -z "$stale_oid" ] \
       && [ "$codexmark" = "green@$head_oid" ] && [ -n "$head_oid" ] \
       && [ "$review_decision" = "CHANGES_REQUESTED" ] && [ -n "$SELF_LOGIN" ]; then
      if is_held "$hold"; then
        echo "reconcile-merged-prs: $id — PR#$num blocked by a superseded self-review but merge_hold set (operator gate); no retraction"
        retract_held=$((retract_held + 1)); continue
      fi
      # Native auto-merge turns this dismissal from merge-ENABLING into merge-
      # TRIGGERING. If an operator (or a legacy pass) armed `gh pr merge --auto`,
      # GitHub merges the moment the last block clears — server-side, before
      # merge-skill.sh ever runs, so the signoff_dismissed approval requirement
      # recorded below cannot hold it: that requirement is enforced only by our
      # own skill. Fail CLOSED — leave the block standing and say why. Disarming
      # auto-merge for the operator would silently undo a deliberate choice, and
      # merging unreviewed work is exactly what this whole arm exists to prevent.
      # A probe we cannot READ counts as armed (automerge_state answers "unknown"):
      # an API/auth/parse failure looks exactly like "disarmed" through a
      # `// empty` filter, and guessing wrong here is a server-side merge.
      automerge=$(automerge_state "$num")
      if [ "$automerge" = "armed" ]; then
        echo "reconcile-merged-prs: WARN $id — PR#$num blocked by a superseded self-review, but native auto-merge is ARMED; NOT retracting (the dismissal would trigger an immediate server-side merge past the approval requirement). Disarm auto-merge (gh pr merge --disable-auto --repo $ORIGIN_REPO_Q $num) or land it deliberately." >&2
        retract_held=$((retract_held + 1)); continue
      fi
      if [ "$automerge" != "disarmed" ]; then
        echo "reconcile-merged-prs: WARN $id — PR#$num blocked by a superseded self-review, but its native auto-merge state is UNREADABLE (the autoMergeRequest probe failed or returned a malformed payload); NOT retracting. An unreadable probe cannot prove auto-merge is off, and a wrong guess merges server-side past the approval requirement — so it counts as armed. Retry once 'gh pr view $num --repo $ORIGIN_REPO_Q --json autoMergeRequest' answers." >&2
        retract_held=$((retract_held + 1)); continue
      fi
      # Paginated, explicitly: GitHub pages this endpoint (30/page by default),
      # and a PR that has taken review rounds runs past one page — exactly the PRs
      # this arm exists for. An unpaginated read silently misses the superseded
      # review and the PR stays stranded, recreating the liveness bug being fixed.
      #
      # FETCH and REDUCE are SEPARATE steps, each with its own status check — the
      # same split merge-skill.sh makes for reviews_raw/reviews_rc, and the same
      # one the re-gate template makes on its half of this retraction. Fused into
      # one assignment tested only for emptiness, a read that fails PART WAY
      # THROUGH is indistinguishable from a complete one: `gh --paginate` streams
      # the pages it did get, jq reduces them without complaint, and the result is
      # a well-formed answer computed from a TRUNCATED history that this arm then
      # dismisses from as though it had seen all of it. The same silence covers a
      # read that fails OUTRIGHT — an expired token, a rate limit — which renders
      # as "nothing to retract" and strands the PR permanently and invisibly.
      # ANY failure skips the retraction and says so; the arm is convergent, so the
      # next pass re-enters it once the history reads.
      # PINNED to the origin repository, like the PR read above and unlike the
      # `{owner}/{repo}` placeholder this used to carry (review tk-78ty5 finding
      # #3). Those placeholders resolve from gh's AMBIENT repo context — the
      # current directory's remote, or $GH_REPO — which is NOT guaranteed to be
      # the repository this pass derived $num from. Under a drifted context the
      # arm reads a SAME-NUMBERED PR in another repository, and then the write
      # half below dismisses a review there while stamping signoff_dismissed on
      # OUR anchor: a block removed in one repository, the requirement that
      # replaces it recorded in another. Every GitHub call in this arm is pinned
      # for that reason; the identity of the PR must not depend on cwd.
      reviews_raw=$(gh_api_origin --paginate "repos/$ORIGIN_REPO/pulls/$num/reviews?per_page=100" \
        --jq '.[]' 2>/dev/null); reviews_rc=$?
      if [ "$reviews_rc" -ne 0 ]; then
        echo "reconcile-merged-prs: WARN $id — PR#$num reviews history read FAILED (gh rc=$reviews_rc); NOT retracting any superseded self-review (a partial page set cannot be told apart from a complete one and the dismissal is irreversible); retry next pass" >&2
        retract_held=$((retract_held + 1)); continue
      fi
      SUPERSEDED=$(printf '%s' "$reviews_raw" \
        | jq -r --arg h "$SELF_LOGIN" --arg oid "$head_oid" \
            'select((.user.login // "") == $h)
             | select(.state == "CHANGES_REQUESTED")
             | select((.commit_id // "") != $oid) | .id' 2>/dev/null); reduce_rc=$?
      if [ "$reduce_rc" -ne 0 ]; then
        echo "reconcile-merged-prs: WARN $id — PR#$num reviews history is UNREADABLE (reduce rc=$reduce_rc); NOT retracting any superseded self-review; retry next pass" >&2
        retract_held=$((retract_held + 1)); continue
      fi
      if [ -n "$SUPERSEDED" ]; then
        while IFS= read -r rid; do
          [ -n "$rid" ] || continue
          # Re-read the live head immediately before the irreversible call. The
          # listing above is a snapshot: if the head moved since, a review in it
          # may be a FRESH block on the NEW head, not a superseded one — the
          # commit_id filter cannot tell them apart once head_oid is stale. Bail
          # out of the whole retraction; next pass re-reads a settled state.
          live_head=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json headRefOid -q .headRefOid 2>/dev/null)
          if [ "$live_head" != "$head_oid" ]; then
            echo "reconcile-merged-prs: WARN $id — PR#$num head moved ($head_oid -> ${live_head:-unknown}) mid-pass; NOT retracting review $rid (it may block the new head)" >&2
            retract_held=$((retract_held + 1)); break
          fi
          # Re-probe auto-merge here too, after the head re-read and immediately
          # before the irreversible call. The up-front probe is a snapshot: an
          # operator can arm `gh pr merge --auto` in the window between it and this
          # dismissal, and then the dismissal merges the PR server-side. Same
          # fail-closed reading — anything but a definite "disarmed" holds. Break
          # rather than continue: the state is PR-wide, so if it is unsafe for this
          # review it is unsafe for every later one on the same PR.
          am_now=$(automerge_state "$num")
          if [ "$am_now" != "disarmed" ]; then
            echo "reconcile-merged-prs: WARN $id — PR#$num native auto-merge state is '$am_now' immediately before dismissing review $rid; NOT retracting (an armed — or unreadable, hence assumed armed — auto-merge merges server-side past the approval requirement)" >&2
            retract_held=$((retract_held + 1)); break
          fi
          # Re-read the ANCHOR too, in the same place and for the same reason. The
          # two facts re-checked above are GitHub's; every bead-side fact this arm
          # is acting on still comes from the ROWS snapshot taken at the top of the
          # pass — before the PR reads, before the reviews listing. Inside that
          # window an operator can park the anchor (merge_hold), a re-gate can
          # clear check.codex, a resolver can un-park or retarget the anchor off
          # this PR. Each of those makes the retraction wrong in a way the GitHub
          # re-checks cannot see, and the retraction is irreversible: it removes
          # the last block on a PR nothing else is holding.
          #
          # Require the anchor to still BE what the arm decided about: open, not
          # held, parked on THIS PR, gate still green at the live head, and still
          # describing THIS pull request. Unreadable is unsafe — same reading as
          # the auto-merge probe, since a read we never got proves none of it.
          # Break rather than continue: every condition here is anchor- or PR-wide,
          # so what stops this review stops the rest.
          #
          # The PR number is resolved with `pr_nums_here` — the SAME widened,
          # in-repo identity the ROWS projection above used to pick `$num` in the
          # first place, and the same rule merge-skill.sh's terminal re-read
          # applies (review tk-5knqi finding #2). Read from `pr_number` ALONE, as
          # this did, the guard contradicts the arm that reached it: an anchor
          # keyed only by `fork_pr`/`fork_pr_url` — the fork-sync shape, which
          # stamps no pr_number at all — resolves a perfectly good `$num` up top,
          # takes every guard, and then fails HERE with pr_number='' read as
          # "the anchor moved off this PR". The retraction never runs, and it is
          # the one arm that can un-strand such a PR: its gate is green at the
          # live head, so the stale-gate arm never fires and nothing re-dispatches
          # a review. Exactly the fork-keyed path the rest of this pass widened,
          # reintroduced in its last guard.
          #
          # EXACTLY ONE in-repo number or nothing, as everywhere else: several
          # numbers do not answer "which PR does this anchor gate", and an
          # ambiguous anchor must hold rather than have one picked for it.
          #
          # The identity fields (`merged_target`, `pr_url`, `branch`) are re-asked
          # too, against the LIVE PR facts this pass read — not against the ROWS
          # snapshot they were first compared to. They authorize the dismissal as
          # directly as the gate marker does, and NONE of them moves the head, so
          # the head re-read above cannot catch a mid-pass retarget or an identity
          # repair (check-set-heal backfilling a certified pr_url, an operator
          # correcting a mis-stamped branch). Same set, same reasoning, as the
          # merge skill's terminal re-read.
          fresh=$(gc bd show "$id" --json 2>/dev/null \
            | tr -d '\000-\010\013\014\016-\037' \
            | jq -c --arg o "$ORIGIN_REPO_Q" "$PR_SELF_JQ"'
                     .[0] | select(. != null) | select(.metadata != null)
                     | (pr_nums_here($o)) as $ns
                     | {status: (.status // ""),
                        hold: ((.metadata.merge_hold // "") | tostring),
                        result: (.metadata.merge_result // ""),
                        pr: (if ($ns | length) == 1 then $ns[0] else "" end),
                        target: (.metadata.merged_target // ""),
                        prurl: (.metadata.pr_url // ""),
                        branch: (.metadata.branch // ""),
                        mark: (.metadata["check.codex"] // "")}' 2>/dev/null)
          if [ -z "$fresh" ]; then
            echo "reconcile-merged-prs: WARN $id — anchor metadata UNREADABLE immediately before dismissing review $rid on PR#$num; NOT retracting (an unreadable anchor cannot prove the PR is still gated by it, unheld, and green at the live head)" >&2
            retract_held=$((retract_held + 1)); break
          fi
          f_status=$(printf '%s' "$fresh" | jq -r '.status' 2>/dev/null \
            | tr '[:upper:]' '[:lower:]')
          f_hold=$(printf '%s' "$fresh" | jq -r '.hold' 2>/dev/null)
          f_result=$(printf '%s' "$fresh" | jq -r '.result' 2>/dev/null)
          f_pr=$(printf '%s' "$fresh" | jq -r '.pr' 2>/dev/null)
          f_mark=$(printf '%s' "$fresh" | jq -r '.mark' 2>/dev/null)
          f_target=$(printf '%s' "$fresh" | jq -r '.target' 2>/dev/null)
          f_prurl=$(printf '%s' "$fresh" | jq -r '.prurl' 2>/dev/null)
          f_branch=$(printf '%s' "$fresh" | jq -r '.branch' 2>/dev/null)
          if [ "$f_status" != "open" ] || is_held "$f_hold" \
             || [ "$f_result" != "pull_request" ] || [ "$f_pr" != "$num" ] \
             || [ "$f_mark" != "green@$head_oid" ]; then
            echo "reconcile-merged-prs: WARN $id — anchor changed mid-pass (status='$f_status' merge_hold='$f_hold' merge_result='$f_result' pr_number='$f_pr' check.codex='$f_mark'; want open + unheld + pull_request + PR#$num + green@$head_oid); NOT retracting review $rid (the block would come off a PR this anchor no longer gates as validated)" >&2
            retract_held=$((retract_held + 1)); break
          fi
          # Identity, compared to the LIVE PR. An anchor recording NOTHING for a
          # field is governed by the pinned read alone, exactly as the identity arm
          # earlier in this loop treats an absent value: silence is not a
          # disagreement. A recorded value that DISAGREES is, and it means the bead
          # and the PR describe different work — so the block stays on.
          f_reason=""
          if [ -n "$f_target" ] && [ -n "$base" ] && [ "$f_target" != "$base" ]; then
            f_reason="anchor was retargeted mid-pass (merged_target='$f_target', PR base '$base')"
          elif [ -n "$f_prurl" ] && [ -n "$pr_url" ] \
               && [ "$(pr_url_canon "$f_prurl")" != "$(pr_url_canon "$pr_url")" ]; then
            f_reason="anchor now records pr_url '$f_prurl', which is not the PR#$num this pass read ('$pr_url')"
          elif [ -n "$f_branch" ] && [ -n "$head_ref" ] && [ "$f_branch" != "$head_ref" ]; then
            f_reason="anchor now records branch '$f_branch' but PR#$num is opened from '$head_ref'"
          fi
          if [ -n "$f_reason" ]; then
            echo "reconcile-merged-prs: WARN $id — $f_reason; NOT retracting review $rid (the bead and the PR no longer describe the same work)" >&2
            retract_held=$((retract_held + 1)); break
          fi
          # Record the pairing marker, then READ IT BACK before trading the GitHub
          # block away for it. `gc bd update` reporting success is not proof the
          # write is durable — the same reason arm_stale_gate verifies its route
          # rather than trusting an exit status (tk-3xy37) — and this marker is the
          # ONLY thing standing in for the block about to be removed: merge-skill.sh
          # demands a real external approving review because signoff_dismissed is
          # PRESENT. Dismiss on an unverified write and both the block and the
          # requirement are gone at once, the one combination that can land
          # unreviewed work. A miss just holds; the next pass re-enters this arm.
          gc bd update "$id" --set-metadata signoff_dismissed="$rid@$head_oid" >/dev/null 2>&1
          paired=$(gc bd show "$id" --json 2>/dev/null \
            | jq -r '.[0].metadata.signoff_dismissed // empty' 2>/dev/null)
          if [ "$paired" = "$rid@$head_oid" ]; then
            if gh_api_origin -X PUT "repos/$ORIGIN_REPO/pulls/$num/reviews/$rid/dismissals" \
                 -f message="Superseded: this review is pinned to a commit that is no longer the head, and the codex gate is green at the live head $head_oid. Approval remains external." \
                 -f event=DISMISS >/dev/null 2>&1; then
              retracted=$((retracted + 1))
              echo "reconcile-merged-prs: $id — PR#$num retracted superseded self-review $rid (gate green@$head_oid, GitHub was BLOCKED on a dead commit); approval now required explicitly"
            else
              echo "reconcile-merged-prs: WARN $id could not dismiss superseded review $rid on PR#$num; PR stays blocked (retry next pass)" >&2
              retract_held=$((retract_held + 1))
            fi
          else
            echo "reconcile-merged-prs: WARN $id could not record signoff_dismissed durably (read back '${paired:-}', want '$rid@$head_oid'); NOT dismissing review $rid (dismissing without a durable marker would drop the approval requirement)" >&2
            retract_held=$((retract_held + 1))
          fi
        done <<< "$SUPERSEDED"
        continue
      fi
    fi
  fi

  # --- PR open: DETECT-ONLY. The merge skill (merge-skill.sh) is the single
  # writer that lands a ready PR (validate -> merge -> record); the observer has
  # NO merge authority and never runs `gh pr merge`. A non-draft open PR is left
  # for the skill; a draft is skipped (drafts are retired). Either way the anchor
  # stays OPEN until the merged-close path above observes an authoritative merge.
  # The merge gate (the check_set markers, the open-rework-child hold,
  # mergeability) lives in the merge skill, not here — keeping the observer free
  # of merge authority.
  if [ "$state" = "OPEN" ]; then
    skipped=$((skipped + 1)); continue
  fi

  skipped=$((skipped + 1))
done <<< "$ROWS"

# --- Anchorless open PRs: the PR outlived its gating bead. -------------------
# Everything above enumerates BEAD -> PR, so it can only ever see a PR some live
# bead still names. A PR whose bead is CLOSED (or gone) is invisible to EVERY
# automated path — not this pass, not the merge skill, not the patrol — because
# all of them start from the bead. Nothing reports it, so it does not read as
# broken; it reads as absent.
#
# Not hypothetical: the pre-#163 close-on-publish model closed the work bead at
# PR-CREATION rather than on land, and the PRs it stranded sat untouched for
# weeks — surfaced only when a human cross-checked `gh pr list` against the
# ledger by hand. The close-on-land model no longer creates that state, but the
# blind spot outlives its cause: any path where a PR outlives its anchor (an
# operator closing a bead early, a force-rewrite, a deleted bead) re-enters it.
#
# So close the loop from the other side: walk PR -> BEAD and report open PRs no
# live bead points at. DETECT + SURFACE ONLY — never merge, close, or reopen
# one. Disposition (land it, close it, rework it) needs context this pass does
# not have and stays an operator call; see docs/work-bead-state-machine.md.
anchorless=0; unowned=0; foreign_prs=0
PR_LIST=$(gh pr list --repo "$ORIGIN_REPO_Q" --state open --limit 200 \
  --json number,url,isDraft,headRefName,baseRefName 2>/dev/null)
if [ -z "$PR_LIST" ]; then
  # Distinct from "[]" (a real, empty result): empty output means the call
  # failed. Skip rather than guess — retried next pass.
  echo "reconcile-merged-prs: open-PR enumeration failed; anchorless scan skipped (retry next pass)" >&2
elif [ "$PR_LIST" != "[]" ]; then
  # Every PR number named by a LIVE bead — gating anchors, rework children, and
  # review beads alike. ONE ledger query rather than one per PR: a PR named by
  # ANY live bead is tracked by something and is not a finding, whether or not
  # that bead is the anchor.
  # FAIL CLOSED, through the same guarded helper every other ledger read here uses.
  # Treating an unreadable result as "nothing is tracked" would flag every open PR
  # at once and escalate a storm, so all three failure shapes must be caught, not
  # just the empty one this used to test: `gc bd list --json` reports its own
  # failures as a non-empty error OBJECT on stdout, and a read that DIES after
  # emitting a well-formed array announces that only in its exit status. Both
  # survive an emptiness test; a genuinely empty ledger returns "[]" and does fall
  # through to the scan below (review tk-thvbq finding #3).
  #
  # $LIVE_STATUSES, not a hand-written subset. "Live" has ONE definition in this
  # script and every other lookup uses it; a shorter list here does not narrow a
  # scan, it manufactures findings — a PR whose anchor is parked `deferred`,
  # `hooked` or `pinned` is tracked by a bead that this query would not return, so
  # the PR reads as anchorless and gets reported as one (review tk-y5r1e P2).
  if ! LIVE=$(pr_bead_read --status "$LIVE_STATUSES"); then
    echo "reconcile-merged-prs: live-bead read failed; anchorless scan skipped (retry next pass)" >&2
  else
    # Every PR number a live bead names, under any key (pr_refs), NOT pr_number
    # alone: a fork_pr-keyed bead is live and does name its PR, so its PR is not
    # anchorless and must never be reported as such.
    #
    # Restricted to refs that could name a PR in THIS repository (`in_repo`): the
    # PRs being subtracted from came from `gh pr list --repo $ORIGIN_REPO_Q`, so a
    # ref positively parsed as another repository's is about a different pull
    # request and must not silence ours. `?` still matches, so a pr_number-only
    # bead tracks its PR exactly as before (review tk-thvbq finding #2).
    TRACKED=$(printf '%s' "$LIVE" \
      | jq -r --arg o "$ORIGIN_REPO_Q" "$PR_REF_JQ"'
          [ .[] | pr_refs | in_repo($o) | .[].n ] | unique | .[]' 2>/dev/null)
    # Tracked is not the same fact as OWNED, and collapsing them is how widening
    # the key set turns a false finding into false silence. A PR whose only live
    # beads carry no gating metadata has something naming it and nothing that will
    # land it — gc-qin3c/PR#100 is exactly that: fork_pr set, no merge_result, no
    # branch, no target, no merge_strategy, assignee=operator. Keep it visible on
    # its own (non-escalating) line rather than letting it drop into the silence
    # reserved for PRs an automated path is actually driving.
    OWNERS=$(printf '%s' "$LIVE" | jq -c --arg o "$ORIGIN_REPO_Q" "$PR_REF_JQ$GATING_JQ"'
      [ .[] | . as $b | (pr_refs | in_repo($o))[].n | { n: ., g: ($b | gating),
          who: (($b.id // "?")
                + (if (($b.assignee // "") | tostring) == "" then ""
                   else " (" + (($b.assignee) | tostring) + ")" end)) } ]
      | group_by(.n)
      | map({ key: .[0].n,
              value: { gated: (map(.g) | any), who: (map(.who) | unique | join(", ")) } })
      | from_entries' 2>/dev/null)
    # A failed ownership build must never turn every tracked PR into an UNOWNED
    # line, so an absent entry reads as owned below — i.e. falls back to the
    # pre-existing "tracked is enough" silence.
    [ -n "$OWNERS" ] || OWNERS='{}'
    PR_ROWS=$(printf '%s' "$PR_LIST" \
      | jq -r '.[] | [(.number|tostring), .url, (.isDraft|tostring), .headRefName, .baseRefName] | join("|")' 2>/dev/null)
    while IFS='|' read -r pnum purl pdraft phead pbase; do
      [ -n "${pnum:-}" ] || continue

      # The same identity question the per-anchor loop asks, on the OTHER
      # direction's read. `gh pr list` is pinned to $ORIGIN_REPO_Q too, and this
      # arm writes state off it: it stamps anchorless_flagged on a LOCAL closed
      # bead and mails an escalation about it. Numbers collide freely across
      # repositories, so a list that came back from anywhere else would resolve
      # strangers' pull requests onto this rig's beads. Drop the row; a wholly
      # foreign list therefore reports nothing at all rather than a storm of
      # false findings.
      if [ "$(url_repo_q "$(pr_url_canon "$purl")")" != "$ORIGIN_REPO_Q" ]; then
        foreign_prs=$((foreign_prs + 1))
        continue
      fi

      draft_note=""
      [ "$pdraft" = "true" ] && draft_note=" (draft)"

      # Tracked by a live bead -> not an ANCHORLESS finding. Exact-match so PR#7
      # is never satisfied by PR#77.
      if list_has_line "$TRACKED" "$pnum"; then
        # Owned by something that can act on it -> genuinely fine, stay silent.
        # `has($n)`, NOT `.[$n].gated // true`: jq's `//` treats FALSE as empty,
        # so the alternative form rewrites every ungated PR to gated=true and
        # silently disables this whole arm. The default belongs to the missing
        # key (an unbuilt map reads as owned), never to a present `false`.
        gated=$(printf '%s' "$OWNERS" \
          | jq -r --arg n "$pnum" 'if has($n) then .[$n].gated else true end' 2>/dev/null)
        [ "$gated" = "true" ] && continue
        # Tracked but UNOWNED. Distinct from anchorless (a bead does name it, so
        # an operator has somewhere to start) and NOT escalated (the naming bead
        # is live, so this is a routing gap, not a stranded PR), but it is not
        # "fine" either: no automated path will land it.
        who=$(printf '%s' "$OWNERS" | jq -r --arg n "$pnum" '.[$n].who // ""' 2>/dev/null)
        unowned=$((unowned + 1))
        echo "reconcile-merged-prs: UNOWNED PR#$pnum$draft_note ($phead -> $pbase) — named by live bead(s) ${who:-?}, none carrying gating metadata (no merge_result/merge_strategy/branch/target); tracked, but no automated path will land it"
        continue
      fi

      # Resolve the bead that DID name this PR, if one still exists. A closed one
      # is the high-confidence signature (a Gas City PR whose anchor closed out
      # from under it) AND the only durable place to bound the escalation.
      # --limit=0 (all), not a page: the pick below is "oldest carrying
      # merge_result", so a truncated page could hide the very bead we want.
      # Keyed the same widened way as TRACKED — a closed fork_pr-keyed anchor must
      # resolve here too, or the PR reports as "no bead in any state" (the
      # non-escalating arm) when a perfectly good bead names it.
      if ! dead=$(pr_bead_query closed "$pnum"); then
        # Cannot tell who owned it. It IS untracked by any live bead, so it stays
        # a finding, but the escalation has nothing durable to bound it with —
        # report and retry next pass rather than mail unbounded.
        anchorless=$((anchorless + 1))
        echo "reconcile-merged-prs: ANCHORLESS PR#$pnum$draft_note ($phead -> $pbase) — closed-bead resolution failed; not escalating (retry next pass)" >&2
        continue
      fi
      # Several closed beads routinely name one PR — the anchor that opened it,
      # its review beads, and any "address findings" rework children. Pick the
      # bead that OPENED the PR, since that is the one an operator reopens to
      # re-engage it: filter to those carrying merge_result (the gating-anchor
      # signature, which review beads lack), then take the OLDEST, because the
      # rework children that share that marker were all created later. Fall back
      # to the oldest bead of any kind if none carries the marker.
      dead_row=$(printf '%s' "$dead" | jq -c '
        (map(select((.metadata.merge_result // "") != "")) | sort_by(.created_at // "")) as $anchors
        | (if ($anchors | length) > 0 then $anchors else sort_by(.created_at // "") end)
        | .[0] // empty' 2>/dev/null)
      dead_id=$(printf '%s' "$dead_row" | jq -r '.id // empty' 2>/dev/null)
      dead_flag=$(printf '%s' "$dead_row" | jq -r '.metadata.anchorless_flagged // empty' 2>/dev/null)
      # Every closed bead naming this PR, oldest first. The disposition may touch
      # more than the one we mark, so the operator gets the whole set, not just
      # our pick.
      dead_all=$(printf '%s' "$dead" \
        | jq -r '[sort_by(.created_at // "") | .[].id] | join(", ")' 2>/dev/null)
      anchorless=$((anchorless + 1))

      if [ -z "$dead_id" ]; then
        # No bead names this PR in any state. It may never have been Gas City's
        # (a human or bot opened it), so this is reported but NOT escalated:
        # there is nothing durable to mark, and an unbounded mail would repeat
        # every wake. The log line is the surface.
        echo "reconcile-merged-prs: ANCHORLESS PR#$pnum$draft_note ($phead -> $pbase) — no bead in any state references it; not tracked by any automated path"
        continue
      fi
      if [ "$dead_flag" = "$pnum" ]; then
        # Already escalated for this PR. Keep reporting it (it is still stranded)
        # but do not re-mail.
        echo "reconcile-merged-prs: ANCHORLESS PR#$pnum$draft_note ($phead -> $pbase) — anchor $dead_id is CLOSED; already escalated, awaiting operator disposition"
        continue
      fi
      # Stamp FIRST, mail second — the same close-FIRST convergence the merged
      # path uses. If the stamp fails we have no bound, so we must NOT mail:
      # report loudly and retry next pass. A delayed escalation is recoverable;
      # a mail storm is not.
      if gc bd update "$dead_id" --set-metadata anchorless_flagged="$pnum" >/dev/null 2>&1; then
        if gc mail send mayor/ -s "ESCALATION: anchorless open PR#$pnum (bead $dead_id is closed)" \
             -m "PR#$pnum is OPEN but its bead $dead_id is CLOSED, so no automated path can see it.
Every close-on-land path — this reconciler, the merge skill, the refinery patrol —
enumerates from the BEAD, so a closed bead with an open PR is invisible to all of
them: it will never be landed, rejected, or escalated on its own.

  PR:     $purl$draft_note
  Branch: ${phead:-?} -> ${pbase:-?}
  Bead:   $dead_id (closed) — the bead that opened the PR
  All:    ${dead_all:-$dead_id} (every closed bead naming PR#$pnum, oldest first)

The refinery took NO action: disposition is an operator call, not a merge-processor
one. Decide: LAND it (approve on GitHub, then reopen the bead as a gating anchor —
status=open, merge_result=pull_request, check_set/check.* at the live head — so the
merge skill lands and closes it), CLOSE the PR as abandoned (the bead is already
closed; nothing else to do), or REWORK it (reopen the bead and route it to a
polecat). This pass reports it once and will not act on it." >/dev/null 2>&1; then
          escalated=$((escalated + 1))
        fi
        echo "reconcile-merged-prs: ANCHORLESS PR#$pnum$draft_note ($phead -> $pbase) — anchor $dead_id is CLOSED; routed to operator + escalated"
      else
        echo "reconcile-merged-prs: ANCHORLESS PR#$pnum$draft_note — could not mark bead $dead_id; not escalating unbounded (retry next pass)" >&2
      fi
    done <<< "$PR_ROWS"
    # Never silent: dropping every row is exactly what an ignored `--repo` looks
    # like, and "0 anchorless" would otherwise read as a clean scan.
    [ "$foreign_prs" -eq 0 ] || \
      echo "reconcile-merged-prs: $foreign_prs enumerated open PR(s) did not name '$ORIGIN_REPO_Q' and were IGNORED; the pinned \`gh pr list\` answered for another repository — the anchorless scan is not authoritative this pass" >&2
  fi
fi

echo "reconcile-merged-prs: $closed closed, $abandoned abandoned ($escalated escalated), $retargeted retargeted, $rebased stale-base rebases routed, $rebase_held rebases held, $regated stale-gate re-reviews routed, $gate_held stale-gate re-reviews held, $retracted superseded reviews retracted, $retract_held retractions held, $identity_held foreign-PR identity holds, $anchorless anchorless open PRs, $unowned unowned open PRs, $skipped skipped"
exit 0
