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
#   (ROLLBACKRACE) ...but only while the stamp is still the one THIS run wrote. A
#              peer that mailed and stamped in between must keep its record, or
#              the rollback erases the evidence of a delivered escalation
#   (ROLLBACKFAIL) and when the rollback itself fails, SAY SO: the stamp remains,
#              so a log line claiming "rolled back, next cycle retries" is the
#              opposite of the state an operator is in
#   (PENDING)  ...and the stamp that remains must not read as a delivered notice.
#              Stamp-first means every stamp precedes its mail, so it records its
#              own delivery state: pending until `gc mail send` returns 0. An
#              unconfirmed stamp re-escalates inside the cooldown — otherwise
#              ORPHAN_CLOSED reads the suppression as "the mayor was told" and
#              spends its one-shot close on a notice nobody received
#   (FUTURE)   a stamp dated ahead of now has a NEGATIVE age, which is below every
#              cooldown, so it suppresses until that date arrives — a stamp from
#              next month mutes the anchor for a month. Corrupt, not recent
#   (SKEW)     ...but seconds of clock skew between two hosts is ordinary, and
#              re-escalating on that would be the storm sourced from the clocks
#   (ACQUIREFAIL) `mkdir` succeeding does not mean a file can be created inside.
#              An ignored owner-write failure left this run believing it held a
#              lock that named NOBODY — classified "unknown", governed by age, so
#              a peer proceeded unserialized into the same section, and
#              release_lock could not remove it either
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
#   (HELD)     THE REGRESSION: a held lock used to end this run at SUPPRESSED
#              before it read the anchor or its own --state. A lock orders
#              decisions; it cannot make one on a peer's behalf, so an
#              UNVERIFIABLE holder that outlasts the bounded wait sends us down
#              the unserialized path — which still reads, compares and decides.
#              (A holder we CAN verify as live defers instead — see DUPFIRST)
#   (NEWS)     ...and why that mattered: peer suppressing an unchanged "old" while
#              this run carries "new" produced ZERO mail between them. A changed
#              state must escalate through a peer's lock
#   (NEWSPARALLEL) the same, genuinely concurrent, with different --state values
#   (STALEBREAK) a lock left behind by a killed holder is broken, not obeyed — a
#              dead peer must never mute an anchor forever
#   (LOCKOWNER) the lock records WHO holds it, which is what the four cases below
#              turn on; they build their fixtures from the real owner line
#   (DUPFIRST) THE REGRESSION: "proceed unserialized when the wait expires" fails
#              against a live holder blocked BEFORE its first stamp — both runs
#              read no prior stamp and both mail the same first escalation. A
#              live holder must make this run DEFER
#   (FORCEDEFER) ...but --force still goes out past a live holder: an operator's
#              escape hatch a background wisp can close by holding a lock is none
#   (LIVETTL)  and its other half: a live holder that is merely SLOW is older than
#              LOCK_TTL too, so an age-only stale break stole its lock and put two
#              runs inside one section
#   (MAXHOLD)  ...bounded by the backstop, or a recycled pid would mute the anchor
#              forever, which is worse than the duplicate a wrong break can cost
#   (RELEASEOWNER) why a wrongly broken lock COMPOUNDED: release remembered only
#              the path, so the old holder deleted its successor's lock on the
#              way out and let a third run in behind it
#   (DEADBREAK) a verifiably dead owner is broken at once instead of waited out
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
#   refuse_rollback if present, only the SECOND `gc bd update` of a run fails —
#                 the stamp lands, the mail fails, the undo cannot be written
#   fail_mail     if present, every `gc mail send` fails
#   wedge_show    if present, `gc bd show` blocks for the seconds it contains —
#                 a holder stuck INSIDE the critical section, before it has read
#   wedge_update  if present, the FIRST `gc bd update` blocks for the seconds it
#                 contains — a holder stuck after reading "no prior stamp" and
#                 before that stamp lands, which is the window a peer's
#                 unserialized decision duplicates (DUPFIRST)
#   stamp_race    if present, `gc mail send` replaces the metadata with the rows
#                 it contains and then fails — a peer that escalated between our
#                 stamp and our rollback
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
  # ...and widen it far enough to outlast a peer's whole bounded wait, which is
  # the shape the lock cases below need: a holder that is demonstrably ALIVE and
  # has NOT yet stamped when the peer's patience runs out.
  [ -f "$S/wedge_show" ] && sleep "$(cat "$S/wedge_show")"
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
  # Refuse only the ROLLBACK write. `calls` already carries this invocation, so
  # the run's first update counts 1 (allowed) and the rollback counts 2.
  if [ -f "$S/refuse_rollback" ]; then
    n=$(grep -c '^bd update' "$S/calls" 2>/dev/null)
    [ "${n:-0}" -gt 1 ] && exit 1
  fi
  # Wedge only the FIRST update — the holder's stamp. A peer that gets past the
  # lock reads the anchor while this write is still in flight, which is why it
  # sees no prior stamp and decides "first escalation" too.
  if [ -f "$S/wedge_update" ]; then
    n=$(grep -c '^bd update' "$S/calls" 2>/dev/null)
    [ "${n:-0}" -le 1 ] && sleep "$(cat "$S/wedge_update")"
  fi
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
  # A peer that mailed and stamped in the window between our stamp and our
  # rollback: its rows replace the metadata, and our own send still fails.
  if [ -f "$S/stamp_race" ]; then cat "$S/stamp_race" > "$S/meta"; exit 1; fi
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
seed_pending() { # <state> <epoch> — the same, but delivery was never confirmed
  local token; token=$(token_for "$1")
  reset
  printf 'su-lou.10.8|escalated.witness|%s@%s.pending\n' "$token" "$2" > "$GATE_STATE/meta"
}

