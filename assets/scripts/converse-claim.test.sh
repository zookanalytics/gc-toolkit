#!/usr/bin/env bash
# converse-claim.test.sh — the claim verdict and, at its centre, the hold
# premise-gate diagnostic (assets/scripts/converse-claim.sh). On an
# existing_assignment claim carrying no gc.outcome the script must tell a
# sitting that reached its hold (BEGAN=yes/recheck) from a claim that died
# before step 2 ever re-checked the premise (BEGAN=no), because the caller
# closes the latter as a dead pre-step-2 claim.
#
# The regression this suite pins: a demand is filed by gc-helm as a NATIVE
# human gate (issue_type=gate), which `bd list` hides unless --include-gates.
# A visit with no gc.hold_demand whose item still carries such a gate-demand is
# a live wait (RECHECK); reading the demand list without --include-gates makes
# the gate invisible and misjudges it NO. The stub below hides gate rows unless
# --include-gates is present, so the shipped reader must pass the flag to see
# the demand, and a byte-faithful copy of the pre-fix flagless reader is carried
# as a positive control that misjudges the same fixture as NO.
#
# Hermetic: stubs `gc` (hook + bd show/list/close), reads nothing else; no city,
# no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/converse-claim.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "missing '$2' in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "found '$2' in: $3" ;; *) ok "$1" ;; esac; }

[ -r "$SUT" ] || { printf 'converse-claim: cannot read %s\n' "$SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'converse-claim: jq is required\n' >&2; exit 1; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-claim-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; BARE="$TMPD/bare"
mkdir -p "$BIN" "$BARE"

echo "── the script is shipped executable and syntactically valid ──"
[ -x "$SUT" ] && ok "converse-claim.sh is executable" \
    || bad "converse-claim.sh is executable" "chmod +x it"
bash -n "$SUT" && ok "converse-claim.sh: valid bash" \
    || bad "converse-claim.sh: valid bash" "bash -n failed"

# A stub gc dialed entirely from the environment:
#   hook  --claim --json -> a claim for v-x; CLAIM_MODE=nowork drops bead_id,
#         CLAIM_REASON/CLAIM_GROUP set the reason and continuation group.
#   bd show <id> --json  -> the visit v-x with STALL_ROOT (default item-x),
#         optional gc.hold_demand (HOLD_DEMAND) and gc.outcome (OUTCOME) and
#         status (SHOW_STATUS); SHOW_MODE=unreadable returns [] for the
#         cannot-read-the-visit arm.
#   bd list ... --json   -> a gate-demand on DEMAND_ITEM (default item-x), but
#         ONLY when --include-gates is present; a flagless list returns []. An
#         empty DEMAND_ITEM means no demand exists on any read.
#   bd close <id>        -> exits CLOSE_RC (default 0).
# Any other call exits 2, so a script that grows one fails here, not live.
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    hook)
        if [ "${CLAIM_MODE-}" = nowork ]; then printf '{}\n'; exit 0; fi
        jq -nc --arg r "${CLAIM_REASON-existing_assignment}" --arg g "${CLAIM_GROUP-g}" \
            '{bead_id:"v-x", reason:$r, continuation_group:$g, continuation_assigned:[]}'
        exit 0 ;;
    bd)
        case "${2:-}" in
            show)
                if [ "${SHOW_MODE-}" = unreadable ]; then printf '[]\n'; exit 0; fi
                jq -nc --arg sr "${STALL_ROOT-item-x}" --arg hd "${HOLD_DEMAND-}" \
                       --arg oc "${OUTCOME-}" --arg st "${SHOW_STATUS-}" \
                    '{id:"v-x",
                      status:(if $st == "" then "open" else $st end),
                      metadata:({"task_kind":"visit"}
                        + (if $sr == "" then {} else {stall_root:$sr} end)
                        + (if $hd == "" then {} else {"gc.hold_demand":$hd} end)
                        + (if $oc == "" then {} else {"gc.outcome":$oc} end))}
                      | [.]'
                exit 0 ;;
            list)
                want=0; for a in "$@"; do [ "$a" = "--include-gates" ] && want=1; done
                di="${DEMAND_ITEM-item-x}"
                if [ -n "$di" ] && [ "$want" = 1 ]; then
                    jq -nc --arg i "$di" '[{id:"d-x", metadata:{"gc.demand_for":$i}}]'
                else
                    printf '[]\n'
                fi
                exit 0 ;;
            close) exit "${CLOSE_RC:-0}" ;;
            *) exit 2 ;;
        esac ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"

