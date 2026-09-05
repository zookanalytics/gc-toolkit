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
# Covered: raw-bd-invocation, mktemp-untemplated.
#
# Hermetic: fixture files in a tempdir, the real detector run against them by
# path. No live city, no store, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
DET="$HERE/lint-learned.d/raw-bd-invocation.sh"
DET_MK="$HERE/lint-learned.d/mktemp-untemplated.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

[ -x "$DET" ] || { echo "no detector at $DET"; exit 1; }
[ -x "$DET_MK" ] || { echo "no detector at $DET_MK"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lint-learned-d-test.XXXXXX")" || { echo "cannot allocate a tempdir"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# run <file>... -> sets RC and OUT
run() { OUT="$("$DET" "$@" 2>&1)"; RC=$?; }

# plant <file> — write a fixture from stdin, expanding the @BD@ placeholder to
# the bare client name. The placeholder is what keeps this suite honest: the
# runner scans every tracked file, so a fixture spelled literally here would be
# a finding against the test that proves the finding.
plant() { sed 's/@BD@/bd/g' > "$1"; }

echo "── raw-bd-invocation: what is a finding ──"

# Every shape a real invocation takes in this pack, one per line so the
# assertions can name the line they expect.
plant "$TMP/violations.sh" <<'FIX'
#!/usr/bin/env bash
@BD@ list --status open
raw=$(@BD@ show "$1" --json)
out=$(run_bounded @BD@ list --db "$db" --json)
if [ -n "$D" ]; then @BD@ --db "$D" "$@"; else @BD@ "$@"; fi
ROOT=`@BD@ show "$X" --json`
@BD@ close "$id" && echo done
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

plant "$TMP/waived.sh" <<'FIX'
#!/usr/bin/env bash
@BD@ show "$X" --json   # raw-bd: gc @BD@ loads the city config, cold here
# raw-bd: gc @BD@ loads the city config, cold here
@BD@ dep tree "$C" --json
FIX
run "$TMP/waived.sh"
eq "$RC" 0 "a stated reason waives the line, trailing or on the line above"

plant "$TMP/bare-waiver.sh" <<'FIX'
#!/usr/bin/env bash
@BD@ show "$X" --json   # raw-bd:
FIX
run "$TMP/bare-waiver.sh"
eq "$RC" 1 "a waiver with no reason does not waive"

# The waiver is per line: it must not carry to the next invocation.
plant "$TMP/waiver-scope.sh" <<'FIX'
#!/usr/bin/env bash
@BD@ show "$X" --json   # raw-bd: a documented gc limitation
@BD@ show "$Y" --json
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

# ── mktemp-untemplated ──────────────────────────────────────────────────
#
# Fixtures spell the call as @MKT@ for the same reason raw-bd's spell it
# @BD@: the runner scans every tracked file, so a bare call written
# literally here would be a finding against the test that proves the finding.
mk()  { sed 's/@MKT@/mktemp/g' > "$1"; }
runm() { OUT="$("$DET_MK" "$@" 2>&1)"; RC=$?; }

echo "── mktemp-untemplated: what is a finding ──"

mk "$TMP/bare.sh" <<'FIX'
#!/usr/bin/env bash
D=$(@MKT@)
E="$(@MKT@ -d)"
F=`@MKT@ -u`
@MKT@
G=$(@MKT@ -q -d)
FIX
runm "$TMP/bare.sh"
eq "$RC" 1 "a file with an untemplated call exits 1"
for n in 2 3 4 5 6; do
    has "$OUT" "bare.sh:$n:" "line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 5 "and nothing else is"
has "$OUT" "mktemp-untemplated" "the finding names the rule"
has "$OUT" "gctk-" "the finding names the fix"

echo "── mktemp-untemplated: what is not ──"

mk "$TMP/templated.sh" <<'FIX'
#!/usr/bin/env bash
# @MKT@ -d   <- a commented-out call is prose
A=$(@MKT@ "${TMPDIR:-/tmp}/gctk-thing.XXXXXX")
B="$(@MKT@ -d "${TMPDIR:-/tmp}/gctk-thing.XXXXXX")"
C=$(@MKT@ -t gctk-thing.XXXXXX)
D=$(@MKT@ --tmpdir=/var/tmp gctk-thing.XXXXXX)
E=$(@MKT@ -d "$STATE_DIR/.thing.XXXXXX")
F=$(@MKT@ -u -t gctk-fifo.XXXXXX)
FIX
runm "$TMP/templated.sh"
eq "$RC" 0 "a chosen name in any spelling is clean"
eq "$OUT" "" "a clean file prints nothing"

# The word also appears as data. None of these allocate anything, and a
# detector that flags them trains authors to ignore it.
mk "$TMP/not-a-call.sh" <<'FIX'
#!/usr/bin/env bash
for c in jq date @MKT@ rm cat; do command -v "$c" >/dev/null || exit 1; done
for c in jq @MKT@; do :; done
REAL="$(command -v @MKT@)"
cat > "$TMP/bin/@MKT@" <<'STUB'
STUB
chmod +x "$TMP/bin/@MKT@"
echo "a killed start leaves a @MKT@ that never reached its mv"
FIX
runm "$TMP/not-a-call.sh"
eq "$RC" 0 "the bare word as data — a dependency list, a stub path, prose — is not a call"

# A helper whose NAME starts with the command is the case that reads as a call
# to a scan keying off the first `mktemp` substring on the line: the name is
# not a call, and the untemplated allocation inside it still is.
mk "$TMP/named-helper.sh" <<'FIX'
#!/usr/bin/env bash
@MKT@_tracked() { local f; f="$(@MKT@)" || return 1; TMPFILES+=("$f"); }
@MKT@_kept() { local g; g="$(@MKT@ "${TMPDIR:-/tmp}/gctk-thing.XXXXXX")" || return 1; }
FIX
runm "$TMP/named-helper.sh"
eq "$RC" 1 "a helper named for the command does not stand in for the call inside it"
has "$OUT" "named-helper.sh:2:" "the untemplated call in the helper is reported"
hasnt "$OUT" "named-helper.sh:3:" "and the templated one beside it is not"

echo "── mktemp-untemplated: command starts ──"

# A command word also begins after a compound keyword, after a negation, and
# inside a case arm. Those are ordinary shell, so a recognizer that only knows
# the head of a line and a separator leaves the rule fail-open for them.
mk "$TMP/command-starts.sh" <<'FIX'
#!/usr/bin/env bash
if @MKT@; then :; fi
while @MKT@; do break; done
until @MKT@; do break; done
case "$x" in a) @MKT@ ;; esac
probe() { if :; then :; elif @MKT@; then :; fi; }
! @MKT@
{ @MKT@; }
FIX
runm "$TMP/command-starts.sh"
eq "$RC" 1 "a keyword, negation or case-arm command start is still a call"
for n in 2 3 4 5 6 7 8; do
    has "$OUT" "command-starts.sh:$n:" "line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 7 "and nothing else is"

# The same starts with a template beside them stay clean, so the wider
# recognizer buys coverage without flagging a call that named itself.
mk "$TMP/command-starts-templated.sh" <<'FIX'
#!/usr/bin/env bash
if @MKT@ -u "${TMPDIR:-/tmp}/gctk-thing.XXXXXX" >/dev/null; then :; fi
case "$x" in a) @MKT@ -d "${TMPDIR:-/tmp}/gctk-thing.XXXXXX" ;; esac
! @MKT@ -u gctk-thing.XXXXXX
FIX
runm "$TMP/command-starts-templated.sh"
eq "$RC" 0 "a chosen name after a keyword or case arm is clean"
eq "$OUT" "" "a clean file prints nothing"

