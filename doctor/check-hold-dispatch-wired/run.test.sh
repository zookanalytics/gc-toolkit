#!/usr/bin/env bash
# Hermetic tests for check-hold-dispatch-wired/run.sh.
#
# A wiring check that cannot fail is decoration. Each case below builds a pack
# tree from the REAL shipped files, breaks exactly one link, and requires the
# check to report it — the same discipline the check itself exists to impose on
# the mechanism (tk-oqseh6).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
PACK="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# A fresh copy of the four files the check reads, so a case can break one.
fixture() {
  local d="$TMP/$1"; rm -rf "$d"
  mkdir -p "$d/assets/scripts" "$d/template-fragments"
  cp "$PACK/assets/scripts/hold-dispatch.sh"      "$d/assets/scripts/"
  cp "$PACK/assets/scripts/hold-dispatch.test.sh" "$d/assets/scripts/"
  cp "$PACK/template-fragments/polecat-close-step-chain.template.md" "$d/template-fragments/"
  cp "$PACK/pack.toml" "$d/pack.toml"
  printf '%s' "$d"
}

# run <dir> -> sets RC and OUT
run() { OUT=$(GC_PACK_DIR="$1" "$CHECK" 2>&1) && RC=0 || RC=$?; }

# breaks <label> <dir> <expected substring>
breaks() {
  run "$2"
  # `grep -q <<<` rather than a pipe: grep -q SIGPIPEs its writer on the first
  # match, and pipefail turns that into a failure on a match that succeeded
  # (doctor/check-pipefail-grep-q).
  if [ "$RC" = "2" ] && grep -q "$3" <<< "$OUT"; then
    ok "$1 -> reported"
  else
    bad "$1 -> expected exit 2 naming '$3' (rc=$RC): $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
  fi
}

# --- the happy path, first: a check that never passes is equally useless ------
D=$(fixture green)
run "$D"
[ "$RC" = "0" ] && ok "(GREEN) the shipped pack passes" \
  || bad "(GREEN) shipped pack must pass (rc=$RC): $OUT"

# --- the writer half ----------------------------------------------------------
D=$(fixture noscript); rm -f "$D/assets/scripts/hold-dispatch.sh"
breaks "(MISSING) script absent" "$D" "missing script"

D=$(fixture notexec); chmod -x "$D/assets/scripts/hold-dispatch.sh"
breaks "(NOTEXEC) script not executable" "$D" "not executable"

D=$(fixture nowalk)
sed -i 's/gc\.root_bead_id/gc.SOMETHING_ELSE/g' "$D/assets/scripts/hold-dispatch.sh"
breaks "(NOWALK) writer stops walking the molecule" "$D" "gc.root_bead_id"

D=$(fixture noanchor)
sed -i 's/gc\.input_convoy_id/gc.SOMETHING_ELSE/g' "$D/assets/scripts/hold-dispatch.sh"
breaks "(NOANCHOR) writer stops proving the molecule is this anchor's" "$D" "gc.input_convoy_id"

# The exemption is asserted over CODE only; deleting it from comments alone must
# not trip the check, or the pack could not document the hazard.
D=$(fixture nofinal)
grep -vE '^[[:space:]]*#' "$D/assets/scripts/hold-dispatch.sh" \
  | grep -v 'workflow-finalize' > "$D/assets/scripts/hold-dispatch.sh.new"
mv "$D/assets/scripts/hold-dispatch.sh.new" "$D/assets/scripts/hold-dispatch.sh"
chmod +x "$D/assets/scripts/hold-dispatch.sh"
breaks "(NOFINAL) finalize exemption dropped from the code" "$D" "workflow-finalize"

D=$(fixture closepath)
# shellcheck disable=SC2016  # a literal close path written INTO the fixture — expanding it here would defeat the case
printf '\ngc bd update "$BEAD" --status=closed\n' >> "$D/assets/scripts/hold-dispatch.sh"
breaks "(CLOSEPATH) a close path appears in the writer" "$D" "close path"

D=$(fixture closecomment)
printf '\n# never write --status=closed here, and never run bd close\n' >> "$D/assets/scripts/hold-dispatch.sh"
run "$D"
[ "$RC" = "0" ] && ok "(COMMENT) a close path QUOTED in a comment is not flagged" \
  || bad "(COMMENT) comments must not trip the close-path guard: $OUT"

D=$(fixture notests); rm -f "$D/assets/scripts/hold-dispatch.test.sh"
breaks "(NOTESTS) the cited regression is missing" "$D" "missing tests"

# --- the instruction half -----------------------------------------------------
D=$(fixture nofrag); rm -f "$D/template-fragments/polecat-close-step-chain.template.md"
breaks "(NOFRAG) fragment absent" "$D" "missing fragment"

D=$(fixture uncalled)
sed -i 's/hold-dispatch\.sh//g' "$D/template-fragments/polecat-close-step-chain.template.md"
breaks "(UNCALLED) the prompt stops naming the writer" "$D" "does not name hold-dispatch.sh"

D=$(fixture nostepsonly)
sed -i 's/steps-only//g' "$D/template-fragments/polecat-close-step-chain.template.md"
breaks "(NOSTEPSONLY) the duplicate-dispatch case loses its flag" "$D" "steps-only"

D=$(fixture mayclose)
sed -i 's/never closed/xx/g; s/closes nothing/xx/g; s/not run the close loop/xx/g' \
  "$D/template-fragments/polecat-close-step-chain.template.md"
breaks "(MAYCLOSE) the prompt stops saying a held run closes nothing" "$D" "closes NO step"

# --- the fragment must actually reach a prompt --------------------------------
D=$(fixture uninjected)
sed -i 's/"polecat-close-step-chain"/"something-else"/g' "$D/pack.toml"
breaks "(UNINJECTED) fragment not injected into the polecat" "$D" "does not inject"

D=$(fixture nopack); rm -f "$D/pack.toml"
breaks "(NOPACK) pack.toml unreadable" "$D" "missing pack.toml"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
