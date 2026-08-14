#!/usr/bin/env bash
# refinery-idle-arm.sh — arm a rig's refinery idle-cadence driver in its OWN
# systemd user unit, outside every agent session's cgroup (tk-agzpl).
#
# WHY THIS IS A SCRIPT AND NOT AN INSTRUCTION. `merge-skill.sh` fires only from
# the driver's cadence, so a driver that stops is a merge queue that stops, and
# the stall reports nothing: the rig is not suspended, the refinery is
# configured, the session list looks normal, and APPROVED+CLEAN PRs simply sit
# (gc-toolkit PR#345/#346 waited 7h+). Every part of arming it correctly is a
# step that has ALREADY been skipped by hand at least once on this host:
#
#   * armed with `setsid` (or a bare `&`) — an agent session's scope is
#     KillMode=control-group, so systemd SIGKILLs every process in the cgroup
#     when the session rotates. `setsid` changes the SESSION, not the CGROUP:
#     measured dead in ~8 minutes, and once as a 9h20m outage. A re-arm that
#     silently lapses is WORSE than a known-dead driver, because it converts a
#     visible gap into a false all-clear.
#   * armed with no --working-directory — a `--user` unit inherits
#     `WorkingDirectory=!$HOME`, which is not a git work tree, so
#     merge-skill.sh:773 fails closed on `git remote get-url origin` and prints
#     "NOTHING is merged this pass" forever while the unit reads active/running.
#   * armed with no --setenv — a `--user` unit does NOT inherit the launching
#     shell's environment. Its PATH has no ~/.local/bin, so `gc` exits 127 and
#     the passes read an unreadable ledger as an empty one.
#   * armed with no GC_AGENT — reconcile-graduated-convoys.sh:111 prints
#     "GC_AGENT unset; skip" and owned-convoy graduation never runs, on a driver
#     that looks perfectly healthy in every other respect.
#   * armed without Restart=always — the property is easy to drop on a re-arm
#     and nothing notices (the unit live on this host at the time of writing was
#     re-armed at 04:49 with Restart=no).
#
# Each of those produces a driver that LOOKS armed. Encoding them here is the
# difference between a remedy and a reminder.
#
# WHAT THIS DOES NOT DO: author idle-loop.sh. The driver on disk is the proven
# one — it holds the canonical lock, runs the full current pass set, and emits by
# fingerprint-inversion. Rewriting that filter from scratch is a trap that has
# been re-tripped six times. This script arms what is already there and refuses
# if it is not.
#
# The mechanism, the measurements, and the four liveness signals that look right
# and are not are written up in specs/tk-agzpl/refinery-idle-driver-liveness.md.
# doctor/check-refinery-idle-driver is the standing gate that finds the rigs
# needing this.
#
# Usage:
#   refinery-idle-arm.sh [--rig <rig>] [--agent <identity>] [--driver <path>]
#                        [--working-directory <dir>] [--wait <secs>]
#                        [--force] [--dry-run]
#
# Exit codes:
#   0  armed and verified, or already durably armed (idempotent no-op)
#   1  refused — a live driver or an unidentified lock holder needs a decision
#   2  failed — a precondition is missing, or the arm did not come up

set -u

PROG="refinery-idle-arm"

# Same seam the detector reads (doctor/check-refinery-idle-driver), so the two
# can never disagree about where a driver lives.
STATE_ROOT="${GC_REFINERY_IDLE_ROOT:-/tmp}"

RIG="${GC_RIG:-}"
AGENT=""
DRIVER=""
WORKDIR=""
WAIT_SECS=20
FORCE=""
DRY_RUN=""

die() { echo "$PROG: $1" >&2; exit "${2:-2}"; }
say() { echo "$PROG: $1"; }

