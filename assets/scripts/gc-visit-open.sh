#!/bin/sh
# gc-visit-open.sh — operator-origin visit intake: turn "I need an agent on
# topic X" into a routed, durable conversation in one command (tk-4ojka).
#
# Usage:
#   gc-visit-open "<topic>"            open a conversation on a NEW topic
#   gc-visit-open <bead-id>            open a conversation on an EXISTING bead
#   gc-visit-open "<topic>" --rig gascity   file it in another rig's ledger
#   gc-visit-open "<topic>" --no-react      skip the first reaction, file now
#   gc-visit-open "<topic>" --type decision force the subject bead's type
#   gc-visit-open "<topic>" --topic         "tk-abc12"-shaped strings are topics
#
# ── The affordance this restores ─────────────────────────────────────
# Under the retired -thread model the operator could hit a key and say "I
# need an agent on topic X" at any moment. Threads were dropped for the
# converse model because they had no persistence behind them. Converse has
# exactly that persistence — an open visit outlives sessions, queues
# indefinitely at zero session cost (agents/converse/agent.toml bounds live
# SITTINGS, not open visits), and is recovered by witness patrol or
# `gc bd reclaim` if its session dies — but the INTAKE half was never carried
# across. Every existing visit producer (mol-first-reaction,
# detect-stalled-workflows.sh, gc-helm.sh open) is agent-origin and attaches
# to a bead that already exists. For a topic with no bead yet, the operator's
# only route was four hand-assembled commands that require knowing the
# rig-qualified pool name. This is that route, as one command.
#
# ── What it does NOT own ─────────────────────────────────────────────
# Visit filing. That lives once, in `gc-helm.sh open`'s marked gate-visit
# block, and this script CALLS it rather than copying it — so the visit
# metadata shape, the subject-existence gate (tk-ujwvt), the one-open-visit-
# per-subject gate, and the board cache bust are inherited rather than
# re-derived. `assets/scripts/gate-visit.test.sh` guards that single copy.
# What this script owns is everything upstream of the visit: which rig, the
# subject bead, and which of the two intake paths runs.
#
# ── The two paths (operator ruling, 2026-08-14) ──────────────────────
# PREFERRED — react: create the subject, then sling `mol-first-reaction` at
#   it (formulas/mol-first-reaction.toml, via gc-helm.sh react →
#   tools/gc-proactive.sh sling, which bakes in the codex-gated mr path).
#   The reaction reads the topic, writes a first-reaction CARD to the
#   subject's notes, and FILES THE VISIT itself in its advance-and-drain
#   step. The operator arrives at a framed conversation instead of a blank
#   one. This script files nothing on that path — a second visit would split
#   the conversation.
# FALLBACK — direct: create the subject and file the visit immediately. Taken
#   on --no-react, and taken AUTOMATICALLY whenever the proactive surface
#   cannot deliver (see the deliverability gate below). Costs the framing
#   card; guarantees the conversation exists.
#
# ── Why the fallback is not optional ─────────────────────────────────
# The reaction path is fire-and-forget: `gc sling` routes the subject and
# returns 0, and the visit appears only if a proactive session is later
# spawned to run the formula. TWO independent clamps can prevent that spawn,
# and NEITHER is visible in the sling's exit status:
#   * proactive auto-spawn is DEFAULT-DISABLED (GC_PROACTIVE_ENABLED unset →
#     agents/proactive/agent.toml's work_query and scale_check both emit "no
#     demand" forever); and
#   * at GC_PROACTIVE_CITY_CAP the pool sheds first under session pressure —
#     `gc-proactive.sh sling` logs "proactive sheds" and returns 0 anyway.
# Under either one, an unguarded react path would leave the topic as a routed
# bead nobody ever picks up and NO visit at all: a topic that looks filed and
# is silently forgotten. That is precisely the failure mode this channel
# exists to eliminate, and it is the DEFAULT configuration, not an edge case.
# So the path is chosen by asking `gc-proactive.sh deliverable` FIRST, and the
# answer is printed — the operator always knows whether a visit exists yet.
#
# ── Exit codes ───────────────────────────────────────────────────────
#   0  a conversation is queued (visit filed, or first reaction slung)
#   2  usage error (no topic, unknown flag, unknown rig)
#   3  environment failure (cannot enumerate rigs, gc-helm.sh missing).
#      The rig-enumeration failures share this code but not the message:
#      gc exiting non-zero, an empty / unparseable / wrong-shaped answer
#      and a legitimately rigless city each name their own operator move
#      (tk-lzdty), matching gc-helm.sh's taxonomy so the two front doors
#      cannot tell the operator different stories.
#   4  runtime failure (subject bead create failed, visit filing failed)
#
# Side effects: creates ONE bead (the subject) and then either slings a
# formula at it or files ONE visit on it. Closes nothing, merges nothing.
set -u

