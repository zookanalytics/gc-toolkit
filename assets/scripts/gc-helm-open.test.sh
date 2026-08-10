#!/usr/bin/env bash
# Hermetic test for the gc-helm `open` subject-existence gate (tk-ujwvt).
#
# THE BUG: `gc-helm open <bead-id>` resolved the id PREFIX to a rig, pointed bd
# at that rig's ledger, and then filed a visit — never confirming the bead
# actually resolves there. A typo or a stale id produced a REAL visit bead,
# routed to the rig converse pool with gc.continuation_group=<the typo>. Pool
# demand then spawns a converse session whose prime step (`gc bd show $SUBJECT`)
# cannot resolve anything, so it holds a conversation about a bead that does not
# exist. Reproduced 2026-08-09 in signal-loom: `gc-helm open sl-nope1` filed a
# visit and exited 0. This is the operator front door for the visit spine, so a
# fat-fingered id manufactures junk work and an agent to hold it.
#
# THE FIX: resolve the subject (`gc bd show`) BEFORE the gate-visit block and
# exit 4 ("verb runtime failure", the documented bead-not-found code) with
# nothing filed. Fail CLOSED on every unhappy reading — the only alternative is
# filing a visit on an unverified subject, which is the bug.
#
# This test runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a
# stubbed `gc` on PATH — no live city, Dolt, network, or sessions. Covered:
#   (EXISTS)   a resolvable subject still files the visit: create + all three
#              stamps + the tracks edge, exit 0 (the gate does not break `open`)
#   (HELD)     an already-open visit short-circuits, exit 0, nothing created
#   (MISSING)  bd show's `{"error": …}` OBJECT answer -> exit 4, NOTHING filed
#   (SHAPE)    that object shape never crashes jq into a false "found"
#   (MISMATCH) bd show answering a DIFFERENT bead -> exit 4, nothing filed
#              (the visit is keyed by the literal id typed, so a near-miss
#              would file a visit nothing can resolve)
#   (NORIG)    an id prefix matching no rig -> exit 4 naming the prefix
#   (DOWN)     an empty answer (wedged data plane) -> exit 4, message says
#              "could not verify", NOT "bead not found" — different operator move
#   (CTRLCHR)  control chars in the payload (invalid --json) never read as
#              "missing" when the bead is really there
#   (ORDER)    static: the gate precedes the gate-visit block in the source
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- gc stub ------------------------------------------------------------------
# One rig (prefix tk). `bd show` answers from $FAKE_SHOW_MODE so each case can
# pick the exact payload shape the real `bd show` emits for that reading.
# Every mutating call is appended to $FAKE_CALLS so "nothing was filed" is
# asserted against the actual argv, not against exit status alone.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "rig list")
    # Path has no .beads dir, so gc-helm resolves db="" and issues un-scoped
    # bd calls (the stub ignores --db). Only the prefix mapping matters here.
    jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd show")
    case "$FAKE_SHOW_MODE" in
      found)     jq -n --arg i "$3" '[{id:$i, title:"a real bead", status:"open"}]' ;;
      # The REAL not-found answer: a bare object, not an array, exit 1.
      missing)   printf '{\n  "error": "no issues found matching the provided IDs",\n  "schema_version": 1\n}\n'; exit 1 ;;
      # Resolves, but to some OTHER bead than the one typed.
      mismatch)  jq -n '[{id:"tk-somethingelse", title:"a different bead"}]' ;;
      # Wedged data plane: nothing at all on stdout.
      down)      exit 1 ;;
      # Wedged data plane that DOES answer — same error channel as not-found,
      # different error. Existence is unknown, not disproved.
      dberror)   printf '{"error":"dial tcp 127.0.0.1:3307: connect: connection refused","schema_version":1}\n'; exit 1 ;;
      # A real bead whose notes carry raw control chars (invalid --json).
      ctrlchr)   printf '[{"id":"%s","title":"ctl\002chars","notes":"a\001b"}]\n' "$3" ;;
    esac ;;
  "bd list")
    # The already-held lookup. $FAKE_VISIT set => one open visit on the subject.
    if [ -n "${FAKE_VISIT:-}" ]; then
      jq -n --arg v "$FAKE_VISIT" --arg s "$FAKE_SUBJECT" \
        '[{id:$v, metadata:{task_kind:"visit","gc.continuation_group":$s}}]'
    else printf '[]\n'; fi ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$FAKE_CALLS"
    jq -n '{id:"tk-visit1"}' ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$FAKE_CALLS" ;;
  "bd dep")
    printf 'bd dep %s\n' "$*" >> "$FAKE_CALLS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_CALLS="$TMP/calls"
