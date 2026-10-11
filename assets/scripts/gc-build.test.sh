#!/usr/bin/env bash
# gc-build.test.sh — gc-build.sh's argument contract, and its gctk component.
# gc-helm-svc.test.sh pins the body the components share, on helm: the scratch
# bounding, the atomic publish, the record's revisions, deletion-only rebuilds,
# behind_main's fetch cadence, the probe and the restart. This suite pins what
# is gctk's own, starting with the questions that decide whether lifecycle.sh
# has a binary to exec. lifecycle.sh execs gctk and has no other
# implementation, so a build the city cannot perform has to show up as a failed
# build rather than as a quiet tick.
#   (USAGE)    no component, an unknown one, two of them, or an unknown argument
#              exits 2 and writes nothing
#   (TOOLLESS) a build owed with no Go toolchain is a FAILED build: exit 1 and a
#              last_build_rc=1 record, under --deploy too, so the board's PACK
#              row reports it
#   (KEEP)     that failure leaves an existing binary, and the revision its
#              record names, exactly as they were
#   (CURRENT)  a current binary needs no toolchain: exit 0, recorded as success
#   (BUILD)    with a toolchain, the owed build publishes and records its revision
#   (STAMP)    the binary is stamped with services/gctk's own revision, the
#              identity `gctk version` reports
#   (COMMAND)  gctk is a command, not a service: --deploy restarts nothing, the
#              record carries restart_pending false and no probe fields, no
#              readability status or restart marker is written, and with the
#              city in the environment gc is never asked
#   (BEHIND)   a checkout behind origin/main under services/gctk records the
#              gap, and is never rebuilt for it
#   (LISTCITY) with no city in the environment, the listing's city_path places
#              the state root
#   (NOCITY)   with neither, it refuses and publishes nothing
#   (SCOPED)   an inherited GC_SERVICE_STATE_ROOT, or helm's override, does not
#              move gctk's state root
#   (DEPS)     a local replace-dep joins source_rev, while the stamp stays the
#              module's own revision
# Hermetic: a fixture tree holds a copy of the script beside a stand-in
# services/gctk; the toolchain is a stub or absent, named by GC_GO_BIN; gc is a
# stub named by GC_GCTK_GC_BIN; the state roots and the Go scratch dir are temp
# dirs. No city, no real build, no network.
set -uo pipefail

# The state-root fallback ends at <city>/.gc/services/gctk, and the city this
# suite runs inside is in the ambient environment. A case that omits the
# override must not inherit it, or it publishes a stub over the city's gctk.
unset GC_CITY GC_CITY_PATH GC_CITY_ROOT GC_CITY_RUNTIME_DIR GC_SERVICE_STATE_ROOT \
      GC_HELM_STATE_ROOT GC_GCTK_STATE_ROOT GC_GCTK_GC_BIN GC_GCTK_GOTMP \
      GC_GCTK_ORIGIN_FETCH_TTL GC_GO_BIN
for _leak in GC_CITY GC_CITY_PATH GC_CITY_ROOT GC_SERVICE_STATE_ROOT GC_GCTK_STATE_ROOT; do
  if [ -n "${!_leak:-}" ]; then
    echo "REFUSING TO RUN: $_leak is still set; this suite writes state roots and must not run against a real city." >&2
    exit 1
  fi
done
unset _leak

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-build-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Resolved, so every fixture is reached by its real path whatever TMPDIR's
# spelling: git reports a checkout's toplevel with symlinks resolved.
TMP="$(cd "$TMP" && pwd -P)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (unexpectedly got '$2' in: $1)" ;; *) ok "$3" ;; esac; }

commit_all() { # <repo> [message]
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c user.email=fixture@example.invalid -c user.name=fixture \
      -c commit.gpgsign=false commit -q -m "${2:-fixture}" >/dev/null 2>&1
}

