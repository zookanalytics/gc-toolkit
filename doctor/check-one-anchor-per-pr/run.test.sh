#!/usr/bin/env bash
# Hermetic test for doctor/check-one-anchor-per-pr (I4). Stub gc/bd only.
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

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/beta"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"},{"name":"beta","path":"$TMP/beta"}]}
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
anchor() { printf '{"id":"%s","status":"open","metadata":{"pr_url":"%s"}}' "$1" "$2"; }
store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.json"; }
clear_stores() { rm -f "$TMP/stores/"*.json; }

# --- 1. unique anchors pass ------------------------------------------------
store alpha "$(anchor a-1 https://x/pr/1)" "$(anchor a-2 https://x/pr/2)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "distinct pr_urls are OK"
has "$OUT" "OK:" "the pass message is the OK line"
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--status open" "the scan asks for open beads only"
has "$ARGS" "--has-metadata-key pr_url" "the scan asks for beads carrying a pr_url"
has "$ARGS" "--limit 0" "the scan is not truncated by a default limit"

# --- 2. two open anchors on one PR, same store -------------------------------
store alpha "$(anchor a-1 https://x/pr/7)" "$(anchor a-2 https://x/pr/7)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "two open anchors naming one PR is an ERROR"
has "$OUT" "https://x/pr/7" "the PR is named"
has "$OUT" "alpha/a-1" "the first anchor is listed"
has "$OUT" "alpha/a-2" "the second anchor is listed"
clear_stores

# --- 3. the twin can live in ANOTHER store -----------------------------------
store alpha "$(anchor a-1 https://x/pr/9)"
store beta  "$(anchor b-1 https://x/pr/9)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "the same PR anchored from two stores is the same defect"
has "$OUT" "alpha/a-1" "the alpha anchor is listed"
has "$OUT" "beta/b-1" "the beta anchor is listed"
clear_stores

# --- 4. an empty pr_url is not a group ----------------------------------------
store alpha "$(anchor a-1 '')" "$(anchor a-2 '')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "beads with an empty pr_url do not group into a finding"

# --- 5. fail-CLOSED --------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns — the twin could be hiding there"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"
clear_stores

# --- 6. an ERROR outranks a WARNING -----------------------------------------
store beta "$(anchor b-1 https://x/pr/3)" "$(anchor b-2 https://x/pr/3)"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "2" "a finding plus an unreadable store still exits ERROR"
clear_stores

echo
echo "check-one-anchor-per-pr: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
