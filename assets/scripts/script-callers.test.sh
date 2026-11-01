#!/usr/bin/env bash
# Hermetic test for script-callers.sh, the open steps that call a pack script
# and the merge gate's question about a change that removes one. Proves:
#   - a census reads every store the city's rig list names, each pinned by
#     --db, for beads carrying gc.step_ref in every status but closed, and
#     lists a step only when its text names the script whole: no letter,
#     digit, dot, dash or underscore on either side;
#   - --check-merge takes the files the change removes from assets/scripts/
#     and from a sub-pack's packs/<name>/assets/scripts/, a rename's old path
#     included, that the base still carries, and leaves tests out;
#   - a removed script that a formula at the base or at the head still names, a
#     sub-pack's formula included, exits 1 before any store is read, since no
#     wait clears it;
#   - a removed script only the checkout's HEAD still names exits 4 before any
#     store is read, since its fast-forward clears it, and a checkout at the base
#     is read once;
#   - a removed script that only open steps call exits 3, and one nothing
#     calls exits 0;
#   - one caller in a run parked behind a gate a person holds, a human gate or a
#     park with no await type, exits 5 and names the gate, whichever step of the
#     run the edge sits on; a timer or GitHub gate, a closed gate or a blocker
#     that is no gate parks nothing, and only a store holding a caller has its
#     gates read;
#   - a repository is read from its top, so a directory below it gets the same
#     answers;
#   - it exits 2 when it decides nothing: a usage error, a revision or
#     repository it cannot read, a list of deletions or formulas git cannot give,
#     no rig list, or a store that does not answer, including about its gates,
#     or holds a row it cannot read;
#   - it exits 2 when a loop could not read its whole list: the temp file cannot
#     be created or written, or the loop read fewer lines than the list holds.
#     No failure of a list or a count under a loop reads as an all-clear.
# Runs against a fake gc that serves the rig list and each store's steps from
# JSON files, with real git. No live city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/script-callers.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-script-callers-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub git out
PASS=0; FAIL=0

unset "${!GC_@}" "${!BEADS_@}" "${!GIT_@}" 2>/dev/null || true
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
git config --file "$GIT_CONFIG_GLOBAL" user.name T
git config --file "$GIT_CONFIG_GLOBAL" user.email t@e.com
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false

BIN="$TMP/bin"; mkdir -p "$BIN"
export PATH="$BIN:$PATH"
export STUB_RIGS="$TMP/rigs.json" STUB_GC_LOG="$TMP/gc.log"
STORES="$TMP/stores"
REPO="$TMP/repo"

# --- fake gc: the rig list, and each store's steps --------------------------
# bd list honours the filters a census asks for, so a step the script lists
# had to pass them. The whole-name rule is the script's own.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-}" = rig ] && [ "${2:-}" = list ]; then
  [ "${STUB_RIGS_RC:-0}" = 0 ] || { echo "the store did not answer" >&2; exit "$STUB_RIGS_RC"; }
  cat "${STUB_RIGS:?}"; exit 0
fi
if [ "${1:-}" = bd ] && [ "${2:-}" = list ]; then
  shift 2
  db=""; statuses=""; key=""; type=""; gates_shown=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --db) db="$2"; shift 2 ;;
      --status) statuses="$2"; shift 2 ;;
      --has-metadata-key) key="$2"; shift 2 ;;
      --type) type="$2"; shift 2 ;;
      --include-gates) gates_shown=1; shift ;;
      *) shift ;;
    esac
  done
  [ "$db" != "${STUB_BD_FAIL_DB:-}" ] || { echo "Error: database unavailable" >&2; exit 1; }
  [ -f "$db/steps.json" ] || { echo "Error: no database at $db" >&2; exit 1; }
  echo "gc bd: answering from the rig \"workshop\" store"
  # bd list hides gates unless it is told to show them.
  if [ "$type" = gate ]; then
    [ -n "$gates_shown" ] || { echo '[]'; exit 0; }
    [ "$db" != "${STUB_GATES_FAIL_DB:-}" ] || { echo "Error: gates unavailable" >&2; exit 1; }
    [ -f "$db/gates.json" ] || { echo '[]'; exit 0; }
    jq -c --arg s "$statuses" '[.[] | select(.status as $st | ($s | split(",")) | index($st))]' "$db/gates.json"
    exit 0
  fi
  jq -c --arg s "$statuses" --arg k "$key" '[.[]
    | select(.status as $st | ($s | split(",")) | index($st))
    | select($k == "" or (.metadata | has($k)))]' "$db/steps.json"
  exit 0
fi
echo "fake gc: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$BIN/gc"

