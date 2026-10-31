#!/usr/bin/env bash
# Hermetic test for the deacon patrol's backup-restorability check.
#
# The bug this guards: the dolt-health step used to key its backup verdict off
# `backups.dolt_stale` from `gc dolt health --json`. That field renders ABSENT
# backup data as
#     "backups": {"dolt_freshness": "", "dolt_age_sec": 0, "dolt_stale": false}
# so a TOTAL backup failure is indistinguishable from a fresh backup and the
# threshold row could only ever fire on a PARTIAL one. Two full patrol rotations
# logged "Dolt health: OK" through a real outage in which the city's own ledger
# (HQ / mail / sessions) had no restorable backup for ~40 h.
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
#
# One case runs the snippet with `find` shimmed on PATH to force directory
# traversal order (see "Deterministic forced-order tie"), because the mtime-tie
# rule the snippet encodes is precisely a rule about not depending on that
# order — and a fixture that merely hopes for the unlucky order proves nothing.
# No live city, Dolt, network, or backups.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-deacon-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-dolt-backup-manifest-check-test.XXXXXX")"
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
#
# Both checks below feed $STEP to grep by HERE-STRING, not by `printf | grep`.
# $STEP is ~16 KB and `grep -q` exits the instant it matches, so the writer can
# still be mid-write when the read end closes: it takes SIGPIPE and the
# pipeline returns 141. Under this script's `set -o pipefail` that reads as
# "assertion failed" — measured at ~1% per call, which is a passing suite that
# randomly reports a lost dolt_stale explanation. A here-string is fully
# written before grep starts, so there is no early-close race at all. (The
# BAD_ROWS scan above is safe as written: awk always drains its input.)
# shellcheck disable=SC2016  # backticks are regex literals (the markdown row
# quotes the field as `backups.dolt_stale`), not command substitution.
if grep -qE '`?backups\.dolt_stale`? *== *true' <<< "$STEP"; then
    bad "the retired 'backups.dolt_stale == true' threshold row is back in the step"
else
    ok "the retired 'backups.dolt_stale == true' row is absent from the step"
fi

# ...but the explanation must survive, or the trap gets re-derived by hand.
if grep -q 'dolt_stale' <<< "$STEP"; then
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

# --- Step 3 alert templates must be FLAG-class-neutral ----------------------
# Step 2a FLAGs for five distinct reasons — no backup directory, no manifest, a
# strictly newer file, a stale manifest, a directory that could not be read —
# and only ONE of them has a "newer file" to name. A Step 3 template that
# demands that field renders an empty or invented value for the other four, so
# the operator gets an alert about a file that does not exist. Each Step 2a
# verdict is already a complete one-line reason: the templates carry it
# verbatim, and these assertions keep the class-specific field from creeping
# back. Asserted over the shipped step TEXT, because the templates are prose —
# no snippet marker fences them.
ALERT_LINES="$(grep -E 'FLAG line, verbatim' <<< "$STEP" || true)"
if [ -z "$ALERT_LINES" ]; then
    bad "could not find the Step 3 backup alert template in the dolt-health step"
else
    ok "found the Step 3 backup alert template (patrol-finding.sh, verdict verbatim)"

    if grep -qE 'newer file <' <<< "$ALERT_LINES"; then
        bad "Step 3 backup alert demands a 'newer file' most FLAG classes lack: $ALERT_LINES"
    else
        ok "Step 3 backup alerts demand no class-specific 'newer file' field"
    fi
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
# Portable epoch -> `touch -t` stamp. Split out of stamp_epoch because the
# forced-order fixture further down lives under its own backup root and has to
# stamp by absolute path.
epoch_stamp() { date -d "@$1" '+%Y%m%d%H%M.%S' 2>/dev/null || date -r "$1" '+%Y%m%d%H%M.%S'; }
# Stamp from an explicit epoch. `age` re-reads the clock per call and only
# takes whole hours, so it can express neither "these two files share a
# second" nor "this chunk is one second newer" — both of which the tie
# fixtures below need to pin exactly.
stamp_epoch() {
    local s
    s="$(epoch_stamp "$2")"
    touch -t "$s" "$BACKUP_ROOT/$1"
}
stamp() { touch -t "$(age "$2")" "$BACKUP_ROOT/$1"; }

# healthy: manifest committed last, 1 h ago
mkdb healthy
: > "$BACKUP_ROOT/healthy/aaaa.darc";  stamp healthy/aaaa.darc 2
: > "$BACKUP_ROOT/healthy/manifest";   stamp healthy/manifest 1

# uncommitted: chunks newer than the manifest — the city ledger's outage shape
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
# manifest two cadences old. This is the city ledger's live shape — fresh
# chunks every rotation, nothing ever committed — and it is the case the grace
# path could most easily have re-hidden.
mkdb inflight_stale
: > "$BACKUP_ROOT/inflight_stale/manifest"; stamp inflight_stale/manifest 40
: > "$BACKUP_ROOT/inflight_stale/hhhh.darc"    # written now — no stamp

# nomanifest_inflight: first-ever sync in progress, no manifest committed yet.
mkdb nomanifest_inflight
: > "$BACKUP_ROOT/nomanifest_inflight/iiii.darc"   # written now — no stamp

