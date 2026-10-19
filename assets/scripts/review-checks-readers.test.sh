#!/usr/bin/env bash
# review-checks-readers.test.sh — one reader of the review guidance. A rig's
# review-checks.toml and docs/review-<check>.md are read at the commit being
# judged, laid over the pack's index, and only assets/scripts/review-checks.sh
# reads them. Every other script, formula, skill, doctor check and order asks it
# (--resolve, --show, --check, --extension), so no reader can fall back to a
# working tree or a pack copy on its own.
#
# The test looks for reads, not names: a git object read (show <oid>:<path>), a
# file read (cat, head, tail, source, a < redirect, a -r or -f test) and an
# index handed to the resolver as --file. signoff.sh names both files in what it
# tells a reviewer and reads neither, and prose names them freely.
# A fixture of each read shape proves the scan finds it, and a fixture of
# names proves it reads past them.
#
# Hermetic: reads this checkout's files and writes a mktemp fixture; no gc, bd,
# git or network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-checks-readers-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

# A guidance file: the index, or a check's extension.
GUIDE='(review-checks\.toml|docs/review-[^[:space:]"'"'"'`]*\.md)'
# The read shapes, as extended regexes over one line.
READS=(
  "show[^|;&]*:[^[:space:]]*$GUIDE"
  "(^|[[:space:];|&(\$])(cat|head|tail|source|\.)[[:space:]][^|;&]*$GUIDE"
  "<[[:space:]]*\"?[^[:space:]|;&]*$GUIDE"
  "-[rf][[:space:]]+\"?[^[:space:]]*$GUIDE"
  "--file[[:space:]=]+\"?[^[:space:]]*$GUIDE"
)

# reads <file> : each line of <file> that reads a guidance file, as <n>:<line>.
# A shell or TOML comment line is prose, not a read.
reads() {
  local re
  for re in "${READS[@]}"; do
    grep -nE -- "$re" "$1" 2>/dev/null
  done | grep -vE '^[0-9]+:[[:space:]]*#' | sort -t: -k1,1n -u
}

# The files a reader can live in: every script but the suites, every formula,
# skill, doctor check and order.
SCOPE=$(cd "$ROOT" && {
  find assets/scripts tools doctor -type f -name '*.sh' ! -name '*.test.sh'
  find formulas orders -type f -name '*.toml'
  find skills -type f -name '*.md'
} 2>/dev/null | sort)
[ -n "$SCOPE" ] && ok "the scope lists this checkout's scripts, formulas, skills, doctor checks and orders" \
  || bad "the scope lists this checkout's scripts, formulas, skills, doctor checks and orders" "nothing found under $ROOT"

FOUND=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$f" = "assets/scripts/review-checks.sh" ] && continue
  hits=$(reads "$ROOT/$f")
  [ -z "$hits" ] || FOUND="$FOUND$(printf '%s\n' "$hits" | sed "s|^|$f:|")
"
done <<< "$SCOPE"
eq "$FOUND" "" "no script, formula, skill, doctor check or order outside review-checks.sh reads the review guidance"

# Each read shape is found. The first, third and last are the shapes signoff.sh,
# review-dispatch-body.sh and liveness-sweep.sh read the index in before the
# resolver laid a rig's rows over the pack's.
cat > "$TMP/reads.sh" <<'FIXTURE'
git -C "$root" show "$OID:review-checks.toml" > "$blob"
t=$(git show "${REVIEWED_OID}:docs/review-arch.md")
IDX=$(cat "$root/review-checks.toml")
PURPOSE=$(head -5 "$GC_RIG_ROOT/docs/review-pm.md")
while read -r l; do :; done < "$root/review-checks.toml"
[ -r "$root/review-checks.toml" ] && echo readable
"$S/review-checks.sh" --resolve --check-set c --through merge --file "$HERE/../../review-checks.toml"
FIXTURE
eq "$(reads "$TMP/reads.sh" | wc -l | tr -d ' ')" "7" "every read shape in the fixture is found"

# Names are not reads.
cat > "$TMP/names.sh" <<'FIXTURE'
# reads review-checks.toml at the commit under review
warn "this change edits its own review guidance (review-checks.toml, docs/review-*.md)"
GUIDANCE_EDITS=$(printf '%s\n' "$paths" | awk '/^review-checks\.toml$/ || /^docs\/review-[^\/]*\.md$/')
The reviewed repo's `review-checks.toml` declares the check, and `docs/review-<check>.md` adds to it.
"$(gc kit scripts-dir)/review-checks.sh" --show --at "$REVIEWED_OID"
FIXTURE
eq "$(reads "$TMP/names.sh")" "" "a name, a message, a path pattern and a resolver call are not reads"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
