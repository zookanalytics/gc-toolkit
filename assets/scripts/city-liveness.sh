#!/bin/sh
# city-liveness.sh — the single definition of the liveness flags read from
# `gc rig list --json`: whether a rig is suspended, and whether the city
# controller is running.
#
# Sourced (never executed) by gc-helm.sh (engage's guard) and gc-visit-open.sh
# (the note that a report will wait), so the two read the flags the same way
# and cannot drift. Each caller's enumerate_rigs projects the rig list into
# $RIGS with RIG_PROJECTION_JQ, and the readers below read $RIGS.
#
# `gc rig list --json` reports `running` on every row, and it answers a
# different question on each kind of row (gascity cmd/gc/cmd_rig.go):
#   - On the HQ row (hq=true) it is gc's probe of the city controller. The local
#     path, doRigList, pings the per-city controller socket (controllerAlive),
#     which a supervisor-hosted city answers in-process. The API path,
#     renderRigListFromAPI, asks controllerStatusForCity.
#   - On a rig row it is rigHasRunningAgent, which probes the session names the
#     rig's configured agents would have under the session template. It reads
#     false on an idle rig, which the reconciler still launches sessions in, and
#     it misses sessions named another way, such as bead-named pool sessions.
# So RIG_PROJECTION_JQ carries running on the HQ row only, and nothing here
# reads a rig row's.
#
# A flag gc does not report reads as empty, which is unknown: it refuses
# nothing and notes nothing.

# shellcheck disable=SC2034  # read by the scripts that source this file
RIG_PROJECTION_JQ='[.rigs[]? | {name, path, prefix, hq, suspended} + (if .hq == true then {running} else {} end)]'

# rig_suspended <rig-name> — "true" or "false" for the named rig in $RIGS, or
# empty when gc does not report the flag.
rig_suspended() {
    printf '%s' "${RIGS:-}" | jq -r --arg n "${1:-}" \
        'first(.[]? | select(.name == $n) | if .suspended == null then "" else (.suspended | tostring) end) // ""' 2>/dev/null || true
}

# city_controller_state — sets CONTROLLER_RUNNING to "true", "false", or empty
# (unknown), and CONTROLLER_SEEN to the readings behind a "false", for the
# caller's message.
#
# The HQ row's running decides "true" and unknown on its own. Its "false" counts
# only when `gc status --json` does not contradict it. The local controller
# probe is a socket ping with a 2s read timeout, which a loaded controller can
# miss. gc status reports controllerStatusForCity as .controller, and that asks
# the supervisor about a supervisor-hosted city before it falls back to the
# socket, so a missed ping alone cannot refuse an engage. A gc status that
# reports the controller running clears the HQ reading. One that reports it not
# running confirms it. One that gives no reading leaves it standing; that
# includes a supervisor that is up but cannot say (status "unknown"). gc status
# is asked only when the HQ row reads false.
# shellcheck disable=SC2034  # CONTROLLER_* are read by the scripts that source this file
city_controller_state() {
    CONTROLLER_RUNNING=""; CONTROLLER_SEEN=""
    _ccs_hq=$(printf '%s' "${RIGS:-}" | jq -r \
        'first(.[]? | select(.hq == true) | if .running == null then "" else (.running | tostring) end) // ""' 2>/dev/null || true)
    case "$_ccs_hq" in
        true) CONTROLLER_RUNNING=true; return 0 ;;
        false) ;;
        *) return 0 ;;
    esac

    if command -v timeout >/dev/null 2>&1; then
        _ccs_raw=$(timeout "${GC_CONTROLLER_STATUS_TIMEOUT:-15}" gc status --json 2>/dev/null || true)
    elif command -v gtimeout >/dev/null 2>&1; then
        _ccs_raw=$(gtimeout "${GC_CONTROLLER_STATUS_TIMEOUT:-15}" gc status --json 2>/dev/null || true)
    else
        _ccs_raw=$(gc status --json 2>/dev/null || true)
    fi
    # gc status exits 1 on a degraded snapshot but still prints its JSON, so the
    # exit status is not the reading. Output jq cannot parse gives no reading.
    _ccs_status=$(printf '%s' "$_ccs_raw" | jq -r '
        (.controller // {}) as $c
        | if ($c.running | type) != "boolean" then ""
          elif $c.running then "true"
          elif ($c.status // "") == "unknown" then ""
          else "false" + (if ($c.status // "") == "" then "" else " " + $c.status end) end' 2>/dev/null || true)
    case "$_ccs_status" in
        true)
            CONTROLLER_RUNNING=true ;;
        false*)
            CONTROLLER_RUNNING=false
            _ccs_word="${_ccs_status#false}"; _ccs_word="${_ccs_word# }"
            CONTROLLER_SEEN="the HQ row of 'gc rig list' and 'gc status' both report it not running${_ccs_word:+ (gc status: $_ccs_word)}" ;;
        *)
            CONTROLLER_RUNNING=false
            CONTROLLER_SEEN="the HQ row of 'gc rig list' reports it not running, and 'gc status' could not tell" ;;
    esac
}
