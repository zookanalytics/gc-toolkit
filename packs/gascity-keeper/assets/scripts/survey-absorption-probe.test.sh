#!/usr/bin/env bash
# Hermetic test for survey-absorption-probe.sh, the evidence generator the
# `survey` step of mol-upstream-gc-rebase runs before issuing a verdict.
#
# The fixtures are the shapes of three real commits from the 31-commit
# divergent set the probe was built against, because the two directions this
# script must hold apart both appeared there:
#
#   absorbed        — upstream already carries the construct the commit adds,
#                     and the unmatched remainder is scaffolding. Survey called
#                     it `keep`; the rebase loop later called it
#                     `dropped-absorbed`. The probe must flag it.
#   idiom-collision — upstream carries the same lines for a DIFFERENT purpose
#                     and the commit's whole value is the one unmatched line.
#                     The probe flags this too, and the case is pinned here so
#                     that a later change cannot quietly turn `overlap: high`
#                     into a drop recommendation. Distinguishing it from the
#                     first case is reading work, not text work.
#   local-only      — nothing upstream. The probe must stay quiet.
#
#
# EXECUTES the real shipped script against real temporary git repositories.
# No live city, Dolt, network, or worktrees.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/survey-absorption-probe.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

# --- fixture repository -------------------------------------------------------
# One repo, two branches. `upstream` holds what upstream/main has; `local`
# holds the fork's divergent commits, each committed on top of a shared base so
# the probe sees exactly the added lines under test.
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b base
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name  Test

commit() { git -C "$REPO" add -A && git -C "$REPO" commit -qm "$1"; }

# Shared base: the files before either side diverged.
mkdir -p "$REPO/internal/sling" "$REPO/examples"
cat > "$REPO/internal/sling/sling_test.go" <<'EOF'
package sling

import (
	"os"
	"testing"
)

var sharedTestFormulaDir string
var sharedTestCityDir string

func TestSomething(t *testing.T) {
	t.Log("unchanged")
}
EOF
cat > "$REPO/examples/env_test.go" <<'EOF'
package examples

import (
	"os"
	"strings"
)

func mergeTestEnv(overrides map[string]string) []string {
	env := os.Environ()
	return env
}
EOF
# README.md carries blank lines on BOTH branches on purpose: it is the file
# the local-only commit appends to, so it is what proves a blank upstream line
# never becomes a grep pattern. Without blank lines here that check is vacuous.
cat > "$REPO/README.md" <<'EOF'
# Fixture

A first paragraph of seed prose that both branches share unchanged.

A second paragraph, so the file holds more than one blank line.
EOF
commit "base"
BASE=$(git -C "$REPO" rev-parse HEAD)

# --- upstream branch ----------------------------------------------------------
git -C "$REPO" checkout -q -b upstream "$BASE"

# upstream absorbed the fixture cleanup, with no defensive guards. The lone
# earlyCleanupHelper line is a deliberate decoy: it makes upstream's FIRST
# overlapping run a single line well before the TestMain block, so a span that
# reported the first run instead of the longest would point at the wrong code.
python3 - "$REPO/internal/sling/sling_test.go" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read().replace('''func TestSomething(t *testing.T) {''', '''func earlyCleanupHelper() {
	_ = os.RemoveAll(sharedTestFormulaDir)
}

func TestMain(m *testing.M) {
	code := m.Run()
	_ = os.RemoveAll(sharedTestFormulaDir)
	_ = os.RemoveAll(sharedTestCityDir)
	os.Exit(code)
}

func TestSomething(t *testing.T) {''')
open(p, "w").write(s)
EOF

# upstream uses the filtered-slice idiom to strip OVERRIDE keys — same lines,
# different purpose from what the fork's commit adds.
cat > "$REPO/examples/env_test.go" <<'EOF'
package examples

import (
	"os"
	"strings"
)

func mergeTestEnv(overrides map[string]string) []string {
	env := os.Environ()
	for key := range overrides {
		prefix := key + "="
		filtered := env[:0]
		for _, entry := range env {
			if !strings.HasPrefix(entry, prefix) {
				filtered = append(filtered, entry)
			}
		}
		env = filtered
	}
	return env
}
EOF
commit "upstream state"

