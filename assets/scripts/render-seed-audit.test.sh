#!/usr/bin/env bash
# Tests for the properties generated/seed-audit and its renderer have to hold.
# Two are about the artifact at a merge: --check-merge refuses a merge whose
# result would land a stale artifact, and the artifact's committed shape lets two
# branches that moved different inputs merge at all. Real git, no stubs: both are
# questions about trees, and stubbing git would leave the merge itself
# unexercised. Three are about the renderer: the gcq wrapper pins its working
# directory so the render resolves the synthetic city and not one discovered from
# the cwd it was invoked in, the render is one tree however TMPDIR spells the
# scratch directory, and INDEX.md's byte column holds the bare number whichever
# wc counted it. Three are refusals: --install-hook will not shadow a
# hand-installed hook, a render fails when an agent the pack owns renders the
# builtin worker prompt, and a render fails when the throwaway city's path
# survives the substitution. The cases that render run against a stub `gc` on
# PATH, so no real `gc`, no city and no network are involved; the fixture's own
# copy of the renderer is only ever asked for a manifest, and the hermeticity
# check reads the renderer's text.
#
# Covers: the clobber (a base that moved an input against a head whose render
# predates it) with the offending input named; the current case; a merge result
# carrying no audit; a head that widens the input set, which must be read under
# ITS definition and not this checkout's; a symlinked input, recorded under its
# own path and hashed through the link; the delegation itself, asserted on the
# argv the merged tree's renderer receives; the three cannot-tell exits
# (unresolvable rev, missing manifest, conflicting merge); the merge shape,
# against a control carrying the repo-global line the manifest replaced; the
# gcq wrapper's cwd pin; the hook install's refusal, for a hand-installed hook
# and for a listing that fails, against a control holding only a sample hook;
# the builtin-fallback guard, which holds the pack's own agents and not a
# builtin provider's; a TMPDIR spelled with a trailing slash, by its physical
# path and through a symlink, each against the tree a plain one renders; a city
# spelling no needle names, which fails the render; and a wc that pads its
# count, against the host's.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-render-seed-audit-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
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

echo "# a symlinked input is recorded under its own path, hashed through the link"
on base; git -C "$R" checkout -q -b linked
mkdir -p "$R/packs/p/template-fragments"
ln -s ../../../template-fragments/x.md "$R/packs/p/template-fragments/x.md"
record_of() { sources_of "$R" | grep -A1 -xF "$1" | sed -n 2p; }
eq "$(record_of packs/p/template-fragments/x.md)" "$(sha256sum "$R/template-fragments/x.md" | cut -d' ' -f1)" \
    "the link is an input, hashed as the file it resolves to"
ln -sfn ../../../template-fragments/y.md "$R/packs/p/template-fragments/x.md"
eq "$(record_of packs/p/template-fragments/x.md)" "$(sha256sum "$R/template-fragments/y.md" | cut -d' ' -f1)" \
    "…and a link moved to another file moves its record"

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

# ------------------------------------------------ the renderer's cwd hermeticity
#
# gcq is the one chokepoint every gc call passes through. `env -i` scrubs the
# environment but not the working directory, and `gc` discovers a city by walking
# up from cwd, so a render invoked from a worktree nested inside the live city
# could resolve that city rather than the synthetic one. The wrapper pins cwd to
# the synthetic city to close that path. This reads the wrapper's text rather than
# rendering: proving the behavior needs a gc binary and a city this suite does
# without, and a dropped pin is a text change the read catches.
echo "# gcq pins cwd so the render cannot inherit a city from the caller's cwd"
gcq_body="$(sed -n '/^gcq() {/,/^}/p' "$SUT")"
has "$gcq_body" 'cd "$CITY"' "gcq runs gc from the synthetic city, not the invoking cwd"
has "$gcq_body" 'env -i' "gcq still scrubs the environment"
has "$gcq_body" 'gc --city "$CITY"' "gcq still names the synthetic city explicitly"

