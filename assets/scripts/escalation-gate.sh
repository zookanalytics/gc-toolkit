#!/usr/bin/env bash
# escalation-gate — send an anchor-scoped escalation mail AT MOST ONCE per
# distinct situation, instead of once per patrol cycle (tk-z4aka / lx-b5aev).
#
# THE BUG THIS EXISTS TO PREVENT. mol-witness-patrol re-derives its escalation
# triggers from live state every cycle. The triggers are correct and the
# conditions stay true for as long as the item is stuck — so the witness mailed
# the mayor again, and again, and again. Observed 2026-07-27 (deacon wisp
# lx-wisp-8onlq): the shutupandlisten witness escalated ONE item (PR #35 / anchor
# su-lou.10.8) FIVE times in 2h53m; the su refinery added two more. Seven
# near-identical escalations about one PR sat unread in the mayor's inbox while
# the mayor was itself parked awaiting the operator decision that would have
# resolved it.
#
# The cost is not the mail volume. Repeated identical escalations train every
# recipient to ignore escalation mail — the one signal that is supposed to be
# rare and load-bearing. And each `gc mail send` is a permanent bead plus a Dolt
# commit, so an item blocked on a human signature bills unbounded write
# amplification for as long as the human is away (PR #35: ~88h, on a store the
# doctor already flags at 20852 commits / 2.64 GB noms).
#
# WHY DEDUP CANNOT KEY ON THE SUBJECT LINE. The five witness mails were:
#
#     WITNESS: PR #35 stranded on human approval
#     ESCALATION: PR #35 Codex-green but stranded
#     QUEUE_HEALTH: su PR #35 fully gate-green
#     ESCALATION: PR #35 approval-gated ~88h
#     ESCALATION: PR #35 stranded 3d
#
# One situation, five framings — because an LLM composes the subject fresh each
# cycle from whatever it just observed. Any dedup keyed on the message (subject,
# body, topic) is defeated by rephrasing, which is precisely what a re-deriving
# agent does. So the key is the ANCHOR plus the sending CHANNEL (`--kind`), never
# the message. `--kind` names the escalating ROLE, not the topic: if "queue
# health" and "stranded PR" were separate kinds, the witness would simply storm
# once per framing again. One anchor, one kind, one open escalation.
#
# WHY NOT A /tmp MARKER FILE. That is the su refinery's existing approach and it
# fails in both directions at once (su-xgz2): it survives a session recycle, so a
# genuinely needed escalation is suppressed, and it dies on reboot, so the storm
# comes back. The stamp has to live where the state lives — on the anchor bead,
# the same durable place `check.<gate>=green@<oid>` and `anchorless_flagged` use.
#
# WHY NOT "SEARCH THE RECIPIENT'S INBOX FOR AN OPEN ESCALATION". It is the shape
# the tracker first proposed, and it does not survive contact with the subject-
# drift above: matching an existing escalation requires the anchor id to appear
# in mail we do not control the wording of. It also reads another agent's mailbox
# once per cycle per witness (four of them), and races the mayor archiving it.
# The anchor bead is authoritative, local, and already the convention.
#
# WHEN IT DOES RE-ESCALATE — two independent openings, which is what keeps this a
# dedup rather than a mute:
#
#   STATE CHANGED   `--state` is a fingerprint of the inputs that HOLD the item
#                   (head oid, reviewDecision, mergeStateStatus...). A different
#                   fingerprint is a genuinely different situation and mails
#                   immediately. This is the important one: it means the gate
#                   never hides news, only repetition.
#   COOLDOWN        the same fingerprint re-mails after `--cooldown` seconds
#                   (default 24h) so an item stuck for days still resurfaces
#                   periodically instead of falling silent forever.
#
# The stamp folds both into one value, exactly as `check.<gate>=green@<oid>`
# folds "passed" and "at which commit":
#
#     escalated.<kind> = <readable-label>.<digest-of-raw-state>@<epoch-seconds>
#
# The label is there to read; the DIGEST is what decides. See "COMPARE ON A
# DIGEST" below — a display-safe rendering of the fingerprint is lossy, and a
# lossy comparison suppresses exactly the news the gate must let through.
#
# STAMP FIRST, MAIL SECOND — and the ability to stamp is the LICENSE to mail.
# This is the same convergence rule reconcile-merged-prs.sh uses for its
# anchorless-PR escalation: if we cannot record that we escalated, we must not
# escalate, because an unbounded mail storm is strictly worse than a delayed
# escalation. A failed stamp therefore sends nothing and exits non-zero; the next
# cycle retries the whole thing.
#
# ...BUT A FAILED MAIL ROLLS THE STAMP BACK. Stamp-first has one failure mode
# worth closing: if the stamp lands and the mail then fails, the situation is
# recorded as "already escalated" while the mayor was never told, and the gate
# would suppress it for a whole cooldown. So a failed send restores the previous
# stamp value (or unsets it when there was none). The bound still holds — one
# ATTEMPT per cycle, and a persistently failing `gc mail send` is delivering
# nothing to storm with.
#
# SUPPRESSION IS ON THE MAIL, NOT ON THE OBSERVATION. Every invocation prints its
# verdict on stdout, suppressed ones included, so the patrol log still shows the
# item is stuck. Silence would trade a mail storm for a blind spot.
#
# AT MOST ONCE MEANS AT MOST ONCE CONCURRENTLY TOO. Read prior stamp -> decide ->
# stamp -> mail is a lost update waiting to happen: two cycles for the same
# anchor+kind (a patrol overlapping its own next pass, a patrol plus a hand-run
# gate) can both read "no prior stamp" before either writes, and both mail. So the
# section runs under a mutex keyed on anchor+kind — see TAKE THE LOCK below for
# why it is not a `gc`-level compare-and-set, and why every way it can fail
# resolves toward sending rather than toward silence.
#
# ...BUT A HELD LOCK IS NOT A VERDICT. The mutex ORDERS decisions; it never makes
# one. Treating "a peer holds it" as "therefore suppress" reintroduces the mute
# from a new direction: the peer's situation is not necessarily ours. If the
# holder is re-reporting an unchanged `--state` while WE carry a changed one, the
# holder correctly suppresses and we — deciding nothing — send nothing, so a
# genuinely new head oid or a flipped review decision is dropped entirely.
# Sequentially that same pair mails immediately, which is the contract: suppress
# repetition, never news. So a live lock is WAITED ON (bounded), and then the
# ordinary read/compare/stamp runs for OUR state. Waiting cannot deadlock the
# patrol: the wait is bounded, and on timeout we proceed unserialized like any
# other lock failure. Stamp-first is what makes that safe — a holder that got as
# far as mailing has already written the stamp we are about to read, so the
# unserialized path still converges on suppress when suppression is right.
#
# GENERALIZES BUT IS NOT YET WIRED ELSEWHERE. Nothing here is witness-specific —
# the su refinery's two escalations in the same incident are the same defect from
# the opposite direction, and `--kind refinery` would cover them. That change is
# deliberately NOT made here: tk-z4aka scopes this to mol-witness-patrol and asks
# that a refinery change be checked back first (su-xgz2 tracks that side).
#
# NOT set -e: this is called from a best-effort patrol pass and must never abort
# the wisp. Every exit is explicit.
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: escalation-gate.sh --anchor <bead-id> --subject <s> --body <b>
                          [--state <fingerprint>] [--kind <k>] [--cooldown <secs>]
                          [--to <addr>] [--force] [--dry-run]

  --anchor    bead the escalation is ABOUT; the dedup stamp lives on it (required)
  --subject   mail subject (required)
  --body      mail body (required)
  --state     fingerprint of the inputs holding the item — head oid,
              reviewDecision, mergeStateStatus. A change re-escalates at once.
              Omitted means "no state tracked": only the cooldown re-opens.
  --kind      escalation channel, default "witness". Names the sending ROLE, not
              the topic — see the header. One anchor + kind = one escalation.
  --cooldown  seconds before an UNCHANGED situation may re-mail (default 86400)
  --to        recipient, default "mayor/"
  --force     bypass the gate but still stamp (operator escape hatch)
  --dry-run   print the verdict; write nothing, send nothing

