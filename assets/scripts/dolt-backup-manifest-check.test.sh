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
# The scan is driven by the LIVE database list, not by the backup dirs that
# happen to exist: a database with no backup dir at all emits no verdict from a
# dir-walk, which is the same false-clean the fix exists to kill.
#
# This test EXECUTES the real snippet extracted verbatim from the shipped
# formula (between the `backup-manifest-check` markers) against synthetic
# backup dirs, and separately asserts over the shipped dolt-health step TEXT
# that the retired `dolt_stale` threshold row has not come back anywhere in the
# step — the snippet markers only cover the snippet.
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
# The formula description is a TOML *basic* multi-line string, so any literal
# backslash is escaped as `\\`. Un-escape to recover the literal shell text.
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

# --- Assert over the SHIPPED dolt-health step, not just the snippet ---------
# The snippet markers fence a code block; the retired threshold row lived in the
# step's prose table OUTSIDE them. A test that only reads the snippet would
# happily pass while `| backups.dolt_stale == true | >30 min | ... |` was
# restored one screen above it — exactly the drift a reconciliation against the
# upstream base would reintroduce.
STEP="$(awk '/^id = "dolt-health"$/ {f=1} f && /^\[\[steps\]\]$/ {exit} f {print}' "$TOML")"
if [ -z "$STEP" ]; then
    echo "FAIL - could not extract the dolt-health step from $TOML"
    exit 1
fi
ok "extracted the shipped dolt-health step"

# Threshold rows are `| Signal | Threshold | Meaning |`. Field 2 is the SIGNAL
# cell — the thing the verdict is keyed off. dolt_stale must never appear
# there. It may appear in the Meaning cell and in prose, which is how the step
# explains why the field is insufficient; banning every mention would delete
# the explanation and invite the next reader to re-derive the trap.
BAD_ROWS="$(printf '%s\n' "$STEP" | awk -F'|' '/^[[:space:]]*\|/ && $2 ~ /dolt_stale/ {print}')"
if [ -n "$BAD_ROWS" ]; then
    bad "dolt-health threshold row is keyed off dolt_stale: $BAD_ROWS"
else
    ok "no dolt-health threshold row is keyed off dolt_stale"
fi

# Belt and braces: the exact retired row shape, anywhere in the step.
# shellcheck disable=SC2016  # backticks are regex literals (the markdown row
# quotes the field as `backups.dolt_stale`), not command substitution.
if printf '%s\n' "$STEP" | grep -qE '`?backups\.dolt_stale`? *== *true'; then
    bad "the retired 'backups.dolt_stale == true' threshold row is back in the step"
else
    ok "the retired 'backups.dolt_stale == true' row is absent from the step"
fi

# ...but the explanation must survive, or the trap gets re-derived by hand.
if printf '%s\n' "$STEP" | grep -q 'dolt_stale'; then
    ok "step still explains why dolt_stale is insufficient"
else
    bad "step no longer mentions dolt_stale at all — the explanation was lost"
fi

# The scan must be driven by the live database list (finding: a database with
# no backup dir is invisible to a dir-walk).
if grep -q 'EXPECTED_DBS' "$TMP/check.sh"; then
    ok "snippet drives the scan from an expected-database list"
else
    bad "snippet does not drive the scan from an expected-database list"
fi

# --- Fixtures ---------------------------------------------------------------
# Build synthetic backup dirs with controlled mtimes. `age <h>` -> touch stamp.
BACKUP_ROOT="$TMP/.dolt-backup"
# Portable epoch -> touch stamp: GNU (-d @epoch), BSD/macOS (-r epoch).
age() {
    local e=$(( $(date +%s) - $1 * 3600 ))
    date -d "@$e" '+%Y%m%d%H%M.%S' 2>/dev/null || date -r "$e" '+%Y%m%d%H%M.%S'
}
mkdb() { mkdir -p "$BACKUP_ROOT/$1"; }
# Stamp from an explicit epoch. `age` re-reads the clock per call and only
# takes whole hours, so it can express neither "these two files share a
# second" nor "this chunk is one second newer" — both of which the tie
# fixtures below need to pin exactly.
stamp_epoch() {
    local s
    s="$(date -d "@$2" '+%Y%m%d%H%M.%S' 2>/dev/null || date -r "$2" '+%Y%m%d%H%M.%S')"
    touch -t "$s" "$BACKUP_ROOT/$1"
}
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

