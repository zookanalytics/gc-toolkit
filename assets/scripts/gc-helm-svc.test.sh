#!/usr/bin/env bash
# Hermetic test for gc-helm-svc.sh build-scratch bounding (tk-m18ml).
#
# THE BUG: the script created /var/tmp/gotmp and pointed TMPDIR/GOTMPDIR there
# for every `go build`, and nothing — here or anywhere else in the tree — ever
# deleted from it. A build killed before its own cleanup runs (OOM, supervisor
# SIGKILL, ENOSPC) strands a ~300MB go-link dir permanently, and /var/tmp is on
# the root filesystem and survives reboot, so the leak is monotonic and shares a
# device with the Dolt journal. One post-reboot rebuild storm stranded 222 dirs
# (33G) and filled the root fs.
#
# THE FIX: each invocation builds in $GOTMP/run.<pid> and deletes it on every
# exit path; a sweep before the build reclaims run dirs whose pid is gone
# (immediately — the storm filled the disk in four hours, long before anything
# was "old") and any other entry that is a day stale (the pre-fix backlog).
#
# This runs the REAL script — copied into a throwaway rig tree, because it
# derives the Go module from its own path — with a stub toolchain on GC_GO_BIN
# and GC_HELM_GOTMP pointed at scratch under $TMPDIR. No live city, no network,
# and the real /var/tmp/gotmp is never touched. Covered:
#   (BUILD)       the build/rename/exec path still works end to end
#   (SCRATCH)     the toolchain is handed $GOTMP/run.<pid>, never $GOTMP itself
#   (OWN)         that dir — and the scratch the toolchain leaked inside it — is
#                 gone before the exec that would otherwise outlive the trap
#   (DEAD)        a run dir whose pid is gone is reclaimed on sight
#   (LIVE)        a run dir whose pid is alive is left alone (concurrent build)
#   (STALE)       un-owned scratch a day old is reclaimed (the 33G backlog)
#   (FRESH)       un-owned scratch from minutes ago is left alone
#   (NONPID)      a non-numeric run.* is not mistaken for a dead pid
#   (FAILHARD)    a failed build with no cached binary still exits 1 — and still
#                 cleans up, via the EXIT trap
#   (FAILSOFT)    a failed build with a cached binary still serves it — and the
#                 failed build's leak does not survive the exec
#   (NOBUILD)     nothing to build: no toolchain call, scratch untouched
#   (DEGRADE)     an unwritable scratch root degrades — the service still starts
#                 on the cached binary and the shared root is not removed
#   (STATIC)      the toolchain is never re-pointed at the unbounded $GOTMP
#
# tk-y3tks then added the two defects that took Helm down for days — a failed
# rebuild falling back to an artifact that could not read the stores, and a
# build that could not finish inside the readiness window — so also covered:
#   (GUARD)       a cached artifact failing its own self-check is REFUSED, not
#                 served, and the refusal says why
#   (FAILSOFT)    ...while one that passes is still served (the guard is a
#                 usability test, not a blanket ban on falling back)
#   (NOPROBE)     the up-to-date path pays for no self-check at all
#   (ALLOWSTALE)  GC_HELM_ALLOW_STALE forces the old behaviour, loudly
#   (LOGTAIL)     the detached build's own error reaches the service log
#   (DETACH)      a build survives the supervisor killing the start's process
#                 group at the readiness timeout
#   (ATTACH)      the next start attaches to that build rather than starting a
#                 second one
#   (CONCURRENT)  a binary that is current with its sources is NOT condemned by
#                 an unrelated start's failed build
#
# tk-lv5qf then found the guard did not hold in the environment it was written
# for — the supervisor exports GC_SERVICE_SOCKET, so the probe handed the very
# artifact it was interrogating everything it needed to start and serve — so
# also covered, one case per layer of the fix:
#   (PRESELFCHECK) an artifact too old to know -selfcheck is refused even when
#                 the supervisor's socket is in the environment, because the
#                 probe runs with that socket stripped
#   (PROBEBOUND)  a probe that hangs is killed by the launcher and read as a
#                 refusal, rather than stalling the start it exists to unblock
#
# tk-iyhay (round 3 of the tk-y3tks signoff) then found defect 2 still reachable
# through the lock path itself:
#   (STALELOCK-CURRENT) a start that needs no build serves the current binary
#                 immediately instead of polling a live tokened lock for
#                 GC_HELM_BUILD_WAIT and being killed by the readiness window
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm-svc.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()      { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()     { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()      { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
present() { [ -e "$1" ] && ok "$2" || bad "$2 (missing: $1)"; }
absent()  { [ ! -e "$1" ] && ok "$2" || bad "$2 (still present: $1)"; }
has()     { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (got: $1)" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm-svc.sh present" || bad "gc-helm-svc.sh missing at $SCRIPT"

# A pid the kernel cannot have handed out: allocation stops below pid_max, so
# this one is dead by construction and no case can flake on pid reuse.
DEAD_PID=$(( $(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 32768) + 7 ))

# Backdate an entry past the sweep's one-day threshold. The sweep stats the
# entry itself, so fill it BEFORE calling this — writing inside afterwards
# refreshes the directory mtime and un-ages it.
age_days() { # <path> <days>
    local when
    when="$(date -u -d "$2 days ago" +%Y%m%d%H%M 2>/dev/null || date -u -v-"$2"d +%Y%m%d%H%M)"
    touch -t "$when" "$1"
}

# --- fixture ------------------------------------------------------------------
CASE=0
FAIL_BUILD=""
fixture() { # -> ROOT GOTMP STATE RECORD GOBIN SELFCHECK COUNT
    CASE=$((CASE + 1))
    local base="$TMP/case$CASE"
    ROOT="$base/root"; GOTMP="$base/gotmp"; STATE="$base/state"
    RECORD="$base/go-env"; GOBIN="$base/bin/go"
    SELFCHECK="$base/selfcheck-calls"; COUNT="$base/build-count"
    STUB_SLEEP=""; SELFCHECK_RC=0; ALLOW_STALE=""; BUILD_WAIT=""; RUN_TIMEOUT=""
    # The supervisor exports GC_SERVICE_SOCKET into the launcher. Empty here is
    # equivalent to unset for every consumer (the launcher never reads it), so
    # the cases that predate this knob are unaffected; the tk-lv5qf cases set it.
    SERVICE_SOCKET=""; SELFCHECK_WAIT=""
    mkdir -p "$ROOT/assets/scripts" "$ROOT/services/helm/cmd/helm-svc" \
             "$GOTMP" "$STATE" "$base/bin"
    cp "$SCRIPT" "$ROOT/assets/scripts/gc-helm-svc.sh"
    echo 'package main' > "$ROOT/services/helm/cmd/helm-svc/main.go"
    # Stub toolchain: records the scratch env it was handed, leaks a go-link dir
    # into it the way a killed linker does, then fails or writes a stand-in
    # binary. `go build -o` produces an executable; mktemp staged $BIN_TMP 0600,
    # so the chmod is what keeps the -x check downstream honest.
    cat > "$GOBIN" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'TMPDIR=%s\nGOTMPDIR=%s\n' "${TMPDIR:-}" "${GOTMPDIR:-}" > "$STUB_RECORD"
# One line per invocation: the attach case asserts a second start does NOT
# start a second build, which is only observable by counting.
[ -n "${STUB_COUNT:-}" ] && echo build >> "$STUB_COUNT"
mkdir -p "$GOTMPDIR/go-link-stub"
head -c 4096 /dev/zero > "$GOTMPDIR/go-link-stub/obj"
# A slow link, so a test can kill the start while the build is still running.
[ -n "${STUB_GO_SLEEP:-}" ] && sleep "$STUB_GO_SLEEP"
if [ -n "${STUB_GO_FAIL:-}" ]; then
    echo "stub go: link failed" >&2
    exit 1
fi
out=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
printf '#!/bin/sh\necho "helm-svc-stub ran: $*"\n' > "$out"
chmod +x "$out"
STUB
    chmod +x "$GOBIN"
}

# Plant a previously-built binary. It answers -selfcheck the way the real one
# does — exit status IS the verdict — and records that it was asked, so a case
# can assert the launcher actually consulted the artifact rather than assuming
# it was fine. $SELFCHECK_RC picks the verdict: 0 = this artifact still reads
# the stores, 1 = the tk-y3tks artifact, executable but too old to read v65.
cache_binary() {
    mkdir -p "$STATE/bin"
    cat > "$STATE/bin/helm-svc" <<'CACHED'
#!/bin/sh
for a in "$@"; do
    case "$a" in
        -selfcheck|--selfcheck)
            [ -n "${SELFCHECK_RECORD:-}" ] && echo asked >> "$SELFCHECK_RECORD"
            [ "${SELFCHECK_RC:-0}" = 0 ] || echo "selfcheck FAILED: schema version mismatch" >&2
            exit "${SELFCHECK_RC:-0}" ;;
    esac
done
echo "cached-binary ran: $*"
CACHED
    chmod +x "$STATE/bin/helm-svc"
}

# Plant the artifact the guard actually exists to catch: the Aug 11 vintage,
# which predates -selfcheck entirely. It does NOT branch on argv — that is the
# whole point, an unknown flag is not a flag it knows — it branches on the
# environment, exactly as helm-svc's main() did and does: no GC_SERVICE_SOCKET
# is a fatal, a socket is a service to run. Serving is modelled as a sleep,
# because "starts normally and keeps running" is the failure: the probe never
# returns, the readiness window expires, and the stale board is what the
# supervisor proxies to.
cache_binary_preselfcheck() {
    mkdir -p "$STATE/bin"
    cat > "$STATE/bin/helm-svc" <<'OLD'
#!/bin/sh
if [ -n "${SELFCHECK_RECORD:-}" ]; then
    printf 'args=[%s] socket=[%s]\n' "$*" "${GC_SERVICE_SOCKET:-}" >> "$SELFCHECK_RECORD"
fi
if [ -z "${GC_SERVICE_SOCKET:-}" ]; then
    echo "helm: GC_SERVICE_SOCKET is not set; run me as a proxy_process workspace-service" >&2
    exit 1
fi
echo "stale-binary SERVING on ${GC_SERVICE_SOCKET}"
sleep 30      # "keeps running" is the failure; bounded only so a regression ends
OLD
    chmod +x "$STATE/bin/helm-svc"
}

# Plant an artifact whose probe HANGS regardless of the environment, and then
# reports success. Models a probe blocked on something other than a missing
# socket — an unreachable store, a wedged filesystem — in a binary with no
# internal bound of its own. Only the launcher-side bound can end this.
cache_binary_hangs() {
    mkdir -p "$STATE/bin"
    cat > "$STATE/bin/helm-svc" <<'HANG'
#!/bin/sh
for a in "$@"; do
    case "$a" in
        -selfcheck|--selfcheck)
            [ -n "${SELFCHECK_RECORD:-}" ] && echo asked >> "$SELFCHECK_RECORD"
            sleep 30      # far past the launcher's bound; only it can end this
            exit 0 ;;
    esac
done
echo "hanging-binary ran: $*"
HANG
    chmod +x "$STATE/bin/helm-svc"
}

selfcheck_calls() { [ -f "$SELFCHECK" ] && wc -l < "$SELFCHECK" | tr -d ' ' || echo 0; }
build_count()     { [ -f "$COUNT" ] && wc -l < "$COUNT" | tr -d ' ' || echo 0; }

run_script() { # -> OUT ERR RC
    local err="$TMP/case$CASE/stderr"
    # $RUN_TIMEOUT bounds the launcher itself. A case whose whole point is that
    # the start must NOT block has no other way to fail: without a bound the
    # regression simply hangs the suite for GC_HELM_BUILD_WAIT instead of
    # reporting, and timeout's 124 is what makes "it waited" an assertable RC.
    local -a bound=()
    if [ -n "${RUN_TIMEOUT:-}" ]; then bound=(timeout "$RUN_TIMEOUT"); fi
    set +e
    OUT="$(STUB_RECORD="$RECORD" STUB_GO_FAIL="$FAIL_BUILD" STUB_GO_SLEEP="$STUB_SLEEP" \
           STUB_COUNT="$COUNT" SELFCHECK_RECORD="$SELFCHECK" SELFCHECK_RC="$SELFCHECK_RC" \
           GC_HELM_ALLOW_STALE="$ALLOW_STALE" GC_HELM_BUILD_WAIT="$BUILD_WAIT" \
           GC_SERVICE_SOCKET="$SERVICE_SOCKET" GC_HELM_SELFCHECK_WAIT="$SELFCHECK_WAIT" \
           GC_GO_BIN="$GOBIN" GC_HELM_GOTMP="$GOTMP" GC_SERVICE_STATE_ROOT="$STATE" \
           "${bound[@]}" bash "$ROOT/assets/scripts/gc-helm-svc.sh" "$@" 2>"$err")"
    RC=$?
    set -e
    ERR="$(cat "$err")"
}

run_dir_of() { sed -n 's/^GOTMPDIR=//p' "$RECORD"; }

# Start the launcher in its OWN session, so a test can kill the whole process
# group the way the supervisor kills a service that missed its readiness
# window. That is the only way to observe the fix: a build left in this
# session dies with the group, while a build the launcher detached does not.
run_script_bg() { # -> BG_PID
    local base="$TMP/case$CASE"
    STUB_RECORD="$RECORD" STUB_GO_FAIL="$FAIL_BUILD" STUB_GO_SLEEP="$STUB_SLEEP" \
    STUB_COUNT="$COUNT" SELFCHECK_RECORD="$SELFCHECK" SELFCHECK_RC="$SELFCHECK_RC" \
    GC_HELM_ALLOW_STALE="$ALLOW_STALE" \
    GC_GO_BIN="$GOBIN" GC_HELM_GOTMP="$GOTMP" GC_SERVICE_STATE_ROOT="$STATE" \
    setsid bash "$ROOT/assets/scripts/gc-helm-svc.sh" "$@" \
        >"$base/bg.out" 2>"$base/bg.err" &
    BG_PID=$!
}

# Poll until <file> exists, up to <secs>. Used instead of a fixed sleep so the
# timing cases neither flake on a slow machine nor pad the suite on a fast one.
await() { # <path> <secs>
    local waited=0 limit=$(( ${2:-10} * 10 ))
    while [ ! -e "$1" ] && [ "$waited" -lt "$limit" ]; do sleep 0.1; waited=$((waited + 1)); done
    [ -e "$1" ]
}

# --- case 1: build, sweep, and clean up after itself --------------------------
fixture
mkdir -p "$GOTMP/run.$DEAD_PID" "$GOTMP/run.$$" "$GOTMP/run.bogus" \
         "$GOTMP/go-link-old" "$GOTMP/go-link-fresh"
: > "$GOTMP/run.$DEAD_PID/obj"
: > "$GOTMP/go-link-old/obj"
age_days "$GOTMP/run.$DEAD_PID" 2      # stranded AND stale: the pid decides first
age_days "$GOTMP/go-link-old" 2
run_script --socket /run/helm.sock

eq "$RC" 0 "(BUILD) exits 0 after building and exec'ing the binary"
has "$OUT" "helm-svc-stub ran: --socket /run/helm.sock" "(BUILD) args reach the built binary"
present "$STATE/bin/helm-svc" "(BUILD) binary published to the state root"

RUN_DIR="$(run_dir_of)"
eq "$(sed -n 's/^TMPDIR=//p' "$RECORD")" "$RUN_DIR" "(SCRATCH) TMPDIR and GOTMPDIR agree"
case "$RUN_DIR" in
    "$GOTMP"/run.[0-9]*) ok "(SCRATCH) toolchain got a per-invocation \$GOTMP/run.<pid>" ;;
    *) bad "(SCRATCH) toolchain scratch was '$RUN_DIR', want $GOTMP/run.<pid>" ;;
