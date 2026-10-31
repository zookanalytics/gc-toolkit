#!/usr/bin/env bash
# Hermetic test for assets/scripts/store-only-exit.sh.
#
# The constraint: mol-polecat-work's store-only exit releases its work bead
# open, unassigned and unrouted, so this script is what stands between a run
# with work to land and that release. A record that finishes the bead must not
# leave it reading as work not yet done, so --done hands it to its validating
# closer, held on the run's root so the closer pours once the run ends.
#
# What is exercised here:
#   * the refusal: a commit ahead of the base, an uncommitted change or the
#     branch on origin refuses before anything is written, and the probes read
#     the tree the bead's work_dir names, else the current directory;
#   * nothing to land and no brief: exit 0, nothing written;
#   * --done: the brief lands in the bead's notes, then the bead is blocked by
#     its run's root, then the real deferred-dispatch.sh arms mol-validate-close
#     on the pool the run executes on;
#   * the run is the one this session executes: the root that `gc hook
#     current`'s step names, which run-lib.sh is asked about, so a second live
#     run over the convoy holds nothing;
#   * every --done precondition refuses before anything is written: a claimed,
#     routed or closed bead, no rig-qualified pool, no claimed step, a step that
#     names no root, a run that has ended, works another bead or is poured over
#     another convoy, a run read that fails, no deferred-dispatch.sh, an
#     unreadable bead;
#   * a write that does not land exits 1 and stops what follows it;
#   * a re-run converges on one edge and the arm;
#   * the step's own call, taken from the formula, runs against this script, and
#     the brief's header is the one mol-validate-close reads;
#   * usage errors.
#
# No live city, Dolt, network, or beads: a tmpdir, a `gc` stub over a JSON store
# and an edge file, a `git` stub, run-lib.stub.sh, and the scripts themselves.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/store-only-exit.sh"
TOML="$ROOT/formulas/mol-polecat-work.toml"
CLOSER_TOML="$ROOT/formulas/mol-validate-close.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-store-only-exit-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }

unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
mkdir -p "$TMP/bin"

# --- gc stub over a JSON store and an edge file ("A|type|B": A depends on B). --
# `bd show` answers an array, or an error object for an unknown id, and fails
# when $FAKE_SHOW_FAIL is set. `bd list` filters on --status= and every
# --metadata-field k=v. `bd dep list <id>` answers the beads <id> depends on.
# `bd dep add` records an edge unless $FAKE_DEP_FAIL is set. `bd update` applies
# --status, --assignee, --set-metadata, --unset-metadata and --append-notes; it
# refuses when the id is in $FAKE_UPD_FAIL, and refuses the arm's write (one
# that sets gc.dispatch_when_ready) when $FAKE_ARM_WRITE_FAIL is set; with
# $FAKE_ARM_WRITE_NOOP set it answers that write with success and stores
# nothing, as a store can. `gc-toolkit scripts-dir` names this directory, the pack the step's call runs.
# `runtime drain-ack` records DRAIN in $FAKE_TRACE. `hook current` prints
# $FAKE_HOOK_CURRENT, the step this session claimed, and fails as gc does for a
# session that claimed nothing when $FAKE_HOOK_FAIL is set.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
set -u
S="${FAKE_STORE:?}"; D="${FAKE_DEPS:?}"
printf '%s\n' "$*" >> "${GC_LOG:?}"
case "${1:-} ${2:-}" in
  "gc-toolkit scripts-dir")
    printf '%s\n' "${FAKE_SCRIPTS_DIR:?}"; exit 0 ;;
  "runtime drain-ack")
    printf 'DRAIN\n' >> "${FAKE_TRACE:-/dev/null}"; exit 0 ;;
  "hook current")
    [ -n "${FAKE_HOOK_FAIL:-}" ] && { echo "gc hook current: session has no claimed bead (stub)" >&2; exit 1; }
    printf '%s\n' "${FAKE_HOOK_CURRENT:?}"; exit 0 ;;
