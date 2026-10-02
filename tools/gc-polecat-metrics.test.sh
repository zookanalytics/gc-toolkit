#!/usr/bin/env bash
# Hermetic test for tools/gc-polecat-metrics.sh (tk-6lvz29). Drives the tool
# entirely through its GC_POLECAT_METRICS_FIXTURE seam — canned bead-store reads
# and a canned usage sink, no live city — and asserts on the --json output.
#
# Covers: the session trace (anchor <- convoy <- root -> load-context session),
# the anchor-stamp fallback, an unrecoverable-session row (tokens n/a), the
# per-session sharing caveat (one session, two beads), start-time fallback with
# the start_source flag, review/rework counting by branch, the closed-date
# window filter, model-vs-compute record selection, and the grep-then-jq exact
# session match (a sink line that only mentions a target id in another field is
# not counted).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-polecat-metrics.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-polecat-metrics-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
NOW="$(date -u +%s)"
R_CLOSE="$(iso $((NOW - 2*86400)))"
R_START="$(iso $((NOW - 2*86400 - 3600)))"
R_CREATE="$(iso $((NOW - 3*86400)))"
O_CLOSE="$(iso $((NOW - 400*86400)))"
O_CREATE="$(iso $((NOW - 401*86400)))"

FIX="$TMP/fix"; mkdir -p "$FIX"

# --- anchors: one per scenario -------------------------------------------
cat > "$FIX/anchors.json" <<JSON
[
  {"id":"wb-merged1","title":"feat: traced bead","status":"closed",
   "created_at":"$R_CREATE","started_at":"$R_START","closed_at":"$R_CLOSE",
   "metadata":{"merge_result":"merged","branch":"polecat/wb-merged1","pr_number":"100",
     "pr_url":"http://pr/100","merged_sha":"sha100","merged_target":"main","check_set":"codex"}},
  {"id":"wb-stamp","title":"feat: stamped bead","status":"closed",
   "created_at":"$R_CREATE","started_at":null,"closed_at":"$R_CLOSE",
   "metadata":{"merge_result":"merged","branch":"polecat/wb-stamp","pr_number":"101",
     "gc.session_id":"sess-B"}},
  {"id":"wb-nosession","title":"feat: unrecoverable session","status":"closed",
   "created_at":"$R_CREATE","started_at":"$R_START","closed_at":"$R_CLOSE",
   "metadata":{"merge_result":"merged","branch":"polecat/wb-nosession","pr_number":"102"}},
  {"id":"wb-shareA","title":"feat: shared session A","status":"closed",
   "created_at":"$R_CREATE","started_at":"$R_START","closed_at":"$R_CLOSE",
   "metadata":{"merge_result":"merged","branch":"polecat/wb-shareA","pr_number":"103"}},
  {"id":"wb-shareB","title":"feat: shared session B","status":"closed",
   "created_at":"$R_CREATE","started_at":"$R_START","closed_at":"$R_CLOSE",
   "metadata":{"merge_result":"merged","branch":"polecat/wb-shareB","pr_number":"104"}},
  {"id":"wb-old","title":"feat: outside the window","status":"closed",
   "created_at":"$O_CREATE","started_at":null,"closed_at":"$O_CLOSE",
   "metadata":{"merge_result":"merged","branch":"polecat/wb-old","pr_number":"99","gc.session_id":"sess-B"}}
]
JSON

cat > "$FIX/convoys.json" <<'JSON'
[
  {"id":"cv1","title":"input convoy for wb-merged1","issue_type":"convoy"},
  {"id":"cv2","title":"input convoy for wb-shareA","issue_type":"convoy"},
  {"id":"cv3","title":"input convoy for wb-shareB","issue_type":"convoy"}
]
JSON

