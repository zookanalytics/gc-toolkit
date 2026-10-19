#!/usr/bin/env bash
# signoff.sh — the single writer of check verdicts (component-model I7). Run
# once by the review agent after mol-review's review step produced a verdict:
#   signoff.sh --review-bead <id> --verdict approve|request-changes
#              [--notes-file <path>] [--reviewed-oid <oid>] [--needs-you <text>]
# The posted artifact opens with one line, the same for every check: the check
# and its verdict, then the one decision it needs from the operator or "Nothing
# needs you". The reviewer's notes follow it as the trail.
# A triage approve on an anchor whose bring-current round awaits triage also
# carries that round's ruling (--reopen, --round-reason, --dismiss-approval),
# which bring-current-guard.sh's `decide` records and carries out before the
# artifact is posted. The round's account sits collapsed under the opening line,
# and a ruling that lifts the approval is the decision that line names.
# Both verdicts first record reviewed_oid on the review bead. A lane state names
# no commit, but lane-state.sh derives green only from a local backing bead that
# carries a reviewed_oid, so recording it here is what lets an approve close back
# the lane.
# approve: post the artifact (gh pr review --comment post-open; review-bead
# notes pre-open), dismiss the city's own superseded CHANGES_REQUESTED review,
# and close the review bead signoff_verdict=approve, the record the lane's
# green derives from. request-changes: file ONE routed rework child through
# rework-child.sh, with the reviewer's findings beside it and the lane's
# validation pass, then close the review bead signoff_verdict=request-changes.
# Convergence is judged, not counted. The validator rules whether a further
# whole-diff review is warranted once the must-fix set closes
# (specs/tk-ztapg/review-cycle-architecture.md), so request-changes files a
# rework child on every round and this script bounds none.
# The city never approves its own PRs: nothing here ever passes --approve.
# A lane state is a state of the lane, never a claim about a commit: a verdict
# binds to no oid, and a commit landing on the branch neither stales a verdict
# nor buys a review. The reviewed oid survives as the artifact's audit trail and
# as the dispatch pin mol-review reads.
# The pin still names real content, though: commits added on top of it leave it
# reachable and change nothing here, but a rewrite that drops it from the
# branch (rebase, amend, force-push) means mol-review read and tested a commit
# nobody can merge. Both verdicts are refused on a gone pin, with no verdict
# recorded and no rework filed, and the review bead is closed
# gc.outcome=superseded instead of recorded, so gate-ensure's in-flight probe
# stops seeing it and pours a fresh review at the live head next pass.
# Both are refused on an already-closed review bead: signoff closes the bead
# itself, last, so a closed one was recorded or retired before it was judged.
# A correctness approve on a change that edits its own review guidance
# (review-checks.toml, docs/review-*.md) is refused until --needs-you names the
# edit for the person who approves the merge.
# Callers: mol-review's verdict-and-drain step (the reviewing polecat).
# Exit: 0 recorded, or refused-as-superseded with the review closed for a fresh
#       dispatch · 1 refused, no verdict written · 2 a write did not read back
#       (the review bead is left open so the check stays owed).
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
# The check-index resolver (review-checks.sh) lives beside this script.
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
# The one writer of a rework child. request-changes files its fix unit through it,
# under this review's provenance, and the writer proves the pool route, the work
# order, the blocks edge and the dispatch.
REWORK_CHILD="$HERE/rework-child.sh"
# The single writer of the workflow-owned `status:` PR label. A verdict is the
# event-precise flip: request-changes sets the PR working (a rework child now
# stands on it), and an approve reconciles to the current state. Post-open only.
PR_STATUS_LABEL="${GC_PR_STATUS_LABEL_TOOL:-$HERE/pr-status-label.sh}"
# The dispatch note carried by the validation pass a request-changes verdict
# opens, so the validator polecat that claims it names the method. Same builder
# pr-facts.sh uses for the human feedback batch's pass. Overridable for the test.
VALIDATE_BODY="${GC_VALIDATE_BODY_TOOL:-$HERE/validate-dispatch-body.sh}"
# The single writer of the city's PR posts. A post-open verdict goes through it
# so the review carries the city's mark, and the superseded-block dismissal asks
# its definition of the city's own review (gc_city_own) rather than the login.
PR_POST="$HERE/pr-post.sh"
# The bring-current round's ruling: what a conflicted round reopens, and whether
# the approval it touched is dismissed. Overridable so the hermetic test can
# stand in for it.
BRING_CURRENT="${GC_BRING_CURRENT_TOOL:-$HERE/bring-current-guard.sh}"

usage() {
  cat >&2 <<'U'
usage: signoff.sh --review-bead <id> --verdict approve|request-changes
                  [--notes-file <path>] [--findings-file <path>]
                  [--reviewed-oid <oid>] [--needs-you <text>] [--add-gates <checks>]
                  [--visual <decision> [--visual-fallback-from <modality>]]
                  [--reopen <lanes>|none --round-reason <text> [--dismiss-approval]]

  --review-bead  the dispatched review bead this verdict answers (required)
  --verdict      approve (the pass; posted as a COMMENT, never an approval)
                 or request-changes (required)
  --notes-file   the verdict body, the trail under the opening line; default:
                 the review bead's notes
  --needs-you    the one decision this review needs from the operator: what it
                 is, what it means, and where to look. The opening line names
                 it; absent, it says nothing needs them. A finding is not one,
                 because the city fixes it. Refused beside a ruling that lifts
                 the approval, on this call or recorded by this review's
                 earlier attempt, whose round reason is the decision. Required
                 on a correctness approve whose change edits review-checks.toml
                 or a docs/review-*.md, where it says what the edit changes
                 about the review that ran under it.
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
                 commit in the posted artifact and binds the verdict to no
                 head, except that a pin the branch no longer carries
                 (rewritten out from under it) is refused, not recorded.
                 Whichever source wins is written back to the review bead as
                 the commit this verdict judged.
  --add-gates    checks to union into the anchor's check_set (triage only, with
                 --verdict approve). A set union with read-back that can never
                 remove a declared check, validated against the effective check
                 index at the reviewed commit, the pack's checks with the rows
                 that commit carries; each check added is recorded on the anchor
                 as a `triage-add:` note.
  --visual       the demo check's decision: none when the change needs no
                 visual, else the modality that conveys it (repo-artifact,
                 screenshot or video). Required on every demo verdict and
                 refused on any other check's; none records with approve only.
                 Stamped on the review bead as visual=<decision> and named on
                 the posted artifact's `Visual:` line, where repo-artifact
                 reads `author-committed`: a committed visual is what an
                 author recorded, not a capture of the reviewed commit.
  --visual-fallback-from
                 the modality that fits when --visual names a cheaper one
                 delivered in its place because the fitting one could not be
                 produced: screenshot or video, costlier than --visual.
                 Stamped as visual_fallback_from and named on the `Visual:`
                 line as `fallback from <modality>`. A demo verdict without it
                 clears the stamp.
  --reopen       triage's ruling on a bring-current round that conflicted:
                 the lanes the anchor declares that run again on the merged
                 code, or none. Required on a triage approve while the anchor's
                 bring_current_record holds a conflicted round triage has not
                 ruled on. A check the anchor does not declare is added with
                 --add-gates, and a lane added on this call runs on the merged
                 code as well. On a round this review already ruled on, the
                 verdict's retry carries out the recorded ruling, with these
                 flags dropped or stating that ruling. Refused anywhere else.
  --round-reason why the round reopens what it does, one line; required with
                 --reopen. With --dismiss-approval it is the call the operator
                 is asked to make, and it opens the posted verdict and the
                 dismissal note.
  --dismiss-approval
                 the round made a call that is the operator's to make: it
                 changed what the PR does, by inferring one side's intent or
                 by choosing between two live designs. Lift the approval: no
                 approval given at or before the round counts toward the merge
                 from then on, and each approver is asked to review again.
