#!/usr/bin/env bash
# Hermetic test for the gc-helm `open` subject-existence gate (tk-ujwvt).
#
# THE BUG: `gc-helm open <bead-id>` resolved the id PREFIX to a rig, pointed bd
# at that rig's ledger, and then filed a visit — never confirming the bead
# actually resolves there. A typo or a stale id produced a REAL visit bead,
# parked on the helm board with gc.continuation_group=<the typo>. Engaging it
# spawns a converse sitting whose prime step (`gc bd show $SUBJECT`) cannot
# resolve anything, so it holds a conversation about a bead that does not
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
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-open-test.XXXXXX")"
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
    # FAKE_VISIT_EDGE=1 emits the su-ab9je shape instead (bead tk-d6ddn): the
    # gc.continuation_group stamp landed EMPTY and only the tracks edge names the
    # subject. Rendered in the `gc bd list` key pair (.type + .depends_on_id),
    # which is the shape this call returns.
    if [ -n "${FAKE_VISIT:-}" ] && [ -n "${FAKE_VISIT_EDGE:-}" ]; then
      jq -n --arg v "$FAKE_VISIT" --arg s "$FAKE_SUBJECT" \
        '[{id:$v, metadata:{task_kind:"visit","gc.continuation_group":""},
           dependencies:[{issue_id:$v, depends_on_id:$s, type:"tracks"}]}]'
    elif [ -n "${FAKE_VISIT:-}" ]; then
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
    export FAKE_SHOW_MODE="$1" FAKE_SUBJECT="$2" FAKE_VISIT="${3:-}" FAKE_VISIT_EDGE="${4:-}"
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
grep -q 'bd create .*--title visit: tk-real1' <<< "$CALLS" \
  && ok "(EXISTS) the visit bead is created" || bad "(EXISTS) visit created (calls: $CALLS)"
grep -q 'gc.routed_to=human' <<< "$CALLS" \
  && ok "(EXISTS) parked on the helm board (routed_to=human)" || bad "(EXISTS) routed_to stamp (calls: $CALLS)"
grep -q 'gc.continuation_group=tk-real1' <<< "$CALLS" \
  && ok "(EXISTS) continuation_group stamped with the subject" || bad "(EXISTS) continuation_group stamp"
grep -q 'task_kind=visit' <<< "$CALLS" \
  && ok "(EXISTS) task_kind=visit stamped" || bad "(EXISTS) task_kind stamp"
grep -q 'bd dep add tk-visit1 tk-real1 --type=tracks' <<< "$CALLS" \
  && ok "(EXISTS) tracks edge wired to the subject" || bad "(EXISTS) tracks edge (calls: $CALLS)"
# The converse routed-pool is retired: a successful open parks the visit on the
# board and spawns no session, so its message must report the board and the
# engage action, not the old spawn/vacuum/attach-via-picker advice.
grep -q 'parked on the helm board' <<< "$OUT" \
  && ok "(EXISTS) success message reports a board-parked visit" || bad "(EXISTS) success names the board (out: $OUT)"
grep -q 'engage tk-visit1' <<< "$OUT" \
  && ok "(EXISTS) …and the engage action needed next" || bad "(EXISTS) success points at engage (out: $OUT)"
grep -qE 'will spawn|vacuum|sessions picker' <<< "$OUT" \
  && bad "(EXISTS) success still advertises the retired converse pool" || ok "(EXISTS) no retired spawn/vacuum/picker advice"

# --- (HELD) an existing open visit still short-circuits ------------------------
run_open found tk-real1 tk-visit0
eq "$RC" "0" "(HELD) an already-held subject exits 0"
grep -q 'visit tk-visit0 is already open' <<< "$OUT" \
  && ok "(HELD) prints the existing visit id" || bad "(HELD) existing visit reported (out: $OUT)"
grep -q 'engage tk-visit0' <<< "$OUT" \
  && ok "(HELD) points the operator at engage for the existing visit" || bad "(HELD) points at engage (out: $OUT)"
[ -z "$CALLS" ] \
  && ok "(HELD) no second visit filed" || bad "(HELD) must not file a second visit (calls: $CALLS)"

# --- (HELDEDGE) the su-ab9je shape: stamp EMPTY, tracks edge intact ------------
# bead tk-d6ddn. A visit records its subject twice and only the edge proved
# reliable; keyed on the stamp alone this verb files the duplicate it exists to
# prevent — and this is the OPERATOR's front door, so the duplicate is filed by
# hand, on a subject a converse session is still holding.
run_open found tk-real1 tk-visit0 edge
eq "$RC" "0" "(HELDEDGE) a subject held by an edge-only visit exits 0"
grep -q 'visit tk-visit0 is already open' <<< "$OUT" \
  && ok "(HELDEDGE) the existing visit is found via its tracks edge" \
  || bad "(HELDEDGE) edge-only visit NOT found — the verb would file a duplicate (out: $OUT)"
[ -z "$CALLS" ] \
  && ok "(HELDEDGE) no second visit filed" \
  || bad "(HELDEDGE) filed a duplicate visit (calls: $CALLS)"

