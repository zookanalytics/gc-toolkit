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
#     escalated.<kind> = <state-fingerprint>@<epoch-seconds>
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
# mol-witness-patrol.toml. The script's own default is the real floor: the
# formula may omit --cooldown entirely, so this is what actually governs.
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
if [ -z "$KIND" ]; then
  echo "escalation-gate: --kind must not be empty" >&2
  exit 2
fi
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

# The fingerprint shares one metadata value with the epoch, so it must not
# contain the '@' separator. Collapse everything outside a conservative set to
# '-'; that is lossy for display but never ambiguous for comparison, which is the
# only thing the value is used for. Empty --state becomes '-' — a legitimate
# fingerprint meaning "no state tracked", so cooldown alone governs.
STATE_TOKEN=$(printf '%s' "$STATE" | tr -c 'A-Za-z0-9._:-' '-' | tr -s '-')
[ -z "$STATE_TOKEN" ] && STATE_TOKEN="-"

iso_of() {
  # GNU first, BSD/macOS second, raw epoch as the last resort — this only ever
  # feeds a log line, so an unparsed value must not fail the pass.
  date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || printf 'epoch:%s' "$1"
}

# Read the anchor. `tr -d` strips control characters BEFORE jq: bead notes carry
# raw newlines and escapes from prose, and one of those kills the parse, empties
# the read, and would silently downgrade this to "no prior stamp" — i.e. mail
# every cycle, the exact bug. Losing the parse must never look like losing the
# stamp.
ROW=$(gc bd show "$ANCHOR" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037')
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
  # `<token>@<epoch>`; the token cannot contain '@' (sanitized above), so the
  # last '@' is unambiguously the separator.
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
