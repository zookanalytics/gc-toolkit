#!/usr/bin/env bash
# Hermetic test for assets/scripts/deferred-dispatch.sh.
#
# WHAT THE SCRIPT IS FOR. `gc sling` pours immediately and reads no `blocks`
# deps, so sequencing used to be an agent remembering not to dispatch yet — a
# hold with no home in the ledger, invisible to everyone and lost when the
# holder died. `arm` writes that pending dispatch onto the work bead, and the
# deferred-dispatch order's pass, `gctk bead start-armed`, performs it once
# nothing holds the bead. The arm's keys, its verbs and its start are gctk's,
# and services/gctk/arm's Go tests hold the start's rules; this script keeps
# `arm` and `disarm` for the callers that name it, and `notify` and `list`.
#
# What is exercised:
#   * arm hands its call to the gctk this checkout builds, which writes the
#     record over the fixture store in one write that APPENDS its note, records
#     the target's default formula when no --sling-arg names one, and names
#     what holds the bead now; --sling-arg passes the formula as --on <formula>
#     or --on=<formula> and nothing else; arm's refusals (already routed,
#     closed, at a status other than open, a wait edge into another store, no
#     target, a bead the store does not hold) write nothing;
#   * disarm removes the arm through gctk and then clears a notice owed, in a
#     write of its own;
#   * list prints the start's dry run for each arm, one line each in the shape
#     `<id> -> <target> [<state>] — <reason>`, then each notice owed;
#     list --json prints the listing alone;
#   * notify, the dispatch a named agent's work owes: a mail at once when bd
#     reports the bead ready, otherwise a notice recorded on the bead; it
#     refuses a bead not assigned to the agent, owes nothing on a closed or
#     claimed one, and keeps the record when no turn is requested or its
#     readiness read fails. A notice is done only once the agent's turn is
#     requested: a mail that fails, or is saved with no turn requested, is
#     followed by gc session nudge, and a notice whose nudge fails too stays
#     owed; its retire leaves a record that names another agent since its read;
#     a title or a notice value that spells a second row forges none;
#   * the store each verb's reads are pinned to;
#   * SCRATCH CLEANUP — every verb that stages a temp file leaves none behind.
#
# No live city, Dolt, network, gc or bd — only jq, stubs, a tmpdir, and the
# gctk this checkout builds, which reads and writes the stub store.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/deferred-dispatch.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-deferred-dispatch-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$SUT" ] || chmod +x "$SUT" 2>/dev/null

# The arm's verbs and its start's dry run are gctk's, so the suite builds gctk
# from this checkout and the script runs it over the fixture store below. The
# config gctk reads for a target's default formula names the two pools the
# fixtures arm for.
HOLDS_STUB="$HERE/holds-store.stub.sh"
GCTK_BIN="$("$HOLDS_STUB" build "$TMP/gctk")" || { echo "FAIL - gctk did not build, so no arm can be made"; exit 1; }
HOLDS_CONFIG=$(jq -nc '{ok: true, config: {Agents: [{Name: "pool", Dir: "rig", DefaultSlingFormula: "mol-polecat-work"}, {Name: "other", Dir: "rig", DefaultSlingFormula: "mol-polecat-work"}]}}')
export GCTK_BIN HOLDS_STUB HOLDS_CONFIG GC_NO_API=1
export STUB_GCTK_LOG="$TMP/gctk-reads.log"
LOCKS="$TMP/gctk/city/.gc/runtime/packs/gc-toolkit"

# --- stubs -------------------------------------------------------------------
# $TMP/beads.json is the store: an array of beads, each carrying an extra
# `_ready` flag standing in for bd's own readiness predicate, which the
# notices' readiness read asks for. gctk's own calls read and write the same
# store through holds-store.stub.sh.
BIN="$TMP/bin"; mkdir -p "$BIN"

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/bd" <<'STUB'
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
# Minimal bd stub over $STORE. Understands only the calls the SUT makes.
set -u
STORE="${STUB_STORE:?}"
# Global flags precede the verb, as they do for real bd. The store is a single
# fixture file, so --db is consumed rather than honoured; it only records that
# the read is pinned, which turns off the by-id routing modeled under `list`.
pinned=0
while :; do
    case "${1:-}" in
        --db) pinned=1; shift 2 || shift || true ;;
        *) break ;;
    esac
done
# STUB_RACE_AT and STUB_RACE_JQ land a write another actor makes: the first
# call whose arguments contain STUB_RACE_AT applies the jq program STUB_RACE_JQ
# to the store before it is answered. It fires once; STUB_RACE_FIRED records it.
if [ -n "${STUB_RACE_AT:-}" ] && [ ! -e "${STUB_RACE_FIRED:?}" ]; then
    case " $* " in
        *"$STUB_RACE_AT"*)
            : > "$STUB_RACE_FIRED"
            jq -c "${STUB_RACE_JQ:?}" "$STUB_STORE" > "$STUB_STORE.race" && mv "$STUB_STORE.race" "$STUB_STORE" ;;
    esac
fi
if [ -n "${STUB_BD_LIST_FAIL:-}" ] && [ "${1:-}" = "list" ]; then
    echo "bd: simulated listing failure" >&2; exit 1
fi
# Every `show` fails once the file STUB_SHOW_FAIL_WHEN names exists.
if [ -n "${STUB_SHOW_FAIL_WHEN:-}" ] && [ -e "$STUB_SHOW_FAIL_WHEN" ] && [ "${1:-}" = "show" ]; then
    echo "bd: simulated show failure" >&2; exit 1
