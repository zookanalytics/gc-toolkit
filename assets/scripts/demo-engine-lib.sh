#!/usr/bin/env bash
# demo-engine-lib.sh — the one definition of how a demo capture finds the
# SprintShow engine, provisions the browser it launches, and runs its CLI in a
# sandbox from which the live city cannot be reached. Sourced, never executed.
#
# The engine is the npm package @zookanalytics/sprintshow. A city that has the
# engine's source as a rig uses that checkout: the rig `gc rig list` names
# sprintshow, taken only when its package.json names the package, so an
# unrelated rig of that name is passed over. A checkout has its dependencies
# installed first when it has no node_modules, or when its node_modules lacks a
# package its package.json depends on, as it does once an update of the
# checkout adds one. Its CLI runs from its TypeScript source under node, as the
# engine's own package scripts run it. Any other city uses the published
# package through npx.
#
# The engine's package requires Node 22.18 or later, and a checkout's CLI needs
# that release too, because it is where node starts stripping TypeScript without
# a flag. So Node is checked against that floor before anything is installed.
#
# The browser is installed through the engine's own Playwright before every
# capture, local or published. The engine launches the chromium-headless-shell
# revision its Playwright pins, so only that Playwright's installer knows which
# build to fetch and where to keep it. The installer skips a build that is
# already installed, so a capture on a provisioned host downloads nothing.
#
# The CLI runs inside a macOS sandbox, through sandbox-exec, so the command a
# capture types, the server it starts and the page it loads all run where the
# live city cannot be reached. A read of the city fails there, and a capture
# shows the reviewed commit on fixture data or shows the failure, never live
# state. The sandbox denies:
#   - the contents of the city's directories: gc's home, each city its
#     cities.toml lists, the city, rig and store this session's environment
#     names, and each rig checkout in the city's rig map. A directory's listing
#     and a file's contents are denied, and their metadata is not, because node
#     resolves a path by reading the metadata of each directory above it.
#   - every loopback port but the one the capture's own server listens on, and
#     every Unix socket but the system resolver's, so the supervisor's API, the
#     Dolt server and the session server do not answer.
#   - signals to any process outside the sandbox.
# The CLI also runs without the environment variables that point a command at
# the city: GC_*, BEADS_*, BD_*, DOLT_*, TMUX and TMUX_PANE.
#
# Inside the city's directories the run reads and writes only what the engine's
# own arguments name: its working directory, the output's directory, --cwd,
# --serve-dir, a captures directory, and the script and the music it reads.
# Each directory is widened to the rig worktree that holds it, with that
# worktree's git directories, so git runs there. The run also reads the engine
# checkout, except the dot-directories where a rig keeps its store and its
# agents' state, and no rig's or city's store is readable whatever else is.
# The run is refused before the engine starts when:
#   - a directory it would read and write holds one of the city's directories,
#     or lies inside one in no rig's worktree;
#   - a city is known and its rig map does not read, because then the rig
#     checkouts to deny are unknown;
#   - a server already answers on the --serve or --serve-dir port, because the
#     engine would capture that server, which runs outside the sandbox. A
#     --serve-dir given no --port is given a free one, because the sandbox
#     opens only a port it knows;
#   - --base-url names this host, whose servers run outside the sandbox.
# A host without sandbox-exec runs no capture at all.
#
#   demo_engine_resolve  Checks that this host has the sandbox and checks Node
#                        against the engine's floor, finds the engine, checks
#                        that a capture may run from the working directory, and
#                        installs what it needs before a capture: a checkout's
#                        dependencies, and the browser. Sets DEMO_ENGINE_DIR to
#                        the checkout, or to empty for the published package,
#                        and says on stderr which engine it chose. The
#                        installers write to stderr too, so the caller's stdout
#                        carries only its own report. Returns 1, having said why
#                        on stderr, when the host has no sandbox, Node is
#                        missing or below the floor, the sandbox would refuse a
#                        run from the working directory, an install fails, or
#                        the published package has no npx to run it.
#   demo_engine_find     The lookup alone: sets DEMO_ENGINE_DIR the same way,
#                        installs nothing, and returns 0.
#   demo_engine_cli      Runs the CLI of the engine demo_engine_resolve chose,
#                        inside the sandbox, with the arguments it is given, in
#                        the caller's working directory, and returns the CLI's
#                        exit status. Returns 1, having said why on stderr,
#                        when the run is refused.
#   demo_engine_free_port
#                        Prints a loopback port that nothing listens on, or
#                        returns 1.
#
# DEMO_ENGINE_PACKAGE names the package. DEMO_ENGINE_BIN, when set, names an
# executable that demo_engine_cli runs in the engine's place, in the same
# sandbox. Messages start with the caller's $PROG.
#
# Each capture keeps what only it needs. rig-demo-capture.sh provisions ffmpeg
# for a checkout and records a clip with the CLI's `run`; demo-screenshot.sh
# saves a PNG with its `screenshot`. The demo:capture skill's examples run the
# engine through this file too. demo-engine-lib.test.sh checks this policy
# through each capture and through the skill's examples, and fails when any of
# them stops sourcing this file or runs a step of it itself.
#
# A caller resolves this file beside itself and sources it:
#   # shellcheck source=demo-engine-lib.sh
#   . "$HERE/demo-engine-lib.sh" || { echo "$PROG: cannot source demo-engine-lib.sh" >&2; exit 1; }
#   demo_engine_resolve || exit 1
#   demo_engine_cli <command> <arguments...>
# An agent's shell has no script beside it, so the skill sources this file from
# the pack gc loaded, as "$(gc <binding> scripts-dir)/demo-engine-lib.sh".

