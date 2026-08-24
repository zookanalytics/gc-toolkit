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
case "$sub" in
  list)
    [ -f "$TMP_FIX/list.rc" ] && exit "$(cat "$TMP_FIX/list.rc")"
    [ -f "$TMP_FIX/list.empty" ] && exit 0
    [ -f "$TMP_FIX/list.raw" ] && { cat "$TMP_FIX/list.raw"; exit 0; }
    want=""; prev=""
    for a in "$@"; do [ "$prev" = "--status" ] && want="$a"; prev="$a"; done
    jq -c --arg st "$want" '[ .[] | select($st == "" or .status == $st) ]' < "$TMP_FIX/all.json"
    exit 0 ;;
  show)
    [ -f "$TMP_FIX/show.rc" ] && exit "$(cat "$TMP_FIX/show.rc")"
    ids=(); prev=""
    for a in "$@"; do
        case "$a" in --*) prev="$a"; continue ;; esac
        case "$prev" in --db) prev="" ; continue ;; esac
        [ "$a" = "show" ] && continue
        ids+=("$a"); prev=""
    done
    printf '%s\n' "${ids[@]}" | jq -R -s -c --slurpfile all "$TMP_FIX/all.json" '
        (split("\n") | map(select(length>0))) as $want
      | [ $all[0][] | select(.id as $i | $want | index($i)) ]
      | if length == 0 then {"error":"no issues found matching the provided IDs"} else . end'
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

run() {
    local tag="$1"
    BD_CALLS="$TMP/calls-$tag"; : > "$BD_CALLS"
    RC=0
    OUT="$(BD_CALLS="$BD_CALLS" TMP_FIX="$FIX" PATH="$TMP/bin:$PATH" bash "$CHECK" 2>&1)" || RC=$?
    CALLS="$(cat "$BD_CALLS" 2>/dev/null || true)"
}
reset_fix() { rm -f "$FIX/list.rc" "$FIX/list.empty" "$FIX/list.raw" "$FIX/show.rc" "$FIX/rigs.rc"; }

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

echo "── the quiet path ──"
store "$(bead tk-1aaa1 open 'plain work, no waits')" "$(bead tk-2bbb2 open 'also plain')"
run quiet
eq "$RC" "0" "(QUIET) a store with no prose waits exits 0"
has "$OUT" "is also a graph edge" "(QUIET) …and says the invariant holds"

echo ""
echo "check-wait-is-an-edge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
