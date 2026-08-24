#!/usr/bin/env bash
# control-char-scrub.test.sh — the drift test for the shared control-character
# scrubber (tk-ic9odt, Target 4 of specs/tk-z9nln/consolidation-plan.md).
#
# WHAT IS SHARED AND WHY. Seven scripts scrub `bd --json` output before jq parses
# it, because a single stray control character aborts the whole parse and costs a
# whole store rather than one bead (tk-6kf6r). Until this test they were seven
# independent definitions under three names (`scrub`, `strip_ctrl`, `strip_ctl`)
# carrying TWO INCOMPATIBLE BYTE SETS: five spared TAB, and the two doctor checks
# — the layer least able to afford a silent parse difference — deleted it. Nothing
# noticed, because they were never treated as one thing.
#
# THE BYTE SET, and why TAB and CR are DELETED. Every C0 byte except LF goes. A
# sub-0x20 byte is invalid inside a JSON string, so a raw one reaching us is always
# corruption to drop and never payload — a TAB or CR that is genuine bead content
# arrives ESCAPED (\t, \r), two printable characters a byte filter cannot touch.
# Measured 2026-08-24 over 61.7 MB of `bd list --all --json --limit 0` drawn from the
# four readable rig stores (gc-toolkit, signal-loom, gascity, shutupandlisten; the
# city store refused the connection on a project-identity mismatch and is not
# counted): the ONLY raw C0 byte present anywhere is LF, used as pretty-print
# whitespace — raw TAB and raw CR do not occur at all, while 246 lines carry an
# escaped \t. So deleting TAB and CR costs nothing observable, and no host splits on
# either: all seven join their rows on US (0x1F), which this deletes too.
#
# WHY NOT SPARE TAB, which RFC 8259 does permit as whitespace between tokens. Because
# one caller demonstrably needs it gone, and the consolidation takes ONE byte set
# rather than keeping two. doctor/check-routed-work-claimable ships a fixture — see
# its run.test.sh §7b — feeding a bead whose notes contain a RAW tab; with TAB spared
# the parse aborts and the check degrades that whole store to "NOT checked", so a
# single tab-indented note anywhere would hide every strand in that rig. A checker is
# the layer least able to afford that, and (RESCUE) below pins the behaviour it
# depends on. LF is spared alone because it is the one C0 byte bd actually emits.
#
# The ~28 INLINE `tr -d` pipelines elsewhere in the pack still spare TAB. Folding
# those in is explicitly a different change (specs/tk-z9nln/consolidation-plan.md);
# this test governs the seven NAMED definitions, which are now one byte set.
#
# There is no sourced-library pattern in this pack, by design, so this mirrors the
# pack's existing answer to exactly that problem: one marked block copied verbatim,
# plus a test that makes a copy which drifts fail loudly instead of silently
# (assets/scripts/inflight-membership.test.sh, assets/scripts/gate-visit.test.sh).
#
# Covered:
#   (CANON)   the canonical copy exists, in detect-stalled-workflows.sh
#   (CENSUS)  every known host still carries a marked copy — a floor, so a copy
#             that goes missing fails here rather than drifting quietly
#   (DRIFT)   every copy is byte-identical to canonical
#   (VALID)   every copy is valid bash on its own
#   (BYTES)   the byte set is EXECUTED, not grepped: all 32 C0 bytes plus DEL are
#             fed through the extracted scrubber and the survivors named exactly.
#             This is the assertion a future eighth copy cannot quietly disagree with
#   (SEP)     0x1F is deleted — the property the US-joined row readers depend on,
#             and the one thing both historical byte sets already agreed about
#   (RESCUE)  a RAW in-string TAB is removed, so the payload parses — the property
#             doctor/check-routed-work-claimable's §7b fixture is built on, and the
#             reason this set deletes TAB rather than sparing it
#   (KEEP)    an escaped \t in bead content survives the scrub unaltered
#   (JSON)    executed round-trip: a payload carrying exotic C0 bytes parses only
#             after scrubbing, and pretty-printed JSON still parses after it
#   (NOROLL)  no shipped script defines a second control-char scrubber outside a
#             marked block — the eighth copy this test exists to prevent
#   (ONESET)  no NAMED scrubber anywhere in the pack carries a control-char byte
#             set other than canonical — the divergence this consolidation removed
# Hermetic: reads the repo only; no gc, no city, no Dolt.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SDIR="$REPO/assets/scripts"
DDIR="$REPO/doctor"
CANON_FILE="$SDIR/detect-stalled-workflows.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }

extract() {
    awk '/# >>> control-char-scrub/{f=1} /# <<< control-char-scrub/{print; f=0} f' "$1"
}

