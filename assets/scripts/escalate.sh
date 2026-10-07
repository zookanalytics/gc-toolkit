#!/usr/bin/env bash
# escalate.sh — one open visit per situation. Files a board-visible visit on
# the subject bead (the canonical gate-visit shape from formulas/mol-visit.toml)
# stamped with an escalation_key; a later call naming the same situation finds
# the open visit and files nothing. A visit is a conversation held for a human,
# so this is for what only a human can answer.
#   escalate.sh --subject <bead-id> --key <situation-key> --message <text>
#               [--pool <rig-qualified pool>]
# The counterpart verb retracts a visit whose situation resolved on its own,
# closing it as moot through visit-close.sh (the guarded moot/benign close) so a
# self-healing subject does not leave a moot visit on the board:
#   escalate.sh --retract --subject <bead-id> --key <situation-key> --message <reading>
# Callers: formulas/mol-refinery-patrol.toml, formulas/mol-dog-shutdown-dance.toml,
# the refinery's merge path (pr-open.sh, pr-facts.sh, merge.sh, gate-ensure.sh),
# a blocked polecat, and a patrol emergency that needs a human now.
# A changed situation gets a NEW key.
# A visit filed by the deacon also lands one entry in its incident ledger
# (gc-deacon-ledger.sh); see the marked block at the foot of this file.
#
# What this dedup does NOT span: a situation that RECURS. The window is one
# OPEN visit, and a converse sitting closes each visit, so a condition that
# fires again after the sitting files another. A recurring observation belongs
# in a durable bead instead — assets/scripts/patrol-finding.sh, which the
# deacon and witness patrols file their findings through; the first reaction
# on that bead decides whether it is work, a wait, or a question, and only the
# question becomes a visit.
# The route is proved against the live agent set before anything is created,
# and an already-open visit carrying an unroutable route is repointed rather
# than counted as a satisfied escalation. A rig-qualified --pool also selects
# the store the visit lands in, so route and store cannot disagree; without
# one, a rig-less caller has no store to reconcile an already-open visit's
# rig-qualified route against, and refuses rather than guess. On the board
# route the subject selects the store instead: when its id prefix names one,
# every read and write is pinned by path to that store, the city's included,
# wherever the caller sits. An
# ephemeral --subject (a patrol wisp, or a subject proven to name no bead) is
# redirected onto this store's standing triage subject, because the sitting
# that works the visit writes its outcome and takeaway to the subject.
# A CLOSED visit answers too: a situation a sitting closed `moot` or `benign`
# is not re-filed for GC_ESCALATE_VERDICT_WINDOW seconds (default 86400, 0
# disables), and each suppressed repeat is tallied on that visit.
# Exit: 0 filed, already open, repointed, inside the verdict window, or (--retract)
# closed as moot / no open visit to close · 1 unroutable/could not file/verify/close · 2 usage
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: escalate.sh --subject <bead-id> --key <situation-key> --message <text>
                   [--pool <rig-qualified pool>]
       escalate.sh --retract --subject <bead-id> --key <situation-key>
                   --message <one-line reading>

  --retract  close the OPEN visit for this subject+key as moot, instead of
             filing one, when the situation it raised resolved on its own.
             --message is the reading folded onto the subject and stamped as the
             visit's outcome reason. The caller owns the judgment that the
             premise is gone; no matching open visit is a no-op success. Needs a
             durable subject.
  --subject  the bead the escalation is about; the visit tracks it (required).
             One bead id, [A-Za-z0-9._-] only.
             On the board route the visit is filed in the store the subject's
             id prefix names, whatever GC_RIG says; only a subject whose store
             cannot be derived falls back to the GC_RIG store.
             A durable bead also narrows the dedup to that bead; an ephemeral
             one (a patrol wisp, or a subject proven to name no bead) cannot,
             so there the key alone is the identity, and the visit is filed on
             the standing triage subject (task_kind=triage-subject,
             triage.scope=ephemeral-subject-findings) instead — a wisp burns
             before a sitting can record anything to it, and a non-bead has
             nothing to record to. The subject rides the visit as
             escalation_raised_by
  --key      names the SITUATION, not the wording: one open visit per key,
             narrowed to the subject when the subject is durable.
             [A-Za-z0-9._-] only (required). To keep two situations apart
             under an ephemeral subject, encode what distinguishes them in
             the key (`wedged-<target>`)
  --message  what the visit needs from a human; first line becomes the
             visit title's headline (required)
  --pool     route to a specific pool instead of the board; default `human`,
             which parks the visit on the helm board for the operator to engage
             (the converse routed-pool is retired). A pool route must name a
             live agent identity that reads this rig's store; a rig-qualified
             --pool also selects the store, so route and store cannot disagree.

env:
  GC_ESCALATE_VERDICT_WINDOW  seconds a `moot` or `benign` verdict suppresses
             a re-file of the same situation (default 86400). A detector whose
             condition outlives the sitting re-raises it every cycle otherwise,
             and each repeat costs a sitting to reach the same answer. 0
             disables the window. To raise a situation that has genuinely
             changed, give it a new --key rather than widening this.
U
}

warn() { echo "escalate: $*" >&2; }

