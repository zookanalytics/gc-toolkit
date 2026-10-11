#!/usr/bin/env bash
# pre-open-rebase — arm 5 of the merge cadence: the conflict observer for
# pre_open_gate anchors. Caller: refinery-reconcile.sh.
#
# A pre-open anchor has no PR, so GitHub can answer nothing about it. Every
# conflict arm in the cadence reads `mergeable`/`mergeStateStatus` off a PR that
# does not exist yet, and pr-facts.sh skips any anchor whose `pr_number` is
# absent before it reads anything else. The result is not a narrow enumeration
# that could be widened: widening one routes zero children, because the facts
# those arms dispatch on are PR facts. A pre-open anchor whose branch has gone
# stale therefore gets no merge-in child at all, while an otherwise identical
# pull_request anchor gets one.
#
# This arm asks git the question GitHub cannot yet be asked — does the recorded
# branch still merge into its target — and on a conflict files ONE merge-in child
# per branch to the fix pool, the same child pr-facts.sh's CONFLICTING arm files
# for a PR anchor. ONE fetch per pass mirrors every branch into a private ref
# namespace; per anchor, both sides must resolve there before
# `git merge-tree --write-tree` is asked anything.
# CLEAN records nothing; CONFLICT files, adopts or re-routes one child that brings
# the branch current by MERGE — no branch shape is rebased or force-pushed —
# stamped prepare_mode=merge and counted as dispatched only once that stamp AND
# the route read back.
#
# Same vetoes as pr-facts.sh: an operator merge_hold or rebase_hold on the
# anchor, a rebase_hold on any bead naming the branch, and a live demand
# (rebasing is one horn of what a demand asks, so performing it answers the
# person's question by fait accompli). And the same supersession guard: a
# branch whose conflict is a landed change deleting or rewriting the code it
# edits gets the operator's decision instead of a child (branch-supersession.sh).
#
# Dedup is shared with pr-facts.sh by construction rather than by bookkeeping:
# both arms probe children on `metadata.branch`, and the `rejection_reason`
# written here names `head <oid>` in the phrasing that arm matches. Whichever
# arm sees the branch first files, and the other stands down — a live child on
# the branch already owns the rewrite, and a second would race it.
#
# Args: --fix-pool <pool> [--deadline <epoch-secs>] [--cursor <file>]. The
# pacing pair walks the anchors in a rotation and starts none past the deadline
# (pace-lib.sh), so the next pass resumes where this one stopped.
# Exits: 0, including where nothing could be observed; 1 only when the anchor
# enumeration itself is unreadable, which is the one state that would otherwise
# report a false all-clear. NOT set -e: anchors are independent.
set -u

PROG="pre-open-rebase"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

FIX_POOL=""; DEADLINE=""; CURSOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix-pool) FIX_POOL="${2:-}"; shift 2 ;;
    --deadline) DEADLINE="${2:-}"; shift 2 ;;
    --cursor)   CURSOR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# Where the probe parks the branch tips it compares. Its own namespace, so
# nothing here can move a branch or a remote-tracking ref; the same device
# merge.sh uses for its seed-audit merge gate.
GATE_REF="refs/gc-toolkit/pre-open-rebase"
# Tells a branch a landed change made moot from one that only drifted.
SUPERSESSION="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/branch-supersession.sh"

# The target an anchor that records none lands on, derived per rig from
# origin/HEAD so a rig whose default branch is not `main` gets its own.
DEFAULT_BRANCH="${PR_OPEN_DEFAULT_BRANCH:-}"
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
fi
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="main"

is_held() { case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac; }

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
ALL_STATUSES="$LIVE_STATUSES,closed"

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=pace-lib.sh
. "$_bd_lib_dir/pace-lib.sh" || { echo "cannot source pace-lib.sh beside this script" >&2; exit 1; }