esac
absent "$RUN_DIR" "(OWN) the invocation's own scratch is removed before the exec"
absent "$RUN_DIR/go-link-stub" "(OWN) scratch the toolchain leaked inside it goes with it"

absent "$GOTMP/run.$DEAD_PID" "(DEAD) run dir of a gone pid is reclaimed"
present "$GOTMP/run.$$"       "(LIVE) run dir of a live pid is left alone"
absent  "$GOTMP/go-link-old"  "(STALE) day-old un-owned scratch is reclaimed"
present "$GOTMP/go-link-fresh" "(FRESH) minutes-old un-owned scratch is left alone"
present "$GOTMP/run.bogus"    "(NONPID) non-numeric run.* is not read as a dead pid"

# --- case 2: build fails, nothing cached -> propagate, still clean up ---------
fixture
FAIL_BUILD=1
run_script
FAIL_BUILD=""
eq "$RC" 1 "(FAILHARD) exits 1 when the build fails with no cached binary"
has "$ERR" "build failed and no cached binary to serve" "(FAILHARD) reports why"
absent "$(run_dir_of)" "(FAILHARD) EXIT trap removes the scratch on the exit path"
eq "$(find "$GOTMP" -mindepth 1 -maxdepth 1 -name 'run.*' | wc -l)" "0" \
   "(FAILHARD) no run dir survives"

