#!/usr/bin/env bash
# Hermetic test for assets/scripts/rig-checks.sh: each declared check reaches `gctk
# rig` verbatim, whatever quotes its command carries, and the exit tells a failed
# check from one that could not say.
#
# No live city, Dolt or network: a stub gctk that records its arguments and answers
# from a table, a gc stub, and a real git tree.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/rig-checks.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rig-checks-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name tester
git config --file "$GIT_CONFIG_GLOBAL" user.email tester@example.com
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
T="$TMP/tree"
git init -q "$T"
git -C "$T" commit -q --allow-empty -m base

mkdir -p "$TMP/bin"
# Each call logs one line per argument, between angle brackets, so a command's
# quotes and spaces read back exactly. RC_<check> sets a check's exit.
cat > "$TMP/gctk" <<'GCTK'
#!/usr/bin/env bash
shift
check="$1"
[ -z "${PWD_LOG:-}" ] || pwd -P >> "$PWD_LOG"
for a in "$@"; do printf '<%s>' "$a"; done >> "$LOG"
printf '\n' >> "$LOG"
rc="RC_$check"
exit "${!rc:-0}"
GCTK
chmod +x "$TMP/gctk"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1 $2" = "bd show" ]; then
  [ -z "${GC_SHOW_DOWN:-}" ] || exit 1
  jq -nc --arg id "$3" --arg d "${WORK_DIR-$T}" '[{id: $id, metadata: ({work_dir: $d} | with_entries(select(.value != "")))}]'
  exit 0
fi
printf 'GC %s\n' "$*" >> "$LOG"
exit "${GC_UPDATE_RC:-0}"
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" GCTK_BIN="$TMP/gctk" LOG="$TMP/log" T WORK_READ_WAIT=0

run() { # <mode args...> with the checks on stdin
  : > "$LOG"
  OUT=$(cd "$T" && "$SCRIPT" "$@" 2>&1); RC=$?
}

echo "# a command reaches gctk verbatim"
QUOTED=$'pnpm test --grep "a b" && echo \'done\' $(git diff --name-only origin/main...HEAD)'
run preflight <<<"test=$QUOTED"
eq "$(cat "$LOG")" "<test><--scope><full><--command><$QUOTED>" "both quote kinds, and a substitution, arrive as written"
run preflight <<'CHECKS'
typecheck=tsc
lint=
test=
CHECKS
eq "$(cat "$LOG")" "<typecheck><--command><tsc>" "preflight skips an empty command"
run preflight <<'CHECKS'
typecheck=a=b
CHECKS
eq "$(cat "$LOG")" "<typecheck><--command><a=b>" "only the first = splits a line"

echo "# preflight runs every declared check and reports the worst"
THREE=$'typecheck=t\nlint=l\ntest=x'
run preflight <<<"$THREE"
eq "$RC" 0 "all pass: exits 0"
eq "$(grep -c . "$LOG")" 3 "all three run"
RC_lint=1 run preflight <<<"$THREE"
eq "$RC" 1 "a fail exits 1"
eq "$(grep -c . "$LOG")" 3 "the checks after it still run"
RC_typecheck=4 run preflight <<<"$THREE"
eq "$RC" 4 "a check that could not say exits 4"
RC_typecheck=1 RC_lint=4 run preflight <<<"$THREE"
eq "$RC" 4 "could-not-say outranks a fail"
RC_typecheck=4 RC_lint=1 run preflight <<<"$THREE"
eq "$RC" 4 "whichever comes first"
no "$(cat "$LOG")" "--publish-bead" "preflight publishes nothing"

echo "# setup"
run setup <<<'setup=pnpm i'
eq "$(cat "$LOG")" "<setup><--command><pnpm i>" "setup runs its command"
run setup <<<'setup='
eq "$(cat "$LOG")" "" "an empty setup runs nothing"
eq "$RC" 0 "and exits 0"

echo "# self-review"
ALL=$'setup=s\ntypecheck=t\nlint=l\nbuild=b\naffected=a\ntest=x'
run self-review --bead tk-w <<<"$ALL"
eq "$RC" 0 "all pass: exits 0"
has "$(cat "$LOG")" "<typecheck><--command><t><--publish-bead><tk-w>" "typecheck publishes to the work bead"
has "$(cat "$LOG")" "<lint><--command><l><--publish-bead><tk-w>" "lint publishes to the work bead"
has "$(cat "$LOG")" "<test><--scope><affected><--command><a><--publish-bead><tk-w>" "the affected subset runs when the rig declares one"
no "$(cat "$LOG")" "<--scope><full>" "and the full suite does not"
has "$(cat "$LOG")" "<setup><--command><s>" "setup runs"
has "$(cat "$LOG")" "<build><--command><b>" "build runs"
NOTE=$(sed -n 's/^GC bd update tk-w --set-metadata self_review_setup_build=//p' "$LOG")
eq "$(jq -r '.commit' <<<"$NOTE")" "$(git -C "$T" rev-parse HEAD)" "the note names HEAD"
eq "$(jq -r '[.setup,.build,.setup_command,.build_command] | join(" ")' <<<"$NOTE")" "pass pass s b" "the note records setup and build and their commands"

