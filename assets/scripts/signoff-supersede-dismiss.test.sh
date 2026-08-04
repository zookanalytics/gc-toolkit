#!/usr/bin/env bash
# Hermetic test for the re-gate supersede step (tk-5niup) — the half of the codex
# signoff that reconciles the GitHub side with the bead side.
#
# The bug: codex reviews at head A -> REQUEST_CHANGES (a GitHub review), rework
# lands, head advances A -> B, the re-gate at B posts a COMMENT review and stamps
# check.codex=green@B. But a COMMENT does NOT supersede the same reviewer's
# earlier CHANGES_REQUESTED, so GitHub keeps reviewDecision=CHANGES_REQUESTED and
# mergeStateStatus=BLOCKED forever — pinned to commit A, which no longer exists.
# merge-skill.sh requires CLEAN, so the PR strands: green on the bead, red on
# GitHub, and nothing reconciles them.
#
# The fix retracts OUR OWN superseded review in the same step that stamps green,
# and — because removing a GitHub-side block is merge-triggering on a repo with no
# review requirement — records signoff_dismissed on the anchor so merge-skill.sh
# demands a real EXTERNAL approving review (that pairing is asserted in
# merge-skill.test.sh cases 15/15b/15c).
#
# This test EXECUTES the real snippet extracted verbatim from the template
# (between the `signoff-supersede-dismiss` markers) against stub gh/gc, so it
# cannot drift from the shipped instruction. No live city, Dolt, network, or PRs.
#
# Covered:
#   (A) superseded self-review at a dead commit -> DISMISSED, marker recorded
#   (B) the operator's CHANGES_REQUESTED -> NEVER dismissed (a human veto stands)
#   (C) self-review at the REVIEWED commit -> not dismissed (contradictory, hold)
#   (D) head moved past the reviewed commit -> nothing dismissed (would unblock
#       an unreviewed head)
#   (E) PRE-OPEN (review_branch set, no pr_number) -> no-op (no PR, no reviews)
#   (F) marker write FAILS -> dismissal skipped (never drop the block AND the
#       approval requirement together)
#   (G) ordering: signoff_dismissed is recorded BEFORE the dismissal call
#   (H) idempotence: an already-DISMISSED review is not re-dismissed
#   (I) multiple superseded self-reviews -> all dismissed
#   (J) the GATE-marker write fails -> dismissal skipped (nothing to trade for)
#   (K) the gate-marker write reports success but is NOT durable -> dismissal
#       skipped. The reason that guard is a read-back and not an exit status.
#   (L) native auto-merge ARMED -> dismissal skipped (it would merge server-side,
#       past the approval requirement this step records)
#   (M) the head moves AFTER the reviews listing -> nothing dismissed (the
#       re-read immediately before the irreversible call)
#   (N) the superseded review sits on PAGE 2 -> still found (the read paginates)
#   (O) happy path: check.<name> really is stamped green at the reviewed commit
#   (P) the auto-merge probe FAILS -> dismissal skipped (unreadable counts as
#       armed; a failed probe is indistinguishable from "disarmed" otherwise)
#   (Q) the auto-merge payload is MALFORMED or missing the key -> same
#   (R) auto-merge armed AFTER the up-front probe -> dismissal skipped (the
#       re-probe immediately before the irreversible call)
#   (S) signoff_dismissed reports success but is NOT durable -> dismissal skipped
#   (T) happy path: a durable marker really does let the dismissal through
#   (U) the anchor is under an operator merge_hold -> dismissal skipped (the gate
#       is still stamped; only the merge-triggering retraction waits), and (U2) an
#       explicitly-false hold is not a hold
#   (V) the gate marker cannot be recorded -> the review is NOT closed: it is
#       flagged for retry, re-routed to its own pool, and released LAST, so an
#       unmarked anchor always keeps an open child to raise the gate
#   (W) NO anchor resolves at all -> the same retry release as (V), because
#       "left open" while still claimed by a draining session is invisible to
#       every pool; (W2) with NO pool resolvable the route is left ALONE and the
#       claim is still released, but the retry is NOT reported as re-offered —
#       an unrouted bead is in no pool, so it is reported loudly with the repair
#       command instead; (W3) a live route consumed by the claim is restored from
#       the durable metadata.review_pool the dispatch stamped
#   (V2-V4) the release is READ BACK before the retry counts as re-offered: a
#       durable one is issued once (V2), one that reports success but persists
#       nothing is retried and then reported with the repair command (V3), and an
#       outright failing write is reported too (V4) — never swallowed by `|| true`
#   (V5-V6) the operator merge_hold is re-read immediately before EACH dismissal:
#       a hold set after the up-front check still stops the retraction (V5), and
#       an anchor that cannot be read counts as held (V6)
#   (V7-V10) and so is the anchor's FULL identity, mirroring the observer's own
#       pre-dismissal guard: an anchor that closed (V7), un-parked from
#       merge_result=pull_request (V8), moved to another pr_number (V9), or had
#       check.<gate> moved off / cleared from the reviewed head (V10) each stops
#       the retraction. Checking merge_hold alone let all four dismiss anyway
#   (V12-V14) and it resolves the anchor's PR the WIDE way, under every key a bead
#       names one with: a fork_pr-keyed (V12) or fork_pr_url-keyed (V13) anchor is
#       retracted for, where reading pr_number alone left it BLOCKED forever — while
#       a fork_pr_url naming another repository still holds (V14)
#   (V15-V17) the rest of that identity, mutated mid-step: a retarget (V15), a
#       pr_url moved to another PR (V16, with the cosmetic-difference control) and a
#       branch corrected off this PR (V17) each stop the retraction. None of the
#       three moves the head, so the head re-read cannot see them
#   (V11) the paginated reviews read is checked for FAILURE: a read that dies part
#       way streams a parseable but TRUNCATED history, and one that fails outright
#       looks like "nothing to retract" — both dismissed/stranded silently before
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TEMPLATE="$ROOT/template-fragments/polecat-non-impl-done.template.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gh stub -----------------------------------------------------------------
# Serves every call the snippet makes:
#   gh api user -q .login                      -> the acting handle ($FAKE_LOGIN)
#   gh pr view N --json headRefOid             -> the PR's LIVE head. Reads are
#       COUNTED: the snippet reads the head once up front and again immediately
#       before each dismissal, so $FAKE_HEAD_AFTER (when set) is returned from the
#       second read on — that is how the mid-step head move (L) is simulated.
#   gh pr view N --json autoMergeRequest       -> $FAKE_AUTOMERGE ('' = disarmed)
#   gh api [--paginate] .../reviews --jq '.[]' -> the review list ($FAKE_REVIEWS,
#       lines: id|login|state|commit_id[|page]). WITHOUT --paginate only page 1 is
#       served, exactly as real gh truncates at the first page — that is what lets
#       (M) prove the read is paginated. --jq '.[]' streams one object per line
#       (the snippet re-slurps with `jq -rs`), matching gh's NDJSON behaviour.
#   gh api -X PUT .../reviews/<id>/dismissals  -> RECORDS the dismissal (the seam)
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
# WHICH REPOSITORY each call was aimed at. A PR number names a different pull
# request in every repository, so a call that leaves the repository to gh's ambient
# context (the cwd's remote, $GH_REPO) is aimed at whatever that happens to be —
# and this snippet DISMISSES reviews, which cannot be undone once aimed wrong.
# `gh pr view` carries it as `--repo`; `gh api` carries it in the REST path, where
# an unpinned call reads the LITERAL `{owner}/{repo}` placeholders. Both are
# recorded so the assertions can demand a repository derived from the BEAD
# (review tk-78ty5 finding #4).
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  want=""; pin=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --json)     want="$2"; shift 2 ;;
      --repo|-R)  pin="$2"; shift 2 ;;
      *)          shift ;;
    esac
  done
  [ -n "${FAKE_VIEWPIN:-}" ] && printf '%s\n' "${pin:-<unpinned>}" >> "$FAKE_VIEWPIN"
  if [ "$want" = "autoMergeRequest" ]; then
    # The probe is READ three-valued (armed/disarmed/unknown), so the stub can
    # produce all three shapes plus the mid-step arming window:
    #   $FAKE_AUTOMERGE_FAILS      -> the probe FAILS (non-zero, no output)
    #   $FAKE_AUTOMERGE_MALFORMED  -> parseable-or-not payload WITHOUT the key
    #   $FAKE_AUTOMERGE_AFTER      -> disarmed on the first read, armed from the
    #                                 second on: auto-merge armed in the window
    #                                 between the up-front probe and the dismissal.
    # Auto-merge reads are counted separately from head reads — the snippet probes
    # both, and sharing one counter would make each case's staging depend on the
    # other's call order.
    [ -n "${FAKE_AUTOMERGE_FAILS:-}" ] && exit 1
    if [ -n "${FAKE_AUTOMERGE_MALFORMED:-}" ]; then
      printf '%s\n' "$FAKE_AUTOMERGE_MALFORMED"
      exit 0
    fi
    a=0
    [ -f "${FAKE_AM_READS:-/dev/null}" ] && a=$(cat "$FAKE_AM_READS")
    a=$((a + 1))
    [ -n "${FAKE_AM_READS:-}" ] && printf '%s' "$a" > "$FAKE_AM_READS"
    if [ "$a" -ge 2 ] && [ -n "${FAKE_AUTOMERGE_AFTER:-}" ]; then
      printf '{"autoMergeRequest":{"enabledAt":"%s"}}\n' "$FAKE_AUTOMERGE_AFTER"
    elif [ -n "${FAKE_AUTOMERGE:-}" ]; then
      printf '{"autoMergeRequest":{"enabledAt":"%s"}}\n' "$FAKE_AUTOMERGE"
    else
      printf '{"autoMergeRequest":null}\n'
    fi
    exit 0
  fi
  # headRefOid: count the read so a mid-step head move can be staged.
  n=0
  [ -f "${FAKE_HEAD_READS:-/dev/null}" ] && n=$(cat "$FAKE_HEAD_READS")
  n=$((n + 1))
  [ -n "${FAKE_HEAD_READS:-}" ] && printf '%s' "$n" > "$FAKE_HEAD_READS"
  livehead="${FAKE_HEAD:-}"
  if [ "$n" -ge 2 ] && [ -n "${FAKE_HEAD_AFTER:-}" ]; then
    livehead="$FAKE_HEAD_AFTER"
  fi
  # The pre-dismissal guard reads the PR's IDENTITY in the same round trip as its
  # head — `--json headRefOid,baseRefName,headRefName,url`, answered as one object
  # — so every comparison speaks about the same observation. The single-field
  # `-q .headRefOid` shape is still served bare, as gh does.
  case ",${want}," in
    *,baseRefName,*|*,headRefName,*|*,url,*)
      jq -nc --arg h "$livehead" \
             --arg b "${FAKE_PRVIEW_BASE-main}" \
             --arg r "${FAKE_PRVIEW_REF-polecat/tk-5niup}" \
             --arg u "${FAKE_PRVIEW_URL-https://github.com/acme/repo/pull/37}" \
        '{headRefOid: $h, baseRefName: $b, headRefName: $r, url: $u}' ;;
    *)
      printf '%s\n' "$livehead" ;;
  esac
  exit 0