# The script finds its module at ../../services/gctk and names it by the tree
# hash of that subtree, so the fixture is a committed tree of the same shape.
# The sources are dated in the past, so a binary written by a case is newer.
ROOT="$TMP/root"
mkdir -p "$ROOT/assets/scripts" "$ROOT/services/gctk/cmd/gctk"
cp "$HERE/gc-build.sh" "$ROOT/assets/scripts/gc-build.sh"
printf 'module example.invalid/gctk\n\ngo 1.22\n' > "$ROOT/services/gctk/go.mod"
printf 'package main\n\nfunc main() {}\n' > "$ROOT/services/gctk/cmd/gctk/main.go"
git -C "$ROOT" init -q >/dev/null 2>&1
commit_all "$ROOT"
touch -d '2026-01-01 00:00:00' "$ROOT/services/gctk/go.mod" "$ROOT/services/gctk/cmd/gctk/main.go"
REV=$(git -C "$ROOT/services/gctk" rev-parse 'HEAD:./' 2>/dev/null)
[ -n "$REV" ] && ok "the fixture module has a revision" \
             || bad "the fixture module has no revision; every case below would be vacuous"

# A stub gc: logs every call, and answers `service list --json` from the file
# STUB_GC_SERVICES names, failing when there is none.
mkdir -p "$TMP/bin"
GCBIN="$TMP/bin/gc"
GCLOG="$TMP/gc-calls"
cat > "$GCBIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_GC_LOG"
if [ "${1:-} ${2:-}" = "service list" ]; then
  if [ -n "${STUB_GC_SERVICES:-}" ] && [ -f "$STUB_GC_SERVICES" ]; then
    cat "$STUB_GC_SERVICES"
    exit 0
  fi
  exit 1
fi
exit 0
EOF
chmod +x "$GCBIN"

STATE="$TMP/state"
BUILD="$ROOT/assets/scripts/gc-build.sh"
GOBIN="$TMP/no-go"   # absent until (BUILD) installs a stub toolchain
GOLOG="$TMP/go-calls"
run_raw() { # [args...] — the script's argv verbatim; sets OUT (stdout+stderr) and RC
  OUT=$(GC_GCTK_STATE_ROOT="$STATE" GC_CITY_PATH="$TMP/city" GC_GCTK_GOTMP="$TMP/gotmp" \
        GC_GCTK_GC_BIN="$GCBIN" GC_GCTK_ORIGIN_FETCH_TTL=0 STUB_GC_LOG="$GCLOG" \
        STUB_GO_LOG="$GOLOG" GC_GO_BIN="$GOBIN" bash "$BUILD" "$@" 2>&1); RC=$?
}
run() { run_raw gctk "$@"; }
field() { # <key> [record] — a field of the record, "null" when absent
  jq -r --arg k "$1" '.[$k] | tostring' "${2:-$STATE/build-status.json}" 2>/dev/null
}
record() { # <binary_rev> <built_at> — a prior record from a successful build
  mkdir -p "$STATE"
  jq -n --arg rev "$1" --arg at "$2" \
    '{component: "gctk", built_at: $at, source_rev: $rev, binary_rev: $rev,
      last_build_rc: 0, restart_pending: false}' > "$STATE/build-status.json"
}
builds() { grep -c '^build$' "$GOLOG" 2>/dev/null || true; }

# --- (USAGE) -------------------------------------------------------------------
run_raw
eq "$RC" "2" "(USAGE) no component exits 2"
has "$OUT" "name the component" "(USAGE) …and says what is missing"
run_raw gctkx
eq "$RC" "2" "(USAGE) an unknown component exits 2"
run_raw gctk helm
eq "$RC" "2" "(USAGE) two components in one run exit 2"
run --bogus
eq "$RC" "2" "(USAGE) an unknown argument exits 2"
[ ! -e "$STATE" ] && ok "(USAGE) …and a usage error writes nothing" \
                  || bad "(USAGE) a usage error created the state root"

