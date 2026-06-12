#!/usr/bin/env bash
# Hermetic test for doc-keeper-rolling-cycle.sh.
#
# Uses real temp git repos (a bare "remote" + a working clone the script runs
# in) and a fake `gh` on PATH backed by a text PR ledger. No dependency on the
# live city, GitHub, or the network. Covers: (a) opening the first cycle from
# an empty repo, with an empty seed commit and a tracking PR; (b) idempotent
# re-runs return the same cycle and open nothing new; (c) the caller's checkout
# is never disturbed; (d) a merged cycle's number is retired (next = N+1);
# (e) an abandoned (closed) cycle's number is also retired; (f) lowest-N wins
# when two cycles are open at once; (g) a crashed creation (branch pushed, PR
# missing) self-heals instead of forking a duplicate.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/doc-keeper-rolling-cycle.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

commit() { echo "$2" > "$1/f.txt"; git -C "$1" add -A; git -C "$1" commit -qm "$2"; }

# --- Build a remote with two commits on main, then a working clone. ----------
SRC="$TMP/src"; git init -q -b main "$SRC"; commit "$SRC" c1; commit "$SRC" c2
git clone -q --bare "$SRC" "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/caller"
MAIN_TREE="$(git -C "$TMP/remote.git" rev-parse "main^{tree}")"

# --- Fake gh: models `gh pr list` and `gh pr create` against a ledger. --------
# Ledger lines are "<head>|<state>" with state in open|closed|merged.
mkdir -p "$TMP/bin"
LEDGER="$TMP/pr-ledger"; : > "$LEDGER"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
set -eu
[ "${1:-}" = "pr" ] || { echo "fake gh: unsupported: $*" >&2; exit 2; }
sub="$2"; shift 2
state=all; head=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state) state="$2"; shift 2 ;;
    --head)  head="$2";  shift 2 ;;
    --base|--limit|--json|--title|--body|--repo) shift 2 ;;
    *) shift ;;
  esac
done
case "$sub" in
  list)
    awk -F'|' -v st="$state" '
      BEGIN { printf "[" }
      NF>=2 && (st=="all" || $2==st) {
        if (n++) printf ",";
        printf "{\"number\":%d,\"headRefName\":\"%s\"}", NR, $1
      }
      END { print "]" }' "$FAKE_PR_LEDGER" ;;
  create)
    if awk -F'|' -v h="$head" '$1==h && $2=="open"{f=1} END{exit !f}' "$FAKE_PR_LEDGER"; then
      echo "fake gh: a pull request for $head already exists" >&2; exit 1
    fi
    printf '%s|open\n' "$head" >> "$FAKE_PR_LEDGER"
    echo "https://example.test/pr/$head" ;;
  *) echo "fake gh: unsupported pr $sub" >&2; exit 2 ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_PR_LEDGER="$LEDGER"

run() { ( cd "$TMP/caller" && bash "$SCRIPT" 2>/dev/null ); }
open_count()    { awk -F'|' -v h="$1" '$1==h && $2=="open"'    "$LEDGER" | wc -l | tr -d ' '; }
has_branch()    { git -C "$TMP/remote.git" rev-parse --verify --quiet "refs/heads/$1" >/dev/null; }
ahead_count()   { git -C "$TMP/remote.git" rev-list --count "main..$1"; }
branch_tree()   { git -C "$TMP/remote.git" rev-parse "$1^{tree}"; }
set_state()     { sed -i "s#^$1|[^|]*#$1|$2#" "$LEDGER"; }

CALLER_BRANCH="$(git -C "$TMP/caller" symbolic-ref --short HEAD)"

# --- (a) First cycle opens from an empty repo. -------------------------------
out="$(run)"
eq "$out" "docs/rolling-1" "first run opens cycle 1"
has_branch "docs/rolling-1" && ok "cycle-1 branch pushed to remote" || bad "cycle-1 branch pushed to remote"
eq "$(ahead_count docs/rolling-1)" "1" "cycle-1 branch is one commit ahead of main"
eq "$(branch_tree docs/rolling-1)" "$MAIN_TREE" "cycle-1 seed commit is empty (tree == main)"
eq "$(open_count docs/rolling-1)" "1" "cycle-1 tracking PR opened"

# --- (c) The caller's checkout is untouched (commit-tree side-effect free). ---
eq "$(git -C "$TMP/caller" symbolic-ref --short HEAD)" "$CALLER_BRANCH" "caller stays on its branch"
eq "$(git -C "$TMP/caller" status --porcelain)" "" "caller working tree stays clean"

# --- (b) Idempotent: re-run returns the same cycle, opens nothing new. --------
out="$(run)"
eq "$out" "docs/rolling-1" "re-run returns the open cycle"
eq "$(open_count docs/rolling-1)" "1" "re-run does not duplicate the PR"
has_branch "docs/rolling-2" && bad "re-run must not open cycle 2" || ok "re-run does not open cycle 2"

# --- (d) Merged cycle retires its number: next run opens cycle 2. ------------
set_state "docs/rolling-1" "merged"
out="$(run)"
eq "$out" "docs/rolling-2" "after merge, next run opens cycle 2"
eq "$(open_count docs/rolling-2)" "1" "cycle-2 tracking PR opened"

# --- (e) Abandoned (closed) cycle also retires its number: next opens 3. ------
set_state "docs/rolling-2" "closed"
out="$(run)"
eq "$out" "docs/rolling-3" "after a closed/abandoned cycle, next run opens cycle 3"

# --- (f) Lowest-N wins when two cycles are open at once. ----------------------
printf 'docs/rolling-8|open\ndocs/rolling-9|open\n' > "$LEDGER"
out="$(run)"
eq "$out" "docs/rolling-8" "lowest-numbered open cycle wins"
has_branch "docs/rolling-10" && bad "discovery must not open a new cycle" || ok "discovery opens nothing new"

# --- (g) Crashed creation self-heals: orphan branch, no PR -> open its PR. ----
# Empty PR history (max = 0 -> next = 1) while docs/rolling-1 still exists on
# the remote from case (a). The retry must adopt that branch and open the
# missing PR, NOT fork docs/rolling-2.
: > "$LEDGER"
out="$(run)"
eq "$out" "docs/rolling-1" "crashed creation heals onto the orphan branch"
eq "$(open_count docs/rolling-1)" "1" "heal opens the missing tracking PR"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
