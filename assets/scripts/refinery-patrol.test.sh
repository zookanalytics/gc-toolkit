#!/usr/bin/env bash
# Hermetic test for refinery-patrol.sh, the refinery session's identity check
# and its end, against a fake gc over a JSON store and real git repositories
# (refinery-test-lib.sh). Proves:
#   - identity passes a set GC_AGENT, and an empty one files a patrol finding
#     keyed refinery-empty-identity and exits 1;
#   - end removes every tree the session left under the refinery's home, and
#     writes nothing to the store.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-patrol-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-patrol.sh
}
run() { OUT=$("$SUT/refinery-patrol.sh" "$@" 2>&1); RC=$?; }

echo "# identity"
fresh
run identity
eq "$RC" 0 "a set GC_AGENT passes"
GC_AGENT="" run identity
eq "$RC" 1 "an empty GC_AGENT exits 1"
has "$(logged scripts)" "patrol-finding --scope refinery-findings --key refinery-empty-identity" "…and files a patrol finding"

echo "# end removes the trees the session left, and writes nothing"
fresh
branch_with polecat/a a.txt >/dev/null
prepared a polecat/a
branch_with polecat/b b.txt >/dev/null
prepared b polecat/b
run end
eq "$RC" 0 "end exits 0"
[ ! -e "$HOME_DIR/worktrees/a" ] && [ ! -e "$HOME_DIR/worktrees/b" ] && rt_ok "every tree under the home is removed" || rt_bad "every tree under the home is removed"
hasnt "$(logged gc)" "bd " "…and the store is not written"
fresh
run end
eq "$RC" 0 "a home with no tree left ends at once"
"$SUT/refinery-patrol.sh" bogus >/dev/null 2>&1; eq "$?" 2 "an unknown verb is usage"

echo
echo "refinery-patrol: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
