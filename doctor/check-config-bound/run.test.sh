#!/usr/bin/env bash
# Hermetic test for doctor/check-config-bound. Fixture pack + stub gc.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-config-bound-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
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

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
while [ "${1:-}" = "--city" ]; do shift 2; done
case "$1 $2" in
  "config show") rc="${CFG_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$CFG_FILE" ;;
  "order list") rc="${ORDERS_RC:-0}"; [ "$rc" -eq 0 ] || { [ -n "${ORDERS_ERR:-}" ] && printf '%s\n' "$ORDERS_ERR" >&2; exit "$rc"; }; cat "$ORDERS_JSON" ;;
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
printf '{"orders":[]}\n' > "$TMP/orders-none.json"
run_live() { PATH="$TMP/bin:$PATH" CFG_FILE="$1" ORDERS_JSON="${ORDERS_JSON:-$TMP/orders-none.json}" \
    GC_PACK_DIR="$P" GC_CITY_PATH="$TMP/city" bash "$CHECK" 2>&1; }
OUT=$(run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "0" "a readable resolved prompt_template passes"
has "$OUT" "1 resolved prompt_template" "the live arm counted the template it verified"
OUT=$(run_live "$TMP/cfg-bad.toml"); RC=$?
eq "$RC" "2" "an unreadable resolved prompt_template is an ERROR (the 16-line-stub path)"
has "$OUT" "stubbed" "the stub-primed agent is named"
has "$OUT" "prompts/missing.md" "the unresolvable path is named"

# --- 6. fail-CLOSED: a config that does not load ------------------------------------
OUT=$(CFG_RC=1 run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "1" "an unresolvable city config warns, never passes"
has "$OUT" "UNVERIFIED" "the warning says the answer is unknown"

# --- 7. live arm: an order meant for each rig, registered with no rig --------------
mkdir -p "$TMP/orders"
printf 'scope = "rig"\n' > "$TMP/orders/sweeper.toml"
printf 'scope = "city"\n' > "$TMP/orders/citywide.toml"
cat > "$TMP/orders-unbound.json" <<EOF
{"orders":[{"name":"sweeper","rig":"","source":"$TMP/orders/sweeper.toml"}]}
EOF
OUT=$(ORDERS_JSON="$TMP/orders-unbound.json" run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "2" "a scope=rig order registered with no rig is an ERROR"
has "$OUT" "order sweeper" "the order is named"
has "$OUT" "city store" "the finding says where the order runs instead"
cat > "$TMP/orders-city.json" <<EOF
{"orders":[{"name":"citywide","source":"$TMP/orders/citywide.toml"}]}
EOF
OUT=$(ORDERS_JSON="$TMP/orders-city.json" run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "0" "a scope=city order with no rig is the point of city scope"
has "$OUT" "none of the 1 order(s) registered with no rig" "the arm read the registry it passed"
cat > "$TMP/orders-bound.json" <<EOF
{"orders":[{"name":"sweeper","rig":"alpha","source":"$TMP/orders/sweeper.toml"}]}
EOF
OUT=$(ORDERS_JSON="$TMP/orders-bound.json" run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "0" "a scope=rig order registered for a rig passes"
has "$OUT" "none of the 0 order(s)" "an order with a rig is not one the arm reads"
cat > "$TMP/orders-gone.json" <<EOF
{"orders":[{"name":"ghost","source":"$TMP/orders/ghost.toml"}]}
EOF
OUT=$(ORDERS_JSON="$TMP/orders-gone.json" run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "0" "an order whose source cannot be read is reported, not judged"
has "$OUT" "order ghost" "the unjudged order is still named"
has "$OUT" "declared scope is unknown" "the note says why it was not judged"

# --- 8. fail-CLOSED: an order registry that does not answer --------------------------
OUT=$(ORDERS_RC=1 run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "1" "an unreadable order registry warns (the arm did not run)"
has "$OUT" "could not read the order registry" "the warning says the registry went unread"
hasnt "$OUT" "stderr:" "no stderr is quoted when the probe wrote none"
OUT=$(ORDERS_RC=1 ORDERS_ERR="order registry: socket unavailable" run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "1" "a failed \`gc order list\` still warns"
has "$OUT" "socket unavailable" "the order-registry warning carries the probe's stderr"
OUT=$(ORDERS_JSON="$TMP/cfg-good.toml" run_live "$TMP/cfg-good.toml"); RC=$?
eq "$RC" "1" "a registry that answers with something other than its JSON warns"

echo
echo "check-config-bound: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
