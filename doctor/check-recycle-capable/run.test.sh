#!/usr/bin/env bash
# Hermetic test for doctor/check-recycle-capable. gc is stubbed; the measurement
# arm runs the REAL overlay hook, because that arm exists to assert the shipped
# script and a stub would prove only that the fixture agrees with itself. The
# defer-guard arm runs against a REAL git repo, because that arm parses git's
# porcelain output and ages real mtimes. That arm mirrors the hook's own guard,
# so each case that builds a new guard state also runs the shipped hook on that
# tree: the hook must defer where the check reads the guard true, and recycle
# where it does not.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
OVERLAY="$HERE/../../overlays/cycle-recycle/.claude"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-recycle-capable-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
epoch_stamp() { date -d "@$1" '+%Y%m%d%H%M.%S' 2>/dev/null || date -r "$1" '+%Y%m%d%H%M.%S'; }
age_file() { touch -t "$(epoch_stamp "$(($(date +%s) - $2))")" "$1"; }

mkdir -p "$TMP/bin" "$TMP/pack/overlays/cycle-recycle/.claude/hooks"
HOOKDIR="$TMP/pack/overlays/cycle-recycle/.claude"
install_real_overlay() {
  cp "$OVERLAY/hooks/cycle-recycle.sh" "$HOOKDIR/hooks/cycle-recycle.sh"
  cp "$OVERLAY/settings.json" "$HOOKDIR/settings.json"
  chmod +x "$HOOKDIR/hooks/cycle-recycle.sh"
}
install_real_overlay

# gc is the only external the check still calls. Every invocation is logged, so
# a re-introduced city/API probe shows up as a call this check no longer makes.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
printf '%s\n' "$*" >> "${GC_LOG:-/dev/null}"
case "$*" in
  "cities --json")    [ -n "${CITIES_RC:-}" ] && exit "$CITIES_RC"; cat "$CITIES_JSON" ;;
  *"status --json")   [ -n "${STATUS_RC:-}" ] && exit "$STATUS_RC"; cat "$STATUS_JSON" ;;
  *"rig list --json") [ -n "${RIGS_RC:-}" ] && exit "$RIGS_RC"; cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
# A tripwire, not a fixture: the check must reach no HTTP endpoint at all now.
cat > "$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_LOG:-/dev/null}"
exit 22
CURL
chmod +x "$TMP/bin/gc" "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

cat > "$TMP/cities.json" <<EOF
{"cities":[{"name":"testcity","path":"$TMP/city"}]}
EOF
# alpha runs a refinery; the polecat and witness prove the role filter; beta's
# refineries are asleep and suspended.
cat > "$TMP/status.json" <<'EOF'
{"agents":[
 {"name":"gc-toolkit.refinery","qualified_name":"alpha/gc-toolkit.refinery","scope":"rig","running":true,"suspended":false},
 {"name":"gc-toolkit.witness","qualified_name":"alpha/gc-toolkit.witness","scope":"rig","running":true,"suspended":false},
 {"name":"gc-toolkit.deacon","qualified_name":"gc-toolkit.deacon","scope":"city","running":true,"suspended":false},
 {"name":"gc-toolkit.polecat-1","qualified_name":"alpha/gc-toolkit.polecat-1","scope":"rig","running":true,"suspended":false},
 {"name":"gc-toolkit.refinery","qualified_name":"gamma/gc-toolkit.refinery","scope":"rig","running":false,"suspended":false},
 {"name":"gc-toolkit.refinery","qualified_name":"beta/gc-toolkit.refinery","scope":"rig","running":true,"suspended":true}]}
EOF
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/rigs/alpha","suspended":false},
         {"name":"beta","path":"$TMP/rigs/beta","suspended":false}]}
EOF

mkdir -p "$TMP/rigs/alpha/.beads"
git -C "$TMP/rigs/alpha" init -q
git -C "$TMP/rigs/alpha" config user.email t@example.com
git -C "$TMP/rigs/alpha" config user.name Tester
printf 'dolt.mode: local\n' > "$TMP/rigs/alpha/.beads/config.yaml"
git -C "$TMP/rigs/alpha" add -A
git -C "$TMP/rigs/alpha" -c commit.gpgsign=false commit -qm init

