#!/usr/bin/env bash
# Pack doctor check: refinery merge-completion gate (mol-refinery-patrol v6)
# rejects the phantom-merge failure modes reproduced by the tk-ursrt review.
#
# v5's gate used `git rev-parse HEAD` and a bare `temp` branch name, so
# ambient git state (a stale local $TARGET checkout, or an unrelated work's
# leftover `temp`) could satisfy all checks. v6 reads the local $TARGET ref
# directly, names the temp branch `temp-$WORK`, and pins the caller to
# $TARGET. This check exercises both reproduced failure modes plus the
# happy path against the v6 gate logic, and grep-asserts that the formula
# still contains the v6 sentinel strings (drift detector).
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
formula="$dir/formulas/mol-refinery-patrol.toml"
failures=()
notes=()

# --- Static check: formula contains v6 sentinel strings ---------------------
#
# If the gate's structure drifts (someone reverts to HEAD-based checks, or
# drops the work-specific temp name), the regression scenarios below will
# also fail — but those run a copy of the logic. This grep on the formula
# catches the drift at the source.
require_in_formula() {
    local pattern="$1"
    local label="$2"
    if ! grep -q -- "$pattern" "$formula"; then
        failures+=("formula missing v6 sentinel ($label): $pattern")
    fi
}
require_in_formula 'version = 6' 'formula version'
require_in_formula 'TEMP_BRANCH="temp-$WORK"' 'work-specific temp name'
require_in_formula 'TARGET_SHA=$(git rev-parse --verify --quiet "refs/heads/$TARGET"' 'target ref read'
require_in_formula '"$TARGET_SHA" != "$TEMP_SHA"' 'target == temp comparison'
require_in_formula '"$CURRENT_BRANCH" != "$TARGET"' 'caller-on-target assertion'

# --- Behavioral check: exercise the gate against synthetic scenarios --------
#
# Keep `run_gate` synchronized with the MERGE COMPLETION GATE block in
# formulas/mol-refinery-patrol.toml. This is a faithful copy with the
# side-effecting bits (gc mail, gc runtime, exit) replaced by `return 1`
# so the scenarios can run inside a single shell.
run_gate() {
    local work="$1" target="$2"
    local temp_branch="temp-$work"
    local current_branch target_sha origin_target_sha temp_sha
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    target_sha=$(git rev-parse --verify --quiet "refs/heads/$target" 2>/dev/null || echo "")
    origin_target_sha=$(git rev-parse --verify --quiet "refs/remotes/origin/$target" 2>/dev/null || echo "")
    temp_sha=$(git rev-parse --verify --quiet "refs/heads/$temp_branch" 2>/dev/null || echo "")

    if [ -z "$temp_sha" ]; then
        GATE_REASON="$temp_branch missing"
        return 1
    fi
    if [ "$current_branch" != "$target" ]; then
        GATE_REASON="current branch '${current_branch:-<detached>}' != '$target'"
        return 1
    fi
    if [ -z "$target_sha" ]; then
        GATE_REASON="local $target missing"
        return 1
    fi
    if [ "$target_sha" != "$temp_sha" ]; then
        GATE_REASON="local $target ($target_sha) != $temp_branch ($temp_sha)"
        return 1
    fi
    if [ -z "$origin_target_sha" ]; then
        GATE_REASON="origin/$target missing"
        return 1
    fi
    if ! git merge-base --is-ancestor "$target_sha" "refs/remotes/origin/$target"; then
        GATE_REASON="$target_sha not reachable from origin/$target"
        return 1
    fi
    GATE_REASON="ok"
    return 0
}

# Scenario harness: each scenario sets up a fresh repo under $tmpdir,
# then calls run_gate and asserts the expected outcome.
scratch=$(mktemp -d 2>/dev/null) || { echo "could not create tmpdir"; exit 2; }
trap 'rm -rf "$scratch"' EXIT

# Quiet git so the test output is just our scenario lines.
export GIT_AUTHOR_NAME="gate-test"
export GIT_AUTHOR_EMAIL="gate-test@example.invalid"
export GIT_COMMITTER_NAME="gate-test"
export GIT_COMMITTER_EMAIL="gate-test@example.invalid"

# Build a "remote" bare repo with an initial main commit at origin.
# Uses absolute paths so the caller's cwd is irrelevant.
build_remote() {
    local origin="$1"
    git init --quiet --bare -b main "$origin"
    local seed="$scratch/_seed"
    git init --quiet -b main "$seed"
    git -C "$seed" config user.name "gate-test"
    git -C "$seed" config user.email "gate-test@example.invalid"
    echo "initial" >"$seed/file"
    git -C "$seed" add file
    git -C "$seed" commit --quiet -m "initial"
    git -C "$seed" remote add origin "$origin"
    git -C "$seed" push --quiet origin main
    rm -rf "$seed"
}

# Build a working clone that already has the rebase step's outputs: a
# work branch on origin, and a local `temp-$work` branch fast-forwarded
# from it. Leaves cwd at $repo so the scenario block can keep using
# bare `git` and the gate's `git branch --show-current` resolves there.
build_repo() {
    local repo="$1" origin="$2" work="$3" target="$4"
    git clone --quiet "$origin" "$repo"
    cd "$repo"
    git config user.name "gate-test"
    git config user.email "gate-test@example.invalid"
    git checkout --quiet -b "feat-$work"
    echo "$work change" >>file
    git add file
    git commit --quiet -m "feat: $work"
    git push --quiet origin "feat-$work"
    git checkout --quiet -B "temp-$work" "origin/feat-$work"
}

assert_pass() {
    local name="$1"
    if run_gate "$2" "$3"; then
        notes+=("PASS $name (gate accepted: $GATE_REASON)")
    else
        failures+=("$name: gate REJECTED unexpectedly ($GATE_REASON)")
    fi
}