# --- (TOOLLESS) a fresh city with no toolchain --------------------------------
run --deploy
eq "$RC" "1" "(TOOLLESS) a build owed with no Go toolchain fails the order, under --deploy too"
has "$OUT" "no Go toolchain" "(TOOLLESS) …and says what is missing"
eq "$(field last_build_rc)" "1" "(TOOLLESS) …recording last_build_rc=1 for the board's PACK row"
eq "$(field binary_rev)" "" "(TOOLLESS) …with no binary_rev, because nothing has ever built"
[ ! -e "$STATE/bin/gctk" ] && ok "(TOOLLESS) …and it publishes nothing" \
                          || bad "(TOOLLESS) a binary appeared with no toolchain to build it"
run
eq "$RC" "1" "(TOOLLESS) a hand run with a build owed fails the same way"

# --- (KEEP) a stale binary with no toolchain to rebuild it ---------------------
mkdir -p "$STATE/bin"
printf '#!/bin/sh\necho last-good\n' > "$STATE/bin/gctk"
chmod +x "$STATE/bin/gctk"
record "oldrev" "2026-09-01T00:00:00Z"
SUM_BEFORE=$(cksum < "$STATE/bin/gctk")
run --deploy
eq "$RC" "1" "(KEEP) a binary the tree has moved past, with no toolchain, is a failed build"
eq "$(cksum < "$STATE/bin/gctk")" "$SUM_BEFORE" "(KEEP) …that leaves the serving binary exactly as it was"
eq "$(field binary_rev)" "oldrev" "(KEEP) …and the record still names the revision it serves"
eq "$(field built_at)" "2026-09-01T00:00:00Z" "(KEEP) …and when that binary was built"
eq "$(field last_build_rc)" "1" "(KEEP) …with the failure recorded"
eq "$(field source_rev)" "$REV" "(KEEP) …against the revision the tree is at"

# --- (CURRENT) nothing to build ------------------------------------------------
record "$REV" "2026-09-02T00:00:00Z"
run --deploy
eq "$RC" "0" "(CURRENT) a current binary needs no toolchain: the tick is OK"
has "$OUT" "up to date" "(CURRENT) …and says so"
eq "$(field last_build_rc)" "0" "(CURRENT) …recording success"
eq "$(field binary_rev)" "$REV" "(CURRENT) …for the revision the binary was built from"

# --- (BUILD) a toolchain performs the owed build -------------------------------
# The stub logs its argv one argument per line and writes a file to the -o path,
# the one thing the script reads from a build. It leaves the mode alone, so the
# published binary is executable only because the script makes it so.
GOBIN="$TMP/fake-go"
cat > "$GOBIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$STUB_GO_LOG"
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] || exit 1
printf '#!/bin/sh\necho built\n' > "$out"
EOF
chmod +x "$GOBIN"
record "oldrev" "2026-09-01T00:00:00Z"
: > "$GCLOG"
run --deploy
eq "$RC" "0" "(BUILD) with a toolchain, the owed build succeeds"
eq "$("$STATE/bin/gctk")" "built" "(BUILD) …publishing the binary it built"
eq "$(field binary_rev)" "$REV" "(BUILD) …and recording the revision it was built from"
eq "$(field last_build_rc)" "0" "(BUILD) …as a success"

# --- (STAMP) the binary carries its module's revision --------------------------
grep -qxF -- "-X main.sourceRev=$REV" "$GOLOG" \
  && ok "(STAMP) the build stamps services/gctk's revision for \`gctk version\`" \
  || bad "(STAMP) no '-X main.sourceRev=$REV' in the build's arguments: $(tr '\n' ' ' < "$GOLOG")"

# --- (COMMAND) no service, so no restart and no probe --------------------------
eq "$(field restart_pending)" "false" "(COMMAND) the record says nothing is pending"
eq "$(jq -r 'has("probe_status") or has("probe_detail")' "$STATE/build-status.json")" "false" \
   "(COMMAND) …and carries no probe fields, since nothing probes gctk"
