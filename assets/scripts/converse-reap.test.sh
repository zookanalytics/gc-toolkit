#!/usr/bin/env bash
# Hermetic test for converse-reap.sh.
#
# converse-reap ends a converse sitting once its conversation is over: a sitting
# is a manual session under the alias of the conversation it holds, and Gas City
# does not end a manual session when its work closes, so a session that outlives
# its conversation (a stop that did not take, a conversation another path
# closed, or a hand-back to the operator's queue) runs until this pass closes it.
#
# Runs the REAL converse-reap.sh with a stubbed `gc` (CONVERSE_REAP_GC) — no live
# city, sessions, or store. The stub answers `session list` from a fixture file,
# `bd show <id>` from a per-bead fixture (absent => the not-found error object,
# with the non-zero exit, that bd really returns when nothing resolves), and
# records every `session close` to $CALLS.
# Covered:
#   (CLOSED)  a converse session whose conversation reads closed is closed
#   (GONE)    a converse session whose conversation no longer resolves is closed
#   (QUEUED)  one whose conversation is back in the operator's queue is closed
#   (C-ALIAS) the `c-` fallback alias names the conversation after its prefix
#   (OBJ)     the closed conversation is recognised whether bd answers with an
#             array or the single object it returns for one id
#   (HELD)    a session whose conversation its sitting still holds is kept
#   (ATTACHED) a session an operator is attached to is closed once its
#             conversation reads closed, because viewing a sitting does not keep
#             it open, and is kept while its sitting still holds the
#             conversation
#   (YOUNG)   a session younger than --min-age is never closed, so a sitting
#             engage has started and not yet bound keeps its alias
#   (SETTLING) a session whose conversation closed or came back to the queue
#             less than --min-age ago is kept for a pass, so its sitting can
#             record its last hand-back, and one past that is closed
#   (NOSTAMP) a settled conversation whose last write time does not read is
#             left alone
#   (NOAGE)   a session whose creation time does not read is left alone
#   (NONCONV) an alias that resolves to a bead that is no conversation is left
#             alone
#   (NOALIAS)  a converse session with no alias is left alone
#   (BADALIAS) an alias whose tail is not a bead id is left alone
#   (NONCONVERSE) a non-converse session is ignored entirely
#   (ALREADYCLOSED) a session already closed is not a candidate
#   (COUNTS)  the summary counts reaped / kept / skipped
#   (DRYRUN)  --dry-run names the plan and closes nothing
#   (UNREADABLE-LIST) a session listing that is not JSON aborts (exit 1), reaps 0
#   (UNREADABLE-CONV) a conversation read that is not JSON is skipped, never reaped
#   (OTHERERR) a conversation read that fails with a non not-found error is skipped
#   (CLOSEFAIL) a session that will not close is reported and left for next pass
#   (DISKPRESSURE) a failed temp-file enumeration aborts non-zero, forges no
#             all-clear summary, and closes nothing
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# CONVERSE_REAP_SUT overrides the script under test, so the disk-pressure case
# below can be replayed against a pre-fix copy to confirm it discriminates.
SUT="${CONVERSE_REAP_SUT:-$HERE/converse-reap.sh}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-reap-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()  { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SUT" ] && ok "converse-reap.sh present" || { bad "converse-reap.sh missing at $SUT"; exit 1; }
command -v jq >/dev/null 2>&1 || { bad "jq required for this test"; exit 1; }

mkdir -p "$TMP/bin" "$TMP/beads"
SESSIONS_FILE="$TMP/sessions.json"
export CALLS="$TMP/calls"
export CONVERSE_REAP_GC="$TMP/bin/gc"

