#!/usr/bin/env bash
# Hermetic test for assets/scripts/molecule-hold.sh (tk-dchq5).
#
# THE BUG the script closes: a graph.v2 refusal arm that declines work it must
# not close, and drains leaving its step `open` and routed. `open` is half the
# pool's offer predicate, so a fresh worker claims the same step within minutes,
# re-derives the same refusal, and leaves it open again — one pool slot burned
# per cycle, indefinitely, until a human notices. Observed twice from two
# different refusal arms (su-a0fs.1 2026-08-17; tk-hs5rz 2026-08-23).
#
# What is exercised here:
#   * the LOOP ANCHOR — a molecule shaped like the live one (claimed step, a
#     routed root, five pre-assigned open siblings, a finalize step routed to
#     the control-dispatcher). After the hold nothing in it is claimable and
#     nothing is closed;
#   * the ROOT — de-routing the step alone is not enough, because a routed root
#     re-offers the molecule. The root's status and assignee stay untouched;
#   * the SWEEP TIER — status is the load-bearing write, not the route clear.
#     gascity's stranded-worker repair sweeps {open, in_progress} assigned to a
#     drained session and re-stamps a run_target fallback on whatever it finds
#     unrouted, so a step left open with its route cleared gets re-routed. Only
#     `blocked` is outside that tier;
#   * the ATOMICITY anchor (tk-z27pw) — bd's claim guard refuses `--assignee ""`
#     on an in_progress bead and the refusal rolls back the WHOLE update, so the
#     blocking write must not carry an assignee. Status and route ship together;
#     the assignee clear is a separate, later call;
#   * the ORDER anchor — route first, assignee second. The reverse leaves a bead
#     briefly `open + unassigned + routed`, which is exactly the offer predicate
#     the hold exists to escape;
#   * WORKFLOW-FINALIZE is never de-routed — it is the molecule's only path to
#     retirement;
#   * NOTHING IS EVER CLOSED, on any path, including the failure arms;
#   * fail-closed: a refused blocking write exits 1 and touches nothing else,
#     because a half-held molecule reads as held while it still loops;
#   * ambiguity and unresolvable identity are refused with no writes;
#   * idempotence: an already-blocked step is a normal re-run;
#   * the SUBSTRING trap — session lx-zzk must not own lx-zzk9's bead;
#   * control characters in bd's JSON, which break an unfiltered `| jq`;
#   * usage errors, including a value-taking option at the end of argv;
#   * the FORMULA WIRING — mol-polecat-work's load-context refusal arm is
#     extracted verbatim and must call the script rather than say "leave it
#     open".
#
# No live city, Dolt, network, or beads — only a tmpdir, a `gc` stub over a
# JSON store, and the script itself.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/molecule-hold.sh"
TOML="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
# `grep -q` fed by a here-string, never by a pipe: under pipefail a piped writer
# takes SIGPIPE when grep quits at its first match and a successful match is
# reported as a failure (doctor/check-pipefail-grep-q).
hasin() { grep -q -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2' in: $1)"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2' in: $1)"; else ok "$3"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }
[ -f "$TOML" ]   || { echo "formula not found: $TOML" >&2; exit 1; }

mkdir -p "$TMP/bin"

