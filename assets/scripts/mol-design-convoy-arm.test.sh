#!/usr/bin/env bash
# Hermetic test for mol-design-convoy's gate-shape resolution, its branch cut,
# the steps that file its children and its summary task, and the step that
# hands its subject to the refinery and dispatches the work. It also runs the
# work skill's recipe that stands an integration effort up by hand.
#
# design-gated-resolve turns the design_gated var into exactly true or false.
# It reads the value case-insensitively and falls back to the design-gated
# default on anything it does not recognize, so a typo never drops the design
# gate. load-context, file-design, file-implementation and dispatch each carry a
# copy, and the copies must stay identical.
#
# seed-branch-cut cuts integration/<subject> from the default branch with one
# create-only push, and records the branch and the default branch on the
# subject, which is the effort's landing bead. A refused push after which origin
# carries the branch is an earlier pass's cut, a subject that records the branch
# is cut no further, and a subject that records another branch or lands
# elsewhere is refused. The cut is the marked blocks effort-default-branch and
# effort-branch-push, which the work skill's recipe carries too. The copies must
# stay identical, so both ways of standing an effort up cut from the branch
# origin/HEAD names, a default other than main included.
#
# The filing steps file each child with the integration branch as its target in
# its create, under the subject's epic when it has one, make the subject wait on
# it, hold the implementation behind a gated design, and file the summary task
# under the subject's epic with no target, waiting on both children with the
# subject waiting on it. Each create and each add takes its exit, and one that
# exits non-zero stops its step. An edge is written only when both its ends
# carry the subject's id prefix, which names the store that holds it. None of
# them assigns the subject or dispatches anything, so a setup that stops between
# steps leaves no child in flight, and no child can land while the subject waits
# on fewer than all of them. The dispatch step reads nothing back: it hands the
# subject to the refinery with its notice, slings the design child
# (--merge mr when gated), arms the implementation behind the design or slings
# it, and arms the summary task on mol-polecat-report. It stamps each marker
# (gc.design_armed, gc.impl_armed, gc.summary_armed) right after its own
# dispatch, because a resume skips a dispatch whose marker is set. Each failure
# case breaks one write or read and checks that nothing downstream of it ran.
#
# A resume re-runs every add on edges the failed pass may already have written,
# and bd takes an edge it already holds as a no-op that exits 0, so the resume
# cases run each add over an edge already there and check that the step
# completes, the edge single.
#
# The work skill's recipe (skills/work/integration-effort.md) runs with its
# placeholders filled in: it cuts from origin/HEAD's branch and records it as
# the landing bead's target, files every bead and the summary task with their
# waits before it hands the landing bead over, stops on a write that exits
# non-zero, and dispatches only after that. Its block for a bead that joins later makes the undispatched
# summary task wait on the bead, never the reverse, and refuses a summary task
# that has been dispatched, or whose beads have all closed so that a pass may
# already be slinging it. Its hand-off that brings the effort's branch current
# goes to the rig's refinery with its notice, waits on the outside work, names
# the landing bead, and carries no branch, so the refinery's patrol never takes
# it to land.
#
# EXECUTES the real snippets extracted verbatim between the formula markers and
# from the recipe's fenced blocks, so the test cannot drift from the shipped
# instruction. No live city or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-design-convoy.toml"
RECIPE_FILE="$ROOT/skills/work/integration-effort.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-design-convoy-arm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }
[ -f "$RECIPE_FILE" ] || { echo "effort recipe not found: $RECIPE_FILE" >&2; exit 1; }

# extract_copy <marker> <n> [file]: the lines of the n-th marked copy
# (exclusive) in the formula, or in <file>.
extract_copy() {
  awk -v m="$1" -v want="$2" '
    $0 ~ ("# >>> " m "$") {n++; f=(n == want); next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "${3:-$TOML}"
}
copies() { grep -c -- "# >>> $1\$" "${2:-$TOML}" || true; }
# unindented <marker> <file>: the first marked copy in <file> with each line's
# leading whitespace taken off, so a copy nested in an if body compares equal to
# one at the top of a recipe.
unindented() { extract_copy "$1" 1 "$2" | sed 's/^[[:space:]]*//'; }
# fenced_block <file> <text>: the fenced bash block of <file> that holds <text>.
fenced_block() {
  awk -v m="$2" '
    /^```/ {
      if (inb) { if (hit) { printf "%s", buf; exit } inb = 0; buf = ""; hit = 0 }
      else if ($0 ~ /^```bash[ \t]*$/) inb = 1
      next
    }
    inb { buf = buf $0 "\n"; if (index($0, m)) hit = 1 }
  ' "$1"
}

BLOCKS="seed-branch-cut file-design-create file-design-wait file-implementation-create file-implementation-wait summary-task-create summary-task-wait setup-dispatch"
SHARED="effort-default-branch effort-branch-push"

# --- static pins ---------------------------------------------------------------

for m in design-gated-resolve $BLOCKS $SHARED; do
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
for m in $BLOCKS $SHARED; do
  eq "$(copies "$m")" "1" "$m has one copy in the formula"
done

eq "$(copies design-gated-resolve)" "4" "design-gated-resolve has four copies (load-context, file-design, file-implementation, dispatch)"
if [ "$(extract_copy design-gated-resolve 1)" = "$(extract_copy design-gated-resolve 2)" ] \
   && [ "$(extract_copy design-gated-resolve 1)" = "$(extract_copy design-gated-resolve 3)" ] \
   && [ "$(extract_copy design-gated-resolve 1)" = "$(extract_copy design-gated-resolve 4)" ]; then
  ok "the design-gated-resolve copies are identical"
else
  bad "the design-gated-resolve copies differ — load-context would report a shape the later steps do not act on"
fi

# The branch cut is one rule in two places: the formula's seed step and the
# work skill's recipe for standing an effort up by hand.
for m in $SHARED; do
  eq "$(copies "$m" "$RECIPE_FILE")" "1" "$m has one copy in the work skill's recipe"
  if [ -n "$(unindented "$m" "$TOML")" ] && [ "$(unindented "$m" "$TOML")" = "$(unindented "$m" "$RECIPE_FILE")" ]; then
    ok "the work skill's $m is the formula's"
  else
    bad "the work skill's $m differs from the formula's — the two recipes would cut an effort's branch from different bases"
  fi
done
if grep -qF 'refs/remotes/origin/main' "$RECIPE_FILE" || grep -qE 'target=("?)main' "$RECIPE_FILE"; then
  bad "the work skill's recipe names main itself instead of the default branch the cut resolved"
else
  ok "the work skill's recipe takes the default branch from the cut, never main by name"
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
eq "$(grep -c 'gc runtime drain-ack' "$TOML")" "1" "one step drains: the dispatch step, the last"
# Only the dispatch step hands the subject over or dispatches anything.
for m in file-design-create file-design-wait file-implementation-create file-implementation-wait summary-task-create summary-task-wait; do
  if grep -qE 'gc sling|deferred-dispatch|--assignee' <<< "$(extract_copy "$m" 1)"; then
    bad "$m hands the subject over or dispatches — only the dispatch step may, once the whole setup is filed"
  else
    ok "$m neither hands the subject over nor dispatches"
  fi
done