U
}

warn() { echo "signoff: $*" >&2; }

REVIEW_BEAD=""; VERDICT=""; NOTES_FILE=""; OID_OVERRIDE=""; FINDINGS_FILE=""; ADD_GATES=""; VISUAL=""
VISUAL_FALLBACK=""; REOPEN=""; ROUND_REASON=""; DISMISS_APPROVAL=""; NEEDS_YOU=""
while [ $# -gt 0 ]; do
  case "$1" in
    --review-bead)  REVIEW_BEAD="${2:-}";     shift 2 || { usage; exit 1; } ;;
    --verdict)      VERDICT="${2:-}";         shift 2 || { usage; exit 1; } ;;
    --notes-file)   NOTES_FILE="${2:-}";      shift 2 || { usage; exit 1; } ;;
    --needs-you)    NEEDS_YOU="${2:-}";       shift 2 || { usage; exit 1; } ;;
    --findings-file) FINDINGS_FILE="${2:-}";  shift 2 || { usage; exit 1; } ;;
    --reviewed-oid) OID_OVERRIDE="${2:-}";    shift 2 || { usage; exit 1; } ;;
    --add-gates)    ADD_GATES="${2:-}";       shift 2 || { usage; exit 1; } ;;
    --visual)       VISUAL="${2:-}";          shift 2 || { usage; exit 1; } ;;
    --visual-fallback-from) VISUAL_FALLBACK="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --reopen)       REOPEN="${2:-}";          shift 2 || { usage; exit 1; } ;;
    --round-reason) ROUND_REASON="${2:-}";    shift 2 || { usage; exit 1; } ;;
    --dismiss-approval) DISMISS_APPROVAL=1;   shift ;;
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
# The decision rides the opening line, so it is one line. A "Needs you:" the
# reviewer wrote into it is the line's own label, and a decision of none or
# nothing is no decision.
NEEDS_YOU=$(printf '%s' "$NEEDS_YOU" | tr '\000-\037' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
case "$(printf '%s' "$NEEDS_YOU" | tr '[:upper:]' '[:lower:]')" in
  "needs you:"*) NEEDS_YOU="${NEEDS_YOU:10}"; NEEDS_YOU="${NEEDS_YOU# }" ;;
esac
case "$(printf '%s' "$NEEDS_YOU" | tr '[:upper:]' '[:lower:]')" in
  ''|none|none.|nothing|nothing.|n/a) NEEDS_YOU="" ;;
  *[.!?]) : ;;
  *) NEEDS_YOU="$NEEDS_YOU." ;;
esac

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
row_field() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0][$k] // "") | tostring' 2>/dev/null; }
is_rows()   { printf '%s' "$1" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; }

# The check whose method owns the checks-needed decision; no other check widens.
TRIAGE_GATE=triage
# The check whose method owns the visual decision; no other check records one.
VISUAL_GATE=demo
INDEX_PARSER="$SCRIPT_DIR/review-checks.sh"
# A check_set as one lowercase token per line. The comma split comes first and
# the whitespace strip is a per-line sed: a stream-wide `tr -d` would take the
# newlines the split just made and fuse "correctness,triage" into one name
# nothing declares.
gate_tokens() {
  printf '%s' "${1:-}" | tr ',' '\n' | tr '[:upper:]' '[:lower:]' \
    | sed 's/[[:space:]]//g; /^$/d'
}
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# Read the reviewer's structured findings — a JSON array of {locus, message} —
# and file each as a finding bead through the finding primitive, deduped by
# finding.key. Prints the finding ids, one per line. Best-effort: a store that
# will not take a finding costs that finding, never the rework dispatch the
# merge is held by, so a failure warns and the caller proceeds. The reviewer's
# prose verdict is still the fix unit's rejection_reason and the review bead's
# notes; the beads are the queryable record the validator and check readers use.
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

REVIEW_ROW=$(bd_json show "$REVIEW_BEAD")
is_rows "$REVIEW_ROW" || { warn "review bead $REVIEW_BEAD does not resolve; nothing written"; exit 1; }

# A verdict answering a closed bead records nothing: the dispatch it answers was
# already recorded, or retired unjudged.
REVIEW_STATUS=$(printf '%s' "$REVIEW_ROW" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null)
if [ "$REVIEW_STATUS" = "closed" ]; then
  warn "review bead $REVIEW_BEAD is already closed (gc.outcome='$(row_meta "$REVIEW_ROW" gc.outcome)'); refusing — a retired dispatch records no verdict. Nothing written; re-dispatch the check if it is still owed."
  exit 1
fi
CHECK_NAME=$(row_meta "$REVIEW_ROW" check_name)
[ -n "$CHECK_NAME" ] || CHECK_NAME=correctness
# CHECK_NAME is the lane token the review was dispatched under, in the case the
# anchor's check_set wrote it. CHECK is the check whose method the review ran,
# known by its name case-folded as the check index resolves a token, and the
# triage and demo rules below go by it.
CHECK=$(printf '%s' "$CHECK_NAME" | tr '[:upper:]' '[:lower:]')

# --add-gates carries triage's classification, so it is recorded only by a triage
# approve. Refuse anything else before anything is written.
if [ -n "$ADD_GATES" ]; then
  [ "$VERDICT" = "approve" ] || { warn "--add-gates carries a classification, which only an approve verdict records; nothing written"; exit 1; }
  [ "$CHECK" = "$TRIAGE_GATE" ] || { warn "only the '$TRIAGE_GATE' check may widen a check_set (this review is '$CHECK_NAME'); nothing written"; exit 1; }
fi

# --visual carries the demo check's decision: whether the change needs a visual
# and, when it does, the modality that conveys it. A demo verdict without one is
# refused rather than recorded without the decision it exists to make, and no
# other check records one. none is approve-only: a check that found no visual
# needed has nothing to block on. Refused before anything is written.
#
# --visual-fallback-from records that the visual delivered stands in for the
# modality that fits, which could not be produced here. A fallback is cheaper
# than what it stands in for, and the modalities rank by cost: repo-artifact,
# then screenshot, then video. So the flag names a modality costlier than
# --visual, and --visual none, which delivers nothing, takes none.
VISUAL=$(printf '%s' "$VISUAL" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g')
VISUAL_FALLBACK=$(printf '%s' "$VISUAL_FALLBACK" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g')
modality_cost() { case "$1" in repo-artifact) echo 1 ;; screenshot) echo 2 ;; video) echo 3 ;; *) echo 0 ;; esac; }
if [ "$CHECK" = "$VISUAL_GATE" ]; then
  case "$VISUAL" in
    none|repo-artifact|screenshot|video) ;;
    '') warn "the '$VISUAL_GATE' check records its visual decision on every verdict: pass --visual none|repo-artifact|screenshot|video. Nothing written"; exit 1 ;;
    *)  warn "--visual must be none, repo-artifact, screenshot or video (got '$VISUAL'); nothing written"; exit 1 ;;
  esac
  if [ "$VISUAL" = none ] && [ "$VERDICT" != approve ]; then
    warn "--visual none records that the change needs no visual, which leaves the '$VISUAL_GATE' check nothing to block on; it records with --verdict approve only. Nothing written"
    exit 1
  fi
  if [ -n "$VISUAL_FALLBACK" ]; then
    case "$VISUAL_FALLBACK" in
      screenshot|video) ;;
      *) warn "--visual-fallback-from must be screenshot or video, the modality that fits (got '$VISUAL_FALLBACK'); nothing written"; exit 1 ;;
    esac
    if [ "$VISUAL" = none ]; then
      warn "--visual-fallback-from names the modality a delivered visual stands in for, and --visual none delivers no visual; nothing written"
      exit 1
    fi
    if [ "$(modality_cost "$VISUAL")" -ge "$(modality_cost "$VISUAL_FALLBACK")" ]; then
      warn "a fallback is cheaper than the modality it stands in for, so '$VISUAL' cannot be a fallback from '$VISUAL_FALLBACK'; nothing written"
      exit 1
    fi
  fi
