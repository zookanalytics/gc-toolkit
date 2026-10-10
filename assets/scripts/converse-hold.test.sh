#!/usr/bin/env bash
# converse-hold.test.sh — the step-5 hold mechanism (assets/scripts/converse-hold.sh):
# the takeaway on the GATED bead (visit for a PR anchor, subject otherwise, so the
# hold marker sits beside its edge), the demand gate, the gc.hold_demand
# stamp-and-readback gate, the --hold-merge opt-in (a second demand on the anchor,
# failing closed), and the held lifecycle transition. The gates fail CLOSED:
# unless the demand lands and the stamp reads back off the visit, the script exits
# non-zero and the caller must not post the framing. This suite drives the shipped
# script against stubs whose demand, stamp, gate-visit and merge-demand outcomes
# are dialed independently, and carries a positive control proving the read-back
# closes a real regression rather than pinning a line the old shape already caught.
#
# Hermetic: stubs gc, gc-helm.sh and lifecycle.sh, reads the repo only; no city,
# no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/converse-hold.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "missing '$2' in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "found '$2' in: $3" ;; *) ok "$1" ;; esac; }

[ -r "$SUT" ] || { printf 'converse-hold: cannot read %s\n' "$SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'converse-hold: jq is required\n' >&2; exit 1; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-hold-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; PACK="$TMPD/pack"; FOREIGN="$TMPD/foreign"; CITY="$TMPD/city"; BARE="$TMPD/bare"
mkdir -p "$BIN" "$PACK/assets/scripts" "$FOREIGN" "$CITY/rigs/gc-toolkit/assets/scripts" "$BARE"
PERSIST="$TMPD/persist"   # what `gc bd update` has stamped for gc.hold_demand
HLOG="$TMPD/hlog"         # every gc-helm.sh / lifecycle.sh invocation, in order

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SUT" ] && ok "converse-hold.sh is executable" \
    || bad "converse-hold.sh is executable" "chmod +x it"
bash -n "$SUT" && ok "converse-hold.sh: valid bash" \
    || bad "converse-hold.sh: valid bash" "bash -n failed"

# A stub gc serving the two reads/one write the script makes: `bd show` returns
# the visit with whatever the stamp has persisted; `bd update`
# persists the stamped id unless STAMP_PERSIST=0, overridable by STAMP_VALUE for
# the landed-wrong case, and exits STAMP_RC. Anything else exits 2 so a script
# that grows a third call fails here rather than reaching the live store.
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 2
case "${2:-}" in
    show)
        hd=""; [ -r "$PERSIST" ] && hd="$(cat "$PERSIST")"
        jq -nc --arg hd "$hd" --arg tp "${STUB_TOPIC:-}" \
            --arg tr "${STUB_TRACKS:-}" --arg cg "${STUB_GROUP:-}" \
            '[{id:"v-x", metadata:(({"task_kind":"visit"}
                + (if $hd == "" then {} else {"gc.hold_demand":$hd} end)
                + (if $tp == "" then {} else {"escalation_key":$tp} end)
                + (if $cg == "" then {} else {"gc.continuation_group":$cg} end)))}
              + (if $tr == "" then {} else {dependencies:[{id:$tr, dependency_type:"tracks"}]} end)]' ;;
    update)
        [ -n "${HLOG:-}" ] && printf 'gc %s\n' "$*" >>"$HLOG"
        # The gc.hold_demand write on the visit is the stamp gate under test; the
        # gc.gate_visit write on the demand (an anchored-subject hold) is best-effort,
        # dialed by GATE_VISIT_RC so the refused-stamp path can be exercised.
        case "$*" in
            *gc.hold_demand=*)
                if [ "${STAMP_PERSIST:-1}" = "1" ]; then
                    v="${STAMP_VALUE:-}"
                    if [ -z "$v" ]; then
                        for a in "$@"; do case "$a" in gc.hold_demand=*) v="${a#gc.hold_demand=}" ;; esac; done
                    fi
                    printf '%s' "$v" >"$PERSIST"
                fi
                exit "${STAMP_RC:-0}" ;;
            *gc.gate_visit=*) exit "${GATE_VISIT_RC:-0}" ;;
            *) exit 0 ;;
        esac ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"

