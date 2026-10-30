#!/usr/bin/env bash
# human-gate.sh — one open human gate per bead and situation. A human gate is
# Gas City's native bead for a wait a person must clear before work moves
# (`bd gate create --type=human`). It blocks the bead that waits: that bead
# leaves bd ready and the pool's offer, and bd refuses its close, until a person
# clears the gate with `bd gate resolve`, whose reason is the answer, headed
# `ruled:`, `moot:` or `benign:`. Any pack, formula or person may file one with
# that call, and every reader treats it the same. This helper makes the same
# call, and around it:
#   - it files nothing while an open human gate under the key already blocks
#     the bead, and resolves its own gate as a duplicate when a racing
#     writer's gate comes first;
#   - it files nothing inside a quiet period the call declares;
#   - it refuses a `*-wisp-*` id as the subject, a patrol wisp's or a
#     session's;
#   - it titles the gate with the message's first line, capped;
#   - it makes the gate's description the message it was given;
#   - it reads the gate back from the bead's side;
#   - it records a gate the deacon files in the deacon's incident ledger
#     (gc-deacon-ledger.sh).
#   human-gate.sh --subject <bead-id> --key <situation-key> --message <text>
#                 [--quiet-window <seconds>]
# The counterpart withdraws the filer's own gate once the situation it asked
# about has gone, resolving each open human gate under the key with a `moot:`
# reason:
#   human-gate.sh --retract --subject <bead-id> --key <situation-key> --message <reading>
# A changed situation gets a NEW key.
#
# The gate lands in the store of the bead it blocks, because `gc bd gate create`
# runs in the store that owns the bead named after --blocks, and a bead that
# exists nowhere fails the create. So the bead is passed as its own word and no
# --rig, --city or --db is passed. A wisp is refused: a patrol wisp or a session
# names no bead that can wait, so a situation with no bead of its own is a
# patrol finding (patrol-finding.sh), which a first reaction puts to a person as
# a human gate on the finding when it needs one.
# stdout carries the id of the open gate that asks as of this call's last read
# of the bead's gates (the one filed, the one already open, or the first one
# still open after this call resolves its own duplicate), and with --retract the
# id of each gate this call resolved. Everything else goes to stderr.
# Exit: 0 filed, already open, inside a declared quiet window, or (--retract)
# resolved or nothing open · 1 could not read the bead's gates, file, verify or
# resolve · 2 usage, or a wisp named as the subject
set -uo pipefail

PROG="human-gate"

# A gate's title is what the board's NEEDS cell shows for it, read at a glance,
# so it is capped at the headline cap gc-helm.sh takeaway enforces. The full
# message is the gate's description, so an over-cap first line is cut with an
# ellipsis, not refused.
TITLE_MAX=140

# The head of the reason a writer that lost a create race resolves its own
# gate with (below). It is headed `moot:`, because the duplicate needs nobody
# once the first gate asks. The quiet window skips a gate closed with it,
# because no person answered that gate.
DUP_REASON_HEAD="moot: a duplicate of gate"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: human-gate.sh --subject <bead-id> --key <situation-key> --message <text>
                     [--quiet-window <seconds>]
       human-gate.sh --retract --subject <bead-id> --key <situation-key>
                     --message <one-line reading>

  --subject       the bead that waits for the person; the gate blocks it
                  (required). One bead id, [A-Za-z0-9._-] only. A `*-wisp-*`
                  id names a patrol wisp or a session and is refused: file a
                  patrol finding with patrol-finding.sh instead.
  --key           names the SITUATION, not the wording: one open gate per bead
                  and key. It is the gate's await id. [A-Za-z0-9._-] only
                  (required).
  --message       what the person must clear. The first line is the gate's
                  title, cut at 140 characters; the whole text is its
                  description (required).
  --quiet-window  seconds after a person answered the situation `moot:` or
                  `benign:` during which a re-detection files nothing. Off
                  unless given. Declare it only at a call site that re-detects
                  one persisting condition every pass, and say why there; a
                  call that files an event declares none, so a new occurrence
                  is never muted by the answer to an earlier one.
  --retract       resolve each open human gate under the key that blocks the
                  bead, with the reason `moot: <message>`, instead of filing.
                  The caller owns the judgment that the situation is gone. No
                  open gate is a no-op success.
