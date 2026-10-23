#!/usr/bin/env bash
# review-checks-readers.test.sh — one reader of the review guidance, and one
# list of the checks. A rig's
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
# A check is declared in an index and nowhere else, so no script or formula
# lists two or more of the pack's checks, the names taken from the pack's
# index, except where the default check_set is configured. A fixture of each
# list shape proves the scan finds it.
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

# Each read shape is found.
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

# --- One list -------------------------------------------------------------------
# A check is declared in an index and nowhere else, so no script or formula
# carries a list of two or more of the pack's checks, as a case alternation or a
# comma list. The one exception is the default check_set, which is
# configuration: gate-ensure.sh's --default, refinery-reconcile.sh's
# REFINERY_RECONCILE_CHECK_SET and mol-refinery-patrol's check_set var, with
# lifecycle/lifecycle.toml's check_set_default, which no scan here reads. The
# names come from the pack's index.
NAMES=$("$ROOT/assets/scripts/review-checks.sh" --file "$ROOT/review-checks.toml" 2>/dev/null | cut -f1 | paste -sd'|' -)
case "$NAMES" in
  *'|'*) ok "the pack's index names its checks ($NAMES)" ;;
  *) bad "the pack's index names its checks" "got '$NAMES'" ;;
esac
# lists <file> : each line of <file> that lists two of the checks, as <n>:<line>.
# A name is a whole word: review-arch and arch.md are not the check arch, and a
# shell default's `:-` opens a list as any separator does. A comment is prose.
lists() {
  grep -nE "(^|[^A-Za-z0-9_./-]|:-)($NAMES)[[:space:]]*[|,][[:space:]]*($NAMES)([^A-Za-z0-9_./-]|$)" "$1" 2>/dev/null \
    | grep -vE '^[0-9]+:[[:space:]]*#'
}
# configured <file> <n> <line> : whether the line is a site of the default check_set.
configured() {
  case "$1" in
    assets/scripts/gate-ensure.sh) case "$3" in *DEFAULT_CHECK_SET*) return 0 ;; esac ;;
    assets/scripts/refinery-reconcile.sh) case "$3" in *REFINERY_RECONCILE_CHECK_SET*) return 0 ;; esac ;;
    formulas/mol-refinery-patrol.toml)
      case "$3" in *CHECK_SET=*) return 0 ;; esac
      [ "$(awk -v n="$2" 'NR <= n && /^\[/ { h = $0 } NR == n { print h; exit }' "$ROOT/$1")" = "[vars.check_set]" ] && return 0 ;;
  esac
  return 1
}
LISTS=""; CONFIGURED=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in skills/*) continue ;; esac
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    if configured "$f" "${hit%%:*}" "${hit#*:}"; then CONFIGURED=$((CONFIGURED + 1)); continue; fi
    LISTS="$LISTS$f:$hit
"
  done <<< "$(lists "$ROOT/$f")"
done <<< "$SCOPE"
eq "$LISTS" "" "no script or formula lists two of the pack's checks outside the default check_set's configuration"
[ "$CONFIGURED" -gt 0 ] && ok "the default check_set's configuration is found by the scan ($CONFIGURED lines)" \
  || bad "the default check_set's configuration is found by the scan" "no configured line matched"

# Both list shapes are found, and names that are not a list are not.
cat > "$TMP/lists.sh" <<'FIXTURE'
case "$CHECK_NAME" in correctness|triage|demo) : ;; esac
GATES="arch, pm"
FIXTURE
eq "$(lists "$TMP/lists.sh" | wc -l | tr -d ' ')" "2" "a case alternation and a comma list of checks are found"
cat > "$TMP/not-lists.sh" <<'FIXTURE'
# correctness,triage is the default check_set
SKILL=review-arch,review-pm
cp docs/arch.md docs/pm.md
TRIAGE_GATE=triage
FIXTURE
eq "$(lists "$TMP/not-lists.sh")" "" "a comment, skill names, file names and one check are not lists"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
