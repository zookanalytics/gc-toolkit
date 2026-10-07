#!/usr/bin/env bash
# test-harness.test.sh — the harness's own contract: harness_init hands a suite
# a clean environment. These suites run from a tree inside a live city, whose
# session exports GC_* and BEADS_* (the rig, the city path, the actor, the bead
# under work). A leaked GC_RIG turns into a `--rig <rig>` in a logged sling argv,
# so an inherited value would settle a hermetic assertion on the operator's shell
# rather than on the code. harness_init clears both namespaces so no suite has to.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-test-harness-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"

# Seed the environment a polecat/agent session exports, plus a port binary path
# a suite builds before sourcing the harness (the lifecycle.test.sh pattern:
# GCTK_BUILT is set pre-init because the stub git must not answer the Go build).
export GC_RIG=gc-toolkit GC_CITY_PATH=/live/city GC_CITY=loomington
export GC_AGENT=rig/gc-toolkit.polecat GC_SESSION_NAME=live-sess GC_SESSION_ID=lx-live
export GC_TRIGGER_BEAD_ID=tk-live GC_RIG_ROOT=/live/rigs/gc-toolkit
export BEADS_DIR=/live/beads BEADS_ACTOR=live-actor
GCTK_BUILT="$TMP/gctk"

# Capture the seed before harness_init runs — it is the call under test AND it
# resets PASS/FAIL, so every assertion has to come after it. The captures let a
# post-init assertion prove the seed was really set, so "cleared" is a real
# transition and not a variable that was never there.
SEED_GC_RIG="${GC_RIG:-}"; SEED_BEADS_DIR="${BEADS_DIR:-}"

harness_init

# The seed took, so the clears below discriminate.
eq "$SEED_GC_RIG"   "gc-toolkit"  "seed: GC_RIG was set before harness_init"
eq "$SEED_BEADS_DIR" "/live/beads" "seed: BEADS_DIR was set before harness_init"

# harness_init cleared every live-city variable it was handed.
for v in GC_RIG GC_CITY_PATH GC_CITY GC_AGENT GC_SESSION_NAME GC_SESSION_ID \
         GC_TRIGGER_BEAD_ID GC_RIG_ROOT BEADS_DIR BEADS_ACTOR; do
  if [ -z "${!v:-}" ]; then ok "harness_init cleared $v"; else bad "harness_init left $v=[${!v}]"; fi
done

# The whole namespace, not just the names above: a variable a future city release
# adds must be gone too, or the leak returns one release later. GC_NO_API is the
# one deliberate exception. harness_init sets it, rather than inheriting it, to
# pin the gctk read seam onto the stubbed gc the same way GCTK_BIN is pinned. The
# sweep excludes it by exact name, and the assertion below proves the pin took.
resid="$(compgen -v | grep -E '^(GC_|BEADS_)' | grep -vxF GC_NO_API || true)"
if [ -z "$resid" ]; then ok "no GC_/BEADS_ variable survives harness_init"; else bad "residual city vars: $resid"; fi
eq "${GC_NO_API:-}" "1" "harness_init pins GC_NO_API=1 so a gctk read hits the stub, not the live daemon"

# GCTK_* is out of scope: the port pin stays, and a pre-init build path is not
# collateral — a blanket GC* unset would have taken GCTK_BUILT with it.
eq "$GCTK_BIN"   "none"       "harness_init pins GCTK_BIN=none"
eq "$GCTK_BUILT" "$TMP/gctk"  "harness_init preserves a pre-init GCTK_BUILT"