fi
[ "$1" = "api" ] || exit 0
shift
METHOD=GET
PAGINATE=""
ARGS=()
PATH_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) METHOD="$2"; shift 2 ;;
    -f) ARGS+=("$2"); shift 2 ;;
    -q) shift 2 ;;
    --jq) shift 2 ;;
    --hostname) APIHOST="$2"; shift 2 ;;
    --paginate) PAGINATE=1; shift ;;
    *)  PATH_ARG="$1"; shift ;;
  esac
done
# THE HOST IS THE OTHER HALF OF THE REPOSITORY. A REST path carries `<owner>/<repo>`
# and no host at all, so `gh api` takes the host as `--hostname` and, when it is
# omitted, supplies it from $GH_HOST — meaning a repo-pinned path is still only
# HALF pinned. Recorded separately from the path so an assertion can demand both.
[ -n "${FAKE_APIHOST:-}" ] && printf '%s\n' "${APIHOST:-<unpinned>}" >> "$FAKE_APIHOST"
case "$PATH_ARG" in
  repos/*)
    apipin="${PATH_ARG#repos/}"
    apipin="$(printf '%s' "$apipin" | cut -d/ -f1,2)"
    [ -n "${FAKE_APIPIN:-}" ] && printf '%s\n' "$apipin" >> "$FAKE_APIPIN" ;;
esac
case "$PATH_ARG" in
  user)
    printf '%s\n' "${FAKE_LOGIN:-}" ;;
  */reviews|*/reviews\?*)
    # $FAKE_REVIEWS_FAIL stages a PAGINATED read that DIES PART WAY: the pages
    # already fetched are still streamed (so the output parses perfectly) and the
    # call THEN exits non-zero, which is the only signal that the tail is missing.
    while IFS='|' read -r rid login state cid page; do
      [ -n "$rid" ] || continue
      [ -n "$page" ] || page=1
      if [ -n "${FAKE_REVIEWS_FAIL:-}" ]; then
        [ "$page" = "1" ] || continue
      else
        [ -n "$PAGINATE" ] || [ "$page" = "1" ] || continue
      fi
      printf '{"id":%s,"user":{"login":"%s"},"state":"%s","commit_id":"%s"}\n' \
        "$rid" "$login" "$state" "$cid"
    done < "$FAKE_REVIEWS"
    [ -z "${FAKE_REVIEWS_FAIL:-}" ] || exit 1 ;;
  */dismissals)
    [ "$METHOD" = "PUT" ] || exit 1
    rid="${PATH_ARG%/dismissals}"; rid="${rid##*/}"
    printf '%s\t%s\n' "$rid" "${ARGS[*]:-}" >> "$FAKE_DISMISSED" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- gc stub -----------------------------------------------------------------
# Two seams, because the snippet writes two different markers:
#
#   gc bd update <anchor> --set-metadata check.<name>=green@<oid>
#       The gate stamp. Persisted to $FAKE_CHECKS so the snippet's read-back can
#       see it. $FAKE_CHECK_FAILS makes the write fail outright; the subtler
#       $FAKE_CHECK_NOT_DURABLE makes it report SUCCESS and store nothing — the
#       exact case the read-back exists for, and one a bare exit status misses.
#   gc bd show <anchor> --json
#       Serves BOTH stores back as bead metadata, for both read-backs.
#   gc bd update <anchor> --set-metadata signoff_dismissed=...
#       Recorded in call order into $FAKE_MARKED; $FAKE_MARK_FAILS fails it (F),
#       and $FAKE_MARK_NOT_DURABLE makes it report SUCCESS while storing nothing —
#       the pairing marker's version of the same non-durable write (S).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || exit 0
if [ "$2" = "show" ]; then
  want="$3"
  # The REVIEW bead answers with its own claim state and routing: the retry helper
  # reads gc.routed_to off it to put it back in the pool it came from, and then
  # READS BACK status/assignee/route to prove the release was durable. The claim
  # state lives in $FAKE_CLAIM ("status|assignee"), which the release write below
  # updates — or, when a case stages a non-durable/failing release, does not.
  if [ -n "${REVIEW_BEAD:-}" ] && [ "$want" = "$REVIEW_BEAD" ]; then
    r_status="in_progress"; r_assignee="gc-toolkit__polecat-codex-lx-1"
    if [ -f "${FAKE_CLAIM:-/dev/null}" ] && [ -s "$FAKE_CLAIM" ]; then
      IFS='|' read -r r_status r_assignee < "$FAKE_CLAIM"
    fi
    r_route="${FAKE_REVIEW_POOL:-}"
    if [ -f "${FAKE_ROUTE:-/dev/null}" ] && [ -s "$FAKE_ROUTE" ]; then
      r_route=$(cat "$FAKE_ROUTE")
    fi
    # metadata.review_pool is the DURABLE copy of the route the dispatch stamps
    # alongside gc.routed_to. Staged separately from the live route so a case can
    # model the real shape of the bug: a review whose working route is GONE (claim
    # consumed it / a route write was dropped) but whose dispatch pool is still on
    # the bead, which is what the retry falls back to. It is also STATEFUL, like
    # $FAKE_ROUTE: the retry writes this field now, and both the read-back and a
    # SECOND retry cycle have to see what the first one actually persisted.
    r_pool="${FAKE_REVIEW_POOL_DURABLE:-}"
    if [ -f "${FAKE_POOL:-/dev/null}" ] && [ -s "$FAKE_POOL" ]; then
      r_pool=$(cat "$FAKE_POOL")
    fi
    printf '[{"status":"%s","assignee":"%s","metadata":{"gc.routed_to":"%s","review_pool":"%s"}}]\n' \
      "$r_status" "$r_assignee" "$r_route" "$r_pool"
    exit 0
  fi
  # Anchor reads are COUNTED, because the snippet reads the anchor several times
  # (gate read-back, up-front merge_hold, the per-dismissal hold re-read, the
  # pairing read-back) and the mid-step races are staged by call ordinal:
  #   $FAKE_ANCHOR_SHOW_FAIL_FROM=<n> -> the read returns NOTHING from call n on
  #                                      (an unreadable anchor mid-loop)
  #   $FAKE_MERGE_HOLD_FROM=<n>       -> merge_hold appears from call n on (an
  #                                      operator parking the anchor mid-step)
  ashow=0
  [ -f "${FAKE_ANCHOR_SHOWS:-/dev/null}" ] && ashow=$(cat "$FAKE_ANCHOR_SHOWS")
  ashow=$((ashow + 1))
  [ -n "${FAKE_ANCHOR_SHOWS:-}" ] && printf '%s' "$ashow" > "$FAKE_ANCHOR_SHOWS"
  if [ -n "${FAKE_ANCHOR_SHOW_FAIL_FROM:-}" ] \
     && [ "$ashow" -ge "$FAKE_ANCHOR_SHOW_FAIL_FROM" ]; then
    exit 0
  fi
  hold="${FAKE_MERGE_HOLD:-}"
  if [ -n "${FAKE_MERGE_HOLD_FROM:-}" ] && [ "$ashow" -ge "$FAKE_MERGE_HOLD_FROM" ]; then
    hold="${FAKE_MERGE_HOLD_LATE:-true}"
  fi
  chk=""; mark=""
  [ -f "${FAKE_CHECKS:-/dev/null}" ] && chk=$(cat "$FAKE_CHECKS")
  [ -f "${FAKE_MARKED:-/dev/null}" ] && mark=$(cut -f2 "$FAKE_MARKED" | tail -1)
  # The rest of the anchor IDENTITY the per-dismissal guard requires. Defaults are
  # the shape the arm decided about — open, parked on this PR, gate green at the
  # reviewed head — and each is independently movable from a chosen call ordinal,
  # the same way $FAKE_MERGE_HOLD_FROM moves the operator gate:
  #   $FAKE_ANCHOR_STATUS_FROM=<n>  -> status becomes $FAKE_ANCHOR_STATUS_LATE
  #   $FAKE_ANCHOR_RESULT_FROM=<n>  -> merge_result becomes $FAKE_ANCHOR_RESULT_LATE
  #   $FAKE_ANCHOR_PR_FROM=<n>      -> pr_number becomes $FAKE_ANCHOR_PR_LATE
  #   $FAKE_CHECK_MOVED_FROM=<n>    -> check.<gate> becomes $FAKE_CHECK_MOVED_LATE
  # Ordinal 3 is the per-dismissal re-read (1 = gate read-back, 2 = the up-front
  # hold read, 4 = the pairing read-back).
  a_status="open"
  if [ -n "${FAKE_ANCHOR_STATUS_FROM:-}" ] && [ "$ashow" -ge "$FAKE_ANCHOR_STATUS_FROM" ]; then
    a_status="${FAKE_ANCHOR_STATUS_LATE:-closed}"
  fi
  a_result="pull_request"
  if [ -n "${FAKE_ANCHOR_RESULT_FROM:-}" ] && [ "$ashow" -ge "$FAKE_ANCHOR_RESULT_FROM" ]; then
    a_result="${FAKE_ANCHOR_RESULT_LATE:-}"
  fi
  a_pr="${PR_NUMBER:-}"
  if [ -n "${FAKE_ANCHOR_PR_FROM:-}" ] && [ "$ashow" -ge "$FAKE_ANCHOR_PR_FROM" ]; then
    a_pr="${FAKE_ANCHOR_PR_LATE:-}"
  fi
  if [ -n "${FAKE_CHECK_MOVED_FROM:-}" ] && [ "$ashow" -ge "$FAKE_CHECK_MOVED_FROM" ]; then
    chk="${FAKE_CHECK_MOVED_LATE:-}"
  fi
  # WHICH KEY the anchor names its PR under. `pr_number` is what the refinery
  # stamps, but the fork-sync flow stamps `fork_pr`/`fork_pr_url` and NO pr_number
  # at all — a shape the guard must resolve identically or the dismissal never
  # runs for a fork-keyed anchor. `fork_pr_url` carries its repository in its own
  # value, so it is emitted host-qualified against $PR_REPO_Q.
  a_key="${FAKE_ANCHOR_PR_KEY:-pr_number}"
  # The rest of the anchor's IDENTITY. Absent by default (an anchor that records
  # none of these is governed by the pinned read alone), and each independently
  # movable from a chosen call ordinal like the fields above:
  #   $FAKE_ANCHOR_TARGET / _FROM / _LATE  -> merged_target, a mid-step RETARGET
  #   $FAKE_ANCHOR_PRURL  / _FROM / _LATE  -> pr_url, a mid-step identity repair
  #   $FAKE_ANCHOR_BRANCH / _FROM / _LATE  -> branch, a mid-step branch correction
  # None of the three moves the PR head, so the head re-read cannot catch them —
  # which is exactly why the guard has to ask.
  a_target="${FAKE_ANCHOR_TARGET:-}"
  if [ -n "${FAKE_ANCHOR_TARGET_FROM:-}" ] && [ "$ashow" -ge "$FAKE_ANCHOR_TARGET_FROM" ]; then
    a_target="${FAKE_ANCHOR_TARGET_LATE:-}"
  fi
  a_prurl="${FAKE_ANCHOR_PRURL:-}"
  if [ -n "${FAKE_ANCHOR_PRURL_FROM:-}" ] && [ "$ashow" -ge "$FAKE_ANCHOR_PRURL_FROM" ]; then
    a_prurl="${FAKE_ANCHOR_PRURL_LATE:-}"
  fi
  a_branch="${FAKE_ANCHOR_BRANCH:-}"
  if [ -n "${FAKE_ANCHOR_BRANCH_FROM:-}" ] && [ "$ashow" -ge "$FAKE_ANCHOR_BRANCH_FROM" ]; then
    a_branch="${FAKE_ANCHOR_BRANCH_LATE:-}"
  fi
  sep=""
  printf '[{"status":"%s","metadata":{' "$a_status"
  if [ -n "$chk" ]; then printf '"check.%s":"%s"' "${CHECK_NAME:-codex}" "$chk"; sep=","; fi
  if [ -n "$mark" ]; then printf '%s"signoff_dismissed":"%s"' "$sep" "$mark"; sep=","; fi
  # The operator gate, served only when a case stages it ($FAKE_MERGE_HOLD).
  if [ -n "$hold" ]; then printf '%s"merge_hold":"%s"' "$sep" "$hold"; sep=","; fi
  if [ -n "$a_result" ]; then printf '%s"merge_result":"%s"' "$sep" "$a_result"; sep=","; fi
  if [ -n "$a_target" ]; then printf '%s"merged_target":"%s"' "$sep" "$a_target"; sep=","; fi
  if [ -n "$a_prurl" ]; then printf '%s"pr_url":"%s"' "$sep" "$a_prurl"; sep=","; fi
  if [ -n "$a_branch" ]; then printf '%s"branch":"%s"' "$sep" "$a_branch"; sep=","; fi
  if [ -n "$a_pr" ]; then
    case "$a_key" in
      fork_pr_url) printf '%s"fork_pr_url":"https://%s/pull/%s"' \
                     "$sep" \
                     "${FAKE_ANCHOR_FORK_REPO:-${PR_REPO_Q:-github.com/acme/repo}}" \
                     "$a_pr" ;;
      *)           printf '%s"%s":"%s"' "$sep" "$a_key" "$a_pr" ;;
    esac
  fi
  printf '}}]\n'
  exit 0
