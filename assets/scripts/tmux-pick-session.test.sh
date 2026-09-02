#!/usr/bin/env bash
# Test for tmux-pick-session.sh — the `prefix + S` session picker (tk-5xy1wp).
#
# HERMETIC only. The picker's classification block is pure data-in, data-out:
# a tmux session roster goes in, a display-menu argv comes out. The suite
# drives the REAL script with `tmux` stubbed on PATH, serving a fixture
# roster and capturing the display-menu it assembles — so the derivation,
# the default filter, the display column and the shell-side header text are
# all asserted against what an operator would actually see, not against a
# re-implementation of the awk.
#
# Two runs, because the picker classifies two ways. The first leaves
# GC_CITY_PATH and friends unset, which makes gc_city_name return empty, so
# no cache is keyed and no roles resolve: that is the no-roles path, where
# the picker knows nothing about any session's role. The second points
# GC_HOME and GC_CITY_PATH at throwaway paths, primes the role cache through
# the script's own `--refresh-cache` against a stubbed `curl`, and renders
# from it: that is the live path, where the agent template names the role.
# The SUT is copied to a private dir so its
# `$(dirname $0)/tmux-keeper-toggle.sh` sibling does not resolve to the live
# one, and GC_PICKER_CACHE_DIR keeps the cache out of the operator's.
#
# What each case pins:
#
#   (SLASHED)  a named session's GC_AGENT is a qualified address
#              ("gascity/gc-toolkit.refinery"). Rig and display both come
#              from it.
#   (POOL)     a pool instance carries its own tmux session name in GC_AGENT
#              ("gc-toolkit--gc-toolkit__polecat-1-pool", from
#              template_resolve.go) rather than an address, and the GC_ALIAS
#              beside it arrives empty in tmux's env. That value is non-empty
#              and slashless, so it satisfies the session-name rule and the
#              slashless-GC_AGENT rule at once. The session-name rule has to
#              be tried first, or a pool worker files under a rig named for
#              no rig at all.
#   (CITYNAMED) `gc-toolkit__deacon` carries "gc-toolkit.deacon", which is
#              slashless, and its session name has no "--". It reads "city".
#              That is what the slashless rule is for, so a derivation that
#              sent every slashless agent through the session name would
#              strand it.
#   (MANUAL)   a hand-made session with no GC_AGENT and no "--" falls to the
#              last rule: rig "city", display the raw session name.
#   (MANUALSEP) a hand-made session that DOES carry "--" takes rule 2 like
#              any other: the rig column and the display column never repeat
#              the same rig.
#   (NOROLES)  with nothing to answer the role question, nothing is a
#              worker: every pool slot stays visible and every count reads
#              zero. Showing too much is recoverable and a wrong grouping is
#              not — a hidden converse is a conversation the operator cannot
#              reach from the menu at all.
#   (MARKER)   and the menu title says so, because a menu that groups
#              nothing looks the same as a city running no workers.
#   (ALL)      --all is the escape hatch: everything hidden by default is
#              reachable, and the pool rows carry the parsed display form
#              there too.
#   (SWITCH)   the display column is label-only. Whatever the rows say,
#              `switch-client -t` must still target the RAW tmux session
#              name, or a prettier label becomes an unattachable row.
#
# On the live path:
#
#   (CODEX)    a codex polecat takes a character name from the pack and
#              carries the character address in GC_AGENT, so neither field
#              names its role. The template does, and it folds into the
#              count like any other polecat.
#   (CONVERSE) a converse runs on a pool slot, and a slot is a scheduling
#              fact. It holds a conversation an operator goes to, so it is
#              never folded away. The same assertion pins the null title:
#              a converse row whose API title is null must render no title
#              at all, not the string "null".
#   (POOLED)   the rule read the other way. A pooled refinery is a refinery,
#              and the polecat family is the whole of the worker set.
#   (UNCOVERED) a session the supervisor does not answer for has no role,
#              and no role means shown and uncounted — per session, not per
#              run, so one uncovered row cannot ungroup the rest.
#   (HEADER)   a rig whose every session is folded away still gets its
#              header. The picker is topology awareness, and a rig that
#              vanishes when its polecats are hidden reports the wrong
#              topology.
#   (NOUN)     the header says what it counts, and what it counts is
#              polecats. "Pool worker" is the runtime word for any pool
#              instance, a converse included, so it cannot be the word for
#              a count a converse is deliberately absent from.
#   (TITLE)    template and title ride one API row through one call, so the
#              title column has to survive the widened projection.
#
# On the cache itself:
#
#   (NOFETCH)  the keypress reads the file and makes no API call. That is
#              the whole point of the cache: the call costs one to two
#              seconds on an idle city and several on a busy one, so in
#              front of an operator it is a visible delay that turns into a
#              timeout under the load that makes the roster worth checking.
#   (FRESH)    a map as young as the last keypress carries no marker.
#   (STALE)    an old one does, with its age, because the counts and the
#              folding are that old too.
#   (REFRESH)  --refresh-cache writes the projected map, so what the picker
#              renders from is what a real refresh produced.
#   (KEEPLAST) a failed fetch keeps the last good map. An unreachable
#              supervisor is not evidence that the city has no sessions, and
#              an empty map ungroups every rig at once.
#   (THROTTLE) a failed fetch is still an attempt, and the throttle counts
#              attempts. Counting successes leaves a slow supervisor — the
#              one case where overlapping fetches cost anything — throttled
#              by nothing at all.
#   (DETACH)   the refresh does not hold the keypress open. The binding is a
#              foreground `run-shell` and tmux reads the child's stdout to
#              EOF, so a fetch that inherits it stalls the menu for exactly
#              the time the cache exists to avoid.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/tmux-pick-session.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()  { [[ "$1" == *"$2"* ]] && ok "$3" || bad "$3 (missing '$2')"; }
hasnt() { [[ "$1" == *"$2"* ]] && bad "$3 (found '$2')" || ok "$3"; }

