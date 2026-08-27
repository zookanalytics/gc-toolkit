#!/usr/bin/env bash
# Hermetic tests for the helm build/start split (tk-9tbbk.2) and the
# build-scratch bounding that came before it (tk-m18ml).
#
# THE SPLIT. gc-helm-svc.sh used to build the binary and then exec it. The
# supervisor allows a proxy_process 5s to answer its health probe
# (proxyProcessReadyTimeout); a warm build of this module takes ~12.5s and a
# cold one 2m29s. So the build never finished inside the window, waitReady's
# stopProcessGroup() killed it along with the start, and the next start began
# again — 2,677 abandoned .helm-svc.build.* staging files in three days, and a
# restart that could only report "did not become ready before timeout".
#
# Building now lives in gc-helm-build.sh, out of band, driven by the helm-build
# order. gc-helm-svc.sh execs and nothing else. These tests pin BOTH halves:
# that the launcher cannot build, and that the builder still does everything the
# launcher used to do correctly.
#
# THE READABILITY GATE (tk-00o34c). `find -newer` cannot see a binary going
# stale against its DEPENDENCY: what helm-svc can read is fixed by the beads
# library it embedded, and the store's schema moves under it on a `bd` upgrade.
# The gate also asks `helm-svc probe`, spends `ok` only on a passing one, and
# refuses to rebuild a binary whose library a rebuild would not move.
#
# THE SCRATCH BOUNDING (inherited, tk-m18ml). The build pointed TMPDIR/GOTMPDIR
# at a shared /var/tmp/gotmp that nothing ever emptied; one post-reboot rebuild
# storm stranded 222 dirs (33G) and filled the root fs. Each invocation now
# builds in $GOTMP/run.<pid> and deletes it on every exit path, and sweeps both
# run dirs whose pid is gone and day-old un-owned scratch.
#
# These run the REAL scripts — copied into a throwaway rig tree, because they
# derive the Go module from their own path — with a stub toolchain on GC_GO_BIN,
# a stub gc on GC_HELM_GC_BIN, and GC_HELM_GOTMP pointed at scratch under
# $TMPDIR. No live city, no network, no real /var/tmp/gotmp. Covered:
#
#   launcher (gc-helm-svc.sh)
#   (EXEC)        an existing binary is exec'd, with its arguments
#   (NOBIN)       no binary -> exit 1 naming the out-of-band builder
#   (NOBUILD)     the launcher NEVER invokes a toolchain, even with sources
#                 newer than the binary — the whole point of the split
#   (NOSTALE)     a stale binary is still exec'd; staleness is not its business
#
#   builder (gc-helm-build.sh)
#   (BUILD)       builds and publishes when the binary is missing
#   (REBUILD)     rebuilds when a source is newer than the binary
#   (CURRENT)     up-to-date binary -> no toolchain call, exit 0
#   (GOMOD)       a go.mod-only change still counts as newer (tk-ohdex)
#
#   readability — the second staleness axis (tk-00o34c)
#   (READABLE)    a current binary that can read the stores reports ok, builds nothing
#   (SKEW)        sources unchanged + store schema moved -> it REBUILDS
#   (STUCK)       a rebuild that cannot fix it never writes ok, and exits non-zero
#   (NOLOOP)      and the next tick does not rebuild the same binary again
#   (BUMP)        moving the pinned library re-arms the rebuild
#   (RECOVER)     a store that comes back restores ok and clears the record
#   (LISTCITY)    the city_path in `gc service list` is enough to probe against
#   (UNPROBED)    no city to probe against is reported as such, never as ok
#   (FAILSTATUS)  a failed build still reports failed, not unreadable
#   (FAILKEEP)    a failed build leaves the previous binary untouched, exits 1
#   (ATOMIC)      the binary is published by rename, never built in place
#   (STAGE)       the failed build's staging file does not survive
#   (SWEEPSTAGE)  old stranded staging files are reclaimed; fresh ones are not
#   (SCRATCH)     the toolchain is handed $GOTMP/run.<pid>, never $GOTMP itself
#   (OWN)         that dir — and scratch the toolchain leaked inside it — is gone
#   (DEAD/LIVE)   a dead pid's run dir is reclaimed; a live pid's is not
#   (STALE/FRESH) day-old un-owned scratch is reclaimed; minutes-old is not
#   (NONPID)      a non-numeric run.* is not mistaken for a dead pid
#   (DEGRADE)     an unwritable scratch root degrades to a reported failure,
#                 leaves the last good binary intact, and the service still starts
#   (LISTROOT)    the state root comes from the city's own service listing
#   (ROOT)        it falls back to GC_CITY_ROOT when there is no listing
#   (NOROOT)      with no hint at all it refuses instead of hunting for a city
#   (ISOLATION)   the suite cannot reach a real city's service root
#
#   deploy mode (--deploy, what the order runs)
#   (SKIP)        a city with no helm service builds nothing
#   (LISTFAIL)    a failed service listing does NOT read as "not registered"
#   (QFAIL)       nor does one the filter cannot parse
#   (RESTART)     a successful build restarts the service
#   (NORESTART)   an up-to-date binary restarts nothing
#   (RCFAIL)      a failed restart is reported as a failure
#   (RETRY)       a failed restart is retried on the NEXT run, even though the
#                 binary is by then current — and stops once it is serving
#   (HANDBUILT)   a hand-run build's binary is restarted onto by the next tick
#   (DEADEND)     a build that cannot read the stores is never restarted onto
#   (CONDEMNED)   nor is a pending restart carried out onto one
#
#   build-status record (what the board's PACK rows read)
#   (STATUS)      a successful build records source_rev == binary_rev, rc 0
#   (STATUSFAIL)  a FAILED build moves source_rev, keeps the last good
#                 binary_rev and built_at, and records the non-zero rc — the
#                 gap between the two revisions IS the signal
#   (STATUSNOOP)  an up-to-date tick still writes a record; checked_at is the
#                 only field that can say the build order itself stopped
#   (STATUSDEL)   a deletion-only change rebuilds — `find -newer` is blind to an
#                 input that no longer exists, and the record must never name a
#                 revision the binary was not built from
#   (STATUSPEND)  a published-but-not-serving binary is recorded as such
#   (STATUSTMP)   the record is published by rename, leaving no staging file
#
#   static guards
#   (STATIC)      the toolchain is never re-pointed at the unbounded $GOTMP;
#                 the launcher contains no build at all
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVC="$HERE/gc-helm-svc.sh"
BUILD="$HERE/gc-helm-build.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# This suite must never be able to write into a real city.
#
# It runs inside one: GC_CITY, GC_CITY_PATH, GC_RIG_ROOT and friends are all in
# the ambient environment. Several cases deliberately omit GC_SERVICE_STATE_ROOT
# in order to exercise the builder's fallback chain — and that chain ends at
# "$GC_CITY/.gc/services/<name>". Inherit the ambient city and such a case
# publishes its stub binary straight into the running service's bin/.
#
# That is not hypothetical. On 2026-08-22 it replaced the live 161MB helm-svc
# with a 39-byte shell stub, twice. Nothing failed at the time: the fallback
# "worked", the case passed, and the damage was invisible until the next restart
# would have exec'd the stub.
#
# Three independent layers, because one guard that can be edited away is not a
# guard for a file whose whole job is to survive edits:
#
#   1. strip the city from THIS process, so every child inherits a clean env —
#      no per-call wrapper to forget at a new call site;
#   2. refuse to run at all if anything still points at a city;
#   3. give the fallback cases a sacrificial service name, so even a defeated
#      (1) and (2) resolves to .../services/helm-selftest-<pid>/, never to the
#      real service's binary.
# ---------------------------------------------------------------------------
unset GC_CITY GC_CITY_PATH GC_CITY_ROOT GC_CITY_RUNTIME_DIR GC_SERVICE_STATE_ROOT
unset GC_RIG GC_RIG_ROOT GC_PACK_DIR PACK_DIR GC_HELM_SERVICE_NAME GC_HELM_GC_BIN
for _leak in GC_CITY GC_CITY_PATH GC_CITY_ROOT GC_SERVICE_STATE_ROOT; do
    if [ -n "$(eval "printf '%s' \"\${$_leak:-}\"")" ]; then
        echo "REFUSING TO RUN: $_leak is still set — this suite writes service" >&2
        echo "state roots and must not run against a real city." >&2
        exit 1
    fi