usage() { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --rig)               RIG="${2:-}"; shift 2 ;;
        --agent)             AGENT="${2:-}"; shift 2 ;;
        --driver)            DRIVER="${2:-}"; shift 2 ;;
        --working-directory) WORKDIR="${2:-}"; shift 2 ;;
        --wait)              WAIT_SECS="${2:-}"; shift 2 ;;
        --force)             FORCE=yes; shift ;;
        --dry-run)           DRY_RUN=yes; shift ;;
        -h|--help)           usage; exit 0 ;;
        *)                   die "unknown argument '$1' (try --help)" 2 ;;
    esac
done

[ -n "$RIG" ] || die "no rig: pass --rig <rig> or set GC_RIG" 2
case "$WAIT_SECS" in ''|*[!0-9]*) die "--wait wants whole seconds, got '$WAIT_SECS'" 2 ;; esac

STATE_DIR="$STATE_ROOT/gc-refinery-idle-$RIG"
[ -n "$DRIVER" ] || DRIVER="$STATE_DIR/idle-loop.sh"
LOCK="$STATE_DIR/lock"
LOG="$STATE_DIR/reconcile.log"
UNIT="gc-refinery-idle-$RIG.service"

# ---------------------------------------------------------------------------
# Preconditions.
# ---------------------------------------------------------------------------
command -v systemd-run >/dev/null 2>&1 || die "systemd-run is not on PATH; this host cannot hold a driver outside a session cgroup, and every other arming form dies with the session that ran it" 2
command -v systemctl   >/dev/null 2>&1 || die "systemctl is not on PATH" 2

[ -f "$DRIVER" ] || die "no driver at $DRIVER. This script arms the proven on-disk driver; it does not author one. Copy a sibling rig's idle-loop.sh, adjust its RIG/AGENT/SCRIPTS_DIR/CWD header, and re-run." 2
[ -x "$DRIVER" ] || die "$DRIVER is not executable (chmod +x it)" 2

HOLDER_TOOL=""
if command -v fuser >/dev/null 2>&1; then HOLDER_TOOL="fuser"
elif command -v lsof >/dev/null 2>&1; then HOLDER_TOOL="lsof"
fi
[ -n "$HOLDER_TOOL" ] || die "neither fuser nor lsof is on PATH, and lock HOLDER-ship is the only sound liveness test — the lock FILE outlives a killed driver as a 0-byte orphan. Refusing to arm blind: a second driver would be a second merge-skill writer." 2

# Rig root, from the roster rather than a path guess.
RIG_ROOT=""
if command -v gc >/dev/null 2>&1; then
    RIG_ROOT=$(gc rig list --json 2>/dev/null | jq -r --arg r "$RIG" '.rigs[]? | select((.name // "") == $r) | (.path // "")' 2>/dev/null | head -1)
fi
[ -n "$RIG_ROOT" ] || RIG_ROOT="${GC_CITY_PATH:-}/rigs/$RIG"
[ -d "$RIG_ROOT" ] || die "cannot resolve rig '$RIG' to a checkout (tried the roster, then \${GC_CITY_PATH}/rigs/$RIG)" 2

