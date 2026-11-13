#!/usr/bin/env bash
# rig-demo-capture.test.sh — hermetic coverage of the rig-demo capture core.
# The script resolves a capture engine, provisions what the capture needs, lints
# a script, drives the capture, and checks the produced file. Most cases drive
# the engine through the script's own $SPRINTSHOW_BIN override seam with a stub.
# The ffmpeg cases instead put stub node, npx, npm and gc on PATH, so the engine
# resolves as written. demo-engine-lib.sh finds the engine and provisions its
# browser, and demo-engine-lib.test.sh checks that through this script. Every
# case runs under `env -i` with a PATH of only a coreutils symlink farm and those
# stubs — no host node, npx, gc, or sprintshow — so nothing touches the network
# or the real engine, and each case plants exactly the install result, lint
# result, run result, and output-file outcome it means to exercise. A
# sandbox-exec stub runs the engine it is handed, and a node stub answers the
# library's port pick and port check; demo-engine-lib.test.sh checks the
# sandbox itself.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/rig-demo-capture.sh"
[ -x "$SUT" ] || { echo "not found or not executable: $SUT" >&2; exit 2; }

FAIL=0
ok()    { if eval "$2"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAIL=1; fi; }
has()   { case "$2" in *"$1"*) printf 'ok   - %s\n' "$3" ;; *) printf 'FAIL - %s\n     wanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'FAIL - %s\n     unwanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; *) printf 'ok   - %s\n' "$3" ;; esac; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/rig-demo-capture.XXXXXX")"
ETMP="$(mktemp -d "${TMPDIR:-/tmp}/rig-demo-capture-engine.XXXXXX")"
trap 'rm -rf "$TMPD" "$ETMP"' EXIT

# Only the coreutils the script actually calls; env -i keeps everything else off
# PATH, so a path that should resolve the real engine instead finds nothing —
# which is why every happy case either sets $SPRINTSHOW_BIN or puts the
# resolution stubs on PATH.
FARM="$TMPD/farm"; mkdir -p "$FARM"
for c in bash sed tr head tail dirname mkdir mktemp rm tee wc cat env readlink awk git; do
  p="$(command -v "$c")" || { echo "test setup: required tool '$c' not found" >&2; exit 2; }
  ln -s "$p" "$FARM/$c"
done

# Fixtures: a script file, a serve dir, and an output path under TMPD.
SCRIPT="$TMPD/demo.md"; printf '# Demo: fixture\n\n**Start:** `/`\n' >"$SCRIPT"
SERVE_DIR="$TMPD/app"; mkdir -p "$SERVE_DIR"; printf '<!doctype html><title>x</title>\n' >"$SERVE_DIR/index.html"
OUT="$TMPD/out.mp4"

# Stub engine, driven through $SPRINTSHOW_BIN. `lint` exits $LINT_RC. `run` logs
# its argv to $RUNLOG, finds the -o path, and (unless told otherwise) writes
# bytes there; $RUN_RC fails the run, $RUN_NOFILE leaves no file, $RUN_EMPTY
# leaves an empty one — the three ways a capture can "succeed" yet deliver nothing.
# $RUN_REPORT prints the engine's closing report for a clip of that kind
# (narrated, silent), in the engine's words. $RUN_FAILED writes the clip, prints
# that report with its failed-proof line for that many steps, and exits 1, as
# the engine does when a step of a captured clip fails its proof. $RUN_LATE_RC
# writes the clip and then exits with that code without any report. A run also
# logs the PORT its environment carries, which a --serve command inherits, to
# $RUNLOG.port.
STUB="$TMPD/sprintshow-stub"
cat >"$STUB" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "lint" ]; then exit "${LINT_RC:-0}"; fi
if [ "${1:-}" = "run" ]; then
  printf '%s\n' "$*" >>"${RUNLOG:?}"
  printf '%s\n' "${PORT-unset}" >"$RUNLOG.port"
  o=""; prev=""
  for a in "$@"; do [ "$prev" = "-o" ] && o="$a"; prev="$a"; done
  [ "${RUN_RC:-0}" != 0 ] && exit "${RUN_RC}"
  if [ -n "${RUN_FAILED:-}" ]; then
    [ -n "${RUN_NOFILE:-}" ] || printf 'mp4-bytes\n' >"$o"
    printf 'step 1/2: Open the board\n  ✓ proof held\nstep 2/2: Expand the row\n  ✗ _Prove:_ did not hold: `visible .row`\n\n'
    printf '✅ %s demo → %s\n' "${RUN_REPORT:-narrated}" "$o"
    printf '   ⚠️  %s step(s) failed their proof — video and frames kept: .captures/fixture-123\n' "$RUN_FAILED"
    exit 1
  fi
  [ -n "${RUN_NOFILE:-}" ] && exit 0
  if [ -n "${RUN_EMPTY:-}" ]; then : >"$o"; else printf 'mp4-bytes\n' >"$o"; fi
  [ "${RUN_LATE_RC:-0}" != 0 ] && exit "${RUN_LATE_RC}"
  [ -n "${RUN_REPORT:-}" ] && printf '\n✅ %s demo → %s\n' "$RUN_REPORT" "$o"
  exit 0
