#!/usr/bin/env bash
# Hermetic test for doctor-finding-gate.sh — the close-time gate that stops a
# bead filed against a `gc doctor` finding from closing as if the finding were
# fixed (tk-fwspr). No live city, Dolt, network, or doctor run: `gc` is a stub on
# PATH and every payload is a fixture.
#
# THE BUG. Three times on 2026-08-10, on three independent findings in three
# rigs, a bead filed against a doctor check merged, closed — and the check kept
# firing. Each landed REAL work; none of them re-ran the check at close, so
# "merged" was recorded as "fixed". The gate answers one question at close time:
# does this bead name a check that is STILL FIRING?
#
# What the arms below are actually pinning is the set of ways a gate like this
# fails SILENTLY. Every one of them looks wired and reports nothing:
#
#   (INERT)      --no-run with no cache must be INDETERMINATE, never clean. This
#                is the whole reason `publish` exists: the refinery probes with
#                --no-run, so with nothing warming the cache the arm never fires
#                once. rc 0 here would make that invisible forever.
#   (NSINERT)    the same, for a check named in FULL (`gc-toolkit:check-x`, how
#                doctor reports pack checks). The cold-cache pre-filter decides
#                whether the probe may answer at all, so a shape it does not
#                recognize is INERT for that whole class of bead — and it is
#                inert as rc 0, which the refinery cannot tell apart from a
#                verified-clean close. Half of this script already treated the
#                namespaced form as a check name; the pre-filter did not.
#   (PUBREFUSE)  publish must REFUSE an empty/drifted payload and LEAVE THE
#                PRIOR CACHE INTACT. The patrol's doctor run can come back empty
#                at its 300s bound; installed as the cache it would answer every
#                later probe "nothing is firing" — one wedged run turning into a
#                city-wide all-clear.
#   (DRIFT)      a payload without `.results` is unusable, not empty. `jq
#                '.checks[]'` over a renamed schema yields nothing rather than
#                failing, which reads as "every check is green".
#   (NOISE)      a check-SHAPED token that names no reported check must not
#                report. Prose is full of them, so matching on shape cries wolf
#                on every bead and the real one stops being read.
#   (WHOLE)      `check-set` in prose must not match a reported `check-set-heal`.
#   (STALE)      a cache past its ttl is not a payload; with --no-run that is
#                indeterminate, not a read of yesterday's answer.
#   (SUCCREAD)   an unreadable ledger must NOT mint a successor. Minting on a
#                failed read is how one transient error becomes a duplicate
#                successor every single pass.
#
# Also covered: firing/green intersection, bare-named builtins (the third
# instance, `census-owner-liveness`, carries no `check-` prefix), namespaced
# names, explicit metadata.doctor_check, successor dedup/mint, and that a minted
# successor's metadata carries no literal quote characters.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/doctor-finding-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

[ -x "$SCRIPT" ] || { echo "FAIL - $SCRIPT is not executable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP - jq unavailable"; exit 0; }

# --- the `gc` stub -----------------------------------------------------------
# Answers from fixture files under $TMP so every arm states its own world. The
# distinction that matters most: a MISSING ledger fixture prints nothing (an
# unreadable store), an EMPTY-ARRAY fixture prints `[]` (a readable store with no
# match). The successor lookup must treat those as different — see (SUCCREAD).
mkdir -p "$TMP/bin" "$TMP/beads" "$TMP/ledger"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
sub="${1:-}"; shift || true
case "$sub" in
  bd)
    verb="${1:-}"; shift || true
    case "$verb" in
      show)
        f="$GCSTUB/beads/${1:-}.json"
        [ -f "$f" ] || exit 1
        cat "$f" ;;
      list)
        check=""
        for a in "$@"; do
          case "$a" in doctor_check=*) check="${a#doctor_check=}" ;; esac
        done
        f="$GCSTUB/ledger/$check.json"
        # Missing fixture = unreadable ledger: print NOTHING, non-zero.
        [ -f "$f" ] || exit 1
        cat "$f" ;;
      create)
        # Drain any stdin body so a --body-file - caller never blocks.
        for a in "$@"; do
          case "$a" in --body-file) cat >/dev/null 2>&1 || true ;; esac
        done
        if [ -f "$GCSTUB/create-fails" ]; then exit 1; fi
        n=$(cat "$GCSTUB/counter" 2>/dev/null || echo 0); n=$((n + 1))
        printf '%s' "$n" > "$GCSTUB/counter"
        printf '{"id":"tk-new%s"}\n' "$n" ;;
      update)
        printf '%s\n' "$*" >> "$GCSTUB/update.log" ;;
      *) exit 1 ;;
    esac ;;
  doctor)
    [ -f "$GCSTUB/doctor.json" ] || exit 1
    cat "$GCSTUB/doctor.json"
    # `gc doctor` exits 1 when findings exist — the NORMAL case.
    exit 1 ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gc"
