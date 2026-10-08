#!/usr/bin/env bash
# lint-learned.d.test.sh — behaviour tests for the detectors in
# tools/lint-learned.d/. The runner's own contract is pinned separately in
# lint-learned.test.sh; this suite is about what a detector does and does not
# call a finding.
#
# run-tests-scope: tree
#
# It lives here rather than beside its subject because the runner executes
# every executable in lint-learned.d/ as a detector, so a test file in that
# directory would be run as one.
#
# Covered: raw-bd-invocation, mktemp-untemplated, zsh-colon-modifier,
# bd-helper-in-scope, bd-notes-replace, formula-unquoted-for, pr-post-bypass,
# id-read-unguarded.
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

# ── id-read-unguarded ───────────────────────────────────────────────────
#
# Fixtures spell the alternative's `//` as @OR@: the runner scans every tracked
# file, so the shape written literally here would be a finding against the test
# that proves the finding.
DET_ID="$HERE/lint-learned.d/id-read-unguarded.sh"
[ -x "$DET_ID" ] || { echo "no detector at $DET_ID"; exit 1; }
runid() { OUT="$("$DET_ID" "$@" 2>&1)"; RC=$?; }
plantid() { sed 's#@OR@#//#g' > "$1"; }

echo "── id-read-unguarded: what is a finding ──"

# Silencing jq's stderr does not make the read correct: an array answer still
# crashes at `.id` and reads as "no id" for a bead that was filed.
plantid "$TMP/id-violations.sh" <<'FIX'
#!/usr/bin/env bash
id=$(gc bd create "t" -t task --json | jq -r '.id @OR@ .[0].id')
id=$(gc bd create "t" -t task --json 2>/dev/null | jq -r '.id @OR@ .[0].id @OR@ empty' 2>/dev/null)
id=$(gc bd update "$X" --json | jq -r '.[0].id @OR@ .id')
id=$(printf '%s' "$J" | jq -r '.id@OR@.[0].id')
  -d "body" --json | jq -r '.id @OR@ .[0].id')
FIX
runid "$TMP/id-violations.sh"
eq "$RC" 1 "a file with an unguarded id read exits 1"
for n in 2 3 4 5 6; do
    has "$OUT" "id-violations.sh:$n:" "line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 5 "nothing else is reported"
has "$OUT" "id-read-unguarded" "the finding names the rule"
has "$OUT" 'if type == "array" then (.[0].id // empty) else (.id // empty) end' "the finding names the guarded read"

echo "── id-read-unguarded: what is not ──"

