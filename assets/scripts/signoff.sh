#!/usr/bin/env bash
# signoff.sh — the single writer of gate verdicts (component-model I7: one
# audited writer for check.<gate> markers) and of the check_set widening. Run
# once by the review agent after mol-review's review step produced a verdict:
#   signoff.sh --review-bead <id> --verdict approve|request-changes|escalate
#              [--notes-file <path>] [--reviewed-oid <oid>]
#              [--add-gates <g1,g2>] [--waive-gates <g1,g2>]
#              [--justification <text>]
# approve: post the artifact (gh pr review --comment post-open; review-bead
# notes pre-open), widen check_set when triage asked, stamp
# check.<name>=green@<reviewed-oid> on the anchor, and dismiss the city's own
# superseded CHANGES_REQUESTED review. request-changes: clear the marker and
# file ONE routed rework child — or, at the round cap, stamp
# check.<name>=exception@<head> and route the anchor to a human instead.
# escalate: stamp check.<name>=exception@<head> and file ONE visit framing the
# decision, for a finding that is a choice rather than a defect.
# The city never approves its own PRs: nothing here ever passes --approve.
# Callers: mol-review's verdict-and-drain step (the reviewing polecat).
# Exit: 0 recorded · 1 refused, nothing written · 2 a write did not read back
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
usage: signoff.sh --review-bead <id> --verdict approve|request-changes|escalate
                  [--notes-file <path>] [--reviewed-oid <oid>]
                  [--add-gates <g1,g2>] [--waive-gates <g1,g2>]
                  [--justification <text>]

  --review-bead  the dispatched review bead this verdict answers (required)
  --verdict      approve (the pass; posted as a COMMENT, never an approval),
                 request-changes, or escalate — the finding is a decision a
                 human must make, not a fix (required)
  --notes-file   the verdict body; default: the review bead's notes
  --reviewed-oid the commit the review pinned; default: the review bead's own
                 reviewed_oid (stamped at dispatch), else the live head of the
                 anchor's branch (git ls-remote origin <branch>)
  --add-gates    gates to union into the anchor's check_set (triage only, with
                 --verdict approve). The write is a set union with read-back:
                 it can never remove a declared gate.
  --waive-gates  gates the charter marks waivable that this change does not
                 need (triage only, with --verdict approve). The one
                 sanctioned narrowing; refused without a readable charter.
  --justification one line recorded on the anchor for every gate added or
                 waived; required with either flag.

env: GC_MAX_REVIEW_ROUNDS  rework rounds, counted per gate, before the gate
                           records exception@<head> and routes to a human
                           (default 3)
U
}

warn() { echo "signoff: $*" >&2; }

REVIEW_BEAD=""; VERDICT=""; NOTES_FILE=""; OID_OVERRIDE=""
ADD_GATES=""; WAIVE_GATES=""; JUSTIFICATION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --review-bead)  REVIEW_BEAD="${2:-}";  shift 2 || { usage; exit 1; } ;;
    --verdict)      VERDICT="${2:-}";      shift 2 || { usage; exit 1; } ;;
    --notes-file)   NOTES_FILE="${2:-}";   shift 2 || { usage; exit 1; } ;;
    --reviewed-oid) OID_OVERRIDE="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --add-gates)    ADD_GATES="${2:-}";    shift 2 || { usage; exit 1; } ;;
    --waive-gates)  WAIVE_GATES="${2:-}";  shift 2 || { usage; exit 1; } ;;
    --justification) JUSTIFICATION="${2:-}"; shift 2 || { usage; exit 1; } ;;
    -h|--help)      usage; exit 0 ;;
    *) warn "unknown argument '$1'"; usage; exit 1 ;;
  esac
done
[ -n "$REVIEW_BEAD" ] || { usage; exit 1; }
case "$VERDICT" in
  approve|request-changes|escalate) ;;
  *) warn "--verdict must be approve, request-changes or escalate (got '$VERDICT')"; usage; exit 1 ;;
esac
if { [ -n "$ADD_GATES" ] || [ -n "$WAIVE_GATES" ]; } && [ "$VERDICT" != "approve" ]; then
  warn "--add-gates/--waive-gates carry a classification, which only an approve verdict records; nothing written"; exit 1
fi
if { [ -n "$ADD_GATES" ] || [ -n "$WAIVE_GATES" ]; } && [ -z "$JUSTIFICATION" ]; then
  warn "--justification is required with --add-gates/--waive-gates: an unjustified change to the checks-needed decision is not auditable; nothing written"; exit 1
fi
if [ -n "$NOTES_FILE" ] && [ ! -r "$NOTES_FILE" ]; then
  warn "--notes-file '$NOTES_FILE' is not readable; nothing written"; exit 1
fi

# bd JSON with the C0 set stripped: a raw control byte in notes breaks jq.
bd_json()   { gc bd "$@" --json 2>/dev/null | scrub; }
row_meta()  { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }
row_field() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0][$k] // "") | tostring' 2>/dev/null; }
is_rows()   { printf '%s' "$1" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; }