# tie_chunk_first / tie_manifest_first: the manifest and the newest chunk share
# an mtime SECOND. `stat -c %Y` / `-f %m` return whole seconds, so
# sub-second ordering is invisible — the city ledger's real case had the
# manifest 33 ms NEWER than the last chunk and the check still saw a tie. Dolt
# commits the manifest LAST, so a same-second tie means the commit landed in
# the same second as the final chunk: a FAST, healthy sync. Both must read OK.
#
# Two fixtures, differing in creation order and chunk name, because the
# pre-fix loop broke a tie by `find` traversal order — whichever file the
# directory happened to yield first won. These two are NATURAL-order draws:
# they take whatever order the host filesystem hands back (creation order on
# tmpfs, name-hash on ext4), so on an unlucky host both could yield `manifest`
# first and let pre-fix code pass. They are coverage, not proof — the proof is
# the forced-order case below ("Deterministic forced-order tie"), which shims
# `find` to pin the order and so fails against pre-fix code on every host.
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
# read this as healthy. It is the torn-backup signature and must
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
if grep -q '^INFO' < <(verdict retired); then
    ok "extra backup dir is advisory, not a live-backup failure"
else
    bad "extra backup dir did not come back as INFO: $(verdict retired)"
fi

# uncommitted_fresh must be caught by the trap arm, not the staleness arm — its
# manifest is only 5 h old, so a rule that checks age alone would pass it.
if grep -q 'not the manifest' < <(verdict uncommitted_fresh); then
    ok "uncommitted_fresh caught by the trap arm, not by staleness"
else
    bad "uncommitted_fresh not caught by the trap arm: $(verdict uncommitted_fresh)"
fi

# The tie rule must not swallow the trap it sits next to: one second of strict
# newness still means the run uploaded data it never committed. If this comes
# back OK, the fix degenerated into "the manifest always wins".
if grep -q 'not the manifest' < <(verdict tie_uncommitted); then
    ok "a chunk one second newer than the manifest still FLAGs as uncommitted"
else
    bad "one-second-newer chunk not caught by the trap arm: $(verdict tie_uncommitted)"
fi

# The uncommitted case must name the trap, not just say "old" — a reader has to
# understand the data is unrestorable, not merely behind.
if grep -q 'not the manifest' < <(verdict uncommitted); then
    ok "uncommitted verdict explains the .darc-newer-than-manifest trap"
else
    bad "uncommitted verdict does not explain the trap: $(verdict uncommitted)"
fi

# The missing-dir verdict must name the database and say what is wrong, or the
# Step 3 nudge/escalation template has nothing concrete to carry.
if grep -q 'no backup directory' < <(verdict missing_backup_dir); then
    ok "missing-dir verdict names the database and the cause"
else
    bad "missing-dir verdict is not actionable: $(verdict missing_backup_dir)"
fi

# Generalised: Step 3's templates quote the Step 2a line VERBATIM rather than
# rebuilding it from class-specific fields, so every finding line has to be
# self-describing. A bare `FLAG <db>:` would render an alert that names a
# database and no reason at all — the failure mode the reason-neutral templates
# exist to prevent, seen from the producing end.
BARE="$(printf '%s\n' "$OUT" | grep -E '^(FLAG|RECHECK|FLAG-ROOT)' \
    | grep -vE '^[A-Z-]+ ?[^:]*: .+' || true)"
if [ -n "$BARE" ]; then
    bad "finding lines carry no reason for Step 3 to quote: $BARE"
else
    ok "every finding line carries a reason Step 3 can quote verbatim"
fi

# No verdict may ever name a literal '*' — that is an unmatched glob leaking
# through as a database name, and it gives the deacon nothing to act on.
if grep -qE '^(OK|FLAG|RECHECK|INFO) \*' <<< "$OUT"; then
    bad "a verdict named the unmatched glob '*': $(printf '%s\n' "$OUT" | grep -E '^\w+ \*')"
else
    ok "no verdict names the unmatched glob '*'"
fi

# --- Deterministic forced-order tie -----------------------------------------
# `tie_chunk_first` / `tie_manifest_first` are draws at a variable the test
# cannot set: `find` traversal order. Pin it instead. Shim `find` so that for
# one fixture it emits the tied chunk BEFORE the manifest — the exact order
# under which the pre-fix loop left `newest` pointing at a chunk and false-
# FLAGged a healthy backup — and delegate every other call to the real find.
# Under that forced order the shipped snippet must still read OK. That holds on
# every host, which is what makes this the case a revert of the tie fix cannot
# get past.
REAL_FIND="$(command -v find || true)"
[ -n "$REAL_FIND" ] || { echo "FAIL - no find(1) on PATH; cannot force traversal order"; exit 1; }

FORCED_ROOT="$TMP/forced"
FORCED_DB="$FORCED_ROOT/.dolt-backup/tie_forced"
FIRED="$FORCED_ROOT/find-shim-fired"
mkdir -p "$FORCED_DB" "$TMP/findbin"
: > "$FORCED_DB/manifest"
: > "$FORCED_DB/nnnn.darc"
touch -t "$(epoch_stamp "$TIE_EPOCH")" "$FORCED_DB/manifest" "$FORCED_DB/nnnn.darc"

# Paths are baked in at write time (unquoted heredoc, `\$` escaped where the
# shim's own positional parameters are meant), so the shim needs no environment
# — it only has to recognise the one directory whose order it forces.
cat > "$TMP/findbin/find" <<EOF
#!/usr/bin/env bash
# \$1 is the snippet's search root: 'find "\$db" -type f'.
if [ "\$1" = "$FORCED_DB" ]; then
    : > "$FIRED"
    printf '%s\n' "$FORCED_DB/nnnn.darc" "$FORCED_DB/manifest"
    exit 0
