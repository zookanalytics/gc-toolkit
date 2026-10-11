#!/usr/bin/env bash
# Hermetic test for the witness-patrol notice-finding block.
#
# The block turns one inbox mail, a NOTICE or a request for an act the witness
# may not take, into a finding through patrol-finding.sh, and archives the mail
# only once the finding is filed. Archiving first, or archiving on a failed
# filing, is the case where the request is lost with no record: the mail is gone
# and nothing tracks it. So every path that files nothing must leave the mail
# unread for the next cycle.
#
# patrol-finding.sh is stubbed by a wrapper that records its exact argv and then
# runs the real script in --dry-run, so a flag the real parser would refuse
# fails here too. Stubbed gc and git; no live city, Dolt or network. The block
# is instruction text an agent pastes into its own shell, so it also runs under
# strict bash options and, where installed, zsh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
REAL_PF="$ROOT/assets/scripts/patrol-finding.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-notice-finding-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -x "$REAL_PF" ] || { echo "missing $REAL_PF" >&2; exit 1; }

BLOCK="$(awk '
  /^[[:space:]]*# >>> notice-finding[[:space:]]*$/ {f=1; next}
  /^[[:space:]]*# <<< notice-finding[[:space:]]*$/ {f=0}
  f' "$TOML")"
[ -n "$BLOCK" ] && ok "notice-finding block extracted" \
  || bad "notice-finding block EMPTY — markers missing from $TOML"
printf '%s\n' "$BLOCK" > "$TMP/block.sh"
bash -n "$TMP/block.sh" && ok "the block is valid bash" || bad "the block failed bash -n"
# The formula is a TOML basic string, which rewrites a backslash escape. This
# test reads the raw file, so a backslash would make it check text that differs
# from what the witness is handed.
case "$BLOCK" in
  *'\'*) bad "the block carries a backslash, so the tested text is not the text the witness runs" ;;
  *)     ok "the block is backslash-free" ;;
esac

# ── stubs ──────────────────────────────────────────────────────────────
BIN="$TMP/bin"; RIG="$TMP/rig"; NORIG="$TMP/norig"
mkdir -p "$BIN" "$RIG/assets/scripts" "$NORIG/assets/scripts" "$TMP/cwd" "$TMP/home"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
printf 'gc %s\n' "$*" >> "${STUB_LOG:?}"
# Like the real gc, every mail verb refuses an empty id: peek answers "message
# not found" with exit 1 and an error object on stdout.
case "${1:-} ${2:-}" in
  "mail peek"|"mail archive"|"mail mark-unread")
    [ -n "${3:-}" ] || { echo "gc mail ${2}: beadmail get: message not found" >&2; exit 1; } ;;
esac
case "${1:-} ${2:-}" in
  "mail peek")
    if [ -n "${STUB_PEEK_FAIL:-}" ]; then
      echo "gc mail peek: beadmail get: message not found" >&2
      echo '{"schema_version":"1","ok":false,"error":{"code":"command_failed","exit_code":1}}'
      exit 1
    fi
    cat "${STUB_MAIL:?}" ;;
  "mail archive")     exit "${STUB_ARCHIVE_RC:-0}" ;;
  "mail mark-unread") exit 0 ;;
  *) echo "unexpected gc invocation: $*" >&2; exit 99 ;;
esac
STUB
cat > "$BIN/git" <<'STUB'
#!/usr/bin/env bash
exit 128
STUB
# The wrapper records the exact argv as a JSON array, then hands the same argv
# to the real patrol-finding.sh in --dry-run, which parses and validates it and
# exits before any store read.
cat > "$RIG/assets/scripts/patrol-finding.sh" <<'STUB'
#!/usr/bin/env bash
printf 'patrol-finding\n' >> "${STUB_LOG:?}"
for a in "$@"; do printf '%s' "$a" | jq -Rs .; done | jq -sc . > "${PF_ARGS:?}"
[ -n "${STUB_PF_RC:-}" ] && exit "$STUB_PF_RC"
exec "${REAL_PF:?}" "$@" --dry-run
STUB
chmod +x "$BIN/gc" "$BIN/git" "$RIG/assets/scripts/patrol-finding.sh"

# A NOTICE whose body carries everything a shell would rewrite: quotes, a
# parameter, a command substitution, a backslash and blank lines.
mail_json() {  # <subject> -> a `gc mail peek --json` payload
  jq -nc --arg s "$1" '{schema_version:"1", ok:true, message:{
    id:"lx-wisp-m1", from:"gc-toolkit__polecat-lx-wisp-abc",
    to:"gc-toolkit/gc-toolkit.witness", subject:$s,
    body:"Root tk-root is held and blocks the gate.\n\nIt says \"held\", costs $HOME and `date`, and ends in a back\\slash.",
    created_at:"2026-10-05T10:00:00Z", read:false, thread_id:"t-1"}}'
}
WANT_BODY='Root tk-root is held and blocks the gate.

