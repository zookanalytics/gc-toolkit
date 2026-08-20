#!/usr/bin/env bash
# Hermetic test for the mr-aware Rejection Flow FAIL-CLOSED bead read
# (PR#204 signoff finding, review tk-h51jg).
#
# Both rejection arms of mol-refinery-patrol.toml — the `rebase` step (conflict)
# and the `handle-failures` step (test regression) — repool a rejected gating
# anchor AND must clear its `merge_result` so it drops out of merge-skill.sh's
# `merge_result=pull_request` scan. Left set on a repooled anchor with no rework
# child, the skill lands the un-gated rework — the exact hole this migration
# exists to close.
#
# The pre-fix code repooled UNCONDITIONALLY, then read merge_result in a SEPARATE
# `gc bd show ... 2>/dev/null | jq` that FAILS OPEN: `gc bd` writes errors to
# stderr and leaves stdout empty, so a read that failed AFTER the repool made
# `MR_STATE` empty, the `--unset-metadata merge_result` was silently skipped, and
# the anchor was left routed-to-polecat WITH merge_result still set.
#
# The fix (both `# >>> mr-aware-rejection` … `# <<< mr-aware-rejection` blocks):
# read + SHAPE-validate the bead ONCE before repooling, fold the merge_result
# clear (and pr_url→existing_pr) into the SAME repool update, and if the bead is
# unreadable, FAIL CLOSED — do not repool at all (drain-ack + exit 1), leaving the
# anchor with the refinery to retry rather than pooling it with merge_result set.
#
# This EXECUTES the real snippets extracted verbatim from the formula (between the
# markers) against a fake `gc`, so the test cannot drift from the shipped
# instruction. No live city, Dolt, network, or PRs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: models the reads/writes the rejection snippet performs. ----------
#   gc runtime drain-ack               -> no-op (exit 0)
#   gc bd show <id> --json             -> emit bead JSON per SHOW_SCENARIO:
#       mr         -> mr-shaped anchor (merge_result + pr_url set)
#       nonmr      -> plain bead (no merge_result)
#       unreadable -> EMPTY stdout, exit 0 — the exact bd fails-open behavior the
#                     fix must treat as "cannot determine mr-shape", NOT "non-mr".
#   gc bd update <id> ...              -> record UPDATE_RAN + each set/unset op so
#       the assertions can prove the repool ran (or, when unreadable, did NOT).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "runtime" ] && exit 0
[ "$1" = "bd" ] || exit 0
case "$2" in
  show)
    case "${SHOW_SCENARIO:-mr}" in
      mr)         printf '[{"metadata":{"merge_result":"pull_request","pr_url":"https://example.test/pr/1","pr_number":"1"}}]\n' ;;
      nonmr)      printf '[{"metadata":{}}]\n' ;;
      unreadable) : ;;  # empty stdout — bd fails open (error to stderr, nothing on stdout)
    esac ;;
  update)
    id="$3"; shift 3
    echo "UPDATE_RAN" >> "$FAKE_META"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)   printf 'set|%s|%s\n' "${2%%=*}" "${2#*=}" >> "$FAKE_META"; shift 2 ;;
        --unset-metadata) printf 'unset|%s\n' "$2" >> "$FAKE_META"; shift 2 ;;
        *) shift ;;
      esac
    done ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# git stub: only `git rev-parse origin/<t>` inside the rebase-arm rejection_reason
# string. Fixed sha keeps the test hermetic (no repo dependency).
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
exit 0
GIT
chmod +x "$TMP/bin/git"

# Captured BEFORE the stub PATH goes on: the shared-branch cases at the bottom
# need the REAL git and a real bare origin, not the sha-echoing stub above.
ORIG_PATH="$PATH"
export PATH="$TMP/bin:$PATH"
export FAKE_META="$TMP/meta"

# --- Extract EACH real rejection snippet from the formula. --------------------
# One file per `# >>> mr-aware-rejection` … `# <<< mr-aware-rejection` pair, so
# BOTH arms (rebase + handle-failures) are exercised, not just the first. Missing
# or renamed markers => zero blocks => the guard below fails loudly.
awk -v tmp="$TMP" '
  /# >>> mr-aware-rejection/ { n++; f=1; next }
  /# <<< mr-aware-rejection/ { f=0; next }
  f { print > (tmp "/block" n ".sh") }
' "$TOML"

NBLOCKS=$(ls "$TMP"/block*.sh 2>/dev/null | wc -l | tr -d ' ')
eq "$NBLOCKS" "2" "both rejection arms extracted between mr-aware-rejection markers"