# A backgrounded gate run is "inside the critical section" once its lock carries
# an owner. The lock cases poll for that rather than sleeping a guessed interval,
# so they assert on an observed state instead of on a scheduler. Fractional sleeps
# are honored by GNU and BSD sleep but are not POSIX, so a platform that refuses
# them polls in whole seconds rather than spinning through the budget instantly.
if sleep 0.2 2>/dev/null; then TICK=0.2; TICKS=40; else TICK=1; TICKS=8; fi
wait_for() { # <command...> — poll until it succeeds; non-zero if it never does
  local i=0
  while [ "$i" -lt "$TICKS" ]; do
    "$@" && return 0
    sleep "$TICK"
    i=$((i + 1))
  done
  return 1
}
lock_held()      { [ -s "$LOCK/owner" ]; }        # a run is inside the section
stamp_inflight() { [ "$(updates)" -ge 1 ]; }      # ...and its stamp write is in flight
wait_for_lock()  { wait_for lock_held; }
backdate() { # <path> <epoch> — age a lock without touching who owns it
  touch -d "@$2" "$1" 2>/dev/null \
    || touch -t "$(date -r "$2" +%Y%m%d%H%M 2>/dev/null)" "$1" 2>/dev/null
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

# --- ROLLBACKRACE -------------------------------------------------------------
# THE REGRESSION (pre-open signoff round 2 on tk-z4aka). A failed send restored
# $PRIOR unconditionally. On any unserialized path a peer can have mailed AND
# stamped between our write and our rollback — restoring over that erases the
# record of a mail already in the mayor's inbox, and the anchor then reads as
# never escalated. Roll back only while the stamp is still the one this run wrote.
reset
printf 'su-lou.10.8|escalated.witness|peer000@%s\n' "$NOW" > "$GATE_STATE/stamp_race"
out=$(run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
rm -f "$GATE_STATE/stamp_race"
eq "$rc" "1" "ROLLBACKRACE: exits 1 — this run sent nothing"
eq "$(stamp_of su-lou.10.8 witness)" "peer000@$NOW" \
   "ROLLBACKRACE: the peer's newer stamp survives the rollback"
case "$out" in
  *"not rolling back"*) ok "ROLLBACKRACE: says it left the peer's record alone" ;;
  *)                    bad "ROLLBACKRACE: explains itself (got '$out')" ;;
