#!/usr/bin/env bash
# demo-deliver.test.sh — hermetic coverage of the demo→PR delivery primitive.
# The script probes gh, resolves an origin, and attaches a file, so the test
# controls all three: it runs the script under `env -i` with a PATH of a stub gh
# and gc plus a symlink farm of the coreutils it calls, never the host — so the
# host's real gh (which would make a live network call and cannot be made "not
# found") is never reached, and each case plants exactly the version, origin, PR
# binding, and gh outcome it means to exercise.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/demo-deliver.sh"
[ -x "$SUT" ] || { echo "not found or not executable: $SUT" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required for this test" >&2; exit 2; }

FAIL=0
ok()    { if eval "$2"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAIL=1; fi; }
has()   { case "$2" in *"$1"*) printf 'ok   - %s\n' "$3" ;; *) printf 'FAIL - %s\n     wanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'FAIL - %s\n     unwanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; *) printf 'ok   - %s\n' "$3" ;; esac; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/demo-deliver.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
HOMEDIR="$TMPD/home"; mkdir -p "$HOMEDIR"

# A symlink farm of just the coreutils the script calls, and a stub dir ahead of
# it. env -i means only these are on PATH — no host gh, gc, node, or anything else.
FARM="$TMPD/farm"; mkdir -p "$FARM"
for c in bash sed tr head tail grep git jq; do
  p="$(command -v "$c")" || { echo "test setup: required tool '$c' not found" >&2; exit 2; }
  ln -s "$p" "$FARM/$c"
done
STUBS="$TMPD/stubs"; mkdir -p "$STUBS"

# A git repo whose origin fabricates the repository we own.
REPO="$TMPD/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" remote add origin https://github.com/acme/widgets.git

# A produced artifact with bytes, and an empty one.
MP4="$TMPD/demo.mp4"; printf 'not really an mp4 but non-empty\n' >"$MP4"
EMPTY="$TMPD/empty.mp4"; : >"$EMPTY"

# gh stub: `gh --version` prints $GH_STUB_VER; `gh pr comment ...` logs its argv
# to $GHLOG and prints a comment URL, or fails when $GH_STUB_FAIL is set. Every
# other call is a silent success.
cat >"$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "gh version ${GH_STUB_VER:-2.101.0} (2026-01-01)"
  exit 0
fi
printf '%s\n' "$*" >>"${GHLOG:?}"
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "comment" ]; then
  if [ -n "${GH_STUB_FAIL:-}" ]; then echo "stub gh: upload failed" >&2; exit 1; fi
  echo "https://github.com/acme/widgets/pull/stub#issuecomment-1"
  exit 0
fi
exit 0
STUB
chmod +x "$STUBS/gh"

# gc stub: `gc rig list --json` maps $RIG_PREFIX to $RIG_PATH (empty => no rigs);
# `gc bd show` returns a subject carrying $STUB_PR_NUMBER / $STUB_PR_URL. The knob
# names are STUB_-prefixed on purpose: the script's own $PR_URL variable would
# otherwise shadow an un-prefixed knob and the stub would read it back empty.
cat >"$STUBS/gc" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
  jq -nc --arg p "${RIG_PREFIX:-tk}" --arg path "${RIG_PATH:-}" \
    'if $path=="" then {rigs:[]} else {rigs:[{name:"fixture",prefix:$p,path:$path}]} end'
  exit 0
fi
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ]; then
  jq -nc --arg n "${STUB_PR_NUMBER:-}" --arg u "${STUB_PR_URL:-}" \
    '[{id:"tk-sub", metadata:( ({} + (if $n=="" then {} else {pr_number:$n} end)) + (if $u=="" then {} else {pr_url:$u} end) )}]'
  exit 0
fi
exit 0
STUB
chmod +x "$STUBS/gc"

GHLOG="$TMPD/gh.log"
# run [KEY=VAL ...] [--no-gh] -- <sut args...>
# Per-call knobs, so nothing leaks between cases; combined stdout+stderr is
# returned so an assertion can read either the delivery line or the refusal.
run() {
  local ver="2.101.0" fail="" prn="" pru="" rigpath="" rigpre="tk" nogh=""
  while [ $# -gt 0 ]; do
    case "$1" in
      GH_STUB_VER=*)  ver="${1#*=}" ;;
      GH_STUB_FAIL=*) fail="${1#*=}" ;;
      PR_NUMBER=*)    prn="${1#*=}" ;;
      PR_URL=*)       pru="${1#*=}" ;;
      RIG_PATH=*)     rigpath="${1#*=}" ;;
      RIG_PREFIX=*)   rigpre="${1#*=}" ;;
      --no-gh)        nogh=1 ;;
      --)             shift; break ;;
      *)              break ;;
    esac
    shift
  done
  [ -n "$nogh" ] && rm -f "$STUBS/gh"
  : >"$GHLOG"
  ( cd "$REPO" && env -i \
      PATH="$STUBS:$FARM" HOME="$HOMEDIR" GC_RIG_ROOT="$REPO" GHLOG="$GHLOG" \
      GH_STUB_VER="$ver" GH_STUB_FAIL="$fail" STUB_PR_NUMBER="$prn" STUB_PR_URL="$pru" \
      RIG_PATH="$rigpath" RIG_PREFIX="$rigpre" \
      bash "$SUT" "$@" 2>&1 )
}
restore_gh() {
  [ -x "$STUBS/gh" ] && return 0
  cat >"$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "gh version ${GH_STUB_VER:-2.101.0} (2026-01-01)"; exit 0; fi
printf '%s\n' "$*" >>"${GHLOG:?}"
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "comment" ]; then
  if [ -n "${GH_STUB_FAIL:-}" ]; then echo "stub gh: upload failed" >&2; exit 1; fi
  echo "https://github.com/acme/widgets/pull/stub#issuecomment-1"; exit 0
