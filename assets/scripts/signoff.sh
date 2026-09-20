#!/usr/bin/env bash
# signoff.sh — the single writer of gate verdicts (component-model I7: one
# audited writer for check.<gate> markers). Run once by the review agent after
# mol-review's review step produced a verdict:
#   signoff.sh --review-bead <id> --verdict approve|request-changes
#              [--notes-file <path>] [--reviewed-oid <oid>]
# Both verdicts first record reviewed_oid on the review bead. A lane state names
# no commit, but lane-state.sh derives green only from a local backing bead that
# carries a reviewed_oid, so recording it here is what lets an approve close back
# the lane.
# approve: post the artifact (gh pr review --comment post-open; review-bead
# notes pre-open), stamp check.<name>=green on the anchor, and dismiss the
# city's own superseded CHANGES_REQUESTED review. request-changes: clear the
# marker, returning the lane to unreviewed, and file ONE routed rework child.
# Convergence is judged, not counted. The validator rules whether a further
# whole-diff review is warranted once the must-fix set closes
# (specs/tk-ztapg/review-cycle-architecture.md), so request-changes files a
# rework child on every round and this script bounds none.
# The city never approves its own PRs: nothing here ever passes --approve.
# A lane state is a state of the lane, never a claim about a commit: the marker
# is one bare word, a verdict binds to no oid, and a commit landing on the
# branch neither stales a verdict nor buys a review. The reviewed oid survives
# as the artifact's audit trail and as the dispatch pin mol-review reads.
# The pin still names real content, though: commits added on top of it leave it
# reachable and change nothing here, but a rewrite that drops it from the
# branch (rebase, amend, force-push) means mol-review read and tested a commit
# nobody can merge. Both verdicts are refused on a gone pin — no marker, no
# rework, no round spent — and the review bead is closed gc.outcome=superseded
# instead of recorded, so gate-ensure's in-flight probe stops seeing it and
# pours a fresh review at the live head next pass.
# Both are refused on an already-closed review bead: signoff closes the bead
# itself, last, so a closed one was recorded or retired before it was judged.
# Callers: mol-review's verdict-and-drain step (the reviewing polecat).
# Exit: 0 recorded, or refused-as-superseded with the review closed for a fresh
#       dispatch · 1 refused, no verdict written · 2 a write did not read back
#       (the review bead is left open so the gate stays owed).
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# The finding-bead primitive. request-changes files the reviewer's objections
# through it as beads beside the fix unit, and approve closes the lane's
# still-unruled findings through it. Overridable so the hermetic test can stand
# in for it without a live store.
FINDING="${GC_FINDING_TOOL:-$HERE/finding.sh}"
# The route gate (pool-route.sh) lives beside this script; the rework route is
# proved through it before the fix child is filed.
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
# The single writer of the workflow-owned `status:` PR label. A verdict is the
# event-precise flip: request-changes sets the PR working (a rework child now
# stands on it), the cap park sets needs-attention, and an approve reconciles to
# the current state. Post-open only.
PR_STATUS_LABEL="${GC_PR_STATUS_LABEL_TOOL:-$HERE/pr-status-label.sh}"

usage() {
  cat >&2 <<'U'
usage: signoff.sh --review-bead <id> --verdict approve|request-changes
                  [--notes-file <path>] [--findings-file <path>]
                  [--reviewed-oid <oid>]

  --review-bead  the dispatched review bead this verdict answers (required)
  --verdict      approve (the pass; posted as a COMMENT, never an approval)
                 or request-changes (required)
  --notes-file   the verdict body; default: the review bead's notes
  --findings-file
                 the structured finding set as a JSON array, one object per
                 blocking finding, each with a rebase-stable `locus` (a file and
                 symbol or section, never a line or oid) and a `message`; `[]` on
                 approve. request-changes files each as a first-class finding bead
                 beside the rework child, deduped on locus and message. Default:
                 none filed, and the findings live only in the verdict prose.
  --reviewed-oid the commit the review read; default: the review bead's own
                 reviewed_oid (stamped at dispatch), else the live head of the
                 anchor's branch (git ls-remote origin <branch>). It names the
                 commit in the posted artifact; it does not bind the marker,
                 which is a bare lane state — except that a pin the branch no
                 longer carries (rewritten out from under it) is refused, not
                 recorded. Whichever source wins is written back to the review
                 bead as the commit this verdict judged.
U
}

warn() { echo "signoff: $*" >&2; }

