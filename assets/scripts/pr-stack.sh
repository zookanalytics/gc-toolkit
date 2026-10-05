#!/usr/bin/env bash
# pr-stack — arm 12 of the merge cadence: keep an open PR current with its anchor,
# in both managed body regions and in its title.
# A PR body is composed once, by pr-open.sh, out of one anchor. Then two things
# drift it. Commits keep arriving on the branch — a fold, a rework or rebase
# hand-back, a stacked bead whose own PR lands into it — and none of them touch the
# `gc:branch-beads` section, so the reviewer approves a scope the body does not
# describe. And a rework restamps the anchor's `pr_summary`, but pr-open composes
# the `gc:pr-summary` region only at pre_open_gate and the anchor never returns
# there once open (lifecycle has no pull_request -> pre_open_gate edge), so the
# published `## Summary` — the merge surface, and the squash commit message —
# keeps describing superseded work. This arm closes both: for each open PR it
# refreshes the `gc:pr-summary` region when the anchor summary moved past it, then
# re-renders the `gc:branch-beads` section, and lands both in one body edit.
#
# The summary refresh acts only on a well-formed `gc:pr-summary` marker pair whose
# published region is behind the anchor: either its summary text lags the current
# `pr_summary`, or its handoff bullet still names a pre-rework head. A PR merely
# opened, whose summary matches and whose region already names the current head, is a
# no-op, and a legacy markerless or malformed body is left for pr-open's adoption
# path to establish rather than rewritten here. Its handoff bullet is composed in
# `refresh` mode — the reworked head has not re-signed-off, so it names the head and
# points to the PR checks rather than repeating pr-open's pre-open sign-off claim.
# The title drifts the same way. pr-open.sh writes it once, at create, from the
# anchor's title, and the squash commit takes its subject from it, so a PR whose
# anchor a rework retitled would otherwise merge under the superseded name. For a
# pull_request anchor this arm composes the title exactly as the create does
# (cc_title's conventional-commit type, the anchor's title, then the bead id) and
# edits the PR when its words differ. Whitespace alone is never a difference, so a
# title stored with other spacing is not rewritten every pass. The anchor owns the
# title: a title edited on the PR alone is composed back from the anchor on the
# next pass, so a retitle is made on the anchor. The title is an edit of its own,
# so one that fails never holds back a body refresh, nor the other way round.
# For each open anchor (a bead carrying merge_result) that records a pr_number:
# read the branch's bead ledger, three code-written facts unioned —
# metadata.branch (committed onto the branch: the anchor, plus every rework and
# rebase hand-back whose push cleared its pool route — a child still routed to a
# pool has not pushed its fix and stays out), metadata.fold_target (folded onto
# it by a polecat), and
# metadata.merged_target with merge_result=merged (landed its own PR into it) —
# then splice the list into a delimited section at the end of the body. Rows
# that recorded no work are dropped from the ledger — a closed duplicate keeps
# its metadata.branch even for a rebase or rework twin — so the section names
# only commits the branch actually carries. A row whose own branch is some
# other one got here by a merge, so it names that
# branch: a separate work item riding the PR reads differently from a fix to
# it. A stacked bead never renames the PR: the title names the anchor, and the
# body is where a reviewer reads scope.
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
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
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
_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
# The managed `## Summary` region (markers, composer and splice helpers) and the
# title composer (cc_title), shared with pr-open.sh so an opened PR and a
# post-open refresh never diverge.
# shellcheck source=pr-summary-region.sh
. "${GC_PR_SUMMARY_LIB:-$_bd_lib_dir/pr-summary-region.sh}" || { echo "cannot source pr-summary-region.sh beside this script" >&2; exit 1; }

