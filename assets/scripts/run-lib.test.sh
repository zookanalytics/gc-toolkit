#!/usr/bin/env bash
# Hermetic test for assets/scripts/run-lib.sh, the one definition of how a
# workflow run links to the bead it works. Covers:
#   (DEF)     sourcing the file exposes $RUN_JQ and run_lib
#   (CASES)   every case in run-lib.fixture.json, each through its verb over the
#             fixture store: the runs it prints, in order, and nothing else
#   (FAIL)    a read that fails, or answers anything but a JSON array, at any
#             stage of any verb fails the verb, which prints nothing, so no
#             caller reads it as no runs
#   (USAGE)   an unknown verb or scope, and a missing reader or bead, are usage
#             errors
#   (SHAPE)   a convoy read by `bd show` tracks the same beads as one read by a
#             list
#   (BATCH)   the map reads the convoys its roots name in batches, and prints
#             the same runs however they are batched
#   (STUB)    run-lib.stub.sh, which its readers' suites source in its place,
#             answers every case as this file does when given every run of the
#             store, from a file or from a command, and fails, logs and refuses
#             as it says
#   (READERS) every reader of the link sources this file and calls a verb or
#             applies $RUN_JQ
#   (NO-COPY) no other file defines the rule's defs
# A reader with a private copy of the rule drifts silently from this one. The
# behavioral half lives beside each reader, whose suite stubs the verbs.
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/run-lib.sh"
FX="$HERE/run-lib.fixture.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-run-lib-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=run-lib.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${RUN_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$RUN_JQ" || bad "(DEF) sourcing the file exposes \$RUN_JQ"
[ "$(type -t run_lib)" = "function" ] && ok "(DEF) sourcing the file defines run_lib" || bad "(DEF) sourcing the file defines run_lib"
jq -e '(.beads | type) == "array" and (.cases | type) == "array" and (.cases | length) > 0' "$FX" >/dev/null 2>&1 \
    && ok "(DEF) the fixture carries a store and its cases" || bad "(DEF) the fixture carries a store and its cases"