# The city: an HQ and two rigs, each with a store of its own.
cat > "$STUB_RIGS" <<JSON
{"rigs":[
  {"name":"harbor","path":"$STORES/harbor","prefix":"hb","hq":true},
  {"name":"workshop","path":"$STORES/workshop","prefix":"ws"},
  {"name":"lantern","path":"$STORES/lantern","prefix":"ln"}
]}
JSON
mkdir -p "$STORES/harbor/.beads" "$STORES/workshop/.beads" "$STORES/lantern/.beads"
step() { # id step_ref status assignee root description
  jq -nc --arg id "$1" --arg ref "$2" --arg st "$3" --arg as "$4" --arg root "$5" --arg d "$6" \
    '{id: $id, status: $st, assignee: $as, description: $d, metadata: {"gc.step_ref": $ref, "gc.root_bead_id": $root}}'
}
callers_on() {
  printf '[%s]' "$(step hb-s1 mol-k.probe open "" hb-r1 'PROBE="$c/assets/scripts/sub-tool.sh"')" \
    > "$STORES/harbor/.beads/steps.json"
  printf '[%s,%s,%s,%s,%s]' \
    "$(step ws-s1 mol-a.load open "" ws-r1 "$(printf 'Run:\n"$SCRIPTS/old-tool.sh" --flag')")" \
    "$(step ws-s2 mol-a.submit in_progress worker-1 ws-r1 'x=$(gc kit scripts-dir)/old-tool.sh')" \
    "$(step ws-s3 mol-a.done closed "" ws-r0 '"$SCRIPTS/old-tool.sh"')" \
    '{"id":"ws-n1","status":"open","assignee":"","description":"old-tool.sh is named here","metadata":{}}' \
    "$(step ws-s4 mol-a.load open "" ws-r2 'bold-tool.sh, old-tool.sh.bak and old-tool.shx')" \
    > "$STORES/workshop/.beads/steps.json"
  printf '[%s]' "$(step ln-s1 mol-b.check blocked "" ln-r1 "$(printf 'first\nold-tool.sh runs here')")" \
    > "$STORES/lantern/.beads/steps.json"
}
callers_off() {
  local s
  for s in harbor workshop lantern; do printf '[]' > "$STORES/$s/.beads/steps.json"; done
}
gate() { # id status [await_type] — bd leaves an empty await type out of the row
  jq -nc --arg id "$1" --arg st "$2" --arg a "${3:-}" \
    '{id: $id, status: $st, issue_type: "gate", title: "t", metadata: {}} + (if $a == "" then {} else {await_type: $a} end)'
}
gates_off() {
  local s
  for s in harbor workshop lantern; do rm -f "$STORES/$s/.beads/gates.json"; done
}
# The workshop's two runs: ws-r1, whose first step waits on <blocker> and whose
# second waits on the first, and ws-r2, which nothing holds. Each step names the
# script, and the edges are in the raw shape a list row carries.
parked_on() { # blocker
  local name='old-tool.sh'
  jq -nc --arg b "$1" --arg d "\"\$SCRIPTS/$name\"" '[
    {id: "ws-a", status: "open", assignee: "", description: $d, metadata: {"gc.step_ref": "mol-a.load", "gc.root_bead_id": "ws-r1"},
     dependencies: [{issue_id: "ws-a", depends_on_id: $b, type: "blocks"}, {issue_id: "ws-a", depends_on_id: "ws-r1", type: "tracks"}]},
    {id: "ws-b", status: "open", assignee: "", description: $d, metadata: {"gc.step_ref": "mol-a.submit", "gc.root_bead_id": "ws-r1"},
     dependencies: [{issue_id: "ws-b", depends_on_id: "ws-a", type: "blocks"}]},
    {id: "ws-c", status: "open", assignee: "", description: $d, metadata: {"gc.step_ref": "mol-a.load", "gc.root_bead_id": "ws-r2"},
     dependencies: []}
  ]' > "$STORES/workshop/.beads/steps.json"
}
run() { out=$("$SUT" "$@" 2>&1); rc=$?; }

echo "# census"
callers_on; : > "$STUB_GC_LOG"
run old-tool.sh
eq "$rc" "3" "open steps that call the script exit 3"
has "$out" "old-tool.sh: step ws-s1 (mol-a.load, open, unassigned) in run ws-r1, store of rig workshop" \
  "a step that calls it through \$SCRIPTS is listed with its step ref, status, run and store"
has "$out" "old-tool.sh: step ws-s2 (mol-a.submit, in_progress, worker-1) in run ws-r1, store of rig workshop" \
  "...one that calls it through scripts-dir, with its assignee"
has "$out" "old-tool.sh: step ln-s1 (mol-b.check, blocked, unassigned) in run ln-r1, store of rig lantern" \
  "...and a blocked step in another rig's store, its name at the start of a line"
hasnt "$out" "ws-s3" "a closed step is not a caller"
hasnt "$out" "ws-n1" "a bead with no gc.step_ref is not a caller"
hasnt "$out" "ws-s4" "a longer name that holds the script's name is not the script"
eq "$(printf '%s\n' "$out" | head -1)" "3 open step(s) call old-tool.sh" "...the count first, so a log that keeps only the head keeps it"
log=$(cat "$STUB_GC_LOG")
has "$log" "bd list --db $STORES/harbor/.beads --has-metadata-key gc.step_ref --status open,in_progress,blocked,deferred,hooked,pinned --limit=0 --json" \
  "each store is read pinned by --db, for steps in every status but closed"
has "$log" "bd list --db $STORES/lantern/.beads" "...the last rig's store included"

