#!/usr/bin/env bash
# Hermetic test for assets/scripts/molecule-hold.sh.
#
# The constraint: a graph.v2 refusal arm that declines work it must not close
# has to leave its step not-claimable as well as not-closed. `open` is half the
# pool's offer predicate, so an arm that drains leaving its step open has it
# re-offered to a fresh worker, which re-derives the same refusal and leaves it
# open again, one pool slot per cycle.
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
#   * the ATOMICITY anchor — bd's claim guard refuses `--assignee ""`
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
#   * fail-closed on the QUIESCE too — exit 0 is what lets the caller drain, so
#     a root or sibling route that survived exits 1. A sibling whose route clear
#     failed keeps its claim: unassigning it there writes the offer predicate
#     `open + unassigned + routed` rather than escaping it;
#   * ambiguity and unresolvable identity are refused with no writes;
#   * idempotence: an already-blocked step is a normal re-run, and the re-run
#     still repairs a root or sibling an earlier run failed to quiesce;
#   * the SUBSTRING trap — session lx-zzk must not own lx-zzk9's bead;
#   * control characters in bd's JSON, which break an unfiltered `| jq`;
#   * usage errors, including a value-taking option at the end of argv;
#   * the FORMULA WIRING — mol-polecat-work's load-context refusal arm is
#     extracted verbatim and must call the script rather than say "leave it
#     open", escalate through escalate.sh rather than mail, and drain only
#     after a hold that landed.
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
#               --append-notes to the store; refuses ids listed in $FAKE_UPDFAIL,
#               and — for the partial-quiesce arms — refuses only the route
#               clear for ids in $FAKE_UPDFAIL_ROUTE, only the assignee clear
#               for ids in $FAKE_UPDFAIL_ASSIGNEE.
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
    if [ -f "${FAKE_SHOWFAIL:-/dev/null}" ] && grep -qx "${1:-}" "${FAKE_SHOWFAIL:-/dev/null}" 2>/dev/null; then
      echo "bd: cannot show ${1:-} (stub)" >&2
      exit 1
    fi
    if [ -n "${FAKE_OBJ_SHOW:-}" ] && [ "${FAKE_OBJ_SHOW:-}" = "${1:-}" ]; then
      # bd returns an object, not a one-element array, when nothing resolves.
      printf '{"error":"no such issue","id":"%s"}\n' "${1:-}"
      exit 0
    fi
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
    # The sibling enumeration is the only list of exactly open,in_progress with
    # no assignee filter; discover() always pins an assignee. Fail only that one.
    if [ "$wstatus" = "open,in_progress" ] && [ -z "$wassignee" ]; then
      if [ "${FAKE_LISTFAIL:-0}" = "1" ]; then
        echo "bd: cannot list (stub)" >&2
        exit 1
      fi
      if [ "${FAKE_BADJSON_LIST:-0}" = "1" ]; then
        printf 'this is not an array\n'
        exit 0
      fi
    fi
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
    case " $* " in
      *" --unset-metadata gc.routed_to "*)
        if [ -f "${FAKE_UPDFAIL_ROUTE:-/dev/null}" ] && grep -qx "$id" "${FAKE_UPDFAIL_ROUTE:-/dev/null}" 2>/dev/null; then
          echo "bd: cannot clear the route on $id (stub)" >&2
          exit 1
        fi ;;
    esac
    case " $* " in
      *" --assignee "*)
        if [ -f "${FAKE_UPDFAIL_ASSIGNEE:-/dev/null}" ] && grep -qx "$id" "${FAKE_UPDFAIL_ASSIGNEE:-/dev/null}" 2>/dev/null; then
          echo "bd: cannot unassign $id (stub)" >&2
          exit 1
        fi ;;
    esac
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
    tmp="$S.work.$$"; cp "$S" "$tmp"
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
export FAKE_UPDFAIL_ROUTE="$TMP/updfail.route" FAKE_UPDFAIL_ASSIGNEE="$TMP/updfail.assignee"
export FAKE_SHOWFAIL="$TMP/showfail"

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
  : > "$GC_LOG"; : > "$FAKE_UPDFAIL"; : > "$FAKE_UPDFAIL_ROUTE"; : > "$FAKE_UPDFAIL_ASSIGNEE"; : > "$FAKE_SHOWFAIL"
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

