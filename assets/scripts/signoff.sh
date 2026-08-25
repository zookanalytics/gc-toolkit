#!/usr/bin/env bash
# signoff.sh — the single writer of gate verdicts (component-model I7: one
# audited writer for check.<gate> markers). Run once by the review agent after
# mol-review's review step produced a verdict:
#   signoff.sh --review-bead <id> --verdict approve|request-changes
#              [--notes-file <path>] [--reviewed-oid <oid>]
# approve: post the artifact (gh pr review --comment post-open; review-bead
# notes pre-open), stamp check.<name>=green@<reviewed-oid> on the anchor, and
# dismiss the city's own superseded CHANGES_REQUESTED review. request-changes:
# clear the marker and file ONE routed rework child — or, at the round cap,
# stamp check.<name>=exception@<head> and route the anchor to a human instead.
# The city never approves its own PRs: nothing here ever passes --approve.
# Callers: mol-review's verdict-and-drain step (the reviewing polecat).
# Exit: 0 recorded · 1 refused, nothing written · 2 a write did not read back
#       (the review bead is left open so the gate stays owed).
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: signoff.sh --review-bead <id> --verdict approve|request-changes
                  [--notes-file <path>] [--reviewed-oid <oid>]

  --review-bead  the dispatched review bead this verdict answers (required)
  --verdict      approve (the pass; posted as a COMMENT, never an approval)
                 or request-changes (required)
  --notes-file   the verdict body; default: the review bead's notes
  --reviewed-oid the commit the review pinned; default: the review bead's own
                 reviewed_oid (stamped at dispatch), else the live head of the
                 anchor's branch (git ls-remote origin <branch>)

env: GC_MAX_REVIEW_ROUNDS  rework rounds before the gate records
                           exception@<head> and routes to a human (default 3)
U
}

warn() { echo "signoff: $*" >&2; }

REVIEW_BEAD=""; VERDICT=""; NOTES_FILE=""; OID_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --review-bead)  REVIEW_BEAD="${2:-}";  shift 2 || { usage; exit 1; } ;;
    --verdict)      VERDICT="${2:-}";      shift 2 || { usage; exit 1; } ;;
    --notes-file)   NOTES_FILE="${2:-}";   shift 2 || { usage; exit 1; } ;;
    --reviewed-oid) OID_OVERRIDE="${2:-}"; shift 2 || { usage; exit 1; } ;;
    -h|--help)      usage; exit 0 ;;
    *) warn "unknown argument '$1'"; usage; exit 1 ;;
  esac
done
[ -n "$REVIEW_BEAD" ] || { usage; exit 1; }
case "$VERDICT" in
  approve|request-changes) ;;
  *) warn "--verdict must be approve or request-changes (got '$VERDICT')"; usage; exit 1 ;;
esac
if [ -n "$NOTES_FILE" ] && [ ! -r "$NOTES_FILE" ]; then
  warn "--notes-file '$NOTES_FILE' is not readable; nothing written"; exit 1
fi

# bd JSON with the C0 set stripped: a raw control byte in notes breaks jq.
bd_json()   { gc bd "$@" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037'; }
row_meta()  { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }
row_field() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0][$k] // "") | tostring' 2>/dev/null; }
is_rows()   { printf '%s' "$1" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; }

REVIEW_ROW=$(bd_json show "$REVIEW_BEAD")
is_rows "$REVIEW_ROW" || { warn "review bead $REVIEW_BEAD does not resolve; nothing written"; exit 1; }
CHECK_NAME=$(row_meta "$REVIEW_ROW" check_name)
[ -n "$CHECK_NAME" ] || CHECK_NAME=codex

# The anchor the gate lands on: the durable anchor_bead stamp first, the
# blocks edge second. Unresolvable is a refusal — a verdict with nowhere to
# record its marker must not write anything.
ANCHOR=$(row_meta "$REVIEW_ROW" anchor_bead)
if [ -z "$ANCHOR" ]; then
  ANCHOR=$(bd_json dep list "$REVIEW_BEAD" --direction=up -t blocks \
    | jq -r 'if type == "array" then (.[0].id // "") else "" end' 2>/dev/null)
