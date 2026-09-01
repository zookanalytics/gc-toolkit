#!/usr/bin/env bash
# Hermetic test for the one-anchor-per-PR rework hand-back arm (tk-ynz4b,
# formulas/mol-refinery-patrol.toml merge-push step 4).
#
# The defect: a rework child processed through the mr flow was stamped
# merge_result=pull_request like a first handoff, becoming a SECOND gating
# anchor for the same PR. Because merge.sh validates each anchor
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
# second anchor. (merge.sh independently HOLDS any PR claimed by >1 open
# anchor; doctor/check-one-anchor-per-pr asserts it structurally.)
#
# This EXECUTES the real resolve snippet extracted verbatim from the formula
# (between the one-anchor-per-pr-resolve markers) against a fake `gc`, so it
# cannot drift from the shipped instruction, plus static guards on the
# terminal arm's shape. No live city, Dolt, network, or PRs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-one-anchor-per-pr-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: the anchor lookup the resolve snippet performs. -----------------
# `gc bd list --status=open --metadata-field branch=<b> --limit=0 --json`
# filtered against a fixture of
#   id|merge_result|branch|created_at
# rows (open beads). `gc bd update` and `gc bd close` append to $GCLOG when it
# is set. Everything else exits 0 with no output.
#
# The stub honours EVERY --metadata-field it is given, the way bd does: the
# shipped lookup filters on branch alone and applies the anchor half in its own
# jq, but a lookup that also narrowed on `merge_result=<state>` must still see
# only that state here — otherwise a resolver that walks past a parked anchor
# reads as if it found one. An empty merge_result column emits a row with NO
# merge_result key, which is how a plain sibling child is represented.
#
# The emitted row shape mirrors REAL `gc bd list --json`: the creation timestamp
# is `created_at`, and there is NO `created` key. Emitting `created` here is what
# let the shipped resolver's `sort_by(.created // .id)` pass while silently
# falling back to id order against live beads. An empty timestamp column omits
# the key entirely (exercises the last-resort `.id` tiebreak).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1" = "bd" ] && { [ "$2" = "update" ] || [ "$2" = "close" ]; }; then
  [ -n "${GCLOG:-}" ] && printf '%s\n' "$*" >> "$GCLOG"
  # GCUPDRC drives a refused write. The stub models NO ownership check of its
  # own: bd's lives on the `close` verb, and a stub that either enforced or
  # waived it would be answering the question (7b) and (10b2) ask of the
  # shipped text and the emitted command instead.
  case " $* " in *" --status=closed "*) exit "${GCUPDRC:-0}" ;; esac
  exit 0
fi
[ "$1" = "bd" ] && [ "$2" = "list" ] || exit 0
br=""; mr=""; mr_given=0
for a in "$@"; do
  case "$a" in
    branch=*)       br="${a#branch=}" ;;
    merge_result=*) mr="${a#merge_result=}"; mr_given=1 ;;
  esac
done
out=""
while IFS='|' read -r id rmr rbr created_at; do
  [ -n "$id" ] || continue
  [ "$rbr" = "$br" ] || continue
  [ "$mr_given" = 0 ] || [ "$rmr" = "$mr" ] || continue
  if [ -n "$created_at" ]; then
    ts=$(printf '"created_at":"%s",' "$created_at")
  else
    ts=""
  fi
  if [ -n "$rmr" ]; then
    meta=$(printf '{"merge_result":"%s","branch":"%s"}' "$rmr" "$rbr")
  else
    meta=$(printf '{"branch":"%s"}' "$rbr")
  fi
  obj=$(printf '{"id":"%s",%s"metadata":%s}' "$id" "$ts" "$meta")
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

# (3b) The anchor is parked in a HUMAN state — signoff caps its rework rounds
#      and routes it to a person — so it is in neither gating sub-state. It
#      still carries a merge_result, still owns the PR, and doctor still counts
#      it as an open anchor. A lookup restricted to pull_request/pre_open_gate
#      walks straight past it and stamps the child as a second anchor for the
#      same PR.
for HUMAN_STATE in blocked held abandoned retargeted refused_false_completion; do
  printf 'anchor-h|%s|polecat/parent|2026-07-01T00:00:00Z\n' "$HUMAN_STATE" > "$FAKE_ANCHORS"
  eq "$(resolve rework-1 polecat/parent)" "anchor-h|anchor-h" \
     "(3b) anchor parked in '$HUMAN_STATE' is still the gating anchor"