# --- (MISSING) the bug: a typo must file NOTHING -------------------------------
run_open missing tk-nope1
eq "$RC" "4" "(MISSING) an unresolvable id exits 4 (verb runtime failure)"
[ -z "$CALLS" ] \
  && ok "(MISSING) NO visit bead created, routed, or wired — nothing filed" \
  || bad "(MISSING) filed something for a nonexistent bead (calls: $CALLS)"
grep -q 'bead not found' <<< "$ERR" \
  && ok "(MISSING) says 'bead not found'" || bad "(MISSING) message (err: $ERR)"
grep -q "tk-nope1" <<< "$ERR" \
  && ok "(MISSING) names the offending id" || bad "(MISSING) message names the id (err: $ERR)"
# (SHAPE) the not-found payload is an OBJECT, so a `.[]?|.id` probe would make jq
# error out rather than answer cleanly. Assert the gate never mistakes that for a
# resolved subject — i.e. it fails closed on the shape it meets in production.
grep -q 'filed on' <<< "$OUT" \
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
grep -q "prefix 'zz' matches no rig" <<< "$ERR" \
  && ok "(NORIG) names the unmatched prefix (the actionable diagnostic)" \
  || bad "(NORIG) message names the prefix (err: $ERR)"

# --- (DOWN) a wedged data plane is not a typo ---------------------------------
run_open down tk-real1
eq "$RC" "4" "(DOWN) an empty answer exits 4 (fail closed — no visit on an unverified subject)"
[ -z "$CALLS" ] && ok "(DOWN) nothing filed" || bad "(DOWN) filed on an unverified subject (calls: $CALLS)"
grep -q 'could not verify' <<< "$ERR" \
  && ok "(DOWN) says 'could not verify', not 'bead not found'" \
  || bad "(DOWN) a data-plane outage must not be reported as a typo (err: $ERR)"

# --- (DBERROR) an error payload is not a missing bead -------------------------
# The failure mode this separates: a refused Dolt connection answers on the same
# error channel as not-found. Calling that "bead not found" sends the operator
# hunting a typo while the data plane is down.
run_open dberror tk-real1
eq "$RC" "4" "(DBERROR) an error payload exits 4 (fail closed)"
[ -z "$CALLS" ] && ok "(DBERROR) nothing filed" || bad "(DBERROR) filed on an unverified subject (calls: $CALLS)"
grep -q 'could not verify' <<< "$ERR" \
  && ok "(DBERROR) reported as unverifiable, not as a typo" \
  || bad "(DBERROR) a non-not-found error must not read as 'bead not found' (err: $ERR)"
grep -q 'connection refused' <<< "$ERR" \
  && ok "(DBERROR) surfaces the underlying error to the operator" \
  || bad "(DBERROR) message carries the underlying error (err: $ERR)"

# --- (CTRLCHR) invalid --json must not read as missing ------------------------
# Control chars in a bead's notes break `jq` outright; a real bead reported as
# "not found" would send the operator hunting a typo that does not exist.
run_open ctrlchr tk-real1
eq "$RC" "0" "(CTRLCHR) a real bead with control chars in its payload still resolves"
grep -q 'bd create' <<< "$CALLS" \
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

# --- (BLURB) --reason / --body say what the sitting is actually for -----------
# The default wording ("operator pick from the board") is true of the board
# picker and false of every other caller, and the body is not decoration: it is
# written at filing time and read at CLAIM time as the converse session's only
# brief. Two knobs because the default is two — a short title tail and a longer
# brief — so one flag driving both would bloat titles or starve briefs.
: > "$FAKE_CALLS"
export FAKE_SHOW_MODE=found FAKE_SUBJECT=tk-real1 FAKE_VISIT=""
set +e
sh "$SCRIPT" open tk-real1 --reason "operator-origin topic intake" \
   --body "Rebuild what context exists, prep, and hold." >/dev/null 2>&1
set -e
CALLS="$(cat "$FAKE_CALLS")"
grep -q 'bd create .*--title visit: tk-real1 — operator-origin topic intake' <<< "$CALLS" \
  && ok "(BLURB) --reason replaces the title tail" || bad "(BLURB) title tail (calls: $CALLS)"
grep -q -- '-d Rebuild what context exists' <<< "$CALLS" \
  && ok "(BLURB) --body becomes the claim-time brief" || bad "(BLURB) body (calls: $CALLS)"
grep -q 'operator pick from the board' <<< "$CALLS" \
  && bad "(BLURB) the stock wording must not survive an override" || ok "(BLURB) no stock wording left over"
# --reason alone must not leave a stock body contradicting a custom title.
: > "$FAKE_CALLS"
set +e
sh "$SCRIPT" open tk-real1 --reason "operator-origin topic intake" >/dev/null 2>&1
set -e
CALLS="$(cat "$FAKE_CALLS")"
grep -q 'operator pick from the board' <<< "$CALLS" \
  && bad "(BLURB) --reason alone left the stock body (calls: $CALLS)" \
  || ok "(BLURB) --reason alone carries into the body too"
# Still fails closed on a flag with no value, and on a second bead-id.
set +e; sh "$SCRIPT" open tk-real1 --reason >/dev/null 2>&1; RC=$?; set -e
eq "$RC" "2" "(BLURB) --reason with no value is a usage error"
set +e; sh "$SCRIPT" open tk-real1 tk-real2 >/dev/null 2>&1; RC=$?; set -e
eq "$RC" "2" "(BLURB) two bead-ids is a usage error"

