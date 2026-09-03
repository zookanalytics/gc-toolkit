#!/usr/bin/env bash
# Hermetic test for assets/scripts/upstream-finding.sh — the prepare-only path.
# Stubbed gc and escalate.sh over a JSON store, a real throwaway git repo for
# the origin read, and a `gh` on PATH that fails loudly: this script must never
# reach GitHub, and the log proves it did not.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/upstream-finding.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2' in: $1)" ; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"

cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
STORE="${STUB_STORE:?}"
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
[ "${1:-}" = "bd" ] || { echo "gc stub: unsupported '${1:-}'" >&2; exit 2; }
shift
case "${1:-}" in
  list)
    shift
    statuses=""; fields=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
        --metadata-field=*) fields+=("${1#--metadata-field=}") ;;
      esac
      shift || true
    done
    # An unfiltered listing would hide a status bug, so the stub honours the
    # filter the caller passed and nothing else.
    out=$(jq -c --arg st ",$statuses," '[ .[] | select(.status as $s | $st | contains("," + $s + ",")) ]' "$STORE")
    for f in ${fields[@]+"${fields[@]}"}; do
      k="${f%%=*}"; v="${f#*=}"
      out=$(printf '%s' "$out" | jq -c --arg k "$k" --arg v "$v" '[ .[] | select((.metadata[$k] // "") == $v) ]')
    done
    printf '%s\n' "$out" ;;
  show)
    jq -c --arg id "${2:-}" '[.[] | select(.id == $id)]' "$STORE" ;;
  create)
    shift
    title=""; body=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="${1:-}" ;;
        -d) shift; body="${1:-}" ;;
      esac
      shift || true
    done
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    tmp=$(mktemp)
    jq -c --arg id "up-$n" --arg t "$title" --arg d "$body" \
      '. + [{"id":$id,"status":"open","assignee":"","title":$t,"description":$d,"metadata":{},"notes":""}]' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    printf '{"id":"up-%s"}\n' "$n" ;;
  update)
    shift; id="${1:-}"; shift
    tmp=$(mktemp); cp "$STORE" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          # STUB_DROP_KEYS models a write that reported success and half-landed.
          case ",${STUB_DROP_KEYS:-}," in *",$k,"*) shift || true; continue ;; esac
          jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
            'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
      shift || true
    done
    mv "$tmp" "$STORE"; echo "updated $id" ;;
  dep)
    [ "${2:-}" = "add" ] && printf '%s|%s|%s\n' "${3:-}" "${4:-}" "${5#--type=}" >> "${STUB_DEPS:?}" ;;
  *) echo "gc bd stub: unsupported '${1:-}'" >&2; exit 2 ;;
esac
STUB

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_GH_LOG:?}"
echo "gh stub: upstream-finding must never invoke gh" >&2
exit 99
STUB

ESC="$TMP/escalate.sh"
cat > "$ESC" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_ESC_LOG:?}"
[ -n "${STUB_ESC_RC:-}" ] && { echo "escalate: simulated failure" >&2; exit "$STUB_ESC_RC"; }
subject=""
while [ $# -gt 0 ]; do case "$1" in --subject) shift; subject="${1:-}" ;; esac; shift || true; done
echo "escalate: filed visit vis-1 on $subject"
STUB
chmod +x "$BIN/gc" "$BIN/gh" "$ESC"
export PATH="$BIN:$PATH"
export GC_ESCALATE_TOOL="$ESC"
export STUB_STORE="$TMP/beads.json" STUB_SEQ="$TMP/seq" STUB_DEPS="$TMP/deps.txt"
export STUB_GC_LOG="$TMP/gc.log" STUB_GH_LOG="$TMP/gh.log" STUB_ESC_LOG="$TMP/esc.log"
# A rig inherited from the ambient shell would point the stubs at a live city.
unset GC_RIG

# A real repository, so the own-origin refusal is proved against git's own
# answer rather than a stub's idea of one.
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" remote add origin git@github.com:zookanalytics/gc-toolkit.git
cd "$REPO" || exit 1

reset_state() {
  echo '[]' > "$STUB_STORE"; : > "$STUB_SEQ"
  : > "$STUB_GC_LOG"; : > "$STUB_GH_LOG"; : > "$STUB_ESC_LOG"; : > "$STUB_DEPS"
  unset STUB_ESC_RC STUB_DROP_KEYS
}
meta() { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
count() { jq 'length' "$STUB_STORE"; }

BODY_TEXT='sendSources never reaches the delta log.

`toUIMessageStream()` is called with no options at src/x.ts:264 — the "sources"
flag is dropped. Repro: $(npm test) with sendSources: true.'

# ── the happy path ────────────────────────────────────────────────────────
reset_state
OUT=$("$SUT" --message "Hit while working sl-kg9z6; the bug is in the pinned 0.7.1 runtime." \
  -- gh issue create --repo get-convex/agent --title "sendSources cannot be enabled" --body "$BODY_TEXT" 2>&1)
RC=$?
eq "$RC" "0" "parking a finding exits 0"
eq "$(count)" "1" "exactly one bead is filed"
has "$OUT" "parked issue create on get-convex/agent" "reports what it parked"
has "$OUT" "nothing sent" "says out loud that nothing was sent"
eq "$(meta up-1 gh_target_repo)" "get-convex/agent" "gh_target_repo is the target"
eq "$(meta up-1 gh_verb)" "issue create" "gh_verb is the two-word verb"
eq "$(meta up-1 task_kind)" "upstream-send" "task_kind marks the bead"
eq "$(< "$STUB_GH_LOG" wc -l)" "0" "gh is never invoked"

# The parked command must reassemble into the exact argv, body and all.
PARKED=$(meta up-1 gh_command)
eval "set -- $PARKED"
eq "$#" "9" "the parked command re-splits into the same argument count"
eq "$1" "gh" "argv[0] survives"
eq "$5" "get-convex/agent" "the repo survives"
eq "$9" "$BODY_TEXT" "a multi-line body with backticks, quotes and \$( ) survives verbatim"
case "$PARKED" in *$'\n'*) bad "the parked command is one pasteable line" ;; *) ok "the parked command is one pasteable line" ;; esac