# The branch's bead ledger: the three keys the cadence writes when work reaches
# a branch, unioned and deduped, then the rows that recorded no work removed. A
# closed duplicate keeps its metadata.branch — and for a rebase or rework twin
# that branch names this very head — so it reaches the union by that key while
# having contributed no commit. A row carrying duplicate_of, or a no-op
# work_outcome under either key, is dropped, so the section never tells a
# reviewer to approve work that is not on the branch. Any unreadable half fails
# the whole ledger.
#
# The branch key alone is not proof of a commit: signoff.sh stamps
# branch=<this head> on a rework child at CREATION, before any polecat claims
# it, and that child sits open and routed to a pool until one does. Its fix is
# not on the branch, so a direct row that is still routed to a pool
# (gc.routed_to set, not `human`) and carries no merge_result is dropped — the
# same route signal merge.sh reads to hold a merge for an in-flight child. The
# anchor (merge_result set) and a hand-back whose submit-and-exit cleared the
# route both stay; fold_target and merged_target rows are records of work
# already on the branch and skip this gate.
ledger_of() { # <branch>
  local br="$1" direct folded landed
  direct=$(bd_list --status="$ALL_STATUSES" --metadata-field branch="$br") || return 1
  direct=$(printf '%s' "$direct" | jq '
    map(select(
      (((.metadata // {}).merge_result // "") | tostring) != ""
      or (((.metadata // {})["gc.routed_to"] // "") | tostring | (. == "" or . == "human"))
    ))') || return 1
  folded=$(bd_list --status="$ALL_STATUSES" --metadata-field fold_target="$br") || return 1
  landed=$(bd_list --status="$ALL_STATUSES" --metadata-field merged_target="$br" \
    --metadata-field merge_result=merged) || return 1
  printf '%s\n%s\n%s\n' "$direct" "$folded" "$landed" \
    | jq -s 'add | unique_by(.id)
        | map(select(
            (((.metadata // {}).duplicate_of // "") | tostring) == "" and
            (((.metadata // {}).work_outcome // "") | tostring) != "no-op" and
            (((.metadata // {})["gc.work_outcome"] // "") | tostring) != "no-op"
          ))' 2>/dev/null
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

# Bring the gc:pr-summary region current with the anchor. 0 = the region was behind
# and <out-file> now carries it refreshed; 1 = no change (no summary to publish, no
# well-formed region, or the region already carries this summary at this head). The
# region is behind when its summary text lags the anchor OR its handoff bullet names
# a head other than the current one — a rework that moves the head without touching
# the summary still restamps the "at <head>" claim. Only a well-formed marker pair
# (prs_marker_state 0) is rewritten in place: a legacy markerless or malformed body
# is pr-open's adoption path to establish, not this arm's to reshape. The region is
# recomposed in `refresh` mode — the reworked head has not re-signed-off, so the
# handoff bullet names the head and defers the check state to the PR rather than
# repeating the pre-open sign-off claim.
refresh_summary() { # <id> <body-in> <body-out> <anchor-row-json> <head_oid>
  local id="$1" bin="$2" bout="$3" row="$4" head_oid="$5"
  local summary want cur desc checkset branch target SECTION
  summary=$(printf '%s' "$row" | jq -r '.metadata.pr_summary // empty' 2>/dev/null)
  [ -n "$(printf '%s' "$summary" | tr -d '[:space:]')" ] || return 1
  prs_marker_state "$bin" || return 1
  want=$(strip_summary_heading "$summary")
  cur=$(prs_region_summary "$bin")
  # Current only when the summary matches AND the region already names this head:
  # a head-only rework leaves the summary current but the handoff bullet stale.
  if [ "$cur" = "$want" ] && prs_region_names_head "$bin" "$head_oid"; then
    return 1
  fi
  desc=$(printf '%s' "$row" | jq -r '.description // empty' 2>/dev/null)
  checkset=$(printf '%s' "$row" | jq -r '.metadata.check_set // ""' 2>/dev/null)
  branch=$(printf '%s' "$row" | jq -r '.metadata.branch // empty' 2>/dev/null)
  target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // .metadata.target // "main"' 2>/dev/null)
  SECTION=$(mktemp "$STACK_TMP/summary.XXXXXX") || return 1
  if ! compose_managed "$summary" "$desc" "$id" "$branch" "$target" "$checkset" "$head_oid" "" "" refresh > "$SECTION" \
     || [ ! -s "$SECTION" ]; then
    rm -f "$SECTION"; return 1
  fi
  prs_splice_in_place "$bin" "$SECTION" "$bout"
  rm -f "$SECTION"
  return 0
}

# A title compared by its words: whitespace runs collapse to one space and the ends
# are trimmed, so two titles that differ only in spacing compare equal.
title_words() { # <title>
  printf '%s' "$1" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'
}

# The title the PR should carry: the anchor's own, composed exactly as pr-open.sh
# composes it at create (cc_title, then the bead id), in title_words form, which is
# also the form a retitle writes. Prints nothing for an anchor row with no title: a
# bare type and id names nothing, so the PR's title is left as it stands.
want_title() { # <anchor-row-json> <id>
  local t k
  t=$(printf '%s' "$1" | jq -r '.title // empty' 2>/dev/null)
  [ -n "$(title_words "$t")" ] || return 0
  k=$(printf '%s' "$1" | jq -r '.issue_type // empty' 2>/dev/null)
  title_words "$(cc_title "$t" "$k") ($2)"
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

edited=0; current=0; single=0; skipped=0; refreshed=0; retitled=0
SEEN=""
# Per-anchor scratch (rendered section, current body, spliced body) lives under
# one trapped directory, so a signal or timeout mid-iteration takes the whole
# tree with it rather than orphaning gctk-pr-stack.* files in /tmp.
STACK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gctk-pr-stack.XXXXXX") || { echo "$PROG: cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$STACK_TMP"' EXIT; trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
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
    --json number,state,headRefName,headRefOid,body,title </dev/null 2>/dev/null)
  got_num=$(printf '%s' "$PR_JSON" | jq -r '(.number // "") | tostring' 2>/dev/null)
  got_head=$(printf '%s' "$PR_JSON" | jq -r '.headRefName // ""' 2>/dev/null)
  got_state=$(printf '%s' "$PR_JSON" | jq -r '.state // ""' 2>/dev/null)
  got_oid=$(printf '%s' "$PR_JSON" | jq -r '(.headRefOid // "") | tostring' 2>/dev/null)
  got_title=$(printf '%s' "$PR_JSON" | jq -r '(.title // "") | tostring' 2>/dev/null)
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

  # Scratch for this PR: the current body, the branch-beads section, and a splice
  # target the two region edits accumulate onto in turn.
  if ! { CUR=$(mktemp "$STACK_TMP/cur.XXXXXX") && SECTION=$(mktemp "$STACK_TMP/section.XXXXXX") && NEW=$(mktemp "$STACK_TMP/new.XXXXXX"); }; then
    echo "$PROG: cannot create a temp file" >&2; exit 1
  fi
  printf '%s' "$PR_JSON" | jq -r '.body // ""' 2>/dev/null | tr -d '\r' > "$CUR"
  did_summary=0; did_beads=0; beads_n=0; beads_status=""

  # (a) gc:pr-summary — a pull_request anchor. A rework restamps the anchor summary
  # and no earlier arm republishes it once open, so bring the region current when it
  # is behind. Scoped to pull_request: a pre_open_gate anchor is arm 6's to refresh
  # as it adopts and flips, and this is the layer arm 6 cannot reach once the anchor
  # has left that state. A change folds into CUR so the branch-beads pass below reads
  # it and both land in one edit.
  anchor_row=$(printf '%s' "$ANCHORS" | jq -c --arg id "$id" 'map(select(.id == $id)) | .[0] // empty' 2>/dev/null)
  anchor_mr=$(printf '%s' "$anchor_row" | jq -r '(.metadata.merge_result // "") | tostring' 2>/dev/null)
  if [ "$anchor_mr" = "pull_request" ] && refresh_summary "$id" "$CUR" "$NEW" "$anchor_row" "$got_oid"; then
    mv "$NEW" "$CUR"; did_summary=1
  fi

  # (b) gc:branch-beads — a PR carrying more than the opener names every bead on
  # the branch.
  if ! LEDGER=$(ledger_of "$branch"); then
    echo "$PROG: $id could not read the bead ledger for '$branch'; PR#$num branch-beads left as it stands" >&2
    beads_status=skip
  else
    n=$(printf '%s' "$LEDGER" | jq 'length' 2>/dev/null)
    case "$n" in
      ''|*[!0-9]*) beads_status=skip ;;
      *)
        # One bead is the ordinary PR, and pr-open.sh already names it.
        if [ "$n" -lt 2 ]; then
          beads_status=single
        else
          render_section "$branch" "$id" "$LEDGER" > "$SECTION"
          if [ ! -s "$SECTION" ]; then
            echo "$PROG: $id rendered an empty section for '$branch'; PR#$num branch-beads left as it stands" >&2
            beads_status=skip
          else
            marker_state "$CUR"; ms=$?
            if [ "$ms" = 2 ]; then
              echo "$PROG: $id PR#$num body carries no well-formed marker pair; branch-beads left alone (an operator edit this cannot reason about)" >&2
              beads_status=skip
            elif [ "$ms" = 0 ] && [ "$(current_section "$CUR")" = "$(cat "$SECTION")" ]; then
              beads_status=current
            else
              if [ "$ms" = 0 ]; then splice_in_place "$CUR" "$SECTION" "$NEW"; else append_section "$CUR" "$SECTION" "$NEW"; fi
              mv "$NEW" "$CUR"; did_beads=1; beads_n="$n"
            fi
          fi
        fi ;;
    esac
  fi

  # (c) the title — a pull_request anchor's, scoped as (a) is: pr-open writes it
  # only at create, so a retitled anchor reaches the PR here or nowhere. A title
  # that read back empty is unreadable, and nothing is written over it.
  did_title=0; pr_title=""
  if [ "$anchor_mr" = "pull_request" ]; then
    live_title=$(title_words "$got_title")
    pr_title=$(want_title "$anchor_row" "$id")
    if [ -n "$live_title" ] && [ -n "$pr_title" ] && [ "$live_title" != "$pr_title" ]; then did_title=1; fi
  fi

  # One body edit carries whatever moved in the body. When nothing moved there, the
  # outcome is accounted per the sections: a section already current is "current",
  # a lone bead is "single-bead", an unreadable or malformed section is "skipped".
  if [ "$did_summary" = 1 ] || [ "$did_beads" = 1 ]; then
    if gh pr edit "$num" --repo "$ORIGIN_REPO_Q" --body-file "$CUR" </dev/null >/dev/null 2>&1; then
      if [ "$did_beads" = 1 ]; then edited=$((edited + 1)); echo "$PROG: $id PR#$num body now names $beads_n beads on '$branch'"; fi
      if [ "$did_summary" = 1 ]; then refreshed=$((refreshed + 1)); echo "$PROG: $id PR#$num summary region refreshed from the anchor's current pr_summary"; fi
    else
      echo "$PROG: $id PR#$num body edit failed; retried next pass" >&2
      skipped=$((skipped + 1))
    fi
  else
    case "$beads_status" in
      single) single=$((single + 1)) ;;
      skip)   skipped=$((skipped + 1)) ;;
      *)      current=$((current + 1)) ;;
    esac
  fi
  # The title's own edit: a title edit that fails costs the body nothing, and a
  # body edit that failed above does not hold the title back.
  if [ "$did_title" = 1 ]; then
    if gh pr edit "$num" --repo "$ORIGIN_REPO_Q" --title "$pr_title" </dev/null >/dev/null 2>&1; then
      retitled=$((retitled + 1)); echo "$PROG: $id PR#$num title now composed from the anchor: $pr_title"
    else
      echo "$PROG: $id PR#$num title edit failed; retried next pass" >&2
      skipped=$((skipped + 1))
    fi
  fi
  rm -f "$SECTION" "$CUR" "$NEW"
done <<ANCHORS_EOF
$(printf '%s' "$ANCHORS" | jq -r '.[]
  | [ ((.id // "") | tostring),
      (((.metadata // {}).branch // "") | tostring),
      (((.metadata // {}).pr_number // "") | tostring) ] | @tsv' 2>/dev/null)
ANCHORS_EOF

echo "$PROG: $edited edited, $refreshed summary-refreshed, $retitled retitled, $current already current, $single single-bead, $skipped skipped"
exit 0
