#!/usr/bin/env bash
# control-char-scrub.test.sh — regression test for the one control-character
# scrubber and every copy of it (precedent: gate-visit.test.sh).
#
# Formula bodies and pack scripts have no include mechanism, so the scrubber
# lives as marker-delimited copies (# >>> control-char-scrub / # <<<). This
# test extracts every copy from assets/scripts, doctor and overlays, and
# asserts what the pack pays for when they disagree:
#   - one byte set, asserted by EXECUTING the block over every C0 byte
#     rather than by matching its text;
#   - the rescue property doctor/check-state-space depends on: a raw TAB
#     inside a JSON string must not cost the whole payload;
#   - no in-script inline scrub outside the fence;
#   - no dead call: a scrub reached by a name the file defines nowhere, which
#     `bash -n` passes and only the branch reaching the call ever reports;
#   - the lint enforcement (tools/lint-learned.d/inline-ctrl-scrub.sh)
#     still fires on each shape it exists to catch.
#
# The detector is a shape check, run by tools/lint-learned.sh over every
# tracked file; this suite proves what a shape check cannot — that the block
# behaves on every byte, and that all its copies are one block.
# Hermetic: reads the repo only; no gc, no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
[ -d "$REPO/doctor" ] || REPO="$HERE/../.."
SDIR="$REPO/assets/scripts"
DETECTOR="$REPO/tools/lint-learned.d/inline-ctrl-scrub.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-control-char-scrub-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

# Markers are anchored: a header sentence naming one is prose, not a fence.
extract() { awk '/^[[:space:]]*# >>> control-char-scrub[[:space:]]*$/{inb=1; next} /^[[:space:]]*# <<< control-char-scrub[[:space:]]*$/{inb=0} inb' "$1"; }

# Every pack shell file that could host a copy. Tests are excluded: a fixture
# may legitimately spell a byte set out to prove one.
hosts() {
    find "$REPO/assets/scripts" "$REPO/doctor" "$REPO/overlays" "$REPO/tools" \
        -name '*.sh' ! -name '*.test.sh' -type f 2>/dev/null \
        | grep -v '/lint-learned\.d/' | sort
}

echo "── 1. the canonical block ──"
CANON_HOST="$SDIR/merge.sh"
BLOCK="$(extract "$CANON_HOST")"
if [ -n "$BLOCK" ]; then ok "block present in $(basename "$CANON_HOST")"
else bad "block present in $(basename "$CANON_HOST")" "no marked block"; fi
printf '%s\n' "$BLOCK" > "$TMP/block.sh"
if bash -n "$TMP/block.sh" 2>/dev/null; then ok "block is valid bash"
else bad "block is valid bash" "bash -n failed"; fi

echo "── 2. every copy is byte-identical ──"
COPIES=0; DIVERGENT=0
while IFS= read -r f; do
    b="$(extract "$f")"
    [ -n "$b" ] || continue
    COPIES=$((COPIES + 1))
    if [ "$b" != "$BLOCK" ]; then
        DIVERGENT=$((DIVERGENT + 1))
        bad "$(basename "$f"): copy matches canonical" "block differs from $(basename "$CANON_HOST")"
    fi
done < <(hosts)
[ "$DIVERGENT" -eq 0 ] && ok "all $COPIES copies identical"
# A floor, not an equality: new hosts are expected, a host going missing is not.
if [ "$COPIES" -ge 27 ]; then ok "copy census $COPIES ≥ 27"
else bad "copy census $COPIES ≥ 27" "copies disappeared — was the helper inlined again?"; fi

echo "── 3. the byte set, executed ──"
# Feed every C0 byte plus DEL through the extracted block and name the
# survivors. Asserting behaviour, not text, is what makes this suite the
# authority on the byte set rather than a second copy of it.
gen_bytes() { local i; for i in $(seq 0 31) 127; do printf "\\$(printf '%03o' "$i")"; done; }
SURVIVORS="$(gen_bytes | ( eval "$BLOCK"; scrub ) | od -An -tu1 | tr -s ' ' '\n' | grep -v '^$' | tr '\n' ' ' | sed 's/ *$//')"
eq "$SURVIVORS" "10 127" "of every C0 byte and DEL, exactly LF (10) and DEL (127) survive"

