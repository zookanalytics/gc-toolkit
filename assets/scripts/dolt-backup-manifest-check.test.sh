#!/usr/bin/env bash
# Hermetic test for the deacon patrol's backup-restorability check (tk-hef7t).
#
# The bug this guards: the dolt-health step used to key its backup verdict off
# `backups.dolt_stale` from `gc dolt health --json`. That field renders ABSENT
# backup data as
#     "backups": {"dolt_freshness": "", "dolt_age_sec": 0, "dolt_stale": false}
# so a TOTAL backup failure is indistinguishable from a fresh backup and the
# threshold row could only ever fire on a PARTIAL one. Two full patrol rotations
# logged "Dolt health: OK" through a real outage in which the lx ledger (HQ /
# mail / sessions) had no restorable backup for ~40 h.
#
# The fix verifies the backup on disk instead: Dolt writes chunk `.darc` files
# first and commits the `manifest` LAST, so a healthy database's newest file IS
# its manifest. A `.darc` newer than the manifest means the run uploaded data
# but never committed it — not restorable past the manifest, however new the
# chunks look. Directory mtime and directory size both lie here.
#
# This test EXECUTES the real snippet extracted verbatim from the shipped
# formula (between the `backup-manifest-check` markers) against synthetic
# backup dirs, so the tested rule cannot drift from the shipped instruction.
# No live city, Dolt, network, or backups.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-deacon-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# --- Extract the shipped snippet -------------------------------------------
# The formula description is a TOML *basic* multi-line string, so backslashes
# are escaped as `\\`. Un-escape them to recover the literal shell text
# (`\\n` -> `\n` in find -printf, `\\` -> `\` line continuations).
sed -n '/# >>> backup-manifest-check/,/# <<< backup-manifest-check/p' "$TOML" \
    | sed 's/\\\\/\\/g' > "$TMP/check.sh"

if [ ! -s "$TMP/check.sh" ]; then
    echo "FAIL - could not extract backup-manifest-check snippet from $TOML"
    echo "       (markers missing — did a reconciliation drop them?)"
    exit 1
fi
ok "extracted backup-manifest-check snippet from the shipped formula"

bash -n "$TMP/check.sh" || { echo "FAIL - extracted snippet is not valid bash"; exit 1; }
ok "extracted snippet parses as bash"

# The snippet must not have regressed to the dolt_stale key it replaced.
if grep -q 'dolt_stale' "$TMP/check.sh"; then
    bad "snippet keys off dolt_stale (the false-clean field it exists to replace)"
else
    ok "snippet does not key off dolt_stale"
fi

# --- Fixtures ---------------------------------------------------------------
# Build synthetic backup dirs with controlled mtimes. `age <h>` -> epoch stamp.
BACKUP_ROOT="$TMP/.dolt-backup"
age() { date -d "@$(( $(date +%s) - $1 * 3600 ))" '+%Y%m%d%H%M.%S'; }
mkdb() { mkdir -p "$BACKUP_ROOT/$1"; }
stamp() { touch -t "$(age "$2")" "$BACKUP_ROOT/$1"; }

# healthy: manifest committed last, 1 h ago
mkdb healthy
: > "$BACKUP_ROOT/healthy/aaaa.darc";  stamp healthy/aaaa.darc 2
: > "$BACKUP_ROOT/healthy/manifest";   stamp healthy/manifest 1

# uncommitted: chunks newer than the manifest — the lx outage shape
mkdb uncommitted
: > "$BACKUP_ROOT/uncommitted/manifest";  stamp uncommitted/manifest 40
: > "$BACKUP_ROOT/uncommitted/bbbb.darc"; stamp uncommitted/bbbb.darc 1

# uncommitted-fresh: the pure trap arm, and the one every other signal misses.
# The run happened 1 h ago and uploaded chunks, so directory mtime, directory
# size, and "when did the dog last run" all look healthy — but the manifest was
# never committed, so the restorable point is still 5 h back. Only the
# newest-file-is-not-the-manifest rule catches this; the 12 h staleness arm does
# NOT fire here (manifest is 5 h old), so this case isolates the trap.
mkdb uncommitted_fresh
: > "$BACKUP_ROOT/uncommitted_fresh/manifest";  stamp uncommitted_fresh/manifest 5
: > "$BACKUP_ROOT/uncommitted_fresh/ffff.darc"; stamp uncommitted_fresh/ffff.darc 1

# stale: manifest is newest (healthy shape) but far past the 12 h threshold
mkdb stale
: > "$BACKUP_ROOT/stale/cccc.darc"; stamp stale/cccc.darc 300
: > "$BACKUP_ROOT/stale/manifest";  stamp stale/manifest 281

# nomanifest: chunks only, never committed at all
mkdb nomanifest
: > "$BACKUP_ROOT/nomanifest/dddd.darc"; stamp nomanifest/dddd.darc 1

# slow: a large DB whose sync took a long time but DID commit. Manifest is
# newest and recent -> healthy. Guards the "do not flag on duration" rule.
mkdb slow
: > "$BACKUP_ROOT/slow/eeee.darc"; stamp slow/eeee.darc 3
: > "$BACKUP_ROOT/slow/manifest";  stamp slow/manifest 2

# --- Run the shipped snippet against the fixtures ---------------------------
OUT="$(GC_CITY_PATH="$TMP" GC_CITY="$TMP" bash "$TMP/check.sh" 2>&1)"

verdict() { printf '%s\n' "$OUT" | grep -E "^(OK|FLAG) $1:" | head -1; }
expect() {
    local db="$1" want="$2" line
    line="$(verdict "$db")"
    case "$line" in
        "$want "*) ok "$db -> $want ($line)" ;;
        "")        bad "$db -> no verdict emitted" ;;
        *)         bad "$db -> expected $want, got: $line" ;;
    esac
}

expect healthy           OK
expect uncommitted       FLAG   # .darc newer than manifest = not restorable
expect uncommitted_fresh FLAG   # trap arm alone: recent manifest, newer .darc
expect stale             FLAG   # manifest older than 12 h
expect nomanifest        FLAG   # nothing committed at all
expect slow              OK     # slow but committed is NOT a failure

# uncommitted_fresh must be caught by the trap arm, not the staleness arm — its
# manifest is only 5 h old, so a rule that checks age alone would pass it.
if verdict uncommitted_fresh | grep -q 'not the manifest'; then
    ok "uncommitted_fresh caught by the trap arm, not by staleness"
else
    bad "uncommitted_fresh not caught by the trap arm: $(verdict uncommitted_fresh)"
fi

# The uncommitted case must name the trap, not just say "old" — a reader has to
# understand the data is unrestorable, not merely behind.
if verdict uncommitted | grep -q 'not the manifest'; then
    ok "uncommitted verdict explains the .darc-newer-than-manifest trap"
else
    bad "uncommitted verdict does not explain the trap: $(verdict uncommitted)"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