[ -f "$SRC" ] && ok "tmux-pick-session.sh present" || { bad "missing at $SRC"; exit 1; }
[ -x "$SRC" ] && ok "tmux-pick-session.sh executable" || bad "tmux-pick-session.sh not executable"

# Private copy: $0-relative sibling lookup (tmux-keeper-toggle.sh) must not
# reach the live tree and run against the operator's real city.
SUT_DIR="$TMP/scripts"; mkdir -p "$SUT_DIR"
cp "$SRC" "$SUT_DIR/"; chmod +x "$SUT_DIR/tmux-pick-session.sh"
SUT="$SUT_DIR/tmux-pick-session.sh"

BIN="$TMP/bin"; mkdir -p "$BIN"
export STUB_SESSIONS="$TMP/sessions.txt"
export STUB_MENU="$TMP/menu.txt"
export STUB_ACTIVE=""
# The role cache lives under TMP for the whole suite: a run that wrote the
# operator's cache would leave a fixture roster behind for their next
# keypress, and a run that read it would classify against a live city.
export GC_PICKER_CACHE_DIR="$TMP/cache"
export CURL_LOG="$TMP/curl.log"
: > "$CURL_LOG"

# tmux stub. Serves the fixture roster, an empty pane list (no sub-rows to
# assert here) and an empty client_session, and dumps the display-menu argv
# one argument per line — labels contain spaces and box-drawing characters,
# so one-per-line is the only unambiguous dump.
cat > "$BIN/tmux" <<'STUB'
#!/usr/bin/env bash
set -u
while [ $# -gt 0 ] && [ "$1" = "-L" ]; do shift 2; done
case "${1:-}" in
    display-message) printf '%s\n' "${STUB_ACTIVE:-}" ;;
    list-panes)      : ;;
    list-sessions)   cat "${STUB_SESSIONS:?}" ;;
    display-menu)    shift; printf '%s\n' "$@" > "${STUB_MENU:?}" ;;
    *)               exit 1 ;;
esac
STUB
chmod +x "$BIN/tmux"
export PATH="$BIN:$PATH"

