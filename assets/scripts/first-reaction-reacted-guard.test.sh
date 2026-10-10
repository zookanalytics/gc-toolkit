#!/usr/bin/env bash
# Hermetic test for mol-first-reaction.toml's two reacted checks: the
# first-reaction step's check before it writes a card, and the advance-and-drain
# guard that drains a re-offered step whose reaction has already landed.
#
# Both read gc.proactive_reaction. The release writes it with
# `--set-metadata gc.proactive_reaction=1`, which bd stores as the JSON number 1,
# and the store also holds the string "1". A check that matches only one form
# reads a landed reaction as unreacted, and the advance-and-drain guard then
# lets a re-offered step run an exit again; on a ruling or recommend exit that
# files a duplicate visit. So each block is extracted between its markers and
# RUN, once per stored form. The number form is written through the harness's
# gc stub, which stores a --set-metadata value with bd's typing
# (test-harness.test.sh pins that model), so the fixture is the write the
# release performs rather than a hand-typed value.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FORMULA="$ROOT/formulas/mol-first-reaction.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-fr-reacted-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# The canonical copies, placeholders bound. awk directly: the blocks are
# executed, so nothing but the marked lines may ride into them.
block() { # <marker> <out-file>
  awk -v m="$1" '$0 ~ "# >>> " m "$" {f = 1; next} $0 ~ "# <<< " m "$" {f = 0} f' "$FORMULA" \
    | sed 's/{{convoy_id}}/conv-sub/g' > "$2"
}
block first-reaction-reacted-check "$TMP/check.sh"
block advance-and-drain-reacted-guard "$TMP/guard.sh"
grep -q 'gc.proactive_reaction' "$TMP/check.sh" && ok "first-reaction-reacted-check extracted" \
  || bad "could not extract first-reaction-reacted-check from $FORMULA"
grep -q 'gc.proactive_reaction' "$TMP/guard.sh" && ok "advance-and-drain-reacted-guard extracted" \
  || bad "could not extract advance-and-drain-reacted-guard from $FORMULA"

# The blocks also call `gc convoy status` and `gc runtime drain-ack`, which the
# harness stub does not serve; this shim answers those two and hands every
# `gc bd` call to the harness stub. step-close.sh is a logging stub found through
# GC_PACK_DIR, the first place the guard looks.
mkdir -p "$TMP/shim" "$TMP/pack/assets/scripts" "$TMP/cwd"
export CALLS="$TMP/calls"
cat > "$TMP/shim/gc" <<SHIM
#!/usr/bin/env bash
case "\$1 \${2:-}" in
  "convoy status")     printf '{"children":[{"id":"tk-sub"}]}\n' ;;
  "runtime drain-ack") printf 'DRAIN-ACK\n' >> "\$CALLS" ;;
  *)                   exec "$TMP/bin/gc" "\$@" ;;
esac
SHIM
cat > "$TMP/pack/assets/scripts/step-close.sh" <<'SC'
#!/usr/bin/env bash
printf 'STEP-CLOSE %s\n' "$*" >> "$CALLS"
SC
chmod +x "$TMP/shim/gc" "$TMP/pack/assets/scripts/step-close.sh"

run_block() { # <block-file> -> OUT, RC, CALLED
  : > "$CALLS"; RC=0
  OUT="$(cd "$TMP/cwd" && PATH="$TMP/shim:$PATH" GC_PACK_DIR="$TMP/pack" bash "$1" 2>&1)" || RC=$?
  CALLED="$(cat "$CALLS")"
}
subject() { store "[{\"id\":\"tk-sub\",\"status\":\"open\",\"assignee\":\"\",\"title\":\"s\",\"notes\":\"\",\"metadata\":$1}]"; }
stamp_type() { jq -r '.[] | select(.id == "tk-sub") | .metadata["gc.proactive_reaction"] | type' "$STUB_STORE"; }

echo "# advance-and-drain: a landed reaction drains before any exit"
subject '{}'
gc bd update tk-sub --set-metadata gc.proactive_reaction=1 >/dev/null
eq "$(stamp_type)" "number" "(NUMBER) the release's write stores gc.proactive_reaction as the number 1"
run_block "$TMP/guard.sh"
eq "$RC" "0" "(NUMBER) the guard exits 0"
has "$OUT" "ALREADY REACTED" "(NUMBER) a landed reaction stored as a number is read as landed"
has "$CALLED" "STEP-CLOSE --step mol-first-reaction.advance-and-drain --outcome pass" "(NUMBER) …and the step is closed"
has "$CALLED" "DRAIN-ACK" "(NUMBER) …and the session drains, so no exit block runs"

subject '{"gc.proactive_reaction":"1"}'
eq "$(stamp_type)" "string" "(STRING) the store also holds the stamp as the string \"1\""
run_block "$TMP/guard.sh"
eq "$RC" "0" "(STRING) the guard exits 0"
has "$OUT" "ALREADY REACTED" "(STRING) a landed reaction stored as a string is read as landed"
has "$CALLED" "STEP-CLOSE --step mol-first-reaction.advance-and-drain --outcome pass" "(STRING) …and the step is closed"
has "$CALLED" "DRAIN-ACK" "(STRING) …and the session drains"

echo "# advance-and-drain: an unlanded reaction falls through to the exit blocks"
subject '{}'
run_block "$TMP/guard.sh"
eq "$RC" "0" "(UNREACTED) the guard exits 0 without draining"
hasnt "$OUT" "ALREADY REACTED" "(UNREACTED) a bead with no stamp is not read as landed"
eq "$CALLED" "" "(UNREACTED) …and nothing is closed or drained"

# The dispose writes gc.first_reaction before it acts, so a record without the
# release stamp is a partial: the act did not land, and first-reaction-dispose.sh
# resumes it. The guard keys on the release stamp alone, so a partial runs its exit.
subject '{"gc.first_reaction":"ruling"}'
run_block "$TMP/guard.sh"
hasnt "$OUT" "ALREADY REACTED" "(PARTIAL) a record without the release stamp is not read as landed"
eq "$CALLED" "" "(PARTIAL) …so the exit is re-attempted rather than drained"

subject '{"gc.proactive_reaction":""}'
run_block "$TMP/guard.sh"
hasnt "$OUT" "ALREADY REACTED" "(EMPTY) an emptied stamp is not read as landed"

echo "# first-reaction: a completed reaction writes no second card"
subject '{}'
gc bd update tk-sub --set-metadata gc.proactive_reaction=1 >/dev/null
run_block "$TMP/check.sh"
has "$OUT" "ALREADY REACTED" "(NUMBER) the release stamp stored as a number is read as reacted"
subject '{"gc.proactive_reaction":"1"}'
run_block "$TMP/check.sh"
has "$OUT" "ALREADY REACTED" "(STRING) the release stamp stored as a string is read as reacted"
subject '{"gc.first_reaction":"actionable"}'
run_block "$TMP/check.sh"
has "$OUT" "ALREADY REACTED" "(RECORD) a first-reaction record alone is read as reacted here"
subject '{}'
run_block "$TMP/check.sh"
eq "$RC" "0" "(UNREACTED) the check exits 0"
hasnt "$OUT" "ALREADY REACTED" "(UNREACTED) a bead with neither marker is not read as reacted"

echo
echo "first-reaction reacted guards: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
