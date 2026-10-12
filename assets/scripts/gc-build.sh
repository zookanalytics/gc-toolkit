#!/usr/bin/env bash
# gc-build.sh — build one of the pack's compiled components OUT OF BAND from
# everything that runs it. Each caller execs the binary this leaves behind and
# builds nothing, and a failed build leaves the LAST GOOD binary in place:
#   helm  helm-svc, the board backend, run by the gc-helm-svc.sh launcher. The
#         supervisor gives a proxy_process 5s to answer its health probe, and
#         this module builds in ~12.5s warm / 2m29s cold, so a build in the
#         launcher's start path is always killed mid-compile.
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
# -newer is blind to an input a commit deleted. The revision is the module
# SUBTREE's tree hash, so a merge that touches nothing under it neither rebuilds
# nor republishes. A helm binary is also stale when it cannot READ the stores it
# serves: that is fixed by the beads library it embedded, while the store schema
# moves under it on a `bd` upgrade, so `helm-svc probe` asks it, and ok is not
# reported without it.
# Exit: 0 current or built, and for helm under --deploy serving · 1 the build
# or the restart failed, including a build owed with no Go toolchain (the
# previous binary is left exactly as it was), or the published helm binary
# cannot read the city's bead stores · 2 usage. A current binary needs no
# toolchain.
# Writes, under the component's state root <city>/.gc/services/<name>:
#   bin/<binary>       the published binary
#   build-status.json  the record the board's PACK rows read: source_rev
#                      against binary_rev, built_at, last_build_rc,
#                      restart_pending, behind_main (commits behind
#                      origin/<default> under the component's sources,
#                      report-only), checked_at, and for helm probe_status and
#                      probe_detail
#   build-status       helm only: `ok <ts>` built/current AND probed readable ·
#                      `unreadable <ts> <why>` · `unprobed <ts>` no city to
#                      probe against · `failed <ts>`
# Env: GC_CITY_PATH / GC_CITY / GC_CITY_ROOT (the city), else the city_path
# `gc service list --json` reports; GC_GO_BIN. Per component, with <C> one of
# HELM and GCTK: GC_<C>_STATE_ROOT (the state root, overriding the city's),
# GC_<C>_GOTMP (Go scratch root, default /var/tmp/gotmp), GC_<C>_GC_BIN (the gc
# to call), GC_<C>_ORIGIN_FETCH_TTL (seconds between origin fetches for
# behind_main, default 1800; 0 leans on reconcile-rig-checkouts' fetch). helm
# only: GC_HELM_SERVICE_NAME, GC_HELM_CITY_PATH (the city to probe),
# GC_HELM_BUILD_PROBE_TIMEOUT (seconds, default 60). GC_SERVICE_STATE_ROOT is
# not read: the supervisor sets it for whichever service spawned the caller, so
# an inherited one would publish this component into another one's state root.
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

# The component table: where each module lives, what it compiles to, and which
# per-component steps it takes. Everything below the table is one body for every
# component.
#   SERVICE  the supervisor service that runs the binary, empty for a command.
#            A service gates --deploy on the city running it, takes its state
#            root from the city's service listing, and is restarted onto a
#            published binary.
#   PROBE    1: ask the binary (`<binary> probe`) whether it can read the city's
#            bead stores before reporting it ok or putting it into service.
#   ICU      1: the module links ICU through a cgo package (Dolt's
#            go-icu-regex), so on macOS the compile is pointed at Homebrew's
#            keg-only icu4c.
#   STAMP    1: stamp the module's revision into the binary at link time, for
#            the readers that compare the binary itself against the checkout.
# PROBE_TIMEOUT is generous on purpose: a false "unreadable" turns a healthy
# city red and buys a futile rebuild, so a cold Dolt open must be allowed to
# finish.
case "$COMPONENT" in
    helm)
        MOD_REL=services/helm PKG=./cmd/helm-svc BIN_NAME=helm-svc
        SERVICE="${GC_HELM_SERVICE_NAME:-helm}" PROBE=1 ICU=1 STAMP=0
        STATE_ROOT_ENV=GC_HELM_STATE_ROOT
        GOTMP="${GC_HELM_GOTMP:-/var/tmp/gotmp}"
        GC_BIN="${GC_HELM_GC_BIN:-gc}"
        FETCH_TTL="${GC_HELM_ORIGIN_FETCH_TTL:-1800}"
        PROBE_CITY="${GC_HELM_CITY_PATH:-}"
        PROBE_TIMEOUT="${GC_HELM_BUILD_PROBE_TIMEOUT:-60}"
        ;;
    gctk)
        MOD_REL=services/gctk PKG=./cmd/gctk BIN_NAME=gctk
        SERVICE="" PROBE=0 ICU=0 STAMP=1
        STATE_ROOT_ENV=GC_GCTK_STATE_ROOT
        GOTMP="${GC_GCTK_GOTMP:-/var/tmp/gotmp}"
        GC_BIN="${GC_GCTK_GC_BIN:-gc}"
        FETCH_TTL="${GC_GCTK_ORIGIN_FETCH_TTL:-1800}"
        PROBE_CITY="" PROBE_TIMEOUT=0
        ;;
    "") echo "gc-build: name the component to build" >&2; usage; exit 2 ;;
    *)  echo "gc-build: unknown component: $COMPONENT" >&2; usage; exit 2 ;;