echo "── 4. the rescue property ──"
# doctor/check-state-space/run.test.sh §8 feeds a bead whose notes carry a raw
# TAB. A raw C0 byte inside a JSON string is invalid JSON: sparing TAB aborts
# jq and degrades the whole store to "NOT checked", hiding every finding in it.
printf '[{"id":"a-10","notes":"tab\there"}]' > "$TMP/payload.json"
GOT="$( ( eval "$BLOCK"; scrub ) < "$TMP/payload.json" | jq -r '.[0].id' 2>/dev/null )"
eq "$GOT" "a-10" "a raw TAB in a JSON string still parses after the scrub"
# The control: a set that spares TAB loses that same payload, which is what
# makes deleting it load-bearing rather than incidental.
KEEP_TAB='\000-\010\013\014\016-\037'
GOT_TAB="$( tr -d "$KEEP_TAB" < "$TMP/payload.json" | jq -r '.[0].id' 2>/dev/null )"
if [ "$GOT_TAB" != "a-10" ]; then ok "a TAB-preserving set loses that same payload (control)"
else bad "a TAB-preserving set loses that same payload (control)" \
        "it parsed as '$GOT_TAB' — the fixture no longer carries a raw TAB, so §3 is unguarded"; fi

echo "── 5. no in-script scrub outside the fence ──"
# The detector holds the matcher. A second copy of it here would drift from
# the one it mirrors, which is the failure this suite exists to catch.
HOST_FILES=()
while IFS= read -r f; do HOST_FILES+=("$f"); done < <(hosts)
if [ "${#HOST_FILES[@]}" -eq 0 ]; then
    bad "no inline control-character scrub outside the fence" "hosts() matched no files"
elif STRAY_OUT="$("$DETECTOR" "${HOST_FILES[@]}" 2>&1)"; then
    ok "no inline control-character scrub outside the fence (${#HOST_FILES[@]} files)"
else
    bad "no inline control-character scrub outside the fence" "$STRAY_OUT"
fi

echo "── 6. the detector still catches each shape ──"
probe() { # <name> <expected-rc> <body>
    printf '%s\n' "$3" > "$TMP/probe.sh"
    "$DETECTOR" "$TMP/probe.sh" > "$TMP/probe.out" 2>&1; rc=$?
    eq "$rc" "$2" "detector: $1"
}
if [ -x "$DETECTOR" ]; then
    ok "detector is executable"
    # These fixtures ARE the shapes the detector exists to catch, so they are
    # assembled from variables: spelled out, this file would fail its own rule.
    CNTRL='[:cntrl:]'
    ALL_C0='\000-\037'
    TAB="$(printf '\t')"
    probe "flags an octal-range inline scrub" 1 \
        "x=\$(gc bd show z --json | tr -d '$KEEP_TAB')"
    probe "flags a [:cntrl:] inline scrub" 1 \
        "x=\$(gc bd show z --json | tr -d '$CNTRL')"
    probe "flags a double-quoted octal inline scrub" 1 \
        "x=\$(gc bd show z --json | tr -d \"$ALL_C0\")"
    probe "flags a double-quoted [:cntrl:] inline scrub" 1 \
        "x=\$(gc bd show z --json | tr -d \"$CNTRL\")"
    probe "flags an unquoted octal inline scrub" 1 \
        "x=\$(gc bd show z --json | tr -d $ALL_C0)"
    probe "flags an unquoted [:cntrl:] inline scrub" 1 \
        "x=\$(gc bd show z --json | tr -d $CNTRL)"
    probe "flags an inline scrub spelled tr<spaces>-d" 1 \
        "x=\$(gc bd show z --json | tr    -d '$ALL_C0')"
    probe "flags an inline scrub spelled tr<tab>-d" 1 \
        "x=\$(gc bd show z --json | tr${TAB}-d '$ALL_C0')"
    probe "flags a fenced copy with the wrong byte set" 1 \
        "# >>> control-char-scrub
scrub() { tr -d '$KEEP_TAB'; }
# <<< control-char-scrub"
    probe "flags a fenced copy respelled tr<spaces>-d" 1 \
        "# >>> control-char-scrub