[ ! -e "$STATE/build-status" ] && ok "(COMMAND) no readability status is written" \
                               || bad "(COMMAND) a build-status readability file appeared"
[ ! -e "$STATE/restart-pending" ] && ok "(COMMAND) no restart marker is written" \
                                  || bad "(COMMAND) a restart-pending marker appeared for a command"
[ ! -s "$GCLOG" ] && ok "(COMMAND) with its city in the environment, gc is never asked" \
                  || bad "(COMMAND) gc was called: $(tr '\n' ';' < "$GCLOG")"

# --- (BEHIND) a checkout behind origin/main is reported, never rebuilt for -----
# origin/main gets one more services/gctk commit than HEAD. The fetch is off
# (GC_GCTK_ORIGIN_FETCH_TTL=0), so the gap is read off that ref as it stands.
A_COMMIT=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)
printf '// upstream gctk change\n' >> "$ROOT/services/gctk/cmd/gctk/main.go"
commit_all "$ROOT" "upstream gctk change"
git -C "$ROOT" update-ref refs/remotes/origin/main HEAD >/dev/null 2>&1
git -C "$ROOT" reset -q --hard "$A_COMMIT" >/dev/null 2>&1
run --deploy
eq "$RC" "0" "(BEHIND) the tick exits 0"
eq "$(field behind_main)" "1" "(BEHIND) …recording the one commit origin/main carries under services/gctk"
BUILDS_BEFORE=$(builds)
run --deploy
eq "$RC" "0" "(BEHIND) the next tick exits 0"
has "$OUT" "up to date" "(BEHIND) …with the binary current with its own sources"
eq "$(builds)" "$BUILDS_BEFORE" "(BEHIND) …so being behind main alone never rebuilds"
eq "$(field behind_main)" "1" "(BEHIND) …and the gap is still recorded on the no-op tick"
git -C "$ROOT" update-ref -d refs/remotes/origin/main >/dev/null 2>&1

# --- (LISTCITY) the listing names the city when the environment does not -------
LISTED="$TMP/listed-city"
printf '{"city_path":"%s","services":[]}' "$LISTED" > "$TMP/services.json"
OUT=$(GC_GCTK_GOTMP="$TMP/gotmp" GC_GCTK_GC_BIN="$GCBIN" GC_GCTK_ORIGIN_FETCH_TTL=0 \
      STUB_GC_LOG="$GCLOG" STUB_GC_SERVICES="$TMP/services.json" STUB_GO_LOG="$GOLOG" \
      GC_GO_BIN="$GOBIN" bash "$BUILD" gctk --deploy 2>&1); RC=$?
eq "$RC" "0" "(LISTCITY) builds with no city in the environment"
[ -x "$LISTED/.gc/services/gctk/bin/gctk" ] \
  && ok "(LISTCITY) …publishing under the city_path the listing reports" \
  || bad "(LISTCITY) no binary at $LISTED/.gc/services/gctk/bin/gctk: $OUT"

# --- (NOCITY) no city from anywhere --------------------------------------------
OUT=$(GC_GCTK_GOTMP="$TMP/gotmp" GC_GCTK_GC_BIN="$GCBIN" GC_GCTK_ORIGIN_FETCH_TTL=0 \
      STUB_GC_LOG="$GCLOG" STUB_GO_LOG="$GOLOG" \
      GC_GO_BIN="$GOBIN" bash "$BUILD" gctk --deploy 2>&1); RC=$?
eq "$RC" "1" "(NOCITY) with no city in the environment and no listing, it refuses"
has "$OUT" "cannot locate the city runtime dir" "(NOCITY) …saying so"
has "$OUT" "GC_GCTK_STATE_ROOT" "(NOCITY) …and naming the override to set"
hasnt "$OUT" "built" "(NOCITY) …and publishes nothing"

