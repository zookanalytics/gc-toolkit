#!/bin/sh
# cockpit.sh — Gas City operator attention panel.
#
# Launched by the supervisor as the cockpit agent's entrypoint. Single
# foreground loop with these sections:
#   1. Rigs — per-rig polecat count + refinery state
#   2. Open decision beads (city + every rig)
#   3. Mail addressed to human
#   4. Context watch — sessions with elevated context usage
#   5. Open P0/P1 beads (city + every rig)
#   6. Call timings — top 5 per-call durations for this tick
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
#
# Usage: cockpit.sh [--city-path <path>]
#
# --city-path is the absolute path of the city this cockpit serves;
# overrides $GC_CITY / cwd auto-discovery and is the source of truth
# for the API city-name lookup. Pass it explicitly when launching from
# a context that doesn't carry Gas City env (operator shell, ad-hoc
# runs).

EXPLICIT_CITY_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --city-path) EXPLICIT_CITY_PATH="${2:-}"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

CITY="${EXPLICIT_CITY_PATH:-${GC_CITY:-/home/zook/loomington}}"
INTERVAL="${COCKPIT_INTERVAL:-60}"

# Resolve gc commands against the city even when launched from elsewhere
# (e.g. ad-hoc runs from /tmp). All `gc bd list`, `gc mail` calls below
# depend on city auto-discovery from cwd.
cd "$CITY" || exit 1

# Supervisor API discovery — see gc-toolkit-status-line.sh for the
# canonical comment. Port honors ~/.gc/supervisor.toml; city name is
# resolved by matching the current city path against [[cities]] entries
# in ~/.gc/cities.toml. Keep in lockstep with status-line / picker.
gc_api_base() {
    port=8372
    cfg="${GC_HOME:-$HOME/.gc}/supervisor.toml"
    if [ -f "$cfg" ]; then
        v=$(awk -F= '/^[[:space:]]*port[[:space:]]*=/ { gsub(/[[:space:]]/,"",$2); print $2; exit }' "$cfg" 2>/dev/null)
        [ -n "$v" ] && port=$v
    fi
    printf 'http://127.0.0.1:%s' "$port"
}
gc_city_name() {
    cfg="${GC_HOME:-$HOME/.gc}/cities.toml"
    # Same env chain as the other helpers, plus $CITY (already resolved
    # at the top of this script with its own hardcoded last-resort) as
    # the final non-cwd fallback. Without it the script's `cd "$CITY"`
    # would silently disagree with the API URL we build below — gc bd
    # commands would target the default city while /v0/city//sessions
    # 404s. No cwd walk-up — see gc-toolkit-status-line.sh for rationale.
    city_path="${EXPLICIT_CITY_PATH:-${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-${CITY:-}}}}}"
    [ -z "$city_path" ] && return
    city_path="${city_path%/}"
    if [ -f "$cfg" ]; then
        name=$(awk -v want="$city_path" '
            BEGIN { in_block=0; p=""; n=""; found=0 }
            /^\[\[cities\]\]/ {
                if (in_block && p == want && n != "") { print n; found=1; exit }
                in_block=1; p=""; n=""; next
            }
            /^\[/ {
                if (in_block && p == want && n != "") { print n; found=1; exit }
                in_block=0; next
            }
            in_block && /^[[:space:]]*path[[:space:]]*=[[:space:]]*"[^"]*"/ {
                v=$0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); p=v
            }
            in_block && /^[[:space:]]*name[[:space:]]*=[[:space:]]*"[^"]*"/ {
                v=$0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); n=v
            }
            END {
                if (!found && in_block && p == want && n != "") print n
            }
        ' "$cfg")
        [ -n "$name" ] && { printf '%s' "$name"; return; }
    fi
    basename "$city_path"
}

