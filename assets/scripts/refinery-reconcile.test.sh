#!/usr/bin/env bash
# Hermetic test for refinery-reconcile.sh — the merge-cadence pass runner that
# replaced the per-rig /tmp idle driver (tk-d83wm).
#
# Stub pass scripts stand in for the seven real ones, recording their argv; a
# fake `gc` serves the agent roster and the bead listing; a fake `git` answers
# the ls-remote gate. No live city, no Dolt, no network, no systemd.
#
# Covers: (a) every pass runs, in the formula's order, on one invocation;
# (b) there is no loop and no sleep — the cadence belongs to the order;
# (c) the refinery identity and BOTH pool addresses are derived from one
# discovery, so they cannot disagree; (d) check-set-heal rc=3 HOLDS merge-skill
# for that pass and is reported without failing the order — an approval-gated
# queue must not raise order.failed every cooldown; (e) any other non-zero pass
# rc fails the order, and every LATER pass still runs; (f) a missing pass script
# is skipped, not fatal; (g) GC_RIG absent is refused rather than guessed;
# (h) the state dir is keyed per rig, so co-tenant rigs cannot share a handoff
# dedup; (i) the fresh-handoff detector gates on the branch existing on origin,
# reports each id once, and re-reports one that returns; (j) an anchored bead is
# never reported as a lost handoff; (k) the pass log is bounded; (l) the order
# file parses and still carries the wiring the runner depends on.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/refinery-reconcile.sh"
ORDER="$HERE/../../orders/refinery-reconcile.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
# Here-strings, not pipes: `grep -q` exits at its first match and SIGPIPEs the
# writer, and pipefail promotes that 141 to the pipeline's status — so a match
# that SUCCEEDED takes the failure branch once the payload is big enough to
# still be flushing. doctor/check-pipefail-grep-q is the standing gate on this.
has() { grep -qF -- "$2" <<< "$1" && ok "$3" || bad "$3" "missing '$2'"; }
hasnt() { grep -qF -- "$2" <<< "$1" && bad "$3" "unexpected '$2'" || ok "$3"; }

# --- a pack dir holding stub passes next to the real runner ------------------
PACK="$TMP/pack"; mkdir -p "$PACK/assets/scripts" "$TMP/bin" "$TMP/state" "$TMP/rigroot"
cp "$SCRIPT" "$PACK/assets/scripts/refinery-reconcile.sh"
RUNNER="$PACK/assets/scripts/refinery-reconcile.sh"

PASSES="reconcile-refinery-handoffs check-set-heal pre-open-resolve merge-skill reconcile-merged-prs reconcile-gate-verdicts reconcile-graduated-convoys"

# Stub pass: appends "<name> <argv...>" to the trace, exits with the rc named in
# $TMP/rc.<name> (default 0).
mkstub() { # name
    cat > "$PACK/assets/scripts/$1.sh" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$1" "\$*" >> "$TMP/trace"
rcfile="$TMP/rc.$1"
[ -f "\$rcfile" ] && exit "\$(cat "\$rcfile")"
exit 0
STUB
    chmod +x "$PACK/assets/scripts/$1.sh"
}
mkstubs() { for p in $PASSES; do mkstub "$p"; done; }
mkstubs