# --- (RIGTIMEOUT) the rig-enumeration bound is generous, and tunable ----------
# `gc rig list` measured 2.6-8.4s in a loaded city against a 10s bound, so open
# could exit 3 having filed nothing. Harmless for the board picker, not for
# gc-visit-open.sh's topic path — by the time open runs there, the subject bead
# already exists, so a timeout strands it visit-less. TIMEOUT is set only by
# cmd_board's parser, so the one-shot verbs take the tunable below.
mkdir -p "$TMP/slowbin"
cat > "$TMP/slowbin/gc" <<'SLOW'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "rig list")  sleep 2; jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd show")   jq -n --arg i "$3" '[{id:$i, title:"a real bead"}]' ;;
  "bd list")   printf '[]\n' ;;
  "bd create") printf 'bd create %s\n' "$*" >> "$FAKE_CALLS"; jq -n '{id:"tk-visit1"}' ;;
  "bd update") printf 'bd update %s\n' "$*" >> "$FAKE_CALLS" ;;
  "bd dep")    printf 'bd dep %s\n' "$*" >> "$FAKE_CALLS" ;;
esac
exit 0
SLOW
chmod +x "$TMP/slowbin/gc"
: > "$FAKE_CALLS"
set +e
PATH="$TMP/slowbin:$PATH" GC_HELM_RIG_TIMEOUT=1 sh "$SCRIPT" open tk-slow1 >/dev/null 2>&1; RC=$?
set -e
eq "$RC" "3" "(RIGTIMEOUT) a bound shorter than the answer still fails closed"
eq "$(cat "$FAKE_CALLS")" "" "(RIGTIMEOUT) and files nothing when it does"
: > "$FAKE_CALLS"
set +e
PATH="$TMP/slowbin:$PATH" GC_HELM_RIG_TIMEOUT=10 sh "$SCRIPT" open tk-slow1 >/dev/null 2>&1; RC=$?
set -e
eq "$RC" "0" "(RIGTIMEOUT) a generous bound rides out a slow gc rig list"
grep -q 'bd create' <<< "$(cat "$FAKE_CALLS")" \
  && ok "(RIGTIMEOUT) and the visit is filed" || bad "(RIGTIMEOUT) visit filed"
# The shipped default must be generous, not the board's render budget.
grep -q 'GC_HELM_RIG_TIMEOUT:-30' "$SCRIPT" \
  && ok "(RIGTIMEOUT) the shipped default is 30s, not the board's 10" \
  || bad "(RIGTIMEOUT) shipped default changed — a one-shot verb must not inherit the board budget"

# --- (RIGWHY) enumerate_rigs names WHICH failure it hit ----------------------
# THE BUG (tk-lzdty half 2): every unhappy reading of `gc rig list` ended in one
# sentence — "could not enumerate rigs (gc rig list returned nothing)" — and
# exit 3. `|| true` threw away the exit status and `2>/dev/null` threw away the
# stderr, so a timeout kill, a wedged data plane, unparseable output and a city
# that genuinely has no rigs were indistinguishable. Four different operator
# moves, one string. On the CLI that is a bad message; behind the web board's
# open button (tk-66rwg) the exit code plus that string is the ENTIRE signal the
# browser gets, so all four render as the same dead end.
#
# Each case below drives ONE cause through the real script and asserts the
# message names that cause. (DISTINCT) is the assertion the bead is actually
# about: the six sentences must be pairwise different, so no two causes can
# collapse back together.
mkdir -p "$TMP/rigbin"
cat > "$TMP/rigbin/gc" <<'RIGSTUB'
#!/usr/bin/env bash
if [ "$1 ${2:-}" = "rig list" ]; then
  case "${RIGMODE:-}" in
    slow)     sleep 3; jq -n '{rigs:[{name:"gc-toolkit",path:"/nonexistent-rig",prefix:"tk"}]}' ;;
    exitfail) echo "dial tcp 127.0.0.1:3307: connect: connection refused" >&2; exit 7 ;;
    empty)    : ;;                                  # exit 0, prints NOTHING
    notjson)  echo "warning: rebuilding stale rig cache" ;;
    shape)    jq -n '{other:[]}' ;;                 # valid JSON, no .rigs
    rigless)  jq -n '{rigs:[]}' ;;                  # valid, correct, and empty
    ok)       jq -n '{rigs:[{name:"gc-toolkit",path:"/nonexistent-rig",prefix:"tk"}]}' ;;
  esac
  exit 0
fi
printf '%s %s\n' "$1" "${2:-}" >> "$FAKE_CALLS"
case "$1 ${2:-}" in
  "bd show") jq -n --arg i "$3" '[{id:$i, title:"a real bead", status:"open"}]' ;;
  "bd list") printf '[]\n' ;;
  "bd create") jq -n '{id:"tk-visit9"}' ;;
esac
exit 0
RIGSTUB
chmod +x "$TMP/rigbin/gc"