: > "$STUB_GC_LOG"
run old-tool.sh sub-tool.sh
eq "$rc" "3" "steps that call either of two scripts exit 3"
eq "$(printf '%s\n' "$out" | head -1)" "4 open step(s) call old-tool.sh sub-tool.sh" "...counting the steps of both"
has "$out" "sub-tool.sh: step hb-s1 (mol-k.probe, open, unassigned) in run hb-r1, store of rig harbor" "...listing the second script's caller"
has "$out" "old-tool.sh: step ws-s1 (mol-a.load, open, unassigned) in run ws-r1, store of rig workshop" "...and the first's"
eq "$(grep -c '^bd list .*--has-metadata-key gc.step_ref' "$STUB_GC_LOG")" "3" "...reading each of the three stores' steps once, however many scripts are asked about"
eq "$(grep -c -e '--type gate' "$STUB_GC_LOG")" "3" "...and each store's gates once, each holding a caller"

callers_off
run old-tool.sh keep.sh
eq "$rc" "0" "no caller exits 0"
has "$out" "no open step calls old-tool.sh keep.sh" "...and says which scripts it asked about"

callers_on
export STUB_BD_FAIL_DB="$STORES/lantern/.beads"
run old-tool.sh
eq "$rc" "2" "a store that does not answer decides nothing"
has "$out" "cannot read the open steps in the store of rig 'lantern' ($STORES/lantern/.beads); nothing was decided" \
  "...and names the store"
unset STUB_BD_FAIL_DB

callers_off
printf '[{"id":"hb-bad","status":"open","assignee":"","description":7,"metadata":{"gc.step_ref":"mol-k.bad"}}]' \
  > "$STORES/harbor/.beads/steps.json"
run old-tool.sh
eq "$rc" "2" "a step row the census cannot read decides nothing"
has "$out" "cannot read the open steps in the store of rig 'harbor'" "...and names the store"
hasnt "$out" "no open step calls" "...with no all-clear"
callers_on

export STUB_RIGS_RC=1
run old-tool.sh
eq "$rc" "2" "an unreadable rig list decides nothing"
has "$out" "cannot read the city's rigs" "...and says so"
unset STUB_RIGS_RC
cp "$STUB_RIGS" "$TMP/rigs.keep"; printf '{"rigs":[]}' > "$STUB_RIGS"
run old-tool.sh
eq "$rc" "2" "a city that lists no rig decides nothing, since no store was read"
has "$out" "the city lists no rig" "...and says so"
printf '{"rigs":[{"name":"harbor","path":"%s"},{"name":"lantern"}]}' "$STORES/harbor" > "$STUB_RIGS"
callers_off
run old-tool.sh
eq "$rc" "2" "a rig the list gives no path for decides nothing, since its store was not read"
callers_on
cp "$TMP/rigs.keep" "$STUB_RIGS"

echo "# a run a person's gate parks"
gates_off; callers_off
printf '[%s]' "$(gate ws-g open)" > "$STORES/workshop/.beads/gates.json"
parked_on ws-g
: > "$STUB_GC_LOG"
run old-tool.sh
eq "$rc" "5" "a caller in a run a park holds exits 5, a park carrying no await type"
eq "$(printf '%s\n' "$out" | head -1)" "3 open step(s) call old-tool.sh, and 2 of them sit in runs a person's gate parks (ws-g)" \
  "...counting the parked ones, naming the gate"
has "$out" "old-tool.sh: step ws-a (mol-a.load, open, unassigned) in run ws-r1, store of rig workshop, parked behind ws-g" \
  "...marking the step the edge sits on"
has "$out" "old-tool.sh: step ws-b (mol-a.submit, open, unassigned) in run ws-r1, store of rig workshop, parked behind ws-g" \
  "...and a later step of that run, which waits only on the step before it"
has "$out" "old-tool.sh: step ws-c (mol-a.load, open, unassigned) in run ws-r2, store of rig workshop" "...and listing the run nothing parks"
hasnt "$out" "in run ws-r2, store of rig workshop, parked" "...unmarked"
eq "$(grep -c -e '--type gate --include-gates' "$STUB_GC_LOG")" "1" "only the store holding a caller has its gates read"
has "$(cat "$STUB_GC_LOG")" "bd list --db $STORES/workshop/.beads --type gate --include-gates --status open,in_progress,blocked,deferred,hooked,pinned --limit=0 --json" \
  "...pinned by --db, in every status but closed"

printf '[%s]' "$(gate ws-g open human)" > "$STORES/workshop/.beads/gates.json"
run old-tool.sh
eq "$rc" "5" "a human gate parks a run"
printf '[%s]' "$(gate ws-g open bead)" > "$STORES/workshop/.beads/gates.json"
run old-tool.sh
eq "$rc" "5" "...and so does a gate of a type the city's sweep does not close"

for await in timer gh:run gh:pr; do
  printf '[%s]' "$(gate ws-g open "$await")" > "$STORES/workshop/.beads/gates.json"
  run old-tool.sh
  eq "$rc" "3" "a $await gate closes on its own and parks nothing"
  hasnt "$out" "parked behind" "...and no step is marked"
done

