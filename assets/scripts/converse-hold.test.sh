#!/usr/bin/env bash
# converse-hold.test.sh — the step-5 hold mechanism (assets/scripts/converse-hold.sh):
# the takeaway on the item, the demand gate, the gc.hold_demand stamp-and-readback
# gate, and the held lifecycle transition. The two gates fail CLOSED: unless the
# demand lands and the stamp reads back off the visit, the script exits non-zero
# and the caller must not post the framing. This suite drives the shipped script
# against stubs whose demand and stamp outcomes are dialed independently, and
# carries a positive control proving the read-back closes a real regression
# rather than pinning a line the old shape already caught.
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
# the visit with its stall_root and whatever the stamp has persisted; `bd update`
# persists the stamped id unless STAMP_PERSIST=0, overridable by STAMP_VALUE for
# the landed-wrong case, and exits STAMP_RC. Anything else exits 2 so a script
# that grows a third call fails here rather than reaching the live store.
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 2
case "${2:-}" in
    show)
        hd=""; [ -r "$PERSIST" ] && hd="$(cat "$PERSIST")"
        jq -nc --arg sr "${STUB_STALL-item-x}" --arg hd "$hd" \
            '[{id:"v-x", metadata:(({"task_kind":"visit"}
                + (if $sr == "" then {} else {"stall_root":$sr} end)
                + (if $hd == "" then {} else {"gc.hold_demand":$hd} end)))}]' ;;
    update)
        if [ "${STAMP_PERSIST:-1}" = "1" ]; then
            v="${STAMP_VALUE:-}"
            if [ -z "$v" ]; then
                for a in "$@"; do case "$a" in gc.hold_demand=*) v="${a#gc.hold_demand=}" ;; esac; done
            fi
            printf '%s' "$v" >"$PERSIST"
        fi
        exit "${STAMP_RC:-0}" ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"

# stub_helm <root> — a gc-helm.sh under <root> that logs each call (with the
# root, so resolution is observable) and dials its verbs from the environment:
#   takeaway -> exit $STUB_TAKEAWAY_RC (default 0)
#   demand   -> print $STUB_DEMAND_OUT if set, else "demand $STUB_DEMAND_ID filed"
#               (default id d-x); exit $STUB_DEMAND_RC (default 0)
stub_helm() {
    cat >"$1/assets/scripts/gc-helm.sh" <<HELM
#!/usr/bin/env bash
printf 'helm[$2] %s\n' "\$*" >>"\$HLOG"
case "\${1:-}" in
    takeaway) exit "\${STUB_TAKEAWAY_RC:-0}" ;;
    demand)
        if [ -n "\${STUB_DEMAND_OUT+x}" ]; then printf '%s\n' "\$STUB_DEMAND_OUT"
        else printf 'demand %s filed\n' "\${STUB_DEMAND_ID:-d-x}"; fi
        exit "\${STUB_DEMAND_RC:-0}" ;;
    *) exit 2 ;;
esac
HELM
    chmod +x "$1/assets/scripts/gc-helm.sh"
}
# a lifecycle.sh under PACK: state -> $STUB_STATE (default unanchored), transition
# logs and exits $STUB_LC_RC (default 0).
cat >"$PACK/assets/scripts/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
case "${1:-}" in
    state)      printf '%s\n' "${STUB_STATE:-unanchored}" ;;
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
        VISIT=v-x SUBJECT=sub "$@" bash "$SUT" "need X" 2>&1)"
    RC=$?
}
calls() { cat "$HLOG" 2>/dev/null; }
verdict() { [ "$RC" = 0 ] && echo held || echo refused; }

echo "── the happy path: demand lands, stamp persists, the hold proceeds ──"
run
is "a landed demand and a persisted stamp let the hold proceed" "$(verdict)" "held"
has "the takeaway headline is 'holding — <need>' on the item" "helm[RIG] takeaway item-x holding — need X --by converse" "$(calls)"
has "the demand is filed on the item with the bare need text" "helm[RIG] demand item-x need X --by converse" "$(calls)"
is "the stamp persisted the demand id on the visit" "$(cat "$PERSIST" 2>/dev/null)" "d-x"
has "an unanchored item is transitioned to held, routed to a person" "lc transition item-x --to held --route human" "$(calls)"

echo "── the item is the visit's stall_root, and falls back to the subject ──"
run STUB_STALL=item-y
has "a named stall_root is the item the hold writes to" "takeaway item-y holding" "$(calls)"
run STUB_STALL=
has "an absent stall_root falls back to the subject" "takeaway sub holding" "$(calls)"

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

echo "── the lifecycle transition is conditioned on the item being unanchored ──"
run STUB_STATE=unanchored
has "an unanchored item is transitioned to held" "lc transition item-x --to held" "$(calls)"
run STUB_STATE=held
hasnt "an item already anchored is not transitioned again" "lc transition" "$(calls)"

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