esac

# --- ROLLBACKFAIL ---------------------------------------------------------------
# The send failed AND the rollback write failed. The old code printed "stamp
# rolled back so the next cycle retries" either way — the one line an operator
# reads, saying the opposite of what happened: the stamp survives, so the anchor
# goes quiet for a full cooldown. Report the true state, and name the key to clear.
reset
touch "$GATE_STATE/fail_mail" "$GATE_STATE/refuse_rollback"
out=$(run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
rm -f "$GATE_STATE/fail_mail" "$GATE_STATE/refuse_rollback"
eq "$rc" "1" "ROLLBACKFAIL: exits 1"
[ -n "$(stamp_of su-lou.10.8 witness)" ] \
  && ok "ROLLBACKFAIL: the stamp it could not roll back is still on the anchor" \
  || bad "ROLLBACKFAIL: expected the un-rolled-back stamp to remain"
case "$out" in
  *"rolled back so the next cycle retries"*)
    bad "ROLLBACKFAIL: claimed a rollback that never landed" ;;
  *REMAINS*)
    ok "ROLLBACKFAIL: says the stamp REMAINS instead" ;;
  *)
    bad "ROLLBACKFAIL: reports the true state (got '$out')" ;;
esac
case "$out" in
  *"--unset-metadata escalated.witness"*) ok "ROLLBACKFAIL: names the key to clear" ;;
  *)                                      bad "ROLLBACKFAIL: names the key to clear (got '$out')" ;;
esac
# THE PRE-OPEN SIGNOFF ROUND 3 FINDING. The stamp that survives is the record of a
# mail NOBODY RECEIVED, and it used to be indistinguishable from a delivered one:
# the next cycle suppressed on it for a full cooldown, and ORPHAN_CLOSED — which
# reads a suppression as "the mayor was told on an earlier cycle" — closed the bead
# on that non-notice. Neither the mail nor the undo can be repaired here (the write
# is what is failing), so the stamp carries its own delivery state and this one
# stayed `.pending`.
case "$(stamp_of su-lou.10.8 witness)" in
  *.pending) ok "ROLLBACKFAIL: the surviving stamp is marked pending, not delivered" ;;
  *)         bad "ROLLBACKFAIL: the surviving stamp must be pending (got '$(stamp_of su-lou.10.8 witness)')" ;;
esac
case "$out" in
  *"SUPPRESSED until"*) bad "ROLLBACKFAIL: still warns of a suppression the pending stamp prevents" ;;
  *"RE-ESCALATES"*)     ok  "ROLLBACKFAIL: says the next cycle re-escalates instead" ;;
  *)                    bad "ROLLBACKFAIL: reports what the next cycle will do (got '$out')" ;;
esac
: > "$GATE_STATE/calls"
out=$(run "PR #35 stranded" --state "abc123" 2>&1)
eq "$(mails)" "1" "ROLLBACKFAIL: the next cycle RE-ESCALATES rather than suppressing on an undelivered stamp"
case "$out" in
  *pending*) ok "ROLLBACKFAIL: and says why it did not suppress" ;;
  *)         bad "ROLLBACKFAIL: names the pending stamp as its reason (got '$out')" ;;
esac
# ...and that re-send converges: it is delivered, so the stamp is promoted and the
# cycle after it goes quiet. Re-escalating forever would be the storm.
: > "$GATE_STATE/calls"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "0" "ROLLBACKFAIL: the delivered re-send converges — the cycle after it is suppressed"

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

