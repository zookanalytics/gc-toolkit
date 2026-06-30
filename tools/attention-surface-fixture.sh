#!/usr/bin/env bash
# attention-surface-fixture.sh — the automatable assertions for the Phase 3
# attention surface (epic tk-q4xaj; bead tk-qkags; design Phase 3).
#
# Phase 3's SHIP gate is the operator-judged capstone (board → pick a flagged
# bead → land in its resumed universe → it answers a pre-seeded reach-requiring
# question). That end-to-end demo is human-in-the-loop by design and is NOT
# what this fixture replaces. What this fixture locks down is the deterministic
# machinery underneath it, so a regression in the board's new behavior is caught
# automatically:
#
#   • the 4th anchor kind — a flagged bead (gc.attention=1) is admitted, lands
#     in its own FLAGGED band, and floats above every other anchor;
#   • the liveness glyph — the pack-namespaced-alias → bead-id join over
#     `gc session list` (bead-host sessions only) resolves hot/warm/cold,
#     and a live host keeps a decomposed anchor out of the stranded band;
#   • the row cap — the board never balloons past the cap, and --limit=0 opts
#     out for tooling;
#   • the --json contract — additive only (new `live` field present; existing
#     fields intact);
#   • verb dispatch + validation — board/open/flag/clear routing and the
#     fail-closed arg checks.
#
# HERMETIC BY DESIGN. The board's render/rank/glyph path is driven through the
# tool's GC_ATTENTION_FIXTURE hook (canned anchors.ndjson + sessions.json +
# rigs.json under a temp dir), so these assertions write NOTHING to Dolt and
# need no live city. A best-effort read-only smoke at the end proves the real
# gather+contract on the live city; an OPT-IN flag→clear round-trip
# (GC_ATTENTION_FLAG_SMOKE_BEAD=<id>) exercises the live write path on a bead
# the operator chooses — the fixture never invents or closes a bead of its own.
#
# Run:   tools/attention-surface-fixture.sh
# Exit:  0 iff every hermetic assertion passes.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/../assets/scripts/gc-attention.sh"
[ -x "$TOOL" ] || { echo "fixture: $TOOL not executable" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "fixture: jq required" >&2; exit 2; }

FXDIR="$(mktemp -d)"
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap
cleanup() { rm -rf "$FXDIR"; }
trap cleanup EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        expected: [%s]\n        actual:   [%s]\n' "$1" "$2" "$3"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "contains: $2" "$3" ;; esac; }
absent() { case "$3" in *"$2"*) bad "$1" "absent: $2" "$3" ;; *) ok "$1" ;; esac; }

# Board run against the seeded fixture (no Dolt, no live city).
B() { GC_ATTENTION_FIXTURE="$FXDIR" "$TOOL" "$@"; }

# ---------------------------------------------------------------------------
# Seed: 1 rig, and four anchors — a flagged bead with a HOT host, a stranded
# epic, a decision, and a second flagged bead with a WARM (suspended) host.
# Distinct ids make the ordering + glyph assertions unambiguous.
# ---------------------------------------------------------------------------
cat > "$FXDIR/rigs.json" <<'JSON'
[{"name":"gc-toolkit","path":"/tmp/fx-gc-toolkit","prefix":"tk"},
 {"name":"signal-loom","path":"/tmp/fx-signal-loom","prefix":"sl"}]
JSON

