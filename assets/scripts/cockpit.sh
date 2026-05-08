#!/bin/sh
# cockpit.sh — Gas City operator attention panel.
#
# Launched by the supervisor as the cockpit agent's entrypoint. Single
# foreground loop with these sections:
#   1. Rigs — per-rig polecat count + refinery state
#   2. Open decision beads (city + every rig)
#   3. Mail addressed to human
#   4. Open P0/P1 beads (city + every rig)
#   5. Call timings — per-call durations for this tick
#
# Bead lookups go through `gc bd ... --rig <name> --json` because bare
# `bd` from a rig CWD mis-routes to the city DB. Rigs auto-discovered
# from $CITY/rigs/*/.beads/. Output is reformatted (rig header + bead
# lines) for tighter visual grouping.
#
# Every external call is wrapped in `timed_capture` / `timed_pass` so
# the bottom panel surfaces the cost of each tick. Slow calls are
# visible immediately and a lifetime tick-max is tracked across reloads
# of the inner loop (resets when the script restarts).

CITY="${GC_CITY:-/home/zook/loomington}"
INTERVAL="${COCKPIT_INTERVAL:-60}"

# Resolve gc commands against the city even when launched from elsewhere
# (e.g. ad-hoc runs from /tmp). All `gc bd list`, `gc session list`,
# `gc mail` calls below depend on city auto-discovery from cwd.
cd "$CITY" || exit 1

TMPDIR=$(mktemp -d -t cockpit.XXXXXX)
TIMINGS_FILE="$TMPDIR/timings"
TICK_MAX_FILE="$TMPDIR/tick_max"
REFINERY_DIR="$TMPDIR/refinery"
RIGS_PY="$TMPDIR/rigs.py"
mkdir -p "$REFINERY_DIR"
trap 'rm -rf "$TMPDIR"' EXIT
# On signal-driven shutdown (supervisor stop, manual ^C), exit immediately
# after cleanup; otherwise the loop wraps and writes to a now-gone tmpdir.
trap 'rm -rf "$TMPDIR"; exit 0' INT TERM
echo 0 > "$TICK_MAX_FILE"

# Stash the rigs-panel renderer in its own file. We can't combine a
# stdin pipe with a `<<'PY'` heredoc — heredoc wins, the pipe is
# discarded. Writing the script to a file leaves stdin free for the
# session-list JSON.
cat > "$RIGS_PY" <<'PY'
import json, os, sys, collections, glob

try:
    sessions = json.load(sys.stdin)
except Exception:
    sessions = []

ref_state = {}
for path in glob.glob(os.path.join(os.environ["REFINERY_DIR"], "*.json")):
    rig = os.path.splitext(os.path.basename(path))[0]
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = []
    if not isinstance(data, list):
        data = []
    ref_state[rig] = data

polecat_count = collections.Counter()
refinery_sess = {}
for s in sessions:
    if s.get("Closed"):
        continue
    tmpl = s.get("Template", "")
    state = s.get("State", "")
    if "/" in tmpl:
        rig, role = tmpl.split("/", 1)
    else:
        rig, role = "city", tmpl
    role_short = role.split(".")[-1] if "." in role else role
    if "polecat" in role_short and state == "active":
        polecat_count[rig] += 1
    if role_short == "refinery":
        refinery_sess[rig] = state

def fmt_refinery(rig):
    sess = refinery_sess.get(rig)
    if sess is None:
        return "—"
    if sess != "active":
        return sess
    rs = ref_state.get(rig, [])
    if not rs:
        return "idle"
    title = rs[0].get("title", "")
    if len(title) > 48:
        title = title[:45] + "..."
    return f"working ({title})" if title else "working"

rig_order = ["city"] + sorted(ref_state.keys())
for rig in rig_order:
    pc = polecat_count.get(rig, 0)
    rf = "—" if rig == "city" else fmt_refinery(rig)
    print(f"  {rig:<14}  polecats: {pc}  ·  refinery: {rf}")
PY

now_ns() { date +%s%N; }

# timed_capture <label> <cmd...> — runs cmd, captures stdout for the
# caller, logs "<ms>\t<label>" to TIMINGS_FILE.
timed_capture() {
    label=$1; shift
    start=$(now_ns)
    out=$("$@" 2>/dev/null)
    rc=$?
    end=$(now_ns)
    ms=$(( (end - start) / 1000000 ))
    printf '%d\t%s\n' "$ms" "$label" >> "$TIMINGS_FILE"
    printf '%s' "$out"
    return $rc
}

# timed_pass <label> <cmd...> — runs cmd, lets stdout through to the
# terminal, logs duration. Stderr suppressed.
timed_pass() {
    label=$1; shift
    start=$(now_ns)
    "$@" 2>/dev/null
    rc=$?
    end=$(now_ns)
    ms=$(( (end - start) / 1000000 ))
    printf '%d\t%s\n' "$ms" "$label" >> "$TIMINGS_FILE"
    return $rc
}

