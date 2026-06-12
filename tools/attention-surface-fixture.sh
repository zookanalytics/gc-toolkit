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
cat > "$LIVE/anchors.ndjson" <<'JSON'
{"id":"tk-hosted","title":"Hosted epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-08T00:00:00Z","description":"","progress":null,"children":[{"id":"tk-h1","status":"open","assignee":""},{"id":"tk-h2","status":"open","assignee":""}]}
{"id":"tk-lonely","title":"Unhosted epic","kind":"epic","source":"epic","rig":"gc-toolkit","prefix":"tk","priority":2,"updated_at":"2026-06-08T00:00:00Z","description":"","progress":null,"children":[{"id":"tk-l1","status":"open","assignee":""},{"id":"tk-l2","status":"open","assignee":""}]}
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

echo "── hermetic: --json contract stays additive (existing fields intact) ──"
for f in id rig kind title severity weight n_closed m_total open in_progress frontier needs rank_score; do
    eq "field '$f' present on every row" "true" "$(printf '%s' "$J" | jq -c "[.[]|has(\"$f\")]|all")"
done

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

# Opt-in: a full flag→board→clear round-trip on an operator-chosen bead.
if [ -n "${GC_ATTENTION_FLAG_SMOKE_BEAD:-}" ]; then
    echo "── live (opt-in): flag → board → clear round-trip on $GC_ATTENTION_FLAG_SMOKE_BEAD ──"
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
else
    printf '  skip  live flag→clear round-trip (set GC_ATTENTION_FLAG_SMOKE_BEAD=<id> to run)\n'
fi

echo ""
echo "attention-surface-fixture: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
