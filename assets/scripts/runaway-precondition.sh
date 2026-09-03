#!/usr/bin/env bash
# runaway-precondition.sh — the deacon patrol's runaway-polecat detector.
#
# The health scans elsewhere in the patrol look for an agent NOT MOVING: a
# stale wisp, a bead whose updated_at has stopped advancing. This is the
# inverse failure — a polecat moving vigorously with no work left to do. Token
# burn is invisible to both of the not-moving scans, and one state names what
# they miss:
#
#   session ACTIVE + its last claim CLOSED + no queued demand for its pool
#
# Every polecat pool runs min=0: a seat exists only because demand spawned it,
# and it is supposed to drain when its work is done. So a seat still moving
# with a closed claim and an empty queue has nothing left to run.
#
# Three guards keep it off healthy sessions. A session whose last claim closed
# inside the grace window is exiting normally (measured: anchor close to exit
# runs about one to six minutes). A session still holding an open bead under
# any of its three assignee shapes is mid-molecule — a formula that claims per
# step leaves its last claim closed between steps, so the closed claim alone
# does not mean idle. A session whose last_active has gone stale is not
# burning anything, and the not-moving scans own it.
#
# The action ladder is nudge, then warrant: a first sighting gets one nudge
# (harmless to a session already draining), and only a later pass that finds
# the same session still in the state reports verdict=warrant. Filing the
# warrant is the caller's; this script never kills and never files a bead.
#
# Output is one key=value line per candidate session plus a summary line.
# Exit 0 whenever it reported, 2 on a usage error.
# Caller: the deacon patrol's system-health step, once per cycle.
# See docs/runaway-polecat-detection.md.
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: runaway-precondition.sh [--dry-run]
       (default)   classify every polecat session; nudge new findings
       --dry-run   classify and report only; never nudges, never writes state
env:   RUNAWAY_GRACE_S        seconds after a claim closes before the state
                              counts against a session (default 600)
       RUNAWAY_NUDGE_WAIT_S   seconds after the nudge before a still-flagged
                              session becomes warrantable (default 600)
       RUNAWAY_IDLE_S         last_active age past which a session counts as
                              not moving and is left to the stale scans (600)
       RUNAWAY_ROLE_MATCH     ERE matched against the template's agent segment
                              (default polecat)
       RUNAWAY_CALL_TIMEOUT   per-gc-call bound in seconds, 0 disables (20)
       RUNAWAY_STATE_DIR      where the per-session nudge record lives
USAGE
}

DRY_RUN=0
case "${1:-}" in
  "")        ;;
  --dry-run) DRY_RUN=1 ;;
  -h|--help) usage; exit 0 ;;
  *)         usage; exit 2 ;;
esac

num() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }

GRACE_S="${RUNAWAY_GRACE_S:-600}";      num "$GRACE_S"      || GRACE_S=600
NUDGE_WAIT_S="${RUNAWAY_NUDGE_WAIT_S:-600}"; num "$NUDGE_WAIT_S" || NUDGE_WAIT_S=600
IDLE_S="${RUNAWAY_IDLE_S:-600}";        num "$IDLE_S"       || IDLE_S=600
CALL_TIMEOUT="${RUNAWAY_CALL_TIMEOUT:-20}"; num "$CALL_TIMEOUT" || CALL_TIMEOUT=20
ROLE_MATCH="${RUNAWAY_ROLE_MATCH:-polecat}"

CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
DEFAULT_STATE_DIR="${CITY:+$CITY/.gc/runtime}"
DEFAULT_STATE_DIR="${DEFAULT_STATE_DIR:-${TMPDIR:-/tmp}/gc}/runaway-precondition"
STATE_DIR="${RUNAWAY_STATE_DIR:-$DEFAULT_STATE_DIR}"

# Recorded, never exited on: without a state dir the ladder cannot remember a
# nudge, so every pass reports flag and none reports warrant. That is a
# degraded surface, not a silent one — the summary line says which.
STATE_DIR_OK=1
mkdir -p "$STATE_DIR" 2>/dev/null || STATE_DIR_OK=0
# -w too: mkdir -p succeeds on an existing unwritable directory.
{ [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ]; } || STATE_DIR_OK=0