fi
exit 0
STUB
chmod +x "$STUB"

# The sandbox and the port pick. sandbox-exec logs the command it runs to
# $SANDBOX_LOG, then runs it. node answers the free-port pick with 50123 and
# says no server answers on a port it is asked about.
SBX="$TMPD/sandbox-bin"; mkdir -p "$SBX"
cat >"$SBX/sandbox-exec" <<'SBXSTUB'
#!/usr/bin/env bash
[ "${1:-}" = "-p" ] && [ $# -ge 3 ] || { echo "sandbox-exec stub: expected -p <profile> <command...>" >&2; exit 64; }
shift 2
printf 'sandbox-exec %s\n' "$*" >>"${SANDBOX_LOG:-/dev/null}"
exec "$@"
SBXSTUB
cat >"$SBX/node" <<'NODE'
#!/usr/bin/env bash
if [ "${1:-}" = "-e" ] && [ $# -ge 3 ]; then exit 0; fi
if [ "${1:-}" = "-e" ]; then printf 50123; exit 0; fi
echo "node stub: unexpected call: $*" >&2; exit 97
NODE
chmod +x "$SBX/sandbox-exec" "$SBX/node"
SANDBOX_LOG="$TMPD/sandbox.log"

RUNLOG="$TMPD/run.log"
# run [KEY=VAL ...] -- <sut args...>; per-call knobs, combined stdout+stderr.
# $RUN_PATH replaces the sandbox directory on PATH for one call.
run() {
  local lint_rc=0 run_rc=0 nofile="" empty="" report="" failed="" late_rc=0
  while [ $# -gt 0 ]; do
    case "$1" in
      LINT_RC=*)   lint_rc="${1#*=}" ;;
      RUN_RC=*)    run_rc="${1#*=}" ;;
      RUN_NOFILE=*) nofile="${1#*=}" ;;
      RUN_EMPTY=*) empty="${1#*=}" ;;
      RUN_REPORT=*) report="${1#*=}" ;;
      RUN_FAILED=*) failed="${1#*=}" ;;
      RUN_LATE_RC=*) late_rc="${1#*=}" ;;
      --) shift; break ;;
      *) break ;;
    esac
    shift
  done
  : >"$RUNLOG"; : >"$SANDBOX_LOG"; rm -f "$OUT" "$RUNLOG.port"
  ( cd "$TMPD" && env -i PATH="${RUN_PATH-$SBX}:$FARM" RUNLOG="$RUNLOG" SPRINTSHOW_BIN="$STUB" SANDBOX_LOG="$SANDBOX_LOG" GIT_CEILING_DIRECTORIES="$TMPD" \
      LINT_RC="$lint_rc" RUN_RC="$run_rc" RUN_NOFILE="$nofile" RUN_EMPTY="$empty" \
      RUN_REPORT="$report" RUN_FAILED="$failed" RUN_LATE_RC="$late_rc" \
      bash "$SUT" "$@" 2>&1 )
}

echo "# happy path: lint + capture + a non-empty file -> exit 0"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "capture exits 0" "[ '$rc' = 0 ]"
ok "output file exists and is non-empty" "[ -s '$OUT' ]"
RL="$(cat "$RUNLOG")"
has "run $SCRIPT" "$RL" "it runs the given script"
has "--mode walkthrough" "$RL" "walkthrough is the default mode"
has "-o $OUT" "$RL" "the output path is forwarded"
has "--serve-dir $SERVE_DIR" "$RL" "the serve-dir target is forwarded"
has "captured $OUT" "$out" "it reports the captured file"
has "sandbox-exec $STUB lint $SCRIPT" "$(cat "$SANDBOX_LOG")" "the stand-in engine lints inside the sandbox"
has "sandbox-exec $STUB run $SCRIPT" "$(cat "$SANDBOX_LOG")" "and captures inside it"
has "--port 50123" "$RL" "a --serve-dir is given the free port the sandbox opens"

echo "# a relative --serve-dir resolves against --cwd, and --cwd goes no further"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir app --cwd "$TMPD")"; rc=$?
ok "a relative serve-dir with a cwd exits 0" "[ '$rc' = 0 ]"
RL="$(cat "$RUNLOG")"
has "--serve-dir $SERVE_DIR" "$RL" "it is served from the directory --cwd names"
hasnt "--cwd" "$RL" "and the engine, which spawns no command, is given no --cwd"

