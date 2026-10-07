#!/usr/bin/env bash
# gc-gctk-build.test.sh — the gctk build order's script, on the questions that
# decide whether lifecycle.sh has a binary to exec. lifecycle.sh execs gctk and
# has no other implementation, so a build the city cannot perform has to show
# up as a failed build rather than as a quiet tick.
#   (TOOLLESS) a build owed with no Go toolchain is a FAILED build: exit 1 and a
#              last_build_rc=1 record, under --deploy too, so the board's PACK
#              row reports it
#   (KEEP)     that failure leaves an existing binary, and the revision its
#              record names, exactly as they were
#   (CURRENT)  a current binary needs no toolchain: exit 0, recorded as success
#   (BUILD)    with a toolchain, the owed build publishes and records its revision
#   (USAGE)    an unknown argument exits 2
# Hermetic: a fixture tree holds a copy of the script beside a stand-in
# services/gctk; the toolchain is a stub or absent, named by GC_GO_BIN; the
# state root and the Go scratch dir are temp dirs. No city, no real build.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-build-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

# The script finds its module at ../../services/gctk and names it by the tree
# hash of that subtree, so the fixture is a committed tree of the same shape.
# The sources are dated in the past, so a binary written by a case is newer.
ROOT="$TMP/root"
mkdir -p "$ROOT/assets/scripts" "$ROOT/services/gctk/cmd/gctk"
cp "$HERE/gc-gctk-build.sh" "$ROOT/assets/scripts/gc-gctk-build.sh"
printf 'module example.invalid/gctk\n\ngo 1.22\n' > "$ROOT/services/gctk/go.mod"
printf 'package main\n\nfunc main() {}\n' > "$ROOT/services/gctk/cmd/gctk/main.go"
git -C "$ROOT" init -q >/dev/null 2>&1
git -C "$ROOT" add -A >/dev/null 2>&1
git -C "$ROOT" -c user.email=fixture@example.invalid -c user.name=fixture \
    -c commit.gpgsign=false commit -q -m fixture >/dev/null 2>&1
touch -d '2026-01-01 00:00:00' "$ROOT/services/gctk/go.mod" "$ROOT/services/gctk/cmd/gctk/main.go"
REV=$(git -C "$ROOT/services/gctk" rev-parse 'HEAD:./' 2>/dev/null)
[ -n "$REV" ] && ok "the fixture module has a revision" \
             || bad "the fixture module has no revision; every case below would be vacuous"

STATE="$TMP/state"
BUILD="$ROOT/assets/scripts/gc-gctk-build.sh"
GOBIN="$TMP/no-go"   # absent until (BUILD) installs a stub toolchain
run() { # [args...] — sets OUT (stdout+stderr) and RC
  OUT=$(GC_SERVICE_STATE_ROOT="$STATE" GC_CITY_PATH="$TMP/city" GC_GCTK_GOTMP="$TMP/gotmp" \
        GC_GO_BIN="$GOBIN" bash "$BUILD" "$@" 2>&1); RC=$?
}
field() { jq -r --arg k "$1" '.[$k] | tostring' "$STATE/build-status.json" 2>/dev/null; }
record() { # <binary_rev> <built_at> — a prior record from a successful build
  mkdir -p "$STATE"
  jq -n --arg rev "$1" --arg at "$2" \
    '{component: "gctk", built_at: $at, source_rev: $rev, binary_rev: $rev,
      last_build_rc: 0, restart_pending: false}' > "$STATE/build-status.json"
}

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
# The stub writes an executable to the -o path, the one thing the script reads
# from a build.
GOBIN="$TMP/fake-go"
cat > "$GOBIN" <<'EOF'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] || exit 1
printf '#!/bin/sh\necho built\n' > "$out"
EOF
chmod +x "$GOBIN"
record "oldrev" "2026-09-01T00:00:00Z"
run --deploy
eq "$RC" "0" "(BUILD) with a toolchain, the owed build succeeds"
eq "$("$STATE/bin/gctk")" "built" "(BUILD) …publishing the binary it built"
eq "$(field binary_rev)" "$REV" "(BUILD) …and recording the revision it was built from"
eq "$(field last_build_rc)" "0" "(BUILD) …as a success"

# --- (USAGE) -------------------------------------------------------------------
run --bogus
eq "$RC" "2" "(USAGE) an unknown argument exits 2"

echo
echo "gc-gctk-build: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
