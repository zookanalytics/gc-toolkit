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
# Covered: raw-bd-invocation, mktemp-untemplated, bd-helper-in-scope.
#
# Hermetic: fixture files in a tempdir, the real detector run against them by
# path. No live city, no store, no network.
#
# doc-filing is covered too. Its fixture runs use a copy of the detector,
# which reads its gap list from beside itself. One section reads the
# repository's own gap list instead, because that list is data the tree has to
# keep true.

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

echo "── mktemp-untemplated: redirects and inline comments end the operands ──"

# A redirect and an inline comment are not templates. A redirect's fd number
# sits BEFORE its `<`/`>`, so a scan that dropped only the operator left the
# digit behind (`2` from `2>/dev/null`) and it read as a phantom operand — the
# bare call passed. A `#` opens a comment through end of line the same way.
# Both spellings appear on the real call sites this rule guards.
mk "$TMP/redirects-comments.sh" <<'FIX'
#!/usr/bin/env bash
A=$(@MKT@ 2>/dev/null)
B=$(@MKT@ -q -d 2>err)
C=$(@MKT@ 2>&1)
D=$(@MKT@ -d 3</dev/null)
E=$(@MKT@ >/tmp/out)
F=$(@MKT@ -d 2>/dev/null || printf '')
G=$(@MKT@ -p /var/tmp 2>/dev/null)
@MKT@ # trailing comment
FIX
runm "$TMP/redirects-comments.sh"
eq "$RC" 1 "a redirect or an inline comment does not stand in for a template"
for n in 2 3 4 5 6 7 8 9; do
    has "$OUT" "redirects-comments.sh:$n:" "line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 8 "and nothing else is"

# The same redirects and comments beside a chosen name stay clean: the fd
# number and the comment are stripped, and the template that survives is seen.
mk "$TMP/redirects-comments-templated.sh" <<'FIX'
#!/usr/bin/env bash
A=$(@MKT@ "${TMPDIR:-/tmp}/gctk-thing.XXXXXX" 2>/dev/null)
B=$(@MKT@ -d "${TMPDIR:-/tmp}/gctk-thing.XXXXXX" 2>/dev/null || printf '')
C=$(@MKT@ -t gctk-thing.XXXXXX 2>&1)
D=$(@MKT@ "${TMPDIR:-/tmp}/gctk-thing.XXXXXX" >/tmp/out)
@MKT@ "${TMPDIR:-/tmp}/gctk-thing.XXXXXX"  # trailing comment
FIX
runm "$TMP/redirects-comments-templated.sh"
eq "$RC" 0 "a chosen name beside a redirect or a comment is clean"
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

# A detector script is reachable code the runner executes, so a real bare call
# in one is a finding like any file. Only mktemp-untemplated.sh is exempt — its
# matching logic names the command in case patterns a text scanner cannot tell
# from a call.
mkdir -p "$TMP/lint-learned.d"
cp "$TMP/bare.sh" "$TMP/lint-learned.d/other-detector.sh"
runm "$TMP/lint-learned.d/other-detector.sh"
eq "$RC" 1 "a real bare call in a detector script is reported"
has "$OUT" "other-detector.sh:2:" "and the finding names its line"

cp "$TMP/bare.sh" "$TMP/lint-learned.d/mktemp-untemplated.sh"
runm "$TMP/lint-learned.d/mktemp-untemplated.sh"
eq "$RC" 0 "the mktemp detector itself is exempt — it spells the command in its own patterns"

mk "$TMP/lint-learned.d/prose-detector.sh" <<'FIX'
#!/usr/bin/env bash
# a bare @MKT@ -d here would leak; this line is prose
FIXTEXT='fix: @MKT@ -d "${TMPDIR:-/tmp}/gctk-x.XXXXXX"'
D=$(@MKT@ "${TMPDIR:-/tmp}/gctk-clean.XXXXXX")
FIX
runm "$TMP/lint-learned.d/prose-detector.sh"
eq "$RC" 0 "comments, quoted fix text, and a templated call in a scanned detector stay clean"

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

