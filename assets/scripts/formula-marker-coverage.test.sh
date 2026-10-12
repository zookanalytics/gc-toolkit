#!/usr/bin/env bash
# formula-marker-coverage.test.sh — every marked block in a formula is named
# by a test.
#
# A formula marks a block of its shell (`# >>> <name>` to `# <<< <name>`) so a
# test can extract the shipped text verbatim and execute it. An extractor test
# fails when its own markers disappear. Nothing fails when the test itself
# disappears, so a deleted or rewritten test leaves its block looking pinned
# while nothing runs it. This suite fails instead: every marker in
# formulas/*.toml and packs/*/formulas/*.toml must be named by a tracked
# *.test.sh other than this one.
#
# A test names a marker when a line of it that is not a comment carries the
# marker's whole name. Extractors build the marker pattern at run time from a
# name they are handed (`extract submit-branch-gate "$TOML"`), so the name is
# what every test that runs a block carries, whatever its extraction looks
# like. A comment does not count, because a comment is what a rewrite leaves
# behind. A longer name that contains the marker's does not count, and neither
# does a file name that starts with it: `gate-visit.test.sh` names a test, not
# the gate-visit marker. The check is by name, so a name that several formulas
# share is covered once a test names it.
#
# A formula line that opens with `#` and then `>>>` or `<<<` must read exactly
# `# >>> <name>` or `# <<< <name>`. Extractors anchor on that shape, so a block
# marked any other way is extracted by nothing, and this suite reports the line
# rather than skipping it.
#
# Shared-snippet markers in scripts (control-char-scrub, gate-visit's script
# copies) follow a different convention, one canonical block copied into many
# hosts, and each has its own suite.
#
# Hermetic: reads tracked files through git ls-files. No gc, no city, no
# network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SELF="assets/scripts/formula-marker-coverage.test.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-formula-marker-coverage-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

