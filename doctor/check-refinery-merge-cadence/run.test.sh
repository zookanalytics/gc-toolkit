#!/usr/bin/env bash
# Hermetic test for doctor/check-refinery-merge-cadence/run.sh — the merge-clock
# liveness detector. Stubs `gc` (order registry, rig roster, run history) and
# `ps` (process table) on PATH, and builds a throwaway pack dir. No live city,
# Dolt, network, or systemd.
#
# Covered:
#   (1)  every rig registered and fresh, no rogue driver -> OK (exit 0)
#   (2)  ONE rig stale while others are fresh -> ERROR (exit 2), names the rig
#        and says the controller is up  [the per-rig outage this check is for]
#   (3)  EVERY rig stale -> ERROR (exit 2) with the city-wide message, and the
#        cold-boot caveat, not four copies of the per-rig one
#   (4)  a rig importing this pack with NO refinery-reconcile registration ->
#        ERROR (exit 2), and says a disabled override looks identical
#   (5)  zero registrations city-wide -> ERROR (exit 2), "NOT REGISTERED"
#   (6)  live /tmp/gc-refinery-idle-<rig>/idle-loop.sh -> ERROR (exit 2), names
#        the rig and the retire command  [the second merge-skill.sh writer]
#   (7)  a process merely MENTIONING the driver — a tail on its log, a pager
#        open on idle-loop.sh itself, or a shell `-c` command string naming the
#        path — is NOT a driver -> not flagged. Arm 3 matches the shell's script
#        argument, not the path anywhere in the line, so reading the retired
#        script (quite possibly to confirm it is gone) does not get you reported
#        as a live second writer
#   (7b) the script exec'd directly, with no shell word, IS a driver -> flagged
#   (7c) one driver forking children with the same argv is ONE finding, not one
#        per process (the live driver showed up three times in `ps`)
#   (8)  suspended rig with no runs -> skipped, still exit 0, and said in a note
#   (9)  `gc order list` unreadable -> WARN (exit 1), never a silent OK
#   (10) `gc order history` unreadable -> WARN (exit 1); with a registration
#        error already found, ERROR (exit 2) and liveness declared undetermined
#   (11) `gc rig list` unreadable -> WARN, and the liveness arm still runs
#   (12) pack no longer ships orders/refinery-reconcile.toml -> WARN (exit 1),
#        never a green verdict about a subject that is gone
#   (13) the history read passes `--limit 0`  [LOAD-BEARING: any positive limit
#        makes `gc order history` answer for the city store alone, which is the
#        misread that produced the P1 this check came from]
#   (14) the history read is bounded by `--since` so the unbounded read stays cheap
#   (15) GC_DOCTOR_MERGE_CADENCE_WINDOW overrides the window
#   (16) a malformed window falls back to 15m rather than passing junk to `gc`
#   (17) a stale rig's message points at that rig's own pass.log and history
#   (18) a host whose only working `ps` form is the PID-prefixed `ps ax` still
#        reports a live driver. The snapshot is normalised to a command-only
#        column first; feeding `123 ? Ss 0:00 bash ...` to a first-WORD matcher
#        makes the arm structurally unable to fire  [green with a live driver]
#   (18b) that same fallback does not turn a mere reader into a driver — the
#        normalisation is precise, not just permissive
#   (18c) the same, on a `ps` whose COMMAND is preceded by THREE columns and not
#        four (busybox: PID USER TIME). A fixed-field strip eats the first word
#        of COMMAND here, turning a pager into a bare script path — which arm 3
#        reads as a driver. The strip anchors on the TIME column for this reason
#   (19) NO `ps` form works -> WARN (exit 1), never an OK whose summary claims
#        "no out-of-band driver" on evidence nobody gathered  [FAIL CLOSED]
#   (INV) detect-only: no fix.sh ships next to run.sh (a sibling fix.sh would
#        auto-opt this check into `gc doctor --fix`, and there is nothing here
#        to fix automatically — restarting a merge cadence is an operator act)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -qF -- "$1" "$2" && ok "$3" || bad "$3 (missing '$1' in $(cat "$2"))"; }
hasnt() { grep -qF -- "$1" "$2" && bad "$3 (unexpected '$1')" || ok "$3"; }

