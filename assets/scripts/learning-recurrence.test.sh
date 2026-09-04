#!/usr/bin/env bash
# Hermetic test for assets/scripts/learning-recurrence.sh — the
# feedback-learning loop's recurrence metric. Stubbed gc; no live city, Dolt,
# or network. Fixture timestamps are computed from `now` so the windows stay
# meaningful whenever the suite runs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/learning-recurrence.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { if grep -qF -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if grep -qF -- "$2" <<< "$1"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

ago() { date -u -d "-$1 days" +%Y-%m-%dT%H:%M:%SZ; }

# --- stub gc --------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  rig)
    [ -n "${STUB_RIGS_EMPTY:-}" ] && { echo '{"rigs":[]}'; exit 0; }
    cat "${STUB_RIGS:?}" ;;
  bd)
    shift
    store=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -C)      shift; store="$1" ;;
        --rig)   shift; store="$STUB_STORE_DIR/$1.json" ;;
        list)    : ;;
      esac
      shift || true
    done
    case "$store" in
      */"$STUB_BROKEN_RIG".json|"$STUB_BROKEN_RIG") echo 'bd: store unreachable' >&2; exit 1 ;;
    esac
    [ -r "$store" ] && cat "$store" || echo '[]' ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
export STUB_STORE_DIR="$TMP/stores"; mkdir -p "$STUB_STORE_DIR"
export STUB_BROKEN_RIG="__none__"

# `gc rig list --json` returns an OBJECT whose HQ entry is addressable only by
# path; the stub keeps that shape so the script's own reader is exercised.
cat > "$TMP/rigs.json" <<JSON
{"rigs":[{"name":"alpha","path":"$STUB_STORE_DIR/alpha.json"},
         {"name":"beta","path":"$STUB_STORE_DIR/beta.json"}]}
JSON
export STUB_RIGS="$TMP/rigs.json"

# Both writers (mol-feedback-miner, the file-feedback-observations fragment)
# create with `-l observation` AND stamp task_kind=observation, so the fixture
# carries both. `mislabelled` drops the metadata to stand for the beads the
# label alone sweeps in.
obs() { # id created_at provenance category pattern source
  jq -nc --arg id "$1" --arg c "$2" --arg p "$3" --arg cat "$4" --arg pat "$5" --arg s "$6" \
    '{id:$id, created_at:$c, metadata:{task_kind:"observation", "obs.provenance":$p, "obs.category":$cat, "obs.distilled":$pat, "obs.source":$s}}'
}
mislabelled() { # id created_at category — carries the label, not the kind
  jq -nc --arg id "$1" --arg c "$2" --arg cat "$3" \
    '{id:$id, created_at:$c, metadata:{"obs.provenance":("prov-" + $id), "obs.category":$cat}}'
}

# alpha: one category seen three times (two inside the window, one older),
# one singleton, one event double-captured under a single provenance key, and
# one whole-turn provenance carrying three corrections that are not the same
# correction — different category, different pattern bead.
{
  obs a1 "$(ago 80)"  "pr:o/r#1:comment:1" doc-venue ""        self
  obs a2 "$(ago 10)"  "pr:o/r#2:comment:2" doc-venue tk-pat1   miner
  obs a3 "$(ago 3)"   "pr:o/r#3:comment:3" doc-venue tk-pat1   operator
  obs a4 "$(ago 5)"   "bead:x:turn:1"      lone-slug ""        self
  obs a5 "$(ago 4)"   "pr:o/r#9:comment:9" dup-slug  ""        self
  obs a6 "$(ago 4)"   "pr:o/r#9:comment:9" dup-slug  ""        miner
  obs a7 "$(ago 6)"   "bead:y:turn:2"      turn-one  tk-pat1   self
  obs a8 "$(ago 6)"   "bead:y:turn:2"      turn-two  tk-pat2   self
  obs a9 "$(ago 6)"   "bead:y:turn:2"      turn-one  ""        miner
} | jq -s . > "$STUB_STORE_DIR/alpha.json"

# beta: one event inside the prior window that repeats alpha's oldest category.
{
  obs b1 "$(ago 45)" "pr:o/r#4:comment:4" doc-venue "" miner
} | jq -s . > "$STUB_STORE_DIR/beta.json"