done

# (3c) The other half of the predicate: carrying a merge_result is what makes a
#      row an anchor. A sibling child on the same branch has none, so a
#      branch-only lookup must not elect it — that would close a first handoff
#      as if it were a rework of its own sibling.
cat > "$FAKE_ANCHORS" <<'A'
sibling-child||polecat/parent|2026-07-01T00:00:00Z
A
eq "$(resolve work-1 polecat/parent)" "|work-1" \
   "(3c) a sibling carrying no merge_result is not an anchor"

# (3d) An unrecorded branch must not run the lookup at all: `--metadata-field
#      branch=` with an empty value matches every bead that records no branch,
#      and electing one of those hands the merge to a stranger's anchor.
cat > "$FAKE_ANCHORS" <<'A'
tk-elsewhere|pull_request||2026-07-01T00:00:00Z
A
eq "$(resolve work-1 '')" "|work-1" \
   "(3d) empty BRANCH resolves to no anchor rather than matching branchless beads"

# (4) Self-exclusion: the only row on the branch is $WORK itself (an idempotent
#     re-run inspecting its own stamped state) -> NOT its own existing anchor.
cat > "$FAKE_ANCHORS" <<'A'
work-1|pull_request|polecat/work-1|2026-07-01T00:00:00Z
A
eq "$(resolve work-1 polecat/work-1)" "|work-1" \
   "(4) \$WORK's own row is excluded -> no existing anchor"

# (5) Legacy double-anchor on the branch: deterministic pick — the OLDEST row
#     (the original anchor predates any rework-minted duplicate).
#
#     The fixture is adversarial to the two ways this can silently degrade, so
#     the assertion actually tests the sort key rather than luck:
#       - id ordering  — the newer duplicate's id sorts FIRST lexicographically,
#         so a resolver reading a non-existent timestamp field (the tk-52mrh
#         defect: `.created` on a row that only has `created_at`) collapses to
#         `.id` and elects the gateless duplicate;
#       - no ordering  — the newer duplicate is also the FIRST input row, so a
#         missing/stable-no-op sort picks it too.
#     Only sorting on the real `created_at` yields tk-zzzz9.
cat > "$FAKE_ANCHORS" <<'A'
tk-aaaa1|pull_request|polecat/parent|2026-07-15T00:00:00Z
tk-zzzz9|pull_request|polecat/parent|2026-07-01T00:00:00Z
A
eq "$(resolve rework-2 polecat/parent)" "tk-zzzz9|tk-zzzz9" \
   "(5) two candidates -> oldest (original) anchor wins on created_at, not id order"

# (5b) Timestamps absent entirely (defensive): the resolver must still be
#      DETERMINISTIC rather than input-order-dependent, falling back to id.
cat > "$FAKE_ANCHORS" <<'A'
tk-zzzz9|pull_request|polecat/parent|
tk-aaaa1|pull_request|polecat/parent|
A
eq "$(resolve rework-2 polecat/parent)" "tk-aaaa1|tk-aaaa1" \
   "(5b) no created_at on any row -> deterministic \$WORK-independent id tiebreak"

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
grep -q 'gc bd update "\$WORK" --status=closed' <<< "$REWORK_ARM" \
  && ok "(7) rework arm closes \$WORK (landed-on-branch terminal)" \
  || bad "(7) rework arm must close \$WORK"
# The VERB is the assertion. bd's ownership check is a property of `bd close`:
# it compares the actor to the assignee and refuses a bead held by another
# principal. Every bead the refinery closes is one someone handed it, and the
# refusal is per-anchor and permanent, so a retry meets it unchanged every pass.
# `bd update --status=closed` reaches the same status carrying no such check.
# Neither this suite's stub nor the shared harness models an acting identity, so
# a stub can answer this question in either direction and prove nothing —
# the shipped text and the emitted command (10b, 10b2) are what pin it.
grep -q 'gc bd close' <<< "$REWORK_ARM" \
  && bad "(7b) rework arm must not close through 'gc bd close' — that verb carries bd's ownership check, which refuses a bead assigned to another principal" \
  || ok "(7b) rework arm closes through 'bd update --status=closed', past the close-verb ownership check"
