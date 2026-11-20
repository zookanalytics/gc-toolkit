#!/usr/bin/env bash
# gc-build.sh — build one of the pack's compiled components OUT OF BAND from
# everything that runs it. Each caller execs the binary this leaves behind and
# builds nothing, and a failed build leaves the LAST GOOD binary in place:
#   helm  helm-svc, the board backend, run by the gc-helm-svc.sh launcher. The
#         supervisor gives a proxy_process 5s to answer its health probe, and
#         a cold build of helm-svc takes longer (5 to 6s at loads of 14 to
#         20), so a cold build in the launcher's start path is killed
#         mid-compile.
#   gctk  the merge cadence's compiled data plane, exec'd by the cadence
#         scripts whose logic it carries. A build inside the cadence would put
#         a Go toolchain in the path of a merge, and a failed one would take the
#         cadence down with it.
# Usage:
#   gc-build.sh <component>            build iff the binary is missing or stale
#   gc-build.sh <component> --deploy   order mode. helm is a supervisor service:
#                                      a city that does not run it builds
#                                      nothing, and the service is restarted
#                                      onto a published binary not yet serving.
#                                      gctk is a command that serves the moment
#                                      it lands, so --deploy does what a hand
#                                      run does.
# A binary is stale when a source is newer than it (find -newer), or when the
# recorded binary_rev differs from the revision this run sees, because find
# -newer is blind to an input a commit deleted. The revision is one hash over
# the binary's inputs at HEAD, the folders it compiles from and the module's
# go.mod and go.sum, so a merge that touches none of them neither rebuilds nor
# republishes.
# Exit: 0 current or built, and for helm under --deploy serving · 1 the build
# or the restart failed, including a build owed with no Go toolchain or with
# no Go release named in go.mod (the previous binary is left exactly as it
# was) · 2 usage. A current binary needs no toolchain.
# Writes, under the component's state root <city>/.gc/services/<name>:
#   bin/<binary>       the published binary
#   build-status.json  the record of what the component serves: source_rev
#                      against binary_rev, built_at, last_build_rc,
#                      restart_pending, behind_main (commits behind
#                      origin/<default> under the component's inputs,
#                      report-only) and checked_at
# Env: GC_CITY_PATH / GC_CITY / GC_CITY_ROOT (the city), else the city_path
# `gc service list --json` reports; GC_GO_BIN. Per component, with <C> one of
# HELM and GCTK: GC_<C>_STATE_ROOT (the state root, overriding the city's),
# GC_<C>_GOTMP (Go scratch root, default /var/tmp/gotmp), GC_<C>_GC_BIN (the gc
# to call), GC_<C>_ORIGIN_FETCH_TTL (seconds between origin fetches for
# behind_main, default 1800; 0 leans on reconcile-rig-checkouts' fetch). helm
# only: GC_HELM_SERVICE_NAME. GC_SERVICE_STATE_ROOT is not read: the supervisor
# sets it for whichever service spawned the caller, so an inherited one would
# publish this component into another one's state root.
# Callers: orders/helm-build, orders/gctk-build.
set -euo pipefail

usage() { echo "usage: gc-build.sh <helm|gctk> [--deploy]" >&2; }

COMPONENT=""
DEPLOY=0
for arg in "$@"; do
    case "$arg" in
        --deploy) DEPLOY=1 ;;
        -*) echo "gc-build: unknown argument: $arg" >&2; usage; exit 2 ;;
        *)
            if [ -n "$COMPONENT" ]; then
                echo "gc-build: one component per run, not '$COMPONENT' and '$arg'" >&2; usage; exit 2
            fi
            COMPONENT="$arg" ;;
    esac
done

