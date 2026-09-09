#!/usr/bin/env bash
# Hermetic test for converse-reap.sh.
#
# converse-reap ends a converse sitting once its visit has closed: converse is
# spawn-on-engagement, the manual session is exempt from every pool backstop, and
# closing the visit (sign-off or dismiss) does not close the session, so a settled
# sitting leaks a max_active_sessions slot until this pass closes it.
#
# Runs the REAL converse-reap.sh with a stubbed `gc` (CONVERSE_REAP_GC) — no live
# city, sessions, or store. The stub answers `session list` from a fixture file,
# `bd show <vid>` from a per-visit fixture (absent => the not-found error object,
# with the non-zero exit, that bd really returns when nothing resolves), and
# records every `session close` to $CALLS.
# Covered:
#   (CLOSED)  a converse session whose visit reads closed is closed
#   (GONE)    a converse session whose visit no longer resolves is closed
#   (OBJ)     the closed visit is recognised whether bd answers with an array or
#             the single object it returns for one id
#   (OPEN)    a session whose visit is still open (a live hold) is kept
#   (ATTACHED) a session an operator is attached to is NEVER closed, even with a
#             closed visit — the typed-text hard-no
#   (NONVISIT) an alias that resolves to a non-visit bead is left alone
#   (NOALIAS)  a converse session with no alias is left alone
#   (BADALIAS) an alias whose tail is not a bead id is left alone
#   (NONCONVERSE) a non-converse session is ignored entirely
#   (ALREADYCLOSED) a session already closed is not a candidate
#   (COUNTS)  the summary counts reaped / kept / skipped
#   (DRYRUN)  --dry-run names the plan and closes nothing
#   (UNREADABLE-LIST) a session listing that is not JSON aborts (exit 1), reaps 0
#   (UNREADABLE-VISIT) a visit read that is not JSON is skipped, never reaped
#   (OTHERERR) a visit read that fails with a non not-found error is skipped
#   (CLOSEFAIL) a session that will not close is reported and left for next pass
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/converse-reap.sh"
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
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "session list")
    if [ -n "${LIST_BROKEN:-}" ]; then echo "gc: not json here"; exit 0; fi
    cat "$SESSIONS_FILE" ;;
  "bd show")
    vid="$3"
    if [ "${VISIT_BROKEN:-}" = "$vid" ]; then echo "gc bd: garbled >>>"; exit 0; fi
    if [ "${VISIT_ERROR:-}" = "$vid" ]; then
      # A failure that is NOT not-found (a store blip): valid JSON, non-zero
      # exit, no not-found signature. The reap must skip it, never reap.
      jq -n '{error:"store temporarily unavailable", schema_version:1}'; exit 1
    fi
    if [ -f "$BEADS_DIR/$vid.json" ]; then cat "$BEADS_DIR/$vid.json"
    else
      # A deleted/purged id: real `gc bd show` prints the not-found object AND
      # exits non-zero. The stub must reproduce that non-zero exit so the reap is
      # tested against the answer it really gets — the signature it reads to
      # classify the visit GONE.
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

# A converse session row.
sess() { # <id> <alias|null> <state> <attached> <closed> [template]
  local tmpl="${6:-gc-toolkit/gc-toolkit.converse-opus}"
  local alias_json="null"; [ "$2" != "null" ] && alias_json="\"$2\""
  printf '{"id":"%s","template":"%s","alias":%s,"state":"%s","attached":%s,"closed":%s}' \
    "$1" "$tmpl" "$alias_json" "$3" "$4" "$5"
}
visit() { # <vid> <status>
  jq -n --arg v "$1" --arg s "$2" '[{id:$v, status:$s, metadata:{task_kind:"visit"}}]' > "$BEADS_DIR/$1.json"
}
visit_obj() { # <vid> <status> — bd answers with a bare object, not an array
  jq -n --arg v "$1" --arg s "$2" '{id:$v, status:$s, metadata:{task_kind:"visit"}}' > "$BEADS_DIR/$1.json"
}
task_bead() { # <vid> <status> — a non-visit bead
  jq -n --arg v "$1" --arg s "$2" '[{id:$v, status:$s, metadata:{task_kind:"task"}}]' > "$BEADS_DIR/$1.json"
}