echo "# an empty --cwd -> exit 2, so an app never runs from the caller's directory instead"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve 'npm run dev' --cwd "")"; rc=$?
ok "an empty cwd exits 2" "[ '$rc' = 2 ]"
has "--cwd needs a value" "$out" "it says --cwd needs a value"
ok "nothing is linted or captured" "[ ! -s '$RUNLOG' ] && [ ! -s '$SANDBOX_LOG' ] && [ ! -e '$OUT' ]"

echo "# no sandbox -> exit 1, and the engine never runs"
out="$(RUN_PATH="" run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a host without sandbox-exec exits 1" "[ '$rc' = 1 ]"
has "sandbox-exec not found" "$out" "it says there is no sandbox"
ok "nothing is linted or captured" "[ ! -s '$RUNLOG' ] && [ ! -s '$SANDBOX_LOG' ] && [ ! -e '$OUT' ]"

echo "# --mode proof is forwarded"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR" --mode proof)"; rc=$?
ok "proof mode exits 0" "[ '$rc' = 0 ]"
has "--mode proof" "$(cat "$RUNLOG")" "proof mode is forwarded"

echo "# --base-url and --serve are each forwarded; --no-narrate too; a --base-url on this host is refused"
out="$(run -- --script "$SCRIPT" --output "$OUT" --base-url https://preview.example.com)"; rc=$?
ok "base-url exits 0" "[ '$rc' = 0 ]"
has "--base-url https://preview.example.com" "$(cat "$RUNLOG")" "base-url is forwarded"
out="$(run -- --script "$SCRIPT" --output "$OUT" --base-url http://localhost:3000)"; rc=$?
ok "a base-url on this host exits 1" "[ '$rc' = 1 ]"
has "names a server on this host" "$out" "it says a server here runs outside the sandbox"
ok "nothing is captured" "[ ! -s '$RUNLOG' ] && [ ! -e '$OUT' ]"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve 'npm run dev' --port 4321 --no-narrate --cwd "$SERVE_DIR")"; rc=$?
ok "serve exits 0" "[ '$rc' = 0 ]"
RL="$(cat "$RUNLOG")"
has "--serve npm run dev" "$RL" "serve command is forwarded"
has "--port 4321" "$RL" "port is forwarded"
has "--no-narrate" "$RL" "no-narrate is forwarded"

echo "# a --serve command gets its port as PORT, and --port 0 picks a free one, as a screenshot's command does"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve 'npm run dev' --port 4321 --cwd "$SERVE_DIR")"; rc=$?
P="$(cat "$RUNLOG.port")"
ok "a --serve with a --port exits 0" "[ '$rc' = 0 ]"
ok "the command's environment carries the port as PORT (got $P)" "[ '$P' = 4321 ]"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve 'npm run dev' --port 0 --cwd "$SERVE_DIR")"; rc=$?
P="$(cat "$RUNLOG.port")"
ok "a --serve with --port 0 exits 0" "[ '$rc' = 0 ]"
has "--port 50123" "$(cat "$RUNLOG")" "--port 0 becomes the free port the library picks"
ok "and the command gets that port as PORT (got $P)" "[ '$P' = 50123 ]"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve 'npm run dev' --cwd "$SERVE_DIR")"; rc=$?
P="$(cat "$RUNLOG.port")"
ok "a --serve with no --port gets no PORT (got $P)" "[ '$P' = unset ]"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR" --port 4321)"; rc=$?
P="$(cat "$RUNLOG.port")"
ok "a --serve-dir, which spawns no command, sets no PORT (got $P)" "[ '$P' = unset ]"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR" --port 0)"; rc=$?
ok "--port 0 with a --serve-dir exits 2" "[ '$rc' = 2 ]"
has "give it with --serve only" "$out" "it says --port 0 picks a port for a command"
ok "nothing is captured" "[ ! -s '$RUNLOG' ] && [ ! -e '$OUT' ]"

