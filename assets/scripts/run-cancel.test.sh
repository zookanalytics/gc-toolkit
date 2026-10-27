#!/usr/bin/env bash
# Hermetic test for assets/scripts/run-cancel.sh.
#
# The constraint: a molecule's lifecycle is gascity's, so a run that should not
# continue ends through gascity's run cancel and the pack writes none of the
# molecule's beads. The script sends one POST to the supervisor and appends its
# reason to the step this session holds; nothing else is written.
#
# What is exercised here:
#   * the REQUEST: POST /v0/city/<city>/runs/<root>/cancel at the address
#     $GC_HOME/supervisor.toml gives, carrying the X-GC-Request header gascity
#     requires on a mutation, for the city cities.toml registers at
#     $GC_CITY_PATH;
#   * --step resolves the run from this session's step (in_progress, then open,
#     then blocked; --bead a verified hint) and --root takes it as given;
#   * NO MEMBER WRITE: the one bd write on any path is the reason appended to
#     the held step in --step mode, once the run has ended, so an attempt that
#     does not end it writes nothing;
#   * the ANSWERS: 202 ends the run; 409 is a run already terminal once its root
#     reads closed again, whose open leftovers gascity's `gc convoy delete
#     --force` closes, unless one carries a branch or a merge_result; a 409 for
#     a root that still reads live ends nothing and closes nothing; 404 is not
#     ended; a 5xx or a failed connection is retried and then not ended;
#   * the CITY: GC_CITY_PATH names it, else `gc status`, so a caller outside a
#     session (an operator's shell running gc-helm.sh) reaches the same city;
#   * refusals with no request and no write: no identity, an ambiguous step, a
#     step naming no root, a bead that is not a workflow root, usage errors;
#   * the SUBSTRING trap: session hq-zzk must not own hq-zzk9's bead.
#
# No live city, Dolt, network, or beads: a tmpdir, a `gc` stub over a JSON
# store, a `curl` stub that answers from a queue, and the script itself.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/run-cancel.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-run-cancel-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }

# The suite owns the environment: a live session's GC_* would otherwise name a
# real city and a real session.
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
mkdir -p "$TMP/bin" "$TMP/home"

# --- gc stub over a mutable JSON store. --------------------------------------
# `bd show`   : the bead as a one-element array (unknown id -> an error object).
# `bd list`   : filters on --status= (comma list), --assignee= and
#               --metadata-field k=v.
# `bd update` : applies --append-notes; any other flag is recorded and refused,
#               because this script writes nothing but a note.
# `convoy delete <root> --force` : closes every live bead whose
#               gc.root_bead_id is <root>, or exits $FAKE_DELETE_RC.
# `status`    : answers $FAKE_STATUS, or fails when it is unset.
# Every invocation is appended verbatim to $GC_LOG.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
set -u
S="${FAKE_STORE:?}"
printf '%s\n' "$*" >> "${GC_LOG:?}"
if [ "${1:-}" = "convoy" ] && [ "${2:-}" = "delete" ]; then
  [ -n "${FAKE_DELETE_RC:-}" ] && { echo "gc: simulated convoy delete failure" >&2; exit "$FAKE_DELETE_RC"; }
  case " $* " in *" --force "*) ;; *) echo "Dry run."; exit 0 ;; esac
  jq -c --arg r "${3:-}" 'map(if (.metadata["gc.root_bead_id"] // "") == $r and .status != "closed"
                              then .status = "closed" | .metadata["gc.outcome"] = "skipped" else . end)' "$S" > "$S.n" && mv "$S.n" "$S"
  exit 0
fi
if [ "${1:-}" = "status" ]; then
  [ -n "${FAKE_STATUS:-}" ] || { echo "gc: no city here (stub)" >&2; exit 1; }
  printf '%s\n' "$FAKE_STATUS"; exit 0
