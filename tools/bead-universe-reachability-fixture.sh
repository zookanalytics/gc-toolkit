#!/usr/bin/env bash
# bead-universe-reachability-fixture.sh — the automatable Phase 2 gate for the
# Bead-Universe Operating Model (specs/bead-universe/design-doc.md, Phase 2).
# That design is v1, superseded in part by specs/tk-h9pq5/design-doc.md (v2):
# v2 replaced the binding and lifecycle and left Phase 2 untouched, so v1 is
# still the gate this fixture scores against — read its supersession banner
# before citing the rest of it.
#
# THE GATE (design Phase 2, "dual metric, automatable"):
#   A seeded subtree + a fixed list of questions, each with a known ground-truth
#   answer key, answerable ONLY by reaching the fed slice + the fetch tools.
#   Scored by EXACT-MATCH against the keys (not an LLM judge).
#   Pass = 100% recall AND fed-slice <= the token ceiling.
#
# HERMETIC BY DESIGN. The subtree is seeded as canned data sources under a
# temp dir and fed to gc-bd-universe.sh via its GC_BD_UNIVERSE_FIXTURE hook,
# so this gate is deterministic, fast, and writes NOTHING to Dolt (no seeded
# beads to leak; nothing to clean up but a temp dir). A best-effort live smoke
# at the end proves the real gc/gh integration path on one live bead.
#
# The "host given ONLY the fed slice + fetch tools" constraint is modeled by
# answering each question ONLY from `slice`/`fetch` output — never from the raw
# canned JSON — so a pass means the slice+fetch CONTRACT surfaces every fact.
#
# Run:  tools/bead-universe-reachability-fixture.sh
# Exit: 0 iff every assertion passes (100% recall, footprint within ceiling,
#       tier + boundary + null-vs-error assertions all green).

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/gc-bd-universe.sh"
[ -x "$TOOL" ] || { echo "fixture: $TOOL not executable" >&2; exit 2; }

CEILING="${GC_BD_UNIVERSE_TOKEN_CEILING:-2000}"
SMOKE_BEAD="${SMOKE_BEAD:-tk-oqmc7}"

FXDIR="$(mktemp -d)"
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() { rm -rf "$FXDIR"; }
trap cleanup EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        expected: [%s]\n        actual:   [%s]\n' "$1" "$2" "$3"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "contains: $2" "$3" ;; esac; }
absent() { case "$3" in *"$2"*) bad "$1" "absent: $2" "$3" ;; *) ok "$1" ;; esac; }

# Run the tool against the seeded subtree.
U() { GC_BD_UNIVERSE_FIXTURE="$FXDIR" GC_BD_UNIVERSE_TOKEN_CEILING="$CEILING" "$TOOL" "$@"; }