# An option a wrapper takes with a separate word, and timeout's own DURATION
# operand, are consumed with it — otherwise the operand stays in front of the
# real call and the wrapped bare mktemp reads as something else. timeout's
# duration can be a variable, so skipping only a leading digit left the ordinary
# spellings fail-open.
mk "$TMP/wrapped-option-args.sh" <<'FIX'
#!/usr/bin/env bash
env -u TMPDIR @MKT@ -d
timeout "$CALL_TIMEOUT" @MKT@ -d
timeout $CALL_TIMEOUT @MKT@ -d
timeout --kill-after 1s 5s @MKT@ -d
timeout -s TERM 5 @MKT@ -d
FIX
runm "$TMP/wrapped-option-args.sh"
eq "$RC" 1 "a wrapper option argument or a variable timeout duration does not mask the call"
for n in 2 3 4 5 6; do
    has "$OUT" "wrapped-option-args.sh:$n:" "line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 5 "and nothing else is"

# The same spellings in front of a chosen name stay clean: the option argument
# and the duration must not be mistaken for the template.
mk "$TMP/wrapped-option-args-templated.sh" <<'FIX'
#!/usr/bin/env bash
env -u TMPDIR @MKT@ -d "${TMPDIR:-/tmp}/gctk-x.XXXXXX"
timeout "$CALL_TIMEOUT" @MKT@ -d "${TMPDIR:-/tmp}/gctk-x.XXXXXX"
timeout --kill-after 1s 5s @MKT@ -t gctk-x.XXXXXX
FIX
runm "$TMP/wrapped-option-args-templated.sh"
eq "$RC" 0 "a chosen name behind a wrapper option argument or duration is clean"
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

# A `<<WORD` written inside a quoted string is data, not shell syntax, so it
# must not open a here-doc and swallow the real code after it. Reading the
# opener before quoted spans were accounted for left the rule fail-open here.
mk "$TMP/heredoc-in-quotes.sh" <<'FIX'
#!/usr/bin/env bash
printf 'cat <<EOF\n'
@MKT@ -d
FIX
runm "$TMP/heredoc-in-quotes.sh"
eq "$RC" 1 "a <<EOF mention inside a quoted string does not open a here-doc"
has "$OUT" "heredoc-in-quotes.sh:3:" "so the real bare call after it is reported"

# A terminator quoted to disable body expansion is still a real opener, and its
# body is still data — the fix must not lose that case while gaining the one above.
mk "$TMP/heredoc-quoted-term.sh" <<'FIX'
#!/usr/bin/env bash
cat <<'EOF'
@MKT@ -d
EOF
@MKT@ -d
FIX
runm "$TMP/heredoc-quoted-term.sh"
eq "$RC" 1 "a quoted here-doc terminator still opens a body that is skipped"
has "$OUT" "heredoc-quoted-term.sh:5:" "the real call after the here-doc is reported"
hasnt "$OUT" "heredoc-quoted-term.sh:3:" "the body of the quoted-terminator here-doc is not"

echo "── mktemp-untemplated: line continuations ──"

# A `\`-newline joins two physical lines into one command before the shell
# splits it, so `@MKT@ \` then `-d` runs as `@MKT@ -d`. Scanned a line at a
# time the trailing `\` reads as a surviving template operand and the bare
# continued call goes clean; the scanner folds continuations first so the whole
# call is judged at once, and reports it at the line the call opened on.
mk "$TMP/continued-bare.sh" <<'FIX'
#!/usr/bin/env bash
D=$(@MKT@ \
   -d)
E=$(@MKT@ \
   -q \
   -d)
FIX
runm "$TMP/continued-bare.sh"
eq "$RC" 1 "a bare call split across a line continuation is still a call"
has "$OUT" "continued-bare.sh:2:" "the single-continuation call is reported where it opened"
has "$OUT" "continued-bare.sh:4:" "the twice-continued call is reported where it opened"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 2 "and nothing else is"

# The same calls with a template past the continuation stay clean: folding must
# reveal the chosen name, not invent a finding.
mk "$TMP/continued-templated.sh" <<'FIX'
#!/usr/bin/env bash
A=$(@MKT@ \
   "${TMPDIR:-/tmp}/gctk-x.XXXXXX")
B=$(@MKT@ \
   -d \
   "${TMPDIR:-/tmp}/gctk-y.XXXXXX")
