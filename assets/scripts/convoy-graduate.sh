#!/usr/bin/env bash
# convoy-graduate — arm 8 of the merge cadence: graduate a complete OWNED
# integration convoy into an ordinary mr-mode work bead for the refinery.
# Conditions, all fail-closed: owned convoy targeting integration/*, all
# members closed, at least one bead in the ledger records a MERGE onto that
# branch (merged_target=<branch> + merge_result=merged — "all closed" alone is
# vacuously true for a convoy whose members landed nothing), no merge_hold /
# rebase_hold on the convoy bead or on any live bead naming the branch, and no
# live bead already owning the branch. Then: assignee=$GC_AGENT (the refinery),
# branch=<integration branch>, target=$TARGET, merge_strategy=mr,
# graduation=true. Idempotent via the convoy bead's own metadata.branch.
# Every read is of this rig's own store, and no city-wide convoy query runs.
# Args: --target <branch> (default main); --stamp <file>, the interval
# watermark below. Caller: refinery-reconcile.sh with GC_AGENT projected; an
# unreadable probe skips (retry next pass), never acts.
set -u

PROG="convoy-graduate"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

TARGET_BRANCH="main"
STAMP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET_BRANCH="${2:-main}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
    --stamp) STAMP="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
    *) shift ;;
  esac
done

# Graduation assigns the convoy bead; without an identity it would strand at
# assignee="". Skip rather than strand.
if [ -z "${GC_AGENT:-}" ]; then
  echo "$PROG: GC_AGENT unset; skip" >&2
  exit 0
fi

# Interval watermark. Graduation is not latency-sensitive: what it starts is a
# PR that waits on a human approval. So the arm runs at most once per
# MIN_INTERVAL_SECS, and a complete convoy graduates at most that much later
# than it would on the next pass. --stamp names a file holding the epoch
# second of the last pass that answered every candidate; a pass that starts
# within MIN_INTERVAL_SECS of it reads nothing. Only such a pass writes it, so
# an abort, or a candidate skipped on a read that could not answer, leaves the
# next pass to run. A stamp ahead of the clock is ignored, so a clock stepped
# back cannot park the arm.
MIN_INTERVAL_SECS=900
T0=$(date -u +%s)
if [ -n "$STAMP" ]; then
  last=$(head -n 1 "$STAMP" 2>/dev/null)
  case "$last" in ''|*[!0-9]*) last="" ;; esac
  if [ -n "$last" ]; then
    age=$(( T0 - 10#$last ))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$MIN_INTERVAL_SECS" ]; then
      echo "$PROG: last complete pass ${age}s ago; next one after ${MIN_INTERVAL_SECS}s"
      exit 0
    fi
  fi
fi
stamp_pass() {
  [ -n "$STAMP" ] || return 0
  printf '%s\n' "$T0" > "$STAMP.tmp" 2>/dev/null && mv -f "$STAMP.tmp" "$STAMP" 2>/dev/null
  return 0
}

# Every non-closed status still owns its branch (a blocked/hooked/pinned bead
# is parked, not gone); closed alone releases it.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
ALL_STATUSES="$LIVE_STATUSES,closed"

is_held() { case "${1:-}" in ""|false|False|FALSE|0|null) return 1 ;; *) return 0 ;; esac; }