plantid "$TMP/id-clean.sh" <<'FIX'
#!/usr/bin/env bash
# jq -r '.id @OR@ .[0].id' is the shape the rule bans; a comment only states it
id=$(gc bd create "t" -t task --json | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
first=$(printf '%s' "$LIST" | jq -r '.[0].id // empty')
one=$(printf '%s' "$OBJ" | jq -r '.id // empty')
other=$(printf '%s' "$J" | jq -r '.idx @OR@ .[0].idx')
longer=$(printf '%s' "$J" | jq -r '.id @OR@ .[0].identity')
FIX
runid "$TMP/id-clean.sh"
eq "$RC" 0 "the guarded read, one-shape reads, a longer key and a comment are clean"
eq "$OUT" "" "a clean file prints nothing"

echo "── id-read-unguarded: fences run, prose quotes ──"

plantid "$TMP/id-doc.md" <<'FIX'
# A doc

Never read an id as `jq -r '.id @OR@ .[0].id'`; this line is prose.

```bash
OBS=$(gc bd create "obs" --json | jq -r '.id @OR@ .[0].id')
# jq -r '.id @OR@ .[0].id' in a comment inside the fence
```

~~~
id=$(jq -r '.[0].id @OR@ .id' <<< "$J")
~~~
FIX
runid "$TMP/id-doc.md"
eq "$RC" 1 "an unguarded read inside a doc's fence is a finding"
has "$OUT" "id-doc.md:6:" "a backtick fence is scanned"
has "$OUT" "id-doc.md:11:" "a tilde fence is scanned"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 2 "prose outside a fence, and a comment inside one, are not"

plantid "$TMP/id-formula.toml" <<'FIX'
[[steps]]
id = "file"
description = """
Never write `.id @OR@ .[0].id` in a step.
```bash
BEAD=$(gc bd create "t" --json | jq -r '.id @OR@ .[0].id')
```
"""
FIX
runid "$TMP/id-formula.toml"
eq "$RC" 1 "a formula step's fenced read is a finding"
has "$OUT" "id-formula.toml:6:" "and it is the fenced line that is reported"
hasnt "$OUT" "id-formula.toml:4:" "the step's prose is not"

echo "── id-read-unguarded: scope ──"

# The dated records quote the shape, renders duplicate their sources, and the
# detectors state the shapes they hunt.
mkdir -p "$TMP/specs/tk-x" "$TMP/generated" "$TMP/lint-learned.d"
for p in specs/tk-x/notes.sh generated/render.sh lint-learned.d/other.sh; do
    plantid "$TMP/$p" <<'FIX'
id=$(jq -r '.id @OR@ .[0].id' <<< "$J")
FIX
done
runid "$TMP/specs/tk-x/notes.sh" "$TMP/generated/render.sh" "$TMP/lint-learned.d/other.sh"
eq "$RC" 0 "specs/, generated/ and lint-learned.d/ are skipped"
plantid "$TMP/id-other.txt" <<'FIX'
id=$(jq -r '.id @OR@ .[0].id' <<< "$J")
FIX
runid "$TMP/id-other.txt" "$TMP/no-such-file.sh"
eq "$RC" 0 "a file outside *.sh, *.toml and *.md, and a path that is not a file, drop out"

echo "── id-read-unguarded: a detector that cannot scan says so ──"

mkdir -p "$TMP/shim-id"
printf '#!/usr/bin/env bash\nexit 2\n' > "$TMP/shim-id/grep"
chmod +x "$TMP/shim-id/grep"
OUT="$(PATH="$TMP/shim-id:$PATH" "$DET_ID" "$TMP/id-clean.sh" 2>&1)"; RC=$?
eq "$RC" 2 "a scan that cannot read its files exits 2, not 0 and not 1"
has "$OUT" "detector cannot scan" "and says so"

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

echo "── zsh-colon-modifier: what is a finding ──"

# The detector is path-scoped to agent-run surfaces, so fixtures are planted at
# matching paths under a root of their own. The shapes are spelled literally:
# this test file is not one of those paths, so the runner never reads it for
# this rule.
DET_ZC="$HERE/lint-learned.d/zsh-colon-modifier.sh"
[ -x "$DET_ZC" ] || { echo "no detector at $DET_ZC"; exit 1; }
runz() { OUT="$("$DET_ZC" "$@" 2>&1)"; RC=$?; }
ZC="$TMP/zc"
SKILL="$ZC/skills/s/SKILL.md"
mkdir -p "$ZC/formulas" "$ZC/agents/a" "$ZC/packs/k/agents/b" \
         "$ZC/template-fragments" "$ZC/skills/s" "$ZC/docs"

# Every in-scope surface is scanned: a formula TOML's description, agent prompt
# templates at the top level and under packs/, startup fragments, skills, and
# the named docs runbook.
cat > "$ZC/formulas/f.toml" <<'FIX'
description = """
```bash
git show "$REV:review-checks.toml"
```
"""
FIX
for p in agents/a/prompt.template.md packs/k/agents/b/prompt.template.md \
         template-fragments/frag.template.md skills/s/SKILL.md \
         docs/gascity-dispatch-containment.md; do
    cat > "$ZC/$p" <<'FIX'
```bash
git show "$REV:review-checks.toml"
```
FIX
done
runz "$ZC/formulas/f.toml" "$ZC/agents/a/prompt.template.md" \
     "$ZC/packs/k/agents/b/prompt.template.md" \
     "$ZC/template-fragments/frag.template.md" "$SKILL" \
     "$ZC/docs/gascity-dispatch-containment.md"
eq "$RC" 1 "an unbraced modifier in any in-scope surface is a finding"
has "$OUT" "formulas/f.toml:3:" "a formula TOML is scanned"
has "$OUT" "agents/a/prompt.template.md:2:" "a top-level agent prompt is scanned"
has "$OUT" "packs/k/agents/b/prompt.template.md:2:" "a pack agent prompt is scanned"
has "$OUT" "template-fragments/frag.template.md:2:" "a startup fragment is scanned"
has "$OUT" "skills/s/SKILL.md:2:" "a skill is scanned"
has "$OUT" "docs/gascity-dispatch-containment.md:2:" "the named docs runbook is scanned"
has "$OUT" 'unbraced $REV:r' "the finding names the expansion and its modifier"
has "$OUT" 'write ${REV}:r' "the finding names the fix"
has "$OUT" "zsh-colon-modifier" "the finding names the rule"

# Each modifier letter rewrites on its own, and g, w and f prefix a run of
# them. One line per shape, so the count proves none is missed or doubled.
{
    echo '```bash'
    for L in a c e h l q r s t u A P Q; do printf 'echo "$V:%sord"\n' "$L"; done
    for P in ga wh fr gwt; do printf 'echo "$V:%sx"\n' "$P"; done
    echo '```'
} > "$SKILL"
runz "$SKILL"
eq "$RC" 1 "the modifier letters are findings"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 17 "each modifier letter and prefixed run is reported once"
has "$OUT" 'unbraced $V:gwt' "a prefixed run is reported with the modifier it prefixes"

# Every context zsh expands in, one line each. The second line of a multi-line
# double-quoted string, an unquoted heredoc body, and the line after a quoted
# heredoc closes are each read in the context they really have. A `#` inside a
# word opens no comment. The sh and shell tags are shell too.
cat > "$SKILL" <<'FIX'
```bash
echo $V:hello
X=$V:hello
echo "$V:hello"
echo "$(printf '%s' "$V:hello")"
echo `echo $V:hello`
echo "'$V:hello'"
cat <<< "$V:hello"
KEY="pr:$REPO_SLUG#$N:comment:$CID"
echo pr:$REPO_SLUG#$N:comment
git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
echo "$1:h"
echo "$12:h"
echo "$?:h"
echo "first
second $V:hello"
cat <<EOF
body '$V:hello'
EOF
cat <<'EOF'
quoted
EOF
echo after $V:hello
echo "$V:hello" "$V:hello"
```
```sh
echo $V:hello
```
```shell
echo $V:hello
```
FIX
runz "$SKILL"
eq "$RC" 1 "every expanding context is a finding"
for n in 2 3 4 5 6 7 8 9 10 11 12 13 14 16 18 23 24 27 30; do
    has "$OUT" "SKILL.md:$n:" "SKILL.md line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 19 "nothing else is, and a line with two expansions is reported once"
has "$OUT" "SKILL.md:10: unbraced \$N:c" "a # inside an unquoted word opens no comment"
has "$OUT" 'unbraced $12:h' "a multi-digit positional parameter is read whole"

# A formula TOML is read through its basic-string escapes: `\\` there is one
# backslash, which escapes the `$` after it. The same bytes in markdown are an
# escaped backslash, and the expansion after them is live.
cat > "$ZC/formulas/esc.toml" <<'FIX'
description = """
```bash
echo \\$V:hello
```
"""
FIX
printf '%s\n' '```bash' 'echo \\$V:hello' '```' > "$SKILL"
runz "$ZC/formulas/esc.toml"
eq "$RC" 0 "an escaped dollar in a formula TOML is not a finding"
runz "$SKILL"
eq "$RC" 1 "the same bytes in markdown escape the backslash, not the dollar"

echo "── zsh-colon-modifier: what is not ──"

# Letters zsh keeps, characters that are not modifiers, braced names, and every
# context that does not expand. F and W read a delimited argument and are not
# flagged.
cat > "$SKILL" <<'FIX'
```bash
echo "$V:d $V:m $V:b $V:x $V:p $V:go $V:wx $V:fo $V:String $V:Feature $V:Worker"
echo "$V:- $V:= $V:+ $V:? $V:$X $V:443 $V:/ $V::h $V:"
echo "${V}:hello ${V:-x}:hello"
echo '$V:hello'
gh api graphql -f query='query($owner:String!, $after:String) { x }'
jq -r '
  "$V:hello"
' f
echo $'$V:hello'
echo \$V:hello "\$V:hello"
# echo $V:hello
echo hi # $V:hello
echo "$(jq -r '$V:hello' f)"
cat <<'EOF'
$V:hello
EOF
cat <<"EOF"
$V:hello
EOF
cat <<\EOF
$V:hello
EOF
X="$(cat <<'BODY'
$V:hello
BODY
)"
echo $(( N + 1 )):hello
```
FIX
runz "$SKILL"
eq "$RC" 0 "kept letters, non-modifiers, braced names and non-expanding contexts are not findings"
eq "$OUT" "" "and nothing is printed"

# The terminator of a <<- heredoc may be tab-indented. The quoted body ends
# there, so the line after it is scanned again.
printf '```bash\ncat <<-%sEOF%s\n\t$V:hello\n\tEOF\necho after $V:hello\n```\n' "'" "'" > "$SKILL"
runz "$SKILL"
eq "$RC" 1 "the line after a tab-indented terminator is scanned"
has "$OUT" "SKILL.md:5:" "and reported"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 1 "while the quoted body stays quiet"

# Only a fence tagged as shell is read. Untagged, text and zsh fences, and prose
# outside any fence, are not.
cat > "$SKILL" <<'FIX'
```
echo $V:hello
```
```text
echo $V:hello
```
```zsh
echo $V:hello
```
not fenced: echo $V:hello
FIX
runz "$SKILL"
eq "$RC" 0 "untagged, text and zsh fences and unfenced prose are not read"

# Scripts run under bash, where the shape is literal. A doc off the runbook list
# may show a broken command as a counter-example. specs/, generated/ and
# base-snapshots/ are frozen or rendered, and lint-learned.d/ states the shapes.
mkdir -p "$ZC/assets/scripts" "$ZC/specs/b/formulas" \
         "$ZC/generated/seed-audit/agents/a" "$ZC/base-snapshots/x/formulas" \
         "$ZC/lint-learned.d/skills/s"
printf '#!/usr/bin/env bash\ngit show "$REV:review-checks.toml"\n' > "$ZC/assets/scripts/x.sh"
for p in docs/other-doc.md specs/b/formulas/f.toml \
         generated/seed-audit/agents/a/prompt.template.md \
         base-snapshots/x/formulas/f.toml lint-learned.d/skills/s/SKILL.md; do
    printf '```bash\ngit show "$REV:review-checks.toml"\n```\n' > "$ZC/$p"
done
runz "$ZC/assets/scripts/x.sh" "$ZC/docs/other-doc.md" "$ZC/specs/b/formulas/f.toml" \
     "$ZC/generated/seed-audit/agents/a/prompt.template.md" \
     "$ZC/base-snapshots/x/formulas/f.toml" "$ZC/lint-learned.d/skills/s/SKILL.md" \
     "$ZC/does-not-exist.md"
eq "$RC" 0 "scripts, unlisted docs, frozen and rendered trees, and missing paths are out of scope"
eq "$OUT" "" "and nothing is printed"

echo "── zsh-colon-modifier: a detector that cannot scan says so ──"

# A failed scan prints nothing, so on its output alone it would pass for a clean
# file.
mkdir -p "$ZC/broken-awk"
printf '#!/bin/sh\nexit 2\n' > "$ZC/broken-awk/awk"
chmod +x "$ZC/broken-awk/awk"
printf '```bash\necho $V:hello\n```\n' > "$SKILL"
OUT="$(PATH="$ZC/broken-awk:${PATH:-}" "$DET_ZC" "$SKILL" 2>&1)"; RC=$?
eq "$RC" 2 "a scan that fails exits 2"
has "$OUT" "cannot scan" "and names the file it could not scan"

echo "── zsh-colon-modifier: the review-triage lines, unbraced ──"

# Put back the shape these two lines shipped with, and both are found in their
# real context, past every quote, heredoc and substitution above them. The
# braced skill is clean.
REAL_TRIAGE="$HERE/../skills/review-triage/SKILL.md"
MUT="$ZC/skills/review-triage/SKILL.md"
mkdir -p "$ZC/skills/review-triage"
sed -e 's/"${REVIEWED_OID}:review-checks.toml"/"$REVIEWED_OID:review-checks.toml"/' \
    -e 's/bead:${ANCHOR}:turn:/bead:$ANCHOR:turn:/' "$REAL_TRIAGE" > "$MUT"
L1="$(grep -nF '"$REVIEWED_OID:review-checks.toml"' "$MUT" | cut -d: -f1)"
L2="$(grep -nF 'bead:$ANCHOR:turn:' "$MUT" | cut -d: -f1)"
if [ -n "$L1" ] && [ -n "$L2" ]; then
    ok "both lines are unbraced in the copy"
else
    bad "both lines are unbraced in the copy" "the braced lines were not found in $REAL_TRIAGE"
fi
runz "$MUT"
eq "$RC" 1 "the unbraced lines are findings"
has "$OUT" "SKILL.md:$L1: unbraced \$REVIEWED_OID:r" "the index read is reported"
has "$OUT" "SKILL.md:$L2: unbraced \$ANCHOR:t" "the provenance key is reported"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 2 "and nothing else in the skill is"
runz "$REAL_TRIAGE"
eq "$RC" 0 "the braced skill is clean"

echo "── zsh-colon-modifier: every real shell fence is scanned to its end ──"

# A canary expansion goes in before the closing line of every shell fence in
# every in-scope file of this checkout. The scan must reach each canary in a
# context that expands and report nothing else. A quote, heredoc or
# substitution the scanner misread would run past its real end and hide the
# canary, or expose text that never expands.
ZC_ROOT="$(cd "$HERE/.." && pwd)"
CAN="$ZC/canary"
mkdir -p "$CAN"
: > "$CAN/.want"
mutants=()
while IFS= read -r p; do
    case "$p" in
        specs/* | */specs/* | generated/* | */generated/* \
        | base-snapshots/* | */base-snapshots/*) continue ;;
        formulas/*.toml | */formulas/*.toml \
        | template-fragments/*.template.md | */template-fragments/*.template.md \
        | agents/*/prompt.template.md | */agents/*/prompt.template.md \
        | skills/*/SKILL.md | */skills/*/SKILL.md \
        | docs/gascity-dispatch-containment.md) ;;
        *) continue ;;
    esac
    mkdir -p "$(dirname "$CAN/$p")"
    awk -v want="$CAN/.want" -v m="$CAN/$p" '
        function shell_fence(l,   lang) {
            lang = l
            sub(/^[[:space:]]*```[[:space:]]*/, "", lang)
            sub(/[[:space:]].*$/, "", lang)
            return (lang == "bash" || lang == "sh" || lang == "shell")
        }
        /^[[:space:]]*```/ {
            if (inb) { print "echo $CANARY:hello"; n++; print m ":" n >> want; inb = 0 }
            else if (other) other = 0
            else if (shell_fence($0)) inb = 1
            else other = 1
        }
        { print; n++ }
    ' "$ZC_ROOT/$p" > "$CAN/$p"
    mutants+=("$CAN/$p")
done < <(git -C "$ZC_ROOT" ls-files)
sort "$CAN/.want" > "$CAN/.want.sorted"
"$DET_ZC" ${mutants[@]+"${mutants[@]}"} | cut -d: -f1,2 | sort > "$CAN/.got"
FENCES="$(grep -c . "$CAN/.want.sorted")"
if [ "$FENCES" -gt 0 ]; then
    ok "the checkout has shell fences to plant ($FENCES in ${#mutants[@]} files)"
else
    bad "the checkout has shell fences to plant" "no in-scope shell fence found under $ZC_ROOT"
fi
if cmp -s "$CAN/.want.sorted" "$CAN/.got"; then
    ok "every canary is reported, and nothing else"
else
    bad "every canary is reported, and nothing else" "$(diff "$CAN/.want.sorted" "$CAN/.got" | head -20)"
fi

if command -v zsh >/dev/null 2>&1; then
    echo "── zsh-colon-modifier: a finding is exactly what zsh rewrites ──"

    # zsh and bash run each snippet with the same values, and the detector must
    # report it exactly when the two print different text. F and W are left
    # out: what zsh prints for them is not stable from run to run.
    ZPRE='V=x1/y2.z3 N=7 CID=9 REPO_SLUG=o/r BRANCH=polecat/tk-a.b; set -- p1/q1.r1 a b c d e f g h i j k12/l.m; true'
    zcheck() {
        local z b want
        printf '```bash\n%s\n```\n' "$1" > "$SKILL"
        z="$(cd "$ZC" && zsh -f -c "$ZPRE"$'\n'"$1" < /dev/null 2>&1)"
        b="$(cd "$ZC" && bash -c "$ZPRE"$'\n'"$1" < /dev/null 2>&1)"
        if [ "$z" = "$b" ]; then want=0; else want=1; fi
        runz "$SKILL"
        [ "$RC" = "$want" ] || ZMISS="$ZMISS
        [detector exit $RC, zsh output differs: $want] $1"
    }
    ZMISS=""
    for L in a b c d e f g h i j k l m n o p q r s t u v w x y z \
             A B C D E G H I J K L M N O P Q R S T U V X Y Z; do
        zcheck "printf '%s\n' \"\$V:${L}ord\""
    done
    for L in a h q x; do zcheck "printf '%s\n' \$V:${L}ord"; done
    for P in g w f gw ff; do
        for L in a h s Q o d; do zcheck "printf '%s\n' \"\$V:${P}${L}z\""; done
    done
    eq "$ZMISS" "" "every letter and prefixed run is a finding exactly when zsh rewrites it"

    ZMISS=""
    snip=""
    while IFS= read -r line; do
        if [ "$line" = "--" ]; then zcheck "$snip"; snip=""; continue; fi
        snip="$snip${snip:+$'\n'}$line"
    done <<'CASES'
X=$V:hello; printf '%s\n' "$X"
--
printf '%s\n' "$(printf '%s' "$V:hello")"
--
printf '%s\n' `printf '%s' $V:hello`
--
printf '%s\n' "'$V:hello'"
--
cat <<< "$V:hello"
--
KEY="pr:$REPO_SLUG#$N:comment:$CID"; printf '%s\n' "$KEY"
--
printf '%s\n' "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
--
printf '%s\n' "$1:h" "$12:h"
--
true; printf '%s\n' "$?:h"
--
printf '%s\n' "first
second $V:hello"
--
cat <<EOF
body $V:hello '$V:hello'
EOF
--
case $V:hello in x1ello) echo M ;; *) echo L ;; esac
--
[[ $V:hello == x1ello ]] && echo M || echo L
--
printf '%s\n' ${V}:hello "${V:-x}:hello"
--
printf '%s\n' "$V:- $V:= $V:+ $V:$N $V:443 $V:/ $V::h $V:"
--
printf '%s\n' "$V:?"
--
printf '%s\n' '$V:hello' $'$V:hello' \$V:hello "\$V:hello"
--
printf '%s\n' "$(printf '%s' '$V:hello')"
--
printf '%s\n' '
$V:hello
'
--
printf '%s\n' hi # $V:hello
--
cat <<'EOF'
$V:hello
EOF
--
cat <<\EOF
$V:hello
EOF
--
X="$(cat <<'BODY'
$V:hello
BODY
)"; printf '%s\n' "$X"
--
printf '%s\n' $(( N + 1 )):hello
--
printf '%s\n' "pr:$REPO_SLUG#$N"
--
CASES
    eq "$ZMISS" "" "every context is a finding exactly when zsh rewrites it"
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

echo "── bd-notes-replace: what is a finding ──"

# Fixtures spell the flag @NOTES@ and a bare client @BD@, for the reason the
# other detectors use placeholders: the runner scans this file too, and a
# literal write here would be a finding against the test that proves it.
DET_NR="$HERE/lint-learned.d/bd-notes-replace.sh"
[ -x "$DET_NR" ] || { echo "no detector at $DET_NR"; exit 1; }
runnr() { OUT="$("$DET_NR" "$@" 2>&1)"; RC=$?; }
plantnr() { sed -e 's/@NOTES@/--notes/g' -e 's/@BD@/bd/g' > "$1"; }

# Every spelling a notes write takes in this pack, one per line.
plantnr "$TMP/replace.sh" <<'FIX'
#!/usr/bin/env bash
gc bd update "$X" @NOTES@ "done"
@BD@ update "$X" @NOTES@="done"
gc_bd update "$X" @NOTES@ "done"
gc bd --rig "$R" update "$X" @NOTES@ "done"
"$BIN/gc" bd update "$X" --status=open @NOTES@ "done"
OUT="$(gc bd update "$X" @NOTES@ "done" 2>&1)"
FIX
runnr "$TMP/replace.sh"
eq "$RC" 1 "a file that replaces notes exits 1"
for n in 2 3 4 5 6 7; do
    has "$OUT" "replace.sh:$n:" "line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 6 "and nothing else is"
has "$OUT" "bd-notes-replace" "the finding names the rule"
has "$OUT" "fix: --append-notes" "the finding names the fix"

# A flag on a continued line belongs to the command it continues, and is
# reported where that command opens. A substitution between `update` and the
# flag is one word of the command, not its end.
plantnr "$TMP/continued.sh" <<'FIX'
#!/usr/bin/env bash
gc bd update "$X" \
    --set-metadata "at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --status=open \
    @NOTES@ "done"
echo between
gc bd update "$X" --assignee="$(whoami)" @NOTES@ "$(cat <<EOF
the body
EOF
)"
gc bd update "$X" --set-metadata at=$(date -u +%s) @NOTES@ "done"
FIX
runnr "$TMP/continued.sh"
eq "$RC" 1 "continued and substituted writes are found"
has "$OUT" "continued.sh:2:" "a continued write is reported where it opens"
has "$OUT" "continued.sh:7:" "a write whose value is a here-doc substitution is reported"
has "$OUT" "continued.sh:11:" "an unquoted substitution before the flag does not end the command"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 3 "and nothing else is"

# A formula recipe is run as written, so a fenced write is a finding and the
# same words in prose are not. A placeholder's stray quote in one fence does
# not carry into the next.
plantnr "$TMP/recipe.toml" <<'FIX'
description = """
Prose may say gc bd update {{issue}} @NOTES@ and it is not a finding.
```bash
gc bd update {{issue}} --set-metadata reason=<what's wrong>
```

```bash
gc bd update {{issue}} @NOTES@ "<summary>"
```
"""
FIX
runnr "$TMP/recipe.toml"
eq "$RC" 1 "a formula recipe that replaces notes exits 1"
has "$OUT" "recipe.toml:8:" "the fenced write is reported, past an unclosed quote in the fence before it"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 1 "prose outside a fence is not"

# A prompt or fragment carries its recipes in plain fences, often indented
# under a list item, and in marker-fenced snippets.
plantnr "$TMP/prompt.md" <<'FIX'
Never write `gc bd update <id> @NOTES@`: it replaces the field.

1. Record the card:
   ```bash
   gc bd update <id> @NOTES@ "..."       # the first-reaction card
   ```

# >>> marked-snippet
gc bd update "$W" @NOTES@ "x"
# <<< marked-snippet
FIX
runnr "$TMP/prompt.md"
eq "$RC" 1 "a prompt recipe that replaces notes exits 1"
has "$OUT" "prompt.md:5:" "an indented fenced write is reported"
has "$OUT" "prompt.md:9:" "a marker-fenced write is reported"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 2 "inline code in prose is not"

echo "── bd-notes-replace: what is not ──"

# Appends, other commands, and the shape stated as data: in a comment, a
# string, a multi-line string, a here-doc body, or a case pattern.
plantnr "$TMP/appends.sh" <<'FIX'
#!/usr/bin/env bash
# gc bd update "$X" @NOTES@ "done"   <- a commented-out write is prose
gc bd update "$X" --append-notes "done"   # never @NOTES@
gc bd update "$X" --append-notes "$(printf 'was %s' "$Y")"
gc bd create "title" @NOTES@ "a new bead has no notes to erase"
gc bd update "$X" --status=open; echo @NOTES@
gc bd update "$X" --status=open && printf '%s\n' @NOTES@
gc bd update "$X" @NOTES@-file findings.md
gc bd update "$X" --append-notes 'never @NOTES@ here, it replaces'
gc bd update "$X" --append-notes "never @NOTES@ here, it replaces"
echo "never run gc bd update X @NOTES@ y"
hasnt "$LOG" "bd update X @NOTES@" "a test that pins the shape holds it as data"
msg="first line
gc bd update X @NOTES@ y
last line"
cat <<'EOF'
gc bd update X @NOTES@ y
EOF
case "$1" in
    @NOTES@) shift; note="${1:-}" ;;
esac
FIX
runnr "$TMP/appends.sh"
eq "$RC" 0 "appends, other commands, comments, strings and here-doc bodies are clean"
eq "$OUT" "" "a clean file prints nothing"

echo "── bd-notes-replace: scope ──"

mkdir -p "$TMP/specs/tk-x" "$TMP/generated/agents" "$TMP/lint-learned.d"
cp "$TMP/replace.sh" "$TMP/specs/tk-x/repro.sh"
cp "$TMP/prompt.md" "$TMP/generated/agents/prompt.md"
cp "$TMP/replace.sh" "$TMP/lint-learned.d/other-detector.sh"
cp "$TMP/replace.sh" "$TMP/replace.go"
runnr "$TMP/specs/tk-x/repro.sh" "$TMP/generated/agents/prompt.md" \
    "$TMP/lint-learned.d/other-detector.sh" "$TMP/replace.go" "$TMP/does-not-exist.sh"
eq "$RC" 0 "specs/, generated/, the detector directory, other file types and missing paths are skipped"

echo "── bd-notes-replace: a detector that cannot scan says so ──"

# A scan that does not run reads every file as clean, so the detector must
# report itself broken rather than pass.
mkdir -p "$TMP/shim-awk"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/shim-awk/awk"
chmod +x "$TMP/shim-awk/awk"
OUT="$(PATH="$TMP/shim-awk:$PATH" "$DET_NR" "$TMP/replace.sh" 2>&1)"; RC=$?
eq "$RC" 2 "a failed scan exits 2, not 0 and not 1"
has "$OUT" "detector cannot scan it" "and says which file it could not scan"

echo "── formula-unquoted-for: what is a finding ──"

# This detector is PATH-SCOPED to the agent-executed surfaces, so fixtures are
# planted at paths that match that scope. The loop is spelled literally rather
# than through a placeholder because this test file is not one of those paths —
# the runner scanning the whole tree never scans it for this rule.
DET_FUF="$HERE/lint-learned.d/formula-unquoted-for.sh"
[ -x "$DET_FUF" ] || { echo "no detector at $DET_FUF"; exit 1; }
runf() { OUT="$("$DET_FUF" "$@" 2>&1)"; RC=$?; }

# Every in-scope surface is scanned: formula TOMLs, agent prompt templates
# (top-level and under packs/), startup fragments, skills, and the named docs
# runbook.
mkdir -p "$TMP/formulas" "$TMP/agents/refinery" "$TMP/packs/k/agents/keeper" \
         "$TMP/template-fragments" "$TMP/skills/s" "$TMP/docs"
for p in formulas/f.toml agents/refinery/prompt.template.md \
         packs/k/agents/keeper/prompt.template.md \
         template-fragments/frag.template.md \
         skills/s/SKILL.md \
         docs/gascity-dispatch-containment.md; do
    cat > "$TMP/$p" <<'FIX'
```bash
for x in $LIST; do echo "$x"; done
```
FIX
done
runf "$TMP/formulas/f.toml" "$TMP/agents/refinery/prompt.template.md" \
     "$TMP/packs/k/agents/keeper/prompt.template.md" \
     "$TMP/template-fragments/frag.template.md" \
     "$TMP/skills/s/SKILL.md" \
     "$TMP/docs/gascity-dispatch-containment.md"
eq "$RC" 1 "an unquoted loop in any in-scope surface is a finding"
has "$OUT" "formulas/f.toml:2:" "the formula TOML is scanned"
has "$OUT" "agents/refinery/prompt.template.md:2:" "a top-level agent prompt is scanned"
has "$OUT" "packs/k/agents/keeper/prompt.template.md:2:" "a pack agent prompt is scanned"
has "$OUT" "template-fragments/frag.template.md:2:" "a startup fragment is scanned"
has "$OUT" "skills/s/SKILL.md:2:" "a skill is scanned"
has "$OUT" "docs/gascity-dispatch-containment.md:2:" "the named docs runbook is scanned"
has "$OUT" "formula-unquoted-for" "the finding names the rule"

# Every parameter-expansion shape zsh leaves unsplit is a finding: the braced
# and defaulted forms, a positional parameter, a variable listed beside a
# command substitution, and a loop nested on the same line as another.
cat > "$TMP/formulas/params.toml" <<'FIX'
```bash
for x in ${LIST:-}; do echo "$x"; done
for x in $1; do echo "$x"; done
for x in $(cmd) $LIST; do echo "$x"; done
for r in $(cmd); do for x in $INNER; do echo "$x"; done; done
for r in a b; do for x in $INNER; do echo "$x"; done; done
x=1; for y in $LIST; do echo "$y"; done
```
FIX
runf "$TMP/formulas/params.toml"
eq "$RC" 1 "unsplit parameter expansions are findings"
for n in 2 3 4 5 6 7; do
    has "$OUT" "params.toml:$n:" "params.toml line $n is reported"
done

echo "── formula-unquoted-for: what is not ──"

# A quoted list, zsh's explicit \${=VAR} split, and a literal list are all fine;
# a loop outside a shell fence is prose, not executed.
cat > "$TMP/formulas/clean.toml" <<'FIX'
```bash
for x in "$LIST"; do echo "$x"; done
for x in ${=LIST}; do echo "$x"; done
for x in a b c; do echo "$x"; done
```
```text
for x in $LIST; do echo "$x"; done
```
not fenced at all: for x in $LIST; do echo "$x"; done
FIX
runf "$TMP/formulas/clean.toml"
eq "$RC" 0 "quoted, \${=VAR}, literal, and unfenced loops are not findings"
eq "$OUT" "" "and nothing is printed"

# zsh splits the output of an unquoted command substitution as sh does, so a
# list built from one iterates per word in both shells: $(cmd), backticks, and
# arithmetic, including a parameter inside the substitution and a substitution
# that continues onto the next line. A process substitution is one file name
# in both shells, and a parameter inside it is an argument, as in $(cmd). A
# one-line nested loop over a quoted list is not a finding either.
cat > "$TMP/formulas/cmdsub.toml" <<'FIX'
```bash
for extra in $(printf '%s\n' "$IDS" | sed '1d'); do burn "$extra"; done
for v in $(printf '%s' "$J" | jq -r '.vars[]?.name // empty'); do echo "$v"; done
for x in `cat $LISTFILE`; do echo "$x"; done
for i in $((N + 1)) $(seq 1 $N); do echo "$i"; done
for x in $(outer $(inner) $ARG); do echo "$x"; done
for id in $(gc bd list --json |
  jq -r '.[].id'); do echo "$id"; done
