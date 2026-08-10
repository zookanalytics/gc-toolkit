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
ALERT_LINES="$(grep -E 'Backup needed:|Backup dog retries not clearing' <<< "$STEP" || true)"
if [ -z "$ALERT_LINES" ]; then
    bad "could not find the Step 3 backup alert templates in the dolt-health step"
else
    ok "found the Step 3 backup alert templates"

    if grep -qE 'newer file <' <<< "$ALERT_LINES"; then
        bad "Step 3 backup alert demands a 'newer file' most FLAG classes lack: $ALERT_LINES"
    else
        ok "Step 3 backup alerts demand no class-specific 'newer file' field"
    fi

    # Both of them — the dog nudge and the mayor escalation.
    if [ "$(grep -c 'verbatim' <<< "$ALERT_LINES" || true)" -ge 2 ]; then
        ok "both Step 3 backup alerts carry the Step 2a verdict line verbatim"
    else
        bad "Step 3 backup alerts do not both carry the verdict line: $ALERT_LINES"
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
    if grep -q '^FLAG-ROOT:' <<< "$NODB"; then
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
