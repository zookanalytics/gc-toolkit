#!/usr/bin/env bash
# signoff.sh — the single writer of gate verdicts (component-model I7: one
# audited writer for check.<gate> markers). Run once by the review agent after
# mol-review's review step produced a verdict:
#   signoff.sh --review-bead <id> --verdict approve|request-changes
#              [--notes-file <path>] [--reviewed-oid <oid>]
# Both verdicts first record reviewed_oid on the review bead. The city never
# posts an APPROVED GitHub review, so that record is the only evidence
# doctor/check-gate-marker-provenance can resolve a marker written here
# against, and gate-ensure.sh reads the same field to tell a commit already
# judged from one nobody has reviewed.
# approve: post the artifact (gh pr review --comment post-open; review-bead
# notes pre-open), stamp check.<name>=green@<reviewed-oid> on the anchor, and
# dismiss the city's own superseded CHANGES_REQUESTED review. request-changes:
# clear the marker and file ONE routed rework child — or, at the round cap,
# stamp check.<name>=exception@<head> and route the anchor to a human instead.
# The cap counts rework rounds since the last operator feedback, not since the
# branch was cut: pr-facts.sh records each batch of feedback on the anchor, and
# the rounds spent before it become a floor this script subtracts. An anchor
# capped before its PR was opened has no review conversation whose next comment
# could record such a batch, so the cap also has a verb:
#   signoff.sh reset <anchor> --reason <why>
# advances the floor to the rounds already spent and retires the park the cap
# wrote, in one audited write, with the ruling recorded on the anchor.
# The city never approves its own PRs: nothing here ever passes --approve.
# Every oid stamped into a marker is a full 40 lowercase hex; a shorter one is
# refused, since merge.sh can only read the marker by comparing it to a head.
# Both verdicts are refused when the reviewed commit has left the branch.
# Both are refused on an already-closed review bead: signoff closes the bead
# itself, last, so a closed one was recorded or retired before it was judged.
# Callers: mol-review's verdict-and-drain step (the reviewing polecat).
# Exit: 0 recorded · 1 refused, no verdict written · 2 a write did not read back
#       (the review bead is left open so the gate stays owed).
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: signoff.sh --review-bead <id> --verdict approve|request-changes
                  [--notes-file <path>] [--reviewed-oid <oid>]
       signoff.sh reset <anchor> --reason <why> [--batch <id>]

  --review-bead  the dispatched review bead this verdict answers (required)
  --verdict      approve (the pass; posted as a COMMENT, never an approval)
                 or request-changes (required)
  --notes-file   the verdict body; default: the review bead's notes
  --reviewed-oid the commit the review pinned; default: the review bead's own
                 reviewed_oid (stamped at dispatch), else the live head of the
                 anchor's branch (git ls-remote origin <branch>). A pin that
                 has left the branch is refused, not bound. Whichever source
                 wins is written back to the review bead as the commit this
                 verdict judged.

reset: retire a round cap under a ruling. Advances signoff_round_floor to the
  rounds already spent and retires the park the cap wrote — check.<gate>,
  blocked_reason, signoff_cap, the human route, the cap's own gc.takeaway and
  the dispatch tally — in one write. Needs no PR and no review bead, and writes to no other bead. Refused
  when the rework ledger the floor comes from does not read, or names no round.
  Refused while a live demand holds the anchor: a sitting is waiting on a
  person there, and this ruling would hand the decision back to a pool.
  --reason  why the cap is retired; recorded on the anchor (required)
  --batch   the batch id the floor is pinned to (default: reset-<UTC stamp>)

env: GC_MAX_REVIEW_ROUNDS  rework rounds before the gate records
                           exception@<head> and routes to a human (default 3).
                           Counted since the last operator feedback on the PR.
U
}

warn() { echo "signoff: $*" >&2; }