cat > "$FXDIR/anchors.ndjson" <<'JSON'
{"id":"tk-flaghot","title":"CI mystery","kind":"flagged","source":"flagged","rig":"gc-toolkit","prefix":"tk","priority":3,"updated_at":"2026-06-07T03:00:00Z","description":"","progress":null,"children":[],"reason":"CI red, cause unknown","flagged_at":"2026-06-07T03:00:00Z"}
{"id":"tk-epic","title":"Big epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"references sl-zzz9","progress":null,"children":[{"id":"tk-a","status":"open","assignee":""},{"id":"tk-b","status":"closed","assignee":""}]}
{"id":"sl-dec","title":"Pick a path","kind":"decision","source":"decision","rig":"signal-loom","prefix":"sl","priority":1,"updated_at":"2026-06-05T00:00:00Z","description":"","progress":null,"children":[]}
{"id":"tk-flagwarm","title":"Stale spec","kind":"flagged","source":"flagged","rig":"gc-toolkit","prefix":"tk","priority":4,"updated_at":"2026-06-06T00:00:00Z","description":"","progress":null,"children":[],"reason":"needs a re-read","flagged_at":"2026-06-06T00:00:00Z"}
JSON

# Sessions model the real shape: a bead-host alias is pack-namespaced
# (<pack>.<bead-id>) and carries the bead-host template, so the board's
# liveness join strips the leading "<pack>." and joins only bead-host
# sessions. tk-flaghot has an ACTIVE host (hot); tk-flagwarm a SUSPENDED one
# (warm); everything else cold. The refinery (non-bead-host template, aliased
# with slashes) must NOT perturb the join.
cat > "$FXDIR/sessions.json" <<'JSON'
{"sessions":[
  {"id":"lx-1","alias":"gc-toolkit.tk-flaghot","template":"gc-toolkit.bead-host","state":"active","running":true,"attached":false},
  {"id":"lx-2","alias":"gc-toolkit.tk-flagwarm","template":"gc-toolkit.bead-host","state":"suspended","running":false,"attached":false},
  {"id":"lx-9","alias":"gc-toolkit/gc-toolkit.refinery","template":"gc-toolkit.refinery","state":"active","running":true}
]}
JSON

echo "── hermetic: 4th anchor (flagged) + FLAGGED band ──"
J="$(B --json)"
eq   "board returns a JSON array"            "array"  "$(printf '%s' "$J" | jq -r 'type')"
eq   "all four anchors admitted"             "4"      "$(printf '%s' "$J" | jq 'length')"
eq   "flagged kind present"                  "2"      "$(printf '%s' "$J" | jq '[.[]|select(.kind=="flagged")]|length')"
eq   "top row is a flagged bead"             "FLAGGED" "$(printf '%s' "$J" | jq -r '.[0].severity')"
eq   "flagged floats above the stranded epic" "true"  "$(printf '%s' "$J" | jq -r '(.[0].rank_score) > (.[]|select(.kind=="epic").rank_score)')"
has  "flagged frontier carries the reason"   "CI red" "$(printf '%s' "$J" | jq -r '.[]|select(.id=="tk-flaghot").frontier')"

echo "── hermetic: liveness glyph join (pack-namespaced alias → bead-id) ──"
eq   "hot host resolves hot"   "hot"  "$(printf '%s' "$J" | jq -r '.[]|select(.id=="tk-flaghot").live')"
eq   "suspended host is warm"  "warm" "$(printf '%s' "$J" | jq -r '.[]|select(.id=="tk-flagwarm").live')"
eq   "no host is cold"         "cold" "$(printf '%s' "$J" | jq -r '.[]|select(.id=="tk-epic").live')"
eq   "live field is on every row (additive contract)" "4" "$(printf '%s' "$J" | jq '[.[]|select(.live!=null)]|length')"
has  "hot glyph in human table"   "●" "$(B)"
has  "warm glyph in human table"  "◐" "$(B)"

echo "── hermetic: live host ⇒ active, not stranded (tk-q4xaj.2) ──"
# A decomposed epic with open children and ZERO in-progress is the classic
# "stranded/HIGH" shape — UNLESS a live bead-host is resident, in which case
# it is being worked via a 1:1 conversation, not via child polecats. Two
# sibling epics with the identical stranded shape: tk-hosted has a HOT host,
# tk-lonely has none. The fix must spare the hosted one and ONLY the hosted
# one (liveness-gated, not a blanket suppression).
LIVE="$(mktemp -d)"; cp "$FXDIR/rigs.json" "$LIVE/rigs.json"
# updated_at must be RECENT, not a hardcoded date: this case asserts NORMAL,
# and a fixed past date eventually crosses STALE_DAYS and bumps NORMAL→ELEVATED
# (a time-bomb). Compute it relative to now so the assertion never rots. The
# heredoc is intentionally UNquoted so $LIVE_RECENT interpolates (the JSON lines
# carry no other shell metacharacters).
LIVE_RECENT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$LIVE/anchors.ndjson" <<JSON
{"id":"tk-hosted","title":"Hosted epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$LIVE_RECENT","description":"","progress":null,"children":[{"id":"tk-h1","status":"open","assignee":""},{"id":"tk-h2","status":"open","assignee":""}]}
{"id":"tk-lonely","title":"Unhosted epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$LIVE_RECENT","description":"","progress":null,"children":[{"id":"tk-l1","status":"open","assignee":""},{"id":"tk-l2","status":"open","assignee":""}]}
JSON
cat > "$LIVE/sessions.json" <<'JSON'
{"sessions":[
  {"id":"lx-h","alias":"gc-toolkit.tk-hosted","template":"gc-toolkit.bead-host","state":"active","running":true,"attached":true}
]}
JSON
LIVEJ="$(GC_ATTENTION_FIXTURE="$LIVE" "$TOOL" --json)"
eq     "hosted epic resolves hot"               "hot"    "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-hosted").live')"
eq     "hosted epic is NORMAL, not HIGH"        "NORMAL" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-hosted").severity')"
eq     "hosted epic is NOT stranded"            "false"  "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-hosted").stranded')"
has    "hosted epic frontier reads in-conversation" "in conversation" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-hosted").frontier')"
absent "hosted epic frontier drops (stranded)"  "stranded" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-hosted").frontier')"
has    "hosted epic needs is open-to-join"      "open to join" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-hosted").needs')"
has    "hosted epic still shows the hot glyph"  "●" "$(GC_ATTENTION_FIXTURE="$LIVE" "$TOOL")"
# Control: the unhosted sibling, identical shape but no host, stays HIGH.
eq     "unhosted sibling stays cold"            "cold"   "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-lonely").live')"
eq     "unhosted sibling stays HIGH"            "HIGH"   "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-lonely").severity')"
eq     "unhosted sibling stays stranded"        "true"   "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-lonely").stranded')"
has    "unhosted sibling frontier says stranded" "stranded" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-lonely").frontier')"
rm -rf "$LIVE"