TMPDIR=$(mktemp -d -t cockpit.XXXXXX)
TIMINGS_FILE="$TMPDIR/timings"
TICK_MAX_FILE="$TMPDIR/tick_max"
REFINERY_DIR="$TMPDIR/refinery"
RIGS_PY="$TMPDIR/rigs.py"
CTX_PY="$TMPDIR/ctx.py"
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

# Supervisor API shape: {"items": [...], "total": N}. Closed sessions are
# excluded by default so we don't need to filter them here.
try:
    payload = json.load(sys.stdin)
except Exception:
    payload = {}
sessions = payload.get("items", []) if isinstance(payload, dict) else []

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
    tmpl = s.get("template", "")
    state = s.get("state", "")
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

# Context-watch renderer. Same heredoc-vs-pipe constraint as RIGS_PY —
# we feed sessions_json on stdin, so the script lives in its own file.
cat > "$CTX_PY" <<'PY'
import json, os, sys

# Roles whose context_pct is structurally absent (no LLM behind them).
# Skip BEFORE counting so they drop out of "(of N polled)". Extend this
# set if more non-LLM agent types emerge.
SKIP_ROLES = {"control-dispatcher"}

# Per-session peek fallback for asleep agents. handler_sessions.go's
# enrichSessionResponse returns early when state != active, so
# context_pct is never populated for asleep sessions even with
# peek=true. The shell wrapper peeks each asleep session via
# `gc session peek` and writes "<sid>\t<pct>" rows here; without this
# fallback a high-context dormant agent — the expensive wake-up case
# this panel is meant to surface — silently disappears.
asleep_ctx = {}
asleep_path = os.environ.get("ASLEEP_CTX_FILE", "")
if asleep_path:
    try:
        with open(asleep_path) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2 and parts[0] and parts[1].isdigit():
                    asleep_ctx[parts[0]] = int(parts[1])
    except FileNotFoundError:
        pass

try:
    payload = json.load(sys.stdin)
except Exception:
    payload = {}
sessions = payload.get("items", []) if isinstance(payload, dict) else []

rows = []
for s in sessions:
    state = s.get("state")
    if state not in ("active", "asleep"):
        continue
    tmpl = s.get("template", "")
    rig, role = tmpl.split("/", 1) if "/" in tmpl else ("city", tmpl)
    role_short = role.split(".")[-1] if "." in role else role
    if role_short in SKIP_ROLES:
        continue
    sid = s.get("id", "")
    if not sid:
        continue
    pct = s.get("context_pct")
    if not isinstance(pct, int) and state == "asleep":
        # API doesn't enrich asleep sessions; fall back to the peeked value.
        pct = asleep_ctx.get(sid)
    if isinstance(pct, int):
        if pct < 12:
            tier = "hidden"
        elif pct <= 25:
            tier = "watch"
        elif pct <= 49:
            tier = "care"
        else:
            tier = "red"
        rows.append({"id": sid, "tmpl": tmpl, "ctx": f"ctx:{pct}%", "n": pct, "tier": tier})
    else:
        # context_pct null/missing: agent is mid-turn or hasn't reported
        # yet. Show as midturn so the operator knows it was polled.
        rows.append({"id": sid, "tmpl": tmpl, "ctx": "ctx:…", "n": None, "tier": "midturn"})

counts = {"watch": 0, "care": 0, "red": 0}
for r in rows:
    if r["tier"] in counts:
        counts[r["tier"]] += 1

print(f"  {counts['watch']} watch · {counts['care']} care · {counts['red']} red  (of {len(rows)} polled)")

body = [r for r in rows if r["tier"] in ("watch", "care", "red")]
body.sort(key=lambda r: (-r["n"], r["id"]))

if not body:
    print("  (all under 12%)")
