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
# capture types and the page it loads run where the live city cannot be
# reached. So does a copy of a rig's UI that `gctk rig serve` runs for a
# capture or a person, whose serve command runs inside the same sandbox through
# demo_engine_sandboxed. A read of the city fails there, and a capture shows the
# reviewed commit on fixture data or shows the failure, never live state. The
# sandbox denies:
#   - the contents of the city's directories: gc's home, each city `gc cities`
#     lists there, the city, rig and store this session's environment names, and
#     each rig checkout in the city's rig map. A directory's listing and a file's
#     contents are denied, and their metadata is not, because node resolves a
#     path by reading the metadata of each directory above it.
#   - every loopback port but one, and every Unix socket but the system
#     resolver's, so the supervisor's API, the Dolt server and the session
#     server do not answer. The one port is the engine's own --serve-dir
#     server's, the port of a rig's app that a --base-url on this host names, as
#     below, or, for a copy, the copy's own.
#   - signals to any process outside the sandbox.
# The CLI also runs without the environment variables that point a command at
# the city: GC_*, GT_*, BEADS_*, BD_*, DOLT_*, TMUX and TMUX_PANE.
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
#   - gc's home holds a city registry that `gc cities` does not read, because
#     then the cities to deny are unknown;
#   - a city is known and its rig map does not read, because then the rig
#     checkouts to deny are unknown;
#   - the engine is given --serve, which would start a server whose port the
#     sandbox cannot vouch for. A capture serves an app with a command as a copy
#     that `gctk rig serve` runs inside this sandbox, and points the engine at
#     the copy with --base-url;
#   - a server already answers on the --serve-dir port, because the engine
#     would capture that server, which runs outside the sandbox. A --serve-dir
#     given no --port is given a free one, because the sandbox opens only a
#     port it knows;
#   - --base-url names this host, whose servers run outside the sandbox, unless
#     a copy that `gctk rig serve` runs holds its port, as `gctk rig serve
#     --check` answers in the checkout a process listening there works in, or
#     each process listening on its port works in a worktree of a rig whose
#     app_reads_city is "false". No variable that points at the city may name
#     the port. A rig's checkout, which holds its store, and the city's own
#     repository never count as such a worktree.
# A host without sandbox-exec runs no capture at all.
#
# app_reads_city is a formula var that mol-rig-demo declares with the default
# "false". A city sets it to "true" in city.toml for each rig whose app reads
# the city, such as a rig that develops code for a city:
#   [rigs.formula_vars]
#   app_reads_city = "true"
# It lives outside the rig's repository, so no change the rig reviews can
# remove it. Any value but "false" counts as "true", and so does a read that
# fails. The rig that holds this library counts as "true" too, because the
# pack's board and scripts read the city.
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
#   demo_engine_sandboxed <port> <dir> <command...>
#                        Runs the command inside the sandbox, in the caller's
#                        working directory, with <port> the one loopback port
#                        it may reach and <dir> what it reads and writes, as a
#                        capture's --cwd. `gctk rig serve` runs a copy's serve
#                        command through it. Returns the command's exit status,
#                        or 1, having said why on stderr, when the run is
#                        refused.
#   demo_engine_copy <dir> <command>
#                        Serves an app a command serves as a copy that `gctk
#                        rig serve` runs from the checkout <dir> sits in, with
#                        no address, and sets DEMO_ENGINE_COPY_URL to the
#                        loopback URL a capture's --base-url gives the engine.
#                        A checkout has one copy, so captures from one checkout
#                        run one after another. One that already runs the
#                        command is the one captured, and it keeps running
#                        after the capture, and one that runs another command
#                        is refused. One this call's start reports it ran is
#                        demo_engine_copy_stop's to end. Returns 1, having said
#                        why on stderr, when no copy of the command runs.
#   demo_engine_copy_stop
#                        Ends the copy demo_engine_copy started, if it started
#                        one.
#   demo_engine_guide <dir>
#                        Reads the app that the rig's demo guide names: the
#                        docs/review-demo.md of the commit checked out in the
#                        git worktree that holds <dir>, which review-checks.sh
#                        --extension demo reads at that commit. Sets
#                        DEMO_GUIDE_ROOT to the worktree's root, DEMO_GUIDE to
#                        the guide's name and commit, or to empty when the
#                        commit carries none, and DEMO_GUIDE_SERVE,
#                        DEMO_GUIDE_SERVE_DIR, DEMO_GUIDE_BASE_URL,
#                        DEMO_GUIDE_CWD and DEMO_GUIDE_PORT to the values of the
#                        guide's **Serve:**, **Serve dir:**, **Base URL:**,
#                        **Cwd:** and **Port:** lines, each empty when the guide
#                        has no such line. A relative directory is resolved
#                        against the worktree's root. Returns 1, having said
#                        why on stderr, when <dir> is in no git worktree, the
#                        guide does not read, or it names a line twice, names
#                        more than one of **Serve:**, **Serve dir:** and **Base
#                        URL:**, names **Port:** beside no **Serve dir:**, gives
#                        a value that is not one code span, or names a
#                        directory that lies outside the worktree.
#
# A rig names the app a capture brings up in its demo guide, in the options a
# capture takes: the guide's section "Bring the app up" holds one line for
# each, such as **Serve:** `npm run dev`. The lines are read only in that
# section and outside a fenced code block. Every capture that takes the app
# from the guide reads it through demo_engine_guide, so the guide names the
# app the same way to each. The demo:capture skill says what else the guide
# holds.
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
# the pack gc loaded, as "$(gc <binding> scripts-dir)/demo-engine-lib.sh". That
# shell can be zsh or macOS's bash 3.2, so this file keeps to what each of them
# runs: zsh ties a variable named argv to the positional parameters, and bash 3.2
# cannot parse a case pattern with no opening parenthesis inside $(...).

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

