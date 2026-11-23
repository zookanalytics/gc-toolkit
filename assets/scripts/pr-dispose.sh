#!/usr/bin/env bash
# pr-dispose — record a deliberate PR-close disposition on the open anchor, then
# close the PR, so the PR's closer consummates the terminal close through
# bead-rehome.sh instead of filing a human gate that re-asks a decision already
# made. The closer is the landing order (gctk pr reconcile), which reads an
# anchor on Gas Town's pending record, pull_request_pending or
# pull_request_head_changed.
#
# It stamps three metadata keys naming the intended bead-rehome invocation —
# gc.pr_close_disposition_kind, gc.pr_close_disposition_successor, and an
# optional gc.pr_close_disposition_successor_store — in one update whose exit
# decides, and closes the PR with an explaining comment (unless --no-close-pr,
# for an operator who will close it in the UI). It does NOT close the anchor:
# that terminal close is the closer's, the single consummation point, which
# closes it with the edge that names its successor (the terminal state
# doctor/check-closed-implies-landed accepts) once the PR reads closed. On the
# pending record the landing order also requests no merge of a PR whose anchor
# carries the keys.
#
# The read of the anchor and the stamp hold the store's record lock, a flock on
# pr-record.lock in the .beads directory of the store that holds the anchor
# (bead-store.sh --db), which the landing order holds for each record from its
# read of the record to its last write of it. So the stamp lands before a run
# reads the anchor, and that run requests no merge, or after the run's last
# write, and never between a run's read of the anchor and its merge request.
# The lock is taken before the anchor is read and released once the stamp has
# landed, before the PR is read or closed. Every gc call made while it is held
# runs with its descriptor closed, so no process a store read leaves running
# holds the lock. It waits up to $PR_RECORD_LOCK_WAIT_SECS (300) for the lock,
# and a lock that does not come writes nothing. --dry-run takes no lock.
#
# The anchor must own an open PR that the closer reads: not closed on the
# pending record, which the landing order reads while the refinery holds the
# anchor. An anchor already disposed (its duplicates or supersedes edge names a
# successor) is a no-op; an anchor past that state (abandoned, merged, an
# exception of the pending record) is refused, with bead-rehome.sh named as the
# direct verb for it. bead-rehome.sh makes no GitHub call, and at an exception
# the landing order no longer reads the PR, which can still be open. So at an
# exception the refusal frees the lock and asks GitHub about each PR the record
# names. While one reads open, the refusal names its close, gh pr close <url>,
# in place of the direct verb. When GitHub cannot say, it names what to repair.
#
#   pr-dispose.sh --anchor <bead-id> --successor <bead-id> \
#                 --kind re-homed|folded|fixed-upstream|duplicate|not-needed \
#                 [--successor-store rig:<name>] [--note "<why>"] \
#                 [--pr <num>] [--no-close-pr] [--dry-run]
#
# Under every kind but not-needed the successor is the bead that carries the
# work now. Under not-needed nothing carries it, and the successor is the
# evidence that concluded the bead was unnecessary — typically the conversation
# of the sitting that ruled. It is required either way, because it is the
# whole of what distinguishes a sound disposition from a careless close.
#
# Callers: a sitting's ruling, through converse-signoff.sh --retire, and
# operator close-outs — the PR side of the bead-rehome disposition doctrine
# (docs/state-machine.md "Disposition").
# The current store must be the anchor's rig (GC_RIG, or run in its checkout).
# Exit: 0 stamped (PR closed) or already disposed · 1 error, a record lock that
# did not come within the wait among them · 2 usage.
set -uo pipefail

PROG="pr-dispose"
# The single writer of the city's PR posts: the closing comment goes through it
# so it carries the city's mark and is never read back as feedback.
PR_POST="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/pr-post.sh"
# The one resolver of a bead's store, which names the store whose record lock
# the stamp takes.
BEAD_STORE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/bead-store.sh"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }

# host/owner/repo from a PR url, so every gh call is pinned to the PR's own
# repository: a bare #NUM names a different pull request per repo per host.
url_repo_q() {
  printf '%s' "${1:-}" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p'
}
# a PR url reduced to scheme://host/owner/repo/pull/<n>, for identity comparison.
canon_pr_url() {
  printf '%s' "${1:-}" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##'
}