printf '[%s]' "$(gate ws-g closed human)" > "$STORES/workshop/.beads/gates.json"
run old-tool.sh
eq "$rc" "3" "a closed gate parks nothing"
rm -f "$STORES/workshop/.beads/gates.json"
parked_on ws-task
run old-tool.sh
eq "$rc" "3" "a blocker that is no gate parks nothing, since its work can end on its own"

printf '[%s,%s]' "$(gate ws-g open)" "$(gate ws-h open human)" > "$STORES/workshop/.beads/gates.json"
jq -c 'map(if .id == "ws-c" then .dependencies = [{issue_id: "ws-c", depends_on_id: "ws-h", type: "blocks"}] elif .id == "ws-a" then .dependencies[0].depends_on_id = "ws-g" else . end)' \
  "$STORES/workshop/.beads/steps.json" > "$TMP/two-gates.json"
cp "$TMP/two-gates.json" "$STORES/workshop/.beads/steps.json"
run old-tool.sh keep.sh
eq "$(printf '%s\n' "$out" | head -1)" "3 open step(s) call old-tool.sh keep.sh, and 3 of them sit in runs a person's gate parks (ws-g, ws-h)" \
  "two gates parking two runs are both named"
printf '[%s]' "$(gate lantern-g open)" > "$STORES/lantern/.beads/gates.json"
jq -nc '[{id: "ln-a", status: "open", assignee: "", description: "old-tool.sh", metadata: {"gc.step_ref": "mol-b.load", "gc.root_bead_id": "ln-r1"},
          dependencies: [{issue_id: "ln-a", depends_on_id: "lantern-g", type: "blocks"}]}]' > "$STORES/lantern/.beads/steps.json"
run old-tool.sh
has "$(printf '%s\n' "$out" | head -1)" "(ws-g, ws-h, lantern-g)" "...and so are gates in other stores, each once"
jq -nc '[{id: "ln-a", status: "open", assignee: "", description: "old-tool.sh keep.sh", metadata: {"gc.step_ref": "mol-b.load", "gc.root_bead_id": "ln-r1"},
          dependencies: [{issue_id: "ln-a", depends_on_id: "lantern-g", type: "blocks"}]}]' > "$STORES/lantern/.beads/steps.json"
: > "$STUB_GC_LOG"
run old-tool.sh keep.sh
eq "$(printf '%s\n' "$out" | head -1)" "5 open step(s) call old-tool.sh keep.sh, and 5 of them sit in runs a person's gate parks (ws-g, ws-h, lantern-g)" \
  "...once each though two scripts' callers wait on it"
eq "$(grep -c -e "--db $STORES/lantern/.beads --type gate" "$STUB_GC_LOG")" "1" "...and a store holding callers of two scripts has its gates read once"
gates_off

# A step with no run of its own is judged by its own edge.
printf '[%s]' "$(gate ws-g open)" > "$STORES/workshop/.beads/gates.json"
jq -nc '[{id: "ws-x", status: "open", assignee: "", description: "old-tool.sh", metadata: {"gc.step_ref": "mol-a.load"},
          dependencies: [{issue_id: "ws-x", depends_on_id: "ws-g", type: "blocks"}]}]' > "$STORES/workshop/.beads/steps.json"
callers_off_but_workshop() { printf '[]' > "$STORES/harbor/.beads/steps.json"; printf '[]' > "$STORES/lantern/.beads/steps.json"; }
callers_off_but_workshop
run old-tool.sh
eq "$rc" "5" "a step that names no run is parked by its own edge"
has "$out" "step ws-x (mol-a.load, open, unassigned) in run ?, store of rig workshop, parked behind ws-g" "...and says it names no run"

parked_on ws-g
export STUB_GATES_FAIL_DB="$STORES/workshop/.beads"
run old-tool.sh
eq "$rc" "2" "a store whose gates cannot be read decides nothing"
has "$out" "cannot read the gates in the store of rig 'workshop' ($STORES/workshop/.beads); nothing was decided" "...and names the store"
hasnt "$out" "open step(s) call" "...with no count that reads as an answer"
printf '[]' > "$STORES/workshop/.beads/steps.json"
run old-tool.sh
eq "$rc" "0" "a store holding no caller is not asked about its gates, so its failure holds nothing"
unset STUB_GATES_FAIL_DB

printf '[{"id":"ws-g","status":"open","await_type":7}]' > "$STORES/workshop/.beads/gates.json"
parked_on ws-g
jq -c 'map(.dependencies = 7)' "$STORES/workshop/.beads/steps.json" > "$TMP/bad-edges.json"
cp "$TMP/bad-edges.json" "$STORES/workshop/.beads/steps.json"
run old-tool.sh
eq "$rc" "2" "a step's edges it cannot read decide nothing"
has "$out" "cannot read the gates in the store of rig 'workshop'" "...and name the store"
gates_off; callers_on

echo "# usage"
run; eq "$rc" "2" "no script and no --check-merge is a usage error"
run assets/scripts/old-tool.sh; eq "$rc" "2" "a path is not a script's file name"
run --frobnicate; eq "$rc" "2" "an unknown option is a usage error"
run --check-merge main; eq "$rc" "2" "--check-merge needs two revisions"
run --check-merge main main old-tool.sh; eq "$rc" "2" "--check-merge takes no script names"