echo "── hermetic: dead-owner in-progress is stuck, not moving (PROBLEM 1) ──"
# An in-progress child counts as MOVING only if its owning session is live.
# A child in_progress whose owner is dead (archived/closed/absent — keyed off
# .state, NEVER .running) is the canonical UNKNOWN-stuck case: it must NOT mask
# a stall. Four sibling epics, identical shape: a DEAD owner (session archived),
# an ABSENT owner (assignee not in the session list at all), a LIVE-owner
# control (session active, .running null to prove we ignore it), and a MIXED
# anchor (one live + one dead in-progress child). Recent updated_at so the
# staleness bump never perturbs the severity assertions.
DO="$(mktemp -d)"; cp "$FXDIR/rigs.json" "$DO/rigs.json"
DO_RECENT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$DO/anchors.ndjson" <<JSON
{"id":"tk-dead","title":"Dead-owner epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$DO_RECENT","description":"","progress":null,"children":[{"id":"tk-d1","status":"in_progress","assignee":"gc-toolkit__polecat-dead"},{"id":"tk-d2","status":"open","assignee":""}]}
{"id":"tk-absent","title":"Absent-owner epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$DO_RECENT","description":"","progress":null,"children":[{"id":"tk-ab1","status":"in_progress","assignee":"gc-toolkit__polecat-gone"},{"id":"tk-ab2","status":"open","assignee":""}]}
{"id":"tk-live","title":"Live-owner epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$DO_RECENT","description":"","progress":null,"children":[{"id":"tk-lv1","status":"in_progress","assignee":"gc-toolkit__polecat-live"},{"id":"tk-lv2","status":"open","assignee":""}]}
{"id":"tk-mixed","title":"Mixed-owner epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$DO_RECENT","description":"","progress":null,"children":[{"id":"tk-mx1","status":"in_progress","assignee":"gc-toolkit__polecat-live"},{"id":"tk-mx2","status":"in_progress","assignee":"gc-toolkit__polecat-dead"},{"id":"tk-mx3","status":"open","assignee":""}]}
JSON
cat > "$DO/sessions.json" <<'JSON'
{"sessions":[
  {"session_name":"gc-toolkit__polecat-dead","alias":"gc-toolkit/gc-toolkit.deadcat","template":"gc-toolkit/gc-toolkit.polecat","state":"archived","running":false},
  {"session_name":"gc-toolkit__polecat-live","alias":"gc-toolkit/gc-toolkit.livecat","template":"gc-toolkit/gc-toolkit.polecat","state":"active","running":null}
]}
JSON
DOJ="$(GC_ATTENTION_FIXTURE="$DO" "$TOOL" --json)"
# Dead owner (session archived) → the in-progress child does not count as moving.
eq  "dead-owner: in_progress_live is 0"            "0"      "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-dead").in_progress_live')"
eq  "dead-owner: in_progress_dead is 1"            "1"      "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-dead").in_progress_dead')"
eq  "dead-owner: dead_owner flag true"             "true"   "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-dead").dead_owner')"
eq  "dead-owner: severity HIGH (stuck surfaced)"   "HIGH"   "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-dead").severity')"
eq  "dead-owner: stranded true"                    "true"   "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-dead").stranded')"
has "dead-owner: frontier names the stuck child"   "stuck (dead owner)" "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-dead").frontier')"
has "dead-owner: needs says recover/reassign"      "dead owner"         "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-dead").needs')"
has "dead-owner: stuck id rides into dead_owner_heads" "tk-d1"          "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-dead").dead_owner_heads|join(",")')"
# Absent owner (assignee not in the session list) is dead too.
eq  "absent-owner: dead_owner flag true"           "true"   "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-absent").dead_owner')"
eq  "absent-owner: severity HIGH"                  "HIGH"   "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-absent").severity')"
# Live-owner control: the SAME shape stays active (NORMAL), not stranded — and
# liveness keys off .state (active), never .running (null here would false-flag).
eq  "live-owner: in_progress_live is 1"            "1"      "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-live").in_progress_live')"
eq  "live-owner: dead_owner flag false"            "false"  "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-live").dead_owner')"
eq  "live-owner: severity NORMAL"                  "NORMAL" "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-live").severity')"
eq  "live-owner: not stranded"                     "false"  "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-live").stranded')"
absent "live-owner: a null .running does NOT mark it stuck" "stuck" "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-live").frontier')"
# Mixed: one live + one dead in-progress → still moving (ELEVATED), stuck surfaced.
eq  "mixed: in_progress_live is 1"                 "1"        "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-mixed").in_progress_live')"
eq  "mixed: in_progress_dead is 1"                 "1"        "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-mixed").in_progress_dead')"
eq  "mixed: severity ELEVATED (moving + a stuck child)" "ELEVATED" "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-mixed").severity')"
eq  "mixed: not stranded (live work present)"      "false"    "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-mixed").stranded')"
has "mixed: frontier shows live + stuck"           "stuck (dead owner)" "$(printf '%s' "$DOJ" | jq -r '.[]|select(.id=="tk-mixed").frontier')"
rm -rf "$DO"