# The fixture roster: every derivation shape, plus the pool/named pair that
# FOLD and KEEPNAMED turn on. Fields mirror the script's -F format:
# name|attached|windows|GC_AGENT.
cat > "$STUB_SESSIONS" <<'ROSTER'
gascity--gc-toolkit__refinery|0|1|gascity/gc-toolkit.refinery
gascity--gc-toolkit__refinery-1-pool|0|1|gascity--gc-toolkit__refinery-1-pool
gc-toolkit--gc-toolkit__converse-1-pool|0|1|gc-toolkit--gc-toolkit__converse-1-pool
gc-toolkit--gc-toolkit__hicks|0|1|gc-toolkit/gc-toolkit.hicks
gc-toolkit--gc-toolkit__polecat-1-pool|0|1|gc-toolkit--gc-toolkit__polecat-1-pool
gc-toolkit--gc-toolkit__polecat-2-pool|0|1|gc-toolkit--gc-toolkit__polecat-2-pool
gc-toolkit--gc-toolkit__refinery|0|1|gc-toolkit/gc-toolkit.refinery
gc-toolkit--gc-toolkit__ripley|0|1|gc-toolkit/gc-toolkit.ripley
gc-toolkit__deacon|0|1|gc-toolkit.deacon
oversight--gc-toolkit__polecat-1-pool|0|1|oversight--gc-toolkit__polecat-1-pool
signal-loom--gc-toolkit__refinery-1-pool|0|1|signal-loom--gc-toolkit__refinery-1-pool
scratch|0|1|
ops--notebook|0|1|
ops--polecat-9-pool|0|1|
ROSTER

# Run the picker with no city resolvable (no cache key, so no roles) and no
# inherited tmux socket, and return the captured menu.
run_picker() {
    : > "$STUB_MENU"
    env -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT -u GC_TMUX_SOCKET -u GC_AGENT \
        "$SUT" "$@" >/dev/null 2>&1
    cat "$STUB_MENU"
}

# The API fixture the curl stub serves. Templates for everything the
# supervisor knows; ops--notebook and ops--polecat-9-pool are absent from it
# on purpose, and `scratch` carries neither key.
cat > "$TMP/api.json" <<'API'
{"items": [
  {"session_name": "gascity--gc-toolkit__refinery",            "template": "gascity/gc-toolkit.refinery",         "title": ""},
  {"session_name": "gascity--gc-toolkit__refinery-1-pool",     "template": "gascity/gc-toolkit.refinery",         "title": "gascity/gc-toolkit.refinery-1"},
  {"session_name": "gc-toolkit--gc-toolkit__converse-1-pool",  "template": "gc-toolkit/gc-toolkit.converse",      "title": null},
  {"session_name": "gc-toolkit--gc-toolkit__hicks",            "template": "gc-toolkit/gc-toolkit.polecat-codex", "title": ""},
  {"session_name": "gc-toolkit--gc-toolkit__polecat-1-pool",   "template": "gc-toolkit/gc-toolkit.polecat",       "title": ""},
  {"session_name": "gc-toolkit--gc-toolkit__polecat-2-pool",   "template": "gc-toolkit/gc-toolkit.polecat",       "title": ""},
  {"session_name": "gc-toolkit--gc-toolkit__refinery",         "template": "gc-toolkit/gc-toolkit.refinery",      "title": "landing PR #497"},
  {"session_name": "gc-toolkit--gc-toolkit__ripley",           "template": "gc-toolkit/gc-toolkit.polecat-codex", "title": ""},
  {"session_name": "gc-toolkit__deacon",                       "template": "gc-toolkit.deacon",                   "title": ""},
  {"session_name": "oversight--gc-toolkit__polecat-1-pool",    "template": "oversight/gc-toolkit.polecat",        "title": ""},
  {"session_name": "signal-loom--gc-toolkit__refinery-1-pool", "template": "signal-loom/gc-toolkit.refinery",     "title": ""},
  {"session_name": "scratch"}
]}
API