scrub() { tr    -d '$KEEP_TAB'; }
# <<< control-char-scrub"
    probe "passes the canonical copy" 0 \
        "# >>> control-char-scrub
$BLOCK
# <<< control-char-scrub"
    probe "passes a portable snippet in another fence" 0 \
        "# >>> gate-visit
V=\$(gc bd show \"\$V\" --json | tr -d '$CNTRL')
# <<< gate-visit"
    probe "passes the shape quoted in a comment" 0 \
        "# prose citing tr -d '$ALL_C0' as an example"
    probe "passes a non-control tr -d" 0 "z=\$(printf x | tr -d '[:space:]')"

    # A dead call cannot be inferred from a shape, so the detector lists the
    # names the consolidation retired. Split across a concatenation here for
    # the same reason as the shapes above: spelled whole, this file would
    # carry the token its own rule forbids.
    RETIRED="strip_ct""l"
    RETIRED_ALT="strip_ct""rl"
    probe "flags a call to a retired helper name" 1 \
        "x=\$(gc bd show z --json | $RETIRED | jq .)"
    probe "flags the other retired spelling" 1 \
        "x=\$(gc bd show z --json | $RETIRED_ALT | jq .)"
    # The shape that reaches production: the fence is present and correct, and
    # a later edit calls the name it replaced.
    probe "flags a retired name in a file that also defines scrub" 1 \
        "# >>> control-char-scrub
$BLOCK
# <<< control-char-scrub
rows=\$(gc bd show z --json | scrub | jq .)
offered=\$(gc bd ready --json | $RETIRED | jq .)"
    probe "flags a retired name inside another fence" 1 \
        "# >>> gate-visit
V=\$(gc bd show \"\$V\" --json | $RETIRED)
# <<< gate-visit"
    probe "passes a retired name quoted in a comment" 0 \
        "# prose naming $RETIRED as the helper the consolidation replaced"
    probe "passes a longer identifier that merely contains one" 0 \
        "json_${RETIRED}_rows() { cat; }
x=\$(gc bd show z --json | json_${RETIRED}_rows)"

    probe "flags a | scrub the file defines nowhere" 1 \
        "x=\$(gc bd show z --json | scrub | jq .)"
    # The pack's prevailing call shape closes a command substitution, so the
    # call is terminated by `)` rather than by whitespace.
    probe "flags a | scrub closing a command substitution" 1 \
        "x=\$(gc bd show z --json | scrub)"
    probe "flags a | scrub terminated by a semicolon" 1 \
        "x=\$(gc bd show z --json | scrub); echo done"
    probe "passes a longer name that merely starts with scrub" 0 \
        "scrubbed() { cat; }
x=\$(gc bd show z --json | scrubbed)"
    probe "passes | scrub where the fenced copy defines it" 0 \
        "# >>> control-char-scrub
$BLOCK
# <<< control-char-scrub
x=\$(gc bd show z --json | scrub | jq .)"
    probe "passes | scrub defined below the call" 0 \
        "x=\$(gc bd show z --json | scrub | jq .)
# >>> control-char-scrub
$BLOCK
# <<< control-char-scrub"
    probe "flags | scrub where the fence carries no definition" 1 \
        "# >>> control-char-scrub
# <<< control-char-scrub
x=\$(gc bd show z --json | scrub | jq .)"
    probe "passes | scrub inside another fence" 0 \
        "# >>> gate-visit
V=\$(gc bd show \"\$V\" --json | scrub)
# <<< gate-visit"
    # The detector's own canonical constant must agree with the block, or it
    # would police a byte set the pack does not use.
    DET_CANON="$(sed -n 's/^CANON="\(.*\)"$/\1/p' "$DETECTOR")"
    eval "DET_CANON=\"$DET_CANON\""
    BLOCK_FN="$(printf '%s\n' "$BLOCK" | grep '^scrub() { tr -d')"
    eq "$DET_CANON" "$BLOCK_FN" "detector's canonical constant matches the block"
else
    bad "detector is executable" "missing or not executable: $DETECTOR"
fi

echo
echo "control-char-scrub: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
