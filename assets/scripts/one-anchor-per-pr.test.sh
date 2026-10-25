#!/usr/bin/env bash
# Hermetic test for the one-anchor-per-PR rework hand-back arm
# (formulas/mol-refinery-patrol.toml merge-push step 4).
#
# The defect: a rework child processed through the mr flow was stamped
# merge_result=pull_request like a first handoff, becoming a SECOND gating
# anchor for the same PR. Because merge.sh validates each anchor
# independently, the PR's effective gate became its WEAKEST anchor — the
# rework anchor carried no check_set, so a CLEAN PR merged with the real
# anchor's correctness check red. And because the in-flight-rework hold excludes
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
#   id|merge_result|branch|created_at[|anchor_bead[|issue_type]]
# rows (open beads). A non-empty anchor_bead column lands in the row's
# metadata, and a non-empty issue_type column is the row's issue_type, as a
# convoy's row carries it. `gc bd update` and `gc bd close` append to $GCLOG
# when it is set, and `gc runtime drain-ack` appends to $DRAINLOG. Everything
# else exits 0 with no output.
#
# $FAKE_LIST_RC is the listing's exit status, and $FAKE_LIST_RAW, when set,
# replaces the fixture's array with its own text, so a read can fail while it
# prints a whole array, print [] as it fails, or print what is no array at all.
# `gc bd show <id> --json` answers from $FAKE_SHOW's id|issue_type|status
# lines, a bead's own row wherever it is open, and a bead absent there gets
# bd's own answer for a missing id: an error object and exit 1.
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
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
if [ "$1" = "bd" ] && { [ "$2" = "update" ] || [ "$2" = "close" ]; }; then
  [ -n "${GCLOG:-}" ] && printf '%s\n' "$*" >> "$GCLOG"
  # GCUPDRC drives a refused write. The stub models NO ownership check of its
  # own: bd's lives on the `close` verb, and a stub that either enforced or
  # waived it would be answering the question (7b) and (10b2) ask of the
  # shipped text and the emitted command instead.
  case " $* " in *" --status=closed "*) exit "${GCUPDRC:-0}" ;; esac
  exit 0
fi
if [ "$1" = "runtime" ] && [ "$2" = "drain-ack" ]; then
  [ -n "${DRAINLOG:-}" ] && printf 'drain-ack\n' >> "$DRAINLOG"
  exit 0
fi
if [ "$1" = "bd" ] && [ "$2" = "show" ]; then
  while IFS='|' read -r sid stype sstatus; do
    [ "$sid" = "$3" ] || continue
    printf '[{"id":"%s","issue_type":"%s","status":"%s"}]\n' "$sid" "$stype" "$sstatus"
    exit 0
  done < "${FAKE_SHOW:-/dev/null}"
  printf '{"error":"no issues found matching the provided IDs"}\n'
  exit 1
fi
[ "$1" = "bd" ] && [ "$2" = "list" ] || exit 0
if [ -n "${FAKE_LIST_RAW+set}" ]; then
  printf '%s\n' "$FAKE_LIST_RAW"
  exit "${FAKE_LIST_RC:-0}"
fi
br=""; mr=""; mr_given=0
for a in "$@"; do
  case "$a" in
    branch=*)       br="${a#branch=}" ;;
    merge_result=*) mr="${a#merge_result=}"; mr_given=1 ;;
  esac
done
out=""
while IFS='|' read -r id rmr rbr created_at ranchor rtype; do
  [ -n "$id" ] || continue
  [ "$rbr" = "$br" ] || continue
  [ "$mr_given" = 0 ] || [ "$rmr" = "$mr" ] || continue
  if [ -n "$created_at" ]; then
    ts=$(printf '"created_at":"%s",' "$created_at")
  else
    ts=""
  fi
  [ -z "$rtype" ] || ts=$(printf '%s"issue_type":"%s",' "$ts" "$rtype")
  if [ -n "$rmr" ]; then
    meta=$(printf '{"merge_result":"%s","branch":"%s"' "$rmr" "$rbr")
  else
    meta=$(printf '{"branch":"%s"' "$rbr")
  fi
  if [ -n "$ranchor" ]; then
    meta=$(printf '%s,"anchor_bead":"%s"}' "$meta" "$ranchor")
  else
    meta="$meta}"
  fi
  obj=$(printf '{"id":"%s",%s"metadata":%s}' "$id" "$ts" "$meta")
  if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