export GCSTUB="$TMP"
export PATH="$TMP/bin:$PATH"

# bead <id> <title> <description> <notes> [doctor_check]
bead() {
  jq -n --arg t "$2" --arg d "$3" --arg n "$4" --arg c "${5:-}" \
    '[{title:$t, description:$d, notes:$n,
       metadata: (if $c == "" then {} else {doctor_check:$c} end)}]' \
    > "$TMP/beads/$1.json"
}
# payload <file> <name:status> ...
# Split on the LAST colon, never the first: check names are themselves
# colon-namespaced (`gc-toolkit:check-x`), so `%%:*` would register a fixture
# check called `gc-toolkit` and the namespaced arm would be testing nothing.
payload() {
  local f="$1"; shift
  local arr="[]" pair
  for pair in "$@"; do
    arr=$(jq -c --arg n "${pair%:*}" --arg s "${pair##*:}" \
            '. + [{name:$n, status:$s, severity:"blocking", message:"x"}]' <<<"$arr")
  done
  jq -n --argjson r "$arr" '{ok:1, failed:1, results:$r}' > "$f"
}

CACHE="$TMP/cache.json"
FRESH="$TMP/fresh.json"
payload "$FRESH" \
  "check-rig-scoped-orders-bound:error" \
  "check-base-artifact-collision:warning" \
  "census-owner-liveness:error" \
  "gc-toolkit:check-namespaced:error" \
  "check-set-heal:error" \
  "check-liveness-sweep-wired:ok"

# =============================================================================
# publish
# =============================================================================
rm -f "$CACHE"
out=$("$SCRIPT" publish "$FRESH" --cache "$CACHE" 2>/dev/null); rc=$?
eq "$rc" "0" "(PUBLISH) a valid payload publishes"
eq "$out" "$CACHE" "(PUBLISH) prints the cache path it installed"
eq "$(jq -r '.results | length' "$CACHE" 2>/dev/null)" "6" "(PUBLISH) cache carries the payload"

out=$(printf '%s' "$(cat "$FRESH")" | "$SCRIPT" publish - --cache "$TMP/stdin.json" 2>/dev/null); rc=$?
eq "$rc" "0" "(PUBSTDIN) publishes from stdin via -"
eq "$(jq -r '.results | length' "$TMP/stdin.json" 2>/dev/null)" "6" "(PUBSTDIN) stdin payload lands"

# The cache the refinery would read, resolved from the env rather than --cache.
GC_DOCTOR_GATE_CACHE="$TMP/env.json" "$SCRIPT" publish "$FRESH" >/dev/null 2>&1
eq "$(jq -r '.results | length' "$TMP/env.json" 2>/dev/null)" "6" \
   "(PUBENV) GC_DOCTOR_GATE_CACHE resolves the same path for writer and reader"

# The critical refusal: a bad payload must not replace a good cache.
before=$(cat "$CACHE")
: > "$TMP/empty.json"
"$SCRIPT" publish "$TMP/empty.json" --cache "$CACHE" >/dev/null 2>&1
eq "$?" "2" "(PUBREFUSE) an empty payload is refused"
eq "$(cat "$CACHE")" "$before" "(PUBREFUSE) the prior cache is left INTACT"

echo '{"checks":[{"name":"check-x","status":"error"}]}' > "$TMP/drift.json"
"$SCRIPT" publish "$TMP/drift.json" --cache "$CACHE" >/dev/null 2>&1
eq "$?" "2" "(DRIFT) a payload with no .results is refused"
eq "$(cat "$CACHE")" "$before" "(DRIFT) the prior cache survives schema drift"

echo 'not json at all' > "$TMP/garbage.json"
"$SCRIPT" publish "$TMP/garbage.json" --cache "$CACHE" >/dev/null 2>&1
eq "$?" "2" "(PUBREFUSE) unparseable input is refused"