# run [VAR=val ...] — converse-claim.sh from a non-git cwd with the stub gc on
# PATH; captures stdout+stderr (the verdict is stdout, the BEGAN diagnostic is
# stderr) and the exit status. Trailing VAR=val pairs dial the stub inline.
OUT=""; RC=0
run() {
    OUT="$(cd "$BARE" && env PATH="$BIN:$PATH" GIT_CEILING_DIRECTORIES="$TMPD" "$@" bash "$SUT" 2>&1)"
    RC=$?
}
began() { printf '%s\n' "$OUT" | grep -m1 '^premise-gate: BEGAN=' | sed 's/^premise-gate: BEGAN=//'; }

echo "── REGRESSION: a gate-only demand on the item is a live wait, not a dead claim ──"
run
is   "a gate-demand hidden from a flagless list still reads BEGAN=recheck" "$(began)" "recheck"
has  "the hold verdict is unchanged on stdout" "action=hold bead=v-x group=g reason=already-underway" "$OUT"
is   "…and the hold exit code is 3" "$RC" "3"

# Why the flag is load-bearing, shown against the very stub the script drives.
seen() { ( cd "$BARE" && env PATH="$BIN:$PATH" DEMAND_ITEM=item-x bash -c "gc bd list --status=open,in_progress $1 --json --limit=0" ); }
is   "the fixture hides the gate-demand from a flagless bd list" "$(seen '' | jq -c .)" "[]"
has  "…and reveals it only with --include-gates" "d-x" "$(seen --include-gates)"

echo "── positive control: the pre-fix flagless reader misjudges the same fixture ──"
# A byte-faithful copy of the pre-fix BEGAN arms: bd list WITHOUT --include-gates.
# That it reads NO where the shipped reader now reads RECHECK proves the flag
# closes a real regression rather than pinning a case the old shape caught.
cat >"$TMPD/oldread" <<'OLD'
#!/usr/bin/env bash
HD_LIST=$(gc bd list --status=open,in_progress --json --limit=0 2>/dev/null)
if printf '%s' "$HD_LIST" | jq -e --arg i "$1" 'type == "array" and any(.[]?; (.metadata["gc.demand_for"] // "") == $i)' >/dev/null 2>&1; then
    echo recheck
elif printf '%s' "$HD_LIST" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo no
else
    echo recheck
fi
OLD
chmod +x "$TMPD/oldread"
oldbegan() { ( cd "$BARE" && env PATH="$BIN:$PATH" DEMAND_ITEM=item-x bash "$TMPD/oldread" item-x ); }
is   "the pre-fix flagless reader reads the live gate-demand as NO" "$(oldbegan)" "no"

echo "── the rest of the BEGAN state machine ──"
run HOLD_DEMAND=d-x
is   "a visit already carrying gc.hold_demand is BEGAN=yes" "$(began)" "yes"
run SHOW_MODE=unreadable
is   "a visit bead that will not read is BEGAN=unknown (never licenses a close)" "$(began)" "unknown"
run DEMAND_ITEM=
is   "no open demand on the item at all is BEGAN=no" "$(began)" "no"
run STALL_ROOT= DEMAND_ITEM=g
is   "with no stall_root the item falls back to the group, and its gate still rechecks" "$(began)" "recheck"

echo "── the other top-level verdicts still hold ──"
run CLAIM_MODE=nowork
has  "an empty claim drains as no-work" "action=drain reason=no-work" "$OUT"
is   "…exit 1" "$RC" "1"
run CLAIM_REASON=claimed
has  "a fresh claim with no group filter is WORK" "action=work bead=v-x group=g" "$OUT"
is   "…exit 0" "$RC" "0"
run OUTCOME=settled SHOW_STATUS=closed
has  "an existing_assignment visit carrying gc.outcome FINISHes" "action=finish bead=v-x group=g reason=outcome-stamped" "$OUT"
is   "…exit 4" "$RC" "4"

echo
echo "converse-claim: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
