#!/usr/bin/env bash
# Hermetic test for doctor/check-wait-is-an-edge (tk-wz4igt, invariant I1).
#
# THE INVARIANT: "every dependency is recorded in the bead graph — no wait lives
# only in prose or in a metadata string." A sentence freezes when it is written
# and is never true again, so a bead that is genuinely blocked and one that is
# entirely finished produce identical rows when prose is the only record.
#
# What is exercised here:
#   * both ERROR arms with positive controls — UNEDGED (target still open) and
#     FROZEN (target already closed, the defect in its terminal form). They are
#     different degrees and must not be merged into one message.
#   * THE SCAN SHAPE, which is its own case because getting it wrong was
#     silent. The first draft made the verb group non-capturing, so jq's scan()
#     returned only the id capture, the id landed in the verb slot, the
#     candidate field came out EMPTY, and the check reported a clean city while
#     eighteen real violations sat in the stores. A doctor check that cannot
#     fail is worse than no check, so (SCAN) pins what scan() must return.
#   * the NOISE FLOOR, which is most of the design. A bare "names a bead id"
#     predicate flags provenance, file paths and conclusions — and a conclusion
#     is prose BY DESIGN. Every one of those shapes has a case here asserting
#     it is NOT flagged.
#   * the id PREFIX SET coming from the roster, without which ordinary
#     hyphenated English ("base-branch", "in-flight") reads as a bead id.
#   * BOTH EDGE SPELLINGS. `bd list` says {type, depends_on_id} and `bd show`
#     says {dependency_type, id} for the same edge; reading one only would
#     report every prose wait as a violation.
#   * BOTH DIRECTIONS — an edge from either side puts the relation in the graph.
#   * the QUIET path — a store with nothing wrong exits 0 and names no bead.
#   * the fail-CLOSED arms. Every probe that cannot be READ must warn, never
#     pass.
#
# No live city, Dolt, or network — stub `gc`/`bd` on PATH and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$CHECK" ] || chmod +x "$CHECK" 2>/dev/null
mkdir -p "$TMP/bin" "$TMP/rig/.beads"

# --- stubs -------------------------------------------------------------------
# `bd list` answers from $STORE_LIST; `bd show` resolves ids out of $STORE_ALL,
# which is the union of open and closed beads. Both apply the filters they are
# handed rather than trusting them — a stub that answered every query with its
# whole fixture would let the check ask the wrong question and still pass.
cat > "$TMP/bin/bd" <<'BDEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BD_CALLS"
sub="${1:-}"
# WHICH STORE was asked. `--db <path>/.beads` names it, and the stub answers
# from that store's own fixture when one exists ($TMP_FIX/all-<name>.json),
# falling back to the single-store all.json. Without this the stub answers every
# --db with one fixture, which would let a store-local resolve pass a
# cross-store test — the exact defect tk-w2dk5k P1 reported.
store_fixture() {
    local dbp="" prev="" a
    for a in "$@"; do [ "$prev" = "--db" ] && dbp="$a"; prev="$a"; done
    if [ -n "$dbp" ]; then
        local key; key="$(basename "$(dirname "$dbp")")"
        [ -f "$TMP_FIX/all-$key.json" ] && { printf '%s' "$TMP_FIX/all-$key.json"; return; }
    fi
    printf '%s' "$TMP_FIX/all.json"
}
case "$sub" in
  list)
    [ -f "$TMP_FIX/list.rc" ] && exit "$(cat "$TMP_FIX/list.rc")"
    [ -f "$TMP_FIX/list.empty" ] && exit 0
    [ -f "$TMP_FIX/list.raw" ] && { cat "$TMP_FIX/list.raw"; exit 0; }
    src="$(store_fixture "$@")"
    [ -f "$src" ] || { echo '[]'; exit 0; }
    want=""; prev=""
    for a in "$@"; do [ "$prev" = "--status" ] && want="$a"; prev="$a"; done
    jq -c --arg st "$want" '[ .[] | select($st == "" or .status == $st) ]' < "$src"
    exit 0 ;;
  show)
    [ -f "$TMP_FIX/show.rc" ] && exit "$(cat "$TMP_FIX/show.rc")"
    # A non-zero exit carrying some OTHER error object — a real unreadable
    # store, as opposed to the determinate "none of these resolved".
    [ -f "$TMP_FIX/show.errobj" ] && { cat "$TMP_FIX/show.errobj"; exit 1; }
    src="$(store_fixture "$@")"
    [ -f "$src" ] || src="$TMP_FIX/all.json"
    ids=(); prev=""
    for a in "$@"; do
        case "$a" in --*) prev="$a"; continue ;; esac
        case "$prev" in --db) prev="" ; continue ;; esac
        [ "$a" = "show" ] && continue
        ids+=("$a"); prev=""
    done
    printf '%s\n' "${ids[@]}" | jq -R -s -c --slurpfile all "$src" '
        (split("\n") | map(select(length>0))) as $want
      | [ $all[0][] | select(.id as $i | $want | index($i)) ]
      | if length == 0 then {"error":"no issues found matching the provided IDs"} else . end'
    # EXIT 1 WHEN NOTHING RESOLVED, because that is what `bd show` does — it
    # prints the error object on stdout AND exits 1. A stub that returned 0
    # here would accept an answer the real tool refuses, and hide the arm that
    # has to tell "none of these are beads" apart from "the store is
    # unreadable". Resolution is grouped by owning store, so an all-non-id
    # batch is routine: `gc-toolkit` and `gc-toolkit.furiosa` are the whole
    # `gc-` group in a store whose waits name no gascity bead.
    printf '%s\n' "${ids[@]}" | jq -e -R -s --slurpfile all "$src" '
        (split("\n") | map(select(length>0))) as $want
      | any($all[0][]; .id as $i | $want | index($i))' >/dev/null 2>&1 || exit 1
    exit 0 ;;
