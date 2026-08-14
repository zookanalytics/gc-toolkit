#!/usr/bin/env bash
# Hermetic test for gc-visit-open.sh — the operator-origin visit intake
# (tk-4ojka). Runs the REAL script (via `sh`, as shipped) with `gc`,
# `gc-helm.sh` and `gc-proactive.sh` stubbed on PATH — no live city, Dolt,
# network, or sessions.
#
# What the cases are guarding, and why each one was worth a test:
#
#   (DIRECT)    --no-react files the visit NOW, through gc-helm.sh open —
#               the script must never hand-roll a gate-visit block of its own.
#   (SINGLE)    the react path files NO visit: mol-first-reaction's
#               advance-and-drain step files it, and a second one would split
#               the conversation into two sittings of the same subject.
#   (SHED)      the whole reason the fallback exists. `gc sling` is
#               fire-and-forget and returns 0 whether or not anything will
#               ever pick the bead up, so an unguarded react path leaves the
#               topic routed, unclaimed, and WITHOUT a visit — filed-looking
#               and silently forgotten. Both clamps that cause it (auto-spawn
#               disabled — the DEFAULT — and the city session cap) are asked
#               about up front, and a "no" must divert to the direct path.
#   (RECOVER)   a react path that fails outright still ends in a visit rather
#               than a subject bead nobody is coming to.
#   (RIG)       the default rig is FIXED (gc-toolkit), never inferred from
#               cwd: this is fired from wherever the operator is sitting, and
#               a silently varying destination is the worst failure mode an
#               intake path can have. An unknown --rig files nothing.
#   (SUBJECT)   an existing bead is its own subject — no second bead is
#               minted — and a contradictory --rig/--type is refused rather
#               than ignored.
#   (SHAPE)     "dolt-latency" is a topic, "tk-abc12" is a bead id, and the
#               difference is the RIG PREFIX, not the hyphen. A prefix-shaped
#               string no ledger answers for must not become a bead literally
#               titled "tk-abc12".
#   (TYPE)      a question becomes a decision bead; --type overrides.
#   (FAILCLOSE) a subject that could not be created files no visit, and a
#               missing argument creates nothing at all.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-visit-open.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -qF -- "$2" <<< "$1" && ok "$3" || bad "$3 (in: $1)"; }
hasnt() { grep -qF -- "$2" <<< "$1" && bad "$3 (in: $1)" || ok "$3"; }

[ -f "$SCRIPT" ] && ok "gc-visit-open.sh present" || { bad "gc-visit-open.sh missing at $SCRIPT"; exit 1; }

mkdir -p "$TMP/bin" "$TMP/rigs/gc-toolkit/.beads" "$TMP/rigs/gascity/.beads"

# --- gc stub -----------------------------------------------------------------
# Two rigs, so "which ledger" is a real question the test can check. Every
# mutating call is appended to $FAKE_CALLS so "nothing was created" is asserted
# against the actual argv, not against exit status alone.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "rig list")
    jq -n --arg t "$FAKE_RIGS/gc-toolkit" --arg g "$FAKE_RIGS/gascity" \
      '{rigs:[{name:"gc-toolkit", path:$t, prefix:"tk"},
              {name:"gascity",    path:$g, prefix:"gc"}]}' ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$FAKE_CALLS"
    if [ -n "${FAKE_CREATE_FAIL:-}" ]; then printf '{"error":"nope"}\n'; exit 1; fi
    jq -n '{id:"tk-newsub"}' ;;
esac
exit 0
GC

# --- gc-helm.sh stub ----------------------------------------------------------
# Records the verb and argv; $FAKE_HELM_RC drives the failure cases.
cat > "$TMP/bin/gc-helm.sh" <<'HELM'
#!/usr/bin/env bash
printf 'helm %s\n' "$*" >> "$FAKE_CALLS"
exit "${FAKE_HELM_RC:-0}"
HELM

# --- gc-proactive.sh stub -----------------------------------------------------
# $FAKE_DELIVERABLE picks which clamp answers: yes / disabled / cap.
cat > "$TMP/bin/gc-proactive.sh" <<'PRO'
#!/usr/bin/env bash
printf 'proactive %s\n' "$*" >> "$FAKE_CALLS"
case "${FAKE_DELIVERABLE:-yes}" in
  yes)      echo "yes: proactive enabled and under the city cap (3/20)"; exit 0 ;;
  disabled) echo "no: proactive auto-spawn is disabled (GC_PROACTIVE_ENABLED unset or not truthy) — a slung reaction would sit routed and unclaimed"; exit 1 ;;
  cap)      echo "no: city at session cap (20/20) — proactive sheds first under session pressure"; exit 1 ;;
esac
PRO

chmod +x "$TMP/bin/gc" "$TMP/bin/gc-helm.sh" "$TMP/bin/gc-proactive.sh"