# --- case 3: build fails, cached binary -> serve it, drop the failed scratch --
fixture
cache_binary
touch "$ROOT/services/helm/cmd/helm-svc/main.go"   # source newer -> rebuild attempted
FAIL_BUILD=1
run_script --socket /run/helm.sock
FAIL_BUILD=""
eq "$RC" 0 "(FAILSOFT) keeps serving the cached binary when the rebuild fails"
has "$OUT" "cached-binary ran: --socket /run/helm.sock" "(FAILSOFT) the cached binary is the one exec'd"
has "$ERR" "rebuild failed; continuing to serve existing" "(FAILSOFT) the failure still surfaces"
absent "$(run_dir_of)" "(FAILSOFT) a failed build's leak does not survive the exec"
eq "$(selfcheck_calls)" "1" "(FAILSOFT) the artifact was asked to prove itself before being served"
has "$ERR" "stub go: link failed" "(LOGTAIL) the toolchain's own error reaches the service log"

# --- case 4: nothing to build -> toolchain untouched, scratch untouched ------
fixture
cache_binary                                        # newer than main.go -> no rebuild
mkdir -p "$GOTMP/go-link-old"
: > "$GOTMP/go-link-old/obj"
age_days "$GOTMP/go-link-old" 3
run_script --socket /run/helm.sock
eq "$RC" 0 "(NOBUILD) serves the up-to-date binary"
has "$OUT" "cached-binary ran:" "(NOBUILD) exec'd without rebuilding"
absent "$RECORD" "(NOBUILD) the toolchain was never invoked"
present "$GOTMP/go-link-old" "(NOBUILD) the sweep is scoped to builds; scratch is untouched"
eq "$(selfcheck_calls)" "0" "(NOPROBE) an up-to-date binary is served without paying for a self-check"