# The component table: what each binary compiles from, what it compiles to, and
# which per-component steps it takes. Everything below the table is one body for
# every component.
#   DIR      the component's own folder, where its main package and anything it
#            embeds live (helm embeds web/dist).
#   IMPORTS  every other folder of this repository it compiles from. helm
#            imports gctk's domain packages, prstatus among them, the status core
#            the PR-label writer also derives from. gctk compiles from its own
#            folder alone (services/gctk/deps_test.go).
#   SERVICE  the supervisor service that runs the binary, empty for a command.
#            A service gates --deploy on the city running it, takes its state
#            root from the city's service listing, and is restarted onto a
#            published binary.
#   STAMP    1: stamp the binary's revision into it at link time, for the
#            readers that compare the binary itself against the checkout.
case "$COMPONENT" in
    helm)
        DIR=services/helm IMPORTS=(services/gctk) PKG=./cmd/helm-svc BIN_NAME=helm-svc
        SERVICE="${GC_HELM_SERVICE_NAME:-helm}" STAMP=0
        STATE_ROOT_ENV=GC_HELM_STATE_ROOT
        GOTMP="${GC_HELM_GOTMP:-/var/tmp/gotmp}"
        GC_BIN="${GC_HELM_GC_BIN:-gc}"
        FETCH_TTL="${GC_HELM_ORIGIN_FETCH_TTL:-1800}"
        ;;
    gctk)
        DIR=services/gctk IMPORTS=() PKG=./cmd/gctk BIN_NAME=gctk
        SERVICE="" STAMP=1
        STATE_ROOT_ENV=GC_GCTK_STATE_ROOT
        GOTMP="${GC_GCTK_GOTMP:-/var/tmp/gotmp}"
        GC_BIN="${GC_GCTK_GC_BIN:-gc}"
        FETCH_TTL="${GC_GCTK_ORIGIN_FETCH_TTL:-1800}"
        ;;
    "") echo "gc-build: name the component to build" >&2; usage; exit 2 ;;
    *)  echo "gc-build: unknown component: $COMPONENT" >&2; usage; exit 2 ;;
esac
ME="gc-build $COMPONENT"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# The binary's inputs, relative to ROOT, the module root: go.mod and go.sum,
# which pin every dependency the binary compiles, and the folders it compiles
# from. SOURCE_REV (the staleness identity), newer_than_binary (the mtime scan)
# and behind_main all span exactly these, so a change confined to a folder the
# binary imports rebuilds it, and a dependency bump rebuilds both binaries.
INPUTS=(go.mod go.sum "$DIR" ${IMPORTS[@]+"${IMPORTS[@]}"})

# The city this run builds for: the env chain an order's process and a shell
# inside the city both carry, else the city_path of the service listing below,
# which answers a run whose environment names no city.
CITY_ROOT="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"

# One `gc service list` says whether this city runs the component's service,
# where that service's state root is (authoritative: it beats reproducing
# gascity's StateRootOrDefault here), and which city this is when the
# environment does not say. A command component whose environment names its city
# has nothing to ask it. Only a SUCCESSFUL listing that omits the service is
# proof of absence; an erroring one must not silently stop deploys.
SERVICES=""
if [ -n "$SERVICE" ] || [ -z "$CITY_ROOT" ]; then
    if ! SERVICES="$("$GC_BIN" service list --json 2>/dev/null)"; then
        SERVICES=""
        if [ -n "$SERVICE" ] && [ "$DEPLOY" -eq 1 ]; then
            echo "$ME: could not list services; proceeding on the assumption '$SERVICE' is registered" >&2
        fi
    fi
fi
if [ -n "$SERVICE" ] && [ -n "$SERVICES" ]; then
    # jq -e: 1 = found nothing; anything else = jq could not run (not absent).
    set +e
    printf '%s' "$SERVICES" | jq -e --arg n "$SERVICE" \
        '[.services[]? | select((.service_name // .name) == $n)] | length > 0' >/dev/null 2>&1
    _q_rc=$?
    set -e
    if [ "$_q_rc" -eq 1 ]; then
        # This city does not run the service; a hand-run build is not gated.
        if [ "$DEPLOY" -eq 1 ]; then
            echo "$ME: no '$SERVICE' service in this city; nothing to deploy"
            exit 0
        fi
    elif [ "$_q_rc" -ne 0 ]; then
        echo "$ME: could not read the service listing (jq exit $_q_rc); proceeding" >&2
    fi