NOW="$(date +%s)"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/runaway-precondition.XXXXXX")" || exit 2
trap 'rm -rf "$TMPD"' EXIT

# Ownership marker: the first line of every file this script writes. Read,
# delete and prune all test it before touching a file. A label, not a lock.
STATE_MAGIC='#runaway-precondition-state-v1'

run_bounded() {
  if [ "$CALL_TIMEOUT" -gt 0 ] && command -v timeout >/dev/null 2>&1; then
    timeout "$CALL_TIMEOUT" "$@" </dev/null
  else
    "$@" </dev/null
  fi
}

# Safe as a filename and as an argument. Anything else never reaches gc or the
# state dir; it is reported as unknown instead.
safe_id() { case "${1:-}" in '' | *[!A-Za-z0-9._-]* | .* | -* | *..*) return 1 ;; *) return 0 ;; esac }

owned_file() {
  local first=""
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  IFS= read -r first < "$1" 2>/dev/null || return 1
  [ "$first" = "$STATE_MAGIC" ]
}

state_get() { # <path> <key>
  owned_file "$1" || return 1
  sed -n "s/^$2=//p" "$1" | sed -n 1p
}

state_write() { # <path> <first_flag> <last_nudge> <nudges>
  [ "$STATE_DIR_OK" = "1" ] || return 1
  local tmp
  tmp="$(mktemp "$STATE_DIR/.rp-tmp.XXXXXX" 2>/dev/null)" || return 1
  printf '%s\nfirst_flag=%s\nlast_nudge=%s\nnudges=%s\n' \
    "$STATE_MAGIC" "$2" "$3" "$4" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$1" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

state_clear() { # <path> — only ever removes a file this script wrote
  owned_file "$1" || return 0
  rm -f "$1" 2>/dev/null || true
}

# RFC3339 to epoch seconds; empty on anything unparseable, so a caller that
# cannot date something reports unknown rather than computing an age from 0.
epoch_of() {
  local t="${1:-}"
  case "$t" in '' | null | 0001-01-01*) return 1 ;; esac
  date -u -d "$t" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$t" +%s 2>/dev/null
}

# --- probes, each cached: a pass classifies at most a handful of sessions and
# --- must not re-ask the same question once per session.

DEMAND_CACHE=""
pool_demand() { # <template> -> yes|no|unknown
  local t="$1" hit rc
  # Exact field compare, not a pattern: a template carries / and . , both of
  # which a regex reads as something other than themselves.
  hit="$(printf '%s\n' "$DEMAND_CACHE" | awk -v t="$t" '$1 == t { print $2; exit }')"
  [ -n "$hit" ] && { printf '%s' "$hit"; return 0; }
  # Bare `gc hook <agent>` is the read-only probe of that agent's work query:
  # exit 0 when the pool has an offer waiting, 1 when the queue is empty. The
  # payload is the whole offer list and is not wanted here.
  run_bounded gc hook "$t" >/dev/null 2>&1
  rc=$?
  case "$rc" in
    0) hit=yes ;;
    1) hit=no ;;
    *) hit=unknown ;;
  esac
  DEMAND_CACHE="$DEMAND_CACHE
$t $hit"
  printf '%s' "$hit"
}

RIG_CACHE=""
rig_open_beads() { # <rig> -> path to a JSON array of that rig's live beads
  local rig="$1" f
  # The rig names a file here; anything outside the safe set is folded so a
  # value from the session list cannot reach outside the scratch directory.
  f="$TMPD/rig-$(printf '%s' "$rig" | tr -c 'A-Za-z0-9._-' '_').json"
  case "$RIG_CACHE" in *"|$rig|"*) printf '%s' "$f"; return 0 ;; esac
  RIG_CACHE="$RIG_CACHE|$rig|"
  # `--rig` rather than an inherited BEADS_DIR: the gc wrapper re-resolves the
  # store from the invoking rig and ignores the environment, so a city-scoped
  # caller that does not name the rig reads its own store for every session.
  if ! run_bounded gc bd list --rig="$rig" --status=open,in_progress --limit=0 --json 2>/dev/null \
      | jq -c 'if type == "array" then . else [] end' > "$f" 2>/dev/null; then
    printf '[]' > "$f"
  fi
  [ -s "$f" ] || printf '[]' > "$f"
  printf '%s' "$f"
}

