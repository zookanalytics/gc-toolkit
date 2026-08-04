#!/usr/bin/env bash
# burn-watch.sh — post-restart burn check. Run every ~15 min for the first hour.
#
# Answers four questions, in the order they go wrong:
#   1. Is the round cap actually loaded? (a merged PR does nothing until the rig root is pulled)
#   2. Is any anchor past the cap? (the cap should ESCALATE, never spawn round N+1)
#   3. How many codex reviews have been minted? (the Copilot budget)
#   4. How many polecat sessions are live? (the Claude burn rate)
#
# Read-only. Safe to run against a live city.
set -uo pipefail

CITY="${GC_CITY_ROOT:-/home/zook/loomington}"
RIGS=(gc-toolkit gascity signal-loom shutupandlisten)
CAP="${GC_MAX_REVIEW_ROUNDS:-3}"
# When PR#252 (the cap) merged. Rework children older than this predate the cap
# and prove nothing about whether it works; only newer ones can indict it.
CAP_LANDED="${GC_CAP_LANDED_AT:-2026-08-03T17:22:55Z}"

echo "=== burn-watch $(date -u +%Y-%m-%dT%H:%M:%SZ) (cap=$CAP) ==="

# --- 1. cap loaded? -----------------------------------------------------------
# Checks the file the city ACTUALLY loads (the .beads/formulas symlink target and
# the rig-root fragment), not origin/main. This is the check that would have
# caught the cap being merged but not pulled.
echo
echo "-- cap loaded --"
for r in "${RIGS[@]}"; do
  f=$(grep -c 'GC_MAX_REVIEW_ROUNDS' "$CITY/rigs/$r/.beads/formulas/mol-refinery-patrol.formula.toml" 2>/dev/null || echo 0)
  [ "$f" -gt 0 ] && s=ok || s='*** NOT LOADED ***'
  echo "   $r refinery-half: $f  $s"
done
p=$(grep -c 'signoff-round-cap' "$CITY/rigs/gc-toolkit/template-fragments/polecat-non-impl-done.template.md" 2>/dev/null || echo 0)
[ "$p" -gt 0 ] && s=ok || s='*** NOT LOADED ***'
echo "   polecat-half (shared by all rigs): $p  $s"
for r in "${RIGS[@]}"; do
  b=$(git -C "$CITY/rigs/$r" rev-list --count HEAD..origin/main 2>/dev/null || echo '?')
  [ "$b" = "0" ] && s=ok || s="*** $b BEHIND — pull before trusting the above ***"
  echo "   $r rig-root: $s"
done

# --- 2. anchors past the cap --------------------------------------------------
# Rework children carry source_review_bead; one child per round by construction.
# Past the cap the anchor must be routed to human, NOT carrying a fresh child.
echo
echo "-- anchors at/over cap (should be routed to human, not spawning) --"
found=0
for r in "${RIGS[@]}"; do
  cd "$CITY/rigs/$r" 2>/dev/null || continue
  for a in $(bd list --status=open --json 2>/dev/null | sed -n '/^[[{]/,$p' \
             | jq -r '.[] | select(.metadata.merge_result != null) | .id' 2>/dev/null); do
    n=$(bd dep list "$a" --direction=up -t parent-child --json 2>/dev/null \
        | jq '[.[] | select(.metadata.source_review_bead != null)] | length' 2>/dev/null || echo 0)
    if [ "${n:-0}" -ge "$CAP" ]; then
      routed=$(bd show "$a" --json 2>/dev/null | sed -n '/^[[{]/,$p' | jq -r '.[0].metadata."gc.routed_to" // "none"' 2>/dev/null)
      # Three distinct states — do NOT collapse them. An anchor that accumulated
      # its rounds BEFORE the cap existed has not been through the cap yet, and
      # reads identically to one the cap failed on. Even an OPEN rework child is
      # innocent if it was minted before the cap landed. The only real failure is
      # a rework child created AFTER GC_CAP_LANDED_AT, which means something
      # spawned round N+1 with the cap in force.
      newer=$(bd dep list "$a" --direction=up -t parent-child --json 2>/dev/null \
        | jq --arg t "$CAP_LANDED" \
             '[.[] | select(.metadata.source_review_bead != null)
                   | select(.created_at > $t)] | length' 2>/dev/null || echo 0)
      if [ "${newer:-0}" -gt 0 ]; then
        verdict="*** SPAWNED PAST CAP ($newer child since cap landed) — investigate ***"
      elif [ "$routed" = "human" ]; then
        verdict="ok — cap fired, escalated"
      else
        verdict="pre-cap backlog — will trip the cap on next re-dispatch (expected)"
      fi
      echo "   $r/$a: $n rounds, routed_to=${routed:-none}, children since cap=$newer"
      echo "        $verdict"
      found=1
    fi
  done
