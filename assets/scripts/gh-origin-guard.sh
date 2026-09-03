#!/bin/sh
# gh-origin-guard.sh — Claude PreToolUse hook: refuse an agent-typed `gh` write
# aimed at a repository this rig does not own.
#
# One bot account backs every agent's gh token, so any agent can write to any
# repository that token reaches. Filing an issue, a PR, or a comment on someone
# else's repository spends a stranger's attention, and that is the operator's
# call rather than an agent's. This script is where that boundary is enforced.
#
# The boundary is the OWN ORIGIN of a rig, not an organization. Rigs legitimately
# live outside the operator's org — shutupandlisten's origin is
# suandl/shutupandlisten — so an org-keyed rule would refuse that rig's whole PR
# flow while still permitting writes to unrelated repositories inside the org.
#
# What it sees: the command an agent types into Bash. A `gh` call made inside a
# script the agent runs is invisible here, and pr-open.sh and pr-facts.sh
# already pin --repo to an origin they resolve themselves. This guards reach by
# accident; it is not a sandbox and a determined bypass stays available.
#
# Contract:
#   * stdout is one JSON deny object, or nothing at all.
#   * exit 0 always — the refusal travels in the JSON, and a guard that crashed
#     must not wedge every Bash call in the city.
#   * A write verb whose target cannot be established is REFUSED. "Outside the
#     origin" is the safe reading of a target that will not resolve.

set -u

# The bead tracking the prepare-a-command-instead-of-sending-it path, named in
# the refusal so a blocked agent is told what to do rather than only stopped.
PREPARE_PATH_BEAD="tk-k80q5m"

# --- output --------------------------------------------------------------

json_string() {
    printf '%s' "${1:-}" \
        | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
        | awk 'BEGIN { ORS = "" } NR > 1 { print "\\n" } { print }'
}

deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
        "$(json_string "$1")"
    exit 0
}

# --- repository identity -------------------------------------------------

# Reduce any spelling of a repository to host/owner/name, lowercased. Accepts
# owner/name, host/owner/name, and the https/ssh/scp remote URL forms. The host
# is kept and compared: dropping it would let another forge carrying the same
# owner/name pair read as an origin we own. Unparseable input yields empty,
# which every caller treats as unresolved.
norm_repo() {
    _r=$(printf '%s' "${1:-}" | tr -d '[:space:]' | tr 'A-Z' 'a-z')
    [ -n "$_r" ] || return 0
    _r=$(printf '%s' "$_r" \
        | sed -e 's#^[a-z][a-z0-9+.-]*://##' \
              -e 's#^[^/@]*@##' \
              -e 's#:#/#' \
              -e 's#\.git$##' \
              -e 's#/*$##')
    case $(printf '%s' "$_r" | awk -F/ '{ print NF }') in
        2) _r="${GH_HOST:-github.com}/$_r" ;;
        3) : ;;
        *) return 0 ;;
    esac
    # Every element must be present and plausible; a stray empty field would
    # otherwise compare equal across two different repositories.
    printf '%s' "$_r" | grep -Eq '^[a-z0-9.-]+/[a-z0-9._-]+/[a-z0-9._-]+$' || return 0
    printf '%s' "$_r"
}

origin_of() {
    [ -n "${1:-}" ] || return 0
    [ -d "$1" ] || return 0
    _u=$(git -C "$1" remote get-url origin 2>/dev/null) || return 0
    norm_repo "$_u"
}

