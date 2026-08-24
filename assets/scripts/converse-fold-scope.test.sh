#!/usr/bin/env bash
# converse-fold-scope.test.sh — regression test for the converse role's
# fold-on-concurrent-hold check (pattern tk-ogsok; precedent:
# converse-signoff.test.sh, liveness-sweep-delta.test.sh).
#
# The bug: the check keyed two per-visit decisions off the SHARED
# gc.continuation_group. That assumes one subject == one topic, which is
# false for a standing scope (task_kind=triage-subject), where the group
# is a bucket carrying one visit per distinct item — the shape
# assets/scripts/detect-stalled-workflows.sh files, one visit per
# workflow root, each stamped stall_root=<root> under one subject.
#
# Two failures, both silent:
#   1. LOSS — a sitting about workflow A folds into a live sitting about
#      workflow B, because they share a bucket. A's decision is dropped
#      and the fold reads as correct dedup.
#   2. MUTUAL FOLD — both live sessions see each other, both fold, and
#      the subject ends with ZERO sittings. Recorded live: su-331y
#      (workflow su-ykfw) and su-s1if (workflow su-vc8n) under group
#      su-vehr, the rule firing both ways.
#
# Neither is a knowledge gap, so neither is fixable by telling the role
# to be careful: an agent that follows the contract exactly still drops
# the decision, and the mutual fold is a race between two sessions. The
# rule itself had to change, so the rule itself is what this test runs —
# the marked block is EXTRACTED from the prompt and EXECUTED against
# fixtures, not grepped for hopeful prose.
#
# Hermetic: stubs `gc`, reads the repo only; no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
PROMPT="$REPO/agents/converse/prompt.template.md"
DETECT="$REPO/assets/scripts/detect-stalled-workflows.sh"

PASS=0
FAIL=0
ok() {
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$1"
}
bad() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n        %s\n' "$1" "$2"
}
# have <label> <literal> <file> — fixed-string presence
have() {
    if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing: $2"; fi
}
# is <label> <got> <want>
is() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi
}

for f in "$PROMPT" "$DETECT"; do
    [ -r "$f" ] || {
        printf 'converse-fold-scope: cannot read %s\n' "$f" >&2
        exit 1
    }
done
command -v jq >/dev/null 2>&1 || {
    printf 'converse-fold-scope: jq is required to run the extracted block\n' >&2
    exit 1
}

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"
FIXDIR="$TMPD/fix"
mkdir -p "$BIN" "$FIXDIR"

# A stub `gc` serving exactly the two reads the block makes. Anything else
# exits 2, so a block that grows a third read fails here rather than
# silently reading the live store from a test.
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 2
case "${2:-}" in
    show)
        f="$FIXDIR/show-${3:-}.json"
        if [ -r "$f" ]; then cat "$f"; else printf '[]\n'; fi
        ;;
    list) cat "$FIXDIR/list.json" ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"