"$SCRIPT" publish "$TMP/does-not-exist.json" --cache "$CACHE" >/dev/null 2>&1
eq "$?" "2" "(PUBREFUSE) a missing source file is refused"

# =============================================================================
# probe — the intersection
# =============================================================================
bead b-firing "gc doctor: check-rig-scoped-orders-bound still unresolved" \
     "the orders fire unbound" "" ""
out=$("$SCRIPT" probe b-firing --json "$FRESH" 2>/dev/null); rc=$?
eq "$rc" "1" "(FIRING) a named, firing check exits 1"
eq "$out" "check-rig-scoped-orders-bound" "(FIRING) it names the check"

bead b-green "the check-liveness-sweep-wired check is fine now" "" "" ""
out=$("$SCRIPT" probe b-green --json "$FRESH" 2>/dev/null); rc=$?
eq "$rc" "0" "(GREEN) a named check that is ok exits 0"
eq "$out" "" "(GREEN) and reports nothing"

# A bead naming TWO checks where only one fires — the shape that makes
# match-on-regex unusable, since both tokens look identical.
bead b-mixed "check-rig-scoped-orders-bound and check-liveness-sweep-wired" "" "" ""
out=$("$SCRIPT" probe b-mixed --json "$FRESH" 2>/dev/null); rc=$?
eq "$rc" "1" "(MIXED) reports when any named check fires"
eq "$out" "check-rig-scoped-orders-bound" "(MIXED) reports ONLY the firing one"

bead b-noise "check-name and check-scope are prose, not checks" "" "" ""
out=$("$SCRIPT" probe b-noise --json "$FRESH" 2>/dev/null); rc=$?
eq "$rc" "0" "(NOISE) check-shaped prose naming no reported check exits 0"
eq "$out" "" "(NOISE) and stays silent"

bead b-whole "the check-set is normalized" "" "" ""
out=$("$SCRIPT" probe b-whole --json "$FRESH" 2>/dev/null); rc=$?
eq "$rc" "0" "(WHOLE) check-set does not match reported check-set-heal"

bead b-bare "census-owner-liveness reports dangling owner_bead references" "" "" ""
out=$("$SCRIPT" probe b-bare --json "$FRESH" 2>/dev/null); rc=$?
eq "$rc" "1" "(BARE) a bare-named builtin check matches"
eq "$out" "census-owner-liveness" "(BARE) it names the bare check"

bead b-ns "see check-namespaced for the detail" "" "" ""
out=$("$SCRIPT" probe b-ns --json "$FRESH" 2>/dev/null); rc=$?
eq "$rc" "1" "(NAMESPACE) a namespaced check matches on its bare suffix"
eq "$out" "gc-toolkit:check-namespaced" "(NAMESPACE) it reports the full name"

# The other way a namespaced check is written — in FULL, which is how doctor
# itself reports it and how a filer copying a doctor line would name it.
bead b-nsfull "gc doctor: gc-toolkit:check-namespaced is still firing" "" "" ""
out=$("$SCRIPT" probe b-nsfull --json "$FRESH" 2>/dev/null); rc=$?
eq "$rc" "1" "(NSFULL) a full namespaced token matches"
eq "$out" "gc-toolkit:check-namespaced" "(NSFULL) it reports the full name"

bead b-path "see specs/tk-gi2pc/check-rig-scoped-orders-bound.md" "" "" ""
eq "$("$SCRIPT" probe b-path --json "$FRESH" >/dev/null 2>&1; echo $?)" "1" \
   "(TOKENIZE) a check name embedded in a path still matches"

bead b-explicit "nothing check-shaped in this title at all" "" "" "census-owner-liveness"
out=$("$SCRIPT" probe b-explicit --json "$FRESH" 2>/dev/null); rc=$?
eq "$rc" "1" "(EXPLICIT) metadata.doctor_check matches with no prose token"
eq "$out" "census-owner-liveness" "(EXPLICIT) it names the declared check"

bead b-notes "unrelated title" "unrelated body" "notes mention check-base-artifact-collision" ""
eq "$("$SCRIPT" probe b-notes --json "$FRESH" >/dev/null 2>&1; echo $?)" "1" \
   "(NOTES) notes are searched too"