usage() {
  cat >&2 <<'U'
usage: pr-dispose.sh --anchor <bead-id> --successor <bead-id>
                     --kind re-homed|folded|fixed-upstream|duplicate|not-needed
                     [--successor-store rig:<name>] [--note "<one sentence>"]
                     [--pr <num>] [--no-close-pr] [--dry-run]

Records a deliberate supersede/not-planned PR-close disposition on the open
anchor and closes the PR; the PR's closer, the landing order, then closes the
anchor through bead-rehome.sh instead of filing a human gate. The read
of the anchor and the stamp hold the store's record lock, waiting up to
$PR_RECORD_LOCK_WAIT_SECS (300) while the landing order holds it.

  --anchor          the open work bead the PR gates (merge_result
                    pull_request_pending or pull_request_head_changed)
  --successor       the carrier of the work, or (not-needed) the evidence
  --kind            the bead-rehome kind the disposition maps to
  --successor-store rig:<name>, only when the successor's id prefix is ambiguous
  --note            one sentence of why, carried into the PR comment
  --pr              PR number; defaults to the anchor's metadata.pr_number
  --no-close-pr     stamp only; you will close the PR yourself (e.g. in the UI)
  --dry-run         print what would be done, write nothing
U
}

ANCHOR=""; SUCCESSOR=""; KIND=""; STORE=""; NOTE=""; PRNUM=""; NO_CLOSE=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)          ANCHOR="${2:-}"; shift 2 ;;
    --successor)       SUCCESSOR="${2:-}"; shift 2 ;;
    --kind)            KIND="${2:-}"; shift 2 ;;
    --successor-store) STORE="${2:-}"; shift 2 ;;
    --note)            NOTE="${2:-}"; shift 2 ;;
    --pr)              PRNUM="${2:-}"; shift 2 ;;
    --no-close-pr)     NO_CLOSE=1; shift ;;
    --dry-run)         DRY=1; shift ;;
    -h|--help)         usage; exit 2 ;;
    *)                 warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done

[ -n "$ANCHOR" ]    || { warn "--anchor is required";    usage; exit 2; }
[ -n "$SUCCESSOR" ] || { warn "--successor is required"; usage; exit 2; }
[ -n "$KIND" ]      || { warn "--kind is required";      usage; exit 2; }
# The kind is a closed set, the same one bead-rehome enforces: the closer hands
# it straight to bead-rehome, so a kind refused there must be refused here.
case "$KIND" in
  re-homed|folded|fixed-upstream|duplicate|not-needed) ;;
  *) die "--kind must be one of re-homed|folded|fixed-upstream|duplicate|not-needed (got '$KIND')" 2 ;;
esac

command -v gc >/dev/null 2>&1 || die "gc is required" 1
command -v jq >/dev/null 2>&1 || die "jq is required" 1

# The store's record lock (the header's rule), taken on fd 9 before the anchor
# is read and held through the stamp.
RECORD_LOCK_WAIT="${PR_RECORD_LOCK_WAIT_SECS:-300}"
case "$RECORD_LOCK_WAIT" in ''|*[!0-9]*) RECORD_LOCK_WAIT=300 ;; esac
take_record_lock() {
  local db lock
  db=$("$BEAD_STORE" --db "$ANCHOR" 2>/dev/null) && [ -n "$db" ] \
    || die "the store that holds $ANCHOR did not resolve ('bead-store.sh --db $ANCHOR' says why), so its record lock cannot be taken; nothing written" 1
  lock="$db/pr-record.lock"
  command -v flock >/dev/null 2>&1 \
    || die "flock is not on PATH, so the store's record lock ($lock) cannot be taken; nothing written" 1
  exec 9>>"$lock" \
    || die "the store's record lock ($lock) does not open; nothing written" 1
  flock -w "$RECORD_LOCK_WAIT" 9 \
    || die "another writer of a PR's pending record held the store's record lock ($lock) for ${RECORD_LOCK_WAIT}s; nothing written. Re-run this disposition" 1
}
[ "$DRY" -eq 1 ] || take_record_lock

# Read the anchor from the current store.
AJSON=$(gc bd show "$ANCHOR" --json 2>/dev/null 9>&- | scrub)
printf '%s' "$AJSON" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
  || die "could not read anchor $ANCHOR from the current store; set GC_RIG to its rig, or run in that rig's checkout" 1
A_STATUS=$(printf '%s' "$AJSON" | jq -r '.[0].status // ""')
A_MR=$(printf '%s' "$AJSON" | jq -r '(.[0].metadata.merge_result // "") | tostring')
# The disposition is read off the anchor's list row, which carries an edge onto
# a successor in another rig's store as well.
A_PRIOR=$(bd_disposed_to "$ANCHOR" 9>&- || true)
[ -n "$PRNUM" ] || PRNUM=$(printf '%s' "$AJSON" | jq -r '(.[0].metadata.pr_number // "") | tostring')