# --- PENDING ------------------------------------------------------------------
# A stamp is written BEFORE the mail, so between those two writes it records an
# escalation that may never have gone out. If the send fails the stamp is rolled
# back — unless that write fails too (ROLLBACKFAIL), and then a stamp for a mail
# nobody received is what every later cycle reads. Suppressing on it is not just a
# lost mail: ORPHAN_CLOSED reads a suppression as "the mayor was told" and spends
# its one-shot `gc bd close` on it. So the stamp records its own delivery state,
# and an unconfirmed one re-escalates INSIDE the cooldown.
seed_pending "abc123" "$NOW"
out=$(run "PR #35 stranded" --state "abc123" 2>&1)
eq "$(mails)" "1" "PENDING: an undelivered prior stamp re-escalates inside the cooldown"
case "$out" in
  *pending*) ok "PENDING: and names the unconfirmed delivery as the reason" ;;
  *)         bad "PENDING: names its reason (got '$out')" ;;
esac
case "$(stamp_of su-lou.10.8 witness)" in
  *.pending) bad "PENDING: the delivered re-send left the stamp pending" ;;
  *)         ok  "PENDING: a delivered re-send promotes the stamp out of pending" ;;
esac
# The control: the SAME state and epoch, delivered, is suppressed. Without this the
# case above would pass just as well if pending had been ignored and something else
# were forcing the mail.
seed_prior "abc123" "$NOW"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "0" "PENDING: a DELIVERED stamp of the same age still suppresses"

# ...and the promotion is a second write that lands AFTER the mail, never before:
# promoting first would record a delivery that had not happened yet, which is the
# whole defect wearing the fix's clothes.
reset
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
mail_at=$(grep -n '^mail send' "$GATE_STATE/calls" | head -1 | cut -d: -f1)
promote_at=$(grep -n '^bd update' "$GATE_STATE/calls" | tail -1 | cut -d: -f1)
eq "$(updates)" "2" "PENDING: one escalation writes twice — the pending stamp and its promotion"
[ -n "$mail_at" ] && [ "$promote_at" -gt "$mail_at" ] \
  && ok "PENDING: the promotion follows the mail it records" \
  || bad "PENDING: promotion must follow the mail (mail@${mail_at:-none} promote@${promote_at:-none})"

# A mail that lands while the promotion fails: the notice IS out, so the worst
# available outcome is one duplicate — never a lost notice, and it converges as
# soon as a write succeeds.
reset
touch "$GATE_STATE/refuse_rollback"   # refuses the run's SECOND update: the promotion
out=$(run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
rm -f "$GATE_STATE/refuse_rollback"
eq "$rc" "0" "PENDING: a failed promotion does not turn a delivered mail into a failure"
eq "$(mails)" "1" "PENDING: the mail went out"
case "$out" in
  *"DELIVERED but"*) ok "PENDING: says the mail landed but the stamp did not promote" ;;
  *)                 bad "PENDING: reports the failed promotion (got '$out')" ;;
esac
: > "$GATE_STATE/calls"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "1" "PENDING: the next cycle re-sends once rather than trusting an unconfirmed stamp"
: > "$GATE_STATE/calls"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "0" "PENDING: and then converges — the duplicate is bounded at one"

# --- FUTURE / SKEW ------------------------------------------------------------
# A stamp dated ahead of now yields a NEGATIVE age, which is smaller than any
# cooldown — so an unchanged situation reads as "escalated recently" on every cycle
# until that timestamp actually arrives. A stamp from next month mutes the anchor
# for a month. Treat a future epoch as corrupt: re-escalate once and rewrite it.
seed_prior "abc123" "$((NOW + 2592000))"
out=$(run "PR #35 stranded" --state "abc123" 2>&1)
eq "$(mails)" "1" "FUTURE: a stamp dated a month ahead re-escalates instead of muting until then"
case "$out" in
  *FUTURE*) ok "FUTURE: says the stamp was in the future" ;;
  *)        bad "FUTURE: explains itself (got '$out')" ;;
esac
case "$(stamp_of su-lou.10.8 witness)" in
  *"@$((NOW + 2592000))"*) bad "FUTURE: the future stamp survived — the next cycle mutes again" ;;
  *)                       ok  "FUTURE: and is rewritten, so it converges after one mail" ;;
