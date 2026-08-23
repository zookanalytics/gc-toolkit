#!/usr/bin/env bash
# helm-surface-fixture.sh — the automatable assertions for the Phase 3
# attention surface. Phase 3 originates in Bead-Universe v1
# (specs/bead-universe/design-doc.md, Phase 3), but what this fixture asserts
# is governed by v2 (specs/tk-h9pq5/design-doc.md): v2 kept the board and
# rewired what a pick does — file-or-attach a visit, not resume-or-create a
# per-bead host — which is why the held glyph below reads visit presence.
# The v1 flag scenarios are gone outright: the gc.attention flag was removed
# by operator decision 2026-08-08
# (specs/2026-08-fresh-start/attention-flag-removal.md).
#
# The operator-judged capstone (board → pick a bead → converse session
# holds the conversation) is human-in-the-loop by design and is NOT
# what this fixture replaces. What this fixture locks down is the deterministic
# machinery underneath it, so a regression in the board's behavior is caught
# automatically:
#
#   • the held glyph — visit presence (an open visit bead whose
#     gc.continuation_group names the anchor) resolves held/not-held,
#     and a held anchor stays out of the stranded band;
#   • the row cap — the board never balloons past the cap, and --limit=0 opts
#     out for tooling;
#   • the --json contract — every documented field present (the `held`
#     visit fact is the one conversation glyph; there is no `live` field);
#   • verb dispatch + validation — board/open/react/takeaway routing and the
#     fail-closed arg checks;
#   • the gather-failure contract — a failed gather errors and
#     is never cached, a legit empty board still is, and a host with no
#     timeout/gtimeout degrades instead of dying (stub gc + private PATH).
#
# HERMETIC BY DESIGN. The board's render/rank/glyph path is driven through the
# tool's GC_HELM_FIXTURE hook (canned anchors.ndjson + visits.json +
# sessions.json + rigs.json under a temp dir), so these assertions write
# NOTHING to Dolt and need no live city. A best-effort read-only smoke at the
# end proves the real gather+contract on the live city; an OPT-IN takeaway
# round-trip (GC_HELM_SMOKE_BEAD=<id>) exercises the live write path on a bead
# the operator chooses — the fixture never invents or closes a bead of its own.
#
# Run:   tools/helm-surface-fixture.sh
# Exit:  0 iff every hermetic assertion passes.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/../assets/scripts/gc-helm.sh"
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
B() { GC_HELM_FIXTURE="$FXDIR" "$TOOL" "$@"; }

# ---------------------------------------------------------------------------
# Seed: 1 rig, and four anchors — an epic with an OPEN VISIT (held), a
# stranded epic, a decision, and a second epic with no visit.
# Distinct ids make the ordering + glyph assertions unambiguous.
# ---------------------------------------------------------------------------
cat > "$FXDIR/rigs.json" <<'JSON'
[{"name":"gc-toolkit","path":"/tmp/fx-gc-toolkit","prefix":"tk"},
 {"name":"signal-loom","path":"/tmp/fx-signal-loom","prefix":"sl"}]
JSON

