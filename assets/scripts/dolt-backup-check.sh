#!/usr/bin/env bash
# dolt-backup-check — verify every live database has a restorable Dolt backup,
# by manifest mtime, never by `backups.dolt_stale`.
#
#   dolt-backup-check.sh        (HEALTH_JSON or EXPECTED_DBS in the environment)
#
# `gc dolt health --json` renders ABSENT backup data as `dolt_stale=false`, so
# that field reads false-clean through a TOTAL outage. A backup is restorable
# only up to its committed manifest: Dolt writes chunks first and the manifest
# LAST, so a healthy directory's newest file IS the manifest, and an
# equal-second tie resolves TO it. The scan is driven by the live database list
# from the health report, never a walk of the backup directories, because a
# database with no directory at all is invisible to a walk. A missing or empty
# backup root is one FLAG-ROOT naming every affected database. An in-flight sync
# gets a bounded RECHECK grace (GRACE_SEC) that a stale manifest (STALE_H)
# bypasses. A directory that cannot be read is UNPROVEN, never clean.
#
# Prints one verdict line per database: OK, FLAG, RECHECK, FLAG-ROOT, or an
# advisory INFO for a backup directory with no live database. Each FLAG line is
# a complete one-line reason, carried verbatim into the finding it files.
#
# Called by mol-deacon-patrol's dolt-health step.
# env: HEALTH_JSON (the step's `gc dolt health --json` payload, probed again
#      when empty), EXPECTED_DBS (overrides the database list), GRACE_SEC,
#      STALE_H, GC_CITY_PATH or GC_CITY (the city holding .dolt-backup).
BACKUP_ROOT="${GC_CITY_PATH:-$GC_CITY}/.dolt-backup"
# Expected databases come from the step's health report in $HEALTH_JSON,
# probed again when it is empty. Lazy by design — set EXPECTED_DBS to run
# against a fixture (the test does) and neither the probe nor jq is invoked.
: "${EXPECTED_DBS:=$(printf '%s' "${HEALTH_JSON:-$(gc dolt health --json)}" | jq -r '.databases[].name')}"
# In-flight grace: mid-sync the newest file IS a chunk, because the manifest
# is committed last. Only call that a failure once the writes have stopped
# advancing for GRACE_SEC — or once the manifest is already stale, which no
# healthy in-flight run can explain.
GRACE_SEC="${GRACE_SEC:-900}"
STALE_H="${STALE_H:-12}"
NOW=$(date +%s)
# Portable mtime: GNU (-c), BSD/macOS (-f), 0 when the file is absent.
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
# Split the list ONCE, with awk rather than with shell word-splitting, and
# derive both forms from it: one name per line for the loop below, and the
# space-joined one-liner a root-level finding names every affected database on.
# (zsh does not word-split unquoted expansions, so a shell split runs once on
# the whole list joined into a single token.)
DB_LIST=$(mktemp "${TMPDIR:-/tmp}/gctk-deacon-patrol.XXXXXX")
trap 'rm -f "$DB_LIST"' EXIT; trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
printf '%s' "$EXPECTED_DBS" | awk '{ for (i = 1; i <= NF; i++) print $i }' > "$DB_LIST"
DB_NAMES=$(awk '{ if (s == "") s = $0; else s = s " " $0 } END { print s }' "$DB_LIST")

if [ -z "$EXPECTED_DBS" ]; then
    echo "FLAG-ROOT: health report listed no databases - cannot verify any backup"
elif [ ! -d "$BACKUP_ROOT" ]; then
    echo "FLAG-ROOT: no backup root at $BACKUP_ROOT - NO restorable backup for: $DB_NAMES"