# --- case 5: scratch hygiene cannot stop the service starting -----------------
# `set -e` is live in the script, so an unguarded mkdir/rm in the hygiene would
# abort the start — and the case where it aborts is a full or unwritable disk,
# exactly when the cached-binary fallback is the behaviour that matters. An
# unwritable $GOTMP stands in for that here: every cleanup call fails, and the
# run dir cannot be created at all.
fixture
cache_binary
touch "$ROOT/services/helm/cmd/helm-svc/main.go"    # source newer -> rebuild attempted
mkdir -p "$GOTMP/go-link-old" "$GOTMP/run.$DEAD_PID"
: > "$GOTMP/go-link-old/obj"
: > "$GOTMP/run.$DEAD_PID/obj"
age_days "$GOTMP/go-link-old" 2                     # both sweepable, but every
chmod 500 "$GOTMP"                                  # rm below will fail on EACCES
run_script --socket /run/helm.sock
chmod 700 "$GOTMP"
eq "$RC" 0 "(DEGRADE) an unwritable scratch root does not stop the service starting"
has "$OUT" "cached-binary ran:" "(DEGRADE) the cached binary is still served"
has "$ERR" "cannot create" "(DEGRADE) the degraded path says so"
present "$GOTMP" "(DEGRADE) the shared root is not removed as if it were owned scratch"
present "$GOTMP/go-link-old" "(DEGRADE) a failed age sweep is swallowed, not fatal"
present "$GOTMP/run.$DEAD_PID" "(DEGRADE) a failed dead-pid sweep is swallowed, not fatal"

