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
    STUB_SLEEP=""; SELFCHECK_RC=0; ALLOW_STALE=""
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

selfcheck_calls() { [ -f "$SELFCHECK" ] && wc -l < "$SELFCHECK" | tr -d ' ' || echo 0; }
build_count()     { [ -f "$COUNT" ] && wc -l < "$COUNT" | tr -d ' ' || echo 0; }

run_script() { # -> OUT ERR RC
    local err="$TMP/case$CASE/stderr"
    set +e
    OUT="$(STUB_RECORD="$RECORD" STUB_GO_FAIL="$FAIL_BUILD" STUB_GO_SLEEP="$STUB_SLEEP" \
           STUB_COUNT="$COUNT" SELFCHECK_RECORD="$SELFCHECK" SELFCHECK_RC="$SELFCHECK_RC" \
           GC_HELM_ALLOW_STALE="$ALLOW_STALE" \
           GC_GO_BIN="$GOBIN" GC_HELM_GOTMP="$GOTMP" GC_SERVICE_STATE_ROOT="$STATE" \
           bash "$ROOT/assets/scripts/gc-helm-svc.sh" "$@" 2>"$err")"
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
# this start wanted no build at all — it only waited on one another start left
# running, and that one failed. Refusing here would take a good binary out of
# service on the strength of an unrelated failure, and the self-check cannot
# tell "too old to read the stores" from "the stores are down right now".
fixture
cache_binary                                    # newer than main.go -> need_build=0
SELFCHECK_RC=1                                  # would REFUSE if the guard ran here
mkdir -p "$STATE/bin"
sleep 2 &                                       # stand in for another start's builder
FAKE_BUILDER=$!
echo "$FAKE_BUILDER" > "$STATE/bin/.build.pid"
echo fail > "$STATE/bin/.build.result"
run_script --socket /run/helm.sock
wait "$FAKE_BUILDER" 2>/dev/null || true
eq "$RC" 0 "(CONCURRENT) a current binary is served even though another start's build failed"
has "$OUT" "cached-binary ran:" "(CONCURRENT) it is the binary that gets exec'd"
eq "$(selfcheck_calls)" "0" "(CONCURRENT) no self-check is paid for: nothing here is superseded"
has "$ERR" "current with its sources" "(CONCURRENT) the log says why it was trusted"

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

echo ""
echo "gc-helm-svc build-scratch bounding: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