fi
[ "$2" = "update" ] || exit 0
anchor="$3"
# Every update is logged verbatim (id + args) so the retry path — which writes to
# the REVIEW bead, not the anchor — can be asserted on.
[ -n "${FAKE_UPDATES:-}" ] && printf '%s\n' "$*" >> "$FAKE_UPDATES"
# The retry helper's two writes against the REVIEW bead are STATEFUL here, because
# the helper reads them back: the route write updates $FAKE_ROUTE and the release
# updates $FAKE_CLAIM, so a later `bd show` reflects them.
#   $FAKE_RELEASE_FAILS        -> the release write fails outright (non-zero)
#   $FAKE_RELEASE_NOT_DURABLE  -> it reports SUCCESS and persists nothing (the
#                                 case an exit-status check cannot see)
if [ -n "${REVIEW_BEAD:-}" ] && [ "$anchor" = "$REVIEW_BEAD" ]; then
  case "$*" in
    *"--status=open --assignee="*)
      [ -n "${FAKE_RELEASE_FAILS:-}" ] && exit 1
      [ -n "${FAKE_RELEASE_NOT_DURABLE:-}" ] && exit 0
      [ -n "${FAKE_CLAIM:-}" ] && printf 'open|' > "$FAKE_CLAIM"
      exit 0 ;;
    *"gc.routed_to="*)
      # Join FIRST: ${*##pat} strips the pattern from each positional parameter
      # individually, so it would yield the (unmatched) first arg, not the value.
      all="$*"; route="${all##*gc.routed_to=}"; route="${route%% *}"
      [ -n "${FAKE_ROUTE:-}" ] && printf '%s' "$route" > "$FAKE_ROUTE"
      # The DURABLE half of the same write. $FAKE_POOL_NOT_DURABLE makes it report
      # SUCCESS and persist nothing — the asymmetric drop that leaves the review
      # claimable exactly once, which is the failure the read-back has to catch.
      case "$all" in
        *"review_pool="*)
          pool="${all##*review_pool=}"; pool="${pool%% *}"
          [ -n "${FAKE_POOL:-}" ] && [ -z "${FAKE_POOL_NOT_DURABLE:-}" ] \
            && printf '%s' "$pool" > "$FAKE_POOL" ;;
      esac
      exit 0 ;;
  esac
fi
check=""; val=""
for a in "$@"; do
  case "$a" in
    check.*=*)            check="${a#*=}" ;;
    signoff_dismissed=*)  val="${a#signoff_dismissed=}" ;;
  esac
done
if [ -n "$check" ]; then
  [ -n "${FAKE_CHECK_FAILS:-}" ] && exit 1
  [ -n "${FAKE_CHECK_NOT_DURABLE:-}" ] && exit 0
  printf '%s' "$check" > "$FAKE_CHECKS"
  exit 0
fi
[ -n "$val" ] || exit 0
[ -n "${FAKE_MARK_FAILS:-}" ] && exit 1
[ -n "${FAKE_MARK_NOT_DURABLE:-}" ] && exit 0
printf '%s\t%s\n' "$anchor" "$val" >> "$FAKE_MARKED"
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- Extract the REAL snippet from the template. ------------------------------
# If the markers or the snippet are removed/renamed, extraction yields nothing
# and the guard below fails loudly — the contract cannot silently disappear.
SNIPPET="$(awk '
  /# >>> signoff-supersede-dismiss/ {f=1; next}
  /# <<< signoff-supersede-dismiss/ {f=0}
  f' "$TEMPLATE")"

[ -n "$SNIPPET" ] \
  && ok "snippet extracted between signoff-supersede-dismiss markers" \
  || bad "snippet extraction EMPTY — markers missing from $TEMPLATE"

# The retry-release helper is defined ONCE in the template, ABOVE both arms that
# call it (the unrecorded-stamp arm inside this snippet, and the no-anchor arm
# below), so it carries its own markers and is prepended to both runners — the
# same shape the real done sequence has, where the function is defined earlier in
# the fragment and both arms are in its scope. Extracting it separately is also
# what keeps "one helper, two callers" honest: a second open-coded copy would not
# be exercised by either runner.
HELPER="$(awk '
  /# >>> signoff-retry-release/ {f=1; next}
  /# <<< signoff-retry-release/ {f=0}
  f' "$TEMPLATE")"

[ -n "$HELPER" ] \
  && ok "retry-release helper extracted between signoff-retry-release markers" \
  || bad "retry-release helper extraction EMPTY — markers missing from $TEMPLATE"

# The snippet runs inside the done-sequence's `if [ -n "$ANCHOR" ]` block, NOT
# under set -e (the polecat runs it exactly this way).
# SIGNOFF_UNRECORDED is the snippet's OUTPUT to the surrounding done-sequence
# ("do not close this review bead"), so it is captured the same way the anchor
# resolution test captures ANCHOR: echoed after the snippet body.
{ printf '%s\n' "$HELPER"
  printf '%s\n' "$SNIPPET"
  printf 'printf "%%s" "${SIGNOFF_UNRECORDED:-}" > "$FAKE_UNRECORDED"\n'; } > "$TMP/run.sh"