echo "# --check-merge"
G() { git -C "$REPO" "$@" >/dev/null 2>&1 || { echo "setup failed: git $*" >&2; exit 1; }; }
put() { mkdir -p "$(dirname "$REPO/$1")"; printf '%s\n' "$2" > "$REPO/$1"; }
git init -q "$REPO"
put assets/scripts/old-tool.sh '#!/bin/sh'
put assets/scripts/keep.sh '#!/bin/sh'
put assets/scripts/old-tool.test.sh '#!/bin/sh'
put packs/sub/assets/scripts/sub-tool.sh '#!/bin/sh'
put packs/sub/assets/scripts/sub-tool.test.sh '#!/bin/sh'
put packs/sub/docs/notes.md 'how sub-tool.sh runs'
put formulas/mol-a.toml 'run = "$SCRIPTS/keep.sh"'
put formulas/mol-b.toml 'run = "$SCRIPTS/old-tool.sh"'
put docs/notes.md 'old-tool.sh is documented here'
G add -A; G commit -q -m c0
# One change stops naming the script and removes it.
G checkout -q -b same-change
G rm -q assets/scripts/old-tool.sh
put formulas/mol-b.toml 'run = "$SCRIPTS/keep.sh"'
G commit -qam same-change
# main stops naming it first; its text still holds a longer name.
G checkout -q main
put formulas/mol-b.toml 'run = "$SCRIPTS/keep.sh"  # not bold-tool.sh'
G commit -qam stop-naming
G checkout -q -b delete; G rm -q assets/scripts/old-tool.sh; G commit -qm delete
G checkout -q main; G checkout -q -b head-names
G rm -q assets/scripts/old-tool.sh
put formulas/mol-c.toml 'run = "$SCRIPTS/old-tool.sh"'
G add -A; G commit -qm head-names
G checkout -q main; G checkout -q -b tests-only
G rm -q assets/scripts/old-tool.test.sh packs/sub/assets/scripts/sub-tool.test.sh; G commit -qm tests-only
G checkout -q main; G checkout -q -b rename; G mv assets/scripts/old-tool.sh assets/scripts/new-tool.sh; G commit -qm rename
G checkout -q main; G checkout -q -b edit-only; put assets/scripts/keep.sh '#!/bin/sh
true'; G commit -qam edit-only
G checkout -q main; G checkout -q -b drop-keep; G rm -q assets/scripts/keep.sh; G commit -qm drop-keep
G checkout -q main; G checkout -q -b subpack
put packs/sub/formulas/mol-s.toml 'run = "$SCRIPTS/old-tool.sh"'
G add -A; G commit -qm subpack
G checkout -q -b subpack-delete; G rm -q assets/scripts/old-tool.sh; G commit -qm subpack-delete
G checkout -q main; G checkout -q -b main-dropped; G rm -q assets/scripts/keep.sh; G commit -qm main-dropped
G checkout -q main; G checkout -q -b sub-delete; G rm -q packs/sub/assets/scripts/sub-tool.sh; G commit -qm sub-delete
G checkout -q main; G checkout -q -b sub-doc-drop; G rm -q packs/sub/docs/notes.md; G commit -qm sub-doc-drop
G checkout -q main; G checkout -q -b sub-named
G rm -q packs/sub/assets/scripts/sub-tool.sh
put packs/sub/formulas/mol-t.toml 'run = "$PACK/assets/scripts/sub-tool.sh"'
G add -A; G commit -qm sub-named
# More than 64 KiB of removed paths, the size at which bash backs a here-string
# with a temp file. All but one are tests, so the census asks about one script.
G checkout -q main; G checkout -q -b long-base
LONG_NAME=$(printf '%0220d' 0)
for i in $(seq 1 300); do : > "$REPO/assets/scripts/$i-$LONG_NAME.test.sh"; done
G add -A; G commit -qm long-base
G checkout -q -b long-delete
G rm -q 'assets/scripts/*0.test.sh' assets/scripts/old-tool.sh; G commit -qm long-delete
G checkout -q main
# A history of its own, which shares no merge base with main.
G checkout -q --orphan unrelated; G commit -qm unrelated
G checkout -q main

callers_on; : > "$STUB_GC_LOG"
run --root "$REPO" --check-merge main edit-only
eq "$rc" "0" "a change that removes no script passes"
has "$out" "the merge removes no pack script" "...and says so"
eq "$(wc -c < "$STUB_GC_LOG" | tr -d ' ')" "0" "...without reading a store"

run --root "$REPO" --check-merge main tests-only
eq "$rc" "0" "removing a test, the pack's or a sub-pack's, is not removing a script"
has "$out" "the merge removes no pack script" "...so nothing is asked about it"

run --root "$REPO" --check-merge main-dropped drop-keep
eq "$rc" "0" "a script the base no longer carries is not the change's to remove"

: > "$STUB_GC_LOG"
run --root "$REPO" --check-merge main~1 same-change
eq "$rc" "1" "removing a script a formula at the base still names exits 1"
has "$out" "assets/scripts/old-tool.sh: the merge removes it, and formulas/mol-b.toml at the base (main~1) still names it" \
  "...naming the formula and the side"
