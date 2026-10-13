#!/usr/bin/env bash
# doctor-parallel-reads.test.sh — regression test for the block a doctor check
# overlaps its probes with, and every copy of it (precedent:
# doctor-budget.test.sh).
#
# A check that reads its stores at once runs each read as a background job. The
# read lands in a file under a scratch tree the check holds open, its stderr
# lands beside it so the warning for a failed read can say why, and the
# per-store jobs start through a cap, so the load a check adds does not grow
# with the rig count. Pack scripts have no include mechanism, so the block
# lives as marker-fenced copies (# >>> doctor-parallel-reads / # <<<). Hand
# copies drift apart, and a copy that drops stderr leaves its warnings with an
# rc and no reason. This suite extracts every copy and asserts:
#   - one block, asserted by EXECUTING it rather than by matching its text;
#   - a read keeps its stdout scrubbed, its stderr beside it, and its own rc;
#   - the scratch tree is made under TMPDIR, held open, and removed on exit;
#   - the cap holds however many jobs start, waits only for its own jobs,
#     returns each job's status, and frees a slot even when `wait -n` reports
#     no job;
#   - no check carries a hand copy of any of it, and every copy sits below the
#     two blocks it calls into: doctor-budget's run_bounded and
#     control-char-scrub's scrub.
# Hermetic: reads the repo and runs the block; no gc, no city, no network.
#
# run-tests-scope: tree

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
[ -d "$REPO/doctor" ] || REPO="$HERE/../.."
FENCE="doctor-parallel-reads"
CANON_HOST="$REPO/doctor/check-routed-work-claimable/run.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-doctor-parallel-reads-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