FIX
runm "$TMP/continued-templated.sh"
eq "$RC" 0 "a chosen name past a continuation is clean"
eq "$OUT" "" "a clean file prints nothing"

# `\\` at a line's end is an escaped literal backslash, not a continuation: the
# line does not fold, so a real bare call on the next line is judged on its own
# and still found. A fold that keyed off any trailing backslash would swallow
# that call and hide it.
mk "$TMP/continued-escaped.sh" <<'FIX'
#!/usr/bin/env bash
echo done \\
@MKT@ -d
FIX
runm "$TMP/continued-escaped.sh"
eq "$RC" 1 "an escaped trailing backslash does not fold the next line away"
has "$OUT" "continued-escaped.sh:3:" "so the real bare call after it is reported"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 1 "and nothing else is"

# The recipe surfaces fold continuations too: a bare call split across lines in
# a formula recipe or a marker-fenced snippet is run verbatim and is a finding.
mk "$TMP/continued.toml" <<'FIX'
description = """
```bash
D=$(@MKT@ \
   -d)
```
"""
FIX
runm "$TMP/continued.toml"
eq "$RC" 1 "a continued bare call in a formula recipe is scanned as one call"
has "$OUT" "continued.toml:3:" "and reported where it opened"

mk "$TMP/continued-clean.toml" <<'FIX'
description = """
```bash
A=$(@MKT@ \
   "${TMPDIR:-/tmp}/gctk-x.XXXXXX")
```
"""
FIX
runm "$TMP/continued-clean.toml"
eq "$RC" 0 "a continued chosen name in a recipe is clean"
eq "$OUT" "" "a clean file prints nothing"

mk "$TMP/continued.md" <<'FIX'
# >>> the-check
D=$(@MKT@ \
   -d)
# <<< the-check
FIX
runm "$TMP/continued.md"
eq "$RC" 1 "a continued bare call in a marker-fenced snippet is scanned as one call"
has "$OUT" "continued.md:2:" "and reported where it opened"

# ── doc-filing ──────────────────────────────────────────────────────────
#
# The detector reads paths relative to the repository root and its gap list
# from its own directory. So the fixture runs use a copy of it inside a
# fixture root, beside a fixture list.
DET_DF="$HERE/lint-learned.d/doc-filing.sh"
[ -x "$DET_DF" ] || { echo "no detector at $DET_DF"; exit 1; }
DF="$TMP/doc-filing"
mkdir -p "$DF/tools/lint-learned.d"
cp "$DET_DF" "$DF/tools/lint-learned.d/doc-filing.sh"
rundf() { OUT="$(cd "$DF" && tools/lint-learned.d/doc-filing.sh "$@" 2>&1)"; RC=$?; }
# page <path> — write a fixture page from stdin under the fixture root.
page() { mkdir -p "$DF/$(dirname "$1")" && cat > "$DF/$1"; }
gaps() { cat > "$DF/tools/lint-learned.d/doc-filing.gaps"; }

echo "── doc-filing: what is a finding ──"

gaps < /dev/null
page docs/new.md <<'MD'
---
name: New
description: A central page that never states its charter.
---

# New
MD
page docs/topic/nested.md <<'MD'
# Nested
MD
page docs/fenced.md <<'MD'
# Fenced

```markdown
## Scope
```
MD
page docs/deeper.md <<'MD'
# Deeper

### Scope
MD
page docs/longer.md <<'MD'
## Scope and history
MD
page docs/empty.md < /dev/null
page specs/tk-a/notes.md <<'MD'
# Notes with no frontmatter
MD
page specs/tk-a/name-only.md <<'MD'
---
name: Name only
---
MD
page specs/tk-a/blank.md <<'MD'
---
description: ""
---
MD
page specs/tk-a/null.md <<'MD'
---
description: ~
---
MD
page specs/tk-a/empty-fold.md <<'MD'
---
description: >
name: A folded value with no lines under it
---
MD
page specs/tk-a/unclosed.md <<'MD'
---
description: The block never closes, so it is not frontmatter.
MD
page specs/tk-a/late.md <<'MD'
# A title first

---
description: Frontmatter opens the page or it is not frontmatter.
---
MD
page specs/tk-a/nested-key.md <<'MD'
---
meta:
  description: Only a top-level key counts.
