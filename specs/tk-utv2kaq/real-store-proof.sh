#!/usr/bin/env bash
# The stand-down on the real scripts against a scratch store run by the real bd,
# with a real blocks edge onto a real human gate. The suites stub bd, and their
# test floor refuses the real one, so this is run by hand and its output is the
# record in real-store-proof.md.
#
#   env -i HOME="$HOME" TERM=dumb bash real-store-proof.sh \
#     <work dir> <this branch's assets/scripts> <a base's assets/scripts> <gctk binary>
#
# Each case prints what it did and what the store then reads. <base's scripts> is
# the deferred-dispatch.sh a pass already running would be: the control for the
# re-read of the arm.
set -u
W="$1"; SCRIPTS="$2"; BASE="$3"; GCTK="$4"
STORE="$W/store"
[ ! -e "$STORE" ] || { echo "$W already holds a store, and a server from that run can still answer for it: use a fresh work dir"; exit 1; }
mkdir -p "$STORE" "$W/state" "$W/tmp" "$W/bin"
export PATH="$W/bin:/opt/homebrew/bin:/Users/gc/.local/bin:/usr/bin:/bin:/usr/sbin"
export TMPDIR="$W/tmp" PROBE_STORE="$STORE" PROBE_LOG="$W/sling.log" GCTK_BIN="$GCTK"
: > "$PROBE_LOG"; : > "$PROBE_LOG.unsupported"

# gc over the scratch store: `gc bd` is bd, `gc rig list` names the one rig, and
# `gc sling` records the send. PROBE_FAIL refuses the one gc bd verb it names,
# PROBE_LAND_AT names the listing at which PROBE_LAND runs, once: a write that
# lands while a pass is between its reads, and PROBE_AFTER names the write after
# which PROBE_AFTER_RUN runs: a pass that comes right behind that write.
cat > "$W/bin/gc" <<'SHIM'
#!/usr/bin/env bash
case "${1:-}" in
  bd)
    shift
    [ "${1:-}" = --rig ] && shift 2
    case " $* " in
      *"${PROBE_FAIL:-<none>}"*) echo "gc shim: refused: $*" >&2; exit 1 ;;
    esac
    if [ -n "${PROBE_LAND_AT:-}" ] && [ ! -e "$PROBE_LOG.landed" ]; then
      case " $* " in
        *"$PROBE_LAND_AT"*)
          : > "$PROBE_LOG.landed"
          env -u PROBE_LAND_AT -u PROBE_LAND bash -c "$PROBE_LAND" >&2 ;;
      esac
    fi
    if [ -n "${PROBE_AFTER:-}" ]; then
      case " $* " in
        *"$PROBE_AFTER"*)
          # raw-bd: this shim is the scratch store's gc bd
          bd "$@"; rc=$?
          env -u PROBE_AFTER -u PROBE_AFTER_RUN bash -c "$PROBE_AFTER_RUN" >&2
          exit "$rc" ;;
      esac
    fi
    # raw-bd: this shim is the scratch store's gc bd
    exec bd "$@" ;;
  rig) printf '{"rigs":[{"name":"probe","path":"%s","prefix":"pb"}]}\n' "${PROBE_STORE:?}" ;;
  session) printf '{"sessions":[]}\n' ;;
  sling)
    shift; [ "${1:-}" = --rig ] && shift 2
    printf 'sling %s\n' "$*" >> "${PROBE_LOG:?}" ;;
  *) printf 'gc %s\n' "$*" >> "${PROBE_LOG:?}.unsupported"; printf 'gc shim: unsupported: %s\n' "$*" >&2; exit 2 ;;
esac
SHIM
chmod +x "$W/bin/gc"

( cd "$STORE" && git init -q -b main . && git config user.name probe && git config user.email probe@example.invalid ) \
  || { echo "store init failed"; exit 1; }
# raw-bd: nothing but bd makes the scratch store
( cd "$STORE" && bd init --prefix pb --non-interactive --proxied-server >"$W/init.log" 2>&1 ) \
  || { echo "store init failed"; tail -5 "$W/init.log"; exit 1; }