# nomanifest: chunks only, never committed at all, and not being written now
mkdb nomanifest
: > "$BACKUP_ROOT/nomanifest/dddd.darc"; stamp nomanifest/dddd.darc 1

# emptydir: a backup directory with nothing in it at all
mkdb emptydir

# slow: a large DB whose sync took a long time but DID commit. Manifest is
# newest and recent -> healthy. Guards the "do not flag on duration" rule.
mkdb slow
: > "$BACKUP_ROOT/slow/eeee.darc"; stamp slow/eeee.darc 3
: > "$BACKUP_ROOT/slow/manifest";  stamp slow/manifest 2

# inflight: a sync in progress RIGHT NOW. Dolt commits the manifest last, so
# mid-run the newest file is legitimately a chunk. Flagging this would fire on
# every healthy run that happens to overlap a patrol rotation.
mkdb inflight
: > "$BACKUP_ROOT/inflight/manifest"; stamp inflight/manifest 1
: > "$BACKUP_ROOT/inflight/gggg.darc"          # written now — no stamp

# inflight_stale: a chunk written RIGHT NOW, but the manifest is 40 h behind.
# The grace window must NOT swallow this: no healthy in-flight run explains a
# manifest two cadences old. This is the live lx shape — fresh chunks every
# rotation, nothing ever committed — and it is the case the grace path could
# most easily have re-hidden.
mkdb inflight_stale
: > "$BACKUP_ROOT/inflight_stale/manifest"; stamp inflight_stale/manifest 40
: > "$BACKUP_ROOT/inflight_stale/hhhh.darc"    # written now — no stamp

# nomanifest_inflight: first-ever sync in progress, no manifest committed yet.
mkdb nomanifest_inflight
: > "$BACKUP_ROOT/nomanifest_inflight/iiii.darc"   # written now — no stamp

# tie_chunk_first / tie_manifest_first: the manifest and the newest chunk share
# an mtime SECOND (tk-40mlc). `stat -c %Y` / `-f %m` return whole seconds, so
# sub-second ordering is invisible — the real lx case had the manifest 33 ms
# NEWER than the last chunk and the check still saw a tie. Dolt commits the
# manifest LAST, so a same-second tie means the commit landed in the same
# second as the final chunk: a FAST, healthy sync. Both must read OK.
#
# Two fixtures, differing in creation order and chunk name, because the
# pre-fix loop broke a tie by `find` traversal order — whichever file the
# directory happened to yield first won. Traversal order is not portably
# controllable (creation order on tmpfs, name-hash on ext4), so one fixture
# could pass buggy code by luck; two independent draws make that unlikely.
# Under the tie rule both are deterministic regardless of traversal order.
TIE_EPOCH=$(( $(date +%s) - 2 * 3600 ))

mkdb tie_chunk_first
: > "$BACKUP_ROOT/tie_chunk_first/kkkk.darc"; stamp_epoch tie_chunk_first/kkkk.darc "$TIE_EPOCH"
: > "$BACKUP_ROOT/tie_chunk_first/manifest";  stamp_epoch tie_chunk_first/manifest  "$TIE_EPOCH"

mkdb tie_manifest_first
: > "$BACKUP_ROOT/tie_manifest_first/manifest";  stamp_epoch tie_manifest_first/manifest  "$TIE_EPOCH"
: > "$BACKUP_ROOT/tie_manifest_first/llll.darc"; stamp_epoch tie_manifest_first/llll.darc "$TIE_EPOCH"

# tie_uncommitted: the tightest form of the rule the tie must NOT weaken — a
# chunk STRICTLY newer than the manifest, by a single second. A fix that let
# the manifest win unconditionally, or that compared with any tolerance, would
# read this as healthy. It is the torn-backup signature (tk-hef7t) and must
# still FLAG. The manifest is 2 h old, well inside the 12 h staleness arm, so
# only the trap arm can catch it.
mkdb tie_uncommitted
: > "$BACKUP_ROOT/tie_uncommitted/manifest";  stamp_epoch tie_uncommitted/manifest  "$TIE_EPOCH"
: > "$BACKUP_ROOT/tie_uncommitted/mmmm.darc"; stamp_epoch tie_uncommitted/mmmm.darc "$(( TIE_EPOCH + 1 ))"

