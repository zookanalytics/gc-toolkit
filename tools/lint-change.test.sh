#!/usr/bin/env bash
# lint-change.test.sh — tools/lint-change.sh, the repository's lint that
# `make lint` runs.
#
# Asserted here:
#   - it runs tools/lint-learned.sh and then tools/lint.sh from the root, each
#     given the files the change since BASE names, root-relative and each
#     whole: a name with a space, one with a non-ASCII character and one with a
#     tab among them; lint.sh is given BASE too;
#   - both run whichever fails, and the run exits 1 when either fails, 0 when
#     both pass;
#   - a change that names no file gives each of them no file;
#   - a run from a directory below the root runs them from the root;
#   - no BASE, an option for one, a second argument and a BASE git cannot read
#     are usage errors that run neither;
#   - with the real lint.sh, its step-text lint and its warrant list read the
#     change from the BASE the run names, where that and origin/main part ways,
#     and where there is no origin/main.
#
# Hermetic: runs a copy of lint-change.sh in a throwaway git repository, with
# stand-ins for tools/lint-learned.sh and tools/lint.sh that log each call. The
# last section runs copies of the real lint.sh, lint-step-text.sh and
# warrants-touched.sh in a repository of its own.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lint-change-test.XXXXXX")" || { echo "cannot mktemp"; exit 1; }
TMP="$(cd "$TMP" && pwd -P)" || { echo "cannot resolve the temp dir"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
LOG="$TMP/calls"
mkdir -p "$REPO/tools" "$REPO/docs"
cp "$SRC/tools/lint-change.sh" "$REPO/tools/lint-change.sh"
# Each stand-in logs its name, the directory it ran in and its argument count,
# then each argument on a line of its own between brackets, and exits with its
# STUB_*_RC.
for stub in lint-learned:STUB_LEARNED_RC lint:STUB_LINT_RC; do
  name="${stub%%:*}" rc_var="${stub#*:}"
  cat > "$REPO/tools/$name.sh" <<F
#!/usr/bin/env bash
printf '%s %s cwd=%s\n' "$name" "\$#" "\$PWD" >> "\$STUB_LOG"
for a in "\$@"; do printf '  [%s]\n' "\$a" >> "\$STUB_LOG"; done
exit "\${$rc_var:-0}"
F
  chmod +x "$REPO/tools/$name.sh"
done
printf '# notes\n' > "$REPO/docs/notes.md"
printf 'gone\n' > "$REPO/docs/gone.md"

gitc() { git -C "$REPO" -c user.name=lint-change-test -c user.email=lint-change-test@example.invalid -c commit.gpgsign=false "$@"; }
git -C "$REPO" init -q
gitc config core.quotePath true
gitc add -A
gitc commit -q -m base
gitc branch base

# run [dir] <args...> -> RC, OUT and CALLS: a run of the copy's lint-change.sh
# from the root, or from REPO/<dir> when the first argument is --in <dir>.
run() {
  local dir="$REPO"
  if [ "${1:-}" = --in ]; then dir="$REPO/$2"; shift 2; fi
  : > "$LOG"
  OUT="$(cd "$dir" && env STUB_LOG="$LOG" bash "$REPO/tools/lint-change.sh" "$@" 2>&1)"; RC=$?
  CALLS="$(cat "$LOG")"
}

echo "── the change, to both linters ──"
gitc checkout -q -b change base
printf '# notes, changed\n' > "$REPO/docs/notes.md"
printf 'x\n' > "$REPO/docs/my file.md"
printf 'x\n' > "$REPO/docs/caf"$'\xc3\xa9'".md"
printf 'x\n' > "$REPO/docs/a"$'\t'"b.md"
gitc rm -q docs/gone.md
gitc add -A
gitc commit -q -m "change docs"
files="$(printf '  [%s]\n' "docs/a"$'\t'"b.md" "docs/caf"$'\xc3\xa9'".md" "docs/gone.md" "docs/my file.md" "docs/notes.md")"
want="$(printf 'lint-learned 5 cwd=%s\n%s\nlint 8 cwd=%s\n  [--base]\n  [base]\n  [--]\n%s' "$REPO" "$files" "$REPO" "$files")"
run base
eq "$RC" 0 "both linters passing passes"
eq "$CALLS" "$want" "lint-learned.sh runs, then lint.sh with the base, from the root, each given every file the change names, each whole"

echo "── one fails, both run ──"
STUB_LEARNED_RC=1 run base
eq "$RC" 1 "a learned-rule finding fails the run"
eq "$(printf '%s\n' "$CALLS" | grep -c '^lint ')" 1 "…and lint.sh still runs"
STUB_LEARNED_RC=2 run base
eq "$RC" 1 "lint-learned.sh that could not run fails the run"
eq "$(printf '%s\n' "$CALLS" | grep -c '^lint ')" 1 "…and lint.sh still runs"
STUB_LINT_RC=1 run base
eq "$RC" 1 "a lint.sh finding fails the run"
eq "$(printf '%s\n' "$CALLS" | grep -c '^lint-learned ')" 1 "…after lint-learned.sh ran"
STUB_LEARNED_RC=1 STUB_LINT_RC=1 run base
eq "$RC" 1 "both failing fails the run"
eq "$(printf '%s\n' "$CALLS" | grep -cE '^lint(-learned)? ')" 2 "…with both run"

echo "── a run from below the root ──"
run --in docs base
eq "$RC" 0 "a run from docs/ passes"
eq "$CALLS" "$want" "…and runs both from the root, with root-relative names"

echo "── a change that names no file ──"
gitc checkout -q -b same base
run base
eq "$RC" 0 "a change that names no file passes when both pass"
eq "$CALLS" "$(printf 'lint-learned 0 cwd=%s\nlint 3 cwd=%s\n  [--base]\n  [base]\n  [--]' "$REPO" "$REPO")" "…and gives each linter no file"

echo "── usage ──"
for args in "" "--list" "base extra" "no-such-ref"; do
  # shellcheck disable=SC2086  # each case's words are the arguments
  run $args
  eq "$RC" 2 "'lint-change.sh $args' is a usage error"
  eq "$CALLS" "" "…that runs neither linter"
done
run no-such-ref
has "$OUT" "cannot read the change from no-such-ref to HEAD" "a BASE git cannot read is named"
run --help
eq "$RC" 0 "--help exits 0"
has "$OUT" "lint-change.sh BASE" "…printing the usage"

echo "── the base reaches lint.sh's parts that read the change ──"
# A skill gains a procedure on the branch landed, and topic is cut from landed.
# Since the older base, topic's change adds the procedure and touches the
# warrant that covers the skill, and since landed it does neither. The real
# lint.sh, lint-step-text.sh and warrants-touched.sh run here, and git ignores
# them, so no shell file or go.mod is tracked and the shell and Go lints have
# nothing to run. Stand-ins take the place of lint-learned.sh and the shellcheck
# runner.
E2E="$TMP/e2e"
mkdir -p "$E2E/tools" "$E2E/assets/scripts" "$E2E/docs" "$E2E/skills/example"
for t in lint-change.sh lint.sh lint-step-text.sh warrants-touched.sh; do
  cp "$SRC/tools/$t" "$E2E/tools/$t"
done
printf '#!/usr/bin/env bash\nexit 0\n' > "$E2E/tools/lint-learned.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$E2E/assets/scripts/shellcheck-run.sh"
chmod +x "$E2E"/tools/*.sh "$E2E/assets/scripts/shellcheck-run.sh"
printf '# Warrants\n\n## Example warrant\n\n- **Covers.** `skills/example/SKILL.md`\n- **Verified.** 2026-11-24\n' > "$E2E/docs/warrants.md"
printf '# Example\n' > "$E2E/skills/example/SKILL.md"
printf '# notes\n' > "$E2E/docs/notes.md"
e2ec() { git -C "$E2E" -c user.name=lint-change-test -c user.email=lint-change-test@example.invalid -c commit.gpgsign=false "$@"; }
git -C "$E2E" init -q
printf 'tools/\nassets/\n' >> "$E2E/.git/info/exclude"
e2ec add -A
e2ec commit -q -m base
e2ec branch older
e2ec checkout -q -b landed
printf '# Example\n\n```bash\necho one\necho two\n```\n' > "$E2E/skills/example/SKILL.md"
e2ec commit -q -am "the skill gains a procedure"
e2ec update-ref refs/remotes/origin/main landed
e2ec checkout -q -b topic
printf '# notes, changed\n' > "$E2E/docs/notes.md"
e2ec commit -q -am "change the notes"
run_e2e() { OUT="$(cd "$E2E" && bash tools/lint-change.sh "$@" 2>&1)"; RC=$?; }

run_e2e older
eq "$RC" 1 "a base before the procedure fails the run"
has "$OUT" "step and skill text: FAIL — a change adds a procedure" "…because the step-text lint reads the change from it"
has "$OUT" "warrants: touched, listed above" "…and the warrant list does too"
run_e2e origin/main
eq "$RC" 0 "origin/main, after the procedure, passes"
has "$OUT" "step and skill text: clean" "…with no procedure added since it"
has "$OUT" "warrants: none touched" "…and no warrant touched"
e2ec update-ref -d refs/remotes/origin/main
run_e2e landed
eq "$RC" 0 "a base that names the commit origin/main named passes with no origin/main"

printf '\nlint-change: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