# ------------------------------------------------ the hook install's refusal
#
# core.hooksPath replaces .git/hooks rather than layering onto it, so the install
# refuses while a hand-installed hook sits there. The listing that finds one has
# to work under BSD find as well as GNU find: a listing that comes back empty
# reads as "no hooks" and shadows the hook it was meant to protect. Run from the
# repo root, the way the install is run.
echo "# --install-hook refuses to shadow a hand-installed hook"
H="$TMP/hooked"
mkdir -p "$H"
printf 'name = "fixture"\n' > "$H/pack.toml"
git -C "$H" init -q
mkdir -p "$H/.git/hooks"
printf '#!/bin/sh\n' > "$H/.git/hooks/pre-commit.sample"
printf '#!/bin/sh\nexit 0\n' > "$H/.git/hooks/pre-push"
chmod +x "$H/.git/hooks/pre-push"
out=$(cd "$H" && bash "$SUT" --root "$H" --install-hook 2>&1); rc=$?
eq "$rc" 2 "a hand-installed hook refuses the install"
has "$out" "pre-push" "…and the refusal names it"
hasnt "$out" "pre-commit.sample" "…but not a sample git ships"
eq "$(git -C "$H" config --get core.hooksPath)" "" "…and core.hooksPath is left unset"
rm "$H/.git/hooks/pre-push"
# A find that fails stands in for any listing that cannot see the directory.
mkdir -p "$TMP/failing-find"
printf '#!/bin/sh\necho "find: listing refused" >&2\nexit 1\n' > "$TMP/failing-find/find"
chmod +x "$TMP/failing-find/find"
out=$(cd "$H" && PATH="$TMP/failing-find:$PATH" bash "$SUT" --root "$H" --install-hook 2>&1); rc=$?
eq "$rc" 2 "a hook listing that fails refuses the install"
has "$out" "hand-installed hooks there cannot be ruled out" "…and says why"
eq "$(git -C "$H" config --get core.hooksPath)" "" "…and core.hooksPath is still unset"
out=$(cd "$H" && bash "$SUT" --root "$H" --install-hook 2>&1); rc=$?
eq "$rc" 0 "control: with only a sample hook left, the install proceeds"
eq "$(git -C "$H" config --get core.hooksPath)" "assets/hooks" "…and points core.hooksPath at assets/hooks"

# ------------------------------------------------ the builtin-fallback guard
#
# An agent this pack owns that renders the builtin worker prompt fails the render,
# while a builtin-provider agent may render it. Which agents the pack owns comes
# from its agent.toml files, and that list has to come out the same under BSD and
# GNU find: an empty list holds no agent to the rule. A stub gc on PATH answers
# the render's calls, so this needs no real gc, no city and no network. The stub
# receives no environment through the render's env -i, so it reads what each
# agent primes to from files.
echo "# a pack agent that renders the builtin worker prompt fails the render"
P="$TMP/render-pack"
mkdir -p "$P/agents/alpha" "$TMP/stub-gc"
printf 'name = "fixture"\n' > "$P/pack.toml"
printf 'name = "alpha"\n' > "$P/agents/alpha/agent.toml"
printf '# alpha doctrine\n' > "$P/agents/alpha/prompt.template.md"
BUILTIN_WORKER='You are a worker agent in a Gas City workspace using the graph-first workflow'
cat > "$TMP/stub-gc/gc" <<STUB
#!/usr/bin/env bash
[ "\${1:-}" = --city ] && shift 2
case "\$1 \${2:-}" in
    "config show")  printf '[[agent]]\nname = "alpha"\n' ;;
    "agent list")   printf '{"agents":[{"name":"alpha"},{"name":"claude"}]}\n' ;;
    "formula list") printf 'mol-fixture\n' ;;
    "formula show") printf '# mol-fixture\n' ;;
    "prime alpha")  "$TMP/stub-gc/spell-city" < "$TMP/stub-gc/alpha.txt" ;;
    "prime claude") printf '%s\n' "$BUILTIN_WORKER" ;;
    *)              exit 1 ;;