# retired: a backup dir with NO live database. Advisory only — a dropped or
# renamed db must not produce a verdict that reads as a live-backup failure.
mkdb retired
: > "$BACKUP_ROOT/retired/jjjj.darc"; stamp retired/jjjj.darc 400
: > "$BACKUP_ROOT/retired/manifest";  stamp retired/manifest 399

# missing_backup_dir is deliberately NOT created: a live database with no
# backup directory at all. This is the worst case and the one a dir-walk can
# never see — it must still produce a verdict.
DBS="healthy uncommitted uncommitted_fresh stale nomanifest emptydir slow
inflight inflight_stale nomanifest_inflight missing_backup_dir
tie_chunk_first tie_manifest_first tie_uncommitted"

# --- Run the shipped snippet against the fixtures ---------------------------
OUT="$(GC_CITY_PATH="$TMP" GC_CITY="$TMP" EXPECTED_DBS="$DBS" bash "$TMP/check.sh" 2>&1)"

# `|| true` is load-bearing: under `set -o pipefail` a no-match grep fails the
# pipeline, and `set -e` would abort the run at the first missing verdict —
# turning the very case this suite exists to detect (a database that produces
# NO verdict) into a silent early exit instead of a reported failure.
verdict() { printf '%s\n' "$OUT" | grep -E "^(OK|FLAG|RECHECK|INFO) $1:" | head -1 || true; }
expect() {
    local db="$1" want="$2" line
    line="$(verdict "$db")"
    case "$line" in
        "$want "*) ok "$db -> $want ($line)" ;;
        "")        bad "$db -> no verdict emitted" ;;
        *)         bad "$db -> expected $want, got: $line" ;;
    esac
}

expect healthy             OK
expect uncommitted         FLAG     # .darc newer than manifest = not restorable
expect uncommitted_fresh   FLAG     # trap arm alone: recent manifest, newer .darc
expect stale               FLAG     # manifest older than 12 h
expect nomanifest          FLAG     # nothing committed at all
expect emptydir            FLAG     # backup dir exists but is empty
expect slow                OK       # slow but committed is NOT a failure
expect inflight            RECHECK  # sync in progress — indeterminate, not failed
expect inflight_stale      FLAG     # in-flight writes cannot excuse a 40 h manifest
expect nomanifest_inflight RECHECK  # first commit may still be in flight
expect missing_backup_dir  FLAG     # live database with NO backup dir at all
expect retired             INFO     # backup dir with no live database: advisory
expect tie_chunk_first     OK       # manifest/chunk same second = fast healthy sync
expect tie_manifest_first  OK       # ...and independent of traversal order
expect tie_uncommitted     FLAG     # chunk STRICTLY newer, by 1 s, is still torn

# Every expected database must be covered — the false-clean this whole check
# exists to kill is a database that simply produces no verdict.
UNCOVERED=""
for db in $DBS; do
    [ -n "$(verdict "$db")" ] || UNCOVERED="$UNCOVERED $db"
done
if [ -n "$UNCOVERED" ]; then
    bad "expected databases produced no verdict:$UNCOVERED"
else
    ok "every expected database produced a verdict"
fi

# The advisory arm must not masquerade as a failure verdict.
if verdict retired | grep -q '^INFO'; then
    ok "extra backup dir is advisory, not a live-backup failure"
else
    bad "extra backup dir did not come back as INFO: $(verdict retired)"
fi

# uncommitted_fresh must be caught by the trap arm, not the staleness arm — its
# manifest is only 5 h old, so a rule that checks age alone would pass it.
if verdict uncommitted_fresh | grep -q 'not the manifest'; then
    ok "uncommitted_fresh caught by the trap arm, not by staleness"
else
    bad "uncommitted_fresh not caught by the trap arm: $(verdict uncommitted_fresh)"
fi

