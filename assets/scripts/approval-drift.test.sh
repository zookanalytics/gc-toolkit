#!/usr/bin/env bash
# approval-drift.test.sh — hermetic tests for the scope/architectural drift
# classifier. Scope, stands, no-baseline and fail-toward-stands run over the gc
# stub alone; the architectural arm needs real diffs, so it drops the git stub
# and builds a throwaway repo.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-approval-drift-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
harness_init
SUT="$HERE/approval-drift.sh"

mkbead() { # <id> <title> <description> <metadata-json>
  jq -cn --arg id "$1" --arg t "$2" --arg d "$3" --argjson m "$4" \
    '{id:$id,status:"open",assignee:"",title:$t,description:$d,notes:"",metadata:$m}'
}
classify() { "$SUT" classify "$@"; }

# --- scope-digest: stable, content-sensitive, notes-blind ---------------------
store "[$(mkbead tk-anc "Add a widget" "## What
Build the widget." '{}')]"
D1=$("$SUT" scope-digest --anchor tk-anc); DR=$?
eq "$DR" 0 "scope-digest exits 0 on a readable bead"
case "$D1" in [0-9a-f]*) ok "scope-digest is hex ($D1)" ;; *) bad "scope-digest not hex ($D1)" ;; esac

# Reflowed whitespace is the same scope.
store "[$(mkbead tk-anc "Add a widget" "## What    Build   the widget." '{}')]"
D2=$("$SUT" scope-digest --anchor tk-anc)
eq "$D2" "$D1" "scope-digest ignores whitespace reflow"

# Appended notes are not scope: same title+description, different notes.
store "[$(jq -cn '{id:"tk-anc",status:"open",assignee:"",title:"Add a widget",description:"## What\nBuild the widget.",notes:"deferred-dispatch: churn",metadata:{}}')]"
D3=$("$SUT" scope-digest --anchor tk-anc)
eq "$D3" "$D1" "scope-digest excludes appended notes"

# A requirements rewrite changes the digest.
store "[$(mkbead tk-anc "Add a widget" "## What
Build a DIFFERENT widget." '{}')]"
D4=$("$SUT" scope-digest --anchor tk-anc)
case "$D4" in "$D1") bad "scope-digest unchanged after a rewrite" ;; *) ok "scope-digest changes on a requirements rewrite" ;; esac

# Unreadable bead -> rc 1, no digest.
D5=$("$SUT" scope-digest --anchor tk-missing); DR=$?
eq "$DR" 1 "scope-digest on a missing bead exits 1"

# --- classify: no baseline is never drift ------------------------------------
store "[$(mkbead tk-anc "Add a widget" "## What
Build the widget." '{"merge_result":"pull_request","check_set":"codex"}')]"
eq "$(classify --anchor tk-anc --lane codex)" stands "no baseline classifies stands"

# --- classify: scope drift ----------------------------------------------------
# Baseline digest matches current -> stands. (approved_oid set, but the git stub
# yields no diff, so the arch arm is a no-op and scope is what decides.)
CUR=$("$SUT" scope-digest --anchor tk-anc)
store "[$(mkbead tk-anc "Add a widget" "## What
Build the widget." "{\"merge_result\":\"pull_request\",\"check_set\":\"codex\",\"approved_oid.codex\":\"abc123\",\"approved_scope_digest.codex\":\"$CUR\"}")]"
eq "$(classify --anchor tk-anc --lane codex)" stands "matching scope baseline classifies stands"

# Baseline digest differs from current -> scope.
store "[$(mkbead tk-anc "Add a widget" "## What
Build the widget." '{"merge_result":"pull_request","check_set":"codex","approved_oid.codex":"abc123","approved_scope_digest.codex":"ffffffffffff"}')]"
eq "$(classify --anchor tk-anc --lane codex)" scope "a changed scope digest classifies scope"

# The lane defaults to codex when --lane is omitted.
eq "$(classify --anchor tk-anc)" scope "classify defaults the lane to codex"