# --- case: a cached artifact that cannot read the stores is REFUSED ----------
# The tk-y3tks outage in one case. The rebuild fails (ENOSPC, in the incident)
# and a cached binary is present and executable — but it is the Aug 11 artifact
# whose embedded beads library knows v61 against stores since migrated to v65,
# so every board gather dies. The old launcher served it on the strength of
# `-x "$BIN"` alone and reported a running service for days. Serving a binary
# that cannot read the store is not availability.
fixture
cache_binary
touch "$ROOT/services/helm/cmd/helm-svc/main.go"   # source newer -> rebuild attempted
FAIL_BUILD=1
SELFCHECK_RC=1                                     # the artifact fails its own probe
run_script --socket /run/helm.sock
FAIL_BUILD=""
eq "$RC" 1 "(GUARD) refuses to start on an artifact that fails its self-check"
eq "$(selfcheck_calls)" "1" "(GUARD) the artifact was actually asked"
has "$ERR" "REFUSING to serve" "(GUARD) the refusal is explicit"
has "$ERR" "failed its own self-check" "(GUARD) it says WHY, not just that it failed"
case "$OUT" in
    *"cached-binary ran: --socket"*) bad "(GUARD) the unusable artifact was exec'd anyway" ;;
    *) ok "(GUARD) the unusable artifact is never exec'd" ;;
esac

# --- case: the operator can still force the old behaviour --------------------
# The guard fails closed, so there has to be a way past it: a board that cannot
# read one rig is still worth more than no board at all, and that judgement
# belongs to the operator rather than to this script. It stays loud.
fixture
cache_binary
touch "$ROOT/services/helm/cmd/helm-svc/main.go"
FAIL_BUILD=1
SELFCHECK_RC=1
ALLOW_STALE=1
run_script --socket /run/helm.sock
FAIL_BUILD=""
eq "$RC" 0 "(ALLOWSTALE) GC_HELM_ALLOW_STALE serves the artifact anyway"
has "$OUT" "cached-binary ran:" "(ALLOWSTALE) the cached artifact is the one exec'd"
has "$ERR" "SELF-CHECK SKIPPED" "(ALLOWSTALE) the override announces itself"

# --- case: the socket the supervisor exports never reaches the probe ---------
# tk-lv5qf. The guard above rests on one claim: an artifact too old to know
# -selfcheck fails by construction, because it ignores the unknown argv, finds
# no GC_SERVICE_SOCKET, and dies. The first half is a property of the artifact;
# the SECOND half is a property of the CALLER, and the caller had it backwards.
# The supervisor exports GC_SERVICE_SOCKET into this launcher, so a probe that
# inherited the environment handed the Aug 11 binary a live socket — and that
# binary does what it has always done with a socket: binds it and serves. The
# probe never returns, the readiness window expires, and the supervisor proxies
# the stale board. The guard reproduced the outage it was written to prevent.
#
# The socket strip is what carries this case: SELFCHECK_WAIT is set short so a
# regression fails fast rather than hanging, but the timeout must not be what
# saves us — a probe that has to be KILLED has already run the old binary as a
# server. So the assertions are that the artifact saw an EMPTY socket and never
# reached its serving path, neither of which the timeout can make true.
fixture
cache_binary_preselfcheck
SERVICE_SOCKET="$TMP/case$CASE/helm.sock"
SELFCHECK_WAIT=5
touch "$ROOT/services/helm/cmd/helm-svc/main.go"   # source newer -> rebuild attempted
FAIL_BUILD=1
run_script --socket "$SERVICE_SOCKET"
FAIL_BUILD=""
PROBE_ARGV="$(cat "$SELFCHECK" 2>/dev/null || true)"
BUILD_LOG_TXT="$(cat "$STATE/bin/build.log" 2>/dev/null || true)"
eq "$RC" 1 "(PRESELFCHECK) a pre-selfcheck artifact is refused, not served"
has "$PROBE_ARGV" "socket=[]" "(PRESELFCHECK) the probe runs with GC_SERVICE_SOCKET stripped"
case "$PROBE_ARGV" in
    *"socket=[$SERVICE_SOCKET]"*) bad "(PRESELFCHECK) the probe leaked the live service socket to the artifact" ;;
    *)                            ok  "(PRESELFCHECK) the probe leaked the live service socket to the artifact — it did not" ;;
esac
case "$BUILD_LOG_TXT" in
    *SERVING*) bad "(PRESELFCHECK) the old artifact started serving during its own probe" ;;
    *)         ok  "(PRESELFCHECK) the old artifact never reaches its serving path" ;;
esac
case "$BUILD_LOG_TXT" in
    *"self-check exceeded"*) bad "(PRESELFCHECK) the probe had to be killed — it was handed a socket and ran as a server" ;;
    *)                       ok  "(PRESELFCHECK) the probe exits on its own, immediately" ;;
esac
has "$ERR" "REFUSING to serve" "(PRESELFCHECK) the refusal is explicit"