export BEADS_DIR="$STORE/.beads" GC_RIG=probe GC_RIG_ROOT="$STORE" GC_AGENT=probe-person BEADS_ACTOR=probe-person GC_VISIT_COMMENT_TOOL=/bin/true
DB="$STORE/.beads"
cd "$STORE" || exit 1
gc bd config set types.custom "convoy,gate,molecule,decision" >/dev/null 2>&1
i=0
until gc bd create "warm-up" -t task --json >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -lt 40 ] || { echo "the store never accepted a create"; exit 1; }
  perl -e 'select(undef,undef,undef,0.5)'
done
echo "bd: $(gc bd version 2>/dev/null | head -1)"

mk() { gc bd create "$1" -t "${2:-task}" --json 2>>"$W/mk.err" | jq -r 'if type == "array" then .[0].id else .id end'; }
row() {
  gc bd show "$1" --json 2>/dev/null | jq -c '.[0] | {status, assignee: (.assignee // ""), close_reason: (.close_reason // ""),
    armed: (.metadata["gc.dispatch_when_ready"] // ""), route: (.metadata["gc.routed_to"] // ""),
    pointer: (.metadata["gc.superseded_by"] // ""), outcome: (.metadata["gc.work_outcome"] // "")}'
}
gate_of() { gc bd dep list "$1" --type blocks --json 2>/dev/null | jq -r --arg k "$2" '[ .[] | select((.await_id // "") == $k) ] | .[0].id // empty'; }
pass() { DEFERRED_DISPATCH_STATE_DIR="$W/state" "${1:-$SCRIPTS}/deferred-dispatch.sh" reconcile --db "$DB" 2>&1 | grep -v '^deferred-dispatch: until' | tail -3 | cut -c1-170; }
slings() { wc -l < "$PROBE_LOG" | tr -d ' '; }
waiting() { # <title> <key> [<type>] -> a work bead a real gate blocks, armed to re-sling, as a declined run leaves it
  local b; b=$(mk "$1" "${3:-task}")
  gc bd update "$b" --set-metadata gc.execution_routed_to=probe/probe.polecat >/dev/null
  "$SCRIPTS/human-gate.sh" --subject "$b" --key "$2" --message "$1: does this go on?" >/dev/null || { echo "gate not filed on $b" >&2; return 1; }
  GC_DEFERRED_DISPATCH_TOOL="$SCRIPTS/deferred-dispatch.sh" "$SCRIPTS/await-ruling.sh" "$b" --key "$2" --formula mol-polecat-work >/dev/null || { echo "wait not recorded on $b" >&2; return 1; }
  printf '%s' "$b"
}
say() { printf '\n## %s\n' "$*"; }

say "Close first, as the old instruction said: bd refuses it"
A=$(waiting "close first" polecat-a); GA=$(gate_of "$A" polecat-a)
echo "work $A, gate $GA: $(row "$A")"
gc bd close "$A" --reason "standing down" 2>&1 | tail -1 | cut -c1-170; echo "rc=${PIPESTATUS[0]}"
echo "after: $(row "$A")"

say "Gate first, the only other order by hand: the arm restarts the work"
gc bd gate resolve "$GA" --reason "ruled: do not go on" >/dev/null 2>&1
before=$(slings); pass "$SCRIPTS" | tail -1
echo "slings by that pass: $(($(slings) - before)): $(tail -1 "$PROBE_LOG")"
gc bd update "$A" --unset-metadata gc.dispatch_when_ready_slung >/dev/null 2>&1

say "stand-down.sh on the same shape"
B=$(waiting "stand down" polecat-b); GB=$(gate_of "$B" polecat-b)
echo "work $B, gate $GB: $(row "$B")"
"$SCRIPTS/stand-down.sh" "$B" --key polecat-b --ruling "the branch is wrong and nobody needs this" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "rc=${PIPESTATUS[0]}"
echo "work: $(row "$B")"
echo "gate: $(gc bd show "$GB" --json | jq -c '.[0] | {status, close_reason, supersedes: (.metadata["gc.supersedes"] // "")}')"
before=$(slings); pass "$SCRIPTS" | tail -1
echo "slings by the next pass: $(($(slings) - before))"
"$SCRIPTS/stand-down.sh" "$B" --key polecat-b --ruling "again" 2>&1 | cut -c1-170; echo "a second run: rc=${PIPESTATUS[0]}"

say "A pass already running: the stand-down lands between the pass's arm listing and its hold read"
C=$(waiting "mid-pass, base's pass" polecat-c)
: > "$PROBE_LOG"; rm -f "$PROBE_LOG.landed"
PROBE_LAND_AT="--ready" PROBE_LAND="$SCRIPTS/stand-down.sh $C --key polecat-c --ruling 'stop this while the pass runs' >/dev/null 2>&1" pass "$BASE" | tail -1
echo "the base's pass, no re-read of the arm: slings $(slings): $(tail -1 "$PROBE_LOG"); work: $(row "$C")"
D=$(waiting "mid-pass, this pass" polecat-d)
: > "$PROBE_LOG"; rm -f "$PROBE_LOG.landed"
PROBE_LAND_AT="--ready" PROBE_LAND="$SCRIPTS/stand-down.sh $D --key polecat-d --ruling 'stop this while the pass runs' >/dev/null 2>&1" pass "$SCRIPTS" | tail -2
echo "this branch's pass: slings $(slings); work: $(row "$D")"

say "A store write that fails partway, then a re-run"
E=$(waiting "stopped partway" polecat-e); GE=$(gate_of "$E" polecat-e)
PROBE_FAIL="gate resolve" "$SCRIPTS/stand-down.sh" "$E" --key polecat-e --ruling "stop" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "gate resolve refused: rc=${PIPESTATUS[0]}"
echo "work: $(row "$E"); gate status: $(gc bd show "$GE" --json | jq -r '.[0].status')"
before=$(slings); pass "$SCRIPTS" | tail -1; echo "slings by a pass between the runs: $(($(slings) - before))"
"$SCRIPTS/stand-down.sh" "$E" --key polecat-e --ruling "stop" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "re-run: rc=${PIPESTATUS[0]}"
echo "work: $(row "$E")"

say "A sitting: stand down first, then the sign-off"
F=$(waiting "sitting" polecat-f); GF=$(gate_of "$F" polecat-f)
V=$(gc bd create "Discuss: $F" -t task --assignee human --metadata '{"task_kind":"visit"}' --json 2>>"$W/mk.err" | jq -r 'if type == "array" then .[0].id else .id end')
gc bd dep add "$V" "$F" -t tracks >/dev/null 2>&1; gc bd dep add "$V" "$GF" -t replies-to >/dev/null 2>&1
"$SCRIPTS/stand-down.sh" "$F" --key polecat-f --ruling "the operator ruled this out" --successor "$V" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "stand-down: rc=${PIPESTATUS[0]}"
"$SCRIPTS/converse-signoff.sh" --conversation "$V" --outcome "Ruled out: nothing builds this" --ruled yes --ruling "the operator ruled this out" --route human --no-wait 2>&1 | cut -c1-170; echo "sign-off: rc=${PIPESTATUS[0]}"
echo "work: $(row "$F")"; echo "gate: $(gc bd show "$GF" --json | jq -c '.[0] | {status, close_reason}')"; echo "conversation: $(gc bd show "$V" --json | jq -c '.[0] | {status}')"

say "A sitting's hold left the subject at held: stand down, then the sign-off"
H1=$(waiting "held" polecat-held); GH1=$(gate_of "$H1" polecat-held)
"$SCRIPTS/deferred-dispatch.sh" disarm "$H1" --reason "as a hold on an unarmed subject leaves it" >/dev/null 2>&1
"$SCRIPTS/gc-helm.sh" takeaway "$H1" "Waits on the operator" --by converse >/dev/null 2>&1
"$SCRIPTS/lifecycle.sh" transition "$H1" --to held --route human 2>&1 | cut -c1-170
V1=$(gc bd create "Discuss: $H1" -t task --assignee human --metadata '{"task_kind":"visit"}' --json 2>>"$W/mk.err" | jq -r 'if type == "array" then .[0].id else .id end')
gc bd dep add "$V1" "$H1" -t tracks >/dev/null 2>&1; gc bd dep add "$V1" "$GH1" -t replies-to >/dev/null 2>&1
echo "state before: $("$SCRIPTS/lifecycle.sh" state "$H1" 2>&1)"
"$SCRIPTS/stand-down.sh" "$H1" --key polecat-held --ruling "ruled out from a held sitting" --successor "$V1" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "stand-down: rc=${PIPESTATUS[0]}"
echo "state after: $("$SCRIPTS/lifecycle.sh" state "$H1" 2>&1); work: $(row "$H1"); merge_result: $(gc bd show "$H1" --json | jq -r '.[0].metadata.merge_result // "none"')"
"$SCRIPTS/converse-signoff.sh" --conversation "$V1" --outcome "Ruled out: nothing builds this" --ruled yes --ruling "ruled out from a held sitting" --route human --no-wait 2>&1 | cut -c1-200; echo "sign-off: rc=${PIPESTATUS[0]}"
echo "work: $(row "$H1"); merge_result: $(gc bd show "$H1" --json | jq -r '.[0].metadata.merge_result // "none"')"; echo "conversation: $(gc bd show "$V1" --json | jq -c '.[0] | {status}')"

say "Refusals, each writing nothing"
snapshot() { gc bd show "$1" --json | jq -c '.[0] | del(.updated_at)'; }
try() { # <label> <work> <args...>
  local label="$1" b="$2"; shift 2
  local before; before=$(snapshot "$b")
  "$SCRIPTS/stand-down.sh" "$b" "$@" 2>&1 | tail -1 | cut -c1-200
  echo "$label: rc=${PIPESTATUS[0]}; store $( [ "$before" = "$(snapshot "$b")" ] && echo unchanged || echo CHANGED )"
}
G=$(waiting "wrong key" polecat-g); try "a key no gate carries" "$G" --key nobody --ruling x
H=$(waiting "two gates" polecat-h); "$SCRIPTS/human-gate.sh" --subject "$H" --key other-question --message "another question" >/dev/null; try "another open gate" "$H" --key polecat-h --ruling x
I=$(waiting "real blocker" polecat-i); J=$(mk "prerequisite"); gc bd dep add "$I" "$J" -t blocks >/dev/null 2>&1; try "another live blocker" "$I" --key polecat-i --ruling x
K=$(waiting "parent" polecat-k); gc bd create "child" -t task --parent "$K" --json >/dev/null 2>&1; try "an open child" "$K" --key polecat-k --ruling x
L=$(waiting "shared" polecat-l); GL=$(gate_of "$L" polecat-l); M=$(mk "other bead the gate holds"); gc bd dep add "$M" "$GL" -t blocks >/dev/null 2>&1; try "a gate that holds another bead, with nothing else as the evidence" "$L" --key polecat-l --ruling x
N=$(waiting "PR" polecat-n); gc bd update "$N" --set-metadata merge_result=pull_request >/dev/null; try "an open PR" "$N" --key polecat-n --ruling x
O=$(waiting "assigned person" polecat-o); GO=$(gate_of "$O" polecat-o); gc bd update "$GO" --assignee someone >/dev/null; try "a gate a person is assigned" "$O" --key polecat-o --ruling x
Q=$(waiting "claimed" polecat-q); gc bd update "$Q" --assignee someone --status in_progress >/dev/null; try "a claim" "$Q" --key polecat-q --ruling x

say "A gate that holds another bead, taken off it by hand with the arm standing: the next pass sends the work"
L3=$(waiting "shared, by hand" polecat-l3); GL3=$(gate_of "$L3" polecat-l3); M3=$(mk "the other bead"); gc bd dep add "$M3" "$GL3" -t blocks >/dev/null 2>&1
gc bd dep remove "$L3" "$GL3" >/dev/null 2>&1
before=$(slings); pass "$SCRIPTS" | tail -1
echo "slings by that pass: $(($(slings) - before)): $(tail -1 "$PROBE_LOG")"

say "A gate that holds another bead, with the evidence named: this bead leaves it, and a pass right behind that write sends nothing"
L2=$(waiting "shared, evidence named" polecat-l2); GL2=$(gate_of "$L2" polecat-l2); M2=$(mk "the other bead"); gc bd dep add "$M2" "$GL2" -t blocks >/dev/null 2>&1
"$SCRIPTS/deferred-dispatch.sh" arm "$M2" --target probe/probe.polecat --reason "waits on the gate" >/dev/null 2>&1
EV=$(mk "evidence")
before=$(slings)
PROBE_AFTER="dep remove $L2" PROBE_AFTER_RUN="DEFERRED_DISPATCH_STATE_DIR='$W/state' '$SCRIPTS/deferred-dispatch.sh' reconcile --db '$DB' > '$W/pass-behind.log' 2>&1" \
  "$SCRIPTS/stand-down.sh" "$L2" --key polecat-l2 --ruling "only this bead stops" --successor "$EV" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "rc=${PIPESTATUS[0]}"
echo "the pass behind the edge: $(grep -v '^deferred-dispatch: until' "$W/pass-behind.log" | tail -1 | cut -c1-170)"
echo "slings by that pass and the stand-down: $(($(slings) - before))"
echo "work: $(row "$L2")"; echo "gate: $(gc bd show "$GL2" --json | jq -c '.[0] | {status}')"; echo "other bead: $(row "$M2")"
before=$(slings); pass "$SCRIPTS" | tail -1; echo "slings by the next pass: $(($(slings) - before))"
gc bd gate resolve "$GL2" --reason "ruled: the other bead goes on" >/dev/null 2>&1
before=$(slings); pass "$SCRIPTS" | tail -1
echo "an answer once the work has closed, then a pass: slings $(($(slings) - before)): $(tail -1 "$PROBE_LOG")"

say "A routed bead on a shared gate: off it by hand a pool's query offers the work, and through the command it does not"
routed() { # <title> <key> -> a work bead a pool's route names, on a real gate beside another bead
  local b g o; b=$(mk "$1")
  gc bd update "$b" --set-metadata gc.routed_to=probe/probe.polecat >/dev/null
  "$SCRIPTS/human-gate.sh" --subject "$b" --key "$2" --message "$1: does this go on?" >/dev/null || { echo "gate not filed on $b" >&2; return 1; }
  g=$(gate_of "$b" "$2"); o=$(mk "the other bead"); gc bd dep add "$o" "$g" -t blocks >/dev/null 2>&1
  printf '%s' "$b"
}
offered() { gc bd ready --metadata-field gc.routed_to=probe/probe.polecat --unassigned --json 2>/dev/null | jq -c --arg b "$1" '[ .[] | select(.id == $b) | .id ]'; }
R1=$(routed "routed, by hand" polecat-r1); GR1=$(gate_of "$R1" polecat-r1)
echo "a pool's query, on the gate: $(offered "$R1")"
gc bd dep remove "$R1" "$GR1" >/dev/null 2>&1
echo "a pool's query, off the gate by hand: $(offered "$R1")"
R2=$(routed "routed, through the command" polecat-r2); EV2=$(mk "evidence")
PROBE_AFTER="dep remove $R2" PROBE_AFTER_RUN="gc bd ready --metadata-field gc.routed_to=probe/probe.polecat --unassigned --json 2>/dev/null | jq -c '[ .[] | select(.id == \"$R2\") | .id ]' > '$W/offered-behind.log'" \
  "$SCRIPTS/stand-down.sh" "$R2" --key polecat-r2 --ruling "only this bead stops" --successor "$EV2" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "rc=${PIPESTATUS[0]}"
echo "a pool's query, right behind the edge: $(cat "$W/offered-behind.log")"
echo "work: $(row "$R2")"

say "The same gate in a sitting: stand down, then a sign-off that leaves the gate to the other bead"
S=$(waiting "sitting, shared gate" polecat-s); GS=$(gate_of "$S" polecat-s); M4=$(mk "the other bead"); gc bd dep add "$M4" "$GS" -t blocks >/dev/null 2>&1
VS=$(gc bd create "Discuss: $S" -t task --assignee human --metadata '{"task_kind":"visit"}' --json 2>>"$W/mk.err" | jq -r 'if type == "array" then .[0].id else .id end')
gc bd dep add "$VS" "$S" -t tracks >/dev/null 2>&1; gc bd dep add "$VS" "$GS" -t replies-to >/dev/null 2>&1
"$SCRIPTS/stand-down.sh" "$S" --key polecat-s --ruling "the operator ruled this out" --successor "$VS" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "stand-down: rc=${PIPESTATUS[0]}"
"$SCRIPTS/converse-signoff.sh" --conversation "$VS" --outcome "Ruled out: nothing builds this" --ruled yes --ruling "the operator ruled this out" --route human --no-wait --leave "$GS" 2>&1 | cut -c1-170; echo "sign-off: rc=${PIPESTATUS[0]}"
echo "work: $(row "$S")"; echo "gate: $(gc bd show "$GS" --json | jq -c '.[0] | {status}')"; echo "other bead: $(row "$M4")"; echo "conversation: $(gc bd show "$VS" --json | jq -c '.[0] | {status}')"
before=$(slings); pass "$SCRIPTS" | tail -1; echo "slings by the next pass: $(($(slings) - before))"

say "A graduated convoy the refinery parked, whose gate's message names the stand-down"
CV=$(gc bd create "a graduated convoy" -t convoy --json 2>>"$W/mk.err" | jq -r 'if type == "array" then .[0].id else .id end')
TR=$(mk "a bead the convoy tracks"); gc bd dep add "$CV" "$TR" -t tracks >/dev/null 2>&1
"$SCRIPTS/human-gate.sh" --subject "$CV" --key refinery-zero-diff-check-failed --message "the zero-diff check could not run" >/dev/null
"$SCRIPTS/lifecycle.sh" transition "$CV" --to blocked --assignee "" --route human --set "blocked_reason=the check could not run" --takeaway "the check could not run" 2>&1 | cut -c1-170
"$SCRIPTS/stand-down.sh" "$CV" --key refinery-zero-diff-check-failed --ruling "drop the graduation" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "rc=${PIPESTATUS[0]}"
echo "convoy: $(row "$CV")"; echo "tracked: $(row "$TR")"

say "An epic that carries a hypothesis and no ruling: the gate holds it as it stands, and the stand-down closes it on a disposition"
EP=$(waiting "stewarded epic" polecat-ep epic); GEP=$(gate_of "$EP" polecat-ep)
gc bd update "$EP" --set-metadata epic_hypothesis="the hypothesis" >/dev/null
"$SCRIPTS/finalize-gate.sh" check "$EP" --except-key polecat-ep | cut -c1-120; echo "the gate as it stands: rc=${PIPESTATUS[0]}"
"$SCRIPTS/finalize-gate.sh" check "$EP" --except-key polecat-ep --as-disposed; echo "the gate read as the close will leave it: rc=$?"
VE=$(gc bd create "Discuss: $EP" -t task --assignee human --metadata '{"task_kind":"visit"}' --json 2>>"$W/mk.err" | jq -r 'if type == "array" then .[0].id else .id end')
gc bd dep add "$VE" "$EP" -t tracks >/dev/null 2>&1; gc bd dep add "$VE" "$GEP" -t replies-to >/dev/null 2>&1
"$SCRIPTS/stand-down.sh" "$EP" --key polecat-ep --ruling "the operator ruled this epic out" --successor "$VE" 2>&1 | grep -v 'attribution\|SELECT' | cut -c1-170; echo "stand-down: rc=${PIPESTATUS[0]}"
"$SCRIPTS/converse-signoff.sh" --conversation "$VE" --outcome "Ruled out: nothing builds this" --ruled yes --ruling "the operator ruled this epic out" --route human --no-wait 2>&1 | cut -c1-170; echo "sign-off: rc=${PIPESTATUS[0]}"
echo "epic: $(row "$EP"); ruling: $(gc bd show "$EP" --json | jq -c '.[0].metadata.epic_ruling // "none"')"; echo "gate: $(gc bd show "$GEP" --json | jq -c '.[0] | {status, close_reason}')"; echo "conversation: $(gc bd show "$VE" --json | jq -c '.[0] | {status}')"
before=$(slings); pass "$SCRIPTS" | tail -1; echo "slings by the next pass: $(($(slings) - before))"
"$SCRIPTS/../../doctor/check-epic-closed-implies-ruled/run.sh" 2>&1 | head -3 | cut -c1-170; echo "I15: rc=${PIPESTATUS[0]}"
EK=$(waiting "epic with a unit" polecat-ek epic); gc bd update "$EK" --set-metadata epic_hypothesis="the hypothesis" >/dev/null; gc bd create "a unit" -t task --parent "$EK" --json >/dev/null 2>&1; try "an epic with an open child" "$EK" --key polecat-ek --ruling x
EH=$(waiting "epic with two gates" polecat-eh epic); gc bd update "$EH" --set-metadata epic_hypothesis="the hypothesis" >/dev/null; "$SCRIPTS/human-gate.sh" --subject "$EH" --key other-question --message "another question" >/dev/null; try "an epic under another open gate" "$EH" --key polecat-eh --ruling x

printf '\n## What the shim was asked that it does not serve\n'; sort -u "$PROBE_LOG.unsupported"
