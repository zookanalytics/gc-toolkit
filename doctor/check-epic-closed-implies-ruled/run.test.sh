#!/usr/bin/env bash
# Hermetic test for doctor/check-epic-closed-implies-ruled (I14). Stub gc/bd only.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-epic-ruled-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list")
    rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
# Deliberately looser than bd: it serves the whole store whatever the query
# filters on (the --type=epic / --status closed scoping is bd's, proven here by
# asserting the query shape in BD_ARGS), so a fixture controls exactly the rows.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
printf '%s\n' "$*" >> "${BD_ARGS:-/dev/null}"
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores" BD_ARGS="$TMP/bd-args.log"
run_check() { : > "$BD_ARGS"; RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }
# issue_type is cosmetic here (the check trusts --type=epic from the query); the
# verdict is read from status + metadata.
epic() { printf '{"id":"%s","issue_type":"epic","status":"%s","metadata":%s}' "$1" "$2" "$3"; }
store() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.json"; }

# --- 1. a closed epic ruled close passes, and the query is scoped to epics ----
store "$(epic E1 closed '{"epic_hypothesis":"for X","epic_ruling":"close","epic_ruling_reason":"held"}')" \
      "$(epic E2 closed '{"epic_ruling":"close"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "closed epics ruled close pass"
has "$OUT" "OK:" "the pass message is the OK line"
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--type=epic" "the scan asks only for epics"
has "$ARGS" "--status closed" "the scan asks only for closed epics"
has "$ARGS" "--limit 0" "the scan is not truncated by a default limit"

# --- 2. a STEWARDED (has a hypothesis) closed epic with no ruling is an ERROR -
store "$(epic E3 closed '{"epic_hypothesis":"for X, Y, signal Z"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a stewarded closed epic carrying no epic_ruling is an ERROR"
has "$OUT" "E3" "the unruled epic is named"
has "$OUT" "update E3 --set-metadata epic_ruling=close --set-metadata epic_ruling_reason=" "the remedy records the close ruling and its outcome on the closed epic"
has "$OUT" "reopen E3" "the remedy offers reopening to rule"
hasnt "$OUT" "lifecycle.sh reopen" "the remedy does not offer lifecycle.sh reopen, which refuses an epic"
has "$OUT" "--db $TMP/alpha/.beads" "the remedy names the store the epic lives in"
has "$OUT" "docs/epics.md" "the finding cites the contract"

# --- 2a. a close ruling carries its outcome: a closed epic ruled close with no
# epic_ruling_reason, or one of whitespace alone, is an ERROR naming the field --
store "$(epic E3nr closed '{"epic_hypothesis":"for X","epic_ruling":"close"}')" \
      "$(epic E3ws closed '{"epic_hypothesis":"for X","epic_ruling":"close","epic_ruling_reason":" "}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a closed epic ruled close with no outcome is an ERROR"
has "$OUT" "E3nr" "the outcome-less epic is named"
has "$OUT" "E3ws" "the whitespace-outcome epic is named"
has "$OUT" "no outcome (epic_ruling_reason)" "the finding names the missing outcome field"

# --- 2b. continue and shift keep an epic open: a closed epic carrying either was
# closed on a ruling that does not end it, an ERROR naming the ruling ---------
for r in continue shift; do
  store "$(epic "E3$r" closed "{\"epic_hypothesis\":\"for X\",\"epic_ruling\":\"$r\"}")"
  OUT=$(run_check); RC=$?
  eq "$RC" "2" "a closed epic ruled $r (non-terminal) is an ERROR"
  has "$OUT" "E3$r" "the $r-ruled epic is named"
  has "$OUT" "non-terminal ruling '$r'" "the finding names the non-terminal ruling"
done

# --- 3. an empty epic_ruling reads the same as an absent one ------------------
store "$(epic E4 closed '{"epic_hypothesis":"for X","epic_ruling":""}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an epic_ruling stamped EMPTY is not a ruling"
has "$OUT" "E4" "the empty-ruling epic is named"

# --- 3b. a present-but-off-enum ruling ("pending", a typo) is not a ruling: the
# enum is continue|shift|close (docs/epics.md), so I14 reads it as unruled. -----
store "$(epic E4off closed '{"epic_hypothesis":"for X","epic_ruling":"pending"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an off-enum epic_ruling ('pending') reads as unruled"
has "$OUT" "E4off" "the off-enum epic is named as an error"

# --- 4. a disposed epic carries its own terminal state -----------------------
store "$(epic E5 closed '{"epic_hypothesis":"for X","gc.superseded_by":"s-9"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "gc.superseded_by is the explicit disposition the check accepts"
hasnt "$OUT" "E5" "the disposed epic is not named"
has "$OUT" "retired into a successor" "the disposal is counted"

# --- 5. a closed epic that never entered stewardship (no hypothesis) is exempt,
# so the check ships clean on a pre-stewardship store -------------------------
store "$(epic E5b closed '{}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a pre-stewardship closed epic (no hypothesis) is exempt, not an error"
hasnt "$OUT" "E5b" "the legacy epic is not named"
has "$OUT" "predate epic stewardship" "the legacy exemption is counted"

# --- 6. an open epic is out of scope (only closed epics are judged) -----------
store "$(epic E6 open '{"epic_hypothesis":"for X"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open, unruled epic is not a finding — the ruling is owed only at close"

# --- 7. mixed: only the stewarded unruled one is reported --------------------
store "$(epic E7 closed '{"epic_hypothesis":"for X","epic_ruling":"close","epic_ruling_reason":"disproven"}')" \
      "$(epic E8 closed '{"epic_hypothesis":"for X"}')" \
      "$(epic E9 closed '{}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a mix flags the stewarded unruled epic"
has "$OUT" "E8" "the unruled epic is named"
hasnt "$OUT" "epic E7" "the ruled epic is not named"
hasnt "$OUT" "epic E9" "the legacy epic is not flagged as an error"

# --- 7. fail-CLOSED ----------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failing \`gc rig list\` warns, never passes"
has "$OUT" "cannot determine" "the enumeration failure is named"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"
# A VALID {"error":...} object is bd's shape when a query does not resolve
# (bead-context.sh) — unreadable, not "no epics". `.[]?` would iterate the object
# and the downstream `//` swallow the index error, yielding zero rows at exit 0 and
# a false OK; the type guard makes jq error so the store lands in warnings.
printf '{"error":"ledger unavailable"}' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a store answering with an {error} object warns, never passes"
has "$OUT" "NOT checked" "the error-object store is named as not checked"

# --- 8. offline-safe: the check never calls gh -------------------------------
if grep -qE '(^|[^a-z])gh[[:space:]]' < <(grep -vE '^[[:space:]]*#' "$CHECK"); then
    bad "the check shells out to gh — it is specified ledger-only"
else
    ok "the check is ledger-only (no gh calls)"
fi

echo
echo "check-epic-closed-implies-ruled: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
