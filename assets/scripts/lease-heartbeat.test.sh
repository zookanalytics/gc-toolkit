#!/usr/bin/env bash
# Hermetic test for lease-heartbeat.sh — the holder-side claim-lease keepalive
# that wraps a long command and refreshes the bead's lease while it runs — and
# for the formula regions that wire it into the long pool-claim paths.
#
# No live city, Dolt, or network: a stub `gc` on PATH records every
# `bd heartbeat <id>` it is asked for, and the cadence knobs are
# turned down (INTERVAL=1, POLL=1) so a 3-second command exercises several ticks
# in a few seconds. What it proves: the command's exit status is propagated, the
# lease is refreshed up front and again during a long run, a failing or missing
# heartbeat never fails the command, a refused heartbeat is reported once on
# stderr, an empty bead id runs the command plain, and misuse exits 2. The
# wiring section EXECUTES each formula's keepalive region, extracted verbatim,
# and asserts the id it hands the wrapper is the bead the step's own
# `gc hook --claim` returned — never the review bead or the work bead, which
# carry no lease for the holder to refresh. It also renders each polecat step's
# test-command lines with a command carrying both quote kinds and runs them, so
# the rig's test command reaches the keepalive verbatim.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/lease-heartbeat.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lease-heartbeat-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
ge()  { [ "$1" -ge "$2" ] && ok "$3" || bad "$3 (got '$1' want >= '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 ('$2' not in '$1')" ;; esac; }

# --- stub gc: record each `bd heartbeat <id>`, honor a configurable exit code --
# A refusal prints the store's own wording, so the report's reason is checkable.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "heartbeat" ]; then
    printf '%s\n' "${3:-}" >> "$HB_LOG"
    rc="${FAKE_GC_HB_RC:-0}"
    [ "$rc" -eq 0 ] || echo "Error: heartbeat ${3:-}: issue not claimable: ${3:-} status open" >&2
    exit "$rc"
fi
exit 0
EOF
chmod +x "$TMP/bin/gc"
export HB_LOG="$TMP/hb.log"
# Intercept `gc` with the stub; `timeout`, `sleep`, etc. still resolve normally.
export PATH="$TMP/bin:$PATH"

hb_count() { [ -f "$HB_LOG" ] && wc -l < "$HB_LOG" | tr -d ' ' || echo 0; }

# run <args...> : run the wrapper without tripping set -e; its status lands in RC.
run() { set +e; bash "$SCRIPT" "$@"; RC=$?; set -e; }

[ -x "$SCRIPT" ] && ok "lease-heartbeat.sh is executable" || bad "lease-heartbeat.sh missing or not executable"
bash -n "$SCRIPT" && ok "lease-heartbeat.sh parses (bash -n)" || bad "lease-heartbeat.sh failed bash -n"

# --- exit-status propagation ------------------------------------------------
: > "$HB_LOG"
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-prop -- bash -c 'exit 7'
eq "$RC" "7" "propagates a non-zero command exit status"

: > "$HB_LOG"
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-prop -- bash -c 'exit 0'
eq "$RC" "0" "propagates a zero command exit status"

# --- the command actually runs, and the lease is refreshed WHILE it runs ----
: > "$HB_LOG"
rm -f "$TMP/ran"
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-live -- bash -c "sleep 3; : > '$TMP/ran'" 2> "$TMP/err"
eq "$RC" "0" "a long command still exits 0 under the wrapper"
[ -f "$TMP/ran" ] && ok "the wrapped command ran to completion" || bad "the wrapped command did not run"
ge "$(hb_count)" "2" "the lease is refreshed up front AND at least once during a 3s run"
# every recorded heartbeat named the bead we asked for, nothing else
STRAY="$(grep -cv '^tk-live$' "$HB_LOG" || true)"
eq "${STRAY:-0}" "0" "every heartbeat targeted the wrapped bead id"
eq "$(wc -c < "$TMP/err" | tr -d ' ')" "0" "heartbeats the store accepts write nothing to stderr"