SUBJECT=""; KEY=""; MESSAGE=""; POOL_ARG=""; RETRACT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) SUBJECT="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --key)     KEY="${2:-}";     shift 2 || { usage; exit 2; } ;;
    --message) MESSAGE="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --pool)    POOL_ARG="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --retract) RETRACT=1; shift ;;
    -h|--help) usage; exit 2 ;;
    *) warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done
if [ -z "$SUBJECT" ] || [ -z "$KEY" ] || [ -z "$MESSAGE" ]; then
  warn "--subject, --key and --message are all required"; usage; exit 2
fi
# A '=' or metacharacter in the key breaks the exact-match dedup read.
case "$KEY" in
  *[!A-Za-z0-9._-]*) warn "--key must contain only [A-Za-z0-9._-] (got '$KEY')"; exit 2 ;;
esac
# The subject is one bead id. A durable subject is stamped as the visit's
# gc.continuation_group, which the dedup and retract listings match exactly,
# and is the far end of the tracks edge. A subject carrying a second word files
# a visit that no later call matches and that tracks no bead. A space in it
# usually comes from an unquoted expansion that did not word-split (zsh does
# not), which joins the id to the word beside it.
case "$SUBJECT" in
  *[!A-Za-z0-9._-]*)
    warn "--subject must be one bead id, [A-Za-z0-9._-] only (got '$SUBJECT'). An id joined to its neighbour usually comes from an unquoted \$VAR that did not word-split (zsh does not split it); read each field into its own variable, as 'while read -r SID SWHEN' does, and pass the id alone. Nothing was filed or closed."
    exit 2 ;;
esac

# GC_RIG naming a bound rig selects the store `gc bd` reads and writes,
# outranking BEADS_DIR and the working directory, and a pool offer is claimed
# only by an agent that reads that store. A rig-less caller naming a
# rig-qualified pool therefore adopts that rig: one flag names the route and the
# store, and they agree.
POOL_RIG="${POOL_ARG%%/*}"
if [ -z "${GC_RIG:-}" ] && [ -n "$POOL_ARG" ] && [ "$POOL_RIG" != "$POOL_ARG" ]; then
  export GC_RIG="$POOL_RIG"
  warn "GC_RIG unset; adopting rig '$POOL_RIG' from --pool so the visit lands in the store that pool reads"
fi

# >>> subject-class
# Whether --subject is a durable bead decides the dedup identity below and, on
# the board route, whether a store can be derived from the subject at all.
# Resolved once here, so every path agrees:
#   durable   — escalation-rig.sh (bead-store.sh) resolves exactly one rig: a
#               real bead id whose store is known.
#   ephemeral — a *-wisp-* id (its prefix resolves, but the wisp is burned and
#               re-poured every cycle, so it names no durable subject), OR a
#               subject bead-store proves is no placeable bead at all
#               (escalation-rig exit 1: no <prefix>-<id> shape, or a prefix the
#               readable rig set does not carry). A bare literal fallback with no
#               bead-id shape lands here. Both get key-alone dedup on the
#               standing triage subject below: a tracks edge to a non-bead fails,
#               and a sitting's outcome written to one has nowhere to land.
#   unproven  — escalation-rig exit 3, or any code but 0 and 1: no store could
#               be asked (the store helper could not run, the rig set was
#               unreadable, or a prefix two rigs carry). The subject may be a
#               real bead, so it is NOT bucketed as ephemeral; the board-route
#               block refuses it when GC_RIG is unset.
# The *-wisp-* glob overrides escalation-rig's answer because a wisp's own prefix
# (lx-, tk-) does resolve to a rig, so resolvability alone would miscall it
# durable. The rig a wisp resolves to is kept, so the board route files it in the
# store its prefix names, as it does a durable subject.
ESC_RIG_SH="${GC_ESCALATION_RIG_TOOL:-$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/escalation-rig.sh}"
subj_rig_why=""
# esc_rig [--db] <subject> leaves escalation-rig.sh's answer in ESC_OUT, its exit
# code in ESC_RC, and its stderr appended to subj_rig_why. bash runs no command
# whose redirection it cannot open and reports exit 1, which here would read as
# the proven no-bead answer. So the stderr file is made first, and without one
# only the reason is dropped, never the answer.
esc_rig() {
  local rig_err why
  ESC_OUT=""
  if [ ! -x "$ESC_RIG_SH" ]; then
    ESC_RC=3; subj_rig_why="cannot execute $ESC_RIG_SH"
    return 0
  fi
  rig_err=$(mktemp "${TMPDIR:-/tmp}/escalate-rig.XXXXXX" 2>/dev/null) || rig_err=/dev/null
  ESC_OUT=$("$ESC_RIG_SH" "$@" 2>"$rig_err"); ESC_RC=$?
  if [ "$rig_err" != /dev/null ]; then
    why=$(tr '\n' ' ' < "$rig_err" 2>/dev/null | cut -c1-300 | sed 's/  */ /g; s/^ *//; s/ *$//')
    rm -f "$rig_err" 2>/dev/null || true
    if [ -n "$why" ]; then subj_rig_why="${subj_rig_why:+$subj_rig_why; }$why"; fi
  fi
  return 0
}
esc_rig "$SUBJECT"; SUBJECT_RIG="$ESC_OUT"
case "$ESC_RC" in
  0) SUBJECT_CLASS=durable ;;
  1) SUBJECT_CLASS=ephemeral; SUBJECT_RIG="" ;;
  *) SUBJECT_CLASS=unproven; SUBJECT_RIG="" ;;