# The reader a verb calls: the fixture store, answering the reads the verbs
# make the way bd does. A list leaves closed beads out unless it is given
# --all; --id, --metadata-field and --has-metadata-key filter it. `dep list
# <id> --direction=up -t tracks` prints each bead that tracks <id>, without its
# own edges, as bd does. Every read is logged. FAIL_ON names an argument
# string: a read whose arguments contain it fails, and with FAIL_HOW=parse it
# answers bd's error object at exit 0 instead.
STORE="$FX"
READS="$TMP/reads.log"
FAIL_ON=""; FAIL_HOW=""
fx_bd() {
    printf '%s\n' "$*" >> "$READS"
    if [ -n "$FAIL_ON" ]; then
        case " $* " in
            *"$FAIL_ON"*)
                if [ "$FAIL_HOW" = parse ]; then printf '{"error": "no issue found"}\n'; return 0; fi
                return 1 ;;
        esac
    fi
    if [ "${1:-}" = dep ] && [ "${2:-}" = list ]; then
        jq -c --arg id "$3" '[ (if type == "array" then . else .beads end)[]
            | select(any((.dependencies // [])[]; .depends_on_id == $id and .type == "tracks"))
            | del(.dependencies) + {dependency_type: "tracks"} ]' "$STORE"
        return
    fi
    [ "${1:-}" = list ] || { echo "fx_bd: unexpected read: $*" >&2; return 1; }
    shift
    local ids="" field="" key="" all=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --id) ids="$2"; shift ;;
            --metadata-field) field="$2"; shift ;;
            --has-metadata-key) key="$2"; shift ;;
            --all) all=1 ;;
            --limit) shift ;;
            --include-ephemeral|--json) ;;
            *) echo "fx_bd: unexpected list argument: $1" >&2; return 1 ;;
        esac
        shift
    done
    jq -c --arg ids "$ids" --arg field "$field" --arg key "$key" --argjson all "$all" '
        [ (if type == "array" then . else .beads end)[]
          | select($all == 1 or .status != "closed")
          | select($ids == "" or (.id as $i | $ids | split(",") | index($i) != null))
          | select($key == "" or ((.metadata // {}) | has($key)))
          | select($field == "" or (($field | index("=")) as $at
                                    | ((.metadata // {})[$field[0:$at]] // null) == $field[$at + 1:])) ]' "$STORE"
}
reads() { wc -l < "$READS" | tr -d ' '; }
verb() { : > "$READS"; run_lib "$@"; }

echo "# the fixture's cases"
while IFS= read -r c; do
    [ -n "$c" ] || continue
    name="$(printf '%s' "$c" | jq -r '.name')"
    v="$(printf '%s' "$c" | jq -r '.verb')"
    arg="$(printf '%s' "$c" | jq -r '.arg')"
    want="$(printf '%s' "$c" | jq -c '.runs')"
    if [ "$v" = map ]; then
        got="$(verb map fx_bd $arg)"; rc=$?
    else
        got="$(verb "$v" fx_bd "$arg")"; rc=$?
    fi
    eq "$rc" "0" "(CASES) $name: $v ${arg:-live} answers"
    eq "$(printf '%s' "$got" | jq -c '.' 2>/dev/null)" "$want" "(CASES) $name"
done <<< "$(jq -c '.cases[]' "$FX")"

echo "# a read that fails fails the verb"
fails() { # <label> <fail-on> <verb args...>
    local label="$1" on="$2" how got rc
    shift 2
    for how in exit parse; do
        FAIL_ON="$on"; FAIL_HOW="$how"
        got="$(verb "$@")"; rc=$?
        FAIL_ON=""; FAIL_HOW=""
        eq "$rc" "1" "(FAIL) $label ($how): the verb fails"
        eq "$got" "" "(FAIL) $label ($how): the verb prints nothing"
    done
}
fails "runs: the convoys tracking the bead" "dep list" runs fx_bd work-a
fails "runs: the roots poured over a convoy" "gc.input_convoy_id=cv-a1" runs fx_bd work-a
fails "runs: the roots that record the bead as their issue" "gc.var.issue=work-a" runs fx_bd work-a
fails "runs: the convoys the roots name" "--id cv-a0,cv-a1" runs fx_bd work-a
fails "subject: the bead itself" "--id root-a1" subject fx_bd root-a1
fails "subject: the convoy a root names" "--id cv-a1" subject fx_bd root-a1
fails "subject: the roots poured over a convoy" "gc.input_convoy_id=cv-a1" subject fx_bd cv-a1
fails "map: the roots that name a convoy" "--has-metadata-key gc.input_convoy_id" map fx_bd
fails "map: the roots that record an issue" "--has-metadata-key gc.var.issue" map fx_bd all
fails "map: the convoys the roots name" "--id " map fx_bd
noticed_bd() { printf 'gc bd: answering from the rig "x" store\n'; fx_bd "$@"; }
eq "$(run_lib subject noticed_bd root-a1 | jq -r '.[0].bead')" "work-a" "(FAIL) a store notice printed on stdout is dropped, not read as a failure"
ctl_bd() { fx_bd "$@" | LC_ALL=C sed "s/input convoy for/input$(printf '\001')convoy for/"; }
eq "$(run_lib subject ctl_bd root-a1 | jq -r '.[0].bead')" "work-a" "(FAIL) a raw control byte in a row's title is scrubbed, not read as a failure"
printf '[{"id": "x"}, 1]' > "$TMP/mixed.json"
mixed_bd() { cat "$TMP/mixed.json"; }
got="$(run_lib subject mixed_bd x)"; rc=$?
eq "$rc:$got" "1:" "(FAIL) a read that answers an array holding a non-object fails the verb"

echo "# usage"
for args in "nope fx_bd x" "runs" "runs fx_bd" "subject fx_bd" "map fx_bd live"; do
    # shellcheck disable=SC2086  # each case is a word list
    run_lib $args >/dev/null 2>&1; rc=$?
    eq "$rc" "2" "(USAGE) run_lib $args is a usage error"
done

echo "# both shapes bd prints edges in"
eq "$(printf '%s' '{"id":"cv","issue_type":"convoy","dependencies":[{"id":"w-1","dependency_type":"tracks"},{"id":"e-1","dependency_type":"parent-child"}]}' | jq -c "$RUN_JQ"'run_tracked')" \
   '["w-1"]' "(SHAPE) a convoy read by bd show tracks the beads its {id, dependency_type} edges name"
eq "$(printf '%s' '{"id":"cv","issue_type":"convoy","dependencies":[{"issue_id":"cv","depends_on_id":"w-1","type":"tracks"},{"issue_id":"cv","depends_on_id":"w-1","type":"tracks"}]}' | jq -c "$RUN_JQ"'run_tracked')" \
   '["w-1"]' "(SHAPE) a convoy read by a list tracks each bead its {depends_on_id, type} edges name, once"
eq "$(printf '%s' '[{"id":"r","issue_type":"task","status":"open","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"cv"}},{"id":"cv","issue_type":"convoy","dependencies":[{"id":"w-1","dependency_type":"tracks"}]}]' | jq -c "$RUN_JQ"'run_rows | map(.bead)')" \
   '["w-1"]' "(SHAPE) run_rows judges rows already read, a show's convoy included"

echo "# batched convoy reads"
want="$(verb map fx_bd all)"
RUN_LIB_ID_BATCH=2
got="$(verb map fx_bd all)"; rc=$?
n="$(grep -c -- '--id ' "$READS")"
RUN_LIB_ID_BATCH=200
eq "$rc" "0" "(BATCH) a map read in batches of two answers"
eq "$got" "$want" "(BATCH) batching the convoy reads changes no run"
eq "$n" "3" "(BATCH) the six convoys the roots name are read two at a time"

echo "# the stub its readers' suites source"
# Given every run of the fixture's store, the stub answers each case as the
# lib does, so a reader's suite that feeds it runs feeds what the lib reads.
verb map fx_bd all > "$TMP/every-run.json"
STUB_OUT="$(
    GC_RUN_LIB="$HERE/run-lib.stub.sh"
    RUN_LIB_STUB_RUNS="$TMP/every-run.json"
    RUN_LIB_STUB_LOG="$TMP/stub.log"
    # shellcheck source=run-lib.stub.sh
    . "$HERE/run-lib.stub.sh" || { echo "cannot source run-lib.stub.sh"; exit 0; }
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        v="$(printf '%s' "$c" | jq -r '.verb')"; arg="$(printf '%s' "$c" | jq -r '.arg')"
        if [ "$v" = map ]; then got="$(run_lib map fx_bd $arg)"; else got="$(run_lib "$v" fx_bd "$arg")"; fi
        printf '%s\t%s\n' "$(printf '%s' "$c" | jq -r '.name')" "$( [ "$(printf '%s' "$got" | jq -c .)" = "$(printf '%s' "$c" | jq -c '.runs')" ] && echo same || echo "differs: $got")"
    done <<< "$(jq -c '.cases[]' "$FX")"
    RUN_LIB_STUB_FAIL="subject:root-a1 map"
    run_lib subject fx_bd root-a1 >/dev/null; printf 'fail-arg\t%s\n' "$?"
    run_lib subject fx_bd root-e >/dev/null; printf 'other-arg\t%s\n' "$?"
    run_lib map fx_bd >/dev/null; printf 'fail-verb\t%s\n' "$?"
    RUN_LIB_STUB_FAIL=""
    run_lib runs no_such_reader work-a >/dev/null 2>&1; printf 'no-reader\t%s\n' "$?"
    RUN_LIB_STUB_RUNS="$TMP/absent.json"
    printf 'no-file\t%s\n' "$(run_lib map fx_bd)"
    printf '#!/bin/sh\ncat %s\n' "$TMP/every-run.json" > "$TMP/runs-cmd"; chmod +x "$TMP/runs-cmd"
    RUN_LIB_STUB_CMD="$TMP/runs-cmd"
    printf 'cmd\t%s\n' "$(run_lib runs fx_bd work-a | jq -r 'map(.root) | join(",")')"
    printf '#!/bin/sh\nexit 1\n' > "$TMP/runs-cmd"
    run_lib map fx_bd >/dev/null 2>&1; printf 'cmd-fails\t%s\n' "$?"
    RUN_LIB_STUB_CMD=""
    printf 'logged\t%s\n' "$(head -n 1 "$TMP/stub.log")"
)"
while IFS=$'\t' read -r name verdict; do
    case "$name" in
        fail-arg) eq "$verdict" "1" "(STUB) a call RUN_LIB_STUB_FAIL names as <verb>:<arg> fails" ;;
        other-arg) eq "$verdict" "0" "(STUB) the same verb with another argument answers" ;;
        fail-verb) eq "$verdict" "1" "(STUB) a verb RUN_LIB_STUB_FAIL names fails" ;;
        no-reader) eq "$verdict" "2" "(STUB) a reader the caller never defined is a usage error" ;;
        no-file) eq "$verdict" "[]" "(STUB) a runs file that does not exist is a store with no runs" ;;
        cmd) eq "$verdict" "root-a0,root-a1" "(STUB) RUN_LIB_STUB_CMD's output is the runs each call answers from" ;;
        cmd-fails) eq "$verdict" "1" "(STUB) a RUN_LIB_STUB_CMD that fails fails the call" ;;
        logged) eq "$verdict" "runs fx_bd work-a" "(STUB) each call is logged with the reader it was given" ;;
        *) eq "$verdict" "same" "(STUB) the stub answers as the lib does: $name" ;;
    esac