# --- (SCOPED) other components' state roots are not gctk's ---------------------
SCOPED_CITY="$TMP/scoped-city"
OUT=$(GC_SERVICE_STATE_ROOT="$TMP/svc-root" GC_HELM_STATE_ROOT="$TMP/helm-root" \
      GC_CITY_PATH="$SCOPED_CITY" GC_GCTK_GOTMP="$TMP/gotmp" GC_GCTK_GC_BIN="$GCBIN" \
      GC_GCTK_ORIGIN_FETCH_TTL=0 STUB_GC_LOG="$GCLOG" STUB_GO_LOG="$GOLOG" \
      GC_GO_BIN="$GOBIN" bash "$BUILD" gctk --deploy 2>&1); RC=$?
eq "$RC" "0" "(SCOPED) builds with another service's state root in the environment"
[ -x "$SCOPED_CITY/.gc/services/gctk/bin/gctk" ] \
  && ok "(SCOPED) …publishing into gctk's own state root" \
  || bad "(SCOPED) no binary at $SCOPED_CITY/.gc/services/gctk/bin/gctk: $OUT"
[ ! -e "$TMP/svc-root" ] && ok "(SCOPED) nothing is written under GC_SERVICE_STATE_ROOT" \
                         || bad "(SCOPED) the build wrote under GC_SERVICE_STATE_ROOT"
[ ! -e "$TMP/helm-root" ] && ok "(SCOPED) nor under helm's override" \
                          || bad "(SCOPED) the build wrote under GC_HELM_STATE_ROOT"

# --- (DEPS) a local replace-dep joins the identity, not the stamp --------------
# gctk replaces in no local module today; the build reads go.mod's replace
# directives, so one added later is covered without naming it here.
ROOT2="$TMP/root2"
mkdir -p "$ROOT2/assets/scripts" "$ROOT2/services/gctk/cmd/gctk" "$ROOT2/services/dep"
cp "$HERE/gc-build.sh" "$ROOT2/assets/scripts/gc-build.sh"
printf 'module example.invalid/gctk\n\ngo 1.22\n\nrequire example.invalid/dep v0.0.0\n\nreplace example.invalid/dep => ../dep\n' \
  > "$ROOT2/services/gctk/go.mod"
printf 'package main\n\nfunc main() {}\n' > "$ROOT2/services/gctk/cmd/gctk/main.go"
printf 'module example.invalid/dep\n\ngo 1.22\n' > "$ROOT2/services/dep/go.mod"
printf 'package dep\n' > "$ROOT2/services/dep/dep.go"
git -C "$ROOT2" init -q >/dev/null 2>&1
commit_all "$ROOT2"
REV2=$(git -C "$ROOT2/services/gctk" rev-parse 'HEAD:./' 2>/dev/null)
DEPREV=$(git -C "$ROOT2/services/dep" rev-parse 'HEAD:./' 2>/dev/null)
STATE2="$TMP/state2"
: > "$GOLOG"
OUT=$(GC_GCTK_STATE_ROOT="$STATE2" GC_CITY_PATH="$TMP/city" GC_GCTK_GOTMP="$TMP/gotmp" \
      GC_GCTK_GC_BIN="$GCBIN" GC_GCTK_ORIGIN_FETCH_TTL=0 STUB_GC_LOG="$GCLOG" \
      STUB_GO_LOG="$GOLOG" GC_GO_BIN="$GOBIN" bash "$ROOT2/assets/scripts/gc-build.sh" gctk 2>&1); RC=$?
eq "$RC" "0" "(DEPS) a module with a local replace-dep builds"
eq "$(field source_rev "$STATE2/build-status.json")" "$REV2 $DEPREV" \
   "(DEPS) …and its source_rev spans the replaced module's subtree"
grep -qxF -- "-X main.sourceRev=$REV2" "$GOLOG" \
  && ok "(DEPS) …while the stamp stays services/gctk's own revision, the one its readers compare" \
  || bad "(DEPS) the stamp is not '-X main.sourceRev=$REV2': $(tr '\n' ' ' < "$GOLOG")"

echo
echo "gc-build: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
