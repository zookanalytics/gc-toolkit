#!/usr/bin/env bash
# Hermetic test for escalation-gate.sh (tk-z4aka / lx-b5aev). Stubs `gc`
# (bd show, bd update, mail send) on PATH. No live city, Dolt, mail, or network.
#
# The gate sends an anchor-scoped escalation AT MOST ONCE per distinct situation
# instead of once per patrol cycle. Covered:
#   (FIRST)    no prior stamp -> mails, and records escalated.<kind>=<state>@<now>
#   (SUPPRESS) same anchor + same state, inside the cooldown -> NO mail, and no
#              write either; the verdict still prints so the log shows it stuck
#   (DRIFT)    THE REGRESSION: the five real PR #35 subjects, one anchor, one
#              unchanged state -> exactly ONE mail. Dedup must key on the anchor
#              and channel, never the message, because an LLM reframes the
#              subject every cycle
#   (CHANGED)  a different state fingerprint -> mails again immediately; the gate
#              hides repetition, never news
#   (COLLIDE)  two DIFFERENT raw states that render to the same display-safe
#              label ("abc/123" and "abc 123") must still compare as different.
#              A lossy token would suppress them as identical — the mute the
#              state fingerprint exists to prevent, wearing the gate's badge
#   (COOLDOWN) unchanged state older than --cooldown -> mails again, so an item
#              stuck for days resurfaces instead of going silent forever
#   (ORDER)    the stamp is written BEFORE the mail — the ability to record the
#              escalation is the license to send it
#   (STAMPFAIL) the stamp is refused -> NOTHING is mailed, exit 1; an unbounded
#              storm is strictly worse than a late escalation
#   (MAILFAIL) the send fails after the stamp landed -> the stamp is ROLLED BACK
#              and exit 1, so the situation is not recorded as "already
#              escalated" while the mayor was never told...
#   (RETRY)    ...and the very next run therefore still mails
#   (RESTORE)  rollback restores a PREVIOUS stamp value rather than unsetting it
#   (NOANCHOR) unreadable anchor -> nowhere to bound the escalation -> no mail
#   (CORRUPT)  a malformed prior stamp -> re-escalates and rewrites it well-formed
#              (treating it as "recent" would mute the anchor forever)
#   (FORCE)    --force bypasses suppression but still stamps
#   (DRY)      --dry-run: no stamp, no mail, verdict printed
#   (KIND)     a different --kind is an independent channel
#   (CTRL)     control characters in the bead's notes must not break the metadata
#              read — a lost parse would look like a lost stamp and mail EVERY
#              cycle, which is the original bug. Covers a raw TAB and CR as well
#              as \001: jq rejects the WHOLE C0 range, and prose notes are exactly
#              where a tab comes from
#   (PARALLEL) THE RACE: two simultaneous FIRST escalations for one anchor both
#              read "no prior stamp" before either writes, and both mail. At most
#              once has to hold under concurrency too, so the read/decide/stamp/
#              send section runs under an anchor+kind mutex
#   (LOCKWAIT) a peer holding the lock is WAITED for, not guessed at, so the
#              mutex actually serializes rather than merely detecting contention
#   (HELD)     THE REGRESSION: a live lock used to end this run at SUPPRESSED
#              before it read the anchor or its own --state. A lock orders
#              decisions; it cannot make one on a peer's behalf, so a holder that
#              outlasts the bounded wait sends us down the unserialized path —
#              which still reads, compares and decides
#   (NEWS)     ...and why that mattered: peer suppressing an unchanged "old" while
#              this run carries "new" produced ZERO mail between them. A changed
#              state must escalate through a peer's lock
#   (NEWSPARALLEL) the same, genuinely concurrent, with different --state values
#   (STALEBREAK) a lock left behind by a killed holder is broken, not obeyed — a
#              dead peer must never mute an anchor forever
#   (RELEASE)  the lock is released on every exit path, including the failures
#   (DRYLOCK)  --dry-run takes no lock, so a probe cannot suppress a real send
#   (LOCKFREE) an unusable lock root proceeds UNSERIALIZED with a warning: a
#              duplicate mail is recoverable, silence is not
#   (OPTDRIFT) structural: every option the parse loop handles is in
#              require_value's known-option list, or `--body --newopt` silently
#              eats the new flag as a value
#   (USAGE)    missing required arguments -> exit 2, nothing sent
#   (KINDSAFE) --kind becomes the metadata KEY `escalated.<kind>`, so a value
#              carrying '=' or whitespace would write a key nothing can read
#              back — the channel would stop deduplicating silently
#   (ARGEND)   THE HANG: a value-taking option LAST in argv used to leave argv
#              untouched (`shift 2` fails without `set -e`) and spin the parse
#              loop forever. Every such option must exit 2 instead — a patrol
#              pass that hangs is worse than the storm this script replaces
#   (WATCHDOG) the time bound ARGEND runs under must not need GNU `timeout`, and
#              its portable fallback is exercised on every platform: on the one
#              where `timeout` is absent, an unbounded fallback would make THIS
#              TEST the hang it exists to catch, and a hung suite reports nothing
#   (ARGFLAG)  `--body --dry-run` must not store the flag as the body
#   (ARGSHAPE) structural: every value-taking arm calls require_value, so a
#              future option cannot reintroduce the hang uncovered
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/escalation-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"
export GATE_STATE="$TMP/state"
export PATH="$TMP/bin:$PATH"
# Keep the anchor+kind mutex inside this run's tmpdir. Sharing the real
# /tmp/gc-escalation-gate would let two concurrent test runs — or a live witness
# patrolling the same anchor id — suppress each other's cases.
export GC_ESCALATION_GATE_LOCKDIR="$TMP/locks"
LOCK="$GC_ESCALATION_GATE_LOCKDIR/su-lou.10.8.witness.lock"