# The bead a session is holding, if any. All three assignee shapes are tested
# together: a pool seat is stamped with its session id, a named polecat with
# its alias, and `gc bd update --claim` writes the session name. A filter
# written for one shape reads FALSE CLEAN against the other two.
live_claim() { # <rig> <id> <session_name> <alias> -> bead id or empty
  local f; f="$(rig_open_beads "$1")"
  jq -r --arg a "$2" --arg b "$3" --arg c "$4" \
    'first(.[] | select((.assignee // "") as $x | $x != "" and ($x == $a or $x == $b or $x == $c)) | .id) // ""' \
    "$f" 2>/dev/null
}

# --- classify

emit() { # <session> <verdict> <template> <rig> <anchor> <anchor_status> <closed_age> <idle> <demand> <nudges> <reason>
  printf 'session=%s verdict=%s template=%s rig=%s anchor=%s anchor_status=%s closed_age_s=%s idle_s=%s demand=%s nudges=%s reason=%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}"
}

SESSIONS_JSON="$TMPD/sessions.json"
if ! run_bounded gc session list --json 2>/dev/null \
    | jq -c '[.sessions[]? | select((.state // "") == "active")]' > "$SESSIONS_JSON" 2>/dev/null; then
  printf '[]' > "$SESSIONS_JSON"
fi
[ -s "$SESSIONS_JSON" ] || printf '[]' > "$SESSIONS_JSON"

# The role filter runs on the template's AGENT segment, never the whole
# string: a rig named after a role would otherwise pull every session in it.
# Every field renders "-" when absent rather than empty: `read` splits on tab,
# tab is IFS whitespace to bash, and a run of IFS whitespace is ONE delimiter —
# so a single empty field (a pool seat has no alias) shifts every field after
# it one place left and the row is read as a different session.
CANDIDATES="$TMPD/candidates.tsv"
jq -r --arg re "$ROLE_MATCH" '
  def dash: if . == null or . == "" then "-" else . end;
  .[]
  | (.template | dash) as $t
  | ($t | split("/") | last | split(".") | last) as $role
  | select($role | test($re))
  | [ (.id | dash), $t, (.rig | dash), (.session_name | dash), (.alias | dash), (.last_active | dash) ]
  | @tsv' "$SESSIONS_JSON" > "$CANDIDATES" 2>/dev/null || : > "$CANDIDATES"

SEEN="$TMPD/seen.txt"; : > "$SEEN"
N=0; N_FLAG=0; N_WARRANT=0; N_UNKNOWN=0