# in_shell <shell> <script>: runs the script the way every case does. zsh runs
# with -f, because a plain zsh runs its home's .zshenv before the script, and a
# .zshenv that puts Homebrew first on PATH sets the real git ahead of the stubs.
in_shell() { if [ "$1" = zsh ]; then zsh -f "$2"; else "$1" "$2"; fi; }

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
  SHELLS+=(zsh)
  # This .zshenv stops any zsh that reads it, so a case that starts a plain zsh
  # fails in every home, not only in a home whose own .zshenv gets in the way.
  mkdir -p "$TMP/zdot"
  printf 'exit 7\n' > "$TMP/zdot/.zshenv"
  export ZDOTDIR="$TMP/zdot"
  printf ':\n' > "$TMP/noop.sh"
  RC=0; zsh "$TMP/noop.sh" || RC=$?
  eq "$RC" "7" "(premise) a plain zsh runs the .zshenv before its script"
  RC=0; in_shell zsh "$TMP/noop.sh" || RC=$?
  eq "$RC" "0" "the zsh every case runs reads no startup file"
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
  in_shell "$sh" "$TMP/resolve.sh" 2> "$TMP/resolve.err"
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
# one line each. A `bd --rig <rig>` call is answered from the same store. Failure
# injection, each a space-separated list:
#   REFUSE_EDGES  "<a>><b>" pairs whose `dep add` exits 1 and writes nothing
#   UPDATE_FAIL   "<id>:<key>" (or "<id>:assignee") whose `update` exits 1 and
#                 writes nothing
#   SHOW_FAIL     ids whose `show` answers nothing
#   CREATE_FAIL   the ids whose create bd refuses, or 1, which refuses every
#                 create
# and NEXT_ID (the id a create files) or NEXT_IDS (the ids successive creates
# file, in order), SLING_RC, ROSTER_FILE (what `agent list --json` prints) and
# ROSTER_FAIL. A create takes its title
# from --title or its first plain argument, and its --deps entries as bd does: a
# bare id or <type>:<id> makes the new bead depend on it, and blocks:<id> makes
# <id> wait on the new bead. A dep add over an edge of the same type the store
# already holds is a no-op that exits 0, as bd's is, and one of another type
# onto the same pair exits 1. An update's --if-assignee is the guard bd
# applies, exiting 13 on a mismatch. `rig list` names the one rig, "rig", at
# RIG_ROOT, and `<binding> scripts-dir` prints SCRIPTS. A read the gctk under
# test makes is answered from the same store through holds-store.stub.sh, and
# is not logged, so the log holds only what the block itself ran.
mkdir -p "$TMP/bin" "$TMP/rig"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
if [ -n "${HOLDS_STUB_READ:-}" ] && [ "${1:-}" = bd ]; then
  shift
  HOLDS_STORE="$STORE" exec "${HOLDS_STUB:?}" answer "$@"
fi
printf 'gc %s' "$*" | tr '\n' ' ' >> "$GC_LOG"; printf '\n' >> "$GC_LOG"
listed() { case " ${1:-} " in *" $2 "*) return 0 ;; esac; return 1; }
put() { jq -c "$@" "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"; }
[ "${1:-}" = "bd" ] && [ "${2:-}" = "--rig" ] && set -- bd "${@:4}"
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
    shift 2; title=""; desc=""; meta='{}'; parent=""; deps=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) title="$2"; shift 2 ;;
        -d) desc="$2"; shift 2 ;;
        --metadata) meta="$2"; shift 2 ;;
        --parent) parent="$2"; shift 2 ;;
        --deps) deps="$2"; shift 2 ;;
        -t) shift 2 ;;
        -*) shift ;;
        *) [ -n "$title" ] || title="$1"; shift ;;
      esac
    done
    if [ -n "${NEXT_IDS:-}" ]; then
      n=$(( $(cat "$STORE.creates" 2>/dev/null || echo 0) + 1 )); printf '%s\n' "$n" > "$STORE.creates"
      new=$(printf '%s\n' $NEXT_IDS | sed -n "${n}p")
    else
      new="$NEXT_ID"
    fi
    { [ "${CREATE_FAIL:-}" = 1 ] || listed "${CREATE_FAIL:-}" "$new"; } && { echo '{"error":"simulated refusal"}'; exit 1; }
    put --arg id "$new" --arg t "$title" --arg d "$desc" --argjson m "$meta" --arg p "$parent" \
      '. + [{id: $id, title: $t, issue_type: "task", status: "open", assignee: "", description: $d, metadata: $m,
             _deps: (if $p == "" then [] else [{id: $p, dependency_type: "parent-child"}] end)}]'
    for dep in $(printf '%s' "$deps" | tr ',' ' '); do
      case "$dep" in
        blocks:*) a="${dep#blocks:}"; b="$new"; t=blocks ;;
        *:*) a="$new"; b="${dep#*:}"; t="${dep%%:*}" ;;
        *) a="$new"; b="$dep"; t=blocks ;;
      esac
      put --arg a "$a" --arg b "$b" --arg t "$t" 'map(if .id == $a then ._deps = ((._deps // []) + [{id: $b, dependency_type: $t}]) else . end)'
    done
    jq -nc --arg id "$new" '{id: $id}'
    exit 0 ;;
  "bd dep")
    case "${3:-}" in
      add)
        a="$4"; b="$5"; t="${6#--type=}"
        listed "${REFUSE_EDGES:-}" "$a>$b" && { echo "Error: refused" >&2; exit 1; }
        # bd takes an edge of the same type it already holds as a no-op that
        # exits 0, and refuses one of another type onto the same pair.
        if jq -e --arg a "$a" --arg b "$b" --arg t "$t" 'any(.[]; .id == $a and any((._deps // [])[]; .id == $b and .dependency_type == $t))' "$STORE" >/dev/null; then
          echo "Added dependency: $a depends on $b ($t)"; exit 0
        fi
        if jq -e --arg a "$a" --arg b "$b" 'any(.[]; .id == $a and any((._deps // [])[]; .id == $b))' "$STORE" >/dev/null; then
          echo "Error: $a already depends on $b by another type" >&2; exit 1
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
  "rig list")
    jq -nc --arg p "$RIG_ROOT" '{rigs: [{name: "rig", path: $p}]}'; exit 0 ;;
  "gc-toolkit scripts-dir")
    printf '%s\n' "$SCRIPTS"; exit 0 ;;
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
# The late-join block asks gctk bead holds what holds the summary task, from the
# gctk built from this checkout.
export HOLDS_STUB="$HERE/holds-store.stub.sh" GC_NO_API=1
GCTK_BIN="$("$HOLDS_STUB" build "$TMP/gctk")" || { echo "FAIL - gctk did not build, so the late-join block cannot run"; exit 1; }
export GCTK_BIN
export SUBJECT="dz-sub" BRANCH="integration/dz-sub" INITIATIVE="Rebuild the widget"
printf '%s\n' '{"agents":[{"qualified_name":"rig/gc-toolkit.polecat"},{"qualified_name":"rig/gc-toolkit.refinery"}]}' > "$ROSTER_FILE"

