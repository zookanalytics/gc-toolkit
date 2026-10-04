#!/usr/bin/env bash
# Tests for build-scratch-reap.sh against a synthetic scratch root. Real
# filesystem and real lsof/proc — holder detection is the whole safety model, so
# the shell tools are NOT stubbed (harness_init would replace them).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-build-scratch-reap-test.XXXXXX")"
HOLDERS=()
cleanup() {
    for p in ${HOLDERS[@]+"${HOLDERS[@]}"}; do kill "$p" 2>/dev/null || true; done
    chmod -R u+w "$TMP" 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

# shellcheck source=assets/scripts/test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; no harness_init (keep real tools)
PASS=0; FAIL=0
SUT="$HERE/build-scratch-reap.sh"
ROOT="$TMP/root"
mkdir -p "$ROOT"

gone()  { if [ ! -e "$1" ]; then ok "$2"; else bad "$2 (still present: $1)"; fi; }
kept()  { if [ -e "$1" ]; then ok "$2"; else bad "$2 (was removed: $1)"; fi; }

# Background holders must not inherit this script's (or a command
# substitution's) stdout/stderr: a process that does keeps the pipe open and the
# reader blocks on EOF until the holder exits. Each detaches all three streams.
#
# A pid that is certainly dead: spawn a child and reap it. Linux allocates pids
# sequentially, so a just-freed pid is not reused until the counter wraps.
dead_pid() { local p; sleep 0.1 </dev/null >/dev/null 2>&1 & p=$!; wait "$p" 2>/dev/null || true; echo "$p"; }
# A live pid held for the duration of the run.
live_pid() { local p; sleep 300 </dev/null >/dev/null 2>&1 & p=$!; HOLDERS+=("$p"); echo "$p"; }
# Open a file inside PATHARG and keep it open, so lsof reports a holder.
hold_open() { ( exec 9>"$1"; exec sleep 300 ) </dev/null >/dev/null 2>&1 & HOLDERS+=("$!"); }

DEAD1="$(dead_pid)"; DEAD2="$(dead_pid)"; DEAD3="$(dead_pid)"; DEADH="$(dead_pid)"
LIVE1="$(live_pid)"; LIVERUN="$(live_pid)"

# --- dead scratch: must be reaped ---
mkdir -p "$ROOT/gct${DEAD1}-111";           : >"$ROOT/gct${DEAD1}-111/f"
mkdir -p "$ROOT/gct-${DEAD2}-222";          : >"$ROOT/gct-${DEAD2}-222/f"
mkdir -p "$ROOT/run.${DEAD3}";              : >"$ROOT/run.${DEAD3}/f"
mkdir -p "$ROOT/go-build99887766";          : >"$ROOT/go-build99887766/a.o"
mkdir -p "$ROOT/go-link-55443322";          : >"$ROOT/go-link-55443322/exe"
mkdir -p "$ROOT/gctk-liveness.deaddir"
: >"$ROOT/gctk-pr-facts.deadfile"

# --- live or held: must be kept ---
mkdir -p "$ROOT/gct${LIVE1}-333"            # pid alive
mkdir -p "$ROOT/run.${LIVERUN}"             # pid alive
mkdir -p "$ROOT/gct${DEADH}-444"            # dead pid BUT an open holder inside
hold_open "$ROOT/gct${DEADH}-444/.lock"
mkdir -p "$ROOT/go-build-held"; hold_open "$ROOT/go-build-held/obj"   # no pid, held
hold_open "$ROOT/gctk-held.file"            # held plain file

# --- unparseable / unrecognized / cache: must be kept ---
mkdir -p "$ROOT/gct12x-777"                 # matches gct<digit>, pid '12x' non-numeric
mkdir -p "$ROOT/gctfoo-1"                   # gct but not a pid form, not gctk
mkdir -p "$ROOT/run.bogus"                  # run. but non-numeric
mkdir -p "$ROOT/.pnpm-store"; : >"$ROOT/.pnpm-store/pkg"   # rebuild-cost cache
mkdir -p "$ROOT/unrelated-dir"              # matches no pattern

sleep 0.3   # let holders open their fds

# --- dry-run: decides but removes nothing ---
DRY="$(bash "$SUT" --root "$ROOT" --no-lock --dry-run 2>&1)"
has "$DRY" "would reap" "dry-run reports a plan"
has "$DRY" "dry-run" "dry-run summary names itself"
kept "$ROOT/gct${DEAD1}-111" "dry-run removes nothing (dead gct tree still there)"
kept "$ROOT/go-build99887766" "dry-run removes nothing (dead go-build still there)"

# --- real pass ---
OUT="$(bash "$SUT" --root "$ROOT" --no-lock --verbose 2>&1)"
has "$OUT" "reaped" "real pass prints a summary"

gone "$ROOT/gct${DEAD1}-111"      "reaps gct<pid>-<n> with a dead pid"
gone "$ROOT/gct-${DEAD2}-222"     "reaps gct-<pid>-<n> (dash form) with a dead pid"
gone "$ROOT/run.${DEAD3}"         "reaps run.<pid> with a dead pid"
gone "$ROOT/go-build99887766"     "reaps an unheld go-build tree"
gone "$ROOT/go-link-55443322"     "reaps an unheld go-link tree"
gone "$ROOT/gctk-liveness.deaddir" "reaps an unheld gctk-* dir"
gone "$ROOT/gctk-pr-facts.deadfile" "reaps an unheld gctk-* file"

kept "$ROOT/gct${LIVE1}-333"      "keeps gct<pid> whose pid is alive"
kept "$ROOT/run.${LIVERUN}"       "keeps run.<pid> whose pid is alive"
kept "$ROOT/gct${DEADH}-444"      "keeps a dead-pid tree that still has an open holder"
kept "$ROOT/go-build-held"        "keeps a held go-build tree (no pid, open fd inside)"
kept "$ROOT/gctk-held.file"       "keeps a held gctk-* file"
kept "$ROOT/gct12x-777"           "keeps a gct name whose pid is non-numeric (unparseable)"
kept "$ROOT/gctfoo-1"             "keeps a gct name that is not a pid form"
kept "$ROOT/run.bogus"            "keeps run.<non-numeric>"
kept "$ROOT/.pnpm-store"          "keeps the rebuild-cost cache .pnpm-store"
kept "$ROOT/unrelated-dir"        "keeps a dir matching no pattern"

# --- refuses to reap when lsof cannot be trusted ---
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
printf '#!/bin/sh\nexit 0\n' >"$FAKEBIN/lsof"; chmod +x "$FAKEBIN/lsof"   # lsof that reports nothing
mkdir -p "$ROOT/gct${DEAD1}-again"
RC=0
REFUSE="$(PATH="$FAKEBIN:$PATH" bash "$SUT" --root "$ROOT" --no-lock 2>&1)" || RC=$?
eq "$RC" "1" "refuses (exit 1) when lsof reports nothing for self"
has "$REFUSE" "refusing to reap" "refusal explains itself"
kept "$ROOT/gct${DEAD1}-again" "refusal leaves dead scratch untouched"

echo "build-scratch-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
