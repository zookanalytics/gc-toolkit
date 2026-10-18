#!/usr/bin/env bash
# review-checks.test.sh — the one parser and resolver of the check index
# (assets/scripts/review-checks.sh). Asserts:
#   - the emit verbs print <check>\t<purpose>\t<phase> TSV, --check narrows by the
#     check's name case-folded, an older index's method key is ignored, and a
#     missing index, an undeclared check and an index that declares nothing fail
#     closed;
#   - the pack's own review-checks.toml declares the forced baseline, gives every
#     check a phase in the ordered set and a skill the pack ships, and carries no
#     method key;
#   - the resolver's phase-scoped gating sets, the non-lane drop, case-folded
#     dedupe, the undeclared and unphased pre-open defaults, and the refusal of a
#     phase outside the ordered set;
#   - the layered index: the pack's rows beside the script, a rig's rows laid over
#     them from the commit --at names and never from the working tree, a call that
#     names no commit refused unless --file or GC_REVIEW_CHECKS_INDEX names the
#     index, and --extension reading a commit's docs/review-<check>.md;
#   - --at fetching a commit the checkout has not fetched, and failing on one
#     nothing can fetch.
#
# Hermetic: runs the script against fixtures in a mktemp dir, with a fixture pack
# (a copy of the script under <pack>/assets/scripts beside a fixture index) and
# scratch git repositories; no gc, no bd, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/review-checks.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "'$2' has no '$3'" ;; esac; }
excludes() { case "$2" in *"$3"*) bad "$1" "leaked '$3'" ;; *) ok "$1" ;; esac; }
count()    { printf '%s\n' "$1" | grep -c .; }