cat > "$FXDIR/anchors.ndjson" <<'JSON'
{"id":"tk-held","title":"CI mystery","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":3,"updated_at":"2026-06-07T03:00:00Z","description":"","progress":null,"children":[{"id":"tk-hh1","status":"open","assignee":""}]}
{"id":"tk-epic","title":"Big epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"references sl-zzz9","progress":null,"children":[{"id":"tk-a","status":"open","assignee":""},{"id":"tk-b","status":"closed","assignee":""}]}
{"id":"sl-dec","title":"Pick a path","kind":"decision","source":"decision","rig":"signal-loom","prefix":"sl","priority":1,"updated_at":"2026-06-05T00:00:00Z","description":"","progress":null,"children":[]}
{"id":"tk-quiet","title":"Stale spec","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":4,"updated_at":"2026-06-06T00:00:00Z","description":"","progress":null,"children":[{"id":"tk-hw1","status":"open","assignee":""}]}
JSON

# Visit presence models the real shape: tk-held has an open visit in its
# continuation group (held); everything else has none. Sessions feed ONLY
# the child-owner liveness map now — a session (like the refinery here)
# must NOT perturb the held glyph.
cat > "$FXDIR/visits.json" <<'JSON'
["tk-held"]
JSON
cat > "$FXDIR/sessions.json" <<'JSON'
{"sessions":[
  {"id":"lx-9","alias":"gc-toolkit/gc-toolkit.refinery","template":"gc-toolkit.refinery","state":"active","running":true}
]}
JSON

echo "── hermetic: anchor kinds + severity bands ──"
J="$(B --json)"
eq   "board returns a JSON array"            "array"  "$(printf '%s' "$J" | jq -r 'type')"
eq   "all four anchors admitted"             "4"      "$(printf '%s' "$J" | jq 'length')"
eq   "epic kind present"                     "3"      "$(printf '%s' "$J" | jq '[.[]|select(.kind=="epic")]|length')"
eq   "top row is the stranded epic (HIGH)"   "HIGH"   "$(printf '%s' "$J" | jq -r '.[0].severity')"
eq   "the stranded epic floats above the decision" "true" "$(printf '%s' "$J" | jq -r '(.[]|select(.id=="tk-epic").rank_score) > (.[]|select(.id=="sl-dec").rank_score)')"
has  "decision frontier is human-gated"      "human-gated" "$(printf '%s' "$J" | jq -r '.[]|select(.id=="sl-dec").frontier')"

echo "── hermetic: held glyph (visit presence, not sessions) ──"
eq   "open visit resolves held"       "true"  "$(printf '%s' "$J" | jq -r '.[]|select(.id=="tk-held").held')"
eq   "no visit is not held"           "false" "$(printf '%s' "$J" | jq -r '.[]|select(.id=="tk-epic").held')"
eq   "no visit is not held (control)" "false" "$(printf '%s' "$J" | jq -r '.[]|select(.id=="tk-quiet").held')"
eq   "held field is on every row"     "4"     "$(printf '%s' "$J" | jq '[.[]|select(.held!=null)]|length')"
has  "held glyph in human table"      "●"     "$(B)"

echo "── hermetic: open visit ⇒ active, not stranded ──"
# A decomposed epic with open children and ZERO in-progress is the classic
# "stranded/HIGH" shape — UNLESS an open visit holds its conversation, in
# which case it is being worked via that conversation, not via child
# polecats. Two sibling epics with the identical stranded shape: tk-visited
# has an open visit, tk-lonely has none. The spare must hit the visited one
# and ONLY the visited one (visit-gated, not a blanket suppression).
LIVE="$(mktemp -d)"; cp "$FXDIR/rigs.json" "$LIVE/rigs.json"
# updated_at must be RECENT, not a hardcoded date: this case asserts NORMAL,
# and a fixed past date eventually crosses STALE_DAYS and bumps NORMAL→ELEVATED
# (a time-bomb). Compute it relative to now so the assertion never rots. The
# heredoc is intentionally UNquoted so $LIVE_RECENT interpolates (the JSON lines
# carry no other shell metacharacters).
LIVE_RECENT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$LIVE/anchors.ndjson" <<JSON
{"id":"tk-visited","title":"Visited epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$LIVE_RECENT","description":"","progress":null,"children":[{"id":"tk-h1","status":"open","assignee":""},{"id":"tk-h2","status":"open","assignee":""}]}
{"id":"tk-lonely","title":"Unvisited epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"$LIVE_RECENT","description":"","progress":null,"children":[{"id":"tk-l1","status":"open","assignee":""},{"id":"tk-l2","status":"open","assignee":""}]}
JSON
printf '["tk-visited"]\n' > "$LIVE/visits.json"
printf '{}' > "$LIVE/sessions.json"
LIVEJ="$(GC_HELM_FIXTURE="$LIVE" "$TOOL" --json)"
eq     "visited epic resolves held"             "true"   "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-visited").held')"
eq     "visited epic is NORMAL, not HIGH"       "NORMAL" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-visited").severity')"
eq     "visited epic is NOT stranded"           "false"  "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-visited").stranded')"
has    "visited epic frontier reads in-conversation" "in conversation" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-visited").frontier')"
absent "visited epic frontier drops (stranded)" "stranded" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-visited").frontier')"
has    "visited epic needs is open-to-join"     "open to join" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-visited").needs')"
has    "visited epic still shows the held glyph" "●" "$(GC_HELM_FIXTURE="$LIVE" "$TOOL")"
# Control: the unvisited sibling, identical shape but no visit, stays HIGH.
eq     "unvisited sibling is not held"          "false"  "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-lonely").held')"
eq     "unvisited sibling stays HIGH"           "HIGH"   "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-lonely").severity')"
eq     "unvisited sibling stays stranded"       "true"   "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-lonely").stranded')"
has    "unvisited sibling frontier says stranded" "stranded" "$(printf '%s' "$LIVEJ" | jq -r '.[]|select(.id=="tk-lonely").frontier')"
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
DOJ="$(GC_HELM_FIXTURE="$DO" "$TOOL" --json)"
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
UOJ="$(GC_HELM_FIXTURE="$UO" "$TOOL" --json)"
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
absent "owned convoy: not marked unowned"      "unowned convoy" "$(printf '%s' "$UOJ" | jq -r '.[]|select(.id=="tk-owncv").frontier')"
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
# The feature's core contract: an anchor's gc.takeaway is the
# NEEDS sentence; when absent NEEDS is a TERSE deterministic phrase, never a
# bead-id list; the mechanical heads/xref ids move to --json (open_heads,
# cross_rig_refs). A whitespace-laden takeaway is collapsed to one line so it
# can never break the human table.
TKV="$(mktemp -d)"; cp "$FXDIR/rigs.json" "$TKV/rigs.json"; printf '{}' > "$TKV/sessions.json"
cat > "$TKV/anchors.ndjson" <<'JSON'
{"id":"tk-tk","title":"has takeaway","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"takeaway":"need operator to pick the storage backend before schema lands","takeaway_at":"2026-06-10T00:00:00Z","takeaway_by":"proactive","children":[{"id":"tk-c1","status":"open","assignee":""},{"id":"tk-c2","status":"closed","assignee":""}]}
{"id":"tk-bare","title":"stranded no takeaway","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"blocks sl-zzz9 downstream","progress":null,"takeaway":"","children":[{"id":"tk-c3","status":"open","assignee":""},{"id":"tk-c4","status":"open","assignee":""}]}
{"id":"tk-ml","title":"whitespacey takeaway","kind":"decision","source":"decision","rig":"gc-toolkit","prefix":"tk","priority":1,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"takeaway":"line one\nline two   trailing  ","children":[]}
{"id":"tk-mlp","title":"whitespacey takeaway, parked","kind":"parked","source":"parked","rig":"gc-toolkit","prefix":"tk","priority":1,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"takeaway":"line one\nline two   trailing  ","children":[]}
JSON
TKJ="$(GC_HELM_FIXTURE="$TKV" "$TOOL" --json)"
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
# Asserted on BOTH surfaces the collapsed string reaches, because a human-gated
# row no longer spends its takeaway on NEEDS: tk-ml is a decision with nothing
# outstanding, so it is RULED (tk-b3rga) and NEEDS becomes the disposition
# phrase. The collapsing is unchanged; only which column shows it moved, and
# `takeaway` is the field that carries it everywhere.
eq  "whitespacey takeaway collapses to one line" "line one line two trailing" \
    "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-ml").takeaway')"
eq  "…and on the NEEDS path, where a non-human-gated row still spends it" \
    "line one line two trailing" \
    "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-mlp").needs')"
