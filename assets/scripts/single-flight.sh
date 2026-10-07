#!/usr/bin/env bash
# single-flight.sh — serialise per-rig passes of a cadence order behind one flock.
# Sourced, never executed. The refinery-reconcile and epic-steward orders both use
# it so the acquire-and-stall-report logic lives in one place and the two cannot
# drift: a wedged pass is reported by both, not skipped silently by one.
#
# A caller resolves this file beside itself and sources it:
#   # shellcheck source=single-flight.sh
#   . "${GC_SINGLE_FLIGHT:-$SCRIPT_DIR/single-flight.sh}" || { echo "cannot source single-flight.sh" >&2; exit 1; }
#
# single_flight_acquire <state_dir> [stall_secs]
#   Opens fd 9 on <state_dir>/pass.lock in the CALLER's shell and takes a
#   non-blocking exclusive flock, so the arms the caller runs next inherit fd 9 and
#   hold the lock until the pass exits — the kernel releases it on any exit, SIGKILL
#   included. On winning the lock it records <state_dir>/pass.holder as "<pid>
#   <epoch>". It never exits the shell; it sets these and returns 0, leaving the
#   exit code and any logging to the caller:
#     SF_STATUS=held       this pass holds the lock — run the arms.
#     SF_STATUS=inflight   another live pass holds it — skip this tick (exit 0).
#     SF_STATUS=stalled    the holder is older than stall_secs: a prior pass is
#                          wedged (an arm still owns fd 9 after its driver is gone),
#                          so merges/visits have stopped — report it (exit non-zero),
#                          do not skip silently every tick.
#     SF_STATUS=unguarded  no usable flock (missing, or the lock file cannot be
#                          created or opened): nothing serialises the arms, so the
#                          caller must run none (exit non-zero).
#   SF_MSG is a one-line human description for the caller to print and log.
#   SF_HOLDER_INFO names the current holder ("pid N, Ms elapsed") for the skip/stall
#   cases, so a caller can log it in its own format.
#
# stall_secs defaults to 900. A holder whose timestamp is absent or unparseable is
# treated as a live pass (inflight), never stalled — a torn holder write must not
# promote a healthy pass to "wedged".

# SF_STATUS and SF_MSG are results the sourcing caller reads; shellcheck lints
# this file alone, so it cannot see that read and reports them unused.
# shellcheck disable=SC2034
single_flight_acquire() {
  _sf_state="$1"; _sf_stall="${2:-900}"
  SF_STATUS=""; SF_MSG=""; SF_HOLDER_INFO=""
  _sf_lock="$_sf_state/pass.lock"
  _sf_holder="$_sf_state/pass.holder"

  if ! command -v flock >/dev/null 2>&1; then
    SF_STATUS=unguarded; SF_MSG="flock not found on PATH"; return 0
  fi
  if ! ( : >> "$_sf_lock" ) 2>/dev/null; then
    SF_STATUS=unguarded; SF_MSG="cannot create $_sf_lock"; return 0
  fi
  if ! exec 9>>"$_sf_lock"; then
    SF_STATUS=unguarded; SF_MSG="cannot open $_sf_lock"; return 0
  fi
  if flock -n 9; then
    printf '%s %s\n' "$$" "$(date -u +%s)" > "$_sf_holder" 2>/dev/null || true
    SF_STATUS=held; return 0
  fi

  # Another pass holds the lock. Read its holder record to decide skip vs stalled.
  _sf_pid=""; _sf_since=""; _sf_elapsed=""
  [ -r "$_sf_holder" ] && read -r _sf_pid _sf_since < "$_sf_holder"
  case "$_sf_since" in
    ''|*[!0-9]*) ;;
    *) _sf_elapsed=$(( $(date -u +%s) - _sf_since )) ;;
  esac
  SF_HOLDER_INFO="pid ${_sf_pid:-unknown}"
  [ -n "$_sf_elapsed" ] && SF_HOLDER_INFO="$SF_HOLDER_INFO, ${_sf_elapsed}s elapsed"
  if [ -n "$_sf_elapsed" ] && [ "$_sf_elapsed" -gt "$_sf_stall" ]; then
    SF_STATUS=stalled
    SF_MSG="pass lock held ${_sf_elapsed}s (> ${_sf_stall}s) by $SF_HOLDER_INFO — the cadence is wedged and nothing is landing"
  else
    SF_STATUS=inflight
    SF_MSG="a pass is already in flight ($SF_HOLDER_INFO) — skipping this tick"
  fi
  return 0
}
