#!/usr/bin/env bash
# pr-dispose — record a deliberate PR-close disposition on the OPEN anchor, then
# close the PR, so the refinery's pr-facts.sh consummates the terminal close
# through bead-rehome.sh instead of filing a rework-or-close visit that re-asks
# a decision already made.
#
# It stamps three metadata keys naming the intended bead-rehome invocation —
# gc.pr_close_disposition_kind, gc.pr_close_disposition_successor, and an
# optional gc.pr_close_disposition_successor_store — reads them back, and closes
# the PR with an explaining comment (unless --no-close-pr, for an operator who
# will close it in the UI). It does NOT close the anchor: that terminal close is
# pr-facts's, the single consummation point, which stamps gc.superseded_by (the
# terminal state doctor/check-closed-implies-landed accepts) and retires any
# rework-or-close visit an earlier pass filed.
#
# The anchor must be OPEN and carrying merge_result=pull_request — the state
# pr-facts enumerates. An anchor already disposed (gc.superseded_by set) is a
# no-op; an anchor past that state (abandoned, merged) is refused, with
# bead-rehome.sh named as the direct verb for it.
#
#   pr-dispose.sh --anchor <bead-id> --successor <bead-id> \
#                 --kind re-homed|folded|fixed-upstream|duplicate|not-needed \
#                 [--successor-store rig:<name>] [--note "<why>"] \
#                 [--pr <num>] [--no-close-pr] [--dry-run]
#
# Under every kind but not-needed the successor is the bead that carries the
# work now. Under not-needed nothing carries it, and the successor is the
# evidence that concluded the bead was unnecessary — typically the visit bead
# from the sitting that ruled. It is required either way, because it is the
# whole of what distinguishes a sound disposition from a careless close.
#
# Callers: converse dispositions and operator close-outs — the PR side of the
# bead-rehome disposition doctrine (docs/state-machine.md "Disposition").
# The current store must be the anchor's rig (GC_RIG, or run in its checkout).
# Exit: 0 stamped (PR closed) or already disposed · 1 error · 2 usage.
set -uo pipefail

PROG="pr-dispose"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
warn() { echo "$PROG: $1" >&2; }
die()  { echo "$PROG: $1" >&2; exit "${2:-1}"; }

usage() {
  cat >&2 <<'U'
usage: pr-dispose.sh --anchor <bead-id> --successor <bead-id>
                     --kind re-homed|folded|fixed-upstream|duplicate|not-needed
                     [--successor-store rig:<name>] [--note "<one sentence>"]
                     [--pr <num>] [--no-close-pr] [--dry-run]

Records a deliberate supersede/not-planned PR-close disposition on the OPEN
anchor and closes the PR; the refinery's pr-facts.sh then closes the anchor
through bead-rehome.sh instead of filing a rework-or-close visit.

  --anchor          the open work bead the PR gates (merge_result=pull_request)
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
# The kind is a closed set, the same one bead-rehome enforces: pr-facts hands it
# straight to bead-rehome, so a kind refused there must be refused here.
case "$KIND" in
  re-homed|folded|fixed-upstream|duplicate|not-needed) ;;
  *) die "--kind must be one of re-homed|folded|fixed-upstream|duplicate|not-needed (got '$KIND')" 2 ;;
esac

command -v gc >/dev/null 2>&1 || die "gc is required" 1
command -v jq >/dev/null 2>&1 || die "jq is required" 1

# Read the anchor from the current store.
AJSON=$(gc bd show "$ANCHOR" --json 2>/dev/null | scrub)
printf '%s' "$AJSON" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
  || die "could not read anchor $ANCHOR from the current store; set GC_RIG to its rig, or run in that rig's checkout" 1
A_STATUS=$(printf '%s' "$AJSON" | jq -r '.[0].status // ""')
A_MR=$(printf '%s' "$AJSON" | jq -r '(.[0].metadata.merge_result // "") | tostring')
A_PRIOR=$(printf '%s' "$AJSON" | jq -r '.[0].metadata["gc.superseded_by"] // .[0].metadata.superseded_by // ""')
[ -n "$PRNUM" ] || PRNUM=$(printf '%s' "$AJSON" | jq -r '(.[0].metadata.pr_number // "") | tostring')