for r in $(cmd); do for x in "$Q"; do echo "$x"; done; done
for f in <(printf '%s\n' $IDS) >(cat); do echo "$f"; done
```
FIX
runf "$TMP/formulas/cmdsub.toml"
eq "$RC" 0 "command substitution lists are not findings"
eq "$OUT" "" "and nothing is printed"

echo "── formula-unquoted-for: quoted spans and substitutions are data ──"

# A list ends at its first top-level `;`, or at a `#` that starts a word. A `;`,
# `#`, quote or `do` inside a quoted span, a backslash escape, or a substitution
# is data, so an unsplit expansion after one is still a finding. `do` inside a
# list is an ordinary word, and a loop nested inside another's list is judged.
cat > "$TMP/formulas/spans.toml" <<'FIX'
```bash
for x in $(printf 'a;b') $LIST; do printf '[%s]' "$x"; done
for x in `printf a; printf b` $LIST; do printf '[%s]' "$x"; done
for x in 'a;b' $LIST; do printf '[%s]' "$x"; done
for x in "a;b" $LIST; do printf '[%s]' "$x"; done
for x in "a\";b" $LIST; do printf '[%s]' "$x"; done
for x in $'it\'s;' $LIST; do printf '[%s]' "$x"; done
for x in a\;b $LIST; do printf '[%s]' "$x"; done
for x in "it's" $LIST 'b'; do printf '[%s]' "$x"; done
for x in a#b $LIST; do printf '[%s]' "$x"; done
for x in "a #b" $LIST; do printf '[%s]' "$x"; done
for x in a do $LIST; do printf '[%s]' "$x"; done
for x in $(for y in $LIST; do printf '<%s>' "$y"; done); do printf '[%s]' "$x"; done
for x in ${#LIST} $LIST; do printf '[%s]' "$x"; done
for x in `printf '%s' a\`printf b\`` $LIST; do printf '[%s]' "$x"; done
for f in <(printf 'a;b') $LIST; do cat "$f"; done
```
FIX
runf "$TMP/formulas/spans.toml"
eq "$RC" 1 "an expansion after a terminator inside a span is a finding"
for n in 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    has "$OUT" "spans.toml:$n:" "spans.toml line $n is reported"
done

# The same spans hide what a raw scan would wrongly report. A `$` that is
# escaped, or that sits inside a quoted span or a substitution, is not an
# unquoted expansion, even where an apostrophe, a nested `(` or an escaped `)`
# would end that span early in a naive scan. Nor is a bare `$` before a span,
# an unquoted `$x` in the loop body, or a `$LIST` in a comment. A count ($#, a
# ${#VAR} length, arithmetic) is one number in both shells.
cat > "$TMP/formulas/spans-clean.toml" <<'FIX'
```bash
for x in $(printf 'a;b') "$LIST"; do printf '[%s]' "$x"; done
for x in "a;b" 'c;$d' "$(printf '%s;' "$LIST")"; do printf '[%s]' "$x"; done
for x in "`printf '%s' "$LIST"`"; do printf '[%s]' "$x"; done
for x in $(printf '%s ' $((N - 1)) $END); do printf '[%s]' "$x"; done
for x in $(printf '%s ' a\) $X); do printf '[%s]' "$x"; done
for x in "$LIST's" 'b'; do printf '[%s]' "$x"; done
for x in \$LIST; do printf '[%s]' "$x"; done
for x in $'it\'s' "$LIST"; do printf '[%s]' "$x"; done
for x in $`printf a` "$LIST"; do printf '[%s]' "$x"; done
for x in a b; do printf '[%s]' $x; done
for n in ${#LIST} $# $((1 + 1)); do printf '[%s]' "$n"; done
for x in a b # $LIST
do printf '[%s]' "$x"; done
```
FIX
runf "$TMP/formulas/spans-clean.toml"
eq "$RC" 0 "data in a span, the loop body, a comment, and a count are not findings"
eq "$OUT" "" "and nothing is printed"

# A newline ends a list only at the top level. Inside a quoted span or a
# substitution it is data, and after a backslash it continues the line, so the
# list runs on into the next line, and an unsplit expansion there is still a
# finding. Each finding is reported once, at the line its for-statement starts
# on, and that includes a loop that starts a later line inside a substitution,
# with or without a backslash continuation before it.
cat > "$TMP/formulas/spans-multiline.toml" <<'FIX'
```bash
for x in $(printf 'a\n'
  ) $LIST; do printf '[%s]' "$x"; done
for x in $(printf '%s\n' a |
  sed 's/a/b/' |
  cat) $LIST; do printf '[%s]' "$x"; done
for x in "a
b" $LIST; do printf '[%s]' "$x"; done
for x in 'a
b' $LIST; do printf '[%s]' "$x"; done
for x in $(printf a
for y in $LIST; do printf '<%s>' "$y"; done); do printf '[%s]' "$x"; done
for x in $LIST $(for y in $LIST; do
  printf '<%s>' "$y"; done); do printf '[%s]' "$x"; done
for x in a \
  $LIST; do printf '[%s]' "$x"; done
for x in a \
  $(printf b
for y in $LIST; do printf '<%s>' "$y"; done); do printf '[%s]' "$x"; done
```
FIX
runf "$TMP/formulas/spans-multiline.toml"
eq "$RC" 1 "an expansion after a line break inside a span or after a backslash is a finding"
for n in 2 4 7 9 12 13 15 19; do
    has "$OUT" "spans-multiline.toml:$n:" "spans-multiline.toml line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 8 "and each is reported once, at the line its for-statement starts on"

# A line break exposes nothing on its own. An expansion inside the span that
# holds the break is still data, and a top-level newline still ends a list,
# nested or not, so an unquoted $y or $x in the loop body after it is not a
# finding. A line that opens with `#` holds no loop, whether it is a comment
# inside a substitution or data inside a quote.
cat > "$TMP/formulas/spans-multiline-clean.toml" <<'FIX'
```bash
for x in $(printf '%s\n' $LIST
  ); do printf '[%s]' "$x"; done
for x in "a
$LIST"; do printf '[%s]' "$x"; done
for x in a b
do printf '[%s]' $x; done
for x in $(printf a
for y in b c
do printf '<%s>' $y; done); do printf '[%s]' "$x"; done
for x in $(printf a
# was: a; for y in $LIST; do :
); do printf '[%s]' "$x"; done
for x in "a
# b; for y in $LIST; do :
c"; do printf '[%s]' "$x"; done
```
FIX
runf "$TMP/formulas/spans-multiline-clean.toml"
eq "$RC" 0 "data in a multi-line span, a body after a top-level newline, and a #-led line are not findings"
eq "$OUT" "" "and nothing is printed"

# The shells are the ground truth. Each loop in the four fixtures above, one
# line or several, runs under zsh and under bash with a two-word LIST: every
# finding iterates differently in the two shells, and every clean loop alike.
# Skipped where zsh is not installed.
if command -v zsh >/dev/null 2>&1; then
    for fx in spans spans-clean spans-multiline spans-multiline-clean; do
        case "$fx" in *-clean) want=alike ;; *) want=differently ;; esac
        n=0; loop=""
        while IFS= read -r line; do
            n=$((n + 1))
            case "$line" in '```'*) continue ;; esac
            [ -n "$loop" ] || at=$n
            loop="${loop:+$loop
}$line"
            case "$line" in *'; done') ;; *) continue ;; esac
            z="$(zsh -f -c "LIST='c d'; $loop" 2>&1)"
            b="$(BASH_ENV='' bash -c "LIST='c d'; $loop" 2>&1)"
            loop=""
            got=alike; [ "$z" = "$b" ] || got=differently
            eq "$got" "$want" "$fx.toml:$at iterates $want under zsh and bash"
        done < "$TMP/formulas/$fx.toml"
    done