fi
case "${1:-}" in
  list)
    shift
    key=""; ready=0; all=0; gates=0; id=""; parent=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --has-metadata-key) shift; key="${1:-}" ;;
        --parent) shift; parent="${1:-}" ;;
        --id) shift; id="${1:-}" ;;
        --ready) ready=1 ;;
        --all) all=1 ;;
        --include-gates) gates=1 ;;
        *) : ;;
      esac
      shift || true
    done
    # A listing by one metadata key that fails while every other answers: the
    # notice listing failing on its own.
    if [ -n "${STUB_BD_LIST_FAIL_KEY:-}" ] && [ "$key" = "$STUB_BD_LIST_FAIL_KEY" ]; then
      echo "bd: simulated listing failure for $key" >&2; exit 1
    fi
    # Real bd refuses this combination outright:
    #   "validation failed: --ready cannot filter on IDFilter (--id); the
    #    blocker-aware ready query cannot be narrowed to specific ids"
    # The stub must refuse it too, or it will happily serve a query that can
    # only ever error against the live tool.
    if [ "$ready" = "1" ] && [ -n "$id" ]; then
      echo "Error: validation failed: --ready cannot filter on IDFilter (--id)" >&2; exit 1
    fi
    # A by-id read that fails while the armed listings answer: the hold walk's
    # read, failing on its own.
    if [ -n "${STUB_BD_LIST_ID_FAIL:-}" ] && [ -n "$id" ]; then
      echo "bd: simulated by-id listing failure" >&2; exit 1
    fi
    # `--id` takes a comma list (the bulk blocker-status read passes many). Real
    # `bd list --json` carries each bead's own outgoing edges under `.dependencies`
    # in the list-edge shape ({issue_id: self, depends_on_id: blocker, type}); the
    # SUT reads its candidates' blockers off that snapshot rather than a dep-list
    # per bead, so the stub must render `.dependencies` from the `_deps` fixture
    # field. A blocker's STATUS is NOT part of that edge shape — it is resolved by
    # a separate `bd list --id <blocker>`, so the blocker must be its own bead in
    # the store, exactly as it is live.
    #
    # `gc bd` routes a by-id read to the store that holds the id it names, ahead
    # of GC_RIG, unless --db pins the store. Modeled for the case a check must
    # survive: an unpinned --id list none of whose ids has a row in this store,
    # but which another store holds (STUB_FOREIGN_STORE), is answered from that
    # other store, where the ids do have rows.
    src="$STORE"
    # STUB_LIST_STORE answers every listing from the view a pass started from,
    # while show and update reach the store as it is now: a write that landed
    # between a pass's listing and its later read of the same bead.
    [ -n "${STUB_LIST_STORE:-}" ] && src="$STUB_LIST_STORE"
    if [ "$pinned" = 0 ] && [ -n "$id" ] && [ -n "${STUB_FOREIGN_STORE:-}" ] \
       && jq -e --arg id "$id" '($id | split(",")) as $ids | all(.[]; (.id as $i | $ids | index($i)) == null)' "$STORE" >/dev/null \
       && jq -e --arg id "$id" '($id | split(",")) as $ids | any(.[]; (.id as $i | $ids | index($i)) != null)' "$STUB_FOREIGN_STORE" >/dev/null; then
      src="$STUB_FOREIGN_STORE"
    fi
    # Real bd hides a gate bead from a listing unless --include-gates asks for
    # it, so a fixture bead with issue_type "gate" is hidden the same way.
    # --parent names the parent a listed bead carries in the fixture's `parent`
    # field; a fixture with none is no bead's child.
    jq -c --arg k "$key" --arg id "$id" --argjson ready "$ready" --argjson all "$all" --argjson gates "$gates" \
          --arg parent "$parent" '
      ($id | if . == "" then [] else split(",") end) as $ids
      | [ .[]
        | select($k == "" or (.metadata | has($k)))
        | select(($ids | length) == 0 or (.id as $i | $ids | index($i)))
        | select($all == 1 or .status != "closed")
        | select($ready == 0 or (._ready == true))
        | select($gates == 1 or (.issue_type // "") != "gate")
        | select($parent == "" or (.parent // "") == $parent)
        | . as $b
        | .dependencies = [ ($b._deps // [])[] | {issue_id: $b.id, depends_on_id: .id, type: .dependency_type} ]
        | del(._ready) | del(._deps) ]' "$src"
    ;;
  show)
    # Real `bd show --json` renders the bead's own edges under `.dependencies`
    # in the show shape ({id, dependency_type, issue_type, status}), each target
    # resolved in this store and one with no row left out, while its
    # dependency_count counts every edge, the ones left out included.
    id="${2:-}"
    src="$STORE"
    out="$(jq -c --arg id "$id" '
      . as $store
      | [ .[] | select(.id == $id) | . as $b
          | .dependency_count = (($b._deps // []) | length)
          | .dependencies = [ ($b._deps // [])[] | . as $e
              | ($store | map(select(.id == $e.id)) | .[0]) as $t
              | select($t != null)
              | {id: $e.id, dependency_type: $e.dependency_type, issue_type: ($t.issue_type // "task"), status: $t.status} ]
          | del(._ready) | del(._deps) ]' "$src")"
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      # bd answers an OBJECT, not an empty array, when nothing resolves.
      echo '{"error":"no issues found matching the provided IDs","schema_version":1}'
    else
      printf '%s\n' "$out"
    fi
    ;;
  update)
    shift
    id="${1:-}"; shift || true
    sets=(); unsets=(); note=""; note_mode=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; sets+=("${1:-}") ;;
        --set-metadata=*) sets+=("${1#--set-metadata=}") ;;
        --unset-metadata) shift; unsets+=("${1:-}") ;;
        --unset-metadata=*) unsets+=("${1#--unset-metadata=}") ;;
        --append-notes) shift; note="${1:-}"; note_mode="append" ;;
        --append-notes=*) note="${1#--append-notes=}"; note_mode="append" ;;
        # Modelled deliberately: bd's --notes REPLACES. A stub that ignored it
        # would let a destructive-write regression pass the append assertions.
        --notes) shift; note="${1:-}"; note_mode="replace" ;;
        --notes=*) note="${1#--notes=}"; note_mode="replace" ;;
        *) : ;;
      esac
      shift || true
    done
    # One jq pass lands the whole update, in bd's order: each --set-metadata
    # k=v split at its first =, each --unset-metadata, then the notes, appended
    # or replaced.
    tmp="$STORE.$$"
    jq -c --arg id "$id" --arg mode "$note_mode" --arg n "$note" \
       --argjson ns "${#sets[@]}" '
      ($ARGS.positional[:$ns] | map(split("=") as $p | if ($p | length) <= 1 then [., .] else [$p[0], ($p[1:] | join("="))] end)) as $sets
      | $ARGS.positional[$ns:] as $unsets
      | map(if .id == $id then
          reduce $sets[] as [$k, $v] (.; .metadata[$k] = $v)
          | reduce $unsets[] as $k (.; .metadata |= del(.[$k]))
          | (if $mode == "append" then .notes = ((.notes // "") + (if (.notes // "") == "" then "" else "\n" end) + $n)
             elif $mode == "replace" then .notes = $n else . end)
        else . end)' "$STORE" --args ${sets[@]+"${sets[@]}"} ${unsets[@]+"${unsets[@]}"} > "$tmp" && mv "$tmp" "$STORE"
    echo "updated $id"
    ;;
  dep)
    # `dep list <id> --json` reads a bead's own outgoing edges
    # (own_blocks_unresolved_ids). Real bd answers an ARRAY of {id,
    # dependency_type, status} and an ERROR OBJECT (not an array) for an
    # unresolvable id, so the stub serves both shapes to exercise the SUT's
    # fail-closed array check.
    shift
    [ "${1:-}" = "list" ] || { echo "bd stub: unsupported 'dep ${1:-}'" >&2; exit 2; }
    shift; depid="${1:-}"
    if [ "$(jq -r --arg id "$depid" 'any(.[]; .id == $id)' "$STORE")" != "true" ]; then
      echo '{"error":"resolving '"$depid"': no issue found","schema_version":1}'
    else
      # _deps models the bead's own edges. Real bd hides an edge whose target
      # has no row in this store (cross-repo/external): it warns on stderr and
      # omits it from the array, so `bd dep list <bead>` returns [] for a bead
      # whose only blocker is cross-store. Model that, so
      # own_blocks_unresolved_ids sees the edge dep list dropped. An in-store
      # gate resolves here, as it does live, though a default listing hides it.
      jq -c --arg id "$depid" '
        . as $store
        | [ .[] | select(.id == $id) ] | .[0] as $b
        | [ ($b._deps // [])[] | select(.id as $t | ($store | any(.[]; .id == $t))) ]' "$STORE"
    fi
    ;;
  *) echo "bd stub: unsupported '${1:-}'" >&2; exit 2 ;;
esac
STUB
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
if [ "${1:-}" = "bd" ]; then
    shift
    # A call the gctk under test makes answers from the same fixture, through
    # the seam holds-store.stub.sh keeps, so the real binary reads and writes
    # this store.
    if [ -n "${HOLDS_STUB_READ:-}" ]; then
        printf '%s\n' "$*" >> "${STUB_GCTK_LOG:-/dev/null}"
        [ -z "${STUB_BD_LIST_FAIL:-}" ] || export HOLDS_FAIL=list
        HOLDS_STORE="$STUB_STORE" exec "${HOLDS_STUB:?}" answer "$@"
    fi
    printf '%s\n' "$*" >> "${STUB_BD_LOG:-/dev/null}"
    # The bd stub runs in this process rather than a second bash's.
    export VIA_GC_BD=1
    . "${0%/*}/bd" "$@"
    exit
fi
if [ "${1:-}" = "sling" ]; then
    shift
    printf '%s\n' "$*" >> "${STUB_SLING_LOG:?}"
    exit 0
fi
# A notice is a `gc mail send`, one line per call, answering as gascity's
# doMailSendJSON does. STUB_MAIL_RC fails the send outright, saving nothing.
# A send whose dedup key matches a message still in the agent's mailbox
# (STUB_MAILBOX, one "<to> <key>" line per saved message) saves nothing,
# requests no turn and exits 0 with already_done. Any other send saves the
# message and then requests the turn, and STUB_MAIL_NUDGE_FAILS fails that
# request: the real command then says so only on stderr and by leaving
# `notified` out of its --json result, and still exits 0.
if [ "${1:-}" = "mail" ]; then
    shift
    printf '%s\n' "$*" >> "${STUB_MAIL_LOG:?}"
    if [ "${STUB_MAIL_RC:-0}" != 0 ]; then
        echo "gc mail send: simulated send failure" >&2; exit "$STUB_MAIL_RC"
    fi
    to="${2:-}"; dedup=""; json=0; prev=""
    for a in "$@"; do
        [ "$prev" = "--dedup" ] && dedup="$a"
        [ "$a" = "--json" ] && json=1
        prev="$a"
    done
    if [ -n "$dedup" ] && grep -qxF -- "$to $dedup" "${STUB_MAILBOX:?}" 2>/dev/null; then
        [ "$json" = 1 ] && printf '%s\n' '{"schema_version":"1","ok":true,"command":"mail.send","action":"send","id":"m-first","count":0,"already_done":true}'
        exit 0
    fi
    printf '%s %s\n' "$to" "$dedup" >> "$STUB_MAILBOX"
    # STUB_MAIL_REWRITE is a jq program applied to the store while the mail is
    # sent: a write another caller lands in the meantime.
    if [ -n "${STUB_MAIL_REWRITE:-}" ]; then
        jq -c "$STUB_MAIL_REWRITE" "${STUB_STORE:?}" > "$STUB_STORE.rw" && mv "$STUB_STORE.rw" "$STUB_STORE"
    fi
    if [ -n "${STUB_MAIL_NUDGE_FAILS:-}" ]; then
        echo "gc mail send: nudge failed: simulated nudge-store failure" >&2
        [ "$json" = 1 ] && printf '%s\n' '{"schema_version":"1","ok":true,"command":"mail.send","action":"send","id":"m-new","count":1}'
        exit 0
    fi
    [ "$json" = 1 ] && printf '%s\n' '{"schema_version":"1","ok":true,"command":"mail.send","action":"send","id":"m-new","count":1,"notified":true}'
    exit 0
fi
# A turn requested directly is a `gc session nudge`: one line per call, and
# STUB_NUDGE_RC is its exit.
if [ "${1:-}" = "session" ] && [ "${2:-}" = "nudge" ]; then
    shift 2
    printf '%s\n' "$*" >> "${STUB_NUDGE_LOG:?}"
    if [ "${STUB_NUDGE_RC:-0}" != 0 ]; then
        echo "gc session nudge: simulated nudge failure" >&2; exit "$STUB_NUDGE_RC"
    fi
    exit 0
fi
echo "gc stub: unsupported '${1:-}'" >&2; exit 2
STUB
chmod +x "$BIN/bd" "$BIN/gc"

export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/beads.json"
export STUB_SLING_LOG="$TMP/sling.log"
export STUB_MAIL_LOG="$TMP/mail.log"
export STUB_MAILBOX="$TMP/mailbox"
export STUB_NUDGE_LOG="$TMP/nudge.log"
export BEADS_ACTOR="test-actor"
unset GC_AGENT GC_RIG GC_RIG_ROOT GC_MAX_DISPATCH_SLING_FAILURES 2>/dev/null || true

store() {
    printf '%s' "$1" > "$STUB_STORE"
    : > "$STUB_SLING_LOG"; : > "$STUB_MAIL_LOG"; : > "$STUB_MAILBOX"; : > "$STUB_NUDGE_LOG"
}
meta()  { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
notes() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STUB_STORE"; }
slings() { wc -l < "$STUB_SLING_LOG" | tr -d ' '; }
mails() { wc -l < "$STUB_MAIL_LOG" | tr -d ' '; }
mailbox() { wc -l < "$STUB_MAILBOX" | tr -d ' '; }
nudges() { wc -l < "$STUB_NUDGE_LOG" | tr -d ' '; }
locks_left() { find "$LOCKS" -name 'dispatch-*.lock' 2>/dev/null | wc -l | tr -d ' '; }
# armed <target> [<formula>] [<more>]: the metadata of a bead armed for <target>
# on <formula>, or on its default, with <more> JSON members added.
armed() {
    local args='[]'
    [ -z "${2:-}" ] || args="[\"--on\",\"$2\"]"
    printf '"gc.dispatch_when_ready":"%s","gc.dispatch_when_ready_args":%s,"gc.dispatch_when_ready_armed_by":"x","gc.dispatch_when_ready_armed_at":"2026-11-13T06:19:00Z"%s' \
        "$1" "$(jq -nc --arg a "$args" '$a')" "${3:+,$3}"
}

# --- ARM ---------------------------------------------------------------------
echo "# arm"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"mayor: dispatch after b-0 lands","_ready":false}]'
out="$("$SUT" arm b-1 --target rig/pool --reason "needs b-0" 2>&1)"; rc=$?
eq "$rc" 0 "arm exits 0"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "arm records the target"
eq "$(meta b-1 gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "with no --sling-arg, arm records the target's default formula"
eq "$(meta b-1 gc.dispatch_when_ready_armed_by)" "test-actor" "arm records who armed it"
has "$(meta b-1 gc.dispatch_when_ready_armed_at)" "T" "arm records when"
eq "$(meta b-1 gc.dispatch_when_ready_reason)" "needs b-0" "arm records the reason"
has "$(notes b-1)" "mayor: dispatch after b-0 lands" "arm APPENDS to notes (prior note survives)"
has "$(notes b-1)" "deferred-dispatch: dispatch armed by test-actor" "arm's own note keeps the prefix its readers find it by"
has "$out" "armed b-1 for rig/pool on mol-polecat-work" "arm says what it did"
has "$out" "Nothing holds it now" "and that nothing holds it"
eq "$(locks_left)" "0" "the arm leaves no dispatch lock behind"

store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":""}]'
"$SUT" arm b-1 --target rig/pool --sling-arg --on --sling-arg mol-validate-close --reason r >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_args)" '["--on","mol-validate-close"]' "--sling-arg --on --sling-arg <formula> records that formula"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":""}]'
"$SUT" arm b-1 --target rig/pool --sling-arg --on=mol-polecat-report --reason r >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_args)" '["--on","mol-polecat-report"]' "--sling-arg --on=<formula> records that formula"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":""}]'
"$SUT" arm b-1 --target rig/pool >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_reason)" "no reason was given" "an arm with no --reason says none was given"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" arm b-1 --target rig/pool --sling-arg --var --sling-arg a=b --reason r 2>&1)"; rc=$?
eq "$rc" 2 "a --sling-arg that names no formula is a usage error"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "and writes nothing"
has "$out" "--on <formula>" "naming the form it takes"

