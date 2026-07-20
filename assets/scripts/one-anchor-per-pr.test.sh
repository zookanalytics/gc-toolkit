#!/usr/bin/env bash
# Hermetic test for the one-anchor-per-PR rework hand-back arm (tk-ynz4b,
# formulas/mol-refinery-patrol.toml merge-push step 4).
#
# The defect: a rework child processed through the mr flow was stamped
# merge_result=pull_request like a first handoff, becoming a SECOND gating
# anchor for the same PR. Because merge-skill.sh validates each anchor
# independently, the PR's effective gate became its WEAKEST anchor — the
# rework anchor carried no check_set, so a CLEAN PR merged with the real
# anchor's codex gate red. And because the in-flight-rework hold excludes
# merge_result-carrying beads, the rework bead's openness held nothing.
#
# The fix under test: before dispatching the signoff and transitioning to a
# gating sub-state, merge-push resolves whether the branch ALREADY has an open
# gating anchor (merge_result=pull_request or pre_open_gate on the same
# branch). If so, the hand-back is a rework: the review anchors to the
# EXISTING anchor and $WORK closes as landed-on-branch — never minting a
# second anchor. (merge-skill.sh independently HOLDS any PR claimed by >1 open
# anchor — legacy pairs — covered by merge-skill.test.sh case 12.)
#
# This EXECUTES the real resolve snippet extracted verbatim from the formula
# (between the one-anchor-per-pr-resolve markers) against a fake `gc`, so it
# cannot drift from the shipped instruction, plus static guards on the
# terminal arm's shape. No live city, Dolt, network, or PRs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: the anchor lookup the resolve snippet performs. -----------------
# `gc bd list --status=open --metadata-field merge_result=<v> --metadata-field
# branch=<b> --limit=N --json` filtered against a fixture of
#   id|merge_result|branch|created
# rows (open beads). Everything else exits 0 with no output.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] && [ "$2" = "list" ] || exit 0
mr=""; br=""
for a in "$@"; do
  case "$a" in
    merge_result=*) mr="${a#merge_result=}" ;;
    branch=*)       br="${a#branch=}" ;;
  esac
done
out=""
while IFS='|' read -r id rmr rbr created; do
  [ -n "$id" ] || continue
  [ "$rmr" = "$mr" ] || continue
  [ "$rbr" = "$br" ] || continue
  obj=$(printf '{"id":"%s","created":"%s","metadata":{"merge_result":"%s","branch":"%s"}}' \
    "$id" "$created" "$rmr" "$rbr")
  if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
done < "$FAKE_ANCHORS"
printf '[%s]\n' "$out"
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors"

# --- Extract the REAL resolve snippet from the formula. -----------------------
SNIPPET="$(awk '
  /# >>> one-anchor-per-pr-resolve/ {f=1; next}
  /# <<< one-anchor-per-pr-resolve/ {f=0}
  f' "$TOML")"

[ -n "$SNIPPET" ] \
  && ok "resolve snippet extracted between one-anchor-per-pr-resolve markers" \
  || bad "resolve snippet extraction EMPTY — markers missing from $TOML"

{ printf '%s\n' "$SNIPPET"; printf 'printf "%%s|%%s\\n" "$EXISTING_ANCHOR" "$GATING_ANCHOR"\n'; } > "$TMP/run.sh"

# resolve <work> <branch> -> echo "EXISTING_ANCHOR|GATING_ANCHOR"
resolve() {
  WORK="$1" BRANCH="$2" bash "$TMP/run.sh" 2>/dev/null | tail -1
}

# (1) First handoff: no other anchor on the branch -> no existing anchor, the
#     gating anchor is $WORK itself (unchanged behavior).
: > "$FAKE_ANCHORS"
eq "$(resolve work-1 polecat/work-1)" "|work-1" \
   "(1) first handoff -> no existing anchor, GATING_ANCHOR=\$WORK"

# (2) Rework hand-back, post-open: an open pull_request anchor holds the same
#     branch -> resolved as the gating anchor.
cat > "$FAKE_ANCHORS" <<'A'
anchor-po|pull_request|polecat/parent|2026-07-01T00:00:00Z
other|pull_request|polecat/other|2026-07-01T00:00:00Z
A
eq "$(resolve rework-1 polecat/parent)" "anchor-po|anchor-po" \
   "(2) post-open anchor on same branch -> resolved as gating anchor"

# (3) Rework hand-back, pre-open: the anchor is parked in pre_open_gate (no PR
#     yet) -> found by the second lookup; the rework must not mint a second
#     pre-open anchor either.
cat > "$FAKE_ANCHORS" <<'A'
anchor-pre|pre_open_gate|polecat/parent|2026-07-01T00:00:00Z
A
eq "$(resolve rework-1 polecat/parent)" "anchor-pre|anchor-pre" \
   "(3) pre_open_gate anchor on same branch -> resolved as gating anchor"

