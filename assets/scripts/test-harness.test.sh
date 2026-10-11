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

# Seed the environment a polecat/agent session exports, an inherited gctk
# binary path and forced fallback, and the build a suite makes before
# harness_init (harness_build_gctk sets GCTK_BUILT pre-init because the stub git
# must not answer the Go build).
export GC_RIG=gc-toolkit GC_CITY_PATH=/live/city GC_CITY=loomington
export GC_AGENT=rig/gc-toolkit.polecat GC_SESSION_NAME=live-sess GC_SESSION_ID=lx-live
export GC_TRIGGER_BEAD_ID=tk-live GC_RIG_ROOT=/live/rigs/gc-toolkit
export BEADS_DIR=/live/beads BEADS_ACTOR=live-actor
export GCTK_BIN=/live/city/.gc/services/gctk/bin/gctk GCTK_FALLBACK=merge
GCTK_BUILT="$TMP/gctk"

# Capture the seed before harness_init runs — it is the call under test AND it
# resets PASS/FAIL, so every assertion has to come after it. The captures let a
# post-init assertion prove the seed was really set, so "cleared" is a real
# transition and not a variable that was never there.
SEED_GC_RIG="${GC_RIG:-}"; SEED_BEADS_DIR="${BEADS_DIR:-}"; SEED_GCTK_FALLBACK="${GCTK_FALLBACK:-}"

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

# GCTK_* is out of that sweep: the pre-init build path is not collateral — a
# blanket GC* unset would have taken GCTK_BUILT with it — and GCTK_BIN is pinned
# to that build, never to the binary an inherited GCTK_BIN names.
eq "$GCTK_BUILT" "$TMP/gctk"  "harness_init preserves a pre-init GCTK_BUILT"
eq "$GCTK_BIN"   "$TMP/gctk"  "harness_init pins GCTK_BIN to the suite's own build, over an inherited one"
# An inherited GCTK_FALLBACK would put a port onto its shell in a suite that
# meant to test the binary, so harness_init clears it.
eq "$SEED_GCTK_FALLBACK" "merge" "seed: GCTK_FALLBACK was set before harness_init"
eq "${GCTK_FALLBACK-<unset>}" "<unset>" "harness_init clears an inherited GCTK_FALLBACK"

# A suite that built nothing reaches no binary at all: lifecycle.sh refuses
# under GCTK_BIN=none, and that refusal is what such a suite sees.
eq "$(unset GCTK_BUILT; harness_init >/dev/null; printf '%s' "$GCTK_BIN")" "none" \
   "with no build, harness_init pins GCTK_BIN=none"
# A build that did not happen is named as the suite's first failure, rather
# than surfacing as every lifecycle transition the suite makes being refused.
out=$(GCTK_BUILT="" GCTK_BUILD_ERR="gctk did not build — fixture" harness_init; echo "fails=$FAIL")
has "$out" "FAIL - gctk did not build — fixture" "harness_init reports a build that did not happen"
has "$out" "fails=1" "…as one counted failure"