# What holds the bead, as the arm reads it: its blocker, or a park on its epic.
store '[{"id":"b-0","status":"open","assignee":"","metadata":{},"notes":"","title":"Land b-0"},
        {"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"b-0","dependency_type":"blocks"}]}]'
out="$("$SUT" arm b-1 --target rig/pool --reason r 2>&1)"
hasnt "$out" "Nothing holds it" "arm on a blocked bead does not claim it will dispatch at once"
has "$out" 'b-0 "Land b-0" holds it' "arm names the blocker the arm now waits on"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"epic","dependency_type":"parent-child"}]},
        {"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":"","_deps":[{"id":"park","dependency_type":"blocks"}]},
        {"id":"park","status":"open","issue_type":"gate","title":"Parked until the operator unparks it","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" arm b-1 --target rig/pool --reason r 2>&1)"; rc=$?
eq "$rc" 0 "arm records a dispatch under a parked epic"
has "$out" 'park "Parked until the operator unparks it" on its ancestor epic holds it' "arm names the park that holds it"

# A gate is hidden from a listing that does not ask for gates, but gctk's reads
# ask for every hidden type, so an armed gate is answered as any bead is.
store '[{"id":"g-1","status":"open","issue_type":"gate","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" arm g-1 --target rig/pool --reason r 2>&1)"; rc=$?
eq "$rc" 0 "arm records the dispatch on a gate bead"
has "$out" "Nothing holds it now" "arm answers a gate bead from its own edges"