# curl stub, not a mocked fetch: the real jq projection is part of what is
# under test. No STUB_API in the environment exits like a failed connection.
# Every call is logged, so a run can assert what it did NOT fetch, and
# STUB_SLOW makes a fetch outlast the keypress that spawned it.
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
set -u
if [ -n "${CURL_LOG:-}" ]; then printf 'call\n' >> "$CURL_LOG"; fi
if [ -n "${STUB_SLOW:-}" ]; then sleep "$STUB_SLOW"; fi
if [ ! -f "${STUB_API:-/nonexistent}" ]; then exit 7; fi
cat "$STUB_API"
STUB
chmod +x "$BIN/curl"

# GC_HOME has no cities.toml, so gc_city_name falls through to the basename
# of GC_CITY_PATH and the API URL resolves without touching the operator's
# config. curl is stubbed, so the URL itself never leaves the process.
picker_env() {
    env -u GC_CITY -u GC_CITY_ROOT -u GC_TMUX_SOCKET -u GC_AGENT \
        GC_HOME="$TMP/gchome" GC_CITY_PATH="$TMP/testcity" "$@"
}

# Prime the cache through the script's own refresh mode, which is the same
# code the detached background fetch runs — the suite renders from what a
# real refresh writes, not from a hand-built file.
prime_cache() {
    picker_env STUB_API="${1:-$TMP/api.json}" "$SUT" --refresh-cache >/dev/null 2>&1
}

# Render from the primed cache with the API unreachable, and with the refresh
# throttle set past any test run so no background fetch fires: what the curl
# log holds afterwards is exactly what the keypress itself did.
run_picker_api() {
    : > "$STUB_MENU"; : > "$CURL_LOG"
    picker_env GC_PICKER_REFRESH_EVERY=999999 "$SUT" "$@" >/dev/null 2>&1
    cat "$STUB_MENU"
}

prime_cache
# The cache path is keyed by city inside the script; the suite finds the file
# it wrote rather than recomputing the key and testing its own arithmetic.
ROLES_CACHE="$(set -- "$TMP/cache"/roles-*.cache; printf '%s' "$1")"

MENU="$(run_picker)"
ALLMENU="$(run_picker --all)"
APIMENU="$(run_picker_api)"
APIALL="$(run_picker_api --all)"

[ -n "$MENU" ] && ok "default run produced a menu" || { bad "default run produced no menu"; echo "$MENU"; }

# label_for <menu> <session-name> — the menu label whose action targets that
# raw tmux session. The dump is label/key/command triples, so the label is two
# lines above its command. Keyed on the RAW name because that is the only
# unique handle: two rigs can run the same <pack>.<role>, and the whole point
# of the derivation is that the display column is not the session name.
label_for() {
    printf '%s\n' "$1" | awk -v want="switch-client -t $2" '
        $0 == want { print p2; exit } { p2 = p1; p1 = $0 }'
}
# The two derived columns, pinned exactly rather than by substring. A display
# that merely CONTAINS the right text, carrying an unstripped "<rig>--" prefix
# in front of it, is still the wrong display, and a substring assertion passes
# it.
rig_col()  { printf '%s' "$1" | sed -e 's/^ *\[//' -e 's/\].*//'; }
disp_col() { printf '%s' "$1" | sed -e 's/[[:space:]]*$//' -e 's/.*  //'; }
# derives <menu> <session-name> — "<rig>|<display>", the whole derivation.
derives() { local l; l="$(label_for "$1" "$2")"; printf '%s|%s' "$(rig_col "$l")" "$(disp_col "$l")"; }

# --- derivation ------------------------------------------------------------
eq "$(derives "$MENU" 'gc-toolkit--gc-toolkit__refinery')" 'gc-toolkit|gc-toolkit.refinery' \
    "SLASHED: rig and display both come from the qualified GC_AGENT"
eq "$(derives "$MENU" 'gascity--gc-toolkit__refinery')" 'gascity|gc-toolkit.refinery' \
    "SLASHED: the same <pack>.<role> in two rigs files under each"