echo "── mktemp-untemplated: option arity ──"

# An option that takes a directory or a suffix has not named anything: with no
# TEMPLATE beside it the basename is still the libc `tmp.XXXXXXXXXX`, which is
# the family the rule exists to empty. `mktemp -u` on each of these prints a
# `tmp.*` name.
mk "$TMP/option-args.sh" <<'FIX'
#!/usr/bin/env bash
A=$(@MKT@ --suffix=.json)
B=$(@MKT@ --suffix .json)
C=$(@MKT@ --tmpdir=/var/tmp)
D=$(@MKT@ -p /var/tmp)
E=$(@MKT@ -dp "$STATE_DIR")
F=$(@MKT@ -t)
FIX
runm "$TMP/option-args.sh"
eq "$RC" 1 "an option that chooses a directory or a suffix is not a template"
for n in 2 3 4 5 6 7; do
    has "$OUT" "option-args.sh:$n:" "line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 6 "and nothing else is"

# The same options with a TEMPLATE beside them: the producer named it, and the
# option's own argument must not be mistaken for that name.
mk "$TMP/option-args-templated.sh" <<'FIX'
#!/usr/bin/env bash
A=$(@MKT@ --suffix=.json "${TMPDIR:-/tmp}/gctk-thing.XXXXXX")
B=$(@MKT@ --suffix .json gctk-thing.XXXXXX)
C=$(@MKT@ --tmpdir=/var/tmp gctk-thing.XXXXXX)
D=$(@MKT@ -p /var/tmp gctk-thing.XXXXXX)
E=$(@MKT@ -dp /var/tmp gctk-thing.XXXXXX)
F=$(@MKT@ --tmpdir gctk-thing.XXXXXX)
FIX
runm "$TMP/option-args-templated.sh"
eq "$RC" 0 "a template beside the option argument is still a chosen name"
eq "$OUT" "" "a clean file prints nothing"