done
unset _leak

# The name the fallback cases build under. Never "helm", so the resolution chain
# cannot land on the live service's binary even if the strip above is defeated.
SAFE_NAME="helm-selftest-$$"

PASS=0; FAIL=0
ok()      { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()     { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()      { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
present() { [ -e "$1" ] && ok "$2" || bad "$2 (missing: $1)"; }
absent()  { [ ! -e "$1" ] && ok "$2" || bad "$2 (still present: $1)"; }
has()     { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (got: $1)" ;; esac; }
hasnt()   { case "$1" in *"$2"*) bad "$3 (unexpectedly got: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SVC" ]   && ok "gc-helm-svc.sh present"   || bad "gc-helm-svc.sh missing at $SVC"
[ -f "$BUILD" ] && ok "gc-helm-build.sh present" || bad "gc-helm-build.sh missing at $BUILD"

# A pid the kernel cannot have handed out: allocation stops below pid_max, so
# this one is dead by construction and no case can flake on pid reuse.
DEAD_PID=$(( $(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 32768) + 7 ))

# A gc that is not there, so the service listing is unavailable.
NO_SUCH_GC="$TMP/no-such-gc"

# Backdate an entry past a sweep threshold. The sweep stats the entry itself, so
# fill it BEFORE calling this — writing inside afterwards refreshes the
# directory mtime and un-ages it.
age_days() { # <path> <days>
    local when
    when="$(date -u -d "$2 days ago" +%Y%m%d%H%M 2>/dev/null || date -u -v-"$2"d +%Y%m%d%H%M)"
    touch -t "$when" "$1"
}
age_mins() { # <path> <minutes>
    local when
    when="$(date -u -d "$2 minutes ago" +%Y%m%d%H%M 2>/dev/null || date -u -v-"$2"M +%Y%m%d%H%M)"
    touch -t "$when" "$1"
}

# --- fixture ------------------------------------------------------------------
CASE=0
FAIL_BUILD=""
fixture() { # -> ROOT GOTMP STATE RECORD GOBIN GCBIN GCLOG SERVICES
    CASE=$((CASE + 1))
    # Reset per case so one case's skew cannot leak into the next. CITY empty
    # means "no city to probe".
    CITY=""; PROBE_FAIL_BUILT=""; PROBE_FAIL_CACHED=""; BEADS_VERSION="v0.0.0-stub"
    local base="$TMP/case$CASE"
    ROOT="$base/root"; GOTMP="$base/gotmp"; STATE="$base/state"
    STATE_CITY="$base/city"
    RECORD="$base/go-env"; GOBIN="$base/bin/go"
    GCBIN="$base/bin/gc"; GCLOG="$base/gc-calls"; SERVICES="$base/services.json"
    mkdir -p "$ROOT/assets/scripts" "$ROOT/services/helm/cmd/helm-svc" \
             "$GOTMP" "$STATE" "$base/bin" "$STATE_CITY/.gc/services/helm"
    cp "$SVC" "$ROOT/assets/scripts/gc-helm-svc.sh"
    cp "$BUILD" "$ROOT/assets/scripts/gc-helm-build.sh"
    echo 'package main' > "$ROOT/services/helm/cmd/helm-svc/main.go"
    printf 'module helm\n' > "$ROOT/services/helm/go.mod"
    # The REAL `gc service list --json` reports `service_name`, not `name`, and
    # carries `city_path` + a relative `state_root`. An earlier stub here said
    # `name`; the suite passed while the live gate matched nothing, so the order
    # would have skipped every city forever. The stub answers what the tool
    # answers — verified against the live CLI on 2026-08-22.
    printf '{"city_path":"%s","services":[{"service_name":"helm","state_root":".gc/services/helm"}]}' \
        "$STATE_CITY" > "$SERVICES"

    # Stub toolchain: records the scratch env it was handed, leaks a go-link dir
    # into it the way a killed linker does, then fails or writes a stand-in
    # binary. `go build -o` produces an executable; mktemp staged $BIN_TMP 0600,
    # so the chmod is what keeps the -x check downstream honest.
    cat > "$GOBIN" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
# `go version -m <binary>` is a read, not a build, so it must answer before the
# build-scratch machinery below: recording it would make every readability check
# look like a compile.
if [ "${1:-}" = "version" ] && [ "${2:-}" = "-m" ]; then
    printf '\tpath\thelm-svc\n\tdep\tgithub.com/steveyegge/beads\t%s\th1:stub=\n' \
        "${STUB_BEADS_VERSION:-v0.0.0-stub}"
    exit 0
fi
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
# Record what the build was told to write to, so (ATOMIC) can prove the
# toolchain was never pointed straight at the published binary.
printf '%s\n' "$out" >> "$STUB_RECORD.out"
cat > "$out" <<'BUILT'
#!/bin/sh
if [ "$1" = "probe" ]; then
    if [ -n "${STUB_PROBE_FAIL_BUILT:-}" ]; then
        echo "helm-svc probe: cannot read the city's bead stores: no rig bead store could be read: rig gc-toolkit: $STUB_PROBE_FAIL_BUILT" >&2
        exit 3
    fi
    echo "helm-svc probe: bead stores are readable"
    exit 0
fi
echo "helm-svc-stub ran: $*"
BUILT
chmod +x "$out"
STUB
    chmod +x "$GOBIN"

    # Stub gc: answers `service list --json` from a file the case controls and
    # logs every invocation so restart behaviour can be asserted.
    cat > "$GCBIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_GC_LOG"
if [ "${1:-} ${2:-}" = "service list" ]; then
    [ -n "${STUB_GC_LIST_FAIL:-}" ] && exit 1
    cat "$STUB_GC_SERVICES"
    exit 0
fi
if [ "${1:-} ${2:-}" = "service restart" ]; then
    [ -n "${STUB_GC_RESTART_FAIL:-}" ] && { echo "restart refused" >&2; exit 1; }
    echo "restarted ${3:-}"
    exit 0
fi
exit 0
STUB
    chmod +x "$GCBIN"
}

cache_binary() { # plant a previously-built binary
    mkdir -p "$STATE/bin"
    cat > "$STATE/bin/helm-svc" <<'CACHED'
#!/bin/sh
if [ "$1" = "probe" ]; then
    if [ -n "${STUB_PROBE_FAIL_CACHED:-}" ]; then
        echo "helm-svc probe: cannot read the city's bead stores: no rig bead store could be read: rig gc-toolkit: $STUB_PROBE_FAIL_CACHED" >&2
        exit 3
    fi
    echo "helm-svc probe: bead stores are readable"
    exit 0
fi
echo "cached-binary ran: $*"
CACHED
    chmod +x "$STATE/bin/helm-svc"
}

touch_source() { touch "$ROOT/services/helm/cmd/helm-svc/main.go"; }

# A throwaway repo so the builder's `git rev-parse HEAD` has an answer. The
# revisions are the whole point of the record, and a fixture with no repo would
# let every revision assertion pass vacuously against the empty string. Local
# and never pushed, so the identity here is scaffolding, not provenance.
commit_fixture() { # <dir> -> the new revision on stdout
    git -C "$1" init -q >/dev/null 2>&1 || return 1
    git -C "$1" add -A >/dev/null 2>&1 || return 1
    git -C "$1" -c user.email=fixture@example.invalid -c user.name=fixture \
        -c commit.gpgsign=false commit -q -m "fixture" >/dev/null 2>&1 || return 1
    git -C "$1" rev-parse HEAD 2>/dev/null
}

# `has`, not `//`: jq's alternative operator treats FALSE as absent, so a
# `// ""` reader would report restart_pending=false as an empty string and the
# cleared case would pass against the wrong value.
status_field() { jq -r --arg k "$1" 'if has($k) then .[$k] else "" end | tostring' "$STATE/build-status.json" 2>/dev/null; }

run_build() { # -> OUT ERR RC
    local err="$TMP/case$CASE/stderr-build"
    set +e
    OUT="$(STUB_RECORD="$RECORD" STUB_GO_FAIL="$FAIL_BUILD" \
           STUB_GC_LOG="$GCLOG" STUB_GC_SERVICES="$SERVICES" \
           STUB_GC_LIST_FAIL="${LIST_FAIL:-}" STUB_GC_RESTART_FAIL="${RESTART_FAIL:-}" \
           STUB_PROBE_FAIL_BUILT="${PROBE_FAIL_BUILT:-}" \
           STUB_PROBE_FAIL_CACHED="${PROBE_FAIL_CACHED:-}" \
           STUB_BEADS_VERSION="${BEADS_VERSION:-v0.0.0-stub}" \
           GC_HELM_CITY_PATH="${CITY:-}" \
           GC_GO_BIN="$GOBIN" GC_HELM_GOTMP="$GOTMP" GC_SERVICE_STATE_ROOT="$STATE" \
           GC_HELM_GC_BIN="$GCBIN" \
           bash "$ROOT/assets/scripts/gc-helm-build.sh" "$@" 2>"$err")"
    RC=$?
    set -e
    ERR="$(cat "$err")"
}

run_svc() { # -> OUT ERR RC
    local err="$TMP/case$CASE/stderr-svc"
    set +e
    OUT="$(STUB_RECORD="$RECORD" GC_GO_BIN="$GOBIN" GC_HELM_GOTMP="$GOTMP" \
           GC_SERVICE_STATE_ROOT="$STATE" \
           bash "$ROOT/assets/scripts/gc-helm-svc.sh" "$@" 2>"$err")"
    RC=$?
    set -e
    ERR="$(cat "$err")"
}

run_dir_of() { sed -n 's/^GOTMPDIR=//p' "$RECORD"; }

# ==============================================================================
# LAUNCHER — gc-helm-svc.sh must exec and never build
# ==============================================================================

# --- the happy path: exec what the builder left -------------------------------
fixture
cache_binary
run_svc --socket /run/helm.sock
eq "$RC" 0 "(EXEC) exits 0 exec'ing the prebuilt binary"
has "$OUT" "cached-binary ran: --socket /run/helm.sock" "(EXEC) args reach the binary"
absent "$RECORD" "(EXEC) the launcher invoked no toolchain"

# --- sources newer than the binary: STILL no build ----------------------------
# This is the split. Before it, a newer source here triggered a ~12.5s build
# inside a 5s readiness window, which the supervisor then killed along with the
# start. The launcher must now serve what it has and leave the build to the
# out-of-band builder.
fixture
cache_binary
touch_source
run_svc --socket /run/helm.sock
eq "$RC" 0 "(NOSTALE) a stale binary is still served"
has "$OUT" "cached-binary ran:" "(NOSTALE) the stale binary is the one exec'd"
absent "$RECORD" "(NOBUILD) the launcher does not build even when sources are newer"
eq "$(find "$GOTMP" -mindepth 1 -maxdepth 1 | wc -l)" "0" \
   "(NOBUILD) the launcher creates no build scratch at all"

# --- no binary at all ---------------------------------------------------------
fixture
run_svc --socket /run/helm.sock
eq "$RC" 1 "(NOBIN) exits 1 when there is no binary to exec"
has "$ERR" "no binary at" "(NOBIN) says what is missing"
has "$ERR" "gc-helm-build.sh" "(NOBIN) names the out-of-band builder"
absent "$RECORD" "(NOBIN) still refuses to build its way out"

# ==============================================================================
# BUILDER — gc-helm-build.sh
# ==============================================================================

# --- case: builds when the binary is missing, and sweeps while it is there ----
fixture
mkdir -p "$GOTMP/run.$DEAD_PID" "$GOTMP/run.$$" "$GOTMP/run.bogus" \
         "$GOTMP/go-link-old" "$GOTMP/go-link-fresh"
: > "$GOTMP/run.$DEAD_PID/obj"
: > "$GOTMP/go-link-old/obj"
age_days "$GOTMP/run.$DEAD_PID" 2      # stranded AND stale: the pid decides first
age_days "$GOTMP/go-link-old" 2
run_build

eq "$RC" 0 "(BUILD) exits 0 after building"
has "$OUT" "built" "(BUILD) reports that it built"
present "$STATE/bin/helm-svc" "(BUILD) binary published to the state root"
[ -x "$STATE/bin/helm-svc" ] && ok "(BUILD) the published binary is executable" \
                             || bad "(BUILD) the published binary is not executable"

RUN_DIR="$(run_dir_of)"
eq "$(sed -n 's/^TMPDIR=//p' "$RECORD")" "$RUN_DIR" "(SCRATCH) TMPDIR and GOTMPDIR agree"
case "$RUN_DIR" in
    "$GOTMP"/run.[0-9]*) ok "(SCRATCH) toolchain got a per-invocation \$GOTMP/run.<pid>" ;;
    *) bad "(SCRATCH) toolchain scratch was '$RUN_DIR', want $GOTMP/run.<pid>" ;;
esac
absent "$RUN_DIR" "(OWN) the invocation's own scratch is removed"
absent "$RUN_DIR/go-link-stub" "(OWN) scratch the toolchain leaked inside it goes with it"

absent "$GOTMP/run.$DEAD_PID" "(DEAD) run dir of a gone pid is reclaimed"
present "$GOTMP/run.$$"        "(LIVE) run dir of a live pid is left alone"
absent  "$GOTMP/go-link-old"   "(STALE) day-old un-owned scratch is reclaimed"
present "$GOTMP/go-link-fresh" "(FRESH) minutes-old un-owned scratch is left alone"
present "$GOTMP/run.bogus"     "(NONPID) non-numeric run.* is not read as a dead pid"

# The toolchain must be told to write somewhere other than the published path,
# so a failed link can never truncate the binary that is currently serving.
BUILT_TO="$(cat "$RECORD.out")"
[ "$BUILT_TO" != "$STATE/bin/helm-svc" ] \
    && ok "(ATOMIC) the toolchain built to staging, not to the published binary" \
    || bad "(ATOMIC) the toolchain was pointed straight at $STATE/bin/helm-svc"
case "$BUILT_TO" in
    "$STATE/bin/".helm-svc.build.*) ok "(ATOMIC) staging sits beside the binary, so the rename is atomic" ;;
    *) bad "(ATOMIC) staging was '$BUILT_TO', not a .helm-svc.build.* beside the binary" ;;
