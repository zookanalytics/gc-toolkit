#!/usr/bin/env bash
# Hermetic test for mol-design-convoy's gate-shape resolution, its branch cut,
# and the steps that file its children and its summary task.
#
# design-gated-resolve turns the design_gated var into exactly true or false.
# It reads the value case-insensitively and falls back to the design-gated
# default on anything it does not recognize, so a typo never drops the design
# gate. load-context, arm-design and arm-implementation each carry a copy, and
# the copies must stay identical.
#
# seed-branch-cut cuts integration/<subject> from the default branch with one
# create-only push, and records the branch and the default branch on the
# subject, which is the effort's landing bead. A refused push after which origin
# carries the branch is an earlier pass's cut, a subject that records the branch
# is cut no further, and a subject that records another branch or lands
# elsewhere is refused.
#
# The arm steps file each child with the integration branch as its target in
# its create, under the subject's epic when it has one, make the subject wait on
# it, and read both back before anything dispatches. arm-design hands the subject to the refinery once that first wait
# reads back, and slings the design child --merge mr when it is design-gated.
# The summary step files the summary task under the subject's epic, with no
# target, makes it wait on both children and the subject wait on it, and arms it
# on mol-polecat-report only once all three edges read back. Each step stamps
# its marker (gc.design_armed, gc.impl_armed, gc.summary_armed) only after every
# write landed and read back, because a resume skips a step whose marker is set.
# A child slung without its target would land on the default branch, a subject
# handed over while it waits on nothing would reach the refinery at once, and a
# summary task armed with nothing to wait on would be dispatched at once. Each
# failure case breaks one write and checks that nothing downstream of it ran.
#
# The read-back decides whether a write landed, not its exit status. A resume
# re-runs every add on edges the failed pass may already have written, and bd
# refuses the duplicate, so the resume cases give each add a non-zero exit over
# an edge that reads back and check that the step completes.
#
# EXECUTES the real snippets extracted verbatim between the formula markers, so
# the test cannot drift from the shipped instruction. No live city or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-design-convoy.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-design-convoy-arm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# extract_copy <marker> <n>: the lines of the n-th marked copy (exclusive).
extract_copy() {
  awk -v m="$1" -v want="$2" '
    $0 ~ ("# >>> " m "$") {n++; f=(n == want); next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}
copies() { grep -c -- "# >>> $1\$" "$TOML" || true; }

BLOCKS="seed-branch-cut arm-design-create arm-design-dispatch arm-implementation-create arm-implementation-dispatch summary-task-create summary-task-arm"

# --- static pins ---------------------------------------------------------------

for m in design-gated-resolve $BLOCKS; do
  BLOCK="$(extract_copy "$m" 1)"
  [ -n "$BLOCK" ] && ok "$m extracted between markers" \
    || bad "$m extraction EMPTY — markers missing from $TOML"
  # A TOML triple-quoted string eats a trailing backslash (line-ending escape)
  # and silently joins lines, so a shipped snippet must be backslash-free.
  case "$BLOCK" in
    *\\*) bad "$m contains a backslash — TOML escapes will mangle it" ;;
    *)    ok  "$m is backslash-free" ;;
  esac
done
for m in $BLOCKS; do
  eq "$(copies "$m")" "1" "$m has one copy"
done

eq "$(copies design-gated-resolve)" "3" "design-gated-resolve has three copies (load-context, arm-design, arm-implementation)"
if [ "$(extract_copy design-gated-resolve 1)" = "$(extract_copy design-gated-resolve 2)" ] \
   && [ "$(extract_copy design-gated-resolve 1)" = "$(extract_copy design-gated-resolve 3)" ]; then
  ok "the design-gated-resolve copies are identical"
else
  bad "the design-gated-resolve copies differ — load-context would report a shape the arm steps do not act on"
fi

# Gate 1 binds through merge.sh's universal approval rule, so the formula stamps
# no check_set, and the retired codex lane appears nowhere.
if grep -qE -- '--set-metadata "?check_set' "$TOML"; then
  bad "the formula writes check_set — gate 1 needs no lane token under the universal approval rule"
else
  ok "the formula writes no check_set"
fi
if grep -qi 'codex' "$TOML"; then
  bad "the formula names the retired codex lane"
else
  ok "the formula does not name the retired codex lane"
fi
# The object-or-array alternative crashes jq on a refused create instead of
# reporting bd's reason.
if grep -qE '\.id[[:space:]]*//[[:space:]]*\.\[0\]\.id|\.\[0\]\.id[[:space:]]*//[[:space:]]*\.id([^[:alnum:]_]|$)' "$TOML"; then
  bad "the formula reads a bd answer's id as an object-or-array alternative"
else
  ok "the formula reads bd answers' ids type-guarded"
fi
# Each bead carries its own branch, so no convoy carries one: the formula makes
# no convoy, links no child to one, and gives the subject no until edge onto
# one.
for probe in 'convoy create' 'convoy target' 'convoy-seed' '--type=parent-child' '--type=until'; do
  if grep -qF -- "$probe" "$TOML"; then
    bad "the formula carries '$probe' — a convoy carries no branch and closes no subject"
  else
    ok "the formula carries no '$probe'"
  fi
done
eq "$(grep -c 'gc runtime drain-ack' "$TOML")" "1" "one step drains: the summary step, the last"

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=(zsh)
else
  echo "note - zsh not present; executing under bash only"
fi

# --- design-gated-resolve --------------------------------------------------------

RESOLVE="$(extract_copy design-gated-resolve 1)"

# resolve <shell> <value>: the block with {{design_gated}} replaced by <value>
# the way the formula engine substitutes it. Prints the resolved value; stderr
# goes to $TMP/resolve.err.
resolve() {
  local sh="$1" val="$2"
  {
    printf '%s\n' "${RESOLVE//\{\{design_gated\}\}/$val}"
    printf 'printf "%%s\\n" "$DESIGN_GATED"\n'
  } > "$TMP/resolve.sh"
  "$sh" "$TMP/resolve.sh" 2> "$TMP/resolve.err"
}

