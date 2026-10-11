#!/usr/bin/env bash
# witness-recovery.test.sh — recover-orphaned-beads runs the stages of
# witness-recovery.sh in the order the merge verify allows.
#
# The step's per-bead command salvages and verifies first, and the verify's
# verdict decides the rest. A bead whose work is not on its target (`no`), or
# that has no branch to verify (`skip`), is cleaned up, disposed back to the pool
# and recorded. A landed branch (`yes`) has its worktree cleaned and is never
# disposed, because the witness closes that bead instead of re-dispatching
# finished work. Any other verdict, `unknown` and an empty one included, cleans
# nothing and disposes nothing: the work may not be anywhere else, and a human
# decides.
#
# The test renders the step from the formula, extracts its per-bead command, and
# runs it with every stage replaced by a stub that logs its own name, so it
# reads the shipped order rather than a copy of it. It also checks that every
# stage the command calls is a function the library defines.
#
# Hermetic: reads the formula and the library. No city, store, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
LIB="$HERE/witness-recovery.sh"

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # tomllib_python and the assertion helpers only

PASS=0; FAIL=0

if ! PY="$(tomllib_python)"; then
  echo "skip - witness recovery order: $PY"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-witness-recovery-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The per-bead command is the step's one bash block that sets BEAD.
"$PY" - "$TOML" > "$TMP/recover.sh" <<'PY'
import re, sys, tomllib
with open(sys.argv[1], "rb") as f:
    steps = tomllib.load(f).get("steps") or []
desc = next((s.get("description", "") for s in steps if s.get("id") == "recover-orphaned-beads"), "")
blocks = [b for b in re.findall(r"```bash\n(.*?)```", desc, re.S) if 'BEAD="<bead>"' in b]
sys.stdout.write(blocks[0] if len(blocks) == 1 else "")
PY
[ -s "$TMP/recover.sh" ] \
  && ok "extracted the per-bead recovery command from recover-orphaned-beads" \
  || bad "recover-orphaned-beads has no single bash block that sets BEAD in $TOML"
bash -n "$TMP/recover.sh" 2>/dev/null \
  && ok "the per-bead command is valid bash" \
  || bad "the per-bead command fails bash -n"

STAGES="$(grep -oE 'witness_[a-z_]+' "$TMP/recover.sh" | sort -u | tr '\n' ' ')"
for stage in witness_verify witness_worktree_cleanup witness_dispose witness_record; do
  has " $STAGES" " $stage " "the per-bead command runs $stage"
done
for stage in $STAGES; do
  grep -qE "^$stage\(\) \{" "$LIB" \
    && ok "$stage is a function witness-recovery.sh defines" \
    || bad "the step calls $stage, which witness-recovery.sh does not define"
done

# ran <verdict> — the stages the command ran, in order, when the verify reports
# <verdict>. Every stage is a stub that logs its name; the verify's stub also
# sets BRANCH_MERGED.
ran() {
  VERDICT="$1" STAGES="$STAGES" bash -c '
    RAN=""
    for stage in $STAGES; do eval "$stage() { RAN=\"\$RAN $stage\"; }"; done
    witness_verify() { RAN="$RAN witness_verify"; BRANCH_MERGED="$VERDICT"; }
    . "$0" >/dev/null 2>&1
    printf "%s " "$RAN"
  ' "$TMP/recover.sh"
}

# before <sequence> <first> <second> — 0 when <first> ran and <second> ran
# after it, or did not run at all.
before() {
  local seq="$1" a="$2" b="$3" rest
  case "$seq" in *" $a "*) ;; *) return 1 ;; esac
  rest="${seq%%" $a "*}"
  case "$rest " in *" $b "*) return 1 ;; esac
  return 0
}

for verdict in no skip; do
  seq="$(ran "$verdict")"
  has "$seq" " witness_dispose " "BRANCH_MERGED=$verdict returns the bead to the pool"
  has "$seq" " witness_worktree_cleanup " "BRANCH_MERGED=$verdict cleans up the worktree"
  has "$seq" " witness_record " "BRANCH_MERGED=$verdict records the recovery"
  before "$seq" witness_owning_store witness_worktree_cleanup \
    && ok "BRANCH_MERGED=$verdict proves the owning store before removing the worktree" \
    || bad "BRANCH_MERGED=$verdict removes the worktree without the owning-store guard ahead of it: $seq"
  before "$seq" witness_dispose witness_record \
    && ok "BRANCH_MERGED=$verdict records only after the disposal's verdict" \
    || bad "BRANCH_MERGED=$verdict records before disposing: $seq"
done

seq="$(ran yes)"
hasnt "$seq" " witness_dispose " "BRANCH_MERGED=yes never re-dispatches landed work"
hasnt "$seq" " witness_record " "BRANCH_MERGED=yes records no recovery"
has "$seq" " witness_worktree_cleanup " "BRANCH_MERGED=yes cleans the landed branch's worktree"
before "$seq" witness_owning_store witness_worktree_cleanup \
  && ok "BRANCH_MERGED=yes proves the owning store before removing the worktree" \
  || bad "BRANCH_MERGED=yes removes the worktree without the owning-store guard ahead of it: $seq"

for verdict in unknown ""; do
  seq="$(ran "$verdict")"
  hasnt "$seq" " witness_dispose " "BRANCH_MERGED='$verdict' disposes nothing"
  hasnt "$seq" " witness_worktree_cleanup " "BRANCH_MERGED='$verdict' leaves the worktree standing"
  hasnt "$seq" " witness_record " "BRANCH_MERGED='$verdict' records no recovery"
done

# Nothing is cleaned up or disposed before the verify reports.
for verdict in no skip yes; do
  seq="$(ran "$verdict")"
  for stage in witness_owning_store witness_worktree_cleanup witness_dispose; do
    before "$seq" witness_verify "$stage" \
      && ok "BRANCH_MERGED=$verdict runs $stage only after the verify" \
      || bad "BRANCH_MERGED=$verdict runs $stage before the verify: $seq"
  done
done

echo
echo "witness-recovery: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
