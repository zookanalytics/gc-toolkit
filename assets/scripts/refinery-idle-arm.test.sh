#!/usr/bin/env bash
# Hermetic test for assets/scripts/refinery-idle-arm.sh (tk-agzpl).
#
# WHAT IT IS GUARDING. Every property this script sets is one that has already
# been dropped by hand on this host, and every one of them fails SILENTLY —
# the unit reads active/running either way. So the assertions are mostly about
# the exact shape of the systemd-run invocation (cases 1-3) and about refusing
# to declare success on a unit that came up without the lock or in somebody
# else's cgroup (cases 12-13). `ActiveState=active` proves nothing here: the
# driver exits 0 the moment it cannot take the lock.
#
# The (8) family guards the same thing on the way IN rather than the way out: a
# holder in the right cgroup is liveness, not health, and answering "already
# armed" to a degraded unit is a false all-clear delivered by the very script
# doctor/check-refinery-idle-driver tells an operator to run. Each (8) case
# degrades exactly one property of an otherwise-healthy live unit.
#
# systemd-run, systemctl, fuser and ps are faked through PATH; the fake
# systemd-run writes the fixtures that describe the unit it "started", so a case
# can pose a unit that comes up healthy, one that never takes the lock, and one
# that lands in the wrong cgroup. `git` and the coreutils are real.
#
# Covered:
#   (1)  --dry-run carries Restart=always, --working-directory, the rig's env
#   (2)  session-scoped env keys are NOT handed to the unit
#   (3)  the CALLER's rig identity never leaks into another rig's unit
#   (4)  no driver on disk        -> 2, and it refuses to author one
#   (5)  working directory is not a git work tree      -> 2
#   (6)  working directory has no origin remote        -> 2
#   (7)  already armed AND healthy     -> 0 and NOTHING is run
#   (8)  already armed but DEGRADED    -> 1 each, runs nothing: Restart dropped,
#        WorkingDirectory unset / non-repo / no origin, GC_AGENT unset, another
#        rig's ledger, a PATH that cannot resolve `gc` — and --force replaces it
#   (9)  alive in a session scope, no --force -> 1, kills nothing
#   (10) foreign lock holder                  -> 1, kills nothing
#   (11) clean arm, unit takes the lock in its own cgroup -> 0
#   (12) unit comes up but never takes the lock           -> 2
#   (13) unit takes the lock in a foreign cgroup          -> 2
#   (14) no systemd-run on PATH                          -> 2
#
# NOT covered: the --force teardown itself (kill the driver and the children
# that inherited its FD 9, wait for the flock to clear). `kill` is a bash
# BUILTIN, so a PATH fake cannot intercept it and no fixture can make a fake
# pid "die" — testing it would mean contorting the script for the test. What IS
# covered is every path that decides WHETHER to tear down, which is where the
# damage would be: cases 7-10 all leave a live or unidentified holder alone.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ARM="$HERE/refinery-idle-arm.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# A real git work tree with an origin remote — what the merge passes need.
GITDIR="$SANDBOX/checkout"
mkdir -p "$GITDIR"
git -C "$GITDIR" init -q 2>/dev/null
git -C "$GITDIR" remote add origin https://github.com/example/repo.git 2>/dev/null
NOORIGIN="$SANDBOX/no-origin"; mkdir -p "$NOORIGIN"; git -C "$NOORIGIN" init -q 2>/dev/null
PLAIN="$SANDBOX/plain"; mkdir -p "$PLAIN"

mkbin() { # mkbin <case-dir> [--no-systemd-run]
    local d="$1" bin="$1/bin" real
    mkdir -p "$bin"
    for real in bash jq tr grep sed awk head tail wc cat env git sleep kill sort timeout touch; do
        command -v "$real" >/dev/null 2>&1 && ln -sf "$(command -v "$real")" "$bin/$real"
    done

    cat > "$bin/gc" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "rig list")   cat "$FAKE_CASE/rigs.json" ;;
    "agent list") cat "$FAKE_CASE/agents.json" ;;
    *)            exit 1 ;;
