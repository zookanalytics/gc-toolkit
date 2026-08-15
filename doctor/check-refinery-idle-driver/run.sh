#!/usr/bin/env bash
# Pack doctor check: every rig that can merge has a LIVE, DURABLE refinery idle
# driver (tk-agzpl).
#
# WHAT THE DRIVER IS. `mol-refinery-patrol`'s find-work step is a cadence
# contract — `sleep {{event_timeout}}`, re-scan, repeat — and `merge-skill.sh`
# fires only from that cadence. In this harness the cadence is implemented
# out-of-band by a per-rig driver at
#
#     <state-dir>/idle-loop.sh          (state dir: /tmp/gc-refinery-idle-<rig>)
#
# holding <state-dir>/lock for its whole life. A live refinery AGENT runs the
# same passes inline, but only while it happens to be awake in find-work. So the
# driver, not the session, is what lands approved work on a cadence.
#
# THE DEFECT. When that driver dies, nothing reports it. gc-toolkit PR#345 and
# PR#346 were reviewDecision=APPROVED and mergeStateStatus=CLEAN from
# 2026-08-13T19:36Z and sat unlanded for over seven hours; the rig was not
# suspended, the refinery was configured, `gc doctor` passed 148 checks, and no
# witness escalation, mail, or bead existed. The driver's last tick was
# 2026-08-13T17:38:40Z. One nudge landed both PRs within ~14 minutes, so the
# work was merge-ready the whole time and only the server was missing. The stall
# is silent by construction and is discovered hours later by a human noticing
# that approved PRs are not merging.
#
# WHY IT DIES. Not a crash and not a self-exit. Every agent session runs inside
# a systemd scope cgroup (`…/tmux-spawn-<uuid>.scope`) whose KillMode is
# control-group, so systemd SIGKILLs every process in that cgroup when the scope
# stops. `setsid` changes the SESSION, not the CGROUP — a setsid-armed driver is
# still in the launching session's cgroup and dies at the next rotation (measured
# twice: ~8 min once, 9h20m of outage the other). That makes ALIVE-IN-A-SESSION-
# SCOPE a third state, distinct from both alive and dead: it is working right now
# and is guaranteed to stop, unreported, at a moment nobody will connect to it.
#
# THE FOUR FALSE-GREENS THIS CHECK REFUSES TO USE. Each was confirmed against a
# live example on the host that filed the bead, not theorised:
#
#   1. `gc session list` — a live refinery session with a dead driver is
#      indistinguishable from a healthy one. Session presence is CORRELATED
#      (the driver dies with the session that armed it) but is not the test.
#   2. `gc rig status` agent lines — "unknown (partial status)" is what a merely
#      not-running agent reports, so it cannot separate configured-and-idle from
#      configured-and-dead.
#   3. reconcile.log / driver.out mtime — wrong in BOTH directions. reconcile.log
#      was written at 03:15 by the refinery AGENT running the passes inline
#      minutes AFTER the driver died (false green); and driver.out went stale at
#      03:15 while a healthy re-armed driver logged only to reconcile.log (false
#      red). Any detector keyed on one file's mtime is wrong both ways.
#   4. lock file EXISTENCE — a SIGKILLed driver orphans its lock as a 0-byte file
#      with no holder, so `[ -f lock ]` reports "armed" forever.
#
# WHAT IS ASSERTED, per rig that is not suspended and has a refinery configured:
# the lock is HELD, by a process whose command line is that rig's own
# idle-loop.sh, in a cgroup that is the driver's own systemd unit. Holder-ness is
# read with `fuser`/`lsof` (read-only). The lock is never TAKEN to test it —
# taking it for even a moment would trip the duplicate-arm guard of a driver
# arming at that instant and make this check the cause of the outage it looks for.
#
# WHY THE COMMAND LINE AND NOT MERELY A HOLDER. The driver holds the lock on FD 9
# for its whole life, so every child it forks — each reconcile pass, and the
# interval `sleep` — inherits that descriptor and is also a holder. A live
# gc-toolkit lock routinely reads seven pids, three of which are the driver and
# its subshells and four of which are pass scripts. "Someone holds it" is
# therefore satisfied for up to one interval AFTER the driver dies, by its own
# orphaned children. Only a holder whose argv is this rig's idle-loop.sh counts.
#
# ALSO ASSERTED, on a driver that IS durably armed: that its unit has a
# WorkingDirectory which is a git work tree WITH an `origin` remote.
# `systemd-run --user` units inherit `WorkingDirectory=!/home/zook`, which is not
# a repo, and merge-skill.sh:773 then fails closed on `git remote get-url origin`
# and prints "NOTHING is merged this pass" on every tick while the unit reads
# active/running. A repo with NO origin fails at that same line for the same
# reason — the passes cannot name the repository to merge in — and so do
# pre-open-resolve.sh:105, reconcile-merged-prs.sh:235,
# reconcile-gate-verdicts.sh:189 and check-set-heal.sh:562. The two are one
# defect wearing two faces, and refinery-idle-arm.sh:159-162 refuses to arm into
# either; a detector that accepted one of them would call a rig healthy and then
# send its operator to a remedy that refuses that very state. A driver that
# ticks forever and merges nothing is worse than a dead one, and it is the exact
# shape — merge-ready work, silent host — this check exists to end.
#
# SEVERITY. A dead driver is the defect on its own, whether or not work is queued
# at this instant: the stall is silent, so the cost is set by when someone
# happens to look, not by the queue depth now. Merge-ready PRs (APPROVED and
# CLEAN) ESCALATE a dead rig to an error rather than triggering it. That probe
# runs only for a rig already found unhealthy, so a green host makes no network
# call.
#
# WHAT IS NOT ASSERTED. A suspended rig (exempt — nothing should be merging).
# A rig with no refinery agent. Whether the driver's passes are CORRECT — this
# is a liveness check, and `reconcile.log` content is the acceptance test for a
# freshly armed driver, which belongs to whoever armed it.
#
# THE REMEDY is assets/scripts/refinery-idle-arm.sh, which arms the driver in its
# own systemd user unit with the environment those passes need. Do not re-arm
# with `setsid` or a bare `&` from inside an agent session: per the mechanism
# above that cannot survive, and a re-arm that silently lapses is worse than a
# known-dead driver because it converts a visible gap into a false all-clear.
# For a rig reported here as ALIVE-but-degraded (the WorkingDirectory warnings
# below), that remedy needs `--force`: the arm re-checks the live unit's
# properties and refuses to replace a live merge writer on its own say-so, so a
# bare re-run reports the same degradation instead of fixing it.
#
# The investigation behind every assertion here — the measurements, and the two
# hypotheses their own authors retracted — is written up in
# specs/tk-agzpl/refinery-idle-driver-liveness.md. Read it before relaxing any
# of these probes into a cheaper one.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