# The repositories a write may land on, one per line.
#
# $GC_RIG_ROOT is authoritative and narrow: a rig agent is measured against its
# OWN rig even while standing in a clone of something else. City-scope agents
# (deacon, mechanik) carry no rig root and legitimately work across rigs, so
# for them the owned set is every rig in the city. Falling back to the working
# directory instead would make the guard vacuous exactly where it is needed —
# a checkout of someone else's repository would authorize itself.
allowed_origins() {
    if [ -n "${GC_RIG_ROOT:-}" ]; then
        _o=$(origin_of "$GC_RIG_ROOT")
        if [ -n "$_o" ]; then
            printf '%s\n' "$_o"
            return 0
        fi
    fi
    _found=""
    if [ -n "${GC_CITY_PATH:-}" ] && [ -d "$GC_CITY_PATH/rigs" ]; then
        for _d in "$GC_CITY_PATH"/rigs/*; do
            [ -d "$_d" ] || continue
            _o=$(origin_of "$_d")
            [ -n "$_o" ] || continue
            _found=1
            printf '%s\n' "$_o"
        done
    fi
    [ -n "$_found" ] && return 0
    origin_of "$CWD"
}

# --- payload -------------------------------------------------------------

command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat 2>/dev/null) || exit 0
[ -n "$PAYLOAD" ] || exit 0

# One jq for the overwhelmingly common case: this hook runs ahead of every Bash
# call in the city, so anything that is not a Bash call naming `gh` as a command
# word leaves here having paid a single filter.
GATE=$(printf '%s' "$PAYLOAD" | jq -r '
    if (.tool_name == "Bash")
       and ((.tool_input.command // "") | test("(^|[^a-zA-Z0-9_-])gh([^a-zA-Z0-9_-]|$)"))
    then "1" else "0" end' 2>/dev/null) || exit 0
[ "$GATE" = "1" ] || exit 0

CMD=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

CWD=$(printf '%s' "$PAYLOAD" | jq -r '.cwd // ""' 2>/dev/null)
{ [ -n "${CWD:-}" ] && [ -d "$CWD" ]; } || CWD=$PWD

# --- command inspection --------------------------------------------------

# Find guarded writes in the command line, honouring shell quoting.
#
# Quoting is the whole difficulty. A --title or --body routinely carries prose
# about gh itself, and a scanner that splits on whitespace reads the `--repo`
# inside such a body as this call's target — refusing a write to our own
# repository because of a sentence in it. Tokenizing with quote state keeps a
# quoted argument as ONE token, so its contents can never be mistaken for
# structure. The same walk splits commands on unquoted operators, so a write
# behind && or a pipe is inspected rather than skipped.
#
# Emits one line per guarded write, fields separated by \037: noun, verb, --repo
# value, inline GH_REPO value, and the pending cd destination. A unit separator
# rather than a tab, because the shell collapses runs of whitespace separators
# and an empty --repo field would shift the inline GH_REPO into its place. The
# shell resolves origins; awk only lexes.
SCAN=$(printf '%s' "$CMD" | awk '
function push() {
    if (have) { ntok++; T[ntok] = tok }
    tok = ""; have = 0
}
# A cd earlier on the same command line moves where a later gh call resolves its
# repository. Following it is what keeps `cd <someone-elses-clone> && gh issue
# create` from being measured against the directory the session started in. An
# unexpandable destination becomes "?", which resolves to no repository and is
# therefore refused rather than assumed to be ours.
function note_cd(i,   a) {
    if (i + 1 > ntok) { cdspec = "?"; return }
    a = T[i + 1]
    if (a == "-" || a ~ /\$/ || substr(a, 1, 1) == "~") { cdspec = "?"; return }
    if (substr(a, 1, 1) == "/") { cdspec = a }
    else if (cdspec == "?") { return }
    else if (cdspec == "") { cdspec = a }
    else { cdspec = cdspec "/" a }
}
function analyze(   i, j, noun, verb, key, repo, inl) {
    if (ntok == 0) return
    i = 1; inl = ""
    # Leading assignments and command wrappers sit in front of the real command.
    # GH_REPO among them is the repository gh would use, so it is kept.
    while (i <= ntok) {
        if (T[i] ~ /^GH_REPO=/) { inl = substr(T[i], 9); i++; continue }
        if (T[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
        if (T[i] == "env" || T[i] == "command" || T[i] == "builtin" ||
            T[i] == "nohup" || T[i] == "exec" || T[i] == "time") { i++; continue }
        break
    }
    if (i > ntok) return
    if (T[i] == "cd") { note_cd(i); return }
    if (T[i] != "gh" && T[i] !~ /\/gh$/) return
    i++
    # gh reads as `gh <noun> <verb>`: the noun is the first token that is not an
    # option, the verb the one directly after it. Taking the verb by position
    # rather than by searching is what keeps prose from matching.
    noun = ""; verb = ""
    while (i <= ntok) {
        if (substr(T[i], 1, 1) == "-") { i++; continue }
        noun = T[i]
        if (i + 1 <= ntok) verb = T[i + 1]
        break
    }
    key = noun "/" verb
    # Exactly the verbs the ruling names. `gh api` reaches the same endpoints
    # and is deliberately not covered.
    if (key != "issue/create" && key != "issue/comment" &&
        key != "pr/create" && key != "pr/comment" && key != "pr/review") return
    # --repo/-R wins over everything, matching gh: flag, then GH_REPO, then the
    # repository of the working directory.
    repo = ""
    for (j = 1; j <= ntok; j++) {
        if (T[j] ~ /^--repo=/) { repo = substr(T[j], 8); break }
        if (T[j] ~ /^-R=/)     { repo = substr(T[j], 4); break }
        if (T[j] == "--repo" || T[j] == "-R") {
            if (j < ntok) repo = T[j + 1]
            break
        }
    }
    printf "%s\037%s\037%s\037%s\037%s\n", noun, verb, repo, inl, cdspec
}
function reset(   k) { for (k = 1; k <= ntok; k++) delete T[k]; ntok = 0 }
BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); BT = sprintf("%c", 96) }
{ buf = (NR > 1 ? buf "\n" $0 : $0) }
END {
    n = length(buf); tok = ""; have = 0; ntok = 0; inS = 0; inD = 0; cdspec = ""
    for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (inS) { if (c == SQ) inS = 0; else { tok = tok c; have = 1 } ; continue }
        if (inD) {
            if (c == DQ) { inD = 0; continue }
            if (c == "\\" && i < n) { i++; tok = tok substr(buf, i, 1); have = 1; continue }
            tok = tok c; have = 1; continue
        }
        if (c == SQ) { inS = 1; have = 1; continue }
        if (c == DQ) { inD = 1; have = 1; continue }
        if (c == "\\" && i < n) { i++; tok = tok substr(buf, i, 1); have = 1; continue }
        if (c == " " || c == "\t") { push(); continue }
        if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")" ||
            c == BT || c == "\n") { push(); analyze(); reset(); continue }
        tok = tok c; have = 1
    }
    push(); analyze()
}' 2>/dev/null)

[ -n "${SCAN:-}" ] || exit 0

# --- verdict -------------------------------------------------------------

# Every guarded write on the command line is judged, not only the first: a
# legitimate write chained ahead of an off-origin one must not shield it.
ALLOWED=$(allowed_origins)
OWNED=$(printf '%s' "$ALLOWED" | paste -sd, - 2>/dev/null)

NOUN=""; VERB=""; TARGET=""; REFUSE=""
while IFS="$(printf '\037')" read -r _noun _verb _flag _inline _cd; do
    [ -n "${_noun:-}" ] || continue

    # Where this call would actually run, after any cd ahead of it.
    _base=$CWD
    if [ -n "${_cd:-}" ]; then
        if [ "$_cd" = "?" ]; then
            _base=""
        else
            case "$_cd" in
                /*) _base=$_cd ;;
                *)  _base="$CWD/$_cd" ;;
            esac
            [ -d "$_base" ] || _base=""
        fi
    fi

    if [ -n "${_flag:-}" ]; then
        _target=$(norm_repo "$_flag")
    elif [ -n "${_inline:-}" ]; then
        _target=$(norm_repo "$_inline")
    elif [ -n "${GH_REPO:-}" ]; then
        _target=$(norm_repo "$GH_REPO")
    else
        # No explicit target: gh resolves against the working directory's
        # remote, so the guard resolves the same way rather than waving the
        # call through.
        _target=$(origin_of "$_base")
    fi

    if [ -n "${ALLOWED:-}" ] && [ -n "${_target:-}" ] \
       && printf '%s\n' "$ALLOWED" | grep -Fxq "$_target"; then
        continue
    fi

    NOUN=$_noun; VERB=$_verb; TARGET=${_target:-}; REFUSE=1
    break
done <<SCANLINES
$SCAN
SCANLINES

[ -n "$REFUSE" ] || exit 0

if [ -z "${ALLOWED:-}" ]; then
    deny "gh-origin-guard: refused \`gh $NOUN $VERB\`.

No repository of our own could be resolved here, so there is no way to tell
whether ${TARGET:-that repository} is one of ours. A write that cannot be shown
to land on a repository we own is treated as landing on someone else's.

Run it from a checkout whose \`origin\` remote is the rig's repository, or hand
the operator the exact command to send. Bead $PREPARE_PATH_BEAD carries the
prepare-a-command path."
fi

if [ -z "${TARGET:-}" ]; then
    deny "gh-origin-guard: refused \`gh $NOUN $VERB\`.

No target repository could be resolved for this call: it names no --repo, and
the working directory is not a checkout with a GitHub \`origin\` remote. The
repositories this session may write to are: $OWNED.

Name the repository explicitly with \`--repo\` if the write belongs to one of
those. Bead $PREPARE_PATH_BEAD carries the path for a write that belongs
somewhere else."
fi

deny "gh-origin-guard: refused \`gh $NOUN $VERB\` aimed at $TARGET.

That repository is not ours. This session may write to: $OWNED.

Opening an issue or a PR, or leaving a comment, on anyone else's repository
spends their attention, and the operator holds that decision — an agent does not
make it on their behalf.

Instead of sending: prepare the exact command and file it for the operator to
run, which is the path bead $PREPARE_PATH_BEAD carries. If the operator has
already approved this specific send, they run it themselves.

Reads are unaffected: \`gh issue view\`, \`gh pr view\`, \`gh search\` and the
rest reach $TARGET normally."
