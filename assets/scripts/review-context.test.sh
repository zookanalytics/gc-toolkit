#!/usr/bin/env bash
# Hermetic test for review-context.sh: a review reads the page as it will be
# published, and the pack's work-quality standards and exemplars.
#
# What it holds:
#   1. POST-OPEN — the page is read through the repository pinned from the
#      review bead's pr_url, never a bare number; an unparseable pr_url reads
#      nothing and exits 1.
#   2. PRE-OPEN — the anchor's title and pending pr_summary print; an absent
#      summary says the dispatch description ships in its place, with its locus.
#   3. STANDARDS — every work-quality fragment prints, then the exemplars; a
#      pack with none says so for the coverage line.
#
# Fakes gc and gh and builds a fixture pack; no city, Dolt, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/review-context.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-context-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3" "'$2' unexpectedly in '$1'" ;; *) ok "$3" ;; esac; }

[ -x "$SUT" ] || { echo "not executable: $SUT" >&2; exit 1; }

# gc : `bd show tk-review` answers $FAKE_REVIEW, `bd show tk-anchor` $FAKE_ANCHOR.
# gh : `pr view` records its argv and prints a page.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1 $2" = "bd show" ] || exit 0
case "$3" in
  tk-review) printf '%s' "${FAKE_REVIEW:-[]}" ;;
  tk-anchor) printf '%s' "${FAKE_ANCHOR:-[]}" ;;
esac
exit 0
GC
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
[ "$1 $2" = "pr view" ] && { printf 'Title: Compare heads\n\nThe body.\n'; exit 0; }
exit 1
GH
chmod +x "$TMP/bin/gc" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_GH_LOG="$TMP/gh.log"

mkdir -p "$TMP/pack/template-fragments" "$TMP/empty-pack"
printf 'BASE STANDARDS\n'    > "$TMP/pack/template-fragments/work-quality-base.template.md"
printf 'POLECAT STANDARDS\n' > "$TMP/pack/template-fragments/work-quality-polecat.template.md"
printf 'EXEMPLARS\n'         > "$TMP/pack/template-fragments/learning-exemplars.template.md"
printf 'OPERATOR PROFILE\n'  > "$TMP/pack/template-fragments/operator-profile.template.md"

# run <pack> -> "<rc>"; output left in $TMP/out.
run() {
  : > "$FAKE_GH_LOG"
  local rc=0
  "$SUT" --review-bead tk-review --pack "$1" > "$TMP/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# --- 1. Post-open. ------------------------------------------------------------
export FAKE_REVIEW='[{"metadata":{"pr_number":"7","pr_url":"https://github.com/acme/widgets/pull/7"}}]'
eq "$(run "$TMP/pack")" "0" "post-open: exits 0"
eq "$(cat "$FAKE_GH_LOG")" "pr view 7 --repo github.com/acme/widgets --json title,body -q \"Title: \" + .title + \"\\n\\n\" + .body" \
   "post-open: the page is read through the repository pinned from pr_url"
has "$(cat "$TMP/out")" "Title: Compare heads" "post-open: prints the page's title and body"
FAKE_REVIEW='[{"metadata":{"pr_number":"7","pr_url":"not a url"}}]' run "$TMP/pack" > "$TMP/rc"
eq "$(cat "$TMP/rc")" "1" "post-open, unparseable pr_url: exits 1"
eq "$(cat "$FAKE_GH_LOG")" "" "and asks gh nothing, rather than resolve PR#7 from ambient context"
has "$(cat "$TMP/out")" "no parseable pr_url" "and says why"

# --- 2. Pre-open. -------------------------------------------------------------
export FAKE_REVIEW='[{"metadata":{"review_branch":"polecat/tk-x","anchor_bead":"tk-anchor"}}]'
FAKE_ANCHOR='[{"title":"Compare heads","metadata":{"pr_summary":"Compares heads instead of names."}}]' run "$TMP/pack" > "$TMP/rc"
eq "$(cat "$TMP/rc")" "0" "pre-open: exits 0"
has "$(cat "$TMP/out")" "Title: Compare heads" "pre-open: prints the anchor's title"
has "$(cat "$TMP/out")" "Compares heads instead of names." "pre-open: prints the pending summary"
FAKE_ANCHOR='[{"title":"Compare heads","metadata":{}}]' run "$TMP/pack" > /dev/null
has "$(cat "$TMP/out")" "pr_summary: absent — pr-open.sh will publish the dispatch description in its place (locus: anchor tk-anchor / pr_summary)" \
   "pre-open, no summary: says the dispatch description ships instead, with the locus"
FAKE_ANCHOR='[{"title":"T","metadata":{"pr_summary":"   "}}]' run "$TMP/pack" > /dev/null
has "$(cat "$TMP/out")" "pr_summary: absent" "a whitespace-only summary reads as absent"
FAKE_REVIEW='[{"metadata":{}}]' run "$TMP/pack" > "$TMP/rc"
eq "$(cat "$TMP/rc")" "1" "pre-open with no anchor_bead: exits 1"

# --- 3. Standards. ------------------------------------------------------------
export FAKE_ANCHOR='[{"title":"T","metadata":{"pr_summary":"S"}}]'
run "$TMP/pack" > /dev/null
OUT="$(cat "$TMP/out")"
has "$OUT" "BASE STANDARDS" "prints the work-quality base fragment"
has "$OUT" "POLECAT STANDARDS" "and every class fragment"
has "$OUT" "EXEMPLARS" "and the exemplars"
no  "$OUT" "OPERATOR PROFILE" "but not the operator profile, which governs an agent, not a diff"
run "$TMP/empty-pack" > /dev/null
has "$(cat "$TMP/out")" "work-quality fragments not found" "a pack with no fragments says so for the coverage line"

eq "$("$SUT" > /dev/null 2>&1; echo $?)" "2" "no --review-bead refuses as usage"

echo
echo "review-context: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