# Two verbs. The default records a verdict against a review bead; `reset`
# names its anchor positionally, answers no dispatch, and writes to nothing
# else. The verb is read before the flag loop so an anchor id is never taken
# for a stray argument.
MODE=verdict; ANCHOR=""; RESET_REASON=""; RESET_BATCH_ARG=""
if [ "${1:-}" = "reset" ]; then
  MODE=reset; shift
  case "${1:-}" in
    ''|-*) warn "reset needs the anchor bead id as its first argument"; usage; exit 1 ;;
    *)     ANCHOR="$1"; shift ;;
  esac
fi

REVIEW_BEAD=""; VERDICT=""; NOTES_FILE=""; OID_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --review-bead)  REVIEW_BEAD="${2:-}";     shift 2 || { usage; exit 1; } ;;
    --verdict)      VERDICT="${2:-}";         shift 2 || { usage; exit 1; } ;;
    --notes-file)   NOTES_FILE="${2:-}";      shift 2 || { usage; exit 1; } ;;
    --reviewed-oid) OID_OVERRIDE="${2:-}";    shift 2 || { usage; exit 1; } ;;
    --reason)       RESET_REASON="${2:-}";    shift 2 || { usage; exit 1; } ;;
    --batch)        RESET_BATCH_ARG="${2:-}"; shift 2 || { usage; exit 1; } ;;
    -h|--help)      usage; exit 0 ;;
    *) warn "unknown argument '$1'"; usage; exit 1 ;;
  esac
done
if [ "$MODE" = reset ]; then
  # The ruling is the whole audit trail for a retirement no dispatch justifies.
  [ -n "$RESET_REASON" ] || { warn "reset needs --reason: a cap retired with nothing recorded leaves the anchor unable to say who released it or why"; usage; exit 1; }
  if [ -n "$REVIEW_BEAD$VERDICT$NOTES_FILE$OID_OVERRIDE" ]; then
    warn "reset records no verdict and answers no review bead; drop the verdict flags"; usage; exit 1
  fi
else
  [ -n "$REVIEW_BEAD" ] || { usage; exit 1; }
  if [ -n "$RESET_REASON$RESET_BATCH_ARG" ]; then
    warn "--reason and --batch belong to 'signoff.sh reset', not to a verdict"; usage; exit 1
  fi
  case "$VERDICT" in
    approve|request-changes) ;;
    *) warn "--verdict must be approve or request-changes (got '$VERDICT')"; usage; exit 1 ;;
  esac
  if [ -n "$NOTES_FILE" ] && [ ! -r "$NOTES_FILE" ]; then
    warn "--notes-file '$NOTES_FILE' is not readable; nothing written"; exit 1
  fi
fi

# bd JSON with the C0 set stripped: a raw control byte in notes breaks jq.
bd_json()   { gc bd "$@" --json 2>/dev/null | scrub; }
row_meta()  { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }
row_field() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0][$k] // "") | tostring' 2>/dev/null; }
is_rows()   { printf '%s' "$1" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; }

