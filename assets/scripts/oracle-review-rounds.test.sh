#!/usr/bin/env bash
# Tests for oracle-review-rounds.sh: the counting logic against a hermetic store.
# Proves it counts only terminal non-rework anchors, counts only decided review
# rounds (review_branch + signoff_verdict), and prints the rate as a bare number.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/oracle-review-rounds.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-oracle-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; STATE="$TMP/state"
mkdir -p "$BIN" "$STATE"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

# stub bd list: serves reviews when the query names task_kind=review, else anchors.
cat > "$BIN/bd" <<'STUB'
#!/usr/bin/env bash
S="$GOAL_TEST_STATE"
[ "${1:-}" = "list" ] || { printf '[]\n'; exit 0; }
shift
case "$*" in
  *task_kind=review*) cat "$S/reviews.json" ;;
  *merge_result*)     cat "$S/anchors.json" ;;
  *)                  printf '[]\n' ;;
esac
STUB
chmod +x "$BIN/bd"
export GOAL_TEST_STATE="$STATE"

# 4 terminal non-rework anchors (a1..a4); r1/m1 filtered by title, x1 by
# task_kind=rework, p1 by non-terminal merge_result.
cat > "$STATE/anchors.json" <<'JSON'
[
 {"id":"a1","title":"impl A","metadata":{"merge_result":"merged"}},
 {"id":"a2","title":"impl B","metadata":{"merge_result":"merged"}},
 {"id":"a3","title":"impl C","metadata":{"merge_result":"abandoned"}},
 {"id":"a4","title":"impl D","metadata":{"merge_result":"duplicate"}},
 {"id":"r1","title":"Rework branch polecat/a1: address findings","metadata":{"merge_result":"merged"}},
 {"id":"m1","title":"Merge main into polecat/a2","metadata":{"merge_result":"merged"}},
 {"id":"x1","title":"impl E","metadata":{"merge_result":"merged","task_kind":"rework"}},
 {"id":"p1","title":"impl F","metadata":{"merge_result":"pull_request"}}
]
JSON

# decided rounds (review_branch + signoff_verdict): a1=2, a2=1, a3=3, a4=0.
# v3 has no verdict (churn), v5 has no branch (validator) — neither counts.
cat > "$STATE/reviews.json" <<'JSON'
[
 {"id":"v1","metadata":{"task_kind":"review","anchor_bead":"a1","review_branch":"polecat/a1","signoff_verdict":"request-changes"}},
 {"id":"v2","metadata":{"task_kind":"review","anchor_bead":"a1","review_branch":"polecat/a1","signoff_verdict":"approve"}},
 {"id":"v3","metadata":{"task_kind":"review","anchor_bead":"a1","review_branch":"polecat/a1"}},
 {"id":"v4","metadata":{"task_kind":"review","anchor_bead":"a2","review_branch":"polecat/a2","signoff_verdict":"approve"}},
 {"id":"v5","metadata":{"task_kind":"review","anchor_bead":"a2","signoff_verdict":"approve"}},
 {"id":"v6","metadata":{"task_kind":"review","anchor_bead":"a3","review_branch":"polecat/a3","signoff_verdict":"request-changes"}},
 {"id":"v7","metadata":{"task_kind":"review","anchor_bead":"a3","review_branch":"polecat/a3","signoff_verdict":"request-changes"}},
 {"id":"v8","metadata":{"task_kind":"review","anchor_bead":"a3","review_branch":"polecat/a3","signoff_verdict":"approve"}}
]
JSON

run() { PATH="$BIN:$PATH" bash "$SUT" "$@" 2>/dev/null; }

# second-review rate: anchors with >=2 decided rounds (a1,a3) over N=4 -> 50.0
eq "$(run --window-days 30)" "50.0" "second-review rate = 50.0 (a1,a3 of 4)"

# min-rounds 3: only a3 -> 25.0
eq "$(run --window-days 30 --min-rounds 3)" "25.0" "third-review rate = 25.0 (a3 of 4)"

# min-rounds 1: a1,a2,a3 have >=1 -> 75.0
eq "$(run --window-days 30 --min-rounds 1)" "75.0" "first-review rate = 75.0 (a1,a2,a3 of 4)"

# stdout is a single bare number
LINES=$(run --window-days 30 | wc -l | tr -d ' ')
eq "$LINES" "1" "prints one line to stdout"

# empty store -> exit 1 (cannot measure)
printf '[]\n' > "$STATE/anchors.json"
set +e; run --window-days 30 >/dev/null 2>&1; rc=$?; set -e
eq "$rc" "1" "no terminal anchors -> exit 1"

# bad flag -> exit 2
set +e; PATH="$BIN:$PATH" bash "$SUT" --min-rounds abc >/dev/null 2>&1; rc=$?; set -e
eq "$rc" "2" "non-integer --min-rounds -> exit 2"

echo "---"
echo "oracle-review-rounds: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