# --- Stub `gc` ----------------------------------------------------------------
# Backed by a state dir so each case can seed metadata and force failures:
#   meta          "<anchor>|<key>|<value>" lines — the anchor's metadata
#   calls         ordered log of every gc invocation the gate made
#   raw_show      if present, emitted verbatim as `gc bd show` output (used to
#                 reproduce bd's real control-character corruption)
#   missing       if present, `gc bd show` fails (unreadable anchor)
#   refuse_update if present, every `gc bd update` fails
#   fail_mail     if present, every `gc mail send` fails
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
S="$GATE_STATE"
printf '%s\n' "$*" >> "$S/calls"

if [ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ]; then
  [ -f "$S/missing" ] && exit 1
  # Widen the critical section so two concurrent runs genuinely overlap inside it
  # (PARALLEL). Without this the winner can finish before the loser even starts,
  # and the race the mutex exists for is never exercised.
  [ -f "$S/slow_show" ] && sleep 1
  if [ -f "$S/raw_show" ]; then cat "$S/raw_show"; exit 0; fi
  id="$3"
  meta='{}'
  while IFS='|' read -r a k v; do
    [ "$a" = "$id" ] || continue
    meta=$(printf '%s' "$meta" | jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}')
  done < "$S/meta"
  jq -nc --arg id "$id" --argjson meta "$meta" '[{id:$id, metadata:$meta}]'
  exit 0
fi

if [ "${1:-}" = "bd" ] && [ "${2:-}" = "update" ]; then
  [ -f "$S/refuse_update" ] && exit 1
  id="$3"; shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --set-metadata)
        kv="$2"; k="${kv%%=*}"; v="${kv#*=}"
        grep -v "^$id|$k|" "$S/meta" > "$S/meta.new" 2>/dev/null || true
        mv "$S/meta.new" "$S/meta"
        printf '%s|%s|%s\n' "$id" "$k" "$v" >> "$S/meta"
        shift 2 ;;
      --unset-metadata)
        k="$2"
        grep -v "^$id|$k|" "$S/meta" > "$S/meta.new" 2>/dev/null || true
        mv "$S/meta.new" "$S/meta"
        shift 2 ;;
      *) shift ;;
    esac
  done
  exit 0
fi

if [ "${1:-}" = "mail" ] && [ "${2:-}" = "send" ]; then
  [ -f "$S/fail_mail" ] && exit 1
  exit 0
fi
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- Helpers ------------------------------------------------------------------
reset() {
  rm -rf "$GATE_STATE"; mkdir -p "$GATE_STATE"
  : > "$GATE_STATE/meta"; : > "$GATE_STATE/calls"
}
stamp_of() { # anchor kind -> stored escalated.<kind> value
  grep "^$1|escalated.$2|" "$GATE_STATE/meta" 2>/dev/null | head -1 | cut -d'|' -f3-
}
# `grep -c` prints 0 AND exits 1 when nothing matches, so a `|| echo 0` fallback
# would emit the count twice. Capture, ignore the status, default only when the
# file is absent.
count_calls() { local n; n=$(grep -c "$1" "$GATE_STATE/calls" 2>/dev/null); printf '%s' "${n:-0}"; }
mails()   { count_calls '^mail send'; }
updates() { count_calls '^bd update'; }
run() { "$SCRIPT" --anchor su-lou.10.8 --subject "$1" --body "b" "${@:2}"; }

# The stamp value is `<token>@<epoch>`. Cases that seed a PRIOR stamp need the
# token the gate would have written for a given --state — derived by RUNNING the
# gate once, never by re-implementing its token format here. A test that
# recomputes the format seeds whatever the format used to be, so it keeps passing
# through exactly the change it should have caught.
token_for() { # <state> -> token
  reset
  run "token probe" --state "$1" >/dev/null 2>&1
  local cur; cur=$(stamp_of su-lou.10.8 witness)
  printf '%s' "${cur%@*}"
}
seed_prior() { # <state> <epoch> — a prior stamp for <state>, aged to <epoch>
  local token; token=$(token_for "$1")
  reset
  printf 'su-lou.10.8|escalated.witness|%s@%s\n' "$token" "$2" > "$GATE_STATE/meta"
}

