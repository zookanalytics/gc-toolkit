#!/usr/bin/env bash
# Hermetic test for resolve-salvage-branch.sh (tk-19213). Stubs `gc` (bd show,
# convoy status) on PATH and builds REAL git repos with a REAL origin, so every
# branch answer comes from an actual `git ls-remote`. No live city, Dolt, or
# network.
#
# THE BUG. Witness salvage reads `metadata.branch` off the ORPHANED BEAD. A
# graph.v2 STEP bead has no such key — the branch lives on the anchor, one hop
# away through the root's input convoy — so the salvage had no branch name to
# look for and searched remote refs for the workflow, convoy and session ids
# instead. No branch is named after any of those (a polecat branch is
# `polecat/<work-item-id>`), so the search could not match the branch it existed
# to find, and returned "nothing to salvage" over a complete, codex-green
# branch (step tk-bs8mv, 2026-08-13; the work later merged as PR #333).
#
# Covered:
#   (STEP)      THE REGRESSION — an orphaned step whose anchor has a live
#               `polecat/<id>` branch is NOT declared unsalvageable
#   (PREMISE)   the near-miss is real: the workflow/convoy/session ids match no
#               ref at all while `polecat/<anchor>` sits right there
#   (EXPLICIT)  an explicitly recorded `metadata.branch` outranks the naming
#               convention — a rejection-resume branch is deliberately not
#               `polecat/<id>`, and the recorded name is what the refinery merges
#   (OWN)       a plain work bead resolves off its own metadata, exactly as
#               before — the shape that already worked must not change
#   (SELFCONV)  a work bead whose branch metadata never landed is still found by
#               convention
#   (NONE)      anchor resolved, branch genuinely absent -> salvageable=0, quiet.
#               Case E must stay reachable or every orphan escalates forever
#   (LOUD-*)    every way the search can fail to name a branch exits NON-ZERO:
#               a convoy that is not a single member, a root with no convoy, a
#               root row that is gone, a remote that will not answer. "None
#               found" is a claim about a search that ran
#   (WORKDIR)   the anchor's work_dir reaches the caller, so Cases C/D can still
#               inspect the worktree the step bead never recorded
#   (IDKEYS)    the workflow/convoy/session searches are KEPT as additional
#               keys, reported separately as a weak signal — the fix adds a key,
#               it does not swap one blind key for another
#   (SESSIONKEY) the bare-form key is only derived for short-prefixed ids; a
#               session NAME must not contribute a junk substring to the scan
#   (WIRED)     the formula actually calls this script, in a marker block that is
#               backslash-free and parses as bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/resolve-salvage-branch.sh"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

# --- Stub city. ---------------------------------------------------------------
# `gc bd show <id> --json` and `gc convoy status <id> --json` answer from fixture
# files. A missing bead fixture returns bd's own error envelope, which is how an
# absent row actually reads.
mkdir -p "$TMP/bin" "$TMP/beads" "$TMP/convoys"
cat > "$TMP/bin/gc" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "bd show")
    f="$GC_TEST_FIXTURES/beads/$3.json"
    if [ -f "$f" ]; then cat "$f"; exit 0; fi
    echo '{"error":"no issues found matching the provided IDs"}'; exit 0 ;;
  "convoy status")
    f="$GC_TEST_FIXTURES/convoys/$3.json"
    if [ -f "$f" ]; then cat "$f"; exit 0; fi
    echo '{"error":"convoy not found"}'; exit 1 ;;
esac
echo "stub gc: unexpected call: $*" >&2
exit 1
EOF
chmod +x "$TMP/bin/gc"
export GC_TEST_FIXTURES="$TMP"
PATH="$TMP/bin:$PATH"
export PATH

bead() {
  # bead <id> <metadata-json>
  printf '[{"id":"%s","metadata":%s}]\n' "$1" "$2" > "$TMP/beads/$1.json"
}
convoy() {
  # convoy <id> <child-id>...  (zero, one or many members)
  local id="$1"; shift
  local kids=""
  for k in "$@"; do kids="${kids:+$kids,}{\"id\":\"$k\"}"; done
  printf '{"id":null,"children":[%s]}\n' "$kids" > "$TMP/convoys/$id.json"
}

# --- A real repo with a real origin. ------------------------------------------
ORIGIN="$TMP/origin.git"
git init -q --bare "$ORIGIN"
RIG="$TMP/rig"
git init -q "$RIG"
git -C "$RIG" config user.email t@t
git -C "$RIG" config user.name t
git -C "$RIG" remote add origin "$ORIGIN"
echo base > "$RIG/f.txt"
git -C "$RIG" add -A
git -C "$RIG" commit -qm base
git -C "$RIG" push -q origin HEAD:refs/heads/main