# fixture [<jq edit>]: a store holding the subject dz-sub under the epic ep-1,
# with its planned work in its description and nothing recorded on it, and the
# design and implementation children dz-design and dz-impl, each filed with the
# integration branch as its target. The edit, when given, changes it. Every
# injected failure is reset.
fixture() {
  jq -nc '[
    {id: "ep-1", title: "The widget epic", issue_type: "epic", status: "open", assignee: "", description: "", metadata: {}, _deps: []},
    {id: "dz-sub", title: "Rebuild the widget", issue_type: "task", status: "open", assignee: "",
     description: "Plan: rebuild the widget renderer and retire the old cache.", metadata: {},
     _deps: [{id: "ep-1", dependency_type: "parent-child"}]},
    {id: "dz-design", title: "design: Rebuild the widget", issue_type: "task", status: "open", assignee: "", description: "", metadata: {target: "integration/dz-sub"}, _deps: []},
    {id: "dz-impl", title: "implement: Rebuild the widget per its design", issue_type: "task", status: "open", assignee: "", description: "", metadata: {target: "integration/dz-sub"}, _deps: []}
  ]' > "$STORE"
  [ -z "${1:-}" ] || { jq -c "$1" "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"; }
  rm -f "$STORE.creates"
  printf 'main\n' > "$ORIGIN_REFS"
  export ORIGIN_HEAD=main FETCH_RC=0 PUSH_FAIL="" REFUSE_EDGES="" UPDATE_FAIL="" SHOW_FAIL="" \
    CREATE_FAIL="" NEXT_ID="" NEXT_IDS="" SLING_RC=0 ARM_RC=0 NOTIFY_RC=0 ROSTER_FAIL="" \
    DESIGN_ARMED="" IMPL_ARMED="" SUMMARY_ARMED=""
  export DESIGN_CHILD="dz-design" IMPL_CHILD="dz-impl" SUMMARY_TASK=""
}
# subject_json: the subject as the step's derive block reads it.
subject_json() { SUBJECT_JSON="$(PATH="$TMP/bin:$PATH" GC_LOG=/dev/null gc bd show "$SUBJECT" --json)"; export SUBJECT_JSON; }
# The rows and edges of a whole setup: the summary task dz-sum under the epic,
# waiting on both children, and the subject waiting on both children and on it.
SUMMARY_ROW='{id: "dz-sum", title: "summary: the PR for Rebuild the widget", issue_type: "task", status: "open", assignee: "", description: "", metadata: {}, _deps: [{id: "ep-1", dependency_type: "parent-child"}]}'
WIRED='. + ['"$SUMMARY_ROW"'] | map(if .id == "dz-sub" then ._deps += [{id: "dz-design", dependency_type: "blocks"}, {id: "dz-impl", dependency_type: "blocks"}, {id: "dz-sum", dependency_type: "blocks"}]
  elif .id == "dz-sum" then ._deps += [{id: "dz-design", dependency_type: "blocks"}, {id: "dz-impl", dependency_type: "blocks"}]
  elif .id == "dz-impl" then ._deps += [{id: "dz-design", dependency_type: "blocks"}] else . end)
  | map(if .id == "dz-sub" then .metadata += {branch: "integration/dz-sub", target: "main", "gc.design_child": "dz-design", "gc.impl_child": "dz-impl", "gc.summary_task": "dz-sum"} else . end)'
# wired [<jq edit>]: fixture with the whole design-gated setup in place, then the edit.
wired() { fixture "$WIRED${1:+ | $1}"; subject_json; export SUMMARY_TASK=dz-sum DESIGN_GATED=true; }