# Guarded reads: non-zero = "I cannot tell", never "there is nothing there" —
# an error object on stdout with rc=0 must not read as an empty result.
bd_list() {
  local raw rc
  raw=$(gc bd list ${GC_RIG:+--rig="$GC_RIG"} "$@" --limit=0 --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
convoy_meta() { # <id> -> {hold, rhold, branch, psummary}; non-zero = unreadable
  local raw rc out
  raw=$(gc bd show "$1" ${GC_RIG:+--rig="$GC_RIG"} --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || return 1
  out=$(printf '%s' "$raw" | jq -c '.[0] | {hold: (.metadata.merge_hold // ""),
    rhold: (.metadata.rebase_hold // ""), branch: (.metadata.branch // ""),
    psummary: (.metadata.pr_summary // "")}' 2>/dev/null) || return 1
  printf '%s\n' "$out"
}
dep_rows() { # <id> [dep-list args...] -> JSON array; non-zero = unreadable
  local raw rc
  raw=$(gc bd dep list "$@" ${GC_RIG:+--rig="$GC_RIG"} --json 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
count_rows() { # <json-array> [jq-filter] -> count of rows passing the filter
  printf '%s' "$1" | jq -r "[ .[] | ${2:-.} ] | length" 2>/dev/null
}

# A convoy's members, counted the way gascity's own convoy reads count them
# (`gc convoy status`, `/convoy/{id}/check`): its parent-child children plus
# the targets of its own `tracks` edges. The convoy is complete when it has at
# least one member and every member is closed or tombstoned. A tracks edge
# whose target this store holds no row for counts as unfinished, never done.
# `bd dep list` leaves such an edge out of its answer, so the edge set comes
# from the convoy's list row (<tracks>, comma-joined), and a target that the
# listing did not resolve holds the convoy. Children are read first: an open
# child settles the answer without the second read.
# rc: 0 complete, 1 not complete, 2 a read could not answer.
UNFINISHED='select(((.status // "") | tostring) as $s | ($s != "closed" and $s != "tombstone"))'
members_complete() { # <cid> <tracks>
  local cid="$1" tracks="$2" kids tracked n_kids n_tracked open dangling
  kids=$(dep_rows "$cid" --direction=up --type=parent-child) || return 2
  open=$(count_rows "$kids" "$UNFINISHED") && n_kids=$(count_rows "$kids") || return 2
  [ "$open" -eq 0 ] || return 1
  tracked=$(dep_rows "$cid" --direction=down --type=tracks) || return 2
  open=$(count_rows "$tracked" "$UNFINISHED") && n_tracked=$(count_rows "$tracked") || return 2
  [ "$open" -eq 0 ] || return 1
  dangling=$(printf '%s' "$tracked" | jq -r --arg want "$tracks" '
    [ .[].id ] as $have
    | [ $want | split(",")[] | select(length > 0)
        | select(. as $w | any($have[]; . == $w) | not) ]
    | join(",")' 2>/dev/null) || return 2
  if [ -n "$dangling" ]; then
    echo "$PROG: $cid — its tracks edge(s) to $dangling name no bead in this rig's store; a member that cannot be read is not finished, so not graduated"
    return 1
  fi
  [ $((n_kids + n_tracked)) -gt 0 ] || return 1
  return 0
}

# Compose a seed pr_summary for a graduating convoy from the beads that merged
# onto its integration branch, so the graduated PR describes the work that
# landed rather than falling back to the convoy's dispatch text (pr-open.sh's
# fallback when pr_summary is absent). Each landed bead carries its own
# already-reviewed pr_summary, so their union is a diff-derived account; the
# pre-open review then validates that union against the integrated diff. It
# reads the landed set already in hand in one jq pass, so an unreadable value
# yields no seed. Echoes the seed on stdout; empty output means "no seed".
compose_member_summary() { # <convoy-id> <landed-json>
  local cid="$1" landed_json="$2" out
  out=$(printf '%s' "$landed_json" | jq -r --arg cid "$cid" '
    [ .[] | select(((.metadata.merge_result // "") | tostring | ascii_downcase) == "merged") ] as $m
    | if ($m | length) == 0 then ""
      else "This PR graduates integration convoy `\($cid)`, landing the work of these beads:\n"
           + ( $m | map(
                 "\n- `\(.id)` — \((.title // "") | tostring | gsub("\n"; " "))"
                 + ( ((.metadata.pr_summary // "") | tostring)
                     | if . == "" then ""
                       else "\n" + (rtrimstr("\n") | split("\n") | map("  " + .) | join("\n")) end )
               ) | join("") )
      end' 2>/dev/null) || return 0
  printf '%s' "$out"
}

# Candidates: this rig's open convoys labelled owned that target integration/*
# and carry no branch yet (graduation stamps one, and moves the target to
# $TARGET_BRANCH). The owned label is checked on each row as well as asked of
# the store, so a store that ignored the label filter could widen only the
# read, never the candidate set. Each row also carries the convoy's own
# dependency edges, and its tracks targets ride along to the member check.
# --brief drops only the free-form text, which nothing here reads.
# A failed read is a failure to ENUMERATE, not an empty rig. Exit 0 here would
# let refinery-reconcile mark this arm clean and move on — the false all-clear
# this guard class exists to prevent — so abort non-zero instead, and the
# cadence logs and retries it next pass. (A rig with no such convoy lists `[]`,
# which passes this guard and stops at the CANDS gate below.)
if ! OWNED=$(bd_list --type=convoy --status=open --label=owned --brief); then
  echo "$PROG: could not list this rig's open owned convoys; that is a failure to ENUMERATE, not an empty rig, so ABORTING non-zero rather than reporting a false all-clear (retries next pass)" >&2
  exit 1
fi
CANDS=$(printf '%s' "$OWNED" | jq -r '
  .[]
  | select(any((.labels // [])[]; . == "owned"))
  | select((.metadata.target // "") | tostring | startswith("integration/"))
  | select(((.metadata.branch // "") | tostring) == "")
  | "\(.id)\t\(.metadata.target)\t\([ (.dependencies // [])[] | select(.type == "tracks") | .depends_on_id ] | unique | join(","))"' 2>/dev/null); cands_rc=$?
# A jq failure is could-not-enumerate, not "nothing matched": abort rather than
# fall through to the empty-queue exit below and forge an all-clear.
if [ "$cands_rc" -ne 0 ]; then
  echo "$PROG: read this rig's convoys but could not render candidates (jq rc=$cands_rc); that is a failure to ENUMERATE, so ABORTING non-zero rather than reporting a false all-clear (retries next pass)" >&2
  exit 1
fi
[ -n "$CANDS" ] || { echo "$PROG: no complete owned integration convoys"; stamp_pass; exit 0; }

# Feed the loop from an EXPLICIT, CHECKED temp file — never a `<<<` here-string.
# bash backs a here-string with a temp file it creates implicitly; under disk
# pressure that creation fails SILENTLY (this script is set -u, not set -e, so the
# errored redirection does not abort), the loop runs ZERO times, and control falls
# through to the summary below — printing "0 graduating, 0 skipped, 0 held, 0
# vacuous, 0 incomplete" and exiting 0, indistinguishable from a healthy empty
# queue even though the CANDS guard just proved the list non-empty. A checked temp
# file turns that silent blackout into a non-zero abort the cadence logs and
# retries; a plain file redirect keeps the loop in THIS shell, so the counters
# below survive.
ROWS_FILE=$(mktemp "${TMPDIR:-/tmp}/gctk-convoy-graduate.XXXXXX" 2>/dev/null) || {
  echo "$PROG: cannot create a temp file to enumerate graduation candidates (disk full?); this pass could NOT enumerate its work, so it is ABORTING non-zero rather than reporting a false-empty '0 graduating, 0 skipped, 0 held, 0 vacuous, 0 incomplete' queue (retries next pass)" >&2
  exit 1
}
trap 'rm -f "$ROWS_FILE"' EXIT
printf '%s\n' "$CANDS" > "$ROWS_FILE" || {
  echo "$PROG: cannot write the candidate list to a temp file (disk full?); this pass could NOT enumerate its work, so it is ABORTING non-zero rather than reporting a false-empty queue (retries next pass)" >&2
  exit 1
}
expected=$(grep -c . "$ROWS_FILE" 2>/dev/null || true)
case "$expected" in ''|*[!0-9]*) expected=0 ;; esac

# retry counts the candidates skipped on a read that could not answer; a pass
# with any leaves the stamp alone, so the next pass retries them.
graduated=0; skipped=0; held=0; vacuous=0; incomplete=0; processed=0; retry=0
while IFS="$(printf '\t')" read -r cid ctarget ctracks; do
  [ -n "${cid:-}" ] || continue
  processed=$((processed + 1))

  members_complete "$cid" "${ctracks:-}"; members_rc=$?
  if [ "$members_rc" -eq 1 ]; then
    incomplete=$((incomplete + 1)); continue
  elif [ "$members_rc" -ne 0 ]; then
    echo "$PROG: $cid — member read failed; not graduated (retry next pass)" >&2
    skipped=$((skipped + 1)); retry=$((retry + 1)); continue
  fi

  if ! cmeta=$(convoy_meta "$cid"); then
    echo "$PROG: $cid — convoy bead read failed; not graduated (retry next pass)" >&2
    skipped=$((skipped + 1)); retry=$((retry + 1)); continue
  fi
  # Operator gate (a): a hold on the convoy bead itself. Graduation causes both
  # a rebase and a landing, so either marker vetoes.
  if is_held "$(printf '%s' "$cmeta" | jq -r '.hold')" \
     || is_held "$(printf '%s' "$cmeta" | jq -r '.rhold')"; then
    echo "$PROG: $cid — merge_hold/rebase_hold set on the convoy (operator gate); not graduated"
    held=$((held + 1)); continue
  fi
  # Idempotency: metadata.branch on the convoy bead means "already initiated".
  if [ -n "$(printf '%s' "$cmeta" | jq -r '.branch')" ]; then
    skipped=$((skipped + 1)); continue
  fi

  # Operator gate (b): who else is on this branch? The hold commonly lives on a
  # SEPARATE bead naming the branch; a live unheld owner means a graduation is
  # already in flight and a second assignment would duplicate its PR.
  if ! probe=$(bd_list --metadata-field "branch=$ctarget" --status "$LIVE_STATUSES"); then
    echo "$PROG: $cid — branch probe on '$ctarget' failed; not graduated (retry next pass)" >&2
    skipped=$((skipped + 1)); retry=$((retry + 1)); continue
  fi
  frozen=$(printf '%s' "$probe" | jq -r '
    [ .[] | select([((.metadata.merge_hold // "") | tostring), ((.metadata.rebase_hold // "") | tostring)]
        | map(ascii_downcase) | any(. != "" and . != "false" and . != "0" and . != "null"))
      | .id ] | .[0] // empty' 2>/dev/null)
  if [ -n "$frozen" ]; then
    echo "$PROG: $cid — $frozen holds branch '$ctarget' with merge_hold/rebase_hold (operator gate); not graduated"
    held=$((held + 1)); continue
  fi
  inflight=$(printf '%s' "$probe" | jq -r --arg cid "$cid" \
    '[ .[] | select(.id != $cid) | .id ] | .[0] // empty' 2>/dev/null)
  if [ -n "$inflight" ]; then
    echo "$PROG: $cid — $inflight already owns branch '$ctarget'; not graduated (would duplicate its PR)"
    skipped=$((skipped + 1)); continue
  fi

  # Non-vacuous completion: the ledger must record at least one merge ONTO the
  # branch. Closed beads count (close-on-land closes them at that merge).
  if ! landed_raw=$(bd_list --metadata-field "merged_target=$ctarget" --status "$ALL_STATUSES"); then
    echo "$PROG: $cid — landing probe on '$ctarget' failed; not graduated (retry next pass)" >&2
    skipped=$((skipped + 1)); retry=$((retry + 1)); continue
  fi
  landed=$(printf '%s' "$landed_raw" | jq -r '
    [ .[] | select(((.metadata.merge_result // "") | tostring | ascii_downcase) == "merged") | .id ]
    | .[0] // empty' 2>/dev/null)
  if [ -z "$landed" ]; then
    echo "$PROG: $cid — no bead records a merge onto '$ctarget' (merged_target + merge_result=merged); its members closing proves nothing about the branch, not graduated (land deliberately with \`gc convoy land\` if it is complete)"
    vacuous=$((vacuous + 1)); continue
  fi

  UPD=("$cid" ${GC_RIG:+--rig="$GC_RIG"}
       --assignee="$GC_AGENT"
       --set-metadata "branch=$ctarget"
       --set-metadata "target=$TARGET_BRANCH"
       --set-metadata "merge_strategy=mr"
       --set-metadata "graduation=true")
  # Seed the ## Summary from the members, so the graduated PR describes the work
  # that landed rather than falling back to the convoy's dispatch text. An
  # already-authored summary is preserved (read-modify-write); composing one is
  # best-effort, and its absence just leaves pr-open's fallback for the review
  # to flag.
  if [ -z "$(printf '%s' "$cmeta" | jq -r '.psummary')" ]; then
    SEED=$(compose_member_summary "$cid" "$landed_raw")
    [ -n "$SEED" ] && UPD+=(--set-metadata "pr_summary=$SEED")
  fi
  if gc bd update "${UPD[@]}" >/dev/null 2>&1; then
    graduated=$((graduated + 1))
    echo "$PROG: graduating $cid — $ctarget -> $TARGET_BRANCH (mr; human-approved PR)"
  else
    skipped=$((skipped + 1)); retry=$((retry + 1))
    echo "$PROG: $cid assign failed; retry next pass" >&2
  fi
done < "$ROWS_FILE"

# A pass that could not read every candidate it enumerated must NOT print the
# summary as though it finished — a short read would forge the same false
# all-clear the checked temp file above exists to prevent.
if [ "$processed" -ne "$expected" ]; then
  echo "$PROG: enumerated only $processed of $expected graduation candidates — the work list was read short (disk pressure? a truncated temp file?); this pass is INCOMPLETE, so it is ABORTING non-zero rather than reporting '$graduated graduating, $skipped skipped, $held held, $vacuous vacuous, $incomplete incomplete' as a finished queue (retries next pass)" >&2
  exit 1
fi

echo "$PROG: $graduated graduating, $skipped skipped, $held held, $vacuous vacuous, $incomplete incomplete"
[ "$retry" -eq 0 ] && stamp_pass
exit 0