ANCHOR=""
REVIEW_BEAD=""; VERDICT=""; NOTES_FILE=""; OID_OVERRIDE=""; FINDINGS_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --review-bead)  REVIEW_BEAD="${2:-}";     shift 2 || { usage; exit 1; } ;;
    --verdict)      VERDICT="${2:-}";         shift 2 || { usage; exit 1; } ;;
    --notes-file)   NOTES_FILE="${2:-}";      shift 2 || { usage; exit 1; } ;;
    --findings-file) FINDINGS_FILE="${2:-}";  shift 2 || { usage; exit 1; } ;;
    --reviewed-oid) OID_OVERRIDE="${2:-}";    shift 2 || { usage; exit 1; } ;;
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
if [ -n "$FINDINGS_FILE" ] && [ ! -r "$FINDINGS_FILE" ]; then
  warn "--findings-file '$FINDINGS_FILE' is not readable; nothing written"; exit 1
fi

# bd JSON with the C0 set stripped: a raw control byte in notes breaks jq.
bd_json()   { gc bd "$@" --json 2>/dev/null | scrub; }
row_meta()  { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }
row_field() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0][$k] // "") | tostring' 2>/dev/null; }
is_rows()   { printf '%s' "$1" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; }

# Read the reviewer's structured findings — a JSON array of {locus, message} —
# and file each as a finding bead through the finding primitive, deduped by
# finding.key. Prints the finding ids, one per line. Best-effort: a store that
# will not take a finding costs that finding, never the rework dispatch the
# merge is held by, so a failure warns and the caller proceeds. The reviewer's
# prose verdict is still the fix unit's rejection_reason and the review bead's
# notes; the beads are the queryable record the validator and gate readers use.
file_findings() { # <anchor> <lane> <findings-file>
  local anchor="$1" lane="$2" ff="$3" obj locus message fid
  [ -n "$ff" ] && [ -r "$ff" ] || return 0
  if ! jq -e 'type == "array"' "$ff" >/dev/null 2>&1; then
    warn "findings file is not a JSON array; no findings filed (the rework child still holds the merge)"
    return 0
  fi
  while IFS= read -r obj; do
    [ -n "$obj" ] || continue
    locus=$(printf '%s' "$obj" | jq -r '.locus // ""' 2>/dev/null)
    message=$(printf '%s' "$obj" | jq -r '.message // ""' 2>/dev/null)
    [ -n "$locus" ] && [ -n "$message" ] || continue
    if fid=$("$FINDING" upsert --anchor "$anchor" --lane "$lane" --locus "$locus" --message "$message" 2>/dev/null) && [ -n "$fid" ]; then
      printf '%s\n' "$fid"
    else
      warn "could not file finding for locus '$locus'; it is left to the verdict prose"
    fi
  done < <(jq -c '.[]?' "$ff" 2>/dev/null)
}

