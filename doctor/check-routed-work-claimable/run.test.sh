#!/usr/bin/env bash
# Hermetic test for doctor/check-routed-work-claimable (tk-5cgyk).
#
# THE BUG the check guards: a pool is offered a bead by EXACT string equality
# between `gc.routed_to` and the pool's own route identity (gascity
# hookClaimMatchesRoute / the `bd ready --metadata-field` offer query). A
# rig-UNQUALIFIED pool name — `gc-toolkit.polecat` instead of
# `gc-toolkit/gc-toolkit.polecat` — is therefore matched by nothing, and the
# bead sits open and unassigned forever. That is how tk-5cgyk, the bead
# carrying the fix for the order-side twin of this defect, was itself stranded
# with every configuration file correct and no check anywhere reporting it.
#
# What is exercised here:
#   * the ERROR arm that names the exact repair, when the bead's own rig
#     qualifies the route into a live identity;
#   * the ERROR arm that can only list candidates — the city-store shape, where
#     no rig prefix applies (the wisp strand of tk-gi2pc);
#   * every shape that must NOT be flagged: an exact identity, the `human`
#     sentinel, an empty route, and a route nothing resembles (unclaimable, but
#     indistinguishable from a sentinel we do not know — reported, not judged);
#   * the QUERY itself — open + unassigned + carrying a route key. If that
#     drifts, the check silently stops seeing the beads it exists to find;
#   * the fail-CLOSED arms. Every probe that cannot be READ must warn, never
#     pass: with no identity set every route looks dead, and with an unreadable
#     store the strand is exactly as invisible as it was before the check. A
#     check that reports OK when it cannot see reproduces the original bug.
#
# No live city, Dolt, network, or beads — only jq, stub `gc`/`bd`, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
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

# The stub `bd` below keys each store off the basename of its --db path, so
# every scope's directory is named for its rig — the city root included.
CITY="$TMP/testcity"
mkdir -p "$CITY" "$TMP/stores" "$TMP/bin"

# --- Fixtures ---------------------------------------------------------------
# Identity universe: two rig-qualified pools sharing one bare name, plus a
# city-scope named session that HAS no rig prefix. That last one is why the
# check keys on the identity set and never on syntax: `pack.mayor` is bare and
# perfectly live, so "bare means broken" would flag a healthy route.
cat > "$TMP/agents.json" <<EOF
{"schema_version":"1","ok":true,"city_name":"testcity","city_path":"$CITY",
 "agents":[
   {"qualified_name":"alpha/pack.polecat","scope":"rig"},
   {"qualified_name":"beta/pack.polecat","scope":"rig"},
   {"qualified_name":"alpha/pack.refinery","scope":"rig"},
   {"qualified_name":"pack.mayor","scope":"city"}
 ]}
EOF

cat > "$TMP/rigs.json" <<EOF
{"schema_version":"1","ok":true,"rigs":[
  {"name":"testcity","path":"$CITY"},
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"}
]}
EOF

# bead <id> <route>
bead() { printf '{"id":"%s","status":"open","metadata":{"gc.routed_to":"%s"}}' "$1" "$2"; }
store() { # store() <name> <bead-json>... — writes $TMP/stores/<name>.json
    local name="$1"; shift
    local IFS=,
    printf '[%s]' "$*" > "$TMP/stores/$name.json"
}

# --- Stubs ------------------------------------------------------------------
# `gc`: agent list / rig list, each answering from a file so a scenario can hand
# over malformed bytes. AGENTS_RC / RIGS_RC force a failed probe.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "agent list")
      rc="${AGENTS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"
      cat "$AGENTS_JSON" ;;
  "rig list")
      rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"
      cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# `bd list`: answers per store from $STORES/<rig>.json, keyed off the --db path.
# Every invocation appends its full argv to $BD_ARGS so the query itself can be
# asserted. BD_FAIL_STORE makes one named store fail; BD_EMPTY_STORE makes one
# return nothing at all (which is not the same as `[]`).
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BD_ARGS"
db=""
prev=""
for a in "$@"; do
  [ "$prev" = "--db" ] && db="$a"
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
[ "$name" = "${BD_EMPTY_STORE:-}" ] && exit 0
f="$STORES/$name.json"
if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
chmod +x "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH"
export STORES="$TMP/stores"
BD_ARGS="$TMP/bd-args.log"
export BD_ARGS

