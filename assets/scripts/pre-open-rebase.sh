#!/usr/bin/env bash
# pre-open-rebase — arm 1a of the merge cadence: the conflict observer for
# pre_open_gate anchors. Caller: refinery-reconcile.sh.
#
# A pre-open anchor has no PR, so GitHub can answer nothing about it. Every
# conflict arm in the cadence reads `mergeable`/`mergeStateStatus` off a PR that
# does not exist yet, and pr-facts.sh skips any anchor whose `pr_number` is
# absent before it reads anything else. The result is not a narrow enumeration
# that could be widened: widening one routes zero children, because the facts
# those arms dispatch on are PR facts. A pre-open anchor whose branch has gone
# stale therefore gets no rebase child at all, while an otherwise identical
# pull_request anchor gets one.
#
# This arm asks git the question GitHub cannot yet be asked — does the recorded
# branch still merge into its target — and on a conflict files ONE rebase child
# per branch to the fix pool, the same child pr-facts.sh's CONFLICTING arm files
# for a PR anchor. ONE fetch per pass mirrors every branch into a private ref
# namespace; per anchor, both sides must resolve there before
# `git merge-tree --write-tree` is asked anything.
# CLEAN records nothing; CONFLICT classifies the head branch (allowlist: only
# polecat/* may be rewritten, and never a graduation) and files, adopts or
# re-routes one child, stamped prepare_mode and counted as dispatched only once
# that stamp AND the route read back.
#
# Same vetoes as pr-facts.sh: an operator merge_hold or rebase_hold on the
# anchor, a rebase_hold on any bead naming the branch, and a live demand
# (rebasing is one horn of what a demand asks, so performing it answers the
# person's question by fait accompli).
#
# Dedup is shared with pr-facts.sh by construction rather than by bookkeeping:
# both arms probe children on `metadata.branch`, and the `rejection_reason`
# written here names `head <oid>` in the phrasing that arm matches. Whichever
# arm sees the branch first files, and the other stands down — a live child on
# the branch already owns the rewrite, and a second would race it.
#
# Args: --fix-pool <pool>.
# Exits: 0, including where nothing could be observed; 1 only when the anchor
# enumeration itself is unreadable, which is the one state that would otherwise
# report a false all-clear. NOT set -e: anchors are independent.
set -u

PROG="pre-open-rebase"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

FIX_POOL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix-pool) FIX_POOL="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# Where the probe parks the branch tips it compares. Its own namespace, so
# nothing here can move a branch or a remote-tracking ref; the same device
# merge.sh uses for its seed-audit merge gate.
GATE_REF="refs/gc-toolkit/pre-open-rebase"

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