NOW=$(date +%s)
TOKEN_ABC=$(token_for "abc123")

# --- FIRST --------------------------------------------------------------------
reset
out=$(run "PR #35 stranded" --state "abc123/APPROVED/BLOCKED" 2>&1); rc=$?
eq "$rc" "0" "FIRST: exits 0"
eq "$(mails)" "1" "FIRST: mails once"
stamp=$(stamp_of su-lou.10.8 witness)
case "$stamp" in
  abc123-APPROVED-BLOCKED.*@*) ok "FIRST: stamp is <readable-label>.<digest>@<epoch>" ;;
  *) bad "FIRST: stamp is <readable-label>.<digest>@<epoch> (got '$stamp')" ;;
esac
# The label is decoration; the digest is what the comparison turns on, and it is
# taken over the RAW --state — not over the label it was rendered into.
if command -v sha256sum >/dev/null 2>&1; then
  want=$(printf '%s' "abc123/APPROVED/BLOCKED" | sha256sum | awk '{print $1}' | cut -c1-16)
  got=${stamp%@*}; got=${got##*.}
  eq "$got" "$want" "FIRST: the deciding half is a digest of the raw --state"
fi
case "$out" in *ESCALATED*) ok "FIRST: reports ESCALATED" ;; *) bad "FIRST: reports ESCALATED (got '$out')" ;; esac

# --- SUPPRESS -----------------------------------------------------------------
: > "$GATE_STATE/calls"
out=$(run "PR #35 still stranded" --state "abc123/APPROVED/BLOCKED" 2>&1); rc=$?
eq "$rc" "0" "SUPPRESS: exits 0 (suppression is a correct outcome)"
eq "$(mails)" "0" "SUPPRESS: sends no mail"
eq "$(updates)" "0" "SUPPRESS: writes nothing"
case "$out" in *SUPPRESSED*) ok "SUPPRESS: still prints the verdict (not a blind spot)" ;; *) bad "SUPPRESS: prints verdict (got '$out')" ;; esac

# --- DRIFT (the regression) ---------------------------------------------------
# The five real subjects from the 2026-07-27 incident, one anchor, one unchanged
# situation. Subject-keyed dedup would have sent all five.
reset
while IFS= read -r subj; do
  run "$subj" --state "abc123/APPROVED/BLOCKED" >/dev/null 2>&1
done <<'SUBJECTS'
WITNESS: PR #35 stranded on human approval
ESCALATION: PR #35 Codex-green but stranded
QUEUE_HEALTH: su PR #35 fully gate-green
ESCALATION: PR #35 approval-gated ~88h
ESCALATION: PR #35 stranded 3d
SUBJECTS
eq "$(mails)" "1" "DRIFT: five reframings of one situation produce exactly ONE mail"

# --- CHANGED ------------------------------------------------------------------
: > "$GATE_STATE/calls"
run "PR #35 head moved" --state "def456/APPROVED/BLOCKED" >/dev/null 2>&1
eq "$(mails)" "1" "CHANGED: a new state fingerprint re-escalates at once"

# --- COLLIDE ------------------------------------------------------------------
# Two DIFFERENT situations whose display-safe renderings are identical: '/' and
# ' ' both collapse to '-', so a token built from that rendering compares them
# EQUAL and suppresses the second. The gate would then be hiding news, which is
# the one thing it must never do — and silently, which is worse than the storm.
reset
run "PR #35 stranded" --state "abc/123" >/dev/null 2>&1
: > "$GATE_STATE/calls"
run "PR #35 moved on" --state "abc 123" >/dev/null 2>&1
eq "$(mails)" "1" "COLLIDE: states that RENDER alike but differ raw still re-escalate"
# ...while a genuinely identical state is still suppressed, so the fix did not
# simply make every comparison unequal.
: > "$GATE_STATE/calls"
run "PR #35 still there" --state "abc 123" >/dev/null 2>&1
eq "$(mails)" "0" "COLLIDE: an identical raw state is still suppressed"

# --- COOLDOWN -----------------------------------------------------------------
seed_prior "abc123" "$((NOW - 90000))"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "1" "COOLDOWN: unchanged but older than 24h re-escalates"

seed_prior "abc123" "$((NOW - 90000))"
run "PR #35 stranded" --state "abc123" --cooldown 172800 >/dev/null 2>&1
eq "$(mails)" "0" "COOLDOWN: a longer --cooldown still suppresses it"