publish() {
  # publish <branch> — put a distinct commit on origin under that branch name.
  git -C "$RIG" checkout -q -B tmpwork main
  echo "$1" > "$RIG/f.txt"
  git -C "$RIG" commit -q -am "work for $1"
  git -C "$RIG" push -q origin "HEAD:refs/heads/$1"
  git -C "$RIG" checkout -q main
}

run() {
  # run <bead-id> [repo-root] -> stdout of the resolver; RC holds its exit status
  local repo="${2:-$RIG}"
  set +e
  OUT="$("$SCRIPT" --bead "$1" --repo-root "$repo" 2>/dev/null)"
  RC=$?
  set -e
  printf '%s' "$OUT"
}
field() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }

# --- Fixtures: one workflow whose step is orphaned. ---------------------------
# step -> root -> input convoy -> the single tracked member (the work item).
bead tk-step '{"gc.step_ref":"mol-polecat-work.load-context","gc.root_bead_id":"tk-root","gc.session_id":"lx-sess","gc.session_name":"gc-toolkit__polecat-lx-sess"}'
bead tk-root '{"gc.input_convoy_id":"tk-convoy","gc.kind":"workflow"}'
convoy tk-convoy tk-anchor
bead tk-anchor '{"work_dir":"/w/tk-anchor"}'

publish "polecat/tk-anchor"

# (STEP) The regression. Before the fix this bead had no branch name at all and
# fell through to Case E.
run tk-step >/dev/null
eq "$RC" "0"                        "(STEP) resolver exits 0 on a resolvable step"
eq "$(field anchor)" "tk-anchor"    "(STEP) anchor resolved root -> convoy -> single member"
eq "$(field branch)" "polecat/tk-anchor" \
                                    "(STEP) branch resolved to the polecat/<work-item-id> convention"
eq "$(field salvageable)" "1"       "(STEP) orphaned step over a live branch is NOT declared unsalvageable"
eq "$(field match)" "exact"         "(STEP) the hit is an exact ref match, not a substring guess"
[ -n "$(field branch_sha)" ] \
  && ok "(STEP) reports the branch sha on origin" \
  || bad "(STEP) branch_sha empty for a branch that exists"

# (WORKDIR) The step records no worktree; the anchor's must reach the caller, or
# Cases C and D still have nothing to look at.
eq "$(field work_dir)" "/w/tk-anchor" "(WORKDIR) anchor's work_dir surfaces for a step bead"

# (PREMISE) The near-miss, asserted rather than assumed: searching the ids the
# step DOES carry finds nothing, while the branch is sitting on origin.
for id in tk-root root tk-convoy convoy lx-sess sess; do
  if grep -q -- "$id" < <(git -C "$RIG" ls-remote --heads origin 2>/dev/null); then
    bad "(PREMISE) expected no ref matching '$id'"
  fi
done
ok "(PREMISE) workflow/convoy/session ids match no ref, while polecat/tk-anchor exists"

# (IDKEYS) Those searches are kept as ADDITIONAL keys, not dropped. A ref that
# does match one is reported — separately, as the weak signal it is.
# Compared field-by-field, never by substring: every bare form is a substring of
# the full id it came from, so a substring check cannot tell the two apart and
# would pass whether or not the key it names was actually derived.
has_key() {
  local k
  for k in $(field id_keys); do
    [ "$k" = "$1" ] && return 0
  done
  return 1
}
has_key "tk-root" \
  && ok "(IDKEYS) workflow id still searched as an additional key" \
  || bad "(IDKEYS) workflow id key was dropped"
has_key "tk-convoy" \
  && ok "(IDKEYS) convoy id still searched as an additional key" \
  || bad "(IDKEYS) convoy id key was dropped"
has_key "sess" \
  && ok "(IDKEYS) session id searched in its bare form too (the near-miss's form)" \
  || bad "(IDKEYS) bare session-id form was dropped"

# (SESSIONKEY) but the bare form is only derived where it means something. The
# session NAME's first component is `gc`, and `toolkit__polecat-lx-sess` is not
# an id — a junk key in a substring scan is how false hits get made. The full
# session name is a legitimate key and stays.
has_key "toolkit__polecat-lx-sess" \
  && bad "(SESSIONKEY) junk bare form derived from a session name" \
  || ok "(SESSIONKEY) no junk bare form derived from a session name"
has_key "gc-toolkit__polecat-lx-sess" \
  && ok "(SESSIONKEY) the full session name is still a key" \
  || bad "(SESSIONKEY) full session name key was dropped"