# Already disposed: bead-rehome already recorded its successor. Nothing to add.
if [ -n "$A_PRIOR" ]; then
  echo "$PROG: $ANCHOR already names $A_PRIOR as its successor — already disposed, nothing to do"
  exit 0
fi
# The marker only means something on a state its closer reads: an anchor on the
# pending record that is not closed, which the landing order reads. Past that,
# it will not see it, so refuse and name the direct verb rather than stamp a
# marker nothing consummates.
CLOSER=""
case "$A_MR" in
  pull_request_pending|pull_request_head_changed) [ "$A_STATUS" = closed ] || CLOSER="the landing order" ;;
esac
# The record stops following a bead's PR at an exception, and its pr_state then
# holds the exception's word, so only GitHub says whether that PR is still open.
# record.Exception, in services/gctk/pr/record, names these values, and
# pr-dispose.test.sh holds this copy to it.
RECORD_EXCEPTIONS="pull_request_reconcile_invalid pull_request_closed_unmerged pull_request_merged_unvalidated_head pull_request_merge_evidence_contradiction pull_request_legacy_closed_unverified pull_request_merged_close_refused"
PR_URL_RE='^https://[^/]+/[^/]+/[^/]+/pull/[0-9]+$'
if [ -z "$CLOSER" ]; then
  case " $RECORD_EXCEPTIONS " in
    *" ${A_MR:-none} "*)
      # Nothing is written past this point, so the lock goes free before GitHub
      # is read.
      exec 9>&-
      READ_PRS=" "
      for pr_key in pr_url existing_pr; do
        pr=$(printf '%s' "$AJSON" | jq -r --arg k "$pr_key" '(.[0].metadata[$k] // "") | tostring' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$pr" ] || continue
        case "$READ_PRS" in *" $pr "*) continue ;; esac
        READ_PRS="$READ_PRS$pr "
        [[ $pr =~ $PR_URL_RE ]] \
          || die "$ANCHOR is at $A_MR, and its $pr_key reads '$pr', which is not a PR's URL, so GitHub cannot say whether that PR is still open. Correct $pr_key, then run this again" 1
        PR_STATE=$(gh pr view "$pr" --json state </dev/null 2>/dev/null | scrub | jq -r '.state // ""' 2>/dev/null) || PR_STATE=""
        case "$PR_STATE" in
          CLOSED|MERGED) ;;
          OPEN)
            die "$ANCHOR is at $A_MR, where the landing order no longer reads its PR, and its PR $pr is still open, which disposing of $ANCHOR directly would leave open behind the closed bead. Close it first, then run this again: gh pr close $pr. At an exception, closing the PR by hand files no gate" 1 ;;
          *)
            die "$ANCHOR is at $A_MR, and GitHub did not say whether its PR $pr is still open: gh pr view $pr --json state did not answer. Run this again once it does" 1 ;;
        esac
      done
      [ "$READ_PRS" != " " ] \
        || die "$ANCHOR is at $A_MR, and neither pr_url nor existing_pr names its PR, so GitHub cannot say whether that PR is still open. Set pr_url to the PR's URL, then run this again" 1 ;;
  esac
  die "$ANCHOR is status='$A_STATUS' merge_result='${A_MR:-unset}', not an anchor whose open PR a closer consummates: not closed at pull_request_pending or pull_request_head_changed. Dispose an anchor past that state directly: bead-rehome.sh --origin $ANCHOR --successor $SUCCESSOR --kind $KIND" 1
fi
# The PR repository AND number both come from the anchor's own pr_url. A bare
# PR number names a different pull request per repository per host, and this
# script can read the anchor from another rig (GC_RIG) while the checkout's
# origin is an unrelated repo — pinning gh to the checkout origin could then
# close a same-numbered PR in the wrong repository. Refuse an unparseable
# pr_url, and a --pr / metadata.pr_number that contradicts it, before touching
# anything.
PR_URL=$(printf '%s' "$AJSON" | jq -r '.[0].metadata.pr_url // ""')
PR_REPO_Q=$(url_repo_q "$PR_URL")
[ -n "$PR_REPO_Q" ] || die "no parseable pr_url on $ANCHOR (metadata.pr_url='$PR_URL'); refusing to run GitHub calls a bare PR number would aim at the checkout's origin repo. Close the PR by hand, and pr-facts auto-disposes $ANCHOR once it is CLOSED" 1
URL_NUM="${PR_URL##*/pull/}"; URL_NUM="${URL_NUM%%[!0-9]*}"
case "$URL_NUM" in ''|*[!0-9]*) die "the pr_url on $ANCHOR ('$PR_URL') carries no numeric PR number" 1 ;; esac
if [ -n "$PRNUM" ] && [ "$PRNUM" != "$URL_NUM" ]; then
  die "the PR number ($PRNUM, from --pr or metadata.pr_number) does not match the anchor's pr_url (#$URL_NUM in $PR_REPO_Q); refusing rather than acting on the wrong PR — reconcile --pr / metadata.pr_number with metadata.pr_url" 1