esac
case "$SUBJECT" in *-wisp-*) SUBJECT_CLASS=ephemeral ;; esac
SUBJECT_IS_EPHEMERAL=0; [ "$SUBJECT_CLASS" = ephemeral ] && SUBJECT_IS_EPHEMERAL=1
# <<< subject-class

# The default route is `human` (the retired converse pool's replacement; set in
# the gate-visit block below): the visit parks on the helm board, which is not a
# pool name that selects a store. The visit belongs in its subject's own store.
# bd writes the tracks edge into the store the visit is filed in, so a visit
# filed anywhere else keeps its link to the subject where nothing reading the
# subject's store can find it: severed from the subject, the silent mute this
# script exists to end.
#
# Neither GC_RIG nor the working directory reliably selects that store. `gc bd`
# honors GC_RIG only when it names a bound rig, and the city's own store is not
# one: GC_RIG set to the city's rig name draws a warning and is ignored, and the
# call answers from the caller's working directory. A caller in a rig checkout
# escalating about a city-store subject would file into its own rig.
#
# So on the board route the store is proven from the subject itself, through
# escalation-rig.sh (bead-store.sh): the one prefix->store derivation the
# destructive gates use, which refuses a prefix no rig carries, one two rigs
# carry, an unreadable rig set, and a rig with no path, each with its own reason
# on stderr. Every `gc bd` call below names that store by path through
# STORE_DB, because a --db path reaches every store, the city's included, ahead
# of GC_RIG and the working directory. GC_RIG is bound to the subject's rig for
# pool-route.sh, which judges an already-open visit's route against the rig
# whose store it was read from. A caller's GC_RIG naming another rig is
# overridden with a warning rather than refused, since the pin files the visit
# in the subject's store whatever GC_RIG says.
#
# A subject with no store to pin is handled by the class resolved above. An
# ephemeral one (a subject proven to name no bead, or a wisp whose prefix names
# no addressable store) is left to the triage redirect below, which files on the
# standing subject in the ambient store. Refusing it here would drop it whenever
# GC_RIG is unset, the silent mute the empty-identity escalation itself exists
# to report. A durable or unproven one may be a real bead, so it is filed
# unpinned under the caller's GC_RIG, since there is nothing to disprove that
# pin with, and is refused when GC_RIG is unset.
STORE_DB=""
if [ -z "$POOL_ARG" ] || [ "$POOL_ARG" = "human" ]; then
  # The rig names the store for pool-route.sh and the path selects it for
  # `gc bd`; without both, the store is unproven.
  subj_db=""
  if [ -n "$SUBJECT_RIG" ]; then
    esc_rig --db "$SUBJECT"
    [ "$ESC_RC" = 0 ] && subj_db="$ESC_OUT"
  fi
  if [ -n "$subj_db" ]; then
    STORE_DB="$subj_db"
    if [ -z "${GC_RIG:-}" ]; then
      warn "GC_RIG unset and the route defaults to the board ('human'); deriving rig '$SUBJECT_RIG' from subject '$SUBJECT' and filing in its store ($STORE_DB), not the caller's ambient store"
    elif [ "$GC_RIG" != "$SUBJECT_RIG" ]; then
      warn "GC_RIG='$GC_RIG' but subject '$SUBJECT' lives in rig '$SUBJECT_RIG'; on the board route the visit belongs in the subject's own store, so it is filed there ($STORE_DB), not in the '$GC_RIG' store"
    fi
    export GC_RIG="$SUBJECT_RIG"
  elif [ "$SUBJECT_CLASS" != ephemeral ] && [ -z "${GC_RIG:-}" ]; then
    warn "GC_RIG unset, the route defaults to the board ('human'), and the store for subject '$SUBJECT' could not be proven (${subj_rig_why:-no rig resolved}) — nothing filed. A visit created in the caller's ambient store would be severed from its subject. Re-run with GC_RIG set, or with a rig-qualified --pool."
    exit 1
  fi
fi

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }

# >>> retract-moot
# --retract closes the OPEN visit this script filed for a subject, as moot, when
# the situation it raised resolved on its own. It is the counterpart to filing:
# escalate.sh owns the visit's identity — escalation_key, narrowed to a durable
# subject by gc.continuation_group — so it is the one place that can find that
# visit again without a caller re-deriving the match and drifting from it. A
# caller reaches this only once it has decided the premise is gone; that judgment
# is the caller's, because whether a resolved subject implies a moot premise is
# per-subject-type (reconcile-rig-checkouts.sh retracts here because its subject
# tracks exactly one divergence and clears only on a clean sync, which does not
# generalize to every visit).
#
# Only an OPEN visit is retracted. A visit a human already claimed (in_progress)
# is theirs to close: the recheck-premise skill folds mootness in at their prep,
# and an unattended caller must not close a conversation out from under them.
# The close routes through visit-close.sh, the one guarded close — it folds the
# reading onto the subject's notes, stamps gc.outcome=moot and gc.outcome_reason
# (so the board reads a decision, not a dropped need), and closes the visit. No
# matching open visit is success: retract is idempotent, so a second pass, or a
# subject that never raised one, exits 0 having changed nothing. The lookup reads
# the subject's own store, pinned by STORE_DB in the board-route block above
# exactly as the filing path is; visit-close.sh addresses the visit and the
# subject by id, and an id resolves to the store that holds it.
if [ "$RETRACT" = 1 ]; then
  if [ "$SUBJECT_IS_EPHEMERAL" = 1 ]; then
    warn "--retract needs a durable subject; '$SUBJECT' is ephemeral (a patrol wisp, or a subject proven to name no bead), and its visits hang on the standing triage bucket keyed by --key alone, so there is no one subject-scoped visit to retract"
    exit 2
  fi
  VISIT_CLOSE="${GC_ESCALATE_VISIT_CLOSE_TOOL:-$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/visit-close.sh}"
  [ -x "$VISIT_CLOSE" ] || { warn "visit-close.sh not found or not executable ($VISIT_CLOSE); cannot retract the visit as moot"; exit 1; }
  # Read the open visits for this subject+key. An unreadable read is not proof no
  # visit exists: bd_json discards bd's stderr, so a failed list, a non-array
  # error value, or unparseable output all arrive as text that is not a JSON
  # array. Treating that as "nothing to do" (exit 0) would let a caller close the
  # subject while its visit stays open, recreating the phantom demand retract
  # exists to clear — so fail closed unless the read parses as an array. A
  # readable array with no match keeps the idempotent no-op.
  RETRACT_LISTING=$(bd_json list ${STORE_DB:+--db "$STORE_DB"} --status=open --metadata-field "escalation_key=$KEY" \
      --metadata-field "gc.continuation_group=$SUBJECT" --limit=20)
  if ! printf '%s' "$RETRACT_LISTING" | jq -e 'type == "array"' >/dev/null 2>&1; then
    warn "could not read open visits for $SUBJECT [$KEY]; NOT retracting — the visit's state is unknown and its subject must not be closed on an unreadable lookup"
    exit 1
  fi
  # The same open-visit identity the filing dedup matches on, re-checked field by
  # field because a listing that silently ignored a filter would match the wrong
  # bead.
  RETRACT_VISIT=$(printf '%s' "$RETRACT_LISTING" \
    | jq -r --arg k "$KEY" --arg s "$SUBJECT" \
        '.[] | select((.metadata.escalation_key // "") == $k and (.metadata["gc.continuation_group"] // "") == $s) | .id' \
    | head -n 1)
  if [ -z "$RETRACT_VISIT" ]; then
    echo "escalate: no open visit for $SUBJECT [$KEY] to retract — nothing to do"
    exit 0
  fi
  if "$VISIT_CLOSE" --visit "$RETRACT_VISIT" --subject "$SUBJECT" --outcome moot --reason "$MESSAGE"; then
    echo "escalate: retracted visit $RETRACT_VISIT on $SUBJECT [$KEY] as moot"
    exit 0
  fi
  warn "visit-close.sh did not close $RETRACT_VISIT; it stays open for a human"
  exit 1
fi
# <<< retract-moot

# The route gate is pool-route.sh, shared with every other copy of this
# block: one implementation decides what "addresses somebody" means, so a
# caller cannot drift from it by re-deriving the answer in its own copy.
SELF_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
POOL_ROUTE="$SELF_DIR/pool-route.sh"
[ -x "$POOL_ROUTE" ] || { warn "pool-route.sh not found beside this script ($POOL_ROUTE); no route can be proved, so nothing is filed"; exit 1; }
# ok | unknown | cross-rig | no-identity | unbound-store, for a route this
# script did not write.
route_verdict() { "$POOL_ROUTE" --verdict "$1"; }

# The headline is the first line of the message, capped so a long paragraph
# does not run into the visit title. When it overruns, cut back to the last
# word boundary near the cap (a bare byte cut severs a word, e.g. "…un" from
# "until") and mark the cut with an ellipsis so the title says it was shortened.
HEADLINE=$(printf '%s' "$MESSAGE" | head -n 1)
HEADLINE_MAX=100
if [ "${#HEADLINE}" -gt "$HEADLINE_MAX" ]; then
  keep=$(( HEADLINE_MAX - 1 ))          # leave room for the ellipsis
  cut=${HEADLINE:0:$keep}
  atword=${cut% *}                       # drop back to the last space
  if [ "$atword" != "$cut" ] && [ "${#atword}" -ge $(( keep / 2 )) ]; then
    cut=$atword                          # take the word boundary unless it loses most of the text
  fi
  HEADLINE="${cut}…"
fi

# >>> gate-visit
# Canonical gate-visit shape (formulas/mol-visit.toml); gate-visit.test.sh
# checks this copy's invariants. escalation_key rides its own flag beside it.
# The pool is resolved at each point that WRITES it, never up here: an
# escalation whose visit is already open and routable has already asked its
# human, and a default pool that call never needed must not turn it into a
# failure. The default is the board marker `human` (the converse routed-pool is
# retired); pool-route.sh passes `human` through unqualified.
POOL_NAME="${POOL_ARG:-human}"