# run <blockfile> <scenario> -> echo the snippet's exit code; leaves $FAKE_META
# populated. exit 0 == repool proceeded; non-zero == fail-closed defer.
run() {
  : > "$FAKE_META"
  if SHOW_SCENARIO="$2" WORK=work-1 TARGET=main GC_RIG=rig PREPARE_MODE="${PREPARE_MODE:-merge}" bash "$1" >/dev/null 2>&1; then
    echo 0
  else
    echo "$?"
  fi
}

# Exercise every extracted arm identically — the fail-closed contract is the same
# for both, so neither can regress silently.
for BLK in "$TMP"/block*.sh; do
  L="$(basename "$BLK" .sh)"

  # (A) mr-shaped + readable -> repool proceeds; merge_result cleared and
  #     pr_url→existing_pr carried IN THE SAME update.
  eq "$(run "$BLK" mr)" "0" "[$L](A) mr-shaped readable bead -> repool proceeds (exit 0)"
  grep -q '^UPDATE_RAN$' "$FAKE_META" \
    && ok "[$L](A) repool update ran" || bad "[$L](A) repool update did not run"
  grep -q '^unset|merge_result$' "$FAKE_META" \
    && ok "[$L](A) merge_result cleared in the SAME repool update" \
    || bad "[$L](A) merge_result NOT cleared"
  grep -q '^set|existing_pr|https://example.test/pr/1$' "$FAKE_META" \
    && ok "[$L](A) pr_url carried to existing_pr" || bad "[$L](A) existing_pr not carried"
  grep -q '^set|rejection_reason|' "$FAKE_META" \
    && ok "[$L](A) rejection_reason set" || bad "[$L](A) rejection_reason missing"
  grep -q '^set|gc.routed_to|' "$FAKE_META" \
    && ok "[$L](A) routed back to the polecat pool" || bad "[$L](A) gc.routed_to missing"

  # (B) non-mr + readable -> plain repool; NO merge_result clear, NO existing_pr.
  eq "$(run "$BLK" nonmr)" "0" "[$L](B) non-mr readable bead -> plain repool (exit 0)"
  grep -q '^UPDATE_RAN$' "$FAKE_META" \
    && ok "[$L](B) repool update ran" || bad "[$L](B) repool update did not run"
  if grep -q '^unset|merge_result$' "$FAKE_META"; then
    bad "[$L](B) merge_result cleared on a NON-mr bead (spurious unset)"
  else
    ok "[$L](B) no spurious merge_result clear on a non-mr bead"
  fi
  if grep -q '^set|existing_pr|' "$FAKE_META"; then
    bad "[$L](B) existing_pr set on a non-mr bead"
  else
    ok "[$L](B) no existing_pr on a non-mr bead"
  fi

  # (C) THE FIX: unreadable bead (empty stdout) -> FAIL CLOSED. exit 1, and NO
  #     repool ran, so the anchor is left with the refinery (merge_result intact)
  #     rather than pooled to a polecat with merge_result still set.
  eq "$(run "$BLK" unreadable)" "1" "[$L](C) unreadable bead -> fail-closed defer (exit 1)"
  if grep -q '^UPDATE_RAN$' "$FAKE_META"; then
    bad "[$L](C) repool RAN on an unreadable bead — the exact bug this fix prevents"
  else
    ok "[$L](C) unreadable bead -> NO repool ran (anchor left with the refinery)"
  fi
done

# The rebase arm's work order must NAME the prepare mode, not just carry it as
# metadata: metadata.prepare_mode is what the resume block switches on, and this
# string is what the worker reads when it decides whether to force past a
# non-fast-forward push. Only block1 (the rebase arm) has PREPARE_MODE in scope.
run "$TMP/block1.sh" mr >/dev/null
grep -q '^set|rejection_reason|.*prepare_mode=merge' "$FAKE_META" \
  && ok  "[block1] conflict work order names prepare_mode for the worker" \
  || bad "[block1] conflict work order does not name the prepare mode"

