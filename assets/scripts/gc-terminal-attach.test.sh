#!/usr/bin/env bash
# Hermetic test for the city web terminal's attach guard (tk-rbf9r).
#
# WHAT IS BEING GUARDED. ttyd runs with `-a/--url-arg`, so the browser's query
# string becomes the argv of the attach command, and with `-W`, so the resulting
# terminal is writable. `gc-terminal-attach.sh` is the only thing standing
# between a URL and `gc session attach`. Every hostile input below was verified
# to actually reach argv through ttyd 1.7.7 — a leading dash, `../`, a `;`, a
# second `arg=` — so these are regression tests for reachable inputs, not for
# hypothetical ones.
#
# Hermetic: `gc` is a stub on PATH, so no city, no Dolt, no tmux, no network,
# and no session is ever really attached. The stub prints what WOULD have been
# exec'd, which is what the assertions read.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/gc-terminal-attach.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -f "$GUARD" ] && ok "guard exists at $GUARD" || { bad "guard missing: $GUARD"; }

bash -n "$GUARD" \
  && ok "guard is syntactically valid bash" \
  || bad "guard failed bash -n"

[ -x "$GUARD" ] \
  && ok "guard is executable (ttyd execs it directly)" \
  || bad "guard is not executable — ttyd could not spawn it"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$GUARD" \
    && ok "guard is shellcheck-clean" \
    || bad "guard has shellcheck findings"
fi

# --- The stub `gc`. ----------------------------------------------------------
# `session list --json` prints the fixture; `session attach` prints its argv and
# exits, so a test can tell "would have attached X" from "refused".
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
if [ "${1-}" = "session" ] && [ "${2-}" = "list" ]; then
  [ "${GC_STUB_LIST_FAILS:-0}" = "1" ] && exit 1
  cat "$GC_STUB_LISTING"
  exit 0
fi
if [ "${1-}" = "session" ] && [ "${2-}" = "attach" ]; then
  shift 2
  printf 'ATTACH'
  for a in "$@"; do printf ' [%s]' "$a"; done
  printf '\n'
  exit 0
fi
echo "stub gc: unexpected invocation: $*" >&2
exit 99
STUB
chmod +x "$TMP/bin/gc"

# Shaped like real `gc session list --json` output, with the three identifier
# forms `gc session attach` accepts. The witness row is the one that matters
# most: a real rig-scoped alias contains a '/'.
cat > "$TMP/sessions.json" <<'JSON'
{
  "_cache_age_s": 0,
  "sessions": [
    {"id": "lx-vllv",  "alias": "gc-toolkit.mayor",              "session_name": "gc-toolkit__mayor"},
    {"id": "lx-2rz07", "alias": "gc-toolkit/gc-toolkit.witness", "session_name": "gc-toolkit__witness"},
    {"id": "lx-k7r38", "alias": "gc-toolkit/gc-toolkit.nux",     "session_name": "gc-toolkit__polecat-lx-k7r38"}
  ]
}
JSON

OUT=''; RC=0
run_guard() {
  set +e
  OUT="$(PATH="$TMP/bin:$PATH" \
         GC_STUB_LISTING="$TMP/sessions.json" \
         GC_STUB_LIST_FAILS="${GC_STUB_LIST_FAILS:-0}" \
         GC_TERMINAL_DEFAULT_SESSION=gc-toolkit.mayor \
         bash "$GUARD" "$@" 2>&1)"
  RC=$?
  set -e
}

# attaches <expected-argv-tail> <label> [args...]
attaches() {
  local want="$1" label="$2"; shift 2
  run_guard "$@"
  if [ "$RC" -eq 0 ] && [ "$OUT" = "ATTACH $want" ]; then
    ok "$label"
  else
    bad "$label (rc=$RC out='$OUT' want='ATTACH $want')"
  fi
}

# refuses <label> [args...] — refusal means BOTH a non-zero exit and, the part
# that actually matters, no attach at all.
refuses() {
  local label="$1"; shift
  run_guard "$@"
  if [ "$RC" -eq 0 ]; then
    bad "$label — guard exited 0 (out='$OUT')"
  elif [[ "$OUT" == *ATTACH* ]]; then
    bad "$label — REFUSAL LEAKED AN ATTACH (out='$OUT')"
  elif [[ "$OUT" != *"refusing to attach"* ]]; then
    bad "$label — refused without saying why (out='$OUT')"
  else
    ok "$label"
  fi
}

echo "--- the default target: today's behaviour, preserved ---"

# The pre-tk-rbf9r invocation was `gc session attach gc-toolkit.mayor` with no
# argument at all, and that is what a client sends when it names no session.
attaches "[gc-toolkit.mayor]" "(A) no argument attaches the default"

# ttyd sends a bare `?arg=` as one EMPTY argument, not as zero arguments
# (verified on 1.7.7). Treating it as anything but "no session named" would
# change the default behaviour of a URL the board can legitimately produce.
attaches "[gc-toolkit.mayor]" "(B) empty argument attaches the default" ""