# Idempotence: an open (or claimed) visit for this situation means the human is
# already asked. What "this situation" is depends on whether the subject
# carries identity from one call to the next.
#
# A durable subject narrows the situation to one bead — `polecat-blocked` on
# two work beads is two situations — and both filters ride the listing so a
# shared key dedups exactly even when more than the row window carry it;
# subject-side filtering of a truncated window would re-file a duplicate every
# pass. A patrol wisp is burned and re-poured every cycle, so its id cannot
# identify a situation from one call to the next and the conjunction can never
# match. The key alone is the identity there, and a key-only listing cannot be
# truncated past its own match. Either way the matched row is re-checked
# field by field, because a listing that silently ignored a filter would
# suppress everything.
#
# The matched row's own route rides the listing too: a visit nothing can claim
# has asked nobody, so counting it as satisfied is the same mute one pass
# later.
#
# An unreadable listing files anyway — a duplicate visit is a bounded nuisance,
# a silent mute is the failure this replaces.
# SUBJECT_IS_EPHEMERAL was resolved in the subject-class block above (a wisp, or
# a subject proven to name no placeable bead).
if [ "$SUBJECT_IS_EPHEMERAL" = 1 ]; then
  DEDUP_SCOPE="[$KEY]"
  OPEN_ROW=$(bd_json list ${STORE_DB:+--db "$STORE_DB"} --status=open,in_progress --metadata-field "escalation_key=$KEY" --limit=20 \
    | jq -r --arg k "$KEY" \
        'if type == "array" then (.[] | select((.metadata.escalation_key // "") == $k) | [.id, (.metadata["gc.routed_to"] // "")] | @tsv) else empty end' 2>/dev/null \
    | head -n 1)
else
  DEDUP_SCOPE="$SUBJECT [$KEY]"
  OPEN_ROW=$(bd_json list ${STORE_DB:+--db "$STORE_DB"} --status=open,in_progress --metadata-field "escalation_key=$KEY" \
      --metadata-field "gc.continuation_group=$SUBJECT" --limit=20 \
    | jq -r --arg k "$KEY" --arg s "$SUBJECT" \
        'if type == "array" then (.[] | select((.metadata.escalation_key // "") == $k and (.metadata["gc.continuation_group"] // "") == $s) | [.id, (.metadata["gc.routed_to"] // "")] | @tsv) else empty end' 2>/dev/null \
    | head -n 1)
fi
OPEN="${OPEN_ROW%%$'\t'*}"; OPEN_ROUTE=""
case "$OPEN_ROW" in *$'\t'*) OPEN_ROUTE="${OPEN_ROW#*$'\t'}" ;; esac
if [ -n "$OPEN" ]; then
  case "$(route_verdict "$OPEN_ROUTE")" in
    ok)
      echo "escalate: visit $OPEN already open for $DEDUP_SCOPE — not filing another"
      exit 0 ;;
    unknown)
      echo "escalate: visit $OPEN already open for $DEDUP_SCOPE — not filing another; its route '$OPEN_ROUTE' is UNVERIFIED"
      exit 0 ;;
    unbound-store)
      # The row was matched in whatever store the ambient environment picked,
      # and its route names a rig. Which store that pool reads is exactly what
      # GC_RIG would have said, so neither answer is available here: counting
      # the visit is the mute this script exists to end, and repointing would
      # rewrite a route that is very likely sound. The caller names its store.
      warn "visit $OPEN is open for $DEDUP_SCOPE and routes to '$OPEN_ROUTE', but GC_RIG is unset, so nothing here can tell whether that pool reads the store this row came from — a visit in a store it never lists has asked nobody."
      warn "  repair: re-run with --pool '$OPEN_ROUTE' (or GC_RIG=${OPEN_ROUTE%%/*}) so the store and the route agree."
      exit 1 ;;
  esac
  POOL=$("$POOL_ROUTE" "$POOL_NAME") || exit 1
  warn "visit $OPEN is open for $DEDUP_SCOPE but routes to '$OPEN_ROUTE', which no live pool claims — repointing it at '$POOL'."
  gc bd update "$OPEN" ${STORE_DB:+--db "$STORE_DB"} --set-metadata "gc.routed_to=$POOL" >/dev/null 2>&1
  OPEN_GOT=$(bd_json show "$OPEN" ${STORE_DB:+--db "$STORE_DB"} | jq -r '.[0].metadata["gc.routed_to"] // ""' 2>/dev/null)
  if [ "$OPEN_GOT" != "$POOL" ]; then
    warn "the repoint did not land on $OPEN (route reads '$OPEN_GOT'); repair: gc bd update $OPEN${STORE_DB:+ --db $STORE_DB} --set-metadata gc.routed_to=$POOL"
    exit 1
  fi
  echo "escalate: visit $OPEN already open for $DEDUP_SCOPE — repointed to $POOL, not filing another"
  exit 0
fi