esac
exit 0
BDEOF

cat > "$TMP/bin/gc" <<'GCEOF'
#!/usr/bin/env bash
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
    [ -f "$TMP_FIX/rigs.rc" ] && exit "$(cat "$TMP_FIX/rigs.rc")"
    cat "$TMP_FIX/rigs.json"; exit 0
fi
exit 0
GCEOF
chmod +x "$TMP/bin/bd" "$TMP/bin/gc"

FIX="$TMP/fix"; mkdir -p "$FIX"
export TMP_FIX="$FIX"
cat > "$FIX/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/rig","prefix":"tk","hq":false}]}
EOF

# --- fixture builders --------------------------------------------------------
# bead <id> <status> <notes> [edge-target] [edge-style]
# edge-style: list = {type, depends_on_id} (what `bd list` renders)
#             show = {dependency_type, id} (what `bd show` renders)
bead() {
    local id="$1" st="$2" notes="$3" edge="${4:-}" style="${5:-list}"
    local deps='[]'
    if [ -n "$edge" ]; then
        if [ "$style" = "show" ]; then
            deps=$(jq -c -n --arg t "$edge" '[{dependency_type:"blocks", id:$t}]')
        else
            deps=$(jq -c -n --arg t "$edge" '[{type:"blocks", depends_on_id:$t}]')
        fi
    fi
    jq -c -n --arg id "$id" --arg st "$st" --arg n "$notes" --argjson d "$deps" \
        '{id:$id, status:$st, notes:$n, metadata:{}, dependencies:$d}'
}
# bead_meta <id> <status> <metadata-key> <metadata-value>
bead_meta() {
    jq -c -n --arg id "$1" --arg st "$2" --arg k "$3" --arg v "$4" \
        '{id:$id, status:$st, notes:"", metadata:{($k):$v}, dependencies:[]}'
}
store() { printf '%s\n' "$@" | jq -s -c '.' > "$FIX/all.json"; }
# store_in <rig-dir-name> <bead-json>... — one store's contents, for the
# cross-store cases. The rig dir is created because the check skips a scope
# (and an owning store) whose .beads directory does not exist.
store_in() {
    local key="$1"; shift
    mkdir -p "$TMP/$key/.beads"
    printf '%s\n' "$@" | jq -s -c '.' > "$FIX/all-$key.json"
}
# two_rigs — a roster of two rigs with DISTINCT prefixes, so a candidate id
# names exactly one owning store.
two_rigs() {
    mkdir -p "$TMP/alpha/.beads" "$TMP/beta/.beads"
    cat > "$FIX/rigs.json" <<TWOEOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","prefix":"tk","hq":false},
         {"name":"beta","path":"$TMP/beta","prefix":"sl","hq":false}]}
