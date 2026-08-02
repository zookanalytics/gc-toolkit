#!/usr/bin/env bash
# merge-skill — the single writer of merged-truth (docs/work-bead-state-machine.md
# "Merge: one writer of merged-truth"). This is the main-PR LANDING path: it
# replaces GitHub auto-merge (`gh pr merge --auto`) with an explicit merge the
# refinery performs itself. The refinery is the single writer — it does not
# delegate the landing to GitHub and then poll for the result.
#
# Runs on the refinery's idle wake, folded into mol-refinery-patrol's find-work
# loop, BEFORE the detect-only observer (reconcile-merged-prs.sh). For each OPEN
# gating anchor (the bead parked OPEN on a published PR, marked
# merge_result=pull_request by mol-refinery-patrol merge-push step 4) whose PR is
# open, non-draft, and whose full check-set is satisfied, it performs the three
# merge-skill actions IN ORDER:
#
#   validate -> merge -> record
#
#   validate: the PR is claimed by exactly ONE open anchor (a second anchor
#             would let the weakest check_set decide the merge — tk-ynz4b),
#             the PR's live base == the anchor's merged_target (no retarget),
#             every gate the anchor declares in check_set is green AT THE LIVE
#             HEAD (per-gate marker check.<name>=green@<head>, so a stale approval
#             or a post-review commit re-gates instead of merging), no unclosed
#             rework/review child holds the anchor — resolved BOTH by pr_number and
#             through the anchor's own dependency edges, because a rework child
#             carries the branch while the ANCHOR carries PR identity (an unclosed
#             child holds the merge — an anchor lands only when ALL its children
#             are closed), and
#             GitHub reports the PR mergeable with its required check-set green
#             (mergeStateStatus=CLEAN folds CI + approval + base-current +
#             no-conflict into one signal).
#   merge:    `gh pr merge --squash` — an IMMEDIATE merge, NOT `--auto`. Branch
#             protection still gates the real merge server-side; a server-side
#             refusal leaves the anchor OPEN and is retried next idle pass.
#   record:   close the anchor "Merged to <target> at <sha>" and stamp
#             merge_result=merged + merged_sha — synchronous, because the skill
#             that merged is the one that knows it merged. If the record half
#             dies after a successful merge, the observer's merged-close path
#             (reconcile-merged-prs.sh) is the convergent backstop next pass.
#
# Single writer, on purpose: the merge is performed in exactly ONE place. Any
# anchor that is NOT open/ready — already merged, closed-unmerged, retargeted,
# draft — is LEFT untouched for the observer to record or escalate; the skill
# only ever MERGES, it never records a transition it did not perform. Keeping one
# authority over "did it land" means no second place for that state to drift.
#
# NOT set -e: best-effort, must never abort the patrol's idle loop. A merge is
# performed ONLY on an authoritative all-green validate; any tool error or a
# non-CLEAN state simply skips the anchor and retries next idle pass.
#
# Enumerated by BEAD, not by `gh pr list` — but a bead names its PR by NUMBER,
# and a number does not name a pull request: `gh pr view <n>` resolves it in
# whatever repository gh considers CURRENT, which `gh repo set-default`, GH_REPO,
# GH_HOST or a different cwd all move. check-set-heal.sh certifies that identity
# before it exposes a recovered anchor here — but a certification performed in
# THAT process does not travel to this one, and the anchors it recovers are
# pr_number-only until it backfills the certified pr_url. So this script asks the
# same question for itself, of the one source gh cannot move: what this checkout
# pushes to (review tk-sdqwh finding #2).
set -uo pipefail

# gh is the only way to read PR state and perform the merge here. Without it
# there is nothing to do (the observer's merged-close path also no-ops without
# gh, so an un-merged anchor simply waits).
command -v gh >/dev/null 2>&1 || exit 0

# Statuses a bead can hold that are NOT "finished". The child gate's invariant is
# "an anchor lands only when ALL its children are CLOSED" — so every non-closed
# status holds, not just open/in_progress. A `blocked` child in particular is the
# strongest reason to hold (something is stuck on it) and was the live shape in
# tk-lgjvg: the rework child was blocked + routed to human while its anchor merged
# past it. Same value and same name as reconcile-merged-prs.sh's LIVE_STATUSES, on
# purpose — the observer and the merge skill must agree on what "still live" means
# or one will route work the other has already merged past.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# Per-probe wall-clock bound. This skill runs inside mol-refinery-patrol's
# find-work loop, which applies no timeout of its own, so an unbounded `gc bd`
# against a wedged Dolt hangs the PATROL — every anchor behind it, not just this
# one. A hung probe is the same thing as an unreadable one (both mean "the holder
# set is unknown"), and the gate already fails CLOSED on unreadable, so bounding
# converts a stall into the held/retry path it belongs in. Same idiom and same
# env-override shape as doctor/check-merge-gate-drop/run.sh's run_bounded.
PROBE_BOUND="${MERGE_SKILL_PROBE_TIMEOUT:-30}"