fi

# A list runs on only while the list itself is open. A list that ends with its
# line does not pull in the next line, and neither does a quote that opens
# after the list has ended, like the apostrophe in a trailing comment, so a
# commented-out loop on the next line stays a comment. The end of a block or
# of the file ends a list too: a list cut off there is judged as it stands,
# and the next block's loop is reported at its own line.
cat > "$TMP/formulas/list-ends.toml" <<'FIX'
```bash
for x in a b
# echo; for y in $LIST; do printf '[%s]' "$y"; done
do printf '[%s]' "$x"; done
for x in a b; do printf '[%s]' "$x"; done # don't
# echo; for y in $LIST; do printf '[%s]' "$y"; done
for y in $LIST; do printf '[%s]' "$y"; done
for x in $LIST $(printf a
```
```bash
for y in $LIST; do printf '[%s]' "$y"; done
```
```bash
for x in $LIST \
FIX
runf "$TMP/formulas/list-ends.toml"
eq "$RC" 1 "a list cut off by the end of its block or file is still judged"
for n in 7 8 11 14; do
    has "$OUT" "list-ends.toml:$n:" "list-ends.toml line $n is reported"
done
eq "$(printf '%s\n' "$OUT" | grep -c .)" 4 "and nothing else is, the commented-out loops included"

# Scope excludes rendered and frozen trees even when they carry the defect: the
# fix belongs in the source they render from or froze.
mkdir -p "$TMP/specs/b/formulas" "$TMP/generated/seed-audit/agents/a" \
         "$TMP/base-snapshots/x/formulas"
for p in specs/b/formulas/f.toml \
         generated/seed-audit/agents/a/prompt.template.md \
         base-snapshots/x/formulas/f.toml; do
    cat > "$TMP/$p" <<'FIX'
```bash
for x in $LIST; do echo "$x"; done
```
FIX
done
runf "$TMP/specs/b/formulas/f.toml" \
     "$TMP/generated/seed-audit/agents/a/prompt.template.md" \
     "$TMP/base-snapshots/x/formulas/f.toml"
eq "$RC" 0 "specs/, generated/, and base-snapshots/ are excluded"

# Docs are named one at a time, not matched by a docs/* glob — an ordinary doc
# whose fenced example happens to hold an unquoted loop is illustrative, not a
# runbook, and must not be flagged.
cat > "$TMP/docs/other-doc.md" <<'FIX'
```bash
for x in $LIST; do echo "$x"; done
```
FIX
runf "$TMP/docs/other-doc.md"
eq "$RC" 0 "a doc not on the runbook list is not scanned"

echo "── pr-post-bypass: what is a finding ──"

# Spelled with placeholders, so the file that tests the detector is not itself a
# finding when the runner scans the whole tree: @GH@ -> gh, @MUT@ ->
# addPullRequestReviewThreadReply, @ADDC@ -> addComment.
DET_PP="$HERE/lint-learned.d/pr-post-bypass.sh"
[ -x "$DET_PP" ] || { echo "no detector at $DET_PP"; exit 1; }
runpp() { OUT="$("$DET_PP" "$@" 2>&1)"; RC=$?; }
plantpp() { sed -e 's/@GH@/gh/g' -e 's/@MUT@/addPullRequestReviewThreadReply/g' -e 's/@ADDC@/addComment/g' > "$1"; }

# Every shape a post takes, one per line, so each assertion names its line. A
# continued command is reported at the line it opens on.
plantpp "$TMP/pp-violations.sh" <<'FIX'
#!/usr/bin/env bash
@GH@ pr comment "$PR" --repo "$R" --body "x"
out=$(@GH@ pr review "$PR" --comment --body-file "$F")
if @GH@ issue comment 5 --body "hi"; then :; fi
GH_TOKEN="$T" @GH@ pr comment 7 --body x
msg="$(@GH@ pr comment 8 --body y)"
x=`@GH@ pr review 9 --approve`
[ -n "$P" ] && @GH@ pr comment "$P" --body z || true
@GH@ api --method PATCH "repos/$R/issues/comments/$ID" --hostname h -f body="$B"
gh_api_origin -X POST "repos/$R/pulls/$N/comments" -f body="$B" -f path=a
@GH@ api "repos/$R/pulls/$N/comments/$C/replies" -f body="$B"
@GH@ api -X PUT "repos/$R/pulls/$N/reviews/$RID" -f body="$B"
@GH@ api graphql -f query='mutation($t:ID!,$b:String!){@MUT@(input:{pullRequestReviewThreadId:$t,body:$b}){clientMutationId}}' -f t="$T" -f b="$B"
@GH@ api "repos/$R/issues/$N/comments" \
  -f body="$B"
[ -n "$S" ] && @GH@ pr comment "$S" --repo "$Q" \
  --body "Superseded" >/dev/null 2>&1 || true
if ! @GH@ pr comment 1 --body x; then echo no; fi
FIX
runpp "$TMP/pp-violations.sh"
eq "$RC" 1 "a file that posts around the helper exits 1"
for n in 2 3 4 5 6 7 8 9 10 11 12 13 14 16 18; do
    has "$OUT" "pp-violations.sh:$n:" "line $n is reported"
done
hasnt "$OUT" "pp-violations.sh:15:" "a continuation line is judged with the line it continues"
hasnt "$OUT" "pp-violations.sh:17:" "…for a gh pr comment too"
eq "$(printf '%s\n' "$OUT" | grep -c 'pp-violations.sh:')" 15 "one finding per post"
has "$OUT" 'pp-violations.sh:3: posts with `gh pr review`' "the finding names the gh verb"
has "$OUT" 'pp-violations.sh:4: posts with `gh issue comment`' "…a conversation comment through the issue API included"
has "$OUT" 'pp-violations.sh:13: calls the GraphQL mutation `addPullRequestReviewThreadReply`' "a mutation finding names the mutation"
has "$OUT" "pp-violations.sh:9: writes a PR comment or review through \`gh api\`" "a REST write is named as one"
has "$OUT" "pr-post-bypass" "the finding names the rule"

# A GraphQL document is a string, so the field call is read wherever it sits: on
# a line of a multi-line document, or in a here-doc body.
plantpp "$TMP/pp-documents.sh" <<'FIX'
#!/usr/bin/env bash
Q='mutation($s:ID!,$b:String!){
  @ADDC@(input:{subjectId:$s,body:$b}){clientMutationId}
}'
@GH@ api graphql -f query="$Q" -f s="$S" -f b="$B"
D=$(cat <<'GQL'
mutation { @ADDC@ (input: {subjectId: "x", body: "y"}) { clientMutationId } }
GQL
)
FIX
runpp "$TMP/pp-documents.sh"
eq "$RC" 1 "a mutation in a multi-line document or a here-doc is a finding"
has "$OUT" "pp-documents.sh:3:" "the field call inside a multi-line string is reported"
has "$OUT" "pp-documents.sh:7:" "the field call inside a here-doc body is reported"
eq "$(printf '%s\n' "$OUT" | grep -c 'pp-documents.sh:')" 2 "the graphql call carrying the document is not a second finding"

# Fenced code in a formula or a prompt is a recipe an agent runs verbatim.
plantpp "$TMP/pp-formula.toml" <<'FIX'
[steps.reply]
description = """
Reply on the PR like this:

```bash
@GH@ pr comment "$PR" --body "done"
```

Prose that mentions @GH@ pr comment is not a recipe.
"""
FIX
runpp "$TMP/pp-formula.toml"
eq "$RC" 1 "a post in a formula's fenced recipe is a finding"
has "$OUT" "pp-formula.toml:6:" "the fenced post is reported"
hasnt "$OUT" "pp-formula.toml:9:" "prose outside the fence is not"
plantpp "$TMP/pp-prompt.md" <<'FIX'
# Guide

Never run `@GH@ pr comment` by hand.

```bash
@GH@ pr review "$PR" --comment --body x
```
# >>> snippet
@GH@ issue comment 3 --body y
# <<< snippet
FIX
runpp "$TMP/pp-prompt.md"
eq "$RC" 1 "a post in a prompt's fenced code is a finding"
has "$OUT" "pp-prompt.md:6:" 'the ``` fenced post is reported'
has "$OUT" "pp-prompt.md:9:" "the marker-fenced post is reported"
hasnt "$OUT" "pp-prompt.md:3:" "an inline code span in prose is not"

