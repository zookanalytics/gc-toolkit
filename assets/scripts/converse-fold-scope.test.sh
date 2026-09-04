#!/usr/bin/env bash
# converse-fold-scope.test.sh — regression test for the converse role's
# fold-on-concurrent-hold check (pattern tk-ogsok; precedent:
# converse-signoff.test.sh, liveness-sweep-delta.test.sh).
#
# The bug: the check keyed two per-visit decisions off the SHARED
# gc.continuation_group. That assumes one subject == one topic, which is
# false for a standing scope (task_kind=triage-subject), where the group
# is a bucket carrying one visit per distinct item — the root-scoped
# stall-visit shape (one visit per workflow root, each stamped
# stall_root=<root> under one subject), which liveness-sweep.sh's root
# fold consumes.
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
SWEEP="$REPO/assets/scripts/liveness-sweep.sh"

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

for f in "$PROMPT" "$SWEEP"; do
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
# stamp — the visit's SECOND recording of its own subject, and the one that
# has held where the stamp did not (su-ab9je); it is what the empty-group
# cases below recover from.
# A 6th writes escalation_key, the stamp escalate.sh gives every visit it
# files. Those name no target, so the key is the only thing that tells two
# situations under one bucket apart.
visit() {
    jq -nc --arg id "$1" --arg g "$2" --arg i "$3" --arg a "$4" --arg t "${5:-}" \
        --arg k "${6:-}" \
        '{id:$id, assignee:$a,
          metadata:({"task_kind":"visit","gc.continuation_group":$g}
                    + (if $i == "" then {} else {"stall_root":$i} end)
                    + (if $k == "" then {} else {"escalation_key":$k} end))}
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

echo "── one bucket, two escalation keys: neither folds ──"
# escalate.sh files one visit per situation and names no target, so every
# visit it files under a standing scope carries an absent stall_root and the
# subject cannot tell them apart. escalation_key can, and it is a stamp the
# filer already writes on each one.
fixture "$(visit v-two sub '' sess-2 '' doctor-check-cadence-live)" \
    "$(visit v-one sub '' sess-1 '' doctor-dolt-noms-size)"
is "positive control: the old group-only rule saw a sibling for both" \
    "$(legacy_holds sub)" "2"
is "positive control: the pre-fix block folded two distinct findings together" \
    "$(legacy_holder v-two sub)" "v-one"
out="$(run_block v-two sub)"
is "the item stays the SUBJECT — a takeaway target has to be a bead" \
    "$(field "$out" ITEM)" "sub"
is "v-two holds its own sitting" "$(field "$out" HOLDER)" "v-two"
is "v-one holds its own sitting" "$(holder v-one sub)" "v-one"

# The converse: one situation, two visits. escalate.sh dedups these before
# the second exists, and the fold must still collapse them if one ever does.
fixture "$(visit v-two sub '' sess-2 '' doctor-dolt-noms-size)" \
    "$(visit v-one sub '' sess-1 '' doctor-dolt-noms-size)"
is "two visits for the SAME key still fold to the lowest id" \
    "$(holder v-two sub)" "v-one"

# A named target outranks the key: stall_root is both the item and the topic,
# so a stall visit's fold does not change because a key rode along.
fixture "$(visit v-two sub r-alpha sess-2 '' key-beta)" \
    "$(visit v-one sub r-alpha sess-1 '' key-alpha)"
is "a shared stall_root folds even when the keys differ" \
    "$(holder v-two sub)" "v-one"

# The two namespaces never compare equal: a key spelled like a sibling's
# stall_root is still a different topic.
fixture "$(visit v-two sub '' sess-2 '' r-alpha)" \
    "$(visit v-one sub r-alpha sess-1)"
is "a key equal to a sibling's stall_root is not the same topic" \
    "$(holder v-two sub)" "v-two"

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
# tk-tu5g3. The claim reports the gc.continuation_group STAMP, and the stamp
# lands empty on a minority of visits. With an empty $SUBJECT both filters
# stop discriminating — every empty-group visit matches the first, and
# stall_root is empty on those too so it falls back to $s and matches the
# second — and the lowest-id tiebreak picks a winner across UNRELATED topics:
# the zero-sittings outcome the tiebreak was added to prevent, by the other
# door.

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

# The interlock, from the SIBLING side. Recovering only our own subject would
# leave the candidate scan matching siblings by stamp alone — two live
# sittings whose edges name the same subject would each see only themselves,
# both read as holder, and both proceed.
fixture "$(visit v-two '' '' sess-2 sub)" "$(visit v-one '' '' sess-1 sub)"
h1="$(holder v-one '')"
h2="$(holder v-two '')"
is "two empty-stamped siblings tracking the same subject: lowest id holds" "$h1" "v-one"
is "…and the higher id folds into it" "$h2" "v-one"
folds=0
[ "$h1" = "v-one" ] || folds=$((folds + 1))
[ "$h2" = "v-two" ] || folds=$((folds + 1))
is "…so exactly one of the two folds (never both, never neither)" "$folds" "1"