# >>> takeaway-hold-discriminator
# Whether a person still owes an answer on this anchor. `gc.takeaway` cannot
# say: it is one field a sitting stamps when it begins and REPLACES with its
# outcome when it signs off, and nothing clears it, so its presence dates the
# last sitting instead of naming a live wait. Read as a hold, it parks an
# anchor from its first conversation onward.
#
# The wait itself is a bead. `gc-helm.sh demand` files what a person owes as
# its own bead stamped gc.demand_for=<anchor>, blocking the anchor on it, and
# the sitting closes that bead with the ruling that answers it. A live demand
# is a live hold; none, and the takeaway records a sitting that ended.
#
# Only demands count. Rework children and `--waiting-on` edges are work in
# flight, which the merge already holds on, and reading `blocks` at large would
# restore the same permanence one indirection out. The `held` lifecycle state
# is not read either: it is entered only from `unanchored`, and every anchor a
# round cap parks carries pre_open_gate or pull_request.
#
# Fails CLOSED — a ledger that will not read answers "held", because releasing
# an anchor a person is holding hands their decision back to a pool.
takeaway_is_holding() { # <anchor-id>; 0 = a person still owes an answer here
  local rows
  rows=$(gc bd list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --metadata-field "gc.demand_for=${1:-}" --limit=0 --json 2>/dev/null) || return 0
  rows=$(printf '%s' "$rows" | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 0
  printf '%s' "$rows" | jq -e --arg a "${1:-}" \
    '[ .[] | select(((.metadata["gc.demand_for"] // "") | tostring) == $a) ] | length > 0' \
    >/dev/null 2>&1
}
# <<< takeaway-hold-discriminator

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

# Every rework child ever filed against this anchor: one per round, each stamped
# source_review_bead by the signoff that filed it. The cap bounds
# non-convergence, which only an attempted rework can demonstrate, so review
# dispatches are not rounds however many read the same commit. What counts
# against the cap is this total minus the floor a reset records.
#
# The two verbs read this ledger on opposite terms, because a wrong count is
# spent in opposite directions. This reader fails rather than answer from a walk
# it could not parse: the filter yields a number only from an array of rows, and
# every other shape — an error payload, a bare string, nothing at all — leaves
# jq failing and n empty.
count_rework_children() {
  local kids n
  kids=$(bd_json dep list "$ANCHOR" --direction=down -t blocks)
  n=$(printf '%s' "$kids" | jq '[.[] | select((.metadata.source_review_bead // "") != "")] | length' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$n"
}

# An unreadable ledger reads 0 for the cap: a count guessed low only declines to
# park, and capping on a guess parks live work.
rework_children() {
  local n
  n=$(count_rework_children) || n=0
  printf '%s' "$n"
}

# --- reset: retire a round cap under a ruling -----------------------------------
# The counter otherwise moves on one condition: operator feedback, which
# pr-facts.sh records from review comments on a PR. An anchor capped before its
# PR was opened has no such conversation, so no batch can ever be recorded, and
# clearing the exception by hand only lets the next pass recompute the same
# rounds and re-cap. This verb writes the floor itself and retires the park in
# the same call, so the release survives the next pass.
if [ "$MODE" = reset ]; then
  ANCHOR_ROW=$(bd_json show "$ANCHOR")
  is_rows "$ANCHOR_ROW" || { warn "anchor $ANCHOR does not resolve; nothing written"; exit 1; }

  # A sitting still waiting on a person outranks the ruling this verb carries,
  # exactly as it outranks pr-facts.sh's reset: releasing an anchor a sitting is
  # holding hands work back to the pool the sitting took it from. A sitting that
  # already ended does not — and this verb is the recovery path for the anchor
  # it left parked, so reading its takeaway as a hold would close the last way
  # out of the park.
  if takeaway_is_holding "$ANCHOR"; then
    warn "anchor $ANCHOR is held by a live demand: a sitting is waiting on a person here, and this ruling would hand the decision back to a pool. Nothing written — close the demand with the answer, or rule through the sitting that filed it"
    exit 1
  fi

  # The floor is written FROM this count, so it is read strictly: a floor
  # guessed low is a cap the next pass re-fires, which is the deadlock this verb
  # exists to end. An unreadable walk is not zero rounds, and zero rounds is
  # nothing to release — the floor it would write is the 0 already in force.
  TOTAL=$(count_rework_children) || TOTAL=""
  if [ -z "$TOTAL" ]; then
    warn "the rework ledger under $ANCHOR did not read as a dependency listing; nothing written — the floor comes from that count, and one guessed low re-caps on the next pass. Re-run once 'gc bd dep list $ANCHOR --direction=down -t blocks --json' answers."
    exit 1
  fi
  if [ "$TOTAL" = 0 ]; then
    warn "no rework child is filed under $ANCHOR: there is no round to retire, and the floor this would write is the 0 already in force. Nothing written — a park still standing here is not one the round counter can lift."
    exit 1
  fi
  CAP="${GC_MAX_REVIEW_ROUNDS:-3}"
  case "$CAP" in ''|*[!0-9]*) CAP=3 ;; esac
  BATCH="$RESET_BATCH_ARG"
  [ -n "$BATCH" ] || BATCH="reset-$(date -u +%Y%m%dT%H%M%SZ)"

  # The floor and the batch it is pinned to are written together. A floor whose
  # batch differs from signoff_rounds_reset is re-derived at the next verdict,
  # which would move it past the rounds this ruling released and cap again.
  WANT_FLOOR="$TOTAL@$BATCH"
  WRITES=(--set-metadata "signoff_round_floor=$WANT_FLOOR" --set-metadata "signoff_rounds_reset=$BATCH")

  # Retire the cap's own park with the counter: an exception still bound to the
  # head re-settles the gate and a human route keeps the anchor queued, so a
  # reset leaving either standing would not be one. signoff_cap names the
  # exception the park belongs to and the two must still agree — an exception a
  # person stamped, or one already retired by hand, is not this cap's to clear.
  # The dispatch tally goes with it: released rounds nobody may dispatch are no
  # release.
  CAP_STAMP=$(row_meta "$ANCHOR_ROW" signoff_cap)
  PARK_GATE=""; PARK_OID=""; RETIRED=""; RETIRED_TAKEAWAY=""; TALLY_KEYS=()
  case "$CAP_STAMP" in
    ?*@?*) PARK_GATE="${CAP_STAMP%%@*}"; PARK_OID="${CAP_STAMP#*@}" ;;
  esac
  if [ -n "$PARK_GATE" ] && [ "$(row_meta "$ANCHOR_ROW" "check.$PARK_GATE")" = "exception@$PARK_OID" ]; then
    WRITES+=(--unset-metadata "check.$PARK_GATE" --unset-metadata blocked_reason \
             --unset-metadata signoff_cap --set-metadata "gc.routed_to=")
    RETIRED="check.$PARK_GATE=exception@$PARK_OID, blocked_reason, signoff_cap and the human route"
    # The cap writes the board's NEEDS sentence for this park, so the sentence
    # goes with the park. Only its own: gc.takeaway_by names the writer, and a
    # sitting's record of a decision on this anchor is not this verb's to clear.
    if [ "$(row_meta "$ANCHOR_ROW" gc.takeaway_by)" = signoff ]; then
      WRITES+=(--unset-metadata gc.takeaway --unset-metadata gc.takeaway_at \
               --unset-metadata gc.takeaway_by)
      RETIRED_TAKEAWAY=1
      RETIRED="$RETIRED, the cap's takeaway"
    fi
    while IFS= read -r K; do
      [ -n "${K:-}" ] || continue
      WRITES+=(--unset-metadata "$K"); TALLY_KEYS+=("$K"); RETIRED="$RETIRED, $K"
    done <<TALLY
