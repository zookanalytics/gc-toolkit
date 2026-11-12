#!/usr/bin/env bash
# ui-copy.test.sh — the script that runs a copy of a rig's UI. Proves that start
# runs the rig's declared serve command from the tree on a port of its own,
# reads the three vars in one gc call, and publishes the copy only on request;
# that the copy's leader leads a process group of its own and carries the
# caller's session values where the orphan sweep reads them; that a publish
# command which ends alone leaves the copy running with no address until start
# publishes it again, and a copy that ends takes its publish command with it;
# that a publish refused while another client changes the config is tried
# again, and a port refused as taken moves the copy to another; that a city
# with no publisher gets a copy with no address; and that stop ends the whole
# group. Real processes. gc, the publish command and the free-port pick are
# stubs, so no suite touches Tailscale, a city or node; python3 serves.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/ui-copy.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-ui-copy-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"

# A copy a failed assertion left running is ended by its group before the
# temp dir goes.
cleanup() {
  local f pid
  for f in "$TMP"/state/*/pid "$TMP"/city/.gc/runtime/packs/gc-toolkit/ui-copies/*/pid; do
    [ -f "$f" ] || continue
    pid=$(cat "$f" 2>/dev/null)
    case "$pid" in '' | *[!0-9]*) continue ;; esac
    [ "$pid" -gt 1 ] && kill -KILL -- "-$pid" 2>/dev/null
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
# The members of a process group, one pid per line.
members() { ps -axo pgid=,pid= | awk -v g="$1" '$1 == g { print $2 }'; }
group_gone() { [ -z "$(members "$1")" ]; }
# A port answers on loopback.
answers() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
# The record of the copy a report names, and its leader's pid.
record() { dirname "$(field "$1" log)"; }
leader() { cat "$(record "$1")/pid" 2>/dev/null; }
publisher_pid() { local p; p=$(cat "$(record "$1")/publisher" 2>/dev/null); printf '%s' "${p#* }"; }
# A process's environment, as the orphan sweep reads it: ps on macOS, /proc on
# Linux.
environment() {
  if [ -r "/proc/$1/environ" ]; then tr '\0' '\n' <"/proc/$1/environ"; else ps eww -o command= -p "$1" | tr ' ' '\n'; fi
}

[ -x "$SCRIPT" ] || { echo "missing or not executable: $SCRIPT"; exit 1; }
bash -n "$SCRIPT" && ok "ui-copy.sh is valid bash" || bad "ui-copy.sh is valid bash" "bash -n failed"
command -v python3 >/dev/null 2>&1 || { echo "test setup: python3 not found; it serves the copies"; exit 2; }

# --- stubs -------------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/state" "$TMP/a" "$TMP/b"
# gc answers ui-copy.sh's one read from UI_SERVE, UI_PUBLISH and UI_PATTERN,
# logging each call. GC_STUB_FAIL answers as gc does for a rig no city
# registers, and GC_STUB_UNDECLARED leaves the three vars out of the formula.
cat >"$BIN/gc" <<'GC'
#!/usr/bin/env bash
printf 'gc %s\n' "$*" >>"${GC_CALLS:?}"
if [ "${1:-} ${2:-} ${3:-}" = "formula show mol-rig-demo" ]; then
  if [ -n "${GC_STUB_FAIL:-}" ]; then
    printf '{"ok":false,"error":{"message":"rig \\"demo\\" is not registered in any city"}}\n'; exit 1
  fi
  jq -nc --arg s "${UI_SERVE:-}" --arg p "${UI_PUBLISH:-}" --arg a "${UI_PATTERN:-}" --arg drop "${GC_STUB_UNDECLARED:-}" '
    def v($n; $x): {name: $n, default: ""} + (if $x == "" then {rig_default: null} else {rig_default: $x} end);
    {ok: true, name: "mol-rig-demo", vars: ([{name: "app_reads_city", default: "false", rig_default: "true"}]
      + (if $drop != "" then [] else [v("ui_serve_command"; $s), v("ui_publish_command"; $p), v("ui_address_pattern"; $a)] end))}'
  exit 0
fi
echo "gc stub: unexpected call: $*" >&2; exit 97
GC
# node answers demo_engine_free_port's pick with a port python3 finds free, or
# fails as a host with no node does when NODE_STUB_FAIL is set.
cat >"$BIN/node" <<'NODE'
#!/usr/bin/env bash
if [ "${1:-}" = "-e" ] && [ $# -eq 2 ] && [ -z "${NODE_STUB_FAIL:-}" ]; then
  exec python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1], end="")'