# The bead a human reads carries the command too, not just the metadata.
DESC=$(jq -r '.[] | select(.id == "up-1") | .description' "$STUB_STORE")
has "$DESC" "$PARKED" "the description carries the pasteable command"
has "$DESC" "Hit while working sl-kg9z6" "the description carries the operator's rationale"

# The ask reaches a human, on this bead.
ESC=$(cat "$STUB_ESC_LOG")
has "$ESC" "--subject up-1" "escalate.sh is called on the new bead"
has "$ESC" "--key upstream-send-" "the visit carries the situation key"
has "$OUT" "filed visit vis-1" "the visit line is passed through to the caller"

# ── dedup ─────────────────────────────────────────────────────────────────
: > "$STUB_ESC_LOG"
OUT=$("$SUT" --message "same finding, second pass" \
  -- gh issue create --repo get-convex/agent --title "sendSources cannot be enabled" --body "$BODY_TEXT" 2>&1)
eq "$?" "0" "a repeat run exits 0"
eq "$(count)" "1" "a repeat run files no second bead"
has "$OUT" "already carries this send" "a repeat run says the ask already stands"
has "$(cat "$STUB_ESC_LOG")" "--subject up-1" "the repeat run refreshes the ask on the SAME bead"

# ── an answered ask is not re-asked ───────────────────────────────────────
: > "$STUB_ESC_LOG"
tmp=$(mktemp); jq -c 'map(if .id == "up-1" then .status = "closed" else . end)' "$STUB_STORE" > "$tmp" && mv "$tmp" "$STUB_STORE"
OUT=$("$SUT" --message "third pass, after the operator answered" \
  -- gh issue create --repo get-convex/agent --title "sendSources cannot be enabled" --body "$BODY_TEXT" 2>&1)
eq "$?" "0" "a run against a closed ask exits 0"
eq "$(count)" "1" "a closed ask is not re-filed"
has "$OUT" "a human has answered it" "it says the ask was already answered"
eq "$(< "$STUB_ESC_LOG" wc -l)" "0" "no visit is filed for an answered ask"

# ── a reused key with a different command is a divergence ─────────────────
reset_state
"$SUT" --key sendsources --message "first" \
  -- gh issue create --repo get-convex/agent --title "A" --body "one" >/dev/null 2>&1
OUT=$("$SUT" --key sendsources --message "second" \
  -- gh issue create --repo get-convex/agent --title "B" --body "two" 2>&1)
eq "$?" "2" "a changed command under a reused key is refused"
eq "$(count)" "1" "the divergent run files nothing"
has "$OUT" "DIFFERENT command" "the refusal names the divergence"
has "$OUT" "new --key" "the refusal says how to proceed"

# ── refusals that keep the parked command pasteable ───────────────────────
reset_state
OUT=$("$SUT" --message "why" -- gh issue create --title "T" --body "B" 2>&1)
eq "$?" "2" "a command naming no repository is refused"
eq "$(count)" "0" "nothing is filed for a command with no repository"
has "$OUT" "--repo <owner/name>" "the refusal names the missing flag"

OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --body-file /tmp/body.md 2>&1)
eq "$?" "2" "a --body-file is refused"
has "$OUT" "gone when the command is pasted" "the refusal says why a file path cannot be parked"

OUT=$("$SUT" --message "why" -- "gh issue create --repo a/b --title T" 2>&1)
eq "$?" "2" "a command quoted into one argument is refused"
has "$OUT" "separate arguments after --" "the refusal names the mistake"

OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --repo c/d --title T --body B 2>&1)
eq "$?" "2" "two disagreeing repositories are refused"
has "$OUT" "exactly once" "the refusal asks for one target"

OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --repo a/b --title T --body B 2>&1)
eq "$?" "0" "a repeated but agreeing --repo is accepted"