# hook_verdict <tree> — what the shipped hook does at the end of a turn over its
# threshold, as the alpha refinery with <tree> as both its working directory and
# GC_RIG_ROOT: "recycles" (it called gc handoff) or "defers" (its git-op guard
# held it and it called no gc). The hook prepends $HOME/go/bin to PATH, so the
# logging stub there wins over this suite's gc stub.
mkdir -p "$TMP/hookhome/go/bin"
cat > "$TMP/hookhome/go/bin/gc" <<'HOOKGC'
#!/bin/sh
printf '%s\n' "$*" >> "$HOOK_GC_LOG"
HOOKGC
chmod +x "$TMP/hookhome/go/bin/gc"
printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":250000,"cache_creation_input_tokens":1000}}}' > "$TMP/over-threshold.jsonl"
hook_verdict() {
  local err calls
  : > "$TMP/hook-gc.log"
  err=$(cd "$1" && printf '{"transcript_path":"%s"}' "$TMP/over-threshold.jsonl" \
    | env -i PATH="$PATH" HOME="$TMP/hookhome" HOOK_GC_LOG="$TMP/hook-gc.log" \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        GC_AGENT=alpha/gc-toolkit.refinery GC_RIG_ROOT="$1" GC_CITY_PATH="$TMP/city" \
        GC_SESSION_ID=refinery-1 sh "$HOOKDIR/hooks/cycle-recycle.sh" 2>&1 >/dev/null)
  calls=$(cat "$TMP/hook-gc.log")
  case "$calls" in
    "handoff "*) echo recycles ;;
    "") case "$err" in *"refinery mid git-op"*) echo defers ;; *) echo "neither: $err" ;; esac ;;
    *) echo "unexpected gc calls: $calls" ;;
  esac
}

run_check() {
  : > "$TMP/curl.log"; : > "$TMP/gc.log"
  GC_PACK_DIR="$TMP/pack" GC_CITY_PATH="$TMP/city" \
  CITIES_JSON="${CITIES_JSON:-$TMP/cities.json}" STATUS_JSON="${STATUS_JSON:-$TMP/status.json}" \
  RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" \
  CURL_LOG="$TMP/curl.log" GC_LOG="$TMP/gc.log" bash "$CHECK" 2>&1
}

# --- 1. healthy and idle: silent, and measured through the shipped hook -------
OUT=$(run_check); RC=$?
eq "$RC" "0" "the real overlay hook plus a clean rig tree is OK"
has "$OUT" "measurement reads a transcript" "the OK line states what was asserted"
has "$OUT" "drift check sees a changed pack file" "including the drift probe through the shipped hook"
hasnt "$OUT" "defer guard true" "a clean tree raises no deferral note"
eq "$(cat "$TMP/curl.log")" "" "the check reaches no HTTP endpoint — the API measurement is gone"
hasnt "$(cat "$TMP/gc.log")" "cities --json" "and resolves no city name, which only the API URL needed"
has "$OUT" "beta/gc-toolkit.refinery: suspended" "a suspended refinery is noted, not judged"
has "$OUT" "gamma/gc-toolkit.refinery: not running" "an asleep refinery is noted, not judged"
eq "$(hook_verdict "$TMP/rigs/alpha")" "recycles" "the shipped hook recycles on the same clean tree, so the agreement cases below reach its guard"

# --- 2. a hook that measures NOTHING — the live failure this check exists for -
cat > "$HOOKDIR/hooks/cycle-recycle.sh" <<'MUTE'
#!/bin/sh
exit 0
MUTE
OUT=$(run_check); RC=$?
eq "$RC" "2" "a hook whose measurement returns nothing is an ERROR, not a silent skip"
has "$OUT" "returned nothing" "the finding names the empty measurement"
has "$OUT" "200000" "the finding states the threshold nothing can cross"
has "$OUT" "--measure" "the finding names the command a reader can rerun"
has "$OUT" "--drift refinery\` found no change" "and a drift check that sees nothing is a finding of its own"

# --- 3. a hook that measures the WRONG number --------------------------------
cat > "$HOOKDIR/hooks/cycle-recycle.sh" <<'WRONG'
#!/bin/sh
echo 42
WRONG
OUT=$(run_check); RC=$?
eq "$RC" "2" "a measurement that disagrees with the transcript is an ERROR"
has "$OUT" "returned \"42\"" "the finding quotes what the hook actually said"
has "$OUT" "251100" "and the total the transcript actually carries"