# gc.execution_routed_to is provenance, not a live queue, so a blocked bead
# carrying only it is the shape doctor/check-blocked-work-armed flags and names
# arming as the fix for. arm accepts it, or that remedy is a dead end.
store '[{"id":"b-2","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/pool"},"notes":""}]'
out="$("$SUT" arm b-2 --target rig/pool --reason r 2>&1)"; rc=$?
eq "$rc" 0 "arm accepts a bead carrying only gc.execution_routed_to"
eq "$(meta b-2 gc.dispatch_when_ready)" "rig/pool" "and records the dispatch"

# An arm already on the bead for the same target and formula writes nothing.
store '[{"id":"b-3","status":"open","assignee":"","metadata":{'"$(armed rig/pool mol-x)"'},"notes":"armed once"}]'
out="$("$SUT" arm b-3 --target rig/pool --sling-arg --on --sling-arg mol-x --reason again 2>&1)"; rc=$?
eq "$rc" 0 "arming the same arm again exits 0"
has "$out" "already armed" "and says so"
eq "$(notes b-3)" "armed once" "writing nothing"

echo "# arm refusals"
# bd resolves a dependency within one store, so a wait edge onto a bead in
# another rig holds nothing here, and the start would send the bead while that
# bead is still open. arm refuses it. Another store holds ra-x, and this run is
# unpinned, so gc would answer a read naming ra-x from that store: every read
# gctk makes after asking where the store is names that store.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"ra-x","dependency_type":"blocks","status":"open"}]}]'
: > "$STUB_GCTK_LOG"
out="$("$SUT" arm b-1 --target rig/pool --reason r 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead with a wait edge into another store"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "and writes nothing"
has "$out" "ra-x" "naming the edge's bead"
eq "$(sed -n '1p' "$STUB_GCTK_LOG")" "where --json" "the unpinned call first asks gc which store it resolves"
eq "$(sed '1d' "$STUB_GCTK_LOG" | grep -c -v '^--db /stub/.beads ')" "0" "and every read after it names that store"
: > "$STUB_GCTK_LOG"
out="$("$SUT" arm b-1 --target rig/pool --reason r --db "$TMP/rig/.beads" 2>&1)"; rc=$?
eq "$rc" 1 "a pinned arm refuses it too"
eq "$(grep -c -v "^--db $TMP/rig/.beads " "$STUB_GCTK_LOG")" "0" "every read of a pinned arm names the store --db names"