# A closed visit carries a VERDICT, and two of them say a human was not needed:
# `moot` (the premise no longer holds) and `benign` (it holds but needs nobody).
# The converse role stamps them on gc.outcome before it closes
# (agents/converse/prompt.template.md). Nothing read them back, and the dedup
# above only sees OPEN visits, so a detector whose condition outlives the
# sitting re-filed the identical situation on its next cycle and spent another
# one. This window is where that verdict is honored.
#
# The newest closed visit for the situation decides, across every outcome. Only
# moot and benign suppress; any other outcome means the sitting acted, so the
# next occurrence stands on different ground and an older moot behind a newer
# ruling cannot mute it. A situation that has CHANGED takes a new key by the
# rule at the top of this file, so the window cannot trap a new signal behind an
# old answer.
#
# The newest is chosen by timestamp across the whole closed set, not a page of
# it, because a truncated listing could return an older verdict as though it
# were the latest.
#
# Suppression is COUNTED, never silent — this script exists to end silent
# mutes. The tally rides the visit that earned the verdict, so a recurrence
# costs one in-place update instead of a bead per cycle, and a situation that
# recurs relentlessly reports how many sittings the window saved.
VERDICT_WINDOW="${GC_ESCALATE_VERDICT_WINDOW:-86400}"
case "$VERDICT_WINDOW" in ''|*[!0-9]*) VERDICT_WINDOW=86400 ;; esac
if [ "$VERDICT_WINDOW" -gt 0 ]; then
  if [ "$SUBJECT_IS_EPHEMERAL" = 1 ]; then
    VERDICT_SUBJECT=""
    VERDICT_RAW=$(bd_json list ${STORE_DB:+--db "$STORE_DB"} --status=closed --metadata-field "escalation_key=$KEY" --limit=0)
  else
    VERDICT_SUBJECT="$SUBJECT"
    VERDICT_RAW=$(bd_json list ${STORE_DB:+--db "$STORE_DB"} --status=closed --metadata-field "escalation_key=$KEY" \
      --metadata-field "gc.continuation_group=$SUBJECT" --limit=0)
  fi
  # Re-checked field by field for the same reason the open listing is: a
  # listing that silently ignored a filter would suppress everything.
  VERDICT_ROW=$(printf '%s' "$VERDICT_RAW" | jq -r --arg k "$KEY" --arg s "$VERDICT_SUBJECT" '
    if type != "array" then empty else
      [ .[]
        | select((.metadata.escalation_key // "") == $k)
        | select($s == "" or (.metadata["gc.continuation_group"] // "") == $s)
        | { id: .id,
            outcome: (.metadata["gc.outcome"] // ""),
            n: (((.metadata["escalation.recurrences"] // "0") | tonumber?) // 0),
            at: (((.closed_at // "") | fromdateiso8601?) // 0) }
        | select(.at > 0) ]
      | sort_by(.at)
      | last
      | if . == null then empty
        elif (.outcome == "moot" or .outcome == "benign")
        then [ .id, .outcome, ((now - .at) | floor | tostring), (.n | tostring) ] | @tsv
        else empty end
    end' 2>/dev/null)
  if [ -n "$VERDICT_ROW" ]; then
    V_ID="${VERDICT_ROW%%	*}";   V_REST="${VERDICT_ROW#*	}"
    V_OUTCOME="${V_REST%%	*}";  V_REST="${V_REST#*	}"
    V_AGE="${V_REST%%	*}";      V_COUNT="${V_REST#*	}"
    case "$V_AGE$V_COUNT" in *[!0-9]*) V_AGE=""; V_COUNT="" ;; esac
    if [ -n "$V_AGE" ] && [ "$V_AGE" -lt "$VERDICT_WINDOW" ]; then
      V_COUNT=$((V_COUNT + 1))
      gc bd update "$V_ID" ${STORE_DB:+--db "$STORE_DB"} \
        --set-metadata "escalation.recurrences=$V_COUNT" \
        --set-metadata "escalation.recurrence_last=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 \
        || warn "could not record the recurrence on $V_ID; the suppression below still stands"
      echo "escalate: $DEDUP_SCOPE was answered '$V_OUTCOME' ${V_AGE}s ago on visit $V_ID — not filing another inside ${VERDICT_WINDOW}s (recurrence $V_COUNT). A situation that has CHANGED takes a new --key; GC_ESCALATE_VERDICT_WINDOW=0 disables the window."
      exit 0
    fi
  fi
fi

POOL=$("$POOL_ROUTE" "$POOL_NAME") || exit 1

# The subject has to outlive the visit. A converse sitting records what it
# settled by appending to the subject and stamps its closing takeaway there
# (converse-signoff.sh, step 7 of agents/converse/prompt.template.md). A wisp
# is burned at the end of the iteration that poured it, so on a wisp subject
# both writes address a bead that no longer exists, and the sitting's own guard
# ("NO TAKEAWAY ON $SUBJECT") cannot be satisfied at all.
#
# So an ephemeral subject is redirected rather than filed on: the visit hangs
# on this store's standing triage subject, and the wisp survives as
# provenance. That subject is durable by construction: liveness-sweep.sh's
# classify block reads a task_kind=triage-subject bead as held-by-design, and
# its recurrence arm skips a scope carrying no schema token
# (p<=N · label:X · kind:X · unrouted), so the bucket files no visits of its
# own. Redirecting rather than refusing follows the rule the rest of this
# script files under: a visit whose disposition is lost has still asked a
# human, and refusing to file asks nobody.
#
# Only the FILING side moves. The dedup above still identifies a wisp-raised
# situation by its key alone, which is what matches the visits already open
# under a burned wisp's group; narrowing those to the bucket would match none
# of them and re-file every one.
#
# A shared subject makes the group a bucket rather than a topic, so what keeps
# two findings in it apart is the escalation_key stamped on each visit below.
# The converse fold check (converse-fold.sh) reads exactly that: it resolves a
# visit's topic as the key under a `key:` prefix, else the subject, and folds a
# sitting only into a sibling of the same topic. On a redirected visit the
# subject is the shared bucket, so the key is the only discriminator it has;
# dropping it, or scoping it to the bucket, would make every finding here look
# like one situation and fold all but the lowest id away unread.
TRIAGE_SCOPE="ephemeral-subject-findings"
RAISED_BY=""
if [ "$SUBJECT_IS_EPHEMERAL" = 1 ]; then
  # The matched row is re-checked field by field, as in the dedup listing
  # above. A filter the listing ignored would hand back an unrelated open
  # bead, and the visit would take its title, its group stamp and its tracks
  # edge from a bead nobody escalated about.
  STANDING=$(bd_json list ${STORE_DB:+--db "$STORE_DB"} --status=open,in_progress \
      --metadata-field "task_kind=triage-subject" \
      --metadata-field "triage.scope=$TRIAGE_SCOPE" --limit=20 \
    | jq -r --arg s "$TRIAGE_SCOPE" 'if type == "array" then
        ([.[] | select((.metadata.task_kind // "") == "triage-subject"
                   and (.metadata["triage.scope"] // "") == $s)][0].id // "")
      else "" end' 2>/dev/null)
  if [ -z "$STANDING" ]; then
    # An unreadable listing arrives here too and mints a second bucket. That
    # is the trade the dedup listing already makes: a duplicate bead is a
    # bounded nuisance, a disposition written to a burned wisp is gone.
    STANDING=$(gc bd create -t task \
      --title "triage: escalations raised from an ephemeral subject (this rig)" \
      -d "Standing subject for escalations whose caller named an ephemeral subject — a patrol wisp, which is burned and re-poured every cycle. One open visit per situation key hangs here; each visit names the wisp that raised it in escalation_raised_by, and a sitting's outcome and takeaway land on this bead." \
      ${STORE_DB:+--db "$STORE_DB"} --json 2>/dev/null | scrub | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null || true)
    if [ -n "$STANDING" ] && [ "$STANDING" != "null" ]; then
      gc bd update "$STANDING" ${STORE_DB:+--db "$STORE_DB"} --set-metadata "task_kind=triage-subject" \
        --set-metadata "triage.scope=$TRIAGE_SCOPE" >/dev/null
      # Both stamps are what the lookup above filters on, so a stamp that did
      # not land costs a fresh bucket on every later ephemeral escalation.
      STANDING_ROW=$(bd_json show "$STANDING" ${STORE_DB:+--db "$STORE_DB"})
      STANDING_KIND=$(printf '%s' "$STANDING_ROW" | jq -r '.[0].metadata.task_kind // ""' 2>/dev/null)
      STANDING_SCOPE=$(printf '%s' "$STANDING_ROW" | jq -r '.[0].metadata["triage.scope"] // ""' 2>/dev/null)
      if [ "$STANDING_KIND" != "triage-subject" ] || [ "$STANDING_SCOPE" != "$TRIAGE_SCOPE" ]; then
        warn "standing subject $STANDING was created but its markers did not read back (task_kind='$STANDING_KIND' triage.scope='$STANDING_SCOPE'); the next ephemeral escalation will mint another. repair: gc bd update $STANDING${STORE_DB:+ --db $STORE_DB} --set-metadata task_kind=triage-subject --set-metadata triage.scope=$TRIAGE_SCOPE"
      fi
    else
      STANDING=""
    fi
  fi
  if [ -n "$STANDING" ]; then
    RAISED_BY="$SUBJECT"
    SUBJECT="$STANDING"
    warn "subject '$RAISED_BY' is ephemeral and cannot receive a sitting's outcome; filing on standing subject $SUBJECT instead."
  else
    warn "subject '$SUBJECT' is ephemeral and no standing subject could be read or created; filing on the wisp itself — a sitting's outcome and takeaway will be lost when it burns."
  fi
fi

BODY="$MESSAGE"
[ -n "$RAISED_BY" ] && BODY="$MESSAGE

Raised from $RAISED_BY, which is ephemeral. The visit hangs on this standing subject so the sitting's outcome and takeaway have a bead that outlives the cycle."

# The identity metadata is stamped in the create itself. The dedup listing
# above finds a prior visit by escalation_key — and, for a durable subject, by
# gc.continuation_group — so a visit that exists without those stamps is
# invisible to it, and the next call for the same situation files a duplicate.
# A create followed by a separate stamp is two writes; an interruption between
# them leaves an unstamped visit that nothing can dedup against. One write
# cannot: the bead and its dedup keys land together or not at all.
# escalation_raised_by (provenance for a redirected visit, whose subject is then
# the bucket) rides the same object; empty when the subject was not redirected.
VISIT_META=$(jq -nc --arg pool "$POOL" --arg subject "$SUBJECT" --arg key "$KEY" --arg raised "$RAISED_BY" \
  '{"gc.routed_to": $pool, "gc.continuation_group": $subject, "task_kind": "visit", "escalation_key": $key}
   + (if $raised == "" then {} else {"escalation_raised_by": $raised} end)')
VISIT_JSON=$(gc bd create -t task --title "visit: $SUBJECT — $HEADLINE" -d "$BODY" --metadata "$VISIT_META" ${STORE_DB:+--db "$STORE_DB"} --json 2>/dev/null || true)
VISIT=$(printf '%s' "$VISIT_JSON" | scrub | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null || true)
[ -n "$VISIT" ] && [ "$VISIT" != "null" ] \
  || { create_err=$(printf '%s' "$VISIT_JSON" | scrub | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null || true)
       echo "escalate: bd create returned no id${create_err:+: $create_err} — nothing filed; re-run rather than improvising another create form" >&2; exit 1; }
gc bd dep add "$VISIT" "$SUBJECT" --type=tracks ${STORE_DB:+--db "$STORE_DB"}
# tracks, NOT parent-child: a parent-child edge transmits the subject's
# blocked state to the visit, unclaimable exactly where conversation is owed.
# Read the group stamp back and repair it from the subject if it landed
# empty: it can land present-but-empty even when the create's other stamps
# land, and an empty group disables converse's group-scoped re-claim fence —
# and here also this script's own dedup listing for a durable subject. Repair
# and warn, never exit — this block files the one visit for its scope, and on
# a persistent miss the tracks edge still carries the subject for guards that
# read the union.
GROUP_GOT=$(gc bd show "$VISIT" --json ${STORE_DB:+--db "$STORE_DB"} | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
if [ "$GROUP_GOT" != "$SUBJECT" ]; then
  echo "gate-visit: warning: gc.continuation_group on $VISIT read back as '$GROUP_GOT', expected '$SUBJECT' — repairing" >&2
  gc bd update "$VISIT" --set-metadata "gc.continuation_group=$SUBJECT" ${STORE_DB:+--db "$STORE_DB"} || true
  GROUP_GOT=$(gc bd show "$VISIT" --json ${STORE_DB:+--db "$STORE_DB"} | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
  if [ "$GROUP_GOT" = "$SUBJECT" ]; then
    echo "gate-visit: the repair landed on $VISIT" >&2
  else
    echo "gate-visit: warning: the repair did not land on $VISIT — the tracks edge still carries the subject, and the live-visit guards read the union" >&2
  fi
fi
# <<< gate-visit

# The route and key are what make the visit claimable and the dedup real, so
# both are read back; a visit that did not stamp is repaired by hand. (The
# group stamp is read back and repaired inside the gate-visit block above.)
ROW=$(bd_json show "$VISIT" ${STORE_DB:+--db "$STORE_DB"})
GOT_ROUTE=$(printf '%s' "$ROW" | jq -r '.[0].metadata["gc.routed_to"] // ""' 2>/dev/null)
GOT_KEY=$(printf '%s' "$ROW" | jq -r '.[0].metadata.escalation_key // ""' 2>/dev/null)
if [ "$GOT_ROUTE" != "$POOL" ] || [ "$GOT_KEY" != "$KEY" ]; then
  warn "visit $VISIT was created but its stamps did not read back (route='$GOT_ROUTE' key='$GOT_KEY'); repair: gc bd update $VISIT${STORE_DB:+ --db $STORE_DB} --set-metadata gc.routed_to=$POOL --set-metadata escalation_key=$KEY"
  exit 1
fi

# The deacon's shift record. Filing a visit is a non-routine action, and this
# is the only place that holds the visit id it points at, so the entry is
# written here rather than asked for at each call site. Gated to the deacon
# because the ledger records what the deacon did: every other caller escalates
# about its own work. A dedup or repoint exit above writes nothing — the
# situation reached the ledger on the pass that filed it, and a repeat is the
# noise a signal-only ledger exists to leave out. A ledger failure is reported
# and never changes this exit: the visit is filed either way.
# >>> deacon-ledger-append
LEDGER_ROLE="${GC_AGENT:-}"; LEDGER_ROLE="${LEDGER_ROLE##*/}"; LEDGER_ROLE="${LEDGER_ROLE##*.}"
if [ "$LEDGER_ROLE" = deacon ]; then
  LEDGER_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/gc-deacon-ledger.sh"
  if [ -x "$LEDGER_SH" ]; then
    "$LEDGER_SH" append escalation "$KEY: $HEADLINE" "bead:$VISIT" >/dev/null \
      || warn "visit $VISIT is filed, but its ledger entry was not written"
  else
    warn "no executable gc-deacon-ledger.sh beside this script; visit $VISIT is filed but absent from the ledger"
  fi
fi
# <<< deacon-ledger-append

echo "escalate: filed visit $VISIT on $SUBJECT [$KEY] -> $POOL"
exit 0