# --- entry heartbeat fires even for an instantaneous command ----------------
: > "$HB_LOG"
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-fast -- true
eq "$RC" "0" "an instant command exits 0"
ge "$(hb_count)" "1" "the up-front heartbeat fires even when the command is instant"

# --- a failing heartbeat must never fail the wrapped command ----------------
: > "$HB_LOG"
FAKE_GC_HB_RC=1 LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-hbfail -- bash -c 'exit 0' 2> /dev/null
eq "$RC" "0" "a heartbeat that exits non-zero does not fail the command"

# --- a refused heartbeat is reported once, not swallowed --------------------
# A keepalive aimed at a bead the holder never claimed is refused on every tick.
# The holder must hear about it, once, while the command runs to its own status.
: > "$HB_LOG"
rm -f "$TMP/ran"
FAKE_GC_HB_RC=1 LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-refused -- bash -c "sleep 3; : > '$TMP/ran'; exit 3" 2> "$TMP/err"
eq "$RC" "3" "a refused heartbeat leaves the command's exit status intact"
[ -f "$TMP/ran" ] && ok "the command runs to completion under refused heartbeats" || bad "the command did not run under refused heartbeats"
ge "$(hb_count)" "2" "the wrapper keeps trying across the run"
eq "$(grep -cF 'heartbeat on tk-refused failed' "$TMP/err" || true)" "1" "the refusal is reported exactly once across several failed ticks"
has "$(cat "$TMP/err")" "issue not claimable" "the report carries the store's reason"

# --- an empty bead id runs the command plain --------------------------------
# An unset claim variable in a caller must cost the keepalive, never the run.
: > "$HB_LOG"
rm -f "$TMP/ran"
run "" -- bash -c ": > '$TMP/ran'; exit 4" 2> "$TMP/err"
eq "$RC" "4" "an empty bead id still runs the command and propagates its status"
[ -f "$TMP/ran" ] && ok "an empty bead id runs the wrapped command" || bad "an empty bead id did not run the command"
eq "$(hb_count)" "0" "an empty bead id makes no heartbeat call"
has "$(cat "$TMP/err")" "no bead id given" "an empty bead id is reported on stderr"

# --- misuse exits 2 ---------------------------------------------------------
run tk-x -- 2> /dev/null; eq "$RC" "2" "missing command exits 2"
run tk-x bash -c 'exit 0' 2> /dev/null; eq "$RC" "2" "missing -- separator exits 2"
run 2> /dev/null; eq "$RC" "2" "missing bead id exits 2"

# --- wiring: each long pool-claim path heartbeats its own claim --------------
# The lease is on the bead the step's `gc hook --claim` returned and nowhere
# else; a keepalive handed any other id is refused by the store and refreshes
# nothing. Each region is extracted verbatim from its formula and executed with
# a stub wrapper that records the id it was handed, with every candidate id set
# to a distinct value, so the region's target is read off what it passed.
ROOT="$(cd "$HERE/../.." && pwd)"

extract() {  # extract <toml> <marker>
    awk -v m="$2" '
        $0 ~ ("# >>> " m "$") {f=1; next}
        $0 ~ ("# <<< " m "$") {f=0}
        f' "$1"
}

STUB_PACK="$TMP/pack"
mkdir -p "$STUB_PACK/assets/scripts"
cat > "$STUB_PACK/assets/scripts/lease-heartbeat.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$TARGET_LOG"
shift 2
exec "$@"
EOF
chmod +x "$STUB_PACK/assets/scripts/lease-heartbeat.sh"
export TARGET_LOG="$TMP/target.log"

# run_region <region-file> <pack-dir> : source the region in a fresh shell, from
# a directory outside any repo, then run `hb touch $TMP/hb-ran`.
run_region() {
    : > "$TARGET_LOG"
    rm -f "$TMP/hb-ran"
    ( cd "$TMP" && env GC_PACK_DIR="$2" GC_RIG_ROOT="" GC_CITY_PATH="$TMP/no-city" \
        CLAIMED_STEP_BEAD_ID=tk-claimed-step CLAIMED_ITER_BEAD=tk-claimed-iter \
        REVIEW_BEAD=tk-review-bead WORK_BEAD_ID=tk-work-bead \
        bash -c '. "$1" && hb touch "$2"' _ "$1" "$TMP/hb-ran" )
}

