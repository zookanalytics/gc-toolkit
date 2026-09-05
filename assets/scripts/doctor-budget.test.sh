#!/usr/bin/env bash
# doctor-budget.test.sh — regression test for the one doctor probe budget and
# every copy of it (precedent: control-char-scrub.test.sh).
#
# `gc doctor` runs each pack check under --check-timeout (default 60s) and, on
# expiry, ABANDONS it: internal/doctor/doctor.go boundedRun drops the goroutine
# and throws away the private buffer the check was writing to. The process is
# not killed and its answer is not read, so a check that has not printed by the
# deadline is never heard however complete it becomes afterwards.
#
# A constant per-probe `timeout` cannot hold that line. Every check here probes
# once per rig inside a loop, so the ceilings sum with the city: thirteen checks
# carrying up to eight probes each could bound every one of them correctly and
# still be abandoned. The fix is one deadline for the whole check, with each
# probe bounded by the time left before it — which makes "the summed ceilings
# fit the budget" a property of the block rather than a per-check sum to audit.
#
# Pack scripts have no include mechanism, so the block lives as marker-fenced
# copies (# >>> doctor-budget / # <<<). This suite extracts every copy and
# asserts what the pack pays for when they disagree:
#   - one block, asserted by EXECUTING it rather than by matching its text;
#   - a slice that is never more than the time left, so probes cannot sum
#     past the deadline no matter how many a check runs;
#   - a refused probe returning 124, the code `timeout` returns on expiry, so
#     each caller's existing "this store was NOT checked" arm degrades it;
#   - the end-to-end property, on a real check against a wedged data plane:
#     it prints a partial warning inside the budget instead of being abandoned;
#   - no check bounding a probe by any other means.
# Hermetic: reads the repo and stubs gc; no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
[ -d "$REPO/doctor" ] || REPO="$HERE/../.."
FENCE="doctor-budget"
CANON_HOST="$REPO/doctor/check-gate-integrity/run.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2'" ;; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-doctor-budget-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
now() { date +%s; }

extract() { awk -v f="$FENCE" '
    $0 ~ "^[[:space:]]*# >>> " f "[[:space:]]*$" {inb=1; next}
    $0 ~ "^[[:space:]]*# <<< " f "[[:space:]]*$" {inb=0}
    inb' "$1"; }

hosts() { find "$REPO/doctor" -name 'run.sh' -type f 2>/dev/null | sort; }

echo "── 1. the canonical block ──"
BLOCK="$(extract "$CANON_HOST")"
if [ -n "$BLOCK" ]; then ok "block present in check-gate-integrity"
else bad "block present in check-gate-integrity" "no marked block"; fi
printf '%s\n' "$BLOCK" > "$TMP/block.sh"
if bash -n "$TMP/block.sh" 2>/dev/null; then ok "block is valid bash"
else bad "block is valid bash" "bash -n failed"; fi

echo "── 2. every copy is byte-identical ──"
COPIES=0; DIVERGENT=0
while IFS= read -r f; do
    b="$(extract "$f")"
    [ -n "$b" ] || continue
    COPIES=$((COPIES + 1))
    if [ "$b" != "$BLOCK" ]; then
        DIVERGENT=$((DIVERGENT + 1))
        bad "$(basename "$(dirname "$f")"): copy matches canonical" "block differs from check-gate-integrity"
    fi
done < <(hosts)
[ "$DIVERGENT" -eq 0 ] && ok "all $COPIES copies identical"
# A floor, not an equality: new hosts are expected, a host going missing is not.
if [ "$COPIES" -ge 13 ]; then ok "copy census $COPIES ≥ 13"
else bad "copy census $COPIES ≥ 13" "copies disappeared — did a check inline its own bound again?"; fi

echo "── 3. the budget, derived ──"
budget() { GC_DOCTOR_CHECK_TIMEOUT="$1" bash -c 'set -u; . "$1"; printf "%s %s" "$BUDGET_TOTAL" "$BUDGET_CAP"' _ "$TMP/block.sh"; }
eq "$(budget 20)"    "20 10" "an exported budget is honored, and a probe may take at most half of it"
eq "$(budget 30s)"   "30 15" "a trailing s is accepted — the doctor's flag prints its duration that way"
eq "$(budget 1m0s)"  "60 30" "an unparseable duration falls back to the default rather than breaking every probe"
eq "$(budget '')"    "60 30" "an empty value falls back too"
# The default tracks `gc doctor --check-timeout`, whose own default is 1m0s.
eq "$(bash -c 'set -u; . "$1"; printf "%s" "$BUDGET_TOTAL"' _ "$TMP/block.sh")" "60" \
   "unset leaves the doctor's own 60s default, which is what runs today"

echo "── 4. the slice is the time left, capped ──"
SLICES="$(GC_DOCTOR_CHECK_TIMEOUT=20 bash -c '
    set -u; . "$1"
    printf "%s " "$(budget_slice)"                                  # capped at half
    BUDGET_DEADLINE=$(( $(budget_now) + 3 )); printf "%s " "$(budget_slice)"   # under the cap
    BUDGET_DEADLINE=$(( $(budget_now) - 9 )); printf "%s " "$(budget_slice)"   # past it
    budget_spent && printf spent' _ "$TMP/block.sh")"
eq "$SLICES" "10 3 0 spent" "the slice is min(cap, time left), floors at 0, and then reports itself spent"
RC="$(bash -c 'set -u; . "$1"; BUDGET_DEADLINE=$(( $(budget_now) - 9 ))
    run_bounded touch "$2"; printf "%s" "$?"' _ "$TMP/block.sh" "$TMP/ran")"
eq "$RC" "124" "a probe that no longer fits returns 124 — what \`timeout\` returns on expiry"
if [ -f "$TMP/ran" ]; then bad "a refused probe does not run its command" "the command ran anyway"
else ok "a refused probe does not run its command"; fi

echo "── 5. summed ceilings cannot exceed the budget ──"
# Executed, not counted: eight probes that would each take 4s, under a 10s
# budget. The deadline is what bounds them, so the loop finishes early AND
# reaches the line after it — the report step a killed check never reaches.
S=$(now)
OUT="$(GC_DOCTOR_CHECK_TIMEOUT=10 bash -c '
    set -u; . "$1"
    for _ in 1 2 3 4 5 6 7 8; do run_bounded sleep 4; done
    budget_spent && printf reported' _ "$TMP/block.sh")"
E=$(( $(now) - S ))
eq "$OUT" "reported" "the check reaches its report step after the probes"
if [ "$E" -lt 10 ]; then ok "8×4s of probes fit inside a 10s budget (took ${E}s)"
else bad "8×4s of probes fit inside a 10s budget" "took ${E}s"; fi
# The control: the same eight probes under a constant per-probe bound, which is
# the shape this block replaces. Without it §5 would pass on any fast fixture.
S=$(now)
bash -c 'for _ in 1 2 3 4 5 6 7 8; do timeout 4 sleep 4; done' >/dev/null 2>&1
C=$(( $(now) - S ))
if [ "$C" -gt 10 ]; then ok "a constant 4s bound on the same eight overruns it (took ${C}s, control)"
else bad "a constant 4s bound on the same eight overruns it (control)" \
        "took ${C}s — the fixture no longer discriminates, so §5 proves nothing"; fi

echo "── 6. a wedged data plane warns, in budget, rather than being abandoned ──"
# A real check against a store that never answers. gc doctor would abandon it
# and report "outcome unknown"; the deadline makes it say what it could not read.
mkdir -p "$TMP/bin" "$TMP/rigs"
printf '{"rigs":[' > "$TMP/rigs.json"
for i in 1 2 3 4 5 6; do
    mkdir -p "$TMP/rigs/r$i"
    [ "$i" = 1 ] || printf ',' >> "$TMP/rigs.json"
    printf '{"name":"r%s","path":"%s/rigs/r%s"}' "$i" "$TMP" "$i" >> "$TMP/rigs.json"
done
printf ']}' >> "$TMP/rigs.json"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") cat "$RIGS_JSON" ;;
  "bd list")  sleep 60 ;;            # the wedged data plane
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"
S=$(now)
OUT="$(PATH="$TMP/bin:$PATH" RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" \
       GC_DOCTOR_CHECK_TIMEOUT=12 bash "$CANON_HOST" 2>&1)"; RC=$?