# The driver's state-dir root. `/tmp` is where the drivers live today; the
# override is the single seam for relocating them somewhere a reboot does not
# erase (a known residual — a reboot removes idle-loop.sh and the unit then
# fails to start). refinery-idle-arm.sh reads the same variable, so the detector
# and the remedy can never disagree about where to look.
STATE_ROOT="${GC_REFINERY_IDLE_ROOT:-/tmp}"

# `gc doctor` applies no timeout to pack checks, so an unbounded probe against a
# wedged control plane would hang the whole doctor run.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

errors=()
warnings=()
notes=()

run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$BOUND" "$@" </dev/null
    else
        # No coreutils timeout (some macOS hosts). Degrade to an unbounded call
        # rather than skipping the check entirely.
        "$@" </dev/null
    fi
}

# `printf '%s\n' "${arr[@]}"` with an EMPTY array still prints a blank line,
# which reads as an unexplained detail row in doctor output. Print nothing.
print_lines() { [ "$#" -eq 0 ] || printf '%s\n' "$@"; }

# ---------------------------------------------------------------------------
# Host probes. Each is one external command so the whole surface is fakeable
# through PATH, and each degrades to empty rather than to a wrong answer.
# ---------------------------------------------------------------------------

# PIDs holding a file open, one per line. READ-ONLY on purpose: `flock -n` would
# answer the same question by TAKING the lock, and a driver arming in that window
# would see contention and exit.
HOLDER_TOOL=""
if command -v fuser >/dev/null 2>&1; then
    HOLDER_TOOL="fuser"
elif command -v lsof >/dev/null 2>&1; then
    HOLDER_TOOL="lsof"
fi

lock_holders() { # lock_holders <path>
    [ -e "$1" ] || return 0
    case "$HOLDER_TOOL" in
        # fuser prints PIDs space-separated on stdout and everything else on
        # stderr.
        fuser) run_bounded fuser "$1" 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+$' ;;
        lsof)  run_bounded lsof -t -- "$1" 2>/dev/null | grep -E '^[0-9]+$' ;;
        *)     return 0 ;;
    esac
}

