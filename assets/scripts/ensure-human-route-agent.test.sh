#!/usr/bin/env bash
# Hermetic test for ensure-human-route-agent.sh. Every case runs against a
# fixture city.toml in a temp dir; the real town config is never touched.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/ensure-human-route-agent.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-ensure-human-route-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

# Count bare [[agent]] blocks named "human" (the script's own idempotency key).
count_bare_human() {
    awk '
        /^[[:space:]]*\[\[agent\]\][[:space:]]*$/ { inblk=1; next }
        /^[[:space:]]*\[/                         { inblk=0 }
        inblk && /^[[:space:]]*name[[:space:]]*=[[:space:]]*"human"[[:space:]]*$/ { n++ }
        END { print n + 0 }
    ' "$1"
}

# A city.toml shaped like the real one: rig imports, a [[patches.agent]], and a
# trailing [agent_defaults] table — no top-level [[agent]] blocks.
fresh_city() { # <dir> [extra]
    mkdir -p "$1"
    cat > "$1/city.toml" <<'EOF'
[workspace]
provider = "claude"

[[rigs]]
name = "gc-toolkit"
prefix = "tk"
[rigs.imports]
[rigs.imports.gc-toolkit]
source = "/pack"

[patches]
[[patches.agent]]
name = "polecat"
inject_fragments_append = ["x"]

[agent_defaults]
default_sling_formula = "mol-polecat-work"
EOF
    [ -n "${2:-}" ] && printf '%s\n' "$2" >> "$1/city.toml"
    return 0
}

# --- 1. absent -> appended, present, idempotent -------------------------------
C="$TMP/c1"; fresh_city "$C"
BEFORE_LINES=$(wc -l < "$C/city.toml")
OUT=$(GC_CITY_PATH="$C" bash "$SCRIPT" 2>&1); RC=$?
eq "$RC" "0" "appending to a city with no human agent succeeds"
has "$OUT" "APPENDED" "it reports the append"
has "$OUT" "gc reload" "it names the operator's reload step"
eq "$(count_bare_human "$C/city.toml")" "1" "exactly one bare human agent after the append"
has "$(cat "$C/city.toml")" 'max_active_sessions = 0' "the load-bearing field was written"
has "$(cat "$C/city.toml")" 'default_sling_formula = "mol-polecat-work"' "pre-existing content is preserved"
OUT=$(GC_CITY_PATH="$C" bash "$SCRIPT" --check 2>&1); RC=$?
eq "$RC" "0" "--check now reports the agent present"
has "$OUT" "already declares" "--check confirms presence"

# --- 2. a second apply is a no-op (no duplicate) ------------------------------
OUT=$(GC_CITY_PATH="$C" bash "$SCRIPT" 2>&1); RC=$?
eq "$RC" "0" "re-running against a city that already has it succeeds"
has "$OUT" "no change" "it reports no change"
eq "$(count_bare_human "$C/city.toml")" "1" "still exactly one bare human agent (idempotent)"

# --- 3. a [[patches.agent]] named human does NOT count as the bare agent ------
C="$TMP/c3"; fresh_city "$C" '
[[patches.agent]]
name = "human"
nudge = "x"'
eq "$(count_bare_human "$C/city.toml")" "0" "a patches.agent named human is not a bare agent"
OUT=$(GC_CITY_PATH="$C" bash "$SCRIPT" 2>&1); RC=$?
eq "$RC" "0" "the bare agent is still appended past a same-named patch"
has "$OUT" "APPENDED" "it appended rather than treating the patch as the agent"
eq "$(count_bare_human "$C/city.toml")" "1" "exactly one bare human agent now exists"

# --- 4. --check on an absent agent reports and writes nothing -----------------
C="$TMP/c4"; fresh_city "$C"
SUM_BEFORE=$(cksum < "$C/city.toml")
OUT=$(GC_CITY_PATH="$C" bash "$SCRIPT" --check 2>&1); RC=$?
eq "$RC" "1" "--check on an absent agent exits 1"
has "$OUT" "MISSING" "--check names the absence"
eq "$(cksum < "$C/city.toml")" "$SUM_BEFORE" "--check left the file byte-for-byte unchanged"

# --- 5. missing inputs fail closed with exit 2 --------------------------------
OUT=$(env -u GC_CITY_PATH -u GC_CITY bash "$SCRIPT" 2>&1); RC=$?
eq "$RC" "2" "no city in scope is an error, not a silent pass"
OUT=$(GC_CITY_PATH="$TMP/does-not-exist" bash "$SCRIPT" 2>&1); RC=$?
eq "$RC" "2" "a city with no city.toml is an error"
has "$OUT" "no city.toml" "it names what was missing"
OUT=$(env -u GC_CITY_PATH -u GC_CITY bash "$SCRIPT" --city 2>&1); RC=$?
eq "$RC" "2" "--city with no value is an error, not an infinite loop"
has "$OUT" "needs a path" "it names the missing --city value"

# --- 6. --city overrides the environment --------------------------------------
C="$TMP/c6"; fresh_city "$C"
OUT=$(GC_CITY_PATH="$TMP/does-not-exist" bash "$SCRIPT" --city "$C" 2>&1); RC=$?
eq "$RC" "0" "--city takes precedence over GC_CITY_PATH"
eq "$(count_bare_human "$C/city.toml")" "1" "the override city got the agent"

# --- 7. the result parses as TOML with the intended agent (if tomllib is here)-
if python3 -c 'import tomllib' >/dev/null 2>&1; then
    RES=$(python3 - "$C/city.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    d = tomllib.load(fh)
bare = [a for a in d.get("agent", []) if a.get("name") == "human"]
patched = d.get("patches", {}).get("agent", [])
if len(bare) == 1 and bare[0].get("max_active_sessions") == 0:
    print("ok")
else:
    print("bad bare=%r patched=%r" % (bare, patched))
PY
)
    eq "$RES" "ok" "the written file parses: one top-level agent name=human, max_active_sessions=0"
else
    ok "tomllib absent — skipped the TOML parse assertion"
fi

# --- 8. the temp is staged beside city.toml, independent of $TMPDIR -----------
# The rename that publishes the write is atomic only within one filesystem. The
# town config can sit on a different filesystem from $TMPDIR, so a temp under
# $TMPDIR would make `mv` a cross-device copy that can leave city.toml partially
# written. Proof the temp lives beside city.toml instead: a $TMPDIR that cannot
# even hold a temp file must not affect the write.
C="$TMP/c8"; fresh_city "$C"
OUT=$(GC_CITY_PATH="$C" TMPDIR="$TMP/no-such-tmpdir" bash "$SCRIPT" 2>&1); RC=$?
eq "$RC" "0" "append succeeds when TMPDIR is unusable (temp staged beside city.toml)"
has "$OUT" "APPENDED" "it still reports the append"
eq "$(count_bare_human "$C/city.toml")" "1" "exactly one bare human agent after the append"
LEFTOVER=$(find "$C" -maxdepth 1 -name '.gctk-ensure-human-route.*' 2>/dev/null)
eq "$LEFTOVER" "" "no temp file is left beside city.toml after a successful write"

echo
echo "ensure-human-route-agent: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
