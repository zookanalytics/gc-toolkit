#!/usr/bin/env bash
# Hermetic test for the way in to gc-helm and its seats: a bare `gc-helm`,
# `gc-helm po --rig <name>` and `gc-helm mechanik`.
#
# Runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a stubbed `gc` on
# PATH that records every call, and the city's rigs from a fixture. No live
# city, controller, tmux or session.
# Covered:
#   (BARE)        a bare gc-helm on a terminal hands it to engage's form, on
#                 starting a conversation
#   (BARE-NOTTY)  without a terminal it names the verbs and what a bare gc-helm
#                 does on one, prints the usage and exits 2, opening no form
#   (BARE-MISSING) with no form built it exits 3, naming the seats' commands
#   (PO, MK)      a seat's verb reads its session's name from the agent roster
#                 and makes one `gc session attach` on it, which starts a seat
#                 that is not running, and nothing else: no session listing, no
#                 nudge and no wake of its own; once the attach comes back it
#                 names how to return
#   (KIT)         under a city that imports the pack as kit, each verb attaches
#                 to the session the roster names, kit.mechanik and
#                 <rig>/kit.po
#   (PO-RIG)      po needs --rig, the rig by its exact name, and refuses a rig
#                 the city has not, the city's HQ or a suspended rig, attaching
#                 nothing
#   (SEAT-NAME)   a roster that cannot be read exits 4 naming the re-run, and
#                 one that names no agent of the seat's template in its rig, or
#                 several, exits 4 naming them, each attaching nothing
#   (PO-ATTACH-FAIL, MK-ATTACH-FAIL) an attach that fails exits 4, naming the
#                 re-run and no return
#   (PO-ARGS, MK-ARGS) an argument or a flag the verb does not take exits 2 and
#                 calls nothing
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
SCRIPT_REAL="$(readlink -f "$SCRIPT" 2>/dev/null || printf '%s' "$SCRIPT")"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-seats-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()    { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# The session's own city must not reach a hermetic run.
unset GC_CITY_PATH GC_CITY GC_CITY_ROOT GC_RIG BEADS_DIR GC_HELM_FIXTURE GC_HELM_ASSUME_TTY GC_HELM_FORM_BIN || true
export CALLS="$TMP/calls"
mkdir -p "$TMP/bin" "$TMP/agents/converse-claude-opus"
export GC_HELM_AGENTS_DIR="$TMP/agents" TMPDIR="$TMP"

# The stub records each call on a line of its own. `gc agent list` prints the
# roster $ROSTER names, or exits $ROSTER_RC saying why when that is not 0.
# `gc session attach` exits $ATTACH_RC, saying why on stderr when that is not
# 0, as gc does; every other call is one the verbs must not make, so the stub
# fails it.
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" | tr '\n' ' ' >> "$CALLS"; printf '\n' >> "$CALLS"
case "$1 ${2:-}" in
  "agent list")
    [ "${ROSTER_RC:-0}" -eq 0 ] || { echo "gc agent list: loading city config failed" >&2; exit "$ROSTER_RC"; }
    cat "$ROSTER" ;;
  "session attach")
    [ "${ATTACH_RC:-0}" -eq 0 ] || echo "gc session attach: session ${3:-} did not start within 2m0s; not attaching" >&2
    exit "${ATTACH_RC:-0}" ;;
  *) echo "stub gc: unhandled: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gc"

# The conversation form's stand-in records the argv it was handed.
cat > "$TMP/bin/form-stub" <<'FORM'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done > "$FORM_ARGV_FILE"
echo "form-stub ran"
FORM
chmod +x "$TMP/bin/form-stub"
export FORM_ARGV_FILE="$TMP/form.argv"
export PATH="$TMP/bin:$PATH"

# The city's rigs, as gc-helm reads them through its fixture seam.
mkdir -p "$TMP/fixture"
cat > "$TMP/fixture/rigs.json" <<'RIGS'
[{"name":"town","path":"/city","prefix":"hq","hq":true,"suspended":false},
 {"name":"gc-toolkit","path":"/rigs/gc-toolkit","prefix":"tk","hq":false,"suspended":false},
 {"name":"paused","path":"/rigs/paused","prefix":"pz","hq":false,"suspended":true}]
RIGS