esac
eq "$(find "$STATE/bin" -maxdepth 1 -name '.helm-svc.build.*' | wc -l)" "0" \
   "(STAGE) no staging file survives a successful build"

# --- case: rebuilds when a source is newer ------------------------------------
fixture
cache_binary
touch_source
run_build
eq "$RC" 0 "(REBUILD) exits 0"
present "$RECORD" "(REBUILD) the toolchain WAS invoked for a newer source"
run_svc --socket /run/helm.sock
has "$OUT" "helm-svc-stub ran:" "(REBUILD) the freshly built binary replaced the cached one"

# --- case: go.mod-only change still counts (tk-ohdex) -------------------------
fixture
cache_binary
touch "$ROOT/services/helm/go.mod"
run_build
eq "$RC" 0 "(GOMOD) exits 0"
present "$RECORD" "(GOMOD) a go.mod-only change triggers a rebuild"

# --- case: nothing to build ---------------------------------------------------
fixture
cache_binary                                        # newer than main.go -> current
mkdir -p "$GOTMP/go-link-old"
: > "$GOTMP/go-link-old/obj"
age_days "$GOTMP/go-link-old" 3
run_build
eq "$RC" 0 "(CURRENT) exits 0 when the binary is current"
has "$OUT" "up to date" "(CURRENT) says so"
absent "$RECORD" "(CURRENT) the toolchain was never invoked"
present "$GOTMP/go-link-old" "(CURRENT) the sweep is scoped to builds; scratch is untouched"

