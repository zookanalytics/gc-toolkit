#!/usr/bin/env bash
# gc-helm-handback.test.sh — the handback verb: a converse sitting records the
# hand-back it is posting, read from stdin, on its visit, so engage can print
# the sitting's last words in the operator's tab once the sitting has ended.
#
# Runs the REAL gc-helm.sh (via `sh`, as shipped) with a stubbed `gc` on PATH
# that keeps each written metadata value, so the verb's read-back reads what
# its own write stored. Covered:
#   (RECORD)   a multi-line hand-back lands whole, as gc.handback beside
#              gc.handback_at, in one write pinned at the visit's rig store
#   (REPLACE)  a second record replaces the first
#   (REPAIR)   a write that reads back without its value is written once more
#   (NOLAND)   a value that never reads back exits 4 and says so
#   (EMPTY)    an empty or blank stdin is refused (exit 2) and writes nothing
#   (NOTVISIT) a bead that is not a visit is refused (exit 2) and writes nothing
#   (NOARG)    no visit id is refused (exit 2)
#   (MISSING)  a visit that does not resolve exits 4 through verify_subject
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-handback.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()     { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()    { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()     { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()    { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnot() { case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin" "$TMP/rig/.beads" "$TMP/meta"
export RIG_PATH="$TMP/rig"

# --- gc stub ------------------------------------------------------------------
# One rig (prefix tk). `bd show` answers tk-vis as a visit and tk-task as a
# plain task, each carrying the metadata the stub's store holds: one file per
# key under $META. `bd update --set-metadata k=v` writes those files, except
# that $DROP_WRITES (a count) makes that many writes exit 0 and store nothing,
# the store behaviour the read-back exists for. Every update is logged, one
# argv element per line between markers, to $CALLS.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "${1:-} ${2:-}" in
  "rig list")
    jq -n --arg p "$RIG_PATH" '{rigs:[{name:"gc-toolkit", path:$p, prefix:"tk"}]}' ;;
  "bd show")
    id="$3"
    case "$id" in
      tk-vis|tk-task)
        kind=visit; [ "$id" = tk-task ] && kind=task
        meta=$(jq -n --arg k "$kind" '{task_kind:$k}')
        for f in "$META"/*; do
          [ -f "$f" ] || continue
          meta=$(printf '%s' "$meta" | jq --arg k "${f##*/}" --rawfile v "$f" '. + {($k): $v}')
        done
        jq -n --arg i "$id" --argjson m "$meta" '[{id:$i, title:"a bead", status:"in_progress", assignee:"s1", metadata:$m}]' ;;
      *) printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1 ;;
    esac ;;
  "bd update")
    { echo "<<update"; printf '%s\n' "$@"; echo "update>>"; } >> "$CALLS"
    if [ "${DROP_WRITES:-0}" -gt 0 ]; then
      n=$(( $(cat "$DROPPED" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$DROPPED"
      [ "$n" -le "$DROP_WRITES" ] && exit 0
    fi
    shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) kv="$2"; printf '%s' "${kv#*=}" > "$META/${kv%%=*}"; shift 2 ;;
        *) shift ;;
      esac
    done ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export CALLS="$TMP/calls" META="$TMP/meta" DROPPED="$TMP/dropped"
unset GC_HELM_FIXTURE || true
export TMPDIR="$TMP"

# run_handback <stdin-text> <args…> -> RC / OUT (stdout+stderr) / CALLED
run_handback() {
    _in="$1"; shift
    : > "$CALLS"; rm -f "$DROPPED"
    RC=0
    OUT="$(printf '%s' "$_in" | sh "$SCRIPT" handback "$@" 2>&1)" || RC=$?
    CALLED="$(cat "$CALLS")"
}
stored() { cat "$META/$1" 2>/dev/null; }

HB1='tk-subj — the board redesign

The new layout ships behind a flag, so nothing changes for anyone until it is
turned on. The recommendation is to turn it on for the operator first.

Recommendation: turn the flag on for one week, then decide.'

echo "── handback records the hand-back whole ──"
run_handback "$HB1
" tk-vis
eq "$RC" 0 "(RECORD) a hand-back on a visit exits 0"
eq "$(stored gc.handback)" "$HB1" "(RECORD) the stored hand-back is the text as piped in, every line of it"
case "$(stored gc.handback_at)" in
  20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z) ok "(RECORD) gc.handback_at is a UTC timestamp" ;;
  *) bad "(RECORD) gc.handback_at is a UTC timestamp (got '$(stored gc.handback_at)')" ;;
esac
eq "$(printf '%s\n' "$CALLED" | grep -c '^<<update$')" "1" "(RECORD) one write lands it"
has "$CALLED" "$(printf -- '--db\n%s/rig/.beads' "$TMP")" "(RECORD) the write is pinned at the visit's rig store"
has "$OUT" "recorded on tk-vis" "(RECORD) the verb says where it recorded"

echo "── a later hand-back replaces the earlier one ──"
HB2='tk-subj — the board redesign

Settled: the flag is on for the operator, and the rest wait a week.'
run_handback "$HB2" tk-vis
eq "$RC" 0 "(REPLACE) the second record exits 0"
eq "$(stored gc.handback)" "$HB2" "(REPLACE) the visit now carries the second hand-back"

echo "── the write is read back ──"
rm -f "$META"/*
DROP_WRITES=1 run_handback "$HB1" tk-vis
eq "$RC" 0 "(REPAIR) a write that stored nothing is repaired, and the verb exits 0"
eq "$(printf '%s\n' "$CALLED" | grep -c '^<<update$')" "2" "(REPAIR) …by one more write"
eq "$(stored gc.handback)" "$HB1" "(REPAIR) …and the hand-back is stored"
rm -f "$META"/*
DROP_WRITES=5 run_handback "$HB1" tk-vis
eq "$RC" 4 "(NOLAND) a hand-back that never reads back exits 4"
has "$OUT" "did not read back on tk-vis" "(NOLAND) …and says it did not land"
eq "$(printf '%s\n' "$CALLED" | grep -c '^<<update$')" "2" "(NOLAND) …after the one repair write"

echo "── refusals write nothing ──"
run_handback "" tk-vis
eq "$RC" 2 "(EMPTY) an empty stdin exits 2"
eq "$CALLED" "" "(EMPTY) …and writes nothing"
run_handback "

" tk-vis
eq "$RC" 2 "(EMPTY) a blank stdin exits 2"
eq "$CALLED" "" "(EMPTY) …and writes nothing"
run_handback "$HB1" tk-task
eq "$RC" 2 "(NOTVISIT) a bead that is not a visit exits 2"
has "$OUT" "is not a visit" "(NOTVISIT) …and says why"
eq "$CALLED" "" "(NOTVISIT) …and writes nothing"
run_handback "$HB1"
eq "$RC" 2 "(NOARG) no visit id exits 2"
eq "$CALLED" "" "(NOARG) …and writes nothing"
run_handback "$HB1" tk-gone
eq "$RC" 4 "(MISSING) a visit that does not resolve exits 4"
has "$OUT" "bead not found" "(MISSING) …reported by the shared subject check"
eq "$CALLED" "" "(MISSING) …and writes nothing"

echo
echo "gc-helm handback: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