# scan <root> — the formula markers in the tree at <root>, and the tests that
# name each one, as tab-separated lines:
#   marker     <formula>:<line>  <name>  <tests naming it, space-separated>
#   malformed  <formula>:<line>  <the line>
# A marker no test names has an empty last field. Returns 2 when git cannot
# list the tree's tracked files, which must never read as a tree with nothing
# in it.
scan() {
  local root="$1" listed f
  local -a formulas=() tests=()
  listed="$(git -C "$root" ls-files -- 'formulas/*.toml' 'packs/*/formulas/*.toml')" || return 2
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$root/$f" ] && formulas+=("$f")
  done <<< "$listed"
  listed="$(git -C "$root" ls-files -- '*.test.sh')" || return 2
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$root/$f" ] && [ "$f" != "$SELF" ] && tests+=("$f")
  done <<< "$listed"
  [ "${#formulas[@]}" -gt 0 ] || return 0
  # Every formula comes before every test on the command line, so the whole
  # set of names is known before the first test is read. A test line splits
  # into words of letters, digits, `_`, `-` and `.`, so a file name stays one
  # word. A period that ends a word is punctuation and is dropped.
  ( cd "$root" && LC_ALL=C awk '
    FILENAME ~ /\.toml$/ {
      if ($0 !~ /^[[:space:]]*#[[:space:]]*(>>>|<<<)/) next
      if ($0 !~ /^[[:space:]]*# (>>>|<<<) [A-Za-z0-9._-]+[[:space:]]*$/) {
        print "malformed\t" FILENAME ":" FNR "\t" $0
        next
      }
      if ($0 !~ /^[[:space:]]*# >>> /) next
      name = $0
      sub(/^[[:space:]]*# >>> /, "", name)
      sub(/[[:space:]]+$/, "", name)
      n++; marker[n] = name; where[n] = FILENAME ":" FNR; want[name] = 1
      next
    }
    /^[[:space:]]*#/ { next }
    {
      k = split($0, tok, /[^A-Za-z0-9._-]+/)
      for (i = 1; i <= k; i++) {
        t = tok[i]
        sub(/\.+$/, "", t)
        if (t == "" || !(t in want) || ((t, FILENAME) in named)) continue
        named[t, FILENAME] = 1
        by[t] = by[t] (by[t] == "" ? "" : " ") FILENAME
      }
    }
    END { for (i = 1; i <= n; i++) print "marker\t" where[i] "\t" marker[i] "\t" by[marker[i]] }
  ' "${formulas[@]}" ${tests[@]+"${tests[@]}"} )
}

# Field <n> of every <kind> line, sorted and space-joined.
field() { # <scan output> <kind> <n> [covered|uncovered]
  printf '%s\n' "$1" | awk -F'\t' -v kind="$2" -v n="$3" -v want="${4:-}" '
    $1 != kind { next }
    want == "covered" && $4 == "" { next }
    want == "uncovered" && $4 != "" { next }
    { print $n }' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}

echo "# the scan, on a tree built here"
# Each fixture marker is named in exactly one way, so a case that comes out
# covered or uncovered says which way counts.
FX="$TMP/fixture"
mkdir -p "$FX/formulas" "$FX/packs/p/formulas" "$FX/assets/scripts"
cat > "$FX/formulas/mol-fx.toml" <<'TOML'
[[steps]]
description = """
# >>> fx-called
echo called
# <<< fx-called
  # >>> fx-indented
  echo indented
  # <<< fx-indented
# >>> fx-sentence
echo sentence
# <<< fx-sentence
# >>> fx-comment-only
echo comment
# <<< fx-comment-only
# >>> fx-file-name
echo file
# <<< fx-file-name
# >>> fx-prefix
echo prefix
# <<< fx-prefix
# >>> fx-untracked
echo untracked
# <<< fx-untracked
# >>> fx-self
echo self
# <<< fx-self
#>>> fx-squashed
# >>> two words
"""
TOML
cat > "$FX/packs/p/formulas/mol-pk.toml" <<'TOML'
# >>> fx-pack
echo pack
# <<< fx-pack
TOML
cat > "$FX/assets/scripts/fx.test.sh" <<'SH'
#!/usr/bin/env bash
# fx-comment-only is named here, in a comment, and nowhere else.
extract fx-called "$TOML"
awk '/# >>> fx-indented$/ {f=1; next} /# <<< fx-indented$/ {f=0} f' "$TOML"
ok "the block runs as fx-sentence."
. "$HERE/fx-file-name.test.sh"
extract fx-prefix-longer "$TOML"
SH
printf 'extract fx-self "$TOML"\n' > "$FX/assets/scripts/formula-marker-coverage.test.sh"
git -c init.defaultBranch=main -C "$FX" init -q
git -C "$FX" add -A
printf 'extract fx-untracked "$TOML"\n' > "$FX/assets/scripts/untracked.test.sh"
OUT="$(scan "$FX")"; rc=$?
eq "$rc" "0" "the scan lists a git tree"
eq "$(field "$OUT" marker 3 covered)" "fx-called fx-indented fx-sentence" \
  "a name on a line of code counts, called, indented or ending a sentence"
eq "$(field "$OUT" marker 3 uncovered)" "fx-comment-only fx-file-name fx-pack fx-prefix fx-self fx-untracked" \
  "a comment, a file name, a longer name, this suite and an untracked test name nothing, and a pack formula is scanned"
eq "$(field "$OUT" marker 4 covered)" "assets/scripts/fx.test.sh assets/scripts/fx.test.sh assets/scripts/fx.test.sh" \
  "each covered marker names the test that names it"
eq "$(field "$OUT" malformed 2)" "formulas/mol-fx.toml:27 formulas/mol-fx.toml:28" \
  "a marker line extractors cannot match is reported, not skipped"
OUT="$(scan "$TMP/not-a-repo" 2>/dev/null)"; rc=$?
eq "$rc" "2" "a tree git cannot list fails the scan rather than reading as empty"

echo "# every formula marker in this tree is named by a test"
OUT="$(scan "$ROOT")"; rc=$?
[ "$rc" -eq 0 ] || bad "git could not list the tracked files under $ROOT (rc=$rc)"
MARKERS=0
while IFS=$'\t' read -r kind where name tests; do
  case "$kind" in
    marker)
      MARKERS=$((MARKERS + 1))
      if [ -n "$tests" ]; then
        ok "$where $name is named by $tests"
      else
        bad "$where $name is named by no test: nothing extracts and runs this block, so add a test that does, or remove the markers"
      fi ;;
    malformed)
      bad "$where reads '$name', a marker line no extractor matches: write it as '# >>> <name>' or '# <<< <name>'" ;;
  esac
done <<< "$OUT"
# A scan that found no marker is spelled the same as a clean one.
if [ "$MARKERS" -gt 0 ]; then
  ok "the scan read $MARKERS formula markers"
else
  bad "the scan read no formula marker under $ROOT, so it checked nothing"
fi

echo
echo "formula-marker-coverage: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