env:
  GC_ESCALATION_GATE_LOCKDIR  directory holding the per-anchor+kind mutex
                              (default /tmp/gc-escalation-gate). Set it to
                              isolate a test run from the live locks.
  GC_ESCALATION_GATE_LOCK_WAIT  seconds to wait for a live holder of that mutex
                              before proceeding unserialized (default 30). A
                              held lock delays this decision; it never makes it.

exit: 0 mailed or suppressed (both correct) · 1 not gated, nothing sent · 2 usage
USAGE
}

# WHY VALUE-TAKING OPTIONS ARE VALIDATED BEFORE THE SHIFT. The obvious arm,
# `OPT="${2:-}"; shift 2`, fails in two ways:
#
#   HANGS ON A MISSING VALUE. With the option last in argv there is no $2, so
#   `shift 2` FAILS and leaves argv untouched — and the `while [ $# -gt 0 ]` loop
#   below then spins forever. `set -e` would have aborted; this script
#   deliberately runs without it (see the header) so nothing stops it. A patrol
#   pass that hangs is strictly worse than the mail storm this script replaces.
#
#   EATS THE NEXT OPTION. `--body --dry-run` silently stores "--dry-run" as the
#   body and swallows the flag, so the run mails a nonsense body instead of
#   reporting a usage error.
#
# Only an EXACT match against one of our own options is rejected. A value that
# merely begins with '-' is legitimate — a subject or body may open with a dash —
# and rejecting those would fail closed on a real escalation, the silent mute
# this script must never become.
#
# This is a function, not a subshell, so `exit 2` exits the script: a usage error
# stamps nothing and sends nothing.
require_value() {
  # Called as `require_value "$@"` from inside the arm, so $1 is the option and
  # $2 its candidate value (absent when the option ends argv).
  if [ "$#" -lt 2 ]; then
    echo "escalation-gate: $1 requires a value" >&2
    usage
    exit 2
  fi
  case "$2" in
    --anchor|--subject|--body|--state|--kind|--cooldown|--to|--force|--dry-run|-h|--help)
      echo "escalation-gate: $1 requires a value, but the next argument is the option '$2'" >&2
      usage
      exit 2 ;;
  esac
}