for sh in "${SHELLS[@]}"; do
  for v in true True TRUE 1 yes On " true "; do
    eq "$(resolve "$sh" "$v")" "true" "[$sh] design_gated='$v' resolves to true"
  done
  for v in false False FALSE 0 no off " Off "; do
    eq "$(resolve "$sh" "$v")" "false" "[$sh] design_gated='$v' resolves to false"
  done
  eq "$(resolve "$sh" "")" "true" "[$sh] an empty design_gated falls back to true"
  grep -q 'not a recognized boolean' "$TMP/resolve.err" \
    && ok "[$sh] an empty design_gated is reported" \
    || bad "[$sh] an empty design_gated fell back silently"
  eq "$(resolve "$sh" "flase")" "true" "[$sh] a misspelled design_gated falls back to true"
  grep -q "design_gated='flase'" "$TMP/resolve.err" \
    && ok "[$sh] the misspelled value is named in the warning" \
    || bad "[$sh] the misspelled value is not named in the warning"
  eq "$(resolve "$sh" "{{design_gated}}")" "true" "[$sh] an unsubstituted placeholder falls back to true"
  resolve "$sh" "false" >/dev/null
  [ -s "$TMP/resolve.err" ] && bad "[$sh] a recognized value printed a warning" \
    || ok "[$sh] a recognized value prints no warning"
done

# --- stubs -------------------------------------------------------------------------
# gc answers from a store, STORE: a JSON array of beads, each {id, title,
# issue_type, status, assignee, description, metadata, _deps}, where _deps holds
# the bead's own edges as {id, dependency_type}. Every call is logged to GC_LOG,
# one line each. Failure injection, each a space-separated list:
#   REFUSE_EDGES  "<a>><b>" pairs whose `dep add` exits 1 and writes nothing
#   DROP_EDGES    pairs whose `dep add` exits 0 and writes nothing, as bd does
#                 for an edge onto a bead in another store
#   UPDATE_FAIL   "<id>:<key>" (or "<id>:assignee") whose `update` exits 1 and
#                 writes nothing
#   SHOW_FAIL     ids whose `show` answers nothing
# and CREATE_FAIL (a create bd refuses), NEXT_ID (the id a create files),
# SLING_RC, ROSTER_FILE (what `agent list --json` prints) and ROSTER_FAIL.
# A dep add over an edge the store already holds exits 1, as bd refuses a
# duplicate. An update's --if-assignee is the guard bd applies, exiting 13 on a
# mismatch.
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
printf 'gc %s' "$*" | tr '\n' ' ' >> "$GC_LOG"; printf '\n' >> "$GC_LOG"
listed() { case " ${1:-} " in *" $2 "*) return 0 ;; esac; return 1; }
put() { jq -c "$@" "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"; }
case "${1:-} ${2:-}" in
  "bd show")
    listed "${SHOW_FAIL:-}" "$3" && exit 1
    jq -c --arg id "$3" '. as $s | [ .[] | select(.id == $id)
        | .dependencies = [ (._deps // [])[] | .id as $t | ($s | map(select(.id == $t)) | .[0]) as $o
            | . + {issue_type: ($o.issue_type // "task"), status: ($o.status // "open")} ]
        | del(._deps) ]' "$STORE"
    exit 0 ;;
  "bd update")
    id="$3"; shift 3; sets='{}'; who="-"; guard="-"; keys=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) sets=$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '. + {($k): $v}' <<< "$sets"); keys="$keys $id:${2%%=*}"; shift 2 ;;
        --assignee) who="$2"; keys="$keys $id:assignee"; shift 2 ;;
        --if-assignee) guard="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    for k in $keys; do listed "${UPDATE_FAIL:-}" "$k" && { echo "update refused" >&2; exit 1; }; done
    if [ "$guard" != "-" ]; then
      [ "$(jq -r --arg id "$id" '.[] | select(.id == $id) | .assignee // ""' "$STORE")" = "$guard" ] \
        || { echo "the assignee no longer matches" >&2; exit 13; }
    fi
    put --arg id "$id" --argjson s "$sets" --arg w "$who" \
      'map(if .id == $id then (.metadata = ((.metadata // {}) + $s)) | (if $w == "-" then . else .assignee = $w end) else . end)'
    exit 0 ;;
  "bd create")
    shift 2; title=""; desc=""; meta='{}'; parent=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) title="$2"; shift 2 ;;
        -d) desc="$2"; shift 2 ;;
        --metadata) meta="$2"; shift 2 ;;
        --parent) parent="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -z "${CREATE_FAIL:-}" ] || { echo '{"error":"simulated refusal"}'; exit 1; }
    put --arg id "$NEXT_ID" --arg t "$title" --arg d "$desc" --argjson m "$meta" --arg p "$parent" \
      '. + [{id: $id, title: $t, issue_type: "task", status: "open", assignee: "", description: $d, metadata: $m,
             _deps: (if $p == "" then [] else [{id: $p, dependency_type: "parent-child"}] end)}]'
    jq -nc --arg id "$NEXT_ID" '{id: $id}'
    exit 0 ;;
  "bd dep")
    case "${3:-}" in
      add)
        a="$4"; b="$5"; t="${6#--type=}"
        listed "${REFUSE_EDGES:-}" "$a>$b" && { echo "Error: refused" >&2; exit 1; }
        listed "${DROP_EDGES:-}" "$a>$b" && { echo "Added dependency: $a depends on $b ($t)"; exit 0; }
        if jq -e --arg a "$a" --arg b "$b" 'any(.[]; .id == $a and any((._deps // [])[]; .id == $b))' "$STORE" >/dev/null; then
          echo "Error: dependency $a -> $b already exists" >&2; exit 1
        fi
        put --arg a "$a" --arg b "$b" --arg t "$t" 'map(if .id == $a then ._deps = ((._deps // []) + [{id: $b, dependency_type: $t}]) else . end)'
        exit 0 ;;
      list)
        id="$4"; t=""; prev=""
        for x in "$@"; do [ "$prev" = "-t" ] && t="$x"; prev="$x"; done
        jq -c --arg id "$id" --arg t "$t" '. as $s | [ .[] | select(.id == $id) | (._deps // [])[]
            | select($t == "" or .dependency_type == $t) | .id as $o
            | {id: $o, dependency_type, status: (($s | map(select(.id == $o)) | .[0].status) // "open")} ]' "$STORE"
        exit 0 ;;
    esac ;;
  "agent list")
    [ -z "${ROSTER_FAIL:-}" ] || exit 1
    cat "$ROSTER_FILE"; exit 0 ;;
esac
[ "${1:-}" = "sling" ] && exit "${SLING_RC:-0}"
exit 0
STUB
# git, for the branch cut: ORIGIN_REFS lists the branches origin carries, as a
# fetch has read them. A push writes its branch there unless the branch is
# already listed, which an empty lease refuses, or PUSH_FAIL refuses every push.
# ORIGIN_HEAD names the default branch origin/HEAD points at; empty, the
# symbolic ref is unreadable. FETCH_RC is the exit of the fetch of origin.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<'STUB'
printf 'git %s\n' "$*" >> "$GC_LOG"
[ "${1:-}" = "-C" ] && shift 2
case "${1:-}" in
  fetch) [ "${2:-}" = "--prune" ] && exit "${FETCH_RC:-0}"; exit 0 ;;
  symbolic-ref) [ -n "${ORIGIN_HEAD:-}" ] || exit 1; printf 'refs/remotes/origin/%s\n' "$ORIGIN_HEAD"; exit 0 ;;
  show-ref) ref="${!#}"; grep -qxF -- "${ref#refs/remotes/origin/}" "$ORIGIN_REFS"; exit $? ;;
  push)
    [ -z "${PUSH_FAIL:-}" ] || { echo "push refused" >&2; exit 1; }
    dst="${3#*:}"; b="${dst#refs/heads/}"
    grep -qxF -- "$b" "$ORIGIN_REFS" && { echo " ! [rejected] (stale info)" >&2; exit 1; }
    printf '%s\n' "$b" >> "$ORIGIN_REFS"; exit 0 ;;