# --- gc stub ------------------------------------------------------------------
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 ${2:-}" in
  "session list")
    if [ -n "${LIST_BROKEN:-}" ]; then echo "gc: not json here"; exit 0; fi
    cat "$SESSIONS_FILE" ;;
  "bd show")
    vid="$3"
    if [ "${CONV_BROKEN:-}" = "$vid" ]; then echo "gc bd: garbled >>>"; exit 0; fi
    if [ "${CONV_ERROR:-}" = "$vid" ]; then
      # A failure that is NOT not-found (a store blip): valid JSON, non-zero
      # exit, no not-found signature. The reap must skip it, never reap.
      jq -n '{error:"store temporarily unavailable", schema_version:1}'; exit 1
    fi
    if [ -f "$BEADS_DIR/$vid.json" ]; then cat "$BEADS_DIR/$vid.json"
    else
      # A deleted/purged id: real `gc bd show` prints the not-found object AND
      # exits non-zero. The stub must reproduce that non-zero exit so the reap is
      # tested against the answer it really gets — the signature it reads to
      # classify the conversation GONE.
      jq -n '{error:"no issues found matching the provided IDs", hint:"some IDs may reference deleted/purged records with no trace left in the live database", schema_version:1}'; exit 1
    fi ;;
  "session close")
    sid="$3"
    case " ${CLOSE_FAILS:-} " in *" $sid "*) exit 1 ;; esac
    printf 'close %s\n' "$sid" >> "$CALLS"; exit 0 ;;
  *) echo "fake gc: unhandled: $*" >&2; exit 3 ;;
esac
GC
chmod +x "$TMP/bin/gc"
export SESSIONS_FILE BEADS_DIR="$TMP/beads"

# A converse session row; created long ago unless a creation time is given.
sess() { # <id> <alias|null> <state> <attached> <closed> [template] [created_at|none]
  local tmpl="${6:-gc-toolkit/gc-toolkit.converse-opus}"
  local alias_json="null"; [ "$2" != "null" ] && alias_json="\"$2\""
  local created="${7:-2026-01-01T00:00:00Z}" created_json
  if [ "$created" = none ]; then created_json=""; else created_json=",\"created_at\":\"$created\""; fi
  printf '{"id":"%s","template":"%s","alias":%s,"state":"%s","attached":%s,"closed":%s%s}' \
    "$1" "$tmpl" "$alias_json" "$3" "$4" "$5" "$created_json"
}
# conv <id> <status> <assignee> [updated_at|none] — a conversation, a task that
# tracks tk-subj, in the `gc bd show` edge spelling, last written long ago unless
# a time is given.
conv() {
  jq -n --arg v "$1" --arg s "$2" --arg a "$3" --arg u "${4:-2026-01-01T00:00:00Z}" '[{id:$v, issue_type:"task", status:$s, assignee:$a,
      dependencies:[{id:"tk-subj", dependency_type:"tracks"}]} + (if $u == "none" then {} else {updated_at:$u} end)]' > "$BEADS_DIR/$1.json"
}
conv_obj() { # <id> <status> <assignee> — bd answers with a bare object, not an array
  jq -n --arg v "$1" --arg s "$2" --arg a "$3" '{id:$v, issue_type:"task", status:$s, assignee:$a, updated_at:"2026-01-01T00:00:00Z",
      dependencies:[{id:"tk-subj", dependency_type:"tracks"}]}' > "$BEADS_DIR/$1.json"
}
task_bead() { # <id> <status> — a task that tracks nothing: work a person owes, no conversation
  jq -n --arg v "$1" --arg s "$2" '[{id:$v, issue_type:"task", status:$s, assignee:"alice", dependencies:[]}]' > "$BEADS_DIR/$1.json"
}