fi
if [ -z "$CITY_ROOT" ] && [ -n "$SERVICES" ]; then
    CITY_ROOT="$(printf '%s' "$SERVICES" | jq -r '.city_path // empty' 2>/dev/null || true)"
fi

# State root: the component's override, else for a service the root the listing
# reports for it, else <city>/.gc/services/<name>. A run that resolves none of
# them refuses rather than guessing: a binary published to the wrong root
# succeeds, and nothing ever serves it.
STATE_NAME="${SERVICE:-$COMPONENT}"
STATE_ROOT="${!STATE_ROOT_ENV:-}"
if [ -z "$STATE_ROOT" ] && [ -n "$SERVICE" ] && [ -n "$SERVICES" ]; then
    _city="$(printf '%s' "$SERVICES" | jq -r '.city_path // empty' 2>/dev/null || true)"
    _root="$(printf '%s' "$SERVICES" | jq -r --arg n "$SERVICE" \
        'first(.services[]? | select((.service_name // .name) == $n) | .state_root // empty) // empty' 2>/dev/null || true)"
    case "$_root" in
        "")  ;;                              # nothing reported; fall through
        /*)  STATE_ROOT="$_root" ;;          # already absolute
        *)   [ -n "$_city" ] && STATE_ROOT="$_city/$_root" ;;
    esac
fi
if [ -z "$STATE_ROOT" ] && [ -n "$CITY_ROOT" ]; then
    STATE_ROOT="$CITY_ROOT/.gc/services/$STATE_NAME"
fi
if [ -z "$STATE_ROOT" ]; then
    echo "$ME: cannot locate the city runtime dir; set GC_CITY_PATH or $STATE_ROOT_ENV, or run where \`gc service list --json\` reports a city_path" >&2
    exit 1
fi

BIN_DIR="$STATE_ROOT/bin"
BIN="$BIN_DIR/$BIN_NAME"
mkdir -p "$BIN_DIR"

# A service's publish that nothing has restarted onto yet. It is written before
# the restart and removed only by a restart that succeeded (see
# restart_service), so a failed restart carries to the next run. A command has
# no restart, and no marker.
RESTART_PENDING="$STATE_ROOT/restart-pending"

STATUS="$STATE_ROOT/build-status.json"
# SOURCE_REV is the identity of the binary's committed inputs, deletions
# included: git's hash of the listing `git ls-tree HEAD` gives for INPUTS, the
# tree of each folder and the blob of go.mod and go.sum. The repo HEAD would
# move on every merge to main and cost a rebuild, and for a service a restart,
# for each. A tick that cannot list them (git absent, no commit) leaves it
# empty, never the hash of an empty listing.
SOURCE_REV=""
if _listing="$(git -C "$ROOT" ls-tree HEAD -- "${INPUTS[@]}" 2>/dev/null)" && [ -n "$_listing" ]; then
    SOURCE_REV="$(printf '%s\n' "$_listing" | git -C "$ROOT" hash-object --stdin 2>/dev/null || true)"
fi

# behind_main — how far this checkout is behind origin/<default> under the
# binary's inputs, REPORT-ONLY. Everything above keys on the LOCAL checkout:
# SOURCE_REV lists HEAD's inputs, newer_than_binary scans HEAD's files.
# So a checkout parked off-main (another branch, or one not fast-forwarded)
# keeps its binary current with THAT branch — source_rev == binary_rev — while
# what it serves is behind main. Nothing above can see that, so the record
# would read a false "current". This counts the commits origin/<default>
# carries under the binary's inputs that HEAD lacks.
#
# It NEVER feeds need_build. A checkout may be off-main on purpose, and a rebuild
# on every unrelated main merge is exactly what the SOURCE_REV identity exists
# to avoid — the requirement is to REPORT drift, not to rebuild
# on it. The comparison wants a fresh origin ref: reconcile-rig-checkouts fetches
# origin on its own cadence, so it is usually already current, and this fetch is
# bounded to at most one ATTEMPT per FETCH_TTL for each state root (0 disables
# it and leans on reconcile) so a 5-minute tick does not fetch every time, and a
# failing origin costs one attempt per TTL rather than one per tick. Every step
# degrades to "gap unknown" (0), never to a failed build.
BEHIND_MAIN=0
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    DEFAULT_REF="$(git -C "$ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
    case "$FETCH_TTL" in ''|*[!0-9]*) FETCH_TTL=1800 ;; esac
    FETCH_MARK="$STATE_ROOT/origin-fetch-at"
    NOW_S="$(date +%s 2>/dev/null || echo 0)"
    LAST_S=0
    [ -f "$FETCH_MARK" ] && LAST_S="$(cat "$FETCH_MARK" 2>/dev/null || echo 0)"
    case "$LAST_S" in ''|*[!0-9]*) LAST_S=0 ;; esac
    # Record the attempt BEFORE fetching, not only on success. The cost the
    # cadence bounds is the fetch ATTEMPT, so a marker advanced only after a
    # successful fetch leaves an unreachable or unauthenticated origin
    # re-attempting on every later tick. Advancing it here holds a failing
    # origin to one attempt per TTL; the gap below still reads off the last
    # origin ref, so a lost fetch degrades to a stale count, never a failure.
    if [ "$FETCH_TTL" -gt 0 ] && [ "$((NOW_S - LAST_S))" -ge "$FETCH_TTL" ]; then
        printf '%s\n' "$NOW_S" > "$FETCH_MARK" 2>/dev/null || true
        git -C "$ROOT" fetch --quiet --no-tags origin "${DEFAULT_REF#origin/}" 2>/dev/null || true
    fi
    # Commits the default branch carries under the binary's inputs that HEAD
    # lacks: 0 when on main and current, when ahead, or when the ref is absent.
    _behind="$(git -C "$ROOT" rev-list --count "HEAD..$DEFAULT_REF" -- "${INPUTS[@]}" 2>/dev/null || true)"
    case "$_behind" in ''|*[!0-9]*) _behind=0 ;; esac
    BEHIND_MAIN="$_behind"
fi

# A field of the previous record, or empty. A build that failed keeps the last
# good binary serving, so its built_at and binary_rev must survive the failure
# that did not replace them.
prev_field() { # <key>
    [ -f "$STATUS" ] || return 0
    jq -r --arg k "$1" '(.[$k] // "") | tostring' "$STATUS" 2>/dev/null || true
}

# build-status.json — what this component is SERVING versus what the sources
# say. Nothing else can answer it: every caller execs a prebuilt binary, so one
# older than its sources serves in silence.
#
# Every run that reaches a build decision writes one, the no-op tick included:
# checked_at is what says the build order itself is still running, and it is the
# only field a quiet tick moves. Published by atomic rename, so a reader polling
# the file never catches it half-written. Every step degrades to leaving the old
# record in place, because a status file is a report and losing one must not
# fail a build.
write_record() { # <last_build_rc> <binary_rev> <built_at>
    local rc="$1" brev="$2" bat="$3" pending="false" tmp
    if [ -n "$SERVICE" ] && [ -e "$RESTART_PENDING" ]; then pending="true"; fi
    tmp="$(mktemp "$STATE_ROOT/.build-status.XXXXXX" 2>/dev/null)" || return 0
    if jq -n --arg component "$STATE_NAME" --arg built_at "$bat" \
        --arg source_rev "$SOURCE_REV" --arg binary_rev "$brev" \
        --argjson last_build_rc "$rc" --argjson restart_pending "$pending" \
        --argjson behind_main "$BEHIND_MAIN" \
        --arg checked_at "$(date -u +%FT%TZ)" \
        '{component: $component, built_at: $built_at, source_rev: $source_rev,
          binary_rev: $binary_rev, last_build_rc: $last_build_rc,
          restart_pending: $restart_pending, behind_main: $behind_main,
          checked_at: $checked_at}' \
        > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$STATUS" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null
    else
        rm -f -- "$tmp" 2>/dev/null
    fi
    return 0
}

# Go toolchain: override, PATH, then the conventional system install. It is
# needed only once there is something to build. Whichever go starts the build,
# the build runs the Go release go.mod names (go_release).
GO="${GC_GO_BIN:-}"
if [ -z "$GO" ]; then
    if command -v go >/dev/null 2>&1; then GO="go"; else GO="/usr/local/go/bin/go"; fi
fi

# go_release <go.mod> — the Go release the file names: its toolchain line, else
# go and the version on its go line, the choice CI's actions/setup-go makes from
# the same file (parseGoVersionFile). Prints nothing when the file names none.
go_release() {
    local line go_line="" toolchain_line=""
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ ^toolchain[[:space:]]+(go[0-9]+\.[0-9]+(\.[0-9]+|rc[0-9]+))([[:space:]]|$) ]]; then
            toolchain_line="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^go[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)([[:space:]]|$) ]]; then
            go_line="go${BASH_REMATCH[1]}"
        fi
    done < "$1"
    printf '%s\n' "${toolchain_line:-$go_line}"
}

# Build inputs: *.go, go.mod/go.sum (explicit — `-name '*.go'` misses them, and
# a dependency-only bump must still rebuild), and web/dist (helm's go:embed).
# Scanned across every one of INPUTS, so an edit in a folder the binary imports
# is seen as newer. node_modules pruned.
newer_than_binary() {
    local _in _paths=()
    for _in in "${INPUTS[@]}"; do _paths+=("$ROOT/$_in"); done
    find "${_paths[@]}" -name node_modules -prune -o \( -name '*.go' -o -name go.mod -o -name go.sum -o -path "$ROOT/$DIR/web/dist/*" \) -newer "$BIN" -print -quit 2>/dev/null
}

# Is the pid alive? Tells a live scratch dir from a stranded one.
pid_alive() {
    if [ -d /proc ]; then
        [ -e "/proc/$1" ]
    else
        kill -0 "$1" 2>/dev/null
    fi
}

# Restart the service onto the published binary; clear the pending marker only
# on success. "Published" and "serving" differ, and only the first is on disk: a
# failed restart leaves a binary newer than every source, so no later tick would
# ever be stale — the marker is what carries the unfinished restart to the next
# run.
restart_service() {
    echo "$ME: restarting service '$SERVICE'"
    if ! "$GC_BIN" service restart "$SERVICE"; then
        echo "$ME: 'gc service restart $SERVICE' failed; the new binary is published but not yet serving" >&2
        return 1
    fi
    # Only success clears it; a failed clear costs one redundant restart.
    rm -f -- "$RESTART_PENDING" 2>/dev/null \
        || echo "$ME: could not clear $RESTART_PENDING; the next run will restart again" >&2
    return 0
}

# Reclaim stranded staging files; an hour is far past the slowest build, so
# nothing in flight can be swept.
find "$BIN_DIR" -maxdepth 1 -type f -name ".$BIN_NAME.build.*" -mmin +60 -delete 2>/dev/null || true

# `find -newer` cannot see a DELETED input: after a deletion-only commit
# nothing that remains is newer than the binary. binary_rev is the revision the
# binary was actually built from, so it is what separates a current binary from
# one the tree has moved past.
need_build=0
if [ ! -x "$BIN" ]; then
    need_build=1
elif [ -n "$(newer_than_binary)" ]; then
    need_build=1
elif [ -n "$SOURCE_REV" ] && [ "$(prev_field binary_rev)" != "$SOURCE_REV" ]; then
    need_build=1
fi
if [ "$need_build" -eq 0 ]; then
    # No input is newer and the record already names this revision, so the
    # binary IS the current revision — that is what makes recording it here
    # honest rather than a guess. built_at comes off the binary's own mtime when
    # no earlier record names it.
    CURRENT_BUILT_AT="$(prev_field built_at)"
    [ -n "$CURRENT_BUILT_AT" ] || CURRENT_BUILT_AT="$(date -u -r "$BIN" +%FT%TZ 2>/dev/null || true)"
    # A tick that could not read the revision (git absent, a held index.lock)
    # has learned nothing about the binary: keep naming the revision it was
    # built from, or the next tick that can read sees an empty binary_rev and
    # rebuilds a current binary, and restarts a service onto it.
    CURRENT_REV="$SOURCE_REV"
    [ -n "$CURRENT_REV" ] || CURRENT_REV="$(prev_field binary_rev)"

    # Current is not serving: an unrestarted publish leaves its marker, and this
    # branch is the only one a later run can reach.
    if [ -n "$SERVICE" ] && [ "$DEPLOY" -eq 1 ] && [ -e "$RESTART_PENDING" ]; then
        echo "$ME: $BIN is up to date but not yet serving; retrying the restart"
        if ! restart_service; then
            write_record 0 "$CURRENT_REV" "$CURRENT_BUILT_AT"
            exit 1
        fi
    fi
    echo "$ME: $BIN is up to date"
    write_record 0 "$CURRENT_REV" "$CURRENT_BUILT_AT"
    exit 0
fi

# A build is owed and nothing can perform it: that is a failed build, recorded
# like any other, and $BIN is not touched. A
# city that never gets a gctk binary refuses every lifecycle transition, every
# merge pass and every epic the work skill files, since lifecycle.sh, merge.sh
# and epic.sh have nothing else to exec, and a city that has one keeps it.
if ! command -v "$GO" >/dev/null 2>&1; then
    echo "$ME: BUILD FAILED: no Go toolchain ($GO) to build $ROOT/$DIR; set GC_GO_BIN. $BIN left unchanged" >&2
    write_record 1 "$(prev_field binary_rev)" "$(prev_field built_at)"
    exit 1
fi

# The build runs under GOTOOLCHAIN set to the release go.mod names, so go runs
# that release whatever version $GO is, and downloads it into the module cache
# the first time it is another (https://go.dev/doc/toolchain). A go.mod that
# names no release is a failed build too: the binary would take whichever Go
# the host has, not the one CI tests.
GO_RELEASE="$(go_release "$ROOT/go.mod")"
if [ -z "$GO_RELEASE" ]; then
    echo "$ME: BUILD FAILED: $ROOT/go.mod names no Go release, on a go line such as 'go 1.27.4' or a toolchain line, to build $ROOT/$DIR with. $BIN left unchanged" >&2
    write_record 1 "$(prev_field binary_rev)" "$(prev_field built_at)"
    exit 1
fi

# Linker and cgo scratch goes under $GOTMP, a root this script bounds, never
# the shared temp dir. GOCACHE stays at its default, which is what keeps
# rebuilds fast.
mkdir -p "$GOTMP"

# Bound $GOTMP, where a killed build strands ~300MB per go-link dir on the root
# fs: reclaim dead-pid run.<pid> dirs on sight, and anything else a day old. A
# concurrent build's scratch, whichever component it builds, is fresh AND alive.
for gotmp_entry in "$GOTMP"/run.*; do
    [ -d "$gotmp_entry" ] || continue          # no match: the glob itself
    gotmp_pid="${gotmp_entry##*/run.}"
    case "$gotmp_pid" in ''|*[!0-9]*) continue ;; esac   # not pid-owned
    if pid_alive "$gotmp_pid"; then continue; fi
    rm -rf -- "$gotmp_entry" 2>/dev/null || true