esac
ME="gc-build $COMPONENT"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/../../$MOD_REL" && pwd)"
if [ "$ICU" -eq 1 ]; then
    # shellcheck source=icu4c-cgo.sh
    . "$HERE/icu4c-cgo.sh" || { echo "$ME: cannot source icu4c-cgo.sh from $HERE" >&2; exit 1; }
fi

# Every `replace <module> => <local path>` in the module's go.mod points at a
# sibling module whose sources are compiled into the binary: helm replaces in
# services/gctk, the prstatus tri-state core the PR-label writer also derives
# from. Those sources are build inputs, so SOURCE_REV (the staleness identity),
# newer_than_binary (the mtime scan) and behind_main all span them: a change
# confined to a replaced sibling must rebuild the binary, or it serves stale
# logic while every other reader of that sibling has moved. Reading the replace
# directives rather than naming the siblings keeps every future local module
# covered by construction.
local_dep_mods() {
    awk '
        function rhs(   i) { for (i = 1; i <= NF; i++) if ($i == "=>") return $(i + 1); return "" }
        $1 == "replace" && $2 == "(" { inblock = 1; next }
        inblock && $1 == ")"         { inblock = 0; next }
        $1 == "replace" && /=>/      { print rhs(); next }
        inblock && /=>/              { print rhs() }
    ' "$MOD/go.mod" 2>/dev/null | while IFS= read -r _p; do
        case "$_p" in
            /*)        ( cd "$_p"      2>/dev/null && pwd ) ;;
            ./*|../*)  ( cd "$MOD/$_p" 2>/dev/null && pwd ) ;;
            *) continue ;;   # a versioned module-path replacement, not a local dir
        esac
    done
}
LOCAL_DEP_MODS=()
while IFS= read -r _m; do
    if [ -n "$_m" ]; then LOCAL_DEP_MODS+=("$_m"); fi
done < <(local_dep_mods)

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
# HEAD:./ is the tree hash of $MOD at HEAD — the identity of this module's
# committed inputs, deletions included. The repo HEAD would move on every merge
# to main and cost a rebuild, and for a service a restart, for each. Each local
# module the component replaces in adds its own subtree hash, so a sibling-only
# change moves SOURCE_REV without widening the identity to all of main.
MOD_REV="$(git -C "$MOD" rev-parse 'HEAD:./' 2>/dev/null || true)"
SOURCE_REV="$MOD_REV"
if [ -n "$SOURCE_REV" ]; then
    for _dep in ${LOCAL_DEP_MODS[@]+"${LOCAL_DEP_MODS[@]}"}; do
        _dep_rev="$(git -C "$_dep" rev-parse 'HEAD:./' 2>/dev/null || true)"
        [ -n "$_dep_rev" ] && SOURCE_REV="$SOURCE_REV $_dep_rev"
    done
fi

# behind_main — how far this checkout is behind origin/<default> under the
# component's source paths, REPORT-ONLY. Everything above keys on the LOCAL
# checkout: SOURCE_REV is HEAD's subtree, newer_than_binary scans HEAD's files.
# So a checkout parked off-main (another branch, or one not fast-forwarded)
# keeps its binary current with THAT branch — source_rev == binary_rev, a clean
# probe — while what it serves is behind main. Nothing above can see that, so the
# PACK row would read a false "ok". This counts the commits origin/<default>
# carries under the component's sources that HEAD lacks, and the board bands a
# nonzero count as drift.
#
# It NEVER feeds need_build. A checkout may be off-main on purpose, and a rebuild
# on every unrelated main merge is exactly what the SOURCE_REV subtree-hash
# identity exists to avoid — the requirement is to REPORT drift, not to rebuild
# on it. The comparison wants a fresh origin ref: reconcile-rig-checkouts fetches
# origin on its own cadence, so it is usually already current, and this fetch is
# bounded to at most one ATTEMPT per FETCH_TTL for each state root (0 disables
# it and leans on reconcile) so a 5-minute tick does not fetch every time, and a
# failing origin costs one attempt per TTL rather than one per tick. Every step
# degrades to "gap unknown" (0), never to a failed build.
BEHIND_MAIN=0
REPO_ROOT="$(git -C "$MOD" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$REPO_ROOT" ]; then
    SRC_PATHS=()
    for _p in "$MOD" ${LOCAL_DEP_MODS[@]+"${LOCAL_DEP_MODS[@]}"}; do
        # A pathspec has to be inside this repo, and "behind origin/main" is this
        # repo's question; a replace-dep resolved to another checkout is dropped.
        # Both answers come from git, which resolves symlinks for each module
        # the way it did for REPO_ROOT. MOD and the replace-deps are logical
        # `pwd` paths, so a string match against REPO_ROOT misses every module
        # of a checkout reached through a symlinked path.
        [ "$(git -C "$_p" rev-parse --show-toplevel 2>/dev/null || true)" = "$REPO_ROOT" ] || continue
        _prefix="$(git -C "$_p" rev-parse --show-prefix 2>/dev/null || true)"
        SRC_PATHS+=("${_prefix:-.}")
    done
    if [ "${#SRC_PATHS[@]}" -gt 0 ]; then
        DEFAULT_REF="$(git -C "$REPO_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
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
            git -C "$REPO_ROOT" fetch --quiet --no-tags origin "${DEFAULT_REF#origin/}" 2>/dev/null || true
        fi
        # Commits the default branch carries under the component's sources that
        # HEAD lacks: 0 when on main and current, when ahead, or when the ref is
        # absent.
        _behind="$(git -C "$REPO_ROOT" rev-list --count "HEAD..$DEFAULT_REF" -- "${SRC_PATHS[@]}" 2>/dev/null || true)"
        case "$_behind" in ''|*[!0-9]*) _behind=0 ;; esac
        BEHIND_MAIN="$_behind"
    fi
fi

# What the probe said about the binary this run reports on, in one variable:
# write_record reads it rather than taking it as an argument, so a path that
# condemns a binary cannot record it as current by omitting one. It stays empty
# for a component that does not probe, and that component's record carries no
# probe fields. "unprobed" is the answer for a run that resolved no city to ask
# about. The probe is handed its city explicitly, so it answers for the city this
# run resolved rather than for whatever its own environment names.
PROBE_KIND=""
PROBE_DETAIL=""
if [ "$PROBE" -eq 1 ]; then
    PROBE_KIND=unprobed
    [ -n "$PROBE_CITY" ] || PROBE_CITY="$CITY_ROOT"
fi

# A field of the previous record, or empty. A build that failed keeps the last
# good binary serving, so its built_at and binary_rev must survive the failure
# that did not replace them.
prev_field() { # <key>
    [ -f "$STATUS" ] || return 0
    jq -r --arg k "$1" '(.[$k] // "") | tostring' "$STATUS" 2>/dev/null || true
}

# build-status.json — what this component is SERVING versus what the sources
# say, written where the board reads it (services/helm reads every
# .gc/services/*/build-status.json into the PACK rows). Nothing else can answer
# it: every caller execs a prebuilt binary, so one older than its sources serves
# in silence.
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
        --arg probe_status "$PROBE_KIND" --arg probe_detail "$PROBE_DETAIL" \
        --argjson behind_main "$BEHIND_MAIN" \
        --arg checked_at "$(date -u +%FT%TZ)" \
        '{component: $component, built_at: $built_at, source_rev: $source_rev,
          binary_rev: $binary_rev, last_build_rc: $last_build_rc,
          restart_pending: $restart_pending, probe_status: $probe_status,
          probe_detail: $probe_detail, behind_main: $behind_main,
          checked_at: $checked_at}
         | if $probe_status == "" then del(.probe_status, .probe_detail) else . end' \
        > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$STATUS" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null
    else
        rm -f -- "$tmp" 2>/dev/null
    fi
    return 0
}