# The city's agent roster, as `gc agent list --json` gives it: the pack imported
# as gc-toolkit, with mechanik for the city and a po in each rig, the HQ aside,
# beside an agent of another name. The same city importing the pack as kit.
export ROSTER="$TMP/fixture/agents.json"
cat > "$ROSTER" <<'AGENTS'
{"city_name":"town","agents":[
 {"name":"mechanik","qualified_name":"gc-toolkit.mechanik","scope":"city"},
 {"name":"witness","qualified_name":"gc-toolkit/gc-toolkit.witness","dir":"gc-toolkit","scope":"rig"},
 {"name":"po","qualified_name":"gc-toolkit/gc-toolkit.po","dir":"gc-toolkit","scope":"rig"},
 {"name":"po","qualified_name":"paused/gc-toolkit.po","dir":"paused","scope":"rig"}]}
AGENTS
cat > "$TMP/fixture/agents-kit.json" <<'AGENTS'
{"city_name":"town","agents":[
 {"name":"mechanik","qualified_name":"kit.mechanik","scope":"city"},
 {"name":"po","qualified_name":"gc-toolkit/kit.po","dir":"gc-toolkit","scope":"rig"},
 {"name":"po","qualified_name":"paused/kit.po","dir":"paused","scope":"rig"}]}
AGENTS

# reset — no calls recorded and no form run.
reset() { : > "$CALLS"; rm -f "$FORM_ARGV_FILE"; }

# run <verb> [args...] -> RC/OUT/CALLED, CALLED being the calls in order, apart
# by '|'. stdin is /dev/null, so no terminal.
run() {
  set +e
  OUT="$(sh "$SCRIPT" "$@" </dev/null 2>"$TMP/err")"; RC=$?
  set -e
  OUT="$OUT$(cat "$TMP/err")"
  CALLED="$(paste -s -d'|' - < "$CALLS")"
}

echo "# a bare gc-helm opens engage's form on a terminal, and without one prints its usage"
reset
set +e
OUT="$(GC_HELM_ASSUME_TTY=1 GC_HELM_FORM_BIN="$TMP/bin/form-stub" sh "$SCRIPT" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 0 "(BARE) a bare gc-helm on a terminal runs the form"
eq "$(paste -s -d'|' - < "$FORM_ARGV_FILE" 2>/dev/null || true)" "form|--helm|$SCRIPT_REAL|--models|claude-opus" "(BARE) …as engage runs it, on starting a conversation, handed this script's path"
eq "$(cat "$CALLS")" "" "(BARE) …calling no gc first"
reset
set +e
OUT="$(GC_HELM_FORM_BIN="$TMP/bin/form-stub" sh "$SCRIPT" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 2 "(BARE-NOTTY) a bare gc-helm without a terminal exits 2"
has "$OUT" "name a verb" "(BARE-NOTTY) …asking for a verb"
has "$OUT" "a bare gc-helm opens engage's form" "(BARE-NOTTY) …saying what it does on a terminal"
has "$OUT" "gc-helm po --rig <name>  attach to the rig's Product Owner" "(BARE-NOTTY) …and printing the usage, the seats included"
eq "$(cat "$FORM_ARGV_FILE" 2>/dev/null || true)" "" "(BARE-NOTTY) …opening no form"
reset
set +e
OUT="$(GC_HELM_ASSUME_TTY=1 GC_HELM_FORM_BIN="$TMP/no-such-form" sh "$SCRIPT" </dev/null 2>&1)"; RC=$?
set -e
eq "$RC" 3 "(BARE-MISSING) with no form built a bare gc-helm exits 3"
has "$OUT" "no helm-svc binary is built" "(BARE-MISSING) …saying the form is not built"
has "$OUT" "gc-helm po --rig <name> to open a rig's Product Owner, gc-helm mechanik to attach to mechanik" "(BARE-MISSING) …naming the seats' commands"
has "$OUT" "gc-helm attach <conversation> to return" "(BARE-MISSING) …and the conversations' commands"