esac
: > "$GATE_STATE/calls"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "0" "FUTURE: the rewritten stamp suppresses normally"

# The other direction: stamps are written by whichever host ran the gate, so a few
# seconds of clock skew between two of them is ordinary. Treating THAT as corrupt
# would re-escalate every cycle for as long as the skew lasts — the storm again,
# sourced from the clocks. Inside the grace it still suppresses.
seed_prior "abc123" "$((NOW + 60))"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1
eq "$(mails)" "0" "SKEW: a stamp seconds ahead is clock skew, not corruption — still suppressed"

# --- FORCE --------------------------------------------------------------------
reset
printf 'su-lou.10.8|escalated.witness|%s@%s\n' "$TOKEN_ABC" "$NOW" > "$GATE_STATE/meta"
run "PR #35 stranded" --state "abc123" --force >/dev/null 2>&1
eq "$(mails)" "1" "FORCE: bypasses an in-cooldown suppression"
# Two writes, one escalation: the pending stamp and its promotion to delivered.
eq "$(updates)" "2" "FORCE: still stamps"

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
# One ESCALATION, which is two writes: the pending stamp that licenses the mail
# and the promotion that records it delivered (see PENDING below). The loser of
# the race writes neither — it suppresses on the winner's stamp — so a third write
# here would mean both runs entered the section.
eq "$(updates)" "2" "PARALLEL: and one escalation's worth of writes, not two"
case "$(stamp_of su-lou.10.8 witness)" in
  *.pending) bad "PARALLEL: the surviving stamp is still pending — the delivered promotion was lost" ;;
  '')        bad "PARALLEL: no stamp survived the race" ;;
  *)         ok  "PARALLEL: the surviving stamp records a DELIVERED escalation" ;;
esac
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
# decisions; it cannot make one on someone else's behalf. So an UNVERIFIABLE holder
# (no owner file — this fixture, and any lock from a pre-ownership version) that
# outlasts the bounded wait sends us down the unserialized path — which still reads, still
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
#
# The fixture lock carries no owner, so its holder is UNVERIFIABLE and this stays
# the unserialized path (DUPFIRST covers the verifiably-live one). That is the
# right shape here: with nothing to verify, the gate keeps its bias toward
# sending rather than deferring to a lock that may belong to nobody.
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

# --- LOCKOWNER ------------------------------------------------------------------
# The cases below build variants of a lock owner (a dead pid, a successor). Take
# the line the gate ACTUALLY writes rather than re-typing its format here: a test
# that reproduces a format seeds whatever the format used to be, so it keeps
# passing through exactly the change it should have caught.
#
# The probe is held open just long enough to read its lock and then allowed to
# FINISH. Killing it instead is what a first draft did, and `kill $!` on a
# backgrounded shell function may only reap the subshell — the gate child then
# survives as an orphan and mails into whatever case's log comes next, which
# reads as a duplicate escalation produced by the code under test.
reset
printf '1\n' > "$GATE_STATE/wedge_show"
run "owner probe" --state "abc123" >/dev/null 2>&1 &
probe=$!
REAL_OWNER=""
wait_for_lock && REAL_OWNER=$(cat "$LOCK/owner" 2>/dev/null)
wait "$probe" 2>/dev/null
rm -f "$GATE_STATE/wedge_show"; rm -rf "$LOCK"
[ -n "$REAL_OWNER" ] && ok "LOCKOWNER: the gate records an owner in the lock it takes" \
  || bad "LOCKOWNER: no owner appeared in the lock — the ownership cases cannot run"