It says "held", costs $HOME and `date`, and ends in a back\slash.'
mail_json "NOTICE: held root tk-root blocks the merge gate" > "$TMP/notice.json"

# run <shell> <prelude> [env assignments...] -> OUT, RC, LOG, ARGS
# env -i drops the city this suite may be running inside, and HOME points at
# scratch, so neither a stray variable nor a shell startup file can route a gc
# call past the stub to a live store.
run() {
  local sh="$1" prelude="$2"; shift 2
  local -a shell=("$sh")
  [ "$sh" = zsh ] && shell=(zsh -f)
  : > "$TMP/log"; rm -f "$TMP/args.json"
  { printf '%s\n' "$prelude"; cat "$TMP/block.sh"; } > "$TMP/run.sh"
  OUT=$(cd "$TMP/cwd" && env -i PATH="$BIN:$PATH" HOME="$TMP/home" STUB_LOG="$TMP/log" \
        PF_ARGS="$TMP/args.json" REAL_PF="$REAL_PF" GC_RIG=gc-toolkit GC_RIG_ROOT="$RIG" \
        GC_CITY_PATH="$TMP/nocity" STUB_MAIL="$TMP/notice.json" "$@" "${shell[@]}" "$TMP/run.sh" 2>&1); RC=$?
  LOG=$(cat "$TMP/log")
  ARGS=$(cat "$TMP/args.json" 2>/dev/null || echo '[]')
}
# arg <flag> -> the value that follows <flag> in the recorded patrol-finding argv
arg() { printf '%s' "$ARGS" | jq -r --arg f "$1" 'index($f) as $i | if $i == null then "<absent>" else .[$i + 1] end'; }
before() {  # <first> <second> -> 0 when <first> is logged before <second>
  awk -v a="$1" -v b="$2" 'index($0, a) && !x {x=NR} index($0, b) && !y {y=NR} END {exit !(x && y && x < y)}' "$TMP/log"
}

BASE='MAIL_ID=lx-wisp-m1; KEY=held-gate-molecule; ABOUT=tk-root'

echo "# a NOTICE that names its bead is filed, then archived"
run bash "$BASE"
eq "$RC" 0 "the block exits 0"
eq "$(arg --scope)" "witness-findings" "filed under the witness's finding scope"
eq "$(arg --key)" "held-gate-molecule" "keyed on the situation the witness named"
eq "$(arg --about)" "tk-root" "scoped to the bead the mail concerns"
eq "$(arg --title)" "held root tk-root blocks the merge gate" "titled by the subject, NOTICE: prefix dropped"
MSG="$(arg --message)"
SOURCE_SEP=$'\n\n## Source'
eq "${MSG%%"$SOURCE_SEP"*}" "$WANT_BODY" "the mail body reaches the finding verbatim"
has "$MSG" "Mail lx-wisp-m1 from gc-toolkit__polecat-lx-wisp-abc, sent 2026-10-05T10:00:00Z." "the finding names the mail, its sender and when it was sent"
has "$MSG" "Subject: NOTICE: held root tk-root blocks the merge gate" "and carries the subject unmodified"
hasnt "$MSG" "## Witness" "no witness section when NOTE is unset"
has "$OUT" "key=held-gate-molecule scope=witness-findings" "the real patrol-finding.sh parser accepted every flag"
has "$OUT" "about=tk-root" "and read the --about"
has "$LOG" "gc mail peek lx-wisp-m1 --json" "the mail is read with peek, which leaves it unread"
has "$LOG" "gc mail archive lx-wisp-m1" "the mail is archived"
before "patrol-finding" "gc mail archive" && ok "the archive comes after the filing" \
  || bad "the mail was archived before the finding was filed"
hasnt "$LOG" "mark-unread" "a filed mail is not returned to the inbox"

echo "# a mail that names no bead files with an empty --about, which the parser reads as none"
run bash 'MAIL_ID=lx-wisp-m1; KEY=held-gate-molecule; ABOUT='
eq "$(arg --about)" "" "the --about value is empty"
has "$OUT" "key=held-gate-molecule scope=witness-findings" "the real parser still accepts it"
hasnt "$OUT" "about=" "and records no about, the same as omitting the flag"
has "$LOG" "gc mail archive lx-wisp-m1" "the mail is archived"
run bash 'MAIL_ID=lx-wisp-m1; KEY=held-gate-molecule'
hasnt "$OUT" "about=" "an unset ABOUT is the same as an empty one"

echo "# NOTE adds what the witness knows, under its own heading"
run bash "$BASE; NOTE='dead-molecule-dispose.sh owns this reap'"
has "$(arg --message)" "## Witness
dead-molecule-dispose.sh owns this reap" "the note follows the mail under a witness heading"

echo "# a subject without the prefix is the title as sent"
mail_json "please reap held root tk-root" > "$TMP/notice.json"
run bash "$BASE"
eq "$(arg --title)" "please reap held root tk-root" "a request with no NOTICE: prefix keeps its subject"
mail_json "NOTICE: " > "$TMP/notice.json"
run bash "$BASE"
eq "$(arg --title)" "NOTICE: " "a subject that is only the prefix falls back to the whole subject, not an empty title"
mail_json "NOTICE: held root tk-root blocks the merge gate" > "$TMP/notice.json"