# Both verbs write to the anchor; these two read and write it.
stamp_anchor() { # <key> <value> [note]: write, read back, exit 2 when it did not stick
  local args=(--set-metadata "$1=$2")
  [ $# -lt 3 ] || args+=(--append-notes "$3")
  gc bd update "$ANCHOR" "${args[@]}" >/dev/null 2>&1 || true
  local got; got=$(row_meta "$(bd_json show "$ANCHOR")" "$1")
  if [ "$got" != "$2" ]; then
    warn "$1 did not read back on anchor $ANCHOR (got '${got:-}', want '$2'); review bead left OPEN so the gate stays owed"
    exit 2
  fi
}

REVIEW_ROW=$(bd_json show "$REVIEW_BEAD")
is_rows "$REVIEW_ROW" || { warn "review bead $REVIEW_BEAD does not resolve; nothing written"; exit 1; }

# A verdict answering a closed bead may not clear a marker or spend a round:
# the dispatch it answers was already recorded, or retired unjudged.
REVIEW_STATUS=$(printf '%s' "$REVIEW_ROW" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null)
if [ "$REVIEW_STATUS" = "closed" ]; then
  warn "review bead $REVIEW_BEAD is already closed (gc.outcome='$(row_meta "$REVIEW_ROW" gc.outcome)'); refusing — a retired dispatch records no verdict. Nothing written; re-dispatch the gate if it is still owed."
  exit 1
fi
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
# The commit this verdict READ, in order: the caller's --reviewed-oid; the
# reviewed_oid the DISPATCH pinned on the review bead (gate-ensure/pr-facts
# stamp the live head at dispatch time); only then the live head. It names the
# commit in the posted artifact and in the pre-open record, so a dispatch pin
# wins over a live head read after the fact. The lane state it accompanies is
# not bound to it: the verdict is about the lane, and the merge compares no
# marker to a head.
REVIEWED_OID="$OID_OVERRIDE"
[ -n "$REVIEWED_OID" ] || REVIEWED_OID=$(row_meta "$REVIEW_ROW" reviewed_oid)

# The live head of the anchor's branch: the PR's own head post-open (what the
# merge condition compares against), the remote ref pre-open. Empty is
# "unanswerable", never "no head".
live_head() {
  if [ -n "$POST_OPEN" ]; then
    gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" --json headRefOid -q .headRefOid 2>/dev/null
  elif [ -n "$BRANCH" ]; then
    git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk 'NR == 1 {print $1}'
  fi
}

if [ -z "$REVIEWED_OID" ]; then
  [ -n "$BRANCH" ] || { warn "anchor $ANCHOR names no branch and no --reviewed-oid was given; nothing names the commit this verdict read"; exit 1; }
  REVIEWED_OID=$(git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk 'NR == 1 {print $1}')
fi
# The artifact names the commit judged, and the pre-open record stamps it back
# on the review bead, so a verdict still needs one. It is not held to a length:
# nothing compares it to a head any more, and an abbreviated sha still names the
# commit a reader would look up.
REVIEWED_OID=$(printf '%s' "$REVIEWED_OID" | tr '[:upper:]' '[:lower:]')
case "$REVIEWED_OID" in
  ''|*[!0-9a-f]*) warn "no usable reviewed oid for branch '${BRANCH:-?}' (got '${REVIEWED_OID:-}'); nothing written"; exit 1 ;;
esac

# Answers on | gone | unknown for whether <oid> is still in the branch's
# history. Commits added on top keep it 'on' — the pin still names real
# content, and no marker compares to a head, so a grown branch is not this
# check's business. Only a rewrite makes it 'gone'. Unknown proceeds: a probe
# that cannot reach the remote must not discard a review round that happened.
oid_on_branch() { # <oid> <live-head>
  local oid="$1" live="${2:-}" base rc
  [ -n "$live" ] || { printf 'unknown'; return 0; }
  [ "$oid" != "$live" ] || { printf 'on'; return 0; }
  if [ -n "$PR_REPO" ]; then
    base=$(gh api --hostname "$PR_HOST" "repos/$PR_REPO/compare/$oid...$live" \
      --jq '.merge_base_commit.sha // empty' 2>/dev/null)
    if [ "$base" = "$oid" ]; then printf 'on'; return 0
    elif [ -n "$base" ]; then printf 'gone'; return 0
    fi
  fi
  [ -n "$BRANCH" ] && git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" >/dev/null 2>&1
  git merge-base --is-ancestor "$oid" "$live" >/dev/null 2>&1; rc=$?
  case "$rc" in
    0) printf 'on' ;;
    1) printf 'gone' ;;
    *) printf 'unknown' ;;   # git could not resolve one of the commits
  esac
}