# --- DUPFIRST -------------------------------------------------------------------
# THE REGRESSION (pre-open signoff round 2 on tk-z4aka). The bounded wait used to
# end in "proceed UNSERIALIZED" whoever held the lock, reasoning that stamp-first
# makes that safe: a holder that got as far as mailing has already written the
# stamp we would read. The holder it misses is the one blocked BEFORE its first
# stamp — a wedged `gc bd show`, which is exactly the condition that outlasts the
# wait. Both runs then read the same empty prior state, both decide "first
# escalation", and both mail: the lost update the mutex exists to prevent,
# arriving through the mutex's own timeout. A verifiably LIVE holder must make
# this run DEFER — decide nothing, send nothing, retry next cycle.
#
# The wedge is on the STAMP WRITE, not the read: that is the window the finding
# names. Wedging the read instead makes the holder re-read AFTER the peer has
# stamped, which is the case stamp-first already converges — the fixture would
# then pass against the very code it is meant to catch. Verified by reproducing
# both against the pre-fix script: wedged read sends 1 mail, wedged stamp sends 2.
reset
printf '5\n' > "$GATE_STATE/wedge_update"
run "PR #35 stranded on human approval" --state "abc123" >/dev/null 2>&1 &
holder=$!
wait_for_lock || bad "DUPFIRST: the holder never took the lock"
wait_for stamp_inflight || bad "DUPFIRST: the holder never reached its stamp write"
eq "$(stamp_of su-lou.10.8 witness)" "" \
   "DUPFIRST: the holder is mid-stamp — the anchor still records nothing"
out=$(GC_ESCALATION_GATE_LOCK_WAIT=1 run "ESCALATION: PR #35 Codex-green but stranded" --state "abc123" 2>&1); rc=$?
eq "$(mails)" "0" "DUPFIRST: does not mail past a live holder that may not have stamped"
eq "$rc" "1" "DUPFIRST: defers instead — nothing sent, next cycle retries"
case "$out" in *"NOT SENT"*) ok "DUPFIRST: says NOT SENT" ;; *) bad "DUPFIRST: says NOT SENT (got '$out')" ;; esac
[ -s "$LOCK/owner" ] && ok "DUPFIRST: leaves the holder's lock alone" || bad "DUPFIRST: disturbed the holder's lock"
wait "$holder"
rm -f "$GATE_STATE/wedge_update"
eq "$(mails)" "1" "DUPFIRST: the holder's own escalation still goes out — exactly one"

# --- FORCEDEFER -------------------------------------------------------------------
# The deferral is the right default for a patrol wisp — it comes back in minutes.
# It must not swallow the operator's escape hatch, though: --force means a human
# decided this goes out now, and an escape hatch a background wisp can close by
# holding a lock is not one.
reset
printf '5\n' > "$GATE_STATE/wedge_update"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1 &
holder=$!
wait_for_lock || bad "FORCEDEFER: the holder never took the lock"
wait_for stamp_inflight || bad "FORCEDEFER: the holder never reached its stamp write"
out=$(GC_ESCALATION_GATE_LOCK_WAIT=1 run "OPERATOR: send it now" --state "abc123" --force 2>&1); rc=$?
eq "$rc" "0" "FORCEDEFER: --force is not deferred by a live holder"
eq "$(mails)" "1" "FORCEDEFER: the operator's escalation goes out"
case "$out" in *UNSERIALIZED*) ok "FORCEDEFER: and says it went unserialized" ;; *) bad "FORCEDEFER: warns (got '$out')" ;; esac
wait "$holder"
rm -f "$GATE_STATE/wedge_update"