esac
exit 0
STUB
cat > "$TMP/bin/deferred-dispatch.sh" <<'STUB'
#!/usr/bin/env bash
printf 'deferred-dispatch %s\n' "$*" >> "$GC_LOG"
case "${1:-}" in
  arm) exit "${ARM_RC:-0}" ;;
  notify) exit "${NOTIFY_RC:-0}" ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gc" "$TMP/bin/git" "$TMP/bin/deferred-dispatch.sh"

export GC_LOG="$TMP/gc.log" STORE="$TMP/store.json" ORIGIN_REFS="$TMP/origin-refs" ROSTER_FILE="$TMP/roster.json"
export SCRIPTS="$TMP/bin" RIG_ROOT="$TMP/rig" POOL="rig/gc-toolkit.polecat" REFINERY="rig/gc-toolkit.refinery"
export SUBJECT="sub-1" BRANCH="integration/sub-1" INITIATIVE="Rebuild the widget"
printf '%s\n' '{"agents":[{"qualified_name":"rig/gc-toolkit.polecat"},{"qualified_name":"rig/gc-toolkit.refinery"}]}' > "$ROSTER_FILE"

# fixture [<jq edit>]: a store holding the subject sub-1 under the epic ep-1,
# with its planned work in its description and nothing recorded on it, and the
# design and implementation children dz-design and dz-impl, each filed with the
# integration branch as its target. The edit, when given, changes it. Every
# injected failure is reset.
fixture() {
  jq -nc '[
    {id: "ep-1", title: "The widget epic", issue_type: "epic", status: "open", assignee: "", description: "", metadata: {}, _deps: []},
    {id: "sub-1", title: "Rebuild the widget", issue_type: "task", status: "open", assignee: "",
     description: "Plan: rebuild the widget renderer and retire the old cache.", metadata: {},
     _deps: [{id: "ep-1", dependency_type: "parent-child"}]},
    {id: "dz-design", title: "design: Rebuild the widget", issue_type: "task", status: "open", assignee: "", description: "", metadata: {target: "integration/sub-1"}, _deps: []},
    {id: "dz-impl", title: "implement: Rebuild the widget per its design", issue_type: "task", status: "open", assignee: "", description: "", metadata: {target: "integration/sub-1"}, _deps: []}
  ]' > "$STORE"
  [ -z "${1:-}" ] || { jq -c "$1" "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"; }
  printf 'main\n' > "$ORIGIN_REFS"
  export ORIGIN_HEAD=main FETCH_RC=0 PUSH_FAIL="" REFUSE_EDGES="" DROP_EDGES="" UPDATE_FAIL="" SHOW_FAIL="" \
    CREATE_FAIL="" NEXT_ID="" SLING_RC=0 ARM_RC=0 NOTIFY_RC=0 ROSTER_FAIL="" ARMED=""
  export DESIGN_CHILD="dz-design" IMPL_CHILD="dz-impl" SUMMARY_TASK=""
}
# subject_json: the subject as the step's derive block reads it.
subject_json() { SUBJECT_JSON="$(PATH="$TMP/bin:$PATH" GC_LOG=/dev/null gc bd show "$SUBJECT" --json)"; export SUBJECT_JSON; }

