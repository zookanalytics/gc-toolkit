#!/usr/bin/env bash
# Hermetic test for doctor/check-wisp-cascade-intact. Stub gc/bd.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

ALL="fk_wisp_labels_issue fk_wisp_events_issue fk_wisp_comments_issue fk_wisp_child_counters_parent"

mkdir -p "$TMP/bin" "$TMP/stores"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)     shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
db=""; prev=""; query=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; query="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
# The check issues exactly two queries; tell them apart by the table each reads.
case "$query" in
  *TABLE_CONSTRAINTS*)
      f="$STORES/$name.fks"
      printf '['; sep=""
      if [ -f "$f" ]; then
          while IFS= read -r c; do
              [ -n "$c" ] || continue
              printf '%s{"CONSTRAINT_NAME":"%s"}' "$sep" "$c"; sep=","
          done < "$f"
      fi
      printf ']'
      ;;
  *INFORMATION_SCHEMA.TABLES*)
      n=0; [ -f "$STORES/$name.plane" ] && n=1
      printf '[{"n":%s}]' "$n"
      ;;
  *) printf '[]' ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

run_check() { RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }

# rigs <name>[:suspended] ... — writes the rig list the check enumerates.
rigs() {
    local out="" sep="" spec name susp
    for spec in "$@"; do
        name="${spec%%:*}"; susp=false
        [ "$spec" != "$name" ] && susp=true
        out="$out$sep{\"name\":\"$name\",\"path\":\"$TMP/$name\",\"suspended\":$susp}"
        sep=","
    done
    printf '{"rigs":[%s]}' "$out" > "$TMP/rigs.json"
}
# store <name> <constraint>... — the constraints that store reports. A store
# named here always has a wisps table unless plane_off is called for it.
store() { local n="$1"; shift; : > "$STORES/$n.fks"; printf '%s\n' "$@" >> "$STORES/$n.fks"; : > "$STORES/$n.plane"; }
plane_off() { rm -f "$STORES/$1.plane"; }

# --- 1. every store fully constrained passes ----------------------------------
rigs alpha beta
store alpha $ALL
store beta $ALL
OUT=$(run_check); RC=$?
eq "$RC" "0" "a city whose every store carries all four constraints passes"
has "$OUT" "OK:" "the pass message is the OK line"

# --- 2. one missing constraint is a finding -----------------------------------
rigs alpha beta
store alpha $ALL
store beta fk_wisp_labels_issue fk_wisp_events_issue fk_wisp_comments_issue
OUT=$(run_check); RC=$?
eq "$RC" "1" "a store missing one constraint warns at the default severity"
has "$OUT" "beta" "the finding names the store"
has "$OUT" "fk_wisp_child_counters_parent" "the finding names the missing constraint"
hasnt "$OUT" "alpha:" "the fully-constrained store is not reported"

# --- 3. all four missing, wisp plane present ----------------------------------
rigs alpha
store alpha
OUT=$(run_check); RC=$?
eq "$RC" "1" "a store with a wisp plane and no constraints is a finding"
has "$OUT" "missing 4" "the finding counts every missing constraint"
has "$OUT" "ADD CONSTRAINT" "the finding carries the repair"
has "$OUT" "purge" "the finding says the repair follows a purge of the orphan rows"

# --- 4. all four missing, no wisp plane at all --------------------------------
rigs alpha
store alpha
plane_off alpha
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store carrying no wisp plane passes"
has "$OUT" "no wisp plane" "the storeless case is a note, not a finding"

# --- 5. an unreadable store never passes --------------------------------------
rigs alpha beta
store alpha $ALL
store beta $ALL
OUT=$(BD_FAIL_STORE=beta run_check); RC=$?
eq "$RC" "1" "a store that cannot be read warns rather than passing"
has "$OUT" "NOT checked" "the warning says the store was not checked"
has "$OUT" "beta" "the unreadable store is named"

# --- 6. a suspended store is skipped, not queried ------------------------------
rigs alpha beta:suspended
store alpha $ALL
store beta
OUT=$(run_check); RC=$?
eq "$RC" "0" "a suspended store is skipped, so its empty constraint set is not a finding"
has "$OUT" "suspended" "the skip says why"

# --- 7. the severity override raises a finding to an error ---------------------
rigs alpha
store alpha
OUT=$(GC_DOCTOR_WISP_CASCADE_SEVERITY=error run_check); RC=$?
eq "$RC" "2" "the severity override reports a missing constraint as an error"
has "$OUT" "not enforced" "the error message differs from the warning message"

# --- 8. an unusable rig list never reads as a clean city -----------------------
rigs alpha
store alpha $ALL
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed rig enumeration warns rather than passing"
has "$OUT" "cannot determine" "the message says the store set is unknown"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