# Keep this in step with `[vars.escalation_cooldown] default` in
# mol-witness-patrol.toml. The formula's marked snippets DO pass
# `--cooldown {{escalation_cooldown}}`, so a rendered override is honored — but
# that var reaches the script unsubstituted on a `--root-only` pour (handled
# below), so this default is still what actually governs in the common case.
DEFAULT_COOLDOWN=86400

ANCHOR=""; SUBJECT=""; BODY=""; STATE=""; KIND="witness"
COOLDOWN="$DEFAULT_COOLDOWN"; TO="mayor/"; FORCE=0; DRY_RUN=0

# Every value-taking arm calls `require_value "$@"` FIRST, on the same line, so
# the `shift 2` that follows can never fail (see require_value above). Keep that
# shape when adding an option — `escalation-gate.test.sh` asserts it structurally,
# because no runtime test can cover an option that does not exist yet.
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)   require_value "$@"; ANCHOR="$2";   shift 2 ;;
    --subject)  require_value "$@"; SUBJECT="$2";  shift 2 ;;
    --body)     require_value "$@"; BODY="$2";     shift 2 ;;
    --state)    require_value "$@"; STATE="$2";    shift 2 ;;
    --kind)     require_value "$@"; KIND="$2";     shift 2 ;;
    --cooldown) require_value "$@"; COOLDOWN="$2"; shift 2 ;;
    --to)       require_value "$@"; TO="$2";       shift 2 ;;
    --force)    FORCE=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  usage; exit 2 ;;
    *)          echo "escalation-gate: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$ANCHOR" ] || [ -z "$SUBJECT" ] || [ -z "$BODY" ]; then
  echo "escalation-gate: --anchor, --subject and --body are all required" >&2
  usage
  exit 2
fi
# The kind becomes part of the metadata KEY (`escalated.<kind>`), written as
# `--set-metadata "<key>=<value>"`. A kind carrying '=' would split the pair at
# the wrong place; whitespace or a metacharacter would land a key no reader can
# address — either way the channel silently stops deduplicating and the storm is
# back. Constrain it to the character set bead metadata keys already use. This is
# a usage error like a bad --cooldown: it is caught before anything is sent, and
# the marked formula snippets do not pass --kind at all.
case "$KIND" in
  '')
    echo "escalation-gate: --kind must not be empty" >&2
    exit 2 ;;
  *[!A-Za-z0-9._-]*)
    echo "escalation-gate: --kind must contain only [A-Za-z0-9._-] (got '$KIND')" >&2
    exit 2 ;;
