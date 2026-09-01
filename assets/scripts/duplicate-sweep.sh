#!/usr/bin/env bash
# duplicate-sweep — arm 7 of the merge cadence; caller: refinery-reconcile.sh.
# Gives `duplicate_of` a reader. A polecat that diagnoses a duplicate dispatch
# stamps the marker and parks the bead, because polecats never close work
# beads; without a reader the bead sits open until a human rules on it, one at
# a time. This arm disposes of the ones that are provably safe and leaves the
# rest exactly where they are.
# Disposal goes through bead-rehome.sh --kind duplicate, which is the one
# writer for a successor pointer: it stamps gc.superseded_by + _store, reads
# them back, and closes only if they stuck. Nothing here writes a close.
# The stamp alone never justifies a close — it records a diagnosis that may be
# hours old — so every gate below re-establishes a fact rather than trusting
# one, and an untested condition is never a satisfied one:
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
# A successor in another store is skipped, not guessed at: `gc bd` reads this
# rig only, so its status is unestablished here.
# A bead carrying a hold_reason is disposable — the hold parks a BRANCH, and
# nothing here moves one — but the close reason says a hold was standing, so a
# deliberate park is never retired silently.
# Reads every bead named, writes only duplicate-marked ones. No merge
# authority, no branch touched, no PR touched.
# Exits: 0 pass completed · 1 the enumeration could not be read (swept
# nothing). A refused close is reported, not retried: bead-rehome leaves the
# bead open, pointed and findable, which is the designed partial state.
set -u

PROG="duplicate-sweep"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REHOME="${DUPLICATE_SWEEP_REHOME:-$SCRIPTS_DIR/bead-rehome.sh}"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

# in_progress is deliberately absent: a bead someone is holding is being
# judged right now, and this arm is not the judge.
LIVE_STATUSES="open,blocked,deferred,hooked,pinned"

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

if [ ! -x "$REHOME" ]; then
  echo "$PROG: no executable $REHOME — the disposal writer is the whole arm; sweeping nothing" >&2
  exit 0
fi

# This rig's own store ref, for the cross-store skip below. Unset means every
# duplicate_of_store reads as foreign, which errs toward leaving beads alone.
SELF_STORE="rig:${GC_RIG:-}"

# --- the live duplicate-marked population ------------------------------------
ROWS=$(bd_list --has-metadata-key duplicate_of --status="$LIVE_STATUSES") || {
  echo "$PROG: could not enumerate duplicate-marked beads; failing loudly rather than reporting a false all-clear" >&2
  exit 1
}
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
[ -n "$CANDS" ] || { echo "$PROG: no live duplicate-marked beads"; exit 0; }

disposed=0; held=0; stuck=0
# The loop is fed by a heredoc, not a pipe, so it runs in this shell and the
# counters this touches are the ones reported at the end.
hold() { held=$((held + 1)); echo "$PROG: leaving $id alone — $1"; }

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

  NOTE="verified by $PROG: $SWHY, and $WHY"
  [ "$held_flag" = "held" ] && NOTE="$NOTE; it was parked under a hold_reason, which stays on the bead"
  "$REHOME" --origin "$id" --successor "$dup_of" --kind duplicate \
    --note "$NOTE" </dev/null >/dev/null 2>&1 || true

  # bead-rehome gates its own close on the pointer read-back; this is the
  # arm's independent confirmation that the disposal actually landed.
  if ! DROW=$(bd_show "$id"); then
    echo "$PROG: $id could not be re-read after the disposal; retry next pass" >&2
    stuck=$((stuck + 1)); continue
  fi
  DSTATUS=$(row_field "$DROW" status | tr '[:upper:]' '[:lower:]')
  DSUCC=$(row_meta "$DROW" gc.superseded_by)
  if [ "$DSTATUS" != "closed" ] || [ "$DSUCC" != "$dup_of" ]; then
    echo "$PROG: $id was NOT disposed (status='$DSTATUS' gc.superseded_by='${DSUCC:-}'); bead-rehome leaves it open, pointed and findable — judge the refusal, it is not retried" >&2
    stuck=$((stuck + 1)); continue
  fi
  disposed=$((disposed + 1))
  echo "$PROG: closed $id as a duplicate of $dup_of — $SWHY, and $WHY"
done <<CANDS_EOF
$CANDS
CANDS_EOF

echo "$PROG: $disposed duplicate(s) disposed, $held left alone, $stuck write(s) held for retry"
exit 0