# ==============================================================================
# READABILITY — the second staleness axis (tk-00o34c)
# ==============================================================================
SKEW_MSG="schema version mismatch: database is at v66, binary knows up to v65 (1 migration ahead)"

status_kind() { cut -d' ' -f1 "$STATE/build-status" 2>/dev/null || echo "<no build-status>"; }
build_count() { grep -c '^' "$RECORD.out" 2>/dev/null || echo 0; }

# --- case: a current binary that CAN read reports ok and builds nothing -------
fixture
cache_binary
CITY="$STATE_CITY"
run_build
eq "$RC" 0 "(READABLE) exits 0"
has "$OUT" "up to date" "(READABLE) still the up-to-date path"
has "$OUT" "can read the city" "(READABLE) and says the readability was checked"
absent "$RECORD" "(READABLE) a passing probe builds nothing"
eq "$(status_kind)" "ok" "(READABLE) build-status is ok"

# --- case: sources unchanged, store schema moved -> REBUILD -------------------
fixture
cache_binary                                        # newer than main.go -> current
CITY="$STATE_CITY"
PROBE_FAIL_CACHED="$SKEW_MSG"
run_build
eq "$RC" 0 "(SKEW) exits 0 after rebuilding"
has "$OUT" "cannot read the city's bead stores" "(SKEW) says what the mtime check could not see"
present "$RECORD" "(SKEW) the toolchain WAS invoked — sources unchanged, store moved"
eq "$(status_kind)" "ok" "(SKEW) the rebuilt binary reads, so ok is earned"
absent "$STATE/probe-failed" "(SKEW) and nothing is latched"

# --- case: a rebuild that cannot fix it must not report ok --------------------
# The pin, not the sources, is what is stale, so the binary that comes out of
# the build is as blind as the one that went in.
fixture
cache_binary
CITY="$STATE_CITY"
PROBE_FAIL_CACHED="$SKEW_MSG"
PROBE_FAIL_BUILT="$SKEW_MSG"
run_build
eq "$RC" 1 "(STUCK) exits non-zero — the third green light goes red"
eq "$(build_count)" "1" "(STUCK) it did try the rebuild"
eq "$(status_kind)" "unreadable" "(STUCK) build-status CANNOT read ok while the board fails"
has "$(cat "$STATE/build-status")" "schema version mismatch" "(STUCK) and carries the reason"
has "$ERR" "CANNOT READ" "(STUCK) reported on stderr too"
present "$STATE/probe-failed" "(STUCK) what was tried is recorded"

# --- case: the next tick does not rebuild the same binary again ---------------
# Same case, so the state the previous run left is the input to this one.
run_build
eq "$RC" 1 "(NOLOOP) still a failure"
eq "$(build_count)" "1" "(NOLOOP) no second build — a rebuild loop is not a remedy"
eq "$(status_kind)" "unreadable" "(NOLOOP) and it still refuses to say ok"
has "$ERR" "go.mod" "(NOLOOP) it names the remedy it cannot perform itself"

# --- case: a dependency bump re-arms the rebuild ------------------------------
# The latch is keyed on the LIBRARY that failed, not on "we already tried". The
# skew is left in place to isolate that one variable.
BEADS_VERSION="v1.2.2-0.20260825072917-62d211937bd3"
run_build
eq "$RC" 1 "(BUMP) the skew is untouched, so it still fails"
eq "$(build_count)" "2" "(BUMP) but a different library version is worth another build"
eq "$(status_kind)" "unreadable" "(BUMP) and it says so"
eq "$(cat "$STATE/probe-failed" 2>/dev/null || true)" "$BEADS_VERSION" \
   "(BUMP) the latch now names what was tried"