$(printf '%s' "$ANCHOR_ROW" | jq -r '(.[0].metadata // {}) | keys[]?
  | select(. == "dispatch_count" or startswith("dispatch_backstop."))' 2>/dev/null)
TALLY
  fi

  NOTE="signoff: round cap retired by ruling — $RESET_REASON. The floor is set to the $TOTAL rework round(s) already filed under this anchor, pinned to batch $BATCH, so the next verdict counts from 0 of $CAP"
  if [ -n "$RETIRED" ]; then
    NOTE="$NOTE, and the park the cap wrote is retired with it ($RETIRED)."
  else
    NOTE="$NOTE. No park was retired: signoff_cap claims no standing exception here, so an exception on this anchor is a person's and stays."
  fi
  gc bd update "$ANCHOR" "${WRITES[@]}" --append-notes "$NOTE" >/dev/null 2>&1 || true

  AFTER=$(bd_json show "$ANCHOR")
  is_rows "$AFTER" || { warn "anchor $ANCHOR would not resolve on the read-back, so whether the reset landed is unproven; read it with: gc bd show $ANCHOR --json"; exit 2; }
  BAD=""
  [ "$(row_meta "$AFTER" signoff_round_floor)" = "$WANT_FLOOR" ] || BAD="$BAD signoff_round_floor"
  [ "$(row_meta "$AFTER" signoff_rounds_reset)" = "$BATCH" ]     || BAD="$BAD signoff_rounds_reset"
  if [ -n "$RETIRED" ]; then
    [ -z "$(row_meta "$AFTER" "check.$PARK_GATE")" ] || BAD="$BAD check.$PARK_GATE"
    [ -z "$(row_meta "$AFTER" signoff_cap)" ]        || BAD="$BAD signoff_cap"
    [ -z "$(row_meta "$AFTER" blocked_reason)" ]     || BAD="$BAD blocked_reason"
    [ -z "$(row_meta "$AFTER" gc.routed_to)" ]       || BAD="$BAD gc.routed_to"
    if [ -n "$RETIRED_TAKEAWAY" ]; then
      [ -z "$(row_meta "$AFTER" gc.takeaway)" ]    || BAD="$BAD gc.takeaway"
      [ -z "$(row_meta "$AFTER" gc.takeaway_at)" ] || BAD="$BAD gc.takeaway_at"
      [ -z "$(row_meta "$AFTER" gc.takeaway_by)" ] || BAD="$BAD gc.takeaway_by"
    fi
    # The tally is verified key by key: gate-ensure.sh holds dispatches at the
    # backstop while dispatch_count stands, so a tally unset that was denied or
    # lost while the rest of the write landed leaves the anchor undispatchable
    # under a release that reported success.
    for K in ${TALLY_KEYS[@]+"${TALLY_KEYS[@]}"}; do
      [ -z "$(row_meta "$AFTER" "$K")" ] || BAD="$BAD $K"
    done
  fi
  if [ -n "$BAD" ]; then
    warn "the reset did not read back on $ANCHOR (${BAD# }); the cap stands and the next signoff pass re-caps. Clear the named keys by hand, or re-run — a floor that did land is harmless to write again."
    exit 2
  fi
  echo "signoff: round cap on $ANCHOR reset to 0 of $CAP (floor $WANT_FLOOR)${RETIRED:+ — retired $RETIRED}"
  exit 0
fi

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
# Evidence binding, in order: the caller's --reviewed-oid; the reviewed_oid the
# DISPATCH pinned on the review bead (gate-ensure/pr-facts stamp the live head
# at dispatch time); only then the live head. The live-head fallback is the
# weakest binding — a push between review and signoff would stamp green at a
# commit nobody reviewed, so a dispatch-pinned oid always wins (a moved head
# then correctly fails the merge's green@<live head> condition and re-gates).
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
  [ -n "$BRANCH" ] || { warn "anchor $ANCHOR names no branch and no --reviewed-oid was given; nothing to bind the verdict to"; exit 1; }
  REVIEWED_OID=$(git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk 'NR == 1 {print $1}')
fi
# The verdict is stamped into check.<g>, whose grammar is <verb>@<40-hex oid>.
# An abbreviated sha passes a hex-only test yet equals no live head merge.sh
# could read it against, so the marker holds the anchor instead of gating it.
REVIEWED_OID=$(printf '%s' "$REVIEWED_OID" | tr '[:upper:]' '[:lower:]')
case "$REVIEWED_OID" in
  ''|*[!0-9a-f]*) warn "no usable reviewed oid for branch '${BRANCH:-?}' (got '${REVIEWED_OID:-}'); nothing written"; exit 1 ;;