echo "== atomicity: the blocking write carries no assignee (a batched --assignee rolls the status back) =="
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

# The re-run is the only repair path once the step is blocked: blocked is not
# claimable, so nothing else comes back to finish a quiesce that half-landed.
echo "== idempotence repairs a quiesce that did not finish =="
reset_store
printf 'root-1\ns-impl\n' > "$FAKE_UPDFAIL"
OUT=$("$SCRIPT" --step "$STEP" --reason "first pass" 2>&1); RC=$?
eq "$RC" "1" "the first pass reports the incomplete quiesce"
eq "$(meta root-1 'gc.routed_to')" "$POOL" "and leaves the root routed"
: > "$FAKE_UPDFAIL"
OUT=$("$SCRIPT" --step "$STEP" --reason "second pass" 2>&1); RC=$?
eq "$RC" "0" "the re-run over the already-blocked step exits 0 once the writes go through"
has "$OUT" "already blocked" "it recognises the existing hold"
eq "$(meta root-1 'gc.routed_to')" "<absent>" "and de-routes the root the first pass could not"
eq "$(meta s-impl 'gc.routed_to')" "<absent>" "the sibling is de-routed too"
eq "$(bassignee s-impl)" "" "and unassigned"
eq "$(bstatus s-load)" "blocked" "the step is still blocked, not re-blocked into some other state"

# The same repair through the hint path: --bead naming an already-blocked step
# still has to check the root and the siblings.
reset_store
printf 'root-1\n' > "$FAKE_UPDFAIL"
"$SCRIPT" --step "$STEP" --reason "first pass" >/dev/null 2>&1
: > "$FAKE_UPDFAIL"
OUT=$("$SCRIPT" --step "$STEP" --bead s-load --reason "second pass" 2>&1); RC=$?
eq "$RC" "0" "--bead naming an already-blocked step exits 0"
has "$OUT" "already blocked" "and recognises the existing hold"
eq "$(meta root-1 'gc.routed_to')" "<absent>" "and repairs the root the first pass left routed"

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

echo "== fail-closed: a root that stays routed is not a hold =="
reset_store
printf 'root-1\n' > "$FAKE_UPDFAIL"
OUT=$("$SCRIPT" --step "$STEP" --reason "root resists" 2>&1); RC=$?
eq "$RC" "1" "a root whose route clear failed exits 1 — draining there re-offers the molecule"
has "$OUT" "could not de-route root root-1" "the root that resisted is named"
has "$OUT" "Do not drain" "and the caller is told what not to do"
eq "$(bstatus s-load)"             "blocked" "the step is still held — the failure is downstream of the load-bearing write"
eq "$(meta root-1 'gc.routed_to')" "$POOL"   "the root demonstrably still carries the route"
eq "$(meta s-setup 'gc.routed_to')" "<absent>" "the siblings are still quiesced best-effort"
hasnt "$(gclog)" "--status=closed" "the incomplete-quiesce arm closes nothing"

echo "== fail-closed: a sibling that stays routed keeps its claim =="
reset_store
printf 's-impl\n' > "$FAKE_UPDFAIL_ROUTE"
OUT=$("$SCRIPT" --step "$STEP" --reason "sibling route resists" 2>&1); RC=$?
eq "$RC" "1" "an unquiesceable sibling exits 1"
has "$OUT" "could not de-route sibling step s-impl" "the sibling that resisted is named"
eq "$(bstatus s-load)" "blocked" "the held step is still held"
eq "$(meta s-impl 'gc.routed_to')" "$POOL" "and it demonstrably still carries the route"
eq "$(bassignee s-impl)" "$MINE" "its claim is RETAINED — an unassigned routed step is exactly what the pool offers"
hasnt "$(gclog)" "bd update s-impl --assignee" "the assignee clear is not even attempted once the route clear failed"
eq "$(meta s-setup 'gc.routed_to')" "<absent>" "the other siblings are still quiesced"
eq "$(bassignee s-setup)"           ""         "and still unassigned"
hasnt "$(gclog)" "--status=closed" "the partial-quiesce arm closes nothing"