# The ruled row says what it now wants instead — and stands out of the band.
eq  "an answered decision spends NEEDS on the disposition, not the ruling" \
    "ruled — close or extend" \
    "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-ml").needs')"
eq  "…and leaves the ELEVATED band" "LOW" \
    "$(printf '%s' "$TKJ" | jq -r '.[]|select(.id=="tk-ml").severity')"
# Human table: the takeaway sentence shows; no raw/truncated bead-id leaks in.
HT="$(GC_HELM_FIXTURE="$TKV" "$TOOL")"
has    "human table shows the takeaway sentence"        "pick the storage backend" "$HT"
absent "human table leaks no frontier bead-id (tk-c3)"  "tk-c3"                    "$HT"
absent "human table leaks no cross-rig bead-id (sl-zzz9)" "sl-zzz9"                "$HT"
rm -rf "$TKV"

echo "── hermetic: row cap + --limit=0 opt-out ──"
eq   "default cap honored (MAX_ROWS=2 → 2 rows)" "2" "$(GC_HELM_MAX_ROWS=2 B --json | jq 'length')"
eq   "--limit=0 overrides the cap (all 4)"       "4" "$(GC_HELM_MAX_ROWS=2 B --json --limit=0 | jq 'length')"
eq   "--limit=1 takes the single top row"        "1" "$(B --json --limit=1 | jq 'length')"
has  "capped table notes 'showing N of M'" "showing 2 of 4" "$(GC_HELM_MAX_ROWS=2 B)"