# run_block <marker> <shell>: runs the marked block with the step's variables
# in the environment and the stubs first on PATH. Sets RC; the call log is
# $GC_LOG. A sentinel after the block records whether execution ran past it:
# the step's contract is that a failed write stops it, not merely that the
# block's last command happened to fail.
run_block() {
  local m="$1" sh="$2"
  { extract_copy "$m" 1; printf 'printf "past\\n" > "%s"\n' "$TMP/past.flag"; } > "$TMP/block.sh"
  : > "$GC_LOG"; rm -f "$TMP/past.flag"
  RC=0
  PATH="$TMP/bin:$PATH" "$sh" "$TMP/block.sh" >"$TMP/block.out" 2>"$TMP/block.err" || RC=$?
}
logged()     { grep -qF -- "$1" "$GC_LOG"; }
not_logged() { ! grep -qF -- "$1" "$GC_LOG"; }
count()      { grep -cF -- "$1" "$GC_LOG" || true; }
stopped()    { [ "$RC" -ne 0 ] && [ ! -e "$TMP/past.flag" ]; }
reported()   { grep -qF -- "$1" "$TMP/block.err"; }
# meta <id> <key>: the key as the store holds it, or <absent>.
meta()       { jq -r --arg id "$1" --arg k "$2" '.[] | select(.id == $id) | .metadata[$k] // "<absent>"' "$STORE"; }
field()      { jq -r --arg id "$1" --arg f "$2" '.[] | select(.id == $id) | .[$f] // "<absent>"' "$STORE"; }
waits_on()   { jq -r --arg a "$1" --arg b "$2" '[.[] | select(.id == $a) | (._deps // [])[] | select(.id == $b and .dependency_type == "blocks")] | length' "$STORE"; }
# parents <id>: the bead's parent-child parents, space-joined, or nothing.
parents()    { jq -r --arg id "$1" '[.[] | select(.id == $id) | (._deps // [])[] | select(.dependency_type == "parent-child") | .id] | join(" ")' "$STORE"; }
# line_of <text>: the number of the first log line holding <text>, or 0.
line_of()    { awk -v t="$1" 'index($0, t) { print NR; f = 1; exit } END { if (!f) print 0 }' "$GC_LOG"; }
# says <id> <text>: the bead's description holds <text>.
says()       { case "$(field "$1" description)" in *"$2"*) return 0 ;; esac; return 1; }
before()     { local a b; a=$(line_of "$1"); b=$(line_of "$2"); [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -lt "$b" ]; }