# --- 4. a hook predating --measure or --drift never recycles the doctor -------
# It ignores the flag and falls through to its self-gate, so each probe must
# hand it an empty GC_AGENT or running the doctor would recycle whoever ran it.
cat > "$HOOKDIR/hooks/cycle-recycle.sh" <<'OLD'
#!/bin/sh
printf '[%s]\n' "${GC_AGENT:-}" >> "$SEEN_AGENT"
[ -n "${GC_AGENT:-}" ] || exit 0
echo "RECYCLED" >> "$SEEN_AGENT"
OLD
: > "$TMP/seen-agent"
OUT=$(SEEN_AGENT="$TMP/seen-agent" GC_AGENT="alpha/gc-toolkit.refinery" run_check); RC=$?
eq "$RC" "2" "a hook with no --measure or --drift reports as unmeasurable"
eq "$(cat "$TMP/seen-agent")" "[]
[]" "both probes cleared GC_AGENT, so the old self-gate exits each time"
hasnt "$(cat "$TMP/seen-agent")" "RECYCLED" "and the doctor never triggers a recycle by probing"
install_real_overlay

# --- 5. the Stop wiring must exist and keep the hook's stdin -----------------
rm -f "$HOOKDIR/settings.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an overlay that ships the hook but no settings.json is an ERROR"
has "$OUT" "never runs" "the finding says the hook has no trigger"

printf '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"sh /x/other.sh"}]}]}}\n' > "$HOOKDIR/settings.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a Stop hook that never invokes cycle-recycle.sh is an ERROR"
has "$OUT" "nothing to run it" "the finding says the script is shipped unwired"

printf '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"sh cycle-recycle.sh < /dev/null"}]}]}}\n' > "$HOOKDIR/settings.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a Stop wiring that redirects the hook's stdin away is an ERROR"
has "$OUT" "redirects the hook's stdin away" "the finding names the starved stdin"
has "$OUT" "arrives ON stdin" "and says why that kills the measurement"

printf '{"hooks":{"Stop":[]}}\n' > "$HOOKDIR/settings.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a settings.json with no Stop command at all is an ERROR"
has "$OUT" "no trigger" "the finding says the recycle is never invoked"

# The real overlay's Stop wiring, with each UserPromptSubmit shape below.
with_prompt_hooks() {
  jq --argjson ups "$1" '.hooks.UserPromptSubmit = $ups' "$OVERLAY/settings.json" > "$HOOKDIR/settings.json"
}
with_prompt_hooks '[]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a settings.json whose UserPromptSubmit runs no cycle-recycle.sh --prompt is an ERROR"
has "$OUT" "no UserPromptSubmit hook" "the finding names the missing prompt-time wiring"
hasnt "$OUT" "no Stop hook" "and the Stop wiring beside it raises nothing"

with_prompt_hooks '[{"matcher":"","hooks":[{"type":"command","command":"sh cycle-recycle.sh"}]}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a UserPromptSubmit wiring that runs the hook without --prompt is an ERROR"
has "$OUT" "no UserPromptSubmit hook" "since only --prompt reads drift before a prompt"

with_prompt_hooks '[{"matcher":"","hooks":[{"type":"command","command":"sh cycle-recycle.sh --prompt < /dev/null"}]}]'
OUT=$(run_check); RC=$?
eq "$RC" "2" "a UserPromptSubmit wiring that redirects the hook's stdin away is an ERROR"
has "$OUT" "the transcript path and the prompt arrive ON stdin" "the finding says what the starved hook loses"
install_real_overlay