# The default path must not depend on the allowlist machinery: a city whose
# session list is unavailable still gets the terminal it had before.
GC_STUB_LIST_FAILS=1 attaches "[gc-toolkit.mayor]" \
  "(C) default still attaches when the session list is unavailable"
GC_STUB_LIST_FAILS=0

echo "--- naming a live session: the feature ---"

attaches "[--] [gc-toolkit.mayor]" "(D) a live alias attaches" "gc-toolkit.mayor"

# The '/' case. A blanket '/' ban would have made the feature useless, because
# every rig-scoped session has one; the allowlist is what makes it safe.
attaches "[--] [gc-toolkit/gc-toolkit.witness]" \
  "(E) a live rig-scoped alias (contains '/') attaches" "gc-toolkit/gc-toolkit.witness"

attaches "[--] [lx-k7r38]" "(F) a live session id attaches" "lx-k7r38"
attaches "[--] [gc-toolkit__polecat-lx-k7r38]" \
  "(G) a live session_name attaches" "gc-toolkit__polecat-lx-k7r38"

# `--` is passed so `gc` cannot read a name as a flag even if the syntax rule
# is someday loosened. The assertions above pin it.
grep -q 'exec gc session attach -- "\$REQUESTED"' "$GUARD" \
  && ok "(H) the validated attach passes -- before the name" \
  || bad "(H) the validated attach no longer passes --"

echo "--- hostile argv that ttyd was proven to deliver ---"

# `?arg=%2Dv` really does arrive as argv `-v`. Unguarded, `gc` would read it as
# a flag rather than a session name.
refuses "(I) leading-dash argv is refused (-v)" "-v"
refuses "(J) leading-dash argv is refused (--writable)" "--writable"

# `?arg=..%2Fetc` arrives intact.
refuses "(K) path traversal is refused" "../etc/passwd"
refuses "(L) traversal inside an otherwise-valid name is refused" "gc-toolkit/../../etc"

# ttyd appends EVERY `arg=` in the query string, so this is the exact shape an
# injection attempt takes: name the real session, then append a flag.
refuses "(M) a second argument is refused (the ?arg=&arg= shape)" \
  "gc-toolkit.mayor" "--writable"

# Shell metacharacters arrive verbatim. `gc` is exec'd without a shell so these
# are not immediately dangerous, but a name is never accepted on spelling.
refuses "(N) semicolon is refused" "gc-toolkit.mayor;id"
refuses "(O) command substitution is refused" '$(id)'
refuses "(P) backticks are refused" '`id`'
refuses "(Q) pipe is refused" "a|b"
refuses "(R) ampersand is refused" "a&b"
refuses "(S) redirection is refused" "a>b"
refuses "(T) whitespace is refused" "gc-toolkit mayor"
refuses "(U) newline is refused" 'gc-toolkit
mayor'
refuses "(V) a leading dot is refused" ".hidden"
refuses "(W) a deep path is refused" "a/b/c"
refuses "(X) an over-long name is refused" "$(printf 'a%.0s' $(seq 1 200))"

echo "--- well-formed but not live: the allowlist is the control ---"

# The whole point: passing the syntax rules is not sufficient. This name is
# spelled exactly like a real session and is refused solely because it is not
# in the live list.
refuses "(Y) a well-formed name that is not a live session is refused" "gc-toolkit.ghost"

# A session that exists in another city's list, or one that has since drained,
# is the same case — and so is an unreadable list.
GC_STUB_LIST_FAILS=1 refuses \
  "(Z) a named session is refused when the session list cannot be read" "gc-toolkit.mayor"
GC_STUB_LIST_FAILS=0

# Without jq there is no allowlist, so there is no validation, so nothing named
# may be attached. (PATH holds only the stub: no jq, no coreutils.)
set +e
OUT="$(PATH="$TMP/bin" \
       GC_STUB_LISTING="$TMP/sessions.json" \
       GC_TERMINAL_DEFAULT_SESSION=gc-toolkit.mayor \
       bash "$GUARD" gc-toolkit.mayor 2>&1)"
RC=$?
set -e
{ [ "$RC" -ne 0 ] && [[ "$OUT" != *ATTACH* ]]; } \
  && ok "(AA) a named session is refused when jq is unavailable" \
  || bad "(AA) guard attached without an allowlist (rc=$RC out='$OUT')"

echo "--- the detach invariant's half of the contract ---"

# ttyd signals the process it spawned when the socket closes (-s 1, SIGHUP).
# `exec` makes that process the tmux client itself, so the signal detaches it.
# A guard that forked and waited would put a shell in between and the detach
# would no longer be this script's guarantee — closing a tile is the one
# operation that must never reach the agent's session.
grep -qE '^exec gc session attach' "$GUARD" \
  && ok "(AB) the guard execs the attach rather than forking it" \
  || bad "(AB) the guard no longer execs — ttyd's SIGHUP would land on a shell"

[ "$(grep -cE '^[[:space:]]*exec gc session attach' "$GUARD")" -eq 2 ] \
  && ok "(AC) both attach paths (default and validated) exec" \
  || bad "(AC) an attach path stopped exec'ing"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
