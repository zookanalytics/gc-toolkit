#!/usr/bin/env bash
# review-checks.test.sh — the one parser of the check-index grammar
# (assets/scripts/review-checks.sh). Asserts it emits <check>\t<method>\t<purpose>
# TSV, narrows with --check, and fails closed on a missing index, an undeclared
# check, and an index that declares nothing. Also asserts the repo's own
# review-checks.toml declares the forced baseline (correctness, triage).
#
# Hermetic: runs the script against fixtures in a mktemp dir; no gc, no bd, no
# network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/review-checks.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "'$2' has no '$3'" ;; esac; }

[ -x "$SUT" ] || { echo "missing or non-executable $SUT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-checks-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

IDX="$TMP/review-checks.toml"
cat >"$IDX" <<'TOML'
# a comment line, ignored
[checks.correctness]
method = "formulas/mol-review.toml"
purpose = "Is the change correct and safe as merged?"
phase = "pre-open"

[checks.triage]
method = "skills/review-triage/SKILL.md"
purpose = "Which specialist checks does this diff warrant?"
phase = "pre-open"

[checks.demo]
method = "skills/gc-demo-script/SKILL.md + skills/demo-capture/SKILL.md"
purpose = "Was the operator-watched surface recorded doing the thing?"
phase = "open-as-draft"

[unrelated]
method = "not-a-check"
TOML

# All rows.
OUT="$("$SUT" --file "$IDX")"; RC=$?
is  "all-rows exit 0" "$RC" "0"
is  "declares exactly three checks" "$(printf '%s\n' "$OUT" | grep -c .)" "3"
has "correctness row carries its method" "$OUT" "correctness	formulas/mol-review.toml	"
has "triage row present" "$OUT" "triage	skills/review-triage/SKILL.md	"
has "demo method keeps the + join" "$OUT" "gc-demo-script/SKILL.md + skills/demo-capture/SKILL.md"
case "$OUT" in *"unrelated"*) bad "a key outside [checks.*] is not read as a check" "leaked 'unrelated'" ;; *) ok "a key outside [checks.*] is not read as a check" ;; esac

# --check narrows to one row.
OUT="$("$SUT" --file "$IDX" --check triage)"; RC=$?
is  "--check exit 0" "$RC" "0"
is  "--check emits one row" "$(printf '%s\n' "$OUT" | grep -c .)" "1"
has "--check emits the asked row" "$OUT" "triage	skills/review-triage/SKILL.md	"

# --check for an undeclared check fails closed.
"$SUT" --file "$IDX" --check nonesuch >/dev/null 2>&1
is "undeclared --check exits 1" "$?" "1"

# A missing index fails closed.
"$SUT" --file "$TMP/nope.toml" >/dev/null 2>&1
is "missing index exits 1" "$?" "1"

# An index that declares no checks fails closed.
EMPTY="$TMP/empty.toml"; printf '# nothing here\n[other]\nx = "y"\n' >"$EMPTY"
"$SUT" --file "$EMPTY" >/dev/null 2>&1
is "index with no checks exits 1" "$?" "1"

# No --file is a usage error.
"$SUT" >/dev/null 2>&1
is "no --file exits 2" "$?" "2"

# The repo's own index declares the forced baseline and the arch specialist.
REAL="$REPO/review-checks.toml"
if [ -r "$REAL" ]; then
  "$SUT" --file "$REAL" --check correctness >/dev/null 2>&1
  is "repo index declares correctness" "$?" "0"
  "$SUT" --file "$REAL" --check triage >/dev/null 2>&1
  is "repo index declares triage" "$?" "0"
  "$SUT" --file "$REAL" --check arch >/dev/null 2>&1
  is "repo index declares the arch specialist check" "$?" "0"
  # Every check the real index declares carries a phase in the ordered set; an
  # unphased check falls to the resolver's pre-phase fallback and warns on every
  # resolve that names it, so the shipped index must not carry one.
  unphased=$("$SUT" --file "$REAL" | awk -F'\t' 'NF && $4 !~ /^(pre-open|open-as-draft|ready-for-review|merge)$/ { print $1 }')
  is "every check in the repo index declares a valid phase" "$unphased" ""
else
  bad "repo carries review-checks.toml" "no $REAL"
fi