publish "wip/tk-root-scratch"
run tk-step >/dev/null
eq "$(field branch)" "polecat/tk-anchor" \
                                    "(IDKEYS) a weak id-key hit never displaces the exact match"
grep -q "wip/tk-root-scratch" < <(field candidate_refs) \
  && ok "(IDKEYS) id-key hits are reported as candidate_refs" \
  || bad "(IDKEYS) id-key hit was not reported"

# (EXPLICIT) An explicitly recorded branch outranks the convention. Both exist on
# origin here, so only priority can decide it.
bead tk-anchor '{"work_dir":"/w/tk-anchor","branch":"recovery/tk-anchor-a0468f9"}'
publish "recovery/tk-anchor-a0468f9"
run tk-step >/dev/null
eq "$(field branch)" "recovery/tk-anchor-a0468f9" \
                                    "(EXPLICIT) recorded metadata.branch outranks polecat/<id>"
eq "$(field salvageable)" "1"       "(EXPLICIT) still salvageable"
bead tk-anchor '{"work_dir":"/w/tk-anchor"}'

# (OWN) The shape that already worked: a plain work bead carrying its own branch.
# No anchor hop is needed and none is required.
bead tk-plain '{"branch":"polecat/tk-anchor","work_dir":"/w/tk-plain"}'
run tk-plain >/dev/null
eq "$RC" "0"                        "(OWN) plain work bead resolves"
eq "$(field branch)" "polecat/tk-anchor" "(OWN) own metadata.branch is used"
eq "$(field anchor)" ""             "(OWN) no anchor hop attempted for a non-step bead"
eq "$(field salvageable)" "1"       "(OWN) unchanged behavior for the shape that worked"

# (SELFCONV) A work bead whose branch-metadata write was lost is still found by
# the convention on its own id.
publish "polecat/tk-lost"
bead tk-lost '{}'
run tk-lost >/dev/null
eq "$RC" "0"                        "(SELFCONV) bead with empty metadata resolves"
eq "$(field branch)" "polecat/tk-lost" "(SELFCONV) convention on the bead's own id is searched"

# (NONE) Case E must stay reachable. An anchor that resolved and a branch that
# genuinely is not there is a quiet, legitimate "nothing to salvage".
bead tk-step2 '{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root2"}'
bead tk-root2 '{"gc.input_convoy_id":"tk-convoy2"}'
convoy tk-convoy2 tk-anchor2
bead tk-anchor2 '{}'
run tk-step2 >/dev/null
eq "$RC" "0"                        "(NONE) genuine absence is not an error"
eq "$(field salvageable)" "0"       "(NONE) reports nothing to salvage"
eq "$(field resolution)" "ok"       "(NONE) resolution is ok — the search actually ran"
eq "$(field anchor)" "tk-anchor2"   "(NONE) and it ran against the resolved anchor"

# (LOUD-CONVOY) A convoy that is not exactly one tracked member is a shape this
# pass does not understand. Guessing attributes one work item's branch to
# another; the cheap failure is to say so and skip.
bead tk-step3 '{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root3"}'
bead tk-root3 '{"gc.input_convoy_id":"tk-convoy3"}'
convoy tk-convoy3 tk-a tk-b
run tk-step3 >/dev/null
eq "$RC" "3"                        "(LOUD-CONVOY) multi-member convoy exits 3, not 0"
eq "$(field resolution)" "unresolved-anchor" "(LOUD-CONVOY) resolution names the failure"
eq "$(field salvageable)" "unknown" "(LOUD-CONVOY) never claims 'nothing to salvage'"

convoy tk-convoy3
run tk-step3 >/dev/null
eq "$RC" "3"                        "(LOUD-CONVOY) empty convoy exits 3 too"

# (LOUD-NOCONVOY) A root that records no input convoy.
bead tk-step4 '{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-root4"}'
bead tk-root4 '{"gc.kind":"workflow"}'
run tk-step4 >/dev/null
eq "$RC" "3"                        "(LOUD-NOCONVOY) root with no input convoy exits 3"
eq "$(field convoy)" ""             "(LOUD-NOCONVOY) and reports the empty link"

# (LOUD-ROOTGONE) The root row is not in the store. Unreadable is not absence:
# the branch may well be there, we just cannot name it.
bead tk-step5 '{"gc.step_ref":"mol-polecat-work.implement","gc.root_bead_id":"tk-missing"}'
run tk-step5 >/dev/null
eq "$RC" "4"                        "(LOUD-ROOTGONE) missing root row exits 4"
eq "$(field resolution)" "unreadable" "(LOUD-ROOTGONE) resolution says the store did not answer"
eq "$(field salvageable)" "unknown" "(LOUD-ROOTGONE) never claims 'nothing to salvage'"