U
}

warn() { echo "$PROG: $*" >&2; }

SUBJECT=""; KEY=""; MESSAGE=""; QUIET_WINDOW=""; RETRACT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --subject)      SUBJECT="${2:-}";      shift 2 || { usage; exit 2; } ;;
    --key)          KEY="${2:-}";          shift 2 || { usage; exit 2; } ;;
    --message)      MESSAGE="${2:-}";      shift 2 || { usage; exit 2; } ;;
    --quiet-window) QUIET_WINDOW="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --retract)      RETRACT=1; shift ;;
    -h|--help)      usage; exit 2 ;;
    *) warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done
if [ -z "$SUBJECT" ] || [ -z "$KEY" ] || [ -z "$MESSAGE" ]; then
  warn "--subject, --key and --message are all required"; usage; exit 2
fi
# The key is matched exactly against each gate's await id.
case "$KEY" in
  *[!A-Za-z0-9._-]*) warn "--key must contain only [A-Za-z0-9._-] (got '$KEY')"; exit 2 ;;
esac
# The subject is one bead id. A space in it usually comes from an unquoted
# expansion that did not word-split (zsh does not), which joins the id to the
# word beside it, and `gc bd` would then route the call by the wrong word.
case "$SUBJECT" in
  *[!A-Za-z0-9._-]*)
    warn "--subject must be one bead id, [A-Za-z0-9._-] only (got '$SUBJECT'). An id joined to its neighbour usually comes from an unquoted \$VAR that did not word-split (zsh does not split it); read each field into its own variable, as 'while read -r SID SWHEN' does, and pass the id alone. Nothing was filed or resolved."
    exit 2 ;;
esac
case "$QUIET_WINDOW" in
  '') ;;
  *[!0-9]*) warn "--quiet-window takes a whole number of seconds (got '$QUIET_WINDOW')"; exit 2 ;;
esac
if [ "$RETRACT" = 1 ] && [ -n "$QUIET_WINDOW" ]; then
  warn "--quiet-window applies to a filing; --retract resolves gates and keeps no window"; exit 2
fi

# A patrol wisp is burned and re-poured every cycle, and a session id names no
# work, so neither is a bead that can wait. A gate on one would block nothing
# once the wisp burns, and the next pass would file again.
case "$SUBJECT" in
  *-wisp-*)
    warn "'$SUBJECT' names a patrol wisp or a session, not a bead that can wait for a person. Nothing was filed or resolved. A situation with no bead of its own is a patrol finding: file it with patrol-finding.sh --key $KEY --title <one line> --message <text>, and its first reaction files a human gate on the finding when a person must answer."
    exit 2 ;;
esac

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }

# Every decision below reads the bead's human gates through its `blocks` edges,
# the one reader rule, closed gates included, and tells the open ones by
# open_human_gate, bd-lib.sh's rule of which gates still hold. A subject that
# names no bead fails this read, and nothing is filed or resolved on an
# unreadable one.
if ! GATES=$(bd_human_gates "$SUBJECT"); then
  warn "could not read the human gates of '$SUBJECT' (no such bead, or its store did not answer). Nothing was filed or resolved."
  exit 1
fi
# The open human gates under the key are read in bd-lib.sh's one order
# (bd_gates_open_under_key), so two writers that read the same gates name the
# same first gate, and await-ruling.sh waits on that gate too.