# ---------------------------------------------------------------------------
# Seed the subtree: an epic with 3 children, a discovered-from dep, and notes.
# Distinctive magic words make exact-match keys unambiguous.
#   fx-epic ── parent of ── fx-impl (open), fx-done (closed, PR+CI), fx-todo (pre-work)
#           ── discovered-from ── fx-design  (title must show; full body must NOT)
# ---------------------------------------------------------------------------
seed() {
    cat > "$FXDIR/fx-epic.show.json" <<'JSON'
[{
  "id": "fx-epic",
  "title": "Seeded Universe Epic",
  "description": "Root epic of the seeded universe. The body-tier magic word is BORZOI. Target release is v9.9.\nThis body spans multiple lines so the full-body-feed is exercised, while neighbor bodies stay trimmed.",
  "status": "open",
  "issue_type": "epic",
  "priority": 1,
  "comment_count": 0,
  "notes": "note 1: kickoff\nnote 2: design landed\nnote 3: latest-note magic is WALRUS",
  "dependencies": [
    {
      "id": "fx-design",
      "title": "Design doc for the seeded universe",
      "status": "closed",
      "dependency_type": "discovered-from",
      "description": "FULL-DESIGN-BODY that must never appear in the epic's fed slice — only this dep's title may."
    }
  ]
}]
JSON

    cat > "$FXDIR/fx-epic.children.json" <<'JSON'
[
  {"id": "fx-impl", "title": "Implement the thing", "status": "open",   "type": "task"},
  {"id": "fx-done", "title": "Finished sub-task",    "status": "closed", "type": "task"},
  {"id": "fx-todo", "title": "Not started yet",      "status": "open",   "type": "task"}
]
JSON

    cat > "$FXDIR/fx-impl.show.json" <<'JSON'
[{
  "id": "fx-impl",
  "title": "Implement the thing",
  "description": "Full body reachable only by fetching this neighbor: the secret port is 8472.",
  "status": "open",
  "issue_type": "task",
  "priority": 2,
  "comment_count": 0
}]
JSON

    cat > "$FXDIR/fx-done.show.json" <<'JSON'
[{
  "id": "fx-done",
  "title": "Finished sub-task",
  "description": "Completed sub-task body.",
  "status": "closed",
  "issue_type": "task",
  "priority": 2,
  "comment_count": 4,
  "metadata": {
    "pr_number": 1234,
    "pr_url": "https://github.com/seed/repo/pull/1234",
    "branch": "polecat/fx-done",
    "target": "main"
  }
}]
JSON

    cat > "$FXDIR/fx-done.pr.json" <<'JSON'
{"number": 1234, "title": "Finished sub-task PR", "state": "MERGED", "body": "PR body for fx-done."}
JSON

    printf 'pass\nall checks passed (3/3)\n' > "$FXDIR/fx-done.checks.txt"

    # The incident shape (tk-d6ixcw): an approving bot comment on top, a
    # COMMENTED review whose body is EMPTY, and the objections living only in
    # the inline review comments. None of it moves state, mergeability or the
    # check rollup, so it is reachable through the conversation tier alone.
    cat > "$FXDIR/fx-done.conversation.json" <<'JSON'
{
  "number": 1234,
  "url": "https://github.com/seed/repo/pull/1234",
  "state": "OPEN",
  "updatedAt": "2026-08-26T17:06:22Z",
  "comments": [
    {"author": {"login": "seed-bot"}, "createdAt": "2026-08-26T08:49:52Z",
     "body": "Codex signoff: VERDICT approve. The clean-read magic word is MEERKAT."}
  ],
  "reviews": [
    {"author": {"login": "seed-operator"}, "state": "COMMENTED",
     "submittedAt": "2026-08-26T17:06:21Z", "body": ""}
  ],
  "review_comments": [
    {"user": {"login": "seed-operator"}, "created_at": "2026-08-26T16:46:33Z",
     "path": "docs/seed.md", "line": 71,
     "body": "First objection: the inline-only magic word is PANGOLIN."},
    {"user": {"login": "seed-operator"}, "created_at": "2026-08-26T16:47:10Z",
     "path": "tools/seed.sh", "original_line": 12,
     "body": "Second objection, carried on original_line."}
  ]
}
JSON

    # A PR with nothing said on it: the 'no_conversation' arm, distinct from
    # fx-todo's pre-work null and fx-ghost's unreachable error.
    cat > "$FXDIR/fx-quiet.show.json" <<'JSON'
[{
  "id": "fx-quiet",
  "title": "PR open, nobody has said anything",
  "description": "Has a PR; its conversation is empty.",
  "status": "open",
  "issue_type": "task",
  "priority": 2,
  "comment_count": 0,
  "metadata": {"pr_number": 4321, "pr_url": "https://github.com/seed/repo/pull/4321"}
}]
JSON

    cat > "$FXDIR/fx-quiet.conversation.json" <<'JSON'
{
  "number": 4321,
  "url": "https://github.com/seed/repo/pull/4321",
  "state": "OPEN",
  "updatedAt": "2026-08-20T00:00:00Z",
  "comments": [],
  "reviews": [],
  "review_comments": []
}
JSON

    cat > "$FXDIR/fx-todo.show.json" <<'JSON'
[{
  "id": "fx-todo",
  "title": "Not started yet",
  "description": "Pre-work sub-task: no PR yet, so CI is 'not yet' (null), not an error.",
  "status": "open",
  "issue_type": "task",
  "priority": 2,
  "comment_count": 0
}]
JSON

    # fx-ghost references a PR but stages no PR data -> the ERROR side of
    # null-vs-error: a referenced-but-unreachable PR (exit 3), distinct from
    # fx-todo's expected pre-work 'null' (exit 0).
    cat > "$FXDIR/fx-ghost.show.json" <<'JSON'
[{
  "id": "fx-ghost",
  "title": "References a vanished PR",
  "description": "Has a PR reference but the PR cannot be reached.",
  "status": "open",
  "issue_type": "task",
  "priority": 2,
  "comment_count": 0,
  "metadata": {"pr_number": 9999}
}]
JSON

    # Validate the seed itself so a malformed fixture fails loudly, not silently.
    local f
    for f in fx-epic.show fx-epic.children fx-impl.show fx-done.show fx-done.pr \
             fx-done.conversation fx-todo.show fx-ghost.show fx-quiet.show \
             fx-quiet.conversation; do
        jq -e . "$FXDIR/$f.json" >/dev/null || { echo "fixture: malformed seed $f.json" >&2; exit 2; }
    done
}