run_check() {
    : > "$BD_ARGS"
    AGENTS_JSON="${AGENTS_JSON_OVERRIDE:-$TMP/agents.json}" \
    RIGS_JSON="${RIGS_JSON_OVERRIDE:-$TMP/rigs.json}" \
    GC_PACK_DIR="$ROOT" bash "$CHECK" 2>&1
}

# --- 0. Positive control ----------------------------------------------------
# Prove the fixture is real before trusting any verdict computed from it. A
# malformed identity list would make every "no findings" case pass for the
# wrong reason, and an identity set that accidentally CONTAINS the bare name
# would make the error cases impossible to reach.
eq "$(jq -r '.agents | length' "$TMP/agents.json" 2>/dev/null)" "4" \
   "positive control: the identity fixture parses and holds four agents"
eq "$(jq -r '[.agents[].qualified_name | select(. == "pack.polecat")] | length' "$TMP/agents.json")" "0" \
   "positive control: the bare pool name is NOT a live identity in the fixture"
eq "$(jq -r '[.agents[].qualified_name | select(. == "alpha/pack.polecat")] | length' "$TMP/agents.json")" "1" \
   "positive control: its rig-qualified form IS a live identity"

# --- 1. ERROR: rig-unqualified route, repair nameable ------------------------
store alpha "$(bead a-1 pack.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a rig-unqualified pool route on a rig bead is an ERROR"
has "$OUT" "a-1" "the error names the stranded bead"
has "$OUT" "alpha/pack.polecat" "the error names the exact repair"
rm -f "$TMP/stores/alpha.json"

# --- 2. The query the check relies on ---------------------------------------
# open + unassigned + has the route key. Drop any one of these and the check
# starts reporting clean on stores full of stranded work.
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--status open" "the scan asks for open beads"
has "$ARGS" "--no-assignee" "the scan asks for unassigned beads only"
has "$ARGS" "--has-metadata-key gc.routed_to" "the scan asks for beads carrying a route"
has "$ARGS" "--limit 0" "the scan is not silently truncated by a default limit"

# --- 3. ERROR: the city store, where no rig prefix applies ------------------
# The tk-gi2pc shape: a wisp poured into the city store with a bare rig-pool
# name. Still unclaimable, but the repair is not ours to pick, so the finding
# lists the candidates instead of naming one.
store testcity "$(bead c-1 pack.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bare rig-pool route in the CITY store is an ERROR"
has "$OUT" "c-1" "the city-store error names the bead"
has "$OUT" "alpha/pack.polecat, beta/pack.polecat" "it lists every candidate rather than guessing one"
hasnt "$OUT" "set gc.routed_to" "it does not name a repair it cannot know"
rm -f "$TMP/stores/testcity.json"

# --- 4. OK: an exact live identity ------------------------------------------
store alpha "$(bead a-2 alpha/pack.refinery)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a route that is an exact live identity is not flagged"
hasnt "$OUT" "a-2" "the working route is not named as a finding"

# --- 5. OK: a bare-but-live city identity -----------------------------------
# `pack.mayor` has no rig prefix and is perfectly claimable. This is the case
# that makes a syntax rule ("a dot and no slash is broken") wrong.
store alpha "$(bead a-2 alpha/pack.refinery)" "$(bead a-3 pack.mayor)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a bare route that IS a live city identity is not flagged"
hasnt "$OUT" "a-3" "the live city-scope route is not named as a finding"

# --- 6. OK: the `human` sentinel and an empty route -------------------------
# `human` names no agent on purpose (the signoff round cap writes it, the
# quiesce sweeps read it); an empty route is how the done sequence hands a bead
# to an assignee. Both are everywhere in a healthy store.
store alpha "$(bead a-4 human)" "$(bead a-5 '')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "the human sentinel and an empty route are not findings"
hasnt "$OUT" "a-4" "the human-routed bead is not named"
hasnt "$OUT" "a-5" "the empty-route bead is not named"