echo "── hermetic: dedup (a bead matched by two gathers shows once) ──"
DUP="$(mktemp -d)"; cp "$FXDIR/rigs.json" "$DUP/rigs.json"; printf '{}' > "$DUP/sessions.json"
cat > "$DUP/anchors.ndjson" <<'JSON'
{"id":"tk-dup","title":"Dual","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"children":[{"id":"tk-a","status":"open","assignee":""}]}
{"id":"tk-dup","title":"Dual","kind":"convoy","source":"convoy","owned":true,"rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"children":[{"id":"tk-b","status":"closed","assignee":""}]}
JSON
DUPJ="$(GC_HELM_FIXTURE="$DUP" "$TOOL" --json)"
eq   "doubly-gathered bead dedups to a single row" "1"    "$(printf '%s' "$DUPJ" | jq 'length')"
eq   "the surviving row is the higher-ranked one"  "epic" "$(printf '%s' "$DUPJ" | jq -r '.[0].kind')"
rm -rf "$DUP"

echo "── hermetic: the ID/RIG columns never truncate (tk-mtuej) ──"
# rpad TRUNCATES, so a fixed-width identifier column silently merges rows: at
# the old ID width of 11, the three sibling anchors sl-kg9z6.4.1/.2/.9 — 12
# characters each, discriminated only by the last one — all rendered
# "sl-kg9z6.4." and the operator could not tell which row was which. RIG failed
# the same way at 13 ("shutupandlisten" → "shutupandlist", butted against KIND).
# Both widths are now derived from the widest value on the board.
WIDE="$(mktemp -d)"; printf '{}' > "$WIDE/sessions.json"
cat > "$WIDE/rigs.json" <<'JSON'
[{"name":"shutupandlisten","path":"/tmp/fx-shutupandlisten","prefix":"sl"}]
JSON
cat > "$WIDE/anchors.ndjson" <<'JSON'
{"id":"sl-kg9z6.4.1","title":"Sibling one","kind":"convoy","source":"convoy","owned":true,"rig":"shutupandlisten","prefix":"sl","priority":2,"updated_at":"2026-06-01T00:00:00Z","description":"","progress":null,"children":[{"id":"sl-c1","status":"open","assignee":""}]}
{"id":"sl-kg9z6.4.2","title":"Sibling two","kind":"convoy","source":"convoy","owned":true,"rig":"shutupandlisten","prefix":"sl","priority":2,"updated_at":"2026-06-02T00:00:00Z","description":"","progress":null,"children":[{"id":"sl-c2","status":"open","assignee":""}]}
{"id":"sl-kg9z6.4.9","title":"Sibling nine","kind":"convoy","source":"convoy","owned":true,"rig":"shutupandlisten","prefix":"sl","priority":2,"updated_at":"2026-06-03T00:00:00Z","description":"","progress":null,"children":[{"id":"sl-c9","status":"open","assignee":""}]}
JSON
WIDET="$(GC_HELM_FIXTURE="$WIDE" "$TOOL")"
eq "all three 12-char sibling ids are on the board" "3" \
   "$(GC_HELM_FIXTURE="$WIDE" "$TOOL" --json | jq '[.[]|select(.id|startswith("sl-kg9z6.4."))]|length')"
has "12-char id .1 renders in full"  "sl-kg9z6.4.1" "$WIDET"
has "12-char id .2 renders in full"  "sl-kg9z6.4.2" "$WIDET"
has "12-char id .9 renders in full"  "sl-kg9z6.4.9" "$WIDET"
absent "no row renders the truncated collision cell" "sl-kg9z6.4. " "$WIDET"
has "a long rig name keeps its tail and its gutter" "shutupandlisten " "$WIDET"
# Widening moves the LAYOUT, not just the cell: every data row must still start
# RIG at the same column the header does. (Byte offsets are safe here — the text
# left of RIG is ASCII on all four lines; none of these rows is held.)
WIDE_HDR_COL="$(printf '%s\n' "$WIDET" | awk '/^  SEV/ {print index($0, "RIG"); exit}')"
WIDE_ROW_COLS="$(printf '%s\n' "$WIDET" | awk '/shutupandlisten/ {print index($0, "shutupandlisten")}' | sort -u)"
eq "the three rows agree on one RIG column"     "1"                "$(printf '%s\n' "$WIDE_ROW_COLS" | wc -l | tr -d ' ')"
eq "rows start RIG where the header says"       "$WIDE_HDR_COL"    "$WIDE_ROW_COLS"
# RIG's 1-based start column minus the 11 columns before ID (held + SEV) and
# minus 1 for the 1-based index IS the ID column's width.
eq "the ID column widened to 13 (12-char id + gutter)" "13" "$((WIDE_HDR_COL - 12))"
rm -rf "$WIDE"
# Control — the quiet path: a board of ordinary ids keeps the classic layout,
# so the fix widens on demand rather than permanently reflowing every board.
eq "ordinary board keeps RIG at its classic column" "23" \
   "$(B | awk '/^  SEV/ {print index($0, "RIG"); exit}')"

echo "── hermetic: empty board ──"
EMPTY="$(mktemp -d)"; : > "$EMPTY/anchors.ndjson"; cp "$FXDIR/rigs.json" "$EMPTY/rigs.json"; printf '{}' > "$EMPTY/sessions.json"
has  "empty board says nothing floats" "Nothing floats" "$(GC_HELM_FIXTURE="$EMPTY" "$TOOL" 2>/dev/null)"
eq   "empty board --json is []" "0" "$(GC_HELM_FIXTURE="$EMPTY" "$TOOL" --json | jq 'length')"
rm -rf "$EMPTY"

echo "── hermetic: failed gather → error + NO cache; legit-empty → cached quiet board ──"
# These drive the REAL (non-fixture) gather path through a stub `gc` placed at
# the front of a private PATH, with TMPDIR + GC_CITY_PATH pointed into the
# sandbox so the cache lands (or not) somewhere we can assert on hermetically.
# Nothing touches Dolt, the live city, or the operator's real cache dir.

# (a) Rigs enumerate fine, but EVERY per-rig/convoy query dies (the
# timeout/wedge/error shape). The board must print the explicit
# gather-failure line — NOT the quiet empty-board message —, exit non-zero,
# and write NO cache, so a transient failure can never be served as a false
# "0 anchors" all-clear for the cache TTL.
GF="$(mktemp -d)"; mkdir -p "$GF/bin" "$GF/rig/.beads" "$GF/tmp"
cat > "$GF/bin/gc" <<GCEOF
#!/bin/sh
case "\$1 \$2" in
  "rig list") printf '{"rigs":[{"name":"stubrig","path":"$GF/rig","prefix":"tk"}]}\n' ;;
  *) exit 1 ;;
