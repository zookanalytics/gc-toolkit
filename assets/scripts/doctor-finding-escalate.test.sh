#!/usr/bin/env bash
# Hermetic test for assets/scripts/doctor-finding-escalate.sh — the key and the
# message a doctor finding escalates under.
#
# The subject under test is copied beside a RECORDING escalate.sh stub, so the
# sibling lookup the real script does is what the test exercises, and every
# assertion reads the argv escalate.sh would have received. No live city, no
# network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SUT="$HERE/doctor-finding-escalate.sh"
REAL_ESCALATE="$HERE/escalate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

SDIR="$TMP/scripts"; mkdir -p "$SDIR"
cp "$REAL_SUT" "$SDIR/doctor-finding-escalate.sh"
SUT="$SDIR/doctor-finding-escalate.sh"
ARGV="$TMP/argv"

# Records argv one NUL-free line per argument, so a multi-line --message stays
# readable and the flags stay countable.
cat > "$SDIR/escalate.sh" <<'STUB'
#!/usr/bin/env bash
set -u
: > "${STUB_ARGV:?}"
while [ $# -gt 0 ]; do printf '<<%s>>\n' "$1" >> "$STUB_ARGV"; shift; done
exit "${STUB_ESCALATE_RC:-0}"
STUB
chmod +x "$SDIR/escalate.sh"
export STUB_ARGV="$ARGV"

reset() { : > "$ARGV"; }
# The value escalate.sh would have received for <flag>; empty when unpassed.
argof() {
  awk -v flag="<<$1>>" '
    $0 == flag { grab = 1; next }
    grab { if ($0 ~ /^<<--/ && $0 ~ />>$/) { exit } ; sub(/^<</, ""); sub(/>>$/, ""); print }
  ' "$ARGV"
}
called() { [ -s "$ARGV" ] && echo yes || echo no; }

FINDING='{"name":"gc-toolkit:check-recycle-capable","status":"warning","severity":"blocking","message":"cycle-recycle can never fire","fix_hint":"read the Stop hook","details":["hook reads .input_tokens","the endpoint has no such field"]}'

echo "# the key is derived from .name, not composed by the caller"
reset
out=$("$SUT" --subject tk-triage --finding "$FINDING" 2>&1); rc=$?
eq "$rc" 0 "a well-formed finding escalates"
eq "$(argof --subject)" "tk-triage" "the subject is passed through"
eq "$(argof --key)" "doctor-gc-toolkit-check-recycle-capable" "the key is doctor- plus the slugged check name"
has "$out" "escalates under key" "the derivation is announced"

echo "# one check yields ONE key, whatever the caller's spelling of the object"
# The dedup escalate.sh performs is exact-match on the key, so this is the
# whole guarantee: any two callers holding the same finding must agree.
reset
"$SUT" --subject tk-triage --finding "$FINDING" >/dev/null 2>&1
KEY_A="$(argof --key)"
reset
# Same finding, re-serialised: reordered keys, different whitespace, and piped
# in on stdin rather than passed as a flag.
printf '%s' "$FINDING" | jq '{severity, status, details, name, message, fix_hint}' \
  | "$SUT" --subject tk-triage >/dev/null 2>&1
KEY_B="$(argof --key)"
eq "$KEY_B" "$KEY_A" "a re-serialised finding derives the same key"
reset
printf '  %s  \n' "$FINDING" | "$SUT" --subject tk-other >/dev/null 2>&1
eq "$(argof --key)" "$KEY_A" "surrounding whitespace and a different subject do not move the key"

echo "# every derived key is legal input to escalate.sh"
# The charset is escalate.sh's, read from escalate.sh: a change there must
# fail here rather than silently leave this script deriving rejected keys.
GUARD=$(grep -oE '\*\[!A-Za-z0-9[^]]*\]\*' "$REAL_ESCALATE" | head -n 1)
eq "$GUARD" '*[!A-Za-z0-9._-]*' "escalate.sh still enforces the charset the slug targets"
for n in "rig:gc-toolkit:root-branch" "order-firing-current" "a b/c" "UPPER:Mixed_Case" "x@@@y"; do
  reset
  "$SUT" --subject tk-t --finding "$(jq -nc --arg n "$n" '{name:$n,status:"warning",message:"m"}')" >/dev/null 2>&1
  K="$(argof --key)"
  case "$K" in
    *[!A-Za-z0-9._-]*) bad "key for '$n' is charset-legal (got '$K')" ;;
    "") bad "key for '$n' is charset-legal (nothing was passed)" ;;
    *) ok "key for '$n' is charset-legal ('$K')" ;;
  esac
done
reset
"$SUT" --subject tk-t --finding '{"name":"rig:gc-toolkit:root-branch","status":"warning","message":"m"}' >/dev/null 2>&1
eq "$(argof --key)" "doctor-rig-gc-toolkit-root-branch" "colons become single dashes"
reset
"$SUT" --subject tk-t --finding '{"name":"a::b---c","status":"warning","message":"m"}' >/dev/null 2>&1
eq "$(argof --key)" "doctor-a-b-c" "runs of illegal bytes and dashes collapse to one"