pid_args()   { ps -o args= -p "$1" 2>/dev/null | head -1; }
pid_cgroup() { ps -o cgroup= -p "$1" 2>/dev/null | head -1; }

# Both WorkingDirectory probes are git questions. Without git they are skipped
# rather than answered wrongly — the same degrade-to-empty rule every other probe
# here follows.
HAVE_GIT=""
command -v git >/dev/null 2>&1 && HAVE_GIT="yes"

unit_working_directory() { # unit_working_directory <unit>
    command -v systemctl >/dev/null 2>&1 || return 0
    run_bounded systemctl --user show "$1" -p WorkingDirectory 2>/dev/null \
        | sed -n 's/^WorkingDirectory=//p' | head -1
}

# Open PRs that are merge-ready by the mayor's definition: APPROVED review
# decision and a CLEAN merge state. Only ever called for a rig already found
# unhealthy.
merge_ready_prs() { # merge_ready_prs <rig-path>
    command -v gh >/dev/null 2>&1 || return 0
    [ -d "$1" ] || return 0
    ( cd "$1" 2>/dev/null || exit 0
      run_bounded gh pr list --state open --limit 100 \
          --json number,reviewDecision,mergeStateStatus 2>/dev/null ) \
        | jq -r '.[]? | select((.reviewDecision // "") == "APPROVED")
                      | select((.mergeStateStatus // "") == "CLEAN")
                      | "#\(.number)"' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Rig roster. `gc rig list --json` reports EFFECTIVE suspension (runtime state,
# not just the config's suspended_on_start), which is what the exemption needs.
# ---------------------------------------------------------------------------
rigs_json=$(run_bounded gc rig list --json 2>/dev/null)
rig_rows=$(printf '%s' "$rigs_json" | jq -r '
    .rigs[]?
    | select((.hq // false) | not)
    | [(.name // ""), ((.suspended // false) | tostring), (.path // "")]
    | @tsv' 2>/dev/null)

if [ -z "$rig_rows" ]; then
    echo "cannot determine refinery idle driver liveness"
    echo "\`gc rig list --json\` returned no usable rig roster (timeout ${BOUND}s, or schema drift); there is no set of rigs to probe."
    exit 1
fi

if [ -z "$HOLDER_TOOL" ]; then
    echo "cannot determine refinery idle driver liveness"
    echo "Neither \`fuser\` nor \`lsof\` is on PATH, and lock HOLDER-ship is the only sound liveness test — the lock FILE survives the driver as a 0-byte orphan, and every other cheap signal (session list, log mtime) is a confirmed false-green."
    echo "Install psmisc (fuser) or lsof on this host, or run this check where the drivers live."
    exit 1
fi

# ---------------------------------------------------------------------------
# Which rigs have a refinery at all. A rig with none should not be merging, so
# it wants no driver. If the roster is unreadable, evaluate every rig and SAY SO
# rather than skipping: a wrong quiet answer here reproduces the outage.
# ---------------------------------------------------------------------------
agents_json=$(run_bounded gc agent list --json 2>/dev/null)
refinery_rigs=$(printf '%s' "$agents_json" | jq -r '
    .agents[]?
    | select((.name // "") == "refinery")
    | (.qualified_name // "")
    | select(contains("/"))
    | split("/")[0]' 2>/dev/null)
refinery_roster_readable="yes"
if [ -z "$refinery_rigs" ]; then
    refinery_roster_readable=""
    notes+=("refinery roster unreadable: \`gc agent list --json\` named no rig-scoped refinery (timeout ${BOUND}s, or schema drift). Every non-suspended rig below was probed as if it has one; a rig that genuinely has no refinery would be reported here as a false finding.")
fi

has_refinery() { # has_refinery <rig>
    [ -n "$refinery_roster_readable" ] || return 0
    grep -qxF -- "$1" <<< "$refinery_rigs"
}

# ---------------------------------------------------------------------------
# Per-rig evaluation.
# ---------------------------------------------------------------------------
checked=0
healthy=0
skipped_suspended=0
skipped_no_refinery=0
unhealthy=()   # rig<TAB>state<TAB>detail — merge-readiness is probed after

while IFS=$'\t' read -r rig suspended rig_path; do
    [ -n "$rig" ] || continue

    if [ "$suspended" = "true" ]; then
        skipped_suspended=$((skipped_suspended + 1))
        continue
    fi
    if ! has_refinery "$rig"; then
        skipped_no_refinery=$((skipped_no_refinery + 1))
        continue
    fi

    checked=$((checked + 1))
    state_dir="$STATE_ROOT/gc-refinery-idle-$rig"
    driver="$state_dir/idle-loop.sh"
    lock="$state_dir/lock"

    # Holders of the lock, split into "is this rig's driver" and "something else".
    driver_pid=""
    foreign_pids=""
    while read -r pid; do
        [ -n "$pid" ] || continue
        args=$(pid_args "$pid")
        case "$args" in
            *"$driver"*) [ -n "$driver_pid" ] || driver_pid="$pid" ;;
            "")          : ;;  # exited between the listing and the read
            *)           foreign_pids="${foreign_pids:+$foreign_pids }$pid" ;;
        esac
    done <<< "$(lock_holders "$lock")"

    if [ -z "$driver_pid" ]; then
        if [ ! -f "$driver" ]; then
            unhealthy+=("$rig	ABSENT	no driver at $driver — this rig has never had a merge cadence, so approved work lands only while a refinery session happens to be awake in find-work")
        elif [ -e "$lock" ]; then
            unhealthy+=("$rig	DEAD	$driver is on disk and $lock EXISTS BUT IS UNHELD — the orphaned lock of a killed driver (its existence is the false-green; only holder-ship is the test)")
        else
            unhealthy+=("$rig	DEAD	$driver is on disk but was never armed (no lock file, no holder)")
        fi
        [ -n "$foreign_pids" ] && notes+=("$rig: $lock is held by pid(s) $foreign_pids, none of which is $driver. Most likely the just-killed driver's own children — each reconcile pass and the interval \`sleep\` INHERIT the driver's FD 9 and keep the flock alive for up to one interval after it dies. They clear on their own; until they do, an arm exits 0 without taking the lock and looks successful. If they persist, identify them before re-arming.")
        continue
    fi

    # Alive. Durable, or alive-but-doomed?
    cgroup=$(pid_cgroup "$driver_pid")
    unit="gc-refinery-idle-$rig.service"
    case "$cgroup" in
        *"$unit"*)
            # systemd reports the value with its `-` (ignore-failure) and `!`
            # (privileged) prefixes still attached; both name the same directory.
            # Stripped exactly as refinery-idle-arm.sh:223 strips them, so a
            # prefixed path is judged as the path it is rather than reported as a
            # missing repo, and so the detector and the remedy can never disagree
            # about which directory they are looking at.
            wd=$(unit_working_directory "$unit"); wd=${wd#-}; wd=${wd#!}
            if [ -z "$wd" ]; then
                warnings+=("$rig: driver ALIVE in $unit (pid $driver_pid), but its WorkingDirectory is unset or unreadable. A --user unit inherits \`WorkingDirectory=!\$HOME\`, which is not a git work tree; merge-skill.sh:773 then fails closed on \`git remote get-url origin\` and merges NOTHING on every tick while the unit reads active/running. Re-arm with assets/scripts/refinery-idle-arm.sh --rig $rig --force, which passes --working-directory (--force because that driver is live: the arm reports the degradation and refuses to replace a live driver without it).")
            elif [ -n "$HAVE_GIT" ] && ! git -C "$wd" rev-parse --git-dir >/dev/null 2>&1; then
                warnings+=("$rig: driver ALIVE in $unit (pid $driver_pid) but its WorkingDirectory '$wd' is NOT a git work tree — merge-skill.sh:773 fails closed there and prints 'NOTHING is merged this pass' every tick, silently, while the unit reads active/running. Re-arm with assets/scripts/refinery-idle-arm.sh --rig $rig --force (--force because that driver is live: the arm reports the degradation and refuses to replace a live driver without it).")
            elif [ -n "$HAVE_GIT" ] && ! git -C "$wd" remote get-url origin >/dev/null 2>&1; then
                warnings+=("$rig: driver ALIVE in $unit (pid $driver_pid) and its WorkingDirectory '$wd' IS a git work tree, but it has no 'origin' remote — so the merge passes cannot name the repository to merge in and refuse on every tick. merge-skill.sh:773 fails closed at the same line an absent repo fails at, as do pre-open-resolve.sh:105, reconcile-merged-prs.sh:235, reconcile-gate-verdicts.sh:189 and check-set-heal.sh:562: nothing merges, silently, while the unit reads active/running. Re-arm with assets/scripts/refinery-idle-arm.sh --rig $rig --force, which validates the working directory against this same rule before arming (--force because that driver is live: the arm reports the degradation and refuses to replace a live driver without it).")
            else
                healthy=$((healthy + 1))
            fi
            ;;
        *.scope*)
            unhealthy+=("$rig	DOOMED	driver ALIVE (pid $driver_pid) but running in session scope '$cgroup', not $unit — that scope is KillMode=control-group, so systemd SIGKILLs it at the next session rotation and the outage starts there, hours before anyone connects the two")
            ;;
        "")
            healthy=$((healthy + 1))
            notes+=("$rig: driver ALIVE (pid $driver_pid) holding $lock, but \`ps -o cgroup=\` returned nothing on this host, so durability is UNVERIFIED — if it was armed from inside an agent session it will die at the next rotation.")
            ;;
        *)
            healthy=$((healthy + 1))
            notes+=("$rig: driver ALIVE (pid $driver_pid) in cgroup '$cgroup', which is neither $unit nor a session scope. Liveness is established; durability is not.")
            ;;
    esac
done <<< "$rig_rows"

# ---------------------------------------------------------------------------
# Severity. Merge-ready PRs escalate an unhealthy rig; they never trigger one.
# Probed only for rigs already found unhealthy, so a green host makes no network
# call — and NOT for a DOOMED rig, whose driver is merging right now: the whole
# claim the escalation makes ("nothing is merging them") is false there, and the
# defect is about the next rotation rather than the current queue.
# ---------------------------------------------------------------------------
gh_unreadable=""
for row in ${unhealthy[@]+"${unhealthy[@]}"}; do
    rig=${row%%	*}
    rest=${row#*	}
    state=${rest%%	*}
    detail=${rest#*	}

    if [ "$state" = "DOOMED" ]; then
        warnings+=("$rig: $state. $detail")
        continue
    fi

    rig_path=$(printf '%s\n' "$rig_rows" | awk -F'\t' -v r="$rig" '$1 == r { print $3; exit }')
    ready_list=$(merge_ready_prs "$rig_path")
    ready_count=$(grep -c '^#' <<< "$ready_list")
    ready=$(tr '\n' ' ' <<< "$ready_list")
    ready=${ready% }

    if [ "$ready_count" -gt 0 ]; then
        errors+=("$rig: $state and $ready_count PR(s) are APPROVED+CLEAN right now ($ready) — these are merge-ready and nothing is merging them. $detail")
    else
        if ! command -v gh >/dev/null 2>&1; then gh_unreadable="yes"; fi
        warnings+=("$rig: $state. $detail")
    fi
done

[ -n "$gh_unreadable" ] && notes+=("\`gh\` is not on PATH, so no rig above could be escalated on merge-ready PRs. A dead driver is the defect either way; the escalation only ranks it.")

summary_tail="checked $checked rig(s)"
[ "$skipped_suspended" -gt 0 ]   && summary_tail="$summary_tail, skipped $skipped_suspended suspended"
[ "$skipped_no_refinery" -gt 0 ] && summary_tail="$summary_tail, skipped $skipped_no_refinery with no refinery"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "refinery idle driver dead with merge-ready work waiting: ${#errors[@]} rig(s) ($summary_tail)"
    print_lines "${errors[@]}"
    print_lines "${warnings[@]+"${warnings[@]}"}" "${notes[@]+"${notes[@]}"}"
    echo ""
    echo "Fix, per rig: assets/scripts/refinery-idle-arm.sh --rig <rig>   (arms the driver in its own systemd user unit with Restart=always, outside every session cgroup)."
    echo "Stopgap that lands the queued work immediately: gc session nudge <rig>/<binding>.refinery \"Process MQ\""
    exit 2
fi

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "refinery idle driver not durably live on ${#warnings[@]} rig(s) ($summary_tail)"
    print_lines "${warnings[@]}"
    print_lines "${notes[@]+"${notes[@]}"}"
    echo ""
    echo "Fix, per rig: assets/scripts/refinery-idle-arm.sh --rig <rig>"
    echo "No PR is merge-ready on these rigs at this instant, which is why the outage is invisible — it surfaces the next time something goes APPROVED+CLEAN, and then it is hours old."
    exit 1
fi

echo "OK: refinery idle driver live and durably armed on $healthy of $checked rig(s) ($summary_tail)"
print_lines "${notes[@]+"${notes[@]}"}"
exit 0
