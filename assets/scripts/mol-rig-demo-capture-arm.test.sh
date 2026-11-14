#!/usr/bin/env bash
# Hermetic test for mol-rig-demo's capture block, the rig-demo-capture-run
# region of the capture step.
#
# rig-demo-capture.sh exits 1 when no clip appears and 3 when the clip records a
# step failing its proof. On either, the block appends a note naming which one,
# then declines through decline.sh, with a human gate on the request bead under
# the capture key, and exits 1. decline.sh files the gate, cancels the run and
# drains, and decline.test.sh holds that order. On success the block records the
# clip path on the request bead.
#
# A step's blocks can run under a strict shell, where a failing command whose
# status nothing catches ends the block on the spot. For this block that abort
# skips the decline, which leaves the run claimed with no gate behind it. So
# every case runs twice, once under `set -euo pipefail` and once under a plain
# shell, and both runs must reach the same end.
#
# EXECUTES the real block extracted verbatim between the formula markers, with
# the pour vars rendered at their defaults, against a stub capture, a fake `gc`,
# and a stub decline script. No live city, browser, or network.
#
# A capture's sandbox refuses a rig's own checkout, so the app runs from a
# detached worktree of it, which the step's rig-demo-app-root region makes. A
# pour names at most one app target, which the rig-demo-app-target region
# counts, and a pour that names none takes the app the rig's demo guide names in
# that worktree. The last cases run those two regions and the capture block with
# the real capture, sandbox library and workspace scripts, against a fixture
# city whose rig commits a guide, a stub engine, a stub sandbox-exec that keeps
# the profile it was handed, and a stub gctk that runs a copy's serve command
# through the library's sandbox, as gctk rig serve does.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-rig-demo.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rig-demo-capture-arm-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }

[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract the REAL block from the formula. --------------------------------
# A removed or renamed marker extracts nothing, and the checks below fail loudly.
MARKER=rig-demo-capture-run
awk -v m="$MARKER" '
  $0 ~ ("# >>> " m "$") {f=1; next}
  $0 ~ ("# <<< " m "$") {f=0}
  f' "$TOML" \
  | sed -e 's/{{rig_name}}/demo-rig/g' -e 's/{{capture_mode}}/walkthrough/g' \
        -e 's/{{serve_port}}//g' -e 's/{{narrate}}/true/g' \
        -e 's/{{binding_prefix}}/gc-toolkit./g' > "$TMP/block.sh"

echo "# the region extracts as runnable bash"
if [ ! -s "$TMP/block.sh" ]; then
  bad "extraction EMPTY: the $MARKER markers are missing"
  echo "PASS=$PASS FAIL=$FAIL"
  exit 1
fi
ok "extracted between the markers"
eq "$(grep -c "^# >>> $MARKER\$" "$TOML")" "1" "exactly one region"
case "$(cat "$TMP/block.sh")" in
  *\\*) bad "contains a backslash, which TOML line-ending escapes will mangle" ;;
  *)    ok  "backslash-free (safe inside a TOML triple-quoted string)" ;;
esac
case "$(cat "$TMP/block.sh")" in
  *'{{'*) bad "a pour var the test does not render" "$(grep -o '{{[a-z_]*}}' "$TMP/block.sh" | sort -u | tr '\n' ' ')" ;;
  *)      ok  "every pour var in the region is rendered" ;;
esac
bash -n "$TMP/block.sh" && ok "syntactically valid bash" || bad "failed bash -n"
{ printf 'set -euo pipefail\n'; cat "$TMP/block.sh"; } > "$TMP/strict.sh"
cp "$TMP/block.sh" "$TMP/plain.sh"

# --- Fakes. --------------------------------------------------------------------
# gc: the block reaches `bd update` (the failure note, or the clip path on
# success), and a `runtime drain-ack` the block made itself would log DRAIN. The
# capture and decline stubs sit in a stub pack, $STUB_PACK, which gc names for
# `gc gc-toolkit scripts-dir`. Each fake records its verb into one ordered log
# and its argv into its own file.
mkdir -p "$TMP/bin" "$TMP/pack/assets/scripts" "$TMP/cwd"
SHEBANG="#!${BASH:-/usr/bin/env bash}"
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
  "bd update")         printf 'UPDATE\n' >> "$FAKE_LOG"; printf '%s\n' "$*" >> "$FAKE_DIR/gc.argv" ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG" ;;