while IFS=$'\t' read -r sid template rig sname alias last_active; do
  [ -n "$sid" ] || continue
  N=$((N + 1))
  if ! safe_id "$sid"; then
    N_UNKNOWN=$((N_UNKNOWN + 1))
    emit "<unsafe>" unknown "$template" "$rig" - - -1 -1 unknown 0 unsafe-session-id
    continue
  fi
  printf '%s\n' "$sid" >> "$SEEN"
  state="$STATE_DIR/$sid"
  nudges="$(state_get "$state" nudges)"; num "$nudges" || nudges=0

  # 1. Still moving? A session whose last turn has gone quiet is the
  #    not-moving axis, which the stale-wisp and stale-bead scans already own.
  # A stamp from after this pass began is a session that moved while the pass
  # ran, so a negative age clamps to 0. Only an unreadable stamp is unknown.
  idle=""
  if la="$(epoch_of "$last_active")"; then
    idle=$((NOW - la))
    [ "$idle" -lt 0 ] && idle=0
  fi
  if [ -z "$idle" ]; then
    N_UNKNOWN=$((N_UNKNOWN + 1))
    emit "$sid" unknown "$template" "$rig" - - -1 -1 unknown "$nudges" unreadable-last-active
    continue
  fi
  if [ "$idle" -gt "$IDLE_S" ]; then
    [ "$DRY_RUN" = "1" ] || state_clear "$state"
    emit "$sid" clean "$template" "$rig" - - -1 "$idle" unknown "$nudges" not-moving
    continue
  fi

  # 2. What did it last claim? The claim protocol stamps that bead onto the
  #    session's own bead, which is what `gc hook current` reads back — the
  #    one answer that does not depend on guessing an assignee shape.
  anchor="$(GC_SESSION_ID="$sid" run_bounded gc hook current --id-only 2>/dev/null | sed -n 1p)"
  if [ -z "$anchor" ] || ! safe_id "$anchor"; then
    # Nothing claimed yet. A seat that has never held work is outside this
    # rule: there is no completed work to prove it is done, and a seat still
    # coming up looks the same.
    [ "$DRY_RUN" = "1" ] || state_clear "$state"
    emit "$sid" clean "$template" "$rig" - - -1 "$idle" unknown "$nudges" no-claim-yet
    continue
  fi

  # `--id <value>`, spaced, is the one flag here that must NOT take the
  # `--flag=value` form: the wrapper picks the store by sniffing a bead id out
  # of the spaced arguments, so `--id=<foreign-prefix>` is never seen and the
  # query answers from the caller's own rig with an empty array. A polecat's
  # anchor lives in its own rig's store, which is not the deacon's.
  anchor_row="$(run_bounded gc bd list --id "$anchor" --all --limit=0 --json 2>/dev/null \
    | jq -r 'if type == "array" then (.[0] // {}) else {} end
             | [ (.status // ""), (.closed_at // ""), (.updated_at // "") ] | @tsv' 2>/dev/null)"
  astatus="$(printf '%s' "$anchor_row" | cut -f1)"
  aclosed="$(printf '%s' "$anchor_row" | cut -f2)"
  aupdated="$(printf '%s' "$anchor_row" | cut -f3)"
  if [ -z "$astatus" ]; then
    N_UNKNOWN=$((N_UNKNOWN + 1))
    emit "$sid" unknown "$template" "$rig" "$anchor" - -1 "$idle" unknown "$nudges" anchor-unreadable
    continue
  fi
  if [ "$astatus" != "closed" ]; then
    [ "$DRY_RUN" = "1" ] || state_clear "$state"
    emit "$sid" clean "$template" "$rig" "$anchor" "$astatus" -1 "$idle" unknown "$nudges" anchor-open
    continue
  fi

  # 3. How long ago did it close? closed_at is the clock; updated_at is the
  #    fallback for a store that closed a bead without stamping one.
  closed_age=""
  if ct="$(epoch_of "$aclosed")" || ct="$(epoch_of "$aupdated")"; then
    closed_age=$((NOW - ct))
    [ "$closed_age" -lt 0 ] && closed_age=0
  fi
  if [ -z "$closed_age" ]; then
    N_UNKNOWN=$((N_UNKNOWN + 1))
    emit "$sid" unknown "$template" "$rig" "$anchor" "$astatus" -1 "$idle" unknown "$nudges" undated-close
    continue
  fi
  if [ "$closed_age" -lt "$GRACE_S" ]; then
    emit "$sid" grace "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" unknown "$nudges" clean-exit-window
    continue
  fi

  # 4. Holding anything else? A formula that claims per step leaves its last
  #    claim closed between steps while the work bead stays open under it.
  #    The scan needs the session's rig to name a store: without one it
  #    cannot prove the session holds nothing, and unproven is not a finding.
  if [ "$rig" = "-" ] || ! safe_id "$rig"; then
    N_UNKNOWN=$((N_UNKNOWN + 1))
    emit "$sid" unknown "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" unknown "$nudges" no-rig
    continue
  fi
  held="$(live_claim "$rig" "$sid" "$sname" "$alias")"
  if [ -n "$held" ]; then
    [ "$DRY_RUN" = "1" ] || state_clear "$state"
    emit "$sid" clean "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" unknown "$nudges" "holds-$held"
    continue
  fi

  # 5. Anything queued for its pool? Work waiting is work it will claim.
  demand="$(pool_demand "$template")"
  if [ "$demand" = "yes" ]; then
    [ "$DRY_RUN" = "1" ] || state_clear "$state"
    emit "$sid" clean "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" "$demand" "$nudges" queued-demand
    continue
  fi
  if [ "$demand" = "unknown" ]; then
    N_UNKNOWN=$((N_UNKNOWN + 1))
    emit "$sid" unknown "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" "$demand" "$nudges" demand-unreadable
    continue
  fi

  # In the precondition. Nudge on the first sighting; a later pass that still
  # finds it here is the one that reports a warrant.
  first_flag="$(state_get "$state" first_flag)"; num "$first_flag" || first_flag="$NOW"
  last_nudge="$(state_get "$state" last_nudge)"; num "$last_nudge" || last_nudge=""

  if [ "$DRY_RUN" = "1" ]; then
    N_FLAG=$((N_FLAG + 1))
    emit "$sid" flag "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" "$demand" "$nudges" dry-run
    continue
  fi

  if [ -n "$last_nudge" ] && [ "$((NOW - last_nudge))" -ge "$NUDGE_WAIT_S" ]; then
    N_WARRANT=$((N_WARRANT + 1))
    state_write "$state" "$first_flag" "$last_nudge" "$nudges" || true
    emit "$sid" warrant "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" "$demand" "$nudges" still-flagged-after-nudge
    continue
  fi
  if [ -n "$last_nudge" ]; then
    N_FLAG=$((N_FLAG + 1))
    state_write "$state" "$first_flag" "$last_nudge" "$nudges" || true
    emit "$sid" flag "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" "$demand" "$nudges" nudged-recently
    continue
  fi

  # A nudge that did not go out is not recorded as one: the next pass must
  # retry it rather than start counting down to a warrant nobody warned about.
  if run_bounded gc session nudge "$sid" \
      "NOTICE: your last claim $anchor is closed, you hold no other claim, and your pool has no queued work. If you have nothing left to run, close your step chain and run gc runtime drain-ack now." \
      >/dev/null 2>&1; then
    nudges=$((nudges + 1))
    state_write "$state" "$first_flag" "$NOW" "$nudges" || true
    N_FLAG=$((N_FLAG + 1))
    emit "$sid" flag "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" "$demand" "$nudges" nudged
  else
    state_write "$state" "$first_flag" "" "$nudges" || true
    N_FLAG=$((N_FLAG + 1))
    emit "$sid" flag "$template" "$rig" "$anchor" "$astatus" "$closed_age" "$idle" "$demand" "$nudges" nudge-failed
  fi
done < "$CANDIDATES"

# Sessions that are gone leave no record behind: a pool seat is short-lived,
# and a stale file would hand a recycled id somebody else's nudge count.
if [ "$STATE_DIR_OK" = "1" ] && [ "$DRY_RUN" != "1" ]; then
  for path in "$STATE_DIR"/*; do
    [ -e "$path" ] || continue
    owned_file "$path" || continue
    grep -qxF "${path##*/}" "$SEEN" 2>/dev/null || rm -f "$path" 2>/dev/null || true
  done
fi

state_dir_verdict=ok
[ "$STATE_DIR_OK" = "1" ] || state_dir_verdict=unavailable
printf 'runaway-precondition: sessions=%s flag=%s warrant=%s unknown=%s state_dir=%s\n' \
  "$N" "$N_FLAG" "$N_WARRANT" "$N_UNKNOWN" "$state_dir_verdict"
