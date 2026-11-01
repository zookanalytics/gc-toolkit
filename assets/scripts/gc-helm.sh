#!/bin/sh
# gc-helm.sh — the helm verbs: the WRITE verbs, and the read-only resolve and
# unplaced.
# Job: write the operator-facing state the helm board renders, and the
# operator's steering moves. The board itself is `helm-svc board`
# (services/helm); this script renders nothing.
# Verbs (full grammar and per-verb notes in usage(), `gc-helm --help`): the
# write verbs open, engage, react, takeaway, park, priority, dismiss, handback,
# accept, and the read-only resolve and unplaced. open, engage and react take a
# <subject> (a bead id, a PR number or URL, or a superseded id) and resolve it to
# the live bead that owns the work by metadata and the graph, never a title; an
# unresolvable or ambiguous reference is refused and nothing is filed.
# Callers: tmux-pick-helm.sh (engage), operator-intake.sh (react, resolve,
# open), helm-svc's POST routes via GC_HELM_OPEN_TOOL (open, engage, accept,
# dismiss — open's stderr/stdout sentences are parsed by
# services/helm/internal/server, guarded by open_parity_test.go), converse
# (takeaway, handback) and the proactive worker (takeaway), the placement
# sitting (unplaced), operators by hand (park, priority).
# Exit codes: 0 ok, 2 usage, 3 environment (jq/gc missing, rigs
# unenumerable, no city root or flock for Accept's lock — each failure names
# its own operator move),
# 4 verb runtime failure (bead not found / unverifiable / filing failed /
# a --route, or a takeaway headline or disposition, that will not stamp / a
# pour stamp a release leaves on a bead held for placement / an unplaced list
# missing a store that did not answer / a priority move that did not read
# back / an Accept refused or held by another Accept on the bead),
# 5 react no-op: the subject already has an open first reaction, or a live owner
# owns its reaction, so nothing was filed (a first reaction happens once at a
# time) — distinct from 4 so an intake caller files its own conversation
# instead of reading a skip as a dispatched reaction.
# 6 react no-op: a live workflow already drives the subject, so nothing was
# filed (a first reaction never races work in flight) — distinct from 5 so the
# intake caller names the cause in the conversation it files.
# 7 react no-op: the subject already has a route or a deferred-dispatch arm, so
# nothing was filed (a first reaction never second-guesses a dispatch already
# decided) — distinct from 5 and 6 so the intake caller names the cause in the
# conversation it files.

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
  gc-helm open  <bead-id> [--reason "..."] [--body "..."] [--allow-duplicate] [--json]  file a conversation about the bead in the operator's queue, for the operator to engage; a second concern joins the bead's conversation already in the queue unless --allow-duplicate files a fresh one; --json prints {subject,conversation,filed}
  gc-helm engage [<subject>] [--subject <id>] [--new-subject [--rig <name>]] [--model <variant>] [--skill <name>] [--reason "..." | --template <key>] [--no-input] [--no-attach]  hold a conversation about the bead in a converse sitting and attach: attach to its live sitting, or take its conversation from the queue, or file one, then spawn a sitting named for it. Pointed at a human gate it takes the one bead still waiting on the gate, and the conversation replies to the gate. On a TTY it prompts for subject, conversation (existing vs new), starter, model, and, for a new conversation, skill; any value on the command line pre-fills and skips its prompt, and --no-input keeps the non-interactive one-shot behavior. --skill seeds the sitting with any skill it carries as its lens on the subject (--skill review-arch is a conversation with the Architect). --new-subject files a FRESH subject bead (its title is the positional text; --rig picks the rig, prompted otherwise) and engages it in one gesture
  gc-helm react <bead-id> [--reason "..."]  file a first reaction — a reaction bead that tracks the subject, claimed and disposed by the proactive pool
  gc-helm takeaway <bead-id> "<text>" [--by host|proactive|converse] [--waiting-on <bead-id>... | --no-wait] [--release [--route <rig>/<agent> | --assign <named-agent>]]  set the board-visible takeaway headline (≤140 chars, ENFORCED)
  gc-helm park <bead-id> "<text>" [--body "..."]  hold everything under the bead that has not started: file a gate titled with why it is parked and what releases it (≤140 chars, ENFORCED), described by --body, and make the bead wait on it
  gc-helm park <bead-id> --waiting-on <bead-id>  the same hold behind an existing bead, filing no gate
  gc-helm priority <bead-id> <P0-P4> [--dry-run]  set the priority of a bead that follows nothing, and re-rank the work that follows it
  gc-helm priority <bead-id> --shift <±n> [--dry-run]  set the shift of a bead that follows a parent or an anchor: +1 is one level later, -1 one level sooner
  gc-helm dismiss  [<bead-id>] [--reason "..."] [--operator] [--json]  the operator is done with this sitting: close the conversation a live sitting holds on the bead, answering no gate, and stop the session that held it; a conversation id closes that conversation (subject inferred from the current sitting when omitted); --operator stops every session as the operator, from outside it; --json prints {subject,matched,closed,ok}
  gc-helm handback <conversation-id> < hand-back  record the hand-back a converse sitting is posting, read from stdin, on its conversation, replacing the one before; engage prints the latest in the operator's tab once the sitting has ended
  gc-helm accept <bead-id> [--reason "..."] [--conversation <task>] [--var <key>=<value> ...]  accept a recommendation: resolve the human gate that put it to the operator, read the answer back, and dispatch the bead's gc.recommended_formula at it; refuses while another human gate blocks the bead, and finishes an acceptance an earlier Accept left unfinished (subject or conversation id). --conversation names the conversation whose sitting's sign-off runs this Accept, which it does not warn of; each --var rides the sling, a var the operator settled for this dispatch
  gc-helm resolve <bead-id|pr-number|pr-url>  print the LIVE bead a reference resolves to (a PR ref to its anchor, a superseded id to its successor); a live id or an unrecognized reference prints unchanged, an unresolvable or ambiguous PR is refused. Read-only, files nothing — operator-intake.sh uses it to route a PR reference before it becomes a topic
  gc-helm unplaced [--json]  list the placement sitting's queue: every live bead in the city's stores marked placement=pending that nothing has placed since (no parent, route, arm, assignee or live pour), priority then age; --json prints one object for a caller: the rows as beads, the suspended rigs it skipped, and the rigs whose store did not answer. Read-only, files nothing; exits 4 after the list when a store did not answer

The board is `helm-svc board` (services/helm). This script renders no
board. open, engage and react take the subject as a bead id, a PR number
or URL, or a superseded bead id, and resolve it to the LIVE bead that owns the
work by metadata and the graph — a PR number/URL to its anchor, a
closed+superseded id along gc.superseded_by to its successor — never an id
scraped from a title. A live bead recording a PR in pr_number/pr_url stands
for the anchor it names in anchor_bead, if any. An unresolvable or ambiguous
reference is refused, naming what it could not resolve; nothing is filed.
A conversation is an ordinary task that tracks the one bead it is about and
replies to each human gate it answers (bd's replies-to edge). It is assigned
to `human` while it waits in the operator's queue, and to its sitting's alias,
which names its own id, while a sitting holds it (conversation.sh holds the
one definition of that shape). open files one in the queue, in the bead's own
store; its --reason is the title and --body the ask the sitting reads when it
claims the conversation. engage holds a conversation in a sitting: it attaches
to a live sitting on the bead, or takes the bead's conversation from the
queue, or one whose sitting's session has closed, or files a new one. It then
spawns a manual converse-<model> sitting (origin=manual, backstop-exempt)
named for the conversation, binds the conversation to that sitting's alias
with a write guarded on the holder it read, so the session's own claim adopts
it, and attaches once the reconciler has started it, however long the start
takes, reporting the sitting's state while it waits (an interrupted wait leaves
the sitting to start on its own, to attach later). Pointed at a human gate,
engage takes the one bead still waiting on the gate and makes the conversation
it lands on reply to the gate; with several beads waiting it names them and
starts nothing, and with none it says nothing waits and starts nothing.
Engaging a bead or a PR names each open human gate that holds it, reached
through its open blocks edges, by the reader the PR's held: gate label and the
board's row read: the interactive prompt offers each, and picking one engages
it as if it were named, and any other engage says how to.
--model picks the converse variant (opus, the work tier, is the default),
--no-attach spawns without attaching. On a TTY engage is INTERACTIVE: with no
subject it prompts for one (id or title search), lists the subject's open
conversations and offers one of them or a new conversation, prompts a new
conversation's starter (a lettered seed, Enter for the default, or free text
sent verbatim), prompts the model as a numbered choice over the configured
variants, and for a new conversation asks for a skill (Enter for none, ? to
list them). Any command-line value pre-fills and skips its prompt
(--subject/positional, --reason/--template, --model, --skill); --no-input
reverts to the flag-driven one-shot behavior. Starter seeds and the lens
brief live in assets/scripts/gc-helm-engage-starters.sh.
--skill <name> takes any skill on the sitting's roster (gc skill list --agent
<rig>/gc-toolkit.converse-<model>), a bare name resolving to its one full
match (review-arch to gc-toolkit.review-arch). The new conversation's ask
tells the sitting to load that skill, read the subject through it, and leave
the skill's final writes, such as a review verdict, to the bead it was written
for; a --reason or --template opener follows the brief. It is refused on an
explicit conversation id, whose ask is already written, and on a name the
roster does not carry; a roster that will not read seeds the name unverified.
A --reason, --template or --skill with a SUBJECT is a concern of its own, so
it files a new conversation carrying that opener and engages it even when the
bead has one, passing --allow-duplicate through to open and --body the opener
as the ask. A --reason with an explicit conversation id is refused, because a
new conversation needs a subject and the reason would otherwise be dropped.
Engage warns when it starts a sitting while another live sitting tracks the
bead, or replies to a gate the bead waits on. The summary and prompts print on
stdout; a single [debug] line of conversation/sitting ids is always printed on
stderr.
--new-subject raises a topic that has no bead yet: it creates a fresh
operator-origin subject bead (the positional text, or an interactive prompt, is
its title and — absent --reason/--template — its opener), then files the one
conversation and engages it, all in one gesture. The rig to create it in comes
from --rig or an interactive prompt over the converse-capable rigs (needed
because there is no id prefix yet to derive a rig from); --no-input requires
--rig. The subject is marked gc.reaction_owned=1 so the async
first-reaction/proactive worker stands down rather than file a second
conversation; engage files the one conversation itself.
dismiss ends the sitting. react files a proactive first-reaction bead via
tools/gc-proactive.sh (its --reason is log-only operator intent). takeaway
stamps gc.takeaway (+_at/+_by) in one
update; --release also reopens/unassigns/clears the route and ends the run
beneath the anchor through gascity's run cancel. On an anchor that is already
CLOSED the reopen would resurrect a landed disposition, so it is skipped and
only the run's end runs; --route <rig>/<agent> releases it TO a pool instead of
back to the human, in the same write, and is refused on a closed anchor and on
a bead blocked by anything but a human gate, since the work is then on the
blocker and a pool has nothing to perform here; --assign <named-agent> releases
it TO a named agent instead, in the same write, as its assignee and with no
route, because the assignee is what the controller and the pack's notice read
to give a named agent a turn (docs/deferred-dispatch.md). --assign is refused
beside --route and on a closed anchor, and without --waiting-on also on a bead
blocked by anything but a human gate; with --waiting-on the named waits gate
the hand-off, since the agent's hook offers the bead only once bd reports it
ready; --waiting-on (repeatable) records the wait as a `blocks` edge beside the
prose so the board can re-ask whether it landed. --no-wait is the other answer
to the same question: this sitting settled the subject and nothing is waiting
on it. It stamps gc.takeaway_settled, which lifecycle.toml [holds] reads to
tell a settled headline from one parking a bead on prose, and it contradicts
--waiting-on. Say neither and the headline is a hold that
doctor/check-wait-is-an-edge reports, which is the honest reading of a park
nothing re-asks.

park holds everything under a bead that has not started and leaves work in
flight running (docs/steering.md). It gives the bead one `blocks` edge, onto
the gate the text form files or onto the bead --waiting-on names, and reads the
edge back. It prints `park <blocker> holds <bead>`, then what the park holds
and what it leaves running. Re-running the text form with the same text files
no second gate, and a --body on the re-run becomes that gate's description. It
refuses a bead in flight (one claimed, in_progress or hooked, one carrying
branch, merge_result or rejection_reason, or one with a workflow past
load-context), because the bead's own edge would hold its merge. Closing the
gate releases the park; removing one bead's edge (gc bd dep remove <bead>
<gate>) releases that bead alone.

priority moves where work queues (docs/steering.md). A bead's priority is the
priority of the bead it follows plus its own shift: a member follows its most
urgent parent, PR-finishing work its anchor, and a workflow's convoy, root and
steps the bead they were poured for. A P-value sets a bead that follows
nothing, and is refused on a bead that follows something, naming the shift
that would land it there; --shift sets a bead that follows a parent or an
anchor, and is refused on a bead that follows nothing. A workflow's convoy,
root or step takes no priority of its own. The move then writes every bead
that follows the bead, held beads included, their live workflows and their
anchors' PR-finishing work, leaves claimed beads as they are, and reads it
all back (assets/scripts/queue-priority.sh move). --dry-run prints what it
would write.

dismiss is the operator's explicit "end this sitting". It closes the
conversation a live sitting holds on the subject, with a reason naming the
dismissal, and answers nothing: every human gate the conversation replies to
stays open and owed, for its filer or the next sitting. It then stops the
converse session that held the conversation with `gc runtime drain-ack`, so
the controller ends the session outside this process: the session dismiss runs
in acks itself, last, and any other is acked as an operator. --operator says
the caller is outside the sitting even when it runs under the sitting's
identity to infer the subject, as prefix+X does, so every session is acked as
an operator and none acks itself. A session that will not stop is left to
converse-reap, which closes any converse session whose conversation reads
closed. The close falls back to --force when bd refuses an operator closing a
conversation its sitting holds. A conversation the verb could not account for
aborts the run, which exits 4. It writes nothing to the subject. A subject with
no live sitting has nothing to end, and dismiss says so and writes nothing; a
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
gc.handback with gc.handback_at, replacing the one recorded before, then read
back. engage runs its attach as a child, so when the tab's tmux client exits,
engage reads the conversation. A closed conversation prints how it closed and
the latest hand-back; a conversation still open prints the command that
re-attaches. A bead that is not a conversation is refused, and so is an empty
stdin.

accept answers a first reaction's recommendation (gc.recommended_formula on
the bead) by clearing the human gate that put it to the operator, the gate
under the key first-reaction, and nothing else. It is offered while the bead
carries the recommendation, that gate is open and unassigned or closed with an
acceptance an earlier Accept did not finish, and no other open human gate
blocks the bead. Every Accept on a bead runs under the bead's acceptance lock,
a flock on a file under <city>/.gc/runtime/packs/gc-toolkit, from before its
live read of those three conditions to its last write, and refuses while
another Accept holds it. It records the acceptance's dispatch input (its
token, the formula and each --var) on the gate, resolves the gate with
`ruled: accepted <formula> accept:<token>`, reads its own answer back, checks
that no open human gate blocks the bead, releases a bead a sitting's hold left
at held to unanchored, since a run poured at a held bead cancels at its first
step, slings the formula titled `<formula> accept:<token>`, and records the
dispatch by stripping gc.recommended_formula. An answer another reached first
stands, and Accept slings nothing. A gate filed in the meantime, or a sling
that poured no root, reopens the gate. A run that stopped after its resolve, or
whose release did not land, leaves an unfinished acceptance, which the next
Accept finishes under the same token, slinging only when no root carries the
token, and slinging the vars the acceptance recorded. A sitting takes a
recommendation through this verb too: its sign-off's --accept runs it with
--conversation naming the sitting's own conversation, which Accept then does
not warn of as a live sitting on the bead, and with a --var for each var the
operator's ruling settled for the dispatch, such as mol-design-convoy's
design_gated=false. Each --var rides the sling. A run that finishes an
acceptance slings the vars that acceptance was made with and refuses a --var
that differs from them, and a root an earlier run already poured under the
token keeps the vars it was poured with.
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

# meta_now <bead> <key> — one metadata key as the store answers it right now,
# for reading a write back. A row that will not read answers empty, which every
# caller here treats the same as a value that did not land. $db is the caller's
# store pin; the verbs that pin by BEADS_DIR leave it unset.
meta_now() {
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd show "$1" ${db:+--db "$db"} --json 2>/dev/null | scrub \
        | jq -r --arg k "$2" 'if type == "array" then ((.[0].metadata // {})[$k] // "") else "" end' 2>/dev/null || printf ''
}

# assignee_now <bead> — the bead's top-level assignee as the store reads it now,
# empty when unassigned or unreadable. Same pinned store as meta_now.
assignee_now() {
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd show "$1" ${db:+--db "$db"} --json 2>/dev/null | scrub \
        | jq -r 'if type == "array" then (.[0].assignee // "") else "" end' 2>/dev/null || printf ''
}

# row_now <bead> — the bead's own row as the store answers it now, one line of
# JSON, or empty when it does not resolve. Same pinned store as meta_now.
row_now() {
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd show "$1" ${db:+--db "$db"} --json 2>/dev/null | scrub \
        | jq -c --arg b "$1" \
            'if type == "array" then ([ .[] | select(type == "object" and (.id // "") == $b) ] | first // empty) else empty end' \
            2>/dev/null || true
}

