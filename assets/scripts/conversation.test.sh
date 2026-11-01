#!/usr/bin/env bash
# Hermetic test for assets/scripts/conversation.sh, the one definition of a
# conversation's shape. Covers:
#   (ALIAS)  the assignee rule: `human`, the task's own id, its `c-` fallback,
#            bare or qualified by rig and template binding, are a conversation's;
#            an alias naming another id, a pool route, a person's name and an id
#            that only contains the task's are not
#   (SAME)   the jq form and the shell form agree on every assignee above
#   (SHAPE)  `conversation` also wants a task tracking exactly one bead: a
#            second tracks edge, no tracks edge, or another issue type is not one
#   (SUBJ)   conversation_subjects names the beads its tracks edges reach
#   (NO-COPY) no other file in the pack defines these defs
# Reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/conversation.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
# shellcheck source=conversation.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${CONVERSATION_JQ:-}" ] && ok "sourcing the file exposes \$CONVERSATION_JQ" \
    || bad "sourcing the file exposes \$CONVERSATION_JQ"

# A row for task tk-c1 with the given assignee, tracking one bead.
row() { jq -nc --arg a "$1" '{id: "tk-c1", issue_type: "task", assignee: $a,
    dependencies: [{issue_id: "tk-c1", depends_on_id: "n-1", type: "tracks"}]}'; }
jq_says() { row "$1" | jq -r "$CONVERSATION_JQ"'if conversation then "yes" else "no" end'; }
sh_says() { if conversation_assignee "$1" tk-c1; then echo yes; else echo no; fi; }

echo "# the assignee rule, in both forms"
while IFS='|' read -r assignee want why; do
    [ -n "$assignee" ] || continue
    eq "$(jq_says "$assignee")" "$want" "(ALIAS) jq: $why ($assignee)"
    eq "$(sh_says "$assignee")" "$want" "(SAME) shell agrees: $why ($assignee)"
done <<'CASES'
human|yes|the queue of the operator
tk-c1|yes|the bare alias, the task's own id
c-tk-c1|yes|the c- fallback alias
gc-toolkit/gc-toolkit.tk-c1|yes|the alias a claim records, qualified
gc-toolkit/gc-toolkit.c-tk-c1|yes|the qualified c- fallback
gc-toolkit/tk-c1|yes|qualified by the rig alone
gc-toolkit/gc-toolkit.tk-c2|no|an alias naming another id
rig/gc-toolkit.polecat|no|a pool route
alice|no|a person's name: work that person owes
xtk-c1|no|an id that only ends with the task's
tk-c1x|no|an id that only begins with the task's
CASES
eq "$(row "" | jq -r "$CONVERSATION_JQ"'if conversation then "yes" else "no" end')" "no" "(ALIAS) an unassigned task is no conversation"
if conversation_assignee "" tk-c1; then bad "(SAME) shell: an empty assignee is no conversation's"; else ok "(SAME) shell: an empty assignee is no conversation's"; fi

echo "# the whole shape"
shape() { jq -nc "$1" | jq -r "$CONVERSATION_JQ"'if conversation then "yes" else "no" end'; }
eq "$(shape '{id:"tk-c1",issue_type:"task",assignee:"human",dependencies:[{depends_on_id:"n-1",type:"tracks"},{depends_on_id:"n-2",type:"tracks"}]}')" "no" \
   "(SHAPE) a task tracking two beads is no conversation"
eq "$(shape '{id:"tk-c1",issue_type:"task",assignee:"human"}')" "no" \
   "(SHAPE) a task tracking nothing is work a person owes, not a conversation"
eq "$(shape '{id:"tk-c1",issue_type:"task",assignee:"human",dependencies:[{depends_on_id:"n-1",type:"tracks"},{depends_on_id:"n-2",type:"blocks"}]}')" "yes" \
   "(SHAPE) an edge of another type beside its one tracks edge leaves it a conversation"
eq "$(shape '{id:"tk-c1",issue_type:"gate",await_type:"human",assignee:"human",dependencies:[{depends_on_id:"n-1",type:"tracks"}]}')" "no" \
   "(SHAPE) a gate is never a conversation"
eq "$(row human | jq -r "$CONVERSATION_JQ"'conversation_subjects | join(",")')" "n-1" \
   "(SUBJ) conversation_subjects names the bead it tracks"

echo "# no private copies"
COPY_RE='def (conversation|conversation_alias|conversation_subjects)[^a-z_]|conversation_assignee\(\)'
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/conversation.test.sh") continue ;; esac
        COPIES="$COPIES ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$COPY_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside conversation.sh defines the conversation shape"

echo
echo "conversation: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
