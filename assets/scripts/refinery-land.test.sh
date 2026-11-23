#!/usr/bin/env bash
# Hermetic test for refinery-land.sh, the refinery patrol's merge-push step.
# Runs the real script with the real direct-merge-push.sh, refinery-publish.sh
# and branch-push.sh against real git repositories, with a fake gc, gh and gctk
# and a stub lifecycle.sh that logs each transition (refinery-test-lib.sh).
# Proves:
#   - a direct bead onto an integration branch lands by a fast-forward push and
#     is recorded through direct-merge-push.sh, one a person handed back from a
#     park, blocked or refused_false_completion, included;
#   - a direct bead bound for the default branch takes mr;
#   - mr publishes the PR and records it pending (refinery-publish.sh, whose
#     own suite proves the publication's cases);
#   - a branch with no change parks the bead behind refinery-false-completion,
#     unless the target carries the bead's stamped direct landing, which is
#     recorded, and a gate that is not filed parks nothing;
#   - an unsupported strategy parks the bead behind
#     refinery-unsupported-strategy;
#   - a target that moved after the prep lands nothing (exit 6);
#   - a bead whose branch the refinery's tree does not hold gets no write.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../tools/test-floor.sh" || exit 2
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-land-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
# The check index is gctk's, built from this checkout once, beside the
# directory each case empties.
RT_GCTK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-land-bin.XXXXXX")"
trap 'rm -rf "$TMP" "$RT_GCTK_DIR"' EXIT
( cd "$HERE/../../services/gctk" && go build -buildvcs=false -o "$RT_GCTK_DIR/gctk" ./cmd/gctk ) >"$RT_GCTK_DIR/build.log" 2>&1 \
  || { echo "gctk did not build: $(tail -3 "$RT_GCTK_DIR/build.log")" >&2; exit 1; }
export RT_GCTK_REAL="$RT_GCTK_DIR/gctk"
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-land.sh refinery-publish.sh direct-merge-push.sh rig-root.sh
  export GC_RIG_ROOT="$RIG" DIRECT_MERGE_PUSH_BACKOFF=0
}
run() { OUT=$("$SUT/refinery-land.sh" "$@" 2>&1); RC=$?; }
integration() { branch_with integration/e e-base.txt >/dev/null; }

echo "# a direct bead onto an integration branch lands by a fast-forward push"
fresh
integration
branch_with polecat/d d.txt integration/e >/dev/null
work d polecat/d '{"target":"integration/e","merge_strategy":"direct"}'
prepared d polecat/d
git -C "$HOME_DIR" fetch -q origin "+refs/heads/integration/e:refs/remotes/origin/integration/e"
git -C "$HOME_DIR/worktrees/d" merge -q --no-edit refs/remotes/origin/integration/e >/dev/null 2>&1
HEAD_D=$(git -C "$HOME_DIR/worktrees/d" rev-parse HEAD)
run --bead d
eq "$RC" 0 "the landing exits 0"
eq "$(tip integration/e)" "$HEAD_D" "the target holds the prepared head"
has "$(logged scripts)" "lifecycle transition d --to merged --close --set merged_sha=$HEAD_D --set merged_target=integration/e" "the landing is recorded and the bead closed"
[ ! -e "$HOME_DIR/worktrees/d" ] && rt_ok "the tree is removed" || rt_bad "the tree is removed"
eq "$(tip polecat/d)" "<absent>" "delete_merged_branches deletes the branch once the landing is recorded"
hasnt "$(logged gctk)" "pr compose" "with no PR open from the target, nothing is composed"

# direct_onto <bead> <metadata> — a direct bead whose branch, cut from
# integration/e, carries a change, prepared and current with integration/e;
# HEAD_D is its prepared head.
direct_onto() {
  integration
  branch_with "polecat/$1" "$1.txt" integration/e >/dev/null
  work "$1" "polecat/$1" "$(jq -nc --argjson m "$2" '{target: "integration/e", merge_strategy: "direct"} + $m')"
  prepared "$1" "polecat/$1"
  git -C "$HOME_DIR" fetch -q origin "+refs/heads/integration/e:refs/remotes/origin/integration/e"
  git -C "$HOME_DIR/worktrees/$1" merge -q --no-edit refs/remotes/origin/integration/e >/dev/null 2>&1
  HEAD_D=$(git -C "$HOME_DIR/worktrees/$1" rev-parse HEAD)
}

echo "# a direct bead handed back from a park lands and is recorded"
for park in blocked refused_false_completion; do
  fresh
  direct_onto d "{\"merge_result\":\"$park\",\"rejection_reason\":\"parked\"}"
  run --bead d
  eq "$RC" 0 "$park: the landing exits 0"
  eq "$(tip integration/e)" "$HEAD_D" "$park: the target holds the prepared head"
  has "$(logged scripts)" "lifecycle transition d --to merged --close --set merged_sha=$HEAD_D --set merged_target=integration/e --unset rejection_reason" \
    "$park: the bead closes merged at its merged_sha, its rejection cleared"