cat > "$FIX/roots.json" <<'JSON'
[
  {"id":"r1","title":"mol-polecat-work","metadata":{"gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"cv1"}},
  {"id":"r2","title":"mol-polecat-work","metadata":{"gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"cv2"}},
  {"id":"r3","title":"mol-polecat-work","metadata":{"gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"cv3"}}
]
JSON

cat > "$FIX/loadcontext.json" <<'JSON'
[
  {"id":"lc1","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"r1","gc.session_id":"sess-A","gc.session_name":"polecat-A"}},
  {"id":"lc2","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"r2","gc.session_id":"sess-S","gc.session_name":"polecat-S"}},
  {"id":"lc3","metadata":{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"r3","gc.session_id":"sess-S","gc.session_name":"polecat-S"}}
]
JSON

cat > "$FIX/reviews.json" <<'JSON'
[
  {"id":"rv1","title":"Review branch polecat/wb-merged1 -> main (codex)","metadata":{"task_kind":"review","check_name":"codex","review_branch":"polecat/wb-merged1"}},
  {"id":"rv2","title":"Review branch polecat/wb-merged1 -> main (correctness)","metadata":{"task_kind":"review","check_name":"correctness","review_branch":"polecat/wb-merged1"}},
  {"id":"rv3","title":"Review branch polecat/wb-shareA -> main (codex)","metadata":{"task_kind":"review","check_name":"codex","review_branch":"polecat/wb-shareA"}}
]
JSON

# rk1: a post-open "Rework PR#..." round. rk2: a pre-open "Rework branch ..."
# child — a different title the live fetch now reaches via task_kind=rework, not
# the old title prefix. rk3: a finding bead that merely quotes "Rework PR" in its
# title and carries no branch; it must join no row.
cat > "$FIX/reworks.json" <<'JSON'
[
  {"id":"rk1","title":"Rework PR#100: address findings","metadata":{"branch":"polecat/wb-merged1"}},
  {"id":"rk2","title":"Rework branch polecat/wb-merged1: address pre-open signoff findings","metadata":{"task_kind":"rework","branch":"polecat/wb-merged1","source_review_bead":"rv2"}},
  {"id":"rk3","title":"finding[correctness]: the report fetches rework rows with the Rework PR title match","metadata":{"task_kind":"finding"}}
]
JSON

# --- usage sink: model records to sum, a compute record to exclude, and a
#     foreign session whose line only mentions sess-A in idempotency_key ------
cat > "$FIX/usage.jsonl" <<'JSON'
{"kind":"model","session_id":"sess-A","run_id":"sess-A","output_tokens":100,"input_tokens":10,"cache_read_tokens":1000,"cache_creation_tokens":50,"cost_usd_estimate":1.0}
{"kind":"model","session_id":"sess-A","run_id":"sess-A","output_tokens":200,"input_tokens":20,"cache_read_tokens":2000,"cache_creation_tokens":60,"cost_usd_estimate":2.0}
{"kind":"compute","session_id":"sess-A","run_id":"sess-A","wall_seconds":42.0}
{"kind":"model","session_id":"sess-B","run_id":"sess-B","output_tokens":500,"input_tokens":5,"cache_read_tokens":500,"cache_creation_tokens":5,"cost_usd_estimate":5.0}
{"kind":"model","session_id":"sess-S","run_id":"sess-S","output_tokens":700,"input_tokens":7,"cache_read_tokens":700,"cache_creation_tokens":7,"cost_usd_estimate":7.0}
{"kind":"model","session_id":"sess-S","run_id":"sess-S","output_tokens":800,"input_tokens":8,"cache_read_tokens":800,"cache_creation_tokens":8,"cost_usd_estimate":8.0}
{"kind":"model","session_id":"sess-OTHER","run_id":"sess-OTHER","output_tokens":9999,"input_tokens":1,"cache_read_tokens":1,"cache_creation_tokens":1,"cost_usd_estimate":99.0,"idempotency_key":"ref-sess-A-leak"}
JSON

export GC_POLECAT_METRICS_FIXTURE="$FIX"

# --- windowed run (30d): wb-old must drop out --------------------------------
OUT="$(bash "$SCRIPT" --since 30 --json 2>/dev/null)"
eq "$(printf '%s' "$OUT" | jq -r '.meta.total')" "5" "(WINDOW) wb-old excluded, 5 rows in 30d window"
eq "$(printf '%s' "$OUT" | jq -r '.meta.token_resolved')" "4" "(COVERAGE) 4 of 5 rows have tokens"
eq "$(printf '%s' "$OUT" | jq -r '.meta.token_unresolved')" "1" "(COVERAGE) 1 row unresolved"

row() { printf '%s' "$OUT" | jq -c --arg b "$1" '.rows[] | select(.bead==$b)'; }

M="$(row wb-merged1)"
eq "$(printf '%s' "$M" | jq -r '.sessions[0]')" "sess-A" "(TRACE) wb-merged1 session recovered via load-context trace"
eq "$(printf '%s' "$M" | jq -r '.tokens.output_tokens')" "300" "(SUM) wb-merged1 output = 100+200 (compute record excluded)"
eq "$(printf '%s' "$M" | jq -r '.tokens.cost_usd_estimate')" "3" "(SUM) wb-merged1 cost = 1.0+2.0"
eq "$(printf '%s' "$M" | jq -r '.reviews')" "2" "(REVIEWS) wb-merged1 counts 2 gate reviews on its branch"
eq "$(printf '%s' "$M" | jq -r '.reviews_by_check.correctness')" "1" "(REVIEWS) by-check breakdown present"
eq "$(printf '%s' "$M" | jq -r '.reworks')" "2" "(REWORKS) wb-merged1 counts its post-open and pre-open 'Rework branch' rounds; a branchless title match is excluded"
eq "$(printf '%s' "$M" | jq -r '.start_source')" "started_at" "(START) wb-merged1 uses started_at"
eq "$(printf '%s' "$M" | jq -r '.tokens_shared')" "false" "(SHARE) wb-merged1 not shared"

S="$(row wb-stamp)"
eq "$(printf '%s' "$S" | jq -r '.sessions[0]')" "sess-B" "(STAMP) wb-stamp session from anchor gc.session_id"
eq "$(printf '%s' "$S" | jq -r '.tokens.output_tokens')" "500" "(SUM) wb-stamp output = 500"
eq "$(printf '%s' "$S" | jq -r '.start_source')" "created_at" "(START) wb-stamp falls back to created_at (started_at null)"

N="$(row wb-nosession)"
eq "$(printf '%s' "$N" | jq -r '.tokens')" "null" "(NA) wb-nosession has no recoverable session -> tokens null"
eq "$(printf '%s' "$N" | jq -r '.sessions | length')" "0" "(NA) wb-nosession resolved no sessions"

A="$(row wb-shareA)"; B="$(row wb-shareB)"
eq "$(printf '%s' "$A" | jq -r '.tokens_shared')" "true" "(SHARE) wb-shareA flagged shared"
eq "$(printf '%s' "$A" | jq -r '.session_beads')" "2" "(SHARE) wb-shareA session built 2 beads"
eq "$(printf '%s' "$A" | jq -r '.tokens.output_tokens')" "1500" "(SHARE) wb-shareA shows session total 700+800"
eq "$(printf '%s' "$B" | jq -r '.tokens.output_tokens')" "1500" "(SHARE) wb-shareB shows the same session total (repeated)"

# The foreign session's 9999 must never surface — grep may match its line on the
# idempotency_key, but the jq pass keys on (.session_id // .run_id).
eq "$(printf '%s' "$OUT" | jq -r '[.rows[] | select(.tokens!=null) | .tokens.output_tokens] | max')" "1500" "(FILTER) foreign sess-OTHER (9999) never counted"

# --- --all run: wb-old now included ------------------------------------------
OUT_ALL="$(bash "$SCRIPT" --all --json 2>/dev/null)"
eq "$(printf '%s' "$OUT_ALL" | jq -r '.meta.total')" "6" "(ALL) --all includes the out-of-window bead"

# --- a missing sink is reported, not rendered as zero ------------------------
OUT_NOSINK="$(bash "$SCRIPT" --all --json --sink "$TMP/does-not-exist.jsonl" 2>/dev/null)"
eq "$(printf '%s' "$OUT_NOSINK" | jq -r '.meta.sink_available')" "false" "(SINK) missing sink flagged sink_available=false"
eq "$(printf '%s' "$OUT_NOSINK" | jq -r '[.rows[] | select(.tokens!=null)] | length')" "0" "(SINK) no tokens fabricated when sink absent"

echo
echo "gc-polecat-metrics: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
