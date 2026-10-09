#!/bin/sh
# gc-helm-engage-starters.sh — the starter-seed table for `gc-helm engage`.
# A starter is the opening message a fresh converse sitting reads when it claims
# its visit. A seed establishes the TOPIC and the sitting's READINESS to talk;
# it does not set an agenda or presume a direction — the operator leads once
# engaged. The one investigative seed (unstick-a-stall) still names no single
# cause. These live here, not inline in engage's prompt loop, so they can be
# tuned without touching the CLI. `__SUBJECT__` is replaced with the subject
# bead id at emit time.
# Interface:
#   gc-helm-engage-starters.sh list                 -> "<key>\t<label>\t<letter>" per seed
#   gc-helm-engage-starters.sh seed <key> [subject] -> the seed body on stdout
# Exit: 0 ok, 2 unknown key / usage.
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
    ""|-h|--help)
        cat >&2 <<'U'
usage: gc-helm-engage-starters.sh list
       gc-helm-engage-starters.sh seed <key> [subject]

  list   print "<key>\t<label>\t<letter>" for each starter seed, in menu order.
  seed   print the named seed's body, replacing __SUBJECT__ with [subject].
U
        [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || exit 2
        ;;
    *)
        echo "$PROG: unknown subcommand '$1' (try: list, seed)" >&2
        exit 2
        ;;
esac