[ -x "$SUT" ] || { echo "missing or non-executable $SUT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-checks-test.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# Nothing from the caller's city or git config reaches the fixtures.
unset GC_RIG_ROOT GC_REVIEW_CHECKS_INDEX GIT_DIR GIT_WORK_TREE 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

IDX="$TMP/review-checks.toml"
cat >"$IDX" <<'TOML'
# a comment line, ignored
[checks.correctness]
method = "skills/review-correctness/SKILL.md"
purpose = "Is the change correct and safe as merged?"
phase = "pre-open"

[checks.triage]
method = "skills/review-triage/SKILL.md"
purpose = "Which specialist checks does this diff warrant?"
phase = "pre-open"

[checks.demo]
purpose = "Was the operator-watched surface recorded doing the thing?"
phase = "open-as-draft"

[unrelated]
purpose = "not-a-check"
TOML

# ---- the emit verbs, over one named file ------------------------------------
OUT="$("$SUT" --file "$IDX")"; RC=$?
is  "all-rows exit 0" "$RC" "0"
is  "declares exactly three checks" "$(count "$OUT")" "3"
has "a row is name, purpose and phase" "$OUT" "correctness	Is the change correct and safe as merged?	pre-open"
has "triage row present" "$OUT" "triage	Which specialist checks does this diff warrant?	pre-open"
has "demo row carries open-as-draft" "$OUT" "demo	Was the operator-watched surface recorded doing the thing?	open-as-draft"
excludes "an older index's method key is ignored" "$OUT" "skills/review-correctness"
excludes "a key outside [checks.*] is not read as a check" "$OUT" "unrelated"
is  "--show prints the same rows" "$("$SUT" --show --file "$IDX")" "$OUT"

OUT="$("$SUT" --file "$IDX" --check triage)"; RC=$?
is  "--check exit 0" "$RC" "0"
is  "--check emits the asked row alone" "$OUT" "triage	Which specialist checks does this diff warrant?	pre-open"
"$SUT" --file "$IDX" --check nonesuch >/dev/null 2>&1
is "undeclared --check exits 1" "$?" "1"

# --check knows a check by its name case-folded, the rule --resolve matches a
# check_set token by, and emits the row as the index writes it.
OUT="$("$SUT" --file "$IDX" --check TRIAGE)"; RC=$?
is  "--check TRIAGE exit 0" "$RC" "0"
has "--check TRIAGE emits the triage row" "$OUT" "triage	Which specialist checks"
MIXED="$TMP/mixed-case.toml"
printf '[checks.Security]\nmethod = "m"\npurpose = "p"\nphase = "pre-open"\n' >"$MIXED"
OUT="$("$SUT" --file "$MIXED" --check security)"; RC=$?
is  "--check security exit 0 on a row written [checks.Security]" "$RC" "0"
is  "…and the row keeps the name the index wrote" "$OUT" "Security	p	pre-open"
# An empty purpose stays an empty column rather than folding the phase into it.
printf '[checks.bare]\nphase = "merge"\n' >"$TMP/bare.toml"
is "an empty purpose keeps its column" "$("$SUT" --file "$TMP/bare.toml" --check bare)" "bare		merge"

"$SUT" --file "$TMP/nope.toml" >/dev/null 2>&1
is "a missing index exits 1" "$?" "1"
EMPTY="$TMP/empty.toml"; printf '# nothing here\n[other]\nx = "y"\n' >"$EMPTY"
"$SUT" --file "$EMPTY" >/dev/null 2>&1
is "an index with no checks exits 1" "$?" "1"

# ---- a call that names neither a commit nor an index ----------------------------
"$SUT" >/dev/null 2>&1
is "no arguments exit 2" "$?" "2"
ERR="$("$SUT" --show 2>&1 >/dev/null)"; RC=$?
is  "--show with no commit exits 2" "$RC" "2"
has "…saying no commit was named" "$ERR" "no commit named"
"$SUT" --resolve --check-set correctness --through merge --at "" >/dev/null 2>&1
is "--resolve with --at \"\" exits 2" "$?" "2"
"$SUT" --resolve --show --at HEAD >/dev/null 2>&1
is "two verbs in one call exit 2" "$?" "2"

# ---- the pack's own index -----------------------------------------------------
REAL="$REPO/review-checks.toml"
if [ -r "$REAL" ]; then
  for c in correctness triage arch; do
    "$SUT" --file "$REAL" --check "$c" >/dev/null 2>&1
    is "the pack's index declares $c" "$?" "0"
  done
  # Every check declares a phase in the ordered set: an unphased check falls to
  # the resolver's pre-open default and warns on every resolve that names it.
  ERR="$("$SUT" --file "$REAL" 2>&1 >/dev/null)"
  is "every check in the pack's index declares a valid phase" "$ERR" ""
  # Every check's method is the skill named from the check, so every check the
  # pack declares has one the pack ships.
  unshipped=$("$SUT" --file "$REAL" 2>/dev/null | cut -f1 \
    | while IFS= read -r c; do
        [ -n "$c" ] && [ ! -f "$REPO/skills/review-$(printf '%s' "$c" | tr '[:upper:]' '[:lower:]')/SKILL.md" ] && printf '%s ' "$c"
      done)
  is "every check the pack's index declares has its skills/review-<check>/SKILL.md" "$unshipped" ""
  is "the pack's index carries no method key" "$(grep -cE '^[[:space:]]*method[[:space:]]*=' "$REAL")" "0"
else
  bad "the pack carries review-checks.toml" "no $REAL"
fi

# ---- the resolver: phase-scoped gating sets ----------------------------------
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

OUT="$("$SUT" --resolve --check-set "correctness,demo" --through merge --with-phase --file "$IDX" 2>/dev/null)"
has "--with-phase pairs correctness with pre-open" "$OUT" "correctness	pre-open"
has "--with-phase pairs demo with open-as-draft" "$OUT" "demo	open-as-draft"

# Dedupe on the lowercased form; the surviving token keeps its original case.
OUT="$("$SUT" --resolve --check-set "Correctness,correctness,TRIAGE" --through merge --file "$IDX" 2>/dev/null)"
is  "resolve dedupes case-folded duplicates: two checks" "$(count "$OUT")" "2"
has "resolve keeps the token's original case" "$OUT" "Correctness"

# An undeclared token defaults to pre-open, the dispatchable backstop, not the
# merge gate: pre-open is the one phase gate-ensure dispatches at every stage, so
# the token always has a path to its review rather than a merge-only gate that
# could hold the merge with no review produced. A live anchor still carrying a
# legacy token (e.g. `codex`) therefore keeps gating the create and stays
# satisfiable.
OUT="$("$SUT" --resolve --check-set "correctness,bogus" --through pre-open --file "$IDX" 2>/dev/null)"
has "undeclared token gates pre-open" "$OUT" "bogus"
OUT="$("$SUT" --resolve --check-set "correctness,bogus" --through merge --with-phase --file "$IDX" 2>/dev/null)"
has "undeclared token still gates merge, carrying the pre-open phase" "$OUT" "bogus	pre-open"
ERR="$("$SUT" --resolve --check-set "bogus" --through pre-open --file "$IDX" 2>&1 >/dev/null)"
has "an undeclared token's warning names the index that was read" "$ERR" "is not declared in the index ($IDX)"

# An empty set, or one naming only non-lanes, resolves to nothing at exit 0.
OUT="$("$SUT" --resolve --check-set "" --through merge --file "$IDX" 2>/dev/null)"; RC=$?
is "empty check-set: exit 0" "$RC" "0"
is "empty check-set: no gates" "$(count "$OUT")" "0"
OUT="$("$SUT" --resolve --check-set "none,off,approval" --through merge --file "$IDX" 2>/dev/null)"
is "non-lane-only check-set: no gates" "$(count "$OUT")" "0"

"$SUT" --resolve --check-set "correctness" --through nonsense --file "$IDX" >/dev/null 2>&1
is "bad --through exits 2" "$?" "2"
"$SUT" --resolve --check-set "correctness" --file "$IDX" >/dev/null 2>&1
is "--resolve without --through exits 2" "$?" "2"

# An index with no phase column defaults every declared check to pre-open, so a
# branch cut before the phase column never opens an ungated PR.
OLDIDX="$TMP/old.toml"
printf '[checks.correctness]\nmethod = "m"\npurpose = "p"\n[checks.triage]\nmethod = "m"\npurpose = "p"\n' >"$OLDIDX"
OUT="$("$SUT" --resolve --check-set "correctness,triage" --through pre-open --file "$OLDIDX" 2>/dev/null)"
is "old index: declared-but-unphased defaults to pre-open" "$(count "$OUT")" "2"
ERR="$("$SUT" --resolve --check-set "correctness" --through pre-open --file "$OLDIDX" 2>&1 >/dev/null)"
has "an absent phase is named as absent" "$ERR" "is declared with no phase"
is "--check of an unphased row prints the pre-open it gates at" "$("$SUT" --file "$OLDIDX" --check triage 2>/dev/null)" "triage	p	pre-open"

# A phase value outside the ordered set (misspelled or mis-cased) is an index
# error, not an absent phase: the resolve exits 1 so every caller holds, rather
# than demote a merge-phase check to pre-open and gate the create on it.
BADIDX="$TMP/badphase.toml"
printf '[checks.weird]\npurpose = "p"\nphase = "Merge"\n[checks.fine]\npurpose = "p"\nphase = "merge"\n' >"$BADIDX"
"$SUT" --resolve --check-set "weird" --through merge --with-phase --file "$BADIDX" >/dev/null 2>&1
is "an unrecognized phase fails the resolve (exit 1)" "$?" "1"
ERR="$("$SUT" --resolve --check-set "weird" --through merge --file "$BADIDX" 2>&1 >/dev/null)"
has "…naming the bad value, not 'no phase'" "$ERR" "declares phase 'Merge', which is not a phase"
OUT="$("$SUT" --resolve --check-set "fine" --through merge --with-phase --file "$BADIDX" 2>/dev/null)"; RC=$?
is  "a set that does not name the malformed check still resolves" "$RC" "0"
has "…with its own declared phase" "$OUT" "fine	merge"
"$SUT" --file "$BADIDX" --check weird >/dev/null 2>&1
is "--check of a row with a phase outside the ordered set exits 1" "$?" "1"
OUT="$("$SUT" --show --file "$BADIDX" 2>"$TMP/err")"; RC=$?
is       "--show over a malformed row exits 0" "$RC" "0"
is       "…listing the rows it accepts" "$OUT" "fine	p	merge"
has      "…and naming the row it leaves out" "$(cat "$TMP/err")" "check 'weird' declares phase 'Merge'"

# No readable index: every token is undeclared, so every non-lane token takes
# pre-open and gates every transition, rather than open an ungated PR.
OUT="$("$SUT" --resolve --check-set "correctness,demo,approval,none" --through pre-open --file "$TMP/nope.toml" 2>/dev/null)"; RC=$?
is       "no-index fallback: exit 0" "$RC" "0"
is       "no-index fallback: both real tokens survive" "$(count "$OUT")" "2"
excludes "no-index fallback still drops approval" "$OUT" "approval"
OUT="$("$SUT" --resolve --check-set "correctness,demo" --through pre-open --with-phase --file "$TMP/nope.toml" 2>/dev/null)"
has "no-index --with-phase tags demo pre-open, the phase it gates at" "$OUT" "demo	pre-open"
excludes "no-index --with-phase never tags a token merge" "$OUT" "	merge"

# ---- the layered index ----------------------------------------------------------
# A fixture pack: the script under <pack>/assets/scripts, its index at <pack>.
PACK="$TMP/pack"; mkdir -p "$PACK/assets/scripts"
cp "$SUT" "$PACK/assets/scripts/review-checks.sh"; chmod +x "$PACK/assets/scripts/review-checks.sh"
PSUT="$PACK/assets/scripts/review-checks.sh"
cat >"$PACK/review-checks.toml" <<'TOML'
[checks.correctness]
purpose = "PACK correctness"
phase = "pre-open"

[checks.triage]
purpose = "PACK triage"
phase = "pre-open"

[checks.demo]
purpose = "PACK demo"
phase = "open-as-draft"
TOML

# Fixture commits are unsigned: an operator's global commit.gpgsign would
# otherwise need a signing agent this hermetic run does not have.
commit_q() { git -C "$1" -c user.email=t@t.test -c user.name=t -c commit.gpgsign=false commit -q "${@:2}" >/dev/null 2>&1; }
RIG="$TMP/rig"; mkdir -p "$RIG/docs"
git -C "$RIG" init -q
echo readme > "$RIG/README"
git -C "$RIG" add README && commit_q "$RIG" -m "no index"
NOIDX="$(git -C "$RIG" rev-parse --verify -q HEAD)"
# The rig's index: demo moves to pre-open and keeps the pack's purpose, ux is the
# rig's own check, and the method key an older index carries is ignored.
cat >"$RIG/review-checks.toml" <<'TOML'
[checks.Demo]
method = "skills/review-demo/SKILL.md"
phase = "pre-open"

[checks.ux]
purpose = "RIG ux"
phase = "pre-open"
TOML
printf 'ARCH-GUIDANCE-MARK\n' > "$RIG/docs/review-arch.md"
git -C "$RIG" add review-checks.toml docs/review-arch.md && commit_q "$RIG" -m "rig index"
WITHIDX="$(git -C "$RIG" rev-parse --verify -q HEAD)"
# The working tree carries an index no commit does, which no read may answer from.
printf '[checks.wt]\npurpose = "WORKTREE wt"\nphase = "pre-open"\n[checks.demo]\nphase = "merge"\n' > "$RIG/review-checks.toml"

if [ -n "$NOIDX" ] && [ -n "$WITHIDX" ]; then
  # A commit with no index resolves to the pack's rows, and the working tree's
  # index adds nothing.
  OUT="$(cd "$RIG" && "$PSUT" --show --at "$NOIDX" 2>/dev/null)"; RC=$?
  is "a commit with no index: exit 0" "$RC" "0"
  is "…its effective index is the pack's rows" "$OUT" "$(printf 'correctness\tPACK correctness\tpre-open\ntriage\tPACK triage\tpre-open\ndemo\tPACK demo\topen-as-draft')"
  OUT="$(cd "$RIG" && "$PSUT" --resolve --check-set "correctness,demo,wt" --through pre-open --with-phase --at "$NOIDX" 2>/dev/null)"
  excludes "…demo keeps the pack's open-as-draft, not the working tree's merge" "$OUT" "demo"
  has      "…and the working tree's own check is undeclared there, so pre-open" "$OUT" "wt	pre-open"

  # A rig row changes a pack check's phase and keeps its purpose; a rig row adds
  # a check; the pack's row keeps its name.
  OUT="$(cd "$RIG" && "$PSUT" --show --at "$WITHIDX" 2>/dev/null)"
  has      "a rig row changes a pack check's phase and keeps its purpose" "$OUT" "demo	PACK demo	pre-open"
  has      "a rig row adds a check of the rig's own" "$OUT" "ux	RIG ux	pre-open"
  is       "…after the pack's checks, in order" "$(printf '%s\n' "$OUT" | cut -f1 | tr '\n' ' ')" "correctness triage demo ux "
  excludes "the working tree's index answers for no commit" "$OUT" "WORKTREE"
  OUT="$(cd "$RIG" && "$PSUT" --resolve --check-set "correctness,demo,ux" --through pre-open --at "$WITHIDX" 2>/dev/null)"
  is "the resolve at that commit gates the moved demo and the rig's ux at pre-open" "$(printf '%s\n' "$OUT" | tr '\n' ' ')" "correctness demo ux "
  is "--check reads one effective row" "$(cd "$RIG" && "$PSUT" --check demo --at "$WITHIDX" 2>/dev/null)" "demo	PACK demo	pre-open"
  # GC_RIG_ROOT names the rig's repository for a caller standing outside it.
  OUT="$(cd "$TMP" && GC_RIG_ROOT="$RIG" "$PSUT" --check ux --at "$WITHIDX" 2>/dev/null)"
  is "a caller outside the rig reads its rows through GC_RIG_ROOT" "$OUT" "ux	RIG ux	pre-open"

  # A call that names no commit is refused, even beside a working-tree index.
  (cd "$RIG" && "$PSUT" --show >/dev/null 2>&1); is "no --at, beside a working-tree index: exit 2" "$?" "2"
  (cd "$RIG" && "$PSUT" --resolve --check-set correctness --through merge --at "" >/dev/null 2>&1)
  is "--at \"\", beside a working-tree index: exit 2" "$?" "2"
  OUT="$(cd "$RIG" && "$PSUT" --resolve --check-set correctness --through merge --at "" 2>/dev/null)"
  is "…emitting no gates" "$(count "$OUT")" "0"

  # An index named outright resolves without a commit and stands in for both
  # layers: the pack's rows are not added to it.
  OUT="$(cd "$RIG" && "$PSUT" --show --file "$IDX" 2>/dev/null)"; RC=$?
  is       "--file resolves without --at" "$RC" "0"
  excludes "…and the pack's rows are not laid under it" "$OUT" "PACK"
  OUT="$(cd "$RIG" && GC_REVIEW_CHECKS_INDEX="$IDX" "$PSUT" --resolve --check-set "correctness,demo" --through pre-open 2>/dev/null)"; RC=$?
  is       "GC_REVIEW_CHECKS_INDEX resolves without --at" "$RC" "0"
  is       "…against the index it names" "$OUT" "correctness"
  OUT="$(GC_REVIEW_CHECKS_INDEX="$IDX" "$PSUT" --resolve --check-set "correctness,demo" --through pre-open --at deadbeef 2>/dev/null)"
  is       "GC_REVIEW_CHECKS_INDEX wins over --at" "$OUT" "correctness"
  OUT="$(GC_REVIEW_CHECKS_INDEX="$TMP/absent.toml" "$PSUT" --resolve --check-set "correctness,demo" --through pre-open 2>/dev/null)"
  is "GC_REVIEW_CHECKS_INDEX naming a missing file forces the no-index fallback (both survive)" "$(count "$OUT")" "2"

  # The extension: a commit's docs/review-<check>.md, the check folded to
  # lowercase; nothing at a commit that carries none; always at a commit.
  OUT="$(cd "$RIG" && "$PSUT" --extension ARCH --at "$WITHIDX" 2>/dev/null)"; RC=$?
  is "--extension prints the commit's docs/review-<check>.md" "$OUT" "ARCH-GUIDANCE-MARK"
  is "…exit 0" "$RC" "0"
  OUT="$(cd "$RIG" && "$PSUT" --extension arch --at "$NOIDX" 2>/dev/null)"; RC=$?
  is "--extension at a commit that carries none prints nothing" "$OUT" ""
  is "…and exits 0" "$RC" "0"
  (cd "$RIG" && "$PSUT" --extension arch >/dev/null 2>&1); is "--extension with no commit exits 2" "$?" "2"
  (cd "$RIG" && "$PSUT" --extension arch --file "$IDX" >/dev/null 2>&1); is "…even beside --file" "$?" "2"
  (cd "$RIG" && GC_REVIEW_CHECKS_INDEX="$IDX" "$PSUT" --extension arch >/dev/null 2>&1); is "…even beside GC_REVIEW_CHECKS_INDEX" "$?" "2"
  (cd "$RIG" && "$PSUT" --extension ../README --at "$WITHIDX" >/dev/null 2>&1); is "--extension takes a check name, not a path" "$?" "2"

  # A rig row with a phase outside the ordered set is refused at the commits that
  # carry it, and only there.
  printf '[checks.triage]\nphase = "Pre-Open"\n' > "$RIG/review-checks.toml"
  git -C "$RIG" add review-checks.toml && commit_q "$RIG" -m "bad rig phase"
  BADRIG="$(git -C "$RIG" rev-parse --verify -q HEAD)"
  ERR="$(cd "$RIG" && "$PSUT" --resolve --check-set "correctness,triage" --through merge --at "$BADRIG" 2>&1 >/dev/null)"; RC=$?
  is  "a rig row with a phase outside the ordered set fails the resolve (exit 1)" "$RC" "1"
  has "…naming it" "$ERR" "check 'triage' declares phase 'Pre-Open'"
  OUT="$(cd "$RIG" && "$PSUT" --resolve --check-set "correctness,triage" --through merge --at "$WITHIDX" 2>/dev/null)"; RC=$?
  is  "…while a commit without that row still resolves" "$RC" "0"
  OUT="$(cd "$RIG" && "$PSUT" --show --at "$BADRIG" 2>/dev/null)"
  excludes "--show leaves the refused row off the menu" "$OUT" "triage"
else
  bad "layered-index fixture setup" "could not build the rig repository"
fi

# No repository here at all: there is no rig layer to read, and the call says so.
NOREPO="$TMP/norepo"; mkdir -p "$NOREPO"
OUT="$(cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$TMP" "$PSUT" --show --at 0123456789abcdef0123456789abcdef01234567 2>"$TMP/err")"; RC=$?
is  "no repository here: exit 0" "$RC" "0"
is  "…the pack's rows stand alone" "$(count "$OUT")" "3"
has "…and stderr says no rig rows were read" "$(cat "$TMP/err")" "no rig rows are read"