# The tie rule must not swallow the trap it sits next to: one second of strict
# newness still means the run uploaded data it never committed. If this comes
# back OK, the fix degenerated into "the manifest always wins".
if verdict tie_uncommitted | grep -q 'not the manifest'; then
    ok "a chunk one second newer than the manifest still FLAGs as uncommitted"
else
    bad "one-second-newer chunk not caught by the trap arm: $(verdict tie_uncommitted)"
fi

# The uncommitted case must name the trap, not just say "old" — a reader has to
# understand the data is unrestorable, not merely behind.
if verdict uncommitted | grep -q 'not the manifest'; then
    ok "uncommitted verdict explains the .darc-newer-than-manifest trap"
else
    bad "uncommitted verdict does not explain the trap: $(verdict uncommitted)"
fi

# The missing-dir verdict must name the database and say what is wrong, or the
# Step 3 nudge/escalation template has nothing concrete to carry.
if verdict missing_backup_dir | grep -q 'no backup directory'; then
    ok "missing-dir verdict names the database and the cause"
else
    bad "missing-dir verdict is not actionable: $(verdict missing_backup_dir)"
fi

# No verdict may ever name a literal '*' — that is an unmatched glob leaking
# through as a database name, and it gives the deacon nothing to act on.
if printf '%s\n' "$OUT" | grep -qE '^(OK|FLAG|RECHECK|INFO) \*'; then
    bad "a verdict named the unmatched glob '*': $(printf '%s\n' "$OUT" | grep -E '^\w+ \*')"
else
    ok "no verdict names the unmatched glob '*'"
fi

# --- Root-level terminal findings -------------------------------------------
# A missing or empty backup root means NO database has a restorable backup. It
# must be an explicit, named finding — not an unmatched glob falling through the
# per-database loop, and not a bare warning the deacon can log past.
root_case() {
    local label="$1" root="$2"
    local out
    out="$(GC_CITY_PATH="$root" GC_CITY="$root" EXPECTED_DBS="$DBS" bash "$TMP/check.sh" 2>&1)"
    if printf '%s\n' "$out" | grep -q '^FLAG-ROOT:'; then
        ok "$label -> FLAG-ROOT ($(printf '%s\n' "$out" | grep '^FLAG-ROOT:' | head -1))"
    else
        bad "$label -> no FLAG-ROOT finding; got: $out"
    fi
    # It has to name the databases, or the escalation template is empty.
    if printf '%s\n' "$out" | grep -q 'healthy'; then
        ok "$label finding names the affected databases"
    else
        bad "$label finding does not name the affected databases: $out"
    fi
    if printf '%s\n' "$out" | grep -qE '^(OK|FLAG|RECHECK|INFO) \*'; then
        bad "$label leaked an unmatched glob as a database name: $out"
    else
        ok "$label does not leak an unmatched glob"
    fi
}

MISSING_ROOT="$TMP/missing"      # never created -> no .dolt-backup under it
root_case "missing backup root" "$MISSING_ROOT"

EMPTY_ROOT="$TMP/empty"
mkdir -p "$EMPTY_ROOT/.dolt-backup"
root_case "empty backup root" "$EMPTY_ROOT"

# --- No database list -------------------------------------------------------
# If the health report yields no databases, nothing is verified. That is a
# terminal finding too — an empty loop must never read as "all clean". Stub
# `gc` so the snippet's default EXPECTED_DBS resolution runs hermetically; this
# also exercises the un-overridden default path.
if command -v jq >/dev/null 2>&1; then
    mkdir -p "$TMP/bin"
    printf '%s\n' '#!/bin/sh' 'echo "{\"databases\":[]}"' > "$TMP/bin/gc"
    chmod +x "$TMP/bin/gc"
    NODB="$(PATH="$TMP/bin:$PATH" GC_CITY_PATH="$TMP" GC_CITY="$TMP" bash "$TMP/check.sh" 2>&1)"
    if printf '%s\n' "$NODB" | grep -q '^FLAG-ROOT:'; then
        ok "empty database list -> FLAG-ROOT ($(printf '%s\n' "$NODB" | head -1))"
    else
        bad "empty database list did not produce FLAG-ROOT; got: $NODB"
    fi
else
    echo "skip - empty-database-list case (jq not installed)"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