# ---------------------------------------------------------------------------
# Stubs. Every `gc` invocation is logged so a test can assert the exact flags
# the history read was made with.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
D="${GC_STUB_DIR:?}"
echo "$*" >> "$D/calls.log"
case "${1:-}:${2:-}" in
    order:list)    [ -f "$D/orders.json" ]  && { cat "$D/orders.json";  exit 0; }; exit 1 ;;
    order:history) [ -f "$D/history.json" ] && { cat "$D/history.json"; exit 0; }; exit 1 ;;
    rig:list)      [ -f "$D/rigs.json" ]    && { cat "$D/rigs.json";    exit 0; }; exit 1 ;;
esac
exit 1
STUB
# The `ps` stub is FORM-AWARE on purpose. run.sh matches the first WORD of each
# line, so what a given host's `ps` puts in column 1 decides whether the driver
# arm can fire at all. GC_STUB_PS_FORMS names the shapes this simulated host
# supports; anything else exits 1, the way a host without that flag would:
#   argsonly     -> `-eo args=` / `ax -o args=`: argv only, no header
#   pidprefixed  -> `ps ax`: header + PID TTY STAT TIME COMMAND
# Unset means both, which is what a real Linux host does.
cat > "$TMP/bin/ps" <<'STUB'
#!/usr/bin/env bash
D="${GC_STUB_DIR:?}"
forms="${GC_STUB_PS_FORMS-argsonly pidprefixed}"
case "$*" in
    *"args="*|*"command="*) want=argsonly ;;
    *)                      want=pidprefixed ;;
esac
case " $forms " in
    *" $want "*) ;;
    *) exit 1 ;;
esac
# A real `ps` always lists at least itself, so the baseline snapshot is one
# line even when the fixture adds none. run.sh reads a zero-row table as a
# failed read; a stub that returned nothing would be simulating something no
# host does.
emit() {
    echo "/usr/bin/ps $*"
    [ -f "$D/ps.txt" ] && cat "$D/ps.txt"
    return 0
}
if [ "$want" = pidprefixed ]; then
    # How many columns precede COMMAND is NOT fixed across implementations:
    # procps prints PID TTY STAT TIME, busybox prints PID USER TIME. Both are
    # simulated because a fixed-field strip silently mangles the other one.
    case "${GC_STUB_PS_COLUMNS-procps}" in
        busybox) echo "  PID USER     TIME COMMAND"; fmt='%5d root     0:00 %s\n' ;;
        *)       echo "  PID TTY      STAT   TIME COMMAND"; fmt='%5d ?        Ss     0:00 %s\n' ;;
    esac
    n=100
    emit "$@" | while IFS= read -r l; do
        [ -n "$l" ] || continue
        # shellcheck disable=SC2059 # fmt is a chosen literal, not user input
        printf "$fmt" "$n" "$l"
        n=$((n + 1))
    done
else
    emit "$@"
fi
exit 0
STUB
chmod +x "$TMP/bin/gc" "$TMP/bin/ps"
export PATH="$TMP/bin:$PATH"

# A throwaway pack dir carrying this pack's order names. refinery-reconcile is
# the subject; feedback-miner is what marks a rig as importing the pack.
PACK="$TMP/pack"
mkdir -p "$PACK/orders"
printf 'scope = "rig"\n' > "$PACK/orders/refinery-reconcile.toml"
printf 'scope = "rig"\n' > "$PACK/orders/feedback-miner.toml"

RIGS='{"rigs":[{"name":"loomington","suspended":false,"hq":true},
                {"name":"gascity","suspended":false,"hq":false},
                {"name":"gc-toolkit","suspended":false,"hq":false},
                {"name":"signal-loom","suspended":false,"hq":false}]}'