# The mirror: the scan must not over-match once it resolves candidates. Two
# empty stamps whose EDGES name different subjects are different sittings.
fixture "$(visit v-two '' '' sess-2 other)" "$(visit v-one '' '' sess-1 sub)"
is "two empty-stamped siblings tracking DIFFERENT subjects do not fold (v-two)" \
    "$(holder v-two '')" "v-two"
is "…nor the other way (v-one)" "$(holder v-one '')" "v-one"

# Mixed recording: one sibling stamped, one recovered from its edge. They are
# the same sitting and must see each other.
fixture "$(visit v-two '' '' sess-2 sub)" "$(visit v-one sub '' sess-1)"
is "an empty-stamped visit sees a properly stamped sibling" "$(holder v-two '')" "v-one"
fixture "$(visit v-two sub '' sess-2)" "$(visit v-one '' '' sess-1 sub)"
is "…and a properly stamped visit sees an empty-stamped sibling" "$(holder v-two sub)" "v-one"

# A candidate with neither recording cannot be placed, so it is nobody's
# holder — resolving candidates must not turn an unplaceable one into a match.
fixture "$(visit v-two '' '' sess-2)" "$(visit v-one sub '' sess-1)"
is "an unresolvable SIBLING is not a holder for a known subject" "$(holder v-two sub)" "v-one"
fixture "$(visit v-one '' '' sess-1)" "$(visit v-two sub '' sess-2)"
is "…and it does not match a subject it cannot be shown to share" "$(holder v-two sub)" "v-two"

# The item still comes from the visit's own stall_root once the subject is
# recovered — recovery must not flatten the per-visit target back to the
# bucket.
fixture "$(visit v-two '' r-beta sess-2 sub)" "$(visit v-one sub r-alpha sess-1)"
out="$(run_block v-two '')"
is "a recovered subject keeps the per-visit item" "$(field "$out" ITEM)" "r-beta"
is "…and siblings about different items still do not fold" "$(field "$out" HOLDER)" "v-two"

# Neither recording present: nothing can scope the fold, so it must not
# happen.
fixture "$(visit v-two '' '' sess-2)" "$(visit v-one '' '' sess-1)"
is "with no stamp and no edge the block refuses to fold at all" \
    "$(holder v-two '')" "v-two"
have "the prompt says an unresolvable subject holds" \
    'You are the holder.' "$PROMPT"

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
# stall_root is the shared key. If the sweep's root fold renames it, this
# test fails here rather than the fold quietly widening back to the bucket.
have "the liveness sweep still folds on the stall_root key" \
    '.metadata.stall_root // empty' "$SWEEP"
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

# ── HOLD-ARM PREMISE GATE (visit-hold-premise-gate) ──────────────────────────
# Deliberately housed in this suite, not a converse-hold-*.test.sh of its own:
# the pack has no test discovery, so a fresh file is a suite nobody runs
# (pack-tests-have-no-auto-discovery). This suite already extracts and executes
# blocks from the same prompt, so the hold-arm gate rides the harness the fold
# block built — same stub `gc`, same fixtures dir.
#
# The defect (tk-3vbus7): step 1's action=hold arm skipped the premise re-check
# on the action=hold verdict ALONE. But `gc hook --claim` returns
# existing_assignment (→ action=hold) for ANY bead already assigned to this
# session identity, including a claim that died BEFORE step 2 ever ran. The gate
# tells a real hold from a dead claim by a trace only a sitting past step 5
# leaves: step 5 stamps the demand's id on the VISIT bead as gc.hold_demand
# before it waits. The key is on the visit, so it is attributable — a sibling
# sitting on the same item stamps the shared item's demand and takeaway, never
# this visit's gc.hold_demand, so it cannot forge the trace. Absence routes to
# step 2, so a visit whose premise died between filing and claiming re-checks it
# and closes there instead of posting a framing for a dead premise.
echo "── the hold-arm premise gate is extractable ──"
extract_hold_block() {
    awk '/# >>> visit-hold-premise-gate/ {f = 1; next}
         /# <<< visit-hold-premise-gate/ {f = 0}
         f {print}' "$PROMPT"
}
if [ -n "$(extract_hold_block)" ]; then
    ok "the premise gate is extractable (# >>> visit-hold-premise-gate markers present)"
else
    bad "the premise gate is extractable" "no visit-hold-premise-gate block in $PROMPT"
fi