export PATH="$TMP/bin:$PATH"
export FAKE_CALLS="$TMP/calls"
export FAKE_RIGS="$TMP/rigs"
export GC_HELM_TOOL="$TMP/bin/gc-helm.sh"
export GC_PROACTIVE_TOOL="$TMP/bin/gc-proactive.sh"
export TMPDIR="$TMP"

# run <deliverable> [args...] -> sets RC/OUT/ERR/CALLS
run() {
    : > "$FAKE_CALLS"
    export FAKE_DELIVERABLE="$1"; shift
    set +e
    OUT="$(sh "$SCRIPT" "$@" 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"
    CALLS="$(cat "$FAKE_CALLS")"
}

# --- (DIRECT) --no-react files the visit now, via gc-helm.sh open ------------
# A positive control first: a script that refused everything would satisfy
# every fail-closed assertion below while delivering nothing.
run yes "why is dolt wedging under load" --no-react
eq "$RC" "0" "(DIRECT) --no-react exits 0"
has "$CALLS" "bd create -t task --title why is dolt wedging under load" "(DIRECT) subject bead created from the topic"
has "$CALLS" "helm open tk-newsub" "(DIRECT) the visit is filed through gc-helm.sh open"
has "$CALLS" "--reason operator-origin topic intake" "(DIRECT) the visit says what it is actually for"
has "$CALLS" "--body" "(DIRECT) the claim-time brief is supplied"
hasnt "$CALLS" "helm react" "(DIRECT) no first reaction is slung"
has "$OUT" "visit filed" "(DIRECT) the summary reports a filed visit"
has "$OUT" "tk-newsub" "(DIRECT) the summary names the subject id"

# The subject body carries the topic as a durable seed, not just a title —
# the converse session reads the BODY at claim time.
has "$CALLS" "-d why is dolt wedging under load" "(DIRECT) the topic is the subject's durable body too"

# --- (SINGLE) the react path files NO visit ----------------------------------
run yes "how should we shard the refinery queue"
eq "$RC" "0" "(SINGLE) the react path exits 0"
has "$CALLS" "helm react tk-newsub" "(SINGLE) the first reaction is slung at the new subject"
hasnt "$CALLS" "helm open" "(SINGLE) no visit is filed — the reaction files it"
has "$OUT" "not filed yet" "(SINGLE) the operator is told the visit does not exist yet"
has "$OUT" "--no-react" "(SINGLE) and is told how to get the conversation now"

# --- (SHED) an undeliverable proactive surface diverts to the direct path ----
for why in disabled cap; do
    run "$why" "what should the deacon do about quota parks"
    eq "$RC" "0" "(SHED/$why) exits 0"
    hasnt "$CALLS" "helm react" "(SHED/$why) nothing is slung at a pool that cannot run it"
    has "$CALLS" "helm open tk-newsub" "(SHED/$why) the visit is filed directly instead"
    has "$OUT" "visit filed" "(SHED/$why) the summary reports a filed visit"
done
run disabled "a topic"
has "$OUT" "auto-spawn is disabled" "(SHED) the summary relays WHICH clamp said no"
run cap "a topic"
has "$OUT" "session cap" "(SHED) the cap answer is relayed verbatim too"

# A proactive tool that is missing entirely is the same situation: no reaction
# is coming, so the visit must be filed rather than waited for.
: > "$FAKE_CALLS"
set +e
OUT="$(GC_PROACTIVE_TOOL="$TMP/bin/nonexistent.sh" sh "$SCRIPT" "a topic" 2>"$TMP/err")"; RC=$?
set -e
CALLS="$(cat "$FAKE_CALLS")"
eq "$RC" "0" "(SHED/missing) a missing gc-proactive.sh still exits 0"
has "$CALLS" "helm open tk-newsub" "(SHED/missing) the visit is filed directly"

# --- (RECOVER) a failed sling still ends in a conversation --------------------
run yes "a topic that fails to sling"
FAKE_HELM_RC=4 run yes "a topic that fails to sling"
# helm is stubbed to fail for BOTH verbs here, so the run ends in the die() —
# what matters is that it TRIED the direct path after react failed.
has "$CALLS" "helm react tk-newsub" "(RECOVER) react was attempted"
has "$CALLS" "helm open tk-newsub" "(RECOVER) a failed react falls through to filing the visit"
has "$ERR" "falling back" "(RECOVER) the fallback is announced, not silent"
eq "$RC" "4" "(RECOVER) a direct path that also fails exits 4"
unset FAKE_HELM_RC