fi
exec "$REAL_FIND" "\$@"
EOF
chmod +x "$TMP/findbin/find"

FORCED_OUT="$(PATH="$TMP/findbin:$PATH" GC_CITY_PATH="$FORCED_ROOT" GC_CITY="$FORCED_ROOT" \
    EXPECTED_DBS="tie_forced" bash "$TMP/check.sh" 2>&1)"

# The shim must actually have run, or the case is vacuous: if the snippet
# stopped shelling out to `find`, or the PATH prefix were ignored, the fixture
# would silently fall back to natural order and become a coin flip again.
if [ -f "$FIRED" ]; then
    ok "forced-order find shim was exercised (tie order really was forced)"
else
    bad "forced-order find shim never fired — tie order was NOT forced; got: $FORCED_OUT"
fi

FORCED_VERDICT="$(printf '%s\n' "$FORCED_OUT" \
    | grep -E '^(OK|FLAG|RECHECK|INFO) tie_forced:' | head -1 || true)"
case "$FORCED_VERDICT" in
    "OK "*) ok "tie survives a forced chunk-before-manifest traversal ($FORCED_VERDICT)" ;;
    "")     bad "forced-order tie produced no verdict; got: $FORCED_OUT" ;;
    *)      bad "forced-order tie did not read OK: $FORCED_VERDICT" ;;
esac

# --- A failed or empty directory scan is never OK ---------------------------
# The manifest seed that makes a tie read OK also makes a FAILED scan read OK,
# unless the scan's exit status is checked: `done < <(find ...)` throws that
# status away, so a directory the patrol cannot enumerate leaves `newest` on the
# seeded manifest, and a fresh manifest walks straight to "OK: manifest is
# newest". That hides a strictly newer chunk behind a permissions or I/O error —
# the same false-clean class the whole check exists to kill, reintroduced by its
# own fix. Shim `find` to fail for two fixtures, and to succeed while listing
# nothing for a third, then pin all three verdicts. Against pre-fix code every
# one of them reads OK.
SCAN_ROOT="$TMP/scanfail"
SCAN_FIRED="$SCAN_ROOT/find-shim-calls"
mkdir -p "$SCAN_ROOT/.dolt-backup" "$TMP/failbin"
for d in scan_fresh scan_stale scan_empty; do
    mkdir -p "$SCAN_ROOT/.dolt-backup/$d"
    : > "$SCAN_ROOT/.dolt-backup/$d/manifest"
done
# The manifests are READABLE, and fresh everywhere except scan_stale. Freshness
# is precisely what used to carry a failed scan to OK, so it is the state under
# test; scan_stale pins the other half of the rule (already stale -> FLAG, not
# an indeterminate the patrol could sit on).
touch -t "$(epoch_stamp "$(( $(date +%s) - 3600 ))")"      "$SCAN_ROOT/.dolt-backup/scan_fresh/manifest"
touch -t "$(epoch_stamp "$(( $(date +%s) - 3600 ))")"      "$SCAN_ROOT/.dolt-backup/scan_empty/manifest"
touch -t "$(epoch_stamp "$(( $(date +%s) - 40 * 3600 ))")" "$SCAN_ROOT/.dolt-backup/scan_stale/manifest"

# Same shape as the forced-order shim: paths baked in at write time, `\$` kept
# literal for the shim's own parameters, everything else delegated to real find.
cat > "$TMP/failbin/find" <<EOF
#!/usr/bin/env bash
# \$1 is the snippet's search root: 'find "\$db" -type f'.
case "\$1" in
    */scan_empty)
        printf '%s\n' "\$1" >> "$SCAN_FIRED"
        exit 0 ;;                    # enumerated nothing, reported no error
    */scan_fresh|*/scan_stale)
        printf '%s\n' "\$1" >> "$SCAN_FIRED"
        echo "find: '\$1': Permission denied" >&2
        exit 1 ;;
esac
exec "$REAL_FIND" "\$@"
EOF
chmod +x "$TMP/failbin/find"

SCAN_OUT="$(PATH="$TMP/failbin:$PATH" GC_CITY_PATH="$SCAN_ROOT" GC_CITY="$SCAN_ROOT" \
    EXPECTED_DBS="scan_fresh scan_stale scan_empty" bash "$TMP/check.sh" 2>&1)"

scan_expect() {
    local db="$1" want="$2" line
    line="$(printf '%s\n' "$SCAN_OUT" | grep -E "^(OK|FLAG|RECHECK|INFO) $db:" | head -1 || true)"
    case "$line" in
        "$want "*) ok "$db -> $want ($line)" ;;
        "")        bad "$db -> no verdict emitted; got: $SCAN_OUT" ;;
        *)         bad "$db -> expected $want, got: $line" ;;
    esac
}

# Vacuity guard, as for the forced-order case: if the snippet stopped shelling
# out to `find`, or the PATH prefix were ignored, these fixtures would quietly
# enumerate for real and assert nothing.
for d in scan_fresh scan_stale scan_empty; do
    if grep -q "/$d\$" "$SCAN_FIRED" 2>/dev/null; then
        ok "scan shim was exercised for $d"
    else
        bad "scan shim never fired for $d — the scan was NOT forced; got: $SCAN_OUT"
    fi
done