elif [ -n "$VISUAL" ] || [ -n "$VISUAL_FALLBACK" ]; then
  warn "only the '$VISUAL_GATE' check records a visual decision (this review is '$CHECK_NAME'); nothing written"
  exit 1
fi

# The anchor the check lands on: the durable anchor_bead stamp first, the
# blocks edge second. Unresolvable is a refusal — a verdict with no anchor to
# land on must not write anything.
ANCHOR=$(row_meta "$REVIEW_ROW" anchor_bead)
if [ -z "$ANCHOR" ]; then
  ANCHOR=$(bd_json dep list "$REVIEW_BEAD" --direction=up -t blocks \
    | jq -r 'if type == "array" then (.[0].id // "") else "" end' 2>/dev/null)
fi
[ -n "$ANCHOR" ] || { warn "no anchor resolves for $REVIEW_BEAD (no metadata.anchor_bead, no blocks edge); refusing — the check has nowhere to land"; exit 1; }
ANCHOR_ROW=$(bd_json show "$ANCHOR")
is_rows "$ANCHOR_ROW" || { warn "anchor $ANCHOR does not resolve; nothing written"; exit 1; }

# A bring-current round that conflicted and awaits this triage verdict's ruling.
# The guard filed it on the anchor and reopened the triage lane, so a triage
# verdict on this anchor is that ruling as well as its classification, and it is
# not recorded without one. decide records a ruling on the round before it
# reopens a lane or dismisses an approval, so a round this same review already
# ruled on may hold a ruling that was never carried out: its retry runs decide
# again, which carries out what was recorded. A round another review ruled on
# owes this verdict nothing.
ROUND_HEAD=""; ROUND_RULING=""
if [ "$CHECK" = "$TRIAGE_GATE" ]; then
  ROUND=$(printf '%s' "$ANCHOR_ROW" | jq -c --arg rv "$REVIEW_BEAD" '(.[0].metadata.bring_current_record // null)
    | if type == "string" then (fromjson? // null) else . end
    | if type == "object" and .class == "conflicted"
         and (.triage == null or ((.triage | type) == "object" and (.triage.review // "") == $rv))
      then {head: (.head // ""), ruling: .triage} else empty end' 2>/dev/null)
  ROUND_HEAD=$(printf '%s' "$ROUND" | jq -r '.head // ""' 2>/dev/null)
  ROUND_RULING=$(printf '%s' "$ROUND" | jq -c '.ruling // empty' 2>/dev/null)
fi
if [ -n "$REOPEN$ROUND_REASON$DISMISS_APPROVAL" ]; then
  [ "$CHECK" = "$TRIAGE_GATE" ] && [ "$VERDICT" = "approve" ] \
    || { warn "--reopen, --round-reason and --dismiss-approval carry triage's ruling on a bring-current round, which only a triage approve records; nothing written"; exit 1; }
  [ -n "$ROUND_HEAD" ] \
    || { warn "no bring-current round on $ANCHOR awaits triage's ruling; drop --reopen, --round-reason and --dismiss-approval. Nothing written"; exit 1; }
fi
# The lanes a --reopen names, as decide reads them: none, or the lanes sorted and
# comma-joined.
round_lanes() { if [ "$1" = "none" ]; then echo none; else gate_tokens "$1" | LC_ALL=C sort -u | paste -sd, -; fi; }
if [ -n "$ROUND_HEAD" ] && [ -n "$ROUND_RULING" ] && [ "$VERDICT" = "approve" ]; then
  # This review's ruling is already recorded, and a retry carries it out as
  # recorded. A call that states a different one is refused rather than replaced
  # unseen, since the posted account of the round renders the recorded ruling.
  RULED_LANES=$(printf '%s' "$ROUND_RULING" | jq -r '[ .reopen[]? | tostring | ascii_downcase ] | unique | if length == 0 then "none" else join(",") end' 2>/dev/null)
  RULED_DISMISS=$(printf '%s' "$ROUND_RULING" | jq -r 'if .dismiss == true then "1" else "" end' 2>/dev/null)
  if [ -n "$REOPEN$ROUND_REASON$DISMISS_APPROVAL" ] \
     && { [ "$(round_lanes "$REOPEN")" != "$RULED_LANES" ] || [ "$DISMISS_APPROVAL" != "$RULED_DISMISS" ]; }; then
    warn "$REVIEW_BEAD already ruled on the bring-current round up to ${ROUND_HEAD:0:12} on $ANCHOR (reopen $RULED_LANES$([ -n "$RULED_DISMISS" ] && echo ", dismiss the approval")), and a recorded ruling is carried out as recorded: re-run with that ruling, or with no --reopen, --round-reason or --dismiss-approval. Nothing written"
    exit 1
  fi
  REOPEN="$RULED_LANES"; DISMISS_APPROVAL="$RULED_DISMISS"
  RULED_REASON=$(printf '%s' "$ROUND_RULING" | jq -r '.reason // ""' 2>/dev/null)
  [ -z "$RULED_REASON" ] || ROUND_REASON="$RULED_REASON"
fi
# A ruling that lifts the approval, passed on this call or recorded by this
# review's earlier attempt, names its decision in the round's reason, and the
# opening line names one decision.
if [ -n "$NEEDS_YOU" ] && [ -n "$DISMISS_APPROVAL" ]; then
  warn "a ruling that lifts the approval asks the operator the call its round reason names, and the opening line names one decision; drop --needs-you. Nothing written"
  exit 1
fi
if [ -n "$ROUND_HEAD" ] && [ "$VERDICT" = "approve" ]; then
  if [ -z "$REOPEN" ] || [ -z "$(printf '%s' "$ROUND_REASON" | tr -d '[:space:]')" ]; then
    warn "the bring-current round up to ${ROUND_HEAD:0:12} on $ANCHOR awaits this triage's ruling: pass --reopen <lanes>|none and --round-reason <why>, and --dismiss-approval only when the round made a call that is the operator's to make, with --round-reason naming it (bring-current-audit.sh render --anchor $ANCHOR --as comment reads the round). Nothing written"
    exit 1
  fi
fi

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
# wins over a live head read after the fact. The verdict is about the lane and
# is not bound to it, and the merge compares no verdict to a head.
REVIEWED_OID="$OID_OVERRIDE"
[ -n "$REVIEWED_OID" ] || REVIEWED_OID=$(row_meta "$REVIEW_ROW" reviewed_oid)

# The head of the anchor's branch on origin. ls-remote matches its pattern
# against a ref's tail, so only the line for the exact ref is taken.
branch_head() {
  git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null \
    | awk -v r="refs/heads/$BRANCH" '$2 == r { print $1; exit }'
}

# The live head of the anchor's branch: the PR's own head post-open (what the
# merge condition compares against), the remote ref pre-open. Empty is
# "unanswerable", never "no head".
live_head() {
  if [ -n "$POST_OPEN" ]; then
    gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" --json headRefOid -q .headRefOid 2>/dev/null
  elif [ -n "$BRANCH" ]; then
    branch_head
  fi
}

if [ -z "$REVIEWED_OID" ]; then
  [ -n "$BRANCH" ] || { warn "anchor $ANCHOR names no branch and no --reviewed-oid was given; nothing names the commit this verdict read"; exit 1; }
  REVIEWED_OID=$(branch_head)
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
# content, and nothing compares a verdict to a head, so a grown branch is not
# this check's business. Only a rewrite makes it 'gone'. Unknown proceeds: a probe
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
  # verdict is recorded.
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
    "signoff refused a verdict at $REVIEWED_OID: that commit has left branch '${BRANCH:-?}', now at ${LIVE_HEAD:-unknown}. No verdict recorded; closing this review as superseded so gate-ensure pours a fresh one at the live head." \
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
  echo "signoff: $REVIEW_BEAD superseded — $REVIEWED_OID left branch '${BRANCH:-?}' (now at ${LIVE_HEAD:-unknown}); no verdict recorded"
  exit 0
fi

# The artifact body. Its first line is the same for every check: the check and
# its verdict, then the one decision this review needs from the operator, or
# that nothing does, so a busy reader can stop there. Under it come the round's
# account when a triage ruling rides this verdict, the reviewer's notes as the
# trail, and the lines scripts read: the demo decision, and the trailer naming
# the anchor and the exact commit judged, which traces the posted comment back
# to the check it satisfied.
BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/gctk-signoff.XXXXXX") || { warn "mktemp failed"; exit 1; }
TRAIL_FILE=$(mktemp "${TMPDIR:-/tmp}/gctk-signoff-trail.XXXXXX") || { rm -f "$BODY_FILE"; warn "mktemp failed"; exit 1; }
trap 'rm -f "$BODY_FILE" "$TRAIL_FILE"' EXIT
if [ -n "$NOTES_FILE" ]; then
  cat "$NOTES_FILE" > "$TRAIL_FILE"
else
  printf '%s' "$REVIEW_ROW" | jq -r '.[0].notes // ""' > "$TRAIL_FILE" 2>/dev/null
fi
# Set by apply_round_decision: the round's account, and what a ruling that lifts
# the approval asks of the operator.
ROUND_BODY=""; ROUND_ASK=""
# A check's name as the opening word; a name of two letters is an acronym.
check_label() { # <check-name>
  if [ "${#1}" -le 2 ]; then printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
  else printf '%s%s' "$(printf '%s' "${1:0:1}" | tr '[:lower:]' '[:upper:]')" "${1:1}"; fi
}
# The opening line's first half: the check and its verdict. A request-changes
# verdict hands this half alone to its rework child as the summary, because the
# second half speaks to the operator and the child's reader is the worker that
# fixes it.
verdict_head() { printf '%s: %s.' "$(check_label "$CHECK_NAME")" "$VERDICT"; }
compose_artifact() {
  local needs="Nothing needs you." visual_note=""
  if [ -n "$ROUND_ASK" ]; then needs="$ROUND_ASK"
  elif [ -n "$NEEDS_YOU" ]; then needs="Needs you: $NEEDS_YOU"; fi
  # The Visual line says what the visual is, not only its modality: a
  # repo-artifact is what an author committed, not a capture of the reviewed
  # commit, and a fallback names the modality that fits.
  if [ -n "$VISUAL" ]; then
    [ "$VISUAL" != repo-artifact ] || visual_note="author-committed"
    [ -z "$VISUAL_FALLBACK" ] || visual_note="${visual_note:+$visual_note; }fallback from $VISUAL_FALLBACK"
  fi
  {
    printf '%s %s\n\n' "$(verdict_head)" "$needs"
    [ -z "$ROUND_BODY" ] || printf '%s\n\n' "$ROUND_BODY"
    [ ! -s "$TRAIL_FILE" ] || printf '%s\n\n' "$(cat "$TRAIL_FILE")"
    [ -z "$VISUAL" ] || printf 'Visual: %s%s\n' "$VISUAL" "${visual_note:+ ($visual_note)}"
    printf 'Anchor: %s — check.%s @ %s\n' "$ANCHOR" "$CHECK_NAME" "$REVIEWED_OID"
  } > "$BODY_FILE"
}

# The commit a verdict bound to is recorded on the review bead first, and only
# then does the artifact go where its findings are read. That record is the
# only evidence a city verdict leaves: a lane state names no commit and nothing
# here ever posts an APPROVED GitHub review, so a closed review bead carrying
# anchor_bead, reviewed_oid, check_name and the signoff_verdict close_review()
# stamps below is what lane-state.sh derives a local backing's green from, and
# what doctor/check-gate-marker-provenance audits. Where the artifact was posted
# says where the findings are read, never which commit was judged, so the record
# does not vary with it. request-changes records it too: gate-ensure.sh's
# per-head bar reads it back off the closed review, so no second whole-diff
# review pours at a head this one judged. Because the record is written first, a
# store that will not take it costs a re-run instead of a posted verdict that
# backs nothing. A demo verdict's visual decision rides in the same write, so
# the record names what the check decided as well as the commit it decided on.
# So does its fallback, which the write clears when this verdict names none,
# because a retried verdict must not keep an earlier attempt's.
# A review whose anchor resolved through the blocks edge alone names no
# anchor_bead, and lane-state.sh finds an anchor's reviews only by that key and
# the membership edge. Such a review is joined to its anchor first and takes
# the key in the same write, so its close backs the lane it judged.
post_artifact() {
  compose_artifact
  local rec=(--set-metadata "reviewed_oid=$REVIEWED_OID") adopt=""
  if [ -n "$VISUAL" ]; then
    rec+=(--set-metadata "visual=$VISUAL")
    if [ -n "$VISUAL_FALLBACK" ]; then
      rec+=(--set-metadata "visual_fallback_from=$VISUAL_FALLBACK")
    else
      rec+=(--unset-metadata visual_fallback_from)
    fi
  fi
  if [ -z "$(row_meta "$REVIEW_ROW" anchor_bead)" ]; then
    if ! bd_anchor_link "$ANCHOR" "$REVIEW_BEAD"; then
      warn "review $REVIEW_BEAD could not be joined to anchor $ANCHOR; nothing posted, review left open for a retry"
      exit 2
    fi
    rec+=(--set-metadata "anchor_bead=$ANCHOR")
    adopt=1
  fi
  gc bd update "$REVIEW_BEAD" "${rec[@]}" >/dev/null 2>&1 || true
  local row got
  row=$(bd_json show "$REVIEW_BEAD")
  got=$(row_meta "$row" reviewed_oid)
  if [ "$got" != "$REVIEWED_OID" ]; then
    warn "the reviewed commit did not read back on $REVIEW_BEAD (reviewed_oid='$got', want '$REVIEWED_OID'); nothing posted, review left open for a retry"
    exit 2
  fi
  got=$(row_meta "$row" anchor_bead)
  if [ -n "$adopt" ] && [ "$got" != "$ANCHOR" ]; then
    warn "the anchor did not read back on $REVIEW_BEAD (anchor_bead='$got', want '$ANCHOR'); nothing posted, review left open for a retry"
    exit 2
  fi
  got=$(row_meta "$row" visual)
  if [ -n "$VISUAL" ] && [ "$got" != "$VISUAL" ]; then
    warn "the visual decision did not read back on $REVIEW_BEAD (visual='$got', want '$VISUAL'); nothing posted, review left open for a retry"
    exit 2
  fi
  got=$(row_meta "$row" visual_fallback_from)
  if [ -n "$VISUAL" ] && [ "$got" != "$VISUAL_FALLBACK" ]; then
    warn "the visual fallback did not read back on $REVIEW_BEAD (visual_fallback_from='$got', want '$VISUAL_FALLBACK'); nothing posted, review left open for a retry"
    exit 2
  fi
  if [ -n "$POST_OPEN" ]; then
    # COMMENT for both verdicts, NEVER --approve: approval is external/human,
    # and the merge is held by the lane state the recorded verdict derives, not
    # by a bot review.
    "$PR_POST" review --repo "$PR_REPO_Q" --pr "$PR_NUMBER" --body-file "$BODY_FILE" >/dev/null 2>&1 \
      || warn "could not post the review comment on PR#$PR_NUMBER; the recorded verdict still governs"
  else
    # Pre-open, the bead's notes are the only copy of the body. pr-open.sh
    # replays them into the PR it opens, and on request-changes they are the
    # findings the rework child is pointed at. So this append is verified on
    # the same terms as the record above: the trailer line names this anchor,
    # check and commit, and nothing but this function writes it. Absent, the
    # append did not land, and exiting here leaves the review open, with no
    # rework filed against findings nobody can read.
    gc bd update "$REVIEW_BEAD" --append-notes "$(cat "$BODY_FILE")" >/dev/null 2>&1 || true
    local trailer landed
    trailer="Anchor: $ANCHOR — check.$CHECK_NAME @ $REVIEWED_OID"
    landed=$(row_field "$(bd_json show "$REVIEW_BEAD")" notes)
    if ! grep -qF -- "$trailer" <<< "$landed"; then
      warn "the verdict body did not read back on $REVIEW_BEAD (its notes carry no '$trailer'); no rework filed, review left open for a retry"
      exit 2
    fi
  fi
}

close_review() {
  # signoff_verdict rides in the same write as the close: lane-state.sh reads it
  # to tell an approving review bead from one that recorded request-changes, and
  # so does doctor's check-gate-marker-provenance.
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

# Ensure this lane's validation pass on the anchor — the machine-review-batch
# opener. The reviewer raised findings; the validator rules them and, once the
# must-fix set closes, judges whether another full review is warranted (decision
# 3 of specs/tk-ztapg/review-cycle-architecture.md, "The validator" — the
# judgement that replaced the round counter). A task_kind=validation bead on the
# anchor is what gate-ensure.sh's open_validation_passes dispatches mol-validate
# onto, and what its quiescence clause (c) reads to hold a fresh whole-diff
# review off the anchor while the pass is open. pr-facts.sh opens this same shape
# for a human feedback batch; this is the machine-review-batch opener the same
# section names. It runs alongside the fix unit rather than before it: the full
# target-3 shape rules must-fix before any work goes out, but a pass opened
# beside the dispatched fix unit still closes the convergence gap the retired
# round cap left, which is this verdict's part.
#
# One live pass per (anchor, lane): check_name is the lane mol-validate selects
# findings by and backs or supersedes, so a re-pool of this verdict or a later
# round on the same still-open lane reuses the pass rather than hanging a second
# blocks edge that double-holds the anchor. Called at each request-changes exit
# after the fix child is settled, so a pass-open that will not complete leaves
# the review open to retry rather than closing it past a gap. Fail closed: a
# shape or edge that does not read back exits non-zero.
ensure_validation_pass() {
  local rows vpass vtitle vctx vbody vident vmeta vfix vblk
  # The lane probe selects a pass by the VALIDATION_SELECT keys (bd-lib.sh).
  if ! rows=$(bd_anchor_children "$ANCHOR" "$LIVE_STATUSES"); then
    warn "validation-pass probe for lane $CHECK_NAME on $ANCHOR is unreadable; review left open for a retry"
    exit 2
  fi
  vpass=$(printf '%s' "$rows" | jq -r --arg l "$CHECK_NAME" '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "validation")
          | select(((.metadata.check_name // "") | tostring) == $l) | .id ] | .[0] // empty' 2>/dev/null)
  if [ -n "$POST_OPEN" ]; then
    vtitle="Validate PR#$PR_NUMBER $CHECK_NAME review @ $REVIEWED_OID"
    vctx="a $CHECK_NAME review batch on PR#$PR_NUMBER at $REVIEWED_OID"
  else
    vtitle="Validate branch $BRANCH $CHECK_NAME review @ $REVIEWED_OID"
    vctx="a $CHECK_NAME review batch on branch $BRANCH at $REVIEWED_OID"
  fi
  if [ -n "$vpass" ]; then
    echo "signoff: reusing open validation pass $vpass for lane $CHECK_NAME on $ANCHOR"
  else
    # A pass an earlier two-write create left behind carries this title but
    # not the shape the lane probe reads, while its blocks edge holds the anchor
    # beside the pass filed below, so it is closed first. Best-effort: an
    # unreadable listing closes nothing and the pass is filed anyway.
    bd_unmake_orphans "$VALIDATION_SELECT" "$vtitle" \
      "Unmade by signoff: a $CHECK_NAME validation pass on $ANCHOR filed without the shape the lane probe selects it by, so no validator could rule it, while its blocks edge held $ANCHOR. A pass carrying it is filed in its place." >/dev/null || true
    # The pass is filed whole: the shape the validator path reads, the blocks
    # edge that holds the anchor and the membership edge onto it (--child-of)
    # ride the create. A create whose reply is lost has still landed where the
    # lane probe above finds it, so the retry reuses it rather than minting a
    # twin that would double-block the anchor. One that stays short of a
    # VALIDATION_SELECT key is closed by bd_create, which then prints no id.
    vident=$(validation_work_order "$ANCHOR" "$CHECK_NAME" "$REVIEWED_OID")
    vbody=""
    [ -x "$VALIDATE_BODY" ] && vbody=$("$VALIDATE_BODY" --note "This validation pass rules $vctx. The findings to rule are the open task_kind=finding beads on anchor $ANCHOR carrying finding.lane=$CHECK_NAME." 2>/dev/null) || vbody=""
    if [ -n "$vbody" ]; then
      vpass=$(printf '%s' "$vbody" | bd_create --select "$VALIDATION_SELECT" --child-of "$ANCHOR" "$vident" "$vtitle" -t task --deps "blocks:$ANCHOR" --body-file -)
    else
      warn "validate-dispatch note unavailable ($VALIDATE_BODY); opening a title-only validation pass"
      vpass=$(bd_create --select "$VALIDATION_SELECT" --child-of "$ANCHOR" "$vident" "$vtitle" -t task --deps "blocks:$ANCHOR")
    fi
    if [ -z "$vpass" ]; then
      warn "could not open a validation pass for lane $CHECK_NAME on $ANCHOR; review left open for a retry"
      exit 2
    fi
  fi
  # Stamp the shape the validator path reads and read it back: task_kind=validation
  # is what open_validation_passes selects, check_name is the lane, anchor_bead
  # scopes the findings, reviewed_oid pins the head. reviewed_oid is only ADDED
  # when absent, never overwritten, so a pass reused across rounds keeps the head
  # it opened at rather than a validator mid-rule being moved under it.
  vmeta=$(bd_json show "$vpass")
  is_rows "$vmeta" || { warn "validation pass $vpass did not resolve after open; review left open for a retry"; exit 2; }
  # A pass about to take anchor_bead is joined to the anchor first, so the stamp
  # never lands on a pass the anchor's closed-children read cannot reach. A pass
  # filed above carries the edge from its create.
  if [ "$(row_meta "$vmeta" anchor_bead)" != "$ANCHOR" ] && ! bd_anchor_link "$ANCHOR" "$vpass"; then
    warn "validation pass $vpass could not be joined to anchor $ANCHOR; review left open for a retry"
    exit 2
  fi
  vfix=()
  [ "$(row_meta "$vmeta" task_kind)" != "validation" ]   && vfix+=(--set-metadata task_kind=validation)
  [ "$(row_meta "$vmeta" anchor_bead)" != "$ANCHOR" ]    && vfix+=(--set-metadata "anchor_bead=$ANCHOR")
  [ "$(row_meta "$vmeta" check_name)" != "$CHECK_NAME" ] && vfix+=(--set-metadata "check_name=$CHECK_NAME")
  [ -z "$(row_meta "$vmeta" reviewed_oid)" ]             && vfix+=(--set-metadata "reviewed_oid=$REVIEWED_OID")
  if [ "${#vfix[@]}" -gt 0 ]; then
    gc bd update "$vpass" "${vfix[@]}" >/dev/null 2>&1 || true
    vmeta=$(bd_json show "$vpass")
  fi
  if [ "$(row_meta "$vmeta" task_kind)" != "validation" ] || [ "$(row_meta "$vmeta" anchor_bead)" != "$ANCHOR" ] \
     || [ "$(row_meta "$vmeta" check_name)" != "$CHECK_NAME" ] || [ -z "$(row_meta "$vmeta" reviewed_oid)" ]; then
    warn "validation pass $vpass did not record the batch shape (want task_kind=validation anchor_bead=$ANCHOR check_name=$CHECK_NAME reviewed_oid set; got task_kind='$(row_meta "$vmeta" task_kind)' anchor_bead='$(row_meta "$vmeta" anchor_bead)' check_name='$(row_meta "$vmeta" check_name)' reviewed_oid='$(row_meta "$vmeta" reviewed_oid)'); review left open for a retry"
    exit 2
  fi
  # The pass must HOLD the anchor, not merely sit beside it: merge.sh reads every
  # live blocks blocker into its in-flight hold and bd refuses to close a blocked
  # anchor, so absent the edge the pass holds nothing and gate-ensure would
  # dispatch a validator that releases a merge nothing was holding. Idempotent — a
  # reused pass keeps its one edge — and fail-closed like the shape stamp above.
  if ! vblk=$(bd_json dep list "$ANCHOR" --direction=down -t blocks) \
     || ! printf '%s' "$vblk" | jq -e 'type == "array"' >/dev/null 2>&1; then
    warn "validation-pass blocker probe on $ANCHOR is unreadable; review left open for a retry"
    exit 2
  fi
  if ! printf '%s' "$vblk" | jq -e --arg v "$vpass" 'any(.[]?; (.id // "") == $v)' >/dev/null 2>&1; then
    if ! gc bd dep "$vpass" --blocks "$ANCHOR" >/dev/null 2>&1 \
       || ! bd_json dep list "$ANCHOR" --direction=down -t blocks \
            | jq -e --arg v "$vpass" 'any(.[]?; (.id // "") == $v)' >/dev/null 2>&1; then
      warn "validation pass $vpass did not record a blocks edge on $ANCHOR; review left open for a retry"
      exit 2
    fi
  fi
  echo "signoff: validation pass $vpass open for lane $CHECK_NAME on $ANCHOR — mol-validate judges convergence"
}

# A pass at a new head retracts the city's OWN superseded CHANGES_REQUESTED,
# else the PR stays BLOCKED on a dead commit while the bead reads green.
# Guards, all fail-closed: our own review only — one pr-post.sh marked, or one
# under our handle from before the anchor's provenance cutover (gc_city_own); a
# human's block, or an unmarked review under our handle after it, is a real veto;
# a commit other than the reviewed one; the reviewed commit still the live
# head; auto-merge definitely disarmed (with it armed, a dismissal can let
# GitHub merge server-side, past the approval rule merge.sh enforces);
# signoff_dismissed stamped and read back BEFORE the irreversible dismissal,
# so no dismissal goes unrecorded.
dismiss_superseded() {
  [ -n "$POST_OPEN" ] || return 0
  local handle live raw rc stale rid paired owndef since
  handle=$(gh api --hostname "$PR_HOST" user -q .login 2>/dev/null)
  [ -n "$handle" ] || return 0
  owndef=$("$PR_POST" own-def 2>/dev/null) && [ -n "$owndef" ] || return 0
  # Passed on as found: gc_city_cutover reads a malformed stamp as no cutover.
  since=$(row_meta "$ANCHOR_ROW" pr_provenance_since)
  live=$(live_head)
  [ "$live" = "$REVIEWED_OID" ] || return 0
  raw=$(gh pr view "$PR_NUMBER" --repo "$PR_REPO_Q" --json autoMergeRequest 2>/dev/null) || return 0
  printf '%s' "$raw" | jq -e 'type == "object" and has("autoMergeRequest") and .autoMergeRequest == null' >/dev/null 2>&1 || return 0
  raw=$(gh api --hostname "$PR_HOST" --paginate "repos/$PR_REPO/pulls/$PR_NUMBER/reviews?per_page=100" --jq '.[]' 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] || return 0
  stale=$(printf '%s' "$raw" | jq -rs --arg h "$handle" --arg since "$since" --arg oid "$REVIEWED_OID" "$owndef"'
    .[] | select(gc_city_own($h; $since) and .state == "CHANGES_REQUESTED" and (.commit_id // "") != $oid) | .id' 2>/dev/null)
  for rid in $stale; do
    gc bd update "$ANCHOR" --set-metadata "signoff_dismissed=$rid@$REVIEWED_OID" >/dev/null 2>&1 || true
    paired=$(row_meta "$(bd_json show "$ANCHOR")" signoff_dismissed)
    if [ "$paired" != "$rid@$REVIEWED_OID" ]; then
      warn "signoff_dismissed did not stick on $ANCHOR; NOT dismissing review $rid"
      continue
    fi
    gh api --hostname "$PR_HOST" -X PUT "repos/$PR_REPO/pulls/$PR_NUMBER/reviews/$rid/dismissals" \
      -f message="Superseded by the re-gate at $REVIEWED_OID: the $CHECK_NAME check is green at the live head. Approval remains external." \
      -f event=DISMISS >/dev/null 2>&1 \
      || warn "could not dismiss superseded review $rid on PR#$PR_NUMBER; the next round retries"
  done
}

# A disposed anchor — pr-dispose.sh stamped gc.pr_close_disposition_kind on it when
# the PR was withdrawn or superseded — awaits only pr-facts.sh's terminal close. A
# verdict that lands in that window (a review dispatched before the disposal, ruling
# after it) is moot: the PR will not ship, so a rework child or a validation pass
# would spawn work on a dead anchor, and the pass would hang a blocks edge that
# holds the very close the disposal is waiting on. Write
# nothing to the anchor. Close the review the caller drains behind as moot — not
# recorded, so it backs no lane green (lane-state.sh), and not superseded, so
# gate-ensure pours no fresh review at the live head — then exit. pr-facts.sh
# consummates the disposition; gate-ensure.sh skips the same anchor for the same
# reason. Marker absence is trustworthy only when the re-read resolved: an
# unreadable fresh row cannot be told from an undisposed anchor, so an
# unresolvable probe leaves the review open rather than falling through.
DISPOSED_ROW=$(bd_json show "$ANCHOR")
if ! is_rows "$DISPOSED_ROW"; then
  warn "disposition re-read of anchor $ANCHOR returned no row; a failed read cannot be told from an undisposed anchor, so refusing to record the verdict or file rework on a possibly-disposed anchor. Review $REVIEW_BEAD left open for a retry."
  exit 2
fi
DISPOSED=$(row_meta "$DISPOSED_ROW" "gc.pr_close_disposition_kind")
if [ -n "$DISPOSED" ]; then
  gc bd update "$REVIEW_BEAD" --set-metadata gc.outcome=moot \
    --append-notes "signoff: $VERDICT verdict is MOOT — anchor $ANCHOR was disposed (gc.pr_close_disposition_kind=$DISPOSED) before this verdict was ruled. No verdict recorded, no rework filed, no validation pass opened; pr-facts.sh consummates the disposition." \
    --status=closed >/dev/null 2>&1 || true
  DISPOSED_ST=$(row_field "$(bd_json show "$REVIEW_BEAD")" status)
  if [ "$DISPOSED_ST" != "closed" ]; then
    warn "anchor $ANCHOR is disposed (gc.pr_close_disposition_kind=$DISPOSED) but closing review $REVIEW_BEAD as moot did not read back (status='$DISPOSED_ST'); review left open for a retry"
    exit 2
  fi
  echo "signoff: anchor $ANCHOR is disposed (gc.pr_close_disposition_kind=$DISPOSED); $VERDICT verdict is moot — no verdict recorded, no rework filed, no validation pass opened. Review $REVIEW_BEAD closed."
  exit 0
fi

# Whether the effective check index at the reviewed commit declares <check>: the
# pack's checks with the rows that commit carries laid over them, read through
# the one resolver, never the working tree's. Non-zero for a check no layer
# declares, one whose phase is outside the ordered set, and a commit the
# resolver cannot read; INDEX_WHY then carries the resolver's reason.
INDEX_WHY=""
index_has_check() { # <check>
  INDEX_WHY=""
  [ -x "$INDEX_PARSER" ] || { INDEX_WHY="the check resolver is missing ($INDEX_PARSER)"; return 1; }
  INDEX_WHY=$("$INDEX_PARSER" --check "$1" --at "$REVIEWED_OID" 2>&1 >/dev/null) && return 0
  INDEX_WHY=$(printf '%s' "$INDEX_WHY" | tr '\n' ' ' | sed 's/^review-checks: //; s/ *$//')
  return 1
}

# The review guidance a change edits, as the one resolver lists it:
# review-checks.toml and the docs/review-*.md files among the paths it touches
# from where its branch left its base to the reviewed commit. The resolver finds
# the commit as it finds any commit it reads, fetching it by id when no
# repository here holds it yet. Every reader takes that guidance at the commit
# it judges, so a branch's edit to it governed the branch's own review. Sets
# GUIDANCE_EDITS, space-separated, and returns 0 once the paths are listed;
# non-zero, with GUIDANCE_WHY, when they cannot be: no base names where the
# branch left, or the resolver could not list them and says why.
GUIDANCE_EDITS=""; GUIDANCE_WHY=""
guidance_edits() {
  local base err out rc
  base=$(row_meta "$REVIEW_ROW" review_base)
  [ -n "$base" ] || base=$(row_meta "$ANCHOR_ROW" merged_target)
  [ -n "$base" ] || base=$(row_meta "$ANCHOR_ROW" target)
  [ -n "$base" ] || { GUIDANCE_WHY="neither the review nor its anchor names the base the branch left"; return 1; }
  [ -x "$INDEX_PARSER" ] || { GUIDANCE_WHY="the check resolver is missing ($INDEX_PARSER)"; return 1; }
  err=$(mktemp "${TMPDIR:-/tmp}/gctk-signoff-edits.XXXXXX") || { GUIDANCE_WHY="no scratch file for the resolver's reason"; return 1; }
  out=$("$INDEX_PARSER" --edits --base "$base" --at "$REVIEWED_OID" 2>"$err"); rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$err"
    GUIDANCE_EDITS=$(printf '%s\n' "$out" | sed '/^$/d' | paste -sd' ' -)
    return 0
  fi
  GUIDANCE_WHY=$(tr '\n' ' ' < "$err" | sed 's/review-checks: //g; s/ *$//')
  rm -f "$err"
  [ -n "$GUIDANCE_WHY" ] || GUIDANCE_WHY="the check resolver exited $rc"
  return 1
}

# Triage's classification: union the added checks into check_set and record one
# triage-add note per check added, in ONE write with read-back. Runs BEFORE the
# artifact and the review's close, so a refused or unpersisted widening leaves
# the triage review open and the check still owed — the opposite order would
# derive triage green over a narrower set than triage decided on.
WIDEN_SUMMARY=""
apply_triage_decision() {
  [ -n "$ADD_GATES" ] || return 0
  local fresh cur canon union tok added newset got missing lines first
  fresh=$(bd_json show "$ANCHOR")
  is_rows "$fresh" || { warn "anchor $ANCHOR did not resolve for the widening read; nothing written"; exit 2; }
  cur=$(row_meta "$fresh" check_set)
  canon=$(printf '%s' "$cur" | tr -d '[:space:],' | tr '[:upper:]' '[:lower:]')
  case "$canon" in
    none|off)
      warn "anchor $ANCHOR declares the '$cur' opt-out, which is human-only; recording the verdict without widening"
      return 0 ;;
  esac
  union=$(gate_tokens "$cur"); added=""; lines=""
  for tok in $(gate_tokens "$ADD_GATES"); do
    if ! index_has_check "$tok"; then
      warn "check '$tok' is not on the effective index at $REVIEWED_OID (${INDEX_WHY:-the resolver gave no reason}); the index is closed and triage classifies over it — nothing written"; exit 1
    fi
    grep -qx -- "$tok" <<< "$union" && continue
    union="$union
$tok"
    added="${added:+$added,}$tok"
    lines="${lines}triage-add: $tok @$REVIEWED_OID
"
  done
  [ -n "$lines" ] || { WIDEN_SUMMARY=" (no check added)"; return 0; }
  newset=$(printf '%s\n' "$union" | sed '/^$/d' | tr '\n' ',' | sed 's/,$//')
  gc bd update "$ANCHOR" --set-metadata "check_set=$newset" --append-notes "$lines" >/dev/null 2>&1 || true
  fresh=$(bd_json show "$ANCHOR")
  got=$(gate_tokens "$(row_meta "$fresh" check_set)")
  missing=""
  for tok in $(printf '%s\n' "$union" | sed '/^$/d'); do
    grep -qx -- "$tok" <<< "$got" || missing="${missing:+$missing,}$tok"
  done
  if [ -n "$missing" ]; then
    warn "check_set on $ANCHOR did not read back with '$missing' (have '$(row_meta "$fresh" check_set)', want '$newset'); review left OPEN so the check stays owed"
    exit 2
  fi
  first="${lines%%$'\n'*}"
  case "$(printf '%s' "$fresh" | jq -r '.[0].notes // ""' 2>/dev/null)" in
    *"$first"*) : ;;
    *) warn "the triage-add note did not read back on $ANCHOR; a widening its add-note did not record is not auditable, so the review is left OPEN"; exit 2 ;;
  esac
  WIDEN_SUMMARY=" (check_set now $newset${added:+; added $added})"
}

# Triage's ruling on the bring-current round: recorded and carried out by the
# guard's `decide` (the lanes to run again, the dismissal), AFTER the widening so
# a lane added on this call is reopened with the rest, and BEFORE the artifact
# and the review's close, so a ruling that did not land leaves the review open
# and the round still owed. The artifact then carries the round's account under its
# opening line, and a ruling that lifts the approval gives that line its ask,
# both rendered from the anchor's record.
apply_round_decision() {
  [ -n "$ROUND_HEAD" ] || return 0
  local round_body round_ask rc args added
  round_body=$(mktemp "${TMPDIR:-/tmp}/gctk-signoff-round.XXXXXX") || { warn "mktemp failed"; exit 2; }
  round_ask=$(mktemp "${TMPDIR:-/tmp}/gctk-signoff-ask.XXXXXX") || { rm -f "$round_body"; warn "mktemp failed"; exit 2; }
  added=$(gate_tokens "$ADD_GATES" | paste -sd, -)
  args=(decide --anchor "$ANCHOR" --review-bead "$REVIEW_BEAD" --reopen "$REOPEN"
        --reason "$ROUND_REASON" --body-out "$round_body" --ask-out "$round_ask")
  [ -z "$added" ] || args+=(--add "$added")
  [ -z "$DISMISS_APPROVAL" ] || args+=(--dismiss-approval)
  "$BRING_CURRENT" "${args[@]}"; rc=$?
  case "$rc" in
    0) : ;;
    1) rm -f "$round_body" "$round_ask"; warn "the bring-current ruling was refused; nothing written, re-run this call with the ruling corrected"; exit 1 ;;
    *) rm -f "$round_body" "$round_ask"; warn "the bring-current ruling did not fully land on $ANCHOR; review left OPEN, and the same call retries it"; exit 2 ;;
  esac
  ROUND_BODY=$(cat "$round_body")
  ROUND_ASK=$(tr '\000-\037' ' ' < "$round_ask" | sed 's/  */ /g; s/^ //; s/ $//')
  rm -f "$round_body" "$round_ask"
}

# A correctness approve on a change that edits its own review guidance names the
# edit to the person who approves the merge, so it is refused, with nothing
# written, until --needs-you says what the edit changes about the review. Paths
# that cannot be listed leave the edit unchecked, which the opening line then
# says, so the approver reads the diff for one instead.
if [ "$CHECK" = correctness ] && [ "$VERDICT" = approve ] && [ -z "$NEEDS_YOU" ]; then
  if guidance_edits; then
    if [ -n "$GUIDANCE_EDITS" ]; then
      warn "this change edits its own review guidance ($GUIDANCE_EDITS), and its review ran under that edit, since every reader takes the guidance at the commit it judges. A correctness approve names the edit to the person who approves the merge: re-run with --needs-you saying what the edit changes about the review. Nothing written"
      exit 1
    fi
  else
    NEEDS_YOU="signoff could not list the paths this change touches ($GUIDANCE_WHY), so whether it edits its own review guidance (review-checks.toml, docs/review-*.md) is unchecked; read its diff for such an edit before you approve the merge."
  fi
fi

if [ "$VERDICT" = "approve" ]; then
  apply_triage_decision
  apply_round_decision
  post_artifact
  dismiss_superseded
  close_review
  # The verdict is in; reconcile rather than assert a value, so an open rework
  # child on ANOTHER lane still reads working and a wedged merge reads
  # needs-attention. The gone-pin refusal above already scoped this verdict to the
  # reviewed commit.
  [ -z "$POST_OPEN" ] || "$PR_STATUS_LABEL" reconcile --anchor "$ANCHOR" --pr "$PR_NUMBER" \
    --repo "$PR_REPO_Q" --host "$PR_HOST" >/dev/null 2>&1 || true
  # signoff records the verdict; it does not resolve findings. Closing this lane's
  # still-unvalidated findings as moot belongs to gate-ensure.sh, the single owner
  # of stage-3 resolution: it derives the green lane state and computes quiescence,
  # so the one reader that holds the re-gate is the one that releases it, and the
  # two cannot disagree. The close lands on gate-ensure's next reconcile pass — or,
  # if the anchor merges or closes before that pass, on gate-ensure's orphaned
  # sweep, which sheds a closed anchor's still-unvalidated findings (no validator
  # runs on closed work), so the deferral strands nothing.
  echo "signoff: $CHECK_NAME approve recorded on $ANCHOR at $REVIEWED_OID$WIDEN_SUMMARY; review $REVIEW_BEAD closed"
  exit 0
fi

post_artifact

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

# The fix unit is filed by rework-child.sh under this review's provenance
# (source_review_bead). What the review decides is decided here: the pool the
# rework routes to (the review's fix_target_pool, else the writer's default),
# where it lands, and the reason and title it carries.
FIX_POOL_NAME=$(row_meta "$REVIEW_ROW" fix_target_pool)
FIX_TARGET=$(row_meta "$ANCHOR_ROW" merged_target)
[ -n "$FIX_TARGET" ] || FIX_TARGET=$(row_meta "$ANCHOR_ROW" target)
[ -n "$FIX_TARGET" ] || FIX_TARGET=$(row_meta "$REVIEW_ROW" review_base)
if [ -z "$FIX_TARGET" ]; then
  warn "no landing target resolves for the rework child (anchor merged_target/target, review_base all empty); review left open"
  exit 2
fi
REASON_HEAD=$(verdict_head)
# The objections are filed as findings beside this child; the rejection_reason
# carries the one-line summary and points the resumed worker at the beads, rather
# than being the whole record.
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
REWORK_ARGS=(--anchor "$ANCHOR" --review-bead "$REVIEW_BEAD" --branch "$BRANCH"
             --target "$FIX_TARGET" --title "$TITLE" --reason "$REJECTION_REASON")
[ -z "$FIX_POOL_NAME" ] || REWORK_ARGS+=(--pool "$FIX_POOL_NAME")
[ -z "$POST_OPEN" ] || REWORK_ARGS+=(--pr-url "$PR_URL" --pr-number "$PR_NUMBER")
# close_review is this path's last write, so a filing that did not complete leaves
# the review open. The re-pool re-enters here, and the writer adopts the child
# this pass filed rather than minting a second one.
if ! FILED=$("$REWORK_CHILD" "${REWORK_ARGS[@]}"); then
  warn "the rework child for review $REVIEW_BEAD was not dispatched; review left open for a retry"
  exit 2
fi
read -r FIX_BEAD FIX_POOL FIX_STATE <<< "$FILED"

# The fix unit's edges onto the findings it answers are NOT hung here. Every
# finding is still unvalidated at this point, and a fix unit that blocked one the
# validator later declines would refuse that finding's close (bd will not close a
# blocked issue) and stall the validator's triage. The close-ordering edge onto a
# finding is hung as the validator rules that finding must-fix (finding.sh
# set-disposition), so the fix unit blocks only the findings it must answer. The
# fix unit's edge onto the anchor is what holds the merge in the meantime.
ensure_validation_pass
close_review
# A rework child now stands on the anchor; the city holds the ball until it lands.
[ -z "$POST_OPEN" ] || "$PR_STATUS_LABEL" set --pr "$PR_NUMBER" --value working \
  --repo "$PR_REPO_Q" --host "$PR_HOST" >/dev/null 2>&1 || true
if [ "$FIX_STATE" = in-flight ]; then
  echo "signoff: request-changes recorded on $ANCHOR — rework $FIX_BEAD already dispatched to $FIX_POOL"
else
  echo "signoff: request-changes recorded on $ANCHOR — rework $FIX_BEAD slung mol-polecat-work to $FIX_POOL"
fi
exit 0