# build-status — a probing component's one-line readability status, beside the
# record.
write_status() { # <kind> [detail]
    local line
    [ "$PROBE" -eq 1 ] || return 0
    line="$1 $(date -u +%FT%TZ)"
    if [ -n "${2:-}" ]; then line="$line $2"; fi
    printf '%s\n' "$line" > "$STATE_ROOT/build-status" 2>/dev/null || true
}

# Go toolchain: override, PATH, then the conventional system install. It is
# needed only once there is something to build.
GO="${GC_GO_BIN:-}"
if [ -z "$GO" ]; then
    if command -v go >/dev/null 2>&1; then GO="go"; else GO="/usr/local/go/bin/go"; fi
fi

# A rebuild changes what a binary can read only if the embedded beads library
# moves, which is what separates "retry the build" from "the pin is the problem".
BEADS_MODULE="github.com/steveyegge/beads"
PROBE_LATCH="$STATE_ROOT/probe-failed"

# probe_binary <path> — 0 readable, 1 not, with the reason in PROBE_DETAIL.
# A binary too old to know the verb answers non-zero too, which is the right
# answer: it predates the check and is worth rebuilding.
probe_binary() {
    local out=""
    PROBE_DETAIL=""
    if out="$(GC_HELM_CITY_PATH="$PROBE_CITY" "$1" probe --timeout="$PROBE_TIMEOUT" 2>&1)"; then
        return 0
    fi
    # One line, bounded: build-status is a single-line file and the live
    # schema-skew message names every rig in the city.
    PROBE_DETAIL="$(printf '%s' "$out" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ *//; s/ *$//' | cut -c1-300)"
    [ -n "$PROBE_DETAIL" ] || PROBE_DETAIL="the probe produced no diagnostic"
    return 1
}