echo "── mktemp-untemplated: an assignment prefix is still a command ──"

# `VAR=val mktemp` runs mktemp with VAR set for that one command. It is a
# command start the head-of-line-and-separator recognizer walked past, so the
# rule read it as data and let a bare, unattributable allocation through.
mk "$TMP/assign-prefix.sh" <<'FIX'
#!/usr/bin/env bash
TMPDIR=/var/tmp @MKT@ -d
A=1 B=2 @MKT@
FIX
runm "$TMP/assign-prefix.sh"
eq "$RC" 1 "an assignment-prefixed call is a call"
has "$OUT" "assign-prefix.sh:2:" "a single assignment before the command is reported"
has "$OUT" "assign-prefix.sh:3:" "a run of assignment words before it is reported"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 2 "and nothing else is"

# The same prefix in front of a chosen name is clean: the assignment is not an
# operand, so it must not be mistaken for the template.
mk "$TMP/assign-prefix-templated.sh" <<'FIX'
#!/usr/bin/env bash
TMPDIR=/var/tmp @MKT@ "${TMPDIR:-/tmp}/gctk-thing.XXXXXX"
FIX
runm "$TMP/assign-prefix-templated.sh"
eq "$RC" 0 "a chosen name behind an assignment prefix is clean"
eq "$OUT" "" "a clean file prints nothing"

echo "── mktemp-untemplated: more than one call on a line ──"

# Each call is judged on its own argument list. A greedy scan that read only the
# last call on a line let a templated call vouch for a bare one beside it,
# whichever order they fell in.
mk "$TMP/two-calls.sh" <<'FIX'
#!/usr/bin/env bash
A=$(@MKT@); B=$(@MKT@ "${TMPDIR:-/tmp}/gctk-two.XXXXXX")
C=$(@MKT@ "${TMPDIR:-/tmp}/gctk-two.XXXXXX") || D=$(@MKT@)
FIX
runm "$TMP/two-calls.sh"
eq "$RC" 1 "a bare call beside a templated one is still reported"
has "$OUT" "two-calls.sh:2:" "the bare call before a templated one is found"
has "$OUT" "two-calls.sh:3:" "the bare call after a templated one is found"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 2 "and each such line is reported once"

mk "$TMP/two-calls-templated.sh" <<'FIX'
#!/usr/bin/env bash
A=$(@MKT@ "${TMPDIR:-/tmp}/gctk-a.XXXXXX"); B=$(@MKT@ "${TMPDIR:-/tmp}/gctk-b.XXXXXX")
FIX
runm "$TMP/two-calls-templated.sh"
eq "$RC" 0 "two chosen names on one line are clean"
eq "$OUT" "" "a clean file prints nothing"

echo "── mktemp-untemplated: scope ──"

mk "$TMP/prose.md" <<'FIX'
Reproduce with:
```bash
D=$(@MKT@ -d)
```
FIX
runm "$TMP/prose.md"
eq "$RC" 0 "a fenced block in Markdown is documentation, not a recipe"

mk "$TMP/snippet.md" <<'FIX'
# >>> the-check
D=$(@MKT@ -d)
# <<< the-check
FIX
runm "$TMP/snippet.md"
eq "$RC" 1 "a marker-fenced snippet in Markdown is lifted and run, so it is scanned"
has "$OUT" "snippet.md:2:" "and the finding names the line inside the fence"

