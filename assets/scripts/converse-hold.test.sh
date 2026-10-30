#!/usr/bin/env bash
# converse-hold.test.sh — the step-5 hold mechanism (assets/scripts/converse-hold.sh):
# the decision's length budget (the headline cap less the "holding — " prefix,
# checked before any write), the visit read gate (a visit that cannot be read
# stops the hold before any write), the takeaway on the GATED bead (visit for a
# PR anchor, subject otherwise, so the hold marker sits beside its edge) and its
# gate, the demand gate, the gc.hold_demand stamp-and-readback gate, the
# --hold-merge opt-in (a second demand on the anchor, failing closed), and the
# held lifecycle transition. The gates fail CLOSED: unless the visit is read,
# the headline and the demand land and the stamp reads back off the visit, the
# script exits non-zero and the caller must not post the framing. This suite
# drives the shipped script against stubs whose visit read, takeaway, demand,
# stamp, gate-visit and merge-demand outcomes are dialed independently. The
# stub writer enforces the shipped gc-helm.sh's cap, and the shipped writer's
# own length gate is run on the budget's boundary. A positive control proves the
# read-back closes a real regression rather than pinning a line the old shape
# already caught.
#
# Hermetic: stubs gc, gc-helm.sh and lifecycle.sh, and runs the shipped
# gc-helm.sh only against the stub gc; reads the repo only; no city, no network.

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
CAPLESS="$TMPD/capless"
mkdir -p "$BIN" "$PACK/assets/scripts" "$FOREIGN" "$CITY/rigs/gc-toolkit/assets/scripts" "$BARE" \
    "$CAPLESS/assets/scripts"
PERSIST="$TMPD/persist"   # what `gc bd update` has stamped for gc.hold_demand
HLOG="$TMPD/hlog"         # every gc-helm.sh / lifecycle.sh invocation, in order

# rep <text> <n> — <text> repeated <n> times.
rep() { local s="" i; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SUT" ] && ok "converse-hold.sh is executable" \
    || bad "converse-hold.sh is executable" "chmod +x it"
bash -n "$SUT" && ok "converse-hold.sh: valid bash" \
    || bad "converse-hold.sh: valid bash" "bash -n failed"

# The headline cap converse-hold.sh reads off its writer, read here off the
# shipped one. The decision's budget is that cap less the prefix the takeaway
# puts in front of it.
CAP="$(sed -n 's/^TAKEAWAY_MAX=\([0-9][0-9]*\).*/\1/p' "$REPO/assets/scripts/gc-helm.sh" | head -n 1)"
case "$CAP" in
    ''|*[!0-9]*)
        bad "gc-helm.sh declares the TAKEAWAY_MAX line converse-hold.sh reads its cap from" \
            "no TAKEAWAY_MAX=<n> line in $REPO/assets/scripts/gc-helm.sh"
        echo; echo "converse-hold: $PASS passed, $FAIL failed"; exit 1 ;;
    *) ok "gc-helm.sh declares the TAKEAWAY_MAX line converse-hold.sh reads its cap from" ;;
esac
PREFIX="holding — "
BUDGET=$((CAP - $(printf '%s' "$PREFIX" | jq -Rsr 'length')))

