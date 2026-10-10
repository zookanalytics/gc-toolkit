#!/usr/bin/env bash
# scaffolding-sweep — retires the machine review scaffolding hung on an anchor
# once that anchor is DISPOSED — withdrawn won't-do, or closed not-planned — so a
# disposed anchor can finalize instead of standing "stuck" behind scaffolding
# that will never resolve. The scaffolding is the validation pass, the finding
# beads, and the rework/fix-unit beads (task_kind=validation|finding|rework),
# each carrying anchor_bead=<anchor>. A validation pass, a must-fix finding and
# a fix unit each hold a `blocks` edge on the anchor, and a fix unit also blocks
# every must-fix finding it answers. While any is open the anchor cannot be
# non-force-closed and gate-ensure's quiescence holds its lane, which is the
# "stuck forever" an abandoned or withdrawn anchor otherwise sits in: nothing in
# the cadence closes this scaffolding once the subject stops moving
# (close-answered keys on a fix LANDING, not on a disposal).
#
# Callers: refinery-reconcile.sh, as arm 10, over every disposed anchor; and
# pr-facts.sh's disposition arm, with --anchor <id>, over the one anchor whose
# terminal close it is about to take. That arm runs it before bead-rehome.sh
# closes the anchor, so the close is not refused for scaffolding this sweep
# would retire anyway, and both callers retire exactly the same set.
#
# What this does NOT touch:
#   - task_kind=review — review-sweep.sh (arm 9) owns a review with no surface.
#   - task_kind=visit — a human conversation. A disposed PR does not moot why it
#     closed or what comes next, and finalize-gate.sh holds the anchor's own
#     close while a visit is open. Human gates and visits are left standing.
#   - the anchor itself — bead-rehome.sh (via pr-facts.sh's close arm) is the one
#     anchor-closer, and finalize-gate holds it while a human visit is owed.
#     Clearing the machine scaffolding here is what lets that close land once the
#     human side is done; this sweep never closes an anchor.
#   - a bead carrying rebase_hold — an operator's freeze, which pr-facts.sh's
#     parked-children drop honors too. Its blocks edge keeps the anchor open
#     until the operator lifts the hold.
#
# The disposed signal is read from the ANCHOR: a non-empty gc.superseded_by (the
# pointer bead-rehome.sh stamps and reads back) or a gc.pr_close_disposition_kind
# (the intent pr-dispose.sh records before the PR closes). Neither is ever
# stamped on a landing, so a merged anchor's leftover scaffolding is out of scope
# (that is finding.sh close-answered's, keyed on the fix landing); a merged
# anchor is skipped explicitly as a backstop.
#
# The close order follows those edges (finding.sh wire-fix-unit writes the fix
# unit's): reworks close first, then findings, then validation passes, so no
# close is refused by a blocker still open in the same pass. Anything left blocked is reported and
# retried next pass. A claimed scaffolding bead is swept too: on a disposed
# anchor its holder has nothing left to produce. Closes are read back; a close
# that does not stick is held for retry, never counted.
#
# A finding is mooted only when it objects to the disposed diff. A machine-lane
# finding does, by the review contract: a reviewer files an out-of-scope bug as
# a bead of its own, never as a finding (formulas/mol-review.toml, step 6b). So
# does a human finding whose locus names no file, an objection to the PR as a
# whole, and one whose GitHub comment sits on a line the diff added or removed.
# A human comment on a line the diff did not change can cite code the target
# branch already carries, and closing the PR does not answer it, so that finding
# is carried forward instead. A bug bead takes its objection, and the finding
# closes through bead-rehome.sh pointed at that bug. The bug carries no
# anchor_bead, so it reaches a first reaction like any discovered work, and it
# is born with gc.supersedes=<finding>, so a retry finds it rather than filing
# a twin. A human finding that names a file but records no comment id, or sits
# on an anchor that records no PR, can never be checked and is carried forward
# the same way. One whose PR comments do not read this pass is left for the
# next.
#
# Reads anchors and, once per anchor carrying a human finding that names a file,
# that PR's inline review comments. Writes scaffolding beads (gc.outcome=moot,
# the reason appended to notes, status closed, all read back) and, for a finding
# carried forward, one bug bead and the bead-rehome.sh close of the finding.
# Exits: 0 pass completed · 1 an enumeration could not be read (nothing swept) ·
# 2 usage · 3 (--anchor only) a finding's comment line could not be read, so
# the anchor is not ready to close this pass.
set -u

PROG="scaffolding-sweep"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# Scaffolding is dispatched into any of these; closed ones need no sweeping.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
ALL_STATUSES="$LIVE_STATUSES,closed"