PROG="gc-visit-open"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
HELM="${GC_HELM_TOOL:-$SCRIPT_DIR/gc-helm.sh}"
PROACTIVE_TOOL="${GC_PROACTIVE_TOOL:-$SCRIPT_DIR/../../tools/gc-proactive.sh}"

# The default rig (operator ruling, 2026-08-14). Converse is scope="rig" and
# the pool name is rig-qualified, so a topic that is not rig-specific still
# has to land somewhere. It is deliberately NOT inferred from cwd: this is
# fired from wherever the operator happens to be sitting, and silently filing
# a topic in whatever rig that shell was pointed at is the worst failure mode
# an intake path can have. A wrong-but-FIXED default is discoverable; a
# wrong-and-VARYING one is not.
DEFAULT_RIG="${GC_VISIT_DEFAULT_RIG:-gc-toolkit}"

usage() {
    cat >&2 <<'EOF'
Usage:
  gc-visit-open "<topic>" [--rig <rig>] [--no-react] [--type <t>] [--topic]
  gc-visit-open <bead-id>  [--no-react]

Opens a durable conversation in one step. A topic string becomes a subject
bead; an existing bead id is used as the subject as-is. Either way a visit is
queued for the rig-qualified converse pool, which holds the conversation.

  --rig <rig>    File the subject in this rig's ledger (default: gc-toolkit;
                 override with GC_VISIT_DEFAULT_RIG). Ignored for a bead id —
                 an existing bead's own rig is authoritative.
  --no-react     Skip the proactive first reaction and file the visit now.
                 Faster and unconditional; you lose the framing card.
  --type <t>     Subject bead type (default: task, or decision when the topic
                 reads as a question).
  --topic        Treat the argument as a topic even if it looks like a bead id.
  -h, --help     This help.

Without --no-react the topic is handed to a proactive first reaction, which
writes a framing card and files the visit itself — but ONLY when that pool can
actually run. When it cannot (auto-spawn disabled, or the city is at the
session cap) this falls back to filing the visit directly and says so.
EOF
}

# die <message> [exit-code] — $1 only, never $* : the code is the SECOND
# argument, and joining both into the message prints it as trailing noise.
die()   { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-4}"; }
note()  { printf '%s\n' "$*" >&2; }

# ── The subject's title ──────────────────────────────────────────────
# `bd create` refuses a title over 500 bytes. The topic key exists so the
# operator can type a PARAGRAPH — that is the whole rationale of the popup
# (tk-w4dp4), which is deliberately sized multi-line to invite one — so handing
# the topic through as the title made the key fail exactly when it was used as
# designed: a 579-character paragraph was refused, and the draft's only route
# into the ledger with it (tk-wp50s, hit live 2026-08-22).
#
# Shortening costs nothing, because the title is not where the topic lives.
# SUBJ_BODY carries $ARG verbatim and the converse session reads the BODY at
# claim time, so the title only has to be a findable label on the board. Capped
# well under the library's 500 so the value stays a label rather than a
# paragraph that happens to fit, and so this does not have to track that limit.
#
# Bytes, even though the refusal says "characters": a 600-character CJK title
# is refused as "got 1800". So this is a byte budget too, which is what
# `${#var}` measures in the shell this runs under.
TITLE_MAX=200