esac
case "$COOLDOWN" in
  '{{'*'}}')
    # An unsubstituted formula var. This one specific case must NOT be fatal:
    # mol-witness-patrol is poured `--root-only` and only `binding_prefix` is
    # passed as a --var, so a `[vars.x] default` is prose the agent hand-
    # substitutes, not data the pour materializes. Treating it as a usage error
    # would exit 2 and send NOTHING — failing closed on every escalation, a
    # silent mute strictly worse than the storm this script replaces. Fall back
    # to the default and say so.
    echo "escalation-gate: --cooldown was passed unsubstituted ('$COOLDOWN'); using the ${DEFAULT_COOLDOWN}s default" >&2
    COOLDOWN="$DEFAULT_COOLDOWN" ;;
  ''|*[!0-9]*)
    # Any other non-numeric value is a real typo — still fatal, and still before
    # anything is sent.
    echo "escalation-gate: --cooldown must be a whole number of seconds (got '$COOLDOWN')" >&2
    exit 2 ;;
esac

KEY="escalated.$KIND"
NOW=$(date +%s)

# TAKE THE LOCK.
#
# Everything from here to the mail is one critical section — read the prior stamp,
# decide, stamp, send, roll back on failure — and without serialization two
# concurrent invocations for the same anchor+kind both read "no prior stamp", both
# decide "first escalation", and both mail. That is an ordinary lost update, and it
# breaks the at-most-once property this whole script is for.
#
# WHY NOT A gc-LEVEL COMPARE-AND-SET. `gc bd update` does have conditional writes,
# but only `--if-assignee` and `--if-status` (write nothing, exit 13 on mismatch),
# and both guard a FIELD. The stamp is a METADATA key; there is no --if-metadata,
# so "write this stamp only if the one I read is still there" is not expressible.
# Hence a mutex.
#
# WHY mkdir. It is atomic on every POSIX filesystem and needs nothing installed —
# `flock` is not on stock macOS, and a second code path is a second thing to get
# wrong. The lock is per anchor+kind, so unrelated anchors never contend.
#
# THIS IS NOT THE /tmp MARKER THE HEADER REJECTS. That one was dedup STATE, which
# fails in both directions: it outlives a session recycle (suppressing a needed
# escalation) and dies on reboot (letting the storm back). This is a MUTEX. It
# lives for exactly one invocation, and losing it costs only the serialization —
# never a suppressed escalation, never a forgotten one.
#
# HOW IT FAILS MATTERS MORE THAN THAT IT LOCKS. Every failure resolves toward
# DECIDING — and therefore, when the state warrants it, toward sending. None
# resolves toward silence, and none skips the decision:
#
#   HELD, FRESH    a peer is in the critical section for this same anchor+kind
#                  right now. WAIT for it, up to LOCK_WAIT, then decide normally.
#                  We must not adopt the peer's verdict as our own: it is deciding
#                  about the state IT observed, and if ours differs, ours is news
#                  (see "A HELD LOCK IS NOT A VERDICT" in the header).
#   HELD, TOO LONG the holder is still alive but slower than LOCK_WAIT (a wedged
#                  Dolt write). Proceed UNSERIALIZED with a warning rather than
#                  hang the patrol pass. Stamp-first keeps this honest: if the
#                  holder already mailed, we read its stamp and suppress anyway.
#   HELD, STALE    the holder died mid-section. Break the lock and proceed: a
#                  crashed peer must never mute an anchor forever.
#   CANNOT LOCK    the lock root is unwritable. Proceed UNSERIALIZED with a
#                  warning — the race costs a duplicate mail, and refusing would
#                  cost silence, which this script exists to prevent.
LOCK_TTL=300
LOCK_ROOT="${GC_ESCALATION_GATE_LOCKDIR:-/tmp/gc-escalation-gate}"
LOCK_DIR=""
# How long to wait for a LIVE holder before giving up on serialization. Sized for
# the critical section it guards — one `gc bd show`, one `gc bd update`, one
# `gc mail send`, each of which the ops guidance already treats as able to take
# seconds against a loaded Dolt. Past that the holder is wedged rather than busy,
# and a patrol pass that blocks on it is worse than an unserialized decision.
DEFAULT_LOCK_WAIT=30
LOCK_WAIT="${GC_ESCALATION_GATE_LOCK_WAIT:-$DEFAULT_LOCK_WAIT}"
case "$LOCK_WAIT" in
  ''|*[!0-9]*)
    # Never fatal: a mistyped env var must not stop an escalation, and this knob
    # only tunes how long we try to be tidy about ordering.
    echo "escalation-gate: GC_ESCALATION_GATE_LOCK_WAIT must be a whole number of seconds (got '$LOCK_WAIT'); using ${DEFAULT_LOCK_WAIT}s" >&2
    LOCK_WAIT="$DEFAULT_LOCK_WAIT" ;;