echo "# the message is prose, never the finding object"
reset
"$SUT" --subject tk-triage --finding "$FINDING" >/dev/null 2>&1
MSG="$(argof --message)"
eq "$(head -n 1 <<< "$MSG")" "cycle-recycle can never fire" ".message is the first line, which becomes the visit title"
hasnt "$MSG" '{"name"' "the raw finding object is not the message"
has "$MSG" "check: gc-toolkit:check-recycle-capable" "the body names the check"
has "$MSG" "status: warning" "the body carries the status"
has "$MSG" "severity: blocking" "the body carries the severity"
has "$MSG" "fix hint: read the Stop hook" "the body carries the fix hint"
has "$MSG" "  - hook reads .input_tokens" "the body carries the details"

echo "# absent fields are omitted, and a message-less finding still gets prose"
reset
"$SUT" --subject tk-t --finding '{"name":"bare-check","status":"error"}' >/dev/null 2>&1
MSG="$(argof --message)"
eq "$(head -n 1 <<< "$MSG")" "doctor check bare-check reports error" "a finding with no message gets a prose headline"
hasnt "$MSG" "fix hint:" "an absent fix_hint prints no label"
hasnt "$MSG" "details:" "absent details print no label"
hasnt "$MSG" "severity:" "an absent severity prints no label"

echo "# --pool is passed through, and nothing else is invented"
reset
"$SUT" --subject tk-t --finding "$FINDING" --pool myrig/gc-toolkit.converse >/dev/null 2>&1
eq "$(argof --pool)" "myrig/gc-toolkit.converse" "--pool reaches escalate.sh"
reset
"$SUT" --subject tk-t --finding "$FINDING" >/dev/null 2>&1
hasnt "$(cat "$ARGV")" "<<--pool>>" "no --pool is invented when the caller passed none"

echo "# a finding that names no check files NOTHING"
# An invented key is the free-hand spelling this script removes, so every
# unreadable input must stop before escalate.sh is reached.
# Leaves what the run printed in REFUSE_OUT rather than on stdout: its own
# assertions must count, and a command substitution would run them in a
# subshell where the tallies die.
REFUSE_OUT=""
refuses() { # <label> <expected-rc> <stdin> [args...]
  local label="$1" want="$2" input="$3"; shift 3
  reset
  local rc
  REFUSE_OUT=$(printf '%s' "$input" | "$SUT" "$@" 2>&1); rc=$?
  eq "$rc" "$want" "$label exits $want"
  eq "$(called)" "no" "$label files nothing"
}
refuses "an empty finding" 2 "" --subject tk-t
has "$REFUSE_OUT" "no finding given" "an empty finding says so"
refuses "unparseable JSON" 2 '{"name": ' --subject tk-t
has "$REFUSE_OUT" "does not parse as JSON" "unparseable JSON says so"
refuses "two findings" 2 '{"name":"a","message":"m"}
{"name":"b","message":"m"}' --subject tk-t
has "$REFUSE_OUT" "expected ONE finding, got 2" "two findings are counted and refused"
refuses "a finding with no .name" 2 '{"status":"warning","message":"m"}' --subject tk-t
has "$REFUSE_OUT" "names no check" "a nameless finding says so"
refuses "an empty .name" 2 '{"name":"","status":"warning","message":"m"}' --subject tk-t
has "$REFUSE_OUT" "names no check" "an empty name says so"
refuses "a name with no key-legal byte" 2 '{"name":"///","message":"m"}' --subject tk-t
has "$REFUSE_OUT" "no key-legal byte" "a name that slugs to nothing says so"
refuses "a JSON array of findings" 2 '[{"name":"a","message":"m"}]' --subject tk-t
has "$REFUSE_OUT" "names no check" "an array is not one finding"

echo "# usage"
refuses "a missing --subject" 2 "$FINDING"
has "$REFUSE_OUT" "--subject is required" "the missing flag is named"
refuses "an unknown argument" 2 "$FINDING" --subject tk-t --nonsense
has "$REFUSE_OUT" "unknown argument" "the unknown argument is named"

echo "# a raw control byte in the finding does not cost the escalation"
# doctor details quote bead text, which can carry one; aborting jq here would
# turn a real finding into silence.
reset
printf '{"name":"ctl-check","status":"warning","message":"tab\there","details":["a\tb"]}' \
  | "$SUT" --subject tk-t >/dev/null 2>&1
eq "$(argof --key)" "doctor-ctl-check" "a finding carrying a raw TAB still escalates"
has "$(argof --message)" "tabhere" "the scrubbed message survives"

echo "# escalate.sh's exit code is the script's"
reset
STUB_ESCALATE_RC=1 "$SUT" --subject tk-t --finding "$FINDING" >/dev/null 2>&1; rc=$?
eq "$rc" 1 "a refusal from escalate.sh is reported, not swallowed"

echo "# escalate.sh must be beside the script"
reset
LONE="$TMP/lone"; mkdir -p "$LONE"; cp "$REAL_SUT" "$LONE/"
out=$("$LONE/doctor-finding-escalate.sh" --subject tk-t --finding "$FINDING" 2>&1); rc=$?
eq "$rc" 1 "a missing escalate.sh exits 1"
has "$out" "not beside this script" "and says what is missing"

echo
echo "doctor-finding-escalate.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
