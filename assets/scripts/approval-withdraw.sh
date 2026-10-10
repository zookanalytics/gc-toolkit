#!/usr/bin/env bash
# approval-withdraw — dismisses the approvals on an anchor's pull request when
# the validator rules that a fresh whole-diff review is warranted.
#
# An approval stands across later pushes until someone dismisses it
# (review-verdict.sh), so a small fix after an approval lands on it. A change
# big enough to need another whole-diff review is different: the code the
# approval was given to is not the code that will land. The validator judges
# which kind of change a batch calls for (formulas/mol-validate.toml,
# rule-convergence), and it runs this on every ruling that a fresh whole-diff
# review is warranted. Without the dismissal the old approval would merge the
# reworked PR. It would also keep the fresh review the ruling ordered from being
# dispatched, because lane-state.sh reads an APPROVED GitHub review as the green
# of a lane with no backing of its own.
#
# WHAT IT DISMISSES. Every approval on the PR that has not been dismissed, from
# every account other than the city's: standing_approvals in review-verdict.sh,
# the definition merge.sh lands on. That is not only each account's latest
# approval. A dismissed review drops out of the approval rule, so an older
# approval left standing would count again, and so would an approval behind its
# author's later CHANGES_REQUESTED once that request is dismissed. A
# CHANGES_REQUESTED review is never dismissed here, and neither is the city's own
# review.
#
# RECORD FIRST. A dismissal cannot be undone, so before the first one this
# appends the judgment to the anchor's notes and stamps approval_dismissed (the
# review ids) on the validation pass, and reads the stamp back. The stamp fixes
# what this pass withdraws: a retry dismisses only the recorded reviews that
# still read APPROVED. It finishes an interrupted withdrawal, and it never
# reaches an approval the operator gave after reading this pass's dismissal.
# When no approval stands, nothing is written, so a retry looks again.
#
# UNROUTED FEEDBACK WAITS. GitHub keeps the inline comments of a dismissed
# review, and pr-facts.sh reads a dismissal as retiring the comments under it,
# so they stop counting as feedback. An approval can carry inline comments the
# operator means as feedback. While one of them sits above both of the anchor's
# routing marks (pr_comment_watermark, pr_comment_answered), the feedback loop
# has not read it yet, and dismissing its review now would drop it unread. This
# then dismisses nothing and exits 1, and the retry after the next reconcile
# pass finds it routed.
#
# NO RE-REQUEST. The change the ruling calls for has not been pushed yet, so a
# review request now would ask for a look at code that is about to change. The
# PR reads review-required on GitHub and on the board, and the board asks for
# the review once the rework settles (gctk prstatus: needs-review when nothing
# is in flight and no approval stands).
#
# Usage:
#   approval-withdraw.sh --pass <id> --reason <text>
# <id> is the validation pass whose ruling this carries out; its anchor_bead is
# the anchor, whose pr_url names the PR. <text> opens the dismissal message the
# approver reads on GitHub: what the change will be, and why it needs another
# look.
# Exit: 0 nothing stood to dismiss, or every approval this pass recorded reads
# dismissed · 1 a read or a write failed, or an approval carries feedback not yet
# routed, and the caller retries · 2 usage
set -u

PROG="approval-withdraw"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 2; }
# The approval rule merge.sh lands on: standing_approvals($self) is every
# approval not yet dismissed from an account other than the city's.
# shellcheck source=review-verdict.sh
. "$SCRIPTS_DIR/review-verdict.sh" || { echo "$PROG: cannot source review-verdict.sh beside this script" >&2; exit 2; }

usage() {
  echo "usage: $PROG --pass <validation-pass-id> --reason <text>" >&2
  exit 2
}

pass=""; reason=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pass)   [ $# -ge 2 ] || usage; pass="$2"; shift 2 ;;
    --reason) [ $# -ge 2 ] || usage; reason="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$pass" ] && [ -n "$reason" ] || usage
case "$reason" in *[.!?]) : ;; *) reason="$reason." ;; esac