assert_fail() {
    local name="$1" want_substr="$2"
    if run_gate "$3" "$4"; then
        failures+=("$name: gate ACCEPTED but should have rejected")
        return
    fi
    case "$GATE_REASON" in
        *"$want_substr"*)
            notes+=("PASS $name (gate rejected: $GATE_REASON)")
            ;;
        *)
            failures+=("$name: gate rejected for wrong reason ($GATE_REASON); wanted substring '$want_substr'")
            ;;
    esac
}

# --------------------------------------------------------------------------
# Scenario 1 — Happy path. Local target fast-forwarded to temp-WORK, pushed.
# Gate must PASS.
# --------------------------------------------------------------------------
work="tk-aaaa1"
build_remote "$scratch/origin-happy.git"
build_repo "$scratch/repo-happy" "$scratch/origin-happy.git" "$work" "main"
git checkout --quiet main
git merge --quiet --ff-only "temp-$work"
git push --quiet origin main
assert_pass "happy_path" "$work" "main"

# --------------------------------------------------------------------------
# Scenario 2 — temp-$WORK missing (rebase/merge step never ran for THIS work).
# Gate must REJECT with "temp missing".
# --------------------------------------------------------------------------
work="tk-bbbb2"
build_remote "$scratch/origin-tempmissing.git"
build_repo "$scratch/repo-tempmissing" "$scratch/origin-tempmissing.git" "$work" "main"
git checkout --quiet main
git merge --quiet --ff-only "temp-$work"
git push --quiet origin main
git branch -D "temp-$work" >/dev/null 2>&1
assert_fail "temp_missing" "missing" "$work" "main"

# --------------------------------------------------------------------------
# Scenario 3 — codex failure #1 (tk-ursrt: "gate checks HEAD, not local
# $TARGET"). This scenario tightens the caller-on-target axis so the
# rejection MUST come from check 3 (local $TARGET ref vs temp), not from
# check 2 (current branch != target). Setup: temp-$WORK has the rebased
# work; caller is on main; local main is STALE (no `git merge --ff-only`
# was run); origin/main has been advanced via an out-of-band push so the
# v5 ancestor check on HEAD would have passed vacuously. The only line of
# defense is reading local $TARGET ref directly — v5 passes, v6 rejects.
# --------------------------------------------------------------------------
work="tk-cccc3"
build_remote "$scratch/origin-staletarget.git"
build_repo "$scratch/repo-staletarget" "$scratch/origin-staletarget.git" "$work" "main"
# Out-of-band: advance origin/main so the "reachable from origin/main"
# check (v5's only remaining proof) passes without local main moving.
git push --quiet origin "temp-$work:main"
git fetch --quiet origin
# Caller is on main (check 2 passes), but local main is still at the
# initial commit (check 3 rejects because main != temp-$WORK).
git checkout --quiet main
assert_fail "stale_local_target_v5_bug" "!=" "$work" "main"

# --------------------------------------------------------------------------
# Scenario 4 — codex failure #2 (tk-ursrt: "stale temp can satisfy all
# checks for unrelated work"): a `temp-$OTHER` branch from a different
# work exists, but THIS work's `temp-$WORK` does not. v5 accepted any
# branch named `temp`; v6 requires the work-specific name. To make this
# adversarial, also create a bare `temp` branch (the literal v5 name) to
# confirm v6 ignores it. Gate must REJECT with "missing".
# --------------------------------------------------------------------------
work="tk-dddd4"
other_work="tk-eeee5"
build_remote "$scratch/origin-wrongtemp.git"
build_repo "$scratch/repo-wrongtemp" "$scratch/origin-wrongtemp.git" "$other_work" "main"
git checkout --quiet -B temp "temp-$other_work"
git checkout --quiet main
git merge --quiet --ff-only "temp-$other_work"
git push --quiet origin main
git fetch --quiet origin
assert_fail "wrong_works_temp" "missing" "$work" "main"

# --------------------------------------------------------------------------
# Scenario 5 — caller is still on temp-$WORK (v5's HEAD-based read).
# Local main is fast-forwarded and pushed correctly, but the gate now
# pins the caller to $TARGET so the read of $TARGET is unambiguous. Gate
# must REJECT.
# --------------------------------------------------------------------------
work="tk-ffff6"
build_remote "$scratch/origin-notontarget.git"
build_repo "$scratch/repo-notontarget" "$scratch/origin-notontarget.git" "$work" "main"
git checkout --quiet main
git merge --quiet --ff-only "temp-$work"
git push --quiet origin main
git checkout --quiet "temp-$work"
assert_fail "not_on_target" "current branch" "$work" "main"

# --------------------------------------------------------------------------
# Scenario 6 — local target == temp, but push didn't land. Gate must REJECT.
# --------------------------------------------------------------------------
work="tk-gggg7"
build_remote "$scratch/origin-nopush.git"
build_repo "$scratch/repo-nopush" "$scratch/origin-nopush.git" "$work" "main"
git checkout --quiet main
git merge --quiet --ff-only "temp-$work"
# Deliberately skip `git push origin main`.
assert_fail "push_not_landed" "not reachable" "$work" "main"

# --------------------------------------------------------------------------

if [ ${#failures[@]} -eq 0 ]; then
    echo "refinery gate (mol-refinery-patrol v6) rejects all phantom-merge scenarios"
    for n in "${notes[@]}"; do
        echo "$n"
    done
    exit 0
fi

echo "${#failures[@]} refinery-gate failure(s) — see tk-tt28o (rework of tk-c9q75 per review tk-ursrt)"
for f in "${failures[@]}"; do
    echo "$f"
done
for n in "${notes[@]}"; do
    echo "$n"
done
exit 2