DEMO_ENGINE_PACKAGE=@zookanalytics/sprintshow

# The directory this library is sourced from, where rig-map.sh sits beside it.
# bash names the file being sourced in BASH_SOURCE, and zsh in $0.
DEMO_ENGINE_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)

_demo_engine_say() { echo "${PROG:-demo-engine-lib}: $1" >&2; }

_demo_engine_node_ok() {
  local ver major rest minor
  if ! command -v node >/dev/null 2>&1; then
    _demo_engine_say "node not found; the SprintShow engine needs Node >= 22.18. doctor/check-demo-toolchain names this gap."
    return 1
  fi
  ver=$(node --version 2>/dev/null | sed 's/^v//')
  major=${ver%%.*}; rest=${ver#*.}; minor=${rest%%.*}
  case "$major" in ''|*[!0-9]*) major=0 ;; esac
  case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
  if [ "$major" -lt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -lt 18 ]; }; then
    _demo_engine_say "Node ${ver:-unknown} is below the engine's floor of 22.18"
    return 1
  fi
}

# _demo_engine_rig_map: reads the city's rig map into DEMO_ENGINE_RIG_MAP once
# per shell, and returns whether it holds one. It stays empty when gc or jq is
# missing or the map does not read, and rig-map.sh then says why on stderr.
_demo_engine_rig_map() {
  if [ -z "${_DEMO_ENGINE_RIG_MAP_READ:-}" ]; then
    _DEMO_ENGINE_RIG_MAP_READ=1
    DEMO_ENGINE_RIG_MAP=""
    if command -v gc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      DEMO_ENGINE_RIG_MAP=$("$DEMO_ENGINE_LIB_DIR/rig-map.sh")
    fi
  fi
  [ -n "$DEMO_ENGINE_RIG_MAP" ]
}

demo_engine_find() {
  local dir=""
  DEMO_ENGINE_DIR=""
  if _demo_engine_rig_map; then
    dir=$(printf '%s' "$DEMO_ENGINE_RIG_MAP" | jq -r '.rigs[]? | objects | select(.name=="sprintshow") | .path // empty' 2>/dev/null | head -n1)
  fi
  if [ -n "$dir" ] && [ "$(jq -r '.name // empty' "$dir/package.json" 2>/dev/null)" = "$DEMO_ENGINE_PACKAGE" ]; then
    DEMO_ENGINE_DIR=$dir
  fi
  return 0
}

# _demo_engine_deps_missing <checkout>: true when the checkout has no
# node_modules, or when a package its package.json lists in dependencies is not
# installed there.
_demo_engine_deps_missing() {
  local name
  [ -d "$1/node_modules" ] || return 0
  while IFS= read -r name; do
    [ -z "$name" ] || [ -f "$1/node_modules/$name/package.json" ] || return 0
  done < <(jq -r '(.dependencies // {}) | keys[]' "$1/package.json" 2>/dev/null)
  return 1
}

