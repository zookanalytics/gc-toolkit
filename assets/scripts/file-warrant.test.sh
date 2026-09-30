#!/usr/bin/env bash
# Hermetic test for file-warrant.sh — the shared warrant filer.
#
# warrant.target must be a session id the dog can feed to dance-probe.sh and
# `gc session kill`. The bug this script exists to close is a warrant filed
# against an agent address (a rig-qualified `/`-bearing assignee) that
# dance-probe.sh then refuses as unsafe. So the load-bearing assertions are: a
# `/`-bearing owner never lands in warrant.target (it is resolved to a session
# id first), and an owner that resolves to no live session files nothing.
# Stubbed gc; no live city, Dolt or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/file-warrant.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-file-warrant-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -x "$SUT" ] || { echo "file-warrant.sh missing or not executable at $SUT" >&2; exit 1; }

# A stateful gc stub: bd create writes the warrant into a JSON store that both
# the dedup query and the post-create re-read read back, so a second call for
# the same target sees the first, exactly as the live store does.
BIN="$TMP/bin"; mkdir -p "$BIN"
export STUB_GC_LOG="$TMP/gc.log"
export STUB_STORE="$TMP/store.json"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
STORE="${STUB_STORE:?}"; [ -s "$STORE" ] || echo '[]' > "$STORE"
sub="${1:-}"; verb="${2:-}"
case "$sub $verb" in
  "session list")
    [ -n "${STUB_SESSIONS_FAIL:-}" ] && { echo "gc: session list unavailable" >&2; exit 1; }
    printf '%s\n' "${STUB_SESSIONS:-{\"sessions\":[]}}" ;;
  "bd list")
    shift 2 || true
    tv=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --metadata-field) shift; case "${1:-}" in warrant.target=*) tv="${1#warrant.target=}" ;; esac ;;
        --metadata-field=*) case "${1#--metadata-field=}" in warrant.target=*) tv="${1#*warrant.target=}" ;; esac ;;
      esac
      shift || true
    done
    jq -c --arg t "$tv" '[ .[] | select($t == "" or ((.metadata["warrant.target"] // "") == $t)) ]' "$STORE" ;;
  "bd create")
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo "gc: bd create failed" >&2; exit 1; }
    shift 2 || true
    title=""; meta="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --title=*) title="${1#--title=}" ;;
        --title) shift; title="${1:-}" ;;
        --metadata) shift; meta="${1:-}" ;;
        --metadata=*) meta="${1#--metadata=}" ;;
      esac
      shift || true
    done
    n=$(jq 'length' "$STORE"); nid="tk-w$((n + 1))"
    tmp="$(mktemp "${STORE%/*}/.gc-stub.XXXXXX")"
    jq -c --arg id "$nid" --arg t "$title" --argjson m "$meta" \
      '. + [{id: $id, status: "open", title: $t, metadata: $m}]' "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    printf '{"id":"%s"}\n' "$nid" ;;
  *) echo "unexpected gc invocation: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"

# A roster where the wedged owner is reachable ONLY as a `/`-bearing alias —
# exactly the shape that produced the bug — plus a dead session that must never
# be targeted.
ROSTER='{"sessions":[
  {"id":"lx-wisp-p3","alias":"gc-toolkit/gc-toolkit.polecat-3","session_name":"gc-toolkit--gc-toolkit__polecat-3-pool","state":"active"},
  {"id":"lx-wisp-idle","alias":"gc-toolkit/gc-toolkit.witness","session_name":"gc-toolkit--gc-toolkit__witness","state":"asleep"},
  {"id":"lx-wisp-dead","alias":"gc-toolkit/gc-toolkit.polecat-9","session_name":"gc-toolkit--gc-toolkit__polecat-9-pool","state":"closed"}
]}'

# reset clears the store; run clears only the log, so LOG/META reflect that one
# invocation while a warrant filed by an earlier run survives for the dedup case.
reset() { echo '[]' > "$STUB_STORE"; }
# run <args...> -> OUT (stdout), ERR (stderr), RC, LOG (gc calls), META (the
# create's --metadata JSON, or empty when no create was logged)
run() {
  : > "$STUB_GC_LOG"
  OUT="$("$SUT" "$@" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
  LOG="$(cat "$STUB_GC_LOG")"
  META="$(grep -F 'bd create' "$STUB_GC_LOG" | sed 's/^.*--metadata //' | head -1)"
}
mget() { printf '%s' "$META" | jq -r --arg k "$1" '.[$k] // ""' 2>/dev/null; }

echo "# a /-bearing owner is resolved to a session id — it never lands in warrant.target"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "gc-toolkit/gc-toolkit.polecat-3" --reason "no wisp progress for 90m" --requester witness --dog "gc-toolkit.dog"
eq "$RC" 0 "the warrant is filed"
has "$LOG" 'bd create' "one create call is made"
eq "$(mget 'warrant.target')" "lx-wisp-p3" "warrant.target is the resolved session id"
hasnt "$(mget 'warrant.target')" "/" "and carries no slash — dance-probe.sh would accept it"
case "$(mget 'warrant.target')" in *[!A-Za-z0-9._-]*) bad "target is charset-safe" ;; *) ok "target is charset-safe" ;; esac
eq "$(mget 'warrant.reason')" "no wisp progress for 90m" "the reason is carried through"
eq "$(mget 'warrant.requester')" "witness" "the requester is carried through"
eq "$(mget 'gc.routed_to')" "gc-toolkit.dog" "the warrant is routed at the resolved dog"
eq "$OUT" "tk-w1" "the filed warrant id is printed for the caller's ledger"

echo "# the role (not the session id) is what the human-readable title carries"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "lx-wisp-p3" --role "gc-toolkit/gc-toolkit.polecat-3" --reason "stale 2h" --requester deacon --dog "gc-toolkit.dog"
has "$LOG" 'Stuck: gc-toolkit/gc-toolkit.polecat-3' "the title names the role a human reads"
eq "$(mget 'warrant.target')" "lx-wisp-p3" "while the target stays the session id"
eq "$(mget 'warrant.requester')" "deacon" "requester passes through for the deacon too"

echo "# an owner already given as a live session id resolves to itself"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "lx-wisp-p3" --reason r --requester witness --dog d
eq "$(mget 'warrant.target')" "lx-wisp-p3" "an id owner is filed unchanged"
eq "$(mget 'gc.routed_to')" "d" "and the dog route is stamped verbatim"

echo "# a session name resolves to its id"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "gc-toolkit--gc-toolkit__polecat-3-pool" --reason r --requester witness --dog d
eq "$(mget 'warrant.target')" "lx-wisp-p3" "a session_name owner resolves to the id"

echo "# an owner that matches no live session files nothing and refuses"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "gc-toolkit/gc-toolkit.ghost" --reason r --requester witness --dog d
eq "$RC" 1 "the filer refuses"
hasnt "$LOG" 'bd create' "no warrant is written"
has "$ERR" "no warrant filed" "and it says why on stderr"

echo "# an owner that matches ONLY a dead session is refused, never targeted"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "gc-toolkit/gc-toolkit.polecat-9" --reason r --requester witness --dog d
eq "$RC" 1 "a closed session is not a live target"
hasnt "$LOG" 'bd create' "so nothing is filed"

echo "# an asleep session is live enough to warrant"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "gc-toolkit/gc-toolkit.witness" --reason r --requester deacon --dog d
eq "$RC" 0 "an asleep owner still files"
eq "$(mget 'warrant.target')" "lx-wisp-idle" "targeting its session id"

echo "# a second warrant for the same session collapses onto the first"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "gc-toolkit/gc-toolkit.polecat-3" --reason "first" --requester witness --dog "gc-toolkit.dog"
eq "$OUT" "tk-w1" "the first warrant is filed"
run --owner "gc-toolkit--gc-toolkit__polecat-3-pool" --reason "second, different owner form" --requester deacon --dog "gc-toolkit.dog"
eq "$OUT" "tk-w1" "the repeat resolves to the same warrant already open"
eq "$RC" 3 "and exits 3 so a ledger skips the repeat while a coverage check still passes"
hasnt "$LOG" 'bd create' "and files no second one"
has "$ERR" "already open" "and it says so on stderr, keeping stdout the bare id"

echo "# an unreadable session list is not proof of a live target — refuse"
reset; export STUB_SESSIONS="$ROSTER"; export STUB_SESSIONS_FAIL=1
run --owner "lx-wisp-p3" --reason r --requester witness --dog d
eq "$RC" 1 "a broken roster refuses rather than filing blind"
hasnt "$LOG" 'bd create' "nothing is written"
unset STUB_SESSIONS_FAIL

echo "# a reason carrying a double quote cannot break the metadata payload"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "lx-wisp-p3" --reason 'bead "tk-a" stale 6h' --requester witness --dog "gc-toolkit.dog"
has "$LOG" 'bd create' "the warrant is still filed"
printf '%s' "$META" | jq -e . >/dev/null 2>&1 && ok "and its metadata is parseable JSON" || bad "the metadata payload did not survive the quote"
eq "$(mget 'warrant.reason')" 'bead "tk-a" stale 6h' "with the reason intact"

echo "# missing required arguments are usage errors, and file nothing"
reset; export STUB_SESSIONS="$ROSTER"
run --owner "lx-wisp-p3" --requester witness --dog d
eq "$RC" 2 "a missing --reason is a usage error"
hasnt "$LOG" 'bd create' "and nothing is filed"
run --reason r --requester witness --dog d
eq "$RC" 2 "a missing --owner is a usage error"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
