#!/usr/bin/env bash
# Hermetic test for assets/scripts/rig-checks.sh: each declared check reaches `gctk
# rig` verbatim, whatever its command holds, through the step's own call as a pour
# renders it, and the exit tells a failed check from one that could not say.
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
if [ "$1 $2" = "gc-toolkit scripts-dir" ]; then
  printf '%s\n' "$SCRIPTS_DIR"
  exit 0
fi
if [ "$1 $2" = "bd show" ]; then
  [ -z "${GC_SHOW_DOWN:-}" ] || exit 1
  jq -nc --arg id "$3" --arg d "${WORK_DIR-$T}" '[{id: $id, metadata: ({work_dir: $d} | with_entries(select(.value != "")))}]'
  exit 0
fi
printf 'GC %s\n' "$*" >> "$LOG"
exit "${GC_UPDATE_RC:-0}"
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" GCTK_BIN="$TMP/gctk" LOG="$TMP/log" T WORK_READ_WAIT=0 SCRIPTS_DIR="$HERE"

run() { # <mode args...>
  : > "$LOG"
  OUT=$(cd "$T" && "$SCRIPT" "$@" 2>&1 </dev/null); RC=$?
}

echo "# a command reaches gctk verbatim"
QUOTED=$'pnpm test --grep "a b" && echo \'done\' $(git diff --name-only origin/main...HEAD)'
run preflight --test "$QUOTED"
eq "$(cat "$LOG")" "<test><--scope><full><--command><$QUOTED>" "both quote kinds, and a substitution, arrive as written"
run preflight --typecheck tsc --lint "" --test ""
eq "$(cat "$LOG")" "<typecheck><--command><tsc>" "preflight skips an empty command"
run preflight --typecheck tsc
eq "$(cat "$LOG")" "<typecheck><--command><tsc>" "and an absent one"

echo "# preflight runs every declared check and reports the worst"
THREE=(--typecheck t --lint l --test x)
run preflight "${THREE[@]}"
eq "$RC" 0 "all pass: exits 0"
eq "$(grep -c . "$LOG")" 3 "all three run"
RC_lint=1 run preflight "${THREE[@]}"
eq "$RC" 1 "a fail exits 1"
eq "$(grep -c . "$LOG")" 3 "the checks after it still run"
RC_typecheck=4 run preflight "${THREE[@]}"
eq "$RC" 4 "a check that could not say exits 4"
RC_typecheck=1 RC_lint=4 run preflight "${THREE[@]}"
eq "$RC" 4 "could-not-say outranks a fail"
RC_typecheck=4 RC_lint=1 run preflight "${THREE[@]}"
eq "$RC" 4 "whichever comes first"
no "$(cat "$LOG")" "--publish-bead" "preflight publishes nothing"

echo "# setup"
run setup --setup 'pnpm i'
eq "$(cat "$LOG")" "<setup><--command><pnpm i>" "setup runs its command"
run setup --setup ''
eq "$(cat "$LOG")" "" "an empty setup runs nothing"
eq "$RC" 0 "and exits 0"

echo "# self-review"
ALL=(--setup s --typecheck t --lint l --build b --affected a --test x)
run self-review --bead tk-w "${ALL[@]}"
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

run self-review --bead tk-w --test x
has "$(cat "$LOG")" "<test><--scope><full><--command><x><--publish-bead><tk-w>" "with no affected command, the full suite runs"
has "$(cat "$LOG")" "<typecheck><--nothing-declared><--publish-bead><tk-w>" "a check with no command records a pass that ran nothing"
has "$(cat "$LOG")" "<lint><--nothing-declared><--publish-bead><tk-w>" "lint too"
NOTE=$(sed -n 's/^GC bd update tk-w --set-metadata self_review_setup_build=//p' "$LOG")
eq "$(jq -r '[.setup,.build] | join(" ")' <<<"$NOTE")" "none none" "setup and build with no command note none"
run self-review --bead tk-w
has "$(cat "$LOG")" "<test><--nothing-declared><--publish-bead><tk-w>" "with no test command at all, test records nothing declared"

RC_setup=1 run self-review --bead tk-w "${ALL[@]}"
eq "$RC" 1 "a failed setup exits 1"
NOTE=$(sed -n 's/^GC bd update tk-w --set-metadata self_review_setup_build=//p' "$LOG")
eq "$(jq -r '.setup' <<<"$NOTE")" "fail" "and the note records it"
RC_build=1 run self-review --bead tk-w "${ALL[@]}"
eq "$RC" 1 "a failed build exits 1"
RC_test=4 run self-review --bead tk-w "${ALL[@]}"
eq "$RC" 4 "a test run that could not say exits 4"