---
MD
page specs/tk-a/deep/er/notes.md <<'MD'
# Deep
MD
DF_NO_SCOPE=(docs/new.md docs/topic/nested.md docs/fenced.md docs/deeper.md docs/longer.md)
DF_NO_DESC=(specs/tk-a/notes.md specs/tk-a/name-only.md specs/tk-a/blank.md specs/tk-a/null.md
    specs/tk-a/empty-fold.md specs/tk-a/unclosed.md specs/tk-a/late.md specs/tk-a/nested-key.md
    specs/tk-a/deep/er/notes.md)
# docs/empty.md is named only as ./docs/empty.md, and docs/new.md both ways.
rundf "${DF_NO_SCOPE[@]}" "${DF_NO_DESC[@]}" ./docs/empty.md ./docs/new.md
eq "$RC" 1 "a page missing its tier's part exits 1"
for p in "${DF_NO_SCOPE[@]}" docs/empty.md; do
    has "$OUT" "$p:1: no \"## Scope\" section" "$p is reported for a missing Scope"
done
for p in "${DF_NO_DESC[@]}"; do
    has "$OUT" "$p:1: no frontmatter description" "$p is reported for a missing description"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 15 "each page is reported once, whatever spelling named it, and nothing else is"
has "$OUT" "specs/<bead-id>/" "a missing Scope names the other home a page can have"
has "$OUT" "\"Inside docs/\"" "and points at the placement rule"
has "$OUT" "(learned rule: doc-filing)" "the finding names the rule"

echo "── doc-filing: what is not ──"

page docs/good.md <<'MD'
---
name: Good
description: A central page with its charter.
---

# Good

## Scope

**Mandate.** What the page owns.
MD
page docs/bare.md <<'MD'
# Bare

A description is encouraged on a docs/ page, not required.

## Scope
MD
page docs/closing-hashes.md <<'MD'
## Scope ##
MD
page docs/after-fence.md <<'MD'
~~~sh
echo "a fence that closes"
~~~

## Scope
MD
page docs/rule-first.md <<'MD'
---
A page that opens with a rule it never closes has no frontmatter.

## Scope
MD
page docs/inline-code.md <<'MD'
`code` at the start of a line opens no fence.

## Scope
MD
page specs/tk-b/plain.md <<'MD'
---
name: Plain
description: Why the page exists.
---
MD
page specs/tk-b/folded.md <<'MD'
---
description: >-
  A folded value on the lines below its key.
---
MD
page specs/tk-b/next-line.md <<'MD'
---
description:
  A plain value that starts on the next line.
---
MD
page specs/tk-b/quoted.md <<'MD'
---
description: 'Quoted: a colon inside.'
---
MD
page specs/tk-b/no-scope.md <<'MD'
---
description: A spec page needs no Scope section.
---
MD
printf -- '---\r\ndescription: Written with CRLF line ends.\r\n---\r\n\r\n## Scope\r\n' > "$DF/specs/tk-b/crlf.md"
cp "$DF/specs/tk-b/crlf.md" "$DF/docs/crlf.md"
page docs/notes.txt <<'MD'
not markdown
MD
page README.md <<'MD'
# Outside both tiers
MD
page services/helm/docs/guide.md <<'MD'
# A docs directory below the root is not the central tier
MD
page generated/out.md <<'MD'
# Generated
MD
DF_GOOD=(docs/good.md docs/bare.md docs/closing-hashes.md docs/after-fence.md docs/rule-first.md
    docs/inline-code.md docs/crlf.md
    specs/tk-b/plain.md specs/tk-b/folded.md specs/tk-b/next-line.md specs/tk-b/quoted.md
    specs/tk-b/no-scope.md specs/tk-b/crlf.md)
rundf "${DF_GOOD[@]}" docs/notes.txt README.md services/helm/docs/guide.md generated/out.md docs/absent.md
eq "$RC" 0 "pages carrying their tier's part, and paths outside the tiers, are clean"
eq "$OUT" "" "a clean run prints nothing"

echo "── doc-filing: the gap list ──"

gaps <<'GAPS'
# A comment line and a blank line are not entries.

docs/new.md
  specs/tk-a/notes.md