# A terminal script declares **Terminal:** among its head lines and drives a
# shell in the engine's own terminal.
TSCRIPT="$TMPD/terminal.md"
printf '# Demo: a report\n\n**Terminal:** 100x30\n\n## Steps\n\n1. **The report prints**\n   `run true`\n' >"$TSCRIPT"
echo "# a terminal script records with no app target, linted and captured in the sandbox, and its shell starts in --cwd"
out="$(run -- --script "$TSCRIPT" --output "$OUT" --cwd "$SERVE_DIR")"; rc=$?
ok "a terminal script with no app target exits 0" "[ '$rc' = 0 ]"
ok "the clip exists and is non-empty" "[ -s '$OUT' ]"
has "captured $OUT" "$out" "it reports the captured clip"
RL="$(cat "$RUNLOG")"
has "run $TSCRIPT" "$RL" "it records the terminal script"
has "--cwd $SERVE_DIR" "$RL" "its shell starts in --cwd"
for f in --serve-dir --serve --base-url --port; do hasnt "$f " "$RL" "the engine is given no $f"; done
has "sandbox-exec $STUB lint $TSCRIPT" "$(cat "$SANDBOX_LOG")" "it lints the terminal script inside the sandbox"
has "sandbox-exec $STUB run $TSCRIPT" "$(cat "$SANDBOX_LOG")" "and records it inside the sandbox"
out="$(run -- --script "$TSCRIPT" --output "$OUT")"; rc=$?
ok "a terminal script with no --cwd exits 0" "[ '$rc' = 0 ]"
hasnt "--cwd" "$(cat "$RUNLOG")" "its shell starts where the capture runs"
out="$(run LINT_RC=1 -- --script "$TSCRIPT" --output "$OUT")"; rc=$?
ok "a terminal script the linter rejects exits 1" "[ '$rc' = 1 ]"
ok "and nothing is recorded" "[ ! -s '$RUNLOG' ] && [ ! -e '$OUT' ]"
out="$(run RUN_NOFILE=1 -- --script "$TSCRIPT" --output "$OUT")"; rc=$?
ok "a terminal capture that leaves no clip exits 1" "[ '$rc' = 1 ]"
has "does not exist" "$out" "it catches the silent non-delivery"
out="$(run RUN_FAILED=1 -- --script "$TSCRIPT" --output "$OUT")"; rc=$?
ok "a terminal clip with a failed proof exits 3" "[ '$rc' = 3 ]"

echo "# a terminal script takes no app target and no --port -> exit 2, before anything is linted"
for args in "--serve-dir $SERVE_DIR" "--serve true" "--base-url https://preview.example.com" "--port 4321"; do
  # shellcheck disable=SC2086 # each case is a flag and a value without blanks
  out="$(run -- --script "$TSCRIPT" --output "$OUT" $args)"; rc=$?
  ok "a terminal script with ${args%% *} exits 2" "[ '$rc' = 2 ]"
  has "is a terminal script, which runs in the engine's own terminal" "$out" "it says a terminal script takes no ${args%% *}"
  ok "nothing is linted or captured" "[ ! -s '$RUNLOG' ] && [ ! -s '$SANDBOX_LOG' ] && [ ! -e '$OUT' ]"
done

echo "# the engine's rule for a terminal script: **Terminal:** in any case, among the lines above the first ## heading"
LSCRIPT="$TMPD/lower.md"
printf '# Demo: lower\n\n   **terminal:**\n\n## Steps\n\n1. **The report prints**\n   `run true`\n' >"$LSCRIPT"
out="$(run -- --script "$LSCRIPT" --output "$OUT")"; rc=$?
ok "an indented, lowercase **terminal:** declares a terminal script" "[ '$rc' = 0 ]"
PSCRIPT="$TMPD/late.md"
printf '# Demo: late\n\n**Start:** `/`\n\n## Notes\n\n**Terminal:** 80x24\n\n## Steps\n\n1. **It opens**\n' >"$PSCRIPT"
out="$(run -- --script "$PSCRIPT" --output "$OUT")"; rc=$?
ok "a **Terminal:** line below a ## heading leaves a page script, which needs its app (exit 2)" "[ '$rc' = 2 ]"
has "exactly one of --serve-dir" "$out" "it asks for the page's app target"