# The comprehensive fixture. Aliases are the qualified <rig>/<pack>.<visit-id>
# form engage writes, so the visit id is the final dot-segment.
build_world() {
  : > "$CALLS"; rm -f "$TMP/beads"/*.json
  visit     tk-closed  closed
  visit     tk-open    in_progress
  visit_obj tk-obj     closed
  visit     tk-attn    closed
  task_bead tk-task    open
  # tk-gone: no fixture file => absent
  {
    printf '{"sessions":['
    sess s-closed        gc-toolkit/gc-toolkit.tk-closed active false false
    printf ','; sess s-open   gc-toolkit/gc-toolkit.tk-open   active false false
    printf ','; sess s-obj    gc-toolkit/gc-toolkit.tk-obj    asleep false false
    printf ','; sess s-gone   gc-toolkit/gc-toolkit.tk-gone   asleep false false
    printf ','; sess s-attn   gc-toolkit/gc-toolkit.tk-attn   active true  false
    printf ','; sess s-task   gc-toolkit/gc-toolkit.tk-task   asleep false false
    printf ','; sess s-noalias null                           asleep false false
    printf ','; sess s-badalias gc-toolkit/gc-toolkit.nodash  asleep false false
    printf ','; sess s-alreadyclosed gc-toolkit/gc-toolkit.tk-closed asleep false true
    printf ','; sess s-notconv gc-toolkit/gc-toolkit.tk-open  active false false gc-toolkit/gc-toolkit.polecat
    printf ']}'
  } > "$SESSIONS_FILE"
}

# --- the main pass ------------------------------------------------------------
build_world
OUT="$(bash "$SUT" 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"

eq "$RC" "0" "a normal pass exits 0"
has "$CLOSED" "close s-closed"  "CLOSED: a closed visit's session is closed"
has "$CLOSED" "close s-gone"    "GONE: a vanished visit's session is closed"
has "$CLOSED" "close s-obj"     "OBJ: a closed visit answered as a bare object is recognised"
hasnt "$CLOSED" "close s-open"  "OPEN: a live hold is kept"
hasnt "$CLOSED" "close s-attn"  "ATTACHED: an attached session is never closed, even with a closed visit"
hasnt "$CLOSED" "close s-task"  "NONVISIT: an alias resolving to a non-visit is left alone"
hasnt "$CLOSED" "close s-noalias" "NOALIAS: a session with no alias is left alone"
hasnt "$CLOSED" "close s-badalias" "BADALIAS: a non-bead-id alias tail is left alone"
hasnt "$CLOSED" "close s-notconv" "NONCONVERSE: a non-converse session is ignored"
hasnt "$CLOSED" "close s-alreadyclosed" "ALREADYCLOSED: an already-closed session is not a candidate"

has "$OUT" "closed 3 settled converse sittings" "COUNTS: three sittings reaped"
has "$OUT" "kept 1 held"    "COUNTS: one live hold kept"
has "$OUT" "skipped 2"      "COUNTS: the non-visit and bad-alias candidates are skipped"

# --- dry-run ------------------------------------------------------------------
build_world
OUT="$(bash "$SUT" --dry-run 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "0" "DRYRUN: exits 0"
eq "$CLOSED" "" "DRYRUN: closes nothing"
has "$OUT" "would close 3 settled converse sittings" "DRYRUN: reports the plan count"
has "$OUT" "s-closed (visit tk-closed closed)" "DRYRUN: names a closed-visit sitting in the plan"
has "$OUT" "s-gone (visit tk-gone gone)" "DRYRUN: names a gone-visit sitting in the plan"

# --- unreadable session listing ----------------------------------------------
build_world
OUT="$(LIST_BROKEN=1 bash "$SUT" 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "1" "UNREADABLE-LIST: a non-JSON session listing aborts with exit 1"
eq "$CLOSED" "" "UNREADABLE-LIST: nothing is closed on an unreadable listing"
has "$OUT" "could not read the session list" "UNREADABLE-LIST: says why"

# --- unreadable visit read (one session) -------------------------------------
build_world
OUT="$(VISIT_BROKEN=tk-closed bash "$SUT" 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "0" "UNREADABLE-VISIT: the pass still completes"
hasnt "$CLOSED" "close s-closed" "UNREADABLE-VISIT: a session whose visit will not read is NOT closed"
has "$CLOSED" "close s-gone" "UNREADABLE-VISIT: other settled sittings are still reaped"

# --- a session that will not close -------------------------------------------
# The close is the one operation this order performs, so a session that fails to
# close is reported on stderr and counted skipped, and must NOT appear among the
# reaped list on stdout — otherwise the summary would claim a slot it never freed.
# stdout and stderr are captured apart: the failure line names the sitting on
# stderr too, so a combined capture could not tell it from a reaped-list entry.
build_world
CLOSE_FAILS='s-closed' bash "$SUT" >"$TMP/cf.out" 2>"$TMP/cf.err"; RC=$?
CF_OUT="$(cat "$TMP/cf.out")"; CF_ERR="$(cat "$TMP/cf.err")"
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "0" "CLOSEFAIL: the pass exits 0"
has "$CF_ERR" "could not close settled sitting s-closed" "CLOSEFAIL: the failure is reported on stderr"
has "$CLOSED" "close s-gone" "CLOSEFAIL: a failed close does not stop the pass"
hasnt "$CF_OUT" "s-closed (visit tk-closed closed)" "CLOSEFAIL: the failed sitting is NOT listed among the reaped"
has "$CF_OUT" "s-gone (visit tk-gone gone)" "CLOSEFAIL: a sitting that did close IS listed"
has "$CF_OUT" "closed 2 settled" "CLOSEFAIL: only the two that closed are counted reaped"
has "$CF_OUT" "skipped 3" "CLOSEFAIL: the failed close is counted skipped, with the non-visit and bad-alias"

# --- a visit read that fails with a NON not-found error is skipped ------------
# `gc bd show` exits non-zero for reasons other than a purged id (a store blip).
# Only bd's not-found signature means gone; any other failure is an unreadable
# probe — kept and counted skipped, never reaped.
: > "$CALLS"; rm -f "$TMP/beads"/*.json
printf '{"sessions":[%s]}' "$(sess s-err gc-toolkit/gc-toolkit.tk-err asleep false false)" > "$SESSIONS_FILE"
OUT="$(VISIT_ERROR=tk-err bash "$SUT" 2>&1)"; RC=$?
CLOSED="$(cat "$CALLS" 2>/dev/null)"
eq "$RC" "0" "OTHERERR: the pass completes"
eq "$CLOSED" "" "OTHERERR: a non not-found visit failure is NOT reaped"
has "$OUT" "closed 0 settled" "OTHERERR: nothing reaped"
has "$OUT" "skipped 1" "OTHERERR: the unreadable visit is counted skipped"

# --- nothing to do ------------------------------------------------------------
: > "$CALLS"
printf '{"sessions":[%s]}' "$(sess s-only gc-toolkit/gc-toolkit.tk-open active false false gc-toolkit/gc-toolkit.polecat)" > "$SESSIONS_FILE"
OUT="$(bash "$SUT" 2>&1)"; RC=$?
eq "$RC" "0" "EMPTY: a city with no converse candidates exits 0"
has "$OUT" "closed 0 settled converse sittings" "EMPTY: reports nothing reaped"

echo ""
echo "converse-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