esac
[ "${1:-}" = "bd" ] || { echo "gc stub: unsupported '$*'" >&2; exit 2; }
shift
[ "${1:-}" = "--db" ] && shift 2
verb="${1:-}"; shift || true
case "$verb" in
  show)
    [ -n "${FAKE_SHOW_FAIL:-}" ] && { echo "bd: store down (stub)" >&2; exit 1; }
    out=$(jq -c --arg id "${1:-}" '[ .[] | select(.id == $id) ]' "$S")
    if [ "$out" = "[]" ]; then printf '{"error":"no issue found matching %s"}\n' "${1:-}"; else printf '%s\n' "$out"; fi ;;
  list)
    st=""; mfs=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) st="${1#--status=}" ;;
        --metadata-field) shift; mfs+=("$1") ;;
      esac
      shift
    done
    filter='.'
    for kv in ${mfs[@]+"${mfs[@]}"}; do
      filter="$filter | select((.metadata[\"${kv%%=*}\"] // \"\") == \"${kv#*=}\")"
    done
    jq -c --arg st "$st" "[ .[] | (.status // \"open\") as \$bst | select(\$st == \"\" or ((\$st | split(\",\")) | index(\$bst))) | $filter ]" "$S" ;;
  dep)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        id="${1:-}"
        rows=$(awk -F'|' -v a="$id" '$1 == a { print $2 "|" $3 }' "$D")
        printf '%s\n' "$rows" | jq -R -s -c --slurpfile s "$S" '
          split("\n") | map(select(length > 0) | split("|")) as $e
          | [ $e[] | . as [$t, $b] | ($s[0][] | select(.id == $b)) as $row
              | {id: $b, dependency_type: $t, status: ($row.status // "open")} ]' ;;
      add)
        [ -n "${FAKE_DEP_FAIL:-}" ] && { echo "bd: refused (stub)" >&2; exit 1; }
        a="${1:-}"; b="${2:-}"; t="blocks"
        shift 2 || true
        for x in "$@"; do case "$x" in --type=*) t="${x#--type=}" ;; esac; done
        grep -qxF "$a|$t|$b" "$D" 2>/dev/null || printf '%s|%s|%s\n' "$a" "$t" "$b" >> "$D" ;;
      *) exit 2 ;;
    esac ;;
  update)
    id="${1:-}"; shift || true
    case " ${FAKE_UPD_FAIL:-} " in *" $id "*) echo "bd: cannot update $id (stub)" >&2; exit 1 ;; esac
    for x in "$@"; do
      case "$x" in
        gc.dispatch_when_ready=*)
          [ -n "${FAKE_ARM_WRITE_FAIL:-}" ] && { echo "bd: store fault writing $id (stub)" >&2; exit 1; }
          [ -n "${FAKE_ARM_WRITE_NOOP:-}" ] && { echo "✓ Updated issue: $id"; exit 0; } ;;
      esac
    done
    tmp="$S.n"; cp "$S" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*|--assignee=*)
          f="${1%%=*}"; f="${f#--}"
          jq -c --arg id "$id" --arg f "$f" --arg v "${1#*=}" 'map(if .id == $id then .[$f] = $v else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
        --set-metadata) shift; jq -c --arg id "$id" --arg k "${1%%=*}" --arg v "${1#*=}" 'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
        --unset-metadata) shift; jq -c --arg id "$id" --arg k "$1" 'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
        --append-notes) shift; jq -c --arg id "$id" --arg n "$1" 'map(if .id == $id then .notes = ((.notes // "") + $n) else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
      esac
      shift
    done
    mv "$tmp" "$S"
    echo "✓ Updated issue: $id" ;;
  *) echo "gc stub: unsupported 'bd $verb'" >&2; exit 2 ;;
esac
exit 0
GC

# --- git stub: the three probes, after an optional -C <dir>. ------------------
# `rev-list --count` answers $FAKE_AHEAD (0), `status --porcelain` $FAKE_DIRTY
# and `ls-remote origin` $FAKE_PUSHED, both empty by default; $FAKE_GIT_FAIL
# fails every call. Each call is logged as "<dir>|<args>".
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<'GIT'
dir="."
if [ "${1:-}" = "-C" ]; then dir="${2:-}"; shift 2; fi
printf '%s|%s\n' "$dir" "$*" >> "${GIT_LOG:?}"
[ -n "${FAKE_GIT_FAIL:-}" ] && { echo "fatal: not a git repository (stub)" >&2; exit 128; }
case "${1:-} ${2:-}" in
  "rev-list --count")   printf '%s\n' "${FAKE_AHEAD:-0}" ;;
  "status --porcelain") [ -z "${FAKE_DIRTY:-}" ] || printf '%s\n' "$FAKE_DIRTY" ;;
  "ls-remote origin")   [ -z "${FAKE_PUSHED:-}" ] || printf '%s\n' "$FAKE_PUSHED" ;;