esac

release_lock() {
  # Only ever removes a lock THIS process took: LOCK_DIR is set solely on a
  # successful acquire, so a suppressed run cannot delete the peer's lock.
  [ -n "$LOCK_DIR" ] || return 0
  rm -f "$LOCK_DIR/at" 2>/dev/null
  rmdir "$LOCK_DIR" 2>/dev/null
  LOCK_DIR=""
}

lock_started() {
  # Epoch the lock was taken, or empty when that cannot be established. The
  # directory's own mtime is the primary source because mkdir sets it atomically
  # with the acquisition itself — there is no window where the lock exists but its
  # age does not. The `at` file is the fallback for a platform with neither stat
  # flavor. GNU first, BSD/macOS second.
  local at
  at=$(stat -c %Y "$1" 2>/dev/null) || at=$(stat -f %m "$1" 2>/dev/null) || at=""
  [ -n "$at" ] || at=$(cat "$1/at" 2>/dev/null)
  case "$at" in
    ''|*[!0-9]*) printf '' ;;
    *)           printf '%s' "$at" ;;
  esac
}

take_lock() {
  # ALWAYS returns 0 — the caller decides either way. The only question this
  # answers is whether the decision that follows is serialized against a peer, and
  # the two unserialized outcomes each say so on stderr. There is deliberately no
  # "return 1 = suppress": a lock is not a verdict, and the version that let it be
  # one dropped changed-state escalations on the floor.
  if ! mkdir -p "$LOCK_ROOT" 2>/dev/null; then
    echo "escalation-gate: cannot create lock dir $LOCK_ROOT; proceeding UNSERIALIZED — a duplicate escalation is better than a suppressed one" >&2
    return 0
  fi
  local dir key started age now deadline stale
  # The key lands in a path, so reduce it to the same character set the metadata
  # key already constrains --kind to. ANCHOR is a bead id; a stray character in it
  # must not escape the lock root.
  key=$(printf '%s.%s' "$ANCHOR" "$KIND" | tr -c 'A-Za-z0-9._-' '-')
  dir="$LOCK_ROOT/$key.lock"
  deadline=$(( NOW + LOCK_WAIT ))
  # Terminates unconditionally: every iteration either acquires, or re-checks a
  # clock that advances past `deadline`. LOCK_WAIT=0 makes this exactly one pass.
  while : ; do
    if mkdir "$dir" 2>/dev/null; then
      LOCK_DIR="$dir"
      printf '%s\n' "$NOW" > "$dir/at" 2>/dev/null
      return 0
    fi
    now=$(date +%s)
    # A clock we cannot read must not become an unbounded wait: `[ "" -ge N ]` is
    # an error, not a false, so the deadline test below would never fire and this
    # loop would spin forever. A patrol pass that hangs is worse than the storm
    # this script replaces (see the header), so treat it as "time is up".
    case "$now" in ''|*[!0-9]*) now="$deadline" ;; esac
    started=$(lock_started "$dir")
    stale=0
    if [ -z "$started" ]; then
      # An age we cannot read at all — only possible on a platform with no `stat`
      # in the microseconds before `at` is written. Breaking is no worse than
      # having no lock; leaving it would wedge the anchor permanently, the mute.
      stale=1
    else
      age=$(( now - started ))
      [ "$age" -lt 0 ] && age=0
      [ "$age" -ge "$LOCK_TTL" ] && stale=1
    fi
    if [ "$stale" = "1" ]; then
      rm -f "$dir/at" 2>/dev/null
      rmdir "$dir" 2>/dev/null
      if mkdir "$dir" 2>/dev/null; then
        LOCK_DIR="$dir"
        printf '%s\n' "$NOW" > "$dir/at" 2>/dev/null
        return 0
      fi
      # Another process broke it first and is now inside — a live holder again.
      # Fall through to the wait.
    fi
    if [ "$now" -ge "$deadline" ]; then
      echo "escalation-gate: $ANCHOR [$KIND] a peer has held the lock for over ${LOCK_WAIT}s; proceeding UNSERIALIZED — deciding late is recoverable, skipping the decision is not" >&2
      return 0
    fi
    sleep 1
  done
}

