#!/usr/bin/env bash
# install-doctor-table.test.sh — docs/install.md's gc doctor table names
# exactly the checks the pack ships under doctor/.
#
# install.md §5 tells an operator what each `gc doctor` failure means, one row
# per check. The shipped set is a directory scan — every doctor/check-<name>/
# is a check, with no manifest — so the table is the one hand-kept copy of that
# set, and it drifts the moment a check is added or renamed without its row.
# Nothing else reads the table, so the drift is silent until an operator meets
# a failure the guide never names.
#
# This asserts the two sets are equal: a shipped check with no row, or a row
# naming no shipped check, fails. A row is read by its shape — a leading `| `
# then a backtick-quoted check name — so a `--check-*` FLAG mentioned in prose,
# which is not a check, is never counted as a row.
#
# Hermetic: reads the repo tree; no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
[ -d "$REPO/doctor" ] || REPO="$HERE/../.."
DOC="$REPO/docs/install.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

# The checks a doc names in table rows: a row opens `| ` then a backtick-quoted
# name. A `--check-*` flag in prose never opens a line that way.
table_checks() { grep -oE '^\| `check-[a-z0-9-]+`' "$1" | sed -E 's/^\| `//; s/`$//' | LC_ALL=C sort -u; }
# The checks the pack ships: one directory per check, no manifest.
shipped_checks() {
    find "$1/doctor" -maxdepth 1 -type d -name 'check-*' 2>/dev/null \
        | while IFS= read -r d; do basename "$d"; done | LC_ALL=C sort -u
}

echo "── 1. the table and the tree are both readable ──"
TABLE="$(table_checks "$DOC")"
SHIPPED="$(shipped_checks "$REPO")"
if [ -n "$TABLE" ]; then ok "install.md names checks in table rows"
else bad "install.md names checks in table rows" "no '| \`check-...\`' row found — did the table move or change shape?"; fi
if [ -n "$SHIPPED" ]; then ok "doctor/ ships check-* directories"
else bad "doctor/ ships check-* directories" "no doctor/check-* dir under $REPO"; fi

echo "── 2. every shipped check has a table row ──"
MISSING="$(comm -13 <(printf '%s\n' "$TABLE") <(printf '%s\n' "$SHIPPED"))"
if [ -z "$MISSING" ]; then ok "no shipped check is missing from the table"
else bad "no shipped check is missing from the table" "add a row for: $(printf '%s ' $MISSING)"; fi

echo "── 3. every table row names a shipped check ──"
STALE="$(comm -23 <(printf '%s\n' "$TABLE") <(printf '%s\n' "$SHIPPED"))"
if [ -z "$STALE" ]; then ok "no table row names a check the pack no longer ships"
else bad "no table row names a check the pack no longer ships" "remove or rename the row for: $(printf '%s ' $STALE)"; fi

echo "── 4. the comparison discriminates (synthetic) ──"
# §2/§3 passing must mean the sets agree, not that the detector never fires.
# A fixture with one extra shipped check and one stale row must surface exactly
# those, and a `--check-*` flag in prose must stay out of the row set.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-install-table-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/doctor/check-alpha" "$TMP/doctor/check-beta" "$TMP/docs"
cat > "$TMP/docs/install.md" <<'MD'
The pack's checks, and what a failure means:

| Check | Asserts | First-failure cause |
|---|---|---|
| `check-alpha` | something | a cause |
| `check-gamma` | something | a cause |

Render with `render-seed-audit.sh --check-merge` over the merge tree.
MD
F_TABLE="$(table_checks "$TMP/docs/install.md")"
F_SHIPPED="$(shipped_checks "$TMP")"
F_MISSING="$(comm -13 <(printf '%s\n' "$F_TABLE") <(printf '%s\n' "$F_SHIPPED") | tr '\n' ' ')"
F_STALE="$(comm -23 <(printf '%s\n' "$F_TABLE") <(printf '%s\n' "$F_SHIPPED") | tr '\n' ' ')"
if [ "$F_MISSING" = "check-beta " ]; then ok "a shipped check with no row is reported missing"
else bad "a shipped check with no row is reported missing" "got '$F_MISSING'"; fi
if [ "$F_STALE" = "check-gamma " ]; then ok "a row naming no shipped check is reported stale"
else bad "a row naming no shipped check is reported stale" "got '$F_STALE'"; fi
case "$F_TABLE" in
    *check-merge*) bad "a --check-* flag in prose is not read as a row" "check-merge leaked into the table set" ;;
    *) ok "a --check-* flag in prose is not read as a row" ;;
esac

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