# (LOUD-BEADGONE) Same for the orphaned bead itself.
run tk-nosuchbead >/dev/null
eq "$RC" "4"                        "(LOUD-BEADGONE) unreadable bead exits 4"

# (LOUD-NOREMOTE) A remote that does not answer must not read as "no branches".
# This is the same false all-clear one layer down, and the reason the exit
# status of ls-remote is checked at all.
DEAF="$TMP/deaf"
git init -q "$DEAF"
git -C "$DEAF" remote add origin "$TMP/does-not-exist.git"
run tk-plain "$DEAF" >/dev/null
eq "$RC" "4"                        "(LOUD-NOREMOTE) unreachable origin exits 4"
eq "$(field resolution)" "no-remote" "(LOUD-NOREMOTE) resolution says the remote did not answer"
eq "$(field salvageable)" "unknown" "(LOUD-NOREMOTE) never claims 'nothing to salvage'"

# (LOUD-NOREPO) No repository at all -> the question cannot be asked. Run from a
# directory outside any repository and with GC_RIG_ROOT unset, or the resolver's
# cwd fallback would legitimately find one.
set +e
OUT="$(cd "$TMP" && env -u GC_RIG_ROOT "$SCRIPT" --bead tk-plain --repo-root "$TMP/not-a-repo" 2>/dev/null)"
RC=$?
set -e
eq "$RC" "4"                         "(LOUD-NOREPO) no resolvable repository exits 4"
eq "$(field resolution)" "no-repo"   "(LOUD-NOREPO) resolution says there was no repository"
eq "$(field salvageable)" "unknown"  "(LOUD-NOREPO) never claims 'nothing to salvage'"

# (USAGE) Missing --bead is a usage error, distinct from every salvage verdict.
set +e
"$SCRIPT" >/dev/null 2>&1
USAGE_RC=$?
set -e
eq "$USAGE_RC" "2" "(USAGE) missing --bead exits 2"

# --- (WIRED) The formula must actually call this. -----------------------------
# A resolver nothing invokes fixes nothing. These are static guards over the
# witness patrol's salvage step.
grep -q "resolve-salvage-branch.sh" "$TOML" \
  && ok "(WIRED) mol-witness-patrol invokes resolve-salvage-branch.sh" \
  || bad "(WIRED) formula does not invoke resolve-salvage-branch.sh"

BLOCK="$(awk '
  /# >>> salvage-anchor-resolve/ {f=1; next}
  /# <<< salvage-anchor-resolve/ {f=0}
  f' "$TOML")"
[ -n "$BLOCK" ] \
  && ok "(WIRED) salvage-anchor-resolve block extracted between its markers" \
  || bad "(WIRED) block extraction EMPTY — markers missing from $TOML"

printf '%s\n' "$BLOCK" > "$TMP/block.sh"
bash -n "$TMP/block.sh" \
  && ok "(WIRED) extracted block is syntactically valid bash" \
  || bad "(WIRED) extracted block failed bash -n"

# The formula description is a TOML triple-quoted string: a trailing backslash is
# a line-ending escape that silently collapses the snippet the agent actually
# runs, so the raw text this test checks and the rendered text the witness runs
# would differ. Write the block with no backslash at all.
# Matched as a FIXED string: the bracket-expression form of this pattern is a
# syntax error under some greps on PATH, and a test that errors out reads as a
# pass under `||`.
grep -qF '\' < <(printf '%s\n' "$BLOCK") \
  && bad "(WIRED) extracted block contains a backslash — raw and rendered text will differ" \
  || ok "(WIRED) extracted block is backslash-free"

# The loud exit statuses are only worth anything if Case E is gated on them.
grep -q "SALVAGE_RC" < <(printf '%s\n' "$BLOCK") \
  && ok "(WIRED) block captures the resolver's exit status" \
  || bad "(WIRED) block ignores the resolver's exit status"

# (STEPCLOSE) Resolving a branch for a step bead makes Step 3's "already on main
# -> close the bead" arm reachable for steps, which it was not before: the
# branch belongs to the ANCHOR, and closing `load-context` unblocks the
# pool-routed `workspace-setup` behind it. The close must stay gated.
grep -q 'if \[ -n "\$ANCHOR" \]; then' < <(cat "$TOML") \
  && ok "(STEPCLOSE) Step 3 guards the close on whether the branch came from an anchor" \
  || bad "(STEPCLOSE) Step 3 close is not guarded for step beads"
grep -q "Not closing the step" < <(cat "$TOML") \
  && ok "(STEPCLOSE) and says so — a step is retired by Step 3b, not by hand" \
  || bad "(STEPCLOSE) no instruction against closing the step"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