# --- 6. fail-CLOSED on an unreadable roster or a missing tool ----------------
OUT=$(STATUS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable agent roster warns, never passes"
has "$OUT" "would not be visible" "the warning says a latched guard could hide"
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable rig roster warns — a latched guard would be invisible"
has "$OUT" "defer-guard arm did not run" "the warning names the arm that was skipped"
# An absolute bash, so emptying PATH removes jq without removing the shell.
OUT=$(PATH=/nonexistent GC_PACK_DIR="$TMP/pack" "$BASH" "$CHECK" 2>&1); RC=$?
eq "$RC" "1" "a host without jq warns — the hook's only measurement tool is absent"
has "$OUT" "jq is not on PATH" "and says which tool is missing"

# --- 7. a roster that carries agents but no refinery -------------------------
cat > "$TMP/status-norole.json" <<'EOF'
{"agents":[{"name":"gc-toolkit.polecat-1","qualified_name":"alpha/gc-toolkit.polecat-1","scope":"rig","running":true,"suspended":false}]}
EOF
OUT=$(STATUS_JSON="$TMP/status-norole.json" run_check); RC=$?
eq "$RC" "1" "a roster with agents but no refinery warns, never reports OK"
has "$OUT" "roster's naming moved" "the warning names the drift it cannot rule out"
printf '{"agents":[]}\n' > "$TMP/status-empty.json"
OUT=$(STATUS_JSON="$TMP/status-empty.json" run_check); RC=$?
eq "$RC" "0" "a city that runs no agent at all reads no guard and stays silent"

# --- 8. LATCHED defer guard — the other live failure -------------------------
printf 'dolt.mode: server\n' > "$TMP/rigs/alpha/.beads/config.yaml"
age_file "$TMP/rigs/alpha/.beads/config.yaml" $((23 * 86400))
OUT=$(run_check); RC=$?
eq "$RC" "2" "a tracked file dirty past the bound is an ERROR, not a deferral"
has "$OUT" ".beads/config.yaml" "the finding names the file that latched the guard"
has "$OUT" "23d" "the finding states how long the guard has been true"
has "$OUT" "rig alpha" "the finding names the rig whose refinery is stuck"
has "$OUT" "24h bound" "the finding states the bound it crossed"
eq "$(hook_verdict "$TMP/rigs/alpha")" "defers" "the shipped hook defers on the same dirty .beads/config.yaml"

# --- 9. the bound is configurable --------------------------------------------
OUT=$(GC_DOCTOR_RECYCLE_LATCH_HOURS=$((30 * 24)) run_check); RC=$?
eq "$RC" "0" "a bound wider than the age reads the same tree as a git op in flight"
has "$OUT" "inside the 720h bound" "the override is the bound the note reports"

# --- 10. a TRANSIENT dirty tree is not a latch -------------------------------
touch "$TMP/rigs/alpha/.beads/config.yaml"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a freshly dirtied tree is a git op in flight, not a latch"
has "$OUT" "defer guard true" "the transient deferral is noted"
hasnt "$OUT" "cannot fire" "and it is not a finding"
git -C "$TMP/rigs/alpha" checkout -q -- .beads/config.yaml

# --- 11. an in-flight git-op marker is recognised ----------------------------
: > "$TMP/rigs/alpha/.git/MERGE_HEAD"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a fresh merge marker defers normally"
has "$OUT" "MERGE_HEAD (git-op in progress)" "the marker is named as the guard's source"
eq "$(hook_verdict "$TMP/rigs/alpha")" "defers" "the shipped hook defers on the same marker"
age_file "$TMP/rigs/alpha/.git/MERGE_HEAD" $((3 * 86400))
OUT=$(run_check); RC=$?
eq "$RC" "2" "a merge marker older than the bound is a latch, not an op in flight"
has "$OUT" "MERGE_HEAD" "the stale marker is named"
rm -f "$TMP/rigs/alpha/.git/MERGE_HEAD"

# --- 12. untracked files never latch the guard -------------------------------
# The hook passes --untracked-files=no, so scratch must not read as a git op.
echo scratch > "$TMP/rigs/alpha/scratch.tmp"
age_file "$TMP/rigs/alpha/scratch.tmp" $((40 * 86400))
OUT=$(run_check); RC=$?
eq "$RC" "0" "an untracked file is scratch, not a defer guard"
hasnt "$OUT" "scratch.tmp" "and it is named in no finding"
eq "$(hook_verdict "$TMP/rigs/alpha")" "recycles" "the shipped hook does not defer on it either"
rm -f "$TMP/rigs/alpha/scratch.tmp"

# --- 13. a rig with no refinery is not read ----------------------------------
cat > "$TMP/status-nowork.json" <<'EOF'
{"agents":[{"name":"gc-toolkit.witness","qualified_name":"alpha/gc-toolkit.witness","scope":"rig","running":true,"suspended":false}]}
EOF
printf 'dolt.mode: server\n' > "$TMP/rigs/alpha/.beads/config.yaml"
age_file "$TMP/rigs/alpha/.beads/config.yaml" $((23 * 86400))
OUT=$(STATUS_JSON="$TMP/status-nowork.json" run_check); RC=$?
eq "$RC" "1" "the guard is refinery-only — a witness-only rig is not read"
hasnt "$OUT" "config.yaml" "no dirty-tree finding is raised for it"
git -C "$TMP/rigs/alpha" checkout -q -- .beads/config.yaml

# --- 14. a pack that ships no hook has nothing to assert ---------------------
mkdir -p "$TMP/emptypack"
OUT=$(GC_PACK_DIR="$TMP/emptypack" GC_CITY_PATH="$TMP/city" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "a pack with no cycle-recycle overlay is OK"
has "$OUT" "ships no cycle-recycle hook" "and says why it asserted nothing"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