demo_engine_resolve() {
  _demo_engine_sandbox_ok || return 1
  _demo_engine_node_ok || return 1
  demo_engine_find
  # Whether a capture may run from here at all, decided before anything is
  # installed. demo_engine_cli decides it again for every directory a run names.
  _demo_engine_city || return 1
  _demo_engine_reach "$(pwd -P)" >/dev/null || return 1
  if [ -n "$DEMO_ENGINE_DIR" ]; then
    if _demo_engine_deps_missing "$DEMO_ENGINE_DIR" && ! ( cd "$DEMO_ENGINE_DIR" && npm install ) >&2; then
      _demo_engine_say "'npm install' failed in the sprintshow rig checkout"
      return 1
    fi
    if ! ( cd "$DEMO_ENGINE_DIR" && npm run provision:browser ) >&2; then
      _demo_engine_say "could not provision the browser ('npm run provision:browser' failed in the sprintshow rig checkout)"
      return 1
    fi
    _demo_engine_say "engine = local sprintshow rig ($DEMO_ENGINE_DIR)"
  else
    if ! command -v npx >/dev/null 2>&1; then
      _demo_engine_say "npx not found; it ships with Node and runs the published engine"
      return 1
    fi
    if ! npx --yes --package="$DEMO_ENGINE_PACKAGE" -- playwright install chromium-headless-shell >&2; then
      _demo_engine_say "could not provision the browser (the published engine's 'playwright install chromium-headless-shell' failed)"
      return 1
    fi
    _demo_engine_say "engine = published $DEMO_ENGINE_PACKAGE (no local rig checkout)"
  fi
}

# --- the sandbox -------------------------------------------------------------

_demo_engine_sandbox_ok() {
  command -v sandbox-exec >/dev/null 2>&1 && return 0
  _demo_engine_say "sandbox-exec not found, so this host has no sandbox to keep a capture away from the live city, and no capture runs here; captures run on macOS, which ships sandbox-exec"
  return 1
}

demo_engine_free_port() {
  local port
  port=$(node -e 'const s = require("net").createServer(); s.listen(0, "127.0.0.1", () => { process.stdout.write(String(s.address().port)); s.close(); });' 2>/dev/null)
  case "$port" in ''|*[!0-9]*|0*) return 1 ;; esac
  printf '%s\n' "$port"
}

# _demo_engine_port_answers <port>: true when a server answers on that loopback
# port, over IPv4 or IPv6, or when nothing could tell.
_demo_engine_port_answers() {
  node -e 'const net = require("net"); const port = Number(process.argv[1]); const knock = (host) => new Promise((done) => { const s = net.connect({ host, port }); s.setTimeout(2000, () => { s.destroy(); done(false); }); s.once("connect", () => { s.destroy(); done(true); }); s.once("error", () => done(false)); }); (async () => { process.exit((await knock("127.0.0.1")) || (await knock("::1")) ? 3 : 0); })();' "$1" >/dev/null 2>&1
  [ $? -ne 0 ]
}

# _demo_engine_loopback <url>: true when the URL's host is this host's loopback.
_demo_engine_loopback() {
  local h="${1#*://}"
  h="${h%%/*}"; h="${h%%\?*}"; h="${h%%#*}"; h="${h##*@}"
  case "$h" in
    \[*) h="${h#\[}"; h="${h%%]*}" ;;
    *) h="${h%:*}" ;;
  esac
  case "$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')" in
    localhost|localhost.|*.localhost|*.localhost.|127.*|::1|0.0.0.0|::) return 0 ;;
  esac
  return 1
}