LIVE_HEAD=$(live_head)
if [ "$(oid_on_branch "$REVIEWED_OID" "$LIVE_HEAD")" = "gone" ]; then
  # A dispatch pin that no longer names real content: gate-ensure/pr-facts
  # stamped it at a head the branch has since been rewritten out from under
  # (rebase, amend, force-push), so what mol-review read and tested is not
  # mergeable content. This is not "moved" — commits added on top stay 'on'
  # and are not this check's business — and it is not a failure to retry: the
  # review bead is closed superseded so gate-ensure's in-flight probe stops
  # seeing it and pours a fresh review at the live head next pass. Neither
  # verdict is recorded, no marker is touched, no round is spent.
  #
  # mol-review re-reads the dispatch pin on the next claim, so a dead one left
  # in place would re-review the same departed commit — clear only the bead's
  # own pin: a caller who overrode a live one has not staled the dispatch.
  # Best-effort — the refusal proceeds either way.
  if [ "$(row_meta "$REVIEW_ROW" reviewed_oid)" = "$REVIEWED_OID" ]; then
    gc bd update "$REVIEW_BEAD" --unset-metadata reviewed_oid >/dev/null 2>&1 || true
    # A denied or raced delete does not always fail the call, and the note and
    # warning below both state the pin as cleared. Read it back. row_meta
    # answers '' for a key that is gone and for a row it could not read, so
    # absence is proof only from a row that resolved.
    AFTER_ROW=$(bd_json show "$REVIEW_BEAD")
    if ! is_rows "$AFTER_ROW"; then
      warn "head moved to ${LIVE_HEAD:-unknown}, but $REVIEW_BEAD would not resolve on the read-back after clearing the dead dispatch pin, so whether reviewed_oid=$REVIEWED_OID is gone is unproven. Nothing was written, no round was spent, and the review bead is left OPEN rather than closed superseded on an unproven clear. If the pin survived, the next mol-review claim re-reviews $REVIEWED_OID instead of the live head. Check it by hand: gc bd show $REVIEW_BEAD --json, then gc bd update $REVIEW_BEAD --unset-metadata reviewed_oid"
      exit 2
    fi
    if [ "$(row_meta "$AFTER_ROW" reviewed_oid)" = "$REVIEWED_OID" ]; then
      warn "head moved to ${LIVE_HEAD:-unknown}, but clearing the dead dispatch pin did not read back on $REVIEW_BEAD: reviewed_oid is still $REVIEWED_OID. Nothing was written, no round was spent, and the review bead is left OPEN rather than closed superseded while the pin still stands. Clear it by hand: gc bd update $REVIEW_BEAD --unset-metadata reviewed_oid"
      exit 2
    fi
  fi
  gc bd update "$REVIEW_BEAD" --append-notes \
    "signoff refused a verdict at $REVIEWED_OID: that commit has left branch '${BRANCH:-?}', now at ${LIVE_HEAD:-unknown}. No marker written, no round spent; closing this review as superseded so gate-ensure pours a fresh one at the live head." \
    >/dev/null 2>&1 || true
  gc bd update "$REVIEW_BEAD" --set-metadata gc.outcome=superseded --status=closed >/dev/null 2>&1 || true
  SUPERSEDED_ROW=$(bd_json show "$REVIEW_BEAD")
  SUPERSEDED_ST=$(printf '%s' "$SUPERSEDED_ROW" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null)
  SUPERSEDED_OC=$(row_meta "$SUPERSEDED_ROW" gc.outcome)
  if [ "$SUPERSEDED_ST" != "closed" ] || [ "$SUPERSEDED_OC" != "superseded" ]; then
    warn "head moved to ${LIVE_HEAD:-unknown} and the pin was cleared, but closing $REVIEW_BEAD as superseded did not read back (status='$SUPERSEDED_ST' gc.outcome='$SUPERSEDED_OC'); review left open for a retry"
    exit 2
  fi
  warn "head moved: reviewed oid $REVIEWED_OID has left branch '${BRANCH:-?}', now at $LIVE_HEAD. No verdict written — review $REVIEW_BEAD closed as superseded; gate-ensure pours a fresh review at the live head."
  echo "signoff: $REVIEW_BEAD superseded — $REVIEWED_OID left branch '${BRANCH:-?}' (now at ${LIVE_HEAD:-unknown}); no marker written, no round spent"
  exit 0
fi

# The artifact body. It always names the anchor and the exact commit judged,
# so the posted comment is traceable back to the gate it satisfied.
BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/gctk-signoff.XXXXXX") || { warn "mktemp failed"; exit 1; }
trap 'rm -f "$BODY_FILE"' EXIT
if [ -n "$NOTES_FILE" ]; then
  cat "$NOTES_FILE" > "$BODY_FILE"
else
  printf '%s' "$REVIEW_ROW" | jq -r '.[0].notes // ""' > "$BODY_FILE" 2>/dev/null
fi
[ -s "$BODY_FILE" ] || printf 'Signoff verdict: %s (check %s).\n' "$VERDICT" "$CHECK_NAME" > "$BODY_FILE"
printf '\nAnchor: %s — check.%s @ %s\n' "$ANCHOR" "$CHECK_NAME" "$REVIEWED_OID" >> "$BODY_FILE"