# --- local branch -------------------------------------------------------------
git -C "$REPO" checkout -q -b local "$BASE"

# Case 1 (absorbed): the same cleanup upstream already has, plus two guards.
python3 - "$REPO/internal/sling/sling_test.go" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read().replace('''func TestSomething(t *testing.T) {''', '''func TestMain(m *testing.M) {
	code := m.Run()
	if sharedTestFormulaDir != "" {
		_ = os.RemoveAll(sharedTestFormulaDir)
	}
	if sharedTestCityDir != "" {
		_ = os.RemoveAll(sharedTestCityDir)
	}
	os.Exit(code)
}

func TestSomething(t *testing.T) {''')
open(p, "w").write(s)
EOF
commit "test(sling): cleanup shared fixture dirs in TestMain"
SHA_ABSORBED=$(git -C "$REPO" rev-parse HEAD)

# Case 2 (idiom-collision): the same filtered-slice idiom upstream has, but the
# commit exists for the one predicate line upstream does not have.
cat > "$REPO/examples/env_test.go" <<'EOF'
package examples

import (
	"os"
	"strings"
)

func mergeTestEnv(overrides map[string]string) []string {
	env := os.Environ()
	filtered := env[:0]
	for _, entry := range env {
		if strings.HasPrefix(entry, "GC_") || strings.HasPrefix(entry, "DOLT_") {
			continue
		}
		filtered = append(filtered, entry)
	}
	env = filtered
	return env
}
EOF
commit "fix(tests): isolate mergeTestEnv from host GC_/DOLT_"
SHA_IDIOM=$(git -C "$REPO" rev-parse HEAD)

# Case 3 (local-only): nothing upstream carries.
cat >> "$REPO/README.md" <<'EOF'
This paragraph documents a purely local operational convention that upstream
has never had any equivalent of, in any file, at any revision.
EOF
commit "docs: local-only operational convention"
SHA_LOCAL=$(git -C "$REPO" rev-parse HEAD)

# Case 4 (absent-upstream): a file upstream does not have at all.
mkdir -p "$REPO/local"
cat > "$REPO/local/only.go" <<'EOF'
package local

func OnlyHereAndNowhereElse() string {
	return "a distinctive local sentinel value"
}
EOF
commit "feat(local): add a file upstream does not have"
SHA_ABSENT=$(git -C "$REPO" rev-parse HEAD)

# Case 5 (trivia): an added block that is mostly noise, to pin exactly which
# lines count. Only the signature and the return carry identity; the comment,
# the short assignment and the brace must not.
cat >> "$REPO/examples/env_test.go" <<'EOF'

// a comment line that must never be counted
func trivialShapeHelperFunction() int {
	x := 1
	return 41 + x + oneDistinctiveIdentifier
}
EOF
commit "refactor(examples): add trivialShapeHelperFunction"
SHA_TRIVIA=$(git -C "$REPO" rev-parse HEAD)

# Case 6 (whitespace): upstream's line differs only by indentation.
cat >> "$REPO/internal/sling/sling_test.go" <<'EOF'

func helperWithDistinctiveName(input string) string {
	return input + "-suffix"
}
EOF
commit "refactor(sling): add helperWithDistinctiveName"
SHA_WS=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q upstream
cat >> "$REPO/internal/sling/sling_test.go" <<'EOF'

func helperWithDistinctiveName(input string) string {
        return input + "-suffix"
}
EOF
commit "upstream: same helper, different indentation"
git -C "$REPO" checkout -q local

probe() { "$SCRIPT" --repo "$REPO" --upstream upstream "$@" 2>"$TMP/err"; }
field() { printf '%s' "$1" | jq -r "$2"; }

# --- case 1: the absorbed shape must be flagged -------------------------------
OUT=$(probe "$SHA_ABSORBED")
if [ $? -ne 0 ]; then bad "absorbed: probe exited non-zero ($(cat "$TMP/err"))"; else
  ok "absorbed: probe exits 0"
fi
if [ "$(field "$OUT" '.[0].overlap')" = "high" ]; then
  ok "absorbed: overlap=high"
else
  bad "absorbed: overlap=$(field "$OUT" '.[0].overlap'), want high"