# --- ORDER --------------------------------------------------------------------
reset
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
first=$(head -1 "$GATE_STATE/calls" | cut -d' ' -f1-2)
stamp_line=$(grep -n '^bd update' "$GATE_STATE/calls" | head -1 | cut -d: -f1)
mail_line=$(grep -n '^mail send' "$GATE_STATE/calls" | head -1 | cut -d: -f1)
eq "$first" "bd show" "ORDER: reads the anchor first"
[ "$stamp_line" -lt "$mail_line" ] && ok "ORDER: stamps BEFORE mailing" \
  || bad "ORDER: stamps before mailing (stamp@$stamp_line mail@$mail_line)"

# --- STAMPFAIL ----------------------------------------------------------------
reset
touch "$GATE_STATE/refuse_update"
out=$(run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
eq "$rc" "1" "STAMPFAIL: exits non-zero"
eq "$(mails)" "0" "STAMPFAIL: sends NOTHING when it cannot bound the escalation"
case "$out" in *"NOT SENT"*) ok "STAMPFAIL: says NOT SENT" ;; *) bad "STAMPFAIL: says NOT SENT (got '$out')" ;; esac

# --- MAILFAIL + RETRY ---------------------------------------------------------
reset
touch "$GATE_STATE/fail_mail"
out=$(run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
eq "$rc" "1" "MAILFAIL: exits non-zero"
eq "$(stamp_of su-lou.10.8 witness)" "" "MAILFAIL: rolls the stamp back (unset — there was no prior)"
rm -f "$GATE_STATE/fail_mail"; : > "$GATE_STATE/calls"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "1" "RETRY: the next cycle still escalates, so nothing was lost"

# --- RESTORE ------------------------------------------------------------------
reset
printf 'su-lou.10.8|escalated.witness|old000@%s\n' "$((NOW - 90000))" > "$GATE_STATE/meta"
touch "$GATE_STATE/fail_mail"
run "PR #35 stranded" --state "new111" >/dev/null 2>&1
eq "$(stamp_of su-lou.10.8 witness)" "old000@$((NOW - 90000))" "RESTORE: a failed send restores the PREVIOUS stamp, not an empty one"

# --- NOANCHOR -----------------------------------------------------------------
reset
touch "$GATE_STATE/missing"
out=$(run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
eq "$rc" "1" "NOANCHOR: exits non-zero"
eq "$(mails)" "0" "NOANCHOR: refuses to send what it cannot bound"

# --- CORRUPT ------------------------------------------------------------------
reset
printf 'su-lou.10.8|escalated.witness|garbage-no-epoch\n' > "$GATE_STATE/meta"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "1" "CORRUPT: a malformed stamp re-escalates rather than muting forever"
eq "$(stamp_of su-lou.10.8 witness)" "$TOKEN_ABC@$(stamp_of su-lou.10.8 witness | sed 's/.*@//')" \
   "CORRUPT: and is rewritten well-formed, so it converges after one mail"

# --- FORCE --------------------------------------------------------------------
reset
printf 'su-lou.10.8|escalated.witness|%s@%s\n' "$TOKEN_ABC" "$NOW" > "$GATE_STATE/meta"
run "PR #35 stranded" --state "abc123" --force >/dev/null 2>&1
eq "$(mails)" "1" "FORCE: bypasses an in-cooldown suppression"
eq "$(updates)" "1" "FORCE: still stamps"

# --- DRY ----------------------------------------------------------------------
reset
out=$(run "PR #35 stranded" --state "abc123" --dry-run 2>&1); rc=$?
eq "$rc" "0" "DRY: exits 0"
eq "$(mails)" "0" "DRY: sends nothing"
eq "$(updates)" "0" "DRY: writes nothing"
case "$out" in *"WOULD ESCALATE"*) ok "DRY: reports the verdict it would have acted on" ;; *) bad "DRY: reports verdict (got '$out')" ;; esac

# --- KIND ---------------------------------------------------------------------
reset
run "witness view" --state "abc123" >/dev/null 2>&1
: > "$GATE_STATE/calls"
run "refinery view" --state "abc123" --kind refinery >/dev/null 2>&1
eq "$(mails)" "1" "KIND: a different channel escalates independently"
[ -n "$(stamp_of su-lou.10.8 refinery)" ] && [ -n "$(stamp_of su-lou.10.8 witness)" ] \
  && ok "KIND: the two channels keep separate stamps" || bad "KIND: separate stamps"