echo "── hermetic: unowned non-machine convoy is the orphan exception (PROBLEM 2) ──"
# Everything-is-owned: a non-machine convoy that is NOT owned is the orphan
# EXCEPTION the observer must SURFACE (HIGH), never drop. An OWNED convoy stays a
# normal floating anchor. (The render path is driven directly here; the gather's
# machine-convoy exclusion — sling-* and "input convoy for …" — is a Dolt-side
# filter exercised by the live smoke, not hermetically.)
UO="$(mktemp -d)"; cp "$FXDIR/rigs.json" "$UO/rigs.json"; printf '{}' > "$UO/sessions.json"
UO_RECENT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$UO/anchors.ndjson" <<JSON
{"id":"tk-orphan","title":"Orphan convoy","kind":"unowned","source":"unowned","owned":false,"rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$UO_RECENT","description":"","progress":null,"children":[{"id":"tk-orf1","status":"open","assignee":""}]}
{"id":"tk-owncv","title":"Owned initiative","kind":"convoy","source":"convoy","owned":true,"rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$UO_RECENT","description":"","progress":null,"children":[{"id":"tk-ow1","status":"closed","assignee":""}]}
JSON
UOJ="$(GC_ATTENTION_FIXTURE="$UO" "$TOOL" --json)"
eq  "unowned: kind is unowned"                 "unowned" "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-orphan").kind')"
eq  "unowned: severity HIGH (orphan exception)" "HIGH"   "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-orphan").severity')"
eq  "unowned: owned field is false"            "false"   "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-orphan").owned')"
has "unowned: frontier flags no owning bead"   "unowned convoy" "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-orphan").frontier')"
has "unowned: needs says assign an owning bead" "assign an owning bead" "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-orphan").needs')"
eq  "unowned: floats above the owned convoy"   "true"    "$(printf '%s' "$UOJ" | jq -r '(.[]|select(.id=="tk-orphan").rank_score) > (.[]|select(.id=="tk-owncv").rank_score)')"
# Owned convoy stays a normal floating anchor (kind convoy, owned true, here LOW
# because all children closed) — never mislabelled as the unowned exception.
eq  "owned convoy: kind is convoy"             "convoy"  "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-owncv").kind')"
eq  "owned convoy: owned field is true"        "true"    "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-owncv").owned')"
has "owned convoy: complete reads graduate"    "graduate" "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-owncv").needs')"
absent "owned convoy: not flagged unowned"     "unowned convoy" "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-owncv").frontier')"
rm -rf "$UO"

echo "── hermetic: --json contract stays additive (existing + new fields intact) ──"
# Existing fields MUST persist (additive-only contract); the takeaway feature
# ADDS open_heads + takeaway/_at/_by (always-present keys, null when absent).
for f in id rig kind title severity weight n_closed m_total open in_progress frontier needs rank_score \
         open_heads takeaway takeaway_at takeaway_by \
         in_progress_live in_progress_dead dead_owner dead_owner_heads owned; do
    eq "field '$f' present on every row" "true" "$(printf '%s' "$J" | jq -c "[.[]|has(\"$f\")]|all")"
done

echo "── hermetic: takeaway drives NEEDS (present → sentence; absent → terse, no bead-ids) ──"
# The feature's core contract (bead tk-q4xaj.3): an anchor's gc.takeaway is the
# NEEDS sentence; when absent NEEDS is a TERSE deterministic phrase, never a
# bead-id list; the mechanical heads/xref ids move to --json (open_heads,
# cross_rig_refs). A whitespace-laden takeaway is collapsed to one line so it
# can never break the human table.
TKV="$(mktemp -d)"; cp "$FXDIR/rigs.json" "$TKV/rigs.json"; printf '{}' > "$TKV/sessions.json"
cat > "$TKV/anchors.ndjson" <<'JSON'
{"id":"tk-tk","title":"has takeaway","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"takeaway":"need operator to pick the storage backend before schema lands","takeaway_at":"2026-06-10T00:00:00Z","takeaway_by":"proactive","children":[{"id":"tk-c1","status":"open","assignee":""},{"id":"tk-c2","status":"closed","assignee":""}]}
{"id":"tk-bare","title":"stranded no takeaway","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"blocks sl-zzz9 downstream","progress":null,"takeaway":"","children":[{"id":"tk-c3","status":"open","assignee":""},{"id":"tk-c4","status":"open","assignee":""}]}
{"id":"tk-ml","title":"whitespacey takeaway","kind":"decision","source":"decision","rig":"gc-toolkit","prefix":"tk","priority":1,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"takeaway":"line one\nline two   trailing  ","children":[]}
JSON
TKJ="$(GC_ATTENTION_FIXTURE="$TKV" "$TOOL" --json)"
# Present: the takeaway sentence IS the NEEDS, and the by/at ride into --json.
has "takeaway present → NEEDS is the sentence" "pick the storage backend" \
    "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-tk").needs')"
eq  "takeaway present → JSON .takeaway carries the sentence" \
    "need operator to pick the storage backend before schema lands" \
    "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-tk").takeaway')"
eq  "takeaway present → JSON .takeaway_by is recorded" "proactive" \
    "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-tk").takeaway_by')"
