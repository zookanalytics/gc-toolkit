#!/usr/bin/env bash
# Hermetic test for doctor/check-closed-implies-landed (I5). Stub gc/bd only.
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

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
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
bead() { printf '{"id":"%s","status":"closed","metadata":%s}' "$1" "$2"; }
store() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.json"; }

# --- 1. healthy terminal shapes pass -----------------------------------------
store "$(bead c-1 '{"merge_result":"merged","merged_sha":"abc123"}')" \
      "$(bead c-2 '{"merge_result":"abandoned"}')" \
      "$(bead c-3 '{"merge_result":"blocked"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "merged+sha and explicit terminal states pass"
has "$OUT" "OK:" "the pass message is the OK line"
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--status closed" "the scan asks for CLOSED beads"
has "$ARGS" "--has-metadata-key merge_result" "the scan asks for anchors only"
has "$ARGS" "--limit 0" "the scan is not truncated by a default limit"

# --- 2. closed but not landed (the 2026-08-23 shape) --------------------------
store "$(bead c-4 '{"merge_result":"pull_request","pr_url":"https://x/pr/4"}')" \
      "$(bead c-5 '{"merge_result":"pre_open_gate"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "closed with merge_result=pull_request/pre_open_gate is an ERROR"
has "$OUT" "c-4" "the pull_request husk is named"
has "$OUT" "https://x/pr/4" "the stranded PR is named"
has "$OUT" "c-5" "the pre_open_gate husk is named"

# --- 3. merged with no evidence -----------------------------------------------
store "$(bead c-6 '{"merge_result":"merged"}')"
OUT=$(run_check); RC=$?
eq "$RC" "1" "closed merged with NO merged_sha is a WARNING, not an error"
has "$OUT" "c-6" "the unevidenced landing is named"
has "$OUT" "merged_sha" "the warning names the missing evidence"

# --- 4. unanchored closed beads are out of scope --------------------------------
store "$(bead c-7 '{"merge_result":""}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an empty merge_result on a closed bead is not a finding here"

# --- 5. fail-CLOSED ------------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"

# --- 6. offline-safe: the check never calls gh ----------------------------------
if grep -vE '^[[:space:]]*#' "$CHECK" | grep -qE '(^|[^a-z])gh[[:space:]]'; then
    bad "the check shells out to gh — it is specified ledger-only"
else
    ok "the check is ledger-only (no gh calls)"
fi

echo
echo "check-closed-implies-landed: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