check_region() {  # check_region <toml-path-under-root> <marker> <want-target>
    local toml="$ROOT/$1" label="$1 $2" want="$3" block var
    block="$(extract "$toml" "$2")"
    if [ -z "$block" ]; then
        bad "$label: region not found (markers missing)"
        return 0
    fi
    eq "$(grep -c "^# >>> $2\$" "$toml")" "1" "$label: exactly one region"
    # A TOML triple-quoted string eats a trailing backslash and joins lines.
    case "$block" in
        *\\*) bad "$label: region contains a backslash, which TOML would mangle" ;;
        *)    ok  "$label: region is backslash-free" ;;
    esac
    printf '%s\n' "$block" > "$TMP/region.sh"
    if ! bash -n "$TMP/region.sh"; then
        bad "$label: region fails bash -n"
        return 0
    fi
    # The keepalive's target is the id the region actually hands the wrapper.
    if run_region "$TMP/region.sh" "$STUB_PACK"; then ok "$label: hb exits 0"; else bad "$label: hb exited non-zero"; fi
    [ -f "$TMP/hb-ran" ] && ok "$label: hb runs the wrapped command" || bad "$label: hb did not run the wrapped command"
    eq "$(cat "$TARGET_LOG")" "$want" "$label: the keepalive targets the claimed bead"
    # ...and that id comes from the step's own claim, not from some other pin.
    var="$(printf '%s\n' "$block" | sed -n 's/.*"\$LHB" "\$\([A-Z_]*\)" -- .*/\1/p')"
    if [ -n "$var" ] && awk -v p="$var=\"<the bead_id your gc hook --claim returned" 'index($0, p) == 1 { f = 1 } END { exit !f }' "$toml"; then
        ok "$label: \$$var is set from the step's gc hook --claim"
    else
        bad "$label: the keepalive's id variable (${var:-none}) is not set from a gc hook --claim in $1"
    fi
    # With no wrapper resolvable, hb still runs the command, plain.
    if run_region "$TMP/region.sh" "$TMP/no-pack"; then ok "$label: hb exits 0 with no wrapper"; else bad "$label: hb exited non-zero with no wrapper"; fi
    [ -f "$TMP/hb-ran" ] && ok "$label: hb runs the command plain when no wrapper resolves" || bad "$label: hb did not run the command with no wrapper"
}

check_region formulas/mol-polecat-work.toml preflight-lease-keepalive   tk-claimed-step
check_region formulas/mol-polecat-work.toml self-review-lease-keepalive tk-claimed-iter
check_region formulas/mol-review.toml       review-lease-keepalive      tk-claimed-step