# >>> takeaway-hold-discriminator
# Whether a person still owes an answer on this anchor. `gc.takeaway` cannot
# say: it is one field a sitting stamps when it begins and REPLACES with its
# outcome when it signs off, and nothing clears it, so its presence dates the
# last sitting instead of naming a live wait. Read as a hold, it parks an
# anchor from its first conversation onward.
#
# The wait itself is a human gate. `gc-helm.sh demand` files what a person
# owes as a native gate (issue_type=gate, await_type=human) stamped
# gc.demand_for=<anchor> and blocking the anchor on it, and a sitting resolves
# that gate (gc bd gate resolve) with the ruling that answers it. A live
# demand is a live hold; none, and the takeaway records a sitting that ended.
#
# Only demands count. Rework children and `--waiting-on` edges are work in
# flight, which the merge already holds on, and reading `blocks` at large would
# restore the same permanence one indirection out. The `held` lifecycle state
# is not read either: it is entered only from `unanchored`.
#
# demand_gate_state reads the demand ledger for an anchor in three:
#   0  a live demand holds the anchor
#   1  the ledger read cleanly and no demand holds
#   2  the ledger would not read — the list failed or returned a non-array
# gc.demand_for names the demand's anchor.
demand_gate_state() { # <anchor-id>
  local rows
  # --include-gates: the demand is a human gate (issue_type=gate), which
  # `bd list` hides by default; without it a held anchor reads released.
  rows=$(bd_list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --include-gates --metadata-field "gc.demand_for=${1:-}") || return 2
  printf '%s' "$rows" | jq -e --arg a "${1:-}" \
    '[ .[] | select(((.metadata["gc.demand_for"] // "") | tostring) == $a) ] | length > 0' \
    >/dev/null 2>&1 && return 0
  return 1
}
# Fails CLOSED — a ledger that will not read answers "held", because releasing an
# anchor a person is holding hands their decision back to a pool.
takeaway_is_holding() { # <anchor-id>; 0 = a person owes an answer here
  local st; demand_gate_state "${1:-}"; st=$?
  [ "$st" -ne 1 ]
}
# <<< takeaway-hold-discriminator

# --- enumerate ------------------------------------------------------------------
ANCHORS=$(bd_list --status=open --metadata-field merge_result=pre_open_gate) || {
  echo "$PROG: could not enumerate pre-open anchors; failing loudly rather than reporting a false all-clear" >&2
  exit 1
}
[ "$ANCHORS" != "[]" ] || { echo "$PROG: no pre-open anchors"; exit 0; }

# --- one fetch for the whole pass -----------------------------------------------
# A fetch costs one network round trip whatever it carries: the same 1.5s for two
# refspecs as for every branch in the repository. Fetching per anchor would spend
# that once per anchor, and this arm runs inside the cadence's single-flight lock,
# so that time is merge latency for the whole queue. One glob refspec instead.
# --prune is what keeps it honest: without it a branch deleted on origin keeps its
# ref here and the probe compares a commit nobody can push to. The glob also
# removes the failure mode a list of named refspecs has, where one branch that is
# gone fails the whole fetch and nothing at all is observed.
if ! git fetch --prune --quiet --no-tags origin "+refs/heads/*:$GATE_REF/heads/*" 2>/dev/null; then
  echo "$PROG: could not fetch origin; NO anchor was observed this pass, which is not the same as none needing a rebase" >&2
  exit 1
fi