esac
if [ "${#REVIEWED_OID}" -ne 40 ]; then
  warn "reviewed oid '$REVIEWED_OID' is ${#REVIEWED_OID} hex character(s); check.$CHECK_NAME requires the full 40 — pass the unabbreviated commit; nothing written"
  exit 1
fi

# Answers on | gone | unknown for whether <oid> is still in the branch's
# history. Commits added on top keep it 'on' — the reviewed diff is still
# there and green@<pin> fails the merge's live-head condition on its own. Only
# a rewrite makes it 'gone'. Unknown proceeds: a probe that cannot reach the
# remote must not discard a review round that happened.
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
  # mol-review re-reads the dispatch pin on the next claim, so a dead one left
  # in place re-reviews the same departed commit. Clear only the bead's own pin:
  # a caller who overrode a live one has not staled the dispatch. Best-effort —
  # the refusal stands either way.
  if [ "$(row_meta "$REVIEW_ROW" reviewed_oid)" = "$REVIEWED_OID" ]; then
    gc bd update "$REVIEW_BEAD" --unset-metadata reviewed_oid >/dev/null 2>&1 || true
    # A denied or raced delete does not always fail the call, and the note and
    # warning below both state the pin as cleared. Read it back. row_meta
    # answers '' for a key that is gone and for a row it could not read, so
    # absence is proof only from a row that resolved.
    AFTER_ROW=$(bd_json show "$REVIEW_BEAD")
    if ! is_rows "$AFTER_ROW"; then
      warn "head moved to ${LIVE_HEAD:-unknown}, but $REVIEW_BEAD would not resolve on the read-back after clearing the dead dispatch pin, so whether reviewed_oid=$REVIEWED_OID is gone is unproven. Nothing was written and no round was spent. If the pin survived, the next mol-review claim re-reviews $REVIEWED_OID instead of the live head. Check it by hand: gc bd show $REVIEW_BEAD --json, then gc bd update $REVIEW_BEAD --unset-metadata reviewed_oid"
      exit 2
    fi
    if [ "$(row_meta "$AFTER_ROW" reviewed_oid)" = "$REVIEWED_OID" ]; then
      warn "head moved to ${LIVE_HEAD:-unknown}, but clearing the dead dispatch pin did not read back on $REVIEW_BEAD: reviewed_oid is still $REVIEWED_OID. Nothing was written and no round was spent. The pin stands, so the next mol-review claim re-reviews $REVIEWED_OID instead of the live head. Clear it by hand: gc bd update $REVIEW_BEAD --unset-metadata reviewed_oid"
      exit 2
    fi
  fi
  gc bd update "$REVIEW_BEAD" --append-notes \
    "signoff refused a verdict at $REVIEWED_OID: that commit has left branch '${BRANCH:-?}', now at ${LIVE_HEAD:-unknown}. No marker written, no rework filed; the dispatch pin is cleared for a re-review at the live head." \
    >/dev/null 2>&1 || true
  warn "head moved: reviewed oid $REVIEWED_OID has left branch '${BRANCH:-?}', now at $LIVE_HEAD. No verdict written — re-pin at $LIVE_HEAD, review that commit, and submit the verdict it earns."
  exit 1