esac
exit 0
GC
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/pack/assets/scripts/rig-demo-capture.sh" <<'CAP'
printf 'CAPTURE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "$FAKE_DIR/capture.argv"
exit "$FAKE_CAPTURE_RC"
CAP
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/pack/assets/scripts/decline.sh" <<'DECLINE'
printf 'DECLINE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "$FAKE_DIR/decline.argv"
exit "${FAKE_DECLINE_RC:-0}"
DECLINE
chmod +x "$TMP/bin/gc" "$TMP/pack/assets/scripts/"*.sh
export PATH="$TMP/bin:$PATH"
export STUB_PACK="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH="" GIT_CEILING_DIRECTORIES="$TMP"

# The variables the capture step sets before this block: the request bead, the
# resolved script, the clip path, the app target, and the scripts dir.
OUT="$TMP/rig-demo/tk-req/demo-rig-walkthrough.mp4"

# run <strict|plain> <capture exit> prints "<rc>|<ordered verb log>"
#   FAKE_DECLINE_RC sets the decline stub's exit.
run() {
  : > "$TMP/log"; : > "$TMP/gc.argv"; : > "$TMP/capture.argv"; : > "$TMP/decline.argv"
  local rc=0
  ( cd "$TMP/cwd" &&
    REQUEST_BEAD=tk-req SCRIPT_PATH="$TMP/cwd/walkthrough.md" OUT="$OUT" \
    SERVE_DIR="${RUN_SERVE_DIR-$TMP/cwd/site}" SERVE_CMD="" BASE_URL="" APP_ROOT="$TMP/cwd" \
    SCRIPTS="$TMP/pack/assets/scripts" \
    FAKE_LOG="$TMP/log" FAKE_DIR="$TMP" FAKE_CAPTURE_RC="$2" \
    FAKE_DECLINE_RC="${FAKE_DECLINE_RC:-0}" \
      bash "$TMP/$1.sh" ) > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

for MODE in strict plain; do
  echo "# $MODE shell: a clean capture records the clip on the request bead"
  eq "$(run "$MODE" 0)" "0|CAPTURE;UPDATE;" "$MODE: exit 0 records the clip, with no decline"
  has "$(cat "$TMP/capture.argv")" "--output $OUT" "$MODE: the capture writes the clip the block records"
  has "$(cat "$TMP/gc.argv")" "bd update tk-req --set-metadata demo_mp4_path=$OUT" "$MODE: the clip path lands on the request bead"

  echo "# $MODE shell: no clip declines with a gate on the request bead"
  eq "$(run "$MODE" 1)" "1|CAPTURE;UPDATE;DECLINE;" "$MODE: exit 1 notes the failure, declines, and exits 1, leaving the drain to decline.sh"
  has "$(cat "$TMP/decline.argv")" "--step mol-rig-demo.capture --reason capture of demo-rig failed: " "$MODE: the decline names the capture step and why it ends"
  has "$(cat "$TMP/decline.argv")" "--subject tk-req --key rig-demo-capture-failed --message " "$MODE: the gate blocks the request bead under the capture key"
  has "$(cat "$TMP/decline.argv")" "produced no MP4" "$MODE: exit 1 is reported as no clip"
  case "$(cat "$TMP/decline.argv")" in
    *--formula*) bad "$MODE: the decline arms a re-sling; a demo's pour carries its vars, so a person re-pours it" ;;
    *) ok "$MODE: the decline arms no re-sling" ;;
  esac

  echo "# $MODE shell: a clip with a failed proof declines the same way"
  eq "$(run "$MODE" 3)" "1|CAPTURE;UPDATE;DECLINE;" "$MODE: exit 3 notes the failure, declines, and exits 1"
  has "$(cat "$TMP/decline.argv")" "the clip at $OUT recorded at least one step failing its proof" "$MODE: the gate names the failed-proof clip"
  has "$(cat "$TMP/gc.argv")" "--append-notes rig-demo: capture failed for demo-rig" "$MODE: the request bead's note records the failure"
  has "$(cat "$TMP/gc.argv")" "failing its proof" "$MODE: and names the failed proof"

  echo "# $MODE shell: a decline that does not land still ends the block"
  eq "$(FAKE_DECLINE_RC=1 run "$MODE" 3)" "1|CAPTURE;UPDATE;DECLINE;" "$MODE: the block exits 1 and does not drain"

  echo "# $MODE shell: a pour that names no app target hands the capture the worktree, whose guide names the app"
  eq "$(RUN_SERVE_DIR="" run "$MODE" 0)" "0|CAPTURE;UPDATE;" "$MODE: the capture runs and the clip is recorded"
  has "$(cat "$TMP/capture.argv")" "--guide $TMP/cwd" "$MODE: the capture takes the app from the guide in the worktree"
  case "$(cat "$TMP/capture.argv")" in
    *--serve*|*--base-url*|*--cwd*) bad "$MODE: and names no app of its own" "$(cat "$TMP/capture.argv")" ;;
    *) ok "$MODE: and names no app of its own" ;;
  esac
