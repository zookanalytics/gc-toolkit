#!/usr/bin/env bash
# Hermetic test for assets/scripts/priority-lib.sh, the one definition of a
# bead's priority.
# Covers:
#   (DEF)       sourcing the file exposes $PRIORITY_JQ, priority_graph and the
#               depth cap
#   (CASES)     every case in priority-lib.fixture.json: the priority the
#               function computes, what the bead follows and through which bead,
#               its shift, or why it cannot be computed, and the reads the walk
#               makes
#   (SUBJECT)   a workflow bead leads to the bead it was poured for
#   (FOLLOWERS) the index a writer walks down from a moved bead
#   (FAIL)      a read that fails or does not parse fails the walk, and a chain
#               deeper than the cap is unreadable
#   (READERS)   every reader of a priority sources this file and applies
#               $PRIORITY_JQ
#   (NO-COPY)   no other file in the pack defines the function's jq defs
# A reader with a private copy of the function drifts silently from this one.
# The behavioral half lives beside each reader (queue-priority.test.sh,
# gc-helm-priority.test.sh).
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/priority-lib.sh"
FX="$HERE/priority-lib.fixture.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-priority-lib-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=priority-lib.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${PRIORITY_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$PRIORITY_JQ" || bad "(DEF) sourcing the file exposes \$PRIORITY_JQ"
[ "$(type -t priority_graph)" = "function" ] && ok "(DEF) sourcing the file defines priority_graph" || bad "(DEF) sourcing the file defines priority_graph"
case "${PRIORITY_MAX_DEPTH:-}" in ''|*[!0-9]*) bad "(DEF) PRIORITY_MAX_DEPTH is a whole number (got '${PRIORITY_MAX_DEPTH:-}')" ;; *) ok "(DEF) PRIORITY_MAX_DEPTH is a whole number" ;; esac
jq -e '(.beads | type) == "array" and (.cases | type) == "array" and (.cases | length) > 0' "$FX" >/dev/null 2>&1 \
    && ok "(DEF) the fixture carries a store and its cases" || bad "(DEF) the fixture carries a store and its cases"
eq "$(jq -n "$PRIORITY_JQ"'prio_depth' 2>/dev/null)" "$PRIORITY_MAX_DEPTH" "(DEF) the program reads the depth cap the shell names"

# The reader the walk calls: the fixture store, by id, the way a real reader
# answers from its own store at every status. Each call is logged so the reads
# can be counted.
STORE="$FX"
READS="$TMP/reads.log"
fx_read() {
    printf '%s\n' "$1" >> "$READS"
    jq -c --arg ids "$1" '($ids | split(",")) as $w | [ (if type == "array" then . else .beads end)[] | select(.id as $i | $w | index($i)) ]' "$STORE"
}
# walk <bead-id>: the walk for one bead, leaving its seed and its graph for ask.
walk() {
    : > "$READS"
    jq -c --arg b "$1" '[ (if type == "array" then . else .beads end)[] | select(.id == $b) ]' "$STORE" > "$TMP/seed.json"
    priority_graph fx_read "$TMP/seed.json" "$TMP/graph.json"
}
ask() { jq -c --slurpfile g "$TMP/graph.json" "$PRIORITY_JQ"".[0] | $1" "$TMP/seed.json" 2>/dev/null; }
reads() { wc -l < "$READS" | tr -d ' '; }

echo "# the fixture's cases"
while IFS= read -r c; do
    [ -n "$c" ] || continue
    name="$(printf '%s' "$c" | jq -r '.name')"
    bead="$(printf '%s' "$c" | jq -r '.bead')"
    if ! walk "$bead"; then bad "(CASES) $name: the walk for $bead fails"; continue; fi
    got="$(ask 'priority_of($g[0])')"
    want_err="$(printf '%s' "$c" | jq -r '.error // empty')"
    if [ -n "$want_err" ]; then
        eq "$(printf '%s' "$got" | jq -r 'has("priority") | tostring')" "false" "(CASES) $name: no priority is computed"
        has "$(printf '%s' "$got" | jq -r '.error // ""')" "$want_err" "(CASES) $name: the reason says why"
    else
        eq "$(printf '%s' "$got" | jq -c '{priority, kind, via, shift}')" \
           "$(printf '%s' "$c" | jq -c '{priority, kind, via, shift}')" "(CASES) $name"
    fi
    want_reads="$(printf '%s' "$c" | jq -r '.reads // empty')"
    [ -z "$want_reads" ] || eq "$(reads)" "$want_reads" "(CASES) $name: $want_reads read(s), one per generation of followed beads"
done <<< "$(jq -c '.cases[]' "$FX")"

echo "# a workflow bead leads to the bead it was poured for"
walk step-1a && eq "$(ask 'priority_subject($g[0]) | .id')" '"m-plain"' "(SUBJECT) a step leads through its root and input convoy to its work bead"
walk root-owned && eq "$(ask 'priority_subject($g[0]) | .id')" '"cv-owned"' "(SUBJECT) a workflow over a convoy gascity did not make leads to that convoy"
walk rework-1 && eq "$(ask 'priority_subject($g[0]) | .id')" '"rework-1"' "(SUBJECT) a bead that is not a workflow bead is its own subject"

echo "# the followers index"
jq -c '[ .beads[] | {key: .id, value: .} ] | from_entries' "$FX" > "$TMP/all.json"
idx="$(jq -c "$PRIORITY_JQ"'priority_followers(.)' "$TMP/all.json" 2>/dev/null)"
eq "$(printf '%s' "$idx" | jq -c '.["epic-1"] | sort')" \
   '["anchor-1","bad-shift","lvl-1","m-claimed","m-held","m-later","m-plain","m-sooner","two-parents"]' \
   "(FOLLOWERS) every bead that could follow the epic, a member of two epics included"
