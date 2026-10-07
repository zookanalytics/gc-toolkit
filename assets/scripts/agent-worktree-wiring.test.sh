#!/usr/bin/env bash
# A rig-scoped agent shells gh/git to inspect the rig it serves, and those tools
# resolve the repo from the working directory. An agent whose work_dir is a plain
# directory under the city .gc tree therefore resolves to the CITY repo, not its
# rig — gh reports a rig PR as nonexistent, git ls-remote misses a rig branch.
# The fix is a work_dir that is a git worktree of the rig repo, cut by a
# worktree-setup.sh pre_start hook, exactly as the polecat/proactive/refinery
# pools already do. This test holds that wiring so a rig-scoped agent cannot
# silently be added — or reverted — onto a city-tree path again.
#
# Two invariants, checked over every agent TOML in the pack:
#
#   1. Wiring agreement. A work_dir under .gc/worktrees/ needs a worktree-setup
#      pre_start to create it, and a worktree-setup pre_start needs a
#      .gc/worktrees/ work_dir to land in. Half of the pair alone is a work_dir
#      that resolves to a directory nothing prepares, or a worktree nothing uses.
#
#   2. Rig resolution. A scope="rig" agent must resolve git/gh to its rig. It
#      does so with a .gc/worktrees/ work_dir (its cwd IS a rig worktree), OR it
#      never resolves from cwd at all — it passes the repo explicitly on every
#      call (gh --repo, git -C <root>) — and then declares a `# worktree-exempt:`
#      marker naming why. The marker makes the exception deliberate and visible;
#      its absence on a city-tree rig agent is the bug this test exists to catch.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

TOMLS=()
for T in "$ROOT"/agents/*/agent.toml "$ROOT"/packs/*/agents/*/agent.toml; do
  [ -s "$T" ] && TOMLS+=("$T")
done
[ "${#TOMLS[@]}" -gt 0 ] || { echo "no agent TOMLs under $ROOT" >&2; exit 1; }

# toplevel <toml> <key> — the key's value, read only from the region above the
# first [table] header, so a same-named key inside [env] or [pool] cannot be
# mistaken for the agent's own.
toplevel() {
  awk -v k="$2" '
    /^[[:space:]]*\[/ { exit }
    $0 ~ "^" k "[[:space:]]*=" {
      sub("^" k "[[:space:]]*=[[:space:]]*", "")
      sub(/[[:space:]]*(#.*)?$/, "")
      gsub(/^"|"$/, "")
      print; exit
    }
  ' "$1"
}

for TOML in "${TOMLS[@]}"; do
  NAME=$(basename "$(dirname "$TOML")")
  SCOPE=$(toplevel "$TOML" scope)
  WORK_DIR=$(toplevel "$TOML" work_dir)

  case "$WORK_DIR" in
    .gc/worktrees/*) WT_PATH=yes ;;
    *)               WT_PATH=no ;;
  esac
  # The pre_start hook, if present, is a non-comment line naming worktree-setup.sh.
  if grep -qE '^[^#]*worktree-setup\.sh' "$TOML"; then WT_SETUP=yes; else WT_SETUP=no; fi
  # A deliberate, documented exception to the rig-resolution invariant.
  if grep -qE '^[[:space:]]*#[[:space:]]*worktree-exempt:' "$TOML"; then EXEMPT=yes; else EXEMPT=no; fi

  # 1. Wiring agreement — both directions.
  if [ "$WT_PATH" = yes ] && [ "$WT_SETUP" = no ]; then
    bad "$NAME: work_dir is under .gc/worktrees/ ($WORK_DIR) but no worktree-setup.sh pre_start creates it"
  elif [ "$WT_SETUP" = yes ] && [ "$WT_PATH" = no ]; then
    bad "$NAME: has a worktree-setup.sh pre_start but work_dir ($WORK_DIR) is not under .gc/worktrees/ — the worktree it cuts is never the cwd"
  else
    ok "$NAME: worktree wiring agrees (work_dir under .gc/worktrees/: $WT_PATH; worktree-setup pre_start: $WT_SETUP)"
  fi

  # A city-scoped agent has no single rig, so {{.Rig}} cannot expand — a
  # worktree path templated on it resolves to a malformed .gc/worktrees//... .
  case "$SCOPE" in
    city)
      case "$WORK_DIR" in
        *'{{'*'.Rig'*'}}'*) bad "$NAME: scope=city but work_dir references {{.Rig}} ($WORK_DIR), which does not expand for a city-scoped agent" ;;
      esac ;;
  esac

  # 2. Rig resolution.
  if [ "$SCOPE" = rig ]; then
    if [ "$WT_PATH" = yes ]; then
      ok "$NAME: rig-scoped and its cwd is a rig worktree"
    elif [ "$EXEMPT" = yes ]; then
      ok "$NAME: rig-scoped, not a rig worktree, but declares worktree-exempt (resolves the repo explicitly)"
    else
      bad "$NAME: rig-scoped but work_dir ($WORK_DIR) is not a rig worktree and no '# worktree-exempt:' marker explains why — its gh/git resolve to the city repo, not the rig it serves"
    fi
  fi
done

echo
echo "agent-worktree-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
