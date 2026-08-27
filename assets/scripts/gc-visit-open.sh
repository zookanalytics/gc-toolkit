#!/bin/sh
# gc-visit-open.sh — operator-origin visit intake: turn "I need an agent on
# topic X" into a routed, durable conversation in one command (tk-4ojka).
# Usage:
#   gc-visit-open "<topic>"                 open a conversation on a NEW topic
#   gc-visit-open <bead-id>                 open one on an EXISTING bead
#   flags: --rig <rig> · --no-react · --type <t> · --topic (id-shaped strings
#   are topics)
# Owns everything upstream of the visit (rig, subject bead, path choice);
# visit filing itself lives ONCE in gc-helm.sh open's gate-visit block, which
# this calls (gate-visit.test.sh guards that single copy). Two paths:
# PREFERRED slings mol-first-reaction (framing card, reaction files the
# visit); FALLBACK files the visit directly — taken on --no-react or whenever
# `gc-proactive.sh deliverable` answers no (divert-on-no is the contract —
# a sling into a downed pool fails invisibly; today's tool always says yes).
# Exit: 0 conversation queued · 2 usage · 3 environment (rig enumeration
# matches gc-helm.sh's per-cause taxonomy, tk-lzdty) · 4 runtime failure.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

PROG="gc-visit-open"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
HELM="${GC_HELM_TOOL:-$SCRIPT_DIR/gc-helm.sh}"
PROACTIVE_TOOL="${GC_PROACTIVE_TOOL:-$SCRIPT_DIR/../../tools/gc-proactive.sh}"

# The default rig — deliberately NOT inferred from cwd: a wrong-but-FIXED
# default is discoverable, a wrong-and-VARYING one is not.
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
# `bd create` refuses a title over 500 BYTES, and the popup invites a
# paragraph (tk-wp50s). The topic lives verbatim in the BODY; the title is a
# derived label, capped well under 500 in bytes (what ${#var} measures here).
TITLE_MAX=200

# derive_title <text> — one-line board label: whitespace collapsed, over-long
# topics cut at a WORD boundary (an offset cut can slice a multi-byte char).
derive_title() {
    _dt=$(printf '%s' "$1" | tr '\n\r\t' '   ' | tr -s ' ')
    _dt="${_dt# }"; _dt="${_dt% }"
    [ "${#_dt}" -le "$TITLE_MAX" ] && { printf '%s' "$_dt"; return 0; }

    # Drop trailing words until it fits, holding a byte back for the ellipsis.
    while [ "${#_dt}" -gt "$((TITLE_MAX - 1))" ]; do
        _dt_prev="$_dt"
        _dt="${_dt% *}"
        [ "$_dt" = "$_dt_prev" ] && break     # one unbroken token — no boundary to use
    done
    # One unbroken token (URL, hash, spaceless script): cut at the byte, then
    # repair a trailing half-character.
    if [ "${#_dt}" -gt "$((TITLE_MAX - 1))" ]; then
        while [ "${#_dt}" -gt "$((TITLE_MAX - 1))" ]; do _dt="${_dt%?}"; done
        # Keyed on OUTPUT: iconv emits the valid prefix even as it "fails".
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

# ── Bead id or topic? Disambiguated by RIG PREFIX, not shape alone ────
# prefix matches no rig → topic; matches and resolves → subject; matches but
# does not resolve → gc-helm.sh's subject-exists gate exits 4 (a typo must
# not become a topic bead titled "tk-abc12"). --topic forces the collision.
looks_like_bead_id=""
case "$ARG" in
    *[!a-zA-Z0-9_-]*|-*) : ;;                       # whitespace/punctuation → a topic
    *-*) [ -n "$FORCE_TOPIC" ] || looks_like_bead_id=1 ;;
esac

