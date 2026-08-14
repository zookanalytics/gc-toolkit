#!/usr/bin/env bash
# Hermetic test for doctor/check-refinery-idle-driver/run.sh (tk-agzpl).
#
# THE HOLE IT CLOSES. Every cheap way to ask "is the merge cadence running" has
# a confirmed false answer on this host, and a detector built on one of them is
# WORSE than no detector: it certifies a merge queue that has stopped. So the
# load-bearing cases here are not the failures — they are (12) and (13), where
# the driver is dead while every discarded signal reads healthy: a fresh
# reconcile.log and driver.out (the refinery AGENT writes those inline, minutes
# after the driver is gone) and a lock FILE that a SIGKILLed driver orphans as a
# 0-byte file forever. A check that keyed on either would pass those cases, and
# it must not.
#
# The whole host surface is faked through PATH — `gc`, `fuser`, `ps`,
# `systemctl`, `gh` — so a case can pose any liveness state without a city, a
# systemd unit, or the network. `git` and the coreutils are the real ones.
#
# Covered:
#   (1)  both rigs durably armed, git working directory        -> OK      (0)
#   (2)  driver on disk, lock file present, NOBODY holding it  -> WARNING (1)
#   (3)  same, plus an APPROVED+CLEAN PR waiting               -> ERROR   (2)
#   (4)  no state dir at all (never armed)                     -> WARNING (1)
#   (5)  lock held, but the holder is in a tmux-spawn scope    -> WARNING (1)
#   (5b) …and a merge-ready PR does NOT escalate that to an error
#   (6)  the same dead rig, suspended                          -> OK      (0)
#   (7)  the same dead rig, no refinery agent configured       -> OK      (0)
#   (8)  durably armed but WorkingDirectory is not a git tree  -> WARNING (1)
#   (8b) durably armed, git tree, but NO origin remote         -> WARNING (1)
#   (8c) WorkingDirectory carrying systemd's `-`/`!` prefix    -> OK      (0)
#   (9)  lock held by a FOREIGN process, no driver             -> WARNING (1)
#   (10) `gc rig list` unreadable                              -> WARNING (1)
#   (11) neither fuser nor lsof on PATH                        -> WARNING (1)
#   (12) VACUOUS-GREEN GUARD: dead driver, FRESH logs          -> WARNING (1)
#   (13) VACUOUS-GREEN GUARD: (12) must name the orphaned lock
#   (14) an unhealthy rig is reported even with no PR data at all
#   (15) a healthy driver PLUS the children that inherit its FD 9   -> OK    (0)
#   (16) only those children left, driver gone                      -> WARNING (1)

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/run.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# ---------------------------------------------------------------------------
# The fake host. Each fake answers from files inside the case directory, so a
# case describes a liveness state by writing fixtures rather than by creating
# processes.
#
#   <case>/rigs.json            gc rig list --json
#   <case>/agents.json          gc agent list --json
#   <case>/gc.rc                if present, gc exits with it and prints nothing
#   <lock>.holders              PIDs fuser reports for that lock
#   <case>/ps.args.<pid>        ps -o args= -p <pid>
#   <case>/ps.cgroup.<pid>      ps -o cgroup= -p <pid>
#   <case>/wd.<unit>            systemctl --user show <unit> -p WorkingDirectory
#   <rig-path>/.fake-prs.json   gh pr list --json … run from that rig
# ---------------------------------------------------------------------------
mkbin() { # mkbin <case-dir> [--no-holder-tools]
    local d="$1" bin="$1/bin" real
    mkdir -p "$bin"
    # Real tools the check legitimately uses. Symlinked rather than inherited so
    # case (11) can remove fuser/lsof from a PATH that still works.
    for real in bash timeout jq tr grep sed awk head tail wc cat env git sleep; do
        command -v "$real" >/dev/null 2>&1 && ln -sf "$(command -v "$real")" "$bin/$real"
    done

    cat > "$bin/gc" <<'EOF'
#!/usr/bin/env bash
[ -f "$FAKE_CASE/gc.rc" ] && exit "$(cat "$FAKE_CASE/gc.rc")"
case "$1 $2" in
    "rig list")   cat "$FAKE_CASE/rigs.json" ;;
    "agent list") cat "$FAKE_CASE/agents.json" 2>/dev/null || echo '{"agents":[]}' ;;
    *)            exit 1 ;;