fi
[ -n "$ANCHOR" ] || { warn "no anchor resolves for $REVIEW_BEAD (no metadata.anchor_bead, no blocks edge); refusing — the gate has nowhere to land"; exit 1; }
ANCHOR_ROW=$(bd_json show "$ANCHOR")
is_rows "$ANCHOR_ROW" || { warn "anchor $ANCHOR does not resolve; nothing written"; exit 1; }

# Post-open iff the ANCHOR names a PR.
PR_NUMBER=$(row_meta "$ANCHOR_ROW" pr_number)
PR_URL=$(row_meta "$ANCHOR_ROW" pr_url)
POST_OPEN=""
{ [ -n "$PR_NUMBER" ] || [ -n "$PR_URL" ]; } && POST_OPEN=1
PR_REPO_Q=""; PR_REPO=""; PR_HOST=""
if [ -n "$POST_OPEN" ]; then
  [ -n "$PR_URL" ] || PR_URL=$(row_meta "$REVIEW_ROW" pr_url)
  # Pin host+repo from the bead's own pr_url: a bare PR number names a
  # different pull request per repository per host.
  PR_REPO_Q=$(printf '%s' "$PR_URL" \
    | sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/][^/]*\)/\([^/][^/]*/[^/][^/]*\)/pull/[0-9].*#\1/\2#p')
  [ -n "$PR_REPO_Q" ] || { warn "post-open anchor $ANCHOR carries no parseable pr_url ('$PR_URL'); refusing to run unpinned GitHub calls"; exit 1; }
  PR_REPO="${PR_REPO_Q#*/}"
  PR_HOST="${PR_REPO_Q%%/*}"
  if [ -z "$PR_NUMBER" ]; then
    PR_NUMBER="${PR_URL##*/pull/}"; PR_NUMBER="${PR_NUMBER%%[!0-9]*}"
  fi
  [ -n "$PR_NUMBER" ] || { warn "post-open anchor $ANCHOR has no resolvable PR number"; exit 1; }
fi

BRANCH=$(row_meta "$ANCHOR_ROW" branch)
[ -n "$BRANCH" ] || BRANCH=$(row_meta "$REVIEW_ROW" review_branch)
# Evidence binding, in order: the caller's --reviewed-oid; the reviewed_oid the
# DISPATCH pinned on the review bead (gate-ensure/pr-facts stamp the live head
# at dispatch time); only then the live head. The live-head fallback is the
# weakest binding — a push between review and signoff would stamp green at a
# commit nobody reviewed, so a dispatch-pinned oid always wins (a moved head
# then correctly fails the merge's green@<live head> condition and re-gates).
REVIEWED_OID="$OID_OVERRIDE"
[ -n "$REVIEWED_OID" ] || REVIEWED_OID=$(row_meta "$REVIEW_ROW" reviewed_oid)
if [ -z "$REVIEWED_OID" ]; then
  [ -n "$BRANCH" ] || { warn "anchor $ANCHOR names no branch and no --reviewed-oid was given; nothing to bind the verdict to"; exit 1; }
  REVIEWED_OID=$(git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk 'NR == 1 {print $1}')
fi
case "$REVIEWED_OID" in
  ''|*[!0-9a-fA-F]*) warn "no usable reviewed oid for branch '${BRANCH:-?}' (got '${REVIEWED_OID:-}'); nothing written"; exit 1 ;;
esac

# The artifact body. It always names the anchor and the exact commit judged,
# so the posted comment is traceable back to the gate it satisfied.
BODY_FILE=$(mktemp) || { warn "mktemp failed"; exit 1; }
trap 'rm -f "$BODY_FILE"' EXIT
if [ -n "$NOTES_FILE" ]; then
  cat "$NOTES_FILE" > "$BODY_FILE"
else
  printf '%s' "$REVIEW_ROW" | jq -r '.[0].notes // ""' > "$BODY_FILE" 2>/dev/null
