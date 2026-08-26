#!/usr/bin/env bash
# Hermetic test for doctor/check-plan-targets-filed. Fixture pack + stub ledger.
# The stubs refuse what the real tools refuse: `bd list` exits non-zero when its
# --db store is absent, so the unreadable-store arm is driven rather than
# assumed. A live control at the end runs the check against the real pack.
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

P="$TMP/pack"; BIN="$TMP/bin"; STORE="$TMP/rig/.beads"
mkdir -p "$P/docs" "$BIN" "$STORE"

# Stub ledger: `bd list --db <dir>` answers from <dir>/ids, and fails when that
# store is absent — the real command fails on an unreadable store too.
cat > "$BIN/bd" <<'B'
#!/usr/bin/env bash
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
[ -n "$db" ] || { echo "bd: --db is required" >&2; exit 2; }
[ -f "$db/ids" ] || { echo "bd: cannot open $db" >&2; exit 1; }
jq -R -s 'split("\n") | map(select(length > 0) | {id: .})' < "$db/ids"
B
cat > "$BIN/gc" <<'G'
#!/usr/bin/env bash
[ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ] || { echo "gc: unexpected $*" >&2; exit 2; }
[ -n "${RIGLIST_FAIL:-}" ] && exit 3
cat "$RIGLIST"
G
chmod +x "$BIN/bd" "$BIN/gc"
printf 'tk-real1\ntk-real2\n' > "$STORE/ids"
cat > "$TMP/riglist.json" <<J
{"rigs":[{"name":"r1","path":"$TMP/rig","suspended":false}]}
J
export RIGLIST="$TMP/riglist.json"

doc() { printf '%s\n' "$@" > "$P/docs/plan.md"; }
run_check() { PATH="$BIN:$PATH" GC_PACK_DIR="$P" bash "$CHECK" 2>&1; }

# --- 1. a fully bound checklist passes ---------------------------------------
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' \
    '| 1 | Do the thing | `tk-real1` |' \
    '| 2 | Skip the thing | none — folded into target 1 |' \
    '| 3 | Already done | landed: `refinery-reconcile.sh` |'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a fully bound checklist is OK"
has "$OUT" "3 target row(s): 1 bead-bound, 1 deliberate none, 1 landed" "the summary counts each binding state"

# --- 2. a blank binding cell is an ERROR -------------------------------------
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' \
    '| 1 | Do the thing | `tk-real1` |' \
    '| 2 | The dropped one | |'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a row that binds to nothing is an ERROR"
has "$OUT" "docs/plan.md:8" "the unbound row is named by file and line"
has "$OUT" "The dropped one" "the unbound row's text is shown"

# --- 3. a bead ID that resolves nowhere is an ERROR ---------------------------
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' \
    '| 1 | Typo | `tk-nosuch` |'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bead reference resolving in no store is an ERROR"
has "$OUT" "tk-nosuch" "the unresolved ID is named"

# --- 4. EVERY bead in a cell is verified, not just the first ------------------
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' \
    '| 1 | Two halves | `tk-real1`, `tk-real2` |'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a row citing two real beads passes"
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' \
    '| 1 | Two halves | `tk-real1`, `tk-ghost` |'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a second bead in the same cell is verified too"
has "$OUT" "tk-ghost" "the unverified half is named"

# --- 5. `none` needs a reason ------------------------------------------------
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' '| 1 | X | none |'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bare 'none' with no reason does not bind"

# --- 6. `landed:` needs a subject --------------------------------------------
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' '| 1 | X | landed: |'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bare 'landed:' with no subject does not bind"

# --- 7. a marker introducing no table WARNS ----------------------------------
doc '# Plan' '' '<!-- plan-targets -->' '' 'Just prose, no table.'
OUT=$(run_check); RC=$?
eq "$RC" "1" "a marker that introduces no table is a WARNING"
has "$OUT" "introduce no table" "the message says the marker is empty"

# --- 8. an unreadable store WARNS and never passes ---------------------------
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' '| 1 | X | `tk-real1` |'
mv "$STORE/ids" "$STORE/ids.hidden"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unreadable store WARNS rather than passing"
has "$OUT" "NOT verified" "the message says the references went unverified"
mv "$STORE/ids.hidden" "$STORE/ids"