echo "# a seat's verb is Gas City's attach on the seat, by the name the roster gives it, and nothing else"
export GC_HELM_FIXTURE="$TMP/fixture"
reset; run po --rig gc-toolkit
eq "$RC" 0 "(PO) po exits 0 once the attach comes back"
eq "$CALLED" "agent list --json |session attach gc-toolkit/gc-toolkit.po " "(PO) …having read the roster and made one attach, on the rig's po by the name the roster gives it"
has "$OUT" "Return to the Product Owner of gc-toolkit with: gc-helm po --rig gc-toolkit" "(PO) …and naming how to return"
reset; run po --rig=gc-toolkit
eq "$CALLED" "agent list --json |session attach gc-toolkit/gc-toolkit.po " "(PO) --rig=<name> names the rig too"
reset; run mechanik
eq "$RC" 0 "(MK) mechanik exits 0 once the attach comes back"
eq "$CALLED" "agent list --json |session attach gc-toolkit.mechanik " "(MK) …having read the roster and made one attach, on mechanik's seat"
has "$OUT" "Return to mechanik with: gc-helm mechanik" "(MK) …and naming how to return"

echo "# a city that imports the pack under another name opens the same seats"
reset; ROSTER="$TMP/fixture/agents-kit.json" run po --rig gc-toolkit
eq "$RC" 0 "(KIT) po exits 0 under a city that imports the pack as kit"
eq "$CALLED" "agent list --json |session attach gc-toolkit/kit.po " "(KIT) …attaching to the rig's po under the name kit gives it"
has "$OUT" "Return to the Product Owner of gc-toolkit with: gc-helm po --rig gc-toolkit" "(KIT) …and naming how to return"
reset; ROSTER="$TMP/fixture/agents-kit.json" run mechanik
eq "$RC" 0 "(KIT) mechanik exits 0 there too"
eq "$CALLED" "agent list --json |session attach kit.mechanik " "(KIT) …attaching to kit.mechanik"

echo "# po names its rig, one the city has and that runs"
reset; run po
eq "$RC" 2 "(PO-RIG) po without --rig exits 2"
has "$OUT" "each rig has its own Product Owner, so name the rig: gc-helm po --rig <name>" "(PO-RIG) …saying so"
eq "$CALLED" "" "(PO-RIG) …and calling nothing"
reset; run po --rig
eq "$RC" 2 "(PO-RIG) --rig with no value exits 2"
reset; run po --rig tk
eq "$RC" 4 "(PO-RIG) a rig named by its prefix, not its name, exits 4"
has "$OUT" "--rig 'tk' matches no rig in 'gc rig list' (known: gc-toolkit, paused). Nothing attached." "(PO-RIG) …naming the rigs there are, the HQ left out"
eq "$CALLED" "" "(PO-RIG) …and attaching nothing"
reset; run po --rig town
eq "$RC" 4 "(PO-RIG) the city's HQ exits 4, since Gas City runs no rig's po there"
has "$OUT" "'town' is the city's HQ in 'gc rig list', not a rig" "(PO-RIG) …saying so"
has "$OUT" "so the HQ has no Product Owner. Name a rig: gc-toolkit, paused. Nothing attached." "(PO-RIG) …naming the rigs to choose from"
eq "$CALLED" "" "(PO-RIG) …and attaching nothing"
reset; run po --rig paused
eq "$RC" 4 "(PO-RIG) a suspended rig exits 4"
has "$OUT" "rig 'paused' is suspended" "(PO-RIG) …saying so"
has "$OUT" "gc rig resume paused" "(PO-RIG) …and naming the resume"
eq "$CALLED" "" "(PO-RIG) …and attaching nothing"