grep -q 'merge_result=' <<< "$REWORK_ARM" \
  && bad "(8) rework arm must NOT stamp merge_result (would mint a second anchor)" \
  || ok "(8) rework arm stamps no merge_result — \$WORK never enters the anchor class"

# --- Executable pin: the terminal arm never stamps an unaddressable PR. -------
# An empty pr_url/pr_number on a pull_request anchor is skipped by merge.sh and
# pr-facts.sh forever; the arm must fall back to pre_open_gate (pr-open.sh then
# adopts the recorded PR and stamps real coordinates).
TERMINAL="$(awk '/# >>> one-anchor-per-pr-terminal/{f=1;next} /# <<< one-anchor-per-pr-terminal/{f=0} f' "$TOML")"
[ -n "$TERMINAL" ] \
  && ok "(9a) terminal snippet extracted for execution" \
  || bad "(9a) terminal snippet extraction EMPTY"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/git"
chmod +x "$TMP/bin/git"
export LCLOG="$TMP/lc.log"
cat > "$TMP/bin/lc-stub" <<'L'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${LCLOG:?}"
exit "${LCRC:-0}"
L
chmod +x "$TMP/bin/lc-stub"
printf '%s\n' "$TERMINAL" > "$TMP/terminal.sh"
run_terminal() { # <pre_open> <pr_url> <pr_number>
  : > "$LCLOG"
  EXISTING_ANCHOR="" WORK=w1 BRANCH=polecat/w1 TARGET=main CHECK_SET=codex \
    LC="$TMP/bin/lc-stub" PRE_OPEN="$1" PR_URL="$2" PR_NUMBER="$3" \
    bash "$TMP/terminal.sh" >/dev/null 2>&1
  cat "$LCLOG"
}
lc_out=$(run_terminal 0 "https://github.com/o/r/pull/7" 7)
case "$lc_out" in
  *"--to pull_request"*"pr_url=https://github.com/o/r/pull/7"*) ok "(9b) resolved PR coordinates transition to pull_request" ;;
  *) bad "(9b) resolved PR coordinates must transition to pull_request (got: $lc_out)" ;;
esac
lc_out=$(run_terminal 0 "" "")
case "$lc_out" in
  *"--to pull_request"*) bad "(9c) unresolved PR coordinates must NEVER stamp pull_request (got: $lc_out)" ;;
  *"--to pre_open_gate"*) ok "(9c) unresolved PR coordinates fall back to pre_open_gate (pr-open adopts the PR)" ;;
  *) bad "(9c) expected a pre_open_gate fallback transition (got: $lc_out)" ;;
esac

# --- The rework hand-back's exit from the anchor class. -----------------------
# THE INVARIANT (doctor/check-one-anchor-per-pr, I4): after a child's submit is
# processed, exactly ONE open bead on that metadata.branch carries a non-empty
# merge_result — the anchor. The child gets there by leaving through
# lifecycle.sh: `--to unanchored` unsets merge_result on any state it inherited,
# and `unanchored -> unanchored` is a legal self-edge, so the normal child (which
# never had one) takes the same path. Closing while still carrying one is an I5
# error (doctor/check-closed-implies-landed), which is why the close is
# conditional on the transition.
run_rework() { # <lc-rc> -> "<lifecycle calls>#<gc bd calls>"
  : > "$LCLOG"; : > "$TMP/gc.log"
  EXISTING_ANCHOR=anchor-po WORK=w1 BRANCH=polecat/parent TARGET=main CHECK_SET=codex \
    LC="$TMP/bin/lc-stub" PRE_OPEN=0 PR_URL="" PR_NUMBER="" \
    LCRC="$1" GCLOG="$TMP/gc.log" \
    bash "$TMP/terminal.sh" >/dev/null 2>&1
  printf '%s#%s' "$(tr '\n' ';' < "$LCLOG")" "$(tr '\n' ';' < "$TMP/gc.log")"
}

REWORK_OK="$(run_rework 0)"
case "$REWORK_OK" in
  *"transition w1 --to unanchored --unset rejection_reason"*)
    ok "(10a) the child leaves the anchor class through lifecycle.sh before it closes" ;;
  *) bad "(10a) expected a --to unanchored transition on the child (got: $REWORK_OK)" ;;