esac
GCEOF
chmod +x "$GF/bin/gc"
ec=0
FOUT="$(TMPDIR="$GF/tmp" GC_CITY_PATH="$GF/city" PATH="$GF/bin:$PATH" "$TOOL" board 2>&1)" || ec=$?
eq     "failed gather exits non-zero (3)"             "3"             "$ec"
has    "failed gather prints the explicit error line" "gather failed" "$FOUT"
absent "failed gather never reads as a quiet board"   "Nothing floats" "$FOUT"
# Glob the cache format-AGNOSTICALLY ('board*', not 'board-*'). The file name
# carries the format on purpose, so it CHANGES whenever the cache layout does
# (tk-fkeft bumped it to board2-). A glob pinned to one format stops matching
# at that moment — and because both of these assertions expect to find NOTHING,
# they would keep passing while measuring nothing at all.
eq     "failed gather writes NO cache file"           ""              "$(find "$GF/tmp" -name 'board*' -type f 2>/dev/null)"
rm -rf "$GF"

# (b) Control: a legitimately EMPTY board (every query answers, with valid
# empty JSON) still prints the quiet message, exits 0, and IS cached.
GE="$(mktemp -d)"; mkdir -p "$GE/bin" "$GE/rig/.beads" "$GE/tmp"
cat > "$GE/bin/gc" <<GCEOF
#!/bin/sh
case "\$1 \$2" in
  "rig list")     printf '{"rigs":[{"name":"stubrig","path":"$GE/rig","prefix":"tk"}]}\n' ;;
  "bd list")      printf '[]\n' ;;
  "convoy list")  printf '{"convoys":[]}\n' ;;
  "session list") printf '{"sessions":[]}\n' ;;
  *) printf '[]\n' ;;