# stub_helm <root> — a gc-helm.sh under <root> that logs each call (with the
# root, so resolution is observable) and dials its verbs from the environment:
#   takeaway -> exit $STUB_TAKEAWAY_RC (default 0)
#   demand   -> print $STUB_DEMAND_OUT if set, else "demand $STUB_DEMAND_ID filed"
#               (default id d-x); exit $STUB_DEMAND_RC (default 0). A demand on a
#               bead OTHER than the visit v-x — the --hold-merge second demand on
#               the anchor — exits $STUB_MERGE_DEMAND_RC instead when that is set,
#               so the merge-hold arm can be failed without failing the first.
stub_helm() {
    cat >"$1/assets/scripts/gc-helm.sh" <<HELM
#!/usr/bin/env bash
printf 'helm[$2] %s\n' "\$*" >>"\$HLOG"
case "\${1:-}" in
    takeaway) exit "\${STUB_TAKEAWAY_RC:-0}" ;;
    demand)
        if [ -n "\${STUB_DEMAND_OUT+x}" ]; then printf '%s\n' "\$STUB_DEMAND_OUT"
        else printf 'demand %s filed\n' "\${STUB_DEMAND_ID:-d-x}"; fi
        if [ -n "\${STUB_MERGE_DEMAND_RC:-}" ] && [ "\$2" != "v-x" ]; then exit "\$STUB_MERGE_DEMAND_RC"; fi
        exit "\${STUB_DEMAND_RC:-0}" ;;
    *) exit 2 ;;
esac
HELM
    chmod +x "$1/assets/scripts/gc-helm.sh"
}
# a lifecycle.sh under PACK: state -> $STUB_STATE (default unanchored), transition
# logs and exits $STUB_LC_RC (default 0). STUB_STATE_RC models the real `state`'s
# failure shape — an unreadable or undeclared subject prints NOTHING and exits
# non-zero — so the suite can prove the gate fails closed when the read fails.
cat >"$PACK/assets/scripts/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
case "${1:-}" in
    state)
        if [ "${STUB_STATE_RC:-0}" != "0" ]; then exit "$STUB_STATE_RC"; fi
        printf '%s\n' "${STUB_STATE:-unanchored}" ;;
    transition) printf 'lc %s\n' "$*" >>"$HLOG"; exit "${STUB_LC_RC:-0}" ;;
    *) exit 2 ;;
esac
LC
chmod +x "$PACK/assets/scripts/lifecycle.sh"
stub_helm "$PACK" RIG
stub_helm "$CITY/rigs/gc-toolkit" CITY

# run [VAR=val ...] — run converse-hold.sh "need X" from a non-git cwd with the
# owning-rig pack on GC_RIG_ROOT, resetting the persist file and call log first.
# Trailing VAR=val pairs override any default (env: last assignment wins), so a
# case dials STAMP_RC/STAMP_PERSIST/STUB_DEMAND_RC/GC_RIG_ROOT/… inline.
OUT=""; RC=0
run() {
    rm -f "$PERSIST" "$HLOG"; : >"$HLOG"
    OUT="$(cd "$BARE" && env PATH="$BIN:$PATH" \
        GC_RIG_ROOT="$PACK" GC_CITY_PATH="$CITY" \
        GIT_CEILING_DIRECTORIES="$TMPD" PERSIST="$PERSIST" HLOG="$HLOG" \
        VISIT=v-x SUBJECT=item-x "$@" bash "$SUT" "need X" 2>&1)"
    RC=$?
}
# Like run, but passes the --hold-merge opt-in flag to the script.
run_hold_merge() {
    rm -f "$PERSIST" "$HLOG"; : >"$HLOG"
    OUT="$(cd "$BARE" && env PATH="$BIN:$PATH" \
        GC_RIG_ROOT="$PACK" GC_CITY_PATH="$CITY" \
        GIT_CEILING_DIRECTORIES="$TMPD" PERSIST="$PERSIST" HLOG="$HLOG" \
        VISIT=v-x SUBJECT=item-x "$@" bash "$SUT" --hold-merge "need X" 2>&1)"
    RC=$?
}
calls() { cat "$HLOG" 2>/dev/null; }
verdict() { [ "$RC" = 0 ] && echo held || echo refused; }