# --- CTRL ---------------------------------------------------------------------
# bd emits raw control characters from prose notes, which makes the JSON invalid
# and kills jq. If that read silently returned "no stamp", the gate would mail
# every cycle — the original bug wearing a disguise. `tr -d` must strip them
# before jq sees them.
#
# Every C0 byte is covered, not just the exotic ones: jq answers "control
# characters from U+0000 through U+001F must be escaped" for a raw TAB and CR
# exactly as it does for \001, and a tab is the one a human actually types into a
# note. A sanitation class that spares tab/LF/CR leaves the common case broken.
for ctl in '\001' '\011' '\015'; do
  reset
  printf "[{\"id\":\"su-lou.10.8\",\"metadata\":{\"escalated.witness\":\"%s@%s\"},\"notes\":\"line${ctl}two\"}]" \
    "$TOKEN_ABC" "$NOW" > "$GATE_STATE/raw_show"
  out=$(run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
  eq "$rc" "0" "CTRL($ctl): survives the control character in the bead payload"
  eq "$(mails)" "0" "CTRL($ctl): still sees the prior stamp and suppresses"
done

# --- PARALLEL (the race) ------------------------------------------------------
# Two patrols reach the same anchor at once — a cycle overlapping its own next
# pass, or a patrol plus a hand-run gate. Read prior stamp -> decide -> stamp ->
# mail is a lost update: both read "no prior stamp", both decide "first
# escalation", both mail. At most once must hold under concurrency, not just in
# sequence, so the section runs under an anchor+kind mutex.
reset
touch "$GATE_STATE/slow_show"
run "PR #35 stranded on human approval" --state "abc123" >/dev/null 2>&1 &
a=$!
run "ESCALATION: PR #35 Codex-green but stranded" --state "abc123" >/dev/null 2>&1 &
b=$!
wait "$a"; wait "$b"
rm -f "$GATE_STATE/slow_show"
eq "$(mails)" "1" "PARALLEL: two simultaneous first escalations send exactly ONE mail"
eq "$(updates)" "1" "PARALLEL: and stamp exactly once"
# The serialization must not wedge the anchor: real news on the next cycle still
# gets through.
: > "$GATE_STATE/calls"
run "PR #35 head moved" --state "def456" >/dev/null 2>&1
eq "$(mails)" "1" "PARALLEL: the next genuine change still escalates"

# --- LOCKWAIT -----------------------------------------------------------------
# A peer holds the lock and then releases it. The run must WAIT for its turn and
# then decide normally — serialization is the point of the mutex, so giving up on
# it the moment there is contention would make the lock decorative.
reset
mkdir -p "$LOCK"; printf '%s\n' "$NOW" > "$LOCK/at"
( sleep 2; rm -f "$LOCK/at"; rmdir "$LOCK" 2>/dev/null ) &
releaser=$!
out=$(run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
wait "$releaser" 2>/dev/null
eq "$rc" "0" "LOCKWAIT: exits 0"
eq "$(mails)" "1" "LOCKWAIT: waits for the holder, then decides normally"
case "$out" in
  *UNSERIALIZED*) bad "LOCKWAIT: gave up on the lock instead of waiting for it" ;;
  *)              ok  "LOCKWAIT: took the lock rather than proceeding unserialized" ;;
esac
[ -d "$LOCK" ] && bad "LOCKWAIT: left the lock it waited for behind" || ok "LOCKWAIT: releases it again"

# --- HELD ---------------------------------------------------------------------
# THE REGRESSION (pre-open signoff on tk-z4aka). A held lock used to be treated as
# a completed decision: any peer in the critical section for this anchor+kind made
# this run exit SUPPRESSED before it ever read the anchor or looked at its OWN
# --state. But the holder is deciding about the state IT observed. A lock orders
# decisions; it cannot make one on someone else's behalf. So a holder that outlasts
# the bounded wait sends us down the unserialized path — which still reads, still
# compares, and still decides — rather than down a silent exit.
reset
mkdir -p "$LOCK"; printf '%s\n' "$NOW" > "$LOCK/at"
out=$(GC_ESCALATION_GATE_LOCK_WAIT=1 run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
eq "$rc" "0" "HELD: exits 0"
eq "$(mails)" "1" "HELD: a peer's lock delays this decision, it does not make it"
case "$out" in *UNSERIALIZED*) ok "HELD: says it proceeded unserialized" ;; *) bad "HELD: warns (got '$out')" ;; esac
[ -d "$LOCK" ] && ok "HELD: leaves the peer's lock alone" || bad "HELD: deleted a lock it did not take"
rm -rf "$LOCK"

# --- NEWS ---------------------------------------------------------------------
# The same regression at its sharpest, and the reason it is a P2 rather than a
# missed optimization. A prior stamp for "old" exists and a peer holds the lock —
# the peer is re-reporting that unchanged "old", so it correctly suppresses and
# mails nothing. We carry "new". Sequentially we would mail AT ONCE ("state
# changed"); under the old lock branch we exited SUPPRESSED and the pair sent zero
# mail between them. That is the gate hiding news, which is the one failure it
# exists to prevent, and it is silent.
seed_prior "old" "$NOW"
mkdir -p "$LOCK"; printf '%s\n' "$NOW" > "$LOCK/at"
out=$(GC_ESCALATION_GATE_LOCK_WAIT=1 run "PR #35 head moved" --state "new" 2>&1); rc=$?
eq "$rc" "0" "NEWS: exits 0"
eq "$(mails)" "1" "NEWS: a CHANGED state is not suppressed by a peer's lock"
case "$out" in *"state changed"*) ok "NEWS: and reports why it escalated" ;; *) bad "NEWS: reports the state change (got '$out')" ;; esac
rm -rf "$LOCK"