has "$(printf '%s\n' "$out" | head -1)" "1 formula file(s) name a script the merge removes." "...under a headline with the count"
has "$(printf '%s\n' "$out" | head -1)" "Keep a file at each such path, a hand-off to what replaces it" "...and the remedy"
hasnt "$out" "docs/notes.md" "a document that names it is not a formula"
eq "$(wc -c < "$STUB_GC_LOG" | tr -d ' ')" "0" "...decided before any store is read, since no wait clears it"

run --root "$REPO" --check-merge main head-names
eq "$rc" "1" "removing a script a formula at the head names exits 1"
has "$out" "assets/scripts/old-tool.sh: the merge removes it, and formulas/mol-c.toml at the head (head-names) still names it" \
  "...naming the head's formula"

run --root "$REPO" --check-merge subpack subpack-delete
eq "$rc" "1" "a sub-pack's formula counts"
has "$out" "packs/sub/formulas/mol-s.toml at the base (subpack) still names it" "...and is named"

: > "$STUB_GC_LOG"
run --root "$REPO" --check-merge main delete
eq "$rc" "3" "removing a script only open steps call exits 3"
has "$out" "old-tool.sh: step ws-s1 (mol-a.load, open, unassigned) in run ws-r1, store of rig workshop" "...listing each caller"
has "$(printf '%s\n' "$out" | head -1)" "3 open step(s) call a script the merge removes (assets/scripts/old-tool.sh)" "...under a headline with the count"

# One parked caller among moving ones is a person's to end.
printf '[%s]' "$(gate ws-g open)" > "$STORES/workshop/.beads/gates.json"
parked_on ws-g
run --root "$REPO" --check-merge main delete
eq "$rc" "5" "removing a script a parked run calls exits 5, though other callers are moving"
first=$(printf '%s\n' "$out" | head -1)
has "$first" "(assets/scripts/old-tool.sh), and 2 of them sit in runs a person's gate parks (ws-g)." "...naming the gate on the first line, which the merge's reason keeps"
has "$first" "Release each gate or cancel each parked run, and the merge goes on." "...and what ends the wait"
has "$out" "in run ws-r1, store of rig workshop, parked behind ws-g" "...listing each caller"
gates_off; callers_on

run --root "$REPO" --check-merge main rename
eq "$rc" "3" "a rename removes the old path"
has "$out" "(assets/scripts/old-tool.sh)" "...which is the path the callers lose"

# A sub-pack's formulas call the scripts it ships beside them.
run --root "$REPO" --check-merge main sub-named
eq "$rc" "1" "removing a sub-pack's script that a formula still names exits 1"
has "$out" "packs/sub/assets/scripts/sub-tool.sh: the merge removes it, and packs/sub/formulas/mol-t.toml at the head (sub-named) still names it" \
  "...naming the script by its path in the sub-pack"
: > "$STUB_GC_LOG"
run --root "$REPO" --check-merge main sub-delete
eq "$rc" "3" "removing a sub-pack's script that open steps call exits 3"
has "$out" "sub-tool.sh: step hb-s1 (mol-k.probe, open, unassigned) in run hb-r1, store of rig harbor" "...listing its caller"
has "$(printf '%s\n' "$out" | head -1)" "1 open step(s) call a script the merge removes (packs/sub/assets/scripts/sub-tool.sh)" \
  "...under a headline naming its path"
: > "$STUB_GC_LOG"
run --root "$REPO" --check-merge main sub-doc-drop
eq "$rc" "0" "a sub-pack's file outside its assets/scripts/ is not a script"
has "$out" "the merge removes no pack script" "...so nothing is asked about it"
eq "$(wc -c < "$STUB_GC_LOG" | tr -d ' ')" "0" "...and no store is read"

# The city pours from the checkout it imports the pack from, which reaches the
# base only when it is fast-forwarded.
G checkout -q --detach main~1
: > "$STUB_GC_LOG"
run --root "$REPO" --check-merge main delete
eq "$rc" "4" "a formula only the checkout's HEAD still carries is a wait, since its fast-forward clears it"
has "$out" "assets/scripts/old-tool.sh: the merge removes it, and formulas/mol-b.toml at the checkout's HEAD (" \
  "...naming the checkout's HEAD"
has "$(printf '%s\n' "$out" | head -1)" "once it is fast-forwarded to the base, so the merge waits for that, and nobody has to act" "...and saying nobody has to act"
hasnt "$out" "Keep a file at each such path" "...with no remedy to make"
eq "$(wc -c < "$STUB_GC_LOG" | tr -d ' ')" "0" "...before any store is read"
run --root "$REPO" --check-merge main~1 same-change
eq "$rc" "1" "a formula at the base and the checkout alike is the branch's to fix"
has "$(printf '%s\n' "$out" | head -1)" "1 formula file(s) name a script the merge removes." \
  "a checkout at the base is read once, as the base"
G checkout -q main~1
G rm -q assets/scripts/keep.sh; G commit -qm checkout-ahead
run --root "$REPO" --check-merge main~1 same-change
eq "$rc" "1" "a formula at the base outranks one at the checkout's HEAD"
has "$out" "formulas/mol-b.toml at the base (main~1) still names it" "...and is the one named"
hasnt "$out" "at the checkout's HEAD (" "...with the checkout left unread"
G checkout -q main