fi
[ "${1:-}" = "bd" ] || { echo "gc stub: unsupported '$*'" >&2; exit 2; }
shift
verb="${1:-}"; shift || true
case "$verb" in
  show)
    out=$(jq -c --arg id "${1:-}" '[ .[] | select(.id == $id) ]' "$S")
    if [ "$out" = "[]" ]; then printf '{"error":"no issue found matching %s"}\n' "${1:-}"; else printf '%s\n' "$out"; fi ;;
  list)
    wstatus=""; wassignee=""; mk=""; mv=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*)   wstatus="${1#--status=}" ;;
        --assignee=*) wassignee="${1#--assignee=}" ;;
        --metadata-field) shift; mk="${1%%=*}"; mv="${1#*=}" ;;
      esac
      shift
    done
    jq -c --arg st "$wstatus" --arg as "$wassignee" --arg mk "$mk" --arg mv "$mv" '
      [ .[]
        | (.status // "open") as $bst
        | select($st == "" or (($st | split(",")) | index($bst)))
        | select($as == "" or ((.assignee // "") == $as))
        | select($mk == "" or ((.metadata[$mk] // "") == $mv)) ]' "$S" ;;
  update)
    id="${1:-}"; shift || true
    note=""; other=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --append-notes) shift; note="${1:-}" ;;
        --json) ;;
        *) other="$other $1" ;;
      esac
      shift || true
    done
    if [ -n "$other" ]; then echo "gc stub: refused update of $id:$other" >&2; exit 1; fi
    jq -c --arg id "$id" --arg n "$note" 'map(if .id == $id then .notes = ((.notes // "") + $n) else . end)' "$S" > "$S.n" && mv "$S.n" "$S"
    echo "✓ Updated issue: $id" ;;
  *) echo "gc stub: unsupported 'bd $verb'" >&2; exit 2 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- curl stub. ---------------------------------------------------------------
# Records "<method> <url> <header>" per call and answers from $FAKE_CURL_QUEUE,
# one "<code> <json body>" per line, consumed in order; an exhausted queue
# repeats its last line. Code 000 is a failed connection: no body, exit 7. A
# request without the X-GC-Request header is answered 403, as gascity answers it.
# With $FAKE_409_CLOSES set, a 409 also closes that root in the store, the way a
# run that ended between the script's read and its request looks.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/curl" <<'CURL'
set -u
out=""; fmt=""; method="GET"; hdr=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) shift; out="$1" ;;
    -w) shift; fmt="$1" ;;
    -X) shift; method="$1" ;;
    -H) shift; hdr="$hdr$1;" ;;
    --max-time) shift ;;
    -s) ;;
    *) url="$1" ;;
  esac
  shift
done
printf '%s %s %s\n' "$method" "$url" "$hdr" >> "${CURL_LOG:?}"
Q="${FAKE_CURL_QUEUE:?}"
line=$(head -n 1 "$Q")
[ "$(wc -l < "$Q" | tr -d ' ')" -gt 1 ] && { tail -n +2 "$Q" > "$Q.n" && mv "$Q.n" "$Q"; }
code="${line%% *}"; body="${line#* }"
case "$hdr" in *"X-GC-Request:"*) ;; *) code=403; body='{"title":"Forbidden","status":403,"detail":"csrf: X-GC-Request header required on mutation endpoints"}' ;; esac
if [ "$code" = "000" ]; then printf '000'; exit 7; fi
# A 409 for a run that ended between the script's read and its request.
if [ "$code" = "409" ] && [ -n "${FAKE_409_CLOSES:-}" ]; then
  jq -c --arg r "$FAKE_409_CLOSES" 'map(if .id == $r then .status = "closed" else . end)' "$FAKE_STORE" > "$FAKE_STORE.c" && mv "$FAKE_STORE.c" "$FAKE_STORE"
fi
[ -n "$out" ] && printf '%s' "$body" > "$out"
[ "$fmt" = '%{http_code}' ] && printf '%s' "$code"
exit 0
CURL
chmod +x "$TMP/bin/curl"

export PATH="$TMP/bin:$PATH"
export FAKE_STORE="$TMP/store.json" GC_LOG="$TMP/gc.log" CURL_LOG="$TMP/curl.log" FAKE_CURL_QUEUE="$TMP/queue"
export GC_HOME="$TMP/home" GC_RUN_CANCEL_BACKOFF=0
cat > "$GC_HOME/cities.toml" <<'TOML'
[[cities]]
  path = "/srv/elsewhere"
  name = "other"

[[cities]]
  path = "/srv/town"
  name = "mycity"
TOML
export GC_CITY_PATH="/srv/town"

