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
mkdir -p "$P/assets/scripts" "$P/generated/seed-audit/agents" "$P/generated/seed-audit/formulas" "$TMP/bin"
# Stub gc: run.sh reads `gc version` off PATH and compares it to the version
# the artifact records, so an unstubbed fixture is green only where gc is absent.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "${1:-}" = "version" ] && { printf '%s\n' "${GCVER:-gc v1}"; exit 0; }
exit 0
GC
chmod +x "$TMP/bin/gc"
# The upkeep arm sits behind a rev-parse guard: without a real repo it is
# skipped, and "hook wired" then reports a read that never happened.
git init -q -b main "$P"
git -C "$P" config core.hooksPath assets/hooks
# Stub renderer: --print-sources answers from $LIVE so tests steer it. $LIVE is
# a path list, one input per line; the stub renders it into the two-line record
# the real one writes, so the fixture states which inputs moved, not a format.
cat > "$P/assets/scripts/render-seed-audit.sh" <<'R'
#!/usr/bin/env bash
for a in "$@"; do
    [ "$a" = "--print-sources" ] || continue
    [ -n "${LIVE:-}" ] || exit 0
    echo "# fixture manifest"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf '%s\n%s\n' "${line%%=*}" "${line#*=}"
    done <<< "$LIVE"
    exit 0
done
exit 0
R
chmod +x "$P/assets/scripts/render-seed-audit.sh"
index() { { echo "# seed audit"; echo "- \`gc\` version: \`gc v1\`"; } > "$P/generated/seed-audit/INDEX.md"; }
manifest() { # <path=hash>... — what the artifact commits
    LIVE="$(printf '%s\n' "$@")" bash "$P/assets/scripts/render-seed-audit.sh" --print-sources \
        > "$P/generated/seed-audit/SOURCES.txt"
}
printf 'p\n' > "$P/generated/seed-audit/agents/worker.md"
printf 'f\n' > "$P/generated/seed-audit/formulas/mol-x.md"
# core.hooksPath resolves local-then-global, so an operator with a global one
# set would answer case 9's unset read; /dev/null pins the fixture to local.
run_check() { LIVE="${LIVE:-}" GCVER="${GCVER:-gc v1}" GC_PACK_DIR="$P" PATH="$TMP/bin:$PATH" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$CHECK" 2>&1; }

CURRENT='agents/a.md=h1
template-fragments/x.md=h2'

# --- 1. a manifest matching the tree passes -----------------------------------
index
manifest $CURRENT
OUT=$(LIVE="$CURRENT" run_check); RC=$?
eq "$RC" "0" "a matching manifest is OK"
has "$OUT" "1 agent prompt(s), 1 formula recipe(s)" "the summary counts the artifact"
has "$OUT" "2 input(s) hashed" "…and the inputs it hashed, not the lines it read"
has "$OUT" "hook wired" "the green line reports an upkeep read it actually made"

# --- 2. a drifting input is an ERROR, and is named ----------------------------
OUT=$(LIVE='agents/a.md=h1
template-fragments/x.md=MOVED' run_check); RC=$?
eq "$RC" "2" "an input that moved is an ERROR"
has "$OUT" "STALE" "the message says the audit is stale"
has "$OUT" "template-fragments/x.md" "the input that moved is named"
hasnt "$OUT" "agents/a.md" "…and the input that did not is not"

# --- 2b. an input added or removed is drift too -------------------------------
OUT=$(LIVE='agents/a.md=h1' run_check); RC=$?
eq "$RC" "2" "an input that disappeared is an ERROR"
has "$OUT" "template-fragments/x.md" "the missing input is named"

# --- 3. ABSENT audit is a WARNING (fresh clone before first render) ---------------
rm -rf "$P/generated"
OUT=$(LIVE="$CURRENT" run_check); RC=$?
eq "$RC" "1" "an entirely absent audit WARNS rather than erroring"
has "$OUT" "ABSENT" "the message says the audit is absent"
has "$OUT" "fresh clone" "the message explains the expected case"
mkdir -p "$P/generated/seed-audit/agents" "$P/generated/seed-audit/formulas"
printf 'p\n' > "$P/generated/seed-audit/agents/worker.md"
printf 'f\n' > "$P/generated/seed-audit/formulas/mol-x.md"
index

# --- 4. an audit with no manifest is an ERROR (unverifiable) ------------------
OUT=$(LIVE="$CURRENT" run_check); RC=$?
eq "$RC" "2" "an audit committing no SOURCES.txt is an ERROR"
has "$OUT" "UNVERIFIABLE" "the message says staleness cannot be checked at all"

# --- 5. a dark manifest signal warns ------------------------------------------
manifest $CURRENT
OUT=$(LIVE= run_check); RC=$?
eq "$RC" "1" "a renderer that prints no manifest warns, never passes"
has "$OUT" "UNVERIFIED" "the message says the signal is dark"

# --- 6. a non-executable renderer still checks, but warns -------------------------------
chmod -x "$P/assets/scripts/render-seed-audit.sh"
OUT=$(LIVE="$CURRENT" run_check); RC=$?
eq "$RC" "1" "a shipped-but-not-executable renderer is a warning"
has "$OUT" "NOT executable" "the mode bit is named"
OUT=$(LIVE='agents/a.md=MOVED
template-fragments/x.md=h2' run_check); RC=$?
eq "$RC" "2" "staleness is still detected through bash despite the mode bit"
chmod +x "$P/assets/scripts/render-seed-audit.sh"

# --- 7. a gc newer than the artifact records warns, never errors ------------------
OUT=$(LIVE="$CURRENT" GCVER='gc v9' run_check); RC=$?
eq "$RC" "1" "a host gc newer than the rendered artifact warns"
has "$OUT" "gc version drift" "the drift is named"
has "$OUT" 'rendered with "gc v1", host runs "gc v9"' "both versions are shown"
has "$OUT" "upkeep is not fully wired" "content is current, only upkeep is flagged"

# --- 8. a hook wired somewhere else warns -----------------------------------------
git -C "$P" config core.hooksPath .githooks
OUT=$(LIVE="$CURRENT" run_check); RC=$?
eq "$RC" "1" "a hooksPath pointing somewhere else warns"
has "$OUT" 'core.hooksPath is ".githooks", not assets/hooks' "the configured path is named once"
has "$OUT" "upkeep is not fully wired" "the summary separates upkeep from content"
git -C "$P" config core.hooksPath assets/hooks

# --- 9. no hook wired at all warns ------------------------------------------------
git -C "$P" config --unset core.hooksPath
OUT=$(LIVE="$CURRENT" run_check); RC=$?
eq "$RC" "1" "an unset hooksPath warns"
has "$OUT" "core.hooksPath is unset, not assets/hooks" "the unset case reads as one value"
git -C "$P" config core.hooksPath assets/hooks

# --- 10. no renderer shipped = nothing to keep current -------------------------------------
rm "$P/assets/scripts/render-seed-audit.sh"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a pack shipping no renderer has nothing to keep current"

echo
echo "check-seed-audit-current: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