# extract_fence <name> <file> prints the body of that file's <name> block.
extract_fence() { awk -v f="$1" '
    $0 ~ "^[[:space:]]*# >>> " f "[[:space:]]*$" {inb=1; next}
    $0 ~ "^[[:space:]]*# <<< " f "[[:space:]]*$" {inb=0}
    inb' "$2"; }
extract() { extract_fence "$FENCE" "$1"; }
# fence_line <name> <file> prints the line number of that file's <name> opener.
fence_line() { grep -n -E "^[[:space:]]*# >>> $1[[:space:]]*\$" "$2" | head -1 | cut -d: -f1; }

hosts() { find "$REPO/doctor" -name 'run.sh' -type f 2>/dev/null | sort; }

echo "── 1. the canonical block ──"
BLOCK="$(extract "$CANON_HOST")"
if [ -n "$BLOCK" ]; then ok "block present in check-routed-work-claimable"
else bad "block present in check-routed-work-claimable" "no marked block"; fi
printf '%s\n' "$BLOCK" > "$TMP/block-only.sh"
if bash -n "$TMP/block-only.sh" 2>/dev/null; then ok "block is valid bash"
else bad "block is valid bash" "bash -n failed"; fi
# The block calls run_bounded and scrub, so it runs here as every host runs it:
# below the host's own doctor-budget and control-char-scrub blocks.
{ extract_fence doctor-budget "$CANON_HOST"
  extract_fence control-char-scrub "$CANON_HOST"
  printf '%s\n' "$BLOCK"; } > "$TMP/block.sh"
# blk <script> runs <script> under set -u with the block in scope; extra
# arguments arrive as $1, $2 and so on.
blk() { local body="$1"; shift; bash -c 'set -u; . "$0"; '"$body" "$TMP/block.sh" "$@"; }

echo "── 2. every copy is byte-identical ──"
COPIES=0; DIVERGENT=0
while IFS= read -r f; do
    b="$(extract "$f")"
    [ -n "$b" ] || continue
    COPIES=$((COPIES + 1))
    if [ "$b" != "$BLOCK" ]; then
        DIVERGENT=$((DIVERGENT + 1))
        bad "$(basename "$(dirname "$f")"): copy matches canonical" "block differs from check-routed-work-claimable"
    fi
done < <(hosts)
[ "$DIVERGENT" -eq 0 ] && ok "all $COPIES copies identical"
# A floor, not an equality: new hosts are expected, a host going missing is not.
if [ "$COPIES" -ge 3 ]; then ok "copy census $COPIES ≥ 3"
else bad "copy census $COPIES ≥ 3" "copies disappeared — did a check inline its own reads again?"; fi

echo "── 3. a read keeps its stdout, its stderr and its own rc ──"
# probe <stdout> <stderr> <rc> prints both streams (printf %b escapes) and
# exits <rc>; it touches $PROBE_RAN when set, so a refused probe is visible.
cat > "$TMP/probe" <<'EOF'
#!/usr/bin/env bash
[ -z "${PROBE_RAN:-}" ] || : > "$PROBE_RAN"
printf '%b' "$1"; printf '%b' "$2" >&2; exit "$3"
EOF
chmod +x "$TMP/probe"
mkdir -p "$TMP/rt"
OUT="$(TMPDIR="$TMP/rt" blk 'reads_init t-read || exit 9
    read_to "$WORK/r.json" "$1" "[1,\t2]\n" "\n   \n  dolt: table not found\nsecond line\n" 3; rc=$?
    printf "rc=%s|out=%s|err=%s" "$rc" "$(cat "$WORK/r.json")" "$(err_of "$WORK/r.json")"' "$TMP/probe")"
eq "$OUT" "rc=3|out=[1,2]|err=  dolt: table not found" \
   "read_to returns the probe's rc, scrubs its stdout, and err_of names the first non-blank stderr line"
OUT="$(TMPDIR="$TMP/rt" blk 'reads_init t-read || exit 9
    read_to "$WORK/r.json" "$1" "[]" "a\001b\033c\n" 1
    printf "%s" "$(err_of "$WORK/r.json")"' "$TMP/probe")"
eq "$OUT" "abc" "err_of strips control characters, so a diagnostic stays one line"
LONG="$(printf '%0300d' 0)"
OUT="$(TMPDIR="$TMP/rt" blk 'reads_init t-read || exit 9
    read_to "$WORK/r.json" "$1" "[]" "$2\n" 1
    printf "%s" "$(err_of "$WORK/r.json")"' "$TMP/probe" "$LONG")"
eq "${#OUT}" "200" "err_of cuts a long diagnostic to 200 characters"
OUT="$(TMPDIR="$TMP/rt" blk 'reads_init t-read || exit 9
    read_to "$WORK/r.json" "$1" "[]" "" 2; rc=$?
    printf "rc=%s|err=[%s]" "$rc" "$(err_of "$WORK/r.json")"' "$TMP/probe")"
eq "$OUT" "rc=2|err=[]" "a probe that wrote no stderr gives err_of nothing to print, and the rc still stands"
rm -f "$TMP/ran"
OUT="$(TMPDIR="$TMP/rt" PROBE_RAN="$TMP/ran" blk 'reads_init t-read || exit 9
    BUDGET_DEADLINE=$(( $(budget_now) - 9 ))
    read_to "$WORK/r.json" "$1" "[]" "" 0; printf "%s" "$?"' "$TMP/probe")"
eq "$OUT" "124" "a read the budget no longer fits returns 124, as every NOT-checked arm expects"
if [ -e "$TMP/ran" ]; then bad "a refused read does not run its probe" "the probe ran anyway"
else ok "a refused read does not run its probe"; fi

echo "── 4. the scratch tree ──"
OUT="$(TMPDIR="$TMP/rt" blk 'reads_init t-tree || exit 9
    case "$WORK" in "$1"/gctk-t-tree.*) printf "named " ;; esac
    [ -d "$WORK" ] && printf "dir "
    printf held >&9 && [ "$(cat "$WORK/.hold")" = held ] && printf "held"' "$TMP/rt")"
eq "$OUT" "named dir held" "reads_init makes gctk-<check>.* under TMPDIR and holds a file in it open on fd 9"
eq "$(ls -A "$TMP/rt")" "" "the tree is removed when the check exits"
OUT="$(TMPDIR="$TMP/no-such-dir" blk 'if reads_init t-none; then printf made; else printf refused; fi')"
eq "$OUT" "refused" "with no usable TMPDIR, reads_init fails rather than handing out a tree it does not have"

echo "── 5. the cap ──"
# job <dir> <name> <rc> marks itself in flight, records how many are in flight,
# and exits <rc> once it has unmarked itself. With BARRIER=<n>, it then waits
# until <n> jobs have arrived, failing after 20s, so the last to arrive finds
# every other one still in flight.
cat > "$TMP/job" <<'EOF'
#!/usr/bin/env bash
d="$1"; mkdir "$d/in.$2"; : > "$d/arrived.$2"
ls -d "$d"/in.* 2>/dev/null | wc -l | tr -d ' ' >> "$d/peaks"
echo "$2" >> "$d/ran"
if [ -n "${BARRIER:-}" ]; then
    waited=0
    while [ "$(ls "$d"/arrived.* 2>/dev/null | wc -l | tr -d ' ')" -lt "$BARRIER" ]; do
        [ "$waited" -lt 200 ] || { rmdir "$d/in.$2"; exit 99; }
        sleep 0.1; waited=$((waited + 1))
    done
