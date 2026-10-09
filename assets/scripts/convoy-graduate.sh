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
# Args: --target <branch> (default main). Caller: refinery-reconcile.sh with
# GC_AGENT projected; an unreadable probe skips (retry next pass), never acts.
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
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET_BRANCH="${2:-main}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
    *) shift ;;
  esac
done

# Graduation assigns the convoy bead; without an identity it would strand at
# assignee="". Skip rather than strand.
if [ -z "${GC_AGENT:-}" ]; then
  echo "$PROG: GC_AGENT unset; skip" >&2
  exit 0
fi

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

# Owned-ness + member completion live only in `gc convoy list` (city-wide;
# intersected with this rig's convoy ledger below).
CONVOYS=$(gc convoy list --json 2>/dev/null); convoys_rc=$?
# A failed or empty read is a failure to ENUMERATE, not an empty city. Exit 0
# here would let refinery-reconcile mark this arm clean and move on — the false
# all-clear this guard class exists to prevent — so abort non-zero instead, and
# the cadence logs and retries it next pass. (`gc convoy list` yields
# `{"convoys":[]}` for a convoy-less city, which is non-empty, so a genuinely
# empty city still passes this guard and stops at the CANDS gate below.)
if [ "$convoys_rc" -ne 0 ] || [ -z "$CONVOYS" ]; then
  echo "$PROG: could not list convoys (gc convoy list rc=$convoys_rc); that is a failure to ENUMERATE, not an empty city, so ABORTING non-zero rather than reporting a false all-clear (retries next pass)" >&2
  exit 1
fi
CANDS=$(printf '%s' "$CONVOYS" | scrub | jq -r '
  .convoys[]?
  | select((.fields.target // "") | startswith("integration/"))
  | select(.progress.total > 0 and .progress.closed == .progress.total)
  | select(.owned == true)
  | "\(.id)\t\(.fields.target)"' 2>/dev/null); cands_rc=$?
# A jq parse failure is could-not-enumerate, not "nothing matched": abort rather
# than fall through to the empty-queue exit below and forge an all-clear.
if [ "$cands_rc" -ne 0 ]; then
  echo "$PROG: read the convoy list but could not render candidates (jq rc=$cands_rc); that is a failure to ENUMERATE, so ABORTING non-zero rather than reporting a false all-clear (retries next pass)" >&2
  exit 1
fi
[ -n "$CANDS" ] || { echo "$PROG: no complete owned integration convoys"; exit 0; }

RIG_CONVOYS=$(gc bd list ${GC_RIG:+--rig="$GC_RIG"} --type=convoy --status=open \
  --limit=0 --json 2>/dev/null | scrub | jq -r '.[].id' 2>/dev/null)

# Feed the loop from an EXPLICIT, CHECKED temp file — never a `<<<` here-string.
# bash backs a here-string with a temp file it creates implicitly; under disk
# pressure that creation fails SILENTLY (this script is set -u, not set -e, so the
# errored redirection does not abort), the loop runs ZERO times, and control falls
# through to the summary below — printing "0 graduating, 0 skipped, 0 held, 0
# vacuous" and exiting 0, indistinguishable from a healthy empty queue even though
# the CANDS guard just proved the list non-empty. A checked temp file turns that
# silent blackout into a non-zero abort the cadence logs and retries; a plain file
# redirect keeps the loop in THIS shell, so the counters below survive.
ROWS_FILE=$(mktemp "${TMPDIR:-/tmp}/gctk-convoy-graduate.XXXXXX" 2>/dev/null) || {
  echo "$PROG: cannot create a temp file to enumerate graduation candidates (disk full?); this pass could NOT enumerate its work, so it is ABORTING non-zero rather than reporting a false-empty '0 graduating, 0 skipped, 0 held, 0 vacuous' queue (retries next pass)" >&2
  exit 1
}
trap 'rm -f "$ROWS_FILE"' EXIT
printf '%s\n' "$CANDS" > "$ROWS_FILE" || {
  echo "$PROG: cannot write the candidate list to a temp file (disk full?); this pass could NOT enumerate its work, so it is ABORTING non-zero rather than reporting a false-empty queue (retries next pass)" >&2
  exit 1
}
expected=$(grep -c . "$ROWS_FILE" 2>/dev/null || true)
case "$expected" in ''|*[!0-9]*) expected=0 ;; esac

graduated=0; skipped=0; held=0; vacuous=0; processed=0
while IFS="$(printf '\t')" read -r cid ctarget; do
  [ -n "${cid:-}" ] || continue
  processed=$((processed + 1))
  # -F, here-string: convoy ids contain dots, and grep -q in a pipe SIGPIPEs. A
  # disk-pressure <<< failure here reads empty and SKIPS this candidate — a
  # counted, visible refusal, never a forged graduation — so unlike the main
  # enumeration below it needs no checked-tempfile remedy.
  grep -qxF -- "$cid" <<< "$RIG_CONVOYS" || { skipped=$((skipped + 1)); continue; }

  if ! cmeta=$(convoy_meta "$cid"); then
    echo "$PROG: $cid — convoy bead read failed; not graduated (retry next pass)" >&2
    skipped=$((skipped + 1)); continue
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
    skipped=$((skipped + 1)); continue
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
    skipped=$((skipped + 1)); continue
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
    skipped=$((skipped + 1))
    echo "$PROG: $cid assign failed; retry next pass" >&2
  fi
done < "$ROWS_FILE"

# A pass that could not read every candidate it enumerated must NOT print the
# summary as though it finished — a short read would forge the same false
# all-clear the checked temp file above exists to prevent.
if [ "$processed" -ne "$expected" ]; then
  echo "$PROG: enumerated only $processed of $expected graduation candidates — the work list was read short (disk pressure? a truncated temp file?); this pass is INCOMPLETE, so it is ABORTING non-zero rather than reporting '$graduated graduating, $skipped skipped, $held held, $vacuous vacuous' as a finished queue (retries next pass)" >&2
  exit 1
fi

echo "$PROG: $graduated graduating, $skipped skipped, $held held, $vacuous vacuous"
exit 0