# run_block <marker> <shell>: runs the marked block with the step's variables
# in the environment and the stubs first on PATH. Sets RC; the call log is
# $GC_LOG. A sentinel after the block records whether execution ran past it:
# the step's contract is that a failed write stops it, not merely that the
# block's last command happened to fail.
run_block() {
  local m="$1" sh="$2"
  { extract_copy "$m" 1; printf 'printf "past\\n" > "%s"\n' "$TMP/past.flag"; } > "$TMP/block.sh"
  run_file "$sh"
}
# run_file <shell>: runs $TMP/block.sh as run_block does.
run_file() {
  : > "$GC_LOG"; rm -f "$TMP/past.flag"
  RC=0
  PATH="$TMP/bin:$PATH" in_shell "$1" "$TMP/block.sh" >"$TMP/block.out" 2>"$TMP/block.err" || RC=$?
}
logged()     { grep -qF -- "$1" "$GC_LOG"; }
not_logged() { ! grep -qF -- "$1" "$GC_LOG"; }
count()      { grep -cF -- "$1" "$GC_LOG" || true; }
stopped()    { [ "$RC" -ne 0 ] && [ ! -e "$TMP/past.flag" ]; }
reported()   { grep -qF -- "$1" "$TMP/block.err"; }
# released: the run handed nothing over and dispatched nothing.
released()   { grep -qE 'gc sling|deferred-dispatch|--assignee' "$GC_LOG"; }
# meta <id> <key>: the key as the store holds it, or <absent>.
meta()       { jq -r --arg id "$1" --arg k "$2" '.[] | select(.id == $id) | .metadata[$k] // "<absent>"' "$STORE"; }
field()      { jq -r --arg id "$1" --arg f "$2" '.[] | select(.id == $id) | .[$f] // "<absent>"' "$STORE"; }
waits_on()   { jq -r --arg a "$1" --arg b "$2" '[.[] | select(.id == $a) | (._deps // [])[] | select(.id == $b and .dependency_type == "blocks")] | length' "$STORE"; }
# open_blockers <id>: the bead's blocks edges onto beads still open, space-joined.
open_blockers() { jq -r --arg id "$1" '. as $s | [.[] | select(.id == $id) | (._deps // [])[] | select(.dependency_type == "blocks") | .id as $b
                    | select(($s | map(select(.id == $b)) | .[0].status // "open") != "closed") | $b] | join(" ")' "$STORE"; }
# parents <id>: the bead's parent-child parents, space-joined, or nothing.
parents()    { jq -r --arg id "$1" '[.[] | select(.id == $id) | (._deps // [])[] | select(.dependency_type == "parent-child") | .id] | join(" ")' "$STORE"; }
# line_of <text>: the number of the first log line holding <text>, or 0.
line_of()    { awk -v t="$1" 'index($0, t) { print NR; f = 1; exit } END { if (!f) print 0 }' "$GC_LOG"; }
# last_line_of <text>: the number of the last log line holding <text>, or 0.
last_line_of() { awk -v t="$1" 'index($0, t) { n = NR } END { print n + 0 }' "$GC_LOG"; }
# says <id> <text>: the bead's description holds <text>.
says()       { case "$(field "$1" description)" in *"$2"*) return 0 ;; esac; return 1; }
before()     { local a b; a=$(line_of "$1"); b=$(line_of "$2"); [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -lt "$b" ]; }
# all_before <text> <text2>: every log line holding <text> precedes the first holding <text2>.
all_before() { local a b; a=$(last_line_of "$1"); b=$(line_of "$2"); [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -lt "$b" ]; }

for sh in "${SHELLS[@]}"; do
  # --- seed-branch-cut ---
  fixture; subject_json
  run_block seed-branch-cut "$sh"
  eq "$RC" "0" "[$sh] seed: a fresh subject is cut and recorded"
  logged "git -C $RIG_ROOT push origin refs/remotes/origin/main:refs/heads/integration/dz-sub --force-with-lease=refs/heads/integration/dz-sub:" \
    && ok "[$sh] seed: one create-only push from the rig's checkout cuts the branch from the default branch" \
    || bad "[$sh] seed: no create-only push of the branch"
  grep -qxF "integration/dz-sub" "$ORIGIN_REFS" && ok "[$sh] seed: origin carries the branch" \
    || bad "[$sh] seed: origin does not carry the branch"
  eq "$(meta dz-sub branch) $(meta dz-sub target)" "integration/dz-sub main" "[$sh] seed: the subject records the branch and the default branch as its target"
  before "fetch --prune origin" "push origin" && ok "[$sh] seed: the cut follows a fetch of origin" \
    || bad "[$sh] seed: the push ran without a fetch before it"

  fixture; subject_json; export ORIGIN_HEAD=trunk; printf 'trunk\n' > "$ORIGIN_REFS"
  run_block seed-branch-cut "$sh"
  eq "$RC $(meta dz-sub target)" "0 trunk" "[$sh] seed: the default branch is the one origin/HEAD names"
  logged "push origin refs/remotes/origin/trunk:refs/heads/integration/dz-sub" \
    && ok "[$sh] seed: …and the branch is cut from it" || bad "[$sh] seed: the branch was not cut from origin/HEAD's branch"

  fixture; subject_json; export ORIGIN_HEAD=""
  run_block seed-branch-cut "$sh"
  eq "$RC $(meta dz-sub target)" "0 main" "[$sh] seed: an unreadable origin/HEAD falls back to main"

  # resume: an earlier pass cut the branch and died before its record landed
  fixture; subject_json; printf 'main\nintegration/dz-sub\n' > "$ORIGIN_REFS"
  run_block seed-branch-cut "$sh"
  eq "$RC" "0" "[$sh] seed resume: a refused push after which origin carries the branch is an earlier cut"
  eq "$(meta dz-sub branch)" "integration/dz-sub" "[$sh] seed resume: …and the branch is recorded"
  grep -qF "already carries" "$TMP/block.out" && ok "[$sh] seed resume: the earlier cut is reported" \
    || bad "[$sh] seed resume: the earlier cut passed silently"

  fixture; subject_json; export PUSH_FAIL=1
  run_block seed-branch-cut "$sh"
  stopped && [ "$(meta dz-sub branch)" = "<absent>" ] \
    && ok "[$sh] seed: a push that fails while origin lacks the branch stops the step with nothing recorded" \
    || bad "[$sh] seed: a failed push was trusted (rc=$RC, branch=$(meta dz-sub branch))"

  fixture; subject_json; export FETCH_RC=1
  run_block seed-branch-cut "$sh"
  stopped && not_logged "push origin" && ok "[$sh] seed: a failed fetch stops the step before the push" \
    || bad "[$sh] seed: the push ran after a failed fetch (rc=$RC)"

  fixture '.[1].metadata = {branch: "integration/dz-sub", target: "main"}'; subject_json
  run_block seed-branch-cut "$sh"
  eq "$RC" "0" "[$sh] seed: a subject that records the branch passes"
  not_logged "git " && ok "[$sh] seed: …and is cut no further" || bad "[$sh] seed: a recorded branch was cut again"

  fixture '.[1].metadata = {branch: "polecat/dz-sub"}'; subject_json
  run_block seed-branch-cut "$sh"
  stopped && not_logged "push origin" && [ "$(meta dz-sub branch)" = "polecat/dz-sub" ] && reported "not this run's to cut" \
    && ok "[$sh] seed: a subject recording another branch keeps it, nothing is cut, and the refusal says why" \
    || bad "[$sh] seed: a subject recording another branch was cut over (rc=$RC)"

  fixture '.[1].metadata = {target: "integration/other"}'; subject_json
  run_block seed-branch-cut "$sh"
  stopped && not_logged "push origin" && [ "$(meta dz-sub target)" = "integration/other" ] \
    && ok "[$sh] seed: a subject that lands inside another branch is not cut" \
    || bad "[$sh] seed: a subject landing inside another branch was cut (rc=$RC)"

  fixture '.[1].metadata = {target: "main"}'; subject_json
  run_block seed-branch-cut "$sh"
  eq "$RC $(meta dz-sub branch)" "0 integration/dz-sub" "[$sh] seed: a subject that already lands on the default branch is cut"

  fixture; subject_json; export UPDATE_FAIL="dz-sub:branch"
  run_block seed-branch-cut "$sh"
  stopped && reported "not filing anything" && ok "[$sh] seed: a record the store refuses stops the step" \
    || bad "[$sh] seed: an unrecorded branch passed (rc=$RC)"

  # --- file-design-create ---
  fixture '.[2:] = []'; subject_json; export DESIGN_CHILD="" NEXT_ID=dz-design DESIGN_GATED=true
  run_block file-design-create "$sh"
  eq "$RC" "0" "[$sh] design create: the design child is filed"
  eq "$(meta dz-design target)" "integration/dz-sub" "[$sh] design create: its target is the integration branch, written in its create"
  eq "$(meta dz-sub gc.design_child)" "dz-design" "[$sh] design create: gc.design_child is recorded on the subject"
  says dz-design "It is a stage" && ok "[$sh] design create: design-gated, the brief says it is a stage" \
    || bad "[$sh] design create: the gated brief does not say the child is a stage"
  eq "$(parents dz-design)" "ep-1" "[$sh] design create: it is filed under the subject's epic, beside the subject"

  fixture '.[2:] = [] | .[1]._deps = []'; subject_json; export DESIGN_CHILD="" NEXT_ID=dz-design DESIGN_GATED=true
  run_block file-design-create "$sh"
  eq "$RC $(parents dz-design)" "0 " "[$sh] design create: a subject with no epic gives the child no parent"

  fixture '.[2:] = []'; subject_json; export DESIGN_CHILD="" NEXT_ID=dz-design DESIGN_GATED=false
  run_block file-design-create "$sh"
  says dz-design "with no PR of its own" && ok "[$sh] design create: all-in-one, the brief says it lands with no PR of its own" \
    || bad "[$sh] design create: the all-in-one brief does not say how it lands"

  fixture '.[2:] = []'; subject_json; export DESIGN_CHILD="" CREATE_FAIL=1
  run_block file-design-create "$sh"
  stopped && reported "simulated refusal" && [ "$(meta dz-sub gc.design_child)" = "<absent>" ] \
    && ok "[$sh] design create: a refused create reports bd's reason and records nothing" \
    || bad "[$sh] design create: a refused create passed (rc=$RC)"

  fixture; subject_json
  run_block file-design-create "$sh"
  eq "$RC" "0" "[$sh] design create: a filed child is not filed again"
  not_logged "bd create" && ok "[$sh] design create: …and nothing is created" || bad "[$sh] design create: a second child was filed"

  # --- file-design-wait ---
  fixture; subject_json; export DESIGN_GATED=true
  run_block file-design-wait "$sh"
  eq "$RC" "0" "[$sh] design wait: a filed child is waited on"
  eq "$(waits_on dz-sub dz-design)" "1" "[$sh] design wait: the subject waits on the design child"
  ! released && [ "$(field dz-sub assignee)" = "" ] \
    && ok "[$sh] design wait: the subject is not handed over and the child is not slung, so a setup that stops here leaves nothing in flight" \
    || bad "[$sh] design wait: handed over or dispatched before the rest of the setup existed"

  fixture; subject_json; export REFUSE_EDGES="dz-sub>dz-design"
  run_block file-design-wait "$sh"
  stopped && reported "refused the wait" && ok "[$sh] design wait: an add bd refuses fails the step" \
    || bad "[$sh] design wait: a refused add passed (rc=$RC)"

  fixture; subject_json; export DESIGN_CHILD=xx-design
  run_block file-design-wait "$sh"
  stopped && not_logged "dep add" && reported "another store" \
    && ok "[$sh] design wait: a child in another store gets no edge, since one would hold nothing" \
    || bad "[$sh] design wait: an edge onto another store's bead was written (rc=$RC)"

  # resume: the edge is there from the failed first pass, and bd's re-add is a no-op
  fixture '.[1]._deps += [{id: "dz-design", dependency_type: "blocks"}]'; subject_json
  run_block file-design-wait "$sh"
  eq "$RC $(waits_on dz-sub dz-design)" "0 1" "[$sh] design wait resume: a wait already there completes the step, once"

  # --- file-implementation-create ---
  fixture '.[3:] = []'; subject_json; export IMPL_CHILD="" NEXT_ID=dz-impl DESIGN_GATED=true
  run_block file-implementation-create "$sh"
  eq "$RC" "0" "[$sh] impl create: the implementation child is filed"
  eq "$(meta dz-impl target)" "integration/dz-sub" "[$sh] impl create: its target is the integration branch, written in its create"
  eq "$(meta dz-sub gc.impl_child)" "dz-impl" "[$sh] impl create: gc.impl_child is recorded on the subject"
  eq "$(parents dz-impl)" "ep-1" "[$sh] impl create: it is filed under the subject's epic"
  says dz-impl "gc.summary_task" && says dz-impl "target=integration/dz-sub" \
    && ok "[$sh] impl create: its brief gives a bead it splits into the same writes, the summary task's wait among them" \
    || bad "[$sh] impl create: the brief does not give a split bead its writes"

  fixture '.[3:] = []'; subject_json; export IMPL_CHILD="" CREATE_FAIL=1
  run_block file-implementation-create "$sh"
  stopped && [ "$(meta dz-sub gc.impl_child)" = "<absent>" ] && ok "[$sh] impl create: a refused create records nothing" \
    || bad "[$sh] impl create: a refused create passed (rc=$RC)"

  # --- file-implementation-wait ---
  fixture; subject_json; export DESIGN_GATED=true
  run_block file-implementation-wait "$sh"
  eq "$RC" "0" "[$sh] impl wait gated: verified waits complete the step"
  eq "$(waits_on dz-sub dz-impl)" "1" "[$sh] impl wait: the subject waits on the implementation child"
  eq "$(waits_on dz-impl dz-design)" "1" "[$sh] impl wait gated: the design child blocks the implementation (operand order)"
  ! released && ok "[$sh] impl wait gated: nothing is armed or slung" || bad "[$sh] impl wait gated: dispatched before the summary task existed"

  fixture; subject_json; export DESIGN_GATED=false
  run_block file-implementation-wait "$sh"
  eq "$RC" "0" "[$sh] impl wait all-in-one: the subject's wait alone completes the step"
  [ "$(waits_on dz-impl dz-design)" = "0" ] && ok "[$sh] impl wait all-in-one: no design edge holds it" \
    || bad "[$sh] impl wait all-in-one: held behind the design anyway"
  ! released && ok "[$sh] impl wait all-in-one: the child is not slung before the summary task is filed" \
    || bad "[$sh] impl wait all-in-one: the implementation started before gc.summary_task existed"

  fixture; subject_json; export DESIGN_GATED=true REFUSE_EDGES="dz-sub>dz-impl"
  run_block file-implementation-wait "$sh"
  stopped && not_logged "dz-impl dz-design" && ok "[$sh] impl wait: a refused wait of the subject stops before the design's edge" \
    || bad "[$sh] impl wait: a refused wait of the subject went ahead (rc=$RC)"

  fixture; subject_json; export DESIGN_GATED=true REFUSE_EDGES="dz-impl>dz-design"
  run_block file-implementation-wait "$sh"
  stopped && ok "[$sh] impl wait gated: a design edge bd refuses fails the step" \
    || bad "[$sh] impl wait gated: a refused design edge passed (rc=$RC)"

  fixture; subject_json; export DESIGN_GATED=true IMPL_CHILD=xx-impl
  run_block file-implementation-wait "$sh"
  stopped && not_logged "dep add" && reported "another store" \
    && ok "[$sh] impl wait: a child in another store gets no edge, since one would hold nothing" \
    || bad "[$sh] impl wait: an edge onto another store's bead was written (rc=$RC)"

  # resume: both edges are there from the failed first pass, and bd's re-adds are no-ops
  fixture '.[1]._deps += [{id: "dz-impl", dependency_type: "blocks"}] | .[3]._deps += [{id: "dz-design", dependency_type: "blocks"}]'; subject_json
  export DESIGN_GATED=true
  run_block file-implementation-wait "$sh"
  eq "$RC $(waits_on dz-sub dz-impl) $(waits_on dz-impl dz-design)" "0 1 1" "[$sh] impl wait gated resume: edges already there complete the step, once each"

  # --- summary-task-create ---
  fixture; subject_json; export NEXT_ID=dz-sum
  run_block summary-task-create "$sh"
  eq "$RC" "0" "[$sh] summary create: the summary task is filed"
  eq "$(parents dz-sum)" "ep-1" "[$sh] summary create: it is filed under the subject's epic, beside the subject"
  eq "$(meta dz-sum target)" "<absent>" "[$sh] summary create: it carries no target"
  says dz-sum "pr_summary of dz-sub" && ok "[$sh] summary create: its description names the subject it writes for" \
    || bad "[$sh] summary create: its description does not name the subject"
  eq "$(meta dz-sub gc.summary_task)" "dz-sum" "[$sh] summary create: gc.summary_task is recorded on the subject"

  fixture '.[1]._deps = []'; subject_json; export NEXT_ID=dz-sum
  run_block summary-task-create "$sh"
  eq "$RC $(parents dz-sum)" "0 " "[$sh] summary create: a subject with no epic gives the task no parent"

  fixture '.[0].issue_type = "task"'; subject_json; export NEXT_ID=dz-sum
  run_block summary-task-create "$sh"
  eq "$RC $(parents dz-sum)" "0 " "[$sh] summary create: a parent that is not an epic is not the task's"

  fixture; subject_json; export CREATE_FAIL=1
  run_block summary-task-create "$sh"
  stopped && reported "simulated refusal" && [ "$(meta dz-sub gc.summary_task)" = "<absent>" ] \
    && ok "[$sh] summary create: a refused create reports bd's reason and records nothing" || bad "[$sh] summary create: a refused create passed (rc=$RC)"

  fixture; subject_json; export SUMMARY_TASK=dz-sum
  run_block summary-task-create "$sh"
  eq "$RC" "0" "[$sh] summary create: a filed task is not filed again"
  not_logged "bd create" && ok "[$sh] summary create: …and nothing is created" || bad "[$sh] summary create: a second task was filed"

  # --- summary-task-wait ---
  fixture ". + [$SUMMARY_ROW]"; subject_json; export SUMMARY_TASK=dz-sum
  run_block summary-task-wait "$sh"
  eq "$RC" "0" "[$sh] summary wait: the three edges complete the step"
  eq "$(waits_on dz-sum dz-design) $(waits_on dz-sum dz-impl)" "1 1" "[$sh] summary wait: the task waits on both children"
  eq "$(waits_on dz-sub dz-sum)" "1" "[$sh] summary wait: the subject waits on the task"
  ! released && ok "[$sh] summary wait: nothing is armed, handed over or slung" || bad "[$sh] summary wait: dispatched from a filing step"

  for edge in "dz-sum>dz-design" "dz-sum>dz-impl" "dz-sub>dz-sum"; do
    fixture ". + [$SUMMARY_ROW]"; subject_json; export SUMMARY_TASK=dz-sum REFUSE_EDGES="$edge"
    run_block summary-task-wait "$sh"
    stopped && ok "[$sh] summary wait: an edge $edge bd refuses fails the step" \
      || bad "[$sh] summary wait: a refused edge $edge passed (rc=$RC)"
  done
  fixture ". + [$SUMMARY_ROW]"; subject_json; export SUMMARY_TASK=xx-sum REFUSE_EDGES=""
  run_block summary-task-wait "$sh"
  stopped && not_logged "dep add" && reported "another store" \
    && ok "[$sh] summary wait: a task in another store gets no edge, since one would hold nothing" \
    || bad "[$sh] summary wait: an edge onto another store's bead was written (rc=$RC)"

  # resume: every edge is there from a failed pass, and bd's three re-adds are no-ops
  fixture ". + [$SUMMARY_ROW] | map(if .id == \"dz-sub\" then ._deps += [{id: \"dz-sum\", dependency_type: \"blocks\"}] elif .id == \"dz-sum\" then ._deps += [{id: \"dz-design\", dependency_type: \"blocks\"}, {id: \"dz-impl\", dependency_type: \"blocks\"}] else . end)"
  subject_json; export SUMMARY_TASK=dz-sum
  run_block summary-task-wait "$sh"
  eq "$RC" "0" "[$sh] summary wait resume: edges already there complete the step"

  # --- a setup that stops between steps leaves nothing in flight ---
  # The filing steps one after another over one store, each from its own shell
  # as a resumed run would be: after each, the subject is with nobody and no
  # child is slung or armed, so nothing can land before the subject waits on
  # every bead. Then the dispatch step hands it over and dispatches.
  for gated in true false; do
    fixture; subject_json; export DESIGN_GATED="$gated" NEXT_ID=dz-sum; INFLIGHT=""
    for m in file-design-wait file-implementation-wait summary-task-create summary-task-wait; do
      [ "$m" = summary-task-wait ] && export SUMMARY_TASK=dz-sum
      run_block "$m" "$sh"
      if [ "$RC" -ne 0 ] || released || [ "$(field dz-sub assignee)" != "" ]; then INFLIGHT="$INFLIGHT $m"; fi
    done
    [ -z "$INFLIGHT" ] && ok "[$sh] setup (design_gated=$gated): no filing step hands the subject over or dispatches a child" \
      || bad "[$sh] setup (design_gated=$gated): a filing step failed, handed over or dispatched:$INFLIGHT"
    jq -c 'map(if .id == "dz-sub" then .metadata += {branch: "integration/dz-sub", target: "main", "gc.design_child": "dz-design", "gc.impl_child": "dz-impl", "gc.summary_task": "dz-sum"} else . end)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    subject_json
    run_block setup-dispatch "$sh"
    [ "$RC" -eq 0 ] && [ "$(field dz-sub assignee)" = "rig/gc-toolkit.refinery" ] && logged "sling rig/gc-toolkit.polecat dz-design" \
      && ok "[$sh] setup (design_gated=$gated): once every wait is filed, the dispatch step hands the subject over and dispatches" \
      || bad "[$sh] setup (design_gated=$gated): the dispatch step did not complete over the filed setup (rc=$RC)"
  done

  # --- setup-dispatch, design-gated ---
  wired
  run_block setup-dispatch "$sh"
  eq "$RC" "0" "[$sh] dispatch gated: a filed setup is handed over and dispatched"
  eq "$(field dz-sub assignee)" "rig/gc-toolkit.refinery" "[$sh] dispatch: the subject is assigned to the refinery"
  logged "deferred-dispatch notify dz-sub --agent rig/gc-toolkit.refinery" \
    && ok "[$sh] dispatch: the notice the assignment owes is recorded" || bad "[$sh] dispatch: no notice"
  logged "sling rig/gc-toolkit.polecat dz-design --on mol-polecat-work --merge mr" \
    && ok "[$sh] dispatch gated: the design child is slung --merge mr, a stage" || bad "[$sh] dispatch gated: not slung as a stage"
  logged "deferred-dispatch arm dz-impl --target rig/gc-toolkit.polecat --sling-arg --on --sling-arg mol-polecat-work" \
    && ok "[$sh] dispatch gated: the implementation is armed behind the design" || bad "[$sh] dispatch gated: no deferred arm of the implementation"
  not_logged "sling rig/gc-toolkit.polecat dz-impl" && ok "[$sh] dispatch gated: the implementation is not slung now" \
    || bad "[$sh] dispatch gated: the implementation was slung before the design closed"
  logged "deferred-dispatch arm dz-sum --target rig/gc-toolkit.polecat --sling-arg --on --sling-arg mol-polecat-report" \
    && ok "[$sh] dispatch: the summary task is armed to the polecat pool on mol-polecat-report" || bad "[$sh] dispatch: no arm on mol-polecat-report"
  eq "$(meta dz-sub gc.design_armed) $(meta dz-sub gc.impl_armed) $(meta dz-sub gc.summary_armed)" "1 1 1" "[$sh] dispatch: the three markers are stamped"
  not_logged "bd dep list" && not_logged "bd show dz-design" && not_logged "bd show dz-impl" \
    && ok "[$sh] dispatch: it reads no target or edge back" \
    || bad "[$sh] dispatch: the setup was read back"
  before "update dz-sub --if-assignee" "deferred-dispatch notify" && before "deferred-dispatch notify" "gc sling" \
    && before "gc sling" "deferred-dispatch arm dz-impl" && before "deferred-dispatch arm dz-impl" "deferred-dispatch arm dz-sum" \
    && ok "[$sh] dispatch: the hand-over and its notice come before any dispatch" \
    || bad "[$sh] dispatch: a dispatch ran before the subject was handed over"

  # --- setup-dispatch, all-in-one ---
  wired 'map(if .id == "dz-impl" then ._deps = [] else . end)'; export DESIGN_GATED=false
  run_block setup-dispatch "$sh"
  eq "$RC" "0" "[$sh] dispatch all-in-one: the step succeeds"
  logged "sling rig/gc-toolkit.polecat dz-design --on mol-polecat-work" && logged "sling rig/gc-toolkit.polecat dz-impl --on mol-polecat-work" && not_logged "--merge" \
    && ok "[$sh] dispatch all-in-one: both children are slung with no merge strategy" \
    || bad "[$sh] dispatch all-in-one: not slung as written"
  not_logged "deferred-dispatch arm dz-impl" && ok "[$sh] dispatch all-in-one: the implementation is not armed behind the design" \
    || bad "[$sh] dispatch all-in-one: held behind the design anyway"

  # --- setup-dispatch refusals: nothing handed over, nothing dispatched ---
  wired
  printf '%s\n' '{"agents":[{"qualified_name":"rig/gc-toolkit.polecat"}]}' > "$ROSTER_FILE"
  run_block setup-dispatch "$sh"
  stopped && ! released && ok "[$sh] dispatch: a refinery address the roster lacks hands nothing over and dispatches nothing" \
    || bad "[$sh] dispatch: handed over to an address no agent holds (rc=$RC)"
  printf '%s\n' '{"agents":[{"qualified_name":"rig/gc-toolkit.polecat"},{"qualified_name":"rig/gc-toolkit.refinery"}]}' > "$ROSTER_FILE"

  wired; export ROSTER_FAIL=1
  run_block setup-dispatch "$sh"
  eq "$RC $(field dz-sub assignee)" "0 rig/gc-toolkit.refinery" "[$sh] dispatch: an unreadable roster hands over unchecked"
  reported "roster unreadable" && ok "[$sh] dispatch: …and says so" || bad "[$sh] dispatch: the unchecked hand-over passed silently"

  wired '.[1].assignee = "someone-else"'
  run_block setup-dispatch "$sh"
  stopped && not_logged "sling" && not_logged "deferred-dispatch" && [ "$(field dz-sub assignee)" = "someone-else" ] \
    && ok "[$sh] dispatch: a subject assigned elsewhere keeps its assignee and nothing is dispatched" \
    || bad "[$sh] dispatch: a subject assigned elsewhere was handed over (rc=$RC)"

  wired; export UPDATE_FAIL="dz-sub:assignee"
  run_block setup-dispatch "$sh"
  stopped && not_logged "deferred-dispatch" && not_logged "sling" \
    && ok "[$sh] dispatch: an assignment that fails neither records the notice nor dispatches" \
    || bad "[$sh] dispatch: went ahead after a failed assignment (rc=$RC)"

  wired; export NOTIFY_RC=1
  run_block setup-dispatch "$sh"
  stopped && not_logged "sling" && not_logged "deferred-dispatch arm" && [ "$(meta dz-sub gc.design_armed)" = "<absent>" ] \
    && ok "[$sh] dispatch: a notice that does not record stops before any dispatch" \
    || bad "[$sh] dispatch: dispatched with no notice recorded (rc=$RC)"

  wired; export SLING_RC=1
  run_block setup-dispatch "$sh"
  stopped && [ "$(meta dz-sub gc.design_armed)" = "<absent>" ] && not_logged "deferred-dispatch arm" \
    && ok "[$sh] dispatch: a failed sling leaves its marker unstamped and dispatches nothing after it" \
    || bad "[$sh] dispatch: a failed sling stamped the marker or went on (rc=$RC)"

  wired; export ARM_RC=1
  run_block setup-dispatch "$sh"
  stopped && [ "$(meta dz-sub gc.impl_armed)" = "<absent>" ] && [ "$(meta dz-sub gc.summary_armed)" = "<absent>" ] \
    && ok "[$sh] dispatch: a failed arm leaves its marker unstamped" || bad "[$sh] dispatch: a failed arm stamped a marker (rc=$RC)"

  for key in gc.design_armed gc.impl_armed gc.summary_armed; do
    wired; export UPDATE_FAIL="dz-sub:$key"
    run_block setup-dispatch "$sh"
    stopped && ok "[$sh] dispatch: a $key that does not record fails the step" || bad "[$sh] dispatch: an unrecorded $key passed"
  done

  # resume: the design child was slung, and landed, before the run stopped
  wired 'map(if .id == "dz-design" then .status = "closed" else . end) | .[1].assignee = "rig/gc-toolkit.refinery"'
  export DESIGN_ARMED=1
  run_block setup-dispatch "$sh"
  eq "$RC" "0" "[$sh] dispatch resume: a run that stopped after the design's sling completes"
  not_logged "sling rig/gc-toolkit.polecat dz-design" && ok "[$sh] dispatch resume: the design child is not slung again" \
    || bad "[$sh] dispatch resume: the design child was slung a second time"
  not_logged "--if-assignee" && ok "[$sh] dispatch resume: a subject already with the refinery is not assigned again" \
    || bad "[$sh] dispatch resume: the subject was assigned again"
  logged "deferred-dispatch arm dz-impl" && logged "deferred-dispatch arm dz-sum" \
    && ok "[$sh] dispatch resume: the implementation and the summary task are armed" || bad "[$sh] dispatch resume: an arm is missing"
  eq "$(open_blockers dz-sub)" "dz-impl dz-sum" "[$sh] dispatch resume: the subject is still held by the implementation and the summary task"

  wired; export SUMMARY_ARMED=1
  run_block setup-dispatch "$sh"
  eq "$RC" "0" "[$sh] dispatch: a subject whose summary task is armed is a no-op"
  [ -s "$GC_LOG" ] && bad "[$sh] dispatch: a finished setup still wrote" || ok "[$sh] dispatch: a finished setup writes nothing"
done

# --- the work skill's recipe --------------------------------------------------
# The recipe as a session runs it, with its placeholders filled in for one
# bead of the effort. NEXT_IDS gives the landing bead, the bead and the summary
# task their ids in the order the recipe files them.
RECIPE="$(fenced_block "$RECIPE_FILE" '# >>> effort-default-branch')"
LATE="$(fenced_block "$RECIPE_FILE" "dep add's second id is the bead that is waited on")"
[ -n "$RECIPE" ] && ok "the work skill's recipe is found" || bad "the work skill's recipe is not found in $RECIPE_FILE"
[ -n "$LATE" ] && ok "the work skill's block for a bead that joins later is found" || bad "the work skill's late-join block is not found in $RECIPE_FILE"
fill() {
  sed -e 's#<each bead of the effort, comma-separated>#$WORK#g' \
      -e 's#<rig>#rig#g' -e 's#<epic>#ep-1#g' -e 's#<binding>#gc-toolkit#g' \
      -e 's#<[^>]*>#x#g'
}
# recipe_store: a store holding only the epic; origin carries only the branch
# origin/HEAD names, ORIGIN_HEAD_FOR (default trunk).
recipe_store() {
  fixture '.[1:] = []'
  export ORIGIN_HEAD="${ORIGIN_HEAD_FOR:-trunk}" NEXT_IDS="land-1 work-1 dz-sum"
  printf '%s\n' "$ORIGIN_HEAD" > "$ORIGIN_REFS"
}
run_recipe() { { printf '%s\n' "$RECIPE" | fill; printf 'printf "past\\n" > "%s"\n' "$TMP/past.flag"; } > "$TMP/block.sh"; run_file "$1"; }
run_late() { { printf '%s\n' "$LATE" | fill; printf 'printf "past\\n" > "%s"\n' "$TMP/past.flag"; } > "$TMP/block.sh"; run_file "$1"; }

for sh in "${SHELLS[@]}"; do
  recipe_store
  run_recipe "$sh"
  eq "$RC" "0" "[$sh] recipe: an effort is stood up on a rig whose default branch is trunk, with no main"
  logged "push origin refs/remotes/origin/trunk:refs/heads/integration/land-1" \
    && ok "[$sh] recipe: the branch is cut from the branch origin/HEAD names" || bad "[$sh] recipe: the branch was not cut from origin/HEAD's branch"
  eq "$(meta land-1 branch) $(meta land-1 target)" "integration/land-1 trunk" "[$sh] recipe: the landing bead records the branch and the default branch as its target"
  eq "$(meta work-1 target)" "integration/land-1" "[$sh] recipe: the bead's target is the integration branch"
  eq "$(waits_on land-1 work-1) $(waits_on land-1 dz-sum) $(waits_on dz-sum work-1)" "1 1 1" \
    "[$sh] recipe: the landing bead waits on the bead and the summary task, and the summary task on the bead"
  eq "$(meta dz-sum target)" "<absent>" "[$sh] recipe: the summary task carries no target"
  eq "$(field land-1 assignee)" "rig/gc-toolkit.refinery" "[$sh] recipe: the landing bead is handed to the refinery"
  logged "deferred-dispatch notify land-1 --agent rig/gc-toolkit.refinery" \
    && ok "[$sh] recipe: …with the notice the assignment owes" || bad "[$sh] recipe: no notice for the assignment"
  logged "sling rig/gc-toolkit.polecat work-1" && logged "deferred-dispatch arm dz-sum --target rig/gc-toolkit.polecat --sling-arg --on --sling-arg mol-polecat-report" \
    && ok "[$sh] recipe: the bead is slung and the summary task armed on mol-polecat-report" || bad "[$sh] recipe: the work was not dispatched"
  all_before "rig create" "update land-1 --assignee" && before "update land-1 --assignee" "gc sling" \
    && ok "[$sh] recipe: every wait is written before the hand-over, and the hand-over comes before the sling" \
    || bad "[$sh] recipe: the landing bead was handed over, or the bead slung, before every wait was written"
  not_logged "dep list" && not_logged "bd --rig rig show" && ok "[$sh] recipe: it reads no write back" \
    || bad "[$sh] recipe: a write was read back"

  ORIGIN_HEAD_FOR=main recipe_store
  run_recipe "$sh"
  eq "$RC $(meta land-1 target)" "0 main" "[$sh] recipe: a rig whose default branch is main lands its effort on main"

  for fail in "UPDATE_FAIL=land-1:branch" "CREATE_FAIL=work-1" "CREATE_FAIL=dz-sum"; do
    recipe_store; export "${fail?}"
    run_recipe "$sh"
    stopped && ! released && ok "[$sh] recipe: a write the store refuses ($fail) hands nothing over and dispatches nothing" \
      || bad "[$sh] recipe: went ahead past a refused write ($fail) (rc=$RC)"
  done

  recipe_store; export PUSH_FAIL=1
  run_recipe "$sh"
  stopped && not_logged "bd --rig rig update" && ok "[$sh] recipe: a cut that fails records nothing on the landing bead" \
    || bad "[$sh] recipe: went ahead after a failed cut (rc=$RC)"

  # --- a bead that joins later ---
  # The effort's beads and its summary task are filed and dispatched; work-2
  # joins with the writes that file an effort's bead (its target and the landing
  # bead's wait on it). The summary task's own wait takes it while the
  # task is undispatched, which its arm shows, since the deferred-dispatch order
  # clears an arm once it has sent the bead, and still held, which the open
  # work-1 shows.
  JOINED='map(if .id == "land-1" then ._deps += [{id: "work-2", dependency_type: "blocks"}] else . end)
    + [{id: "work-2", title: "x", issue_type: "task", status: "open", assignee: "", description: "", metadata: {target: "integration/land-1"}, _deps: []}]'
  recipe_store; run_recipe "$sh"
  jq -c "$JOINED"' | map(if .id == "dz-sum" then .metadata += {"gc.dispatch_when_ready": "rig/gc-toolkit.polecat"} else . end)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
  export SUMMARY=dz-sum WORK=work-2
  run_late "$sh"
  eq "$RC" "0" "[$sh] late join: an undispatched summary task takes the joining bead's wait"
  eq "$(waits_on dz-sum work-2)" "1" "[$sh] late join: the summary task waits on the joining bead"
  eq "$(open_blockers work-2)" "" "[$sh] late join: the joining bead waits on no summary task, so it is free to sling"
  case " $(open_blockers dz-sum) " in *" work-2 "*) ok "[$sh] late join: the summary task is held until the joining bead lands" ;;
    *) bad "[$sh] late join: the summary task is not held by the joining bead" ;; esac

  recipe_store; run_recipe "$sh"
  jq -c "$JOINED"' | map(if .id == "dz-sum" then .metadata = {} else . end)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
  export SUMMARY=dz-sum WORK=work-2
  run_late "$sh"
  stopped && not_logged "dep add" && [ "$(waits_on dz-sum work-2)" = "0" ] && reported "file a fresh summary task" \
    && ok "[$sh] late join: a summary task with no arm, dispatched already, takes no wait, and a fresh one is asked for" \
    || bad "[$sh] late join: a summary task with no arm took the wait (rc=$RC)"

  # Armed with no marker, every bead it waits on closed: a pass that read it as
  # ready slings it whatever wait is added after, so it takes none either.
  recipe_store; run_recipe "$sh"
  jq -c "$JOINED"' | map(if .id == "dz-sum" then .metadata += {"gc.dispatch_when_ready": "rig/gc-toolkit.polecat"} elif .id == "work-1" then .status = "closed" else . end)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
  export SUMMARY=dz-sum WORK=work-2
  run_late "$sh"
  stopped && not_logged "dep add" && [ "$(waits_on dz-sum work-2)" = "0" ] && reported "file a fresh summary task" \
    && ok "[$sh] late join: a summary task whose beads have all closed takes no wait, and a fresh one is asked for" \
    || bad "[$sh] late join: a summary task whose beads have all closed took the wait (rc=$RC)"

  # Armed with no marker, every blocks wait closed, and a waits-for edge of its
  # own onto a spawner whose child is open: the store cannot judge that edge yet,
  # so the task reads unjudged, which a caller that acts counts as still waiting,
  # and it takes the joining bead's wait.
  recipe_store; run_recipe "$sh"
  jq -c "$JOINED"' | map(if .id == "dz-sum" then .metadata += {"gc.dispatch_when_ready": "rig/gc-toolkit.polecat"} | ._deps += [{id: "sp-1", dependency_type: "waits-for"}] elif .id == "work-1" then .status = "closed" else . end)
    + [{id: "sp-1", title: "spawner", issue_type: "task", status: "open", assignee: "", description: "", metadata: {}, _deps: []},
       {id: "sp-1a", title: "spawned", issue_type: "task", status: "open", assignee: "", description: "", metadata: {}, _deps: [{id: "sp-1", dependency_type: "parent-child"}]}]' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
  export SUMMARY=dz-sum WORK=work-2
  run_late "$sh"
  eq "$RC" "0" "[$sh] late join: a summary task its own waits-for edge holds, unjudged, takes the joining bead's wait"
  eq "$(waits_on dz-sum work-2)" "1" "[$sh] late join: ...and waits on the joining bead"
  unset SUMMARY WORK