# run <reviews-fixture> <reviewed-oid> <live-head> <pr-number> <review-branch>
run() {
  : > "$TMP/dismissed"; : > "$TMP/marked"; : > "$TMP/checks"; printf '0' > "$TMP/headreads"
  printf '0' > "$TMP/amreads"; : > "$TMP/updates"; : > "$TMP/unrecorded"
  printf '0' > "$TMP/anchorshows"; : > "$TMP/claim"; : > "$TMP/route"; : > "$TMP/pool"
  : > "$TMP/viewpin"; : > "$TMP/apipin"; : > "$TMP/apihost"
  cat > "$TMP/reviews" <<< "$1"
  PATH="$TMP/bin:$PATH" \
  FAKE_REVIEWS="$TMP/reviews" FAKE_DISMISSED="$TMP/dismissed" FAKE_MARKED="$TMP/marked" \
  FAKE_CHECKS="$TMP/checks" FAKE_HEAD_READS="$TMP/headreads" FAKE_AM_READS="$TMP/amreads" \
  FAKE_UPDATES="$TMP/updates" FAKE_UNRECORDED="$TMP/unrecorded" \
  FAKE_ANCHOR_SHOWS="$TMP/anchorshows" FAKE_CLAIM="$TMP/claim" FAKE_ROUTE="$TMP/route" \
  FAKE_POOL="$TMP/pool" \
  FAKE_MERGE_HOLD="${FAKE_MERGE_HOLD:-}" FAKE_REVIEW_POOL="rig/rig.polecat-codex" \
  FAKE_MERGE_HOLD_FROM="${FAKE_MERGE_HOLD_FROM:-}" \
  FAKE_MERGE_HOLD_LATE="${FAKE_MERGE_HOLD_LATE:-}" \
  FAKE_ANCHOR_SHOW_FAIL_FROM="${FAKE_ANCHOR_SHOW_FAIL_FROM:-}" \
  FAKE_ANCHOR_STATUS_FROM="${FAKE_ANCHOR_STATUS_FROM:-}" \
  FAKE_ANCHOR_STATUS_LATE="${FAKE_ANCHOR_STATUS_LATE:-}" \
  FAKE_ANCHOR_RESULT_FROM="${FAKE_ANCHOR_RESULT_FROM:-}" \
  FAKE_ANCHOR_RESULT_LATE="${FAKE_ANCHOR_RESULT_LATE:-}" \
  FAKE_ANCHOR_PR_FROM="${FAKE_ANCHOR_PR_FROM:-}" \
  FAKE_ANCHOR_PR_LATE="${FAKE_ANCHOR_PR_LATE:-}" \
  FAKE_CHECK_MOVED_FROM="${FAKE_CHECK_MOVED_FROM:-}" \
  FAKE_CHECK_MOVED_LATE="${FAKE_CHECK_MOVED_LATE:-}" \
  FAKE_REVIEWS_FAIL="${FAKE_REVIEWS_FAIL:-}" \
  FAKE_RELEASE_FAILS="${FAKE_RELEASE_FAILS:-}" \
  FAKE_RELEASE_NOT_DURABLE="${FAKE_RELEASE_NOT_DURABLE:-}" \
  REVIEW_BEAD="review-1" \
  FAKE_LOGIN="zook-bot" FAKE_HEAD="$3" FAKE_MARK_FAILS="${FAKE_MARK_FAILS:-}" \
  FAKE_MARK_NOT_DURABLE="${FAKE_MARK_NOT_DURABLE:-}" \
  FAKE_CHECK_FAILS="${FAKE_CHECK_FAILS:-}" \
  FAKE_CHECK_NOT_DURABLE="${FAKE_CHECK_NOT_DURABLE:-}" \
  FAKE_AUTOMERGE="${FAKE_AUTOMERGE:-}" FAKE_HEAD_AFTER="${FAKE_HEAD_AFTER:-}" \
  FAKE_AUTOMERGE_FAILS="${FAKE_AUTOMERGE_FAILS:-}" \
  FAKE_AUTOMERGE_MALFORMED="${FAKE_AUTOMERGE_MALFORMED:-}" \
  FAKE_AUTOMERGE_AFTER="${FAKE_AUTOMERGE_AFTER:-}" \
  FAKE_VIEWPIN="$TMP/viewpin" FAKE_APIPIN="$TMP/apipin" FAKE_APIHOST="$TMP/apihost" \
  FAKE_PRVIEW_BASE="${FAKE_PRVIEW_BASE-main}" \
  FAKE_PRVIEW_REF="${FAKE_PRVIEW_REF-polecat/tk-5niup}" \
  FAKE_PRVIEW_URL="${FAKE_PRVIEW_URL-https://github.com/acme/repo/pull/37}" \
  FAKE_ANCHOR_PR_KEY="${FAKE_ANCHOR_PR_KEY-pr_number}" \
  FAKE_ANCHOR_FORK_REPO="${FAKE_ANCHOR_FORK_REPO-}" \
  FAKE_ANCHOR_TARGET="${FAKE_ANCHOR_TARGET-}" \
  FAKE_ANCHOR_TARGET_FROM="${FAKE_ANCHOR_TARGET_FROM-}" \
  FAKE_ANCHOR_TARGET_LATE="${FAKE_ANCHOR_TARGET_LATE-}" \
  FAKE_ANCHOR_PRURL="${FAKE_ANCHOR_PRURL-}" \
  FAKE_ANCHOR_PRURL_FROM="${FAKE_ANCHOR_PRURL_FROM-}" \
  FAKE_ANCHOR_PRURL_LATE="${FAKE_ANCHOR_PRURL_LATE-}" \
  FAKE_ANCHOR_BRANCH="${FAKE_ANCHOR_BRANCH-}" \
  FAKE_ANCHOR_BRANCH_FROM="${FAKE_ANCHOR_BRANCH_FROM-}" \
  FAKE_ANCHOR_BRANCH_LATE="${FAKE_ANCHOR_BRANCH_LATE-}" \
  ANCHOR="anchor-1" CHECK_NAME="codex" \
  PR_NUMBER="$4" REVIEW_BRANCH="$5" REVIEWED_OID="$2" REVIEW_HANDLE="" \
  PR_REPO_Q="${PR_REPO_Q-github.com/acme/repo}" PR_REPO="${PR_REPO-acme/repo}" \
  PR_HOST="${PR_HOST-github.com}" \
    bash "$TMP/run.sh" 2>"$TMP/err"
}
# Every `--repo` pin the snippet passed, and every repository its REST paths named,
# deduplicated. "github.com/acme/repo" / "acme/repo" is the bead-derived answer;
# "<unpinned>" or "{owner}/{repo}" is a call that left the repository to gh.
view_pins() { sort -u "$TMP/viewpin" | tr '\n' ' ' | sed 's/ $//'; }
api_pins()  { sort -u "$TMP/apipin"  | tr '\n' ' ' | sed 's/ $//'; }
dismissed_ids() { cut -f1 "$TMP/dismissed" | sort | tr '\n' ' ' | sed 's/ $//'; }

# (A) THE BUG: our own CHANGES_REQUESTED pinned to the DEAD commit A, while the
#     re-gate passed at the live head B. Pre-fix nothing retracted it and the PR
#     was BLOCKED forever; now it is dismissed and the pairing marker recorded.
run '900|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "900" "(A) superseded self-review at a dead commit -> dismissed"
eq "$(cut -f2 "$TMP/marked")" "900@liveheadB" \
   "(A) signoff_dismissed recorded on the anchor (arms merge-skill's approval gate)"
eq "$(cut -f1 "$TMP/marked")" "anchor-1" "(A) marker written to the resolved ANCHOR"

# (B) SAFETY: the operator's CHANGES_REQUESTED must NEVER be dismissed, even
#     though it too sits at a superseded commit. Live shape: gc-toolkit PR#80's
#     block is johnzook's, not the city's. Dismissing it would erase a human veto.
run '800|johnzook|CHANGES_REQUESTED|deadcommitA
901|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "901" "(B) human CHANGES_REQUESTED left standing; only our own retracted"

# (C) Our own CHANGES_REQUESTED at the SAME commit we just passed: contradictory,
#     so the block stands (fail-closed) rather than being retracted.
run '902|zook-bot|CHANGES_REQUESTED|liveheadB' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(C) self-review at the reviewed commit -> NOT dismissed"
eq "$(wc -l < "$TMP/marked" | tr -d ' ')" "0" "(C) no marker written when nothing is retracted"

# (D) The head moved AFTER our signoff. Dismissing here would unblock a commit
#     nobody reviewed — the same stale-head hazard the green@<oid> marker guards.
run '903|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'headMOVEDc' '37' ''
eq "$(dismissed_ids)" "" "(D) head moved past the reviewed commit -> nothing dismissed"

# (E) PRE-OPEN: review_branch set and no pr_number — there is no PR and no review
#     to retract, so the whole step is a no-op.
run '904|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '' 'polecat/tk-1'
eq "$(dismissed_ids)" "" "(E) pre-open (review_branch, no pr_number) -> no-op"

# (F) FAIL-CLOSED ORDERING: the marker write fails. The dismissal must NOT run —
#     dropping the GitHub block while failing to record the approval requirement
#     is the one combination that can merge unapproved work.
FAKE_MARK_FAILS=1 run '905|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(F) marker write fails -> dismissal SKIPPED (never lose block + requirement)"
grep -q 'NOT dismissing review 905' "$TMP/err" \
  && ok "(F) skip is reported, naming the review left in place" \
  || bad "(F) skip must warn (got: $(cat "$TMP/err"))"

# (G) ORDERING is structural, not incidental: the marker write is what GATES the
#     dismissal, so it must appear before the dismissals call in the snippet.
MARK_LINE=$(printf '%s\n' "$SNIPPET" | grep -n 'set-metadata signoff_dismissed' | head -1 | cut -d: -f1)
DISMISS_LINE=$(printf '%s\n' "$SNIPPET" | grep -n 'reviews/\$RID/dismissals' | head -1 | cut -d: -f1)
{ [ -n "$MARK_LINE" ] && [ -n "$DISMISS_LINE" ] && [ "$MARK_LINE" -lt "$DISMISS_LINE" ]; } \
  && ok "(G) signoff_dismissed is recorded BEFORE the dismissal call" \
  || bad "(G) marker must precede the dismissal (mark=$MARK_LINE dismiss=$DISMISS_LINE)"

# (H) IDEMPOTENCE: a review we already dismissed reports state DISMISSED, so a
#     re-run of the re-gate does not re-dismiss it (or re-stamp the marker).
run '906|zook-bot|DISMISSED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(H) already-DISMISSED review is not re-dismissed (idempotent re-gate)"

# (I) Several rounds of changes leave several superseded self-reviews; all are
#     retracted, since any one of them keeps reviewDecision=CHANGES_REQUESTED.
run '907|zook-bot|CHANGES_REQUESTED|deadcommitA
908|zook-bot|CHANGES_REQUESTED|deadcommitB
909|zook-bot|COMMENTED|deadcommitB' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "907 908" "(I) every superseded self-review dismissed; COMMENTED untouched"

# (J) The gate stamp is the thing the retraction TRADES FOR. If its write fails
#     outright there is nothing on the other side of the trade, so the block must
#     stay: dismissing here would drop the GitHub block AND leave no recorded gate.
FAKE_CHECK_FAILS=1 run '910|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(J) gate-marker write fails -> dismissal SKIPPED (nothing to trade for)"
grep -q 'did not stick on anchor anchor-1' "$TMP/err" \
  && ok "(J) the unrecorded gate is reported before anything is retracted" \
  || bad "(J) failed gate stamp must warn (got: $(cat "$TMP/err"))"

# (K) The subtle half of the same guard, and the reason it is a READ-BACK rather
#     than an exit-status check: the write REPORTS SUCCESS but is not durable.
#     `|| true` makes success and failure indistinguishable downstream, so only
#     reading the marker back can tell the retraction it is safe to proceed.
FAKE_CHECK_NOT_DURABLE=1 run '911|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(K) gate stamp reports success but did not persist -> dismissal SKIPPED"
eq "$(wc -l < "$TMP/marked" | tr -d ' ')" "0" "(K) no signoff_dismissed recorded on an unrecorded gate"
grep -q "want 'green@liveheadB'" "$TMP/err" \
  && ok "(K) the read-back names the marker it expected and did not find" \
  || bad "(K) non-durable gate stamp must warn (got: $(cat "$TMP/err"))"

# (L) NATIVE AUTO-MERGE. With `gh pr merge --auto` armed, dropping the last block
#     does not PERMIT a merge, it PERFORMS one — server-side, before merge-skill.sh
#     ever reads signoff_dismissed. That marker binds our own skill, never GitHub,
#     so the requirement recorded here cannot hold the merge. Fail closed.
FAKE_AUTOMERGE="2026-07-31T00:00:00Z" run '912|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(L) native auto-merge armed -> dismissal SKIPPED (fail-closed)"
grep -q 'auto-merge ARMED' "$TMP/err" \
  && ok "(L) the auto-merge hold is reported with the disarm instruction" \
  || bad "(L) auto-merge hold must warn (got: $(cat "$TMP/err"))"