# --- fixture pack checkout ------------------------------------------------
REPO="$TMP/repo"; mkdir -p "$REPO/template-fragments" "$REPO/docs"
ADOPTED=$(date -u -d "-30 days" +%Y-%m-%d)
cat > "$REPO/template-fragments/learned-conventions-polecat.template.md" <<MD
{{ define "learned-conventions-polecat" }}
<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->
<!-- rule:tk-pat1 src:audit:tk-test adopted:$ADOPTED -->
- A rule whose pattern bead keeps collecting evidence after adoption.
<!-- rule:tk-quiet src:audit:tk-test adopted:$ADOPTED -->
- A rule nothing has recurred against.
{{ end }}
MD
cat > "$REPO/template-fragments/operator-profile.template.md" <<MD
{{ define "operator-profile" }}
<!-- src:pr:#465:review:r1 (operator feedback) adopted:2026-08-25 -->
- An entry with no pattern-bead anchor, so recurrence cannot be attributed.
{{ end }}
MD
# The review-rubric carrier anchors in a TOML comment ledger, not in the step
# description, so the inventory has to reach a formula file too.
mkdir -p "$REPO/formulas"
cat > "$REPO/formulas/mol-review.toml" <<MD
# <!-- rule:<pattern-bead> src:<refs> adopted:<date> --> <dimension>
# <!-- rule:tk-rub1 src:audit:tk-test adopted:$ADOPTED --> Contract
[[steps]]
id = "review"
MD

# --- 1. inventory ---------------------------------------------------------
INV=$(cd "$REPO" && "$SUT" --inventory --repo "$REPO" 2>&1)
eq "$(grep -c . <<< "$INV")" "4" "inventory lists one row per adopted entry"
hasnt "$INV" 'rule:<pattern-bead>' "inventory skips the seeded placeholder anchor"
has "$INV" "tk-pat1" "inventory extracts the pattern bead from a rule: anchor"
has "$INV" "operator-profile.template.md	-	2026-08-25" "an anchor with no rule: field reports '-' rather than guessing"
has "$INV" "formulas/mol-review.toml	tk-rub1" "the review-rubric ledger is inventoried beside the fragment carriers"

# --- 2. report over the fixture corpus ------------------------------------
J=$("$SUT" --repo "$REPO" --window-days 30 --json 2>&1)
eq "$(jq -r '.corpus.observations' <<< "$J")" "10" "every observation across both stores is read"
eq "$(jq -r '.corpus.events_after_dedup' <<< "$J")" "8" "two captures of one correction collapse to one event"
eq "$(jq -r '.corpus.stores' <<< "$J")" "2" "both stores counted"

# a2, a3 repeat doc-venue (a1 is older); a4/a5 are firsts of their slug.
eq "$(jq -r '.m1_category_repeat.window.repeats' <<< "$J")" "2" "M1 counts only events whose category was seen earlier"
eq "$(jq -r '.m1_category_repeat.window.categorised' <<< "$J")" "6" "M1 denominator is the window's categorised events"
eq "$(jq -r '.m1_category_repeat.prior.repeats' <<< "$J")" "1" "the prior window is scored the same way"
eq "$(jq -r '.m1_category_repeat.fragmentation.distinct' <<< "$J")" "5" "fragmentation counts distinct slugs"

# a2 and a3 carry obs.distilled=tk-pat1 and postdate the adoption date.
eq "$(jq -r '[.m2_post_adoption.rules[] | select(.pattern=="tk-pat1")] | .[0].since_adoption' <<< "$J")" "3" \
   "M2 attributes post-adoption events through obs.distilled"
eq "$(jq -r '[.m2_post_adoption.rules[] | select(.pattern=="tk-quiet")] | .[0].since_adoption' <<< "$J")" "0" \
   "a rule with no matching observations scores zero, not null"
eq "$(jq -r '.m2_post_adoption.adopted_total' <<< "$J")" "4" "every adopted entry is inventoried"
eq "$(jq -r '.m2_post_adoption.measurable' <<< "$J")" "3" "an entry without a pattern anchor is not counted as measurable"

# --- 2a. task_kind decides, the label only narrows ------------------------
# `-l observation` is a listing narrowing, not the discriminator: the label is
# free-text and any bead may carry it. A bead without task_kind=observation is
# not an observation, and admitting it would inflate the corpus both metrics
# are scored against.
mkdir -p "$TMP/stores2a"
{
  obs         k1 "$(ago 5)" "pr:o/r#30:comment:30" real-slug tk-pat1 self
  mislabelled k2 "$(ago 4)" impostor-slug
} | jq -s . > "$TMP/stores2a/alpha.json"
cat > "$TMP/rigs2a.json" <<JSON
{"rigs":[{"name":"alpha","path":"$TMP/stores2a/alpha.json"}]}
JSON
K=$(STUB_RIGS="$TMP/rigs2a.json" "$SUT" --repo "$REPO" --window-days 30 --json 2>&1)
eq "$(jq -r '.corpus.observations' <<< "$K")" "1" \
   "a bead carrying the label but not task_kind=observation is not an observation"