# An unknown future status must read as FIRING — the gate refuses to certify
# what it cannot classify.
payload "$TMP/weird.json" "check-weird:quarantined"
bead b-weird "check-weird is doing something new" "" "" ""
eq "$("$SCRIPT" probe b-weird --json "$TMP/weird.json" >/dev/null 2>&1; echo $?)" "1" \
   "(UNKNOWNSTATUS) an unrecognized status counts as firing"

payload "$TMP/skipped.json" "check-skipped:skipped"
bead b-skip "check-skipped is skipped" "" "" ""
eq "$("$SCRIPT" probe b-skip --json "$TMP/skipped.json" >/dev/null 2>&1; echo $?)" "0" \
   "(SKIPPED) a skipped check is not firing"

# =============================================================================
# probe — payload resolution, and the inert-gate regression
# =============================================================================
COLD="$TMP/nonexistent-cache.json"
rm -f "$COLD"
bead b-plaus "check-rig-scoped-orders-bound is still open" "" "" ""
"$SCRIPT" probe b-plaus --cache "$COLD" --no-run >/dev/null 2>&1
eq "$?" "2" "(INERT) --no-run with a cold cache is INDETERMINATE, never clean"

bead b-routine "ordinary work bead, no checks named" "just code" "" ""
"$SCRIPT" probe b-routine --cache "$COLD" --no-run >/dev/null 2>&1
eq "$?" "0" "(ROUTINE) a bead naming nothing check-shaped is clean on a cold cache"

# (NSINERT) The same INERT claim for a bead whose ONLY check token is written in
# full, `gc-toolkit:check-namespaced`. The pre-filter decides whether the probe
# may answer at all on a cold cache, so a shape it does not recognize returns
# CLEAN — indistinguishable, at the refinery close arm, from a gate that ran and
# found nothing: no annotation, and not even a dgate_unknown to say the gate was
# never evaluated. A namespaced pack-check anchor would close as verified-clean
# having verified nothing, which is the silent-inert failure (INERT) above pins
# for the bare shape.
"$SCRIPT" probe b-nsfull --cache "$COLD" --no-run >/dev/null 2>&1
eq "$?" "2" "(NSINERT) a FULL namespaced token is plausible: cold cache + --no-run is INDETERMINATE"

# ...and the pre-filter must stay narrow while it is wider: a colon token that is
# not a namespace-before-a-check (a timestamp out of a bead note) must still buy
# no doctor run, or every routine close pays for one.
bead b-colon "mayor note 2026-08-10T18:55Z about ordinary work" "" "" ""
"$SCRIPT" probe b-colon --cache "$COLD" --no-run >/dev/null 2>&1
eq "$?" "0" "(NSNARROW) a colon token that names no check is still clean on a cold cache"

# publish, then the same cold-cache probe answers for real — the end-to-end
# claim the patrol wiring rests on.
"$SCRIPT" publish "$FRESH" --cache "$COLD" >/dev/null 2>&1
out=$("$SCRIPT" probe b-plaus --cache "$COLD" --no-run 2>/dev/null); rc=$?
eq "$rc" "1" "(WARM) after publish, the same --no-run probe reports the finding"
eq "$out" "check-rig-scoped-orders-bound" "(WARM) and names it"
out=$("$SCRIPT" probe b-nsfull --cache "$COLD" --no-run 2>/dev/null); rc=$?
eq "$rc" "1" "(WARM) the full-namespaced bead answers from the same warm cache"
eq "$out" "gc-toolkit:check-namespaced" "(WARM) and names the namespaced check"

# A cache older than the ttl is not a payload.
touch -t 200001010000 "$COLD" 2>/dev/null || true
"$SCRIPT" probe b-plaus --cache "$COLD" --ttl 60 --no-run >/dev/null 2>&1
eq "$?" "2" "(STALE) a cache past its ttl is indeterminate under --no-run"
out=$("$SCRIPT" probe b-plaus --cache "$COLD" --ttl 999999999 --no-run 2>/dev/null)
eq "$out" "check-rig-scoped-orders-bound" "(TTL) within ttl the same cache is used"

# A live run happens only without --no-run, and publishes what it ran.
cp "$FRESH" "$TMP/doctor.json"
LIVE="$TMP/live-cache.json"; rm -f "$LIVE"
out=$("$SCRIPT" probe b-plaus --cache "$LIVE" 2>/dev/null); rc=$?
eq "$rc" "1" "(LIVERUN) with no cache and no --no-run, doctor is run"
eq "$out" "check-rig-scoped-orders-bound" "(LIVERUN) and the finding is reported"
eq "$(jq -r '.results | length' "$LIVE" 2>/dev/null)" "6" \
   "(LIVERUN) the live run publishes its payload for the next caller"