fi
[ -s "$BODY_FILE" ] || printf 'Signoff verdict: %s (check %s).\n' "$VERDICT" "$CHECK_NAME" > "$BODY_FILE"
printf '\nAnchor: %s — check.%s @ %s\n' "$ANCHOR" "$CHECK_NAME" "$REVIEWED_OID" >> "$BODY_FILE"

post_artifact() {
  if [ -n "$POST_OPEN" ]; then
    # COMMENT for both verdicts, NEVER --approve: approval is external/human,
    # and the merge is held by the recorded marker, not by a bot review.
    gh pr review "$PR_NUMBER" --repo "$PR_REPO_Q" --comment --body-file "$BODY_FILE" >/dev/null 2>&1 \
      || warn "could not post the review comment on PR#$PR_NUMBER; the recorded marker still governs"
  else
    gc bd update "$REVIEW_BEAD" --set-metadata "reviewed_oid=$REVIEWED_OID" \
      --append-notes "$(cat "$BODY_FILE")" >/dev/null 2>&1 || true
    local got; got=$(row_meta "$(bd_json show "$REVIEW_BEAD")" reviewed_oid)
    if [ "$got" != "$REVIEWED_OID" ]; then
      warn "pre-open verdict did not read back on $REVIEW_BEAD (reviewed_oid='$got'); review left open for a retry"
      exit 2
    fi
  fi
}

stamp_anchor() { # <key> <value>: write, read back, exit 2 when it did not stick
  gc bd update "$ANCHOR" --set-metadata "$1=$2" >/dev/null 2>&1 || true
  local got; got=$(row_meta "$(bd_json show "$ANCHOR")" "$1")
  if [ "$got" != "$2" ]; then
    warn "$1 did not read back on anchor $ANCHOR (got '${got:-}', want '$2'); review bead left OPEN so the gate stays owed"
    exit 2
  fi
}

close_review() {
  gc bd update "$REVIEW_BEAD" --set-metadata gc.outcome=recorded --status=closed >/dev/null 2>&1 || true
  local row st oc
  row=$(bd_json show "$REVIEW_BEAD")
  st=$(printf '%s' "$row" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null)
  oc=$(row_meta "$row" gc.outcome)
  if [ "$st" != "closed" ] || [ "$oc" != "recorded" ]; then
    warn "review bead $REVIEW_BEAD close did not read back (status='$st' gc.outcome='$oc')"
    exit 2
  fi
}

# A pass at a new head retracts the city's OWN superseded CHANGES_REQUESTED,
# else the PR stays BLOCKED on a dead commit while the bead reads green.
# Guards, all fail-closed: our handle only (a human's block is a real veto);
# a commit other than the reviewed one; the reviewed commit still the live
# head; auto-merge definitely disarmed (a dismissal merges server-side past
# the recorded approval requirement otherwise); signoff_dismissed stamped and
# read back BEFORE the irreversible dismissal.
dismiss_superseded() {
  [ -n "$POST_OPEN" ] || return 0
  local handle live raw rc stale rid paired
  handle=$(gh api --hostname "$PR_HOST" user -q .login 2>/dev/null)
  [ -n "$handle" ] || return 0
  live=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" --json headRefOid -q .headRefOid 2>/dev/null)
  [ "$live" = "$REVIEWED_OID" ] || return 0
  raw=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" --json autoMergeRequest 2>/dev/null) || return 0
  printf '%s' "$raw" | jq -e 'type == "object" and has("autoMergeRequest") and .autoMergeRequest == null' >/dev/null 2>&1 || return 0
  raw=$(gh api --hostname "$PR_HOST" --paginate "repos/$PR_REPO/pulls/$PR_NUMBER/reviews?per_page=100" --jq '.[]' 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] || return 0
  stale=$(printf '%s' "$raw" | jq -rs --arg h "$handle" --arg oid "$REVIEWED_OID" \
    '.[] | select((.user.login // "") == $h and .state == "CHANGES_REQUESTED" and (.commit_id // "") != $oid) | .id' 2>/dev/null)
  for rid in $stale; do
    gc bd update "$ANCHOR" --set-metadata "signoff_dismissed=$rid@$REVIEWED_OID" >/dev/null 2>&1 || true
    paired=$(row_meta "$(bd_json show "$ANCHOR")" signoff_dismissed)
    if [ "$paired" != "$rid@$REVIEWED_OID" ]; then
      warn "signoff_dismissed did not stick on $ANCHOR; NOT dismissing review $rid"
      continue
    fi
    gh api --hostname "$PR_HOST" -X PUT "repos/$PR_REPO/pulls/$PR_NUMBER/reviews/$rid/dismissals" \
      -f message="Superseded by the re-gate at $REVIEWED_OID: the $CHECK_NAME gate is green at the live head. Approval remains external." \
      -f event=DISMISS >/dev/null 2>&1 \
      || warn "could not dismiss superseded review $rid on PR#$PR_NUMBER; the next round retries"
  done
}