# (M) HEAD MOVED MID-STEP. The reviews listing is a snapshot taken after the
#     up-front head check. If the head advances between them, a review in that
#     listing may be a FRESH block on the NEW head, and against a stale
#     REVIEWED_OID the commit_id filter reads it as superseded — retracting a live
#     veto. The re-read immediately before the irreversible call is what stops it.
#     (Distinct from (D), where the head had already moved before the step began.)
FAKE_HEAD_AFTER="headMOVEDc" run '913|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(M) head moves after the listing -> nothing dismissed (re-read guard)"
grep -q 'head moved (liveheadB -> headMOVEDc) mid-step' "$TMP/err" \
  && ok "(M) the mid-step head move is reported, naming both commits" \
  || bad "(M) mid-step head move must warn (got: $(cat "$TMP/err"))"

# (N) PAGINATION. GitHub pages this endpoint at 30, and a PR that took a changes
#     round — the only kind this step fires on — is exactly the PR whose reviews
#     spill past page one. The stub serves page 2 ONLY for a --paginate read, so
#     an unpaginated read would see just the COMMENTED review, retract nothing,
#     and strand the PR in the very state this step exists to heal.
run '914|zook-bot|COMMENTED|liveheadB|1
915|zook-bot|CHANGES_REQUESTED|deadcommitA|2' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "915" "(N) superseded review on page 2 is found and retracted (read is paginated)"

# (O) The positive half of guard 0: on the happy path the gate marker really is
#     stamped at the commit that was reviewed, which is what merge-skill.sh later
#     matches against the live head.
run '916|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(cat "$TMP/checks")" "green@liveheadB" \
   "(O) check.codex stamped green at the REVIEWED commit before any retraction"

# (P) The auto-merge probe FAILS (API error, auth, rate limit). Read through a
#     `// empty` filter that is INDISTINGUISHABLE from `autoMergeRequest: null`,
#     so the guard that exists to stop a server-side merge would clear itself on
#     an answer it never got. Unreadable must count as armed.
FAKE_AUTOMERGE_FAILS=1 run '917|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(P) auto-merge probe FAILS -> dismissal SKIPPED (unreadable counts as armed)"
grep -q 'auto-merge state is UNREADABLE' "$TMP/err" \
  && ok "(P) the unreadable probe is reported as the reason, not silently ignored" \
  || bad "(P) failed auto-merge probe must warn (got: $(cat "$TMP/err"))"

# (Q) The same fail-open shape from a MALFORMED payload rather than a failed call:
#     a truncated/garbled body, or valid JSON that simply does not carry the key
#     (a schema change, a `gh` too old to know the field). `.autoMergeRequest //
#     empty` yields "" for all of them. The guard demands the key be PRESENT in a
#     parseable object, so each is unknown -> held.
for MALFORMED in 'not json at all' '{"autoMergeRequest":' '{}' '[]'; do
  FAKE_AUTOMERGE_MALFORMED="$MALFORMED" \
    run '918|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
  eq "$(dismissed_ids)" "" "(Q) malformed auto-merge payload '$MALFORMED' -> dismissal SKIPPED"
done

# (R) TOCTOU. The up-front probe answered "disarmed" honestly, and then an
#     operator armed auto-merge before the dismissal landed. A one-time probe
#     cannot see that window; the re-probe immediately before the irreversible
#     call — after the live-head re-read, same placement and same reason — can.
FAKE_AUTOMERGE_AFTER="2026-08-01T00:00:00Z" \
  run '919|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(R) auto-merge armed after the up-front probe -> dismissal SKIPPED"
grep -q "auto-merge state is 'armed' immediately before dismissing review 919" "$TMP/err" \
  && ok "(R) the mid-step arming is reported, naming the review left in place" \
  || bad "(R) mid-step auto-merge arming must warn (got: $(cat "$TMP/err"))"

# (S) The pairing marker's half of (K), and the reason THIS write is read back
#     too: `gc bd update` reports success and stores nothing. Pre-fix the exit
#     status said "recorded", the dismissal ran, and the PR lost its GitHub block
#     while merge-skill.sh saw no signoff_dismissed and therefore demanded no
#     external approval — block and requirement gone together, the one
#     combination that lands unreviewed work.
FAKE_MARK_NOT_DURABLE=1 run '920|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(S) signoff_dismissed reports success but did not persist -> dismissal SKIPPED"
grep -q "want '920@liveheadB'" "$TMP/err" \
  && ok "(S) the read-back names the pairing marker it expected and did not find" \
  || bad "(S) non-durable signoff_dismissed must warn (got: $(cat "$TMP/err"))"

# (T) The positive half of (S): on the happy path the dismissal is preceded by a
#     marker that is really readable back, so the trade the retraction makes —
#     GitHub block out, recorded approval requirement in — actually holds.
run '921|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "921" "(T) durable marker -> dismissal proceeds (the guard is not simply always-hold)"
eq "$(cut -f2 "$TMP/marked")" "921@liveheadB" \
   "(T) the marker read back is the one this dismissal recorded"
eq "$(cat "$TMP/unrecorded")" "" \
   "(T) a recorded gate does NOT flag the review for a retry (no over-trigger)"

# (U) OPERATOR MERGE_HOLD. Retraction removes a GitHub-side merge block, which is
#     merge-triggering on a repo with no review requirement — precisely the
#     pipeline work an operator's merge_hold says to stop. reconcile-merged-prs.sh
#     already skips its retraction arm while held; this step runs in the same
#     anchor state and must make the same call. The gate marker is still stamped
#     (recording the signoff is not merge-triggering); only the retraction waits.
FAKE_MERGE_HOLD=true run '922|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(U) anchor under operator merge_hold -> dismissal SKIPPED"
eq "$(cat "$TMP/checks")" "green@liveheadB" \
   "(U) the gate marker is still stamped while held (only the retraction waits)"
grep -q 'merge_hold=true (operator gate)' "$TMP/err" \
  && ok "(U) the hold is reported, naming the operator gate" \
  || bad "(U) merge_hold skip must warn (got: $(cat "$TMP/err"))"
# (U2) and an explicitly-false hold is NOT a hold — a stale merge_hold=false must
#      not freeze the re-gate forever.
FAKE_MERGE_HOLD=false run '923|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "923" "(U2) merge_hold=false is not a hold -> dismissal proceeds"

# (V) THE UNRECORDED-GATE STRAND. When the marker cannot be recorded, the review
#     must NOT be closed: the anchor keeps its check_set, so merge-skill.sh holds
#     the merge (pre-open: no PR opens) while check-set-heal.sh — which repairs an
#     EMPTY check_set, not a missing marker under a normal one — leaves it alone.
#     Closed, nothing re-raises the gate and the PR strands silently. The snippet
#     flags the retry, re-routes the bead to its own pool, and releases the claim.
FAKE_CHECK_NOT_DURABLE=1 run '924|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(cat "$TMP/unrecorded")" "1" \
   "(V) unrecorded gate -> SIGNOFF_UNRECORDED set (the done-sequence skips the close)"
grep -q 'update review-1 .*signoff_retry=' "$TMP/updates" \
  && ok "(V) the retry reason is recorded on the REVIEW bead" \
  || bad "(V) signoff_retry must be stamped on the review bead (got: $(cat "$TMP/updates"))"
grep -q 'update review-1 --set-metadata gc.routed_to=rig/rig.polecat-codex' "$TMP/updates" \
  && ok "(V) the review is re-routed to the pool it came from" \
  || bad "(V) review must be re-routed for a retry (got: $(cat "$TMP/updates"))"
grep -q 'update review-1 --status=open --assignee=' "$TMP/updates" \
  && ok "(V) the claim is released so the pool can re-offer the review" \
  || bad "(V) review must be released to the pool (got: $(cat "$TMP/updates"))"
# The release is LAST: a bead that is claimable before it is routed can be picked
# up unrouted, and a batched release+route can roll back as a unit.
ROUTE_LINE=$(grep -n 'gc.routed_to=' "$TMP/updates" | head -1 | cut -d: -f1)
RELEASE_LINE=$(grep -n -- '--status=open --assignee=' "$TMP/updates" | head -1 | cut -d: -f1)
{ [ -n "$ROUTE_LINE" ] && [ -n "$RELEASE_LINE" ] && [ "$ROUTE_LINE" -lt "$RELEASE_LINE" ]; } \
  && ok "(V) the bead is routed BEFORE the assignee is released" \
  || bad "(V) route must precede release (route=$ROUTE_LINE release=$RELEASE_LINE)"
grep -q 'left OPEN and re-routed' "$TMP/err" \
  && ok "(V) the retry is reported, naming the review left open" \
  || bad "(V) unrecorded gate must warn (got: $(cat "$TMP/err"))"
eq "$(dismissed_ids)" "" "(V) and nothing is dismissed on an unrecorded gate"
# (V2) THE RELEASE IS READ BACK. The three writes are all `|| true`, so "released"
# was only ever an exit status — and an exit status cannot tell a durable write
# from one that reported success and stored nothing. The helper reads the bead back
# and only then calls the retry re-offered.
grep -q 'Signoff retry re-offered: review review-1 reads back open and unassigned, routed to rig/rig.polecat-codex' "$TMP/err" \
  && ok "(V2) the release is READ BACK (open + unassigned + routed) before the retry counts as re-offered" \
  || bad "(V2) retry must be confirmed by a read-back (got: $(cat "$TMP/err"))"
eq "$(grep -c -- '--status=open --assignee=' "$TMP/updates")" "1" \
   "(V2) a durable release is issued once — the read-back does not trigger a needless retry"

# (V3) THE NON-DURABLE RELEASE. `gc bd update --status=open --assignee=` reports
# success and persists NOTHING: the review stays in_progress, still assigned to a
# session that drains one step later. No pool offers an assigned bead, so the gate
# is owed to nobody and the PR strands silently — the same invisible failure (V)
# and (W) exist to prevent, arriving through a dropped write instead of a skipped
# one. The helper retries once and then says so loudly, with the repair command.
FAKE_CHECK_NOT_DURABLE=1 FAKE_RELEASE_NOT_DURABLE=1 \
  run '925|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
grep -q 'signoff retry for review review-1 did NOT persist after 2 attempts' "$TMP/err" \
  && ok "(V3) a release that reports success but does not persist -> reported, not silently trusted" \
  || bad "(V3) non-durable release must warn (got: $(cat "$TMP/err"))"
grep -q 'Repair by hand: gc bd update review-1 --status=open --assignee=' "$TMP/err" \
  && ok "(V3) the warning carries the hand-repair command (the bead is claimable by nobody)" \
  || bad "(V3) non-durable release must name the repair (got: $(cat "$TMP/err"))"
eq "$(grep -c -- '--status=open --assignee=' "$TMP/updates")" "2" \
   "(V3) the release is retried once before giving up (a dropped write is usually transient)"
eq "$(cat "$TMP/unrecorded")" "1" \
   "(V3) and the review is STILL not closed (a failed release never converts into a close)"

# (V4) the same guard against an outright FAILING release write, which the old
# `|| true` swallowed just as completely as the non-durable one.
FAKE_CHECK_NOT_DURABLE=1 FAKE_RELEASE_FAILS=1 \
  run '926|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