# --- NEWSPARALLEL -------------------------------------------------------------
# The concurrent form of NEWS: two invocations for one anchor+kind carrying
# DIFFERENT --state values, overlapping for real. The changed one must get out.
#
# The TOTAL is deliberately not pinned. If the "old" run wins the lock it
# suppresses and exactly one mail (the news) is sent; if the "new" run wins, the
# "old" run then reads a stamp that no longer matches ITS observation and mails
# too. Two is not a bug — going backwards is a state change like any other, and
# the gate cannot know direction. Asserting a total here would be asserting a
# scheduling order.
seed_prior "old" "$NOW"
touch "$GATE_STATE/slow_show"
run "PR #35 still stranded" --state "old" >/dev/null 2>&1 &
a=$!
run "PR #35 head moved" --state "new" >/dev/null 2>&1 &
b=$!
wait "$a"; wait "$b"
rm -f "$GATE_STATE/slow_show"
grep -q 'head moved' "$GATE_STATE/calls" \
  && ok "NEWSPARALLEL: the changed state still escalates under contention" \
  || bad "NEWSPARALLEL: the changed-state escalation was lost to the peer's lock"
[ "$(mails)" -ge 1 ] && ok "NEWSPARALLEL: at least one mail went out" \
  || bad "NEWSPARALLEL: the pair sent nothing at all (got '$(mails)')"

# --- STALEBREAK ---------------------------------------------------------------
# A holder killed mid-section leaves the lock behind. Obeying it would mute the
# anchor forever — the silent failure this whole script is written against — so a
# lock older than the TTL is broken and taken.
reset
mkdir -p "$LOCK"; printf '%s\n' "$((NOW - 3600))" > "$LOCK/at"
touch -t 202001010000 "$LOCK" 2>/dev/null   # the dir mtime is the primary age source
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "1" "STALEBREAK: a lock from a dead holder does not mute the anchor"
[ -d "$LOCK" ] && bad "STALEBREAK: the broken lock was not released" || ok "STALEBREAK: and is released again on exit"

# --- RELEASE ------------------------------------------------------------------
reset
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
[ -d "$LOCK" ] && bad "RELEASE: a normal run left its lock behind" || ok "RELEASE: the lock is released on exit"
# ...including the failure paths, or one unreadable anchor wedges it until the TTL.
reset
touch "$GATE_STATE/missing"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
[ -d "$LOCK" ] && bad "RELEASE: a non-zero exit left its lock behind" || ok "RELEASE: released even when the run exits 1"

# --- DRYLOCK ------------------------------------------------------------------
# A probe must not be able to suppress a real escalation, so --dry-run takes no
# lock at all (it writes nothing and sends nothing, so it has no section to guard).
reset
run "PR #35 stranded" --state "abc123" --dry-run >/dev/null 2>&1
[ -d "$LOCK" ] && bad "DRYLOCK: --dry-run took a lock" || ok "DRYLOCK: --dry-run takes no lock"

# --- LOCKFREE -----------------------------------------------------------------
# The lock root cannot be created. Refusing to send would be a mute; the race it
# leaves open costs at most a duplicate mail. Proceed, and say so.
reset
out=$(GC_ESCALATION_GATE_LOCKDIR=/dev/null/nope run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
eq "$rc" "0" "LOCKFREE: an unusable lock root is not fatal"
eq "$(mails)" "1" "LOCKFREE: the escalation is still delivered"
case "$out" in *UNSERIALIZED*) ok "LOCKFREE: warns that it proceeded unserialized" ;; *) bad "LOCKFREE: warns (got '$out')" ;; esac

# --- UNSUBSTITUTED ------------------------------------------------------------
# mol-witness-patrol is poured --root-only with only binding_prefix as a --var,
# so `--cooldown {{escalation_cooldown}}` can reach the script verbatim. Exiting
# 2 there would send NOTHING on every escalation — a silent mute strictly worse
# than the storm. It must degrade to the default and still deliver.
reset
out=$(run "PR #35 stranded" --state "abc123" --cooldown '{{escalation_cooldown}}' 2>&1); rc=$?
eq "$rc" "0" "UNSUBSTITUTED: an unrendered formula var is not fatal"
eq "$(mails)" "1" "UNSUBSTITUTED: the escalation is still delivered"
case "$out" in *"using the 86400s default"*) ok "UNSUBSTITUTED: warns that it fell back" ;; *) bad "UNSUBSTITUTED: warns (got '$out')" ;; esac