fi
exit 1
NODE
# The serve command: an HTTP server on loopback at $PORT that records its
# working directory and port.
cat >"$TMP/serve.py" <<'PY'
import http.server, os
port = int(os.environ["PORT"])
with open(os.environ["SERVED"], "a") as f:
    f.write("%s %d\n" % (os.getcwd(), port))
http.server.HTTPServer(("127.0.0.1", port), http.server.SimpleHTTPRequestHandler).serve_forever()
PY
# The publish command, by mode: ok stays running; again-once refuses its first
# run as Tailscale does while another client changes the serve config;
# taken-first refuses the first port it is given as Tailscale refuses a port
# another mapping holds; fails refuses for another reason. Each run logs its
# mode and $PORT.
cat >"$TMP/publish.sh" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$PORT" >>"${PUBLISHED:?}"
case "$1" in
  again-once)
    if [ ! -e "$PUBLISHED.again" ]; then
      : >"$PUBLISHED.again"
      echo "Another client is changing the serve config; please try again." >&2
      exit 1
    fi ;;
  taken-first)
    [ -e "$PUBLISHED.first" ] || printf '%s\n' "$PORT" >"$PUBLISHED.first"
    if [ "$(cat "$PUBLISHED.first")" = "$PORT" ]; then
      echo "error: listener already exists for port $PORT" >&2
      exit 1
    fi ;;
  fails)
    echo "serve config: access denied" >&2
    exit 1 ;;
esac
echo "Available within your tailnet: https://host.example:$PORT/"
exec sleep 300
SH
chmod +x "$BIN/gc" "$BIN/node" "$TMP/publish.sh"

# The suite's own environment: no ambient city value reaches the script, and
# the session values are the suite's, naming a city no sweep serves.
for v in $(compgen -e); do
  case "$v" in GC_* | BEADS_* | UI_COPY_*) unset "$v" ;; esac
done
export PATH="$BIN:$PATH" GC_CALLS="$TMP/gc.calls" SERVED="$TMP/served" PUBLISHED="$TMP/published"
export UI_COPY_STATE_DIR="$TMP/state" UI_COPY_SETTLE=1 UI_COPY_START_WAIT=30
export GC_SESSION_ID=ui-copy-test-session GC_CITY_PATH="$TMP/no-city" GC_RUNTIME_EPOCH=7
export UI_SERVE="python3 $TMP/serve.py" UI_PUBLISH="$TMP/publish.sh ok" UI_PATTERN='https://host.example:$PORT/'
: >"$GC_CALLS"; : >"$SERVED"; : >"$PUBLISHED"

echo "── usage ──"
"$SCRIPT" >/dev/null 2>&1; eq "$?" 2 "no subcommand exits 2"
"$SCRIPT" start --rig demo >/dev/null 2>&1; eq "$?" 2 "start with no --tree exits 2"
"$SCRIPT" start --tree "$TMP/a" >/dev/null 2>&1; eq "$?" 2 "start with no --rig and no GC_RIG exits 2"
"$SCRIPT" status --tree "$TMP/a" --publish >/dev/null 2>&1; eq "$?" 2 "an option status does not take exits 2"

echo "── start without an address ──"
OUT=$("$SCRIPT" start --tree "$TMP/a" --rig demo); RC=$?
eq "$RC" 0 "start exits 0"
eq "$(field "$OUT" state)" running "it reports state=running"
PA=$(field "$OUT" port)
case "$PA" in '' | *[!0-9]*) bad "it prints the port" "port='$PA'" ;; *) ok "it prints the port" ;; esac
grep -qx 'address=' <<<"$OUT" && ok "it prints an empty address" || bad "it prints an empty address" "$OUT"
has "$(field "$OUT" detail)" "started without --publish" "detail says why it has no address"
answers "$PA" && ok "the copy answers on its port" || bad "the copy answers on its port" "port $PA"
eq "$(cat "$SERVED")" "$TMP/a $PA" "the serve command ran from the tree, with the port as PORT"
eq "$(cat "$GC_CALLS")" "gc formula show mol-rig-demo --rig demo --json" "start reads the vars in one gc call"
eq "$(cat "$PUBLISHED")" "" "no publish command ran"
LA=$(leader "$OUT")
eq "$(ps -o pgid= -p "$LA" | tr -d '[:space:]')" "$LA" "the leader leads its own process group"
case "$(ps -o stat= -p "$LA")" in
  *s*) ok "the leader leads its own session" ;;
  *) bad "the leader leads its own session" "stat='$(ps -o stat= -p "$LA")'" ;;
