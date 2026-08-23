#!/usr/bin/env bash
# inflight-membership.test.sh — the drift test for the shared in-flight
# membership predicate (tk-vie5k, implementing the tk-j5wrs ruling).
#
# WHAT IS SHARED AND WHY. Four dispatchers can mint a `task_kind=review` bead and
# a fifth reader (salvage) decides whether a molecule is still coming for a bead.
# Each computed "what is already acting on this anchor" its own way, from a
# different edge convention, and every symptom under tk-j5wrs is a different wrong
# answer to that one question. The class has been fixed three times, each at one
# site, and returned through another (#387, #390, #395): partial convergence IS the
# failure mode, so the predicate is one marked block copied verbatim and this test
# is what makes a copy that drifts fail loudly instead of silently.
#
# There is no sourced-library pattern in this pack — every assets/scripts/*.sh is
# standalone and the readers span three media (shell, TOML formula body, markdown
# fragment) — so this mirrors the pack's existing answer to exactly that problem:
# formulas/mol-visit.toml + assets/scripts/gate-visit.test.sh (the gate-visit
# block), and assets/scripts/signoff-round-cap.test.sh, which additionally EXECUTES
# the extracted block rather than grepping its text.
#
# Covered:
#   (CANON)    the canonical copy exists, in check-set-heal.sh
#   (CENSUS)   every known host still carries a marked copy — a floor, so a copy
#              that goes missing fails here rather than drifting quietly
#   (DRIFT)    every copy is byte-identical to canonical, modulo the indentation a
#              TOML formula body legitimately adds
#   (VALID)    every copy is valid bash on its own
#   (CLAIM)    `claimable` — the routed/unclaimed half, asserted on the four shapes
#              that decide it, including the one salvage was blind to
#   (ACT)      `acting` — the whole predicate, including the review and
#              owning-status clauses `claimable` deliberately does not carry
#   (AUTH)     `anchor_authority` — anchor_bead is authoritative: mine / theirs /
#              unattributed, the ruling's decision 2 expressed as three answers
#   (NOROLL)   no reader hand-rolls the membership question outside a marked block
# Hermetic: reads the repo only; no gc, no city, no Dolt.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SDIR="$REPO/assets/scripts"
FDIR="$REPO/formulas"
TDIR="$REPO/template-fragments"
CANON_FILE="$SDIR/check-set-heal.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }

# Extract the marked block from one file, with the common leading indentation
# stripped. A TOML formula body indents its shell by two spaces and that is not
# drift; anything else inside the block is.
extract() {
    awk '/# >>> inflight-membership/{f=1} /# <<< inflight-membership/{print; f=0} f' "$1" \
      | sed 's/^  //'
}

echo "── (CANON) the canonical copy ──"
CANON="$(extract "$CANON_FILE")"
if [ -n "$CANON" ]; then
    ok "canonical block present in check-set-heal.sh"
else
    bad "canonical block present in check-set-heal.sh" "no marked block found — every assertion below would pass vacuously"
    echo; echo "inflight-membership: $PASS passed, $((FAIL + 1)) failed"; exit 1
fi

echo "── (CENSUS)/(DRIFT)/(VALID) every copy ──"
# The known hosts, by surface. A floor rather than an exact list: adding a reader
# is expected, losing one is the regression.
HOSTS="$SDIR/check-set-heal.sh $SDIR/recover-stranded-branches.sh $SDIR/reconcile-merged-prs.sh $FDIR/mol-refinery-patrol.toml"
COPIES=0
for f in $HOSTS; do
    name="$(basename "$f")"
    blk="$(extract "$f")"
    if [ -z "$blk" ]; then
        bad "(CENSUS) $name carries a marked copy" "no # >>> inflight-membership block — did it get unmarked or hand-rolled?"
        continue
    fi
    COPIES=$((COPIES + 1))
    ok "(CENSUS) $name carries a marked copy"
    if [ "$blk" = "$CANON" ]; then
        ok "(DRIFT) $name is byte-identical to canonical"
    else
        bad "(DRIFT) $name is byte-identical to canonical" \
            "$(diff <(printf '%s\n' "$CANON") <(printf '%s\n' "$blk") | head -12)"
    fi
    printf '%s\n' "$blk" > "$TMP/copy.sh"
    bash -n "$TMP/copy.sh" 2>/dev/null && ok "(VALID) $name copy is valid bash" \
        || bad "(VALID) $name copy is valid bash" "bash -n failed"
done
if [ "$COPIES" -ge 4 ]; then
    ok "(CENSUS) all four known readers carry the block ($COPIES found)"
else
    bad "(CENSUS) all four known readers carry the block" "expected >=4, found $COPIES"
fi

# --- behaviour, run against the extracted block ------------------------------
# Grepping the text would pass on a block that says the right words and computes
# the wrong answer, so the predicate is EXECUTED. Everything below runs the
# canonical copy the same way a reader does: source it, feed jq a bead.
printf '%s\n' "$CANON" > "$TMP/canon.sh"
# shellcheck disable=SC1091  # generated at test time
. "$TMP/canon.sh"

# ask <jq-filter> <bead-json> [anchor] -> the filter's answer as text
ask() {
    printf '%s' "$2" | jq -r --arg live "$INFLIGHT_LIVE_STATUSES" --arg a "${3:-anchor-1}" \
        "$INFLIGHT_MEMBERSHIP_JQ$1" 2>/dev/null
}

echo "── (CLAIM) the routed/unclaimed half ──"
eq "$(ask 'if claimable then "yes" else "no" end' '{"id":"b","status":"open","assignee":"","metadata":{"gc.routed_to":"rig/pool"}}')" \
   "yes" "(CLAIM) routed to a pool is claimable"