# =============================================================================
# SHARED-BRANCH PREPARE MODE (tk-a0hva)
# =============================================================================
# Placed in this suite deliberately, despite the file's mr-aware-rejection name:
# these cases cover the SAME `rebase` step of mol-refinery-patrol.toml that the
# blocks above come from, and gc-toolkit has no test discovery at all — a new
# `shared-branch-merge-mode.test.sh` is a regression nothing would ever run. An
# executed test in a slightly misnamed suite beats a well-named orphan.
#
# THE DEFECT. The refinery applied one sequential-rebase protocol to ANY branch
# it prepared for merge. Correct for a disposable per-bead polecat/<id> branch;
# destructive for an owned convoy's integration branch, whose commits are
# already MERGED PRs — rebasing re-points those PRs at objects the branch no
# longer holds and leaves the originals dangling. Incident 2026-08-19: convoy
# tk-t80p1 -> PR #388 rewrote three merged PRs (#273, #275, #294). The work bead
# carried a twice-restated "MERGE main INTO integration. DO NOT REBASE", which
# did not hold, because the actor that rebased was processing the convoy's
# graduation bead, not the bead the prohibition was written on.
#
# These cases run the REAL extracted snippets against a REAL git repo with a
# REAL bare origin, so "the branch was not rewritten" is asserted against git's
# own object graph and a real push, not against a stub's argv. `git` is wrapped
# so the argv is also observable — a fast-forward push and a force-with-lease
# push both SUCCEED here, so behaviour alone cannot prove which arm ran.
SB="$TMP/sharedbranch"
mkdir -p "$SB/bin"

REAL_GIT="$(PATH="$ORIG_PATH" command -v git)"
[ -n "$REAL_GIT" ] && ok "real git located for the shared-branch fixtures" \
                   || bad "real git NOT found — shared-branch cases cannot run"

# git wrapper: record argv, then exec the real git.
cat > "$SB/bin/git" <<GITW
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$GIT_ARGV_LOG"
exec "$REAL_GIT" "\$@"
GITW
chmod +x "$SB/bin/git"

# gc stub: `gc bd show <work> --json` emits \$BEAD_JSON_OUT verbatim (empty ==
# bd's fails-open shape); `gc runtime drain-ack` is a no-op.
cat > "$SB/bin/gc" <<'GCS'
#!/usr/bin/env bash
[ "$1" = "runtime" ] && exit 0
if [ "$1" = "bd" ] && [ "$2" = "show" ]; then
  printf '%s' "${BEAD_JSON_OUT:-}"
  exit 0
fi
if [ "$1" = "bd" ] && [ "$2" = "update" ]; then
  [ -n "${GC_ARGV_LOG:-}" ] && printf '%s\n' "$*" >> "$GC_ARGV_LOG"
  exit "${GC_UPDATE_RC:-0}"
fi
exit 0
GCS
chmod +x "$SB/bin/gc"

export GIT_CONFIG_GLOBAL="$SB/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
cat > "$GIT_CONFIG_GLOBAL" <<'CFG'
[user]
    name = Refinery Test
    email = refinery@test.invalid
[init]
    defaultBranch = main
[commit]
    gpgsign = false
[advice]
    detachedHead = false
CFG

g() { "$REAL_GIT" -C "$1" "${@:2}"; }
commit_in() { # <repo> <file> <content> <message>
  printf '%s\n' "$3" > "$1/$2"
  g "$1" add "$2" >/dev/null
  g "$1" commit -qm "$4" >/dev/null
}

# --- Fixture: origin with main, integration/x (two "merged PR" commits),
#     integration/conflict, and polecat/p. main then moves ahead of all of them.
"$REAL_GIT" init -q --bare "$SB/origin.git"
"$REAL_GIT" clone -q "$SB/origin.git" "$SB/seed"
commit_in "$SB/seed" base.txt "base" "c1: base"
g "$SB/seed" push -q origin main

g "$SB/seed" checkout -q -b integration/x
commit_in "$SB/seed" feat-a.txt "a" "i1: merged PR #273"
commit_in "$SB/seed" feat-b.txt "b" "i2: merged PR #275"
g "$SB/seed" push -q origin integration/x

g "$SB/seed" checkout -q -b integration/conflict main
commit_in "$SB/seed" shared.txt "integration side" "i3: conflicting edit"
g "$SB/seed" push -q origin integration/conflict

g "$SB/seed" checkout -q -b polecat/p main
commit_in "$SB/seed" work.txt "w" "p1: polecat work"
g "$SB/seed" push -q origin polecat/p

g "$SB/seed" checkout -q main
commit_in "$SB/seed" moved.txt "m" "m1: main moves ahead"
commit_in "$SB/seed" shared.txt "main side" "m2: conflicting edit"
g "$SB/seed" push -q origin main

INT_TIP=$(g "$SB/seed" rev-parse origin/integration/x)
POL_TIP=$(g "$SB/seed" rev-parse origin/polecat/p)

