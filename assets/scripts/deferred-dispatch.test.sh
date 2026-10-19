#!/usr/bin/env bash
# Hermetic test for assets/scripts/deferred-dispatch.sh.
#
# WHAT THE SCRIPT IS FOR. `gc sling` pours immediately and reads no `blocks`
# deps, so sequencing used to be an agent remembering not to dispatch yet — a
# hold with no home in the ledger, invisible to everyone and lost when the
# holder died. `arm` writes that pending dispatch onto the work bead; the
# `reconcile` pass performs it once bd itself reports the bead ready.
#
# What is exercised:
#   * arm writes the record and APPENDS to notes (a replacing write here would
#     destroy the dispatch note the arm is supposed to make legible);
#   * arm's fail-closed refusals — already routed, closed, no target;
#   * arm ACCEPTS a bead carrying only gc.execution_routed_to (execution
#     provenance, not a live queue): the shape doctor/check-blocked-work-armed
#     flags and names arming as the fix for, so refusing would be a dead end;
#   * arm's cross-store warning — a `blocks` edge bd cannot resolve in the
#     bead's own store holds nothing, so arm names it rather than announce an
#     immediate dispatch, pinned by --db or not, and withholds that announcement
#     whenever it could not read the bead's edges;
#   * the dispatch arm: ready + armed -> exactly one `gc sling` with the
#     recorded target and pass-through args, then the record cleared;
#   * the two-state gc.dispatch_when_ready_slung marker: a proven "slung@" marker
#     (or a bare-timestamp one) RETIRES the arm without a second sling, while an
#     unproven "slinging@" marker — a pass that died before confirming its sling —
#     is RE-SLUNG, so a crash mid-dispatch never silently loses the work; recovery
#     reads this one owned marker, not any lane-specific stamp, and the pre-sling
#     stamp is the unproven state so a crash there recovers as a re-sling;
#   * every OTHER arm that must NOT sling: held by a blocker on it or on an
#     ancestor (hold-lib.sh), assigned, sling failed;
#   * the hold: an armed child of a parked epic, one two levels down and one
#     whose epic waits on a task are held and named with the blocker's title in
#     list, and the pass log names each such hold once with the arms it keeps;
#     an arm its own blocker holds is counted there, not named. One whose epic
#     waits only on a demand gate is slung, and so is one in flight under a
#     parked epic, which only an open blocker of its own holds. A held arm stays
#     intact and fires once its hold releases. A blocker of its own the store
#     does not return holds it, while an ancestor, or a blocker on an ancestor,
#     the store does not return holds nothing. A backslash in a title prints
#     as stored;
#   * list --json prints the listing alone, with no hold walk;
#   * notify, the dispatch a named agent's work owes: a mail at once when bd
#     reports the bead ready, otherwise a notice recorded for the pass; it
#     refuses a bead not assigned to the agent, owes nothing on a closed or
#     claimed one, and keeps the record when no turn is requested or its
#     readiness read fails. A notice is done only once the agent's turn is
#     requested: a mail that fails, or is saved with no turn requested, is
#     followed by gc session nudge, and a notice whose nudge fails too stays
#     owed, and the next pass recovers it while its first mail still holds the
#     dedup key. The pass sends a notice once bd reports its bead ready,
#     retires one on a closed, claimed or reassigned bead, fails on a turn it
#     cannot request or a notice listing it cannot read while its slings still
#     run, leaves one past its budget, and list shows them; every retire, in a
#     pass or in notify, leaves a record that names another agent since its
#     listing, or a notice owed again; disarm clears one, while a pass that
#     retires an arm on the same bead leaves it; a title or a notice value that
#     spells a second row forges none;
#   * the closed-bead retire arm;
#   * the UNTIL resolved-by consumer — an `until` dep ("X resolves me") disposes
#     the gated bead through bead-rehome once its targets all close, while ONLY
#     `until` disposes (a `blocks` edge to a closed target never does — the scope
#     guard), a non-open or assigned bead is left alone, a bead its own open
#     `blocks` blocker holds is never handed to bead-rehome, a bead whose `until`
#     edge was removed after the listing is kept, a bead given an edge after the
#     listing to a bead this store has no row for, which `bd show` leaves out,
#     is left undecided, a held close (bead-rehome
#     refuses) and a hard failure are told apart, dry-run disposes nothing, the
#     whole candidate set resolves in a bounded read count with no per-bead call
#     and no jq process per candidate, a disposal starts only while the pass
#     budget has room for one, a pinned pass names its store to bead-rehome, and
#     the until half runs when the dispatch half cannot read its armed set; a
#     mol-design-convoy subject whose run's own blocks wrote its `until` edge
#     and handed it off is disposed toward its owned convoy once that convoy
#     closes, while one its run never handed off is left as live work;
#   * the CLAIM a disposal is made under — the pass claims a bead in one write
#     conditional on its status and assignee, before the read it decides the
#     disposal on, and runs bead-rehome as the claim. A dispatch or a worker's
#     claim that lands before the claim keeps the bead. A dispatch that lands
#     while the pass holds the bead, through this suite's disposer and through
#     the real bead-rehome.sh, reopens it and withdraws its pointer, and so does
#     an `until` edge removed then. The pass marks the bead before bead-rehome
#     stamps its pointer, and a held or failed close, through the real
#     bead-rehome.sh too, gives the bead back without that pointer. A claim, or
#     an unchecked close, a pass left is finished by the next pass, before any
#     other half runs: a pass stopped after the stamp leaves a pointer its mark
#     names, which the next pass withdraws, while a pointer no mark names, or
#     one another closer records before the claim, stays and reads as live
#     work. Another closer whose gates passed before the claim, run through
#     the real bead-rehome.sh, stamps nothing while the pass holds the bead,
#     whether it is released after the pass's stamp or before it, so the pass
#     neither withdraws nor overwrites a pointer it did not stamp; and a stamp
#     the claim no longer covers writes nothing, leaving the bead to whoever
#     took it. An arm that lands while the pass holds the bead outlives a close no
#     pass could check, and fires once the check reopens the bead. A give-back
#     or a check that fails is left for the pass after, and so is one the budget
#     leaves, which the pass declares as it does a disposal;
#   * the CONVOY-LEAK guards — gc sling mints an input convoy per call, so an arm
#     that never finalizes must not be re-slung forever: an arm whose work
#     another path already delivered (a merge_result stamp) RETIRES without
#     slinging, and a sling that keeps failing is COUNTED, CAPPED, and escalated
#     once (keeping the arm, never a silent retire) instead of leaking one convoy
#     per pass; a proven dispatch clears the count so the budget resets;
#   * the FALSE-EMPTY-QUEUE guard — an unreadable listing exits non-zero
#     instead of printing a summary byte-identical to a healthy empty queue.
#     That fail-open is the exact class this script must not have: it is a
#     dispatcher, and a silent "nothing was owed" is how the hold went missing
#     in the first place;
#   * the QUIET PATH — an empty store still passes, so the guard above did not
#     strand the ordinary no-work case;
#   * the ARG_MAX guard — a large armed set still enumerates and dispatches. A
#     snapshot handed to jq as one argv value dies past the kernel per-argument
#     cap, which silently strands the whole backlog; the fixture is sized to
#     prove the old argv pass fails before asserting the SUT survives it;
#   * the PASS LOCK — a pass that overlaps one in flight exits 0 having read and
#     slung nothing, so two overlapping passes make one sling; a holder past the
#     stall bound fails the pass, and a lock that cannot be taken refuses it;
#     no gc, escalate.sh or bead-rehome.sh call is handed its descriptor, so no
#     process one leaves running carries it past the pass, while a call still
#     running holds it after a pass killed by itself; with no GC_RIG it is keyed
#     by the rig root;
#   * the PASS BUDGET — a pass starts a sling or an escalation only while a full
#     allowance is left, on a clock the test controls, and reports the beads it
#     left armed and untouched; a pass that fails declares nothing; a dry run
#     takes no lock and spends no budget;
#   * a POSITIVE CONTROL over the shipped order file, so a passing suite cannot
#     mean the cadence that consumes these records was quietly un-shipped, and
#     its timeout is bounded by the budget below it and the stall bound above;
#   * SCRATCH CLEANUP — every verb that stages a temp file leaves none behind.
#
# No live city, Dolt, network, gc or bd — only jq, stubs, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
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

# --- stubs -------------------------------------------------------------------
# $TMP/beads.json is the store: an array of beads, each carrying an extra
# `_ready` flag standing in for bd's own readiness predicate. The script must
# ASK for readiness rather than compute it, so the stub answers and the test
# asserts the script honored the answer.
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
# --actor names who writes, as BEADS_ACTOR does when it is absent; `close`
# reads it.
pinned=0; actor="${BEADS_ACTOR:-}"
while :; do
    case "${1:-}" in
        --db) pinned=1; shift 2 || shift || true ;;
        --actor) actor="${2:-}"; shift 2 || shift || true ;;
        *) break ;;
    esac
done
# STUB_RACE_AT and STUB_RACE_JQ land a write another actor makes: the first
# call whose arguments contain STUB_RACE_AT applies the jq program STUB_RACE_JQ
# to the store before it is answered. It fires once; STUB_RACE_FIRED records it.
# With STUB_CLOCK set, that call also advances the test's clock STUB_RACE_SECS.
if [ -n "${STUB_RACE_AT:-}" ] && [ ! -e "${STUB_RACE_FIRED:?}" ]; then
    case " $* " in
        *"$STUB_RACE_AT"*)
            : > "$STUB_RACE_FIRED"
            jq -c "${STUB_RACE_JQ:?}" "$STUB_STORE" > "$STUB_STORE.race" && mv "$STUB_STORE.race" "$STUB_STORE"
            if [ -n "${STUB_CLOCK:-}" ] && [ -n "${STUB_RACE_SECS:-}" ]; then
                printf '%s\n' "$(( $(cat "$STUB_CLOCK") + STUB_RACE_SECS ))" > "$STUB_CLOCK"
            fi ;;
    esac
fi
# STUB_FRESH_STORE, when set, is the store as it stands once the until half
# starts a fresh read: a write that lands between the pass-start listing and
# that read. The fresh read opens with `bd show`, the only show a reconcile pass
# makes, so from that call on every read answers from it, while the listing and
# the status read before it answer from $STORE. "$STUB_FRESH_STORE.read" records
# the switch, and the test's fresh_store helper empties it.
now="$STORE"
if [ -n "${STUB_FRESH_STORE:-}" ]; then
    [ "${1:-}" = "show" ] && printf 'read\n' > "$STUB_FRESH_STORE.read"
    [ -s "$STUB_FRESH_STORE.read" ] && now="$STUB_FRESH_STORE"
fi
if [ -n "${STUB_BD_LIST_FAIL:-}" ] && [ "${1:-}" = "list" ]; then
    echo "bd: simulated listing failure" >&2; exit 1
fi
# Every `show` fails once the file STUB_SHOW_FAIL_WHEN names exists.
if [ -n "${STUB_SHOW_FAIL_WHEN:-}" ] && [ -e "$STUB_SHOW_FAIL_WHEN" ] && [ "${1:-}" = "show" ]; then
    echo "bd: simulated show failure" >&2; exit 1
fi
# STUB_BD_ARMED_FAIL fails only the armed listings (--has-metadata-key), so the
# dispatch half cannot read its set while the until half's reads still answer.
if [ -n "${STUB_BD_ARMED_FAIL:-}" ] && [ "${1:-}" = "list" ]; then
    case " $* " in *" --has-metadata-key "*) echo "bd: simulated armed listing failure" >&2; exit 1 ;; esac
fi
case "${1:-}" in
  list)
    shift
    key=""; ready=0; all=0; gates=0; id=""; who="-"; st=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --has-metadata-key) shift; key="${1:-}" ;;
        --id) shift; id="${1:-}" ;;
        --ready) ready=1 ;;
        --all) all=1 ;;
        --include-gates) gates=1 ;;
        --assignee) shift; who="${1:-}" ;;
        --assignee=*) who="${1#--assignee=}" ;;
        --status) shift; st="${1:-}" ;;
        --status=*) st="${1#--status=}" ;;
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
    # STUB_BD_ROW_FAIL names a bead whose own row cannot be read by id, while
    # every other by-id read answers.
    if [ -n "${STUB_BD_ROW_FAIL:-}" ] && [ "$id" = "$STUB_BD_ROW_FAIL" ]; then
      echo "bd: simulated row read failure" >&2; exit 1
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
    src="$now"
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
    # --status names the statuses listed, a comma list, closed included when it
    # is named; --assignee names the one assignee.
    jq -c --arg k "$key" --arg id "$id" --argjson ready "$ready" --argjson all "$all" --argjson gates "$gates" \
          --arg who "$who" --arg st "$st" '
      ($id | if . == "" then [] else split(",") end) as $ids
      | ($st | if . == "" then [] else split(",") end) as $sts
      | [ .[]
        | select($k == "" or (.metadata | has($k)))
        | select(($ids | length) == 0 or (.id as $i | $ids | index($i)))
        | select(if ($sts | length) > 0 then (.status as $s | $sts | index($s)) != null else ($all == 1 or .status != "closed") end)
        | select($who == "-" or (.assignee // "") == $who)
        | select($ready == 0 or (._ready == true))
        | select($gates == 1 or (.issue_type // "") != "gate")
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
    src="$now"
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
    upd_args="$*"
    sets=(); unsets=(); note=""; note_mode=""
    new_st="-"; new_who="-"; if_st="-"; if_who="-"
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
        --status|-s) shift; new_st="${1:-}" ;;
        --status=*) new_st="${1#--status=}" ;;
        --assignee|-a) shift; new_who="${1:-}" ;;
        --assignee=*) new_who="${1#--assignee=}" ;;
        --if-status) shift; if_st="${1:-}" ;;
        --if-status=*) if_st="${1#--if-status=}" ;;
        --if-assignee) shift; if_who="${1:-}" ;;
        --if-assignee=*) if_who="${1#--if-assignee=}" ;;
        *) : ;;
      esac
      shift || true
    done
    # STUB_UPDATE_HOLD_AT holds the first update whose arguments contain it,
    # which creates the file STUB_UPDATE_HOLD and waits for
    # "$STUB_UPDATE_HOLD.release": before its guard is checked, or, with
    # STUB_UPDATE_HOLD_AFTER set, once its write has landed. A test parks one
    # writer there while another acts.
    held=""
    if [ -n "${STUB_UPDATE_HOLD_AT:-}" ] && [ ! -e "${STUB_UPDATE_HOLD:?}" ]; then
      case " $id $upd_args " in *"$STUB_UPDATE_HOLD_AT"*) held=1 ;; esac
    fi
    hold_update() {
      : > "$STUB_UPDATE_HOLD"
      local i=0
      while [ ! -e "$STUB_UPDATE_HOLD.release" ] && [ "$i" -lt 2400 ]; do sleep 0.05; i=$((i + 1)); done
    }
    [ -z "$held" ] || [ -n "${STUB_UPDATE_HOLD_AFTER:-}" ] || hold_update
    # STUB_UPDATE_FAIL_AT fails, writing nothing, every update whose arguments
    # contain it.
    if [ -n "${STUB_UPDATE_FAIL_AT:-}" ]; then
      case " $id $upd_args " in
        *"$STUB_UPDATE_FAIL_AT"*) echo "bd: simulated update failure" >&2; exit 1 ;;
      esac
    fi
    # bd's --if-status and --if-assignee guards: the update lands only while the
    # bead still has that status and that assignee ("" is unassigned), checked in
    # the same write; a stale guard writes nothing and exits 13.
    if [ "$if_st" != "-" ] || [ "$if_who" != "-" ]; then
      cur="$(jq -r --arg id "$id" '(.[] | select(.id == $id) | [(.status // ""), (.assignee // "")] | @tsv) // empty' "$STORE")"
      [ -n "$cur" ] || { echo "bd: no issue found matching $id" >&2; exit 1; }
      if { [ "$if_st" != "-" ] && [ "${cur%%$'\t'*}" != "$if_st" ]; } \
         || { [ "$if_who" != "-" ] && [ "${cur#*$'\t'}" != "$if_who" ]; }; then
        echo "Error: precondition failed for $id: status/assignee changed" >&2; exit 13
      fi
    fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-deferred-dispatch-test.XXXXXX")"
    cp "$STORE" "$tmp"
    # A status that leaves closed takes the close with it, as bd's reopen does.
    if [ "$new_st" != "-" ]; then
      jq -c --arg id "$id" --arg s "$new_st" \
        'map(if .id == $id then ((if .status == "closed" and $s != "closed" then del(.close_reason) else . end) | .status = $s) else . end)' \
        "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    fi
    if [ "$new_who" != "-" ]; then
      jq -c --arg id "$id" --arg a "$new_who" 'map(if .id == $id then .assignee = $a else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    fi
    for kv in ${sets[@]+"${sets[@]}"}; do
      k="${kv%%=*}"; v="${kv#*=}"
      jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
        'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    for k in ${unsets[@]+"${unsets[@]}"}; do
      jq -c --arg id "$id" --arg k "$k" \
        'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    if [ "$note_mode" = "append" ]; then
      jq -c --arg id "$id" --arg n "$note" \
        'map(if .id == $id then .notes = ((.notes // "") + (if (.notes // "") == "" then "" else "\n" end) + $n) else . end)' \
        "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    elif [ "$note_mode" = "replace" ]; then
      jq -c --arg id "$id" --arg n "$note" \
        'map(if .id == $id then .notes = $n else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    fi
    mv "$tmp" "$STORE"
    [ -z "$held" ] || [ -z "${STUB_UPDATE_HOLD_AFTER:-}" ] || hold_update
    echo "updated $id"
    ;;
  close)
    # `bd close <id> --reason R`. bd closes an assigned bead only for its
    # assignee, the actor, and refuses one a `blocks` blocker still holds.
    shift
    id="${1:-}"; shift || true
    reason=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --reason|-r) shift; reason="${1:-}" ;;
        --reason=*) reason="${1#--reason=}" ;;
        *) : ;;
      esac
      shift || true
    done
    who="$(jq -r --arg id "$id" '(.[] | select(.id == $id) | (.assignee // "")) // empty' "$STORE")"
    jq -e --arg id "$id" 'any(.[]; .id == $id)' "$STORE" >/dev/null || { echo "Error: no issue found matching $id" >&2; exit 1; }
    if [ -n "$who" ] && [ "$who" != "$actor" ]; then
      echo "Error: cannot close $id: assignee is \"$who\", actor is \"$actor\"; reclaim or use --force to override" >&2; exit 1
    fi
    if jq -e --arg id "$id" '. as $s | ([.[] | select(.id == $id)] | .[0]) as $b
         | any(($b._deps // [])[]; .dependency_type == "blocks" and (.id as $t | any($s[]; .id == $t and .status != "closed")))' "$STORE" >/dev/null; then
      echo "Error: cannot close $id: blocked by an open issue" >&2; exit 1
    fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-deferred-dispatch-test.XXXXXX")"
    jq -c --arg id "$id" --arg r "$reason" 'map(if .id == $id then (.status = "closed" | .close_reason = $r) else . end)' "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    echo "✓ Closed $id"
    ;;
  dep)
    # `dep list <id> --json` reads a bead's own outgoing edges
    # (own_blocks_unresolved_ids), and `--direction=up` reads the beads that
    # depend on it (the until consumer's fresh read). Real bd answers an ARRAY
    # of {id, dependency_type, status} and an ERROR OBJECT (not an array) for an
    # unresolvable id, so the stub serves both shapes to exercise the SUT's
    # fail-closed array check. `-t <type>` keeps the edges of that type.
    # `dep add <a> <b> --type=<t>` and `dep remove <a> <b>` write a's own edge
    # to b, as the design-convoy formula's blocks do. bd keeps one edge per pair
    # and refuses a second, and reports success for removing an edge that was
    # never there.
    shift
    if [ "${1:-}" = "add" ]; then
      from="${2:-}"; to="${3:-}"; t="${4#--type=}"
      jq -e --arg f "$from" --arg o "$to" 'any(.[]; .id == $f and any((._deps // [])[]; .id == $o))' "$STORE" >/dev/null \
        && { echo "Error: dependency $from -> $to already exists" >&2; exit 1; }
      jq -c --arg f "$from" --arg o "$to" --arg t "$t" 'map(if .id == $f then ._deps = ((._deps // []) + [{id: $o, dependency_type: $t}]) else . end)' "$STORE" > "$STORE.dep" && mv "$STORE.dep" "$STORE"
      exit 0
    fi
    if [ "${1:-}" = "remove" ]; then
      from="${2:-}"; to="${3:-}"
      jq -c --arg f "$from" --arg o "$to" 'map(if .id == $f then ._deps = [ (._deps // [])[] | select(.id != $o) ] else . end)' "$STORE" > "$STORE.dep" && mv "$STORE.dep" "$STORE"
      exit 0
    fi
    [ "${1:-}" = "list" ] || { echo "bd stub: unsupported 'dep ${1:-}'" >&2; exit 2; }
    shift; depid="${1:-}"; shift || true
    direction=down; deptype=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --direction=*) direction="${1#--direction=}" ;;
        --direction) shift; direction="${1:-}" ;;
        -t) shift; deptype="${1:-}" ;;
        *) : ;;
      esac
      shift || true
    done
    if [ "$direction" = "up" ]; then
      # `bd dep list <id> --direction=up --json` answers the beads that depend
      # on <id>, each as {id, dependency_type, issue_type, status}: a convoy's
      # tracks edge, a child's parent-child edge, a blocked bead's blocks edge.
      # STUB_DEP_UP_FAIL names a bead whose dependents cannot be read.
      if [ -n "${STUB_DEP_UP_FAIL:-}" ] && [ "$STUB_DEP_UP_FAIL" = "$depid" ]; then
        echo '{"error":"simulated dependents failure","schema_version":1}'; exit 0
      fi
      jq -c --arg id "$depid" --arg dt "$deptype" '
        [ .[] | . as $b | ($b._deps // [])[] | select(.id == $id)
          | select($dt == "" or .dependency_type == $dt)
          | {id: $b.id, dependency_type: .dependency_type, issue_type: ($b.issue_type // "task"), status: $b.status} ]' "$now"
      exit 0
    fi
    if [ "$(jq -r --arg id "$depid" 'any(.[]; .id == $id)' "$now")" != "true" ]; then
      echo '{"error":"resolving '"$depid"': no issue found","schema_version":1}'
    else
      # _deps models the bead's own edges. Real bd hides an edge whose target
      # has no row in this store (cross-repo/external): it warns on stderr and
      # omits it from the array, so `bd dep list <bead>` returns [] for a bead
      # whose only blocker is cross-store. Model that, so
      # own_blocks_unresolved_ids sees the edge dep list dropped. An in-store
      # gate resolves here, as it does live, though a default listing hides it.
      jq -c --arg id "$depid" --arg dt "$deptype" '
        . as $store
        | [ .[] | select(.id == $id) ] | .[0] as $b
        | [ ($b._deps // [])[] | select(.id as $t | ($store | any(.[]; .id == $t)))
            | select($dt == "" or .dependency_type == $dt) ]' "$now"
    fi
    ;;
  *) echo "bd stub: unsupported '${1:-}'" >&2; exit 2 ;;
esac
STUB

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
# With STUB_FD9_LOG set, each call records whether fd 9, the descriptor the pass
# lock is held on, reached it.
if [ -n "${STUB_FD9_LOG:-}" ]; then
    if { : >&9; } 2>/dev/null; then fd9=open; else fd9=closed; fi
    printf 'gc %s fd9=%s\n' "${1:-}" "$fd9" >> "$STUB_FD9_LOG"
fi
# With STUB_GC_DAEMON set, the first call leaves a process running that keeps
# every descriptor gc was handed, as a store read that brings up a Dolt server
# does. Its pid goes to the named file.
if [ -n "${STUB_GC_DAEMON:-}" ] && [ ! -e "$STUB_GC_DAEMON" ]; then
    ( exec sleep 300 ) </dev/null >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$STUB_GC_DAEMON"
fi
if [ "${1:-}" = "bd" ]; then
    shift
    printf '%s\n' "$*" >> "${STUB_BD_LOG:-/dev/null}"
    VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@"
fi
if [ "${1:-}" = "sling" ]; then
    shift
    printf '%s\n' "$*" >> "${STUB_SLING_LOG:?}"
    # Record the slung marker AS IT STANDS at sling time, so a test can prove the
    # pass stamps the UNPROVEN state before it slings — a crash here must recover
    # as a re-sling, not a retire. After the shift, $1 is the target, $2 the bead.
    if [ -n "${STUB_SLING_MARKER_LOG:-}" ]; then
        jq -r --arg id "${2:-}" '(.[] | select(.id == $id) | .metadata["gc.dispatch_when_ready_slung"]) // "<absent>"' "${STUB_STORE:?}" >> "$STUB_SLING_MARKER_LOG"
    fi
    # A sling's duration on the test's clock (the date stub), so a pass spends its
    # budget at a rate the test sets rather than at the host's load.
    if [ -n "${STUB_CLOCK:-}" ] && [ -n "${STUB_SLING_SECS:-}" ]; then
        printf '%s\n' "$(( $(cat "$STUB_CLOCK") + STUB_SLING_SECS ))" > "$STUB_CLOCK"
    fi
    # The first sling under STUB_SLING_HOLD waits for its release file, so a test
    # can catch a pass mid-sling. Later slings pass straight through: a second pass
    # that got past the lock would sling at once and be counted, not hang the suite.
    if [ -n "${STUB_SLING_HOLD:-}" ] && [ ! -e "$STUB_SLING_HOLD.taken" ]; then
        : > "$STUB_SLING_HOLD.taken"
        : > "$STUB_SLING_HOLD.started"
        i=0
        while [ ! -e "$STUB_SLING_HOLD.release" ] && [ "$i" -lt 6000 ]; do sleep 0.05; i=$((i + 1)); done
    fi
    # STUB_SLING_STAMPS=1 makes a successful sling leave the route a real pool
    # sling leaves on the bead (gc.routed_to=<target>).
    if [ -n "${STUB_SLING_STAMPS:-}" ] && [ "${STUB_SLING_RC:-0}" = 0 ]; then
        tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-deferred-dispatch-test.XXXXXX")"
        jq -c --arg id "${2:-}" --arg t "${1:-}" 'map(if .id == $id then .metadata["gc.routed_to"] = $t else . end)' "${STUB_STORE:?}" > "$tmp" && mv "$tmp" "$STUB_STORE"
    fi
    exit "${STUB_SLING_RC:-0}"
fi
# The rig roster, from STUB_RIGS_JSON (nothing when unset). STUB_RIG_LOG, when
# set, gets one line per read.
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
    printf 'rig list\n' >> "${STUB_RIG_LOG:-/dev/null}"
    [ -z "${STUB_RIGS_JSON:-}" ] || cat "$STUB_RIGS_JSON"
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
# `gc convoy status <id> --json` names the beads the convoy tracks as its
# children, and `gc convoy close <id>` closes the convoy whatever its children
# are: the reads and the write of the design-convoy formula's hand-off.
if [ "${1:-}" = "convoy" ] && [ "${2:-}" = "status" ]; then
    jq -ce --arg c "${3:-}" '. as $s | ([ .[] | select(.id == $c and .issue_type == "convoy") ] | .[0]) as $cv
        | if $cv == null then error("no convoy " + $c) else
            {id: $cv.id, status: $cv.status,
             children: [ ($cv._deps // [])[] | select(.dependency_type == "tracks") | .id as $m
                         | ($s | map(select(.id == $m)) | .[0]) | select(. != null) | {id, status} ]} end' "${STUB_STORE:?}" || exit 1
    exit 0
fi
if [ "${1:-}" = "convoy" ] && [ "${2:-}" = "close" ]; then
    jq -e --arg c "${3:-}" 'any(.[]; .id == $c and .issue_type == "convoy")' "${STUB_STORE:?}" >/dev/null \
        || { echo "gc convoy close: bead ${3:-} is not a convoy" >&2; exit 1; }
    tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-deferred-dispatch-test.XXXXXX")"
    jq -c --arg c "${3:-}" 'map(if .id == $c then .status = "closed" else . end)' "$STUB_STORE" > "$tmp" && mv "$tmp" "$STUB_STORE"
    echo "Closed convoy ${3:-}"
    exit 0
fi
echo "gc stub: unsupported '${1:-}'" >&2; exit 2
STUB
# escalate.sh stub: records each call (subject + key) so the retry-cap test can
# prove reconcile hands a stuck dispatch to a person exactly once, and answers
# like the real tool. Resolved by the SUT through GC_ESCALATE_TOOL.
cat > "$BIN/escalate.sh" <<'ESC'
#!/usr/bin/env bash
set -u
if [ -n "${STUB_FD9_LOG:-}" ]; then
    if { : >&9; } 2>/dev/null; then fd9=open; else fd9=closed; fi
    printf 'escalate fd9=%s\n' "$fd9" >> "$STUB_FD9_LOG"
fi
subject=""; key=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) shift; subject="${1:-}" ;;
    --key) shift; key="${1:-}" ;;
    --message) shift ;;
    *) : ;;
  esac
  shift || true
done
printf '%s\t%s\n' "$subject" "$key" >> "${ESC_CALLS:?}"
echo "escalate: filed visit tk-visit1 on $subject [$key]"
ESC
# bead-rehome.sh stub: the resolved-by consumer's disposer. Records each call
# (origin + successor + kind, then the two stores it was told, "-" for one it
# was left to derive) so a test can prove reconcile disposed the right bead
# toward the right successor with the right kind in the right store, and on
# success CLOSES the origin + stamps gc.superseded_by in the store, exactly as
# the real tool leaves it — so a second pass no longer enumerates the bead.
# STUB_REHOME_RC forces the held (5) / conflict (6) / hard-fail paths, and
# STUB_REHOME_SECS advances the test's clock by that much per call. Resolved by
# the SUT via GC_REHOME_TOOL.
cat > "$BIN/bead-rehome.sh" <<'RH'
#!/usr/bin/env bash
set -u
if [ -n "${STUB_FD9_LOG:-}" ]; then
    if { : >&9; } 2>/dev/null; then fd9=open; else fd9=closed; fi
    printf 'rehome fd9=%s\n' "$fd9" >> "$STUB_FD9_LOG"
fi
origin=""; successor=""; kind=""; ostore="-"; sstore="-"
while [ $# -gt 0 ]; do
  case "$1" in
    --origin) shift; origin="${1:-}" ;;
    --successor) shift; successor="${1:-}" ;;
    --kind) shift; kind="${1:-}" ;;
    --origin-store) shift; ostore="${1:-}" ;;
    --successor-store) shift; sstore="${1:-}" ;;
    --note) shift ;;
    *) : ;;
  esac
  shift || true