eq "$(derives "$ALLMENU" 'gc-toolkit--gc-toolkit__polecat-1-pool')" \
   'gc-toolkit|gc-toolkit.polecat-1-pool' \
    "POOL: a pool instance derives exactly like the named session beside it"
eq "$(derives "$ALLMENU" 'gascity--gc-toolkit__refinery-1-pool')" \
   'gascity|gc-toolkit.refinery-1-pool' \
    "POOL: rig comes from the session name, not the slashless GC_AGENT"
eq "$(derives "$ALLMENU" 'gc-toolkit--gc-toolkit__converse-1-pool')" \
   'gc-toolkit|gc-toolkit.converse-1-pool' \
    "POOL: every pooled role derives the same way, not just polecat"

# The deacon is hidden by the default filter, so this reads the --all menu.
eq "$(derives "$ALLMENU" 'gc-toolkit__deacon')" 'city|gc-toolkit.deacon' \
    "CITYNAMED: slashless GC_AGENT with no '--' still reads city"

eq "$(derives "$MENU" 'scratch')" 'city|scratch' \
    "MANUAL: empty GC_AGENT with no '--' reads city, display is the raw name"

eq "$(derives "$MENU" 'ops--notebook')" 'ops|notebook' \
    "MANUALSEP: empty GC_AGENT with '--' takes the rig from the name"

# --- display form ----------------------------------------------------------
hasnt "$ALLMENU" 'gc-toolkit--gc-toolkit__polecat-1-pool  ' \
    "POOL: the raw session name never reaches the display column"

# --- no roles: nothing is a worker -----------------------------------------
has "$MENU" 'converse-1-pool' \
    "NOROLES: a converse on a pool slot is not guessed into a worker"
has "$MENU" 'refinery-1-pool' \
    "NOROLES: nor is a pooled refinery"
has "$MENU" 'polecat-1-pool' \
    "NOROLES: nor is the polecat the name would have been right about"
has "$MENU" '── gc-toolkit ──' \
    "NOROLES: the header renders with no count rather than a guessed one"
hasnt "$MENU" 'polecat ──' \
    "NOROLES: ...and no rig claims a worker"
hasnt "$MENU" 'pool worker' \
    "NOUN: the count is polecats, and every pool instance is a pool worker"
has "$MENU" ' Sessions ▫ no roles ' \
    "MARKER: an ungrouped menu says it is ungrouped"

has "$ALLMENU" 'converse-1-pool' "ALL: --all reveals converse-N-pool"
has "$ALLMENU" 'refinery-1-pool' "ALL: --all reveals refinery-N-pool"
has "$ALLMENU" 'gc-toolkit.deacon' "ALL: --all reveals the name-hidden roles"
hasnt "$MENU" 'gc-toolkit.deacon' \
    "NOROLES: the name-based hides are a separate rule and still apply"

# --- template classification (live path) -----------------------------------
hasnt "$APIMENU" 'gc-toolkit.hicks' \
    "CODEX: a codex polecat under a character name is folded away"
hasnt "$APIMENU" 'gc-toolkit.ripley' \
    "CODEX: ...and so is the second one"
eq "$(derives "$APIALL" 'gc-toolkit--gc-toolkit__hicks')" 'gc-toolkit|gc-toolkit.hicks' \
    "CODEX: --all still reaches it, derived from the character address"
# gc-toolkit runs polecat-1-pool + polecat-2-pool + hicks + ripley = 4, and
# the converse that the suffix rule counted is gone from the total.
has "$APIMENU" '── gc-toolkit • 4 polecats ──' \
    "CODEX: the count is the polecat family, and only the polecat family"

eq "$(derives "$APIMENU" 'gc-toolkit--gc-toolkit__converse-1-pool')" \
   'gc-toolkit|gc-toolkit.converse-1-pool' \
    "CONVERSE: a converse on a pool slot stays a visible row, with no title"

eq "$(derives "$APIMENU" 'gascity--gc-toolkit__refinery-1-pool')" \
   'gascity|gc-toolkit.refinery-1-pool' \
    "POOLED: a pooled refinery is a refinery, not a worker"
