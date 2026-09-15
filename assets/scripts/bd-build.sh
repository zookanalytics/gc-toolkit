#!/usr/bin/env bash
# bd-build.sh — build the `bd` (beads CLI) release that gascity pins, the way
# upstream releases it, and optionally install it on this host.
#
# Why this exists: the host bd used to be a hand-built CGO_ENABLED=0 binary at
# an untagged commit. Upstream's linux-amd64 release (beads .goreleaser.yml,
# id bd-linux-amd64) is CGO_ENABLED=1 with -tags gms_pure_go and is verified
# by beads' own scripts/verify-cgo.sh; without CGO the embedded-Dolt paths
# gascity's tests exercise hard-fail. Building from the tag reproduces the
# release artifact instead of tracking a moving commit.
#
# Usage:
#   bd-build.sh                 build to BD_BUILD_OUT and print the path
#   bd-build.sh --install       build, then swap it into BD_BUILD_INSTALL_DIR/bd
#   bd-build.sh --check         exit 0 iff the installed bd already reports the pin
#   bd-build.sh --version vX    override the pin (default: BD_VERSION in deps.env)
#
# Environment:
#   BD_BUILD_DEPS_ENV      gascity deps.env carrying BD_VERSION
#                          (default: $GC_CITY_PATH/rigs/gascity/deps.env)
#   BD_BUILD_BEADS_REPO    local beads git checkout; cloned if absent
#                          (default: $HOME/beads)
#   BD_BUILD_UPSTREAM      clone/fetch source for tags
#                          (default: https://github.com/gastownhall/beads.git)
#   BD_BUILD_OUT           where the built binary lands when not installing
#                          (default: $BD_BUILD_BEADS_REPO/../bd-<version>)
#   BD_BUILD_INSTALL_DIR   (default: $HOME/.local/bin)
#   GOTMPDIR               compile scratch; kept OFF tmpfs (default /var/tmp/gotmp)
# Never sets GOCACHE and never runs `go clean -cache` (shared build cache).
set -euo pipefail

MODE=build
PIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) MODE=install ;;
    --check) MODE=check ;;
    --version) shift; PIN="${1:-}" ;;
    --version=*) PIN="${1#--version=}" ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "bd-build: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

CITY="${GC_CITY_PATH:-$HOME/loomington}"
DEPS_ENV="${BD_BUILD_DEPS_ENV:-$CITY/rigs/gascity/deps.env}"
REPO="${BD_BUILD_BEADS_REPO:-$HOME/beads}"
UPSTREAM="${BD_BUILD_UPSTREAM:-https://github.com/gastownhall/beads.git}"
INSTALL_DIR="${BD_BUILD_INSTALL_DIR:-$HOME/.local/bin}"
export GOTMPDIR="${GOTMPDIR:-/var/tmp/gotmp}"
mkdir -p "$GOTMPDIR"

# resolve_pin — the tag to build: --version wins, else BD_VERSION from deps.env.
resolve_pin() {
  if [ -n "$PIN" ]; then printf '%s' "$PIN"; return 0; fi
  [ -r "$DEPS_ENV" ] || { echo "bd-build: deps.env not readable: $DEPS_ENV" >&2; return 1; }
  local v
  v="$(sed -n 's/^BD_VERSION=\([^[:space:]#]*\).*/\1/p' "$DEPS_ENV" | head -1)"
  [ -n "$v" ] || { echo "bd-build: no BD_VERSION in $DEPS_ENV" >&2; return 1; }
  printf '%s' "$v"
}

# installed_version — the first version token `bd version` prints, or "".
installed_version() {
  local bin="$INSTALL_DIR/bd"
  [ -x "$bin" ] || return 0
  "$bin" version 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^v?[0-9]+\.[0-9]+\.[0-9]+/) { print $i; exit } }'
}

pin="$(resolve_pin)"
want="${pin#v}"

if [ "$MODE" = check ]; then
  have="$(installed_version)"
  if [ "${have#v}" = "$want" ]; then
    echo "bd-build: installed bd is the pin ($pin)"
    exit 0
  fi
  echo "bd-build: installed bd is '${have:-absent}', pin is $pin" >&2
  exit 1
fi

# The checkout is a mirror of upstream used only for tags; it is never built
# in place, so a dirty or unrelated branch there does not matter.
if [ ! -d "$REPO/.git" ]; then
  echo "bd-build: cloning $UPSTREAM into $REPO"
  git clone -q "$UPSTREAM" "$REPO"
fi
if ! git -C "$REPO" rev-parse -q --verify "refs/tags/$pin^{commit}" >/dev/null 2>&1; then
  git -C "$REPO" fetch -q --tags "$UPSTREAM" || true
fi
commit="$(git -C "$REPO" rev-parse -q --verify "refs/tags/$pin^{commit}" 2>/dev/null || true)"
[ -n "$commit" ] || { echo "bd-build: tag $pin not found in $REPO (fetched from $UPSTREAM)" >&2; exit 1; }
short="$(git -C "$REPO" rev-parse --short "$commit")"

WORK="$(mktemp -d -p /var/tmp bd-build.XXXXXX)"
cleanup() {
  git -C "$REPO" worktree remove --force "$WORK/src" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM HUP
git -C "$REPO" worktree add -q --detach "$WORK/src" "$commit"

# Exactly the goreleaser bd-linux-amd64 recipe, minus the archive step.
echo "bd-build: building bd $pin ($short) with CGO_ENABLED=1 -tags gms_pure_go"
( cd "$WORK/src" && CGO_ENABLED=1 CC="${CC:-gcc}" CXX="${CXX:-g++}" \
    go build -trimpath -tags gms_pure_go \
      -ldflags "-s -w -X main.Version=$want -X main.Build=$short -X main.Commit=$commit -X main.Branch=main" \
      -o "$WORK/bd" ./cmd/bd )

# Verify before anything is installed: the binary names the pin, and the build
# metadata says CGO was on (the same fact beads' verify-cgo.sh checks).
reported="$("$WORK/bd" version 2>/dev/null || true)"
case "$reported" in
  *"$want"*) ;;
  *) echo "bd-build: built binary reports '$reported', want $want" >&2; exit 1 ;;
esac
if ! go version -m "$WORK/bd" | grep -q -E '^[[:space:]]*build[[:space:]]+CGO_ENABLED=1$'; then
  echo "bd-build: built binary is not a CGO build; refusing (embedded Dolt would be unavailable)" >&2
  exit 1
fi

if [ "$MODE" = build ]; then
  out="${BD_BUILD_OUT:-$(dirname "$REPO")/bd-$want}"
  mkdir -p "$(dirname "$out")"
  install -m 0755 "$WORK/bd" "$out"
  echo "bd-build: built $out ($reported)"
  exit 0
fi

# --install: keep a versioned backup of what is there, then swap atomically so
# no caller ever sees a half-written binary.
mkdir -p "$INSTALL_DIR"
if [ -x "$INSTALL_DIR/bd" ]; then
  have="$(installed_version)"
  cp -f "$INSTALL_DIR/bd" "$INSTALL_DIR/bd.${have:-unknown}.bak"
fi
tmp="$INSTALL_DIR/.bd.tmp.$$"
install -m 0755 "$WORK/bd" "$tmp"
mv -f "$tmp" "$INSTALL_DIR/bd"
echo "bd-build: installed $INSTALL_DIR/bd ($reported)"