eq "$(jq -r '.m1_category_repeat.fragmentation.categorised' <<< "$K")" "1" \
   "and its obs.category never reaches the M1 accounting"

# --- 2b. one provenance key, several distinct corrections -----------------
# A whole-turn provenance (bead:<id>:turn:<date>) covers every correction made
# in that turn. Collapsing the group to one row loses real recurrence, and
# picking the earliest row loses the attribution a later capture carries.
mkdir -p "$TMP/stores4"
{
  obs t1 "$(ago 5)" "bead:z:turn:9" cat-one tk-pat1  self
  obs t2 "$(ago 5)" "bead:z:turn:9" cat-two tk-quiet self
  obs t3 "$(ago 4)" "bead:z:turn:9" cat-one ""       miner
} | jq -s . > "$TMP/stores4/alpha.json"
cat > "$TMP/rigs4.json" <<JSON
{"rigs":[{"name":"alpha","path":"$TMP/stores4/alpha.json"}]}
JSON
D=$(STUB_RIGS="$TMP/rigs4.json" "$SUT" --repo "$REPO" --window-days 30 --json 2>&1)
eq "$(jq -r '.corpus.observations' <<< "$D")" "3" "all three captures are read"
eq "$(jq -r '.corpus.events_after_dedup' <<< "$D")" "2" \
   "distinct corrections under one provenance key stay distinct events"
eq "$(jq -r '[.m2_post_adoption.rules[] | select(.pattern=="tk-pat1")] | .[0].since_adoption' <<< "$D")" "1" \
   "the survivor keeps the attribution when only one capture in the group carries it"

# --- 2c. a date-only anchor does not count its own adoption day -----------
# The distiller stamps consumed observations when it files the proposal, so
# same-day evidence predates the merge as often as it follows it.
REPO2="$TMP/repo2"; mkdir -p "$REPO2/template-fragments"
TODAY=$(date -u +%Y-%m-%d)
TWO_DAYS_AGO=$(date -u -d "-2 days" +%Y-%m-%d)
cat > "$REPO2/template-fragments/learned-conventions-polecat.template.md" <<MD
{{ define "learned-conventions-polecat" }}
<!-- rule:tk-today src:audit:tk-test adopted:$TODAY -->
- A rule adopted today, on evidence captured today.
<!-- rule:tk-older src:audit:tk-test adopted:$TWO_DAYS_AGO -->
- A rule adopted two days ago.
{{ end }}
MD
mkdir -p "$TMP/stores5"
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
  obs s1 "$NOW_TS" "pr:o/r#20:comment:20" same-day  tk-today self
  obs s2 "$NOW_TS" "pr:o/r#21:comment:21" later-day tk-older self
} | jq -s . > "$TMP/stores5/alpha.json"
cat > "$TMP/rigs5.json" <<JSON
{"rigs":[{"name":"alpha","path":"$TMP/stores5/alpha.json"}]}
JSON
A=$(STUB_RIGS="$TMP/rigs5.json" "$SUT" --repo "$REPO2" --window-days 30 --json 2>&1)
eq "$(jq -r '[.m2_post_adoption.rules[] | select(.pattern=="tk-today")] | .[0].since_adoption' <<< "$A")" "0" \
   "evidence from the adoption day itself is not post-adoption recurrence"
eq "$(jq -r '[.m2_post_adoption.rules[] | select(.pattern=="tk-older")] | .[0].since_adoption' <<< "$A")" "1" \
   "evidence after the adoption day still counts"

# --- 3. the qualifiers fire ----------------------------------------------
T=$("$SUT" --repo "$REPO" --window-days 30 2>&1)
has "$T" "unmeasurable (no pattern-bead anchor)" "entries that cannot be attributed are named"

# A corpus shaped like the live one: a fresh slug per event, nothing distilled.
# Both qualifiers must fire, or a floored M1 and an unmeasured M2 read as a
# healthy loop.
mkdir -p "$TMP/stores3"
{
  obs f1 "$(ago 12)" "q1" slug-one   "" self
  obs f2 "$(ago 11)" "q2" slug-two   "" self
  obs f3 "$(ago 10)" "q3" slug-three "" self
  obs f4 "$(ago 9)"  "q4" slug-four  "" miner
} | jq -s . > "$TMP/stores3/alpha.json"
cat > "$TMP/rigs3.json" <<JSON
{"rigs":[{"name":"alpha","path":"$TMP/stores3/alpha.json"}]}
JSON
F=$(STUB_RIGS="$TMP/rigs3.json" "$SUT" --repo "$REPO" --window-days 30 2>&1)
has "$F" "HIGH FRAGMENTATION" "the fragmentation qualifier fires when slugs are near-unique"
has "$F" "LOW COVERAGE" "the coverage qualifier fires when most window events are unattributed"