esac
exit 0
GIT
chmod +x "$TMP/bin/gc" "$TMP/bin/git"
export PATH="$TMP/bin:$PATH"
export FAKE_STORE="$TMP/store.json" FAKE_DEPS="$TMP/deps.txt" GC_LOG="$TMP/gc.log" GIT_LOG="$TMP/git.log" \
  FAKE_TRACE="$TMP/trace" FAKE_SCRIPTS_DIR="$HERE" FAKE_HOOK_CURRENT="tk-step"
export GC_RUN_LIB="$HERE/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$TMP/runs.json" RUN_LIB_STUB_FAIL="" \
  RUN_LIB_STUB_LOG="$TMP/run-lib.log"

POOL="gc-toolkit/gc-toolkit.polecat"
LIVE_RUN='{"root":"tk-root","convoy":"tk-cv","bead":"tk-work","formula":"mol-polecat-work","live":true}'
BRIEF="Every check passed live at 19:02Z: it's 100% done, and \$HOME, \`date\` and \"quotes\" land verbatim."
reset() {
  mkdir -p "$TMP/wt"
  cat > "$FAKE_STORE" <<JSON
[
 {"id":"tk-work","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"$POOL","branch":"polecat/tk-work","work_dir":"$TMP/wt"}},
 {"id":"tk-root","status":"in_progress","assignee":"","metadata":{"gc.kind":"workflow"}},
 {"id":"tk-step","status":"in_progress","assignee":"","metadata":{"gc.root_bead_id":"tk-root","gc.step_ref":"mol-polecat-work.submit-and-exit"}}
]
JSON
  printf '[%s]\n' "$LIVE_RUN" > "$RUN_LIB_STUB_RUNS"
  : > "$FAKE_DEPS"; : > "$GC_LOG"; : > "$GIT_LOG"; : > "$FAKE_TRACE"; : > "$RUN_LIB_STUB_LOG"
}
# set_work <jq update> — rewrite the work bead's row.
set_work() {
  jq -c "map(if .id == \"tk-work\" then ($1) else . end)" "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
}
run() { OUT=$("$SCRIPT" "$@" 2>&1); RC=$?; }
meta() { jq -r --arg i "$1" --arg k "$2" '(.[] | select(.id == $i) | .metadata[$k]) // "<absent>"' "$FAKE_STORE"; }
notes() { jq -r '(.[] | select(.id == "tk-work") | .notes) // ""' "$FAKE_STORE"; }
writes() { grep -cE '^bd (update|dep add)' "$GC_LOG" | tr -d ' '; }
edge_rows() { grep -c '^tk-work|blocks|tk-root$' "$FAKE_DEPS" | tr -d ' '; }
DONE_ARGS=(--bead tk-work --base main --convoy tk-cv --done "$BRIEF")

# ── 1. nothing to land, no brief ──────────────────────────────────────────────
reset
run --bead tk-work --base main
eq "$RC" 0 "nothing to land: exit 0"
has "$OUT" "tk-work has nothing to land" "nothing to land: says so"
eq "$(writes)" 0 "nothing to land, no brief: nothing written"
eq "$(meta tk-work gc.dispatch_when_ready)" "<absent>" "no brief: no closer armed"
has "$(cat "$GIT_LOG")" "$TMP/wt|rev-list --count origin/main..HEAD" "the probes read the tree the bead's work_dir names"
has "$(cat "$GIT_LOG")" "$TMP/wt|ls-remote origin refs/heads/polecat/tk-work" "the pushed-branch probe names polecat/<bead>"
reset
run --bead tk-work --base main --convoy tk-cv --done ""
eq "$RC|$(writes)" "0|0" "an empty brief, the step's default: exit 0, nothing written"

reset; set_work '.metadata |= del(.work_dir)'
run --bead tk-work --base main
eq "$RC" 0 "no work_dir: exit 0"
has "$(cat "$GIT_LOG")" ".|status --porcelain" "no work_dir: the probes read the current directory"
reset; set_work ".metadata.work_dir = \"$TMP/gone\""
run --bead tk-work --base main
has "$(cat "$GIT_LOG")" ".|status --porcelain" "a work_dir that is not a directory: the probes read the current directory"

reset
OUT=$(FAKE_GIT_FAIL=1 "$SCRIPT" --bead tk-work --base main 2>&1); RC=$?
eq "$RC" 0 "a probe git cannot answer counts as nothing to land"

# ── 2. the refusal writes nothing ─────────────────────────────────────────────
for probe in "FAKE_AHEAD=2|commits ahead of origin/main: 2" \
             "FAKE_DIRTY= M formulas/x.toml|uncommitted changes: yes" \
             "FAKE_PUSHED=abc123	refs/heads/polecat/tk-work|branch already on origin: polecat/tk-work"; do
  assign="${probe%%|*}"; line="${probe#*|}"
  reset
  OUT=$(env "$assign" "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
  eq "$RC" 1 "${assign%%=*}: refused"
  has "$OUT" "STORE-ONLY EXIT REFUSED: this run has work to land" "${assign%%=*}: says the run has work to land"
  has "$OUT" "$line" "${assign%%=*}: names what it found"
  has "$OUT" "tree read: $TMP/wt" "${assign%%=*}: names the tree it read"
  eq "$(writes)|$(edge_rows)|$(meta tk-work gc.dispatch_when_ready)" "0|0|<absent>" "${assign%%=*}: nothing written, even with a brief"
done

# ── 3. --done hands the bead to its validating closer ─────────────────────────
reset
run "${DONE_ARGS[@]}"
eq "$RC" 0 "--done: exit 0"
has "$OUT" "mol-validate-close is armed on $POOL, held on run tk-root" "--done: names the closer, the pool and the run"
has "$(notes)" "## Close brief (store-only exit, " "--done: the brief lands as a close brief section"
has "$(notes)" "$BRIEF" "--done: the brief lands verbatim"
eq "$(edge_rows)" 1 "--done: the bead is blocked by its run's root"
eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "--done: the closer is armed on the pool the run executes on"
eq "$(meta tk-work gc.dispatch_when_ready_args)" '["--on","mol-validate-close"]' "--done: the arm pours mol-validate-close"
eq "$(meta tk-work halt_reason)" "<absent>" "--done: the record is the step's write, not this script's"
BRIEF_LN=$(grep -n -- '--append-notes ## Close brief' "$GC_LOG" | head -1 | cut -d: -f1)
EDGE_LN=$(grep -n '^bd dep add tk-work tk-root --type=blocks' "$GC_LOG" | head -1 | cut -d: -f1)
ARM_LN=$(grep -n -- '--set-metadata gc.dispatch_when_ready=' "$GC_LOG" | head -1 | cut -d: -f1)
{ [ -n "$BRIEF_LN" ] && [ -n "$EDGE_LN" ] && [ -n "$ARM_LN" ] && [ "$BRIEF_LN" -lt "$EDGE_LN" ] && [ "$EDGE_LN" -lt "$ARM_LN" ]; } \
  && ok "--done: the brief lands before the hold, and the hold before the arm" \
  || bad "--done: the brief, the hold and the arm out of order (brief ${BRIEF_LN:-?}, edge ${EDGE_LN:-?}, arm ${ARM_LN:-?})"
has "$(cat "$GC_LOG")" "hook current --id-only" "--done: the run comes from the step this session claimed"
eq "$(cat "$RUN_LIB_STUB_LOG")" "subject store_read tk-root" "--done: run-lib.sh is asked about the root the claimed step names, not the convoy"

# A second live run over the convoy is not this session's: the hold goes on the
# root the claimed step names.
reset; printf '[%s,%s]\n' "${LIVE_RUN/tk-root/tk-root0}" "$LIVE_RUN" > "$RUN_LIB_STUB_RUNS"
run "${DONE_ARGS[@]}"
eq "$RC|$(edge_rows)|$(grep -c '|tk-root0$' "$FAKE_DEPS" | tr -d ' ')" "0|1|0" "a second live run over the convoy: held on this session's run alone"

reset; set_work '.metadata |= (del(.["gc.execution_routed_to"]) | .["gc.routed_to"] = "")'
jq -c 'map(if .id == "tk-work" then .metadata["gc.execution_routed_to"] = "gc-toolkit/gc-toolkit.polecat-codex" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run "${DONE_ARGS[@]}"
eq "$RC|$(meta tk-work gc.dispatch_when_ready)" "0|gc-toolkit/gc-toolkit.polecat-codex" "--done: the closer follows the pool the run executes on"

# ── 4. a re-run converges ─────────────────────────────────────────────────────
reset
run "${DONE_ARGS[@]}"
run "${DONE_ARGS[@]}"
eq "$RC" 0 "a re-run: exit 0"
eq "$(edge_rows)" 1 "a re-run writes no second edge"
eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "a re-run keeps the arm"

# ── 5. --done preconditions refuse before anything is written ────────────────
refused() { # <label> <expected text>
  eq "$RC" 1 "$1: exit 1"
  has "$OUT" "$2" "$1: says why"
  eq "$(writes)|$(edge_rows)|$(meta tk-work gc.dispatch_when_ready)" "0|0|<absent>" "$1: nothing written"
}
reset; set_work '.status = "in_progress" | .assignee = "hq-other"'
run "${DONE_ARGS[@]}"; refused "a claimed bead" "is status 'in_progress', assignee 'hq-other'"
reset; set_work '.assignee = "hq-other"'
run "${DONE_ARGS[@]}"; refused "an open bead under an assignee" "assignee 'hq-other'"
reset; set_work '.metadata["gc.routed_to"] = "gc-toolkit/gc-toolkit.polecat"'
run "${DONE_ARGS[@]}"; refused "a routed bead" "gc.routed_to 'gc-toolkit/gc-toolkit.polecat'"
reset; set_work '.status = "closed"'
run "${DONE_ARGS[@]}"; refused "a closed bead" "is status 'closed'"
reset; set_work '.metadata |= del(.["gc.execution_routed_to"])'
run "${DONE_ARGS[@]}"; refused "no pool" "names no rig-qualified pool"
reset; set_work '.metadata["gc.execution_routed_to"] = "gc-toolkit.polecat"'
run "${DONE_ARGS[@]}"; refused "a pool that is not rig-qualified" "gave 'gc-toolkit.polecat'"
reset
OUT=$(FAKE_HOOK_FAIL=1 "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
refused "no step this session claimed" "gc hook current names no step this session claimed"
reset
OUT=$(FAKE_HOOK_CURRENT=tk-unknown "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
refused "a claimed step the store does not return" "tk-unknown, the step this session claimed, names no run root"
reset; jq -c 'map(if .id == "tk-step" then (.metadata |= del(.["gc.root_bead_id"])) else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run "${DONE_ARGS[@]}"; refused "a claimed step that names no root" "tk-step, the step this session claimed, names no run root"
reset; printf '[%s]\n' "${LIVE_RUN/\"live\":true/\"live\":false}" > "$RUN_LIB_STUB_RUNS"
run "${DONE_ARGS[@]}"; refused "a run that has ended" "the run rooted at tk-root, which this session executes, is not a live run over tk-cv that works tk-work"
reset; printf '[%s]\n' "${LIVE_RUN/\"tk-work\"/\"tk-else\"}" > "$RUN_LIB_STUB_RUNS"
run "${DONE_ARGS[@]}"; refused "a run that works another bead" "is not a live run over tk-cv that works tk-work"
reset; printf '[%s]\n' "${LIVE_RUN/\"tk-cv\"/\"tk-cv2\"}" > "$RUN_LIB_STUB_RUNS"
run "${DONE_ARGS[@]}"; refused "a run poured over another convoy" "is not a live run over tk-cv that works tk-work"
reset; printf '[]\n' > "$RUN_LIB_STUB_RUNS"
run "${DONE_ARGS[@]}"; refused "a root run-lib.sh finds no run for" "is not a live run over tk-cv that works tk-work"
reset
OUT=$(RUN_LIB_STUB_FAIL=subject "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
refused "a run read that fails" "could not read the run rooted at tk-root"
reset
OUT=$(GC_DEFERRED_DISPATCH_TOOL="$TMP/missing.sh" "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
refused "no deferred-dispatch.sh" "deferred-dispatch.sh not found"
reset
OUT=$(FAKE_SHOW_FAIL=1 "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
refused "an unreadable bead" "could not read tk-work"
reset
run --bead tk-gone --base main --convoy tk-cv --done "$BRIEF"
eq "$RC|$(writes)" "1|0" "an unknown bead: exit 1, nothing written"

# ── 6. a write that does not land stops what follows it ──────────────────────
reset
OUT=$(FAKE_UPD_FAIL=tk-work "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
eq "$RC" 1 "the brief refused: exit 1"
has "$OUT" "the close brief did not land on tk-work" "the brief refused: says so"
eq "$(edge_rows)|$(meta tk-work gc.dispatch_when_ready)" "0|<absent>" "the brief refused: no hold, no arm"
reset
OUT=$(FAKE_DEP_FAIL=1 "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
eq "$RC" 1 "the hold refused: exit 1"
has "$OUT" "the blocks edge from tk-work onto its run's root tk-root did not land" "the hold refused: says so"
eq "$(meta tk-work gc.dispatch_when_ready)" "<absent>" "the hold refused: the closer is not armed unheld"
reset
OUT=$(FAKE_ARM_WRITE_FAIL=1 "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
eq "$RC" 1 "the arm refused: exit 1"
has "$OUT" "the validating closer was not armed on tk-work" "the arm refused: says so"
eq "$(edge_rows)" 1 "the arm refused: the hold stays, for the re-run"
reset
OUT=$(FAKE_ARM_WRITE_NOOP=1 "$SCRIPT" "${DONE_ARGS[@]}" 2>&1); RC=$?
eq "$RC" 1 "an arm the store took and did not keep: exit 1"
has "$OUT" "reads back armed to ''" "an arm the store did not keep: the read-back says so"

# ── 7. the step's own call, and the brief's reader ───────────────────────────
CALL="$(awk '/# >>> submit-store-only-check$/{f=1; next} /# <<< submit-store-only-check$/{f=0} f' "$TOML" \
  | sed 's|{{binding_prefix}}|gc-toolkit.|g; s|{{base_branch}}|main|g; s|{{convoy_id}}|tk-cv|g')"
[ -n "$CALL" ] && ok "the step's call is extracted between submit-store-only-check markers" \
  || bad "the step's call extraction is EMPTY — markers missing from $TOML"
eq "$(printf '%s\n' "$CALL" | grep -c 'store-only-exit.sh' | tr -d ' ')" 1 "the step calls this script once"
printf '%s\n' "$CALL" > "$TMP/call.sh"
reset
OUT=$(WORK_BEAD_ID=tk-work STORE_ONLY_DONE="$BRIEF" bash "$TMP/call.sh" 2>&1); RC=$?
eq "$RC" 0 "the step's call with a brief: exit 0"
eq "$(edge_rows)|$(meta tk-work gc.dispatch_when_ready)" "1|$POOL" "the step's call with a brief: held and armed"
eq "$(cat "$FAKE_TRACE")" "" "the step's call that lands does not drain"
reset
OUT=$(WORK_BEAD_ID=tk-work STORE_ONLY_DONE="" bash "$TMP/call.sh" 2>&1); RC=$?
eq "$RC|$(writes)" "0|0" "the step's call with no brief: exit 0, nothing written"
reset
OUT=$(WORK_BEAD_ID=tk-work STORE_ONLY_DONE="$BRIEF" FAKE_AHEAD=1 bash "$TMP/call.sh" 2>&1); RC=$?
eq "$RC|$(cat "$FAKE_TRACE")|$(writes)" "1|DRAIN|0" "the step's call refused: exit 1 and drain, nothing written"

grep -qF '## Close brief (store-only exit, <time>)' "$CLOSER_TOML" \
  && ok "mol-validate-close names the store-only exit's brief header" \
  || bad "mol-validate-close does not name '## Close brief (store-only exit, <time>)', the header this script writes"
grep -qx 'formula = "mol-validate-close"' "$CLOSER_TOML" \
  && ok "the formula the arm pours exists" \
  || bad "no formula named mol-validate-close at $CLOSER_TOML"

# ── 8. usage ──────────────────────────────────────────────────────────────────
usage_case() { # <label> <args...>
  local label="$1"; shift
  reset
  OUT=$("$SCRIPT" "$@" 2>&1); RC=$?
  eq "$RC|$(writes)" "2|0" "$label: exit 2, nothing written"
}
usage_case "no --bead" --base main
usage_case "no --base" --bead tk-work
usage_case "--done without --convoy" --bead tk-work --base main --done "$BRIEF"
usage_case "an unsubstituted convoy" --bead tk-work --base main --convoy '{{convoy_id}}' --done "$BRIEF"
usage_case "an unsubstituted base" --bead tk-work --base '{{base_branch}}'
usage_case "a bead outside the id charset" --bead 'tk work' --base main
usage_case "a base outside the branch charset" --bead tk-work --base 'main;rm'
usage_case "an unknown argument" --bead tk-work --base main --record x
usage_case "--bead with no value" --base main --bead
usage_case "--bead followed by an option" --bead --base main

echo
echo "store-only-exit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