done < "$FAKE_ANCHORS"
printf '[%s]\n' "$out"
exit "${FAKE_LIST_RC:-0}"
GC
chmod +x "$TMP/bin/gc"
# escalate.sh beside lifecycle.sh, where merge-push finds it: one line per call
# on $ESCLOG.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/escalate.sh" <<'ESC'
[ -n "${ESCLOG:-}" ] && printf '%s\n' "$*" >> "$ESCLOG"
exit 0
ESC
chmod +x "$TMP/bin/escalate.sh"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors"
export FAKE_SHOW="$TMP/show"
: > "$FAKE_SHOW"

# --- Extract the REAL resolve snippet from the formula. -----------------------
SNIPPET="$(awk '
  /# >>> one-anchor-per-pr-resolve/ {f=1; next}
  /# <<< one-anchor-per-pr-resolve/ {f=0}
  f' "$TOML")"

[ -n "$SNIPPET" ] \
  && ok "resolve snippet extracted between one-anchor-per-pr-resolve markers" \
  || bad "resolve snippet extraction EMPTY — markers missing from $TOML"

{ printf '%s\n' "$SNIPPET"; printf 'printf "%%s|%%s\\n" "$EXISTING_ANCHOR" "$GATING_ANCHOR"\n'; } > "$TMP/run.sh"

# resolve <work> <branch> [bead-json] -> echo "EXISTING_ANCHOR|GATING_ANCHOR"
#   <bead-json> is $WORK's own row, which merge-push reads into $BEAD_JSON.
resolve() {
  WORK="$1" BRANCH="$2" BEAD_JSON="${3:-}" bash "$TMP/run.sh" 2>/dev/null | tail -1
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

# (3b) The anchor is parked in a HUMAN state — routed to a person — so it is
#      in neither gating sub-state. It still carries a merge_result, still
#      owns the PR, and doctor still counts it as an open anchor. A lookup
#      restricted to pull_request/pre_open_gate walks straight past it and
#      stamps the child as a second anchor for the same PR.
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
#         so a resolver reading a non-existent timestamp field (the
#         defect: `.created` on a row that only has `created_at`) collapses to
#         `.id` and elects the checkless duplicate;
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

# (5c) A convoy's rebuild child lands on a bead that carries no merge_result
#      yet: it names the convoy as its anchor_bead, and the convoy is open on
#      the same branch. With no anchor there, the convoy is the bead this
#      landing anchors (LANDS_ON), and it is the gating anchor. The child's role
#      is read from its own row ($BEAD_JSON), never from the listing.
{ printf '%s\n' "$SNIPPET"; printf 'printf "%%s|%%s|%%s\\n" "$EXISTING_ANCHOR" "$GATING_ANCHOR" "$LANDS_ON"\n'; } > "$TMP/run3.sh"
resolve3() { # <work> <branch> [bead-json] -> "EXISTING_ANCHOR|GATING_ANCHOR|LANDS_ON"
  WORK="$1" BRANCH="$2" BEAD_JSON="${3:-}" bash "$TMP/run3.sh" 2>/dev/null | tail -1
}
# held <work> <branch> <bead-json> -> "<rc>|<resolved line>|<drain-acks>|<escalations>"
#   for a resolve that may stop: it then prints no resolved line, drains and
#   exits 1. LC names the lifecycle writer whose directory holds escalate.sh.
held() {
  : > "$TMP/drain.log"; : > "$TMP/esc.log"; local out rc
  if out=$(WORK="$1" BRANCH="$2" BEAD_JSON="${3:-}" LC="$TMP/bin/lc-stub" \
             DRAINLOG="$TMP/drain.log" ESCLOG="$TMP/esc.log" bash "$TMP/run3.sh" 2>/dev/null); then rc=0; else rc=$?; fi
  printf '%s|%s|%s|%s' "$rc" "$(printf '%s\n' "$out" | tail -1)" \
    "$(tr '\n' ';' < "$TMP/drain.log")" "$(tr '\n' ';' < "$TMP/esc.log")"
}
REBUILD_ROW='[{"id":"rebuild-1","metadata":{"task_kind":"rework","anchor_bead":"cv","branch":"integration/cv"}}]'
cat > "$FAKE_ANCHORS" <<'A'
rebuild-1||integration/cv|2026-07-02T00:00:00Z|cv|task
cv||integration/cv|2026-07-01T00:00:00Z||convoy
A
eq "$(resolve3 rebuild-1 integration/cv "$REBUILD_ROW")" "|cv|cv" \
   "(5c) a rebuild child naming its unanchored convoy on its branch lands on it: LANDS_ON=GATING_ANCHOR=cv"
eq "$(resolve rebuild-1 integration/cv "$REBUILD_ROW")" "|cv" \
   "(5c) ...and the two-field reading names it the gating anchor"
# (5d) An anchor that carries a merge_result still wins, and nothing is anchored.
cat > "$FAKE_ANCHORS" <<'A'
rebuild-1||integration/cv|2026-07-02T00:00:00Z|cv|task
cv||integration/cv|2026-07-01T00:00:00Z||convoy
anchor-pre|pre_open_gate|integration/cv|2026-07-03T00:00:00Z|
A
eq "$(resolve3 rebuild-1 integration/cv "$REBUILD_ROW")" "anchor-pre|anchor-pre|" \
   "(5d) a merge_result-carrying anchor on the branch wins; LANDS_ON stays empty"
# (5e) The named convoy must be open on the same branch: one this lookup does
#      not return is never anchored. The child does not anchor itself in its
#      place either, or its merge would close the child and leave the convoy's
#      graduation unanchored. Its landing waits, and a visit on the child asks
#      a person about the convoy.
cat > "$FAKE_ANCHORS" <<'A'
rebuild-1||integration/cv|2026-07-02T00:00:00Z|cv|task
cv||integration/other|2026-07-01T00:00:00Z||convoy
A
printf 'cv|convoy|open\n' > "$FAKE_SHOW"
HELD_E="$(held rebuild-1 integration/cv "$REBUILD_ROW")"
case "$HELD_E" in
  "1||drain-ack;|--subject rebuild-1 --key refinery-rebuild-convoy-not-open --message "*)
    ok "(5e) a named convoy open on another branch is not anchored, the child is not its own anchor, and a visit asks about it" ;;
  *) bad "(5e) a rebuild child whose convoy is open on another branch must stop, drain and escalate once (got: $HELD_E)" ;;
