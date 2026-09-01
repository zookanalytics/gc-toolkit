#!/usr/bin/env bash
# Tests for the two properties generated/seed-audit has to hold at a merge:
# --check-merge refuses a merge whose result would land a stale artifact, and
# the artifact's committed shape lets two branches that moved different inputs
# merge at all. Real git, no stubs: both are questions about trees, and stubbing
# git would leave the merge itself unexercised. Nothing here renders, so no
# `gc`, no city and no network are involved; the fixture's own copy of the
# renderer is only ever asked for a manifest.
#
# Covers: the clobber (a base that moved an input against a head whose render
# predates it) with the offending input named; the current case; a merge result
# carrying no audit; a head that widens the input set, which must be read under
# ITS definition and not this checkout's; the delegation itself, asserted on the
# argv the merged tree's renderer receives; the three cannot-tell exits
# (unresolvable rev, missing manifest, conflicting merge); and the merge shape,
# against a control carrying the repo-global line the manifest replaced.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub out git
PASS=0; FAIL=0

SUT="$HERE/render-seed-audit.sh"
R="$TMP/repo"

sources_of() { bash "$1/assets/scripts/render-seed-audit.sh" --root "$1" --print-sources; }
write_audit() { # <repo> — the artifact a render at this tree would commit
    mkdir -p "$1/generated/seed-audit"
    printf '# Seed audit\n\n- input manifest: `SOURCES.txt`\n' > "$1/generated/seed-audit/INDEX.md"
    sources_of "$1" > "$1/generated/seed-audit/SOURCES.txt"
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
printf 'fragment v1\n' > "$R/template-fragments/y.md"
git -C "$R" init -q -b c0
git -C "$R" config user.email test@example.invalid
git -C "$R" config user.name "test"
commit c0

git -C "$R" checkout -q -b base
printf 'fragment v2\n' > "$R/template-fragments/x.md"
commit "move a prompt input, render nothing"

echo "# a render made before the base moved is STALE at the merge"
git -C "$R" checkout -q -b stale c0
write_audit "$R"
commit "establish the audit at the old base"
out=$(check_merge base stale); rc=$?
eq "$rc" 1 "the clobber exits 1"
has "$out" "would be STALE at the merge of stale into base" "the verdict names both sides"
has "$out" "template-fragments/x.md" "the input the render never saw is named"
hasnt "$out" "template-fragments/y.md" "…and the input that did not move is not"
has "$out" "assets/scripts/render-seed-audit.sh && git add generated/seed-audit" "the remedy is spelled out"

echo "# a render made at the base is current"
on base; git -C "$R" checkout -q -b fresh
write_audit "$R"
commit "render at the base"
out=$(check_merge base fresh); rc=$?
eq "$rc" 0 "a current artifact exits 0"
has "$out" "seed audit is current at the merge of fresh into base" "…and says so"

echo "# a merge result carrying no audit has nothing to keep current"
out=$(check_merge base base); rc=$?
eq "$rc" 0 "no artifact in the merge result exits 0"
has "$out" "carries no seed audit" "…as a stated fact, not a silent pass"

echo "# the stub tree a pack carries before its first render is MISSING, not stale"
on base; git -C "$R" checkout -q -b stub
mkdir -p "$R/generated/seed-audit"
printf 'rendered on first install\n' > "$R/generated/seed-audit/README.md"
commit "the pre-render stub"
out=$(check_merge base stub); rc=$?
eq "$rc" 0 "a stub carrying neither INDEX.md nor SOURCES.txt exits 0"
has "$out" "carries no seed audit" "…for the stated reason, not by falling through a file test"

echo "# the input set is the MERGED TREE's to define, not this checkout's"
# A head that widens digest_inputs records SOURCES.txt under the wider set. Read
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
write_audit "$R"
commit "widen the input set and re-render"
out=$(check_merge base widened); rc=$?
eq "$rc" 0 "a widened input set is not a clobber"
mt=$(git -C "$R" merge-tree --write-tree base widened)
mkdir -p "$TMP/mt" && git -C "$R" archive --format=tar "$mt" | tar -x -C "$TMP/mt"
theirs=$(bash "$TMP/mt/assets/scripts/render-seed-audit.sh" --root "$TMP/mt" --print-sources)
ours=$(bash "$SUT" --root "$TMP/mt" --print-sources)
if [ "$ours" != "$theirs" ]; then ok "control: this checkout's renderer disagrees, so the delegation is load-bearing"
else bad "control: both renderers agree, so this case proves nothing"; fi

echo "# the merged tree's renderer is asked for a manifest, never a render"
on base; git -C "$R" checkout -q -b stubbed
LOG="$TMP/renderer.log"; : > "$LOG"
STUBBED_MANIFEST="$TMP/stubbed.txt"
sources_of "$R" > "$STUBBED_MANIFEST"
cat > "$R/assets/scripts/render-seed-audit.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$LOG"
cat "$STUBBED_MANIFEST"
STUB
mkdir -p "$R/generated/seed-audit"
printf '# Seed audit\n' > "$R/generated/seed-audit/INDEX.md"
cp "$STUBBED_MANIFEST" "$R/generated/seed-audit/SOURCES.txt"
commit "record what the gate asks the renderer for"
out=$(check_merge base stubbed); rc=$?
eq "$rc" 0 "the manifest the merged tree reports is the one compared"
has "$(cat "$LOG")" "--print-sources" "the merged tree's renderer was asked for a manifest"
hasnt "$(cat "$LOG")" "--check" "…and was never asked to render or self-check"

echo "# cannot-tell exits 2 rather than passing"
on base; git -C "$R" checkout -q -b nomanifest
write_audit "$R"
rm "$R/generated/seed-audit/SOURCES.txt"
commit "an audit that records no manifest"
out=$(check_merge base nomanifest); rc=$?
eq "$rc" 2 "an audit with no SOURCES.txt exits 2"
has "$out" "commits no SOURCES.txt" "…and says why"

out=$(check_merge base no-such-branch); rc=$?
eq "$rc" 2 "an unresolvable rev exits 2"
has "$out" "names no commit" "…and says which"

on c0; git -C "$R" checkout -q -b conflicting
printf 'fragment v3\n' > "$R/template-fragments/x.md"
write_audit "$R"
commit "move the same input the base moved"
out=$(check_merge base conflicting); rc=$?
eq "$rc" 2 "a conflicting merge exits 2"
has "$out" "does not merge into" "…rather than reporting on a tree that cannot exist"

out=$(bash "$SUT" --root "$R" --check-merge 2>&1); rc=$?
eq "$rc" 2 "--check-merge without its two revs exits 2"

# Both arms fail closed here; what the guard buys is the diagnosis, so the
# assertion is on the message rather than the exit.
out=$(TMPDIR=/nonexistent-under-test bash "$SUT" --root "$R" --check-merge base fresh 2>&1); rc=$?
eq "$rc" 2 "a scratch dir that cannot be made exits 2"
has "$out" "mktemp failed" "…naming the cause, not the tar failure downstream of it"

# ------------------------------------------------ the shape that has to merge
#
# The gate above is only half of what the artifact owes the merge queue. A
# repo-global line in a per-branch committed file moves on EVERY seed-input
# edit, so two pull requests touching two unrelated inputs collide there
# unconditionally and each landing forces a rebase of everything still open.
# The two inputs here are neighbours in sort order, which is the case a flat
# `<hash>  <path>` list still loses: git needs one unchanged line between two
# changes, and adjacent entries leave none.
echo "# two branches that moved different inputs merge"
two_branches() { # <suffix> <extra-line-writer> — returns 0 when the merge is clean
    local sfx="$1" extra="$2" b
    # The two branches have to MODIFY the artifact, which means a base that
    # already carries one: git calls add/add a whole-file conflict whatever the
    # content, and a fixture branching off the pre-render tree would pass the
    # control for a reason that has nothing to do with the line shape.
    on c0; git -C "$R" checkout -q -B "shape-base-$sfx" c0
    write_audit "$R"; "$extra" "$R"
    commit "establish the audit"
    for b in x y; do
        on "shape-base-$sfx"; git -C "$R" checkout -q -B "edit-$b-$sfx" "shape-base-$sfx"
        printf 'moved by %s\n' "$b" > "$R/template-fragments/$b.md"
        write_audit "$R"
        "$extra" "$R"
        commit "move template-fragments/$b.md"
    done
    git -C "$R" merge-tree --write-tree "edit-x-$sfx" "edit-y-$sfx" >/dev/null 2>&1
}
no_extra() { :; }
add_global_line() { printf -- '- source digest: `%s`\n' \
    "$(sources_of "$1" | sha256sum | cut -d' ' -f1)" >> "$1/generated/seed-audit/INDEX.md"; }

if two_branches shape no_extra; then ok "adjacent inputs, one record each: the merge is clean"
else bad "adjacent inputs still collide — the artifact re-serializes the merge queue"; fi

# The control proves the fixture can fail: the same two branches, with the one
# repo-global line this artifact was cured of added back.
if two_branches control add_global_line; then
    bad "control: a repo-global digest line merged, so the case above proves nothing"
else ok "control: the repo-global digest line these two never touched conflicts"; fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