# visit <id> <group> <item> <assignee> — one row of the in_progress listing.
# An empty <item> writes NO stall_root key at all: absent is the ordinary
# subject-is-the-topic shape, and it must behave differently from a stall
# visit rather than collapsing to the same branch.
# A 5th argument writes the `tracks` edge a visit is filed with alongside its
# stamp. It is the visit's SECOND recording of its own subject, and the one that
# has held where the stamp did not (su-ab9je) — so it is what the empty-group
# cases below recover from.
visit() {
    jq -nc --arg id "$1" --arg g "$2" --arg i "$3" --arg a "$4" --arg t "${5:-}" \
        '{id:$id, assignee:$a,
          metadata:({"task_kind":"visit","gc.continuation_group":$g}
                    + (if $i == "" then {} else {"stall_root":$i} end))}
         + (if $t == "" then {} else {dependencies:[{id:$t, dependency_type:"tracks"}]} end)'
}
# fixture <visit-json>... — write list.json plus a show-<id>.json per visit.
fixture() {
    rm -f "$FIXDIR"/*.json
    printf '%s\n' "$@" | jq -sc '.' >"$FIXDIR/list.json"
    for row in "$@"; do
        printf '%s' "$row" | jq -c '[.]' >"$FIXDIR/show-$(printf '%s' "$row" | jq -r '.id').json"
    done
}
# unreadable — a listing that is not JSON (the read that did not happen).
unreadable() {
    printf 'ERROR: dolt: connection refused\n' >"$FIXDIR/list.json"
}

# The block under test, lifted verbatim between its markers.
extract_block() {
    awk '/# >>> visit-fold-check/ {f = 1; next}
         /# <<< visit-fold-check/ {f = 0}
         f {print}' "$PROMPT"
}
# run_block <visit-id> <subject-id> — prints ITEM=… / HOLDER=… as resolved.
# Runs with the stub first on PATH and cwd outside any checkout.
run_block() {
    {
        extract_block
        printf 'printf "ITEM=%%s\\nHOLDER=%%s\\n" "$ITEM" "$HOLDER"\n'
    } >"$TMPD/probe.sh"
    (
        cd "$TMPD" &&
            PATH="$BIN:$PATH" FIXDIR="$FIXDIR" VISIT="$1" SUBJECT="$2" \
                bash "$TMPD/probe.sh" 2>/dev/null
    )
}
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }
# holder <visit> <subject> — just the resolved holder.
holder() { field "$(run_block "$1" "$2")" HOLDER; }
# legacy_holds <subject> — what the OLD group-only rule saw: the count of
# held sibling visits of this group. >1 means it told BOTH sittings that
# another session already holds one. Present as a positive control: it
# proves each fixture below actually reproduces the bug rather than being
# a shape the old rule handled correctly all along.
legacy_holds() {
    jq --arg s "$1" '[.[] | select((.metadata.task_kind // "") == "visit")
        | select((.metadata["gc.continuation_group"] // "") == $s)
        | select(.assignee != "")] | length' "$FIXDIR/list.json"
}

# legacy_holder <visit> <subject> — what the PRE-FIX block resolved, reproduced
# exactly: no tracks-edge recovery, no empty-subject refusal. Present for the
# same reason as legacy_holds — to prove each empty-group fixture below really
# does reproduce the defect rather than being a shape the old rule handled.
legacy_holder() {
    _lh_i=$(jq -r '.[0].metadata.stall_root // ""' "$FIXDIR/show-$1.json" 2>/dev/null)
    [ -n "$_lh_i" ] || _lh_i="$2"
    jq -r --arg s "$2" --arg i "$_lh_i" --arg v "$1" '
        [ .[] | select((.metadata.task_kind // "")=="visit")
          | select((.metadata["gc.continuation_group"] // "")==$s)
          | select(((.metadata.stall_root // "") | if . == "" then $s else . end)==$i)
          | select((.assignee // "")!="") | .id ]
        + [$v] | unique | .[0]' "$FIXDIR/list.json" 2>/dev/null
}

BLOCK="$(extract_block)"
if [ -n "$BLOCK" ]; then
    ok "the fold check is extractable (# >>> visit-fold-check markers present)"
else
    printf 'converse-fold-scope: no visit-fold-check block in %s — nothing to test\n' "$PROMPT" >&2
    exit 1
fi

echo "── a bucket's siblings are about DIFFERENT items: neither folds ──"
# The loss, in its live shape: one standing scope, two workflows, two
# sessions. Reverse-ordered on purpose — the answer must come from the
# ids, not from which row the listing happened to return first.
fixture "$(visit v-two sub r-beta sess-2)" "$(visit v-one sub r-alpha sess-1)"
is "positive control: the old group-only rule saw a sibling for both" \
    "$(legacy_holds sub)" "2"
out="$(run_block v-one sub)"
is "the item is the visit's own target, not the bucket" "$(field "$out" ITEM)" "r-alpha"
is "v-one holds its own sitting" "$(field "$out" HOLDER)" "v-one"
is "v-two holds its own sitting" "$(holder v-two sub)" "v-two"

echo "── two sittings on the SAME item: exactly one folds ──"
fixture "$(visit v-two sub r-alpha sess-2)" "$(visit v-one sub r-alpha sess-1)"
is "positive control: both would fold under an untied rule" "$(legacy_holds sub)" "2"
h1="$(holder v-one sub)"
h2="$(holder v-two sub)"
is "lowest id holds" "$h1" "v-one"
is "the higher id folds into it" "$h2" "v-one"
folds=0
[ "$h1" = "v-one" ] || folds=$((folds + 1))
[ "$h2" = "v-two" ] || folds=$((folds + 1))
is "exactly one of the two sittings folds (never both, never neither)" "$folds" "1"

echo "── a subject with no per-visit target still dedups (legacy shape) ──"
# The ordinary case the original rule was written for: one subject, one
# topic, two visits. Absent stall_root falls back to the subject, so both
# are about the same item and the fold still fires — narrowing the scope
# must not switch dedup off for the shape that always needed it.
fixture "$(visit v-two sub '' sess-2)" "$(visit v-one sub '' sess-1)"
out="$(run_block v-two sub)"
is "the item falls back to the subject when no target is named" "$(field "$out" ITEM)" "sub"
is "the higher id still folds into the lower" "$(field "$out" HOLDER)" "v-one"
is "the lower id still holds" "$(holder v-one sub)" "v-one"

echo "── only live sittings of THIS group count ──"
fixture "$(visit v-one sub r-alpha '')" "$(visit v-two sub r-alpha sess-2)"
is "an unassigned sibling is not a holder, even with a lower id" \
    "$(holder v-two sub)" "v-two"
fixture "$(visit v-one other r-alpha sess-1)" "$(visit v-two sub r-alpha sess-2)"
is "a held visit of another group is not a holder, same item or not" \
    "$(holder v-two sub)" "v-two"
fixture "$(visit v-one sub r-alpha sess-1)"
is "a lone sitting holds" "$(holder v-one sub)" "v-one"

echo "── an EMPTY continuation group never folds across subjects ──"
# tk-tu5g3. The claim reports the gc.continuation_group STAMP, and that stamp
# lands empty on a minority of visits — 7 of the 74 ever filed when this was
# written, across three different filers, including BOTH visits in_progress
# city-wide on 2026-08-24. With an empty $SUBJECT both filters above stop
# discriminating: every empty-group visit matches the first, and stall_root is
# empty on those too so it falls back to $s and matches the second. The
# lowest-id tiebreak then picks a winner across UNRELATED topics — the
# ZERO-SITTINGS outcome it was added to prevent, arriving by the other door,
# and strictly worse than the guard merely failing open.

# The live shape: two in_progress visits, both stamped empty, about different
# subjects. Neither may fold into the other.
fixture "$(visit v-two '' '' sess-2)" "$(visit v-one '' '' sess-1)"
is "positive control: the pre-fix rule folded v-two into an unrelated v-one" \
    "$(legacy_holder v-two '')" "v-one"
is "an unresolvable subject holds its own sitting (v-two)" "$(holder v-two '')" "v-two"
is "…and so does the other one (v-one)" "$(holder v-one '')" "v-one"

# The recovery: the stamp is empty but the tracks edge carries the subject, so
# the block resolves it and ordinary scoping applies again — same subject, so
# the lowest id still holds and the higher still folds.
fixture "$(visit v-two '' '' sess-2 sub)" "$(visit v-one sub '' sess-1)"
is "an empty stamp is recovered from the tracks edge" "$(holder v-two '')" "v-one"

# …and recovery must not fold ACROSS subjects: same empty stamp, edge naming a
# different subject, so v-one is not v-two's holder.
fixture "$(visit v-two '' '' sess-2 other)" "$(visit v-one sub '' sess-1)"
is "a recovered subject still scopes the fold" "$(holder v-two '')" "v-two"

# The item still comes from the visit's own stall_root once the subject is
# recovered — recovery must not flatten the per-visit target back to the bucket.
fixture "$(visit v-two '' r-beta sess-2 sub)" "$(visit v-one sub r-alpha sess-1)"
out="$(run_block v-two '')"
is "a recovered subject keeps the per-visit item" "$(field "$out" ITEM)" "r-beta"
is "…and siblings about different items still do not fold" "$(field "$out" HOLDER)" "v-two"

# Neither recording present: nothing can scope the fold, so it must not happen.
fixture "$(visit v-two '' '' sess-2)" "$(visit v-one '' '' sess-1)"
is "with no stamp and no edge the block refuses to fold at all" \
    "$(holder v-two '')" "v-two"
have "the prompt says an unresolvable subject holds" \
    'You are the holder.' "$PROMPT"
have "the fold rule cites the empty-stamp bead" 'tk-tu5g3' "$PROMPT"

echo "── an unreadable listing never folds ──"
# Fail-safe direction. A listing that did not read cannot prove another
# session holds anything, and folding on it loses a decision nobody can
# tell was ever made — so the block must resolve EMPTY, which the prompt
# reads as "hold".
fixture "$(visit v-one sub r-alpha sess-1)"
unreadable
is "a garbage listing resolves no holder" "$(holder v-one sub)" ""
have "the prompt reads an empty holder as HOLD, not as fold" \
    'When it is EMPTY the' "$PROMPT"

echo "── the contract the block is written against ──"
# stall_root is the producer's key. If the detector renames it, this test
# fails here rather than the fold quietly widening back to the bucket.
have "the stall detector still stamps stall_root on the visit" \
    '--set-metadata "stall_root=$root"' "$DETECT"
have "the fold rule cites its pattern bead" 'tk-ogsok' "$PROMPT"
have "the fold is conditioned on the holder being ANOTHER visit" \
    'Fold only when `$HOLDER` is another' "$PROMPT"
# The takeaway target is the other half of the same defect: one field on a
# shared bucket cannot hold N sittings, and the readers look at the item.
n_item_stamp=$(grep -c 'takeaway "\$ITEM"' "$PROMPT")
if [ "$n_item_stamp" -ge 2 ]; then
    ok "both takeaway stamps target the item ($n_item_stamp)"
else
    bad "both takeaway stamps target the item" \
        "$n_item_stamp block(s) stamp \$ITEM — a stamp on the shared bucket is overwritten by the next sibling"
fi
if grep -q 'takeaway "\$SUBJECT"' "$PROMPT"; then
    bad "no takeaway stamps the shared bucket" \
        "a takeaway on \$SUBJECT clobbers siblings and is invisible to the readers that look at the item"
else
    ok "no takeaway stamps the shared bucket"
fi

echo
echo "converse-fold-scope: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