# --- case: recovery without a rebuild ----------------------------------------
# The store can also come back on its own (the rig migrates back, or the skew
# was a half-finished upgrade). The up-to-date path must notice.
fixture
cache_binary
CITY="$STATE_CITY"
PROBE_FAIL_CACHED="$SKEW_MSG"
run_build
eq "$(status_kind)" "ok" "(RECOVER) setup: rebuilt into a readable binary"
PROBE_FAIL_BUILT="$SKEW_MSG"
run_build
eq "$(status_kind)" "unreadable" "(RECOVER) the store moves again and it says so"
PROBE_FAIL_BUILT=""
run_build
eq "$RC" 0 "(RECOVER) exits 0 once it can read again"
eq "$(status_kind)" "ok" "(RECOVER) ok returns"
absent "$STATE/probe-failed" "(RECOVER) and the latch is gone"

# --- case: no city to probe against is not a green light ----------------------
# A run that cannot ask the question must not answer it with `ok`.
fixture
cache_binary
LIST_FAIL=1
run_build
LIST_FAIL=""
eq "$RC" 0 "(UNPROBED) a hand run still exits 0"
has "$OUT" "unprobed" "(UNPROBED) and says the readability was not checked"
eq "$(status_kind)" "unprobed" "(UNPROBED) build-status says so rather than ok"
absent "$RECORD" "(UNPROBED) nothing is built on a question it cannot ask"

# --- case: the city comes from the service listing when the env has none ------
# The supervisor that runs the helm-build order carries no GC_CITY, so this is
# the resolution every scheduled tick uses.
fixture
cache_binary
PROBE_FAIL_CACHED="$SKEW_MSG"
run_build
has "$OUT" "cannot read the city's bead stores" \
    "(LISTCITY) the listing's city_path is enough to probe against"
present "$RECORD" "(LISTCITY) so the gate still fires with no city in the environment"
eq "$(status_kind)" "ok" "(LISTCITY) and reports on what it rebuilt"

# --- case: a failed build's status is still the build failure -----------------
fixture
cache_binary
touch_source
CITY="$STATE_CITY"
FAIL_BUILD=1
run_build
FAIL_BUILD=""
eq "$RC" 1 "(FAILSTATUS) exits 1"
eq "$(status_kind)" "failed" "(FAILSTATUS) a build that never produced a binary reports failed, not unreadable"

# --- case: build fails -> previous binary untouched, non-zero -----------------
fixture
cache_binary
touch_source
FAIL_BUILD=1
run_build
FAIL_BUILD=""
eq "$RC" 1 "(FAILKEEP) exits 1 when the build fails"
has "$ERR" "BUILD FAILED" "(FAILKEEP) reports the failure"
run_svc --socket /run/helm.sock
has "$OUT" "cached-binary ran:" "(FAILKEEP) the previously-built binary is untouched and still serves"
absent "$(run_dir_of)" "(FAILKEEP) the failed build's scratch does not survive"
eq "$(find "$STATE/bin" -maxdepth 1 -name '.helm-svc.build.*' | wc -l)" "0" \
   "(STAGE) the failed build's staging file does not survive either"

# --- case: the 2,677 stranded staging files are reclaimed ---------------------
# One per killed start, laid down by the inline-build era between 08-19 and
# 08-22. mktemp publishes the name before the build writes a byte, so a kill in
# between leaves one behind.
fixture
cache_binary
touch_source
mkdir -p "$STATE/bin"
: > "$STATE/bin/.helm-svc.build.OLD001"
: > "$STATE/bin/.helm-svc.build.OLD002"
: > "$STATE/bin/.helm-svc.build.FRESH1"
age_mins "$STATE/bin/.helm-svc.build.OLD001" 120
age_mins "$STATE/bin/.helm-svc.build.OLD002" 120
run_build
absent "$STATE/bin/.helm-svc.build.OLD001" "(SWEEPSTAGE) stranded staging files are reclaimed"
absent "$STATE/bin/.helm-svc.build.OLD002" "(SWEEPSTAGE) all of them, not just one"
present "$STATE/bin/.helm-svc.build.FRESH1" \
    "(SWEEPSTAGE) a fresh staging file — a concurrent build's — is left alone"

# --- case: scratch hygiene degrades rather than aborting ----------------------
# `set -e` is live in the script, so an unguarded mkdir/rm in the hygiene would
# abort it at the first EACCES — before the build, before any diagnostic, and
# before the cleanup that protects the published binary. An unwritable $GOTMP
# stands in for the full disk: every sweep call fails and the run dir cannot be
# created at all.
#
# The build genuinely cannot succeed on a disk it cannot write to, so this does
# NOT assert a green build. What it asserts is that the script degrades all the
# way through to a reported failure with the previously-built binary intact —
# rather than dying mid-hygiene, which is the state that would leave a
# half-swept scratch root and no diagnostic at all.
if [ "$(id -u)" -eq 0 ]; then
    # root ignores directory modes, so the unwritable scratch cannot be staged.
    ok "(DEGRADE) skipped (running as root; chmod cannot make the scratch unwritable)"
else
fixture
cache_binary
touch_source
mkdir -p "$GOTMP/go-link-old" "$GOTMP/run.$DEAD_PID"
: > "$GOTMP/go-link-old/obj"
: > "$GOTMP/run.$DEAD_PID/obj"
age_days "$GOTMP/go-link-old" 2                     # both sweepable, but every
chmod 500 "$GOTMP"                                  # rm below will fail on EACCES
run_build
chmod 700 "$GOTMP"
eq "$RC" 1 "(DEGRADE) reaches a reported build failure instead of dying in the hygiene"
has "$ERR" "cannot create" "(DEGRADE) the degraded scratch path says so"
has "$ERR" "BUILD FAILED" "(DEGRADE) and the build failure is still reported"
present "$GOTMP" "(DEGRADE) the shared root is not removed as if it were owned scratch"
present "$GOTMP/go-link-old" "(DEGRADE) a failed age sweep is swallowed, not fatal"
present "$GOTMP/run.$DEAD_PID" "(DEGRADE) a failed dead-pid sweep is swallowed, not fatal"
run_svc --socket /run/helm.sock
eq "$RC" 0 "(DEGRADE) the service still starts — the launcher does not depend on the build"
has "$OUT" "cached-binary ran:" "(DEGRADE) on the binary the last good build left"
fi