echo "── the happy path: demand lands, stamp persists, the hold proceeds ──"
run
is "a landed demand and a persisted stamp let the hold proceed" "$(verdict)" "held"
has "the takeaway headline is 'holding — <need>' on the subject" "helm[RIG] takeaway item-x holding — need X --by converse" "$(calls)"
has "the demand is filed on the subject with the bare need text" "helm[RIG] demand item-x need X --by converse" "$(calls)"
is "the stamp persisted the demand id on the visit" "$(cat "$PERSIST" 2>/dev/null)" "d-x"
has "an unanchored subject is transitioned to held, routed to a person" "lc transition item-x --to held --route human" "$(calls)"

echo "── the hold writes to the subject it is handed ──"
run SUBJECT=item-y
has "the hold writes to the subject it is handed" "takeaway item-y holding" "$(calls)"
hasnt "…and to no other bead" "takeaway item-x" "$(calls)"

echo "── the demand gate fails closed unless a demand id lands ──"
run STUB_DEMAND_RC=4
is "a demand that exits non-zero refuses the hold" "$(verdict)" "refused"
has "…and says why" "NO DEMAND FILED" "$OUT"
run STUB_DEMAND_RC=4 STUB_DEMAND_ID=d-x
is "a non-zero demand that still printed an id refuses (the exit is the signal)" "$(verdict)" "refused"
run STUB_DEMAND_OUT="oops no id here"
is "a zero-exit demand whose output names no id refuses" "$(verdict)" "refused"
run STUB_DEMAND_OUT="" STUB_DEMAND_RC=0
is "a zero-exit demand with empty output refuses" "$(verdict)" "refused"
# The gate fires before the stamp: a refused demand leaves nothing stamped.
run STUB_DEMAND_RC=4
is "a refused demand never reaches the stamp" "$(cat "$PERSIST" 2>/dev/null || echo '<none>')" "<none>"
hasnt "…and never reaches the lifecycle transition" "lc transition" "$(calls)"

echo "── the stamp gate fails closed unless the trace reads back off the visit ──"
run STAMP_PERSIST=1
is "a stamp that persists lets the hold proceed" "$(verdict)" "held"
run STAMP_RC=1 STAMP_PERSIST=0
is "a refused update that left no trace refuses the framing" "$(verdict)" "refused"
has "…and says the trace did not persist" "DID NOT PERSIST" "$OUT"
run STAMP_RC=0 STAMP_PERSIST=0
is "an update that reports success but does not persist still refuses" "$(verdict)" "refused"
run STAMP_VALUE=d-other
is "a stamp that landed the WRONG id refuses the framing" "$(verdict)" "refused"

echo "── positive control: the pre-fix update-or-echo framed on a phantom stamp ──"
# The shipped step 5 once wrote `gc bd update ... || echo` with no read-back, so
# a success-with-no-persist update satisfied it and the sitting framed with no
# trace. That the OLD shape HOLDS where the gate now REFUSES proves the read-back
# closes a real regression rather than pinning a case the old line caught.
legacy() {
    rm -f "$PERSIST"
    ( cd "$BARE" && env PATH="$BIN:$PATH" PERSIST="$PERSIST" \
        STAMP_RC="$1" STAMP_PERSIST="$2" VISIT=v-x DEMAND=d-x \
        bash -c 'gc bd update "$VISIT" --set-metadata "gc.hold_demand=$DEMAND" || echo stamp-failed' >/dev/null 2>&1 )
    [ "$?" = 0 ] && echo held || echo refused
}
is "the pre-fix update-or-echo framed on a success-no-persist stamp" "$(legacy 0 0)" "held"