TWOEOF
}
one_rig() {
    rm -f "$FIX/all-alpha.json" "$FIX/all-beta.json"
    cat > "$FIX/rigs.json" <<ONEEOF
{"rigs":[{"name":"alpha","path":"$TMP/rig","prefix":"tk","hq":false}]}
ONEEOF
}

run() {
    local tag="$1"
    BD_CALLS="$TMP/calls-$tag"; : > "$BD_CALLS"
    RC=0
    OUT="$(BD_CALLS="$BD_CALLS" TMP_FIX="$FIX" PATH="$TMP/bin:$PATH" bash "$CHECK" 2>&1)" || RC=$?
    CALLS="$(cat "$BD_CALLS" 2>/dev/null || true)"
}
reset_fix() { rm -f "$FIX/list.rc" "$FIX/list.empty" "$FIX/list.raw" "$FIX/show.rc" "$FIX/show.errobj" "$FIX/rigs.rc"; }

echo "── the two error arms ──"

# (UNEDGED) the wait is real, the target is open, the graph cannot answer it.
store "$(bead tk-9src1 open 'holding — blocked by tk-8tgt2 until that lands')" \
      "$(bead tk-8tgt2 open 'the thing being waited for')"
run unedged
eq "$RC" "2" "(UNEDGED) a prose wait with no edge is an ERROR"
has "$OUT" "tk-9src1" "(UNEDGED) …naming the waiting bead"
has "$OUT" "blocked by tk-8tgt2" "(UNEDGED) …quoting the prose that asserts the wait"
has "$OUT" "tk-8tgt2 is open" "(UNEDGED) …and the target's live status"

# (FROZEN) the target already closed. Same missing edge, worse consequence.
store "$(bead tk-9src1 open 'holding — blocked by tk-8tgt2 until that lands')" \
      "$(bead tk-8tgt2 closed 'done ages ago')"
run frozen
eq "$RC" "2" "(FROZEN) a prose wait on an already-CLOSED bead is an ERROR"
has "$OUT" "already CLOSED" "(FROZEN) …and is reported as the terminal form"
has "$OUT" "pending forever" "(FROZEN) …saying why it can never resolve itself"

echo "── the edge satisfies it, in either spelling and either direction ──"

# (EDGED) the ordinary correct shape.
store "$(bead tk-9src1 open 'holding — blocked by tk-8tgt2 until that lands' tk-8tgt2 list)" \
      "$(bead tk-8tgt2 open 'x')"
run edged
eq "$RC" "0" "(EDGED) a prose wait WITH an edge is not a finding"
hasnt "$OUT" "tk-9src1" "(EDGED) …and the bead is not named at all"

# (SPELLING) the same edge as `bd show` renders it. Reading one spelling only
# would report every correctly-edged wait as a violation.
store "$(bead tk-9src1 open 'holding — blocked by tk-8tgt2 until that lands' tk-8tgt2 show)" \
      "$(bead tk-8tgt2 open 'x')"
run spelling
eq "$RC" "0" "(SPELLING) an edge in bd show's {dependency_type,id} form counts too"

# (REVERSE) the edge points target -> source. The relation is in the graph.
store "$(bead tk-9src1 open 'holding — blocked by tk-8tgt2 until that lands')" \
      "$(bead tk-8tgt2 open 'x' tk-9src1 list)"
run reverse
eq "$RC" "0" "(REVERSE) an edge from the other side satisfies the invariant"