# --dry-run writes nothing and sends nothing, so it has no critical section to
# protect — and taking the lock would let a probe suppress a real escalation.
if [ "$DRY_RUN" != "1" ]; then
  trap release_lock EXIT
  take_lock
fi

# COMPARE ON A DIGEST, DISPLAY THE LABEL.
#
# The fingerprint shares one metadata value with the epoch, so the token must not
# contain the '@' separator, and it has to survive a round trip through bead
# metadata — which rules out a verbatim `--state`. The obvious fix, collapsing
# everything outside a conservative set to '-', is LOSSY, and lossy is the one
# thing this comparison cannot be: `abc/123` and `abc 123` both render `abc-123`,
# so a genuinely changed situation compares EQUAL to the one before it and is
# suppressed for a full cooldown. That is the gate becoming a mute — precisely
# the failure the state fingerprint exists to prevent, and worse than the storm
# because it is silent.
#
# So the token carries both: a sanitized LABEL for the log line (`state changed
# (X -> Y)` is unreadable as two hashes), and a digest of the RAW `--state` that
# actually decides. The comparison therefore turns on the raw value, never on
# what the label collapsed. The label is truncated because it is decoration;
# uniqueness never depends on it.
#
# Empty --state stays exactly '-' — a legitimate fingerprint meaning "no state
# tracked", so cooldown alone governs. Keeping that value byte-identical also
# means anchors tracking no state are not re-escalated for the format change
# alone. An anchor that DOES carry an old-format stamp reads as "state changed"
# once, mails once, and is stamped in the new format — converged after a single
# cycle, which is the same way a corrupt stamp is handled below.
state_digest() {
  # sha256, then the same value under BSD/macOS, then openssl; `cksum` is the
  # POSIX last resort (32-bit, weaker, still far better than the collapse above).
  # Only the first 16 hex chars are kept — 64 bits over the handful of distinct
  # fingerprints one anchor ever has.
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}' | cut -c1-16
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}' | cut -c1-16
  elif command -v openssl >/dev/null 2>&1; then
    printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}' | cut -c1-16
  else
    printf '%s' "$1" | cksum | awk '{print $1 "-" $2}'
  fi
}

if [ -z "$STATE" ]; then
  STATE_TOKEN="-"
else
  STATE_LABEL=$(printf '%s' "$STATE" | tr -c 'A-Za-z0-9._:-' '-' | tr -s '-' | cut -c1-64)
  STATE_TOKEN="$STATE_LABEL.$(state_digest "$STATE")"
fi

iso_of() {
  # GNU first, BSD/macOS second, raw epoch as the last resort — this only ever
  # feeds a log line, so an unparsed value must not fail the pass.
  date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || printf 'epoch:%s' "$1"
}

# Read the anchor. `tr -d` strips control characters BEFORE jq: bead notes carry
# raw escapes from prose, and one of those kills the parse, empties the read, and
# would silently downgrade this to "no prior stamp" — i.e. mail every cycle, the
# exact bug. Losing the parse must never look like losing the stamp.
#
# The class is EVERY control character, not the usual `\000-\010\013\014\016-\037`
# range that spares tab/LF/CR. jq rejects every unescaped C0 byte inside a string
# with the same "control characters from U+0000 through U+001F must be escaped"
# parse error — a raw tab in a note is as fatal as a raw \001, and prose is where
# tabs come from. Deleting them is safe in the other direction too: control bytes
# are never significant JSON syntax, and the whitespace between tokens that
# pretty-printing adds is optional, so a stripped payload parses identically.
#
# `[:cntrl:]` rather than a `\NNN` range so this line is byte-identical to the
# copy in mol-witness-patrol.toml, where a backslash would be eaten by the TOML
# """ string and ship something other than what the wiring test exercises.
ROW=$(gc bd show "$ANCHOR" --json 2>/dev/null | tr -d '[:cntrl:]')
ANCHOR_ID=$(printf '%s' "$ROW" | jq -r '.[0].id // empty' 2>/dev/null)
if [ -z "$ANCHOR_ID" ]; then
  # No anchor means nowhere to record that we escalated, and an escalation we
  # cannot bound is the storm this script exists to stop. Refuse to send.
  echo "escalation-gate: $ANCHOR [$KIND] NOT SENT — anchor bead unreadable; cannot bound the escalation, retry next cycle: $SUBJECT" >&2
  exit 1