# The commit a verdict bound to is recorded on the review bead first, and only
# then does the artifact go where its findings are read. That record is the
# only evidence a city verdict leaves: a lane state names no commit and nothing
# here ever posts an APPROVED GitHub review, so a closed review bead carrying
# anchor_bead, reviewed_oid, check_name and the signoff_verdict close_review()
# stamps below is what lane-state.sh derives a local backing's green from — and
# what doctor/check-gate-marker-provenance's marker arm resolves a green marker
# against. Where the artifact was posted says where the findings are
# read, never which commit was judged, so the record does not vary with it.
# request-changes records it too: it leaves no marker, but the round it spent
# is part of the same ledger. Because the record is written first, a store that
# will not take it costs a re-run instead of a marker nothing accounts for.
post_artifact() {
  gc bd update "$REVIEW_BEAD" --set-metadata "reviewed_oid=$REVIEWED_OID" >/dev/null 2>&1 || true
  local got; got=$(row_meta "$(bd_json show "$REVIEW_BEAD")" reviewed_oid)
  if [ "$got" != "$REVIEWED_OID" ]; then
    warn "the reviewed commit did not read back on $REVIEW_BEAD (reviewed_oid='$got', want '$REVIEWED_OID'); nothing posted and no marker stamped, review left open for a retry"
    exit 2
  fi
  if [ -n "$POST_OPEN" ]; then
    # COMMENT for both verdicts, NEVER --approve: approval is external/human,
    # and the merge is held by the recorded marker, not by a bot review.
    gh pr review "$PR_NUMBER" --repo "$PR_REPO_Q" --comment --body-file "$BODY_FILE" >/dev/null 2>&1 \
      || warn "could not post the review comment on PR#$PR_NUMBER; the recorded marker still governs"
  else
    # Pre-open, the bead's notes are the only copy of the body. pr-open.sh
    # replays them into the PR it opens, and on request-changes they are the
    # findings the rework child is pointed at. So this append is verified on
    # the same terms as the record above: the trailer line names this anchor,
    # check and commit, and nothing but this function writes it. Absent, the
    # append did not land, and exiting here leaves no marker stamped and no
    # rework filed against findings nobody can read.
    gc bd update "$REVIEW_BEAD" --append-notes "$(cat "$BODY_FILE")" >/dev/null 2>&1 || true
    local trailer landed
    trailer="Anchor: $ANCHOR — check.$CHECK_NAME @ $REVIEWED_OID"
    landed=$(row_field "$(bd_json show "$REVIEW_BEAD")" notes)
    if ! grep -qF -- "$trailer" <<< "$landed"; then
      warn "the verdict body did not read back on $REVIEW_BEAD (its notes carry no '$trailer'); no marker stamped and no rework filed, review left open for a retry"
      exit 2
    fi
  fi
}

