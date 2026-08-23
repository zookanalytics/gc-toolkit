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
#   validate: the anchor's metadata is RE-READ first (the enumeration snapshot
#             predates the PR read, and the signoff path writes the anchor
#             concurrently), and then, against that fresh metadata: the PR is
#             claimed by exactly ONE open anchor (a second anchor
#             would let the weakest check_set decide the merge — tk-ynz4b),
#             the PR's live base == the anchor's merged_target (no retarget),
#             every gate the anchor declares in check_set is green AT THE LIVE
#             HEAD (per-gate marker check.<name>=green@<head>, so a stale approval
#             or a post-review commit re-gates instead of merging), no unclosed
#             rework/review child holds the anchor — resolved BOTH by every key a
#             bead names a PR with AND through the anchor's own dependency edges,
#             because a rework child carries the branch while the ANCHOR carries
#             PR identity (an unclosed child holds the merge — an anchor lands
#             only when ALL its children are closed; "unclosed" means any
#             NON-CLOSED status, and a ledger read that FAILS holds rather than
#             reading as "no child"),
#             the `approval` member is satisfied by a real EXTERNAL approving
#             review when the anchor requires it (see below), and GitHub reports
#             the PR mergeable (mergeStateStatus=CLEAN folds CI + base-current +
#             no-conflict — and approval too, but ONLY on a repo that requires
#             reviews; see the approval gate). UNSTABLE is decided on the
#             REQUIRED status-check set instead of on the composite, because it
#             means "a check is red and nothing required is blocking" — see the
#             mergeStateStatus gate (tk-zuoys).
#   merge:    the anchor is re-read ONE more time, immediately before `gh pr
#             merge`, and the ENTIRE anchor-local authorization set is recomputed
#             from it — status, merge_result, PR number, merge_hold, every
#             check.<gate> marker, signoff_dismissed, merged_target, pr_url and
#             branch. `--match-head-commit` binds the merge to the validated
#             COMMIT, but none of those fields move the head, so a mid-pass write
#             to any of them (a late dismissal arming the approval requirement, a
#             same-head retarget, an identity repair) would otherwise sail
#             straight through it. Any mismatch, or an unreadable re-read, HOLDS.
#   record:   close the anchor "Merged to <target> at <sha>" and stamp
#             merge_result=merged + merged_sha — synchronous, because the skill
#             that merged is the one that knows it merged. If the record half
#             dies after a successful merge, the observer's merged-close path
#             (reconcile-merged-prs.sh) is the convergent backstop next pass.
#             The close recovers from ONE refusal — the identity ENCODING
#             mismatch, where the assignee and the actor are the same principal
#             written two ways — by retrying with --force; every other refusal
#             falls through to the observer, which counts the consecutive
#             failures and escalates. See close_anchor() below.
#
# The `approval` check-set member (tk-5niup). CLEAN is documented as folding
# approval, and on a repo whose ruleset requires a review that is true: no
# approval => REVIEW_REQUIRED => BLOCKED. On a repo with NO review requirement
# and no CI, CLEAN is true with ZERO approving reviews — so "CLEAN implies
# approved" silently stops holding, and the merge lands unreviewed work. The
# `approval` member makes that check EXPLICIT and independent of CLEAN: it is
# satisfied only by an APPROVED latest-review from an account OTHER than the one
# this skill acts as (the city never approves its own PRs — approval is
# EXTERNAL/human, #185). It is required when EITHER
#   - the anchor names `approval` in check_set (an opt-in a rig on an
#     unprotected repo should declare), or
#   - the anchor carries `signoff_dismissed` — the city retracted its OWN
#     blocking review on this PR (template-fragments/polecat-non-impl-done.template.md,
#     the re-gate supersede step). Once we have removed a GitHub-side block
#     ourselves, CLEAN can no longer be read as approval evidence on this PR, so
#     the requirement is STICKY (presence, not head-match): a later head only
#     re-gates the markers, it never un-dismisses the review we dismissed.
#   - or the PR's review history shows a review AUTHORED BY THIS ACCOUNT whose
#     state is DISMISSED (tk-tmefn). This is the same fact as `signoff_dismissed`
#     — a GitHub-side block of OURS was retracted — read from the side that
#     cannot be bypassed. The bead marker records only the dismissals the CITY
#     performed in-band; an operator who clears the stale city review BY HAND on
#     github.com leaves no marker at all, and on an unprotected repo with
#     check_set=codex, check.codex green at the live head and no CI, the PR then
#     reads CLEAN with zero owed approvals and lands unapproved. The retraction
#     is what made it CLEAN either way, so the requirement must follow the
#     retraction, not the bookkeeping. GitHub only permits dismissing a
#     state-bearing review (APPROVED / CHANGES_REQUESTED) and the city never
#     approves (#185), so a DISMISSED review under this login can only be a
#     CHANGES_REQUESTED of ours that someone took back. Like the marker arm it is
#     STICKY: dismissal is permanent, and a later head re-gates the check.<name>
#     markers without un-dismissing anything.
# `approval` is evidenced by GitHub review state, not by a check.<name> marker,
# so the marker loop drops it the same way it drops the none/off sentinel. It is
# HEAD-BOUND exactly like check.<name>=green@<head>: the approving review must be
# attached to the PR's live head. An approval of an earlier head is evidence
# about a commit that is no longer what would merge — and where stale approvals
# stay effective, that is precisely the gap a dismissal-then-merge would slip
# through. So the evidence is read from the REST reviews history (which carries
# each verdict's `commit_id`), not from `latestReviews` (which does not).
#
# The VETO is UNCONDITIONAL, and is not part of the `approval` gate (tk-bdfww). A
# standing CHANGES_REQUESTED — any non-self reviewer whose LATEST verdict is one —
# holds every merge candidate whose review history was read, whether or not that
# candidate's check_set names `approval`, whether or not the anchor carries
# signoff_dismissed, and whether or not anything was dismissed on the PR. The two
# are different questions: `approval` asks whether a human said YES where GitHub
# does not require one, the veto asks whether a human said NO. Enforced only
# inside the armed approval branch (where it started), the ordinary anchor —
# check_set `codex`, marker green at the live head, CLEAN because the repo is
# unprotected — never reached it, so an open objection from a human reviewer did
# not hold the merge at all. Unlike the approval, the veto is NOT head-bound: an
# objection stands until its author supersedes it with a later verdict or it is
# dismissed, and pushing a new commit over it resolves nothing.
#
# TRUSTED approver, not merely a non-self one (tk-pkgym). "Any login that is not
# ours" is not an approval policy: on a public repo ANY account can submit an
# APPROVED review, and this gate matters precisely where GitHub enforces nothing
# server-side (an unprotected repo — the case the `approval` member exists for),
# so a drive-by approval from a read-only collaborator, an unrelated bot, or a
# throwaway account would land the PR. An approving review therefore counts only
# from an account that satisfies the trusted-approver policy:
#   - MERGE_TRUSTED_APPROVERS (comma-separated logins), when set, IS the policy:
#     an explicit operator allowlist, evaluated with no API call.
#   - otherwise the approver must hold write-level permission on the repo
#     (admin/maintain/write, read from
#     repos/{owner}/{repo}/collaborators/<login>/permission).
# Anything else — including a permission probe that cannot be READ — is untrusted
# and HOLDS the merge, fail-closed like every other gate here (an unreadable
# probe is indistinguishable from "no access", and guessing merges unreviewed
# work). The hold names both remedies, so an operator whose token cannot read
# collaborator permissions can set the allowlist instead of being stuck.
#
# Residual race, accepted and documented rather than papered over: every gate here
# is validated CLIENT-side and the merge is then issued, so review state can still
# change AT THE SAME HEAD inside that window (an approval dismissed, a
# CHANGES_REQUESTED posted) and this pass would still merge. --match-head-commit
# binds the COMMIT half — a push cannot slip an unvalidated head into the squash —
# but nothing binds the review half; only server-side branch protection is atomic
# with the merge. A rig that cannot accept the window should require reviews in the
# repo ruleset, so GitHub itself refuses. See docs/work-bead-state-machine.md.
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

# The trusted-approver policy (see the header). An operator allowlist, when set,
# IS the policy; otherwise trust is write-level repo permission. Empty/unset =
# permission-probe policy, which is the default on every rig that has not
# declared an allowlist.
TRUSTED_APPROVERS="${MERGE_TRUSTED_APPROVERS:-}"

# Does this login satisfy the trusted-approver policy? 0 = trusted, 1 = not (and
# 1 covers "cannot tell", which is the fail-closed answer: an approval we cannot
# attribute to a trusted account must not land a PR).
approver_trusted() {
  local login="$1" perm rc
  [ -n "$login" ] || return 1
  if [ -n "$TRUSTED_APPROVERS" ]; then
    # Allowlist mode: the operator named the accounts, so no probe — a listed
    # account need not even be a collaborator (e.g. an org reviewer acting
    # through a team). Comma-split with surrounding space ignored, whole-token
    # match, so a spaced list behaves like the comma lists check_set uses.
    #
    # Matched in-shell rather than through a `... | grep -qx` pipeline, because
    # `set -o pipefail` is on (line 110) and `grep -q` exits at the FIRST match:
    # that closes the pipe under whatever is still writing, so an upstream filter
    # can take SIGPIPE and make the whole pipeline report 141 — a TRUSTED approver
    # read back as untrusted, on nothing but how long the allowlist happens to be.
    # Whitespace is stripped outright instead of per-token trimmed: a GitHub login
    # cannot contain any, so all of it is padding. `$login` is non-empty (checked
    # above), so the comma-delimited containment test cannot match an empty slot
    # in a list like "a,,b".
    case ",$(printf '%s' "$TRUSTED_APPROVERS" | tr -d '[:space:]')," in
      *",$login,"*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  # Permission mode: ask GitHub what this account may actually DO to the repo.
  # author_association is deliberately NOT used for this — COLLABORATOR covers a
  # read-only collaborator, so it would trust an account with no write access.
  # A failed call (404 for a non-collaborator, 403 for a token that cannot read
  # collaborator permissions, a rate limit) returns 1: unreadable is untrusted.
  #
  # PINNED to the origin repository, like every other GitHub read here and unlike
  # the `{owner}/{repo}` placeholder this used to carry (review tk-5knqi finding
  # #1). That placeholder is resolved from gh's AMBIENT context — `gh repo
  # set-default`, $GH_REPO, $GH_HOST, the cwd — which is not this checkout's
  # origin, and the question being asked is "may this account write to the
  # repository we are about to merge in". Answered against a repository the
  # operator happens to be pointing at, a login with write access THERE and none
  # here satisfies the approval gate for a PR it cannot touch: the merge is then
  # authorized by a permission that does not exist where it is spent.
  perm=$(gh_api_origin "repos/$ORIGIN_REPO/collaborators/$login/permission" \
           --jq '.permission' 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] || return 1
  case "$perm" in
    admin|maintain|write) return 0 ;;
    *) return 1 ;;
  esac
}

# --- guarded ledger reads (KEEP IN SYNC with reconcile-merged-prs.sh) --------
# Which statuses can still OWN a PR? Every non-closed one. The in-flight-child
# gate below asks "does any rework/review bead still owe work on this PR", and a
# child parked in `blocked` (waiting on a dependency), `deferred`, `hooked` (sitting
# on an agent's hook) or `pinned` owes exactly as much as one in `open` — it is
# simply not being worked this minute. Read as open,in_progress alone, every one
# of those is INVISIBLE to the gate and the PR merges past the work it represents.
# That was the live tk-lgjvg shape: the rework child was `blocked` + routed to a
# human while its anchor merged straight past it.
# Identical to reconcile-merged-prs.sh's LIVE_STATUSES; re-derive BOTH if
# `bd statuses` ever grows a new non-closed status.
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