# Every probe runs with stdin CLOSED. The anchor loop below reads its work list
# from a here-string on fd 0; a probe child that inherited and consumed it would
# silently truncate the anchor sweep — anchors would vanish from the run rather
# than fail, which reads as "nothing to merge".
run_bounded() {
  if command -v timeout >/dev/null 2>&1; then
    # timeout exits 124 on expiry — a non-zero rc, so it lands in the same
    # fail-closed branch as any other broken probe. No special case needed.
    timeout "$PROBE_BOUND" "$@" </dev/null
  else
    # No coreutils timeout (some macOS hosts). Degrade to an unbounded call
    # rather than dropping the probe: a skipped probe fails closed and would
    # hold EVERY merge forever on such a host.
    "$@" </dev/null
  fi
}

# Read a `gc bd`-family JSON array, or fail. Mirrors reconcile-merged-prs.sh's
# pr_bead_read: the command's own exit status, then a non-empty payload, then the
# payload's SHAPE. The shape check is what separates "no results" (`[]`) from an
# error object that arrived with a zero exit status — `.[]` iterates an object's
# values happily, so without it a malformed read projects cleanly to "no children".
#
# The shape check has THREE layers, and none is belt-and-braces.
#
#   DOCUMENT COUNT (tk-wkrcy). The payload must be EXACTLY ONE JSON document.
#   `jq -e` is not a validator of a raw STREAM: it evaluates the program once per
#   document and its exit status reflects only the LAST output, so a probe that
#   emits `{}` (a stray progress/error object, an interleaved warning — city.toml
#   stderr pollution of --json output is a known shape) followed by a valid array
#   PASSED the old top-level check. Downstream that is worse than an outright
#   failure: probe_holders slurps all three probe payloads into ONE stream and
#   reads them POSITIONALLY as .[0]/.[1]/.[2], so one extra leading document
#   shifts every later probe down a slot — the blockers array lands at .[3] and is
#   silently dropped, and a real merge-ordering blocker stops holding the merge.
#   That is a fail-OPEN shape reachable with a zero exit status, which is why the
#   count is enforced HERE and the canonical single document is what we emit:
#   every caller then gets one document per probe by construction, never a stream
#   whose length it has to trust.
#
#   TOP-LEVEL SHAPE. `.[]` iterates an object's values happily, so without it a
#   malformed read (an error object that arrived with a zero exit status)
#   projects cleanly to "no children".
#
#   PER-ELEMENT SHAPE (tk-qoyly). The holder filter downstream indexes
#   `.metadata.merge_result` on every element; one element whose metadata is a
#   string (schema drift, a probe that returned a mixed payload) makes that jq
#   abort — and an aborted filter yields an EMPTY holder list, which reads as "no
#   children" and merges past every real holder that was in the array. So an array
#   that cannot be read element-for-element is an UNREADABLE probe, not an empty
#   one. Required per element: an object, a usable non-empty string id, and
#   metadata that is an object or absent.
bead_read_array() {
  local raw rc out
  raw=$(run_bounded "$@" 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ -n "$raw" ] || return 1
  # -s slurps the whole stream into an array of documents, which is what makes
  # the count observable at all; each `error(...)` aborts jq with a non-zero exit
  # and no stdout, landing in the same fail-closed branch as a broken probe.
  out=$(printf '%s' "$raw" | jq -sc '
      if length != 1 then error("probe emitted \(length) JSON documents, want exactly 1") else .[0] end
      | if type == "array" then . else error("probe payload is not an array") end
      | if all(.[];
               type == "object"
               and ((.id | type) == "string")
               and ((.id | length) > 0)
               and (((.metadata | type) as $t | $t == "object" or $t == "null")))
        then . else error("probe payload holds an unreadable element") end
    ' 2>/dev/null) || return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# Every bead that HOLDS the merge of anchor $1 (PR #$2), as one JSON array.
# Returns non-zero if ANY probe is unreadable, so the caller can fail closed.
#
# Three sources, because no single one sees every holder:
#
#   1. pr_number=<num> — beads naming the PR in their OWN metadata. This is what
#      the observer's rebase and re-review children stamp
#      (reconcile-merged-prs.sh), and it is the ONLY source this gate used before
#      tk-lgjvg.
#   2. dep up / parent-child — the anchor's CHILDREN. A rework child filed by the
#      signoff gate carries branch + source_review_bead but NOT pr_number: the
#      ANCHOR is the bead that owns PR identity, and the PRE-OPEN rework arm
#      cannot stamp a number at all because no PR exists yet when it files. Keyed
#      on pr_number alone such a child is invisible and the gate PASSES — the
#      fail-OPEN defect this function exists to close (live case: anchor tk-h9pq5
#      / PR#233 merged past its open rework child tk-t88hg).
#   3. dep down / blocks — the beads that BLOCK the anchor. That is precisely how
#      a signoff gate attaches ("the gate's bead BLOCKS the convoy",
#      docs/work-bead-state-machine.md) and how an operator files an explicit
#      merge-ordering block.
#
# The two walks deliberately NOT taken are the reason both dep probes are type-
# filtered; either one would deadlock a healthy anchor forever:
#   - up / blocks         = DOWNSTREAM beads waiting for this one to LAND. They
#                           are unblocked BY the merge, so holding on them is a
#                           cycle (live shape: tk-274uj "Depends on tk-h9pq5").
#   - down / parent-child = this anchor's own PARENT (an epic or convoy), which
#                           stays open by construction until the anchor closes.
#
# Each holder is tagged with the PROVENANCE that found it, in the synthesized
# `_via` field ("pr_number" or "dep"; a bead seen by both is "dep", the stronger
# claim). The caller needs it because the two sources justify DIFFERENT filters,
# and BOTH of the caller's exclusions are scoped to `_via == "pr_number"` for one
# shared reason: they exist to undo the pr_number probe's over-broad sweep, and
# neither describes anything true of a bead found by a dependency edge.
#   - merge_result drops a duplicate ANCHOR the pr_number probe swept up. Applied
#     to a dependency edge it deletes a real holder — an upstream PR / pre-open
#     anchor filed as an explicit merge-ordering `blocks` carries merge_result by
#     definition — so the exclusion made the gate fail OPEN on exactly the edge
#     that was added to close it (tk-je0rk).
#   - REPOSITORY identity drops a foreign bead that names the same PR NUMBER in
#     another repository. Applied to a dependency edge it deletes a legitimate
#     CROSS-REPOSITORY blocker, which is the whole point of filing one by hand —
#     the same fail-OPEN shape, re-entered through the identity guard (tk-9m8q4).
# A dependency edge is a claim made in THIS ledger about THIS anchor; a PR number
# is a coincidence until certified. Only the coincidence gets filtered.
probe_holders() {
  local anchor="$1" num="$2" by_pr children blockers
  by_pr=$(bead_read_array gc bd list --metadata-field pr_number="$num" \
    --status "$LIVE_STATUSES" --limit=0 --json) || return 1
  children=$(bead_read_array gc bd dep list "$anchor" \
    --direction=up -t parent-child --json) || return 1
  blockers=$(bead_read_array gc bd dep list "$anchor" \
    --direction=down -t blocks --json) || return 1
  # The three payloads are read POSITIONALLY, so the slurped stream must be
  # exactly three documents. bead_read_array already guarantees one canonical
  # document each (tk-wkrcy); this restates that as a hard assertion at the point
  # the positions are actually consumed, so any future drift is a fail-CLOSED
  # error instead of a silent slot shift that drops a probe off the end.
  #
  # group_by(.id) rather than unique_by(.id): dedup must MERGE provenance, not
  # pick whichever copy sorted first. A bead reachable both ways is a dependency
  # holder — take the union, so a dep-linked bead that also stamps pr_number is
  # never demoted to the excludable pr_number class.
  printf '%s\n%s\n%s' "$by_pr" "$children" "$blockers" \
    | jq -sc '
        if length != 3 then error("probe stream is \(length) documents, want exactly 3") else . end
        | [ (.[0][] | . + {_via: "pr_number"}),
            (.[1][] | . + {_via: "dep"}),
            (.[2][] | . + {_via: "dep"}) ]
        | group_by(.id)
        | map(.[0] + {_via: (if (map(._via) | index("dep")) then "dep" else "pr_number" end)})
      ' 2>/dev/null
}
# THE REPOSITORY EVERY PR READ AND EVERY MERGE IS PINNED TO. Host-qualified
# `<host>/<owner>/<repo>`, the form `--repo` pins with (`[HOST/]OWNER/REPO`, host
# filled from GH_HOST when omitted — `gh help environment`) and the form a
# pull-request URL carries, so a hostless pin cannot be re-hosted underneath us.
# It comes from the origin remote, NEVER from `gh`: gh's current repository is
# the very thing a foreign same-numbered PR arrives through, so asking gh to
# name the expectation would make the check vacuous.
#
# Same parse and same fail-closed rule as check-set-heal.sh's
# resolve_origin_repo/resolve_origin_repo_q, which is the reference
# implementation; these scripts are standalone by design (the patrol resolves and
# runs each one independently, and an importer rig may be running an older pack),
# so the helper is duplicated rather than sourced. Keep them in step.
ORIGIN_REPO_Q=""
origin_url=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$origin_url" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_REPO_Q=$(printf '%s' "$origin_url" \
      | sed -e 's#^ssh://git@github.com/##' -e 's#^git@github.com:##' \
            -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
# Exactly `<owner>/<repo>`, or nothing: a half-parsed value would pin the read to
# a repository nobody named.
case "$ORIGIN_REPO_Q" in
  */*/*|/*|*/) ORIGIN_REPO_Q="" ;;
  */*)         ORIGIN_REPO_Q="github.com/$ORIGIN_REPO_Q" ;;
  *)           ORIGIN_REPO_Q="" ;;
esac
if [ -z "$ORIGIN_REPO_Q" ]; then
  # FAIL CLOSED. Unresolvable origin means every PR number below would be read —
  # and merged — in a repository this script cannot name, which is the one error
  # here that is not a deferral: a wrong merge cannot be retried away. Merging
  # nothing this pass costs one idle wake.
  echo "merge-skill: cannot resolve this checkout's origin repository (no origin remote, or not a github.com <owner>/<repo> URL); a bare PR number would be read in whatever repository gh considers current, so NOTHING is merged this pass" >&2
  exit 0
fi

# The SAME repository, hostless. `gh` reports a pull request's HEAD repository as
# `headRepositoryOwner.login` + `headRepository.name` and nothing else — a PR's head
# is always on the PR's own host, so gh omits it — and the head check below compares
# against that shape. Derived from the host-qualified form rather than re-parsed, so
# the two can never disagree about which repository this checkout pushes to. Mirrors
# check-set-heal.sh's ORIGIN_REPO / pre-open-resolve.sh's.
ORIGIN_REPO="${ORIGIN_REPO_Q#*/}"