store '[{"id":"b-2r","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/pool"},"notes":""}]'
out="$("$SUT" arm b-2r --target rig/pool --reason r 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead already routed (gc.routed_to)"
eq "$(meta b-2r gc.dispatch_when_ready)" "<absent>" "a refused arm writes nothing"
has "$out" "dispatched already" "the refusal names the reason"

store '[{"id":"b-3","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" arm b-3 --target rig/pool --reason r 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a closed bead"

for HELD in blocked deferred hooked pinned; do
  store '[{"id":"b-h","status":"'"$HELD"'","assignee":"","metadata":{},"notes":""}]'
  out="$("$SUT" arm b-h --target rig/pool --reason r 2>&1)"; rc=$?
  eq "$rc" 1 "arm refuses a $HELD bead"
  eq "$(meta b-h gc.dispatch_when_ready)" "<absent>" "a refused $HELD arm writes nothing"
  has "$out" "sends an open bead alone" "the $HELD refusal says the start sends open beads only"
done

store '[{"id":"b-4","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" arm b-4 2>&1)"; rc=$?
eq "$rc" 2 "arm without --target is a usage error"
eq "$(meta b-4 gc.dispatch_when_ready)" "<absent>" "arm without --target writes nothing"
out="$("$SUT" arm b-nope --target rig/pool --reason r 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead that does not resolve"
out="$("$SUT" arm b-4 --target rig/nowhere --reason r 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a target whose default formula the config does not give"
eq "$(meta b-4 gc.dispatch_when_ready)" "<absent>" "and writes nothing"
eq "$(locks_left)" "0" "no refusal leaves a dispatch lock behind"

# --- disarm ------------------------------------------------------------------
echo "# disarm"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$(armed rig/pool mol-x '"gc.dispatch_when_ready_reason":"r","gc.dispatch_when_ready_fail_count":"2"')"'},"notes":"keep me"}]'
out="$("$SUT" disarm b-1 --reason "superseded" 2>&1)"; rc=$?
eq "$rc" 0 "disarm exits 0"
for k in gc.dispatch_when_ready gc.dispatch_when_ready_args gc.dispatch_when_ready_armed_by gc.dispatch_when_ready_armed_at gc.dispatch_when_ready_reason gc.dispatch_when_ready_fail_count; do
  eq "$(meta b-1 "$k")" "<absent>" "disarm clears $k"
done
has "$(notes b-1)" "keep me" "disarm appends to notes rather than replacing"
has "$(notes b-1)" "deferred-dispatch: dispatch record cleared at" "disarm's note keeps its prefix"
has "$(notes b-1)" "superseded" "disarm records why"
store '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":""}]'
"$SUT" disarm n-1 >/dev/null 2>&1; rc=$?
eq "$rc" 0 "disarm on a bead with only a notice exits 0"
eq "$(meta n-1 gc.notify_when_ready)" "<absent>" "disarm clears a notice owed too"
store '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{'"$(armed rig/pool mol-x '"gc.notify_when_ready":"gc-toolkit.mechanik"')"'},"notes":""}]'
"$SUT" disarm n-1 >/dev/null 2>&1
eq "$(meta n-1 gc.dispatch_when_ready)" "<absent>" "disarm on a bead with an arm and a notice clears the arm"
eq "$(meta n-1 gc.notify_when_ready)" "<absent>" "and the notice, in the same verb"
store '[{"id":"p-1","status":"open","assignee":"","metadata":{},"notes":"untouched"}]'
out="$("$SUT" disarm p-1 2>&1)"; rc=$?
eq "$rc" 0 "disarm of a bead with no arm exits 0"
eq "$(notes p-1)" "untouched" "and writes nothing"
out="$("$SUT" disarm p-nope 2>&1)"; rc=$?
eq "$rc" 1 "disarm of a bead the store does not hold fails"

