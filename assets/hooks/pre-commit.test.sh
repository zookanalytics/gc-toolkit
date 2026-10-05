#!/usr/bin/env bash
# pre-commit.test.sh — behaviour tests for the docs-binary guard in
# assets/hooks/pre-commit: a commit that stages a binary file under a docs/
# directory is refused before it lands, and every other commit goes through.
# What the detector calls binary is pinned in tools/lint-learned.d.test.sh;
# this suite is about the hook that runs it.
#
# Git runs only the file named for the hook, so this suite can sit beside it in
# core.hooksPath without ever running as a hook.
#
# Hermetic: a throwaway repository wired through core.hooksPath to copies of
# the real hook and the real detector, at their pack paths. No live city, no
# gc, no network. No fixture commit touches a seed input, so the hook's
# seed-audit half exits before the render.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/pre-commit"
DET="$HERE/../../tools/lint-learned.d/docs-binary.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

[ -f "$HOOK" ] || { echo "no hook at $HOOK"; exit 1; }
[ -x "$DET" ] || { echo "no detector at $DET"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pre-commit-test.XXXXXX")" || { echo "cannot allocate a tempdir"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Ambient git state must not reach the fixture repo: no signing key, no global
# hooks, and no repository inherited from a caller that is itself a hook.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

REPO="$TMP/repo"
GUARD="$REPO/tools/lint-learned.d/docs-binary.sh"
mkdir -p "$REPO/assets/hooks" "$REPO/tools/lint-learned.d"
cp "$HOOK" "$REPO/assets/hooks/pre-commit"
cp "$DET" "$GUARD"
chmod +x "$REPO/assets/hooks/pre-commit" "$GUARD"
git -c init.defaultBranch=main init -q "$REPO"
git -C "$REPO" config user.name "pre-commit test"
git -C "$REPO" config user.email "pre-commit-test@example.invalid"
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" config core.hooksPath assets/hooks
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "fixture: the hook and the detector" || { echo "cannot make the base commit"; exit 1; }

PNG='\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR'

# attempt <path> <bytes> — stage one file, try to commit it, and leave the index
# clean for the next attempt. Sets RC, OUT, and LANDED (yes/no: did HEAD move).
attempt() {
    local path="$1" before
    mkdir -p "$REPO/$(dirname "$path")"
    printf '%b' "$2" > "$REPO/$path"
    git -C "$REPO" add -- "$path"
    before="$(git -C "$REPO" rev-parse HEAD)"
    OUT="$(git -C "$REPO" commit -q -m "add $path" 2>&1)"; RC=$?
    if [ "$(git -C "$REPO" rev-parse HEAD)" = "$before" ]; then LANDED=no; else LANDED=yes; fi
    git -C "$REPO" reset -q
}

echo "── a binary under docs/ is refused ──"

attempt docs/shot.png "$PNG"
eq "$LANDED" no "an image under the root docs/ does not land"
if [ "$RC" -ne 0 ]; then ok "and the commit exits non-zero"; else bad "and the commit exits non-zero" "rc=$RC"; fi
has "$OUT" "docs/shot.png:1:" "the refusal names the file"
has "$OUT" "commit refused" "the refusal says the commit was refused"
has "$OUT" "specs/<bead-id>/" "the refusal names the committed home"
has "$OUT" "demo-deliver.sh" "the refusal names the uncommitted route"

attempt services/helm/docs/screenshots/after.png "$PNG"
eq "$LANDED" no "an image under a nested docs/ does not land"

attempt "docs/my shot.png" "$PNG"
eq "$LANDED" no "a staged path with a space does not slip past"
has "$OUT" "docs/my shot.png:1:" "and it is named whole"

# Without -z, git prints a non-ASCII path quoted and escaped, which names no
# file, so the guard would wave it through.
attempt "docs/café.png" "$PNG"
eq "$LANDED" no "a staged path git would quote does not slip past"

echo "── every other commit goes through ──"

attempt specs/tk-x/screenshots/shot.png "$PNG"
eq "$LANDED" yes "a capture under specs/<bead-id>/ lands"

attempt docs/guide.md '# Guide\n\nText that stays true.\n'
eq "$LANDED" yes "a text doc under docs/ lands"

echo "── a rename into docs/ is a new path there ──"

git -C "$REPO" mv specs/tk-x/screenshots/shot.png docs/moved.png
before="$(git -C "$REPO" rev-parse HEAD)"
OUT="$(git -C "$REPO" commit -q -m "move a capture into docs" 2>&1)"
eq "$(git -C "$REPO" rev-parse HEAD)" "$before" "moving a committed capture into docs/ does not land"
has "$OUT" "docs/moved.png:1:" "and the refusal names the new path"
git -C "$REPO" reset -q --hard

echo "── a check that cannot run blocks; a retired one does not ──"

cp "$GUARD" "$TMP/guard.saved"
printf '#!/usr/bin/env bash\nexit 2\n' > "$GUARD"
attempt docs/after-break.md 'text\n'
eq "$LANDED" no "a detector that errors aborts the commit"
has "$OUT" "could not run" "and says the check could not run, not that it found something"

mv "$GUARD" "$TMP/guard.broken"
attempt docs/after-retire.md 'text\n'
eq "$LANDED" yes "with the detector gone, commits go through"
cp "$TMP/guard.saved" "$GUARD"

echo
echo "pre-commit.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