esac
printf 'cv|convoy|closed\n' > "$FAKE_SHOW"
case "$(held rebuild-1 integration/cv "$REBUILD_ROW")" in
  "1||drain-ack;|--subject rebuild-1 --key refinery-rebuild-convoy-not-open "*)
    ok "(5e) a closed named convoy holds the landing the same way" ;;
  *) bad "(5e) a rebuild child whose convoy is closed must stop, drain and escalate once" ;;
esac
# (5e2) A named bead whose own row cannot be read might be a convoy, so the
#       landing waits for the next pass. Nothing is a question for a person yet.
: > "$FAKE_SHOW"
eq "$(held rebuild-1 integration/cv "$REBUILD_ROW")" "1||drain-ack;|" \
   "(5e2) a named bead that cannot be read holds the landing, and files no visit"
# (5e3) A named bead that is not a convoy and not open on the branch leaves
#       $WORK its own anchor, as a first handoff is.
cat > "$FAKE_ANCHORS" <<'A'
rb-1||polecat/a|2026-07-02T00:00:00Z|a|task
A
printf 'a|task|closed\n' > "$FAKE_SHOW"
eq "$(held rb-1 polecat/a '[{"id":"rb-1","metadata":{"task_kind":"rework","anchor_bead":"a"}}]')" "0||rb-1|||" \
   "(5e3) a rework naming a closed bead that is not a convoy is its own gating anchor"
: > "$FAKE_SHOW"
# (5f) A bead $WORK does not name is never elected, whatever it carries: a
#      fresh handoff beside an unanchored convoy anchors itself, as in (3c).
cat > "$FAKE_ANCHORS" <<'A'
work-1||integration/cv|2026-07-02T00:00:00Z||task
cv||integration/cv|2026-07-01T00:00:00Z||convoy
A
eq "$(resolve3 work-1 integration/cv '[{"id":"work-1","metadata":{"branch":"integration/cv"}}]')" "|work-1|" \
   "(5f) a bead \$WORK does not name is never the bead its landing anchors"
# (5g) The role is $WORK's own row's, not the listing's. A listing that leaves
#      $WORK out still lands it, and a listing row naming a convoy does not
#      make a bead whose own row names nothing a rebuild child.
cat > "$FAKE_ANCHORS" <<'A'
cv||integration/cv|2026-07-01T00:00:00Z||convoy
A
eq "$(resolve3 rebuild-1 integration/cv "$REBUILD_ROW")" "|cv|cv" \
   "(5g) a rebuild child the listing leaves out lands on its convoy from its own row"
