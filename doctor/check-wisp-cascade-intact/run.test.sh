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

# Canonical tuple per constraint, matching the four constrained city stores. A
# store lists a constraint by name (correct tuple) or name:field=value to seed a
# single wrong field for the full-tuple check.
declare -A C_TBL=(
    [fk_wisp_labels_issue]=wisp_labels
    [fk_wisp_events_issue]=wisp_events
    [fk_wisp_comments_issue]=wisp_comments
    [fk_wisp_child_counters_parent]=wisp_child_counters
)
declare -A C_COL=(
    [fk_wisp_labels_issue]=issue_id
    [fk_wisp_events_issue]=issue_id
    [fk_wisp_comments_issue]=issue_id
    [fk_wisp_child_counters_parent]=parent_id
)

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
  *REFERENTIAL_CONSTRAINTS*)
      # $name.fks holds one TAB-separated tuple per constraint:
      # name<TAB>tbl<TAB>col<TAB>ref_tbl<TAB>ref_col<TAB>del_rule<TAB>upd_rule
      f="$STORES/$name.fks"
      printf '['; sep=""
      if [ -f "$f" ]; then
          while IFS=$'\t' read -r cn ctbl ccol crtbl crcol cdel cupd; do
              [ -n "$cn" ] || continue
              printf '%s{"name":"%s","tbl":"%s","col":"%s","ref_tbl":"%s","ref_col":"%s","del_rule":"%s","upd_rule":"%s"}' \
                  "$sep" "$cn" "$ctbl" "$ccol" "$crtbl" "$crcol" "$cdel" "$cupd"; sep=","
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
# store <name> <entry>... — the constraints that store reports. Each entry is a
# constraint name (canonical tuple) or name:field=value overriding one field of
# it (field in tbl,col,ref_tbl,ref_col,del,upd). A store named here always has a
# wisps table unless plane_off is called for it.
store() {
    local n="$1"; shift
    : > "$STORES/$n.fks"; : > "$STORES/$n.plane"
    local entry name over key val tbl col rtbl rcol del upd
    for entry in "$@"; do
        name="${entry%%:*}"; over=""
        [ "$entry" != "$name" ] && over="${entry#*:}"
        tbl="${C_TBL[$name]}"; col="${C_COL[$name]}"; rtbl=wisps; rcol=id; del=CASCADE; upd=CASCADE
        if [ -n "$over" ]; then
            key="${over%%=*}"; val="${over#*=}"
            case "$key" in
                tbl) tbl="$val" ;; col) col="$val" ;;
                ref_tbl) rtbl="$val" ;; ref_col) rcol="$val" ;;
                del) del="$val" ;; upd) upd="$val" ;;
                *) echo "store: unknown override '$key'" >&2; return 2 ;;
            esac
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$tbl" "$col" "$rtbl" "$rcol" "$del" "$upd" >> "$STORES/$n.fks"
    done
}
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
has "$OUT" "4 of 4" "the finding counts every missing constraint"
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

# --- 9. a misspelled severity refuses rather than silently warning -------------
rigs alpha
store alpha
OUT=$(GC_DOCTOR_WISP_CASCADE_SEVERITY=err run_check); RC=$?
eq "$RC" "1" "an unrecognised severity refuses instead of guessing"
has "$OUT" "neither warn nor error" "the refusal names the bad value"
hasnt "$OUT" "ADD CONSTRAINT" "the refusal happens before any store is read"

# --- 10. a present constraint whose tuple is wrong is a finding ----------------
# Every name is present in each case, so a names-only check would pass them all;
# asserting the full tuple is what catches a foreign key that exists but does
# not cascade. One field wrong at a time, so each field's comparison is proven
# load-bearing — drop any one and the matching case stops reporting.
for bad in \
    "del=RESTRICT|ON DELETE=RESTRICT" \
    "upd=RESTRICT|ON UPDATE=RESTRICT" \
    "col=wisp_id|column=wisp_id" \
    "tbl=wisp_event|table=wisp_event" \
    "ref_tbl=issues|references=issues" \
    "ref_col=uuid|referenced column=uuid"; do
    override="${bad%%|*}"; needle="${bad##*|}"
    rigs alpha
    store alpha fk_wisp_labels_issue fk_wisp_comments_issue fk_wisp_child_counters_parent "fk_wisp_events_issue:$override"
    OUT=$(run_check); RC=$?
    eq    "$RC" "1"                     "a present constraint with $override warns (its name alone would pass)"
    has   "$OUT" "fk_wisp_events_issue" "the finding names the non-cascading constraint ($override)"
    has   "$OUT" "$needle"             "the finding names the field that diverges ($override)"
    hasnt "$OUT" "no wisp plane"       "a present-but-wrong constraint is not read as a missing plane ($override)"
done

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