# A stub gc serving the two reads/one write the script makes: `bd show` returns
# the visit with whatever the stamp has persisted, plus the metadata object
# STUB_VISIT_META carries, or STUB_SHOW_OUT in its place when that is set
# (empty for no answer at all), and exits STUB_SHOW_RC. Its
# first STUB_SHOW_FAILS reads answer nothing and exit 1, a store that recovers
# between the hold's reads. `bd update` persists the stamped id unless
# STAMP_PERSIST=0, overridable by STAMP_VALUE for the landed-wrong case, and
# exits STAMP_RC. Anything else exits 2 so a script that grows a third call
# fails here rather than reaching the live store.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
[ "${1:-}" = "bd" ] || exit 2
case "${2:-}" in
    show)
        if [ "${STUB_SHOW_FAILS:-0}" -gt 0 ]; then
            n=0; [ -r "$PERSIST.reads" ] && n="$(cat "$PERSIST.reads")"
            printf '%s' "$((n + 1))" >"$PERSIST.reads"
            [ "$n" -lt "$STUB_SHOW_FAILS" ] && exit 1
        fi
        if [ -n "${STUB_SHOW_OUT+x}" ]; then
            printf '%s' "$STUB_SHOW_OUT"
        else
            hd=""; [ -r "$PERSIST" ] && hd="$(cat "$PERSIST")"
            vm="${STUB_VISIT_META:-}"; [ -n "$vm" ] || vm='{}'
            jq -nc --arg hd "$hd" --arg tp "${STUB_TOPIC:-}" --arg vt "${STUB_VISIT_TOPIC:-}" \
                --arg tr "${STUB_TRACKS:-}" --arg cg "${STUB_GROUP:-}" --argjson vm "$vm" \
                '[{id:"v-x", metadata:(({"task_kind":"visit"} + $vm
                    + (if $hd == "" then {} else {"gc.hold_demand":$hd} end)
                    + (if $tp == "" then {} else {"escalation_key":$tp} end)
                    + (if $vt == "" then {} else {"visit_topic":$vt} end)
                    + (if $cg == "" then {} else {"gc.continuation_group":$cg} end)))}
                  + (if $tr == "" then {} else {dependencies:[{id:$tr, dependency_type:"tracks"}]} end)]'
        fi
        exit "${STUB_SHOW_RC:-0}" ;;
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

# stub_helm <root> <label> [nocap] — a gc-helm.sh under <root> that logs each
# call (with <label>, so resolution is observable) and dials its verbs from the
# environment:
#   takeaway -> refuse a headline over the shipped writer's cap, measured the way
#               it measures (whitespace collapsed, codepoints), with its message
#               and exit 2; else exit $STUB_TAKEAWAY_RC (default 0)
#   demand   -> print $STUB_DEMAND_OUT if set, else "demand $STUB_DEMAND_ID filed"
#               (default id d-x); exit $STUB_DEMAND_RC (default 0). A demand on a
#               bead OTHER than the visit v-x — the --hold-merge second demand on
#               the anchor — exits $STUB_MERGE_DEMAND_RC instead when that is set,
#               so the merge-hold arm can be failed without failing the first.
# It declares TAKEAWAY_MAX the way the shipped writer does. `nocap` leaves that
# line out and still enforces the cap: a writer whose cap cannot be read.
stub_helm() {
    local cap_line="TAKEAWAY_MAX=$CAP"
    [ "${3:-}" = nocap ] && cap_line="# no cap declared"
    cat >"$1/assets/scripts/gc-helm.sh" <<HELM
#!/usr/bin/env bash
$cap_line
printf 'helm[$2] %s\n' "\$*" >>"\$HLOG"
case "\${1:-}" in
    takeaway)
        h=\$(printf '%s' "\${3:-}" | tr -s '[:space:]' ' '); h="\${h# }"; h="\${h% }"
        n=\$(printf '%s' "\$h" | jq -Rsr 'length')
        if [ "\$n" -gt $CAP ]; then
            echo "gc-helm: takeaway: text is \$n chars; the cap is $CAP" >&2; exit 2
        fi
        exit "\${STUB_TAKEAWAY_RC:-0}" ;;
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
stub_helm "$CAPLESS" CAPLESS nocap
# The script takes its writers from beside itself, in the copy of the pack that
# runs, so each pack here carries its own copy of the script and the libraries
# it sources. FOREIGN carries no writer at all.
for d in "$PACK" "$CITY/rigs/gc-toolkit" "$CAPLESS" "$FOREIGN"; do
    mkdir -p "$d/assets/scripts"
    cp "$SUT" "$REPO/assets/scripts/visit-identity.sh" "$REPO/assets/scripts/visit-topic.sh" "$d/assets/scripts/"
done