scan_expect scan_fresh RECHECK  # unreadable dir + fresh manifest = unproven
scan_expect scan_stale FLAG     # unreadable dir + 40 h manifest = a finding now
scan_expect scan_empty RECHECK  # exit 0 but listed nothing, manifest readable

# The headline invariant, stated as itself: an unreadable backup directory must
# never produce a clean verdict, whatever the manifest looks like.
if grep -qE '^OK ' <<< "$SCAN_OUT"; then
    bad "an unenumerable backup directory read as OK: $(printf '%s\n' "$SCAN_OUT" | grep -E '^OK ')"
else
    ok "no unenumerable backup directory read as OK"
fi

# The verdict has to say the SCAN failed, not merely that something is wrong:
# Step 3 quotes this line verbatim, and "fix the directory read" is a different
# action from "re-run the backup dog".
if grep -q 'scan failed' < <(grep -E '^RECHECK scan_fresh:' <<< "$SCAN_OUT"); then
    ok "scan-failure verdict names the scan as the cause"
else
    bad "scan-failure verdict does not name the scan: $(printf '%s\n' "$SCAN_OUT" | grep -E '^RECHECK scan_fresh:' || true)"
fi
if grep -q 'Permission denied' < <(grep -E '^RECHECK scan_fresh:' <<< "$SCAN_OUT"); then
    ok "scan-failure verdict carries the underlying find error"
else
    bad "scan-failure verdict drops the find error: $(printf '%s\n' "$SCAN_OUT" | grep -E '^RECHECK scan_fresh:' || true)"
fi

# --- ...and the scan-failure arm must survive a strict shell ----------------
# Every assertion above runs the snippet under a plain `bash`. The arm they
# pin is reached only if `scan_rc` is actually assigned, and reading it from
# `$?` after a bare `scan_out=$(find ...)` does NOT survive `set -e`: the
# failing substitution is itself the assignment's exit status, so errexit
# aborts the shell before the next statement runs. The entire
# unreadable-directory arm then vanishes — no RECHECK, no FLAG, no output at
# all — and the false-clean it exists to kill comes back as a silent abort.
# This snippet is documentation as much as code and gets pasted into strict
# shells; the step already guards its OTHER expected-failure call with
# `|| true` for exactly this reason. So re-run the same shimmed fixtures under
# `bash -euo pipefail` (a superset of `-e -o pipefail`) and demand identical
# verdicts.
#
# These assertions are self-guarding against a dead PATH shim: an unshimmed
# run enumerates for real and reads OK, which is not what they accept.
#
# The capture uses the very `|| rc=$?` shape the snippet itself must use —
# this script runs under `set -e` too, so reading the status any other way
# would abort the suite on a regression instead of reporting it.
STRICT_RC=0
STRICT_OUT="$(PATH="$TMP/failbin:$PATH" GC_CITY_PATH="$SCAN_ROOT" GC_CITY="$SCAN_ROOT" \
    EXPECTED_DBS="scan_fresh scan_stale scan_empty" \
    bash -euo pipefail "$TMP/check.sh" 2>&1)" || STRICT_RC=$?

if [ "$STRICT_RC" -eq 0 ]; then
    ok "snippet exits clean under 'bash -euo pipefail' with a failing find"
else
    bad "snippet aborted under 'bash -euo pipefail' (rc=$STRICT_RC); got: $STRICT_OUT"
fi

strict_expect() {
    local db="$1" want="$2" line
    line="$(grep -E "^(OK|FLAG|RECHECK|INFO) $db:" <<< "$STRICT_OUT" | head -1 || true)"
    case "$line" in
        "$want "*) ok "strict shell: $db -> $want ($line)" ;;
        "")        bad "strict shell: $db emitted no verdict; got: $STRICT_OUT" ;;
        *)         bad "strict shell: $db expected $want, got: $line" ;;
    esac
}

strict_expect scan_fresh RECHECK
strict_expect scan_stale FLAG
strict_expect scan_empty RECHECK

# --- A failed scan BUFFER is never OK ---------------------------------------
# The scan arm above fails `find` itself. This arm fails the step BETWEEN a
# successful find and the newest-file loop: the buffering of the file list.
# The loop used to read it with `done <<< "$scan_out"`, and bash backs a
# here-string with a temp file it creates silently — so under disk pressure
# that redirect fails, the loop runs zero times, `newest` keeps its seeded
# manifest, and a fresh-manifest directory walks straight to "OK: manifest is
# newest" while a newer chunk sits unseen. The fix buffers the scan through a
# CHECKED mktemp, so this shims the mktemp COMMAND to fail only the scan
# buffer (never the $DB_LIST temp) and pins the verdicts. A here-string does
# not call the mktemp command, so against pre-fix code the shim is a no-op and
# every fixture below reads OK — which is exactly what these assertions reject.
REAL_MKTEMP="$(command -v mktemp || true)"
[ -n "$REAL_MKTEMP" ] || { echo "FAIL - no mktemp(1) on PATH; cannot force a buffer failure"; exit 1; }

BUF_ROOT="$TMP/bufferfail"
BUF_FIRED="$BUF_ROOT/mktemp-shim-calls"
mkdir -p "$BUF_ROOT/.dolt-backup" "$TMP/mktempbin"
for d in scanbuf_fresh scanbuf_stale; do
    mkdir -p "$BUF_ROOT/.dolt-backup/$d"