# Siblings resolve from $0 so a copied-out scripts dir (the test harness) and
# an importing rig both reach the same pair.
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ESCALATE="$SCRIPTS_DIR/escalate.sh"
CHARTER_PARSER="$SCRIPTS_DIR/review-charter.sh"
# The parser is a pack artifact, resolved above from $0. The charter is not:
# it belongs to the REPO UNDER REVIEW, so only the reviewed checkout is a rung.
# No pack fallback — GC_PACK_DIR or the scripts dir's parent would validate an
# importing rig's gates against gc-toolkit's menu, silently. A rig that ships
# no charter must read as no charter (widening unvalidated, narrowing refused),
# which is what makes the gap visible instead of borrowed.
CHARTER=""
for c in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do
  [ -n "$c" ] && [ -r "$c/docs/review-charter.md" ] && { CHARTER="$c/docs/review-charter.md"; break; }
done
# The gate whose method owns the checks-needed decision; no other gate may
# widen or waive.
TRIAGE_GATE=triage

REVIEW_ROW=$(bd_json show "$REVIEW_BEAD")
is_rows "$REVIEW_ROW" || { warn "review bead $REVIEW_BEAD does not resolve; nothing written"; exit 1; }
CHECK_NAME=$(row_meta "$REVIEW_ROW" check_name)
[ -n "$CHECK_NAME" ] || CHECK_NAME=codex
if { [ -n "$ADD_GATES" ] || [ -n "$WAIVE_GATES" ]; } && [ "$CHECK_NAME" != "$TRIAGE_GATE" ]; then
  warn "only the '$TRIAGE_GATE' gate may widen or waive a check_set (this review is '$CHECK_NAME'); nothing written"; exit 1
fi

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