list_rigs() {
    for r in "$CITY"/rigs/*/; do
        [ -d "$r/.beads" ] || continue
        basename "$r"
    done
}

section_divider() {
    printf '\n══════════════════════════════════════════════════════════════\n'
    printf '  %s\n' "$1"
    printf '══════════════════════════════════════════════════════════════\n\n'
}

# bead_block <store-label> <timing-label> <gc-bd-flags...>
# Prints rig header + beads, returns 0 if any printed, 1 otherwise.
bead_block() {
    name=$1; shift
    qlabel=$1; shift
    json=$(timed_capture "bd-list:$qlabel:$name" gc bd list "$@" --json)
    case "$json" in
        ''|'[]') return 1 ;;
    esac
    printf '%s' "$json" | RIG_NAME="$name" python3 -c '
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(data, list) or not data:
    sys.exit(1)
name = os.environ["RIG_NAME"]
print(f"  {name}  ({len(data)})")
for d in data:
    sym = "○" if d["status"] == "open" else "◐"
    pri = "P" + str(d["priority"])
    bid = d["id"]
    title = d["title"]
    if len(title) > 70:
        title = title[:67] + "..."
    print(f"    {sym} {bid:<14} {pri}  {title}")
'
}

draw_section() {
    label=$1; shift
    qlabel=$1; shift
    section_divider "$label"
    found=0
    if bead_block "city" "$qlabel" "$@"; then found=1; fi
    for rig in $(list_rigs); do
        if bead_block "$rig" "$qlabel" "$@" --rig "$rig"; then found=1; fi
    done
    [ "$found" = 0 ] && printf '  (none)\n'
}

# draw_rigs — per-rig polecat count + refinery state.
#
# Polecat count: sessions with Template ".../*polecat*" and State=active.
# Refinery state:
#   - missing  → no refinery session for this rig (printed as "—")
#   - asleep   → refinery session exists but tmux pane idle/closed
#   - idle     → active session, no in-progress wisp assigned to it
#   - working  → active session, in-progress wisp assigned to it
#                (wisp title is shown when present)
draw_rigs() {
    section_divider 'RIGS'
    sessions_json=$(timed_capture "session-list" gc session list --json)
    # Wipe any prior tick's refinery JSON files; one file per rig so
    # we don't have to escape multi-line pretty-printed JSON in a
    # combined index file.
    rm -f "$REFINERY_DIR"/*.json 2>/dev/null
    for rig in $(list_rigs); do
        rjson=$(timed_capture "bd-refinery:$rig" gc bd list --rig "$rig" --status in_progress --assignee "$rig/gc-toolkit.refinery" --json)
        case "$rjson" in
            '') rjson='[]' ;;
        esac
        printf '%s' "$rjson" > "$REFINERY_DIR/$rig.json"
    done

    printf '%s' "$sessions_json" | REFINERY_DIR="$REFINERY_DIR" python3 "$RIGS_PY"
}

draw_timings() {
    section_divider 'CALL TIMINGS (this tick)'
    if [ ! -s "$TIMINGS_FILE" ]; then
        printf '  (no calls)\n'
        return
    fi
    total=$(awk '{s+=$1} END {print s+0}' "$TIMINGS_FILE")
    prev_max=$(cat "$TICK_MAX_FILE")
    new_max=""
    if [ "$total" -gt "$prev_max" ]; then
        echo "$total" > "$TICK_MAX_FILE"
        new_max="  ← new max"
    fi
    sort -k1,1nr "$TIMINGS_FILE" | awk '{printf "  %-40s %5d ms\n", $2, $1}'
    printf '  %-40s %5d ms%s\n' 'TOTAL (this tick)' "$total" "$new_max"
    printf '  %-40s %5d ms\n' 'TOTAL MAX (since launch)' "$(cat "$TICK_MAX_FILE")"
}

# Cursor home, clear screen, clear scrollback. Explicit ANSI because
# TERM is unset in the cockpit pane env, so `clear`/`tput` may emit
# partial sequences that leak as ^[ artifacts.
clear_pane() { printf '\033[H\033[2J\033[3J'; }

# Wipe any pre-script supervisor banner once, before the loop starts.
clear_pane

while :; do
    : > "$TIMINGS_FILE"
    clear_pane
    printf '═══ Gas City attention ── %s ═══\n' "$(date '+%Y-%m-%d %H:%M:%S')"

    draw_rigs
    draw_section 'OPEN DECISION BEADS' 'decision' -t decision --status open

    section_divider 'MAIL TO HUMAN'
    timed_pass "mail-inbox-human" gc mail inbox human || printf '  (gc mail inbox unavailable)\n'

    draw_section 'OPEN P0/P1 BEADS' 'p01' -p 0,1 --status open,in_progress

    draw_timings

    sleep "$INTERVAL"
done