fi
exit 0
STUB
  chmod +x "$STUBS/gh"
}

echo "# happy path: --pr <number> attaches, pins the origin, exits 0"
out="$(run -- --file "$MP4" --pr 41)"; rc=$?
ok "delivery exits 0" "[ '$rc' = 0 ]"
GH="$(cat "$GHLOG")"
has "pr comment 41" "$GH" "posts a comment on PR 41"
has "--repo github.com/acme/widgets" "$GH" "the post is pinned to our origin"
has "--attach $MP4" "$GH" "the file is attached inline"
has "Demo capture for this PR" "$GH" "a factual default body is included"
has "delivered $MP4 to PR#41" "$out" "it reports the delivery"

echo "# gh version compare is numeric: 2.101.0 is NOT below 2.99.0"
out="$(run GH_STUB_VER=2.101.0 -- --file "$MP4" --pr 7)"; rc=$?
ok "2.101.0 accepted (numeric, not string, compare)" "[ '$rc' = 0 ]"
has "pr comment 7" "$(cat "$GHLOG")" "2.101.0 proceeds to the attach"

echo "# gh at the exact floor 2.99.0 is accepted"
out="$(run GH_STUB_VER=2.99.0 -- --file "$MP4" --pr 8)"; rc=$?
ok "2.99.0 accepted" "[ '$rc' = 0 ]"

echo "# gh below the floor is refused, and nothing is posted"
out="$(run GH_STUB_VER=2.98.0 -- --file "$MP4" --pr 9)"; rc=$?
ok "2.98.0 refused (exit 1)" "[ '$rc' = 1 ]"
has "below 2.99.0" "$out" "it names the floor"
hasnt "pr comment" "$(cat "$GHLOG")" "no comment is posted on an old gh"

echo "# a major below 2 is refused despite a high minor"
out="$(run GH_STUB_VER=1.99.0 -- --file "$MP4" --pr 9)"; rc=$?
ok "1.99.0 refused" "[ '$rc' = 1 ]"

echo "# gh not found is refused (fail closed), nothing posted"
out="$(run --no-gh -- --file "$MP4" --pr 10)"; rc=$?
ok "missing gh exits 1" "[ '$rc' = 1 ]"
has "gh not found" "$out" "it says gh is missing"
restore_gh

echo "# an empty artifact is refused"
out="$(run -- --file "$EMPTY" --pr 11)"; rc=$?
ok "empty file exits 1" "[ '$rc' = 1 ]"
has "is empty" "$out" "it says the file is empty"

echo "# a PR URL outside our origin is refused"
out="$(run -- --file "$MP4" --pr "https://github.com/someone-else/theirs/pull/7")"; rc=$?
ok "foreign PR URL exits 1" "[ '$rc' = 1 ]"
has "refusing to attach" "$out" "it says why it refused"
hasnt "pr comment" "$(cat "$GHLOG")" "nothing is posted to a foreign PR"

echo "# a PR URL in our origin is accepted and reduced to its number"
out="$(run -- --file "$MP4" --pr "https://github.com/acme/widgets/pull/88")"; rc=$?
ok "our-origin PR URL exits 0" "[ '$rc' = 0 ]"
has "pr comment 88" "$(cat "$GHLOG")" "the URL is reduced to the PR number"

echo "# --subject resolves the PR from the bead's pr_number"
out="$(run PR_NUMBER=55 RIG_PATH="$REPO" RIG_PREFIX=tk -- --file "$MP4" --subject tk-sub)"; rc=$?
ok "subject delivery exits 0" "[ '$rc' = 0 ]"
has "pr comment 55" "$(cat "$GHLOG")" "the PR comes from the subject's pr_number"

echo "# --subject with only a pr_url resolves and attaches"
out="$(run PR_URL="https://github.com/acme/widgets/pull/56" RIG_PATH="$REPO" RIG_PREFIX=tk -- --file "$MP4" --subject tk-sub)"; rc=$?
ok "subject-by-url delivery exits 0" "[ '$rc' = 0 ]"
has "pr comment 56" "$(cat "$GHLOG")" "the PR comes from the subject's pr_url"

echo "# no PR and no resolvable subject is refused"
out="$(run -- --file "$MP4" --subject tk-sub)"; rc=$?
ok "unresolvable PR exits 1" "[ '$rc' = 1 ]"
has "no PR given and none resolvable" "$out" "it says the PR could not be resolved"

echo "# a gh failure is surfaced, not swallowed (fail closed)"
out="$(run GH_STUB_FAIL=1 -- --file "$MP4" --pr 41)"; rc=$?
ok "gh failure exits 1" "[ '$rc' = 1 ]"
has "failed" "$out" "it reports the gh failure"

echo "# --body overrides the default"
out="$(run -- --file "$MP4" --pr 41 --body "watch the board render")"; rc=$?
ok "custom body exits 0" "[ '$rc' = 0 ]"
GH="$(cat "$GHLOG")"
has "watch the board render" "$GH" "the custom body is used"
hasnt "Demo capture for this PR" "$GH" "the default body is not used when overridden"

echo "# a missing --file is a usage error (exit 2)"
out="$(run -- --pr 41)"; rc=$?
ok "missing --file exits 2" "[ '$rc' = 2 ]"

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all demo-deliver assertions passed"; else echo "FAIL: demo-deliver had failures"; fi
exit "$FAIL"