esac
[ "$(ps -o pgid= -p $$ | tr -d '[:space:]')" != "$LA" ] && ok "the copy is outside the caller's process group" \
  || bad "the copy is outside the caller's process group" "same pgid as the suite"
ENVIRON=$(environment "$LA")
has "$ENVIRON" "GC_SESSION_ID=ui-copy-test-session" "the leader carries the caller's GC_SESSION_ID where the sweep reads it"
has "$ENVIRON" "GC_CITY_PATH=$TMP/no-city" "the leader carries the caller's GC_CITY_PATH"
has "$ENVIRON" "GC_RUNTIME_EPOCH=7" "the leader carries the caller's GC_RUNTIME_EPOCH"
if [ "$(uname -s)" = Darwin ]; then
  case "$(ps -o comm= -p "$LA")" in
    /bin/* | /usr/bin/* | /sbin/* | /usr/sbin/*) bad "the leader is no system binary, whose environment macOS hides" "$(ps -o comm= -p "$LA")" ;;
    *) ok "the leader is no system binary, whose environment macOS hides" ;;
  esac
fi

echo "── start again, status, and a second tree ──"
OUT2=$("$SCRIPT" start --tree "$TMP/a/" --rig demo); RC=$?
eq "$RC" 0 "a second start for the tree exits 0"
eq "$(field "$OUT2" port)" "$PA" "it reports the running copy's port"
eq "$(leader "$OUT2")" "$LA" "it starts no second copy"
eq "$(wc -l <"$SERVED" | tr -d ' ')" 1 "the serve command ran once"
OUT=$("$SCRIPT" status --tree "$TMP/a"); RC=$?
eq "$RC" 0 "status of a running copy exits 0"
eq "$(field "$OUT" state)" running "status reports state=running"
eq "$(field "$OUT" port)" "$PA" "status reports the port"
OUTB=$("$SCRIPT" start --tree "$TMP/b" --rig demo); RC=$?
eq "$RC" 0 "a copy of a second tree starts beside the first"
PB=$(field "$OUTB" port)
[ -n "$PB" ] && [ "$PB" != "$PA" ] && ok "it has a port of its own" || bad "it has a port of its own" "$PB vs $PA"
answers "$PA" && answers "$PB" && ok "both copies answer" || bad "both copies answer" "$PA $PB"

echo "── stop ends the copy's whole group ──"
OUT=$("$SCRIPT" stop --tree "$TMP/a"); RC=$?
eq "$RC" 0 "stop exits 0"
eq "$(field "$OUT" state)" stopped "it reports state=stopped"
group_gone "$LA" && ok "no member of the copy's group is left" || bad "no member of the copy's group is left" "$(members "$LA")"
answers "$PA" && bad "the port no longer answers" "port $PA" || ok "the port no longer answers"
OUT=$("$SCRIPT" status --tree "$TMP/a"); RC=$?
eq "$RC" 1 "status of a stopped copy exits 1"
eq "$(field "$OUT" state)" none "it reports state=none"
OUT=$("$SCRIPT" stop --tree "$TMP/a"); RC=$?
eq "$RC" 0 "a stop with no copy running exits 0"
eq "$(field "$OUT" state)" none "it reports state=none"
"$SCRIPT" stop --tree "$TMP/b" >/dev/null

echo "── start with an address ──"
OUT=$(UI_PATTERN='https://host.example:${PORT}/x/$PORT' "$SCRIPT" start --tree "$TMP/a" --rig demo --publish); RC=$?
eq "$RC" 0 "start --publish exits 0"
P=$(field "$OUT" port)
eq "$(field "$OUT" address)" "https://host.example:$P/x/$P" "the address is the pattern with the port for each \$PORT and \${PORT}"
eq "$(cat "$PUBLISHED")" "ok $P" "the publish command ran once, with the port as PORT"
L=$(leader "$OUT"); PUB=$(publisher_pid "$OUT")
eq "$(ps -o pgid= -p "$PUB" | tr -d '[:space:]')" "$L" "the publish command runs in the copy's process group"
OUT=$("$SCRIPT" status --tree "$TMP/a"); RC=$?
ADDR=$(field "$OUT" address)
eq "$ADDR" "https://host.example:$P/x/$P" "status reports the address"

echo "── a publish command that ends alone ──"
kill -TERM "$PUB"
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PUB" 2>/dev/null || break; sleep 0.2; done
OUT=$("$SCRIPT" status --tree "$TMP/a"); RC=$?
eq "$RC" 0 "the copy still runs"
grep -qx 'address=' <<<"$OUT" && ok "it reads as having no address" || bad "it reads as having no address" "$OUT"
has "$(field "$OUT" detail)" "publish command ended" "detail says the publish command ended"
answers "$P" && ok "the copy still answers" || bad "the copy still answers" "port $P"
OUT=$("$SCRIPT" start --tree "$TMP/a" --rig demo --publish); RC=$?
eq "$RC" 0 "start --publish on that copy exits 0"
eq "$(field "$OUT" port)" "$P" "it keeps the copy and its port"
eq "$(field "$OUT" address)" "$ADDR" "the copy has its address again"
eq "$(leader "$OUT")" "$L" "the same leader runs it"
eq "$(wc -l <"$PUBLISHED" | tr -d ' ')" 2 "the publish command ran a second time"
"$SCRIPT" stop --tree "$TMP/a" >/dev/null
group_gone "$L" && ok "stop ends the publish command with the copy" || bad "stop ends the publish command with the copy" "$(members "$L")"

echo "── a copy that ends takes its publish command with it ──"
: >"$PUBLISHED"
OUT=$("$SCRIPT" start --tree "$TMP/a" --rig demo --publish)
L=$(leader "$OUT"); PUB=$(publisher_pid "$OUT")
SERVE_PID=$(ps -axo pgid=,pid=,command= | awk -v g="$L" '$1 == g && /serve\.py/ { print $2 }' | head -1)
[ -n "$SERVE_PID" ] && kill -TERM "$SERVE_PID"
for _ in $(seq 1 25); do group_gone "$L" && break; sleep 0.2; done
group_gone "$L" && ok "the leader ended the group once the serve command ended" || bad "the leader ended the group once the serve command ended" "$(members "$L")"
kill -0 "$PUB" 2>/dev/null && bad "the publish command ended with the copy" "pid $PUB" || ok "the publish command ended with the copy"
OUT=$("$SCRIPT" status --tree "$TMP/a"); RC=$?
eq "$RC" 1 "status of a copy that ended exits 1"
eq "$(field "$OUT" state)" died "it reports state=died"
eq "$(field "$OUT" rc)" 143 "it reports the serve command's exit code"
OUT=$("$SCRIPT" start --tree "$TMP/a" --rig demo); RC=$?
eq "$RC" 0 "a start for that tree runs a new copy"
[ "$(leader "$OUT")" != "$L" ] && ok "under a new leader" || bad "under a new leader" "same leader $L"
"$SCRIPT" stop --tree "$TMP/a" >/dev/null

echo "── a publish refused while another client changes the config is tried again ──"
: >"$PUBLISHED"
OUT=$(UI_PUBLISH="$TMP/publish.sh again-once" "$SCRIPT" start --tree "$TMP/a" --rig demo --publish); RC=$?
eq "$RC" 0 "start exits 0"
P=$(field "$OUT" port)
eq "$(field "$OUT" address)" "https://host.example:$P/" "the copy is published"
eq "$(cat "$PUBLISHED")" "again-once $P
again-once $P" "the publish command ran twice, on the same port"
"$SCRIPT" stop --tree "$TMP/a" >/dev/null

echo "── a port refused as taken moves the copy to another ──"
: >"$PUBLISHED"; : >"$SERVED"
OUT=$(UI_PUBLISH="$TMP/publish.sh taken-first" "$SCRIPT" start --tree "$TMP/a" --rig demo --publish); RC=$?
eq "$RC" 0 "start exits 0"
FIRST=$(cat "$PUBLISHED.first" 2>/dev/null)
P=$(field "$OUT" port)
[ -n "$P" ] && [ -n "$FIRST" ] && [ "$P" != "$FIRST" ] && ok "the copy runs on another port" || bad "the copy runs on another port" "first=$FIRST now=$P"
eq "$(field "$OUT" address)" "https://host.example:$P/" "the address names the new port"
eq "$(wc -l <"$SERVED" | tr -d ' ')" 2 "the serve command ran again, on the new port"
answers "$FIRST" && bad "nothing answers on the refused port" "port $FIRST" || ok "nothing answers on the refused port"
answers "$P" && ok "the copy answers on the new port" || bad "the copy answers on the new port" "port $P"
"$SCRIPT" stop --tree "$TMP/a" >/dev/null

echo "── a publish refused for another reason ──"
OUT=$(UI_PUBLISH="$TMP/publish.sh fails" "$SCRIPT" start --tree "$TMP/a" --rig demo --publish); RC=$?
eq "$RC" 0 "start exits 0, with the copy running"
grep -qx 'address=' <<<"$OUT" && ok "it has no address" || bad "it has no address" "$OUT"
has "$(field "$OUT" detail)" "access denied" "detail carries what the publish command said"
"$SCRIPT" stop --tree "$TMP/a" >/dev/null

echo "── a city with no publisher ──"
: >"$PUBLISHED"
OUT=$(UI_PUBLISH="" "$SCRIPT" start --tree "$TMP/a" --rig demo --publish); RC=$?
eq "$RC" 0 "start --publish exits 0"
eq "$(field "$OUT" state)" running "the copy runs"
answers "$(field "$OUT" port)" && ok "it answers on the port it prints" || bad "it answers on the port it prints" "$OUT"
grep -qx 'address=' <<<"$OUT" && ok "it prints an empty address" || bad "it prints an empty address" "$OUT"
has "$(field "$OUT" detail)" "no address can be given" "detail says no address can be given"
eq "$(cat "$PUBLISHED")" "" "no publish command ran"
"$SCRIPT" stop --tree "$TMP/a" >/dev/null

echo "── refusals ──"
OUT=$(UI_SERVE="" "$SCRIPT" start --tree "$TMP/a" --rig demo); RC=$?
eq "$RC" 1 "a rig with no serve command exits 1"
eq "$(field "$OUT" state)" failed "it reports state=failed"
eq "$(field "$OUT" reason)" no-serve-command "it gives the reason"
has "$(field "$OUT" detail)" "rig demo declares no ui_serve_command" "detail names the rig"
OUT=$(GC_STUB_UNDECLARED=1 "$SCRIPT" start --tree "$TMP/a" --rig demo); RC=$?
eq "$(field "$OUT" reason)" no-serve-command "a formula that declares no serve command is refused"
has "$(field "$OUT" detail)" "mol-rig-demo, as gc loads it, declares no ui_serve_command" "detail names the formula"
OUT=$(GC_STUB_FAIL=1 "$SCRIPT" start --tree "$TMP/a" --rig demo); RC=$?
eq "$RC" 1 "a read gc refuses exits 1"
eq "$(field "$OUT" reason)" vars-unread "it gives the reason"
has "$(field "$OUT" detail)" "is not registered in any city" "detail carries gc's error"
OUT=$("$SCRIPT" start --tree "$TMP/missing" --rig demo); RC=$?
eq "$(field "$OUT" reason)" no-tree "a tree that is not a directory is refused"
OUT=$(NODE_STUB_FAIL=1 "$SCRIPT" start --tree "$TMP/a" --rig demo); RC=$?
eq "$(field "$OUT" reason)" no-free-port "no free port is refused"
eq "$(ls "$TMP/state")" "" "no refusal leaves a record"

echo "── a copy that never comes up ──"
OUT=$(UI_SERVE='echo cannot serve; exit 3' "$SCRIPT" start --tree "$TMP/a" --rig demo); RC=$?
eq "$RC" 1 "a serve command that ends at once exits 1"
eq "$(field "$OUT" reason)" serve-exited "it gives the reason"
eq "$(field "$OUT" rc)" 3 "it reports the serve command's exit code"
has "$OUT" "cannot serve" "it shows the serve command's output"
OUT=$(UI_COPY_START_WAIT=2 UI_SERVE="echo \$\$ >$TMP/never.pid; exec sleep 60" "$SCRIPT" start --tree "$TMP/a" --rig demo); RC=$?
eq "$RC" 1 "a copy that never answers exits 1"
eq "$(field "$OUT" reason)" not-answering "it gives the reason"
eq "$(ls "$TMP/state")" "" "neither leaves a record"
NEVER=$(cat "$TMP/never.pid" 2>/dev/null)
[ -n "$NEVER" ] && ! kill -0 "$NEVER" 2>/dev/null && ok "the copy that never answered was stopped" \
  || bad "the copy that never answered was stopped" "pid '$NEVER'"

echo "── the state root is the city's when the city names one ──"
mkdir -p "$TMP/city/.gc"
OUT=$(env -u UI_COPY_STATE_DIR GC_CITY_PATH="$TMP/city" "$SCRIPT" start --tree "$TMP/a" --rig demo); RC=$?
eq "$RC" 0 "start exits 0"
eq "$(dirname "$(record "$OUT")")" "$TMP/city/.gc/runtime/packs/gc-toolkit/ui-copies" "the record is under the city's pack state"
OUT=$(env -u UI_COPY_STATE_DIR GC_CITY_PATH="$TMP/city" "$SCRIPT" stop --tree "$TMP/a"); RC=$?
eq "$(field "$OUT" state)" stopped "stop finds the copy there"

echo
echo "ui-copy.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