# A close or reopen handed a comment posts that comment.
plantpp "$TMP/pp-close.sh" <<'FIX'
#!/usr/bin/env bash
@GH@ pr close "$N" --repo "$Q" --comment "$CMT" >/dev/null 2>&1
if @GH@ pr reopen 5 -c "back again"; then :; fi
@GH@ issue close 3 --comment="done"
[ -n "$P" ] && @GH@ pr close "$P" --repo "$Q" \
  --comment "Superseded" || true
FIX
runpp "$TMP/pp-close.sh"
eq "$RC" 1 "a close or reopen that carries a comment is a finding"
for n in 2 3 4 5; do
    has "$OUT" "pp-close.sh:$n:" "line $n is reported"
done
hasnt "$OUT" "pp-close.sh:6:" "a continued close is judged with the line it opens on"
eq "$(printf '%s\n' "$OUT" | grep -c 'pp-close.sh:')" 4 "one finding per commented close"
has "$OUT" 'pp-close.sh:2: posts a comment with `gh pr close --comment`' "the finding names the gh verb"
has "$OUT" 'pp-close.sh:3: posts a comment with `gh pr reopen --comment`' "…a reopen included"
has "$OUT" 'pp-close.sh:4: posts a comment with `gh issue close --comment`' "…and the issue pair"