done
fresh
integration
STAMP=$(branch_with polecat/s s.txt integration/e)
git -C "$SEED" checkout -q integration/e && git -C "$SEED" merge -q --ff-only "$STAMP" && git -C "$SEED" push -q origin integration/e
work s polecat/s "{\"target\":\"integration/e\",\"merge_strategy\":\"direct\",\"direct_landing_sha\":\"$STAMP\",\"merge_result\":\"blocked\"}"
prepared s polecat/s
run --bead s
eq "$RC" 0 "a landing pushed under a park but never recorded is recorded"
has "$(logged scripts)" "lifecycle transition s --to merged --close --set merged_sha=$STAMP" "…at its stamp"
echo "# a direct bead bound for the default branch takes mr"
fresh
branch_with polecat/m m.txt >/dev/null
work m polecat/m '{"merge_strategy":"direct"}'
prepared m polecat/m
HEAD_M=$(git -C "$HOME_DIR/worktrees/m" rev-parse HEAD)
run --bead m
eq "$RC" 0 "the landing exits 0"
[ "$(tip main)" != "$HEAD_M" ] && rt_ok "nothing is pushed onto the default branch" || rt_bad "nothing is pushed onto the default branch"
eq "$(meta m merge_result)" "pull_request_pending" "the bead's PR is published and recorded pending"

echo "# mr publishes the PR and records it pending"
fresh
branch_with polecat/n n.txt >/dev/null
work n polecat/n
prepared n polecat/n
HEAD_N=$(git -C "$HOME_DIR/worktrees/n" rev-parse HEAD)
run --bead n
eq "$RC" 0 "the landing exits 0"
eq "$(meta n merge_result)" "pull_request_pending" "the bead records its PR as pending"
eq "$(tip polecat/n)" "$HEAD_N" "the prepared head is on its branch"
has "$(logged gh)" "pr create" "the PR opens"
hasnt "$(logged scripts)" "lifecycle" "no lifecycle transition is written"
[ ! -e "$HOME_DIR/worktrees/n" ] && rt_ok "the tree is removed" || rt_bad "the tree is removed"

echo "# a branch with no change parks the bead, unless the target carries its stamped landing"
fresh
git -C "$SEED" fetch -q origin && git -C "$SEED" branch -f polecat/z origin/main && git -C "$SEED" push -q origin polecat/z
work z polecat/z
prepared z polecat/z
run --bead z
eq "$RC" 4 "the landing parks (exit 4)"
has "$(logged scripts)" "human-gate --subject z --key refinery-false-completion" "the gate is keyed refinery-false-completion"
eq "$(meta z merge_result)" "refused_false_completion" "the bead records refused_false_completion"
eq "$(bassignee z)" "$GC_AGENT" "…and stays with the refinery, held by its gate"
fresh
git -C "$SEED" fetch -q origin && git -C "$SEED" branch -f polecat/y origin/main && git -C "$SEED" push -q origin polecat/y
work y polecat/y
prepared y polecat/y
STUB_HUMAN_GATE_RC=1 run --bead y
eq "$RC" 1 "a refusal whose gate is not filed stops (exit 1)"
eq "$(meta y merge_result)" "<absent>" "…and parks nothing, so the bead stays with the refinery for the next patrol"
fresh
integration
STAMP=$(branch_with polecat/s s.txt integration/e)
git -C "$SEED" checkout -q integration/e && git -C "$SEED" merge -q --ff-only "$STAMP" && git -C "$SEED" push -q origin integration/e
work s polecat/s "{\"target\":\"integration/e\",\"merge_strategy\":\"direct\",\"direct_landing_sha\":\"$STAMP\"}"
prepared s polecat/s
run --bead s
eq "$RC" 0 "a stamped landing the target carries is recorded"
has "$(logged scripts)" "lifecycle transition s --to merged --close --set merged_sha=$STAMP" "…at the stamped commit"

echo "# an unsupported strategy parks the bead"
fresh
integration
branch_with polecat/l l.txt integration/e >/dev/null
work l polecat/l '{"target":"integration/e","merge_strategy":"local"}'
prepared l polecat/l
run --bead l
eq "$RC" 4 "the landing parks (exit 4)"
has "$(logged scripts)" "human-gate --subject l --key refinery-unsupported-strategy" "the gate is keyed refinery-unsupported-strategy"

echo "# a target that moved after the prep lands nothing"
fresh
integration
branch_with polecat/t t.txt integration/e >/dev/null
work t polecat/t '{"target":"integration/e","merge_strategy":"direct"}'
prepared t polecat/t
git -C "$HOME_DIR" fetch -q origin "+refs/heads/integration/e:refs/remotes/origin/integration/e"
git -C "$HOME_DIR/worktrees/t" merge -q --no-edit refs/remotes/origin/integration/e >/dev/null 2>&1
MOVED=$(branch_with integration/e later.txt integration/e)
run --bead t
eq "$RC" 6 "the landing says the target moved (exit 6)"
has "$OUT" "the next pass prepares it again" "it says the next pass prepares it again"
eq "$(tip integration/e)" "$MOVED" "the target keeps what moved it"
hasnt "$(logged scripts)" "--to merged" "nothing is recorded"

echo "# a bead whose branch the refinery's tree does not hold gets no write"
fresh
branch_with polecat/p p.txt >/dev/null
branch_with polecat/q q.txt >/dev/null
work p polecat/p
work q polecat/q
prepared q polecat/q
run --bead p
eq "$RC" 1 "a bead this iteration did not prepare is refused"
eq "$(logged scripts)" "" "no gate, transition or landing is written"
eq "$(tip polecat/p)" "$(git -C "$SEED" rev-parse polecat/p)" "nothing is pushed"

echo
echo "refinery-land: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