# Absent: a terse phrase, NO frontier bead-id and NO cross-rig bead-id.
NB="$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-bare").needs')"
has    "takeaway absent → NEEDS is a terse human phrase"  "decomposed, idle" "$NB"
absent "takeaway absent → NEEDS has NO frontier bead-id"  "tk-c3"            "$NB"
absent "takeaway absent → NEEDS has NO cross-rig bead-id" "sl-zzz9"          "$NB"
eq     "takeaway absent → JSON .takeaway is null"         "null"             "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-bare").takeaway')"
# The mechanical ids moved to --json (open_heads + the existing cross_rig_refs).
has "frontier heads moved to --json open_heads"    "tk-c3"   "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-bare").open_heads|join(",")')"
has "cross-rig refs moved to --json cross_rig_refs" "sl-zzz9" "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-bare").cross_rig_refs|join(",")')"
# Whitespace/newlines in a takeaway are collapsed to one table-safe line.
eq  "whitespacey takeaway collapses to one line" "line one line two trailing" \
    "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-ml").needs')"
# Human table: the takeaway sentence shows; no raw/truncated bead-id leaks in.
HT="$(GC_ATTENTION_FIXTURE="$TKV" "$TOOL")"
has    "human table shows the takeaway sentence"        "pick the storage backend" "$HT"
absent "human table leaks no frontier bead-id (tk-c3)"  "tk-c3"                    "$HT"
absent "human table leaks no cross-rig bead-id (sl-zzz9)" "sl-zzz9"                "$HT"
rm -rf "$TKV"

echo "── hermetic: row cap + --limit=0 opt-out ──"
eq   "default cap honored (MAX_ROWS=2 → 2 rows)" "2" "$(GC_ATTENTION_MAX_ROWS=2 B --json | jq 'length')"
eq   "--limit=0 overrides the cap (all 4)"       "4" "$(GC_ATTENTION_MAX_ROWS=2 B --json --limit=0 | jq 'length')"
eq   "--limit=1 takes the single top row"        "1" "$(B --json --limit=1 | jq 'length')"
has  "capped table notes 'showing N of M'" "showing 2 of 4" "$(GC_ATTENTION_MAX_ROWS=2 B)"