# The hermetic stub environment is still installed.
case "$STUB_STORE" in "$TMP"/*) ok "STUB_STORE points into TMP" ;; *) bad "STUB_STORE not under TMP: $STUB_STORE" ;; esac
case ":$PATH:" in *":$TMP/bin:"*) ok "stub bin is on PATH" ;; *) bad "stub bin not on PATH" ;; esac
[ -x "$TMP/bin/gc" ] && ok "stub gc installed" || bad "stub gc missing"

# A suite that WANTS a rig sets it after harness_init returns.
export GC_RIG=myrig
eq "$GC_RIG" "myrig" "a rig exported after harness_init is honored"

# The gc bd create stub lands a create the way real bd does: --metadata (a JSON
# value, its types kept), --status and --notes ride the one insert, and a
# --metadata that is not JSON is refused with nothing created. A stub that
# dropped the payload made a writer whose stamps ride the create look like one
# that stamps in a second write, so no suite could see a payload land at birth.
store '[]'
eq "$(gc bd create "born" -t task --metadata '{"task_kind":"review","n":1,"oid":"0123"}' --status=closed --notes "first note" --json | jq -r '.id')" \
  "new-1" "create answers the id it minted"
eq "$(bstatus new-1)" "closed" "--status rides the create"
eq "$(meta new-1 task_kind)" "review" "--metadata rides the create"
eq "$(jq -c '.[] | select(.id == "new-1") | .metadata.n' "$STUB_STORE")" '1' "…keeping its JSON types: a number stays a number"
eq "$(jq -c '.[] | select(.id == "new-1") | .metadata.oid' "$STUB_STORE")" '"0123"' "…and a JSON string stays a string"
eq "$(notes new-1)" "first note" "--notes rides the create"
gc bd create "plain" -t task --json >/dev/null
eq "$(bstatus new-2)" "open" "a create with no --status is open"
eq "$(jq -c '.[] | select(.id == "new-2") | .metadata' "$STUB_STORE")" '{}' "…and carries no metadata"
if gc bd create "bad" --metadata 'not json' --json >/dev/null 2>&1; then bad "an unparseable --metadata was accepted"; else ok "an unparseable --metadata is refused"; fi
eq "$(jq 'length' "$STUB_STORE")" "2" "…and creates nothing"
STUB_DROP_KEYS="new-3:status,oid" gc bd create "partial" --metadata '{"task_kind":"review","oid":"x"}' --status=closed --json >/dev/null
eq "$(bstatus new-3)" "open" "STUB_DROP_KEYS naming the minted id drops the create's status"
eq "$(meta new-3 oid)" "<absent>" "…and the named metadata keys"
eq "$(meta new-3 task_kind)" "review" "…and lands the rest"
if STUB_CREATE_FAIL=1 gc bd create "refused" --json >/dev/null 2>&1; then bad "STUB_CREATE_FAIL did not refuse the create"; else ok "STUB_CREATE_FAIL refuses the create"; fi
eq "$(jq 'length' "$STUB_STORE")" "3" "…and creates nothing"
if STUB_CREATE_GARBAGE=1 gc bd create "lost" --json | jq -e . >/dev/null 2>&1; then bad "STUB_CREATE_GARBAGE answered parseable JSON"; else ok "STUB_CREATE_GARBAGE answers a reply no JSON reader parses"; fi
eq "$(jq -r '.[] | select(.id == "new-4") | .title' "$STUB_STORE")" "lost" "…while the create still lands"

# The gc bd update stub lands every flag of one call in one pass over the store:
# the sets in order (a later value for a key wins), the unsets, the assignee,
# the status, the appended note and the description. A value that parses as a
# JSON number, boolean or null is stored typed and anything else as raw text,
# as real bd stores them; a key or field STUB_DROP_KEYS names is left as it was
# while the rest of the same call still lands, and the bead itself is never
# lost, whichever fields the knob drops.
store '[{"id":"tk-u","status":"open","assignee":"","title":"u","notes":"first","description":"","metadata":{"keep":"k","gone":"g","typed":"old"}},{"id":"tk-v","status":"open","assignee":"","title":"v","notes":"","metadata":{}}]'
gc bd update tk-u --set-metadata typed=1 --set-metadata "eq=a=b" --set-metadata flag=true \
  --set-metadata typed=2.5 --set-metadata nul=null --set-metadata txt=" 007 " --unset-metadata gone \
  --assignee lx-one --status=in_progress --append-notes "second" --description "d1" --json >/dev/null
eq "$(jq -c '.[] | select(.id == "tk-u") | .metadata' "$STUB_STORE")" \
  '{"keep":"k","typed":2.5,"eq":"a=b","flag":true,"nul":null,"txt":" 007 "}' \
  "update: every set lands typed as bd types it, the later value of a repeated key wins, a value keeps its own = and the unset is gone"
eq "$(bassignee tk-u)" "lx-one" "update: the assignee rides the same call"
eq "$(bstatus tk-u)" "in_progress" "update: …and so does the status"
eq "$(notes tk-u)" $'first\nsecond' "update: a note is appended on its own line"
eq "$(jq -r '.[] | select(.id == "tk-u") | .description' "$STUB_STORE")" "d1" "update: …and the description lands"
eq "$(jq -c '.[] | select(.id == "tk-v")' "$STUB_STORE")" '{"id":"tk-v","status":"open","assignee":"","title":"v","notes":"","metadata":{}}' \
  "update: the other beads are untouched"
gc bd update tk-v --append-notes "only" >/dev/null
eq "$(notes tk-v)" "only" "update: the first note takes no leading newline"
STUB_DROP_KEYS="tk-u:status,typed,assignee" gc bd update tk-u --status=closed --set-metadata typed=9 --set-metadata other=o --assignee lx-two --unset-metadata keep >/dev/null
eq "$(bstatus tk-u)" "in_progress" "update: a dropped status leaves the bead as it was"
eq "$(meta tk-u typed)" "2.5" "update: …and a dropped metadata key keeps its old value"
eq "$(bassignee tk-u)" "lx-one" "update: …and a dropped assignee is not written"
eq "$(meta tk-u other)" "o" "update: …while the keys the knob does not name still land"
eq "$(meta tk-u keep)" "<absent>" "update: …including an unset"
eq "$(jq 'length' "$STUB_STORE")" "2" "update: no bead is lost to a dropped field"
gc bd update tk-missing --status=closed >/dev/null
eq "$(jq 'length' "$STUB_STORE")" "2" "update: an id the store does not hold changes nothing"

# The gc bd list stub answers its --metadata-field filters in the same pass as
# the rest of the query: a row must match every field, a value is compared as
# text (a stored number matches its spelling), and a field with no `=` matches
# nothing a store would hold.
store '[{"id":"l1","status":"open","title":"a","metadata":{"k":"v","n":1}},{"id":"l2","status":"open","title":"b","metadata":{"k":"v","n":2}},{"id":"l3","status":"closed","title":"c","metadata":{"k":"v","n":1}}]'
ids() { jq -r 'map(.id) | join(",")'; }
eq "$(gc bd list --metadata-field k=v --json | ids)" "l1,l2,l3" "list: one metadata field selects every row carrying it"
eq "$(gc bd list --metadata-field k=v --metadata-field n=1 --json | ids)" "l1,l3" "list: two fields both have to match"
eq "$(gc bd list --status=open --metadata-field n=1 --json | ids)" "l1" "list: …and the status filter applies with them"
eq "$(gc bd list --metadata-field=k=v --metadata-field n=3 --json | ids)" "" "list: a field no row matches selects nothing"
eq "$(gc bd list --metadata-field k --json | ids)" "" "list: a field without = selects nothing"

# The gc sling stub pours in one pass: the route key is retired and the
# execution route stamped, unless STUB_DROP_KEYS drops the stamp.
store '[{"id":"tk-s","status":"open","assignee":"","title":"s","notes":"","metadata":{"gc.routed_to":"pool"}}]'
gc sling pool tk-s --on mol-x >/dev/null
eq "$(meta tk-s gc.routed_to)" "<absent>" "sling: the route is retired"
eq "$(meta tk-s gc.execution_routed_to)" "pool" "sling: …and the execution route stamped"
store '[{"id":"tk-s","status":"open","assignee":"","title":"s","notes":"","metadata":{"gc.routed_to":"pool"}}]'
STUB_DROP_KEYS="tk-s:gc.execution_routed_to" gc sling pool tk-s --on mol-x >/dev/null
eq "$(meta tk-s gc.routed_to)" "<absent>" "sling: a dropped stamp still retires the route"
eq "$(meta tk-s gc.execution_routed_to)" "<absent>" "sling: …and leaves the stamp unwritten"

# STUB_ENFORCE_CLOSE_OWNER mirrors real bd's close-ownership check: `bd close`
# refuses a bead assigned to another actor unless --force is passed, an
# unassigned bead or the actor's own closes plainly, and `bd update
# --status=closed` never runs the check. A caller that drops its --force passes
# against a stub that refuses nothing, so the refusal is pinned here, and so is
# the default: with the knob unset any actor closes, as every other suite expects.
store '[{"id":"tk-held","status":"in_progress","assignee":"lx-sitting","title":"h","notes":"","metadata":{}},{"id":"tk-free","status":"open","assignee":"","title":"f","notes":"","metadata":{}},{"id":"tk-mine","status":"open","assignee":"rig/refinery","title":"m","notes":"","metadata":{}},{"id":"tk-upd","status":"in_progress","assignee":"lx-sitting","title":"u","notes":"","metadata":{}},{"id":"tk-off","status":"in_progress","assignee":"lx-sitting","title":"o","notes":"","metadata":{}}]'
as_refinery() { STUB_ENFORCE_CLOSE_OWNER=1 BEADS_ACTOR=rig/refinery gc bd "$@" >/dev/null 2>&1; }
as_refinery close tk-held --reason r; rc=$?
eq "$rc" "1" "close: a bead assigned to another actor is refused without --force"
eq "$(bstatus tk-held)" "in_progress" "...and is left as it was"
as_refinery close tk-held --reason r --force
eq "$(bstatus tk-held)" "closed" "close --force overrides the ownership check"
as_refinery close tk-free --reason r
eq "$(bstatus tk-free)" "closed" "close: an unassigned bead closes for any actor"
as_refinery close tk-mine --reason r
eq "$(bstatus tk-mine)" "closed" "close: the actor's own bead closes without --force"
as_refinery update tk-upd --status=closed
eq "$(bstatus tk-upd)" "closed" "update --status=closed never runs the close verb's ownership check"
gc bd close tk-off --reason r >/dev/null 2>&1
eq "$(bstatus tk-off)" "closed" "with the knob unset, a plain close lands whoever holds the bead"

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

# A GraphQL mutation names only a node id, as the real API takes it, and the gh
# stub writes the one PR fixture that holds the node. It starts as many jq
# processes with thirty PR fixtures written as with one, so a suite's mutations
# do not slow down as it adds PRs. A fixture whose text names the id without
# holding the node is passed over and left as it was. A request's -f variables
# reach the handler as written: quotes, an equals sign and non-ASCII text
# arrive whole, a trailing newline is dropped, and a name given twice keeps its
# last value.
gql_thread() { # <num>: a PR fixture whose one thread T-<num> holds comment NC-<num>
  printf '{"reviews":[],"threads":[{"id":"T-%s","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-%s","databaseId":1,"author":{"login":"op"},"body":"b","reactionGroups":[]}]}}],"issue_comments":[]}' "$1" "$1"
}
reactions() { jq -r '.threads[0].comments.nodes[0].reactionGroups | map(.content) | join(",")' "$GH_DIR/threads_$1.json"; }
REACT_Q='mutation($id:ID!,$c:ReactionContent!){addReaction(input:{subjectId:$id,content:$c}){clientMutationId}}'
JQ_REAL="$(command -v jq)"; mkdir -p "$TMP/jqcount"
printf '#!/bin/sh\necho x >> "%s"\nexec "%s" "$@"\n' "$TMP/jqcount/runs" "$JQ_REAL" > "$TMP/jqcount/jq"
chmod +x "$TMP/jqcount/jq"
jq_runs() { # <command>...: how many jq processes the command started
  : > "$TMP/jqcount/runs"
  PATH="$TMP/jqcount:$PATH" "$@" >/dev/null 2>&1
  wc -l < "$TMP/jqcount/runs" | tr -d ' '
}
gql_thread 50 > "$GH_DIR/threads_50.json"
one=$(jq_runs gh api graphql -f query="$REACT_Q" -f id=NC-50 -f c=EYES)
eq "$(reactions 50)" "EYES" "gh graphql: addReaction marks the node in the fixture that holds it"
for n in $(seq 51 79); do gql_thread "$n" > "$GH_DIR/threads_$n.json"; done
many=$(jq_runs gh api graphql -f query="$REACT_Q" -f id=NC-79 -f c=EYES)
eq "$(reactions 79)" "EYES" "gh graphql: …and finds it in the last of thirty fixtures"
eq "$many" "$one" "gh graphql: a mutation starts as many jq processes with thirty PR fixtures as with one"
eq "$(grep -l EYES "$GH_DIR"/threads_5[1-9].json "$GH_DIR"/threads_[67]?.json | wc -l | tr -d ' ')" "1" \
  "gh graphql: …and writes no fixture but the one holding the node"
gql_thread 81 > "$GH_DIR/threads_81.json"
gql_thread 80 | jq -c '.threads[0].comments.nodes[0].replyTo = "NC-81"' > "$GH_DIR/threads_80.json"
cp "$GH_DIR/threads_80.json" "$TMP/threads_80.before"
gh api graphql -f query="$REACT_Q" -f id=NC-81 -f c=EYES >/dev/null
eq "$(reactions 81)" "EYES" "gh graphql: a fixture that only names the id does not take the node's write"
if cmp -s "$GH_DIR/threads_80.json" "$TMP/threads_80.before"; then ok "gh graphql: …and is left as it was"; else bad "gh graphql: the fixture naming NC-81 was rewritten"; fi
gh api graphql -f query="$REACT_Q" -f id=NC-81 -f c=HEART -f c=$'a "quoted" = value, ✅\nline two\n' >/dev/null
eq "$(jq -c '.threads[0].comments.nodes[0].reactionGroups | map(.content)' "$GH_DIR/threads_81.json")" '["EYES","a \"quoted\" = value, ✅\nline two"]' \
  "gh graphql: a variable arrives whole, the last value given for its name, its trailing newline dropped"

# The gc bd dep stub holds one edge per (issue, depends_on) pair, as real bd
# does. A second type on a taken pair is refused with exit 1 and writes nothing,
# whichever form wrote either edge. The same type again is a no-op that exits 0,
# and the reversed pair is a different pair. A stub that appends every edge
# accepts two edges on one pair, a state no real store can hold, so a writer
# that needs both passes here and fails against bd; the rule is pinned here.
: > "$STUB_DEPS"
gc bd dep add tk-kd tk-blk --type discovered-from
if err=$(gc bd dep tk-blk --blocks tk-kd 2>&1); then
  bad "a blocks edge on a pair that already carries discovered-from was accepted"
else
  ok "a blocks edge on a pair that already carries discovered-from is refused"
fi
has "$err" "dependency tk-kd -> tk-blk already exists with type \"discovered-from\" (requested \"blocks\")" "...with bd's already-exists error naming the pair and both types"
eq "$(cat "$STUB_DEPS")" "tk-kd|discovered-from|tk-blk" "...and the refused edge writes nothing"
: > "$STUB_DEPS"
gc bd dep tk-blk --blocks tk-kd
if gc bd dep add tk-kd tk-blk --type discovered-from 2>/dev/null; then
  bad "a discovered-from edge on a pair a blocks edge holds was accepted"
else
  ok "a discovered-from edge on a pair a blocks edge holds is refused (dep add form)"
fi
eq "$(cat "$STUB_DEPS")" "tk-blk|blocks|tk-kd" "...and the refused edge writes nothing"
if gc bd dep add tk-kd tk-blk --type blocks; then ok "re-adding a pair with the type it carries exits 0"; else bad "re-adding a pair with the type it carries failed"; fi
eq "$(grep -c . "$STUB_DEPS")" "1" "...and leaves one edge on the pair"
if gc bd dep add tk-blk tk-kd --type related; then ok "the reversed pair is a different pair: a related edge lands beside the blocks edge"; else bad "the reversed pair was refused as if it were the same pair"; fi
has "$(cat "$STUB_DEPS")" "tk-blk|related|tk-kd" "...and is stored"

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

# The gc bd update stub replaces a description the way real bd does, under
# either spelling of the flag, and leaves the rest of the bead as it was.
store '[{"id":"tk-desc","status":"open","assignee":"","title":"d","description":"first","notes":"n","metadata":{"k":"v"}}]'
gc bd update tk-desc --description "second, with a space" >/dev/null
eq "$(jq -r '.[0].description' "$STUB_STORE")" "second, with a space" "update --description replaces the description"
gc bd update tk-desc -d third >/dev/null
eq "$(jq -r '.[0].description' "$STUB_STORE")" "third" "...and -d is the same flag"
eq "$(jq -c '.[0] | [.notes, .metadata.k, .status]' "$STUB_STORE")" '["n","v","open"]' "...leaving notes, metadata and status alone"

# The gc bd update stub lands a whole write in one jq, and the gc bd list stub
# answers a query and all of its --metadata-field filters in one, however many
# flags the call carries. Each counted call is read back, so a call that stopped
# before its jq cannot pass the count.
store '[{"id":"tk-one","status":"open","assignee":"a","title":"o","notes":"n","metadata":{"old":"x","gone":"y"}},
        {"id":"tk-two","status":"open","assignee":"","title":"t","notes":"","metadata":{"lane":"c","stage":"1"}}]'
one=$(jq_runs gc bd update tk-one --set-metadata k1=1)
many=$(jq_runs gc bd update tk-one --set-metadata k1=2 --set-metadata k2=b --set-metadata k1=3 \
  --unset-metadata gone --unset-metadata k2 --assignee=bob --status=in_progress --append-notes more --description d)
eq "$many" "$one" "update: a write with nine flags starts as many jq processes as one with a single key"
eq "$(jq -c '.[] | select(.id == "tk-one") | [.metadata, .assignee, .status, .notes, .description]' "$STUB_STORE")" \
  '[{"old":"x","k1":3},"bob","in_progress","n\nmore","d"]' "update: …and every flag of that write lands"
one=$(jq_runs gc bd list --json)
many=$(jq_runs gc bd list --metadata-field lane=c --metadata-field stage=1 --metadata-field=old= --status=open --json)
eq "$many" "$one" "list: a read with three --metadata-field filters starts as many jq processes as one with none"
eq "$(gc bd list --metadata-field lane=c --metadata-field stage=1 --metadata-field=old= --status=open --json | jq -r 'map(.id) | join(",")')" "tk-two" \
  "list: …and that read answers with the one bead every filter matches"

# part: tools/run-tests.sh runs a suite with parts once per part, exporting the
# run's part and every declared one. Each probe runs in a subshell, so the
# failure an undeclared name records is read back from its output rather than
# counted against this suite.
out=$(unset RUN_TESTS_PART RUN_TESTS_PARTS; part alpha; echo "alpha=$?"; part beta; echo "beta=$?")
has "$out" "alpha=0" "part: run directly, every part runs"
has "$out" "beta=0" "…the second part too"
out=$(export RUN_TESTS_PART=beta RUN_TESTS_PARTS="alpha beta"; base=$FAIL
      part alpha; echo "alpha=$?"; part beta; echo "beta=$? declared-fails=$((FAIL - base))"
      part gamma; echo "gamma=$? undeclared-fails=$((FAIL - base))")
has "$out" "alpha=1" "part: under run-tests a run skips every other part"
has "$out" "beta=0 declared-fails=0" "…executes its own, and records no failure for a declared name"
has "$out" "gamma=1 undeclared-fails=1" "…while a group under a name the header never declared fails the run"
has "$out" "part 'gamma' is not declared" "…naming that group"
out=$(export RUN_TESTS_PART=beta; unset RUN_TESTS_PARTS; base=$FAIL
      part gamma; echo "gamma=$? fails=$((FAIL - base))"; part beta; echo "beta=$?")
has "$out" "gamma=1 fails=0" "part: one part picked by hand, with no declared list, skips the others without failing"
has "$out" "beta=0" "…and runs the part it names"

# tomllib_python: each probe's PATH holds stand-in interpreters and a directory
# with only the grep and sort the search runs, so no real Python on the host is
# found. A stand-in answers the two questions the search asks: whether tomllib
# imports, and which version it is.
PYT="$TMP/python"
mkdir -p "$PYT/tools" "$PYT/new" "$PYT/old" "$PYT/versioned" "$PYT/oldversioned"
ln -s "$(command -v grep)" "$(command -v sort)" "$PYT/tools/"
fake_python() { # <path> <version> <yes|no: tomllib imports>
  local rc=1
  [ "$3" = yes ] && rc=0
  printf '#!/bin/sh\ncase "$2" in\n  *tomllib*) exit %s ;;\n  *platform*) echo %s ;;\nesac\n' "$rc" "$2" > "$1"
  chmod +x "$1"
}
fake_python "$PYT/new/python3" 3.12.3 yes
fake_python "$PYT/old/python3" 3.9.6 no
fake_python "$PYT/versioned/python3.11" 3.11.9 yes
fake_python "$PYT/versioned/python3.13" 3.13.1 yes
fake_python "$PYT/versioned/python3.14-config" 3.14.0 yes
fake_python "$PYT/oldversioned/python3.10" 3.10.4 no
out=$(PATH="$PYT/new:$PYT/versioned:$PYT/tools"; tomllib_python); rc=$?
eq "$rc" "0" "tomllib_python: a python3 with tomllib is found"
eq "$out" "$PYT/new/python3" "…and printed by its path, ahead of any versioned name"
out=$(PATH="$PYT/old:$PYT/versioned:$PYT/tools"; tomllib_python); rc=$?
eq "$rc" "0" "tomllib_python: a python3 without tomllib is passed over for a versioned one that has it"
eq "$out" "$PYT/versioned/python3.13" "…the newest python3.N, and never a name such as python3.14-config"
out=$(PATH="$PYT/old:$PYT/oldversioned:$PYT/tools"; tomllib_python); rc=$?
eq "$rc" "1" "tomllib_python: with no Python that has tomllib, it returns 1"
eq "$out" "tomllib needs Python 3.11 or newer, and PATH has $PYT/old/python3 3.9.6, $PYT/oldversioned/python3.10 3.10.4" \
  "…and names every Python it found, with its version"
# shellcheck disable=SC2123  # a PATH with no Python on it is the case under test
out=$(PATH="$PYT/tools"; tomllib_python); rc=$?
eq "$rc" "1" "tomllib_python: with no Python at all, it returns 1"
eq "$out" "tomllib needs Python 3.11 or newer, and PATH has no python3" "…and says there is none"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
