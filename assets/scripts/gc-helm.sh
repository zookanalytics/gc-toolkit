#!/bin/sh
# gc-helm.sh — the helm verbs: the WRITE verbs, and the read-only resolve.
# Job: write the operator-facing state the helm board renders. The operator's
# steering moves are gctk's (gctk bead park, gctk bead place, gctk reaction
# accept), and a priority move is queue-priority.sh's. The board itself is
# helm-svc's web page
# (services/helm), and `helm-svc board --json` prints its rows; this script
# renders nothing.
# Verbs (full grammar and per-verb notes in usage(), `gc-helm --help`): the
# write verbs open, engage, attach, dismiss and handback, the read-only resolve
# and conversations, and po
# and mechanik, which attach to the seats the operator sits with: a rig's po,
# and the city's mechanik. engage, which a bare gc-helm on a terminal runs, and
# attach hand a terminal to the conversation form (helm_form), whose People
# page opens a seat. open and engage take a
# <subject> (a bead id, a PR number or URL, or a superseded id) and resolve it to
# the live bead that owns the work by metadata and the graph, never a title; an
# unresolvable or ambiguous reference is refused and nothing is filed.
# Callers: operator-intake.sh (resolve, open), helm-svc's POST routes
# via GC_HELM_OPEN_TOOL (open, engage — open's stderr/stdout
# sentences are parsed by services/helm/internal/server, guarded by
# open_parity_test.go), converse (handback), and helm-svc's conversation form
# on the operator's terminal (conversations, open, engage, po and mechanik).
# Exit codes: 0 ok, 2 usage, 3 environment (jq/gc missing, rigs
# unenumerable — each failure names its own operator move),
# 4 verb runtime failure (bead not found / unverifiable / filing failed).

set -eu

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

PROG="gc-helm"
TAKEAWAY_MAX=140                            # hard cap on a takeaway headline, in CODEPOINTS
FIXTURE="${GC_HELM_FIXTURE:-}"              # test hook: <dir>/rigs.json replaces `gc rig list`

usage() {
    cat >&2 <<'EOF'
Usage:
  gc-helm  on a terminal, engage's form, the way in, whose tabs start a conversation, return to one, or open mechanik or a rig's Product Owner from the People page; without a terminal, this usage and exit 2
  gc-helm po --rig <name>  attach to the rig's Product Owner: a live sitting as it stands, and any other through the controller's start, which opens a new sitting with its prompt
  gc-helm mechanik  attach to mechanik, the city's one, waiting while the controller starts it
  gc-helm open  <bead-id> [--reason "..."] [--body "..."] [--allow-duplicate] [--if-subject <id>] [--conversation <id>] [--from <bead-id>] [--json]  file a conversation about the bead in the operator's queue, for the operator to engage; a second concern joins the bead's conversation already in the queue unless --allow-duplicate files a fresh one, which lands instead on a conversation in the queue whose whole ask is that concern; a conversation about an open PR, or a bead of one, holds the PR's merge until it closes; --if-subject files only while the reference still names that subject, and a reference that names another now, through a successor, a PR's anchor or a gate's waiter, files nothing (exit 4); --conversation completes the conversation an earlier open filed for the concern, by its id, wherever it stands, adding the reply onto the gate that did not land, and the hold on an open PR's merge only while the conversation waits in the queue, since a sitting that has taken it keeps or lifts that hold; one no longer open on the bead or holding another ask files nothing (exit 4); a gate several open beads wait on files the conversation about the one whose wait on it is oldest, with a note naming the others; --from names the bead a gate was reached from, and such a gate files the conversation about that bead while it is one of them, while a gate that no longer holds that bead files nothing (exit 4); --json prints {subject,conversation,filed}, and names the conversation on every exit once it is filed
  gc-helm open  --new-subject --rig <name> [<question> | --reason "<question>"] [--json]  file a FRESH subject in the named rig for a topic that has no bead yet, the question unchanged in its description and its title derived from the question's opening, then its conversation in the queue; --json answers the subject, filed:false, the moment it is filed, and open's last answer is the one that counts, so a subject filed whose conversation is not is named for a re-run onto it
  gc-helm engage [<subject>] [--subject <id>] [--from <bead-id>] [--new-subject [--rig <name>]] [--model <variant>] [--skill <name>] [--reason "..." | --template <key>] [--no-input] [--no-attach]  hold a conversation about the bead in a converse sitting and attach: attach to its live sitting, or take its conversation from the queue, or file one, then spawn a sitting named for it. Pointed at a human gate it takes the one bead still waiting on the gate, or of several waiting the --from bead when it is one of them and otherwise the one whose wait on it is oldest, and the conversation replies to the gate. On a terminal, with no --reason, --template or --skill, it opens the conversation form instead: subject (a bead or a PR, or a rig's name or prefix typed there for a new topic in that rig), question, model and whether to attach on one screen, filled in from the command line, where --rig fills in the subject and --no-attach turns attaching off; --no-input keeps the flag-driven one-shot path. --skill seeds the sitting with any skill it carries as its lens on the subject (--skill review-arch is a conversation with the Architect). --new-subject files a FRESH subject bead in the --rig rig (the positional text, or --reason, is the question; its title is derived from the question's opening) and engages it in one gesture
  gc-helm attach [<conversation>]  return to a conversation: with an id, engage's attach (a live sitting once it has started, or a new sitting on a conversation whose sitting ended or that waits in the queue); with none, on a terminal, the conversation form's list of conversations to return to, by topic and readiness
  gc-helm conversations [<ref> [--from <bead-id>]] [--json]  list where each open conversation stands: its sitting's readiness (queued, starting, preparing, ready, ended) and whether a terminal is attached; with a subject reference, the subject as engage resolves it, --from as engage takes it, the rig a conversation about it is held in, whether a sitting can start there, its open conversations and what holds it; with none, --json also gives the rigs a new topic can be filed in, and the seats the form's People page lists, mechanik and each rig's Product Owner, each with its session as 'gc session list' holds it. Read-only
  gc-helm dismiss  [<bead-id>] [--reason "..."] [--operator] [--json]  the operator is done with this sitting: close the conversation a live sitting holds on the bead, answering no gate, and stop the session that held it; a conversation id closes that conversation (subject inferred from the current sitting when omitted); --operator stops every session as the operator, from outside it; --json prints {subject,matched,closed,ok}
  gc-helm handback <conversation-id> < hand-back  record the hand-back a converse sitting is posting, read from stdin, on its conversation, replacing the one before; engage prints the latest in the operator's tab once the sitting has ended
  gc-helm resolve <bead-id|pr-number|pr-url>  print the LIVE bead a reference resolves to (a PR ref to its anchor, a superseded id to its successor); a live id or an unrecognized reference prints unchanged, an unresolvable or ambiguous PR is refused. Read-only, files nothing — operator-intake.sh uses it to route a PR reference before it becomes a topic

The board is `helm-svc board` (services/helm). This script renders no
board. open and engage take the subject as a bead id, a PR number
or URL, or a superseded bead id, and resolve it to the LIVE bead that owns the
work by metadata and the graph — a PR number/URL to its anchor, a
closed+superseded id along its supersedes edge to its successor — never an id
scraped from a title. A live bead recording a PR in pr_number/pr_url stands
for the anchor it names in anchor_bead, if any. An unresolvable or ambiguous
reference is refused, naming what it could not resolve; nothing is filed.
A conversation is an ordinary task that tracks the one bead it is about and
replies to each human gate it answers (bd's replies-to edge). It is assigned
to `human` while it waits in the operator's queue, and to its sitting's alias,
which names its own id, while a sitting holds it (conversation.sh holds the
one definition of that shape). open files one in the queue, in the bead's own
store; its --reason is the title and --body the ask the sitting reads when it
claims the conversation. A conversation about an open PR's anchor, or about a
bead whose anchor_bead names that anchor, holds the PR's merge until it closes,
and otherwise blocks nothing: open makes the anchor depend on the conversation
through bd's blocks edge, and engage adds the edge again when it starts a
sitting. bd lifts the block once the conversation closes, by whatever route, so
no close writes a release. A failed read of that anchor files nothing, and an
edge the store refuses exits 4 with the conversation filed and the repair named.
engage holds a conversation in a sitting: it attaches
to a live sitting on the bead, or takes the bead's conversation from the
queue, or one whose sitting's session has closed, or files a new one. It then
spawns a manual converse-<model> sitting (origin=manual, backstop-exempt)
named for the conversation, binds the conversation to that sitting's alias
with a write guarded on the holder it read, so the session's own claim adopts
it, and attaches once the reconciler has started it, however long the start
takes, reporting the sitting's state while it waits (an interrupted wait leaves
the sitting to start on its own, to attach later). Pointed at a human gate,
engage takes the one bead still waiting on the gate and makes the conversation
it lands on reply to the gate; with several beads waiting it takes the --from
bead when that bead is one of them, and otherwise the one whose wait on the gate
is oldest, so engaging the question again lands on the same bead, and a note
on the conversation names the others, filed with it when engage files it and
written once onto one the bead already has; with none it says nothing waits and
starts nothing.
Named by a conversation that has closed, engage says when it closed and the
first line of its last hand-back after the header, starts nothing and names
the subject's engage, which opens a fresh conversation. A subject that is
closed too takes no new conversation, and engage names none.
Engaging a bead or a PR names everything that holds it, by the definition the
PR's held: labels and the board's row read (gctk pr status): each open
human gate reached through its open blocks edges, each bead a person owes the
next move on that the same edges reach, such as another PR waiting on a review,
and the PR's own review threads or blocked verdict, and how to engage each.
--model picks the converse variant by the name its template carries after
converse- (claude-opus, the work tier, is the default), and refuses a name
engage does not offer, listing the ones it does. --no-attach spawns without
attaching. Starter seeds and the lens brief live in
assets/scripts/gc-helm-engage-starters.sh.
On a terminal, an engage that names no concern (--reason, --template or
--skill) and not --no-input opens the conversation form, helm-svc's `form`
command (helm_form). One screen holds the subject, a multiline question one
Tab after it, the model, shown with each word of its name capitalized and
Claude-Opus as the default, and whether to attach, which is on unless
--no-attach is given. The subject is a bead id, a PR number or URL, or a rig's
whole name or prefix typed there, matched ignoring case, which starts a new
topic in that rig, so the rig is the operator's choice and is never inferred;
part of a name names nothing. A rig's name wins over a bead of the same id, so
typed text settles only once the city's rigs are read. The subject the command
line names, and a bead the form puts there, such as a gate, are looked up and
never matched to a rig, and --rig fills in the subject with the name of the
rig it names exactly, as open --new-subject --rig does. The rig the subject
names, or a bead's own rig, shows on a line below it. Up and down move between
the fields at a field's first and last row, and stop at the first and last
field. While
the operator types, the form reads `conversations` for the subject: its rig,
whether a sitting can start there, its open conversations and what holds it,
and the city's rigs with their prefixes. A gate
chosen from what holds the subject becomes the subject, read and saved --from
the subject it was chosen from, so a gate several beads wait on is about that
one. A gate typed as the subject is about the bead engage takes from it. A result
for an earlier subject never stands in for the current one, and no result
changes a conversation the operator chose. Ctrl+S saves only once the
destination it shows is settled: open files the question as a new conversation,
with --allow-duplicate and --if-subject naming the subject shown on a subject,
and --new-subject --rig on a topic, and the form says it is saved; engage
<conversation> --no-attach then starts its sitting. On a human gate the question
is optional, and its box shows the gate's own question: left empty, the save
passes open no --reason, so the ask is what the gate asks. Once the sitting has started, the
form attaches to it, or with attaching off leaves it to prepare and names how to
return to it. In a suspended rig, named or a bead's own, attaching is off and
says why, and Ctrl+S saves the question and leaves, starting no sitting: the
conversation waits in the queue until the rig resumes (gc rig resume <rig>).
A save open refuses reads the subject again, so a subject that
names another bead now is shown before the next Ctrl+S can file there. After a
start that failed, Enter attaches, holding the conversation in a new sitting.
Leaving keeps what was saved. A question the form did not save is kept in a file
when it closes, and before the terminal goes to a sitting. `gc-helm attach`
opens the same form on the conversations to return to. A --model the
configured variants do not carry is refused before the form opens.
--skill <name> takes any skill on the sitting's roster (gc skill list --agent
<rig>/gc-toolkit.converse-<model>), a bare name resolving to its one full
match (review-arch to gc-toolkit.review-arch). The new conversation's ask
tells the sitting to load that skill, read the subject through it, and leave
the skill's final writes, such as a review verdict, to the bead it was written
for; a --reason or --template opener follows the brief. It is refused on an
open conversation's id, whose ask is already written, and on a name the
roster does not carry; a roster that will not read seeds the name unverified.
A --reason, --template or --skill with a SUBJECT is a concern of its own, so
it files a new conversation carrying that opener and engages it even when the
bead has one, passing --allow-duplicate through to open and --body the opener
as the ask. A --reason with an open conversation's id is refused, because a
new conversation needs a subject and the reason would otherwise be dropped.
Engage warns when it starts a sitting while another live sitting tracks the
bead, or replies to a gate the bead waits on. The summary prints on stdout; a
single [debug] line of conversation/sitting ids is always printed on stderr.
--new-subject raises a topic that has no bead yet: it creates a fresh
operator-origin subject bead in the --rig rig, the rig being the caller's
choice because there is no id prefix yet to derive one from, then files the
one conversation and engages it, all in one gesture. The positional text, or
--reason without one, is the question: the subject's description keeps it
unchanged with a provenance line after it, its title is the label
conversation_title derives from its opening, and absent --reason or
--template it is the conversation's opener too. The subject is filed assigned
to human, so no first reaction starts on it before its conversation exists.
Once the one conversation engage files tracks the subject, the subject is
handed to it, and a first reaction refuses the subject rather than put it to
the operator a second time.