# --- case: the listing's state_root is authoritative -------------------------
# The order has no GC_SERVICE_STATE_ROOT — only the supervisor's own spawn does.
# Reproducing gascity's StateRootOrDefault() here would be a second copy of a
# rule that lives in another repo; reading `city_path` + `state_root` off the
# listing cannot drift from it. Pinned because a build published to the wrong
# path is invisible: it succeeds, and the service keeps serving the old binary.
fixture
set +e
OUT="$(STUB_RECORD="$RECORD" GC_GO_BIN="$GOBIN" GC_HELM_GOTMP="$GOTMP" \
       STUB_GC_LOG="$GCLOG" STUB_GC_SERVICES="$SERVICES" GC_HELM_GC_BIN="$GCBIN" \
       bash "$ROOT/assets/scripts/gc-helm-build.sh" 2>&1)"
RC=$?
set -e
eq "$RC" 0 "(LISTROOT) builds using the state root the city reported"
present "$STATE_CITY/.gc/services/helm/bin/helm-svc" \
    "(LISTROOT) the binary lands where the listing said, not at a guessed path"

# --- case: the state root is derived when there is no listing to read ---------
# The builder runs from an order, which sets GC_CITY_ROOT but not
# GC_SERVICE_STATE_ROOT — that one only exists inside the supervisor's own spawn.
fixture
CITY="$TMP/case$CASE/city2"
mkdir -p "$CITY/.gc/services/$SAFE_NAME"
set +e
OUT="$(STUB_RECORD="$RECORD" GC_GO_BIN="$GOBIN" GC_HELM_GOTMP="$GOTMP" \
       GC_CITY_ROOT="$CITY" GC_HELM_GC_BIN="$NO_SUCH_GC" GC_HELM_SERVICE_NAME="$SAFE_NAME" \
       bash "$ROOT/assets/scripts/gc-helm-build.sh" 2>&1)"
RC=$?
set -e
eq "$RC" 0 "(ROOT) builds with only GC_CITY_ROOT set"
present "$CITY/.gc/services/$SAFE_NAME/bin/helm-svc" \
    "(ROOT) the binary lands where the supervisor will look for it"

# --- case: no state-root hint at all -> refuse, do not go hunting -------------
# Every earlier resolution step is unavailable here: no GC_SERVICE_STATE_ROOT,
# no listing, no GC_CITY_ROOT/GC_CITY, and a module in a throwaway tree with no
# .gc above it. The builder must say it cannot locate the city and stop.
#
# This is the assertion that would have caught the 2026-08-22 accident, in which
# a case with no explicit state root silently inherited the ambient GC_CITY and
# published into the live service. `sandboxed` strips that env; this proves what
# the script does once it is stripped.
fixture
set +e
OUT="$(STUB_RECORD="$RECORD" GC_GO_BIN="$GOBIN" GC_HELM_GOTMP="$GOTMP" \
       GC_HELM_GC_BIN="$NO_SUCH_GC" GC_HELM_SERVICE_NAME="$SAFE_NAME" \
       bash "$ROOT/assets/scripts/gc-helm-build.sh" 2>&1)"
RC=$?
set -e
eq "$RC" 1 "(NOROOT) refuses when it cannot locate a state root"
has "$OUT" "cannot locate the city runtime dir" "(NOROOT) says so, naming the env to set"
hasnt "$OUT" "built" "(NOROOT) publishes nothing"

# ==============================================================================
# DEPLOY MODE — what the helm-build order runs
# ==============================================================================

# --- case: a city with no helm service does nothing ---------------------------
fixture
printf '{"city_path":"%s","services":[{"service_name":"something-else","state_root":".gc/services/other"}]}' \
    "$STATE_CITY" > "$SERVICES"
run_build --deploy
eq "$RC" 0 "(SKIP) exits 0 in a city with no helm service"
has "$OUT" "nothing to deploy" "(SKIP) says why"
absent "$RECORD" "(SKIP) no 161MB build for a city that will never run it"
absent "$STATE/bin/helm-svc" "(SKIP) nothing published"

# --- case: a broken listing is not proof of absence ---------------------------
# Reading a failed `gc service list` as "not registered" would silently stop
# deploying on any transient CLI failure — the class of silent stall this whole
# change exists to end.
fixture
LIST_FAIL=1
run_build --deploy
LIST_FAIL=""
eq "$RC" 0 "(LISTFAIL) proceeds when the service listing fails"
has "$ERR" "could not list services" "(LISTFAIL) says it is proceeding blind"
present "$RECORD" "(LISTFAIL) the build still happened"

# --- case: an unreadable listing is not proof of absence either ---------------
# `gc service list` SUCCEEDS here but hands back something the filter cannot
# answer from. Collapsing that into "no helm service" is the same silent-stall
# bug as (LISTFAIL): one missing dependency or one schema change and the order
# deploys nothing, forever, without ever failing.
fixture
printf 'not json at all' > "$SERVICES"
run_build --deploy
eq "$RC" 0 "(QFAIL) proceeds when the listing cannot be parsed"
has "$ERR" "could not read the service listing" "(QFAIL) says the lookup broke, not that helm is absent"
present "$RECORD" "(QFAIL) the build still happened"
hasnt "$OUT" "nothing to deploy" "(QFAIL) an unparseable listing is never read as absence"

# --- case: a build restarts the service ---------------------------------------
fixture
run_build --deploy
eq "$RC" 0 "(RESTART) exits 0"
present "$STATE/bin/helm-svc" "(RESTART) the binary was published"
has "$(cat "$GCLOG")" "service restart helm" "(RESTART) build and restart are one step"

# --- case: nothing to build restarts nothing ----------------------------------
# A restart on every tick would bounce the board every 5 minutes forever.
fixture
cache_binary
run_build --deploy
eq "$RC" 0 "(NORESTART) exits 0 with the binary already current"
hasnt "$(cat "$GCLOG")" "service restart" "(NORESTART) an up-to-date binary restarts nothing"

# --- case: a failed restart is a failure --------------------------------------
# The binary is published but not serving; that is exactly the "landed but
# inert" state this order exists to prevent, so it must not exit 0.
fixture
RESTART_FAIL=1
run_build --deploy
RESTART_FAIL=""
eq "$RC" 1 "(RCFAIL) a failed restart exits non-zero"
has "$ERR" "not yet serving" "(RCFAIL) names the half-applied state"
present "$STATE/restart-pending" "(RCFAIL) the unfinished restart is recorded for the next run"