echo "── the noise floor: what must NOT be flagged ──"

# (CONCLUSION) a conclusion is prose BY DESIGN and is never cleared. Demanding
# an edge for one would invert the rule this check enforces.
store "$(bead tk-9src1 open 'disposed — folded into tk-8tgt2; nothing further here')" \
      "$(bead tk-8tgt2 closed 'x')"
run conclusion
eq "$RC" "0" "(CONCLUSION) 'folded into <bead>' is a conclusion, not a wait"
hasnt "$OUT" "tk-9src1" "(CONCLUSION) …and is not named"

# (PROVENANCE) the single most common bead reference in the ledger.
store "$(bead tk-9src1 open 'Implemented (tk-8tgt2): the change landed in three commits')" \
      "$(bead tk-8tgt2 closed 'x')"
run provenance
eq "$RC" "0" "(PROVENANCE) 'Implemented (<bead>)' is not a wait"

# (PATH) a spec path names a bead and is not a dependency.
store "$(bead tk-9src1 open 'Record: specs/tk-8tgt2/plan.md carries the reasoning')" \
      "$(bead tk-8tgt2 closed 'x')"
run path
eq "$RC" "0" "(PATH) a specs/<bead>/ path is not a wait"

# (SELFREF) a bead quoting its own id cannot be waiting on itself.
store "$(bead tk-9src1 open 'blocked by tk-9src1 per the earlier note')"
run selfref
eq "$RC" "0" "(SELFREF) a bead naming ITSELF is not a wait"

# (WORDS) ordinary hyphenated English. The prefix set from the roster is what
# stops these being read as bead ids at all.
store "$(bead tk-9src1 open 'blocked on base-branch, pending in-flight work, gated on un-taken slots')"
run words
eq "$RC" "0" "(WORDS) hyphenated English is not a bead id"
hasnt "$OUT" "base-branch" "(WORDS) …and produces no note either"

# (CLOSEDSRC) only OPEN beads are scanned; a closed bead's prose is history.
store "$(bead tk-9src1 closed 'holding — blocked by tk-8tgt2 until that lands')" \
      "$(bead tk-8tgt2 open 'x')"
run closedsrc
eq "$RC" "0" "(CLOSEDSRC) a CLOSED bead's prose is not judged"

echo "── the shapes that must be reported, but as notes ──"

# (RIGNAME) a rig or agent name shares a real prefix and can only be rejected
# by resolution. It is noted, never counted as a violation.
store "$(bead tk-9src1 open 'held by tk-7nope3 per the dispatch')"
run rigname
eq "$RC" "0" "(RIGNAME) an unresolvable candidate is not an ERROR"
has "$OUT" "resolves to no bead" "(RIGNAME) …but is reported as a note"

# (TRAILINGDOT) the id pattern must admit dots for hierarchical ids, so a
# sentence-final period gets swallowed unless it is stripped.
store "$(bead tk-9src1 open 'holding — awaiting tk-8tgt2.')" \
      "$(bead tk-8tgt2 closed 'x')"
run trailingdot
eq "$RC" "2" "(TRAILINGDOT) a sentence-final period does not break resolution"
has "$OUT" "tk-8tgt2 " "(TRAILINGDOT) …the id is reported without the period"

# (HIER) an interior dot is part of the id and must survive.
store "$(bead tk-9src1 open 'holding — blocked by tk-8tgt2.4 until that lands')" \
      "$(bead tk-8tgt2.4 open 'x')"
run hier
eq "$RC" "2" "(HIER) a hierarchical id keeps its interior dots"
has "$OUT" "tk-8tgt2.4" "(HIER) …and is reported whole"

echo "── metadata, and the scan shape ──"

# (METADATA) the invariant names blocked_reason and check.*.reason. The key is
# matched by SHAPE so today's actual keys (reason, rejection_reason) are
# covered without hardcoding one that does not exist.
store "$(bead_meta tk-9src1 open rejection_reason 'rejected — blocked by tk-8tgt2')" \
      "$(bead tk-8tgt2 open 'x')"