seed

echo "== Reachability gate: seeded subtree, exact-match against answer keys =="

slice="$(U slice fx-epic --json)"
human="$(U slice fx-epic)"

echo "-- FED tier (answered from the fed slice alone) --"
# Q1: body fact.
eq  "Q1  body magic word"          "BORZOI" "$(printf '%s' "$slice" | jq -r '.body' | grep -oE 'BORZOI' | head -1)"
# Q2: a second body fact.
eq  "Q2  body target release"      "v9.9"   "$(printf '%s' "$slice" | jq -r '.body' | grep -oE 'v9\.9' | head -1)"
# Q3: 1-hop child count.
eq  "Q3  children count"           "3"      "$(printf '%s' "$slice" | jq -r '.counts.children')"
# Q4: a specific child's status, from the title-only manifest.
eq  "Q4  child fx-done status"     "closed" "$(printf '%s' "$slice" | jq -r '.manifest.children[]|select(.id=="fx-done").status')"
# Q5: a specific child's title, from the manifest.
eq  "Q5  child fx-impl title"      "Implement the thing" "$(printf '%s' "$slice" | jq -r '.manifest.children[]|select(.id=="fx-impl").title')"
# Q6: the discovered-from dep id, from the manifest.
eq  "Q6  dep (discovered-from) id" "fx-design" "$(printf '%s' "$slice" | jq -r '.manifest.deps[]|select(.rel=="discovered-from").id')"
# Q7: notes tail fact.
eq  "Q7  notes-tail magic word"    "WALRUS" "$(printf '%s' "$slice" | jq -r '.notes_tail' | grep -oE 'WALRUS' | head -1)"

echo "-- FETCHABLE tier (answered only after a fetch) --"
# Q8: a fact that lives ONLY in a child's full body -> must fetch the neighbor.
eq  "Q8  fetch neighbor fx-impl: secret port" "8472" \
    "$(U fetch fx-epic neighbor fx-impl | jq -r '.description' | grep -oE '[0-9]{4}' | head -1)"
# Q9: PR number for fx-done -> fetch pr.
eq  "Q9  fetch pr fx-done: number" "1234" \
    "$(U fetch fx-done pr --json | jq -r '.number')"
# Q10: CI status for fx-done -> fetch ci (the gh pr checks wiring).
eq  "Q10 fetch ci fx-done: state"  "pass" \
    "$(U fetch fx-done ci --json | jq -r '.state')"
# Bonus: full comment history reach (count surfaced).
has "Q11 fetch comments fx-done"   "4" "$(U fetch fx-done comments)"

echo "-- CONVERSATION tier: what has been SAID on the PR (tk-d6ixcw) --"
conv="$(U fetch fx-done conversation --json)"
# Q11b: the objections are counted, not just the bot's approval.
eq "Q11b conversation inline count"   "2" "$(printf '%s' "$conv" | jq -r '.counts.review_comments')"
eq "Q11c conversation total count"    "4" "$(printf '%s' "$conv" | jq -r '.counts.total')"
# Q11d: a fact that lives ONLY in an inline review comment.
eq "Q11d inline-only magic word"      "PANGOLIN" \
    "$(printf '%s' "$conv" | jq -r '.review_comments[].body' | grep -oE 'PANGOLIN' | head -1)"
# Q11e: an inline comment on a stale hunk reports original_line, not null.
eq "Q11e original_line fallback"      "12" \
    "$(printf '%s' "$conv" | jq -r '.review_comments[]|select(.path=="tools/seed.sh").line')"
# Q11f: a COMMENTED review with an EMPTY body is still surfaced — the review
# that moved no state field is the one the state view cannot show.
eq "Q11f COMMENTED review surfaced"   "COMMENTED" \
    "$(printf '%s' "$conv" | jq -r '.reviews[].state')"