run self-review --bead tk-w <<<'test=x'
has "$(cat "$LOG")" "<test><--scope><full><--command><x><--publish-bead><tk-w>" "with no affected command, the full suite runs"
has "$(cat "$LOG")" "<typecheck><--nothing-declared><--publish-bead><tk-w>" "a check with no command records a pass that ran nothing"
has "$(cat "$LOG")" "<lint><--nothing-declared><--publish-bead><tk-w>" "lint too"
NOTE=$(sed -n 's/^GC bd update tk-w --set-metadata self_review_setup_build=//p' "$LOG")
eq "$(jq -r '[.setup,.build] | join(" ")' <<<"$NOTE")" "none none" "setup and build with no command note none"
run self-review --bead tk-w </dev/null
has "$(cat "$LOG")" "<test><--nothing-declared><--publish-bead><tk-w>" "with no test command at all, test records nothing declared"

RC_setup=1 run self-review --bead tk-w <<<"$ALL"
eq "$RC" 1 "a failed setup exits 1"
NOTE=$(sed -n 's/^GC bd update tk-w --set-metadata self_review_setup_build=//p' "$LOG")
eq "$(jq -r '.setup' <<<"$NOTE")" "fail" "and the note records it"
RC_build=1 run self-review --bead tk-w <<<"$ALL"
eq "$RC" 1 "a failed build exits 1"
RC_test=4 run self-review --bead tk-w <<<"$ALL"
eq "$RC" 4 "a test run that could not say exits 4"

echo wip > "$T/wip.txt"
run self-review --bead tk-w <<<"$ALL"
no "$(cat "$LOG")" "self_review_setup_build" "a dirty tree notes no outcome at HEAD"
rm -f "$T/wip.txt"
GC_UPDATE_RC=1 run self-review --bead tk-w <<<"$ALL"
eq "$RC" 1 "a note that does not land exits 1"
has "$OUT" "did not land on tk-w" "and says so"

echo "# self-review runs in the tree the work bead records"
REAL_T=$(cd "$T" && pwd -P)
: > "$LOG"; : > "$TMP/pwd"
OUT=$(cd "$TMP" && PWD_LOG="$TMP/pwd" "$SCRIPT" self-review --bead tk-w <<<"$ALL" 2>&1); RC=$?
eq "$RC" 0 "from a directory that is no repository: exits 0"
eq "$(sort -u "$TMP/pwd")" "$REAL_T" "every check runs in the recorded tree"
eq "$(grep -c . "$TMP/pwd")" 5 "all five checks run there"
NOTE=$(sed -n 's/^GC bd update tk-w --set-metadata self_review_setup_build=//p' "$LOG")
eq "$(jq -r '.commit' <<<"$NOTE")" "$(git -C "$T" rev-parse HEAD)" "and the note names that tree's HEAD"

: > "$LOG"
OUT=$(cd "$TMP" && WORK_DIR="" "$SCRIPT" self-review --bead tk-w <<<"$ALL" 2>&1); RC=$?
eq "$RC" 4 "no work_dir recorded: could not say"
has "$OUT" "none recorded" "and says so"
eq "$(cat "$LOG")" "" "and runs nothing"

: > "$LOG"
OUT=$(cd "$TMP" && WORK_DIR="$TMP/gone" "$SCRIPT" self-review --bead tk-w <<<"$ALL" 2>&1); RC=$?
eq "$RC" 4 "a work_dir no longer on disk: could not say"
has "$OUT" "$TMP/gone" "and names it"
eq "$(cat "$LOG")" "" "and runs nothing"

: > "$LOG"
OUT=$(cd "$TMP" && GC_SHOW_DOWN=1 "$SCRIPT" self-review --bead tk-w <<<"$ALL" 2>&1); RC=$?
eq "$RC" 4 "a store that does not answer: could not say"
has "$OUT" "could not read tk-w" "and says so"
eq "$(cat "$LOG")" "" "and runs nothing"

: > "$LOG"
OUT=$(cd "$T" && GC_SHOW_DOWN=1 "$SCRIPT" preflight <<<"$THREE" 2>&1); RC=$?
eq "$RC" 0 "preflight reads no bead"
eq "$(grep -c . "$LOG")" 3 "and runs where it was called"

echo "# usage"
run <<<''; eq "$RC" 2 "no mode: usage error"
run nope <<<''; eq "$RC" 2 "an unknown mode: usage error"
run self-review <<<''; eq "$RC" 2 "self-review without --bead: usage error"
run preflight --bead x <<<''; eq "$RC" 2 "preflight with --bead: usage error"
run preflight --nope <<<''; eq "$RC" 2 "an unknown flag: usage error"
run preflight <<<'not a check'; eq "$RC" 2 "a line that names no check: usage error"
has "$OUT" "names no check" "and says so"
eq "$(cat "$LOG")" "" "and runs nothing"

echo
echo "rig-checks: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