# Rework rounds already spent on this anchor: one routed child per round, each
# stamped source_review_bead by the signoff that filed it (the primary count).
# The backup is dispatch_count on the ANCHOR — that is where gate-ensure
# writes it. An unreadable ledger reads 0 — capping on a guess parks live work.
count_rounds() {
  local kids n dc
  kids=$(bd_json dep list "$ANCHOR" --direction=down -t blocks)
  n=$(printf '%s' "$kids" | jq '[.[] | select((.metadata.source_review_bead // "") != "")] | length' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  dc=$(row_meta "$ANCHOR_ROW" dispatch_count)
  case "$dc" in ''|*[!0-9]*) dc=0 ;; esac
  [ "$dc" -gt "$n" ] && n="$dc"
  printf '%s' "$n"
}

if [ "$VERDICT" = "approve" ]; then
  post_artifact
  stamp_anchor "check.$CHECK_NAME" "green@$REVIEWED_OID"
  dismiss_superseded
  close_review
  echo "signoff: check.$CHECK_NAME=green@$REVIEWED_OID recorded on $ANCHOR; review $REVIEW_BEAD closed"
  exit 0
fi

ROUNDS=$(count_rounds)
CAP="${GC_MAX_REVIEW_ROUNDS:-3}"
case "$CAP" in ''|*[!0-9]*) CAP=3 ;; esac
post_artifact

if [ "$ROUNDS" -ge "$CAP" ]; then
  # Terminal verdict: ONE write under check.<name> (the exception), never a
  # clear beside it — an absent marker re-arms the dispatch this cap refuses.
  stamp_anchor "check.$CHECK_NAME" "exception@$REVIEWED_OID"
  gc bd update "$ANCHOR" \
    --set-metadata gc.routed_to=human \
    --set-metadata "blocked_reason=signoff did not converge after $ROUNDS rework rounds (cap $CAP); findings are in the review beads under this anchor" \
    >/dev/null 2>&1 || true
  if [ "$(row_meta "$(bd_json show "$ANCHOR")" gc.routed_to)" != "human" ]; then
    warn "gc.routed_to=human did not read back on $ANCHOR; review left open for a retry"
    exit 2
  fi
  close_review
  echo "signoff: round cap on $ANCHOR ($ROUNDS/$CAP) — check.$CHECK_NAME=exception@$REVIEWED_OID, anchor routed to human, no rework filed"
  exit 0
fi

# Under the cap: the head is no longer gate-validated — clear the marker so
# nothing opens or merges it before the rework lands, then file ONE child.
gc bd update "$ANCHOR" --unset-metadata "check.$CHECK_NAME" >/dev/null 2>&1 || true
GOT=$(row_meta "$(bd_json show "$ANCHOR")" "check.$CHECK_NAME")
if [ -n "$GOT" ]; then
  warn "check.$CHECK_NAME still reads '$GOT' on $ANCHOR after the clear; review left open for a retry"
  exit 2
fi