done

# --- the hand-off that brings an effort's branch current -----------------------
# The recipe's block, with the landing bead land-1 and the outside work out-1
# filled in. The store holds the epic, the landing bead and the outside work,
# and the create files the hand-off as ho-1.
HANDOFF="$(fenced_block "$RECIPE_FILE" "LANDING=<the landing bead of the effort>")"
[ -n "$HANDOFF" ] && ok "the work skill's hand-off block is found" || bad "the work skill's hand-off block is not found in $RECIPE_FILE"
handoff_store() {
  fixture '.[1:] = [] | . + [
    {id: "land-1", title: "Rebuild the widget", issue_type: "task", status: "open", assignee: "rig/gc-toolkit.refinery", description: "",
     metadata: {branch: "integration/land-1", target: "main"}, _deps: [{id: "ep-1", dependency_type: "parent-child"}]},
    {id: "out-1", title: "the outside work", issue_type: "task", status: "open", assignee: "", description: "", metadata: {}, _deps: []}]'
  export NEXT_ID=ho-1
}
run_handoff() {
  { printf '%s\n' "$HANDOFF" | sed -e 's#<the landing bead of the effort>#land-1#g' -e 's#<the bead of the outside work>#out-1#g' | fill
    printf 'printf "past\\n" > "%s"\n' "$TMP/past.flag"; } > "$TMP/block.sh"
  run_file "$1"
}