# The refinery's canonical identity. Passing the CALLER's GC_AGENT would stamp a
# polecat (or another rig's refinery) onto every convoy graduation this driver
# performs, so it is always resolved for the TARGET rig and overridden below.
if [ -z "$AGENT" ] && command -v gc >/dev/null 2>&1; then
    AGENT=$(gc agent list --json 2>/dev/null | jq -r --arg r "$RIG/" '
        .agents[]? | select((.name // "") == "refinery")
        | (.qualified_name // "") | select(startswith($r))' 2>/dev/null | head -1)
fi
if [ -z "$AGENT" ]; then
    echo "$PROG: WARNING could not resolve rig '$RIG''s refinery identity; arming with GC_AGENT unset. reconcile-graduated-convoys.sh:111 will print 'GC_AGENT unset; skip' on EVERY tick and owned-convoy graduation will never run — pass --agent <rig>/<binding>.refinery to close that." >&2
fi

# ---------------------------------------------------------------------------
# Working directory. The unit MUST land in a git work tree: the merge passes all
# resolve the target repository through `git remote get-url origin` and fail
# CLOSED without it, which is a driver that ticks forever and merges nothing.
# ---------------------------------------------------------------------------
if [ -z "$WORKDIR" ]; then
    for cand in "${GC_CITY_PATH:-}/.gc/worktrees/$RIG/refinery" "$RIG_ROOT"; do
        if [ -n "$cand" ] && git -C "$cand" rev-parse --git-dir >/dev/null 2>&1; then
            WORKDIR="$cand"; break
        fi
    done
fi
[ -n "$WORKDIR" ] || die "no git work tree to run the driver in (tried the refinery worktree, then $RIG_ROOT). Without one the merge passes fail closed on every tick and merge NOTHING, silently." 2
git -C "$WORKDIR" rev-parse --git-dir >/dev/null 2>&1 \
    || die "--working-directory '$WORKDIR' is not a git work tree; merge-skill.sh:773 fails closed there and the driver would tick forever without merging" 2
git -C "$WORKDIR" remote get-url origin >/dev/null 2>&1 \
    || die "'$WORKDIR' is a git work tree with no 'origin' remote; the merge passes cannot name the repository to merge in and would refuse on every tick" 2

# ---------------------------------------------------------------------------
# Current state of the lock.
# ---------------------------------------------------------------------------
lock_holders() {
    [ -e "$LOCK" ] || return 0
    case "$HOLDER_TOOL" in
        fuser) fuser "$LOCK" 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+$' ;;
        lsof)  lsof -t -- "$LOCK" 2>/dev/null | grep -E '^[0-9]+$' ;;
    esac
}
pid_args()   { ps -o args= -p "$1" 2>/dev/null | head -1; }
pid_cgroup() { ps -o cgroup= -p "$1" 2>/dev/null | head -1; }

driver_pid=""
foreign_pids=""
while read -r pid; do
    [ -n "$pid" ] || continue
    args=$(pid_args "$pid")
    case "$args" in
        *"$DRIVER"*) [ -n "$driver_pid" ] || driver_pid="$pid" ;;
        "")          : ;;
        *)           foreign_pids="${foreign_pids:+$foreign_pids }$pid" ;;
    esac
done <<< "$(lock_holders)"

if [ -n "$foreign_pids" ] && [ -z "$driver_pid" ]; then
    echo "$PROG: REFUSING — $LOCK is held by pid(s) $foreign_pids, none of which is $DRIVER." >&2
    echo "$PROG: arming now would start a unit that takes no lock, exits 0 immediately, and looks like success. Identify those processes first:" >&2
    for p in $foreign_pids; do echo "  pid $p: $(pid_args "$p")" >&2; done
    exit 1
fi

