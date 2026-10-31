#!/usr/bin/env bash
# Hermetic test for warrants-touched.sh, the list of the docs/warrants.md entries
# a branch touches.
#
# The defects it guards against: a covered path, key or named block that a branch
# changes goes unlisted, so the author learns of it from the arch review; a
# listing with no Verified date; a list that names what the branch did not touch,
# so the author stops reading it; and a page or base it cannot read that passes
# as nothing touched.
#
# A throwaway git repository holds a fixture page, and each case is a branch of
# it measured against a local origin/main. The last section reads the real page,
# because a covered file renamed or a Covers line in a form the list cannot read
# would otherwise pass silently.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/warrants-touched.sh"
REAL_ROOT="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-warrants-touched-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -qxF -- "$1" "$TMP/out" && ok "$2" || bad "$2 (no line '$1' in: $(cat "$TMP/out" "$TMP/err"))"; }
hasnt() { if grep -qF -- "$1" "$TMP/out"; then bad "$2 ('$1' in: $(cat "$TMP/out"))"; else ok "$2"; fi; }

[ -x "$SUT" ] && ok "warrants-touched.sh is executable" || bad "warrants-touched.sh is not executable"
bash -n "$SUT" && ok "warrants-touched.sh is syntactically valid bash" || bad "warrants-touched.sh failed bash -n"

# --- The fixture repository. --------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO/docs" "$REPO/scripts" "$REPO/overlays/guard" "$REPO/overlays/guardian" \
  "$REPO/services/pkg" "$REPO/services/pkg2" "$REPO/formulas" "$REPO/format" "$REPO/specs/x"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
git -C "$REPO" config commit.gpgsign false

cat > "$REPO/docs/warrants.md" <<'PAGE'
---
name: Warrants
---

# Warrants

## An entry

- **Covers.** The paths and keys. `format/example.sh` is this section's text.
- **Verified.** The date of the last verification.

## Keeping it true

- A change that touches a covered path re-verifies the entry.

## Path warrant

