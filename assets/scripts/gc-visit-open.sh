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
#   3  environment failure (cannot enumerate rigs, gc-helm.sh missing)
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
    RIGS=$(gc rig list --json 2>/dev/null | jq -c '[.rigs[]? | {name, path, prefix}]' 2>/dev/null)
    [ -n "$RIGS" ] || RIGS='[]'
    [ "$(printf '%s' "$RIGS" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ] \
        || die "could not enumerate rigs (gc rig list returned nothing)" 3
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

    # The topic string is the whole of what was said at the keystroke, so it
    # is BOTH the title and the durable seed in the body — the converse
    # session reads the body at claim time to rebuild what this is about, and
    # a title alone strands it if the operator typed a paragraph.
    SUBJ_BODY="$ARG

---
Operator-origin intake, filed by \`$PROG\` on $(date -u +%Y-%m-%dT%H:%M:%SZ).
The line above is the whole of what was said at the keystroke — the seed of a
conversation, not a specification. Ask before assuming scope."

    SUBJ_RAW=$(gc bd create -t "$SUBJ_TYPE" --title "$ARG" -d "$SUBJ_BODY" \
        --db "$RIG_PATH/.beads" --json 2>/dev/null)
    SUBJECT=$(printf '%s' "$SUBJ_RAW" | tr -d '\000-\010\013\014\016-\037' \
        | jq -r '.id // .[0].id // empty' 2>/dev/null)
    [ -n "$SUBJECT" ] && [ "$SUBJECT" != "null" ] \
        || die "could not create the subject bead in rig '$RIG' (bd create returned no id) — nothing filed" 4
    RIG_NAME="$RIG"
    note "$PROG: subject $SUBJECT created in rig $RIG_NAME ($SUBJ_TYPE)"
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
    REACT_WHY="$("$PROACTIVE_TOOL" deliverable 2>/dev/null)" && REACT=1
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