for sh in "${SHELLS[@]}"; do
  # --- seed-branch-cut ---
  fixture; subject_json
  run_block seed-branch-cut "$sh"
  eq "$RC" "0" "[$sh] seed: a fresh subject is cut and recorded"
  logged "git -C $RIG_ROOT push origin refs/remotes/origin/main:refs/heads/integration/sub-1 --force-with-lease=refs/heads/integration/sub-1:" \
    && ok "[$sh] seed: one create-only push from the rig's checkout cuts the branch from the default branch" \
    || bad "[$sh] seed: no create-only push of the branch"
  grep -qxF "integration/sub-1" "$ORIGIN_REFS" && ok "[$sh] seed: origin carries the branch" \
    || bad "[$sh] seed: origin does not carry the branch"
  eq "$(meta sub-1 branch) $(meta sub-1 target)" "integration/sub-1 main" "[$sh] seed: the subject records the branch and the default branch as its target"
  before "fetch --prune origin" "push origin" && ok "[$sh] seed: the cut follows a fetch of origin" \
    || bad "[$sh] seed: the push ran without a fetch before it"

  fixture; subject_json; export ORIGIN_HEAD=trunk; printf 'trunk\n' > "$ORIGIN_REFS"
  run_block seed-branch-cut "$sh"
  eq "$RC $(meta sub-1 target)" "0 trunk" "[$sh] seed: the default branch is the one origin/HEAD names"
  logged "push origin refs/remotes/origin/trunk:refs/heads/integration/sub-1" \
    && ok "[$sh] seed: …and the branch is cut from it" || bad "[$sh] seed: the branch was not cut from origin/HEAD's branch"

  fixture; subject_json; export ORIGIN_HEAD=""
  run_block seed-branch-cut "$sh"
  eq "$RC $(meta sub-1 target)" "0 main" "[$sh] seed: an unreadable origin/HEAD falls back to main"

  # resume: an earlier pass cut the branch and died before its record landed
  fixture; subject_json; printf 'main\nintegration/sub-1\n' > "$ORIGIN_REFS"
  run_block seed-branch-cut "$sh"
  eq "$RC" "0" "[$sh] seed resume: a refused push after which origin carries the branch is an earlier cut"
  eq "$(meta sub-1 branch)" "integration/sub-1" "[$sh] seed resume: …and the branch is recorded"
  grep -qF "already carries" "$TMP/block.out" && ok "[$sh] seed resume: the earlier cut is reported" \
    || bad "[$sh] seed resume: the earlier cut passed silently"

  fixture; subject_json; export PUSH_FAIL=1
  run_block seed-branch-cut "$sh"
  stopped && [ "$(meta sub-1 branch)" = "<absent>" ] \
    && ok "[$sh] seed: a push that fails while origin lacks the branch stops the step with nothing recorded" \
    || bad "[$sh] seed: a failed push was trusted (rc=$RC, branch=$(meta sub-1 branch))"

  fixture; subject_json; export FETCH_RC=1
  run_block seed-branch-cut "$sh"
  stopped && not_logged "push origin" && ok "[$sh] seed: a failed fetch stops the step before the push" \
    || bad "[$sh] seed: the push ran after a failed fetch (rc=$RC)"

  fixture '.[1].metadata = {branch: "integration/sub-1", target: "main"}'; subject_json
  run_block seed-branch-cut "$sh"
  eq "$RC" "0" "[$sh] seed: a subject that records the branch passes"
  not_logged "git " && ok "[$sh] seed: …and is cut no further" || bad "[$sh] seed: a recorded branch was cut again"

  fixture '.[1].metadata = {branch: "polecat/sub-1"}'; subject_json
  run_block seed-branch-cut "$sh"
  stopped && not_logged "push origin" && [ "$(meta sub-1 branch)" = "polecat/sub-1" ] && reported "not this run's to cut" \
    && ok "[$sh] seed: a subject recording another branch keeps it, nothing is cut, and the refusal says why" \
    || bad "[$sh] seed: a subject recording another branch was cut over (rc=$RC)"

  fixture '.[1].metadata = {target: "integration/other"}'; subject_json
  run_block seed-branch-cut "$sh"
  stopped && not_logged "push origin" && [ "$(meta sub-1 target)" = "integration/other" ] \
    && ok "[$sh] seed: a subject that lands inside another branch is not cut" \
    || bad "[$sh] seed: a subject landing inside another branch was cut (rc=$RC)"

  fixture '.[1].metadata = {target: "main"}'; subject_json
  run_block seed-branch-cut "$sh"
  eq "$RC $(meta sub-1 branch)" "0 integration/sub-1" "[$sh] seed: a subject that already lands on the default branch is cut"

  fixture; subject_json; export UPDATE_FAIL="sub-1:branch"
  run_block seed-branch-cut "$sh"
  stopped && reported "not filing anything" && ok "[$sh] seed: a record that does not read back stops the step" \
    || bad "[$sh] seed: an unrecorded branch passed (rc=$RC)"

  # --- arm-design-create ---
  fixture '.[2:] = []'; subject_json; export DESIGN_CHILD="" NEXT_ID=dz-design DESIGN_GATED=true
  run_block arm-design-create "$sh"
  eq "$RC" "0" "[$sh] design create: the design child is filed"
  eq "$(meta dz-design target)" "integration/sub-1" "[$sh] design create: its target is the integration branch, written in its create"
  eq "$(meta sub-1 gc.design_child)" "dz-design" "[$sh] design create: gc.design_child is recorded on the subject"
  says dz-design "It is a stage" && ok "[$sh] design create: design-gated, the brief says it is a stage" \
    || bad "[$sh] design create: the gated brief does not say the child is a stage"
  eq "$(parents dz-design)" "ep-1" "[$sh] design create: it is filed under the subject's epic, beside the subject"

  fixture '.[2:] = [] | .[1]._deps = []'; subject_json; export DESIGN_CHILD="" NEXT_ID=dz-design DESIGN_GATED=true
  run_block arm-design-create "$sh"
  eq "$RC $(parents dz-design)" "0 " "[$sh] design create: a subject with no epic gives the child no parent"

  fixture '.[2:] = []'; subject_json; export DESIGN_CHILD="" NEXT_ID=dz-design DESIGN_GATED=false
  run_block arm-design-create "$sh"
  says dz-design "with no PR of its own" && ok "[$sh] design create: all-in-one, the brief says it lands with no PR of its own" \
    || bad "[$sh] design create: the all-in-one brief does not say how it lands"

  fixture '.[2:] = []'; subject_json; export DESIGN_CHILD="" CREATE_FAIL=1
  run_block arm-design-create "$sh"
  stopped && reported "simulated refusal" && [ "$(meta sub-1 gc.design_child)" = "<absent>" ] \
    && ok "[$sh] design create: a refused create reports bd's reason and records nothing" \
    || bad "[$sh] design create: a refused create passed (rc=$RC)"

  fixture; subject_json
  run_block arm-design-create "$sh"
  eq "$RC" "0" "[$sh] design create: a filed child is not filed again"
  not_logged "bd create" && ok "[$sh] design create: …and nothing is created" || bad "[$sh] design create: a second child was filed"

  # --- arm-design-dispatch ---
  fixture; subject_json; export DESIGN_GATED=true
  run_block arm-design-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-design gated: a child whose target and wait read back is handed over and slung"
  eq "$(waits_on sub-1 dz-design)" "1" "[$sh] arm-design: the subject waits on the design child"
  eq "$(field sub-1 assignee)" "rig/gc-toolkit.refinery" "[$sh] arm-design: the subject is assigned to the refinery"
  logged "deferred-dispatch notify sub-1 --agent rig/gc-toolkit.refinery" \
    && ok "[$sh] arm-design: the notice the assignment owes is recorded" || bad "[$sh] arm-design: no notice"
  logged "sling rig/gc-toolkit.polecat dz-design --on mol-polecat-work --merge mr" \
    && ok "[$sh] arm-design gated: the design child is slung --merge mr, a stage" || bad "[$sh] arm-design gated: not slung as a stage"
  eq "$(meta sub-1 gc.design_armed)" "1" "[$sh] arm-design: gc.design_armed is stamped"
  before "bd dep list sub-1" "update sub-1 --if-assignee" && before "update sub-1 --if-assignee" "deferred-dispatch notify" \
    && before "deferred-dispatch notify" "gc sling" \
    && ok "[$sh] arm-design: the hand-over follows the wait's read-back, and the sling follows the hand-over" \
    || bad "[$sh] arm-design: the hand-over or the sling is out of order"

  fixture; subject_json; export DESIGN_GATED=false
  run_block arm-design-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-design all-in-one: the step succeeds"
  logged "sling rig/gc-toolkit.polecat dz-design --on mol-polecat-work" && not_logged "--merge" \
    && ok "[$sh] arm-design all-in-one: the design child is slung with no merge strategy" \
    || bad "[$sh] arm-design all-in-one: slung with a merge strategy, or not slung"

  fixture '.[2].metadata = {}'; subject_json; export DESIGN_GATED=true
  run_block arm-design-dispatch "$sh"
  stopped && not_logged "dep add" && not_logged "sling " && [ "$(field sub-1 assignee)" = "" ] \
    && ok "[$sh] arm-design: a child that reads no target is neither waited on, handed over nor slung" \
    || bad "[$sh] arm-design: a child with no target went ahead (rc=$RC)"

  fixture; subject_json; export DROP_EDGES="sub-1>dz-design"
  run_block arm-design-dispatch "$sh"
  stopped && not_logged "notify" && not_logged "sling " && [ "$(field sub-1 assignee)" = "" ] && [ "$(meta sub-1 gc.design_armed)" = "<absent>" ] \
    && ok "[$sh] arm-design: a wait that exits 0 but does not read back stops before the hand-over" \
    || bad "[$sh] arm-design: an unread wait was trusted (rc=$RC)"

  fixture; subject_json; export REFUSE_EDGES="sub-1>dz-design"
  run_block arm-design-dispatch "$sh"
  stopped && not_logged "sling " && ok "[$sh] arm-design: a refused add that reads no edge back fails the step" \
    || bad "[$sh] arm-design: a refused add passed (rc=$RC)"

  # resume: the edge and the hand-over are there from the failed first pass
  fixture '.[1]._deps += [{id: "dz-design", dependency_type: "blocks"}] | .[1].assignee = "rig/gc-toolkit.refinery"'; subject_json
  run_block arm-design-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-design resume: an existing wait and hand-over complete the step"
  eq "$(count "gc sling")" "1" "[$sh] arm-design resume: the child is slung once"
  reported "reading the edge back" && ok "[$sh] arm-design resume: the refused add is reported" \
    || bad "[$sh] arm-design resume: the refused add passed silently"
  not_logged "--if-assignee" && ok "[$sh] arm-design resume: a subject already with the refinery is not assigned again" \
    || bad "[$sh] arm-design resume: the subject was assigned again"

  fixture; subject_json
  printf '%s\n' '{"agents":[{"qualified_name":"rig/gc-toolkit.polecat"}]}' > "$ROSTER_FILE"
  run_block arm-design-dispatch "$sh"
  stopped && not_logged "update sub-1 --if-assignee" && not_logged "sling " \
    && ok "[$sh] arm-design: a refinery address the roster lacks hands nothing over" \
    || bad "[$sh] arm-design: handed over to an address no agent holds (rc=$RC)"
  printf '%s\n' '{"agents":[{"qualified_name":"rig/gc-toolkit.polecat"},{"qualified_name":"rig/gc-toolkit.refinery"}]}' > "$ROSTER_FILE"

  fixture; subject_json; export ROSTER_FAIL=1
  run_block arm-design-dispatch "$sh"
  eq "$RC $(field sub-1 assignee)" "0 rig/gc-toolkit.refinery" "[$sh] arm-design: an unreadable roster hands over unchecked"
  reported "roster unreadable" && ok "[$sh] arm-design: …and says so" || bad "[$sh] arm-design: the unchecked hand-over passed silently"

  fixture '.[1].assignee = "someone-else"'; subject_json
  run_block arm-design-dispatch "$sh"
  stopped && not_logged "sling " && [ "$(field sub-1 assignee)" = "someone-else" ] \
    && ok "[$sh] arm-design: a subject assigned elsewhere keeps its assignee and nothing is slung" \
    || bad "[$sh] arm-design: a subject assigned elsewhere was handed over (rc=$RC)"

  fixture; subject_json; export UPDATE_FAIL="sub-1:assignee"
  run_block arm-design-dispatch "$sh"
  stopped && not_logged "notify" && not_logged "sling " \
    && ok "[$sh] arm-design: an assignment that fails neither records the notice nor slings" \
    || bad "[$sh] arm-design: went ahead after a failed assignment (rc=$RC)"

  fixture; subject_json; export NOTIFY_RC=1
  run_block arm-design-dispatch "$sh"
  stopped && not_logged "sling " && [ "$(meta sub-1 gc.design_armed)" = "<absent>" ] \
    && ok "[$sh] arm-design: a notice that does not record stops before the sling" \
    || bad "[$sh] arm-design: slung with no notice recorded (rc=$RC)"

  fixture; subject_json; export SLING_RC=1
  run_block arm-design-dispatch "$sh"
  stopped && [ "$(meta sub-1 gc.design_armed)" = "<absent>" ] \
    && ok "[$sh] arm-design: a failed sling leaves the marker unstamped" || bad "[$sh] arm-design: a failed sling stamped the marker (rc=$RC)"

  fixture; subject_json; export UPDATE_FAIL="sub-1:gc.design_armed"
  run_block arm-design-dispatch "$sh"
  stopped && ok "[$sh] arm-design: a marker that does not record fails the step" || bad "[$sh] arm-design: an unrecorded marker passed"

  fixture; subject_json; export ARMED=1
  run_block arm-design-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-design: an armed subject is a no-op"
  [ -s "$GC_LOG" ] && bad "[$sh] arm-design: an armed subject still wrote" || ok "[$sh] arm-design: an armed subject writes nothing"

  # --- arm-implementation-create ---
  fixture '.[3:] = []'; subject_json; export IMPL_CHILD="" NEXT_ID=dz-impl DESIGN_GATED=true
  run_block arm-implementation-create "$sh"
  eq "$RC" "0" "[$sh] impl create: the implementation child is filed"
  eq "$(meta dz-impl target)" "integration/sub-1" "[$sh] impl create: its target is the integration branch, written in its create"
  eq "$(meta sub-1 gc.impl_child)" "dz-impl" "[$sh] impl create: gc.impl_child is recorded on the subject"
  eq "$(parents dz-impl)" "ep-1" "[$sh] impl create: it is filed under the subject's epic"
  says dz-impl "gc.summary_task" && says dz-impl "target=integration/sub-1" \
    && ok "[$sh] impl create: its brief gives a bead it splits into the same writes, the summary task's wait among them" \
    || bad "[$sh] impl create: the brief does not give a split bead its writes"

  fixture '.[3:] = []'; subject_json; export IMPL_CHILD="" CREATE_FAIL=1
  run_block arm-implementation-create "$sh"
  stopped && [ "$(meta sub-1 gc.impl_child)" = "<absent>" ] && ok "[$sh] impl create: a refused create records nothing" \
    || bad "[$sh] impl create: a refused create passed (rc=$RC)"

  # --- arm-implementation-dispatch, design-gated ---
  fixture; subject_json; export DESIGN_GATED=true
  run_block arm-implementation-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-impl gated: verified waits arm the deferred dispatch"
  eq "$(waits_on sub-1 dz-impl)" "1" "[$sh] arm-impl: the subject waits on the implementation child"
  eq "$(waits_on dz-impl dz-design)" "1" "[$sh] arm-impl gated: the design child blocks the implementation (operand order)"
  logged "deferred-dispatch arm dz-impl --target rig/gc-toolkit.polecat --sling-arg --on --sling-arg mol-polecat-work" \
    && ok "[$sh] arm-impl gated: the deferred dispatch is armed" || bad "[$sh] arm-impl gated: no deferred arm"
  not_logged "gc sling" && ok "[$sh] arm-impl gated: nothing is slung now" || bad "[$sh] arm-impl gated: slung before the design closed"
  eq "$(meta sub-1 gc.impl_armed)" "1" "[$sh] arm-impl gated: gc.impl_armed is stamped"

  fixture '.[3].metadata = {}'; subject_json
  run_block arm-implementation-dispatch "$sh"
  stopped && not_logged "dep add" && not_logged "deferred-dispatch" \
    && ok "[$sh] arm-impl: a child that reads no target is neither waited on nor dispatched" \
    || bad "[$sh] arm-impl: a child with no target went ahead (rc=$RC)"

  fixture; subject_json; export DROP_EDGES="sub-1>dz-impl"
  run_block arm-implementation-dispatch "$sh"
  stopped && not_logged "dz-impl dz-design" && not_logged "deferred-dispatch" \
    && ok "[$sh] arm-impl: an unread wait of the subject stops before the design's edge" \
    || bad "[$sh] arm-impl: an unread wait of the subject was trusted (rc=$RC)"

  fixture; subject_json; export DROP_EDGES="dz-impl>dz-design"
  run_block arm-implementation-dispatch "$sh"
  stopped && not_logged "deferred-dispatch" && [ "$(meta sub-1 gc.impl_armed)" = "<absent>" ] \
    && ok "[$sh] arm-impl gated: a design edge that does not read back stops before the arm" \
    || bad "[$sh] arm-impl gated: an unread design edge was trusted (rc=$RC)"

  # resume: both edges are there from the failed first pass, bd refuses both duplicates
  fixture '.[1]._deps += [{id: "dz-impl", dependency_type: "blocks"}] | .[3]._deps += [{id: "dz-design", dependency_type: "blocks"}]'; subject_json
  run_block arm-implementation-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-impl gated resume: existing edges that read back are armed and stamped"
  eq "$(count "deferred-dispatch arm")" "1" "[$sh] arm-impl gated resume: the child is armed once"
  [ "$(grep -c 'reading the edge back' "$TMP/block.err")" = "2" ] \
    && ok "[$sh] arm-impl gated resume: both refused adds are reported" || bad "[$sh] arm-impl gated resume: a refused add passed silently"

  fixture; subject_json; export ARM_RC=1
  run_block arm-implementation-dispatch "$sh"
  stopped && [ "$(meta sub-1 gc.impl_armed)" = "<absent>" ] \
    && ok "[$sh] arm-impl gated: a failed deferred arm leaves the marker unstamped" || bad "[$sh] arm-impl gated: a failed arm still stamped (rc=$RC)"

  fixture; subject_json; export UPDATE_FAIL="sub-1:gc.impl_armed"
  run_block arm-implementation-dispatch "$sh"
  stopped && ok "[$sh] arm-impl: a marker that does not record fails the step" || bad "[$sh] arm-impl: an unrecorded marker passed"

  # --- arm-implementation-dispatch, all-in-one ---
  fixture; subject_json; export DESIGN_GATED=false
  run_block arm-implementation-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-impl all-in-one: a verified wait slings the child now"
  logged "sling rig/gc-toolkit.polecat dz-impl --on mol-polecat-work" && not_logged "--merge" \
    && ok "[$sh] arm-impl all-in-one: the child is slung with no merge strategy" || bad "[$sh] arm-impl all-in-one: not slung as written"
  [ "$(waits_on dz-impl dz-design)" = "0" ] && not_logged "deferred-dispatch" \
    && ok "[$sh] arm-impl all-in-one: no design edge and no deferred arm" || bad "[$sh] arm-impl all-in-one: held behind the design anyway"

  fixture; subject_json; export DESIGN_GATED=false DROP_EDGES="sub-1>dz-impl"
  run_block arm-implementation-dispatch "$sh"
  stopped && not_logged "gc sling" && ok "[$sh] arm-impl all-in-one: an unread wait slings nothing" \
    || bad "[$sh] arm-impl all-in-one: slung over an unread wait (rc=$RC)"

  fixture; subject_json; export ARMED=1
  run_block arm-implementation-dispatch "$sh"
  eq "$RC" "0" "[$sh] arm-impl: an armed subject is a no-op"
  [ -s "$GC_LOG" ] && bad "[$sh] arm-impl: an armed subject still wrote" || ok "[$sh] arm-impl: an armed subject writes nothing"

  # --- summary-task-create ---
  fixture; subject_json; export NEXT_ID=sum-1
  run_block summary-task-create "$sh"
  eq "$RC" "0" "[$sh] summary create: the summary task is filed"
  eq "$(parents sum-1)" "ep-1" "[$sh] summary create: it is filed under the subject's epic, beside the subject"
  eq "$(meta sum-1 target)" "<absent>" "[$sh] summary create: it carries no target"
  says sum-1 "pr_summary of sub-1" && ok "[$sh] summary create: its description names the subject it writes for" \
    || bad "[$sh] summary create: its description does not name the subject"
  eq "$(meta sub-1 gc.summary_task)" "sum-1" "[$sh] summary create: gc.summary_task is recorded on the subject"

  fixture '.[1]._deps = []'; subject_json; export NEXT_ID=sum-1
  run_block summary-task-create "$sh"
  eq "$RC $(parents sum-1)" "0 " "[$sh] summary create: a subject with no epic gives the task no parent"

  fixture '.[0].issue_type = "task"'; subject_json; export NEXT_ID=sum-1
  run_block summary-task-create "$sh"
  eq "$RC $(parents sum-1)" "0 " "[$sh] summary create: a parent that is not an epic is not the task's"

  fixture; subject_json; export CREATE_FAIL=1
  run_block summary-task-create "$sh"
  stopped && reported "simulated refusal" && [ "$(meta sub-1 gc.summary_task)" = "<absent>" ] \
    && ok "[$sh] summary create: a refused create reports bd's reason and records nothing" || bad "[$sh] summary create: a refused create passed (rc=$RC)"

  fixture; subject_json; export SUMMARY_TASK=sum-1
  run_block summary-task-create "$sh"
  eq "$RC" "0" "[$sh] summary create: a filed task is not filed again"
  not_logged "bd create" && ok "[$sh] summary create: …and nothing is created" || bad "[$sh] summary create: a second task was filed"

  # --- summary-task-arm ---
  SUMMARY_ROW='{id: "sum-1", title: "summary: the PR for Rebuild the widget", issue_type: "task", status: "open", assignee: "", description: "", metadata: {}, _deps: [{id: "ep-1", dependency_type: "parent-child"}]}'
  fixture ". + [$SUMMARY_ROW]"; subject_json; export SUMMARY_TASK=sum-1
  run_block summary-task-arm "$sh"
  eq "$RC" "0" "[$sh] summary arm: edges that read back arm the task"
  eq "$(waits_on sum-1 dz-design) $(waits_on sum-1 dz-impl)" "1 1" "[$sh] summary arm: the task waits on both children"
  eq "$(waits_on sub-1 sum-1)" "1" "[$sh] summary arm: the subject waits on the task"
  logged "deferred-dispatch arm sum-1 --target rig/gc-toolkit.polecat --sling-arg --on --sling-arg mol-polecat-report" \
    && ok "[$sh] summary arm: the task is armed to the polecat pool on mol-polecat-report" || bad "[$sh] summary arm: no arm on mol-polecat-report"
  before "bd dep list sub-1" "deferred-dispatch arm" && ok "[$sh] summary arm: the arm follows the last read-back" \
    || bad "[$sh] summary arm: armed before every edge read back"
  eq "$(meta sub-1 gc.summary_armed)" "1" "[$sh] summary arm: gc.summary_armed is stamped"

  for edge in "sum-1>dz-design" "sum-1>dz-impl" "sub-1>sum-1"; do
    fixture ". + [$SUMMARY_ROW]"; subject_json; export SUMMARY_TASK=sum-1 DROP_EDGES="$edge"
    run_block summary-task-arm "$sh"
    stopped && not_logged "deferred-dispatch" && [ "$(meta sub-1 gc.summary_armed)" = "<absent>" ] \
      && ok "[$sh] summary arm: an edge $edge that does not read back fails the step with nothing armed" \
      || bad "[$sh] summary arm: an unread edge $edge was trusted (rc=$RC)"
  done

  # resume: every edge is there from a pass whose arm failed
  fixture ". + [$SUMMARY_ROW]"; subject_json; export SUMMARY_TASK=sum-1 ARM_RC=1
  run_block summary-task-arm "$sh"
  stopped && [ "$(meta sub-1 gc.summary_armed)" = "<absent>" ] \
    && ok "[$sh] summary arm: a failed arm leaves the marker unstamped" || bad "[$sh] summary arm: a failed arm stamped the marker (rc=$RC)"
  export ARM_RC=0
  run_block summary-task-arm "$sh"
  eq "$RC" "0" "[$sh] summary arm resume: edges that already read back arm the task"
  eq "$(count "deferred-dispatch arm")" "1" "[$sh] summary arm resume: …once"
  [ "$(grep -c 'reading the edge back' "$TMP/block.err")" = "3" ] \
    && ok "[$sh] summary arm resume: the three refused adds are reported" || bad "[$sh] summary arm resume: a refused add passed silently"

  fixture ". + [$SUMMARY_ROW]"; subject_json; export SUMMARY_TASK=sum-1 UPDATE_FAIL="sub-1:gc.summary_armed"
  run_block summary-task-arm "$sh"
  stopped && ok "[$sh] summary arm: a marker that does not record fails the step" || bad "[$sh] summary arm: an unrecorded marker passed"

  fixture ". + [$SUMMARY_ROW]"; subject_json; export SUMMARY_TASK=sum-1 ARMED=1
  run_block summary-task-arm "$sh"
  eq "$RC" "0" "[$sh] summary arm: an armed subject is a no-op"
  [ -s "$GC_LOG" ] && bad "[$sh] summary arm: an armed subject still wrote" || ok "[$sh] summary arm: an armed subject writes nothing"
done

echo
echo "mol-design-convoy-arm: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