# --- (RIG) the default rig is fixed; --rig retargets; unknown rigs file nothing
run disabled "some cross-cutting topic"
has "$CALLS" "--db $TMP/rigs/gc-toolkit/.beads" "(RIG) the default rig is gc-toolkit, not inferred from cwd"
run disabled "a gascity topic" --rig gascity
has "$CALLS" "--db $TMP/rigs/gascity/.beads" "(RIG) --rig retargets the ledger"
run disabled "a topic" --rig nosuchrig
eq "$RC" "2" "(RIG) an unknown rig is a usage error"
eq "$CALLS" "" "(RIG) an unknown rig creates nothing and files nothing"
has "$ERR" "unknown rig" "(RIG) the error names the problem"
# die() takes the exit code as its SECOND argument; a $*-joined message printed
# it as trailing noise ("… shutupandlisten) 2"). Caught live, not by the
# substring assertion above — so assert the whole line, not a fragment.
[[ "$ERR" =~ \)$ ]] && ok "(RIG) the exit code does not leak into the message" \
    || bad "(RIG) the exit code leaks into the message (got: $ERR)"
# The env override exists so a differently-shaped city can move the default
# without editing the script.
: > "$FAKE_CALLS"
set +e
GC_VISIT_DEFAULT_RIG=gascity FAKE_DELIVERABLE=disabled sh "$SCRIPT" "a topic" >/dev/null 2>&1
set -e
has "$(cat "$FAKE_CALLS")" "--db $TMP/rigs/gascity/.beads" "(RIG) GC_VISIT_DEFAULT_RIG moves the default"

# --- (SUBJECT) an existing bead is its own subject ----------------------------
run disabled tk-abc12
eq "$RC" "0" "(SUBJECT) an existing bead id exits 0"
hasnt "$CALLS" "bd create" "(SUBJECT) no second bead is minted for an existing subject"
has "$CALLS" "helm open tk-abc12" "(SUBJECT) the visit is filed on the bead itself"
run disabled tk-abc12 --rig gascity
eq "$RC" "2" "(SUBJECT) --rig on an existing bead is refused, not ignored"
eq "$CALLS" "" "(SUBJECT) and files nothing"
run disabled tk-abc12 --type decision
eq "$RC" "2" "(SUBJECT) --type on an existing bead is refused"

# --- (SHAPE) prefix, not hyphen, decides id-vs-topic --------------------------
run disabled "dolt-latency"
has "$CALLS" "bd create" "(SHAPE) a hyphenated word whose prefix matches no rig is a topic"
has "$CALLS" "--title dolt-latency" "(SHAPE) and keeps its literal text"
run disabled "tk-abc12" --topic
has "$CALLS" "bd create" "(SHAPE) --topic forces a bead-shaped string to be a topic"
run disabled "gc-toolkit is slow"
has "$CALLS" "bd create" "(SHAPE) a multi-word string starting with a rig prefix is still a topic"

# --- (TYPE) a question is a decision -----------------------------------------
run disabled "should the refinery land siblings in one pass?"
has "$CALLS" "bd create -t decision" "(TYPE) a topic ending in ? becomes a decision bead"
run disabled "rework the refinery sibling pass"
has "$CALLS" "bd create -t task" "(TYPE) everything else is a task"
run disabled "should we do this?" --type task
has "$CALLS" "bd create -t task" "(TYPE) --type overrides the heuristic"

# --- (FAILCLOSE) nothing half-filed -------------------------------------------
: > "$FAKE_CALLS"
set +e
OUT="$(FAKE_CREATE_FAIL=1 FAKE_DELIVERABLE=disabled sh "$SCRIPT" "a topic" 2>"$TMP/err")"; RC=$?
set -e
CALLS="$(cat "$FAKE_CALLS")"; ERR="$(cat "$TMP/err")"
eq "$RC" "4" "(FAILCLOSE) a subject that cannot be created exits 4"
hasnt "$CALLS" "helm open" "(FAILCLOSE) and files no visit"
has "$ERR" "nothing filed" "(FAILCLOSE) the message says nothing was filed"

run disabled
eq "$RC" "2" "(FAILCLOSE) no argument is a usage error"
eq "$CALLS" "" "(FAILCLOSE) and creates nothing"
run disabled "a topic" --bogus
eq "$RC" "2" "(FAILCLOSE) an unknown flag is a usage error"
eq "$CALLS" "" "(FAILCLOSE) and creates nothing"
run disabled "topic one" "topic two"
eq "$RC" "2" "(FAILCLOSE) two positionals are a usage error (quote the topic)"
eq "$CALLS" "" "(FAILCLOSE) and create nothing"

# --- (HELP/SYNTAX) ------------------------------------------------------------
run yes --help
eq "$RC" "0" "(HELP) --help exits 0"
eq "$CALLS" "" "(HELP) --help touches nothing"
sh -n "$SCRIPT" 2>/dev/null && ok "(SYNTAX) gc-visit-open.sh parses as POSIX sh" || bad "(SYNTAX) sh -n failed"

echo ""
echo "gc-visit-open operator intake: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