esac
EOF
    cat > "$bin/fuser" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in -*) ;; *) lock="$a" ;; esac; done
[ -f "$lock.holders" ] || exit 1
tr '\n' ' ' < "$lock.holders"
EOF
    cat > "$bin/ps" <<'EOF'
#!/usr/bin/env bash
fmt=""; pid=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) fmt="${2%=}"; shift 2 ;;
        -p) pid="$2"; shift 2 ;;
        *)  shift ;;
    esac
done
cat "$FAKE_CASE/ps.$fmt.$pid" 2>/dev/null
EOF
    cat > "$bin/systemctl" <<'EOF'
#!/usr/bin/env bash
verb=""; unit=""; props=""
for a in "$@"; do
    case "$a" in
        --user) ;;
        show|stop|reset-failed|status) verb="$a" ;;
        -p) ;;
        Restart|MainPID|ActiveState|SubState|WorkingDirectory|Environment) props="$props $a" ;;
        *) unit="$a" ;;
    esac
done
echo "$verb $unit" >> "$FAKE_CASE/systemctl.calls"
[ "$verb" = "show" ] || exit 0
for p in $props; do echo "$p=$(cat "$FAKE_CASE/unit.$p" 2>/dev/null)"; done
EOF
    cat > "$bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
# Record the invocation, then apply the case's scripted outcome: which pid the
# unit reports, whether that pid holds the lock, and what cgroup it is in.
printf '%s\n' "$@" > "$FAKE_CASE/systemd-run.args"
[ -f "$FAKE_CASE/systemd-run.rc" ] && exit "$(cat "$FAKE_CASE/systemd-run.rc")"
pid=$(cat "$FAKE_CASE/spawn.pid" 2>/dev/null || echo 9001)
echo "$pid" > "$FAKE_CASE/unit.MainPID"
echo "active" > "$FAKE_CASE/unit.ActiveState"
echo "running" > "$FAKE_CASE/unit.SubState"
printf 'bash %s\n' "$(cat "$FAKE_CASE/driver.path")" > "$FAKE_CASE/ps.args.$pid"
cat "$FAKE_CASE/spawn.cgroup" > "$FAKE_CASE/ps.cgroup.$pid" 2>/dev/null
lock=$(cat "$FAKE_CASE/lock.path")
touch "$lock"
[ -f "$FAKE_CASE/spawn.nolock" ] || printf '%s\n' "$pid" >> "$lock.holders"
exit 0
EOF
    chmod +x "$bin"/gc "$bin"/fuser "$bin"/ps "$bin"/systemctl "$bin"/systemd-run
    [ "${2:-}" = "--no-systemd-run" ] && rm -f "$bin/systemd-run"
    return 0
}

# newcase <name> [--no-systemd-run] -> case dir with one rig "alpha"
newcase() {
    local d="$SANDBOX/$1"
    mkdir -p "$d/drivers/gc-refinery-idle-alpha" "$d/rigs/alpha"
    mkbin "$d" "${2:-}"
    jq -n --arg p "$d/rigs/alpha" --arg q "$d/rigs/beta" \
        '{rigs:[{name:"alpha",suspended:false,hq:false,path:$p},
                {name:"beta", suspended:false,hq:false,path:$q}]}' > "$d/rigs.json"
    jq -n '{agents:[{name:"refinery",scope:"rig",qualified_name:"alpha/gc-toolkit.refinery"},
                    {name:"refinery",scope:"rig",qualified_name:"beta/gc-toolkit.refinery"}]}' > "$d/agents.json"
    mkdir -p "$d/rigs/beta"
    printf '#!/usr/bin/env bash\n: driver\n' > "$d/drivers/gc-refinery-idle-alpha/idle-loop.sh"
    chmod +x "$d/drivers/gc-refinery-idle-alpha/idle-loop.sh"
    printf '%s' "$d/drivers/gc-refinery-idle-alpha/idle-loop.sh" > "$d/driver.path"
    printf '%s' "$d/drivers/gc-refinery-idle-alpha/lock" > "$d/lock.path"
    printf '0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-alpha.service\n' > "$d/spawn.cgroup"
    printf '%s' "$d"
}