# The comprehensive fixture. Aliases are the qualified <rig>/<binding>.<alias>
# form engage's sessions carry, so the alias is the final dot-segment.
build_world() {
  : > "$CALLS"; rm -f "$TMP/beads"/*.json
  conv     tk-closed closed      gc-toolkit/gc-toolkit.tk-closed
  conv     tk-queued open        human
  conv     tk-held   in_progress gc-toolkit/gc-toolkit.tk-held
  conv_obj tk-obj    closed      gc-toolkit/gc-toolkit.tk-obj
  conv     tk-attn   closed      gc-toolkit/gc-toolkit.tk-attn
  conv     tk-attnheld in_progress gc-toolkit/gc-toolkit.tk-attnheld
  conv     tk-cfall  closed      gc-toolkit/gc-toolkit.c-tk-cfall
  conv     tk-young  open        human
  conv     tk-noage  closed      gc-toolkit/gc-toolkit.tk-noage
  task_bead tk-task  open
  # tk-gone: no fixture file => absent
  {
    printf '{"sessions":['
    sess s-closed        gc-toolkit/gc-toolkit.tk-closed active false false
    printf ','; sess s-queued gc-toolkit/gc-toolkit.tk-queued asleep false false
    printf ','; sess s-held   gc-toolkit/gc-toolkit.tk-held   active false false
    printf ','; sess s-obj    gc-toolkit/gc-toolkit.tk-obj    asleep false false
    printf ','; sess s-gone   gc-toolkit/gc-toolkit.tk-gone   asleep false false
    printf ','; sess s-attn   gc-toolkit/gc-toolkit.tk-attn   active true  false
    printf ','; sess s-cfall  gc-toolkit/gc-toolkit.c-tk-cfall asleep false false
    printf ','; sess s-young  gc-toolkit/gc-toolkit.tk-young  creating false false gc-toolkit/gc-toolkit.converse-opus "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf ','; sess s-noage  gc-toolkit/gc-toolkit.tk-noage  asleep false false gc-toolkit/gc-toolkit.converse-opus none
    printf ','; sess s-attnheld gc-toolkit/gc-toolkit.tk-attnheld active true false
    printf ','; sess s-task   gc-toolkit/gc-toolkit.tk-task   asleep false false
    printf ','; sess s-noalias null                           asleep false false
    printf ','; sess s-badalias gc-toolkit/gc-toolkit.nodash  asleep false false
    printf ','; sess s-alreadyclosed gc-toolkit/gc-toolkit.tk-closed asleep false true
    printf ','; sess s-notconv gc-toolkit/gc-toolkit.tk-held  active false false gc-toolkit/gc-toolkit.polecat
    printf ']}'
  } > "$SESSIONS_FILE"
}

# --- the main pass ------------------------------------------------------------
build_world
OUT="$(bash "$SUT" 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"

eq "$RC" "0" "a normal pass exits 0"
has "$CLOSED" "close s-closed"  "CLOSED: a closed conversation's session is closed"
has "$CLOSED" "close s-gone"    "GONE: a vanished conversation's session is closed"
has "$CLOSED" "close s-queued"  "QUEUED: a session whose conversation is back in the queue is closed"
has "$CLOSED" "close s-cfall"   "C-ALIAS: the c- fallback alias names its conversation after the prefix"
has "$CLOSED" "close s-obj"     "OBJ: a closed conversation answered as a bare object is recognised"
hasnt "$CLOSED" "close s-held"  "HELD: a sitting still holding its conversation is kept"
has "$CLOSED" "close s-attn"    "ATTACHED: an attached session is closed once its conversation reads closed"
hasnt "$CLOSED" "close s-attnheld" "ATTACHED: an attached session whose sitting still holds its conversation is kept"
hasnt "$CLOSED" "close s-young" "YOUNG: a session younger than --min-age is never closed"
hasnt "$CLOSED" "close s-noage" "NOAGE: a session whose age does not read is left alone"
hasnt "$CLOSED" "close s-task"  "NONCONV: an alias resolving to a bead that is no conversation is left alone"
hasnt "$CLOSED" "close s-noalias" "NOALIAS: a session with no alias is left alone"
hasnt "$CLOSED" "close s-badalias" "BADALIAS: a non-bead-id alias tail is left alone"
hasnt "$CLOSED" "close s-notconv" "NONCONVERSE: a non-converse session is ignored"
hasnt "$CLOSED" "close s-alreadyclosed" "ALREADYCLOSED: an already-closed session is not a candidate"

has "$OUT" "closed 6 settled converse sittings" "COUNTS: six sittings reaped"
has "$OUT" "kept 2 held"    "COUNTS: two live sittings kept"
has "$OUT" "skipped 2"      "COUNTS: the non-conversation and bad-alias candidates are skipped"

# --- dry-run ------------------------------------------------------------------
build_world
OUT="$(bash "$SUT" --dry-run 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "0" "DRYRUN: exits 0"
eq "$CLOSED" "" "DRYRUN: closes nothing"
has "$OUT" "would close 6 settled converse sittings" "DRYRUN: reports the plan count"
has "$OUT" "s-closed (conversation tk-closed closed)" "DRYRUN: names a closed conversation's sitting in the plan"
has "$OUT" "s-gone (conversation tk-gone gone)" "DRYRUN: names a gone conversation's sitting in the plan"
has "$OUT" "s-queued (conversation tk-queued queued)" "DRYRUN: names a queued conversation's sitting in the plan"

# --- unreadable session listing ----------------------------------------------
build_world
OUT="$(LIST_BROKEN=1 bash "$SUT" 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "1" "UNREADABLE-LIST: a non-JSON session listing aborts with exit 1"
eq "$CLOSED" "" "UNREADABLE-LIST: nothing is closed on an unreadable listing"
has "$OUT" "could not read the session list" "UNREADABLE-LIST: says why"

# --- unreadable conversation read (one session) ------------------------------
build_world
OUT="$(CONV_BROKEN=tk-closed bash "$SUT" 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "0" "UNREADABLE-CONV: the pass still completes"
hasnt "$CLOSED" "close s-closed" "UNREADABLE-CONV: a session whose conversation will not read is NOT closed"
has "$CLOSED" "close s-gone" "UNREADABLE-CONV: other settled sittings are still reaped"

# --- a session that will not close -------------------------------------------
# The close is the one operation this order performs, so a session that fails to
# close is reported on stderr and counted skipped, and must NOT appear among the
# reaped list on stdout — otherwise the summary would claim a sitting it never
# closed.
# stdout and stderr are captured apart: the failure line names the sitting on
# stderr too, so a combined capture could not tell it from a reaped-list entry.
build_world
CLOSE_FAILS='s-closed' bash "$SUT" >"$TMP/cf.out" 2>"$TMP/cf.err"; RC=$?
CF_OUT="$(cat "$TMP/cf.out")"; CF_ERR="$(cat "$TMP/cf.err")"
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "0" "CLOSEFAIL: the pass exits 0"
has "$CF_ERR" "could not close settled sitting s-closed" "CLOSEFAIL: the failure is reported on stderr"
has "$CLOSED" "close s-gone" "CLOSEFAIL: a failed close does not stop the pass"
hasnt "$CF_OUT" "s-closed (conversation tk-closed closed)" "CLOSEFAIL: the failed sitting is NOT listed among the reaped"
has "$CF_OUT" "s-gone (conversation tk-gone gone)" "CLOSEFAIL: a sitting that did close IS listed"
has "$CF_OUT" "closed 5 settled" "CLOSEFAIL: only the five that closed are counted reaped"
has "$CF_OUT" "skipped 3" "CLOSEFAIL: the failed close is counted skipped, with the non-conversation and bad-alias"

# --- a conversation read that fails with a NON not-found error is skipped -----
# `gc bd show` exits non-zero for reasons other than a purged id (a store blip).
# Only bd's not-found signature means gone; any other failure is an unreadable
# probe — kept and counted skipped, never reaped.
: > "$CALLS"; rm -f "$TMP/beads"/*.json
printf '{"sessions":[%s]}' "$(sess s-err gc-toolkit/gc-toolkit.tk-err asleep false false)" > "$SESSIONS_FILE"
OUT="$(CONV_ERROR=tk-err bash "$SUT" 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "0" "OTHERERR: the pass completes"
eq "$CLOSED" "" "OTHERERR: a non not-found conversation failure is NOT reaped"
has "$OUT" "closed 0 settled" "OTHERERR: nothing reaped"
has "$OUT" "skipped 1" "OTHERERR: the unreadable conversation is counted skipped"

# --- a conversation settled within the last interval waits a pass -------------
# The sign-off writes the close or the hand-back to the queue, and the sitting
# records its last hand-back on its next tool call. A pass in between would end
# the session before that record lands, so a conversation written less than
# --min-age ago keeps its session for a pass, attached or not, and one written
# longer ago is reaped.
: > "$CALLS"; rm -f "$TMP/beads"/*.json
NOW_TS="$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%SZ")')"
PAST_TS="$(jq -nr '(now - 360) | strftime("%Y-%m-%dT%H:%M:%SZ")')"
conv tk-justclosed closed gc-toolkit/gc-toolkit.tk-justclosed "$NOW_TS"
conv tk-justqueued open   human                               "$NOW_TS"
conv tk-pastgrace  closed gc-toolkit/gc-toolkit.tk-pastgrace  "$PAST_TS"
conv tk-nostamp    closed gc-toolkit/gc-toolkit.tk-nostamp    none
printf '{"sessions":[%s,%s,%s,%s]}' \
  "$(sess s-justclosed gc-toolkit/gc-toolkit.tk-justclosed active true false)" \
  "$(sess s-justqueued gc-toolkit/gc-toolkit.tk-justqueued active false false)" \
  "$(sess s-pastgrace  gc-toolkit/gc-toolkit.tk-pastgrace  active false false)" \
  "$(sess s-nostamp    gc-toolkit/gc-toolkit.tk-nostamp    asleep false false)" > "$SESSIONS_FILE"
OUT="$(bash "$SUT" 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "0" "SETTLING: the pass completes"
hasnt "$CLOSED" "close s-justclosed" "SETTLING: a session whose conversation closed seconds ago is kept for a pass"
hasnt "$CLOSED" "close s-justqueued" "SETTLING: and one whose conversation came back to the queue seconds ago"
has "$CLOSED" "close s-pastgrace" "SETTLING: one whose conversation closed longer than --min-age ago is closed"
hasnt "$CLOSED" "close s-nostamp" "NOSTAMP: a settled conversation whose last write time does not read is left alone"
has "$OUT" "kept 2 settled within the last 300s" "SETTLING: the summary counts the two that wait"
has "$OUT" "skipped 1" "NOSTAMP: and counts the unreadable one skipped"

# --- nothing to do ------------------------------------------------------------
: > "$CALLS"
printf '{"sessions":[%s]}' "$(sess s-only gc-toolkit/gc-toolkit.tk-held active false false gc-toolkit/gc-toolkit.polecat)" > "$SESSIONS_FILE"
OUT="$(bash "$SUT" 2>&1)"; RC=$?
eq "$RC" "0" "EMPTY: a city with no converse candidates exits 0"
has "$OUT" "closed 0 settled converse sittings" "EMPTY: reports nothing reaped"

# --- disk pressure: a failed temp-file enumeration must NOT forge an all-clear -
# The candidate loop reads a producer-named temp file created with mktemp. Under
# disk pressure mktemp fails with ENOSPC; the pre-fix form drove the loop from a
# `<<<` here-string, whose implicit temp file failed the same way but silently,
# running the loop zero times and still printing the summary and exiting 0 — an
# all-clear byte-identical to a healthy empty queue. A failing `mktemp` shim first
# on PATH reproduces ENOSPC hermetically. The fixed script aborts non-zero with no
# summary and closes nothing; the pre-fix `<<<` form does not call mktemp, so this
# case run against it (CONVERSE_REAP_SUT=<old copy>) fails every assertion below,
# which is what proves the case discriminates.
build_world
MKTEMP_SHIM="$TMP/mkbin"; mkdir -p "$MKTEMP_SHIM"
cat > "$MKTEMP_SHIM/mktemp" <<'MT'
#!/usr/bin/env bash
echo "mktemp: No space left on device" >&2
exit 1
MT
chmod +x "$MKTEMP_SHIM/mktemp"
PATH="$MKTEMP_SHIM:$PATH" bash "$SUT" >"$TMP/dp.out" 2>"$TMP/dp.err"; RC=$?
DP_OUT="$(cat "$TMP/dp.out")"; DP_ERR="$(cat "$TMP/dp.err")"
CLOSED="$(cat "$CALLS" 2>/dev/null)"
[ "$RC" -ne 0 ] && ok "DISKPRESSURE: a failed temp-file enumeration aborts non-zero" \
  || bad "DISKPRESSURE: must abort non-zero on a failed mktemp (got rc=$RC)"
hasnt "$DP_OUT" "settled converse sittings" "DISKPRESSURE: the forged all-clear summary is ABSENT from stdout"
eq "$CLOSED" "" "DISKPRESSURE: no session is closed when enumeration fails"
has "$DP_ERR" "reaping nothing" "DISKPRESSURE: the blackout is announced on stderr"

echo ""
echo "converse-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