cat > "$FAKE_ANCHORS" <<'A'
rebuild-1||integration/cv|2026-07-02T00:00:00Z|cv|task
cv||integration/cv|2026-07-01T00:00:00Z||convoy
A
eq "$(resolve3 rebuild-1 integration/cv '[{"id":"rebuild-1","metadata":{"branch":"integration/cv"}}]')" "|rebuild-1|" \
   "(5g) a listing row's anchor_bead does not stand in for \$WORK's own row"
# (5h) Only a convoy's rebuild child anchors the bead it names. A non-convoy
#      anchor A that a rejection unanchored is open on its branch with its own
#      rebuild queued; a review's rework of A landing now must not anchor A, or
#      that rebuild's load-context reads A as finished and the rebuild is lost.
cat > "$FAKE_ANCHORS" <<'A'
rv-1||polecat/a|2026-07-02T00:00:00Z|a|task
rb-1||polecat/a|2026-07-02T00:00:00Z|a|task
a||polecat/a|2026-07-01T00:00:00Z||task
A
eq "$(resolve3 rv-1 polecat/a '[{"id":"rv-1","metadata":{"task_kind":"rework","anchor_bead":"a","source_review_bead":"tk-review"}}]')" "|rv-1|" \
   "(5h) a review's rework never anchors the bead it names"
eq "$(resolve3 rb-1 polecat/a '[{"id":"rb-1","metadata":{"task_kind":"rework","anchor_bead":"a"}}]')" "|rb-1|" \
   "(5h) a rework naming a bead that is not a convoy never anchors it"
cat > "$FAKE_ANCHORS" <<'A'
rv-2||integration/cv|2026-07-02T00:00:00Z|cv|task
ru-1||integration/cv|2026-07-02T00:00:00Z|cv|task
cv||integration/cv|2026-07-01T00:00:00Z||convoy
A
eq "$(resolve3 rv-2 integration/cv '[{"id":"rv-2","metadata":{"task_kind":"rework","anchor_bead":"cv","source_review_bead":"tk-review"}}]')" "|rv-2|" \
   "(5h) a review's rework of a convoy never anchors the convoy"
eq "$(resolve3 ru-1 integration/cv '[{"id":"ru-1","metadata":{"task_kind":"rework","anchor_bead":"cv","source_ruling_bead":"tk-visit"}}]')" "|ru-1|" \
   "(5h) a ruling's rework of a convoy never anchors the convoy"
# (5i) Submit step 4b in mol-polecat-work resolves the summary's anchor with the
#      same block, so a polecat stamps its summary on the bead this landing
#      anchors. One text, held equal here.
lands_block() { awk '/# >>> rebuild-child-lands-on$/ {f=1; next} /# <<< rebuild-child-lands-on$/ {f=0} f' "$1"; }
LANDS_PATROL="$(lands_block "$TOML")"
LANDS_POLECAT="$(lands_block "$ROOT/formulas/mol-polecat-work.toml")"
if [ -n "$LANDS_PATROL" ] && [ "$LANDS_PATROL" = "$LANDS_POLECAT" ]; then
  ok "(5i) merge-push and submit step 4b carry one rebuild-child-lands-on block"
else
  bad "(5i) the rebuild-child-lands-on block differs between the two formulas, or is missing"
fi

# --- Static guards: the terminal arm's shape in the formula. ------------------
# Extract the rework arm: from the terminal marker up to the top-level `else`
# (the first handoff's gating transition). It must close $WORK as
# landed-on-branch and must NOT stamp merge_result (that is the whole point — a
# rework child never enters the anchor class).
REWORK_ARM="$(awk '
  /# >>> one-anchor-per-pr-terminal/ {f=1}
  /# <<< one-anchor-per-pr-terminal/ {f=0}
  f && /^(elif|else)/ {f=0}
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
# Ref-aware git stub for the terminal arm's origin read-back gate. `fetch`
# exits $STUB_FETCH_RC (0 unless set) to model a read-back that fails; `rev-parse`
# of HEAD echoes $STUB_PREPARED_HEAD and of any origin/* ref echoes
# $STUB_REMOTE_HEAD, cut to its first 8 characters under --short — an empty env
# var models an absent ref (empty output). -C <dir> is ignored: the arm's
# PREP_WT is unset under test, so the stub answers from the environment, not a
# real repository. Anything else exits 0 with no output, as the dumb stub did.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<'GIT'
op=""; short=0
for a in "$@"; do
  case "$a" in
    fetch)     exit "${STUB_FETCH_RC:-0}" ;;
    rev-parse) op="rev-parse" ;;
    --short)   short=1 ;;
  esac