# run_arm <case-dir> <expected-rc> <name> [extra args…]; output in $OUT
OUT=""
run_arm() {
    local d="$1" want="$2" name="$3" rc; shift 3
    OUT="$(PATH="$d/bin" FAKE_CASE="$d" GC_REFINERY_IDLE_ROOT="$d/drivers" \
           GC_CITY_PATH="$d" GC_RIG=alpha \
           GC_SESSION_ID=sess-1 GC_SESSION_NAME=alpha__polecat-1 GC_TEMPLATE=tpl \
           GC_TRIGGER_WORK_BEAD_ID=tk-old GC_ALIAS=furiosa \
           GC_AGENT=alpha/gc-toolkit.polecat BEADS_DIR=/wrong/.beads \
           BEADS_DOLT_SERVER_PORT=38676 \
           bash "$ARM" --working-directory "$GITDIR" "$@" 2>&1)"
    rc=$?
    if [ "$rc" -eq "$want" ]; then
        ok "$name (exit $rc)"
    else
        bad "$name" "want exit $want, got $rc: $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
    fi
}

# A live holder of alpha's lock.
add_holder() { # add_holder <case-dir> <pid> <args> <cgroup>
    local d="$1"
    touch "$d/drivers/gc-refinery-idle-alpha/lock"
    printf '%s\n' "$2" >> "$d/drivers/gc-refinery-idle-alpha/lock.holders"
    printf '%s\n' "$3" > "$d/ps.args.$2"
    printf '%s\n' "$4" > "$d/ps.cgroup.$2"
}
armed() { [ -f "$1/systemd-run.args" ]; }
arg_has() { grep -qxF -- "$2" "$1/systemd-run.args" 2>/dev/null; }

# What a HEALTHY live unit shows. The already-armed cases each degrade exactly
# one of these, because each one ALONE is a driver that reads active/running
# while merging nothing or silently skipping a pass — which is the whole reason
# the no-op path has to read the unit instead of trusting the cgroup.
#
# The unit PATH here is the sandbox's own bin, which has gc/jq/git but no
# bd/gh/flock. That is deliberate: the script's shell cannot resolve them either,
# so re-arming would hand over the same gap and they must be REPORTED rather than
# counted as a reason to replace a live driver.
healthy_unit() { # healthy_unit <case-dir>
    local d="$1"
    echo always    > "$d/unit.Restart"
    echo "$GITDIR" > "$d/unit.WorkingDirectory"
    printf 'GC_RIG=alpha GC_RIG_ROOT=%s BEADS_DIR=%s GC_AGENT=alpha/gc-toolkit.refinery PATH=%s HOME=%s\n' \
        "$d/rigs/alpha" "$d/rigs/alpha/.beads" "$d/bin" "$HOME" > "$d/unit.Environment"
}

# A live driver of ours, in its own unit — the shape every case below starts from.
live_in_unit() { # live_in_unit <case-dir> <pid>
    add_holder "$1" "$2" "bash $1/drivers/gc-refinery-idle-alpha/idle-loop.sh" \
        "0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-alpha.service"
}

echo "refinery-idle-arm:"

# (1) The shape of the invocation is the whole point of the script.
d=$(newcase c1)
run_arm "$d" 0 "--dry-run emits a full invocation" --dry-run
for want in "--property=Restart=always" "--property=RestartSec=15" "--working-directory=$GITDIR"; do
    case "$OUT" in *"$want"*) ok "carries $want" ;; *) bad "carries $want" "not in: $OUT" ;; esac
done
case "$OUT" in *"--setenv=GC_AGENT=alpha/gc-toolkit.refinery"*) ok "sets GC_AGENT to the rig's refinery" ;;
    *) bad "sets GC_AGENT" "not in: $OUT" ;; esac