# Negative control: a corpus that is well clustered and fully attributed must
# NOT print either qualifier, or the warnings are unconditional decoration.
mkdir -p "$TMP/stores2"
{
  obs c1 "$(ago 40)" "p1" shared-slug tk-pat1 self
  obs c2 "$(ago 9)"  "p2" shared-slug tk-pat1 miner
  obs c3 "$(ago 8)"  "p3" shared-slug tk-pat1 operator
  obs c4 "$(ago 7)"  "p4" shared-slug tk-pat1 self
} | jq -s . > "$TMP/stores2/alpha.json"
cat > "$TMP/rigs2.json" <<JSON
{"rigs":[{"name":"alpha","path":"$TMP/stores2/alpha.json"}]}
JSON
C=$(STUB_RIGS="$TMP/rigs2.json" "$SUT" --repo "$REPO" --window-days 30 2>&1)
hasnt "$C" "HIGH FRAGMENTATION" "a clustered corpus does not trip the fragmentation qualifier"
hasnt "$C" "LOW COVERAGE" "a fully attributed window does not trip the coverage qualifier"

# --- 4. fail closed on a partial city ------------------------------------
OUT=$(STUB_BROKEN_RIG="beta" "$SUT" --repo "$REPO" 2>&1); RC=$?
eq "$RC" "1" "an unreadable store exits 1"
has "$OUT" "refusing to report on a partial city" "and says why"
hasnt "$OUT" "M1  repeat feedback" "no partial report is printed"

OUT=$(STUB_RIGS_EMPTY=1 "$SUT" --repo "$REPO" 2>&1); RC=$?
eq "$RC" "1" "an empty rig enumeration exits 1"
has "$OUT" "refusing to report on a partial city" "and says why"

# --- 5. --ref pins the carrier read in report mode too --------------------
# The distiller passes --ref origin/main to the report as well as to
# --inventory: read from a working tree, a proposal branch counts its own
# unmerged entries as adopted.
GREPO="$TMP/grepo"; mkdir -p "$GREPO/template-fragments"
git -C "$GREPO" init -q >/dev/null 2>&1
cat > "$GREPO/template-fragments/learned-conventions-polecat.template.md" <<MD
{{ define "learned-conventions-polecat" }}
<!-- rule:tk-merged src:audit:tk-test adopted:$ADOPTED -->
- A rule that is already on the ref.
{{ end }}
MD
git -C "$GREPO" add -A >/dev/null 2>&1
git -C "$GREPO" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false \
    commit -q --no-verify -m seed >/dev/null 2>&1
cat >> "$GREPO/template-fragments/learned-conventions-polecat.template.md" <<MD
<!-- rule:tk-unmerged src:audit:tk-test adopted:$ADOPTED -->
- A rule that exists only in the working tree.
MD
R=$("$SUT" --inventory --repo "$GREPO" --ref HEAD 2>&1)
has   "$R" "tk-merged"   "--ref reads the carrier from the ref"
hasnt "$R" "tk-unmerged" "and not from the working tree"
R=$(STUB_RIGS="$TMP/rigs2.json" "$SUT" --repo "$GREPO" --ref HEAD --window-days 30 --json 2>&1)
eq "$(jq -r '.m2_post_adoption.adopted_total' <<< "$R")" "1" \
   "report mode honors --ref, so an unmerged entry is not counted as adopted"
R=$(STUB_RIGS="$TMP/rigs2.json" "$SUT" --repo "$GREPO" --window-days 30 --json 2>&1)
eq "$(jq -r '.m2_post_adoption.adopted_total' <<< "$R")" "2" \
   "and without --ref the working tree is what it reads"

# --- 6. usage ------------------------------------------------------------
OUT=$("$SUT" --window-days 0 --repo "$REPO" 2>&1); eq "$?" "2" "--window-days 0 is rejected"
OUT=$("$SUT" --window-days x --repo "$REPO" 2>&1); eq "$?" "2" "a non-numeric window is rejected"
OUT=$("$SUT" --nope --repo "$REPO" 2>&1); eq "$?" "2" "an unknown flag is rejected"

echo
echo "learning-recurrence.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
