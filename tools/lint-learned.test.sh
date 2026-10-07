#!/usr/bin/env bash
# lint-learned.test.sh — regression test for the runner's file-list contract.
#
# The runner is a gate: a rig wires it into `lint_command` and reads its exit
# code. That makes the enumeration, not the detectors, the part worth pinning.
# A detector that cannot see a file reports nothing, and reporting nothing is
# spelled the same way as a clean tree, so every path that fails to enumerate
# must exit 2 rather than 0.
#
# Asserted here:
#   - whole-tree mode reaches a tracked file no diff touches;
#   - an enumeration that fails exits 2, for a failing `git ls-files` and for
#     a failing `mktemp`;
#   - outside a git repository is exit 2, not a vacuous pass;
#   - argv mode lints exactly its arguments and nothing else;
#   - findings carry repo-relative paths whatever directory the caller is in;
#   - a detector that errors fails the run.
#
# Hermetic: builds a throwaway repo with a fixture detector and runs a copy of
# the runner inside it. No live city, no network, and the pack's own detectors
# never execute, so the suite stays green as the tree changes.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$HERE/lint-learned.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lint-learned-test.XXXXXX")" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Ambient git config must not reach the fixture repo.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

REPO="$TMP/repo"
mkdir -p "$REPO/tools/lint-learned.d" "$REPO/src"
cp "$RUNNER" "$REPO/tools/lint-learned.sh"

# The fixture detector stands in for the whole family: it flags one token, in
# the runner's finding format, so the assertions are about the runner. Like
# the real detectors it skips its own directory, where the token it hunts is
# stated rather than committed.
cat > "$REPO/tools/lint-learned.d/fixture.sh" <<'DET'
#!/usr/bin/env bash
set -uo pipefail
found=0
for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in */lint-learned.d/*) continue ;; esac
    while IFS= read -r hit; do
        echo "$f:${hit%%:*}: fixture violation"
        found=1
    done < <(grep -n PLANTED_VIOLATION "$f" 2>/dev/null)
done
[ "$found" -eq 0 ]
DET
chmod +x "$REPO/tools/lint-learned.d/fixture.sh"

echo 'clean file' > "$REPO/src/clean.sh"
echo 'also clean' > "$REPO/src/other.sh"
git -C "$REPO" init -q
git -C "$REPO" add -A          # ls-files reads the index; no commit needed

# run <dir> [args...] -> sets RC and OUT
run() { local d="$1"; shift; OUT="$(cd "$d" && "$REPO/tools/lint-learned.sh" "$@" 2>&1)"; RC=$?; }

echo "── 1. whole-tree mode reaches an untouched tracked file ──"
TRACKED="$(git -C "$REPO" ls-files | wc -l | tr -d ' ')"
run "$REPO"
eq "$RC" 0 "a clean tree passes"
has "$OUT" "$TRACKED file(s)" "every tracked file is enumerated"

echo 'PLANTED_VIOLATION' > "$REPO/src/planted.sh"
git -C "$REPO" add -A
run "$REPO"
eq "$RC" 1 "a violation anywhere in the tree fails the run"
has "$OUT" "src/planted.sh:1: fixture violation" "the finding names the file and line"

echo "── 2. an enumeration it cannot complete exits 2 ──"
BIN="$TMP/bin"; mkdir -p "$BIN"
REAL_GIT="$(command -v git)"
cat > "$BIN/git" <<GITSTUB
#!/usr/bin/env bash
# Fails the listing the way a corrupt index or an unreadable object store
# would, and passes everything else through.
if [ "\${1:-}" = "ls-files" ]; then
  echo "fatal: simulated index read failure" >&2
  exit 128
fi
exec "$REAL_GIT" "\$@"
GITSTUB
chmod +x "$BIN/git"
OUT="$(cd "$REPO" && PATH="$BIN:$PATH" "$REPO/tools/lint-learned.sh" 2>&1)"; RC=$?
eq "$RC" 2 "a failing git ls-files exits 2, not a green 0"
hasnt "$OUT" "lint-learned: OK" "and does not report OK"
has "$OUT" "cannot enumerate" "and says why"

BADTMP="$TMP/badtmp"; mkdir -p "$BADTMP"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BADTMP/mktemp"; chmod +x "$BADTMP/mktemp"
OUT="$(cd "$REPO" && PATH="$BADTMP:$PATH" "$REPO/tools/lint-learned.sh" 2>&1)"; RC=$?
eq "$RC" 2 "a failing mktemp exits 2"

echo "── 3. outside a git repository ──"
mkdir -p "$TMP/notarepo"
OUT="$(cd "$TMP/notarepo" && GIT_CEILING_DIRECTORIES="$TMP" "$REPO/tools/lint-learned.sh" 2>&1)"; RC=$?
eq "$RC" 2 "no repository to enumerate exits 2"
has "$OUT" "pass files on argv" "and names the way out"

echo "── 4. argv mode lints exactly its arguments ──"
run "$REPO" src/clean.sh
eq "$RC" 0 "the planted file is not read when it is not named"
has "$OUT" "1 file(s)" "only the named file is linted"

run "$REPO" src/planted.sh
eq "$RC" 1 "a named violating file fails"

run "$REPO" src/clean.sh /no/such/path
eq "$RC" 0 "a path that does not exist drops out"
has "$OUT" "1 file(s)" "and is not counted"

run "$REPO" /no/such/path
eq "$RC" 0 "an argv list that is entirely gone is a clean pass, not an error"
has "$OUT" "no files to lint" "and says so"

echo "── 5. findings are repo-relative from any cwd ──"
run "$REPO/src"
eq "$RC" 1 "invoked from a subdirectory, the whole tree is still read"
has "$OUT" "src/planted.sh:1:" "the path stays repo-relative"
hasnt "$OUT" "$REPO/src/planted.sh" "not absolute"

echo "── 6. a detector that errors fails the run ──"
rm "$REPO/tools/lint-learned.d/fixture.sh"
printf '#!/usr/bin/env bash\necho "detector blew up" >&2\nexit 3\n' \
    > "$REPO/tools/lint-learned.d/broken.sh"
chmod +x "$REPO/tools/lint-learned.d/broken.sh"
run "$REPO"
eq "$RC" 1 "an exit-3 detector is a failure, never a pass"
has "$OUT" "ERROR (exit 3)" "and is reported as a broken detector"

rm "$REPO/tools/lint-learned.d/broken.sh"
run "$REPO"
eq "$RC" 0 "no executable detectors is vacuously clean"
has "$OUT" "vacuously" "and says it was vacuous"

printf '\nlint-learned: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