esac
EOF
    cat > "$bin/fuser" <<'EOF'
#!/usr/bin/env bash
# Real fuser prints PIDs on stdout and its commentary on stderr.
for a in "$@"; do case "$a" in -*) ;; *) lock="$a" ;; esac; done
[ -f "$lock.holders" ] || exit 1
tr '\n' ' ' < "$lock.holders"
EOF
    cat > "$bin/ps" <<'EOF'
#!/usr/bin/env bash
# ps -o <fmt>= -p <pid>
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
# systemctl --user show <unit> -p WorkingDirectory
unit=""; for a in "$@"; do case "$a" in --user|-p|show|WorkingDirectory) ;; *) unit="$a" ;; esac; done
echo "WorkingDirectory=$(cat "$FAKE_CASE/wd.$unit" 2>/dev/null)"
EOF
    cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
[ -f "$PWD/.fake-prs.json" ] && cat "$PWD/.fake-prs.json" || echo '[]'
EOF
    chmod +x "$bin"/gc "$bin"/fuser "$bin"/ps "$bin"/systemctl "$bin"/gh
    [ "${2:-}" = "--no-holder-tools" ] && rm -f "$bin/fuser" "$bin/lsof"
    return 0
}

# rig <case-dir> <name> <suspended> — a rig in the roster, with a real checkout.
add_rig() {
    local d="$1" name="$2" susp="$3"
    mkdir -p "$d/rigs/$name"
    local rows="$d/.rigs.rows"
    printf '%s\t%s\t%s\n' "$name" "$susp" "$d/rigs/$name" >> "$rows"
    add_refinery "$d" "$name"
}
add_refinery() { printf '%s\n' "$2" >> "$1/.refinery.rows"; }

seal_rigs() { # seal_rigs <case-dir>  — render the two roster fixtures
    local d="$1"
    jq -Rn --rawfile rows "$d/.rigs.rows" '
        {rigs: ($rows | rtrimstr("\n") | split("\n") | map(split("\t")
              | {name: .[0], suspended: (.[1] == "true"), hq: false, path: .[2]}))}' \
        > "$d/rigs.json"
    if [ -s "$d/.refinery.rows" ]; then
        jq -Rn --rawfile rows "$d/.refinery.rows" '
            {agents: ($rows | rtrimstr("\n") | split("\n")
                  | map({name: "refinery", scope: "rig", qualified_name: (. + "/gc-toolkit.refinery")}))}' \
            > "$d/agents.json"
    else
        echo '{"agents":[]}' > "$d/agents.json"
    fi
}

# A state dir for <rig> under the case's driver root, with idle-loop.sh present.
add_driver() { # add_driver <case-dir> <rig>
    local sd="$1/drivers/gc-refinery-idle-$2"
    mkdir -p "$sd"
    printf '#!/usr/bin/env bash\n: driver for %s\n' "$2" > "$sd/idle-loop.sh"
    chmod +x "$sd/idle-loop.sh"
    printf '%s\n' "$sd"
}

# A live holder of <rig>'s lock: pid, command line, cgroup.
add_holder() { # add_holder <case-dir> <rig> <pid> <args> <cgroup>
    local d="$1" sd="$1/drivers/gc-refinery-idle-$2"
    mkdir -p "$sd"
    touch "$sd/lock"
    printf '%s\n' "$3" >> "$sd/lock.holders"
    printf '%s\n' "$4" > "$d/ps.args.$3"
    printf '%s\n' "$5" > "$d/ps.cgroup.$3"
}

newcase() { # newcase <name> -> case dir
    local d="$SANDBOX/$1"
    mkdir -p "$d/drivers"
    : > "$d/.rigs.rows"; : > "$d/.refinery.rows"
    mkbin "$d" "${2:-}"
    printf '%s' "$d"
}