MINE="gc-toolkit__polecat-hq-98h2m"
export GC_SESSION_NAME="$MINE" GC_SESSION_ID="hq-98h2m"

STEP="mol-polecat-work.load-context"
URL="http://127.0.0.1:8372/v0/city/mycity/runs/tk-root/cancel"

# The live molecule shape: a routed root, this session's in_progress load-context,
# pre-assigned open siblings, the dispatcher's finalize step; and an unrelated
# bead of a substring-sharing session.
reset() {
  cat > "$FAKE_STORE" <<JSON
[
 {"id":"tk-root","status":"in_progress","assignee":"","metadata":{"gc.kind":"workflow","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.input_convoy_id":"tk-cv"}},
 {"id":"tk-lc","status":"in_progress","assignee":"$MINE","metadata":{"gc.step_ref":"$STEP","gc.root_bead_id":"tk-root","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
 {"id":"tk-ws","status":"open","assignee":"$MINE","metadata":{"gc.step_ref":"mol-polecat-work.workspace-setup","gc.root_bead_id":"tk-root","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
 {"id":"tk-fin","status":"open","assignee":"","metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.root_bead_id":"tk-root","gc.routed_to":"gc-toolkit/core.control-dispatcher"}},
 {"id":"tk-work","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}},
 {"id":"tk-other","status":"in_progress","assignee":"${MINE}9","metadata":{"gc.step_ref":"$STEP","gc.root_bead_id":"tk-root2"}},
 {"id":"tk-root2","status":"in_progress","assignee":"","metadata":{"gc.kind":"workflow"}}
]
JSON
  : > "$GC_LOG"; : > "$CURL_LOG"
  printf '%s\n' "${1:-202 {\"run_id\":\"tk-root\",\"status\":\"canceled\",\"closed\":4}}" > "$FAKE_CURL_QUEUE"
}
run() { OUT=$("$SCRIPT" "$@" 2>&1); RC=$?; }
writes()   { grep -E '^bd update' "$GC_LOG" || true; }
calls()    { wc -l < "$CURL_LOG" | tr -d ' '; }
bnotes()   { jq -r --arg i "$1" '(.[] | select(.id == $i) | .notes) // ""' "$FAKE_STORE"; }
bstatus()  { jq -r --arg i "$1" '(.[] | select(.id == $i) | .status) // "<absent>"' "$FAKE_STORE"; }

# ── 1. --step: the run of this session's step, one POST, one note ────────────
reset
run --step "$STEP" --reason "duplicate dispatch: tk-work already in flight"
eq "$RC" 0 "--step: a 202 ends the run"
eq "$(calls)" 1 "--step: exactly one request"
has "$(cat "$CURL_LOG")" "POST $URL " "--step: POST to the run cancel of the step's root, in the city cities.toml names"
has "$(cat "$CURL_LOG")" "X-GC-Request:" "--step: the request carries gascity's anti-CSRF header"
has "$OUT" "cancelled run tk-root (4 beads closed): duplicate dispatch" "--step: the result line names the run, the count and the reason"
eq "$(writes)" "bd update tk-lc --append-notes Declined at $STEP by $MINE: duplicate dispatch: tk-work already in flight. Run tk-root cancelled through gascity (4 beads closed)." \
  "--step: the only write is the reason on the held step, naming what the cancel did"
for b in tk-root tk-ws tk-fin tk-work; do eq "$(bnotes "$b")" "" "--step: $b is not written"; done
eq "$(bstatus tk-lc)" "in_progress" "--step: the script closes nothing itself; gascity's cancel does"

# ── 2. --root: no step held, no write at all ─────────────────────────────────
reset
run --root tk-root --reason "stood down by the sitting"
eq "$RC" 0 "--root: a 202 ends the run"
has "$(cat "$CURL_LOG")" "POST $URL " "--root: POST to the named run"
eq "$(writes)" "" "--root: nothing is written"

# ── 3. --bead: a verified hint wins; a foreign one is ignored ─────────────────
reset
cat > "$TMP/store2.json" <<JSON
[
 {"id":"tk-rootA","status":"in_progress","assignee":"","metadata":{"gc.kind":"workflow"}},
 {"id":"tk-rootB","status":"in_progress","assignee":"","metadata":{"gc.formula_contract":"graph.v2"}},
 {"id":"tk-a","status":"in_progress","assignee":"$MINE","metadata":{"gc.step_ref":"$STEP","gc.root_bead_id":"tk-rootA"}},
 {"id":"tk-b","status":"in_progress","assignee":"$MINE","metadata":{"gc.step_ref":"$STEP","gc.root_bead_id":"tk-rootB"}}
]
JSON
cp "$TMP/store2.json" "$FAKE_STORE"
run --step "$STEP" --bead tk-b --reason r
eq "$RC" 0 "--bead: a verified hint resolves two same-step beads"
has "$(cat "$CURL_LOG")" "/runs/tk-rootB/cancel" "--bead: the hint's root is cancelled (a graph.v2-contract root counts)"
cp "$TMP/store2.json" "$FAKE_STORE"; : > "$CURL_LOG"; : > "$GC_LOG"
run --step "$STEP" --reason r
eq "$RC" 2 "ambiguous: two in_progress beads for the step and no hint are refused"
eq "$(calls)" 0 "ambiguous: no request"
eq "$(writes)" "" "ambiguous: no write"
reset
run --step "$STEP" --bead tk-other --reason r
eq "$RC" 0 "a foreign --bead is ignored and the store resolves this session's step"
has "$OUT" "NOTE: --bead tk-other is not this session's" "a foreign --bead is reported"
has "$(cat "$CURL_LOG")" "/runs/tk-root/cancel" "a foreign --bead: this session's root, not the hint's"

reset
run --step "$STEP" --bead "<the bead_id your gc hook --claim returned>" --reason r
eq "$RC" 0 "a placeholder --bead is ignored and the store resolves this session's step"
has "$OUT" "is not a bead id; resolving from the store" "a placeholder --bead is reported"
has "$(cat "$CURL_LOG")" "/runs/tk-root/cancel" "a placeholder --bead: this session's root"

# ── 4. tiers: open, then blocked ─────────────────────────────────────────────
reset
jq -c 'map(if .id == "tk-lc" then .status = "blocked" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run --step "$STEP" --reason r
eq "$RC" 0 "a step this session already blocked still names its run"
has "$(cat "$CURL_LOG")" "/runs/tk-root/cancel" "blocked tier: the step's root"

# ── 5. the substring trap ────────────────────────────────────────────────────
reset
export GC_SESSION_NAME="gc-toolkit__polecat-hq-98h2" GC_SESSION_ID="hq-98h2"
run --step "$STEP" --reason r
eq "$RC" 2 "substring: session hq-98h2 owns none of hq-98h2m's beads"
eq "$(calls)" 0 "substring: no request"
export GC_SESSION_NAME="$MINE" GC_SESSION_ID="hq-98h2m"

# ── 6. refusals: no identity, no root, not a root ────────────────────────────
reset
OUT=$(env -u GC_SESSION_NAME -u GC_SESSION_ID "$SCRIPT" --step "$STEP" --reason r 2>&1); RC=$?
eq "$RC" 2 "no identity: refused"
has "$OUT" "no session identity" "no identity: says why"
eq "$(calls)" 0 "no identity: no request"
reset
jq -c 'map(if .id == "tk-lc" then (.metadata |= del(.["gc.root_bead_id"])) else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run --step "$STEP" --reason r
eq "$RC" 2 "a step naming no root is refused"
eq "$(calls)" 0 "no root: no request"
reset
run --root tk-lc --reason r
eq "$RC" 2 "--root naming a step, not a workflow root, is refused"
eq "$(calls)" 0 "not a root: no request"
reset
run --root tk-nosuch --reason r
eq "$RC" 1 "--root naming no bead: an unread root is not ended"
eq "$(calls)" 0 "no bead: no request"

# ── 7. a run already over: its root is closed ────────────────────────────────
TERMINAL='409 {"title":"Wrong State Conflict","status":409,"detail":"run tk-root is already terminal; nothing to cancel"}'
close_root()  { jq -c 'map(if .id == "tk-root" then .status = "closed" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"; }
close_chain() { jq -c 'map(if (.id == "tk-root" or (.metadata["gc.root_bead_id"] // "") == "tk-root") then .status = "closed" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"; }
reset; close_chain
run --root tk-root --reason r
eq "$RC" 0 "a closed root with every member closed: the run had already ended"
has "$OUT" "had already ended" "an ended run: says so"
eq "$(calls)" 0 "an ended run: no cancel is sent, since gascity cancels no terminal run"
hasnt "$(cat "$GC_LOG")" "convoy delete" "an ended run with nothing open: no convoy delete"

reset; close_root
OUT=$(env -u GC_CITY_PATH "$SCRIPT" --root tk-root --reason r 2>&1); RC=$?
eq "$RC" 0 "a closed root with members left open: gascity closes them, no city needed"
eq "$(calls)" 0 "leftovers under a closed root: no cancel is sent"
has "$(cat "$GC_LOG")" "convoy delete tk-root --force" "leftovers: gc convoy delete <root> --force"
for b in tk-lc tk-ws tk-fin; do eq "$(bstatus "$b")" "closed" "leftovers: $b closed"; done
eq "$(bstatus tk-work)" "open" "leftovers: the work bead, which names no root, is untouched"
eq "$(writes)" "" "leftovers: the script itself writes nothing"

reset "$TERMINAL"
OUT=$(FAKE_409_CLOSES=tk-root "$SCRIPT" --root tk-root --reason r 2>&1); RC=$?
eq "$RC" 0 "a root that read live and answers 409 having ended in the meantime: its leftovers are closed"
eq "$(calls)" 1 "a 409: one request, not retried"
has "$(cat "$GC_LOG")" "convoy delete tk-root --force" "a 409: the members left open are closed through gascity"

# A 409 that the root does not bear out is not read as an ended run.
reset "$TERMINAL"
run --root tk-root --reason r
eq "$RC" 1 "a 409 for a root that still reads live: not ended"
has "$OUT" "still reads 'in_progress'" "a 409 for a live root: names what the root reads"
has "$OUT" "already terminal; nothing to cancel" "a 409 for a live root: gascity's detail is reported"
hasnt "$(cat "$GC_LOG")" "convoy delete" "a 409 for a live root: nothing is closed by hand"
eq "$(bstatus tk-root) $(bstatus tk-lc) $(bstatus tk-ws) $(bstatus tk-fin)" "in_progress in_progress open open" \
  "a 409 for a live root: the root and every step keep their status"
reset "$TERMINAL"
run --step "$STEP" --reason r
eq "$RC" 1 "--step, a 409 for a live root: not ended"
eq "$(writes)" "" "--step, a 409 for a live root: no note, since the run did not end"

# In --step mode the note lands once a run already over has its leftovers closed.
reset; close_root
run --step "$STEP" --reason "work already delivered"
eq "$RC" 0 "--step on a closed root with leftovers: ended"
eq "$(writes)" "bd update tk-lc --append-notes Declined at $STEP by $MINE: work already delivered. Run tk-root had already ended; gascity closed the 3 member(s) it left open." \
  "--step on a closed root: the note says the run had already ended"

reset; close_root
jq -c 'map(if .id == "tk-ws" then .metadata.merge_result = "pull_request" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run --root tk-root --reason r
eq "$RC" 2 "a leftover carrying a merge_result: refused, nothing written"
has "$OUT" "tk-ws carries a branch or a merge_result" "a work-bead leftover is named"
hasnt "$(cat "$GC_LOG")" "convoy delete tk-root --force" "a work-bead leftover: no convoy delete"

reset; close_root
OUT=$(FAKE_DELETE_RC=1 "$SCRIPT" --root tk-root --reason r 2>&1); RC=$?
eq "$RC" 1 "leftovers and a failed convoy delete: not ended"

# --ended: the caller read the root as closed and ends only what it left open.
reset; close_root
run --root tk-root --reason r --ended
eq "$RC" 0 "--ended on a closed root: its leftovers are closed"
has "$(cat "$GC_LOG")" "convoy delete tk-root --force" "--ended: through gascity"
reset
run --root tk-root --reason r --ended
eq "$RC" 2 "--ended on a root that reads live: refused rather than cancelled"
eq "$(calls)" 0 "--ended on a live root: no cancel is sent"
hasnt "$(cat "$GC_LOG")" "convoy delete" "--ended on a live root: nothing is closed"
run --step "$STEP" --reason r --ended
eq "$RC" 2 "--ended with --step: usage refused"

# ── 8. 404 and the retried failures ──────────────────────────────────────────
reset '404 {"status":404,"detail":"run not found: tk-root"}'
run --root tk-root --reason r
eq "$RC" 1 "404: not ended"
has "$OUT" "run not found: tk-root" "404: gascity's detail is reported"
eq "$(calls)" 1 "404: not retried"

reset '503 {"status":503,"detail":"run cancel failed: store busy"}'
printf '%s\n' '202 {"closed":2}' >> "$FAKE_CURL_QUEUE"
run --root tk-root --reason r
eq "$RC" 0 "a 503 then a 202: ended on the retry"
eq "$(calls)" 2 "503 then 202: two requests"

reset '503 {"status":503,"detail":"run cancel failed: store busy"}'
run --step "$STEP" --reason r
eq "$RC" 1 "--step, 503 on every attempt: not ended"
eq "$(writes)" "" "--step, 503 on every attempt: no note, so a retry adds none either"

reset '503 {"status":503,"detail":"run cancel failed: store busy"}'
run --root tk-root --reason r
eq "$RC" 1 "503 on every attempt: not ended"
eq "$(calls)" 3 "503: three attempts by default"
has "$OUT" "store busy" "503: gascity's detail is reported"

reset '000 '
run --root tk-root --reason r
eq "$RC" 1 "no connection on every attempt: not ended"
eq "$(calls)" 3 "no connection: retried"
has "$OUT" "no connection" "no connection: said plainly"

reset '400 {"status":400,"detail":"bad"}'
run --root tk-root --reason r
eq "$RC" 1 "an unexpected 4xx: not ended, not retried"
eq "$(calls)" 1 "4xx: one request"

# ── 9. the address and the city ──────────────────────────────────────────────
reset
printf '[supervisor]\nbind = "0.0.0.0"\nport = 9911\n\n[other]\nport = 1\n' > "$GC_HOME/supervisor.toml"
run --root tk-root --reason r
has "$(cat "$CURL_LOG")" "POST http://127.0.0.1:9911/v0/city/mycity/runs/tk-root/cancel" "supervisor.toml: a wildcard bind is loopback, the port is [supervisor]'s"
reset
printf '[supervisor]\nbind = "::1"\n' > "$GC_HOME/supervisor.toml"
run --root tk-root --reason r
has "$(cat "$CURL_LOG")" "POST http://[::1]:8372/" "supervisor.toml: an IPv6 bind is bracketed"
rm -f "$GC_HOME/supervisor.toml"
reset
OUT=$(GC_CITY_PATH=/srv/unlisted/ "$SCRIPT" --root tk-root --reason r 2>&1); RC=$?
has "$(cat "$CURL_LOG")" "/v0/city/unlisted/runs/" "an unregistered city path falls back to its basename"
reset
OUT=$(env -u GC_CITY_PATH FAKE_STATUS='{"city_path":"/srv/town","city_name":"ignored"}' "$SCRIPT" --root tk-root --reason r 2>&1); RC=$?
eq "$RC" 0 "no city path in the environment: gc status names it"
has "$(cat "$CURL_LOG")" "POST $URL " "gc status's city path is named as cities.toml registers it"
reset
OUT=$(env -u GC_CITY_PATH "$SCRIPT" --root tk-root --reason r 2>&1); RC=$?
eq "$RC" 1 "no city path and none from gc status: not ended"
has "$OUT" "none from gc status" "no city: says where it looked"
eq "$(calls)" 0 "no city path: no request"

# ── 10. dry run and usage ────────────────────────────────────────────────────
reset
run --step "$STEP" --reason r --dry-run
eq "$RC" 0 "dry run: exit 0"
has "$OUT" "DRY RUN: would cancel run tk-root" "dry run: names the run"
eq "$(calls)" 0 "dry run: no request"
eq "$(writes)" "" "dry run: no write"

reset
for args in "--step $STEP --root tk-root --reason r" "--reason r" "--step $STEP" "--root tk-root --reason" "--step {{step}} --reason r" "--root tk-root --reason r --bogus"; do
  # shellcheck disable=SC2086  # each case is a word list on purpose
  run $args
  eq "$RC" 2 "usage refused: $args"
done
eq "$(calls)" 0 "usage: no request on any refusal"
eq "$(writes)" "" "usage: no write on any refusal"

echo
echo "run-cancel.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