# >>> retract-moot
# --retract withdraws the filer's own gate: it resolves every open human gate
# under the key among the bead's gates, with a `moot:` reason, because the
# situation it asked about is gone. A gate that blocks several beads is
# resolved once, and every bead it held is released. A sitting may be
# discussing the gate, and the retract clears it anyway; the sitting learns it
# at its sign-off, which reads each gate back. bd reports success on a gate
# another resolver closed first and keeps that resolver's reason, so each gate
# is read back, and a reason other than ours is reported as the answer that
# stood. A retract interrupted part way leaves gates the next retract for the
# situation finds and resolves.
if [ "$RETRACT" = 1 ]; then
  REASON="moot: $MESSAGE"
  OPEN_IDS=$(printf '%s' "$GATES" | bd_gates_open_under_key "$KEY" | jq -r '.[].id' 2>/dev/null)
  if [ -z "$OPEN_IDS" ]; then
    warn "no open human gate under [$KEY] blocks $SUBJECT — nothing to withdraw"
    exit 0
  fi
  RETRACT_RC=0
  while IFS= read -r GATE; do
    [ -n "$GATE" ] || continue
    gc bd gate resolve "$GATE" --reason "$REASON" </dev/null >/dev/null 2>&1
    ROW=$(bd_json show "$GATE")
    GOT_STATUS=$(printf '%s' "$ROW" | jq -r 'if type == "array" then (.[0].status // "") else "" end' 2>/dev/null)
    GOT_REASON=$(printf '%s' "$ROW" | jq -r 'if type == "array" then (.[0].close_reason // "") else "" end' 2>/dev/null)
    if [ "$GOT_STATUS" != closed ]; then
      warn "gate $GATE on $SUBJECT [$KEY] did not resolve (status reads '${GOT_STATUS:-unreadable}'); it stays open for a person. repair: gc bd gate resolve $GATE --reason \"$REASON\""
      RETRACT_RC=1
      continue
    fi
    if [ "$GOT_REASON" = "$REASON" ]; then
      warn "withdrew gate $GATE on $SUBJECT [$KEY]"
    else
      warn "gate $GATE on $SUBJECT [$KEY] was already cleared; its answer stands: $GOT_REASON"
    fi
    printf '%s\n' "$GATE"
  done <<RETRACT_EOF
$OPEN_IDS
RETRACT_EOF
  exit "$RETRACT_RC"
fi
# <<< retract-moot

# An open human gate under the key means the person is already asked. That
# holds for a gate filed on another bead that this one already waits on, such
# as the bring-current gate on an anchor that its rework child waits on too.
OPEN_GATE=$(printf '%s' "$GATES" | bd_gates_open_under_key "$KEY" | jq -r '.[0].id // empty' 2>/dev/null)
if [ -n "$OPEN_GATE" ]; then
  warn "gate $OPEN_GATE already asks for $SUBJECT [$KEY] — not filing another"
  printf '%s\n' "$OPEN_GATE"
  exit 0
fi