ANCHOR_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)
      [ -n "${2:-}" ] || { echo "$PROG: --anchor needs a bead id" >&2; exit 2; }
      ANCHOR_ONLY="$2"; shift 2 ;;
    -h|--help) echo "usage: $PROG [--anchor <id>]"; exit 0 ;;
    *) echo "$PROG: unknown argument '$1' (usage: $PROG [--anchor <id>])" >&2; exit 2 ;;
  esac
done

# Guarded reads: non-zero means "could not tell", never "nothing there".
_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
# The sanctioned close with a successor pointer, for a finding carried forward.
REHOME="$_bd_lib_dir/bead-rehome.sh"
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
is_held() { case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac; }

NL='
'

# The origin repository the PR comments are read from, resolved on first use.
ORIGIN_HOST=""; ORIGIN_REPO=""; ORIGIN_READ=""
origin_repo() {
  if [ -z "$ORIGIN_READ" ]; then
    ORIGIN_READ=1
    local u
    u=$(git remote get-url origin </dev/null 2>/dev/null | tr -d '[:space:]')
    case "$u" in
      git@github.com:*|https://github.com/*|ssh://git@github.com/*)
        ORIGIN_HOST="github.com"
        ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
          -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    esac
    case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
  fi
  [ -n "$ORIGIN_REPO" ]
}

# pr_comment_lines <anchor> <anchor-row> — the anchor's PR inline review
# comments as "<comment id>\t<marker>" rows in CMT_ROWS, where the marker is the
# first character of the commented line in its diff hunk: `+` added, `-`
# removed, a space for a line the diff did not change. Read once per anchor.
# Returns 0 read, 1 not readable this pass, 2 the anchor records no PR.
CMT_ANCHOR=""; CMT_ROWS=""; CMT_RC=1
pr_comment_lines() {
  [ "$1" = "$CMT_ANCHOR" ] && return "$CMT_RC"
  CMT_ANCHOR="$1"; CMT_ROWS=""; CMT_RC=1
  local num rows
  num=$(row_meta "$2" pr_number)
  case "$num" in ''|*[!0-9]*) CMT_RC=2; return 2 ;; esac
  origin_repo || return 1
  command -v gh >/dev/null 2>&1 || return 1
  rows=$(gh api --hostname "$ORIGIN_HOST" --paginate "repos/$ORIGIN_REPO/pulls/$num/comments?per_page=100" \
    --jq '.[] | [ (.id | tostring), ((.diff_hunk // "") | split("\n") | last | .[0:1]) ] | @tsv' \
    </dev/null 2>/dev/null) || return 1
  CMT_ROWS="$rows"; CMT_RC=0
  return 0
}

# finding_scope <anchor> <anchor-row> <source> <comment id> <locus file> — sets
# SCOPE to diff (the finding objects to the disposed diff), outlives (it can
# cite code the target branch carries, so it is carried forward), or unread
# (its comment line could not be read this pass), and SCOPE_WHY to the reason
# as one sentence.
finding_scope() {
  local num marker
  SCOPE="diff"; SCOPE_WHY=""
  case "$3" in human:*) : ;; *) SCOPE_WHY="A machine-lane finding objects only to the diff it reviewed."; return 0 ;; esac
  [ -n "$5" ] || { SCOPE_WHY="Its locus names no file, so it objects to the PR as a whole."; return 0; }
  num=$(row_meta "$2" pr_number)
  if [ -z "$4" ]; then
    SCOPE="outlives"
    SCOPE_WHY="It names $5 but records no comment id, so whether the diff changed the line it cites cannot be read."
    return 0
  fi
  pr_comment_lines "$1" "$2"
  case "$?" in
    0) : ;;
    2) SCOPE="outlives"
       SCOPE_WHY="It names $5 but anchor $1 records no PR, so whether the diff changed the line it cites cannot be read."
       return 0 ;;
    *) SCOPE="unread"; return 0 ;;
  esac
  marker=$(printf '%s\n' "$CMT_ROWS" | awk -F'\t' -v c="$4" '$1 == c { print ($2 == "" ? "file" : $2); exit }')
  case "$marker" in
    " ")  SCOPE="outlives"
          SCOPE_WHY="Its comment sits on a line of $5 that PR#$num did not change, so it can cite code the target branch already carries." ;;
    "")   SCOPE_WHY="Its comment is no longer on PR#$num." ;;
    file) SCOPE_WHY="Its comment is on the whole of a file PR#$num changed." ;;
    *)    SCOPE_WHY="Its comment sits on a line PR#$num changed." ;;
  esac
  return 0
}