done
[ "$found" -eq 0 ] && echo "   none"

# --- 3. codex reviews minted (Copilot budget) ---------------------------------
echo
echo "-- codex review beads (Copilot burn) --"
tot=0
for r in "${RIGS[@]}"; do
  cd "$CITY/rigs/$r" 2>/dev/null || continue
  o=$(bd list --status=open,in_progress --json 2>/dev/null | sed -n '/^[[{]/,$p' \
      | jq '[.[] | select(.metadata.task_kind == "review")] | length' 2>/dev/null || echo 0)
  echo "   $r: $o in flight"
  tot=$((tot + ${o:-0}))
done
echo "   TOTAL in flight: $tot   (pool ceiling is 2/rig = 8 concurrent)"

# --- 4. live polecat sessions (Claude burn rate) ------------------------------
# Count by TEMPLATE, never by session_name. Polecat session names carry the PACK
# prefix, not the rig: shutupandlisten's polecats are also named
# "gc-toolkit__polecat-*". Counting by name conflates rigs and reports 4 in
# gc-toolkit when it is 2 there and 2 in shutupandlisten. Cost me a false
# "the cap didn't load" on 2026-08-04.
echo
echo "-- live sessions --"
gc session list --json 2>/dev/null | sed -n '/^[[{]/,$p' | python3 -c "
import sys,json,collections
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
s=d.get('sessions',d) if isinstance(d,dict) else d
c=collections.Counter(x.get('template','(none)') for x in s)
tot=0
for k,v in sorted(c.items()):
    if 'polecat' in k:
        flag='  *** OVER CAP ***' if v>2 else ''
        print(f'   {v}  {k}{flag}')
        tot+=v
print(f'   -- {tot} polecat+codex sessions, {len(s)} sessions total')
" 2>/dev/null
echo "   claude procs: $(pgrep -xc claude 2>/dev/null || echo 0)"
echo "   codex procs:  $(pgrep -xc codex 2>/dev/null || echo 0)"
echo "   load:         $(cut -d' ' -f1-3 /proc/loadavg)"
# The running supervisor's own view. This is the ONLY check that proves the
# daemon loaded the cap -- gc config show re-parses city.toml from disk and so
# proves nothing about the live process. A poolDesired of 2 against a backlog
# of 100 ready beads is the cap binding; 5 would mean it is not.
echo
echo "-- supervisor's desired polecat pool sizes (live daemon view) --"
grep 'poolDesired.*polecat' "${HOME}/.gc/supervisor.log" 2>/dev/null | tail -8 | sed 's/^/   /' || echo "   (no log)"

echo
echo "=== thresholds ==="
echo "  ANY 'NOT LOADED' or 'BEHIND'      -> stop; the cap is not protecting you"
echo "  ANY 'SPAWNED PAST CAP'            -> cap is broken; suspend and investigate"
echo "  'pre-cap backlog' entries         -> expected once each; must become"
echo "                                       'cap fired, escalated', and must not recur"
echo "  codex in flight > 8 sustained     -> pool cap is being bypassed (2/rig x 4)"
echo "  ANY pool 'OVER CAP' above         -> the throttle is not binding; investigate"
echo "  poolDesired polecat = 5           -> daemon has the OLD config; restart it"
echo "  claude procs > ~34 sustained      -> measured 24 on 2026-08-04 with 6 polecats"
echo "                                       live and 28 sessions. The non-polecat"
echo "                                       roster alone (4 witness, 4 refinery, 4"
echo "                                       dispatcher, mayor/boot/deacon/dog/"
echo "                                       mechanik, bead-hosts, mayor-threads) is"
echo "                                       ~18-22, so a low threshold here is all"
echo "                                       false alarms. Ceiling = that + 16."
echo "                                       Trust the per-pool counts, not this."