done
# scanbuf_fresh: a healthy shape — a chunk, then the manifest committed last
# and only 1 h old. A pre-fix `<<<` loop buffers this fine and reads it OK;
# with the buffer temp denied, the fix cannot see the directory at all, so it
# must refuse to certify it rather than trust the seeded manifest.
: > "$BUF_ROOT/.dolt-backup/scanbuf_fresh/pppp.darc"
: > "$BUF_ROOT/.dolt-backup/scanbuf_fresh/manifest"
touch -t "$(epoch_stamp "$(( $(date +%s) - 2 * 3600 ))")" "$BUF_ROOT/.dolt-backup/scanbuf_fresh/pppp.darc"
touch -t "$(epoch_stamp "$(( $(date +%s) - 3600 ))")"     "$BUF_ROOT/.dolt-backup/scanbuf_fresh/manifest"
# scanbuf_stale: manifest newest but 40 h old — the other scan_fail arm, a
# finding now rather than an indeterminate the patrol could sit on.
: > "$BUF_ROOT/.dolt-backup/scanbuf_stale/qqqq.darc"
: > "$BUF_ROOT/.dolt-backup/scanbuf_stale/manifest"
touch -t "$(epoch_stamp "$(( $(date +%s) - 41 * 3600 ))")" "$BUF_ROOT/.dolt-backup/scanbuf_stale/qqqq.darc"
touch -t "$(epoch_stamp "$(( $(date +%s) - 40 * 3600 ))")" "$BUF_ROOT/.dolt-backup/scanbuf_stale/manifest"

# Fail only the scan-buffer mktemp (its template names it); delegate the
# $DB_LIST temp and every other call to the real mktemp. Paths baked in at
# write time, `\$` kept literal for the shim's own parameters.
cat > "$TMP/mktempbin/mktemp" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
    case "\$arg" in
        *gctk-deacon-backup-scan*)
            printf '%s\n' "\$arg" >> "$BUF_FIRED"
            echo "mktemp: failed to create file via template '\$arg': No space left on device" >&2
            exit 1 ;;
    esac
done
exec "$REAL_MKTEMP" "\$@"
EOF
chmod +x "$TMP/mktempbin/mktemp"

BUF_OUT="$(PATH="$TMP/mktempbin:$PATH" GC_CITY_PATH="$BUF_ROOT" GC_CITY="$BUF_ROOT" \
    EXPECTED_DBS="scanbuf_fresh scanbuf_stale" bash "$TMP/check.sh" 2>&1)"

# Vacuity guard: if the snippet stopped buffering through the mktemp command,
# the shim never fires and the fixtures enumerate for real — asserting nothing.
if [ -s "$BUF_FIRED" ]; then
    ok "mktemp buffer shim was exercised (scan buffering really was forced to fail)"
else
    bad "mktemp buffer shim never fired — buffering was NOT forced to fail; got: $BUF_OUT"
fi

buf_expect() {
    local db="$1" want="$2" line
    line="$(printf '%s\n' "$BUF_OUT" | grep -E "^(OK|FLAG|RECHECK|INFO) $db:" | head -1 || true)"
    case "$line" in
        "$want "*) ok "$db -> $want ($line)" ;;
        "")        bad "$db -> no verdict emitted; got: $BUF_OUT" ;;
        *)         bad "$db -> expected $want, got: $line" ;;
    esac
}
buf_expect scanbuf_fresh RECHECK  # buffer denied + fresh manifest = unproven, not OK
buf_expect scanbuf_stale FLAG     # buffer denied + 40 h manifest = a finding now

# The headline invariant, as for a failed find: a directory the patrol could
# not buffer must never read OK. This is the assertion that fails against
# pre-fix code — a `<<<` loop buffers scanbuf_fresh and emits `OK scanbuf_fresh`.
if grep -qE '^OK ' <<< "$BUF_OUT"; then
    bad "a backup directory whose scan could not be buffered read as OK: $(printf '%s\n' "$BUF_OUT" | grep -E '^OK ')"
else
    ok "no unbufferable backup directory read as OK"
fi

# Step 3 quotes the verdict verbatim, so it has to name the buffering failure —
# "the host is out of scratch space" is a different action from "re-run the dog".
if grep -qiE 'buffer|temp file' < <(grep -E '^RECHECK scanbuf_fresh:' <<< "$BUF_OUT"); then
    ok "buffer-failure verdict names the buffering/temp failure as the cause"
else
    bad "buffer-failure verdict does not name the cause: $(printf '%s\n' "$BUF_OUT" | grep -E '^RECHECK scanbuf_fresh:' || true)"
fi

# ...and the buffer-failure arm must survive a strict shell too. The fix reads
# the mktemp status with `|| scan_buf=""`, the same `|| rc=$?` shape the find
# arm uses; written as a bare `scan_buf=$(mktemp ...)` it would abort the whole
# step under `set -e` the instant the buffer could not be made, and the
# unreadable-directory verdict would vanish into a silent exit.
BUF_STRICT_RC=0
BUF_STRICT_OUT="$(PATH="$TMP/mktempbin:$PATH" GC_CITY_PATH="$BUF_ROOT" GC_CITY="$BUF_ROOT" \
    EXPECTED_DBS="scanbuf_fresh scanbuf_stale" \
    bash -euo pipefail "$TMP/check.sh" 2>&1)" || BUF_STRICT_RC=$?
if [ "$BUF_STRICT_RC" -eq 0 ]; then
    ok "snippet exits clean under 'bash -euo pipefail' with a failing buffer mktemp"