# run_need <need> [VAR=val ...] — run the copy of converse-hold.sh "<need>" in
# RUN_PACK (PACK by default) from a non-git cwd, resetting the persist file, the
# stub's read count and the call log first. Trailing VAR=val pairs override any
# default (env: last assignment wins), so a case dials STAMP_RC/STAMP_PERSIST/
# STUB_DEMAND_RC/… inline. run [VAR=val ...] is run_need "need X".
OUT=""; RC=0
run_need() {
    local need="$1"; shift
    rm -f "$PERSIST" "$PERSIST.reads" "$HLOG"; : >"$HLOG"
    OUT="$(cd "$BARE" && env PATH="$BIN:$PATH" \
        GC_RIG_ROOT="$PACK" GC_CITY_PATH="$CITY" \
        GIT_CEILING_DIRECTORIES="$TMPD" PERSIST="$PERSIST" HLOG="$HLOG" \
        VISIT=v-x SUBJECT=item-x "$@" bash "${RUN_PACK:-$PACK}/assets/scripts/converse-hold.sh" "$need" 2>&1)"
    RC=$?
}
run() { run_need "need X" "$@"; }
# Like run, but passes the --hold-merge opt-in flag to the script.
run_hold_merge() {
    rm -f "$PERSIST" "$PERSIST.reads" "$HLOG"; : >"$HLOG"
    OUT="$(cd "$BARE" && env PATH="$BIN:$PATH" \
        GC_RIG_ROOT="$PACK" GC_CITY_PATH="$CITY" \
        GIT_CEILING_DIRECTORIES="$TMPD" PERSIST="$PERSIST" HLOG="$HLOG" \
        VISIT=v-x SUBJECT=item-x "$@" bash "${RUN_PACK:-$PACK}/assets/scripts/converse-hold.sh" --hold-merge "need X" 2>&1)"
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

echo "── the decision gets the headline cap less the prefix, checked before any write ──"
# The writer refuses a takeaway over its cap, and the takeaway puts the prefix in
# front of the decision, so the decision gets the cap less the prefix. One over
# that is refused with its own budget before anything is read or written; the
# boundary is inclusive.
run_need "$(rep x "$BUDGET")"
is "a decision of exactly the budget holds" "$(verdict)" "held"
has "…and its headline reaches the writer whole" "takeaway item-x $PREFIX$(rep x "$BUDGET") --by converse" "$(calls)"
run_need "$(rep x $((BUDGET + 1)))"
is "a decision one over the budget is refused as usage (exit 2)" "$RC" "2"
has "…and the refusal names its length and its budget" "the decision is $((BUDGET + 1)) chars; keep it to $BUDGET" "$OUT"
is "…before any takeaway, demand or update is written" "$(calls)" ""
is "…so no hold_demand is stamped" "$(cat "$PERSIST" 2>/dev/null || echo '<none>')" "<none>"
run_need "$(rep x "$CAP")"
is "a decision as long as the whole cap is refused too" "$RC" "2"
is "…before any write" "$(calls)" ""
# Measured the way the writer measures it: codepoints, after the whitespace collapse.
run_need "$(rep é "$BUDGET")"
is "the budget counts codepoints, so a multi-byte decision of the budget holds" "$(verdict)" "held"
run_need "$(rep x $((BUDGET - 2)))   y"
is "the budget counts the collapsed text, so a run of spaces costs one" "$(verdict)" "held"
run_need "   "
is "a decision that is only whitespace is refused as usage" "$RC" "2"
is "…before any write" "$(calls)" ""

echo "── the visit read gate: a visit that cannot be read stops the hold before any write ──"
# Every demand carries the visit's topic, here its escalation_key. A failed read
# taken as an empty answer files the demand with no topic, and a topic-less
# demand matches whatever demand already sits on the gated bead, a sibling
# sitting's on a shared subject. So a read counts only when it exits 0 with the
# visit's own row, and anything else exits 1 having written nothing. The lead
# case fails one read and lets the store answer after it, so the stamp's
# read-back finds the stamp and nothing later in the hold refuses in its place.
run STUB_TOPIC=finding-b STUB_SHOW_FAILS=1
is "a visit read that fails refuses the hold (exit 1)" "$RC" "1"
has "…and says the visit could not be read" "VISIT UNREADABLE: v-x could not be read" "$OUT"
hasnt "…and files no demand, so none goes out without the topic" "demand item-x" "$(calls)"
hasnt "…and writes no holding headline" "takeaway" "$(calls)"
is "…and writes nothing at all" "$(calls)" ""
is "…so no hold_demand is stamped" "$(cat "$PERSIST" 2>/dev/null || echo '<none>')" "<none>"
run STUB_TOPIC=finding-b STUB_SHOW_RC=1 STUB_SHOW_OUT=
is "a store that does not answer at all refuses the hold too" "$RC" "1"
is "…before any write" "$(calls)" ""
run STUB_TOPIC=finding-b STUB_SHOW_RC=1
is "a read that exits non-zero refuses even when it printed the visit (the exit is the signal)" "$RC" "1"
is "…before any write" "$(calls)" ""
run STUB_SHOW_OUT="Error: search count issues: invalid connection"
is "a zero-exit read whose answer does not parse refuses" "$RC" "1"
is "…before any write" "$(calls)" ""
run STUB_SHOW_OUT="[]"
is "a zero-exit read that answers with no row refuses" "$RC" "1"
is "…before any write" "$(calls)" ""
run STUB_SHOW_OUT='[{"id":"v-other","metadata":{"escalation_key":"finding-a"}}]'
is "a read that answers with another bead's row refuses" "$RC" "1"
is "…before any write" "$(calls)" ""
run STUB_SHOW_RC=1 STUB_SHOW_OUT='{"error":"no issues found matching the provided IDs"}'
is "a visit the store says does not exist refuses the hold (exit 1)" "$RC" "1"
has "…and says it does not exist" "NO SUCH VISIT: v-x does not exist" "$OUT"
is "…before any write" "$(calls)" ""
run SUBJECT= STUB_SHOW_RC=1 STUB_SHOW_OUT=
is "with no SUBJECT, a visit that cannot be read refuses as unreadable (exit 1)" "$RC" "1"
hasnt "…not as a visit that names no subject" "no subject" "$OUT"
is "…before any write" "$(calls)" ""

echo "── the takeaway gate: a headline the writer refuses stops the hold ──"
# The headline is how the board shows the hold, and it is the first write, so a
# refused one stops the hold before the demand is filed.
run STUB_TAKEAWAY_RC=4
is "a takeaway the writer refuses refuses the hold (exit 1)" "$RC" "1"
has "…and says the board cannot show it" "NO HOLDING HEADLINE on item-x" "$OUT"
hasnt "…and files no demand" "demand item-x" "$(calls)"
is "…and stamps no hold_demand" "$(cat "$PERSIST" 2>/dev/null || echo '<none>')" "<none>"
hasnt "…and makes no held transition" "lc transition" "$(calls)"
run STUB_TAKEAWAY_RC=4 STUB_STATE=pull_request
is "an anchored hold whose headline is refused is refused too" "$RC" "1"
hasnt "…with no demand on the visit" "demand v-x" "$(calls)"
# A writer whose cap cannot be read leaves the length to it, and its refusal must
# still stop the hold.
RUN_PACK="$CAPLESS" run_need "$(rep x $((BUDGET + 1)))"
is "a writer whose cap cannot be read still stops an over-long hold" "$RC" "1"
has "…because the writer refused the headline" "the cap is $CAP" "$OUT"
hasnt "…and no demand is filed under it" "demand item-x" "$(calls)"
is "…and no hold_demand is stamped" "$(cat "$PERSIST" 2>/dev/null || echo '<none>')" "<none>"
RUN_PACK="$CAPLESS" run_need "$(rep x "$BUDGET")"
is "…while a decision within the budget holds through it" "$(verdict)" "held"

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

echo "── a visit filed for a distinct concern scopes its demands to itself ──"
# gc-helm.sh open --allow-duplicate (engage --reason, --template, a new visit
# picked at the prompt) files a second visit on a subject that may already have a
# live sitting, and stamps it visit_topic=own. The two sittings share the subject,
# so each demand this one files carries `visit:` and its own id as the topic, and
# its lookup never matches the live sitting's demand on the subject. The live
# sitting's lookup carries no topic and still matches this one's demand, so the
# protection runs one way.
run STUB_VISIT_TOPIC=own
has "a pre-PR subject's conversation demand carries the visit's own topic" "helm[RIG] demand item-x need X --by converse --topic visit:v-x" "$(calls)"
run_hold_merge STUB_STATE=pull_request STUB_VISIT_TOPIC=own
has "an anchored hold's visit demand carries it" "helm[RIG] demand v-x need X --by converse --topic visit:v-x" "$(calls)"
has "…and so does the --hold-merge demand on the shared anchor" "helm[RIG] demand item-x need X --by converse --topic visit:v-x" "$(calls)"
run STUB_VISIT_TOPIC=own STUB_TOPIC=finding-b
has "an escalation_key still names the topic when both are stamped" "helm[RIG] demand item-x need X --by converse --topic finding-b" "$(calls)"
run STUB_VISIT_TOPIC=other
hasnt "a visit_topic other than own is no topic of its own" "--topic" "$(calls)"

echo "── every case of the shared topic fixture files its demands under its demand topic ──"
# visit-topic.sh is the one definition of a visit's topic, and
# visit-topic.fixture.json holds the cases the fold, the hold and the sign-off
# each run. The stub serves the fixture's visit carrying each case's metadata.
# An anchored hold with --hold-merge files both demands a sitting can file, the
# conversation demand on the visit and the merge hold on the anchor, and each
# carries the case's demand topic, or none.
FX="$REPO/assets/scripts/visit-topic.fixture.json"
is "the fixture's visit is the one the stub serves" "$(jq -r '.visit' "$FX")" "v-x"
is "the fixture's subject is the one the hold is handed" "$(jq -r '.subject' "$FX")" "item-x"
while IFS= read -r c; do
    [ -n "$c" ] || continue
    name="$(printf '%s' "$c" | jq -r '.name')"
    want="$(printf '%s' "$c" | jq -r '.demand_topic')"
    run_hold_merge STUB_STATE=pull_request STUB_VISIT_META="$(printf '%s' "$c" | jq -c '.metadata')"
    is "(FIXTURE) $name: the hold proceeds" "$(verdict)" "held"
    if [ -n "$want" ]; then
        has "(FIXTURE) $name: the visit demand carries its demand topic" \
            "helm[RIG] demand v-x need X --by converse --topic $want" "$(calls)"
        has "(FIXTURE) $name: …and so does the merge hold" \
            "helm[RIG] demand item-x need X --by converse --topic $want" "$(calls)"
    else
        hasnt "(FIXTURE) $name: no demand carries a topic" "--topic" "$(calls)"
    fi
done <<< "$(jq -c '.cases[]' "$FX")"

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
RUN_PACK="$CITY/rigs/gc-toolkit" run
has "a missing lifecycle writer still finds the demand writer" "helm[CITY]" "$(calls)"
has "…and with no state readable, the demand fails closed to the SUBJECT" "helm[CITY] demand item-x need X --by converse" "$(calls)"
hasnt "…never the visit" "demand v-x" "$(calls)"

echo "── the writers are the ones beside the script, never a rig's or the city's ──"
run GC_RIG_ROOT="$FOREIGN"
has "the pack's own gc-helm.sh writes, whatever the rig root holds" "helm[RIG]" "$(calls)"
RUN_PACK="$FOREIGN" run GC_RIG_ROOT="$PACK"
has "a pack with no writer beside the script is LOUD" "NO TAKEAWAY WRITER" "$OUT"
is "…and with no writer the hold cannot land, so it refuses" "$(verdict)" "refused"
hasnt "…though the rig root and the city each hold one, neither is used" "helm[" "$(calls)"

echo "── the shipped writer's cap falls on the budget's boundary ──"
# The stub writers enforce the cap read off the shipped gc-helm.sh, so this holds
# the shipped writer to the same boundary: it refuses the headline a decision one
# over the budget composes and passes the one a budget decision composes. Its
# length gate runs before any store read, and the stub gc answers anything but
# `bd show`/`bd update` with exit 2, so neither run reaches a store.
real_takeaway() {
    (cd "$BARE" && { env PATH="$BIN:$PATH" TMPDIR="$TMPD" GC_CITY_PATH="$CITY" \
        sh "$REPO/assets/scripts/gc-helm.sh" takeaway item-x "$1" --by converse >/dev/null; } 2>&1)
}
has "the shipped writer refuses the headline of a decision one over the budget" \
    "the cap is $CAP" "$(real_takeaway "$PREFIX$(rep x $((BUDGET + 1)))")"
hasnt "…and its length gate passes the headline of a budget decision" \
    "the cap is" "$(real_takeaway "$PREFIX$(rep x "$BUDGET")")"

echo "── the documented budget is the writer's cap less the prefix ──"
# A sitting writes to the length its docs state, so every decision length the
# hold's docs state is the budget the writer enforces.
is "every decision length the converse-hold skill states is the budget" \
    "$(grep -o '≤[0-9]* char' "$REPO/skills/converse-hold/SKILL.md" | sort -u)" "≤$BUDGET char"
is "…and so is the one converse-hold.sh's header states" \
    "$(grep -o '≤[0-9]* char' "$SUT" | sort -u)" "≤$BUDGET char"

echo
echo "converse-hold: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
