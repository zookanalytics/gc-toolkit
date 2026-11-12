#!/usr/bin/env bash
# pr-stack — arm 10 of the merge cadence: keep an open PR current with its anchor,
# in both managed body sections and in its title.
# A PR body is composed once, by pr-open.sh, out of one anchor. Then two things
# drift it. Commits keep arriving on the branch — a fold, a rework or rebase
# hand-back, a stacked bead whose own PR lands into it — and none of them touch the
# `gc:branch-beads` section, so the reviewer approves a scope the body does not
# describe. And a rework restamps the anchor's PR summary, but pr-open composes
# the `gc:pr-summary` region only at pre_open_gate and the anchor never returns
# there once open (lifecycle has no pull_request -> pre_open_gate edge), so the
# published `## Summary` — the merge surface, and the squash commit message —
# keeps describing superseded work. The title drifts the same way: pr-open.sh
# writes it once, at create, and the squash commit takes its subject from it.
# This arm closes all three. For each open PR it asks `gctk pr compose` for the
# title and body its anchor says the PR should carry, lands the body in one edit
# when a section moved, and the title in an edit of its own when its words
# differ.
# The rules of each section are the composer's: the summary region is rewritten
# only when it no longer says what the anchor says at the PR's head, read by its
# markers; the branch-beads section names every bead whose work the branch
# carries, once there is more than the anchor's own; a body whose markers are
# not one well-formed pair is left alone; and a ledger that does not read leaves
# its section as it stands, because a short list published as the whole one
# would drop beads the body names. Whitespace alone is never a title difference,
# so a title stored with other spacing is not rewritten every pass. The anchor
# owns the title: a title edited on the PR alone is composed back from the anchor
# on the next pass, so a retitle is made on the anchor. A title edit that fails
# never holds back a body edit, nor the other way round.
# The summary region and the title are a pull_request anchor's: a pre_open_gate
# anchor's PR is arm 3's to refresh as it adopts and flips, and this is the layer
# arm 3 cannot reach once the anchor has left that state. The branch-beads
# section is every open anchor's.
# Read-modify-write, pinned to origin and certified by number before any write
# (right repo, right head branch, state OPEN). Any read that fails skips that
# anchor.
# Args: [--deadline <epoch-secs>] [--cursor <file>] pace the walk over the open
# PRs: a rotation, with no new PR started past the deadline (pace-lib.sh).
# Caller: refinery-reconcile.sh. Fail-closed on identity; not set -e.
set -u

PROG="pr-stack"
DEADLINE=""; CURSOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --deadline) DEADLINE="${2:-}"; shift 2 ;;
    --cursor)   CURSOR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

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
# shellcheck source=pace-lib.sh
. "$_bd_lib_dir/pace-lib.sh" || { echo "cannot source pace-lib.sh beside this script" >&2; exit 1; }
# The PR's title and body are composed by `gctk pr compose`, which pr-open.sh
# asks too, so an opened PR and a post-open refresh never diverge. The binary is
# the one gctk-resolve.sh's chain names.
# shellcheck source=gctk-resolve.sh
. "$_bd_lib_dir/gctk-resolve.sh" || { echo "cannot source gctk-resolve.sh beside this script" >&2; exit 1; }
REVIEW_CHECKS="$_bd_lib_dir/review-checks.sh"

# The anchor's gates at <head_oid>, `<name>\t<phase>` per line, which a summary
# region the composer must rewrite names. Read only when it asks for them, so an
# open PR whose region is current costs no resolve. Non-zero when the resolver
# fails: an unreadable set is never an empty one.
resolve_phased() { # <check_set> <head_oid>
  [ -x "$REVIEW_CHECKS" ] || return 1
  "$REVIEW_CHECKS" --resolve --check-set "${1:-}" --through open-as-draft --with-phase --at "${2:-}" 2>/dev/null
}

# The answer of `gctk pr compose <id> <flags>`: one JSON object carrying the
# title, the body and each section's outcome. Non-zero, printing nothing, when no
# binary is there to ask or it composed nothing; a pass with no binary says so
# once.
GCTK=""; GCTK_MISSING=""
compose_pr() { # <id> <gctk pr compose flags...>
  if [ -z "$GCTK" ]; then
    [ -z "$GCTK_MISSING" ] || return 1
    if ! GCTK=$(gctk_path); then
      GCTK_MISSING=1
      echo "$PROG: no gctk binary to compose a PR with (GCTK_BIN='${GCTK_BIN:-}'); no PR is edited this pass" >&2
      return 1
    fi
  fi
  "$GCTK" pr compose "$@" </dev/null
}

# A title compared by its words: whitespace runs collapse to one space and the ends
# are trimmed, so two titles that differ only in spacing compare equal.
title_words() { # <title>
  printf '%s' "$1" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'
}

# --- enumerate ------------------------------------------------------------------
# Anchors, not every bead that records a PR: pr-facts.sh stamps pr_number on
# rework and review children too, and a child is a bead on the branch, never a
# writer of the body.
ANCHORS=$(bd_list --status=open --has-metadata-key merge_result) || {
  echo "$PROG: could not enumerate open anchors; failing loudly rather than reporting a false all-clear" >&2
  exit 1
}
[ "$ANCHORS" != "[]" ] || { echo "$PROG: no open anchors"; exit 0; }

