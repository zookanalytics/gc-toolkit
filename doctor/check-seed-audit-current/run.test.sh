#!/usr/bin/env bash
# Hermetic test for doctor/check-seed-audit-current. Fixture pack + stub renderer.
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

P="$TMP/pack"
mkdir -p "$P/assets/scripts" "$P/generated/seed-audit/agents" "$P/generated/seed-audit/formulas"
# Stub renderer: --print-digest answers from $DIGEST so tests steer it.
cat > "$P/assets/scripts/render-seed-audit.sh" <<'R'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "--print-digest" ] && { printf '%s' "${DIGEST:-}"; exit 0; }; done
exit 0
R
chmod +x "$P/assets/scripts/render-seed-audit.sh"
index() { # <digest>
    { echo "# seed audit"; echo "- source digest: \`$1\`"; echo "- \`gc\` version: \`gc v1\`"; } \
        > "$P/generated/seed-audit/INDEX.md"
}
printf 'p\n' > "$P/generated/seed-audit/agents/worker.md"
printf 'f\n' > "$P/generated/seed-audit/formulas/mol-x.md"
run_check() { DIGEST="${DIGEST:-}" GC_PACK_DIR="$P" bash "$CHECK" 2>&1; }

# --- 1. current digest passes -------------------------------------------------
index d1
OUT=$(DIGEST=d1 run_check); RC=$?
eq "$RC" "0" "a matching digest is OK"
has "$OUT" "1 agent prompt(s), 1 formula recipe(s)" "the summary counts the artifact"

# --- 2. stale digest is an ERROR ------------------------------------------------
OUT=$(DIGEST=d2 run_check); RC=$?
eq "$RC" "2" "a digest mismatch is an ERROR"
has "$OUT" "STALE" "the message says the audit is stale"
has "$OUT" "recorded digest: d1" "the recorded digest is shown"
has "$OUT" "actual digest:   d2" "the actual digest is shown"

# --- 3. ABSENT audit is a WARNING (fresh clone before first render) ---------------
rm -rf "$P/generated"
OUT=$(DIGEST=d1 run_check); RC=$?
eq "$RC" "1" "an entirely absent audit WARNS rather than erroring"
has "$OUT" "ABSENT" "the message says the audit is absent"
has "$OUT" "fresh clone" "the message explains the expected case"
mkdir -p "$P/generated/seed-audit/agents" "$P/generated/seed-audit/formulas"
printf 'p\n' > "$P/generated/seed-audit/agents/worker.md"
printf 'f\n' > "$P/generated/seed-audit/formulas/mol-x.md"

# --- 4. an INDEX with no digest line is an ERROR (unverifiable) ---------------------
printf '# seed audit, hand-mangled\n' > "$P/generated/seed-audit/INDEX.md"
OUT=$(DIGEST=d1 run_check); RC=$?
eq "$RC" "2" "an INDEX recording no source digest is an ERROR"
has "$OUT" "UNVERIFIABLE" "the message says staleness cannot be checked at all"

# --- 5. a dark digest signal warns ---------------------------------------------------
index d1
OUT=$(DIGEST= run_check); RC=$?
eq "$RC" "1" "a renderer that prints no digest warns, never passes"
has "$OUT" "UNVERIFIED" "the message says the signal is dark"

# --- 6. a non-executable renderer still checks, but warns -------------------------------
chmod -x "$P/assets/scripts/render-seed-audit.sh"
OUT=$(DIGEST=d1 run_check); RC=$?
eq "$RC" "1" "a shipped-but-not-executable renderer is a warning"
has "$OUT" "NOT executable" "the mode bit is named"
OUT=$(DIGEST=d2 run_check); RC=$?
eq "$RC" "2" "staleness is still detected through bash despite the mode bit"
chmod +x "$P/assets/scripts/render-seed-audit.sh"

# --- 7. no renderer shipped = nothing to keep current -------------------------------------
rm "$P/assets/scripts/render-seed-audit.sh"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a pack shipping no renderer has nothing to keep current"

echo
echo "check-seed-audit-current: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