# --- fake gc: agent roster + bead listing ------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "agent list")
    cat "$GCSTUB_AGENTS"
    ;;
  "bd list")
    cat "$GCSTUB_BEADS"
    ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# --- fake git: ls-remote answers from a list of branches that "exist" --------
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in refs/heads/*)
    grep -qxF "${a#refs/heads/}" "$GITSTUB_BRANCHES" 2>/dev/null && exit 0 || exit 2 ;;
  esac
done
exit 0
GIT
chmod +x "$TMP/bin/git"

cat > "$TMP/agents.json" <<'JSON'
{"agents":[
 {"name":"polecat","qualified_name":"alpha/gc-toolkit.polecat"},
 {"name":"refinery","qualified_name":"alpha/gc-toolkit.refinery"},
 {"name":"refinery","qualified_name":"beta/gc-toolkit.refinery"}
]}
JSON
: > "$TMP/beads-empty.json"; echo '[]' > "$TMP/beads-empty.json"
: > "$TMP/branches"

export GCSTUB_AGENTS="$TMP/agents.json"
export GCSTUB_BEADS="$TMP/beads-empty.json"
export GITSTUB_BRANCHES="$TMP/branches"

run() { # [env assignments handled by caller]; runs the runner, captures out+rc
    : > "$TMP/trace"
    OUT="$(PATH="$TMP/bin:$PATH" \
        GC_RIG="${RIG_OVERRIDE-alpha}" \
        GC_RIG_ROOT="$TMP/rigroot" \
        GC_PACK_STATE_DIR="$TMP/state" \
        "$RUNNER" 2>&1)"
    RC=$?
    TRACE="$(cat "$TMP/trace" 2>/dev/null)"
}

# --- 1. every pass runs, in the formula's order ------------------------------
echo "── 1. the pass set ──"
rm -f "$TMP"/rc.*
run
eq "$RC" 0 "(1) a clean pass exits 0"
ORDER_SEEN="$(printf '%s\n' "$TRACE" | awk '{print $1}' | paste -sd, -)"
eq "$ORDER_SEEN" \
   "reconcile-refinery-handoffs,check-set-heal,pre-open-resolve,merge-skill,reconcile-merged-prs,reconcile-gate-verdicts,reconcile-graduated-convoys" \
   "(2) all seven passes ran, in the formula's order"

# --- 2. no loop, no sleep ----------------------------------------------------
echo "── 2. the cadence is the order's, not the script's ──"
COUNT="$(printf '%s\n' "$TRACE" | grep -c '^merge-skill ')"
eq "$COUNT" 1 "(3) one invocation runs the pass set exactly once"
grep -qE '^[[:space:]]*sleep ' "$SCRIPT" \
    && bad "(4) the runner contains no sleep" "found a sleep" \
    || ok "(4) the runner contains no sleep"
grep -qE '^[[:space:]]*while true' "$SCRIPT" \
    && bad "(5) the runner contains no unbounded loop" "found while true" \
    || ok "(5) the runner contains no unbounded loop"
grep -q 'flock' "$SCRIPT" \
    && bad "(6) no flock — the controller's open-tracking gate is the single-flight" "found flock" \
    || ok "(6) no flock — the controller's open-tracking gate is the single-flight"

# --- 3. one discovery drives all three addresses -----------------------------
echo "── 3. identity ──"
has "$TRACE" "--refinery alpha/gc-toolkit.refinery" "(7) the handoff pass gets the discovered refinery address"
has "$TRACE" "--fix-pool alpha/gc-toolkit.polecat"  "(8) the fix pool shares the discovered binding prefix"
has "$TRACE" "--review-pool alpha/gc-toolkit.polecat-codex" "(9) the review pool shares it too"
hasnt "$TRACE" "beta/" "(10) another rig's refinery is never addressed"

# An unbound refinery ("<rig>/refinery") yields an empty prefix, not a literal.
cat > "$TMP/agents-bare.json" <<'JSON'
{"agents":[{"name":"refinery","qualified_name":"alpha/refinery"}]}
JSON
GCSTUB_AGENTS="$TMP/agents-bare.json" run
has "$TRACE" "--fix-pool alpha/polecat" "(11) an unbound refinery yields unprefixed pools, not a literal prefix"
GCSTUB_AGENTS="$TMP/agents.json"

# --- 4. the heal gate --------------------------------------------------------
echo "── 4. check-set-heal gates merge-skill ──"
echo 3 > "$TMP/rc.check-set-heal"
run
eq "$RC" 0 "(12) rc=3 is a designed HOLD, not an order failure"
hasnt "$TRACE" "merge-skill " "(13) merge-skill is HELD for the pass"
has "$OUT" "UNSAFE" "(14) the hold is reported on stdout"
has "$TRACE" "reconcile-merged-prs " "(15) the passes after the hold still run"

echo 1 > "$TMP/rc.check-set-heal"
run
eq "$RC" 1 "(16) any other non-zero heal rc fails the order"
has "$TRACE" "merge-skill " "(17) a plain heal failure does NOT hold merge-skill"
rm -f "$TMP/rc.check-set-heal"

# --- 5. a failing pass never skips the passes after it -----------------------
echo "── 5. best-effort ──"
echo 4 > "$TMP/rc.pre-open-resolve"
run
eq "$RC" 1 "(18) a failing pass fails the order, so it reaches order.failed"
has "$OUT" "pre-open-resolve rc=4" "(19) the failing pass is named for the event excerpt"
has "$TRACE" "merge-skill " "(20) later passes still run"
has "$TRACE" "reconcile-graduated-convoys " "(21) including the last one"
rm -f "$TMP/rc.pre-open-resolve"

echo "── 6. a missing pass script ──"
rm -f "$PACK/assets/scripts/reconcile-gate-verdicts.sh"
run
eq "$RC" 0 "(22) an absent pass is skipped, not fatal (older pack copies lack newer arms)"
has "$TRACE" "reconcile-graduated-convoys " "(23) the pass after it still runs"
mkstub reconcile-gate-verdicts

# --- 7. no rig is a refusal, not a guess -------------------------------------
echo "── 7. rig scoping ──"
RIG_OVERRIDE="" run
eq "$RC" 2 "(24) GC_RIG unset is refused"
eq "$TRACE" "" "(25) nothing ran against an unnamed rig"
unset RIG_OVERRIDE

RIG_OVERRIDE=beta run
[ -d "$TMP/state/refinery-reconcile/beta" ] && [ -d "$TMP/state/refinery-reconcile/alpha" ] \
    && ok "(26) each rig keys its own state dir under one CITY+PACK state root" \
    || bad "(26) each rig keys its own state dir under one CITY+PACK state root" \
           "$(ls "$TMP/state/refinery-reconcile" 2>&1 | tr '\n' ' ')"
unset RIG_OVERRIDE

# --- 7b. the graduation target is this rig's own, not a shared constant -------
echo "── 7b. graduation target ──"
cat > "$TMP/bin/git" <<'GIT2'
#!/usr/bin/env bash
if [ "${3:-}" = "symbolic-ref" ]; then
  [ -n "${GITSTUB_HEAD:-}" ] && { printf '%s
' "$GITSTUB_HEAD"; exit 0; }
  exit 1
fi
for a in "$@"; do
  case "$a" in refs/heads/*)
    grep -qxF "${a#refs/heads/}" "$GITSTUB_BRANCHES" 2>/dev/null && exit 0 || exit 2 ;;
  esac
done
exit 0
GIT2
chmod +x "$TMP/bin/git"
GITSTUB_HEAD="origin/trunk" run
has "$TRACE" "--target trunk" "(26b) the target comes from this rig's origin/HEAD, not a shared constant"
GITSTUB_HEAD="" run
has "$TRACE" "--target main" "(26c) an unreadable origin/HEAD falls back to main (the old drivers' hardcoded value)"
: > "$TMP/trace"
OUT="$(PATH="$TMP/bin:$PATH" GC_RIG=alpha GC_RIG_ROOT="$TMP/rigroot" \
  GC_PACK_STATE_DIR="$TMP/state" REFINERY_RECONCILE_TARGET=release \
  GITSTUB_HEAD=origin/trunk "$RUNNER" 2>&1)"
has "$(cat "$TMP/trace")" "--target release" "(26d) an explicit override still wins"
unset GITSTUB_HEAD

# --- 8. the fresh-handoff detector -------------------------------------------
echo "── 8. fresh-handoff detector ──"
cat > "$TMP/beads.json" <<'JSON'
[
 {"id":"tk-pushed","assignee":"","metadata":{"branch":"polecat/tk-pushed","gc.routed_to":""}},
 {"id":"tk-unpushed","assignee":"","metadata":{"branch":"polecat/tk-unpushed","gc.routed_to":""}},
 {"id":"tk-anchored","assignee":"","metadata":{"branch":"polecat/tk-anchored","gc.routed_to":"","merge_result":"pull_request"}},
 {"id":"tk-someone","assignee":"alpha/gc-toolkit.polecat","metadata":{"branch":"polecat/tk-someone","gc.routed_to":"alpha/gc-toolkit.polecat"}}
]
JSON
echo "polecat/tk-pushed"   >  "$TMP/branches"
echo "polecat/tk-anchored" >> "$TMP/branches"
echo "polecat/tk-someone"  >> "$TMP/branches"
GCSTUB_BEADS="$TMP/beads.json"

run
has  "$OUT" "FRESH HANDOFF" "(27) a pushed, unanchored, unowned branch is reported"
has  "$OUT" "tk-pushed"     "(28) by id"
hasnt "$OUT" "tk-unpushed"  "(29) a bead whose branch is not on origin is live WIP, not a lost handoff"
hasnt "$OUT" "tk-anchored"  "(30) an anchored bead belongs to the passes, not the detector"
hasnt "$OUT" "tk-someone"   "(31) a bead someone else holds is not a lost handoff"
eq "$RC" 0 "(32) a fresh handoff is news, not a failure"

run
hasnt "$OUT" "FRESH HANDOFF" "(33) the same id is not re-reported on the next pass"

echo "polecat/tk-unpushed" >> "$TMP/branches"
run
has "$OUT" "tk-unpushed" "(34) a branch that appears later IS reported then"
hasnt "$OUT" "tk-pushed" "(35) and the already-seen id stays quiet"

GCSTUB_BEADS="$TMP/beads-empty.json"

# --- 9. the log is bounded ---------------------------------------------------
echo "── 9. the pass log ──"
LOG="$TMP/state/refinery-reconcile/alpha/pass.log"
[ -s "$LOG" ] && ok "(36) the pass writes a durable log under the pack state dir" \
              || bad "(36) the pass writes a durable log under the pack state dir"
for _ in 1 2 3; do
    OUT="$(PATH="$TMP/bin:$PATH" GC_RIG=alpha GC_RIG_ROOT="$TMP/rigroot" \
        GC_PACK_STATE_DIR="$TMP/state" REFINERY_RECONCILE_LOG_KEEP=5 "$RUNNER" 2>&1)"
done
LINES="$(wc -l < "$LOG" | tr -d ' ')"
[ "$LINES" -le 5 ] && ok "(37) the log is trimmed to LOG_KEEP lines" \
                   || bad "(37) the log is trimmed to LOG_KEEP lines" "got $LINES"

# --- 10. the order that drives it --------------------------------------------
echo "── 10. the order ──"
if command -v python3 >/dev/null 2>&1; then
    ORDER_JSON="$(python3 - "$ORDER" <<'PY'
import json,sys,tomllib
d=tomllib.load(open(sys.argv[1],'rb'))['order']
print(json.dumps(d))
PY
)" || ORDER_JSON=""
    [ -n "$ORDER_JSON" ] && ok "(38) orders/refinery-reconcile.toml parses as TOML" \
                         || bad "(38) orders/refinery-reconcile.toml parses as TOML"
    has "$ORDER_JSON" '"scope": "rig"' "(39) scope=rig — one registration, and one single-flight gate, per rig"
    has "$ORDER_JSON" '"trigger": "cooldown"' "(40) cooldown is the cadence"
    has "$ORDER_JSON" 'refinery-reconcile.sh' "(41) it execs this runner"
    hasnt "$ORDER_JSON" 'no_work_gate' "(42) no_work_gate is NOT set — it would disable the single-flight gate"
    # timeout must stay under core order-tracking-sweep's --stale-after 10m, or a
    # wedged pass has its tracking bead swept and a second dispatch starts.
    TMO="$(printf '%s' "$ORDER_JSON" | sed -n 's/.*"timeout": "\([^"]*\)".*/\1/p')"
    case "$TMO" in
        *s) SECS="${TMO%s}" ;;
        *m) SECS=$(( ${TMO%m} * 60 )) ;;
        *)  SECS=99999 ;;
    esac
    [ "$SECS" -gt 0 ] && [ "$SECS" -lt 600 ] \
        && ok "(43) timeout ($TMO) stays under order-tracking-sweep's 10m stale window" \
        || bad "(43) timeout ($TMO) stays under order-tracking-sweep's 10m stale window"
else
    echo "skip - python3 absent; order-file assertions not run"
fi

echo
echo "refinery-reconcile.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
