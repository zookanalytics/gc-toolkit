#!/usr/bin/env bash
# Test for render-seed-audit.sh --check-merge — the merge-result freshness gate.
# Real git, no stubs: the mode is a question about trees, and stubbing git would
# leave the merge itself unexercised. Nothing here renders, so no `gc`, no city
# and no network are involved; the fixture's own copy of the renderer is only
# ever asked for a digest.
#
# Covers: the clobber (a base that moved an input against a head whose render
# predates it) with the offending input named; the current case; a merge result
# carrying no audit; a head that widens the input set, which must be read under
# ITS definition and not this checkout's; the delegation itself, asserted on the
# argv the merged tree's renderer receives; and the three cannot-tell exits
# (unresolvable rev, missing digest line, conflicting merge).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub out git
PASS=0; FAIL=0

SUT="$HERE/render-seed-audit.sh"
R="$TMP/repo"

digest_of() { bash "$1/assets/scripts/render-seed-audit.sh" --root "$1" --print-digest; }
write_index() { # <repo> <digest-line-body>
    mkdir -p "$1/generated/seed-audit"
    printf '# Seed audit\n\n- source digest: `%s`\n' "$2" > "$1/generated/seed-audit/INDEX.md"
}
on() { # <branch> — check out a branch with no residue from the last one
    git -C "$R" checkout -q "$1" && git -C "$R" clean -qfd
}
commit() { git -C "$R" add -A && git -C "$R" commit -q -m "$1"; }
check_merge() { bash "$SUT" --root "$R" --check-merge "$1" "$2" 2>&1; }

# ---------------------------------------------------------------- the fixture
#
# c0 is the shape a pack has before its first render: sources, the renderer, no
# artifact. `base` moves a prompt input off c0 and commits no render — the state
# a bypassed hook, a host without `gc`, or a replayed commit leaves behind. Every
# other branch answers that base.
mkdir -p "$R/agents" "$R/template-fragments" "$R/assets/scripts"
cp "$SUT" "$R/assets/scripts/render-seed-audit.sh"
printf 'name = "fixture"\n' > "$R/pack.toml"
printf '# agent a\n' > "$R/agents/a.md"
printf 'fragment v1\n' > "$R/template-fragments/x.md"
git -C "$R" init -q -b c0
git -C "$R" config user.email test@example.invalid
git -C "$R" config user.name "test"
commit c0

git -C "$R" checkout -q -b base
printf 'fragment v2\n' > "$R/template-fragments/x.md"
commit "move a prompt input, render nothing"

echo "# a render made before the base moved is STALE at the merge"
git -C "$R" checkout -q -b stale c0
write_index "$R" "$(digest_of "$R")"
commit "establish the audit at the old base"
out=$(check_merge base stale); rc=$?
eq "$rc" 1 "the clobber exits 1"
has "$out" "would be STALE at the merge of stale into base" "the verdict names both sides"
has "$out" "template-fragments/x.md" "the input the render never saw is named"
has "$out" "assets/scripts/render-seed-audit.sh && git add generated/seed-audit" "the remedy is spelled out"

echo "# a render made at the base is current"
on base; git -C "$R" checkout -q -b fresh
write_index "$R" "$(digest_of "$R")"
commit "render at the base"
out=$(check_merge base fresh); rc=$?
eq "$rc" 0 "a current artifact exits 0"
has "$out" "seed audit is current at the merge of fresh into base" "…and says so"

echo "# a merge result carrying no audit has nothing to keep current"
out=$(check_merge base base); rc=$?
eq "$rc" 0 "no artifact in the merge result exits 0"
has "$out" "carries no seed audit" "…as a stated fact, not a silent pass"

echo "# the digest is the MERGED TREE's to define, not this checkout's"
# A head that widens digest_inputs renders its INDEX.md under the wider set. Read
# with this checkout's older definition it would look stale for a reason that is
# not the clobber, so the mode must ask the tree under test.
on base; git -C "$R" checkout -q -b widened
mkdir -p "$R/docs"; printf 'doc\n' > "$R/docs/d.md"
python3 - "$R/assets/scripts/render-seed-audit.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'find "$root/agents" "$root/template-fragments" "$root/formulas" "$root/packs" \\'
assert s.count(old) == 1, "fixture patch no longer matches digest_inputs"
open(p, "w").write(s.replace(old, old[:-1] + '"$root/docs" \\'))
PY
write_index "$R" "$(digest_of "$R")"
commit "widen the input set and re-render"
out=$(check_merge base widened); rc=$?
eq "$rc" 0 "a widened input set is not a clobber"
mt=$(git -C "$R" merge-tree --write-tree base widened)
mkdir -p "$TMP/mt" && git -C "$R" archive --format=tar "$mt" | tar -x -C "$TMP/mt"
theirs=$(bash "$TMP/mt/assets/scripts/render-seed-audit.sh" --root "$TMP/mt" --print-digest)
ours=$(bash "$SUT" --root "$TMP/mt" --print-digest)
if [ "$ours" != "$theirs" ]; then ok "control: this checkout's renderer disagrees, so the delegation is load-bearing"
else bad "control: both renderers agree, so this case proves nothing"; fi

echo "# the merged tree's renderer is asked for a digest, never a render"
on base; git -C "$R" checkout -q -b stubbed
LOG="$TMP/renderer.log"; : > "$LOG"
cat > "$R/assets/scripts/render-seed-audit.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$LOG"
echo deadbeef
STUB
write_index "$R" deadbeef
commit "record what the gate asks the renderer for"
out=$(check_merge base stubbed); rc=$?
eq "$rc" 0 "the digest the merged tree reports is the one compared"
has "$(cat "$LOG")" "--print-digest" "the merged tree's renderer was asked for a digest"
hasnt "$(cat "$LOG")" "--check" "…and was never asked to render or self-check"

echo "# cannot-tell exits 2 rather than passing"
on base; git -C "$R" checkout -q -b nodigest
write_index "$R" "x"
sed -i 's/^- source digest.*$/- source digest: none/' "$R/generated/seed-audit/INDEX.md"
commit "an INDEX.md that records no digest"
out=$(check_merge base nodigest); rc=$?
eq "$rc" 2 "an unverifiable INDEX.md exits 2"
has "$out" "records no source digest" "…and says why"

out=$(check_merge base no-such-branch); rc=$?
eq "$rc" 2 "an unresolvable rev exits 2"
has "$out" "names no commit" "…and says which"

on c0; git -C "$R" checkout -q -b conflicting
printf 'fragment v3\n' > "$R/template-fragments/x.md"
write_index "$R" "$(digest_of "$R")"
commit "move the same input the base moved"
out=$(check_merge base conflicting); rc=$?
eq "$rc" 2 "a conflicting merge exits 2"
has "$out" "does not merge into" "…rather than reporting on a tree that cannot exist"

out=$(bash "$SUT" --root "$R" --check-merge 2>&1); rc=$?
eq "$rc" 2 "--check-merge without its two revs exits 2"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