case "$OUT" in *"--setenv=BEADS_DIR=$d/rigs/alpha/.beads"*) ok "sets BEADS_DIR from the rig root" ;;
    *) bad "sets BEADS_DIR" "not in: $OUT" ;; esac
case "$OUT" in *"--setenv=BEADS_DOLT_SERVER_PORT=38676"*) ok "passes the caller's BEADS_* through" ;;
    *) bad "passes BEADS_* through" "not in: $OUT" ;; esac

# (2) A driver that outlives its launcher must not carry the launcher's identity.
for leak in GC_SESSION_ID GC_SESSION_NAME GC_TEMPLATE GC_ALIAS GC_TRIGGER_WORK_BEAD_ID; do
    case "$OUT" in
        *"--setenv=$leak="*) bad "drops session-scoped $leak" "leaked into: $OUT" ;;
        *) ok "drops session-scoped $leak" ;;
    esac
done

# (3) Arming ANOTHER rig from this session must not stamp this session's rig.
d=$(newcase c3)
mkdir -p "$d/drivers/gc-refinery-idle-beta"
cp "$d/drivers/gc-refinery-idle-alpha/idle-loop.sh" "$d/drivers/gc-refinery-idle-beta/"
run_arm "$d" 0 "--dry-run for another rig" --rig beta --dry-run
case "$OUT" in *"--setenv=GC_RIG=beta"*) ok "GC_RIG is the target rig, not the caller's" ;;
    *) bad "GC_RIG is the target rig" "not in: $OUT" ;; esac
case "$OUT" in *"--setenv=GC_AGENT=beta/gc-toolkit.refinery"*) ok "GC_AGENT is the target rig's refinery" ;;
    *) bad "GC_AGENT is the target rig's refinery" "not in: $OUT" ;; esac
case "$OUT" in *"--setenv=GC_AGENT=alpha/gc-toolkit.polecat"*) bad "caller's GC_AGENT leaked" "in: $OUT" ;;
    *) ok "the caller's own GC_AGENT does not leak" ;; esac

# (4) It arms the proven driver; it does not write one.
d=$(newcase c4)
rm -f "$d/drivers/gc-refinery-idle-alpha/idle-loop.sh"
run_arm "$d" 2 "no driver on disk -> failure"
case "$OUT" in *"does not author one"*) ok "refuses to author a driver" ;; *) bad "refuses to author" "not in: $OUT" ;; esac

# (5)+(6) The working directory is where the merge passes fail closed, silently.
d=$(newcase c5)
OUT="$(PATH="$d/bin" FAKE_CASE="$d" GC_REFINERY_IDLE_ROOT="$d/drivers" GC_CITY_PATH="$d" \
       bash "$ARM" --rig alpha --working-directory "$PLAIN" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then ok "non-git working directory -> failure (exit 2)"; else bad "non-git working directory" "got $rc: $OUT"; fi
if armed "$d"; then bad "nothing was armed" "systemd-run ran anyway"; else ok "nothing was armed"; fi

d=$(newcase c6)
OUT="$(PATH="$d/bin" FAKE_CASE="$d" GC_REFINERY_IDLE_ROOT="$d/drivers" GC_CITY_PATH="$d" \
       bash "$ARM" --rig alpha --working-directory "$NOORIGIN" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then ok "work tree with no origin -> failure (exit 2)"; else bad "no origin remote" "got $rc: $OUT"; fi

# (7) Idempotence. A live, durable, HEALTHY driver is left alone.
d=$(newcase c7)
live_in_unit "$d" 9100
healthy_unit "$d"
run_arm "$d" 0 "already armed and healthy -> no-op"
if armed "$d"; then bad "no-op really is a no-op" "systemd-run ran"; else ok "no-op really is a no-op"; fi
case "$OUT" in *"does not resolve bd gh flock"*)
        ok "reports the tools no re-arm could supply, without refusing over them" ;;
    *)  bad "reports unfixable PATH gaps" "not in: $OUT" ;; esac