esac
GCEOF
chmod +x "$GE/bin/gc"
ec=0
EOUT="$(TMPDIR="$GE/tmp" GC_CITY_PATH="$GE/city" PATH="$GE/bin:$PATH" "$TOOL" board 2>&1)" || ec=$?
eq  "legit empty board exits 0"                   "0"              "$ec"
has "legit empty board prints the quiet message"  "Nothing floats" "$EOUT"
eq  "legit empty board IS cached (1 cache file)"  "1"              "$(find "$GE/tmp" -name 'board*' -type f 2>/dev/null | wc -l | tr -d ' ')"
EOUT2="$(TMPDIR="$GE/tmp" GC_CITY_PATH="$GE/city" PATH="$GE/bin:$PATH" "$TOOL" board 2>&1 || true)"
has "second glance serves from the cache"         "cached"         "$EOUT2"

echo "── hermetic: no timeout/gtimeout on PATH → board degrades, does not die ──"
# Stock-macOS shape: neither GNU timeout nor gtimeout exists. Build a minimal
# command sandbox (symlinks to only the tools the board needs + the stub gc
# from (b)) and run with PATH set to ONLY that dir — with_timeout must fall
# through to running the command unbounded instead of the old hard death
# ("[: : integer expression expected" + jq --argjson garbage).
NT="$(mktemp -d)"; mkdir -p "$NT/bin" "$NT/tmp"
for c in jq date mktemp rm cat head tail sed mkdir mv id cksum cut readlink dirname sort tr uniq wc; do
    p="$(command -v "$c" 2>/dev/null || true)"; [ -n "$p" ] && ln -s "$p" "$NT/bin/$c"
done
ln -s "$GE/bin/gc" "$NT/bin/gc"
if PATH="$NT/bin" command -v timeout >/dev/null 2>&1 || PATH="$NT/bin" command -v gtimeout >/dev/null 2>&1; then
    printf '  skip  timeout-less PATH case (sandbox unexpectedly resolves a timeout)\n'
else
    ec=0
    NOUT="$(TMPDIR="$NT/tmp" GC_CITY_PATH="$NT/city" PATH="$NT/bin" "$TOOL" board 2>&1)" || ec=$?
    eq     "no-timeout PATH: board still runs (exit 0)"        "0"                  "$ec"
    has    "no-timeout PATH: renders the quiet board"          "Nothing floats"     "$NOUT"
    absent "no-timeout PATH: no integer-expression crash"      "integer expression" "$NOUT"
    absent "no-timeout PATH: no jq --argjson garbage"          "invalid JSON text"  "$NOUT"
fi
rm -rf "$NT" "$GE"