else
    bad "snippet aborted under 'bash -euo pipefail' (rc=$BUF_STRICT_RC); got: $BUF_STRICT_OUT"
fi
for pair in "scanbuf_fresh:RECHECK" "scanbuf_stale:FLAG"; do
    bdb="${pair%%:*}"; bwant="${pair##*:}"
    bline="$(grep -E "^(OK|FLAG|RECHECK|INFO) $bdb:" <<< "$BUF_STRICT_OUT" | head -1 || true)"
    case "$bline" in
        "$bwant "*) ok "strict shell: $bdb -> $bwant ($bline)" ;;
        "")         bad "strict shell: $bdb emitted no verdict; got: $BUF_STRICT_OUT" ;;
        *)          bad "strict shell: $bdb expected $bwant, got: $bline" ;;
    esac
done

# --- Root-level terminal findings -------------------------------------------
# A missing or empty backup root means NO database has a restorable backup. It
# must be an explicit, named finding — not an unmatched glob falling through the
# per-database loop, and not a bare warning the deacon can log past.
root_case() {
    local label="$1" root="$2"
    local out
    out="$(GC_CITY_PATH="$root" GC_CITY="$root" EXPECTED_DBS="$DBS" bash "$TMP/check.sh" 2>&1)"
    if grep -q '^FLAG-ROOT:' <<< "$out"; then
        ok "$label -> FLAG-ROOT ($(printf '%s\n' "$out" | grep '^FLAG-ROOT:' | head -1))"
    else
        bad "$label -> no FLAG-ROOT finding; got: $out"
    fi
    # It has to name the databases, or the escalation template is empty.
    if grep -q 'healthy' <<< "$out"; then
        ok "$label finding names the affected databases"
    else
        bad "$label finding does not name the affected databases: $out"
    fi
    if grep -qE '^(OK|FLAG|RECHECK|INFO) \*' <<< "$out"; then
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

# --- The stub gc behind the un-overridden default path ------------------------
# It answers each thing the snippet and backup-alarm-scope.sh ask of gc from what
# the case set, and logs every call. Paths are baked in at write time.
GC_LOG="$TMP/gc.log"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GC_LOG"
case "\$*" in
    *" scripts-dir") printf '%s\n' "$HERE" ;;
    "dolt health --json") printf '%s' "\${STUB_HEALTH:-}" ;;
    "rig list --json") [ -n "\${STUB_RIGS:-}" ] || exit 1; printf '%s' "\$STUB_RIGS" ;;
esac
EOF
chmod +x "$TMP/bin/gc"

# --- No database list -------------------------------------------------------
# If the health report yields no databases, nothing is verified. That is a
# terminal finding too — an empty loop must never read as "all clean". The stub
# gc runs the snippet's default EXPECTED_DBS resolution hermetically; this also
# exercises the un-overridden default path.
for no_dbs in '{"databases":[]}' 'not json' ''; do
    NODB="$(STUB_HEALTH="$no_dbs" PATH="$TMP/bin:$PATH" GC_CITY_PATH="$TMP" GC_CITY="$TMP" bash "$TMP/check.sh" 2>&1)"
    if grep -q '^FLAG-ROOT: health report listed no databases' <<< "$NODB"; then
        ok "health report '$no_dbs' -> FLAG-ROOT ($(grep '^FLAG-ROOT:' <<< "$NODB" | head -1))"
    else
        bad "health report '$no_dbs' did not produce the no-database FLAG-ROOT; got: $NODB"
    fi
done

# --- A suspended rig's database is left out of the scan ----------------------
# Gas City's backup order skips a suspended rig's store, so its manifest ages by
# design. What a suspended rig shares with a running one is still backed up and
# still judged, and so is anything no suspended rig can be shown to hold.
SCOPE_SH="$HERE/backup-alarm-scope.sh"
CITY_FIX="$TMP/city"
mkdir -p "$CITY_FIX/.beads" "$CITY_FIX/.dolt-backup"
printf '{"dolt_database":"hq"}\n' > "$CITY_FIX/.beads/metadata.json"
mk_rig_store() { # <rig> <database>
    mkdir -p "$CITY_FIX/rigs/$1/.beads"
    printf '{"dolt_database":"%s"}\n' "$2" > "$CITY_FIX/rigs/$1/.beads/metadata.json"
}
mk_manifest() { # <database> <hours old>
    mkdir -p "$CITY_FIX/.dolt-backup/$1"
    : > "$CITY_FIX/.dolt-backup/$1/manifest"
    touch -t "$(age "$2")" "$CITY_FIX/.dolt-backup/$1/manifest"
}
mk_rig_store live live;              mk_manifest hq 1;        mk_manifest live 1
mk_rig_store livestale livestale;    mk_manifest livestale 40
mk_rig_store paused paused;          mk_manifest paused 40
mk_rig_store pausedshare shared;     mk_rig_store liveshare shared; mk_manifest shared 40
mkdir -p "$CITY_FIX/rigs/pausednometa";                       mk_manifest nometa 40
mk_rig_store pausednew pausednew
FIX_RIGS="$(jq -nc --arg c "$CITY_FIX" '{city_path: $c, rigs: [
    {name: "city", path: $c, hq: true, suspended: false},
    {name: "live", path: ($c + "/rigs/live"), suspended: false},
    {name: "livestale", path: ($c + "/rigs/livestale"), suspended: false},
    {name: "paused", path: ($c + "/rigs/paused"), suspended: true},
    {name: "pausedshare", path: ($c + "/rigs/pausedshare"), suspended: true},
    {name: "liveshare", path: ($c + "/rigs/liveshare"), suspended: false},
    {name: "pausednometa", path: ($c + "/rigs/pausednometa"), suspended: true},
    {name: "pausednew", path: ($c + "/rigs/pausednew"), suspended: true}]}')"