done
[ "$op" = "rev-parse" ] || exit 0
for a in "$@"; do
  case "$a" in
    HEAD)     printf '%s\n' "${STUB_PREPARED_HEAD:-}"; exit 0 ;;
    origin/*)
      if [ "$short" = 1 ]; then printf '%.8s\n' "${STUB_REMOTE_HEAD:-}"; else printf '%s\n' "${STUB_REMOTE_HEAD:-}"; fi
      exit 0 ;;
  esac
done
exit 0
GIT
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
  EXISTING_ANCHOR="" WORK=w1 BRANCH=polecat/w1 TARGET=main CHECK_SET=correctness \
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
  # origin holds exactly the prepared head, so the read-back gate passes and the
  # arm proceeds to record + close (10f/10g cover the mismatch).
  EXISTING_ANCHOR=anchor-po WORK=w1 BRANCH=polecat/parent TARGET=main CHECK_SET=correctness \
    LC="$TMP/bin/lc-stub" PRE_OPEN=0 PR_URL="" PR_NUMBER="" \
    LCRC="$1" GCLOG="$TMP/gc.log" \
    STUB_PREPARED_HEAD=cafef00d STUB_REMOTE_HEAD=cafef00d \
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
refused_out=$(EXISTING_ANCHOR=anchor-po WORK=w1 BRANCH=polecat/parent TARGET=main CHECK_SET=correctness \
  LC="$TMP/bin/lc-stub" PRE_OPEN=0 PR_URL="" PR_NUMBER="" LCRC=0 \
  STUB_PREPARED_HEAD=cafef00d STUB_REMOTE_HEAD=cafef00d \
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

# --- The landing is provable against origin, never asserted from local. -------
# The rework hand-back closes landed-on-branch, so the recorded sha must come
# from origin. When origin/$BRANCH does not hold the prepared head — the mr push
# rejected, skipped, or lost — the arm must record NO landing (no anchor note),
# close NOTHING, and exit non-zero, leaving $WORK routed. That is the exact
# false-done the arm exists to prevent: a rework closed as "landed at <sha>" over
# a branch the fix never reached, while origin/$BRANCH still points at the pre-fix
# tip.
run_gate() { # <prepared-head> <remote-head> [fetch-rc] -> "<rc>#<lifecycle>;<gc>"
  : > "$LCLOG"; : > "$TMP/gc.log"; local rc
  if EXISTING_ANCHOR=anchor-po WORK=w1 BRANCH=polecat/parent TARGET=main CHECK_SET=correctness \
       LC="$TMP/bin/lc-stub" PRE_OPEN=0 PR_URL="" PR_NUMBER="" LCRC=0 GCLOG="$TMP/gc.log" \
       STUB_PREPARED_HEAD="$1" STUB_REMOTE_HEAD="$2" STUB_FETCH_RC="${3:-0}" \
       bash "$TMP/terminal.sh" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  printf '%s#%s;%s' "$rc" "$(tr '\n' ';' < "$LCLOG")" "$(tr '\n' ';' < "$TMP/gc.log")"
}

# origin holds a DIFFERENT sha than the prepared head (stale ref: push never landed).
GATE_MISMATCH="$(run_gate deadbeef feedface)"
case "$GATE_MISMATCH" in
  *"transition w1"*|*"update w1 --status=closed"*|*"update anchor-po"*)
    bad "(10f) a mismatched origin recorded a landing or closed the child (got: $GATE_MISMATCH)" ;;
  1#*) ok "(10f) origin != prepared head -> no anchor note, no transition, no close; arm exits non-zero" ;;
  *) bad "(10f) mismatched origin must fail closed non-zero, mutating nothing (got: $GATE_MISMATCH)" ;;
esac

# origin has no such ref at all (branch absent on the remote).
GATE_ABSENT="$(run_gate deadbeef '')"
case "$GATE_ABSENT" in
  *"transition w1"*|*"update w1 --status=closed"*|*"update anchor-po"*)
    bad "(10g) an absent origin ref recorded a landing or closed the child (got: $GATE_ABSENT)" ;;
  1#*) ok "(10g) origin ref absent -> no anchor note, no transition, no close; arm exits non-zero" ;;
  *) bad "(10g) absent origin ref must fail closed non-zero, mutating nothing (got: $GATE_ABSENT)" ;;
esac

# origin holds exactly the prepared head: the landing IS recorded and $WORK
# closes, with the sha read back from the remote tip (not the local prep HEAD).
GATE_MATCH="$(run_gate cafe1234 cafe1234)"
case "$GATE_MATCH" in
  *"transition w1 --to unanchored"*) ok "(10h) origin == prepared head -> the child leaves the anchor class and closes" ;;
  *) bad "(10h) a verified landing must transition the child (got: $GATE_MATCH)" ;;
esac
case "$GATE_MATCH" in
  *"update anchor-po"*"landed on polecat/parent at cafe1234"*) ok "(10i) the anchor note records the sha read back from origin" ;;
  *) bad "(10i) the anchor note must carry the origin-read sha (got: $GATE_MATCH)" ;;
esac

# The read-back fetch can itself fail, leaving origin/$BRANCH at whatever the
# local remote-tracking ref last cached. When that stale value coincides with
# the prepared head, an equality check that trusted it would record a landing
# the fetch never proved. A failed fetch must fail closed regardless of what the
# stale ref says: no anchor note, no transition, no close, non-zero exit.
GATE_FETCH_FAIL="$(run_gate cafef00d cafef00d 42)"
case "$GATE_FETCH_FAIL" in
  *"transition w1"*|*"update w1 --status=closed"*|*"update anchor-po"*)
    bad "(10j) a failed fetch recorded a landing or closed the child off a stale ref (got: $GATE_FETCH_FAIL)" ;;
  1#*) ok "(10j) fetch failure -> no anchor note, no transition, no close; arm exits non-zero even when the stale origin ref equals HEAD" ;;
  *) bad "(10j) a failed fetch must fail closed non-zero, mutating nothing (got: $GATE_FETCH_FAIL)" ;;
esac

# --- A rework child landing on a bead that carries no merge_result yet. -------
# The bead the child names (LANDS_ON) takes the gating transition this pass
# would have given the child, once the push reads back, and only then does the
# child leave the anchor class and close landed-on-branch. Anchoring first
# means a close that fails leaves an anchor the next pass finds on the branch.
run_lands() { # <lc-rc> <prepared-head> <remote-head> [pr_url pr_number] -> "<rc>#<lifecycle>#<gc>"
  : > "$LCLOG"; : > "$TMP/gc.log"; local rc
  if EXISTING_ANCHOR="" LANDS_ON=cv WORK=rebuild-1 BRANCH=integration/cv TARGET=main CHECK_SET=correctness \
       LC="$TMP/bin/lc-stub" PRE_OPEN=0 PR_URL="${4:-}" PR_NUMBER="${5:-}" LCRC="$1" GCLOG="$TMP/gc.log" \
       STUB_PREPARED_HEAD="$2" STUB_REMOTE_HEAD="$3" \
       bash "$TMP/terminal.sh" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  printf '%s#%s#%s' "$rc" "$(tr '\n' ';' < "$LCLOG")" "$(tr '\n' ';' < "$TMP/gc.log")"
}
LANDS_OK="$(run_lands 0 cafef00d cafef00d)"
case "$LANDS_OK" in
  "0#transition cv --to pre_open_gate --assignee  --route  --set merged_target=main --set check_set=correctness --unset rejection_reason;transition rebuild-1 --to unanchored --unset rejection_reason;#"*)
    ok "(12a) the named bead is anchored at pre_open_gate first, then the child leaves the anchor class" ;;
  *) bad "(12a) expected cv anchored at pre_open_gate, then the child unanchored (got: $LANDS_OK)" ;;
esac
case "$LANDS_OK" in
  *"#"*"update cv --append-notes Rework rebuild-1 landed on integration/cv at cafef00d"*"update rebuild-1 --status=closed"*"gating continues on anchor cv"*)
    ok "(12b) the anchor is annotated, and the child closes landed-on-branch naming it" ;;
  *) bad "(12b) expected the anchor note and the child's close naming cv (got: $LANDS_OK)" ;;
esac
case "$LANDS_OK" in
  *"transition rebuild-1 --to pre_open_gate"*|*"transition rebuild-1 --to pull_request"*)
    bad "(12c) the child must take no gating state of its own (got: $LANDS_OK)" ;;
  *) ok "(12c) the child takes no gating state: the branch's one anchor is the bead it names" ;;
esac
LANDS_PR="$(run_lands 0 cafef00d cafef00d "https://github.com/o/r/pull/9" 9)"
case "$LANDS_PR" in
  "0#transition cv --to pull_request --assignee  --route  --set pr_url=https://github.com/o/r/pull/9 --set pr_number=9 "*)
    ok "(12d) with both PR coordinates resolved, the named bead is anchored at pull_request" ;;
  *) bad "(12d) expected cv anchored at pull_request (got: $LANDS_PR)" ;;
esac
LANDS_REFUSED="$(run_lands 1 cafef00d cafef00d)"
case "$LANDS_REFUSED" in
  *"transition rebuild-1"*|*"update rebuild-1 --status=closed"*|*"update cv --append-notes"*)
    bad "(12e) a refused anchoring must close nothing and note nothing (got: $LANDS_REFUSED)" ;;
  1#"transition cv --to pre_open_gate"*) ok "(12e) a refused anchoring closes nothing, and the arm exits non-zero" ;;
  *) bad "(12e) a refused anchoring must exit non-zero after the one attempt (got: $LANDS_REFUSED)" ;;
esac
LANDS_UNPUSHED="$(run_lands 0 deadbeef feedface)"
case "$LANDS_UNPUSHED" in
  "1##") ok "(12f) a push that does not read back anchors nothing and closes nothing" ;;
  *) bad "(12f) a push that does not read back must write nothing (got: $LANDS_UNPUSHED)" ;;
esac

# --- The resolve and the terminal, run as merge-push runs them. ---------------
# merge-push runs the resolve block and then the terminal block in one shell, so
# these cases run the two as one script. A landing whose listing or named convoy
# cannot be resolved stops before the terminal: no gating transition, no note,
# no close, one drain, exit 1, so the next pass retries the landing.
{ printf '%s\n' "$SNIPPET"; printf '%s\n' "$TERMINAL"; } > "$TMP/landing.sh"
run_landing() { # [VAR=value...] -> "<rc>#<lifecycle>#<gc writes>#<drain-acks>#<escalations>"
  : > "$LCLOG"; : > "$TMP/gc.log"; : > "$TMP/drain.log"; : > "$TMP/esc.log"; local rc
  if env WORK=rebuild-1 BRANCH=integration/cv BEAD_JSON="$REBUILD_ROW" TARGET=main CHECK_SET=correctness \
       LC="$TMP/bin/lc-stub" PRE_OPEN=0 PR_URL="" PR_NUMBER="" LCRC=0 GCLOG="$TMP/gc.log" \
       DRAINLOG="$TMP/drain.log" ESCLOG="$TMP/esc.log" STUB_PREPARED_HEAD=cafef00d STUB_REMOTE_HEAD=cafef00d \
       "$@" bash "$TMP/landing.sh" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  printf '%s#%s#%s#%s#%s' "$rc" "$(tr '\n' ';' < "$LCLOG")" "$(tr '\n' ';' < "$TMP/gc.log")" \
    "$(tr '\n' ';' < "$TMP/drain.log")" "$(tr '\n' ';' < "$TMP/esc.log")"
}
cat > "$FAKE_ANCHORS" <<'A'
rebuild-1||integration/cv|2026-07-02T00:00:00Z|cv|task
cv||integration/cv|2026-07-01T00:00:00Z||convoy
A
: > "$FAKE_SHOW"
# (13a) The control: the listing reads, the convoy is open on the branch, and
#       the landing anchors it and closes the child. The cases below stop where
#       they do because of what they read.
LANDING_OK="$(run_landing)"
case "$LANDING_OK" in
  "0#transition cv --to pre_open_gate "*"transition rebuild-1 --to unanchored "*"#"*"update rebuild-1 --status=closed"*)
    ok "(13a) with the listing read, the landing anchors the convoy and closes its rebuild child" ;;
  *) bad "(13a) expected cv anchored and rebuild-1 closed (got: $LANDING_OK)" ;;
esac
# (13b) The listing fails, though it printed the whole branch.
eq "$(run_landing FAKE_LIST_RC=1)" "1###drain-ack;#" \
   "(13b) a failed listing makes no gating transition and no close, and drains for the next pass"
# (13c) The listing fails and prints [], which a reader of its output alone
#       takes for an empty branch.
eq "$(run_landing FAKE_LIST_RC=1 FAKE_LIST_RAW='[]')" "1###drain-ack;#" \
   "(13c) a failed listing that prints [] holds the landing the same way"
# (13d) The listing exits 0 with what is no array: bd's error object.
eq "$(run_landing FAKE_LIST_RAW='{"error":"database is locked"}')" "1###drain-ack;#" \
   "(13d) a listing that is not a JSON array holds the landing"
# (13e) A raw control byte inside a note is not a failed read: once it is
#       dropped the listing parses, and the landing goes on as in (13a).
RAW_CTRL=$'[{"id":"cv","issue_type":"convoy","created_at":"2026-07-01T00:00:00Z","metadata":{"branch":"integration/cv"},"notes":"line one\nline\ttwo"}]'
LANDING_CTRL="$(run_landing FAKE_LIST_RAW="$RAW_CTRL")"
case "$LANDING_CTRL" in
  "0#transition cv --to pre_open_gate "*"#"*"update rebuild-1 --status=closed"*)
    ok "(13e) a listing with a raw control byte in a note still anchors the convoy" ;;
  *) bad "(13e) expected the scrubbed listing to anchor cv (got: $LANDING_CTRL)" ;;
esac
# (13f) The convoy the child names is closed, so the listing does not return it.
cat > "$FAKE_ANCHORS" <<'A'
rebuild-1||integration/cv|2026-07-02T00:00:00Z|cv|task
A
printf 'cv|convoy|closed\n' > "$FAKE_SHOW"
LANDING_CLOSED="$(run_landing)"
case "$LANDING_CLOSED" in
  "1###drain-ack;#--subject rebuild-1 --key refinery-rebuild-convoy-not-open "*)
    ok "(13f) a rebuild child whose convoy is closed anchors nothing, closes nothing and files one visit" ;;
  *) bad "(13f) expected no transition, no close, one drain and one visit (got: $LANDING_CLOSED)" ;;
esac
# (13g) The named bead cannot be read at all.
: > "$FAKE_SHOW"
eq "$(run_landing)" "1###drain-ack;#" \
   "(13g) a rebuild child whose named bead cannot be read anchors nothing and closes nothing"

# --- The landed-on-branch close carries the rework's work record. -------------
# The runtime's work-record gate reads gc.work_outcome, gc.work_commit and
# gc.work_branch on this close. The record is the landing the read-back proved:
# shipped, the FULL head read back from origin (the note carries the short
# one), on the branch that head is on.
FULL_HEAD=cafef00dcafef00dcafef00dcafef00dcafef00d
: > "$LCLOG"; : > "$TMP/gc.log"
EXISTING_ANCHOR=anchor-po WORK=w1 BRANCH=polecat/parent TARGET=main CHECK_SET=correctness \
  LC="$TMP/bin/lc-stub" PRE_OPEN=0 PR_URL="" PR_NUMBER="" LCRC=0 GCLOG="$TMP/gc.log" \
  STUB_PREPARED_HEAD="$FULL_HEAD" STUB_REMOTE_HEAD="$FULL_HEAD" \
  bash "$TMP/terminal.sh" >/dev/null 2>&1 || true
CLOSE_LINE="$(grep -- 'update w1 --status=closed' "$TMP/gc.log" || true)"
case "$CLOSE_LINE" in
  *"--set-metadata gc.work_outcome=shipped "*) ok "(10k) the landed-on-branch close records gc.work_outcome=shipped" ;;
  *) bad "(10k) the landed-on-branch close must record gc.work_outcome=shipped (got: '$CLOSE_LINE')" ;;
esac
case "$CLOSE_LINE" in
  *"--set-metadata gc.work_commit=$FULL_HEAD "*) ok "(10l) gc.work_commit is the full head read back from origin" ;;
  *) bad "(10l) gc.work_commit must be the full origin head $FULL_HEAD (got: '$CLOSE_LINE')" ;;
esac
case "$CLOSE_LINE" in
  *"--set-metadata gc.work_branch=polecat/parent "*) ok "(10m) gc.work_branch is the branch the rework landed on" ;;
  *) bad "(10m) gc.work_branch must be the branch the rework landed on, polecat/parent (got: '$CLOSE_LINE')" ;;
esac
case "$CLOSE_LINE" in
  *"Rework landed on polecat/parent at cafef00d;"*) ok "(10n) the close note still carries the short sha" ;;
  *) bad "(10n) the close note must carry the short sha (got: '$CLOSE_LINE')" ;;
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