echo "── pr-post-bypass: what is not ──"

# Reads, writes that post no body, strings, comments, here-doc prose, a stub
# that names the mutation, and the helper's own call are none of them posts.
plantpp "$TMP/pp-clean.sh" <<'FIX'
#!/usr/bin/env bash
# @GH@ pr comment 12 --body "a comment line"
echo "run @GH@ pr comment 12 later"
printf '%s\n' '@GH@ pr review --approve'
"$SUT" --message "why" -- @GH@ issue comment 5 --repo a/b
cat <<'EOF'
Never run `@GH@ pr review --approve`; $(@GH@ pr comment) is for pr-post.sh.
EOF
raw=$(@GH@ api "repos/$R/issues/$N/comments" --paginate --hostname "$H")
@GH@ api "repos/$R/pulls/$N/comments?per_page=100" --paginate --jq '.[]'
@GH@ api -X PUT "repos/$R/pulls/$N/reviews/$RID/dismissals" -f message="m"
@GH@ api -X POST "repos/$R/issues/comments/$C/reactions" -f content=EYES
@GH@ api -X POST "repos/$R/pulls/$N/requested_reviewers" -f "reviewers[]=$L"
case "$q" in *@MUT@*) echo stub ;; esac
echo '{"data":{"@MUT@":{"clientMutationId":null}}}'
hasnt "$(cat "$LOG")" "@MUT@" "never replied twice"
"$PR_POST" comment --repo "$Q" --pr "$N" --body "$B"
gh_api_origin() { @GH@ api --hostname "$H" "$@"; }
@GH@ pr view 12 --json comments
@GH@ pr checkout 12
@GH@ pr close "$N" --repo "$Q" >/dev/null 2>&1
@GH@ pr close 5 --delete-branch && bash -c 'echo closed'
@GH@ pr reopen 5 --repo "$Q"
FIX
runpp "$TMP/pp-clean.sh"
eq "$RC" 0 "reads, dismissals, reactions, strings, comments, here-doc prose, stubs and uncommented closes are clean"
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT" | sed 's/^/        /'

# The helper is the one place the raw calls belong, and the detector skips its
# own directory and dated records.
mkdir -p "$TMP/pp-exempt/lint-learned.d" "$TMP/pp-exempt/specs"
plantpp "$TMP/pp-exempt/pr-post.sh" <<'FIX'
#!/usr/bin/env bash
@GH@ pr comment "$PR" --repo "$R" --body "$BODY"
FIX
cp "$TMP/pp-exempt/pr-post.sh" "$TMP/pp-exempt/lint-learned.d/other-detector.sh"
plantpp "$TMP/pp-exempt/specs/record.md" <<'FIX'
```bash
@GH@ pr comment 5 --body "what an old spec ran"
```
FIX
runpp "$TMP/pp-exempt/pr-post.sh" "$TMP/pp-exempt/lint-learned.d/other-detector.sh" "$TMP/pp-exempt/specs/record.md"
eq "$RC" 0 "pr-post.sh, lint-learned.d/ and specs/ are skipped"

echo
echo "lint-learned.d.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