# Rework rounds already spent on THIS GATE: one routed child per round, each
# stamped source_review_bead and check_name by the signoff that filed it (the
# primary count). A child with no check_name counts against codex, the
# default gate. The backup is
# dispatch_count.<gate> on the ANCHOR — that is where gate-ensure writes it.
# Counting per gate is what keeps a multi-gate check_set from spending one
# gate's rounds on another and capping an anchor nobody has reworked once.
# An unreadable ledger reads 0 — capping on a guess parks live work.
count_rounds() {
  local kids n dc
  kids=$(bd_json dep list "$ANCHOR" --direction=down -t blocks)
  n=$(printf '%s' "$kids" | jq --arg g "$CHECK_NAME" '
    [ .[]
      | select((.metadata.source_review_bead // "") != "")
      | select((((.metadata.check_name // "") | tostring)
                | if . == "" then "codex" else . end) == $g) ] | length' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  dc=$(row_meta "$ANCHOR_ROW" "dispatch_count.$CHECK_NAME")
  case "$dc" in ''|*[!0-9]*) dc=0 ;; esac
  [ "$dc" -gt "$n" ] && n="$dc"
  printf '%s' "$n"
}


# A check_set as one token per line. Splitting on the comma FIRST and deleting
# only [:blank:] is load-bearing: [:space:] would delete the newlines the split
# just made and fuse "codex,triage" into one bogus gate name.
gate_tokens() {
  printf '%s' "${1:-}" | tr ',' '\n' | tr -d '[:blank:]' \
    | tr '[:upper:]' '[:lower:]' | sed '/^$/d'
}

# The charter's menu row for one gate, on stdout.
# rc: 0 declared · 1 charter readable but gate undeclared · 2 no charter here.
charter_row() { # <gate>
  [ -n "$CHARTER" ] && [ -x "$CHARTER_PARSER" ] || return 2
  "$CHARTER_PARSER" --file "$CHARTER" --gate "$1" 2>/dev/null
}

# Triage's classification: union the added gates into check_set and record one
# justification line per gate added or waived, in ONE write with read-back.
# Runs BEFORE the artifact and the green stamp, so a refused or unpersisted
# widening leaves check.triage absent and the gate still owed — the opposite
# order would read green over a narrower set than triage decided on.
WIDEN_SUMMARY=""
apply_triage_decision() {
  [ -n "$ADD_GATES" ] || [ -n "$WAIVE_GATES" ] || return 0
  local fresh cur canon union tok row rc lines added waived newset got_tokens missing first
  fresh=$(bd_json show "$ANCHOR")
  is_rows "$fresh" || { warn "anchor $ANCHOR did not resolve for the widening read; nothing written"; exit 2; }
  cur=$(row_meta "$fresh" check_set)
  canon=$(printf '%s' "$cur" | tr -d '[:blank:],' | tr '[:upper:]' '[:lower:]')
  case "$canon" in
    none|off)
      warn "anchor $ANCHOR declares the '$cur' opt-out, which is human-only; recording the verdict without widening"
      return 0 ;;
  esac
  union=$(gate_tokens "$cur")
  lines=""; added=""; waived=""

  for tok in $(gate_tokens "$ADD_GATES"); do
    charter_row "$tok" >/dev/null; rc=$?
    if [ "$rc" -eq 1 ]; then
      warn "gate '$tok' is not on the menu declared in $CHARTER; the menu is closed and triage classifies over it — nothing written"; exit 1
    fi
    [ "$rc" -eq 2 ] && warn "no charter is readable from here; accepting '$tok' unvalidated (widening is always safe; a narrowing is not)"
    if grep -qx -- "$tok" <<< "$union"; then continue; fi
    union="$union
$tok"
    added="${added:+$added,}$tok"
    lines="${lines}triage-add: $tok @$REVIEWED_OID — $JUSTIFICATION
"
  done

  for tok in $(gate_tokens "$WAIVE_GATES"); do
    row=$(charter_row "$tok"); rc=$?
    if [ "$rc" -ne 0 ]; then
      warn "cannot waive '$tok': ${CHARTER:-no charter} declares no such waivable gate. A narrowing warrant is declared or it does not exist — nothing written"; exit 1
    fi
    if [ "$(printf '%s' "$row" | awk -F'\t' 'NR == 1 { print $4 }')" != "yes" ]; then
      warn "the charter does not mark '$tok' waivable; nothing written"; exit 1
    fi
    if grep -qx -- "$tok" <<< "$(gate_tokens "$cur")"; then
      warn "gate '$tok' is already declared in check_set; widening is monotonic, so a waiver cannot remove it — nothing written"; exit 1
    fi
    waived="${waived:+$waived,}$tok"
    lines="${lines}triage-waive: $tok @$REVIEWED_OID — $JUSTIFICATION
"
  done

  [ -n "$lines" ] || { WIDEN_SUMMARY=" (no gate added or waived)"; return 0; }
  newset=$(printf '%s\n' "$union" | sed '/^$/d' | tr '\n' ',' | sed 's/,$//')
  gc bd update "$ANCHOR" --set-metadata "check_set=$newset" --append-notes "$lines" >/dev/null 2>&1 || true

  fresh=$(bd_json show "$ANCHOR")
  got_tokens=$(gate_tokens "$(row_meta "$fresh" check_set)")
  missing=""
  for tok in $(printf '%s\n' "$union" | sed '/^$/d'); do
    grep -qx -- "$tok" <<< "$got_tokens" || missing="${missing:+$missing,}$tok"
  done
  if [ -n "$missing" ]; then
    warn "check_set on $ANCHOR did not read back with '$missing' (have '$(row_meta "$fresh" check_set)', want '$newset'); review left OPEN so the gate stays owed"
    exit 2
  fi
  first="${lines%%$'\n'*}"
  case "$(printf '%s' "$fresh" | jq -r '.[0].notes // ""' 2>/dev/null)" in
    *"$first"*) : ;;
    *) warn "the justification did not read back on $ANCHOR; an unjustified widening is not auditable, so the review is left OPEN"; exit 2 ;;
  esac
  WIDEN_SUMMARY=" (check_set now $newset${added:+; added $added}${waived:+; waived $waived})"
}

if [ "$VERDICT" = "approve" ]; then
  apply_triage_decision
  post_artifact
  stamp_anchor "check.$CHECK_NAME" "green@$REVIEWED_OID"
  dismiss_superseded
  close_review
  echo "signoff: check.$CHECK_NAME=green@$REVIEWED_OID recorded on $ANCHOR$WIDEN_SUMMARY; review $REVIEW_BEAD closed"
  exit 0
fi

# A finding that is a choice, not a fix: hold the merge on an exception and put
# the decision in front of a human. No rework child — handing a design question
# back as a defect is the loop that converges on nothing.
if [ "$VERDICT" = "escalate" ]; then
  post_artifact
  stamp_anchor "check.$CHECK_NAME" "exception@$REVIEWED_OID"
  gc bd update "$ANCHOR" \
    --set-metadata "blocked_reason=check.$CHECK_NAME escalated at $REVIEWED_OID: the finding is a decision, not a defect; the open visit on this anchor frames it" \
    >/dev/null 2>&1 || true
  if [ ! -x "$ESCALATE" ]; then
    warn "escalate.sh is not beside signoff.sh ($ESCALATE); the exception marker holds the merge but NO visit was filed — review left OPEN so a retry can file it"
    exit 2
  fi
  if ! "$ESCALATE" --subject "$ANCHOR" --key "gate-escalation.$CHECK_NAME" \
      --message "$(printf 'Gate %s escalated on %s at %s: a decision, not a defect\n\n%s\n' \
                    "$CHECK_NAME" "$ANCHOR" "$REVIEWED_OID" "$(cat "$BODY_FILE")")"; then
    warn "could not file the escalation visit for $ANCHOR; the exception marker holds the merge but no human was asked — review left OPEN so a retry can file it"
    exit 2
  fi
  close_review
  echo "signoff: check.$CHECK_NAME=exception@$REVIEWED_OID recorded on $ANCHOR and one visit filed; review $REVIEW_BEAD closed"
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
  --set-metadata "check_name=$CHECK_NAME"
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
    (if ($m.check_name // "") != "" then empty else "check_name" end),
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
