#!/usr/bin/env bash
# review-sweep — arm 6 of the merge cadence; caller: refinery-reconcile.sh.
# Closes a dispatched review that has no reviewable surface left: its anchor is
# closed AND its review_branch is absent from origin. Both conditions are
# required. An anchor still gating means the review is owed, and a branch that
# is merely unfetched is not a deleted one.
# No verdict is written. approve and request-changes each bind a marker to a
# commit and there is no commit; request-changes would also file a rework child
# against work that already landed. The verb is a sweep rather than a third
# signoff.sh verdict because the residue is filed by two dispatchers
# (gate-ensure.sh and pr-facts.sh) and neither of them is the reviewer.
# Branch existence comes from ONE `git ls-remote --heads origin` per pass. A
# ref missing from a listing that was read is absent; a listing that could not
# be read sweeps nothing, because every branch would read as deleted.
# Reads anchors, writes only review beads: gc.outcome=moot, the reason appended
# to notes, status closed, all read back. A claimed review is swept too — with
# no branch and a closed anchor its holder has no verdict to give either.
# A review carrying no review_branch or no anchor_bead is left alone: neither
# condition can be tested, and an untested condition is not a satisfied one.
# Exits: 0 pass completed · 1 an enumeration could not be read (nothing swept).
set -u

PROG="review-sweep"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

# A review is dispatched into any of these; closed ones need no sweeping.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# Guarded reads: non-zero means "could not tell", never "nothing there".
bd_list() {
  local raw rc
  raw=$(gc bd list "$@" --limit=0 --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
# </dev/null on every call inside the candidate loop: that loop is fed by a
# heredoc, and a child inheriting its stdin would consume the rows behind it.
bd_show() {
  local raw
  raw=$(gc bd show "$1" --json </dev/null 2>/dev/null | scrub)
  printf '%s' "$raw" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
row_field() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0][$k] // "") | tostring' 2>/dev/null; }
row_meta()  { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }

# --- origin's live branch names, read once ----------------------------------
REFS=$(git ls-remote --heads origin 2>/dev/null) || REFS=""
BRANCHES=$(printf '%s\n' "$REFS" \
  | sed -n 's#^[^[:space:]]\{1,\}[[:space:]]\{1,\}refs/heads/##p')
if [ -z "$BRANCHES" ]; then
  echo "$PROG: origin's branch list is unreadable; sweeping nothing rather than reading every branch as deleted" >&2
  exit 1
fi
NL='
'
on_origin() { # <branch> — exact membership; a ref name cannot contain a newline
  case "$NL$BRANCHES$NL" in *"$NL$1$NL"*) return 0 ;; esac
  return 1
}

# --- the live review population ---------------------------------------------
ROWS=$(bd_list --metadata-field task_kind=review --status="$LIVE_STATUSES") || {
  echo "$PROG: could not enumerate live review beads; failing loudly rather than reporting a false all-clear" >&2
  exit 1
}
CANDS=$(printf '%s' "$ROWS" | jq -r '
  .[] | [ ((.id // "") | tostring),
          ((.metadata.anchor_bead // "") | tostring),
          ((.metadata.review_branch // "") | tostring) ] | @tsv' 2>/dev/null)
[ -n "$CANDS" ] || { echo "$PROG: no live review beads"; exit 0; }

swept=0; held=0; stuck=0
while IFS=$'\t' read -r rid anchor branch; do
  [ -n "${rid:-}" ] || continue
  # Cheapest discriminator first: a branch still on origin is a live surface,
  # and that is the whole population on a healthy day.
  [ -n "$branch" ] || { held=$((held + 1)); continue; }
  on_origin "$branch" && { held=$((held + 1)); continue; }
  [ -n "$anchor" ] || { held=$((held + 1)); continue; }

  if ! AROW=$(bd_show "$anchor"); then
    echo "$PROG: review $rid names anchor $anchor, which does not resolve; leaving the review open" >&2
    held=$((held + 1)); continue
  fi
  ASTATUS=$(row_field "$AROW" status | tr '[:upper:]' '[:lower:]')
  [ "$ASTATUS" = "closed" ] || { held=$((held + 1)); continue; }
  AMR=$(row_meta "$AROW" merge_result)

  gc bd update "$rid" \
    --set-metadata gc.outcome=moot \
    --append-notes "$PROG: closed with no verdict. Anchor $anchor is closed (merge_result=${AMR:-unrecorded}) and origin has no branch $branch, so neither approve nor request-changes could bind to a commit. No gate marker was written and no rework child was filed." \
    --status=closed </dev/null >/dev/null 2>&1 || true

  if ! RROW=$(bd_show "$rid"); then
    echo "$PROG: review $rid could not be re-read after the close; retry next pass" >&2
    stuck=$((stuck + 1)); continue
  fi
  RSTATUS=$(row_field "$RROW" status | tr '[:upper:]' '[:lower:]')
  ROUTCOME=$(row_meta "$RROW" gc.outcome)
  if [ "$RSTATUS" != "closed" ] || [ "$ROUTCOME" != "moot" ]; then
    echo "$PROG: review $rid close did not read back (status='$RSTATUS' gc.outcome='$ROUTCOME'); retry next pass" >&2
    stuck=$((stuck + 1)); continue
  fi
  swept=$((swept + 1))
  echo "$PROG: closed review $rid — anchor $anchor is closed and origin has no branch $branch"
done <<CANDS_EOF
$CANDS
CANDS_EOF

echo "$PROG: $swept review(s) closed, $held left alone, $stuck write(s) held for retry"
exit 0