orders_for() { # rig...
    local out='{"orders":[' first=1 r
    for r in "$@"; do
        [ "$first" = 1 ] || out="$out,"
        first=0
        out="$out{\"name\":\"refinery-reconcile\",\"rig\":\"$r\",\"enabled\":true},{\"name\":\"feedback-miner\",\"rig\":\"$r\",\"enabled\":true}"
    done
    printf '%s]}' "$out"
}

history_for() { # rig...
    local out='{"entries":[' first=1 r
    for r in "$@"; do
        [ "$first" = 1 ] || out="$out,"
        first=0
        out="$out{\"order\":\"refinery-reconcile\",\"rig\":\"$r\",\"executed\":\"2026-08-20T08:15:16Z\"}"
    done
    printf '%s]}' "$out"
}

# Reset the stub dir to the healthy baseline; each case mutates one thing.
reset() {
    rm -rf "$TMP/stub"
    mkdir -p "$TMP/stub"
    export GC_STUB_DIR="$TMP/stub"
    orders_for gascity gc-toolkit signal-loom > "$TMP/stub/orders.json"
    history_for gascity gc-toolkit signal-loom > "$TMP/stub/history.json"
    printf '%s' "$RIGS" > "$TMP/stub/rigs.json"
    : > "$TMP/stub/ps.txt"
}

run_check() { # -> writes $TMP/out, returns exit code
    GC_PACK_DIR="$PACK" bash "$SCRIPT" > "$TMP/out" 2>&1
}

# ---------------------------------------------------------------------------
# (1) healthy city
# ---------------------------------------------------------------------------
reset
run_check; rc=$?
eq "$rc" 0 "(1) every rig registered and fresh -> exit 0"
has "OK:" "$TMP/out" "(1) says OK"
has "3 rig(s)" "$TMP/out" "(1) counts the rigs it checked"

# ---------------------------------------------------------------------------
# (13)(14)(17) the history read's shape — asserted on the healthy run's log
# ---------------------------------------------------------------------------
hist_call=$(grep '^order history' "$TMP/stub/calls.log" | head -1)
case "$hist_call" in
    *"--limit 0"*) ok "(13) history read passes --limit 0 (store-complete)" ;;
    *) bad "(13) history read must pass --limit 0; got '$hist_call'" ;;
esac
case "$hist_call" in
    *"--since 15m"*) ok "(14) history read is bounded by --since" ;;
    *) bad "(14) history read must pass --since; got '$hist_call'" ;;
esac

# ---------------------------------------------------------------------------
# (2) one rig stale, others fresh
# ---------------------------------------------------------------------------
reset
history_for gascity signal-loom > "$TMP/stub/history.json"
run_check; rc=$?
eq "$rc" 2 "(2) one stale rig -> exit 2"
has "gc-toolkit: registered but has NOT run" "$TMP/out" "(2) names the stale rig"
has "while other rigs have" "$TMP/out" "(2) says the controller is up"
has "pass.log" "$TMP/out" "(17) points at the rig's own pass.log"
has "--rig gc-toolkit --limit 0" "$TMP/out" "(17) gives a store-complete follow-up query"
hasnt "down city-wide" "$TMP/out" "(2) does not claim a city-wide outage"

# ---------------------------------------------------------------------------
# (3) every rig stale
# ---------------------------------------------------------------------------
reset
printf '{"entries":[]}' > "$TMP/stub/history.json"
run_check; rc=$?
eq "$rc" 2 "(3) all rigs stale -> exit 2"
has "NO rig has run" "$TMP/out" "(3) uses the city-wide message"
has "clears on the next tick" "$TMP/out" "(3) states the cold-boot caveat"
hasnt "while other rigs have" "$TMP/out" "(3) does not use the per-rig message"