# ---- the phase column ---------------------------------------------------------
OUT="$("$SUT" --file "$IDX")"
has "emit carries the phase column (correctness pre-open)" "$OUT" "correctness	formulas/mol-review.toml	Is the change correct and safe as merged?	pre-open"
has "emit carries open-as-draft (demo)" "$OUT" "	open-as-draft"
has "--check demo carries its phase" "$("$SUT" --file "$IDX" --check demo)" "	open-as-draft"

# ---- the resolver: phase-scoped gating sets ----------------------------------
excludes() { case "$2" in *"$3"*) bad "$1" "leaked '$3'" ;; *) ok "$1" ;; esac; }
count()    { printf '%s\n' "$1" | grep -c .; }

OUT="$("$SUT" --resolve --check-set "correctness,triage,demo" --through pre-open --file "$IDX" 2>/dev/null)"
is       "resolve --through pre-open: two checks" "$(count "$OUT")" "2"
has      "resolve pre-open has correctness" "$OUT" "correctness"
has      "resolve pre-open has triage" "$OUT" "triage"
excludes "resolve pre-open excludes open-as-draft demo" "$OUT" "demo"

OUT="$("$SUT" --resolve --check-set "correctness,triage,demo" --through open-as-draft --file "$IDX" 2>/dev/null)"
is  "resolve --through open-as-draft: three checks" "$(count "$OUT")" "3"
has "resolve open-as-draft includes demo" "$OUT" "demo"

OUT="$("$SUT" --resolve --check-set "correctness,triage,demo,approval,none,off" --through merge --file "$IDX" 2>/dev/null)"
is       "resolve --through merge drops the three non-lanes: three checks" "$(count "$OUT")" "3"
excludes "resolve drops approval" "$OUT" "approval"
excludes "resolve drops none" "$OUT" "none"
excludes "resolve drops off" "$OUT" "off"

# --with-phase emits <name>\t<phase>.
OUT="$("$SUT" --resolve --check-set "correctness,demo" --through merge --with-phase --file "$IDX" 2>/dev/null)"
has "--with-phase pairs correctness with pre-open" "$OUT" "correctness	pre-open"
has "--with-phase pairs demo with open-as-draft" "$OUT" "demo	open-as-draft"

# Dedupe on the lowercased form; the surviving token keeps its original case.
OUT="$("$SUT" --resolve --check-set "Correctness,correctness,TRIAGE" --through merge --file "$IDX" 2>/dev/null)"
is  "resolve dedupes case-folded duplicates: two checks" "$(count "$OUT")" "2"
has "resolve keeps the token's original case" "$OUT" "Correctness"

# An undeclared token defaults to pre-open — the dispatchable backstop — not the
# merge gate: pre-open is the one phase gate-ensure dispatches at every stage, so
# the token always has a path to its review rather than a merge-only gate that
# could hold the merge with no review produced. A live anchor still carrying a
# legacy token (e.g. `codex`) therefore keeps gating the create and stays
# satisfiable.
OUT="$("$SUT" --resolve --check-set "correctness,bogus" --through pre-open --file "$IDX" 2>/dev/null)"
has "undeclared token gates pre-open" "$OUT" "bogus"
# Pre-open precedes merge, so merge still lists it — now backed by a review the
# dispatcher can actually run. --with-phase pins the resolved phase as pre-open,
# proving it is not the unreachable merge-only backstop.
OUT="$("$SUT" --resolve --check-set "correctness,bogus" --through merge --with-phase --file "$IDX" 2>/dev/null)"
has "undeclared token still gates merge, carrying the pre-open phase" "$OUT" "bogus	pre-open"

# An empty set, or one naming only non-lanes, resolves to nothing at exit 0.
OUT="$("$SUT" --resolve --check-set "" --through merge --file "$IDX" 2>/dev/null)"; RC=$?
is "empty check-set: exit 0" "$RC" "0"
is "empty check-set: no gates" "$(count "$OUT")" "0"
OUT="$("$SUT" --resolve --check-set "none,off,approval" --through merge --file "$IDX" 2>/dev/null)"
is "non-lane-only check-set: no gates" "$(count "$OUT")" "0"

# A bad --through is a usage error.
"$SUT" --resolve --check-set "correctness" --through nonsense --file "$IDX" >/dev/null 2>&1
is "bad --through exits 2" "$?" "2"
"$SUT" --resolve --check-set "correctness" --file "$IDX" >/dev/null 2>&1
is "--resolve without --through exits 2" "$?" "2"