# Q11g: updated_at is carried, so a moved timestamp under an unmoved state is
# readable as a reason to look.
eq "Q11g conversation updated_at"     "2026-08-26T17:06:22Z" \
    "$(printf '%s' "$conv" | jq -r '.updated_at')"
# Q11h: reached content is fenced in the human view like every other fetch.
has "Q11h conversation human view fenced" "UNTRUSTED DATA" "$(U fetch fx-done conversation)"
# Q11i: the tier is advertised in the fed slice, so a host knows to reach it.
has "Q11i conversation advertised in fetchable" "conversation" \
    "$(printf '%s' "$slice" | jq -r '.fetchable | join(" ")')"
# Q11j: a PR with nothing said on it is 'no_conversation', not an error.
eq "Q11j quiet PR -> no_conversation" "no_conversation" \
    "$(U fetch fx-quiet conversation --json | jq -r '.state')"

echo "-- LIVE PATH (stubbed gc/gh): every --paginate page is read --"
# `gh --paginate` emits ONE JSON ARRAY PER PAGE. A plain `.[]?` over that
# stream reads page one and drops the rest silently, which on a busy PR is the
# same blindness as not fetching at all. Driving the LIVE path (fixture hook
# off) against stubs that emit two pages is what holds the slurp in place; the
# stubs exit 9 on any call shape the tool is not supposed to make, so a
# rewritten call fails here rather than passing quietly.
STUB="$FXDIR/stub"; mkdir -p "$STUB"
cat > "$STUB/bead.json" <<'JSON'
[{"id":"fx-live","title":"Live-path bead","description":"b","status":"open","issue_type":"task",
  "comment_count":0,"metadata":{"pr_number":777,"pr_url":"https://github.com/seed/repo/pull/777"}}]
JSON
cat > "$STUB/view.json" <<'JSON'
{"number":777,"url":"https://github.com/seed/repo/pull/777","state":"OPEN",
 "updatedAt":"2026-08-26T17:06:22Z","comments":[],"reviews":[]}
JSON
cat > "$STUB/page1.json" <<'JSON'
[{"user":{"login":"a"},"created_at":"2026-08-26T01:00:00Z","path":"p1","line":1,"body":"page one first"},
 {"user":{"login":"a"},"created_at":"2026-08-26T01:01:00Z","path":"p1","line":2,"body":"page one second"}]
JSON
cat > "$STUB/page2.json" <<'JSON'
[{"user":{"login":"b"},"created_at":"2026-08-26T02:00:00Z","path":"p2","line":3,"body":"page two first"},
 {"user":{"login":"b"},"created_at":"2026-08-26T02:01:00Z","path":"p2","line":4,"body":"PAGE-TWO-MAGIC"}]
JSON
cat > "$STUB/gc" <<'STUBEOF'
#!/bin/sh
if [ "$1" != "bd" ] || [ "$2" != "show" ]; then echo "stub gc: unexpected call: $*" >&2; exit 9; fi
cat "$STUB_DIR/bead.json"
STUBEOF
cat > "$STUB/gh" <<'STUBEOF'
#!/bin/sh
case "$1" in
  pr)
    [ "$2" = "view" ] || { echo "stub gh: unexpected pr subcommand: $*" >&2; exit 9; }
    case "$*" in
      *"--repo seed/repo"*) : ;;
      *) echo "stub gh: pr view must name the repo parsed from pr_url: $*" >&2; exit 9 ;;
    esac
    case "$*" in
      *"--json number,url,state,updatedAt,comments,reviews"*) : ;;
      *) echo "stub gh: pr view must request the conversation fields: $*" >&2; exit 9 ;;
    esac
    cat "$STUB_DIR/view.json" ;;
  api)
    case "$*" in
      *"repos/seed/repo/pulls/777/comments"*) : ;;
      *) echo "stub gh: unexpected api path: $*" >&2; exit 9 ;;
    esac
    case "$*" in
      *--paginate*) : ;;
      *) echo "stub gh: inline comments must be paginated: $*" >&2; exit 9 ;;
    esac
    cat "$STUB_DIR/page1.json" "$STUB_DIR/page2.json" ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 9 ;;
esac
STUBEOF
chmod +x "$STUB/gc" "$STUB/gh"