# --- the rig's demo guide ----------------------------------------------------

# The guide is read at the commit, as every reader of a rig's review guidance
# reads it, so a capture takes the app of the commit it shows and never a copy
# in a working tree. The awk program reads the guide's section "Bring the app
# up": a level-one or level-two heading of that text, in any case, opens it,
# and the next such heading closes it. A fenced code block, opened by three or
# more backticks or tildes and closed by at least as many of the same, holds no
# heading and no line. Each line it reads prints as key=value, and each fault
# as !message, and it exits 1 when it found one.
# shellcheck disable=SC2034  # the DEMO_GUIDE_* values are read by the scripts that source this file
demo_engine_guide() {
  local dir="$1" top="" oid="" text="" out="" rc=0 root="" line key val raw k p
  DEMO_GUIDE=""; DEMO_GUIDE_ROOT=""; DEMO_GUIDE_SERVE=""; DEMO_GUIDE_SERVE_DIR=""
  DEMO_GUIDE_BASE_URL=""; DEMO_GUIDE_CWD=""; DEMO_GUIDE_PORT=""
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) \
    && oid=$(git -C "$dir" rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null) \
    && [ -n "$top" ] && [ -n "$oid" ] \
    || { _demo_engine_say "'$dir' is in no git worktree with a commit checked out, so no commit there holds a demo guide"; return 1; }
  DEMO_GUIDE_ROOT="$top"
  text=$(CDPATH='' cd -- "$top" && "$DEMO_ENGINE_LIB_DIR/review-checks.sh" --extension demo --at "$oid") \
    || { _demo_engine_say "the demo guide at $oid in $top did not read"; return 1; }
  [ -n "$text" ] || return 0
  DEMO_GUIDE="docs/review-demo.md at $(printf '%.12s' "$oid") in $top"
  out=$(printf '%s\n' "$text" | awk -v guide="$DEMO_GUIDE" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function fault(m) { printf "!%s\n", m; bad = 1 }
    {
      raw = $0; sub(/\r$/, "", raw)
      t = raw; ind = 0
      while (ind < 4 && substr(t, 1, 1) == " ") { t = substr(t, 2); ind++ }
      if (ind < 4 && (substr(t, 1, 3) == "```" || substr(t, 1, 3) == "~~~")) {
        c = substr(t, 1, 1); n = 0
        while (substr(t, n + 1, 1) == c) n++
        if (fence == "") { fence = c; flen = n; next }
        if (c == fence && n >= flen && trim(substr(t, n + 1)) == "") { fence = ""; next }
      }
      if (fence != "") next
      if (ind < 4 && substr(t, 1, 1) == "#") {
        h = 0
        while (substr(t, h + 1, 1) == "#") h++
        rest = substr(t, h + 1)
        if (h <= 2 && (rest == "" || rest ~ /^[ \t]/)) {
          txt = trim(rest); sub(/(^|[ \t]+)#+$/, "", txt)
          sect = (tolower(txt) == "bring the app up")
          next
        }
      }
      if (!sect) next
      l = trim(raw)
      if (l !~ /^\*\*[^*]+:\*\*/) next
      k = substr(l, 3); k = substr(k, 1, index(k, ":**") - 1)
      key = tolower(k)
      if (key == "serve dir") key = "serve_dir"
      else if (key == "base url") key = "base_url"
      else if (key != "serve" && key != "cwd" && key != "port") next
      v = trim(substr(l, index(l, ":**") + 3))
      if (seen[key]++) { fault(guide ", line " FNR ": the section Bring the app up names **" k ":** twice; name it once"); next }
      if (v !~ /^`[^`]+`$/ || trim(substr(v, 2, length(v) - 2)) == "") {
        fault(guide ", line " FNR ": write **" k ":** with its value in one code span, as **" k ":** `<value>`")
        next
      }
      printf "%s=%s\n", key, trim(substr(v, 2, length(v) - 2))
    }
    END {
      if ((seen["serve"] > 0) + (seen["serve_dir"] > 0) + (seen["base_url"] > 0) > 1)
        fault(guide ": the section Bring the app up names more than one of **Serve:**, **Serve dir:** and **Base URL:**; name the one app a capture brings up")
      if (seen["port"] && !seen["serve_dir"])
        fault(guide ": the section Bring the app up names **Port:**, which is the port of the server that serves a **Serve dir:**; a **Serve:** command gets a free port of its own as $PORT, so name **Port:** only beside **Serve dir:**")
      exit bad
    }') || rc=1
  # A capture opens the rig worktree that holds each directory it is given, so
  # a directory the guide names must lie in the worktree the guide was read
  # from. It leads where the deepest part of it that exists leads, through any
  # symlink the commit holds, as the sandbox resolves it.
  root=$(_demo_engine_canon "$top")
  [ -n "$root" ] || { _demo_engine_say "the root of the worktree $top did not resolve"; return 1; }
  while IFS= read -r line; do
    case "$line" in
      '!'*) _demo_engine_say "${line#!}"; continue ;;
      *=*) ;;
      *) continue ;;
    esac
    key=${line%%=*}; val=${line#*=}
    case "$key" in
      cwd|serve_dir)
        raw=$val
        case "$val" in
          /*) ;;
          .|./) val="$top" ;;
          ./*) val="$top/${val#./}" ;;
          *) val="$top/$val" ;;
        esac
        p=$val
        while [ ! -e "$p" ] && [ "$p" != / ]; do p=$(dirname -- "$p"); done
        p=$(_demo_engine_canon "$p")
        if [ -z "$p" ] || ! _demo_engine_under "$p" "$root"; then
          if [ "$key" = cwd ]; then k='**Cwd:**'; else k='**Serve dir:**'; fi
          _demo_engine_say "$DEMO_GUIDE: $k \`$raw\` leads outside the worktree, to ${p:-a place that does not resolve}; name a directory in the repository, relative to its root"
          rc=1; continue
        fi ;;
    esac
    case "$key" in
      serve) DEMO_GUIDE_SERVE="$val" ;;
      serve_dir) DEMO_GUIDE_SERVE_DIR="$val" ;;
      base_url) DEMO_GUIDE_BASE_URL="$val" ;;
      cwd) DEMO_GUIDE_CWD="$val" ;;
      port) DEMO_GUIDE_PORT="$val" ;;
    esac
  done <<EOF
$out
EOF
  return "$rc"
}

# --- the sandbox -------------------------------------------------------------

_demo_engine_sandbox_ok() {
  command -v sandbox-exec >/dev/null 2>&1 && return 0
  _demo_engine_say "sandbox-exec not found, so this host has no sandbox to keep a capture away from the live city, and no capture runs here; captures run on macOS, which ships sandbox-exec"
  return 1
}

# _demo_engine_free_port: prints a loopback port that nothing listens on, for
# the engine's own --serve-dir server, or returns 1.
_demo_engine_free_port() {
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

# _demo_engine_url_port <url>: prints the TCP port the URL names, or the port
# its http or https scheme implies, or returns 1 when it names no port from 1 to
# 65535.
_demo_engine_url_port() {
  local scheme="" h p=""
  case "$1" in *://*) scheme=$(printf '%s' "${1%%://*}" | tr '[:upper:]' '[:lower:]') ;; esac
  h="${1#*://}"
  h="${h%%/*}"; h="${h%%\?*}"; h="${h%%#*}"; h="${h##*@}"
  case "$h" in
    \[*\]:*) p="${h##*\]:}" ;;
    \[*) ;;
    *:*) p="${h##*:}" ;;
  esac
  if [ -z "$p" ]; then
    case "$scheme" in http) p=80 ;; https) p=443 ;; *) return 1 ;; esac
  fi
  case "$p" in ''|*[!0-9]*|0*|??????*) return 1 ;; esac
  [ "$p" -le 65535 ] || return 1
  printf '%s\n' "$p"
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

# _demo_engine_cities: reads into _DEMO_ENGINE_CITIES each city path `gc cities`
# lists, one per line, for the gc home the environment names and for the user's
# own. A home with no registry lists none. Returns 1, having said why, when gc
# does not read a registry, because the cities to deny are then unknown.
_demo_engine_cities() {
  local h out paths NL='
'
  _DEMO_ENGINE_CITIES=""
  for h in "${GC_HOME:-}" "${HOME:+$HOME/.gc}"; do
    [ -n "$h" ] && [ -f "$h/cities.toml" ] || continue
    if command -v gc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
      && out=$(GC_HOME="$h" gc cities --json) \
      && paths=$(printf '%s' "$out" | jq -er '.cities | map(.path) | join("\n")'); then
      _DEMO_ENGINE_CITIES="$_DEMO_ENGINE_CITIES$NL$paths"
    else
      _demo_engine_say "gc did not read the city registry in $h, so the cities to keep out of the capture's reach are unknown"
      return 1
    fi
  done
}

# _demo_engine_city_known: after _demo_engine_cities, true when gc's home lists a
# city that exists, or the environment names one.
_demo_engine_city_known() {
  local p
  while IFS= read -r p; do
    case "$p" in /*) [ -d "$p" ] && return 0 ;; esac
  done <<EOF
${GC_CITY_PATH:-}
${GC_CITY:-}
${_DEMO_ENGINE_CITIES:-}
EOF
  return 1
}

# _demo_engine_city_places <rigs>: after _demo_engine_cities, each directory that
# holds the live city's state, one canonical path per line: gc's home, each city
# it lists, the city, rig and store the environment names, and each rig checkout
# in <rigs>.
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
${_DEMO_ENGINE_CITIES:-}
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
# _DEMO_ENGINE_RIGS, each rig checkout its rig map lists, _DEMO_ENGINE_HQ, the
# checkout of the map's hq entry, which is the city's own repository, and
# _DEMO_ENGINE_PLACES, each of its directories, one canonical path per line.
# Returns 1, having said why, when gc does not read a city registry, or when a
# city is known and its rig map does not read, because the cities or the rig
# checkouts to deny are then unknown.
_demo_engine_city() {
  local p
  _demo_engine_cities || return 1
  if _demo_engine_city_known && ! _demo_engine_rig_map; then
    _demo_engine_say "the city's rig map did not read, so the rig checkouts to keep out of the capture's reach are unknown; $DEMO_ENGINE_LIB_DIR/rig-map.sh says why"
    return 1
  fi
  _DEMO_ENGINE_RIGS=""; _DEMO_ENGINE_HQ=""
  if [ -n "${DEMO_ENGINE_RIG_MAP:-}" ]; then
    _DEMO_ENGINE_RIGS=$(printf '%s' "$DEMO_ENGINE_RIG_MAP" | jq -r '.rigs[]? | objects | .path // empty' 2>/dev/null \
      | while IFS= read -r p; do case "$p" in (/*) _demo_engine_canon "$p" ;; esac; done)
    _DEMO_ENGINE_HQ=$(printf '%s' "$DEMO_ENGINE_RIG_MAP" | jq -r '.rigs[]? | objects | select(.hq == true) | .path // empty' 2>/dev/null \
      | while IFS= read -r p; do case "$p" in (/*) _demo_engine_canon "$p" ;; esac; done)
  fi
  _DEMO_ENGINE_PLACES=$(_demo_engine_city_places "$_DEMO_ENGINE_RIGS")
}

# _demo_engine_rig_of <dir>: after _demo_engine_city, the canonical checkout of
# the rig whose repository holds the directory, or nothing.
_demo_engine_rig_of() {
  local common p
  [ -n "${_DEMO_ENGINE_RIGS:-}" ] && command -v git >/dev/null 2>&1 || return 0
  common=$(_demo_engine_canon "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")
  [ -n "$common" ] || return 0
  while IFS= read -r p; do
    if [ -n "$p" ] && [ "$common" = "$p/.git" ]; then printf '%s\n' "$p"; return 0; fi
  done <<EOF
$_DEMO_ENGINE_RIGS
EOF
}

# _demo_engine_reach <dir>: after _demo_engine_city, what a run that reads and
# writes the directory may reach: the directory, widened to the rig worktree
# that holds it, and that worktree's own git directory, each on a line after
# "rw ", and the worktree's repository on a line after "ro ". Returns 1, having
# said why, when the directory holds one of the city's directories, or lies in
# one in no rig's worktree.
_demo_engine_reach() {
  local d top common="" gd="" checkout p
  d=$(_demo_engine_canon "$1"); [ -n "$d" ] || return 0
  top="$d"
  checkout=$(_demo_engine_rig_of "$d")
  if [ -n "$checkout" ]; then
    common="$checkout/.git"
    top=$(_demo_engine_canon "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)"); [ -n "$top" ] || top="$d"
    gd=$(_demo_engine_canon "$(git -C "$d" rev-parse --path-format=absolute --git-dir 2>/dev/null)")
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if _demo_engine_under "$p" "$top"; then
      _demo_engine_say "$top holds $p, where the live city keeps its state, so a capture cannot read or write it; capture from a rig worktree, or from a directory that holds none of the city's"
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

# The formula var that says a rig's app reads the city, and the formula that
# declares it.
DEMO_ENGINE_READS_CITY_VAR=app_reads_city
DEMO_ENGINE_READS_CITY_FORMULA=mol-rig-demo

# _demo_engine_rig_name <rig checkout>: the name the city's rig map gives the
# rig with that checkout, or nothing.
_demo_engine_rig_name() {
  local tab p n
  tab=$(printf '\t')
  printf '%s' "${DEMO_ENGINE_RIG_MAP:-}" | jq -r '.rigs[]? | objects | [(.path // "" | tostring), (.name // "" | tostring)] | @tsv' 2>/dev/null \
    | while IFS="$tab" read -r p n; do
        case "$p" in (/*) if [ "$(_demo_engine_canon "$p")" = "$1" ]; then printf '%s\n' "$n"; break; fi ;; esac
      done
}

# _demo_engine_reads_city <rig checkout>: after _demo_engine_city, true when the
# rig's app_reads_city counts as "true", with _DEMO_ENGINE_READS_WHY set to why,
# and 1 when it reads "false".
_demo_engine_reads_city() {
  local name res
  if [ "$1" = "$(_demo_engine_rig_of "$DEMO_ENGINE_LIB_DIR")" ]; then
    _DEMO_ENGINE_READS_WHY="which holds this pack's own source, so its $DEMO_ENGINE_READS_CITY_VAR counts as \"true\""
    return 0
  fi
  name=$(_demo_engine_rig_name "$1")
  if [ -z "$name" ]; then
    _DEMO_ENGINE_READS_WHY="whose $DEMO_ENGINE_READS_CITY_VAR did not read, because the rig map gives that rig no name, so it counts as \"true\""
    return 0
  fi
  res=$(gc formula show "$DEMO_ENGINE_READS_CITY_FORMULA" --rig "$name" --json 2>/dev/null \
    | jq -r --arg v "$DEMO_ENGINE_READS_CITY_VAR" --arg f "$DEMO_ENGINE_READS_CITY_FORMULA" '
        if .ok != true then "unread " + ((.error.message // "gc formula show answered no formula") | tostring)
        else ([.vars[]? | select(.name == $v)][0]) as $d
          | if $d == null then "unread \($f) declares no \($v)"
            elif $d.rig_default != null then "rig " + ($d.rig_default | tostring)
            else "default " + (($d.default // "") | tostring) end
        end' 2>/dev/null)
  case "$res" in
    "rig false"|"default false") return 1 ;;
    "rig true") _DEMO_ENGINE_READS_WHY="for which city.toml sets $DEMO_ENGINE_READS_CITY_VAR = \"true\"" ;;
    "rig "*|"default "*) _DEMO_ENGINE_READS_WHY="whose $DEMO_ENGINE_READS_CITY_VAR reads \"${res#* }\", which is not \"false\", so it counts as \"true\"" ;;
    "unread "*) _DEMO_ENGINE_READS_WHY="whose $DEMO_ENGINE_READS_CITY_VAR did not read, because ${res#unread }, so it counts as \"true\"" ;;
    *) _DEMO_ENGINE_READS_WHY="whose $DEMO_ENGINE_READS_CITY_VAR did not read, because gc formula show $DEMO_ENGINE_READS_CITY_FORMULA --rig $name answered nothing jq could read, so it counts as \"true\"" ;;
  esac
  return 0
}

# _demo_engine_local_no <url> <reason>: says why a capture does not reach the
# server a --base-url on this host names, and returns 1.
_demo_engine_local_no() {
  _demo_engine_say "--base-url $1 names a server on this host, which runs outside the capture's sandbox. A capture reaches one only when a copy that gctk rig serve runs holds its port, or a worktree of a rig whose $DEMO_ENGINE_READS_CITY_VAR is \"false\" serves it, and here $2. Serve the app as a copy with gctk rig serve, which runs it inside the sandbox, or with --serve-dir, or capture a deployed preview"
  return 1
}

# _demo_engine_copy_port <port> <pids>: true when a copy that gctk rig serve
# runs holds the port, as gctk rig serve --check answers in the checkout one of
# the processes listening there works in, with _DEMO_ENGINE_COPY set to that
# checkout. The check reports a copy as running only while every process that
# listens on its port at an address loopback reaches is in the copy's own
# process group, whose serve command runs inside this sandbox.
_demo_engine_copy_port() {
  local port="$1" gctk pid dir top rep
  gctk="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
  [ -x "$gctk" ] || return 1
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    dir=$(lsof -a -nP -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)
    [ -n "$dir" ] || continue
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || continue
    rep=$(cd "$top" && "$gctk" rig serve --check 2>/dev/null)
    if printf '%s' "$rep" | jq -e --argjson p "$port" '.state == "running" and .port == $p' >/dev/null 2>&1; then
      _DEMO_ENGINE_COPY=$top
      return 0
    fi
  done <<EOF
$2
EOF
  return 1
}

# _demo_engine_local_port <url>: after _demo_engine_city, prints the port of a
# --base-url on this host when the rule in this file's header lets a capture
# reach it. Returns 1, having said why, otherwise.
_demo_engine_local_port() {
  local url="$1" port v val pids pid dir checkout="" NL='
'
  port=$(_demo_engine_url_port "$url") || { _demo_engine_local_no "$url" "the URL names no port from 1 to 65535"; return 1; }
  while IFS='=' read -r v val; do
    case "$v" in
      *PORT) [ "$val" != "$port" ] || { _demo_engine_local_no "$url" "port $port is the one $v names, which is the city's"; return 1; } ;;
    esac
    case "$val" in
      *:*)
        if _demo_engine_loopback "$val" && [ "$(_demo_engine_url_port "$val")" = "$port" ]; then
          _demo_engine_local_no "$url" "port $port is the one $v names, which is the city's"; return 1
        fi ;;
    esac
  done < <(env | sed -n -E '/^(GC|GT|BEADS|BD|DOLT)_[A-Za-z0-9_]*=/p')
  command -v lsof >/dev/null 2>&1 \
    || { _demo_engine_local_no "$url" "lsof, which names the processes that listen on port $port, is not on PATH"; return 1; }
  pids=$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null)
  [ -n "$pids" ] || { _demo_engine_local_no "$url" "no process of yours listens on port $port, so nothing shows whose server answers there"; return 1; }
  if _demo_engine_copy_port "$port" "$pids"; then
    _demo_engine_say "--base-url $url is a copy that gctk rig serve runs from $_DEMO_ENGINE_COPY inside the sandbox, so the capture reaches port $port and no other loopback port"
    printf '%s\n' "$port"
    return 0
  fi
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    dir=$(lsof -a -nP -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)
    [ -n "$dir" ] || { _demo_engine_local_no "$url" "lsof names no working directory for process $pid, which listens on port $port"; return 1; }
    checkout=$(_demo_engine_rig_of "$dir")
    [ -n "$checkout" ] || { _demo_engine_local_no "$url" "process $pid, which listens on port $port, works in $dir, which is in no rig's repository"; return 1; }
    case "$NL${_DEMO_ENGINE_HQ:-}$NL" in
      *"$NL$checkout$NL"*) _demo_engine_local_no "$url" "process $pid, which listens on port $port, works in $dir, in the city's own repository"; return 1 ;;
    esac
    _demo_engine_reach "$dir" >/dev/null 2>&1 \
      || { _demo_engine_local_no "$url" "process $pid, which listens on port $port, works in $dir, which holds the city's state, as a rig's checkout holds its store"; return 1; }
    if _demo_engine_reads_city "$checkout"; then
      _demo_engine_local_no "$url" "process $pid, which listens on port $port, works in a worktree of $checkout, $_DEMO_ENGINE_READS_WHY"; return 1
    fi
  done <<EOF
$pids
EOF
  _demo_engine_say "--base-url $url is served from a worktree of $checkout, whose $DEMO_ENGINE_READS_CITY_VAR is \"false\", so the capture reaches port $port and no other loopback port"
  printf '%s\n' "$port"
}

demo_engine_cli() {
  local NL='
' pos="" port="" open="" base="" serve_dir="" cand="" files=""
  local -a args
  _demo_engine_sandbox_ok || return 1
  args=("$@")
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
      --serve)
        _demo_engine_say "the engine's --serve would start a server whose port the sandbox cannot vouch for; serve the app as a copy with gctk rig serve, which runs it inside the sandbox, and give the engine the copy's --base-url"
        return 1 ;;
      --base-url)  base="${2:-}"; shift ;;
      --mode|--selector|--scale) shift ;;
      -*) ;;
      *) [ -n "$pos" ] || pos="$1" ;;
    esac
    [ $# -eq 0 ] || shift
  done
  if [ -d "$pos" ]; then cand="$cand$NL$pos"; elif [ -f "$pos" ]; then files="$files$NL$pos"; fi
  [ -z "${DEMO_ENGINE_BIN:-}" ] || files="$files$NL$DEMO_ENGINE_BIN"

  # The one loopback port the run may reach is its --serve-dir server's, where
  # nothing may answer before the run starts, or the port of a rig's app that a
  # --base-url on this host names.
  _demo_engine_city || return 1
  if [ -n "$base" ] && _demo_engine_loopback "$base"; then
    if [ -n "$serve_dir" ]; then
      _demo_engine_say "--base-url $base and --serve-dir each name an app to capture; give one"
      return 1
    fi
    open=$(_demo_engine_local_port "$base") || return 1
  fi
  if [ -n "$serve_dir" ]; then
    if [ -z "$port" ]; then
      open=$(_demo_engine_free_port) || { _demo_engine_say "could not find a free port for the --serve-dir server"; return 1; }
      args+=(--port "$open")
    else
      open="$port"
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

  if [ -n "${DEMO_ENGINE_BIN:-}" ]; then
    set -- "$DEMO_ENGINE_BIN"
  elif [ -n "${DEMO_ENGINE_DIR:-}" ]; then
    set -- node "$DEMO_ENGINE_DIR/src/cli.ts"
  else
    set -- npx --yes "$DEMO_ENGINE_PACKAGE"
  fi
  _demo_engine_sandbox_run "$open" "$cand" "$files" "$@" ${args[@]+"${args[@]}"}
}

demo_engine_sandboxed() {
  local port="${1:-}" dir="${2:-}"
  [ $# -ge 3 ] || { _demo_engine_say "demo_engine_sandboxed needs a port, a directory and a command"; return 1; }
  shift 2
  _demo_engine_sandbox_ok || return 1
  case "$port" in
    ''|*[!0-9]*|0*|??????*) _demo_engine_say "'$port' is not a port from 1 to 65535"; return 1 ;;
  esac
  [ "$port" -le 65535 ] || { _demo_engine_say "'$port' is not a port from 1 to 65535"; return 1; }
  [ -d "$dir" ] || { _demo_engine_say "'$dir' is not a directory"; return 1; }
  _demo_engine_city || return 1
  _demo_engine_sandbox_run "$port" "$(pwd -P)
$dir" "" "$@"
}

# _demo_engine_sandbox_run <port> <dirs> <files> <command...>: after
# _demo_engine_city, runs the command inside the sandbox, in the caller's
# working directory, with the port, when one is given, the one loopback port it
# may reach. Each of <dirs>, one per line, is read and written as
# _demo_engine_reach widens it, each of <files> is read, and the engine
# checkout, when one was chosen, is read. Returns the command's exit status, or
# 1, having said why, when the run is refused.
_demo_engine_sandbox_run() {
  local NL='
' open="$1" cand="$2" files="$3" places rw="" ro="" p d reach kind engine="" profile v
  local -a unsets
  shift 3

  # The city's directories, and each directory the run reads and writes, as
  # _demo_engine_reach widens it.
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
  # The Unix socket rules come first. Written after a loopback port's allow, the
  # deny on Unix sockets takes that allow back for most ports, over IPv4 and IPv6.
  profile="$profile$NL(deny network-outbound (remote unix-socket))"
  profile="$profile$NL(allow network-outbound (remote unix-socket (path-literal \"/private/var/run/mDNSResponder\")))"
  profile="$profile$NL(deny network-outbound (remote ip \"localhost:*\"))"
  [ -z "$open" ] || profile="$profile$NL(allow network-outbound (remote ip \"localhost:$open\"))"
  profile="$profile$NL(deny signal)$NL(allow signal (target same-sandbox))"

  unsets=()
  while IFS= read -r v; do
    [ -z "$v" ] || unsets+=(-u "$v")
  done < <(env | sed -n -E 's/^((GC|GT|BEADS|BD|DOLT)_[A-Za-z0-9_]*|TMUX|TMUX_PANE)=.*/\1/p')
  env ${unsets[@]+"${unsets[@]}"} sandbox-exec -p "$profile" "$@"
}

# The gctk binary that runs a copy: $GCTK_BIN, else the city's build.
_demo_engine_gctk() { printf '%s\n' "${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"; }

demo_engine_copy() {
  local dir="${1:-}" command="${2:-}" gctk rep state port
  DEMO_ENGINE_COPY_URL=""; DEMO_ENGINE_COPY_STOP=""
  gctk=$(_demo_engine_gctk)
  [ -x "$gctk" ] || { _demo_engine_say "no gctk binary at $gctk, which runs the copy a capture serves the app as; the gctk-build order publishes it, or set GCTK_BIN"; return 1; }
  [ -d "$dir" ] || { _demo_engine_say "'$dir' is not a directory to serve the app from"; return 1; }
  _demo_engine_say "serving the app from $dir as a copy (gctk rig serve), which runs inside the sandbox"
  rep=$(cd "$dir" && GCTK_SCRIPTS_DIR="$DEMO_ENGINE_LIB_DIR" "$gctk" rig serve --command "$command")
  state=$(printf '%s' "$rep" | jq -r '.state // empty' 2>/dev/null)
  if [ "$state" != running ]; then
    _demo_engine_say "the app's copy did not start: $(printf '%s' "$rep" | jq -r '"\(.reason // "no reason"): \(.detail // "gctk rig serve answered nothing jq could read")"' 2>/dev/null)"
    return 1
  fi
  # Whose the copy is comes from the start's own report. A copy it ran is this
  # capture's to stop, and one it found running belongs to whoever started it,
  # so it keeps running after the capture. The start refuses a copy that runs
  # another command, which would show another app.
  if [ "$(printf '%s' "$rep" | jq -r '.started // false' 2>/dev/null)" = true ]; then
    DEMO_ENGINE_COPY_STOP=$dir
  else
    _demo_engine_say "a copy (gctk rig serve) of this command already runs from $dir, so the capture takes it and leaves it running"
  fi
  port=$(printf '%s' "$rep" | jq -r '.port // empty' 2>/dev/null)
  case "$port" in
    ''|*[!0-9]*) _demo_engine_say "gctk rig serve reported no port for the app's copy"; return 1 ;;
  esac
  # shellcheck disable=SC2034 # the capture that sourced this file reads it
  DEMO_ENGINE_COPY_URL="http://127.0.0.1:$port/"
}

demo_engine_copy_stop() {
  [ -n "${DEMO_ENGINE_COPY_STOP:-}" ] || return 0
  ( cd "$DEMO_ENGINE_COPY_STOP" && "$(_demo_engine_gctk)" rig serve --stop >/dev/null )
  DEMO_ENGINE_COPY_STOP=""
}