# run_case <case-dir> <expected-rc> <name>; leaves output in $OUT
OUT=""
run_case() {
    local d="$1" want="$2" name="$3" rc
    seal_rigs "$d"
    OUT="$(PATH="$d/bin" FAKE_CASE="$d" GC_REFINERY_IDLE_ROOT="$d/drivers" \
           GC_DOCTOR_CHECK_TIMEOUT=5 bash "$CHECK" 2>&1)"
    rc=$?
    if [ "$rc" -eq "$want" ]; then
        ok "$name (exit $rc)"
    else
        bad "$name" "want exit $want, got $rc: $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
    fi
}

# A working directory the merge passes can actually use: a git work tree WITH an
# origin remote. The remote is not decoration — merge-skill.sh:773 and the four
# other passes resolve the repository to merge in through
# `git remote get-url origin` and fail closed without one, so a bare `git init`
# is a directory that ticks forever and merges nothing. Cases that expect OK
# must therefore point at a tree that has one.
GITDIR="$SANDBOX/worktree"
mkdir -p "$GITDIR"
git -C "$GITDIR" init -q 2>/dev/null
git -C "$GITDIR" remote add origin https://github.com/example/rig.git 2>/dev/null
# A git work tree with NO origin remote — the half-configured shape the arm
# script refuses at refinery-idle-arm.sh:161 and the detector used to pass.
NOORIGIN="$SANDBOX/worktree-no-origin"
mkdir -p "$NOORIGIN"
git -C "$NOORIGIN" init -q 2>/dev/null
NOTGIT="$SANDBOX/plain"
mkdir -p "$NOTGIT"

echo "check-refinery-idle-driver:"

# (1) Both rigs durably armed in their own unit, with a git working directory.
d=$(newcase c1)
pid=3000
for r in alpha beta; do
    pid=$((pid + 1))
    add_rig "$d" "$r" false
    add_driver "$d" "$r" >/dev/null
    add_holder "$d" "$r" "$pid" "bash $d/drivers/gc-refinery-idle-$r/idle-loop.sh" \
        "0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-$r.service"
    printf '%s\n' "$GITDIR" > "$d/wd.gc-refinery-idle-$r.service"
done
run_case "$d" 0 "both rigs durably armed -> OK"

# (2) Driver on disk, lock file PRESENT, nobody holding it. The signature of a
#     SIGKILLed driver, and the case a `[ -f lock ]` detector calls healthy.
d=$(newcase c2)
add_rig "$d" alpha false
sd=$(add_driver "$d" alpha); touch "$sd/lock"
run_case "$d" 1 "unheld lock file -> WARNING"

# (3) The same rig, with an APPROVED+CLEAN PR waiting on it.
d=$(newcase c3)
add_rig "$d" alpha false
sd=$(add_driver "$d" alpha); touch "$sd/lock"
echo '[{"number":345,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN"}]' > "$d/rigs/alpha/.fake-prs.json"
run_case "$d" 2 "dead driver + merge-ready PR -> ERROR"
case "$OUT" in *"#345"*) ok "names the waiting PR" ;; *) bad "names the waiting PR" "not in: $OUT" ;; esac

# (4) No state dir at all.
d=$(newcase c4)
add_rig "$d" alpha false
run_case "$d" 1 "no driver on disk -> WARNING"
case "$OUT" in *ABSENT*) ok "reports ABSENT" ;; *) bad "reports ABSENT" "not in: $OUT" ;; esac

# (5) Alive, holding the lock — inside a session scope. Working now, dead at the
#     next rotation, and invisible to every liveness probe that stops at "alive".
d=$(newcase c5)
add_rig "$d" alpha false
add_driver "$d" alpha >/dev/null
add_holder "$d" alpha 4242 "bash $d/drivers/gc-refinery-idle-alpha/idle-loop.sh" \
    "0::/user.slice/user-1000.slice/user@1000.service/tmux-spawn-9f2a.scope"
run_case "$d" 1 "alive in a session scope -> WARNING"
case "$OUT" in *DOOMED*) ok "reports DOOMED, not healthy" ;; *) bad "reports DOOMED" "not in: $OUT" ;; esac