done

# --- The app target and root, through the real capture and its sandbox. ---------
TARGET_MARKER=rig-demo-app-target
awk -v m="$TARGET_MARKER" '
  $0 ~ ("# >>> " m "$") {f=1; next}
  $0 ~ ("# <<< " m "$") {f=0}
  f' "$TOML" | sed -e 's/{{rig_name}}/demo-rig/g' -e 's/{{binding_prefix}}/gc-toolkit./g' > "$TMP/app-target.sh"
echo "# the app target's region extracts as runnable bash"
[ -s "$TMP/app-target.sh" ] && ok "extracted between the $TARGET_MARKER markers" || bad "extraction EMPTY: the $TARGET_MARKER markers are missing"
eq "$(grep -c "^# >>> $TARGET_MARKER\$" "$TOML")" "1" "exactly one $TARGET_MARKER region"
case "$(cat "$TMP/app-target.sh")" in
  *'{{'*) bad "a pour var the test does not render in $TARGET_MARKER" ;;
  *)      ok  "every pour var in $TARGET_MARKER is rendered" ;;
esac
APP_MARKER=rig-demo-app-root
awk -v m="$APP_MARKER" '
  $0 ~ ("# >>> " m "$") {f=1; next}
  $0 ~ ("# <<< " m "$") {f=0}
  f' "$TOML" | sed -e 's/{{rig_name}}/demo-rig/g' > "$TMP/app-root.sh"
echo "# the app root's region extracts as runnable bash"
[ -s "$TMP/app-root.sh" ] && ok "extracted between the $APP_MARKER markers" || bad "extraction EMPTY: the $APP_MARKER markers are missing"
eq "$(grep -c "^# >>> $APP_MARKER\$" "$TOML")" "1" "exactly one $APP_MARKER region"
{ printf 'set -euo pipefail\n'; cat "$TMP/app-target.sh" "$TMP/app-root.sh" "$TMP/block.sh"; } > "$TMP/app-strict.sh"
cat "$TMP/app-target.sh" "$TMP/app-root.sh" "$TMP/block.sh" > "$TMP/app-plain.sh"
bash -n "$TMP/app-plain.sh" && ok "the three regions run as one script" || bad "the three regions failed bash -n"

# A city whose one rig is a git repository holding a store, a committed site,
# and a demo guide that names the site as its app.
CITY="$TMP/city"; RIG="$CITY/rigs/demo-rig"; WS="$TMP/ws"; WT="$WS/gc-review-tk-req/wt"
mkdir -p "$RIG/.beads" "$RIG/site" "$RIG/docs" "$TMP/home" "$WS"
printf '<!doctype html><title>x</title>\n' > "$RIG/site/index.html"
printf '# The demo guide\n\n## Bring the app up\n\n**Serve dir:** `site`\n' > "$RIG/docs/review-demo.md"
printf '.beads/\n' > "$RIG/.gitignore"
git -C "$RIG" init -q
git -C "$RIG" add .gitignore site docs
git -C "$RIG" -c user.name=fixture -c user.email=fixture@example.com -c commit.gpgsign=false commit -q -m init
RIG_HEAD="$(git -C "$RIG" rev-parse HEAD)"
printf '# Demo: fixture\n\n**Start:** `/`\n' > "$TMP/cwd/walkthrough.md"
printf '# Demo: a report\n\n**Terminal:**\n\n## Steps\n\n1. **It prints**\n   `run true`\n' > "$TMP/cwd/terminal.md"