# --- Extract the two prepare/push snippets. ----------------------------------
extract_marker() { # <marker> -> stdout
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") { f=1; next }
    $0 ~ ("# <<< " m "$") { f=0 }
    f' "$TOML"
}
extract_marker shared-branch-merge-mode > "$SB/prepare.sh"
extract_marker shared-branch-push-mode  > "$SB/push.sh"

[ -s "$SB/prepare.sh" ] \
  && ok "prepare block extracted between shared-branch-merge-mode markers" \
  || bad "prepare block extraction EMPTY — markers missing from $TOML"
[ -s "$SB/push.sh" ] \
  && ok "push block extracted between shared-branch-push-mode markers" \
  || bad "push block extraction EMPTY — markers missing from $TOML"

# TOML `"""` eats a trailing backslash as a line-ending escape, so an extracted
# snippet containing one is already mangled by the time it ships.
for f in "$SB/prepare.sh" "$SB/push.sh"; do
  case "$(cat "$f")" in
    *\\*) bad "$(basename "$f") contains a backslash — TOML will mangle it" ;;
    *)    ok  "$(basename "$f") is backslash-free (safe in a TOML triple-quote)" ;;
  esac
  bash -n "$f" 2>/dev/null \
    && ok "$(basename "$f") is syntactically valid bash" \
    || bad "$(basename "$f") is NOT valid bash"
done

# prepare <label> <branch-json> -> exit code; leaves a fresh clone at $SB/run
# with whatever the block did, and the git argv in $SB/run.argv.
prepare() { # <bead-json>
  rm -rf "$SB/run"
  "$REAL_GIT" clone -q "$SB/origin.git" "$SB/run"
  : > "$SB/run.argv"
  : > "$SB/run.gc"
  ( cd "$SB/run" \
    && PATH="$SB/bin:$ORIG_PATH" \
       GIT_ARGV_LOG="$SB/run.argv" \
       GC_ARGV_LOG="$SB/run.gc" \
       GC_UPDATE_RC="${GC_UPDATE_RC:-0}" \
       BEAD_JSON_OUT="$1" \
       WORK=work-1 \
       TARGET_BRANCH_DEFAULT=main \
       bash "$SB/prepare.sh" ) > "$SB/run.out" 2>&1
  echo "$?"
}

# (A) Graduation bead on an integration branch -> MERGE, never rebase.
J_GRAD='[{"metadata":{"branch":"integration/x","target":"main","graduation":"true"}}]'
eq "$(prepare "$J_GRAD")" "0" "(A) graduation bead prepares cleanly"
if g "$SB/run" merge-base --is-ancestor "$INT_TIP" temp 2>/dev/null; then
  ok "(A) integration tip $INT_TIP is still an ancestor of temp — merged PRs NOT rewritten"
else
  bad "(A) integration tip $INT_TIP was REWRITTEN — the tk-t80p1 incident, reproduced"
fi
grep -q '^rebase ' "$SB/run.argv" \
  && bad "(A) git rebase was invoked on an integration branch" \
  || ok  "(A) git rebase never invoked on the integration branch"
grep -q '^merge --no-edit origin/main$' "$SB/run.argv" \
  && ok  "(A) origin/main was merged IN" \
  || bad "(A) origin/main was not merged in"

# (B) Same branch WITHOUT the graduation flag: the name alone must be enough.
#     The flag is stamped by reconcile-graduated-convoys.sh, but a hand-filed
#     catch-up bead (the tk-0d3y5 shape) carries no flag at all.
J_INT='[{"metadata":{"branch":"integration/x","target":"main"}}]'
eq "$(prepare "$J_INT")" "0" "(B) unflagged integration branch prepares cleanly"
if g "$SB/run" merge-base --is-ancestor "$INT_TIP" temp 2>/dev/null; then
  ok "(B) unflagged integration branch preserved without the graduation flag"
else
  bad "(B) unflagged integration branch was REWRITTEN (allowlist did not hold)"
fi

# (C) An unrecognized branch shape must fail to the NON-destructive side.
J_ODD='[{"metadata":{"branch":"feat/one-off","target":"main"}}]'
"$REAL_GIT" -C "$SB/seed" checkout -q -b feat/one-off main~1
commit_in "$SB/seed" odd.txt "o" "f1: unprefixed-ish one-off"
g "$SB/seed" push -q origin feat/one-off
ODD_TIP=$(g "$SB/seed" rev-parse origin/feat/one-off)
eq "$(prepare "$J_ODD")" "0" "(C) unrecognized branch shape prepares cleanly"
if g "$SB/run" merge-base --is-ancestor "$ODD_TIP" temp 2>/dev/null; then
  ok "(C) unrecognized shape defaulted to MERGE (allowlist, not denylist)"
