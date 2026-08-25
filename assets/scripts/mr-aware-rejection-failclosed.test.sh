#!/usr/bin/env bash
# Hermetic test for the refinery's rejection repool (both `mr-aware-rejection`
# blocks in formulas/mol-refinery-patrol.toml).
#
# THE CONTRACT:
#   1. FAIL CLOSED on an unreadable bead — `gc bd` fails open (errors to
#      stderr, empty stdout), so an unread bead must never be repooled as if
#      it were a plain direct-mode work bead.
#   2. FAIL CLOSED when lifecycle.sh is missing — every merge_result
#      transition goes through the one writer; a hand-rolled repool is how
#      split transitions come back.
#   3. The repool is ONE lifecycle transition to `unanchored`: assignee
#      cleared, routed back to the polecat pool, rejection_reason carried.
#   4. A bead with a live PR (pr_url) carries it over as existing_pr, so the
#      rework reuses the same PR instead of minting a duplicate.
#
# Executes the real blocks extracted verbatim from the formula against stub
# `gc` + `lifecycle.sh`. No live city, Dolt, network, or worktrees.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

# --- Extract every marked copy (one file per block). ---------------------------
NBLOCKS=$(awk '
  /# >>> mr-aware-rejection$/ { n++; f=1; next }
  /# <<< mr-aware-rejection$/ { f=0; next }
  f { print > ("'"$TMP"'/block-" n ".sh") }
  END { print n }' "$TOML")
eq "$NBLOCKS" "2" "both rejection arms carry the mr-aware-rejection block"

for i in 1 2; do
  [ -s "$TMP/block-$i.sh" ] || { bad "block $i extracted"; continue; }
  grep -q '[\]' "$TMP/block-$i.sh" \
    && bad "block $i backslash-free (TOML would eat it)" \
    || ok "block $i backslash-free (TOML would eat it)"
  sed -e "s|{{binding_prefix}}|gc-toolkit.|g" "$TMP/block-$i.sh" > "$TMP/run-$i.sh"
  bash -n "$TMP/run-$i.sh" && ok "block $i is valid bash" || bad "block $i is valid bash"
done

# --- Stubs. ---------------------------------------------------------------------
# gc: bd show answers $FAKE_META (or nothing when FAKE_BD_FAILS=1); drain-ack
# is recorded. lifecycle.sh: records its argv, lives under a fake rig root so
# the block's candidate resolution finds it.
mkdir -p "$TMP/bin" "$TMP/rig/assets/scripts"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd show") [ "${FAKE_BD_FAILS:-0}" = "1" ] && exit 1
             printf '[{"metadata":%s}]\n' "${FAKE_META:-{\}}"; exit 0 ;;
  "bd update") shift 2; printf 'UPDATE|%s\n' "$*" >> "$FAKE_LOG"; exit 0 ;;
esac
exit 0
GC
cat > "$TMP/rig/assets/scripts/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
printf 'LIFECYCLE|%s\n' "$*" >> "$FAKE_LOG"
exit 0
LC
chmod +x "$TMP/bin/gc" "$TMP/rig/assets/scripts/lifecycle.sh"
export PATH="$TMP/bin:$PATH"

# run <block#> <meta-json|-> [rig-root] -> "<rc>|<log>"
run() {
  : > "$TMP/log"
  local rc=0 fails=0 meta="$2"
  [ "$meta" = "-" ] && { fails=1; meta='{}'; }
  # cwd = $TMP (not a git repo) so the block's `git rev-parse --show-toplevel`
  # fallback cannot resolve the real repo and shadow the stub lifecycle.sh.
  ( cd "$TMP" && \
    WORK=tk-work REJECT_REASON="conflict with main" GC_RIG="" \
    GC_RIG_ROOT="${3-$TMP/rig}" GC_CITY_PATH="" \
    FAKE_META="$meta" FAKE_BD_FAILS="$fails" FAKE_LOG="$TMP/log" \
    bash "$TMP/run-$1.sh" > "$TMP/out" 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

for i in 1 2; do
  echo "── block $i ──"

  # (1) Unreadable bead: repool NOTHING; leave the bead with the refinery.
  eq "$(run "$i" -)" "1|DRAIN;" \
     "block $i: unreadable bead -> no repool, drain (fails closed)"

  # (2) Missing lifecycle.sh: same fail-closed shape — never hand-roll the write.
  eq "$(run "$i" '{}' "$TMP/nowhere")" "1|DRAIN;" \
     "block $i: missing lifecycle.sh -> no repool, drain (single-writer rule)"

  # (3) Plain work bead: one lifecycle transition to unanchored, routed back to
  #     the polecat pool with the reason; no existing_pr invented.
  eq "$(run "$i" '{}')" \
     "0|LIFECYCLE|transition tk-work --to unanchored --assignee  --route gc-toolkit.polecat --set rejection_reason=conflict with main;" \
     "block $i: plain bead -> one unanchored transition, routed to the pool"

  # (4) An anchor with a live PR carries it over so the rework reuses the PR.
  eq "$(run "$i" '{"merge_result":"pull_request","pr_url":"https://github.com/o/r/pull/7"}')" \
     "0|LIFECYCLE|transition tk-work --to unanchored --assignee  --route gc-toolkit.polecat --set rejection_reason=conflict with main --set existing_pr=https://github.com/o/r/pull/7;" \
     "block $i: mr anchor -> existing_pr carried into the repool"

  # (5) The block never writes the bead directly — lifecycle.sh is the writer.
  run "$i" '{}' >/dev/null
  grep -q '^UPDATE|' "$TMP/log" \
    && bad "block $i: no direct bead writes" "found a gc bd update" \
    || ok "block $i: no direct bead writes (lifecycle.sh is the writer)"
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