# (8x) …and every degradation of that same live driver is REFUSED, not waved
#      through. Each one alone reads active/running, so an unvalidated no-op
#      answers "already armed" for all of them — which is a false all-clear on
#      the one script doctor/check-refinery-idle-driver names as the remedy.
d=$(newcase c8a)
live_in_unit "$d" 9101
healthy_unit "$d"; echo no > "$d/unit.Restart"
run_arm "$d" 1 "already armed, Restart dropped -> refuse"
case "$OUT" in *"--force"*) ok "names --force as the upgrade" ;; *) bad "names --force" "not in: $OUT" ;; esac
case "$OUT" in *"Restart='no'"*) ok "names the dropped property" ;; *) bad "names Restart" "not in: $OUT" ;; esac
if armed "$d"; then bad "did not re-arm without --force" "systemd-run ran"; else ok "did not re-arm without --force"; fi

d=$(newcase c8b)
live_in_unit "$d" 9104
healthy_unit "$d"; : > "$d/unit.WorkingDirectory"
run_arm "$d" 1 "already armed, WorkingDirectory unset -> refuse"
case "$OUT" in *"WorkingDirectory is unset"*) ok "names the unset working directory" ;;
    *) bad "names the unset working directory" "not in: $OUT" ;; esac
if armed "$d"; then bad "unset WorkingDirectory armed nothing" "systemd-run ran"; else ok "unset WorkingDirectory armed nothing"; fi

# The bad directory is the UNIT's, while --working-directory names a good one:
# the health of a live driver is a property of the unit, never of this argv.
d=$(newcase c8c)
live_in_unit "$d" 9105
healthy_unit "$d"; echo "$PLAIN" > "$d/unit.WorkingDirectory"
run_arm "$d" 1 "already armed, unit WorkingDirectory is not a git tree -> refuse"
case "$OUT" in *"is not a git work tree"*) ok "names the non-repo working directory" ;;
    *) bad "names the non-repo working directory" "not in: $OUT" ;; esac

d=$(newcase c8d)
live_in_unit "$d" 9106
healthy_unit "$d"; echo "$NOORIGIN" > "$d/unit.WorkingDirectory"
run_arm "$d" 1 "already armed, unit WorkingDirectory has no origin -> refuse"
case "$OUT" in *"no 'origin' remote"*) ok "names the missing origin remote" ;;
    *) bad "names the missing origin remote" "not in: $OUT" ;; esac

# GC_AGENT: the pass that self-skips. Nothing else on the host reports it.
d=$(newcase c8e)
live_in_unit "$d" 9107
healthy_unit "$d"
sed 's| GC_AGENT=[^ ]*||' "$d/unit.Environment" > "$d/unit.Environment.tmp" && mv "$d/unit.Environment.tmp" "$d/unit.Environment"
run_arm "$d" 1 "already armed, GC_AGENT unset in the unit -> refuse"
case "$OUT" in *"GC_AGENT is unset"*) ok "names the self-skipping pass" ;;
    *) bad "names GC_AGENT" "not in: $OUT" ;; esac

d=$(newcase c8f)
live_in_unit "$d" 9108
healthy_unit "$d"
sed 's|BEADS_DIR=[^ ]*|BEADS_DIR=/some/other/rig/.beads|' "$d/unit.Environment" > "$d/unit.Environment.tmp" && mv "$d/unit.Environment.tmp" "$d/unit.Environment"
run_arm "$d" 1 "already armed against another rig's ledger -> refuse"
case "$OUT" in *"/some/other/rig/.beads"*) ok "names the wrong ledger" ;;
    *) bad "names the wrong ledger" "not in: $OUT" ;; esac

# A PATH gap this shell CAN close is a degradation; the ones it cannot are only
# reported (asserted in case 7), so the remedy is never one that cannot work.
d=$(newcase c8g)
live_in_unit "$d" 9109
healthy_unit "$d"
sed "s|PATH=[^ ]*|PATH=$d/nowhere|" "$d/unit.Environment" > "$d/unit.Environment.tmp" && mv "$d/unit.Environment.tmp" "$d/unit.Environment"
run_arm "$d" 1 "already armed with a PATH that cannot resolve gc -> refuse"
case "$OUT" in *"does not resolve: gc"*) ok "names the tool the unit cannot run" ;;
    *) bad "names the unresolvable tool" "not in: $OUT" ;; esac