fi
if [ "$(field "$OUT" '.[0].must_read')" = "true" ]; then
  ok "absorbed: must_read=true"
else
  bad "absorbed: must_read=$(field "$OUT" '.[0].must_read'), want true"
fi
C=$(field "$OUT" '.[0].containment')
if [ "$C" -ge 60 ]; then ok "absorbed: containment $C% >= threshold"; else bad "absorbed: containment $C%, want >= 60"; fi
# The unmatched remainder is the whole point of the report: it must be exactly
# the two guards, so the reader sees what upstream does NOT have.
UNMATCHED=$(field "$OUT" '.[0].unmatched_lines | sort | join("|")')
if [ "$UNMATCHED" = 'if sharedTestCityDir != "" {|if sharedTestFormulaDir != "" {' ]; then
  ok "absorbed: unmatched_lines are exactly the two guards"
else
  bad "absorbed: unmatched_lines=[$UNMATCHED]"
fi
SPAN=$(field "$OUT" '.[0].files[] | select(.path | endswith("sling_test.go")) | .upstream_span')
if grep -qE '^[0-9]+-[0-9]+$' <<<"$SPAN"; then
  ok "absorbed: upstream_span names a line range ($SPAN)"
else
  bad "absorbed: upstream_span=$SPAN, want a line range"
fi
# The span must actually cover upstream's TestMain, or it sends the reader to
# the wrong place — which is the entire value of reporting it.
S_START=${SPAN%-*}; S_END=${SPAN#*-}
TM_LINE=$(git -C "$REPO" show upstream:internal/sling/sling_test.go | grep -n 'func TestMain' | cut -d: -f1)
if [ -n "$TM_LINE" ] && [ "$S_START" -le "$TM_LINE" ] && [ "$S_END" -ge "$TM_LINE" ]; then
  ok "absorbed: upstream_span covers upstream's TestMain (line $TM_LINE)"
else
  bad "absorbed: span $SPAN does not cover TestMain at line $TM_LINE"
fi
# The decoy earlyCleanupHelper line overlaps too and comes first. The span is
# only useful if it is the LONGEST run, so its length is pinned, not just its
# location.
if [ "$((S_END - S_START + 1))" = "5" ]; then
  ok "absorbed: upstream_span is the longest run (5 lines), not the first"
else
  bad "absorbed: span $SPAN spans $((S_END - S_START + 1)) lines, want 5"
fi

# --- case 2: the idiom collision is flagged too, and that is pinned -----------
OUT=$(probe "$SHA_IDIOM")
if [ "$(field "$OUT" '.[0].overlap')" = "high" ]; then
  ok "idiom-collision: overlap=high (probe does NOT separate this from absorption)"
else
  bad "idiom-collision: overlap=$(field "$OUT" '.[0].overlap'), want high"
fi
UNMATCHED=$(field "$OUT" '.[0].unmatched_lines | join("|")')
case "$UNMATCHED" in
  *'strings.HasPrefix(entry, "GC_")'*) ok "idiom-collision: the load-bearing line is reported unmatched" ;;
  *) bad "idiom-collision: unmatched_lines=[$UNMATCHED], want the GC_/DOLT_ predicate" ;;
esac

# --- case 3: local-only stays quiet -------------------------------------------
OUT=$(probe "$SHA_LOCAL")
if [ "$(field "$OUT" '.[0].overlap')" = "none" ] && [ "$(field "$OUT" '.[0].containment')" = "0" ]; then
  ok "local-only: overlap=none, containment=0"
else
  bad "local-only: overlap=$(field "$OUT" '.[0].overlap') containment=$(field "$OUT" '.[0].containment')"
fi
if [ "$(field "$OUT" '.[0].must_read')" = "false" ]; then
  ok "local-only: must_read=false"
else
  bad "local-only: must_read=$(field "$OUT" '.[0].must_read'), want false"
fi

# --- case 4: a file upstream does not have ------------------------------------
OUT=$(probe "$SHA_ABSENT")
ST=$(field "$OUT" '.[0].files[] | select(.path == "local/only.go") | .status')
if [ "$ST" = "absent-upstream" ]; then
  ok "absent-upstream: reported as absent, not as absorption"
else
  bad "absent-upstream: status=$ST"