echo "── (CANON) the canonical copy ──"
CANON="$(extract "$CANON_FILE")"
if [ -n "$CANON" ]; then
    ok "canonical block present in detect-stalled-workflows.sh"
else
    bad "canonical block present in detect-stalled-workflows.sh" \
        "no marked block found — every assertion below would pass vacuously"
    echo; echo "control-char-scrub: $PASS passed, $((FAIL + 1)) failed"; exit 1
fi

echo "── (CENSUS)/(DRIFT)/(VALID) every copy ──"
# The known hosts. A floor rather than an exact list: adding a reader is expected,
# losing one is the regression.
HOSTS="$SDIR/detect-stalled-workflows.sh
$SDIR/detect-parked-dispositions.sh
$SDIR/backfill-operator-origin.sh
$SDIR/liveness-recheck.sh
$SDIR/liveness-sweep-precheck.sh
$DDIR/check-routed-work-claimable/run.sh
$DDIR/check-finalized-molecule-step-reoffer/run.sh"
COPIES=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    name="$(basename "$f")"
    # Every doctor check's file is run.sh, so a bare basename would name none of
    # them. Say which check it is.
    case "$f" in "$DDIR"/*) name="doctor/$(basename "$(dirname "$f")")/$name" ;; esac
    blk="$(extract "$f")"
    if [ -z "$blk" ]; then
        bad "(CENSUS) $name carries a marked copy" \
            "no # >>> control-char-scrub block — did it get unmarked or hand-rolled?"
        continue
    fi
    COPIES=$((COPIES + 1))
    ok "(CENSUS) $name carries a marked copy"
    if [ "$blk" = "$CANON" ]; then
        ok "(DRIFT) $name is byte-identical to canonical"
    else
        bad "(DRIFT) $name is byte-identical to canonical" \
            "$(diff <(printf '%s\n' "$CANON") <(printf '%s\n' "$blk") | head -12)"
    fi
    printf '%s\n' "$blk" > "$TMP/copy.sh"
    if bash -n "$TMP/copy.sh" 2>/dev/null; then
        ok "(VALID) $name copy is valid bash"
    else
        bad "(VALID) $name copy is valid bash" "bash -n failed"
    fi
done <<EOF
$HOSTS
EOF
if [ "$COPIES" -ge 7 ]; then
    ok "(CENSUS) every known host carries the block ($COPIES found)"
else
    bad "(CENSUS) every known host carries the block" "expected >=7, found $COPIES"
fi

# --- behaviour, run against the extracted block ------------------------------
# Grepping the definition's text would pass on a copy that says the right words and
# filters the wrong bytes, so the scrubber is EXECUTED. Everything below runs the
# canonical copy the same way a caller does: source it, pipe bytes through it.
printf '%s\n' "$CANON" > "$TMP/canon.sh"
# shellcheck disable=SC1091  # generated at test time
. "$TMP/canon.sh"

echo "── (BYTES) the byte set, executed ──"
# All 32 C0 bytes in order, then DEL (0x7F), then a printable. NUL cannot survive a
# shell variable, so the probe and its result stay in FILES and are compared as
# octal — a variable round-trip here would silently drop the very byte most worth
# asserting.
: > "$TMP/probe.bin"
i=0
while [ "$i" -lt 32 ]; do
    printf "\\$(printf '%03o' "$i")" >> "$TMP/probe.bin"
    i=$((i + 1))
done
printf '\177A' >> "$TMP/probe.bin"

scrub < "$TMP/probe.bin" > "$TMP/scrubbed.bin"
SURVIVORS="$(od -An -to1 -v < "$TMP/scrubbed.bin" | tr -s ' ' '\n' | grep -v '^$' | tr '\n' ' ')"
# LF alone of the C0 range — then DEL, then 'A'. TAB and CR are NOT here: sparing
# them is the divergence this consolidation closed, so a copy that reverted to the
# TAB-preserving set fails on this line first. DEL is deliberately in the
# expectation too: this set is C0-only, and a copy that widened it to 0x7F would be
# a different filter answering a different question.
eq "$SURVIVORS" "012 177 101 " "(BYTES) survivors are exactly LF, DEL, 'A'"

PROBE_N=$(wc -c < "$TMP/probe.bin" | tr -d ' ')
SCRUBBED_N=$(wc -c < "$TMP/scrubbed.bin" | tr -d ' ')
eq "$PROBE_N" "34" "(BYTES) probe carries all 32 C0 bytes plus DEL plus a printable"
eq "$SCRUBBED_N" "3" "(BYTES) 31 of the 34 bytes are deleted"

echo "── (SEP) the US separator is deleted ──"
# Five of these scripts join their rows on 0x1F and read them back with IFS set to
# it. That is only safe because the scrub already removed every raw 0x1F from the
# payload, so no bead's content can pose as a field separator. Both historical byte
# sets agreed here; a copy that stopped deleting 0x1F would silently shift fields.
printf 'a\037b' > "$TMP/sep.bin"
scrub < "$TMP/sep.bin" > "$TMP/sep.out"
eq "$(cat "$TMP/sep.out")" "ab" "(SEP) a raw 0x1F in the payload is removed"

echo "── (KEEP) escaped content survives ──"
# A tab that is genuine bead content is transported as the two printable characters
# backslash-t. If a copy ever "fixed" the byte set by reaching for that, this fails.
ESC='{"notes":"col1\tcol2"}'
eq "$(printf '%s' "$ESC" | scrub)" "$ESC" "(KEEP) an escaped \\t in JSON content is untouched"

echo "── (JSON) round-trip through jq ──"
if command -v jq >/dev/null 2>&1; then
    # A bead whose notes carry the exotic C0 bytes bd is known to emit. Invalid JSON
    # before the scrub, valid after — this is the whole reason the function exists.
    printf '{"id":"tk-1","notes":"a\002b\016c"}' > "$TMP/dirty.json"
    if jq -e . < "$TMP/dirty.json" >/dev/null 2>&1; then
        bad "(JSON) the dirty fixture is genuinely unparseable" \
            "jq accepted raw C0 bytes inside a string — the fixture proves nothing"
    else
        ok "(JSON) the dirty fixture is genuinely unparseable"
    fi
    scrub < "$TMP/dirty.json" > "$TMP/clean.json"
    eq "$(jq -r '.notes' < "$TMP/clean.json" 2>/dev/null)" "abc" \
        "(JSON) scrubbing makes it parse, keeping the printable payload"

    # Pretty-printed output indented with TAB and terminated with CRLF still parses
    # after the scrub. Deleting TAB and CR cannot break a JSON text: they are only
    # ever insignificant whitespace BETWEEN tokens, so removing them re-flows the
    # layout and changes nothing jq reads.
    printf '[\r\n\t{\r\n\t\t"id":\t"tk-2"\r\n\t}\r\n]' > "$TMP/pretty.json"
    scrub < "$TMP/pretty.json" > "$TMP/pretty.out"
    eq "$(jq -r '.[0].id' < "$TMP/pretty.out" 2>/dev/null)" "tk-2" \
        "(JSON) TAB/CR-formatted JSON still parses after the scrub"
else
    ok "(JSON) skipped — jq not on PATH"
fi

echo "── (RESCUE) a raw in-string TAB is removed ──"
# This is the arm that justifies the byte set, and the one a revert to the
# TAB-preserving variant would break. doctor/check-routed-work-claimable's run.test.sh
# §7b feeds exactly this shape — a bead whose notes carry a RAW tab plus another raw
# C0 byte — and requires the check to still report its finding. With TAB spared the
# document stays invalid, jq aborts, and the check degrades the entire store to
# "NOT checked": one tab-indented note would hide every strand in that rig.
if command -v jq >/dev/null 2>&1; then
    printf '[{"id":"a-7","notes":"tab\there\001and a NUL-ish byte"}]' > "$TMP/rawtab.json"
    if jq -e . < "$TMP/rawtab.json" >/dev/null 2>&1; then
        bad "(RESCUE) the raw-TAB fixture is genuinely unparseable" \
            "jq accepted a raw TAB inside a JSON string — the fixture proves nothing"
    else
        ok "(RESCUE) the raw-TAB fixture is genuinely unparseable"
    fi
    scrub < "$TMP/rawtab.json" > "$TMP/rawtab.out"
    eq "$(jq -r '.[0].id' < "$TMP/rawtab.out" 2>/dev/null)" "a-7" \
        "(RESCUE) scrubbing rescues the parse, so the bead is still seen"
    eq "$(jq -r '.[0].notes' < "$TMP/rawtab.out" 2>/dev/null)" "tabhereand a NUL-ish byte" \
        "(RESCUE) the raw TAB is deleted, not escaped or replaced"
else
    ok "(RESCUE) skipped — jq not on PATH"
fi

echo "── (NOROLL) the scrubber is defined ONCE ──"
# The way this class arrived: someone needs to scrub before jq, writes a local
# one-liner that is correct for their own site, and the next divergence is invisible
# until a pipeline downstream reads different fields than its neighbour. A second
# DEFINITION is that move, and it is what this arm refuses.
#
# Scoped to definitions, not uses. Roughly thirty INLINE `tr -d` pipelines scrub bd
# output across the pack without naming a function; those are call sites of the same
# byte set, not competing definitions, and folding them in is a different change.
#
# Swept across every shipped script, not just the known hosts: an eighth definition
# is exactly what this is for, and it would carry no marker to be found by. Test
# files are excluded — they quote and extract the block, they do not ship it.
#
# The search pattern is assembled from pieces rather than written out. The
# `*.test.sh` exclusion above is what actually keeps this file out of the sweep; the
# assembly is a second guard, so that a copy of this test living somewhere the
# exclusion does not reach still cannot match on its own search string.
DEF_OPEN='\(\)[[:space:]]*\{'
TR_DEL='tr[[:space:]]+-d[[:space:]]+.\\0'
SCRUB_DEF="$DEF_OPEN.*$TR_DEL"
NOROLL_CLEAN=1
for f in "$SDIR"/*.sh "$DDIR"/*/run.sh; do
    [ -f "$f" ] || continue
    case "$f" in *.test.sh) continue ;; esac
    name="$(basename "$f")"
    case "$f" in "$DDIR"/*) name="doctor/$(basename "$(dirname "$f")")/$name" ;; esac
    outside="$(awk '/# >>> control-char-scrub/{f=1} /# <<< control-char-scrub/{f=0; next} !f' "$f" \
                 | grep -nE "$SCRUB_DEF" || true)"
    [ -z "$outside" ] && continue
    NOROLL_CLEAN=0
    bad "(NOROLL) $name defines a control-char scrubber outside the marked block" \
        "$(printf '%s' "$outside" | head -4)"
done
[ "$NOROLL_CLEAN" -eq 1 ] && ok "(NOROLL) no second control-char scrubber definition in the pack"

echo "── (ONESET) every NAMED scrubber agrees, pack-wide ──"
# (NOROLL) sweeps assets/scripts and doctor/*/run.sh — where all seven originals
# live and where a copy-paste lands. This arm asks the same question of the REST of
# the shipped pack (tools, services, orders, formula bodies), which those globs
# never reach: is there a named control-char scrubber out there, and does its byte
# set match canonical?
#
# It is scoped to DEFINITIONS on purpose. Roughly 28 inline `tr -d` pipelines still
# spare TAB; folding those in is explicitly a different change
# (specs/tk-z9nln/consolidation-plan.md), and banning their byte set here would fail
# on code this bead is not touching.
#
# Test files are excluded — they quote and extract the block, they do not ship it.
CANON_TR="$(printf '%s' "$CANON" | grep -oE "tr[[:space:]]+-d[[:space:]]+'[^']*'" | head -1)"
if [ -n "$CANON_TR" ]; then
    ok "(ONESET) canonical tr expression extracted"