# derive_title <text> — a one-line board label for a free-text topic.
#
# Whitespace (newlines included) collapses to single spaces: a multi-line title
# renders as garbage on every surface that shows one, and the popup hands us
# multi-line input by design.
#
# An over-long topic is cut back to a WORD boundary, never to an offset — an
# offset cut can slice a multi-byte character in half and leave a title that is
# not valid UTF-8. Cutting at a SENTENCE boundary is deliberately not attempted:
# the period that ends a sentence is not distinguishable here from the one in
# "gc-visit-open.sh is slow", which would title itself "gc-visit-open."
derive_title() {
    _dt=$(printf '%s' "$1" | tr '\n\r\t' '   ' | tr -s ' ')
    _dt="${_dt# }"; _dt="${_dt% }"
    [ "${#_dt}" -le "$TITLE_MAX" ] && { printf '%s' "$_dt"; return 0; }

    # Drop whole trailing words until it fits, holding a byte back for the
    # ellipsis that marks the cut. That ellipsis is itself three bytes, so the
    # label can land two bytes over TITLE_MAX — which is the point of setting
    # TITLE_MAX nowhere near the 500 that actually matters.
    while [ "${#_dt}" -gt "$((TITLE_MAX - 1))" ]; do
        _dt_prev="$_dt"
        _dt="${_dt% *}"
        [ "$_dt" = "$_dt_prev" ] && break     # one unbroken token — no boundary to use
    done
    # Only reachable for one unbroken token — a URL, a hash, or a script whose
    # writing system does not put spaces between words. Nothing to cut on but
    # the byte, so cut, then drop the half-character that leaves at the end:
    # an invalid title is refused by the ledger, and a topic with no spaces in
    # it is exactly the input that would hit that.
    if [ "${#_dt}" -gt "$((TITLE_MAX - 1))" ]; then
        while [ "${#_dt}" -gt "$((TITLE_MAX - 1))" ]; do _dt="${_dt%?}"; done
        # Keyed on OUTPUT, not exit status: iconv reports a trailing incomplete
        # sequence as a failure while still emitting the valid prefix, which is
        # exactly the repair wanted. Empty output means no iconv — keep the cut.
        _dt_utf8=$(printf '%s' "$_dt" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null)
        [ -n "$_dt_utf8" ] && _dt="$_dt_utf8"
    fi
    printf '%s…' "${_dt% }"
}

# ── Argument parsing ─────────────────────────────────────────────────
ARG=""; RIG=""; NO_REACT=""; SUBJ_TYPE=""; FORCE_TOPIC=""
while [ $# -gt 0 ]; do
    case "$1" in
        --rig=*)   RIG="${1#--rig=}"; shift ;;
        --rig)     shift; [ $# -gt 0 ] || { echo "$PROG: --rig requires a value" >&2; exit 2; }
                   RIG="$1"; shift ;;
        --type=*)  SUBJ_TYPE="${1#--type=}"; shift ;;
        --type)    shift; [ $# -gt 0 ] || { echo "$PROG: --type requires a value" >&2; exit 2; }
                   SUBJ_TYPE="$1"; shift ;;
        --no-react) NO_REACT=1; shift ;;
        --topic)   FORCE_TOPIC=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --)        shift; [ $# -gt 0 ] && { [ -z "$ARG" ] || { echo "$PROG: takes one topic or bead-id" >&2; exit 2; }; ARG="$1"; shift; } ;;
        -*)        echo "$PROG: unknown flag '$1'" >&2; usage; exit 2 ;;
        *)         [ -z "$ARG" ] || { echo "$PROG: takes one topic or bead-id (quote a multi-word topic)" >&2; exit 2; }
                   ARG="$1"; shift ;;
    esac