fi

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

# The commit a verdict bound to is recorded on the review bead first, and only
# then does the artifact go where its findings are read. That record is the
# only evidence a city verdict leaves: nothing here ever posts an APPROVED
# GitHub review, so doctor/check-gate-marker-provenance can resolve a marker
# written here only against a review bead carrying anchor_bead, reviewed_oid
# and check_name. Where the artifact was posted says where the findings are
# read, never which commit was judged, so the record does not vary with it.
# request-changes records it too: it leaves no marker, but gate-ensure.sh's
# already_answered reads this field to refuse a second review of a commit
# whose rework is still open. Because the record is written first, a store
# that will not take it costs a re-run instead of a marker nothing accounts for.
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
    gc bd update "$REVIEW_BEAD" --append-notes "$(cat "$BODY_FILE")" >/dev/null 2>&1 || true
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
  stamp_anchor "check.$CHECK_NAME" "green@$REVIEWED_OID"
  dismiss_superseded
  close_review
  echo "signoff: check.$CHECK_NAME=green@$REVIEWED_OID recorded on $ANCHOR; review $REVIEW_BEAD closed"
  exit 0
fi

TOTAL=$(rework_children)
CAP="${GC_MAX_REVIEW_ROUNDS:-3}"
case "$CAP" in ''|*[!0-9]*) CAP=3 ;; esac

# Operator feedback is not a failed round. It is input the branch has never
# been reviewed against, and the cap measures something else: the city failing
# to converge against its own reviewer. So the rounds spent before that input
# stop counting. pr-facts.sh records the batch that carried it in
# signoff_rounds_reset, keyed on GitHub author identity — every id in a batch
# was written by a login other than the city's own — so a codex verdict (posted
# under that login), a re-review and a rework hand-back (which post nothing) all
# leave the counter where it is. The floor is WRITTEN at the first verdict after
# a batch rather than re-derived each time: this verdict files a child of its
# own, and a floor recomputed next pass would swallow that one too, leaving a
# cap that never trips.
RESET_BATCH=$(row_meta "$ANCHOR_ROW" signoff_rounds_reset)
FLOOR_RAW=$(row_meta "$ANCHOR_ROW" signoff_round_floor)
case "$FLOOR_RAW" in
  *@*) FLOOR="${FLOOR_RAW%%@*}"; FLOOR_BATCH="${FLOOR_RAW#*@}" ;;
  *)   FLOOR=""; FLOOR_BATCH="" ;;