# Already disposed: bead-rehome already stamped a pointer. Nothing to add.
if [ -n "$A_PRIOR" ]; then
  echo "$PROG: $ANCHOR already carries gc.superseded_by=$A_PRIOR — already disposed, nothing to do"
  exit 0
fi
# The marker only means something on the state pr-facts enumerates: an OPEN
# pull_request anchor. Past that, pr-facts will not see it, so refuse and name
# the direct verb rather than stamp a marker nothing consummates.
if [ "$A_STATUS" != "open" ] || [ "$A_MR" != "pull_request" ]; then
  die "$ANCHOR is status='$A_STATUS' merge_result='${A_MR:-unset}', not an OPEN pull_request anchor pr-facts can consummate. Dispose an anchor past that state directly: bead-rehome.sh --origin $ANCHOR --successor $SUCCESSOR --kind $KIND" 1
fi
case "$PRNUM" in
  ''|*[!0-9]*) die "no numeric PR number on $ANCHOR (metadata.pr_number) and none given via --pr" 1 ;;
esac

# Best-effort: confirm the successor resolves. bead-rehome is the authority at
# consummation (it searches every store), so an unresolved successor here only
# warns — a false refusal on a cross-store successor would be worse.
if ! gc bd show "$SUCCESSOR" --json 2>/dev/null | scrub | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
  warn "could not confirm successor $SUCCESSOR in the current store; bead-rehome validates it at dispose time (pass --successor-store rig:<name> if its prefix is ambiguous)"
fi

if [ "$DRY" -eq 1 ]; then
  printf '%s (dry run)\n  anchor:    %s [%s] merge_result=%s\n  successor: %s%s\n  kind:      %s\n  marker:    gc.pr_close_disposition_kind=%s gc.pr_close_disposition_successor=%s%s\n  pr:        #%s %s\n' \
    "$PROG" "$ANCHOR" "$A_STATUS" "$A_MR" "$SUCCESSOR" "${STORE:+ ($STORE)}" "$KIND" \
    "$KIND" "$SUCCESSOR" "${STORE:+ gc.pr_close_disposition_successor_store=$STORE}" \
    "$PRNUM" "$( [ "$NO_CLOSE" -eq 1 ] && echo '(left open; --no-close-pr)' || echo '(will be closed)' )"
  exit 0
fi

# Stamp the marker and read it back: a marker that did not land would let the PR
# close abandon the anchor as an unknown close, the very thing this prevents.
SET_ARGS=(--set-metadata "gc.pr_close_disposition_kind=$KIND" \
          --set-metadata "gc.pr_close_disposition_successor=$SUCCESSOR")
# The store is part of the marker pr-facts hands to bead-rehome: an ambiguous
# successor needs it to resolve in the right store. Stamp it when given; when
# omitted, UNSET it, so an omitted store cannot silently inherit a stale value a
# prior disposition attempt left and consummate in the wrong store. The read-back
# below asserts the landed store equals the requested one — "" when omitted.
if [ -n "$STORE" ]; then
  SET_ARGS+=(--set-metadata "gc.pr_close_disposition_successor_store=$STORE")
else
  SET_ARGS+=(--unset-metadata "gc.pr_close_disposition_successor_store")
fi
gc bd update "$ANCHOR" "${SET_ARGS[@]}" >/dev/null 2>&1 \
  || die "could not stamp the disposition marker on $ANCHOR" 1