# (8h) --force is the decision, and it replaces the degraded driver.
d=$(newcase c8h)
live_in_unit "$d" 9110
healthy_unit "$d"; echo no > "$d/unit.Restart"
run_arm "$d" 0 "degraded + --force -> proceeds to replace it" --force --dry-run
case "$OUT" in *"replacing a DEGRADED driver"*) ok "says what it is replacing and why" ;;
    *) bad "announces the replacement" "not in: $OUT" ;; esac
case "$OUT" in *"--property=Restart=always"*) ok "the replacement restores Restart=always" ;;
    *) bad "replacement restores Restart=always" "not in: $OUT" ;; esac

# (9) A doomed driver is still a live merge writer: replacing it is a decision.
d=$(newcase c9)
add_holder "$d" 9102 "bash $d/drivers/gc-refinery-idle-alpha/idle-loop.sh" \
    "0::/user.slice/user-1000.slice/user@1000.service/tmux-spawn-1f2e.scope"
run_arm "$d" 1 "alive in a session scope, no --force -> refuse"
if armed "$d"; then bad "refusal armed nothing" "systemd-run ran"; else ok "refusal armed nothing"; fi

# (10) An unidentified holder is never killed and never armed over.
d=$(newcase c10)
add_holder "$d" 9103 "tail -f /var/log/syslog" "0::/user.slice/whatever.scope"
run_arm "$d" 1 "foreign lock holder -> refuse"
case "$OUT" in *"9103"*) ok "names the foreign holder" ;; *) bad "names the foreign holder" "not in: $OUT" ;; esac

# (11) The clean arm.
d=$(newcase c11)
echo 9200 > "$d/spawn.pid"
run_arm "$d" 0 "clean arm -> success" --wait 3
armed "$d" || bad "systemd-run was invoked" "no args recorded"
if arg_has "$d" "--property=Restart=always"; then ok "the real invocation carries Restart=always"
else bad "real invocation carries Restart=always" "$(tr '\n' ' ' < "$d/systemd-run.args" 2>/dev/null)"; fi
if arg_has "$d" "--unit=gc-refinery-idle-alpha.service"; then ok "unit is rig-namespaced"
else bad "unit is rig-namespaced" "$(tr '\n' ' ' < "$d/systemd-run.args" 2>/dev/null)"; fi
if grep -q '^stop gc-refinery-idle-alpha.service$' "$d/systemctl.calls" 2>/dev/null; then
    ok "stops any prior unit before arming"
else
    bad "stops any prior unit" "calls: $(tr '\n' ' ' < "$d/systemctl.calls" 2>/dev/null)"
fi

# (12) The unit is active and running and holds no lock. That is not the cadence.
d=$(newcase c12)
echo 9201 > "$d/spawn.pid"
touch "$d/spawn.nolock"
run_arm "$d" 2 "unit up but never took the lock -> failure" --wait 1
case "$OUT" in *"never took"*) ok "says the lock was never taken" ;; *) bad "says the lock was never taken" "not in: $OUT" ;; esac

# (13) Verify by cgroup, never by unit state: this is the failure being fixed.
d=$(newcase c13)
echo 9202 > "$d/spawn.pid"
printf '0::/user.slice/user-1000.slice/user@1000.service/tmux-spawn-abcd.scope\n' > "$d/spawn.cgroup"
run_arm "$d" 2 "unit lands in a session scope -> failure" --wait 3

# (14) A host with no systemd-run cannot hold a driver outside a session.
d=$(newcase c14 --no-systemd-run)
run_arm "$d" 2 "no systemd-run on PATH -> failure"

echo
echo "refinery-idle-arm: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