# Step 1 passes SUBJECT, and the visit records it twice, as its tracks edge and
# as its gc.continuation_group stamp, so an empty SUBJECT is recovered from the
# visit the way converse-fold.sh recovers it. With neither, the takeaway and the
# demand would address an empty bead id, so the hold refuses before any write.
echo "── an empty SUBJECT is recovered from the visit, and refused when the visit names none ──"
run SUBJECT= STUB_TRACKS=item-t
is "a hold with no SUBJECT proceeds when the visit tracks its subject" "$(verdict)" "held"
has "…and the demand gates the tracked subject" "helm[RIG] demand item-t need X --by converse" "$(calls)"
run SUBJECT= STUB_GROUP=item-g
has "with no tracks edge, the gc.continuation_group stamp names the subject" \
    "helm[RIG] demand item-g need X --by converse" "$(calls)"
run SUBJECT=
is "a visit that names no subject is refused (exit 2)" "$RC" "2"
has "…and the refusal says why" "no subject" "$OUT"
hasnt "…before any takeaway or demand is written" "helm[" "$(calls)"

echo "── the lifecycle transition is conditioned on the subject being unanchored ──"
run STUB_STATE=unanchored
has "an unanchored subject is transitioned to held" "lc transition item-x --to held" "$(calls)"
run STUB_STATE=held
hasnt "a non-unanchored state is not transitioned to held" "lc transition" "$(calls)"
has "a pre-PR off-ramp (held) is not a PR anchor, so it fails closed to the SUBJECT" "demand item-x" "$(calls)"
hasnt "…so the demand never gates the visit" "demand v-x" "$(calls)"

echo "── an anchored subject: the conversation demand gates the VISIT, not the subject ──"
# A conversation about a PR anchor must not freeze the merge (operator ruling):
# its wait gates the visit, and the subject anchor keeps moving. Only a pre-PR
# (unanchored) subject takes the demand itself, which the default case above proves.
run STUB_STATE=pull_request
is "an anchored subject still lets the hold proceed" "$(verdict)" "held"
has "the demand is filed on the VISIT, so the anchor is never blocked" "helm[RIG] demand v-x need X --by converse" "$(calls)"
hasnt "…and NOT on the subject, so the merge is not frozen" "demand item-x" "$(calls)"
has "the visit is recorded as the gate's own visit, so gate-visit-sweep files no second one" "gc bd update d-x --set-metadata gc.gate_visit=v-x" "$(calls)"
hasnt "…and an anchored subject is not transitioned to held" "lc transition" "$(calls)"
is "the hold_demand stamp still lands on the visit" "$(cat "$PERSIST" 2>/dev/null)" "d-x"
has "the takeaway headline lands on the VISIT (the gated bead), beside its edge" "helm[RIG] takeaway v-x holding — need X --by converse" "$(calls)"
hasnt "…and NOT on the anchor, which would be an unedged hold the board reads as holding" "takeaway item-x" "$(calls)"
# The gate_visit stamp is best-effort: a hold whose demand landed still proceeds
# even when that hygiene write is REFUSED. GATE_VISIT_RC dials the refusal; the
# default 0 never exercises the `|| echo` fallback (gate-visit-sweep's self-cover
# backstops the lost stamp).
run STUB_STATE=pull_request GATE_VISIT_RC=1
is "an anchored hold proceeds even when the gate_visit stamp is refused" "$(verdict)" "held"
has "…and says the gate_visit stamp could not be written" "could not stamp gc.gate_visit=v-x on d-x" "$OUT"
# The whole PR-anchor set gates the visit, not just pull_request: a pre-open-gate
# anchor has a live merge to protect, and a merged anchor is a closed bead a
# demand cannot land on.
run STUB_STATE=pre_open_gate
has "a pre-open-gate anchor gates the visit" "demand v-x" "$(calls)"
hasnt "…never the subject" "demand item-x" "$(calls)"
run STUB_STATE=merged
has "a merged (closed) anchor gates the visit" "demand v-x" "$(calls)"
hasnt "…never a demand on the closed subject" "demand item-x" "$(calls)"