# The repository a pull-request URL names, host-qualified — one definition for
# both places identity is compared. Mirrors check-set-heal.sh's url_repo_q.
url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}

# The same question, asked in jq of a bead's own metadata, for the two HOLD guards
# below. Both used to key on the bare PR NUMBER, and a number names a different
# pull request in every other repository this ledger spans — so a foreign bead
# carrying #<n> could hold THIS repository's #<n>:
#
#   dup-anchor  a foreign anchor for `otherhost/o/OTHER#745` makes our #745 look
#               claimed by two open anchors, and EVERY anchor of a "multi-anchor"
#               PR is held — a hold no operator can release by repairing anything
#               in this repository;
#   open-child  a foreign rework child naming #745 reads as rework in flight on
#               ours, holding it indefinitely.
#
# Both fail toward HOLDING rather than merging, which is why they are P2 and not a
# merge hazard — but an indefinite hold on a ready PR is the silent stall the whole
# check-set-heal/reconcile pass exists to end, arrived at from the other side
# (review tk-thvbq finding #4).
#
# `?` is the fail-closed wildcard and matches ANY repository, so ONLY a positive,
# parsed disagreement clears a hold; a legacy row that names no URL at all holds
# exactly as it does today. Same rule and same host-qualified form as
# check-set-heal.sh's incumbent/in-flight guards and reconcile-merged-prs.sh's
# pr_refs; these scripts are standalone by design, so it is duplicated rather than
# sourced. Keep them in step.
REPO_JQ='
def repo_of:
  ([ capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<r>[^/]+/[^/]+)/pull/[0-9]") ] | .[0])
  | (if . == null then "?" else (.h + "/" + .r) end);
def same_repo($a; $b): ($a == "?" or $b == "?" or $a == $b);
'

# Open gating anchors in this rig's ledger. Bounded for the same reason as the
# holder probes, and FIRST in line: this read runs before any of them, so leaving
# it unbounded would hang the patrol here and the probe bounds would never be
# reached. Its failure semantics are unchanged — a timeout empties ANCHORS, which
# takes the existing "no gating anchors" exit. That degrades to merging NOTHING
# this pass, never to merging something unvalidated.
ANCHORS=$(run_bounded gc bd list --status=open \
  --metadata-field merge_result=pull_request \
  --limit=200 --json 2>/dev/null)
[ -n "$ANCHORS" ] && [ "$ANCHORS" != "[]" ] \
  || { echo "merge-skill: no gating anchors"; exit 0; }

# One compact JSON row per anchor. Built into a variable (not piped into the
# loop) so the loop runs in THIS shell and the counters below survive the
# pipe/subshell boundary.
#
# `repo` is WHICH REPOSITORY'S PR#<n> this anchor names, resolved once here and
# carried on the row so the duplicate guard below cannot disagree with it: from the
# anchor's own pr_url when it parses, otherwise this checkout's origin — which is
# the repository the pinned `gh pr view --repo` below WILL resolve its number in,
# and so the only repository this anchor can turn out to be about. Same resolution
# order as check-set-heal.sh's candidate rows.
ROWS=$(printf '%s' "$ANCHORS" \
  | jq -c --arg o "$ORIGIN_REPO_Q" "$REPO_JQ"'.[] | (((.metadata.pr_url // "") | tostring) | repo_of) as $r | {id, pr: (.metadata.pr_number // ""), prurl: (.metadata.pr_url // ""), repo: (if $r == "?" then $o else $r end), branch: (.metadata.branch // ""), target: (.metadata.merged_target // ""), checkset: (.metadata.check_set // ""), hold: (.metadata.merge_hold // ""), meta: (.metadata // {})}' 2>/dev/null)
[ -n "$ROWS" ] || { echo "merge-skill: no gating anchors"; exit 0; }

# One-anchor-per-PR guard (tk-ynz4b): the loop below validates each anchor
# INDEPENDENTLY, so a PR claimed by more than one open anchor is gated by its
# WEAKEST anchor — e.g. a rework child that leaked into the anchor class with no
# check_set would land the PR while the real anchor's codex gate is red, and
# (carrying merge_result) that same leaked bead is invisible to the in-flight
# rework hold below. One gating anchor per PR is the design intent
# (docs/work-bead-state-machine.md); the refinery no longer mints a second
# anchor on rework hand-back (mol-refinery-patrol.toml one-anchor-per-pr arm),
# so a duplicate here is legacy/out-of-band state. Precompute the anchors claimed
# by >1 open anchor; EVERY anchor of such a PR is held in validate.
#
# KEYED ON REPOSITORY **AND** NUMBER, with `?` matching anything (see REPO_JQ): a
# foreign anchor for another repository's #<n> is not a duplicate of ours, and
# keyed on the bare number it held both forever. The result is a set of anchor IDs
# rather than numbers, because with a wildcard in the key "this number is
# ambiguous" is no longer a property of the number alone — two anchors can share a
# number and still be positively distinct, so each is judged against the anchors it
# actually collides with. Same construction as check-set-heal.sh's DUP_CAND.
DUP_ANCHORS=$(printf '%s\n' "$ROWS" \
  | jq -rs "$REPO_JQ"'. as $all
      | [ $all[]
          | . as $a
          | select($a.pr != "")
          | select([ $all[]
                     | select(.id != $a.id)
                     | select(.pr == $a.pr)
                     | select(same_repo(.repo; $a.repo)) ] | length > 0)
          | $a.id ]
      | .[]' 2>/dev/null)

merged=0; held=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  num=$(printf '%s' "$row" | jq -r '.pr // empty')
  prurl=$(printf '%s' "$row" | jq -r '.prurl // empty')
  arepo=$(printf '%s' "$row" | jq -r '.repo // empty')
  [ -n "$arepo" ] || arepo="?"
  abranch=$(printf '%s' "$row" | jq -r '.branch // empty')
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  hold=$(printf '%s' "$row" | jq -r '.hold // empty')
  if [ -z "$id" ] || [ -z "$num" ]; then
    skipped=$((skipped + 1)); continue
  fi

  # Read live PR state, PINNED to this checkout's repository. Only request fields
  # supported by `gh pr view --json` on supported gh versions — an unknown field
  # errors and, with stderr suppressed, empties PR_JSON, skipping the anchor
  # forever. mergeStateStatus is the composite gate (CLEAN = mergeable, required
  # checks green, approved, base current); the test's gh stub rejects unsupported
  # fields to guard this. `url` is requested for the identity check below.
  PR_JSON=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" \
    --json state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,url 2>/dev/null)
  if [ -z "$PR_JSON" ]; then
    echo "merge-skill: PR#$num view failed; skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
  is_draft=$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')
  base=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // ""')
  head_ref=$(printf '%s' "$PR_JSON" | jq -r '.headRefName // ""')
  head_oid=$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // ""')
  merge_state=$(printf '%s' "$PR_JSON" | jq -r '.mergeStateStatus // ""')
  mergeable=$(printf '%s' "$PR_JSON" | jq -r '.mergeable // ""')
  live_url=$(printf '%s' "$PR_JSON" | jq -r '.url // ""' \
    | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##')
  # `<owner>/<repo>` of the branch the PR is opened FROM, assembled defensively: gh
  # returns both as objects that are NULL when the head repository has been deleted,
  # and a half-resolved "owner/" would compare unequal by luck rather than by design.
  # Either both halves are present or the value is empty — and empty is UNREADABLE,
  # which holds. Compared BARE: a PR's head is always on the PR's own host, so gh
  # reports it hostless and the host half of the identity is carried by the url.
  # Byte-identical to pre-open-resolve.sh's certify_pr_row; keep them in step.
  head_repo=$(printf '%s' "$PR_JSON" | jq -r '
    ((.headRepositoryOwner.login // "") | tostring) as $o
    | ((.headRepository.name // "") | tostring) as $n
    | if $o == "" or $n == "" then "" else $o + "/" + $n end' 2>/dev/null)
  # GitHub's own answer to "is the head somewhere else?", read as a STRING so a
  # field gh did not return is empty rather than "false".
  head_cross=$(printf '%s' "$PR_JSON" | jq -r 'if has("isCrossRepository") then (.isCrossRepository | tostring) else "" end' 2>/dev/null)

  # --- identity: is the PR that answered really THIS anchor's PR? -----------
  # Asked BEFORE any state is derived from the answer, because every gate below
  # trusts the object this read returned. `--repo` above already pinned it, so
  # both checks should now be tautologies — and they are kept precisely because
  # they should be: a gh that ignores the flag, a redirect after a repository
  # transfer or rename, or an unparseable URL surfaces HERE as a refusal instead
  # of as a merge. This is the one script whose mistake cannot be retried away
  # (review tk-sdqwh finding #2).
  live_repo_q=$(url_repo_q "$live_url")
  if [ "$live_repo_q" != "$ORIGIN_REPO_Q" ]; then
    echo "merge-skill: PR#$num answered from '${live_repo_q:-<unparseable>}', not this checkout's '$ORIGIN_REPO_Q'; that is another repository's pull request — merge held (anchor $id), operator must repair the metadata"
    held=$((held + 1)); continue
  fi
  # The anchor's own recorded URL, when it has one — the identity check-set-heal.sh
  # certified and persisted, re-checked here by the process that acts on it. Same
  # normalization on both sides (trailing slashes, /files, #discussion trimmed);
  # an anchor with no pr_url is governed by the pinned read and the repository
  # check above.
  if [ -n "$prurl" ]; then
    want_url=$(printf '%s' "$prurl" | tr -d '[:space:]' \
      | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##')
    if [ "$want_url" != "$live_url" ]; then
      echo "merge-skill: PR#$num resolves to '$live_url' but anchor $id records pr_url '$prurl'; the bead and the PR name different pull requests — merge held, operator must repair the metadata"
      held=$((held + 1)); continue
    fi
  fi

  # --- identity, second half: WHERE DOES THIS PULL REQUEST COME FROM? ---------
  # The checks above establish that the PR LIVES in this repository. That is not the
  # same claim as it being OURS. A pull request opened INTO this repository FROM a
  # fork carries one of OUR urls — same host, same owner, same repo, same number —
  # and differs only in its HEAD. So every check above passes on it, and this script
  # then SQUASH-MERGES that fork's head onto the target under our anchor's gates
  # (review tk-pka2d finding #2). pre-open-resolve.sh already refuses such a row
  # before adopting it; the landing path is the one place the mistake cannot be
  # retried away, so it must ask the same question of the PR it is about to merge.
  #
  # Three halves, all required:
  #   head repo    the branch is in THIS repository, not a fork of it
  #   cross-repo   ...and GitHub agrees; a row claiming our head repo while ALSO
  #                reporting itself cross-repository has contradicted itself, and a
  #                self-contradicting identity is unestablished, not a tie to break
  #   head branch  it is the branch this anchor recorded — the right work, not just
  #                the right repository. Only checked when the anchor HAS a recorded
  #                branch: a pr_number-only anchor (what check-set-heal.sh's recovery
  #                produces before backfill) has nothing to disagree with, and is
  #                governed by the two repository checks.
  #
  # Unreadable is HELD, not merged: a gh whose schema shifted, or a head repository
  # that was deleted, leaves the question unanswered — and unanswered must not land.
  if [ -z "$head_repo" ] || [ -z "$head_cross" ]; then
    echo "merge-skill: PR#$num head identity is unreadable (headrepo='${head_repo:-<empty>}' cross='${head_cross:-<empty>}'); cannot tell whether it is opened from this repository or a fork of it — merge held (anchor $id), retry next pass"
    held=$((held + 1)); continue
  fi
  if [ "$head_repo" != "$ORIGIN_REPO" ]; then
    echo "merge-skill: PR#$num is opened from FORK '$head_repo', not this checkout's '$ORIGIN_REPO'; it lives in our repository but the work is not ours — merge held (anchor $id), operator must repair the metadata"
    held=$((held + 1)); continue
  fi
  if [ "$head_cross" != "false" ]; then
    echo "merge-skill: PR#$num reports head repository '$head_repo' (this checkout's own) and cross-repository='$head_cross' at the same time; the two halves of the head identity disagree, so it is not certified — merge held (anchor $id), retry next pass"
    held=$((held + 1)); continue
  fi
  if [ -n "$abranch" ] && [ "$head_ref" != "$abranch" ]; then
    echo "merge-skill: anchor $id records branch '$abranch' but PR#$num is opened from '$head_ref'; the bead and the PR describe different work — merge held, operator must repair the metadata"
    held=$((held + 1)); continue
  fi

  # The merge skill acts ONLY on an OPEN, non-draft PR. Merged / closed-unmerged /
  # retargeted are the observer's to record or escalate; the skill never records
  # a transition it did not perform (single writer of merged-truth).
  [ "$state" = "OPEN" ] || { skipped=$((skipped + 1)); continue; }
  [ "$is_draft" != "true" ] || { skipped=$((skipped + 1)); continue; }

  # --- validate -----------------------------------------------------------
  # Operator hold: metadata.merge_hold on the anchor is an explicit operator gate
  # ("do not land yet — awaiting manual sign-off"). When truthy the skill must NOT
  # merge no matter how green the PR looks. Checked FIRST, before every PR-state
  # gate: it is the cheapest gate (metadata already in hand) and the highest
  # priority (an intentional operator block, independent of PR state), so a held
  # anchor short-circuits before the referencing-bead `gc bd list`. Before this
  # gate the hold was honored only INCIDENTALLY — when the PR happened to be
  # non-CLEAN (BLOCKED/BEHIND) — so a fully-CLEAN held PR would squash-merge to the
  # target with no operator signal. Truthy = set and not empty/false/0 (operators
  # set merge_hold=true); an unset or explicitly-false marker does not hold.
  case "$hold" in
    ""|false|False|FALSE|0|null) : ;;
    *)
      echo "merge-skill: PR#$num merge_hold set (operator gate); merge held for operator (anchor $id)"
      held=$((held + 1)); continue ;;
  esac
  # One-anchor-per-PR (tk-ynz4b): this PR is claimed by multiple open anchors,
  # so no single anchor's check_set can be trusted to speak for the PR — the
  # weakest would decide the merge. Hold every anchor of the PR; the hold
  # releases on a later pass once exactly one open anchor remains (close/demote
  # the duplicate — usually the rework-minted one — to repair the taxonomy).
  if [ -n "$DUP_ANCHORS" ] && printf '%s\n' "$DUP_ANCHORS" | grep -qxF "$id"; then
    echo "merge-skill: PR#$num has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor $id) — close/demote the duplicate anchor to release (tk-ynz4b)"
    held=$((held + 1)); continue
  fi
  # Retarget: live base must still match the anchor's recorded merged_target. A
  # mismatch means the PR was retargeted after publication; merging would land on
  # the WRONG branch. Hold — the observer (reconcile-merged-prs.sh) escalates the
  # retarget to a human; the skill must never merge across the mismatch.
  if [ -n "$target" ] && [ -n "$base" ] && [ "$target" != "$base" ]; then
    echo "merge-skill: PR#$num base '$base' != target '$target' (retargeted); merge held (anchor $id, observer escalates)"
    held=$((held + 1)); continue
  fi
  # Check-set: every gate the anchor declares in check_set must be green AT THE
  # LIVE HEAD, recorded as a per-gate marker check.<name>=green@<head_oid>. The
  # green@<sha> form folds two checks the old single signoff_head conflated —
  # "this gate passed" and "title/description current at this commit" — into one
  # value: a post-review commit moves the head, so a marker stamped at the old
  # head (green@<old-sha>) no longer matches and the gate re-gates, stopping a
  # stale approval from carrying an out-of-date PR onto the target. An EMPTY
  # check_set declares NO gates, and the merge is then governed only by the
  # remaining members below (no-retarget, no-open-child, mergeStateStatus=CLEAN
  # = CI + approval). That empty case is the bug fix: the former code held the
  # merge UNCONDITIONALLY on a missing signoff_head even when no signoff gate was
  # required, stranding human-approved CLEAN PRs forever; a no-gate check_set now
  # lands once CLEAN. `hold_gate` is the first gate not green at the live head
  # (empty string when all are), computed in jq so a dynamic marker key
  # (check.<name>) needs no bash-array gymnastics.
  #
  # The `none`/`off` SENTINEL is read as no-gates too (tk-i48ca). A gateless rig
  # used to express that as the empty string, which is why empty had to mean
  # ungated — but empty is ALSO what a hand-recovered anchor carries when it never
  # ran the formula's normalization, so the two were indistinguishable and a
  # recovered bead merged with no codex review. The formula now stamps the literal
  # `none` for a deliberate opt-out, so the reading here must honour it or a
  # gateless rig would hold forever on a gate named "none" that nothing can stamp.
  # Empty is deliberately still ungated HERE (#163/#182 unchanged — this script is
  # not the fail-closed point); check-set-heal.sh normalizes an empty check_set
  # upstream, on the pass that runs immediately before this one.
  hold_gate=$(printf '%s' "$row" | jq -r --arg head "$head_oid" '
    . as $row
    | (($row.checkset // "")
        | split(",")
        | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
        | map(select(length > 0))
        | map(select((. | ascii_downcase) as $g | $g != "none" and $g != "off"))) as $gates
    | (first( $gates[] | select( (($row.meta["check." + .]) // "") != ("green@" + $head) ) )) // ""
  ' 2>/dev/null)
  if [ -n "$hold_gate" ]; then
    have=$(printf '%s' "$row" | jq -r --arg k "check.$hold_gate" '.meta[$k] // "none"' 2>/dev/null)
    echo "merge-skill: PR#$num check '$hold_gate' not green at live head (have '$have', want 'green@$head_oid'); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # An open rework/review child holds the merge (docs/work-bead-state-machine.md:
  # an anchor lands only when ALL its children are closed). probe_holders resolves
  # that set from pr_number AND from the anchor's own dependency edges — see its
  # header for why one key alone is fail-open. --limit=0 (unbounded) on the
  # pr_number probe: the gate must see EVERY referencing bead, not a page of them,
  # or a child past the cap could let a PR merge while rework is still open.
  #
  # The merge_result exclusion is scoped to `_via == "pr_number"` holders ON
  # PURPOSE (tk-je0rk). It exists for ONE job: the pr_number probe sweeps up every
  # bead naming this PR, including a DUPLICATE gating anchor, and a second anchor
  # is the DUP_PRS guard's business above, not a child's. Applied to the whole
  # holder set it also deleted every dependency-edge holder that carries
  # merge_result — and an upstream PR or pre-open anchor filed as an explicit
  # merge-ordering `blocks` carries one BY DEFINITION. So the blocker vanished,
  # and a CLEAN downstream PR merged straight past the anchor it was ordered
  # behind: the same fail-OPEN shape on the very edge added to close it. A holder
  # reached by a dependency edge holds regardless of merge_result; only the
  # anchor's own id is excluded unconditionally, since nothing holds itself.
  #
  # The REPOSITORY exclusion is scoped to `_via == "pr_number"` for the same
  # reason and by the same rule (tk-9m8q4). A PR NUMBER names a different pull
  # request in every other repository this ledger spans, so the pr_number probe
  # is the one — and the only one — that can sweep up a stranger: a foreign
  # rework child carrying #<n> reads as rework in flight on OUR #<n> and holds a
  # ready PR indefinitely. That hold is released by certifying the holder's own
  # pr_url against this anchor's repository.
  #
  # A DEPENDENCY-EDGE holder is never repository-filtered. It was found by an
  # explicit edge in THIS ledger, so it holds by virtue of the edge, not by
  # naming a number — its pr_url is not the reason it is here, and an upstream
  # blocker legitimately names a DIFFERENT repository's PR (a cross-repo
  # merge-ordering block is precisely why an operator files one by hand).
  # Repository-filtering the dep set would delete that blocker and merge straight
  # past it: the identical fail-OPEN shape tk-je0rk hit by scoping merge_result
  # too widely, re-entered through the identity guard instead. So identity
  # narrows only what the number swept in.
  #
  # `?` remains the fail-closed wildcard (REPO_JQ): only a positive, parsed
  # disagreement clears a hold, so a legacy child with no pr_url keeps its veto.
  #
  # FAIL CLOSED on an unreadable probe. An empty result from a BROKEN query is
  # indistinguishable from "no children", and that read merges past open rework —
  # the same fail-open shape, arrived at through a tool error instead of a narrow
  # predicate. Counted as HELD, not skipped: this is the gate deciding not to
  # merge, not the anchor being unevaluable. A held merge is recoverable on the
  # next idle pass; a merge past open rework is not.
  # Reported on stdout with the other hold reasons, not stderr: the outcome is a
  # gate HOLD the patrol log must show alongside its peers, not a skipped anchor.
  if ! holders=$(probe_holders "$id" "$num"); then
    echo "merge-skill: PR#$num in-flight rework/review probe failed; merge held (anchor $id, retry next pass)"
    held=$((held + 1)); continue
  fi
  # The holder's STATUS rides along in the hold reason. It is no longer always
  # "open" — a `blocked` child holds too, and that is the one an operator has to
  # go unstick by hand rather than wait out, so the log must not call it open.
  # A merge_result-carrying holder also names it, because the two hold for
  # opposite operator actions: a rework child is something to go finish, while an
  # upstream gating anchor is something to WAIT for. Without the marker the log
  # sends an operator hunting for rework that does not exist.
  #
  # FAIL CLOSED on a filter that ERRORS, distinctly from one that finds nothing
  # (tk-qoyly). This jq indexes and downcases fields it did not validate, so any
  # element shape it cannot handle — a non-string status, a metadata value that
  # is not an object — aborts it. With stderr suppressed an abort is
  # byte-identical to "no holders": empty output, and the anchor sails on to
  # `gh pr merge`. That is the SAME fail-open class the dependency probes were
  # widened to close, arrived at one layer further down, so it gets the same
  # answer — hold and retry. `if !` (not `$?` after the assignment) because the
  # command substitution's status is the only place the abort is visible.
  if ! inflight=$(printf '%s' "$holders" | jq -r --arg anchor "$id" --arg live "$LIVE_STATUSES" --arg r "$arepo" "$REPO_JQ"'
    ($live | split(",")) as $live_statuses
    | [ .[]
        | select((.id // "") != "" and .id != $anchor)
        | select(((.status // "open") | ascii_downcase) as $s | $live_statuses | index($s))
        | ((.metadata.merge_result // "") | tostring) as $mr
        | ((._via // "pr_number")) as $via
        | select($via == "dep"
                 or ($mr == ""
                     and same_repo((((.metadata.pr_url // "") | tostring) | repo_of); $r)))
        | "\(.id) (\(.status // "open")\(if $mr == "" then "" else ", merge_result=" + $mr end))" ]
    | .[0] // empty' 2>/dev/null); then
    echo "merge-skill: PR#$num in-flight holder filter unreadable; merge held (anchor $id, retry next pass)"
    held=$((held + 1)); continue
  fi
  if [ -n "$inflight" ]; then
    echo "merge-skill: PR#$num has unclosed rework/review bead $inflight; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # CI + approval + base-current + no-conflict: GitHub's composite
  # mergeStateStatus. CLEAN is the only state that is mergeable with every
  # required check green and approved. BLOCKED (missing approval/required check),
  # BEHIND (base moved), UNSTABLE (a required check pending/failing), DIRTY
  # (conflict), UNKNOWN (GitHub still computing) all hold the merge and retry.
  if [ "$merge_state" != "CLEAN" ]; then
    echo "merge-skill: PR#$num not mergeable yet (mergeStateStatus='${merge_state:-unknown}', mergeable='${mergeable:-?}'); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- merge (single writer; IMMEDIATE, not --auto) -----------------------
  # --squash matches the repo's squash-merge convention (commit "(#N)" tail).
  # The full check-set validated above; this is the terminal check. A server-side
  # refusal (branch protection, a race) leaves the anchor OPEN to retry next pass.
  # PINNED like the read: the merge must land in the repository whose PR was just
  # validated, not in whatever repository gh considers current at this instant.
  MERGE_ERR=$(gh pr merge "$num" --repo "$ORIGIN_REPO_Q" --squash 2>&1); merge_rc=$?
  if [ "$merge_rc" -ne 0 ]; then
    echo "merge-skill: PR#$num merge attempt failed (rc=$merge_rc); merge held (anchor $id): $MERGE_ERR" >&2
    held=$((held + 1)); continue
  fi

  # --- record (synchronous; observer is the convergent backstop) ----------
  # Re-read the squash commit GitHub produced. Close FIRST for convergence: if
  # the close fails the anchor stays open + merge_result=pull_request and the
  # observer's merged-close path closes it next pass. The merged_sha/merge_result
  # write is best-effort AFTER the close — the close reason already names the
  # merge commit, so a failed metadata write loses no authority, only a field.
  merge_oid=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json mergeCommit 2>/dev/null | jq -r '.mergeCommit.oid // ""')
  short=$(printf '%.8s' "$merge_oid")
  if gc bd close "$id" --reason "Merged to $target at ${short:-merge}" >/dev/null 2>&1; then
    gc bd update "$id" \
      --set-metadata merge_result=merged \
      --set-metadata merged_sha="$merge_oid" \
      --unset-metadata rejection_reason >/dev/null 2>&1 || true
    merged=$((merged + 1))
    echo "merge-skill: merged + recorded $id — PR#$num squashed to $target at ${short:-?}"
  else
    echo "merge-skill: PR#$num MERGED but close failed for $id; observer records next pass" >&2
    skipped=$((skipped + 1))
  fi
done <<< "$ROWS"

echo "merge-skill: $merged merged, $held held, $skipped skipped"
exit 0