- **Covers.** `scripts/alpha.sh`, `overlays/guard/`, `services/pkg`,
  [alpha.md](alpha.md#a-section), `rootfile.toml` and
  [upstream](https://example.invalid/page.md).
- **Stands in for.** A primitive.
- **Evidence.**
  - A nested bullet names `scripts/decoy.sh`, and no Covers line does.
- **Verified.** 2026-01-02, at `gastownhall/gascity` main abc1234, and
  `gastownhall/beads` main def5678.
- **Retires when.** The trigger fires.

## Key warrant

- **Covers.** The `alpha_key`, `beta.key` and `gamma-key` keys, and a
  `state-file` file in a private dir. It does not cover the `plain_word` here.
- **Verified.** 2026-01-03, at `gastownhall/gascity` main abc1234.

## Part warrant

- **Covers.** The `gate-block` block of `formulas/flow.toml`. The `[axis]` in
  `lifecycle.toml`, with its `machines` list, and the keys' entry in its
  `[meta.keys]` table, and the `[meta.other]` table of `lifecycle.toml`.
- **Verified.** 2026-01-04, at `gastownhall/gascity` main abc1234.

## Stale part warrant

- **Covers.** The `ghost-block` block of `scripts/ghost.sh`.
- **Verified.** 2026-01-05, at `gastownhall/gascity` main abc1234.

## Verb warrant

- **Covers.** The `gamma` verb of `scripts/tool.sh`.
- **Verified.** 2026-01-06, at `gastownhall/gascity` main abc1234.
PAGE

printf 'alpha\n' > "$REPO/scripts/alpha.sh"
printf 'decoy\n' > "$REPO/scripts/decoy.sh"
printf 'ghost\n' > "$REPO/scripts/ghost.sh"
printf 'tool\n' > "$REPO/scripts/tool.sh"
printf 'other\n' > "$REPO/scripts/other.sh"
printf 'guard\n' > "$REPO/overlays/guard/settings.json"
printf 'guardian\n' > "$REPO/overlays/guardian/settings.json"
printf 'pkg\n' > "$REPO/services/pkg/a.go"
printf 'pkg2\n' > "$REPO/services/pkg2/a.go"
printf 'page\n' > "$REPO/docs/alpha.md"
printf 'page\n' > "$REPO/docs/alpha.md.txt"
printf 'root\n' > "$REPO/rootfile.toml"
printf 'example\n' > "$REPO/format/example.sh"
printf 'note\n' > "$REPO/specs/x/note.txt"
printf 'notes\n' > "$REPO/notes.txt"
cat > "$REPO/formulas/flow.toml" <<'TOML'
description = """
before
# >>> gate-block
inside
# <<< gate-block
after
"""
TOML
cat > "$REPO/lifecycle.toml" <<'TOML'
top = 1

[axis]
machines = ["a"]

[axis.detail]
deep = 1

[axis_other]
near = 1

[meta.keys]
keys = ["k"]

[meta.keysmith]
near = 2

[meta.other]
keys = ["o"]

[elsewhere]
far = 1
TOML
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
git -C "$REPO" update-ref refs/remotes/origin/main main

CASE=0
branch() { CASE=$((CASE + 1)); git -C "$REPO" checkout -q -b "case-$CASE" main; }
done_case() { git -C "$REPO" reset -q --hard; git -C "$REPO" clean -qfd; git -C "$REPO" checkout -q main; }
commit() { git -C "$REPO" add -A; git -C "$REPO" commit -qm "$1"; }
run() { rc=0; ( cd "$REPO" && bash "$SUT" "$@" ) >"$TMP/out" 2>"$TMP/err" || rc=$?; }

NONE='warrants-touched: since origin/main, this branch touches no warrant in docs/warrants.md'

# --- The three the bead names: a path, a key, and neither. -----------------------
echo "── a covered path ──"
branch
printf 'edit\n' >> "$REPO/scripts/alpha.sh"; commit path
run
eq "$rc" 1 "a branch that changes a covered path exits 1"
has '- Path warrant: Verified 2026-01-02, not updated on this branch' "it lists the warrant with its Verified date"
has '    changes scripts/alpha.sh' "it names the path"
hasnt 'Key warrant' "it lists no warrant the branch does not touch"
hasnt 'Part warrant' "it lists no part warrant the branch does not touch"
done_case

echo "── a covered key ──"
branch
printf 'set alpha_key=1\n' >> "$REPO/scripts/other.sh"; commit key
run
eq "$rc" 1 "a branch that adds a line naming a covered key exits 1"
has '- Key warrant: Verified 2026-01-03, not updated on this branch' "it lists the warrant with its Verified date"
has '    a changed line names alpha_key, in scripts/other.sh' "it names the key and the file"
hasnt 'Path warrant' "it lists no warrant the branch does not touch"
done_case

echo "── neither ──"
branch
printf 'edit\n' >> "$REPO/scripts/other.sh"; commit neither
run
eq "$rc" 0 "a branch that touches nothing covered exits 0"
eq "$(cat "$TMP/out")" "$NONE" "it says so, and lists nothing"
done_case

echo "── no change at all ──"
branch
run
eq "$rc" 0 "a branch with no change exits 0"
eq "$(cat "$TMP/out")" "$NONE" "it says so"
done_case

# --- Every shape of path a Covers line names. --------------------------------
echo "── paths ──"
branch
printf 'edit\n' >> "$REPO/overlays/guard/settings.json"; commit dir
run
has '    changes overlays/guard' "a file under a covered directory touches it"
done_case

branch
printf 'edit\n' >> "$REPO/overlays/guardian/settings.json"; commit sibling
run
eq "$rc" 0 "a directory whose name only starts the same does not"
done_case

branch
printf 'edit\n' >> "$REPO/services/pkg/a.go"; commit package
run
has '    changes services/pkg' "a package named with no trailing slash covers what is under it"
done_case

branch
printf 'edit\n' >> "$REPO/services/pkg2/a.go"; commit package2
run
eq "$rc" 0 "a package whose name only starts the same does not"
done_case

branch
printf 'edit\n' >> "$REPO/docs/alpha.md"; commit link
run
has '    changes docs/alpha.md' "a link is read against docs/, with its anchor dropped"
done_case

branch
printf 'edit\n' >> "$REPO/docs/alpha.md.txt"; commit link2
run
eq "$rc" 0 "a file whose name only starts the same as a link does not"
done_case

branch
printf 'edit\n' >> "$REPO/rootfile.toml"; commit root
run
has '    changes rootfile.toml' "a backticked file at the top of the repository is a path"
done_case

branch
git -C "$REPO" mv scripts/alpha.sh scripts/moved.sh; commit rename
run
has '    changes scripts/alpha.sh' "a rename counts under the covered path it left"
done_case

branch
git -C "$REPO" rm -q scripts/alpha.sh; commit delete
run
has '    changes scripts/alpha.sh' "deleting a covered path touches it"
done_case

branch
printf 'edit\n' >> "$REPO/format/example.sh"; printf 'edit\n' >> "$REPO/scripts/decoy.sh"; commit decoys
run
eq "$rc" 0 "the format section and an Evidence bullet name nothing it counts"
done_case

# --- Keys and names, whole. -------------------------------------------------
echo "── names ──"
key_case() {  # $1 = line added, $2 = expected exit, $3 = description
  branch
  printf '%s\n' "$1" >> "$REPO/scripts/other.sh"; commit key
  run
  eq "$rc" "$2" "$3"
  done_case
}
key_case 'x = alpha_key_extra'  0 "a name inside a longer word with an underscore is not it"
key_case 'x = xalpha_key'       0 "nor with a letter before it"
key_case 'x = betaXkey'         0 "a dot in a name is a dot, not any character"
key_case 'x = gamma-key-more'   0 "a hyphen continues a word"
key_case 'plain_word = 1'       0 "a backticked word with no key after it is not a name"
key_case 'x = .alpha_key'       1 "a jq path naming it counts"
key_case 'x = "beta.key"'       1 "a dotted key, quoted, counts"
key_case 'beta.key.'            1 "a dot closing a sentence after it still counts"
key_case 'gamma-key'            1 "a name listed before the word key counts, whatever its punctuation"
key_case 'rm state-file'        1 "a name followed by the word file counts"

branch
printf 'set alpha_key=1\n' >> "$REPO/scripts/other.sh"; commit add
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git -C "$REPO" checkout -q -b case-remove
sed -i.bak '/alpha_key/d' "$REPO/scripts/other.sh"; rm -f "$REPO/scripts/other.sh.bak"; commit remove
run
has '    a changed line names alpha_key, in scripts/other.sh' "a line that removes a key touches it"
done_case
git -C "$REPO" update-ref refs/remotes/origin/main main

branch
for f in docs/guide.md AGENTS.md scripts/other.test.sh services/pkg2/a_test.go specs/x/note.txt; do
  printf 'alpha_key\n' >> "$REPO/$f"
done
commit excluded
run
eq "$rc" 0 "a key named in markdown, a test or specs/ is not edited there"
done_case

branch
sed -i.bak 's/^## Keeping it true$/## Keeping it true (alpha_key)/' "$REPO/docs/warrants.md"; rm -f "$REPO/docs/warrants.md.bak"; commit page
run
eq "$rc" 0 "the page itself naming a key does not touch it"
done_case

branch
# git prints this added line as `+++ alpha_key`, the shape of a file header.
printf '%s\n' '++ alpha_key' >> "$REPO/scripts/other.sh"; commit plusses
run
has '    a changed line names alpha_key, in scripts/other.sh' "an added line that reads like a file header still counts"
done_case

branch
printf '%s\n' '-- alpha_key' >> "$REPO/scripts/other.sh"; commit dashes
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git -C "$REPO" checkout -q -b case-dashes-removed
sed -i.bak '/alpha_key/d' "$REPO/scripts/other.sh"; rm -f "$REPO/scripts/other.sh.bak"; commit dashes-removed
run
has '    a changed line names alpha_key, in scripts/other.sh' "a removed line that reads like a file header still counts"
done_case
git -C "$REPO" update-ref refs/remotes/origin/main main

branch
printf 'alpha_key\n' > "$REPO/scripts/one.sh"
printf 'alpha_key\n' > "$REPO/scripts/two.sh"
printf 'alpha_key\n' > "$REPO/scripts/three.sh"
printf 'alpha_key\n' > "$REPO/scripts/four.sh"
commit many
run
has '    a changed line names alpha_key, in scripts/four.sh, scripts/one.sh, scripts/three.sh and 1 more' "it names three files and counts the rest"
done_case

# --- Named blocks and tables. -----------------------------------------------
echo "── blocks and tables ──"
branch
sed -i.bak 's/^inside$/edited/' "$REPO/formulas/flow.toml"; rm -f "$REPO/formulas/flow.toml.bak"; commit block
run
has '    changes the block gate-block of formulas/flow.toml' "a change inside a named block touches it"
has '- Part warrant: Verified 2026-01-04, not updated on this branch' "it lists the warrant"
done_case

branch
sed -i.bak 's/^before$/edited/' "$REPO/formulas/flow.toml"; rm -f "$REPO/formulas/flow.toml.bak"; commit outside
run
eq "$rc" 0 "a change above the block does not touch it"
done_case

branch
sed -i.bak 's/^after$/edited/' "$REPO/formulas/flow.toml"; rm -f "$REPO/formulas/flow.toml.bak"; commit outside-after
run
eq "$rc" 0 "nor does a change below it"
done_case

branch
sed -i.bak 's/^inside$/edited/' "$REPO/formulas/flow.toml"; rm -f "$REPO/formulas/flow.toml.bak"
run
has '    changes the block gate-block of formulas/flow.toml' "an uncommitted edit inside a block counts"
done_case

branch
sed -i.bak '/^# >>> gate-block$/,/^# <<< gate-block$/d' "$REPO/formulas/flow.toml"; rm -f "$REPO/formulas/flow.toml.bak"; commit gone
run
has '    changes the block gate-block of formulas/flow.toml' "removing the block touches it"
done_case

table_case() {  # $1 = sed program, $2 = expected line or empty, $3 = description
  branch
  sed -i.bak "$1" "$REPO/lifecycle.toml"; rm -f "$REPO/lifecycle.toml.bak"; commit table
  run
  if [ -n "$2" ]; then has "$2" "$3"; else eq "$rc" 0 "$3"; fi
  done_case
}
table_case 's/^machines = .*/machines = ["b"]/' '    changes the table [axis] of lifecycle.toml' "a change inside a table named with in touches it"
table_case 's/^deep = 1/deep = 2/' '    changes the table [axis] of lifecycle.toml' "a table under it counts as part of it"
table_case 's/^near = 1/near = 3/' '' "a table whose name only starts the same does not"
table_case 's/^keys = \["k"\]/keys = ["j"]/' '    changes the table [meta.keys] of lifecycle.toml' "a table named with its finds the file named before it"
table_case 's/^near = 2/near = 3/' '' "nor does a sibling table sharing its prefix"
table_case 's/^keys = \["o"\]/keys = ["p"]/' '    changes the table [meta.other] of lifecycle.toml' "a table named with table of touches it"
table_case 's/^far = 1/far = 2/' '' "a change in a table Covers does not name does not"
table_case 's/^top = 1/top = 2/' '' "nor does a change above every table"

branch
printf 'edit\n' >> "$REPO/scripts/ghost.sh"; commit ghost
run
has '    changes scripts/ghost.sh, whose block ghost-block Covers names and neither side carries' "a block its file does not carry counts the whole file"
done_case

# --- A file named for a part of it. ------------------------------------------
echo "── a part it cannot find ──"
branch
printf 'edit\n' >> "$REPO/scripts/tool.sh"; commit verb
run
eq "$rc" 1 "a file named for one verb is listed on any change to it"
has '    changes scripts/tool.sh' "it names the file"
has '    Covers: The `gamma` verb of `scripts/tool.sh`.' "it prints the Covers line, so the author can read which part"
done_case

# --- Verified, against the base. ----------------------------------------------
echo "── Verified ──"
branch
printf 'edit\n' >> "$REPO/scripts/alpha.sh"
sed -i.bak 's/^- \*\*Verified\.\*\* 2026-01-02, at/- **Verified.** 2026-02-02, at/' "$REPO/docs/warrants.md"; rm -f "$REPO/docs/warrants.md.bak"
commit reverified
run
has '- Path warrant: Verified 2026-02-02, updated on this branch' "a branch that re-dates it shows the new date as updated"
done_case

branch
printf 'edit\n' >> "$REPO/scripts/alpha.sh"
sed -i.bak 's/^  `gastownhall\/beads` main def5678\.$/  `gastownhall\/beads` main fedcba9./' "$REPO/docs/warrants.md"; rm -f "$REPO/docs/warrants.md.bak"
commit continuation
run
has '- Path warrant: Verified 2026-01-02, updated on this branch' "a revision read on a Verified continuation line counts too"
done_case

branch
printf 'new\n' > "$REPO/scripts/new.sh"
cat >> "$REPO/docs/warrants.md" <<'PAGE'

## New warrant

- **Covers.** `scripts/new.sh`.
- **Verified.** 2026-03-03, at `gastownhall/gascity` main abc1234.
PAGE
commit added
run
has '- New warrant: Verified 2026-03-03, added on this branch' "an entry the branch adds reads as added"
done_case

branch
printf 'new\n' > "$REPO/scripts/undated.sh"
cat >> "$REPO/docs/warrants.md" <<'PAGE'

## Undated warrant

- **Covers.** `scripts/undated.sh`.
PAGE
commit undated
run
has '- Undated warrant: Verified none, added on this branch' "an entry with no Verified says so rather than dropping out"
done_case

branch
printf 'new\n' > "$REPO/scripts/undated.sh"
cat >> "$REPO/docs/warrants.md" <<'PAGE'

## Dateless warrant

- **Covers.** `scripts/undated.sh`.
- **Verified.** Not yet read.
PAGE
commit dateless
run
has '- Dateless warrant: Verified none, added on this branch' "a Verified with no date reads as none"
done_case

# --- What the change is. ------------------------------------------------------
echo "── the change ──"
branch
printf 'edit\n' >> "$REPO/scripts/alpha.sh"
run
has '    changes scripts/alpha.sh' "an uncommitted edit counts"
done_case

branch
printf 'set alpha_key=1\n' >> "$REPO/scripts/other.sh"
run
has '    a changed line names alpha_key, in scripts/other.sh' "an uncommitted key counts"
done_case

branch
printf 'alpha_key\n' > "$REPO/scripts/untracked.sh"
run
eq "$rc" 0 "an untracked file does not, as git diff does not show it"
done_case

git -C "$REPO" checkout -q -b case-moved main
printf 'edit\n' >> "$REPO/notes.txt"; commit branch-work
git -C "$REPO" checkout -q main
printf 'edit\n' >> "$REPO/scripts/alpha.sh"; commit base-moved
git -C "$REPO" update-ref refs/remotes/origin/main main
git -C "$REPO" checkout -q case-moved
run
eq "$rc" 0 "a covered change on the base since the branch left it is not the branch's"
git -C "$REPO" checkout -q main
git -C "$REPO" reset -q --hard HEAD~1
git -C "$REPO" update-ref refs/remotes/origin/main main

git -C "$REPO" update-ref refs/remotes/origin/effort main
branch
printf 'edit\n' >> "$REPO/scripts/alpha.sh"; commit effort-member
git -C "$REPO" update-ref refs/remotes/origin/effort HEAD
printf 'edit\n' >> "$REPO/notes.txt"; commit member-work
run --base origin/effort
eq "$rc" 0 "--base measures from the revision it names"
eq "$(cat "$TMP/out")" 'warrants-touched: since origin/effort, this branch touches no warrant in docs/warrants.md' "and says which"
run --base=origin/main
has '    changes scripts/alpha.sh' "--base=REV reads the same, and origin/main is the default it replaces"
done_case

( cd "$REPO/docs" && bash "$SUT" ) >"$TMP/out" 2>"$TMP/err"; rc=$?
eq "$rc" 0 "it reads the page from the top of the repository, wherever it runs"

# --- Could not operate: exit 2, never a clean list. ---------------------------
echo "── could not operate ──"
run --base origin/no-such
eq "$rc" 2 "a base git cannot read exits 2"
grep -q "cannot read base revision 'origin/no-such'" "$TMP/err" && ok "it names the base" || bad "it does not name the base: $(cat "$TMP/err")"

run --base
eq "$rc" 2 "--base with no revision exits 2"
run --no-such-flag
eq "$rc" 2 "an unknown argument exits 2"

branch
git -C "$REPO" rm -q docs/warrants.md; commit no-page
run
eq "$rc" 2 "a missing page exits 2"
grep -q 'cannot read docs/warrants.md' "$TMP/err" && ok "it names the page" || bad "it does not name the page: $(cat "$TMP/err")"
done_case

branch
printf '# Warrants\n\nNo entries here.\n' > "$REPO/docs/warrants.md"; commit empty-page
run
eq "$rc" 2 "a page with no entry exits 2"
grep -q 'holds no entry' "$TMP/err" && ok "it says so" || bad "it does not say so: $(cat "$TMP/err")"
done_case

rc=0; ( cd "$TMP" && bash "$SUT" ) >"$TMP/out" 2>"$TMP/err" || rc=$?
eq "$rc" 2 "outside a repository exits 2"

git -C "$REPO" checkout -q --orphan case-unrelated
git -C "$REPO" commit -qm unrelated
run
eq "$rc" 2 "a HEAD sharing no history with the base exits 2"
done_case

# --- What each entry's Covers line names. -------------------------------------
echo "── --covers ──"
run --covers
eq "$rc" 0 "--covers exits 0"
eq "$(cat "$TMP/out")" "$(printf '%s\n' \
  $'Path warrant\tpath\tscripts/alpha.sh\t-' \
  $'Path warrant\tpath\toverlays/guard\t-' \
  $'Path warrant\tpath\tservices/pkg\t-' \
  $'Path warrant\tpath\tdocs/alpha.md\t-' \
  $'Path warrant\tpath\trootfile.toml\t-' \
  $'Key warrant\tname\talpha_key\t-' \
  $'Key warrant\tname\tbeta.key\t-' \
  $'Key warrant\tname\tgamma-key\t-' \
  $'Key warrant\tname\tstate-file\t-' \
  $'Part warrant\tblock\tgate-block\tformulas/flow.toml' \
  $'Part warrant\ttable\t[axis]\tlifecycle.toml' \
  $'Part warrant\ttable\t[meta.keys]\tlifecycle.toml' \
  $'Part warrant\ttable\t[meta.other]\tlifecycle.toml' \
  $'Stale part warrant\tblock\tghost-block\tscripts/ghost.sh' \
  $'Verb warrant\tpath\tscripts/tool.sh\t-')" "each entry's terms, with a path named only as a home dropped"

branch
cat >> "$REPO/docs/warrants.md" <<'PAGE'

## Bare warrant

- **Covers.** Something in plain words.
- **Verified.** 2026-03-03.

## Shared warrant

- **Covers.** `scripts/alpha.sh`, and `scripts/alpha.sh` once more.
- **Verified.** 2026-03-04.
PAGE
commit bare
run --covers
grep -qxF "$(printf 'Bare warrant\tnone\t-\t-')" "$TMP/out" && ok "an entry naming nothing it reads is marked none" || bad "the bare entry is not marked: $(cat "$TMP/out")"
eq "$(grep -cxF "$(printf 'Shared warrant\tpath\tscripts/alpha.sh\t-')" "$TMP/out")" 1 "a path two entries share is each one's, and counts once in each"
printf 'edit\n' >> "$REPO/scripts/alpha.sh"; commit shared
run
has '- Path warrant: Verified 2026-01-02, not updated on this branch' "a path two entries share lists the first"
has '- Shared warrant: Verified 2026-03-04, added on this branch' "and the second"
done_case

# --- The real page: every entry reads, and what it names is there. ------------
# A Covers line the list cannot read leaves its warrant silently off every list,
# and a covered file renamed without its entry does the same.
echo "── the real page ──"
PAGE_REPO="$REAL_ROOT"
if rows=$(cd "$PAGE_REPO" && bash "$SUT" --covers); then ok "the real page parses"; else bad "the real page does not parse"; fi
[ -n "$rows" ] && ok "the real page holds entries" || bad "the real page holds no entry"
while IFS=$'\t' read -r entry kind term home; do
  case "$kind" in
    path)
      [ -e "$PAGE_REPO/$term" ] && ok "$entry: $term is in the tree" || bad "$entry: $term is not in the tree" ;;
    name)
      if git -C "$PAGE_REPO" grep -q -F -e "$term" -- . ':(exclude)docs/warrants.md'; then
        ok "$entry: $term is in the tree"
      else
        bad "$entry: $term is nowhere in the tree"
      fi ;;
    block)
      if grep -q -x -e "[[:space:]]*# >>> $term" "$PAGE_REPO/$home" 2>/dev/null; then
        ok "$entry: $home carries the block $term"
      else
        bad "$entry: $home carries no block $term"
      fi ;;
    table)
      if grep -q -x -F -e "$term" "$PAGE_REPO/$home" 2>/dev/null; then
        ok "$entry: $home carries the table $term"
      else
        bad "$entry: $home carries no table $term"
      fi ;;
    *)
      bad "$entry: its Covers line names nothing the list reads" ;;
  esac
done < <(printf '%s\n' "$rows")

echo
echo "warrants-touched.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