else
  bad "(C) unrecognized shape was REBASED — the guard is a denylist, not an allowlist"
fi

# (D) A per-bead polecat branch still REBASES — the fix must not disable the
#     behaviour that is correct for disposable branches.
J_POL='[{"metadata":{"branch":"polecat/p","target":"main"}}]'
eq "$(prepare "$J_POL")" "0" "(D) polecat branch prepares cleanly"
if g "$SB/run" merge-base --is-ancestor "$POL_TIP" temp 2>/dev/null; then
  bad "(D) polecat branch was MERGED, not rebased — rebase behaviour regressed"
else
  ok "(D) polecat branch was rebased (its old tip is no longer an ancestor)"
fi
grep -q '^rebase origin/main$' "$SB/run.argv" \
  && ok "(D) git rebase origin/main invoked for the polecat branch" \
  || bad "(D) git rebase origin/main NOT invoked for the polecat branch"

# (E) Unreadable bead -> FAIL CLOSED. bd fails open (empty stdout, exit 0), and
#     an empty `graduation` read that way is indistinguishable from an unset one,
#     so the block must refuse rather than classify.
eq "$(prepare "")" "1" "(E) unreadable bead -> fail-closed refusal (exit 1)"
if g "$SB/run" rev-parse --verify temp >/dev/null 2>&1; then
  bad "(E) temp branch was created despite an unreadable bead"
else
  ok "(E) no branch prepared on an unreadable bead"
fi
# The exit code alone does NOT pin the shape check: with it deleted, BRANCH
# reads empty and the no-branch arm refuses too, for a different reason. Only
# the diagnostic separates "bd was unreadable" from "this bead names no
# branch", and an operator reading the refinery log needs that distinction.
grep -q 'could not read' "$SB/run.out" \
  && ok  "(E) refusal names bd unreadability, not a missing branch" \
  || bad "(E) unreadable bead was misreported (shape check gone?): $(head -1 "$SB/run.out")"

# (F) Readable bead with no metadata.branch -> refuse; there is nothing to merge.
eq "$(prepare '[{"metadata":{"target":"main"}}]')" "1" \
   "(F) bead without metadata.branch -> refusal (exit 1)"
grep -q 'carries no metadata.branch' "$SB/run.out" \
  && ok  "(F) refusal names the missing branch, not a bd failure" \
  || bad "(F) missing-branch refusal was misreported: $(head -1 "$SB/run.out")"

# (G) Conflict on the merge arm aborts, leaving a clean worktree for the
#     rejection flow that follows this block in the step.
J_CONF='[{"metadata":{"branch":"integration/conflict","target":"main","graduation":"true"}}]'
prepare "$J_CONF" > "$SB/conflict.rc"
if [ -f "$SB/run/.git/MERGE_HEAD" ]; then
  bad "(G) conflicting merge left MERGE_HEAD — the abort did not run"
else
  ok "(G) conflicting merge aborted; worktree left clean"
fi
grep -q '^merge --abort$' "$SB/run.argv" \
  && ok "(G) git merge --abort ran (not git rebase --abort)" \
  || bad "(G) git merge --abort did not run on the merge arm"

# (J) The graduation flag is the SECOND, independent signal. The allowlist above
#     already covers every branch that is not named polecat/*, so this is the one
#     shape where the flag alone decides: a graduation handed over on a
#     polecat-shaped branch is still an integration->main landing, and must not
#     be rewritten.
J_GRADPOL='[{"metadata":{"branch":"polecat/p","target":"main","graduation":"true"}}]'
eq "$(prepare "$J_GRADPOL")" "0" "(J) graduation on a polecat-shaped branch prepares cleanly"
if g "$SB/run" merge-base --is-ancestor "$POL_TIP" temp 2>/dev/null; then
  ok "(J) graduation flag forced MERGE even on a polecat-shaped branch"
else
  bad "(J) graduation flag was ignored — branch rewritten on the allowlist alone"
fi

# --- Push mode: force ONLY when the push actually rewrites history. -----------
# Both pushes SUCCEED against a real bare origin, so the argv is what
# distinguishes the arms — and the object graph is what proves the consequence.
push_after() { # <bead-json> -> exit code, argv in $SB/run.argv (appended)
  prepare "$1" >/dev/null
  ( cd "$SB/run" \
    && PATH="$SB/bin:$ORIG_PATH" \
       GIT_ARGV_LOG="$SB/run.argv" \
       BRANCH="$2" \
       bash "$SB/push.sh" ) >/dev/null 2>&1
  echo "$?"
}