echo "# a seat the roster gives no one name is attached to by no name"
reset; ROSTER_RC=1 run po --rig gc-toolkit
eq "$RC" 4 "(SEAT-NAME) a roster that cannot be read exits 4"
has "$OUT" "could not read 'gc agent list', which gives the session of the Product Owner of gc-toolkit its name, so nothing was attached. Re-run: gc-helm po --rig gc-toolkit" "(SEAT-NAME) …saying so and naming the re-run"
eq "$CALLED" "agent list --json " "(SEAT-NAME) …and attaching nothing"
printf 'gc: warming up\n' > "$TMP/fixture/agents-garbled.json"
reset; ROSTER="$TMP/fixture/agents-garbled.json" run mechanik
eq "$RC" 4 "(SEAT-NAME) a roster that is not one exits 4 too"
has "$OUT" "could not read 'gc agent list', which gives the session of mechanik its name, so nothing was attached. Re-run: gc-helm mechanik" "(SEAT-NAME) …saying so"
eq "$CALLED" "agent list --json " "(SEAT-NAME) …and attaching nothing"
jq -c '.agents |= map(select(.dir != "gc-toolkit"))' "$ROSTER" > "$TMP/fixture/agents-nopo.json"
reset; ROSTER="$TMP/fixture/agents-nopo.json" run po --rig gc-toolkit
eq "$RC" 4 "(SEAT-NAME) a rig whose roster names no po exits 4, a po of another rig not counting"
has "$OUT" "'gc agent list' names no po agent in rig 'gc-toolkit', so the city runs no session for the Product Owner of gc-toolkit. Nothing attached." "(SEAT-NAME) …saying so"
eq "$CALLED" "agent list --json " "(SEAT-NAME) …and attaching nothing"
jq -c '.agents |= map(if .name == "mechanik" then . + {dir: "gc-toolkit", qualified_name: "gc-toolkit/gc-toolkit.mechanik"} else . end)' "$ROSTER" > "$TMP/fixture/agents-rigmk.json"
reset; ROSTER="$TMP/fixture/agents-rigmk.json" run mechanik
eq "$RC" 4 "(SEAT-NAME) a roster whose only mechanik is a rig's exits 4, since mechanik is the city's own"
has "$OUT" "'gc agent list' names no mechanik agent for the city, so the city runs no session for mechanik. Nothing attached." "(SEAT-NAME) …saying so"
eq "$CALLED" "agent list --json " "(SEAT-NAME) …and attaching nothing"
jq -c '.agents += [{name: "po", qualified_name: "gc-toolkit/kit.po", dir: "gc-toolkit", scope: "rig"}]' "$ROSTER" > "$TMP/fixture/agents-twopo.json"
reset; ROSTER="$TMP/fixture/agents-twopo.json" run po --rig gc-toolkit
eq "$RC" 4 "(SEAT-NAME) a rig whose roster names two po agents exits 4"
has "$OUT" "'gc agent list' names more than one po agent in rig 'gc-toolkit' (gc-toolkit/gc-toolkit.po, gc-toolkit/kit.po), so the session of the Product Owner of gc-toolkit is not known. Nothing attached." "(SEAT-NAME) …naming both"
eq "$CALLED" "agent list --json " "(SEAT-NAME) …and attaching nothing"

echo "# an attach that fails exits 4"
reset; ATTACH_RC=1 run po --rig gc-toolkit
eq "$RC" 4 "(PO-ATTACH-FAIL) an attach that fails exits 4"
has "$OUT" "did not start within 2m0s" "(PO-ATTACH-FAIL) …leaving gc's reason in view"
has "$OUT" "gc session attach gc-toolkit/gc-toolkit.po exited 1, so the Product Owner of gc-toolkit was not attached. Re-run: gc-helm po --rig gc-toolkit" "(PO-ATTACH-FAIL) …and naming the re-run"
hasnt "$OUT" "Return to" "(PO-ATTACH-FAIL) …and no return"
reset; ATTACH_RC=1 run mechanik
eq "$RC" 4 "(MK-ATTACH-FAIL) mechanik's attach that fails exits 4"
has "$OUT" "so mechanik was not attached. Re-run: gc-helm mechanik" "(MK-ATTACH-FAIL) …naming the re-run"

echo "# a seat's verb takes nothing else"
reset; run po --rig gc-toolkit now
eq "$RC" 2 "(PO-ARGS) an argument exits 2"
has "$OUT" "po takes no argument" "(PO-ARGS) …saying so"
eq "$CALLED" "" "(PO-ARGS) …and calling nothing"
reset; run po --bogus
eq "$RC" 2 "(PO-ARGS) an unknown flag exits 2"
has "$OUT" "po: unknown flag '--bogus'" "(PO-ARGS) …naming the flag"
eq "$CALLED" "" "(PO-ARGS) …and calling nothing"
reset; run mechanik now
eq "$RC" 2 "(MK-ARGS) an argument exits 2"
eq "$CALLED" "" "(MK-ARGS) …and calling nothing"
reset; run mechanik --rig gc-toolkit
eq "$RC" 2 "(MK-ARGS) --rig exits 2"
has "$OUT" "mechanik is one for the city" "(MK-ARGS) …saying why"
eq "$CALLED" "" "(MK-ARGS) …and calling nothing"
reset; run mechanik --bogus
eq "$RC" 2 "(MK-ARGS) an unknown flag exits 2"
eq "$CALLED" "" "(MK-ARGS) …and calling nothing"

echo
echo "gc-helm-seats: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