grep -q 'signoff retry for review review-1 did NOT persist' "$TMP/err" \
  && ok "(V4) a release write that FAILS is reported too (not swallowed by || true)" \
  || bad "(V4) failing release must warn (got: $(cat "$TMP/err"))"
eq "$(cat "$TMP/unrecorded")" "1" "(V4) and the close is still skipped"

# (V5) MID-PASS OPERATOR HOLD. Guard 7 read merge_hold ONCE, before the reviews
# listing. An operator who parks the anchor inside the window between that read and
# the dismissal would still lose the last GitHub-side block on the PR they just
# held — the most merge-triggering act this step has, done in defiance of the gate
# that exists to stop exactly it. The hold is re-read immediately before each
# dismissal, like the head and auto-merge probes beside it.
FAKE_MERGE_HOLD_FROM=3 \
  run '927|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V5) merge_hold set AFTER the up-front check -> dismissal SKIPPED"
grep -q 'carries merge_hold=true (operator gate) immediately before dismissing review 927' "$TMP/err" \
  && ok "(V5) the mid-step hold is reported, naming the review left in place" \
  || bad "(V5) mid-step merge_hold must warn (got: $(cat "$TMP/err"))"
eq "$(cat "$TMP/checks")" "green@liveheadB" \
   "(V5) the gate marker is still stamped (recording the signoff is not merge-triggering)"

# (V6) and an anchor whose metadata cannot be READ at that moment is treated as
# held, for the same reason an unreadable auto-merge probe is treated as armed:
# `.merge_hold // ""` renders an unreadable bead and an unheld one identically, so
# a failed read would clear the very guard it should arm.
FAKE_ANCHOR_SHOW_FAIL_FROM=3 \
  run '928|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V6) unreadable anchor before the dismissal -> SKIPPED (unreadable counts as held)"
grep -q 'metadata is UNREADABLE immediately before dismissing review 928' "$TMP/err" \
  && ok "(V6) the unreadable anchor is reported as the reason, not silently ignored" \
  || bad "(V6) unreadable anchor must warn (got: $(cat "$TMP/err"))"

# (V7-V10) FULL ANCHOR IDENTITY, not merge_hold alone. The per-dismissal re-read
# used to check exactly one field, so the other four ways the anchor can stop
# being what this arm decided about all slipped through and the block came off
# anyway. The observer's retraction arm (reconcile-merged-prs.sh) already required
# the whole set before dismissing; these pin the same requirement on the template
# half, which is the merge-TRIGGERING one. Ordinal 3 is the per-dismissal re-read.
#
# (V7) the anchor CLOSED mid-step: it no longer gates anything, so the block must
#      not come off on its authority.
FAKE_ANCHOR_STATUS_FROM=3 FAKE_ANCHOR_STATUS_LATE=closed \
  run '929|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V7) anchor CLOSED before the dismissal -> SKIPPED"
grep -q "changed mid-step (status='closed'" "$TMP/err" \
  && ok "(V7) the closed anchor is named as the reason" \
  || bad "(V7) closed anchor must warn (got: $(cat "$TMP/err"))"

# (V8) the anchor UN-PARKED from merge_result=pull_request: it no longer speaks
#      for a published PR at all.
FAKE_ANCHOR_RESULT_FROM=3 FAKE_ANCHOR_RESULT_LATE="" \
  run '930|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V8) anchor un-parked from pull_request -> SKIPPED"
grep -q "merge_result=''" "$TMP/err" \
  && ok "(V8) the un-parked anchor is named as the reason" \
  || bad "(V8) un-parked anchor must warn (got: $(cat "$TMP/err"))"

# (V9) the anchor's pr_number moved to a DIFFERENT PR: the block about to be
#      removed is on a PR this anchor no longer claims.
FAKE_ANCHOR_PR_FROM=3 FAKE_ANCHOR_PR_LATE=99 \
  run '931|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V9) anchor retargeted to another PR -> SKIPPED"
grep -q "pr_number='99'" "$TMP/err" \
  && ok "(V9) the retargeted anchor is named as the reason" \
  || bad "(V9) retargeted anchor must warn (got: $(cat "$TMP/err"))"

# (V10) check.<gate> was cleared or moved off the reviewed head by a re-gate
#       running concurrently: the head is no longer validated, so removing the
#       block would unblock work nothing currently vouches for. This is the case
#       the observer explicitly checks and the template did not.
FAKE_CHECK_MOVED_FROM=3 FAKE_CHECK_MOVED_LATE="green@someOtherHead" \
  run '932|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V10) check.<gate> moved off the reviewed head -> SKIPPED"
grep -q "check.codex='green@someOtherHead'" "$TMP/err" \
  && ok "(V10) the moved gate marker is named as the reason" \
  || bad "(V10) moved gate marker must warn (got: $(cat "$TMP/err"))"
# ...and the same when the marker is cleared outright rather than moved.
FAKE_CHECK_MOVED_FROM=3 FAKE_CHECK_MOVED_LATE="" \
  run '933|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V10) check.<gate> CLEARED mid-step -> SKIPPED"

# (V11) PARTIAL REVIEW HISTORY. `gh --paginate` streams the pages it did get and
# THEN fails, so what reached stdout parses perfectly — a well-formed history that
# is simply not the whole one. Fused into a single `gh | jq` assignment tested only
# for emptiness, that truncation was invisible and this step dismissed from it as
# though it had read everything; a read that failed OUTRIGHT (an expired token, a
# rate limit) was equally invisible, rendering as "nothing superseded to retract"
# and stranding the PR silently and permanently. The fetch and the reduction now
# carry their own status checks, matching merge-skill.sh and the observer arm.
FAKE_REVIEWS_FAIL=1 \
  run '934|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V11) reviews history read fails part way -> nothing dismissed"
grep -q 'reviews history read FAILED' "$TMP/err" \
  && ok "(V11) the failed history read is reported, not swallowed into 'nothing to retract'" \
  || bad "(V11) failed reviews read must warn (got: $(cat "$TMP/err"))"
eq "$(cat "$TMP/checks")" "green@liveheadB" \
   "(V11) the gate marker is still stamped (recording the signoff does not depend on the retraction)"

# (V12-V14) THE FORK-KEYED ANCHOR (review tk-5knqi finding #2). The guard added by
# (V7)-(V10) re-read the anchor's PR as `metadata.pr_number` alone — but that is
# only one of the keys a bead names its PR with. The fork-sync flow stamps
# `fork_pr`/`fork_pr_url` and NO pr_number at all, and every OTHER path here reads
# the widened set. So a fork-keyed anchor resolved fine everywhere up to this
# guard, which then read pr_number='' and could not tell it apart from "the anchor
# moved off this PR": the retraction never ran. That is not a deferral — this arm
# is the only in-band way out for such a PR (its gate is green at the live head, so
# no re-gate is ever dispatched), so it stayed BLOCKED on a dead commit forever.
# The narrow read regressed exactly the fork-keyed path the rest of the pass had
# just widened, in its last guard.
FAKE_ANCHOR_PR_KEY=fork_pr \
  run '940|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "940" "(V12) fork_pr-keyed anchor -> the superseded review IS retracted"
eq "$(cut -f2 "$TMP/marked" | tail -1)" "940@liveheadB" \
   "(V12) and the pairing marker is still recorded on it"

FAKE_ANCHOR_PR_KEY=fork_pr_url \
  run '941|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "941" \
   "(V13) fork_pr_url-keyed anchor -> retracted too (the number is parsed out of the url)"

# ...and the widening stays FAIL-CLOSED. A `fork_pr_url` that positively names
# ANOTHER repository is about somebody else's pull request, so it yields no number
# here and the guard holds — the widened read must not become a way to satisfy the
# identity check with a PR in a repository this step never read.
FAKE_ANCHOR_PR_KEY=fork_pr_url FAKE_ANCHOR_FORK_REPO="github.com/other/repo" \
  run '942|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V14) a fork_pr_url naming ANOTHER repository -> SKIPPED"
grep -q "pr_number=''" "$TMP/err" \
  && ok "(V14) and the reason reports the anchor as naming no PR here" \
  || bad "(V14) foreign fork_pr_url must warn (got: $(cat "$TMP/err"))"

# (V15-V17) THE REST OF THE IDENTITY, mutated mid-step. merged_target, pr_url and
# branch authorize the dismissal as directly as the gate marker does, and NONE of
# them moves the PR head — so the head re-read immediately above cannot catch any
# of them. Each is staged from call ordinal 3, the per-dismissal re-read, so the
# arm decides on the old value and the guard sees the new one. Same set, same
# reasoning, as merge-skill.sh's terminal re-read before `gh pr merge`.
FAKE_ANCHOR_TARGET_FROM=3 FAKE_ANCHOR_TARGET_LATE="release/2.0" \
  run '943|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V15) anchor retargeted mid-step -> SKIPPED"
grep -q "retargeted mid-step (merged_target='release/2.0', PR base 'main')" "$TMP/err" \
  && ok "(V15) the retarget is named against the PR's live base" \
  || bad "(V15) mid-step retarget must warn (got: $(cat "$TMP/err"))"

FAKE_ANCHOR_PRURL_FROM=3 FAKE_ANCHOR_PRURL_LATE="https://github.com/acme/repo/pull/99" \
  run '944|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V16) anchor's pr_url moved to another PR mid-step -> SKIPPED"
grep -q "records pr_url 'https://github.com/acme/repo/pull/99'" "$TMP/err" \
  && ok "(V16) the disagreeing url is named against the PR just read" \
  || bad "(V16) mid-step pr_url move must warn (got: $(cat "$TMP/err"))"

# ...but a COSMETIC difference is not a different pull request. Both sides are
# canonicalized, so a `/files` suffix and a trailing slash still match — otherwise
# the guard would hold every anchor whose recorded url merely reads differently.
FAKE_ANCHOR_PRURL="https://github.com/acme/repo/pull/37/files" \
  run '945|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "945" \
   "(V16) a cosmetically-different url for the SAME PR still dismisses"

FAKE_ANCHOR_BRANCH_FROM=3 FAKE_ANCHOR_BRANCH_LATE="polecat/somebody-else" \
  run '946|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(V17) anchor's branch corrected off this PR mid-step -> SKIPPED"
grep -q "records branch 'polecat/somebody-else' but PR#37 is opened from 'polecat/tk-5niup'" "$TMP/err" \
  && ok "(V17) the branch disagreement is named against the PR's live head ref" \
  || bad "(V17) mid-step branch change must warn (got: $(cat "$TMP/err"))"

# ...and an anchor that records NONE of the three is governed by the pinned read
# alone: silence is not a disagreement, or the guard would hold every legacy anchor
# that never carried these fields. (A) already proves that path, asserted here as
# the explicit control for this trio.
FAKE_ANCHOR_TARGET="" FAKE_ANCHOR_PRURL="" FAKE_ANCHOR_BRANCH="" \
  run '947|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "947" \
   "(V15-V17 control) an anchor recording no target/url/branch still dismisses"