eq "$(push_after "$J_GRAD" integration/x)" "0" "(H) merge-mode push succeeds"
grep -q 'force-with-lease' "$SB/run.argv" \
  && bad "(H) merge-mode push used --force-with-lease on a shared branch" \
  || ok  "(H) merge-mode push was a plain fast-forward — no force on a shared branch"
if g "$SB/origin.git" merge-base --is-ancestor "$INT_TIP" "refs/heads/integration/x" 2>/dev/null; then
  ok "(H) origin/integration/x still contains its pre-push tip — nothing rewritten"
else
  bad "(H) origin/integration/x lost its pre-push tip — merged PRs orphaned"
fi

eq "$(push_after "$J_POL" polecat/p)" "0" "(I) rebase-mode push succeeds"
grep -q 'push origin HEAD:polecat/p --force-with-lease' "$SB/run.argv" \
  && ok  "(I) rebase-mode push used --force-with-lease (the rewrite needs the lease)" \
  || bad "(I) rebase-mode push did not use --force-with-lease"
grep -q 'push origin HEAD:polecat/p --force$' "$SB/run.argv" \
  && bad "(I) plain --force was used" \
  || ok  "(I) plain --force never used"

# =============================================================================
# THE HAND-BACK WORK ORDER (tk-j32ep — signoff finding on tk-a0hva)
# =============================================================================
# Case (G) above proves the merge arm ABORTS a conflicting merge. That is only
# the first half of the story, and the half that stops here is not the half that
# rewrites anything.
#
# What happens NEXT is the hazard. `PREPARE_FAILED` falls into the rejection
# flow, which repools the SAME work bead to the polecat pool with a
# rejection_reason. The polecat's rejected-branch resume brings a branch current
# by REBASE, and its submit step reads a non-fast-forward push as "force-needed?"
# — so the shared branch this block refused to rewrite gets rewritten one step
# later by a different actor, and force-pushed. The prohibition held for the
# refinery and leaked around it.
#
# The fix carries the refinery's classification on the bead
# (`metadata.prepare_mode`), and the polecat's `rejected-branch-resume-mode`
# block honors it. These cases follow case (G) THROUGH that handoff: the stamp,
# its fail-closed guard, and the resume block executed for real against a real
# shared branch and a real origin — asserting on git's object graph and on
# whether a plain push fast-forwards, not on a stub's argv alone.

# (K) The prepare block stamps the mode it just derived — this is what makes the
#     classification reachable from the other formula, one step later.
eq "$(prepare "$J_INT")" "0" "(K) integration branch prepares cleanly"
grep -q 'bd update work-1 --set-metadata prepare_mode=merge' "$SB/run.gc" \
  && ok  "(K) prepare_mode=merge stamped on the work bead" \
  || bad "(K) prepare_mode NOT stamped — the hand-back cannot know this branch is shared"

eq "$(prepare "$J_POL")" "0" "(L) polecat branch prepares cleanly"
grep -q 'bd update work-1 --set-metadata prepare_mode=rebase' "$SB/run.gc" \
  && ok  "(L) prepare_mode=rebase stamped for a disposable per-bead branch" \
  || bad "(L) prepare_mode=rebase NOT stamped"

# (M) The stamp is FAIL-CLOSED and runs BEFORE the worktree is touched. An
#     unrecorded mode is a hand-back that will rebase a shared branch, so the
#     block must refuse to prepare at all rather than prepare something it
#     cannot hand back safely.
GC_UPDATE_RC=1
prepare_rc=$(prepare "$J_INT")
GC_UPDATE_RC=0
eq "$prepare_rc" "1" "(M) unrecordable prepare_mode -> fail-closed refusal (exit 1)"
grep -q 'could not record prepare_mode' "$SB/run.out" \
  && ok  "(M) refusal names the unrecorded mode" \
  || bad "(M) refusal was misreported: $(head -1 "$SB/run.out")"
if g "$SB/run" rev-parse --verify temp >/dev/null 2>&1; then
  bad "(M) temp branch was prepared despite an unrecordable mode"
else
  ok "(M) nothing prepared when the mode could not be recorded"
fi