done <<< "$STUB_OUT"

echo "# every reader sources the one definition"
# A reader names the file in the line that sources it, or, when it sources it
# through a variable, in the `# shellcheck source=` directive above that line,
# which run-tests.sh reads the same way. Other comment lines are left out, so a
# reader that names the definition in prose but no longer calls it still fails.
READERS="assets/scripts/step-close.sh
overlays/work-context/.claude/hooks/work-context.sh
assets/scripts/self-review-check.sh
packs/gascity-keeper/assets/scripts/rebase-check.sh
assets/scripts/work-tree-holder.sh
assets/scripts/gate-ensure.sh
assets/scripts/gc-helm.sh
assets/scripts/queue-priority.sh
assets/scripts/priority-lib.sh
assets/scripts/liveness-sweep.sh
doctor/check-blocked-work-armed/run.sh
doctor/check-root-advancing/run.sh"
while IFS= read -r r; do
    [ -n "$r" ] || continue
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    if grep -qE '(^|[[:space:];&|])(\.|source)[[:space:]].*run-lib\.sh' <<< "$code" \
       || { grep -qE '^[[:space:]]*# shellcheck source=([^[:space:]]*/)?run-lib\.sh' "$f" \
            && grep -qE '(^|[[:space:];&|])\.[[:space:]]+"\$' <<< "$code"; }; then
        ok "(READERS) $r sources run-lib.sh"
    else
        bad "(READERS) $r sources run-lib.sh"
    fi
    grep -qE 'run_lib (runs|subject|map)|RUN_JQ' <<< "$code" \
        && ok "(READERS) $r calls a verb or applies \$RUN_JQ" \
        || bad "(READERS) $r calls a verb or applies \$RUN_JQ"
done <<< "$READERS"

echo "# no private copies"
# Specs and generated renders are history and output, not readers.
DEF_RE='def[[:space:]]+(run_is_root|run_convoy|run_tracked|run_of|run_rows)\b'
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/run-lib.test.sh") continue ;; esac
        COPIES="$COPIES ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$DEF_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside run-lib.sh defines its own run defs"

echo
echo "run-lib: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