esac
case "$REWORK_OK" in
  *"#"*"update w1 --status=closed"*) ok "(10b) the child then closes landed-on-branch" ;;
  *) bad "(10b) the child must close after the transition (got: $REWORK_OK)" ;;
esac
# The mirror of (7b), on the command actually emitted rather than on the source:
# `bd close` must not appear for ANY bead this arm touches.
case "$REWORK_OK" in
  *"bd close "*) bad "(10b2) the arm emitted 'bd close', which bd refuses on a bead assigned to another principal (got: $REWORK_OK)" ;;
  *)             ok "(10b2) no 'bd close' is emitted — the close cannot meet the close-verb ownership check" ;;
esac
# A refused close is reported, not swallowed. The transition already landed, so
# the child sits unanchored, open and assigned — the shape that reads as work
# still in flight, and the one a silent close leaves behind every pass.
: > "$LCLOG"; : > "$TMP/gc.log"
refused_out=$(EXISTING_ANCHOR=anchor-po WORK=w1 BRANCH=polecat/parent TARGET=main CHECK_SET=codex \
  LC="$TMP/bin/lc-stub" PRE_OPEN=0 PR_URL="" PR_NUMBER="" LCRC=0 \
  GCLOG="$TMP/gc.log" GCUPDRC=1 bash "$TMP/terminal.sh" 2>&1 >/dev/null)
case "$refused_out" in
  *"did not close"*|*"close was refused"*) ok "(10b3) a refused close is reported" ;;
  *) bad "(10b3) a refused close must be reported (got: '$refused_out')" ;;
esac
# The anchor keeps its own state: the arm annotates it and transitions nothing.
case "$REWORK_OK" in
  *"transition anchor-po"*) bad "(10c) the arm must not transition the existing anchor (got: $REWORK_OK)" ;;
  *)                        ok "(10c) the existing anchor is annotated, never transitioned" ;;
esac
# The whole point: the child never joins the anchor class, so the branch still
# has exactly the one anchor it had before.
case "$REWORK_OK" in
  *"--to pull_request"*|*"--to pre_open_gate"*)
    bad "(10d) the rework arm must stamp no gating state on the child (got: $REWORK_OK)" ;;
  *) ok "(10d) branch keeps one anchor: the child is stamped into no gating state" ;;
esac

# A refused transition must NOT close. A child closed still carrying an
# inherited merge_result is invisible to merge.sh and reads as an anchor that
# left the queue without landing; leaving it open lets the next pass retry.
REWORK_REFUSED="$(run_rework 1)"
case "$REWORK_REFUSED" in
  *"#"*"w1 --status=closed"*|*"#"*"close w1"*)
    bad "(10e) a refused transition must not close the child (got: $REWORK_REFUSED)" ;;
  *) ok "(10e) a refused transition leaves the child open for the next pass" ;;
esac

# Review dispatch moved to the cadence's gate-ensure; the formula's remaining
# duty is that the transitions land on the right bead, checked below.

# The gating transitions (both sub-states, written through lifecycle.sh) must
# sit INSIDE the terminal markers, downstream of the rework arm, so a rework
# hand-back can never reach them.
T_START=$(grep -n '# >>> one-anchor-per-pr-terminal' "$TOML" | head -1 | cut -d: -f1)
T_END=$(grep -n '# <<< one-anchor-per-pr-terminal' "$TOML" | head -1 | cut -d: -f1)
PREOPEN_LINE=$(grep -n -- '--to pre_open_gate' "$TOML" | head -1 | cut -d: -f1)
POSTOPEN_LINE=$(grep -n -- '--to pull_request' "$TOML" | head -1 | cut -d: -f1)
{ [ -n "$T_START" ] && [ -n "$T_END" ] && [ -n "$PREOPEN_LINE" ] && [ -n "$POSTOPEN_LINE" ] \
  && [ "$PREOPEN_LINE" -gt "$T_START" ] && [ "$PREOPEN_LINE" -lt "$T_END" ] \
  && [ "$POSTOPEN_LINE" -gt "$T_START" ] && [ "$POSTOPEN_LINE" -lt "$T_END" ]; } \
  && ok "(11) both gating transitions sit inside the terminal arm (rework path bypasses them)" \
  || bad "(11) gating transitions must sit inside the one-anchor-per-pr-terminal markers (got start=$T_START end=$T_END pre=$PREOPEN_LINE post=$POSTOPEN_LINE)"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