# --- case: the next run finishes a restart the last one could not -------------
# Two runs, because the hole only opens on the second. Run 1 publishes and its
# restart fails, which leaves the binary NEWER than every source: nothing is
# stale any more, so the up-to-date branch is the only one any later run can
# reach. Exiting 0 there — "is up to date", no restart — is what would make a
# transient restart failure permanent, the old process serving the old inode for
# as long as nobody edits a source file again. That is the "landed but inert"
# state this whole order exists to end, reached the other way round.
fixture
RESTART_FAIL=1
run_build --deploy
RESTART_FAIL=""
eq "$RC" 1 "(RETRY) run 1's restart fails"
present "$STATE/bin/helm-svc" "(RETRY) run 1 published the binary regardless"
rm -f "$RECORD"; : > "$GCLOG"          # judge run 2 on its own calls alone
run_build --deploy
eq "$RC" 0 "(RETRY) run 2 exits 0"
absent "$RECORD" "(RETRY) run 2 rebuilds nothing — the binary is current"
has "$(cat "$GCLOG")" "service restart helm" "(RETRY) run 2 restarts onto it anyway"
absent "$STATE/restart-pending" "(RETRY) and the record is cleared by the restart that worked"
rm -f "$RECORD"; : > "$GCLOG"
run_build --deploy
eq "$RC" 0 "(RETRY) run 3 exits 0"
hasnt "$(cat "$GCLOG")" "service restart" "(RETRY) a served binary is not restarted again every tick"

# --- case: a hand-run build reaches the service on the next tick --------------
# `gc-helm-build.sh` with no --deploy publishes and restarts nothing by design.
# Before the pending record existed, that binary was inert until the next SOURCE
# edit made it stale again — the same dead end as a failed restart, entered by
# someone building by hand.
fixture
run_build
eq "$RC" 0 "(HANDBUILT) a hand-run build exits 0"
hasnt "$(cat "$GCLOG")" "service restart" "(HANDBUILT) and restarts nothing itself"
rm -f "$RECORD"; : > "$GCLOG"
run_build --deploy
eq "$RC" 0 "(HANDBUILT) the next deploy tick exits 0"
absent "$RECORD" "(HANDBUILT) with nothing left to build"
has "$(cat "$GCLOG")" "service restart helm" "(HANDBUILT) and serves what the hand build left"

# --- case: a deploy never restarts onto a binary it just condemned ------------
# The gate exists to keep an unreadable binary out of service, so reporting one
# must not be the step that puts it there. The restart stub is set to fail, so a
# run that reached it could not go on to report the readability failure instead.
fixture
cache_binary
touch_source
CITY="$STATE_CITY"
PROBE_FAIL_BUILT="$SKEW_MSG"
RESTART_FAIL=1
run_build --deploy
RESTART_FAIL=""
eq "$RC" 1 "(DEADEND) exits non-zero"
eq "$(status_kind)" "unreadable" "(DEADEND) build-status says why"
present "$RECORD" "(DEADEND) the build did happen"
has "$ERR" "CANNOT READ" "(DEADEND) and the failure it reports is the unreadable one"
hasnt "$(cat "$GCLOG")" "service restart" "(DEADEND) the service was not restarted onto it"
absent "$STATE/restart-pending" "(DEADEND) and no later run is told to finish that restart"

# --- case: nor is a restart the last run left pending -------------------------
# The marker outlives the run that wrote it, and the up-to-date branch is the
# only one a later run can reach. So the probe has to be asked there first, or
# the retry serves what the probe would have condemned.
fixture
cache_binary
CITY="$STATE_CITY"
PROBE_FAIL_CACHED="$SKEW_MSG"
printf '%s\n' "$BEADS_VERSION" > "$STATE/probe-failed"   # already tried: no rebuild left
: > "$STATE/restart-pending"
run_build --deploy
eq "$RC" 1 "(CONDEMNED) exits non-zero"
eq "$(status_kind)" "unreadable" "(CONDEMNED) build-status says why"
absent "$RECORD" "(CONDEMNED) the latch means nothing is rebuilt"
hasnt "$(cat "$GCLOG")" "service restart" "(CONDEMNED) and the pending restart is not run onto it"
present "$STATE/restart-pending" "(CONDEMNED) the marker is kept for a binary that can serve"

# ==============================================================================
# BUILD-STATUS RECORD — the seam the board's PACK rows read
# ==============================================================================
#
# Nothing in the running system builds this binary, so a helm-svc older than
# services/helm serves a stale dashboard in silence. This record is the only
# thing that can say so, and it is read by services/helm itself — which means a
# record that lies is a board that lies.

# --- case: a successful build records what it built ---------------------------
fixture
REV_A="$(commit_fixture "$ROOT" || true)"
[ -n "$REV_A" ] && ok "(STATUS) the fixture has a revision to record" \
                || bad "(STATUS) could not create a fixture repo; the revision assertions would pass vacuously"
run_build
eq "$RC" 0 "(STATUS) the build exits 0"
present "$STATE/build-status.json" "(STATUS) a record is written"
eq "$(status_field component)" "helm" "(STATUS) it names the component"
eq "$(status_field last_build_rc)" "0" "(STATUS) rc 0"
eq "$(status_field source_rev)" "$REV_A" "(STATUS) source_rev is the revision the tick saw"
eq "$(status_field binary_rev)" "$REV_A" "(STATUS) a successful build makes binary_rev match it"
eq "$(status_field restart_pending)" "true" "(STATUS) a hand build publishes without restarting, and says so"
[ -n "$(status_field built_at)" ] && ok "(STATUS) built_at is stamped" || bad "(STATUS) built_at is empty"
[ -n "$(status_field checked_at)" ] && ok "(STATUS) checked_at is stamped" || bad "(STATUS) checked_at is empty"

# --- case: a failed build keeps the last good binary in the record ------------
# The binary that is still SERVING is the one the record must name. Moving
# binary_rev to the revision that failed to build would report the cadence as
# current at a commit it cannot run.
BUILT_AT_A="$(status_field built_at)"
# A content change, not just a touch: `git commit` with nothing staged fails,
# and REV_B would come back empty with the assertions comparing '' to ''.
echo '// second revision' >> "$ROOT/services/helm/cmd/helm-svc/main.go"
REV_B="$(commit_fixture "$ROOT" || true)"
[ "$REV_B" != "$REV_A" ] && ok "(STATUSFAIL) the tree moved to a second revision" \
                         || bad "(STATUSFAIL) the fixture did not advance; the gap cannot be shown"
FAIL_BUILD=1
run_build
FAIL_BUILD=""
eq "$RC" 1 "(STATUSFAIL) a failed build exits 1"
eq "$(status_field last_build_rc)" "1" "(STATUSFAIL) the failure is recorded"
eq "$(status_field source_rev)" "$REV_B" "(STATUSFAIL) source_rev follows the tree"
eq "$(status_field binary_rev)" "$REV_A" "(STATUSFAIL) binary_rev stays on what is still serving"
eq "$(status_field built_at)" "$BUILT_AT_A" "(STATUSFAIL) and so does built_at"