done
find "$GOTMP" -mindepth 1 -maxdepth 1 -mmin +1440 -exec rm -rf -- {} + 2>/dev/null || true

# Build in scratch this invocation owns; every hygiene step degrades rather
# than fails (an unguarded mkdir under set -e would abort on the full disk
# where finishing matters most).
GOTMP_RUN="$GOTMP/run.$$"
GOTMP_RUN_OWNED=0
rm -rf -- "$GOTMP_RUN" 2>/dev/null || true   # a recycled pid inherits nothing
if mkdir "$GOTMP_RUN" 2>/dev/null; then
    GOTMP_RUN_OWNED=1
else
    echo "$ME: cannot create $GOTMP_RUN; building in $GOTMP" >&2
    GOTMP_RUN="$GOTMP"
fi

# One trap for every exit path: drop owned scratch (never the shared root on
# the degraded path) and the staging file.
cleanup() {
    [ "$GOTMP_RUN_OWNED" -eq 1 ] && rm -rf -- "$GOTMP_RUN" 2>/dev/null
    [ -n "${BIN_TMP:-}" ] && rm -f -- "$BIN_TMP" 2>/dev/null
    return 0
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# A stamping component's binary carries the revision it was built from
# (`gctk version`), stamped as SOURCE_REV, so doctor/check-cadence-live
# compares the identity the build records against the checkout rather than a
# commit hash. A build with no revision to stamp falls back to the toolchain's
# VCS stamp.
GO_BUILD_FLAGS=()
if [ "$STAMP" -eq 1 ] && [ -n "$SOURCE_REV" ]; then
    GO_BUILD_FLAGS+=(-ldflags "-X main.sourceRev=$SOURCE_REV")
fi

# Publish only via atomic rename from a scratch file beside $BIN: an in-place
# -o could truncate the live binary into a half-written file that still passes
# a caller's -x test.
build_ok=0
BIN_TMP=""
echo "$ME: building $ROOT/$DIR -> $BIN with $GO_RELEASE"
if BIN_TMP="$(mktemp "$BIN_DIR/.$BIN_NAME.build.XXXXXX" 2>/dev/null)"; then
    if ( cd "$ROOT/$DIR" && TMPDIR="$GOTMP_RUN" GOTMPDIR="$GOTMP_RUN" GOTOOLCHAIN="$GO_RELEASE" \
            "$GO" build ${GO_BUILD_FLAGS[@]+"${GO_BUILD_FLAGS[@]}"} -o "$BIN_TMP" "$PKG" ) \
        && chmod +x "$BIN_TMP" && mv -f "$BIN_TMP" "$BIN"; then
        build_ok=1
        BIN_TMP=""      # renamed away; nothing left for cleanup to remove
    fi
fi

if [ "$build_ok" -eq 0 ]; then
    # $BIN was never touched; failing here costs a log line and a retry. The
    # record keeps the LAST GOOD binary's revision and build time, because that
    # is what is still serving — only source_rev moves, and the gap between the
    # two is the whole signal.
    echo "$ME: BUILD FAILED; $BIN left unchanged" >&2
    write_record 1 "$(prev_field binary_rev)" "$(prev_field built_at)"
    exit 1
fi

BUILT_AT="$(date -u +%FT%TZ)"
echo "$ME: built $BIN"

# For a service, build and restart are one step: a binary nothing restarts onto
# is inert. Record the unfinished half BEFORE the restart, so whatever stops
# this run leaves the evidence; it also carries a hand-run build to the next
# tick. The status record is written AFTER the restart either way —
# restart_pending is a fact about the moment the record is taken, and a failed
# restart is exactly the state worth publishing.
if [ -n "$SERVICE" ]; then
    printf 'published %s\n' "$(date -u +%FT%TZ)" > "$RESTART_PENDING" 2>/dev/null \
        || echo "$ME: could not write $RESTART_PENDING; a failed restart will not be retried" >&2
    if [ "$DEPLOY" -eq 1 ] && ! restart_service; then
        write_record 0 "$SOURCE_REV" "$BUILT_AT"
        exit 1
    fi
fi
write_record 0 "$SOURCE_REV" "$BUILT_AT"