# blocks_edge_reads_back <bead> <blocker> — 0 iff the bead's own row, read now,
# carries a `blocks` edge onto <blocker>. A row that will not read is a missing
# edge. park reports an edge as landed only through this read, never through
# the exit status of the `dep add` or create that wrote it.
blocks_edge_reads_back() {
    row_now "$1" | jq -e --arg d "$2" '
        [ (.dependencies // [])[]? | select(type == "object")
          | select(((.dependency_type // .type // "") | tostring) == "blocks")
          | select(((.id // .depends_on_id // "") | tostring) == $d) ] | length > 0' >/dev/null 2>&1
}

# stamp_hides_placement — given a `bd show --json` answer on stdin whose row
# carries gc.execution_routed_to, print 1 when that stamp is all that keeps the
# bead out of the placement queue (placement.sh's awaiting_placement holds for
# the row without it) and 0 when it is not. An answer that is not a row prints 1,
# because nothing then shows the stamp hides nothing.
stamp_hides_placement() {
    shp_v=$(jq -r "$DISPATCH_PATH_JQ$PLACEMENT_JQ"'
        if type == "array" and length > 0
        then (.[0] | del(.metadata["gc.execution_routed_to"]) | if awaiting_placement then "1" else "0" end)
        else "1" end' 2>/dev/null) || shp_v=1
    case "$shp_v" in 0) printf '0' ;; *) printf '1' ;; esac
}

# normalize_headline <raw-text> <verb> — collapse whitespace runs, trim, and
# enforce the shared ≤TAKEAWAY_MAX cap; sets HEADLINE. One gate for two verbs:
# a park gate's TITLE is a one-line headline as a takeaway stamp is, so a cap
# enforced in only one of them is a cap the other renders past.
HEADLINE=""
normalize_headline() {
    HEADLINE=$(printf '%s' "$1" | tr -s '[:space:]' ' ')
    HEADLINE="${HEADLINE# }"; HEADLINE="${HEADLINE% }"
    [ -n "$HEADLINE" ] || { echo "$PROG: $2 needs \"<text>\" (the ≤${TAKEAWAY_MAX}-char one-line headline)" >&2; usage; exit 2; }
    # >>> takeaway-length-gate
    # REJECT over the cap, never truncate: only the author knows which clause
    # is the headline. Measured in CODEPOINTS — what both
    # renderers measure — with a shell-count fallback so the gate cannot
    # silently fail open on a broken jq.
    tlen=$(printf '%s' "$HEADLINE" | jq -Rsr 'length' 2>/dev/null || true)
    case "$tlen" in ''|*[!0-9]*) tlen=${#HEADLINE} ;; esac
    if [ "$tlen" -gt "$TAKEAWAY_MAX" ]; then
        echo "$PROG: $2: text is $tlen chars; the cap is $TAKEAWAY_MAX" >&2
        case "$2" in
            park) echo "$PROG: park: it is the park gate's title, one line read wherever the gate is listed. Cut it to why the bead is parked and what releases it, and put the rest in --body." >&2 ;;
            *)    echo "$PROG: $2: it renders as the board's NEEDS cell — one line, read at a glance. Cut it to the single sentence the operator needs and put the rest in the bead's notes." >&2 ;;
        esac
        exit 2
    fi
    # <<< takeaway-length-gate
}

# conversation_title <raw> — a conversation's title, whitespace collapsed and
# capped at TAKEAWAY_MAX codepoints and at 400 bytes. normalize_headline REJECTS
# over its cap because a takeaway headline IS the deliverable and only the
# author knows which clause to keep; a conversation carries its full ask in its
# description, so here the over-cap tail is TRUNCATED with an ellipsis instead.
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
# assigned to `human` or to the alias that names its own id. open, engage,
# dismiss and accept read conversations by it, as the board and the liveness
# classifier do. Exposes $CONVERSATION_JQ.
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
# The one definition of a bead that waits for placement, shared with the
# liveness classifier and check-blocked-work-armed, and the dispatch path it
# reads, shared with the proactive scan and the doctor checks: unplaced lists
# exactly the beads that predicate admits. Expose $PLACEMENT_JQ and
# $DISPATCH_PATH_JQ.
# shellcheck source=dispatch-path.sh
. "${GC_DISPATCH_PATH_LIB:-$SCRIPT_DIR/dispatch-path.sh}" \
    || { echo "$PROG: cannot source dispatch-path.sh from $SCRIPT_DIR" >&2; exit 3; }
# shellcheck source=placement.sh
. "${GC_PLACEMENT_LIB:-$SCRIPT_DIR/placement.sh}" \
    || { echo "$PROG: cannot source placement.sh from $SCRIPT_DIR" >&2; exit 3; }
# The one reader of a run's link to the bead it works: the release finds the
# runs beneath an anchor, and the park survey the workflows poured for a bead.
# Exposes run_lib and $RUN_JQ.
# shellcheck source=run-lib.sh
. "${GC_RUN_LIB:-$SCRIPT_DIR/run-lib.sh}" \
    || { echo "$PROG: cannot source run-lib.sh from $SCRIPT_DIR" >&2; exit 3; }
PROACTIVE_TOOL="${GC_PROACTIVE_TOOL:-$SCRIPT_DIR/../../tools/gc-proactive.sh}"
# The priority move's writer, which owns the priority function and the store's
# priority lock.
QUEUE_PRIORITY_TOOL="${GC_QUEUE_PRIORITY_TOOL:-$SCRIPT_DIR/queue-priority.sh}"
# engage's starter seeds live in a sibling data table; its converse-<model>
# variants are enumerated from the agent dirs, so the model menu cannot drift
# from what `gc session new converse-<model>` resolves. Both are overridable so
# a hermetic test can point them at a fixture.
STARTERS_TOOL="${GC_HELM_STARTERS_TOOL:-$SCRIPT_DIR/gc-helm-engage-starters.sh}"
ENGAGE_AGENTS_DIR="${GC_HELM_AGENTS_DIR:-$SCRIPT_DIR/../../agents}"
# Leaves a reminder on the subject's PR that a sitting engaged (and, on dismiss,
# that it closed). Best-effort and self-silencing when the subject has no PR;
# overridable so a hermetic test can point it at a fixture.
SITTING_COMMENT_TOOL="${GC_SITTING_COMMENT_TOOL:-$SCRIPT_DIR/pr-sitting-comment.sh}"
# Ends the run beneath a released anchor through gascity's run cancel;
# overridable so a hermetic test can point it at a fixture.
RUN_CANCEL_TOOL="${GC_RUN_CANCEL_TOOL:-$SCRIPT_DIR/run-cancel.sh}"
# The writer of a bead's lifecycle state, which Accept runs to release a held
# bead before it dispatches; overridable so a hermetic test can point it at a
# fixture.
LIFECYCLE_TOOL="${GC_LIFECYCLE_TOOL:-$SCRIPT_DIR/lifecycle.sh}"
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
# the same three step-close.sh tries as the assignee, and the same set the
# claim hook matches when a respawn adopts a hold. Empty when none is set.
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

# bd_rows <gc-bd-args...> — one `gc bd` read that must answer a JSON array,
# printed scrubbed with the `gc bd:` rig-store notice stripped. Returns 1 on a
# read that failed or answered anything else, so "none" and "could not read"
# stay apart.
bd_rows() {
    _br_raw=$(gc bd "$@" --json 2>/dev/null) || return 1
    printf '%s' "$_br_raw" | grep -av '^gc bd:' | scrub | jq -ce 'if type == "array" then . else error("not an array") end' 2>/dev/null
}

# human_gate_rows <bead> — the bead's human gates, open and closed, as the rows
# `gc bd dep list <bead> --type blocks` answers: the one reader rule. Each row
# carries the gate's id, status, await_id, assignee, title, created_at and,
# once closed, close_reason. Returns 1 when the read did not answer.
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

# live_sittings — the converse sessions `gc session list` holds that have not
# ended, one {id, alias, session_name, created_at, attached} object each, as a
# JSON array. A converse session is one whose template names converse. A
# sleeping session is listed, because attaching wakes it; a closed one is left
# out, and so is one listed with an empty state, which is how a closed session
# reads when gc answers from the supervisor. Returns 1 when the list did not
# answer, which proves no sitting live and none gone.
live_sittings() {
    _ls_raw=$(gc session list --state all --json 2>/dev/null) || return 1
    printf '%s' "$_ls_raw" | scrub | jq -ce '
        if type == "object" and ((.sessions // null) | type) == "array"
        then [ .sessions[] | objects
               | select((.closed // false) != true)
               | select(((.state // "") | tostring) as $st | $st != "" and $st != "closed" and $st != "failed-create")
               | select(((.template // "") | tostring) | test("converse"))
               | {id: ((.id // "") | tostring), alias: ((.alias // "") | tostring),
                  session_name: ((.session_name // "") | tostring),
                  created_at: ((.created_at // "") | tostring), attached: ((.attached // false) == true)} ]
        else error("sessions array unreadable") end' 2>/dev/null
}

# $SITTING_JQ — whether a conversation row is held by a live sitting, given
# live_sittings as $live: its assignee is a live session's alias, session name
# or id, or both the assignee and a live session's alias name the
# conversation's own id (conversation_alias). Prepend $CONVERSATION_JQ.
SITTING_JQ='
  def held_live($live):
    . as $row | ((.assignee // "") | tostring) as $a
    | $a != "" and $a != "human"
      and any($live[]; . as $s
              | $s.alias == $a or $s.session_name == $a or $s.id == $a
                or (($row | conversation_alias)
                    and ({id: ($row.id // ""), assignee: $s.alias} | conversation_alias)));
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
        _srig=$(gc session list --state all --json 2>/dev/null | scrub \
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
# title legitimately names OTHER beads (`gc.supersedes`), so an id scraped from
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
#   closed + gc.superseded_by            ->  followed to the live successor
#   live bead id                         ->  unchanged
RESOLVED_SUBJECT=""
resolve_live_subject() {
    _rls_ref="$1"
    RESOLVED_SUBJECT="$_rls_ref"

    # Rig health first: the PR search reads every rig's store, so validate the
    # rig list (exit 3) before any read reaches the wire, and cache it here for
    # the search and for the caller's later rig_path_for_bead.
    enumerate_rigs

    # Classify without touching the store. A PR URL pins the repo; a bare
    # number does not. A bead id carries a rig-prefix and a dash; a topic
    # string is neither and passes through untouched.
    _rls_prnum=""; _rls_prurl=""
    case "$_rls_ref" in
        http://*/pull/[0-9]*|https://*/pull/[0-9]*)
            _rls_prurl="$_rls_ref"
            _rls_prnum=$(printf '%s' "$_rls_ref" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p') ;;
        *[!0-9]*) : ;;                       # a non-digit: not a bare PR number
        [0-9]*)   _rls_prnum="$_rls_ref" ;;  # all digits: a bare PR number
    esac

    if [ -n "$_rls_prnum" ]; then
        _resolve_pr_reference "$_rls_prnum" "$_rls_prurl"
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
_resolve_pr_reference() {
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

    _pr_uniq=$(printf '%s' "$_pr_anchors" | awk 'NF && !seen[$0]++')
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

# _resolve_superseded_reference <bead-id> — follow a settled disposition
# (status closed + gc.superseded_by) to its live successor and set
# RESOLVED_SUBJECT. bead-rehome.sh stamps gc.superseded_by (+ the legacy bare
# key) alongside gc.superseded_by_store; the successor is read cross-ledger by
# its rig-unique id, so that store hint is not needed to find it. A live bead,
# or one that does not resolve, passes through unchanged for the caller's
# existence gate; a cycle is refused (exit 4) rather than guessed.
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
            # A SUCCESSOR we followed does not resolve (a broken or cross-store
            # pointer). Refuse — never fall back to opening the settled predecessor.
            echo "$PROG: $_ss_orig is superseded by $_ss_cur, which does not resolve (a broken or cross-store pointer). Refusing to open the settled predecessor; pass the live bead id directly. Nothing filed." >&2
            exit 4
        fi
        _ss_status=$(printf '%s' "$_ss_this" | jq -r '.status // ""' 2>/dev/null) || _ss_status=""
        _ss_succ=$(printf '%s' "$_ss_this" | jq -r '(.metadata["gc.superseded_by"] // .metadata.superseded_by // "")' 2>/dev/null) || _ss_succ=""
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

# ── Release helper: end the run beneath a released anchor ─────────────
# A molecule whose anchor is out of play — parked by a stand-down, released to a
# pool or an agent, or closed by a fold that landed after the pour — must not
# keep running, and a molecule's lifecycle is gascity's. So the release ends
# each such run through gascity's run cancel (run-cancel.sh --root), which
# closes the root and every step that is not closed. This script writes no step
# and no root. That is why the walk is reachable on a closed anchor too.
#
# The runs beneath the anchor are the live runs run-lib.sh names for it: a
# run whose input convoy's one tracked bead IS the anchor. Keying on the anchor
# keeps the resolution bounded — the work does not grow with the number of
# molecules open in the store.
#
# A molecule the RELEASING session holds a step of is its own run, such as a
# sitting disposing the anchor it runs on, and it closes its own chain the
# normal way, so it is left alone. A read that fails, of the runs or of the
# steps that say whose a run is, ends nothing and is reported as a miss, since
# a run it could not read may still run.
#
# Guards: fail closed on an unresolved or foreign anchor; an absent root is the
# witness patrol's, not ours.
#
# Subshell. $1 = released anchor id, $2 = rig .beads path or "". Returns
# non-zero when a run it set out to end did not end, or when it could not read
# which runs to end, each named on stderr.
# >>> cancel-release-molecules
cancel_release_molecules() (
    set +e
    _anchor="$1"; _db="$2"; _missed=0

    _me=$(session_identities)

    # shellcheck disable=SC2329,SC2086  # run_lib calls it; ${_db:+--db "$_db"} expands to 0 or 2 space-free fields
    release_bd() { gc bd ${_db:+--db "$_db"} "$@"; }
    if ! _runs=$(run_lib runs release_bd "$_anchor"); then
        echo "$PROG: takeaway: could not read the runs beneath $_anchor, so none was ended and any of them may still run" >&2
        echo "$PROG:   end each by hand: $RUN_CANCEL_TOOL --root <root>${_db:+ --db $_db} --reason \"<why>\"" >&2
        exit 1
    fi
    _match_roots=$(printf '%s' "$_runs" | jq -r '.[] | select(.live) | .root' 2>/dev/null)
    [ -n "$_match_roots" ] || exit 0

    # One row per live member of a molecule: a root, or a step naming its root.
    # shellcheck disable=SC2086  # ${_db:+--db "$_db"} expands to 0 or 2 space-free fields
    if ! _live=$(gc bd list --status=open,in_progress,blocked ${_db:+--db "$_db"} --json --limit=0 2>/dev/null) \
       || ! _rows=$(printf '%s' "$_live" | jq -c '
            .[]
            | . as $b
            | (($b.metadata["gc.kind"] // "") == "workflow") as $isroot
            | select($isroot
                     or ((($b.metadata["gc.step_ref"]     // "") != "")
                         and (($b.metadata["gc.root_bead_id"] // "") != "")))
            | { root:     (if $isroot then $b.id
                                      else ($b.metadata["gc.root_bead_id"] // "") end),
                assignee: ($b.assignee // "") }' 2>/dev/null); then
        echo "$PROG: takeaway: could not read whose runs are beneath $_anchor, so none was ended and any of them may still run" >&2
        echo "$PROG:   end each by hand: $RUN_CANCEL_TOOL --root <root>${_db:+ --db $_db} --reason \"<why>\"" >&2
        exit 1
    fi

    while IFS= read -r _root; do
        [ -n "$_root" ] || continue

        _own=""
        if [ -n "$_me" ]; then
            _own=$(printf '%s\n' "$_rows" | jq -r -s --arg r "$_root" --arg me "$_me" '
                ($me | split("\n") | map(select(length > 0))) as $ids
                | [ .[] | select(.root == $r) | (.assignee // "") | select(. != "") | . as $a | select($ids | any(. == $a)) ]
                | if length > 0 then "own" else "" end' 2>/dev/null || true)
        fi
        if [ -n "$_own" ]; then
            echo "$PROG: takeaway: kept run $_root of $_anchor — this session holds a step of it and closes its own chain"
            continue
        fi

        # shellcheck disable=SC2086  # ${_db:+--db "$_db"} expands to 0 or 2 space-free fields
        if _out=$("$RUN_CANCEL_TOOL" --root "$_root" ${_db:+--db "$_db"} --reason "takeaway --release on $_anchor took its work out of play" 2>&1); then
            echo "$PROG: takeaway: ended run $_root of $_anchor through gascity"
        else
            _missed=1
            echo "$PROG: takeaway: run $_root of $_anchor did not end: $(printf '%s' "$_out" | tr '\n' ' ')" >&2
            echo "$PROG:   end it by hand: $RUN_CANCEL_TOOL --root $_root${_db:+ --db $_db} --reason \"<why>\"" >&2
        fi
    done <<ROOTS
$_match_roots
ROOTS
    exit "$_missed"
)
# <<< cancel-release-molecules

# ── Verb: takeaway ───────────────────────────────────────────────────
# Stamp gc.takeaway/_at/_by in ONE update, then bust the cache. --release adds
# two acts to that stamp: PARK the anchor, and END the run beneath it.
#
# The park (reopen, unassign, stamp the route) rides the same write as the
# headline, so a reaction that concludes "this is work" hands the bead on in
# the write that records the conclusion: either the whole disposition lands or
# none of it does. It applies to an anchor still standing.
# A closed anchor was disposed already, so it keeps that disposition and gets
# the run's end alone.
#
# The run's end is gascity's run cancel on the molecule's root, which closes the
# root and every step that is not closed; a run the releasing session holds a
# step of is its own, and is left to close its chain.
#
# --route names a pool to release TO. The target is rig-qualified or refused,
# because gc.routed_to is read by exact string and a bare agent name routes to
# nobody and sits forever; on a closed anchor the route is refused outright. It
# also names a bead that is itself the work, so a bead blocked by anything but
# a human gate is refused.
# --assign names a NAMED agent to release TO, written as the assignee with no
# route (the usage says why). A bead is addressed one way or the other, never
# both. --assign is refused on a closed anchor like --route. Without
# --waiting-on it also takes the --route blocker guard. With --waiting-on the
# guard is skipped: the caller has named the waits, and the hook offers the
# bead only once bd reports it ready, so every open blocker gates the hand-off,
# named or not.
# --waiting-on records each wait as a `blocks` edge, best-effort: the stamp is
# what the sitting owes the operator, so a rejected edge only warns and never
# fails the verb. One wait is written as no edge: a LANDED rider — a bead that
# both rode the SUBJECT's own branch and has already put its work there, proven
# by a post-push state (closed, or handed off to the refinery). Its deliverable
# is in the subject's own head, so the subject's merge is what carries it, and
# an edge would gate that merge on work that merges WITH it — the blocker
# merge.sh's dep-edge lane holds on with no release, a PR wedged forever. Same
# branch WITHOUT that proof is not this case: metadata.branch is set at
# workspace-setup, before the wait pushes, so a still-open same-branch wait may
# not be on the branch yet, and its edge stands so the subject cannot merge past
# it. When EVERY named wait is a landed rider the headline records
# gc.takeaway_settled, the settled shape --no-wait writes, so no held marker is
# left edgeless for doctor/check-wait-is-an-edge. Every other wait keeps its edge.
#
# The headline says nothing about whether the subject is still waiting, and
# every sitting stamps one, so the disposition rides beside it in
# gc.takeaway_settled: "1" under --no-wait, empty otherwise. It is written with
# EVERY headline, never left to stand, because a stamp that outlived its
# sitting would answer for the next one — a settled sign-off would silence the
# park that followed it. lifecycle/lifecycle.toml [holds] settled_keys is where
# doctor/check-wait-is-an-edge reads the pairing.
#
# A --release that PARKS an open anchor for a person (no --route) must carry one
# of --waiting-on or --no-wait — the wait as an edge, or the settled mark that
# says there is none — UNLESS the bead already carries an open blocker whose edge
# holds it. Neither flag on a bead with no blocker is the silent prose-only park
# refused below, the unedged hold the I1 backlog exists to drain. A --release
# --route DISPATCHES to a pool instead (moving, not held), as --assign does to a
# named agent, a closed anchor takes only the run's end, and a bare headline (no
# --release) parks nothing — all exempt.
cmd_takeaway() {
    bead=""; text=""; by="host"; release=""; route=""; assign=""; npos=0
    waiting_ids=""; no_wait=""; subj_branch=""; real_waits=""; skipped_riders=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --by=*)    by="${1#--by=}"; shift ;;
            --by)      shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --by requires a value" >&2; exit 2; }; by="$1"; shift ;;
            --waiting-on=*) waiting_ids="$waiting_ids ${1#--waiting-on=}"; shift ;;
            --waiting-on)   shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --waiting-on requires a bead id" >&2; exit 2; }
                            waiting_ids="$waiting_ids $1"; shift ;;
            --no-wait) no_wait=1; shift ;;
            --release) release=1; shift ;;
            --route=*) route="${1#--route=}"; shift ;;
            --route)   shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --route requires a <rig>/<agent> target" >&2; exit 2; }; route="$1"; shift ;;
            --assign=*) assign="${1#--assign=}"; shift ;;
            --assign)   shift; [ $# -gt 0 ] || { echo "$PROG: takeaway: --assign requires a named-agent identity" >&2; exit 2; }; assign="$1"; shift ;;
            -h|--help) usage; exit 0 ;;
            -*) echo "$PROG: takeaway: unknown flag '$1'" >&2; exit 2 ;;
            *)
                npos=$((npos + 1))
                case "$npos" in
                    1) bead="$1" ;;
                    2) text="$1" ;;
                    *) echo "$PROG: takeaway takes one <bead-id> and one \"<text>\"" >&2; exit 2 ;;
                esac
                shift ;;
        esac
    done
    [ -n "$bead" ] || { echo "$PROG: takeaway needs <bead-id>" >&2; usage; exit 2; }

    # Two answers to one question, and they contradict: a named wait IS the
    # subject still waiting. Refused before anything is written, so what gets
    # repaired is the claim rather than the bead.
    if [ -n "$no_wait" ] && [ -n "$waiting_ids" ]; then
        echo "$PROG: takeaway: --no-wait contradicts --waiting-on$waiting_ids — one says nothing is waiting on $bead, the other names what is. Pass whichever is true. Nothing was written." >&2
        exit 2
    fi

    normalize_headline "$text" takeaway
    text="$HEADLINE"

    [ -n "$by" ] || by="host"

    # --route rides --release: a route stamped without the release would leave
    # the bead assigned to this session AND routed to a pool, which is the
    # half-state no reader can act on.
    if [ -n "$route" ]; then
        [ -n "$release" ] || { echo "$PROG: takeaway: --route needs --release (it names where the bead is released TO)" >&2; exit 2; }
        case "$route" in
            */*) : ;;
            *) echo "$PROG: takeaway: --route '$route' is not rig-qualified; gc.routed_to is matched as an exact string, so a bare agent name routes to nobody and the bead sits forever. Use <rig>/<agent>." >&2; exit 2 ;;
        esac
    fi
    # --assign rides --release for the same reason, and it excludes --route. The
    # agent's hook offers the bead by its assignee whatever the route, and a
    # pool's claim and Gas City's pool demand count both skip an assigned bead,
    # so a route beside the assignee offers the bead to no pool member until
    # the assignee is cleared, and then hands it to the pool instead of the
    # agent.
    if [ -n "$assign" ]; then
        [ -n "$release" ] || { echo "$PROG: takeaway: --assign needs --release (it names who the bead is released TO)" >&2; exit 2; }
        [ -z "$route" ] || { echo "$PROG: takeaway: --assign and --route both name where $bead goes. A bead is addressed to a named agent by its assignee or to a pool by gc.routed_to, never both. Pass one. Nothing was written." >&2; exit 2; }
    fi

    path=$(rig_path_for_bead "$bead")
    db=""; [ -n "$path" ] && [ -d "$path/.beads" ] && db="$path/.beads"

    # --release is two acts welded into one flag: PARK the anchor (reopen,
    # unassign, stamp the route) and END the run beneath it. The park
    # is correct for an anchor still standing and destructive for one already
    # disposed — a bead closed by a fold carries gc.superseded_by and a
    # close_reason naming its carrier, and `--status=open` there makes work
    # whose disposition landed visible as open in every reader of open beads.
    # The run's end is the half a disposed anchor still needs: a fold that lands
    # AFTER the pour leaves the run going either way, and gascity's autoclose
    # skips a run with open steps. So a closed anchor keeps its disposition and
    # still gets the walk.
    #
    # The status is read before anything is written, and an unreadable one
    # refuses the verb: a bead whose disposition cannot be proven is the one
    # case where reopening it costs the most.
    # >>> takeaway-release-closed-anchor
    release_park=""
    if [ -n "$release" ]; then
        release_park=1
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        anchor_json=$(gc bd show "$bead" ${db:+--db "$db"} --json 2>/dev/null | scrub)
        anchor_status=$(printf '%s' "$anchor_json" \
            | jq -r --arg b "$bead" \
                'if type == "array"
                 then [ .[] | select(type == "object" and (.id // "") == $b) ] | first | (.status // "")
                 else empty end' 2>/dev/null || true)
        if [ -z "$anchor_status" ]; then
            echo "$PROG: takeaway: could not read the status of '$bead' (does it exist in rig '${path:-?}'?). Refusing --release rather than reopen a bead whose disposition cannot be read. Nothing was written." >&2
            exit 4
        fi
        if [ "$anchor_status" = "closed" ]; then
            release_park=""
            superseded=$(printf '%s' "$anchor_json" \
                | jq -r --arg b "$bead" \
                    'if type == "array"
                     then [ .[] | select(type == "object" and (.id // "") == $b) ] | first | ((.metadata // {})["gc.superseded_by"] // "")
                     else empty end' 2>/dev/null || true)
            echo "$PROG: takeaway: $bead is closed${superseded:+, superseded by $superseded} — its disposition stands, so the release write is skipped (no reopen, no unassign, no route stamp). The run beneath it is still ended." >&2
        fi
    fi
    # <<< takeaway-release-closed-anchor

    # A park for a person states its disposition, UNLESS the bead is already held
    # by an open blocker — then the wait is an existing edge and a bare --release
    # parks it beside that edge, not a prose-only hold. --release reopens a
    # standing anchor and either DISPATCHES it (a --route to a pool or an
    # --assign to a named agent, moving) or PARKS it for a person (neither:
    # open, unassigned, at rest). A held park names its wait: --waiting-on
    # writes it as a `blocks` edge, --no-wait says nothing waits and stamps
    # gc.takeaway_settled. Neither, on a bead carrying NO
    # open blocker, is the silent prose-only park — a headline holding it with no
    # edge and no settled mark, the shape doctor/check-wait-is-an-edge reports and
    # the I1 backlog drains, refilled by parks faster than closes drain it. Any
    # open blocker counts, a human gate included: a gate is an edge that holds.
    # An unreadable probe refuses the park: with the blockers unread no existing
    # edge can be proven, and stamping an unedged hold on a bead the guard could
    # not inspect is the shape it exists to stop, so the caller states its
    # disposition (--waiting-on or --no-wait) or re-runs once the store answers.
    # A dispatch is moving and leaves no unedged hold, so the route guard below
    # fails open on the same probe where this one fails closed; a closed anchor
    # took no park (release_park cleared above); a bare headline (no --release)
    # parks nothing; a converse sitting stamps one beside a gate that holds it.
    if [ -n "$release_park" ] && [ -z "$route" ] && [ -z "$assign" ] && [ -z "$no_wait" ] && [ -z "$waiting_ids" ]; then
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        park_held=$(gc bd dep list "$bead" ${db:+--db "$db"} --direction=down --json 2>/dev/null | scrub \
            | jq -er 'if type == "array" then
                   [ .[] | select((.dependency_type // "") == "blocks")
                         | select((.status // "") != "closed") | .id ] | join(" ")
                 else error("not an edge array") end' 2>/dev/null) || park_held="__unreadable__"
        if [ "$park_held" = "__unreadable__" ]; then
            echo "$PROG: takeaway: --release parks $bead for a person, and a park states its disposition — but $bead's blockers could not be read, so an open blocker holding it beside an edge cannot be proven. Pass --waiting-on <bead> for the wait it holds on (written as a blocks edge), or --no-wait when nothing waits on it, or re-run once the store answers: a park the guard cannot clear must not stamp an unedged hold on a bead it could not inspect. Nothing was written." >&2
            exit 2
        fi
        if [ -z "$park_held" ]; then
            echo "$PROG: takeaway: --release parks $bead for a person, and a park states its disposition: --waiting-on <bead> for the wait it holds on (written as a blocks edge), or --no-wait when nothing waits on it. $bead carries no open blocker to hold it, so neither flag leaves the headline an unedged hold — the shape doctor/check-wait-is-an-edge reports and the I1 backlog drains. Nothing was written." >&2
            exit 2
        fi
    fi

    # A pool route promises a claim some session can perform. A bead blocked by
    # anything other than a human gate has its method somewhere else: no pool
    # can see it until the blocker closes, and by then it is a record of work
    # that already happened, so each session that claims it re-derives that and
    # drains. A human gate is the one blocker that leaves the route honest,
    # because answering it is what makes this bead the work. The gate's own
    # fields tell it apart ($HUMAN_GATE_JQ's human_gate), not its shape.
    # Refused before the write, so a re-run without --route still lands the
    # headline, and the route is all the refusal costs: the board gathers a
    # parked row on gc.takeaway and bands it disposition-due once its waits have
    # all closed, so the operator is asked either way. An unreadable probe
    # allows the route and says so. A bd that will not answer must not cost a
    # sitting its disposition, but a route stamped over an uninspected bead is
    # a weaker promise than one the guard cleared, and in silence the two read
    # alike. Unreadable covers the payload as well as the exit code: `dep list`
    # reports a bead it cannot resolve as a JSON error OBJECT on stdout, which
    # a filter that answers "" on anything but an array takes for no edges at
    # all. A cross-store edge is left out of the array entirely, invisible here
    # as it is to every other reader of this graph. A closed anchor is not this
    # refusal's case: its route is refused below on the disposition itself,
    # after the headline and the run's end a folded anchor still needs have
    # landed. An --assign takes the same guard, since a named agent offered a
    # bead whose work sits on a blocker has nothing to perform either, unless
    # the call names its waits with --waiting-on: the agent's hook offers the
    # bead only once bd reports it ready, so the named waits gate the hand-off.
    dest=""; dest_flag=""
    if [ -n "$route" ]; then dest="$route"; dest_flag="--route"
    elif [ -n "$assign" ] && [ -z "$waiting_ids" ]; then dest="$assign"; dest_flag="--assign"; fi
    if [ -n "$dest" ] && [ -n "$release_park" ]; then
        probe_read=1
        need_human_gate_jq
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        blocked_by=$(gc bd dep list "$bead" ${db:+--db "$db"} --direction=down --json 2>/dev/null | scrub \
            | jq -er "$HUMAN_GATE_JQ"'if type == "array" then
                   [ .[] | select((.dependency_type // "") == "blocks")
                         | select((.status // "") != "closed")
                         | select(human_gate | not)
                         | .id ] | join(" ")
                 else error("not an edge array") end' 2>/dev/null) || probe_read=""
        if [ -z "$probe_read" ]; then
            blocked_by=""
            echo "$PROG: takeaway: could not read the blockers on $bead ('gc bd dep list' failed, or answered with something other than an edge array), so $dest_flag '$dest' goes UNCHECKED. If this bead's work is really on a blocker, it reaches '$dest' with no method to perform once that blocker closes. Re-run with --release alone to leave it at rest, or re-run this call once the store answers." >&2
        fi
        if [ -n "$blocked_by" ] && [ "$dest_flag" = "--route" ]; then
            echo "$PROG: takeaway: --route '$route' on $bead, which is blocked by $blocked_by. None of those is a human gate on $bead, so the work is on them and this bead has no method a pool can perform: routed, it waits for them to close and is then offered to '$route' forever. Re-run with --release alone, which still lands the headline and the release and leaves the bead at rest. A bead that should reach a pool once its blocker clears is first-reaction-dispose.sh --disposition blocked --then-route '$route', which routes on the unblock instead of now." >&2
            exit 2
        fi
        if [ -n "$blocked_by" ]; then
            echo "$PROG: takeaway: --assign '$assign' on $bead, which is blocked by $blocked_by. None of those is a human gate on $bead, so the work is on them: assigned, $bead reaches '$assign' once they close, as a record of work that already happened. Re-run with --release alone, which still lands the headline and the release and leaves the bead at rest. A bead that should reach '$assign' once its blocker clears names that wait: first-reaction-dispose.sh --disposition blocked --then-assign '$assign'." >&2
            exit 2
        fi
    fi

    # Partition --waiting-on into the waits a pool still owes and the LANDED
    # riders. A landed rider both rode <bead>'s OWN branch and has already put
    # its work there, so <bead>'s own merge is what carries it
    # (docs/human-engagement.md, "How a held sitting ends"): an edge would
    # gate <bead>'s merge on work that merges WITH it — the deadlock merge.sh's
    # dep-edge lane holds on with no release — while asserting a pending wait
    # that does not exist. Both halves are required. metadata.branch is set at
    # workspace-setup, before the wait implements, pushes or hands off, so
    # equality proves the wait MEANS to ride this branch, not that its work is
    # on it. The proof its work landed is a post-push state: the wait is closed
    # (merged), or its assignee is the refinery (the handoff submit-and-exit
    # writes only after it verifies the push). Absent the proof — a wait still
    # open under a pool, or a probe that will not read — the edge stands, so
    # <bead> cannot merge past work that has not landed. Only a landed rider is
    # dropped; if EVERY named wait is one, the sitting is settled with respect to
    # all of them, so no_wait is set and the headline stamps gc.takeaway_settled
    # the same way --no-wait does — which keeps doctor/check-wait-is-an-edge (I1)
    # satisfied without an edge to a wait that is not there.
    if [ -n "$waiting_ids" ]; then
        subj_branch=$(meta_now "$bead" branch)
        have_real=""
        for _w in $waiting_ids; do
            [ -n "$_w" ] || continue
            if [ "$_w" = "$bead" ]; then
                echo "$PROG: takeaway: --waiting-on $_w is the bead itself; skipped" >&2
                continue
            fi
            # Read the wait once: its branch says whether it rode <bead>'s
            # branch, its status and assignee whether its work is provably there.
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            _wrow=$(gc bd show "$_w" ${db:+--db "$db"} --json 2>/dev/null | scrub)
            _wbranch=$(printf '%s' "$_wrow" | jq -r 'if type == "array" then ((.[0].metadata // {}).branch // "") else "" end' 2>/dev/null)
            _wstatus=$(printf '%s' "$_wrow" | jq -r 'if type == "array" then (.[0].status // "") else "" end' 2>/dev/null)
            _wassignee=$(printf '%s' "$_wrow" | jq -r 'if type == "array" then (.[0].assignee // "") else "" end' 2>/dev/null)
            _rider=""
            if [ -n "$subj_branch" ] && [ "$_wbranch" = "$subj_branch" ]; then
                case "$_wstatus" in closed) _rider=1 ;; esac
                case "$_wassignee" in refinery|*.refinery|*/refinery) _rider=1 ;; esac
            fi
            if [ -n "$_rider" ]; then
                skipped_riders="$skipped_riders $_w"
                continue
            fi
            real_waits="$real_waits $_w"; have_real=1
        done
        if [ -n "$skipped_riders" ] && [ -z "$have_real" ]; then no_wait=1; fi
    fi

    # Build args with `set --` ($text/$by contain spaces); --release rides the
    # SAME update so stamp + release stay one Dolt write.
    set --
    set -- "$@" --set-metadata "gc.takeaway=$text" \
               --set-metadata "gc.takeaway_at=$(iso_now)" \
               --set-metadata "gc.takeaway_by=$by" \
               --set-metadata "gc.takeaway_settled=$no_wait"
    # --release retires the pour's routing on the anchor: gc.routed_to takes the
    # new route (empty when none) and gc.execution_routed_to — the stamp a pour
    # leaves naming the pool it dispatched to — is dropped. That stamp is
    # execution provenance, not a live dispatch path: deferred-dispatch's reconcile
    # keys idempotency on its own gc.dispatch_when_ready_slung marker, and arm
    # refuses on a live route (gc.routed_to) or that marker, so neither reads
    # gc.execution_routed_to. The placement queue does read it: placement.sh counts
    # it as a live pour, which places a bead, so a finished pour's stamp left on a
    # bead held for placement keeps that bead out of the queue. The release drops
    # it, and its read-back below fails the verb when that is the stamp's effect.
    #
    # The park unassigns the bead, or assigns it to the --assign agent, so the
    # identity the last executor stamped goes with the old assignee:
    # gc.session_name and gc.session_id name the session that held it, and the
    # bead no longer has that executor for them to name. A
    # gc.session_name left behind is residue the moment the bead next carries a
    # route its stamp does not match — the shape doctor/executor-identity-residue
    # reports on an open, routed bead — and a gc.session_id left behind is the
    # stale pin the runtime's orphan recovery resolves an owner from. Both are
    # read back after this write and a lone unset retried, the way
    # the route beside them is: a silent multi-pair drop would otherwise report a
    # successful release while the very residue
    # doctor/executor-identity-residue exists to catch survives on the bead.
    [ -n "$release_park" ] && set -- "$@" --status=open --assignee="$assign" \
               --set-metadata "gc.routed_to=$route" --unset-metadata gc.execution_routed_to \
               --unset-metadata gc.session_name --unset-metadata gc.session_id
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    gc bd update "$bead" ${db:+--db "$db"} "$@" >/dev/null 2>&1 \
        || { echo "$PROG: takeaway: could not update '$bead' (does it exist in rig '${path:-?}'?)" >&2; exit 4; }
    # The headline is what this verb exists to write, so it is read back first,
    # in every mode: it rides the bare stamp, the park and a closed anchor's
    # run end alike. One `--set-metadata` pair in a multi-pair update can fail to
    # land while its siblings land, and a headline that does not land leaves the
    # one the bead carried before this call, empty or an earlier sitting's. So
    # the read-back compares with the text this call wrote, not with empty. The
    # repair re-stamps the headline together with this call's disposition, as
    # every headline write does (lifecycle.toml [holds]): a headline repaired
    # alone could land beside the disposition an earlier sitting left, and read
    # as a wait already discharged. The disposition is still read back on its
    # own below. A repair that also misses is a verb failure, because callers
    # read a zero exit as the headline being set. The miss is reported here with
    # its repair. Its exit comes last, after the edges, the run's end and every
    # other check have run and printed their own repairs. The messages carrying
    # the headline go through printf, because sh's echo interprets backslash
    # escapes, and a headline is free text.
    takeaway_missed=""
    takeaway_got=$(meta_now "$bead" gc.takeaway)
    if [ "$takeaway_got" != "$text" ]; then
        printf '%s\n' "$PROG: takeaway: gc.takeaway on $bead read back as '$takeaway_got', expected '$text' — repairing" >&2
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        gc bd update "$bead" ${db:+--db "$db"} --set-metadata "gc.takeaway=$text" --set-metadata "gc.takeaway_settled=$no_wait" >/dev/null 2>&1 || true
        takeaway_got=$(meta_now "$bead" gc.takeaway)
        if [ "$takeaway_got" = "$text" ]; then
            echo "$PROG: takeaway: the headline repair landed on $bead" >&2
        else
            takeaway_missed=1
            # The by-hand repair is pasted into a shell, so the headline is
            # single-quoted, with each ' inside it written as '\''.
            takeaway_arg=$(printf '%s' "gc.takeaway=$text" | sed "s/'/'\\\\''/g")
            printf '%s\n' "$PROG: takeaway: $bead still reads gc.takeaway='$takeaway_got', not the headline this call wrote, so the board does not show it. Stamp it by hand: gc bd update $bead${db:+ --db $db} --set-metadata '$takeaway_arg' --set-metadata gc.takeaway_settled=$no_wait" >&2
        fi
    fi
    # A route that lands EMPTY is the worst outcome of all: the bead is open,
    # unassigned and routed to nobody, which no pool's exact-match query can
    # see. One `--set-metadata` pair in a multi-pair update can land
    # present-but-empty while its siblings land, so read this one back and
    # repair it. A repair that also misses is a verb failure, because --route
    # promises the pool can see the bead and a caller reading a zero exit as
    # "released to that pool" would be wrong. The writes that did land stay,
    # and the message names them, so the miss is repairable by hand.
    route_missed=""
    if [ -n "$route" ] && [ -n "$release_park" ]; then
        route_got=$(meta_now "$bead" gc.routed_to)
        if [ "$route_got" != "$route" ]; then
            echo "$PROG: takeaway: gc.routed_to on $bead read back as '$route_got', expected '$route' — repairing" >&2
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            gc bd update "$bead" ${db:+--db "$db"} --set-metadata "gc.routed_to=$route" >/dev/null 2>&1 || true
            route_got=$(meta_now "$bead" gc.routed_to)
            if [ "$route_got" = "$route" ]; then
                echo "$PROG: takeaway: the route repair landed on $bead" >&2
            else
                route_missed=1
            fi
        fi
    fi
    # An --assign is read back on the same terms. The release writes the
    # assignee as the bead's only address, beside an empty route, so one that
    # did not land leaves the bead open, unassigned and unrouted, offered to
    # nobody.
    assign_missed=""
    if [ -n "$assign" ] && [ -n "$release_park" ]; then
        assign_got=$(assignee_now "$bead")
        if [ "$assign_got" != "$assign" ]; then
            echo "$PROG: takeaway: the assignee on $bead read back as '$assign_got', expected '$assign' — repairing" >&2
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            gc bd update "$bead" ${db:+--db "$db"} --assignee="$assign" >/dev/null 2>&1 || true
            assign_got=$(assignee_now "$bead")
            if [ "$assign_got" = "$assign" ]; then
                echo "$PROG: takeaway: the assignee repair landed on $bead" >&2
            else
                assign_missed=1
            fi
        fi
    fi
    # The disposition is read back on the same terms, and for a sharper reason:
    # it is the one field of the stamp whose STALE value is a wrong answer
    # rather than a missing one. A park whose clear did not land keeps the
    # previous sitting's "settled", and doctor/check-wait-is-an-edge then reads
    # this bead as a wait somebody already discharged — the exact blindness the
    # pairing exists to remove, on the exact bead a person is owed an answer
    # about. A repair that also misses is a verb failure: a caller reading a
    # zero exit as "the disposition landed" would be wrong.
    settled_missed=""
    settled_got=$(meta_now "$bead" gc.takeaway_settled)
    if [ "$settled_got" != "$no_wait" ]; then
        echo "$PROG: takeaway: gc.takeaway_settled on $bead read back as '$settled_got', expected '$no_wait' — repairing" >&2
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        gc bd update "$bead" ${db:+--db "$db"} --set-metadata "gc.takeaway_settled=$no_wait" >/dev/null 2>&1 || true
        settled_got=$(meta_now "$bead" gc.takeaway_settled)
        if [ "$settled_got" = "$no_wait" ]; then
            echo "$PROG: takeaway: the disposition repair landed on $bead" >&2
        else
            settled_missed=1
            echo "$PROG: takeaway: $bead still reads gc.takeaway_settled='$settled_got', not '$no_wait' — the headline is stamped, but the disposition beside it is the one the sitting before it left, so the wait check answers for this bead from a stamp nobody wrote for it. Stamp it by hand: gc bd update $bead${db:+ --db $db} --set-metadata gc.takeaway_settled=$no_wait" >&2
        fi
    fi
    # The pour stamp is read back too: gc.execution_routed_to names the pool the
    # pour dispatched this bead to, and a release ends that pour. Clear it, retry a
    # lone unset, and if it still survives, ask placement.sh whether the stamp is
    # all that keeps the bead out of the placement queue. On a bead held for
    # placement it is, because the queue reads the stamp as a live pour, so that
    # miss fails the verb below. On any other bead no reader misreads the stamp: no
    # arm or reconcile guard reads it (reconcile keys on its own
    # gc.dispatch_when_ready_slung marker). That miss warns and the release stands,
    # because first-reaction-dispose's --then-route arm runs right after this
    # release, and a failure here would skip the arm.
    exec_missed=""; exec_hides=""
    if [ -n "$release_park" ]; then
        exec_got=$(meta_now "$bead" gc.execution_routed_to)
        if [ -n "$exec_got" ]; then
            echo "$PROG: takeaway: gc.execution_routed_to on $bead read back as '$exec_got', expected empty — repairing" >&2
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            gc bd update "$bead" ${db:+--db "$db"} --unset-metadata gc.execution_routed_to >/dev/null 2>&1 || true
            # One read answers both questions, whether the stamp survived and
            # whether it hides a bead held for placement, so the two answers
            # cannot come from different states of the bead.
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            exec_row=$(gc bd show "$bead" ${db:+--db "$db"} --json 2>/dev/null | scrub) || exec_row=""
            exec_got=$(printf '%s' "$exec_row" \
                | jq -r 'if type == "array" then ((.[0].metadata // {})["gc.execution_routed_to"] // "") else "" end' 2>/dev/null) || exec_got=""
            if [ -z "$exec_got" ]; then
                echo "$PROG: takeaway: the execution-stamp repair landed on $bead" >&2
            else
                exec_missed=1
                exec_hides=$(printf '%s' "$exec_row" | stamp_hides_placement)
            fi
        fi
    fi
    # The executor identity the unassign takes with it is read back like the route
    # above, and fails the verb the same way: both keys have readers.
    # A gc.session_name left on the now-open bead is the residue
    # doctor/executor-identity-residue reports the moment the bead next carries a
    # route its stamp does not match — the finding this release exists to close. It
    # rides the same multi-pair write, so the same silent drop can leave it
    # standing; read it back, retry a lone unset, and fail if it survives.
    # orphan-dispose.sh verifies the same pair after its own release.
    sname_missed=""
    if [ -n "$release_park" ]; then
        sname_got=$(meta_now "$bead" gc.session_name)
        if [ -n "$sname_got" ]; then
            echo "$PROG: takeaway: gc.session_name on $bead read back as '$sname_got', expected empty — repairing" >&2
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            gc bd update "$bead" ${db:+--db "$db"} --unset-metadata gc.session_name >/dev/null 2>&1 || true
            sname_got=$(meta_now "$bead" gc.session_name)
            if [ -z "$sname_got" ]; then
                echo "$PROG: takeaway: the session-name repair landed on $bead" >&2
            else
                sname_missed=1
            fi
        fi
    fi
    # gc.session_id is the pin the runtime's orphan recovery resolves an owner
    # from, so one left behind lets it resolve a dead owner for a bead nobody
    # holds. Same write, same silent drop, same read-back-and-fail.
    sid_missed=""
    if [ -n "$release_park" ]; then
        sid_got=$(meta_now "$bead" gc.session_id)
        if [ -n "$sid_got" ]; then
            echo "$PROG: takeaway: gc.session_id on $bead read back as '$sid_got', expected empty — repairing" >&2
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            gc bd update "$bead" ${db:+--db "$db"} --unset-metadata gc.session_id >/dev/null 2>&1 || true
            sid_got=$(meta_now "$bead" gc.session_id)
            if [ -z "$sid_got" ]; then
                echo "$PROG: takeaway: the session-id repair landed on $bead" >&2
            else
                sid_missed=1
            fi
        fi
    fi
    # Edges AFTER the stamp: a failure here degrades to prose-only, never
    # loses the conclusion. `dep add <bead> <blocker>` = "<bead> is blocked by
    # <blocker>", so the edge lands on <bead> — what the board reads. Only the
    # waits still owed reach here; landed riders were partitioned out above and
    # are reported after, so the reason each got no edge is on the log.
    for _w in $real_waits; do
        [ -n "$_w" ] || continue
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        if gc bd dep add "$bead" "$_w" -t blocks ${db:+--db "$db"} >/dev/null 2>&1; then
            echo "waiting-on edge: $bead depends on $_w"
        else
            echo "$PROG: takeaway: could not wire --waiting-on $_w (same store? already wired? cycle?) — the takeaway text still stands, but the board cannot see this wait" >&2
        fi
    done
    for _w in $skipped_riders; do
        echo "$PROG: takeaway: --waiting-on $_w is a landed rider on $bead's own branch ($subj_branch) — its work is already there, so $bead's merge is what lands it and no wait edge is written (an edge would gate $bead's merge on work that merges with it, with no release). The board re-asks this wait through $bead's own landing." >&2
    done
    bust_cache
    cancel_missed=""
    if [ -n "$release" ]; then
        cancel_release_molecules "$bead" "$db" || cancel_missed=1
    fi
    if [ -n "$route_missed" ]; then
        echo "$PROG: takeaway: $bead is released but NOT routed to '$route' — it is open, unassigned and visible to no pool. The headline, the release and the edges are written; stamp the route by hand: gc bd update $bead${db:+ --db $db} --set-metadata gc.routed_to=$route" >&2
        exit 4
    fi
    if [ -n "$assign_missed" ]; then
        echo "$PROG: takeaway: $bead is released but NOT assigned to '$assign' (it reads '$assign_got') — it is open and unrouted, so no agent's hook offers it. The headline, the release and the edges are written; assign it by hand: gc bd update $bead${db:+ --db $db} --assignee $assign" >&2
        exit 4
    fi
    # Reported at its read-back above; the exit waits until here so the edges
    # and the run's end still run, the way the route miss does.
    if [ -n "$settled_missed" ]; then
        exit 4
    fi
    # Named, with its repair, by the helper. Nothing retries a cancel that did not
    # land, so a zero exit here would read as a run ended when it still runs.
    if [ -n "$cancel_missed" ]; then
        exit 4
    fi
    # A surviving session pin is exit-4 like the route above, on any bead: both
    # pins have readers wherever they are left. A caller reading
    # a zero exit as "released, identity cleared" would route the bead onward — the
    # exact next step that turns a surviving gc.session_name into the residue
    # doctor/executor-identity-residue reports. The release and edges are kept and
    # named, so a hand repair finishes it.
    if [ -n "$sname_missed" ]; then
        echo "$PROG: takeaway: $bead still carries gc.session_name='$sname_got' after release — the executor identity the unassign was meant to take with it, so doctor/executor-identity-residue re-fires the moment this bead next carries a route. The headline, release and edges are written; clear it by hand: gc bd update $bead${db:+ --db $db} --unset-metadata gc.session_name" >&2
        exit 4
    fi
    if [ -n "$sid_missed" ]; then
        echo "$PROG: takeaway: $bead still carries gc.session_id='$sid_got' after release — a stale orphan-recovery pin, so the runtime resolves a dead owner for a bead nobody holds. The headline, release and edges are written; clear it by hand: gc bd update $bead${db:+ --db $db} --unset-metadata gc.session_id" >&2
        exit 4
    fi
    # A surviving pour stamp fails the verb where it hides a bead held for
    # placement: placement.sh reads it as a live pour, so gc-helm.sh unplaced does
    # not list the bead and the placement sitting is never shown it. On any other
    # bead the stamp WARNS and the release stands, for the --then-route arm that
    # runs next.
    if [ -n "$exec_missed" ]; then
        if [ "$exec_hides" = 1 ]; then
            echo "$PROG: takeaway: $bead is held for placement but still carries gc.execution_routed_to='$exec_got' after release. placement.sh reads that stamp as a live pour, so gc-helm.sh unplaced does not list $bead and the placement sitting is never shown it. The headline, release and edges are written; clear it by hand: gc bd update $bead${db:+ --db $db} --unset-metadata gc.execution_routed_to" >&2
            exit 4
        fi
        echo "$PROG: takeaway: $bead still carries gc.execution_routed_to='$exec_got' after release — provenance a finished pour left. No arm or reconcile guard reads it (deferred-dispatch keys on gc.dispatch_when_ready_slung), and $bead is not held for placement, where the queue would read it as a live pour, so the release stands. Clear it by hand if you want it gone: gc bd update $bead${db:+ --db $db} --unset-metadata gc.execution_routed_to" >&2
    fi
    # A route asked for on a closed anchor is refused the same way a route that
    # would not stamp is: the useful writes stand, and the exit is non-zero so
    # no caller reads it as "released to that pool". Routing a disposed bead is
    # the resurrection in its purest form — the pool claims it and cuts a
    # branch for superseded work.
    if [ -n "$route" ] && [ -z "$release_park" ]; then
        echo "$PROG: takeaway: $bead is closed, so it was NOT routed to '$route' — a pool that claimed it would work a bead whose disposition landed. The headline and the run's end are written. If the disposition is wrong, reopen the bead deliberately and re-run: gc bd update $bead${db:+ --db $db} --status=open" >&2
        exit 4
    fi
    if [ -n "$assign" ] && [ -z "$release_park" ]; then
        echo "$PROG: takeaway: $bead is closed, so it was NOT assigned to '$assign' — the agent would be handed a bead whose disposition landed. The headline and the run's end are written. If the disposition is wrong, reopen the bead deliberately and re-run: gc bd update $bead${db:+ --db $db} --status=open" >&2
        exit 4
    fi
    # Reported at its read-back above, with its repair. The exit stands in for
    # the success line, which would say the headline is set.
    if [ -n "$takeaway_missed" ]; then
        exit 4
    fi
    rel_note=""
    if [ -n "$release" ]; then
        if [ -n "$release_park" ]; then rel_note=" [released${route:+ to $route}${assign:+ to $assign}]"
        else rel_note=" [run ended; anchor left closed]"; fi
    fi
    echo "takeaway set on $bead (by $by)$rel_note: $text"
}

# ── Verb: park ───────────────────────────────────────────────────────
# A park holds everything under a bead that has not started, by giving the bead
# one `blocks` edge (docs/steering.md). The text form files a gate of its own
# for the edge to land on, and --waiting-on lands it on an existing bead and
# files nothing. Either way the edge is read back off the bead before the verb
# reports success: an edge that did not land leaves the bead and everything
# under it reading ready while the operator believes them held.
#
# The gate is a plain gate: issue_type=gate, titled with the text, with no
# await type and none of the [holds] markers that doctor/check-wait-is-an-edge
# reads, so no reader takes it for a human gate and no sweep closes it. It is
# born with its edge in one transaction (`bd create --deps blocks:<bead>`), so
# no gate exists that holds nothing, and it is filed in the bead's own store,
# because bd resolves an edge only within one store. Who parked the bead, and
# when, are the gate's creator and creation time.
#
# Refused before anything is written, besides the forms and the headline cap:
# - a bead in flight: someone has claimed it (in_progress or hooked, bd's claim
#   statuses), it carries branch, merge_result or rejection_reason, or a
#   workflow poured for it has passed load-context. Its own edge would be a
#   live direct blocker: merge.sh holds an anchor's merge on any open blocker
#   of its own, and bd refuses to close a bead that has one. Parking its parent
#   holds the parent's unstarted work and leaves this bead's PR landing.
# - a bead to wait on that is closed, lives in another store, or sits under
#   the bead: each edge would hold nothing, or bd refuses it.

# PARK_SURVEY_JQ reads one listing of the bead's store, every bead not closed,
# and sorts the bead (--arg b) and everything under it by what a park does to
# each. A bead is under another through parent-child edges, any of its parents
# counting. A bead is in flight when its status is a claim (in_progress or
# hooked), when it carries merge_result, rejection_reason or branch, or when a
# workflow poured for it has passed load-context. The status alone does not
# cover a workflow, because a pour promotes its own root to in_progress and
# never claims the bead it was poured for. A workflow is found from its bead:
# it is a run among the listed rows whose bead is that bead, as run-lib.sh's
# run_rows names it. The workflow has passed load-context once no step of the
# root whose gc.step_ref ends in .load-context is still open, so a formula with
# no such step counts as started.
#   flight  in flight, with why; the park leaves it running.
#   poured  under the bead, not in flight and not armed (gc.dispatch_when_ready),
#           with a workflow still at load-context.
#   held    the bead, and everything else under it. An armed member is held:
#           deferred dispatch slings an armed bead only when no blocker holds
#           it or any of its ancestors (hold-lib.sh).
# Rows come in either bd shape: a listing's edges are {depends_on_id, type},
# and a `bd show` row's are {id, dependency_type}.
# shellcheck disable=SC2016  # jq program, single-quoted on purpose
PARK_SURVEY_JQ="$RUN_JQ"'
  def meta: if (.metadata | type) == "object" then .metadata else {} end;
  def edges: [ (.dependencies // [])[]? | select(type == "object")
               | {t: ((.type // .dependency_type // "") | tostring),
                  on: ((.depends_on_id // .id // "") | tostring)} ];
  def has_($x): any(.[]; . == $x);
  run_rows as $runs
  | [ .[] | select(type == "object")
    | {id: ((.id // "") | tostring), it: ((.issue_type // "") | tostring),
       st: ((.status // "") | tostring), a: ((.assignee // "") | tostring), m: meta, e: edges} ] as $all
  | def under($front; $acc):
      if ($front | length) == 0 then $acc
      else ([ $all[] | select(any(.e[]; .t == "parent-child" and (.on as $o | $front | has_($o)))) | .id ]
            | unique | map(select(. as $x | ($acc | has_($x) | not) and $x != $b))) as $next
           | under($next; $acc + $next) end;
    under([$b]; []) as $sub
  | [ $all[] | select(((.m["gc.step_ref"] // "") | tostring) | endswith(".load-context"))
      | ((.m["gc.root_bead_id"] // "") | tostring) ] as $at_lc
  | ($all | map({key: .id, value: .}) | from_entries) as $by
  | def why($r):
      $r.m as $m
      | if (($m.merge_result // "") | tostring) != "" then "merge_result=" + ($m.merge_result | tostring)
        elif (($m.rejection_reason // "") | tostring) != "" then "rejection_reason set"
        elif (($m.branch // "") | tostring) != "" then "branch " + ($m.branch | tostring)
        elif $r.st == "in_progress" or $r.st == "hooked" then $r.st + (if $r.a != "" then " under " + $r.a else "" end)
        else "" end;
    def workflows($id): [ $runs[] | select(.bead == $id) | .root ];
    [ ([$b] + $sub)[] as $id
      | ($by[$id] // {st: "", a: "", m: {}}) as $r
      | $r.m as $m
      | workflows($id) as $ws
      | {id: $id,
         why: (why($r) as $w
               | if $w != "" then $w
                 else ([ $ws[] | select(. as $x | $at_lc | has_($x) | not) ] | first // "") as $past
                      | if $past != "" then "workflow " + $past + " past load-context" else "" end end),
         armed: ((($m["gc.dispatch_when_ready"] // "") | tostring) != ""),
         poured: ([ $ws[] | select(. as $x | $at_lc | has_($x)) ] | first // "")} ] as $rows
  | { self: ((first($rows[] | select(.id == $b))) // {id: $b, why: ""}),
      flight: [ $rows[] | select(.why != "") | {id, why} ],
      poured: [ $rows[] | select(.id != $b and .why == "" and (.armed | not) and .poured != "") | {id, root: .poured} ],
      held: [ $rows[] | select(.why == "" and (.id == $b or .armed or .poured == "")) | .id ] }'

# park_open_gate_titled <bead-row-json> <text> — the open gate the bead already
# waits on under exactly this title, or empty. A re-run finds the gate it filed.
# Only a gate in the shape the text form files counts: no await type and no
# metadata. A gate of another kind can carry the same title. A human gate
# (await_type=human) is released by the operator's decision, a
# gate with any await type by its condition firing, and a gate with metadata
# belongs to the writer that stamped it. Adopting one would report a park while
# the bead waits on something that is not a park.
park_open_gate_titled() {
    printf '%s' "$1" | jq -r --arg t "$2" '
        [ (.dependencies // [])[]? | select(type == "object")
          | select(((.dependency_type // .type // "") | tostring) == "blocks")
          | select((.status // "") != "closed" and (.issue_type // "") == "gate")
          | select((.title // "") == $t)
          | select(((.await_type // "") | tostring) == "" and (.metadata // {}) == {})
          | ((.id // .depends_on_id // "") | tostring) ]
        | map(select(. != "")) | .[0] // ""' 2>/dev/null || printf ''
}

# park_gate_described <gate> <body> — 0 iff the gate's own row, read now, has
# exactly <body> as its description. A row that will not read has none.
park_gate_described() {
    row_now "$1" | jq -e --arg d "$2" '(.description // "") == $d' >/dev/null 2>&1
}

cmd_park() {
    bead=""; text=""; body=""; body_set=""; wait_on=""; npos=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --body=*)       body="${1#--body=}"; body_set=1; shift ;;
            --body)         shift; [ $# -gt 0 ] || { echo "$PROG: park: --body requires a value" >&2; exit 2; }; body="$1"; body_set=1; shift ;;
            --waiting-on|--waiting-on=*)
                case "$1" in
                    --waiting-on=*) _pk_w="${1#--waiting-on=}"; shift ;;
                    *) shift; [ $# -gt 0 ] || { echo "$PROG: park: --waiting-on requires a bead id" >&2; exit 2; }; _pk_w="$1"; shift ;;
                esac
                [ -n "$_pk_w" ] || { echo "$PROG: park: --waiting-on requires a bead id" >&2; exit 2; }
                [ -z "$wait_on" ] || { echo "$PROG: park: --waiting-on names one bead to wait on, and this call names $wait_on and $_pk_w. Park once per bead. Nothing was written." >&2; exit 2; }
                wait_on="$_pk_w" ;;
            -h|--help)      usage; exit 0 ;;
            -*) echo "$PROG: park: unknown flag '$1'" >&2; exit 2 ;;
            *)
                npos=$((npos + 1))
                case "$npos" in
                    1) bead="$1" ;;
                    2) text="$1" ;;
                    *) echo "$PROG: park takes one <bead-id> and one \"<text>\"" >&2; exit 2 ;;
                esac
                shift ;;
        esac
    done
    [ -n "$bead" ] || { echo "$PROG: park needs <bead-id>" >&2; usage; exit 2; }
    if [ "$npos" -ge 2 ] && [ -n "$wait_on" ]; then
        echo "$PROG: park: \"<text>\" and --waiting-on are the two forms of a park, and a park takes one. The text form files a gate of its own, titled with why $bead is parked and what releases it; --waiting-on parks $bead behind $wait_on and files no gate. Pass one. Nothing was written." >&2
        exit 2
    fi
    if [ "$npos" -lt 2 ] && [ -z "$wait_on" ]; then
        echo "$PROG: park needs \"<text>\", one line of at most $TAKEAWAY_MAX characters saying why $bead is parked and what releases it, or --waiting-on <bead-id> to park it behind an existing bead. Nothing was written." >&2
        exit 2
    fi
    if [ -n "$wait_on" ] && [ -n "$body_set" ]; then
        echo "$PROG: park: --body describes the gate the text form files, and --waiting-on files none, so the body would be dropped. Use the text form to describe a park of its own. Nothing was written." >&2
        exit 2
    fi
    if [ -z "$wait_on" ]; then
        normalize_headline "$text" park
        text="$HEADLINE"
    fi

    path=$(rig_path_for_bead "$bead")
    db=""; [ -n "$path" ] && [ -d "$path/.beads" ] && db="$path/.beads"
    prefix="${bead%%-*}"

    bead_row=$(row_now "$bead")
    [ -n "$bead_row" ] \
        || { echo "$PROG: park: '$bead' does not resolve${path:+ in rig $path}. Nothing was written." >&2; exit 4; }
    bead_status=$(printf '%s' "$bead_row" | jq -r '.status // ""' 2>/dev/null || true)
    if [ "$bead_status" = closed ]; then
        echo "$PROG: park: $bead is closed, so nothing under it waits to start and a park would hold nothing. Nothing was written." >&2
        exit 2
    fi

    # Whether the bead is in flight, and what the park holds under it, come from
    # one listing of its store. A listing that does not read leaves the bead's
    # workflows unproven, and an edge on a bead in flight holds its merge, so the
    # verb stops rather than guess. --brief drops the free text the survey never
    # reads, which is most of a listing's bytes. The bead's own row joins the
    # listing when the listing leaves it out.
    _pk_rc=0
    # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
    _pk_raw=$(gc bd list ${db:+--db "$db"} --status=open,in_progress,blocked,deferred,hooked,pinned --brief --json --limit=0 2>/dev/null) || _pk_rc=$?
    survey=""
    if [ "$_pk_rc" -eq 0 ]; then
        _pk_row=$(printf '%s' "$bead_row" | jq -c '{id, status, assignee, issue_type, metadata,
            dependencies: [ (.dependencies // [])[]? | select(type == "object") | {id, dependency_type} ]}' 2>/dev/null || printf '{}')
        survey=$(printf '%s' "$_pk_raw" | scrub | jq -c --arg b "$bead" --argjson row "$_pk_row" \
            "(if type == \"object\" and ((.issues // null) | type) == \"array\" then .issues else . end)
             | if type == \"array\" then (. + (if any(.[]; (.id // \"\") == \$b) then [] else [\$row] end)) | $PARK_SURVEY_JQ
               else error(\"not a listing\") end" \
            2>/dev/null || true)
    fi
    if [ -z "$survey" ]; then
        echo "$PROG: park: could not list the store that holds $bead${path:+ (rig $path)} to prove that $bead is not in flight, and a park edge on a bead in flight holds its merge. Re-run once the store answers. Nothing was written." >&2
        exit 4
    fi
    self_why=$(printf '%s' "$survey" | jq -r '.self.why // ""' 2>/dev/null || true)
    if [ -n "$self_why" ]; then
        parent=$(printf '%s' "$bead_row" | jq -r '
            (.parent // "") as $p
            | if ($p | tostring) != "" then $p
              else ([ (.dependencies // [])[]? | select(type == "object")
                      | select(((.dependency_type // .type // "") | tostring) == "parent-child")
                      | ((.id // .depends_on_id // "") | tostring) ] | map(select(. != "")) | .[0] // "") end' 2>/dev/null || true)
        echo "$PROG: park: $bead is in flight ($self_why). Its own edge would be a live direct blocker: merge.sh holds an anchor's merge on any open blocker of its own, and bd refuses to close a bead that has one.${parent:+ Park $parent instead, which holds what under it has not started and leaves $bead running.} Nothing was written." >&2
        exit 2
    fi

    if [ -n "$wait_on" ]; then
        if [ "$wait_on" = "$bead" ]; then
            echo "$PROG: park: --waiting-on $wait_on is $bead itself. Nothing was written." >&2
            exit 2
        fi
        if [ "${wait_on%%-*}" != "$prefix" ]; then
            echo "$PROG: park: $wait_on lives in another store than $bead, and bd resolves an edge only within one store, so an edge onto $wait_on would hold nothing. Park with the text form and name $wait_on in it: $PROG park $bead \"<why it is parked and what releases it>\". Nothing was written." >&2
            exit 2
        fi
        wait_row=$(row_now "$wait_on")
        [ -n "$wait_row" ] \
            || { echo "$PROG: park: --waiting-on '$wait_on' does not resolve${path:+ in rig $path}. Nothing was written." >&2; exit 4; }
        if [ "$(printf '%s' "$wait_row" | jq -r '.status // ""' 2>/dev/null || true)" = closed ]; then
            echo "$PROG: park: $wait_on is closed, so an edge onto it holds nothing. Nothing was written." >&2
            exit 2
        fi
        if printf '%s' "$survey" | jq -e --arg w "$wait_on" '(.held + [.poured[].id] + [.flight[].id]) | any(.[]; . == $w)' >/dev/null 2>&1; then
            echo "$PROG: park: $wait_on is under $bead, and bd refuses an edge that makes a bead wait on its own part. Nothing was written." >&2
            exit 2
        fi
        # `dep add <bead> <wait>` reads "<bead> is blocked by <wait>", so the
        # edge lands on the bead, the side that waits. Its exit status settles
        # nothing; the read-back below does.
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        gc bd dep add "$bead" "$wait_on" -t blocks ${db:+--db "$db"} >/dev/null 2>&1 || true
        blocker="$wait_on"
        blocker_title=$(printf '%s' "$wait_row" | jq -r '.title // ""' 2>/dev/null || true)
    else
        blocker=$(park_open_gate_titled "$bead_row" "$text")
        if [ -n "$blocker" ]; then
            # A re-run that names a body is how the operator corrects the
            # park's detail, so the gate it reuses takes that body, read back
            # as the edge is. A re-run without one leaves the description.
            _pk_note=""
            if [ -n "$body_set" ] && ! park_gate_described "$blocker" "$body"; then
                # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
                gc bd update "$blocker" --description="$body" ${db:+--db "$db"} >/dev/null 2>&1 || true
                if ! park_gate_described "$blocker" "$body"; then
                    echo "$PROG: park: $bead already waits on the open gate $blocker under this text, so the park holds, but the gate's description is not the --body this run names: the update did not read back. Apply it by hand: gc bd update $blocker --description \"<the --body text>\"${db:+ --db $db}" >&2
                    exit 4
                fi
                _pk_note=", and its description is now the --body this run names"
            fi
            echo "$PROG: park: $bead already waits on the open gate $blocker under this text; no second gate filed$_pk_note" >&2
        else
            [ -n "$body_set" ] || body="Parks $bead: everything under it that has not started waits on this gate, and work already in flight finishes. Closing this gate releases it. To release one bead this gate holds, remove that bead's edge: gc bd dep remove <bead> <this gate>."
            # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
            blocker=$(gc bd create --type=gate --title="$text" --description="$body" --deps "blocks:$bead" ${db:+--db "$db"} --json 2>/dev/null | scrub \
                | jq -r 'if type == "array" then (.[0].id // empty) elif type == "object" then (.id // empty) else empty end' 2>/dev/null || true)
            # A create that landed and lost its answer left its gate on the bead,
            # under this title: the edge was born with it.
            if [ -z "$blocker" ] || [ "$blocker" = null ]; then
                blocker=$(park_open_gate_titled "$(row_now "$bead")" "$text")
            fi
            case "$blocker" in
                ""|null)
                    echo "$PROG: park: gc bd create filed no gate for $bead, and none waits on it under this text, so nothing holds $bead. Re-run once the store answers." >&2
                    exit 4 ;;
                "$prefix"-*) : ;;
                *)
                    echo "$PROG: park: gc bd create filed $blocker, whose prefix is not '$prefix': it landed in another rig's store and can never hold $bead. Close it by hand (gc bd close $blocker) and re-run from the rig that owns $bead." >&2
                    exit 4 ;;
            esac
        fi
        blocker_title="$text"
    fi

    if ! blocks_edge_reads_back "$bead" "$blocker"; then
        # One repair: re-adding an edge that is there already is a no-op.
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        gc bd dep add "$bead" "$blocker" -t blocks ${db:+--db "$db"} >/dev/null 2>&1 || true
        if ! blocks_edge_reads_back "$bead" "$blocker"; then
            echo "$PROG: park: $bead is NOT blocked by $blocker: the edge did not land, so nothing holds $bead or anything under it. Wire it by hand: gc bd dep add $bead $blocker -t blocks${db:+ --db $db}" >&2
            [ -n "$wait_on" ] || echo "$PROG: park: or close the gate, which holds nothing without its edge: gc bd close $blocker${db:+ --db $db}" >&2
            exit 4
        fi
    fi

    bust_cache
    echo "park $blocker holds $bead: $blocker_title"
    held=$(printf '%s' "$survey" | jq -r '.held | join(" ")' 2>/dev/null || true)
    flight=$(printf '%s' "$survey" | jq -r '[ .flight[] | .id + " (" + .why + ")" ] | join(", ")' 2>/dev/null || true)
    poured=$(printf '%s' "$survey" | jq -r '[ .poured[] | .id + " (workflow " + .root + ")" ] | join(", ")' 2>/dev/null || true)
    echo "held, not started: ${held:-$bead}"
    [ -z "$flight" ] || echo "in flight, keeps running: $flight"
    [ -z "$poured" ] || echo "poured before the park, not held by it: $poured. Load-context reads no ancestor's blockers, so each workflow runs."
}

# ── Verb: priority ───────────────────────────────────────────────────
# priority <bead-id> <P0-P4> | --shift <±n> [--dry-run] — the operator's
# priority move (docs/steering.md). queue-priority.sh move does the work under
# the store's priority lock: it sets the bead's own input, writes every bead
# that follows it, held ones included, their live workflows and their anchors'
# PR-finishing work, leaves claimed beads as they are, and reads it all back.
# This verb names the store the bead lives in and relays the answer: a refusal
# exits 2 with nothing written, and a write that did not land exits 4. A move
# that fails can fail after it wrote some of its beads, so every exit but a
# refusal busts the board cache.
cmd_priority() {
    [ $# -gt 0 ] || { echo "$PROG: priority needs <bead-id> and a priority, P0 to P4, or --shift <±n>" >&2; usage; exit 2; }
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -*) echo "$PROG: priority needs <bead-id> first, then P0 to P4 or --shift <±n>" >&2; exit 2 ;;
    esac
    bead="$1"
    path=$(rig_path_for_bead "$bead")
    if [ -z "$path" ] || [ ! -d "$path/.beads" ]; then
        echo "$PROG: priority: no rig's store holds '$bead': its prefix names no rig with a .beads store. Nothing was written." >&2
        exit 4
    fi
    _pr_rc=0
    "$QUEUE_PRIORITY_TOOL" move "$@" --db "$path/.beads" || _pr_rc=$?
    case "$_pr_rc" in
        0) bust_cache; exit 0 ;;
        2) exit 2 ;;
        *) bust_cache; exit 4 ;;
    esac
}

# ── Verb: resolve ────────────────────────────────────────────────────
# resolve <reference> — print the LIVE bead a reference resolves to, the same
# way open/engage/react resolve their subject: a PR number/URL to its anchor,
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

# ── Verb: unplaced (read-only) ───────────────────────────────────────
# The placement sitting's queue: every live bead in the city's stores that waits
# for placement, by placement.sh's one definition. Intake marks such a bead
# placement=pending when it holds new work for the operator (docs/steering.md),
# and a parent, a route, an arm, an assignee or a live pour each places it,
# whether or not its marker was cleared. Like resolve it files nothing. Rows come
# in the order bd offers ready work, priority then age. A suspended rig's store
# is skipped and named, because reading it would start its Dolt server. A store
# that does not answer is named on stderr and the verb exits 4 after printing
# the rest, so a partial queue never reads as the whole one. --json prints one
# object: the rows as beads, the suspended rigs it skipped, and the rigs whose
# store did not answer. A skip exits 0, because a suspended rig is the
# operator's choice and not a failure, so a caller learns of it from skipped.
UNPLACED_ROW_JQ='
  select(awaiting_placement)
  | {id, rig: $rig, title: (.title // ""), type: (.issue_type // ""),
     priority: (.priority // 2), status: (.status // ""), created_at: (.created_at // ""),
     takeaway: ((.metadata // {})["gc.takeaway"] // "")}'
cmd_unplaced() {
    up_json=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) up_json=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) echo "$PROG: unplaced: unknown argument '$1' (usage: gc-helm unplaced [--json])" >&2; exit 2 ;;
        esac
    done
    enumerate_rigs
    # up_skipped and up_unread hold one rig per line.
    up_lines=""; up_unread=""; up_skipped=""
    up_scopes=$(printf '%s' "$RIGS" | jq -r '.[] | select((.path // "") != "")
        | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)] | join("\u001f")' 2>/dev/null || true)
    up_us=$(printf '\037')
    while IFS="$up_us" read -r up_name up_path up_susp; do
        [ -n "$up_path" ] || continue
        [ -d "$up_path/.beads" ] || continue
        if [ "$up_susp" = "true" ]; then
            echo "$PROG: unplaced: rig ${up_name:-$up_path} is suspended, so its store was not read; any bead waiting there is not listed" >&2
            up_skipped="$up_skipped${up_name:-$up_path}
"
            continue
        fi
        # bd's own exit status, not scrub's: a read that prints an array and then
        # fails has not answered for its store.
        up_rc=0
        up_raw=$(gc bd list --db "$up_path/.beads" --metadata-field placement=pending \
            --status=open,in_progress,blocked,deferred,hooked,pinned --json --limit 0 2>/dev/null) || up_rc=$?
        up_raw=$(printf '%s' "$up_raw" | scrub)
        if [ "$up_rc" -ne 0 ] || ! printf '%s' "$up_raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
            echo "$PROG: unplaced: the store of rig ${up_name:-$up_path} ($up_path/.beads) did not answer, so its beads are missing from this list" >&2
            up_unread="$up_unread${up_name:-$up_path}
"
            continue
        fi
        up_rig_lines=$(printf '%s' "$up_raw" | jq -c --arg rig "$up_name" "$DISPATCH_PATH_JQ$PLACEMENT_JQ"'.[] | '"$UNPLACED_ROW_JQ" 2>/dev/null) || {
            echo "$PROG: unplaced: the beads of rig ${up_name:-$up_path} could not be read as rows, so they are missing from this list" >&2
            up_unread="$up_unread${up_name:-$up_path}
"
            continue
        }
        [ -n "$up_rig_lines" ] && up_lines="$up_lines$up_rig_lines
"
    done <<EOF
$up_scopes
EOF
    up_rows=$(printf '%s' "$up_lines" | jq -cs 'sort_by(.priority, .created_at, .id)' 2>/dev/null) || up_rows='[]'
    if [ -n "$up_json" ]; then
        printf '%s' "$up_rows" | jq -c --arg skipped "$up_skipped" --arg unread "$up_unread" '
            def rigs: split("\n") | map(select(. != ""));
            {beads: ., skipped: ($skipped | rigs), unread: ($unread | rigs)}' \
            || { echo "$PROG: unplaced: the queue could not be printed as JSON" >&2; exit 4; }
    else
        up_n=$(printf '%s' "$up_rows" | jq 'length' 2>/dev/null || echo 0)
        if [ "$up_n" -eq 0 ]; then
            echo "unplaced: no bead waits for placement"
        else
            echo "unplaced: $up_n bead(s) wait for placement"
            printf '%s' "$up_rows" | jq -r '.[]
                | "\(.id)\tP\(.priority)\t\(.type)\t\(.rig)\t\(.created_at | .[0:10])\t\(.title)"
                  + (if .takeaway != "" then "\n\t\(.takeaway)" else "" end)'
        fi
    fi
    if [ -n "$up_unread" ]; then
        echo "$PROG: unplaced: this list is partial; unread: $(printf '%s' "$up_unread" | tr '\n' ' ' | sed 's/ $//')" >&2
        exit 4
    fi
    return 0
}

# verify_subject <bead-id> <verb> <nothing-clause> [<subject-ref>] — resolve a
# bead id to its live row before a write verb acts on it, classifying a
# non-answer the way `open` does. A probe that did not ANSWER — empty output, or
# an error OTHER than the "no issues found" not-found error — is a data-plane
# outage: retryable, existence UNKNOWN, NOT a missing bead. Only a well-formed
# result that resolves no matching row is a genuine not-found, and an id whose
# prefix matches no rig is a not-found provable without the data plane. open,
# engage, dismiss and accept share this one path, so a refused Dolt connection
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
# take_bead <verb> <nothing-msg> [<from>] — settle which bead a conversation is about,
# from the verified row verify_subject left in VS_ROW: the bead itself, the
# subject a conversation id tracks, or, for a gate, the one bead still waiting
# on it, since a conversation always tracks a bead and never a gate. Sets
# TAKE_BEAD (that bead), TAKE_GATE (the human gate the id named, which the
# conversation replies to) and TAKE_CONV (the conversation the id named). A gate
# several open beads wait on takes <from>, the bead the operator reached the gate
# from, when it is one of them. Otherwise it is refused, naming them, so the
# operator names the one they mean, and so is a gate nothing waits on, naming the
# beads it was about, because a sitting there would answer an ask that holds
# nothing. A refusal or a read that did not answer exits 4 with <nothing-msg>.
TAKE_BEAD=""; TAKE_GATE=""; TAKE_CONV=""
take_bead() {
    _tb_verb="$1"; _tb_nothing="$2"; _tb_from="${3:-}"
    TAKE_BEAD=""; TAKE_GATE=""; TAKE_CONV=""
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
            if [ -n "$_tb_from" ]; then
                case " $_tb_open " in *" $_tb_from "*) _tb_open="$_tb_from" ;; esac
            fi
            # shellcheck disable=SC2086  # split the ids into positional parameters to count them
            set -- $_tb_open
            case $# in
                1)  TAKE_BEAD="$1"
                    [ "${_tb_kind#gate"$TAB"}" = human ] && TAKE_GATE="$_tb_id" ;;
                0)  echo "$PROG: $_tb_verb: nothing waits on gate $_tb_id${_tb_closed:+ (it was about $_tb_closed, now closed)}, so there is no bead for a conversation to be about. Clear the gate instead: gc bd gate resolve $_tb_id --reason \"moot: <why nothing waits on it>\". $_tb_nothing" >&2
                    exit 4 ;;
                *)  echo "$PROG: $_tb_verb: gate $_tb_id is about $# beads still waiting on it ($_tb_open), and a conversation is about one bead. Name the one you mean: $PROG $_tb_verb <bead>. $_tb_nothing" >&2
                    exit 4 ;;
            esac ;;
        conversation"$TAB"*)
            TAKE_BEAD="${_tb_kind#conversation"$TAB"}"; TAKE_CONV="$_tb_id" ;;
        *)
            TAKE_BEAD="$_tb_id" ;;
    esac
    [ -n "$TAKE_BEAD" ] || { echo "$PROG: $_tb_verb: could not tell which bead '$_tb_id' is about. $_tb_nothing" >&2; exit 4; }
}

# conversation_replies_to <conversation> <gate> — 0 iff the conversation's own
# row carries a replies-to edge onto the gate. The row is `gc bd list --id`'s,
# whose edges keep a reply onto a gate in another store, which `gc bd dep list`
# of one bead leaves out.
conversation_replies_to() {
    gc bd list --id "$1" --all --json 2>/dev/null | grep -av '^gc bd:' | scrub \
        | jq -e --arg c "$1" --arg g "$2" '
            any(.[]? | objects | select((.id // "") == $c) | (.dependencies // [])[]? | objects;
                ((.type // .dependency_type) // "") == "replies-to" and ((.depends_on_id // .id) // "") == $g)' >/dev/null 2>&1
}

# conversation_reply <conversation> <gate> — make the conversation reply to the
# gate it answers, bd's replies-to edge from the reply onto the original, which
# holds nothing, and read the edge back. 0 once it reads back.
conversation_reply() {
    conversation_replies_to "$1" "$2" && return 0
    gc bd dep add "$1" "$2" --type replies-to >/dev/null 2>&1 || true
    conversation_replies_to "$1" "$2"
}

# open_join <conversation> — join open's concern ($join_note, empty for none)
# to a conversation waiting in the operator's queue, assigned to `human` and
# open, which is where a sitting claims it and reads its notes. The note is
# appended once, in a write guarded on that queue state, so a conversation a
# sitting took or a dismiss closed after open's listing takes no note. A
# pointed gate ($TAKE_GATE) gets the conversation's reply. The row is then read
# back still waiting in the queue, carrying the concern. Returns 0 once that
# reads back; 1 when the conversation is no longer in the queue, so it cannot
# receive the concern and the caller moves on to the next one; and 2 when a
# write or the read-back failed, which it says on stderr.
open_join() {
    _oj_c="$1"; _oj_ask="${open_body:-$open_reason}"
    # $1 is a row_now answer: a row in the queue carries the concern when it is
    # the conversation's own ask or a note an earlier join appended.
    _oj_queued='((.assignee // "") | tostring) == "human" and ((.status // "") | tostring | ascii_downcase) == "open"'
    _oj_carries='((.description // "") == $ask) or ((.notes // "") | contains($n))'
    if [ -n "$join_note" ]; then
        _oj_row=$(row_now "$_oj_c")
        if [ -n "$_oj_row" ] && ! printf '%s' "$_oj_row" | jq -e "$_oj_queued" >/dev/null 2>&1; then
            return 1
        fi
        # A concern the conversation already carries is no second concern, so
        # nothing is written for it. A caller that asks again on every pass
        # while its condition stands, as deferred dispatch's capped arm does,
        # would otherwise grow the notes by a copy a pass. A row that does not
        # read proves nothing, so the guarded write decides.
        if [ -z "$_oj_row" ] || ! printf '%s' "$_oj_row" | jq -e --arg ask "$_oj_ask" --arg n "$join_note" "$_oj_carries" >/dev/null 2>&1; then
            _oj_rc=0
            gc bd update "$_oj_c" --if-assignee human --if-status open --append-notes "$join_note" >/dev/null 2>&1 || _oj_rc=$?
            case "$_oj_rc" in
                0) ;;
                13) return 1 ;;
                *) echo "$PROG: open: could not append the new concern to conversation $_oj_c's notes (gc bd update exited $_oj_rc), so it did not join and nothing records it. Re-run once the store answers: $PROG open $bead" >&2
                   return 2 ;;
            esac
        fi
    fi
    if [ -n "$TAKE_GATE" ] && ! conversation_reply "$_oj_c" "$TAKE_GATE"; then
        echo "$PROG: open: conversation $_oj_c waits in the queue for $bead, but its reply onto gate $TAKE_GATE did not read back. Add it by hand: gc bd dep add $_oj_c $TAKE_GATE --type replies-to" >&2
        return 2
    fi
    _oj_back=$(row_now "$_oj_c")
    if [ -z "$_oj_back" ]; then
        echo "$PROG: open: conversation $_oj_c could not be read back after open joined it, so whether it still waits in the queue${join_note:+ carrying the new concern} cannot be told. Re-run once the store answers: $PROG open $bead" >&2
        return 2
    fi
    printf '%s' "$_oj_back" | jq -e "$_oj_queued" >/dev/null 2>&1 || return 1
    if [ -n "$join_note" ] && ! printf '%s' "$_oj_back" | jq -e --arg ask "$_oj_ask" --arg n "$join_note" "$_oj_carries" >/dev/null 2>&1; then
        echo "$PROG: open: the new concern did not read back in conversation $_oj_c's notes after its append, so it did not join. Re-run once the store answers: $PROG open $bead" >&2
        return 2
    fi
    return 0
}

# ── Verb: open ───────────────────────────────────────────────────────
# File a CONVERSATION about the bead in the operator's queue: an ordinary task
# that tracks the bead, assigned to `human`, holding no session until the
# operator engages it. The bead must RESOLVE first so a typo cannot manufacture
# one. A human gate names the one bead still waiting on it, and the
# conversation replies to that gate. Without --allow-duplicate, a concern on a
# bead whose conversation already waits in the queue joins it (open_join): the
# reason and body are appended to that task's notes, once, so a concern the
# conversation already carries writes nothing. One that leaves the queue
# before the join reads back is passed over for the next one waiting there, or
# for a conversation open files, and a join that cannot be written or read
# back fails the open. --reason is the title, --body the ask
# the sitting reads when it claims the conversation — callers with their own
# origin (operator-intake.sh) pass both rather than misreporting the board
# wording. The conversation is filed in the bead's own store. It leaves the
# conversation's id in CONV and OPEN_FILED at 1 when it filed it, or 0 when it
# joined one already in the queue, for engage, which runs it in its own shell.
cmd_open() {
    bead=""; open_reason=""; open_body=""; open_allow_dup=""; open_json=""; OPEN_FILED=""
    while [ $# -gt 0 ]; do
        case "$1" in
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
    case "$bead" in "") echo "$PROG: open needs <bead-id>" >&2; usage; exit 2 ;; esac

    # Resolve a PR reference or a settled disposition to the live owning bead
    # BEFORE the rig is derived from the id prefix (a PR number has none).
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
    # A gate or a conversation id names the bead the conversation is about.
    take_bead open "No conversation filed."
    if [ "$TAKE_BEAD" != "$bead" ]; then
        open_what=gate; [ -n "$TAKE_CONV" ] && open_what=conversation
        echo "$PROG: open: $bead is a $open_what about $TAKE_BEAD — the conversation is about $TAKE_BEAD" >&2
        bead="$TAKE_BEAD"
        open_pin "$bead"
        verify_subject "$bead" open "No conversation filed." || exit $?
    fi
    subject_clean="$VS_PAYLOAD"

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

    if ! open_convs=$(bead_conversations "$bead"); then
        echo "$PROG: open: could not read the conversations on $bead ('gc bd dep list $bead --direction=up --type tracks', or 'gc bd list --id' of the tasks it names, did not answer). No conversation filed." >&2
        exit 4
    fi

    # Already waiting in the queue? A second concern joins the conversation
    # the operator has not taken up yet, so a double click files one, not two.
    # --allow-duplicate skips the join: engage passes it for a concern of its
    # own, which is a distinct dialogue even when the bead has one.
    if [ -z "$open_allow_dup" ]; then
        join_note=""
        if [ -n "$open_reason$open_body" ]; then
            join_note="Another concern joined this conversation: ${open_reason:-$open_body}"
            if [ -n "$open_reason" ] && [ -n "$open_body" ]; then
                join_note="$join_note

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

    # File the conversation: a task that tracks the bead, in the operator's
    # queue (assigned to `human`), in one create, so no reader ever sees a task
    # in this shape without its subject. bd create answers an ARRAY (or bare
    # object) carrying the id on success and a bare {"error":…} OBJECT on
    # failure; the id is read type-guarded so an error object never crashes jq.
    CONV_JSON=$(gc bd create -t task --title "$conv_title" -d "$conv_body" \
        --deps "tracks:$bead" --assignee human --json 2>/dev/null || true)
    CONV=$(printf '%s' "$CONV_JSON" | scrub \
        | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null || true)
    [ -n "$CONV" ] && [ "$CONV" != "null" ] \
        || { create_err=$(printf '%s' "$CONV_JSON" | scrub | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null || true)
             echo "$PROG: open: could not create a conversation for '$bead'${create_err:+: $create_err}" >&2; exit 4; }
    # The tracks edge is what makes the task a conversation about the bead, so
    # it is read back off the task's own row. A task left without it is no
    # conversation any reader finds, so it is closed rather than left behind.
    if ! gc bd list --id "$CONV" --all --json 2>/dev/null | grep -av '^gc bd:' | scrub \
            | jq -e --arg c "$CONV" --arg s "$bead" "$CONVERSATION_JQ"'
                any(.[]? | objects | select((.id // "") == $c); conversation and conversation_subjects == [$s])' >/dev/null 2>&1; then
        gc bd close "$CONV" --reason "not a conversation: its tracks edge onto $bead or its assignee did not land" >/dev/null 2>&1 || true
        echo "$PROG: open: the task $CONV filed for '$bead' did not read back as a conversation (its tracks edge onto $bead or its assignee did not land), so it was closed. Re-run: $PROG open $bead" >&2
        exit 4
    fi
    if [ -n "$TAKE_GATE" ] && ! conversation_reply "$CONV" "$TAKE_GATE"; then
        echo "$PROG: open: conversation $CONV is filed on $bead, but its reply onto gate $TAKE_GATE did not read back. Add it by hand: gc bd dep add $CONV $TAKE_GATE --type replies-to" >&2
        exit 4
    fi
    OPEN_FILED=1
    bust_cache

    if [ -n "$open_json" ]; then
        jq -nc --arg s "$bead" --arg c "$CONV" '{subject: $s, conversation: $c, filed: true}'
    else
        echo "$PROG: conversation $CONV filed on $bead — waiting in the operator's queue; no session spawned."
        echo "       Engage it when ready: $PROG engage $bead"
    fi
}

# ── Verb: react ──────────────────────────────────────────────────────
# Thin wrapper over tools/gc-proactive.sh `sling` (which owns the budget/cap
# clamp): files a reaction bead that tracks the subject and routes it to the
# proactive pool, so a worker reads the subject, writes a first-reaction card,
# and disposes it.
cmd_react() {
    bead=""; reason=""; nudge=""; dry=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason=*) reason="${1#--reason=}"; shift ;;
            --reason) shift; [ $# -gt 0 ] || { echo "$PROG: react: --reason requires a value" >&2; exit 2; }; reason="$1"; shift ;;
            --nudge) nudge=1; shift ;;
            -n|--dry-run) dry=1; shift ;;
            -h|--help) usage; exit 0 ;;
            -*) echo "$PROG: react: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: react takes one bead-id" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done
    [ -n "$bead" ] || { echo "$PROG: react needs <bead-id>" >&2; usage; exit 2; }

    tool="$PROACTIVE_TOOL"
    [ -x "$tool" ] || tool="$(command -v gc-proactive.sh 2>/dev/null || true)"
    [ -n "$tool" ] && [ -x "$tool" ] \
        || { echo "$PROG: react: cannot find gc-proactive.sh (looked at $PROACTIVE_TOOL)" >&2; exit 4; }

    # Resolve a PR reference or a settled disposition to the live owning bead
    # (parity with open), before the rig is derived from the id prefix.
    resolve_live_subject "$bead"
    bead="$RESOLVED_SUBJECT"

    # Pin bd at the bead's rig (parity with open).
    path=$(rig_path_for_bead "$bead")
    [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"

    # gc-proactive.sh rig-qualifies its pool target from GC_RIG and fails
    # closed when unset. Gate on the NAME resolving — not on $path/.beads
    # existing — so a cross-rig react still qualifies the target.
    rig=$(rig_name_for_bead "$bead")
    [ -n "$rig" ] && export GC_RIG="$rig"

    # The reason is log-only operator intent; gc-proactive.sh has no --reason.
    [ -n "$reason" ] && echo "$PROG: react $bead — $reason" >&2

    set -- sling "$bead"
    [ -n "$nudge" ] && set -- "$@" --nudge
    [ -n "$dry" ] && set -- "$@" --dry-run
    # gc-proactive.sh sling exits 3 (RC_ALREADY_REACTED) when its dedup found an
    # open reaction bead already tracking this subject, or a live owner owning its
    # reaction, 4 (RC_LIVE_WORKFLOW) when its live-workflow guard skipped a bead a
    # live workflow already drives, and 5 (RC_DISPATCH_PATH) when its
    # dispatch-path guard skipped a bead that is already routed or armed. Each is
    # a no-op, not a failure, and NO new reaction was filed. Re-raise them as exit
    # 5, exit 6 and exit 7 so an intake caller (operator-intake.sh) files its own
    # conversation, naming the cause, instead of waiting for a reaction that is already
    # in flight or never ran; any other non-zero is a real failure.
    if "$tool" "$@"; then
        :
    else
        sling_rc=$?
        if [ "$sling_rc" -eq 3 ]; then
            echo "$PROG: react: $bead already has an open first reaction, or a live owner owns its reaction — nothing filed (a first reaction happens once at a time). It reacts when the pool claims the reaction bead, or open a conversation directly." >&2
            exit 5
        fi
        if [ "$sling_rc" -eq 4 ]; then
            echo "$PROG: react: a live workflow already drives $bead — nothing filed (a first reaction never races work in flight). React once that workflow's root closes, or open a conversation directly." >&2
            exit 6
        fi
        if [ "$sling_rc" -eq 5 ]; then
            echo "$PROG: react: $bead is already routed or armed — nothing filed (a first reaction never second-guesses a dispatch already decided). Open a conversation directly, or react once that route or arm is cleared." >&2
            exit 7
        fi
        echo "$PROG: react: gc-proactive.sh sling '$bead' failed" >&2
        exit 4
    fi

    # The reaction runs async once the pool claims the reaction bead; just clear
    # the cache.
    if [ -z "$dry" ]; then bust_cache; fi
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
# takeaway is the board's one-line headline; this is the hand-back whole.
# gc.handback and gc.handback_at land in one write, and the text is read back.
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
    # One repair write, because a write that exits 0 can still read back without
    # its value (the store behaviour meta_now guards against on the takeaway).
    handback_ok=""
    for _hb_try in 1 2; do
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        gc bd update "$bead" ${db:+--db "$db"} --set-metadata "gc.handback=$handback_text" \
            --set-metadata "gc.handback_at=$handback_at" >/dev/null 2>&1 || true
        if [ "$(meta_now "$bead" gc.handback)" = "$handback_text" ]; then handback_ok=1; break; fi
    done
    if [ -z "$handback_ok" ]; then
        echo "$PROG: handback: the hand-back did not read back on $bead, so its tab would print an older one, or none. Re-run it." >&2
        exit 4
    fi
    echo "$PROG: handback: recorded on $bead at $handback_at"
}

# sitting_session_of <conversation-row> — the live converse session holding a
# conversation, printed as "<session-id> own" when it is the session this verb
# runs in and "<session-id> other" when it is not, else nothing. The holder is
# the session the conversation's gc.session_id names, else the one its
# gc.session_name or assignee names: the claim stamps both pins, and a bind the
# sitting never claimed leaves the assignee alone. Only a converse template
# counts, so a bead some other agent holds never stops that agent, and a
# listing that will not read names nobody.
sitting_session_of() {
    _sso_sid=$(printf '%s' "$1" | jq -r '(.metadata // {})["gc.session_id"] // ""' 2>/dev/null || true)
    _sso_sn=$(printf '%s' "$1" | jq -r '(.metadata // {})["gc.session_name"] // ""' 2>/dev/null || true)
    _sso_as=$(printf '%s' "$1" | jq -r '.assignee // ""' 2>/dev/null || true)
    [ -n "$_sso_sid$_sso_sn$_sso_as" ] || return 0
    gc session list --state all --json 2>/dev/null | scrub | jq -r \
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
# A session that will not stop is left to converse-reap, which closes any
# converse session whose conversation reads closed.
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
    # see. A close counts once the conversation reads back closed.
    sitting_failed=0; closed_n=0
    for _c in $convs; do
        # The work-record gate the close runs wants gc.work_outcome.
        # work-outcome.sh stamps it in a write of its own, so it never decides
        # whether the conversation closes.
        work_outcome_noop "$_c" gc bd
        if gc bd close "$_c" --reason "$_dwhy" >/dev/null 2>&1; then
            _how="closed"
        elif gc bd close "$_c" --reason "$_dwhy" --force >/dev/null 2>&1; then
            _how="closed over its holder's claim"
        else
            _how=""
        fi
        _c_row=""; [ -n "$_how" ] && _c_row=$(row_now "$_c")
        if [ -n "$_c_row" ] && [ "$(printf '%s' "$_c_row" | jq -r '.status // ""' 2>/dev/null)" = "closed" ]; then
            closed_n=$((closed_n + 1))
            _dmsg "$PROG: dismiss: $_how conversation $_c — the sitting on $bead ends"
            # A closed sitting updates its PR reminder to say so, if the subject
            # has a PR. update-only, so a conversation that never engaged (left
            # no comment) touches nothing; best effort, never failing the dismiss.
            if [ -x "$SITTING_COMMENT_TOOL" ]; then
                "$SITTING_COMMENT_TOOL" close --sitting "$_c" --subject "$bead" --outcome dismissed --summary "$_dwhy" || true
            fi
        else
            sitting_failed=1
            echo "$PROG: dismiss: could not close conversation $_c; its sitting keeps the pane. Close it by hand: gc bd close $_c --force" >&2
        fi
        # The session holding the closed conversation, read from its closed
        # row, which still names it: bd's close leaves the assignee and the
        # claim's pins as they were. It is stopped once the run's writes are
        # done (dismiss_stop_sittings).
        if [ "$(printf '%s' "$_c_row" | jq -r '.status // ""' 2>/dev/null)" = "closed" ]; then
            _c_holder=$(sitting_session_of "$_c_row")
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
                echo "$PROG: dismiss: could not stop session $_ds_id, which held the sitting; converse-reap closes it on its next pass, because its conversation is closed" >&2
            fi
        done
        IFS=$_ds_ifs
        if [ -n "$_ds_own" ]; then
            _dmsg "$PROG: dismiss: ending this session ($_ds_own), which held the sitting"
            gc runtime drain-ack >/dev/null 2>&1 \
                || echo "$PROG: dismiss: could not end this session ($_ds_own); converse-reap closes it on its next pass, because its conversation is closed" >&2
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

# ── Accept: the bead's acceptance lock ───────────────────────────────
# accept_lock_dir — the directory Accept's per-bead lock files live in:
# <city>/.gc/runtime/packs/gc-toolkit, the directory Gas City sets aside for the
# pack's runtime state. It is named from the city root, never through
# GC_PACK_STATE_DIR, which Gas City sets only for an order's run, so the CLI,
# helm-svc and any other caller reach the same file. Prints nothing when no city
# root can be named.
accept_lock_dir() {
    _ald_root=$(city_root)
    [ -z "$_ald_root" ] || printf '%s/.gc/runtime/packs/gc-toolkit' "$_ald_root"
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

# accept_take_lock <bead> — take the bead's acceptance lock: a non-blocking
# exclusive flock on accept-<rig>-<bead>.lock in accept_lock_dir, held on fd 9,
# keyed by the bead's store and id as Gas City keys its launch lock, with this
# process and the time it took the lock in accept-<rig>-<bead>.holder as
# "<pid> <epoch>". Returns 0 holding it; 1 when another Accept holds it, and
# ACCEPT_LOCK_NOTE then names that run's process and how long it has held the
# lock; 3 when no lock can be taken, and ACCEPT_LOCK_NOTE names why. Only a 0
# leaves fd 9 open. The kernel frees the lock once no process keeps a
# descriptor on it, however each one exits. The file stays in place after the
# run, because a file removed while one run holds it lets the next run lock a
# new one.
ACCEPT_LOCK_NOTE=""
accept_take_lock() {
    ACCEPT_LOCK_NOTE=""
    if ! command -v flock >/dev/null 2>&1; then
        ACCEPT_LOCK_NOTE="flock is not on PATH"; return 3
    fi
    _atl_dir=$(accept_lock_dir)
    if [ -z "$_atl_dir" ]; then
        ACCEPT_LOCK_NOTE="no city root could be named (GC_CITY_PATH, GC_CITY or GC_CITY_ROOT holding .gc, or the HQ rig gc reports), and a lock two callers could resolve to two files excludes nothing"
        return 3
    fi
    _atl_key="accept-${rig:-city}-$1"
    _atl_lock="$_atl_dir/$_atl_key.lock"; _atl_holder="$_atl_dir/$_atl_key.holder"
    if ! mkdir -p "$_atl_dir" 2>/dev/null || ! ( : >> "$_atl_lock" ) 2>/dev/null; then
        ACCEPT_LOCK_NOTE="cannot create $_atl_lock"; return 3
    fi
    exec 9>>"$_atl_lock"
    if flock -n 9; then
        printf '%s %s\n' "$$" "$(date -u +%s)" > "$_atl_holder" 2>/dev/null || true
        return 0
    fi
    exec 9>&-
    _atl_pid=""; _atl_since=""; _atl_held=""
    if [ -r "$_atl_holder" ]; then read -r _atl_pid _atl_since < "$_atl_holder" || true; fi
    case "$_atl_since" in
        ''|*[!0-9]*) ;;
        *) _atl_held=$(( $(date -u +%s) - _atl_since )) ;;
    esac
    ACCEPT_LOCK_NOTE="pid ${_atl_pid:-unknown}${_atl_held:+, holding it for ${_atl_held}s}"
    return 1
}

# accept_gc <args...> — every gc call a run makes while it holds the acceptance
# lock, its sling among them, as the pack's pass lock runs its children
# (bd-lib.sh's pass_child). gc starts with fd 9 closed, so nothing gc starts or
# leaves running, such as a Dolt server, holds the lock against every later
# Accept. The subshell it runs from keeps fd 9 and waits on it, so the lock
# stays held while gc runs, even when something kills this run's own process
# alone. cmd_accept defines `gc` as this once it holds the lock, so the helpers
# it calls run the same way. The gc it runs is the program's path, $ACCEPT_GC,
# never `command gc`: a shell applies a redirection on a builtin such as
# `command` in the subshell itself, and bash keeps fd 9's copy on another
# descriptor that the program inherits, so the lock would outlive the run in
# whatever gc leaves running.
ACCEPT_GC=""
accept_gc() { ( "$ACCEPT_GC" "$@" 9>&-; exit "$?" ); }

# accept_lifecycle <args...> — the lifecycle writer, run under the acceptance
# lock the way accept_gc runs gc: the program starts with fd 9 closed, and the
# subshell that waits on it keeps the lock.
accept_lifecycle() { ( "$LIFECYCLE_TOOL" "$@" 9>&-; exit "$?" ); }

# accept_token — a token unique to this run, which titles the root its sling
# pours and closes the recommendation's gate, so a later run tells this
# acceptance's dispatch from any other. Fixed length, so no token is another's
# prefix in a title search.
accept_token() {
    _at=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    case "$_at" in
        ????????????????) ;;
        *) _at=$(printf '%08x%08x' "$$" "$(date -u +%s)") ;;
    esac
    printf '%s' "$_at"
}

# accept_token_root <token> — whether a sling under acceptance <token> poured:
# "found <root-id>" when a root titled with accept:<token> exists and is not a
# pour that failed part way (molecule_failed, which Gas City closes), "none"
# when no such root exists, and "unread" when the search did not answer, which
# proves nothing. Only a sling under that acceptance titles a root with its
# token, so one search finds the root live or finished.
accept_token_root() {
    if ! _atr=$(bd_rows list --all --include-ephemeral --title-contains "accept:$1" --limit=0); then
        printf 'unread'; return 0
    fi
    _atr_id=$(printf '%s' "$_atr" | jq -r --arg t "accept:$1" '
        [ .[] | objects | select(((.title // "") | tostring) | contains($t))
              | select((((.metadata // {})["molecule_failed"] // "") | tostring) != "true")
              | .id // empty ] | first // empty' 2>/dev/null || true)
    if [ -n "$_atr_id" ]; then printf 'found %s' "$_atr_id"; else printf 'none'; fi
}

# accept_mark_dispatched <subject> <formula> <token> — record that Accept
# dispatched <formula>, and withdraw the recommendation, in one write:
# gc.recommended_formula_dispatched=<formula> records the dispatch, and
# stripping gc.recommended_formula — the key the board's Accept derivation
# reads — ends the acceptance, so no later Accept dispatches it again. Both
# writes are read back and retried once. Returns non-zero when the
# recommendation still reads live or the record did not stick; the gate's
# answer still names the acceptance then, so the next Accept finishes the
# record without a second dispatch.
accept_mark_dispatched() {
    _amd_subj="$1"; _amd_formula="$2"; _amd_tok="$3"
    gc bd update "$_amd_subj" \
        --set-metadata "gc.recommended_formula_dispatched=$_amd_formula" \
        --unset-metadata gc.recommended_formula \
        --append-notes "Accept dispatched $_amd_formula (acceptance $_amd_tok)${accept_reason:+: $accept_reason}; gc.recommended_formula withdrawn." \
        >/dev/null 2>&1 || true
    _amd_live=$(meta_now "$_amd_subj" gc.recommended_formula)
    if [ -n "$_amd_live" ]; then
        gc bd update "$_amd_subj" --unset-metadata gc.recommended_formula >/dev/null 2>&1 || true
        _amd_live=$(meta_now "$_amd_subj" gc.recommended_formula)
    fi
    _amd_mark=$(meta_now "$_amd_subj" gc.recommended_formula_dispatched)
    if [ "$_amd_mark" != "$_amd_formula" ]; then
        gc bd update "$_amd_subj" --set-metadata "gc.recommended_formula_dispatched=$_amd_formula" >/dev/null 2>&1 || true
        _amd_mark=$(meta_now "$_amd_subj" gc.recommended_formula_dispatched)
    fi
    [ -z "$_amd_live" ] && [ "$_amd_mark" = "$_amd_formula" ]
}

# accept_reopen <why> <gate>... — put the recommendation's gate back on the
# board, open and owed, from Accept's own accepted close, and read each back as
# open. bd's reopen clears the close and its reason and blocks again what the
# gate blocked. Returns 0 once every gate reads open; ACCEPT_REOPEN_LEFT names
# the ones that do not.
ACCEPT_REOPEN_LEFT=""
accept_reopen() {
    _ar_why="$1"; shift; ACCEPT_REOPEN_LEFT=""
    for _ar_g in "$@"; do
        gc bd reopen "$_ar_g" --reason "$_ar_why" >/dev/null 2>&1 || true
    done
    for _ar_g in "$@"; do
        if [ "$(row_now "$_ar_g" | jq -r '.status // ""' 2>/dev/null)" != "open" ]; then
            ACCEPT_REOPEN_LEFT="${ACCEPT_REOPEN_LEFT:+$ACCEPT_REOPEN_LEFT }$_ar_g"
        fi
    done
    [ -z "$ACCEPT_REOPEN_LEFT" ]
}

# accept_reopen_said — the sentence a refusal ends with after accept_reopen:
# that the question is back on the board, or which gate did not reopen.
accept_reopen_said() {
    if [ -z "$ACCEPT_REOPEN_LEFT" ]; then
        printf '%s' " The recommendation's gate $* is open again, back on the board."
    else
        printf '%s' " $ACCEPT_REOPEN_LEFT did not read back open after its reopen, so it reads answered while nothing is dispatched. Reopen it by hand: gc bd reopen <id>."
    fi
}

# accept_warn_live <bead> <gate>... — the warning Accept owes when a live
# sitting's conversation tracks the bead or replies to the recommendation's
# gate: Accept clears the gate anyway, and that sitting learns it at its
# sign-off. The conversation --conversation names is the caller's own, whose
# sign-off runs this Accept, so it is not warned of. Best effort, writes
# nothing; a read that does not answer is named.
accept_warn_live() {
    _awl_bead="$1"; shift
    if ! _awl_live=$(live_sittings); then
        echo "$PROG: accept: could not read 'gc session list' to warn of a live sitting on $_awl_bead; going on." >&2
        return 0
    fi
    _awl_rows=$(bead_conversations "$_awl_bead" 2>/dev/null || printf '[]')
    for _awl_g in "$@"; do
        _awl_rep=$(bd_rows dep list "$_awl_g" --direction=up --type replies-to 2>/dev/null || printf '[]')
        _awl_rows=$(printf '%s\n%s' "$_awl_rows" "$_awl_rep" | jq -sc 'add // []' 2>/dev/null || printf '%s' "$_awl_rows")
    done
    _awl_held=$(printf '%s' "$_awl_rows" | jq -r --argjson live "$_awl_live" --arg self "${accept_conv:-}" "$CONVERSATION_JQ$SITTING_JQ"'
        [ .[] | objects | select(held_live($live)) | .id // empty | select(. != $self) ] | unique | join(" ")' 2>/dev/null || true)
    if [ -n "$_awl_held" ]; then
        echo "$PROG: accept: warning: a live sitting holds conversation $_awl_held on $_awl_bead or replying to the recommendation's gate. Accept clears the gate anyway, and that sitting learns it at its sign-off." >&2
    fi
    return 0
}

# accept_var <key>=<value> — add a var the caller settled for the dispatch to
# accept_vars, one per line. Exits 2 on anything else: a key must lead, and a
# var holds no newline, so the list splits back into the vars it was given.
ACCEPT_NL='
'
accept_var() {
    case "$1" in
        *"$ACCEPT_NL"*) ;;
        [!=]*=*) accept_vars="${accept_vars:+$accept_vars$ACCEPT_NL}$1"; return 0 ;;
    esac
    echo "$PROG: accept: --var takes <key>=<value> on one line, not '$1'" >&2
    exit 2
}

# accept_sling <bead> <formula> <token> — the dispatch: the formula slung at
# the bead, titled with the token, with a --var for each line of accept_vars.
accept_sling() {
    _asl_rest="$accept_vars"
    set -- ${GC_RIG:+--rig "$GC_RIG"} "$1" --on "$2" --title "$2 accept:$3"
    while [ -n "$_asl_rest" ]; do
        set -- "$@" --var "${_asl_rest%%"$ACCEPT_NL"*}"
        case "$_asl_rest" in
            *"$ACCEPT_NL"*) _asl_rest="${_asl_rest#*"$ACCEPT_NL"}" ;;
            *) _asl_rest="" ;;
        esac
    done
    gc sling "$@"
}

# accept_input <token> <formula> — the acceptance's dispatch input as one line
# of JSON, {token, formula, vars}, with vars as accept_vars lists them.
accept_input() {
    printf '%s' "$accept_vars" | jq -Rsc --arg t "$1" --arg f "$2" \
        '{token: $t, formula: $f, vars: (if . == "" then [] else split("\n") end)}'
}

# accept_record <token> <formula> <gate>... — record the acceptance's dispatch
# input on each gate as gc.acceptance, before the resolve that names the token,
# and read each back. Returns 0 once every gate reads it back; ACCEPT_RECORD_LEFT
# names the ones that do not.
ACCEPT_RECORD_LEFT=""
accept_record() {
    _arc_tok="$1"; _arc_formula="$2"; shift 2; ACCEPT_RECORD_LEFT=""
    _arc_in=$(accept_input "$_arc_tok" "$_arc_formula") || _arc_in=""
    if [ -z "$_arc_in" ]; then
        ACCEPT_RECORD_LEFT="$*"
        return 1
    fi
    for _arc_g in "$@"; do
        gc bd update "$_arc_g" --set-metadata "gc.acceptance=$_arc_in" >/dev/null 2>&1 || true
        if ! row_now "$_arc_g" | jq -e --arg want "$_arc_in" '
                ((.metadata // {})["gc.acceptance"] // null)
                | (if type == "string" then (fromjson? // null) else . end) == ($want | fromjson)' >/dev/null 2>&1; then
            ACCEPT_RECORD_LEFT="${ACCEPT_RECORD_LEFT:+$ACCEPT_RECORD_LEFT }$_arc_g"
        fi
    done
    [ -z "$ACCEPT_RECORD_LEFT" ]
}

# accept_recorded_vars <gate-row> <token> <formula> — the vars the acceptance
# under <token> was accepted with, one per line as accept_vars holds them, read
# off the gate's gc.acceptance. Returns 1 when the gate records no dispatch
# input under that token for that formula.
accept_recorded_vars() {
    printf '%s' "$1" | jq -er --arg t "$2" --arg f "$3" '
        ((.metadata // {})["gc.acceptance"] // empty)
        | (if type == "string" then (fromjson? // empty) else . end)
        | select(type == "object" and ((.token // "") | tostring) == $t and ((.formula // "") | tostring) == $f)
        | [ (.vars // [])[] | tostring ] | join("\n")' 2>/dev/null
}

# accept_vars_said <vars> — vars as a sling would carry them, for a message.
accept_vars_said() {
    if [ -z "$1" ]; then printf 'no --var'; return 0; fi
    printf '%s' "$1" | awk 'BEGIN { ORS = "" } { printf "%s--var %s", (NR > 1 ? " " : ""), $0 }'
}

# ── Verb: accept ─────────────────────────────────────────────────────
# Accept a recommendation: clear the human gate that put gc.recommended_formula
# to the operator, the gate under the key first-reaction, and dispatch the
# formula at the bead. The board runs it straight off a row, and a sitting's
# sign-off runs it when the operator's ruling takes the recommendation
# (converse-signoff.sh --accept), so every dispatch of a recommendation goes
# through this one writer and its lock. Discuss (engage) stays the path for a
# recommendation the operator wants to weigh instead. Accept clears that one
# gate and nothing else: separate situations on one bead are separate gates,
# and each gate's close does something of its own, so one click must not spend
# itself as answers the operator never gave.
#
# It is offered while all three hold: the bead carries gc.recommended_formula;
# the recommendation's gate is open and unassigned, or closed with an
# acceptance an earlier Accept did not finish; and no other open human gate
# blocks the bead, since the bead's next step waits for each gate that blocks
# it and a formula sling reads no blocks edge.
#
# Every Accept on a bead runs under the bead's acceptance lock from before its
# live read of those conditions to its last write, so one run's search, sling
# and record never interleave with another's, and an acceptance is dispatched
# once even after the work it sent has finished. On an open gate it records
# the acceptance's dispatch input on the gate (gc.acceptance: the token, the
# formula and each --var) and reads it back, resolves the gate with
# `ruled: accepted <formula> accept:<token>`, reads its own answer back, reads
# back that no open human gate blocks the bead, releases a bead a sitting's
# hold left at `held` to unanchored, since a run poured at a held bead cancels
# at its first step, slings the formula titled `<formula> accept:<token>`, and
# records the dispatch. The first answer to reach the gate wins: a sitting's
# ruling, a filer's withdrawal or a person's resolve stands, and Accept slings
# nothing and reopens nothing. A gate filed in the meantime, or a sling that
# poured no root under the token, reopens the gate from Accept's own close. A
# run that stopped after its resolve leaves the gate closed with its answer
# beside the recommendation, an unfinished acceptance, which the next run
# finishes under the same token: it records the dispatch when a root carries
# the token, and otherwise takes the read-back, the release, the sling and the
# record, slinging the vars the gate records under the token.
# An acceptance dispatches the input it was accepted with whoever finishes it,
# so a finishing run given a --var that differs from that input dispatches
# nothing, and one given none, as the board's Accept is, slings the recorded
# vars.
cmd_accept() {
    bead=""; accept_reason=""; accept_conv=""; accept_vars=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason=*) accept_reason="${1#--reason=}"; shift ;;
            --reason)   shift; [ $# -gt 0 ] || { echo "$PROG: accept: --reason requires a value" >&2; exit 2; }
                        accept_reason="$1"; shift ;;
            --conversation=*) accept_conv="${1#--conversation=}"; shift ;;
            --conversation)   shift; [ $# -gt 0 ] || { echo "$PROG: accept: --conversation requires a value" >&2; exit 2; }
                              accept_conv="$1"; shift ;;
            --var=*) accept_var "${1#--var=}"; shift ;;
            --var)   shift; [ $# -gt 0 ] || { echo "$PROG: accept: --var requires <key>=<value>" >&2; exit 2; }
                     accept_var "$1"; shift ;;
            -h|--help)  usage; exit 0 ;;
            -*) echo "$PROG: accept: unknown flag '$1'" >&2; exit 2 ;;
            *) [ -z "$bead" ] || { echo "$PROG: accept takes one bead-id" >&2; exit 2; }; bead="$1"; shift ;;
        esac
    done
    case "$bead" in "") echo "$PROG: accept needs <bead-id>" >&2; usage; exit 2 ;; esac

    # Resolve a PR reference or a settled disposition to the live owning bead,
    # the same way open/engage/dismiss do; a conversation or gate id names the
    # bead it is about.
    resolve_live_subject "$bead"
    bead="$RESOLVED_SUBJECT"
    verify_subject "$bead" accept "Nothing dispatched." || exit $?
    take_bead accept "Nothing dispatched."
    bead="$TAKE_BEAD"

    # Pin the bead's rig, so the gate reads, the sling and the record all act
    # in its store, and the lock is keyed by that store.
    rig=$(rig_name_for_bead "$bead")
    [ -n "$rig" ] && export GC_RIG="$rig"
    path=$(rig_path_for_bead "$bead")
    [ -n "$path" ] && [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"
    need_human_gate_jq

    ACCEPT_GC=$(command -v gc 2>/dev/null || true)
    case "$ACCEPT_GC" in
        */*) ;;
        *) echo "$PROG: accept: cannot name the gc program's path ('command -v gc' answered '${ACCEPT_GC}'), and a gc run under the acceptance lock must be a program for the lock's descriptor to close in it. Nothing dispatched." >&2
           exit 3 ;;
    esac
    lock_rc=0; accept_take_lock "$bead" || lock_rc=$?
    case "$lock_rc" in
        0) ;;
        1) echo "$PROG: accept: another Accept on $bead holds its acceptance lock ($ACCEPT_LOCK_NOTE), so this one refuses and writes nothing. Re-run once that one has finished." >&2
           exit 4 ;;
        *) echo "$PROG: accept: cannot take $bead's acceptance lock: $ACCEPT_LOCK_NOTE. Accept refuses without it, because two Accepts on one bead could each dispatch it. Nothing dispatched." >&2
           exit 3 ;;
    esac
    gc() { accept_gc "$@"; }

    # The live read of the three conditions, under the lock: a board row can be
    # stale and a command can be copied.
    verify_subject "$bead" accept "Nothing dispatched." || exit $?
    formula=$(printf '%s' "$VS_ROW" | jq -r '(.metadata // {})["gc.recommended_formula"] // "" | tostring' 2>/dev/null || true)
    dispatched=$(printf '%s' "$VS_ROW" | jq -r '(.metadata // {})["gc.recommended_formula_dispatched"] // "" | tostring' 2>/dev/null || true)
    if [ -z "$formula" ]; then
        if [ -n "$dispatched" ]; then
            echo "$PROG: accept: $bead carries no gc.recommended_formula: its recommendation was dispatched ($dispatched). Nothing to accept; nothing dispatched." >&2
        else
            echo "$PROG: accept: $bead carries no gc.recommended_formula — it is discuss-only. Engage it to decide. Nothing dispatched." >&2
        fi
        exit 2
    fi
    if ! gates=$(human_gate_rows "$bead"); then
        echo "$PROG: accept: could not read the human gates on $bead ('gc bd dep list $bead --type blocks' did not answer), so whether Accept may answer cannot be told. Nothing dispatched." >&2
        exit 4
    fi
    others=$(printf '%s' "$gates" | jq -r "$HUMAN_GATE_JQ"'
        [ .[] | select(open_human_gate("")) | select(((.await_id // "") | tostring) != "first-reaction")
              | "\(.id) (\(.title // "untitled"))" ] | join("; ")' 2>/dev/null || true)
    if [ -n "$others" ]; then
        echo "$PROG: accept: another human gate still blocks $bead: $others. Accept answers only the recommendation, and $bead's next step waits for every gate that blocks it, so Accept waits until those are cleared. Discuss it to answer them: $PROG engage $bead. Nothing dispatched." >&2
        exit 4
    fi
    rec_open=$(printf '%s' "$gates" | jq -r "$HUMAN_GATE_JQ"'[ .[] | select(open_human_gate("first-reaction")) | .id ] | join(" ")' 2>/dev/null || true)
    tok=""
    if [ -n "$rec_open" ]; then
        rec_assigned=$(printf '%s' "$gates" | jq -r "$HUMAN_GATE_JQ"'
            [ .[] | select(open_human_gate("first-reaction")) | select(((.assignee // "") | tostring) != "")
                  | "\(.id) (assigned to \(.assignee))" ] | join("; ")' 2>/dev/null || true)
        if [ -n "$rec_assigned" ]; then
            echo "$PROG: accept: the recommendation's gate $rec_assigned is that person's to clear, not Accept's. Nothing dispatched." >&2
            exit 4
        fi
        rec_gates="$rec_open"
    else
        # No open gate under the key: the newest gate under it is the
        # recommendation's, because no recommendation is older than the gate
        # that asks it. An Accept's answer there beside the recommendation is
        # an acceptance an earlier run did not finish.
        rec_newest=$(printf '%s' "$gates" | jq -c '
            [ .[] | select(((.await_id // "") | tostring) == "first-reaction") ]
            | sort_by(.created_at // "") | last // empty' 2>/dev/null || true)
        if [ -z "$rec_newest" ]; then
            echo "$PROG: accept: no human gate under the key first-reaction puts $bead's recommendation ($formula) to the operator, so nothing asks for an Accept. Discuss it to decide: $PROG engage $bead. Nothing dispatched." >&2
            exit 4
        fi
        rec_gates=$(printf '%s' "$rec_newest" | jq -r '.id // ""')
        rec_reason=$(printf '%s' "$rec_newest" | jq -r '.close_reason // "" | tostring')
        tok=$(printf '%s' "$rec_newest" | jq -r --arg f "$formula" '
            (.close_reason // "" | tostring)
            | capture("^ruled: accepted (?<f>[^ ]+) accept:(?<t>[0-9a-f]+)$")? // {}
            | select(.f == $f) | .t // empty' 2>/dev/null || true)
        if [ -z "$tok" ]; then
            echo "$PROG: accept: the recommendation's gate $rec_gates on $bead was answered: \"${rec_reason:-no reason}\". That answer stands, and nothing asks for an Accept. Discuss it to decide: $PROG engage $bead. Nothing dispatched." >&2
            exit 4
        fi
    fi
    # shellcheck disable=SC2086  # the gate ids are space-free words
    accept_warn_live "$bead" $rec_gates

    if [ -z "$tok" ]; then
        # Step 1: the operator's acceptance, which the resolve is. Its dispatch
        # input goes on the gate first, under the token the answer names, so
        # whichever run finishes the acceptance slings what was accepted.
        tok=$(accept_token)
        answer="ruled: accepted $formula accept:$tok"
        # shellcheck disable=SC2086  # the gate ids are space-free words
        if ! accept_record "$tok" "$formula" $rec_gates; then
            echo "$PROG: accept: could not record acceptance $tok's dispatch input ($(accept_vars_said "$accept_vars")) on $bead's recommendation gate ${ACCEPT_RECORD_LEFT:-$rec_gates}, so nothing is resolved or dispatched. Re-run once the store answers: $PROG accept $bead" >&2
            exit 4
        fi
        for g in $rec_gates; do
            gc bd gate resolve "$g" --reason "$answer" >/dev/null 2>&1 || true
        done
        # Step 2: go on only when the close reason is this run's own. bd
        # resolves a closed gate without changing it and reports success either
        # way, so only the read-back tells this answer from one that got there
        # first. A read that does not answer leaves the acceptance for the next
        # Accept to finish.
        if ! back=$(human_gate_rows "$bead"); then
            echo "$PROG: accept: resolved $bead's recommendation gate $rec_gates, but its answer could not be read back, so nothing is dispatched yet. The next Accept finishes this acceptance ($tok) once the store answers: $PROG accept $bead" >&2
            exit 4
        fi
        ours=""; theirs=""; unclosed=""
        for g in $rec_gates; do
            g_state=$(printf '%s' "$back" | jq -r --arg g "$g" --arg a "$answer" '
                [ .[] | select(.id == $g) ] | first // {}
                | if ((.status // "") | tostring) != "closed" then "open"
                  elif ((.close_reason // "") | tostring) == $a then "ours"
                  else "theirs\t" + ((.close_reason // "") | tostring) end' 2>/dev/null || printf 'open')
            case "$g_state" in
                ours) ours="${ours:+$ours }$g" ;;
                theirs"$TAB"*) theirs="${theirs:+$theirs; }$g: \"${g_state#theirs"$TAB"}\"" ;;
                *) unclosed="${unclosed:+$unclosed }$g" ;;
            esac
        done
        if [ -n "$theirs$unclosed" ]; then
            back_said=""
            if [ -n "$ours" ]; then
                # shellcheck disable=SC2086  # the gate ids are space-free words
                accept_reopen "Accept stood down: another answer reached the recommendation first" $ours || true
                # shellcheck disable=SC2086
                back_said=$(accept_reopen_said $ours)
            fi
            if [ -n "$theirs" ]; then
                echo "$PROG: accept: another answer reached $bead's recommendation gate first — $theirs. The first answer stands, so Accept dispatches nothing.$back_said" >&2
            else
                echo "$PROG: accept: the recommendation gate $unclosed on $bead did not close on its resolve, so Accept dispatches nothing. Re-run accept, or resolve it by hand.$back_said" >&2
            fi
            exit 4
        fi
    else
        # The finish of an acceptance an earlier Accept left unfinished. The
        # run that wrote the answer has stopped, since this one holds the lock,
        # so its root, live or finished, is found by the token.
        echo "$PROG: accept: $bead carries an acceptance an earlier Accept left unfinished ($tok); finishing it" >&2
        root_state=$(accept_token_root "$tok")
        case "$root_state" in
            found\ *)
                if ! accept_mark_dispatched "$bead" "$formula" "$tok"; then
                    echo "$PROG: accept: acceptance $tok already dispatched $formula at $bead (root ${root_state#found }), but the record did not stick (gc.recommended_formula still reads live). The next Accept finishes the record without a second dispatch: $PROG accept $bead" >&2
                    exit 4
                fi
                echo "$PROG: accept: acceptance $tok had already dispatched $formula at $bead (root ${root_state#found }); recorded it, slinging nothing${accept_vars:+. That root keeps the vars it was poured with, so the --var given here does not reach it}"
                bust_cache
                return 0 ;;
            unread)
                echo "$PROG: accept: could not search for a root of acceptance $tok on $bead, which proves nothing, so nothing is dispatched or written. Re-run once the store answers: $PROG accept $bead" >&2
                exit 4 ;;
        esac
        # No root carries the token, so this run slings, and it slings the
        # input the acceptance was made with, read off the gate, never this
        # run's own: the board's Accept passes no --var, and a retry's defaults
        # would undo a var the operator's ruling settled.
        if ! recorded_vars=$(accept_recorded_vars "$rec_newest" "$tok" "$formula"); then
            echo "$PROG: accept: the recommendation's gate $rec_gates on $bead records no dispatch input for acceptance $tok, so the vars it was accepted with cannot be told, and nothing is dispatched or written. Reopen the gate and Accept again: gc bd reopen $rec_gates && $PROG accept $bead" >&2
            exit 4
        fi
        if [ -n "$accept_vars" ] && [ "$accept_vars" != "$recorded_vars" ]; then
            echo "$PROG: accept: acceptance $tok on $bead was accepted with $(accept_vars_said "$recorded_vars"), and this run was given $(accept_vars_said "$accept_vars"). An acceptance dispatches the input it was accepted with, so nothing is dispatched or written. Finish it as accepted, with those vars or none: $PROG accept $bead. To dispatch other vars, reopen the gate first: gc bd reopen $rec_gates" >&2
            exit 4
        fi
        accept_vars="$recorded_vars"
        [ -z "$accept_vars" ] || echo "$PROG: accept: acceptance $tok slings the vars it was accepted with: $(accept_vars_said "$accept_vars")" >&2
    fi

    # Step 3: no open human gate blocks the bead. A gate filed between the live
    # read and the resolve shows here, and the recommendation goes back on the
    # board rather than starting the work ahead of that gate.
    if ! late_rows=$(human_gate_rows "$bead"); then
        echo "$PROG: accept: could not read back the human gates on $bead after its acceptance ($tok), so nothing is dispatched yet. The next Accept finishes it once the store answers: $PROG accept $bead" >&2
        exit 4
    fi
    late=$(printf '%s' "$late_rows" | jq -r "$HUMAN_GATE_JQ"'[ .[] | select(open_human_gate("")) | "\(.id) (\(.title // "untitled"))" ] | join("; ")' 2>/dev/null || true)
    if [ -n "$late" ]; then
        # shellcheck disable=SC2086  # the gate ids are space-free words
        accept_reopen "Accept stood down: another human gate blocks the bead" $rec_gates || true
        # shellcheck disable=SC2086
        echo "$PROG: accept: a human gate filed since Accept read $bead blocks it: $late. Nothing is dispatched ahead of it.$(accept_reopen_said $rec_gates) Discuss it: $PROG engage $bead" >&2
        exit 4
    fi

    # Step 3b: a bead a sitting held goes back to unanchored before the sling.
    # A sitting's hold moves an unanchored bead to `held` while the operator owes
    # the answer of a gate that blocks it (skills/converse-hold), and
    # mol-polecat-work's load-context reads any merge_result as a PR or merge
    # that already exists, so a run poured at a held bead cancels at its first
    # step while step 5 withdraws the recommendation. The acceptance is that
    # answer, and step 3 read back that no other open human gate blocks the
    # bead, so Accept releases it here, routed to human, as a sitting's
    # sign-off releases a subject that takes its recommendation. A release that
    # does not read back leaves the acceptance unfinished, for the next Accept
    # to finish.
    held_row=$(row_now "$bead")
    if [ -z "$held_row" ]; then
        echo "$PROG: accept: could not read $bead back after its acceptance ($tok) to tell whether it reads held, so nothing is dispatched yet. The next Accept finishes it once the store answers: $PROG accept $bead" >&2
        exit 4
    fi
    if [ "$(printf '%s' "$held_row" | jq -r '(.metadata // {}).merge_result // "" | tostring' 2>/dev/null)" = held ]; then
        lc_rc=0
        accept_lifecycle transition "$bead" --to unanchored --expect held --route human >/dev/null 2>&1 || lc_rc=$?
        released_row=$(row_now "$bead")
        if [ -z "$released_row" ] || [ "$(printf '%s' "$released_row" | jq -r '(.metadata // {}).merge_result // "" | tostring' 2>/dev/null)" = held ]; then
            echo "$PROG: accept: $bead reads held, as a sitting's hold on its gate left it, and its release to unanchored did not read back (lifecycle.sh exited $lc_rc), so nothing is dispatched: mol-polecat-work cancels a run poured at a held bead. The next Accept finishes acceptance $tok once the release can land: $PROG accept $bead" >&2
            exit 4
        fi
        echo "$PROG: accept: released $bead from held, which waited on this answer" >&2
    fi

    # Step 4: dispatch the recommendation AT the bead (--on), titled with the
    # token, so the root it pours names the acceptance that sent it. A graph.v2
    # formula reads the bead as its input convoy's one tracked member, so the
    # sling carries no var of its own, only each --var the caller gave.
    sling_rc=0
    accept_sling "$bead" "$formula" "$tok" || sling_rc=$?
    if [ "$sling_rc" -ne 0 ]; then
        # A sling can fail after its pour committed, and that pour runs, so the
        # token's root decides whether the dispatch landed.
        root_state=$(accept_token_root "$tok")
        case "$root_state" in
            found\ *)
                echo "$PROG: accept: 'gc sling ... --on $formula' exited $sling_rc for $bead, but root ${root_state#found } carries acceptance $tok, so the dispatch landed" >&2 ;;
            unread)
                echo "$PROG: accept: 'gc sling ... --on $formula' exited $sling_rc for $bead, and whether it poured could not be read, so nothing more is written. The next Accept finishes acceptance $tok once the store answers: $PROG accept $bead" >&2
                exit 4 ;;
            *)
                # shellcheck disable=SC2086  # the gate ids are space-free words
                accept_reopen "Accept's sling of $formula poured nothing, so the question stands" $rec_gates || true
                if [ "$sling_rc" -eq 3 ]; then
                    why="$formula already runs at $bead from another dispatch, which Gas City's launch lock refused to start twice"
                else
                    why="'gc sling ... --on $formula' failed and poured no root under acceptance $tok"
                fi
                # shellcheck disable=SC2086
                echo "$PROG: accept: $why. Nothing is dispatched.$(accept_reopen_said $rec_gates) Retry, or Discuss it: $PROG engage $bead" >&2
                exit 1 ;;
        esac
    fi

    # Step 5: record the dispatch, withdrawing the recommendation.
    if ! accept_mark_dispatched "$bead" "$formula" "$tok"; then
        echo "$PROG: accept: dispatched $formula at $bead (acceptance $tok), but the record did not stick (gc.recommended_formula still reads live). The next Accept finishes the record without a second dispatch: $PROG accept $bead" >&2
        exit 4
    fi
    bust_cache
    echo "$PROG: accept: dispatched $formula at $bead (acceptance $tok)"
}

# ── engage: decision helpers (UI-reusable) ──────────────────────────
# The five engage decisions — subject, conversation, starter, model, skill — resolved from
# durable state, factored out of the prompt loop so a later helm UI can drive
# the same logic. The prompt_* wrappers add the one terminal read; the
# list/find/seed helpers touch no terminal. Prompts print to the foreground
# (stdout) and read stdin; a closed input (EOF) returns non-zero, so a caller
# cancels rather than loops.

# engage_list_models — configured converse-<model> tokens, one per line, opus
# (the work tier) first. Enumerated from the agent dirs the templates live in,
# so the menu tracks what `gc session new converse-<model>` can resolve.
engage_list_models() {
    _elm_all=""
    for _elm_d in "$ENGAGE_AGENTS_DIR"/converse-*; do
        [ -d "$_elm_d" ] || continue
        _elm_m=$(basename "$_elm_d"); _elm_m=${_elm_m#converse-}
        [ -n "$_elm_m" ] || continue
        _elm_all="$_elm_all $_elm_m"
    done
    # Two passes so opus leads; `if` (not `&&`) keeps a false test from making the
    # final loop iteration — and so the function — return non-zero under set -e.
    for _elm_m in $_elm_all; do
        if [ "$_elm_m" = opus ]; then printf '%s\n' "$_elm_m"; fi
    done
    for _elm_m in $_elm_all; do
        if [ "$_elm_m" != opus ]; then printf '%s\n' "$_elm_m"; fi
    done
}

# engage_model_label <token> — the token with an initial capital, for the menu.
engage_model_label() {
    printf '%s%s' "$(printf '%s' "$1" | cut -c1 | tr '[:lower:]' '[:upper:]')" \
                  "$(printf '%s' "$1" | cut -c2-)"
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

# holding_gate_rows <bead> — the open human gates that hold the bead, nearest
# first, one "<id>\t<title>" row each: `gctk pr-status gates`, the reader the PR's
# held: gate label and the board's row read, so what engage offers cannot differ
# from what they say. Returns 1 when gctk is not there or did not answer, which
# says nothing about the gates.
holding_gate_rows() {
    _hgr_bin="${GCTK_BIN:-}"
    if [ -z "$_hgr_bin" ]; then
        _hgr_root=$(city_root)
        [ -n "$_hgr_root" ] || return 1
        _hgr_bin="$_hgr_root/.gc/services/gctk/bin/gctk"
    fi
    [ -x "$_hgr_bin" ] || return 1
    _hgr_json=$("$_hgr_bin" pr-status gates --anchor "$1" 2>/dev/null) || return 1
    printf '%s' "$_hgr_json" | jq -r '.[] | [.id, (.title // "")] | @tsv' 2>/dev/null
}

# engage_warn_gates_unread <bead> — say that the gates holding the bead did not
# read, which leaves the operator to look for them. Engage goes on: a sitting on
# the bead can still be started.
engage_warn_gates_unread() {
    echo "$PROG: engage: could not read the human gates that hold $1 ('gctk pr-status gates' did not answer), so none are offered." >&2
}

# engage_say_holding_gates <bead> — name each open human gate that holds the bead,
# and how to engage it, for an engage that asks nothing. A sitting on the bead does
# not answer them unless its conversation replies to them.
engage_say_holding_gates() {
    if ! _esh_rows=$(holding_gate_rows "$1"); then
        engage_warn_gates_unread "$1"
        return 0
    fi
    printf '%s\n' "$_esh_rows" | while IFS= read -r _esh_row; do
        [ -n "$_esh_row" ] || continue
        _esh_id=$(printf '%s' "$_esh_row" | cut -f1)
        echo "$PROG: engage: $1 is held by human gate $_esh_id (\"$(printf '%s' "$_esh_row" | cut -f2-)\"). To answer it: $PROG engage $_esh_id" >&2
    done
}

# engage_take <id> [<from>] — settle what the engage is about from a bead, a
# conversation or a gate: sets bead and bead_row to the bead its conversation
# tracks, pointed_gate to a gate the id named, which the conversation replies to,
# and named_conv to a conversation it named. <from> is the bead a gate was picked
# from (take_bead). A refusal exits.
engage_take() {
    bead="$1"
    verify_subject "$bead" engage "Nothing spawned." || exit $?
    take_bead engage "Nothing spawned." "${2:-}"
    pointed_gate="$TAKE_GATE"; named_conv="$TAKE_CONV"
    if [ "$TAKE_BEAD" != "$bead" ]; then
        if [ -n "$named_conv" ]; then
            echo "$PROG: engage: $bead is a conversation on $TAKE_BEAD" >&2
        else
            echo "$PROG: engage: $bead is a gate about $TAKE_BEAD, the one bead still waiting on it — engaging $TAKE_BEAD, and the conversation replies to the gate" >&2
        fi
        bead="$TAKE_BEAD"
        verify_subject "$bead" engage "Nothing spawned." || exit $?
    fi
    bead_row="$VS_ROW"
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
# answer or answered malformed). Memoized per rig and model: the skill prompt
# lists the roster, then resolves a typed name against it.
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

# engage_search_subjects <query> — open beads whose title contains the query,
# leaving out conversations, one "<id>\t<title>" row each. The subject
# prompt's title search, split out so a UI can populate its own picker from the
# same rows.
engage_search_subjects() {
    gc bd list --status=open,in_progress --title-contains "$1" --json --limit=0 2>/dev/null | scrub \
        | jq -r "$CONVERSATION_JQ"'.[]? | objects | select(conversation | not) | [.id, (.title // "")] | @tsv' 2>/dev/null || true
}

# engage_prompt_subject — a typed id, PR number, or URL is taken as-is
# (downstream verification fails closed on a bogus one); anything else is a
# title search offering numbered matches. Sets ENGAGE_SUBJECT.
engage_prompt_subject() {
    while :; do
        printf '  Subject? (id or search) › '
        IFS= read -r _eps_in || return 1
        _eps_in=${_eps_in# }; _eps_in=${_eps_in% }
        [ -n "$_eps_in" ] || { printf '  enter a bead id, PR number/URL, or search text\n'; continue; }
        case "$_eps_in" in
            *-*|[0-9]*|http://*|https://*) ENGAGE_SUBJECT="$_eps_in"; return 0 ;;
        esac
        _eps_rows=$(engage_search_subjects "$_eps_in")
        if [ -z "$_eps_rows" ]; then
            printf '  no open bead matches "%s" — try an id or different text\n' "$_eps_in"
            continue
        fi
        _eps_i=0; _eps_map=""
        while IFS="$TAB" read -r _eps_id _eps_title; do
            [ -n "$_eps_id" ] || continue
            _eps_i=$((_eps_i + 1))
            [ "$_eps_i" -gt 9 ] && { printf '    … more matches; narrow the search\n'; break; }
            printf '    [%s] %s — %s\n' "$_eps_i" "$_eps_id" "$_eps_title"
            _eps_map="$_eps_map$_eps_i $_eps_id
"
        done <<EOF
$_eps_rows
EOF
        printf '  Which? [1-%s], or type to search again › ' "$_eps_i"
        IFS= read -r _eps_pick || return 1
        case "$_eps_pick" in
            ""|*[!0-9]*) continue ;;
        esac
        _eps_sel=$(printf '%s' "$_eps_map" | awk -v n="$_eps_pick" '$1==n{print $2}')
        [ -n "$_eps_sel" ] && { ENGAGE_SUBJECT="$_eps_sel"; return 0; }
    done
}

# engage_prompt_conversation_or_starter <subject> — ONE prompt covering the
# choice of a conversation the subject already has, of a human gate that holds
# it, and the starter of a new conversation. The subject's open conversations are
# listed numbered with their state, and the gates follow on the same numbers,
# unless the engage was pointed at a gate already; the starter seeds follow, each
# keyed by its letter. The single reply resolves as: a number takes that
# conversation (a live sitting is attached to, any other is held in a fresh
# sitting) or engages that gate; a seed letter opens a new conversation on that
# seed; any other text opens a new conversation with that text as its opener;
# Enter takes the default, which attaches to a live sitting, takes a conversation
# from the queue, or files one. Numbers and letters never collide, so both live
# in one prompt. Sets ENGAGE_CONV_CHOICE to a conversation id, "new", or "" for
# the default, and ENGAGE_GATE_CHOICE to a gate picked; on "new" it also sets
# ENGAGE_STARTER_BODY (the conversation's ask; empty = blank) and
# ENGAGE_STARTER_TAIL (a short title).
engage_prompt_conversation_or_starter() {
    ENGAGE_STARTER_BODY=""; ENGAGE_STARTER_TAIL=""; ENGAGE_CONV_CHOICE=""; ENGAGE_GATE_CHOICE=""
    _epv_i=0; _epv_map=""; _epv_gmap=""; _epv_convs=0
    _epv_rows=$(engage_find_conversations "$1" || true)
    if [ -n "$_epv_rows" ]; then
        printf '  Subject has open conversation(s):\n'
        # Read whole lines and cut the columns: an empty field collapses under
        # a whitespace IFS in `read`, so split with cut, which keeps it.
        while IFS= read -r _epv_row; do
            [ -n "$_epv_row" ] || continue
            _epv_id=$(printf '%s' "$_epv_row" | cut -f1)
            _epv_st=$(printf '%s' "$_epv_row" | cut -f2)
            _epv_title=$(printf '%s' "$_epv_row" | cut -f5-)
            [ -n "$_epv_id" ] || continue
            case "$_epv_st" in
                live)  _epv_lbl="in session — attaches" ;;
                queue) _epv_lbl="in your queue" ;;
                *)     _epv_lbl="its sitting ended — resumes it" ;;
            esac
            _epv_i=$((_epv_i + 1))
            printf '    [%s] %s — "%s"  (%s)\n' "$_epv_i" "$_epv_id" "$_epv_title" "$_epv_lbl"
            _epv_map="$_epv_map$_epv_i $_epv_id
"
        done <<EOR
$_epv_rows
EOR
        _epv_convs="$_epv_i"
    fi
    if [ -z "$pointed_gate" ]; then
        if _epv_rows=$(holding_gate_rows "$1"); then
            [ -z "$_epv_rows" ] || printf '  Held by human gate(s):\n'
            while IFS= read -r _epv_row; do
                [ -n "$_epv_row" ] || continue
                _epv_id=$(printf '%s' "$_epv_row" | cut -f1)
                _epv_i=$((_epv_i + 1))
                printf '    [%s] %s — "%s"  (takes the bead waiting on it, and answers the gate)\n' \
                    "$_epv_i" "$_epv_id" "$(printf '%s' "$_epv_row" | cut -f2-)"
                _epv_gmap="$_epv_gmap$_epv_i $_epv_id
"
            done <<EOR
$_epv_rows
EOR
        else
            engage_warn_gates_unread "$1"
        fi
    fi
    # The new-conversation starters, keyed by letter; a menu and a letter->key map.
    _epv_smenu=""; _epv_smap=""
    while IFS="$TAB" read -r _eps_key _eps_label _eps_letter; do
        [ -n "$_eps_key" ] && [ -n "$_eps_letter" ] || continue
        [ -n "$_epv_smenu" ] && _epv_smenu="$_epv_smenu · "
        _epv_smenu="${_epv_smenu}[$_eps_letter] $_eps_label"
        _epv_smap="$_epv_smap$_eps_letter $_eps_key
"
    done <<EOR
$(engage_starter_list)
EOR
    [ -n "$_epv_smenu" ] && printf '    new:  %s · or type your own opener\n' "$_epv_smenu"
    if [ "$_epv_i" -eq 0 ]; then
        printf '  a letter or text starts a new conversation · Enter = a new one, blank › '
    elif [ "$_epv_convs" -eq 0 ]; then
        printf '  [1-%s] engage a listed gate · a letter or text starts a new conversation · Enter = a new one, blank › ' "$_epv_i"
    elif [ -n "$_epv_gmap" ]; then
        printf '  [1-%s] take a listed conversation or gate · a letter or text starts a new one · Enter = the first conversation › ' "$_epv_i"
    else
        printf '  [1-%s] take a listed conversation · a letter or text starts a new one · Enter = the first listed › ' "$_epv_i"
    fi
    IFS= read -r _epv_reply || return 1
    # Enter → the default: the first listed conversation, or a new blank one.
    [ -n "$_epv_reply" ] || return 0
    # A seed letter (case-insensitive) → a new conversation on that seed.
    _epv_lc=$(printf '%s' "$_epv_reply" | tr 'A-Z' 'a-z')
    _epv_seed=$(printf '%s' "$_epv_smap" | awk -v l="$_epv_lc" '$1==l{print $2}')
    if [ -n "$_epv_seed" ]; then
        ENGAGE_CONV_CHOICE="new"
        ENGAGE_STARTER_BODY=$(engage_starter_seed "$_epv_seed" "$1")
        ENGAGE_STARTER_TAIL=$(engage_starter_list | awk -F"$TAB" -v k="$_epv_seed" '$1==k{print $2}')
        return 0
    fi
    # A number naming a listed conversation → take it; one naming a gate → engage it.
    case "$_epv_reply" in
        *[!0-9]*) : ;;
        *)
            _epv_sel=$(printf '%s' "$_epv_map" | awk -v n="$_epv_reply" '$1==n{print $2}')
            if [ -n "$_epv_sel" ]; then ENGAGE_CONV_CHOICE="$_epv_sel"; return 0; fi
            _epv_sel=$(printf '%s' "$_epv_gmap" | awk -v n="$_epv_reply" '$1==n{print $2}')
            if [ -n "$_epv_sel" ]; then ENGAGE_GATE_CHOICE="$_epv_sel"; return 0; fi ;;
    esac
    # Anything else → a new conversation with the reply verbatim as its opener.
    ENGAGE_CONV_CHOICE="new"
    ENGAGE_STARTER_BODY="$_epv_reply"
    ENGAGE_STARTER_TAIL=$(printf '%s' "$_epv_reply" | cut -c1-60)
    return 0
}

# engage_prompt_model — numbered selection over the configured variants; Enter
# keeps opus (the work tier). Sets ENGAGE_MODEL.
engage_prompt_model() {
    _epm_i=0; _epm_map=""; _epm_menu=""
    for _epm_m in $(engage_list_models); do
        _epm_i=$((_epm_i + 1))
        _epm_lbl=$(engage_model_label "$_epm_m")
        [ "$_epm_m" = opus ] && _epm_lbl="$_epm_lbl (default)"
        [ -n "$_epm_menu" ] && _epm_menu="$_epm_menu · "
        _epm_menu="${_epm_menu}[$_epm_i] $_epm_lbl"
        _epm_map="$_epm_map$_epm_i $_epm_m
"
    done
    if [ "$_epm_i" -eq 0 ]; then ENGAGE_MODEL=opus; return 0; fi
    printf '  Model — %s   (Enter = Opus) › ' "$_epm_menu"
    IFS= read -r _epm_reply || return 1
    case "$_epm_reply" in
        "") ENGAGE_MODEL=opus; return 0 ;;
        *[!0-9]*) printf '  (not a listed number; keeping Opus)\n'; ENGAGE_MODEL=opus; return 0 ;;
    esac
    _epm_pick=$(printf '%s' "$_epm_map" | awk -v n="$_epm_reply" '$1==n{print $2}')
    if [ -n "$_epm_pick" ]; then ENGAGE_MODEL="$_epm_pick"; else printf '  (no such choice; keeping Opus)\n'; ENGAGE_MODEL=opus; fi
    return 0
}

# engage_prompt_skill <rig> <model> — the optional skill a NEW conversation seeds its
# sitting with as a lens on the subject. Enter is none. A name resolves as
# engage_resolve_skill does, ? lists the roster numbered, and a number picks from
# that list. A name that does not resolve is asked again rather than refused.
# Sets ENGAGE_SKILL (the full name, or empty for none).
engage_prompt_skill() {
    ENGAGE_SKILL=""
    while :; do
        printf '  Skill — Enter = none · a skill name, e.g. review-arch · ? lists them › '
        IFS= read -r _epk_in || return 1
        _epk_in=$(printf '%s' "$_epk_in" | sed 's/^ *//; s/ *$//')
        case "$_epk_in" in
            "") return 0 ;;
            "?")
                engage_skill_roster "$1" "$2"
                if [ -n "$ENGAGE_SKILL_ROSTER" ]; then
                    printf '%s\n' "$ENGAGE_SKILL_ROSTER" | awk '{ printf "    [%d] %s\n", NR, $0 }'
                elif [ "$ENGAGE_SKILL_ROSTER_OK" = 1 ]; then
                    printf '    (this sitting carries no skills)\n'
                else
                    printf '    (no skill list could be read for this sitting; a typed name is seeded unverified)\n'
                fi
                continue ;;
            *[!0-9]*) ;;
            *)
                engage_skill_roster "$1" "$2"
                _epk_pick=$(printf '%s\n' "$ENGAGE_SKILL_ROSTER" | awk -v n="$_epk_in" 'NR == n')
                if [ -n "$_epk_pick" ]; then ENGAGE_SKILL="$_epk_pick"; return 0; fi
                printf '  (no skill numbered %s; ? lists them)\n' "$_epk_in"
                continue ;;
        esac
        case "$_epk_in" in
            *[!A-Za-z0-9._-]*) printf '  (a skill name is letters, digits, dots and hyphens; ? lists them)\n'; continue ;;
        esac
        engage_resolve_skill "$1" "$2" "$_epk_in"
        case "$ENGAGE_SKILL_STATE" in
            ok|unread) ENGAGE_SKILL="$ENGAGE_SKILL_NAME"; return 0 ;;
            ambiguous) printf '  "%s" matches %s; type one in full\n' "$_epk_in" "$ENGAGE_SKILL_MATCHES" ;;
            *) printf '  no skill "%s" on this sitting; ? lists them\n' "$_epk_in" ;;
        esac
    done
}

# engage_prompt_rig — numbered selection over the rigs that carry a converse
# template (only those can host a sitting). A single such rig is auto-selected;
# none is an error. Sets ENGAGE_RIG.
engage_prompt_rig() {
    enumerate_rigs
    _epr_i=0; _epr_map=""; _epr_menu=""
    while IFS="$TAB" read -r _epr_name _epr_path; do
        [ -n "$_epr_name" ] || continue
        rig_carries_converse "$_epr_name" || continue
        _epr_i=$((_epr_i + 1))
        _epr_map="$_epr_map$_epr_i $_epr_name
"
        [ -n "$_epr_menu" ] && _epr_menu="$_epr_menu · "
        _epr_menu="${_epr_menu}[$_epr_i] $_epr_name"
    done <<EOF
$(printf '%s' "$RIGS" | jq -r '.[] | [.name, .path] | @tsv' 2>/dev/null)
EOF
    if [ "$_epr_i" -eq 0 ]; then
        echo "$PROG: engage: no rig in this city carries a converse template, so there is nowhere to host a new-subject sitting." >&2
        return 1
    fi
    if [ "$_epr_i" -eq 1 ]; then
        ENGAGE_RIG=$(printf '%s' "$_epr_map" | awk 'NR==1{print $2}')
        printf '  Rig: %s (the only converse-capable rig)\n' "$ENGAGE_RIG"
        return 0
    fi
    printf '  Rig — %s › ' "$_epr_menu"
    IFS= read -r _epr_reply || return 1
    case "$_epr_reply" in
        ""|*[!0-9]*) printf '  (not a listed number)\n'; return 1 ;;
    esac
    ENGAGE_RIG=$(printf '%s' "$_epr_map" | awk -v n="$_epr_reply" '$1==n{print $2}')
    [ -n "$ENGAGE_RIG" ] || { printf '  (no such choice)\n'; return 1; }
    return 0
}

# engage_create_subject — the --new-subject pre-step. Resolve the target rig,
# obtain the subject title, and create a fresh operator-origin subject bead in
# that rig's store. Mutates the caller's engage state the way the engage_prompt_*
# helpers set ENGAGE_*: on return $bead is the new id and the opener is primed
# (engage_reason/engage_file_new), so the rest of cmd_engage runs unchanged.
# Reads new_subject_title, engage_rig, engage_interactive, engage_reason*,
# engage_template.
#
# The subject is created MARKED gc.reaction_owned=1 — a live owner (this engage)
# already owns reacting to it — so the async first-reaction / proactive worker
# stands down rather than file a SECOND conversation (engage files the one
# conversation itself, below): tools/gc-proactive.sh drops a marked bead from its scan and refuses to
# file a reaction for one, and a reaction that reaches one anyway closes without
# acting (agents/proactive/prompt.template.md). The marker is set in the
# `gc bd create` write itself (--metadata), so the scan can never observe the
# bead unmarked.
# gc.origin=operator is the honest origin; the subject still gets its one
# operator-filed conversation.
engage_create_subject() {
    enumerate_rigs
    # 1. Resolve the rig: a --rig value, else an interactive prompt, else refuse.
    if [ -z "$engage_rig" ]; then
        if [ "$engage_interactive" = 1 ]; then
            engage_prompt_rig || { echo "$PROG: engage: no rig chosen — nothing created" >&2; exit 2; }
            engage_rig="$ENGAGE_RIG"
        else
            echo "$PROG: engage: --new-subject needs a rig to create the subject in; pass --rig <name> (one-shot) or run interactively." >&2
            exit 2
        fi
    fi
    _ecs_path=$(printf '%s' "$RIGS" | jq -r --arg n "$engage_rig" '.[] | select(.name==$n) | .path' 2>/dev/null | head -n1)
    if [ -z "$_ecs_path" ]; then
        echo "$PROG: engage: --rig '$engage_rig' matches no rig in 'gc rig list' (known: $(printf '%s' "$RIGS" | jq -r '[.[].name] | join(", ")' 2>/dev/null)). Nothing created." >&2
        exit 4
    fi
    if ! rig_carries_converse "$engage_rig"; then
        echo "$PROG: engage: rig '$engage_rig' ($_ecs_path) carries no converse template, so it can host no converse sitting. Pick a converse-capable rig. Nothing created." >&2
        exit 4
    fi
    if [ ! -d "$_ecs_path/.beads" ]; then
        echo "$PROG: engage: rig '$engage_rig' has no .beads ledger at $_ecs_path/.beads — nothing created." >&2
        exit 4
    fi
    # 2. The subject title: the positional/pre-filled text, else an interactive
    #    prompt. It is the new bead's title and, absent a starter, the opener.
    if [ -z "$new_subject_title" ] && [ "$engage_interactive" = 1 ]; then
        printf '  New subject — what is it about? › '
        IFS= read -r new_subject_title || { echo "$PROG: engage: no subject text — nothing created" >&2; exit 2; }
    fi
    new_subject_title=$(printf '%s' "$new_subject_title" | sed 's/^ *//; s/ *$//')
    [ -n "$new_subject_title" ] || { echo "$PROG: engage: --new-subject needs a subject (the new bead's title / what it is about). Nothing created." >&2; exit 2; }
    # 3. The opener: an explicit --reason/--template wins; otherwise the title
    #    doubles as it. A new subject always files a fresh conversation
    #    (engage_file_new), so the opener is settled here — mark the starter
    #    pre-filled so the interactive conversation/starter prompt (which lists a
    #    subject's EXISTING conversations) is skipped; a brand-new subject has none.
    if [ -z "$engage_template" ] && [ "$engage_reason_set" = 0 ]; then
        engage_reason="$new_subject_title"; engage_reason_set=1
    fi
    engage_file_new=1; starter_prefilled=1
    # 4. Create the subject ATOMICALLY with its markers (see the header note).
    _ecs_body="Operator-initiated conversation subject (gc-helm engage --new-subject): ${engage_reason:-$new_subject_title}"
    _ecs_json=$(gc bd create -t task --title "$new_subject_title" -d "$_ecs_body" \
        --metadata '{"gc.origin":"operator","gc.reaction_owned":"1"}' \
        --db "$_ecs_path/.beads" --json 2>/dev/null || true)
    bead=$(printf '%s' "$_ecs_json" | scrub | jq -r 'if type=="array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null || true)
    if [ -z "$bead" ] || [ "$bead" = "null" ]; then
        _ecs_err=$(printf '%s' "$_ecs_json" | scrub | jq -r 'if type=="object" then (.error // empty) else empty end' 2>/dev/null || true)
        echo "$PROG: engage: could not create the subject bead in rig '$engage_rig'${_ecs_err:+: $_ecs_err}. Nothing spawned." >&2
        exit 4
    fi
    # Arm the abort backstop the instant the marked subject exists. Every gate
    # from here to the conversation-filing in cmd_engage can still abort (a
    # suspended rig, a downed controller, an unknown --template or --model, a
    # store read that will not confirm the bead), and until the conversation is
    # filed an abort would leave this operator-origin subject owing a
    # conversation that nothing supplies: its own stand-down marker hides it
    # from the async worker (gc-proactive drops a marked bead, and a reaction
    # that reaches one stands down), and even unmarked a first reaction does
    # not file one for gc.origin=operator (actionable/blocked/close file none).
    # So engage_new_subject_cleanup files that one conversation itself on exit;
    # cmd_engage disarms it once the conversation is filed. enumerate_rigs (called at the top of
    # this function) already set and cleared its own trap and memoizes on every
    # later call, so it never clobbers this one.
    _ens_cleanup_bead="$bead"
    trap 'engage_new_subject_cleanup' EXIT
    trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
    echo "$PROG: engage: filed subject $bead in rig '$engage_rig' — \"$new_subject_title\"" >&2
}

# engage_new_subject_cleanup — the abort backstop for --new-subject, armed by
# engage_create_subject the instant the marked subject exists and disarmed by
# cmd_engage once the conversation is filed. While armed, any exit (an abort
# gate or a signal) means the live engage stopped before cmd_engage filed the
# subject's one conversation. The subject still owes it and the async worker
# will not supply it — the stand-down marker hides it from the scan, and even
# unmarked a first reaction files none for an operator-origin bead. So file the
# one conversation here with cmd_open, the same path the happy flow uses: it
# resolves the subject's rig from its id, joins a conversation already in the
# queue, and files the conversation in the operator's queue. The marker is LEFT
# set, exactly as a successful engage leaves it, so the async worker still
# stands down rather than filing a second. Run cmd_open in a subshell so its
# own exits cannot abort this trap, and disarm first so it cannot re-enter. A no-op
# when nothing is armed; it preserves the process's exit code.
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
        echo "$PROG: engage: new subject $_enc_bead was created but its conversation could NOT be filed (store error?); it still carries the gc.reaction_owned marker. File the conversation by hand: $PROG open $_enc_bead" >&2
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
# A concern the operator brings (--reason, --template, --skill, or a new
# conversation picked at the prompt) is a distinct dialogue, so it files a
# fresh conversation even when the bead has one. A sitting is a manual
# converse-<model> session named for its conversation (origin=manual, which the
# pool execution backstop never governs). The session is spawned before the
# bind, because its alias is the reservation: only one session that is not
# closed can hold the alias. Then the conversation is bound to the session's
# alias with a write guarded on the holder engage read, so of two engages only
# one bind lands, and the session's own `gc hook --claim` adopts it. dismiss
# ends the sitting.
#
# The argument is the bead the operator picked off the board. A conversation id
# names its own conversation. A gate names the one bead still waiting on it, and
# the conversation engage lands on replies to the gate (bd's replies-to edge),
# read back before any sitting starts, so the sitting finds the gate among its
# conversation's replies. Engage warns when it starts a sitting while another
# live sitting tracks the bead or replies to a gate the bead waits on: one
# sitting per bead is engage's default, not a guarantee.
#
# --model selects the tier (opus default, else fable or codex). --skill seeds
# the sitting with a skill as its lens on the subject, any skill the sitting
# carries. The lens brief is the new conversation's ask, which a sitting on any
# model reads when it claims the conversation, so the skill rides it across a
# restart with no per-skill template. --no-attach spawns and binds without
# attaching — the board picker uses it, then the operator attaches from the
# session picker. Attached (the default), the operator lands in the sitting
# directly.
cmd_engage() {
    bead=""; engage_model="opus"; engage_reason=""; engage_attach=1
    engage_no_input=0; engage_model_set=0; engage_reason_set=0; engage_template=""
    engage_skill=""; engage_skill_set=0
    # Interactive decisions carried into the conversation choice and output below.
    engage_body=""; engage_file_new=0; engage_chosen_conv=""; conv_new=0
    # --new-subject files a FRESH subject bead, then engages it (rig-aware, since
    # there is no id prefix yet to derive the rig from). --rig names that rig;
    # --subject names an EXISTING one, so the two are mutually exclusive.
    engage_new_subject=0; engage_rig=""; engage_subject_flag=0
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

    # Interactive is the DEFAULT on a TTY; --no-input reverts to the flag-driven,
    # one-shot behavior for scripts/CI. GC_HELM_ASSUME_TTY is a test seam that
    # forces the interactive path when stdin is a pipe, as in a hermetic test.
    engage_interactive=0
    if [ "$engage_no_input" = 0 ] && { [ -t 0 ] || [ -n "${GC_HELM_ASSUME_TTY:-}" ]; }; then
        engage_interactive=1
    fi
    # A pre-filled --reason/--template already commits to a new conversation
    # with that opener, and --skill to a new conversation carrying its lens
    # brief, so the interactive conversation/starter prompt is skipped for any
    # of them.
    starter_prefilled=0
    if [ "$engage_reason_set" = 1 ] || [ -n "$engage_template" ] || [ -n "$engage_skill" ]; then starter_prefilled=1; fi

    # --rig names the rig a NEW subject is created in; an existing subject's rig
    # comes from its id prefix, so --rig is meaningless there. Refuse rather than
    # silently ignore it.
    if [ -n "$engage_rig" ] && [ "$engage_new_subject" = 0 ]; then
        echo "$PROG: engage: --rig applies only with --new-subject; an existing subject's rig is derived from its id. Drop --rig, or add --new-subject to create one." >&2
        exit 2
    fi

    # --new-subject: file a FRESH subject bead in a chosen rig, then engage it in
    # one gesture. The positional argument is the subject TEXT (the new bead's
    # title), not an id; --subject names an EXISTING bead, so the two conflict.
    # engage_create_subject resolves the rig, obtains the title, creates the
    # marked bead, and leaves its id in $bead with the opener primed — after it
    # the rest of this verb runs unchanged, deriving the rig from the new id's
    # prefix and filing the ONE conversation the marker keeps the async worker
    # from duplicating.
    if [ "$engage_new_subject" = 1 ]; then
        if [ "$engage_subject_flag" = 1 ]; then
            echo "$PROG: engage: --subject names an existing bead and --new-subject creates one — pass only one." >&2
            exit 2
        fi
        new_subject_title="$bead"; bead=""
        engage_create_subject
    fi

    # Subject: prompt when absent on a TTY; a flag or positional pre-fills it.
    if [ -z "$bead" ]; then
        if [ "$engage_interactive" = 1 ]; then
            engage_prompt_subject || { echo "$PROG: engage: no subject given — nothing engaged" >&2; exit 2; }
            bead="$ENGAGE_SUBJECT"
        else
            echo "$PROG: engage needs <bead-id> (a bead to converse about, a conversation, or a human gate)" >&2; usage; exit 2
        fi
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
    # A rig that carries no converse template can host no converse sitting, so an
    # engage there can only half-act: file a conversation and export GC_RIG, then
    # fail at the spawn. An HQ / city-store bead resolves to the city root, which
    # carries none. Refuse up front, before any conversation is filed or
    # GC_RIG/BEADS_DIR is exported, so the engage is a clean no-op.
    if ! rig_carries_converse "$rig"; then
        echo "$PROG: engage: converse is not available for '$bead': its rig '${rig:-?}' ($path) carries no converse template. HQ/city-store beads are not converse-engageable. Nothing filed, nothing spawned." >&2
        exit 4
    fi
    [ -d "$path/.beads" ] && export BEADS_DIR="$path/.beads"
    [ -n "$rig" ] && export GC_RIG="$rig"

    # A spawned converse sitting is launched and sustained by the RECONCILER, the
    # city controller's loop — a converse slot sets nudge="" and idle_timeout=0,
    # so no pool backstop cycles it. The reconciler skips a suspended rig's
    # agents and does not run while the controller is down, so on either the
    # sitting never comes up: engage would report success while the conversation
    # sits bound to a session that never registers. Refuse before spawning and
    # name the fix. A rig with no agents running is idle, not down, and the
    # reconciler launches the sitting there like anywhere else. Both flags come
    # from the `gc rig list` enumerate_rigs already read, and
    # city_controller_state asks gc status before an HQ running=false counts
    # (city-liveness.sh). A gc that reports neither flag leaves them empty, which
    # reads as unknown and does not refuse.
    if [ "$(rig_suspended "$rig")" = "true" ]; then
        echo "$PROG: engage: rig '${rig:-?}' is suspended, so the reconciler skips its agents and a spawned converse sitting would never come up. Resume the rig, then re-engage: gc rig resume ${rig:-<rig>}" >&2
        exit 4
    fi
    city_controller_state
    if [ "$CONTROLLER_RUNNING" = "false" ]; then
        echo "$PROG: engage: the city controller did not answer ($CONTROLLER_SEEN), so nothing would launch a spawned converse sitting. Check 'gc status' and 'gc supervisor status', then re-engage once the controller answers." >&2
        exit 4
    fi

    # The bead must resolve before anything spawns — the shared resolve+classify,
    # so an unanswered read fails closed as a data-plane outage, not a missing
    # bead, the way open does. A gate names the one bead still waiting on it, and
    # a conversation id names its own conversation and the bead it tracks.
    engage_take "$bead"

    # --skill and --reason write a NEW conversation's ask, which is written once,
    # at filing. An explicit conversation id names a conversation whose ask
    # already exists, so neither has anywhere to go; refuse before any prompt,
    # and point at the subject form that files a conversation carrying them.
    if [ -n "$named_conv" ] && [ -n "$engage_skill" ]; then
        echo "$PROG: engage: --skill seeds a NEW conversation's ask, which needs a subject — but '$named_conv' is an explicit conversation id, and its ask is already written. Engage its subject with --skill instead: $PROG engage $bead --skill $engage_skill. Nothing spawned." >&2
        exit 2
    fi
    if [ -n "$named_conv" ] && [ -n "$engage_reason$engage_template" ]; then
        echo "$PROG: engage: --reason or --template files a NEW conversation, which needs a subject — but '$named_conv' is an explicit conversation id. Engage the subject with --reason to open a fresh conversation, or drop it to engage this conversation as-is. Nothing spawned." >&2
        exit 2
    fi

    # Ground the operator in the bead they picked, before the conversation or
    # model prompt: a typed id, PR number, or URL carries nothing of the bead on
    # its own, and a title search drops all but the title once a match is
    # chosen. Interactive only — a --no-input caller named the subject on argv
    # and its stdout is a script's to parse.
    if [ "$engage_interactive" = 1 ]; then
        subject_summary=$(printf '%s' "$bead_row" | jq -r '
            (.title // "") as $t
            | ($t | if length > 72 then .[0:71] + "…" else . end) as $tt
            | "  Subject: " + (.id // "?")
              + " (" + (.issue_type // "?") + " · " + (.status // "?")
              + " · p" + ((.priority // 0) | tostring) + ")"
              + (if $tt == "" then "" else " — \"" + $tt + "\"" end)' 2>/dev/null || true)
        [ -n "$subject_summary" ] && printf '%s\n' "$subject_summary"
        if [ -n "$pointed_gate" ]; then
            gate_title=$(row_now "$pointed_gate" | jq -r '(.title // "") | if length > 96 then .[0:95] + "…" else . end' 2>/dev/null || true)
            printf '  Gate:    %s — "%s"\n' "$pointed_gate" "${gate_title:-untitled}"
        fi
        if [ -n "$named_conv" ]; then
            conv_title=$(row_now "$named_conv" | jq -r '(.title // "") | if length > 96 then .[0:95] + "…" else . end' 2>/dev/null || true)
            printf '  Conversation: %s — "%s"\n' "$named_conv" "${conv_title:-untitled}"
        fi
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

    # Interactive decision for a SUBJECT, in one prompt: take one of its
    # conversations, engage a gate that holds it, or open a new one (blank, on a
    # seed, or with a typed opener). An explicit conversation id names its own
    # conversation, and a pre-filled --reason/--template already chose a new one.
    # An engage that asks nothing names the gates instead, unless it was pointed
    # at a conversation or a gate.
    if [ "$engage_interactive" = 1 ] && [ -z "$named_conv" ] && [ "$starter_prefilled" = 0 ]; then
        engage_prompt_conversation_or_starter "$bead" || { echo "$PROG: engage: no input — nothing engaged" >&2; exit 2; }
        case "$ENGAGE_CONV_CHOICE" in
            new) engage_file_new=1
                 engage_reason="$ENGAGE_STARTER_TAIL"
                 engage_body="$ENGAGE_STARTER_BODY" ;;
            "")  ;;
            *)   engage_chosen_conv="$ENGAGE_CONV_CHOICE" ;;
        esac
        [ -z "$ENGAGE_GATE_CHOICE" ] || engage_take "$ENGAGE_GATE_CHOICE" "$bead"
    elif [ -z "$named_conv" ] && [ -z "$pointed_gate" ]; then
        engage_say_holding_gates "$bead"
    fi

    # Model: prompt when interactive and unset, else the opus default (or the
    # flag). Validated against the configured variants before the template binds.
    if [ "$engage_model_set" = 0 ] && [ "$engage_interactive" = 1 ]; then
        engage_prompt_model || { echo "$PROG: engage: no input — nothing engaged" >&2; exit 2; }
        engage_model="$ENGAGE_MODEL"
    fi
    if ! engage_valid_model "$engage_model"; then
        echo "$PROG: engage: --model must be one of: $(engage_list_models | tr '\n' ' ' | sed 's/ *$//') (got '$engage_model')" >&2
        exit 2
    fi
    template="converse-$engage_model"

    # Skill: offered interactively only when a NEW conversation is being filed,
    # since an existing conversation's ask is already written. It comes after the
    # model because the roster is that sitting's own:
    # <rig>/gc-toolkit.converse-<model>.
    if [ -z "$engage_skill" ] && [ "$engage_interactive" = 1 ] && [ -z "$named_conv" ] \
        && { [ "$engage_file_new" = 1 ] || [ -n "$engage_reason" ]; }; then
        engage_prompt_skill "$rig" "$engage_model" || { echo "$PROG: engage: no input — nothing engaged" >&2; exit 2; }
        engage_skill="$ENGAGE_SKILL"
    fi
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
    # is a distinct dialogue; the operator's pick at the prompt names one; and
    # with none of those engage attaches first: a live sitting's conversation,
    # else one waiting in the queue, else one whose sitting's session has
    # closed, else a new one. The listing and the session list must both answer
    # before engage chooses, so it never starts a second sitting beside a live
    # one it could not see. The holder and the status engage reads here are what
    # its bind is guarded on below.
    CONV=""; conv_state=""; conv_holder=""; conv_status=""
    if [ -n "$named_conv" ]; then
        CONV="$named_conv"
    elif [ "$engage_file_new" = 1 ] || [ -n "$engage_reason" ]; then
        :
    elif [ -n "$engage_chosen_conv" ]; then
        CONV="$engage_chosen_conv"
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
            echo "$PROG: engage: conversation $CONV is not an open conversation about $bead (closed, or not a conversation). Engage the subject to open a fresh one: $PROG engage $bead. Nothing spawned." >&2
            exit 4
        fi
        conv_state=$(printf '%s' "$conv_line" | cut -f2)
        conv_holder=$(printf '%s' "$conv_line" | cut -f3)
        conv_status=$(printf '%s' "$conv_line" | cut -f4)
    else
        if [ "$engage_file_new" = 1 ] || [ -n "$engage_reason" ]; then
            echo "$PROG: engage: filing a new conversation on $bead, then engaging it" >&2
            set -- "$bead" --allow-duplicate
            [ -n "$engage_reason" ] && set -- "$@" --reason "$engage_reason"
            [ -n "$engage_body" ] && set -- "$@" --body "$engage_body"
        else
            # Pointed at a gate, the conversation is filed through the gate, so
            # its title and ask are what the gate asks.
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
    fi

    # Pointed at a gate, the conversation engage landed on replies to it,
    # whichever it is, and the reply reads back before a sitting starts or the
    # operator attaches, so the sitting finds the gate among its conversation's
    # replies at its next read.
    if [ -n "$pointed_gate" ] && ! conversation_reply "$CONV" "$pointed_gate"; then
        echo "$PROG: engage: conversation $CONV's reply onto gate $pointed_gate did not read back, so the sitting would not know the gate it answers. Nothing spawned. Add it by hand and re-engage: gc bd dep add $CONV $pointed_gate --type replies-to" >&2
        exit 4
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
    # engage_await_start returns 0 once the sitting $sid's `gc session list` row
    # reads `active`, which it does only once the runtime is running; before the
    # launch it reads start-pending or creating. It returns 2 when the sitting
    # ended first, and 1 when ENGAGE_WAIT_TIMEOUT seconds pass first. A closed
    # sitting drops out of the list when gc reads it from the store, and stays
    # listed with an empty state when gc reads it from the supervisor, so both a
    # row that leaves the list and an empty state mean it ended, as does
    # failed-create. A sitting not listed yet may only lag the supervisor's read
    # cache, so it is waited on, and so is a listing that did not read.
    # start_state keeps the last state read, and start_waited the seconds waited
    # as of that read, for the messages that follow.
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
            start_state=$(gc session list --state all --json 2>/dev/null | scrub | jq -r --arg id "$sid" '
                if type == "object" and ((.sessions // null) | type) == "array"
                then (first(.sessions[] | select((.id // "") == $id)
                            | if (.state // "") == "" then "closed" else .state end)
                      // "unlisted")
                else "unreadable" end' 2>/dev/null || true)
            start_waited=$(( $(date +%s) - _start_t0 ))
            _start_now=""
            case "$start_state" in
                active) return 0 ;;
                closed|failed-create) return 2 ;;
                unlisted) [ "$_start_seen" = 0 ] || { start_state=gone; return 2; } ;;
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
            ''|unreadable) printf "could not be read from 'gc session list'" ;;
            *) printf 'is %s' "$1" ;;
        esac
    }
    # engage_kick — a codex sitting's opening turn; a claude one gets none
    # (see the kick's notes below).
    engage_kick() {
        case "$engage_model" in
            opus|fable) ;;   # provider=claude: self-starts from the argv prompt, no kick
            *)
                kick="The operator engaged this sitting. Begin now: claim your conversation ($CONV), re-check its premise, prep, and post your framing, then hold for the operator."
                _kick_opener="${engage_body:-$engage_reason}"
                [ -n "$_kick_opener" ] && kick="$kick The operator's reason: $_kick_opener"
                gc session nudge "$sid" "$kick" >/dev/null 2>&1 \
                    || echo "$PROG: engage: spawned and bound $CONV, but could not send $sid its opening turn — attach and type 'begin' to start it: gc session attach $sid" >&2
                ;;
        esac
    }
    # engage_wait <kick> — the attach path's wait for the launch, under the
    # INT, TERM and HUP trap, HUP being the terminal going away under the wait.
    # The handler writes and closes nothing, so the binding and the start carry
    # on without engage. With <kick> set, a codex sitting is kicked first, as on
    # every path past the wait, so it begins once it starts. The handler
    # disarms itself, so a second Ctrl-C ends engage at once. Leaves the wait's
    # answer in start_rc.
    engage_wait() {
        _ew_kick="$1"
        start_rc=0; start_waited=0
        trap 'engage_wait_interrupted 130' INT
        trap 'engage_wait_interrupted 143' TERM
        trap 'engage_wait_interrupted 129' HUP
        engage_await_start || start_rc=$?
        trap - INT TERM HUP
    }
    engage_wait_interrupted() {
        trap - INT TERM HUP
        [ -z "$_ew_kick" ] || engage_kick
        echo "$PROG: engage: stopped waiting after $(engage_dur "$start_waited"). Conversation $CONV stays held by $sname, which the reconciler goes on starting; attach once it reads active in 'gc session list': gc session attach $sid" >&2
        exit "$1"
    }

    # Once the attach returns, the tab is back at this shell, and what it prints
    # next is the operator's only account of the sitting it left: nothing of the
    # pane survives it. tmux shows [exited] when the sitting's session ended
    # (each converse template sets detach-on-destroy on its own session) and
    # [detached] when the operator left it, and both exit 0, so the
    # conversation says which. A closed conversation is a sitting that ended,
    # and the tab prints how the conversation closed and the last hand-back the
    # sitting recorded on it (cmd_handback). A conversation still open is a
    # sitting still going, and the tab prints how to re-attach. A failed attach
    # reads the same conversation first, because a sitting that ended before the
    # tab reached it is reported, not offered for an attach.
    engage_after_attach() {
        _aa_row=$(row_now "$CONV")
        _aa_status=$(printf '%s' "$_aa_row" | jq -r '.status // ""' 2>/dev/null || true)
        if [ "$_aa_status" = "closed" ]; then
            _aa_reason=$(printf '%s' "$_aa_row" | jq -r '.close_reason // "" | tostring' 2>/dev/null || true)
            _aa_at=$(printf '%s' "$_aa_row" | jq -r '(.metadata // {})["gc.handback_at"] // "" | tostring' 2>/dev/null || true)
            # The text is the sitting's own, printed to the operator's terminal,
            # so control bytes other than tab and newline are dropped.
            _aa_text=$(printf '%s' "$_aa_row" | jq -r '(.metadata // {})["gc.handback"] // "" | tostring
                | gsub("[\\x00-\\x08\\x0b-\\x1f\\x7f]"; "")' 2>/dev/null || true)
            printf '\nThe sitting on %s has ended: conversation %s closed%s.\n' "$bead" "$CONV" "${_aa_reason:+ ($_aa_reason)}"
            if [ -n "$_aa_text" ]; then
                printf 'Its last hand-back%s:\n\n%s\n' "${_aa_at:+, recorded $_aa_at}" "$_aa_text"
            else
                printf 'It recorded no hand-back.\n'
            fi
        elif [ "$1" -ne 0 ]; then
            echo "$PROG: engage: could not attach to $sid — attach when ready: gc session attach $sid" >&2
        elif [ -z "$_aa_status" ]; then
            printf '\nCould not read conversation %s, so whether its sitting has ended is unknown: gc bd show %s\n' "$CONV" "$CONV"
        else
            printf '\nThe sitting on %s is still open (conversation %s). Re-attach: gc session attach %s\n' "$bead" "$CONV" "$sid"
        fi
    }

    # A live sitting holds this conversation: attach the operator to it rather
    # than start a second. A sitting is live from the spawn that created it, so
    # one another engage spawned with --no-attach can still be waiting for the
    # reconciler's launch, and the attach waits for it here as it does below.
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
        printf '✓ the live sitting %s holds conversation %s for %s — attaching to it rather than starting a second\n' "$sid" "$CONV" "$bead"
        printf '  attach: gc session attach %s\n' "$sid"
        printf '[debug] conversation=%s sitting=%s holder=%s subject=%s\n' "$CONV" "$sid" "$conv_holder" "$bead" >&2
        if [ "$engage_attach" = "1" ]; then
            engage_wait ""
            case "$start_rc" in
                0) attach_rc=0
                   gc session attach "$sid" || attach_rc=$?
                   engage_after_attach "$attach_rc" ;;
                2) echo "$PROG: engage: the sitting $sname that holds conversation $CONV ended before the reconciler started it (its state in 'gc session list': $start_state), so there is nothing to attach. Re-run to start a sitting on it: $PROG engage $bead" >&2
                   exit 4 ;;
                *) echo "$PROG: engage: the reconciler has not started $sname after $(engage_dur "$ENGAGE_WAIT_TIMEOUT") (its state in 'gc session list': ${start_state:-unreadable}), so it was not attached; an attach now would launch it without its prompt. Attach once it reads active there: gc session attach $sid" >&2
                   exit 4 ;;
            esac
        fi
        return 0
    fi

    # A session still in the list under this conversation's alias that does not
    # hold it keeps the alias, since only a closed session gives one up. A
    # sitting cut short leaves exactly that: its conversation back in the queue
    # and its session waiting for converse-reap. So such a session is closed
    # first and read back gone, and only then is the alias free for the new
    # sitting. A session spawned less than the bind wait ago may be a concurrent
    # engage about to bind the conversation, and one the operator is attached to
    # is a pane in use, so neither is closed here: the spawn below meets its
    # alias, and engage_alias_held waits for its bind and names it.
    if ! live_now=$(live_sittings); then
        echo "$PROG: engage: could not read 'gc session list' before starting a sitting on conversation $CONV. Nothing spawned; retry once it answers: $PROG engage $bead" >&2
        exit 4
    fi
    stale_after="${GC_HELM_ENGAGE_BIND_WAIT:-20}"
    case "$stale_after" in ''|*[!0-9]*) stale_after=20 ;; esac
    for _st in $(printf '%s' "$live_now" | jq -r --arg c "$CONV" --argjson w "$stale_after" "$CONVERSATION_JQ"'
            .[] | select({id: $c, assignee: .alias} | conversation_alias)
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
    # from the city root (where the tmux board picker runs) the bare name matches
    # no rig and nothing spawns. Point GC_DIR at the subject's rig so the name
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

    # The spawn was refused because a session already holds the alias, so this
    # engage spawned nothing and must point the operator at what holds the
    # conversation, never at a sitting to close that may be the one that won.
    # The holder is either a concurrent engage that spawned first and is about
    # to bind the conversation, or a sitting left by an engage that stopped
    # between its spawn and its bind. Only the conversation tells them apart: a
    # concurrent engage binds it within one store write of its spawn returning.
    # So wait up to GC_HELM_ENGAGE_BIND_WAIT seconds for its holder to change
    # from the one this engage read, and name the session as left over only
    # when it stayed unchanged for the whole wait. Exits 4 on every path.
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
            if [ -n "$_ah_status" ] && { [ "$_ah_status" = "closed" ] || [ "$_ah_owner" != "$conv_holder" ]; }; then
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
        if [ -n "$_ah_status" ] && [ "$_ah_owner" != "$conv_holder" ]; then
            echo "$PROG: engage: conversation $CONV is held by '${_ah_owner:-nobody}', bound while this engage was spawning, so nothing was spawned here. Attach to its sitting instead: $PROG engage $CONV" >&2
            exit 4
        fi
        # The alias engage asked for is the final segment of the qualified
        # alias gc stores (conversation.sh's conversation_alias reads it). A
        # listing that does not answer with a sessions array names no holder
        # and proves none gone.
        _ah_list_ok=1
        _ah_holder=$(gc session list --state all --json 2>/dev/null | scrub | jq -er --arg c "$CONV" "$CONVERSATION_JQ"'
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
            *"session alias already exists"*) engage_alias_held ;;
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
        salias=$(gc session list --state all --json 2>/dev/null | scrub \
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
    # own. Either way the conversation must read back held by this sitting and
    # not closed, or the sitting has nothing to claim and is closed.
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
    fi
    bound_row=$(row_now "$CONV")
    assigned=$(printf '%s' "$bound_row" | jq -r '.assignee // ""' 2>/dev/null || true)
    bound_status=$(printf '%s' "$bound_row" | jq -r '(.status // "") | ascii_downcase' 2>/dev/null || true)
    if [ "$assigned" != "$salias" ]; then
        if [ -n "$assigned" ] && [ "$assigned" != "$conv_holder" ]; then
            engage_abort "$sid" "conversation $CONV is held by '$assigned', not the sitting '$salias' this engage spawned — another writer took it after the bind. The sitting holds nothing and was closed; re-run to reach it: $PROG engage $bead"
        fi
        engage_abort "$sid" "conversation $CONV read back assigned to '${assigned:-nobody}' after binding it to '$salias' — the bind did not persist. The sitting holds nothing and was closed; the conversation is unchanged — re-run: $PROG engage $bead"
    fi
    if [ "$bound_status" = closed ]; then
        engage_abort "$sid" "conversation $CONV reads closed (a dismiss, or a sign-off, closed it while this sitting spawned), so the sitting $sname has nothing to claim and was closed. Engage the subject to open a fresh conversation: $PROG engage $bead"
    fi
    bust_cache

    # Leave a reminder on the subject's PR that this sitting engaged, if it has
    # a PR. Best effort: pr-sitting-comment.sh self-silences when the subject
    # has no PR or gh is absent, and its failure must not fail an engage that
    # already bound its conversation. (The reason is passed conditionally
    # because /bin/sh word-splits ${x:+...}, which would break a multi-word
    # reason.)
    if [ -x "$SITTING_COMMENT_TOOL" ]; then
        if [ -n "$engage_reason" ]; then
            "$SITTING_COMMENT_TOOL" engage --sitting "$CONV" --subject "$bead" --reason "$engage_reason" || true
        else
            "$SITTING_COMMENT_TOOL" engage --sitting "$CONV" --subject "$bead" || true
        fi
    fi

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
    if [ "$conv_new" = 0 ] && [ -z "$named_conv" ] && [ -z "$engage_chosen_conv" ]; then
        conv_title=$(row_now "$CONV" | jq -r '.title // ""' 2>/dev/null || true)
        conv_label="conversation $CONV"
        [ -n "$conv_title" ] && conv_label="conversation \"$conv_title\""
        echo "$PROG: engage: took the $conv_label already on $bead, not a fresh one. To open a new conversation instead, re-run: $PROG engage $bead --reason \"<topic>\""
    fi
    printf '[debug] conversation=%s sitting=%s (%s) alias=%s subject=%s work_dir=%s\n' \
        "$CONV" "$sid" "$sname" "$salias" "$bead" "${swork_dir:-?}" >&2

    # A freshly spawned sitting self-starts from the prompt its launch delivers,
    # and only the reconciler's launch delivers one. `gc session new --no-attach`
    # records the sitting as start-pending. The reconciler then launches it with
    # the rendered converse prompt on argv (every converse provider resolves to
    # prompt_mode=arg), and step 1 of that prompt is the claim block. So a claude
    # sitting (opus, fable) claims its conversation, re-checks the premise, preps, and
    # posts its framing with no keystrokes. Sending it a kick as well is worse
    # than redundant. engage would deliver the kick while that self-started turn
    # is still running, so the harness holds it as a deferred reminder and
    # releases it after the framing lands, and the operator reads a stale
    # "begin now" once per engage.
    #
    # The attach path waits for the reconciler's launch first
    # (engage_await_start, above), and attaches only a started sitting.
    # It waits as long as the start takes, because a start on a busy controller
    # can take minutes, and an engage that stops waiting first leaves the
    # operator with no sitting on screen while it starts anyway.
    #
    # codex is the exception to self-starting. gascity delivers its prompt the
    # same way, but the codex CLI is not trusted to consume an argv prompt at
    # launch: its pool slots carry no prompt template and are primed by an
    # explicit nudge instead. A codex sitting can wake idle at its prompt, so it
    # keeps a START directive kick. A bare poke reads as a connectivity check and
    # does not begin the loop, so the kick names the action. An idle session takes
    # it at once, with no in-flight turn for the harness to defer it behind. The
    # kick follows the start wait and precedes the attach, so the operator lands
    # on a started sitting. On the --no-attach board-picker path it starts the
    # sitting for whoever attaches later; a kick that reaches the sitting before
    # its launch does not launch it, because gc queues the nudge and delivers it
    # once the reconciler has. A failed kick is not fatal: the conversation is bound, so
    # report it and let the operator start it by hand.
    #
    # A --reason is filed into the conversation's ask by cmd_open, so every sitting reads
    # it when it claims. The kick also carries it, for the one provider kicked.
    start_rc=0
    if [ "$engage_attach" = "1" ]; then
        engage_wait kick
        if [ "$start_rc" -eq 2 ]; then
            echo "$PROG: engage: the sitting $sname ended before the reconciler started it (its state in 'gc session list': $start_state), so there is nothing to attach. Conversation $CONV is still bound to it; hand it back to the operator's queue: gc bd update $CONV --if-assignee \"$salias\" --assignee human --status open" >&2
            exit 4
        fi
    fi

    engage_kick

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

# ── Dispatch ─────────────────────────────────────────────────────────
case "${1:-}" in
    open)          shift; cmd_open "$@" ;;
    engage)        shift; cmd_engage "$@" ;;
    react)         shift; cmd_react "$@" ;;
    resolve)       shift; cmd_resolve "$@" ;;
    unplaced)      shift; cmd_unplaced "$@" ;;
    takeaway)      shift; cmd_takeaway "$@" ;;
    park)          shift; cmd_park "$@" ;;
    priority)      shift; cmd_priority "$@" ;;
    dismiss)       shift; cmd_dismiss "$@" ;;
    handback)      shift; cmd_handback "$@" ;;
    accept)        shift; cmd_accept "$@" ;;
    board)         echo "$PROG: the board moved to 'helm-svc board' (services/helm)" >&2; exit 2 ;;
    demand)        echo "$PROG: a wait a person must clear is a human gate on the bead that waits: file it with human-gate.sh --subject <bead> --key <key> --message \"<what they must clear>\", or with gc bd gate create --type=human --blocks <bead>. Nothing was filed." >&2; exit 2 ;;
    -h|--help|help) usage; exit 0 ;;
    *)             echo "$PROG: unknown verb '${1:-}' (try: open, engage, react, accept, takeaway, park, priority, dismiss, handback, resolve, unplaced, help; the board is 'helm-svc board')" >&2; usage; exit 2 ;;
esac