fi
sleep "${HOLD:-0.3}"
rmdir "$d/in.$2"
exit "$3"
EOF
chmod +x "$TMP/job"
# fan <dir> <n> starts <n> jobs through the cap and prints their statuses, in
# start order.
FAN='d="$1"; n="$2"; pids=(); i=1
    while [ "$i" -le "$n" ]; do fanout "$3" "$d" "j$i" "$i"; pids+=("$FANOUT_PID"); i=$((i + 1)); done
    for p in "${pids[@]}"; do fanout_wait "$p"; printf "%s " "$?"; done'
mkdir -p "$TMP/c1"
OUT="$(GC_DOCTOR_FANOUT=2 blk "$FAN" "$TMP/c1" 6 "$TMP/job")"
eq "$OUT" "1 2 3 4 5 6 " "six jobs through a cap of two all run, and each returns its own status"
eq "$(sort -n "$TMP/c1/peaks" | tail -1)" "2" "no more than two were ever in flight"
eq "$(grep -c . "$TMP/c1/ran")" "6" "every job ran"
# The control: the same six under the default cap, each held until all six are
# in flight. A fixture that could not see six at once would make the peak of
# two above prove nothing.
mkdir -p "$TMP/c2"
OUT="$(BARRIER=6 HOLD=0 blk "$FAN" "$TMP/c2" 6 "$TMP/job")"
eq "$OUT" "1 2 3 4 5 6 " "under the default cap the same six run at once (control)"
eq "$(sort -n "$TMP/c2/peaks" | tail -1)" "6" "…and all six were in flight together (control)"

# The bash manual promises 127 for a pid that is no longer an active child, so
# a status `wait -n` has reported may be gone by the time anyone asks for it.
# This shadow `wait` forgets each status that way, as the cases below require.
FORGETFUL='reported=" "
    wait() {
        if [ "${1:-}" = "-n" ]; then
            local v="" a prev=""
            for a in "$@"; do [ "$prev" = "-p" ] && v="$a"; prev="$a"; done
            builtin wait "$@"; local rc=$?
            [ -z "$v" ] || reported="$reported${!v} "
            return "$rc"
        fi
        case "$reported" in *" $1 "*) return 127 ;; esac
        builtin wait "$@"
    }
'

# The cap waits only for its own jobs. Another background job that has already
# exited must not free a slot: a bare `wait -n` would return for it and start
# the next job while the cap's only job still runs. Nor may the cap collect
# that job's status, which its owner still has to read. Here the cap's first
# job runs until a watcher releases it. The watcher waits until the other job
# has exited and half a second has passed, then records whether the second job
# had started, and only then releases the first.
mkdir -p "$TMP/c3"
OUT="$(GC_DOCTOR_FANOUT=1 blk "$FORGETFUL"'d="$1"
    ( : > "$d/other-done"; exit 9 ) & other=$!
    fanout bash -c "while [ ! -e \"\$1/release\" ]; do sleep 0.05; done" _ "$d"; first=$FANOUT_PID
    ( while [ ! -e "$d/other-done" ]; do sleep 0.05; done; sleep 0.5
      if [ -e "$d/second" ]; then echo early > "$d/verdict"; else echo waited > "$d/verdict"; fi
      : > "$d/release" ) & watcher=$!
    fanout bash -c ": > \"\$1/second\"" _ "$d"; second=$FANOUT_PID
    fanout_wait "$first"; fanout_wait "$second"; wait "$watcher"; wait "$other"
    printf "other=%s" "$?"' "$TMP/c3")"
eq "$(cat "$TMP/c3/verdict" 2>/dev/null)" "waited" "an unrelated job's exit frees no slot: the second job waited for the first"
eq "$OUT" "other=9" "and the unrelated job's status is left for its owner to read"

