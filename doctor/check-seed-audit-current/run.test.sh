#!/usr/bin/env bash
# Hermetic test for doctor/check-seed-audit-current. Fixture pack + stub renderer.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-seed-audit-current-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

P="$TMP/pack"
mkdir -p "$P/assets/scripts" "$P/generated/seed-audit/agents" "$P/generated/seed-audit/formulas"
# The upkeep arm sits behind a rev-parse guard: without a real repo it is
# skipped, and "hook wired" then reports a read that never happened.
git init -q -b main "$P"
git -C "$P" config core.hooksPath assets/hooks
# Stub renderer: records every invocation and answers nothing. The check judges
# no staleness, so any call it makes is a render or a manifest read it does not
# owe, and the log is how case 7 sees one.
RENDERER_LOG="$TMP/renderer.log"
: > "$RENDERER_LOG"
cat > "$P/assets/scripts/render-seed-audit.sh" <<R
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$RENDERER_LOG"
exit 1
R
chmod +x "$P/assets/scripts/render-seed-audit.sh"
printf '# seed audit\n' > "$P/generated/seed-audit/INDEX.md"
printf 'p\n' > "$P/generated/seed-audit/agents/worker.md"
printf 'f\n' > "$P/generated/seed-audit/formulas/mol-x.md"
# core.hooksPath resolves local-then-global, so an operator with a global one
# set would answer case 5's unset read; /dev/null pins the fixture to local.
run_check() { GC_PACK_DIR="$P" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$CHECK" 2>&1; }

# --- 1. a present audit with its hook wired passes ----------------------------
OUT=$(run_check); RC=$?
eq "$RC" "0" "a present audit with the hook wired is OK"
has "$OUT" "1 agent prompt(s), 1 formula recipe(s)" "the summary counts the artifact"
has "$OUT" "hook wired" "the green line reports an upkeep read it actually made"

# --- 2. ABSENT audit is a WARNING (fresh clone before first render) -----------
mv "$P/generated" "$TMP/generated.away"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an entirely absent audit WARNS rather than erroring"
has "$OUT" "ABSENT" "the message says the audit is absent"
has "$OUT" "fresh clone" "the message explains the expected case"
mv "$TMP/generated.away" "$P/generated"

# --- 3. a non-executable renderer warns ---------------------------------------
chmod -x "$P/assets/scripts/render-seed-audit.sh"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a shipped-but-not-executable renderer is a warning"
has "$OUT" "NOT executable" "the mode bit is named"
chmod +x "$P/assets/scripts/render-seed-audit.sh"

# --- 4. a hook wired somewhere else warns -------------------------------------
git -C "$P" config core.hooksPath .githooks
OUT=$(run_check); RC=$?
eq "$RC" "1" "a hooksPath pointing somewhere else warns"
has "$OUT" 'core.hooksPath is ".githooks", not assets/hooks' "the configured path is named once"
has "$OUT" "upkeep is not fully wired" "the summary separates upkeep from content"
git -C "$P" config core.hooksPath assets/hooks

# --- 5. no hook wired at all warns --------------------------------------------
git -C "$P" config --unset core.hooksPath
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unset hooksPath warns"
has "$OUT" "core.hooksPath is unset, not assets/hooks" "the unset case reads as one value"
git -C "$P" config core.hooksPath assets/hooks

# --- 6. a manifest decides nothing --------------------------------------------
# The audit commits no SOURCES.txt, and one left behind describes inputs nobody
# compares any more: neither is an error, and neither is read.
OUT=$(run_check); RC=$?
eq "$RC" "0" "an audit committing no SOURCES.txt is OK"
printf '# a manifest from an older renderer\nagents/a.md\nnot-a-hash\n' > "$P/generated/seed-audit/SOURCES.txt"
OUT=$(run_check); RC=$?
eq "$RC" "0" "…and so is one carrying a SOURCES.txt that matches nothing"
rm "$P/generated/seed-audit/SOURCES.txt"

# --- 7. the check renders nothing ---------------------------------------------
eq "$(cat "$RENDERER_LOG")" "" "no case above invoked the renderer, for a render or a manifest"

# --- 8. no renderer shipped = nothing to keep current -------------------------
rm "$P/assets/scripts/render-seed-audit.sh"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a pack shipping no renderer has nothing to keep current"
has "$OUT" "nothing to keep current" "…and says so"

echo
echo "check-seed-audit-current: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