# A baseline bound to another lane does not drift the codex lane.
store "[$(mkbead tk-anc "Add a widget" "## What
Build the widget." '{"merge_result":"pull_request","check_set":"codex,security","approved_oid.security":"abc123","approved_scope_digest.security":"ffffffffffff"}')]"
eq "$(classify --anchor tk-anc --lane codex)" stands "a security-lane baseline leaves codex standing"
eq "$(classify --anchor tk-anc --lane security)" scope "the security lane reads its own baseline"

# --- classify: fail toward stands --------------------------------------------
export STUB_SHOW_FAIL=1
eq "$(classify --anchor tk-anc --lane codex)" stands "an unreadable anchor classifies stands"
unset STUB_SHOW_FAIL
export STUB_SHOW_FAIL=""

# Usage errors are the only non-zero exit.
"$SUT" classify --lane codex >/dev/null 2>&1; eq "$?" 2 "classify with no --anchor exits 2"
"$SUT" bogus-verb >/dev/null 2>&1; eq "$?" 2 "an unknown verb exits 2"

# --- classify: architectural drift (real git) --------------------------------
rm -f "$BIN/git"   # use real git for the diff arm; the gc stub still serves beads
REPO="$TMP/repo"; mkdir -p "$REPO"
(
  cd "$REPO"
  git init -q
  git config user.email t@t; git config user.name t; git config commit.gpgsign false
  mkdir -p assets/scripts; printf 'echo a\n' > assets/scripts/a.sh
  git add -A; git commit -q -m base
  BASE=$(git rev-parse HEAD); echo "$BASE" > "$TMP/base.sha"
  printf 'echo a\necho a2\n' > assets/scripts/a.sh
  git add -A; git commit -q -m approved
  git rev-parse HEAD > "$TMP/approved.sha"
  # Fixup in the reviewed directory only: no new top-level path.
  printf 'echo a\necho a2\necho a3\n' > assets/scripts/a.sh
  git add -A; git commit -q -m fixup
  git rev-parse HEAD > "$TMP/fixup.sha"
  # Growth into a new top-level directory absent from the reviewed set.
  mkdir -p services; printf 'svc\n' > services/new.go
  git add -A; git commit -q -m grow
  git rev-parse HEAD > "$TMP/grow.sha"
)
BASE=$(cat "$TMP/base.sha"); APPROVED=$(cat "$TMP/approved.sha")
FIXUP=$(cat "$TMP/fixup.sha"); GROW=$(cat "$TMP/grow.sha")
store "[$(mkbead tk-anc "Add a widget" "## What
Build the widget." "{\"merge_result\":\"pull_request\",\"check_set\":\"codex\",\"branch\":\"polecat/x\",\"target\":\"$BASE\",\"approved_oid.codex\":\"$APPROVED\",\"approved_scope_digest.codex\":\"$CUR\"}")]"

# A fixup inside the reviewed directory adds no new top-level path -> stands.
eq "$(cd "$REPO" && classify --anchor tk-anc --lane codex --head "$FIXUP" --base "$BASE")" stands "a fixup in the reviewed tree classifies stands"

# Growth into services/ is a new top-level path -> arch.
eq "$(cd "$REPO" && classify --anchor tk-anc --lane codex --head "$GROW" --base "$BASE")" arch "growth into a new top-level path classifies arch"

# The magnitude factor is off by default: a large fixup in the reviewed tree is
# still stands on the path signal alone.
BIGFIX=$(cd "$REPO" && { git checkout -q "$FIXUP"; for i in $(seq 1 40); do printf 'echo %s\n' "$i" >> assets/scripts/a.sh; done; git add -A; git commit -q -m bigfix; git rev-parse HEAD; git checkout -q - 2>/dev/null; })
eq "$(cd "$REPO" && classify --anchor tk-anc --lane codex --head "$BIGFIX" --base "$BASE")" stands "a large same-tree fixup is stands with the factor off"
# With the factor set low, the same large fixup trips the magnitude signal.
eq "$(cd "$REPO" && APPROVAL_DRIFT_ARCH_MAGNITUDE_FACTOR=2 classify --anchor tk-anc --lane codex --head "$BIGFIX" --base "$BASE")" arch "the magnitude factor trips arch when configured"

echo "---"
echo "approval-drift.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