close_review() {
  # signoff_verdict rides in the same write as the close: doctor's
  # check-gate-marker-provenance reads it to tell an approving review bead from
  # one that recorded request-changes, now that (anchor, lane) alone no longer
  # carries an oid to key on.
  gc bd update "$REVIEW_BEAD" --set-metadata gc.outcome=recorded \
    --set-metadata "signoff_verdict=$VERDICT" --status=closed >/dev/null 2>&1 || true
  local row st oc sv
  row=$(bd_json show "$REVIEW_BEAD")
  st=$(printf '%s' "$row" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null)
  oc=$(row_meta "$row" gc.outcome)
  sv=$(row_meta "$row" signoff_verdict)
  if [ "$st" != "closed" ] || [ "$oc" != "recorded" ] || [ "$sv" != "$VERDICT" ]; then
    warn "review bead $REVIEW_BEAD close did not read back (status='$st' gc.outcome='$oc' signoff_verdict='$sv')"
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
  live=$(live_head)
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

if [ "$VERDICT" = "approve" ]; then
  post_artifact
  stamp_anchor "check.$CHECK_NAME" green
  dismiss_superseded
  close_review
  # The verdict is in; reconcile rather than assert a value, so an open rework
  # child on ANOTHER lane still reads working and a wedged merge reads
  # needs-attention. The gone-pin refusal above already scoped this verdict to the
  # reviewed commit.
  [ -z "$POST_OPEN" ] || "$PR_STATUS_LABEL" reconcile --anchor "$ANCHOR" --pr "$PR_NUMBER" \
    --repo "$PR_REPO_Q" --host "$PR_HOST" >/dev/null 2>&1 || true
  # The lane found nothing this round, so its still-unruled findings from
  # earlier rounds are answered: close them. Validated findings (the validator's)
  # and any a fix unit still blocks are left alone. Best-effort — this is
  # cleanup, never a gate the verdict depends on.
  "$FINDING" close-unvalidated --anchor "$ANCHOR" --lane "$CHECK_NAME" --reason "lane green at $REVIEWED_OID" >/dev/null 2>&1 || true
  echo "signoff: check.$CHECK_NAME=green recorded on $ANCHOR at $REVIEWED_OID; review $REVIEW_BEAD closed"
  exit 0
fi

post_artifact

# This lane owes a fresh look once the rework lands, so clear the marker — the
# lane returns to unreviewed — then file ONE child.
gc bd update "$ANCHOR" --unset-metadata "check.$CHECK_NAME" >/dev/null 2>&1 || true
GOT=$(row_meta "$(bd_json show "$ANCHOR")" "check.$CHECK_NAME")
if [ -n "$GOT" ]; then
  warn "check.$CHECK_NAME still reads '$GOT' on $ANCHOR after the clear; review left open for a retry"
  exit 2
fi

# File the reviewer's objections as findings beside the fix unit, deduped by
# finding.key, so one objection cannot be filed twice across rounds and each
# survives the rebase that would destroy a commit-pinned reference. Filed before
# the fix unit so its work order can name them. Best-effort by construction (see
# file_findings): the fix unit's own blocks edge onto the anchor holds the merge,
# so a store that will not take a finding costs the finding, never the hold.
FINDING_IDS=""
if [ -n "$FINDINGS_FILE" ]; then
  FINDING_IDS=$(file_findings "$ANCHOR" "$CHECK_NAME" "$FINDINGS_FILE" | paste -sd, -)
fi
FINDING_COUNT=0
[ -n "$FINDING_IDS" ] && FINDING_COUNT=$(printf '%s' "$FINDING_IDS" | tr ',' '\n' | grep -c '[^[:space:]]')

# The child is offered off this route by exact byte equality, and GC_RIG picks
# both the store it lands in and the rig segment a rig-scoped pool carries, so
# an address built out of GC_RIG alone renders bare for a rig-less caller: the
# stamp reads back clean, no polecat is ever offered the rework, and the PR
# just stops moving. Prove the route BEFORE the child exists — a review left
# open is retried, a rework child nothing claims is found by a human.
FIX_POOL_NAME=$(row_meta "$REVIEW_ROW" fix_target_pool)
[ -n "$FIX_POOL_NAME" ] || FIX_POOL_NAME="gc-toolkit.polecat"
FIX_POOL=$("$SCRIPT_DIR/pool-route.sh" "$FIX_POOL_NAME") || {
  warn "the rework child would route to '$FIX_POOL_NAME', which no live pool claims; review left open for a retry"
  exit 2
}
FIX_TARGET=$(row_meta "$ANCHOR_ROW" merged_target)
[ -n "$FIX_TARGET" ] || FIX_TARGET=$(row_meta "$ANCHOR_ROW" target)
[ -n "$FIX_TARGET" ] || FIX_TARGET=$(row_meta "$REVIEW_ROW" review_base)
if [ -z "$FIX_TARGET" ]; then
  warn "no landing target resolves for the rework child (anchor merged_target/target, review_base all empty); review left open"
  exit 2
fi
REASON_HEAD=$(head -n 1 "$BODY_FILE" | cut -c1-200)
# The objections themselves are now the findings this child blocks; the
# rejection_reason carries the one-line summary and points the resumed worker at
# the beads, rather than being the whole record.
if [ "$FINDING_COUNT" -gt 0 ]; then
  REJECTION_REASON="signoff requested changes: address the $FINDING_COUNT finding(s) this bead blocks. $REASON_HEAD"
else
  REJECTION_REASON="signoff requested changes: $REASON_HEAD"
fi
if [ -n "$POST_OPEN" ]; then
  TITLE="Rework PR#$PR_NUMBER: address signoff findings"
else
  TITLE="Rework branch $BRANCH: address pre-open signoff findings"
fi
# One review bead owns at most one rework child. This path is fully re-runnable
# — close_review is its last write, and every exit-2 above it (work-order
# verify, an unproven pour) leaves the review OPEN with a child already filed
# and its blocks edge already hung. A re-pool then re-enters here, so a create
# keyed to the same review mints a SECOND child for one finding: the dispatched
# one lands, the other never dispatches yet still holds a merge-hold edge no
# close cancels. Adopt the open child that already answers this review instead.
# The key is exact — a genuine next round is a new review bead with a different
# source_review_bead — so subsequent reworks are untouched, and the adopt reads
# the same down/blocks walk the adopt path reads. An unreadable walk yields
# no adopted child and falls through to create.
FIX_BEAD=$(bd_json dep list "$ANCHOR" --direction=down -t blocks \
  | jq -r --arg r "$REVIEW_BEAD" '
      [ .[]? | select(((.metadata.source_review_bead // "") == $r)
                       and (((.status // "open") | ascii_downcase) != "closed")) ]
      | sort_by(.created_at // .id) | (.[0].id // empty)' 2>/dev/null)
if [ -n "$FIX_BEAD" ]; then
  # A child that already read back a pour (gc.execution_routed_to stamped) is in
  # flight: only close_review was still owed. Re-stamping or re-slinging it would
  # stomp a live worktree or double-dispatch the molecule, so close and stop.
  ADOPT_ROUTE=$(row_meta "$(bd_json show "$FIX_BEAD")" "gc.execution_routed_to")
  if [ -n "$ADOPT_ROUTE" ]; then
    echo "signoff: rework child $FIX_BEAD (source_review_bead=$REVIEW_BEAD) was already dispatched to $ADOPT_ROUTE; closing the review it left open, filing no second child"
    close_review
    # The in-flight rework child means the city holds the ball; keep it working.
    [ -z "$POST_OPEN" ] || "$PR_STATUS_LABEL" set --pr "$PR_NUMBER" --value working \
      --repo "$PR_REPO_Q" --host "$PR_HOST" >/dev/null 2>&1 || true
    echo "signoff: request-changes recorded on $ANCHOR — rework $FIX_BEAD already dispatched to $ADOPT_ROUTE"
    exit 0
  fi
  # Never dispatched: adopt it and finish the dispatch this pass owes. The work
  # order is re-stamped below, repairing a partial prior write; the round the
  # child already records is this same round, so it is preserved rather than
  # advanced, and refilled only if that prior write never landed one.
  echo "signoff: adopting existing open rework child $FIX_BEAD for review $REVIEW_BEAD (a prior attempt filed it but never dispatched); filing no second child"
  [ -n "$(row_meta "$(bd_json show "$FIX_BEAD")" rejection_reason)" ] && REJECTION_REASON=""
else
  FIX_BEAD=$(gc bd create "$TITLE" -t task --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
  if [ -z "$FIX_BEAD" ]; then
    warn "could not create the rework child; review left open for a retry"
    exit 2
  fi
fi

# The stamped fields ARE the work order: branch/target say what to resume and
# where it lands, existing_pr keeps the rework on THIS PR, source_review_bead
# names the findings it answers. task_kind and anchor_bead are the role marker:
# the child resumes the ANCHOR's own branch, so with no marker a metadata read
# cannot tell the child from the anchor, and the title prefix is the only signal
# left.
META=(
  --set-metadata "task_kind=rework"
  --set-metadata "anchor_bead=$ANCHOR"
  --set-metadata "branch=$BRANCH"
  --set-metadata "target=$FIX_TARGET"
  --set-metadata "source_review_bead=$REVIEW_BEAD"
  --set-metadata "merge_strategy=mr"
)
# Always set on a fresh child; empty only when adopting one that already records
# its round, which is kept rather than overwritten with a later round's number.
[ -n "$REJECTION_REASON" ] && META+=(--set-metadata "rejection_reason=$REJECTION_REASON")
if [ -n "$POST_OPEN" ]; then
  META+=(--set-metadata "existing_pr=$PR_URL" --set-metadata "pr_url=$PR_URL" --set-metadata "pr_number=$PR_NUMBER")
fi
gc bd update "$FIX_BEAD" "${META[@]}" >/dev/null 2>&1 || true

# The child must BLOCK the anchor. Recorded the other way round it waits on an
# anchor that closes only once the rework lands, so nothing ever claims it, and
# count_rounds, which walks the anchor's dependencies, cannot see it either.
# Skip when the edge is already there: an adopted child carries it from the
# prior attempt, and a second identical edge is one the round-count walk sees
# twice.
if ! bd_json dep list "$ANCHOR" --direction=down -t blocks \
     | jq -e --arg f "$FIX_BEAD" 'any(.[]?; .id == $f)' >/dev/null 2>&1; then
  gc bd dep "$FIX_BEAD" --blocks "$ANCHOR" >/dev/null 2>&1 || true
fi

# Point the fix unit at every finding it answers: the many-to-one relation and
# the close ordering (bd refuses to close a blocked issue, so no finding closes
# before its work does). The anchor edge above already holds the merge, so a
# missing finding edge costs the finding's later auto-close, never the hold.
if [ -n "$FINDING_IDS" ]; then
  "$FINDING" wire-fix-unit --fix-unit "$FIX_BEAD" --anchor "$ANCHOR" --findings "$FINDING_IDS" >/dev/null 2>&1 \
    || warn "could not wire fix unit $FIX_BEAD to all findings ($FINDING_IDS); the anchor edge still holds the merge"
fi

# Verify the work order — every field the resumed workflow reads — and the
# blocks edge BEFORE the pour, so a claimed rework can never run against absent
# fields.
FIX_ROW=$(bd_json show "$FIX_BEAD")
MISSING=$(printf '%s' "$FIX_ROW" | jq -r \
  --arg b "$BRANCH" --arg t "$FIX_TARGET" --arg pr "${POST_OPEN:+$PR_URL}" \
  --arg a "$ANCHOR" '
  (.[0] // {}) as $x | ($x.metadata // {}) as $m | [
    (if ($m.task_kind // "") == "rework" then empty else "task_kind" end),
    (if ($m.anchor_bead // "") == $a then empty else "anchor_bead" end),
    (if ($m.branch // "") == $b then empty else "branch" end),
    (if ($m.target // "") == $t then empty else "target" end),
    (if ($m.source_review_bead // "") != "" then empty else "source_review_bead" end),
    (if ($m.merge_strategy // "") == "mr" then empty else "merge_strategy" end),
    (if ($m.rejection_reason // "") != "" then empty else "rejection_reason" end),
    (if $pr == "" or ($m.existing_pr // "") == $pr then empty else "pr_fields" end)
  ] | join(",") | if . == "" then "ok" else . end' 2>/dev/null)
if [ "$MISSING" = "ok" ]; then
  EDGE=$(bd_json dep list "$ANCHOR" --direction=down -t blocks \
    | jq -r --arg f "$FIX_BEAD" 'if type == "array" and any(.[]; .id == $f) then "ok" else "" end' 2>/dev/null)
  [ "$EDGE" = "ok" ] || MISSING="blocks_edge"
fi
if [ "$MISSING" != "ok" ]; then
  warn "rework child $FIX_BEAD work order incomplete (${MISSING:-unreadable}); review left open — repair with: gc bd show $FIX_BEAD --json | jq '.[0].metadata'"
  exit 2
fi

# Dispatch is a sling, not a bare route stamp. mol-polecat-work gives the rework
# the same control-dispatcher driver and continuation affinity poured work and
# reviews (gate-ensure.sh) get; a bare gc.routed_to route has no driver and
# starves behind assigned molecule steps in the pool's pull queue. The pour
# retires gc.routed_to and stamps gc.execution_routed_to=<pool> on the work
# bead — that is the read-back that proves it. On success wake the pool to claim
# it. If the route does not read back the pour may still have started the
# workflow and only failed to stamp the route (a partial pour that exits
# success); a bare gc.routed_to stamp would then let the pool claim query and
# the workflow dispatcher both act on the same work — a double-dispatch. So
# never bare-stamp: exit non-zero and leave the review unclosed, so the dispatch
# is retried rather than the work double-dispatched.
WORK_FORMULA="mol-polecat-work"
gc sling ${GC_RIG:+--rig "$GC_RIG"} "$FIX_POOL" "$FIX_BEAD" --on "$WORK_FORMULA" >/dev/null 2>&1
if [ "$(row_meta "$(bd_json show "$FIX_BEAD")" "gc.execution_routed_to")" = "$FIX_POOL" ]; then
  DISPATCH="slung $WORK_FORMULA to"
  gc session wake "$FIX_POOL" >/dev/null 2>&1 || true
  gc session nudge "$FIX_POOL" "Rework $FIX_BEAD for anchor $ANCHOR" >/dev/null 2>&1 || true
else
  warn "rework child $FIX_BEAD: mol-polecat-work pour did not stamp gc.execution_routed_to=$FIX_POOL; not falling back to a bare route (double-dispatch hazard) — review left open for a retry."
  exit 2
fi
close_review
# A rework child now stands on the anchor; the city holds the ball until it lands.
[ -z "$POST_OPEN" ] || "$PR_STATUS_LABEL" set --pr "$PR_NUMBER" --value working \
  --repo "$PR_REPO_Q" --host "$PR_HOST" >/dev/null 2>&1 || true
echo "signoff: request-changes recorded on $ANCHOR — check.$CHECK_NAME cleared (lane unreviewed), rework $FIX_BEAD $DISPATCH $FIX_POOL"
exit 0