# Drive one cause; capture stderr and status. Bound is 1s so (TIMEOUT) is quick.
rigwhy() {
  : > "$FAKE_CALLS"
  set +e
  RIGWHY_ERR=$(PATH="$TMP/rigbin:$PATH" RIGMODE="$1" GC_HELM_RIG_TIMEOUT="${2:-30}" \
    sh "$SCRIPT" open tk-any1 2>&1 >/dev/null)
  RIGWHY_RC=$?
  set -e
}
# says <mode> <bound> <substring> <label> — the message names this cause, the
# script still fails closed on 3, and nothing was filed on the way out.
says() {
  rigwhy "$1" "$2"
  case "$RIGWHY_ERR" in
    *"$3"*) ok "(RIGWHY) $4" ;;
    *)      bad "(RIGWHY) $4 — got: $RIGWHY_ERR" ;;
  esac
  eq "$RIGWHY_RC" "3" "(RIGWHY) …and still exits 3 ($4)"
  eq "$(cat "$FAKE_CALLS")" "" "(RIGWHY) …having filed nothing ($4)"
}

says slow     1  "did not answer within 1s and was killed" "a timeout kill says it timed out, and names the bound"
says exitfail 30 "exited 7"                                "a non-zero gc exit reports the status"
says exitfail 30 "connection refused"                      "…and carries gc's own stderr, instead of discarding it"
says empty    30 "exited 0 but printed nothing"            "a silent empty answer is not read as an empty city"
says notjson  30 "is not JSON"                             "unparseable output says so, rather than 'returned nothing'"
says shape    30 "no '.rigs' array"                        "valid JSON of the wrong shape is a gc contract change"
says rigless  30 "no rigs in this city"                    "a genuinely rigless city is reported as a CITY state"

# (DISTINCT) is the whole point of the bead: the causes must not collapse back
# into one string. Collect every message and require six unique ones.
: > "$TMP/rigmsgs"
for m in slow exitfail empty notjson shape rigless; do
  if [ "$m" = slow ]; then rigwhy "$m" 1; else rigwhy "$m" 30; fi
  printf '%s\n' "$RIGWHY_ERR" >> "$TMP/rigmsgs"
done
NUNIQ=$(sort -u "$TMP/rigmsgs" | wc -l | tr -d ' ')
eq "$NUNIQ" "6" "(RIGWHY-DISTINCT) six causes produce six different sentences"

# The rigless message must NOT accuse the data plane — that is the wrong move
# for a city that answered correctly.
rigwhy rigless 30
case "$RIGWHY_ERR" in
  *"gc doctor"*|*Dolt*) bad "(RIGWHY-DISTINCT) an empty city is blamed on the data plane: $RIGWHY_ERR" ;;
  *)                    ok  "(RIGWHY-DISTINCT) an empty city is not blamed on the data plane" ;;
esac
# …and the happy path still works through the same stub, so none of the new
# gates fire on a good answer.
rigwhy ok 30
eq "$RIGWHY_RC" "0" "(RIGWHY) a well-formed rig list still enumerates and files"

# MUTATION CHECK (static): the evidence the taxonomy is built on must still be
# captured. If either of these reverts to the old discard-everything form, the
# cases above keep passing only because the stub is cooperative — so assert the
# source directly. See tk-lzdty.
grep -q 'gc rig list --json 2>"\$_er_errf"' "$SCRIPT" \
  && ok "(RIGWHY-EVIDENCE) gc's stderr is captured, not sent to /dev/null" \
  || bad "(RIGWHY-EVIDENCE) stderr capture removed — messages will lose their 'why'"
# Match the ASSIGNMENT lines only, bounded to the function body. An earlier
# version of this check matched the first line containing "gc rig list", which
# in both the fixed and the broken script is a COMMENT — so it passed against
# the very code it was meant to catch. Anchor guards to code, never to prose.
grep -q '|| true' < <(awk '/^enumerate_rigs\(\)/{f=1} f&&/^\}/{f=0} f&&/rigs_raw=\$\(/' "$SCRIPT") \
  && bad "(RIGWHY-EVIDENCE) '|| true' is back — the exit status is discarded again" \
  || ok "(RIGWHY-EVIDENCE) the exit status is kept, not swallowed by '|| true'"