fi
if [ "$(field "$OUT" '.[0].containment')" = "0" ]; then
  ok "absent-upstream: containment=0"
else
  bad "absent-upstream: containment=$(field "$OUT" '.[0].containment')"
fi

# --- case 5: only lines that carry identity are counted -----------------------
OUT=$(probe "$SHA_TRIVIA")
E=$(field "$OUT" '.[0].eligible')
if [ "$E" = "2" ]; then
  ok "trivia: eligible counts only the two lines that carry identity"
else
  bad "trivia: eligible=$E, want 2 (signature + return only)"
fi
U=$(field "$OUT" '.[0].unmatched_lines | join("|")')
case "$U" in
  *'a comment line that must never be counted'*) bad "trivia: a comment was counted as an added line" ;;
  *'x := 1'*) bad "trivia: a short assignment was counted as an added line" ;;
  *) ok "trivia: the comment and the short assignment are both excluded" ;;
esac

# --- case 6: indentation must not decide containment --------------------------
OUT=$(probe "$SHA_WS")
if [ "$(field "$OUT" '.[0].overlap')" = "high" ]; then
  ok "whitespace: a re-indented upstream line still matches"
else
  bad "whitespace: overlap=$(field "$OUT" '.[0].overlap'), want high"
fi

# --- shared boilerplate is not overlap ----------------------------------------
# The local-only commit appends to README.md, a file whose upstream copy both
# exists and shares its heading and blank lines with the fork's. Nothing the
# commit ADDS is upstream, so the count must be zero: matching is whole-line
# against the added lines only, never against the file's shared remainder.
OUT=$(probe "$SHA_LOCAL")
if [ "$(field "$OUT" '.[0].matched')" = "0" ]; then
  ok "a shared file's unchanged remainder does not count as overlap"
else
  bad "shared remainder matched $(field "$OUT" '.[0].matched') added lines"
fi

# --- ordering and 1:1 output --------------------------------------------------
OUT=$(probe "$SHA_ABSORBED" "$SHA_LOCAL" "$SHA_ABSENT")
if [ "$(field "$OUT" 'length')" = "3" ]; then
  ok "output pairs 1:1 with the input commits"
else
  bad "output has $(field "$OUT" 'length') entries for 3 commits"
fi
OUT=$(probe --range "$BASE..$SHA_LOCAL")
if [ "$(field "$OUT" '.[0].subject')" = "test(sling): cleanup shared fixture dirs in TestMain" ]; then
  ok "--range emits oldest first"
else
  bad "--range first subject = $(field "$OUT" '.[0].subject')"
fi

# --- threshold is honored -----------------------------------------------------
OUT=$(probe --threshold 99 "$SHA_ABSORBED")
if [ "$(field "$OUT" '.[0].overlap')" = "partial" ] && [ "$(field "$OUT" '.[0].must_read')" = "false" ]; then
  ok "--threshold 99 demotes the absorbed case to partial"
else
  bad "--threshold 99: overlap=$(field "$OUT" '.[0].overlap') must_read=$(field "$OUT" '.[0].must_read')"
fi

# --- usage errors fail closed -------------------------------------------------
if ! "$SCRIPT" --upstream upstream "$SHA_LOCAL" >/dev/null 2>&1; then
  ok "missing --repo exits non-zero"
else
  bad "missing --repo exited 0"
fi
if ! "$SCRIPT" --repo "$REPO" --upstream no/such/ref "$SHA_LOCAL" >/dev/null 2>&1; then
  ok "unresolvable --upstream exits non-zero"
else
  bad "unresolvable --upstream exited 0"
fi
if ! "$SCRIPT" --repo "$REPO" --upstream upstream --range "$BASE..$SHA_LOCAL" "$SHA_LOCAL" >/dev/null 2>&1; then
  ok "--range with explicit shas exits non-zero"
else
  bad "--range with explicit shas exited 0"
fi
if ! "$SCRIPT" --repo "$REPO" --upstream upstream >/dev/null 2>&1; then
  ok "no commits exits non-zero"
else
  bad "no commits exited 0"
fi