# --- The other half of the handoff: the polecat's resume block. ---------------
# Extracted from mol-polecat-work.toml the same way, so this test fails if the
# markers are renamed or the block drifts. `{{base_branch}}` is a formula var
# rendered at pour time; substitute what the refinery would have resolved.
TOML_POLECAT="$ROOT/formulas/mol-polecat-work.toml"
awk '
  /# >>> rejected-branch-resume-mode$/ { f=1; next }
  /# <<< rejected-branch-resume-mode$/ { f=0 }
  f' "$TOML_POLECAT" | sed 's/{{base_branch}}/main/g' > "$SB/resume.sh"

[ -s "$SB/resume.sh" ] \
  && ok  "resume block extracted between rejected-branch-resume-mode markers" \
  || bad "resume block extraction EMPTY — markers missing from $TOML_POLECAT"
case "$(cat "$SB/resume.sh")" in
  *\\*) bad "resume.sh contains a backslash — TOML will mangle it" ;;
  *)    ok  "resume.sh is backslash-free (safe in a TOML triple-quote)" ;;
esac
bash -n "$SB/resume.sh" 2>/dev/null \
  && ok "resume.sh is syntactically valid bash" \
  || bad "resume.sh is NOT valid bash"

# Dedicated branches so the resume cases cannot disturb (H)/(I), which push to
# integration/x and polecat/p on this same origin.
C1=$(g "$SB/seed" rev-parse main~2)
"$REAL_GIT" -C "$SB/seed" checkout -q -b integration/resume "$C1"
commit_in "$SB/seed" r-a.txt "ra" "r1: merged PR (integration/resume)"
commit_in "$SB/seed" r-b.txt "rb" "r2: merged PR (integration/resume)"
g "$SB/seed" push -q origin integration/resume
RES_TIP=$(g "$SB/seed" rev-parse origin/integration/resume)

"$REAL_GIT" -C "$SB/seed" checkout -q -b integration/resumeconf "$C1"
commit_in "$SB/seed" shared.txt "integration side" "r3: conflicting edit"
g "$SB/seed" push -q origin integration/resumeconf
CONF_TIP=$(g "$SB/seed" rev-parse origin/integration/resumeconf)

"$REAL_GIT" -C "$SB/seed" checkout -q -b polecat/resume "$C1"
commit_in "$SB/seed" pr.txt "pr" "r4: polecat work"
g "$SB/seed" push -q origin polecat/resume
POLRES_TIP=$(g "$SB/seed" rev-parse origin/polecat/resume)

# resume <branch> <bead-json> -> exit code. Leaves the worktree at $SB/resume
# with whatever the block did, git argv in $SB/resume.argv. The checkout uses
# the REAL git directly so only the block's own git calls land in the log.
resume() { # <branch> <bead-json>
  rm -rf "$SB/resume"
  "$REAL_GIT" clone -q "$SB/origin.git" "$SB/resume"
  "$REAL_GIT" -C "$SB/resume" checkout -q -B "$1" "origin/$1"
  : > "$SB/resume.argv"
  ( cd "$SB/resume" \
    && PATH="$SB/bin:$ORIG_PATH" \
       GIT_ARGV_LOG="$SB/resume.argv" \
       BEAD_JSON_OUT="$2" \
       WORK_BEAD_ID=work-1 \
       bash "$SB/resume.sh" ) > "$SB/resume.out" 2>&1
  echo "$?"
}

# push_resume -> exit code of the polecat submit step's PLAIN push. Not a
# convenience: whether `git push origin HEAD` fast-forwards is exactly what
# decides if the worker is told "force-needed?", so it is the assertion that
# proves the rewrite pressure is gone rather than merely discouraged.
push_resume() {
  ( cd "$SB/resume" && PATH="$SB/bin:$ORIG_PATH" GIT_ARGV_LOG="$SB/resume.argv" \
      git push origin HEAD ) >/dev/null 2>&1
  echo "$?"
}

J_RES_MERGE='[{"metadata":{"branch":"integration/resume","target":"main","rejection_reason":"Conflicts with main at deadbeef","prepare_mode":"merge"}}]'
J_RES_REBASE='[{"metadata":{"branch":"polecat/resume","target":"main","rejection_reason":"tests failed","prepare_mode":"rebase"}}]'
J_RES_CONF='[{"metadata":{"branch":"integration/resumeconf","target":"main","rejection_reason":"Conflicts with main at deadbeef","prepare_mode":"merge"}}]'