RIGS=""
enumerate_rigs() {
    [ -n "$RIGS" ] && return 0
    # >>> rig-enumeration-taxonomy
    # Mirrors gc-helm.sh's enumerate_rigs (per-cause sentences, tk-lzdty); no
    # timeout arm because this script does not bound the call.
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
    # An existing bead's own rig is authoritative; --rig/--type are refused
    # rather than silently ignored.
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

    # A question is a decision, everything else a task; --type overrides.
    if [ -z "$SUBJ_TYPE" ]; then
        case "$ARG" in
            *\?) SUBJ_TYPE="decision" ;;
            *)   SUBJ_TYPE="task" ;;
        esac
    fi

    # The topic lands verbatim in the BODY (read at claim time); the title is
    # only a derived label.
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
    SUBJ_JSON=$(printf '%s' "$SUBJ_RAW" | scrub)
    SUBJECT=$(printf '%s' "$SUBJ_JSON" | jq -r '.id // .[0].id // empty' 2>/dev/null)
    if [ -z "$SUBJECT" ] || [ "$SUBJECT" = "null" ]; then
        # A refused create STATES its reason in .error — surface it (tk-wp50s).
        SUBJ_ERR=$(printf '%s' "$SUBJ_JSON" | jq -r '.error // .[0].error // empty' 2>/dev/null)
        [ -n "$SUBJ_ERR" ] || SUBJ_ERR="bd create returned no id and no error (exit $SUBJ_RC)"
        die "could not create the subject bead in rig '$RIG': $SUBJ_ERR — nothing filed" 4
    fi
    RIG_NAME="$RIG"
    SUBJ_DB="$RIG_PATH/.beads"
    note "$PROG: subject $SUBJECT created in rig $RIG_NAME ($SUBJ_TYPE)"
fi

# ── Record the origin as a KEY, not only as prose ────────────────────
# gc.origin=operator is the machine-readable fact ("operator commissioned
# this") a sweep can select on where the body sentence cannot be (prose
# drifts and gets quoted, tk-2cyxo). BOTH intake paths stamp it; gc-helm.sh
# open deliberately does not (a board pick is a glance, not a commission).
# Only when absent, and never fatal: the deliverable is the conversation.
ORIGIN_NOW=$(gc bd show "$SUBJECT" --json 2>/dev/null \
    | scrub \
    | jq -r 'if type == "array" then ((.[0].metadata // {})["gc.origin"] // "") else "" end' 2>/dev/null)
if [ -z "$ORIGIN_NOW" ]; then
    # shellcheck disable=SC2086  # ${SUBJ_DB:+--db "$SUBJ_DB"} expands to 0 or 2 space-free fields
    gc bd update "$SUBJECT" ${SUBJ_DB:+--db "$SUBJ_DB"} --set-metadata "gc.origin=operator" >/dev/null 2>&1 \
        || note "$PROG: could not stamp gc.origin=operator on $SUBJECT — the conversation is unaffected; stamp it by hand"
fi

# ── Path selection: can a slung first reaction actually be picked up? ─
# Delegated to gc-proactive.sh deliverable so this caller cannot drift from
# the clamps (the tool + agents/proactive/agent.toml).
REACT=""; REACT_WHY=""
if [ -n "$NO_REACT" ]; then
    REACT_WHY="--no-react: filing the visit directly"
elif [ ! -x "$PROACTIVE_TOOL" ]; then
    REACT_WHY="no: cannot find gc-proactive.sh (looked at $PROACTIVE_TOOL)"
else
    # Ask under the SUBJECT's rig (the pool and its clamps are rig-scoped;
    # helm-svc has no GC_RIG of its own — tk-hscs0). Set for this ONE command,
    # not exported: later gc calls resolve their own scope.
    REACT_WHY="$(GC_RIG="${RIG_NAME:-}" "$PROACTIVE_TOOL" deliverable 2>/dev/null)" && REACT=1
    [ -n "$REACT_WHY" ] || REACT_WHY="no: gc-proactive.sh deliverable gave no answer"
fi

# ── Open the conversation ────────────────────────────────────────────
if [ -n "$REACT" ]; then
    # The reaction owns visit creation from here; a second visit would split
    # the conversation.
    if "$HELM" react "$SUBJECT" --reason "operator-origin intake: $ARG"; then
        printf '%s: subject %s — first reaction slung (%s).\n' "$PROG" "$SUBJECT" "$REACT_WHY"
        printf '       The reaction writes a framing card and files the visit; it is not filed yet.\n'
        printf '       Want the conversation now instead? Re-run with --no-react.\n'
        exit 0
    fi
    # Sling failed outright: fall through — a conversation beats a bead
    # nobody is coming to.
    note "$PROG: first reaction sling FAILED — falling back to filing the visit directly"
    REACT_WHY="no: the first-reaction sling failed"
fi

# Direct path: gc-helm.sh open owns the gates; --reason/--body carry what
# this sitting is actually for (read at claim time).
"$HELM" open "$SUBJECT" \
    --reason "operator-origin topic intake" \
    --body "The operator opened this topic directly and no framing card was written ($REACT_WHY). Rebuild whatever context exists on the subject, prep, and hold for the operator. The subject's body is the seed of the conversation, not a specification — ask before assuming scope." \
    || die "could not file the visit on $SUBJECT (the subject bead exists; retry with: $HELM open $SUBJECT)" 4
printf '%s: subject %s — visit filed (%s).\n' "$PROG" "$SUBJECT" "$REACT_WHY"