# (4) Self-exclusion: the only row on the branch is $WORK itself (an idempotent
#     re-run inspecting its own stamped state) -> NOT its own existing anchor.
cat > "$FAKE_ANCHORS" <<'A'
work-1|pull_request|polecat/work-1|2026-07-01T00:00:00Z
A
eq "$(resolve work-1 polecat/work-1)" "|work-1" \
   "(4) \$WORK's own row is excluded -> no existing anchor"

# (5) Legacy double-anchor on the branch: deterministic pick — the OLDEST row
#     (the original anchor predates any rework-minted duplicate).
cat > "$FAKE_ANCHORS" <<'A'
dup-newer|pull_request|polecat/parent|2026-07-15T00:00:00Z
anchor-orig|pull_request|polecat/parent|2026-07-01T00:00:00Z
A
eq "$(resolve rework-2 polecat/parent)" "anchor-orig|anchor-orig" \
   "(5) two candidates -> oldest (original) anchor wins deterministically"

# --- Static guards: the terminal arm's shape in the formula. ------------------
# Extract the rework arm: from the terminal marker's `if [ -n "$EXISTING_ANCHOR"`
# up to its `elif` (the pre-open arm). It must close $WORK as landed-on-branch
# and must NOT stamp merge_result (that is the whole point — a rework child
# never enters the anchor class).
REWORK_ARM="$(awk '
  /# >>> one-anchor-per-pr-terminal/ {f=1}
  /# <<< one-anchor-per-pr-terminal/ {f=0}
  f && /^elif / {f=0}
  f' "$TOML")"
[ -n "$REWORK_ARM" ] \
  && ok "(6) terminal rework arm extracted between one-anchor-per-pr-terminal markers" \
  || bad "(6) terminal rework arm extraction EMPTY — markers missing from $TOML"
printf '%s' "$REWORK_ARM" | grep -q 'gc bd close "\$WORK"' \
  && ok "(7) rework arm closes \$WORK (landed-on-branch terminal)" \
  || bad "(7) rework arm must close \$WORK"
printf '%s' "$REWORK_ARM" | grep -q 'merge_result=' \
  && bad "(8) rework arm must NOT stamp merge_result (would mint a second anchor)" \
  || ok "(8) rework arm stamps no merge_result — \$WORK never enters the anchor class"

# The signoff must link to the RESOLVED anchor, not unconditionally to $WORK:
# the dispatch stamps anchor_bead from GATING_ANCHOR and the gate-dep BLOCKS it.
grep -q -- '--set-metadata anchor_bead="\$GATING_ANCHOR"' "$TOML" \
  && ok "(9) review dispatch stamps anchor_bead from the resolved GATING_ANCHOR" \
  || bad "(9) review dispatch must stamp anchor_bead=\"\$GATING_ANCHOR\""
grep -q -- '--blocks "\$GATING_ANCHOR"' "$TOML" \
  && ok "(10) review gate-dep BLOCKS the resolved GATING_ANCHOR" \
  || bad "(10) review gate-dep must block \"\$GATING_ANCHOR\""

# The gating transitions (both sub-states) must sit INSIDE the terminal markers,
# downstream of the rework arm, so a rework hand-back can never reach them.
T_START=$(grep -n '# >>> one-anchor-per-pr-terminal' "$TOML" | head -1 | cut -d: -f1)
T_END=$(grep -n '# <<< one-anchor-per-pr-terminal' "$TOML" | head -1 | cut -d: -f1)
PREOPEN_LINE=$(grep -n -- '--set-metadata merge_result=pre_open_gate' "$TOML" | head -1 | cut -d: -f1)
POSTOPEN_LINE=$(grep -n -- '--set-metadata merge_result=pull_request' "$TOML" | head -1 | cut -d: -f1)
{ [ -n "$T_START" ] && [ -n "$T_END" ] && [ -n "$PREOPEN_LINE" ] && [ -n "$POSTOPEN_LINE" ] \
  && [ "$PREOPEN_LINE" -gt "$T_START" ] && [ "$PREOPEN_LINE" -lt "$T_END" ] \
  && [ "$POSTOPEN_LINE" -gt "$T_START" ] && [ "$POSTOPEN_LINE" -lt "$T_END" ]; } \
  && ok "(11) both gating transitions sit inside the terminal arm (rework path bypasses them)" \
  || bad "(11) gating transitions must sit inside the one-anchor-per-pr-terminal markers (got start=$T_START end=$T_END pre=$PREOPEN_LINE post=$POSTOPEN_LINE)"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