# An old-format index (no phase column) defaults every declared check to pre-open,
# so a branch cut before the phase column lands never opens an ungated PR.
OLDIDX="$TMP/old.toml"
printf '[checks.correctness]\nmethod = "m"\npurpose = "p"\n[checks.triage]\nmethod = "m"\npurpose = "p"\n' >"$OLDIDX"
OUT="$("$SUT" --resolve --check-set "correctness,triage" --through pre-open --file "$OLDIDX" 2>/dev/null)"
is "old index: declared-but-unphased defaults to pre-open" "$(count "$OUT")" "2"
ERR="$("$SUT" --resolve --check-set "correctness" --through pre-open --file "$OLDIDX" 2>&1 >/dev/null)"
has "an absent phase is named as absent" "$ERR" "is declared with no phase"

# A phase value outside the ordered set (misspelled or mis-cased) is an index
# error, not an absent phase: the resolve exits 1 so every caller holds, rather
# than demote a merge-phase check to pre-open and gate the create on it.
BADIDX="$TMP/badphase.toml"
printf '[checks.weird]\nmethod = "m"\npurpose = "p"\nphase = "Merge"\n[checks.fine]\nmethod = "m"\npurpose = "p"\nphase = "merge"\n' >"$BADIDX"
OUT="$("$SUT" --resolve --check-set "weird" --through merge --with-phase --file "$BADIDX" 2>/dev/null)"; RC=$?
is "an unrecognized phase fails the resolve (exit 1)" "$RC" "1"
ERR="$("$SUT" --resolve --check-set "weird" --through merge --file "$BADIDX" 2>&1 >/dev/null)"
has "…naming the bad value, not 'no phase'" "$ERR" "declares phase 'Merge', which is not a phase"
OUT="$("$SUT" --resolve --check-set "fine" --through merge --with-phase --file "$BADIDX" 2>/dev/null)"; RC=$?
is  "a set that does not name the malformed check still resolves" "$RC" "0"
has "…with its own declared phase" "$OUT" "fine	merge"
ERR="$("$SUT" --resolve --check-set "bogus" --through pre-open --file "$IDX" 2>&1 >/dev/null)"
has "an undeclared token's warning names the index that was read" "$ERR" "is not declared in the index ($IDX)"

# No readable index: every token is undeclared, so every non-lane token takes
# pre-open and gates every transition — rather than open an ungated PR. With
# --with-phase the tokens carry that same pre-open phase, so a reader that splits
# the set by phase sees exactly the gates the plain resolve holds on.
OUT="$("$SUT" --resolve --check-set "correctness,demo,approval,none" --through pre-open --file "$TMP/nope.toml" 2>/dev/null)"; RC=$?
is       "no-index fallback: exit 0" "$RC" "0"
is       "no-index fallback: both real tokens survive" "$(count "$OUT")" "2"
excludes "no-index fallback still drops approval" "$OUT" "approval"
OUT="$("$SUT" --resolve --check-set "correctness,demo" --through pre-open --with-phase --file "$TMP/nope.toml" 2>/dev/null)"
has "no-index --with-phase tags correctness pre-open" "$OUT" "correctness	pre-open"
has "no-index --with-phase tags demo pre-open, the phase it gates at" "$OUT" "demo	pre-open"
excludes "no-index --with-phase never tags a token merge" "$OUT" "	merge"

# --at reads the index from a commit (git show), the path the cadence uses.
# Fixture commits are unsigned: an operator's global commit.gpgsign would
# otherwise need a signing agent this hermetic run does not have.
commit_q() { git -C "$1" -c user.email=t@t.test -c user.name=t -c commit.gpgsign=false commit -q "${@:2}" >/dev/null 2>&1; }
GITREPO="$TMP/gitrepo"; mkdir -p "$GITREPO"
git -C "$GITREPO" init -q
cp "$IDX" "$GITREPO/review-checks.toml"
git -C "$GITREPO" add review-checks.toml
commit_q "$GITREPO" -m "index"
OID="$(git -C "$GITREPO" rev-parse --verify -q HEAD 2>/dev/null)"
if [ -n "$OID" ]; then
  OUT="$(cd "$GITREPO" && "$SUT" --resolve --check-set "correctness,demo" --through pre-open --at "$OID" 2>/dev/null)"
  is       "--at git-show: correctness is pre-open" "$(count "$OUT")" "1"
  excludes "--at git-show: demo excluded pre-open" "$OUT" "demo"
  OUT="$(cd "$GITREPO" && "$SUT" --resolve --check-set "correctness,demo" --through open-as-draft --at "$OID" 2>/dev/null)"
  has "--at git-show: demo included at open-as-draft" "$OUT" "demo"