# (5b) The same rig with an APPROVED+CLEAN PR waiting stays a WARNING. Its
#      driver is merging that PR right now, so the error's claim — "nothing is
#      merging them" — would be false; the defect is the next rotation.
echo '[{"number":902,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN"}]' > "$d/rigs/alpha/.fake-prs.json"
run_case "$d" 1 "DOOMED + merge-ready PR is NOT escalated to ERROR"

# (6) The same dead rig, suspended: exempt.
d=$(newcase c6)
add_rig "$d" alpha true
sd=$(add_driver "$d" alpha); touch "$sd/lock"
run_case "$d" 0 "suspended rig is exempt -> OK"

# (7) The same dead rig with no refinery agent: nothing should be merging there.
d=$(newcase c7)
mkdir -p "$d/rigs/alpha"
printf 'alpha\tfalse\t%s\n' "$d/rigs/alpha" >> "$d/.rigs.rows"
add_refinery "$d" other
mkdir -p "$d/rigs/other"; printf 'other\tfalse\t%s\n' "$d/rigs/other" >> "$d/.rigs.rows"
add_driver "$d" other >/dev/null
add_holder "$d" other 7777 "bash $d/drivers/gc-refinery-idle-other/idle-loop.sh" \
    "0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-other.service"
printf '%s\n' "$GITDIR" > "$d/wd.gc-refinery-idle-other.service"
sd=$(add_driver "$d" alpha); touch "$sd/lock"
run_case "$d" 0 "rig with no refinery is skipped -> OK"

# (8) Durably armed, ticking, active/running — and merging nothing, because its
#     WorkingDirectory is not a git work tree.
d=$(newcase c8)
add_rig "$d" alpha false
add_driver "$d" alpha >/dev/null
add_holder "$d" alpha 5150 "bash $d/drivers/gc-refinery-idle-alpha/idle-loop.sh" \
    "0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-alpha.service"
printf '%s\n' "$NOTGIT" > "$d/wd.gc-refinery-idle-alpha.service"
run_case "$d" 1 "armed but WorkingDirectory is not a git tree -> WARNING"

# (8b) Durably armed, ticking, active/running, WorkingDirectory IS a git work
#      tree — and still merging nothing, because that tree has no origin remote.
#      The passes resolve the repository to merge in through
#      `git remote get-url origin` (merge-skill.sh:773, pre-open-resolve.sh:105,
#      reconcile-merged-prs.sh:235, reconcile-gate-verdicts.sh:189,
#      check-set-heal.sh:562) and every one of them fails closed without it.
#      refinery-idle-arm.sh:161 refuses to arm into this state, so a green here
#      would send the operator to a remedy that rejects what the check just
#      called healthy.
d=$(newcase c8b)
add_rig "$d" alpha false
add_driver "$d" alpha >/dev/null
add_holder "$d" alpha 5151 "bash $d/drivers/gc-refinery-idle-alpha/idle-loop.sh" \
    "0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-alpha.service"
printf '%s\n' "$NOORIGIN" > "$d/wd.gc-refinery-idle-alpha.service"
run_case "$d" 1 "armed, git tree, but NO origin remote -> WARNING (not OK)"
case "$OUT" in
    *"no 'origin' remote"*) ok "names the missing origin remote" ;;
    *) bad "names the missing origin remote" "not in: $OUT" ;;
esac

# (8c) The same healthy driver, with the prefixes systemd attaches to the value
#      it reports (`-` ignore-failure, `!` privileged). Both name the same
#      directory; refinery-idle-arm.sh:223 strips both, and a detector that
#      stripped only one would call a perfectly good repo "NOT a git work tree"
#      and send its operator to re-arm a driver that is already correct.
prefix_case=0
for prefix in - '!'; do
    prefix_case=$((prefix_case + 1))
    d=$(newcase "c8c_$prefix_case")
    add_rig "$d" alpha false
    add_driver "$d" alpha >/dev/null
    add_holder "$d" alpha 5252 "bash $d/drivers/gc-refinery-idle-alpha/idle-loop.sh" \
        "0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-alpha.service"
    printf '%s%s\n' "$prefix" "$GITDIR" > "$d/wd.gc-refinery-idle-alpha.service"
    run_case "$d" 0 "WorkingDirectory prefixed '$prefix' is normalized -> OK"