# --- (RESOLVE) the subject resolver: PR ref / superseded id -> live bead ------
# A PR reference or a settled (closed and superseded) bead id resolves to the
# LIVE bead that owns the work, by metadata and the graph and never by a title,
# before a visit is filed on it. These cases drive the REAL cmd_open over a stub
# whose `bd show` is id-aware, so a supersede chain and a live bead read
# differently, and whose `bd list` answers the PR search. They assert the visit
# is filed on the RESOLVED bead, and that an unresolvable or ambiguous reference
# files nothing.
mkdir -p "$TMP/resbin"
cat > "$TMP/resbin/gc" <<'RESGC'
#!/usr/bin/env bash
# One rig, prefix tk, path with no .beads — so the resolver's PR search and the
# existence gate issue unscoped bd calls this stub answers (as the note in the
# EXISTS stub explains). `bd show` branches on the id so a supersede chain and a
# live bead read differently; `bd list` tells the PR search (which carries
# `blocked` in --status) apart from the already-held visit lookup (which does
# not), so neither reads as the other.
case "$1 ${2:-}" in
  "rig list")
    jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd show")
    case "$3" in
      tk-pred)    jq -n '[{id:"tk-pred",   status:"closed", metadata:{"gc.superseded_by":"tk-succ","gc.superseded_by_store":"rig:gc-toolkit"}}]' ;;
      tk-pred2)   jq -n '[{id:"tk-pred2",  status:"closed", metadata:{"gc.superseded_by":"tk-gone"}}]' ;;
      tk-head)    jq -n '[{id:"tk-head",   status:"closed", metadata:{"gc.superseded_by":"tk-mid"}}]' ;;
      tk-mid)     jq -n '[{id:"tk-mid",    status:"closed", metadata:{"gc.superseded_by":"tk-succ"}}]' ;;
      tk-succ)    jq -n '[{id:"tk-succ",   status:"open",   title:"the live successor"}]' ;;
      tk-cyc1)    jq -n '[{id:"tk-cyc1",   status:"closed", metadata:{"gc.superseded_by":"tk-cyc2"}}]' ;;
      tk-cyc2)    jq -n '[{id:"tk-cyc2",   status:"closed", metadata:{"gc.superseded_by":"tk-cyc1"}}]' ;;
      tk-live1)   jq -n '[{id:"tk-live1",  status:"open",   title:"a live bead"}]' ;;
      tk-prbead)  jq -n '[{id:"tk-prbead", status:"open",   title:"the PR anchor"}]' ;;
      tk-prbead2) jq -n '[{id:"tk-prbead2",status:"open",   title:"another PR anchor"}]' ;;
      tk-defbead) jq -n '[{id:"tk-defbead",status:"deferred",title:"a deferred PR anchor"}]' ;;
      *)          printf '{"error":"no issues found"}\n'; exit 1 ;;
    esac ;;
  "bd list")
    case "$*" in
      # The widened live-status query (open,in_progress,blocked,deferred,hooked,
      # pinned) carries `deferred`; a deferred/hooked/pinned anchor is visible
      # only to it. FAKE_DEFERRED_ROWS models that anchor; unset, the widened
      # query still answers the ordinary PR rows, so the narrow-query PR cases
      # are unaffected by the fix.
      *deferred*) printf '%s' "${FAKE_DEFERRED_ROWS:-${FAKE_PR_ROWS:-[]}}" ;;
      *blocked*)  printf '%s' "${FAKE_PR_ROWS:-[]}" ;;
      *)          printf '%s' "${FAKE_VISIT_ROWS:-[]}" ;;
    esac ;;
  "bd create") printf 'bd create %s\n' "$*" >> "$FAKE_CALLS"; jq -n '{id:"tk-visitR"}' ;;
  "bd update") printf 'bd update %s\n' "$*" >> "$FAKE_CALLS" ;;
  "bd dep")    printf 'bd dep %s\n' "$*" >> "$FAKE_CALLS" ;;
esac
exit 0
RESGC
chmod +x "$TMP/resbin/gc"
# FAKE_DEFERRED_ROWS is intentionally left UNSET by default so the widened PR
# query falls back to FAKE_PR_ROWS and every narrow-query PR case is unaffected;
# the deferred case exports it to model an anchor only the widened query sees.
export FAKE_PR_ROWS='[]' FAKE_VISIT_ROWS='[]'

# run_resolve <arg> -> RC/OUT/ERR/CALLS via the id-aware resbin stub.
run_resolve() {
    : > "$FAKE_CALLS"
    set +e
    OUT="$(PATH="$TMP/resbin:$PATH" sh "$SCRIPT" open "$1" 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"; CALLS="$(cat "$FAKE_CALLS")"
}

# (RESOLVE-SUPERSEDE) a closed+superseded id files on the SUCCESSOR, said aloud.
FAKE_PR_ROWS='[]'; run_resolve tk-pred
eq "$RC" "0" "(RESOLVE-SUPERSEDE) a closed+superseded id resolves and files"
grep -q 'gc.continuation_group=tk-succ' <<< "$CALLS" \
  && ok "(RESOLVE-SUPERSEDE) the visit is filed on the live successor" \
  || bad "(RESOLVE-SUPERSEDE) continuation_group is the successor (calls: $CALLS)"
grep -q 'continuation_group=tk-pred' <<< "$CALLS" \
  && bad "(RESOLVE-SUPERSEDE) filed on the dead predecessor" \
  || ok "(RESOLVE-SUPERSEDE) never files on the predecessor"
grep -q 'tk-pred is closed and superseded' <<< "$ERR" \
  && ok "(RESOLVE-SUPERSEDE) announces the redirect — never silent" \
  || bad "(RESOLVE-SUPERSEDE) redirect not announced (err: $ERR)"

# (RESOLVE-CHAIN) a multi-hop chain (head -> mid -> succ) resolves to the end.
FAKE_PR_ROWS='[]'; run_resolve tk-head
eq "$RC" "0" "(RESOLVE-CHAIN) a supersede chain resolves and files"
grep -q 'gc.continuation_group=tk-succ' <<< "$CALLS" \
  && ok "(RESOLVE-CHAIN) followed head->mid->succ to the live end" \
  || bad "(RESOLVE-CHAIN) chain not followed to the end (calls: $CALLS)"

# (RESOLVE-LIVE) a live bead id passes through unchanged and unremarked.
FAKE_PR_ROWS='[]'; run_resolve tk-live1
eq "$RC" "0" "(RESOLVE-LIVE) a live bead id still files"
grep -q 'gc.continuation_group=tk-live1' <<< "$CALLS" \
  && ok "(RESOLVE-LIVE) filed on the id as given" || bad "(RESOLVE-LIVE) filed elsewhere (calls: $CALLS)"
