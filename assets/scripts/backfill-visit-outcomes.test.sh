#!/usr/bin/env bash
# backfill-visit-outcomes.test.sh — the one-shot legacy-visit outcome backfill
# (assets/scripts/backfill-visit-outcomes.sh): it selects the doctor set
# (task_kind=visit, closed, empty gc.outcome) plus any half-landed row (its
# gc.outcome carries this run's word but gc.outcome_reason is not the reason
# derived from close_reason), stamps both keys, reads them back, and converges
# so a settled store stamps nothing. Dry-run writes nothing; --apply writes
# and verifies.
#
# Hermetic: stubs gc, reads the repo only; no city, no network.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/backfill-visit-outcomes.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1" "missing '$3' in: $2"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1" "found '$3'"; else ok "$1"; fi; }

[ -r "$SUT" ] || { printf 'backfill: cannot read %s\n' "$SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'backfill: jq is required\n' >&2; exit 1; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-backfill-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; STATE="$TMPD/state"; FIX="$TMPD/fix"
mkdir -p "$BIN" "$STATE" "$FIX"

# Fixtures, one JSON array per store, chosen by the --db basename. ACTIVE holds
# two misses (one with a close_reason, one without), plus three beads that must
# be ignored: an already-stamped closed visit, an open visit, and a closed
# non-visit. CLEAN holds only a non-miss. jq in the stub reads $FIX/<key>.json.
cat >"$FIX/active.json" <<'JSON'
[
 {"id":"v-dup","status":"closed","close_reason":"duplicate of v-root; already tracked","metadata":{"task_kind":"visit"}},
 {"id":"v-bare","status":"closed","close_reason":"","metadata":{"task_kind":"visit"}},
 {"id":"v-stamped","status":"closed","close_reason":"was moot","metadata":{"task_kind":"visit","gc.outcome":"moot"}},
 {"id":"v-open","status":"open","close_reason":"","metadata":{"task_kind":"visit"}},
 {"id":"t-task","status":"closed","close_reason":"done","metadata":{"task_kind":"task"}}
]
JSON
cat >"$FIX/clean.json" <<'JSON'
[
 {"id":"v-ok","status":"closed","close_reason":"was benign","metadata":{"task_kind":"visit","gc.outcome":"benign"}}
]
JSON
# HALF holds three rows that all already carry our gc.outcome, to exercise the
# half-landed-repair path: v-half lost its reason (empty), v-drift has a reason
# that no longer matches the one derived from close_reason, and v-done is fully
# and correctly stamped. The selector must re-pick the first two and leave
# v-done alone — the doctor's empty-outcome set catches none of them.
cat >"$FIX/half.json" <<'JSON'
[
 {"id":"v-half","status":"closed","close_reason":"was superseded by v-root","metadata":{"task_kind":"visit","gc.outcome":"unrecorded","gc.outcome_reason":""}},
 {"id":"v-drift","status":"closed","close_reason":"was folded into v-root","metadata":{"task_kind":"visit","gc.outcome":"unrecorded","gc.outcome_reason":"stale headline"}},
 {"id":"v-done","status":"closed","close_reason":"was moot","metadata":{"task_kind":"visit","gc.outcome":"unrecorded","gc.outcome_reason":"was moot"}}
]
JSON

# A stub gc. `bd update ... --db D <id> --set-metadata gc.outcome=..` records the
# stamp under $STATE keyed by db+id; `bd show` reflects it back so the SUT's
# read-back sees exactly what it wrote. FAIL_STAMP makes update a silent no-op
# (exit 0, nothing recorded) to exercise the read-back guard. `bd list` returns
# the fixture named by the --db basename. `rig list` names two active rigs and
# one suspended.
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
key() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }
dbof() { local p=""; while [ $# -gt 0 ]; do [ "$1" = "--db" ] && { shift; p="$1"; break; }; shift; done; printf '%s' "$p"; }
case "${1:-}" in
  rig)
    [ "${2:-}" = "list" ] || exit 2
    jq -nc '{rigs:[
       {name:"active",path:env.DIR_ACTIVE,suspended:false},
       {name:"clean",path:env.DIR_CLEAN,suspended:false},
       {name:"napping",path:"/nope",suspended:true}]}' ;;
  bd)
    case "${2:-}" in
      list)
        db="$(dbof "$@")"
        case "$db" in
          *active*) cat "$FIX/active.json" ;;
          *clean*)  cat "$FIX/clean.json" ;;
          *half*)   cat "$FIX/half.json" ;;
          *)        printf '[]' ;;
        esac ;;
      update)
        db="$(dbof "$@")"; id="$3"
        printf 'update db=%s id=%s %s\n' "$db" "$id" "$*" >>"$UPDLOG"
        [ -n "${FAIL_STAMP:-}" ] && exit 0
        k="$(key "$db|$id")"
        for a in "$@"; do case "$a" in
          gc.outcome=*)        printf '%s' "${a#gc.outcome=}" >"$STATE/$k.o" ;;
          gc.outcome_reason=*) printf '%s' "${a#gc.outcome_reason=}" >"$STATE/$k.r" ;;
        esac; done ;;
      show)
        db="$(dbof "$@")"; id="$3"; k="$(key "$db|$id")"
        jq -nc --arg o "$(cat "$STATE/$k.o" 2>/dev/null)" --arg r "$(cat "$STATE/$k.r" 2>/dev/null)" \
          '[{id:"x",status:"closed",metadata:{"gc.outcome":$o,"gc.outcome_reason":$r}}]' ;;
      *) exit 2 ;;
    esac ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"