# commit_all <worktree>: a repository whose one commit holds what the worktree
# holds, so a guide is read at that commit.
commit_all() {
  git -C "$1" init -q && git -C "$1" add -A \
    && git -C "$1" -c user.name=fixture -c user.email=fixture@example.com -c commit.gpgsign=false commit -q -m fixture
}
# guide <worktree> <lines>: a worktree whose committed demo guide holds the
# section "Bring the app up" with those lines, between two other sections. The
# worktrees sit under the physical path git reports for them.
GBASE="$(cd "$TMPD" && pwd -P)"
guide() {
  mkdir -p "$1/docs"
  printf '# Demo guide\n\n## Surfaces\n\nA page.\n\n## Bring the app up\n\n%s\n\n## Sign-in\n\n**Serve:** `not-the-app`\n' "$2" >"$1/docs/review-demo.md"
  commit_all "$1"
}
GW="$GBASE/rig-wt"; mkdir -p "$GW/web"
guide "$GW" '**Serve:** `npm run dev`
**Cwd:** `web`
**Port:** `4321`'
echo "# --guide takes the app the rig's demo guide names: its command, the directory it runs in, and its port"
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GW")"; rc=$?
ok "a page script with --guide exits 0" "[ '$rc' = 0 ]"
RL="$(cat "$RUNLOG")"
has "--serve npm run dev" "$RL" "the guide's command is the app"
has "--cwd $GW/web" "$RL" "it runs in the guide's directory, under the worktree"
has "--port 4321" "$RL" "on the guide's port"
hasnt "not-the-app" "$RL" "a line in another section of the guide names nothing"
P="$(cat "$RUNLOG.port")"
ok "the command gets the guide's port as PORT (got $P)" "[ '$P' = 4321 ]"
has "the app is the one docs/review-demo.md at " "$out" "it says the app came from the guide at a commit"
has " in $GW names" "$out" "in the worktree --guide named"
printf '\n**Port:** `9999`\n' >>"$GW/docs/review-demo.md"
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GW")"; rc=$?
ok "a guide edited in the worktree and not committed still captures" "[ '$rc' = 0 ]"
has "--port 4321" "$(cat "$RUNLOG")" "the guide is read at the commit, not from the working tree"
git -C "$GW" checkout -q -- docs/review-demo.md

GS="$GBASE/rig-static"; mkdir -p "$GS/site"
guide "$GS" '**Serve dir:** `site`'
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GS")"; rc=$?
ok "a guide's static directory exits 0" "[ '$rc' = 0 ]"
has "--serve-dir $GS/site" "$(cat "$RUNLOG")" "the engine serves the guide's directory, under the worktree"
has "--port 50123" "$(cat "$RUNLOG")" "on a free port, as any --serve-dir is"

GU="$GBASE/rig-preview"; guide "$GU" '**Base URL:** `https://preview.example.com`'
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GU")"; rc=$?
ok "a guide's running endpoint exits 0" "[ '$rc' = 0 ]"
has "--base-url https://preview.example.com" "$(cat "$RUNLOG")" "the engine drives the endpoint the guide names"

GZ="$GBASE/rig-port0"; guide "$GZ" '**Serve:** `go run ./cmd/fixture`
**Port:** `0`'
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GZ")"; rc=$?
P="$(cat "$RUNLOG.port")"
ok "a guide whose port is 0 exits 0" "[ '$rc' = 0 ]"
has "--port 50123" "$(cat "$RUNLOG")" "its command gets a free port"
ok "as PORT (got $P)" "[ '$P' = 50123 ]"
has "--cwd $GZ" "$(cat "$RUNLOG")" "and a guide that names no directory runs the command in the worktree"

echo "# a guide that cannot name the app refuses the capture -> exit 2, with nothing captured"
GN="$GBASE/rig-none"; mkdir -p "$GN"; printf 'x\n' >"$GN/README"; commit_all "$GN"
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GN")"; rc=$?
ok "a commit that carries no guide exits 2" "[ '$rc' = 2 ]"
has "the commit checked out in $GN carries no docs/review-demo.md" "$out" "it says the commit carries no guide"
ok "nothing is captured" "[ ! -s '$RUNLOG' ] && [ ! -e '$OUT' ]"
GG="$GBASE/rig-uncommitted"; mkdir -p "$GG/docs"
printf '## Bring the app up\n\n**Serve dir:** `site`\n' >"$GG/docs/review-demo.md"
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GG")"; rc=$?
ok "a directory in no git worktree exits 2" "[ '$rc' = 2 ]"
has "is in no git worktree with a commit checked out" "$out" "it says no commit holds a guide there"
ok "nothing is captured" "[ ! -s '$RUNLOG' ] && [ ! -e '$OUT' ]"
GE="$GBASE/rig-noapp"; guide "$GE" 'The app is brought up apart from the capture.'
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GE")"; rc=$?
ok "a guide whose section names no app exits 2" "[ '$rc' = 2 ]"
has "in $GE names no app" "$out" "it says the guide names no app"
GT="$GBASE/rig-two"; guide "$GT" '**Serve:** `npm run dev`
**Base URL:** `https://preview.example.com`'
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GT")"; rc=$?
ok "a guide that names two apps exits 2" "[ '$rc' = 2 ]"
has "names more than one of **Serve:**, **Serve dir:** and **Base URL:**" "$out" "it says the guide names more than one app"
ok "nothing is captured" "[ ! -s '$RUNLOG' ] && [ ! -e '$OUT' ]"
GB="$GBASE/rig-bare"; guide "$GB" '**Serve:** npm run dev'
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GB")"; rc=$?
ok "a guide line whose value is not one code span exits 2" "[ '$rc' = 2 ]"
has "write **Serve:** with its value in one code span" "$out" "it says how to write the line"
out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$TMPD/nowhere")"; rc=$?
ok "a --guide that is not a directory exits 1" "[ '$rc' = 1 ]"
has "is not a directory" "$out" "it says so"