esac
case "$FLOOR" in ''|*[!0-9]*) FLOOR=0; FLOOR_BATCH="" ;; esac
if [ -n "$RESET_BATCH" ] && [ "$RESET_BATCH" != "$FLOOR_BATCH" ]; then
  stamp_anchor signoff_round_floor "$TOTAL@$RESET_BATCH" \
    "signoff: round counter reset to 0 of $CAP by operator feedback batch $RESET_BATCH (review.comment ids, recorded by pr-facts.sh when it routed them). The $TOTAL rework round(s) filed before that feedback were spent converging on a review it had not yet given, so they no longer count; the cap now measures the rounds that answer it."
  FLOOR="$TOTAL"
fi
ROUNDS=$((TOTAL - FLOOR))
[ "$ROUNDS" -ge 0 ] || ROUNDS=0
post_artifact

if [ "$ROUNDS" -ge "$CAP" ]; then
  # Terminal verdict: ONE write under check.<name> (the exception), never a
  # clear beside it — an absent marker re-arms the dispatch this cap refuses.
  stamp_anchor "check.$CHECK_NAME" "exception@$REVIEWED_OID"
  # A cap before the PR is open is a different report. The release this cap is
  # designed for is the next operator comment on the PR, and an anchor with no
  # PR has no conversation that could carry one — its rounds were spent
  # answering the city's own reviewer pre-open. Name which case this is, and
  # name the verb that retires the one nothing else can.
  if [ -n "$POST_OPEN" ]; then
    CAP_WHY="findings are in the review beads under this anchor; new operator feedback on PR#$PR_NUMBER retires this cap and its park"
  else
    CAP_WHY="these rounds were spent pre-open, on a branch with no PR, so no review comment can retire this cap; findings are in the review beads under this anchor. Retire it with: signoff.sh reset $ANCHOR --reason '<ruling>'"
  fi
  # signoff_cap names the exception this park belongs to. Operator feedback and
  # the reset verb each retire the park with the cap, and only this stamp tells
  # the cap's own gc.routed_to=human from a person's, so an anchor a human
  # parked by hand stays parked. It is written and verified with them: a park
  # nothing proves is the cap's can be lifted only by a person.
  #
  # The park is recorded twice, at two lengths. blocked_reason is the row's
  # detail and names both the case and the verb that retires it; gc.takeaway is
  # the headline the helm board renders for NEEDS, and a park that writes only
  # the first arrives on the operator's board announcing that nobody recorded
  # what is owed. They are separate strings because the detail passes the
  # 140-codepoint takeaway cap in either case, while the headline holds under it
  # at every round count the cap can reach.
  #
  # gc.takeaway_by carries the same provenance the cap stamp does, one level
  # down: pr-facts.sh retires the cap's own sentence with the park and leaves a
  # sitting's alone, and it tells them apart by that field. A takeaway whose
  # writer did not land reads as the sitting's, so the feedback meant to lift
  # the park leaves the exception and the human route standing. The whole
  # triple is verified below, not just the text a person would see.
  #
  # The timestamp is captured before the write and verified against that exact
  # value. An anchor can already carry an older gc.takeaway_at from a previous
  # park, so a presence check passes while this verdict's timestamp is the one
  # field that did not land — a headline helm dates and attributes to whatever
  # sitting the stale timestamp falls in.
  #
  # gc.takeaway_settled is cleared in the same write for the same reason from
  # the other side: an anchor whose last sitting ended settled carries that
  # disposition, and this park is a person owing an answer. Left standing it
  # would answer for this headline too, and doctor/check-wait-is-an-edge would
  # read the cap as a wait somebody already discharged. A stale value is the one
  # miss a presence check cannot see, so the read-back requires it CLEARED.
  CAP_HEADLINE="signoff did not converge after $ROUNDS rework rounds (cap $CAP); findings are in the review beads under this anchor"
  CAP_TAKEAWAY_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  gc bd update "$ANCHOR" \
    --set-metadata gc.routed_to=human \
    --set-metadata "signoff_cap=$CHECK_NAME@$REVIEWED_OID" \
    --set-metadata "blocked_reason=signoff did not converge after $ROUNDS rework rounds (cap $CAP); $CAP_WHY" \
    --set-metadata "gc.takeaway=$CAP_HEADLINE" \
    --set-metadata "gc.takeaway_at=$CAP_TAKEAWAY_AT" \
    --set-metadata gc.takeaway_by=signoff \
    --set-metadata gc.takeaway_settled= \
    >/dev/null 2>&1 || true
  CAP_ROW=$(bd_json show "$ANCHOR")
  if [ "$(row_meta "$CAP_ROW" gc.routed_to)" != "human" ] \
     || [ "$(row_meta "$CAP_ROW" signoff_cap)" != "$CHECK_NAME@$REVIEWED_OID" ] \
     || [ "$(row_meta "$CAP_ROW" gc.takeaway)" != "$CAP_HEADLINE" ] \
     || [ "$(row_meta "$CAP_ROW" gc.takeaway_by)" != "signoff" ] \
     || [ "$(row_meta "$CAP_ROW" gc.takeaway_at)" != "$CAP_TAKEAWAY_AT" ] \
     || [ -n "$(row_meta "$CAP_ROW" gc.takeaway_settled)" ]; then
    warn "the cap park did not read back on $ANCHOR (gc.routed_to='$(row_meta "$CAP_ROW" gc.routed_to)', signoff_cap='$(row_meta "$CAP_ROW" signoff_cap)', gc.takeaway='$(row_meta "$CAP_ROW" gc.takeaway)', gc.takeaway_by='$(row_meta "$CAP_ROW" gc.takeaway_by)', gc.takeaway_at='$(row_meta "$CAP_ROW" gc.takeaway_at)' want '$CAP_TAKEAWAY_AT', gc.takeaway_settled='$(row_meta "$CAP_ROW" gc.takeaway_settled)' want cleared); review left open for a retry"
    exit 2
  fi
  close_review
  CAP_WHERE="pre-open (no PR)"
  [ -z "$POST_OPEN" ] || CAP_WHERE="PR#$PR_NUMBER"
  echo "signoff: round cap on $ANCHOR ($ROUNDS/$CAP, $CAP_WHERE) — check.$CHECK_NAME=exception@$REVIEWED_OID, anchor routed to human, no rework filed"
  [ -n "$POST_OPEN" ] || echo "signoff: no PR means no review conversation can release this cap — retire it with: signoff.sh reset $ANCHOR --reason '<ruling>'"
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

# The child must BLOCK the anchor. Recorded the other way round it waits on an
# anchor that closes only once the rework lands, so nothing ever claims it, and
# count_rounds, which walks the anchor's dependencies, cannot see it either.
gc bd dep "$FIX_BEAD" --blocks "$ANCHOR" >/dev/null 2>&1 || true

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
if [ "$MISSING" = "ok" ]; then
  EDGE=$(bd_json dep list "$ANCHOR" --direction=down -t blocks \
    | jq -r --arg f "$FIX_BEAD" 'if type == "array" and any(.[]; .id == $f) then "ok" else "" end' 2>/dev/null)
  [ "$EDGE" = "ok" ] || MISSING="blocks_edge"
fi
if [ "$MISSING" != "ok" ]; then
  warn "rework child $FIX_BEAD work order incomplete (${MISSING:-unreadable}); review left open — repair with: gc bd show $FIX_BEAD --json | jq '.[0].metadata'"
  exit 2
fi
close_review
echo "signoff: request-changes recorded on $ANCHOR (round $((ROUNDS + 1))/$CAP) — check.$CHECK_NAME cleared, rework $FIX_BEAD routed to $FIX_POOL"
exit 0