echo wip > "$T/wip.txt"
run self-review --bead tk-w "${ALL[@]}"
no "$(cat "$LOG")" "self_review_setup_build" "a dirty tree notes no outcome at HEAD"
rm -f "$T/wip.txt"
GC_UPDATE_RC=1 run self-review --bead tk-w "${ALL[@]}"
eq "$RC" 1 "a note that does not land exits 1"
has "$OUT" "did not land on tk-w" "and says so"

echo "# self-review runs in the tree the work bead records"
REAL_T=$(cd "$T" && pwd -P)
: > "$LOG"; : > "$TMP/pwd"
OUT=$(cd "$TMP" && PWD_LOG="$TMP/pwd" "$SCRIPT" self-review --bead tk-w "${ALL[@]}" 2>&1); RC=$?
eq "$RC" 0 "from a directory that is no repository: exits 0"
eq "$(sort -u "$TMP/pwd")" "$REAL_T" "every check runs in the recorded tree"
eq "$(grep -c . "$TMP/pwd")" 5 "all five checks run there"
NOTE=$(sed -n 's/^GC bd update tk-w --set-metadata self_review_setup_build=//p' "$LOG")
eq "$(jq -r '.commit' <<<"$NOTE")" "$(git -C "$T" rev-parse HEAD)" "and the note names that tree's HEAD"

: > "$LOG"
OUT=$(cd "$TMP" && WORK_DIR="" "$SCRIPT" self-review --bead tk-w "${ALL[@]}" 2>&1); RC=$?
eq "$RC" 4 "no work_dir recorded: could not say"
has "$OUT" "none recorded" "and says so"
eq "$(cat "$LOG")" "" "and runs nothing"

: > "$LOG"
OUT=$(cd "$TMP" && WORK_DIR="$TMP/gone" "$SCRIPT" self-review --bead tk-w "${ALL[@]}" 2>&1); RC=$?
eq "$RC" 4 "a work_dir no longer on disk: could not say"
has "$OUT" "$TMP/gone" "and names it"
eq "$(cat "$LOG")" "" "and runs nothing"

: > "$LOG"
OUT=$(cd "$TMP" && GC_SHOW_DOWN=1 "$SCRIPT" self-review --bead tk-w "${ALL[@]}" 2>&1); RC=$?
eq "$RC" 4 "a store that does not answer: could not say"
has "$OUT" "could not read tk-w" "and says so"
eq "$(cat "$LOG")" "" "and runs nothing"

: > "$LOG"
OUT=$(cd "$T" && GC_SHOW_DOWN=1 "$SCRIPT" preflight "${THREE[@]}" 2>&1); RC=$?
eq "$RC" 0 "preflight reads no bead"
eq "$(grep -c . "$LOG")" 3 "and runs where it was called"

echo "# the step's own call, as a pour renders it"
# The pour writes each var into the step as it stands, so the block here is what a
# session runs: the formula's own text, with its call reaching this checkout's script
# through the stub's scripts-dir. V_<CHECK> is what the rig declares for that check.
MULTI=$'printf first\nprintf second'
HEREDOC=$'cat <<EOF > out.txt\nit\'s "a" $(not run) `nor this` ) ( \\ $HOME\n\nEOF\nrun out.txt'
LOOKALIKE=$'lint=not a check\n--test not a flag\n\ntest=1'
render_call() { # <mode>
  local block
  block=$(awk -v call="rig-checks.sh\" $1 " '
    /^```bash$/ {buf = ""; f = 1; next}
    /^```$/ {if (f && index(buf, call)) {printf "%s", buf; exit} f = 0; next}
    f {buf = buf $0 "\n"}' "$HERE/../../formulas/mol-polecat-work.toml")
  printf '%s\n' "$block" | jq -Rr \
    --arg setup "${V_SETUP-}" --arg typecheck "${V_TYPECHECK-}" --arg lint "${V_LINT-}" \
    --arg build "${V_BUILD-}" --arg affected "${V_AFFECTED-}" --arg test "${V_TEST-}" '
    {binding_prefix: "gc-toolkit.", setup_command: $setup, typecheck_command: $typecheck,
     lint_command: $lint, build_command: $build, affected_tests_command: $affected,
     test_command: $test} as $v
    | reduce ($v | to_entries[]) as $e (.; split("{{" + $e.key + "}}") | join($e.value))' \
    | sed 's/<the work bead>/tk-w/'
}
# run_call <shell> <mode> : a session's shell runs the rendered block in the tree.
run_call() {
  render_call "$2" > "$TMP/block.sh"
  : > "$LOG"
  case "$1" in
    zsh) OUT=$(cd "$T" && zsh -f "$TMP/block.sh" 2>&1 </dev/null); RC=$? ;;
    *)   OUT=$(cd "$T" && bash "$TMP/block.sh" 2>&1 </dev/null); RC=$? ;;
  esac
}
SHELLS=(bash)
command -v zsh >/dev/null 2>&1 && SHELLS+=(zsh)
for sh in "${SHELLS[@]}"; do
  V_SETUP="$HEREDOC" run_call "$sh" setup
  eq "$RC" 0 "$sh setup: the rendered call exits 0"
  eq "$(cat "$LOG")" "<setup><--command><$HEREDOC>" "$sh setup: a command holding a here-document arrives whole"

  V_TYPECHECK="$MULTI" V_LINT="$HEREDOC" V_TEST="$QUOTED" run_call "$sh" preflight
  eq "$RC" 0 "$sh preflight: the rendered call exits 0"
  eq "$(cat "$LOG")" "<typecheck><--command><$MULTI>
