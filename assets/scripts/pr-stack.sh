#!/usr/bin/env bash
# pr-stack — arm 8 of the merge cadence: keep an open PR's body naming every
# bead whose work is on its head branch.
# A PR body is composed once, by pr-open.sh, out of one anchor. Commits keep
# arriving on the branch afterwards — a fold, a rework or rebase hand-back, a
# stacked bead whose own PR lands into it — and none of them touch the body, so
# the reviewer approves a scope the body does not describe.
# For each open anchor (a bead carrying merge_result) that records a pr_number:
# read the branch's bead ledger, three code-written facts unioned —
# metadata.branch (committed onto the branch: the anchor, plus every rework and
# rebase hand-back), metadata.fold_target (folded onto it by a polecat), and
# metadata.merged_target with merge_result=merged (landed its own PR into it) —
# then splice the list into a delimited section at the end of the body. A row
# whose own branch is some other one got here by a merge, so it names that
# branch: a separate work item riding the PR reads differently from a fix to
# it. The title is never touched: it names the anchor, and the body is where a
# reviewer reads scope.
# One bead is the ordinary case and says nothing pr-open.sh has not already
# written, so nothing is published under it.
# Read-modify-write, pinned to origin and certified by number before any write
# (right repo, right head branch, state OPEN). The body is read \r-stripped:
# GitHub stores a body it re-wrapped with CRLF, and a marker line carrying a
# trailing CR matches neither the splice nor the compare, so every pass would
# append a second section. Idempotence is then the rendered section compared
# against the one already between the markers, never the whole body, and a body
# whose markers are not one well-formed pair is left alone rather than
# rewritten every pass. Any read that fails skips that anchor — a truncated
# ledger published as the whole ledger is worse than last pass's section.
# Caller: refinery-reconcile.sh. Fail-closed on identity; not set -e.
set -u

PROG="pr-stack"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

# Every status a bead can rest in. The ledger is a record of work that reached
# the branch, so a closed contributor counts exactly as much as an open one —
# and --metadata-field answers OPEN-only unless the statuses are named.
ALL_STATUSES="open,in_progress,blocked,deferred,hooked,pinned,closed"
MARK_OPEN="<!-- gc:branch-beads -->"
MARK_CLOSE="<!-- /gc:branch-beads -->"

command -v gh >/dev/null 2>&1 || exit 0

# The repository every read and the edit are pinned to — from the origin
# remote, never from gh (gh's current repo is the movable source this distrusts).
ORIGIN_HOST=""; ORIGIN_REPO=""; ORIGIN_REPO_Q=""
u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
case "$u" in
  git@github.com:*|https://github.com/*|ssh://git@github.com/*)
    ORIGIN_HOST="github.com"
    ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
      -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
esac
case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
if [ -z "$ORIGIN_REPO" ]; then
  echo "$PROG: cannot resolve this checkout's origin repository; NOTHING is edited this pass" >&2
  exit 0
fi
ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"