prow=$(bd_json show "$pass" | jq -c '.[0] | select(type == "object")' 2>/dev/null)
[ -n "$prow" ] || { echo "$PROG: validation pass $pass could not be read; nothing is dismissed and the caller retries" >&2; exit 1; }
anchor=$(printf '%s' "$prow" | jq -r '(.metadata.anchor_bead // "") | tostring')
recorded=$(printf '%s' "$prow" | jq -r '(.metadata.approval_dismissed // "") | tostring')
[ -n "$anchor" ] || { echo "$PROG: validation pass $pass names no anchor_bead, so there is no PR to read" >&2; exit 2; }
case "$recorded" in
  '') : ;;
  *[!0-9,]*|,*|*,|*,,*)
    echo "$PROG: approval_dismissed on $pass reads '$recorded', which is not a list of review ids; nothing is dismissed" >&2
    exit 1 ;;
esac

arow=$(bd_json show "$anchor" | jq -c '.[0] | select(type == "object")' 2>/dev/null)
[ -n "$arow" ] || { echo "$PROG: anchor $anchor could not be read; nothing is dismissed and the caller retries" >&2; exit 1; }
num=$(printf '%s' "$arow" | jq -r '(.metadata.pr_number // "") | tostring')
url=$(printf '%s' "$arow" | jq -r '(.metadata.pr_url // .metadata.existing_pr // "") | tostring')
case "$num" in ''|*[!0-9]*) num="" ;; esac
if [ -z "$num" ]; then
  echo "$PROG: $anchor has no pull request, so no approval stands to dismiss"
  exit 0
fi
host=$(printf '%s' "$url" | sed -n 's#^https://\([^/]*\)/[^/]*/[^/]*/pull/[0-9][0-9]*.*#\1#p')
repo=$(printf '%s' "$url" | sed -n 's#^https://[^/]*/\([^/]*/[^/]*\)/pull/[0-9][0-9]*.*#\1#p')
if [ -z "$host" ] || [ -z "$repo" ] || [ "$(printf '%s' "$url" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p')" != "$num" ]; then
  echo "$PROG: $anchor names PR#$num but its pr_url '$url' does not; nothing is dismissed and the caller retries" >&2
  exit 1
fi

if ! reviews=$(gh api --hostname "$host" --paginate "repos/$repo/pulls/$num/reviews?per_page=100" --jq '.[]' 2>/dev/null); then
  echo "$PROG: PR#$num's reviews could not be read; nothing is dismissed and the caller retries" >&2
  exit 1
fi