run metadata
eq "$RC" "2" "(METADATA) a wait in a reason-shaped metadata value is scanned"
has "$OUT" "tk-8tgt2" "(METADATA) …and named"

# (METAOTHER) a metadata value that is not a reason is not prose to scan.
store "$(bead_meta tk-9src1 open branch 'blocked by tk-8tgt2')" \
      "$(bead tk-8tgt2 open 'x')"
run metaother
eq "$RC" "0" "(METAOTHER) a non-reason metadata key is not scanned"

# (SCAN) the regression for the silent false negative: the verb group must be
# CAPTURING. With it non-capturing, scan() returns only the id, the candidate
# field empties, and the check reports a clean city over real violations.
if grep -q 'def verbs: "(waiting on' "$CHECK"; then
    ok "(SCAN) the verb alternation is a CAPTURING group"
else
    bad "(SCAN) the verb group is non-capturing — scan() will drop the verb and the check goes silently blind"
fi
store "$(bead tk-9src1 open 'holding — awaiting tk-8tgt2')" "$(bead tk-8tgt2 open 'x')"
run scanshape
has "$OUT" "awaiting tk-8tgt2" "(SCAN) …so the finding quotes BOTH the verb and the id"

echo "── the query, and the fail-closed arms ──"

store "$(bead tk-9src1 open 'nothing to see')"
run query
has "$CALLS" "--status open" "(QUERY) scopes to open beads"
has "$CALLS" "--limit 0"     "(QUERY) is uncapped, so a windowed listing cannot false-empty it"
has "$CALLS" "--db $TMP/rig/.beads" "(QUERY) reads the rig's own store"

store "$(bead tk-9src1 open 'holding — blocked by tk-8tgt2 until that lands')" "$(bead tk-8tgt2 open 'x')"
printf '3' > "$FIX/list.rc"; run listfail; reset_fix
eq "$RC" "1" "(LISTFAIL) an unreadable store warns"
has "$OUT" "NOT checked" "(LISTFAIL) …and says the store was not checked"

: > "$FIX/list.empty"; run listempty; reset_fix
eq "$RC" "1" "(LISTEMPTY) empty output is not an empty store"
has "$OUT" "returned no output" "(LISTEMPTY) …and is reported as unread"

printf 'not json' > "$FIX/list.raw"; run listjunk; reset_fix
eq "$RC" "1" "(LISTJUNK) a non-array listing warns"
has "$OUT" "not a JSON array" "(LISTJUNK) …saying so"

printf '4' > "$FIX/show.rc"; run showfail; reset_fix
eq "$RC" "1" "(SHOWFAIL) an unresolvable candidate set warns rather than passing"
has "$OUT" "could not resolve" "(SHOWFAIL) …because a partial resolve would drop real findings"

# (NOMATCH-NARROW) `bd show` exits 1 both when nothing in the batch resolved —
# a determinate answer, accepted — and when the store cannot be read. The
# accept arm is keyed on the no-matches error TEXT, so any other error object
# on a non-zero exit must still fail the store closed. Without this the
# leniency added for grouped all-non-id batches would swallow a broken store.
store "$(bead tk-9src1 open 'holding — blocked by tk-8tgt2 until that lands')" \
      "$(bead tk-8tgt2 open 'x')"
printf '%s' '{"error":"database is locked","schema_version":1}' > "$FIX/show.errobj"
run nomatch_narrow; reset_fix
eq "$RC" "1" "(NOMATCH-NARROW) a different error on a non-zero exit still fails closed"
has "$OUT" "could not resolve" "(NOMATCH-NARROW) …and says the store was not checked"

cat > "$FIX/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/rig","prefix":"","hq":false}]}
EOF
run noprefix
eq "$RC" "1" "(NOPREFIX) no usable issue prefix exits 1"
has "$OUT" "cannot be told from ordinary hyphenated prose" "(NOPREFIX) …because guessing is worse than not looking"
cat > "$FIX/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/rig","prefix":"tk","hq":false}]}
EOF