# --- LIVETTL --------------------------------------------------------------------
# THE OTHER HALF. The stale branch broke any lock older than LOCK_TTL on AGE
# ALONE, so a holder that is merely slow — the wedged write again — had its lock
# deleted and retaken while it was still inside the section. Age guesses at
# abandonment; ownership answers it. A lock whose owner is alive is not breakable.
reset
printf '5\n' > "$GATE_STATE/wedge_show"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1 &
holder=$!
wait_for_lock || bad "LIVETTL: the holder never took the lock"
HELD_BY=$(cat "$LOCK/owner" 2>/dev/null)
# Age it past LOCK_TTL (300s) but under the LOCK_MAX_HOLD backstop, without
# touching who owns it. The wedge stays IN PLACE through the peer's attempt:
# removing it here (as an earlier draft did) lets the holder finish and release
# before the peer looks, so on a slow run the peer takes a fresh lock and DECIDES
# (mails=1, rc=0) instead of deferring to a live owner. That is a harness race,
# not a product regression — the holder is released only after the peer decides.
printf '%s\n' "$((NOW - 600))" > "$LOCK/at"; backdate "$LOCK" "$((NOW - 600))"
out=$(GC_ESCALATION_GATE_LOCK_WAIT=1 run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
eq "$(cat "$LOCK/owner" 2>/dev/null)" "$HELD_BY" \
   "LIVETTL: a live owner's lock is not broken on age alone"
eq "$(mails)" "0" "LIVETTL: and no peer decides inside the holder's section"
eq "$rc" "1" "LIVETTL: it defers"
wait "$holder"
rm -f "$GATE_STATE/wedge_show"
eq "$(mails)" "1" "LIVETTL: the holder finishes its own escalation — exactly one"

# --- MAXHOLD --------------------------------------------------------------------
# ...and the escape hatch, because "never break a live owner" would mute the
# anchor forever if the pid were recycled after a crash, or the holder wedged for
# good. Past LOCK_MAX_HOLD — an hour, far beyond any real critical section — the
# lock is broken anyway. A permanent mute is the failure this script exists to
# prevent; a duplicate is not.
reset
printf '5\n' > "$GATE_STATE/wedge_show"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1 &
holder=$!
wait_for_lock || bad "MAXHOLD: the holder never took the lock"
rm -f "$GATE_STATE/wedge_show"
printf '%s\n' "$((NOW - 7200))" > "$LOCK/at"; backdate "$LOCK" "$((NOW - 7200))"
out=$(GC_ESCALATION_GATE_LOCK_WAIT=1 run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
eq "$rc" "0" "MAXHOLD: a lock held past the backstop does not defer forever"
eq "$(mails)" "1" "MAXHOLD: the escalation gets out"
# The broken-past holder then reads the stamp this run left and suppresses — the
# stamp-first convergence that keeps a broken lock costing at most a duplicate.
wait "$holder"
eq "$(mails)" "1" "MAXHOLD: and the holder converges on suppress rather than mailing again"

# --- RELEASEOWNER -----------------------------------------------------------------
# What made a wrongly broken lock COMPOUND instead of merely costing a duplicate:
# release remembered only the PATH. The original holder, exiting after its lock
# had been broken and retaken, deleted its SUCCESSOR's lock and let a third
# invocation in behind it. Release must check the lock is still ours.
reset
printf '3\n' > "$GATE_STATE/wedge_show"
run "PR #35 stranded" --state "abc123" >/dev/null 2>&1 &
holder=$!
wait_for_lock || bad "RELEASEOWNER: the holder never took the lock"
rm -f "$GATE_STATE/wedge_show"
# Someone breaks the holder's lock and takes it: same path, different owner.
SUCCESSOR=$(printf '%s\n' "$REAL_OWNER" | awk '{$3 = "successor"; print}')
rm -rf "$LOCK"; mkdir -p "$LOCK"; printf '%s\n' "$SUCCESSOR" > "$LOCK/owner"
wait "$holder"
eq "$(cat "$LOCK/owner" 2>/dev/null)" "$SUCCESSOR" \
   "RELEASEOWNER: the holder leaves a lock that is no longer its own"
rm -rf "$LOCK"

# --- DEADBREAK --------------------------------------------------------------------
# A pid that no longer exists is not a guess the way an age is, so a crashed
# holder's lock is broken AT ONCE rather than waited out to the TTL — 300s of a
# patrol pass spent on a holder that is never coming back is its own small mute.
reset
( exit 0 ) & DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null
mkdir -p "$LOCK"; printf '%s\n' "$NOW" > "$LOCK/at"
# The owner the gate itself writes, with a pid that is gone — only the field the
# case is about is changed.
printf '%s\n' "$REAL_OWNER" | awk -v p="$DEAD_PID" '{$2 = p; print}' > "$LOCK/owner"
out=$(GC_ESCALATION_GATE_LOCK_WAIT=1 run "PR #35 stranded" --state "abc123" 2>&1); rc=$?
eq "$rc" "0" "DEADBREAK: exits 0"
eq "$(mails)" "1" "DEADBREAK: a fresh lock from a dead holder does not mute the anchor"
case "$out" in
  *UNSERIALIZED*) bad "DEADBREAK: gave up on the lock instead of breaking a dead one" ;;
  *)              ok  "DEADBREAK: broke it and took the lock properly" ;;