if [ -n "$recorded" ]; then
  # A retry of this pass: finish the recorded set and nothing else.
  targets=$(printf '%s' "$reviews" | scrub | jq -sc --arg ids "$recorded" '
    ($ids | split(",")) as $want
    | [ .[] | select(.state == "APPROVED") | select((.id | tostring) as $i | any($want[]; . == $i))
        | {id: .id, login: (.user.login // "")} ]' 2>/dev/null)
  [ -n "$targets" ] || { echo "$PROG: PR#$num's reviews did not parse; nothing is dismissed and the caller retries" >&2; exit 1; }
  if [ "$targets" = "[]" ]; then
    echo "$PROG: every approval $pass withdrew on PR#$num (review $recorded) reads dismissed"
    exit 0
  fi
else
  self=$(gh api --hostname "$host" user --jq '.login' 2>/dev/null)
  if [ -z "$self" ]; then
    echo "$PROG: the acting login is unresolved, so an outside approval cannot be told from the city's own; nothing is dismissed and the caller retries" >&2
    exit 1
  fi
  targets=$(printf '%s' "$reviews" | scrub | jq -sc --arg self "$self" "$REVIEW_VERDICT_DEF"'
    [ standing_approvals($self)[] | {id: (.id // 0), login: (.user.login // "")} | select(.id != 0 and .login != "") ]' 2>/dev/null)
  [ -n "$targets" ] || { echo "$PROG: PR#$num's reviews did not parse; nothing is dismissed and the caller retries" >&2; exit 1; }
  if [ "$targets" = "[]" ]; then
    echo "$PROG: no approval stands on PR#$num, so the fresh review needs nothing dismissed"
    exit 0
  fi
fi

cwm=$(printf '%s' "$arow" | jq -r '(.metadata.pr_comment_watermark // "") | tostring')
cam=$(printf '%s' "$arow" | jq -r '(.metadata.pr_comment_answered // "") | tostring')
case "$cwm" in ''|*[!0-9]*) cwm=0 ;; esac
case "$cam" in ''|*[!0-9]*) cam=0 ;; esac
[ "$cam" -ge "$cwm" ] || cam="$cwm"
if ! comments=$(gh api --hostname "$host" --paginate "repos/$repo/pulls/$num/comments?per_page=100" --jq '.[]' 2>/dev/null); then
  echo "$PROG: PR#$num's inline comments could not be read; nothing is dismissed and the caller retries" >&2
  exit 1
fi
unread=$(printf '%s' "$comments" | scrub | jq -sr --argjson mark "$cam" --argjson t "$targets" '
  ([ $t[].id | tostring ]) as $rids
  | [ .[] | select(((.pull_request_review_id // "") | tostring) as $p | any($rids[]; . == $p))
          | select((.id // 0) > $mark) | (.id | tostring) ] | join(",")' 2>/dev/null) \
  || { echo "$PROG: PR#$num's inline comments did not parse; nothing is dismissed and the caller retries" >&2; exit 1; }
if [ -n "$unread" ]; then
  echo "$PROG: PR#$num: an approval to dismiss carries inline comments the feedback loop has not routed (comment $unread). A dismissal now would retire them unread, so nothing is dismissed and the caller retries after pr-facts.sh routes them" >&2
  exit 1
fi

ids=$(printf '%s' "$targets" | jq -r '[ .[].id | tostring ] | join(",")')
logins=$(printf '%s' "$targets" | jq -r '[ .[].login ] | unique | if length > 1 then (.[:-1] | join(", ")) + " and " + .[-1] else .[0] end')
if [ "$(printf '%s' "$targets" | jq 'length')" -gt 1 ]; then
  noun="approvals"; rnoun="reviews"; verb="are"
else
  noun="approval"; rnoun="review"; verb="is"
fi

if [ -z "$recorded" ]; then
  if ! gc bd update "$anchor" --append-notes "Validation pass $pass ruled that a fresh whole-diff review is warranted, so the $noun from $logins on PR#$num ($rnoun $ids) $verb dismissed: $reason" >/dev/null 2>&1; then
    echo "$PROG: the dismissal could not be noted on $anchor; nothing is dismissed and the caller retries" >&2
    exit 1
  fi
  gc bd update "$pass" --set-metadata "approval_dismissed=$ids" >/dev/null 2>&1
  got=$(bd_json show "$pass" | jq -r '(.[0].metadata.approval_dismissed // "") | tostring' 2>/dev/null)
  if [ "$got" != "$ids" ]; then
    echo "$PROG: approval_dismissed did not read back on $pass; nothing is dismissed and the caller retries" >&2
    exit 1
  fi
fi

msg="$reason The validator ruled that this change needs a fresh whole-diff review, so this approval does not cover the code that will land. Please review the PR again once that change is pushed."
dismissed=""; failed=""
while IFS=$'\t' read -r rid login; do
  [ -n "$rid" ] || continue
  if gh api --hostname "$host" -X PUT "repos/$repo/pulls/$num/reviews/$rid/dismissals" \
       -f message="$msg" </dev/null >/dev/null 2>&1; then
    dismissed="$dismissed${dismissed:+, }$login (review $rid)"
  else
    failed="$failed${failed:+, }$login (review $rid)"
  fi
done <<TARGETS
$(printf '%s' "$targets" | jq -r '.[] | "\(.id)\t\(.login)"')
TARGETS
if [ -n "$failed" ]; then
  echo "$PROG: PR#$num: dismissed ${dismissed:-none}; could not dismiss $failed. The set is recorded on $pass, so a retry finishes it" >&2
  exit 1
fi
echo "$PROG: PR#$num: dismissed the $noun from $logins ($rnoun $ids), recorded on $pass and in $anchor's notes"
exit 0