live_conv="$(STUB_DIR="$STUB" PATH="$STUB:$PATH" GC_BD_UNIVERSE_FIXTURE="" "$TOOL" fetch fx-live conversation --json)" || live_conv='{}'
eq "Q11k both pages read (2 pages x 2 comments)" "4" \
    "$(printf '%s' "$live_conv" | jq -r '.counts.review_comments // "none"')"
eq "Q11l page-two content reached"               "PAGE-TWO-MAGIC" \
    "$(printf '%s' "$live_conv" | jq -r '.review_comments[]?.body' | grep -oE 'PAGE-TWO-MAGIC' | head -1)"

echo "-- TRIMMING: the one concrete build (heavy dep bodies -> titles) --"
# The dep's FULL body must NOT leak into the fed slice; only its title may.
absent "Q12 dep full body trimmed from fed slice" "FULL-DESIGN-BODY" "$human"
has    "Q12 dep title present in fed slice"        "Design doc for the seeded universe" "$human"

echo "-- NULL-vs-ERROR: pre-work distinction (design Data Model) --"
# fx-todo has no PR: CI is 'prework' (not error). fx-done has a PR with checks.
eq "Q13 fetch ci fx-todo (pre-work)" "prework" "$(U fetch fx-todo ci --json | jq -r '.state')"
eq "Q14 fetch pr fx-todo (pre-work)" "prework" "$(U fetch fx-todo pr --json | jq -r '.state')"
# The ERROR side: a referenced-but-unreachable PR exits 3 (not 0, not the
# pre-work 'null') — so a host can tell "vanished" from "not yet".
rc=0; U fetch fx-ghost pr >/dev/null 2>&1 || rc=$?
eq "Q14b fetch pr fx-ghost -> unreachable exit 3" "3" "$rc"
eq "Q14c fetch conversation fx-todo (pre-work)" "prework" "$(U fetch fx-todo conversation --json | jq -r '.state')"
rc=0; U fetch fx-ghost conversation >/dev/null 2>&1 || rc=$?
eq "Q14d fetch conversation fx-ghost -> unreachable exit 3" "3" "$rc"

echo "-- BOUNDARY: >1-hop is out of reach --"
# fx-stranger is not a 1-hop neighbor of fx-epic -> fetch must refuse.
if U fetch fx-epic neighbor fx-stranger >/dev/null 2>&1; then
    bad "Q15 out-of-reach neighbor refused" "non-zero exit" "exit 0"
else
    ok "Q15 out-of-reach neighbor refused"
fi

echo "-- FOOTPRINT: fed slice within the token ceiling --"
fp="$(U footprint fx-epic)" && fp_rc=0 || fp_rc=$?
toks="$(printf '%s' "$fp" | grep -oE '[0-9]+ tokens' | head -1 | grep -oE '[0-9]+')"
printf '        %s\n' "$fp"
if [ "$fp_rc" -eq 0 ] && [ "${toks:-999999}" -le "$CEILING" ]; then
    ok "Q16 fed-slice ${toks} tokens <= ceiling ${CEILING}"
else
    bad "Q16 fed-slice footprint" "<= ${CEILING} tokens, PASS" "${toks} tokens, rc=${fp_rc}"
fi

echo "-- LIVE SMOKE: real gc/gh path (best-effort) --"
if gc bd show "$SMOKE_BEAD" --json >/dev/null 2>&1; then
    live="$("$TOOL" slice "$SMOKE_BEAD" --json)"
    has "S1  live slice schema" "gc-bd-universe/slice@1" "$(printf '%s' "$live" | jq -r '.schema')"
    blen="$(printf '%s' "$live" | jq -r '.body | length')"
    if [ "${blen:-0}" -gt 0 ]; then ok "S2  live slice body non-empty"; else bad "S2  live slice body non-empty" ">0" "${blen:-0}"; fi
else
    printf '  SKIP  live smoke (bead %s not in this ledger)\n' "$SMOKE_BEAD"
fi

echo ""
TOTAL=$((PASS + FAIL))
echo "==================================================================="
printf 'Reachability gate: %d/%d assertions passed' "$PASS" "$TOTAL"
if [ "$FAIL" -eq 0 ]; then
    printf '  — RECALL 100%%, footprint within ceiling. GATE PASS.\n'
    exit 0
fi
printf '  — %d FAILED. GATE FAIL.\n' "$FAIL"
exit 1