echo "# a raw control byte in the mail does not make it unreadable"
jq -nc '{schema_version:"1", ok:true, message:{id:"lx-wisp-m1", from:"p", to:"w",
  subject:"NOTICE: raw XX byte", body:"b", created_at:"2026-10-05T10:00:00Z"}}' \
  | sed "s/XX/$(printf '\001')/" > "$TMP/notice.json"
run bash "$BASE"
eq "$(arg --title)" "raw  byte" "the byte is stripped and the mail is filed"
has "$LOG" "gc mail archive lx-wisp-m1" "and archived"
mail_json "NOTICE: held root tk-root blocks the merge gate" > "$TMP/notice.json"

echo "# a filing that fails leaves the mail unread for the next cycle"
run bash "$BASE" STUB_PF_RC=1
has "$LOG" "patrol-finding" "the filing was attempted"
hasnt "$LOG" "gc mail archive" "the mail is NOT archived"
has "$LOG" "gc mail mark-unread lx-wisp-m1" "the mail is returned to the unread inbox"
has "$OUT" "filed nothing for mail lx-wisp-m1" "the witness is told nothing was filed"
eq "$RC" 0 "the patrol step survives the failure"
run bash 'MAIL_ID=lx-wisp-m1; KEY="bad key"; ABOUT=tk-root'
hasnt "$LOG" "gc mail archive" "a key the real parser refuses archives nothing"
has "$LOG" "gc mail mark-unread lx-wisp-m1" "and leaves the mail unread"

echo "# nothing is filed, and nothing archived, when a prerequisite is missing"
run bash 'MAIL_ID=lx-wisp-m1; ABOUT=tk-root'
hasnt "$LOG" "patrol-finding" "no KEY: no filing"
hasnt "$LOG" "gc mail archive" "no KEY: no archive"
has "$OUT" "KEY is unset" "no KEY: the witness is told why"
run bash "$BASE" STUB_PEEK_FAIL=1
hasnt "$LOG" "patrol-finding" "an unreadable mail is not filed blind"
hasnt "$LOG" "gc mail archive" "and is not archived"
has "$OUT" "the mail is unreadable" "and the witness is told why"
run bash "$BASE" GC_RIG_ROOT="$NORIG"
hasnt "$LOG" "gc mail archive" "with no patrol-finding.sh in reach, nothing is archived"
has "$OUT" "patrol-finding.sh is not in the pack" "and the witness is told why"

echo "# a failed archive after a good filing is reported, not hidden"
run bash "$BASE" STUB_ARCHIVE_RC=1
has "$LOG" "patrol-finding" "the finding is filed"
has "$OUT" "did not archive" "the archive failure is reported"
eq "$RC" 0 "and the step survives it"

echo "# the block runs in whatever shell the witness has set up"
for PRELUDE in 'set -e' 'set -euo pipefail'; do
  run bash "$PRELUDE; $BASE"
  has "$LOG" "gc mail archive lx-wisp-m1" "$PRELUDE: a filed mail is archived"
  run bash "$PRELUDE; $BASE" STUB_PF_RC=1
  has "$LOG" "gc mail mark-unread lx-wisp-m1" "$PRELUDE: a failed filing leaves the mail unread"
  hasnt "$LOG" "gc mail archive" "$PRELUDE: and archives nothing"
  run bash "$PRELUDE; $BASE" STUB_PEEK_FAIL=1
  has "$OUT" "the mail is unreadable" "$PRELUDE: an unreadable mail reaches the diagnostic"
  run bash "$PRELUDE; KEY=k"
  has "$OUT" "MAIL_ID is unset" "$PRELUDE: an unset MAIL_ID reaches the diagnostic"
  hasnt "$LOG" "gc mail" "$PRELUDE: and makes no mail call with an empty id"
done

if command -v zsh >/dev/null 2>&1; then
  run bash "$BASE"; BASH_ARGS="$ARGS"
  run zsh "$BASE"
  eq "$ARGS" "$BASH_ARGS" "zsh: the block hands patrol-finding.sh the same argv as bash"
  has "$LOG" "gc mail archive lx-wisp-m1" "zsh: the mail is archived"
  run bash 'MAIL_ID=lx-wisp-m1; KEY=held-gate-molecule; ABOUT='; BASH_ARGS="$ARGS"
  run zsh 'MAIL_ID=lx-wisp-m1; KEY=held-gate-molecule; ABOUT='
  eq "$ARGS" "$BASH_ARGS" "zsh: an empty ABOUT is the same argv as under bash"
  run zsh "$BASE" STUB_PF_RC=1
  hasnt "$LOG" "gc mail archive" "zsh: a failed filing archives nothing"
else
  echo "skip - zsh not installed; the zsh runs are skipped"
fi

echo
echo "notice-finding: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