# --- The NO-ANCHOR arm (the `else` of `if [ -n "$ANCHOR" ]`). -----------------
# It sits OUTSIDE the supersede-dismiss markers — that snippet is the body of the
# anchor-RESOLVED branch — so it carries its own markers and is extracted and run
# separately, against the same stubs.
NO_ANCHOR_SNIPPET="$(awk '
  /# >>> signoff-no-anchor-retry/ {f=1; next}
  /# <<< signoff-no-anchor-retry/ {f=0}
  f' "$TEMPLATE")"

[ -n "$NO_ANCHOR_SNIPPET" ] \
  && ok "no-anchor snippet extracted between signoff-no-anchor-retry markers" \
  || bad "no-anchor snippet extraction EMPTY — markers missing from $TEMPLATE"

{ printf '%s\n' "$HELPER"
  printf '%s\n' "$NO_ANCHOR_SNIPPET"
  printf 'printf "%%s" "${SIGNOFF_UNRECORDED:-}" > "$FAKE_UNRECORDED"\n'; } > "$TMP/run-no-anchor.sh"

# run_no_anchor <live-gc.routed_to-on-the-review-bead> [durable metadata.review_pool] [keep-pool]
#   keep-pool: do NOT reset the durable-pool file, so a second cycle inherits what
#   the first one actually persisted. That is the only honest way to test a write
#   whose whole purpose is to be there NEXT time — re-staging it from an env var
#   would pass whether or not the write exists.
run_no_anchor() {
  : > "$TMP/updates"; : > "$TMP/unrecorded"; : > "$TMP/checks"; : > "$TMP/marked"
  : > "$TMP/claim"; : > "$TMP/route"; printf '0' > "$TMP/anchorshows"
  [ "${3:-}" = "keep-pool" ] || : > "$TMP/pool"
  PATH="$TMP/bin:$PATH" \
  FAKE_UPDATES="$TMP/updates" FAKE_UNRECORDED="$TMP/unrecorded" \
  FAKE_CHECKS="$TMP/checks" FAKE_MARKED="$TMP/marked" \
  FAKE_CLAIM="$TMP/claim" FAKE_ROUTE="$TMP/route" FAKE_ANCHOR_SHOWS="$TMP/anchorshows" \
  FAKE_POOL="$TMP/pool" FAKE_POOL_NOT_DURABLE="${FAKE_POOL_NOT_DURABLE:-}" \
  FAKE_RELEASE_FAILS="${FAKE_RELEASE_FAILS:-}" \
  FAKE_RELEASE_NOT_DURABLE="${FAKE_RELEASE_NOT_DURABLE:-}" \
  FAKE_REVIEW_POOL="$1" FAKE_REVIEW_POOL_DURABLE="${2:-}" \
  REVIEW_BEAD="review-1" CHECK_NAME="codex" \
    bash "$TMP/run-no-anchor.sh" 2>"$TMP/err"
}

# (W) NO ANCHOR AT ALL: neither the blocks edge nor metadata.anchor_bead answered,
#     so the gate cannot be recorded ANYWHERE — the same strand as (V) and it owes
#     the same release. Pre-fix this arm only wrote signoff_retry: the bead stayed
#     in_progress and assigned to a session that drains one step later, so no pool
#     ever re-offered it. "Left open" is invisible unless it is also unassigned.
run_no_anchor "rig/rig.polecat-codex"
eq "$(cat "$TMP/unrecorded")" "1" \
   "(W) no anchor -> SIGNOFF_UNRECORDED set (the done-sequence skips the close)"
grep -q 'update review-1 .*signoff_retry=no anchor resolved' "$TMP/updates" \
  && ok "(W) the retry reason names the no-anchor cause" \
  || bad "(W) signoff_retry must be stamped on the review bead (got: $(cat "$TMP/updates"))"
grep -q 'update review-1 --set-metadata gc.routed_to=rig/rig.polecat-codex' "$TMP/updates" \
  && ok "(W) the review is re-routed to the pool it came from" \
  || bad "(W) review must be re-routed for a retry (got: $(cat "$TMP/updates"))"
grep -q 'update review-1 --status=open --assignee=' "$TMP/updates" \
  && ok "(W) the claim is released so the pool can re-offer the review" \
  || bad "(W) review must be released to the pool (got: $(cat "$TMP/updates"))"
W_ROUTE_LINE=$(grep -n 'gc.routed_to=' "$TMP/updates" | head -1 | cut -d: -f1)
W_RELEASE_LINE=$(grep -n -- '--status=open --assignee=' "$TMP/updates" | head -1 | cut -d: -f1)
{ [ -n "$W_ROUTE_LINE" ] && [ -n "$W_RELEASE_LINE" ] && [ "$W_ROUTE_LINE" -lt "$W_RELEASE_LINE" ]; } \
  && ok "(W) the bead is routed BEFORE the assignee is released" \
  || bad "(W) route must precede release (route=$W_ROUTE_LINE release=$W_RELEASE_LINE)"
grep -q 'left OPEN and re-routed to rig/rig.polecat-codex' "$TMP/err" \
  && ok "(W) the retry is reported, naming the pool the review went back to" \
  || bad "(W) no-anchor retry must warn (got: $(cat "$TMP/err"))"
eq "$(cat "$TMP/checks")" "" "(W) and no gate marker is invented with no anchor to hold it"

# (W2) NO pool resolvable at all — neither the live gc.routed_to nor the durable
#      metadata.review_pool. Writing gc.routed_to="" would erase whatever route it
#      had, so the route write is still SKIPPED, and the claim is still released
#      (an assigned bead held by a draining session is the failure this arm exists
#      to prevent, pool or no pool). What must NOT happen is the retry reporting
#      SUCCESS: open + unassigned + UNROUTED matches no pool's offer predicate, so
#      the review is claimable by nobody and the gate is owed forever. Pre-fix the
#      read-back short-circuited the route check on an empty pool and returned 0 —
#      a strand wearing a success message.
run_no_anchor "" ""
grep -q 'gc.routed_to=' "$TMP/updates" \
  && bad "(W2) empty pool must NOT be written back as a route (got: $(cat "$TMP/updates"))" \
  || ok "(W2) no pool recorded -> the route is left alone, not blanked"
grep -q 'update review-1 --status=open --assignee=' "$TMP/updates" \
  && ok "(W2) the claim is released even with no pool to route to" \
  || bad "(W2) review must still be released (got: $(cat "$TMP/updates"))"
eq "$(cat "$TMP/unrecorded")" "1" "(W2) and the close is still skipped"
grep -q 'Signoff retry re-offered' "$TMP/err" \
  && bad "(W2) an unroutable review must NOT be reported as re-offered (got: $(cat "$TMP/err"))" \
  || ok "(W2) no pool -> the retry is NOT reported as re-offered"
grep -q 'NO pool to route it to' "$TMP/err" \
  && ok "(W2) the unroutable retry is reported loudly instead" \
  || bad "(W2) no-pool retry must warn (got: $(cat "$TMP/err"))"
grep -q 'gc.routed_to=<review-pool>' "$TMP/err" \
  && ok "(W2) and the repair command tells the operator to supply the route" \
  || bad "(W2) repair command must name gc.routed_to (got: $(cat "$TMP/err"))"
# BOTH halves, or the repair rebuilds this dead end one claim later: the operator
# sets only the live offer, a pool claims the review and CONSUMES it, and the next
# retry is back to a bead with no pool it can reconstruct the route from — the
# exact shape (W7)/(W8) exist to prevent (review tk-y5r1e P2).
grep -q 'review_pool=<review-pool>' "$TMP/err" \
  && ok "(W2) and it names the DURABLE copy too, so the repair survives the next claim" \
  || bad "(W2) repair command must name review_pool as well (got: $(cat "$TMP/err"))"

# (W3) The live route is GONE — the claim that started this session consumed
#      gc.routed_to — but the dispatch's durable metadata.review_pool is still on
#      the bead. That is the ordinary shape of this path, not an edge case, and it
#      must recover: the retry restores the route from review_pool, reads it back,
#      and only then reports the review re-offered.
run_no_anchor "" "rig/rig.polecat-codex"
grep -q 'update review-1 --set-metadata gc.routed_to=rig/rig.polecat-codex' "$TMP/updates" \
  && ok "(W3) the route is restored from the durable review_pool fallback" \
  || bad "(W3) review_pool must be used when the live route is gone (got: $(cat "$TMP/updates"))"
grep -q 'Signoff retry re-offered' "$TMP/err" \
  && ok "(W3) and with a route read back, the retry IS re-offered" \
  || bad "(W3) a routed retry must report re-offered (got: $(cat "$TMP/err"))"
W3_ROUTE_LINE=$(grep -n 'gc.routed_to=' "$TMP/updates" | head -1 | cut -d: -f1)
W3_RELEASE_LINE=$(grep -n -- '--status=open --assignee=' "$TMP/updates" | head -1 | cut -d: -f1)
{ [ -n "$W3_ROUTE_LINE" ] && [ -n "$W3_RELEASE_LINE" ] && [ "$W3_ROUTE_LINE" -lt "$W3_RELEASE_LINE" ]; } \
  && ok "(W3) the restored route still precedes the release" \
  || bad "(W3) route must precede release (route=$W3_ROUTE_LINE release=$W3_RELEASE_LINE)"

# (W4) THE SPLIT ROUTE (tk-5niup): both fields are present and they DISAGREE —
#      the live gc.routed_to names one pool, the dispatch's durable review_pool
#      names another. The live half is working state (a claim consumes it, a
#      re-route rewrites it), so when the two disagree it is the half that drifted;
#      review_pool is what the dispatch stamped and the only one that still says
#      who owes this gate. Pre-fix the helper read gc.routed_to FIRST and used it
#      whenever it was non-empty, so the retry was released to the WRONG pool and
#      then reported successfully re-offered — the gate owed by a pool that was
#      never dispatched it, wearing a success message, which is the same class of
#      silent strand (W2) closed for the no-pool case.
run_no_anchor "rig/rig.wrong-pool" "rig/rig.polecat-codex"
grep -q 'update review-1 --set-metadata gc.routed_to=rig/rig.polecat-codex' "$TMP/updates" \
  && ok "(W4) split route -> the retry is released to the DURABLE review_pool" \
  || bad "(W4) durable review_pool must win over a disagreeing live route (got: $(cat "$TMP/updates"))"
grep -q 'gc.routed_to=rig/rig.wrong-pool' "$TMP/updates" \
  && bad "(W4) the stale live route must NOT be written back (got: $(cat "$TMP/updates"))" \
  || ok "(W4) the drifted live route is overwritten, not inherited"