done
[ -n "$ARG" ] || { echo "$PROG: needs a topic string or a bead id" >&2; usage; exit 2; }

[ -f "$HELM" ] || die "cannot find gc-helm.sh (looked at $HELM) — visit filing lives there" 3

# ── Is the argument an existing bead, or a topic? ────────────────────
# Disambiguated by RIG PREFIX, not by shape alone: bead ids are
# <rig-prefix>-<suffix>, and the prefix set is enumerable (`gc rig list`). So
# "tk-abc12" resolves as an id in a city with a tk rig, while a hyphenated
# one-word topic like "dolt-latency" has no matching prefix and reads as the
# topic it is. Three outcomes, none of them a guess:
#   * prefix matches no rig      -> a topic, and a subject bead is created
#   * prefix matches, id resolves-> that bead is the subject
#   * prefix matches, id does NOT resolve -> gc-helm.sh's subject-exists gate
#     (tk-ujwvt) exits 4 with nothing filed, which is right: a typo must not
#     become a topic bead literally titled "tk-abc12", buried and unfindable
# The one genuine collision — a topic whose first word IS a rig prefix — is
# forced through with --topic.
looks_like_bead_id=""
case "$ARG" in
    *[!a-zA-Z0-9_-]*|-*) : ;;                       # whitespace/punctuation → a topic
    *-*) [ -n "$FORCE_TOPIC" ] || looks_like_bead_id=1 ;;
esac

RIGS=""
enumerate_rigs() {
    [ -n "$RIGS" ] && return 0
    # >>> rig-enumeration-taxonomy
    # Mirrors gc-helm.sh's enumerate_rigs on purpose: this script's own topic
    # path shells out to `gc-helm.sh open`, so the two front doors must not
    # give different accounts of why a city has no rigs. The old one-liner
    # piped gc straight into jq, which discards gc's exit status (a pipeline
    # reports the LAST command's) along with its stderr, and then reported a
    # wedged data plane, unparseable output and a genuinely rigless city with
    # one identical sentence (tk-lzdty). No timeout arm here — unlike
    # gc-helm.sh this script does not bound the call, so there is no kill to
    # report and claiming one would be a lie.
    _er_errf=$(mktemp 2>/dev/null || printf '')
    _er_rc=0
    if [ -n "$_er_errf" ]; then
        rigs_raw=$(gc rig list --json 2>"$_er_errf") || _er_rc=$?
        _er_why=$(tr '\n' ' ' < "$_er_errf" 2>/dev/null | cut -c1-300 | sed 's/  */ /g; s/^ *//; s/ *$//')
        rm -f "$_er_errf" 2>/dev/null || true
    else
        rigs_raw=$(gc rig list --json 2>/dev/null) || _er_rc=$?
        _er_why=""
    fi
    [ "$_er_rc" -eq 0 ] \
        || die "could not enumerate rigs: 'gc rig list' exited ${_er_rc}${_er_why:+ — $_er_why}. That is the data plane, not this script — try 'gc doctor' and check Dolt. This command wrote nothing." 3
    # jq -e separates the rest by exit status: 4 = no output at all,
    # 5 = would not parse, 1 = parsed but not the {"rigs":[…]} contract.
    _er_shape=0
    printf '%s' "$rigs_raw" | jq -e 'type=="object" and (.rigs|type)=="array"' >/dev/null 2>&1 || _er_shape=$?
    case "$_er_shape" in
        0) : ;;
        4) die "could not enumerate rigs: 'gc rig list --json' exited 0 but printed nothing. A silent empty answer usually means gc was killed or the city path is wrong — check GC_CITY and 'gc doctor'. This command wrote nothing." 3 ;;
        5) die "could not enumerate rigs: 'gc rig list --json' printed something that is not JSON${_er_why:+ — $_er_why}. Run it by hand to see what it actually emitted (a stray log line on stdout is the usual cause). This command wrote nothing." 3 ;;
        *) die "could not enumerate rigs: 'gc rig list --json' printed JSON with no '.rigs' array. That is a gc contract change, not a city problem. This command wrote nothing." 3 ;;
    esac
    RIGS=$(printf '%s' "$rigs_raw" | jq -c '[.rigs[]? | {name, path, prefix}]' 2>/dev/null)
    [ -n "$RIGS" ] || RIGS='[]'
    [ "$(printf '%s' "$RIGS" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ] \
        || die "no rigs in this city: 'gc rig list' answered normally with an empty rig set. Add one with 'gc rig add', or point GC_CITY at the intended city. This command wrote nothing." 3
    # <<< rig-enumeration-taxonomy
}