edited=0; current=0; single=0; skipped=0; refreshed=0; retitled=0
SEEN=""; prs=0
# Per-anchor scratch (the published body and the composed one) lives under
# one trapped directory, so a signal or timeout mid-iteration takes the whole
# tree with it rather than orphaning gctk-pr-stack.* files in /tmp.
STACK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gctk-pr-stack.XXXXXX") || { echo "$PROG: cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$STACK_TMP"' EXIT; trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
pace_start "$CURSOR" "$DEADLINE"
while IFS=$'\t' read -r id branch num; do
  [ -n "${id:-}" ] || continue
  if [ -z "$branch" ] || [ -z "$num" ] || [ -n "${num//[0-9]/}" ]; then continue; fi
  # One PR is written once a pass. Two open anchors on one PR is the defect
  # merge.sh holds and escalates; here it would only mean the same section
  # composed twice.
  case " $SEEN " in *" $num "*) continue ;; esac
  SEEN="$SEEN $num"
  prs=$((prs + 1))
  pace_visit rest "$id"; case $? in 1) continue ;; 2) break ;; esac

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

  # Scratch for this PR: the body as published, and the body composed for it.
  if ! { CUR=$(mktemp "$STACK_TMP/cur.XXXXXX") && NEW=$(mktemp "$STACK_TMP/new.XXXXXX"); }; then
    echo "$PROG: cannot create a temp file" >&2; exit 1
  fi
  printf '%s' "$PR_JSON" | jq -r '.body // ""' 2>/dev/null > "$CUR"

  # One composition: (a) the gc:pr-summary region of a pull_request anchor at the
  # PR's head, and (b) the gc:branch-beads section of every open PR. A region the
  # composer must rewrite names the anchor's gates at that head, which are read
  # only then, so a current region costs no resolve, and one whose gates do not
  # read is left as it stands this pass.
  anchor_row=$(printf '%s' "$ANCHORS" | jq -c --arg id "$id" 'map(select(.id == $id)) | .[0] // empty' 2>/dev/null)
  anchor_mr=$(printf '%s' "$anchor_row" | jq -r '(.metadata.merge_result // "") | tostring' 2>/dev/null)
  sections="branch-beads"
  [ "$anchor_mr" = "pull_request" ] && [ -n "$got_oid" ] && sections="summary,branch-beads"
  COMPOSED=$(compose_pr "$id" --head "$got_oid" --sections "$sections" --body-file "$CUR")
  if [ "$(printf '%s' "$COMPOSED" | jq -r '.summary // empty' 2>/dev/null)" = needs-gates ]; then
    checkset=$(printf '%s' "$anchor_row" | jq -r '.metadata.check_set // ""' 2>/dev/null)
    if phased=$(resolve_phased "$checkset" "$got_oid") \
       && gated=$(compose_pr "$id" --head "$got_oid" --sections "$sections" --body-file "$CUR" --gates "$phased"); then
      COMPOSED="$gated"
    fi
  fi
  if [ -z "$(printf '%s' "$COMPOSED" | jq -r '.branch_beads // empty' 2>/dev/null)" ]; then
    echo "$PROG: $id PR#$num title and body could not be composed; nothing edited" >&2
    skipped=$((skipped + 1)); rm -f "$CUR" "$NEW"; continue
  fi
  printf '%s' "$COMPOSED" | jq -j '.body // ""' > "$NEW"
  did_summary=0; did_beads=0; beads_status=""
  [ "$(printf '%s' "$COMPOSED" | jq -r '.summary // empty')" = written ] && did_summary=1
  beads_n=$(printf '%s' "$COMPOSED" | jq -r '.branch_bead_count // 0')
  case "$(printf '%s' "$COMPOSED" | jq -r '.branch_beads // empty')" in
    written) did_beads=1 ;;
    current) beads_status=current ;;
    single)  beads_status=single ;;
    unread)
      echo "$PROG: $id could not read the bead ledger for '$branch'; PR#$num branch-beads left as it stands" >&2
      beads_status=skip ;;
    unmanaged)
      echo "$PROG: $id PR#$num body carries no well-formed marker pair; branch-beads left alone (an operator edit this cannot reason about)" >&2
      beads_status=skip ;;
    *) beads_status=skip ;;
  esac

  # (c) the title — a pull_request anchor's, scoped as (a) is: pr-open writes it
  # only at create, so a retitled anchor reaches the PR here or nowhere. A title
  # that read back empty is unreadable, and nothing is written over it.
  did_title=0; pr_title=""
  if [ "$anchor_mr" = "pull_request" ]; then
    live_title=$(title_words "$got_title")
    pr_title=$(printf '%s' "$COMPOSED" | jq -r '.title // empty')
    if [ -n "$live_title" ] && [ -n "$pr_title" ] && [ "$live_title" != "$pr_title" ]; then did_title=1; fi
  fi

  # One body edit carries whatever moved in the body. When nothing moved there, the
  # outcome is accounted per the sections: a section already current is "current",
  # a lone bead is "single-bead", an unreadable or malformed section is "skipped".
  if [ "$did_summary" = 1 ] || [ "$did_beads" = 1 ]; then
    if gh pr edit "$num" --repo "$ORIGIN_REPO_Q" --body-file "$NEW" </dev/null >/dev/null 2>&1; then
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
  rm -f "$CUR" "$NEW"
done <<ANCHORS_EOF
$(printf '%s' "$ANCHORS" | jq -c '.[]' 2>/dev/null | pace_order "$CURSOR" | jq -r '
    [ ((.id // "") | tostring),
      (((.metadata // {}).branch // "") | tostring),
      (((.metadata // {}).pr_number // "") | tostring) ] | @tsv' 2>/dev/null)
ANCHORS_EOF
pace_end

if [ -n "$PACE_RESUME_AT" ]; then
  echo "$PROG: visited $PACE_VISITED PRs before the deadline; the next pass resumes at $PACE_RESUME_AT"
else
  echo "$PROG: visited $PACE_VISITED of $prs PRs"
fi
echo "$PROG: $edited edited, $refreshed summary-refreshed, $retitled retitled, $current already current, $single single-bead, $skipped skipped"
exit 0