# --- gc stub over a mutable JSON store. --------------------------------------
# `bd show`   : the bead as a one-element array (unknown id -> []).
# `bd list`   : filters on --status= (comma list) and --assignee=.
# `bd update` : applies --status/--assignee/--set-metadata/--unset-metadata/
#               --append-notes to the store; refuses ids listed in $FAKE_UPDFAIL.
# Every invocation is appended verbatim to $GC_LOG, which is what the ordering
# assertions read.
# FAKE_CTRL=1 injects a raw control character into every title, reproducing the
# bd payloads that make an unfiltered `| jq` exit "invalid".
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
set -u
S="${FAKE_STORE:?}"
printf '%s\n' "$*" >> "${GC_LOG:?}"
[ "${1:-}" = "bd" ] || exit 0
shift
verb="${1:-}"; shift || true
ctl=""
[ "${FAKE_CTRL:-0}" = "1" ] && ctl="$(printf '\001')"
case "$verb" in
  show)
    jq -c --arg id "${1:-}" --arg c "$ctl" \
      '[ .[] | select(.id == $id) | .title = ((.title // "b") + $c) ]' "$S" ;;
  list)
    wstatus=""; wassignee=""
    for a in "$@"; do
      case "$a" in
        --status=*)   wstatus="${a#--status=}" ;;
        --assignee=*) wassignee="${a#--assignee=}" ;;
      esac
    done
    jq -c --arg st "$wstatus" --arg as "$wassignee" --arg c "$ctl" '
      [ .[]
        | (.status // "open") as $bst
        | select($st == "" or (($st | split(",")) | index($bst)))
        | select($as == "" or ((.assignee // "") == $as))
        | .title = ((.title // "b") + $c) ]' "$S" ;;
  update)
    id="${1:-}"; shift || true
    if [ -f "${FAKE_UPDFAIL:-/dev/null}" ] && grep -qx "$id" "${FAKE_UPDFAIL:-/dev/null}" 2>/dev/null; then
      echo "bd: cannot update $id: held (stub)" >&2
      exit 1
    fi
    sets=(); unsets=(); asg=""; asg_set=0; st=""; note=""; note_set=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)   shift; sets+=("${1:-}") ;;
        --set-metadata=*) sets+=("${1#--set-metadata=}") ;;
        --unset-metadata)   shift; unsets+=("${1:-}") ;;
        --unset-metadata=*) unsets+=("${1#--unset-metadata=}") ;;
        --assignee=*) asg="${1#--assignee=}"; asg_set=1 ;;
        --assignee)   shift; asg="${1-}"; asg_set=1 ;;
        --status=*)   st="${1#--status=}" ;;
        --append-notes) shift; note="${1:-}"; note_set=1 ;;
        *) : ;;
      esac
      shift || true
    done
    tmp="$(mktemp)"; cp "$S" "$tmp"
    for kv in ${sets[@]+"${sets[@]}"}; do
      jq -c --arg id "$id" --arg k "${kv%%=*}" --arg v "${kv#*=}" \
        'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    for k in ${unsets[@]+"${unsets[@]}"}; do
      jq -c --arg id "$id" --arg k "$k" \
        'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    [ "$asg_set" = 1 ] && { jq -c --arg id "$id" --arg a "$asg" \
        'map(if .id == $id then .assignee = $a else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"; }
    [ -n "$st" ] && { jq -c --arg id "$id" --arg s "$st" \
        'map(if .id == $id then .status = $s else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"; }
    [ "$note_set" = 1 ] && { jq -c --arg id "$id" --arg n "$note" \
        'map(if .id == $id then .notes = ((.notes // "") + $n) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"; }
    mv "$tmp" "$S"
    echo "✓ Updated issue: $id" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_STORE="$TMP/store.json" GC_LOG="$TMP/gc.log" FAKE_UPDFAIL="$TMP/updfail"

MINE="gc-toolkit--gc-toolkit__polecat-1-pool"
POOL="gc-toolkit/gc-toolkit.polecat"
STEP="mol-polecat-work.load-context"

export GC_SESSION_NAME="$MINE" GC_SESSION_ID="lx-98h2m"
unset GC_ALIAS 2>/dev/null || true

bstatus()  { jq -r --arg i "$1" '(.[] | select(.id == $i) | .status) // "<absent>"' "$FAKE_STORE"; }
bassignee(){ jq -r --arg i "$1" '(.[] | select(.id == $i) | .assignee) // "<absent>"' "$FAKE_STORE"; }
meta()     { jq -r --arg i "$1" --arg k "$2" '(.[] | select(.id == $i) | .metadata[$k]) // "<absent>"' "$FAKE_STORE"; }
gclog()    { cat "$GC_LOG"; }

# The live molecule shape: an in_progress claimed step, a routed root, four
# pre-assigned open siblings, and a finalize step held by the dispatcher.
reset_store() {
  : > "$GC_LOG"; : > "$FAKE_UPDFAIL"
  cat > "$FAKE_STORE" <<STORE
[
 {"id":"root-1","status":"in_progress","assignee":"","metadata":{"gc.routed_to":"$POOL","gc.input_convoy_id":"cv-1"}},
 {"id":"s-load","status":"in_progress","assignee":"$MINE","metadata":{"gc.step_ref":"$STEP","gc.root_bead_id":"root-1","gc.routed_to":"$POOL","gc.session_affinity":"require"}},
 {"id":"s-setup","status":"open","assignee":"$MINE","metadata":{"gc.step_ref":"mol-polecat-work.workspace-setup","gc.root_bead_id":"root-1","gc.routed_to":"$POOL","gc.session_affinity":"require"}},
 {"id":"s-impl","status":"open","assignee":"$MINE","metadata":{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"root-1","gc.routed_to":"$POOL"}},
 {"id":"s-submit","status":"open","assignee":"$MINE","metadata":{"gc.step_ref":"mol-polecat-work.submit-and-exit","gc.root_bead_id":"root-1","gc.routed_to":"$POOL"}},
 {"id":"s-final","status":"open","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.root_bead_id":"root-1","gc.routed_to":"core.control-dispatcher"}},
 {"id":"other-load","status":"in_progress","assignee":"gc-toolkit__polecat-lx-other","metadata":{"gc.step_ref":"$STEP","gc.root_bead_id":"root-9","gc.routed_to":"$POOL"}}
]
STORE
}

echo "== the loop anchor: a full molecule goes quiet, and nothing closes =="
reset_store
OUT=$("$SCRIPT" --step "$STEP" --reason "duplicate dispatch: tk-x is in_progress under live lx-y" 2>&1); RC=$?
eq "$RC" "0" "hold exits 0"

eq "$(bstatus s-load)"   "blocked" "claimed step is blocked, not open and not closed"
eq "$(meta s-load 'gc.routed_to')"       "<absent>" "claimed step is de-routed"
eq "$(meta s-load 'gc.session_affinity')" "<absent>" "claimed step's session affinity is cleared"
eq "$(bassignee s-load)" "$MINE"   "the claim on the held step is RETAINED — blocked is inert in every tier, and the pair is what a re-run resolves on"
has "$(meta s-load blocked_reason)" "duplicate dispatch" "blocked_reason carries the caller's reason"
has "$(jq -r '(.[] | select(.id == "s-load") | .notes) // ""' "$FAKE_STORE")" "Held at $STEP" "the hold is recorded in the step's notes"

eq "$(meta root-1 'gc.routed_to')" "<absent>" "the ROOT is de-routed — a routed root re-offers the molecule"
eq "$(bstatus root-1)"  "in_progress" "the root's status is left to the finalizer"
eq "$(bassignee root-1)" ""          "the root's assignee is untouched"

for sib in s-setup s-impl s-submit; do
  eq "$(meta "$sib" 'gc.routed_to')" "<absent>" "sibling $sib is de-routed"
  eq "$(bassignee "$sib")"           ""         "sibling $sib is unassigned — an assigned open step is inside the stranded-repair sweep"
  eq "$(bstatus "$sib")"             "open"     "sibling $sib keeps its status; the dependency edges already hold it"
done
eq "$(meta s-setup 'gc.session_affinity')" "<absent>" "sibling session affinity is cleared with the route"

eq "$(meta s-final 'gc.routed_to')" "core.control-dispatcher" "workflow-finalize keeps its route — the molecule's only path to retirement"

eq "$(bstatus other-load)"   "in_progress"                    "another session's bead for the same step is untouched"
eq "$(bassignee other-load)" "gc-toolkit__polecat-lx-other"   "another session's claim is untouched"
eq "$(meta other-load 'gc.routed_to')" "$POOL"                "another molecule's route is untouched"

hasnt "$(gclog)" "--status=closed" "nothing is closed anywhere on the success path"

echo "== atomicity: the blocking write carries no assignee (tk-z27pw) =="
BLOCK_LINE=$(grep -m1 -- '--status=blocked' "$GC_LOG")
has   "$BLOCK_LINE" "--unset-metadata gc.routed_to" "status and route clear ship in ONE update"
has   "$BLOCK_LINE" "blocked_reason" "the reason ships with the status"
hasnt "$BLOCK_LINE" "--assignee" "the blocking write carries no assignee — the claim guard would roll the status back with it"

echo "== order: route first, assignee second =="
order_ok=1
for id in s-setup s-impl s-submit; do
  r=$(grep -n -- "bd update $id .*--unset-metadata gc.routed_to" "$GC_LOG" | head -1 | cut -d: -f1)
  a=$(grep -n -- "bd update $id --assignee" "$GC_LOG" | head -1 | cut -d: -f1)
  if [ -z "$r" ] || [ -z "$a" ] || [ "$r" -ge "$a" ]; then order_ok=0; echo "  ($id route=$r assignee=$a)"; fi
done
eq "$order_ok" "1" "every bead is de-routed before it is unassigned (the reverse is the offer predicate)"

echo "== the step is out of the stranded-repair sweep tier =="
eq "$(jq -r '[ .[] | select((.status == "open" or .status == "in_progress") and (.assignee // "") != "" and ((.metadata["gc.root_bead_id"] // "") == "root-1")) ] | length' "$FAKE_STORE")" \
   "0" "no step of the held molecule is left open-or-in_progress AND assigned"
eq "$(jq -r '[ .[] | select(((.metadata["gc.root_bead_id"] // "") == "root-1") and ((.metadata["gc.routed_to"] // "") != "") and (((.metadata["gc.step_ref"] // "") | endswith(".workflow-finalize")) | not)) ] | length' "$FAKE_STORE")" \
   "0" "no step of the held molecule is left routed, except finalize"

echo "== idempotence =="
OUT=$("$SCRIPT" --step "$STEP" --reason "same reason" 2>&1); RC=$?
eq "$RC" "0" "a re-run over an already-held molecule exits 0"
has "$OUT" "already blocked" "and says so"

echo "== fail-closed: a refused blocking write stops there =="
reset_store
echo "s-load" > "$FAKE_UPDFAIL"
OUT=$("$SCRIPT" --step "$STEP" --reason "cannot hold" 2>&1); RC=$?
eq "$RC" "1" "a refused hold exits 1"
has "$OUT" "still claimable" "the diagnostic names the consequence"
eq "$(bstatus s-load)"             "in_progress" "the step is unchanged"
eq "$(meta root-1 'gc.routed_to')" "$POOL"       "the ROOT is not de-routed by a hold that never landed"
eq "$(meta s-setup 'gc.routed_to')" "$POOL"      "siblings are not quiesced by a hold that never landed"
hasnt "$(gclog)" "--status=closed" "the failure arm closes nothing"

echo "== a sibling that refuses its writes does not fail the hold =="
reset_store
printf 's-impl\n' > "$FAKE_UPDFAIL"
OUT=$("$SCRIPT" --step "$STEP" --reason "held" 2>&1); RC=$?
eq "$RC" "0" "one unquiesceable sibling does not fail the hold"
eq "$(bstatus s-load)" "blocked" "the held step is still held"
has "$OUT" "could not de-route sibling step s-impl" "and the sibling that resisted is named"
eq "$(meta s-setup 'gc.routed_to')" "<absent>" "the other siblings are still quiesced"

echo "== ambiguity is refused, and writes nothing =="
reset_store
jq -c --arg m "$MINE" --arg s "$STEP" \
  '. + [{"id":"s-dup","status":"in_progress","assignee":$m,"metadata":{"gc.step_ref":$s,"gc.root_bead_id":"root-1"}}]' \
  "$FAKE_STORE" > "$TMP/s" && mv "$TMP/s" "$FAKE_STORE"
: > "$GC_LOG"
OUT=$("$SCRIPT" --step "$STEP" --reason "ambiguous" 2>&1); RC=$?
eq "$RC" "2" "two beads for one step refuse rather than guess"
has "$OUT" "refusing to guess" "and say why"
eq "$(bstatus s-load)" "in_progress" "nothing was written"
hasnt "$(gclog)" "bd update" "the ambiguity arm issues no update at all"

echo "== the substring trap =="
reset_store
OUT=$(GC_SESSION_NAME="gc-toolkit--gc-toolkit__polecat-1-poo" GC_SESSION_ID="lx-98h2" \
      "$SCRIPT" --step "$STEP" --reason "not mine" 2>&1); RC=$?
eq "$RC" "2" "a session whose name is a PREFIX of the assignee owns nothing"
eq "$(bstatus s-load)" "in_progress" "and writes nothing"

echo "== control characters in bd's JSON =="
reset_store
OUT=$(FAKE_CTRL=1 "$SCRIPT" --step "$STEP" --reason "ctl" 2>&1); RC=$?
eq "$RC" "0" "a raw control byte in a title does not blind resolution"
eq "$(bstatus s-load)" "blocked" "and the hold still lands"

echo "== a step with no root still gets held =="
reset_store
jq -c 'map(if .id == "s-load" then (.metadata |= del(.["gc.root_bead_id"])) else . end)' \
  "$FAKE_STORE" > "$TMP/s" && mv "$TMP/s" "$FAKE_STORE"
OUT=$("$SCRIPT" --step "$STEP" --reason "no root" 2>&1); RC=$?
eq "$RC" "0" "the hold lands without a root"
eq "$(bstatus s-load)" "blocked" "the step is blocked"
has "$OUT" "carries no gc.root_bead_id" "and the gap is reported, not hidden"
eq "$(meta root-1 'gc.routed_to')" "$POOL" "an unresolvable root is left alone"

echo "== dry run writes nothing =="
reset_store
OUT=$("$SCRIPT" --step "$STEP" --reason "peek" --dry-run 2>&1); RC=$?
eq "$RC" "0" "--dry-run exits 0"
has "$OUT" "DRY RUN" "and says so"
eq "$(bstatus s-load)" "in_progress" "and writes nothing"
hasnt "$(gclog)" "bd update" "no update is issued under --dry-run"

echo "== usage =="
reset_store
OUT=$("$SCRIPT" --reason "x" 2>&1); eq "$?" "2" "--step is required"
OUT=$("$SCRIPT" --step "$STEP" 2>&1); RC=$?
eq "$RC" "2" "--reason is required"
has "$OUT" "a hold nobody can read is a stall" "and says why"
OUT=$("$SCRIPT" --step 2>&1); eq "$?" "2" "a value-taking option at the end of argv exits rather than spinning"
OUT=$("$SCRIPT" --step --reason 2>&1); RC=$?
eq "$RC" "2" "an option consumed as a value is refused"
has "$OUT" "requires a value" "and named"
OUT=$("$SCRIPT" --step "{{step_id}}" --reason "x" 2>&1); RC=$?
eq "$RC" "2" "an unsubstituted template placeholder is refused"
OUT=$("$SCRIPT" --step "bad step" --reason "x" 2>&1); eq "$?" "2" "a step ref with illegal characters is refused"
OUT=$(env -u GC_SESSION_NAME -u GC_SESSION_ID -u GC_ALIAS "$SCRIPT" --step "$STEP" --reason "x" 2>&1); RC=$?
eq "$RC" "2" "no session identity refuses rather than guessing"
eq "$(bstatus s-load)" "in_progress" "and writes nothing"

# --- The formula wiring. ------------------------------------------------------
# Extracted verbatim, so a wholesale reconciliation against the base formula
# that drops the arm fails here rather than in production.
echo "== mol-polecat-work load-context refusal arm =="
ARM="$(awk '
  $0 ~ /^# >>> load-context-duplicate-dispatch-hold$/ {f=1; next}
  $0 ~ /^# <<< load-context-duplicate-dispatch-hold$/ {f=0}
  f' "$TOML")"
[ -n "$ARM" ] \
  && ok "refusal arm extracted between its markers" \
  || bad "refusal-arm extraction EMPTY — markers missing from $TOML"
has "$ARM" "molecule-hold.sh" "the refusal arm calls molecule-hold.sh"
has "$ARM" "--step \"mol-polecat-work.load-context\"" "it names its own step ref"
has "$ARM" "drain-ack" "it still drains"
hasnt "$ARM" "--status=closed" "it still closes nothing"
LC_DESC="$(python3 -c "
import sys, tomllib
d = tomllib.load(open(sys.argv[1],'rb'))
print([s for s in d['steps'] if s['id']=='load-context'][0]['description'])
" "$TOML")"
hasnt "$LC_DESC" "Leave this step bead OPEN" "the OPEN instruction is gone from the step text"
has   "$LC_DESC" "never close it" "and the not-closed invariant is still stated"
bash -n <(printf '%s\n' "$ARM") 2>/dev/null \
  && ok "the refusal arm is syntactically valid bash" \
  || bad "the refusal arm does not parse under bash -n"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