done
printf '%s\t%s\t%s\t%s|%s\t%s\n' "$origin" "$successor" "$kind" "$ostore" "$sstore" "${BEADS_ACTOR:-}" >> "${REHOME_CALLS:?}"
if [ -n "${STUB_CLOCK:-}" ] && [ -n "${STUB_REHOME_SECS:-}" ]; then
  printf '%s\n' "$(( $(cat "$STUB_CLOCK") + STUB_REHOME_SECS ))" > "$STUB_CLOCK"
fi
rc="${STUB_REHOME_RC:-0}"
if [ "$rc" = 0 ]; then
  tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-rehome-stub.XXXXXX")"
  jq -c --arg o "$origin" --arg s "$successor" --arg ss "$sstore" \
    'map(if .id == $o then (.status = "closed" | .metadata["gc.superseded_by"] = $s | .metadata["gc.superseded_by_store"] = $ss) else . end)' \
    "${STUB_STORE:?}" > "$tmp" && mv "$tmp" "$STUB_STORE"
fi
exit "$rc"
RH
# A bead-rehome a write races: it applies the jq program STUB_REHOME_RACE_JQ to
# the store, a write another actor lands the moment the pass hands the bead to
# its disposer, then runs the disposer STUB_REHOME_NEXT names (the stub above
# when unset).
# STUB_REHOME_TOUCH names a file it creates once the disposer returns.
cat > "$BIN/rehome-race.sh" <<'RR'
#!/usr/bin/env bash
set -u
jq -c "${STUB_REHOME_RACE_JQ:?}" "${STUB_STORE:?}" > "$STUB_STORE.race" && mv "$STUB_STORE.race" "$STUB_STORE"
"${STUB_REHOME_NEXT:-$(dirname "$0")/bead-rehome.sh}" "$@"
rc=$?
[ -z "${STUB_REHOME_TOUCH:-}" ] || : > "$STUB_REHOME_TOUCH"
exit "$rc"
RR
# date stub: the epoch form the pass budget reads comes from $STUB_CLOCK when a
# test sets it; every other form reaches the real date. The pass reads the clock
# from its own shell, so under STUB_FD9_LOG the stub also records that the pass
# holds fd 9: the positive control for the gc, escalate.sh and bead-rehome.sh
# records above.
export STUB_REAL_DATE; STUB_REAL_DATE="$(command -v date)"
cat > "$BIN/date" <<'DATE'
#!/usr/bin/env bash
if [ -n "${STUB_FD9_LOG:-}" ]; then
    if { : >&9; } 2>/dev/null; then fd9=open; else fd9=closed; fi
    printf 'date fd9=%s\n' "$fd9" >> "$STUB_FD9_LOG"
fi
if [ -n "${STUB_CLOCK:-}" ] && [ "$*" = "-u +%s" ]; then cat "$STUB_CLOCK"; exit 0; fi
exec "${STUB_REAL_DATE:?}" "$@"
DATE
chmod +x "$BIN/bd" "$BIN/gc" "$BIN/escalate.sh" "$BIN/bead-rehome.sh" "$BIN/rehome-race.sh" "$BIN/date"
# A jq that counts its runs, put on PATH only by the case that counts them.
export STUB_REAL_JQ; STUB_REAL_JQ="$(command -v jq)"
mkdir -p "$TMP/jqbin"
cat > "$TMP/jqbin/jq" <<'JQ'
#!/usr/bin/env bash
printf 'jq\n' >> "${STUB_JQ_LOG:?}"
exec "${STUB_REAL_JQ:?}" "$@"
JQ
chmod +x "$TMP/jqbin/jq"

export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/beads.json"
export STUB_SLING_LOG="$TMP/sling.log"
export STUB_MAIL_LOG="$TMP/mail.log"
export STUB_MAILBOX="$TMP/mailbox"
export STUB_NUDGE_LOG="$TMP/nudge.log"
export ESC_CALLS="$TMP/escalate.log"
export REHOME_CALLS="$TMP/rehome.log"
export STUB_RACE_FIRED="$TMP/race.fired"
export GC_ESCALATE_TOOL="$BIN/escalate.sh"
export GC_REHOME_TOOL="$BIN/bead-rehome.sh"
export BEADS_ACTOR="test-actor"
unset GC_AGENT GC_RIG GC_RIG_ROOT 2>/dev/null || true
# The pass lock lives under this run's tmpdir, never the pack state dir a live
# order holds, and the knobs a shell may carry do not settle any assertion. The
# suite runs unpaced: on the real clock a loaded host can spend the default
# budget inside one case, so only the budget cases, on the test's clock, set one.
export DEFERRED_DISPATCH_STATE_DIR="$TMP/state"
export DEFERRED_DISPATCH_PASS_BUDGET_SECS=0
unset GC_PACK_STATE_DIR GC_ORDER_OUTCOME_FILE STUB_RIGS_JSON \
    DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS \
    DEFERRED_DISPATCH_LOCK_STALL_SECS 2>/dev/null || true

store() {
    printf '%s' "$1" > "$STUB_STORE"
    : > "$STUB_SLING_LOG"; : > "$STUB_MAIL_LOG"; : > "$STUB_MAILBOX"; : > "$STUB_NUDGE_LOG"; : > "$ESC_CALLS"; : > "$REHOME_CALLS"
    rm -f "$STUB_RACE_FIRED"
}
# The store as the fresh read finds it, for STUB_FRESH_STORE, with the switch
# to it reset, so a pass reads its listing and status read from the store again.
fresh_store() { printf '%s' "$1" > "$TMP/fresh-store.json"; : > "$TMP/fresh-store.json.read"; }
meta()  { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
notes() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STUB_STORE"; }
slings() { wc -l < "$STUB_SLING_LOG" | tr -d ' '; }
mails() { wc -l < "$STUB_MAIL_LOG" | tr -d ' '; }
mailbox() { wc -l < "$STUB_MAILBOX" | tr -d ' '; }
nudges() { wc -l < "$STUB_NUDGE_LOG" | tr -d ' '; }
# A pass's list reads, split by half. The notices half of every pass reads its
# listing, plus bd's readiness when a notice is owed; a bound on the other
# halves' reads leaves those out.
arm_list_reads() { grep '^list' "$STUB_BD_LOG" | grep -c -v -F -e 'gc.notify_when_ready'; }
notice_list_reads() { grep '^list' "$STUB_BD_LOG" | grep -c -F -e 'gc.notify_when_ready'; }
escalations() { wc -l < "$ESC_CALLS" | tr -d ' '; }
rehomes() { wc -l < "$REHOME_CALLS" | tr -d ' '; }
rehome_call() { sed -n "${1}p" "$REHOME_CALLS" | cut -f1-3; }   # tab-separated: origin<TAB>successor<TAB>kind
rehome_stores() { sed -n "${1}p" "$REHOME_CALLS" | cut -f4; }   # <origin-store>|<successor-store>, "-" for one not passed
status_of() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .status) // "<absent>"' "$STUB_STORE"; }
assignee_of() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .assignee // "") // "<absent>"' "$STUB_STORE"; }
rehome_actor() { sed -n "${1}p" "$REHOME_CALLS" | cut -f5; }   # the BEADS_ACTOR bead-rehome ran as
await() { # <file> — bounded wait for a sentinel to appear
    local i=0
    while [ ! -e "$1" ] && [ "$i" -lt 1200 ]; do sleep 0.05; i=$((i + 1)); done
    [ -e "$1" ]
}

# --- ARM ---------------------------------------------------------------------
echo "# arm"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"mayor: dispatch after b-0 lands","_ready":false}]'
out="$("$SUT" arm b-1 --target rig/pool --reason "needs b-0" 2>&1)"; rc=$?
eq "$rc" 0 "arm exits 0"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "arm records the target"
eq "$(meta b-1 gc.dispatch_when_ready_args)" "[]" "arm records an empty arg list by default"
eq "$(meta b-1 gc.dispatch_when_ready_armed_by)" "test-actor" "arm records who armed it"
has "$(meta b-1 gc.dispatch_when_ready_armed_at)" "T" "arm records when"
eq "$(meta b-1 gc.dispatch_when_ready_reason)" "needs b-0" "arm records the reason"
has "$(notes b-1)" "mayor: dispatch after b-0 lands" "arm APPENDS to notes (prior note survives)"
has "$(notes b-1)" "dispatch armed by test-actor" "arm's own note is present"
has "$out" "armed b-1 -> rig/pool" "arm says what it did"

store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" arm b-1 --target rig/pool 2>&1)"
has "$out" "nothing holds b-1 right now" "arm on an unblocked bead warns it will dispatch immediately"

# The mirror case. It is what makes the hint above load-bearing: a hint that
# fires unconditionally says nothing, and a per-id readiness probe (which real
# bd refuses) would produce no hint in either direction.
store '[{"id":"b-0","status":"open","assignee":"","metadata":{},"notes":"","title":"Land b-0"},
        {"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]}]'
out="$("$SUT" arm b-1 --target rig/pool 2>&1)"
hasnt "$out" "nothing holds b-1" "arm on a BLOCKED bead does not claim it will dispatch immediately"
has "$out" 'b-1 is HELD by b-0 "Land b-0"' "arm names the blocker the arm now waits on"

# A bead with no blocker of its own, under a parked epic: the hint names the
# park, since the next pass holds the arm rather than slinging it.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},
        {"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":"","_deps":[{"id":"park","dependency_type":"blocks"}]},
        {"id":"park","status":"open","issue_type":"gate","title":"Parked until the operator unparks it","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" arm b-1 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm records a dispatch under a parked epic"
hasnt "$out" "nothing holds b-1" "arm does not claim an arm under a parked epic will dispatch"
has "$out" 'b-1 is HELD by park "Parked until the operator unparks it" on ancestor epic' "arm names the park that holds it"

echo "# arm warns on a cross-store blocker it cannot resolve"
# bd resolves dependencies within one store, so a `blocks` edge to a bead in
# another rig (here sl-x, which has no row in this store) holds nothing: bd
# reports the bead ready (_ready) and `bd list --ready` sees no blocker. arm's
# hint would then say nothing holds the bead while the blocker is open, so arm
# must name the unresolvable blocker instead, the one
# place a human can redirect the sequencing. Another store holds sl-x, and this
# run is unpinned, so `gc bd` would answer a read naming sl-x from that store
# and find its row: the check must ask only about b-1's own edges.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true,"_deps":[{"id":"sl-x","dependency_type":"blocks","status":"open"}]}]'
printf '%s' '[{"id":"sl-x","status":"open","assignee":"","metadata":{},"notes":""}]' > "$TMP/foreign.json"
out="$(STUB_FOREIGN_STORE="$TMP/foreign.json" "$SUT" arm b-1 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm still records the dispatch on a cross-store-blocked bead"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the dispatch record is written"
has "$out" "sl-x" "arm names the unresolvable cross-store blocker"
has "$out" "no row in this store" "arm says why that blocker holds nothing here"
hasnt "$out" "nothing holds b-1" "arm does NOT claim the cross-store-blocked bead is unblocked"

# The same arm pinned with --db: no routing, and the same answer.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true,"_deps":[{"id":"sl-x","dependency_type":"blocks","status":"open"}]}]'
out="$(STUB_FOREIGN_STORE="$TMP/foreign.json" "$SUT" arm b-1 --target rig/pool --db "$TMP/rig/.beads" 2>&1)"
has "$out" "has a 'blocks' edge to sl-x" "a pinned arm names the cross-store blocker too"
hasnt "$out" "nothing holds b-1" "and does not claim the bead is unblocked"

echo "# arm does not mistake an in-store gate blocker for a cross-store one"
# A gate is hidden from a listing that does not ask for gates, but it has a row
# in this store and dep list resolves it. Its edge must not read as cross-store,
# and because the gate is closed the bead is announced ready.
store '[{"id":"g-0","status":"closed","issue_type":"gate","assignee":"","metadata":{},"notes":""},
        {"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true,"_deps":[{"id":"g-0","dependency_type":"blocks","status":"closed"}]}]'
out="$("$SUT" arm b-1 --target rig/pool 2>&1)"
hasnt "$out" "no row in this store" "an in-store gate blocker triggers no cross-store warning"
has "$out" "nothing holds b-1 right now" "and the bead its closed gate released is announced ready"

echo "# arm does not mistake an in-store blocker for a cross-store one"
# b-0 has a row in this store, so its edge resolves: no cross-store warning, and
# because the blocker is open the bead is correctly held, not announced ready.
store '[{"id":"b-0","status":"open","assignee":"","metadata":{},"notes":"","_ready":true},
        {"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks","status":"open"}]}]'
out="$("$SUT" arm b-1 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm exits 0 with an in-store blocker"
hasnt "$out" "no row in this store" "an in-store blocker triggers no cross-store warning"
hasnt "$out" "nothing holds b-1" "and the in-store-blocked bead is not announced ready"

echo "# arm does not announce 'no blocker' when the cross-store enumeration itself fails"
# own_blocks_unresolved_ids fails closed (non-zero) when its own `bd list --id`
# read fails, while dep list still reads the bead cleared (no in-store blocker,
# _ready true). cmd_arm must not collapse that enumeration failure into "no
# cross-store blocker": the check is unproven, so the immediate-dispatch hint
# must not stand on it. A read that folded the failure into "none found" would
# print the all-clear here, which the two trailing assertions catch.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_BD_LIST_FAIL=1 "$SUT" arm b-1 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm still records the dispatch when the cross-store probe read fails"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the dispatch record is written"
hasnt "$out" "nothing holds b-1" "arm does NOT announce an unblocked bead when the cross-store check could not be proven"
has "$out" "could not enumerate" "arm warns the cross-store check could not be proven"

echo "# arm does not announce 'no blocker' when its listing carries no row for the bead"
# The listing read succeeds but answers no row for g-1: bd hides a gate bead
# from a listing that does not ask for gates. An empty answer proves nothing
# about g-1's edges, so it must read as unproven, not as "no cross-store
# blocker", even though dep list reads the bead cleared.
store '[{"id":"g-1","status":"open","issue_type":"gate","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" arm g-1 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm still records the dispatch when its listing has no row for the bead"
hasnt "$out" "nothing holds g-1" "arm does NOT announce an unblocked bead whose edges it never read"
has "$out" "could not enumerate" "arm warns the cross-store check could not be proven"

echo "# arm accepts the doctor-flagged shape"
# gc.execution_routed_to is provenance, not a live queue, so a blocked bead
# carrying only it is the exact shape doctor/check-blocked-work-armed flags and
# names arming as the fix for. arm must accept it, or that remedy is a dead end.
store '[{"id":"b-2","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/pool"},"notes":"","_ready":false}]'
out="$("$SUT" arm b-2 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 0 "arm accepts a blocked bead carrying only gc.execution_routed_to"
eq "$(meta b-2 gc.dispatch_when_ready)" "rig/pool" "arming the exec-routed-only bead records the dispatch"
has "$out" "armed b-2 -> rig/pool" "arm says what it did"

echo "# arm refusals"
# A real active route (gc.routed_to, what a pool queue consumes) still blocks
# arming: a second dispatch would queue behind the live one.
store '[{"id":"b-2r","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/pool"},"notes":"","_ready":true}]'
out="$("$SUT" arm b-2r --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead already routed (gc.routed_to)"
eq "$(meta b-2r gc.dispatch_when_ready)" "<absent>" "refused arm writes nothing"
has "$out" "already dispatched" "refusal names the reason"

# A gc.dispatch_when_ready_slung marker in either state means reconcile is
# mid-dispatch on this bead; re-arming over it would stack a second dispatch.
store '[{"id":"b-2s","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready_slung":"slinging@2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" arm b-2s --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead reconcile is mid-dispatch on (gc.dispatch_when_ready_slung)"
eq "$(meta b-2s gc.dispatch_when_ready)" "<absent>" "refused arm writes nothing"
has "$out" "already dispatched" "refusal names the reason"

store '[{"id":"b-3","status":"closed","assignee":"","metadata":{},"notes":"","_ready":false}]'
out="$("$SUT" arm b-3 --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a closed bead"

# `bd list --ready` answers OPEN beads only — it excludes on status before it
# looks at deps at all. So a hold recorded on any other live status can never
# fire, and nothing re-derives status from the dep graph: the arm would sit in
# the queue reading as held by a blocker for as long as the status stands.
for HELD in blocked deferred hooked pinned; do
  store '[{"id":"b-h","status":"'"$HELD"'","assignee":"","metadata":{},"notes":"","_ready":false}]'
  out="$("$SUT" arm b-h --target rig/pool 2>&1)"; rc=$?
  eq "$rc" 1 "arm refuses a $HELD bead"
  eq "$(meta b-h gc.dispatch_when_ready)" "<absent>" "a refused $HELD arm writes nothing"
  has "$out" "answers open beads only" "the $HELD refusal names the ready predicate"
done

store '[{"id":"b-4","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" arm b-4 2>&1)"; rc=$?
eq "$rc" 2 "arm without --target is a usage error"
eq "$(meta b-4 gc.dispatch_when_ready)" "<absent>" "arm without --target writes nothing"

out="$("$SUT" arm b-nope --target rig/pool 2>&1)"; rc=$?
eq "$rc" 1 "arm refuses a bead that does not resolve (bd's object-shaped miss)"

# --- RECONCILE: the dispatch arm ---------------------------------------------
echo "# reconcile dispatches"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "reconcile exits 0 on a clean pass"
eq "$(slings)" "1" "reconcile slung exactly once"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1" "sling got the recorded target and bead"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the record is cleared after a successful dispatch"
has "$(notes b-1)" "dispatched to rig/pool" "the dispatch is recorded in notes"
has "$out" "1 dispatched" "summary counts the dispatch"

echo "# reconcile passes sling args through in order"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[\"--on\",\"mol-pr-from-issue\",\"--merge\",\"mr\"]"},"notes":"","_ready":true}]'
"$SUT" reconcile >/dev/null 2>&1
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1 --on mol-pr-from-issue --merge mr" "recorded sling args reach gc sling in order"

echo "# arm --sling-arg round-trips into the dispatch"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
"$SUT" arm b-1 --target rig/pool --sling-arg --on --sling-arg mol-pr-from-issue >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_args)" '["--on","mol-pr-from-issue"]' "arm encodes --sling-arg as a JSON array"
: > "$STUB_SLING_LOG"
"$SUT" reconcile >/dev/null 2>&1
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1 --on mol-pr-from-issue" "armed args survive the round trip"

# --- RECONCILE: every arm that must NOT sling --------------------------------
echo "# reconcile withholds"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a blocked armed bead is not an error"
eq "$(slings)" "0" "a blocked armed bead is NOT slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "a blocked armed bead keeps its record"
hasnt "$out" "HELD by b-0" "an arm its own blocker holds gets no line of its own in the pass log"
has "$out" "1 held" "summary counts it as held"