E=$(( $(now) - S ))
if [ "$E" -lt 12 ]; then ok "the check returns inside its 12s budget (took ${E}s)"
else bad "the check returns inside its 12s budget" "took ${E}s — gc doctor would have abandoned it"; fi
eq "$RC" "1" "an undeterminable run warns (1) — it neither passes nor errors"
has "$OUT" "doctor budget before every probe ran" "it says the budget, not the data, ended the run"
has "$OUT" "was NOT checked" "and names the stores it could not read"
# Six stores, and every one of them is accounted for.
MISSED=0
for i in 1 2 3 4 5 6; do case "$OUT" in *"r$i:"*) ;; *) MISSED=$((MISSED + 1)) ;; esac; done
eq "$MISSED" "0" "every store is named, including the five the deadline refused outright"

echo "── 7. no check bounds a probe by any other means ──"
STRAY=0
while IFS= read -r f; do
    rel="doctor/$(basename "$(dirname "$f")")/run.sh"
    body="$(awk -v f="$FENCE" '
        $0 ~ "^[[:space:]]*# >>> " f "[[:space:]]*$" {inb=1}
        $0 ~ "^[[:space:]]*# <<< " f "[[:space:]]*$" {inb=0; next}
        !inb' "$f")"
    # A `timeout` reached outside the fence is a second, unbounded ceiling.
    if printf '%s' "$body" | grep -qE '(^|[^[:alnum:]_-])timeout[[:space:]]+[0-9"$]'; then
        bad "$rel: bounds no probe outside the fence" "it spells its own \`timeout\`"; STRAY=1
    fi
    # A private definition drifts from the one block; the fence is where it lives.
    if printf '%s' "$body" | grep -qE '^[[:space:]]*(run_bounded|run_piped|budget_[a-z]+)[[:space:]]*\(\)'; then
        bad "$rel: defines no budget helper outside the fence" "it redefines one"; STRAY=1
    fi
    # And a caller with no fence calls a function nothing defines: `bash -n`
    # passes, and only the branch reaching the call ever reports it.
    if printf '%s' "$body" | grep -qE '(^|[^[:alnum:]_])run_(bounded|piped)([^[:alnum:]_(]|$)' \
       && [ -z "$(extract "$f")" ]; then
        bad "$rel: carries the block it probes with" "it calls run_bounded and has no fence"; STRAY=1
    fi
done < <(hosts)
[ "$STRAY" -eq 0 ] && ok "every bounded probe in doctor/ goes through the fenced block"

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