docs/good.md
specs/tk-b/plain.md
# docs/fenced.md
docs/topic
docs/fenced.md.old
GAPS
rundf docs/new.md specs/tk-a/notes.md docs/good.md specs/tk-b/plain.md docs/fenced.md docs/topic/nested.md
eq "$RC" 1 "a listed page that has its part fails the run"
hasnt "$OUT" "docs/new.md:" "a listed docs/ page with no Scope is not reported"
hasnt "$OUT" "specs/tk-a/notes.md:" "a listed specs/ page with no description is not reported, whitespace around its entry aside"
has "$OUT" "docs/good.md:1: has a \"## Scope\" section now, so delete line 5 of tools/lint-learned.d/doc-filing.gaps" \
    "a listed page that gained its Scope must leave the list, and the finding names its line"
has "$OUT" "specs/tk-b/plain.md:1: has a frontmatter description now, so delete line 6 of" \
    "a listed page that gained its description must leave it too"
has "$OUT" "docs/fenced.md:1: no \"## Scope\"" \
    "a commented-out entry lists nothing, and neither does a longer path that starts with the page's"
has "$OUT" "docs/topic/nested.md:1: no \"## Scope\"" "an entry names one page, never a directory or a prefix"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 4 "and nothing else is reported"

rm "$DF/tools/lint-learned.d/doc-filing.gaps"
rundf docs/new.md
eq "$RC" 1 "with no gap list, no page is exempt"
has "$OUT" "docs/new.md:1: no \"## Scope\"" "and the page is reported"

echo "── doc-filing: a check that cannot read says so ──"

gaps < /dev/null
chmod 000 "$DF/docs/good.md"
if [ -r "$DF/docs/good.md" ]; then
    ok "an unreadable page (not exercised: this user can read anything)"
else
    rundf docs/good.md docs/new.md
    eq "$RC" 2 "an unreadable page is an error, never a pass"
    has "$OUT" "docs/good.md: cannot read it" "and the page is named"
    has "$OUT" "docs/new.md:1: no \"## Scope\"" "the readable pages are still checked"
fi
chmod 644 "$DF/docs/good.md"

chmod 000 "$DF/tools/lint-learned.d/doc-filing.gaps"
if [ -r "$DF/tools/lint-learned.d/doc-filing.gaps" ]; then
    ok "an unreadable gap list (not exercised: this user can read anything)"
else
    rundf docs/good.md
    eq "$RC" 2 "an unreadable gap list is an error, never a pass"
    has "$OUT" "cannot read the gap list" "and says so"
fi
chmod 644 "$DF/tools/lint-learned.d/doc-filing.gaps"

mkdir -p "$TMP/doc-filing-bin"
printf '#!/bin/sh\nexit 3\n' > "$TMP/doc-filing-bin/awk"
chmod +x "$TMP/doc-filing-bin/awk"
OUT="$(cd "$DF" && PATH="$TMP/doc-filing-bin:$PATH" tools/lint-learned.d/doc-filing.sh docs/new.md 2>&1)"; RC=$?
eq "$RC" 2 "a scan that fails is an error, never a pass"
has "$OUT" "the page scan failed" "and says so"

echo "── doc-filing: the repository's own gap list ──"