embedded_beads() { # <binary> — the pinned library version, or "unknown"
    local v=""
    v="$("$GO" version -m "$1" 2>/dev/null | awk -v m="$BEADS_MODULE" '$1 == "dep" && $2 == m { print $3; exit }' || true)"
    printf '%s' "${v:-unknown}"
}

# Build inputs: *.go, go.mod/go.sum (explicit — `-name '*.go'` misses them, and
# a dependency-only bump must still rebuild), and web/dist (helm's go:embed).
# Scanned across $MOD and every local module it replaces in, so a sibling-only
# edit is seen as newer. node_modules pruned.
newer_than_binary() {
    find "$MOD" ${LOCAL_DEP_MODS[@]+"${LOCAL_DEP_MODS[@]}"} -name node_modules -prune -o \( -name '*.go' -o -name go.mod -o -name go.sum -o -path "$MOD/web/dist/*" \) -newer "$BIN" -print -quit 2>/dev/null
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

    # Current in revision terms proves nothing about the store. Ask the binary
    # BEFORE any restart: nothing may be put into service on a binary this run
    # has already condemned.
    if [ "$PROBE" -eq 1 ] && [ -n "$PROBE_CITY" ]; then
        if probe_binary "$BIN"; then PROBE_KIND=ok; else PROBE_KIND=unreadable; fi
    fi

    if [ "$PROBE_KIND" != "unreadable" ]; then
        # Current is not serving: an unrestarted publish leaves its marker, and
        # this branch is the only one a later run can reach.
        if [ -n "$SERVICE" ] && [ "$DEPLOY" -eq 1 ] && [ -e "$RESTART_PENDING" ]; then
            echo "$ME: $BIN is up to date but not yet serving; retrying the restart"
            if ! restart_service; then
                write_record 0 "$CURRENT_REV" "$CURRENT_BUILT_AT"
                exit 1
            fi
        fi
        case "$PROBE_KIND" in
            ok)
                echo "$ME: $BIN is up to date and can read the city's bead stores"
                write_status ok
                rm -f -- "$PROBE_LATCH" 2>/dev/null || true
                ;;
            unprobed)
                echo "$ME: $BIN is up to date (no city resolved; readability unprobed)"
                write_status unprobed
                ;;
            *)
                echo "$ME: $BIN is up to date"
                ;;
        esac
        write_record 0 "$CURRENT_REV" "$CURRENT_BUILT_AT"
        exit 0
    fi

    # Rebuilding is the remedy only while it can produce a different binary;
    # once it has been tried against this exact library version, repeating it
    # every five minutes buries the remedy it cannot perform itself.
    EMBEDDED="$(embedded_beads "$BIN")"
    if [ "$(cat "$PROBE_LATCH" 2>/dev/null || true)" = "$EMBEDDED" ]; then
        echo "$ME: $BIN CANNOT READ the city's bead stores, and a rebuild would embed the same $BEADS_MODULE $EMBEDDED; bump it in $MOD/go.mod. Detail: $PROBE_DETAIL" >&2
        write_status unreadable "$PROBE_DETAIL"
        write_record 0 "$CURRENT_REV" "$CURRENT_BUILT_AT"
        exit 1
    fi
    echo "$ME: $BIN cannot read the city's bead stores; rebuilding. Detail: $PROBE_DETAIL"
    need_build=1