# --- case: a probe that hangs cannot stall the start -------------------------
# The second layer, pinned where only it is observable. Stripping the socket
# ends the case above; it does nothing for a probe blocked on an unreachable
# store or a wedged filesystem, in a binary carrying no bound of its own. An
# unbounded probe stalls the very start it exists to unblock, and the operator
# gets `did not become ready before timeout` again — the message that started
# all of this. Bounded, the artifact is refused and the reason is on the record.
fixture
cache_binary_hangs
SELFCHECK_WAIT=3
touch "$ROOT/services/helm/cmd/helm-svc/main.go"
FAIL_BUILD=1
run_script --socket /run/helm.sock
FAIL_BUILD=""
BUILD_LOG_TXT="$(cat "$STATE/bin/build.log" 2>/dev/null || true)"
eq "$RC" 1 "(PROBEBOUND) a hanging probe is a refusal, not a hang"
eq "$(selfcheck_calls)" "1" "(PROBEBOUND) the artifact was asked exactly once"
has "$BUILD_LOG_TXT" "self-check exceeded" "(PROBEBOUND) the log says the probe was killed on its bound"
case "$OUT" in
    *"hanging-binary ran:"*) bad "(PROBEBOUND) the unprobeable artifact was exec'd anyway" ;;
    *)                       ok  "(PROBEBOUND) the unprobeable artifact is never exec'd" ;;
esac

# --- case: the build outlives the start that began it ------------------------
# The second tk-y3tks defect. Rebuild-on-start runs inside the supervisor's
# readiness window and a ~160MB link does not fit; when the window expires the
# supervisor kills the service, and an inline build dies with it. Every restart
# threw away the same partial link, so `gc service restart helm` could not fix
# what `gc service restart helm` is the remedy for, and the binary sat at Aug 11
# through two restart attempts.
#
# The kill here is the supervisor's: the whole process group, which is why the
# launcher is started in a session of its own. A build left in that group dies
# with it; a build the launcher detached survives and publishes.
fixture
STUB_SLEEP=2
run_script_bg --socket /run/helm.sock
await "$RECORD" 15 && ok "(DETACH) the build starts" || bad "(DETACH) the build never started"
kill -TERM "-$BG_PID" 2>/dev/null || true          # as the readiness timeout does
wait "$BG_PID" 2>/dev/null || true
await "$STATE/bin/helm-svc" 30 \
    && ok "(DETACH) the killed start's build still finishes and publishes the binary" \
    || bad "(DETACH) killing the start killed the build — the binary was never published"

# --- case: the next start attaches to that build instead of restarting it ----
# Attaching is the half that actually breaks the loop. A second start that began
# its own build would restart the same link from scratch and be killed by the
# same window, forever. Only ONE toolchain invocation may happen across both.
fixture
STUB_SLEEP=3
run_script_bg --socket /run/helm.sock
await "$RECORD" 15 || bad "(ATTACH) the first build never started"
kill -TERM "-$BG_PID" 2>/dev/null || true
wait "$BG_PID" 2>/dev/null || true
run_script --socket /run/helm.sock                 # start 2, while the build runs
eq "$RC" 0 "(ATTACH) the next start serves the binary the detached build published"
has "$OUT" "helm-svc-stub ran: --socket /run/helm.sock" "(ATTACH) it exec'd the freshly built binary"
eq "$(build_count)" "1" "(ATTACH) the second start attached to the running build, it did not start another"

# --- case: someone else's failed build does not condemn a current binary -----
# The guard must fire on a SUPERSEDED artifact, not on any artifact that happens
# to be present when a build fails. Here $BIN is newer than every source, so
# this start wanted no build at all, and another start's build fails underneath
# it. Refusing here would take a good binary out of service on the strength of
# an unrelated failure, and the self-check cannot tell "too old to read the
# stores" from "the stores are down right now".
#
# Since tk-iyhay this start does not even wait for that verdict — a no-build
# start serves $BIN immediately (see STALELOCK-CURRENT below), so the failing
# build's `fail` is never consumed at all. The outcome asserted here is
# unchanged and now holds for a stronger reason.
fixture
cache_binary                                    # newer than main.go -> need_build=0
SELFCHECK_RC=1                                  # would REFUSE if the guard ran here
mkdir -p "$STATE/bin"
# A build that is genuinely IN FLIGHT: it holds a tokened lock and has not
# published a verdict yet. It publishes `fail` a moment later, stamped with the
# token from its own lock, which is what makes the verdict provably its answer.
# (Writing the verdict up front would instead describe a build that already
# finished — a stale lock — and is covered by the STALELOCK cases below.)
CONC_TOKEN="btest-concurrent-1"
( sleep 1; echo "$CONC_TOKEN fail" > "$STATE/bin/.build.result" ) &
FAKE_BUILDER=$!
echo "$FAKE_BUILDER $CONC_TOKEN" > "$STATE/bin/.build.pid"
run_script --socket /run/helm.sock
wait "$FAKE_BUILDER" 2>/dev/null || true
eq "$RC" 0 "(CONCURRENT) a current binary is served even though another start's build failed"
has "$OUT" "cached-binary ran:" "(CONCURRENT) it is the binary that gets exec'd"
eq "$(selfcheck_calls)" "0" "(CONCURRENT) no self-check is paid for: nothing here is superseded"
has "$ERR" "current with its sources" "(CONCURRENT) the log says why it was trusted"