callers_off
run --root "$REPO" --check-merge main delete
eq "$rc" "0" "a removed script nothing calls or names passes"
has "$out" "the merge removes assets/scripts/old-tool.sh; no formula names them and no open step calls them" "...and says what it removes"

callers_on; export STUB_BD_FAIL_DB="$STORES/harbor/.beads"
run --root "$REPO" --check-merge main delete
eq "$rc" "2" "a store that does not answer holds the decision"
unset STUB_BD_FAIL_DB

run --root "$REPO" --check-merge main no-such-branch
eq "$rc" "2" "a revision the repository lacks decides nothing"
has "$out" "'no-such-branch' names no commit" "...and says which"
run --root "$REPO" --check-merge no-such-base delete
eq "$rc" "2" "...on either side of the merge"
has "$out" "'no-such-base' names no commit" "...and says which"
run --root "$TMP/not-a-repo" --check-merge main delete
eq "$rc" "2" "a directory that is not a repository decides nothing"
has "$out" "not a git checkout: $TMP/not-a-repo" "...and says which"
run --root "$REPO" --check-merge main unrelated
eq "$rc" "2" "two commits with no merge base decide nothing, since what the head removes cannot be listed"
has "$out" "cannot list what 'unrelated' removes from 'main'" "...and says so"
hasnt "$out" "removes no pack script" "...with no all-clear"
G symbolic-ref HEAD refs/heads/unborn
run --root "$REPO" --check-merge main delete
eq "$rc" "2" "a checkout whose HEAD has no commit decides nothing"
has "$out" "has no HEAD commit" "...and says so"
G symbolic-ref HEAD refs/heads/main

echo "# a directory below the repository's top"
run_below() { out=$(cd "$REPO/assets/scripts" && "$SUT" "$@" 2>&1); rc=$?; }
callers_on
run_below --check-merge main delete
eq "$rc" "3" "run from below the top, a removed script open steps call still holds the merge"
has "$(printf '%s\n' "$out" | head -1)" "(assets/scripts/old-tool.sh)" "...named by its path from the top"
run_below --check-merge main~1 same-change
eq "$rc" "1" "...and a formula that still names a removed script still counts"
has "$out" "formulas/mol-b.toml at the base (main~1) still names it" "...named by its path from the top"
run_below --check-merge main edit-only
eq "$rc" "0" "...and a change that removes no script still passes"
run --root "$REPO/packs/sub" --check-merge main delete
eq "$rc" "3" "--root below the top reads the same repository"
has "$(printf '%s\n' "$out" | head -1)" "(assets/scripts/old-tool.sh)" "...from its top"

echo "# a loop that could not read its whole list"
SCRATCH="$TMP/scratch"; mkdir -p "$SCRATCH"
# Writes to a regular file fail, and pipes and the captured output still work.
limited() { out=$( (ulimit -f 0; trap '' XFSZ; TMPDIR="$SCRATCH" "$@") 2>&1); rc=$?; }
# One command the script reaches through PATH replaced for one run.
run_with() { local dir=$1; shift; out=$(PATH="$dir:$PATH" "$SUT" "$@" 2>&1); rc=$?; }
first_line() { printf '%s\n' "$out" | head -1; }

# More than 64 KiB in one rig's row. The callers are in the rigs after it.
PAD=$(printf '%070000d' 0)
printf '{"rigs":[{"name":"harbor-%s","path":"%s"},{"name":"workshop","path":"%s"},{"name":"lantern","path":"%s"}]}' \
  "$PAD" "$STORES/harbor" "$STORES/workshop" "$STORES/lantern" > "$STUB_RIGS"
callers_on
run old-tool.sh
eq "$rc" "3" "a long rig list is read whole"
has "$out" "old-tool.sh: step ln-s1 (mol-b.check, blocked, unassigned) in run ln-r1, store of rig lantern" "...to its last rig"
limited "$SUT" old-tool.sh
eq "$rc" "2" "a rig list that cannot be written to its temp file decides nothing"
has "$out" "cannot write a loop's input" "...and says so"
hasnt "$out" "no open step calls" "...with no all-clear"
cp "$TMP/rigs.keep" "$STUB_RIGS"

# The system bash backs a here-string of any size with a file on macOS.
run_system_bash() { out=$(/bin/bash "$SUT" "$@" 2>&1); rc=$?; }
run_system_bash old-tool.sh
eq "$rc" "3" "the system bash reads the rig list whole"
limited /bin/bash "$SUT" old-tool.sh
eq "$rc" "2" "...and decides nothing when the short rig list cannot be written"
hasnt "$out" "no open step calls" "...with no all-clear"

run --root "$REPO" --check-merge long-base long-delete
eq "$rc" "3" "a long list of removed paths is read whole"
has "$(first_line)" "a script the merge removes (assets/scripts/old-tool.sh)" "...finding the one script among the tests"
limited "$SUT" --root "$REPO" --check-merge long-base long-delete
eq "$rc" "2" "a list of removed paths that cannot be written to its temp file decides nothing"
has "$out" "cannot write a loop's input" "...and says so"
hasnt "$out" "removes no pack script" "...with no all-clear"