total=$(printf '%s' "$ANCHORS" | jq 'length' 2>/dev/null)
reworked=0; clean=0; held=0; skipped=0
pace_start "$CURSOR" "$DEADLINE"
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  branch=$(printf '%s' "$row" | jq -r '.metadata.branch // empty')
  target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // .metadata.target // empty')
  [ -n "$target" ] || target="$DEFAULT_BRANCH"
  hold=$(printf '%s' "$row" | jq -r '.metadata.merge_hold // ""')
  rhold=$(printf '%s' "$row" | jq -r '.metadata.rebase_hold // ""')
  if [ -z "$id" ] || [ -z "$branch" ]; then skipped=$((skipped + 1)); continue; fi
  pace_visit rest "$id"; case $? in 1) continue ;; 2) break ;; esac

  # --- observe: does this branch still merge into its target? --------------------
  # Both sides are read out of the namespace the pass fetch filled, so the
  # comparison is between the two remote tips and never between a checkout
  # lagging its own default branch and anything else.
  head_oid=$(git rev-parse --verify --quiet "$GATE_REF/heads/$branch" 2>/dev/null)
  base_oid=$(git rev-parse --verify --quiet "$GATE_REF/heads/$target" 2>/dev/null)
  # Nothing is probed until both sides resolve. `git merge-tree` exits 1 for a
  # ref it cannot resolve ("not something we can merge") exactly as it does for a
  # conflict, so on the exit status alone a branch someone deleted is a permanent
  # conflict, and this arm would file it a merge-in child every pass for a branch
  # that is not there. Since the pass fetch is a glob, a branch that is gone
  # reaches here as a missing ref rather than as a failed fetch, and this is the
  # only thing standing between that and a bogus dispatch. It also supplies
  # head_oid, which the dedup below matches on and the work order names.
  if [ -z "$head_oid" ] || [ -z "$base_oid" ]; then
    echo "$PROG: $id branch '$branch' or target '$target' is not on origin; nothing observed" >&2
    skipped=$((skipped + 1)); continue
  fi
  mt_rc=0
  git merge-tree --write-tree "$GATE_REF/heads/$target" "$GATE_REF/heads/$branch" >/dev/null 2>&1 || mt_rc=$?
  case "$mt_rc" in
    0) clean=$((clean + 1)); continue ;;
    1) : ;;   # conflict — the arm below
    *) # unrelated histories (128), or a git with no `merge-tree --write-tree`
       # (2.38). Neither is a conflict, and reporting one would dispatch a
       # merge-in child against a question that was never answered.
       echo "$PROG: $id merge-tree could not compare '$branch' against '$target' (rc=$mt_rc); nothing observed" >&2
       skipped=$((skipped + 1)); continue ;;
  esac

  # --- CONFLICT: file ONE merge-in child per branch to the fix pool --------------
  if is_held "$hold" || is_held "$rhold"; then
    echo "$PROG: $id — '$branch' conflicts with '$target' but a hold is set (operator gate); no rework dispatched"
    held=$((held + 1)); continue
  fi
  if takeaway_is_holding "$id"; then
    echo "$PROG: $id — '$branch' conflicts with '$target' but an open demand holds it for a person's decision; no rework dispatched"
    held=$((held + 1)); continue
  fi
  if [ -z "$FIX_POOL" ]; then
    echo "$PROG: $id — '$branch' conflicts with '$target' but no fix pool is configured; the anchor stays stale (operator must repair)" >&2
    skipped=$((skipped + 1)); continue
  fi

  # --- HOW the branch is brought current before the anchor opens its PR. --------
  # >>> pre-open-dispatch-mode
  # Every branch shape is brought current by MERGING origin/$target in, never by a
  # rebase — per-bead polecat/* branches included. A rebase rewrites history and
  # forces a --force-with-lease push, which resets GitHub's "changes since last
  # review" and drifts the line-anchored review comments on the PR; a merge keeps
  # both. Because no shape rewrites, none can force-push, and a branch shape invented
  # next year cannot slip past an allowlist into a rewrite. main stays linear because
  # merge.sh squashes at land, not because the branch was rebased. pr-facts.sh's
  # `stale-base-dispatch-mode` and mol-refinery-patrol's `shared-branch-merge-mode`
  # make the same choice; pre-open-rebase.test.sh fails if this site and pr-facts.sh
  # diverge. See specs/tk-yu4sng/merge-in-for-all-branches.md.
  prepare_mode=merge
  FIX_TITLE="Merge $target into $branch:"
  fix_instruction="Resume in prepare_mode=merge: bring '$branch' current by MERGING origin/$target IN (git merge --no-edit origin/$target), resolve conflicts, and push as a fast-forward. Do NOT rebase it and do NOT force-push it: a rewrite resets the PR's review view, and on a shared branch it also orphans the already-merged PRs the branch carries (tk-a0hva)."
  # <<< pre-open-dispatch-mode

  # Dedup on branch+head via the child's own metadata, in the shape pr-facts.sh
  # reads: a child of ANY status whose rejection_reason names this head means
  # this head was already routed, and a LIVE child on the branch means a rewrite
  # is already owned. The current anchor is excluded by its id and a foreign
  # anchor by its own merge_result; a rework child of THIS anchor still counts
  # when it carries one, because a child parked for a person sits in the `held`
  # lifecycle state (merge_result=held) yet still owns the branch — dropping it on
  # the merge_result test alone re-mints a merge-current twin every pass.
  kids=$(bd_list --metadata-field branch="$branch" --status="$ALL_STATUSES") || {
    echo "$PROG: $id — '$branch' conflicts but the rework probe failed; no rework dispatched (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  }
  # A child of a prior pass whose route stamp exited 0 without writing. The
  # route is what makes it reachable, and the dedup below matches it, so nothing
  # retries it. Narrowed to open/unassigned/unrouted at THIS head: a metadata
  # write ignores bd's claim guard, so re-stamping a child someone holds stomps
  # live work.
  stranded=$(printf '%s' "$kids" | jq -r --arg id "$id" --arg h "$head_oid" '
    [ .[] | select(.id != $id)
      | select(((.status // "open") | ascii_downcase) == "open")
      | select(((.assignee // "") | tostring) == "")
      | select(((.metadata["gc.routed_to"] // "") | tostring) == "")
      | select(((.metadata["gc.execution_routed_to"] // "") | tostring) == "")
      | select(((.metadata.merge_result // "") | tostring) == "")
      | select(($h != "") and (((.metadata.rejection_reason // "") | tostring) | contains("head " + $h)))
      | .id ] | .[0] // empty' 2>/dev/null)
  # A strand is open, so it matches the live arm below and would veto its own
  # rescue; it is excluded from its own dedup and from nothing else.
  dup=$(printf '%s' "$kids" | jq -r --arg id "$id" --arg s "$stranded" --arg h "$head_oid" --arg live "$LIVE_STATUSES" '
    ($live | split(",")) as $ls
    | [ .[] | select(.id != $id) | select(.id != $s)
        | select(((.metadata.merge_result // "") | tostring) == ""
                 or (((.metadata.task_kind // "") == "rework")
                     and (((.metadata.anchor_bead // "") | tostring) == $id)))
        | ((.status // "open") | ascii_downcase) as $st
        | ((.metadata.rejection_reason // "") | tostring) as $rr
        | select((($rr | contains("head " + $h)) and ($h != ""))
                 or (($ls | index($st)) != null))
        | .id ] | .[0] // empty' 2>/dev/null)
  if [ -n "$dup" ]; then
    # A covering child predating this stamp — or one whose marker write
    # half-landed — sits on the anchor's own branch with no role marker,
    # indistinguishable from the anchor by metadata. Re-stamp only an UNCLAIMED
    # dup that lacks it: a metadata write ignores bd's claim guard, so writing
    # under a live holder is what this arm refuses elsewhere, and the creation
    # path's route read-back below refuses to route an unmarked child, so a
    # CLAIMED one can only predate this stamp. A closed dup is dispositioned and
    # read by no live gate; an unreadable probe re-stamps nothing.
    dneed=$(gc bd show "$dup" --json 2>/dev/null | scrub | jq -r --arg id "$id" '
      .[0] as $x
      | if (($x | type) != "object") then "ok"
        elif ((($x.status // "") | ascii_downcase) == "closed") then "ok"
        elif ((($x.assignee // "") | tostring) != "") then "ok"
        elif ((($x.metadata.task_kind // "") == "rework") and (($x.metadata.anchor_bead // "") == $id)) then "ok"
        else "restamp" end' 2>/dev/null)
    if [ "$dneed" = "restamp" ]; then
      # `gc bd update` returns 0 without writing (the claim guard is one such
      # path), so the exit code cannot prove the marker landed. Read both keys
      # back and re-stamp once, claiming it only when it persists; the next pass
      # reaches this same block rather than report an unmarked child as marked.
      gc bd update "$dup" --set-metadata task_kind=rework --set-metadata anchor_bead="$id" >/dev/null 2>&1 || true
      dgot=$(gc bd show "$dup" --json 2>/dev/null | scrub | jq -r '.[0].metadata | ((.task_kind // "") + "|" + (.anchor_bead // ""))')
      if [ "$dgot" != "rework|$id" ]; then
        gc bd update "$dup" --set-metadata task_kind=rework --set-metadata anchor_bead="$id" >/dev/null 2>&1 || true
        dgot=$(gc bd show "$dup" --json 2>/dev/null | scrub | jq -r '.[0].metadata | ((.task_kind // "") + "|" + (.anchor_bead // ""))')
      fi
      if [ "$dgot" = "rework|$id" ]; then
        echo "$PROG: $id re-stamped role marker on covering rework $dup (task_kind=rework, anchor_bead=$id)"
      else
        echo "$PROG: WARN could not re-stamp role marker on covering rework $dup (retry next pass)" >&2
      fi
    fi
    echo "$PROG: $id — '$branch' conflicts with '$target'; rework $dup already covers this branch at this head, no new child${stranded:+ (unrouted sibling $stranded is redundant and holds the anchor)}"
    skipped=$((skipped + 1)); continue
  fi
  # Any rebase_hold on a bead naming this branch is an operator freeze.
  frozen=$(printf '%s' "$kids" | jq -r '
    [ .[] | ((.metadata.rebase_hold // "") | tostring | ascii_downcase) as $h
      | select($h != "" and $h != "false" and $h != "0" and $h != "null") | .id ] | .[0] // empty' 2>/dev/null)
  if [ -n "$frozen" ]; then
    echo "$PROG: $id — '$branch' conflicts but $frozen holds it with rebase_hold (operator gate); no rework dispatched"
    held=$((held + 1)); continue
  fi
  # A conflict is not always drift. When a change already on the target deleted
  # or rewrote the code this branch edits, bringing it current decides whether
  # the branch still has work to do, and a child sent to merge it would stop and
  # ask. branch-supersession.sh tells the two apart and puts that decision to the
  # operator; it holds only behind an open decision visit, so anything it cannot
  # classify or record falls through to the ordinary child. Read after the dedup
  # above, so a live child stands the arm down first, and before the strand
  # re-route below, so a superseded branch's strand is not routed either.
  if [ -x "$SUPERSESSION" ] && "$SUPERSESSION" hold --anchor "$id" --branch "$branch" \
       --target "$target" --base "$base_oid" --head "$head_oid"; then
    held=$((held + 1)); continue
  fi
  if [ -n "$stranded" ]; then
    FIX="$stranded"
    echo "$PROG: $id re-routing stranded rework $FIX for '$branch' (a prior pass's route stamp did not land)"
  else
    # Orphan adoption BEFORE create: a child this arm created whose stamp then
    # failed carries the deterministic title but no branch metadata — invisible
    # to the branch dedup above, so re-creating would mint a twin every pass.
    # The title is a pure function of the branch name, so it stays deterministic
    # for a given branch across passes.
    # An unreadable probe dispatches nothing (retry next pass).
    if ! forphans=$(bd_list --status=open --title-contains "$FIX_TITLE"); then
      echo "$PROG: $id — '$branch' conflicts but the orphan probe failed; no rework dispatched (retry next pass)" >&2
      skipped=$((skipped + 1)); continue
    fi
    FIX=$(printf '%s' "$forphans" | jq -r '
      [ .[] | select(((.metadata.branch // "") | tostring) == "") | .id ] | .[0] // empty' 2>/dev/null)
    if [ -n "$FIX" ]; then
      echo "$PROG: $id adopting unstamped rework orphan $FIX for '$branch' (created by a prior pass whose stamp failed)"
    else
      FIX=$(gc bd create "$FIX_TITLE base moved, the branch no longer merges" -t task --json 2>/dev/null \
        | scrub | jq -r '.id // empty' 2>/dev/null)
    fi
  fi
  if [ -z "$FIX" ]; then
    echo "$PROG: $id could not file the rework child for '$branch'; retry next pass" >&2
    skipped=$((skipped + 1)); continue
  fi
  # The route is stamped separately, after prepare_mode reads back. A dropped
  # branch leaves a child nothing can act on, which is the safe side; a dropped
  # prepare_mode leaves one that reads as a review bead rather than a rework
  # resume — pr-facts.sh keys that distinction on a non-empty prepare_mode — so
  # it escapes the rework handling. task_kind and anchor_bead are the role
  # marker: the child resumes the ANCHOR's own branch, so with no marker a
  # metadata read cannot tell the child from the anchor.
  #
  # No pr_url/pr_number/existing_pr rides this child: there is no PR yet. The
  # anchor opens its own once the branch is current, which is why the work order
  # tells the polecat not to open one.
  gc bd update "$FIX" \
    --set-metadata task_kind=rework \
    --set-metadata anchor_bead="$id" \
    --set-metadata branch="$branch" \
    --set-metadata target="$target" \
    --set-metadata rejection_reason="stale base at head $head_oid: '$branch' no longer merges into '$target'. $fix_instruction Do NOT open a PR — anchor $id opens its own once the branch is current." \
    --set-metadata prepare_mode="$prepare_mode" \
    --set-metadata merge_strategy=mr >/dev/null 2>&1 \
    || echo "$PROG: WARN rework $FIX created but not fully stamped; route it to $FIX_POOL by hand" >&2
  gc bd dep "$FIX" --blocks "$id" >/dev/null 2>&1 \
    || echo "$PROG: WARN could not attach rework $FIX as a blocks-dep of $id" >&2
  # A new rework child on this branch changes the kids/orphan probes above; drop
  # the per-pass bd_list cache so a later anchor on the same branch does not read
  # a stale "no child" and file a duplicate. No-op outside a reconcile pass.
  bd_cache_clear
  mgot=$(gc bd show "$FIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.prepare_mode // empty')
  if [ "$mgot" != "$prepare_mode" ]; then
    echo "$PROG: WARN rework $FIX did not record prepare_mode=$prepare_mode; left unrouted (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  # task_kind=rework and anchor_bead are the role marker, set in the same write
  # as prepare_mode above. That write can half-land — the exit code does not
  # prove it — and a child dropped to no marker on the anchor's OWN branch is the
  # misread this stamp exists to stop, yet the route below would still dispatch
  # it. Read both back before routing. Re-stamp once; if they still will not
  # take, leave the child unrouted (a later pass re-stamps it) rather than route
  # a rework a metadata read cannot tell from its anchor.
  kgot=$(gc bd show "$FIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata | ((.task_kind // "") + "|" + (.anchor_bead // ""))')
  if [ "$kgot" != "rework|$id" ]; then
    gc bd update "$FIX" --set-metadata task_kind=rework --set-metadata anchor_bead="$id" >/dev/null 2>&1 || true
    kgot=$(gc bd show "$FIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata | ((.task_kind // "") + "|" + (.anchor_bead // ""))')
  fi
  if [ "$kgot" != "rework|$id" ]; then
    echo "$PROG: WARN rework $FIX did not record task_kind=rework/anchor_bead=$id; left unrouted (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  # `gc bd update` returns 0 without having written (the claim guard is one such
  # path), so the exit code does not establish the route, and an unrouted child
  # reported as dispatched is a rework nothing can reach.
  gc bd update "$FIX" --set-metadata gc.routed_to="$FIX_POOL" >/dev/null 2>&1 || true
  rgot=$(gc bd show "$FIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata["gc.routed_to"] // empty')
  if [ "$rgot" != "$FIX_POOL" ]; then
    echo "$PROG: WARN rework $FIX did not record gc.routed_to=$FIX_POOL; left unrouted (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
  fi
  gc session wake "$FIX_POOL" >/dev/null 2>&1 || true
  reworked=$((reworked + 1))
  echo "$PROG: $id — '$branch' conflicts with '$target'; filed $prepare_mode-mode rework $FIX routed to $FIX_POOL"
done <<ANCHORS_EOF
$(printf '%s' "$ANCHORS" | jq -c '.[]' 2>/dev/null | pace_order "$CURSOR")
ANCHORS_EOF
pace_end

if [ -n "$PACE_RESUME_AT" ]; then
  echo "$PROG: visited $PACE_VISITED of ${total:-?} pre-open anchors before the deadline; the next pass resumes at $PACE_RESUME_AT"
else
  echo "$PROG: visited $PACE_VISITED of ${total:-?} pre-open anchors"
fi
echo "$PROG: reworked=$reworked clean=$clean held=$held skipped=$skipped"
exit 0