A bare gc-helm on a terminal opens engage's form on starting a conversation.
The form's pages are tabs at its top: starting a conversation (Ctrl+N),
returning to one (Ctrl+R), and People (Ctrl+P), which lists mechanik and each
rig's Product Owner with the state of its session. A page's key goes to it
from any page and field. ↑ from the subject reaches the tabs, and ←/→ move along
them. Enter on a person leaves the form and then runs `gc-helm po --rig <name>`
or `gc-helm mechanik`, so what the verb prints stays on the terminal and its
exit status is the form's. A seat takes no question, because Gas City's attach
carries no message, so the sitting's purpose is given in the sitting. Each rig
has its own Product Owner, which works that rig's queue and epics, and none
runs in the city's HQ; mechanik is one for the city. Each verb is `gc session
attach` on the seat's session, by the name `gc agent list` gives it:
<rig>/<binding>.po for a rig's Product Owner and <binding>.mechanik for
mechanik, where <binding> is the name the city imports this pack under. It
joins a running session as it stands. For a seat that is not running, it asks
the city's controller to start the session, waits for it to run and then
attaches, and the controller's start gives the agent its prompt as its first
message. The Product Owner starts fresh, so a sitting of it that slept or
ended comes back as a new sitting. A failed attach exits 4 once gc has said
why.

dismiss is the operator's explicit "end this sitting". It closes the
conversation a live sitting holds on the subject, with a reason naming the
dismissal, and answers nothing: every human gate the conversation replies to
stays open and owed, for its filer or the next sitting. It records the
dismissal as one of the visit's actions, a comment on the conversation that
carries no reason, and draws the comment that shows the visit on the subject's
PR again. It then stops the converse session that held the conversation with
`gc runtime drain-ack`, so the controller ends the session outside this
process: the session dismiss runs in acks itself, last, and any other is acked
as an operator. Gas City holds that stop while a client is attached, so the
pane stays live under a tab until it detaches. The ack sets the session's
drain flag, which the converse templates' title reads, so the tab's title
leads with "done" by tmux's next status refresh. --operator says the caller is
outside the sitting even when it runs under the sitting's identity to infer
the subject, as prefix+X does, so every session is acked as an operator and
none acks itself. A session that will not stop holds no conversation any more,
so its template's idle sleep stops it once no client is attached. The close
falls back to --force when bd refuses an operator closing a conversation its
sitting holds. A conversation the verb could not account for aborts the run,
which exits 4. It writes nothing to the subject. A subject with no live
sitting has nothing to end, and dismiss says so and writes nothing; a
conversation id names its own conversation, which dismiss closes whoever holds
it.

dismiss takes the subject as an OPTIONAL argument. Omit it and it infers the
current sitting from session state: the one open conversation assigned to this
session (GC_ALIAS / GC_SESSION_NAME / GC_SESSION_ID), whose subject is the bead
it tracks. That is what lets a bare `gc-helm dismiss` end the sitting the
operator is reading. Inference fails CLOSED — no identity, no held
conversation, more than one, or an unreadable listing each refuse rather than
guess a subject, and name the explicit-id form as the fix.

handback records the hand-back a converse sitting is posting, each framing and
the sign-off, on its conversation. The text is read from stdin and stamped as
gc.handback with gc.handback_at, replacing the one recorded before. A
hand-back recorded once the conversation has closed is the visit's
conclusion, so it also draws the comment that shows the visit on the subject's
PR again. engage runs its attach as a child, so when the tab's tmux client
exits, engage reads the conversation. A closed conversation prints how it
closed and the latest hand-back; a conversation still open prints the command
that re-attaches. A bead that is not a conversation is refused, and so is an
empty stdin.
EOF
}

command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 3; }
command -v gc >/dev/null 2>&1 || { echo "$PROG: gc is required" >&2; exit 3; }

# Portable timeout: GNU timeout, else gtimeout (macOS coreutils), else unbounded.
if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN=gtimeout
else TIMEOUT_BIN=""
fi
with_timeout() {
    _wt_secs="$1"; shift
    if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$_wt_secs" "$@"; else "$@"; fi
}

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# row_now <bead> — the bead's own row as the store answers it now, one line of
# JSON, or empty when it does not resolve. $db is the caller's store pin; the
# verbs that pin by BEADS_DIR leave it unset.
row_now() {
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd show "$1" ${db:+--db "$db"} --json 2>/dev/null | scrub \
        | jq -c --arg b "$1" \
            'if type == "array" then ([ .[] | select(type == "object" and (.id // "") == $b) ] | first // empty) else empty end' \
            2>/dev/null || true
}

# conversation_title <raw> — a conversation's title, whitespace collapsed and
# capped at TAKEAWAY_MAX codepoints and at 400 bytes. gctk's lifecycle.Headline
# REJECTS a takeaway headline over the cap because the headline IS the
# deliverable and only its author knows which clause to keep; a conversation
# carries its full ask in its description, so here the over-cap tail is
# TRUNCATED with an ellipsis instead.
# bd caps a title at 500 BYTES, and a codepoint cap alone overruns it once the
# text is in 4-byte characters, so the byte cap is what keeps the title under
# bd's cap without dropping the reason.
conversation_title() {
    printf '%s' "$1" | jq -Rsr --argjson n "$TAKEAWAY_MAX" \
        '((gsub("\\s+"; " ")) | sub("^ "; "") | sub(" $"; "")) as $h
         | if ($h | length) > $n then (($h[:($n - 1)]) | sub("\\s+$"; "")) + "…" else $h end
         | until(utf8bytelength <= 400; (.[:-2] | sub("\\s+$"; "")) + "…")' \
        2>/dev/null || printf '%s' "$1" | cut -c1-"$TAKEAWAY_MAX"
}

# Sibling tools: assets/scripts/ and tools/ are siblings under the pack root.
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
# The one definition of a conversation's shape: a task that tracks one bead,
# assigned to `human` or to the alias that names its own id. open, engage and
# dismiss read conversations by it, as the board and the liveness classifier
# do. Exposes $CONVERSATION_JQ.
# shellcheck source=conversation.sh
. "${GC_CONVERSATION_LIB:-$SCRIPT_DIR/conversation.sh}" \
    || { echo "$PROG: cannot source conversation.sh from $SCRIPT_DIR" >&2; exit 3; }
# The one definition of whether a rig carries converse — read from the
# import-resolved roster, shared with operator-intake.sh so engage and the
# intake cannot diverge. Exposes rig_carries_converse.
# shellcheck source=converse-capability.sh
. "${GC_CONVERSE_CAPABILITY_LIB:-$SCRIPT_DIR/converse-capability.sh}" \
    || { echo "$PROG: cannot source converse-capability.sh from $SCRIPT_DIR" >&2; exit 3; }
# The one reading of the liveness flags in `gc rig list --json`, shared with
# operator-intake.sh so engage's guard and the intake's note cannot diverge.
# Exposes RIG_PROJECTION_JQ, rig_suspended and city_controller_state.
# shellcheck source=city-liveness.sh
. "${GC_CITY_LIVENESS_LIB:-$SCRIPT_DIR/city-liveness.sh}" \
    || { echo "$PROG: cannot source city-liveness.sh from $SCRIPT_DIR" >&2; exit 3; }
# The one gc.work_outcome stamp a conversation gets before it closes, shared
# with converse-signoff.sh so dismiss cannot diverge from it. Exposes
# work_outcome_noop.
# shellcheck source=work-outcome.sh
. "${GC_WORK_OUTCOME_LIB:-$SCRIPT_DIR/work-outcome.sh}" \
    || { echo "$PROG: cannot source work-outcome.sh from $SCRIPT_DIR" >&2; exit 3; }
# engage's starter seeds live in a sibling data table; its converse-<model>
# variants are enumerated from the agent dirs, so the model menu cannot drift
# from what `gc session new converse-<model>` resolves. Both are overridable so
# a hermetic test can point them at a fixture.
STARTERS_TOOL="${GC_HELM_STARTERS_TOOL:-$SCRIPT_DIR/gc-helm-engage-starters.sh}"
ENGAGE_AGENTS_DIR="${GC_HELM_AGENTS_DIR:-$SCRIPT_DIR/../../agents}"
# The converse templates engage withdraws from its menu and its --model: each
# stays configured only for the sittings already open on it, because Gas City's
# reconciler wakes no session whose template is gone, and goes once none is
# open.
ENGAGE_WITHDRAWN_MODELS="opus fable codex"
# Draws the comment that shows a visit on its subject's PR again from the
# conversation, after a dismiss closes it or a hand-back is recorded on a closed
# one. Best-effort and self-silencing when the subject has no PR or the visit no
# comment; overridable so a hermetic test can point it at a fixture.
SITTING_COMMENT_TOOL="${GC_SITTING_COMMENT_TOOL:-$SCRIPT_DIR/pr-sitting-comment.sh}"
# The longest engage waits, in seconds, for the reconciler to start the sitting
# it spawned before attaching to it. The wait stops once the sitting reads
# active or has ended, so this bound is a backstop for a controller that has
# stopped working the sitting, and it sits above the controller's own limits.
# Gas City rolls back a sitting it has not started 10 minutes after creating it
# (pendingCreateNeverStartedTimeout), and one start runs for at most the city's
# [session] startup_timeout (60s unless the city raises it). 900 clears the two
# together. Overridable, so a hermetic test can reach the bound.
ENGAGE_WAIT_TIMEOUT="${GC_HELM_ENGAGE_WAIT_TIMEOUT:-900}"
case "$ENGAGE_WAIT_TIMEOUT" in ''|*[!0-9]*) ENGAGE_WAIT_TIMEOUT=900 ;; esac
TAB=$(printf '\t')

# Bust the retired bash board's gather cache so a straggler reader never
# serves a pre-write board for a whole TTL.
CACHE_DIR="${TMPDIR:-/tmp}/gc-helm-cache.$(id -u 2>/dev/null || echo 0)"
_city_key=$(printf '%s' "${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-default}}}" | cksum | cut -d' ' -f1)
CACHE_FILE="$CACHE_DIR/board2-$_city_key.ndjson"
bust_cache() { rm -f "$CACHE_FILE" 2>/dev/null || true; }

# The spellings a bead's assignee can carry for THIS session, one per line —
# the same three run-cancel.sh checks a held step's assignee against, and the
# same set the claim hook matches when a respawn adopts a hold. Empty when none
# is set.
session_identities() {
    printf '%s\n%s\n%s\n' "${GC_SESSION_NAME:-}" "${GC_SESSION_ID:-}" "${GC_ALIAS:-}" | grep -v '^$' || true
}

# ── Human gates, conversations and sittings ─────────────────────────
# need_human_gate_jq — load $HUMAN_GATE_JQ, the one rule of which human gates
# still hold a bead, the rule every reader of a bead's gates prepends. It lives
# in bd-lib.sh, a bash library this sh script cannot source, so one bash call
# sources it and prints the rule. Loaded on first use, so the verbs that read
# no gate never pay for it. A library that will not load is an environment
# failure.
HUMAN_GATE_JQ=""
need_human_gate_jq() {
    [ -n "$HUMAN_GATE_JQ" ] && return 0
    HUMAN_GATE_JQ=$(bash -c '. "$1" >/dev/null 2>&1 && printf "%s" "$HUMAN_GATE_JQ"' gc-helm \
        "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" 2>/dev/null) || HUMAN_GATE_JQ=""
    [ -n "$HUMAN_GATE_JQ" ] && return 0
    echo "$PROG: could not read the human gate rule (\$HUMAN_GATE_JQ) from ${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}; it needs bash on PATH. Nothing was written." >&2
    exit 3
}

# need_disposition_jq — load $DISPOSITION_JQ, the one reading of the successor a
# disposed bead names through its duplicates or supersedes edge, from bd-lib.sh
# the same way need_human_gate_jq loads its rule. Loaded on first use.
DISPOSITION_JQ=""
need_disposition_jq() {
    [ -n "$DISPOSITION_JQ" ] && return 0
    DISPOSITION_JQ=$(bash -c '. "$1" >/dev/null 2>&1 && printf "%s" "$DISPOSITION_JQ"' gc-helm \
        "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" 2>/dev/null) || DISPOSITION_JQ=""
    [ -n "$DISPOSITION_JQ" ] && return 0
    echo "$PROG: could not read the disposition rule (\$DISPOSITION_JQ) from ${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}; it needs bash on PATH. Nothing was written." >&2
    exit 3
}

# disposed_to_of <bead-id> — the bead <bead-id> names as its canonical or
# successor, read from its `gc bd list` row in the store its id prefix names, so
# an edge into another rig's store counts. The flags lift every type bd hides from
# a listing, so a gate names its successor as any bead does. Prints nothing when
# it names none. Returns 1 when the row does not read, whether the read failed,
# answered no listing or left the row out, so "names no successor" and "could not
# read" stay apart.
disposed_to_of() {
    need_disposition_jq
    _dt_path=$(rig_path_for_bead "$1")
    _dt_db=""; [ -n "$_dt_path" ] && [ -d "$_dt_path/.beads" ] && _dt_db="$_dt_path/.beads"
    # shellcheck disable=SC2086  # ${_dt_db:+--db "$_dt_db"} expands to 0 or 2 space-free fields
    _dt_raw=$(gc bd list --id "$1" --all --include-gates --include-infra --include-templates ${_dt_db:+--db "$_dt_db"} --json --limit 0 2>/dev/null) || return 1
    printf '%s' "$_dt_raw" | grep -av '^gc bd:' | scrub \
        | jq -er --arg b "$1" "$DISPOSITION_JQ"'
            if type != "array" then error("not a listing") else
              [ .[] | objects | select((.id // "") == $b) ]
              | if length == 0 then error("no row") else (.[0] | disposed_to) end
            end' 2>/dev/null
}

# bd_rows <gc-bd-args...> — one `gc bd` read that must answer a JSON array,
# printed scrubbed with the `gc bd:` rig-store notice stripped. Returns 1 on a
# read that failed or answered anything else, so "none" and "could not read"
# stay apart.
bd_rows() {
    _br_raw=$(gc bd "$@" --json 2>/dev/null) || return 1
    printf '%s' "$_br_raw" | grep -av '^gc bd:' | scrub | jq -ce 'if type == "array" then . else error("not an array") end' 2>/dev/null
}

# human_gate_rows <bead> — the bead's human gates, open and closed, as the rows
# `gc bd dep list <bead> --type blocks` answers. Each row carries the gate's id,
# status, await_id, assignee, title, created_at and, once closed, close_reason.
# Returns 1 when the read did not answer.
human_gate_rows() {
    need_human_gate_jq
    _hg_rows=$(bd_rows dep list "$1" --type blocks) || return 1
    printf '%s' "$_hg_rows" | jq -c "$HUMAN_GATE_JQ"'[ .[] | objects | select(human_gate) ]' 2>/dev/null
}

# gate_waiters <gate> — the beads that wait on the gate through `blocks` edges,
# open and closed, as `gc bd dep list <gate> --direction=up --type blocks` rows.
# A reader that starts from a gate learns what it is about this way. Returns 1
# when the read did not answer.
gate_waiters() {
    _gw_rows=$(bd_rows dep list "$1" --direction=up --type blocks) || return 1
    printf '%s' "$_gw_rows" | jq -c '[ .[] | objects ]' 2>/dev/null
}

# bead_conversations <bead> — the conversations about the bead that are not
# closed, as `gc bd list` rows: each task whose own row has the whole shape
# ($CONVERSATION_JQ's conversation) with the bead as its one subject. The
# inverse `tracks` listing names the candidates, the tasks that track the bead
# assigned to `human` or to the alias that names their own id. It proves only
# that each one tracks the bead, not that the bead is all it tracks, so the
# candidates' own rows are read with their edges, in one listing, and the shared
# rule decides. Returns 1 when either read did not answer, or answered without a
# candidate's row, because a candidate whose edges nothing read proves nothing.
bead_conversations() {
    _bc_rows=$(bd_rows dep list "$1" --direction=up --type tracks) || return 1
    _bc_ids=$(printf '%s' "$_bc_rows" | jq -r "$CONVERSATION_JQ"'
        [ .[] | objects
          | select((.issue_type // "task") == "task")
          | select(((.status // "open") | tostring | ascii_downcase) != "closed")
          | select((((.assignee // "") | tostring) == "human") or conversation_alias)
          | (.id // "") | tostring | select(. != "") ] | unique | join(",")' 2>/dev/null) || return 1
    if [ -z "$_bc_ids" ]; then
        printf '[]\n'
        return 0
    fi
    _bc_own=$(bd_rows list --id "$_bc_ids" --all) || return 1
    printf '%s' "$_bc_own" | jq -ce --arg b "$1" --arg ids "$_bc_ids" "$CONVERSATION_JQ"'
        ($ids | split(",")) as $want
        | [ .[] | objects | select(((.id // "") | tostring) as $i | any($want[]; . == $i)) ] as $own
        | if ([ $own[] | .id ] | unique) != $want then error("a candidate row did not read")
          else [ $own[]
                 | select(((.status // "open") | tostring | ascii_downcase) != "closed")
                 | select(conversation and conversation_subjects == [$b]) ]
          end' 2>/dev/null
}

# session_list_from_store — `gc session list --json` from the city's store
# (GC_NO_API=1), which lists a session from its create on, as the supervisor's
# read cache does not. Every read here that decides a sitting is live reads it.
session_list_from_store() {
    GC_NO_API=1 gc session list --json 2>/dev/null
}

# live_sittings — the converse sessions the store's session list
# (session_list_from_store) holds that have not ended, one {id, alias,
# session_name, created_at, attached, state} object each, as a JSON array. A
# converse session is one whose template names converse. A sleeping session is
# listed, because attaching wakes it, and so is an open one listed with no
# state, which Gas City's own wait for a new session reads as a create still
# under way. A closed session and one whose create failed are left out. Returns
# 1 when the list did not answer, which proves no sitting live and none gone.
live_sittings() {
    _ls_raw=$(session_list_from_store) || return 1
    live_sittings_in "$_ls_raw"
}

# live_sittings_in <session-list> — live_sittings over a session list already
# read from the store, so one read answers it and the seats (SEATS_JQ).
live_sittings_in() {
    printf '%s' "$1" | scrub | jq -ce '
        if type == "object" and ((.sessions // null) | type) == "array"
        then [ .sessions[] | objects
               | select((.closed // false) != true)
               | select(((.state // "") | tostring) as $st | $st != "closed" and $st != "failed-create")
               | select(((.template // "") | tostring) | test("converse"))
               | {id: ((.id // "") | tostring), alias: ((.alias // "") | tostring),
                  session_name: ((.session_name // "") | tostring),
                  created_at: ((.created_at // "") | tostring), attached: ((.attached // false) == true),
                  state: ((.state // "") | tostring)} ]
        else error("sessions array unreadable") end' 2>/dev/null
}

# $SITTING_JQ — the live sitting that holds a conversation row, given
# live_sittings as $live: the first session whose alias, session name or id is
# the row's assignee, or whose alias names the conversation's own id while the
# assignee does too (conversation_alias). held_live is whether there is one.
# Prepend $CONVERSATION_JQ.
SITTING_JQ='
  def sitting($live):
    . as $row | ((.assignee // "") | tostring) as $a
    | if $a == "" or $a == "human" then null
      else first($live[] | . as $s
                 | select($s.alias == $a or $s.session_name == $a or $s.id == $a
                          or (($row | conversation_alias)
                              and ({id: ($row.id // ""), assignee: $s.alias} | conversation_alias)))) // null
      end;
  def held_live($live): sitting($live) != null;
'

# $READINESS_JQ — a conversation as `conversations` prints it, from its `gc bd
# list` row, given live_sittings as $live and the name of the rig whose store
# holds it as $rig. Its state is engage's: live while a live sitting holds it,
# queue while it waits assigned to `human`, left once its sitting's session has
# closed. Its readiness says when to come back to it: queued, starting while its
# session has not started, preparing until the sitting records its first
# hand-back (gc.handback_at, which cmd_handback stamps on each framing) after
# the session was created, ready once it has, and ended for a conversation
# whose sitting is gone. Prepend $CONVERSATION_JQ$SITTING_JQ.
READINESS_JQ='
  def readiness_row($live; $rig):
    sitting($live) as $s
    | ((.metadata // {})["gc.handback_at"] // "" | tostring) as $hb
    | (if ((.assignee // "") | tostring) == "human" then "queue" elif $s != null then "live" else "left" end) as $state
    | {id: ((.id // "") | tostring), rig: $rig, subject: (conversation_subjects[0] // ""),
       title: ((.title // "") | tostring), status: ((.status // "") | tostring | ascii_downcase),
       holder: ((.assignee // "") | tostring), created_at: ((.created_at // "") | tostring),
       handback_at: $hb, state: $state,
       session: (if $s == null then null
                 else {id: $s.id, name: $s.session_name, state: $s.state, attached: $s.attached,
                       created_at: $s.created_at} end),
       readiness: (if $state == "queue" then "queued"
                   elif $state == "left" then "ended"
                   elif ($s.state == "start-pending" or $s.state == "creating" or $s.state == "") then "starting"
                   elif $hb != "" and $hb >= $s.created_at then "ready"
                   else "preparing" end)};
'

# ── Rig enumeration ──────────────────────────────────────────────────
# Sets RIGS (JSON array of {name,path,prefix,hq,suspended}, plus running on the
# HQ row; city-liveness.sh's RIG_PROJECTION_JQ); exits 3 otherwise. For a
# non-CLI caller (the web board's open button) the code plus the sentence is
# the whole signal, so a listing that does not read leaves rig-map.sh's reason,
# which names the operator's move for its cause, on stderr above this script's.
RIGS=""
rigs_count() {
    # jq emits nothing on empty input; normalize so arithmetic never throws.
    _rc=$(printf '%s' "$RIGS" | jq 'length' 2>/dev/null || echo 0)
    case "$_rc" in ''|*[!0-9]*) _rc=0 ;; esac
    printf '%s' "$_rc"
}
enumerate_rigs() {
    [ -n "$RIGS" ] && return 0
    if [ -n "$FIXTURE" ] && [ -f "$FIXTURE/rigs.json" ]; then
        RIGS=$(jq -c '.' < "$FIXTURE/rigs.json" 2>/dev/null || printf '[]')
        [ "$(rigs_count)" -gt 0 ] && return 0
    fi
    rigs_raw=$("$SCRIPT_DIR/rig-map.sh") || {
        echo "$PROG: could not enumerate rigs. This command wrote nothing." >&2
        exit 3
    }

    # The projection carries the flags engage's liveness guard reads from this
    # same enumeration (city-liveness.sh says which, and why a rig row's running
    # is not one). A `gc rig list` that omits a flag leaves it null, which the
    # guard treats as unknown and never refuses on.
    RIGS=$(printf '%s' "$rigs_raw" | jq -c "$RIG_PROJECTION_JQ" 2>/dev/null || printf '[]')
    if [ "$(rigs_count)" -eq 0 ]; then
        # gc answered correctly: this city really has no rigs. Not a malfunction.
        echo "$PROG: no rigs in this city: 'gc rig list' answered normally with an empty rig set. Add one with 'gc rig add', or point GC_CITY at the intended city. This command wrote nothing." >&2
        exit 3
    fi
}

# rig_path_for_bead <bead-id> — rig repo path owning the bead, by id prefix.
rig_path_for_bead() {
    enumerate_rigs
    printf '%s' "$RIGS" | jq -r --arg p "${1%%-*}" '.[] | select(.prefix==$p) | .path' 2>/dev/null | head -n1
}

# rig_name_for_bead <bead-id> — rig NAME owning the bead, by id prefix.
rig_name_for_bead() {
    enumerate_rigs
    printf '%s' "$RIGS" | jq -r --arg p "${1%%-*}" '.[] | select(.prefix==$p) | .name' 2>/dev/null | head -n1
}

# rig_db_for_session — the .beads dir of THIS session's rig, or empty when it
# cannot be resolved. Where the resolvers above key off a bead id, this one
# keys off the session itself: a converse sitting's conversation is filed in
# its SUBJECT's rig, but the session runs with GC_RIG and BEADS_DIR unset and
# so defaults to the CITY store, where that rig-filed conversation is absent. Take the
# rig name from the environment when it names one, else from this session's own
# runtime record (.rig, matched on any identity form), and map it to a repo
# path. Best-effort: an unresolved rig yields empty and the caller keeps its
# default store rather than failing.
rig_db_for_session() {
    _srig="${GC_RIG:-}"
    if [ -z "$_srig" ]; then
        _sids=$(session_identities)
        [ -n "$_sids" ] || return 0
        _srig=$(gc session list --json 2>/dev/null | scrub \
            | jq -r --arg ids "$_sids" '
                ($ids | split("\n") | map(select(. != ""))) as $me
                | [ .sessions[]? | objects | . as $s
                    | ([ $s.id, $s.session_name, $s.alias, $s.name, $s.agent_name ]
                       | map(select(. != null and . != ""))) as $sig
                    | select([ $sig[] | select(. as $x | $me | index($x)) ] | length > 0)
                    | ($s.rig // "") ]
                | map(select(. != "")) | first // ""' 2>/dev/null || true)
    fi
    [ -n "$_srig" ] || return 0
    _spath=$("$SCRIPT_DIR/rig-map.sh" \
        | jq -r --arg n "$_srig" '.rigs[]? | objects | select(.name == $n) | .path' 2>/dev/null | head -n1)
    [ -n "$_spath" ] && [ -d "$_spath/.beads" ] && printf '%s' "$_spath/.beads"
}

# ── Subject resolver: an operator reference to the live bead it owns ──
# The operator supplies a subject by reading it off whatever is in front of
# them — a PR, a board row, a bead whose title cites its lineage. A PR/bead
# title legitimately names OTHER beads (the beads it superseded), so an id scraped from
# one opens the wrong bead: the settled predecessor of a fold, or nothing. The
# fix is a deterministic resolver keyed on structured metadata and the graph,
# never on title text, so a PR number or a superseded id cannot open a dead
# bead.
#
# resolve_live_subject <reference> sets RESOLVED_SUBJECT. A live bead id, and
# any reference this resolver does not recognize (a topic string), pass through
# unchanged for the caller's own existence gate to judge. It fails CLOSED
# (exit 4) on a PR that resolves to no live anchor or to several, when a store
# the PR search must read is unreadable, and on a superseded-by cycle, naming
# what it could not resolve — the alternative is filing on the wrong bead,
# which is the defect this exists to end.
#
#   PR number (615) or URL (…/pull/615)  ->  the anchor of the live beads whose
#                                            pr_number / pr_url matches: each
#                                            one's anchor_bead, or the bead
#                                            itself when it names none (never a
#                                            title)
#   closed + a duplicates/supersedes edge ->  followed to the live successor
#   live bead id                         ->  unchanged
# pr_reference <reference> — classify a reference without touching the store:
# PR_NUM is its PR number and PR_URL its PR URL, both empty for anything else. A
# PR URL pins the repo; a bare number does not. A bead id carries a rig prefix
# and a dash; a topic string is neither.
PR_NUM=""; PR_URL=""
pr_reference() {
    PR_NUM=""; PR_URL=""
    case "$1" in
        http://*/pull/[0-9]*|https://*/pull/[0-9]*)
            PR_URL="$1"
            PR_NUM=$(printf '%s' "$1" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p') ;;
        *[!0-9]*) : ;;               # a non-digit: not a bare PR number
        [0-9]*)   PR_NUM="$1" ;;     # all digits: a bare PR number
    esac
}

RESOLVED_SUBJECT=""
resolve_live_subject() {
    _rls_ref="$1"
    RESOLVED_SUBJECT="$_rls_ref"

    # Rig health first: the PR search reads every rig's store, so validate the
    # rig list (exit 3) before any read reaches the wire, and cache it here for
    # the search and for the caller's later rig_path_for_bead.
    enumerate_rigs

    pr_reference "$_rls_ref"
    if [ -n "$PR_NUM" ]; then
        _resolve_pr_reference "$PR_NUM" "$PR_URL"
        return 0
    fi

    case "$_rls_ref" in
        *-*) _resolve_superseded_reference "$_rls_ref" ;;
    esac
    return 0
}

# _resolve_pr_reference <number> <url-or-empty> — set RESOLVED_SUBJECT to the
# LIVE anchor that owns this PR, or exit 4 fail-closed. pr_number / pr_url are
# bare metadata keys (signoff.sh, pr-facts.sh). Filtered CLIENT-SIDE: bd list's
# --metadata-field mangles a numeric value into non-JSON here. A URL additionally
# pins the repo, so a bare number several repos share is disambiguated by it.
# The anchor records its own PR, and so does a bead that works on the PR, such
# as a rework child, which names the anchor in anchor_bead. So each bead that
# records the PR stands for its anchor_bead, or for itself when it names none,
# and the PR is ambiguous only when those are two different anchors. An
# anchor_bead must name a bead live in a store the search read, so a live
# rework of a closed anchor refuses, naming both.
# The status set is the pack's live-PR set (LIVE_STATUSES in pr-facts.sh,
# mergeLiveStatuses in gctk merge): an anchor is live in deferred/hooked/pinned
# too, so a narrower query would fail to resolve a PR whose bead sits in one of
# those states. The number's uniqueness holds only across EVERY live store, so
# any rig the search cannot fully read refuses the whole resolution (exit 4)
# naming that ledger, rather than resolve from the stores that answered while a
# dropped one may also record the number: a rig with no .beads ledger to pin
# with --db, a list that exits non-zero, and an answer that is not a JSON array.
# pr_reference_anchors is that search: it sets PR_ANCHORS to the live anchors
# that record the PR, one per line, and exits 4 on the stores it could not read
# and on a dead anchor. conversations offers several for an explicit choice.
_resolve_pr_reference() {
    pr_reference_anchors "$1" "$2"
    _pr_uniq="$PR_ANCHORS"
    _pr_count=$(printf '%s\n' "$_pr_uniq" | awk 'NF{c++} END{print c + 0}')

    if [ "$_pr_count" -eq 0 ]; then
        echo "$PROG: no open bead records PR #$_pr_num${_pr_url:+ ($_pr_url)}. If it merged its anchor is closed and there is nothing live to open a conversation on; otherwise pass the live bead id. Nothing filed." >&2
        exit 4
    fi
    if [ "$_pr_count" -gt 1 ]; then
        echo "$PROG: PR #$_pr_num is ambiguous — it resolves to more than one bead: $(printf '%s' "$_pr_uniq" | tr '\n' ' '). Pass the PR URL to pin the repo, or the live bead id directly. Nothing filed." >&2
        exit 4
    fi
    RESOLVED_SUBJECT=$(printf '%s' "$_pr_uniq" | awk 'NF{print; exit}')
    echo "$PROG: PR #$_pr_num -> $RESOLVED_SUBJECT (matched by pr_number/pr_url metadata, never a title)." >&2
}

PR_ANCHORS=""
pr_reference_anchors() {
    _pr_num="$1"; _pr_url="$2"
    # The URL pins the repo. A browser copy can be a PR subpage (…/pull/615/files)
    # or carry a query string, but pr-open.sh stores and merge.sh compares the
    # canonical …/pull/<number> form, so canonicalize the paste before matching.
    _pr_url=$(printf '%s' "$_pr_url" | tr -d '[:space:]' | sed -e 's#\(/pull/[0-9][0-9]*\).*#\1#' -e 's#/*$##')
    _pr_hits=""; _pr_live=""
    _pr_paths=$(printf '%s' "$RIGS" | jq -r '.[].path // ""' 2>/dev/null) || _pr_paths=""
    _pr_saved_ifs=$IFS
    IFS='
'
    for _pr_p in $_pr_paths; do
        _pr_rig=$(printf '%s' "$RIGS" | jq -r --arg p "$_pr_p" '.[] | select(.path == $p) | .name' 2>/dev/null | head -n1)
        # A listed rig whose ledger cannot be pinned with --db would make the
        # per-rig read fall back to the session default store: one store read
        # twice, this rig never read. That is the same incomplete cross-store
        # proof a non-zero or non-array read leaves below, so refuse it the same
        # way. Resolving a bare number while a live rig went unread could file on
        # the wrong repo's anchor.
        if [ -z "$_pr_p" ] || [ ! -d "$_pr_p/.beads" ]; then
            echo "$PROG: PR #$_pr_num is unverifiable: the ledger for rig ${_pr_rig:-?} (${_pr_p:-<no path>}) has no readable .beads store to pin with --db, so the search would fall back to the session default store and never read this rig. A bare PR number is unique only across every live store, so resolving it with a rig unread could file a conversation on the wrong repo's anchor. Repair that store (gc doctor / Dolt) or pass the live bead id. Nothing filed." >&2
            exit 4
        fi
        _pr_db="$_pr_p/.beads"
        # Capture bd's OWN exit status — a pipe to scrub would report scrub's. A
        # store that will not read (non-zero exit) or answers with something that
        # is not a JSON array (an error object, a wedged empty answer) leaves the
        # cross-store uniqueness proof incomplete, so refuse rather than resolve
        # from the stores that answered.
        _pr_rc=0
        _pr_raw=$(gc bd list --db "$_pr_db" --status open,in_progress,blocked,deferred,hooked,pinned --limit 0 --json 2>/dev/null) || _pr_rc=$?
        _pr_rows=$(printf '%s' "$_pr_raw" | scrub)
        if [ "$_pr_rc" -ne 0 ] || ! printf '%s' "$_pr_rows" | jq -e 'type == "array"' >/dev/null 2>&1; then
            _pr_led="$_pr_db"
            if [ "$_pr_rc" -ne 0 ]; then _pr_why="gc bd list exited $_pr_rc"; else _pr_why="its answer was not a JSON array"; fi
            echo "$PROG: PR #$_pr_num is unverifiable: the ledger for rig ${_pr_rig:-?} ($_pr_led) did not read ($_pr_why). A bare PR number is unique only across every live store, so resolving it from the stores that answered could file a conversation on the wrong repo's anchor. Repair that store (gc doctor / Dolt) or pass the live bead id. Nothing filed." >&2
            exit 4
        fi
        # One "<id> <anchor>" line per bead that records the PR.
        _pr_found=$(printf '%s' "$_pr_rows" | jq -r --arg n "$_pr_num" --arg u "$_pr_url" '
            .[]? | objects
            | select(((.metadata.pr_number // "") | tostring) == $n)
            | select($u == "" or (((.metadata.pr_url // "") | gsub("[[:space:]]";"") | sub("(?<p>/pull/[0-9]+).*"; .p)) == $u))
            | ((.metadata.anchor_bead // "") | tostring | gsub("[[:space:]]";"")) as $a
            | "\(.id) \(if $a == "" then .id else $a end)"' 2>/dev/null) || _pr_found=""
        for _pr_pair in $_pr_found; do
            [ -n "$_pr_pair" ] && _pr_hits="$_pr_hits$_pr_pair
"
        done
        _pr_live="$_pr_live$(printf '%s' "$_pr_rows" | jq -r '.[]? | objects | .id // empty' 2>/dev/null)
"
    done

    _pr_anchors=""
    for _pr_pair in $_pr_hits; do
        _pr_id=${_pr_pair%% *}; _pr_anchor=${_pr_pair#* }
        if [ "$_pr_anchor" != "$_pr_id" ] && ! printf '%s\n' "$_pr_live" | awk -v a="$_pr_anchor" '$0 == a {f = 1} END {exit !f}'; then
            echo "$PROG: PR #$_pr_num has no live anchor: $_pr_id records it as work on $_pr_anchor, which is not live in any store the search read. Pass the live bead id directly. Nothing filed." >&2
            exit 4
        fi
        _pr_anchors="$_pr_anchors$_pr_anchor
"
    done
    IFS=$_pr_saved_ifs

    PR_ANCHORS=$(printf '%s' "$_pr_anchors" | awk 'NF && !seen[$0]++')
}

# _resolve_superseded_reference <bead-id> — follow a settled disposition
# (status closed + the duplicates or supersedes edge bead-rehome.sh records) to
# its live successor and set RESOLVED_SUBJECT. The edge is read off the bead's
# list row, which carries one into another rig's store, and the successor is
# read cross-ledger by its rig-unique id. A live bead, or one that does not
# resolve, passes through unchanged for the caller's existence gate. A cycle, and
# a closed bead whose list row does not read, are refused (exit 4) rather than
# guessed.
_resolve_superseded_reference() {
    _ss_orig="$1"; _ss_cur="$1"; _ss_seen=" $1 "; _ss_hops=0
    while [ "$_ss_hops" -le 24 ]; do
        _ss_row=$(gc bd show "$_ss_cur" --json 2>/dev/null | scrub) || _ss_row=""
        _ss_this=$(printf '%s' "$_ss_row" | jq -c --arg b "$_ss_cur" \
            'if type == "array" then (first(.[] | objects | select((.id // "") == $b)) // null) else null end' 2>/dev/null) || _ss_this="null"
        if [ -z "$_ss_this" ] || [ "$_ss_this" = "null" ]; then
            # The reference ITSELF does not resolve: pass it through unchanged so
            # the caller's existence gate reports a clean not-found.
            [ "$_ss_cur" = "$_ss_orig" ] && { RESOLVED_SUBJECT="$_ss_orig"; return 0; }
            # A SUCCESSOR we followed does not resolve (a broken edge, or one onto
            # a store no rig names). Refuse — never fall back to opening the
            # settled predecessor.
            echo "$PROG: $_ss_orig is superseded by $_ss_cur, which does not resolve (a broken edge, or one onto a store no rig names). Refusing to open the settled predecessor; pass the live bead id directly. Nothing filed." >&2
            exit 4
        fi
        _ss_status=$(printf '%s' "$_ss_this" | jq -r '.status // ""' 2>/dev/null) || _ss_status=""
        _ss_succ=""
        if [ "$_ss_status" = "closed" ] && ! _ss_succ=$(disposed_to_of "$_ss_cur"); then
            echo "$PROG: $_ss_cur is closed, and its list row did not read, so whether it names a successor is unknown. Refusing to open the settled bead; re-run once the store answers, or pass the live bead id directly. Nothing filed." >&2
            exit 4
        fi
        if [ "$_ss_status" = "closed" ] && [ -n "$_ss_succ" ]; then
            case "$_ss_seen" in
                *" $_ss_succ "*)
                    echo "$PROG: $_ss_orig leads to a superseded-by cycle at $_ss_succ; refusing to guess which is live. Pass the live bead id directly. Nothing filed." >&2
                    exit 4 ;;
            esac
            _ss_seen="$_ss_seen$_ss_succ "
            _ss_cur="$_ss_succ"
            _ss_hops=$((_ss_hops + 1))
            continue
        fi
        break
    done
    if [ "$_ss_cur" != "$_ss_orig" ]; then
        echo "$PROG: $_ss_orig is closed and superseded -> resolving to the successor $_ss_cur (never the settled predecessor)." >&2
    fi
    RESOLVED_SUBJECT="$_ss_cur"
}

# ── Verb: resolve ────────────────────────────────────────────────────
# resolve <reference> — print the LIVE bead a reference resolves to, the same
# way open and engage resolve their subject: a PR number/URL to its anchor,
# a closed+superseded id to its successor. A live bead id, or any reference
# the resolver does not recognize (a topic string), prints unchanged; an
# unresolvable or ambiguous PR, or a superseded-by cycle, is
# refused (exit 4) naming what it could not resolve. Read-only — it files
# nothing. operator-intake.sh calls this before it decides a reference is a new
# topic, so a PR number or URL reaches the resolver instead of becoming a topic
# bead titled with its number.
cmd_resolve() {
    resolve_ref=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -*) echo "$PROG: resolve: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$resolve_ref" ] || { echo "$PROG: resolve takes one reference" >&2; exit 2; }; resolve_ref="$1"; shift ;;
        esac
    done
    case "$resolve_ref" in "") echo "$PROG: resolve needs <bead-id|pr-number|pr-url>" >&2; usage; exit 2 ;; esac
    resolve_live_subject "$resolve_ref"
    printf '%s\n' "$RESOLVED_SUBJECT"
}

# verify_subject <bead-id> <verb> <nothing-clause> [<subject-ref>] — resolve a
# bead id to its live row before a write verb acts on it, classifying a
# non-answer the way `open` does. A probe that did not ANSWER — empty output, or
# an error OTHER than the "no issues found" not-found error — is a data-plane
# outage: retryable, existence UNKNOWN, NOT a missing bead. Only a well-formed
# result that resolves no matching row is a genuine not-found, and an id whose
# prefix matches no rig is a not-found provable without the data plane. open,
# engage and dismiss share this one path, so a refused Dolt connection
# is never reported to the operator as a typo and the message cannot drift
# between verbs.
#
# `gc bd show <id>` is deliberately UNPINNED: it resolves across ledgers
# regardless of BEADS_DIR, so pinning --db by prefix would false-refuse a real
# subject. The raw read is captured before scrub so an EMPTY answer stays
# distinguishable from an error object, and the id is compared for EQUALITY so a
# row for a different bead is not taken as a resolution.
#
# On a resolved subject: sets VS_PAYLOAD (the scrubbed `gc bd show` array) and
# VS_ROW (the matched object), and returns 0. Otherwise prints the classified
# message to stderr — "$PROG: <verb>: …" suffixed with <nothing-clause> (e.g.
# "Nothing spawned.") — and returns 4, the fail-closed exit code every caller
# already uses. <subject-ref> overrides how the id is named in that message;
# empty uses the bare quoted id.
verify_subject() {
    _vs_bead="$1"; _vs_verb="$2"; _vs_nothing="$3"
    _vs_ref="${4:-}"; [ -n "$_vs_ref" ] || _vs_ref="'$_vs_bead'"
    VS_PAYLOAD=""; VS_ROW=""; _vs_id=""
    _vs_raw=$(gc bd show "$_vs_bead" --json 2>/dev/null || true)
    VS_PAYLOAD=$(printf '%s' "$_vs_raw" | scrub)
    VS_ROW=$(printf '%s' "$VS_PAYLOAD" \
        | jq -c --arg b "$_vs_bead" \
            'if type == "array"
             then ([ .[] | select(type == "object" and (.id // "") == $b) ] | first) // empty
             else empty end' 2>/dev/null || true)
    case "$VS_ROW" in ""|null) VS_ROW="" ;; esac
    if [ -n "$VS_ROW" ]; then
        _vs_id=$(printf '%s' "$VS_ROW" | jq -r '.id // empty' 2>/dev/null || true)
    fi
    [ -n "$_vs_id" ] && return 0

    # No matching row. Not-found is the specific "no issues found" error; any
    # OTHER error means the read FAILED and existence is unknown — reporting an
    # outage as a typo sends the operator hunting a bead that is there.
    _vs_rig=$(rig_name_for_bead "$_vs_bead")
    _vs_probe_err=$(printf '%s' "$VS_PAYLOAD" \
        | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null || true)
    case "$_vs_probe_err" in *"no issues found"*) _vs_probe_err="" ;; esac
    if [ -z "$_vs_rig" ]; then
        echo "$PROG: $_vs_verb: bead not found: $_vs_ref — its id prefix '${_vs_bead%%-*}' matches no rig in 'gc rig list'. $_vs_nothing" >&2
    elif [ -z "$_vs_raw" ] || [ -n "$_vs_probe_err" ]; then
        echo "$PROG: $_vs_verb: could not verify $_vs_ref — 'gc bd show' did not answer${_vs_probe_err:+ ($_vs_probe_err)} (data plane down?). $_vs_nothing" >&2
    else
        echo "$PROG: $_vs_verb: bead not found: $_vs_ref — no rig ledger answers for that id. $_vs_nothing" >&2
    fi
    return 4
}

# ── Conversations: the bead a call is about, and the reply onto a gate ──
# words_and <word>... — the words as a sentence lists them: "a", "a and b",
# "a, b and c".
words_and() {
    case $# in
        0) return 0 ;;
        1) printf '%s' "$1" ;;
        *) _wa_out="$1"; shift
           while [ $# -gt 1 ]; do _wa_out="$_wa_out, $1"; shift; done
           printf '%s and %s' "$_wa_out" "$1" ;;
    esac
}

# gate_pick <gate> <bead>... — of the open beads that wait on the gate, the one
# a conversation about the gate is about: the bead whose blocks edge onto the
# gate is oldest, then the lowest id. An edge's age never changes, so the pick
# stays on that bead while it waits, and the question engaged again finds the
# conversation filed there. A priority can change between two engages, and a
# pick that followed it would move to a bead with no conversation and file a
# second one for the same question. `gc bd gate create --blocks` writes a gate
# with its first edge, so the oldest edge is normally the bead the question was
# asked about. A `gc bd list` row carries each of its edges with the edge's own
# created_at, which the `gc bd dep list` rows gate_waiters reads leave out, so
# the beads' own rows are read, in one listing. Returns 1 when that read did not
# answer, or answered without a bead's row.
gate_pick() {
    _gp_gate="$1"; shift
    _gp_ids=$(printf '%s,' "$@"); _gp_ids="${_gp_ids%,}"
    _gp_rows=$(bd_rows list --id "$_gp_ids" --all --limit 0) || return 1
    printf '%s' "$_gp_rows" | jq -er --arg g "$_gp_gate" --arg ids "$_gp_ids" '
        ($ids | split(",")) as $want
        | [ .[] | objects | select(((.id // "") | tostring) as $i | any($want[]; . == $i)) ] as $rows
        | if ([ $rows[] | .id | tostring ] | unique) != ($want | unique) then error("a bead did not read") else . end
        | [ $rows[]
            | {id: (.id | tostring),
               at: ([ (.dependencies // [])[]? | objects
                      | select(((.depends_on_id // "") | tostring) == $g
                               and (((.type // .dependency_type) // "") | tostring) == "blocks")
                      | (.created_at // "") | tostring | select(. != "") ] | min // "")} ]
        | sort_by((.at == ""), .at, .id) | first | .id' 2>/dev/null
}

# gate_others_line — the sentence a conversation that answers a gate several
# open beads wait on carries about the other beads (TAKE_OTHERS), so its sitting
# sees each bead the answer reaches. Empty when the conversation answers no gate
# or the gate holds no other bead. The sentence rides in the conversation's
# notes and never in its ask: the beads waiting on a gate change while the
# question stays the same, and the ask is what a run again matches the
# conversation by.
gate_others_line() {
    [ -n "$TAKE_GATE" ] && [ -n "$TAKE_OTHERS" ] || return 0
    # shellcheck disable=SC2086  # one word per bead
    set -- $TAKE_OTHERS
    _gol_waits="wait"; [ $# -gt 1 ] || _gol_waits="waits"
    printf 'Gate %s also holds %s, which %s on the same answer.' "$TAKE_GATE" "$(words_and "$@")" "$_gol_waits"
}

# conversation_carries <row> <text> — 0 iff the conversation's row, a row_now
# answer, holds the text in its ask or its notes. A row that did not read holds
# nothing.
conversation_carries() {
    printf '%s' "$1" | jq -e --arg n "$2" '((.description // "") + "\n" + (.notes // "")) | contains($n)' >/dev/null 2>&1
}

# conversation_note_others <verb> <conversation> <sentence> <gate> — give a
# conversation that open or engage lands on, and did not file this run, the
# sentence naming the other open beads the gate holds now (gate_others_line) as
# a note, unless it carries that sentence already, so its sitting sees each bead
# the answer reaches. A row that does not read proves nothing, so the note is
# written. The conversation's reply onto the gate names the gate to its sitting,
# so a note the store refuses costs a warning.
conversation_note_others() {
    [ -n "$3" ] || return 0
    conversation_carries "$(row_now "$2")" "$3" && return 0
    gc bd update "$2" --append-notes "$3" >/dev/null 2>&1 \
        || echo "$PROG: $1: warning: the store refused the note on conversation $2 naming the other beads gate $4 holds; they are listed by: gc bd dep list $4 --direction=up --type blocks" >&2
    return 0
}

# take_bead <verb> <nothing-msg> [<from>] — settle which bead a conversation is about,
# from the verified row verify_subject left in VS_ROW: the bead itself, the
# subject a conversation id tracks, or, for a gate, a bead still waiting on it,
# since a conversation always tracks a bead and never a gate. Sets TAKE_BEAD
# (that bead), TAKE_GATE (the human gate the id named, which the conversation
# replies to), TAKE_CONV (the conversation the id named), TAKE_OTHERS (the other
# open beads the gate holds, sorted) and TAKE_PICKED (1 when gate_pick chose
# the bead). A gate several open beads wait on takes <from>, the bead the caller
# reached it from, when it is one of them. A <from> that waits on the gate only
# through another bead, such as its rework, takes the gate as it is without
# <from>, and one the gate no longer holds (holding_rows) is refused. Otherwise
# open, engage and conversations take the bead gate_pick names, and dismiss
# and handback refuse the gate, naming the beads, so the operator names
# the one they mean, because a pick there would act on a bead nobody named. A
# gate nothing waits on is refused, naming the beads it was about, because a
# sitting there would answer an ask that holds nothing. A refusal or a read that
# did not answer exits 4 with <nothing-msg>.
TAKE_BEAD=""; TAKE_GATE=""; TAKE_CONV=""; TAKE_OTHERS=""; TAKE_PICKED=""
take_bead() {
    _tb_verb="$1"; _tb_nothing="$2"; _tb_from="${3:-}"
    TAKE_BEAD=""; TAKE_GATE=""; TAKE_CONV=""; TAKE_OTHERS=""; TAKE_PICKED=""
    # A `gc bd show` row spells an edge {dependency_type, id}; the shape rule
    # reads the `gc bd list` spelling {type, depends_on_id}, so the row is
    # respelled before conversation.sh's rule reads it.
    _tb_kind=$(printf '%s' "$VS_ROW" | jq -r "$CONVERSATION_JQ"'
        .dependencies = [ (.dependencies // [])[]? | objects
                          | {type: ((.type // .dependency_type) // ""), depends_on_id: ((.depends_on_id // .id) // "")} ]
        | if (.issue_type // "") == "gate" then "gate\t" + ((.await_type // "") | tostring)
          elif conversation then "conversation\t" + conversation_subjects[0]
          else "bead\t" end' 2>/dev/null || true)
    _tb_id=$(printf '%s' "$VS_ROW" | jq -r '.id // ""' 2>/dev/null || true)
    case "$_tb_kind" in
        gate"$TAB"*)
            if ! _tb_waiters=$(gate_waiters "$_tb_id"); then
                echo "$PROG: $_tb_verb: could not read the beads that wait on gate $_tb_id ('gc bd dep list $_tb_id --direction=up --type blocks' did not answer). $_tb_nothing" >&2
                exit 4
            fi
            _tb_open=$(printf '%s' "$_tb_waiters" | jq -r '[ .[] | select(((.status // "open") | tostring | ascii_downcase) != "closed") | .id // empty ] | join(" ")')
            _tb_closed=$(printf '%s' "$_tb_waiters" | jq -r '[ .[] | select(((.status // "open") | tostring | ascii_downcase) == "closed") | .id // empty ] | join(" ")')
            _tb_take=""
            if [ -n "$_tb_from" ]; then
                case " $_tb_open " in
                    *" $_tb_from "*) _tb_take="$_tb_from" ;;
                    *)  # <from> does not wait on the gate itself. One that
                        # waited and has closed is not held by it. Any other is
                        # held only through another bead, when the read a list
                        # of its holds comes from (holding_rows) names the gate.
                        _tb_held=""
                        case " $_tb_closed " in
                            *" $_tb_from "*) ;;
                            *)  if ! _tb_holds=$(holding_rows "$_tb_from"); then
                                    echo "$PROG: $_tb_verb: $_tb_from does not wait on gate $_tb_id itself, and what holds $_tb_from could not be read, so whether the gate still holds it cannot be told. $_tb_nothing" >&2
                                    exit 4
                                fi
                                if printf '%s\n' "$_tb_holds" | awk -F'\t' -v g="$_tb_id" '$1 == "gate" && $2 == g { f = 1 } END { exit !f }'; then
                                    _tb_held=1
                                fi ;;
                        esac
                        if [ -z "$_tb_held" ]; then
                            echo "$PROG: $_tb_verb: $_tb_from does not wait on gate $_tb_id now${_tb_open:+ (the beads waiting on it are $_tb_open)}, so the gate is not $_tb_from's to answer. $_tb_nothing" >&2
                            exit 4
                        fi ;;
                esac
            fi
            # shellcheck disable=SC2086  # split the ids into positional parameters to count them
            set -- $_tb_open
            case $# in
                0)  echo "$PROG: $_tb_verb: nothing waits on gate $_tb_id${_tb_closed:+ (it was about $_tb_closed, now closed)}, so there is no bead for a conversation to be about. Clear the gate instead: gc bd gate resolve $_tb_id --reason \"moot: <why nothing waits on it>\". $_tb_nothing" >&2
                    exit 4 ;;
                1)  _tb_take="$1" ;;
                *)  if [ -z "$_tb_take" ]; then
                        case "$_tb_verb" in
                            open|engage|conversations)
                                if ! _tb_take=$(gate_pick "$_tb_id" "$@"); then
                                    echo "$PROG: $_tb_verb: gate $_tb_id holds $# beads ($_tb_open), and when each began waiting on it could not be read ('gc bd list --id' of them did not answer), so which one a conversation is about cannot be told. $_tb_nothing" >&2
                                    exit 4
                                fi
                                TAKE_PICKED=1 ;;
                            *)  echo "$PROG: $_tb_verb: gate $_tb_id is about $# beads still waiting on it ($_tb_open), and a conversation is about one bead. Name the one you mean: $PROG $_tb_verb <bead>. $_tb_nothing" >&2
                                exit 4 ;;
                        esac
                    fi
                    TAKE_OTHERS=$(printf '%s\n' "$@" | grep -vxF -e "$_tb_take" | LC_ALL=C sort | tr '\n' ' ')
                    TAKE_OTHERS="${TAKE_OTHERS% }" ;;
            esac
            TAKE_BEAD="$_tb_take"
            [ "${_tb_kind#gate"$TAB"}" = human ] && TAKE_GATE="$_tb_id" ;;
        conversation"$TAB"*)
            TAKE_BEAD="${_tb_kind#conversation"$TAB"}"; TAKE_CONV="$_tb_id" ;;
        *)
            TAKE_BEAD="$_tb_id" ;;
    esac
    [ -n "$TAKE_BEAD" ] || { echo "$PROG: $_tb_verb: could not tell which bead '$_tb_id' is about. $_tb_nothing" >&2; exit 4; }
}

# conversation_reply <conversation> <gate> — make the conversation reply to the
# gate it answers, bd's replies-to edge from the reply onto the original, which
# holds nothing. The gate can sit in another store, where bd stores an edge onto
# it without finding it, and the conversation's own `gc bd list` row keeps that
# edge, which `gc bd dep list` leaves out. bd takes an edge it already holds as
# a no-op that exits 0, so a re-run adds it safely. Returns the add's exit.
conversation_reply() {
    gc bd dep add "$1" "$2" --type replies-to >/dev/null 2>&1
}

# ── A conversation on an open PR holds the PR's merge ────────────────
# A conversation about an open PR, or about a bead of one such as its review or
# rework, holds the PR's merge until it closes, and otherwise blocks nothing.
# The hold is bd's own: the PR's anchor depends on the conversation through a
# `blocks` edge, so bd counts the anchor blocked while the conversation is open
# and lets it go once the conversation closes, by whatever route it closes, the
# sign-off, a dismiss, the premise re-check's moot or benign close or a close by
# hand, with nothing to release. The merge pass holds a PR while an open bead
# blocks its anchor. open adds the edge to a conversation it files or finds
# waiting in the operator's queue, and engage adds it whenever it starts a
# sitting, so a conversation filed before its PR opened, or one whose sitting
# lifted the hold, holds the merge again once it is engaged. A sitting that is
# helping the PR land, or whose conversation has nothing to do with whether it
# lands, lifts it with `gc bd dep remove <anchor> <conversation>`
# (skills/converse-hold), and the lift stands for that sitting: open, completing
# a conversation a sitting has taken, leaves the hold as that sitting left it.
# The edge holds only the anchor: a review, a rework or a supplement is a bead
# of its own that the anchor waits on, and goes on while the merge waits. Before
# a PR opens, the anchor is the work itself, which the edge would stop, so only
# an open PR's anchor takes one.

# subject_anchor <subject-row> — the anchor a conversation about the subject
# would hold the merge of: the subject itself when it is an anchor (it carries a
# merge_result), else the bead its anchor_bead names, as a PR's review, rework or
# supplement names it. Prints nothing for a subject that is neither. <row> is the
# subject's own row, as row_now prints it.
subject_anchor() {
    printf '%s' "$1" | jq -r '(.metadata // {}) as $m
        | if (($m.merge_result // "") | tostring) != "" then (.id // "") | tostring
          else ($m.anchor_bead // "") | tostring end' 2>/dev/null || true
}

# conversation_pr_anchor <subject-row> — the anchor whose merge a conversation
# about the subject holds: subject_anchor's, when that anchor is an open PR
# (merge_result pull_request, or pull_request_pending or
# pull_request_head_changed on the pending record, and not closed). Prints
# nothing when the subject is no open PR and no bead of one. Returns 1 when the
# anchor its anchor_bead names does not read, because a PR whose state cannot
# be read could be one the conversation must hold.
conversation_pr_anchor() {
    _cpa_id=$(printf '%s' "$1" | jq -r '(.id // "") | tostring' 2>/dev/null || true)
    _cpa_anchor=$(subject_anchor "$1")
    [ -n "$_cpa_anchor" ] || return 0
    if [ "$_cpa_anchor" = "$_cpa_id" ]; then
        _cpa_row="$1"
    else
        _cpa_row=$(row_now "$_cpa_anchor")
        [ -n "$_cpa_row" ] || return 1
    fi
    printf '%s' "$_cpa_row" | jq -r '
        if (((.metadata // {}).merge_result // "") as $mr
              | $mr == "pull_request" or $mr == "pull_request_pending" or $mr == "pull_request_head_changed")
           and ((.status // "") | tostring | ascii_downcase) != "closed"
        then (.id // "") | tostring else empty end' 2>/dev/null || true
}

# conversation_hold_merge <verb> <conversation> <anchor> — hold the merge of the
# open PR whose anchor is <anchor> until the conversation closes: the anchor
# depends on the conversation through bd's `blocks` edge. bd takes an edge it
# already holds as a no-op that exits 0, so a re-run, or a sitting started on a
# conversation that holds the merge already, adds it safely. Returns 0 once the
# edge is in place. Otherwise it says on stderr how to add it by hand and returns
# 1, because the PR can then merge while the conversation is open.
conversation_hold_merge() {
    _chm_verb="$1"; _chm_conv="$2"; _chm_anchor="$3"
    if ! gc bd dep add "$_chm_anchor" "$_chm_conv" --type blocks >/dev/null 2>&1; then
        echo "$PROG: $_chm_verb: conversation $_chm_conv is open on the PR of $_chm_anchor, but the store refused the edge that holds that PR's merge, so the PR can merge while the conversation is open. Add it by hand: gc bd dep add $_chm_anchor $_chm_conv --type blocks" >&2
        return 1
    fi
    echo "$PROG: $_chm_verb: conversation $_chm_conv holds the merge of the PR of $_chm_anchor until it closes" >&2
    return 0
}

# open_edges <conversation> <where> — the edges open owes a conversation it
# filed or joined: the hold on the merge of the open PR whose anchor is
# $open_anchor, then the reply onto the gate it answers, $TAKE_GATE. Each is
# empty for none. A conversation a sitting has taken out of the queue, the
# sitting $open_sitting names, owes open no hold: engage holds the merge when it
# starts a sitting, and from then on the hold is that sitting's to keep or lift
# (skills/converse-hold). Each edge is written whatever the other's outcome, so
# a reply the store refuses never leaves the PR free to merge while the
# conversation is open, and a hold it refuses never costs the reply. <where>
# says where the conversation stands, for the reply's refusal. Returns 0 once
# each edge it owes is in place, else 1, having said on stderr how to add each
# refused edge by hand.
open_edges() {
    _oe_rc=0
    if [ -n "$open_anchor" ] && [ -n "$open_sitting" ]; then
        echo "$PROG: open: the sitting $open_sitting has taken conversation $1 out of the queue, so the hold on the merge of the PR of $open_anchor stays as that sitting left it" >&2
    elif [ -n "$open_anchor" ]; then
        conversation_hold_merge open "$1" "$open_anchor" || _oe_rc=1
    fi
    if [ -n "$TAKE_GATE" ] && ! conversation_reply "$1" "$TAKE_GATE"; then
        echo "$PROG: open: conversation $1 $2, but the store refused its reply onto gate $TAKE_GATE. Add it by hand: gc bd dep add $1 $TAKE_GATE --type replies-to" >&2
        _oe_rc=1
    fi
    return "$_oe_rc"
}

# open_join <conversation> — join open's concern ($join_concern, empty for none)
# and the sentence naming the other open beads the gate holds ($open_others,
# empty for none) to a conversation waiting in the operator's queue, assigned to
# `human` and open, which is where a sitting claims it and reads its notes. What
# the conversation does not carry yet is appended in one note, in a write
# guarded on that queue state, so a conversation a sitting took or a dismiss
# closed after open's listing takes no note, and the write's exit says whether
# the note landed. The conversation then takes the hold on an open PR's merge
# and the reply onto a pointed gate (open_edges). The row is then read to tell
# that it still waits in the queue. Returns 0 once it does; 1 when the
# conversation is no longer in the queue, so it cannot receive the note and the
# caller moves on to the next one; and 2 when a write or that read failed,
# which it says on stderr.
open_join() {
    _oj_c="$1"; _oj_ask="${open_body:-$open_reason}"; _oj_note=""
    _oj_queued='((.assignee // "") | tostring) == "human" and ((.status // "") | tostring | ascii_downcase) == "open"'
    if [ -n "$join_concern$open_others" ]; then
        _oj_row=$(row_now "$_oj_c")
        if [ -n "$_oj_row" ] && ! printf '%s' "$_oj_row" | jq -e "$_oj_queued" >/dev/null 2>&1; then
            return 1
        fi
        # The concern and the sentence are each written unless the
        # conversation carries it already, and each is checked on its own: the
        # concern is carried when it is the conversation's own ask or a note an
        # earlier join appended, and the sentence when the conversation holds
        # it (conversation_carries). So a conversation whose ask is this very
        # question still takes the beads the gate holds, and a caller that asks
        # again on every pass while its condition stands, as deferred
        # dispatch's capped arm does, does not grow the notes by a copy a pass.
        # A row that does not read proves nothing, so both are written and the
        # guarded write decides.
        _oj_what="the note naming the other beads gate $TAKE_GATE holds"
        if [ -n "$join_concern" ] && ! printf '%s' "$_oj_row" | jq -e --arg ask "$_oj_ask" --arg n "$join_concern" \
                '((.description // "") == $ask) or ((.notes // "") | contains($n))' >/dev/null 2>&1; then
            _oj_note="$join_concern"; _oj_what="the new concern"
        fi
        if [ -n "$open_others" ] && ! conversation_carries "$_oj_row" "$open_others"; then
            _oj_note="${_oj_note:+$_oj_note

}$open_others"
        fi
        if [ -n "$_oj_note" ]; then
            _oj_rc=0
            gc bd update "$_oj_c" --if-assignee human --if-status open --append-notes "$_oj_note" >/dev/null 2>&1 || _oj_rc=$?
            case "$_oj_rc" in
                0) ;;
                13) return 1 ;;
                *) echo "$PROG: open: could not append $_oj_what to conversation $_oj_c's notes (gc bd update exited $_oj_rc), so it did not join and nothing records it. Re-run once the store answers: $PROG open $bead" >&2
                   return 2 ;;
            esac
        fi
    fi
    open_edges "$_oj_c" "waits in the queue for $bead" || return 2
    _oj_back=$(row_now "$_oj_c")
    if [ -z "$_oj_back" ]; then
        echo "$PROG: open: conversation $_oj_c could not be read after open joined it, so whether it still waits in the queue${_oj_note:+ carrying the note open appended} cannot be told. Re-run once the store answers: $PROG open $bead" >&2
        return 2
    fi
    printf '%s' "$_oj_back" | jq -e "$_oj_queued" >/dev/null 2>&1 || return 1
    return 0
}

# open_handoff <subject> <subject-row> — hand a subject create_subject filed to
# the conversation that now tracks it. create_subject files the subject open,
# assigned to `human` and carrying gc.origin=operator, so no first reaction
# can start on it before its conversation exists. Once one does, the open
# conversation keeps a first reaction off the subject, and the assignee goes in
# one write, guarded on that status and assignee, so a claim or a close that
# lands after open read the subject refuses the write and leaves the bead to
# it. A conversation is the only other bead assigned to `human`, and open never
# files one about a conversation, so the row as open read it tells this
# subject from any other, which open leaves as it is. Returns 1 when the store
# refuses the write, which it says on stderr: the subject then stays assigned
# to `human`, which keeps every first reaction off it, and a re-run of open
# finds the conversation and hands the subject to it.
open_handoff() {
    printf '%s' "$2" | jq -e '
        ((.status // "") | tostring) == "open"
        and ((.assignee // "") | tostring) == "human"
        and (((.metadata // {})["gc.origin"] // "") | tostring) == "operator"' >/dev/null 2>&1 || return 0
    _oh_rc=0
    gc bd update "$1" --if-status open --if-assignee human --assignee "" >/dev/null 2>&1 || _oh_rc=$?
    case "$_oh_rc" in
        0|13) return 0 ;;
        *) echo "$PROG: open: conversation $CONV tracks $1, but the store refused the write that hands $1 to it (gc bd update exited $_oh_rc), so $1 stays assigned to human, which keeps every first reaction off it. Re-run once the store answers, which hands it over: $PROG open $1" >&2
           return 1 ;;
    esac
}

# ── Verb: open ───────────────────────────────────────────────────────
# File a CONVERSATION about the bead in the operator's queue: an ordinary task
# that tracks the bead, assigned to `human`, holding no session until the
# operator engages it. The bead must RESOLVE first so a typo cannot manufacture
# one. A human gate names a bead still waiting on it, and the conversation
# replies to that gate. Of several open beads waiting, it names the one --from
# names, or else the one that has waited longest (gate_pick), and a note on the
# conversation names the others, filed with a conversation open files and
# appended once to one it lands on, so its sitting sees each bead the answer
# reaches. With no --reason or --body, the ask is what the gate asks.
# Without --allow-duplicate, a concern on a
# bead whose conversation already waits in the queue joins it (open_join): the
# reason and body are appended to that task's notes, once, so a concern the
# conversation already carries writes nothing. One that leaves the queue
# before the join is written, or by the time open reads it after the join, is
# passed over for the next one waiting there, or for a conversation open files,
# and a join the store refuses, or a read after it that does not answer, fails
# the open. --allow-duplicate files the concern as a conversation of its own,
# unless a conversation waiting in the queue already holds it as its whole ask:
# open then lands on that one, so a run again after a run that filed the
# conversation and failed completes it rather than file a second. Once the
# conversation is filed, --json names it before the reply onto the gate is
# written, so a reply the store refuses, or a run killed while the reply stalls,
# still names it. --reason is the title, --body the ask
# the sitting reads when it claims the conversation — callers with their own
# origin (operator-intake.sh) pass both rather than misreporting the board
# wording. The conversation is filed in the bead's own store. A conversation
# about an open PR, filed or joined, holds the PR's merge until it closes
# (conversation_hold_merge). It leaves the conversation's id in CONV and
# OPEN_FILED at 1 when the conversation holds the concern as its ask, or 0 when
# the concern joined one already in the queue, for engage, which runs it in its
# own shell.
# Engage sets OPEN_GATE_FROM to the bead it settled on, so a gate several beads
# wait on files the conversation about that bead, as engage took it (take_bead).
# --new-subject files the subject first, in the --rig rig (create_subject): the
# positional text, or --reason without one, is the question it is about, and the
# conversation's ask. Such a subject is filed assigned to `human`, and once a
# conversation about it is filed or joined, open hands the subject to that
# conversation (open_handoff), whichever open run gets there, a re-run onto the
# subject included. With --json, open answers the subject the moment it is
# filed, before any read that can stall, so a caller that stops waiting, as the
# conversation form does at its deadline, still knows the subject, and the last
# answer open prints is the one that counts. A subject filed whose conversation
# then is not is named on stderr as well, for a re-run onto it.
# --if-subject names the subject the caller showed before it asked, as the
# conversation form does: a reference that names any other bead by the time open
# resolves it, along a disposition, to a PR's anchor or to a gate's waiter, files
# nothing and exits 4.
# --conversation names the conversation an earlier open filed for this concern
# and did not complete, as the form's save again does with the id that open's
# --json answered. open lands on that conversation and completes it where it
# stands, whatever sitting has taken it since, adding the reply onto the gate
# that did not land, and files nothing. It holds an open PR's merge only while
# the conversation still waits in the queue, because a sitting that has taken it
# keeps or lifts that hold. A conversation that is no longer an open
# conversation about the bead, or that holds another ask, files nothing and
# exits 4.
# --from names the bead the reference was reached from, as the conversation form
# names the subject whose holds listed the gate it files through: a gate several
# open beads wait on files the conversation about that bead while it is one of
# them, as OPEN_GATE_FROM does for engage. A gate that holds the bead only
# through another bead, such as its rework, is taken as it is without --from,
# and one that no longer holds it files nothing (take_bead).
OPEN_GATE_FROM=""
_open_new_subject_bead=""
open_new_subject_report() {
    _onsr_rc=$?
    [ -n "$_open_new_subject_bead" ] || return "$_onsr_rc"
    trap - EXIT
    echo "$PROG: open: subject $_open_new_subject_bead was filed, but its conversation was not. It stays assigned to human until one is, so no first reaction takes it up. File it onto the subject, not as a new one: $PROG open $_open_new_subject_bead --reason \"<the question>\"" >&2
    return "$_onsr_rc"
}
cmd_open() {
    bead=""; open_reason=""; open_body=""; open_allow_dup=""; open_json=""; OPEN_FILED=""
    open_new_subject=0; open_rig=""; open_if_subject=""; open_conv=""; open_from=""; open_sitting=""; open_subject_row=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --new-subject) open_new_subject=1; shift ;;
            --from=*)   open_from="${1#--from=}"; shift ;;
            --from)     shift; [ $# -gt 0 ] || { echo "$PROG: open: --from requires a value" >&2; exit 2; }
                        open_from="$1"; shift ;;
            --if-subject=*) open_if_subject="${1#--if-subject=}"; shift ;;
            --if-subject) shift; [ $# -gt 0 ] || { echo "$PROG: open: --if-subject requires a value" >&2; exit 2; }
                        open_if_subject="$1"; shift ;;
            --conversation=*) open_conv="${1#--conversation=}"; shift ;;
            --conversation) shift; [ $# -gt 0 ] || { echo "$PROG: open: --conversation requires a value" >&2; exit 2; }
                        open_conv="$1"; shift ;;
            --rig=*)    open_rig="${1#--rig=}"; shift ;;
            --rig)      shift; [ $# -gt 0 ] || { echo "$PROG: open: --rig requires a value" >&2; exit 2; }
                        open_rig="$1"; shift ;;
            --reason=*) open_reason="${1#--reason=}"; shift ;;
            --reason)   shift; [ $# -gt 0 ] || { echo "$PROG: open: --reason requires a value" >&2; exit 2; }
                        open_reason="$1"; shift ;;
            --body=*)   open_body="${1#--body=}"; shift ;;
            --body)     shift; [ $# -gt 0 ] || { echo "$PROG: open: --body requires a value" >&2; exit 2; }
                        open_body="$1"; shift ;;
            --allow-duplicate) open_allow_dup=1; shift ;;
            --json)     open_json=1; shift ;;
            -h|--help)  usage; exit 0 ;;
            -*) echo "$PROG: open: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: open takes one bead-id" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done
    if [ -n "$open_rig" ] && [ "$open_new_subject" = 0 ]; then
        echo "$PROG: open: --rig applies only with --new-subject; an existing subject's rig is derived from its id." >&2
        exit 2
    fi
    if [ -n "$open_if_subject" ] && [ "$open_new_subject" = 1 ]; then
        echo "$PROG: open: --if-subject names an existing subject the reference must still name, and --new-subject files a new one; pass only one." >&2
        exit 2
    fi
    if [ -n "$open_conv" ] && [ "$open_new_subject" = 1 ]; then
        echo "$PROG: open: --conversation completes a conversation an earlier open filed on its subject, and --new-subject files a new subject; pass the subject that open filed instead." >&2
        exit 2
    fi
    if [ -n "$open_from" ] && [ "$open_new_subject" = 1 ]; then
        echo "$PROG: open: --from names the bead a gate was reached from, and --new-subject files a new subject; pass only one." >&2
        exit 2
    fi
    if [ "$open_new_subject" = 1 ]; then
        _open_text="${bead:-$open_reason}"
        create_subject open "$open_rig" "$_open_text"
        [ -n "$open_reason$open_body" ] || open_reason="$_open_text"
        _open_new_subject_bead="$bead"
        trap 'open_new_subject_report' EXIT
        # A run killed at its caller's deadline runs no trap, so the subject is
        # answered now, ahead of the reads below. The answer open ends with,
        # when it gets there, comes after this one.
        [ -z "$open_json" ] || jq -nc --arg s "$bead" '{subject: $s, conversation: "", filed: false}'
    fi
    case "$bead" in "") echo "$PROG: open needs <bead-id>" >&2; usage; exit 2 ;; esac

    # Resolve a PR reference or a settled disposition to the live owning bead
    # BEFORE the rig is derived from the id prefix (a PR number has none).
    open_ref="$bead"
    resolve_live_subject "$bead"
    bead="$RESOLVED_SUBJECT"

    # Pin bd at the bead's rig (cross-rig filing) and export its rig as GC_RIG
    # so the conversation is filed in the subject's store and the board gathers
    # it there.
    open_pin() {
        path=$(rig_path_for_bead "$1")
        [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"
        rig=$(rig_name_for_bead "$1")
        [ -n "$rig" ] && export GC_RIG="$rig"
        return 0
    }
    open_pin "$bead"

    # The subject must EXIST before anything is filed: fail CLOSED on every
    # unhappy reading — the alternative is filing a conversation on an
    # unverified subject. verify_subject is the shared resolve+classify that
    # tells a data-plane outage apart from a genuine not-found.
    # >>> open-subject-exists
    verify_subject "$bead" open "No conversation filed." || exit $?
    # <<< open-subject-exists
    # A gate or a conversation id names the bead the conversation is about. A
    # gate that holds other open beads as well has them named to the sitting,
    # in a note on the conversation open files or lands on.
    take_bead open "No conversation filed." "${open_from:-$OPEN_GATE_FROM}"
    open_others=$(gate_others_line)
    if [ "$TAKE_BEAD" != "$bead" ]; then
        open_what=gate; [ -n "$TAKE_CONV" ] && open_what=conversation
        if [ -n "$TAKE_PICKED" ]; then
            # shellcheck disable=SC2086  # one word per bead
            echo "$PROG: open: $bead is a gate about $TAKE_BEAD and $(words_and $TAKE_OTHERS) — the conversation is about $TAKE_BEAD, which has waited on it longest" >&2
        else
            echo "$PROG: open: $bead is a $open_what about $TAKE_BEAD — the conversation is about $TAKE_BEAD" >&2
        fi
        bead="$TAKE_BEAD"
        open_pin "$bead"
        verify_subject "$bead" open "No conversation filed." || exit $?
    fi
    # --if-subject is the subject the caller showed before it asked: a reference
    # that names another bead now, through a successor, a PR's anchor or a gate's
    # waiter, files nothing, so a question never lands where its asker did not see
    # it going.
    if [ -n "$open_if_subject" ] && [ "$bead" != "$open_if_subject" ]; then
        echo "$PROG: open: $open_ref names $bead in rig ${rig:-?} now, not $open_if_subject (--if-subject). No conversation filed." >&2
        exit 4
    fi
    subject_clean="$VS_PAYLOAD"
    open_subject_row="$VS_ROW"

    # A DONE-band row is a finished item, not open work. Filing a fresh
    # conversation on a closed subject is how a settled question gets
    # re-engaged as a new ask. A superseded predecessor was already redirected
    # to its live successor above, so a closed subject here is genuinely
    # settled — refuse it rather than promote a glance into a conversation.
    # >>> open-subject-closed
    subject_status=$(printf '%s' "$subject_clean" \
        | jq -r --arg b "$bead" \
            'if type == "array"
             then (first(.[] | objects | select((.id // "") == $b)) | .status // "")
             else "" end' 2>/dev/null || true)
    if [ "$subject_status" = "closed" ]; then
        echo "$PROG: open: $bead is closed — a settled item on the DONE band, not open work. No conversation filed. To act on it, re-open the bead or file fresh work; a closed row is not a pick." >&2
        exit 4
    fi
    # <<< open-subject-closed

    # A conversation about an open PR, or about a bead of one such as its
    # review or rework, holds the PR's merge from the moment it is filed until
    # it closes. Which PR is read before anything is written, so a read that
    # does not answer files nothing rather than a conversation that holds no
    # merge.
    if ! open_anchor=$(conversation_pr_anchor "$VS_ROW"); then
        echo "$PROG: open: could not read $(subject_anchor "$VS_ROW"), the anchor $bead names, so whether the conversation must hold an open PR's merge cannot be told. No conversation filed." >&2
        exit 4
    fi

    if ! open_convs=$(bead_conversations "$bead"); then
        echo "$PROG: open: could not read the conversations on $bead ('gc bd dep list $bead --direction=up --type tracks', or 'gc bd list --id' of the tasks it names, did not answer). No conversation filed." >&2
        exit 4
    fi

    # Already waiting in the queue? A second concern joins the conversation
    # the operator has not taken up yet, so a double click files one, not two.
    # --allow-duplicate skips the join: engage passes it for a concern of its
    # own, which is a distinct dialogue even when the bead has one. So does
    # --conversation, which names the conversation that holds the concern.
    if [ -z "$open_allow_dup" ] && [ -z "$open_conv" ]; then
        join_concern=""
        if [ -n "$open_reason$open_body" ]; then
            join_concern="Another concern joined this conversation: ${open_reason:-$open_body}"
            if [ -n "$open_reason" ] && [ -n "$open_body" ]; then
                join_concern="$join_concern

$open_body"
            fi
        fi
        # A conversation that left the queue while open joined it is passed
        # over, and the bead's conversations are read again, so open joins the
        # next one waiting there or files one below. Each one passed over stays
        # passed over, so the loop ends.
        join_left=""
        while :; do
            existing=$(printf '%s' "$open_convs" | jq -r --arg left "$join_left" '
                ($left | split(" ")) as $l
                | [ .[] | select(((.assignee // "") | tostring) == "human")
                        | select(((.status // "open") | tostring) == "open")
                        | select(((.id // "") | tostring) as $i | any($l[]; . == $i) | not) ]
                | sort_by(.created_at // "") | (first // {}) | .id // empty' 2>/dev/null || true)
            [ -n "$existing" ] || break
            join_rc=0; open_join "$existing" || join_rc=$?
            case "$join_rc" in
                0) ;;
                1) join_left="${join_left:+$join_left }$existing"
                   if ! open_convs=$(bead_conversations "$bead"); then
                       echo "$PROG: open: conversation $existing left the operator's queue while open joined it, and the conversations on $bead could not be read again to find another. No conversation joined or filed; re-run once the store answers: $PROG open $bead" >&2
                       exit 4
                   fi
                   continue ;;
                *) exit 4 ;;
            esac
            CONV="$existing"; OPEN_FILED=0
            bust_cache
            if [ -n "$open_json" ]; then
                jq -nc --arg s "$bead" --arg c "$existing" '{subject: $s, conversation: $c, filed: false}'
            else
                echo "$PROG: conversation $existing is already open for $bead — waiting in the operator's queue until an operator engages it."
                echo "       Engage it when ready: $PROG engage $bead"
            fi
            open_handoff "$bead" "$open_subject_row" || exit 4
            return 0
        done
    fi

    # What this conversation is ABOUT, in the caller's words, or the gate it
    # answers: its title is the concern, and its description the ask.
    gate_title=""; gate_desc=""
    if [ -n "$TAKE_GATE" ]; then
        gate_row=$(row_now "$TAKE_GATE")
        gate_title=$(printf '%s' "$gate_row" | jq -r '.title // ""' 2>/dev/null || true)
        gate_desc=$(printf '%s' "$gate_row" | jq -r '.description // ""' 2>/dev/null || true)
    fi
    conv_title=$(conversation_title "${open_reason:-${gate_title:-operator pick from the board}}")
    if [ -n "$open_body" ]; then
        conv_body="$open_body"
    elif [ -n "$open_reason" ]; then
        conv_body="$open_reason"
    elif [ -n "$TAKE_GATE" ]; then
        conv_body="Answer the human gate $TAKE_GATE on $bead: ${gate_title:-its question}.${gate_desc:+

$gate_desc}"
    else
        conv_body="Operator picked $bead off the helm board: rebuild the subject's slice, prep, hold for the operator."
    fi

    # A concern of its own that a conversation waiting in the queue already
    # holds as its whole ask is that conversation's, and is not filed again. So
    # an open run again after a run that filed the conversation and then failed,
    # because the store refused its reply onto the gate or its answer was lost,
    # completes that conversation rather than file a second one for the concern.
    # A caller that holds the id of the conversation it filed names it with
    # --conversation, and open completes that one by its id. A sitting another
    # terminal started may have taken it out of the queue by then, and the reply
    # onto the gate holds nothing, so the reply is added all the same. The hold
    # on an open PR's merge is that sitting's to keep or lift by then
    # (skills/converse-hold), and a sitting that is helping the PR land lifts
    # it. So open adds the hold only to a conversation that its listing above
    # still finds in the queue, assigned to `human`, and open_sitting names the
    # sitting that has the conversation otherwise. The ask holds the question
    # alone (gate_others_line), so the match holds when the beads waiting on a
    # gate have changed since the conversation was filed, and the conversation
    # takes the sentence naming them as they stand now when it does not carry
    # it (conversation_note_others).
    CONV=""; open_again=0
    if [ -n "$open_conv" ]; then
        _oc_row=$(printf '%s' "$open_convs" | jq -c --arg c "$open_conv" \
            'first(.[] | select(((.id // "") | tostring) == $c)) // empty' 2>/dev/null || true)
        if [ -z "$_oc_row" ]; then
            echo "$PROG: open: conversation $open_conv is not an open conversation about $bead: it was closed since it was filed, or it is about another bead, so open cannot complete it. No conversation filed." >&2
            exit 4
        fi
        if ! printf '%s' "$_oc_row" | jq -e --arg ask "$conv_body" '((.description // "") | tostring) == $ask' >/dev/null 2>&1; then
            echo "$PROG: open: conversation $open_conv on $bead holds another ask than this concern, so open does not complete it with this one. No conversation filed." >&2
            exit 4
        fi
        CONV="$open_conv"; open_again=1
        open_sitting=$(printf '%s' "$_oc_row" | jq -r '(.assignee // "") | tostring | select(. != "human")' 2>/dev/null || true)
    elif [ -n "$open_allow_dup" ]; then
        CONV=$(printf '%s' "$open_convs" | jq -r --arg ask "$conv_body" '
            [ .[] | select(((.assignee // "") | tostring) == "human")
                  | select(((.status // "open") | tostring) == "open")
                  | select(((.description // "") | tostring) == $ask) ]
            | sort_by(.created_at // "") | (first // {}) | .id // empty' 2>/dev/null || true)
        [ -z "$CONV" ] || open_again=1
    fi

    # File the conversation: a task that tracks the bead, in the operator's
    # queue (assigned to `human`), in one create, so no reader ever sees a task
    # in this shape without its subject, nor one on a shared gate without the
    # note naming the other beads it holds. The tracks edge is what makes the
    # task a conversation about the bead, and the bead can sit in another store,
    # where bd stores the edge without finding its target and the task's own
    # `gc bd list` row still carries it.
    # bd create answers an ARRAY (or bare object) carrying the id on success and
    # a bare {"error":…} OBJECT on failure; the id is read type-guarded so an
    # error object never crashes jq.
    if [ "$open_again" = 0 ]; then
        CONV_RC=0
        CONV_JSON=$(gc bd create -t task --title "$conv_title" -d "$conv_body" ${open_others:+--notes "$open_others"} \
            --deps "tracks:$bead" --assignee human --json 2>/dev/null) || CONV_RC=$?
        CONV=$(printf '%s' "$CONV_JSON" | scrub \
            | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null || true)
        [ "$CONV" != "null" ] || CONV=""
        [ "$CONV_RC" = 0 ] && [ -n "$CONV" ] \
            || { create_err=$(printf '%s' "$CONV_JSON" | scrub | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null || true)
                 echo "$PROG: open: could not create a conversation for '$bead'${create_err:+: $create_err}" >&2; exit 4; }
    fi
    # From here the conversation is filed and holds the concern, so --json
    # answers it now, ahead of its hold on an open PR's merge and its reply onto
    # the gate (open_edges), which can stall. A run
    # killed at its caller's deadline runs no trap and prints nothing more, and
    # a caller that saves again names this conversation with --conversation.
    # Every exit after this answers the same, so it is the last answer open
    # prints.
    OPEN_FILED=1
    if [ -n "$_open_new_subject_bead" ]; then
        _open_new_subject_bead=""
        trap - EXIT
    fi
    [ -z "$open_json" ] || jq -nc --arg s "$bead" --arg c "$CONV" '{subject: $s, conversation: $c, filed: true}'
    bust_cache
    open_edges "$CONV" "is filed on $bead" || exit 4
    [ "$open_again" = 0 ] || conversation_note_others open "$CONV" "$open_others" "$TAKE_GATE"
    open_handoff "$bead" "$open_subject_row" || exit 4

    # One sentence reports a conversation that holds the concern, filed by this
    # open or by an earlier one, and it is the sentence helm-svc's board reads
    # as filed (parseOpenStdout, which open_parity_test.go pins to these
    # echoes). Its tail says where the conversation stands.
    if [ -z "$open_json" ]; then
        open_stands="waiting in the operator's queue; no session spawned."
        open_next="Engage it when ready: $PROG engage $bead"
        if [ -n "$open_sitting" ]; then
            open_stands="the sitting $open_sitting has taken it out of the operator's queue."
            open_next="Return to it: $PROG attach $CONV"
        fi
        echo "$PROG: conversation $CONV filed on $bead — $open_stands"
        echo "       $open_next"
    fi
}

# ── The current sitting, inferred from session state ─────────────────
# current_sitting — the conversation THIS session holds, for a bare
# `gc-helm dismiss`: the one open or in-progress conversation
# ($CONVERSATION_JQ) whose assignee is one of this session's identities. Read
# from this session's own rig store: a conversation is filed in its subject's
# store, and a converse session runs with GC_RIG and BEADS_DIR unset and so
# defaults to the city store, where a rig-filed conversation is absent;
# rig_db_for_session resolves the rig and the pin below reads it.
#
# Sets SITTING_CONV and SITTING_SUBJECT on success (called directly, not in a
# subshell). It fails CLOSED, naming the explicit-id form as the fix: no
# identity, no held conversation, or more than one exit 2 (the operator must
# say which); a listing that failed, did not answer a JSON array, or would not
# parse exits 4 — a read that did not answer is a runtime fault, not a usage
# error, and never proof of no sitting. An argument-free verb that guessed the
# wrong conversation would end the wrong sitting, which is the one failure
# this inference exists to prevent.
SITTING_CONV=""; SITTING_SUBJECT=""
current_sitting() {
    _me=$(session_identities)
    if [ -z "$_me" ]; then
        echo "$PROG: no session identity in the environment (GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS all unset); there is no sitting to infer. Name the subject: $PROG dismiss <bead-id>." >&2
        return 2
    fi
    # Pin the lookup at THIS session's rig store. An unresolved rig leaves the
    # caller default in place, so this never fails the inference outright.
    _vdb=$(rig_db_for_session)
    [ -n "$_vdb" ] && export BEADS_DIR="$_vdb"
    if ! _vjson=$(bd_rows list --status=open,in_progress --limit=0); then
        echo "$PROG: could not read this session's conversations — 'gc bd list' failed or did not answer a JSON array. Name the subject: $PROG dismiss <bead-id>." >&2
        return 4
    fi
    # One jq pass: the held conversations, each as "<id> <subject>". A jq
    # failure here is a listing this verb cannot read, not an empty sitting.
    _held=$(printf '%s' "$_vjson" | jq -r --arg ids "$_me" "$CONVERSATION_JQ"'
        ($ids | split("\n") | map(select(. != ""))) as $me
        | [ .[] | objects | select(conversation) | . as $c
            | select(($me | index(($c.assignee // "") | tostring)) != null)
            | "\(.id) \(conversation_subjects[0])" ]
        | unique | .[]' 2>/dev/null) || {
        echo "$PROG: could not read this session's conversations — 'gc bd list' answered nothing this verb could parse. Name the subject: $PROG dismiss <bead-id>." >&2
        return 4
    }
    if [ -z "$_held" ]; then
        echo "$PROG: no open conversation is assigned to this session ($(printf '%s' "$_me" | tr '\n' ' ')); there is no current sitting. Name the subject: $PROG dismiss <bead-id>." >&2
        return 2
    fi
    if [ "$(printf '%s\n' "$_held" | wc -l | tr -d ' ')" -gt 1 ]; then
        echo "$PROG: this session holds more than one open conversation ($(printf '%s' "$_held" | cut -d' ' -f1 | tr '\n' ' ')); refusing to guess which sitting. Name one: $PROG dismiss <conversation-id>." >&2
        return 2
    fi
    SITTING_CONV="${_held%% *}"
    SITTING_SUBJECT="${_held#* }"
}

# ── Verb: handback ───────────────────────────────────────────────────
# A converse sitting records each hand-back it posts, every framing and the
# sign-off, on its CONVERSATION. The text arrives on stdin and replaces the one
# recorded before, so the conversation carries the sitting's latest words. engage's
# attach path prints them once the sitting's session has ended and the
# operator's tab is back at a shell, where nothing of the pane survives. The
# takeaway is the subject's one-line headline; this is the hand-back whole.
# gc.handback and gc.handback_at land in one write, whose exit says whether they
# landed.
cmd_handback() {
    bead=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -*) echo "$PROG: handback: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: handback takes one conversation id" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done
    [ -n "$bead" ] || { echo "$PROG: handback needs <conversation-id>, with the hand-back on stdin" >&2; usage; exit 2; }
    handback_text=$(cat)
    if [ -z "$(printf '%s' "$handback_text" | tr -d '[:space:]')" ]; then
        echo "$PROG: handback: stdin carried no hand-back, so nothing was recorded on $bead. Pipe in the hand-back as it is posted." >&2
        exit 2
    fi
    verify_subject "$bead" handback "Nothing was recorded." || exit $?
    take_bead handback "Nothing was recorded."
    if [ "$TAKE_CONV" != "$bead" ]; then
        echo "$PROG: handback: $bead is not a conversation, and a hand-back is recorded on the conversation its sitting holds. Nothing was recorded." >&2
        exit 2
    fi
    path=$(rig_path_for_bead "$bead")
    db=""; [ -n "$path" ] && [ -d "$path/.beads" ] && db="$path/.beads"
    handback_at=$(iso_now)
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    if ! gc bd update "$bead" ${db:+--db "$db"} --set-metadata "gc.handback=$handback_text" \
        --set-metadata "gc.handback_at=$handback_at" >/dev/null 2>&1; then
        echo "$PROG: handback: the store refused the hand-back on $bead, so its tab would print an older one, or none. Re-run it." >&2
        exit 4
    fi
    echo "$PROG: handback: recorded on $bead at $handback_at"
    # Once the conversation has closed, its hand-back is the visit's conclusion,
    # which the comment that shows the visit on the subject's PR carries, so the
    # comment is drawn again. Best effort, never failing the record.
    if [ -x "$SITTING_COMMENT_TOOL" ] \
        && [ "$(row_now "$bead" | jq -r '(.status // "") | ascii_downcase' 2>/dev/null)" = closed ]; then
        "$SITTING_COMMENT_TOOL" refresh --sitting "$bead" || true
    fi
}

# sitting_session_of <conversation-row> — the live converse session holding a
# conversation, as the store's session list (session_list_from_store) holds it,
# printed as "<session-id> own" when it is the session this verb runs in and
# "<session-id> other" when it is not, else nothing. The holder is the session
# the conversation's gc.session_id names, else the one its gc.session_name or
# assignee names: the claim stamps both pins, and a bind the sitting never
# claimed leaves the assignee alone. Only a converse template counts, so a bead
# some other agent holds never stops that agent, and a listing that will not
# read names nobody.
sitting_session_of() {
    _sso_sid=$(printf '%s' "$1" | jq -r '(.metadata // {})["gc.session_id"] // ""' 2>/dev/null || true)
    _sso_sn=$(printf '%s' "$1" | jq -r '(.metadata // {})["gc.session_name"] // ""' 2>/dev/null || true)
    _sso_as=$(printf '%s' "$1" | jq -r '.assignee // ""' 2>/dev/null || true)
    [ -n "$_sso_sid$_sso_sn$_sso_as" ] || return 0
    session_list_from_store | scrub | jq -r \
        --arg id "$_sso_sid" --arg sn "$_sso_sn" --arg as "$_sso_as" --arg me "$(session_identities)" '
        ($me | split("\n") | map(select(. != ""))) as $mine
        | if type == "object" and ((.sessions // null) | type) == "array" then
            [ .sessions[] | objects
              | select((.closed // false) != true)
              | select((.template // "") | test("(^|[./])converse(-[^./]*)?$"))
              | select(($id != "" and (.id // "") == $id)
                       or ($sn != "" and (.session_name // "") == $sn)
                       or ($as != "" and ((.session_name // "") == $as or (.alias // "") == $as or (.id // "") == $as)))
              | select((.id // "") != "")
              | .id + " " + (if ([.id, .session_name, .alias] | map(select(. != null and . != "")) | any(. as $x | $mine | index($x) != null))
                             then "own" else "other" end) ]
            | first // empty
          else empty end' 2>/dev/null || true
}

# operator_drain_ack <session-id> — stop a session as the operator, from outside
# it, with `gc runtime drain-ack --operator`. Gas City refuses an operator ack
# whose caller's GC_SESSION_ID or GC_INSTANCE_TOKEN names the session it stops.
# A caller can carry both, because a run-shell job inherits the tmux
# environment of the session its key was pressed in, incarnation token
# included. So the ack runs with this process's session identity and token
# removed.
operator_drain_ack() {
    (
        unset GC_SESSION_ID GC_SESSION_NAME GC_ALIAS GC_INSTANCE_TOKEN
        gc runtime drain-ack --operator "$1"
    ) >/dev/null 2>&1
}

# ── Verb: dismiss ────────────────────────────────────────────────────
# The operator's explicit "end this sitting". converse runs with no
# idle_timeout, so a held conversation keeps its sitting up until something
# closes it; closing it here is the act that ends a sitting the operator no
# longer wants, and the verb then stops the session that held it, so the
# sitting does not outlive its conversation. Dismiss answers nothing: every
# human gate the conversation replies to stays open and owed, for its filer or
# the next sitting, and its replies stay as the record that this conversation
# took it up. It writes nothing to the subject.
#
# A bead names the conversations a live sitting holds on it, and a bead with no
# live sitting has nothing to end. A conversation id names its own
# conversation, which is closed whoever holds it, so the operator can retire
# one waiting in the queue. A conversation the verb could not account for
# aborts the run. Idempotent.
#
# The stop is `gc runtime drain-ack`, so the controller ends the session
# outside this process: a dismiss typed into the sitting's own pane is never
# killed half done. The session this verb runs in acks itself, last of all;
# any other is acked as an operator. Under --operator the caller is outside
# every sitting, whatever identity it runs under, so no session acks itself.
# Gas City holds that stop while a client is attached, so the pane stays live
# under the tab until the tab detaches, and the ack's drain flag puts "done"
# at the head of the tab's title (the converse templates' session_live). A
# session whose stop does not take holds no conversation any more, so its
# template's idle sleep stops it once no client is attached.
cmd_dismiss() {
    bead=""; dismiss_reason=""; dismiss_json=""; dismiss_stop=""; dismiss_operator=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason=*) dismiss_reason="${1#--reason=}"; shift ;;
            --reason)   shift; [ $# -gt 0 ] || { echo "$PROG: dismiss: --reason requires a value" >&2; exit 2; }
                        dismiss_reason="$1"; shift ;;
            --operator) dismiss_operator=1; shift ;;
            --json)     dismiss_json=1; shift ;;
            -h|--help)  usage; exit 0 ;;
            -*) echo "$PROG: dismiss: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: dismiss takes one bead-id" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done
    # In --json mode the one machine object is the only thing on stdout, so the
    # human progress lines print to stderr instead; otherwise they print as before.
    _dmsg() { if [ -n "$dismiss_json" ]; then echo "$@" >&2; else echo "$@"; fi; }
    _dwhy="dismissed by the operator${dismiss_reason:+: $dismiss_reason}"

    convs=""
    if [ -z "$bead" ]; then
        current_sitting || exit $?
        bead="$SITTING_SUBJECT"; convs="$SITTING_CONV"
        # The subject's rig checkout, which the visit's PR comment is drawn
        # from below. A rig list that does not answer costs only that drawing.
        path=$(rig_path_for_bead "$bead" 2>/dev/null) || path=""
        echo "$PROG: dismiss: no bead named; inferred the current sitting's conversation $SITTING_CONV on $bead from session state" >&2
    else
        resolve_live_subject "$bead"
        bead="$RESOLVED_SUBJECT"
        path=$(rig_path_for_bead "$bead")
        [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"
        # The bead must resolve before anything is written — the same
        # resolve+classify open uses, so a read that did not answer is reported
        # as a data-plane outage, not a missing bead.
        verify_subject "$bead" dismiss "Nothing was written." || exit $?
        take_bead dismiss "Nothing was written."
        if [ -n "$TAKE_CONV" ]; then
            convs="$TAKE_CONV"
            echo "$PROG: dismiss: $bead is a conversation on $TAKE_BEAD — closing it" >&2
        else
            if [ "$TAKE_BEAD" != "$bead" ]; then
                echo "$PROG: dismiss: $bead is a gate about $TAKE_BEAD — ending the sitting there" >&2
            fi
            # The conversations about the bead that a live sitting holds. A list
            # of either that did not answer proves no sitting live and none
            # gone, so it fails rather than reading as "nothing to end".
            if ! d_convs=$(bead_conversations "$TAKE_BEAD"); then
                echo "$PROG: dismiss: could not read the conversations on $TAKE_BEAD ('gc bd dep list', or 'gc bd list --id' of the tasks it names, did not answer). Nothing was written. Name the conversation to close it: $PROG dismiss <conversation-id>." >&2
                exit 4
            fi
            if ! d_live=$(live_sittings); then
                echo "$PROG: dismiss: could not read 'gc session list', so which sitting on $TAKE_BEAD is live cannot be told. Nothing was written. Name the conversation to close it: $PROG dismiss <conversation-id>." >&2
                exit 4
            fi
            convs=$(printf '%s' "$d_convs" | jq -r --argjson live "$d_live" "$CONVERSATION_JQ$SITTING_JQ"'
                [ .[] | select(held_live($live)) | .id ] | .[]' 2>/dev/null || true)
        fi
        bead="$TAKE_BEAD"
    fi

    matched=$(printf '%s\n' "$convs" | jq -Rsc '[ split("\n")[] | select(. != "") | {id: .} ]')
    if [ -z "$convs" ]; then
        if [ -n "$dismiss_json" ]; then
            jq -nc --arg s "$bead" '{subject: $s, matched: [], closed: 0, ok: true}'
        else
            echo "$PROG: dismiss: no live sitting on $bead — nothing to end"
        fi
        return 0
    fi

    # A held conversation is ASSIGNED to the sitting's alias, and bd's close
    # refuses a close by anyone but its holder. That refusal is exactly what this
    # verb overrides — the operator is the holder's audience, not its peer — so
    # it escalates to --force. Plain close first, so a conversation in the queue
    # never pays for the override and the forced case is a line the operator can
    # see. A close counts on its exit 0.
    sitting_failed=0; closed_n=0
    for _c in $convs; do
        # The work-record gate the close runs wants gc.work_outcome.
        # work-outcome.sh stamps it in a write of its own, so it never decides
        # whether the conversation closes.
        work_outcome_noop "$_c" gc bd
        # The session holding the conversation, read before the close, which
        # leaves the assignee and the claim's pins as they were. It is stopped
        # once the run's writes are done (dismiss_stop_sittings).
        _c_holder=$(sitting_session_of "$(row_now "$_c")")
        if gc bd close "$_c" --reason "$_dwhy" >/dev/null 2>&1; then
            _how="closed"
        elif gc bd close "$_c" --reason "$_dwhy" --force >/dev/null 2>&1; then
            _how="closed over its holder's claim"
        else
            _how=""
        fi
        if [ -n "$_how" ]; then
            closed_n=$((closed_n + 1))
            _dmsg "$PROG: dismiss: $_how conversation $_c — the sitting on $bead ends"
            # The dismissal is one of the visit's actions, recorded on the
            # conversation without the operator's reason, which is their own
            # words. The comment that shows the visit on the subject's PR is then
            # drawn again from the conversation, from the subject's rig checkout
            # when this run resolved it, because the comment's repository is the
            # origin of the checkout it runs in. Both are best effort and never
            # fail the dismiss, and a conversation whose sitting never named its
            # topic has no comment to draw.
            gc bd comment "$_c" "Dismissed by the operator." >/dev/null 2>&1 \
                || echo "$PROG: dismiss: the dismissal was not recorded on $_c, so the visit's comment on the PR will not list it" >&2
            if [ -x "$SITTING_COMMENT_TOOL" ]; then
                ( if [ -n "${path:-}" ] && [ -d "$path" ]; then cd "$path" || exit 0; fi
                  "$SITTING_COMMENT_TOOL" refresh --sitting "$_c" ) || true
            fi
        else
            sitting_failed=1
            echo "$PROG: dismiss: could not close conversation $_c; its sitting keeps the pane. Close it by hand: gc bd close $_c --force" >&2
        fi
        if [ -n "$_how" ]; then
            [ -n "$_c_holder" ] && dismiss_stop="${dismiss_stop:+$dismiss_stop
}$_c_holder"
        fi
    done

    # dismiss_stop_sittings — stop each session dismiss_stop names, the one this
    # verb runs in last, since a dismiss typed into a sitting's pane ends with
    # that pane. Under --operator none is the one this verb runs in.
    dismiss_stop_sittings() {
        _ds_own=""
        _ds_ifs=$IFS
        IFS='
'
        for _ds_line in $dismiss_stop; do
            _ds_id=${_ds_line%% *}
            if [ "${_ds_line#* }" = own ] && [ -z "$dismiss_operator" ]; then _ds_own=$_ds_id; continue; fi
            if operator_drain_ack "$_ds_id"; then
                _dmsg "$PROG: dismiss: stopped session $_ds_id, which held the sitting"
            else
                echo "$PROG: dismiss: could not stop session $_ds_id, which held the sitting; it holds no conversation now, so its idle sleep stops it once no client is attached" >&2
            fi
        done
        IFS=$_ds_ifs
        if [ -n "$_ds_own" ]; then
            _dmsg "$PROG: dismiss: ending this session ($_ds_own), which held the sitting"
            gc runtime drain-ack >/dev/null 2>&1 \
                || echo "$PROG: dismiss: could not end this session ($_ds_own); it holds no conversation now, so its idle sleep stops it once no client is attached" >&2
        fi
    }

    bust_cache
    if [ "$sitting_failed" -ne 0 ]; then
        [ -n "$dismiss_json" ] && jq -nc --arg s "$bead" --argjson m "$matched" --argjson c "$closed_n" \
            '{subject: $s, matched: $m, closed: $c, ok: false}'
        echo "$PROG: dismiss: $bead was NOT dismissed — a sitting is unaccounted for. Each conversation above says what it needs, and a re-run resumes from there." >&2
        dismiss_stop_sittings
        exit 4
    fi
    if [ -n "$dismiss_json" ]; then
        jq -nc --arg s "$bead" --argjson m "$matched" --argjson c "$closed_n" \
            '{subject: $s, matched: $m, closed: $c, ok: true}'
    fi
    dismiss_stop_sittings
    return 0
}

# city_root — the city's root: GC_CITY_PATH, GC_CITY or GC_CITY_ROOT when it is an
# absolute path holding .gc, else the path gc reports for the city's HQ rig.
# Prints nothing when none names one.
city_root() {
    for _cr_root in "${GC_CITY_PATH:-}" "${GC_CITY:-}" "${GC_CITY_ROOT:-}"; do
        case "$_cr_root" in
            /*) if [ -d "$_cr_root/.gc" ]; then printf '%s' "$_cr_root"; return 0; fi ;;
        esac
    done
    enumerate_rigs
    _cr_root=$(printf '%s' "$RIGS" | jq -r '[ .[] | objects | select(.hq == true) | .path // empty ] | first // empty' 2>/dev/null || true)
    if [ -n "$_cr_root" ] && [ -d "$_cr_root/.gc" ]; then
        printf '%s' "$_cr_root"
    fi
}

# ── engage: decision helpers ─────────────────────────────────────────
# What engage decides — the subject, the conversation, the starter, the model
# and the skill — resolved from durable state. None of them reads a terminal:
# on a terminal the conversation form gathers what the command line leaves open
# (helm_form), and reads what these read through `conversations`.

# engage_list_models — the converse-<model> tokens engage offers, one per line,
# claude-opus (the work tier) first. Enumerated from the agent dirs the
# templates live in, so the menu tracks what `gc session new converse-<model>`
# can resolve, less the templates kept only for the sittings already open on
# them (ENGAGE_WITHDRAWN_MODELS).
engage_list_models() {
    _elm_all=""
    for _elm_d in "$ENGAGE_AGENTS_DIR"/converse-*; do
        [ -d "$_elm_d" ] || continue
        _elm_m=$(basename "$_elm_d"); _elm_m=${_elm_m#converse-}
        [ -n "$_elm_m" ] || continue
        case " $ENGAGE_WITHDRAWN_MODELS " in *" $_elm_m "*) continue ;; esac
        _elm_all="$_elm_all $_elm_m"
    done
    # Two passes so claude-opus leads; `if` (not `&&`) keeps a false test from
    # making the final loop iteration — and so the function — return non-zero
    # under set -e.
    for _elm_m in $_elm_all; do
        if [ "$_elm_m" = claude-opus ]; then printf '%s\n' "$_elm_m"; fi
    done
    for _elm_m in $_elm_all; do
        if [ "$_elm_m" != claude-opus ]; then printf '%s\n' "$_elm_m"; fi
    done
}

# engage_valid_model <token> — 0 iff the token names a configured variant.
# Fails OPEN when the list cannot be enumerated (a broken pack), so engage never
# rejects a model it merely could not confirm; the spawn is the real gate then.
engage_valid_model() {
    _evm_list=$(engage_list_models)
    [ -n "$_evm_list" ] || return 0
    _evm_ok=1
    for _evm in $_evm_list; do
        if [ "$_evm" = "$1" ]; then _evm_ok=0; fi
    done
    return "$_evm_ok"
}

# engage_check_model — refuse, exit 2, an $engage_model that is not a configured
# variant, naming the variants.
engage_check_model() {
    engage_valid_model "$engage_model" && return 0
    echo "$PROG: engage: --model must be one of: $(engage_list_models | tr '\n' ' ' | sed 's/ *$//') (got '$engage_model')" >&2
    exit 2
}

# helm_gctk — the gctk binary the city builds: $GCTK_BIN, else the build under
# the city root. Prints nothing and returns 1 when there is none to run.
helm_gctk() {
    _hg_bin="${GCTK_BIN:-}"
    if [ -z "$_hg_bin" ]; then
        _hg_root=$(city_root)
        [ -n "$_hg_root" ] || return 1
        _hg_bin="$_hg_root/.gc/services/gctk/bin/gctk"
    fi
    [ -x "$_hg_bin" ] || return 1
    printf '%s' "$_hg_bin"
}

# holding_rows <bead> — what holds the bead, one "<held>\t<id>\t<title>" row
# each, in the order of the reasons `gctk pr status --json` gives: the
# definition the PR's held: labels and the board's row read, so what engage
# offers cannot differ from what they say. <held> is the held: value the row
# stands for. <id> is the bead to engage, an open human gate or a bead a person
# owes the next move on, and is empty where the PR's own review threads or blocked
# verdict hold it. Returns 1 when gctk is not there or did not answer, which says
# nothing about what holds the bead.
holding_rows() {
    _hr_bin=$(helm_gctk) || return 1
    _hr_json=$("$_hr_bin" pr status "$1" --json 2>/dev/null) || return 1
    printf '%s' "$_hr_json" | jq -r '.reasons[] | [.held, (.id // ""), (.title // "")] | @tsv' 2>/dev/null
}

# engage_warn_holds_unread <bead> — say that what holds the bead did not read,
# which leaves the operator to look for it. Engage goes on: a sitting on the bead
# can still be started. It writes to stdout, as engage_say_holds does, because
# stdout is all the board's route returns from an engage that exits 0.
engage_warn_holds_unread() {
    echo "$PROG: engage: could not read what holds $1 ('gctk pr status' did not answer), so nothing that holds it is offered."
}

# engage_say_holds <bead> — name each thing that holds the bead, and how to
# engage it, for an engage that asks nothing. A sitting on the bead does not
# answer a gate unless its conversation replies to it.
engage_say_holds() {
    if ! _esh_rows=$(holding_rows "$1"); then
        engage_warn_holds_unread "$1"
        return 0
    fi
    printf '%s\n' "$_esh_rows" | while IFS= read -r _esh_row; do
        [ -n "$_esh_row" ] || continue
        _esh_held=$(printf '%s' "$_esh_row" | cut -f1)
        _esh_id=$(printf '%s' "$_esh_row" | cut -f2)
        _esh_title=$(printf '%s' "$_esh_row" | cut -f3-)
        if [ -z "$_esh_id" ]; then
            echo "$PROG: engage: $1 is held (held: $_esh_held): $_esh_title"
        elif [ "$_esh_held" = gate ]; then
            echo "$PROG: engage: $1 is held by human gate $_esh_id (\"$_esh_title\"). To answer it: $PROG engage $_esh_id --from $1"
        else
            echo "$PROG: engage: $1 is held by $_esh_id (\"$_esh_title\"), which a person has to clear. To engage it: $PROG engage $_esh_id"
        fi
    done
}

# sitting_refusal <bead> <rig> <path> — 0 when a converse sitting can start on
# the bead in its rig; otherwise 1, with SITTING_REFUSAL saying why and naming
# the fix, which engage refuses with before it files anything.
# SITTING_SUSPENDED is true when the reason is the rig's suspension, which
# `conversations` reports to the form as rig_suspended rather than as its
# refusal, because a question can still be filed there and wait in the queue
# until the rig resumes. A rig that carries no converse template
# can host no converse sitting, and an HQ / city-store bead resolves to the city
# root, which carries none. A spawned converse sitting is launched and sustained
# by the RECONCILER, the city controller's loop — a converse slot sets nudge=""
# and idle_timeout=0, so no pool backstop cycles it. The reconciler skips a
# suspended rig's agents and does not run while the controller is down, so on
# either the sitting never comes up, and an engage would report success while
# the conversation sits bound to a session that never registers. A rig with no
# agents running is idle, not down, and the reconciler launches the sitting
# there like anywhere else. Both flags come from the `gc rig list`
# enumerate_rigs already read, and city_controller_state asks gc status before
# an HQ running=false counts (city-liveness.sh). A gc that reports neither flag
# leaves them empty, which reads as unknown and does not refuse.
SITTING_REFUSAL=""; SITTING_SUSPENDED=false
sitting_refusal() {
    SITTING_REFUSAL=""; SITTING_SUSPENDED=false
    if ! rig_carries_converse "$2"; then
        SITTING_REFUSAL="converse is not available for '$1': its rig '${2:-?}' ($3) carries no converse template. HQ/city-store beads are not converse-engageable. Nothing filed, nothing spawned."
        return 1
    fi
    if [ "$(rig_suspended "$2")" = "true" ]; then
        SITTING_SUSPENDED=true
        SITTING_REFUSAL="rig '${2:-?}' is suspended, so the reconciler skips its agents and a spawned converse sitting would never come up. Resume the rig, then re-engage: gc rig resume ${2:-<rig>}"
        return 1
    fi
    city_controller_state
    if [ "$CONTROLLER_RUNNING" = "false" ]; then
        SITTING_REFUSAL="the city controller did not answer ($CONTROLLER_SEEN), so nothing would launch a spawned converse sitting. Check 'gc status' and 'gc supervisor status', then re-engage once the controller answers."
        return 1
    fi
    return 0
}

# engage_take <id> [<from>] — settle what the engage is about from a bead, a
# conversation or a gate: sets bead and bead_row to the bead its conversation
# tracks, pointed_gate to a gate the id named, which the conversation replies to,
# pointed_others to the sentence naming the other open beads that gate holds
# (gate_others_line), and named_conv to a conversation it named. <from> is
# engage's --from, the bead
# the gate was reached from (take_bead). A conversation the id named is read
# for its status here, before anything is filed, and a closed one goes to
# engage_closed_conversation. A refusal exits.
engage_take() {
    bead="$1"; _et_conv_row=""
    verify_subject "$bead" engage "Nothing spawned." || exit $?
    take_bead engage "Nothing spawned." "${2:-}"
    pointed_gate="$TAKE_GATE"; named_conv="$TAKE_CONV"; pointed_others=$(gate_others_line)
    if [ "$TAKE_BEAD" != "$bead" ]; then
        if [ -n "$named_conv" ]; then
            _et_conv_row="$VS_ROW"
            echo "$PROG: engage: $bead is a conversation on $TAKE_BEAD" >&2
        elif [ -n "$TAKE_PICKED" ]; then
            # shellcheck disable=SC2086  # one word per bead
            echo "$PROG: engage: $bead is a gate about $TAKE_BEAD and $(words_and $TAKE_OTHERS) — engaging $TAKE_BEAD, which has waited on it longest, and the conversation replies to the gate" >&2
        else
            echo "$PROG: engage: $bead is a gate about $TAKE_BEAD — engaging $TAKE_BEAD, and the conversation replies to the gate" >&2
        fi
        bead="$TAKE_BEAD"
        verify_subject "$bead" engage "Nothing spawned." || exit $?
    fi
    bead_row="$VS_ROW"
    if [ "$(printf '%s' "$_et_conv_row" | jq -r '(.status // "") | tostring | ascii_downcase' 2>/dev/null || true)" = closed ]; then
        engage_closed_conversation "$_et_conv_row"
    fi
}

# engage_closed_said <row> <subject> — what a closed conversation's own row says
# of its close: when it closed, and the first line of its last hand-back
# (gc.handback). A hand-back opens with a header, `<subject> — <label>`, that
# names the subject and keeps its state for the lines after it, so a first line
# that is that header gives way to the line after it. A sitting may set the
# header in markdown bold, `**<subject> — <label>**`, and the emphasis marks do
# not stop it reading as the header. The text is the sitting's own and reaches
# the operator's terminal, so control bytes are dropped, and a line longer than
# 200 characters is cut at a word.
engage_closed_said() {
    printf '%s' "$1" | jq -r --arg s "$2" '
        ((.closed_at // "") | tostring) as $at
        | ((.metadata // {})["gc.handback"] // "" | tostring
           | gsub("[\\x00-\\x08\\x0b-\\x1f\\x7f]"; "")
           | [ split("\n")[] | gsub("^\\s+|\\s+$"; "") | select(. != "") ]) as $lines
        | (($lines[0] // "") | sub("^[*_]+"; "")) as $first
        | (if ($lines | length) > 1 and ($first | startswith($s))
              and ($first[($s | length):] | test("^[*_]*\\s+[—–-]\\s"))
           then $lines[1] else ($lines[0] // "") end
           | if length > 200 then (.[0:199] | sub("\\s+\\S*$"; "") | sub("[\\s,;:—–-]+$"; "")) + "…" else . end) as $line
        | ((.id // "") | tostring) + " closed" + (if $at == "" then "" else " at " + $at end)
          + (if $line == "" then "" else ", and its hand-back reads \"" + $line + "\"" end)' 2>/dev/null || true
}

# engage_refuse_closed <row> — refuse a conversation that reads closed, saying
# when it closed and how its hand-back reads, and naming the subject's engage,
# which opens a fresh conversation there. Exits 4.
engage_refuse_closed() {
    _erc_said=$(engage_closed_said "$1" "$bead")
    echo "$PROG: engage: ${_erc_said:-the conversation is closed}. A closed conversation is not held again; engage its subject to open a fresh one: $PROG engage $bead. Nothing spawned." >&2
    exit 4
}

# engage_closed_conversation <row> — the id named a conversation that has
# closed, so its sitting ended and nothing holds it again. A subject that is
# closed too takes no new conversation (open refuses it), and a closed
# conversation whose subject is open names the subject's engage, which opens a
# fresh one. Both refusals come before anything is filed and exit 4.
engage_closed_conversation() {
    _ecc_said=$(engage_closed_said "$1" "$bead")
    if [ "$(printf '%s' "$bead_row" | jq -r '(.status // "") | tostring | ascii_downcase' 2>/dev/null || true)" = closed ]; then
        echo "$PROG: engage: ${_ecc_said:-$named_conv is closed}. Its subject $bead is closed too, a settled item that takes no new conversation. To act on it, re-open $bead or file fresh work. Nothing spawned." >&2
        exit 4
    fi
    engage_refuse_closed "$1"
}

# engage_find_conversations <subject> — the subject's conversations that are
# not closed, one "<id>\t<state>\t<assignee>\t<status>\t<title>" row each. The
# state is `live` when a live sitting holds the conversation, `queue` when it
# waits in the operator's queue, and `left` when its sitting's session has
# closed: live first, then the queue, then the ones left, oldest first within
# each. The status is the conversation's own, as the listing read it. Returns 1
# when either read did not answer, so a caller never starts a second sitting
# beside a live one it could not see.
engage_find_conversations() {
    _efc_rows=$(bead_conversations "$1") || return 1
    _efc_live=$(live_sittings) || return 1
    printf '%s' "$_efc_rows" | jq -r --argjson live "$_efc_live" "$CONVERSATION_JQ$SITTING_JQ"'
        [ .[] | . + {state: (if held_live($live) then "live"
                             elif ((.assignee // "") | tostring) == "human" then "queue"
                             else "left" end)} ]
        | sort_by((if .state == "live" then 0 elif .state == "queue" then 1 else 2 end), (.created_at // ""))
        | .[] | [.id, .state, ((.assignee // "") | tostring),
                 ((.status // "open") | tostring | ascii_downcase), ((.title // "") | tostring)] | @tsv' 2>/dev/null
}

# engage_starter_list — "<key>\t<label>" per starter seed, in menu order.
engage_starter_list() { sh "$STARTERS_TOOL" list 2>/dev/null || true; }
# engage_starter_seed <key> <subject> — the seed body with the subject filled in.
engage_starter_seed() { sh "$STARTERS_TOOL" seed "$1" "$2" 2>/dev/null || true; }
# engage_lens_brief <skill> <subject> [opener] — the brief that seeds a sitting
# with the skill as its lens on the subject, the opener following it verbatim.
engage_lens_brief() { sh "$STARTERS_TOOL" lens "$1" "$2" "${3:-}" 2>/dev/null || true; }

# engage_skill_roster <rig> <model> — the skills a converse-<model> sitting in
# the rig carries, read from `gc skill list --agent` for the same
# <rig>/gc-toolkit.converse-<model> address converse-capability.sh reads. That
# is the agent's effective view, so a skill only the rig imports counts and a
# skill another rig imports does not. Sets ENGAGE_SKILL_ROSTER (full names, one
# per line, deduped, since the listing repeats a skill the city and the rig both
# import) and ENGAGE_SKILL_ROSTER_OK (1 on a readable answer, 0 when gc did not
# answer or answered malformed). Memoized per rig and model.
engage_skill_roster() {
    [ "${_esr_key:-}" = "$1/$2" ] && return 0
    _esr_key="$1/$2"; ENGAGE_SKILL_ROSTER=""; ENGAGE_SKILL_ROSTER_OK=0
    _esr_json=$(with_timeout "${GC_ROSTER_TIMEOUT:-15}" gc skill list --agent "$1/gc-toolkit.converse-$2" --json 2>/dev/null | scrub || true)
    [ -n "$_esr_json" ] || return 0
    if _esr_names=$(printf '%s' "$_esr_json" | jq -r '
            if type == "object" and (.entries | type == "array")
            then [ .entries[] | objects | (.name // "") | strings | select(. != "") ] | unique | .[]
            else error("not a skill roster") end' 2>/dev/null); then
        ENGAGE_SKILL_ROSTER="$_esr_names"; ENGAGE_SKILL_ROSTER_OK=1
    fi
}

# engage_resolve_skill <rig> <model> <name> — resolve a typed skill name against
# that roster. A full name matches itself, and a bare name matches the one full
# name ending in ".<name>", so review-arch reaches gc-toolkit.review-arch. Sets
# ENGAGE_SKILL_STATE to ok (ENGAGE_SKILL_NAME is the full name), ambiguous or
# unknown (ENGAGE_SKILL_MATCHES lists the candidates, or the whole roster), or
# unread when the roster did not read. unread fails OPEN, as engage_valid_model
# does for the same failure: ENGAGE_SKILL_NAME keeps the typed name, and the
# brief tells the sitting to say so if it cannot load it. The caller has already
# held the name to letters, digits, dots and hyphens, so awk -v reads it as-is.
engage_resolve_skill() {
    ENGAGE_SKILL_NAME=""; ENGAGE_SKILL_MATCHES=""
    engage_skill_roster "$1" "$2"
    if [ "$ENGAGE_SKILL_ROSTER_OK" != 1 ]; then
        ENGAGE_SKILL_STATE=unread; ENGAGE_SKILL_NAME="$3"; return 0
    fi
    _ers_hits=$(printf '%s\n' "$ENGAGE_SKILL_ROSTER" | awk -v q="$3" '$0 == q')
    if [ -z "$_ers_hits" ]; then
        _ers_hits=$(printf '%s\n' "$ENGAGE_SKILL_ROSTER" \
            | awk -v q=".$3" 'length($0) > length(q) && substr($0, length($0) - length(q) + 1) == q')
    fi
    _ers_n=$(printf '%s' "$_ers_hits" | grep -c . || true)
    if [ "$_ers_n" -eq 1 ]; then
        ENGAGE_SKILL_STATE=ok; ENGAGE_SKILL_NAME="$_ers_hits"
    elif [ "$_ers_n" -gt 1 ]; then
        ENGAGE_SKILL_STATE=ambiguous
        ENGAGE_SKILL_MATCHES=$(printf '%s\n' "$_ers_hits" | tr '\n' ' ' | sed 's/ *$//')
    else
        ENGAGE_SKILL_STATE=unknown
        ENGAGE_SKILL_MATCHES=$(printf '%s\n' "$ENGAGE_SKILL_ROSTER" | tr '\n' ' ' | sed 's/ *$//')
    fi
}

# create_subject <verb> <rig> <text> — create a fresh operator-origin subject
# bead in the rig's store, for a topic that has no bead yet, and set $bead to
# it. The rig is the caller's explicit choice, never inferred: a topic carries
# no id prefix to derive one from, and a bead filed in the wrong rig can draw
# public comments there. It must be a rig `gc rig list` names, carry a converse
# template, so a sitting can be held there, and have a .beads store.
#
# The text is the operator's question as typed. The description keeps it
# unchanged, newlines included, with a provenance line after it, and the title
# is the short label conversation_title derives from its opening, because a
# question is not a title and bd refuses a title over 500 bytes. The caller
# files the subject's one conversation itself, through open, so the subject
# exists for a moment before anything tracks it. It is filed assigned to
# `human`, the operator who asked, in the create itself, so no first reaction
# can start on it in that moment: the sweep reads only unassigned beads, and
# gctk reaction sling refuses an assigned one, as a reaction's own first act
# does. Once its conversation is filed, open hands the subject to it
# (open_handoff), and from then the open conversation keeps a first reaction
# off it. gc.origin=operator is the honest origin.
create_subject() {
    _cs_verb="$1"; _cs_rig="$2"; _cs_text="$3"
    enumerate_rigs
    if [ -z "$_cs_rig" ]; then
        echo "$PROG: $_cs_verb: --new-subject needs --rig <name>, the rig to create the subject in. A new topic names its rig; it is never inferred. Nothing created." >&2
        exit 2
    fi
    _cs_path=$(printf '%s' "$RIGS" | jq -r --arg n "$_cs_rig" '.[] | select(.name==$n) | .path' 2>/dev/null | head -n1)
    if [ -z "$_cs_path" ]; then
        echo "$PROG: $_cs_verb: --rig '$_cs_rig' matches no rig in 'gc rig list' (known: $(printf '%s' "$RIGS" | jq -r '[.[].name] | join(", ")' 2>/dev/null)). Nothing created." >&2
        exit 4
    fi
    if ! rig_carries_converse "$_cs_rig"; then
        echo "$PROG: $_cs_verb: rig '$_cs_rig' ($_cs_path) carries no converse template, so it can host no converse sitting. Pick a converse-capable rig. Nothing created." >&2
        exit 4
    fi
    if [ ! -d "$_cs_path/.beads" ]; then
        echo "$PROG: $_cs_verb: rig '$_cs_rig' has no .beads ledger at $_cs_path/.beads — nothing created." >&2
        exit 4
    fi
    if [ -z "$(printf '%s' "$_cs_text" | tr -d '[:space:]')" ]; then
        echo "$PROG: $_cs_verb: --new-subject needs the question the new subject is about. Nothing created." >&2
        exit 2
    fi
    _cs_title=$(conversation_title "$_cs_text")
    _cs_body="$_cs_text

---
Operator-initiated conversation subject, filed by \`$PROG $_cs_verb --new-subject\`. The text above is the operator's question as typed, and the title is a label derived from its opening."
    _cs_json=$(gc bd create -t task --title "$_cs_title" -d "$_cs_body" \
        --metadata '{"gc.origin":"operator"}' --assignee human \
        --db "$_cs_path/.beads" --json 2>/dev/null || true)
    bead=$(printf '%s' "$_cs_json" | scrub | jq -r 'if type=="array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null || true)
    if [ -z "$bead" ] || [ "$bead" = "null" ]; then
        _cs_err=$(printf '%s' "$_cs_json" | scrub | jq -r 'if type=="object" then (.error // empty) else empty end' 2>/dev/null || true)
        echo "$PROG: $_cs_verb: could not create the subject bead in rig '$_cs_rig'${_cs_err:+: $_cs_err}. Nothing filed." >&2
        exit 4
    fi
    echo "$PROG: $_cs_verb: filed subject $bead in rig '$_cs_rig' — \"$_cs_title\"" >&2
}

# engage_create_subject — the --new-subject pre-step of engage. The positional
# text is the question the subject is about, and --reason is it when no text is
# given; absent --reason or --template the same text is the conversation's
# opener. create_subject files the subject, and on return $bead is its id and
# the opener is primed (engage_reason/engage_file_new), so the rest of cmd_engage
# runs unchanged.
#
# Every gate from here to the conversation-filing in cmd_engage can still abort
# (a suspended rig, a downed controller, an unknown --template or --model, a
# store read that will not confirm the bead), and until the conversation is
# filed an abort would leave this operator-origin subject owing a conversation
# that nothing supplies: it is assigned to `human` until its conversation owns
# it, so no first reaction takes it up. So the abort backstop is armed the
# instant the subject exists, and engage_new_subject_cleanup files that one
# conversation itself on exit; cmd_engage disarms it once the conversation is
# filed. enumerate_rigs already set and cleared its own trap and memoizes on
# every later call, so it never clobbers this one.
engage_create_subject() {
    [ -n "$new_subject_title" ] || new_subject_title="$engage_reason"
    if [ -z "$engage_template" ] && [ "$engage_reason_set" = 0 ]; then
        engage_reason="$new_subject_title"; engage_reason_set=1
    fi
    create_subject engage "$engage_rig" "$new_subject_title"
    engage_file_new=1
    _ens_cleanup_bead="$bead"
    trap 'engage_new_subject_cleanup' EXIT
    trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
}

# engage_new_subject_cleanup — the abort backstop for --new-subject, armed by
# engage_create_subject the instant the subject exists and disarmed by
# cmd_engage once the conversation is filed. While armed, any exit (an abort
# gate or a signal) means the live engage stopped before cmd_engage filed the
# subject's one conversation. The subject still owes it, and no first reaction
# takes it up while it is assigned to `human`. So file the one conversation
# here with cmd_open, the same path the happy flow uses: it resolves the
# subject's rig from its id, joins a conversation already in the queue, files
# the conversation in the operator's queue, and hands the subject to it. Run
# cmd_open in a subshell so its own exits cannot abort this trap, and disarm
# first so it cannot re-enter. A no-op when nothing is armed; it preserves the
# process's exit code.
_ens_cleanup_bead=""
engage_new_subject_cleanup() {
    _enc_rc=$?
    [ -n "${_ens_cleanup_bead:-}" ] || return "$_enc_rc"
    _enc_bead="$_ens_cleanup_bead"
    _ens_cleanup_bead=""
    trap - EXIT INT TERM HUP
    set -- "$_enc_bead"
    [ -n "${engage_reason:-}" ] && set -- "$@" --reason "$engage_reason"
    if ( cmd_open "$@" >/dev/null 2>&1 ); then
        echo "$PROG: engage: the live engage aborted, but filed the one conversation new subject $_enc_bead owes — waiting in the operator's queue. Engage it when ready: $PROG engage $_enc_bead" >&2
    else
        echo "$PROG: engage: new subject $_enc_bead was created but its conversation could NOT be filed, or the subject not handed to it (store error?). It stays assigned to human, so no first reaction takes it up. File the conversation by hand, which hands the subject to it: $PROG open $_enc_bead" >&2
    fi
    return "$_enc_rc"
}

# ── Verb: engage ─────────────────────────────────────────────────────
# The operator's "I want to talk about this now". A conversation about a bead
# waits in the operator's queue and holds no session until the operator
# engages it, so no sitting is demand-spawned. engage takes the bead, lands on
# one of its conversations, and holds it in a sitting: it attaches to a live
# sitting on the bead rather than starting a second, else takes a conversation
# from the queue or one whose sitting's session has closed, else files one.
# A concern the operator brings (--reason, --template or --skill) is a
# distinct dialogue, so it files a
# fresh conversation even when the bead has one. A sitting is a manual
# converse-<model> session named for its conversation (origin=manual, which the
# work ladder that paces pool seats never governs). The session is spawned
# before the bind, because its alias is the reservation: only one session that
# is not closed can hold the alias. Then the conversation is bound to the
# session's alias with a write guarded on the holder engage read, so of two
# engages only one bind lands, and the session's own `gc hook --claim` adopts
# it. dismiss ends the sitting.
#
# The argument is the bead the operator picked off the board. A conversation id
# names its own conversation. A gate names the one bead still waiting on it, and
# the conversation engage lands on replies to the gate (bd's replies-to edge),
# written before any sitting starts, so the sitting finds the gate among its
# conversation's replies. Engage warns when it starts a sitting while another
# live sitting tracks the bead or replies to a gate the bead waits on: one
# sitting per bead is engage's default, not a guarantee. --from names the bead
# the gate was reached from, as engage's line for a gate that holds a bead
# names that bead: a gate several open beads wait on is about it while it is
# one of them, and one that no longer holds it starts nothing (take_bead).
#
# --model selects the tier, claude-opus by default, from the ones
# engage_list_models lists. --skill seeds the sitting with a skill as its lens
# on the subject, any skill the sitting carries. The lens brief is the new
# conversation's ask, which a sitting on any model reads when it claims the
# conversation, so the skill rides it across a restart with no per-skill
# template. --no-attach spawns and binds without
# attaching — the board's engage route uses it, then the operator attaches from
# the session picker. Attached (the default), the operator lands in the sitting
# directly.
cmd_engage() {
    bead=""; engage_model="claude-opus"; engage_reason=""; engage_attach=1
    engage_no_input=0; engage_model_set=0; engage_reason_set=0; engage_template=""
    engage_skill=""; engage_skill_set=0
    # What the concern files, carried into the conversation choice and output below.
    engage_body=""; engage_file_new=0; conv_new=0
    # --new-subject files a FRESH subject bead, then engages it (rig-aware, since
    # there is no id prefix yet to derive the rig from). --rig names that rig;
    # --subject names an EXISTING one, so the two are mutually exclusive.
    engage_new_subject=0; engage_rig=""; engage_subject_flag=0
    # --from names the bead a gate was reached from (engage_take).
    engage_from=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --model=*)   engage_model="${1#--model=}"; engage_model_set=1; shift ;;
            --model)     shift; [ $# -gt 0 ] || { echo "$PROG: engage: --model requires a value" >&2; exit 2; }
                         engage_model="$1"; engage_model_set=1; shift ;;
            --reason=*)  engage_reason="${1#--reason=}"; engage_reason_set=1; shift ;;
            --reason)    shift; [ $# -gt 0 ] || { echo "$PROG: engage: --reason requires a value" >&2; exit 2; }
                         engage_reason="$1"; engage_reason_set=1; shift ;;
            --template=*) engage_template="${1#--template=}"; shift ;;
            --template)  shift; [ $# -gt 0 ] || { echo "$PROG: engage: --template requires a value" >&2; exit 2; }
                         engage_template="$1"; shift ;;
            --skill=*)   engage_skill="${1#--skill=}"; engage_skill_set=1; shift ;;
            --skill)     shift; [ $# -gt 0 ] || { echo "$PROG: engage: --skill requires a value" >&2; exit 2; }
                         engage_skill="$1"; engage_skill_set=1; shift ;;
            --subject=*) [ -z "$bead" ] || { echo "$PROG: engage takes one subject" >&2; exit 2; }; bead="${1#--subject=}"; engage_subject_flag=1; shift ;;
            --subject)   shift; [ $# -gt 0 ] || { echo "$PROG: engage: --subject requires a value" >&2; exit 2; }
                         [ -z "$bead" ] || { echo "$PROG: engage takes one subject" >&2; exit 2; }; bead="$1"; engage_subject_flag=1; shift ;;
            --new-subject) engage_new_subject=1; shift ;;
            --from=*)    engage_from="${1#--from=}"; shift ;;
            --from)      shift; [ $# -gt 0 ] || { echo "$PROG: engage: --from requires a value" >&2; exit 2; }
                         engage_from="$1"; shift ;;
            --rig=*)     engage_rig="${1#--rig=}"; shift ;;
            --rig)       shift; [ $# -gt 0 ] || { echo "$PROG: engage: --rig requires a value" >&2; exit 2; }
                         engage_rig="$1"; shift ;;
            --no-input)  engage_no_input=1; shift ;;
            --no-attach) engage_attach=0; shift ;;
            -h|--help)   usage; exit 0 ;;
            -*) echo "$PROG: engage: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: engage takes one subject" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done

    # --reason and --template both pre-fill the starter — they conflict.
    if [ -n "$engage_reason" ] && [ -n "$engage_template" ]; then
        echo "$PROG: engage: --reason and --template both set the opening message — pass only one." >&2
        exit 2
    fi
    # A skill name is letters, digits, dots and hyphens. An empty or malformed
    # --skill is refused here, before anything is read or filed, and the charset
    # is what lets the name reach the brief's substitution and awk unescaped.
    if [ "$engage_skill_set" = 1 ]; then
        case "$engage_skill" in
            ""|*[!A-Za-z0-9._-]*)
                echo "$PROG: engage: --skill '$engage_skill' is not a skill name (letters, digits, dots and hyphens, e.g. review-arch)." >&2
                exit 2 ;;
        esac
    fi

    # --rig names the rig a NEW subject is created in; an existing subject's rig
    # comes from its id prefix, so --rig is meaningless there. Refuse rather than
    # silently ignore it.
    if [ -n "$engage_rig" ] && [ "$engage_new_subject" = 0 ]; then
        echo "$PROG: engage: --rig applies only with --new-subject; an existing subject's rig is derived from its id. Drop --rig, or add --new-subject to create one." >&2
        exit 2
    fi
    if [ "$engage_new_subject" = 1 ] && [ "$engage_subject_flag" = 1 ]; then
        echo "$PROG: engage: --subject names an existing bead and --new-subject creates one — pass only one." >&2
        exit 2
    fi
    if [ "$engage_new_subject" = 1 ] && [ -n "$engage_from" ]; then
        echo "$PROG: engage: --from names the bead a gate was reached from, and --new-subject creates a new subject — pass only one." >&2
        exit 2
    fi
    if [ -n "$engage_from" ] && [ -z "$bead" ]; then
        echo "$PROG: engage: --from names the bead a gate was reached from, so it needs the gate: $PROG engage <gate> --from <bead>." >&2
        exit 2
    fi

    # On a terminal, an engage whose command line leaves the concern open runs
    # the conversation form (helm_form): the subject, which names a bead, a PR
    # or a new topic's rig, the question, the model and whether to attach are
    # fields of one screen, filled in from the command line, where --rig fills
    # in the subject, and the form saves and starts through this script's own
    # open and engage. --no-attach turns its attach field
    # off, so the flag means on a terminal what it means below. A concern on the
    # command line (--reason, --template or --skill), --no-input, and every
    # engage without a terminal take the flag-driven path below.
    # GC_HELM_ASSUME_TTY is a test seam that takes the form's path when stdin is
    # a pipe, as in a hermetic test. A --model the configured variants do not
    # carry is refused before the form opens, as the flag-driven path refuses
    # it, since the form's model field holds only those.
    if [ "$engage_no_input" = 0 ] && [ "$engage_reason_set" = 0 ] && [ -z "$engage_template" ] \
        && [ -z "$engage_skill" ] && { [ -t 0 ] || [ -n "${GC_HELM_ASSUME_TTY:-}" ]; }; then
        [ "$engage_model_set" = 0 ] || engage_check_model
        set --
        if [ "$engage_new_subject" = 1 ]; then
            set -- --new-subject
            [ -z "$bead" ] || set -- "$@" --question "$bead"
            [ -z "$engage_rig" ] || set -- "$@" --rig "$engage_rig"
        elif [ -n "$bead" ]; then
            set -- --subject "$bead"
            [ -z "$engage_from" ] || set -- "$@" --from "$engage_from"
        fi
        [ "$engage_model_set" = 0 ] || set -- "$@" --model "$engage_model"
        [ "$engage_attach" = 1 ] || set -- "$@" --no-attach
        helm_form engage "$@"
    fi

    # --new-subject: file a FRESH subject bead in a chosen rig, then engage it in
    # one gesture. The positional argument is the question the subject is about,
    # not an id. engage_create_subject creates the bead in the --rig rig,
    # assigned to `human` until its conversation owns it, and leaves its id in
    # $bead with the opener primed. After it the rest of this verb runs
    # unchanged, deriving the rig from the new id's prefix and filing the ONE
    # conversation, whose open hands the subject to it.
    if [ "$engage_new_subject" = 1 ]; then
        new_subject_title="$bead"; bead=""
        engage_create_subject
    fi

    if [ -z "$bead" ]; then
        echo "$PROG: engage needs <bead-id> (a bead to converse about, a conversation, or a human gate)" >&2; usage; exit 2
    fi

    # Resolve a PR reference or a settled disposition to the live owning bead
    # (parity with open), before the rig is derived from the id prefix.
    resolve_live_subject "$bead"
    bead="$RESOLVED_SUBJECT"

    # Pin bd at the bead's rig, as open/dismiss do, so the conversation lookup
    # and bind read and write the store the picked bead lives in. A gate and a
    # conversation sit in the store of the bead they are about, so the id's own
    # prefix names that store. A prefix no rig carries is refused here: the
    # converse templates are rig-scoped, so with no rig there is nowhere to
    # resolve "$template" and nothing to spawn.
    path=$(rig_path_for_bead "$bead")
    if [ -z "$path" ]; then
        echo "$PROG: engage: '$bead' — its id prefix '${bead%%-*}' matches no rig in 'gc rig list', so there is no rig to resolve the converse template in. Nothing spawned." >&2
        exit 4
    fi
    rig=$(rig_name_for_bead "$bead")
    if ! sitting_refusal "$bead" "$rig" "$path"; then
        echo "$PROG: engage: $SITTING_REFUSAL" >&2
        exit 4
    fi
    [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"
    [ -n "$rig" ] && export GC_RIG="$rig"

    # The bead must resolve before anything spawns — the shared resolve+classify,
    # so an unanswered read fails closed as a data-plane outage, not a missing
    # bead, the way open does. A gate names the one bead still waiting on it, and
    # a conversation id names its own conversation and the bead it tracks. A
    # closed conversation is refused.
    engage_take "$bead" "$engage_from"

    # --skill and --reason write a NEW conversation's ask, which is written once,
    # at filing. An open conversation's id names a conversation whose ask
    # already exists, so neither has anywhere to go; refuse before anything is filed,
    # and point at the subject form that files a conversation carrying them.
    if [ -n "$named_conv" ] && [ -n "$engage_skill" ]; then
        echo "$PROG: engage: --skill seeds a NEW conversation's ask, which needs a subject — but '$named_conv' is an explicit conversation id, and its ask is already written. Engage its subject with --skill instead: $PROG engage $bead --skill $engage_skill. Nothing spawned." >&2
        exit 2
    fi
    if [ -n "$named_conv" ] && [ -n "$engage_reason$engage_template" ]; then
        echo "$PROG: engage: --reason or --template files a NEW conversation, which needs a subject — but '$named_conv' is an explicit conversation id. Engage the subject with --reason to open a fresh conversation, or drop it to engage this conversation as-is. Nothing spawned." >&2
        exit 2
    fi

    # --template pre-fills the starter with a named seed now that the subject is
    # known; the seed body becomes the new conversation's ask.
    if [ -n "$engage_template" ]; then
        engage_body=$(engage_starter_seed "$engage_template" "$bead")
        [ -n "$engage_body" ] || { echo "$PROG: engage: unknown --template '$engage_template' (valid: $(engage_starter_list | cut -f1 | tr '\n' ' ' | sed 's/ *$//'))" >&2; exit 2; }
        engage_reason=$(engage_starter_list | awk -F"$TAB" -v k="$engage_template" '$1==k{print $2}')
        [ -n "$engage_reason" ] || engage_reason="$engage_template"
        engage_file_new=1
    fi

    # An engage on a bead names what holds it, unless it was pointed at a
    # conversation or a gate.
    if [ -z "$named_conv" ] && [ -z "$pointed_gate" ]; then
        engage_say_holds "$bead"
    fi

    # The model is the claude-opus default or the flag, validated against the
    # variants engage offers before the template binds.
    engage_check_model
    template="converse-$engage_model"

    # The lens brief becomes the new conversation's ask, ahead of any opener (a
    # seed's body, a typed opener, or --reason), and the skill leads the
    # conversation's title so the board row says whose view the sitting brings.
    # An unreadable roster seeds the typed name unverified, as an unconfirmable
    # --model spawns.
    if [ -n "$engage_skill" ]; then
        engage_resolve_skill "$rig" "$engage_model" "$engage_skill"
        case "$ENGAGE_SKILL_STATE" in
            ok) engage_skill="$ENGAGE_SKILL_NAME" ;;
            unread)
                echo "$PROG: engage: could not read the skill list for $rig/gc-toolkit.$template, so '$engage_skill' is seeded unverified; the sitting says so in its framing if it cannot load it." >&2 ;;
            ambiguous)
                echo "$PROG: engage: --skill '$engage_skill' matches more than one skill ($ENGAGE_SKILL_MATCHES); name one in full. Nothing spawned." >&2
                exit 2 ;;
            *)
                echo "$PROG: engage: unknown --skill '$engage_skill': a $template sitting in rig '$rig' carries ${ENGAGE_SKILL_MATCHES:-no skills}. Nothing spawned." >&2
                exit 2 ;;
        esac
        engage_body=$(engage_lens_brief "$engage_skill" "$bead" "${engage_body:-$engage_reason}")
        [ -n "$engage_body" ] || { echo "$PROG: engage: $STARTERS_TOOL did not produce the lens brief for '$engage_skill'. Nothing spawned." >&2; exit 3; }
        engage_reason="${engage_skill##*.} lens${engage_reason:+: $engage_reason}"
    fi
    # Land on the sitting's conversation. A conversation id named it; a concern
    # files a fresh one, even when the bead has one, because a distinct concern
    # is a distinct dialogue; and with neither engage attaches first: a live sitting's conversation,
    # else one waiting in the queue, else one whose sitting's session has
    # closed, else a new one. The listing and the session list must both answer
    # before engage chooses, so it never starts a second sitting beside a live
    # one it could not see. The holder and the status engage reads here are what
    # its bind is guarded on below.
    CONV=""; conv_state=""; conv_holder=""; conv_status=""; conv_via_open=""
    sid=""; sname=""; start_alias=""
    if [ -n "$named_conv" ]; then
        CONV="$named_conv"
    fi
    if ! conv_rows=$(engage_find_conversations "$bead"); then
        echo "$PROG: engage: could not read the conversations on $bead or 'gc session list', so a live sitting there cannot be ruled out. Nothing spawned; retry once both answer: $PROG engage $bead" >&2
        exit 4
    fi
    if [ -z "$CONV" ] && [ "$engage_file_new" = 0 ] && [ -z "$engage_reason" ]; then
        CONV=$(printf '%s\n' "$conv_rows" | awk -F'\t' 'NF && $1 != "" {print $1; exit}')
    fi
    if [ -n "$CONV" ]; then
        conv_line=$(printf '%s\n' "$conv_rows" | awk -F'\t' -v c="$CONV" '$1 == c')
        if [ -z "$conv_line" ]; then
            # One that closed after engage read it, as a sign-off or a dismiss
            # closes one, is refused as closed. Any other is not one of the
            # bead's open conversations.
            conv_now=$(row_now "$CONV")
            if [ "$(printf '%s' "$conv_now" | jq -r '(.status // "") | tostring | ascii_downcase' 2>/dev/null || true)" = closed ]; then
                engage_refuse_closed "$conv_now"
            fi
            echo "$PROG: engage: $CONV is not an open conversation about $bead, so there is no sitting of it to hold. Engage the subject to take one of its conversations or open a fresh one: $PROG engage $bead. Nothing spawned." >&2
            exit 4
        fi
        conv_state=$(printf '%s' "$conv_line" | cut -f2)
        conv_holder=$(printf '%s' "$conv_line" | cut -f3)
        conv_status=$(printf '%s' "$conv_line" | cut -f4)
    else
        # Pointed at a gate, the conversation is filed through the gate, so it
        # is about the bead engage took from that gate and a note on it names
        # the other beads the gate holds. With no concern, its title and ask
        # are what the gate asks.
        OPEN_GATE_FROM="$bead"
        if [ "$engage_file_new" = 1 ] || [ -n "$engage_reason" ]; then
            echo "$PROG: engage: filing a new conversation on $bead, then engaging it" >&2
            set -- "${pointed_gate:-$bead}" --allow-duplicate
            [ -n "$engage_reason" ] && set -- "$@" --reason "$engage_reason"
            [ -n "$engage_body" ] && set -- "$@" --body "$engage_body"
        else
            echo "$PROG: engage: no conversation on $bead — filing one, then engaging it" >&2
            set -- "${pointed_gate:-$bead}"
        fi
        # cmd_open runs in this shell and leaves in CONV the conversation it
        # filed, or the one it joined when another open filed one in the queue
        # after engage's listing above. Its stdout is terminal advice for a
        # standalone `open`, stale here because engage holds the conversation
        # itself just below. Errors stay on stderr.
        cmd_open "$@" >/dev/null || { echo "$PROG: engage: could not file a conversation for $bead" >&2; exit 4; }
        # The conversation is filed, so a --new-subject subject is no longer an
        # orphan — disarm the abort backstop armed in engage_create_subject.
        if [ -n "${_ens_cleanup_bead:-}" ]; then
            _ens_cleanup_bead=""
            trap - EXIT INT TERM HUP
        fi
        # open files a conversation, or joins one, only as it waits in the
        # queue: assigned to human, at open.
        conv_new="$OPEN_FILED"; conv_state=queue; conv_holder=human; conv_status=open
        conv_via_open=1
    fi

    # A sitting engage starts on a conversation about an open PR holds the PR's
    # merge until the conversation closes. open held it already for a
    # conversation it filed or joined just above, and a live sitting engage
    # attaches to keeps the hold as that sitting left it. Any other
    # conversation, one taken from the queue or left by a sitting whose session
    # closed, takes the hold before its sitting starts, so a conversation filed
    # before its PR opened, or one whose sitting lifted the hold, holds the
    # merge again once it is engaged.
    #
    # Pointed at a gate, the conversation engage landed on replies to it,
    # whichever it is, and the reply is written before a sitting starts or the
    # operator attaches, so the sitting finds the gate among its conversation's
    # replies at its next read.
    #
    # The hold goes on first, and each of the two is written whatever the
    # other's outcome. A reply the store refuses then never leaves the PR free
    # to merge while the conversation is open, and a hold that does not land
    # never costs the reply, which a re-engage of the conversation does not
    # write. Either one failing starts nothing.
    eng_unready=""
    if [ -z "$conv_via_open" ] && [ "$conv_state" != live ]; then
        if ! eng_anchor=$(conversation_pr_anchor "$bead_row"); then
            echo "$PROG: engage: could not read $(subject_anchor "$bead_row"), the anchor $bead names, so whether the sitting must hold an open PR's merge cannot be told. Nothing spawned; re-engage once the store answers: $PROG engage $CONV" >&2
            eng_unready=1
        elif [ -n "$eng_anchor" ] && ! conversation_hold_merge engage "$CONV" "$eng_anchor"; then
            echo "$PROG: engage: nothing spawned, because the sitting would talk while the PR could merge. Re-engage once the hold lands: $PROG engage $CONV" >&2
            eng_unready=1
        fi
    fi
    if [ -n "$pointed_gate" ] && ! conversation_reply "$CONV" "$pointed_gate"; then
        echo "$PROG: engage: the store refused conversation $CONV's reply onto gate $pointed_gate, so the sitting would not know the gate it answers. Nothing spawned. Add it by hand and re-engage: gc bd dep add $CONV $pointed_gate --type replies-to" >&2
        eng_unready=1
    fi
    [ -z "$eng_unready" ] || exit 4
    # A conversation open did not file or join this run, on a gate that holds
    # other open beads too, takes the sentence naming them as a note when it
    # does not carry it, as one open files or joins does, so its sitting sees
    # each bead the answer reaches. A note the store refuses starts nothing
    # less.
    if [ -z "$conv_via_open" ]; then
        conversation_note_others engage "$CONV" "$pointed_others" "$pointed_gate"
    fi

    # One sitting per bead is engage's default, not a guarantee: a concern of
    # its own, two engages racing on a bead with no conversation, or a gate
    # another bead's sitting answers each give a second live sitting, and
    # nothing refuses it. So engage warns when another live sitting tracks the
    # bead, or replies to a gate the bead waits on. Best effort: a read that
    # does not answer only costs the warning.
    eng_others=$(printf '%s\n' "$conv_rows" | awk -F'\t' -v c="$CONV" '$2 == "live" && $1 != c {printf "%s%s", sep, $1; sep=" "}')
    need_human_gate_jq
    if eng_gates=$(human_gate_rows "$bead" 2>/dev/null) && eng_live=$(live_sittings); then
        for _eg in $(printf '%s' "$eng_gates" | jq -r "$HUMAN_GATE_JQ"'.[] | select(open_human_gate("")) | .id' 2>/dev/null); do
            _eg_rep=$(bd_rows dep list "$_eg" --direction=up --type replies-to 2>/dev/null || printf '[]')
            for _eg_c in $(printf '%s' "$_eg_rep" | jq -r --argjson live "$eng_live" --arg c "$CONV" "$CONVERSATION_JQ$SITTING_JQ"'
                    .[] | objects | select(.id != $c) | select(held_live($live)) | .id' 2>/dev/null); do
                case " $eng_others " in *" $_eg_c "*) ;; *) eng_others="${eng_others:+$eng_others }$_eg_c (replies to gate $_eg)" ;; esac
            done
        done
    fi
    [ -z "$eng_others" ] || echo "$PROG: engage: warning: another live sitting is on $bead already — conversation $eng_others. Both fold onto $bead's row, either may answer a gate, and the first answer wins." >&2

    # An attach must not reach a sitting before the reconciler does.
    # `gc session attach` on a sitting the reconciler has not launched yet
    # launches it itself, from the stored command with no prompt, and that
    # sitting idles at its input until someone types into it. So every attach
    # engage makes, to a sitting it spawns or to a live one it reuses, waits for
    # the launch first, the same wait `gc session new` runs before its own
    # attach, and attaches only a started sitting. --no-attach attaches
    # nothing, so it does not wait.
    #
    # engage_await_start returns 0 once the sitting's `gc session list` row
    # reads `active`, which it does only once the runtime is running; before the
    # launch it reads start-pending or creating. It returns 0 at once for a row
    # that reads `asleep` as well: a sitting that has run and slept, as one that
    # stays for the return of the work it sent sleeps under the template's
    # sleep_after_idle, and `gc session attach` wakes it with its thread and
    # delivers its prompt again (specs/tk-pb9wnr3/stay-probe.md), so waiting
    # would only hold the operator to the bound. It returns 2 when the sitting
    # ended first, and 1 when ENGAGE_WAIT_TIMEOUT seconds pass first. The
    # sitting is the row whose id is $sid. With $sid empty it is the open row
    # under the alias $start_alias, bare or qualified, a sitting that holds the
    # conversation by its alias before the list names it, and the first row that
    # alias matches sets $sid and $sname. A row that reads closed or
    # failed-create has ended, and so has one that leaves the list once listed,
    # since a listing of open sessions leaves a closed one out. A sitting not
    # listed yet may only lag the supervisor's read cache, so it is waited on.
    # So is one listed with no state, which Gas City's own wait for a new
    # session reads as a create still under way, and so is a listing that did
    # not read. start_state keeps the last state read, and start_waited the
    # seconds waited as of that read, for the messages that follow.
    #
    # The wait reports itself on stdout, so a slow start reads as progress and
    # not as a hang: a line when it begins, a line each time the sitting's state
    # changes (start-pending to creating, say), and a line every 30 seconds with
    # the time waited. A listing that did not read is no change of state.
    engage_await_start() {
        _start_t0=$(date +%s)
        _start_seen=0; _start_told=0; _start_shown=""; _start_tick=30
        start_state=""; start_waited=0
        while :; do
            _start_row=$(gc session list --json 2>/dev/null | scrub | jq -r --arg id "$sid" --arg al "${start_alias:-}" '
                if type == "object" and ((.sessions // null) | type) == "array"
                then (first(.sessions[] | objects
                            | ((.state // "") | tostring) as $st
                            | ((.alias // "") | tostring) as $a
                            | select(if $id != "" then ((.id // "") | tostring) == $id
                                     else $al != "" and ($a == $al or ($a | endswith("/" + $al)) or ($a | endswith("." + $al)))
                                          and (.closed // false) != true
                                          and $st != "closed" and $st != "failed-create" end)
                            | [ (if (.closed // false) == true then "closed" elif $st == "" then "none" else $st end),
                                ((.id // "") | tostring), ((.session_name // "") | tostring) ] | @tsv)
                      // "unlisted")
                else "unreadable" end' 2>/dev/null || true)
            case "$_start_row" in
                *"$TAB"*)
                    start_state=${_start_row%%"$TAB"*}
                    if [ -z "$sid" ]; then
                        _start_rest=${_start_row#*"$TAB"}
                        sid=${_start_rest%%"$TAB"*}
                        _start_name=${_start_rest#*"$TAB"}
                        [ -z "$_start_name" ] || sname="$_start_name"
                    fi ;;
                *) start_state="$_start_row" ;;
            esac
            start_waited=$(( $(date +%s) - _start_t0 ))
            _start_now=""
            case "$start_state" in
                active|asleep) return 0 ;;
                closed|failed-create) return 2 ;;
                unlisted) [ "$_start_seen" = 0 ] || { start_state=gone; return 2; } ;;
                none) _start_seen=1 ;;
                ''|unreadable) ;;
                *) _start_seen=1; _start_now="$start_state" ;;
            esac
            [ "$start_waited" -lt "$ENGAGE_WAIT_TIMEOUT" ] || return 1
            if [ "$_start_told" = 0 ]; then
                printf '  waiting for the reconciler to start %s (it %s), then attaching; Ctrl-C stops the wait and leaves it starting\n' \
                    "$sname" "$(engage_state_text "$start_state")"
                _start_told=1
            elif [ -n "$_start_now" ] && [ "$_start_now" != "$_start_shown" ]; then
                printf '  %s is now %s, after %s\n' "$sname" "$_start_now" "$(engage_dur "$start_waited")"
            elif [ "$start_waited" -ge "$_start_tick" ]; then
                printf '  still waiting after %s: %s %s\n' \
                    "$(engage_dur "$start_waited")" "$sname" "$(engage_state_text "$start_state")"
            fi
            [ -z "$_start_now" ] || _start_shown="$_start_now"
            while [ "$_start_tick" -le "$start_waited" ]; do _start_tick=$((_start_tick + 30)); done
            sleep 1
        done
    }
    # engage_dur <seconds> — a wait as the operator reads it: 45s, 2m05s.
    engage_dur() {
        if [ "$1" -lt 60 ]; then
            printf '%ss' "$1"
        else
            printf '%sm%02ds' "$(($1 / 60))" "$(($1 % 60))"
        fi
    }
    # engage_state_text <state> — a start_state read, as the verb phrase that
    # follows the sitting in a progress line.
    engage_state_text() {
        case "$1" in
            unlisted) printf 'is not listed yet' ;;
            none) printf 'is listed with no state yet' ;;
            ''|unreadable) printf "could not be read from 'gc session list'" ;;
            *) printf 'is %s' "$1" ;;
        esac
    }
    # engage_attach_later — the attach the operator runs once the sitting has
    # started: gc's own attach of the sitting, or with the sitting not named
    # yet, an attach of the conversation, which engages it again.
    engage_attach_later() {
        if [ -n "$sid" ]; then
            printf 'gc session attach %s' "$sid"
        else
            printf '%s attach %s' "$PROG" "$CONV"
        fi
    }
    # engage_wait — the attach path's wait for the launch, under the INT, TERM
    # and HUP trap, HUP being the terminal going away under the wait. The
    # handler writes and closes nothing, so the binding and the start carry on
    # without engage, and the sitting begins once it starts. The handler
    # disarms itself, so a second Ctrl-C ends engage at once. Leaves the wait's
    # answer in start_rc.
    engage_wait() {
        start_rc=0; start_waited=0
        trap 'engage_wait_interrupted 130' INT
        trap 'engage_wait_interrupted 143' TERM
        trap 'engage_wait_interrupted 129' HUP
        engage_await_start || start_rc=$?
        trap - INT TERM HUP
    }
    engage_wait_interrupted() {
        trap - INT TERM HUP
        echo "$PROG: engage: stopped waiting after $(engage_dur "$start_waited"). Conversation $CONV stays held by $sname, which the reconciler goes on starting; attach once it reads active in 'gc session list': $(engage_attach_later)" >&2
        exit "$1"
    }

    # Once the attach returns, the tab is back at this shell, and what it prints
    # next is the operator's only account of the sitting it left: nothing of the
    # pane survives it. tmux shows [exited] when the sitting's session ended
    # (each converse template sets detach-on-destroy on its own session) and
    # [detached] when the operator left it, and both exit 0, so the
    # conversation says which. A closed conversation is a sitting that ended,
    # and the tab prints how the conversation closed and the last hand-back the
    # sitting recorded on it (cmd_handback). A conversation back in the
    # operator's queue is a sitting cut short, which handed it back and drained,
    # so the tab prints that hand-back and how to take the conversation up
    # again: its session holds the conversation no more, and attaching to it
    # would only wake it. A conversation its sitting still holds is a sitting
    # still going, and the tab prints how to re-attach. A failed attach reads
    # the same conversation first, because a sitting that ended before the tab
    # reached it is reported, not offered for an attach.
    engage_print_handback() {
        _ph_at=$(printf '%s' "$1" | jq -r '(.metadata // {})["gc.handback_at"] // "" | tostring' 2>/dev/null || true)
        # The text is the sitting's own, printed to the operator's terminal,
        # so control bytes other than tab and newline are dropped.
        _ph_text=$(printf '%s' "$1" | jq -r '(.metadata // {})["gc.handback"] // "" | tostring
            | gsub("[\\x00-\\x08\\x0b-\\x1f\\x7f]"; "")' 2>/dev/null || true)
        if [ -n "$_ph_text" ]; then
            printf 'Its last hand-back%s:\n\n%s\n' "${_ph_at:+, recorded $_ph_at}" "$_ph_text"
        else
            printf 'It recorded no hand-back.\n'
        fi
    }
    engage_after_attach() {
        _aa_row=$(row_now "$CONV")
        _aa_status=$(printf '%s' "$_aa_row" | jq -r '.status // ""' 2>/dev/null || true)
        _aa_holder=$(printf '%s' "$_aa_row" | jq -r '.assignee // ""' 2>/dev/null || true)
        if [ "$_aa_status" = "closed" ]; then
            _aa_reason=$(printf '%s' "$_aa_row" | jq -r '.close_reason // "" | tostring' 2>/dev/null || true)
            printf '\nThe sitting on %s has ended: conversation %s closed%s.\n' "$bead" "$CONV" "${_aa_reason:+ ($_aa_reason)}"
            engage_print_handback "$_aa_row"
        elif [ "$_aa_status" = "open" ] && [ "$_aa_holder" = "human" ]; then
            printf '\nThe sitting on %s has ended: conversation %s is back in your queue. Take it up again: %s engage %s\n' "$bead" "$CONV" "$PROG" "$bead"
            engage_print_handback "$_aa_row"
        elif [ "$1" -ne 0 ]; then
            echo "$PROG: engage: could not attach to $sid — attach when ready: gc session attach $sid" >&2
        elif [ -z "$_aa_status" ]; then
            printf '\nCould not read conversation %s, so whether its sitting has ended is unknown: gc bd show %s\n' "$CONV" "$CONV"
        else
            printf '\nThe sitting on %s is still open (conversation %s). Re-attach: gc session attach %s\n' "$bead" "$CONV" "$sid"
        fi
    }

    # engage_attach_held — attach the operator to the sitting that holds the
    # conversation, rather than start a second: $sid, or with $sid empty the
    # sitting under the alias $start_alias, which the session list has not
    # named yet and the start wait names once it does. A sitting is live from
    # the spawn that created it, so one another engage spawned with --no-attach
    # can still be waiting for the reconciler's launch, and the attach waits for
    # it as the attach to a sitting engage spawns does. --no-attach names the
    # sitting and attaches nothing. Exits 4 when the sitting ended, or had not
    # started at the wait's bound.
    engage_attach_held() {
        if [ -n "$sid" ]; then
            printf '✓ the live sitting %s holds conversation %s for %s — attaching to it rather than starting a second\n' "$sid" "$CONV" "$bead"
        else
            printf "✓ conversation %s for %s is held by its sitting %s, which 'gc session list' does not show yet — attaching to it rather than starting a second\n" "$CONV" "$bead" "$sname"
        fi
        printf '  attach: %s\n' "$(engage_attach_later)"
        printf '[debug] conversation=%s sitting=%s holder=%s subject=%s\n' "$CONV" "${sid:-$sname}" "$conv_holder" "$bead" >&2
        [ "$engage_attach" = "1" ] || return 0
        engage_wait
        case "$start_rc" in
            0) attach_rc=0
               gc session attach "$sid" || attach_rc=$?
               engage_after_attach "$attach_rc" ;;
            2) echo "$PROG: engage: the sitting $sname that holds conversation $CONV ended before the reconciler started it (its state in 'gc session list': $start_state), so there is nothing to attach. Re-run to start a new sitting on conversation $CONV: $PROG attach $CONV" >&2
               exit 4 ;;
            *) echo "$PROG: engage: the reconciler has not started $sname after $(engage_dur "$ENGAGE_WAIT_TIMEOUT") (its state in 'gc session list': ${start_state:-unreadable}), so it was not attached; an attach now would launch it without its prompt. Attach once it reads active there: $(engage_attach_later)" >&2
               exit 4 ;;
        esac
    }

    # A live sitting holds this conversation: attach the operator to it.
    if [ "$conv_state" = live ]; then
        live_now=$(live_sittings || printf '[]')
        sid=$(printf '%s' "$live_now" | jq -r --arg a "$conv_holder" --arg c "$CONV" "$CONVERSATION_JQ"'
            [ .[] | select(.alias == $a or .session_name == $a or .id == $a
                           or (({id: $c, assignee: .alias} | conversation_alias) and ({id: $c, assignee: $a} | conversation_alias)))
                  | .id ] | first // empty' 2>/dev/null || true)
        if [ -z "$sid" ]; then
            echo "$PROG: engage: conversation $CONV on $bead reads held by '$conv_holder', but no live session could be named for it. Nothing spawned; re-run: $PROG engage $bead" >&2
            exit 4
        fi
        sname=$(printf '%s' "$live_now" | jq -r --arg s "$sid" '[ .[] | select(.id == $s) | .session_name | select(. != "") ] | first // empty' 2>/dev/null || true)
        [ -n "$sname" ] || sname="$sid"
        engage_attach_held
        return 0
    fi

    # A session still in the list under this conversation's alias that does not
    # hold it keeps the alias, since only a closed session gives one up. A
    # sitting cut short leaves exactly that: its conversation back in the queue
    # and its drained session open until the core reaper closes it a day after
    # its stop. So such a session is closed
    # first and read back gone, and only then is the alias free for the new
    # sitting. A session spawned less than the bind wait ago may be a concurrent
    # engage about to bind the conversation, and one the operator is attached to
    # is a pane in use, so neither is closed here: the spawn below meets its
    # alias, and engage_alias_held waits for its bind and names it. Nor is the
    # session whose alias the conversation is bound to, which holds it even when
    # the listing engage chose by did not show it.
    if ! live_now=$(live_sittings); then
        echo "$PROG: engage: could not read 'gc session list' before starting a sitting on conversation $CONV. Nothing spawned; retry once it answers: $PROG engage $bead" >&2
        exit 4
    fi
    stale_after="${GC_HELM_ENGAGE_BIND_WAIT:-20}"
    case "$stale_after" in ''|*[!0-9]*) stale_after=20 ;; esac
    for _st in $(printf '%s' "$live_now" | jq -r --arg c "$CONV" --arg h "$conv_holder" --argjson w "$stale_after" "$CONVERSATION_JQ"'
            .[] | select({id: $c, assignee: .alias} | conversation_alias)
                | select(.alias != $h)
                | select(.attached != true)
                | select((.created_at | fromdateiso8601? // null) as $t | $t != null and $t < (now - $w))
                | .id' 2>/dev/null); do
        echo "$PROG: engage: session $_st still holds the alias of conversation $CONV without holding it (a sitting cut short) — closing it so a new sitting can take the alias" >&2
        gc session close "$_st" >/dev/null 2>&1 || true
        if ! live_after=$(live_sittings) || printf '%s' "$live_after" | jq -e --arg s "$_st" 'any(.[]; .id == $s)' >/dev/null 2>&1; then
            echo "$PROG: engage: session $_st still holds the alias of conversation $CONV and did not read back closed. Nothing spawned. Close it by hand, then re-run: gc session close $_st && $PROG engage $bead" >&2
            exit 4
        fi
    done

    # Spawn the manual sitting WITHOUT attaching, so the conversation is bound
    # before the session's claim loop runs. Capture the runtime identity from
    # --json, its alias included: a multi-session template stores the alias
    # qualified (<rig>/<binding>.<alias>), and that qualified alias is the actor
    # the session's claim runs as, so it is what the bind writes.
    #
    # The spawn is also the conversation's reservation, which is why it comes
    # before the bind. gascity checks an alias and creates the session that
    # holds it inside one city-wide lock on that alias, and every engage of one
    # conversation spawns under the same alias (its id, or its c- form below),
    # so of two engages of one conversation exactly one creates a sitting. The
    # other is refused at `gc session new` having spawned nothing, and
    # engage_alias_held reports who holds the conversation.
    #
    # `gc session new` resolves a bare template through currentRigContext, which
    # reads GC_DIR (or cwd), NOT the GC_RIG exported above. The converse
    # templates are rig-scoped, with no city-scoped bare converse-<model>, so
    # from the city root (where helm-svc's engage route runs it) the bare name
    # matches no rig and nothing spawns. Point GC_DIR at the subject's rig so the name
    # resolves to that rig's template.
    #
    # gc says WHY a spawn failed only on stderr (template not found in this rig,
    # alias already held, transport down), so it is kept for the message.
    # One spawn attempt under the alias in $1: capture the identity JSON on
    # stdout and gc's reason on stderr (into spawn_why), then parse it.
    engage_spawn() {
        spawn_errf=$(mktemp "${TMPDIR:-/tmp}/gctk-engage-spawn.XXXXXX" 2>/dev/null || printf '')
        if [ -n "$spawn_errf" ]; then
            spawn=$(GC_DIR="$path" gc session new "$template" --alias "$1" --no-attach --json 2>"$spawn_errf" | scrub)
            spawn_why=$(tr '\n' ' ' < "$spawn_errf" 2>/dev/null | cut -c1-300 | sed 's/  */ /g; s/^ *//; s/ *$//')
            rm -f "$spawn_errf" 2>/dev/null || true
        else
            spawn=$(GC_DIR="$path" gc session new "$template" --alias "$1" --no-attach --json 2>/dev/null | scrub)
            spawn_why=""
        fi
        sid=$(printf '%s' "$spawn" | jq -r '.session_id // ""' 2>/dev/null || true)
        sname=$(printf '%s' "$spawn" | jq -r '.session_name // ""' 2>/dev/null || true)
        salias=$(printf '%s' "$spawn" | jq -r '.alias // ""' 2>/dev/null || true)
        swork_dir=$(printf '%s' "$spawn" | jq -r '.work_dir // ""' 2>/dev/null || true)
    }

    # engage_own_alias <assignee> — 0 when <assignee> is the alias this engage
    # asked its spawn for, $session_alias, bare or as gc stores it qualified
    # (<rig>/<binding>.<alias>).
    engage_own_alias() {
        case "$1" in
            "$session_alias"|*/"$session_alias"|*."$session_alias") return 0 ;;
        esac
        return 1
    }

    # The spawn was refused because a session already holds the alias, so this
    # engage spawned nothing. A session's claim runs as its alias, so while the
    # conversation is bound to that alias, the session holding it holds the
    # conversation: it is the conversation's own sitting, whichever engage
    # spawned it, even when the listing engage chose by did not show it yet,
    # and engage_alias_held returns for the caller to attach it. Otherwise the
    # holder is either a concurrent engage that spawned first and is about to
    # bind the conversation, or a sitting left by an engage that stopped between
    # its spawn and its bind. Only the conversation tells them apart: a
    # concurrent engage binds it within one store write of its spawn returning.
    # So wait up to GC_HELM_ENGAGE_BIND_WAIT seconds for its holder to change
    # from the one this engage read. A bind to the alias is the conversation's
    # own sitting again, any other holder is named, and the session is named as
    # left over only when the holder stayed unchanged for the whole wait. Exits
    # 4 on every path but the conversation's own sitting.
    engage_alias_held() {
        _ah_wait="${GC_HELM_ENGAGE_BIND_WAIT:-20}"
        case "$_ah_wait" in ''|*[!0-9]*) _ah_wait=20 ;; esac
        _ah_waited=0
        while :; do
            _ah_row=$(row_now "$CONV")
            _ah_status=$(printf '%s' "$_ah_row" | jq -r '.status // ""' 2>/dev/null || true)
            _ah_owner=$(printf '%s' "$_ah_row" | jq -r '.assignee // ""' 2>/dev/null || true)
            # An unread conversation proves nothing either way, so it keeps the
            # wait going.
            if [ -n "$_ah_status" ] && { [ "$_ah_status" = "closed" ] || [ "$_ah_owner" != "$conv_holder" ] || engage_own_alias "$_ah_owner"; }; then
                break
            fi
            [ "$_ah_waited" -lt "$_ah_wait" ] || break
            sleep 1
            _ah_waited=$((_ah_waited + 1))
        done
        if [ "$_ah_status" = "closed" ]; then
            echo "$PROG: engage: conversation $CONV closed while this engage was spawning, so nothing was spawned." >&2
            exit 4
        fi
        if [ -n "$_ah_status" ] && engage_own_alias "$_ah_owner"; then
            return 0
        fi
        if [ -n "$_ah_status" ] && [ "$_ah_owner" != "$conv_holder" ]; then
            echo "$PROG: engage: conversation $CONV is held by '${_ah_owner:-nobody}', bound while this engage was spawning, so nothing was spawned here. Attach to its sitting instead: $PROG engage $CONV" >&2
            exit 4
        fi
        # The alias engage asked for is the final segment of the qualified
        # alias gc stores (conversation.sh's conversation_alias reads it). A
        # listing that does not answer with a sessions array names no holder
        # and proves none gone.
        _ah_list_ok=1
        _ah_holder=$(session_list_from_store | scrub | jq -er --arg c "$CONV" "$CONVERSATION_JQ"'
            if (type == "object" and ((.sessions // null) | type) == "array")
            then ([ .sessions[]
                    | select((.closed // false) == false)
                    | select({id: $c, assignee: (.alias // "")} | conversation_alias)
                    | (.id // "") | select(. != "") ] | first // "")
            else error("sessions array unreadable") end' 2>/dev/null) || { _ah_list_ok=0; _ah_holder=""; }
        if [ -z "$_ah_status" ]; then
            echo "$PROG: engage: a session${_ah_holder:+ ($_ah_holder)} holds the alias '$session_alias' of conversation $CONV, and the conversation could not be read to tell whether that session bound it. Nothing spawned. Check it with 'gc bd show $CONV', then re-run: $PROG engage $bead" >&2
            exit 4
        fi
        if [ "$_ah_list_ok" = 0 ]; then
            echo "$PROG: engage: a session holds the alias '$session_alias' of conversation $CONV and did not bind it within ${_ah_wait}s, but 'gc session list' could not be read to name it. Nothing spawned; re-run once the session list answers: $PROG engage $bead" >&2
            exit 4
        fi
        if [ -z "$_ah_holder" ]; then
            echo "$PROG: engage: a session held the alias '$session_alias' of conversation $CONV when this engage spawned, and no open session holds it now. Nothing spawned; re-run: $PROG engage $bead" >&2
            exit 4
        fi
        echo "$PROG: engage: session $_ah_holder holds the alias '$session_alias' of conversation $CONV but did not bind it within ${_ah_wait}s, so it is not an engage finishing its bind. It was left by an engage that stopped between spawning it and binding the conversation, and it holds nothing. Nothing spawned. If no other engage of $CONV is still running, close it and re-run: gc session close $_ah_holder && $PROG engage $bead" >&2
        exit 4
    }

    # engage_attach_own <assignee> — attach the operator to the conversation's
    # own sitting: the session holding $session_alias, which <assignee>, the
    # conversation's holder, names. The session list names the session when it
    # shows it, and until it does the start wait finds it by that alias.
    engage_attach_own() {
        conv_holder="$1"; sname="$1"; sid=""; start_alias="$session_alias"
        if _ao_live=$(live_sittings); then
            _ao_row=$(printf '%s' "$_ao_live" | jq -r --arg n "$session_alias" '
                [ .[] | ((.alias // "") | tostring) as $a
                      | select($a == $n or ($a | endswith("/" + $n)) or ($a | endswith("." + $n)))
                      | [(.id // "" | tostring), (.session_name // "" | tostring)] | @tsv ] | first // empty' 2>/dev/null || true)
            if [ -n "$_ao_row" ]; then
                sid=${_ao_row%%"$TAB"*}
                _ao_name=${_ao_row#*"$TAB"}
                [ -z "$_ao_name" ] || sname="$_ao_name"
            fi
        fi
        engage_attach_held
    }

    # Spawn under the bare conversation id first. gascity's ValidateAlias runs
    # before any session is created and refuses an alias matching the session-id
    # syntax `^gc-[0-9]+$`, the reserved `human`, an `s-` prefix, or the 64-char
    # cap, every rejection carrying the sentinel "invalid session alias". A
    # conversation on the gascity rig, whose bead prefix is `gc`, can get an
    # all-numeric id (gc-62297) that reads as a session id and is refused. On
    # that sentinel, retry once under a `c-` prefix no rule can match. Keying on
    # gc's message rather than re-testing ValidateAlias's rules in shell keeps
    # the two from drifting, and covers every rejection reason with one retry.
    session_alias=$CONV
    engage_spawn "$session_alias"
    if [ -z "$sname" ] || [ -z "$sid" ]; then
        case "$spawn_why" in
            *"invalid session alias"*)
                session_alias="c-$CONV"
                engage_spawn "$session_alias" ;;
        esac
    fi
    if [ -z "$sname" ] || [ -z "$sid" ]; then
        case "$spawn_why" in
            *"session alias already exists"*)
                engage_alias_held
                engage_attach_own "$_ah_owner"
                return 0 ;;
        esac
        spawn_hint=""
        case "$spawn_why" in
            *"not found"*) spawn_hint=" The converse templates are rig-scoped: rig '${rig:-?}' ($path) does not carry $template, so a conversation on a bead there cannot be engaged from that rig." ;;
        esac
        echo "$PROG: engage: 'gc session new $template' did not return a session identity — nothing bound.${spawn_why:+ gc said: $spawn_why.}$spawn_hint Output: ${spawn:-<empty>}" >&2
        exit 4
    fi

    # Every post-spawn failure CLOSES the sitting it just spawned before it
    # exits: a converse slot sets nudge="" and idle_timeout=0, so a sitting that
    # never binds a conversation has no idle-claim rescue and would linger
    # holding nothing. Closed, not suspended — a suspended session stays open and
    # keeps its alias reserved, so the advertised re-run would be refused at
    # `gc session new --alias` for as long as it lingered.
    engage_abort() {
        gc session close "$1" >/dev/null 2>&1 || true
        echo "$PROG: engage: $2" >&2
        exit 4
    }
    # The alias the session's claim runs as. A gc whose spawn JSON names none is
    # asked through the session list.
    if [ -z "$salias" ]; then
        salias=$(gc session list --json 2>/dev/null | scrub \
            | jq -r --arg id "$sid" '[ .sessions[]? | objects | select((.id // "") == $id) | .alias // empty ] | first // empty' 2>/dev/null || true)
    fi
    [ -n "$salias" ] || engage_abort "$sid" "spawned $sname, but its alias could not be read, so conversation $CONV has no name to be bound to. The sitting holds nothing and was closed; re-run: $PROG engage $bead"

    # Bind the conversation to the sitting: its assignee becomes the session's
    # alias, so the session's own `gc hook --claim` adopts it (the default work
    # query's assigned tiers) with no pool routing. The bind is CONDITIONAL on
    # the holder and the status engage read — `human` and open for a
    # conversation in the queue, or the alias of a sitting whose session has
    # closed and the status that sitting left — so of two binds from that holder
    # only one lands, and a hand-off or another engage that landed first makes
    # this one miss. So does a dismiss: it closes the conversation and keeps its
    # holder, so a bind guarded on the holder alone would bind a closed
    # conversation, which no claim adopts. A mismatch writes nothing and exits
    # 13, and this engage must not overwrite whoever holds the conversation
    # now. A conversation already assigned to this alias, as a sitting whose
    # session closed leaves it, needs no bind: the new session takes it as its
    # own. No guarded write covers the spawn's window then, so that
    # conversation is read again, and one another writer took or closed in it
    # leaves the sitting nothing to claim, so the sitting is closed.
    if [ "$conv_holder" != "$salias" ]; then
        bind_rc=0
        gc bd update "$CONV" --if-assignee "$conv_holder" --if-status "$conv_status" \
            --unset-metadata gc.session_id --unset-metadata gc.session_name --assignee "$salias" >/dev/null 2>&1 || bind_rc=$?
        if [ "$bind_rc" -eq 13 ]; then
            missed_row=$(row_now "$CONV")
            winner=$(printf '%s' "$missed_row" | jq -r '.assignee // ""' 2>/dev/null || true)
            missed_status=$(printf '%s' "$missed_row" | jq -r '(.status // "") | ascii_downcase' 2>/dev/null || true)
            if [ "$missed_status" = closed ]; then
                engage_abort "$sid" "conversation $CONV was closed while this sitting spawned (a dismiss closes a conversation and keeps its holder), so there is nothing to bind. The sitting $sname this engage spawned holds nothing and was closed; engage the subject to open a fresh conversation: $PROG engage $bead"
            fi
            if [ -n "$missed_row" ] && [ "$winner" = "$conv_holder" ]; then
                engage_abort "$sid" "conversation $CONV went from $conv_status to '${missed_status:-unread}' while this sitting spawned, so the bind wrote nothing. The sitting $sname this engage spawned holds nothing and was closed; re-run to reach the conversation where it is now: $PROG engage $bead"
            fi
            engage_abort "$sid" "conversation $CONV was taken by '${winner:-nobody}' while this sitting spawned — not overwriting. The sitting $sname this engage spawned holds nothing and was closed; re-run to reach the conversation where it is now: $PROG engage $bead"
        fi
        if [ "$bind_rc" -ne 0 ]; then
            engage_abort "$sid" "spawned $sname but the bind of conversation $CONV failed (rc $bind_rc). The sitting holds nothing and was closed; the conversation is unchanged — re-run: $PROG engage $bead"
        fi
    else
        held_row=$(row_now "$CONV")
        assigned=$(printf '%s' "$held_row" | jq -r '.assignee // ""' 2>/dev/null || true)
        held_status=$(printf '%s' "$held_row" | jq -r '(.status // "") | ascii_downcase' 2>/dev/null || true)
        if [ "$assigned" != "$salias" ]; then
            engage_abort "$sid" "conversation $CONV is held by '${assigned:-nobody}', not the sitting '$salias' this engage spawned: another writer took it while the sitting spawned. The sitting holds nothing and was closed; re-run to reach it: $PROG engage $bead"
        fi
        if [ "$held_status" = closed ]; then
            engage_abort "$sid" "conversation $CONV reads closed (a dismiss, or a sign-off, closed it while this sitting spawned), so the sitting $sname has nothing to claim and was closed. Engage the subject to open a fresh conversation: $PROG engage $bead"
        fi
    fi
    bust_cache

    # Human summary on stdout; id-heavy provenance on a single always-on [debug]
    # line on stderr — never gated behind a verbosity flag, since re-running to
    # see it would bind a different conversation.
    _eng_which=existing; [ "$conv_new" = 1 ] && _eng_which=new
    _eng_with=""; [ -n "$engage_skill" ] && _eng_with=" with ${engage_skill##*.}"
    printf '✓ %s%s on %s conversation %s for %s\n' "$template" "$_eng_with" "$_eng_which" "$CONV" "$bead"
    printf '  attach: gc session attach %s\n' "$sid"
    # `engage <subject>` with no concern takes a conversation that already
    # existed, which may be narrower or already-purposed than the fresh
    # discussion the operator meant to start. Name what was taken and offer
    # --reason, so the operator can tell a resumed thread from a new one.
    if [ "$conv_new" = 0 ] && [ -z "$named_conv" ]; then
        conv_title=$(row_now "$CONV" | jq -r '.title // ""' 2>/dev/null || true)
        conv_label="conversation $CONV"
        [ -n "$conv_title" ] && conv_label="conversation \"$conv_title\""
        echo "$PROG: engage: took the $conv_label already on $bead, not a fresh one. To open a new conversation instead, re-run: $PROG engage $bead --reason \"<topic>\""
    fi
    printf '[debug] conversation=%s sitting=%s (%s) alias=%s subject=%s work_dir=%s\n' \
        "$CONV" "$sid" "$sname" "$salias" "$bead" "${swork_dir:-?}" >&2

    # A freshly spawned sitting starts itself from the prompt its launch
    # delivers, and only the reconciler's launch delivers one. `gc session new
    # --no-attach` records the sitting as start-pending. The reconciler then
    # launches it with the rendered converse prompt on argv: every converse
    # provider resolves to prompt_mode=arg, and Claude Code and the codex CLI
    # each take that argument as the session's first user turn. The prompt
    # opens with the entry (converse-entry.sh), which claims the conversation,
    # so the sitting re-checks the premise, preps, and posts its framing with no
    # keystrokes.
    # That holds on the --no-attach board-picker path too, so whoever attaches
    # later finds a started sitting.
    #
    # engage sends the sitting no opening turn of its own. One sent now would
    # find the sitting's first turn still running, and a nudge's default
    # delivery, wait-idle, holds it for an idle boundary rather than enter a
    # running turn, so it would land after the framing as a stale "begin now"
    # and cost one more model turn. What the operator gave engage reaches the
    # sitting through the conversation's ask: cmd_open files a --reason, a
    # seed's body or a lens brief there, and the sitting reads the ask when it
    # claims.
    #
    # The attach path waits for the reconciler's launch first
    # (engage_await_start, above), and attaches only a started sitting.
    # It waits as long as the start takes, because a start on a busy controller
    # can take minutes, and an engage that stops waiting first leaves the
    # operator with no sitting on screen while it starts anyway.
    #
    # A sitting that ends before it starts leaves the conversation bound to its
    # alias, and engage writes nothing to it. The message names an attach of
    # the conversation, which engages it again. That engage spawns under the
    # same alias and takes the conversation with no bind. The board's
    # start-failed mark joins the failed session to the conversation by the
    # session's alias, not by the conversation's assignee.
    start_rc=0
    if [ "$engage_attach" = "1" ]; then
        engage_wait
        if [ "$start_rc" -eq 2 ]; then
            echo "$PROG: engage: the sitting $sname ended before the reconciler started it (its state in 'gc session list': $start_state), so there is nothing to attach. Re-run to start a new sitting on conversation $CONV: $PROG attach $CONV" >&2
            exit 4
        fi
    fi

    # The summary already printed the attach line; on the default path we attach
    # a started sitting. One still unstarted at the bound is left unattached,
    # and the engage fails with exit 4; ENGAGE_WAIT_TIMEOUT says what reaching
    # the bound means.
    if [ "$engage_attach" = "1" ]; then
        if [ "$start_rc" -eq 0 ]; then
            attach_rc=0
            gc session attach "$sid" || attach_rc=$?
            engage_after_attach "$attach_rc"
        else
            echo "$PROG: engage: the reconciler has not started $sname after $(engage_dur "$ENGAGE_WAIT_TIMEOUT") (its state in 'gc session list': ${start_state:-unreadable}), so it was not attached; an attach now would launch it without its prompt. Attach once it reads active there: gc session attach $sid" >&2
            exit 4
        fi
    fi
    return 0
}

# ── The conversation form ────────────────────────────────────────────
# helm_form <verb> [<form-arg>...] — hand the terminal to the conversation form,
# helm-svc's `form` command (services/helm/internal/form). engage runs it on a
# terminal when the command line leaves the concern open, as a bare gc-helm
# does, and attach runs it to find a conversation to return to. The form reads
# and writes through this script, at the path it is given, so what it shows and
# what it files are the verbs' own: it reads `conversations`, saves with
# `open`, starts with `engage --no-attach`, attaches with `engage`, and opens
# the seats with `po --rig <name>` and `mechanik`. GC_HELM_FORM_BIN names the
# binary, which defaults to the one the helm-build order publishes under the
# city's .gc/services/helm. With no binary there, the verb names the
# flag-driven form of the same act and exits 3.
helm_form() {
    _hf_verb="$1"; shift
    _hf_bin="${GC_HELM_FORM_BIN:-}"
    if [ -z "$_hf_bin" ]; then
        _hf_root=$(city_root)
        [ -z "$_hf_root" ] || _hf_bin="$_hf_root/.gc/services/helm/bin/helm-svc"
    fi
    if [ -z "$_hf_bin" ] || [ ! -x "$_hf_bin" ]; then
        echo "$PROG: $_hf_verb: the conversation form is helm-svc's, and no helm-svc binary is built${_hf_bin:+ at $_hf_bin}. Build it with \"\$(gc gc-toolkit scripts-dir)/gc-build.sh\" helm, or name everything on the command line: $PROG engage <subject> --reason \"<question>\" --no-input to start, $PROG attach <conversation> to return, $PROG po --rig <name> to open a rig's Product Owner, $PROG mechanik to attach to mechanik." >&2
        exit 3
    fi
    exec "$_hf_bin" form --helm "$SCRIPT_PATH" --models "$(engage_list_models | paste -s -d, - 2>/dev/null || true)" "$@"
}

# ── Verb: conversations ──────────────────────────────────────────────
# Where each open conversation stands, for a person returning to one and for
# the conversation form, which reads it while the operator types. Read-only.
# Each row is $READINESS_JQ's: the conversation's id, rig, subject, title,
# status and holder, its state as engage reads it (live, queue or left), the
# session of a live sitting with its state and whether a terminal is attached,
# and its readiness (queued, starting, preparing, ready or ended).
#   conversations          every open conversation in the city's stores that a
#                          sitting holds or held, or that waits in the
#                          operator's queue, each with its subject's title.
#                          --json prints {conversations, rigs, seats,
#                          roster_unread, unread}: rigs are the rigs a new
#                          topic can be filed in, each with its name and
#                          prefix, whether it carries converse and whether it
#                          is suspended, seats are the seats the operator sits
#                          with, mechanik and the po of each of those rigs,
#                          each with its session (SEATS_JQ), roster_unread
#                          says the agent roster, which names the seats'
#                          sessions, could not be read, so no seat is listed,
#                          and unread names each rig whose store could not be
#                          read, because it did not answer or its ledger is
#                          not there. A roster or a store that could not be
#                          read exits 4 after the list.
#   conversations <ref>    the subject <ref> names, resolved as engage resolves
#                          it, and where a conversation about it would be held:
#                          {ref, subject: {id, title, status, issue_type,
#                          priority, rig}, gate, conversation, closed,
#                          refusal, rig_suspended, conversations, holds,
#                          holds_read}. refusal says why no sitting can start
#                          there, so nothing is to be filed (sitting_refusal),
#                          and is empty otherwise. rig_suspended says the
#                          subject's rig is suspended, which is no refusal:
#                          no sitting starts there, and a conversation filed
#                          waits in the queue until the rig resumes. holds is
#                          what holds the subject (holding_rows). --from names
#                          the bead the reference was reached from, as the
#                          form names the subject whose
#                          holds listed a gate: a gate several open beads wait
#                          on is about that bead while it is one of them, and
#                          one that no longer holds it is refused. Without
#                          --from such a gate is about the bead whose wait on
#                          it is oldest, as engage takes it (take_bead).
#                          A bare PR number more than one live
#                          anchor records prints {ref, candidates} instead,
#                          each anchor with its title and rig, so the person
#                          picks one. A reference that does not resolve is
#                          refused as engage refuses it, exit 4.
cmd_conversations() {
    _cv_ref=""; _cv_json=0; _cv_from=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) _cv_json=1; shift ;;
            --from=*) _cv_from="${1#--from=}"; shift ;;
            --from) shift; [ $# -gt 0 ] || { echo "$PROG: conversations: --from requires a value" >&2; exit 2; }
                    _cv_from="$1"; shift ;;
            -h|--help) usage; exit 0 ;;
            -*) echo "$PROG: conversations: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$_cv_ref" ] || { echo "$PROG: conversations takes one reference" >&2; exit 2; }
               _cv_ref="$1"; shift ;;
        esac
    done
    if [ -n "$_cv_from" ] && [ -z "$_cv_ref" ]; then
        echo "$PROG: conversations: --from names the bead a gate was reached from, so it needs the gate: $PROG conversations <gate> --from <bead>." >&2
        exit 2
    fi
    if [ -n "$_cv_ref" ]; then
        conversations_about "$_cv_ref"
    else
        conversations_all
    fi
}

# conversations_in_store <rig> <db> — the open conversations in one rig's store,
# each as {rig, subject_title, row}: the rig's name, the title of the
# conversation's subject, and the conversation's own row, which
# conversations_all reads as a $READINESS_JQ row once it has read the sessions.
# Every task in a live status is read in one listing, and the shared rule
# ($CONVERSATION_JQ's conversation) picks the conversations out by their own
# rows. So a conversation waiting in the queue, one its sitting claimed, and
# one bound to a sitting that ended before it claimed it are each found,
# whatever the state of a session. The listing is --brief, because a row is
# read for its assignee, edges, title and metadata, never its description.
# Returns 1 when a read did not answer.
conversations_in_store() {
    _cis_all=$(bd_rows list --db "$2" --status open,in_progress,blocked,deferred,hooked,pinned --type task --brief --limit 0) || return 1
    _cis_rows=$(printf '%s' "$_cis_all" | jq -c "$CONVERSATION_JQ"'
        [ .[] | objects
            | select(((.status // "open") | tostring | ascii_downcase) != "closed")
            | select(conversation) ]' 2>/dev/null) || return 1
    _cis_subj=$(printf '%s' "$_cis_rows" | jq -r "$CONVERSATION_JQ"'[ .[] | conversation_subjects[0] ] | unique | join(",")' 2>/dev/null) || return 1
    _cis_titles='[]'
    if [ -n "$_cis_subj" ]; then
        _cis_titles=$(bd_rows list --db "$2" --id "$_cis_subj" --all --limit 0) || _cis_titles='[]'
    fi
    printf '%s' "$_cis_rows" | jq -c --arg rig "$1" --argjson subj "$_cis_titles" "$CONVERSATION_JQ"'
        ([ $subj[] | objects | {key: ((.id // "") | tostring), value: ((.title // "") | tostring)} ] | from_entries) as $t
        | [ .[] | {rig: $rig, subject_title: ($t[conversation_subjects[0] // ""] // ""), row: .} ]' 2>/dev/null
}

# conversations_all — `conversations` with no reference: every rig's store is
# read at once, each in a subshell of its own, so the list costs about one
# store's reads. A rig whose ledger is not there to read is named in unread with
# the stores that did not answer, since a read pinned to it with --db cannot be
# made, and a list that left it out would read as complete. For the same reason
# a store counts as read only once its subshell has written its list and then
# marked it done, and this shell counts the rigs itself: a read that failed, or
# a list or mark that could not be written, names the store in unread. A rig
# list that cannot be written, or lists that do not put together into one,
# list nothing and fail.
conversations_all() {
    enumerate_rigs
    _ca_tmp=$(mktemp -d "${TMPDIR:-/tmp}/gc-helm-conversations.XXXXXX") \
        || { echo "$PROG: conversations: could not make a scratch directory under ${TMPDIR:-/tmp}" >&2; exit 3; }
    # One rig a line, its name and path apart by the unit separator, which read
    # never collapses as it does a tab, so an empty name stays empty.
    if ! printf '%s' "$RIGS" | jq -r '.[] | [((.name // "") | gsub("[[:cntrl:]]"; " ")), (.path // "")] | join("\u001f")' > "$_ca_tmp/rigs" 2>/dev/null; then
        rm -rf "$_ca_tmp"
        echo "$PROG: conversations: could not write the list of rigs under ${TMPDIR:-/tmp}, so no store was read. Nothing listed." >&2
        exit 3
    fi
    _ca_us=$(printf '\037')
    _ca_i=0
    while IFS="$_ca_us" read -r _ca_name _ca_path; do
        _ca_i=$((_ca_i + 1))
        [ -n "$_ca_path" ] && [ -d "$_ca_path/.beads" ] || continue
        ( conversations_in_store "${_ca_name:-$_ca_path}" "$_ca_path/.beads" > "$_ca_tmp/$_ca_i.json" 2>/dev/null \
            && : > "$_ca_tmp/$_ca_i.done" ) &
    done < "$_ca_tmp/rigs"
    wait
    # Each rig again, by this shell's own count: a list marked done is read,
    # and every other rig is unread.
    set --
    _ca_unread_names=""
    _ca_i=0
    while IFS="$_ca_us" read -r _ca_name _ca_path; do
        _ca_i=$((_ca_i + 1))
        if [ -f "$_ca_tmp/$_ca_i.done" ]; then
            set -- "$@" "$_ca_tmp/$_ca_i.json"
        else
            _ca_unread_names="$_ca_unread_names${_ca_name:-${_ca_path:-a rig with no name}}
"
        fi
    done < "$_ca_tmp/rigs"
    # Each list is one array, so a list that holds anything else, or nothing,
    # fails the whole read.
    _ca_rows='[]'
    if [ $# -gt 0 ]; then
        _ca_rows=$(jq -cs --argjson n "$#" 'if length == $n and all(.[]; type == "array") then add else error("a list did not read") end' "$@" 2>/dev/null) \
            || _ca_rows=""
    fi
    _ca_unread=$(printf '%s' "$_ca_unread_names" | jq -Rsc 'split("\n") | map(select(. != ""))' 2>/dev/null) || _ca_unread=""
    rm -rf "$_ca_tmp"
    if [ -z "$_ca_rows" ] || [ -z "$_ca_unread" ]; then
        echo "$PROG: conversations: the lists the stores answered could not be put together into one, so the list would not be complete. Nothing listed." >&2
        exit 4
    fi
    # Read after the rows: engage spawns a sitting before it binds the
    # conversation, so a row that shows the bind finds the sitting.
    if ! _ca_list=$(session_list_from_store) || ! _ca_live=$(live_sittings_in "$_ca_list"); then
        echo "$PROG: conversations: could not read 'gc session list', so which sittings are live is unknown. Nothing listed." >&2
        exit 4
    fi
    if ! _ca_rows=$(printf '%s' "$_ca_rows" | jq -c --argjson live "$_ca_live" "$CONVERSATION_JQ$SITTING_JQ$READINESS_JQ"'
            [ .[] | .rig as $rig | .subject_title as $t | .row | readiness_row($live; $rig) + {subject_title: $t} ]' 2>/dev/null); then
        echo "$PROG: conversations: the lists the stores answered could not be put together into one, so the list would not be complete. Nothing listed." >&2
        exit 4
    fi
    if [ "$_cv_json" = 1 ]; then
        # The rigs a new topic can be filed in: every rig but the city's own
        # store, with the prefix `gc rig list` gives it, so the form can match
        # a rig typed by its prefix, and sitting_refusal's two rig checks.
        _ca_rigs='[]'
        for _ca_r in $(printf '%s' "$RIGS" | jq -r '.[] | select((.hq // false) | not) | .name // empty' 2>/dev/null); do
            _ca_conv=false; _ca_susp=false
            if rig_carries_converse "$_ca_r"; then _ca_conv=true; fi
            if [ "$(rig_suspended "$_ca_r")" = "true" ]; then _ca_susp=true; fi
            _ca_pfx=$(printf '%s' "$RIGS" | jq -r --arg n "$_ca_r" 'first(.[] | select(.name == $n) | .prefix // "") // ""' 2>/dev/null || true)
            _ca_rigs=$(printf '%s' "$_ca_rigs" | jq -c --arg n "$_ca_r" --arg p "$_ca_pfx" --argjson c "$_ca_conv" --argjson s "$_ca_susp" '. + [{name: $n, prefix: $p, converse: $c, suspended: $s}]')
        done
        # The seats, for the form's People page: mechanik, and the po of each of
        # those rigs, each by the name the agent roster gives its session, read
        # once with the rigs' converse, and each with its session from the
        # session list the conversations were read from. Only the roster's
        # names are passed on, which keeps the argument small in a city of many
        # agents. A roster that cannot be read names no seat, so none is
        # listed, and the conversations and the rigs still are.
        converse_roster
        _ca_roster=""
        if [ -n "${_CONVERSE_ROSTER:-}" ]; then
            _ca_roster=$(printf '%s' "$_CONVERSE_ROSTER" | jq -c '{agents: [.agents[]? | objects | {name, dir, qualified_name}]}' 2>/dev/null) || _ca_roster=""
        fi
        _ca_seats='[]'; _ca_roster_unread=false
        if [ -z "$_ca_roster" ]; then
            _ca_roster_unread=true
            echo "$PROG: conversations: could not read 'gc agent list', which gives each seat's session its name, so no seat is listed." >&2
        elif ! _ca_seats=$(printf '%s' "$_ca_list" | scrub | jq -c --argjson rigs "$_ca_rigs" --argjson roster "$_ca_roster" --arg mechanik "$MECHANIK_TEMPLATE" --arg po "$PO_TEMPLATE" "$SEAT_NAMES_JQ$SEATS_JQ" 2>/dev/null); then
            echo "$PROG: conversations: the seats could not be read from 'gc session list'. Nothing listed." >&2
            exit 4
        fi
        jq -nc --argjson c "$_ca_rows" --argjson r "$_ca_rigs" --argjson s "$_ca_seats" --argjson ru "$_ca_roster_unread" --argjson u "$_ca_unread" \
            '{conversations: $c, rigs: $r, seats: $s, roster_unread: $ru, unread: $u}'
        [ "$_ca_roster_unread" = false ] || exit 4
    else
        printf '%s' "$_ca_rows" | jq -r '
            def rank: {"ready": 0, "preparing": 1, "starting": 2, "ended": 3, "queued": 4}[.readiness] // 5;
            if length == 0 then "No open conversation."
            else sort_by(rank, .created_at) | .[]
                 | "\(.readiness)\(if .session.attached == true then " (attached)" else "" end)\t\(.id)\t\(.rig)\t\(.title)"
                   + (if .subject_title != "" and .subject_title != .title then "\t(on \(.subject): \(.subject_title))" else "\t(on \(.subject))" end)
            end'
        [ "$_ca_unread" = "[]" ] || echo "$PROG: conversations: the store of $(printf '%s' "$_ca_unread" | jq -r 'join(", ")') could not be read, so its conversations are not listed." >&2
    fi
    [ "$_ca_unread" = "[]" ] || exit 4
    return 0
}

# conversations_about <ref> — `conversations <ref>`: the subject engage would
# hold a conversation about, read the way engage reads it.
conversations_about() {
    _cb_ref="$1"
    enumerate_rigs
    pr_reference "$_cb_ref"
    if [ -n "$PR_NUM" ]; then
        pr_reference_anchors "$PR_NUM" "$PR_URL"
        _cb_n=$(printf '%s\n' "$PR_ANCHORS" | awk 'NF{c++} END{print c + 0}')
        if [ "$_cb_n" -eq 0 ]; then
            echo "$PROG: conversations: no open bead records PR #$PR_NUM${PR_URL:+ ($PR_URL)}. If it merged its anchor is closed and there is nothing live to hold a conversation about; otherwise pass the live bead id." >&2
            exit 4
        fi
        if [ "$_cb_n" -gt 1 ]; then
            _cb_cands='[]'
            for _cb_a in $PR_ANCHORS; do
                _cb_apath=$(rig_path_for_bead "$_cb_a")
                _cb_arow=$(bd_rows list ${_cb_apath:+--db "$_cb_apath/.beads"} --id "$_cb_a" --all --limit 0 2>/dev/null || printf '[]')
                _cb_cands=$(printf '%s' "$_cb_cands" | jq -c --arg id "$_cb_a" --arg rig "$(rig_name_for_bead "$_cb_a")" --argjson row "$_cb_arow" '
                    . + [ ([ $row[]? | objects | select((.id // "") == $id) ] | first // {}) as $r
                          | {id: $id, rig: $rig, title: (($r.title // "") | tostring),
                             status: (($r.status // "") | tostring)} ]')
            done
            if [ "$_cv_json" = 1 ]; then
                jq -nc --arg ref "$_cb_ref" --argjson c "$_cb_cands" '{ref: $ref, candidates: $c}'
            else
                echo "PR #$PR_NUM is recorded by more than one live anchor; name the one you mean:"
                printf '%s' "$_cb_cands" | jq -r '.[] | "  \(.id)\t\(.rig)\t\(.title)"'
            fi
            return 0
        fi
        _cb_bead=$(printf '%s' "$PR_ANCHORS" | awk 'NF{print; exit}')
    else
        resolve_live_subject "$_cb_ref"
        _cb_bead="$RESOLVED_SUBJECT"
    fi

    conversations_pin "$_cb_bead"
    verify_subject "$_cb_bead" conversations "Nothing read." || exit $?
    take_bead conversations "Nothing read." "$_cv_from"
    _cb_gate="$TAKE_GATE"; _cb_conv="$TAKE_CONV"; _cb_closed='null'
    if [ -n "$_cb_conv" ] && [ "$(printf '%s' "$VS_ROW" | jq -r '(.status // "") | tostring | ascii_downcase' 2>/dev/null || true)" = closed ]; then
        _cb_closed=$(jq -nc --arg id "$_cb_conv" --arg said "$(engage_closed_said "$VS_ROW" "$TAKE_BEAD")" '{id: $id, said: $said}')
    fi
    if [ "$TAKE_BEAD" != "$_cb_bead" ]; then
        _cb_bead="$TAKE_BEAD"
        conversations_pin "$_cb_bead"
        verify_subject "$_cb_bead" conversations "Nothing read." || exit $?
    fi
    _cb_row="$VS_ROW"
    _cb_refusal=""; _cb_suspended=false
    if [ "$(printf '%s' "$_cb_row" | jq -r '(.status // "") | tostring | ascii_downcase' 2>/dev/null || true)" = closed ]; then
        _cb_refusal="$_cb_bead is closed — a settled item on the DONE band, which takes no new conversation. To act on it, re-open it or file fresh work."
    elif ! sitting_refusal "$_cb_bead" "$rig" "$path"; then
        # A suspended rig starts no sitting, and a conversation filed there
        # waits in the queue until the rig resumes, so the suspension is said
        # on its own and refuses nothing. A rig suspended with its controller
        # down reads only as suspended, since no sitting is started there.
        if [ "$SITTING_SUSPENDED" = true ]; then
            _cb_suspended=true
        else
            _cb_refusal="$SITTING_REFUSAL"
        fi
    fi
    if ! _cb_convs=$(bead_conversations "$_cb_bead") || ! _cb_live=$(live_sittings); then
        echo "$PROG: conversations: could not read the conversations on $_cb_bead or 'gc session list'." >&2
        exit 4
    fi
    _cb_rows=$(printf '%s' "$_cb_convs" | jq -c --arg rig "$rig" --argjson live "$_cb_live" \
        "$CONVERSATION_JQ$SITTING_JQ$READINESS_JQ"'[ .[] | readiness_row($live; $rig) ]' 2>/dev/null || printf '[]')
    _cb_holds='[]'; _cb_holds_read=true
    if _cb_hold_tsv=$(holding_rows "$_cb_bead"); then
        _cb_holds=$(printf '%s' "$_cb_hold_tsv" | jq -Rsc 'split("\n") | map(select(. != "") | split("\t")
            | {held: (.[0] // ""), id: (.[1] // ""), title: (.[2:] | join("\t"))})' 2>/dev/null || printf '[]')
    else
        _cb_holds_read=false
    fi
    _cb_out=$(jq -nc --arg ref "$_cb_ref" --arg rig "$rig" --argjson row "$_cb_row" --arg gate "$_cb_gate" \
        --arg conv "$_cb_conv" --argjson closed "$_cb_closed" --arg refusal "$_cb_refusal" \
        --argjson suspended "$_cb_suspended" \
        --argjson convs "$_cb_rows" --argjson holds "$_cb_holds" --argjson holds_read "$_cb_holds_read" '
        {ref: $ref,
         subject: {id: (($row.id // "") | tostring), title: (($row.title // "") | tostring),
                   status: (($row.status // "") | tostring), issue_type: (($row.issue_type // "") | tostring),
                   priority: ($row.priority // null), rig: $rig},
         gate: $gate, conversation: $conv, closed: $closed, refusal: $refusal, rig_suspended: $suspended,
         conversations: $convs, holds: $holds, holds_read: $holds_read}')
    if [ "$_cv_json" = 1 ]; then
        printf '%s\n' "$_cb_out"
        return 0
    fi
    printf '%s' "$_cb_out" | jq -r '
        "\(.subject.id) in rig \(.subject.rig) (\(.subject.issue_type) · \(.subject.status)) — \(.subject.title)",
        (if .refusal != "" then "  no sitting can start: \(.refusal)" else empty end),
        (if .rig_suspended then "  no sitting can start while rig \(.subject.rig) is suspended, and a conversation filed now waits in the queue until it resumes: gc rig resume \(.subject.rig)" else empty end),
        (if .closed != null then "  \(.closed.said)" else empty end),
        (if (.conversations | length) == 0 then "  no open conversation"
         else (.conversations[] | "  \(.readiness)\(if .session.attached == true then " (attached)" else "" end)\t\(.id)\t\(.title)") end),
        (.holds[] | "  held: \(.held)\(if .id != "" then " by \(.id)" else "" end) — \(.title)"),
        (if .holds_read then empty else "  what holds it did not read" end)'
}

# conversations_pin <bead> — read the bead's own store, as engage does: set path
# and rig from its id prefix and export BEADS_DIR and GC_RIG for them. A prefix
# no rig carries is refused, exit 4.
conversations_pin() {
    path=$(rig_path_for_bead "$1")
    if [ -z "$path" ]; then
        echo "$PROG: conversations: '$1' — its id prefix '${1%%-*}' matches no rig in 'gc rig list'." >&2
        exit 4
    fi
    rig=$(rig_name_for_bead "$1")
    [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"
    [ -n "$rig" ] && export GC_RIG="$rig"
    return 0
}

# ── Verb: attach ─────────────────────────────────────────────────────
# Return to a conversation. With an id it is engage's attach: a live sitting is
# attached once it has started, a conversation whose sitting ended or that waits
# in the queue is held in a new sitting first, and the tab prints how the
# sitting ended when it does. With none, on a terminal, the conversation form
# opens on the conversations to return to, by topic and readiness, those no
# terminal is attached to first (helm_form). Without a terminal it names the
# list instead.
cmd_attach() {
    _at_ref=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -*) echo "$PROG: attach: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$_at_ref" ] || { echo "$PROG: attach takes one conversation" >&2; exit 2; }
               _at_ref="$1"; shift ;;
        esac
    done
    if [ -n "$_at_ref" ]; then
        cmd_engage "$_at_ref" --no-input
        return 0
    fi
    if [ -t 0 ] || [ -n "${GC_HELM_ASSUME_TTY:-}" ]; then
        helm_form attach --return
    fi
    echo "$PROG: attach needs a conversation id without a terminal; list them with: $PROG conversations" >&2
    exit 2
}

# ── The seats: a rig's po, and mechanik ──────────────────────────────
# The seats the operator sits with, each opened in one step, each a row of the
# People page in engage's form and each a command of its own. A rig's po, the
# operator's prioritization partner for that rig's work, is the rig's
# on-demand named session, which a sitting opens and a drain-ack ends.
# Mechanik, the operator's standing conversation, is one named session for the
# city, which the controller keeps running. Each verb is Gas City's attach on
# the seat's session, which owns the seat's start and the wait for it: it
# attaches to a running session, and asks the city's controller to start one
# that is not running, so the agent takes its prompt as its first message, then
# attaches once the session runs (docs/gascity/human-engagement.md, "What an
# attach does to a session that is not running").
#
# Gas City names a seat's session as it names the agent that runs it, after
# the binding the city imports the pack under, and a rig's po after its rig as
# well: <binding>.mechanik and <rig>/<binding>.po. The binding is the city's to
# choose, so the verbs and the People page take a seat's name from the city's
# agent roster (SEAT_NAMES_JQ), and know a seat only by its template, the agent
# pack.toml's [[named_session]] stanza names.
PO_TEMPLATE="po"
MECHANIK_TEMPLATE="mechanik"

# $SEAT_NAMES_JQ — defines seat_names($template; $rig): from the agent roster
# given as input (`gc agent list --json`), the qualified name of each agent
# named $template in the rig named $rig, or of the city's own for an empty
# $rig, once each. A seat's named session takes its agent's qualified name,
# because pack.toml gives the session no name of its own. One name is the
# seat's. None means the city runs no such seat there, and with several, which
# of them is the seat is not known.
SEAT_NAMES_JQ='
  def seat_names($template; $rig):
    [ .agents[]? | objects
      | select(((.name // "") | tostring) == $template and ((.dir // "") | tostring) == $rig)
      | (.qualified_name // "") | tostring | select(. != "") ] | unique;
'

# $SEATS_JQ — the seats, as `conversations --json` lists them for the People
# page, from a `gc session list --json` given as input, with the rigs a new
# topic can be filed in as $rigs, which leave out the city's HQ, the agent
# roster as $roster and the seats' templates as $mechanik and $po. It runs after
# $SEAT_NAMES_JQ. Mechanik comes first, then each rig's po in the order the
# rigs are listed, each as {seat, rig, session}: seat is the verb that opens
# it, rig is the po's rig by its name and empty for mechanik, and session is
# the open session the list holds under the seat's name, {id, name, state,
# attached, created_at} with Gas City's own state, or null when it holds none,
# as for a po that has never run. A seat the roster gives no name, or several,
# is left out, since its verb refuses it.
SEATS_JQ='
  [ .sessions[] | objects
    | select((.closed // false) != true)
    | select(((.state // "") | tostring) != "closed") ] as $open
  | def seat($seat; $rig; $names):
      if ($names | length) == 1 then
        [ {seat: $seat, rig: $rig,
           session: (first($open[] | select(((.alias // "") | tostring) == $names[0])
                     | {id: ((.id // "") | tostring), name: ((.session_name // "") | tostring),
                        state: ((.state // "") | tostring), attached: ((.attached // false) == true),
                        created_at: ((.created_at // "") | tostring)}) // null)} ]
      else [] end;
  seat("mechanik"; ""; $roster | seat_names($mechanik; ""))
  + [ $rigs[] | .name as $r | seat("po"; $r; $roster | seat_names($po; $r))[] ]
'

# cmd_seat <verb> <template> <name> [<arg>...] — attach the terminal to the
# seat's session, and once it comes back, name how to return. The session is
# the one the agent roster names for the seat's template (SEAT_NAMES_JQ). po
# takes --rig <name>, the rig whose po it is, named exactly, as open
# --new-subject --rig takes it, and refuses (exit 4) a rig the city has not,
# the city's HQ, where Gas City stamps no rig's named session, or a suspended
# rig, where it starts no session. mechanik takes no argument. A roster that
# cannot be read, or that names no session for the seat or several, exits 4
# attaching nothing, and so does a failed attach, after gc has said why.
cmd_seat() {
    _seat_verb="$1"; _seat_tmpl="$2"; _seat_name="$3"; shift 3
    _seat_rig=""; _seat_rig_set=0
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --rig=*|--rig)
                [ "$_seat_verb" = po ] || { echo "$PROG: $_seat_verb: unknown flag '$1': mechanik is one for the city" >&2; exit 2; }
                case "$1" in
                    --rig=*) _seat_rig="${1#--rig=}"; shift ;;
                    *) shift; [ $# -gt 0 ] || { echo "$PROG: po: --rig requires a value" >&2; exit 2; }
                       _seat_rig="$1"; shift ;;
                esac
                _seat_rig_set=1 ;;
            -*) echo "$PROG: $_seat_verb: unknown flag '$1'" >&2; exit 2 ;;
            *) echo "$PROG: $_seat_verb takes no argument" >&2; exit 2 ;;
        esac
    done
    _seat_again="$PROG $_seat_verb"
    if [ "$_seat_verb" = po ]; then
        if [ "$_seat_rig_set" = 0 ] || [ -z "$_seat_rig" ]; then
            echo "$PROG: po: each rig has its own Product Owner, so name the rig: $PROG po --rig <name>" >&2
            exit 2
        fi
        enumerate_rigs
        _seat_row=$(printf '%s' "$RIGS" | jq -c --arg n "$_seat_rig" 'first(.[] | select(.name == $n)) // empty' 2>/dev/null)
        _seat_known=$(printf '%s' "$RIGS" | jq -r '[.[] | select((.hq // false) | not) | .name] | join(", ")' 2>/dev/null)
        if [ -z "$_seat_row" ]; then
            echo "$PROG: po: --rig '$_seat_rig' matches no rig in 'gc rig list' (known: $_seat_known). Nothing attached." >&2
            exit 4
        fi
        if [ "$(printf '%s' "$_seat_row" | jq -r '.hq // false' 2>/dev/null)" = true ]; then
            echo "$PROG: po: '$_seat_rig' is the city's HQ in 'gc rig list', not a rig, and Gas City starts a rig's named session only in a rig, so the HQ has no Product Owner. Name a rig: $_seat_known. Nothing attached." >&2
            exit 4
        fi
        if [ "$(printf '%s' "$_seat_row" | jq -r '.suspended // false' 2>/dev/null)" = true ]; then
            echo "$PROG: po: rig '$_seat_rig' is suspended, and Gas City starts no session in a suspended rig, so its Product Owner cannot start until the rig resumes (gc rig resume $_seat_rig). Nothing attached." >&2
            exit 4
        fi
        _seat_name="the Product Owner of $_seat_rig"
        _seat_again="$PROG po --rig $_seat_rig"
    fi
    converse_roster
    _seat_names=""
    if [ -n "${_CONVERSE_ROSTER:-}" ]; then
        _seat_names=$(printf '%s' "$_CONVERSE_ROSTER" | jq -c --arg t "$_seat_tmpl" --arg r "$_seat_rig" "$SEAT_NAMES_JQ"'seat_names($t; $r)' 2>/dev/null) || _seat_names=""
    fi
    _seat_where="for the city"
    [ -z "$_seat_rig" ] || _seat_where="in rig '$_seat_rig'"
    case "$(printf '%s' "$_seat_names" | jq -r 'length' 2>/dev/null)" in
        1) _seat=$(printf '%s' "$_seat_names" | jq -r '.[0]') ;;
        0) echo "$PROG: $_seat_verb: 'gc agent list' names no $_seat_tmpl agent $_seat_where, so the city runs no session for $_seat_name. Nothing attached." >&2
           exit 4 ;;
        ''|*[!0-9]*)
           echo "$PROG: $_seat_verb: could not read 'gc agent list', which gives the session of $_seat_name its name, so nothing was attached. Re-run: $_seat_again" >&2
           exit 4 ;;
        *) echo "$PROG: $_seat_verb: 'gc agent list' names more than one $_seat_tmpl agent $_seat_where ($(printf '%s' "$_seat_names" | jq -r 'join(", ")')), so the session of $_seat_name is not known. Nothing attached." >&2
           exit 4 ;;
    esac
    _seat_rc=0
    gc session attach "$_seat" || _seat_rc=$?
    if [ "$_seat_rc" -ne 0 ]; then
        echo "$PROG: $_seat_verb: gc session attach $_seat exited $_seat_rc, so $_seat_name was not attached. Re-run: $_seat_again" >&2
        exit 4
    fi
    printf '\nReturn to %s with: %s\n' "$_seat_name" "$_seat_again"
}

# ── Dispatch ─────────────────────────────────────────────────────────
case "${1:-}" in
    open)          shift; cmd_open "$@" ;;
    engage)        shift; cmd_engage "$@" ;;
    resolve)       shift; cmd_resolve "$@" ;;
    dismiss)       shift; cmd_dismiss "$@" ;;
    handback)      shift; cmd_handback "$@" ;;
    conversations) shift; cmd_conversations "$@" ;;
    attach)        shift; cmd_attach "$@" ;;
    po)            shift; cmd_seat po "$PO_TEMPLATE" "the Product Owner" "$@" ;;
    mechanik)      shift; cmd_seat mechanik "$MECHANIK_TEMPLATE" mechanik "$@" ;;
    board)         echo "$PROG: the board moved to 'helm-svc board' (services/helm)" >&2; exit 2 ;;
    -h|--help|help) usage; exit 0 ;;
    # A bare gc-helm on a terminal is engage's form, the way in. Without a
    # terminal it names the verbs and exits 2, so no script blocks on a form.
    "")            if [ -t 0 ] || [ -n "${GC_HELM_ASSUME_TTY:-}" ]; then
                       cmd_engage
                   fi
                   echo "$PROG: name a verb (try: engage, attach, po, mechanik, conversations, open, dismiss, handback, resolve, help); on a terminal, a bare $PROG opens engage's form" >&2; usage; exit 2 ;;
    *)             echo "$PROG: unknown verb '${1:-}' (try: po, mechanik, open, engage, attach, conversations, dismiss, handback, resolve, help; the board is 'helm-svc board')" >&2; usage; exit 2 ;;
esac