NO_MKTEMP="$TMP/no-mktemp"; mkdir -p "$NO_MKTEMP"
printf '#!/usr/bin/env bash\necho "mktemp: No space left on device" >&2\nexit 1\n' > "$NO_MKTEMP/mktemp"
chmod +x "$NO_MKTEMP/mktemp"
run_with "$NO_MKTEMP" old-tool.sh
eq "$rc" "2" "a temp file that cannot be created decides nothing"
has "$out" "cannot create a temp file" "...and says so"
run_with "$NO_MKTEMP" --root "$REPO" --check-merge main delete
eq "$rc" "2" "...for a removed script too"
has "$out" "cannot create a temp file" "...and says so"
run_with "$NO_MKTEMP" --root "$REPO" --check-merge main edit-only
eq "$rc" "0" "a change that removes nothing has no list to write, so it still passes"

# A read that ends its loop stands in for lines lost under it. The script's Nth
# read gets nothing, and every other read, a stub's too, is bash's.
run_losing_read() {
  local n=$1; shift
  out=$(
    read() {
      case "$0" in
        */script-callers.sh)
          _sc_reads=$((${_sc_reads:-0} + 1))
          [ "$_sc_reads" -ne "$SC_LOSE_READ" ] || return 1 ;;
      esac
      builtin read "$@"
    }
    export -f read
    SC_LOSE_READ="$n" "$SUT" "$@" 2>&1
  ); rc=$?
}
callers_off
run_losing_read 1 old-tool.sh
eq "$rc" "2" "a census that read none of the rigs decides nothing"
has "$out" "read 0 of the 3 rigs the city lists" "...and says so"
callers_on
run_losing_read 2 old-tool.sh
eq "$rc" "2" "a census that stopped short of the rigs holding the callers decides nothing"
has "$out" "read 1 of the 3 rigs the city lists" "...and says so"
run_losing_read 1 --root "$REPO" --check-merge main delete
eq "$rc" "2" "a loop that read none of the removed paths decides nothing"
has "$out" "read 0 of the 1 paths 'delete' removes" "...and says so"
callers_off
run_losing_read 3 --root "$REPO" --check-merge main head-names
eq "$rc" "2" "a loop that read none of the formulas naming a removed script decides nothing"
has "$out" "read 0 of the 1 files at 'head-names' that name old-tool.sh" "...and says so"
run_losing_read 3 --root "$REPO" --check-merge main delete
eq "$rc" "2" "a loop that read none of the rigs for a removed script decides nothing"
has "$out" "read 0 of the 3 rigs the city lists" "...and says so"

GIT_FAILS="$TMP/git-fails"; mkdir -p "$GIT_FAILS"
REAL_GIT=$(command -v git)
cat > "$GIT_FAILS/git" <<STUB
#!/usr/bin/env bash
case " \$* " in *" ls-tree "*|*" cat-file "*) echo "fatal: bad object" >&2; exit 128 ;; esac
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$GIT_FAILS/git"
run_with "$GIT_FAILS" --root "$REPO" --check-merge main delete
eq "$rc" "2" "a read of whether the base carries a removed path that fails decides nothing"
has "$out" "cannot read 'assets/scripts/old-tool.sh' at 'main'" "...and says so"

GREP_FAILS="$TMP/grep-fails"; mkdir -p "$GREP_FAILS"
cat > "$GREP_FAILS/git" <<STUB
#!/usr/bin/env bash
case " \$* " in *" grep "*) echo "fatal: unable to read tree" >&2; exit 128 ;; esac
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$GREP_FAILS/git"
callers_off
run_with "$GREP_FAILS" --root "$REPO" --check-merge main delete
eq "$rc" "2" "a read of the formulas that fails decides nothing"
has "$out" "cannot read the formulas at 'main'" "...and says so"
hasnt "$out" "no formula names them" "...with no all-clear"

NO_WC="$TMP/no-wc"; mkdir -p "$NO_WC"
printf '#!/usr/bin/env bash\nexit 1\n' > "$NO_WC/wc"; chmod +x "$NO_WC/wc"
callers_on
run_with "$NO_WC" --root "$REPO" --check-merge main delete
eq "$rc" "3" "counting the callers takes no command whose failure could leave the count at zero"
has "$(first_line)" "3 open step(s) call a script the merge removes" "...so the count stands"

TMPDIR="$SCRATCH" "$SUT" old-tool.sh >/dev/null 2>&1
TMPDIR="$SCRATCH" "$SUT" --root "$REPO" --check-merge main delete >/dev/null 2>&1
TMPDIR="$SCRATCH" "$SUT" --root "$REPO" --check-merge main head-names >/dev/null 2>&1
callers_off
TMPDIR="$SCRATCH" "$SUT" --root "$REPO" --check-merge main delete >/dev/null 2>&1
eq "$(ls -A "$SCRATCH")" "" "no temp file stays behind, whatever the answer"
eq "$(grep -c '<<<' "$SUT")" "0" "no loop reads a here-string, which can fail with nothing to check"

echo "---"
echo "script-callers.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