fi

PRIOR=$(printf '%s' "$ROW" | jq -r --arg k "$KEY" '.[0].metadata[$k] // empty' 2>/dev/null)

DECISION="mail"
REASON="first escalation for this anchor"
if [ "$FORCE" = "1" ]; then
  REASON="forced (--force)"
elif [ -n "$PRIOR" ]; then
  # `<token>@<epoch>`; neither the sanitized label nor the digest can contain
  # '@' (see above), so the last '@' is unambiguously the separator.
  PRIOR_TOKEN="${PRIOR%@*}"
  PRIOR_EPOCH="${PRIOR##*@}"
  case "$PRIOR_EPOCH" in
    ''|*[!0-9]*)
      # A corrupt stamp cannot bound anything, and treating it as "recent" would
      # mute the anchor forever. Escalate and overwrite it with a well-formed
      # value — converges after exactly one mail.
      REASON="prior stamp unreadable ('$PRIOR'); re-escalating and rewriting it" ;;
    *)
      AGE=$(( NOW - PRIOR_EPOCH ))
      if [ "$PRIOR_TOKEN" != "$STATE_TOKEN" ]; then
        REASON="state changed since $(iso_of "$PRIOR_EPOCH") ($PRIOR_TOKEN -> $STATE_TOKEN)"
      elif [ "$AGE" -ge "$COOLDOWN" ]; then
        REASON="unchanged, but cooldown elapsed (${AGE}s >= ${COOLDOWN}s)"
      else
        DECISION="suppress"
        REASON="unchanged since $(iso_of "$PRIOR_EPOCH") (${AGE}s ago, cooldown ${COOLDOWN}s)"
      fi ;;
  esac
fi

if [ "$DECISION" = "suppress" ]; then
  # Still report it. The item IS stuck; only the mail is redundant.
  echo "escalation-gate: $ANCHOR_ID [$KIND] SUPPRESSED — $REASON: $SUBJECT"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "escalation-gate: $ANCHOR_ID [$KIND] WOULD ESCALATE — $REASON: $SUBJECT (dry run: nothing stamped, nothing sent)"
  exit 0
fi

# Stamp FIRST. Recording that we escalated is what bounds the next cycle, so a
# stamp we cannot write is a mail we must not send.
if ! gc bd update "$ANCHOR_ID" --set-metadata "$KEY=$STATE_TOKEN@$NOW" >/dev/null 2>&1; then
  echo "escalation-gate: $ANCHOR_ID [$KIND] NOT SENT — could not stamp $KEY; escalating unbounded is worse than escalating late, retry next cycle: $SUBJECT" >&2
  exit 1
fi

if gc mail send "$TO" -s "$SUBJECT" -m "$BODY" >/dev/null 2>&1; then
  echo "escalation-gate: $ANCHOR_ID [$KIND] ESCALATED to $TO — $REASON: $SUBJECT"
  exit 0
fi

# The send failed after the stamp landed. Undo the stamp, or the situation reads
# as "already escalated" for a full cooldown while the mayor was never told.
if [ -n "$PRIOR" ]; then
  gc bd update "$ANCHOR_ID" --set-metadata "$KEY=$PRIOR" >/dev/null 2>&1 \
    || echo "escalation-gate: $ANCHOR_ID [$KIND] could not restore prior stamp '$PRIOR'; next escalation may be suppressed until the cooldown elapses" >&2
else
  gc bd update "$ANCHOR_ID" --unset-metadata "$KEY" >/dev/null 2>&1 \
    || echo "escalation-gate: $ANCHOR_ID [$KIND] could not unset the stamp it just wrote; next escalation may be suppressed until the cooldown elapses" >&2
fi
echo "escalation-gate: $ANCHOR_ID [$KIND] NOT SENT — gc mail send failed; stamp rolled back so the next cycle retries: $SUBJECT" >&2
exit 1