eq "$(printf '%s' "$idx" | jq -c '.["anchor-1"] | sort')" '["review-1","rework-1"]' "(FOLLOWERS) an anchor's PR-finishing work follows it"
eq "$(printf '%s' "$idx" | jq -c '.["m-plain"] | sort')" '["cv-1"]' "(FOLLOWERS) a work bead's input convoy follows it, and a convoy gascity did not make does not"
eq "$(printf '%s' "$idx" | jq -c '.["root-1"] | sort')" '["fin-1","step-1a"]' "(FOLLOWERS) a root's steps follow it"
eq "$(printf '%s' "$idx" | jq -c '.["closed-epic"] // [] | sort')" '["orphan"]' "(FOLLOWERS) the index names what could follow a closed bead, and priority_of decides it follows nothing"
eq "$(printf '%s' "$idx" | jq -c '[ .[][] ] | index("merged-anchor")')" 'null' "(FOLLOWERS) a closed bead follows nothing"

echo "# a read that fails, and a chain past the cap"
fail_read() { return 1; }
jq -c '[ .beads[] | select(.id == "m-plain") ]' "$FX" > "$TMP/seed.json"
priority_graph fail_read "$TMP/seed.json" "$TMP/graph.json"; rc=$?
[ "$rc" -ne 0 ] && ok "(FAIL) a read that fails fails the walk" || bad "(FAIL) a read that fails fails the walk"
garbage_read() { printf 'not json'; }
priority_graph garbage_read "$TMP/seed.json" "$TMP/graph.json"; rc=$?
[ "$rc" -ne 0 ] && ok "(FAIL) a read that does not parse fails the walk" || bad "(FAIL) a read that does not parse fails the walk"
envelope_read() { printf '{"issues":%s}' "$(fx_read "$1")"; }
STORE="$FX"; priority_graph envelope_read "$TMP/seed.json" "$TMP/graph.json" \
    && eq "$(ask 'priority_of($g[0]) | .priority')" "1" "(FAIL) a read in bd's envelope shape is read like a plain array" \
    || bad "(FAIL) a read in bd's envelope shape is read like a plain array"

# A chain one level deeper than the cap: chain-0 is the top, and the seed sits
# PRIORITY_MAX_DEPTH + 1 levels under it.
deep="$TMP/deep.json"
jq -n --argjson n "$((PRIORITY_MAX_DEPTH + 1))" '
    [ {id: "chain-0", status: "open", issue_type: "epic", priority: 1} ]
    + [ range(1; $n + 1) as $i | {id: "chain-\($i)", status: "open", issue_type: "task", priority: 2,
        dependencies: [{issue_id: "chain-\($i)", depends_on_id: "chain-\($i - 1)", type: "parent-child"}]} ]' > "$deep"
STORE="$deep"
: > "$READS"
jq -c --arg b "chain-$((PRIORITY_MAX_DEPTH + 1))" '[ .[] | select(.id == $b) ]' "$deep" > "$TMP/seed.json"
if priority_graph fx_read "$TMP/seed.json" "$TMP/graph.json"; then
    eq "$(reads)" "$PRIORITY_MAX_DEPTH" "(FAIL) the walk stops reading at the cap"
    has "$(ask 'priority_of($g[0]) | .error // ""')" "deeper than $PRIORITY_MAX_DEPTH levels" "(FAIL) a chain past the cap is unreadable, not computed from where the reads stopped"
else
    bad "(FAIL) a chain past the cap still walks to the cap"
fi
jq -c --arg b "chain-$((PRIORITY_MAX_DEPTH - 1))" '[ .[] | select(.id == $b) ]' "$deep" > "$TMP/seed.json"
priority_graph fx_read "$TMP/seed.json" "$TMP/graph.json" \
    && eq "$(ask 'priority_of($g[0]) | .priority')" "1" "(FAIL) a chain inside the cap is computed" \
    || bad "(FAIL) a chain inside the cap is computed"
STORE="$FX"

echo "# every reader sources this file"
READERS=("$HERE/queue-priority.sh")
for r in "${READERS[@]}"; do
    rel="${r#"$ROOT"/}"
    if [ ! -f "$r" ]; then bad "(READERS) $rel exists"; continue; fi
    grep -Eq '^[[:space:]]*\.[[:space:]]+"[^"]*priority-lib\.sh"' "$r" && ok "(READERS) $rel sources priority-lib.sh" || bad "(READERS) $rel sources priority-lib.sh"
    grep -Fq '$PRIORITY_JQ' "$r" && ok "(READERS) $rel applies \$PRIORITY_JQ" || bad "(READERS) $rel applies \$PRIORITY_JQ"
    grep -Fq 'priority_graph ' "$r" && ok "(READERS) $rel builds its graph with priority_graph" || bad "(READERS) $rel builds its graph with priority_graph"
done

echo "# no other file defines the function"
copies="$(git -C "$ROOT" grep -l -F -e 'def priority_of(' -e 'def prio_follows:' -e 'def prio_shift:' -- . 2>/dev/null \
    | grep -v -e '^assets/scripts/priority-lib.sh$' -e '^assets/scripts/priority-lib.test.sh$' || true)"
eq "$copies" "" "(NO-COPY) only priority-lib.sh defines the priority function"

echo
echo "priority-lib: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