FIX_HEALTH='{"databases":[{"name":"hq"},{"name":"live"},{"name":"livestale"},{"name":"paused"},{"name":"shared"},{"name":"nometa"},{"name":"pausednew"}]}'
scope_run() { # <shell...> -- runs the shipped snippet on the fixture city
    STUB_HEALTH="$FIX_HEALTH" STUB_RIGS="${STUB_RIGS-$FIX_RIGS}" PATH="$TMP/bin:$PATH" \
        GC_CITY_PATH="$CITY_FIX" GC_CITY="$CITY_FIX" "$@" "$TMP/check.sh" 2>&1
}
scope_has() { # <output> <line prefix> <label>
    if grep -q "^$2" <<< "$1"; then ok "$3"; else bad "$3 (no '$2' line in: $1)"; fi
}
scope_hasnt() { # <output> <line prefix> <label>
    if grep -q "^$2" <<< "$1"; then bad "$3 (found '$2' in: $1)"; else ok "$3"; fi
}

SCOPE_OUT="$(scope_run bash)"
scope_has   "$SCOPE_OUT" "OK hq:"           "the city's own database is still scanned"
scope_has   "$SCOPE_OUT" "OK live:"         "a running rig's fresh backup still reads OK"
scope_has   "$SCOPE_OUT" "FLAG livestale:"  "a running rig's stale backup still flags"
scope_hasnt "$SCOPE_OUT" "FLAG paused:"     "a suspended rig's stale backup does not flag"
scope_hasnt "$SCOPE_OUT" "OK paused:"       "  ... and gets no verdict it did not earn"
scope_has   "$SCOPE_OUT" "INFO paused: backup dir outside the scan" "  ... only the advisory line"
scope_has   "$SCOPE_OUT" "FLAG shared:"     "a store a running rig also names still flags"
scope_has   "$SCOPE_OUT" "FLAG nometa:"     "a database no rig is shown to hold still flags"
scope_hasnt "$SCOPE_OUT" "FLAG pausednew:"  "a suspended rig's store with no backup dir does not flag either"
SCOPE_STRICT="$(scope_run bash -euo pipefail)"
if [ "$SCOPE_STRICT" = "$SCOPE_OUT" ]; then
    ok "the same verdicts under a strict shell"
else
    bad "a strict shell changed the verdicts: $SCOPE_STRICT"
fi

# Only a rig map that reads can leave a database out. One that does not read
# must leave the alarm flagging, and say why.
for bad_rigs in '' 'not json' '{"rigs":"none"}'; do
    SCOPE_DOWN="$(STUB_RIGS="$bad_rigs" scope_run bash)"
    scope_has "$SCOPE_DOWN" "FLAG paused:" "rig map '$bad_rigs': a suspended rig's stale backup still flags"
    scope_has "$SCOPE_DOWN" "backup-alarm-scope: the rig map did not read" "  ... and it says why"
done

# A report the patrol already holds is used, and nothing asks for another.
: > "$GC_LOG"
SCOPE_HELD="$(HEALTH_JSON="$FIX_HEALTH" scope_run bash)"
scope_hasnt "$SCOPE_HELD" "FLAG paused:" "a held health report leaves the suspended rig's database out too"
if grep -q 'dolt health' "$GC_LOG"; then
    bad "a held health report was probed again: $(cat "$GC_LOG")"
else
    ok "  ... without probing the data plane again"
fi

# The block reads an empty list as the FLAG-ROOT above. The script's own answer
# is what a reader of the deacon's output has to go on.
SCOPE_RC=0
SCOPE_NODB="$(PATH="$TMP/bin:$PATH" "$SCOPE_SH" databases '{"databases":[]}' 2>"$TMP/scope.err")" || SCOPE_RC=$?
if [ "$SCOPE_RC" -eq 1 ] && [ -z "$SCOPE_NODB" ] && grep -q 'listed no databases' "$TMP/scope.err"; then
    ok "a health report with no database prints nothing, exits 1 and says so"
else
    bad "a health report with no database: rc=$SCOPE_RC stdout='$SCOPE_NODB' stderr='$(cat "$TMP/scope.err")'"
fi

# --- A suspended rig's scope in the doctor's freshness finding ---------------
# The finding joins one clause per scope. backup-alarm-scope.sh takes out a
# suspended rig's clause, and with none left the result reads ok, which is what
# the patrol's filter skips. Nothing else in the payload moves.
OUTSIDE="$TMP/outside/pausedfar"
PAYLOAD_RIGS="$(jq -nc --arg c "$CITY_FIX" --arg o "$OUTSIDE" '{city_path: $c, rigs: [
    {name: "live", path: ($c + "/rigs/live"), suspended: false},
    {name: "paused-two", path: ($c + "/rigs/paused-two"), suspended: false},
    {name: "paused", path: ($c + "/rigs/paused"), suspended: true},
    {name: "pausedfar", path: $o, suspended: true}]}')"