# --- 7. Note, not error: a route nothing resembles --------------------------
store alpha "$(bead a-6 not-an-agent-at-all)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an unrecognizable route does not fail the check"
has "$OUT" "a-6" "the unjudgeable route is still reported in the details"
has "$OUT" "reported, not judged" "the note says why it was not judged"
rm -f "$TMP/stores/alpha.json"

# --- 7b. Control characters in a bead payload do not cost us the store ------
# `bd list --json` emits notes and titles verbatim, and a literal TAB is invalid
# inside a JSON string exactly like the rest of the sub-0x20 range. Unstripped it
# aborts the parse, and the whole store degrades to "NOT checked" — so a single
# tab-indented note anywhere would hide every strand in that rig.
printf '[{"id":"a-7","status":"open","metadata":{"gc.routed_to":"pack.polecat"},"notes":"tab\there\001and a NUL-ish byte"}]' \
    > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bead payload carrying raw control characters still yields the finding"
has "$OUT" "a-7" "the finding survives the control characters"
hasnt "$OUT" "NOT checked" "the store is not degraded to unchecked by them"
rm -f "$TMP/stores/alpha.json"

# --- 8. A city with nothing routed is a clean pass, not a crash -------------
OUT=$(run_check); RC=$?
eq "$RC" "0" "empty stores are OK"
has "$OUT" "OK:" "the pass message is the OK line"

# --- 9. Fail-CLOSED: every probe that cannot be read ------------------------
# With no identity set every route looks dead; with an unreadable store the
# strand is as invisible as it was before this check existed. Neither may
# report OK.
OUT=$(AGENTS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc agent list\` warns (it must not report OK)"
has "$OUT" "cannot determine" "the warning says the answer is unknown, not clean"

printf 'not json at all' > "$TMP/garbage.json"
OUT=$(AGENTS_JSON_OVERRIDE="$TMP/garbage.json" run_check); RC=$?
eq "$RC" "1" "a malformed agent listing warns"

printf '{"schema_version":"1","ok":true,"agents":[]}' > "$TMP/noagents.json"
OUT=$(AGENTS_JSON_OVERRIDE="$TMP/noagents.json" run_check); RC=$?
eq "$RC" "1" "an agent listing with zero identities warns rather than flagging everything"

OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns"

printf '{"schema_version":"1","ok":true,"rigs":[]}' > "$TMP/norigs.json"
OUT=$(RIGS_JSON_OVERRIDE="$TMP/norigs.json" run_check); RC=$?
eq "$RC" "1" "a rig listing with no paths warns"

OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a store that cannot be listed warns"
has "$OUT" "NOT checked" "the warning says that store was skipped, not that it was clean"

OUT=$(BD_EMPTY_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a store whose listing returns no output at all warns"

# A store that answers with garbage is not a store with no findings.
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"
rm -f "$TMP/stores/alpha.json"

# --- 10. An ERROR outranks a WARNING ----------------------------------------
# A run that both finds a strand and fails to read a store must exit 2: the
# strand it DID find is the actionable half, and demoting it to a warning
# would bury the finding this check exists to surface.
store beta "$(bead b-1 pack.polecat)"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "2" "a finding plus an unreadable store still exits ERROR"
has "$OUT" "b-1" "the finding survives alongside the warning"
has "$OUT" "NOT checked" "the unreadable store is still reported"
rm -f "$TMP/stores/beta.json"

# --- 11. Pins against the live pack -----------------------------------------
# The `human` allowlist is only justified while the pack actually writes that
# route. If it stops, the exemption is dead weight hiding a real class of
# unclaimable beads and should be revisited here, not discovered in the field.
if grep -q "'\[\"human\"\]'" "$CHECK"; then
    ok "the sentinel allowlist still exempts \"human\""
else
    bad "the sentinel allowlist no longer exempts \"human\""
fi
if grep -rqF 'gc.routed_to=human' "$ROOT/template-fragments" "$ROOT/formulas" 2>/dev/null; then
    ok "the pack still writes gc.routed_to=human, so the exemption is still earned"
else
    bad "nothing in the pack writes gc.routed_to=human — the sentinel exemption is now unjustified"
fi

echo
echo "check-routed-work-claimable: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