# --- audit mode ---------------------------------------------------------------
# The two records the audit joins are metadata STRINGS holding JSON, and the
# survey records a short sha while the rebase loop records a long one.
BEAD=$(jq -nc '{id:"gc-audit",metadata:{
  commit_verdicts:([{sha:"c10144a48",subject:"cleanup fixture dirs",verdict:"keep",rationale:"no upstream equivalent"},
                    {sha:"aaaaaaaa1",subject:"genuinely local",verdict:"keep",rationale:"local only"},
                    {sha:"bbbbbbbb2",subject:"already upstream",verdict:"drop-merged-upstream",rationale:"patch-id"}]|tojson),
  conflict_resolutions:([{commit_sha:"c10144a4853e4493",commit_subject:"cleanup fixture dirs",classification:"dropped-absorbed",resolution:"upstream has TestMain"},
                         {commit_sha:"aaaaaaaa1000",commit_subject:"genuinely local",classification:"mechanical",resolution:"ported"}]|tojson)}}')
AUD=$(printf '%s' "$BEAD" | "$SCRIPT" --audit 2>"$TMP/err")
if [ "$(field "$AUD" '.survey_misses')" = "1" ]; then
  ok "audit: one survey miss (keep -> dropped-absorbed)"
else
  bad "audit: survey_misses=$(field "$AUD" '.survey_misses'), want 1 ($(cat "$TMP/err"))"
fi
if [ "$(field "$AUD" '.missed_commits[0].sha')" = "c10144a48" ]; then
  ok "audit: joins a short survey sha to a long rebase sha"
else
  bad "audit: missed sha=$(field "$AUD" '.missed_commits[0].sha')"
fi
if [ "$(field "$AUD" '.kept')" = "2" ] && [ "$(field "$AUD" '.miss_rate_pct')" = "50" ]; then
  ok "audit: miss rate is over kept commits only"
else
  bad "audit: kept=$(field "$AUD" '.kept') miss_rate_pct=$(field "$AUD" '.miss_rate_pct')"
fi
if [ "$(field "$AUD" '.missed_commits[0].survey_rationale')" = "no upstream equivalent" ]; then
  ok "audit: carries the rationale that was wrong"
else
  bad "audit: rationale=$(field "$AUD" '.missed_commits[0].survey_rationale')"
fi
# A `mechanical` resolution is a conflict the surveyor was RIGHT to keep.
if [ "$(field "$AUD" '.missed_commits | map(.sha) | index("aaaaaaaa1")')" = "null" ]; then
  ok "audit: a mechanical conflict is not counted as a survey miss"
else
  bad "audit: mechanical conflict counted as a miss"
fi
# `gc bd show` prints a store banner before the JSON.
AUD=$(printf 'gc bd: answering from the rig "gascity" store\n%s' "$BEAD" | "$SCRIPT" --audit 2>"$TMP/err")
if [ "$(field "$AUD" '.survey_misses')" = "1" ]; then
  ok "audit: tolerates the gc bd store banner"
else
  bad "audit: banner broke the parse ($(cat "$TMP/err"))"
fi
# A bead array, as `gc bd show --json` actually emits it.
AUD=$(printf '[%s]' "$BEAD" | "$SCRIPT" --audit 2>"$TMP/err")
if [ "$(field "$AUD" '.survey_misses')" = "1" ]; then
  ok "audit: accepts the single-element array gc bd show emits"
else
  bad "audit: array form failed ($(cat "$TMP/err"))"
fi
# A bead with no rebase record yet must report zero, not fail.
AUD=$(jq -nc '{id:"gc-none",metadata:{commit_verdicts:([{sha:"z1",subject:"s",verdict:"keep",rationale:"r"}]|tojson)}}' \
      | "$SCRIPT" --audit 2>"$TMP/err")
if [ "$(field "$AUD" '.survey_misses')" = "0" ] && [ "$(field "$AUD" '.kept')" = "1" ]; then
  ok "audit: a bead with no conflict_resolutions reports zero misses"
else
  bad "audit: no-resolutions bead gave $(field "$AUD" '.survey_misses') ($(cat "$TMP/err"))"
fi
if ! printf 'not json at all\n' | "$SCRIPT" --audit >/dev/null 2>&1; then
  ok "audit: non-JSON input exits non-zero"
else
  bad "audit: non-JSON input exited 0"
fi

echo
echo "survey-absorption-probe.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