# (N) prepare_mode=merge -> the resume MERGES. The old tip stays reachable, so
#     the merged PRs on that branch still point at objects the branch holds.
eq "$(resume integration/resume "$J_RES_MERGE")" "0" "(N) merge-mode resume runs"
grep -q '^rebase ' "$SB/resume.argv" \
  && bad "(N) the resume REBASED a shared branch — the hand-back rewrite, reproduced" \
  || ok  "(N) the resume never invoked git rebase on a shared branch"
grep -q '^merge --no-edit origin/main$' "$SB/resume.argv" \
  && ok  "(N) origin/main was merged IN by the resume" \
  || bad "(N) origin/main was not merged in by the resume"
if g "$SB/resume" merge-base --is-ancestor "$RES_TIP" HEAD 2>/dev/null; then
  ok "(N) integration/resume tip $RES_TIP still an ancestor — merged PRs NOT rewritten"
else
  bad "(N) integration/resume tip $RES_TIP was REWRITTEN by the hand-back"
fi

# (O) …and the push that follows is an ordinary fast-forward. This is the whole
#     point: the worker is never shown a non-fast-forward rejection, so it is
#     never invited to force past one.
eq "$(push_resume)" "0" "(O) merge-mode resume pushes as a plain fast-forward"
grep -q 'force' "$SB/resume.argv" \
  && bad "(O) a force flag appeared on a shared-branch resume" \
  || ok  "(O) no force flag anywhere in the merge-mode resume"
if g "$SB/origin.git" merge-base --is-ancestor "$RES_TIP" "refs/heads/integration/resume" 2>/dev/null; then
  ok "(O) origin/integration/resume still contains its pre-resume tip"
else
  bad "(O) origin/integration/resume lost its pre-resume tip — merged PRs orphaned"
fi

# (P) The disposable per-bead branch must still REBASE. The fix narrows what may
#     be rewritten; it must not stop the rewrite that is correct.
eq "$(resume polecat/resume "$J_RES_REBASE")" "0" "(P) rebase-mode resume runs"
grep -q '^rebase origin/main$' "$SB/resume.argv" \
  && ok  "(P) git rebase origin/main invoked for the polecat branch" \
  || bad "(P) polecat branch was not rebased — resume behaviour regressed"
if g "$SB/resume" merge-base --is-ancestor "$POLRES_TIP" HEAD 2>/dev/null; then
  bad "(P) polecat branch was MERGED, not rebased"
else
  ok "(P) polecat branch was rebased (its old tip is no longer an ancestor)"
fi

# (Q) An ABSENT prepare_mode still rebases. Every bead the refinery hands back
#     has been stamped, so absence means some other writer set rejection_reason
#     — and silently switching every ordinary resume to a merge would put merge
#     commits in every rework PR. Pinned so the default cannot drift unnoticed.
J_RES_NONE='[{"metadata":{"branch":"polecat/resume","target":"main","rejection_reason":"tests failed"}}]'
eq "$(resume polecat/resume "$J_RES_NONE")" "0" "(Q) resume with no prepare_mode runs"
grep -q '^rebase origin/main$' "$SB/resume.argv" \
  && ok  "(Q) absent prepare_mode keeps the existing rebase behaviour" \
  || bad "(Q) absent prepare_mode changed the default resume path"

# (R) CASE (G), FOLLOWED THROUGH. The branch whose merge conflicted in (G) is
#     repooled and resumed here. The resume hits the same conflict — that is
#     expected and is the worker's job to resolve — but it must reach that
#     conflict via MERGE, leaving the shared tip intact and resolvable into a
#     merge commit. Pre-fix, this same handoff rebased and then force-pushed.
resume integration/resumeconf "$J_RES_CONF" > "$SB/resumeconf.rc"
grep -q '^rebase ' "$SB/resume.argv" \
  && bad "(R) the conflicting hand-back REBASED the shared branch — case (G) still leaks" \
  || ok  "(R) the conflicting hand-back never rebased"
grep -q '^merge --no-edit origin/main$' "$SB/resume.argv" \
  && ok  "(R) the conflicting hand-back attempted a MERGE" \
  || bad "(R) the conflicting hand-back did not attempt a merge"
[ -f "$SB/resume/.git/MERGE_HEAD" ] \
  && ok  "(R) left mid-MERGE for the worker to resolve into a merge commit" \
  || bad "(R) not left mid-merge — the conflict was not surfaced as a merge"
if g "$SB/resume" merge-base --is-ancestor "$CONF_TIP" HEAD 2>/dev/null; then
  ok "(R) shared tip $CONF_TIP intact through the conflicting hand-back"
else
  bad "(R) shared tip $CONF_TIP rewritten by the conflicting hand-back"
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