# The hermetic stub environment is still installed.
case "$STUB_STORE" in "$TMP"/*) ok "STUB_STORE points into TMP" ;; *) bad "STUB_STORE not under TMP: $STUB_STORE" ;; esac
case ":$PATH:" in *":$TMP/bin:"*) ok "stub bin is on PATH" ;; *) bad "stub bin not on PATH" ;; esac
[ -x "$TMP/bin/gc" ] && ok "stub gc installed" || bad "stub gc missing"

# A suite that WANTS a rig sets it after harness_init returns.
export GC_RIG=myrig
eq "$GC_RIG" "myrig" "a rig exported after harness_init is honored"

# The gc bd dep stub mirrors real bd's blocks orientation. Real `dep add
# <blocked> <blocker> --type blocks` makes the SECOND operand the blocker — the
# documented `dep add Y X` equals `dep X --blocks Y`. A stub that stored the add
# source-first lets a reversed dep-add read back as the intended edge and pass,
# so the orientation is pinned here.
store '[{"id":"tk-blk","status":"open","assignee":"","title":"b","notes":"","metadata":{}},{"id":"tk-kd","status":"open","assignee":"","title":"k","notes":"","metadata":{}}]'
down_blockers() { gc bd dep list "$1" --direction=down -t blocks --json | jq -r '.[].id' | tr '\n' ' '; }
: > "$STUB_DEPS"
gc bd dep add tk-kd tk-blk --type blocks
has " $(down_blockers tk-kd) " " tk-blk " "dep add <blocked> <blocker> --type blocks: the second operand is the blocker"
hasnt " $(down_blockers tk-blk) " " tk-kd " "...not the reverse — the first operand is the blocked, never a blocker"
: > "$STUB_DEPS"
gc bd dep tk-blk --blocks tk-kd
has " $(down_blockers tk-kd) " " tk-blk " "dep <blocker> --blocks <blocked> lands the same orientation as the dep add form"

# mk_sut_dir carries the libraries a copied SUT sources by sibling path. A copy
# of lifecycle.sh without gctk-resolve.sh beside it refuses every call, so the
# suites that copy it would fail on the harness rather than the code.
mk_sut_dir "$TMP/sut" "$HERE/lifecycle.sh"
[ -f "$TMP/sut/bd-lib.sh" ] && ok "mk_sut_dir copies bd-lib.sh beside the SUT" || bad "mk_sut_dir left bd-lib.sh out"
[ -f "$TMP/sut/gctk-resolve.sh" ] && ok "mk_sut_dir copies gctk-resolve.sh beside the SUT" || bad "mk_sut_dir left gctk-resolve.sh out"
out="$(GCTK_BIN=none "$TMP/sut/lifecycle.sh" state tk-blk 2>&1)"
hasnt "$out" "cannot source gctk-resolve.sh" "a copied lifecycle.sh sources gctk-resolve.sh from its private dir"

# The partial-read knobs model a store error that still printed an array: a
# matching list, or any dep probe, prints [] and exits 1.
out="$(STUB_LIST_PARTIAL="merge_result=pull_request" gc bd list --status=open --metadata-field merge_result=pull_request --json 2>/dev/null)"; rc=$?
eq "$out|$rc" "[]|1" "STUB_LIST_PARTIAL: a matching list prints [] and exits 1"
out="$(STUB_LIST_PARTIAL="merge_result=pull_request" gc bd list --status=open --json 2>/dev/null)"; rc=$?
eq "$rc" "0" "STUB_LIST_PARTIAL: a list that does not match answers normally"
out="$(STUB_DEP_PARTIAL=1 gc bd dep list tk-kd --direction=down -t blocks --json 2>/dev/null)"; rc=$?
eq "$out|$rc" "[]|1" "STUB_DEP_PARTIAL: the dep probe prints [] and exits 1"

# The trailing-bytes knobs model a stream that is unreadable only after its
# array: a matching list, or any dep probe, prints its answer at exit 0 and then
# a line that fails the `jq -e 'type == "array"'` gate the scripts read through.
is_array() { printf '%s' "$1" | jq -e 'type == "array"' >/dev/null 2>&1; }
out="$(STUB_LIST_TRAILING="merge_result=pull_request" gc bd list --status=open --metadata-field merge_result=pull_request --json 2>/dev/null)"; rc=$?
eq "$rc|$(printf '%s\n' "$out" | head -1 | jq -r 'type' 2>/dev/null)" "0|array" "STUB_LIST_TRAILING: a matching list prints its array and exits 0"
if is_array "$out"; then bad "STUB_LIST_TRAILING: the stream still passes the array gate"; else ok "STUB_LIST_TRAILING: …and the bytes after it fail the array gate"; fi
out="$(STUB_LIST_TRAILING="merge_result=pull_request" gc bd list --status=open --json 2>/dev/null)"
if is_array "$out"; then ok "STUB_LIST_TRAILING: a list that does not match answers normally"; else bad "STUB_LIST_TRAILING: a list that does not match carried the tail"; fi
out="$(STUB_DEP_TRAILING=1 gc bd dep list tk-kd --direction=down -t blocks --json 2>/dev/null)"; rc=$?
eq "$rc|$(printf '%s\n' "$out" | head -1 | jq -r 'type' 2>/dev/null)" "0|array" "STUB_DEP_TRAILING: the dep probe prints its array and exits 0"
if is_array "$out"; then bad "STUB_DEP_TRAILING: the stream still passes the array gate"; else ok "STUB_DEP_TRAILING: …and the bytes after it fail the array gate"; fi

# The gh pr view queue scripts the reads of one field set in order, ahead of the
# fixture. A suite queues an UNKNOWN merge state, a failed read, then a computed
# answer, and every step has to reach the read it was queued for: a read of
# another field set must not take one, and an empty file must fail one read and
# then be gone, or every later read fails on it.
printf '{"n":"fixture"}' > "$GH_DIR/pr_view_7.json"
Q="$GH_DIR/pr_view_7.queue/a,b"; mkdir -p "$Q"
printf '{"n":"first"}' > "$Q/01.json"; : > "$Q/02.json"; printf '{"n":"third"}' > "$Q/03.json"
view7() { gh pr view 7 --repo zook/gc-toolkit --json "$1" -q .n 2>/dev/null; }
eq "$(view7 c)" "fixture" "pr view queue: a read of another field set gets the fixture"
eq "$(view7 a,b)" "first" "pr view queue: a read of the queued field set takes the first file"
out=$(view7 a,b); rc=$?
eq "$rc:$out" "1:" "pr view queue: an empty file is a failed read"
eq "$(view7 a,b)" "third" "pr view queue: …consumed, so the next read takes the file after it"
eq "$(view7 a,b)" "fixture" "pr view queue: the fixture answers once the queue is empty"
eq "$(find "$Q" -type f | wc -l | tr -d ' ')" "0" "pr view queue: every queued file was consumed"

# The gc bd update stub stores a --set-metadata value with real bd's typing. A
# value that parses as a JSON number, true, false or null is stored typed, so
# `k=1` reads back as the number 1, and a jq compare of it against the string
# "1" is false. Every other value is stored as its raw text. A stub that stored
# only strings would pass a script whose jq compares a stamp to a string
# literal, and the real store would fail it, so the typing is pinned value by
# value. Numbers are pinned by type alone: jq versions print a number literal
# such as 1e3 differently.
store '[{"id":"tk-md","status":"open","assignee":"","title":"m","notes":"","metadata":{}}]'
stored_type() { jq -r --arg k "$1" '.[] | select(.id == "tk-md") | .metadata | if has($k) then (.[$k] | type) else "<absent>" end' "$STUB_STORE"; }
stored_json() { jq -c --arg k "$1" '.[] | select(.id == "tk-md") | .metadata[$k]' "$STUB_STORE"; }
gc bd update tk-md --set-metadata one=1 --set-metadata pr=1025 --set-metadata neg=-1 \
  --set-metadata frac=1.5 --set-metadata exp=1e3 --set-metadata padded=" 1" \
  --set-metadata yes=true --set-metadata no=false --set-metadata nul=null \
  --set-metadata word=main --set-metadata lead0=0123 --set-metadata zeros=00 \
  --set-metadata plus=+1 --set-metadata dot=.5 --set-metadata nan=NaN --set-metadata cap=True \
  --set-metadata quoted='"x"' --set-metadata arr='[1]' --set-metadata obj='{}' --set-metadata empty= >/dev/null
eq "$(stored_json one)" '1' "k=1 is stored as the number 1, not the string \"1\""
for k in pr neg frac exp padded; do
  eq "$(stored_type "$k")" "number" "a JSON number ($k) is stored as a number"
done
eq "$(stored_json yes)" 'true'  "k=true is stored as the boolean true"
eq "$(stored_json no)"  'false' "k=false is stored as the boolean false"
eq "$(stored_type nul)" "null"  "k=null is stored as JSON null, with the key present"
eq "$(stored_json word)"   '"main"'  "a word is stored as a string"
eq "$(stored_json lead0)"  '"0123"'  "a leading-zero number is not JSON, so it stays a string"
eq "$(stored_json zeros)"  '"00"'    "00 stays a string"
eq "$(stored_json plus)"   '"+1"'    "+1 stays a string"
eq "$(stored_json dot)"    '".5"'    ".5 stays a string"
eq "$(stored_json nan)"    '"NaN"'   "NaN stays a string"
eq "$(stored_json cap)"    '"True"'  "True stays a string: only lowercase true and false are booleans"
eq "$(stored_json quoted)" '"\"x\""' "a quoted JSON string keeps its quotes"
eq "$(stored_json arr)"    '"[1]"'   "a JSON array is stored as its raw text"
eq "$(stored_json obj)"    '"{}"'    "a JSON object is stored as its raw text"
eq "$(stored_json empty)"  '""'      "an empty value is stored as the empty string"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