for sh in "${SHELLS[@]}"; do
  handoff_store; run_handoff "$sh"
  eq "$RC" "0" "[$sh] hand-off: the block files the hand-off and hands it over"
  eq "$(field ho-1 assignee)" "rig/gc-toolkit.refinery" "[$sh] hand-off: the rig's refinery owns it"
  logged "deferred-dispatch notify ho-1 --agent rig/gc-toolkit.refinery" && before "update ho-1 --assignee" "deferred-dispatch notify ho-1" \
    && ok "[$sh] hand-off: …with the notice the assignment owes, after it" || bad "[$sh] hand-off: no notice to the refinery after the assignment"
  eq "$(waits_on ho-1 out-1)" "1" "[$sh] hand-off: it waits on the outside work"
  eq "$(meta ho-1 branch) $(meta ho-1 target)" "<absent> <absent>" "[$sh] hand-off: it carries no branch and no target, so the refinery's patrol never takes it to land"
  eq "$(waits_on land-1 ho-1) $(parents ho-1)" "0 ep-1" "[$sh] hand-off: it sits under the effort's epic, and the landing bead does not wait on it"
  says ho-1 "land-1, the effort's landing bead" && ok "[$sh] hand-off: it names the landing bead, whose branch and target the refinery reads" \
    || bad "[$sh] hand-off: its description does not name the landing bead"

  for fail in "CREATE_FAIL=ho-1" "UPDATE_FAIL=ho-1:assignee" "NOTIFY_RC=1"; do
    handoff_store; export "${fail?}"
    run_handoff "$sh"
    stopped && ok "[$sh] hand-off: a refused write ($fail) stops the block" || bad "[$sh] hand-off: went ahead past a refused write ($fail) (rc=$RC)"
  done
  handoff_store; export UPDATE_FAIL=ho-1:assignee
  run_handoff "$sh"
  not_logged "deferred-dispatch notify" && ok "[$sh] hand-off: an assignment the store refuses sends no notice" \
    || bad "[$sh] hand-off: a notice went out for a hand-off nobody owns"
done

echo
echo "mol-design-convoy-arm: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