grep -qiE 'superseded|PR #' <<< "$ERR" \
  && bad "(RESOLVE-LIVE) a live id must not trigger a redirect note (err: $ERR)" \
  || ok "(RESOLVE-LIVE) no redirect note for a live id"

# (RESOLVE-CYCLE) a superseded-by cycle is refused, not guessed; nothing filed.
FAKE_PR_ROWS='[]'; run_resolve tk-cyc1
eq "$RC" "4" "(RESOLVE-CYCLE) a supersede cycle exits 4"
[ -z "$CALLS" ] && ok "(RESOLVE-CYCLE) nothing filed on a cycle" || bad "(RESOLVE-CYCLE) filed despite a cycle (calls: $CALLS)"
grep -q 'cycle' <<< "$ERR" && ok "(RESOLVE-CYCLE) names the cycle" || bad "(RESOLVE-CYCLE) message (err: $ERR)"

# (RESOLVE-BROKEN-POINTER) a superseded id whose successor does not resolve is
# refused — never a silent fall-back to opening the settled predecessor.
FAKE_PR_ROWS='[]'; run_resolve tk-pred2
eq "$RC" "4" "(RESOLVE-BROKEN-POINTER) an unresolvable successor exits 4"
[ -z "$CALLS" ] \
  && ok "(RESOLVE-BROKEN-POINTER) nothing filed on the settled predecessor" \
  || bad "(RESOLVE-BROKEN-POINTER) filed something (calls: $CALLS)"
grep -q 'tk-gone' <<< "$ERR" \
  && ok "(RESOLVE-BROKEN-POINTER) names the successor it could not resolve" \
  || bad "(RESOLVE-BROKEN-POINTER) names the successor (err: $ERR)"

# (RESOLVE-PR-NUMBER) a bare PR number resolves to the anchor recording it.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]'
run_resolve 615
eq "$RC" "0" "(RESOLVE-PR-NUMBER) a PR number resolves and files"
grep -q 'gc.continuation_group=tk-prbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-NUMBER) filed on the bead whose pr_number matches" \
  || bad "(RESOLVE-PR-NUMBER) filed elsewhere (calls: $CALLS)"
grep -q 'PR #615 -> tk-prbead' <<< "$ERR" \
  && ok "(RESOLVE-PR-NUMBER) says which bead it matched" || bad "(RESOLVE-PR-NUMBER) match not announced (err: $ERR)"

# (RESOLVE-PR-URL) a PR URL resolves the same way, pinning the repo.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]'
run_resolve 'https://github.com/o/r/pull/615'
eq "$RC" "0" "(RESOLVE-PR-URL) a PR URL resolves and files"
grep -q 'gc.continuation_group=tk-prbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-URL) filed on the anchor whose pr_url matches" || bad "(RESOLVE-PR-URL) filed elsewhere (calls: $CALLS)"

# (RESOLVE-PR-URL-DISAMBIG) two beads share a number; the URL pins the repo.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r1/pull/615"}},{"id":"tk-prbead2","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r2/pull/615"}}]'
run_resolve 'https://github.com/o/r1/pull/615'
eq "$RC" "0" "(RESOLVE-PR-URL-DISAMBIG) the URL disambiguates a shared number"
grep -q 'gc.continuation_group=tk-prbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-URL-DISAMBIG) the repo in the URL selects one bead" \
  || bad "(RESOLVE-PR-URL-DISAMBIG) filed elsewhere (calls: $CALLS)"

# (RESOLVE-PR-MISSING) a PR no bead records fails closed, nothing filed.
FAKE_PR_ROWS='[]'; run_resolve 999
eq "$RC" "4" "(RESOLVE-PR-MISSING) an unrecorded PR exits 4"
[ -z "$CALLS" ] && ok "(RESOLVE-PR-MISSING) nothing filed" || bad "(RESOLVE-PR-MISSING) filed something (calls: $CALLS)"
grep -q 'no open bead records PR #999' <<< "$ERR" \
  && ok "(RESOLVE-PR-MISSING) names the PR it could not resolve" || bad "(RESOLVE-PR-MISSING) message (err: $ERR)"

# (RESOLVE-PR-AMBIGUOUS) a bare number several beads record is refused by name.
FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615"}},{"id":"tk-prbead2","status":"open","metadata":{"pr_number":"615"}}]'
run_resolve 615
eq "$RC" "4" "(RESOLVE-PR-AMBIGUOUS) an ambiguous PR number exits 4"
[ -z "$CALLS" ] && ok "(RESOLVE-PR-AMBIGUOUS) nothing filed" || bad "(RESOLVE-PR-AMBIGUOUS) filed something (calls: $CALLS)"
grep -q 'ambiguous' <<< "$ERR" && ok "(RESOLVE-PR-AMBIGUOUS) says ambiguous" || bad "(RESOLVE-PR-AMBIGUOUS) message (err: $ERR)"
grep -q 'tk-prbead2' <<< "$ERR" && ok "(RESOLVE-PR-AMBIGUOUS) names every candidate" || bad "(RESOLVE-PR-AMBIGUOUS) names candidates (err: $ERR)"

