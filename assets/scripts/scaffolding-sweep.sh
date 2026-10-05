#!/usr/bin/env bash
# scaffolding-sweep — arm 10 of the merge cadence; caller: refinery-reconcile.sh.
# Retires the machine review scaffolding hung on an anchor once that anchor is
# DISPOSED — withdrawn won't-do, or closed not-planned — so a disposed anchor
# can finalize instead of standing "stuck" behind scaffolding that will never
# resolve. The scaffolding is the validation pass, the finding beads, and the
# rework/fix-unit beads (task_kind=validation|finding|rework), each carrying
# anchor_bead=<anchor> and a `blocks` edge onto the anchor or onto a rework that
# blocks it. While any is open the anchor cannot be non-force-closed and
# gate-ensure's quiescence holds its lane, which is the "stuck forever" an
# abandoned or withdrawn anchor otherwise sits in: nothing in the cadence closes
# this scaffolding once the subject stops moving (close-answered keys on a fix
# LANDING, not on a disposal).
#
# What this does NOT touch:
#   - task_kind=review — review-sweep.sh (arm 9) owns a review with no surface.
#   - task_kind=visit — a human conversation. A disposed PR does not moot why it
#     closed or what comes next, and finalize-gate.sh holds the anchor's own
#     close while a visit is open. Human gates and visits are left standing.
#   - the anchor itself — bead-rehome.sh (via pr-facts.sh's close arm) is the one
#     anchor-closer, and finalize-gate holds it while a human visit is owed.
#     Clearing the machine scaffolding here is what lets that close land once the
#     human side is done; this arm never closes an anchor.
#
# The disposed signal is read from the ANCHOR: a non-empty gc.superseded_by (the
# pointer bead-rehome.sh stamps and reads back) or a gc.pr_close_disposition_kind
# (the intent pr-dispose.sh records before the PR closes). Neither is ever
# stamped on a landing, so a merged anchor's leftover scaffolding is out of scope
# (that is finding.sh close-answered's, keyed on the fix landing); a merged
# anchor is skipped explicitly as a backstop.
#
# Findings are closed before the reworks they block, so a rework's close is not
# refused by a finding still open in the same pass; anything left blocked is
# reported and retried next pass. A claimed scaffolding bead is swept too: on a
# disposed anchor its holder has nothing left to produce. Closes are read back;
# a close that does not stick is held for retry, never counted.
#
# Reads anchors, writes only scaffolding beads: gc.outcome=moot, the reason
# appended to notes, status closed, all read back.
# Exits: 0 pass completed · 1 an enumeration could not be read (nothing swept).
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

# Guarded reads: non-zero means "could not tell", never "nothing there".
_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
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

NL='
'

# --- the live scaffolding population, findings first --------------------------
# Three reads, concatenated in close order: a finding blocks the rework that
# answers it, so closing findings before reworks means a rework's close is not
# refused this pass by a finding still open. task_kind=review is left to arm 9
# and task_kind=visit to the human side, so neither is read here. An unreadable
# enumeration fails loudly rather than reporting a false empty, because "could
# not tell" is never "none".
CANDS=""
for kind in finding rework validation; do
  ROWS=$(bd_list --metadata-field task_kind="$kind" --status="$LIVE_STATUSES") || {
    echo "$PROG: could not enumerate live $kind beads; failing loudly rather than reporting a false all-clear" >&2
    exit 1
  }
  rows=$(printf '%s' "$ROWS" | jq -r --arg k "$kind" '
    .[] | [ ((.id // "") | tostring),
            ((.metadata.anchor_bead // "") | tostring),
            $k ] | @tsv' 2>/dev/null)
  [ -n "$rows" ] || continue
  CANDS="${CANDS:+$CANDS$NL}$rows"
done
[ -n "$CANDS" ] || { echo "$PROG: no live scaffolding beads"; exit 0; }

swept=0; held=0; stuck=0
while IFS=$'\t' read -r sid anchor kind; do
  [ -n "${sid:-}" ] || continue
  # A scaffolding bead with no anchor_bead cannot be tested against a disposition.
  [ -n "$anchor" ] || { held=$((held + 1)); continue; }

  if ! AROW=$(bd_show "$anchor"); then
    echo "$PROG: $kind $sid names anchor $anchor, which does not resolve; leaving it open" >&2
    held=$((held + 1)); continue
  fi
  AMR=$(row_meta "$AROW" merge_result)
  # A merged anchor is a landing, never a disposal: its leftover scaffolding is
  # close-answered's, not this arm's. Skip it even if a disposition marker is
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

  gc bd update "$sid" \
    --set-metadata gc.outcome=moot \
    --append-notes "$PROG: retired as moot. Anchor $anchor is disposed ($disposed; merge_result=${AMR:-unrecorded}), so this $kind tracks a subject that is not landing: it is closed with no verdict and no fix expected, which clears its hold on the anchor's close. Machine scaffolding only — any human visits on the anchor are left standing." \
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

echo "$PROG: $swept scaffolding bead(s) closed, $held left alone, $stuck write(s) held for retry"
exit 0
