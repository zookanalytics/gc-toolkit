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
# No live city: GC_CITY_PATH and friends are unset, which makes gc_city_name
# return empty and skips the supervisor API call entirely. The SUT is copied
# to a private dir so its `$(dirname $0)/tmux-keeper-toggle.sh` sibling does
# not resolve to the live one.
#
# What the cases are guarding, and why each was worth a test:
#
#   (SLASHED)  a named session's GC_AGENT is a qualified address
#              ("gascity/gc-toolkit.refinery"). Rig and display both come
#              from it. This is the shape that always worked and the control
#              for the other three.
#   (POOL)     THE defect. A pool instance carries its own tmux session name
#              in GC_AGENT ("gc-toolkit--gc-toolkit__polecat-1-pool", from
#              template_resolve.go) rather than an address, and GC_ALIAS
#              beside it arrives empty in tmux's env. That value is non-empty
#              and slashless, so the old branch order filed EVERY pool worker
#              under a synthetic "city" rig before the session-name branch
#              could run. Three live polecats under a rig that does not exist.
#   (CITYNAMED) the reason the slashless branch exists at all, and what makes
#              this a reorder rather than a deletion. `gc-toolkit__deacon`
#              carries "gc-toolkit.deacon" — slashless, and its session name
#              has no "--" — so it must still read "city". A fix that routes
#              all slashless agents through the name would strand it.
#   (MANUAL)   a hand-made session with no GC_AGENT and no "--" falls to the
#              last rule: rig "city", display the raw session name.
#   (MANUALSEP) a hand-made session that DOES carry "--" takes rule 2 like
#              any other: the rig column and the display column never repeat
#              the same rig.
#   (COUNT)    the per-rig header counts the workers running in THAT rig.
#              The count and the rig derivation share `rig`, so the phantom
#              "city" took the polecats with it and every real rig read 0.
#   (FOLD)     converse-N-pool and refinery-N-pool are pool workers with the
#              same short lifetime as a polecat. The default filter used to
#              enumerate role substrings, so it missed both — they rendered
#              as attachable rows and went uncounted. The suffix is the
#              general shape; the role name is not.
#   (KEEPNAMED) the other half of FOLD, and what stops the suffix rule from
#              swallowing the long-lived sessions: `<rig>--<pack>__refinery`
#              is a named refinery, not a pool instance, and must stay
#              visible next to the `refinery-1-pool` that is hidden.
#   (NOUN)     the header says what it counts. It read "polecats" while
#              counting a set that now includes converse and refinery pools.
#   (ALL)      --all is the escape hatch: everything hidden by default is
#              reachable, and the pool rows carry the parsed display form
#              there too.
#   (SWITCH)   the display column is label-only. Whatever the rows say,
#              `switch-client -t` must still target the RAW tmux session
#              name, or a prettier label becomes an unattachable row.
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
gc-toolkit--gc-toolkit__polecat-1-pool|0|1|gc-toolkit--gc-toolkit__polecat-1-pool
gc-toolkit--gc-toolkit__polecat-2-pool|0|1|gc-toolkit--gc-toolkit__polecat-2-pool
gc-toolkit--gc-toolkit__refinery|0|1|gc-toolkit/gc-toolkit.refinery
gc-toolkit__deacon|0|1|gc-toolkit.deacon
signal-loom--gc-toolkit__refinery-1-pool|0|1|signal-loom--gc-toolkit__refinery-1-pool
scratch|0|1|
ops--notebook|0|1|
ROSTER

# Run the picker with no city resolvable (no supervisor API call) and no
# inherited tmux socket, and return the captured menu.
run_picker() {
    : > "$STUB_MENU"
    env -u GC_CITY_PATH -u GC_CITY -u GC_CITY_ROOT -u GC_TMUX_SOCKET -u GC_AGENT \
        "$SUT" "$@" >/dev/null 2>&1
    cat "$STUB_MENU"
}

MENU="$(run_picker)"
ALLMENU="$(run_picker --all)"

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
# The two derived columns, pinned exactly rather than by substring: a display
# that merely CONTAINS the right text (an unstripped "<rig>--" prefix in front
# of it) is the defect one layer over, and a substring assertion passes it.
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
# gc-toolkit runs converse-1-pool + polecat-1-pool + polecat-2-pool = 3.
has "$MENU" '── gc-toolkit • 3 pool workers ──' \
    "COUNT: per-rig header counts the workers in that rig"
# gascity runs refinery-1-pool = 1.
has "$MENU" '── gascity • 1 pool worker ──' \
    "NOUN: singular form, and the noun names what is counted"
hasnt "$MENU" 'polecats ──' \
    "NOUN: header no longer claims to count polecats"
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
has "$MENU" '── signal-loom • 1 pool worker ──' \
    "KEEPNAMED: a rig whose only session is hidden still gets its header"
hasnt "$MENU" '[signal-loom]' \
    "KEEPNAMED: ...and that header is the rig's only row"

has "$ALLMENU" 'converse-1-pool' "ALL: --all reveals converse-N-pool"
has "$ALLMENU" 'refinery-1-pool' "ALL: --all reveals refinery-N-pool"

# --- switch target ---------------------------------------------------------
has "$ALLMENU" 'switch-client -t gc-toolkit--gc-toolkit__polecat-1-pool' \
    "SWITCH: the command still targets the raw tmux session name"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