echo "# --guide names the whole app, so it takes no app target, --cwd or --port beside it -> exit 2"
for args in "--serve-dir $SERVE_DIR" "--base-url https://preview.example.com" "--cwd $SERVE_DIR" "--port 4321"; do
  # shellcheck disable=SC2086 # each case is a flag and a value without blanks
  out="$(run -- --script "$SCRIPT" --output "$OUT" --guide "$GW" $args)"; rc=$?
  ok "--guide with ${args%% *} exits 2" "[ '$rc' = 2 ]"
  has "--guide names the whole app" "$out" "it says --guide names the whole app"
  ok "nothing is linted or captured" "[ ! -s '$RUNLOG' ] && [ ! -s '$SANDBOX_LOG' ] && [ ! -e '$OUT' ]"
done

echo "# a terminal script under --guide starts its shell in the guide's directory, or in the worktree, and takes no app"
out="$(run -- --script "$TSCRIPT" --output "$OUT" --guide "$GW")"; rc=$?
ok "a terminal script with --guide exits 0" "[ '$rc' = 0 ]"
RL="$(cat "$RUNLOG")"
has "--cwd $GW/web" "$RL" "its shell starts in the guide's directory"
for f in --serve --port; do hasnt "$f " "$RL" "the guide's app gives the engine no $f"; done
out="$(run -- --script "$TSCRIPT" --output "$OUT" --guide "$GN")"; rc=$?
ok "a terminal script under a worktree that keeps no guide exits 0" "[ '$rc' = 0 ]"
has "--cwd $GN" "$(cat "$RUNLOG")" "its shell starts in the worktree"

echo "# fail closed: lint rejects the script -> exit 1, no capture"
out="$(run LINT_RC=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "lint failure exits 1" "[ '$rc' = 1 ]"
has "failed lint" "$out" "it says the script failed lint"
hasnt "run $SCRIPT" "$(cat "$RUNLOG")" "no capture runs after a lint failure"

echo "# fail closed: the engine errors -> exit 1"
out="$(run RUN_RC=3 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "capture error exits 1" "[ '$rc' = 1 ]"
has "capture failed" "$out" "it reports the capture failure"

echo "# fail closed: the engine succeeds but produces NO file -> exit 1"
out="$(run RUN_NOFILE=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "missing output exits 1" "[ '$rc' = 1 ]"
has "does not exist" "$out" "it catches the silent non-delivery"

echo "# fail closed: the engine produces an EMPTY file -> exit 1"
out="$(run RUN_EMPTY=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "empty output exits 1" "[ '$rc' = 1 ]"
has "is empty" "$out" "it catches an empty clip"

echo "# the last line says whether the clip is narrated or silent, from the engine's report"
out="$(run RUN_REPORT=narrated -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a narrated capture exits 0" "[ '$rc' = 0 ]"
has "captured $OUT (narrated," "$out" "it reports a narrated clip"
out="$(run RUN_REPORT=silent -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a silent capture exits 0" "[ '$rc' = 0 ]"
has "captured $OUT (silent," "$out" "it reports a silent clip"
out="$(run 'RUN_REPORT=narrated + music bed' -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
has "captured $OUT (narrated," "$out" "a music bed does not hide the narration"

echo "# a clip in which a step failed its proof -> exit 3, naming the clip and the engine's kept working files"
# env -i drops PWD, so the script's pwd is the physical path, which differs from
# the logical one where TMPDIR runs through a symlink (macOS /var).
TMPD_PWD="$(cd "$TMPD" && pwd -P)"
out="$(run RUN_FAILED=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a failed step proof exits 3" "[ '$rc' = 3 ]"
ok "the clip stays on disk" "[ -s '$OUT' ]"
has "1 step(s) failed their proof" "$out" "it counts the failed steps"
has "captured $OUT (narrated)" "$out" "it names the clip and its narration"
has "kept its working files in $TMPD_PWD/.captures/fixture-123" "$out" "it names the kept working files by absolute path"
hasnt "capture failed" "$out" "a clip with a failed step is not reported as a failed capture"

echo "# fail closed: a failed-proof report with no clip on disk -> exit 1"
out="$(run RUN_FAILED=2 RUN_NOFILE=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a failed-proof report without a clip exits 1" "[ '$rc' = 1 ]"
has "capture failed" "$out" "it reports the capture failure"

echo "# fail closed: the engine writes the file, then errors with no report -> exit 1"
out="$(run RUN_LATE_RC=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "an error after the file was written exits 1" "[ '$rc' = 1 ]"
has "capture failed (sprintshow run exited 1)" "$out" "a file without the engine's report is not a captured clip"