fi
PRNUM="$URL_NUM"

# Best-effort: confirm the successor resolves. bead-rehome is the authority at
# consummation (it searches every store), so an unresolved successor here only
# warns — a false refusal on a cross-store successor would be worse.
if ! gc bd show "$SUCCESSOR" --json 2>/dev/null 9>&- | scrub | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
  warn "could not confirm successor $SUCCESSOR in the current store; bead-rehome validates it at dispose time (pass --successor-store rig:<name> if its prefix is ambiguous)"
fi

if [ "$DRY" -eq 1 ]; then
  printf '%s (dry run)\n  anchor:    %s [%s] merge_result=%s\n  successor: %s%s\n  kind:      %s\n  marker:    gc.pr_close_disposition_kind=%s gc.pr_close_disposition_successor=%s%s\n  pr:        #%s in %s %s\n' \
    "$PROG" "$ANCHOR" "$A_STATUS" "$A_MR" "$SUCCESSOR" "${STORE:+ ($STORE)}" "$KIND" \
    "$KIND" "$SUCCESSOR" "${STORE:+ gc.pr_close_disposition_successor_store=$STORE}" \
    "$PRNUM" "$PR_REPO_Q" "$( [ "$NO_CLOSE" -eq 1 ] && echo '(left open; --no-close-pr)' || echo '(will be closed)' )"
  exit 0
fi

# Stamp the marker before the close: a PR closed with no marker would abandon the
# anchor as an unknown close, the very thing this prevents. The update's exit
# decides whether it landed, so a refused stamp closes nothing.
SET_ARGS=(--set-metadata "gc.pr_close_disposition_kind=$KIND" \
          --set-metadata "gc.pr_close_disposition_successor=$SUCCESSOR")
# The store is part of the marker the closer hands to bead-rehome: an ambiguous
# successor needs it to resolve in the right store. Stamp it when given; when
# omitted, UNSET it, so an omitted store cannot silently inherit a stale value a
# prior disposition attempt left and consummate in the wrong store. Both edits
# ride one update, which bd applies whole or not at all.
if [ -n "$STORE" ]; then
  SET_ARGS+=(--set-metadata "gc.pr_close_disposition_successor_store=$STORE")
else
  SET_ARGS+=(--unset-metadata "gc.pr_close_disposition_successor_store")
fi
gc bd update "$ANCHOR" "${SET_ARGS[@]}" >/dev/null 2>&1 9>&- \
  || die "the store refused the disposition marker on $ANCHOR; NOT closing the PR, since a close now would abandon the anchor as an unknown close. Re-run once the store accepts the write" 1
# The stamp has landed, so the record lock goes free before GitHub is read.
exec 9>&-
echo "$PROG: $ANCHOR — recorded PR-close disposition ($KIND -> $SUCCESSOR${STORE:+ in $STORE})"

# Close the PR unless the caller closes it themselves. The closer consummates
# the terminal close once it reads the PR closed, however it reached CLOSED.
if [ "$NO_CLOSE" -eq 1 ]; then
  echo "$PROG: --no-close-pr: leaving PR#$PRNUM for you to close; $CLOSER disposes $ANCHOR once it reads the PR closed"
  exit 0
fi
command -v gh >/dev/null 2>&1 \
  || die "the marker is recorded but gh is not available, so PR#$PRNUM was NOT closed and may still be OPEN — close it by hand (or re-run once gh works), and $CLOSER disposes $ANCHOR once it reads the PR closed" 1