# --- the rig's test command reaches the keepalive verbatim -------------------
# A pour renders the rig's test command into the step text, so a quote inside
# it must not re-split the command the step hands to hb. Each block runs from
# its keepalive region to its closing fence, rendered the way a pour renders
# it, against the stub wrapper. The command carries both quote kinds and a
# pipe character, which a single-quoted rendering turns into shell syntax.
block_tail() {  # block_tail <toml> <marker> : the lines after the region, up to the closing fence
    awk -v m="$2" '
        $0 ~ ("# <<< " m "$") {f=1; next}
        f && /^```/ {exit}
        f' "$1"
}

# render : substitute each command var literally, test_command from $TC and
# affected_tests_command from $ATC, every other command var empty.
render() {
    TC="$TC" ATC="$ATC" awk '
        function rep(s, k, v,   i, out) {
            out = ""
            while ((i = index(s, k)) > 0) { out = out substr(s, 1, i - 1) v; s = substr(s, i + length(k)) }
            return out s
        }
        {
            s = rep($0, "{{test_command}}", ENVIRON["TC"])
            s = rep(s, "{{affected_tests_command}}", ENVIRON["ATC"])
            s = rep(s, "{{setup_command}}", ""); s = rep(s, "{{typecheck_command}}", "")
            s = rep(s, "{{lint_command}}", ""); s = rep(s, "{{build_command}}", "")
            print s
        }'
}

run_block() {  # run_block <toml-path-under-root> <marker> : status lands in BLOCK_RC
    extract "$ROOT/$1" "$2" > "$TMP/region.sh"
    block_tail "$ROOT/$1" "$2" | render > "$TMP/tail.sh"
    : > "$TARGET_LOG"
    rm -f "$TMP/cmd-out"
    BLOCK_RC=0
    ( cd "$TMP" && env GC_PACK_DIR="$STUB_PACK" GC_RIG_ROOT="" GC_CITY_PATH="$TMP/no-city" \
        CLAIMED_STEP_BEAD_ID=tk-claimed-step CLAIMED_ITER_BEAD=tk-claimed-iter \
        bash -c '. "$1"; . "$2"' _ "$TMP/region.sh" "$TMP/tail.sh" ) 2> /dev/null || BLOCK_RC=$?
}

QUOTED="printf '%s|%s|' 'one two' \"it's\" > cmd-out"
WANT_OUT="one two|it's|"

check_tail() {  # check_tail <toml-path-under-root> <marker>
    local tail_text
    tail_text="$(block_tail "$ROOT/$1" "$2")"
    [ -n "$tail_text" ] && ok "$2: test-command lines found" || bad "$2: no test-command lines after the region"
    case "$tail_text" in
        *\\*) bad "$2: test-command lines contain a backslash, which TOML would mangle" ;;
        *)    ok  "$2: test-command lines are backslash-free" ;;
    esac
    case "$(printf '%s\n' "$tail_text" | TC=x ATC=x render)" in
        *'{{'*) bad "$2: test-command lines carry a var the render does not cover" ;;
        *)      ok  "$2: every var in the test-command lines is rendered" ;;
    esac
}

check_tail formulas/mol-polecat-work.toml preflight-lease-keepalive
check_tail formulas/mol-polecat-work.toml self-review-lease-keepalive

TC="$QUOTED"; ATC=""; run_block formulas/mol-polecat-work.toml preflight-lease-keepalive
eq "$BLOCK_RC" "0" "preflight: a quoted test command exits 0"
eq "$(cat "$TMP/cmd-out" 2> /dev/null || true)" "$WANT_OUT" "preflight: a quoted test command runs verbatim"
eq "$(cat "$TARGET_LOG")" "tk-claimed-step" "preflight: the test command runs under the keepalive"

TC=""; ATC=""; run_block formulas/mol-polecat-work.toml preflight-lease-keepalive
eq "$BLOCK_RC" "0" "preflight: an empty test command exits 0"
eq "$(cat "$TARGET_LOG")" "" "preflight: an empty test command runs nothing"

TC="false"; ATC="$QUOTED"; run_block formulas/mol-polecat-work.toml self-review-lease-keepalive
eq "$BLOCK_RC" "0" "self-review: a quoted affected-tests command exits 0"
eq "$(cat "$TMP/cmd-out" 2> /dev/null || true)" "$WANT_OUT" "self-review: the affected-tests command runs verbatim, in place of the full suite"
eq "$(cat "$TARGET_LOG")" "tk-claimed-iter" "self-review: the affected-tests command runs under the keepalive"

TC="$QUOTED"; ATC=""; run_block formulas/mol-polecat-work.toml self-review-lease-keepalive
eq "$BLOCK_RC" "0" "self-review: a quoted test command exits 0"
eq "$(cat "$TMP/cmd-out" 2> /dev/null || true)" "$WANT_OUT" "self-review: with no affected-tests command, the test command runs verbatim"

TC=""; ATC=""; run_block formulas/mol-polecat-work.toml self-review-lease-keepalive
eq "$BLOCK_RC" "0" "self-review: no test command exits 0"
eq "$(cat "$TARGET_LOG")" "" "self-review: no test command runs nothing"

echo "----"
echo "lease-heartbeat.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