if [ -n "$driver_pid" ]; then
    cg=$(pid_cgroup "$driver_pid")
    case "$cg" in
        *"$UNIT"*)
            restart=$(systemctl --user show "$UNIT" -p Restart 2>/dev/null | sed -n 's/^Restart=//p')
            if [ "$restart" = "always" ] && [ -z "$FORCE" ]; then
                say "already armed: pid $driver_pid holds $LOCK in $UNIT (Restart=always). Nothing to do."
                exit 0
            fi
            if [ -z "$FORCE" ]; then
                say "already armed: pid $driver_pid holds $LOCK in $UNIT, but Restart='${restart:-unset}' — a genuine crash would not be recovered."
                say "Re-arm with --force to restore Restart=always (this stops the live driver for a moment; nothing is lost, the next tick re-reads everything)."
                exit 0
            fi
            say "--force: replacing the live driver in $UNIT (pid $driver_pid, Restart='${restart:-unset}')"
            ;;
        *)
            if [ -z "$FORCE" ]; then
                echo "$PROG: REFUSING — a driver is ALIVE (pid $driver_pid) but in cgroup '${cg:-unknown}', not $UNIT." >&2
                echo "$PROG: it is merging right now and will be SIGKILLed at the next session rotation. Replacing it is the fix, but it is a live merge writer, so say so explicitly: re-run with --force." >&2
                exit 1
            fi
            say "--force: replacing an alive-but-doomed driver (pid $driver_pid, cgroup '${cg:-unknown}')"
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# The environment the unit needs. A --user unit inherits the systemd user
# manager's environment, not the caller's, so every variable is passed
# explicitly. Session-scoped keys are dropped: a driver that outlives its
# launcher must not carry that launcher's identity.
# ---------------------------------------------------------------------------
SESSION_SCOPED=" GC_SESSION_ID GC_SESSION_NAME GC_SESSION_ORIGIN GC_CONTINUATION_EPOCH GC_RUNTIME_EPOCH GC_STARTUP_PROMPT_DELIVERED GC_READY_PROMPT_PREFIX GC_TEMPLATE GC_DIR GC_ALIAS GC_BEAD_ID "
# Resolved per-rig below, so a caller's own values can never leak in.
RIG_SCOPED=" GC_RIG GC_RIG_ROOT GC_AGENT BEADS_DIR "

setenv_args=()
for k in $(compgen -e | sort); do
    case "$k" in
        # Whatever bead dispatched the CALLER. Carried into a driver that
        # outlives them, it is a stale id pointing at finished work.
        GC_TRIGGER_*) continue ;;
        BEADS_*|GC_*) ;;
        *) continue ;;
    esac
    case "$SESSION_SCOPED" in *" $k "*) continue ;; esac
    case "$RIG_SCOPED"     in *" $k "*) continue ;; esac
    setenv_args+=("--setenv=$k=${!k}")
done
for k in PATH HOME USER LANG; do
    [ -n "${!k:-}" ] && setenv_args+=("--setenv=$k=${!k}")
done
setenv_args+=("--setenv=GC_RIG=$RIG")
setenv_args+=("--setenv=GC_RIG_ROOT=$RIG_ROOT")
setenv_args+=("--setenv=BEADS_DIR=$RIG_ROOT/.beads")
[ -n "$AGENT" ] && setenv_args+=("--setenv=GC_AGENT=$AGENT")

# The tools the passes shell out to, checked against the PATH being handed over
# rather than the one this shell happens to have. `gc` missing here is the 127
# that reads an unreadable ledger as an empty queue.
missing=""
for tool in gc bd gh jq flock git; do
    command -v "$tool" >/dev/null 2>&1 || missing="${missing:+$missing }$tool"
done
[ -n "$missing" ] && echo "$PROG: WARNING these tools are not resolvable on the PATH being passed to the unit: $missing. The passes shell out to them; a missing one exits 127 and its pass reads as 'nothing to do'." >&2

RUN_ARGS=(
    systemd-run --user --unit="$UNIT"
    --property=Restart=always
    --property=RestartSec=15
    --working-directory="$WORKDIR"
    ${setenv_args[@]+"${setenv_args[@]}"}
    "$DRIVER"
)

if [ -n "$DRY_RUN" ]; then
    say "--dry-run: would run"
    printf '  %q' "${RUN_ARGS[@]}"; echo
    exit 0
fi

# ---------------------------------------------------------------------------
# Clear the way, then arm. Both steps matter: `systemd-run --unit=<name>` fails
# if that unit already exists in any state, and a driver still holding the lock
# makes the new unit exit 0 without ever taking it — which looks like success.
# ---------------------------------------------------------------------------
systemctl --user stop "$UNIT" >/dev/null 2>&1 || true
systemctl --user reset-failed "$UNIT" >/dev/null 2>&1 || true