<lint><--command><$HEREDOC>
<test><--scope><full><--command><$QUOTED>" "$sh preflight: more lines than one, a here-document and both quote kinds arrive whole"

  V_LINT="$MULTI" RC_lint=1 run_call "$sh" preflight
  eq "$RC" 1 "$sh preflight: the block answers what the script answers"
  V_LINT="$MULTI" RC_lint=4 run_call "$sh" preflight
  eq "$RC" 4 "$sh preflight: could-not-say too"
  V_TEST=$'x\n\n' run_call "$sh" preflight
  eq "$(cat "$LOG")" "<test><--scope><full><--command><x>" "$sh preflight: trailing newlines drop, as self-review-check.sh reads the declared command"
  run_call "$sh" preflight
  eq "$RC|$(cat "$LOG")" "0|" "$sh preflight: a rig that declares nothing runs nothing"

  V_SETUP="$LOOKALIKE" V_TYPECHECK="$MULTI" V_LINT="$HEREDOC" V_BUILD="$QUOTED" V_AFFECTED="$MULTI" V_TEST=whole run_call "$sh" self-review
  eq "$RC" 0 "$sh self-review: the rendered call exits 0"
  has "$(cat "$LOG")" "<setup><--command><$LOOKALIKE>" "$sh self-review: lines that read as a check or a flag stay inside the command"
  has "$(cat "$LOG")" "<typecheck><--command><$MULTI><--publish-bead><tk-w>" "$sh self-review: typecheck arrives whole and publishes"
  has "$(cat "$LOG")" "<lint><--command><$HEREDOC><--publish-bead><tk-w>" "$sh self-review: lint too"
  has "$(cat "$LOG")" "<build><--command><$QUOTED>" "$sh self-review: build too"
  has "$(cat "$LOG")" "<test><--scope><affected><--command><$MULTI><--publish-bead><tk-w>" "$sh self-review: and the affected subset"
  eq "$(grep -c 'set-metadata self_review_setup_build=' "$LOG" | tr -d ' ')" 1 "$sh self-review: the block notes setup and build once"

  # Each slot of each call, alone, with a command that a slip in that slot would
  # change: an unquoted delimiter runs its substitutions, and a var of the wrong
  # name leaves the check undeclared. "-" is a check that publishes nothing.
  while read -r mode var check publishes; do
    printf -v "V_$var" '%s' "$HEREDOC"
    run_call "$sh" "$mode"
    unset "V_$var"
    want="$check<--command><$HEREDOC>"
    [ "$publishes" = - ] || want="$want<--publish-bead><tk-w>"
    eq "$RC" 0 "$sh $mode $var: the rendered call exits 0"
    has "$(cat "$LOG")" "$want" "$sh $mode $var: this slot alone hands its command over whole"
  done <<'SLOTS'
setup SETUP <setup> -
preflight TYPECHECK <typecheck> -
preflight LINT <lint> -
preflight TEST <test><--scope><full> -
self-review SETUP <setup> -
self-review TYPECHECK <typecheck> publishes
self-review LINT <lint> publishes
self-review BUILD <build> -
self-review AFFECTED <test><--scope><affected> publishes
self-review TEST <test><--scope><full> publishes
SLOTS
done

echo "# usage"
run; eq "$RC" 2 "no mode: usage error"
run nope; eq "$RC" 2 "an unknown mode: usage error"
run self-review; eq "$RC" 2 "self-review without --bead: usage error"
run preflight --bead x; eq "$RC" 2 "preflight with --bead: usage error"
run preflight --nope; eq "$RC" 2 "an unknown flag: usage error"
run preflight --test; eq "$RC" 2 "a check with no value: usage error"
has "$OUT" "--test requires a value" "and says so"
eq "$(cat "$LOG")" "" "and runs nothing"

echo
echo "rig-checks: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