# --- case: a STALE lock must not suppress a required rebuild -----------------
# The lock outlives the start that wrote it by design, and a pid is not an
# identity: pids are reused. So "the locked pid is alive" can mean an unrelated
# process inherited the number long after the build ended. The old code took
# that as "a build is running", skipped the rebuild it had already decided it
# needed, then read the PREVIOUS build's `ok` and logged "rebuilt" over a binary
# nobody rebuilt — serving a stale artifact while reporting success. This is the
# reviewer's reproduction from tk-e0l83, verbatim in shape: live impostor pid,
# leftover ok verdict, sources newer than the binary, no patience for waiting.
fixture
cache_binary                                    # the artifact that must NOT be served
sleep 30 &                                      # a live process that is NOT a builder
IMPOSTOR=$!
mkdir -p "$STATE/bin"
touch "$ROOT/services/helm/cmd/helm-svc/main.go"   # sources newer -> need_build=1
echo "$IMPOSTOR btest-stale-1" > "$STATE/bin/.build.pid"
echo "btest-stale-1 ok"        > "$STATE/bin/.build.result"
BUILD_WAIT=0
run_script --socket /run/helm.sock
kill "$IMPOSTOR" 2>/dev/null || true
wait "$IMPOSTOR" 2>/dev/null || true
eq "$(build_count)" "1" "(STALELOCK) a stale lock does not suppress the rebuild the start needed"
has "$OUT" "helm-svc-stub ran:" "(STALELOCK) the rebuilt binary is served, not the superseded cache"

# (STALELOCK-PIDONLY) a pre-token lock proves nothing about .build.result — there
# is no way to tell that verdict from an older one — so it is refused outright
# rather than trusted. Guards the upgrade path: a lock written by the previous
# version of this script is exactly this shape.
fixture
cache_binary
sleep 30 &
IMPOSTOR=$!
mkdir -p "$STATE/bin"
touch "$ROOT/services/helm/cmd/helm-svc/main.go"
echo "$IMPOSTOR" > "$STATE/bin/.build.pid"      # pid only: no token
echo ok         > "$STATE/bin/.build.result"    # and an untokened verdict
BUILD_WAIT=0
run_script --socket /run/helm.sock
kill "$IMPOSTOR" 2>/dev/null || true
wait "$IMPOSTOR" 2>/dev/null || true
eq "$(build_count)" "1" "(STALELOCK-PIDONLY) a pre-token lock is not trusted, so the rebuild still runs"
has "$OUT" "helm-svc-stub ran:" "(STALELOCK-PIDONLY) the rebuilt binary is served"

# (STALELOCK-FOREIGN) the verdict of a DIFFERENT build is never consumed as this
# one's answer. Here the attach is legitimate — live pid, tokened lock, no
# verdict for that token — but the verdict that lands carries another token. It
# must read as "no result", i.e. the failure path, not as a silent success.
fixture
cache_binary
mkdir -p "$STATE/bin"
touch "$ROOT/services/helm/cmd/helm-svc/main.go"
( sleep 1; echo "btest-someone-else ok" > "$STATE/bin/.build.result" ) &
FOREIGN=$!
echo "$FOREIGN btest-mine-1" > "$STATE/bin/.build.pid"
run_script --socket /run/helm.sock
wait "$FOREIGN" 2>/dev/null || true
case "$ERR" in
    *"rebuilt"*) bad "(STALELOCK-FOREIGN) another build's ok is not reported as our rebuild" ;;
    *)           ok  "(STALELOCK-FOREIGN) another build's ok is not reported as our rebuild" ;;
esac

# (STALELOCK-SWEEP) a lock whose builder is gone is cleared on sight. It used to
# survive every no-build start — the block that released it only ran when a
# build was wanted — which is how a dead pid stayed on disk long enough to be
# reused in the first place.
fixture
cache_binary                                    # current with sources -> need_build=0
mkdir -p "$STATE/bin"
echo "$DEAD_PID btest-dead-1" > "$STATE/bin/.build.pid"
run_script --socket /run/helm.sock
absent "$STATE/bin/.build.pid" "(STALELOCK-SWEEP) a dead builder's lock is cleared even on a no-build start"