elif [ -z "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
    echo "FLAG-ROOT: backup root $BACKUP_ROOT is empty - NO restorable backup for: $DB_NAMES"
else
    while IFS= read -r name; do
        db="$BACKUP_ROOT/$name"
        if [ ! -d "$db" ]; then
            echo "FLAG $name: no backup directory at $db - never backed up"
            continue
        fi
        m_t=$(mtime_of "$db/manifest")
        # Seed the scan WITH the manifest so an mtime tie resolves to it: stat
        # reads whole seconds and Dolt commits the manifest LAST, so a tie is a
        # fast healthy sync. Only a chunk STRICTLY newer than the manifest
        # displaces it — the torn-backup signature.
        newest="manifest"; newest_t=$m_t
        # ...but a seed is only safe once the directory has actually been READ:
        # capture the scan and its exit status, because an enumeration that
        # fails (or lists nothing while the manifest is readable) would let the
        # seed carry a fresh manifest to OK and hide a newer chunk behind an
        # unreadable directory. Unread is UNPROVEN, never clean. `||` marks the
        # expected failure as handled so a strict shell survives.
        scan_rc=0
        scan_out=$(find "$db" -type f 2>/dev/null) || scan_rc=$?
        scan_fail=""
        if [ "$scan_rc" -ne 0 ]; then
            scan_why=$(find "$db" -type f 2>&1 >/dev/null | sed -n 1p || true)
            scan_fail="find exited $scan_rc${scan_why:+: $scan_why}"
        elif [ "$m_t" -gt 0 ] && [ -z "$scan_out" ]; then
            scan_fail="find listed no files though $db/manifest is readable"
        fi
        # Buffer the scan through a CHECKED temp file, never a `<<<` here-string:
        # bash backs a here-string with a temp it creates silently, so under disk
        # pressure the redirect fails, the loop runs zero times, `newest` keeps
        # its seeded manifest, and a chunk newer than the manifest reads OK
        # unseen. A buffer whose creation and write are both checked turns that
        # blackout into a scan_fail the arms below report.
        scan_buf=""
        if [ -z "$scan_fail" ]; then
            scan_buf=$(mktemp "${TMPDIR:-/tmp}/gctk-deacon-backup-scan.XXXXXX" 2>/dev/null) || scan_buf=""
            if [ -z "$scan_buf" ]; then
                scan_fail="could not create a temp file to buffer the directory scan for $db (disk pressure?)"
            elif ! printf '%s' "$scan_out" | awk 'NF { print }' > "$scan_buf"; then
                scan_fail="could not buffer the directory scan for $db - temp file unwritable (disk pressure?)"
            fi
        fi
        if [ -z "$scan_fail" ]; then
            while IFS= read -r f; do
                [ -n "$f" ] || continue
                t=$(mtime_of "$f")
                if [ "$t" -gt "$newest_t" ]; then newest_t="$t"; newest="${f##*/}"; fi
            done < "$scan_buf"
        fi
        [ -z "$scan_buf" ] || rm -f "$scan_buf"
        since=$(( NOW - newest_t ))
        age_h=$(( (NOW - m_t) / 3600 ))
        if [ -n "$scan_fail" ]; then
            if [ "$m_t" -eq 0 ]; then
                echo "FLAG $name: backup directory scan failed ($scan_fail) and there is no manifest - nothing verifiably restorable"
            elif [ "$age_h" -gt "$STALE_H" ]; then
                echo "FLAG $name: backup directory scan failed ($scan_fail) and the manifest is ${age_h}h old (>${STALE_H}h = 2x backup cadence)"
            else
                echo "RECHECK $name: backup directory scan failed ($scan_fail) - cannot rule out a file newer than the ${age_h}h-old manifest"
            fi
        elif [ "$m_t" -eq 0 ]; then
            if [ "$newest_t" -gt 0 ] && [ "$since" -le "$GRACE_SEC" ]; then
                echo "RECHECK $name: no manifest yet, '$newest' written ${since}s ago - first commit may be in flight"
            else
                echo "FLAG $name: no manifest - nothing restorable"
            fi
        elif [ "$newest" != "manifest" ]; then
            if [ "$since" -le "$GRACE_SEC" ] && [ "$age_h" -le "$STALE_H" ]; then
                echo "RECHECK $name: newest file is '$newest' written ${since}s ago, manifest ${age_h}h old - sync may be in flight"
            else
                echo "FLAG $name: newest file is '$newest', not the manifest - uploaded but never committed; not restorable past ${age_h}h ago"
            fi
        elif [ "$age_h" -gt "$STALE_H" ]; then
            echo "FLAG $name: manifest is ${age_h}h old (>${STALE_H}h = 2x backup cadence)"
        else
            echo "OK $name: manifest is newest, ${age_h}h old"
        fi
    done < "$DB_LIST"
    for d in "$BACKUP_ROOT"/*/; do
        [ -d "$d" ] || continue
        extra="${d%/}"; extra="${extra##*/}"
        case " $DB_NAMES " in
            *" $extra "*) ;;
            *) echo "INFO $extra: backup dir with no live database (advisory)" ;;
        esac
    done
fi
