#!/usr/bin/env bash
# Hermetic test for bd-build.sh.
#
# A fake `go` on PATH RECORDS the argv it was invoked with and emits a shell
# "binary" that answers `version` with whatever -X main.Version= the build
# passed, plus a scripted `go version -m` answer for the CGO check; a throwaway
# git repo with one tag stands in for the beads mirror. No network, no real
# compiler, no dependency on the live city or the host bd.
#
# Covers: (a) the pin is read from deps.env and the built binary reports it;
# (b) the build is upstream's recipe — CGO_ENABLED=1, -tags gms_pure_go,
# ./cmd/bd, the tag's commit in -X main.Commit; (c) --install swaps the binary
# atomically and keeps a versioned backup of the previous one; (d) --check is 0
# only when the installed bd reports the pin; (e) an unknown tag is refused
# before any build; (f) a build whose metadata says CGO_ENABLED=0 is refused
# and nothing is installed — the exact host defect this script replaces.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/bd-build.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bd-build-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }
has() { if printf '%s' "$1" | grep -q -- "$2"; then ok "$3"; else bad "$3 (missing '$2' in: $1)"; fi; }

# --- fake toolchain ----------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"
RECORD="$TMP/go-argv"
CGO_ANSWER="$TMP/cgo-answer"; printf 'CGO_ENABLED=1' > "$CGO_ANSWER"
cat > "$BIN/go" <<'FAKE'
#!/usr/bin/env bash
# `go build ... -ldflags "... -X main.Version=V ..." -o OUT ./cmd/bd`
# `go version -m BIN`
set -euo pipefail
printf '%s\n' "CGO_ENABLED=${CGO_ENABLED-unset} $*" >> "$GO_RECORD"
if [ "$1" = build ]; then
  out=""; ver=""; commit=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -o) shift; out="$1" ;;
      -ldflags) shift
        ver="$(printf '%s' "$1" | sed -n 's/.*main\.Version=\([^ ]*\).*/\1/p')"
        commit="$(printf '%s' "$1" | sed -n 's/.*main\.Commit=\([^ ]*\).*/\1/p')" ;;
    esac
    shift
  done
  printf '#!/usr/bin/env bash\ncase "${1:-}" in version) echo "bd version %s (%s)";; *) echo fake-bd;; esac\n' "$ver" "$commit" > "$out"
  chmod +x "$out"
  exit 0
fi
if [ "$1" = version ] && [ "${2:-}" = -m ]; then
  printf '%s: go1.26.6\n\tpath\tgithub.com/steveyegge/beads/cmd/bd\n\tbuild\t%s\n' "$3" "$(cat "$GO_CGO_ANSWER")"
  exit 0
fi
echo "fake go: unexpected $*" >&2; exit 9
FAKE
chmod +x "$BIN/go"
export GO_RECORD="$RECORD" GO_CGO_ANSWER="$CGO_ANSWER"

# --- fake beads mirror + deps.env ----------------------------------------------
REPO="$TMP/beads"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@x -c user.name=t commit -q --allow-empty -m base
git -C "$REPO" tag v9.9.9
TAGCOMMIT="$(git -C "$REPO" rev-parse v9.9.9)"
DEPS="$TMP/deps.env"
printf '# pins\nBD_VERSION=v9.9.9\nBR_VERSION=0.1.0\n' > "$DEPS"
INSTALL="$TMP/install"; mkdir -p "$INSTALL"
OUT="$TMP/out/bd-built"

run() { # args... — runs the script with the fake toolchain first on PATH
  RC=0
  OUTPUT="$(PATH="$BIN:$PATH" GOTMPDIR="$TMP/gotmp" BD_BUILD_DEPS_ENV="$DEPS" BD_BUILD_BEADS_REPO="$REPO" \
    BD_BUILD_UPSTREAM="$REPO" BD_BUILD_INSTALL_DIR="$INSTALL" BD_BUILD_OUT="$OUT" \
    bash "$SCRIPT" "$@" 2>&1)" || RC=$?
}

# (a) + (b): build from the deps.env pin with upstream's recipe
: > "$RECORD"
run
eq "$RC" 0 "(a) build exits 0"
eq "$("$OUT" version)" "bd version 9.9.9 ($TAGCOMMIT)" "(a) built binary reports the deps.env pin"
BUILD_LINE="$(grep ' build ' "$RECORD" | head -1)"
has "$BUILD_LINE" "^CGO_ENABLED=1 " "(b) CGO_ENABLED=1 for the build"
has "$BUILD_LINE" "-tags gms_pure_go" "(b) -tags gms_pure_go"
has "$BUILD_LINE" "./cmd/bd" "(b) builds ./cmd/bd"
has "$BUILD_LINE" "main.Commit=$TAGCOMMIT" "(b) stamps the tag's commit"
eq "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" "1" "(b) the build worktree is removed afterwards"

# (d) --check before any install: not the pin
run --check
eq "$RC" 1 "(d) --check is 1 with no installed bd"

# (c) --install swaps atomically and keeps a backup of the previous binary
printf '#!/usr/bin/env bash\necho "bd version 1.2.2 (old)"\n' > "$INSTALL/bd"; chmod +x "$INSTALL/bd"
run --install
eq "$RC" 0 "(c) --install exits 0"
eq "$("$INSTALL/bd" version)" "bd version 9.9.9 ($TAGCOMMIT)" "(c) installed bd is the new build"
eq "$("$INSTALL/bd.1.2.2.bak" version)" "bd version 1.2.2 (old)" "(c) previous bd kept as a versioned backup"
eq "$(ls "$INSTALL" | grep -c '^\.bd\.tmp')" "0" "(c) no temp file left behind"

# (d) --check after install: the pin
run --check
eq "$RC" 0 "(d) --check is 0 once the installed bd reports the pin"

# (e) an unknown tag is refused before building
: > "$RECORD"
run --version v0.0.1
eq "$RC" 1 "(e) unknown tag is refused"
has "$OUTPUT" "tag v0.0.1 not found" "(e) names the missing tag"
eq "$(grep -c ' build ' "$RECORD")" "0" "(e) and nothing was built"

# (f) a non-CGO build is refused and nothing is installed
printf 'CGO_ENABLED=0' > "$CGO_ANSWER"
run --install --version v9.9.9
eq "$RC" 1 "(f) a CGO_ENABLED=0 build is refused"
has "$OUTPUT" "not a CGO build" "(f) says why"
eq "$("$INSTALL/bd" version)" "bd version 9.9.9 ($TAGCOMMIT)" "(f) the installed bd is untouched"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