mk "$TMP/formula.toml" <<'FIX'
description = """
Prose that mentions @MKT@ without running it.
```bash
D=$(@MKT@ -d)
```
"""
FIX
runm "$TMP/formula.toml"
eq "$RC" 1 "a fenced recipe in a formula is scanned"
has "$OUT" "formula.toml:4:" "the fenced line is the finding"
hasnt "$OUT" "formula.toml:2:" "the prose line above it is not"

mkdir -p "$TMP/lint-learned.d"
cp "$TMP/bare.sh" "$TMP/lint-learned.d/other-detector.sh"
runm "$TMP/lint-learned.d/other-detector.sh"
eq "$RC" 0 "the detector directory is skipped — the shape is stated there"

runm "$TMP/does-not-exist.sh"
eq "$RC" 0 "a path that is not a file drops out"

echo "── mktemp-untemplated: executable wrappers ──"

# A wrapper runs the command that follows it, so a bare call behind one is
# still an untemplated allocation. A recognizer that only knows the head of a
# line and a separator leaves the rule fail-open for every wrapped spelling.
mk "$TMP/wrapped.sh" <<'FIX'
#!/usr/bin/env bash
command @MKT@ -d
env TMPDIR=/var/tmp @MKT@ -d
time @MKT@ -d
exec @MKT@ -d
nohup @MKT@ -d
timeout 5 @MKT@ -d
FIX
runm "$TMP/wrapped.sh"
eq "$RC" 1 "a bare call behind an executable wrapper is still a call"
for n in 2 3 4 5 6 7; do
    has "$OUT" "wrapped.sh:$n:" "line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 6 "and nothing else is"

# The same wrappers in front of a chosen name stay clean, and `command -v`/`-V`
# look a name up without running it, so the operand is data, not a call.
mk "$TMP/wrapped-templated.sh" <<'FIX'
#!/usr/bin/env bash
command @MKT@ "${TMPDIR:-/tmp}/gctk-x.XXXXXX"
env TMPDIR=/var/tmp @MKT@ -d "${TMPDIR:-/tmp}/gctk-x.XXXXXX"
time @MKT@ -t gctk-x.XXXXXX
command -v @MKT@
command -V @MKT@
FIX
runm "$TMP/wrapped-templated.sh"
eq "$RC" 0 "a chosen name behind a wrapper, and a command -v/-V lookup, are clean"
eq "$OUT" "" "a clean file prints nothing"

echo "── mktemp-untemplated: quoted strings are data ──"

# A separator or the word inside a string literal is data the shell passes on,
# not a command. Treating it as one blocks unrelated shell changes on a false
# positive, since any detector finding fails the gate.
mk "$TMP/quoted.sh" <<'FIX'
#!/usr/bin/env bash
printf "literal; @MKT@ -d"
printf 'literal; @MKT@ -d'
echo "$x; @MKT@ -d"
FIX
runm "$TMP/quoted.sh"
eq "$RC" 0 "a separator and a call inside a quoted string are not a command"
eq "$OUT" "" "a clean file prints nothing"

# A command substitution runs even inside double quotes, so a bare call there
# is still found — collapsing quoted spans must not swallow it.
mk "$TMP/quoted-substitution.sh" <<'FIX'
#!/usr/bin/env bash
E="$(@MKT@ -d)"
FIX
runm "$TMP/quoted-substitution.sh"
eq "$RC" 1 "a bare call in a substitution inside double quotes is still a call"
has "$OUT" "quoted-substitution.sh:2:" "and the finding names its line"

echo "── mktemp-untemplated: here-doc bodies are data ──"

# The lines of a here-doc are fed to a command as input, not run, so a bare
# call in the body is not an allocation. The line after the terminator is
# ordinary code again. `<<-` and a plain `<<` both open a body.
mk "$TMP/heredoc.sh" <<'FIX'
#!/usr/bin/env bash
cat <<DOC
@MKT@ -d
DOC
cat <<-'END'
@MKT@ -d
END
@MKT@ -d
FIX
runm "$TMP/heredoc.sh"
eq "$RC" 1 "a here-doc body is not scanned, but code after the terminator is"
has "$OUT" "heredoc.sh:8:" "the real call after the here-docs is reported"
hasnt "$OUT" "heredoc.sh:3:" "the plain here-doc body is not"
hasnt "$OUT" "heredoc.sh:6:" "the <<- here-doc body is not"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 1 "and nothing else is"


echo
echo "lint-learned.d.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
