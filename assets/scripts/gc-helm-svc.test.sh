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
fixture() { # -> ROOT GOTMP STATE RECORD GOBIN
    CASE=$((CASE + 1))
    local base="$TMP/case$CASE"
    ROOT="$base/root"; GOTMP="$base/gotmp"; STATE="$base/state"
    RECORD="$base/go-env"; GOBIN="$base/bin/go"
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
mkdir -p "$GOTMPDIR/go-link-stub"
head -c 4096 /dev/zero > "$GOTMPDIR/go-link-stub/obj"
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

cache_binary() { # plant a previously-built binary, then make a source newer
    mkdir -p "$STATE/bin"
    printf '#!/bin/sh\necho "cached-binary ran: $*"\n' > "$STATE/bin/helm-svc"
    chmod +x "$STATE/bin/helm-svc"
}

run_script() { # -> OUT ERR RC
    local err="$TMP/case$CASE/stderr"
    set +e
    OUT="$(STUB_RECORD="$RECORD" STUB_GO_FAIL="$FAIL_BUILD" \
           GC_GO_BIN="$GOBIN" GC_HELM_GOTMP="$GOTMP" GC_SERVICE_STATE_ROOT="$STATE" \
           bash "$ROOT/assets/scripts/gc-helm-svc.sh" "$@" 2>"$err")"
    RC=$?
    set -e
    ERR="$(cat "$err")"
}

run_dir_of() { sed -n 's/^GOTMPDIR=//p' "$RECORD"; }

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