# Its API title is the instance alias, which is the display column said
# twice. The rows this change stops hiding must not arrive carrying it.
hasnt "$APIMENU" 'gc-toolkit.refinery-1  ' \
    "POOLED: ...and the alias-shaped title is suppressed, not rendered"
has "$APIMENU" '── gascity ──' \
    "POOLED: ...so gascity counts no polecats and its header carries no count"

eq "$(derives "$APIMENU" 'scratch')" 'city|scratch' \
    "UNCOVERED: an API row with no template at all resolves no role"
has "$APIMENU" 'polecat-9-pool' \
    "UNCOVERED: a session the API never mentions is shown, not guessed at"
has "$APIMENU" '── ops ──' \
    "UNCOVERED: ...and is counted under no rig"
has "$APIMENU" '── oversight • 1 polecat ──' \
    "NOUN: singular form, and the noun names what is counted"
hasnt "$APIMENU" '[oversight]' \
    "HEADER: the rig's every session is folded, and its header still renders"

has "$APIMENU" '│ landing PR #497' \
    "TITLE: the title column survives the widened projection"

# --- switch target ---------------------------------------------------------
has "$ALLMENU" 'switch-client -t gc-toolkit--gc-toolkit__polecat-1-pool' \
    "SWITCH: the command still targets the raw tmux session name"

# --- the cache -------------------------------------------------------------
# APIMENU above was rendered with the API unreachable and the refresh
# throttled off, so its curl log is the keypress's own record.
eq "$(wc -l < "$CURL_LOG" | tr -d ' ')" '0' \
    "NOFETCH: rendering the menu makes no supervisor API call"
[ -s "$ROLES_CACHE" ] && ok "REFRESH: --refresh-cache wrote the role map" \
    || bad "REFRESH: --refresh-cache wrote no role map"
has "$(cat "$ROLES_CACHE")" 'gc-toolkit/gc-toolkit.polecat-codex' \
    "REFRESH: ...projected to <name>\\t<template>\\t<title>"

hasnt "$APIMENU" '▫' \
    "FRESH: a map as young as the last keypress carries no marker"

# Backdate the file the picker reads: staleness is the cache's mtime, and
# nothing else in the run has to move to make the map old.
touch -d "@$(( $(date +%s) - 3700 ))" "$ROLES_CACHE"
STALEMENU="$(run_picker_api)"
has "$STALEMENU" ' Sessions ▫ roles 1h old ' \
    "STALE: an old map is marked, with its age"
has "$STALEMENU" '── gc-toolkit • 4 polecats ──' \
    "STALE: ...and is still what the menu groups by, marker or not"

# A refresh that cannot reach the API must not blank the map it has.
BEFORE="$(cat "$ROLES_CACHE")"
rm -f "$ROLES_CACHE.attempt"
prime_cache "$TMP/nonexistent.json"
eq "$(cat "$ROLES_CACHE")" "$BEFORE" \
    "KEEPLAST: a failed fetch leaves the last good map in place"
[ -f "$ROLES_CACHE.attempt" ] \
    && ok "THROTTLE: ...and still records the attempt the throttle counts" \
    || bad "THROTTLE: a failed fetch recorded no attempt"

# The binding is a foreground `run-shell`, and tmux reads the child's stdout
# to EOF. Command substitution reads the same way, so a refresh that keeps
# the descriptor holds this line open for as long as the fetch runs.
DETACH_T0=$(date +%s)
DETACH_OUT="$(picker_env STUB_API="$TMP/api.json" STUB_SLOW=10 \
    GC_PICKER_REFRESH_EVERY=0 CURL_LOG="" "$SUT" 2>/dev/null)"
DETACH_ELAPSED=$(( $(date +%s) - DETACH_T0 ))
[ "$DETACH_ELAPSED" -lt 5 ] \
    && ok "DETACH: a slow refresh does not hold the keypress open" \
    || bad "DETACH: the keypress waited ${DETACH_ELAPSED}s on the background fetch"
eq "$DETACH_OUT" '' "DETACH: ...and the picker writes nothing to stdout itself"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