echo "== fail-closed: a sibling that cannot be unassigned =="
reset_store
printf 's-setup\n' > "$FAKE_UPDFAIL_ASSIGNEE"
OUT=$("$SCRIPT" --step "$STEP" --reason "sibling claim resists" 2>&1); RC=$?
eq "$RC" "1" "a sibling left open AND assigned exits 1 — the stranded-worker sweep re-routes it"
has "$OUT" "could not unassign sibling step s-setup" "the sibling that resisted is named"
eq "$(meta s-setup 'gc.routed_to')" "<absent>" "its route did come off"
eq "$(bassignee s-setup)" "$MINE" "but the claim that puts it in the sweep tier is still there"
eq "$(bassignee s-impl)"  ""      "the other siblings are still quiesced"

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

echo "== a rootless step is held but fails closed: a missing root is not a quiet molecule =="
reset_store
jq -c 'map(if .id == "s-load" then (.metadata |= del(.["gc.root_bead_id"])) else . end)' \
  "$FAKE_STORE" > "$TMP/s" && mv "$TMP/s" "$FAKE_STORE"
OUT=$("$SCRIPT" --step "$STEP" --reason "no root" 2>&1); RC=$?
eq "$RC" "1" "a missing root exits 1 — every caller is a molecule step, so no root is corruption, not a quiet molecule"
eq "$(bstatus s-load)" "blocked" "the step is still held — the missing root is downstream of the load-bearing write"
has "$OUT" "carries no gc.root_bead_id" "and the gap is reported, not hidden"
has "$OUT" "Do not drain" "and the caller is told not to drain"
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

echo "== an enumeration that cannot happen says so, rather than going quiet =="
reset_store
cat > "$TMP/bin/mktemp" <<'MT'
#!/usr/bin/env bash
echo "mktemp: no space left on device (stub)" >&2
exit 1
MT
chmod +x "$TMP/bin/mktemp"
OUT=$("$SCRIPT" --step "$STEP" --reason "disk pressure" 2>&1); RC=$?
rm -f "$TMP/bin/mktemp"
eq "$RC" "1" "an enumeration that cannot be staged exits 1 — its siblings keep the routes it never cleared"
eq "$(bstatus s-load)" "blocked" "the load-bearing write happened first"
eq "$(meta root-1 'gc.routed_to')" "<absent>" "and the root is still de-routed"
has "$OUT" "siblings keep the routes and claims" "the un-quiesced siblings are named, not silently skipped"
eq "$(meta s-setup 'gc.routed_to')" "$POOL" "and they demonstrably still carry them"

# ── The quiesce reads themselves can fail. bd_json swallows gc's exit through
# the pipe, so a failed show/list once read as an empty result — an empty root
# route or an empty sibling set — and the molecule drained "quiet" while its root
# or siblings were never read. Each read now fails closed on a bad command or a
# non-array payload, keeping that distinct from a genuinely empty store.
echo "== fail-closed: a target whose own read fails cannot resolve a root to quiesce =="
reset_store
echo "s-load" > "$FAKE_SHOWFAIL"
OUT=$("$SCRIPT" --step "$STEP" --reason "target unreadable" 2>&1); RC=$?
: > "$FAKE_SHOWFAIL"
eq "$RC" "1" "a target whose root-resolving read fails exits 1, not 0"
has "$OUT" "could not read s-load to resolve its root" "the unreadable target is named"
has "$OUT" "Do not drain" "and the caller is told not to drain"
eq "$(bstatus s-load)" "blocked" "the step is still held — the read failure is downstream of the load-bearing write"
eq "$(meta root-1 'gc.routed_to')" "$POOL" "the root is left untouched, not falsely reported quiet"

echo "== fail-closed: a root whose route cannot be READ is not a quiet root =="
reset_store
echo "root-1" > "$FAKE_SHOWFAIL"
OUT=$("$SCRIPT" --step "$STEP" --reason "root route unreadable" 2>&1); RC=$?
: > "$FAKE_SHOWFAIL"
eq "$RC" "1" "a root whose show fails exits 1 — an unread route cannot be proven clear"
has "$OUT" "could not read root root-1 to check its route" "the unreadable root is named"
has "$OUT" "Do not drain" "and the caller is told not to drain"
eq "$(bstatus s-load)" "blocked" "the step is still held"
eq "$(meta root-1 'gc.routed_to')" "$POOL" "the route is left intact, not falsely reported clear"