printf '2' > "$FIX/rigs.rc"; run rigfail; reset_fix
eq "$RC" "1" "(RIGFAIL) a failed rig listing exits 1"
has "$OUT" "cannot determine" "(RIGFAIL) …and refuses to judge"

echo "── cross-store waits (tk-w2dk5k P1) ──"
# A wait can name a bead in another rig. Resolved only in the store that
# mentioned it, the target answers "no issues found", the finding is downgraded
# to an unresolved NOTE, and the check exits 0 with a real unedged wait
# standing. Resolution follows the candidate's PREFIX to its owning store.

# (XSTORE) the live shape: signal-loom sl-djvs blocked on gc-toolkit tk-bq9ua.
two_rigs
store_in alpha "$(bead tk-8tgt2 open 'the thing being waited for')"
store_in beta  "$(bead sl-9src1 open 'holding — blocked by tk-8tgt2 until that lands')"
run xstore
eq "$RC" "2" "(XSTORE) a cross-store wait with no edge is an ERROR, not a note"
has "$OUT" "sl-9src1" "(XSTORE) …naming the waiting bead"
has "$OUT" "tk-8tgt2 is open" "(XSTORE) …with the target's status read from ITS OWN store"
hasnt "$OUT" "resolves to no bead" "(XSTORE) …and it is no longer downgraded to an unresolved note"

# (XSTORE-EDGED) the same pair, recorded. A cross-rig edge is just a foreign id
# in the source's edge list, so the crossing must not manufacture a finding.
two_rigs
store_in alpha "$(bead tk-8tgt2 open 'the thing being waited for')"
store_in beta  "$(bead sl-9src1 open 'holding — blocked by tk-8tgt2 until that lands' tk-8tgt2 list)"
run xstore_edged
eq "$RC" "0" "(XSTORE-EDGED) a cross-store wait WITH an edge is not a finding"
hasnt "$OUT" "sl-9src1" "(XSTORE-EDGED) …and the bead is not named"

# (XSTORE-REVERSE) the edge points target -> source, across the boundary. The
# reverse direction is read from the foreign store's own resolve.
two_rigs
store_in alpha "$(bead tk-8tgt2 open 'the thing waited for' sl-9src1 show)"
store_in beta  "$(bead sl-9src1 open 'holding — blocked by tk-8tgt2 until that lands')"
run xstore_reverse
eq "$RC" "0" "(XSTORE-REVERSE) a cross-store edge from the other side satisfies it too"
# Non-vacuous: a store-local resolve also exits 0 here, but by way of an
# unresolved NOTE that names the bead. Silence is what distinguishes them.
hasnt "$OUT" "sl-9src1" "(XSTORE-REVERSE) …silently, not via an unresolved note"

# (XSTORE-FROZEN) the foreign target already CLOSED — the terminal form, which
# store-local resolution could never reach at all.
two_rigs
store_in alpha "$(bead tk-8tgt2 closed 'done ages ago')"
store_in beta  "$(bead sl-9src1 open 'holding — blocked by tk-8tgt2 until that lands')"
run xstore_frozen
eq "$RC" "2" "(XSTORE-FROZEN) a cross-store wait on a CLOSED bead is an ERROR"
has "$OUT" "already CLOSED" "(XSTORE-FROZEN) …reported as the terminal form"

# (XSTORE-GHOST) a candidate whose prefix names a real rig but which exists in
# no store stays a NOTE. Widening resolution must not turn "does not exist"
# into a finding.
two_rigs
store_in alpha "$(bead tk-1aaa1 open 'plain work')"
store_in beta  "$(bead sl-9src1 open 'holding — blocked by tk-7ghost until that lands')"
run xstore_ghost
eq "$RC" "0" "(XSTORE-GHOST) a wait on a bead that exists nowhere is not an error"
has "$OUT" "resolves to no bead in any store" "(XSTORE-GHOST) …it is a note, and says the search was city-wide"
one_rig