if [ -n "$looks_like_bead_id" ]; then
    enumerate_rigs
    prefix_hit=$(printf '%s' "$RIGS" | jq -r --arg p "${ARG%%-*}" \
        '.[] | select(.prefix==$p) | .name' 2>/dev/null | head -n1)
    [ -n "$prefix_hit" ] || looks_like_bead_id=""   # no such rig prefix → it is a topic
fi

# ── Resolve the subject ──────────────────────────────────────────────
if [ -n "$looks_like_bead_id" ]; then
    # An existing bead is its own subject, and its OWN rig is authoritative —
    # gc-helm.sh resolves that from the id prefix and points bd at the right
    # per-rig ledger. A --rig here would be a second, contradictory answer to
    # a question already settled, so it is refused rather than silently
    # ignored.
    [ -z "$RIG" ] || die "--rig does not apply to an existing bead ('$ARG' belongs to rig '$prefix_hit')" 2
    [ -z "$SUBJ_TYPE" ] || die "--type does not apply to an existing bead ('$ARG' already has a type)" 2
    SUBJECT="$ARG"
    RIG_NAME="$prefix_hit"
    SUBJ_DB=$(printf '%s' "$RIGS" | jq -r --arg n "$prefix_hit" \
        '.[] | select(.name==$n) | .path' 2>/dev/null | head -n1)
    [ -n "$SUBJ_DB" ] && SUBJ_DB="$SUBJ_DB/.beads"
    note "$PROG: subject $SUBJECT (existing bead, rig $RIG_NAME)"
else
    # ── Create the subject bead from the topic string ────────────────
    [ -n "$RIG" ] || RIG="$DEFAULT_RIG"
    enumerate_rigs
    RIG_PATH=$(printf '%s' "$RIGS" | jq -r --arg n "$RIG" '.[] | select(.name==$n) | .path' 2>/dev/null | head -n1)
    [ -n "$RIG_PATH" ] || die "unknown rig '$RIG' (try one of: $(printf '%s' "$RIGS" | jq -r '[.[].name] | join(", ")' 2>/dev/null))" 2
    [ -d "$RIG_PATH/.beads" ] || die "rig '$RIG' has no .beads ledger at $RIG_PATH/.beads" 3

    # Type: a question is a decision, everything else a task. A crude read of
    # a free-text topic, so --type overrides it; getting it wrong costs a
    # label on the board, not correctness.
    if [ -z "$SUBJ_TYPE" ]; then
        case "$ARG" in
            *\?) SUBJ_TYPE="decision" ;;
            *)   SUBJ_TYPE="task" ;;
        esac
    fi

    # The topic string is the whole of what was said at the keystroke, so it is
    # the durable seed in the BODY — the converse session reads the body at
    # claim time to rebuild what this is about, and a title alone strands it if
    # the operator typed a paragraph. The title is a label derived from it
    # (derive_title above), never the topic itself.
    SUBJ_BODY="$ARG