# The pages the list held when it was written. It may only lose them: an
# entry outside this set is a page that joined later, the one way the list
# could grow.
DF_STARTED='docs/authority-map.md
docs/cycle-recycle.md
docs/dolt-reclaim.md
docs/foundation.md
docs/gh-origin-guard.md
docs/install.md
docs/product-goals.md
docs/quota-park-recovery.md
docs/scratch-reclaim.md
docs/worktree-reclaim.md
specs/bead-universe/beads-created.md
specs/bead-universe/human-clarifications.md
specs/bead-universe/prd-draft.md
specs/bead-universe/prd-review.md
specs/tk-0tdy7/pilot-learnings.md
specs/tk-1zd25/design.md
specs/tk-2qa85/patrol-cadence-reaim.md
specs/tk-3d0uh/proactive-report.md
specs/tk-4abhrt/cutover-blockers.md
specs/tk-4abhrt/cutover.md
specs/tk-6d0vb.1/composable-check-options.md
specs/tk-eemvf/2026-06-30-001-feat-attention-canvas-plan.md
specs/tk-eemvf/design/attention-canvas-design-brief.md
specs/tk-eemvf/design/how-to.md
specs/tk-husu6/binding-report.md
specs/tk-mw3bso/operator-review-dispositions.md
specs/tk-oml75/spike-report.md
specs/tk-oqmc7/reachability-report.md
specs/tk-px5od/ideation.md
specs/tk-px5od/marching-orders.md
specs/tk-px5od/research-log.md
specs/tk-px5od/research/r1-toyota-production-system.md
specs/tk-px5od/research/r2-cheap-prototyping.md
specs/tk-px5od/research/r3-cheap-photography-curation.md
specs/tk-px5od/research/r4-recovery-oriented-computing.md
specs/tk-px5od/research/r5-amazon-coe.md
specs/tk-px5od/research/v1-red-team.md
specs/tk-px5od/research/v2-ai-native-prior-art.md
specs/tk-px5od/research/v3-skeptic.md
specs/tk-px5od/research/v4-ai-native-inventions.md
specs/tk-px5od/research/v5-inversions-within.md
specs/tk-px5od/research/v6-inversions-against-field.md
specs/tk-px5od/research/v7-hidden-metrics.md
specs/tk-px5od/roadmap.md
specs/tk-px5od/selection-menu.md'
DF_ROOT="$(cd "$HERE/.." && pwd)"
DF_LIVE=()
if [ -f "$DF_ROOT/tools/lint-learned.d/doc-filing.gaps" ]; then
    while IFS= read -r e || [ -n "$e" ]; do
        e="${e#"${e%%[![:space:]]*}"}"
        e="${e%"${e##*[![:space:]]}"}"
        case "$e" in '' | '#'*) continue ;; esac
        DF_LIVE+=("$e")
    done < "$DF_ROOT/tools/lint-learned.d/doc-filing.gaps"
fi
joined=""
gone=""
for e in ${DF_LIVE[@]+"${DF_LIVE[@]}"}; do
    case $'\n'"$DF_STARTED"$'\n' in *$'\n'"$e"$'\n'*) ;; *) joined+=" $e" ;; esac
    [ -f "$DF_ROOT/$e" ] || gone+=" $e"
done
eq "$joined" "" "every entry was on the list as it started, so the list only shrinks"
eq "$gone" "" "every entry names a page in the tree"
if [ "${#DF_LIVE[@]}" -gt 0 ]; then
    OUT="$(cd "$DF_ROOT" && tools/lint-learned.d/doc-filing.sh "${DF_LIVE[@]}" 2>&1)"; RC=$?
    eq "$OUT" "" "every listed page still lacks its part, so no entry is stale"
    eq "$RC" 0 "and the detector passes the list"
fi


echo "── bd-helper-in-scope: what is a finding ──"

# This detector's own subject is spelled with placeholders so the file that
# tests it is not itself a finding when the runner scans the whole tree:
# @J@ -> bd_json, @L@ -> bd_list, @LIB@ -> bd-lib.sh.
DET_BD="$HERE/lint-learned.d/bd-helper-in-scope.sh"
[ -x "$DET_BD" ] || { echo "no detector at $DET_BD"; exit 1; }
runbd() { OUT="$("$DET_BD" "$@" 2>&1)"; RC=$?; }
plantbd() { sed -e 's/@J@/bd_json/g' -e 's/@L@/bd_list/g' -e 's/@LIB@/bd-lib.sh/g' > "$1"; }

# A call to either helper with no definition and no library source dies at
# runtime.
plantbd "$TMP/dangling.sh" <<'FIX'
#!/usr/bin/env bash
out=$(@J@ show "$1")
@L@ --status open || true
FIX
runbd "$TMP/dangling.sh"
eq "$RC" 1 "a call with neither a def nor a source exits 1"
has "$OUT" "dangling.sh:2:" "the bd_json call is reported"
has "$OUT" "dangling.sh:3:" "the bd_list call is reported"
has "$OUT" "bd-helper-in-scope" "the finding names the rule"