# carry_forward <finding> <anchor> <disposition> <why> — file the bug bead that
# takes this finding's objection, or find the one an earlier pass filed, then
# close the finding through bead-rehome.sh pointed at it. Returns 0 once the
# finding reads back closed with that pointer, leaving the bug's id in CF_BUG.
carry_forward() {
  local f="$1" a="$2" disp="$3" why="$4" frow rows bug title desc meta crow
  CF_BUG=""
  frow=$(bd_show "$f") || return 1
  rows=$(bd_list --metadata-field "gc.supersedes=$f" --status="$ALL_STATUSES") || return 1
  bug=$(printf '%s' "$rows" | jq -r --arg f "$f" '
    [ .[] | select(((.metadata["gc.supersedes"] // "") | tostring) == $f) | .id ] | .[0] // empty' 2>/dev/null)
  if [ -z "$bug" ]; then
    title=$(row_field "$frow" title | sed -E 's/^finding\[[^]]*\]: //')
    [ -n "$title" ] || title="Review objection carried forward from finding $f"
    desc=$(printf '%s\n\nCarried forward from finding %s when anchor %s was disposed (%s). %s Closing the PR does not answer it, so it stands here as work of its own: judge it against the current target branch, and close it if the code no longer has the problem.' \
      "$(row_field "$frow" description)" "$f" "$a" "$disp" "$why")
    meta=$(jq -nc --arg f "$f" '{"gc.supersedes": $f}')
    bug=$(printf '%s' "$desc" | gc bd create "$title" -t bug --body-file - --deps "discovered-from:$f" \
            --metadata "$meta" --json 2>/dev/null \
          | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
    [ -n "$bug" ] || return 1
  fi
  CF_BUG="$bug"
  [ -x "$REHOME" ] || return 1
  "$REHOME" --origin "$f" --successor "$bug" --kind re-homed --note "$why" </dev/null >/dev/null 2>&1
  crow=$(bd_show "$f") || return 1
  [ "$(row_field "$crow" status | tr '[:upper:]' '[:lower:]')" = "closed" ] \
    && [ "$(row_meta "$crow" gc.superseded_by)" = "$bug" ]
}

# --- the live scaffolding population, in close order ---------------------------
# One row per bead: id, anchor, kind, rebase_hold, and for a finding the source,
# comment id and the file its locus names (the locus up to its first space or
# colon, any #fragment dropped). pr-facts.sh files a human finding's locus as
# `PR review` for a review body, `PR conversation` for a Conversation comment,
# and `<path>[:<line>]` for an inline comment, so the first two, and a finding
# with no Locus line, name no file. Fields are joined by the unit separator,
# not a tab: `read` merges a run of tabs into one delimiter, and an empty middle
# field would shift every field after it. Reworks come first, then findings,
# then validation passes: a fix unit blocks the findings it answers, so closing
# it first means a finding's close is not refused this pass by a rework still
# open. task_kind=review is left to arm 9 and task_kind=visit to the human side,
# so neither is read here. An unreadable enumeration fails loudly rather than
# reporting a false empty, because "could not tell" is never "none".
US=$(printf '\037')
ROW_JQ='.[] | select(((.metadata.task_kind // "") | tostring) == $k)
  | ((.description // "") | tostring | (split("\n")[0] // "")
     | if startswith("Locus: ") then .[7:] else "" end) as $loc
  | [ ((.id // "") | tostring),
      ((.metadata.anchor_bead // "") | tostring),
      $k,
      ((.metadata.rebase_hold // "") | tostring),
      ((.metadata["finding.source"] // "") | tostring),
      ((.metadata["finding.comment_id"] // "") | tostring),
      (if $loc == "PR review" or $loc == "PR conversation" then ""
       else ($loc | capture("^(?<p>[^ \\t:]*)") | .p | sub("#.*$"; "")) end) ]
  | map(gsub("[[:cntrl:]]"; " ")) | join("\u001f")'
CANDS=""
if [ -n "$ANCHOR_ONLY" ]; then
  ROWS=$(bd_list --metadata-field anchor_bead="$ANCHOR_ONLY" --status="$LIVE_STATUSES") || {
    echo "$PROG: could not enumerate the live scaffolding on $ANCHOR_ONLY; nothing swept, retry next pass" >&2
    exit 1
  }
fi
for kind in rework finding validation; do
  if [ -z "$ANCHOR_ONLY" ]; then
    ROWS=$(bd_list --metadata-field task_kind="$kind" --status="$LIVE_STATUSES") || {
      echo "$PROG: could not enumerate live $kind beads; failing loudly rather than reporting a false all-clear" >&2
      exit 1
    }
  fi
  # Sorted by anchor, so the loop reads each anchor, and its PR comments, once.
  rows=$(printf '%s' "$ROWS" | jq -r --arg k "$kind" "$ROW_JQ" 2>/dev/null | LC_ALL=C sort -t "$US" -k2,2)
  [ -n "$rows" ] || continue
  CANDS="${CANDS:+$CANDS$NL}$rows"
done
[ -n "$CANDS" ] || { echo "$PROG: no live scaffolding beads${ANCHOR_ONLY:+ on $ANCHOR_ONLY}"; exit 0; }

swept=0; carried=0; held=0; stuck=0; unread=0
AROW_FOR=""; AROW=""
while IFS="$US" read -r sid anchor kind hold fsrc fcid fpath; do
  [ -n "${sid:-}" ] || continue
  # A scaffolding bead with no anchor_bead cannot be tested against a disposition.
  [ -n "$anchor" ] || { held=$((held + 1)); continue; }

  # One read per run of rows naming the same anchor: each kind's rows are sorted
  # by anchor, and this sweep never writes an anchor.
  if [ "$anchor" != "$AROW_FOR" ]; then
    AROW_FOR="$anchor"
    AROW=$(bd_show "$anchor") || AROW=""
  fi
  if [ -z "$AROW" ]; then
    echo "$PROG: $kind $sid names anchor $anchor, which does not resolve; leaving it open" >&2
    held=$((held + 1)); continue
  fi
  AMR=$(row_meta "$AROW" merge_result)
  # A merged anchor is a landing, never a disposal: its leftover scaffolding is
  # close-answered's, not this sweep's. Skip it even if a disposition marker is
  # somehow also present.
  [ "$AMR" = "merged" ] && { held=$((held + 1)); continue; }

  SUPERSEDED=$(row_meta "$AROW" gc.superseded_by)
  DISP_KIND=$(row_meta "$AROW" gc.pr_close_disposition_kind)
  disposed=""
  [ -n "$SUPERSEDED" ] && disposed="superseded_by=$SUPERSEDED"
  case "$DISP_KIND" in
    re-homed|folded|fixed-upstream|duplicate|not-needed)
      disposed="${disposed:+$disposed, }pr_close_disposition=$DISP_KIND" ;;
  esac
  [ -n "$disposed" ] || { held=$((held + 1)); continue; }

  if is_held "$hold"; then
    echo "$PROG: $kind $sid on disposed anchor $anchor carries rebase_hold; an operator's freeze is theirs to lift, so it is left open" >&2
    held=$((held + 1)); continue
  fi

  scope_note=""
  if [ "$kind" = "finding" ]; then
    finding_scope "$anchor" "$AROW" "$fsrc" "$fcid" "$fpath"
    case "$SCOPE" in
      unread)
        echo "$PROG: finding $sid names $fpath, but anchor $anchor's PR comments could not be read, so whether it outlives the disposed diff is unknown; left for the next pass" >&2
        unread=$((unread + 1)); continue ;;
      outlives)
        if carry_forward "$sid" "$anchor" "$disposed" "$SCOPE_WHY"; then
          carried=$((carried + 1))
          echo "$PROG: carried finding $sid forward to bug $CF_BUG — $SCOPE_WHY"
        else
          echo "$PROG: finding $sid outlives disposed anchor $anchor, but carrying it forward did not read back${CF_BUG:+ (bug $CF_BUG)}; retry next pass — $SCOPE_WHY" >&2
          stuck=$((stuck + 1))
        fi
        continue ;;
    esac
    scope_note=" $SCOPE_WHY"
  fi

  gc bd update "$sid" \
    --set-metadata gc.outcome=moot \
    --append-notes "$PROG: retired as moot. Anchor $anchor is disposed ($disposed; merge_result=${AMR:-unrecorded}), so this $kind tracks a subject that is not landing: it is closed with no verdict and no fix expected, which clears its hold on the anchor's close.$scope_note Machine scaffolding only — any human visits on the anchor are left standing." \
    --status=closed </dev/null >/dev/null 2>&1 || true

  if ! SROW=$(bd_show "$sid"); then
    echo "$PROG: $kind $sid could not be re-read after the close; retry next pass" >&2
    stuck=$((stuck + 1)); continue
  fi
  SSTATUS=$(row_field "$SROW" status | tr '[:upper:]' '[:lower:]')
  SOUTCOME=$(row_meta "$SROW" gc.outcome)
  if [ "$SSTATUS" != "closed" ] || [ "$SOUTCOME" != "moot" ]; then
    echo "$PROG: $kind $sid close did not read back (status='$SSTATUS' gc.outcome='$SOUTCOME'); retry next pass" >&2
    stuck=$((stuck + 1)); continue
  fi
  swept=$((swept + 1))
  echo "$PROG: closed $kind $sid — anchor $anchor is disposed ($disposed)"
done <<CANDS_EOF
$CANDS
CANDS_EOF

# A closed bead leaves the live set, so a same-pass re-read must not be served
# the rows from before these writes. A no-op outside a reconcile pass.
[ $((swept + carried)) -eq 0 ] || bd_cache_clear

echo "$PROG: $swept scaffolding bead(s) closed, $carried finding(s) carried forward, $held left alone, $stuck write(s) held for retry, $unread finding(s) unread"
[ -n "$ANCHOR_ONLY" ] && [ "$unread" -gt 0 ] && exit 3
exit 0