# Neutralize any inherited helm fixture hook so enumerate_rigs uses the stub.
unset GC_HELM_FIXTURE || true
# Keep the cache out of the operator's real cache dir.
export TMPDIR="$TMP"

# run_open <show-mode> <bead-id> [visit-id] -> sets RC/OUT/ERR/CALLS
run_open() {
    : > "$FAKE_CALLS"
    export FAKE_SHOW_MODE="$1" FAKE_SUBJECT="$2" FAKE_VISIT="${3:-}"
    set +e
    OUT="$(sh "$SCRIPT" open "$2" 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"
    CALLS="$(cat "$FAKE_CALLS")"
}

# --- (EXISTS) the happy path still works --------------------------------------
# A positive control first: a gate that rejects everything would pass every
# fail-closed assertion below while breaking the verb outright.
run_open found tk-real1
eq "$RC" "0" "(EXISTS) a resolvable subject exits 0"
# The stub records `$*`, so quoting is flattened — match the argv words.
printf '%s' "$CALLS" | grep -q 'bd create .*--title visit: tk-real1' \
  && ok "(EXISTS) the visit bead is created" || bad "(EXISTS) visit created (calls: $CALLS)"
printf '%s' "$CALLS" | grep -q 'gc.routed_to=gc-toolkit/gc-toolkit.converse' \
  && ok "(EXISTS) routed to the rig-qualified converse pool" || bad "(EXISTS) routed_to stamp (calls: $CALLS)"
printf '%s' "$CALLS" | grep -q 'gc.continuation_group=tk-real1' \
  && ok "(EXISTS) continuation_group stamped with the subject" || bad "(EXISTS) continuation_group stamp"
printf '%s' "$CALLS" | grep -q 'task_kind=visit' \
  && ok "(EXISTS) task_kind=visit stamped" || bad "(EXISTS) task_kind stamp"
printf '%s' "$CALLS" | grep -q 'bd dep add tk-visit1 tk-real1 --type=tracks' \
  && ok "(EXISTS) tracks edge wired to the subject" || bad "(EXISTS) tracks edge (calls: $CALLS)"

# --- (HELD) an existing open visit still short-circuits ------------------------
run_open found tk-real1 tk-visit0
eq "$RC" "0" "(HELD) an already-held subject exits 0"
printf '%s' "$OUT" | grep -q 'visit tk-visit0 is already open' \
  && ok "(HELD) prints the existing visit id" || bad "(HELD) existing visit reported (out: $OUT)"
[ -z "$CALLS" ] \
  && ok "(HELD) no second visit filed" || bad "(HELD) must not file a second visit (calls: $CALLS)"

# --- (MISSING) the bug: a typo must file NOTHING -------------------------------
run_open missing tk-nope1
eq "$RC" "4" "(MISSING) an unresolvable id exits 4 (verb runtime failure)"
[ -z "$CALLS" ] \
  && ok "(MISSING) NO visit bead created, routed, or wired — nothing filed" \
  || bad "(MISSING) filed something for a nonexistent bead (calls: $CALLS)"
printf '%s' "$ERR" | grep -q 'bead not found' \
  && ok "(MISSING) says 'bead not found'" || bad "(MISSING) message (err: $ERR)"
printf '%s' "$ERR" | grep -q "tk-nope1" \
  && ok "(MISSING) names the offending id" || bad "(MISSING) message names the id (err: $ERR)"
# (SHAPE) the not-found payload is an OBJECT, so a `.[]?|.id` probe would make jq
# error out rather than answer cleanly. Assert the gate never mistakes that for a
# resolved subject — i.e. it fails closed on the shape it meets in production.
printf '%s' "$OUT" | grep -q 'filed on' \
  && bad "(SHAPE) the {\"error\":…} object read as a resolved subject" \
  || ok "(SHAPE) the {\"error\":…} object never reads as resolved"