# (RESOLVE-PR-DEFERRED) a PR whose anchor sits in a NON-OPEN live state (deferred)
# resolves too. The resolver's status set must be the pack's live-PR set
# (open,in_progress,blocked,deferred,hooked,pinned), matching pr-facts.sh:247 and
# merge.sh:126; the narrow open,in_progress,blocked would miss it. FAKE_DEFERRED_ROWS
# is visible only to the widened query, so this is red before the fix (the narrow
# query finds nothing and exits 4) and green after.
FAKE_PR_ROWS='[]'
export FAKE_DEFERRED_ROWS='[{"id":"tk-defbead","status":"deferred","metadata":{"pr_number":"616","pr_url":"https://github.com/o/r/pull/616"}}]'
run_resolve 616
eq "$RC" "0" "(RESOLVE-PR-DEFERRED) a PR anchor in a non-open live state resolves and files"
grep -q 'gc.continuation_group=tk-defbead' <<< "$CALLS" \
  && ok "(RESOLVE-PR-DEFERRED) filed on the deferred anchor recording the PR" \
  || bad "(RESOLVE-PR-DEFERRED) not filed on the deferred anchor (calls: $CALLS)"
grep -q 'PR #616 -> tk-defbead' <<< "$ERR" \
  && ok "(RESOLVE-PR-DEFERRED) says which bead it matched" || bad "(RESOLVE-PR-DEFERRED) match not announced (err: $ERR)"
unset FAKE_PR_ROWS FAKE_VISIT_ROWS FAKE_DEFERRED_ROWS

# --- (RESOLVE-REACT / RESOLVE-ENGAGE) the resolved subject drives the write ----
# react and engage resolve the same reference open does, then act on the LIVE
# bead: react slings it through gc-proactive.sh, engage spawns a sitting on a
# visit tracking it. These cases drive the REAL verbs over a stub that answers
# the resolve reads and, for engage, the spawn and bind, and assert the id each
# verb writes is the RESOLVED one (a supersede chain's successor, or the bead a
# PR number records), never the reference typed.
mkdir -p "$TMP/rebin"
cat > "$TMP/rebin/gc" <<'REBIN'
#!/usr/bin/env bash
# `bd show` branches on the id so a supersede chain, a live bead, and the visit
# read differently; the visit's assignee is served from $VISIT_STATE so the
# assignee the bind writes is the one the readback sees. `bd list` tells the PR
# search (carries `blocked` in --status) apart from the visit lookup. `session
# new` returns a fixed identity; nudge is a no-op. Mutations append to $FAKE_CALLS.
case "$1 ${2:-}" in
  "rig list")
    jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd show")
    case "$3" in
      tk-pred)   jq -n '[{id:"tk-pred",   status:"closed", metadata:{"gc.superseded_by":"tk-succ"}}]' ;;
      tk-succ)   jq -n '[{id:"tk-succ",   status:"open",   title:"the live successor"}]' ;;
      tk-prbead) jq -n '[{id:"tk-prbead", status:"open",   title:"the PR anchor"}]' ;;
      tk-visitE)
        _a="$(cat "$VISIT_STATE" 2>/dev/null || true)"
        jq -n --arg a "$_a" '[{id:"tk-visitE", status:"open", assignee:$a, metadata:{"task_kind":"visit"}}]' ;;
      *) printf '{"error":"no issues found"}\n'; exit 1 ;;
    esac ;;
  "bd list")
    case "$*" in
      *blocked*) printf '%s' "${FAKE_PR_ROWS:-[]}" ;;
      *)         printf '%s' "${FAKE_VISIT_ROWS:-[]}" ;;
    esac ;;
  "bd dep")
    case "$3" in
      list) printf '[]\n' ;;
      *)    printf 'bd dep %s\n' "$*" >> "$FAKE_CALLS" ;;
    esac ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$FAKE_CALLS"
    _sn="$(printf '%s' "$*" | sed -n 's/.* --assignee \(.*\)$/\1/p')"
    [ -n "$_sn" ] && printf '%s' "$_sn" > "$VISIT_STATE" ;;
  "session new")
    jq -n '{session_id:"lx-fake", session_name:"gc-toolkit/converse-opus.tk-visitE"}' ;;
esac
exit 0
REBIN
chmod +x "$TMP/rebin/gc"
cat > "$TMP/rebin/gc-proactive.sh" <<'PROACTIVE'
#!/usr/bin/env bash
printf 'proactive %s\n' "$*" >> "$FAKE_SLING"
exit 0
PROACTIVE
chmod +x "$TMP/rebin/gc-proactive.sh"
export FAKE_SLING="$TMP/slung" VISIT_STATE="$TMP/visit_state"