# began <visit-id> <subject> — run the extracted gate against the current
# fixtures and print the resolved BEGAN. Same stub, cwd, and PATH as the fold
# runner above; a distinct probe file so the two never collide.
began() {
    {
        extract_hold_block
        printf 'printf "GATE_BEGAN=%%s\\n" "$BEGAN"\n'
    } >"$TMPD/hold-probe.sh"
    (
        cd "$TMPD" &&
            PATH="$BIN:$PATH" FIXDIR="$FIXDIR" VISIT="$1" SUBJECT="$2" \
                bash "$TMPD/hold-probe.sh" 2>/dev/null
    ) | sed -n 's/^GATE_BEGAN=//p' | tail -1
}
# The gate reads one thing: gc.hold_demand on THIS visit's bead. hv_demand
# builds a sibling demand on the shared item — the trace the OLD item-level gate
# keyed on — kept here to prove this gate ignores it.
hv_reset() { rm -f "$FIXDIR"/*.json; printf '[]\n' >"$FIXDIR/list.json"; }
hv_visit() { # id [hold_demand] [stall_root]
    jq -nc --arg id "$1" --arg hd "${2:-}" --arg sr "${3:-}" \
        '[{id:$id, metadata:(({"task_kind":"visit"})
            + (if $hd == "" then {} else {"gc.hold_demand":$hd} end)
            + (if $sr == "" then {} else {"stall_root":$sr} end))}]' \
        >"$FIXDIR/show-$1.json"
}
hv_demand() { # demand-id item-id — a sibling open demand naming the item
    jq -nc --arg id "$1" --arg i "$2" '[{id:$id, assignee:"", metadata:{"gc.demand_for":$i}}]' \
        >"$FIXDIR/list.json"
}

echo "── a claim that died before step 5 leaves no trace: re-check the premise ──"
# The observed shape (tk-fzvjw7): an escalate visit under a standing scope whose
# replacement claim found no gc.hold_demand on the visit.
hv_reset
hv_visit v-dead
is "no trace resolves BEGAN=no (fall through to step 2)" "$(began v-dead sub)" "no"

echo "── a visit that stamped gc.hold_demand reached step 5: its hold is real ──"
hv_reset
hv_visit v-held d-held
is "gc.hold_demand resolves BEGAN=yes (re-open at step 4)" "$(began v-held sub)" "yes"

echo "── a sibling demand on the item is not THIS visit's trace ──"
# The P1 the visit-key closes: a standing scope with sibling sittings on one
# item carries an open demand for it. The OLD gate resolved the item and read
# that shared demand as proof this visit held; keyed on the visit it is not.
hv_reset
hv_visit v-sib "" item-x   # no gc.hold_demand; item resolvable, as the old gate keyed on
hv_demand d-x item-x       # a sibling's open demand on the same item
is "a sibling demand with no visit trace resolves BEGAN=no" "$(began v-sib sub)" "no"

echo "── the visit key stands even when its demand is no longer open ──"
# A ruling can close the demand while the sitting still holds. The trace is the
# visit's own record, not the demand's live status, so BEGAN does not depend on
# the listing.
hv_reset
hv_visit v-closed d-gone   # gc.hold_demand set; no matching open demand in list
is "gc.hold_demand with no open demand resolves BEGAN=yes" "$(began v-closed sub)" "yes"

echo "── the prompt gates the skip on the trace, not on the verdict ──"
have "the arm routes a traceless claim to step 2" 'fall through to step 2' "$PROMPT"
have "the arm keeps the fold check skipped on both branches" \
    'The fold check stays skipped on both branches.' "$PROMPT"
have "the gate reads gc.hold_demand off the visit (unique to this block)" \
    'gc.hold_demand' "$PROMPT"
have "step 5 stamps gc.hold_demand on the visit before it waits" \
    'set-metadata "gc.hold_demand=$DEMAND"' "$PROMPT"

# ── HOLD-DEMAND STAMP GATE (hold-demand-stamp-gate) ──────────────────────────
# The P1 this closes (tk-pcjtco): step 1 trusts gc.hold_demand as the SOLE proof
# of a real hold (the began() cases above), but step 5 wrote it as `update ||
# echo` and walked on. An update that is refused, or one that returns success
# without persisting, then leaves the framing posted with no trace, and a later
# scrollback-less restart reads BEGAN=no and closes the engaged sitting at step
# 2 as a dead premise — the mirror of the bug the gate exists to catch. The
# write's own exit status cannot see a value that never landed, so the gate
# reads the key back off the visit and refuses to frame unless it matches. This
# runs the extracted stamp block against a stub whose update result and
# persistence are dialed independently.
echo "── the stamp fails closed unless the trace lands on the visit ──"
BIN2="$TMPD/bin2"
FIX2="$TMPD/fix2"
mkdir -p "$BIN2" "$FIX2"
# A stub gc serving the stamp block's two calls. `bd update` persists the demand
# id it is given (unless STAMP_PERSIST=0) and exits STAMP_RC; `bd show` returns
# whatever update persisted, or [] if nothing did. STAMP_VALUE overrides the
# persisted id, for the stamp-landed-wrong case. Anything else exits 2, so a
# block that grows a third call fails here rather than reading the live store.
cat >"$BIN2/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 2
case "${2:-}" in
    update)
        if [ "${STAMP_PERSIST:-1}" = "1" ]; then
            v="${STAMP_VALUE:-}"
            if [ -z "$v" ]; then
                for a in "$@"; do
                    case "$a" in gc.hold_demand=*) v="${a#gc.hold_demand=}" ;; esac
                done
            fi
            printf '%s' "$v" >"$FIX2/stamped"
        fi
        exit "${STAMP_RC:-0}"
        ;;
    show)
        if [ -r "$FIX2/stamped" ]; then
            jq -nc --arg v "$(cat "$FIX2/stamped")" '[{metadata:{"gc.hold_demand":$v}}]'
        else
            printf '[]\n'
        fi
        ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$BIN2/gc"

extract_stamp_block() {
    awk '/# >>> hold-demand-stamp-gate/ {f = 1; next}
         /# <<< hold-demand-stamp-gate/ {f = 0}
         f {print}' "$PROMPT"
}
if [ -n "$(extract_stamp_block)" ]; then
    ok "the stamp gate is extractable (# >>> hold-demand-stamp-gate markers present)"
else
    bad "the stamp gate is extractable" "no hold-demand-stamp-gate block in $PROMPT"
fi
# stamp_rc <update-rc> <persist:0|1> [persist-value] — run the extracted stamp
# block with the stub dialed to that outcome; print the block's own exit status.
# Same cwd/PATH discipline as the runners above; a distinct probe file.
stamp_rc() {
    rm -f "$FIX2/stamped"
    extract_stamp_block >"$TMPD/stamp-probe.sh"
    (
        cd "$TMPD" &&
            PATH="$BIN2:$PATH" FIX2="$FIX2" STAMP_RC="$1" STAMP_PERSIST="$2" \
                STAMP_VALUE="${3:-}" VISIT="v-x" DEMAND="d-x" ITEM="item-x" \
                bash "$TMPD/stamp-probe.sh" >/dev/null 2>&1
    )
    printf '%s\n' "$?"
}
# verdict <update-rc> <persist> [value] — "held" when the block proceeds to
# frame (exit 0), "refused" when it exits before framing.
verdict() { [ "$(stamp_rc "$@")" = 0 ] && echo held || echo refused; }

is "a stamp that persists lets the hold proceed" "$(verdict 0 1)" "held"
is "a refused update that left no trace refuses the framing" "$(verdict 1 0)" "refused"
is "an update that reports success but does not persist still refuses" \
    "$(verdict 0 0)" "refused"
is "a stamp that landed the WRONG id refuses the framing" \
    "$(verdict 0 1 d-other)" "refused"

# Positive control, the role legacy_holder plays for the fold block. The pre-fix
# stamp was `update || echo` with no read-back, so a success-with-no-persist
# update satisfied it and the sitting framed with no trace. That it HELD where
# the gate now REFUSES proves the read-back closes a real regression rather than
# pinning a case the old line already caught.
legacy_verdict() {
    rm -f "$FIX2/stamped"
    printf 'gc bd update "$VISIT" --set-metadata "gc.hold_demand=$DEMAND" || echo stamp-failed\n' \
        >"$TMPD/legacy-stamp.sh"
    (
        cd "$TMPD" &&
            PATH="$BIN2:$PATH" FIX2="$FIX2" STAMP_RC="$1" STAMP_PERSIST="$2" \
                VISIT="v-x" DEMAND="d-x" bash "$TMPD/legacy-stamp.sh" >/dev/null 2>&1
    )
    [ "$?" = 0 ] && echo held || echo refused
}
is "positive control: the pre-fix update-or-echo framed on a success-no-persist stamp" \
    "$(legacy_verdict 0 0)" "held"

# The prose the fail-closed shape rests on: the block shows the visit back and
# gates the framing on the value, not on the write's exit status alone.
have "the stamp block reads gc.hold_demand back off the visit" \
    'gc bd show "$VISIT"' "$PROMPT"
have "…and refuses to frame when the read-back does not match the demand" \
    'DID NOT PERSIST' "$PROMPT"
have "…and exits before the framing on that refusal" \
    'Do NOT post the framing' "$PROMPT"

echo
echo "converse-fold-scope: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