# A call inside a double-quoted command substitution is a real runtime call —
# the surrounding quotes do not make it inert. Blanking the whole quoted span
# would miss it and leave the guard fail-open for the ordinary rows="$(...)"
# style.
plantbd "$TMP/quoted-cmdsub.sh" <<'FIX'
#!/usr/bin/env bash
rows="$(@L@ --status open)"
meta="$(@J@ show "$1")"
echo "$rows $meta"
FIX
runbd "$TMP/quoted-cmdsub.sh"
eq "$RC" 1 "a call inside a double-quoted command substitution is still a finding"
has "$OUT" "quoted-cmdsub.sh:2:" "the bd_list call in \"\$(...)\" is reported"
has "$OUT" "quoted-cmdsub.sh:3:" "the bd_json call in \"\$(...)\" is reported"

echo "── bd-helper-in-scope: what is not ──"

# Sourcing the library puts both helpers in scope.
plantbd "$TMP/sourced.sh" <<'FIX'
#!/usr/bin/env bash
_d="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=@LIB@
. "${GC_BD_LIB:-$_d/@LIB@}" || exit 1
out=$(@J@ show "$1")
rows=$(@L@ --status open) || true
FIX
runbd "$TMP/sourced.sh"
eq "$RC" 0 "a file that sources the library is clean"
eq "$OUT" "" "and prints nothing"

# A local definition puts that helper in scope — a purpose-built variant is not
# a finding.
plantbd "$TMP/defines.sh" <<'FIX'
#!/usr/bin/env bash
@L@() { run_bounded gc bd list "$@" --db "$RIG_DB" --json --limit 0; }
rows=$(@L@ --status open) || true
FIX
runbd "$TMP/defines.sh"
eq "$RC" 0 "a file that defines its own variant is clean"

# The name in a whole-line comment or a quoted string is prose, not a call.
plantbd "$TMP/prose.sh" <<'FIX'
#!/usr/bin/env bash
# @J@ swallows gc's exit through the pipe — a note, not a call
echo "use @L@ to read rows"
FIX
runbd "$TMP/prose.sh"
eq "$RC" 0 "a name in a comment or a string is not a call"

# A helper name passed as an argument inside a command substitution is not a
# call in command position — scanning the substitution's code must not
# over-report it.
plantbd "$TMP/cmdsub-arg.sh" <<'FIX'
#!/usr/bin/env bash
out="$(echo @L@ @J@)"
echo "$out"
FIX
runbd "$TMP/cmdsub-arg.sh"
eq "$RC" 0 "a helper name passed as an argument inside \$(...) is not a call"

# A definition line is not itself a call, even though the name is on it.
plantbd "$TMP/defonly.sh" <<'FIX'
#!/usr/bin/env bash
@J@() { gc bd "$@" --json; }
FIX
runbd "$TMP/defonly.sh"
eq "$RC" 0 "a definition is not read as a call to itself"

# Scope is per helper: a file that defines one but calls the other unscoped is
# flagged for exactly the dangling one.
plantbd "$TMP/mixed.sh" <<'FIX'
#!/usr/bin/env bash
@L@() { gc bd list "$@" --json; }
rows=$(@L@ --status open)
meta=$(@J@ show "$1")
FIX
runbd "$TMP/mixed.sh"
eq "$RC" 1 "one helper in scope, the other dangling, still fails"
has "$OUT" "bd_json" "the dangling helper is named"
hasnt "$OUT" "bd_list" "the in-scope helper is not"

# A shellcheck source directive is a comment, not a runtime source — it does not
# put the helper in scope.
plantbd "$TMP/directive-only.sh" <<'FIX'
#!/usr/bin/env bash
# shellcheck source=@LIB@
out=$(@J@ show "$1")
FIX
runbd "$TMP/directive-only.sh"
eq "$RC" 1 "a shellcheck source directive alone does not put the helper in scope"

# The detector ignores its own directory: the shapes are stated there.
mkdir -p "$TMP/lint-learned.d"
plantbd "$TMP/lint-learned.d/other-detector.sh" <<'FIX'
#!/usr/bin/env bash
out=$(@J@ show "$1")
FIX
runbd "$TMP/lint-learned.d/other-detector.sh"
eq "$RC" 0 "a file under lint-learned.d/ is skipped"

echo
echo "lint-learned.d.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