# run_react <arg> — drive the REAL cmd_react; the fake gc-proactive.sh records
# the `sling` argv so the resolved subject is checked against the slung id.
run_react() {
    : > "$FAKE_SLING"
    set +e
    OUT="$(PATH="$TMP/rebin:$PATH" GC_PROACTIVE_TOOL="$TMP/rebin/gc-proactive.sh" \
        sh "$SCRIPT" react "$1" --dry-run 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"; SLUNG="$(cat "$FAKE_SLING")"
}
# run_engage <arg> — drive the REAL cmd_engage through the spawn/bind path,
# --no-attach so no session is attached; VISIT_STATE reset so the pre-bind read
# sees the parked visit unassigned.
run_engage() {
    : > "$FAKE_CALLS"; : > "$VISIT_STATE"
    set +e
    OUT="$(PATH="$TMP/rebin:$PATH" sh "$SCRIPT" engage "$1" --no-attach 2>"$TMP/err")"; RC=$?
    set -e
    ERR="$(cat "$TMP/err")"; CALLS="$(cat "$FAKE_CALLS")"
}

# (RESOLVE-REACT-SUPERSEDE) react slings the successor of a settled id.
export FAKE_PR_ROWS='[]' FAKE_VISIT_ROWS='[]'
run_react tk-pred
eq "$RC" "0" "(RESOLVE-REACT-SUPERSEDE) react resolves a settled id and slings"
grep -q 'sling tk-succ' <<< "$SLUNG" \
  && ok "(RESOLVE-REACT-SUPERSEDE) gc-proactive.sh is slung the live successor" \
  || bad "(RESOLVE-REACT-SUPERSEDE) slung the successor (slung: $SLUNG)"
grep -q 'sling tk-pred' <<< "$SLUNG" \
  && bad "(RESOLVE-REACT-SUPERSEDE) slung the settled predecessor" \
  || ok "(RESOLVE-REACT-SUPERSEDE) never slings the predecessor"

# (RESOLVE-REACT-PR) react slings the bead a PR number records, not the number.
export FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]' FAKE_VISIT_ROWS='[]'
run_react 615
eq "$RC" "0" "(RESOLVE-REACT-PR) react resolves a PR number and slings"
grep -q 'sling tk-prbead' <<< "$SLUNG" \
  && ok "(RESOLVE-REACT-PR) gc-proactive.sh is slung the bead recording the PR" \
  || bad "(RESOLVE-REACT-PR) slung the PR anchor (slung: $SLUNG)"
grep -qE 'sling 615( |$)' <<< "$SLUNG" \
  && bad "(RESOLVE-REACT-PR) slung the raw PR number" \
  || ok "(RESOLVE-REACT-PR) never slings the raw PR number"

# (RESOLVE-ENGAGE-SUPERSEDE) engage spawns onto the visit tracking the successor.
export FAKE_PR_ROWS='[]' FAKE_VISIT_ROWS='[{"id":"tk-visitE","status":"open","assignee":"","metadata":{"task_kind":"visit","gc.continuation_group":"tk-succ"}}]'
run_engage tk-pred
eq "$RC" "0" "(RESOLVE-ENGAGE-SUPERSEDE) engage resolves a settled id and binds a sitting"
grep -q 'visit tk-visitE on tk-succ' <<< "$OUT" \
  && ok "(RESOLVE-ENGAGE-SUPERSEDE) the sitting holds a visit on the live successor" \
  || bad "(RESOLVE-ENGAGE-SUPERSEDE) sitting is on the successor (out: $OUT)"
grep -q 'tk-pred is closed and superseded' <<< "$ERR" \
  && ok "(RESOLVE-ENGAGE-SUPERSEDE) announces the redirect before spawning" \
  || bad "(RESOLVE-ENGAGE-SUPERSEDE) redirect announced (err: $ERR)"
grep -q 'bd update tk-visitE.*--assignee gc-toolkit/converse-opus.tk-visitE' <<< "$CALLS" \
  && ok "(RESOLVE-ENGAGE-SUPERSEDE) binds the spawned sitting to the successor's visit" \
  || bad "(RESOLVE-ENGAGE-SUPERSEDE) bound the resolved bead's visit (calls: $CALLS)"

# (RESOLVE-ENGAGE-PR) engage spawns onto the visit tracking the PR's bead.
export FAKE_PR_ROWS='[{"id":"tk-prbead","status":"open","metadata":{"pr_number":"615","pr_url":"https://github.com/o/r/pull/615"}}]' FAKE_VISIT_ROWS='[{"id":"tk-visitE","status":"open","assignee":"","metadata":{"task_kind":"visit","gc.continuation_group":"tk-prbead"}}]'
run_engage 615
eq "$RC" "0" "(RESOLVE-ENGAGE-PR) engage resolves a PR number and binds a sitting"
grep -q 'visit tk-visitE on tk-prbead' <<< "$OUT" \
  && ok "(RESOLVE-ENGAGE-PR) the sitting holds a visit on the bead recording the PR" \
  || bad "(RESOLVE-ENGAGE-PR) sitting is on the PR anchor (out: $OUT)"
grep -q 'PR #615 -> tk-prbead' <<< "$ERR" \
  && ok "(RESOLVE-ENGAGE-PR) announces the PR match before spawning" \
  || bad "(RESOLVE-ENGAGE-PR) PR match announced (err: $ERR)"
unset FAKE_PR_ROWS FAKE_VISIT_ROWS FAKE_SLING VISIT_STATE

# --- (SYNTAX) the shipped script still parses ---------------------------------
sh -n "$SCRIPT" 2>/dev/null && ok "(SYNTAX) gc-helm.sh parses as POSIX sh" || bad "(SYNTAX) sh -n failed"

echo ""
echo "gc-helm open subject-existence gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