esac
STUB
chmod +x "$TMP/stub-gc/gc"
# alpha's prompt names the city the way a real prime does. @@CITY@@ is gc's
# spelling of the path --city was given, which is gascity's
# pathutil.NormalizePathForCompare: cleaned, symlinks resolved, and the darwin
# /private/tmp and /private/var aliases collapsed. @@FOREIGN@@ is a spelling no
# rule derives, the city's own directory names under a root the render never
# saw. gcq runs every call from the city, so the working directory names it.
cat > "$TMP/stub-gc/spell-city" <<'STUB'
#!/usr/bin/env bash
city="$(pwd -P)"
if [ "$(uname -s)" = Darwin ]; then
    case "$city" in /private/tmp/*|/private/var/*) city="${city#/private}" ;; esac
fi
foreign="/elsewhere/$(basename "$(dirname "$city")")/$(basename "$city")"
sed -e "s|@@CITY@@|$city|g" -e "s|@@FOREIGN@@|$foreign|g"
STUB
chmod +x "$TMP/stub-gc/spell-city"
render_stub() { PATH="$TMP/stub-gc:$PATH" bash "$SUT" --root "$P" --out "$TMP/render-out" --jobs 1 2>&1; }

printf '# alpha doctrine\n' > "$TMP/stub-gc/alpha.txt"
out=$(render_stub); rc=$?
eq "$rc" 0 "control: the pack agent renders its own doctrine and the builtin claude its builtin prompt"
printf '%s\n' "$BUILTIN_WORKER" > "$TMP/stub-gc/alpha.txt"
out=$(render_stub); rc=$?
eq "$rc" 2 "the pack agent rendering the builtin worker prompt fails the render"
has "$out" "FAILED agent alpha (rendered a builtin fallback prompt" "…and names the agent and the reason"
hasnt "$out" "FAILED agent claude" "…while claude, which the pack does not own, still passes"

# ------------------------------------------------ the throwaway city's spellings
#
# The city is built under TMPDIR, and gc prints it under the path it resolves
# rather than the one it was handed. A TMPDIR ending in a slash (macOS sets one),
# one spelled by its physical path (/private/var on macOS), and one reached
# through a symlink must each render the tree a plain TMPDIR renders. Otherwise
# the random scratch path lands in the render, and --check calls the tree stale
# straight after the render that wrote it.
echo "# the city's path is substituted however TMPDIR spells it"
D="$(cd "$TMP" && pwd)/scratch"
mkdir -p "$D"
ln -s "$D" "$TMP/scratch-link"
render_under() { # <TMPDIR> <out>
    TMPDIR="$1" PATH="$TMP/stub-gc:$PATH" bash "$SUT" --root "$P" --out "$2" --jobs 1 2>&1
}
printf '# alpha doctrine\ncity: @@CITY@@/city.toml\n' > "$TMP/stub-gc/alpha.txt"
out=$(render_under "$D" "$TMP/city-plain"); rc=$?
eq "$rc" 0 "control: a render under a plain TMPDIR succeeds"
has "$(cat "$TMP/city-plain/agents/alpha.md" 2>/dev/null)" "city: [[CITY-ROOT]]/city.toml" \
    "…and substitutes the city's path"
for spelling in "a trailing slash|$D/" "its physical path|$(cd "$D" && pwd -P)" \
        "a symlink|$TMP/scratch-link"; do
    out=$(render_under "${spelling#*|}" "$TMP/city-other"); rc=$?
    eq "$rc" 0 "a TMPDIR spelled with ${spelling%%|*} renders"
    if diff -r "$TMP/city-plain" "$TMP/city-other" > /dev/null 2>&1; then
        ok "…the same tree as the plain TMPDIR"
    else
        bad "…a tree that differs from the plain TMPDIR's: $(diff -r "$TMP/city-plain" "$TMP/city-other" 2>&1 | head -4)"
    fi
    rm -rf "$TMP/city-other"
done

echo "# a spelling of the city that no needle names fails the render"
printf '# alpha doctrine\ncity: @@FOREIGN@@/city.toml\n' > "$TMP/stub-gc/alpha.txt"
out=$(render_under "$D" "$TMP/city-foreign"); rc=$?
eq "$rc" 2 "a city path that survives the substitution fails the render"
has "$out" "FAILED agent alpha (the throwaway city path survived normalization)" "…naming the agent"
has "$out" "city: /elsewhere/" "…and quoting the line that carries the path"
if [ -e "$TMP/city-foreign" ]; then bad "…but it wrote a tree anyway"; else ok "…and writes no tree"; fi

# ------------------------------------------------ the INDEX.md byte column
#
# BSD wc pads its count with leading blanks and GNU wc prints it bare. The
# stand-in pads on either host, so the case exercises the BSD shape under GNU
# too, and the row assertion holds on a host whose own wc pads.
echo "# a padded wc count reaches INDEX.md as the bare number"
mkdir -p "$TMP/padding-wc"
cat > "$TMP/padding-wc/wc" <<STUB
#!/usr/bin/env bash
printf '%8s\n' "\$("$(command -v wc)" "\$@" | tr -d ' ')"
STUB
chmod +x "$TMP/padding-wc/wc"
printf '# alpha doctrine\n' > "$TMP/stub-gc/alpha.txt"
out=$(render_under "$D" "$TMP/wc-host"); rc=$?
eq "$rc" 0 "control: a render with the host's wc succeeds"
out=$(TMPDIR="$D" PATH="$TMP/padding-wc:$TMP/stub-gc:$PATH" \
    bash "$SUT" --root "$P" --out "$TMP/wc-padded" --jobs 1 2>&1); rc=$?
eq "$rc" 0 "a render with a padding wc succeeds"
has "$(cat "$TMP/wc-padded/INDEX.md" 2>/dev/null)" '| [`alpha`](agents/alpha.md) | 17 | 4 |' \
    "…and its INDEX.md row carries the bare byte count"
if diff -r "$TMP/wc-host" "$TMP/wc-padded" > /dev/null 2>&1; then
    ok "…the same tree as the render with the host's wc"
else
    bad "…a tree that differs from the host wc's: $(diff -r "$TMP/wc-host" "$TMP/wc-padded" 2>&1 | head -4)"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