echo "── --hold-merge: the opt-in files a second demand on the anchor ──"
# The conversation demand gates the visit; --hold-merge adds the merge hold — a
# second demand on the SUBJECT, the blocks edge the merge sweep honors.
run_hold_merge STUB_STATE=pull_request
is "an anchored hold with --hold-merge proceeds" "$(verdict)" "held"
has "the conversation demand still gates the visit" "helm[RIG] demand v-x need X --by converse" "$(calls)"
has "…and a second demand freezes the merge on the anchor" "helm[RIG] demand item-x need X --by converse" "$(calls)"
# Fails closed like the conversation demand: a requested merge hold that does not
# land must not be framed as held.
run_hold_merge STUB_STATE=pull_request STUB_MERGE_DEMAND_RC=4
is "a merge-hold demand that fails refuses the framing" "$(verdict)" "refused"
has "…and says the merge is NOT held" "NO MERGE-HOLD DEMAND FILED on item-x" "$OUT"
# A no-op on an unanchored subject: its single demand already gates it (GATED=subject),
# so the flag files no redundant second one.
run_hold_merge STUB_STATE=unanchored
is "--hold-merge on an unanchored subject still proceeds" "$(verdict)" "held"
is "…and files exactly one demand (no redundant merge hold)" "$(calls | grep -c 'demand item-x')" "1"
hasnt "…and never a visit demand on an unanchored subject" "demand v-x" "$(calls)"

echo "── the visit's escalation_key scopes every demand the sitting files ──"
# Under a standing scope sibling sittings share the subject. Each demand this sitting
# files carries the visit's escalation_key as its topic, so neither sitting's
# demand on the shared subject refreshes the other's gate in place.
run STUB_TOPIC=finding-b
has "a pre-PR subject's conversation demand carries the topic" "helm[RIG] demand item-x need X --by converse --topic finding-b" "$(calls)"
run_hold_merge STUB_STATE=pull_request STUB_TOPIC=finding-b
has "an anchored hold's visit demand carries the topic" "helm[RIG] demand v-x need X --by converse --topic finding-b" "$(calls)"
has "…and so does the --hold-merge demand on the shared anchor" "helm[RIG] demand item-x need X --by converse --topic finding-b" "$(calls)"
run_hold_merge STUB_STATE=pull_request
hasnt "an ordinary visit (no escalation_key) files no topic" "--topic" "$(calls)"

echo "── fail closed: an unreadable or missing lifecycle state gates the SUBJECT ──"
# The gate switches to the visit only for a PROVEN PR-anchor state. A state that
# cannot be read must fail closed to the subject — defaulting to the visit would drop
# a pre-PR subject's blocking edge and let it keep moving while a person owes an
# answer (the regression this rework closes).
run STUB_STATE_RC=2
is "a failed state read still lets the hold proceed" "$(verdict)" "held"
has "…with the demand on the SUBJECT (fail closed)" "demand item-x" "$(calls)"
hasnt "…and never on the visit" "demand v-x" "$(calls)"
hasnt "…and no held transition on an unprovable state" "lc transition" "$(calls)"
run GC_RIG_ROOT="$FOREIGN"
has "a missing lifecycle writer still finds the demand writer" "helm[CITY]" "$(calls)"
has "…and with no state readable, the demand fails closed to the SUBJECT" "helm[CITY] demand item-x need X --by converse" "$(calls)"
hasnt "…never the visit" "demand v-x" "$(calls)"

echo "── the writers are searched for on the candidate roots, not assumed ──"
run
has "the owning rig's gc-helm.sh wins when present" "helm[RIG]" "$(calls)"
run GC_RIG_ROOT="$FOREIGN"
has "a rig with no assets/ falls through to the city pack" "helm[CITY]" "$(calls)"
run GC_RIG_ROOT="$FOREIGN" GC_CITY_PATH="$TMPD/no-such-city"
has "no writer on any candidate root is LOUD" "NO TAKEAWAY WRITER" "$OUT"
is "…and with no writer the hold cannot land, so it refuses" "$(verdict)" "refused"

echo
echo "converse-hold: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