# _demo_engine_canon <path>: the path as the sandbox matches it, with every
# symlink resolved, or nothing when it does not exist.
_demo_engine_canon() {
  local p="$1" n i=0
  [ -n "$p" ] || return 0
  while [ -L "$p" ] && [ "$i" -lt 40 ]; do
    n=$(readlink -- "$p") || return 0
    case "$n" in /*) p="$n" ;; *) p="$(dirname -- "$p")/$n" ;; esac
    i=$((i + 1))
  done
  if [ -d "$p" ]; then
    (CDPATH='' cd -- "$p" 2>/dev/null && pwd -P)
  elif [ -e "$p" ]; then
    n=$(CDPATH='' cd -- "$(dirname -- "$p")" 2>/dev/null && pwd -P) && printf '%s/%s\n' "$n" "${p##*/}"
  fi
}

# _demo_engine_under <path> <dir>: true when the path is the directory or lies
# inside it.
_demo_engine_under() {
  [ "$2" = / ] && return 0
  case "$1" in "$2"|"$2"/*) return 0 ;; esac
  return 1
}

# _demo_engine_cities: each city path gc's home lists in cities.toml, one per
# line.
_demo_engine_cities() {
  local h
  for h in "${GC_HOME:-}" "${HOME:+$HOME/.gc}"; do
    [ -n "$h" ] && [ -f "$h/cities.toml" ] || continue
    sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$h/cities.toml"
  done
}

# _demo_engine_city_known: true when gc's home lists a city that exists, or the
# environment names one.
_demo_engine_city_known() {
  local p
  while IFS= read -r p; do
    case "$p" in /*) [ -d "$p" ] && return 0 ;; esac
  done <<EOF
${GC_CITY_PATH:-}
${GC_CITY:-}
$(_demo_engine_cities)
EOF
  return 1
}

# _demo_engine_city_places <rigs>: each directory that holds the live city's
# state, one canonical path per line: gc's home, each city it lists, the city,
# rig and store the environment names, and each rig checkout in <rigs>.
_demo_engine_city_places() {
  local p
  while IFS= read -r p; do
    case "$p" in /*) _demo_engine_canon "$p" ;; esac
  done <<EOF
${GC_HOME:-}
${HOME:+$HOME/.gc}
${GC_CITY_PATH:-}
${GC_CITY:-}
${GC_RIG_ROOT:-}
${GC_BEADS_SCOPE_ROOT:-}
${BEADS_DIR:-}
${GC_CITY_RUNTIME_DIR:-}
$(_demo_engine_cities)
$1
EOF
}

# _demo_engine_city_stores: each store and state directory no run may read,
# whatever else it may, one canonical path per line: gc's home, the store and
# runtime directory the environment names, and the .beads of each place.
_demo_engine_city_stores() {
  local p
  while IFS= read -r p; do
    case "$p" in /*) _demo_engine_canon "$p" ;; esac
  done <<EOF
${GC_HOME:-}
${HOME:+$HOME/.gc}
${BEADS_DIR:-}
${GC_CITY_RUNTIME_DIR:-}
EOF
  while IFS= read -r p; do
    [ -z "$p" ] || _demo_engine_canon "$p/.beads"
  done <<EOF
$1
EOF
}

# _demo_engine_city: reads where the live city keeps its state into
# _DEMO_ENGINE_RIGS, each rig checkout its rig map lists, and
# _DEMO_ENGINE_PLACES, each of its directories, one canonical path per line.
# Returns 1, having said why, when a city is known and its rig map does not
# read, because the rig checkouts to deny are then unknown.
_demo_engine_city() {
  local p
  if _demo_engine_city_known && ! _demo_engine_rig_map; then
    _demo_engine_say "the city's rig map did not read, so the rig checkouts to keep out of the capture's reach are unknown; $DEMO_ENGINE_LIB_DIR/rig-map.sh says why"
    return 1
  fi
  _DEMO_ENGINE_RIGS=""
  if [ -n "${DEMO_ENGINE_RIG_MAP:-}" ]; then
    _DEMO_ENGINE_RIGS=$(printf '%s' "$DEMO_ENGINE_RIG_MAP" | jq -r '.rigs[]? | objects | .path // empty' 2>/dev/null \
      | while IFS= read -r p; do case "$p" in /*) _demo_engine_canon "$p" ;; esac; done)
  fi
  _DEMO_ENGINE_PLACES=$(_demo_engine_city_places "$_DEMO_ENGINE_RIGS")
}

# _demo_engine_reach <dir>: after _demo_engine_city, what a run that reads and
# writes the directory may reach: the directory, widened to the rig worktree
# that holds it, and that worktree's own git directory, each on a line after
# "rw ", and the worktree's repository on a line after "ro ". Returns 1, having
# said why, when the directory holds one of the city's directories, or lies in
# one in no rig's worktree.
_demo_engine_reach() {
  local d top common="" gd="" match="" p
  d=$(_demo_engine_canon "$1"); [ -n "$d" ] || return 0
  top="$d"
  if [ -n "${_DEMO_ENGINE_RIGS:-}" ] && command -v git >/dev/null 2>&1; then
    common=$(_demo_engine_canon "$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")
    while IFS= read -r p; do [ -z "$common" ] || [ "$common" != "$p/.git" ] || match=1; done <<EOF
$_DEMO_ENGINE_RIGS
EOF
    if [ -n "$match" ]; then
      top=$(_demo_engine_canon "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)"); [ -n "$top" ] || top="$d"
      gd=$(_demo_engine_canon "$(git -C "$d" rev-parse --path-format=absolute --git-dir 2>/dev/null)")
    else
      common=""
    fi
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if _demo_engine_under "$p" "$top"; then
      _demo_engine_say "$top holds $p, where the live city keeps its state, so a capture cannot read or write it; run the capture from, and give it, directories that hold none of the city's"
      return 1
    fi
    if [ -z "$common" ] && _demo_engine_under "$top" "$p"; then
      _demo_engine_say "$top lies in $p, where the live city keeps its state, and in no rig's worktree, so a capture cannot read or write it; capture from a rig worktree, or from a directory outside the city's"
      return 1
    fi
  done <<EOF
${_DEMO_ENGINE_PLACES:-}
EOF
  printf 'rw %s\n' "$top"
  [ -z "$gd" ] || printf 'rw %s\n' "$gd"
  [ -z "$common" ] || printf 'ro %s\n' "$common"
}

demo_engine_cli() {
  local NL='
' pos="" port="" open="" base="" serve="" serve_dir="" cand="" files="" places=""
  local rw="" ro="" p d reach kind engine="" profile v
  local -a argv unsets
  _demo_engine_sandbox_ok || return 1
  argv=("$@")
  [ $# -eq 0 ] || shift

  # What the run reads and writes, and the server it starts, as the engine's own
  # arguments name them.
  cand=$(pwd -P)
  while [ $# -gt 0 ]; do
    case "$1" in
      -o|--output) [ $# -lt 2 ] || cand="$cand$NL$(dirname -- "$2")"; shift ;;
      --cwd)       [ $# -lt 2 ] || cand="$cand$NL$2"; shift ;;
      --serve-dir) serve_dir=1; [ $# -lt 2 ] || cand="$cand$NL$2"; shift ;;
      --music)     [ $# -lt 2 ] || files="$files$NL$2"; shift ;;
      --port)      port="${2:-}"; shift ;;
      --serve)     serve=1; shift ;;
      --base-url)  base="${2:-}"; shift ;;
      --mode|--selector|--scale) shift ;;
      -*) ;;
      *) [ -n "$pos" ] || pos="$1" ;;
    esac
    [ $# -eq 0 ] || shift
  done
  if [ -d "$pos" ]; then cand="$cand$NL$pos"; elif [ -f "$pos" ]; then files="$files$NL$pos"; fi
  [ -z "${DEMO_ENGINE_BIN:-}" ] || files="$files$NL$DEMO_ENGINE_BIN"

  # The one loopback port the run may reach is its own server's, and nothing may
  # answer there before the run starts. --serve waits on 5173 when given no
  # --port, as the engine does.
  if [ -n "$base" ] && _demo_engine_loopback "$base"; then
    _demo_engine_say "--base-url $base names a server on this host, which runs outside the capture's sandbox and can read the live city; start the app with --serve or --serve-dir, which run it inside the sandbox, or capture a deployed preview"
    return 1
  fi
  if [ -n "$serve$serve_dir" ]; then
    if [ -z "$port" ] && [ -z "$serve" ]; then
      open=$(demo_engine_free_port) || { _demo_engine_say "could not find a free port for the --serve-dir server"; return 1; }
      argv+=(--port "$open")
    else
      open="${port:-5173}"
      case "$open" in
        ''|*[!0-9]*|0*|??????*) open="" ;;
      esac
      [ -n "$open" ] && [ "$open" -le 65535 ] \
        || { _demo_engine_say "--port '$port' is not a port from 1 to 65535"; return 1; }
      if _demo_engine_port_answers "$open"; then
        _demo_engine_say "a server already answers on port $open, or nothing could tell, and the engine would capture that server, which runs outside the sandbox; give the capture a --port nothing listens on"
        return 1
      fi
    fi
  fi

  # The city's directories, and each directory the run reads and writes, as
  # _demo_engine_reach widens it.
  _demo_engine_city || return 1
  places="$_DEMO_ENGINE_PLACES"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    reach=$(_demo_engine_reach "$d") || return 1
    while IFS=' ' read -r kind p; do
      case "$kind" in rw) rw="$rw$NL$p" ;; ro) ro="$ro$NL$p" ;; esac
    done <<EOF
$reach
EOF
  done <<EOF
$cand
EOF
  while IFS= read -r p; do
    [ -z "$p" ] || ro="$ro$NL$(_demo_engine_canon "$p")"
  done <<EOF
$files
EOF
  [ -z "${DEMO_ENGINE_DIR:-}" ] || engine=$(_demo_engine_canon "$DEMO_ENGINE_DIR")

  # The profile names each path in a string, so a path it cannot quote is refused.
  while IFS= read -r p; do
    case "$p" in
      *'"'*|*'\'*|*[[:cntrl:]]*)
        _demo_engine_say "the path '$p' holds a double quote, a backslash or a control character, which the sandbox's profile cannot name"
        return 1 ;;
    esac
  done <<EOF
$places
$rw
$ro
${engine:-}
EOF

  profile="(version 1)$NL(allow default)"
  while IFS= read -r p; do
    [ -z "$p" ] || profile="$profile$NL(deny file-read-data file-write* (subpath \"$p\"))"
  done <<EOF
$places
EOF
  if [ -n "${engine:-}" ]; then
    profile="$profile$NL(allow file-read-data (regex #\"^$(printf '%s' "$engine" | sed 's/[][\.^$*+?(){}|]/\\&/g')/[^.]\"))"
  fi
  while IFS= read -r p; do
    [ -z "$p" ] || profile="$profile$NL(allow file-read-data file-write* (subpath \"$p\"))"
  done <<EOF
$rw
EOF
  while IFS= read -r p; do
    [ -z "$p" ] || profile="$profile$NL(allow file-read-data (subpath \"$p\"))"
  done <<EOF
$ro
EOF
  while IFS= read -r p; do
    [ -z "$p" ] || profile="$profile$NL(deny file-read-data file-write* (subpath \"$p\"))"
  done <<EOF
$(_demo_engine_city_stores "$places")
EOF
  profile="$profile$NL(deny network-outbound (remote ip \"localhost:*\"))"
  [ -z "$open" ] || profile="$profile$NL(allow network-outbound (remote ip \"localhost:$open\"))"
  profile="$profile$NL(deny network-outbound (remote unix-socket))"
  profile="$profile$NL(allow network-outbound (remote unix-socket (path-literal \"/private/var/run/mDNSResponder\")))"
  profile="$profile$NL(deny signal)$NL(allow signal (target same-sandbox))"

  unsets=()
  while IFS= read -r v; do
    [ -z "$v" ] || unsets+=(-u "$v")
  done < <(env | sed -n -E 's/^((GC|BEADS|BD|DOLT)_[A-Za-z0-9_]*|TMUX|TMUX_PANE)=.*/\1/p')
  if [ -n "${DEMO_ENGINE_BIN:-}" ]; then
    set -- "$DEMO_ENGINE_BIN"
  elif [ -n "${DEMO_ENGINE_DIR:-}" ]; then
    set -- node "$DEMO_ENGINE_DIR/src/cli.ts"
  else
    set -- npx --yes "$DEMO_ENGINE_PACKAGE"
  fi
  env ${unsets[@]+"${unsets[@]}"} sandbox-exec -p "$profile" "$@" ${argv[@]+"${argv[@]}"}
}