# The stubs these cases add. The engine lints clean and writes the clip it is
# told to; sandbox-exec keeps the profile and runs the engine; node says no
# server answers on a port and picks a free one.
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/engine" <<'ENGINE'
case "${1:-}" in
  lint) exit 0 ;;
  run) printf '%s\n' "$*" >> "$FAKE_DIR/engine.argv"
       o=""; p=""; for a in "$@"; do [ "$p" = "-o" ] && o="$a"; p="$a"; done
       printf 'clip' > "$o" ;;
esac
exit 0
ENGINE
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/sandbox-exec" <<'SBX'
printf '%s\n' "$2" > "$FAKE_DIR/profile"
shift 2
exec "$@"
SBX
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/node" <<'NODE'
[ $# -ge 3 ] || printf '50123'
exit 0
NODE
# gctk, at the city's build path, stands in for gctk rig serve: a start runs the
# serve command through the library's sandbox, which GCTK_SCRIPTS_DIR names, as
# the copy's leader does, keeps that profile, and reports the copy on 50200 as
# one it started, which --check then reports from the copy's checkout. lsof
# names the copy's process as the one listening there, working in that checkout.
mkdir -p "$CITY/.gc/services/gctk/bin"
{ printf '%s\n' "$SHEBANG"; cat; } > "$CITY/.gc/services/gctk/bin/gctk" <<'GCTK'
printf '%s (in %s)\n' "$*" "$(pwd)" >> "$FAKE_DIR/gctk.argv"
case "$*" in
  "rig serve --check")
    if [ "$(cat "$FAKE_DIR/copy-dir" 2>/dev/null)" = "$(pwd)" ]; then printf '{"state":"running","port":50200}\n'; exit 0; fi
    printf '{"state":"none"}\n'; exit 3 ;;
  "rig serve --command "*)
    ( . "$GCTK_SCRIPTS_DIR/demo-engine-lib.sh" && demo_engine_sandboxed 50200 "$(pwd)" true ) \
      || { printf '{"state":"failed","reason":"serve-exited"}\n'; exit 1; }
    cp "$FAKE_DIR/profile" "$FAKE_DIR/copy-profile"
    pwd > "$FAKE_DIR/copy-dir"
    printf '{"state":"running","port":50200,"started":true}\n' ;;
  "rig serve --stop") rm -f "$FAKE_DIR/copy-dir"; printf '{"state":"stopped"}\n' ;;
esac
exit 0
GCTK
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/lsof" <<'LSOF'
dir=$(cat "$FAKE_DIR/copy-dir" 2>/dev/null)
[ -n "$dir" ] || exit 1
case "$*" in
  *"-iTCP:50200 "*) echo 4321 ;;
  *"-p 4321 "*) printf 'p4321\nfcwd\nn%s\n' "$dir" ;;
  *) exit 1 ;;
esac
LSOF
chmod +x "$TMP/bin/engine" "$TMP/bin/sandbox-exec" "$TMP/bin/node" "$CITY/.gc/services/gctk/bin/gctk" "$TMP/bin/lsof"
# gc adds the rig list the sandbox denies by, here.
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
  "rig list")          printf '{"rigs":[{"name":"demo-rig","path":"%s"}]}\n' "$FAKE_RIG" ;;
  "bd update")         printf 'UPDATE\n' >> "$FAKE_LOG"; printf '%s\n' "$*" >> "$FAKE_DIR/gc.argv" ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG" ;;
esac
exit 0
GC