FIX_POOL=$(row_meta "$REVIEW_ROW" fix_target_pool)
[ -n "$FIX_POOL" ] || FIX_POOL="${GC_RIG:+$GC_RIG/}gc-toolkit.polecat"
FIX_TARGET=$(row_meta "$ANCHOR_ROW" merged_target)
[ -n "$FIX_TARGET" ] || FIX_TARGET=$(row_meta "$ANCHOR_ROW" target)
[ -n "$FIX_TARGET" ] || FIX_TARGET=$(row_meta "$REVIEW_ROW" review_base)
if [ -z "$FIX_TARGET" ]; then
  warn "no landing target resolves for the rework child (anchor merged_target/target, review_base all empty); review left open"
  exit 2
fi
REASON_HEAD=$(head -n 1 "$BODY_FILE" | cut -c1-200)
if [ -n "$POST_OPEN" ]; then
  TITLE="Rework PR#$PR_NUMBER: address signoff findings"
else
  TITLE="Rework branch $BRANCH: address pre-open signoff findings"
fi
FIX_BEAD=$(gc bd create "$TITLE" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
if [ -z "$FIX_BEAD" ]; then
  warn "could not create the rework child; review left open for a retry"
  exit 2
fi

# The stamped fields ARE the work order: branch/target say what to resume and
# where it lands, existing_pr keeps the rework on THIS PR, the route says who
# claims it (stamp-don't-sling: the pool's own demand offers it).
META=(
  --set-metadata "branch=$BRANCH"
  --set-metadata "target=$FIX_TARGET"
  --set-metadata "rejection_reason=signoff requested changes (round $((ROUNDS + 1))): $REASON_HEAD"
  --set-metadata "source_review_bead=$REVIEW_BEAD"
  --set-metadata "merge_strategy=mr"
)
if [ -n "$POST_OPEN" ]; then
  META+=(--set-metadata "existing_pr=$PR_URL" --set-metadata "pr_url=$PR_URL" --set-metadata "pr_number=$PR_NUMBER")
fi
META+=(--set-metadata "gc.routed_to=$FIX_POOL")
gc bd update "$FIX_BEAD" "${META[@]}" >/dev/null 2>&1 || true

FIX_ROW=$(bd_json show "$FIX_BEAD")
MISSING=$(printf '%s' "$FIX_ROW" | jq -r \
  --arg b "$BRANCH" --arg t "$FIX_TARGET" --arg p "$FIX_POOL" --arg pr "${POST_OPEN:+$PR_URL}" '
  (.[0] // {}) as $x | ($x.metadata // {}) as $m | [
    (if ($m.branch // "") == $b then empty else "branch" end),
    (if ($m.target // "") == $t then empty else "target" end),
    (if ($m.source_review_bead // "") != "" then empty else "source_review_bead" end),
    (if ($m.merge_strategy // "") == "mr" then empty else "merge_strategy" end),
    (if ($m.rejection_reason // "") != "" then empty else "rejection_reason" end),
    (if $pr == "" or ($m.existing_pr // "") == $pr then empty else "pr_fields" end),
    (if (($m["gc.routed_to"] // "") == $p) or (($x.assignee // "") != "") then empty else "gc.routed_to" end)
  ] | join(",") | if . == "" then "ok" else . end' 2>/dev/null)
if [ "$MISSING" != "ok" ]; then
  warn "rework child $FIX_BEAD work order incomplete (${MISSING:-unreadable}); review left open — repair with: gc bd show $FIX_BEAD --json | jq '.[0].metadata'"
  exit 2
fi
gc bd dep add "$FIX_BEAD" "$ANCHOR" --type=blocks >/dev/null 2>&1 \
  || warn "could not add the blocks edge $FIX_BEAD -> $ANCHOR; the child is routed and the cleared marker still holds the gate"

close_review
echo "signoff: request-changes recorded on $ANCHOR (round $((ROUNDS + 1))/$CAP) — check.$CHECK_NAME cleared, rework $FIX_BEAD routed to $FIX_POOL"
exit 0