if [ -n "$driver_pid" ]; then
    # Kill the driver AND the holders it spawned. The driver holds the lock on
    # FD 9 for its whole life, so every child it forks — each reconcile pass, and
    # the interval `sleep` — INHERITS that descriptor and keeps the flock alive
    # after the parent is gone. Killing only the parent leaves the lock held for
    # up to a full interval, and the new unit would exit 0 without taking it.
    #
    # Exactly the holder set read BEFORE the kill, and by NUMERIC pid. Never
    # `pkill -f "$DRIVER"`: that matches every argv containing the path,
    # including this script's own command line, so it signals its own shell and
    # dies mid-run with the teardown half-done. Re-reading the set here would
    # also be wrong — a holder that appears after the kill is somebody else's
    # new driver, and killing it is not this script's call.
    for p in $driver_pid $foreign_pids; do
        kill "$p" 2>/dev/null || true
    done
    waited=0
    while [ "$waited" -lt 15 ]; do
        [ -n "$(lock_holders)" ] || break
        sleep 1; waited=$((waited + 1))
    done
    still=$(lock_holders | tr '\n' ' ')
    [ -z "${still// /}" ] || die "$LOCK is still held by pid(s) ${still% } after ${waited}s of teardown; not arming a second merge-skill writer" 2
fi

log_before=0
[ -f "$LOG" ] && log_before=$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')

"${RUN_ARGS[@]}" >/dev/null 2>&1 || die "systemd-run failed to start $UNIT (see: systemctl --user status $UNIT)" 2

# ---------------------------------------------------------------------------
# Verify. `ActiveState=active` proves only that systemd started something: the
# driver exits 0 when the lock is taken, and a unit whose passes all fail closed
# reads active/running forever. Accept on the lock and the cgroup.
# ---------------------------------------------------------------------------
main_pid=""
waited=0
while [ "$waited" -le "$WAIT_SECS" ]; do
    main_pid=$(systemctl --user show "$UNIT" -p MainPID 2>/dev/null | sed -n 's/^MainPID=//p')
    [ -n "$main_pid" ] && [ "$main_pid" != "0" ] && grep -qxF "$main_pid" <<< "$(lock_holders)" && break
    main_pid=""
    sleep 1; waited=$((waited + 1))
done

if [ -z "$main_pid" ]; then
    state=$(systemctl --user show "$UNIT" -p ActiveState -p SubState 2>/dev/null | tr '\n' ' ')
    die "armed $UNIT but its MainPID never took $LOCK within ${WAIT_SECS}s ($state). A driver that does not hold the lock is not the cadence — check: systemctl --user status $UNIT" 2
fi

cg=$(pid_cgroup "$main_pid")
case "$cg" in
    *"$UNIT"*) : ;;
    *) die "armed $UNIT but its MainPID $main_pid reports cgroup '${cg:-unknown}' — not the unit's own. It is inside somebody's scope and will be killed with it; that is the whole failure this script exists to prevent." 2 ;;
esac

say "armed: $UNIT MainPID $main_pid holds $LOCK, cgroup $cg, Restart=always, WorkingDirectory=$WORKDIR"

# Log content is the only acceptance test for what the driver DOES, and a full
# pass takes minutes — longer than any sane --wait. Report what was seen and
# name the command rather than blocking or, worse, implying it passed.
log_after=0
[ -f "$LOG" ] && log_after=$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')
if [ "$log_after" -gt "$log_before" ] && [ -n "$(tail -c "+$((log_before + 1))" "$LOG" 2>/dev/null | grep -F 'cannot resolve' | head -1)" ]; then
    echo "$PROG: WARNING the driver's first output already contains 'cannot resolve' — its passes are failing closed and it will merge NOTHING while reading active/running. Check the working directory and PATH above." >&2
    exit 2
fi
say "acceptance test (a full pass takes minutes, so it is not waited on here): tail -40 $LOG"
say "  want: every pass named with real content, and ZERO 'cannot resolve' lines."
exit 0