else
  bad "--at git-show setup" "could not init a fixture git repo"
fi

# GC_REVIEW_CHECKS_INDEX overrides --at (the hermetic-test hook a cadence caller
# uses so its fake reviewed oid does not resolve the live checkout's index).
OUT="$(GC_REVIEW_CHECKS_INDEX="$IDX" "$SUT" --resolve --check-set "correctness,demo" --through pre-open --at deadbeef 2>/dev/null)"
is       "env override wins over --at: one pre-open check" "$(count "$OUT")" "1"
excludes "env override excludes the open-as-draft check" "$OUT" "demo"
OUT="$(GC_REVIEW_CHECKS_INDEX="$TMP/absent.toml" "$SUT" --resolve --check-set "correctness,demo" --through pre-open 2>/dev/null)"
is "env override set to a missing file forces the no-index fallback (both survive)" "$(count "$OUT")" "2"

# --at names a head this checkout has not fetched: the resolver fetches that commit
# from origin by id and reads ITS index, never the working tree's. Two local repos
# stand in for origin and the refinery's checkout; GC_RIG_ROOT is cleared so the
# only repository consulted is the clone.
ORIGIN="$TMP/origin"; CLONE="$TMP/clone"
mkdir -p "$ORIGIN" && git -C "$ORIGIN" init -q && cp "$IDX" "$ORIGIN/review-checks.toml" \
  && git -C "$ORIGIN" add review-checks.toml && commit_q "$ORIGIN" -m one \
  && git clone -q "$ORIGIN" "$CLONE" 2>/dev/null
# The head moves on origin after the clone, and its index moves demo to pre-open.
sed 's/^phase = "open-as-draft"$/phase = "pre-open"/' "$IDX" > "$ORIGIN/review-checks.toml"
commit_q "$ORIGIN" -am two
NEW="$(git -C "$ORIGIN" rev-parse --verify -q HEAD 2>/dev/null)"
if [ -n "$NEW" ] && [ -d "$CLONE/.git" ] && ! git -C "$CLONE" cat-file -e "$NEW^{commit}" 2>/dev/null; then
  OUT="$(cd "$CLONE" && env -u GC_RIG_ROOT "$SUT" --resolve --check-set "correctness,demo" --through pre-open --at "$NEW" 2>/dev/null)"; RC=$?
  is  "--at an unfetched head: exit 0" "$RC" "0"
  has "--at an unfetched head reads that head's index (demo is pre-open there)" "$OUT" "demo"
  git -C "$CLONE" cat-file -e "$NEW^{commit}" 2>/dev/null; is "…having fetched the commit into the clone" "$?" "0"
  # A commit neither the clone nor origin holds fails the resolve: no other
  # tree's index answers for it.
  OUT="$(cd "$CLONE" && env -u GC_RIG_ROOT "$SUT" --resolve --check-set "correctness" --through pre-open --at 0123456789abcdef0123456789abcdef01234567 2>/dev/null)"; RC=$?
  is "--at a commit that cannot be fetched: exit 1" "$RC" "1"
  is "…emitting no gates" "$(count "$OUT")" "0"
  # A commit that carries no index of its own falls through to the working tree.
  git -C "$CLONE" rm -q review-checks.toml && commit_q "$CLONE" -m noindex
  NOIDX="$(git -C "$CLONE" rev-parse --verify -q HEAD)"
  cp "$IDX" "$CLONE/review-checks.toml"
  OUT="$(cd "$CLONE" && env -u GC_RIG_ROOT "$SUT" --resolve --check-set "correctness,demo" --through pre-open --at "$NOIDX" 2>/dev/null)"; RC=$?
  is       "--at a commit with no index: exit 0" "$RC" "0"
  excludes "…the working-tree index stands in (demo stays open-as-draft)" "$OUT" "demo"
else
  bad "--at fetch fixture setup" "could not build the origin/clone pair"
fi

echo
echo "review-checks: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