else
    bad "(ONESET) canonical tr expression extracted" \
        "could not read the tr call out of the canonical block — the sweep below would prove nothing"
fi
ONESET_CLEAN=1
ONESET_SEEN=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in *.test.sh) continue ;; esac
    # Named definitions only: `name() { ... tr -d '\0...' ... }` on one line.
    defs="$(grep -nE "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{[^}]*tr[[:space:]]+-d[[:space:]]+'[^']*\\\\0" "$f" || true)"
    [ -n "$defs" ] || continue
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        ONESET_SEEN=$((ONESET_SEEN + 1))
        got="$(printf '%s' "$d" | grep -oE "tr[[:space:]]+-d[[:space:]]+'[^']*'" | head -1)"
        [ "$got" = "$CANON_TR" ] && continue
        ONESET_CLEAN=0
        bad "(ONESET) ${f#"$REPO"/} defines a scrubber whose byte set is not canonical" \
            "got   $got
        want  $CANON_TR
        at    $(printf '%s' "$d" | cut -d: -f1)"
    done <<INNER
$defs
INNER
done <<OUTER
$(find "$REPO" -type f \( -name '*.sh' -o -name '*.toml' \) \
    -not -path "$REPO/.git/*" -not -path "$REPO/specs/*" 2>/dev/null | sort)
OUTER
if [ "$ONESET_SEEN" -lt 7 ]; then
    bad "(ONESET) the sweep found the known definitions" \
        "expected >=7 named scrubber definitions pack-wide, saw $ONESET_SEEN — the sweep is not reaching them"
elif [ "$ONESET_CLEAN" -eq 1 ]; then
    ok "(ONESET) all $ONESET_SEEN named scrubbers pack-wide carry the canonical byte set"
fi

echo
echo "control-char-scrub: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
