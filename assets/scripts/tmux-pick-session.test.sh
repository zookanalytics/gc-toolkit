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
# GC_CITY_PATH and friends unset, which makes gc_city_name return empty and
# skips the supervisor API call entirely: that is the degraded path, where
# the session-name shape is all the picker has. The second points GC_HOME
# and GC_CITY_PATH at throwaway paths and stubs `curl` with a fixture
# roster: that is the live path, where the agent template names the role.
# The SUT is copied to a private dir so its
# `$(dirname $0)/tmux-keeper-toggle.sh` sibling does not resolve to the live
# one.
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
#   (COUNT)    the per-rig header counts the workers running in THAT rig.
#              The count and the rig derivation share `rig`, so a row that
#              derives the wrong rig is also counted under the wrong header.
#   (FOLD)     with nothing to answer the role question, every "-<n>-pool"
#              session is taken for a polecat: hidden, and counted. Keeping
#              that fallback rather than showing everything is deliberate.
#              A rig of thirty polecats must not flood the menu because one
#              curl timed out.
#   (KEEPNAMED) the bound on the suffix rule: `<rig>--<pack>__refinery` is a
#              named refinery, not a pool instance, and stays visible beside
#              the `refinery-1-pool` that is hidden.
#   (NOUN)     the header says what it counts, and what it counts is
#              polecats. "Pool worker" is the runtime word for any pool
#              instance, a converse included, so it cannot be the word for
#              a count a converse is deliberately absent from.
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
#   (UNKNOWN)  a session the supervisor does not answer for falls back to
#              the name shape per session, not per run.
#   (TITLE)    template and title ride one API row through one call, so the
#              title column has to survive the widened projection.
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
signal-loom--gc-toolkit__refinery-1-pool|0|1|signal-loom--gc-toolkit__refinery-1-pool
scratch|0|1|
ops--notebook|0|1|
ops--polecat-9-pool|0|1|
ROSTER

# Run the picker with no city resolvable (no supervisor API call) and no
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
  {"session_name": "signal-loom--gc-toolkit__refinery-1-pool", "template": "signal-loom/gc-toolkit.refinery",     "title": ""},
  {"session_name": "scratch"}
]}
API

# curl stub, not a mocked fetch: the real jq projection is part of what is
# under test. No STUB_API in the environment exits like a failed connection,
# which is what the degraded path above sees.
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
set -u
[ -f "${STUB_API:-/nonexistent}" ] || exit 7
cat "$STUB_API"
STUB
chmod +x "$BIN/curl"

# GC_HOME has no cities.toml, so gc_city_name falls through to the basename
# of GC_CITY_PATH and the API URL resolves without touching the operator's
# config. curl is stubbed, so the URL itself never leaves the process.
run_picker_api() {
    : > "$STUB_MENU"
    env -u GC_CITY -u GC_CITY_ROOT -u GC_TMUX_SOCKET -u GC_AGENT \
        GC_HOME="$TMP/gchome" GC_CITY_PATH="$TMP/testcity" \
        STUB_API="$TMP/api.json" \
        "$SUT" "$@" >/dev/null 2>&1
    cat "$STUB_MENU"
}

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

# --- headers ---------------------------------------------------------------
# With no API, the suffix takes converse-1-pool for a polecat: it counts
# alongside polecat-1-pool and polecat-2-pool = 3.
has "$MENU" '── gc-toolkit • 3 polecats ──' \
    "COUNT: per-rig header counts the workers in that rig"
# gascity runs refinery-1-pool = 1.
has "$MENU" '── gascity • 1 polecat ──' \
    "NOUN: singular form, and the noun names what is counted"
hasnt "$MENU" 'pool worker' \
    "NOUN: the count is polecats, and every pool instance is a pool worker"
hasnt "$MENU" '── city • ' \
    "COUNT: city holds no workers"

# --- default filter --------------------------------------------------------
hasnt "$MENU" 'converse-1-pool' \
    "FOLD: converse-N-pool is hidden by default"
hasnt "$MENU" 'refinery-1-pool' \
    "FOLD: refinery-N-pool is hidden by default"
hasnt "$MENU" 'polecat-1-pool' \
    "FOLD: polecat-N-pool is hidden by default"
eq "$(derives "$MENU" 'gascity--gc-toolkit__refinery')" 'gascity|gc-toolkit.refinery' \
    "KEEPNAMED: the named refinery stays visible beside its hidden pool"
has "$MENU" '── signal-loom • 1 polecat ──' \
    "KEEPNAMED: a rig whose only session is hidden still gets its header"
hasnt "$MENU" '[signal-loom]' \
    "KEEPNAMED: ...and that header is the rig's only row"

has "$ALLMENU" 'converse-1-pool' "ALL: --all reveals converse-N-pool"
has "$ALLMENU" 'refinery-1-pool' "ALL: --all reveals refinery-N-pool"

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
    "UNKNOWN: an API row with no template at all falls back to the name shape"
hasnt "$APIMENU" 'polecat-9-pool' \
    "UNKNOWN: a session the API never mentions falls back too"
has "$APIMENU" '── ops • 1 polecat ──' \
    "UNKNOWN: ...and the fallback is per session, not per run"

has "$APIMENU" '│ landing PR #497' \
    "TITLE: the title column survives the widened projection"

# --- switch target ---------------------------------------------------------
has "$ALLMENU" 'switch-client -t gc-toolkit--gc-toolkit__polecat-1-pool' \
    "SWITCH: the command still targets the raw tmux session name"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