# Guarded read: non-zero means "could not tell", never "nothing there".
bd_list() {
  local raw rc
  raw=$(gc bd list "$@" --limit=0 --json </dev/null 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}

# The branch's bead ledger: the three keys the cadence writes when work reaches
# a branch, unioned and deduped. Any unreadable half fails the whole ledger.
ledger_of() { # <branch>
  local br="$1" direct folded landed
  direct=$(bd_list --status="$ALL_STATUSES" --metadata-field branch="$br") || return 1
  folded=$(bd_list --status="$ALL_STATUSES" --metadata-field fold_target="$br") || return 1
  landed=$(bd_list --status="$ALL_STATUSES" --metadata-field merged_target="$br" \
    --metadata-field merge_result=merged) || return 1
  printf '%s\n%s\n%s\n' "$direct" "$folded" "$landed" \
    | jq -s 'add | unique_by(.id)' 2>/dev/null
}

# The section the PR body should carry. The anchor leads as the bead the PR was
# opened for; the rest follow oldest-first, which is the order their commits
# reached the branch.
# A row whose own metadata.branch is some OTHER branch got here by a merge, so
# it is a separate work item riding this PR rather than a fix to it — the
# distinction the reviewer needs, and it costs a field already in hand.
render_section() { # <branch> <anchor-id> <ledger-json>
  printf '%s' "$3" | jq -r --arg br "$1" --arg anchor "$2" '
    def clean: (. // "") | tostring | gsub("[\r\n\t]+"; " ")
                 | gsub("<!--"; "") | gsub("-->"; "") | .[0:160];
    def own: ((.metadata // {}).branch // "") | tostring;
    ( [ .[] | select(.id == $anchor) ]
      + ( [ .[] | select(.id != $anchor) ]
          | sort_by((.created_at // .created // ""), .id) ) ) as $rows
    | "## Beads on this branch",
      "",
      "Every bead whose work is on `\($br)`. Approving this PR approves all of them.",
      "",
      ( $rows[]
        | "- `\(.id)` — \(.title | clean)"
          + (if .id == $anchor then " _(opener)_"
             elif (own != "" and own != $br) then " _(merged in from `\(own)`)_"
             else "" end) )
  ' 2>/dev/null
}

# What stands between the markers in the body already, or empty when the
# markers are absent. The body file this reads is already \r-stripped.
current_section() { # <body-file>
  awk -v o="$MARK_OPEN" -v c="$MARK_CLOSE" '
    $0 == o { f = 1; next }
    $0 == c { f = 0; next }
    f { print }
  ' "$1"
}

# 0 = exactly one well-formed pair (replace in place); 1 = neither marker
# (append); 2 = any other shape — a lone marker, a second pair, a close above
# its open. Under those, the section this reads back is not the section it
# wrote, so every pass would disagree with the body and edit it again. A body
# somebody has cut into a shape this cannot reason about is left alone.
marker_state() { # <body-file>
  local o c oi ci
  o=$(grep -cxF "$MARK_OPEN" "$1" 2>/dev/null || true)
  c=$(grep -cxF "$MARK_CLOSE" "$1" 2>/dev/null || true)
  [ "$o" = 0 ] && [ "$c" = 0 ] && return 1
  { [ "$o" = 1 ] && [ "$c" = 1 ]; } || return 2
  oi=$(grep -nxF "$MARK_OPEN" "$1" | head -1 | cut -d: -f1)
  ci=$(grep -nxF "$MARK_CLOSE" "$1" | head -1 | cut -d: -f1)
  [ "$oi" -lt "$ci" ] || return 2
  return 0
}

# The body with the section replaced between its markers.
splice_in_place() { # <body-file> <section-file> <out-file>
  awk -v o="$MARK_OPEN" -v c="$MARK_CLOSE" -v s="$2" '
    $0 == o { print; while ((getline l < s) > 0) print l; close(s); f = 1; next }
    $0 == c { print; f = 0; next }
    !f { print }
  ' "$1" > "$3"
}

# The body with the section, and its markers, appended below what is there.
append_section() { # <body-file> <section-file> <out-file>
  { cat "$1"; printf '\n%s\n' "$MARK_OPEN"; cat "$2"; printf '%s\n' "$MARK_CLOSE"; } > "$3"
}

# --- enumerate ------------------------------------------------------------------
# Anchors, not every bead that records a PR: pr-facts.sh stamps pr_number on
# rework and review children too, and a child is a contributor to the ledger,
# never a writer of the body.
ANCHORS=$(bd_list --status=open --has-metadata-key merge_result) || {
  echo "$PROG: could not enumerate open anchors; failing loudly rather than reporting a false all-clear" >&2
  exit 1
}
[ "$ANCHORS" != "[]" ] || { echo "$PROG: no open anchors"; exit 0; }

edited=0; current=0; single=0; skipped=0
SEEN=""
while IFS=$'\t' read -r id branch num; do
  [ -n "${id:-}" ] || continue
  if [ -z "$branch" ] || [ -z "$num" ] || [ -n "${num//[0-9]/}" ]; then continue; fi
  # One PR is written once a pass. Two open anchors on one PR is the defect
  # merge.sh holds and escalates; here it would only mean the same section
  # composed twice.
  case " $SEEN " in *" $num "*) continue ;; esac
  SEEN="$SEEN $num"

  # </dev/null on every call in this loop: it is fed by a heredoc, and a child
  # inheriting its stdin would consume the anchor rows behind it.
  PR_JSON=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" \
    --json number,state,headRefName,body </dev/null 2>/dev/null)
  got_num=$(printf '%s' "$PR_JSON" | jq -r '(.number // "") | tostring' 2>/dev/null)
  got_head=$(printf '%s' "$PR_JSON" | jq -r '.headRefName // ""' 2>/dev/null)
  got_state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""' 2>/dev/null)
  if [ -z "$got_num" ] || [ -z "$got_head" ] || [ -z "$got_state" ]; then
    echo "$PROG: $id PR#$num unreadable (num='$got_num' head='$got_head' state='$got_state'); nothing edited" >&2
    skipped=$((skipped + 1)); continue
  fi
  if [ "$got_num" != "$num" ] || [ "$got_head" != "$branch" ]; then
    echo "$PROG: $id asked for PR#$num on '$branch', got PR#$got_num on '$got_head'; not ours" >&2
    skipped=$((skipped + 1)); continue
  fi
  # A landed or closed PR is a record, not a thing a reviewer is deciding on.
  [ "$got_state" = "OPEN" ] || continue

  LEDGER=$(ledger_of "$branch") || {
    echo "$PROG: $id could not read the bead ledger for '$branch'; PR#$num left as it stands" >&2
    skipped=$((skipped + 1)); continue
  }
  n=$(printf '%s' "$LEDGER" | jq 'length' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) skipped=$((skipped + 1)); continue ;; esac
  # One bead is the ordinary PR, and pr-open.sh already names it.
  if [ "$n" -lt 2 ]; then single=$((single + 1)); continue; fi

  if ! { SECTION=$(mktemp) && CUR=$(mktemp) && NEW=$(mktemp); }; then
    echo "$PROG: cannot create a temp file" >&2; exit 1
  fi
  render_section "$branch" "$id" "$LEDGER" > "$SECTION"
  printf '%s' "$PR_JSON" | jq -r '.body // ""' 2>/dev/null | tr -d '\r' > "$CUR"
  if [ ! -s "$SECTION" ]; then
    rm -f "$SECTION" "$CUR" "$NEW"
    echo "$PROG: $id rendered an empty section for '$branch'; PR#$num left as it stands" >&2
    skipped=$((skipped + 1)); continue
  fi
  marker_state "$CUR"; ms=$?
  if [ "$ms" = 2 ]; then
    rm -f "$SECTION" "$CUR" "$NEW"
    echo "$PROG: $id PR#$num body carries no well-formed marker pair; left alone (an operator edit this cannot reason about)" >&2
    skipped=$((skipped + 1)); continue
  fi
  if [ "$ms" = 0 ] && [ "$(current_section "$CUR")" = "$(cat "$SECTION")" ]; then
    rm -f "$SECTION" "$CUR" "$NEW"; current=$((current + 1)); continue
  fi
  if [ "$ms" = 0 ]; then
    splice_in_place "$CUR" "$SECTION" "$NEW"
  else
    append_section "$CUR" "$SECTION" "$NEW"
  fi
  if gh pr edit "$num" --repo "$ORIGIN_REPO_Q" --body-file "$NEW" </dev/null >/dev/null 2>&1; then
    edited=$((edited + 1))
    echo "$PROG: $id PR#$num body now names $n beads on '$branch'"
  else
    echo "$PROG: $id PR#$num body edit failed; retried next pass" >&2
    skipped=$((skipped + 1))
  fi
  rm -f "$SECTION" "$CUR" "$NEW"
done <<ANCHORS_EOF
$(printf '%s' "$ANCHORS" | jq -r '.[]
  | [ ((.id // "") | tostring),
      (((.metadata // {}).branch // "") | tostring),
      (((.metadata // {}).pr_number // "") | tostring) ] | @tsv' 2>/dev/null)
ANCHORS_EOF

echo "$PROG: $edited edited, $current already current, $single single-bead, $skipped skipped"
exit 0