# The sling dispatch form: `gc sling` retires gc.routed_to and stamps the live
# route in gc.execution_routed_to, with claimability held by the input convoy.
eq "$(ask 'if claimable then "yes" else "no" end' '{"id":"b","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"rig/pool"}}')" \
   "yes" "(CLAIM) the sling dispatch form is claimable"
# ...but execution_routed_to is NOT retired on the way back, so the assignee is the
# only field separating a live convoy dispatch from a handed-back one (tk-79zn6).
eq "$(ask 'if claimable then "yes" else "no" end' '{"id":"b","status":"open","assignee":"rig/refinery","metadata":{"gc.execution_routed_to":"rig/pool"}}')" \
   "no" "(CLAIM) a handed-back child carrying a stale execution route is NOT claimable"
eq "$(ask 'if claimable then "yes" else "no" end' '{"id":"b","status":"in_progress","assignee":"","metadata":{}}')" \
   "no" "(CLAIM) an unrouted bead is not claimable however busy its status looks"
# THE ONE SALVAGE WAS BLIND TO. A molecule root that is routed and unclaimed is a
# pending pool offer, and salvage read it as a bead with no landing path.
eq "$(ask 'if claimable then "yes" else "no" end' '{"id":"root","status":"in_progress","assignee":"","metadata":{"gc.input_convoy_id":"cv","gc.routed_to":"rig/pool"}}')" \
   "yes" "(CLAIM) a routed, unclaimed molecule root is a pending offer"

echo "── (ACT) the whole predicate ──"
eq "$(ask 'if acting($live) then "yes" else "no" end' '{"id":"b","status":"open","assignee":"","metadata":{"task_kind":"review"}}')" \
   "yes" "(ACT) a review bead is acting whatever else it carries"
eq "$(ask 'if acting($live) then "yes" else "no" end' '{"id":"b","status":"in_progress","assignee":"","metadata":{}}')" \
   "yes" "(ACT) an owning status is acting"
eq "$(ask 'if acting($live) then "yes" else "no" end' '{"id":"b","status":"open","assignee":"","metadata":{}}')" \
   "no" "(ACT) plain open, unrouted, unclaimed is inert — the one status carrying no actor"
# `claimable` is a SUBSET of `acting`, never the reverse: salvage needs the narrow
# half precisely because a graph.v2 root is in_progress from the pour until somebody
# closes it, and nothing does — reading `acting` there calls every husk live.
eq "$(ask 'if (acting($live) and (claimable | not)) then "wider" else "same" end' '{"id":"b","status":"in_progress","assignee":"","metadata":{}}')" \
   "wider" "(ACT) acting is strictly wider than claimable (the husk shape)"

echo "── (AUTH) anchor_bead is authoritative ──"
eq "$(ask 'anchor_authority($a)' '{"id":"r","metadata":{"anchor_bead":"anchor-1"}}' 'anchor-1')" \
   "mine" "(AUTH) a bead naming THIS anchor is ours"
eq "$(ask 'anchor_authority($a)' '{"id":"r","metadata":{"anchor_bead":"anchor-2"}}' 'anchor-1')" \
   "theirs" "(AUTH) a bead naming ANOTHER anchor is positively not ours"
eq "$(ask 'anchor_authority($a)' '{"id":"r","metadata":{"task_kind":"review"}}' 'anchor-1')" \
   "unattributed" "(AUTH) a bead naming no anchor is left to the caller's heuristic"
# The projection reconcile-merged-prs.sh feeds it is not a whole bead; it keeps
# metadata.anchor_bead in its original shape precisely so this holds.
eq "$(ask 'anchor_authority($a)' '{"id":"r","mres":"","rhold":"","metadata":{"anchor_bead":"anchor-1"}}' 'anchor-1')" \
   "mine" "(AUTH) a probe-row projection answers the same as a whole bead"
eq "$(ask 'anchor_authority($a)' '{"id":"r"}' 'anchor-1')" \
   "unattributed" "(AUTH) a bead with no metadata at all is unattributed, never a match"

echo "── (NOROLL) the predicate is defined ONCE ──"
# The specific way this class came back three times: someone answers the question
# locally — correctly for their own site — and the next divergence is invisible
# until it costs a held merge. A second DEFINITION is that move, and it is what
# this arm refuses. Reading `anchor_bead` is not: a ledger query keyed on it, a
# readback that verifies the dispatch wrote it, and prose about it are all fine and
# all common. Only `def acting(` / `def claimable` / `def anchor_authority(` outside
# a marked block is a second implementation.
#
# Swept across the WHOLE pack, not just the known hosts: a fifth reader that
# hand-rolls the predicate is exactly what this is for, and it would carry no
# marker to be found by.
for f in "$SDIR"/*.sh "$FDIR"/*.toml "$TDIR"/*.md; do
    [ -f "$f" ] || continue
    case "$f" in *.test.sh) continue ;; esac   # tests quote the block; they do not ship it
    name="$(basename "$f")"
    outside="$(awk '/# >>> inflight-membership/{f=1} /# <<< inflight-membership/{f=0; next} !f' "$f" \
                 | grep -nE 'def (acting|claimable|anchor_authority)' || true)"
    [ -z "$outside" ] && continue
    bad "(NOROLL) $name defines the predicate outside the marked block" \
        "$(printf '%s' "$outside" | head -4)"
done
ok "(NOROLL) no second definition of acting/claimable/anchor_authority in the pack"

echo
echo "inflight-membership: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