# --- USAGE --------------------------------------------------------------------
reset
"$SCRIPT" --subject s --body b >/dev/null 2>&1; eq "$?" "2" "USAGE: --anchor is required"
"$SCRIPT" --anchor a --body b >/dev/null 2>&1; eq "$?" "2" "USAGE: --subject is required"
"$SCRIPT" --anchor a --subject s >/dev/null 2>&1; eq "$?" "2" "USAGE: --body is required"
"$SCRIPT" --anchor a --subject s --body b --cooldown soon >/dev/null 2>&1; eq "$?" "2" "USAGE: --cooldown must be numeric"
eq "$(mails)" "0" "USAGE: nothing is ever sent on a usage error"

# --- KINDSAFE -----------------------------------------------------------------
# --kind becomes the metadata KEY `escalated.<kind>`, written as
# `--set-metadata "<key>=<value>"`. A kind with '=' splits the pair at the wrong
# place and one with whitespace lands a key no reader addresses — either way the
# stamp cannot be read back, every cycle looks like a first escalation, and the
# storm returns silently. Reject it as a usage error, before anything is sent.
reset
"$SCRIPT" --anchor su-lou.10.8 --subject s --body b --state abc --kind "witness queue" >/dev/null 2>&1
eq "$?" "2" "KINDSAFE: whitespace in --kind is a usage error"
"$SCRIPT" --anchor su-lou.10.8 --subject s --body b --state abc --kind "a=b" >/dev/null 2>&1
eq "$?" "2" "KINDSAFE: '=' in --kind is a usage error"
eq "$(mails)" "0" "KINDSAFE: nothing is sent on a malformed channel"
eq "$(updates)" "0" "KINDSAFE: and nothing is stamped under an unreadable key"
# The shapes real callers use must keep working.
reset
"$SCRIPT" --anchor su-lou.10.8 --subject s --body b --state abc --kind refinery.queue >/dev/null 2>&1
eq "$?" "0" "KINDSAFE: a dotted channel name is still valid"
eq "$(mails)" "1" "KINDSAFE: and is delivered"

# --- ARGEND (the hang) --------------------------------------------------------
# A value-taking option at the END of argv had no $2, so `shift 2` failed and —
# with no `set -e` — left argv unchanged and spun `while [ $# -gt 0 ]` forever.
# Run every case under a hard time bound: a hanging test is a worse failure than
# a failing one, and timeout's 124 must be reported as its own thing rather than
# folded into the exit-2 expectation.
#
# The bound must not itself depend on GNU coreutils. `timeout` is absent on stock
# macOS, and a fallback that just runs the command is no bound at all: on the very
# platform where a regression might land unreviewed, THIS TEST becomes the hang it
# was written to catch — and a hung suite reports nothing, so the defect reads as
# "not run" rather than "failed". The fallback is therefore a real watchdog, built
# only from bash job control and signals.
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"

watchdog_run() { # <cmd> [args...] -> exit code, or 124 if it hung
  "$@" >/dev/null 2>&1 &
  local pid=$! rc=0 watchdog
  # Poll in 1s steps and re-check liveness before killing, so the watchdog exits
  # on its own once the run finishes — it never outlives the case it guards, and
  # it cannot signal a pid that has already been reaped and reused.
  ( for _ in 1 2 3 4 5; do sleep 1; kill -0 "$pid" 2>/dev/null || exit 0; done
    kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid"; rc=$?
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  # SIGKILL surfaces as 128+9; report it as the same 124 `timeout` would, since
  # the gate itself only ever exits 0, 1 or 2.
  [ "$rc" -eq 137 ] && rc=124
  return "$rc"
}

bounded() { # -> exit code, or 124 if it hung
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" 5 "$SCRIPT" "$@" >/dev/null 2>&1
    return $?
  fi
  watchdog_run "$SCRIPT" "$@"
}

# --- WATCHDOG -----------------------------------------------------------------
# Exercise the timeout-free fallback ON EVERY PLATFORM, not only where `timeout`
# happens to be missing. Otherwise the branch that matters on macOS is only ever
# run on macOS — and a bound nobody exercises is a bound nobody can trust.
WD="$TMP/wd"; mkdir -p "$WD"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$WD/hang"; chmod +x "$WD/hang"
printf '#!/usr/bin/env bash\nexit 2\n'   > "$WD/quick"; chmod +x "$WD/quick"
# stderr is dropped because bash announces the SIGKILL ("Killed") as it reaps the
# job — expected here, and noise in the middle of the results.
watchdog_run "$WD/hang" 2>/dev/null
eq "$?" "124" "WATCHDOG: the timeout-free fallback kills a hang and reports it as 124"
watchdog_run "$WD/quick"
eq "$?" "2" "WATCHDOG: and passes a normal exit status through untouched"

reset
for opt in --anchor --subject --body --state --kind --cooldown --to; do
  # The option is last: valid arguments before it, nothing after.
  bounded --anchor su-lou.10.8 --subject s --body b "$opt"; rc=$?
  case "$rc" in
    2)   ok "ARGEND: $opt with no value exits 2" ;;
    124) bad "ARGEND: $opt with no value HUNG (timed out)" ;;
    *)   bad "ARGEND: $opt with no value exits 2 (got '$rc')" ;;
  esac