else:
    for r in body:
        print(f"  {r['id']:<10}  {r['tmpl']:<32}  {r['ctx']:<8} {r['tier']}")
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
# Polecat count: sessions with template ".../*polecat*" and state=active.
# Refinery state:
#   - missing  → no refinery session for this rig (printed as "—")
#   - asleep   → refinery session exists but tmux pane idle/closed
#   - idle     → active session, no in-progress wisp assigned to it
#   - working  → active session, in-progress wisp assigned to it
#                (wisp title is shown when present)
draw_rigs() {
    section_divider 'RIGS'
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

# peek_ctx <session-id> — fallback context-percent extractor for sessions
# the supervisor API doesn't enrich (asleep). Greps `gc session peek`
# output for the latest Claude-style `ctx:N%` or Codex-style
# `Context N% used` statusline. Empty result means the saved buffer
# carries no recognizable ctx line.
peek_ctx() {
    gc session peek "$1" 2>/dev/null \
      | grep -oE 'ctx:[0-9]+%|Context [0-9]+% used' \
      | tail -1 \
      | grep -oE '[0-9]+'
}

# draw_ctx_watch — surface sessions whose context window is filling up so
# the operator can see expensive agents before they bite. For active
# sessions, context_pct comes from the bulk supervisor-API fetch
# (peek=true). For asleep sessions the API skips enrichment
# (handler_sessions returns early when state != active), so we peek
# each individually — asleep agents are the expensive wake-up case
# this panel is meant to surface and cannot silently drop out. Tiers
# each non-closed agent session and prints only watch/care/red.
draw_ctx_watch() {
    section_divider 'CONTEXT WATCH'

    asleep_ctx_file="$TMPDIR/asleep_ctx"
    : > "$asleep_ctx_file"
    asleep_ids=$(printf '%s' "$sessions_json" | python3 -c '
import json, sys
SKIP_ROLES = {"control-dispatcher"}
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for s in payload.get("items", []) if isinstance(payload, dict) else []:
    if s.get("state") != "asleep":
        continue
    tmpl = s.get("template", "")
    role = tmpl.split("/", 1)[1] if "/" in tmpl else tmpl
    role_short = role.split(".")[-1] if "." in role else role
    if role_short in SKIP_ROLES:
        continue
    sid = s.get("id", "")
    if sid:
        print(sid)
')
    if [ -n "$asleep_ids" ]; then
        printf '%s\n' "$asleep_ids" | while read -r sid; do
            [ -z "$sid" ] && continue
            pct=$(timed_capture "ctx-peek:$sid" peek_ctx "$sid")
            printf '%s\t%s\n' "$sid" "$pct" >> "$asleep_ctx_file"
        done
    fi

    printf '%s' "$sessions_json" | ASLEEP_CTX_FILE="$asleep_ctx_file" python3 "$CTX_PY"
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
    sort -k1,1nr "$TIMINGS_FILE" | head -5 | awk '{printf "  %-40s %5d ms\n", $2, $1}'
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

    # Single supervisor-API fetch per tick. The Dolt walk is served from
    # CachingStore (shared with status-line / picker polls). `peek=true`
    # asks the handler to enrich each session with context_pct by tailing
    # the transcript file — required for draw_ctx_watch; the per-session
    # peek runs uncached, but the cockpit cadence (60s default) and
    # ~tens-of-sessions scale keep this well below the prior cost of N
    # `gc session peek` tmux capture-pane subprocesses. curl -f swallows
    # the body during the cold-cache 503 window after `gc start`;
    # downstream Python falls through to "no sessions" on empty input.
    sessions_json=$(timed_capture "session-list" curl -sf --max-time 5 \
        "$(gc_api_base)/v0/city/$(gc_city_name)/sessions?peek=true")

    draw_rigs
    draw_section 'OPEN DECISION BEADS' 'decision' -t decision --status open

    section_divider 'MAIL TO HUMAN'
    timed_pass "mail-inbox-human" gc mail inbox human || printf '  (gc mail inbox unavailable)\n'

    draw_ctx_watch

    draw_section 'OPEN P0/P1 BEADS' 'p01' -p 0,1 --status open,in_progress

    draw_timings

    sleep "$INTERVAL"
done