# Which metadata keys name a pull request? `pr_number` is the key the refinery
# stamps, but it is not the only one a live bead uses: the fork-sync flow records
# `fork_pr` / `fork_pr_url` and no pr_number at all. A gate keyed on pr_number
# alone cannot see such a bead holding this PR. Same def, same three keys, as
# reconcile-merged-prs.sh — a bead that reconciler can see holding a PR must be
# visible to this merge gate too, or the two disagree about who owns a PR and the
# quieter answer is the one that merges.
PR_NUM_JQ='
def pr_nums:
  ( [ (.metadata.pr_number // empty), (.metadata.fork_pr // empty) ] | map(tostring) )
  + ( (.metadata.fork_pr_url // "") | tostring | [ scan("/pull/([0-9]+)") | .[0] ] )
  | map(select(test("^[0-9]+$"))) | unique;
'

# The SAME key set, asked of the anchor about ITSELF rather than about other beads,
# and restricted to numbers that could name a PR in THIS repository (tk-tbacg #2).
#
# The anchor's own identity used to be `metadata.pr_number` alone, while the holder
# probe above and reconcile-merged-prs.sh's ownership set both read every key. A live
# `merge_result=pull_request` anchor keyed only by fork_pr/fork_pr_url was therefore
# UNMERGEABLE here (empty number -> skipped every pass) and SILENT there (reconcile
# counts it owned, so it is never reported anchorless): a PR that nothing lands and
# nothing reports. Reading the same keys is what makes the two passes agree about
# which beads own which PR.
#
# `in-repo` is the reconcile rule (`pr_refs | in_repo`): a bare number names no
# repository, so it is kept (the `?` fail-closed wildcard); a fork_pr_url that
# positively names ANOTHER repository is dropped, because that number is about
# somebody else's pull request and this pass reads and merges only in origin.
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

# One guarded ledger read -> the matching beads as a JSON array on stdout.
# --limit=0 so a probe sees the WHOLE set, not a page of it: a child past the cap
# could let a PR merge while its rework is still open.
#
# Returns NON-ZERO on a failed read, which every caller MUST treat as "I cannot
# tell" and never as "nobody else claims this PR".
#
# Delegates to bead_read_array rather than guarding itself, so the multi-key PR
# query below inherits the SAME guards the dependency probes get: the per-probe
# wall-clock bound, and the three-layer payload check (document count, top-level
# shape, per-element shape). Two readers with two different notions of "readable"
# is how one probe ends up trusting a payload the other would have rejected —
# and the weaker one decides the merge. The failure they both answer is silence:
# `gc ... --json` reports its own failures as a non-empty JSON *object*
# (`{"error": ...}`, exit 1), which survives an emptiness test, projects to zero
# rows, and so fails OPEN — the one direction that merges past owed work.
pr_bead_read() {
  bead_read_array gc bd list "$@" --limit=0 --json
}

# The anchor's LIVE metadata, guarded, as `{status, meta}` — or EMPTY, which every
# caller must read as unreadable and never as an all-default row.
#
# One reader for BOTH re-reads (the pre-validation one and the terminal one
# immediately before `gh pr merge`, tk-tbacg #1). Two readers would be two notions
# of "readable": control characters in bead notes can make `--json` unparseable, and
# `select(...)` rather than `// {}` is what keeps a missing row or missing metadata
# EMPTY instead of an all-default row that validates. A terminal check that read the
# bead more loosely than the earlier one would be a weaker gate wearing the same name.
anchor_row() { # <anchor-id>
  gc bd show "$1" --json 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037' \
    | jq -c '.[0] | select(. != null) | select(.metadata != null)
             | {status: (.status // ""), meta: .metadata}' 2>/dev/null
}

# Is metadata.merge_hold truthy? Operators set `true`; unset/empty/false/0/null do
# not hold. One definition, asked by the validate gate and again terminally.
merge_hold_truthy() { # <merge_hold value>
  case "${1:-}" in
    ""|false|False|FALSE|0|null) return 1 ;;
    *) return 0 ;;
  esac
}

# --- ONE PR, ONE GATE: coalescing the anchors that claim the same pull request.
#
# tk-ynz4b holds a PR claimed by more than one open gating anchor, because the
# loop validates each anchor INDEPENDENTLY and the PR would otherwise be gated by
# its WEAKEST anchor. The hold was written to release "on a later pass once
# exactly one open anchor remains (close/demote the duplicate)" — but NO pass
# performs that demotion, and the mechanism that used to converge these pairs was
# reconcile-merged-prs.sh closing BOTH anchors ON MERGE. The guard gates the very
# merge that ran it, so the pair can only be resolved by hand (tk-3sdfq).
#
# The pairs still occur. Two pre_open_gate anchors on one branch become two
# pull_request anchors BY DESIGN: pre-open-resolve.sh's "already has PR#N; flipped
# to pull_request" arm flips the sibling of whichever anchor opened the PR, so the
# sibling stays visible to the merge and observer passes. That flip is correct —
# and it lands the pair straight into the permanent hold. The patrol's
# one-anchor-per-pr-resolve arm (mol-refinery-patrol.toml) is what should stop the
# second pre_open_gate anchor from being minted in the first place; when it does
# not — a rig checkout on an older pack, an out-of-band write — the pair is real,
# and today nothing can retire it. Live at filing: gascity gc-ddvrx + gc-2s6oz on
# PR#109, codex green on the rework anchor and unable to land.
#
# So this resolves the pair instead of holding it: the anchors of one PR are
# treated as ONE gate whose check-set is the UNION of theirs, satisfied by the
# markers of all of them pooled. Union is what preserves tk-ynz4b's actual intent.
# The bypass it prevents is a WEAKER gate deciding the merge, and a union is
# stronger than either member: a gateless duplicate adds no gate to skip past, and
# the real anchor's `codex` still has to be green. Pooling the MARKERS is sound
# for the same reason the markers are head-pinned at all — `check.<g>=green@<oid>`
# is a statement about the COMMIT ("gate g passed at oid"), not about the bead
# holding it, and every anchor here is parked on the same PR whose live head is
# that oid. A sibling's green@<live head> is evidence about the commit this merge
# would land, whichever bead recorded it.
#
# Coalescing is EARNED, not assumed. Every sibling is re-read live and must still
# be the thing this pass thinks it is — open, parked on a published PR, claiming
# exactly this PULL REQUEST (the same number, and the same url when it records
# one), describing this branch and this target — and must declare a NON-EMPTY
# check_set. Empty is refused deliberately: at the gate site below, an empty
# check_set means "no gates" because check-set-heal.sh normalizes it on the pass
# immediately before this one, but a duplicate minted or reclassified MID-PASS
# has not been through that pass, so an empty set on a
# sibling is UNVALIDATED, not ungated — reading it as "no gates" would union in
# nothing and hand the PR to the weakest anchor, which is precisely tk-ynz4b.
# Anything uncertifiable falls back to the tk-ynz4b hold with the reason named.
#
# Sets, on success: COALESCE_ROW (the anchor row with pooled check.* markers),
# COALESCE_CHECKSET (the unioned check_set), COALESCE_DISMISSED (every
# signoff_dismissed on the PR, joined — a review the city retracted arms the
# external-approval requirement no matter which anchor recorded it).
# On failure: COALESCE_REASON, and returns non-zero.
COALESCE_ROW=""; COALESCE_CHECKSET=""; COALESCE_DISMISSED=""; COALESCE_REASON=""
coalesce_gate() { # <self-id> <self-row> <pr-num> <repo-q> <head-oid> <head-ref> <base> <live-url> <sibling-ids>
  local self="$1" selfrow="$2" pnum="$3" prepo="$4" head="$5" ref="$6" pbase="$7" plive="$8" sibs="$9"
  local sid srow sstatus sresult spr sprurl scs shold sbranch starget sdis pooled
  COALESCE_ROW=""; COALESCE_CHECKSET=""; COALESCE_DISMISSED=""; COALESCE_REASON=""
  pooled="$selfrow"
  COALESCE_CHECKSET=$(printf '%s' "$selfrow" | jq -r '.meta.check_set // ""' 2>/dev/null)
  COALESCE_DISMISSED=$(printf '%s' "$selfrow" | jq -r '.meta.signoff_dismissed // ""' 2>/dev/null)
  for sid in $sibs; do
    [ -n "$sid" ] || continue
    [ "$sid" != "$self" ] || continue
    # LIVE, like every other fact this merge is decided on. The enumeration
    # snapshot is older than the PR read, and a sibling anchor is exactly the bead
    # a concurrent signoff is writing.
    srow=$(anchor_row "$sid")
    if [ -z "$srow" ]; then
      COALESCE_REASON="sibling anchor $sid could not be re-read; an unreadable anchor cannot prove what it gates"
      return 1
    fi
    sstatus=$(printf '%s' "$srow" | jq -r '.status | ascii_downcase' 2>/dev/null)
    sresult=$(printf '%s' "$srow" | jq -r '.meta.merge_result // ""' 2>/dev/null)
    spr=$(printf '%s' "$srow" | jq -r --arg o "$prepo" "$PR_SELF_JQ"'
      {metadata: .meta} | (pr_nums_here($o)) as $ns
      | if ($ns | length) == 1 then $ns[0] else "" end' 2>/dev/null)
    if [ "$sstatus" != "open" ] || [ "$sresult" != "pull_request" ] || [ "$spr" != "$pnum" ]; then
      COALESCE_REASON="sibling anchor $sid no longer gates PR#$pnum (status='${sstatus:-unknown}' merge_result='${sresult:-unset}' claims '${spr:-none}') — the ledger changed mid-pass"
      return 1
    fi
    # Identity, at FULL PULL-REQUEST granularity — the same question the self-anchor
    # check asks of its own recorded pr_url, and it has to be the same question
    # (review tk-mnj3f). A sibling is not merely counted here: its check.* markers
    # are POOLED into the gate that decides this merge, and once the PR lands
    # reconcile-merged-prs.sh closes it as an anchor of that PR. Compared at
    # REPOSITORY granularity, a sibling recording `<this repo>/pull/<OTHER number>`
    # certified — same repository, so the check waved it through — and a bead that
    # names a DIFFERENT pull request got to contribute a green marker to this one,
    # then be skipped as self-checked when the loop reached it. The self check HOLDS
    # exactly that row ("the bead and the PR name different pull requests"), and it
    # holds because the ambiguity is unresolvable — one of the two PR identities is
    # wrong and this script cannot choose — not because self is special. A weaker
    # rule for siblings is the same bypass tk-ynz4b is about, reached THROUGH the
    # coalescing instead of around it.
    #
    # EMPTY still coalesces, on the same fail-closed-wildcard reasoning as the
    # repository rule it replaces: a pr_number-only anchor (check-set-heal.sh's
    # recovery shape, before the certified url is backfilled) records nothing to
    # disagree with, and is governed by the number, status and branch checks
    # instead. Only a POSITIVE disagreement disqualifies — but "positive" now means
    # "not this pull request" rather than "not this repository", which subsumes the
    # foreign-repository case: another repository's url cannot equal this one's.
    # Compared through canon_pr_url on both sides, like every other url comparison
    # here, so a cosmetic difference is never read as a different pull request.
    sprurl=$(printf '%s' "$srow" | jq -r '.meta.pr_url // ""' 2>/dev/null)
    if [ -n "$sprurl" ] && [ "$(canon_pr_url "$sprurl")" != "$plive" ]; then
      COALESCE_REASON="sibling anchor $sid records pr_url '$sprurl', which is not PR#$pnum ('${plive:-unreadable}') — the bead and the pull request name different work, so its gates cannot be pooled into this merge"
      return 1
    fi
    scs=$(printf '%s' "$srow" | jq -r '(.meta.check_set // "") | gsub("[[:space:],]";"")' 2>/dev/null)
    if [ -z "$scs" ]; then
      COALESCE_REASON="sibling anchor $sid declares NO check_set, which is UNVALIDATED rather than ungated here (check-set-heal.sh normalizes an empty set on the pass before this one, and a duplicate minted mid-pass has not been through it) — its gates cannot be unioned"
      return 1
    fi
    shold=$(printf '%s' "$srow" | jq -r '.meta.merge_hold // ""' 2>/dev/null)
    if merge_hold_truthy "$shold"; then
      COALESCE_REASON="sibling anchor $sid carries merge_hold=$shold (operator gate) — a hold on ANY anchor of this PR holds the PR"
      return 1
    fi
    sbranch=$(printf '%s' "$srow" | jq -r '.meta.branch // ""' 2>/dev/null)
    if [ -n "$sbranch" ] && [ -n "$ref" ] && [ "$sbranch" != "$ref" ]; then
      COALESCE_REASON="sibling anchor $sid records branch '$sbranch' but PR#$pnum is opened from '$ref' — the two beads describe different work"
      return 1
    fi
    starget=$(printf '%s' "$srow" | jq -r '.meta.merged_target // ""' 2>/dev/null)
    if [ -n "$starget" ] && [ -n "$pbase" ] && [ "$starget" != "$pbase" ]; then
      COALESCE_REASON="sibling anchor $sid records merged_target '$starget' but PR#$pnum lands on '$pbase'"
      return 1
    fi
    # Union the declared gates; pool ONLY the markers that are green at THIS head.
    # A sibling's stale or absent marker must never overwrite a live green one, so
    # the pooling is additive and head-conditioned rather than an object merge.
    COALESCE_CHECKSET="$COALESCE_CHECKSET,$(printf '%s' "$srow" | jq -r '.meta.check_set // ""' 2>/dev/null)"
    pooled=$(printf '%s\n%s' "$pooled" "$srow" | jq -sc --arg head "$head" '
      .[0] as $acc | .[1].meta as $sib
      | $acc
      | .meta = reduce ($sib | to_entries[]
                        | select((.key | startswith("check."))
                                 and ((.value | tostring) == ("green@" + $head))))
                  as $e (.meta; .[$e.key] = $e.value)' 2>/dev/null)
    if [ -z "$pooled" ]; then
      COALESCE_REASON="the pooled check-set markers could not be built from sibling anchor $sid"
      return 1
    fi
    sdis=$(printf '%s' "$srow" | jq -r '.meta.signoff_dismissed // ""' 2>/dev/null)
    [ -z "$sdis" ] || COALESCE_DISMISSED="${COALESCE_DISMISSED:+$COALESCE_DISMISSED,}$sdis"
  done
  COALESCE_ROW="$pooled"
  return 0
}

# --- closing an anchor past the identity-ENCODING refusal. --------------------
# `bd close` is assignee-gated: it refuses when the bead's assignee string differs
# from the ACTOR string it derives for the calling process. Those two routinely
# carry the SAME principal in two renderings — work is routed under the canonical
# dotted mailbox identity ($GC_AGENT, `<rig>/<pack>.<role>`) while the actor comes
# from $GC_SESSION_NAME (`<rig>--<pack>__<role>`) — so a refinery closing an anchor
# it HOLDS is refused, in bd's own words:
#
#   cannot close sl-jcr4: assignee is "signal-loom/gc-toolkit.refinery",
#   actor is "signal-loom--gc-toolkit__refinery"; reclaim or use --force to override
#
# This script closes the anchor IT JUST MERGED, so hitting the wedge here means the
# PR has landed and the record does not say so — the observer then inherits a merged
# PR whose anchor it also cannot close (signal-loom PR#518: ~40 consecutive failing
# passes before a human forced it). Retry ONCE with --force, and ONLY when the two
# strings are provably one principal.
#
# Deliberately NOT a blanket --force: the same flag also overrides refusals that are
# REAL — a genuinely foreign assignee, and open child issues ("close children first
# or use --force to override") — so forcing on failure alone would paper over
# exactly what the gate exists for. Every other refusal falls through to the
# existing "close failed; observer records next pass" path, which is the correct
# outcome: the observer retries it, counts the consecutive failures, and escalates.
#
# Byte-for-byte the same pair of helpers as reconcile-merged-prs.sh; these scripts
# are standalone by design, so they are duplicated rather than sourced. Keep them
# in step.

# `<rig>/<pack>.<role>` and `<rig>--<pack>__<role>` are one principal in two
# encodings. Normalize toward the DASHED form: `/` and `.` are single unambiguous
# characters, so dotted -> dashed is a total mapping, whereas dashed -> dotted would
# have to guess whether a `--` inside a name is a separator or part of the name.
canon_principal() { printf '%s' "${1:-}" | sed -e 's#/#--#g' -e 's#\.#__#g'; }

# Is this close refusal the identity-ENCODING artifact — one principal, two
# renderings? Non-zero for every OTHER refusal (a foreign assignee, an open-children
# hold, a ledger error), which is what keeps the retry from degenerating into a
# blanket --force. Comparing the message's OWN two strings is also the stronger
# ownership check: it asks bd what it actually compared, instead of trusting this
# process's $GC_AGENT to describe it.
close_refusal_is_identity() { # <close output>
  local msg="${1:-}" a b
  # bd's format string, verbatim:
  #   cannot close %s: assignee is %q, actor is %q; reclaim or use --force to override
  # TWO extractions rather than one emitting a \t: BSD sed (macOS, where this pack
  # also runs) does not expand \t in a replacement, so a tab-joined pair would come
  # back as a literal "t" and split wrong.
  a=$(printf '%s' "$msg" | sed -n 's/.*cannot close [^:]*: assignee is "\([^"]*\)", actor is "\([^"]*\)".*/\1/p' | head -1)
  b=$(printf '%s' "$msg" | sed -n 's/.*cannot close [^:]*: assignee is "\([^"]*\)", actor is "\([^"]*\)".*/\2/p' | head -1)
  [ -n "$a" ] && [ -n "$b" ] || return 1
  [ "$(canon_principal "$a")" = "$(canon_principal "$b")" ]
}

# Close <id> with <reason>, recovering from that one refusal. Returns 0 only when
# the bead is actually CLOSED. Sets CLOSE_FORCED=1 when the override fired, so the
# caller counts it and the merge log names it — an override that HAPPENED must
# never be indistinguishable from a clean close.
close_anchor() { # <id> <reason>
  local id="${1:-}" reason="${2:-}" out
  CLOSE_FORCED=""
  out=$(gc bd close "$id" --reason "$reason" 2>&1) && return 0
  # ECHO THE REFUSAL. This return used to drop $out on the floor, and the caller
  # logs only a COUNT ("close failed ... N consecutive pass(es)"). That is how one
  # outage ran 8+ hours and ~80 failed closes without recording WHY even once, and
  # escalated to the mayor twice carrying a count with no cause (tk-5kfhl). The
  # identity path below already proves the value of echoing it; the path that
  # deliberately does NOT recover is the one that owes a human the reason.
  close_refusal_is_identity "$out" || {
    echo "merge-skill: $id close REFUSED, and not on an identity-encoding mismatch (no override applies): $out" >&2
    return 1
  }
  echo "merge-skill: $id close refused on an identity-ENCODING mismatch (assignee and actor name the same principal in different renderings); retrying once with --force" >&2
  out=$(gc bd close "$id" --reason "$reason" --force 2>&1) || {
    echo "merge-skill: $id --force retry ALSO failed after the identity-encoding refusal: $out" >&2
    return 1
  }
  CLOSE_FORCED=1
  echo "merge-skill: $id closed with --force (identity-encoding mismatch overridden)" >&2
  return 0
}

# The first check-set gate NOT green at <head>, or empty when every gate is green.
# `$2` is the anchor row (`{status, meta}`), `$1` the declared check_set.
#
# NON-ZERO when the markers could not be read at all, which callers MUST hold on.
# An unreadable row and an all-green one are the same empty string on stdout, and
# reading the first as the second is a fail-OPEN: every declared gate would be
# treated as satisfied by a jq that never ran. `jq -e` is what separates them — no
# valid output is a non-zero exit — so "I could not check the gates" can never be
# mistaken for "the gates are green".
#
# The `none`/`off` sentinel and `approval` are dropped for the reasons stated at the
# gate site: the first is a deliberate no-gates opt-out, the second is satisfied by
# GitHub's review state rather than by a check.<name> marker, so leaving either in
# would hold the anchor forever on a marker nothing can ever stamp.
checkset_hold_gate() { # <check_set> <anchor-row-json> <head-oid>
  printf '%s' "${2:-}" | jq -re --arg cs "${1:-}" --arg head "${3:-}" '
    (.meta // {}) as $meta
    | (($cs // "")
        | split(",")
        | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
        | map(select(length > 0))
        | map(select((. | ascii_downcase) as $g | $g != "none" and $g != "off" and $g != "approval"))) as $gates
    | (first( $gates[] | select( (($meta["check." + .]) // "") != ("green@" + $head) ) )) // ""
  ' 2>/dev/null
}

# Every bead in <statuses> that names PR #<num> under ANY key pr_nums knows, as
# ONE id-deduped JSON array. Three KEYED reads unioned rather than one unkeyed
# sweep: --metadata-field filters server-side, and the URL arm is bounded by
# --has-metadata-key fork_pr_url (a handful of beads city-wide).
#
# Fails closed AS A UNIT: if any one read is unreadable the whole query returns
# non-zero. A partial answer is worse than none here, because the callers read
# "no rows" as "nothing else holds this PR" and merge.
pr_bead_query() {
  local statuses="$1" num="$2" acc part
  acc=$(pr_bead_read --metadata-field "pr_number=$num" --status "$statuses") || return 1
  part=$(pr_bead_read --metadata-field "fork_pr=$num" --status "$statuses") || return 1
  acc=$(printf '%s\n%s' "$acc" "$part" | jq -sc 'add' 2>/dev/null) || return 1
  part=$(pr_bead_read --has-metadata-key fork_pr_url --status "$statuses") || return 1
  part=$(printf '%s' "$part" \
    | jq -c --arg n "$num" "$PR_NUM_JQ"'[ .[] | select(pr_nums | index($n)) ]' 2>/dev/null) || return 1
  printf '%s\n%s' "$acc" "$part" | jq -sc 'add | unique_by(.id)' 2>/dev/null
}

# Every bead that HOLDS the merge of anchor $1, as one JSON array. $2 is the
# PR-naming set already read by pr_bead_query (the loop needs it for the
# duplicate-anchor gate too, so it is read ONCE per anchor and passed in).
# Returns non-zero if either dependency probe is unreadable, so the caller can
# fail closed.
#
# Three sources, because no single one sees every holder:
#
#   1. the PR-naming set — beads naming this PR in their OWN metadata, under ANY
#      key pr_nums knows (pr_number, fork_pr, fork_pr_url). Keyed on pr_number
#      alone this missed the fork-sync flow's beads entirely, which is the gap
#      tk-lgjvg left open and named.
#   2. dep up / parent-child — the anchor's CHILDREN. A rework child filed by the
#      signoff gate carries branch + source_review_bead but NOT pr_number: the
#      ANCHOR is the bead that owns PR identity, and the PRE-OPEN rework arm
#      cannot stamp a number at all because no PR exists yet when it files. Keyed
#      on PR-naming metadata alone such a child is invisible and the gate PASSES —
#      the fail-OPEN defect tk-lgjvg closed (live case: anchor tk-h9pq5 / PR#233
#      merged past its open rework child tk-t88hg).
#   3. dep down / blocks — the beads that BLOCK the anchor. That is precisely how
#      a signoff gate attaches ("the gate's bead BLOCKS the convoy",
#      docs/work-bead-state-machine.md) and how an operator files an explicit
#      merge-ordering block.
#
# `--direction` is read from the ANCHOR's end: `up` returns the beads that depend
# ON it — its parent-child CHILDREN — and `down` the beads it depends on, its own
# PARENT and its `blocks` blockers. Confirm that on an anchor which HAS an open
# child before concluding either leg is broken: probed against one whose children
# are all closed, or which has none yet, `up -t parent-child` correctly returns
# `[]`, and reading that as "this leg never returns anything" has already produced
# one spurious fail-OPEN report (tk-8329m). `gc bd show` is the authority on which
# edges exist; dependency_count and the bare `dep list` disagree with it.
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
  local anchor="$1" by_pr="$2" children blockers
  children=$(bead_read_array gc bd dep list "$anchor" \
    --direction=up -t parent-child --json) || return 1
  blockers=$(bead_read_array gc bd dep list "$anchor" \
    --direction=down -t blocks --json) || return 1
  # The three payloads are read POSITIONALLY, so the slurped stream must be
  # exactly three documents. bead_read_array already guarantees one canonical
  # document each (tk-wkrcy) — including for $by_pr, which pr_bead_query built
  # out of it — and this restates that as a hard assertion at the point the
  # positions are actually consumed, so any future drift is a fail-CLOSED error
  # instead of a silent slot shift that drops a probe off the end.
  #
  # group_by(.id) rather than unique_by(.id): dedup must MERGE provenance, not
  # pick whichever copy sorted first. A bead reachable both ways is a dependency
  # holder — take the union, so a dep-linked bead that also names the PR is
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

# And the HOST half, split off the same qualified name so the two can never name
# different places. `gh api` takes no `[HOST/]OWNER/REPO` — a REST path carries
# `<owner>/<repo>` only — so the host is a SEPARATE flag, and omitting it hands
# that half of the identity back to $GH_HOST (`gh help environment`), which is
# the very source `--repo` is pinned to keep out. `<owner>/<repo>` names one
# repository PER HOST: the same path under a drifted GH_HOST reads another
# host's identically-named repository, whose PR #<n> exists too.
ORIGIN_HOST="${ORIGIN_REPO_Q%%/*}"

# Every `gh api` call in this script goes through here, so no REST read can be
# re-hosted underneath the `--repo` pins the PR reads already carry (review
# tk-5knqi finding #1). The caller supplies the `repos/$ORIGIN_REPO/...` path;
# this supplies the host. Mirrors pre-open-resolve.sh's `gh api --hostname
# "$ORIGIN_HOST" "repos/$ORIGIN_REPO/..."` calls, which is the reference shape.
gh_api_origin() { gh api --hostname "$ORIGIN_HOST" "$@"; }

# The account this skill acts as. Used ONLY to exclude our own reviews from the
# approval gate below — the city posts COMMENT signoffs and never approves, so an
# APPROVED review under this login would be a self-approval and must not count.
# Resolved once per pass. If it cannot be resolved, the approval gate holds
# rather than counting an unattributable approval (fail-closed).
#
# Resolved HERE rather than at the top of the pass because it is host-scoped:
# `gh api user` answers for whatever host is in play, and an account name is only
# meaningful against the host whose reviews it is compared with. Pinned to the
# origin host, the exclusion asks about the same account GitHub will attribute
# our reviews to; unpinned under a drifted $GH_HOST it names a DIFFERENT account,
# and an exclusion keyed on the wrong name stops excluding what it exists to
# exclude.
SELF_LOGIN=$(gh_api_origin user -q .login 2>/dev/null)

# The repository a pull-request URL names, host-qualified — one definition for
# both places identity is compared. Mirrors check-set-heal.sh's url_repo_q.
url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}

# A pull-request URL reduced to its canonical `<...>/pull/<n>` form: whitespace
# stripped, a `/files` or `#discussion_r...` suffix and any trailing slash
# trimmed. ONE definition for every URL comparison here — the live PR url, the
# anchor's recorded pr_url at validation, and the same field re-read immediately
# before the merge — so a cosmetic difference is never read as a different pull
# request, and the three sites cannot drift apart. Mirrors the identical
# normalization reconcile-merged-prs.sh applies on both sides of its comparison.
canon_pr_url() {
  printf '%s' "${1:-}" \
    | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##'
}

# --- the REQUIRED status-check set protecting a branch (tk-zuoys) ------------
# Which status checks actually GATE a merge into <branch>. Read for the UNSTABLE
# arm of the mergeStateStatus gate below, where the whole question is whether the
# red checks are gating or merely advisory.
#
# Answers THREE ways — known-with-contexts / known-empty / unknown — and the
# caller HOLDS on unknown. A two-valued answer would have to render an unreadable
# protection API as "nothing required", which is the one reading that can merge
# past a red REQUIRED check.
#
# TWO sources, unioned, because a repository can gate a branch either way and the
# two are independently configurable:
#
#   repos/<repo>/branches/<branch>          classic branch protection, via the
#     .protection.required_status_checks    BRANCH object rather than
#     .contexts + .checks[].context         branches/<branch>/protection.
#
#     Deliberately NOT the protection endpoint, which is the obvious one and is
#     unusable here: "Get branch protection" requires ADMIN on the repository,
#     and the account this skill acts as holds write, not admin (verified against
#     both rigs — repos/<repo>.permissions.admin is false). It answers 404 for a
#     non-admin token exactly as it does for an unprotected branch, so its reply
#     cannot distinguish "nothing is required" from "you may not ask" — and
#     reading that 404 as "nothing required" is precisely the fail-open this
#     helper exists to avoid. The branch object carries the same required_status_
#     checks summary and needs only read access.
#
#   repos/<repo>/rules/branches/<branch>    RULESETS — the modern mechanism, and
#     .[] | required_status_checks rule     what both rigs actually use today
#     .parameters.required_status_checks[]  (gc-toolkit's main is governed by a
#     .context                              ruleset; classic protection is off).
#
#     Also read-access only. A repository with no rulesets answers `[]`, which is
#     a definite empty, not a failure.
#
# EITHER read failing makes the answer unknown. A partial union is not a smaller
# answer, it is a WRONG one: the source that failed is exactly where the required
# context we would then fail to evaluate would have been.
#
# Cached per branch for the pass. Every anchor in a normal pass targets the same
# base, and the answer cannot change usefully within one sweep.
REQUIRED_CACHE=""
REQ_STATE=""
REQ_CONTEXTS=""
REQ_SOURCE=""
required_contexts_for() { # <branch>  -> REQ_STATE / REQ_CONTEXTS / REQ_SOURCE
  local branch="$1" cached rules_raw rules_rc branch_raw branch_rc from_rules from_branch
  REQ_STATE=""; REQ_CONTEXTS=""; REQ_SOURCE=""
  if [ -z "$branch" ]; then
    REQ_STATE="unknown"; REQ_SOURCE="no base branch to ask about"
    return 0
  fi

  cached=$(printf '%s' "$REQUIRED_CACHE" | awk -F'\t' -v b="$branch" '$1 == b { print; exit }')
  if [ -n "$cached" ]; then
    REQ_STATE=$(printf '%s' "$cached" | cut -f2)
    REQ_SOURCE=$(printf '%s' "$cached" | cut -f3)
    # Contexts are cached comma-joined (the cache line is tab-delimited) and
    # handed back newline-delimited, the shape every caller reads.
    REQ_CONTEXTS=$(printf '%s' "$cached" | cut -f4 | tr ',' '\n' | sed '/^$/d')
    return 0
  fi

  # A branch name containing `/` (an integration/* target) is passed through
  # unencoded: both endpoints route the whole remaining path as the branch name.
  rules_raw=$(gh_api_origin "repos/$ORIGIN_REPO/rules/branches/$branch" 2>/dev/null); rules_rc=$?
  branch_raw=$(gh_api_origin "repos/$ORIGIN_REPO/branches/$branch" 2>/dev/null); branch_rc=$?

  # SHAPE, not just exit status. `gh api` prints the error body to stdout on a
  # non-2xx, so a failed read still produces well-formed JSON; and a zero status
  # with a payload that is not the documented shape (an error object, a proxy
  # page) would reduce silently to "no contexts" — the same fail-open as a 404
  # read as "unprotected".
  if [ "$rules_rc" -ne 0 ] \
     || ! printf '%s' "$rules_raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
    REQ_STATE="unknown"
    REQ_SOURCE="rules/branches/$branch unreadable (rc=$rules_rc)"
  elif [ "$branch_rc" -ne 0 ] \
     || ! printf '%s' "$branch_raw" | jq -e 'type == "object" and has("name")' >/dev/null 2>&1; then
    REQ_STATE="unknown"
    REQ_SOURCE="branches/$branch unreadable (rc=$branch_rc)"
  else
    from_rules=$(printf '%s' "$rules_raw" | jq -r '
      [ .[]
        | select(type == "object")
        | select((.type // "") == "required_status_checks")
        | (.parameters.required_status_checks // [])[]
        | (.context // empty) ] | .[]' 2>/dev/null)
    # `contexts` is the legacy list and `checks[].context` the current one; a
    # repository can report either, so both are read and the union deduped.
    from_branch=$(printf '%s' "$branch_raw" | jq -r '
      [ (.protection.required_status_checks.contexts // [])[],
        ((.protection.required_status_checks.checks // [])[] | (.context // empty)) ] | .[]' 2>/dev/null)
    REQ_CONTEXTS=$(printf '%s\n%s\n' "$from_rules" "$from_branch" | sed '/^$/d' | sort -u)
    REQ_STATE="known"
    REQ_SOURCE="rulesets + branch protection on '$branch'"
  fi

  REQUIRED_CACHE=$(printf '%s%s\t%s\t%s\t%s\n' "$REQUIRED_CACHE" "$branch" \
    "$REQ_STATE" "$REQ_SOURCE" "$(printf '%s' "$REQ_CONTEXTS" | tr '\n' ',' | sed 's/,$//')")
  return 0
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
  | jq -c --arg o "$ORIGIN_REPO_Q" "$REPO_JQ$PR_SELF_JQ"'.[] | (((.metadata.pr_url // "") | tostring) | repo_of) as $r | (pr_nums_here($o)) as $ns | {id, prs: $ns, pr: (if ($ns | length) == 1 then $ns[0] else "" end), prurl: (.metadata.pr_url // ""), repo: (if $r == "?" then $o else $r end), branch: (.metadata.branch // ""), target: (.metadata.merged_target // ""), checkset: (.metadata.check_set // ""), hold: (.metadata.merge_hold // ""), dismissed: (.metadata.signoff_dismissed // ""), meta: (.metadata // {})}' 2>/dev/null)
[ -n "$ROWS" ] || { echo "merge-skill: no gating anchors"; exit 0; }

# NO duplicate-anchor precompute here, deliberately. The one-anchor-per-PR guard
# (tk-ynz4b) lives INSIDE the loop, on the same live per-anchor read the in-flight
# holder gate uses. Computing it once from this snapshot — before a single PR had
# even been read — meant a second gating anchor created or reclassified mid-pass
# was simply not in the set: the pass then validated the PR under the current
# anchor's gates alone while a stronger duplicate gate existed, and (a duplicate
# carries merge_result) the child hold excluded it too, so nothing caught it.
# Same staleness argument as the anchor re-read, applied to the anchor's SIBLINGS.

merged=0; held=0; skipped=0
# Closes that only landed because the identity-ENCODING override fired. Reported in
# the summary line: an override that HAPPENED must be visible, not folded into the
# clean-merge count.
forced=0
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
  dismissed=$(printf '%s' "$row" | jq -r '.dismissed // empty')
  if [ -z "$id" ]; then
    skipped=$((skipped + 1)); continue
  fi
  # ONE number, or none of this anchor's business. `pr` is set only when the widened
  # key set resolved to exactly one in-repo number (see PR_SELF_JQ), so the two
  # failure shapes are distinguished HERE rather than collapsed into one skip:
  #   0 keys  the anchor names no PR in this repository at all — not a merge
  #           candidate; skipped exactly as a pr_number-less anchor always was.
  #   >1 keys the anchor names DIFFERENT numbers under different keys (a fork_pr
  #           left over from an earlier PR beside a fresh pr_number, say). Merging
  #           then means PICKING one, and a wrong pick lands the wrong pull
  #           request — the one mistake this script cannot retry away. HELD, so an
  #           operator repairs the metadata; never guessed.
  nprs=$(printf '%s' "$row" | jq -r '(.prs // []) | length' 2>/dev/null)
  if [ "${nprs:-0}" -gt 1 ]; then
    echo "merge-skill: anchor $id names more than one PR number in this repository ($(printf '%s' "$row" | jq -r '(.prs // []) | join(", ")' 2>/dev/null)); merge held — operator must repair the metadata so exactly one PR is claimed"
    held=$((held + 1)); continue
  fi
  if [ -z "$num" ]; then
    skipped=$((skipped + 1)); continue
  fi

  # Read live PR state, PINNED to this checkout's repository. Only request fields
  # supported by `gh pr view --json` on supported gh versions — an unknown field
  # errors and, with stderr suppressed, empties PR_JSON, skipping the anchor
  # forever. mergeStateStatus is the composite gate (CLEAN = mergeable, required
  # checks green, base current — and approved only where the repo requires a
  # review, which is why `approval` is also checked explicitly below);
  # reviewDecision is read for that check's diagnostics only. The approval
  # EVIDENCE comes from the reviews history, not from `latestReviews`, which
  # reports no commit per verdict (see the gate). The test's gh stub rejects
  # unsupported fields to guard this. `url` is requested for the identity check
  # below.
  PR_JSON=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" \
    --json state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,reviewDecision,url 2>/dev/null)
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
  live_url=$(canon_pr_url "$(printf '%s' "$PR_JSON" | jq -r '.url // ""')")
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
    want_url=$(canon_pr_url "$prurl")
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

  # --- refresh the anchor's metadata (ROWS is a pre-PR-read snapshot) ------
  # ROWS was captured BEFORE the PR read above, and the signoff path writes the
  # anchor concurrently: it stamps check.<gate>=green@<head>, THEN records
  # signoff_dismissed, THEN dismisses the GitHub review that was keeping the PR
  # non-CLEAN. A pass that captured ROWS inside that sequence validates a
  # now-CLEAN PR against a snapshot with no signoff_dismissed — and merges
  # without the external approval the dismissal exists to require. The same
  # staleness applies to merge_hold (an operator can park the anchor mid-pass)
  # and to the check.<gate> markers (a re-gate can clear one). So re-read the
  # anchor HERE — after the PR state, before every gate that reads anchor
  # metadata — and validate from that, never from the snapshot.
  #
  # Fail-closed: an unusable re-read skips the anchor for this pass rather than
  # falling back to the snapshot the race is about. Control characters in bead
  # notes can make `--json` unparseable, so strip them before jq. `select(...)`
  # (not `// {}`) keeps a missing row or missing metadata EMPTY, so those stay
  # the unreadable case rather than becoming an all-default row that validates.
  fresh_row=$(anchor_row "$id")
  if [ -z "$fresh_row" ]; then
    echo "merge-skill: anchor $id metadata re-read failed; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  fresh_status=$(printf '%s' "$fresh_row" | jq -r '.status | ascii_downcase' 2>/dev/null)
  # The SAME widened key set the enumeration resolved this anchor's number from
  # (tk-tbacg #2) — asking pr_number alone here would re-open the gap one layer
  # down: a fork_pr-keyed anchor would enumerate with a number and then fail its
  # own re-read as "no longer records a pr_number". Zero or several is a mismatch
  # for the same reason it is above: neither answers "does this bead still claim
  # exactly PR#$num".
  fresh_pr=$(printf '%s' "$fresh_row" | jq -r --arg o "$ORIGIN_REPO_Q" "$PR_SELF_JQ"'
    {metadata: .meta} | (pr_nums_here($o)) as $ns
    | if ($ns | length) == 1 then $ns[0] else "" end' 2>/dev/null)
  fresh_result=$(printf '%s' "$fresh_row" | jq -r '.meta.merge_result // ""' 2>/dev/null)
  # The fresh row must still BE the gating anchor the enumeration selected — open,
  # parked on a published PR, and claiming exactly the PR just read. Re-reading and
  # then validating anyway is only half a fix: the enumeration's `--status=open
  # --metadata-field merge_result=pull_request` filter is what made "$id gates
  # PR#$num" true, and the whole point of the re-read is that the anchor may have
  # changed since. An anchor that closed, was retargeted off the PR, or had its
  # pr_number cleared mid-pass no longer speaks for this PR at all, so every gate
  # below would be validating a claim nothing supports — and an EMPTY fresh
  # pr_number was doing exactly that: it fell through the `-n` guard and merged
  # against `$num` from the stale snapshot. Any mismatch skips (fail-closed); the
  # next pass re-enumerates and sees whatever the anchor now really is.
  if [ "$fresh_status" != "open" ]; then
    echo "merge-skill: anchor $id is no longer open (status='${fresh_status:-unknown}'); skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  if [ "$fresh_result" != "pull_request" ]; then
    echo "merge-skill: anchor $id no longer parked on a published PR (merge_result='${fresh_result:-unset}', want 'pull_request'); skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  if [ -z "$fresh_pr" ]; then
    echo "merge-skill: anchor $id no longer names exactly one PR in this repository (the PR#$num just read came from the stale snapshot); skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  if [ "$fresh_pr" != "$num" ]; then
    echo "merge-skill: anchor $id now claims PR#$fresh_pr, not the PR#$num just read; skip $id (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  row=$(printf '%s' "$fresh_row" | jq -c --arg id "$id" \
    '.meta
     | {id: $id, pr: (.pr_number // ""), target: (.merged_target // ""),
        checkset: (.check_set // ""), hold: (.merge_hold // ""),
        dismissed: (.signoff_dismissed // ""), meta: .}' 2>/dev/null)
  if [ -z "$row" ]; then
    echo "merge-skill: anchor $id metadata re-read unparseable; skip (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  target=$(printf '%s' "$row" | jq -r '.target // empty')
  hold=$(printf '%s' "$row" | jq -r '.hold // empty')
  dismissed=$(printf '%s' "$row" | jq -r '.dismissed // empty')
  checkset=$(printf '%s' "$row" | jq -r '.checkset // empty')

  # --- validate -----------------------------------------------------------
  # Operator hold: metadata.merge_hold on the anchor is an explicit operator gate
  # ("do not land yet — awaiting manual sign-off"). When truthy the skill must NOT
  # merge no matter how green the PR looks. Checked FIRST among the validate
  # gates, on the freshly re-read metadata above: it is the cheapest gate (no
  # further I/O) and the highest priority (an intentional operator block,
  # independent of PR state), so a held anchor short-circuits before the
  # referencing-bead `gc bd list`. Before this gate the hold was honored only
  # INCIDENTALLY — when the PR happened to be non-CLEAN (BLOCKED/BEHIND) — so a
  # fully-CLEAN held PR would squash-merge to the target with no operator signal.
  # Truthy = set and not empty/false/0 (operators set merge_hold=true); an unset
  # or explicitly-false marker does not hold.
  if merge_hold_truthy "$hold"; then
    echo "merge-skill: PR#$num merge_hold set (operator gate); merge held for operator (anchor $id)"
    held=$((held + 1)); continue
  fi
  # --- every live bead that names this PR, read ONCE and guarded ------------
  # TWO merge-deciding gates are answered from this single read: the
  # one-anchor-per-PR guard immediately below and the in-flight-child hold further
  # down. Both ask the same question — "what else in the ledger claims PR#$num
  # RIGHT NOW" — so they share one read rather than paying for the widened query
  # twice per anchor.
  #
  # LIVE, not from the enumeration snapshot. The duplicate-anchor answer used to be
  # precomputed from ROWS once, before any PR was even read: a second gating anchor
  # created or reclassified mid-pass was simply not in that set, so this pass
  # validated the PR under the CURRENT anchor's gates alone while a stronger
  # duplicate gate existed — and, because a duplicate carries merge_result, it is
  # excluded from the child hold too, so nothing else caught it either. Same
  # staleness argument as the anchor re-read above, applied to the anchor's SIBLINGS.
  #
  # Deliberately AFTER the merge_hold gate, which stays the cheapest and highest
  # priority: an operator-parked anchor still short-circuits before any ledger I/O.
  pr_beads=$(pr_bead_query "$LIVE_STATUSES" "$num"); pr_rc=$?
  if [ "$pr_rc" -ne 0 ] || [ -z "$pr_beads" ]; then
    echo "merge-skill: PR#$num referencing-bead read FAILED (rc=$pr_rc); merge held (anchor $id) — an unreadable ledger cannot prove that no open rework/review child and no duplicate gating anchor holds this PR" >&2
    held=$((held + 1)); continue
  fi
  # One-anchor-per-PR (tk-ynz4b): the loop validates each anchor INDEPENDENTLY, so
  # a PR claimed by more than one open anchor is gated by its WEAKEST anchor — e.g.
  # a rework child that leaked into the anchor class with no check_set would land
  # the PR while the real anchor's codex gate is red, and (carrying merge_result)
  # that same leaked bead is invisible to the in-flight rework hold below. One
  # gating anchor per PR is the design intent (docs/work-bead-state-machine.md);
  # the refinery no longer mints a second anchor on rework hand-back
  # (mol-refinery-patrol.toml one-anchor-per-pr arm), so a duplicate here is
  # legacy/out-of-band state. Hold EVERY anchor of such a PR; the hold releases on
  # a later pass once exactly one open anchor remains (close/demote the duplicate —
  # usually the rework-minted one — to repair the taxonomy).
  #
  # KEYED ON REPOSITORY **AND** NUMBER, with `?` matching anything (see REPO_JQ):
  # a PR NUMBER names a different pull request in every other repository this
  # ledger spans, so a foreign anchor for `otherhost/o/OTHER#<n>` is not a
  # duplicate of ours — keyed on the bare number it held both forever, and no
  # operator could release the hold by repairing anything in THIS repository
  # (review tk-thvbq finding #4). Only a positive, parsed disagreement clears the
  # hold: a legacy anchor naming no URL at all reads `?` and still counts, exactly
  # as it does today. This anchor itself always survives the filter — its own row
  # either carries the pr_url $arepo was derived FROM, or none at all (`?`).
  anchor_ids=$(printf '%s' "$pr_beads" | jq -r --arg r "$arepo" "$REPO_JQ"'
    [ .[] | select(((.status // "") | ascii_downcase) == "open")
          | select((.metadata.merge_result // "") == "pull_request")
          | select(same_repo((((.metadata.pr_url // "") | tostring) | repo_of); $r))
          | .id ] | join(" ")' 2>/dev/null); anchor_rc=$?
  if [ "$anchor_rc" -ne 0 ]; then
    echo "merge-skill: PR#$num open-anchor projection unreadable (jq rc=$anchor_rc); merge held (anchor $id)" >&2
    held=$((held + 1)); continue
  fi
  # The current anchor MUST be in that set: the fresh re-read just proved it is
  # open, parked on a published PR, and claiming PR#$num. Missing means the ledger
  # answered something this pass cannot reconcile with the anchor deciding the
  # merge — so hold rather than merge on a view that does not contain it.
  case " $anchor_ids " in
    *" $id "*) : ;;
    *)
      echo "merge-skill: PR#$num live open-anchor set '${anchor_ids:-none}' does not contain $id, which the re-read just showed open and parked on this PR; merge held (anchor $id)" >&2
      held=$((held + 1)); continue ;;
  esac
  # More than one open anchor is COALESCED into a single gate rather than held
  # outright (tk-3sdfq; see coalesce_gate's header). The hold this replaces had no
  # release: it told the operator to "close/demote the duplicate", nothing performs
  # that demotion, and the pass that used to converge these pairs —
  # reconcile-merged-prs.sh closing every anchor of the PR ON MERGE — is gated
  # behind the merge the hold prevents.
  #
  # Coalescing does not weaken tk-ynz4b: the effective check-set becomes the UNION
  # of the anchors' sets, so the weakest member adds nothing to skip past, and the
  # strongest member's gates all still have to be green AT THE LIVE HEAD. Anything
  # that cannot be certified — a sibling that moved, a sibling with an empty (i.e.
  # unvalidated) check_set, an operator hold anywhere on the PR — falls back to
  # exactly the hold that was here before, naming which sibling and why.
  dup_sibs=""
  if [ "$(printf '%s' "$anchor_ids" | wc -w | tr -d '[:space:]')" -gt 1 ]; then
    dup_sibs="$anchor_ids"
    if coalesce_gate "$id" "$row" "$num" "$arepo" "$head_oid" "$head_ref" "$base" "$live_url" "$dup_sibs"; then
      row="$COALESCE_ROW"
      checkset="$COALESCE_CHECKSET"
      [ -z "$COALESCE_DISMISSED" ] || dismissed="$COALESCE_DISMISSED"
      echo "merge-skill: PR#$num is claimed by ${anchor_ids// /, } — coalesced into ONE gate (union check_set '$checkset'), markers pooled at $head_oid (anchor $id, tk-3sdfq)"
    else
      echo "merge-skill: PR#$num has multiple open gating anchors that cannot be coalesced — $COALESCE_REASON; merge held (anchor $id) — close/demote the duplicate anchor to release (tk-ynz4b)"
      held=$((held + 1)); continue
    fi
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
  #
  # `approval` is dropped from this loop the same way (tk-5niup): it is a real
  # check-set member, but its evidence is GitHub's own review state, not a
  # check.<name> marker a reviewer stamps. Left in, naming it in check_set would
  # hold the anchor forever on a `check.approval` nothing can ever stamp — the
  # identical trap the none/off sentinel drop exists to avoid. Its gate runs
  # below, after the in-flight-child hold.
  if ! hold_gate=$(checkset_hold_gate "$checkset" "$row" "$head_oid"); then
    echo "merge-skill: PR#$num check-set markers unreadable on anchor $id; merge held (retry next pass)"
    held=$((held + 1)); continue
  fi
  if [ -n "$hold_gate" ]; then
    have=$(printf '%s' "$row" | jq -r --arg k "check.$hold_gate" '.meta[$k] // "none"' 2>/dev/null)
    echo "merge-skill: PR#$num check '$hold_gate' not green at live head (have '$have', want 'green@$head_oid'); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # An open rework/review child holds the merge (docs/work-bead-state-machine.md:
  # an anchor lands only when ALL its children are closed). probe_holders resolves
  # that set from every PR-naming key AND from the anchor's own dependency edges — see its
  # header for why one source alone is fail-open. The PR-naming half is the
  # multi-key set already read above for the duplicate-anchor gate, so the two
  # gates cannot disagree about who claims this PR; --limit=0 (unbounded) there:
  # the gate must see EVERY referencing bead, not a page of them, or a child past
  # the cap could let a PR merge while rework is still open.
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
  # The TRACKING_ONLY exclusion is the THIRD SHAPE (tk-8329m). The taxonomy above
  # is binary and the two buckets do not cover the ledger: merge_result PRESENT is
  # a duplicate gating anchor (the DUP_PRS guard's business), merge_result ABSENT
  # is presumed a rework child. A bead that references a PR for LINKAGE ONLY is
  # neither, so it lands in the second bucket by construction and holds its own PR
  # forever. The omission that makes such a bead non-gating — no merge_result,
  # deliberately, because stamping one arms this pass to auto-land an operator's
  # PR — is the same omission that makes it a blocker. Nothing releases it: the
  # only pass that closes a PR-linked bead is reconcile-merged-prs.sh, AFTER the
  # PR merges, which is the very thing the hold prevents. The release condition
  # sits downstream of what it blocks, so the hold is permanent, not the one pass
  # this gate is designed to cost (live case: tk-uicmw / PR#291 — CLEAN, APPROVED,
  # codex-green at the live head, held on every idle wake).
  #
  # An EXPLICIT opt-out, never a loosening of the default. An unmarked bead with no
  # merge_result keeps holding exactly as before: fail-closed is the whole point of
  # the $mr == "" arm, and the alternative remedy — presume rework only when a
  # rework/review `task_kind` is present — inverts that, since almost no rework
  # child records a task_kind and every one of them would stop holding. Only a
  # marker an operator sets BY HAND clears the hold, read with merge_hold's
  # truthiness rule (merge_hold_truthy, restated here in jq because the value is
  # per-holder inside the filter, not per-anchor in shell): unset, empty, false, 0
  # and null all keep holding, so a half-written marker cannot disarm a gate.
  #
  # Scoped to `_via == "pr_number"` like both of its neighbours, and by the same
  # rule. A dependency edge is a claim made in THIS ledger that this bead holds
  # this anchor, and "I merely reference the PR for tracking" cannot be true of a
  # bead somebody filed as an explicit merge-ordering `blocks` or as the anchor's
  # own rework child. Honouring the marker on the dep arm would re-open tk-je0rk's
  # fail-OPEN hole through a third door — a holder that names itself harmless.
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
  #
  # COALESCED anchors probe as one (tk-3sdfq): the holder set is the UNION of
  # every member's, and the members themselves are excluded from it. Probing only
  # the anchor that happens to be merging would be the fail-OPEN half of
  # coalescing — a sibling's open rework child holds the PR just as its check-set
  # gates it, and dropping that would land the PR while real rework is in flight.
  # Excluding the members is what stops the union from holding itself: they are no
  # longer separate gating anchors, they are one gate, and a gate does not block
  # its own merge (unexcluded, the pair would deadlock exactly as before, since
  # each member is a dep-linked or PR-naming holder of the other).
  if ! holders=$(probe_holders "$id" "$pr_beads"); then
    echo "merge-skill: PR#$num in-flight rework/review probe failed; merge held (anchor $id, retry next pass)"
    held=$((held + 1)); continue
  fi
  if [ -n "$dup_sibs" ]; then
    holder_fail=""
    for sib_id in $dup_sibs; do
      [ "$sib_id" != "$id" ] || continue
      if ! sib_holders=$(probe_holders "$sib_id" "$pr_beads"); then
        holder_fail="$sib_id"; break
      fi
      holders=$(printf '%s\n%s' "$holders" "$sib_holders" | jq -sc '
        add | group_by(.id)
        | map(.[0] + {_via: (if (map(._via) | index("dep")) then "dep" else "pr_number" end)})' 2>/dev/null)
      [ -n "$holders" ] || { holder_fail="$sib_id"; break; }
    done
    if [ -n "$holder_fail" ]; then
      echo "merge-skill: PR#$num in-flight rework/review probe failed for coalesced sibling $holder_fail; merge held (anchor $id, retry next pass)"
      held=$((held + 1)); continue
    fi
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
  # `$anchor` is EVERY member of the coalesced gate (just `$id` when there is no
  # duplicate), space-wrapped for whole-token matching. Nothing holds itself, and
  # under coalescing "itself" is the whole union.
  if ! inflight=$(printf '%s' "$holders" | jq -r --arg anchor " ${dup_sibs:-$id} " --arg live "$LIVE_STATUSES" --arg r "$arepo" "$REPO_JQ"'
    ($live | split(",")) as $live_statuses
    | [ .[]
        | (.id // "") as $bid
        | select($bid != "" and (($anchor | contains(" " + $bid + " ")) | not))
        | select(((.status // "open") | ascii_downcase) as $s | $live_statuses | index($s))
        | ((.metadata.merge_result // "") | tostring) as $mr
        | ((._via // "pr_number")) as $via
        | ((.metadata.tracking_only // "") | tostring | ascii_downcase) as $track
        | (["", "false", "0", "null"] | index($track) | not) as $tracking_only
        | select($via == "dep"
                 or ($mr == ""
                     and ($tracking_only | not)
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
  # The `approval` member, checked EXPLICITLY and independently of CLEAN
  # (tk-5niup). Required when the anchor names `approval` in check_set, or when
  # it carries signoff_dismissed — the city retracted its own blocking review on
  # this PR, so the CLEAN below is partly OUR doing and cannot be read as
  # approval evidence. Sticky on presence, not head-match: dismissal is
  # permanent, so a later head must not silently drop the requirement.
  #
  # Evidence is an APPROVED review by an account that is BOTH other than
  # $SELF_LOGIN and trusted under the policy in the header (an allowlist entry, or
  # write-level repo permission), attached to the LIVE head. Read from the REST
  # reviews history rather than
  # `gh pr view --json latestReviews`: latestReviews gives the latest verdict per
  # reviewer but carries NO commit, so an approval of an OLD head is
  # indistinguishable from one of the live head. On a repo that does not dismiss
  # stale approvals, that gap is the whole exploit — the city dismisses its own
  # block, an approval nobody re-issued still reads as effective, and unreviewed
  # commits merge. Head-binding closes it, and matches check.<name>=green@<head>:
  # any commit pushed after the approval re-gates.
  #
  # Effective verdict = the LATEST state-bearing review PER non-self reviewer,
  # computed BEFORE any terminal-state filtering. Which states take part matters:
  #   APPROVED / CHANGES_REQUESTED — the verdicts themselves.
  #   DISMISSED — a review whose verdict was RETRACTED (its own state is mutated
  #     to DISMISSED in this history). It carries no verdict, but it must still
  #     take part in "latest", because it SHADOWS that reviewer's older rows:
  #     filtering it out before grouping would let an APPROVED row from before it
  #     resurrect as the reviewer's effective verdict — an approval that was
  #     explicitly taken back satisfying the gate.
  #   COMMENTED / PENDING — carry no verdict AND supersede nothing (the city's
  #     own COMMENT signoffs live here), so they are excluded outright: a later
  #     comment must not shadow a standing approval or changes-request.
  # From that per-reviewer latest set, TWO answers are read: a standing
  # CHANGES_REQUESTED from ANY non-self reviewer vetoes the merge (one reviewer's
  # approval does not overrule another's unresolved objection — and on an
  # unprotected repo mergeStateStatus can be CLEAN straight through it), and the
  # approval itself must be a latest APPROVED pinned to the live head.
  #
  # PAGINATED, explicitly: GitHub pages this endpoint (30/page by default), and a
  # PR that has taken a few review rounds easily runs past one page. An
  # unpaginated read could miss the approval entirely (a permanent false hold) or
  # — worse — miss a reviewer's LATER CHANGES_REQUESTED and let their earlier
  # APPROVED stand as the effective verdict.
  #
  # Checked BEFORE mergeStateStatus so the hold names the missing approval
  # instead of the generic BLOCKED it would otherwise surface as.
  #
  # The `approval` member is matched IN-SHELL against the check_set string, never
  # through a `jq ... | grep -qxF approval` pipeline. `set -o pipefail` is on (line
  # 110) and `grep -q` exits at the FIRST match: that closes the pipe under jq
  # while it is still writing the gates that FOLLOW `approval` in the list, jq
  # takes SIGPIPE, the pipeline reports 141, and the `&& needs_approval=1` never
  # runs. A check_set that DOES name `approval` then reads as one that does not —
  # decided by nothing but how many gates happen to come after it, so a rig can
  # pass on a short check_set and silently lose the gate when it grows. On an
  # unprotected repo, where mergeStateStatus is CLEAN with zero approving reviews,
  # that drops the only thing standing between the PR and an unapproved merge.
  # This is the same failure class the trusted-approver allowlist above already
  # avoids the same way — fixed there, still live here. Whitespace is stripped
  # outright (a gate name cannot contain any) and the comma wrapping makes it a
  # whole-token match, so `approval` matches while `pre-approval` does not.
  needs_approval=""
  case ",$(printf '%s' "$checkset" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')," in
    *",approval,"*) needs_approval=1 ;;
  esac
  [ -n "$dismissed" ] && needs_approval=1

  # The reviews history is read for EVERY candidate that reaches this point, not
  # only for one already known to need an approval (tk-tmefn). It carries the
  # THIRD arm of the requirement — a review of OURS that was DISMISSED — and that
  # arm exists precisely for the case where nothing bead-side says so: an operator
  # who clears the stale city CHANGES_REQUESTED by hand on github.com writes no
  # signoff_dismissed, so a gate armed from the two markers alone never fires, and
  # the PR — CLEAN again only because WE were the block that lifted — merges with
  # no approval owed to anyone. The history is the only place that fact is
  # recorded, so it has to be read BEFORE the arming decision rather than after
  # it.
  #
  # The cost is one paginated call per merge candidate and one new way to hold: a
  # history that cannot be read now holds a PR that previously never needed it.
  # That is the same trade every gate here makes — an unreadable history cannot
  # prove that no block of ours was retracted — and the cost of being wrong is one
  # idle pass, against an unapproved merge that cannot be taken back.
  #
  # Note what is NOT hoisted here: the unresolved-$SELF_LOGIN and unresolved-head
  # holds stay INSIDE the armed branch below. They are about EVALUATING the gate
  # (excluding a self-approval, head-binding an approving review), not about
  # arming it, and hoisting them would hold every anchor on a `gh api user` blip.
  # The arming step handles an unknown login on its own terms, below.
  #
  # FETCH and REDUCE are SEPARATE steps, each with its own status check. Fused
  # into one assignment tested only for non-emptiness, a paginated read that
  # fails PART WAY THROUGH is indistinguishable from a complete one: `gh
  # --paginate` streams the pages it did get, jq reduces them without complaint,
  # and the result is a well-formed answer computed from a TRUNCATED history.
  # That truncation is not a neutral loss — the tail is exactly where a
  # reviewer's later CHANGES_REQUESTED (the verdict that supersedes their own
  # earlier APPROVED) lives, so a half-read history can turn a vetoed PR into an
  # approved one, which is case (18b) re-entering through the error path instead
  # of the paging one. It is also where a dismissal of our own review can sit, so
  # a truncated read can silently un-arm the third arm as well. `set -uo pipefail`
  # is on but `set -e` is deliberately off, so nothing aborts by itself: the exit
  # status must be read explicitly, and ANY failure holds the merge.
  # PINNED to the origin repository AND its host, like the `gh pr view --repo`
  # read that produced $num and unlike the `{owner}/{repo}` placeholder this used
  # to carry (review tk-5knqi finding #1). Unpinned, gh resolves the path in its
  # ambient repository, so the approval gate below decides THIS merge from
  # ANOTHER repository's review history: a same-numbered PR approved there
  # satisfies the gate here, and a standing CHANGES_REQUESTED here is invisible
  # because the veto lives in a history that was never read. Both directions
  # merge work no reviewer of this repository ever cleared.
  reviews_raw=$(gh_api_origin --paginate "repos/$ORIGIN_REPO/pulls/$num/reviews?per_page=100" \
    --jq '.[]' 2>/dev/null); reviews_rc=$?
  if [ "$reviews_rc" -ne 0 ]; then
    echo "merge-skill: PR#$num reviews history read FAILED (gh rc=$reviews_rc; a partial page set can hide a later CHANGES_REQUESTED, or a dismissal of our own blocking review); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  reviews_state=$(printf '%s' "$reviews_raw" \
    | jq -cs --arg self "$SELF_LOGIN" --arg head "$head_oid" '
        ( [ .[]
            | select((.user.login // "") != $self)
            | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED"
                     or .state == "DISMISSED") ]
          | group_by(.user.login // "")
          | map(sort_by((.submitted_at // ""), (.id // 0)) | last) ) as $latest
        | { veto: ([ $latest[]
                     | select(.state == "CHANGES_REQUESTED")
                     | (.user.login // "") ] | .[0] // ""),
            approvers: [ $latest[]
                         | select(.state == "APPROVED")
                         | select((.commit_id // "") == $head)
                         | (.user.login // "") ],
            self_dismissed: ([ .[]
                               | select($self != "")
                               | select((.user.login // "") == $self)
                               | select(.state == "DISMISSED") ] | length),
            any_dismissed: ([ .[]
                              | select(.state == "DISMISSED") ] | length) }' 2>/dev/null); reduce_rc=$?
  if [ "$reduce_rc" -ne 0 ] || [ -z "$reviews_state" ]; then
    echo "merge-skill: PR#$num reviews history is unreadable (reduce rc=$reduce_rc); merge held (anchor $id)"
    held=$((held + 1)); continue
  fi
  # THE VETO, enforced here — for EVERY merge candidate whose history was read,
  # not only for one whose approval gate happens to be armed. A standing
  # CHANGES_REQUESTED is a human saying "not this". It is not a sub-clause of the
  # approval requirement: nothing about a rig declining to declare `approval` in
  # its check_set makes another reviewer's objection stop counting. Scoped inside
  # the armed branch (where it lived), the ordinary codex-only anchor — check_set
  # `codex`, check.codex green@head, no `approval` member, no signoff_dismissed,
  # nothing dismissed in the history — never consulted it at all, and on an
  # unprotected repo mergeStateStatus is CLEAN straight through an open
  # changes-request, so the pass squash-merged past the veto. That is the whole
  # bypass: the one gate that reads a human's explicit objection was reachable
  # only from the gate that reads a human's explicit approval.
  #
  # NOT head-bound, unlike the approval below. An objection stays live until its
  # author supersedes it (`.veto` is computed from each reviewer's LATEST verdict,
  # so a later APPROVED from the same login clears it) or it is dismissed. A new
  # commit does not answer it — pushing over an objection is not resolving one.
  #
  # With an unresolvable $SELF_LOGIN the reduction cannot exclude our OWN rows, so
  # a stale city block reads as an external veto and holds. Deliberate, and the
  # same direction as every other unreadable-input path here: a hold is retried
  # next pass and heals the moment `gh api user` answers, while a merge past a
  # live objection cannot be taken back. The message names the caveat so the hold
  # does not read as a mystery.
  veto=$(printf '%s' "$reviews_state" | jq -r '.veto // ""' 2>/dev/null)
  if [ -n "$veto" ]; then
    veto_caveat=""
    [ -n "$SELF_LOGIN" ] || veto_caveat=" (acting login unresolved, so a block of our own cannot be excluded)"
    echo "merge-skill: PR#$num external reviewer '$veto' has a standing CHANGES_REQUESTED — a latest changes-request vetoes the merge regardless of the check-set$veto_caveat; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # The third arm. A DISMISSED review under our OWN login is a blocking review of
  # ours that was retracted — in-band by the re-gate supersede step, or by hand on
  # github.com, which is the case no marker records. Counted over the WHOLE
  # history rather than the per-reviewer latest set above: the retraction is a
  # permanent fact about this PR, and the city posts a COMMENT every signoff
  # round, so a "latest" reading would let the next comment shadow it away.
  #
  # With no resolvable $SELF_LOGIN, no dismissal can be ATTRIBUTED — so the arm
  # falls back to "was anything dismissed here at all". That is deliberately
  # over-broad (an external reviewer's own retracted approval arms it too) and
  # deliberately narrow in blast radius: a PR with no dismissals in its history —
  # which is nearly all of them, including every PR the city never blocked — is
  # unaffected, so a `gh api user` blip cannot stall the queue. Over-arming costs
  # an approval that was going to be required anyway on a PR whose review state
  # someone has already been editing.
  dismiss_key=self_dismissed
  [ -n "$SELF_LOGIN" ] || dismiss_key=any_dismissed
  self_dismissed=$(printf '%s' "$reviews_state" \
    | jq -r --arg k "$dismiss_key" '.[$k] // 0' 2>/dev/null)
  case "${self_dismissed:-0}" in
    ''|0) : ;;
    *)    needs_approval=1 ;;
  esac
  if [ -n "$needs_approval" ]; then
    if [ -z "$SELF_LOGIN" ]; then
      echo "merge-skill: PR#$num approval required but the acting login is unresolved (cannot exclude a self-approval); merge held (anchor $id)"
      held=$((held + 1)); continue
    fi
    if [ -z "$head_oid" ]; then
      echo "merge-skill: PR#$num approval required but the live head is unresolved (cannot head-bind the approval); merge held (anchor $id)"
      held=$((held + 1)); continue
    fi
    # No veto read here: a standing CHANGES_REQUESTED already held this PR above,
    # for every candidate rather than only for an armed one, so anything reaching
    # this branch has none. What is left is the approval-SPECIFIC evaluation —
    # who approved, at which commit, and whether the city may count them.
    #
    # Every login whose LATEST verdict is an APPROVED at the live head is a
    # CANDIDATE — being non-self is what makes an approval external, not what
    # makes it authoritative. Each candidate is then put to the trusted-approver
    # policy, and the first one that passes satisfies the gate; the rest are
    # reported so an untrusted approval reads as a policy hold rather than as a
    # missing review.
    candidates=$(printf '%s' "$reviews_state" | jq -r '.approvers[]? // empty' 2>/dev/null)
    approver=""; untrusted=""
    while IFS= read -r cand; do
      [ -n "$cand" ] || continue
      if approver_trusted "$cand"; then approver="$cand"; break; fi
      untrusted="${untrusted:+$untrusted, }$cand"
    done <<< "$candidates"
    if [ -z "$approver" ]; then
      # Name the arm that armed the gate, most specific first: the in-band marker,
      # then the GitHub-side dismissal the marker does not record (an operator
      # clearing our review by hand — the hold reads as a mystery without it),
      # then the declared check_set member.
      why="check_set names approval"
      [ "${self_dismissed:-0}" != 0 ] && why="a review authored by '$SELF_LOGIN' was DISMISSED on this PR (${self_dismissed}x) — the city's own block was retracted, so CLEAN is partly our doing"
      [ -n "$dismissed" ] && why="signoff_dismissed=$dismissed"
      if [ -n "$untrusted" ]; then
        policy="write-level repo permission (admin/maintain/write)"
        [ -n "$TRUSTED_APPROVERS" ] && policy="the MERGE_TRUSTED_APPROVERS allowlist"
        echo "merge-skill: PR#$num approved at the live head $head_oid by '$untrusted', but no approver satisfies the trusted-approver policy ($policy) ($why); merge held (anchor $id) — grant the approver write access, or list them in MERGE_TRUSTED_APPROVERS if the permission probe is unreadable for this token"
      else
        echo "merge-skill: PR#$num no external approving review at the live head $head_oid ($why; reviewDecision='$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // ""')'); merge held (anchor $id)"
      fi
      held=$((held + 1)); continue
    fi
  fi
  # CI + base-current + no-conflict: GitHub's composite mergeStateStatus. CLEAN
  # is the mergeable state with every REQUIRED check green. It also folds
  # approval, but only where the repo's ruleset requires a review — on an
  # unprotected repo CLEAN is true with zero approvals, which is what the
  # explicit `approval` member above exists to cover. BLOCKED (a required check
  # or a required review genuinely gating), BEHIND (base moved), DIRTY
  # (conflict), UNKNOWN (GitHub still computing) hold the merge and retry.
  #
  # UNSTABLE is the one non-CLEAN state that is NOT a gate by itself (tk-zuoys),
  # and treating it as one zeroed refinery throughput outright. GitHub defines it
  # as "mergeable with non-passing commit status": a check is red, and NOTHING
  # required is blocking — a failing REQUIRED check is reported as BLOCKED
  # instead. Both of this city's rigs configure zero required status checks, so
  # on either of them a red advisory check made every PR permanently unmergeable
  # under the old `!= CLEAN` rule, however green, approved and gated it was.
  # gascity PR#105 sat at UNSTABLE with 7 failing checks, all pre-existing on
  # main and none required; a plain `gh pr merge --squash` took it with no
  # override at all. The hold was this script's, not GitHub's.
  #
  # So UNSTABLE is decided on the REQUIRED SET rather than on the composite:
  # resolve the contexts that actually gate the base branch and evaluate ONLY
  # those against the head's check rollup. Deliberately NOT relaxed to "merge
  # unless BLOCKED" — that reading is GitHub's composite over again, and it would
  # merge a red required check on any repository that grows one. Zero required
  # contexts is what makes an UNSTABLE PR mergeable, and it is established by
  # reading the protection, never assumed from the state name.
  #
  # The `approval` member above is untouched by this and runs BEFORE it: an
  # unapproved PR is still held by that gate, and by BLOCKED, exactly as before.
  case "$merge_state" in
    CLEAN) : ;;
    UNSTABLE)
      required_contexts_for "$base"
      if [ "$REQ_STATE" != "known" ]; then
        # FAIL CLOSED. Unreadable protection cannot establish that the red checks
        # are advisory, and merging on the state name alone is the composite-only
        # reading this gate exists to replace. One idle pass, against landing a
        # red required check.
        echo "merge-skill: PR#$num is UNSTABLE and the REQUIRED status-check set for base '$base' could not be read ($REQ_SOURCE); cannot tell a red advisory check from a red required one, so merge held (anchor $id)"
        held=$((held + 1)); continue
      fi
      if [ -z "$REQ_CONTEXTS" ]; then
        # The gascity shape: red CI that gates nothing at GitHub.
        echo "merge-skill: PR#$num is UNSTABLE but base '$base' requires NO status checks ($REQ_SOURCE); the red checks are advisory and gate nothing — proceeding (anchor $id)"
      else
        # Required contexts exist: every one of them must be green AT THE HEAD
        # this pass validated. Read lazily, only on this arm, so the hot path's
        # PR payload and its field-shape guard are untouched.
        rollup_raw=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json statusCheckRollup 2>/dev/null)
        if [ -z "$rollup_raw" ] \
           || ! printf '%s' "$rollup_raw" | jq -e 'type == "object" and has("statusCheckRollup")' >/dev/null 2>&1; then
          echo "merge-skill: PR#$num is UNSTABLE and base '$base' requires $(printf '%s' "$REQ_CONTEXTS" | tr '\n' ' ' | sed 's/ $//'), but the head's check rollup is unreadable; merge held (anchor $id)"
          held=$((held + 1)); continue
        fi
        # One verdict line per REQUIRED context. A rollup entry is a CheckRun
        # (name + conclusion) or a StatusContext (context + state); SUCCESS,
        # NEUTRAL and SKIPPED count as passing, matching how GitHub itself
        # satisfies a required check. A required context with NO entry is MISSING
        # — never green — and a CheckRun still running has no conclusion yet, so
        # it lands on the same side. Every rollup entry for a context must pass,
        # so a red run cannot be masked by a green sibling.
        req_json=$(printf '%s\n' "$REQ_CONTEXTS" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null)
        verdicts=""
        if [ -n "$req_json" ]; then
          verdicts=$(printf '%s' "$rollup_raw" | jq -r --argjson req "$req_json" '
            def name_of: (.name // .context // "");
            def green:
              if ((.conclusion // "") | tostring | length) > 0
                then ((.conclusion | ascii_upcase) as $c
                      | $c == "SUCCESS" or $c == "NEUTRAL" or $c == "SKIPPED")
              elif ((.state // "") | tostring | length) > 0
                then ((.state | ascii_upcase) == "SUCCESS")
              else false end;
            (.statusCheckRollup // []) as $rollup
            | $req[] as $r
            | ([ $rollup[] | select(type == "object") | select(name_of == $r) ]) as $hits
            | if ($hits | length) == 0 then "MISSING\t\($r)"
              elif ([ $hits[] | select(green | not) ] | length) > 0 then "RED\t\($r)"
              else "GREEN\t\($r)" end' 2>/dev/null)
        fi
        if [ -z "$verdicts" ]; then
          echo "merge-skill: PR#$num is UNSTABLE and the required-check verdicts for base '$base' could not be computed; merge held (anchor $id)"
          held=$((held + 1)); continue
        fi
        notgreen=$(printf '%s\n' "$verdicts" | awk -F'\t' '$1 != "GREEN" { printf "%s(%s) ", $2, $1 }')
        if [ -n "$notgreen" ]; then
          echo "merge-skill: PR#$num is UNSTABLE and a REQUIRED status check is not green at head $head_oid: ${notgreen% }; merge held (anchor $id)"
          held=$((held + 1)); continue
        fi
        echo "merge-skill: PR#$num is UNSTABLE but every REQUIRED status check on base '$base' is green at head $head_oid ($(printf '%s' "$REQ_CONTEXTS" | tr '\n' ' ' | sed 's/ $//')); the remaining red checks are advisory — proceeding (anchor $id)"
      fi
      ;;
    *)
      echo "merge-skill: PR#$num not mergeable yet (mergeStateStatus='${merge_state:-unknown}', mergeable='${mergeable:-?}'); merge held (anchor $id)"
      held=$((held + 1)); continue ;;
  esac

  # --- merge (single writer; IMMEDIATE, not --auto) -----------------------
  # --squash matches the repo's squash-merge convention (commit "(#N)" tail).
  # The full check-set validated above; this is the terminal check. A server-side
  # refusal (branch protection, a race) leaves the anchor OPEN to retry next pass.
  # PINNED like the read: the merge must land in the repository whose PR was just
  # validated, not in whatever repository gh considers current at this instant.
  #
  # --match-head-commit binds the merge to the SAME commit every gate above was
  # validated against. Every one of those gates is head-bound (check.<name>=
  # green@<head>, the approval's commit_id, mergeStateStatus computed for the
  # head GitHub had) — but the merge itself was not, so a push landing between
  # validation and this call would squash a commit nothing in this pass ever
  # looked at. GitHub refuses the merge on a mismatch, which is exactly the
  # wanted outcome: the anchor stays OPEN and re-validates against the new head
  # next pass. An unresolved head cannot be bound at all, so it holds instead.
  if [ -z "$head_oid" ]; then
    echo "merge-skill: PR#$num live head unresolved (headRefOid empty); cannot head-match the merge; merge held (anchor $id)"
    held=$((held + 1)); continue
  fi

  # --- the LAST thing before the merge: re-read the anchor (tk-tbacg #1) ------
  # `--match-head-commit` binds the merge to the validated COMMIT. Nothing bound it
  # to the validated BEAD. Every gate above ran against metadata read earlier in this
  # pass, and the window between them and this call is wide — the PR read, the
  # referencing-bead query, the holder probes, the reviews history, each an
  # unbounded network or ledger round-trip. Inside it another writer can park the
  # anchor (`merge_hold`), clear or advance a `check.<gate>` marker on a re-gate,
  # close the anchor, or retarget it off this PR, all WITHOUT moving the PR head —
  # so the head-match sails through and the bead that authorized the merge no longer
  # does. The bead is the authority, so it gets the same freshness the commit does.
  #
  # Deliberately the LAST gate and deliberately CHEAP: one `gc bd show`, only for an
  # anchor that already passed everything else (a handful per pass), re-asking
  # EVERY bead-local fact that authorizes this merge — the whole anchor-local
  # authorization set, not a subset of it. The gates whose evidence lives OUTSIDE
  # the bead (CI, the approving review, the child hold) are not re-asked here;
  # their freshness is the head-match's job and the next pass's.
  #
  # "Every bead-local fact" is the correction from review tk-78ty5 finding #2. The
  # first version re-asked status, merge_result, PR number, merge_hold and the
  # check-set markers, and stopped there — so four fields that authorize the merge
  # just as directly were still trusted from a snapshot, and `--match-head-commit`
  # cannot catch any of them because NONE of them move the head:
  #
  #   signoff_dismissed  arms the external-approval requirement. A signoff writing
  #                      it AFTER the approval gate ran (the gate reads it at
  #                      ~1130, the retraction stamps it later in the same window)
  #                      means the city retracted its own block on a PR this pass
  #                      already decided needed no external approval — the exact
  #                      fail-open the marker exists to prevent.
  #   merged_target      a SAME-HEAD retarget. The retarget gate compared the live
  #                      base to the target read before it; repointing the anchor
  #                      afterwards lands this head on a branch nobody validated.
  #   pr_url / branch    identity. Both were read from the pre-PR-read ROWS
  #                      snapshot — the staler of the two reads — and an identity
  #                      REPAIR mid-pass (check-set-heal backfilling a certified
  #                      pr_url, an operator correcting a mis-stamped branch) is
  #                      precisely the write that makes the earlier comparison
  #                      wrong. Re-asked against the live PR, not against the
  #                      snapshot they were first compared to.
  #
  # Each is compared to the LIVE PR fact it was validated against ($base, $live_url,
  # $head_ref), never to the earlier snapshot: the question is "does the bead still
  # authorize THIS merge", not "did the bead change".
  #
  # Fail-closed in both directions: an unreadable re-read HOLDS (a merge is the one
  # act that cannot be retried away, so "I could not confirm" must not merge), and
  # any mismatch holds with the reason named. The next pass re-enumerates and
  # merges once the anchor really does authorize it.
  final_row=$(anchor_row "$id")
  if [ -z "$final_row" ]; then
    echo "merge-skill: PR#$num anchor $id could not be re-read immediately before the merge; merge held (retry next pass) — an unreadable bead cannot authorize a merge"
    held=$((held + 1)); continue
  fi
  final_status=$(printf '%s' "$final_row" | jq -r '.status | ascii_downcase' 2>/dev/null)
  final_result=$(printf '%s' "$final_row" | jq -r '.meta.merge_result // ""' 2>/dev/null)
  final_pr=$(printf '%s' "$final_row" | jq -r --arg o "$ORIGIN_REPO_Q" "$PR_SELF_JQ"'
    {metadata: .meta} | (pr_nums_here($o)) as $ns
    | if ($ns | length) == 1 then $ns[0] else "" end' 2>/dev/null)
  final_hold=$(printf '%s' "$final_row" | jq -r '.meta.merge_hold // ""' 2>/dev/null)
  final_checkset=$(printf '%s' "$final_row" | jq -r '.meta.check_set // ""' 2>/dev/null)
  final_dismissed=$(printf '%s' "$final_row" | jq -r '.meta.signoff_dismissed // ""' 2>/dev/null)
  final_target=$(printf '%s' "$final_row" | jq -r '.meta.merged_target // ""' 2>/dev/null)
  final_prurl=$(printf '%s' "$final_row" | jq -r '.meta.pr_url // ""' 2>/dev/null)
  final_branch=$(printf '%s' "$final_row" | jq -r '.meta.branch // ""' 2>/dev/null)
  final_reason=""
  # A COALESCED gate is re-coalesced here, from fresh reads of every member
  # (tk-3sdfq). The whole point of this re-read is that a bead can change inside
  # the pass's window, and under coalescing the gate is not one bead: a sibling's
  # marker can go stale, an operator can park a sibling, a sibling can stop gating
  # this PR. Re-asking only `$id` would re-confirm a fraction of the authorization
  # and merge on the rest as it stood a dozen round-trips ago. On refusal the
  # reason travels as-is — the same fail-closed answer the first coalesce gives.
  if [ -n "$dup_sibs" ]; then
    if coalesce_gate "$id" "$final_row" "$num" "$arepo" "$head_oid" "$head_ref" "$base" "$live_url" "$dup_sibs"; then
      final_row="$COALESCE_ROW"
      final_checkset="$COALESCE_CHECKSET"
      [ -z "$COALESCE_DISMISSED" ] || final_dismissed="$COALESCE_DISMISSED"
    else
      final_reason="the anchors claiming this PR can no longer be coalesced — $COALESCE_REASON"
    fi
  fi
  if [ -n "$final_reason" ]; then
    : # the coalesced re-read above already named the reason
  elif [ "$final_status" != "open" ]; then
    final_reason="anchor is no longer open (status='${final_status:-unknown}')"
  elif [ "$final_result" != "pull_request" ]; then
    final_reason="anchor no longer parked on a published PR (merge_result='${final_result:-unset}')"
  elif [ "$final_pr" != "$num" ]; then
    final_reason="anchor now claims '${final_pr:-none}', not PR#$num"
  elif merge_hold_truthy "$final_hold"; then
    final_reason="merge_hold was set after validation (operator gate)"
  # A signoff_dismissed that appeared (or changed) after the approval gate ran
  # means the city retracted one of its OWN blocking reviews inside this pass's
  # window. The approval gate is what that marker arms, and it has already run —
  # so this merge was authorized against a bead that did not yet carry the
  # requirement. Hold unconditionally on any change rather than re-deriving
  # `needs_approval` here: the evidence the requirement needs (the reviews
  # history) lives outside the bead, this gate is deliberately one ledger read,
  # and the next pass re-validates the whole approval path against the marker.
  elif [ "$final_dismissed" != "$dismissed" ]; then
    final_reason="signoff_dismissed changed after the approval gate ran ('${dismissed:-unset}' -> '${final_dismissed:-unset}') — a review the city retracted mid-pass arms the external-approval requirement, which this pass has already decided"
  # Same-head retarget: `--match-head-commit` binds the COMMIT, not the branch it
  # lands ON. Compared against the LIVE base, exactly as the retarget gate above
  # compares it, so a retarget between the two reads cannot land this head on a
  # branch no gate in this pass ever looked at.
  elif [ -n "$final_target" ] && [ -n "$base" ] && [ "$final_target" != "$base" ]; then
    final_reason="anchor was retargeted after validation (merged_target='$final_target', PR base '$base') — merging now would land on the wrong branch"
  # Identity, re-asked against the live PR this pass read (not against the ROWS
  # snapshot the first comparison used). An anchor with no recorded url/branch is
  # governed by the pinned read and the repository checks, exactly as above.
  elif [ -n "$final_prurl" ] && [ "$(canon_pr_url "$final_prurl")" != "$live_url" ]; then
    final_reason="anchor now records pr_url '$final_prurl', which is not the PR#$num just validated ('$live_url')"
  elif [ -n "$final_branch" ] && [ -n "$head_ref" ] && [ "$final_branch" != "$head_ref" ]; then
    final_reason="anchor now records branch '$final_branch' but PR#$num is opened from '$head_ref' — the bead and the PR describe different work"
  else
    if ! final_gate=$(checkset_hold_gate "$final_checkset" "$final_row" "$head_oid"); then
      final_gate=""
      final_reason="its check-set markers could not be read"
    fi
    if [ -n "$final_gate" ]; then
      final_have=$(printf '%s' "$final_row" | jq -r --arg k "check.$final_gate" '.meta[$k] // "none"' 2>/dev/null)
      final_reason="check '$final_gate' is no longer green at $head_oid (have '$final_have')"
    fi
  fi
  if [ -n "$final_reason" ]; then
    echo "merge-skill: PR#$num anchor $id changed between validation and the merge — $final_reason; merge held (retry next pass)"
    held=$((held + 1)); continue
  fi

  MERGE_ERR=$(gh pr merge "$num" --repo "$ORIGIN_REPO_Q" --squash \
    --match-head-commit "$head_oid" 2>&1); merge_rc=$?
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
  if close_anchor "$id" "Merged to $target at ${short:-merge}"; then
    [ -z "${CLOSE_FORCED:-}" ] || forced=$((forced + 1))
    # The observer's close-failure counter travels with the other in-flight
    # blockers: this anchor has now closed, so a count left behind from an earlier
    # wedged run would read as stuck and would re-bound a future escalation that
    # has nothing to do with it.
    gc bd update "$id" \
      --set-metadata merge_result=merged \
      --set-metadata merged_sha="$merge_oid" \
      --unset-metadata rejection_reason \
      --unset-metadata close_failures \
      --unset-metadata close_escalated >/dev/null 2>&1 || true
    merged=$((merged + 1))
    echo "merge-skill: merged + recorded $id — PR#$num squashed to $target at ${short:-?}"
  else
    echo "merge-skill: PR#$num MERGED but close failed for $id; observer records next pass" >&2
    skipped=$((skipped + 1))
  fi
done <<< "$ROWS"

echo "merge-skill: $merged merged, $held held, $forced identity-encoding forced closes, $skipped skipped"
exit 0
