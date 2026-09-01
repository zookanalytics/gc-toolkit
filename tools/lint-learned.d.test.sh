#!/usr/bin/env bash
# lint-learned.d.test.sh — behaviour tests for the detectors in
# tools/lint-learned.d/. The runner's own contract is pinned separately in
# lint-learned.test.sh; this suite is about what a detector does and does not
# call a finding.
#
# It lives here rather than beside its subject because the runner executes
# every executable in lint-learned.d/ as a detector, so a test file in that
# directory would be run as one.
#
# Covered: raw-bd-invocation.
#
# Hermetic: fixture files in a tempdir, the real detector run against them by
# path. No live city, no store, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
DET="$HERE/lint-learned.d/raw-bd-invocation.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

[ -x "$DET" ] || { echo "no detector at $DET"; exit 1; }

TMP="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# run <file>... -> sets RC and OUT
run() { OUT="$("$DET" "$@" 2>&1)"; RC=$?; }

echo "── raw-bd-invocation: what is a finding ──"

# Every shape a real invocation takes in this pack, one per line so the
# assertions can name the line they expect.
cat > "$TMP/violations.sh" <<'FIX'
#!/usr/bin/env bash
bd list --status open
raw=$(bd show "$1" --json)
out=$(run_bounded bd list --db "$db" --json)
if [ -n "$D" ]; then bd --db "$D" "$@"; else bd "$@"; fi
ROOT=`bd show "$X" --json`
bd close "$id" && echo done
FIX
run "$TMP/violations.sh"
eq "$RC" 1 "a file with raw bd exits 1"
for n in 2 3 4 5 6 7; do
    has "$OUT" "violations.sh:$n:" "line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 6 "a line carrying two invocations is reported once, and nothing else is"
has "$OUT" "raw-bd-invocation" "the finding names the rule"
has "$OUT" "gc bd" "the finding names the fix"

echo "── raw-bd-invocation: what is not ──"

cat > "$TMP/clean.sh" <<'FIX'
#!/usr/bin/env bash
# bd list --status open   <- a commented-out invocation is prose
gc bd list --status open
raw=$(gc bd show "$1" --json)
out=$(run_bounded gc bd list --db "$db" --json)
gc   bd list --db "$db"
bd_at() { gc bd --db "$1" "$@"; }
bd_show() { run_bounded gc bd show "$1" --json; }
bd_at "$p" show "$id" --json
exec "$BIN/gc" bd show "$1" --json
"$GC" bd list --db "$db"
"${GC}" bd list --db "$db"
$GC bd close "$id"
echo "could not read $W (bd unavailable?) — not preparing"
errors+=("step $b: nothing holds it, and \`bd ready\` cannot offer it either")
if grep -qE -- '--status|--close|bd close' <<< "$UPDATES"; then :; fi
warnings+=("could not read \`bd ready\` (rc=$rc) or \`bd blocked\` (rc=$rc2)")
FIX
run "$TMP/clean.sh"
eq "$RC" 0 "gc bd in every spelling, bd-prefixed helpers, comments and quoted prose are clean"
eq "$OUT" "" "a clean file prints nothing"

echo "── raw-bd-invocation: the waiver ──"

cat > "$TMP/waived.sh" <<'FIX'
#!/usr/bin/env bash
bd show "$X" --json   # raw-bd: gc bd loads the city config, cold here
# raw-bd: gc bd loads the city config, cold here
bd dep tree "$C" --json
FIX
run "$TMP/waived.sh"
eq "$RC" 0 "a stated reason waives the line, trailing or on the line above"

cat > "$TMP/bare-waiver.sh" <<'FIX'
#!/usr/bin/env bash
bd show "$X" --json   # raw-bd:
FIX
run "$TMP/bare-waiver.sh"
eq "$RC" 1 "a waiver with no reason does not waive"

# The waiver is per line: it must not carry to the next invocation.
cat > "$TMP/waiver-scope.sh" <<'FIX'
#!/usr/bin/env bash
bd show "$X" --json   # raw-bd: a documented gc limitation
bd show "$Y" --json
FIX
run "$TMP/waiver-scope.sh"
eq "$RC" 1 "the line after a waived line is still checked"
has "$OUT" "waiver-scope.sh:3:" "and it is the unwaived line that is reported"
hasnt "$OUT" "waiver-scope.sh:2:" "the waived line stays quiet"

echo "── raw-bd-invocation: scope ──"

cp "$TMP/violations.sh" "$TMP/notes.md"
cp "$TMP/violations.sh" "$TMP/formula.toml"
run "$TMP/notes.md" "$TMP/formula.toml"
eq "$RC" 0 "only *.sh is scanned"

mkdir -p "$TMP/lint-learned.d"
cp "$TMP/violations.sh" "$TMP/lint-learned.d/other-detector.sh"
run "$TMP/lint-learned.d/other-detector.sh"
eq "$RC" 0 "the detector directory is skipped — the shape is stated there"

run "$TMP/does-not-exist.sh"
eq "$RC" 0 "a path that is not a file drops out"

echo "── raw-bd-invocation: a detector that cannot scan says so ──"

# Masking `gc bd` is what separates the correct form from the raw one. If it
# does not run, every correct call site reads as a violation, so the detector
# must report itself broken rather than emit that.
mkdir -p "$TMP/shim"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/shim/sed"
chmod +x "$TMP/shim/sed"
OUT="$(PATH="$TMP/shim:$PATH" "$DET" "$TMP/clean.sh" 2>&1)"; RC=$?
eq "$RC" 2 "a failed mask exits 2, not 0 and not 1"
has "$OUT" "detector cannot scan it" "and says which file it could not scan"

echo
echo "lint-learned.d.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