# ---------------------------------------------------------------------------
# (4) importing rig with no merge clock
# ---------------------------------------------------------------------------
reset
cat > "$TMP/stub/orders.json" <<'JSON'
{"orders":[{"name":"refinery-reconcile","rig":"gascity","enabled":true},
           {"name":"feedback-miner","rig":"gascity","enabled":true},
           {"name":"feedback-miner","rig":"gc-toolkit","enabled":true}]}
JSON
history_for gascity > "$TMP/stub/history.json"
run_check; rc=$?
eq "$rc" 2 "(4) importing rig with no registration -> exit 2"
has "gc-toolkit: imports this pack but has NO refinery-reconcile registration" "$TMP/out" "(4) names the rig"
has "enabled = false" "$TMP/out" "(4) says a disabled override presents identically"

# ---------------------------------------------------------------------------
# (5) no registrations at all
# ---------------------------------------------------------------------------
reset
printf '{"orders":[{"name":"feedback-miner","rig":"gascity","enabled":true}]}' > "$TMP/stub/orders.json"
run_check; rc=$?
eq "$rc" 2 "(5) zero registrations -> exit 2"
has "NOT REGISTERED anywhere" "$TMP/out" "(5) says the clock is missing city-wide"

# ---------------------------------------------------------------------------
# (6) live out-of-band driver
# ---------------------------------------------------------------------------
reset
printf 'bash /tmp/gc-refinery-idle-gc-toolkit/idle-loop.sh\n/usr/bin/sshd -D\n' > "$TMP/stub/ps.txt"
run_check; rc=$?
eq "$rc" 2 "(6) live idle-loop driver -> exit 2"
has "out-of-band refinery driver running for rig gc-toolkit" "$TMP/out" "(6) names the rig"
has "SECOND merge-skill.sh writer" "$TMP/out" "(6) says why it is dangerous"
has "systemctl --user stop gc-refinery-idle-gc-toolkit.service" "$TMP/out" "(6) gives the retire command"

# ---------------------------------------------------------------------------
# (7c) one driver, several forked children with identical argv -> one finding
# ---------------------------------------------------------------------------
reset
printf 'bash /tmp/gc-refinery-idle-gc-toolkit/idle-loop.sh\nbash /tmp/gc-refinery-idle-gc-toolkit/idle-loop.sh\nbash /tmp/gc-refinery-idle-gc-toolkit/idle-loop.sh\n' > "$TMP/stub/ps.txt"
run_check; rc=$?
eq "$rc" 2 "(7c) forked driver children -> exit 2"
eq "$(grep -c 'out-of-band refinery driver running' "$TMP/out")" 1 "(7c) one finding per rig, not per process"
has "(3 process(es)" "$TMP/out" "(7c) reports the process count instead"
has "1 problem(s)" "$TMP/out" "(7c) the headline counts one problem"

# ---------------------------------------------------------------------------
# (7) a process merely naming the driver is not a driver
# ---------------------------------------------------------------------------
reset
printf 'tail -f /tmp/gc-refinery-idle-gc-toolkit/reconcile.log\nless /tmp/gc-refinery-idle-gascity/idle-loop.sh\ngrep -n merge /tmp/gc-refinery-idle-signal-loom/idle-loop.sh\n/usr/bin/zsh -c cat /tmp/gc-refinery-idle-gc-toolkit/idle-loop.sh\nbash --command cat /tmp/gc-refinery-idle-signal-loom/idle-loop.sh\n' > "$TMP/stub/ps.txt"
run_check; rc=$?
eq "$rc" 0 "(7) a reader of the driver's log or script is not a driver -> exit 0"
hasnt "out-of-band refinery driver running" "$TMP/out" "(7) not flagged"

# ---------------------------------------------------------------------------
# (7b) the script exec'd directly is a driver
# ---------------------------------------------------------------------------
reset
printf '/tmp/gc-refinery-idle-signal-loom/idle-loop.sh\n' > "$TMP/stub/ps.txt"
run_check; rc=$?
eq "$rc" 2 "(7b) directly exec'd idle-loop.sh -> exit 2"
has "out-of-band refinery driver running for rig signal-loom" "$TMP/out" "(7b) names the rig"