# A --repo inside a body VALUE is text, not a target.
reset_state
OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title T \
  --body "run it as: gh issue list --repo other/repo" 2>&1)
eq "$?" "0" "a --repo inside a body value does not read as a second target"
eq "$(meta up-1 gh_target_repo)" "a/b" "the target comes from the flag, not the body text"

# ── the own-origin refusal ────────────────────────────────────────────────
reset_state
OUT=$("$SUT" --message "why" -- gh issue create --repo zookanalytics/gc-toolkit --title T --body B 2>&1)
eq "$?" "2" "preparing a send to the rig's own origin is refused"
eq "$(count)" "0" "nothing is filed for our own repo"
has "$OUT" "run the command" "the refusal says to just run it"
OUT=$("$SUT" --message "why" -- gh issue create --repo github.com/ZookAnalytics/GC-Toolkit --title T --body B 2>&1)
eq "$?" "2" "the own-origin match survives host prefix and case"

# ── usage ─────────────────────────────────────────────────────────────────
OUT=$("$SUT" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "2" "--message is required"
OUT=$("$SUT" --message "why" 2>&1)
eq "$?" "2" "a run with no command is refused"
OUT=$("$SUT" --message "why" -- curl -X POST https://example.invalid 2>&1)
eq "$?" "2" "a command that is not gh is refused"
has "$OUT" "must be a \`gh\` invocation" "the refusal names what it accepts"
OUT=$("$SUT" --message "why" --key "bad key" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "2" "a key with characters the dedup read cannot carry is refused"

# ── short flag form ───────────────────────────────────────────────────────
reset_state
"$SUT" --message "why" -- gh issue comment 353 -R get-convex/agent --body "ping" >/dev/null 2>&1
eq "$?" "0" "-R is recognised as --repo"
eq "$(meta up-1 gh_target_repo)" "get-convex/agent" "the -R value is the target"
eq "$(meta up-1 gh_verb)" "issue comment" "a comment verb is labelled as itself"

# ── the pool passthrough ──────────────────────────────────────────────────
reset_state
"$SUT" --message "why" --pool "loomington/gc-toolkit.converse" \
  -- gh issue create --repo a/b --title T --body B >/dev/null 2>&1
has "$(cat "$STUB_ESC_LOG")" "--pool loomington/gc-toolkit.converse" "--pool reaches escalate.sh"

# ── failures that must not report a parked send ───────────────────────────
reset_state
export STUB_ESC_RC=1
OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "1" "a visit that could not be filed fails the run"
has "$OUT" "NO ONE HAS BEEN ASKED" "the failure says the ask never reached a human"
eq "$(count)" "1" "the bead survives the failed escalation, so a re-run reuses it"
unset STUB_ESC_RC

reset_state
export STUB_DROP_KEYS="gh_command"
OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "1" "a command stamp that did not land fails the run"
has "$OUT" "did not read back" "the failure names the unverified stamp"
eq "$(< "$STUB_ESC_LOG" wc -l)" "0" "no human is asked to paste a command that is not on the bead"
unset STUB_DROP_KEYS

reset_state
GC_ESCALATE_TOOL="$TMP/nope.sh" OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "1" "a missing escalate.sh fails the run"
has "$OUT" "NO ONE HAS BEEN ASKED" "a missing escalate.sh says the ask never reached a human"

# ── against the real escalate.sh ──────────────────────────────────────────
# The stub above proves this script's own behaviour; it cannot catch the two
# scripts disagreeing about flags. This case runs the REAL escalate.sh over the
# same stub store, so a drift in either argv contract fails here.
reset_state
OUT=$(GC_ESCALATE_TOOL="$HERE/escalate.sh" GC_RIG=testrig \
  "$SUT" --message "found while working a bead" --pool "testrig/gc-toolkit.converse" \
  -- gh issue create --repo get-convex/agent --title "T" --body "B" 2>&1)
eq "$?" "0" "the real escalate.sh accepts what this script passes it"
VISIT=$(jq -r '[.[] | select((.metadata.task_kind // "") == "visit")] | .[0].id // ""' "$STUB_STORE")
[ -n "$VISIT" ] && ok "the real escalate.sh filed a visit" || bad "the real escalate.sh filed a visit"
eq "$(meta "$VISIT" "gc.continuation_group")" "up-1" "the visit tracks the parked bead"
eq "$(meta "$VISIT" "gc.routed_to")" "testrig/gc-toolkit.converse" "the pool this script passed is the route the visit carries"
has "$(cat "$STUB_DEPS")" "$VISIT|up-1|tracks" "the visit tracks the bead by edge, not only by metadata"
has "$(jq -r --arg id "$VISIT" '.[] | select(.id == $id) | .description' "$STUB_STORE")" \
  "$(meta up-1 gh_command)" "the visit a human reads carries the pasteable command"

eq "$(< "$STUB_GH_LOG" wc -l)" "0" "gh was never invoked by any case"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
