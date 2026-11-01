#!/usr/bin/env bash
# Hermetic test for assets/scripts/work-enter.sh: a session that claims a step part
# way through a run enters the recorded tree as the session now holding it, and a
# work bead closed mid-run ends the run instead.
#
# No live city, Dolt or network: a real git tree, a gc stub over a JSON store, a
# stub of run-cancel.sh, and the real decline.sh and work-lib.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-enter-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name tester
git config --file "$GIT_CONFIG_GLOBAL" user.email tester@example.com
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

PACK="$TMP/pack"; mkdir -p "$PACK" "$TMP/bin"
cp "$HERE/work-enter.sh" "$HERE/work-lib.sh" "$HERE/decline.sh" "$HERE/bd-lib.sh" "$PACK/"
cat > "$PACK/run-cancel.sh" <<'STUB'
#!/usr/bin/env bash
printf 'cancel %s\n' "$*" >> "$LOG"
STUB
chmod +x "$PACK/run-cancel.sh"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "runtime drain-ack") printf 'drain\n' >> "$LOG"; exit 0 ;;
  "convoy status")
    ONE='{"children":[{"id":"tk-w"}]}'
    printf '%s\n' "${CONVOY:-$ONE}"; exit 0 ;;
  "hook current") [ -n "${HOOK_CURRENT:-}" ] || exit 1; printf '%s\n' "$HOOK_CURRENT"; exit 0 ;;
  "bd show")
    [ -z "${SHOW_DOWN:-}" ] || exit 1
    out=$(jq -c --arg id "$3" '[.[] | select(.id == $id)]' "$STORE")
    if [ "$out" = "[]" ]; then printf '{"error":"no issues found matching the provided IDs"}\n'; exit 1; fi
    printf '%s\n' "$out"; exit 0 ;;
  "bd update") shift 2; printf 'update %s\n' "$*" >> "$LOG"; exit "${UPDATE_RC:-0}" ;;
esac
echo "gc stub: unsupported '$*'" >&2
exit 2
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" LOG="$TMP/log" STORE="$TMP/store.json"

T="$TMP/tree"
git init -q "$T"
git -C "$T" commit -q --allow-empty -m base
git -C "$T" branch polecat/tk-w

row() { # <status> <metadata json>
  jq -nc --arg s "$1" --argjson m "$2" --arg t "$T" '[{id: "tk-w", status: $s, notes: "a late correction", metadata: ({work_dir: $t, branch: "polecat/tk-w"} + $m)},
    {id: "iter-1", status: "in_progress", metadata: {"gc.step_ref": "self-review.iteration.1", "gc.root_bead_id": "root-1"}}]' > "$STORE"
  : > "$LOG"
}
run() {
  OUT=$(cd "$TMP" && env WORK_READ_WAIT=0 GC_SESSION_ID=sess-me HOOK_CURRENT=iter-1 "$@" "$PACK/work-enter.sh" --convoy cv-1 --step self-review 2>"$TMP/err"); RC=$?
}

git -C "$T" checkout -q main
row open '{}'
run
eq "$RC" 0 "an open bead: exits 0"
eq "$(printf '%s\n' "$OUT" | tail -n 1)" "$T" "the last line is the worktree"
has "$OUT" "a late correction" "the notes, read at this moment, are printed"
eq "$(git -C "$T" branch --show-current)" "polecat/tk-w" "the recorded branch is checked out"
case "$(cat "$LOG")" in *"update tk-w"*) bad "entering the tree writes nothing on the work bead" ;; *) ok "entering the tree writes nothing on the work bead" ;; esac
has "$(cat "$LOG")" "update root-1 --set-metadata gc.var.issue=tk-w" "a self-review iteration stamps the root's issue"

row closed '{}'
run
eq "$RC" 1 "a closed bead: stops"
has "$(cat "$LOG")" "cancel --step self-review --reason work bead tk-w was closed while its run was mid-flight" "the run is cancelled"
has "$(cat "$LOG")" "drain" "the session drains"

jq -nc '[{id: "tk-w", status: "open", metadata: {work_dir: "/nowhere/at/all"}}]' > "$STORE"; : > "$LOG"
run
eq "$RC" 1 "a work_dir that is gone: stops"
has "$(cat "$TMP/err")" "is missing: /nowhere/at/all" "and says which"
jq -nc '[{id: "tk-w", status: "open", metadata: {}}]' > "$STORE"; : > "$LOG"
run
eq "$RC" 1 "no work_dir recorded: stops"

row open '{}'
run SHOW_DOWN=1
eq "$RC" 1 "a store that does not answer: stops"
has "$(cat "$TMP/err")" "The store did not answer" "and says so"
has "$(cat "$LOG")" "drain" "and the step goes back to the pool"

printf '[]' > "$STORE"; : > "$LOG"
run
eq "$RC" 1 "no such bead: stops"

row open '{}'
run 'CONVOY={"children":[]}'
eq "$RC" 1 "a convoy with no single bead: stops"

row open '{}'
OUT=$(cd "$TMP" && env WORK_READ_WAIT=0 GC_SESSION_ID=sess-me HOOK_CURRENT=iter-1 "$PACK/work-enter.sh" --convoy cv-1 --step mol-polecat-work.submit-and-exit 2>/dev/null)
case "$(cat "$LOG")" in *"gc.var.issue"*) bad "another step does not stamp the root" ;; *) ok "another step does not stamp the root" ;; esac

for a in "" "--convoy c" "--step s" "--convoy c --bead b --step s" "--nope"; do
  # shellcheck disable=SC2086  # each case's words are the arguments
  "$PACK/work-enter.sh" $a >/dev/null 2>&1; eq "$?" 2 "usage error for: ${a:-no arguments}"
done

echo
echo "work-enter: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
