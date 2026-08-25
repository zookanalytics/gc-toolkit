#!/usr/bin/env bash
# Hermetic test for doctor/check-config-bound. Fixture pack + stub gc.
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
mkdir -p "$P/template-fragments" "$P/agents/worker" "$P/overlays/hooky" \
         "$P/packs/sub/template-fragments" "$P/packs/sub/agents/kid" "$TMP/bin" "$TMP/city"

# Fragments: one by filename, one by define block, one only in the sub-pack.
printf 'doctrine\n' > "$P/template-fragments/by-file.template.md"
printf '{{ define "by-define" }}x{{ end }}\n' > "$P/template-fragments/blocks.template.md"
printf 'sub doctrine\n' > "$P/packs/sub/template-fragments/sub-only.template.md"

pack_toml() { # writes $P/pack.toml with the given fragment list for one patch
    cat > "$P/pack.toml" <<EOF
[pack]
name = "fixture"
[[patches.agent]]
name = "worker"
inject_fragments_append = [
    # a comment inside the list
    $1
]
overlay_dir = "$2"
EOF
}
cat > "$P/packs/sub/agents/kid/agent.toml" <<'EOF'
inject_fragments = ["sub-only", "by-file"]
EOF

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
while [ "${1:-}" = "--city" ]; do shift 2; done
case "$1 $2" in
  "config show") rc="${CFG_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$CFG_FILE" ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"
run_static() { GC_PACK_DIR="$P" GC_CITY_PATH="" GC_CITY="" bash "$CHECK" 2>&1; }

# --- 1. everything resolves --------------------------------------------------
pack_toml '"by-file", "by-define",' "overlays/hooky"
OUT=$(run_static); RC=$?
eq "$RC" "0" "file-named + define-block fragments and a real overlay_dir pass"
has "$OUT" "OK:" "the pass message is the OK line"
has "$OUT" "not verifiable here" "outside a city the live arm is a note, not a warning"

# --- 2. a fragment that resolves nowhere ----------------------------------------
pack_toml '"by-file", "ghost-doctrine",' "overlays/hooky"
OUT=$(run_static); RC=$?
eq "$RC" "2" "an unresolvable fragment name is an ERROR"
has "$OUT" "ghost-doctrine" "the missing fragment is named"
has "$OUT" "pack.toml" "the declaring file is named"

# --- 3. sub-pack fragments resolve in the sub-pack tree (root as fallback) -------
pack_toml '"by-file",' "overlays/hooky"
OUT=$(run_static); RC=$?
eq "$RC" "0" "a sub-pack agent's fragments resolve in the sub-pack, falling back to the root"
printf 'inject_fragments = ["sub-missing"]\n' > "$P/packs/sub/agents/kid/agent.toml"
OUT=$(run_static); RC=$?
eq "$RC" "2" "a sub-pack fragment missing from BOTH trees is an ERROR"
has "$OUT" "sub-missing" "the missing sub-pack fragment is named"
printf 'inject_fragments = ["sub-only", "by-file"]\n' > "$P/packs/sub/agents/kid/agent.toml"

# --- 4. a dangling overlay_dir ---------------------------------------------------
pack_toml '"by-file",' "overlays/nonexistent"
OUT=$(run_static); RC=$?
eq "$RC" "2" "an overlay_dir naming no directory is an ERROR"
has "$OUT" "overlays/nonexistent" "the dangling overlay is named"
pack_toml '"by-file", "by-define",' "overlays/hooky"

# --- 5. live arm: resolved prompt_template readability -----------------------------
mkdir -p "$TMP/city/prompts"
printf 'real prompt\n' > "$TMP/city/prompts/worker.md"
cat > "$TMP/cfg-good.toml" <<'EOF'
[[agent]]
name = "worker"
prompt_template = "prompts/worker.md"
EOF
cat > "$TMP/cfg-bad.toml" <<'EOF'
[[agent]]
name = "worker"
prompt_template = "prompts/worker.md"
[[agent]]
name = "stubbed"
prompt_template = "prompts/missing.md"
EOF
run_live() { PATH="$TMP/bin:$PATH" CFG_FILE="$1" GC_PACK_DIR="$P" GC_CITY_PATH="$TMP/city" bash "$CHECK" 2>&1; }
OUT=$(run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "0" "a readable resolved prompt_template passes"
has "$OUT" "1 resolved prompt_template" "the live arm counted the template it verified"
OUT=$(run_live "$TMP/cfg-bad.toml"); RC=$?
eq "$RC" "2" "an unreadable resolved prompt_template is an ERROR (the 16-line-stub path)"
has "$OUT" "stubbed" "the stub-primed agent is named"
has "$OUT" "prompts/missing.md" "the unresolvable path is named"

# --- 6. fail-CLOSED: a config that does not load ------------------------------------
OUT=$(PATH="$TMP/bin:$PATH" CFG_RC=1 CFG_FILE="$TMP/cfg-good.toml" GC_PACK_DIR="$P" GC_CITY_PATH="$TMP/city" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "an unresolvable city config warns, never passes"
has "$OUT" "UNVERIFIED" "the warning says the answer is unknown"

echo
echo "check-config-bound: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