# --- case: a tick with nothing to do still reports ----------------------------
# checked_at is the only field a quiet tick moves, so it is the only thing that
# can distinguish a healthy no-op from a build order that stopped running.
fixture
REV_C="$(commit_fixture "$ROOT" || true)"
run_build
rm -f "$RECORD"
CHECKED_1="$(status_field checked_at)"
sleep 1
run_build
eq "$RC" 0 "(STATUSNOOP) the no-op tick exits 0"
absent "$RECORD" "(STATUSNOOP) and builds nothing"
eq "$(status_field last_build_rc)" "0" "(STATUSNOOP) it still reports success"
eq "$(status_field binary_rev)" "$REV_C" "(STATUSNOOP) binary_rev still names the revision the binary was built from"
[ "$(status_field checked_at)" != "$CHECKED_1" ] \
    && ok "(STATUSNOOP) checked_at advanced — the build order is demonstrably alive" \
    || bad "(STATUSNOOP) checked_at did not move; a stopped build order would look healthy"

# --- case: a deletion-only change still rebuilds ------------------------------
# `find -newer` can only test files that still exist. Delete a source and
# nothing remaining has to be newer than the binary, so the mtime test alone
# takes the no-op path and records the new revision for a binary built from the
# old one — the board's PACK row then reads "current" exactly when the cadence
# is serving the previous binary.
fixture
echo 'package main' > "$ROOT/services/helm/cmd/helm-svc/doomed.go"
REV_D="$(commit_fixture "$ROOT" || true)"
run_build
eq "$RC" 0 "(STATUSDEL) the first build exits 0"
eq "$(status_field binary_rev)" "$REV_D" "(STATUSDEL) the binary starts current at its own revision"
rm -f "$RECORD"
git -C "$ROOT" rm -q "services/helm/cmd/helm-svc/doomed.go" >/dev/null 2>&1 || true
REV_E="$(commit_fixture "$ROOT" || true)"
[ -n "$REV_E" ] && [ "$REV_E" != "$REV_D" ] \
    && ok "(STATUSDEL) the deletion advanced the tree" \
    || bad "(STATUSDEL) the fixture did not advance; the stale binary cannot be shown"
# The control: without it this case would pass through the ordinary mtime arm
# and prove nothing about the deletion.
[ -z "$(find "$ROOT/services/helm" \( -name '*.go' -o -name go.mod -o -name go.sum \) -newer "$STATE/bin/helm-svc" -print -quit 2>/dev/null)" ] \
    && ok "(STATUSDEL) and left nothing newer than the binary — the mtime test is blind here" \
    || bad "(STATUSDEL) something is newer than the binary; the case would pass without reaching the blind spot"
run_build
eq "$RC" 0 "(STATUSDEL) the next tick exits 0"
present "$RECORD" "(STATUSDEL) the deleted input forces a rebuild"
eq "$(status_field binary_rev)" "$REV_E" "(STATUSDEL) so binary_rev names a revision the binary was really built from"

# --- case: published but not serving -----------------------------------------
fixture
commit_fixture "$ROOT" >/dev/null 2>&1 || true
RESTART_FAIL=1
run_build --deploy
RESTART_FAIL=""
eq "$RC" 1 "(STATUSPEND) a failed restart exits 1"
eq "$(status_field restart_pending)" "true" "(STATUSPEND) the record says the new binary is not serving"
eq "$(status_field last_build_rc)" "0" "(STATUSPEND) the BUILD did not fail — only the restart"
: > "$GCLOG"
run_build --deploy
eq "$RC" 0 "(STATUSPEND) the retry tick exits 0"
eq "$(status_field restart_pending)" "false" "(STATUSPEND) and the record clears once it is serving"

# --- case: the record is published atomically ---------------------------------
# A reader polls this file; catching it half-written would be a board that
# reports a component it cannot parse.
fixture
commit_fixture "$ROOT" >/dev/null 2>&1 || true
run_build
if [ -n "$(find "$STATE" -maxdepth 1 -name '.build-status.*' -print -quit)" ]; then
    bad "(STATUSTMP) a staging file survived the publish"
else
    ok "(STATUSTMP) no staging file survives the publish"
fi
grep -q 'mv -f "$tmp" "$STATUS"' "$BUILD" \
    && ok "(STATUSTMP) the record is published by rename, never written in place" \
    || bad "(STATUSTMP) the record is no longer published by rename"

# ==============================================================================
# STATIC GUARDS
# ==============================================================================

# The regression that caused the tk-m18ml incident is pointing the toolchain
# straight at the shared, unbounded $GOTMP. Whatever else the build line grows,
# it must hand the toolchain a dir this invocation owns and deletes.
if grep -qE '(TMPDIR|GOTMPDIR)="\$GOTMP"' "$BUILD"; then
    bad "(STATIC) build points TMPDIR/GOTMPDIR at the unbounded \$GOTMP again"
else
    ok "(STATIC) build never points TMPDIR/GOTMPDIR at the unbounded \$GOTMP"
fi
grep -q 'GOTMPDIR="\$GOTMP_RUN"' "$BUILD" \
    && ok "(STATIC) build is handed the per-invocation scratch dir" \
    || bad "(STATIC) build no longer uses \$GOTMP_RUN"

# On the degraded path $GOTMP_RUN IS the shared root, so cleanup must be
# ownership-guarded: unguarded, a fallback triggered by ENOSPC — mkdir fails
# while the directory is still perfectly writable — would rm -rf every
# concurrent build's scratch, on the full disk this bounding exists to prevent.
# (DEGRADE) cannot demonstrate that: its fallback is triggered by unwritability,
# and the same unwritability defeats the destructive rm. So it is pinned here.
grep -q 'GOTMP_RUN_OWNED" -eq 1' "$BUILD" \
    && ok "(STATIC) cleanup only removes scratch this invocation created" \
    || bad "(STATIC) cleanup is no longer ownership-guarded — a degraded run can rm -rf the shared root"

# The launcher must contain no build. (NOBUILD) proves the current one does not
# build for the cases it exercises; this refuses the whole shape, so a future
# edit cannot reintroduce a build down some path the cases do not reach.
if grep -qE '(go build|GC_GO_BIN|GOTMPDIR|newer_than_binary)' "$SVC"; then
    bad "(STATIC) the launcher has grown a build again — it has 5s, and the build needs 12.5s"
else
    ok "(STATIC) the launcher contains no build"
fi
grep -q 'exec "\$BIN"' "$SVC" \
    && ok "(STATIC) the launcher still exec's, so SIGTERM reaches the Go process" \
    || bad "(STATIC) the launcher no longer exec's the binary"

# The isolation is load-bearing, so it is asserted rather than assumed. If a
# future edit drops the strip above, this fails in the suite instead of being
# discovered as a replaced production binary.
[ -z "${GC_CITY:-}${GC_CITY_PATH:-}${GC_CITY_ROOT:-}${GC_SERVICE_STATE_ROOT:-}" ] \
    && ok "(ISOLATION) the ambient city is stripped for the whole suite" \
    || bad "(ISOLATION) a city env var survived — cases can reach the live service root"
case "$SAFE_NAME" in
    helm) bad "(ISOLATION) the fallback cases build under the REAL service name" ;;
    *)    ok "(ISOLATION) fallback cases build under a sacrificial service name" ;;
esac

echo ""
echo "helm build/start split: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
