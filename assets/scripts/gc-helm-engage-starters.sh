#!/bin/sh
# gc-helm-engage-starters.sh — the starter-seed table for `gc-helm engage`.
# A starter is the opening message a fresh converse sitting reads when it claims
# its visit. A seed establishes the TOPIC and the sitting's READINESS to talk;
# it does not set an agenda or presume a direction — the operator leads once
# engaged. The one investigative seed (unstick-a-stall) still names no single
# cause. A lens brief names a skill the sitting loads and reads the subject
# through (`engage --skill`); a seed or the operator's own opener, when there is
# one, follows it. These live here, not inline in engage's prompt loop, so they
# can be tuned without touching the CLI. `__SUBJECT__` is replaced with the
# subject bead id and `__SKILL__` with the skill name at emit time.
# Interface:
#   gc-helm-engage-starters.sh list                 -> "<key>\t<label>\t<letter>" per seed
#   gc-helm-engage-starters.sh seed <key> [subject] -> the seed body on stdout
#   gc-helm-engage-starters.sh lens <skill> [subject] [opener]
#                                                   -> the lens brief on stdout,
#                                                      the opener verbatim after it
# Exit: 0 ok, 2 unknown key / not a skill name / usage.
# Caller: assets/scripts/gc-helm.sh (cmd_engage).
set -eu

PROG="gc-helm-engage-starters"

# The seed rows, in menu order. A seed's key is its stable --template token, its
# label is the one-line menu caption, and its letter is the accelerator engage's
# consolidated visit/starter prompt reads — numbers there pick existing visits,
# so a letter never collides with a visit choice. The bodies are emitted by
# seed_body below, keyed on the same tokens.
seed_list() {
    printf '%s\t%s\t%s\n' discuss-broadly "discuss broadly" d
    printf '%s\t%s\t%s\n' pr-feedback     "PR feedback"     p
    printf '%s\t%s\t%s\n' unstick-a-stall "unstick a stall" s
}

# seed_body <key> — the raw seed text on stdout, with the literal __SUBJECT__
# placeholder; the caller substitutes the subject. Quoted heredocs so nothing in
# the prose is expanded or run.
seed_body() {
    case "$1" in
        discuss-broadly) cat <<'H'
The operator wants to talk through __SUBJECT__ broadly. Load its context and be
ready to discuss, then WAIT for the operator's direction — do not propose an
agenda or start analyzing.
H
            ;;
        pr-feedback) cat <<'H'
The operator has questions about this PR that aren't captured in the review yet
and wants to talk it through before commenting formally. Load the PR and its
diff for context, then let the operator lead with their questions.
H
            ;;
        unstick-a-stall) cat <<'H'
__SUBJECT__ looks stalled. Work out why it isn't moving — blockers, routing,
gates, missing or mis-routed work — and what would unstick it. There may be
several issues; do not assume a single cause.
H
            ;;
        *) return 2 ;;
    esac
}

# lens_body <with-opener> — the raw lens brief, with the literal __SKILL__ and
# __SUBJECT__ placeholders. The skill's own method carries a final step written
# for the bead it was built to serve (a review skill ends in a signoff.sh
# verdict on its review bead), and a sitting holds a visit, not that bead, so
# the brief keeps the skill's judgment and withholds its final writes. Its last
# sentence says what to do first: with no opener the lens is the whole
# assignment, and with one the opener that follows decides.
lens_body() {
    cat <<'H'
The operator engaged this sitting to look at __SUBJECT__ through the __SKILL__
skill. Load that skill before you prep, and keep its lens for the whole sitting:
read and judge __SUBJECT__ and its universe the way the skill does. Use its way
of reading and judging, not its final step. A review verdict, a sign-off, or any
other write the skill makes on the bead it was written for is not yours to make,
because you hold a visit, not that bead. State the skill's judgment in your
framing instead. If no skill by that name is available to you, say so at the top
of your framing and continue without it.
H
    if [ "$1" = 1 ]; then
        echo "The operator's opener follows and says what to do first."
    else
        echo "Post your framing through that lens, then WAIT for the operator's direction."
    fi
}

case "${1:-}" in
    list)
        seed_list
        ;;
    seed)
        [ $# -ge 2 ] || { echo "$PROG: seed needs <key>" >&2; exit 2; }
        key="$2"
        subject="${3:-<subject>}"
        # A subject bead id carries no sed metacharacter, so a plain s|| holds;
        # the placeholder is emitted verbatim when no subject is given.
        if body=$(seed_body "$key"); then
            printf '%s' "$body" | sed "s|__SUBJECT__|$subject|g"
        else
            echo "$PROG: unknown seed '$key' (valid: $(seed_list | cut -f1 | tr '\n' ' ' | sed 's/ *$//'))" >&2
            exit 2
        fi
        ;;
    lens)
        [ $# -ge 2 ] || { echo "$PROG: lens needs <skill>" >&2; exit 2; }
        skill="$2"
        subject="${3:-<subject>}"
        opener="${4:-}"
        # A skill name is letters, digits, dots and hyphens. Refusing anything
        # else keeps the plain s|| below sound, since no sed metacharacter can
        # reach the replacement.
        case "$skill" in
            ""|*[!A-Za-z0-9._-]*) echo "$PROG: lens: '$skill' is not a skill name" >&2; exit 2 ;;
        esac
        with_opener=0
        if [ -n "$opener" ]; then with_opener=1; fi
        lens_body "$with_opener" | sed "s|__SUBJECT__|$subject|g; s|__SKILL__|$skill|g"
        # The opener is the operator's own text, so it is emitted verbatim and
        # never passes through the substitution.
        if [ "$with_opener" = 1 ]; then printf '\n%s\n' "$opener"; fi
        ;;
    ""|-h|--help)
        cat >&2 <<'U'
usage: gc-helm-engage-starters.sh list
       gc-helm-engage-starters.sh seed <key> [subject]
       gc-helm-engage-starters.sh lens <skill> [subject] [opener]

  list   print "<key>\t<label>\t<letter>" for each starter seed, in menu order.
  seed   print the named seed's body, replacing __SUBJECT__ with [subject].
  lens   print the brief that seeds a sitting with <skill> as its lens on
         [subject]; a non-empty [opener] follows it verbatim.
U
        [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || exit 2
        ;;
    *)
        echo "$PROG: unknown subcommand '$1' (try: list, seed, lens)" >&2
        exit 2
        ;;
esac