done

# (9) Something else holds the lock. An arm would exit 0 without taking it.
d=$(newcase c9)
add_rig "$d" alpha false
add_driver "$d" alpha >/dev/null
add_holder "$d" alpha 6060 "tail -f /var/log/syslog" "0::/user.slice/whatever.scope"
run_case "$d" 1 "foreign lock holder -> WARNING"
case "$OUT" in *"held by pid(s) 6060"*) ok "names the foreign holder" ;; *) bad "names the foreign holder" "not in: $OUT" ;; esac

# (10) The control plane cannot be read: say so, never report green.
d=$(newcase c10)
add_rig "$d" alpha false
echo 1 > "$d/gc.rc"
run_case "$d" 1 "unreadable rig roster -> WARNING, not OK"
case "$OUT" in *"cannot determine"*) ok "says it cannot determine" ;; *) bad "says it cannot determine" "not in: $OUT" ;; esac

# (11) No way to read lock holder-ship. The check must refuse rather than fall
#      back to a signal it has already rejected.
d=$(newcase c11 --no-holder-tools)
add_rig "$d" alpha false
add_driver "$d" alpha >/dev/null
run_case "$d" 1 "no fuser and no lsof -> WARNING, not OK"

# (12)+(13) THE VACUOUS-GREEN GUARD. The driver is dead. Its reconcile.log and
#     driver.out were both written one second ago (the refinery agent runs the
#     same passes inline while awake), the lock file is present, and a refinery
#     session is live. Everything a cheaper detector would look at says healthy.
d=$(newcase c12)
add_rig "$d" alpha false
sd=$(add_driver "$d" alpha)
touch "$sd/lock"
echo "---- tick $(date -u +%FT%TZ) ----" > "$sd/reconcile.log"
echo "==== driver start ====" > "$sd/driver.out"
run_case "$d" 1 "dead driver with FRESH logs -> WARNING (not fooled by mtime)"
case "$OUT" in
    *"EXISTS BUT IS UNHELD"*) ok "names the orphaned lock as the false-green" ;;
    *) bad "names the orphaned lock" "not in: $OUT" ;;
esac

# (15) The live shape: a healthy driver's pass scripts and interval `sleep`
#      inherit its FD 9 and are holders too. A live gc-toolkit lock reads seven
#      pids, four of which are not the driver. That must read as healthy, and
#      "someone holds it" must not be what makes it so.
d=$(newcase c15)
add_rig "$d" alpha false
add_driver "$d" alpha >/dev/null
add_holder "$d" alpha 8801 "bash $d/drivers/gc-refinery-idle-alpha/idle-loop.sh" \
    "0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-alpha.service"
add_holder "$d" alpha 8802 "bash /rig/assets/scripts/reconcile-graduated-convoys.sh --target main" \
    "0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-alpha.service"
add_holder "$d" alpha 8803 "sleep 60" \
    "0::/user.slice/user-1000.slice/user@1000.service/app.slice/gc-refinery-idle-alpha.service"
printf '%s\n' "$GITDIR" > "$d/wd.gc-refinery-idle-alpha.service"
run_case "$d" 0 "driver plus its inherited-FD children -> OK"

# (16) The inverse: only the children are left, the driver is gone. Someone
#      holds the lock and the cadence is still dead.
d=$(newcase c16)
add_rig "$d" alpha false
add_driver "$d" alpha >/dev/null
add_holder "$d" alpha 8804 "sleep 60" "0::/user.slice/orphan.scope"
run_case "$d" 1 "only orphaned children hold the lock -> WARNING"
case "$OUT" in *"8804"*) ok "names the leftover holder" ;; *) bad "names the leftover holder" "not in: $OUT" ;; esac

# (14) No gh data at all: the rig is still reported, one severity down.
d=$(newcase c14)
add_rig "$d" alpha false
sd=$(add_driver "$d" alpha); touch "$sd/lock"
rm -f "$d/bin/gh"
run_case "$d" 1 "no gh on PATH -> still WARNS about the dead driver"

echo
echo "check-refinery-idle-driver: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