# (STALELOCK-CURRENT) a live tokened lock with no verdict must not make a
# NO-BUILD start wait. This is what a builder killed mid-link leaves behind —
# reboot, OOM, ENOSPC — once its pid has been reused by an unrelated
# long-running process: pid alive, token present, .build.result never written.
# Neither sweep above can reach it (the pid IS alive, and the token is
# well-formed) and the poll arm deliberately does not clear it, so it persists
# across every restart.
#
# The old code entered the attach/wait path on the strength of that lock even
# though $BIN was already current with its sources, and polled it for up to
# GC_HELM_BUILD_WAIT. That is past the supervisor's readiness window, so the
# launcher was killed before reaching the exec and every restart repeated it:
# defect 2 of tk-y3tks reintroduced through the lock path, with helm down and a
# usable current binary sitting right there. A reboot supplies both halves at
# once — it kills the builder and re-seeds pids low enough to collide.
#
# The bound IS the assertion: with the defect the run never finishes, so RC is
# timeout's 124 rather than the launcher's own status.
fixture
cache_binary                                    # current with sources -> need_build=0
sleep 30 &                                      # a live process that is NOT a builder
IMPOSTOR=$!
mkdir -p "$STATE/bin"
echo "$IMPOSTOR btest-missing-result" > "$STATE/bin/.build.pid"   # tokened, no verdict
BUILD_WAIT=900                                  # the production default
RUN_TIMEOUT=5                                   # far below it: only the fix finishes
run_script --socket /run/helm.sock
kill "$IMPOSTOR" 2>/dev/null || true
wait "$IMPOSTOR" 2>/dev/null || true
eq "$RC" 0 "(STALELOCK-CURRENT) a no-build start does not wait on a live tokened lock"
has "$OUT" "cached-binary ran:" "(STALELOCK-CURRENT) the current binary is exec'd instead"
eq "$(build_count)" "0" "(STALELOCK-CURRENT) nothing is rebuilt: the binary was already current"
eq "$(selfcheck_calls)" "0" "(STALELOCK-CURRENT) no self-check is paid for: nothing here is superseded"
has "$ERR" "already current with its sources" "(STALELOCK-CURRENT) the log says why it did not wait"
# Left deliberately. A lock in this shape cannot be told from a real builder
# that has already renamed the new binary into place — which is precisely what
# makes need_build 0 — but has not yet written its verdict. Clearing it would
# let the next start begin a second build beside that one, the duplicate-build
# loop the attach path exists to prevent. Its owner releases it; an impostor's
# is collected by the dead-pid sweep the moment that process exits.
present "$STATE/bin/.build.pid" "(STALELOCK-CURRENT) the suspect lock is left for its owner, not cleared"

# --- case 5: static guard ----------------------------------------------------
# The regression that caused the incident is pointing the toolchain straight at
# the shared, unbounded $GOTMP. Whatever else the build line grows, it must hand
# the toolchain a dir this invocation owns and deletes.
if grep -qE '(TMPDIR|GOTMPDIR)="\$GOTMP"' "$SCRIPT"; then
    bad "(STATIC) build points TMPDIR/GOTMPDIR at the unbounded \$GOTMP again"
else
    ok "(STATIC) build never points TMPDIR/GOTMPDIR at the unbounded \$GOTMP"
fi
grep -q 'GOTMPDIR="\$GOTMP_RUN"' "$SCRIPT" \
    && ok "(STATIC) build is handed the per-invocation scratch dir" \
    || bad "(STATIC) build no longer uses \$GOTMP_RUN"

# On the degraded path $GOTMP_RUN IS the shared root, so the cleanup after the
# build must be ownership-guarded: unguarded, a fallback triggered by ENOSPC —
# mkdir fails while the directory is still perfectly writable — would rm -rf
# every concurrent build's scratch, on the full disk this whole change exists to
# prevent. (DEGRADE) above cannot demonstrate that: its fallback is triggered by
# unwritability, and the same unwritability defeats the destructive rm. So the
# guard is pinned here instead.
grep -q '\[ "\$GOTMP_RUN_OWNED" -eq 1 \]' "$SCRIPT" \
    && ok "(STATIC) post-build cleanup only removes scratch this invocation created" \
    || bad "(STATIC) post-build cleanup is no longer ownership-guarded — a degraded run can rm -rf the shared root"

# The socket strip is invisible in every passing run — (PRESELFCHECK) is the
# only case that can see it, and only because it plants an artifact that reads
# the environment. Nothing about the probe LOOKS wrong without it, which is how
# it was written that way in the first place. Pin the invocation itself.
grep -q 'env -u GC_SERVICE_SOCKET' "$SCRIPT" \
    && ok "(STATIC) the self-check probe strips the supervisor's service socket" \
    || bad "(STATIC) the self-check probe no longer strips GC_SERVICE_SOCKET — an artifact too old to know the flag will read it and serve"
# ...and pin that EVERY probe call site has one, not just that the string
# appears somewhere. The strip and the invocation are on different lines of the
# bounded arm (a line continuation), so this counts occurrences rather than
# matching them per-line. `|| true` on both: grep -c exits 1 on a zero count,
# and under this file's pipefail that would abort the suite instead of failing
# the assertion.
PROBE_SITES="$(grep -cE '"\$BIN" -selfcheck' "$SCRIPT" || true)"
STRIP_SITES="$(grep -cE 'env -u GC_SERVICE_SOCKET' "$SCRIPT" || true)"
if [ "${PROBE_SITES:-0}" -gt 0 ] && [ "$PROBE_SITES" = "$STRIP_SITES" ]; then
    ok "(STATIC) every -selfcheck call site is paired with an environment strip"
else
    bad "(STATIC) -selfcheck call sites ($PROBE_SITES) and environment strips ($STRIP_SITES) disagree — a probe can hand the artifact a live socket"
fi

echo ""
echo "gc-helm-svc build-scratch bounding: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