echo "# usage errors (exit 2)"
out="$(run -- --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "missing --script exits 2" "[ '$rc' = 2 ]"
out="$(run -- --script "$SCRIPT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "missing --output exits 2" "[ '$rc' = 2 ]"
out="$(run -- --script "$SCRIPT" --output "$OUT")"; rc=$?
ok "no app target exits 2" "[ '$rc' = 2 ]"
has "exactly one of --serve-dir" "$out" "it names the app-target requirement"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR" --base-url http://x)"; rc=$?
ok "two app targets exits 2" "[ '$rc' = 2 ]"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR" --mode fast)"; rc=$?
ok "bad --mode exits 2" "[ '$rc' = 2 ]"

echo "# a --script that does not exist -> exit 1"
out="$(run -- --script "$TMPD/nope.md" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "missing script file exits 1" "[ '$rc' = 1 ]"
has "does not exist" "$out" "it says the script is missing"

# ffmpeg, driven without $SPRINTSHOW_BIN. A clip is assembled with ffmpeg, so a
# checkout fetches its ffmpeg-static binary when the host has none. Stubs on
# PATH stand in for node, npx, npm and gc, and a host ffmpeg is on PATH only for
# a case that names HOST_FFMPEG=1. jq is the real one, because the library reads
# the rig list and the engine's package.json with it. npm, npx and node log every
# call to $CALLLOG in order, and node and npx hand the engine's CLI, its lint and
# its run, to the engine stub. The fetch prints npm's header line to the stdout
# it was given, as npm does, and $FFMPEG_RC fails it.
JQ="$(command -v jq)" || { echo "test setup: required tool 'jq' not found" >&2; exit 2; }
RBIN="$TMPD/resolve-bin"; mkdir -p "$RBIN"
ln -s "$JQ" "$RBIN/jq"
cat >"$RBIN/node" <<'NODE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo v24.0.0; exit 0; fi
if [ "${1:-}" = "-e" ]; then exec "${SBX:?}/node" "$@"; fi
printf 'node %s\n' "$*" >>"${CALLLOG:?}"
case "${1:-}" in */src/cli.ts) shift; exec "${ENGINE_STUB:?}" "$@" ;; esac
echo "node stub: unexpected call: $*" >&2; exit 97
NODE
HOSTBIN="$TMPD/host-bin"; mkdir -p "$HOSTBIN"
printf '#!/usr/bin/env bash\nexit 0\n' >"$HOSTBIN/ffmpeg"
cat >"$RBIN/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1 $2" = "rig list" ] && [ -n "${SS_RIG:-}" ]; then printf '{"rigs":[{"name":"sprintshow","path":"%s"}]}\n' "$SS_RIG"; fi
exit 0
GC
cat >"$RBIN/npm" <<'NPM'
#!/usr/bin/env bash
printf 'npm %s (in %s)\n' "$*" "$PWD" >>"${CALLLOG:?}"
if [ "$*" = "run provision:ffmpeg" ]; then
  printf '> node node_modules/ffmpeg-static/install.js\n'
  if [ "${FFMPEG_RC:-0}" != 0 ]; then printf 'ffmpeg-static: download failed\n'; exit "$FFMPEG_RC"; fi
fi
exit 0
NPM
cat >"$RBIN/npx" <<'NPX'
#!/usr/bin/env bash
printf 'npx %s\n' "$*" >>"${CALLLOG:?}"
case "$1 $2" in
  "--yes @zookanalytics/sprintshow") shift 2; exec "${ENGINE_STUB:?}" "$@" ;;
  "--yes --package=@zookanalytics/sprintshow") exit 0 ;;