# A job the cap waited for still reports its status to fanout_wait, though
# `wait` itself has forgotten it.
OUT="$(GC_DOCTOR_FANOUT=1 blk "$FORGETFUL"'fanout bash -c "exit 7"; a=$FANOUT_PID
    fanout bash -c "exit 5"; b=$FANOUT_PID
    fanout_wait "$a"; ra=$?; fanout_wait "$b"; rb=$?; fanout_wait "$a"; ra2=$?
    printf "%s %s %s|%s" "$ra" "$rb" "$ra2" "$reported"')"
eq "${OUT%%|*}" "7 5 7" "a status the cap collected is returned by fanout_wait, as often as it is asked"
case "${OUT#*|}" in *[0-9]*) ok "…though \`wait\` itself had forgotten it (premise)" ;;
    *) bad "…though \`wait\` itself had forgotten it (premise)" "the cap reported no job through wait -n, so nothing was forgotten" ;; esac

# When `wait -n` reports no job, the cap waits for the oldest, so a slot still
# frees. Without that, the loop would spin forever on a bash whose `wait -n`
# names nothing, long after the doctor had abandoned the check.
OUT="$(GC_DOCTOR_FANOUT=1 timeout 20 bash -c 'set -u; . "$0"
    wait() { if [ "${1:-}" = "-n" ]; then return 2; fi; builtin wait "$@"; }
    fanout bash -c "exit 3"; a=$FANOUT_PID
    fanout bash -c "exit 4"; b=$FANOUT_PID
    fanout bash -c "exit 6"; c=$FANOUT_PID
    for p in "$a" "$b" "$c"; do fanout_wait "$p"; printf "%s " "$?"; done' "$TMP/block.sh")"; RC=$?
eq "$RC" "0" "with a wait -n that reports no job, the cap still returns"
eq "$OUT" "3 4 6 " "…and every job runs and reports its own status"

for v in 3:3 0:8 abc:8 '':8 -2:8 99999999999999999999:8; do
    got="$(GC_DOCTOR_FANOUT="${v%%:*}" blk 'printf "%s" "$FANOUT_CAP"')"
    eq "$got" "${v##*:}" "GC_DOCTOR_FANOUT='${v%%:*}' sets a cap of ${v##*:}"
done
eq "$(env -u GC_DOCTOR_FANOUT bash -c 'set -u; . "$0"; printf "%s" "$FANOUT_CAP"' "$TMP/block.sh")" "8" \
   "unset, the cap is 8"

echo "── 6. no check carries a copy of its own ──"
STRAY=0
while IFS= read -r f; do
    rel="doctor/$(basename "$(dirname "$f")")/run.sh"
    body="$(awk -v f="$FENCE" '
        $0 ~ "^[[:space:]]*# >>> " f "[[:space:]]*$" {inb=1}
        $0 ~ "^[[:space:]]*# <<< " f "[[:space:]]*$" {inb=0; next}
        !inb' "$f")"
    # A private definition drifts from the one block; the fence is where it lives.
    if printf '%s' "$body" | grep -qE '^[[:space:]]*(reads_init|read_to|err_of|fanout|fanout_wait|fanout_reaped)[[:space:]]*\(\)'; then
        bad "$rel: defines none of the block's helpers outside the fence" "it redefines one"; STRAY=1
    fi
    # A caller with no fence calls a function nothing defines: `bash -n` passes,
    # and only the branch reaching the call ever reports it. Whole-line
    # comments are prose, so a check may name a helper in one.
    if printf '%s\n' "$body" | grep -v '^[[:space:]]*#' \
         | grep -qE '(^|[^[:alnum:]_])(reads_init|read_to|err_of|fanout|fanout_wait)([^[:alnum:]_(]|$)' \
       && [ -z "$(extract "$f")" ]; then
        bad "$rel: carries the block it reads with" "it calls one of its helpers and has no fence"; STRAY=1
    fi
    # A copy calls run_bounded and scrub, so both of their blocks sit above it.
    if [ -n "$(extract "$f")" ]; then
        own=$(fence_line "$FENCE" "$f")
        for dep in doctor-budget control-char-scrub; do
            at=$(fence_line "$dep" "$f")
            if [ -z "$at" ] || [ "$at" -ge "$own" ]; then
                bad "$rel: carries the $dep block above this one" "the block calls into it"; STRAY=1
            fi
        done
    fi
done < <(hosts)
[ "$STRAY" -eq 0 ] && ok "every check that reads in parallel carries the one fenced block, below the blocks it calls"

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