echo "== fail-closed: a root show that returns an OBJECT, not an array, is unreadable =="
reset_store
OUT=$(FAKE_OBJ_SHOW=root-1 "$SCRIPT" --step "$STEP" --reason "root resolves to an object" 2>&1); RC=$?
eq "$RC" "1" "a non-array root payload exits 1 — bd returns an object when nothing resolves, and that is not a quiet root"
has "$OUT" "could not read root root-1 to check its route" "the unreadable-shape root is named"
eq "$(meta root-1 'gc.routed_to')" "$POOL" "its route is left intact, not falsely reported clear"

echo "== fail-closed: a sibling enumeration that FAILS is not an empty one =="
reset_store
OUT=$(FAKE_LISTFAIL=1 "$SCRIPT" --step "$STEP" --reason "sibling list unreadable" 2>&1); RC=$?
eq "$RC" "1" "a failed sibling enumeration exits 1 — an unread sibling set cannot be proven quiet"
has "$OUT" "could not enumerate sibling steps" "the failed enumeration is named"
has "$OUT" "Do not drain" "and the caller is told not to drain"
eq "$(bstatus s-load)" "blocked" "the step is still held"
eq "$(meta root-1 'gc.routed_to')" "<absent>" "the root was de-routed before the enumeration failed"
eq "$(bassignee s-setup)" "$MINE" "the siblings keep their claims — an unproven set is not quiesced"

echo "== fail-closed: an unparseable sibling payload is not an empty one =="
reset_store
OUT=$(FAKE_BADJSON_LIST=1 "$SCRIPT" --step "$STEP" --reason "sibling list unparseable" 2>&1); RC=$?
eq "$RC" "1" "a sibling list that returns non-array JSON exits 1 — an unparseable set is not a quiet one"
has "$OUT" "could not enumerate sibling steps" "the unparseable enumeration is named"
eq "$(bstatus s-load)" "blocked" "the step is still held"
eq "$(bassignee s-setup)" "$MINE" "the siblings keep their claims"

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
hasnt "$ARM" "gc mail send" "it escalates rather than mails; a polecat's mail budget is zero"
has "$ARM" "escalate.sh" "and it escalates through escalate.sh"

# The arm executed, against a helper that refuses. A drain on that path leaves
# the step claimable, which is the loop the hold exists to stop.
mkdir -p "$TMP/armpack/assets/scripts"
cat > "$TMP/armpack/assets/scripts/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf 'ESCALATE %s\n' "$*" >> "${ARM_LOG:?}"
exit 0
ESC
cat > "$TMP/armpack/assets/scripts/molecule-hold.sh" <<'MHSTUB'
#!/usr/bin/env bash
printf 'HOLD %s\n' "$*" >> "${ARM_LOG:?}"
exit "${ARM_HOLD_RC:-0}"
MHSTUB
chmod +x "$TMP/armpack/assets/scripts/escalate.sh" "$TMP/armpack/assets/scripts/molecule-hold.sh"

# run_arm <hold-exit-code> -> "<rc>"; the helper trace is left in $TMP/arm.log
# and the gc trace in $GC_LOG. {{convoy_id}} is substituted the way the
# materializer substitutes it before the polecat reads the step.
run_arm() {
  : > "$TMP/arm.log"; : > "$GC_LOG"
  printf '%s\n' "$ARM" | sed 's|{{convoy_id}}|cv-1|g' > "$TMP/arm.sh"
  local rc=0
  OWNER_LIVE=1 WORK_BEAD_ID=tk-work WORK_STATUS=in_progress WORK_OWNER=other-session \
    ARM_LOG="$TMP/arm.log" ARM_HOLD_RC="$1" \
    GC_PACK_DIR="$TMP/armpack" GC_RIG_ROOT="" GC_CITY_PATH="" \
    bash "$TMP/arm.sh" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

eq "$(run_arm 0)" "1" "the refusal arm exits 1"
has "$(cat "$TMP/arm.log")" "ESCALATE --subject tk-work" "it files an escalation on the work bead"
has "$(cat "$TMP/arm.log")" "HOLD --step mol-polecat-work.load-context" "it holds its own step"
has "$(gclog)" "runtime drain-ack" "and a hold that landed is followed by the drain"

eq "$(run_arm 1)" "1" "a refused hold still exits 1"
has "$(cat "$TMP/arm.log")" "HOLD --step mol-polecat-work.load-context" "the hold was attempted"
hasnt "$(gclog)" "runtime drain-ack" "and nothing drained: the step is still claimable"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