esac
echo "npx stub: unexpected call: $*" >&2; exit 97
NPX
chmod +x "$RBIN"/node "$HOSTBIN"/ffmpeg "$RBIN"/gc "$RBIN"/npm "$RBIN"/npx
# A local engine checkout with its deps installed. Its path is the one cd
# reports, since npm's log line records the directory it ran in as $PWD. It is
# a rig checkout, so it lies outside $TMPD, which holds the clip, because the
# sandbox refuses a run that writes to a directory holding one.
ENGINE="$(cd "$ETMP" && pwd)/sprintshow"; mkdir -p "$ENGINE/node_modules"
printf '{"name":"@zookanalytics/sprintshow"}\n' >"$ENGINE/package.json"
CALLLOG="$TMPD/calls.log"
# resolve_run [VAR=VAL ...] -- <sut args...>; the stubs above, never $SPRINTSHOW_BIN.
# Stderr joins stdout, unless STDERR_FILE=<path> keeps it apart in that file.
resolve_run() {
  local envs=() path="$RBIN:$SBX:$FARM" errf=""
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    case "$1" in
      HOST_FFMPEG=1) path="$HOSTBIN:$path" ;;
      STDERR_FILE=*) errf="${1#STDERR_FILE=}" ;;
      *) envs+=("$1") ;;
    esac
    shift
  done
  [ $# -gt 0 ] && shift
  : >"$RUNLOG"; : >"$CALLLOG"; rm -f "$OUT"
  ( cd "$TMPD" || exit 1
    if [ -n "$errf" ]; then exec 2>"$errf"; else exec 2>&1; fi
    env -i PATH="$path" RUNLOG="$RUNLOG" CALLLOG="$CALLLOG" ENGINE_STUB="$STUB" SBX="$SBX" \
      ${envs[@]+"${envs[@]}"} bash "$SUT" "$@" )
}
# line_of <substring> — the first $CALLLOG line holding it, or 0 when none does.
line_of() { awk -v s="$1" 'index($0, s) { print NR; found = 1; exit } END { if (!found) print 0 }' "$CALLLOG"; }

echo "# a checkout on a host with no ffmpeg fetches ffmpeg-static, after the browser and before the engine runs"
out="$(resolve_run SS_RIG="$ENGINE" -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "capture exits 0" "[ '$rc' = 0 ]"
has "npm run provision:ffmpeg (in $ENGINE)" "$(cat "$CALLLOG")" "it fetches ffmpeg-static in the checkout"
B=$(line_of "provision:browser"); F=$(line_of "provision:ffmpeg"); L=$(line_of "lint $SCRIPT")
ok "ffmpeg is fetched after the browser is provisioned and before the engine runs (browser line $B, ffmpeg line $F, lint line $L)" "[ '$B' -gt 0 ] && [ '$F' -gt '$B' ] && [ '$L' -gt '$F' ]"
has "run $SCRIPT" "$(cat "$RUNLOG")" "the capture runs after the fetch"

echo "# the fetch writes to stderr, so stdout carries only the capture's report"
out="$(resolve_run SS_RIG="$ENGINE" STDERR_FILE="$TMPD/stderr" -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a capture that fetched ffmpeg exits 0" "[ '$rc' = 0 ]"
has "ffmpeg-static/install.js" "$(cat "$TMPD/stderr")" "the fetch's output reaches stderr"
hasnt "ffmpeg-static/install.js" "$out" "the fetch writes nothing to stdout"
has "captured $OUT" "$(printf '%s\n' "$out" | tail -n 1)" "the last line on stdout is the capture's report"

echo "# a host ffmpeg, or a checkout's ffmpeg-static already fetched, is used as it is"
out="$(resolve_run SS_RIG="$ENGINE" HOST_FFMPEG=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a capture with a host ffmpeg exits 0" "[ '$rc' = 0 ]"
hasnt "provision:ffmpeg" "$(cat "$CALLLOG")" "a host ffmpeg is not fetched again"
mkdir -p "$ENGINE/node_modules/ffmpeg-static"
printf '#!/usr/bin/env bash\nexit 0\n' >"$ENGINE/node_modules/ffmpeg-static/ffmpeg"; chmod +x "$ENGINE/node_modules/ffmpeg-static/ffmpeg"
out="$(resolve_run SS_RIG="$ENGINE" -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
rm -rf "$ENGINE/node_modules/ffmpeg-static"
ok "a capture with ffmpeg-static fetched exits 0" "[ '$rc' = 0 ]"
hasnt "provision:ffmpeg" "$(cat "$CALLLOG")" "a fetched ffmpeg-static is not fetched again"

echo "# the fetch fails -> exit 1 with its message, no capture"
out="$(resolve_run SS_RIG="$ENGINE" FFMPEG_RC=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a failed fetch exits 1" "[ '$rc' = 1 ]"
has "could not provision ffmpeg (no host ffmpeg and ffmpeg-static fetch failed)" "$out" "it says ffmpeg could not be provisioned"
has "ffmpeg-static: download failed" "$out" "the fetch's own message reaches the caller"
hasnt "lint $SCRIPT" "$(cat "$CALLLOG")" "nothing is linted after a failed fetch"
ok "nothing is captured after a failed fetch" "[ ! -s '$RUNLOG' ] && [ ! -e '$OUT' ]"

echo "# the published package fetches no ffmpeg"
out="$(resolve_run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a capture on the published package exits 0" "[ '$rc' = 0 ]"
hasnt "provision:ffmpeg" "$(cat "$CALLLOG")" "nothing is fetched for a checkout it does not have"

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all rig-demo-capture assertions passed"; else echo "FAIL: rig-demo-capture had failures"; fi
exit "$FAIL"