echo "── verb boundaries: conclusion prose is not a dependency demand (tk-w2dk5k P2) ──"

# (BOUNDARY) `blocked on` is a PREFIX of `blocked only`. Unbounded, the live
# check read "Blocked only on mechanism - see tk-8tgt2" as a wait on tk-8tgt2.
store "$(bead tk-9src1 open 'Blocked only on mechanism - see tk-8tgt2 for the reasoning')" \
      "$(bead tk-8tgt2 open 'x')"
run boundary
eq "$RC" "0" "(BOUNDARY) 'blocked only on' is not 'blocked on' — no finding"
hasnt "$OUT" "tk-9src1" "(BOUNDARY) …and the bead is not named"

# (UNBLOCKED) the negated form, which the same missing boundary inverted:
# `unblocked by <id>` contains `blocked by <id>`.
store "$(bead tk-9src1 open 'unblocked by tk-8tgt2 landing last night; proceeding')" \
      "$(bead tk-8tgt2 closed 'x')"
run unblocked
eq "$RC" "0" "(UNBLOCKED) 'unblocked by' is not 'blocked by' — no finding"
hasnt "$OUT" "tk-9src1" "(UNBLOCKED) …and the bead is not named"

# (DEPENDING) `pending` inside `depending`, and inside `cancelPending`. Both
# are live shapes: "depending on su-3885" and "AfterFunc-vs-cancelPending
# ordering race filed as gc-l2c6v" were both reported as waits.
store "$(bead tk-9src1 open 'depending on tk-8tgt2 the rebase may be unnecessary')" \
      "$(bead tk-8tgt2 open 'x')"
run depending
eq "$RC" "0" "(DEPENDING) 'pending' inside 'depending' is not a wait"
store "$(bead tk-9src1 open 'the AfterFunc-vs-cancelPending ordering race filed as tk-8tgt2')" \
      "$(bead tk-8tgt2 open 'x')"
run cancelpending
eq "$RC" "0" "(DEPENDING) …nor inside 'cancelPending'"

# (UNBLOCKED-ONCE) the shape that needs BOTH boundaries at once: `unblocked
# once <id>` contains `blocked on` — `un` on the left, `once` on the right.
# Live: "unblocked once su-jtqo1 lands" was reported as blocked on su-jtqo1.
store "$(bead tk-9src1 open 'unblocked once tk-8tgt2 lands; nothing to do here')" \
      "$(bead tk-8tgt2 open 'x')"
run unblocked_once
eq "$RC" "0" "(UNBLOCKED-ONCE) 'unblocked once' is not 'blocked on'"
hasnt "$OUT" "tk-9src1" "(UNBLOCKED-ONCE) …and the bead is not named"

# (BOUNDARY-CONTROL) the tightening must not strand the positive path: the
# bare verbs it was narrowing still fire. Without this, (BOUNDARY) and
# (UNBLOCKED) would also pass against a regex that matched nothing at all.
store "$(bead tk-9src1 open 'blocked on tk-8tgt2 for now')" \
      "$(bead tk-8tgt2 open 'x')"
run boundary_ctl
eq "$RC" "2" "(BOUNDARY-CONTROL) a bare 'blocked on <id>' still fires"

# (BOUNDARY-SUFFIX) `await` is itself a prefix of `awaiting`. The longer
# alternative must still win rather than the boundary killing both.
store "$(bead tk-9src1 open 'awaiting tk-8tgt2 before the rebase')" \
      "$(bead tk-8tgt2 open 'x')"
run boundary_suffix
eq "$RC" "2" "(BOUNDARY-SUFFIX) 'awaiting <id>' still matches with boundaries on"

echo "── the quiet path ──"
store "$(bead tk-1aaa1 open 'plain work, no waits')" "$(bead tk-2bbb2 open 'also plain')"
run quiet
eq "$RC" "0" "(QUIET) a store with no prose waits exits 0"
has "$OUT" "is also a graph edge" "(QUIET) …and says the invariant holds"

echo ""
echo "check-wait-is-an-edge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
