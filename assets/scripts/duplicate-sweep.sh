#!/usr/bin/env bash
# duplicate-sweep — arm 11 of the merge cadence; caller: refinery-reconcile.sh.
# Closes the duplicates that are provably safe to close and leaves every other
# bead exactly where it is. Two detections find them:
#   - a `duplicate_of` marker. A polecat that diagnoses a duplicate dispatch
#     stamps the marker and parks the bead, because polecats never close work
#     beads; without a reader the bead sits open until a human rules on it, one
#     at a time.
#   - a never-dispatched rework twin: an open rework child for a review whose
#     work another child of the same review already carried and landed. The twin
#     blocks its anchor, so merge.sh and gate-ensure's quiescence hold the
#     anchor on work nothing will ever run, and no other arm closes it:
#     scaffolding-sweep retires only a disposed anchor's scaffolding, and
#     finding.sh close-answered closes only findings.
# Disposal goes through bead-rehome.sh --kind duplicate, which is the one
# writer for a successor pointer: it stamps gc.superseded_by + _store, reads
# them back, and closes only if they stuck. Nothing here writes a close.
# Neither detection trusts a recorded fact on its own, so every gate below
# re-establishes one from the store, and an untested condition is never a
# satisfied one. Each detection's gates are listed above its pass.
# Reads every bead named, writes only the beads it disposes. No merge
# authority, no branch touched, no PR touched.
# Exits: 0 every enumeration was read · 1 an enumeration could not be read
# (that pass swept nothing; the other still ran). A refused close is reported,
# not retried: bead-rehome leaves the bead open, pointed and findable, which is
# the designed partial state.
set -u

PROG="duplicate-sweep"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REHOME="${DUPLICATE_SWEEP_REHOME:-$SCRIPTS_DIR/bead-rehome.sh}"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# in_progress is deliberately absent: a bead someone is holding is being
# judged right now, and this arm is not the judge.
LIVE_STATUSES="open,blocked,deferred,hooked,pinned"
ALL_STATUSES="open,in_progress,blocked,deferred,hooked,pinned,closed"

# Guarded reads: non-zero means "could not tell", never "nothing there".
_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
# </dev/null on every call inside the candidate loops: each loop is fed by a
# heredoc, and a child inheriting its stdin would consume the rows behind it.
bd_show() {
  local raw
  raw=$(gc bd show "$1" --json </dev/null 2>/dev/null | scrub)
  printf '%s' "$raw" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
row_field() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0][$k] // "") | tostring' 2>/dev/null; }
row_meta()  { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }

# poured <id> — the first convoy tracking <id>, empty when none. A graph.v2 pour
# mints a convoy that tracks the bead it pours over, and that edge outlives the
# metadata the pour stamps. Non-zero = the edges could not be read.
poured() {
  local raw
  raw=$(gc bd dep list "$1" --direction=up -t tracks --json </dev/null 2>/dev/null) || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw" | jq -r '
    [ .[] | select(((.issue_type // .type // "") | tostring) == "convoy") | .id ]
    | (.[0] // empty)' 2>/dev/null
}

if [ ! -x "$REHOME" ]; then
  echo "$PROG: no executable $REHOME — the disposal writer is the whole arm; sweeping nothing" >&2
  exit 0
fi

# This rig's own store ref, for the cross-store skip below. Unset means every
# duplicate_of_store reads as foreign, which errs toward leaving beads alone.
SELF_STORE="rig:${GC_RIG:-}"

disposed=0; held=0; stuck=0; unread=0
# Both loops are fed by a heredoc, not a pipe, so they run in this shell and
# the counters they touch are the ones reported at the end.
hold() { held=$((held + 1)); echo "$PROG: leaving $id alone — $1"; }

# dispose <id> <successor> <why> — the one disposal both passes share. <why> is
# the verified reason; it rides into the close reason and the report line.
# Returns non-zero when the disposal did not read back.
dispose() {
  local DROW DSTATUS DSUCC
  "$REHOME" --origin "$1" --successor "$2" --kind duplicate \
    --note "verified by $PROG: $3" </dev/null >/dev/null 2>&1 || true

  # bead-rehome gates its own close on the pointer read-back; this is the
  # arm's independent confirmation that the disposal actually landed.
  if ! DROW=$(bd_show "$1"); then
    echo "$PROG: $1 could not be re-read after the disposal; retry next pass" >&2
    stuck=$((stuck + 1)); return 1
  fi
  DSTATUS=$(row_field "$DROW" status | tr '[:upper:]' '[:lower:]')
  DSUCC=$(row_meta "$DROW" gc.superseded_by)
  if [ "$DSTATUS" != "closed" ] || [ "$DSUCC" != "$2" ]; then
    echo "$PROG: $1 was NOT disposed (status='$DSTATUS' gc.superseded_by='${DSUCC:-}'); bead-rehome leaves it open, pointed and findable — judge the refusal, it is not retried" >&2
    stuck=$((stuck + 1)); return 1
  fi
  disposed=$((disposed + 1))
  echo "$PROG: closed $1 as a duplicate of $2 — $3"
  # The bead left every live population; a cached listing must not show it open.
  bd_cache_clear
}

# --- the live duplicate-marked population ------------------------------------
# The stamp alone never justifies a close — it records a diagnosis that may be
# hours old:
#   - the named successor RESOLVES, and is closed or records work_outcome
#     shipped: a pointer to a bead that does not exist reads as a resolved
#     disposition and resolves to nothing;
#   - the duplicate recorded NO WORK, proved one of two positive ways —
#     work_outcome=no-op (the polecat's own statement), or no work-product key
#     at all (branch, work_dir, pr_number, pr_url, merge_result, work_commit).
#     Any other outcome refuses under both. Absence of an outcome is not a
#     no-op, which is why the structural arm tests keys rather than assuming;
#   - nobody else owns it: no assignee, not a review bead (signoff.sh and
#     review-sweep close those), not a step bead or workflow root.
# "No work" cannot be tested as "metadata.branch is absent": on a rebase or
# rework dispatch that field names the TWIN's branch, so most verified no-op
# duplicates carry one. The no-op stamp is what says nothing was pushed.
# A successor whose stamped store is not this rig is skipped, not guessed at.
# The skip is keyed on that stamp rather than on the read failing: `gc bd show`
# resolves a foreign id by searching every store, so a hit answers from
# whichever store holds it while a miss answers from the ambient one.
# A bead carrying a hold_reason is disposable — the hold parks a BRANCH, and
# nothing here moves one — but the close reason says a hold was standing, so a
# deliberate park is never retired silently.
CANDS=""
if ! ROWS=$(bd_list --has-metadata-key duplicate_of --status="$LIVE_STATUSES"); then
  echo "$PROG: could not enumerate duplicate-marked beads; failing loudly rather than reporting a false all-clear" >&2
  unread=1
else
  # Every field carries a "-" placeholder when empty: TAB is IFS whitespace, so
  # an empty column would collapse and shift every later one left.
  CANDS=$(printf '%s' "$ROWS" | jq -r '
    def p: if . == null or (. | tostring) == "" then "-" else (. | tostring) end;
    ["branch","work_dir","gc.work_dir","pr_number","pr_url","merge_result","gc.work_commit"] as $work
    | .[]
    | (.metadata // {}) as $m
    | [ ((.id // "") | p),
        ($m["duplicate_of"] | p),
        ($m["duplicate_of_store"] | p),
        (($m["gc.work_outcome"] // $m["work_outcome"]) | p),
        (if ([ $work[] as $k | ($m[$k] // "") | tostring | select(. != "") ] | length) > 0
           then "work" else "none" end),
        (.assignee | p),
        ($m["task_kind"] | p),
        (if (($m["gc.step_ref"] // $m["gc.step_id"] // "") | tostring) != "" or (($m["gc.kind"] // "") | tostring) == "workflow"
           then "step" else "-" end),
        (($m["gc.superseded_by"] // $m["superseded_by"]) | p),
        (if (($m["hold_reason"] // "") | tostring) != "" then "held" else "-" end) ]
    | @tsv' 2>/dev/null)
  [ -n "$CANDS" ] || echo "$PROG: no live duplicate-marked beads"
fi

while IFS=$'\t' read -r id dup_of dup_store outcome workkeys assignee task_kind is_step prior held_flag; do
  [ -n "${id:-}" ] && [ "$id" != "-" ] || continue
  [ "$dup_of" != "-" ] || { hold "duplicate_of is present but names no successor"; continue; }
  [ "$dup_of" != "$id" ] || { hold "duplicate_of names the bead itself"; continue; }
  [ "$assignee" = "-" ] || { hold "it is assigned to $assignee, who is judging it"; continue; }
  [ "$task_kind" != "review" ] || { hold "it is a review bead; signoff.sh and review-sweep close those"; continue; }
  [ "$is_step" != "step" ] || { hold "it is a step bead or workflow root, not a work bead"; continue; }
  if [ "$prior" != "-" ] && [ "$prior" != "$dup_of" ]; then
    hold "it already records a successor pointer to $prior, which is somebody else's disposition"; continue
  fi
  if [ "$dup_store" != "-" ] && [ "$dup_store" != "$SELF_STORE" ]; then
    hold "its successor $dup_of lives in $dup_store, which this pass cannot read"; continue
  fi

  # No work, proved positively. WHY records which arm proved it, because the
  # two are not equally strong and the close reason should say which one ran.
  case "$outcome" in
    no-op) WHY="work_outcome=no-op" ;;
    -)
      [ "$workkeys" = "none" ] || { hold "it records no work_outcome and carries work-product metadata"; continue; }
      WHY="no branch, worktree, PR or merge_result was ever recorded on it" ;;
    *) hold "it records work_outcome=$outcome, which is not a no-op"; continue ;;
  esac

  if ! SROW=$(bd_show "$dup_of"); then
    hold "its successor $dup_of does not resolve in this store"; continue
  fi
  SSTATUS=$(row_field "$SROW" status | tr '[:upper:]' '[:lower:]')
  SOUTCOME=$(row_meta "$SROW" gc.work_outcome)
  [ -n "$SOUTCOME" ] || SOUTCOME=$(row_meta "$SROW" work_outcome)
  if [ "$SSTATUS" = "closed" ]; then
    SWHY="$dup_of is closed"
    SMR=$(row_meta "$SROW" merge_result)
    [ -n "$SMR" ] && SWHY="$SWHY (merge_result=$SMR)"
  elif [ "$SOUTCOME" = "shipped" ]; then
    SWHY="$dup_of is $SSTATUS and records work_outcome=shipped"
  else
    hold "its successor $dup_of is $SSTATUS and has not shipped"; continue
  fi

  WHY="$SWHY, and $WHY"
  [ "$held_flag" = "held" ] && WHY="$WHY; it was parked under a hold_reason, which stays on the bead"
  dispose "$id" "$dup_of" "$WHY"
done <<CANDS_EOF
$CANDS
CANDS_EOF

# --- never-dispatched rework twins --------------------------------------------
# signoff.sh files a rework child per review, stamped with that review's id in
# source_review_bead, and dispatches it with a mol-polecat-work pour. A second
# child for the same review that was never dispatched is a duplicate of the one
# that was, once that one has landed. No marker says so, so each gate below
# re-establishes it:
#   - the population is the OPEN task_kind=rework children naming a
#     source_review_bead whose metadata records no dispatch: unassigned, and no
#     route, deferred dispatch, claim, worktree, commit, prepare or outcome. A
#     child carrying any of those is in flight or done, not a twin, so it is
#     not read further. A duplicate_of marker leaves it to the marker pass;
#   - it names an anchor_bead, and no hold_reason parks it (a park is
#     somebody's judgement in progress);
#   - no convoy tracks it. A pour mints one, and that edge survives what the
#     metadata does not, such as a hold that clears gc.execution_routed_to or a
#     pour whose route stamp never read back. With the metadata, this is the
#     second, independent proof that it was never dispatched;
#   - its review is CLOSED. close_review is signoff.sh's last write, so no
#     request-changes pass is left that could adopt and dispatch the twin while
#     this arm closes it;
#   - a sibling LANDED: another rework child naming the same review and the
#     same anchor, never disposed itself (no successor pointer, no
#     duplicate_of), recording no outcome but shipped (scaffolding-sweep's
#     gc.outcome=moot is a retirement, not a landing), and dispatched, by its
#     metadata or by a convoy tracking it. It either records
#     work_outcome=shipped or is closed with its rejection_reason gone:
#     signoff.sh stamps that field on every child, and the refinery's landing
#     transition unsets it, so a closed child still carrying it was closed
#     without landing. A closed child that was never dispatched is another
#     twin, not a landing.
# The branch, target and PR fields are the work order signoff.sh stamps on
# every child, naming the anchor's branch and PR, so they say nothing about
# what this child did and are not read. Closing the twin releases its blocks
# edge onto the anchor: merge.sh and gate-ensure count only a live blocker.
TWINS=""
if ! RROWS=$(bd_list --metadata-field task_kind=rework --status=open); then
  echo "$PROG: could not enumerate open rework children; failing loudly rather than reporting a false all-clear" >&2
  unread=1
else
  TWINS=$(printf '%s' "$RROWS" | jq -r '
    def p: if . == null or (. | tostring) == "" then "-" else (. | tostring) end;
    def s($k): ((.metadata // {})[$k] // "") | tostring;
    [ "gc.routed_to", "gc.execution_routed_to", "gc.dispatch_when_ready",
      "gc.dispatch_when_ready_slung", "gc.deferred_routed_to",
      "gc.deferred_execution_routed_to", "gc.deferred_assignee",
      "gc.claimed_at", "gc.session_id", "gc.session_name",
      "work_dir", "gc.work_dir", "gc.work_commit", "self_review_passed_sha",
      "prepare_mode", "merge_result", "gc.work_outcome", "work_outcome" ] as $dispatch
    | .[]
    | . as $row
    | select(s("task_kind") == "rework" and s("source_review_bead") != "")
    | select(s("duplicate_of") == "")
    | select(((.assignee // "") | tostring) == "")
    | select([ $dispatch[] as $k | $row | s($k) | select(. != "") ] | length == 0)
    | (.metadata // {}) as $m
    | [ ((.id // "") | p),
        ($m["source_review_bead"] | p),
        ($m["anchor_bead"] | p),
        (if s("hold_reason") != "" then "held" else "-" end),
        (($m["gc.superseded_by"] // $m["superseded_by"]) | p) ]
    | @tsv' 2>/dev/null)
  [ -n "$TWINS" ] || echo "$PROG: no open rework child is undispatched"
fi

while IFS=$'\t' read -r id review anchor held_flag prior; do
  [ -n "${id:-}" ] && [ "$id" != "-" ] || continue
  [ "$anchor" != "-" ] || { hold "it names no anchor_bead, so no sibling can be matched to its anchor"; continue; }
  [ "$held_flag" = "-" ] || { hold "it is parked under a hold_reason, which is somebody's judgement in progress"; continue; }

  if ! CONVOY=$(poured "$id"); then
    hold "what tracks it could not be read, so a pour over it cannot be ruled out"; continue
  fi
  [ -z "$CONVOY" ] || { hold "convoy $CONVOY tracks it, so a molecule was poured over it"; continue; }

  if ! RVROW=$(bd_show "$review"); then
    hold "its review $review does not resolve in this store"; continue
  fi
  RVSTATUS=$(row_field "$RVROW" status | tr '[:upper:]' '[:lower:]')
  [ "$RVSTATUS" = "closed" ] || { hold "its review $review is ${RVSTATUS:-unreadable}, so signoff.sh may still adopt and dispatch it"; continue; }

  # The landed siblings, earliest-filed first, one TSV row each: the id, the
  # metadata that proves its dispatch ("-" when only a convoy could, probed
  # below), and how it landed.
  if ! SIBROWS=$(bd_list --metadata-field source_review_bead="$review" --status="$ALL_STATUSES"); then
    hold "the other children of review $review could not be read"; continue
  fi
  LANDED=$(printf '%s' "$SIBROWS" | jq -r --arg self "$id" --arg r "$review" --arg a "$anchor" '
    def s($k): ((.metadata // {})[$k] // "") | tostring;
    [ .[]
      | select((.id // "") != $self)
      | select(s("task_kind") == "rework" and s("source_review_bead") == $r and s("anchor_bead") == $a)
      | select(s("gc.superseded_by") == "" and s("superseded_by") == "" and s("duplicate_of") == "")
      | select(s("gc.outcome") == "")
      | (if s("gc.work_outcome") != "" then s("gc.work_outcome") else s("work_outcome") end) as $wo
      | select($wo == "" or $wo == "shipped")
      | select($wo == "shipped"
               or ((((.status // "") | ascii_downcase) == "closed") and s("rejection_reason") == ""))
      | { id, created_at: (.created_at // ""),
          evidence: (if $wo == "shipped" then "work_outcome=shipped"
                     elif s("gc.execution_routed_to") != "" then "gc.execution_routed_to=" + s("gc.execution_routed_to")
                     elif s("work_dir") != "" then "work_dir"
                     elif s("gc.work_dir") != "" then "gc.work_dir"
                     else "-" end),
          how: (if $wo == "shipped" then "shipped" else "closed" end) } ]
    | sort_by([.created_at, .id])
    | .[] | [.id, .evidence, .how] | @tsv' 2>/dev/null)

  # A pointer this arm stamped on an earlier pass whose close was refused names
  # the sibling to finish with; any other pointer is somebody else's call.
  SUCC=""; SEVID=""; SHOW=""
  while IFS=$'\t' read -r sib evidence how; do
    [ -n "${sib:-}" ] || continue
    if [ "$prior" != "-" ] && [ "$sib" != "$prior" ]; then continue; fi
    if [ "$evidence" = "-" ]; then
      SCONVOY=$(poured "$sib") || continue
      [ -n "$SCONVOY" ] || continue
      evidence="convoy $SCONVOY tracks it"
    fi
    SUCC="$sib"; SEVID="$evidence"; SHOW="$how"; break
  done <<LANDED_EOF
$LANDED
LANDED_EOF
  if [ -z "$SUCC" ]; then
    if [ "$prior" != "-" ]; then
      hold "it already records a successor pointer to $prior, which is not a landed child of review $review"
    else
      hold "no other child of review $review on anchor $anchor has landed"
    fi
    continue
  fi

  if [ "$SHOW" = "shipped" ]; then
    SWHY="$SUCC answers the same review $review on anchor $anchor and records work_outcome=shipped"
  else
    SWHY="$SUCC answers the same review $review on anchor $anchor, was dispatched ($SEVID) and is closed"
  fi
  dispose "$id" "$SUCC" "$SWHY, and $id was never dispatched: no route, claim, worktree or outcome recorded, no convoy tracks it, and review $review is closed" \
    || continue
  # The twin keeps the anchor's branch, and pr-stack.sh lists every row on a
  # branch in the PR body unless it carries duplicate_of or a no-op outcome.
  # The marker goes on only after the close read back, so a refused close never
  # leaves a marked twin that the marker pass would hold for its branch.
  gc bd update "$id" --set-metadata "duplicate_of=$SUCC" </dev/null >/dev/null 2>&1 || true
  if ! DROW=$(bd_show "$id") || [ "$(row_meta "$DROW" duplicate_of)" != "$SUCC" ]; then
    echo "$PROG: $id is disposed, but duplicate_of=$SUCC did not stick; pr-stack.sh lists it on its anchor's branch until that is stamped by hand" >&2
  fi
done <<TWINS_EOF
$TWINS
TWINS_EOF

echo "$PROG: $disposed duplicate(s) disposed, $held left alone, $stuck write(s) held for retry"
exit "$unread"