# --- 8b. a wholly SUSPENDED ledger WARNS -------------------------------------
# Distinct from the unreadable store above: skipping a suspended rig is not an
# error, so nothing here complains per-store. Without a guard on "did any store
# actually answer", the check would pass having verified nothing.
cat > "$TMP/riglist-suspended.json" <<J
{"rigs":[{"name":"r1","path":"$TMP/rig","suspended":true}]}
J
OUT=$(RIGLIST="$TMP/riglist-suspended.json" run_check); RC=$?
eq "$RC" "1" "a wholly suspended ledger WARNS rather than passing"
has "$OUT" "no bead store could be read" "the message says no store answered"
has "$OUT" "suspended" "the skipped rig is accounted for"

# --- 9. a failed rig listing WARNS -------------------------------------------
OUT=$(RIGLIST_FAIL=1 run_check); RC=$?
eq "$RC" "1" "a failed store listing WARNS rather than passing"
has "$OUT" "NOT verified" "the message says the references went unverified"

# --- 10. no checklist anywhere passes, but says so ---------------------------
doc '# Plan' '' 'An ordinary document with no checklist.' '' \
    '| # | Thing | Risk |' '|---|---|---|' '| 1 | unscanned | |'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a pack with no checklist is OK"
has "$OUT" "no plan's target list is being watched" "a vacuous pass says nothing is watched"
has "$OUT" "0 target row(s)" "the vacuous pass reports zero rows examined"

# --- 11. the checklist ends at the first non-table line ----------------------
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' '| 1 | X | `tk-real1` |' \
    '' 'Prose ends the checklist.' '' \
    '| # | Later table | Risk |' '|---|---|---|' '| 1 | not scanned | |'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a later unrelated table is outside the checklist"
has "$OUT" "1 target row(s)" "only the marked table's rows are counted"

# --- 12. a fenced example is documentation, not a checklist ------------------
# docs/file-structure.md shows the convention in a code fence. Scanning that
# example would make the doc that teaches the rule an instance of it.
doc '# How to write a checklist' '' 'Mark the table like this:' '' \
    '```markdown' \
    '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' \
    '| 1 | An example row | |' \
    '```' '' 'That is the whole convention.'
OUT=$(run_check); RC=$?
eq "$RC" "0" "an unbound row inside a code fence is not a finding"
has "$OUT" "0 target row(s)" "the fenced example contributes no rows"

# --- 13. the marker arms only as a standalone line ---------------------------
# docs/file-structure.md and the filing skill both name the marker in prose.
# Arming on a mention would make every document that explains the rule declare
# a checklist it does not have.
doc '# Prose that names the marker' '' \
    'Mark the table with `<!-- plan-targets -->` and bind the last column.' '' \
    '| # | Not a checklist | Risk |' '|---|---|---|' \
    '| 1 | must not be scanned | |'
OUT=$(run_check); RC=$?
eq "$RC" "0" "the marker quoted inline in prose does not arm the scanner"
has "$OUT" "0 target row(s)" "a mention contributes no rows"

# --- 14. an unreadable document is not a silent under-scan -------------------
doc '# Plan' '' '<!-- plan-targets -->' '' \
    '| # | Target | Bead |' '|---|---|---|' '| 1 | X | `tk-real1` |'
printf 'unreadable\n' > "$P/docs/locked.md"; chmod 000 "$P/docs/locked.md"
OUT=$(run_check); RC=$?
if [ "$(id -u)" = "0" ]; then
    ok "SKIP unreadable-document case (running as root reads it anyway)"
    ok "SKIP unreadable-document message"
else
    eq "$RC" "1" "a document that cannot be read WARNS rather than passing"
    has "$OUT" "went unexamined" "the message says a checklist may have been missed"
fi
rm -f "$P/docs/locked.md"

# --- 15. live control: the real pack, the real ledger ------------------------
# The stubs above could drift from the tools they imitate. One unstubbed run
# proves the check still executes against a real pack and a real store.
PACK_ROOT="$(cd "$HERE/../.." && pwd)"
OUT=$(GC_PACK_DIR="$PACK_ROOT" bash "$CHECK" 2>&1); RC=$?
case "$RC" in
    0|1|2) ok "live control: the check runs against the real pack (rc=$RC)" ;;
    *)     bad "live control: unexpected exit $RC — $OUT" ;;
esac
has "$OUT" "target row(s)" "live control: the summary reports what was examined"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