DIR_ACTIVE="$FIX/store-active"; DIR_CLEAN="$FIX/store-clean"; DIR_HALF="$FIX/store-half"
DB_ACTIVE="$DIR_ACTIVE/.beads"; DB_CLEAN="$DIR_CLEAN/.beads"; DB_HALF="$DIR_HALF/.beads"
UPDLOG="$TMPD/updlog"

run() { # run the SUT with the stub on PATH and a fresh update log
  : >"$UPDLOG"
  PATH="$BIN:$PATH" FIX="$FIX" STATE="$STATE" UPDLOG="$UPDLOG" \
    DIR_ACTIVE="$DIR_ACTIVE" DIR_CLEAN="$DIR_CLEAN" \
    FAIL_STAMP="${FAIL_STAMP:-}" bash "$SUT" "$@" 2>&1
}
stamped() { cat "$STATE/$(printf '%s' "$1|$2" | tr -c 'A-Za-z0-9' '_').o" 2>/dev/null; }
reasonof() { cat "$STATE/$(printf '%s' "$1|$2" | tr -c 'A-Za-z0-9' '_').r" 2>/dev/null; }

echo "backfill-visit-outcomes.test"

# --- dry-run: selects the two misses, writes nothing ---------------------------
OUT="$(run --db "$DB_ACTIVE")"; RC=$?
is   "dry-run exits 0"                       "$RC" "0"
has  "dry-run counts both misses"            "$OUT" "2 closed visit(s) to stamp"
has  "dry-run names v-dup"                   "$OUT" "would stamp v-dup"
has  "dry-run names v-bare"                  "$OUT" "would stamp v-bare"
hasnt "dry-run ignores the already-stamped"  "$OUT" "v-stamped"
hasnt "dry-run ignores the open visit"       "$OUT" "v-open"
hasnt "dry-run ignores the non-visit"        "$OUT" "t-task"
is   "dry-run writes nothing"                "$(wc -l <"$UPDLOG" | tr -d ' ')" "0"

# --- apply: stamps both, preserving close_reason and using the fallback --------
OUT="$(run --apply --db "$DB_ACTIVE")"; RC=$?
is  "apply exits 0"                          "$RC" "0"
has "apply reports 2 stamped"               "$OUT" "stamped 2/2"
is  "v-dup outcome is unrecorded"           "$(stamped "$DB_ACTIVE" v-dup)"  "unrecorded"
is  "v-dup reason is its close_reason"      "$(reasonof "$DB_ACTIVE" v-dup)" "duplicate of v-root; already tracked"
is  "v-bare outcome is unrecorded"          "$(stamped "$DB_ACTIVE" v-bare)" "unrecorded"
is  "v-bare empty close_reason -> fallback" "$(reasonof "$DB_ACTIVE" v-bare)" "closed with no recorded close_reason"
is  "v-stamped never written"               "$(stamped "$DB_ACTIVE" v-stamped)" ""

# --- custom --outcome word -----------------------------------------------------
rm -f "$STATE"/*; OUT="$(run --apply --outcome legacy --db "$DB_ACTIVE")"
is  "custom word stamped"                    "$(stamped "$DB_ACTIVE" v-dup)" "legacy"

# --- read-back failure -> exit 1 -----------------------------------------------
rm -f "$STATE"/*
OUT="$(FAIL_STAMP=1 run --apply --db "$DB_ACTIVE")"; RC=$?
is  "read-back failure exits 1"              "$RC" "1"
has "read-back failure is reported"          "$OUT" "did NOT read back"

# --- half-landed repair: a stamp whose gc.outcome landed but whose reason was
# --- lost (empty) or drifted is re-selected and repaired; a row already holding
# --- the derived reason is left untouched, so repeated runs converge. Without
# --- this the doctor's empty-outcome set never sees the half-landed row again. --
rm -f "$STATE"/*
OUT="$(run --db "$DB_HALF")"; RC=$?
is    "half-landed dry-run exits 0"          "$RC" "0"
has   "empty reason is re-selected"          "$OUT" "would stamp v-half"
has   "drifted reason is re-selected"        "$OUT" "would stamp v-drift"
hasnt "matching reason is left alone"        "$OUT" "v-done"
has   "half-landed counts the two repairs"   "$OUT" "2 closed visit(s) to stamp"
OUT="$(run --apply --db "$DB_HALF")"; RC=$?
is    "half-landed apply exits 0"            "$RC" "0"
has   "half-landed apply stamps both"        "$OUT" "stamped 2/2"
is    "empty reason repaired from close"     "$(reasonof "$DB_HALF" v-half)"  "was superseded by v-root"
is    "drifted reason overwritten"           "$(reasonof "$DB_HALF" v-drift)" "was folded into v-root"
is    "matching-reason row never written"    "$(stamped "$DB_HALF" v-done)"   ""

# --- clean store: nothing to do, exit 0 ----------------------------------------
OUT="$(run --apply --db "$DB_CLEAN")"; RC=$?
is  "clean store exits 0"                    "$RC" "0"
has "clean store reported clean"             "$OUT" "clean"

# --- rig discovery + --rig filter + suspended skip -----------------------------
OUT="$(run)"; RC=$?
is  "discovery exits 0"                      "$RC" "0"
has "discovery scans active"                 "$OUT" "active: 2 closed visit(s) to stamp"
has "discovery scans clean"                  "$OUT" "clean: clean"
hasnt "discovery skips suspended rig"        "$OUT" "napping"
OUT="$(run --rig active)"
has "--rig limits to that rig"               "$OUT" "active: 2 closed visit(s) to stamp"
hasnt "--rig excludes the other"             "$OUT" "clean:"

echo "  ---- $PASS passed, $FAIL failed ----"
[ "$FAIL" -eq 0 ]