esac
[ -d "$LOCK" ] && bad "DEADBREAK: the broken lock was not released" || ok "DEADBREAK: and released it again"

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

# --- ACQUIREFAIL --------------------------------------------------------------
# `mkdir` succeeding says the NAME was free; it says nothing about whether a file
# can be created inside (a full filesystem, a lock root whose mode denies it). The
# owner write's failure used to be ignored, which produced the worst of both
# states: this run believed it held the lock, and the lock it left named nobody.
# An ownerless lock is classified "unknown", and unknown is governed by AGE — so a
# peer inside LOCK_TTL waited out LOCK_WAIT and proceeded UNSERIALIZED into the
# section this run thought it had to itself, and both mailed the same first
# escalation. release_lock could not clean it up either (an absent owner never
# matches LOCK_TOKEN), so it degraded every run for that anchor+kind until the TTL.
# Verify the owner write, and when it cannot be made, hold nothing and say so.
NOWRITE="$TMP/nowrite"
rm -rf "$NOWRITE"; mkdir -p "$NOWRITE/probe"; chmod 0222 "$NOWRITE/probe"
if (: > "$NOWRITE/probe/x") 2>/dev/null; then
  # Root ignores the mode bits, so the fixture cannot produce the failure and the
  # assertions below would pass without exercising anything. Say so out loud.
  ok "ACQUIREFAIL: SKIPPED — this user can write into a mode-0222 directory (running as root?)"
else
  reset
  # umask 0555 makes the gate's own `mkdir` produce a directory with no search
  # permission, so the owner write inside it fails while the mkdir succeeded —
  # exactly the split this case is about. The lock ROOT is created beforehand,
  # under the normal umask, or the gate would take the unusable-root path instead.
  ACQFAIL_ROOT="$NOWRITE/locks"; mkdir -p "$ACQFAIL_ROOT"
  out=$( (umask 0555; GC_ESCALATION_GATE_LOCKDIR="$ACQFAIL_ROOT" \
          run "PR #35 stranded" --state "abc123" 2>&1) ); rc=$?
  eq "$rc" "0" "ACQUIREFAIL: a lock it cannot own is not fatal"
  eq "$(mails)" "1" "ACQUIREFAIL: the escalation is still delivered"
  case "$out" in
    *UNSERIALIZED*) ok "ACQUIREFAIL: warns that it proceeded unserialized" ;;
    *)              bad "ACQUIREFAIL: warns (got '$out')" ;;
  esac
  case "$out" in
    *ownership*) ok "ACQUIREFAIL: names the ownership write as what failed" ;;
    *)           bad "ACQUIREFAIL: names what failed (got '$out')" ;;
  esac
  [ ! -d "$ACQFAIL_ROOT/su-lou.10.8.witness.lock" ] \
    && ok "ACQUIREFAIL: leaves no ownerless lock behind for peers to wait out" \
    || bad "ACQUIREFAIL: an ownerless lock survives at $ACQFAIL_ROOT/su-lou.10.8.witness.lock"
fi
chmod 0755 "$NOWRITE/probe" 2>/dev/null; rm -rf "$NOWRITE"

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