# pour <strict|plain> <serve_dir> <serve_cmd> <base_url> [rig path] prints
# "<rc>|<ordered verb log>", with no workspace left by an earlier case.
pour() {
  : > "$TMP/log"; : > "$TMP/gc.argv"; : > "$TMP/engine.argv"; : > "$TMP/decline.argv"; : > "$TMP/gctk.argv"
  rm -f "$TMP/profile" "$TMP/copy-profile" "$TMP/copy-dir"
  REVIEW_WORKSPACE_DIR="$WS" "$HERE/review-workspace.sh" remove --review-bead tk-req >/dev/null
  local rc=0
  ( cd "$TMP/cwd" && env -i PATH="$PATH" HOME="$TMP/home" TMPDIR="$TMP" GC_CITY_PATH="$CITY" GIT_CEILING_DIRECTORIES="$TMP" \
      REVIEW_WORKSPACE_DIR="$WS" SPRINTSHOW_BIN="$TMP/bin/engine" STUB_PACK="$TMP/pack" \
      FAKE_LOG="$TMP/log" FAKE_DIR="$TMP" FAKE_RIG="$RIG" FAKE_DECLINE_RC=0 \
      REQUEST_BEAD=tk-req SCRIPT_PATH="${POUR_SCRIPT:-$TMP/cwd/walkthrough.md}" OUT="$OUT" \
      SERVE_DIR="$2" SERVE_CMD="$3" BASE_URL="$4" RIG_PATH="${5-$RIG}" \
      SCRIPTS="$HERE" \
      bash "$TMP/app-$1.sh" ) > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

echo "# the sandbox refuses the rig's own checkout, which is why the app needs a worktree"
RC=0
( cd "$TMP/cwd" && env -i PATH="$PATH" HOME="$TMP/home" TMPDIR="$TMP" GC_CITY_PATH="$CITY" FAKE_RIG="$RIG" FAKE_DIR="$TMP" \
    SPRINTSHOW_BIN="$TMP/bin/engine" \
    "$HERE/rig-demo-capture.sh" --script "$TMP/cwd/walkthrough.md" --output "$OUT" --serve-dir "$RIG/site" ) > "$TMP/out" 2>&1 || RC=$?
eq "$RC" 1 "a capture that serves from the rig's checkout exits 1"
has "$(cat "$TMP/out")" "$RIG holds $RIG" "and names the checkout"

for MODE in strict plain; do
  echo "# $MODE shell: a serve_cmd runs as a copy from a detached worktree of the rig at its HEAD"
  eq "$(pour "$MODE" "" "npm run dev" "")" "0|UPDATE;" "$MODE: the capture passes the sandbox, and the clip is recorded"
  has "$(cat "$TMP/gctk.argv")" "rig serve --command npm run dev (in $WT)" "$MODE: gctk rig serve runs the command in the worktree"
  has "$(cat "$TMP/engine.argv")" "--base-url http://127.0.0.1:50200/" "$MODE: the engine records the copy"
  eq "$(git -C "$WT" rev-parse HEAD)" "$RIG_HEAD" "$MODE: the worktree is at the rig's HEAD"
  eq "$(git -C "$WT" symbolic-ref -q HEAD || echo detached)" "detached" "$MODE: and detached"
  has "$(cat "$TMP/copy-profile")" "(allow file-read-data file-write* (subpath \"$WT\"))" "$MODE: the copy's sandbox opens the worktree"
  case "$(cat "$TMP/copy-profile")" in
    *"(allow file-read-data file-write* (subpath \"$RIG\"))"*) bad "$MODE: the copy's sandbox keeps the rig's checkout shut" ;;
    *) ok "$MODE: the copy's sandbox keeps the rig's checkout shut" ;;
  esac
  has "$(cat "$TMP/gctk.argv")" "rig serve --stop (in $WT)" "$MODE: and the capture stops the copy"

  echo "# $MODE shell: a relative serve_dir resolves against that worktree"
  eq "$(pour "$MODE" "site" "" "")" "0|UPDATE;" "$MODE: the capture passes the sandbox"
  has "$(cat "$TMP/engine.argv")" "--serve-dir $WT/site" "$MODE: the engine serves the worktree's directory"

  echo "# $MODE shell: an absolute serve_dir is served as named"
  eq "$(pour "$MODE" "$TMP/cwd" "" "")" "0|UPDATE;" "$MODE: the capture passes the sandbox"
  has "$(cat "$TMP/engine.argv")" "--serve-dir $TMP/cwd" "$MODE: the engine serves the directory named"

  echo "# $MODE shell: a deployed preview needs no worktree"
  eq "$(pour "$MODE" "" "" "https://preview.example.com")" "0|UPDATE;" "$MODE: the capture passes the sandbox"
  has "$(cat "$TMP/engine.argv")" "--base-url https://preview.example.com" "$MODE: the engine drives the preview"
  [ ! -e "$WS/gc-review-tk-req" ] && ok "$MODE: and no workspace is made" || bad "$MODE: and no workspace is made"

  echo "# $MODE shell: a rig the city does not list declines with the capture's gate"
  eq "$(pour "$MODE" "site" "" "" "")" "1|UPDATE;DECLINE;" "$MODE: it notes the failure, declines, and exits 1"
  has "$(cat "$TMP/out")" "demo-rig is not in gc rig list" "$MODE: it names the rig"
  has "$(cat "$TMP/decline.argv")" "--subject tk-req --key rig-demo-capture-failed" "$MODE: the gate blocks the request bead"
  has "$(cat "$TMP/decline.argv")" "no worktree of demo-rig could be made" "$MODE: and says no worktree could be made"
  eq "$(cat "$TMP/engine.argv")" "" "$MODE: the engine never runs"

  echo "# $MODE shell: a pour that names no app target takes the app the rig's guide names, at the worktree's commit"
  eq "$(pour "$MODE" "" "" "")" "0|UPDATE;" "$MODE: the capture passes the sandbox, and the clip is recorded"
  has "$(cat "$TMP/engine.argv")" "--serve-dir $WT/site" "$MODE: the engine serves the directory the guide names, under the worktree"
  eq "$(git -C "$WT" rev-parse HEAD)" "$RIG_HEAD" "$MODE: which is at the rig's HEAD"
  eq "$(cat "$TMP/decline.argv")" "" "$MODE: and nothing declines"

  echo "# $MODE shell: a terminal script's pour names no app, and its shell starts in the worktree"
  eq "$(POUR_SCRIPT="$TMP/cwd/terminal.md" pour "$MODE" "" "" "")" "0|UPDATE;" "$MODE: the terminal capture passes the sandbox, and the clip is recorded"
  has "$(cat "$TMP/engine.argv")" "--cwd $WT" "$MODE: its shell starts in the worktree, since the guide names no directory"
  case "$(cat "$TMP/engine.argv")" in
    *--serve*|*--base-url*|*--port*) bad "$MODE: and the guide's app is not handed to a terminal script" "$(cat "$TMP/engine.argv")" ;;
    *) ok "$MODE: and the guide's app is not handed to a terminal script" ;;
  esac

  echo "# $MODE shell: a pour that names two app targets declines before anything is made"
  eq "$(pour "$MODE" "site" "" "https://preview.example.com")" "1|UPDATE;DECLINE;" "$MODE: it notes the malformed pour, declines, and exits 1"
  has "$(cat "$TMP/decline.argv")" "--subject tk-req --key rig-demo-ambiguous-app-target" "$MODE: the gate blocks the request bead under the app-target key"
  has "$(cat "$TMP/decline.argv")" "got 2 of serve_dir / serve_cmd / base_url" "$MODE: and counts the targets"
  eq "$(cat "$TMP/engine.argv")" "" "$MODE: the engine never runs"
  [ ! -e "$WS/gc-review-tk-req" ] && ok "$MODE: and no workspace is made" || bad "$MODE: and no workspace is made"

  echo "# $MODE shell: a checkout no worktree can be made from does the same"
  eq "$(pour "$MODE" "" "npm run dev" "" "$TMP/cwd")" "1|UPDATE;DECLINE;" "$MODE: it notes the failure, declines, and exits 1"
  has "$(cat "$TMP/out")" "HEAD is not a commit in $TMP/cwd" "$MODE: it names the checkout"
  has "$(cat "$TMP/decline.argv")" "no worktree of demo-rig could be made" "$MODE: and says no worktree could be made"
  eq "$(cat "$TMP/engine.argv")" "" "$MODE: the engine never runs"
done

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