# --- list --------------------------------------------------------------------
# list prints the start's dry run, which writes nothing: each arm in the state
# the next pass would leave it in.
echo "# list"
store '[
 {"id":"b-1","status":"open","assignee":"","metadata":{'"$(armed rig/pool mol-x '"gc.dispatch_when_ready_reason":"needs b-0"')"'},"notes":"","_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""},
 {"id":"b-2","status":"open","assignee":"","metadata":{'"$(armed rig/other)"'},"notes":""},
 {"id":"b-3","status":"closed","assignee":"","metadata":{'"$(armed rig/pool mol-x)"'},"notes":""},
 {"id":"b-5","status":"blocked","assignee":"","metadata":{'"$(armed rig/pool mol-x)"'},"notes":""},
 {"id":"b-6","status":"open","assignee":"","metadata":{'"$(armed rig/pool mol-x '"merge_result":"pull_request"')"'},"notes":""},
 {"id":"b-7","status":"open","assignee":"","metadata":{'"$(armed rig/pool mol-x '"gc.dispatch_when_ready_fail_count":"3"')"'},"notes":""},
 {"id":"b-8","status":"open","assignee":"","labels":["hold:mayor"],"metadata":{'"$(armed rig/pool mol-x)"'},"notes":""},
 {"id":"b-4","status":"open","assignee":"","metadata":{},"notes":""}]'
before="$(cat "$STUB_STORE")"
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list exits 0"
has "$out" "b-1 -> rig/pool [HELD by b-0] — needs b-0" "list shows a held arm with its blocker and its reason"
has "$out" "b-2 -> rig/other [DISPATCHABLE NOW]" "list shows a dispatchable arm"
has "$out" "b-3 -> rig/pool [CLOSED" "list shows a closed arm"
has "$out" "b-5 -> rig/pool [STRANDED — it is at status blocked" "list names a stranded arm"
has "$out" "b-6 -> rig/pool [DELIVERED — another path already delivered its work (merge_result=pull_request)" "list flags an already-delivered arm"
has "$out" "b-7 -> rig/pool [CAPPED — 3 attempts have reached the cap of 3" "list flags a capped arm as needing a person"
has "$out" "b-8 -> rig/pool [HELD — its hold:mayor label holds it" "list names a label that holds an arm"
hasnt "$out" "b-4" "list shows only armed beads"
eq "$(cat "$STUB_STORE")" "$before" "list writes nothing"
eq "$(slings)" "0" "and slings nothing"

# --json prints the armed beads as bd lists them, which says nothing about what
# holds them, so it reads nothing else.
echo "# list --json makes one read"
export STUB_BD_LOG="$TMP/bd-json.log"; : > "$STUB_BD_LOG"; : > "$STUB_GCTK_LOG"
out="$("$SUT" list --json 2>/dev/null)"; rc=$?
eq "$rc" 0 "list --json exits 0"
eq "$(printf '%s' "$out" | jq -r '[.[].id] | sort | join(",")')" "b-1,b-2,b-3,b-5,b-6,b-7,b-8" "list --json prints the armed beads as bd lists them"
eq "$(wc -l < "$STUB_BD_LOG" | tr -d ' ')" "1" "list --json makes one read"
eq "$(wc -l < "$STUB_GCTK_LOG" | tr -d ' ')" "0" "and runs no dry run"
unset STUB_BD_LOG
out="$(STUB_BD_LIST_FAIL=1 "$SUT" list 2>&1)"; rc=$?
eq "$rc" 1 "list fails loudly when the arms cannot be read"
has "$out" "could not enumerate armed beads" "saying so"


# --- notify: the dispatch a named agent's work owes ---------------------------
# A named session's hook offers it a bead by assignee once bd reports the bead
# ready, and nothing wakes an idle named session when that happens. So notify
# mails the agent: at once when bd already reports the bead ready, and otherwise
# it records the notice for the reconcile pass.
echo "# notify"
store '[{"id":"n-1","title":"Edit city.toml","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"card: a city.toml edit","_ready":true}]'
out="$("$SUT" notify n-1 --agent gc-toolkit.mechanik --reason "first reaction: r" 2>&1)"; rc=$?
eq "$rc" 0 "notify exits 0"
eq "$(mails)" "1" "notify on a bead bd reports ready mails the agent at once"
has "$(cat "$STUB_MAIL_LOG")" "send gc-toolkit.mechanik --notify" "the mail goes to the agent and asks for its turn"
has "$(cat "$STUB_MAIL_LOG")" "-s Ready for you: n-1" "the mail names the bead"
has "$(cat "$STUB_MAIL_LOG")" "n-1 (Edit city.toml) is assigned to you" "with its title"
has "$(cat "$STUB_MAIL_LOG")" "run gc hook" "and says how to pick it up"
has "$(cat "$STUB_MAIL_LOG")" "--dedup ready-notice:n-1" "a resend about the same bead collapses onto the first"
has "$(cat "$STUB_MAIL_LOG")" "--json" "and the send reports whether it requested the turn"
eq "$(nudges)" "0" "a mail that requested the turn needs no nudge"
eq "$(meta n-1 gc.notify_when_ready)" "<absent>" "a notice sent at once leaves no record behind"
has "$(notes n-1)" "card: a city.toml edit" "notify APPENDS to notes (prior note survives)"
has "$(notes n-1)" "first reaction: r" "the note carries the reason"
has "$(notes n-1)" "notice sent to gc-toolkit.mechanik" "and records that the agent was told"
has "$out" "notified gc-toolkit.mechanik that n-1 is ready" "notify says what it did"
eq "$(slings)" "0" "a notice slings nothing"