reset
printf 'bash -e /tmp/gc-refinery-idle-gc-toolkit/idle-loop.sh\n' > "$TMP/stub/ps.txt"
run_check; rc=$?
eq "$rc" 2 "(7b) shell script argument after options -> exit 2"
has "out-of-band refinery driver running for rig gc-toolkit" "$TMP/out" "(7b) names the rig from the script argument"

# ---------------------------------------------------------------------------
# (8) suspended rig
# ---------------------------------------------------------------------------
reset
history_for gascity gc-toolkit > "$TMP/stub/history.json"
printf '%s' '{"rigs":[{"name":"gascity","suspended":false,"hq":false},
                      {"name":"gc-toolkit","suspended":false,"hq":false},
                      {"name":"signal-loom","suspended":true,"hq":false}]}' > "$TMP/stub/rigs.json"
run_check; rc=$?
eq "$rc" 0 "(8) suspended rig with no runs -> exit 0"
has "signal-loom: skipped (suspended" "$TMP/out" "(8) says it was skipped"
has "1 suspended rig(s) skipped" "$TMP/out" "(8) counts it in the summary"

# ---------------------------------------------------------------------------
# (9) order registry unreadable
# ---------------------------------------------------------------------------
reset
rm -f "$TMP/stub/orders.json"
run_check; rc=$?
eq "$rc" 1 "(9) unreadable order registry -> exit 1 (warn, not OK)"
has "cannot read the order registry" "$TMP/out" "(9) says what it could not read"

# ---------------------------------------------------------------------------
# (10) run history unreadable
# ---------------------------------------------------------------------------
reset
rm -f "$TMP/stub/history.json"
run_check; rc=$?
eq "$rc" 1 "(10) unreadable history -> exit 1 (warn, not OK)"
has "could not read run history" "$TMP/out" "(10) says the liveness arm did not run"

reset
rm -f "$TMP/stub/history.json"
cat > "$TMP/stub/orders.json" <<'JSON'
{"orders":[{"name":"refinery-reconcile","rig":"gascity","enabled":true},
           {"name":"feedback-miner","rig":"gascity","enabled":true},
           {"name":"feedback-miner","rig":"gc-toolkit","enabled":true}]}
JSON
run_check; rc=$?
eq "$rc" 2 "(10) registration error + unreadable history -> exit 2"
has "liveness undetermined" "$TMP/out" "(10) does not silently claim the cadence is fine"

# ---------------------------------------------------------------------------
# (11) rig roster unreadable — warn, but liveness still runs
# ---------------------------------------------------------------------------
reset
rm -f "$TMP/stub/rigs.json"
run_check; rc=$?
eq "$rc" 1 "(11) unreadable rig roster -> exit 1"
has "could not read the rig roster" "$TMP/out" "(11) says so"
grep -q '^order history' "$TMP/stub/calls.log" && ok "(11) the liveness arm still ran" \
    || bad "(11) the liveness arm was skipped"

# ---------------------------------------------------------------------------
# (12) the subject is gone
# ---------------------------------------------------------------------------
reset
EMPTY="$TMP/emptypack"; mkdir -p "$EMPTY/orders"
GC_PACK_DIR="$EMPTY" bash "$SCRIPT" > "$TMP/out" 2>&1; rc=$?
eq "$rc" 1 "(12) pack no longer ships the order -> exit 1"
has "no longer ships orders/refinery-reconcile.toml" "$TMP/out" "(12) says the subject is gone"
hasnt "OK:" "$TMP/out" "(12) never green about an absent subject"