fi

# A build is owed and nothing can perform it: that is a failed build, recorded
# like any other so the board's PACK row reports it, and $BIN is not touched. A
# city that never gets a gctk binary refuses every lifecycle transition, since
# lifecycle.sh has nothing else to exec, and a city that has one keeps it.
if ! command -v "$GO" >/dev/null 2>&1; then
    echo "$ME: BUILD FAILED: no Go toolchain ($GO) to build $MOD; set GC_GO_BIN. $BIN left unchanged" >&2
    write_status failed
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

# The compile's cgo flags: the caller's own, and for a component that links ICU,
# Homebrew's keg-only icu4c after them on macOS (icu4c-cgo.sh). Worked out only
# when a build is owed, so a tick with nothing to build never asks brew.
BUILD_CGO_CPPFLAGS="${CGO_CPPFLAGS:-}"
BUILD_CGO_LDFLAGS="${CGO_LDFLAGS:-}"
if [ "$ICU" -eq 1 ]; then
    icu4c_cgo_flags "$ME"
    BUILD_CGO_CPPFLAGS="$ICU4C_CGO_CPPFLAGS"
    BUILD_CGO_LDFLAGS="$ICU4C_CGO_LDFLAGS"
fi

# A stamping component's binary carries the revision it was built from
# (`gctk version`), stamped as its module's own subtree hash, so gctk-resolve.sh
# and doctor/check-cadence-live compare one identity against the checkout
# rather than a commit hash against a tree hash. A build with no revision to
# stamp falls back to the toolchain's VCS stamp.
GO_BUILD_FLAGS=()
if [ "$STAMP" -eq 1 ] && [ -n "$MOD_REV" ]; then
    GO_BUILD_FLAGS+=(-ldflags "-X main.sourceRev=$MOD_REV")
fi

# Publish only via atomic rename from a scratch file beside $BIN: an in-place
# -o could truncate the live binary into a half-written file that still passes
# a caller's -x test.
build_ok=0
BIN_TMP=""
echo "$ME: building $MOD -> $BIN"
if BIN_TMP="$(mktemp "$BIN_DIR/.$BIN_NAME.build.XXXXXX" 2>/dev/null)"; then
    if ( cd "$MOD" && TMPDIR="$GOTMP_RUN" GOTMPDIR="$GOTMP_RUN" \
            CGO_CPPFLAGS="$BUILD_CGO_CPPFLAGS" CGO_LDFLAGS="$BUILD_CGO_LDFLAGS" \
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
    write_status failed
    write_record 1 "$(prev_field binary_rev)" "$(prev_field built_at)"
    exit 1
fi

BUILT_AT="$(date -u +%FT%TZ)"
echo "$ME: built $BIN"

# A compiling binary is not a working one: a probing component writes ok only
# behind a passing probe, so nothing downstream can read build-status as a
# healthy board while the gather it reports on cannot run.
if [ "$PROBE" -eq 1 ]; then
    PROBE_KIND=unprobed
    if [ -n "$PROBE_CITY" ]; then
        if probe_binary "$BIN"; then
            PROBE_KIND=ok
            rm -f -- "$PROBE_LATCH" 2>/dev/null || true
        else
            PROBE_KIND=unreadable
            # What was just tried, so the next tick can tell a retry from a loop.
            printf '%s\n' "$(embedded_beads "$BIN")" > "$PROBE_LATCH" 2>/dev/null || true
        fi
    fi
    write_status "$PROBE_KIND" "$PROBE_DETAIL"

    # Stop before the restart, not after it: a condemned binary must not be
    # marked for restart either, or the next run's pending-restart branch serves
    # it.
    if [ "$PROBE_KIND" = "unreadable" ]; then
        echo "$ME: the binary just built CANNOT READ the city's bead stores; the board will not render. The service is left on the binary it is already running. Detail: $PROBE_DETAIL" >&2
        write_record 0 "$SOURCE_REV" "$BUILT_AT"
        exit 1
    fi
fi

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