grep -q 'SPLIT route' "$TMP/err" \
  && ok "(W4) the route disagreement is reported to the operator" \
  || bad "(W4) a split route must be warned about (got: $(cat "$TMP/err"))"
grep -q 'Signoff retry re-offered' "$TMP/err" \
  && ok "(W4) and the repaired retry reads back re-offered" \
  || bad "(W4) a repaired split route must report re-offered (got: $(cat "$TMP/err"))"

# (W5) NOT over-firing: the live route AGREES with the durable copy — the ordinary
#      healthy dispatch. No split warning, and the same pool is used either way.
run_no_anchor "rig/rig.polecat-codex" "rig/rig.polecat-codex"
grep -q 'SPLIT route' "$TMP/err" \
  && bad "(W5) agreeing route fields must NOT be reported as a split (got: $(cat "$TMP/err"))" \
  || ok "(W5) agreeing route fields -> no split warning"
grep -q 'update review-1 --set-metadata gc.routed_to=rig/rig.polecat-codex' "$TMP/updates" \
  && ok "(W5) and the retry still routes to that pool" \
  || bad "(W5) agreeing route must still be written back (got: $(cat "$TMP/updates"))"

# (W6) LEGACY bead: no durable review_pool was ever stamped, so the live route is
#      the sole record of the pool. It must still be used — preferring the durable
#      copy is a preference, not a requirement, and dropping the fallback would
#      strand every review dispatched before review_pool existed.
run_no_anchor "rig/rig.polecat-codex" ""
grep -q 'update review-1 --set-metadata gc.routed_to=rig/rig.polecat-codex' "$TMP/updates" \
  && ok "(W6) no durable copy -> the live gc.routed_to is still used as the fallback" \
  || bad "(W6) live route must remain the fallback (got: $(cat "$TMP/updates"))"
grep -q 'Signoff retry re-offered' "$TMP/err" \
  && ok "(W6) and the legacy-shaped retry reads back re-offered" \
  || bad "(W6) legacy fallback retry must report re-offered (got: $(cat "$TMP/err"))"
grep -q 'update review-1 .*review_pool=rig/rig.polecat-codex' "$TMP/updates" \
  && ok "(W6) and the legacy bead is UPGRADED — the resolved pool is persisted durably" \
  || bad "(W6) a legacy retry must persist review_pool (got: $(cat "$TMP/updates"))"

# (W7) THE TWO-CYCLE LEGACY RETRY (review tk-nwi06 finding #2). (W6)'s fallback
#      works exactly once if the pool it resolves is only ever written to the LIVE
#      route. The pool that claims the re-offer CONSUMES gc.routed_to, so a second
#      retry — an unrecorded gate, an anchor that still will not resolve — finds
#      review_pool absent (it was never stamped, that is what made the bead legacy)
#      AND gc.routed_to spent. With nothing to resolve, the release goes out
#      open + unassigned + UNROUTED: offered to nobody, gate owed forever. The
#      second cycle here is staged from NOTHING but what the first cycle persisted.
run_no_anchor "rig/rig.polecat-codex" ""            # cycle 1: legacy shape
run_no_anchor "" "" keep-pool                       # cycle 2: live route consumed
grep -q 'update review-1 --set-metadata gc.routed_to=rig/rig.polecat-codex' "$TMP/updates" \
  && ok "(W7) the second cycle reconstructs the route from cycle 1's durable write" \
  || bad "(W7) a legacy bead must stay routable across cycles (got: $(cat "$TMP/updates"))"
grep -q 'Signoff retry re-offered' "$TMP/err" \
  && ok "(W7) and the second cycle still reports the review re-offered" \
  || bad "(W7) second-cycle retry must re-offer (got: $(cat "$TMP/err"))"
grep -q 'NO pool to route it to' "$TMP/err" \
  && bad "(W7) the second cycle must NOT strand for want of a pool (got: $(cat "$TMP/err"))" \
  || ok "(W7) the pool is never lost between cycles"

# (W8) NOT declaring victory on the live half alone. The durable write reports
#      SUCCESS and persists nothing — the same non-durable-write shape the route
#      read-back already guards, applied to the field that matters NEXT time. The
#      review is claimable right now, so a check of gc.routed_to alone passes; but
#      the route dies with the next claim, so this must read as a FAILED retry with
#      a repair command, not as a re-offer.
FAKE_POOL_NOT_DURABLE=1 run_no_anchor "rig/rig.polecat-codex" ""
grep -q 'Signoff retry re-offered' "$TMP/err" \
  && bad "(W8) a retry whose durable copy did not land must NOT report re-offered (got: $(cat "$TMP/err"))" \
  || ok "(W8) the live route alone does not count as re-offered"
grep -q 'did NOT persist' "$TMP/err" \
  && ok "(W8) the dropped durable copy is reported as a failed retry" \
  || bad "(W8) a dropped review_pool must warn (got: $(cat "$TMP/err"))"
grep -q 'set-metadata review_pool=rig/rig.polecat-codex' "$TMP/err" \
  && ok "(W8) and the repair command names review_pool, not just the live route" \
  || bad "(W8) repair command must restore the durable copy (got: $(cat "$TMP/err"))"

# =============================================================================
# EVERY GitHub CALL IS PINNED TO THE BEAD'S REPOSITORY (review tk-78ty5 finding #4)
# =============================================================================
# A PR number names a different pull request in every repository. This block reads
# a review history, re-reads a head, probes auto-merge, and then DISMISSES a review
# — and it used to leave the repository to gh entirely: `repos/{owner}/{repo}/...`
# REST paths, which gh expands from its ambient context, and bare
# `gh pr view "$PR_NUMBER"`. A polecat runs this in a worktree it was handed, so
# "whatever repository gh currently thinks it is in" is not a fact about the PR
# under review. Drifted, the arm reads a stranger's #N, finds a superseded review
# THERE, dismisses it, and stamps signoff_dismissed on OUR anchor — our PR still
# blocked, someone else's review retracted, and the approval requirement recorded
# against the wrong one. Unlike a read, that write cannot be compared after the
# fact: it has to be aimed correctly by construction.

# (P1) THE PIN. Same passing case as (A), asserted on WHERE every call went.
run '900|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "900" "(P1) control: the retraction still fires (the pin does not disable the arm)"
eq "$(view_pins)" "github.com/acme/repo" \
   "(P1) every gh pr view passed --repo from the bead — head re-read and auto-merge probe alike (never <unpinned>)"
eq "$(api_pins)" "acme/repo" \
   "(P1) every gh api REST path named the bead's repository (never the ambient {owner}/{repo})"
# ...AND ITS HOST. A REST path carries `<owner>/<repo>` and nothing else, so a
# repo-pinned `gh api` is still only HALF pinned: gh fills the host from $GH_HOST,
# and `acme/repo` names one repository PER HOST. Another host's acme/repo has a
# #37, its own review ids, and its own history — so the arm could read a stranger's
# reviews and PUT a dismissal there while our PR stays blocked, with every
# assertion above still passing. `--hostname` from the bead's own pr_url is what
# closes it (review tk-5knqi finding #1).
eq "$(sort -u "$TMP/apihost" | tr '\n' ' ' | sed 's/ $//')" "github.com" \
   "(P1) every gh api call carried --hostname from the bead (never <unpinned>, which would fall back to \$GH_HOST)"

# (P2) NO REPOSITORY, NO CALLS. The bead records no parseable pr_url, so nothing
# can be pinned. The arm must refuse rather than fall back to gh's ambient context:
# an unstamped gate just re-gates next pass, but a dismissal aimed at the wrong
# repository is irreversible. This is the fail-closed direction the whole block is
# built on, applied to its own precondition.
PR_REPO_Q="" PR_REPO="" run '901|zook-bot|CHANGES_REQUESTED|deadcommitA' 'liveheadB' 'liveheadB' '37' ''
eq "$(dismissed_ids)" "" "(P2) unpinnable PR -> NOTHING dismissed"
eq "$(wc -l < "$TMP/viewpin" | tr -d ' ')" "0" "(P2) unpinnable PR -> no gh pr view attempted"
grep -q 'records no parseable pr_url' "$TMP/err" \
  && ok "(P2) the refusal names the missing pr_url and says how to repair it" \
  || bad "(P2) an unpinnable PR must warn (got: $(cat "$TMP/err"))"

# (P3) THE DERIVATION ITSELF, extracted from the template and run against the same
# gc stub the real done sequence uses. (P1)/(P2) prove the snippet HONOURS
# PR_REPO_Q; this proves the block that PRODUCES it turns a bead's pr_url into the
# host-qualified `--repo` form and the hostless REST form — and that a value which
# is not a pull-request URL yields EMPTY, which is what routes (P2).
REPOPIN="$(awk '
  /# >>> signoff-repo-pin/ {f=1; next}
  /# <<< signoff-repo-pin/ {f=0}
  f' "$TEMPLATE")"
[ -n "$REPOPIN" ] \
  && ok "(P3) repo-pin block extracted between signoff-repo-pin markers" \
  || bad "(P3) repo-pin extraction EMPTY — markers missing from $TEMPLATE"
# `gc bd show` answers with the pr_url under test; the block reads nothing else.
pin_derive() {
  printf '#!/usr/bin/env bash\nprintf %s\n' \
    "'[{\"metadata\":{\"pr_url\":\"$1\"}}]\n'" > "$TMP/bin/gc"
  chmod +x "$TMP/bin/gc"
  { printf '%s\n' "$REPOPIN"
    printf 'printf "%%s|%%s|%%s\\n" "$PR_REPO_Q" "$PR_REPO" "$PR_HOST"\n'; } > "$TMP/pin.sh"
  PATH="$TMP/bin:$PATH" REVIEW_BEAD="review-1" bash "$TMP/pin.sh" 2>/dev/null
}
# THREE forms, because three different callers need three different shapes:
# `gh pr view --repo` takes the host-qualified name, a REST path takes the hostless
# one, and `gh api --hostname` takes the host on its own. All split from the SAME
# parse, so no two of them can name different places.
eq "$(pin_derive 'https://github.com/zookanalytics/gc-toolkit/pull/246')" \
   "github.com/zookanalytics/gc-toolkit|zookanalytics/gc-toolkit|github.com" \
   "(P3) a pr_url yields the host-qualified pin, the hostless REST form AND the host"
eq "$(pin_derive 'https://ghe.example.com/acme/repo/pull/7')" \
   "ghe.example.com/acme/repo|acme/repo|ghe.example.com" \
   "(P3) the HOST is carried, not assumed — a hostless pin would name another host's acme/repo"
eq "$(pin_derive '')" "||" "(P3) no pr_url -> empty pin (routes the fail-closed refusal)"
eq "$(pin_derive 'not-a-url')" "||" "(P3) an unparseable pr_url -> empty pin, never a guess"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
