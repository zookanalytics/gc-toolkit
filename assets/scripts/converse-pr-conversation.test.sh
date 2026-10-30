#!/usr/bin/env bash
# The subject under test is a shell block inside a markdown prompt, so these
# assertions EXTRACT the marked visit-pr-conversation block and EXECUTE it;
# prose that only describes the fetch cannot pass them.
#
# Hermetic: stubs `gc` and the universe tool, reads the repo only; no city, no
# network. The one live call is the real tool serving the tier name read out
# of the prompt — the seam a rename can break with neither file looking wrong.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
SUT="$REPO/assets/scripts/converse-pr-conversation.sh"
TOOL="$REPO/tools/gc-bd-universe.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "missing '$2' in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "found '$2' in: $3" ;; *) ok "$1" ;; esac; }

for f in "$SUT" "$TOOL"; do
    [ -r "$f" ] || { printf 'converse-pr-conversation: cannot read %s\n' "$f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || {
    printf 'converse-pr-conversation: jq is required to run the extracted block\n' >&2
    exit 1
}

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-pr-conversation-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; FIXDIR="$TMPD/fix"; RIGROOT="$TMPD/rig"; CITY="$TMPD/city"; BARE="$TMPD/bare"
mkdir -p "$BIN" "$FIXDIR" "$RIGROOT/tools" "$CITY" "$BARE"
# The script reaches the universe tool in the copy of the pack it runs from,
# under tools/ two levels above assets/scripts. PACK carries the tool and
# NOTOOL does not; the rig root and the city carry one each, so a script that
# looked there instead would find it.

echo "── the script is present and runnable ──"
if [ -x "$SUT" ]; then ok "converse-pr-conversation.sh is present and executable"
else bad "converse-pr-conversation.sh is present and executable" "missing or not +x: $SUT"; fi
if bash -n "$SUT" 2>/dev/null; then ok "converse-pr-conversation: valid bash"
else bad "converse-pr-conversation: valid bash" "bash -n failed"; fi

# A stub `gc` serving the one read the block makes. Anything else exits 2, so
# a block that grows a second read fails here instead of quietly reaching the
# live store from a test.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
[ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ] || exit 2
cat "$FIXDIR/subject.json"
STUB
chmod +x "$BIN/gc"

# A stand-in universe tool that records how it was invoked.
cat >"$RIGROOT/tools/gc-bd-universe.sh" <<'STUB'
#!/usr/bin/env bash
printf 'universe invoked with: %s\n' "$*"
STUB
chmod +x "$RIGROOT/tools/gc-bd-universe.sh"
PACK="$TMPD/pack"; NOTOOL="$TMPD/notool"
mkdir -p "$PACK/assets/scripts" "$PACK/tools" "$NOTOOL/assets/scripts" "$CITY/rigs/gc-toolkit/tools"
cp "$SUT" "$PACK/assets/scripts/"; cp "$SUT" "$NOTOOL/assets/scripts/"
cp "$RIGROOT/tools/gc-bd-universe.sh" "$PACK/tools/"; cp "$RIGROOT/tools/gc-bd-universe.sh" "$CITY/rigs/gc-toolkit/tools/"

# run <subject-json> <pack> — execute the script from <pack>'s assets/scripts,
# from a cwd that is not a git checkout.
run() {
    printf '%s' "$1" > "$FIXDIR/subject.json"
    ( cd "$BARE" && SUBJECT=tk-sub FIXDIR="$FIXDIR" GC_RIG_ROOT="$RIGROOT" GC_CITY_PATH="$CITY" \
        PATH="$BIN:$PATH" bash "$2/assets/scripts/converse-pr-conversation.sh" 2>&1 )
}

echo "── a subject carrying a PR gets its conversation fetched ──"
out="$(run '[{"metadata":{"pr_number":475,"branch":"polecat/x"}}]' "$PACK")"
has "pr_number: the universe tool is invoked" "universe invoked with:" "$out"
has "pr_number: the fetch names the subject and the conversation tier" \
    "fetch tk-sub conversation" "$out"

out="$(run '[{"metadata":{"pr_url":"https://github.com/o/r/pull/475"}}]' "$PACK")"
has "pr_url alone also triggers the fetch" "fetch tk-sub conversation" "$out"

echo "── a subject with no PR fetches nothing ──"
out="$(run '[{"metadata":{"branch":"polecat/x"}}]' "$PACK")"
is "no PR reference: nothing is invoked" "$out" ""

echo "── no tool in the pack is LOUD, not silent ──"
# A pack copy without the tool reads nothing, though the rig root and the city
# hold one. Reading nothing must not read as reading zero.
if [ -n "$(cd "$BARE" && git rev-parse --show-toplevel 2>/dev/null)" ]; then
    printf '  SKIP  no-tool case (the temp dir is inside a git checkout)\n'
else
    out="$(run '[{"metadata":{"pr_number":475}}]' "$NOTOOL")"
    has "no tool: says the conversation is unread" "UNREAD" "$out"
    has "no tool: hands over the paginate slurp, not a plain .[]?" "jq -s '[.[][]?]'" "$out"
    has "no tool: names the PR number it could not read" "475" "$out"

    out="$(run '[{"metadata":{"pr_url":"https://github.com/o/r/pull/475#discussion_r1"}}]' "$NOTOOL")"
    has "no tool: a fragment on the pull URL still yields a bare number" "gh pr view 475 --json" "$out"
    hasnt "no tool: the fragment does not ride into the command" "475#discussion_r1" "$out"

    out="$(run '[{"metadata":{"pr_url":"https://github.com/o/r/pull/475?w=1"}}]' "$NOTOOL")"
    has "no tool: a query string on the pull URL still yields a bare number" "pulls/475/comments" "$out"
    hasnt "no tool: the query string does not ride into the command" "475?w=1" "$out"
fi

echo "── the seam: the tier the prompt asks for is a tier the tool serves ──"
# Read the tier name out of the prompt rather than spelling it here: a test
# that named it itself would pass through a rename on both sides while the
# sitting asked for a tier nobody serves.
TIER="$(sed -n 's/.*fetch "\$SUBJECT" \([a-z_-]*\).*/\1/p' "$SUT" | head -1)"
is "the block names a tier" "$(test -n "$TIER" && echo yes || echo no)" "yes"
mkdir -p "$TMPD/emptyfix"
seam="$(GC_BD_UNIVERSE_FIXTURE="$TMPD/emptyfix" "$TOOL" fetch fx-absent "$TIER" 2>&1 || true)"
hasnt "the tool dispatches the tier the prompt asks for" "unknown tier" "$seam"

echo "── fetched conversation is data, never instructions ──"
hasnt "the script never evals what it fetched" "eval" "$(cat "$SUT")"

echo
echo "converse-pr-conversation: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