# ---- --at fetches a commit the checkout has not fetched ----------------------------
# Two local repos stand in for origin and the refinery's checkout; GC_RIG_ROOT is
# unset so the only repository consulted is the clone.
ORIGIN="$TMP/origin"; CLONE="$TMP/clone"
mkdir -p "$ORIGIN" && git -C "$ORIGIN" init -q && printf '[checks.ux]\npurpose = "one"\nphase = "open-as-draft"\n' > "$ORIGIN/review-checks.toml" \
  && git -C "$ORIGIN" add review-checks.toml && commit_q "$ORIGIN" -m one \
  && git clone -q "$ORIGIN" "$CLONE" 2>/dev/null
# The head moves on origin after the clone, and its index moves ux to pre-open.
printf '[checks.ux]\npurpose = "two"\nphase = "pre-open"\n' > "$ORIGIN/review-checks.toml"
commit_q "$ORIGIN" -am two
NEW="$(git -C "$ORIGIN" rev-parse --verify -q HEAD 2>/dev/null)"
if [ -n "$NEW" ] && [ -d "$CLONE/.git" ] && ! git -C "$CLONE" cat-file -e "$NEW^{commit}" 2>/dev/null; then
  OUT="$(cd "$CLONE" && "$PSUT" --resolve --check-set "correctness,ux" --through pre-open --at "$NEW" 2>/dev/null)"; RC=$?
  is  "--at an unfetched head: exit 0" "$RC" "0"
  has "--at an unfetched head reads that head's index (ux is pre-open there)" "$OUT" "ux"
  git -C "$CLONE" cat-file -e "$NEW^{commit}" 2>/dev/null; is "…having fetched the commit into the clone" "$?" "0"
  # A commit neither the clone nor origin holds fails the call: no other tree's
  # index answers for it.
  OUT="$(cd "$CLONE" && "$PSUT" --resolve --check-set "correctness" --through pre-open --at 0123456789abcdef0123456789abcdef01234567 2>/dev/null)"; RC=$?
  is "--at a commit that cannot be fetched: exit 1" "$RC" "1"
  is "…emitting no gates" "$(count "$OUT")" "0"
  (cd "$CLONE" && "$PSUT" --extension ux --at 0123456789abcdef0123456789abcdef01234567 >/dev/null 2>&1)
  is "--extension at a commit that cannot be fetched: exit 1" "$?" "1"
  # A commit that carries no index of its own adds no rows: the pack's stand,
  # whatever the working tree holds.
  git -C "$CLONE" rm -q review-checks.toml && commit_q "$CLONE" -m noindex
  CNOIDX="$(git -C "$CLONE" rev-parse --verify -q HEAD)"
  printf '[checks.ux]\npurpose = "wt"\nphase = "pre-open"\n' > "$CLONE/review-checks.toml"
  OUT="$(cd "$CLONE" && "$PSUT" --resolve --check-set "correctness,demo" --through pre-open --at "$CNOIDX" 2>/dev/null)"; RC=$?
  is       "--at a commit with no index: exit 0" "$RC" "0"
  excludes "…the pack's rows stand (demo stays open-as-draft)" "$OUT" "demo"
  is       "…and the working tree's index adds no row" "$(cd "$CLONE" && "$PSUT" --check ux --at "$CNOIDX" >/dev/null 2>&1; echo $?)" "1"
else
  bad "--at fetch fixture setup" "could not build the origin/clone pair"
fi

echo
echo "review-checks: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