---
Operator-origin intake, filed by \`$PROG\` on $(date -u +%Y-%m-%dT%H:%M:%SZ).
The text above is the whole of what was said at the keystroke — the seed of a
conversation, not a specification. The title is a shortened label for the
board; this body is the record. Ask before assuming scope."

    SUBJ_TITLE=$(derive_title "$ARG")
    SUBJ_RAW=$(gc bd create -t "$SUBJ_TYPE" --title "$SUBJ_TITLE" -d "$SUBJ_BODY" \
        --db "$RIG_PATH/.beads" --json 2>/dev/null)
    SUBJ_RC=$?
    SUBJ_JSON=$(printf '%s' "$SUBJ_RAW" | tr -d '\000-\010\013\014\016-\037')
    SUBJECT=$(printf '%s' "$SUBJ_JSON" | jq -r '.id // .[0].id // empty' 2>/dev/null)
    if [ -z "$SUBJECT" ] || [ "$SUBJECT" = "null" ]; then
        # A refused create STATES its reason in .error, and keeping only .id
        # threw the whole of it away — the operator was told the create
        # "returned no id" for a refusal that was stated and fixable, and went
        # looking for a broken ledger instead of an over-long title (tk-wp50s).
        SUBJ_ERR=$(printf '%s' "$SUBJ_JSON" | jq -r '.error // .[0].error // empty' 2>/dev/null)
        [ -n "$SUBJ_ERR" ] || SUBJ_ERR="bd create returned no id and no error (exit $SUBJ_RC)"
        die "could not create the subject bead in rig '$RIG': $SUBJ_ERR — nothing filed" 4
    fi
    RIG_NAME="$RIG"
    SUBJ_DB="$RIG_PATH/.beads"
    note "$PROG: subject $SUBJECT created in rig $RIG_NAME ($SUBJ_TYPE)"
fi

# ── Record the origin as a KEY, not only as prose ────────────────────
# The body above says "Operator-origin intake, filed by …" for a human to read.
# That sentence is not a predicate: it has already drifted across two script
# generations plus one an agent typed by hand, and a `--desc-contains` sweep for
# it matches beads that merely QUOTE it (measured on this rig: 13 hits, 3 of them
# discussion, tk-2cyxo). So the same fact is recorded as `gc.origin=operator`,
# which is what `assets/scripts/detect-parked-dispositions.sh` selects on when it
# decides whether a parked subject is owed a visit back once its routed work
# lands. Without the key that sweep cannot see this subject at all.
#
# BOTH intake paths stamp it, because both are the operator asking for a
# conversation: typing a topic, and pointing at a bead that already exists. What
# is deliberately NOT stamped is `gc-helm.sh open` — picking a row off the board
# is the operator glancing at something, not commissioning it, and widening the
# key to that population would turn the narrow ruling ("operator-origin subjects
# only") into "nearly every subject".
#
# ONLY WHEN ABSENT, and never fatal. An existing bead may already carry an origin
# from somewhere else and this must not overrule it; and the deliverable of this
# script is the conversation, so a stamp that fails is a warning, not an exit —
# the visit still lands, and `backfill-operator-origin.sh` re-stamps later.
ORIGIN_NOW=$(gc bd show "$SUBJECT" --json 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037' \
    | jq -r 'if type == "array" then ((.[0].metadata // {})["gc.origin"] // "") else "" end' 2>/dev/null)
if [ -z "$ORIGIN_NOW" ]; then
    # shellcheck disable=SC2086  # ${SUBJ_DB:+--db "$SUBJ_DB"} expands to 0 or 2 space-free fields
    gc bd update "$SUBJECT" ${SUBJ_DB:+--db "$SUBJ_DB"} --set-metadata "gc.origin=operator" >/dev/null 2>&1 \
        || note "$PROG: could not stamp gc.origin=operator on $SUBJECT — the conversation is unaffected, but a parked disposition on this subject will not bring it back on its own (re-run assets/scripts/backfill-operator-origin.sh, or stamp it by hand)"
fi

# ── Path selection: can a slung first reaction actually be picked up? ─
# Asked once the subject is settled and before either path acts, so the answer
# can be reported alongside the ids in one summary — and so a usage error (an
# unknown rig, a missing topic) costs no session query at all. Delegated to
# gc-proactive.sh rather than restated, so this third caller cannot drift from
# the two copies of those clamps that already have to be kept in sync (the tool
# and agents/proactive/agent.toml).
REACT=""; REACT_WHY=""
if [ -n "$NO_REACT" ]; then
    REACT_WHY="--no-react: filing the visit directly"
elif [ ! -x "$PROACTIVE_TOOL" ]; then
    REACT_WHY="no: cannot find gc-proactive.sh (looked at $PROACTIVE_TOOL)"
else
    # Ask under the SUBJECT's rig. The answer is per-rig: the proactive pool
    # is rig-scoped (agents/proactive/agent.toml watches
    # {{.Rig}}/gc-toolkit.proactive), and both clamps are declared on that
    # pool's own city config, so the gate has to know which pool it is asking
    # about before it can read them. gc-proactive.sh qualifies its target from
    # GC_RIG and fails CLOSED when it is unset — and the caller that matters
    # most here, helm-svc, has no GC_RIG at all (it is a city-wide service),
    # so without this the gate answered "disabled" to the very front door the
    # board opens conversations through, and every visit was filed with no
    # framing card (tk-hscs0).
    #
    # Set for this ONE command rather than exported: RIG_NAME is authoritative
    # for this subject, but the rest of the script's gc calls resolve their own
    # scope and must not inherit it. Same move gc-helm.sh's `react` already
    # makes on the sling side, for the same reason. `${RIG_NAME:-}` cannot be
    # empty by the time we get here (both subject branches assign it, and
    # neither falls through), but an empty value would simply mean "no
    # override" — today's behavior — rather than tripping `set -u`.
    REACT_WHY="$(GC_RIG="${RIG_NAME:-}" "$PROACTIVE_TOOL" deliverable 2>/dev/null)" && REACT=1
    [ -n "$REACT_WHY" ] || REACT_WHY="no: gc-proactive.sh deliverable gave no answer"
fi

# ── Open the conversation ────────────────────────────────────────────
if [ -n "$REACT" ]; then
    # The reaction owns visit creation from here (its advance-and-drain step
    # runs the same gate-visit block). Nothing is filed by this script on this
    # path — a second visit would split the conversation.
    if "$HELM" react "$SUBJECT" --reason "operator-origin intake: $ARG"; then
        printf '%s: subject %s — first reaction slung (%s).\n' "$PROG" "$SUBJECT" "$REACT_WHY"
        printf '       The reaction writes a framing card and files the visit; it is not filed yet.\n'
        printf '       Want the conversation now instead? Re-run with --no-react.\n'
        exit 0
    fi
    # The sling failed outright. The subject exists, so falling through to the
    # direct path still delivers a conversation — better than exiting with a
    # bead nobody is coming to.
    note "$PROG: first reaction sling FAILED — falling back to filing the visit directly"
    REACT_WHY="no: the first-reaction sling failed"
fi

# Direct path: gc-helm.sh open owns the gate-visit block, the subject-exists
# gate, and the already-held gate. --reason/--body replace the board-pick
# wording with what this sitting is actually for, since the body is read at
# claim time as the converse session's only brief.
"$HELM" open "$SUBJECT" \
    --reason "operator-origin topic intake" \
    --body "The operator opened this topic directly and no framing card was written ($REACT_WHY). Rebuild whatever context exists on the subject, prep, and hold for the operator. The subject's body is the seed of the conversation, not a specification — ask before assuming scope." \
    || die "could not file the visit on $SUBJECT (the subject bead exists; retry with: $HELM open $SUBJECT)" 4
printf '%s: subject %s — visit filed (%s).\n' "$PROG" "$SUBJECT" "$REACT_WHY"