done
# ...and the option alone, so it is also the FIRST argument — the shape the
# review reproduced (`timeout 2 escalation-gate.sh --anchor` exited 124).
for opt in --anchor --subject --body --state --kind --cooldown --to; do
  bounded "$opt"; rc=$?
  case "$rc" in
    2)   ok "ARGEND: bare $opt exits 2" ;;
    124) bad "ARGEND: bare $opt HUNG (timed out)" ;;
    *)   bad "ARGEND: bare $opt exits 2 (got '$rc')" ;;
  esac
done
eq "$(mails)" "0" "ARGEND: nothing is ever sent"
eq "$(updates)" "0" "ARGEND: nothing is ever stamped"

# --- ARGFLAG ------------------------------------------------------------------
# A missing value followed by another option was consumed as data: `--body
# --dry-run` mailed a body of "--dry-run" and swallowed the flag.
reset
bounded --anchor su-lou.10.8 --subject s --body --dry-run; rc=$?
eq "$rc" "2" "ARGFLAG: --body --dry-run is a usage error, not a body of '--dry-run'"
bounded --anchor --subject s --body b; rc=$?
eq "$rc" "2" "ARGFLAG: --anchor followed by another option is a usage error"
eq "$(mails)" "0" "ARGFLAG: nothing is sent"
eq "$(updates)" "0" "ARGFLAG: nothing is stamped"
# A value that merely STARTS with a dash is legitimate prose and must still work,
# or the guard becomes the silent mute it exists to prevent.
reset
bounded --anchor su-lou.10.8 --subject "-- urgent: PR #35 stranded" --body "-> see thread" --state abc123
eq "$?" "0" "ARGFLAG: a dash-leading subject/body is still a valid value"
eq "$(mails)" "1" "ARGFLAG: and is still delivered"

# --- ARGSHAPE -----------------------------------------------------------------
# Runtime cases can only cover options that exist today. The hang comes back the
# moment someone adds `--foo) FOO="$2"; shift 2 ;;`, so assert the shape itself:
# every `shift 2` in the parser is on a line that first calls require_value.
# Comment lines discuss `shift 2` at length (that is where the bug is explained),
# so drop them first — `<line>:<optional indent>#` — and check only real code.
UNGUARDED=$(grep -n 'shift 2' "$SCRIPT" | grep -v '^[0-9]*:[[:space:]]*#' | grep -vc 'require_value' 2>/dev/null)
eq "${UNGUARDED:-0}" "0" "ARGSHAPE: every 'shift 2' arm calls require_value on the same line"
GUARDED=$(grep -c 'require_value "\$@"' "$SCRIPT" 2>/dev/null)
[ "${GUARDED:-0}" -ge 7 ] && ok "ARGSHAPE: all seven value-taking options are guarded" \
  || bad "ARGSHAPE: expected >=7 guarded options, found '${GUARDED:-0}'"

# --- OPTDRIFT -----------------------------------------------------------------
# require_value rejects a value that is EXACTLY one of our own options, which is
# what makes `--body --dry-run` a usage error instead of a body of "--dry-run".
# That list is maintained by hand, so it drifts: add `--verbose` to the parse loop
# and forget the list, and `--body --verbose` silently stores "--verbose" as the
# body again. Assert the two agree rather than trusting them to.
LOOP_OPTS=$(sed -n '/^while \[ \$# -gt 0 \]; do/,/^done$/p' "$SCRIPT" \
  | grep -oE '\-\-[a-z-]+\)' | sed 's/)$//' | sort -u)
KNOWN_OPTS=$(sed -n '/^require_value()/,/^}$/p' "$SCRIPT" \
  | grep -oE '\-\-[a-z-]+' | sort -u)
# Guard the extraction itself: an empty side would make the comparison below pass
# vacuously, which is how a structural test rots into decoration.
[ -n "$LOOP_OPTS" ] && ok "OPTDRIFT: located the parse loop" || bad "OPTDRIFT: parse loop extraction was EMPTY"
[ -n "$KNOWN_OPTS" ] && ok "OPTDRIFT: located require_value's known-option list" || bad "OPTDRIFT: known-option extraction was EMPTY"
DRIFTED=$(comm -23 <(printf '%s\n' "$LOOP_OPTS") <(printf '%s\n' "$KNOWN_OPTS") | tr '\n' ' ' | sed 's/ *$//')
eq "$DRIFTED" "" "OPTDRIFT: every option the parser handles is in require_value's known list"

echo
echo "escalation-gate.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