echo "── hermetic: verb dispatch + fail-closed validation ──"
has  "help lists the open verb"  "open"  "$("$TOOL" help 2>&1 || true)"
ec=0; "$TOOL" open 2>/dev/null || ec=$?;            eq "open with no bead errors (exit 2)"        "2" "$ec"
ec=0; "$TOOL" bogus-verb 2>/dev/null || ec=$?;      eq "unknown verb errors (exit 2)"             "2" "$ec"
# takeaway: a thin metadata-writer verb; bead-id AND text
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
          GC_HELM_FIXTURE="$FXDIR" "$TOOL" react tk-epic --dry-run 2>&1 || true)"
    has    "react slings mol-first-reaction"          "--on mol-first-reaction"         "$RX"
    has    "react pins the codex-gated mr path"       "--merge mr"                      "$RX"
    absent "react never routes direct"                "--merge direct"                  "$RX"
    has    "react targets the rig-qualified pool"     "gc-toolkit/gc-toolkit.proactive" "$RX"
    has    "react passes the bead through to sling"   "tk-epic"                         "$RX"
    # --reason is accepted as operator intent but NOT forwarded (sling has none).
    RXR="$(GC_RIG=gc-toolkit GC_PROACTIVE_TOOL="$PROACTIVE_TOOL_REAL" GC_PROACTIVE_FIXTURE="$FXDIR" \
           GC_HELM_FIXTURE="$FXDIR" "$TOOL" react tk-epic --reason "pick a backend" --dry-run 2>&1 || true)"
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
            GC_HELM_FIXTURE="$FXDIR" "$TOOL" react tk-epic --dry-run 2>&1 || true)"
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
# `gc helm …` CLI that was never registered, so a bare invocation renders
# root gc help. Pack commands bind under the pack name (`gc <pack> <cmd>`), so
# no top-level helm subcommand can exist. The runnable surface is THIS
# script — reached via the prefix+b tmux picker (tmux-pick-helm.sh →
# gc-helm.sh) or run directly. These
# assertions lock the operator-facing docs to that reality.

# (a) the documented script entry actually runs and prints its own usage.
has  "script --help prints usage" "Usage:" "$("$TOOL" --help 2>&1 || true)"
has  "script -h prints usage"     "Usage:" "$("$TOOL" -h 2>&1 || true)"

# (b) no operator-facing surface file advertises the phantom CLI. The match is
#     the space-form ("gc helm …", incl. backtick-wrapped); the real
#     script name "gc-helm" (hyphen) is intentionally NOT matched.
SURFACE_FILES=(
    "$HERE/../assets/scripts/gc-helm.sh"
    "$HERE/../agents/converse/prompt.template.md"
    "$HERE/../agents/converse/agent.toml"
    "$HERE/../agents/converse/PROVENANCE.md"
)
phantom=""
for f in "${SURFACE_FILES[@]}"; do
    [ -f "$f" ] || continue
    hit="$(grep -nF 'gc helm' "$f" 2>/dev/null || true)"
    [ -n "$hit" ] && phantom+="$f: $hit"$'\n'
done
absent "no operator surface file advertises a phantom 'gc helm' CLI" "gc helm" "$phantom"

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

# Opt-in: a takeaway + takeaway --release round-trip on
# an operator-chosen bead. The fixture never invents or closes a bead — it writes
# only to the bead the operator named, and every leg self-cleans (the unset
# undoes takeaway; the --release leg captures and restores the
# bead's prior lifecycle fields and unsets the marker it set).
if [ -n "${GC_HELM_SMOKE_BEAD:-}" ]; then
    echo "── live (opt-in): takeaway + takeaway --release round-trip on $GC_HELM_SMOKE_BEAD ──"
    bead="$GC_HELM_SMOKE_BEAD"
    # takeaway: write the headline, read back the THREE metadata fields, then
    # unset them (the clean-up leg — takeaway has no inverse verb).
    "$TOOL" takeaway "$bead" "helm-surface-fixture smoke takeaway" --by host >/dev/null 2>&1 \
        && ok "takeaway $bead" || bad "takeaway $bead" "exit 0" "non-zero"
    eq "bead now carries the gc.takeaway headline" "helm-surface-fixture smoke takeaway" \
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
    "$TOOL" takeaway "$bead" "helm-surface-fixture release smoke" --by proactive --release >/dev/null 2>&1 \
        && ok "takeaway --release $bead" || bad "takeaway --release $bead" "exit 0" "non-zero"
    RELJSON="$(gc bd show "$bead" --json 2>/dev/null)"
    eq "release stamps the gc.takeaway headline"      "helm-surface-fixture release smoke" \
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
    printf '  skip  live takeaway round-trip (set GC_HELM_SMOKE_BEAD=<id> to run)\n'
fi

echo ""
echo "helm-surface-fixture: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