STALE="dolt backup: last sync was 30h0m0s ago (> 24h0m0s) — backup pipeline may be disabled or broken"
PAYLOAD_FILE="$TMP/payload.json"
write_payload() { # <message> [<check name>] [<status>]
    jq -n --arg m "$1" --arg n "${2:-bd-backup-freshness}" --arg s "${3:-warning}" '{passed: 1, results: [
        {name: "city-structure", status: "ok", severity: "advisory", message: "OK"},
        {name: $n, status: $s, severity: "advisory", message: $m, fix_hint: "sync it"}]}' > "$PAYLOAD_FILE"
}
narrow() { # sets NARROW_RC and NARROW_ERR
    NARROW_RC=0
    NARROW_ERR="$(STUB_RIGS="${STUB_RIGS-$PAYLOAD_RIGS}" PATH="$TMP/bin:$PATH" "$SCOPE_SH" payload "$PAYLOAD_FILE" 2>&1)" || NARROW_RC=$?
}
result_field() { jq -r --arg f "$1" '.results[1][$f] // "<absent>"' "$PAYLOAD_FILE"; }
same() { # <got> <want> <label>
    if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi
}

write_payload "scope rigs/live: $STALE; scope rigs/paused: $STALE"
narrow
same "$NARROW_RC" 0 "a finding naming a running and a suspended scope is narrowed"
same "$(result_field message)" "scope rigs/live: $STALE" "  ... to the running rig's clause"
same "$(result_field status)" "warning" "  ... and stays a finding"
same "$(result_field fix_hint)" "sync it" "  ... with its fix hint"
same "$(jq -c '.results[0]' "$PAYLOAD_FILE")" '{"name":"city-structure","status":"ok","severity":"advisory","message":"OK"}' \
    "  ... and the next check is untouched"

write_payload "scope rigs/paused: $STALE; scope $OUTSIDE: $STALE"
narrow
same "$(result_field status)" "ok" "a finding naming only suspended scopes reads ok, one outside the city included"
same "$(result_field fix_hint)" "<absent>" "  ... and carries no fix hint"
same "$(jq -r '[.results[] | select(.status != "ok")] | length' "$PAYLOAD_FILE")" 0 "  ... so the patrol's filter finds nothing to file"

write_payload "scope rigs/paused-two: $STALE"
narrow
same "$(result_field message)" "scope rigs/paused-two: $STALE" "a running rig whose name extends a suspended one's keeps its clause"

write_payload "city: read backup_state.json: a; b; scope rigs/paused: read dolt-backup-state.json: c; d; scope rigs/live: $STALE"
narrow
same "$(result_field message)" "city: read backup_state.json: a; b; scope rigs/live: $STALE" \
    "the city's clause stays, and a clause goes with the semicolons in its own text"

write_payload "scope rigs/paused: $STALE" "bd-backup-state"
BEFORE="$(cat "$PAYLOAD_FILE")"; : > "$GC_LOG"
narrow
same "$(cat "$PAYLOAD_FILE")" "$BEFORE" "a sweep without this finding is left as it is"
same "$(grep -c 'rig list' "$GC_LOG" || true)" 0 "  ... and pays for no rig listing"

write_payload "scope rigs/paused: $STALE"
jq '.results += [{name: "bd-backup-state", status: "warning", severity: "advisory", message: "scope rigs/paused: quarantined"}]' \
    "$PAYLOAD_FILE" > "$PAYLOAD_FILE.next"
mv "$PAYLOAD_FILE.next" "$PAYLOAD_FILE"
narrow
same "$(jq -c '.results[2] | [.status, .message]' "$PAYLOAD_FILE")" '["warning","scope rigs/paused: quarantined"]' \
    "another check that names a suspended scope keeps its finding"

write_payload "scope rigs/paused: $STALE"
BEFORE="$(cat "$PAYLOAD_FILE")"
STUB_RIGS="" narrow
same "$NARROW_RC" 1 "a rig map that does not read exits non-zero"
same "$(cat "$PAYLOAD_FILE")" "$BEFORE" "  ... and the payload keeps the finding, byte for byte"
if grep -qF 'keeps every scope it names' <<< "$NARROW_ERR"; then
    ok "  ... and says why"
else
    bad "the narrowing did not say why: $NARROW_ERR"
fi

# A narrowed copy that cannot take the payload's place changes nothing either,
# and leaves nothing beside it.
mkdir -p "$TMP/nomv"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$TMP/nomv/mv"
chmod +x "$TMP/nomv/mv"
write_payload "scope rigs/paused: $STALE"
BEFORE="$(cat "$PAYLOAD_FILE")"
NOMV_RC=0
NOMV_ERR="$(STUB_RIGS="$PAYLOAD_RIGS" PATH="$TMP/nomv:$TMP/bin:$PATH" "$SCOPE_SH" payload "$PAYLOAD_FILE" 2>&1)" || NOMV_RC=$?
same "$NOMV_RC" 1 "a narrowed copy that cannot be moved into place exits non-zero"
same "$(cat "$PAYLOAD_FILE")" "$BEFORE" "  ... and the payload keeps the finding"
same "$(find "$TMP" -maxdepth 1 -name 'payload.json.*' | wc -l | tr -d ' ')" 0 "  ... and no scratch file stays beside it"
if grep -qF 'could not narrow' <<< "$NOMV_ERR"; then
    ok "  ... and says why"
else
    bad "the failed move did not say why: $NOMV_ERR"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