bd_list() { # guarded array read; non-zero = "could not tell"
  local raw rc
  raw=$(gc bd list "$@" --limit=0 --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}

# >>> takeaway-hold-discriminator
# Whether a person still owes an answer on this anchor. `gc.takeaway` cannot
# say: it is one field a sitting stamps when it begins and REPLACES with its
# outcome when it signs off, and nothing clears it, so its presence dates the
# last sitting instead of naming a live wait. Read as a hold, it parks an
# anchor from its first conversation onward.
#
# The wait itself is a bead. `gc-helm.sh demand` files what a person owes as
# its own bead stamped gc.demand_for=<anchor>, blocking the anchor on it, and
# the sitting closes that bead with the ruling that answers it. A live demand
# is a live hold; none, and the takeaway records a sitting that ended.
#
# Only demands count. Rework children and `--waiting-on` edges are work in
# flight, which the merge already holds on, and reading `blocks` at large would
# restore the same permanence one indirection out. The `held` lifecycle state
# is not read either: it is entered only from `unanchored`, and every anchor a
# round cap parks carries pre_open_gate or pull_request.
#
# The cap's OWN demand does not count as a hold against the cap. signoff.sh's
# round cap files a demand to record its park as an edge, stamped
# gc.takeaway_by=signoff — the same provenance the park's takeaway carries, and
# the same field the retire arms read to tell the cap's park from a person's. A
# retire that read its own demand as a live hold would refuse to lift the park
# it exists to lift, so this discriminator excludes it, and only a demand a
# converse sitting owns (any other writer) holds the anchor here.
#
# demand_gate_state reads the demand ledger for an anchor in three, because its
# two callers ask opposite questions of the same rows:
#   0  a demand a converse sitting owns (by != signoff) holds the anchor
#   1  the ledger read cleanly and no such demand holds
#   2  the ledger would not read — the list failed or returned a non-array
# gc.demand_for names the demand's anchor; the cap's own demand (by=signoff) is
# excluded, so a retire never reads the demand it filed as a live hold.
demand_gate_state() { # <anchor-id>
  local rows
  rows=$(gc bd list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --metadata-field "gc.demand_for=${1:-}" --limit=0 --json 2>/dev/null) || return 2
  rows=$(printf '%s' "$rows" | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$rows" | jq -e --arg a "${1:-}" \
    '[ .[] | select(((.metadata["gc.demand_for"] // "") | tostring) == $a)
            | select(((.metadata["gc.takeaway_by"] // "") | tostring) != "signoff") ] | length > 0' \
    >/dev/null 2>&1 && return 0
  return 1
}
# Fails CLOSED — a ledger that will not read answers "held", because releasing an
# anchor a person is holding hands their decision back to a pool. The retire path
# needs only that boolean and collapses "unreadable" into "held"; the cap writer
# reads demand_gate_state directly, because a park must stand on a demand it
# proved, not on a read that did not happen.
takeaway_is_holding() { # <anchor-id>; 0 = a person other than the cap owes an answer here
  local st; demand_gate_state "${1:-}"; st=$?
  [ "$st" -ne 1 ]
}
# Close the demand the cap filed to gate this anchor (gc.demand_for=<anchor>,
# gc.takeaway_by=signoff), and PROVE it closed. The park and its demand retire
# together: left open the demand holds the anchor out of `bd ready` — merge.sh
# reads it as a live blocker — under a park the retire just lifted, so a caller
# that clears the park while this reports success releases the anchor in name
# only. Fails (non-zero) when the ledger will not read, an update is refused, or
# a signoff-owned demand still reads live afterward, so the caller can keep the
# park until both retire. Only the cap's own — a converse sitting's demand
# outranks the retire, is left standing, and does not count against this.
close_cap_demand() { # <anchor> <note>; 0 = no signoff demand holds, non-zero = one may
  local rows id live
  rows=$(gc bd list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --metadata-field "gc.demand_for=${1:-}" --limit=0 --json 2>/dev/null | scrub) || return 1
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  for id in $(printf '%s' "$rows" | jq -r --arg a "${1:-}" \
        '.[] | select(((.metadata["gc.demand_for"] // "") | tostring) == $a)
             | select(((.metadata["gc.takeaway_by"] // "") | tostring) == "signoff")
             | .id' 2>/dev/null); do
    [ -n "$id" ] || continue
    gc bd update "$id" --status=closed --append-notes "${2:-}" >/dev/null 2>&1 || return 1
  done
  # Read the ledger again: a close that was denied or raced leaves the demand
  # live, and the status filter above already drops closed, so any signoff-owned
  # row that still answers is one that did not retire.
  rows=$(gc bd list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --metadata-field "gc.demand_for=${1:-}" --limit=0 --json 2>/dev/null | scrub) || return 1
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  live=$(printf '%s' "$rows" | jq -r --arg a "${1:-}" \
        '[ .[] | select(((.metadata["gc.demand_for"] // "") | tostring) == $a)
                | select(((.metadata["gc.takeaway_by"] // "") | tostring) == "signoff") ] | length' 2>/dev/null)
  case "$live" in ''|*[!0-9]*) return 1 ;; esac
  [ "$live" -eq 0 ]
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

reworked=0; clean=0; held=0; skipped=0
while IFS= read -r row; do
  [ -n "${row:-}" ] || continue
  id=$(printf '%s' "$row" | jq -r '.id // empty')
  branch=$(printf '%s' "$row" | jq -r '.metadata.branch // empty')
  target=$(printf '%s' "$row" | jq -r '.metadata.merged_target // .metadata.target // empty')
  [ -n "$target" ] || target="$DEFAULT_BRANCH"
  # A graduation is the integration-to-main case whatever its branch is named,
  # so the classifier reads this as well as the branch.
  grad=$(printf '%s' "$row" | jq -r '.metadata.graduation // ""')
  hold=$(printf '%s' "$row" | jq -r '.metadata.merge_hold // ""')
  rhold=$(printf '%s' "$row" | jq -r '.metadata.rebase_hold // ""')
  if [ -z "$id" ] || [ -z "$branch" ]; then skipped=$((skipped + 1)); continue; fi

  # --- observe: does this branch still merge into its target? --------------------
  # Both sides are read out of the namespace the pass fetch filled, so the
  # comparison is between the two remote tips and never between a checkout
  # lagging its own default branch and anything else.
  head_oid=$(git rev-parse --verify --quiet "$GATE_REF/heads/$branch" 2>/dev/null)
  base_oid=$(git rev-parse --verify --quiet "$GATE_REF/heads/$target" 2>/dev/null)
  # Nothing is probed until both sides resolve. `git merge-tree` exits 1 for a
  # ref it cannot resolve ("not something we can merge") exactly as it does for a
  # conflict, so on the exit status alone a branch someone deleted is a permanent
  # conflict, and this arm would file it a rebase child every pass for a branch
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
       # rewrite against a question that was never answered.
       echo "$PROG: $id merge-tree could not compare '$branch' against '$target' (rc=$mt_rc); nothing observed" >&2
       skipped=$((skipped + 1)); continue ;;
  esac

  # --- CONFLICT: file ONE rebase child per branch to the fix pool ----------------
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

  # --- WHICH rewrite may be dispatched against this branch. ---------------------
  # >>> pre-open-dispatch-mode
  # The same allowlist as pr-facts.sh's `stale-base-dispatch-mode`, applied where
  # the second actor is chosen. Only polecat/* is single-author and disposable
  # enough to rewrite; every other shape, including one invented next year, must
  # fail to MERGE, which a denylist could not do. Rebase REWRITES commits, which
  # is free on a disposable per-bead branch and destructive on a branch other
  # work already depends on. pre-open-rebase.test.sh fails if the two copies of
  # the allowlist disagree. See specs/tk-rvspf/dispatch-site-branch-classification.md.
  case "$branch" in
    polecat/*) prepare_mode=rebase ;;
    *)         prepare_mode=merge ;;
  esac
  # Load-bearing only for a graduation carried on a polecat-shaped branch.
  if [ "$grad" = "true" ]; then prepare_mode=merge; fi
  # prepare_mode is what stops the rewrite; mol-polecat-work's
  # `rejected-branch-resume-mode` reads it. The title and instruction are for
  # whoever works the bead by hand, and must not contradict it: a merge-mode
  # child titled "Rebase ..." invites exactly what the mode prevents.
  if [ "$prepare_mode" = "merge" ]; then
    FIX_TITLE="Merge $target into shared branch $branch:"
    fix_instruction="Resume in prepare_mode=merge: '$branch' is a SHARED branch, so bring it current by MERGING origin/$target IN (git merge --no-edit origin/$target), resolve conflicts, and push as a fast-forward. Do NOT rebase it and do NOT force-push it: rewriting it orphans the already-merged PRs it carries (tk-a0hva)."
  else
    FIX_TITLE="Rebase $branch onto $target:"
    fix_instruction="Resume in prepare_mode=rebase: rebase '$branch' onto origin/$target, resolve conflicts, and force-push with --force-with-lease."
  fi
  # <<< pre-open-dispatch-mode

  # Dedup on branch+head via the child's own metadata, in the shape pr-facts.sh
  # reads: a child of ANY status whose rejection_reason names this head means
  # this head was already routed, and a LIVE child on the branch means a rewrite
  # is already owned. Anchors are excluded by their own merge_result, so the
  # pull_request anchor this bead becomes never dedups against itself.
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
        | select(((.metadata.merge_result // "") | tostring) == "")
        | ((.status // "open") | ascii_downcase) as $st
        | ((.metadata.rejection_reason // "") | tostring) as $rr
        | select((($rr | contains("head " + $h)) and ($h != ""))
                 or (($ls | index($st)) != null))
        | .id ] | .[0] // empty' 2>/dev/null)
  if [ -n "$dup" ]; then
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
  if [ -n "$stranded" ]; then
    FIX="$stranded"
    echo "$PROG: $id re-routing stranded rework $FIX for '$branch' (a prior pass's route stamp did not land)"
  else
    # Orphan adoption BEFORE create: a child this arm created whose stamp then
    # failed carries the deterministic title but no branch metadata — invisible
    # to the branch dedup above, so re-creating would mint a twin every pass.
    # The title is the classifier's, and stays deterministic for a given branch:
    # the mode is a pure function of the branch name and the graduation marker.
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
  # prepare_mode leaves one that is routable AND rewriting, because the resume
  # path treats an absent mode as rebase.
  #
  # No pr_url/pr_number/existing_pr rides this child: there is no PR yet. The
  # anchor opens its own once the branch is current, which is why the work order
  # tells the polecat not to open one.
  gc bd update "$FIX" \
    --set-metadata branch="$branch" \
    --set-metadata target="$target" \
    --set-metadata rejection_reason="stale base at head $head_oid: '$branch' no longer merges into '$target'. $fix_instruction Do NOT open a PR — anchor $id opens its own once the branch is current." \
    --set-metadata prepare_mode="$prepare_mode" \
    --set-metadata merge_strategy=mr >/dev/null 2>&1 \
    || echo "$PROG: WARN rework $FIX created but not fully stamped; route it to $FIX_POOL by hand" >&2
  gc bd dep "$FIX" --blocks "$id" >/dev/null 2>&1 \
    || echo "$PROG: WARN could not attach rework $FIX as a blocks-dep of $id" >&2
  mgot=$(gc bd show "$FIX" --json 2>/dev/null | scrub | jq -r '.[0].metadata.prepare_mode // empty')
  if [ "$mgot" != "$prepare_mode" ]; then
    echo "$PROG: WARN rework $FIX did not record prepare_mode=$prepare_mode; left unrouted (retry next pass)" >&2
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
$(printf '%s' "$ANCHORS" | jq -c '.[]' 2>/dev/null)
ANCHORS_EOF

echo "$PROG: reworked=$reworked clean=$clean held=$held skipped=$skipped"
exit 0