store '[{"id":"b-1","status":"open","assignee":"someone/else","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a ready bead someone holds is NOT slung out from under them"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the assigned bead keeps its record"
has "$out" "ASSIGNED b-1" "the assignee is reported, not silent"
has "$out" "1 assigned" "summary counts it as assigned, apart from a hold"

# The two-state gc.dispatch_when_ready_slung marker. reconcile stamps it around
# its own sling: "slinging@<ts>" before (attempt in flight, unproven) and
# "slung@<ts>" once the sling returns success (proven). Recovery reads THIS one
# marker, not whatever stamp a given lane happened to leave (a plain pool sling
# shows as gc.routed_to, an --on pour as gc.execution_routed_to).

# Proven ("slung@"): the sling ran and the pass died before disarming — RETIRE,
# do not replay.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_slung":"slung@2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a proven (slung@) marker is NOT slung a second time"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the proven arm is retired instead"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "retiring clears the slung marker too"
has "$out" "already-dispatched" "the retire names the reason"

# Unproven ("slinging@"): a pass stamped the attempt and died before or during
# the sling, or a failed sling could not roll the marker back. The dispatch is
# NOT proven, so it must be RE-SLUNG, not retired — retiring here is the silent
# lost dispatch the two states exist to prevent, and one the blocked-work doctor
# check cannot catch because the blocker has lifted and the bead reads ready.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_slung":"slinging@2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "recovering an unconfirmed sling is a clean pass"
eq "$(slings)" "1" "an unproven (slinging@) marker is RE-SLUNG, not retired"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1" "the re-attempt reaches sling with the recorded target"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the record is cleared after the recovered dispatch"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "a completed dispatch leaves no slung marker behind"
has "$out" "1 dispatched" "summary counts the recovered dispatch"

# A bare-timestamp marker (no state prefix) is read as proven, so an arm already
# mid-dispatch when the two states arrived retires rather than re-slinging.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_slung":"2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a bare-timestamp (unprefixed) marker is read as proven and NOT re-slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the unprefixed marker retires the arm"
has "$out" "already-dispatched" "the retire names the reason"

# The pre-sling stamp is the UNPROVEN state: reconcile must write "slinging@"
# BEFORE it slings, or a crash mid-sling would recover as a retire and lose the
# dispatch. The sling stub records the marker as it stands at sling time.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
: > "$TMP/marker-at-sling.log"
STUB_SLING_MARKER_LOG="$TMP/marker-at-sling.log" "$SUT" reconcile >/dev/null 2>&1
has "$(cat "$TMP/marker-at-sling.log")" "slinging@" "reconcile stamps the unproven slinging@ marker BEFORE it slings"

# The marker is lane-agnostic: an --on arm proven slung retires on the same
# marker, with no argv inspection and no execution-route read, so it is not
# replayed into the graph.v2 live-workflow refusal.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/pool","gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]","gc.dispatch_when_ready_slung":"slung@2026-01-01T00:00:00Z"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an --on arm proven slung is NOT re-slung, exec route notwithstanding"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the proven --on arm is retired"
has "$out" "already-dispatched" "the retire names the reason"

# gc.execution_routed_to alone is NOT a dispatch reconcile reads: a bead armed
# while carrying only it (its workflow gone) is the doctor-flagged shape, and the
# arm remedy only works if reconcile SLINGS it when ready. No slung marker, so it
# dispatches — the exec-route provenance is ignored, not mistaken for a dispatch.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/old","gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "1" "an armed bead carrying only gc.execution_routed_to is slung, not retired"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1" "the exec-routed-only bead reaches sling with its recorded target"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the record is cleared after the dispatch"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "a completed dispatch leaves no slung marker behind"
has "$out" "1 dispatched" "summary counts the dispatch, not a retire"

# A fresh --on arm (no slung marker, pour not yet run) slings like any arm, and
# its recorded args reach gc sling in order.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "1" "a fresh --on arm with no slung marker is slung, not retired"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1 --on mol-polecat-work" "the not-yet-poured --on arm reaches sling with its recorded args"
has "$out" "1 dispatched" "summary counts the dispatch"

store '[{"id":"b-1","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a closed armed bead is NOT slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "a closed armed bead's record is retired"
has "$out" "1 retired" "summary counts the retire"

# --- RECONCILE: a hold on the bead or an ancestor ----------------------------
# bd's is_blocked flag cascades DOWN parent-child edges, so an armed child of a
# blocked epic never enters `bd list --ready`. reconcile asks hold-lib.sh whether
# anything holds such a bead: an open `blocks` blocker on it or on any ancestor
# does, except a demand gate on an ancestor, since waiting on the operator's
# decision is not a hold. A held arm is left intact and named with its blocker.
A1='"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"'

# The demand-gate exception: an epic whose only open blocker is the operator's
# pending decision holds nothing, so its armed child whose own blocker has closed
# is slung though bd --ready excludes it.
echo "# reconcile dispatches an arm whose epic waits only on a demand gate"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"},{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":"","_deps":[{"id":"dg","dependency_type":"blocks"}]},
 {"id":"dg","status":"open","issue_type":"gate","title":"Decide whether the epic goes on","assignee":"","metadata":{"gc.demand_for":"epic"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "dispatching an arm under a demand-gated epic is a clean pass"
eq "$(slings)" "1" "an arm whose epic waits only on a demand gate is slung though bd --ready excludes it"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-1" "the arm reaches sling with its recorded target"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the record is cleared after the dispatch"
has "$out" "nothing holds b-1" "reconcile names why it dispatched a not-ready bead"
has "$out" "1 dispatched" "summary counts the dispatch, not a hold"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"},{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":"","_deps":[{"id":"dg","dependency_type":"blocks"}]},
 {"id":"dg","status":"open","issue_type":"gate","title":"Decide whether the epic goes on","assignee":"","metadata":{"gc.demand_for":"epic"},"notes":""}]'
out="$("$SUT" list 2>&1)"
has "$out" "b-1 -> rig/pool [DISPATCHABLE NOW (nothing holds it" "list flags the demand-gated epic's arm as dispatchable, not held"

# A park is an open blocker on the epic, and it holds the epic's armed work: the
# child is not slung, the pass log and list name the park and its title, and the
# arm stays intact.
PARKED='{"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":"","_deps":[{"id":"park","dependency_type":"blocks"}]},
 {"id":"park","status":"open","issue_type":"gate","title":"Parked until the operator unparks it","assignee":"","metadata":{},"notes":""}'
echo "# reconcile holds an armed child of a parked epic"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"},{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"closed","assignee":"","metadata":{},"notes":""},'"$PARKED"']'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "holding a parked arm is a clean pass"
eq "$(slings)" "0" "an armed child of a parked epic is NOT slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the held arm keeps its record, so unparking needs no re-arm"
has "$out" 'HELD by park "Parked until the operator unparks it" on ancestor epic: b-1' "the pass log names the park, its title, the epic it sits on and the arm it keeps"
has "$out" "1 held" "summary counts it as held"
out="$("$SUT" list 2>&1)"
has "$out" 'b-1 -> rig/pool [HELD by park "Parked until the operator unparks it" on ancestor epic]' "list names the park that holds the arm"

# Unparking closes the gate. The same arm, untouched since, dispatches on the
# next pass.
echo "# the held arm dispatches once the park is released"
jq -c 'map(if .id == "park" then .status = "closed" else . end)' "$STUB_STORE" > "$TMP/unparked.json" && mv "$TMP/unparked.json" "$STUB_STORE"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "1" "the arm fires on the first pass after its park closes"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "and its record is cleared"

# Two levels down: the feature between the task and the parked epic has no
# blocker of its own, so the walk has to reach the epic.
echo "# reconcile holds an arm two levels under a parked epic"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"feat","dependency_type":"parent-child"}]},
 {"id":"feat","status":"open","issue_type":"feature","assignee":"","metadata":{},"notes":"","_deps":[{"id":"epic","dependency_type":"parent-child"}]},'"$PARKED"']'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an arm two levels under a parked epic is NOT slung"
has "$out" 'HELD by park "Parked until the operator unparks it" on ancestor epic: b-1' "the pass log names the park that holds it"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the arm keeps its record"

# A park and a prerequisite hold alike: an epic that waits on a task holds its
# armed work until the task closes.
echo "# reconcile holds an arm whose epic waits on a task"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},
 {"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":"","_deps":[{"id":"t-1","dependency_type":"blocks"}]},
 {"id":"t-1","status":"open","issue_type":"task","title":"Land the prerequisite","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an arm whose epic waits on an open task is NOT slung"
has "$out" 'HELD by t-1 "Land the prerequisite" on ancestor epic: b-1' "the pass log names the task the epic waits on"

# A title is free text, so a backslash in one reaches list and the pass log as
# it was stored, never escaped.
echo "# a backslash in a blocker's title prints as stored"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","title":"fix C:\\path","assignee":"","metadata":{},"notes":""},
 {"id":"b-2","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},
 {"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":"","_deps":[{"id":"park","dependency_type":"blocks"}]},
 {"id":"park","status":"open","issue_type":"gate","title":"Parked: see C:\\notes","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" list 2>&1)"
has "$out" 'b-1 -> rig/pool [HELD by b-0 "fix C:\path"]' "list prints a backslash in a blocker's title once"
has "$out" 'b-2 -> rig/pool [HELD by park "Parked: see C:\notes" on ancestor epic]' "and in the title of a blocker on an ancestor"
hasnt "$out" 'C:\\' "list doubles no backslash"
out="$("$SUT" reconcile 2>&1)"
has "$out" 'HELD by park "Parked: see C:\notes" on ancestor epic: b-2' "the pass log prints the backslash once"
hasnt "$out" 'C:\\' "the pass log doubles no backslash"

# The exception covers an ancestor only: a demand gate on the bead itself is the
# decision about that bead, and it holds.
echo "# reconcile holds an arm that waits on a demand gate of its own"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"dg","dependency_type":"blocks"}]},
 {"id":"dg","status":"open","issue_type":"gate","title":"Decide b-1","assignee":"","metadata":{"gc.demand_for":"b-1"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an arm behind a demand gate of its own is NOT slung"
has "$out" "1 held" "the summary counts it as held"
out="$("$SUT" list 2>&1)"
has "$out" 'b-1 -> rig/pool [HELD by dg "Decide b-1"]' "list names the demand gate that holds it"

# A hold holds work that has not started. A bead in flight carries a branch, a
# merge_result or a rejection_reason, and only a blocker of its own holds it, so
# a re-dispatch of work already begun, such as a rejected handoff's rebuild,
# fires under a parked epic. The walk reads none of its ancestors.
FLIGHT='"branch":"polecat/b-1","rejection_reason":"a test failed"'
echo "# reconcile dispatches an arm in flight under a parked epic"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"','"$FLIGHT"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"},{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"closed","assignee":"","metadata":{},"notes":""},'"$PARKED"']'
out="$("$SUT" list 2>&1)"
has "$out" "b-1 -> rig/pool [DISPATCHABLE NOW (in flight, rejection_reason set: a hold on an ancestor leaves it running" "list shows an arm in flight under a parked epic as dispatchable, and why"
export STUB_BD_LOG="$TMP/bd-flight.log"; : > "$STUB_BD_LOG"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "dispatching an arm in flight under a parked epic is a clean pass"
eq "$(slings)" "1" "an arm in flight is slung though its epic is parked"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "its record is cleared after the dispatch"
has "$out" "nothing holds b-1: it is in flight (rejection_reason set), so a hold on an ancestor leaves it running" "the pass log says why it slung a bead under a parked epic"
hasnt "$out" "HELD by" "the park is not named as holding it"
eq "$(arm_list_reads)" "5" "the walk reads no ancestor of a bead in flight (all + ready + its own blocker, plus the until consumer's one candidate scan and its one listing of unchecked closes)"
unset STUB_BD_LOG

echo "# reconcile holds an arm in flight whose own blocker is open"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"','"$FLIGHT"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"},{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","title":"Land b-0","assignee":"","metadata":{},"notes":""},'"$PARKED"']'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an arm in flight with an open blocker of its own is NOT slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "it keeps its record"
has "$out" "1 held" "it is counted held"
out="$("$SUT" list 2>&1)"
has "$out" 'b-1 -> rig/pool [HELD by b-0 "Land b-0"]' "list names its own blocker, not the park"

echo "# a bead not yet started under a parent in flight stays held by the park above"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"feat","dependency_type":"parent-child"}]},
 {"id":"feat","status":"open","issue_type":"feature","assignee":"","metadata":{"branch":"polecat/feat"},"notes":"","_deps":[{"id":"epic","dependency_type":"parent-child"}]},'"$PARKED"']'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an arm under a parent in flight is NOT slung while the epic above is parked"
has "$out" 'HELD by park "Parked until the operator unparks it" on ancestor epic: b-1' "the pass log names the park"

# An OPEN own blocker still withholds, whatever its ancestors do: the arm waits
# on exactly that blocker.
echo "# reconcile still withholds an arm whose OWN blocker is open"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"},{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""},
 {"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an arm with an open OWN blocker is NOT slung under an epic nothing holds"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the still-blocked arm keeps its record"
hasnt "$out" "HELD by" "an arm its own blocker holds gets no pass-log line, however its ancestors stand"
has "$out" "1 held" "summary counts it as held"

# Fail closed: a blocker of the bead's own that the store does not return holds
# the arm, never slung on a guess. bd list --id silently drops an id with no
# row, so an unread blocker must not read as a released one.
echo "# an unresolvable own blocker fails closed (arm stays held)"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"b-0-missing","dependency_type":"blocks"}]}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "an unresolvable own blocker leaves the arm un-slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the arm keeps its record when its own blocker cannot be resolved"
has "$out" "1 held" "an unresolved blocker counts as held, not dispatched"
out="$("$SUT" list 2>&1)"
has "$out" "b-1 -> rig/pool [HELD by b-0-missing (unreadable)]" "list says the blocker could not be read"

# An ancestor the store does not return, a parent in another store or one
# deleted, holds nothing, as bd's cascade passes no hold through a row the store
# does not hold. Here a second parent waits on a demand gate, the wait that
# keeps the arm out of bd --ready while nothing holds it.
DEMAND_EPIC='{"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":"","_deps":[{"id":"dg","dependency_type":"blocks"}]},
 {"id":"dg","status":"open","issue_type":"gate","title":"Decide whether the epic goes on","assignee":"","metadata":{"gc.demand_for":"epic"},"notes":""}'
echo "# an ancestor the store does not return holds nothing"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic-missing","dependency_type":"parent-child"},{"id":"epic","dependency_type":"parent-child"}]},'"$DEMAND_EPIC"']'
out="$("$SUT" list 2>&1)"
has "$out" "b-1 -> rig/pool [DISPATCHABLE NOW (nothing holds it" "list shows an arm whose parent has no row as dispatchable"
hasnt "$out" "unreadable" "and names no unreadable ancestor"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "dispatching an arm whose parent has no row is a clean pass"
eq "$(slings)" "1" "an arm whose parent has no row is slung"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "its record is cleared after the dispatch"
hasnt "$out" "HELD by" "the pass log names no hold for it"

echo "# a blocker the store does not return on an ancestor holds nothing"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},
 {"id":"epic","status":"open","issue_type":"epic","assignee":"","metadata":{},"notes":"","_deps":[{"id":"dg","dependency_type":"blocks"},{"id":"gate-missing","dependency_type":"blocks"}]},
 {"id":"dg","status":"open","issue_type":"gate","title":"Decide whether the epic goes on","assignee":"","metadata":{"gc.demand_for":"epic"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "1" "an arm whose epic's only other blocker has no row is slung"
hasnt "$out" "HELD by" "the blocker with no row is named as no hold"
echo "# a hold walk that cannot read fails the pass"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},'"$PARKED"']'
out="$(STUB_BD_LIST_ID_FAIL=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a hold walk whose read fails exits non-zero"
has "$out" "could not enumerate" "and says it could not see the queue"
eq "$(slings)" "0" "and slings nothing"