store '[{"id":"n-2","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
        {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" notify n-2 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "notify on a bead that still waits exits 0"
eq "$(mails)" "0" "and sends nothing while bd does not report the bead ready"
eq "$(meta n-2 gc.notify_when_ready)" "gc-toolkit.mechanik" "it records the notice on the bead"
has "$(notes n-2)" "notice armed by test-actor" "with a note saying who armed it"
has "$out" "armed a notice on n-2 -> gc-toolkit.mechanik" "and says it armed the notice"

store '[{"id":"n-3","status":"open","assignee":"someone-else","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" notify n-3 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 1 "notify refuses a bead assigned to someone else"
has "$out" "its assignee is someone-else" "naming who holds it"
eq "$(mails)" "0" "and sends nothing"
eq "$(meta n-3 gc.notify_when_ready)" "<absent>" "and records nothing"
store '[{"id":"n-3","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" notify n-3 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 1 "notify refuses an unassigned bead"
has "$out" "Assign it first" "naming the write that comes first"

store '[{"id":"n-4","status":"closed","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":false}]'
out="$("$SUT" notify n-4 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "a closed bead owes no notice, and notify exits 0"
eq "$(mails)" "0" "sending nothing"
eq "$(meta n-4 gc.notify_when_ready)" "<absent>" "and recording nothing"
store '[{"id":"n-5","status":"in_progress","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":false}]'
out="$("$SUT" notify n-5 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "a bead its agent already claimed owes no notice"
eq "$(mails)" "0" "and gets none"
has "$out" "already claimed" "notify says why"
out="$("$SUT" notify n-5 2>&1)"; rc=$?
eq "$rc" 2 "notify without --agent is a usage error"
out="$("$SUT" notify nope --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 1 "notify on a bead the store does not hold fails"

# Once the record is down the notice is owed. A send that fails outright
# requests no turn, so gc session nudge requests it. A notice that gets no turn
# requested either way, or a readiness read that fails, leaves the record for
# the pass and still exits 0.
store '[{"id":"n-6","title":"Edit city.toml","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_MAIL_RC=1 "$SUT" notify n-6 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "a send that fails exits 0"
eq "$(mailbox)" "0" "saving no mail"
eq "$(nudges)" "1" "so the turn is requested with gc session nudge"
has "$(cat "$STUB_NUDGE_LOG")" "gc-toolkit.mechanik Ready for you: n-6 (Edit city.toml) is assigned to you" "naming the agent and the bead"
eq "$(meta n-6 gc.notify_when_ready)" "<absent>" "and the requested turn retires the notice"
has "$out" "requested gc-toolkit.mechanik's turn for n-6 with gc session nudge: gc mail send could not mail gc-toolkit.mechanik about n-6 (gc mail send: simulated send failure)" "notify says the mail failed and the nudge requested the turn"
store '[{"id":"n-6","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_MAIL_RC=1 STUB_NUDGE_RC=1 "$SUT" notify n-6 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "a send and a nudge that both fail still exit 0, since the notice is recorded"
eq "$(meta n-6 gc.notify_when_ready)" "gc-toolkit.mechanik" "and the record stays for the pass"
has "$out" "the next reconcile pass tries again" "notify says who tries again"
has "$out" "could not request gc-toolkit.mechanik's turn for n-6: gc mail send could not mail gc-toolkit.mechanik about n-6 (gc mail send: simulated send failure), and gc session nudge failed: gc session nudge: simulated nudge failure" "one line names both causes"

# gc mail send saves the mail before it requests the agent's turn, and exits 0
# when that request fails: it says so on stderr and leaves `notified` out of its
# --json result. Unread mail requests no turn, so the notice is not done.
echo "# notify on mail saved with no turn requested"
store '[{"id":"n-6","title":"Edit city.toml","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_MAIL_NUDGE_FAILS=1 "$SUT" notify n-6 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "notify exits 0"
eq "$(mailbox)" "1" "the mail is saved in the agent's mailbox"
eq "$(nudges)" "1" "and, since it requested no turn, the turn is requested with gc session nudge"
has "$(cat "$STUB_NUDGE_LOG")" "gc-toolkit.mechanik Ready for you: n-6 (Edit city.toml) is assigned to you" "naming the agent and the bead"
has "$(cat "$STUB_NUDGE_LOG")" "--reference-bead n-6" "about that bead, so a nudge still queued for it gives way"
eq "$(meta n-6 gc.notify_when_ready)" "<absent>" "the requested turn retires the notice"
has "$out" "nudge failed: simulated nudge-store failure" "gc mail send's diagnostic is kept, not discarded"
has "$out" "requested gc-toolkit.mechanik's turn for n-6 with gc session nudge" "notify says how the turn was requested"

store '[{"id":"n-6","title":"Edit city.toml","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_MAIL_NUDGE_FAILS=1 STUB_NUDGE_RC=1 "$SUT" notify n-6 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "a notice that gets no turn requested still exits 0, since it is recorded"
eq "$(meta n-6 gc.notify_when_ready)" "gc-toolkit.mechanik" "and stays owed for the pass, though its mail was saved"
eq "$(mailbox)" "1" "the saved mail stays in the mailbox"
has "$out" "nudge failed: simulated nudge-store failure" "the mail's diagnostic is kept"
has "$out" "simulated nudge failure" "and so is the nudge's"
has "$out" "turn was not requested; the next reconcile pass tries again" "notify says the turn was not requested"
hasnt "$(notes n-6)" "notice sent" "and no note says the agent was told"
store '[{"id":"n-7","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_BD_LIST_FAIL_KEY=gc.notify_when_ready "$SUT" notify n-7 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "a readiness read that fails still exits 0"
eq "$(mails)" "0" "sending nothing it could not prove ready"
eq "$(meta n-7 gc.notify_when_ready)" "gc-toolkit.mechanik" "and leaving the record for the pass"
has "$out" "could not read whether bd reports it ready" "notify says so"

echo "# list shows the notices owed"
NOTICES='[
 {"id":"n-1","title":"Edit city.toml","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true},
 {"id":"n-2","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""},
 {"id":"n-3","status":"closed","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":""},
 {"id":"n-4","status":"in_progress","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":""},
 {"id":"n-5","status":"open","assignee":"gc-toolkit/gc-toolkit.witness","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true},
 {"id":"n-6","status":"open","assignee":"","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true},
 {"id":"n-8","status":"deferred","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false}]'
store "$NOTICES"
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list exits 0 with notices owed"
has "$out" "n-1 -> notice to gc-toolkit.mechanik [READY — bd reports it ready]" "list shows a notice whose bead bd reports ready"
has "$out" "n-2 -> notice to gc-toolkit.mechanik [WAITING — bd does not report it ready yet]" "and one that waits on bd"
has "$out" "n-8 -> notice to gc-toolkit.mechanik [WAITING — status=deferred, which bd never reports ready]" "and one at a status bd never reports ready"
has "$out" "n-3 -> notice to gc-toolkit.mechanik [CLOSED" "and a closed bead's"
has "$out" "n-4 -> notice to gc-toolkit.mechanik [CLAIMED" "and a claimed bead's"
has "$out" "n-5 -> notice to gc-toolkit.mechanik [MOOT — no longer assigned to gc-toolkit.mechanik" "and a reassigned bead's"
hasnt "$out" "no pending dispatches" "a store with notices owed is not an empty queue"
out="$(STUB_BD_LIST_FAIL_KEY=gc.notify_when_ready "$SUT" list 2>&1)"; rc=$?
eq "$rc" 1 "list fails loudly when the notices cannot be read"

# jq decodes an escaped LF or unit separator in a string and prints it raw, so
# a title or a notice value that spells a second row would add a row list
# trusts.
echo "# a title or a notice value cannot forge a notice row"
store '[
 {"id":"n-1","title":"Edit\nn-9\u001fopen\u001fgc-toolkit/gc-toolkit.witness\u001fgc-toolkit/gc-toolkit.witness\u001f1\u001fforged","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false},
 {"id":"n-2","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik\nn-9\u001fclosed\u001fgc-toolkit.mechanik\u001fgc-toolkit.mechanik\u001f0\u001fforged"},"notes":"","_ready":false},
 {"id":"n-9","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false}]'
out="$("$SUT" list 2>&1)"; rc=$?
eq "$(printf '%s\n' "$out" | grep -c -F -e '-> notice to')" "3" "list shows one notice per bead"
has "$out" "n-1 -> notice to gc-toolkit.mechanik [WAITING" "with each bead's own agent"
hasnt "$out" "gc-toolkit/gc-toolkit.witness" "and none a title spelled"

# notify's retire after its mail re-reads the bead. The write lands while the
# mail goes out: the bead is reassigned, and the new assignee's notice is
# recorded.
echo "# notify's retire leaves a notice recorded since its read"
store '[{"id":"n-5","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_MAIL_REWRITE='map(if .id == "n-5" then (.assignee = "gc-toolkit/gc-toolkit.witness" | .metadata["gc.notify_when_ready"] = "gc-toolkit/gc-toolkit.witness") else . end)' \
    "$SUT" notify n-5 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "notify exits 0"
eq "$(mails)" "1" "it mails the agent the bead was assigned to when it read it"
eq "$(meta n-5 gc.notify_when_ready)" "gc-toolkit/gc-toolkit.witness" "and leaves the notice recorded for the new assignee meanwhile"
has "$out" "left the notice on n-5: its record now names gc-toolkit/gc-toolkit.witness" "saying why it left it"
store '[{"id":"n-5","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_MAIL_REWRITE='map(if .id == "n-5" then (.metadata |= del(.["gc.notify_when_ready"])) else . end)' \
    "$SUT" notify n-5 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "a record another caller already cleared leaves notify nothing to clear"
hasnt "$(notes n-5)" "notice record cleared" "so it writes no retire"
has "$out" "notified gc-toolkit.mechanik that n-5 is ready" "and says the agent was told"

# --- the store the reads are pinned to ---------------------------------------
# `gc bd` resolves its ledger from the invoking rig and ignores BEADS_DIR, so a
# rig-scoped call that does not pin --db reads whatever rig gc resolves.
echo "# store pinning"
export STUB_BD_LOG="$TMP/bd.log"
store '[{"id":"p-1","status":"open","assignee":"","metadata":{'"$(armed rig/pool mol-x)"'},"notes":""}]'
: > "$STUB_BD_LOG"; : > "$STUB_GCTK_LOG"
(GC_RIG_ROOT="$TMP/rigroot" "$SUT" list >/dev/null 2>&1)
has "$(cat "$STUB_BD_LOG")" "--db $TMP/rigroot/.beads" "GC_RIG_ROOT pins the script's reads to that rig's store"
eq "$(grep -c -v "^--db $TMP/rigroot/.beads " "$STUB_GCTK_LOG")" "0" "and every read of the dry run it runs"
: > "$STUB_BD_LOG"; : > "$STUB_GCTK_LOG"
("$SUT" list >/dev/null 2>&1)
hasnt "$(cat "$STUB_BD_LOG")" "--db" "with no GC_RIG_ROOT and no --db, the script pins nothing"
: > "$STUB_BD_LOG"; : > "$STUB_GCTK_LOG"
(GC_RIG_ROOT="$TMP/rigroot" "$SUT" list --db "$TMP/explicit/.beads" >/dev/null 2>&1)
has "$(cat "$STUB_BD_LOG")" "--db $TMP/explicit/.beads" "an explicit --db overrides GC_RIG_ROOT"
hasnt "$(cat "$STUB_BD_LOG")" "--db $TMP/rigroot/.beads" "and the rig-root default is not also passed"
eq "$(grep -c -v "^--db $TMP/explicit/.beads " "$STUB_GCTK_LOG")" "0" "and the dry run reads the store --db names"
unset STUB_BD_LOG

# ── scratch cleanup ─────────────────────────────────────────────────────────
# The EXIT trap reads a registry the allocations append to. Appending from a
# command substitution mutates a subshell's copy and the trap then removes
# nothing, so the cleanup has to be asserted on disk rather than read off the
# presence of a trap line.
SCRATCH="$TMP/scratch"
mkdir -p "$SCRATCH"
TMPDIR="$SCRATCH" "$SUT" list        >/dev/null 2>&1
TMPDIR="$SCRATCH" "$SUT" list --json >/dev/null 2>&1
store '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
TMPDIR="$SCRATCH" "$SUT" notify n-1 --agent gc-toolkit.mechanik >/dev/null 2>&1
LEFT=$(find "$SCRATCH" -maxdepth 1 -name 'gctk-deferred-dispatch.*' 2>/dev/null | wc -l | tr -d ' ')
eq "$LEFT" "0" "no verb leaves a staging file behind in TMPDIR"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