# ---------------------------------------------------------------------------
# (15)(16) the window
# ---------------------------------------------------------------------------
reset
GC_DOCTOR_MERGE_CADENCE_WINDOW=45m run_check
grep -q -- '--since 45m' "$TMP/stub/calls.log" && ok "(15) window override reaches the history read" \
    || bad "(15) window override ignored ($(grep '^order history' "$TMP/stub/calls.log" | head -1))"

reset
GC_DOCTOR_MERGE_CADENCE_WINDOW='; rm -rf /' run_check
grep -q -- '--since 15m' "$TMP/stub/calls.log" && ok "(16) malformed window falls back to 15m" \
    || bad "(16) malformed window was passed through ($(grep '^order history' "$TMP/stub/calls.log" | head -1))"

# ---------------------------------------------------------------------------
# (18) only `ps ax` works — the PID-prefixed fallback must still find a driver
# ---------------------------------------------------------------------------
reset
printf 'bash /tmp/gc-refinery-idle-gc-toolkit/idle-loop.sh\n/usr/bin/sshd -D\n' > "$TMP/stub/ps.txt"
GC_STUB_PS_FORMS=pidprefixed run_check; rc=$?
eq "$rc" 2 "(18) live driver seen only through \`ps ax\` -> exit 2"
has "out-of-band refinery driver running for rig gc-toolkit" "$TMP/out" "(18) names the rig from the normalised line"
has "(1 process(es)" "$TMP/out" "(18) counts the driver once, header row not miscounted"

# (18b) the same fallback must not promote a reader into a driver
reset
printf 'less /tmp/gc-refinery-idle-gascity/idle-loop.sh\ntail -f /tmp/gc-refinery-idle-gc-toolkit/reconcile.log\n' > "$TMP/stub/ps.txt"
GC_STUB_PS_FORMS=pidprefixed run_check; rc=$?
eq "$rc" 0 "(18b) reader seen through \`ps ax\` is still not a driver -> exit 0"
hasnt "out-of-band refinery driver running" "$TMP/out" "(18b) not flagged"

# (18c) a three-column `ps` (busybox: PID USER TIME) normalises just as exactly
reset
printf 'less /tmp/gc-refinery-idle-gascity/idle-loop.sh\n' > "$TMP/stub/ps.txt"
GC_STUB_PS_FORMS=pidprefixed GC_STUB_PS_COLUMNS=busybox run_check; rc=$?
eq "$rc" 0 "(18c) reader on a three-column ps is still not a driver -> exit 0"
hasnt "out-of-band refinery driver running" "$TMP/out" "(18c) not flagged"

reset
printf 'bash /tmp/gc-refinery-idle-signal-loom/idle-loop.sh\n' > "$TMP/stub/ps.txt"
GC_STUB_PS_FORMS=pidprefixed GC_STUB_PS_COLUMNS=busybox run_check; rc=$?
eq "$rc" 2 "(18c) real driver on a three-column ps is still found -> exit 2"
has "out-of-band refinery driver running for rig signal-loom" "$TMP/out" "(18c) names the rig"

# ---------------------------------------------------------------------------
# (19) no `ps` form works at all -> warn, never a silent OK
# ---------------------------------------------------------------------------
reset
printf 'bash /tmp/gc-refinery-idle-gc-toolkit/idle-loop.sh\n' > "$TMP/stub/ps.txt"
GC_STUB_PS_FORMS= run_check; rc=$?
eq "$rc" 1 "(19) unreadable process table -> exit 1 (warn, not OK)"
has "could not snapshot the process table" "$TMP/out" "(19) says what it could not read"
hasnt "OK:" "$TMP/out" "(19) never green about a driver arm that did not run"
hasnt "no out-of-band driver" "$TMP/out" "(19) does not claim absence it never checked"

# ---------------------------------------------------------------------------
# (INV) detect-only
# ---------------------------------------------------------------------------
[ -e "$HERE/fix.sh" ] && bad "(INV) a sibling fix.sh would auto-opt this into \`gc doctor --fix\`" \
    || ok "(INV) detect-only: no fix.sh next to run.sh"

echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