# A routine bead never triggers a run: the cache must stay absent.
NORUN="$TMP/never.json"; rm -f "$NORUN"
"$SCRIPT" probe b-routine --cache "$NORUN" >/dev/null 2>&1
eq "$?" "0" "(NOSPEND) a routine close is clean without running doctor"
[ -f "$NORUN" ] && bad "(NOSPEND) a routine close must not run doctor" \
                || ok "(NOSPEND) no doctor run was paid for"

# =============================================================================
# probe — fail-soft
# =============================================================================
"$SCRIPT" probe no-such-bead --json "$FRESH" >/dev/null 2>&1
eq "$?" "2" "(UNREADABLE) an unreadable bead is indeterminate"
"$SCRIPT" probe b-firing --json "$TMP/drift.json" >/dev/null 2>&1
eq "$?" "2" "(DRIFT) a drifted --json payload is indeterminate, not clean"
"$SCRIPT" probe >/dev/null 2>&1
eq "$?" "2" "(USAGE) probe with no bead id is indeterminate"
"$SCRIPT" bogus-subcommand >/dev/null 2>&1
eq "$?" "2" "(USAGE) an unknown subcommand exits 2"

# =============================================================================
# successor
# =============================================================================
jq -n '[{id:"tk-open1", status:"open"}]' > "$TMP/ledger/check-dup.json"
out=$("$SCRIPT" successor check-dup --pool p 2>/dev/null); rc=$?
eq "$rc" "0" "(SUCCDEDUP) an existing open successor is reused"
eq "$out" "tk-open1" "(SUCCDEDUP) it returns that bead"

jq -n '[{id:"tk-claimed", status:"in_progress"}]' > "$TMP/ledger/check-claimed.json"
eq "$("$SCRIPT" successor check-claimed 2>/dev/null)" "tk-claimed" \
   "(SUCCCLAIMED) an in_progress successor counts as live"

echo '[]' > "$TMP/ledger/check-fresh.json"
out=$("$SCRIPT" successor check-fresh --pool mypool --source tk-src 2>/dev/null); rc=$?
eq "$rc" "0" "(SUCCMINT) with no existing successor, one is minted"
case "$out" in tk-new*) ok "(SUCCMINT) it returns the new bead id" ;;
  *) bad "(SUCCMINT) expected a minted id, got '$out'" ;; esac
grep -q "doctor_check=check-fresh" "$TMP/update.log" \
  && ok "(SUCCMINT) the successor carries metadata.doctor_check" \
  || bad "(SUCCMINT) missing doctor_check stamp"
grep -q "gc.routed_to=mypool" "$TMP/update.log" \
  && ok "(SUCCMINT) it is routed to the fix pool" \
  || bad "(SUCCMINT) missing route"
grep -q "doctor_finding_predecessor=tk-src" "$TMP/update.log" \
  && ok "(SUCCMINT) it records the predecessor" \
  || bad "(SUCCMINT) missing predecessor"
grep -q '"' "$TMP/update.log" \
  && bad "(SUCCQUOTE) metadata values carry literal quote characters" \
  || ok "(SUCCQUOTE) optional flags carry no literal quotes"

# The one that must NOT mint: no ledger fixture = the read failed.
before_count=$(cat "$TMP/counter" 2>/dev/null || echo 0)
"$SCRIPT" successor check-unreadable --pool p >/dev/null 2>&1
eq "$?" "2" "(SUCCREAD) an unreadable ledger is indeterminate"
eq "$(cat "$TMP/counter" 2>/dev/null || echo 0)" "$before_count" \
   "(SUCCREAD) and NO successor is minted on a failed read"

echo '[]' > "$TMP/ledger/check-createfail.json"
touch "$TMP/create-fails"
"$SCRIPT" successor check-createfail >/dev/null 2>&1
eq "$?" "2" "(SUCCCREATE) a failed create is reported, not faked"
rm -f "$TMP/create-fails"

"$SCRIPT" successor >/dev/null 2>&1
eq "$?" "2" "(USAGE) successor with no check name is indeterminate"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