# The quiet period the call declares. The newest closed gate under the key
# that a person answered decides: a reason headed `moot:` or `benign:` says a
# person judged the situation needs nobody, and a re-detection inside the
# window files nothing. Any other answer means the person acted, so the next
# occurrence stands on new ground. A gate a writer resolved as its own
# duplicate is skipped, because nobody judged the situation by closing it, and
# it can close after the person's answer, when its repair runs later. Without
# --quiet-window there is no window, because only the filer knows whether a
# repeat is the same condition seen again or a new event.
if [ -n "$QUIET_WINDOW" ] && [ "$QUIET_WINDOW" -gt 0 ]; then
  QUIET_ROW=$(printf '%s' "$GATES" | jq -r --arg k "$KEY" --arg dup "$DUP_REASON_HEAD " '
    [ .[] | select((.await_id // "") == $k and (.status // "") == "closed")
          | select((.close_reason // "") | tostring | startswith($dup) | not)
          | { id: .id, reason: (.close_reason // ""),
              at: (((.closed_at // "") | sub("\\.[0-9]+"; "") | fromdateiso8601?) // 0) }
          | select(.at > 0) ]
    | sort_by(.at) | last
    | if . == null then empty
      elif (.reason | test("^(moot|benign):"))
      then [ .id, ((now - .at) | floor | tostring), (.reason | split("\n")[0]) ] | @tsv
      else empty end' 2>/dev/null)
  if [ -n "$QUIET_ROW" ]; then
    Q_ID="${QUIET_ROW%%$'\t'*}"; Q_REST="${QUIET_ROW#*$'\t'}"
    Q_AGE="${Q_REST%%$'\t'*}";   Q_REASON="${Q_REST#*$'\t'}"
    case "$Q_AGE" in ''|*[!0-9]*) Q_AGE="" ;; esac
    if [ -n "$Q_AGE" ] && [ "$Q_AGE" -lt "$QUIET_WINDOW" ]; then
      warn "$SUBJECT [$KEY] was answered ${Q_AGE}s ago on gate $Q_ID ($Q_REASON) — not filing another inside the declared ${QUIET_WINDOW}s quiet window. A situation that has CHANGED takes a new --key."
      exit 0
    fi
  fi
fi

# The title is the first line of the message, whitespace collapsed and cut at
# the cap with an ellipsis. bd caps a title at 500 bytes, and a codepoint cap
# alone overruns that once the tail is in 4-byte characters, so the title is
# also held under 400 bytes.
TITLE=$(printf '%s' "$MESSAGE" | head -n 1 | jq -Rsr --argjson n "$TITLE_MAX" \
  '((gsub("\\s+"; " ")) | sub("^ "; "") | sub(" $"; "")) as $h
   | if ($h | length) > $n then (($h[:($n - 1)]) | sub("\\s+$"; "")) + "…" else $h end
   | until(utf8bytelength <= 400; (.[:-2] | sub("\\s+$"; "")) + "…")' 2>/dev/null) \
  || TITLE=$(printf '%s' "$MESSAGE" | head -n 1 | cut -c1-"$TITLE_MAX")
[ -n "$TITLE" ] || TITLE="$KEY"

CREATE_JSON=$(gc bd gate create --type=human --blocks "$SUBJECT" --await-id "$KEY" \
  --title "$TITLE" --reason "$MESSAGE" --json </dev/null 2>/dev/null | grep -a -vE '^gc bd:' | scrub)
GATE=$(printf '%s' "$CREATE_JSON" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
if [ -z "$GATE" ] || [ "$GATE" = null ]; then
  CREATE_ERR=$(printf '%s' "$CREATE_JSON" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null)
  warn "bd gate create returned no id${CREATE_ERR:+: $CREATE_ERR} — nothing filed on $SUBJECT [$KEY]"
  exit 1
fi

# The gate's description is the whole message: what the person reads, and what
# a filer that keeps its report current compares against. bd gate create puts a
# head of its own above the reason it is given and takes no description, so the
# description is set to the message in a second write, which the read-back below
# checks. Filing is rare beside the dedup above, so the write is paid once per
# gate.
gc bd update "$GATE" --description "$MESSAGE" </dev/null >/dev/null 2>&1 || true

# The gate asks only while it blocks the bead under the key, so its edge, its
# type and its await id are read back from the bead's side, the read every other
# reader makes.
if ! GOT=$(bd_human_gates "$SUBJECT"); then
  warn "gate $GATE was filed, but the human gates of $SUBJECT did not read back; check that it blocks $SUBJECT under [$KEY]: gc bd dep list $SUBJECT --type blocks --json"
  exit 1
fi
if ! printf '%s' "$GOT" | bd_gates_open_under_key "$KEY" | jq -e --arg g "$GATE" 'any(.[]; .id == $g)' >/dev/null 2>&1; then
  warn "gate $GATE was filed, but it does not read back as an open human gate under [$KEY] that blocks $SUBJECT; repair: gc bd dep add $SUBJECT $GATE --type=blocks, then check its await id with gc bd show $GATE"
  exit 1
fi
# A description that did not take still leaves a gate that asks, its message
# under bd's head, so the filing stands and only the repair is named.
if ! printf '%s' "$GOT" | jq -e --arg g "$GATE" --arg m "$MESSAGE" 'any(.[]; .id == $g and (.description // "") == $m)' >/dev/null 2>&1; then
  warn "gate $GATE asks for $SUBJECT [$KEY], but its description did not become the message, so bd's own head stands above it; repair: gc bd update $GATE --description <the message>"
fi

# bd keeps no idempotency at create, so two writers racing in the same instant
# can both pass the dedup above and file. Each reads the gates back after its
# own create, and a writer whose gate is not the first resolves it as a
# duplicate and names the gate still open. A writer resolves only the gate it
# filed, because the other writer's caller may already wait on its own gate by
# id. Two gates stand only when one create landed after the other writer read
# back, and then the bead moves once both are cleared.
FIRST_GATE=$(printf '%s' "$GOT" | bd_gates_open_under_key "$KEY" | jq -r '.[0].id // empty' 2>/dev/null)
if [ -n "$FIRST_GATE" ] && [ "$FIRST_GATE" != "$GATE" ]; then
  DUP_REASON="$DUP_REASON_HEAD $FIRST_GATE, filed for the same situation in the same instant"
  gc bd gate resolve "$GATE" --reason "$DUP_REASON" </dev/null >/dev/null 2>&1
  # bd's exit says nothing about whether the duplicate closed: it reports
  # success on a resolve that closed nothing and on a gate another resolver
  # closed first, as the retract above finds. So the duplicate is read back.
  DUP_ROW=$(bd_json show "$GATE")
  DUP_STATUS=$(printf '%s' "$DUP_ROW" | jq -r 'if type == "array" then (.[0].status // "") else "" end' 2>/dev/null)
  DUP_GOT=$(printf '%s' "$DUP_ROW" | jq -r 'if type == "array" then (.[0].close_reason // "") else "" end' 2>/dev/null)
  if [ "$DUP_STATUS" != closed ]; then
    warn "this call's gate $GATE duplicates gate $FIRST_GATE and did not resolve (its status reads '${DUP_STATUS:-unreadable}'), so $SUBJECT stays blocked until both are cleared. repair: gc bd gate resolve $GATE --reason \"$DUP_REASON\""
  elif [ "$DUP_GOT" = "$DUP_REASON" ]; then
    warn "resolved this call's duplicate, gate $GATE, of gate $FIRST_GATE"
  else
    warn "this call's duplicate, gate $GATE, was already cleared, and its answer stands: $DUP_GOT"
  fi
  # The gate named is the one still open once this call's own is resolved.
  # FIRST_GATE can itself be a duplicate: with three writers racing, a third
  # gate that came first but was not yet in this call's read-back can be in
  # FIRST_GATE's writer's, and that writer resolves FIRST_GATE in the same
  # instant. So the gates are read again, and the first open one under the key
  # is named. A read that fails, or finds none open, names FIRST_GATE. The name
  # is the gate that asks as of that read, so a caller that waits later reads
  # the gate again in the same order (bd_gates_open_under_key), as
  # await-ruling.sh does.
  ASKS=$(bd_human_gates "$SUBJECT" | bd_gates_open_under_key "$KEY" | jq -r '.[0].id // empty' 2>/dev/null)
  [ -n "$ASKS" ] || ASKS="$FIRST_GATE"
  warn "gate $ASKS already asks for $SUBJECT [$KEY]"
  printf '%s\n' "$ASKS"
  exit 0
fi

# The deacon's shift record. Filing a gate is a non-routine action, and this is
# the only place that holds the gate id it points at, so the entry is written
# here rather than asked for at each call site. Gated to the deacon because the
# ledger records what the deacon did: every other caller files about its own
# work. A dedup or quiet-window exit above writes nothing, because the situation
# reached the ledger on the pass that filed it. A ledger failure is reported and
# never changes this exit: the gate is filed either way.
# >>> deacon-ledger-append
LEDGER_ROLE="${GC_AGENT:-}"; LEDGER_ROLE="${LEDGER_ROLE##*/}"; LEDGER_ROLE="${LEDGER_ROLE##*.}"
if [ "$LEDGER_ROLE" = deacon ]; then
  LEDGER_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/gc-deacon-ledger.sh"
  if [ -x "$LEDGER_SH" ]; then
    "$LEDGER_SH" append escalation "$KEY: $TITLE" "bead:$GATE" >/dev/null \
      || warn "gate $GATE is filed, but its ledger entry was not written"
  else
    warn "no executable gc-deacon-ledger.sh beside this script; gate $GATE is filed but absent from the ledger"
  fi
fi
# <<< deacon-ledger-append

warn "filed gate $GATE on $SUBJECT [$KEY]"
printf '%s\n' "$GATE"
exit 0