# --- the N+1 fix: a full pass costs a bounded number of bd reads --------------
# A pass that read per bead scaled with the armed set and overran the reconcile
# order's timeout, so it was killed before it dispatched and an owed arm silently
# starved. A pass must resolve every candidate's holds and read every candidate's
# fields WITHOUT a per-bead call: blocker and parent ids come off the snapshot's
# own edges, one listing per generation of ancestors and one for the blockers
# resolve them, and each bead's fields come from the cached snapshot. This proves
# the whole set is decided in reads that do not scale with the number of arms.
echo "# reconcile resolves the whole candidate set without a per-bead read"
export STUB_BD_LOG="$TMP/bd-bulk.log"
store '[
 {"id":"a-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"blk-1","dependency_type":"blocks"}]},
 {"id":"a-2","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"blk-2","dependency_type":"blocks"}]},
 {"id":"a-3","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"blk-3","dependency_type":"blocks"}]},
 {"id":"a-4","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"blk-4","dependency_type":"blocks"}]},
 {"id":"blk-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"blk-2","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"blk-3","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"blk-4","status":"closed","assignee":"","metadata":{},"notes":""}]'
: > "$STUB_BD_LOG"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a bulk pass over four arms held out of --ready is a clean pass"
eq "$(slings)" "4" "all four arms nothing holds dispatch in one pass"
eq "$(grep -c '^dep list' "$STUB_BD_LOG")" "0" "reconcile makes NO per-bead dep-list call — the N+1 is gone"
eq "$(grep -c '^show' "$STUB_BD_LOG")" "0" "reconcile makes NO per-bead show call — fields come from the cached snapshot"
# Five bounded reads, none per-bead: armed all + armed ready + one armed
# blocker-status batch (these four arms are all cascade-held), plus the until
# consumer's one whole-store candidate scan (no until candidates here, so it
# adds no blocker batch of its own) and its one listing of the closes an
# earlier pass left unchecked.
eq "$(arm_list_reads)" "5" "the whole set costs a bounded read count, not one per bead"
eq "$(notice_list_reads)" "1" "and a pass that owes no notice reads the notice listing once"

# The same bound with ancestors: four arms under one parked epic cost one more
# read, for the epic, however many arms sit under it.
store '[
 {"id":"a-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},
 {"id":"a-2","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},
 {"id":"a-3","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},
 {"id":"a-4","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},'"$PARKED"']'
: > "$STUB_BD_LOG"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "none of four arms under a parked epic is slung"
has "$out" "4 held" "all four are counted held"
has "$out" 'HELD by park "Parked until the operator unparks it" on ancestor epic: a-1 a-2 a-3 a-4' "the pass log names the park once, with every arm it keeps"
eq "$(printf '%s\n' "$out" | grep -c 'HELD by')" "1" "one line for one park, however many arms it keeps"
eq "$(grep -c '^dep list\|^show' "$STUB_BD_LOG")" "0" "the walk makes no per-bead call"
eq "$(arm_list_reads)" "6" "four arms under one epic cost six list reads (all + ready + the epic + its blocker, plus the until consumer's one candidate scan and its one listing of unchecked closes), not one per arm"
unset STUB_BD_LOG

# --- the ARG_MAX fix: a large armed set enumerates, never dies on argv --------
# armed_rows used to hand the whole --ready snapshot to jq as a single --argjson
# value. That snapshot carries one row per armed bead, and a single argv
# argument past the kernel's size cap aborts jq with "argument list too long" —
# so once the armed backlog held a few dozen full-body rows EVERY enumeration
# failed and nothing dispatched. The snapshots now reach jq over stdin, which
# has no such cap. The fixture is sized so the old argv pass provably dies (the
# positive control below), then the SUT must still enumerate and dispatch the
# whole set. The stub ignores --brief, so it feeds the SUT full-body rows — the
# payload the stdin path has to survive.
#
# Linux refuses any one argument past 128 KiB. macOS has no per-argument cap and
# refuses only argv and the environment together past ARG_MAX, 1 MiB. Forty rows
# of 32 KiB put the snapshot past both.
echo "# a large armed set enumerates and dispatches (no argv size cap)"
big_store="$(jq -nc '[ range(0;40)
  | {id:("big-\(.)"), status:"open", assignee:"",
     metadata:{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},
     notes:("x" * 32768), _ready:true} ]')"
store "$big_store"
ready_payload="$(gc bd list --has-metadata-key gc.dispatch_when_ready --ready --json --limit 0)"
if jq -n --argjson r "$ready_payload" '1' >/dev/null 2>&1; then
  bad "scale fixture too small: the --ready snapshot fits in one argv value, so it cannot exercise the cap"
else
  ok "scale fixture exceeds the kernel's argv size cap (the pre-fix --argjson pass dies here)"
fi
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list enumerates a large armed set without an argv failure"
hasnt "$out" "could not enumerate" "a large armed set does not read as 'could not enumerate'"
eq "$(printf '%s\n' "$out" | grep -c ' -> rig/pool ')" "40" "list reports every bead in the large armed set"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "reconcile completes a pass over a large armed set"
eq "$(slings)" "40" "reconcile dispatches every ready arm in the large set"

echo "# reconcile keeps the record when the sling fails"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$(STUB_SLING_RC=7 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a failed sling makes the pass exit non-zero"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "a failed sling LEAVES the record armed for the next pass"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "a failed sling rolls the slung marker back so the arm retries, not retires"
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "1" "a failed sling records one attempt against the retry cap"
has "$out" "sling of b-1 -> rig/pool failed" "the failure names the bead and target"

# --- the convoy-leak fix: already-delivered retire, and a capped retry ---------
# Each gc sling mints an input convoy, so an arm that never finalizes must not be
# re-slung forever. Two guards stop it: an arm whose work another path already
# delivered (a merge_result stamp) retires without slinging, and a sling that
# keeps failing is capped and escalated rather than leaking a convoy per pass.

echo "# reconcile retires an arm whose work another path already delivered"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","merge_result":"pull_request"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "retiring an already-delivered arm is a clean pass"
eq "$(slings)" "0" "an already-delivered bead is NOT slung — no redundant convoy"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the already-delivered arm is retired, not left to re-sling every pass"
has "$(notes b-1)" "work already delivered (merge_result=pull_request)" "the retire names the delivery it deferred to"
has "$out" "already-delivered b-1" "the retire is reported, not silent"
has "$out" "1 retired" "summary counts the delivered retire"

echo "# repeated non-finalizing slings are capped and escalated, not leaked one convoy per pass"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
STUB_SLING_RC=7 "$SUT" reconcile >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "1" "failing pass 1 counts one attempt"
STUB_SLING_RC=7 "$SUT" reconcile >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "2" "failing pass 2 counts a second attempt"
STUB_SLING_RC=7 "$SUT" reconcile >/dev/null 2>&1
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "3" "failing pass 3 reaches the cap"
eq "$(escalations)" "0" "no escalation while still under the cap"
before=$(slings)
: > "$ESC_CALLS"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "$before" "a capped bead is NOT re-slung — the convoy-per-pass leak stops"
eq "$(escalations)" "1" "a capped bead is handed to a person exactly once"
eq "$(head -1 "$ESC_CALLS" | cut -f2)" "deferred-dispatch-sling-failed.b-1" "the escalation is keyed per bead, so repeated passes dedup to one visit"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "a capped bead keeps its arm for the person, never a silent retire"
has "$out" "CAPPED b-1" "the cap is reported"

echo "# a proven dispatch clears the accumulated fail count, resetting the budget"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_fail_count":"2"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "1" "a bead one short of the cap is still slung"
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "<absent>" "a proven dispatch clears the fail count so a later arm starts fresh"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "and the arm is retired"
has "$out" "1 dispatched" "summary counts the dispatch"

echo "# reconcile refuses a malformed arg list"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"not-json"},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "0" "a malformed arg list does not produce a sling"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "a malformed arg list leaves the record for a human"
has "$out" "malformed" "the malformed record is reported"

# --- RECONCILE: the until resolved-by consumer -------------------------------
# An `until` dep means "X resolves me": when X closes the bead is DISPOSED, not
# re-triaged. The same pass disposes every open, unassigned bead whose own
# `until` targets have all closed and that carries no live work, through
# bead-rehome so the close carries a successor pointer. ONLY `until` disposes — a
# `blocks` edge is sequencing and its target closing leaves the dependent fully
# owed. Every candidate below names issue_type task: a bead whose type is not
# plain work is never disposed.
echo "# until: dispose a resolved bead"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a resolved until-gated bead is a clean pass"
eq "$(rehomes)" "1" "exactly one disposal"
eq "$(rehome_call 1)" "$(printf 'g-1\tx-1\tfolded')" "disposed g-1 toward its until target x-1, kind folded (successor pointer, not a bare close)"
eq "$(status_of g-1)" "closed" "the disposed bead is closed by bead-rehome, never by this script"
has "$out" "disposed g-1" "the disposal is reported"
has "$out" "until-resolved: 1 disposed, 0 live" "the summary counts it"

echo "# until: wait while the target is still open"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(rehomes)" "0" "an until-gated bead whose target is still open is NOT disposed"
eq "$(status_of g-1)" "open" "it stays open"
has "$out" "until-resolved: 0 disposed, 0 live, 0 held, 1 waiting" "it counts as waiting"

echo "# until: ONLY until disposes — a blocks edge to a closed target never does"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"blocks"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "a blocks edge to a closed target is never disposed (the scope guard)"
eq "$(status_of g-1)" "open" "the blocks-gated bead is untouched"
has "$out" "until-resolved: 0 disposed, 0 live, 0 held, 0 waiting, 0 blocked, 0 left for the next pass (of 0 until-gated)" "a blocks-only bead is not even an until candidate"

echo "# until: a deliberate hold (non-open status) is left alone"
store '[
 {"id":"g-1","issue_type":"task","status":"blocked","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "a non-open (held) until-gated bead is left alone"
has "$out" "of 0 until-gated" "a held status is not an until candidate"

echo "# until: a bead a live worker holds is left alone"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"someone/else","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "an until-gated bead an assignee holds is left alone"
has "$out" "of 0 until-gated" "an assigned bead is not an until candidate"

# --- the live-work guard ------------------------------------------------------
# An open, unassigned bead can still be live work: an anchor stays open and
# unassigned while its PR is reviewed, and so does a bead slung to a pool until a
# worker claims it. bead-rehome can stamp its pointer and still have the close
# refused, and bd closes such a bead without complaint, so the guard must stop it
# before bead-rehome is called at all. Each case: the until target has closed,
# bead-rehome is never called, the bead stays open, and the pass is clean.
live_case() { # name metadata-json expected-mark
    store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":'"$2"',"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
    export STUB_BD_LOG="$TMP/bd-live.log"; : > "$STUB_BD_LOG"
    out="$("$SUT" reconcile 2>&1)"; rc=$?
    eq "$rc" 0 "$1: a live-work hold is an expected state, not a pass failure"
    eq "$(rehomes)" "0" "$1: bead-rehome is never called, so no successor pointer is stamped"
    eq "$(status_of g-1)" "open" "$1: the bead stays open"
    has "$out" "LEFT g-1" "$1: the hold is reported, not silent"
    has "$out" "$3" "$1: the report names the mark that makes it live"
    has "$out" "until-resolved: 0 disposed, 1 live, 0 held, 0 waiting, 0 blocked, 0 left for the next pass (of 1 until-gated)" "$1: the summary counts it as live"
    eq "$(grep -c '^show' "$STUB_BD_LOG")" "0" "$1: a mark on the pass-start row needs no further read"
    unset STUB_BD_LOG
}
echo "# until: an anchor mid-PR is live work"
live_case "anchor mid-PR" '{"branch":"polecat/g-1","merge_result":"pull_request","pr_url":"https://github.com/o/r/pull/7","pr_number":"7"}' "merge_result=pull_request"
echo "# until: an anchor at the pre-open gate is live work"
live_case "pre-open anchor" '{"branch":"polecat/g-1","merge_result":"pre_open_gate"}' "merge_result=pre_open_gate"
echo "# until: work slung to a pool and not yet claimed is live work"
live_case "pool-slung" '{"gc.routed_to":"rig/rig.polecat"}' "gc.routed_to=rig/rig.polecat"
echo "# until: work poured through a formula is live work"
live_case "formula-slung" '{"gc.execution_routed_to":"rig/rig.polecat"}' "gc.execution_routed_to=rig/rig.polecat"
echo "# until: a deferred dispatch still armed behind an open blocker waits for that blocker"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/rig.polecat","gc.dispatch_when_ready_args":"[]"},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"y-1","dependency_type":"blocks"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"y-1","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "armed: the pass is clean"
eq "$(slings)" "0" "armed: the arm still waits on its open blocker"
eq "$(rehomes)" "0" "armed: an armed bead is never disposed"
eq "$(meta g-1 gc.dispatch_when_ready)" "rig/rig.polecat" "armed: the arm is untouched"
has "$out" "1 blocked" "armed: its open blocker holds it before its live work is read"
echo "# until: an arm the retry cap stopped is live work"
# The dispatch half will not sling a capped arm, so the arm is still on the bead
# when the until half reads it.
live_case "capped arm" '{"gc.dispatch_when_ready":"rig/rig.polecat","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_fail_count":"3"}' "gc.dispatch_when_ready=rig/rig.polecat"
echo "# until: a bead a session is bound to is live work"
live_case "session-bound" '{"gc.session_name":"rig__polecat-1"}' "gc.session_name=rig__polecat-1"
echo "# until: a bead with a worktree is live work"
live_case "worktree" '{"work_dir":"/tmp/wt/g-1"}' "work_dir=/tmp/wt/g-1"
echo "# until: a visit is closed by its own closers, never by this pass"
live_case "visit" '{"task_kind":"visit"}' "task_kind=visit"
echo "# until: a workflow step is closed by its molecule"
live_case "step" '{"gc.root_bead_id":"r-1","gc.step_ref":"mol-polecat-work.implement"}' "gc.root_bead_id=r-1"
echo "# until: a parked bead is somebody's judgement in progress"
live_case "parked" '{"hold_reason":"waiting on the operator"}' "hold_reason=waiting on the operator"

echo "# until: an epic closes on its own ruling, never by this pass"
store '[
 {"id":"g-1","issue_type":"epic","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "an epic is never disposed"
has "$out" "issue_type=epic" "the report names its type"
echo "# until: a bead with no readable issue type is not plain work"
store '[
 {"id":"g-1","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "a row with no issue_type is never disposed (an unread mark refuses)"

echo "# until: work just slung by this same pass is live work"
# The dispatch half runs first and slings an armed bead its blockers no longer
# hold, then clears the arm. What is left on the bead is the route the sling
# stamped, and the until half, reading after it, must leave the bead alone.
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","_ready":true,"metadata":{"gc.dispatch_when_ready":"rig/rig.polecat","gc.dispatch_when_ready_args":"[]"},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_SLING_STAMPS=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(slings)" "1" "the dispatch half slings the armed bead"
eq "$(meta g-1 gc.dispatch_when_ready)" "<absent>" "and clears the arm"
eq "$(rehomes)" "0" "the until half does not dispose the bead it just slung"
eq "$(status_of g-1)" "open" "the slung bead stays open for its pool"
has "$out" "gc.routed_to=rig/rig.polecat" "the report names the route the sling left"

echo "# until: a convoy tracking the bead makes it live work, though its metadata is clean"
# A pour mints a convoy that tracks the bead, and that edge outlives a route the
# metadata no longer carries. Only the fresh read of the bead's dependents sees it.
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"c-1","issue_type":"convoy","status":"closed","assignee":"","metadata":{},"notes":"","_deps":[{"id":"g-1","dependency_type":"tracks"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(rehomes)" "0" "a convoy-tracked bead is never disposed, even when that convoy has closed"
has "$out" "tracked by convoy c-1 (closed)" "the report names the convoy"

echo "# until: an open child under the bead makes it live work; a closed one does not"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"k-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"g-1","dependency_type":"parent-child"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "a bead with an open child is never disposed"
has "$out" "open child k-1" "the report names the child"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"k-1","issue_type":"task","status":"closed","assignee":"","metadata":{},"notes":"","_deps":[{"id":"g-1","dependency_type":"parent-child"}]},
 {"id":"b-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"g-1","dependency_type":"blocks"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
"$SUT" reconcile >/dev/null 2>&1
eq "$(rehomes)" "1" "a closed child, or a bead waiting on this one, is not live work on it"

echo "# until: a member of a convoy is live work"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"cv-1","dependency_type":"parent-child"}]},
 {"id":"cv-1","issue_type":"convoy","status":"open","assignee":"","metadata":{},"notes":""},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "a convoy child is never disposed"
has "$out" "child of convoy cv-1" "the report names the convoy"

# A subject slung on mol-design-convoy, as the sling and the run leave it: the
# pour's stamp, the input convoy ic-1 tracking it, the run's records naming its
# owned convoy cv-1, and other work m-1 waiting on it. The formula's own blocks,
# extracted verbatim, write the subject's until edge (seed-convoy) and hand it
# off (drain); the graduation PR's merge then closes cv-1.
DESIGN_FORMULA="$ROOT/formulas/mol-design-convoy.toml"
design_block() { # <marker> -> the block between the marker pair, {{convoy_id}} rendered as ic-1
    awk -v m="$1" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$DESIGN_FORMULA" \
        | sed 's/{{convoy_id}}/ic-1/g'
}
design_store() {
    store '[
 {"id":"s-1","issue_type":"task","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/rig.polecat","gc.design_convoy_id":"cv-1","gc.design_convoy_branch":"integration/cv-1","gc.design_child":"d-1","gc.design_armed":"1","gc.impl_child":"i-1","gc.impl_armed":"1"},"notes":""},
 {"id":"ic-1","issue_type":"convoy","status":"open","assignee":"","metadata":{"gc.synthetic":"true"},"notes":"","_deps":[{"id":"s-1","dependency_type":"tracks"}]},
 {"id":"cv-1","issue_type":"convoy","status":"open","assignee":"","metadata":{"target":"integration/cv-1"},"notes":""},
 {"id":"m-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"s-1","dependency_type":"blocks"}]}]'
}
close_bead() { jq -c --arg id "$1" 'map(if .id == $id then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.c" && mv "$STUB_STORE.c" "$STUB_STORE"; }
design_block seed-convoy-until > "$TMP/design-until.sh"
design_block drain-hand-off > "$TMP/design-hand-off.sh"

echo "# until: a design-convoy subject closes once its owned convoy closes"
if [ -s "$TMP/design-until.sh" ] && [ -s "$TMP/design-hand-off.sh" ]; then
    ok "the design-convoy formula's until and hand-off blocks are extracted"
else
    bad "the design-convoy formula's until or hand-off block is missing from $DESIGN_FORMULA"
fi
design_store
SUBJECT=s-1 CONVOY_ID=cv-1 bash "$TMP/design-until.sh" >/dev/null 2>&1; rc=$?
eq "$rc" 0 "seed-convoy writes the subject's until edge onto its owned convoy and reads it back"
"$SUT" reconcile >/dev/null 2>&1
eq "$(rehomes)" "0" "the subject waits while its owned convoy is open"
bash "$TMP/design-hand-off.sh" >/dev/null 2>&1; rc=$?
eq "$rc" 0 "drain hands the subject off"
eq "$(meta s-1 gc.execution_routed_to)" "<absent>" "the hand-off clears the pour's stamp"
eq "$(status_of ic-1)" "closed" "the hand-off closes the input convoy"
close_bead cv-1
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(rehome_call 1)" "$(printf 's-1\tcv-1\tfolded')" "the subject is disposed toward its owned convoy once that convoy closes"
eq "$(status_of s-1)" "closed" "the subject is closed"
eq "$(meta s-1 gc.superseded_by)" "cv-1" "its successor pointer names the owned convoy"

echo "# until: a design-convoy subject its run never handed off stays open"
design_store
SUBJECT=s-1 CONVOY_ID=cv-1 bash "$TMP/design-until.sh" >/dev/null 2>&1
close_bead cv-1
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "a subject still carrying the pour's marks is never disposed"
has "$out" "LEFT s-1" "the hold is reported"
has "$out" "gc.execution_routed_to=rig/rig.polecat" "the report names the pour's stamp"

echo "# until: the fresh read catches a route that landed after the pass-start listing"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
fresh_store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/rig.polecat"},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_FRESH_STORE="$TMP/fresh-store.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(rehomes)" "0" "a bead slung after the listing is not disposed"
has "$out" "gc.routed_to=rig/rig.polecat" "the fresh read's mark is reported"

echo "# until: a target reopened after the pass-start listing leaves the bead waiting"
fresh_store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_FRESH_STORE="$TMP/fresh-store.json" "$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "a bead whose until target reopened is not disposed"
has "$out" "0 disposed, 0 live, 0 held, 1 waiting" "it counts as waiting"

echo "# until: an unreadable fresh read leaves the bead and fails the pass"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_DEP_UP_FAIL=g-1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a bead owed a disposal that could not be re-read fails the pass"
eq "$(rehomes)" "0" "and is not disposed"
has "$out" "could not re-read g-1" "the failure is reported"
out="$(STUB_BD_ROW_FAIL=g-1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a bead whose own row could not be re-read by id fails the pass"
eq "$(rehomes)" "0" "and is not disposed"
has "$out" "could not re-read g-1" "that failure is reported too"

echo "# until: without until-resolved.sh the consumer disposes nothing"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"a-1","issue_type":"task","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":""}]'
# hold-lib.sh and bd-lib.sh go beside the copy, because without either the
# script exits before any verb, so until-resolved.sh is the one library missing.
mkdir -p "$TMP/lonely"; cp "$SUT" "$TMP/lonely/deferred-dispatch.sh"; cp "$HERE/hold-lib.sh" "$HERE/bd-lib.sh" "$TMP/lonely/"
out="$("$TMP/lonely/deferred-dispatch.sh" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a pass that cannot read the guard fails"
eq "$(rehomes)" "0" "and disposes nothing"
has "$out" "cannot source until-resolved.sh" "the reason is reported"
has "$out" "KEPT the arm on closed a-1" "with no way to tell a close under the claim, the dispatch half keeps the arm on a closed bead"
eq "$(meta a-1 gc.dispatch_when_ready)" "rig/pool" "and the arm stands"

echo "# until: dispose only when ALL targets closed; successor is the latest-closed"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"x-2","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":"","closed_at":"2026-01-01T00:00:00Z"},
 {"id":"x-2","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "a bead with two until targets, one still open, is NOT disposed"
has "$out" "0 disposed, 0 live, 0 held, 1 waiting" "it waits for the last target to close"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"x-2","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":"","closed_at":"2026-01-01T00:00:00Z"},
 {"id":"x-2","status":"closed","assignee":"","metadata":{},"notes":"","closed_at":"2026-02-01T00:00:00Z"}]'
"$SUT" reconcile >/dev/null 2>&1
eq "$(rehome_call 1)" "$(printf 'g-1\tx-2\tfolded')" "with all targets closed, the successor is the latest-closed (x-2)"

echo "# until: a held close (bead-rehome refuses) is reported and retried, not a failure"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_REHOME_RC=5 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a held close (bead-rehome rc=5) is not a pass failure"
eq "$(rehomes)" "1" "the disposal was attempted"
has "$out" "HELD g-1" "the hold is reported, not silent"
has "$out" "until-resolved: 0 disposed, 0 live, 1 held" "the summary counts it as held"

echo "# until: a hard dispose failure fails the pass (fail-closed)"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_REHOME_RC=7 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a hard dispose failure fails the pass"
has "$out" "could not dispose" "the failure is reported, not swallowed"

echo "# until: dry-run disposes nothing"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile --dry-run 2>&1)"
eq "$(rehomes)" "0" "dry-run calls bead-rehome zero times"
eq "$(status_of g-1)" "open" "dry-run leaves the bead open"
has "$out" "DRY-RUN would dispose g-1" "dry-run says what it would do"

echo "# until: an unreadable store never disposes (fail-closed)"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_BD_LIST_FAIL=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "an unreadable store exits non-zero, never disposing an until-gated bead"
eq "$(rehomes)" "0" "and attempts no disposal"

echo "# until: enumeration is a bounded read count; only a disposal reads its own bead"
export STUB_BD_LOG="$TMP/bd-until.log"
store '[
 {"id":"u-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"ux-1","dependency_type":"until"}]},
 {"id":"u-2","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"ux-2","dependency_type":"until"}]},
 {"id":"u-3","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"ux-3","dependency_type":"until"}]},
 {"id":"u-4","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"ux-4","dependency_type":"until"}]},
 {"id":"ux-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"ux-2","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"ux-3","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"ux-4","status":"open","assignee":"","metadata":{},"notes":""}]'
: > "$STUB_BD_LOG"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a bulk pass over four until-gated beads is a clean pass"
eq "$(rehomes)" "3" "all three resolved until-gated beads are disposed in one pass"
# No armed beads here, so armed costs two reads (all + ready, no blocker batch);
# the until consumer costs three more (candidate scan + one target-status batch
# + one listing of the closes an earlier pass left unchecked), whatever the
# candidate count. A disposal reads its own bead, its own row by id and its
# dependents twice: under its claim just before the close, and again just
# after it. The waiting candidate u-4 costs nothing.
eq "$(grep '^list' "$STUB_BD_LOG" | grep -v -F -e 'gc.notify_when_ready' | grep -vc '^list --id u-[0-9] ')" "5" "enumeration costs a bounded read count (candidate scan + one target-status batch + one listing of unchecked closes), not one per bead"
eq "$(grep -c '^show' "$STUB_BD_LOG")" "6" "each disposal reads its own bead before its close and after it, and a waiting candidate is not read"
eq "$(grep -c '^list --id u-[0-9] ' "$STUB_BD_LOG")" "6" "each disposal reads its own row by id before its close and after it, and a waiting candidate is not read"
eq "$(grep -c '^dep list' "$STUB_BD_LOG")" "6" "each disposal reads its own dependents before its close and after it, and a waiting candidate is not read"
unset STUB_BD_LOG

echo "# until: a bead whose until edge was removed after the listing is kept"
# Removing the edge is how a person keeps the bead, and the doctor names it as
# the remedy. The listing still shows the edge, so only the fresh read sees it go.
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
fresh_store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_FRESH_STORE="$TMP/fresh-store.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "an edge removed mid-pass is an expected state, not a pass failure"
eq "$(rehomes)" "0" "the bead is not handed to bead-rehome"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "so no successor pointer is stamped on the work a person chose to keep"
eq "$(status_of g-1)" "open" "the bead stays open"
has "$out" "KEPT g-1" "the pass says why it kept the bead"

echo "# until: a bead its own open blocks blocker holds is never handed to bead-rehome"
# bead-rehome stamps its pointer before bd refuses to close a blocked bead, so a
# call here would leave a live bead pointing at a successor every pass.
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"y-1","dependency_type":"blocks"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"y-1","status":"open","assignee":"","metadata":{},"notes":""}]'
export STUB_BD_LOG="$TMP/bd-blocked.log"; : > "$STUB_BD_LOG"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a bead held by its open blocker is an expected state, not a pass failure"
eq "$(rehomes)" "0" "bead-rehome is not called while its blocks blocker is open"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "so no successor pointer is stamped"
eq "$(grep -c '^show' "$STUB_BD_LOG")" "0" "the scan decides it blocked, so the pass spends no fresh read on it"
unset STUB_BD_LOG
has "$out" "until-resolved: 0 disposed, 0 live, 0 held, 0 waiting, 1 blocked, 0 left for the next pass (of 1 until-gated)" "the summary counts it as blocked"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"y-1","dependency_type":"blocks"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"y-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
"$SUT" reconcile >/dev/null 2>&1
eq "$(rehome_call 1)" "$(printf 'g-1\tx-1\tfolded')" "once the blocker closes, the bead is disposed"

echo "# until: a blocks blocker added after the listing holds the bead"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"y-1","status":"open","assignee":"","metadata":{},"notes":""}]'
fresh_store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"y-1","dependency_type":"blocks"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"y-1","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_FRESH_STORE="$TMP/fresh-store.json" "$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "the fresh read's open blocker stops the disposal"
has "$out" "1 blocked" "and it is counted as blocked"

echo "# until: a blocks blocker this store cannot read leaves the bead undecided"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"far-1","dependency_type":"blocks"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "an unreadable blocker is reported, not a pass failure"
eq "$(rehomes)" "0" "a blocker whose status is unknown never reads as a closed one"
has "$out" "UNRESOLVED g-1" "the pass names the bead it cannot decide"
has "$out" "far-1" "and the id it could not read"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"","dependency_type":"until"}]}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "an until edge with no target id is never disposed"
has "$out" "names no target" "and the pass says so"

echo "# until: an edge added after the listing, to a bead this store has no row for, leaves the bead undecided"
# bd show leaves out an edge whose target has no row in the store, though its
# dependency_count counts it, so the show alone still reads the bead as owed by
# its one closed target. The row of the bead read by id carries the new edge.
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
fresh_store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"far-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_FRESH_STORE="$TMP/fresh-store.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "an edge this store cannot read is reported, not a pass failure"
eq "$(rehomes)" "0" "the bead is not handed to bead-rehome"
eq "$(status_of g-1)" "open" "the bead stays open"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "so no successor pointer is stamped"
has "$out" "UNRESOLVED g-1" "the pass names the bead it cannot decide"
has "$out" "far-1" "and the id it could not read"
has "$out" "0 disposed, 0 live, 0 held, 1 waiting" "it counts as waiting"
fresh_store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"},{"id":"far-2","dependency_type":"blocks"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_FRESH_STORE="$TMP/fresh-store.json" "$SUT" reconcile 2>&1)"
eq "$(rehomes)" "0" "a blocks blocker this store cannot read, added after the listing, holds the bead as well"
has "$out" "UNRESOLVED g-1 — its edges name far-2" "and is named"

# --- the claim a disposal is made under ---------------------------------------
# A dispatch writes its mark whatever the bead holds, so no read before a close
# can keep one out of the gap between that read and the close. The pass claims
# the bead in one write conditional on its status and assignee, decides the
# disposal on a read under that claim, closes the bead through bead-rehome
# acting as the claim, and reads it again after the close: a mark that landed
# while the pass held the bead reopens it and withdraws the pointer. A pass that
# stopped holding a claim leaves it for the next pass to finish.
G1_OWED='[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
ROUTE_G1='map(if .id == "g-1" then .metadata["gc.routed_to"] = "rig/rig.polecat" else . end)'

echo "# until: the disposal is made under a claim, released once the close stands"
store "$G1_OWED"
export STUB_BD_LOG="$TMP/bd-claim.log"; : > "$STUB_BD_LOG"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a disposal under the claim is a clean pass"
eq "$(rehomes)" "1" "the bead is handed to bead-rehome once"
eq "$(rehome_actor 1)" "deferred-dispatch" "bead-rehome acts as the claim, the actor bd's close requires of a bead assigned to it"
eq "$(status_of g-1)" "closed" "the bead is closed"
eq "$(assignee_of g-1)" "" "the claim is released from the closed bead"
eq "$(meta g-1 gc.superseded_by)" "x-1" "the successor pointer stands"
claim_at="$(grep -n -F -x -e 'update g-1 --if-status=open --if-assignee= --status=in_progress --assignee=deferred-dispatch --unset-metadata=gc.until_disposal' "$STUB_BD_LOG" | head -1 | cut -d: -f1)"
read_at="$(grep -n '^show g-1' "$STUB_BD_LOG" | head -1 | cut -d: -f1)"
if [ -n "$claim_at" ] && [ -n "$read_at" ] && [ "$claim_at" -lt "$read_at" ]; then
    ok "the claim is one conditional write, made before the read the disposal is decided on"
else
    bad "the claim is one conditional write, made before the read the disposal is decided on (claim at line '${claim_at:-none}', read at line '${read_at:-none}')"
fi
eq "$(grep -c '^show g-1' "$STUB_BD_LOG")" "2" "the bead is read under the claim and again after its close"
mark_at="$(grep -n -F -x -e 'update g-1 --if-status=in_progress --if-assignee=deferred-dispatch --set-metadata=gc.until_disposal=x-1' "$STUB_BD_LOG" | head -1 | cut -d: -f1)"
reread_at="$(grep -n '^show g-1' "$STUB_BD_LOG" | sed -n 2p | cut -d: -f1)"
if [ -n "$mark_at" ] && [ -n "$read_at" ] && [ -n "$reread_at" ] && [ "$read_at" -lt "$mark_at" ] && [ "$mark_at" -lt "$reread_at" ]; then
    ok "the pass marks the bead with its successor in one write conditional on the claim, after the read under the claim and before the close"
else
    bad "the pass marks the bead with its successor in one write conditional on the claim, after the read under the claim and before the close (read at '${read_at:-none}', mark at '${mark_at:-none}', read after the close at '${reread_at:-none}')"
fi
eq "$(meta g-1 gc.until_disposal)" "<absent>" "the mark goes with the claim"
eq "$(grep -c -F -x -e 'update g-1 --if-status=closed --if-assignee=deferred-dispatch --assignee= --unset-metadata=gc.until_disposal' "$STUB_BD_LOG")" "1" "the release from the closed bead is conditional on the claim, and clears its mark"
unset STUB_BD_LOG

echo "# until: a dispatch that lands before the claim keeps the bead"
store "$G1_OWED"
out="$(STUB_RACE_AT='--if-status=open' STUB_RACE_JQ="$ROUTE_G1" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a bead routed before the claim is a clean pass"
eq "$(rehomes)" "0" "a bead routed between the listing and the claim never reaches bead-rehome"
eq "$(status_of g-1)" "open" "it is open again"
eq "$(assignee_of g-1)" "" "the claim is given back"
eq "$(meta g-1 gc.routed_to)" "rig/rig.polecat" "the route stands, so its pool can claim the bead"
has "$out" "LEFT g-1" "the bead is reported"
has "$out" "gc.routed_to=rig/rig.polecat" "with the route the read under the claim found"
has "$out" "until-resolved: 0 disposed, 1 live" "it counts as live work"

echo "# until: a worker's claim that lands before the pass claims the bead stands"
store "$G1_OWED"
out="$(STUB_RACE_AT='--if-status=open' STUB_RACE_JQ='map(if .id == "g-1" then (.status = "in_progress" | .assignee = "rig/rig.polecat-1") else . end)' "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a bead a worker claimed first is a clean pass"
eq "$(rehomes)" "0" "the worker's bead never reaches bead-rehome"
eq "$(status_of g-1)" "in_progress" "it stays in progress"
eq "$(assignee_of g-1)" "rig/rig.polecat-1" "under the worker that claimed it"
has "$out" "LEFT g-1 — it is no longer open and unassigned" "the pass says why it left the bead"
has "$out" "until-resolved: 0 disposed, 1 live" "it counts as live work"

echo "# until: a dispatch that lands while the pass holds the bead reopens it"
# The bead is routed after the read under the claim and before bead-rehome
# closes it, the gap no read before the close can see into.
store "$G1_OWED"
out="$(GC_REHOME_TOOL="$BIN/rehome-race.sh" STUB_REHOME_RACE_JQ="$ROUTE_G1" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a disposal a dispatch raced is a clean pass"
eq "$(rehomes)" "1" "the bead reached bead-rehome, which closed it"
eq "$(status_of g-1)" "open" "the bead is reopened"
eq "$(assignee_of g-1)" "" "and unassigned, so its pool can claim it"
eq "$(meta g-1 gc.routed_to)" "rig/rig.polecat" "the route stands"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "the successor pointer is withdrawn"
eq "$(meta g-1 gc.superseded_by_store)" "<absent>" "and so is its store"
has "$(notes g-1)" "Reopened" "the bead records why it was reopened"
has "$(notes g-1)" "gc.routed_to=rig/rig.polecat" "naming the mark that landed"
has "$out" "REOPENED g-1" "the pass reports the reopen"
has "$out" "until-resolved: 0 disposed, 1 live" "and counts the bead as live work, not a disposal"

echo "# until: an until edge removed while the pass holds the bead reopens it"
store "$G1_OWED"
out="$(GC_REHOME_TOOL="$BIN/rehome-race.sh" STUB_REHOME_RACE_JQ='map(if .id == "g-1" then ._deps = [] else . end)' "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(status_of g-1)" "open" "a bead whose edge was removed while the pass held it is reopened"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "with no successor pointer"
has "$(notes g-1)" "its until edge to x-1 is gone" "the bead records the removed edge"

# The real disposer, against the same fixture store: a pinned pass names its
# store, so bead-rehome resolves it through `gc rig list` and every read and
# write it makes reaches this store through `gc bd`. bd closes an assigned bead
# only for its assignee, which the stub's close enforces, so a pass that did not
# run bead-rehome as the claim would leave the bead unclosed.
mkdir -p "$TMP/rig-a/.beads"
printf '{"rigs":[{"name":"rig-a","path":"%s"}]}\n' "$TMP/rig-a" > "$TMP/rigs-a.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/finalize-gate-pass.sh"; chmod +x "$BIN/finalize-gate-pass.sh"
real_rehome() { STUB_RIGS_JSON="$TMP/rigs-a.json" GC_FINALIZE_GATE_TOOL="$BIN/finalize-gate-pass.sh" "$@"; }
close_reason() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .close_reason) // ""' "$STUB_STORE"; }

echo "# until: through the real bead-rehome, a disposal closes the bead with its pointer"
store "$G1_OWED"
out="$(real_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
eq "$rc" 0 "the real disposer's close is a clean pass"
eq "$(status_of g-1)" "closed" "the real bead-rehome closes the claimed bead"
eq "$(assignee_of g-1)" "" "and the claim is released from it"
eq "$(meta g-1 gc.superseded_by)" "x-1" "the pointer the real disposer stamped stands"
has "$(close_reason g-1)" "folded into x-1" "its close reason names the successor"
has "$out" "disposed g-1" "the disposal is reported"

echo "# until: through the real bead-rehome, a dispatch that lands while the pass holds the bead reopens it"
store "$G1_OWED"
out="$(real_rehome env GC_REHOME_TOOL="$BIN/rehome-race.sh" STUB_REHOME_NEXT="$HERE/bead-rehome.sh" STUB_REHOME_RACE_JQ="$ROUTE_G1" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
eq "$rc" 0 "the raced disposal through the real disposer is a clean pass"
eq "$(status_of g-1)" "open" "the bead the real disposer closed is reopened"
eq "$(assignee_of g-1)" "" "unassigned"
eq "$(meta g-1 gc.routed_to)" "rig/rig.polecat" "with its route"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "and no successor pointer"
eq "$(close_reason g-1)" "" "and no close reason"
has "$out" "REOPENED g-1" "the reopen is reported"
has "$out" "until-resolved: 0 disposed, 1 live" "the bead counts as live work"

echo "# until: a held close gives the bead back"
store "$G1_OWED"
out="$(STUB_REHOME_RC=5 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a held close is an expected state"
eq "$(status_of g-1)" "open" "the bead is open again"
eq "$(assignee_of g-1)" "" "and unassigned"
eq "$(meta g-1 gc.until_disposal)" "<absent>" "and unmarked"
has "$out" "HELD g-1" "the hold is reported"

echo "# until: a failed disposal gives the bead back and fails the pass"
store "$G1_OWED"
out="$(STUB_REHOME_RC=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a hard disposal failure fails the pass"
eq "$(status_of g-1)" "open" "the bead is open again"
eq "$(assignee_of g-1)" "" "and unassigned"
eq "$(meta g-1 gc.until_disposal)" "<absent>" "and unmarked"

# The real disposer stamps its pointer before its finalize gate and its close,
# so a close the gate holds leaves that pointer behind. A gate that refuses
# stands in for an open visit on the bead.
printf '#!/usr/bin/env bash\necho "an open visit holds the close"\nexit 1\n' > "$BIN/finalize-gate-hold.sh"; chmod +x "$BIN/finalize-gate-hold.sh"
held_rehome() { STUB_RIGS_JSON="$TMP/rigs-a.json" GC_FINALIZE_GATE_TOOL="$BIN/finalize-gate-hold.sh" "$@"; }

echo "# until: through the real bead-rehome, a held close gives the bead back without the pointer it stamped"
store "$G1_OWED"
export STUB_BD_LOG="$TMP/bd-held.log"; : > "$STUB_BD_LOG"
out="$(held_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
eq "$rc" 0 "a close the real disposer had held is an expected state"
mark_at="$(grep -n -F -e 'update g-1 --if-status=in_progress --if-assignee=deferred-dispatch --set-metadata=gc.until_disposal=x-1' "$STUB_BD_LOG" | head -1 | cut -d: -f1)"
stamp_at="$(grep -n -F -e 'update g-1 --if-status=in_progress --if-assignee=deferred-dispatch --set-metadata gc.superseded_by=x-1' "$STUB_BD_LOG" | head -1 | cut -d: -f1)"
if [ -n "$mark_at" ] && [ -n "$stamp_at" ] && [ "$mark_at" -lt "$stamp_at" ]; then
    ok "the pass marks the bead before the real disposer stamps its pointer, in a write conditional on the claim"
else
    bad "the pass marks the bead before the real disposer stamps its pointer, in a write conditional on the claim (mark at line '${mark_at:-none}', stamp at line '${stamp_at:-none}')"
fi
unset STUB_BD_LOG
eq "$(status_of g-1)/$(assignee_of g-1)" "open/" "the bead is open and unassigned again"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "the pointer the real disposer stamped is withdrawn"
eq "$(meta g-1 gc.superseded_by_store)" "<absent>" "and so is its store"
eq "$(meta g-1 gc.until_disposal)" "<absent>" "and the mark"
eq "$(close_reason g-1)" "" "and nothing closed it"
has "$out" "HELD g-1" "the hold is reported"
has "$out" "the successor pointer bead-rehome stamped is withdrawn" "with the withdrawal"
out="$(held_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"
has "$out" "HELD g-1" "the next pass retries the disposal, since nothing marks the bead live"
out="$(real_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"
eq "$(status_of g-1)" "closed" "once the hold clears, a pass disposes it"
eq "$(meta g-1 gc.superseded_by)" "x-1" "with its pointer"

echo "# until: through the real bead-rehome, a dispatch that lands under the claim before a held close leaves the bead routed and unpointed"
store "$G1_OWED"
out="$(held_rehome env GC_REHOME_TOOL="$BIN/rehome-race.sh" STUB_REHOME_NEXT="$HERE/bead-rehome.sh" STUB_REHOME_RACE_JQ="$ROUTE_G1" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(status_of g-1)/$(assignee_of g-1)" "open/" "the bead is given back, open and unassigned"
eq "$(meta g-1 gc.routed_to)" "rig/rig.polecat" "with the route that landed, so its pool can claim it"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "and no pointer, which would read as a disposal once the bead carries a PR"
out="$(held_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"
has "$out" "LEFT g-1" "the next pass leaves the routed bead as live work"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "and no pointer reappears"

echo "# until: a give-back after a held close that does not land keeps the claim, the pointer and its mark, and the next pass withdraws the pointer"
store "$G1_OWED"
out="$(held_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" STUB_UPDATE_FAIL_AT='--if-assignee=deferred-dispatch --status=open' "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
eq "$rc" 1 "a give-back that did not land fails the pass"
eq "$(status_of g-1)/$(assignee_of g-1)" "in_progress/deferred-dispatch" "the bead stays under the claim"
eq "$(meta g-1 gc.superseded_by)/$(meta g-1 gc.until_disposal)" "x-1/x-1" "with the pointer and the mark that names it"
has "$out" "with the successor pointer this pass had bead-rehome stamp" "the failure names the pointer it left"
out="$(held_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
eq "$rc" 0 "the next pass is clean"
has "$out" "withdrawing the successor pointer to x-1 that pass had bead-rehome stamp" "it gives the bead back first, withdrawing that pointer"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "the pointer is gone"
eq "$(status_of g-1)/$(assignee_of g-1)" "open/" "and the bead is open and unassigned once its retry is held again"

echo "# until: a claim an earlier pass left is given back, and the bead disposed"
store '[
 {"id":"g-1","issue_type":"task","status":"in_progress","assignee":"deferred-dispatch","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "finishing a claim a pass left is a clean pass"
has "$out" "gave back g-1" "the claim a pass left is given back first"
eq "$(status_of g-1)" "closed" "then the owed bead is disposed"
eq "$(assignee_of g-1)" "" "and left unassigned"
eq "$(meta g-1 gc.superseded_by)" "x-1" "with its pointer"

echo "# until: a claim an earlier pass left on a bead since routed gives it to its pool"
store '[
 {"id":"g-1","issue_type":"task","status":"in_progress","assignee":"deferred-dispatch","metadata":{"gc.routed_to":"rig/rig.polecat"},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(rehomes)" "0" "the routed bead is not disposed"
eq "$(status_of g-1)" "open" "it is open"
eq "$(assignee_of g-1)" "" "and unassigned, so its pool can claim it"
has "$out" "LEFT g-1" "its live work is reported"

echo "# until: a close an earlier pass made and did not check is checked"
store '[
 {"id":"g-1","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{"gc.superseded_by":"x-1"},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "checking a close a pass left is a clean pass"
has "$out" "the close an earlier pass made under deferred-dispatch stands" "the close is checked"
eq "$(status_of g-1)" "closed" "and stands"
eq "$(assignee_of g-1)" "" "with the claim released"
store '[
 {"id":"g-1","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{"gc.superseded_by":"x-1","gc.routed_to":"rig/rig.polecat"},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(status_of g-1)" "open" "a close a dispatch raced, found by the next pass, is withdrawn"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "with its pointer"
has "$out" "REOPENED g-1" "and reported"
store '[
 {"id":"g-1","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(status_of g-1)" "closed" "a close with no pointer is not a disposal, and stands"
eq "$(assignee_of g-1)" "" "only the claim is released from it"
has "$out" "closed with no successor pointer" "the pass says why"

echo "# until: a close the pass cannot check stays under the claim, and the next pass checks it"
store "$G1_OWED"
rm -f "$TMP/rehomed"
out="$(GC_REHOME_TOOL="$BIN/rehome-race.sh" STUB_REHOME_RACE_JQ='.' STUB_REHOME_TOUCH="$TMP/rehomed" STUB_SHOW_FAIL_WHEN="$TMP/rehomed" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a close the pass could not check fails the pass"
eq "$(status_of g-1)" "closed" "the close stands"
eq "$(assignee_of g-1)" "deferred-dispatch" "under the claim, which marks it unchecked"
has "$out" "could not re-read g-1 after closing it" "the failure is reported"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the next pass is clean"
has "$out" "the close an earlier pass made under deferred-dispatch stands" "it checks the close"
eq "$(assignee_of g-1)" "" "and releases the claim"

echo "# until: a give-back that fails leaves the claim for the next pass, and fails this one"
store "$G1_OWED"
out="$(STUB_RACE_AT='--if-status=open' STUB_RACE_JQ="$ROUTE_G1" STUB_UPDATE_FAIL_AT='--if-status=in_progress' "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a claim the pass could not give back fails the pass"
eq "$(assignee_of g-1)" "deferred-dispatch" "the claim stays"
has "$out" "could not release the claim on g-1" "the failure is reported"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the next pass is clean"
has "$out" "gave back g-1" "it gives the claim back"
eq "$(status_of g-1)" "open" "the bead is open"
eq "$(assignee_of g-1)" "" "and unassigned"
eq "$(meta g-1 gc.routed_to)" "rig/rig.polecat" "with its route"

echo "# until: a pointer another closer records between the listing and the claim keeps the bead, and that pointer"
store "$G1_OWED"
out="$(STUB_RACE_AT='--if-status=open' STUB_RACE_JQ='map(if .id == "g-1" then (.metadata["gc.superseded_by"] = "x-1" | .metadata["gc.superseded_by_store"] = "rig:rig-a") else . end)' "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
eq "$(rehomes)" "0" "the pointed bead never reaches bead-rehome"
eq "$(status_of g-1)/$(assignee_of g-1)" "open/" "it is given back, open and unassigned"
eq "$(meta g-1 gc.superseded_by)" "x-1" "with the other closer's pointer, which the pass neither stamped nor withdraws"
has "$out" "gc.superseded_by=x-1" "the pointer is reported as live work"

echo "# until: a claim an earlier pass left with a pointer its mark does not name keeps that pointer"
store '[
 {"id":"g-1","issue_type":"task","status":"in_progress","assignee":"deferred-dispatch","metadata":{"gc.superseded_by":"x-1","gc.superseded_by_store":"rig:rig-a"},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass is clean"
has "$out" "gave back g-1, which an earlier pass claimed and did not close" "the claim is given back"
hasnt "$out" "withdrawing the successor pointer" "without withdrawing a pointer no mark shows is the pass's own"
eq "$(status_of g-1)/$(assignee_of g-1)" "open/" "open and unassigned"
eq "$(meta g-1 gc.superseded_by)" "x-1" "the other closer's pointer stands"
eq "$(rehomes)" "0" "and the bead is not disposed"
has "$out" "LEFT g-1" "its pointer is reported as live work"

# Another closer's gates pass while the bead is open and unassigned, and its
# stamp is still to come when the pass claims the bead. The real bead-rehome
# runs as both closers: the other one points g-1 at y-1 and is parked just
# before its stamp, then released once the pass has stamped, or once the pass
# is about to stamp.
G1_OWED_Y1='[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"y-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":""}]'
OTHER_AT="$TMP/other-closer-hold"; PASS_AT="$TMP/pass-stamp-hold"
other_closer() { # starts the other closer, parked before its stamp; its pid in OTHER
    rm -f "$OTHER_AT" "$OTHER_AT.release" "$PASS_AT" "$PASS_AT.release"
    real_rehome env BEADS_ACTOR=other-closer STUB_UPDATE_HOLD_AT='gc.superseded_by=y-1' STUB_UPDATE_HOLD="$OTHER_AT" \
        "$HERE/bead-rehome.sh" --origin g-1 --successor y-1 --kind re-homed \
        --origin-store rig:rig-a --successor-store rig:rig-a --note "another closer's ruling" \
        > "$TMP/other-closer.out" 2>&1 &
    OTHER=$!
}
for when in after-the-pass-stamps before-the-pass-stamps; do
    echo "# until: a closer whose gates passed before the claim stamps nothing while the pass holds the bead, released $when"
    store "$G1_OWED_Y1"
    other_closer
    if ! await "$OTHER_AT"; then
        bad "($when) the other closer never reached its stamp (fixture wedged)"
        : > "$OTHER_AT.release"; wait "$OTHER" 2>/dev/null; continue
    fi
    after=""; [ "$when" = before-the-pass-stamps ] || after=1
    real_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" STUB_UPDATE_HOLD_AT='gc.superseded_by=x-1' STUB_UPDATE_HOLD="$PASS_AT" \
        STUB_UPDATE_HOLD_AFTER="$after" "$SUT" reconcile --db "$TMP/rig-a/.beads" > "$TMP/pass.out" 2>&1 &
    pass_pid=$!
    if ! await "$PASS_AT"; then
        bad "($when) the pass never reached its stamp (fixture wedged)"
        : > "$PASS_AT.release"; : > "$OTHER_AT.release"; wait "$pass_pid" "$OTHER" 2>/dev/null; continue
    fi
    eq "$(status_of g-1)/$(assignee_of g-1)" "in_progress/deferred-dispatch" "($when) the pass holds the bead under its claim"
    : > "$OTHER_AT.release"; wait "$OTHER"; orc=$?
    eq "$orc" 4 "($when) the other closer's stamp, judged before the claim, is refused"
    has "$(cat "$TMP/other-closer.out")" "g-1 is no longer open and unassigned" "($when) the other closer says the bead changed after it judged it"
    if [ -n "$after" ]; then
        eq "$(meta g-1 gc.superseded_by)" "x-1" "($when) the pass's pointer stands, untouched by the other closer"
    else
        eq "$(meta g-1 gc.superseded_by)" "<absent>" "($when) nothing the other closer wrote is on the bead for the pass to overwrite"
    fi
    : > "$PASS_AT.release"; wait "$pass_pid"; prc=$?
    out="$(cat "$TMP/pass.out")"
    eq "$prc" 0 "($when) the pass is clean"
    eq "$(status_of g-1)/$(assignee_of g-1)" "closed/" "($when) the pass disposes the bead and releases its claim"
    eq "$(meta g-1 gc.superseded_by)" "x-1" "($when) onto its until target"
    has "$(close_reason g-1)" "folded into x-1" "($when) with a close reason that names the pointer the bead carries"
    has "$out" "disposed g-1" "($when) and reports the disposal"
    eq "$(meta y-1 gc.supersedes)" "<absent>" "($when) the other closer recorded nothing on its successor"
done

echo "# until: a stamp the claim no longer covers writes nothing, and the pass leaves the bead to whoever took it"
store "$G1_OWED"
out="$(real_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" STUB_RACE_AT='gc.superseded_by=x-1' \
    STUB_RACE_JQ='map(if .id == "g-1" then (.status = "in_progress" | .assignee = "rig/rig.polecat-1") else . end)' \
    "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
eq "$rc" 1 "a disposal whose claim was taken from the pass fails the pass"
eq "$(status_of g-1)/$(assignee_of g-1)" "in_progress/rig/rig.polecat-1" "the bead stays with whoever took it"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "with no pointer, since bead-rehome stamps nothing on a bead the claim no longer holds"
has "$out" "g-1 is no longer in progress under deferred-dispatch, so this pass did not give it back" "the pass says it left the bead"

echo "# until: a pass stopped after the real bead-rehome stamped its pointer leaves the claim and the mark, and the next pass withdraws the pointer"
# The gate stub stops the pass where it stands: the real disposer has stamped
# and read back its pointer, and has not closed the bead. With routed=yes, a
# dispatch lands on the bead the moment the pass hands it to the disposer.
cat > "$BIN/finalize-gate-stop.sh" <<'GATE'
#!/usr/bin/env bash
: > "${STUB_GATE_AT:?}"
i=0; while [ ! -e "$STUB_GATE_AT.release" ] && [ "$i" -lt 6000 ]; do sleep 0.05; i=$((i + 1)); done
exit 1
GATE
chmod +x "$BIN/finalize-gate-stop.sh"
UNTIL_LOCKF="$TMP/state/_unscoped/pass.lock"
for routed in no yes; do
    store "$G1_OWED"
    GATE_AT="$TMP/gate-stop-$routed"; rm -f "$GATE_AT" "$GATE_AT.release"
    race='.'; [ "$routed" = no ] || race="$ROUTE_G1"
    # Launched as a simple command, so $! is the pass itself. A SIGKILL runs no
    # EXIT trap, so the pass stages its files under $TMP, which the suite removes.
    TMPDIR="$TMP" STUB_RIGS_JSON="$TMP/rigs-a.json" GC_FINALIZE_GATE_TOOL="$BIN/finalize-gate-stop.sh" STUB_GATE_AT="$GATE_AT" \
        GC_REHOME_TOOL="$BIN/rehome-race.sh" STUB_REHOME_NEXT="$HERE/bead-rehome.sh" STUB_REHOME_RACE_JQ="$race" \
        "$SUT" reconcile --db "$TMP/rig-a/.beads" > /dev/null 2>&1 &
    first=$!
    if await "$GATE_AT"; then
        kill -9 "$first" 2>/dev/null; wait "$first" 2>/dev/null
        : > "$GATE_AT.release"
        i=0; while ! ( exec 8>>"$UNTIL_LOCKF"; flock -n 8 ) 2>/dev/null && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
        eq "$(status_of g-1)/$(assignee_of g-1)" "in_progress/deferred-dispatch" "(routed=$routed) the stopped pass leaves the bead under its claim"
        eq "$(meta g-1 gc.superseded_by)/$(meta g-1 gc.until_disposal)" "x-1/x-1" "(routed=$routed) with the pointer the real disposer stamped and the mark that names it"
        out="$(real_rehome env GC_REHOME_TOOL="$HERE/bead-rehome.sh" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
        eq "$rc" 0 "(routed=$routed) the next pass is clean"
        has "$out" "gave back g-1, which an earlier pass claimed and did not close, withdrawing the successor pointer to x-1 that pass had bead-rehome stamp" \
            "(routed=$routed) it gives the bead back first, withdrawing the pointer its mark names"
        if [ "$routed" = yes ]; then
            eq "$(status_of g-1)/$(assignee_of g-1)" "open/" "the routed bead is open and unassigned, so its pool can claim it"
            eq "$(meta g-1 gc.superseded_by)" "<absent>" "with no pointer"
            has "$out" "LEFT g-1" "and its route is reported as live work"
        else
            eq "$(status_of g-1)" "closed" "the bead is then disposed afresh"
            eq "$(meta g-1 gc.superseded_by)" "x-1" "with a pointer of this pass's own"
            eq "$(meta g-1 gc.until_disposal)" "<absent>" "and no mark"
        fi
    else
        bad "(routed=$routed) the pass to be stopped never reached the finalize gate (fixture wedged)"
        : > "$GATE_AT.release"; wait "$first" 2>/dev/null
    fi
done

# An arm whose `arm` read the bead before the pass claimed it lands while the
# pass holds the bead. The check after the close reopens the bead for it, and a
# pass that cannot make that check leaves the close for the next pass, whose
# dispatch half must not retire the arm before the check reads it.
ARM_G1='map(if .id == "g-1" then (.metadata["gc.dispatch_when_ready"] = "rig/pool" | .metadata["gc.dispatch_when_ready_args"] = "[\"--on\",\"mol-polecat-work\"]") else . end)'
G1_OWED_READY='[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_ready":true,"_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'

echo "# until: an arm that lands while the pass holds the bead outlives a close no pass checked, and fires"
store "$G1_OWED_READY"
rm -f "$TMP/rehomed"
out="$(GC_REHOME_TOOL="$BIN/rehome-race.sh" STUB_REHOME_RACE_JQ="$ARM_G1" STUB_REHOME_TOUCH="$TMP/rehomed" STUB_SHOW_FAIL_WHEN="$TMP/rehomed" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a close the pass could not check fails the pass"
eq "$(status_of g-1)/$(assignee_of g-1)" "closed/deferred-dispatch" "the bead stays closed under the claim"
eq "$(meta g-1 gc.dispatch_when_ready)" "rig/pool" "with the arm that landed while the pass held it"
# The sling leaves the route a real pool sling leaves, which is live work to the
# until half that runs after it.
out="$(STUB_SLING_STAMPS=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the next pass is clean"
has "$out" "REOPENED g-1" "it checks the close, finds the arm, and reopens the bead"
hasnt "$out" "retired arm on closed g-1" "the arm is never retired as one on a closed bead"
reopen_at="$(printf '%s\n' "$out" | grep -n 'REOPENED g-1' | head -1 | cut -d: -f1)"
sling_at="$(printf '%s\n' "$out" | grep -n 'dispatched g-1 -> rig/pool' | head -1 | cut -d: -f1)"
if [ -n "$reopen_at" ] && [ -n "$sling_at" ] && [ "$reopen_at" -lt "$sling_at" ]; then
    ok "the check comes before the dispatch half, which slings the reopened bead in the same pass"
else
    bad "the check comes before the dispatch half, which slings the reopened bead in the same pass (reopen at line '${reopen_at:-none}', sling at line '${sling_at:-none}')"
fi
eq "$(slings)" "1" "the arm fires once"
eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool g-1 --on mol-polecat-work" "with its recorded target and args"
eq "$(meta g-1 gc.superseded_by)" "<absent>" "the disposal is withdrawn"
eq "$(meta g-1 gc.dispatch_when_ready)" "<absent>" "and the proven dispatch clears the arm"
eq "$(status_of g-1)/$(meta g-1 gc.routed_to)" "open/rig/pool" "the bead stays open, routed to the pool its arm named"
has "$out" "LEFT g-1" "and the until half leaves it as live work"

CLOSED_ARMED='[
 {"id":"g-1","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{"gc.superseded_by":"x-1","gc.until_disposal":"x-1","gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true,"_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
echo "# until: while no pass can check a close made under the claim, its arm is kept"
store "$CLOSED_ARMED"
: > "$TMP/show-fails"
out="$(STUB_SHOW_FAIL_WHEN="$TMP/show-fails" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a close the pass still cannot check fails the pass"
has "$out" "KEPT the arm on closed g-1" "the dispatch half keeps its arm for that check"
hasnt "$out" "retired arm on closed g-1" "rather than retiring it"
eq "$(meta g-1 gc.dispatch_when_ready)" "rig/pool" "the arm stands"
eq "$(slings)" "0" "and nothing is slung"
has "$("$SUT" list 2>&1)" "g-1 -> rig/pool [CLOSED under the until consumer's claim" "list says why the arm on it stands"

echo "# until: a close under the claim that the budget leaves keeps its arm, and the pass declares it"
store "$CLOSED_ARMED"
printf '1000\n' > "$TMP/clock-kept"
: > "$TMP/outcome-kept.json"
out="$(STUB_CLOCK="$TMP/clock-kept" DEFERRED_DISPATCH_PASS_BUDGET_SECS=20 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=30 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-kept.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a pass its budget stops exits 0"
has "$out" "KEPT the arm on closed g-1" "the dispatch half keeps the arm on the close it did not reach"
eq "$(meta g-1 gc.dispatch_when_ready)" "rig/pool" "the arm stands"
eq "$(jq -r '[.scopes[]? | "\(.scope): \(.reason)"] | join(",")' "$TMP/outcome-kept.json" 2>/dev/null)" "g-1: claim left for the next pass to finish" \
    "the pass declares the close it left"

echo "# until: an armed bead still in progress under the claim is held for its give-back, not stranded"
store '[
 {"id":"g-1","issue_type":"task","status":"in_progress","assignee":"deferred-dispatch","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(STUB_UPDATE_FAIL_AT='--if-status=in_progress' "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a give-back that fails fails the pass"
has "$out" "HELD g-1 — it is in progress under the until consumer's claim" "the dispatch half holds the arm for the give-back"
hasnt "$out" "STRANDED g-1" "rather than calling it stranded"
eq "$(slings)" "0" "and slings nothing"
has "$("$SUT" list 2>&1)" "g-1 -> rig/pool [HELD by the until consumer's claim" "list shows the claim"

# --- the disposal budget ------------------------------------------------------
# The order's timeout kills a pass wherever it stands, and a killed pass prints
# no summary. So a disposal starts only while a full allowance is left in the
# pass budget. The clock is the test's: each disposal advances it
# STUB_REHOME_SECS.
THREE_OWED='[
 {"id":"u-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"ux-1","dependency_type":"until"}]},
 {"id":"u-2","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"ux-2","dependency_type":"until"}]},
 {"id":"u-3","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"ux-3","dependency_type":"until"}]},
 {"id":"ux-1","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"ux-2","status":"closed","assignee":"","metadata":{},"notes":""},
 {"id":"ux-3","status":"closed","assignee":"","metadata":{},"notes":""}]'
CLOCK="$TMP/clock"
echo "# until: a pass starts no disposal once less than one allowance of its budget is left"
store "$THREE_OWED"
printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" STUB_REHOME_SECS=40 DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a pass its budget stops exits 0 — the bead it left is owed, not failed"
eq "$(rehomes)" "2" "a 100s budget with a 30s allowance starts two 40s disposals"
eq "$(cut -f1 "$REHOME_CALLS" | paste -sd, -)" "u-1,u-2" "in listing order"
has "$out" "pass budget spent" "the pass says its budget stopped it"
has "$out" "until-resolved: 2 disposed, 0 live, 0 held, 0 waiting, 0 blocked, 1 left for the next pass (of 3 until-gated)" "the summary counts the bead it left"
eq "$(status_of u-3)" "open" "the bead it left stays open"
eq "$(meta u-3 gc.superseded_by)" "<absent>" "with no pointer stamped"
: > "$REHOME_CALLS"; printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" STUB_REHOME_SECS=40 DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"
eq "$(cut -f1 "$REHOME_CALLS" | paste -sd, -)" "u-3" "the next pass disposes the bead the last one left"
has "$out" "0 left for the next pass" "and leaves nothing"

echo "# until: with no knob set, the shipped budget and allowance pace the pass"
# 420s and 30s: two 200s disposals start, and the third would begin with 20s left.
store "$THREE_OWED"
printf '1000\n' > "$CLOCK"
out="$( (unset DEFERRED_DISPATCH_PASS_BUDGET_SECS DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS
         STUB_CLOCK="$CLOCK" STUB_REHOME_SECS=200 "$SUT" reconcile) 2>&1)"
eq "$(rehomes)" "2" "the default budget starts two 200s disposals"
has "$out" "1 left for the next pass" "and leaves the third"

echo "# until: a budget spent before the until half begins skips its scan"
store "$THREE_OWED"
printf '1000\n' > "$CLOCK"
export STUB_BD_LOG="$TMP/bd-budget.log"; : > "$STUB_BD_LOG"
out="$(STUB_CLOCK="$CLOCK" DEFERRED_DISPATCH_PASS_BUDGET_SECS=20 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(rehomes)" "0" "and disposes nothing"
has "$out" "before the until half began" "it says the budget was spent before the until half"
eq "$(grep -cx 'list --brief --json --limit 0' "$STUB_BD_LOG")" "0" "and makes no store listing it could not act on"
unset STUB_BD_LOG

echo "# until: a budget spent on what an earlier pass left is declared, and skips the scan"
# Listing what an earlier pass left takes 80s of a 100s budget, so the 30s that
# finishing each bead needs is gone before the first one.
store '[
 {"id":"g-1","issue_type":"task","status":"in_progress","assignee":"deferred-dispatch","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"g-2","issue_type":"task","status":"closed","assignee":"deferred-dispatch","metadata":{"gc.superseded_by":"x-1"},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
printf '1000\n' > "$CLOCK"
: > "$TMP/outcome-recover.json"
export STUB_BD_LOG="$TMP/bd-recover-budget.log"; : > "$STUB_BD_LOG"
out="$(STUB_CLOCK="$CLOCK" STUB_RACE_AT='--assignee=deferred-dispatch' STUB_RACE_JQ='.' STUB_RACE_SECS=80 \
    DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=30 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-recover.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a pass its budget stops before it finishes what an earlier pass left exits 0"
eq "$(status_of g-1)/$(assignee_of g-1)" "in_progress/deferred-dispatch" "the claim it did not reach stays for the next pass"
eq "$(status_of g-2)/$(assignee_of g-2)" "closed/deferred-dispatch" "and so does the close it did not check"
has "$out" "until-resolved: 2 bead(s) an earlier pass left under deferred-dispatch: 0 given back, 0 closes stand, 0 reopened, 2 left for the next pass, 0 failed" "the summary counts both as left for the next pass"
has "$out" "left 2 bead(s) an earlier pass left under deferred-dispatch for the next pass to finish: g-1 g-2" "its output names them"
eq "$(jq -r '.outcome' "$TMP/outcome-recover.json" 2>/dev/null)" "partial" "the pass declares itself partial"
eq "$(jq -r '[.scopes[] | "\(.scope): \(.reason)"] | join(",")' "$TMP/outcome-recover.json" 2>/dev/null)" \
    "g-1: claim left for the next pass to finish,g-2: claim left for the next pass to finish" "naming each bead and what was left on it"
has "$(jq -r '.reason' "$TMP/outcome-recover.json" 2>/dev/null)" "2 bead(s) an earlier pass left under deferred-dispatch, for the next pass to finish" "and giving their count as its reason"
has "$out" "before the until half began — every until-gated bead waits for the next pass" "the pass says the budget ran out before its scan"
eq "$(grep -cx 'list --brief --json --limit 0' "$STUB_BD_LOG")" "0" "and makes no store listing it could not act on"
unset STUB_BD_LOG
printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the next pass is clean"
has "$out" "gave back g-1" "it gives back the claim"
has "$out" "the close an earlier pass made under deferred-dispatch stands" "and checks the close"

echo "# until: a zero budget is unpaced, and a dry run spends no budget"
store "$THREE_OWED"
printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" STUB_REHOME_SECS=1000 DEFERRED_DISPATCH_PASS_BUDGET_SECS=0 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"
eq "$(rehomes)" "3" "a zero budget disposes every owed bead however long each disposal takes"
store "$THREE_OWED"
printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" DEFERRED_DISPATCH_PASS_BUDGET_SECS=20 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=30 "$SUT" reconcile --dry-run 2>&1)"
eq "$(printf '%s\n' "$out" | grep -c 'DRY-RUN would dispose u-')" "3" "a dry run lists every bead a pass would dispose, whatever the budget"
hasnt "$out" "pass budget spent" "and spends none of it"
eq "$(rehomes)" "0" "without disposing"

# --- the store bead-rehome is told -------------------------------------------
# A pinned pass reads one store whatever an id's prefix says, and bead-rehome
# left to itself derives each id's store from its prefix, so the two could land
# on different stores. The pass names its store, as the rig that holds it.
mkdir -p "$TMP/rig-a/.beads" "$TMP/stray/.beads"
printf '{"rigs":[{"name":"other","path":"%s"},{"name":"rig-a","path":"%s"}]}\n' "$TMP/elsewhere" "$TMP/rig-a" > "$TMP/rigs.json"
ONE_OWED='[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
echo "# until: a pinned pass names its store to bead-rehome"
store "$ONE_OWED"
out="$(STUB_RIGS_JSON="$TMP/rigs.json" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
eq "$rc" 0 "a pass pinned with --db is a clean pass"
eq "$(rehome_stores 1)" "rig:rig-a|rig:rig-a" "bead-rehome is told the pinned store for both beads, not left to derive it"
store "$ONE_OWED"
(STUB_RIGS_JSON="$TMP/rigs.json" GC_RIG_ROOT="$TMP/rig-a" "$SUT" reconcile >/dev/null 2>&1)
eq "$(rehome_stores 1)" "rig:rig-a|rig:rig-a" "GC_RIG_ROOT, the order's pin, names the store the same way"
echo "# until: a pinned store no rig holds disposes nothing"
store "$ONE_OWED"
out="$(STUB_RIGS_JSON="$TMP/rigs.json" "$SUT" reconcile --db "$TMP/stray/.beads" 2>&1)"; rc=$?
eq "$rc" 1 "a pinned store bead-rehome cannot be pointed at fails the pass"
eq "$(rehomes)" "0" "and nothing is handed to bead-rehome"
has "$out" "no rig in 'gc rig list' holds the store" "the reason is reported"
echo "# until: an unpinned pass leaves the store to bead-rehome"
store "$ONE_OWED"
"$SUT" reconcile >/dev/null 2>&1
eq "$(rehome_stores 1)" "-|-" "unpinned, bead-rehome derives each store from the id prefix, as an unpinned read routes"
echo "# until: the roster is read once a pass"
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"g-2","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
: > "$TMP/rig.log"
(STUB_RIG_LOG="$TMP/rig.log" STUB_RIGS_JSON="$TMP/rigs.json" "$SUT" reconcile --db "$TMP/rig-a/.beads" >/dev/null 2>&1)
eq "$(rehomes)" "2" "both owed beads are disposed"
eq "$(wc -l < "$TMP/rig.log" | tr -d ' ')" "1" "with one roster read for the pass"

# --- the halves are independent -----------------------------------------------
echo "# until: a dispatch half that cannot read its armed set still lets the until half run"
store "$ONE_OWED"
out="$(STUB_BD_ARMED_FAIL=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "the pass still fails, because the dispatch half could not read its set"
has "$out" "could not enumerate armed beads" "and says so"
eq "$(rehomes)" "1" "but the until half runs and disposes its owed bead"
has "$out" "until-resolved: 1 disposed" "and prints its own summary"

echo "# until: the decision costs no jq process per candidate"
# The jq runs a pass makes are counted for one candidate and for six: two
# waiting on an open target, two held by an open blocker, two owed but carrying
# live work on their rows. None of these needs a fresh read, so every jq run
# left is the fixed cost of the reads.
store '[
 {"id":"w-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"o-1","dependency_type":"until"}]},
 {"id":"o-1","status":"open","assignee":"","metadata":{},"notes":""}]'
: > "$TMP/jq-one.log"
(PATH="$TMP/jqbin:$PATH" STUB_JQ_LOG="$TMP/jq-one.log" "$SUT" reconcile >/dev/null 2>&1)
store '[
 {"id":"w-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"o-1","dependency_type":"until"}]},
 {"id":"w-2","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"o-1","dependency_type":"until"}]},
 {"id":"b-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"c-1","dependency_type":"until"},{"id":"o-1","dependency_type":"blocks"}]},
 {"id":"b-2","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"c-1","dependency_type":"until"},{"id":"o-1","dependency_type":"blocks"}]},
 {"id":"l-1","issue_type":"task","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/pool"},"notes":"","_deps":[{"id":"c-1","dependency_type":"until"}]},
 {"id":"l-2","issue_type":"task","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/pool"},"notes":"","_deps":[{"id":"c-1","dependency_type":"until"}]},
 {"id":"o-1","status":"open","assignee":"","metadata":{},"notes":""},
 {"id":"c-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
: > "$TMP/jq-six.log"
out="$(PATH="$TMP/jqbin:$PATH" STUB_JQ_LOG="$TMP/jq-six.log" "$SUT" reconcile 2>&1)"
has "$out" "until-resolved: 0 disposed, 2 live, 0 held, 2 waiting, 2 blocked, 0 left for the next pass (of 6 until-gated)" "six candidates are decided"
eq "$(wc -l < "$TMP/jq-six.log" | tr -d ' ')" "$(wc -l < "$TMP/jq-one.log" | tr -d ' ')" "with as many jq runs as one candidate takes"

# --- the false-empty-queue guard ---------------------------------------------
# This is the failure this script must not have. A dispatcher that cannot read
# its queue and prints "0 dispatched" is indistinguishable from one with nothing
# owed — which is exactly how a pending dispatch went missing before this
# existed. It must exit non-zero and say it could not see.
echo "# unreadable queue is not an empty queue"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$(STUB_BD_LIST_FAIL=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "an unreadable listing exits non-zero"
hasnt "$out" "0 dispatched, 0 retired" "an unreadable listing does NOT print a healthy-looking summary"
has "$out" "could not enumerate" "an unreadable listing says so"
eq "$(slings)" "0" "an unreadable listing slings nothing"

out="$(STUB_BD_LIST_FAIL=1 "$SUT" list 2>&1)"; rc=$?
eq "$rc" 1 "list also fails loudly on an unreadable store"
out="$(STUB_BD_LIST_FAIL=1 "$SUT" list --json 2>&1)"; rc=$?
eq "$rc" 1 "list --json also fails loudly on an unreadable store"
has "$out" "could not enumerate" "and says so"

# --- the quiet path still passes ---------------------------------------------
# Tightening the guard above must not strand the ordinary no-work case.
echo "# quiet path"
store '[{"id":"b-9","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a store with nothing armed still passes"
has "$out" "0 dispatched" "and reports an honest empty pass"
eq "$(slings)" "0" "and slings nothing"
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list on a store with nothing armed passes"
has "$out" "no pending dispatches" "list says the queue is empty"

# --- list -------------------------------------------------------------------
echo "# list"
store '[
 {"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_reason":"needs b-0"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""},
 {"id":"b-2","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/other"},"notes":"","_ready":true},
 {"id":"b-3","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":"","_ready":false},
 {"id":"b-6","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","merge_result":"pull_request"},"notes":"","_ready":true},
 {"id":"b-7","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_fail_count":"3"},"notes":"","_ready":true},
 {"id":"b-4","status":"open","assignee":"","metadata":{},"notes":"","_ready":true}]'
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list exits 0"
has "$out" "b-1 -> rig/pool [HELD by b-0] — needs b-0" "list shows a held arm with its blocker and its reason"
has "$out" "b-2 -> rig/other [DISPATCHABLE NOW]" "list shows a dispatchable arm"
has "$out" "b-3 -> rig/pool [CLOSED" "list shows a closed arm"
has "$out" "b-6 -> rig/pool [DELIVERED — merge_result=pull_request" "list flags an already-delivered arm (will retire, not sling)"
has "$out" "b-7 -> rig/pool [CAPPED — 3 sling failures" "list flags a capped arm as needing a person"
hasnt "$out" "b-4" "list shows only armed beads"

# --json prints the armed beads as bd lists them, which says nothing about what
# holds them, so it reads nothing else: no hold walk, and no failure of one.
echo "# list --json makes one read and no hold walk"
export STUB_BD_LOG="$TMP/bd-json.log"; : > "$STUB_BD_LOG"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{'"$A1"'},"notes":"","_ready":false,"_deps":[{"id":"epic","dependency_type":"parent-child"}]},'"$PARKED"']'
out="$("$SUT" list --json 2>/dev/null)"; rc=$?
eq "$rc" 0 "list --json exits 0"
eq "$(printf '%s' "$out" | jq -r '[.[].id] | join(",")')" "b-1" "list --json prints the armed beads as bd lists them"
eq "$(wc -l < "$STUB_BD_LOG" | tr -d ' ')" "1" "list --json makes one read"
eq "$(grep -c -e '--id' "$STUB_BD_LOG")" "0" "and walks no hold"
out="$(STUB_BD_LIST_ID_FAIL=1 "$SUT" list --json 2>&1)"; rc=$?
eq "$rc" 0 "a hold walk's read failing does not fail list --json"
unset STUB_BD_LOG

# A held bead and a gated bead are both "not ready", and conflating them is
# what hides a dead arm: the gated one dispatches when its blocker closes, the
# held one never dispatches at all.
store '[
 {"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""},
 {"id":"b-5","status":"blocked","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":"","_ready":false}]'
out="$("$SUT" list 2>&1)"
has "$out" "b-5 -> rig/pool [STRANDED — status=blocked is never --ready]" "list names a stranded arm"
has "$out" "b-1 -> rig/pool [HELD by b-0]" "an open arm is held by its blocker, not stranded"

echo "# reconcile names a stranded arm every pass"
# The arm outlives every session that could remember it, so a silent `waiting`
# count is how it stays lost. Reported on stderr and counted in the summary.
store '[{"id":"b-5","status":"blocked","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "reconcile exits 0 with a stranded arm (nothing failed)"
eq "$(slings)" "0" "a stranded arm is never slung"
has "$out" "STRANDED b-5" "reconcile names the stranded bead"
has "$out" "status=blocked" "and the status that strands it"
has "$out" "1 stranded" "the summary counts it apart from waiting"
eq "$(meta b-5 gc.dispatch_when_ready)" "rig/pool" "the record is kept, not retired — the hold may clear"

store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false,"_deps":[{"id":"b-0","dependency_type":"blocks"}]},
 {"id":"b-0","status":"open","assignee":"","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
has "$out" "1 held, 0 stranded" "an open gated arm counts as held, not stranded"
hasnt "$out" "STRANDED" "and is not reported as stranded"

# --- disarm ------------------------------------------------------------------
echo "# disarm"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_armed_by":"x","gc.dispatch_when_ready_armed_at":"t","gc.dispatch_when_ready_reason":"r","gc.dispatch_when_ready_slung":"t2"},"notes":"keep me","_ready":false}]'
out="$("$SUT" disarm b-1 --reason "superseded" 2>&1)"; rc=$?
eq "$rc" 0 "disarm exits 0"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "disarm clears the target"
eq "$(meta b-1 gc.dispatch_when_ready_args)" "<absent>" "disarm clears the args"
eq "$(meta b-1 gc.dispatch_when_ready_armed_by)" "<absent>" "disarm clears the actor"
eq "$(meta b-1 gc.dispatch_when_ready_armed_at)" "<absent>" "disarm clears the timestamp"
eq "$(meta b-1 gc.dispatch_when_ready_reason)" "<absent>" "disarm clears the reason"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "disarm clears the slung marker"
has "$(notes b-1)" "keep me" "disarm appends to notes rather than replacing"
has "$(notes b-1)" "superseded" "disarm records why"
store '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false}]'
"$SUT" disarm n-1 >/dev/null 2>&1
eq "$(meta n-1 gc.notify_when_ready)" "<absent>" "disarm clears a notice owed too"
store '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false}]'
"$SUT" disarm n-1 >/dev/null 2>&1
eq "$(meta n-1 gc.dispatch_when_ready)" "<absent>" "disarm on a bead with an arm and a notice clears the arm"
eq "$(meta n-1 gc.notify_when_ready)" "<absent>" "and the notice, in the same verb"

# A pass retires an arm through the same write, which leaves a notice owed on
# the bead: only the notice's own send or retire, or the disarm verb, clears it.
echo "# a pass that retires an arm leaves the bead's notice owed"
store '[{"id":"b-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","merge_result":"pull_request","gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false},
        {"id":"b-2","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_slung":"slung@2026-01-01T00:00:00Z","gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a pass that retires arms on beads with notices owed exits 0"
eq "$(meta b-1 gc.dispatch_when_ready)" "<absent>" "the pass retires an arm whose work another path delivered"
eq "$(meta b-1 gc.notify_when_ready)" "gc-toolkit.mechanik" "and leaves the notice owed on the same bead"
eq "$(meta b-2 gc.dispatch_when_ready)" "<absent>" "the pass retires an arm whose sling it proved"
eq "$(meta b-2 gc.notify_when_ready)" "gc-toolkit.mechanik" "and leaves that bead's notice owed too"
has "$out" "notices: 0 sent, 0 retired, 2 waiting" "the notices still wait on bd's readiness"

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
eq "$(meta n-2 gc.notify_when_ready)" "gc-toolkit.mechanik" "it records the notice for the reconcile pass"
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
# The recovery: the first mail is still in the agent's mailbox, unread, so the
# dedup key suppresses the resend and its turn request with it. The pass
# requests the turn directly.
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the next pass recovers the notice"
eq "$(mails)" "2" "it sends the mail again"
eq "$(mailbox)" "1" "and the dedup key keeps a second copy out of the mailbox"
eq "$(nudges)" "2" "so it requests the turn with gc session nudge"
has "$(tail -n 1 "$STUB_NUDGE_LOG")" "gc-toolkit.mechanik Ready for you: n-6 (Edit city.toml)" "naming the agent and the bead"
eq "$(meta n-6 gc.notify_when_ready)" "<absent>" "and the notice retires once the turn is requested"
has "$(notes n-6)" "notice sent to gc-toolkit.mechanik" "with a note that the agent was told"
has "$out" "the notice mailed about n-6 earlier is still in its mailbox" "the pass log says why it nudged"
store '[{"id":"n-7","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
out="$(STUB_BD_LIST_FAIL_KEY=gc.notify_when_ready "$SUT" notify n-7 --agent gc-toolkit.mechanik 2>&1)"; rc=$?
eq "$rc" 0 "a readiness read that fails still exits 0"
eq "$(mails)" "0" "sending nothing it could not prove ready"
eq "$(meta n-7 gc.notify_when_ready)" "gc-toolkit.mechanik" "and leaving the record for the pass"
has "$out" "could not read whether bd reports it ready" "notify says so"

echo "# reconcile sends a notice once bd reports its bead ready"
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
export STUB_BD_LOG="$TMP/bd-notice.log"; : > "$STUB_BD_LOG"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a pass with notices owed exits 0"
eq "$(notice_list_reads)" "2" "the notices cost two list reads, the notices owed and those bd reports ready, however many there are"
eq "$(grep -c '^show' "$STUB_BD_LOG")" "5" "and one per-bead read for each notice it retires, which re-checks the record before clearing it"
eq "$(grep -c -e '^show n-2 ' -e '^show n-8 ' "$STUB_BD_LOG")" "0" "and none for a notice that waits"
unset STUB_BD_LOG
eq "$(mails)" "1" "exactly the notice whose bead bd reports ready is sent"
has "$(cat "$STUB_MAIL_LOG")" "send gc-toolkit.mechanik --notify --dedup ready-notice:n-1" "to its agent, deduped on its bead"
has "$(cat "$STUB_MAIL_LOG")" "n-1 (Edit city.toml) is assigned to you" "naming the bead and its title"
eq "$(meta n-1 gc.notify_when_ready)" "<absent>" "a sent notice retires"
has "$(notes n-1)" "notice sent to gc-toolkit.mechanik" "with a note that the agent was told"
eq "$(meta n-2 gc.notify_when_ready)" "gc-toolkit.mechanik" "a notice whose bead still waits stays armed"
eq "$(meta n-8 gc.notify_when_ready)" "gc-toolkit.mechanik" "and so does one at a status bd never reports ready"
eq "$(meta n-3 gc.notify_when_ready)" "<absent>" "a closed bead's notice retires unsent"
eq "$(meta n-4 gc.notify_when_ready)" "<absent>" "a claimed bead's notice retires unsent"
eq "$(meta n-5 gc.notify_when_ready)" "<absent>" "a reassigned bead's notice retires unsent"
eq "$(meta n-6 gc.notify_when_ready)" "<absent>" "an unassigned bead's notice retires unsent"
has "$(notes n-5)" "no longer assigned to gc-toolkit.mechanik (its assignee is gc-toolkit/gc-toolkit.witness)" "the note says why"
has "$out" "notices: 1 sent, 4 retired, 2 waiting, 0 left for the next pass, 0 failed (of 7)" "the pass counts its notices"
eq "$(slings)" "0" "a notice slings nothing"
# The wait lifts: the next pass sends the notice it held.
jq -c 'map(if .id == "n-2" then ._ready = true else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
: > "$STUB_MAIL_LOG"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$(mails)" "1" "once bd reports the waiting bead ready, the next pass sends its notice"
has "$(cat "$STUB_MAIL_LOG")" "Ready for you: n-2" "naming that bead"
eq "$(meta n-2 gc.notify_when_ready)" "<absent>" "and retires it"

echo "# a notice whose send fails is nudged, and one whose nudge fails too stays armed and fails the pass, and the slings still run"
SEND_FAILS='[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true},
        {"id":"b-2","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
store "$SEND_FAILS"
out="$(STUB_MAIL_RC=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a send that fails, followed by a nudge that requests the turn, passes"
eq "$(nudges)" "1" "the nudge requests the turn"
eq "$(meta n-1 gc.notify_when_ready)" "<absent>" "and the notice retires"
has "$out" "requested gc-toolkit.mechanik's turn for n-1 with gc session nudge: gc mail send could not mail gc-toolkit.mechanik about n-1 (gc mail send: simulated send failure)" "the pass log says the mail failed and the nudge requested the turn"
store "$SEND_FAILS"
out="$(STUB_MAIL_RC=1 STUB_NUDGE_RC=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a notice that gets no turn requested either way fails the pass"
eq "$(meta n-1 gc.notify_when_ready)" "gc-toolkit.mechanik" "and stays armed for the next pass"
has "$out" "could not request gc-toolkit.mechanik's turn for n-1: gc mail send could not mail gc-toolkit.mechanik about n-1 (gc mail send: simulated send failure), and gc session nudge failed: gc session nudge: simulated nudge failure" "one line names both causes"
has "$out" "could not notify gc-toolkit.mechanik that n-1 is ready" "the pass names it"
eq "$(slings)" "1" "the armed sling still runs"

echo "# a pass whose notice gets no turn requested fails, and the next pass recovers it"
store '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true},
        {"id":"b-2","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$(STUB_MAIL_NUDGE_FAILS=1 STUB_NUDGE_RC=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a notice whose mail was saved but got no turn requested fails the pass"
eq "$(meta n-1 gc.notify_when_ready)" "gc-toolkit.mechanik" "and stays armed"
eq "$(mailbox)" "1" "its mail is in the agent's mailbox"
has "$out" "nudge failed: simulated nudge-store failure" "the pass log keeps the mail's diagnostic"
has "$out" "could not request gc-toolkit.mechanik's turn for n-1" "and says the turn was not requested"
has "$out" "1 failed (of 1)" "the pass counts the notice failed"
eq "$(slings)" "1" "the armed sling still runs"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the next pass recovers it, though the first mail still sits unread"
eq "$(mailbox)" "1" "adding no second copy to the mailbox"
eq "$(nudges)" "2" "and requesting the turn with gc session nudge"
eq "$(meta n-1 gc.notify_when_ready)" "<absent>" "the notice retires"
has "$out" "notices: 1 sent" "and the pass counts it sent"

store '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true},
        {"id":"b-2","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
out="$(STUB_BD_LIST_FAIL_KEY=gc.notify_when_ready "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "an unreadable notice listing fails the pass, not reading as no notices owed"
has "$out" "could not enumerate the notices owed" "and says so"
eq "$(slings)" "1" "the armed sling still runs"
eq "$(mails)" "0" "and no notice is sent from a listing that was never read"

echo "# a dry run of the notices sends and retires nothing"
store "$NOTICES"
out="$("$SUT" reconcile --dry-run 2>&1)"; rc=$?
eq "$(mails)" "0" "a dry run sends no notice"
has "$out" "DRY-RUN would notify gc-toolkit.mechanik that n-1 is ready" "it lists the notice a pass would send"
has "$out" "DRY-RUN would retire the notice on n-3" "and the notice it would retire"
eq "$(meta n-1 gc.notify_when_ready)" "gc-toolkit.mechanik" "the ready notice stays armed"
eq "$(meta n-3 gc.notify_when_ready)" "gc-toolkit.mechanik" "and the closed bead's too"

echo "# list shows the notices owed"
store "$NOTICES"
out="$("$SUT" list 2>&1)"; rc=$?
eq "$rc" 0 "list exits 0 with notices owed"
has "$out" "n-1 -> notice to gc-toolkit.mechanik [READY — the next pass notifies gc-toolkit.mechanik]" "list shows a notice the next pass sends"
has "$out" "n-2 -> notice to gc-toolkit.mechanik [WAITING — bd does not report it ready yet]" "and one that waits on bd"
has "$out" "n-8 -> notice to gc-toolkit.mechanik [WAITING — status=deferred, which bd never reports ready]" "and one at a status bd never reports ready"
has "$out" "n-3 -> notice to gc-toolkit.mechanik [CLOSED" "and a closed bead's"
has "$out" "n-4 -> notice to gc-toolkit.mechanik [CLAIMED" "and a claimed bead's"
has "$out" "n-5 -> notice to gc-toolkit.mechanik [MOOT — no longer assigned to gc-toolkit.mechanik" "and a reassigned bead's"
hasnt "$out" "no pending dispatches" "a store with notices owed is not an empty queue"
out="$(STUB_BD_LIST_FAIL_KEY=gc.notify_when_ready "$SUT" list 2>&1)"; rc=$?
eq "$rc" 1 "list fails loudly when the notices cannot be read"

# jq decodes an escaped LF or unit separator in a string and prints it raw, so
# a title or a notice value that spells a second row would add a row the pass
# trusts: here one that notifies the witness about n-9, ready, and then retires
# n-9's notice to mechanik.
echo "# a title or a notice value cannot forge a notice row"
FORGED='[
 {"id":"n-1","title":"Edit\nn-9\u001fopen\u001fgc-toolkit/gc-toolkit.witness\u001fgc-toolkit/gc-toolkit.witness\u001f1\u001fforged","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false},
 {"id":"n-2","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik\nn-9\u001fclosed\u001fgc-toolkit.mechanik\u001fgc-toolkit.mechanik\u001f0\u001fforged"},"notes":"","_ready":false},
 {"id":"n-9","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false}]'
store "$FORGED"
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a pass over strings that spell rows exits 0"
eq "$(mails)" "0" "a title that spells a ready row sends no notice"
eq "$(nudges)" "0" "and requests no turn"
eq "$(meta n-9 gc.notify_when_ready)" "gc-toolkit.mechanik" "and no string retires another bead's notice"
hasnt "$(notes n-9)" "notice record cleared" "so n-9's notes record no retire"
has "$out" "(of 3)" "the pass reads one row per bead"
hasnt "$out" "gc-toolkit/gc-toolkit.witness" "and no row names the agent a title spelled"
store "$FORGED"
out="$("$SUT" list 2>&1)"; rc=$?
eq "$(printf '%s\n' "$out" | grep -c -F -e '-> notice to')" "3" "list shows one notice per bead"
has "$out" "n-1 -> notice to gc-toolkit.mechanik [WAITING" "with each bead's own agent"
hasnt "$out" "gc-toolkit/gc-toolkit.witness" "and none a title spelled"

# notify takes no pass lock, so it can record a notice for a bead's new
# assignee after a pass listed the bead's old one. Every retire re-reads the
# bead and clears the record only while it still names the agent the listing
# named, and an unowed retire also needs the fresh read to show the notice
# unowed. The listings here answer from the view the pass started from.
echo "# a retire leaves a notice recorded since the listing it acted on"
store '[
 {"id":"n-1","status":"open","assignee":"gc-toolkit/gc-toolkit.witness","metadata":{"gc.notify_when_ready":"gc-toolkit/gc-toolkit.witness"},"notes":"","_ready":false},
 {"id":"n-2","status":"open","assignee":"gc-toolkit/gc-toolkit.witness","metadata":{"gc.notify_when_ready":"gc-toolkit/gc-toolkit.witness"},"notes":"","_ready":false},
 {"id":"n-3","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false},
 {"id":"n-4","status":"closed","assignee":"gc-toolkit/gc-toolkit.witness","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":""}]'
printf '%s' '[
 {"id":"n-1","status":"open","assignee":"gc-toolkit/gc-toolkit.witness","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false},
 {"id":"n-2","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true},
 {"id":"n-3","status":"open","assignee":"gc-toolkit/gc-toolkit.witness","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false},
 {"id":"n-4","status":"open","assignee":"gc-toolkit/gc-toolkit.witness","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":false}]' > "$TMP/listed.json"
out="$(STUB_LIST_STORE="$TMP/listed.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a pass whose listing the store has moved past exits 0"
eq "$(meta n-1 gc.notify_when_ready)" "gc-toolkit/gc-toolkit.witness" "a moot notice whose record now names the new assignee is left for that assignee"
has "$out" "left the notice on n-1: its record now names gc-toolkit/gc-toolkit.witness" "and the pass log says why"
hasnt "$(notes n-1)" "notice record cleared" "with no retire recorded on the bead"
eq "$(mails)" "1" "a notice the listing shows ready is sent to the agent it names"
has "$(cat "$STUB_MAIL_LOG")" "send gc-toolkit.mechanik --notify --dedup ready-notice:n-2" "that is, to the old assignee"
eq "$(meta n-2 gc.notify_when_ready)" "gc-toolkit/gc-toolkit.witness" "and the notice recorded for the new assignee meanwhile stays"
has "$out" "notified gc-toolkit.mechanik that n-2 is ready, and left the notice on n-2: its record now names gc-toolkit/gc-toolkit.witness" "the log says the send went out and the new notice stays"
eq "$(meta n-3 gc.notify_when_ready)" "gc-toolkit.mechanik" "a notice the listing read as moot but the store shows owed again stays"
has "$out" "left the notice on n-3: a fresh read shows the notice to gc-toolkit.mechanik owed again" "and the log says so"
eq "$(meta n-4 gc.notify_when_ready)" "<absent>" "a notice still unowed on the fresh read retires"
has "$(notes n-4)" "the bead closed, so no notice is owed" "recording the reason the fresh read gives"
has "$out" "notices: 1 sent, 1 retired, 2 waiting, 0 left for the next pass, 0 failed (of 4)" "the pass counts a notice it left as waiting"

# notify's own retire after the mail re-reads the bead the same way. The write
# lands while the mail goes out: the bead is reassigned, and notify records the
# new assignee's notice.
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
# rig-scoped pass that does not pin --db reads whatever rig gc resolves.
echo "# store pinning"
export STUB_BD_LOG="$TMP/bd.log"
store '[{"id":"p-1","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool"},"notes":""}]'

: > "$STUB_BD_LOG"
(GC_RIG_ROOT="$TMP/rigroot" "$SUT" reconcile >/dev/null 2>&1)
has "$(cat "$STUB_BD_LOG")" "--db $TMP/rigroot/.beads" "GC_RIG_ROOT pins the reads to that rig's store"

: > "$STUB_BD_LOG"
("$SUT" reconcile >/dev/null 2>&1)
hasnt "$(cat "$STUB_BD_LOG")" "--db" "with no GC_RIG_ROOT and no --db, nothing is pinned"

: > "$STUB_BD_LOG"
(GC_RIG_ROOT="$TMP/rigroot" "$SUT" reconcile --db "$TMP/explicit/.beads" >/dev/null 2>&1)
has "$(cat "$STUB_BD_LOG")" "--db $TMP/explicit/.beads" "an explicit --db overrides GC_RIG_ROOT"
hasnt "$(cat "$STUB_BD_LOG")" "--db $TMP/rigroot/.beads" "and the rig-root default is not also passed"
unset STUB_BD_LOG

# --- the pass lock: one pass per rig at a time --------------------------------
# Two passes over one store sling the same ready bead twice: two input convoys
# for one work bead. The controller's tracking gate can be closed under a pass
# still running, so the pass holds its own lock. The first pass here is caught
# inside its sling, with b-1's unproven marker already stamped. A second pass
# that got past the lock would list the store, read that marker as a dead
# attempt, and sling b-1 again: two slings where the lock allows one.
echo "# a pass that overlaps one in flight skips without reading or slinging"
LOCK_PROVEN=0
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
export STUB_BD_LOG="$TMP/bd-lock.log"; : > "$STUB_BD_LOG"
HOLD="$TMP/hold"; rm -f "$HOLD".*
# Launched as a simple command, so $! is the pass itself.
STUB_SLING_HOLD="$HOLD" "$SUT" reconcile > "$TMP/first-pass.out" 2>&1 &
first=$!
if await "$HOLD.started"; then
    reads_before="$(wc -l < "$STUB_BD_LOG" | tr -d ' ')"
    out="$(GC_ORDER_OUTCOME_FILE="$TMP/outcome-skip.json" "$SUT" reconcile 2>&1)"; rc=$?
    eq "$rc" 0 "a pass that overlaps one in flight exits 0 — the cadence is firing, not failing"
    has "$out" "already in flight" "and says a pass is in flight"
    eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1" "in one line"
    eq "$(wc -l < "$STUB_BD_LOG" | tr -d ' ')" "$reads_before" "the skipped pass reads nothing from the store"
    eq "$(jq -r '.outcome' "$TMP/outcome-skip.json" 2>/dev/null)" "skipped" "and declares the run skipped to the controller"
    : > "$HOLD.release"
    wait "$first"; rc=$?
    eq "$rc" 0 "the pass holding the lock finishes clean"
    n="$(slings)"
    eq "$n" "1" "two overlapping passes make exactly one sling"
    [ "$n" = 1 ] && LOCK_PROVEN=1
    has "$(cat "$TMP/first-pass.out")" "1 dispatched" "the pass holding the lock completes its dispatch"
else
    bad "the first pass never reached its sling (fixture wedged)"
    : > "$HOLD.release"; wait "$first" 2>/dev/null
fi
unset STUB_BD_LOG

# The lock below is held by the test, standing in for a pass of rig-a.
echo "# the lock is per rig, a dry run takes none, and a stalled holder fails the pass"
mkdir -p "$TMP/state/rig-a"
( exec 9>>"$TMP/state/rig-a/pass.lock"
  flock -n 9 || exit 1
  : > "$TMP/rig-a-held"
  i=0
  while [ ! -e "$TMP/rig-a-release" ] && [ "$i" -lt 6000 ]; do sleep 0.05; i=$((i + 1)); done ) &
holder=$!
if await "$TMP/rig-a-held"; then
    printf '%s %s\n' "$holder" "$(date -u +%s)" > "$TMP/state/rig-a/pass.holder"
    store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
    out="$(GC_RIG=rig-a "$SUT" reconcile 2>&1)"; rc=$?
    eq "$rc" 0 "a pass of the rig whose lock is held exits 0"
    has "$out" "already in flight (pid $holder" "naming the holder"
    eq "$(slings)" "0" "and slings nothing"
    out="$(GC_RIG=rig-a "$SUT" reconcile --dry-run 2>&1)"; rc=$?
    eq "$rc" 0 "a dry run while a pass holds the lock exits 0"
    has "$out" "DRY-RUN would sling: gc sling --rig rig-a rig/pool b-1" "and still lists what a pass would sling"
    eq "$(slings)" "0" "without slinging"
    printf '%s %s\n' "$holder" 1 > "$TMP/state/rig-a/pass.holder"
    out="$(GC_RIG=rig-a DEFERRED_DISPATCH_LOCK_STALL_SECS=60 "$SUT" reconcile 2>&1)"; rc=$?
    eq "$rc" 1 "a holder past the stall bound fails the pass instead of skipping it"
    has "$out" "nothing is dispatching" "saying the cadence has stopped"
    eq "$(slings)" "0" "and slings nothing"
    out="$(GC_RIG=rig-b "$SUT" reconcile 2>&1)"; rc=$?
    eq "$rc" 0 "a pass of another rig is not held by this rig's lock"
    eq "$(head -1 "$STUB_SLING_LOG")" "--rig rig-b rig/pool b-1" "and makes its sling"
else
    bad "the rig-a lock fixture never took the lock"
fi
: > "$TMP/rig-a-release"; wait "$holder" 2>/dev/null

echo "# a lock that cannot be taken refuses the pass before it reads the store"
# Both ways the lock goes missing: a lock file the pass cannot create, and no
# flock on PATH at all. Nothing else carries single-flight, so a pass that ran
# anyway would be the second slinger the lock exists to prevent.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
mkdir -p "$TMP/state-nolock/_unscoped/pass.lock"
export STUB_BD_LOG="$TMP/bd-nolock.log"; : > "$STUB_BD_LOG"
out="$(DEFERRED_DISPATCH_STATE_DIR="$TMP/state-nolock" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a lock file the pass cannot create fails the pass"
has "$out" "single-flight UNGUARDED" "naming the guarantee it could not take"
eq "$(wc -l < "$STUB_BD_LOG" | tr -d ' ')" "0" "before any read of the store"
eq "$(slings)" "0" "and slings nothing"
# Permissions cannot hide flock from `command -v`, which skips a non-executable
# hit and keeps searching PATH, so this PATH carries the stubs and every tool the
# pass reaches for before its lock, and no flock.
NOFLOCK="$TMP/noflock"; mkdir -p "$NOFLOCK"
for c in bash dirname tr cat jq mkdir mktemp rm wc; do
    p="$(PATH="${PATH#"$BIN":}" command -v "$c" 2>/dev/null)" && ln -sf "$p" "$NOFLOCK/$c"
done
out="$(PATH="$BIN:$NOFLOCK" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a pass with no flock on PATH fails"
has "$out" "flock not found" "naming the missing tool"
eq "$(wc -l < "$STUB_BD_LOG" | tr -d ' ')" "0" "before any read of the store"
eq "$(slings)" "0" "and slings nothing"
unset STUB_BD_LOG

# No gc or escalate.sh call is handed the lock's descriptor. A process a gc call
# starts can outlive the pass, and one that kept fd 9 would hold the lock against
# every later pass, with nothing dispatching on the rig until someone killed it.
echo "# every gc and escalate.sh call a pass makes runs without the lock's descriptor"
store '[
 {"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true},
 {"id":"b-cap","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_fail_count":"3"},"notes":"","_ready":true},
 {"id":"b-done","status":"closed","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":false}]'
FD9="$TMP/fd9.log"; : > "$FD9"
out="$(STUB_FD9_LOG="$FD9" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass completes"
eq "$(slings)" "1" "it slings the ready bead"
eq "$(escalations)" "1" "it escalates the capped bead"
has "$out" "retired arm on closed b-done" "it retires the closed bead's arm"
for call in "gc bd" "gc sling" "escalate"; do
    n="$(grep -c -F "$call fd9=" "$FD9")"
    if [ "$n" -gt 0 ]; then ok "the pass made $n '$call' call(s)"; else bad "the pass made no '$call' call, so nothing about it was proven"; fi
done
leaked="$(grep -F 'fd9=open' "$FD9" | grep -v -F 'date fd9=' || true)"
eq "$leaked" "" "no gc or escalate.sh call was handed fd 9"
n="$(grep -c -F 'date fd9=open' "$FD9")"
if [ "$n" -gt 0 ]; then ok "while the pass itself held it (its clock reads saw fd 9 open $n time(s))"; else bad "the pass never held fd 9, so the closed records prove nothing"; fi

echo "# the until half's gc and bead-rehome.sh calls run without the lock's descriptor too"
# A pinned pass reads the rig roster to name its store to bead-rehome.sh, and a
# disposal runs bead-rehome.sh, whose own store reads and writes inherit what it
# was handed.
store "$ONE_OWED"
FD9="$TMP/fd9-until.log"; : > "$FD9"
out="$(STUB_FD9_LOG="$FD9" STUB_RIGS_JSON="$TMP/rigs.json" "$SUT" reconcile --db "$TMP/rig-a/.beads" 2>&1)"; rc=$?
eq "$rc" 0 "the pass completes"
eq "$(rehomes)" "1" "it disposes the owed bead"
for call in "gc rig" "rehome"; do
    n="$(grep -c -F "$call fd9=" "$FD9")"
    if [ "$n" -gt 0 ]; then ok "the until half made $n '$call' call(s)"; else bad "the until half made no '$call' call, so nothing about it was proven"; fi
done
leaked="$(grep -F 'fd9=open' "$FD9" | grep -v -F 'date fd9=' || true)"
eq "$leaked" "" "no gc or bead-rehome.sh call was handed fd 9"
n="$(grep -c -F 'date fd9=open' "$FD9")"
if [ "$n" -gt 0 ]; then ok "while the pass itself held it (its clock reads saw fd 9 open $n time(s))"; else bad "the pass never held fd 9, so the closed records prove nothing"; fi

echo "# a process a gc call leaves running does not hold the lock against the next pass"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
DAEMON="$TMP/daemon.pid"; rm -f "$DAEMON"
STUB_GC_DAEMON="$DAEMON" "$SUT" reconcile >/dev/null 2>&1; rc=$?
eq "$rc" 0 "the first pass completes"
dpid="$(cat "$DAEMON" 2>/dev/null)"
if [ -n "$dpid" ] && kill -0 "$dpid" 2>/dev/null; then
    ok "a process the first pass's gc call started is still running"
    store '[{"id":"b-2","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
    out="$("$SUT" reconcile 2>&1)"; rc=$?
    eq "$rc" 0 "the next pass exits 0"
    hasnt "$out" "already in flight" "and takes the lock that process does not hold"
    eq "$(head -1 "$STUB_SLING_LOG")" "rig/pool b-2" "and makes its sling"
else
    bad "the long-running process the fixture starts never ran"
fi
[ -n "$dpid" ] && kill "$dpid" 2>/dev/null

echo "# a pass killed by itself mid-sling leaves the lock held until its sling exits"
# The order's timeout stops the pass's whole process group. A pass killed by
# itself leaves its gc sling running, and the subshell pass_child runs the sling
# from keeps the lock until the sling exits, so no second pass slings beside it.
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
LOCKF="$TMP/state/_unscoped/pass.lock"
HOLD="$TMP/hold-kill"; rm -f "$HOLD".*
# Launched as a simple command, so $! is the pass itself. A SIGKILL runs no EXIT
# trap, so the pass stages its files under $TMP, which the suite removes.
TMPDIR="$TMP" STUB_SLING_HOLD="$HOLD" "$SUT" reconcile > /dev/null 2>&1 &
first=$!
if await "$HOLD.started"; then
    kill -9 "$first" 2>/dev/null; wait "$first" 2>/dev/null
    out="$("$SUT" reconcile 2>&1)"; rc=$?
    eq "$rc" 0 "a pass while the killed pass's sling runs on exits 0"
    has "$out" "already in flight" "and is held off by the lock that sling's subshell still holds"
    eq "$(slings)" "1" "so the killed pass's sling is the only one"
    : > "$HOLD.release"
    i=0; while ! ( exec 8>>"$LOCKF"; flock -n 8 ) 2>/dev/null && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
    ( exec 8>>"$LOCKF"; flock -n 8 ) 2>/dev/null && ok "the lock is free once that sling exits" \
        || bad "the lock outlived the killed pass's sling"
else
    bad "the pass to be killed never reached its sling (fixture wedged)"
    : > "$HOLD.release"; wait "$first" 2>/dev/null
fi

echo "# with no GC_RIG, the lock is keyed by the rig root, so two rigs never share one"
# Two roots with one name, each with its own store. A pass of the first is
# caught inside its sling, holding its lock.
ROOT_A="$TMP/roots/a/gc-toolkit"; ROOT_B="$TMP/roots/b/gc-toolkit"; mkdir -p "$ROOT_A" "$ROOT_B"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
cp "$STUB_STORE" "$TMP/beads-b.json"
HOLD="$TMP/hold-root"; rm -f "$HOLD".*
GC_RIG_ROOT="$ROOT_A" STUB_SLING_HOLD="$HOLD" "$SUT" reconcile > "$TMP/root-a.out" 2>&1 &
first=$!
if await "$HOLD.started"; then
    out="$(GC_RIG_ROOT="$ROOT_B" STUB_STORE="$TMP/beads-b.json" "$SUT" reconcile 2>&1)"; rc=$?
    eq "$rc" 0 "a pass of another rig root exits 0"
    hasnt "$out" "already in flight" "and is not held by the first root's lock, though both roots share a name"
    has "$out" "1 dispatched" "it makes its own dispatch"
    out="$(GC_RIG_ROOT="$ROOT_A" "$SUT" reconcile 2>&1)"; rc=$?
    eq "$rc" 0 "a second pass of the first root exits 0"
    has "$out" "already in flight" "and is held off by that root's lock"
    : > "$HOLD.release"; wait "$first"
else
    bad "the first root's pass never reached its sling (fixture wedged)"
    : > "$HOLD.release"; wait "$first" 2>/dev/null
fi

# --- the pass budget: no sling the timeout would cut short ---------------------
# The order's timeout kills a pass wherever it stands, and a sling killed
# mid-flight leaves its input convoy with no workflow and spends one of the
# bead's attempts. So a pass starts a sling only while a full allowance is left
# in its budget. The clock is the test's: each sling advances it STUB_SLING_SECS.
echo "# a pass starts no sling once less than one allowance of its budget is left"
FOUR_READY='[
 {"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true},
 {"id":"b-2","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true},
 {"id":"b-3","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true},
 {"id":"b-4","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
store "$FOUR_READY"
CLOCK="$TMP/clock"; printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" STUB_SLING_SECS=40 DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-partial.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a pass its budget stops exits 0 — the beads it left are owed, not failed"
eq "$(slings)" "2" "a 100s budget with a 30s allowance starts two 40s slings"
eq "$(cut -d' ' -f2 "$STUB_SLING_LOG" | paste -sd, -)" "b-1,b-2" "in listing order"
has "$out" "pass budget spent" "the pass says its budget stopped it"
has "$out" "left 2 ready bead(s) armed for the next pass: b-3 b-4" "and names the beads it left"
has "$out" "2 left for the next pass" "the summary counts them"
for b in b-3 b-4; do
    eq "$(meta "$b" gc.dispatch_when_ready)" "rig/pool" "$b keeps its arm"
    eq "$(meta "$b" gc.dispatch_when_ready_slung)" "<absent>" "$b carries no slung marker"
    eq "$(meta "$b" gc.dispatch_when_ready_fail_count)" "<absent>" "$b has no attempt counted against its cap"
done
eq "$(jq -r '.outcome' "$TMP/outcome-partial.json" 2>/dev/null)" "partial" "the pass declares itself partial to the controller"
eq "$(jq -r '[.scopes[].scope] | join(",")' "$TMP/outcome-partial.json" 2>/dev/null)" "b-3,b-4" "naming each bead it left"
: > "$STUB_SLING_LOG"; printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" STUB_SLING_SECS=40 DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"; rc=$?
eq "$(cut -d' ' -f2 "$STUB_SLING_LOG" | paste -sd, -)" "b-3,b-4" "the next pass slings the beads the last one left"
has "$out" "0 left for the next pass" "and leaves nothing"

echo "# with no knob set, the shipped budget and allowance pace the pass"
# 420s and 90s: two 200s slings start, and the third would begin with 20s left.
store "$FOUR_READY"
printf '1000\n' > "$CLOCK"
out="$( (unset DEFERRED_DISPATCH_PASS_BUDGET_SECS DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS
         STUB_CLOCK="$CLOCK" STUB_SLING_SECS=200 "$SUT" reconcile) 2>&1)"; rc=$?
eq "$(slings)" "2" "the default budget starts two 200s slings"
has "$out" "2 left for the next pass" "and leaves the other two"

echo "# a pass whose budget is spent before its first sling slings nothing and says what it left"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" DEFERRED_DISPATCH_PASS_BUDGET_SECS=20 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(slings)" "0" "and slings nothing"
has "$out" "1 left for the next pass" "it counts the bead it left"
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "<absent>" "with no attempt counted against its cap"

echo "# past the budget, a ready notice waits for the next pass, which the pass declares"
store '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true}]'
printf '1000\n' > "$CLOCK"
: > "$TMP/outcome-notice.json"
out="$(STUB_CLOCK="$CLOCK" DEFERRED_DISPATCH_PASS_BUDGET_SECS=20 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-notice.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(mails)" "0" "and sends no notice past its budget"
eq "$(meta n-1 gc.notify_when_ready)" "gc-toolkit.mechanik" "the notice stays armed"
has "$out" "left 1 ready notice(s) armed for the next pass: n-1" "the pass names the notice it left"
eq "$(jq -r '[.scopes[] | "\(.scope): \(.reason)"] | join(",")' "$TMP/outcome-notice.json" 2>/dev/null)" "n-1: notice left for the next pass" \
    "and declares it to the controller"
"$SUT" reconcile >/dev/null 2>&1
eq "$(mails)" "1" "the next pass, unpaced, sends it"

echo "# a bead a dead pass left mid-sling, reached past the budget, waits for the next pass's re-attempt"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_slung":"slinging@2026-01-01T00:00:00Z","gc.dispatch_when_ready_fail_count":"1"},"notes":"","_ready":true}]'
printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" DEFERRED_DISPATCH_PASS_BUDGET_SECS=20 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(slings)" "0" "and slings nothing"
has "$out" "1 left for the next pass" "it counts the bead it left"
eq "$(meta b-1 gc.dispatch_when_ready)" "rig/pool" "the bead keeps its arm"
eq "$(meta b-1 gc.dispatch_when_ready_slung)" "<absent>" "with the dead pass's unconfirmed marker cleared"
eq "$(meta b-1 gc.dispatch_when_ready_fail_count)" "1" "and only the dead pass's attempt counted against its cap"
"$SUT" reconcile >/dev/null 2>&1
eq "$(slings)" "1" "the next pass makes the re-attempt"

echo "# a zero budget is unpaced, and a dry run spends no budget"
store "$FOUR_READY"
printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" STUB_SLING_SECS=1000 DEFERRED_DISPATCH_PASS_BUDGET_SECS=0 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"; rc=$?
eq "$(slings)" "4" "a zero budget slings every ready bead however long each sling takes"
has "$out" "0 left for the next pass" "and leaves nothing"
store "$FOUR_READY"
printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" DEFERRED_DISPATCH_PASS_BUDGET_SECS=20 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 "$SUT" reconcile --dry-run 2>&1)"; rc=$?
eq "$(printf '%s\n' "$out" | grep -c 'DRY-RUN would sling: gc sling rig/pool b-')" "4" "a dry run lists every bead a pass would sling, whatever the budget"
hasnt "$out" "pass budget spent" "and spends none of it"
eq "$(slings)" "0" "without slinging"

echo "# a pass that leaves nothing declares nothing"
store '[{"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true}]'
: > "$TMP/outcome-full.json"
GC_ORDER_OUTCOME_FILE="$TMP/outcome-full.json" "$SUT" reconcile >/dev/null 2>&1
eq "$(slings)" "1" "the pass slings its ready bead"
[ -s "$TMP/outcome-full.json" ] && bad "a complete pass wrote an outcome declaration: $(cat "$TMP/outcome-full.json")" \
    || ok "a complete pass leaves the controller's outcome file empty"

echo "# past the budget, a capped bead's escalation waits for the next pass"
# The escalation runs escalate.sh against the store, which the timeout can cut
# short like a sling. The bead stays capped and armed, so the next pass files it.
CAP_AFTER_READY='[
 {"id":"b-1","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]"},"notes":"","_ready":true},
 {"id":"b-cap","status":"open","assignee":"","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"[]","gc.dispatch_when_ready_fail_count":"3"},"notes":"","_ready":true}]'
store "$CAP_AFTER_READY"
printf '1000\n' > "$CLOCK"
: > "$TMP/outcome-esc.json"
out="$(STUB_CLOCK="$CLOCK" STUB_SLING_SECS=40 DEFERRED_DISPATCH_PASS_BUDGET_SECS=60 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-esc.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(slings)" "1" "a 60s budget with a 30s allowance starts one 40s sling"
eq "$(escalations)" "0" "and files no escalation once less than an allowance is left"
has "$out" "CAPPED b-cap" "it still reports the capped bead"
has "$out" "its escalation waits for the next pass" "and says the escalation waits"
has "$out" "left the escalation of 1 capped bead(s) for the next pass: b-cap" "naming the bead"
has "$out" "1 capped" "the summary counts it as capped"
eq "$(meta b-cap gc.dispatch_when_ready)" "rig/pool" "the capped bead keeps its arm"
eq "$(jq -r '.outcome' "$TMP/outcome-esc.json" 2>/dev/null)" "partial" "the pass declares itself partial"
eq "$(jq -r '[.scopes[] | "\(.scope): \(.reason)"] | join(",")' "$TMP/outcome-esc.json" 2>/dev/null)" "b-cap: escalation left for the next pass" \
    "naming the bead and the escalation left on it"
printf '1000\n' > "$CLOCK"
out="$(STUB_CLOCK="$CLOCK" STUB_SLING_SECS=40 DEFERRED_DISPATCH_PASS_BUDGET_SECS=60 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 "$SUT" reconcile 2>&1)"; rc=$?
eq "$(escalations)" "1" "the next pass, with its budget unspent, files the escalation"
eq "$(cut -f1 "$ESC_CALLS")" "b-cap" "on the capped bead"

echo "# a pass that fails declares nothing, and its output names what it left"
# The controller reads a declaration only after a run that exits 0, and keeps a
# failed run's output instead. Two slings fail here, and the budget leaves two.
store "$FOUR_READY"
printf '1000\n' > "$CLOCK"
: > "$TMP/outcome-failed.json"
out="$(STUB_CLOCK="$CLOCK" STUB_SLING_SECS=40 STUB_SLING_RC=1 DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-failed.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a pass with a failed sling exits 1"
eq "$(slings)" "2" "after attempting two slings"
has "$out" "left 2 ready bead(s) armed for the next pass: b-3 b-4" "its output names the beads it left"
has "$out" "2 left for the next pass, 2 failed" "and its summary counts both"
[ -s "$TMP/outcome-failed.json" ] && bad "a failed pass wrote an outcome declaration: $(cat "$TMP/outcome-failed.json")" \
    || ok "and it writes no declaration the controller would not read"

# The until half spends the same budget, so the disposals it leaves are as much
# a part of what the pass did not do as the slings, and the one declaration a
# pass makes names them all. A failure in any half fails the pass, so a failed
# until half leaves no declaration of the slings the dispatch half left.
echo "# a pass that leaves a disposal declares it, naming the bead"
store "$THREE_OWED"
printf '1000\n' > "$CLOCK"
: > "$TMP/outcome-until.json"
out="$(STUB_CLOCK="$CLOCK" STUB_REHOME_SECS=40 DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=30 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-until.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass exits 0"
has "$out" "left 1 until-resolved bead(s) for the next pass to dispose: u-3" "its output names the bead it left"
eq "$(jq -r '.outcome' "$TMP/outcome-until.json" 2>/dev/null)" "partial" "the pass declares itself partial"
eq "$(jq -r '[.scopes[] | "\(.scope): \(.reason)"] | join(",")' "$TMP/outcome-until.json" 2>/dev/null)" "u-3: disposal left for the next pass" \
    "naming the bead and the disposal left on it"

echo "# a pass whose dispatch and until halves both leave work declares all of it once"
# 140s, a 30s sling allowance and a 10s disposal allowance: three 40s slings
# start and the fourth would begin with 20s left, then one 40s disposal starts
# with 20s left and the other two find the budget gone.
store "$(jq -cn --argjson a "$FOUR_READY" --argjson b "$THREE_OWED" '$a + $b')"
printf '1000\n' > "$CLOCK"
: > "$TMP/outcome-both.json"
out="$(STUB_CLOCK="$CLOCK" STUB_SLING_SECS=40 STUB_REHOME_SECS=40 DEFERRED_DISPATCH_PASS_BUDGET_SECS=140 \
    DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=10 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-both.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(slings)" "3" "it starts three slings"
eq "$(rehomes)" "1" "and one disposal"
eq "$(jq -r '.outcome' "$TMP/outcome-both.json" 2>/dev/null)" "partial" "the pass declares itself partial"
eq "$(jq -r '[.scopes[] | "\(.scope): \(.reason)"] | join(",")' "$TMP/outcome-both.json" 2>/dev/null)" \
    "b-4: sling left for the next pass,u-2: disposal left for the next pass,u-3: disposal left for the next pass" \
    "naming every bead a half left, and what it left there"
has "$(jq -r '.reason' "$TMP/outcome-both.json" 2>/dev/null)" "1 ready bead(s) left armed for the next pass, 2 until-resolved bead(s) left for the next pass to dispose" \
    "and giving each half's count as its reason"

echo "# a pass whose until half fails declares nothing, though its dispatch half left slings"
store "$(jq -cn --argjson a "$FOUR_READY" --argjson b "$ONE_OWED" '$a + $b')"
printf '1000\n' > "$CLOCK"
: > "$TMP/outcome-until-failed.json"
out="$(STUB_CLOCK="$CLOCK" STUB_SLING_SECS=40 STUB_REHOME_RC=1 DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 \
    DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=10 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-until-failed.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a pass whose disposal failed exits 1"
has "$out" "left 2 ready bead(s) armed for the next pass: b-3 b-4" "its output still names the slings it left"
[ -s "$TMP/outcome-until-failed.json" ] && bad "a failed pass wrote an outcome declaration: $(cat "$TMP/outcome-until-failed.json")" \
    || ok "and it writes no declaration the controller would not read"

echo "# a pass whose every half leaves work declares all of it once, the notices first"
# 20s of budget is less than the 30s a notice or a sling needs, so the ready
# notice and all four ready slings are left. A disposal's 10s allowance still
# fits, and the one 40s disposal it starts leaves the other two.
store "$(jq -cn --argjson a "$FOUR_READY" --argjson b "$THREE_OWED" '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true}] + $a + $b')"
printf '1000\n' > "$CLOCK"
: > "$TMP/outcome-every.json"
out="$(STUB_CLOCK="$CLOCK" STUB_REHOME_SECS=40 DEFERRED_DISPATCH_PASS_BUDGET_SECS=20 \
    DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS=10 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-every.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(mails)" "0" "it sends no notice"
eq "$(slings)" "0" "starts no sling"
eq "$(rehomes)" "1" "and starts one disposal"
has "$out" "left 1 ready notice(s) armed for the next pass: n-1" "its output names the notice it left"
eq "$(jq -r '[.scopes[] | "\(.scope): \(.reason)"] | join(",")' "$TMP/outcome-every.json" 2>/dev/null)" \
    "n-1: notice left for the next pass,b-1: sling left for the next pass,b-2: sling left for the next pass,b-3: sling left for the next pass,b-4: sling left for the next pass,u-2: disposal left for the next pass,u-3: disposal left for the next pass" \
    "the declaration names every bead each half left, the notice first"
has "$(jq -r '.reason' "$TMP/outcome-every.json" 2>/dev/null)" "1 ready notice(s) left armed for the next pass, 4 ready bead(s) left armed for the next pass, 2 until-resolved bead(s) left for the next pass to dispose" \
    "and gives each half's count as its reason, in the order the halves run"

echo "# a pass whose notice fails declares nothing, though its dispatch half left slings"
store "$(jq -cn --argjson a "$FOUR_READY" '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{"gc.notify_when_ready":"gc-toolkit.mechanik"},"notes":"","_ready":true}] + $a')"
printf '1000\n' > "$CLOCK"
: > "$TMP/outcome-notice-failed.json"
out="$(STUB_CLOCK="$CLOCK" STUB_SLING_SECS=40 STUB_MAIL_RC=1 STUB_NUDGE_RC=1 DEFERRED_DISPATCH_PASS_BUDGET_SECS=100 \
    DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS=30 \
    GC_ORDER_OUTCOME_FILE="$TMP/outcome-notice-failed.json" "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "a pass whose notice got no turn requested exits 1"
eq "$(slings)" "2" "after its dispatch half started two slings"
has "$out" "left 2 ready bead(s) armed for the next pass: b-3 b-4" "its output still names the slings it left"
[ -s "$TMP/outcome-notice-failed.json" ] && bad "a failed pass wrote an outcome declaration: $(cat "$TMP/outcome-notice-failed.json")" \
    || ok "and it writes no declaration the controller would not read"

# --- positive control over the shipped cadence -------------------------------
# The arm is only half the mechanism: without the order nothing consumes these
# records and the hold is stranded one layer down instead of in an agent's head.
echo "# shipped order"
ORDER="$ROOT/orders/deferred-dispatch.toml"
[ -s "$ORDER" ] && ok "orders/deferred-dispatch.toml ships" || bad "orders/deferred-dispatch.toml is missing"
o="$(cat "$ORDER" 2>/dev/null)"
has "$o" 'trigger = "cooldown"' "the order is cooldown-triggered"
has "$o" 'scope = "rig"' "the order is rig-scoped (one store per registration)"
has "$o" 'deferred-dispatch.sh reconcile' "the order runs this script's reconcile verb"
if grep -qE '^[[:space:]]*no_work_gate' "$ORDER"; then
    bad "the order does not opt out of the single-flight gate (no_work_gate is set)"
else
    ok "the order does not opt out of the single-flight gate"
fi
# The timeout, bounded by the numbers this script owns. A pass spends its first
# minutes listing the armed set, so a timeout inside the 2m window leaves it no
# room to sling, and above that window a tracking-sweep watchdog can reopen the
# controller's gate under a running pass, so a wider timeout stands on the pass
# lock proven above. The pass budget sits at least one allowance of either kind
# below the timeout, so the last sling or disposal a pass starts can run for
# twice its allowance before the kill. The lock-stall bound sits above it, so a
# pass still running never reads as a wedged one.
SWEEP_WINDOW=120
to="$(awk -F'"' '/^[[:space:]]*timeout[[:space:]]*=/{print $2}' "$ORDER")"
to_secs=""
case "$to" in
    [0-9]*s) to_secs="${to%s}" ;;
    [0-9]*m) to_secs=$(( ${to%m} * 60 )) ;;
esac
case "$to_secs" in ''|*[!0-9]*) to_secs="" ;; esac
PB="$(sed -n 's/^PASS_BUDGET_SECS="\${DEFERRED_DISPATCH_PASS_BUDGET_SECS:-\([0-9][0-9]*\)}"$/\1/p' "$SUT")"
SA="$(sed -n 's/^SLING_ALLOWANCE_SECS="\${DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS:-\([0-9][0-9]*\)}"$/\1/p' "$SUT")"
DA="$(sed -n 's/^DISPOSE_ALLOWANCE_SECS="\${DEFERRED_DISPATCH_DISPOSE_ALLOWANCE_SECS:-\([0-9][0-9]*\)}"$/\1/p' "$SUT")"
STALL="$(sed -n 's/^LOCK_STALL_SECS="\${DEFERRED_DISPATCH_LOCK_STALL_SECS:-\([0-9][0-9]*\)}"$/\1/p' "$SUT")"
if [ -z "$to_secs" ]; then
    bad "order timeout \"$to\" is unparseable, so nothing can be bounded against it"
else
    if [ "$to_secs" -le "$SWEEP_WINDOW" ]; then
        bad "timeout $to leaves a pass no room to sling after it lists the armed set"
    elif [ "$LOCK_PROVEN" = 1 ]; then
        ok "timeout $to outruns the ${SWEEP_WINDOW}s tracking-sweep window, and the pass lock (proven above) carries single-flight"
    else
        bad "timeout $to outruns the ${SWEEP_WINDOW}s tracking-sweep window and the pass lock is unproven — a swept tracking bead is a second pass"
    fi
    case "$PB" in ''|*[!0-9]*) PB="" ;; esac
    case "$SA" in ''|*[!0-9]*) SA="" ;; esac
    if [ -z "$PB" ] || [ -z "$SA" ]; then
        bad "the pass budget or sling allowance default is unreadable, so it cannot be bounded against the timeout"
    elif [ "$SA" -lt "$PB" ] && [ $(( PB + SA )) -le "$to_secs" ]; then
        ok "the ${PB}s pass budget sits at least one ${SA}s sling allowance below the $to timeout"
    else
        bad "the ${PB}s pass budget and ${SA}s sling allowance do not fit the $to timeout — the last sling a pass starts can be killed mid-flight"
    fi
    case "$DA" in ''|*[!0-9]*) DA="" ;; esac
    if [ -z "$PB" ] || [ -z "$DA" ]; then
        bad "the pass budget or disposal allowance default is unreadable, so it cannot be bounded against the timeout"
    elif [ "$DA" -lt "$PB" ] && [ $(( PB + DA )) -le "$to_secs" ]; then
        ok "the ${PB}s pass budget sits at least one ${DA}s disposal allowance below the $to timeout"
    else
        bad "the ${PB}s pass budget and ${DA}s disposal allowance do not fit the $to timeout — the last disposal a pass starts can be killed mid-flight"
    fi
    case "$STALL" in
        ''|*[!0-9]*) bad "the lock-stall default is unreadable, so it cannot be bounded against the timeout" ;;
        *) if [ "$STALL" -gt "$to_secs" ]; then
               ok "the ${STALL}s lock-stall bound sits above the $to timeout"
           else
               bad "the ${STALL}s lock-stall bound is not above the $to timeout — a pass still running reads as a wedged one"
           fi ;;
    esac
fi

# ── scratch cleanup ─────────────────────────────────────────────────────────
# The EXIT trap reads a registry the allocations append to. Appending from a
# command substitution mutates a subshell's copy and the trap then removes
# nothing, so the cleanup has to be asserted on disk rather than read off the
# presence of a trap line.
SCRATCH="$TMP/scratch"
mkdir -p "$SCRATCH"
TMPDIR="$SCRATCH" "$SUT" list                >/dev/null 2>&1
TMPDIR="$SCRATCH" "$SUT" list --json         >/dev/null 2>&1
TMPDIR="$SCRATCH" "$SUT" reconcile           >/dev/null 2>&1
TMPDIR="$SCRATCH" "$SUT" reconcile --dry-run >/dev/null 2>&1
# The until pass re-reads each bead it is about to dispose inside a command
# substitution, where an allocation would land in a subshell's registry.
store '[
 {"id":"g-1","issue_type":"task","status":"open","assignee":"","metadata":{},"notes":"","_deps":[{"id":"x-1","dependency_type":"until"}]},
 {"id":"x-1","status":"closed","assignee":"","metadata":{},"notes":""}]'
out="$(TMPDIR="$SCRATCH" STUB_DEP_UP_FAIL=g-1 "$SUT" reconcile 2>&1)"
has "$out" "could not re-read g-1" "the scratch run reaches the until pass's fresh read and its fail-closed path"
TMPDIR="$SCRATCH" "$SUT" reconcile >/dev/null 2>&1
eq "$(rehomes)" "1" "and its disposal path"
store '[{"id":"n-1","status":"open","assignee":"gc-toolkit.mechanik","metadata":{},"notes":"","_ready":true}]'
TMPDIR="$SCRATCH" "$SUT" notify n-1 --agent gc-toolkit.mechanik >/dev/null 2>&1
LEFT=$(find "$SCRATCH" -maxdepth 1 -name 'gctk-deferred-dispatch.*' 2>/dev/null | wc -l | tr -d ' ')
eq "$LEFT" "0" "no verb leaves a staging file behind in TMPDIR"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