# Read the live PR once, pinned to the anchor's own repository (PR_REPO_Q from
# its pr_url, resolved above), and certify identity before any close. Keep gh's
# exit status — an unreadable state (gh failed, or empty output) must NOT be
# mistaken for a closed PR. Reading it as closed would leave the marker recorded
# while the PR may still be OPEN, a false success: the closer never sees a
# CLOSED PR to consummate the disposition. pipefail (set above) makes the pipe carry
# gh's non-zero status when gh fails.
PR_JSON=$(gh pr view "$PRNUM" --repo "$PR_REPO_Q" --json state,url,comments 2>/dev/null | scrub); rc=$?
if [ "$rc" -ne 0 ] || [ -z "$PR_JSON" ]; then
  die "the marker is recorded but PR#$PRNUM state could not be read from $PR_REPO_Q (gh pr view failed); the PR was NOT closed and may still be OPEN — close it by hand (or re-run once gh works), and $CLOSER disposes $ANCHOR once it reads the PR closed" 1
fi
# Certify the PR gh returned is the one the anchor records: #NUM resolves within
# PR_REPO_Q, but a transferred or renamed repo redirects, so a bare number can
# still land on a different PR. Compare the live url to the anchor's pr_url.
LIVE_URL=$(canon_pr_url "$(printf '%s' "$PR_JSON" | jq -r '.url // ""')")
if [ -z "$LIVE_URL" ] || [ "$(canon_pr_url "$PR_URL")" != "$LIVE_URL" ]; then
  die "PR#$PRNUM in $PR_REPO_Q resolves to '${LIVE_URL:-<none>}', not the anchor's pr_url '$PR_URL'; refusing to close — after a repo transfer or redirect a bare number can name a different PR. Close it by hand if this is expected, and $CLOSER disposes $ANCHOR once it reads the PR closed" 1
fi
PR_STATE=$(printf '%s' "$PR_JSON" | jq -r '.state // ""')
[ -n "$PR_STATE" ] || die "the marker is recorded but PR#$PRNUM returned no state from $PR_REPO_Q; the PR was NOT closed and may still be OPEN — close it by hand (or re-run once gh works), and $CLOSER disposes $ANCHOR once it reads the PR closed" 1
# Idempotent: never reopen or re-close a PR already closed.
if [ "$PR_STATE" = "OPEN" ]; then
  CLEAD="Closing as $KIND: disposition recorded on anchor $ANCHOR "
  CMT="${CLEAD}(successor $SUCCESSOR). The refinery disposes the anchor from this close; no rework-or-close decision is owed."
  [ -n "$NOTE" ] && CMT="$CMT $NOTE"
  # The comment is posted first and gates the close, so the PR never closes
  # without the reason it was closed for. A re-run after a failed close finds the
  # notice its first run posted, so it closes without posting a second one. The
  # notice is this disposition's when it opens with the same kind and anchor and
  # carries the city's mark. The recorded marker cannot stand in for that test: a
  # run whose comment failed recorded the marker too.
  CMARK=$("$PR_POST" mark 2>/dev/null) || CMARK=""
  POSTED=$(printf '%s' "$PR_JSON" | jq -r --arg lead "$CLEAD" --arg mark "$CMARK" '
    [ (.comments // [])[] | ((.body // "") | tostring) as $b
      | select(($mark != "") and ($b | startswith($lead)) and ($b | contains($mark))) ] | length' 2>/dev/null)
  case "$POSTED" in ''|*[!0-9]*) POSTED=0 ;; esac
  if [ "$POSTED" -gt 0 ]; then
    echo "$PROG: PR#$PRNUM already carries this disposition's closing comment; closing it without posting another"
  else
    "$PR_POST" comment --repo "$PR_REPO_Q" --pr "$PRNUM" --body "$CMT" >/dev/null 2>&1 \
      || die "the marker is recorded but the closing comment could not be posted on PR#$PRNUM, so the PR was NOT closed and is still OPEN; close it by hand (or re-run once gh works), and $CLOSER disposes $ANCHOR once it reads the PR closed" 1
  fi
  if gh pr close "$PRNUM" --repo "$PR_REPO_Q" >/dev/null 2>&1; then
    echo "$PROG: closed PR#$PRNUM as $KIND; $CLOSER disposes $ANCHOR once it next reads the PR"
  else
    die "the marker is recorded but 'gh pr close $PRNUM' failed and the PR is still OPEN; close it by hand (or re-run once gh works), and $CLOSER disposes $ANCHOR once it reads the PR closed" 1
  fi
elif [ "$PR_STATE" = "MERGED" ]; then
  echo "$PROG: PR#$PRNUM is already MERGED; the marker is recorded, and $CLOSER records the merge once it next reads the PR"
else
  echo "$PROG: PR#$PRNUM is already $PR_STATE; the marker is recorded, and $CLOSER disposes $ANCHOR once it next reads the PR"
fi
exit 0