# --- (MISMATCH) resolving to a DIFFERENT bead is not a resolution --------------
run_open mismatch tk-typo9
eq "$RC" "4" "(MISMATCH) an answer for another bead exits 4"
[ -z "$CALLS" ] \
  && ok "(MISMATCH) nothing filed for a near-miss id" || bad "(MISMATCH) filed on a near-miss (calls: $CALLS)"

# --- (NORIG) an unknown id prefix ---------------------------------------------
run_open missing zz-1234
eq "$RC" "4" "(NORIG) an id whose prefix matches no rig exits 4"
[ -z "$CALLS" ] && ok "(NORIG) nothing filed" || bad "(NORIG) filed something (calls: $CALLS)"
printf '%s' "$ERR" | grep -q "prefix 'zz' matches no rig" \
  && ok "(NORIG) names the unmatched prefix (the actionable diagnostic)" \
  || bad "(NORIG) message names the prefix (err: $ERR)"

# --- (DOWN) a wedged data plane is not a typo ---------------------------------
run_open down tk-real1
eq "$RC" "4" "(DOWN) an empty answer exits 4 (fail closed — no visit on an unverified subject)"
[ -z "$CALLS" ] && ok "(DOWN) nothing filed" || bad "(DOWN) filed on an unverified subject (calls: $CALLS)"
printf '%s' "$ERR" | grep -q 'could not verify' \
  && ok "(DOWN) says 'could not verify', not 'bead not found'" \
  || bad "(DOWN) a data-plane outage must not be reported as a typo (err: $ERR)"

# --- (DBERROR) an error payload is not a missing bead -------------------------
# The failure mode this separates: a refused Dolt connection answers on the same
# error channel as not-found. Calling that "bead not found" sends the operator
# hunting a typo while the data plane is down.
run_open dberror tk-real1
eq "$RC" "4" "(DBERROR) an error payload exits 4 (fail closed)"
[ -z "$CALLS" ] && ok "(DBERROR) nothing filed" || bad "(DBERROR) filed on an unverified subject (calls: $CALLS)"
printf '%s' "$ERR" | grep -q 'could not verify' \
  && ok "(DBERROR) reported as unverifiable, not as a typo" \
  || bad "(DBERROR) a non-not-found error must not read as 'bead not found' (err: $ERR)"
printf '%s' "$ERR" | grep -q 'connection refused' \
  && ok "(DBERROR) surfaces the underlying error to the operator" \
  || bad "(DBERROR) message carries the underlying error (err: $ERR)"

# --- (CTRLCHR) invalid --json must not read as missing ------------------------
# Control chars in a bead's notes break `jq` outright; a real bead reported as
# "not found" would send the operator hunting a typo that does not exist.
run_open ctrlchr tk-real1
eq "$RC" "0" "(CTRLCHR) a real bead with control chars in its payload still resolves"
printf '%s' "$CALLS" | grep -q 'bd create' \
  && ok "(CTRLCHR) the visit is filed normally" || bad "(CTRLCHR) visit filed (err: $ERR)"

# --- (ORDER static) the gate precedes the gate-visit block --------------------
# Placement is the invariant, not just presence: a check that ran after the
# create would leave the junk visit behind, which is the whole defect.
# `|| true`: with `pipefail`, a grep that finds NOTHING — exactly the regression
# this case exists to catch — would otherwise kill the run under `set -e` before
# it could report, turning a legible failure into a silent early exit.
GATE_LINE="$(grep -n '# >>> open-subject-exists' "$SCRIPT" | head -n1 | cut -d: -f1 || true)"
VISIT_LINE="$(awk '/^cmd_open\(\)/{f=1} f && /# >>> gate-visit/{print NR; exit}' "$SCRIPT")"
if [ -n "$GATE_LINE" ] && [ -n "$VISIT_LINE" ] && [ "$GATE_LINE" -lt "$VISIT_LINE" ]; then
  ok "(ORDER) the existence gate precedes the gate-visit block (line $GATE_LINE < $VISIT_LINE)"
else
  bad "(ORDER) gate must precede the gate-visit block (gate=${GATE_LINE:-absent} visit=${VISIT_LINE:-absent})"
fi

# --- (SYNTAX) the shipped script still parses ---------------------------------
sh -n "$SCRIPT" 2>/dev/null && ok "(SYNTAX) gc-helm.sh parses as POSIX sh" || bad "(SYNTAX) sh -n failed"

echo ""
echo "gc-helm open subject-existence gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