echo "── hermetic: dedup (a bead matched by two gathers shows once) ──"
DUP="$(mktemp -d)"; cp "$FXDIR/rigs.json" "$DUP/rigs.json"; printf '{}' > "$DUP/sessions.json"
cat > "$DUP/anchors.ndjson" <<'JSON'
{"id":"tk-dup","title":"Dual","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"children":[{"id":"tk-a","status":"open","assignee":""}]}
{"id":"tk-dup","title":"Dual","kind":"flagged","source":"flagged","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"children":[],"reason":"look here","flagged_at":"2026-06-07T00:00:00Z"}
JSON
DUPJ="$(GC_ATTENTION_FIXTURE="$DUP" "$TOOL" --json)"
eq   "flagged-epic dedups to a single row" "1"       "$(printf '%s' "$DUPJ" | jq 'length')"
eq   "the surviving row is the FLAGGED one" "flagged" "$(printf '%s' "$DUPJ" | jq -r '.[0].kind')"
rm -rf "$DUP"

echo "── hermetic: empty board ──"
EMPTY="$(mktemp -d)"; : > "$EMPTY/anchors.ndjson"; cp "$FXDIR/rigs.json" "$EMPTY/rigs.json"; printf '{}' > "$EMPTY/sessions.json"
has  "empty board says nothing floats" "Nothing floats" "$(GC_ATTENTION_FIXTURE="$EMPTY" "$TOOL" 2>/dev/null)"
eq   "empty board --json is []" "0" "$(GC_ATTENTION_FIXTURE="$EMPTY" "$TOOL" --json | jq 'length')"
rm -rf "$EMPTY"

echo "── hermetic: verb dispatch + fail-closed validation ──"
has  "help lists the open verb"  "open"  "$("$TOOL" help 2>&1 || true)"
has  "help lists the flag verb"  "flag"  "$("$TOOL" help 2>&1 || true)"
ec=0; "$TOOL" flag 2>/dev/null || ec=$?;            eq "flag with no bead errors (exit 2)"        "2" "$ec"
ec=0; "$TOOL" flag tk-x 2>/dev/null || ec=$?;       eq "flag with no --reason errors (exit 2)"    "2" "$ec"
ec=0; "$TOOL" open 2>/dev/null || ec=$?;            eq "open with no bead errors (exit 2)"        "2" "$ec"
ec=0; "$TOOL" clear 2>/dev/null || ec=$?;           eq "clear with no bead errors (exit 2)"       "2" "$ec"
ec=0; "$TOOL" bogus-verb 2>/dev/null || ec=$?;      eq "unknown verb errors (exit 2)"             "2" "$ec"
# takeaway: a thin metadata-writer verb (like flag/clear), but bead-id AND text
# are BOTH required — missing either fails closed (exit 2). Whitespace-only text
# counts as missing (it collapses to empty before the check).
ec=0; "$TOOL" takeaway 2>/dev/null || ec=$?;        eq "takeaway with no bead errors (exit 2)"    "2" "$ec"
ec=0; "$TOOL" takeaway tk-x 2>/dev/null || ec=$?;   eq "takeaway with no text errors (exit 2)"    "2" "$ec"
ec=0; "$TOOL" takeaway tk-x "   " 2>/dev/null || ec=$?; eq "takeaway with whitespace-only text errors (exit 2)" "2" "$ec"
has  "help lists the takeaway verb" "takeaway"           "$("$TOOL" help 2>&1 || true)"
has  "usage documents takeaway"     "takeaway <bead-id>" "$("$TOOL" --help 2>&1 || true)"
# --release is a recognized boolean flag on takeaway. Probe it WITHOUT a bead so
# the parse-level error (missing bead-id) proves the flag was consumed — not
# rejected as unknown — and no Dolt write is reached. The usage advertises it.
REL_OUT="$("$TOOL" takeaway --release 2>&1 || true)"
has    "takeaway --release is a recognized flag (not unknown)" "needs <bead-id>" "$REL_OUT"
absent "takeaway --release is not rejected as unknown"         "unknown flag"    "$REL_OUT"
has    "usage documents the takeaway --release flag"           "--release"       "$("$TOOL" --help 2>&1 || true)"
# The retired --note flag is now an UNKNOWN flag (takeaway is takeaway-only).
NOTE_OUT="$("$TOOL" takeaway tk-x sometext --note whatever 2>&1 || true)"
has    "the retired takeaway --note flag is now rejected as unknown" "unknown flag" "$NOTE_OUT"

echo "── hermetic: react is the front-door over gc-proactive.sh sling (mr path, codex-gated) ──"
# react <id> is a THIN wrapper over tools/gc-proactive.sh `sling` — it owns no
# sling logic. Driven through the REAL gc-proactive.sh on its --dry-run path
# (GC_PROACTIVE_FIXTURE makes that path echo the resolved command instead of
# calling gc), so this proves the WIRING end-to-end: react → sling →
# mol-first-reaction on the mr path, never direct.
PROACTIVE_TOOL_REAL="$HERE/gc-proactive.sh"
if [ -x "$PROACTIVE_TOOL_REAL" ]; then
    RX="$(GC_RIG=gc-toolkit GC_PROACTIVE_TOOL="$PROACTIVE_TOOL_REAL" GC_PROACTIVE_FIXTURE="$FXDIR" \
          GC_ATTENTION_FIXTURE="$FXDIR" "$TOOL" react tk-epic --dry-run 2>&1 || true)"
    has    "react slings mol-first-reaction"          "--on mol-first-reaction"         "$RX"
    has    "react pins the codex-gated mr path"       "--merge mr"                      "$RX"
    absent "react never routes direct"                "--merge direct"                  "$RX"
    has    "react targets the rig-qualified pool"     "gc-toolkit/gc-toolkit.proactive" "$RX"
    has    "react passes the bead through to sling"   "tk-epic"                         "$RX"
    # --reason is accepted as operator intent but NOT forwarded (sling has none).
    RXR="$(GC_RIG=gc-toolkit GC_PROACTIVE_TOOL="$PROACTIVE_TOOL_REAL" GC_PROACTIVE_FIXTURE="$FXDIR" \
           GC_ATTENTION_FIXTURE="$FXDIR" "$TOOL" react tk-epic --reason "pick a backend" --dry-run 2>&1 || true)"
    has    "react surfaces the operator --reason"     "pick a backend"                  "$RXR"
    absent "react does NOT forward --reason to sling" "--reason"                        "$RXR"
    # Regression (tk-82g33): react must SELF-SUPPLY GC_RIG so the sling can
    # rig-qualify its pool target even from a GC_RIG-less shell — the NORMAL
    # operator path (the prefix+b board picker and a bare shell both lack it).
    # The assertions above pre-set GC_RIG=gc-toolkit, which MASKS the bug by
    # letting resolve_pool_target read it from the environment; here we DROP it
    # with `env -u GC_RIG` and prove react derives gc-toolkit from the tk- bead's
    # own rig. The fixture's rigs.json already maps tk→gc-toolkit, so no fixture
    # data change is needed. "rig-qualify" is the fail-closed die() phrase —
    # asserting it absent proves the guard never fired.
    RXNR="$(env -u GC_RIG GC_PROACTIVE_TOOL="$PROACTIVE_TOOL_REAL" GC_PROACTIVE_FIXTURE="$FXDIR" \
            GC_ATTENTION_FIXTURE="$FXDIR" "$TOOL" react tk-epic --dry-run 2>&1 || true)"
    has    "react self-supplies the rig (no GC_RIG → still rig-qualified)" \
           "gc-toolkit/gc-toolkit.proactive" "$RXNR"
    has    "react (no GC_RIG) still slings mol-first-reaction" "--on mol-first-reaction" "$RXNR"
    has    "react (no GC_RIG) still pins the codex-gated mr path" "--merge mr"           "$RXNR"
    has    "react (no GC_RIG) passes the bead through"         "tk-epic"                 "$RXNR"
    absent "react (no GC_RIG) never hits the fail-closed guard" "rig-qualify"            "$RXNR"
else
    printf '  skip  react→sling wiring (gc-proactive.sh not found at %s)\n' "$PROACTIVE_TOOL_REAL"
fi
# Dispatch + fail-closed validation for the new verb.
ec=0; "$TOOL" react 2>/dev/null || ec=$?;  eq "react with no bead errors (exit 2)" "2" "$ec"
has "help lists the react verb"  "react"            "$("$TOOL" help 2>&1 || true)"
has "usage documents react"      "react <bead-id>"  "$("$TOOL" --help 2>&1 || true)"

echo "── contract: operator surface is the runnable script, not a phantom gc subcommand ──"
# The regression this guards (PR #100 review): the docs/prompt advertised a
# `gc attention …` CLI that was never registered, so a bare invocation renders
# root gc help. Pack commands bind under the pack name (`gc <pack> <cmd>`), so
# no top-level attention subcommand can exist. The runnable surface is THIS
# script — reached via the prefix+b tmux picker (tmux-pick-attention.sh →
# gc-attention.sh) or run directly — plus tools/gc-bead-host.sh. These
# assertions lock the operator-facing docs to that reality.

# (a) the documented script entry actually runs and prints its own usage.
has  "script --help prints usage" "Usage:" "$("$TOOL" --help 2>&1 || true)"
has  "script -h prints usage"     "Usage:" "$("$TOOL" -h 2>&1 || true)"

# (b) no operator-facing surface file advertises the phantom CLI. The match is
#     the space-form ("gc attention …", incl. backtick-wrapped); the real
#     script name "gc-attention" (hyphen) is intentionally NOT matched.
SURFACE_FILES=(
    "$HERE/../assets/scripts/gc-attention.sh"
    "$HERE/../agents/bead-host/prompt.template.md"
    "$HERE/../agents/bead-host/agent.toml"
    "$HERE/../agents/bead-host/PROVENANCE.md"
)
phantom=""
for f in "${SURFACE_FILES[@]}"; do
    [ -f "$f" ] || continue
    hit="$(grep -nF 'gc attention' "$f" 2>/dev/null || true)"
    [ -n "$hit" ] && phantom+="$f: $hit"$'\n'
done
absent "no operator surface file advertises a phantom 'gc attention' CLI" "gc attention" "$phantom"

# ---------------------------------------------------------------------------
# Best-effort LIVE smokes (skipped cleanly when no city / gc is reachable).
# ---------------------------------------------------------------------------
echo "── live (best-effort): real board contract ──"
if command -v gc >/dev/null 2>&1 && gc rig list --json >/dev/null 2>&1; then
    live="$("$TOOL" --json --timeout=8 2>/dev/null || printf 'ERR')"
    if printf '%s' "$live" | jq -e 'type=="array"' >/dev/null 2>&1; then
        ok "live board --json returns an array"
        # If a cache file now exists, a second glance must be cache-fast & valid.
        live2="$("$TOOL" --json --timeout=8 2>/dev/null || printf 'ERR')"
        printf '%s' "$live2" | jq -e 'type=="array"' >/dev/null 2>&1 \
            && ok "second glance (cached) returns an array" \
            || bad "second glance (cached) returns an array" "array" "$live2"
    else
        printf '  skip  live board smoke (gc returned non-array; city may be cold)\n'
    fi
else
    printf '  skip  live board smoke (no reachable city)\n'
fi

# Opt-in: a full flag→board→clear + takeaway + takeaway --release round-trip on
# an operator-chosen bead. The fixture never invents or closes a bead — it writes
# only to the bead the operator named, and every leg self-cleans (clear undoes
# flag; the unset undoes takeaway; the --release leg captures and restores the
# bead's prior lifecycle fields and unsets the marker it set).
if [ -n "${GC_ATTENTION_FLAG_SMOKE_BEAD:-}" ]; then
    echo "── live (opt-in): flag/clear + takeaway + takeaway --release round-trip on $GC_ATTENTION_FLAG_SMOKE_BEAD ──"
    bead="$GC_ATTENTION_FLAG_SMOKE_BEAD"
    "$TOOL" flag "$bead" --reason "attention-surface-fixture smoke" >/dev/null 2>&1 \
        && ok "flag $bead" || bad "flag $bead" "exit 0" "non-zero"
    eq "bead now carries gc.attention=1" "1" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.attention"] // ""')"
    has "flagged bead appears on the live board" "$bead" \
        "$("$TOOL" --json --refresh --timeout=8 2>/dev/null | jq -r '.[]|select(.kind=="flagged").id' || true)"
    "$TOOL" clear "$bead" >/dev/null 2>&1 \
        && ok "clear $bead" || bad "clear $bead" "exit 0" "non-zero"
    eq "bead no longer carries gc.attention" "" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.attention"] // ""')"
    # takeaway: write the headline, read back the THREE metadata fields, then
    # unset them (the clean-up leg — takeaway has no inverse verb).
    "$TOOL" takeaway "$bead" "attention-surface-fixture smoke takeaway" --by host >/dev/null 2>&1 \
        && ok "takeaway $bead" || bad "takeaway $bead" "exit 0" "non-zero"
    eq "bead now carries the gc.takeaway headline" "attention-surface-fixture smoke takeaway" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.takeaway"] // ""')"
    eq "bead now carries gc.takeaway_by=host" "host" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.takeaway_by"] // ""')"
    eq "bead now carries a non-empty gc.takeaway_at stamp" "true" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '(.[0].metadata["gc.takeaway_at"] // "") != ""')"
    gc bd update "$bead" --unset-metadata gc.takeaway --unset-metadata gc.takeaway_at --unset-metadata gc.takeaway_by >/dev/null 2>&1 \
        && ok "unset the smoke takeaway (cleanup)" || bad "unset the smoke takeaway" "exit 0" "non-zero"
    eq "bead no longer carries gc.takeaway" "" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.takeaway"] // ""')"
    # --release leg: ONE call stamps the takeaway AND releases the bead (reopen,
    # unassign, clear route, mark reacted). Capture the prior lifecycle fields so
    # we can restore them — unlike the takeaway-only leg above, --release mutates
    # status/assignee/route.
    PRIOR_STATUS="$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].status // "open"')"
    PRIOR_ASSIGNEE="$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].assignee // ""')"
    PRIOR_ROUTE="$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.routed_to"] // ""')"
    "$TOOL" takeaway "$bead" "attention-surface-fixture release smoke" --by proactive --release >/dev/null 2>&1 \
        && ok "takeaway --release $bead" || bad "takeaway --release $bead" "exit 0" "non-zero"
    RELJSON="$(gc bd show "$bead" --json 2>/dev/null)"
    eq "release stamps the gc.takeaway headline"      "attention-surface-fixture release smoke" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].metadata["gc.takeaway"] // ""')"
    eq "release attributes the takeaway to proactive" "proactive" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].metadata["gc.takeaway_by"] // ""')"
    eq "release reopens the bead (status=open)"       "open" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].status // ""')"
    eq "release clears the assignee"                  "" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].assignee // ""')"
    eq "release clears the pool route (gc.routed_to)" "" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].metadata["gc.routed_to"] // ""')"
    eq "release marks the proactive reaction"         "1" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].metadata["gc.proactive_reaction"] // ""')"
    # Restore the prior lifecycle fields + unset the smoke takeaway/marker.
    gc bd update "$bead" --status="$PRIOR_STATUS" --assignee="$PRIOR_ASSIGNEE" \
        --set-metadata gc.routed_to="$PRIOR_ROUTE" \
        --unset-metadata gc.takeaway --unset-metadata gc.takeaway_at --unset-metadata gc.takeaway_by \
        --unset-metadata gc.proactive_reaction >/dev/null 2>&1 \
        && ok "restore lifecycle + unset the release smoke (cleanup)" || bad "restore the release smoke" "exit 0" "non-zero"
else
    printf '  skip  live flag→clear + takeaway round-trip (set GC_ATTENTION_FLAG_SMOKE_BEAD=<id> to run)\n'
fi

echo ""
echo "attention-surface-fixture: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