CJSON=$(gc bd show "$ANCHOR" --json 2>/dev/null | scrub)
GOT_KIND=$(printf '%s' "$CJSON" | jq -r '.[0].metadata["gc.pr_close_disposition_kind"] // ""')
GOT_SUCC=$(printf '%s' "$CJSON" | jq -r '.[0].metadata["gc.pr_close_disposition_successor"] // ""')
GOT_STORE=$(printf '%s' "$CJSON" | jq -r '.[0].metadata["gc.pr_close_disposition_successor_store"] // ""')
if [ "$GOT_KIND" != "$KIND" ] || [ "$GOT_SUCC" != "$SUCCESSOR" ] || [ "$GOT_STORE" != "$STORE" ]; then
  die "the disposition marker did NOT stick on $ANCHOR (read back kind='$GOT_KIND' successor='$GOT_SUCC' store='$GOT_STORE', wanted kind='$KIND' successor='$SUCCESSOR' store='$STORE'); NOT closing the PR — a close now would abandon the anchor as an unknown close, or consummate it in the wrong store. Re-run once the store accepts the write" 1
fi
echo "$PROG: $ANCHOR — recorded PR-close disposition ($KIND -> $SUCCESSOR${STORE:+ in $STORE})"

# Close the PR unless the caller closes it themselves. pr-facts consummates the
# terminal close on its next pass however the PR reaches CLOSED.
if [ "$NO_CLOSE" -eq 1 ]; then
  echo "$PROG: --no-close-pr: leaving PR#$PRNUM for you to close; pr-facts auto-disposes $ANCHOR once it is CLOSED"
  exit 0
fi
command -v gh >/dev/null 2>&1 \
  || die "the marker is recorded but gh is not available, so PR#$PRNUM was NOT closed and may still be OPEN — close it by hand (or re-run once gh works), and pr-facts auto-disposes $ANCHOR once it is CLOSED" 1

# Origin repo, resolved the way pr-facts.sh resolves it.
ORIGIN_HOST=""; ORIGIN_REPO=""
u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
if [ -z "$ORIGIN_REPO" ]; then
  die "the marker is recorded but the origin repo could not be resolved from this checkout, so PR#$PRNUM was NOT closed and may still be OPEN — close it by hand (or re-run in the anchor's checkout), and pr-facts auto-disposes $ANCHOR once it is CLOSED" 1
fi

# Idempotent: never reopen or re-close a PR already closed. Keep gh's exit
# status — an unreadable state (gh failed, or empty output) must NOT be mistaken
# for a closed PR. Reading it as closed would leave the marker recorded while
# the PR may still be OPEN, a false success: pr-facts never sees a CLOSED PR to
# consummate the disposition. pipefail (set above) makes the pipe carry gh's
# non-zero status when gh fails.
if PR_STATE=$(gh pr view "$PRNUM" --repo "$ORIGIN_HOST/$ORIGIN_REPO" --json state --jq '.state' 2>/dev/null | scrub) \
   && [ -n "$PR_STATE" ]; then
  if [ "$PR_STATE" = "OPEN" ]; then
    CMT="Closing as $KIND: disposition recorded on anchor $ANCHOR (successor $SUCCESSOR). The refinery disposes the anchor from this close; no rework-or-close decision is owed."
    [ -n "$NOTE" ] && CMT="$CMT $NOTE"
    if gh pr close "$PRNUM" --repo "$ORIGIN_HOST/$ORIGIN_REPO" --comment "$CMT" >/dev/null 2>&1; then
      echo "$PROG: closed PR#$PRNUM as $KIND; pr-facts auto-disposes $ANCHOR on its next pass"
    else
      die "the marker is recorded but 'gh pr close $PRNUM' failed and the PR is still OPEN; close it by hand (or re-run once gh works), and pr-facts auto-disposes $ANCHOR once it is CLOSED" 1
    fi
  else
    echo "$PROG: PR#$PRNUM is already $PR_STATE; the marker is recorded, and pr-facts auto-disposes $ANCHOR on its next pass"
  fi
else
  die "the marker is recorded but PR#$PRNUM state could not be read (gh pr view failed); the PR was NOT closed and may still be OPEN — close it by hand (or re-run once gh works), and pr-facts auto-disposes $ANCHOR once it is CLOSED" 1
fi
exit 0
