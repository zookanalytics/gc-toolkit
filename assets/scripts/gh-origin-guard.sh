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
    # An unqualified owner/name is completed with the host gh would use for the
    # call: the effective host the caller resolves ($2), else this process's
    # ambient GH_HOST, else github.com. Qualifying against the ambient value
    # alone would read `GH_HOST=other gh ... --repo owner/name` as our own forge.
    _host=${2:-}
    [ -n "$_host" ] || _host=${GH_HOST:-github.com}
    _host=$(printf '%s' "$_host" | tr -d '[:space:]' | tr 'A-Z' 'a-z')
    [ -n "$_host" ] || _host=github.com
    _r=$(printf '%s' "$_r" \
        | sed -e 's#^[a-z][a-z0-9+.-]*://##' \
              -e 's#^[^/@]*@##' \
              -e 's#:#/#' \
              -e 's#\.git$##' \
              -e 's#/*$##')
    case $(printf '%s' "$_r" | awk -F/ '{ print NF }') in
        2) _r="$_host/$_r" ;;
        3) : ;;
        *) return 0 ;;
    esac
    # Every element must be present and plausible; a stray empty field would
    # otherwise compare equal across two different repositories.
    printf '%s' "$_r" | grep -Eq '^[a-z0-9.-]+/[a-z0-9._-]+/[a-z0-9._-]+$' || return 0
    printf '%s' "$_r"
}

# Extract host/owner/name from the `<url>` operand of `gh issue comment`,
# `gh pr comment` and `gh pr review` — the URL names the repository directly.
# A bare number, a branch name, or anything not shaped like an issue/PR URL
# yields empty, so it is never mistaken for a repository and a branch operand is
# not read as a false target.
repo_from_url() {
    _u=$(printf '%s' "${1:-}" | tr -d '[:space:]' | tr 'A-Z' 'a-z')
    [ -n "$_u" ] || return 0
    printf '%s' "$_u" | grep -Eq '^([a-z][a-z0-9+.-]*://)?[a-z0-9.-]+/[^/]+/[^/]+/(issues|pull|discussions)/' || return 0
    _hon=$(printf '%s' "$_u" \
        | sed -e 's#^[a-z][a-z0-9+.-]*://##' \
        | awk -F/ '{ print $1 "/" $2 "/" $3 }')
    norm_repo "$_hon"
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
        # Set but narrow: the owned set is this rig's origin and nothing else. An
        # unresolvable rig root yields an EMPTY set, not a fall-through to the
        # city or the working directory — a broken root must fail closed, or a
        # checkout of someone else's repository could authorize its own writes.
        origin_of "$GC_RIG_ROOT"
        return 0
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
# value, inline GH_REPO value, the pending cd destination, whether an earlier
# export/unset set GH_REPO in this shell (1/0), that exported value, the inline
# GH_HOST value, whether an earlier export/unset set GH_HOST (1/0), that exported
# value, and the positional operand of a URL-capable verb (issue/pr comment, pr
# review). A unit separator rather than a tab, because the shell collapses runs
# of whitespace separators and an empty field would shift the next one into its
# place. The shell resolves origins; awk only lexes.
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
function note_cd_val(a) {
    if (a == "" || a == "-" || a ~ /\$/ || substr(a, 1, 1) == "~") { cdspec = "?"; return }
    if (substr(a, 1, 1) == "/") { cdspec = a }
    else if (cdspec == "?") { return }
    else if (cdspec == "") { cdspec = a }
    else { cdspec = cdspec "/" a }
}
function note_cd(i) {
    if (i + 1 > ntok) { cdspec = "?"; return }
    note_cd_val(T[i + 1])
}
function analyze(   i, j, k, w, noun, verb, key, repo, inl, inlhost, urlop) {
    if (ntok == 0) return
    i = 1; inl = ""; inlhost = ""
    # Leading assignments and command wrappers sit in front of the real command.
    # GH_REPO and GH_HOST among them are what gh would use for the call, so they
    # are kept; the rest are skipped to reach the command word.
    while (i <= ntok) {
        if (T[i] ~ /^GH_REPO=/) { inl = substr(T[i], 9); i++; continue }
        if (T[i] ~ /^GH_HOST=/) { inlhost = substr(T[i], 9); i++; continue }
        if (T[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
        # env carries its own options and NAME=VALUE assignments before the
        # command. Skipping only the word `env` left an option such as -i as the
        # command token, so the wrapped write was never reached. Parse the env
        # arguments: assignments set GH_REPO/GH_HOST for the call, -C/--chdir
        # moves the directory the way cd does, -u/--unset drops a carried
        # variable, and the first bare word is the wrapped command.
        if (T[i] == "env") {
            i++
            while (i <= ntok) {
                if (T[i] == "--") { i++; break }
                if (T[i] ~ /^GH_REPO=/) { inl = substr(T[i], 9); i++; continue }
                if (T[i] ~ /^GH_HOST=/) { inlhost = substr(T[i], 9); i++; continue }
                if (T[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
                if (T[i] == "-C" || T[i] == "--chdir") { note_cd(i); i += 2; continue }
                if (T[i] ~ /^--chdir=/) { note_cd_val(substr(T[i], 9)); i++; continue }
                if (T[i] == "-u" || T[i] == "--unset") {
                    if (T[i + 1] == "GH_REPO") inl = ""
                    if (T[i + 1] == "GH_HOST") inlhost = ""
                    i += 2; continue
                }
                if (T[i] ~ /^--unset=/) {
                    if (substr(T[i], 9) == "GH_REPO") inl = ""
                    if (substr(T[i], 9) == "GH_HOST") inlhost = ""
                    i++; continue
                }
                if (substr(T[i], 1, 1) == "-") { i++; continue }
                break
            }
            continue
        }
        # These wrappers carry options of their own ahead of the command.
        # Skipping only the bare word left an option like `time -p` or the
        # `command --` sentinel standing as the command token, so the wrapped
        # write was never reached. Consume the option forms that still run the
        # following command; stop at anything else — `command -v gh` looks gh up
        # and runs nothing, so leaving that unguarded is correct.
        if (T[i] == "command" || T[i] == "builtin" ||
            T[i] == "nohup" || T[i] == "exec" || T[i] == "time") {
            w = T[i]; i++
            while (i <= ntok) {
                if (T[i] == "--") { i++; break }
                if (substr(T[i], 1, 1) != "-") break
                if (w == "time" && T[i] == "-p") { i++; continue }
                if (w == "command" && T[i] == "-p") { i++; continue }
                if (w == "exec" && (T[i] == "-c" || T[i] == "-l")) { i++; continue }
                if (w == "exec" && T[i] == "-a") { i += 2; continue }
                break
            }
            continue
        }
        break
    }
    if (i > ntok) return
    # `export GH_REPO=`/`GH_HOST=` and their `unset` set the variable for every
    # later command in this shell, so their effect carries across segments the
    # way a cd does. The inline `GH_REPO=x gh ...` prefix was captured above and
    # does not reach here.
    if (T[i] == "export") {
        for (j = i + 1; j <= ntok; j++) {
            if (T[j] ~ /^GH_REPO=/) { ghval = substr(T[j], 9); ghset = 1 }
            if (T[j] ~ /^GH_HOST=/) { hostval = substr(T[j], 9); hostset = 1 }
        }
        return
    }
    if (T[i] == "unset") {
        for (j = i + 1; j <= ntok; j++) {
            if (T[j] == "GH_REPO") { ghval = ""; ghset = 0 }
            # An unset host falls to the gh default forge, not the ambient
            # value: mark it set-and-empty so the resolver reads github.com.
            if (T[j] == "GH_HOST") { hostval = ""; hostset = 1 }
        }
        return
    }
    if (T[i] == "cd") { note_cd(i); return }
    # pushd moves the working directory the way cd does. Its stack-rotation
    # forms (no argument, or +N/-N) and popd return to a directory this
    # single-line scan does not track, so they mark the destination unresolvable
    # and an implicit write after one is refused.
    if (T[i] == "pushd") {
        if (i + 1 > ntok || T[i + 1] ~ /^[+-]/) { cdspec = "?"; return }
        note_cd(i); return
    }
    if (T[i] == "popd") { cdspec = "?"; return }
    if (T[i] != "gh" && T[i] !~ /\/gh$/) return
    i++
    # gh reads as `gh <noun> <verb>`: the noun is the first token that is not an
    # option, the verb the one directly after it. Taking the verb by position
    # rather than by searching is what keeps prose from matching.
    noun = ""; verb = ""
    while (i <= ntok) {
        # A split --repo/-R carries its value in the NEXT token. Skip both, or
        # the repository is taken for the noun and the guarded verb never matches.
        if (T[i] == "--repo" || T[i] == "-R") { i += 2; continue }
        if (substr(T[i], 1, 1) == "-") { i++; continue }
        noun = T[i]
        if (i + 1 <= ntok) verb = T[i + 1]
        break
    }
    # gh exposes `issue new` and `pr new` as aliases for create. Fold them to
    # the create spelling so the whitelist below covers the documented aliases.
    if (noun == "issue" && verb == "new") verb = "create"
    if (noun == "pr" && verb == "new") verb = "create"
    key = noun "/" verb
    # Exactly the verbs the ruling names. `gh api` reaches the same endpoints
    # and is deliberately not covered.
    if (key != "issue/create" && key != "issue/comment" &&
        key != "pr/create" && key != "pr/comment" && key != "pr/review") return
    # issue comment, pr comment and pr review take a `<number> | <url>` operand
    # that names the repository directly — gh reads the repo from the URL. The
    # first positional after the verb is captured here; the shell resolves a URL
    # among the operands and refuses off-origin, while a bare number or a branch
    # resolves to nothing and falls through to --repo/GH_REPO/cwd.
    urlop = ""
    if (verb == "comment" || verb == "review") {
        k = i + 2
        while (k <= ntok) {
            if (T[k] == "--repo" || T[k] == "-R" ||
                T[k] == "-b" || T[k] == "--body" ||
                T[k] == "-F" || T[k] == "--body-file") { k += 2; continue }
            if (substr(T[k], 1, 1) == "-") { k++; continue }
            urlop = T[k]; break
        }
    }
    # --repo/-R is the explicit flag target: below a `<url>` operand (resolved
    # first on the shell side for a URL-capable verb) but above GH_REPO and the
    # working directory, matching gh. gh binds a repeated selector to its LAST
    # value (a command-level --repo overrides a global one before the noun), so
    # the scan keeps the last match — an owned --repo ahead of an off-origin one
    # must not shield it.
    repo = ""
    for (j = 1; j <= ntok; j++) {
        if (T[j] ~ /^--repo=/)      { repo = substr(T[j], 8) }
        else if (T[j] ~ /^-R=/)     { repo = substr(T[j], 4) }
        else if (T[j] ~ /^-R./)     { repo = substr(T[j], 3) }  # attached -R<repo>
        else if (T[j] == "--repo" || T[j] == "-R") {
            if (j < ntok) { repo = T[j + 1]; j++ }
        }
    }
    printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", noun, verb, repo, inl, cdspec, ghset, ghval, inlhost, hostset, hostval, urlop
}
function reset(   k) { for (k = 1; k <= ntok; k++) delete T[k]; ntok = 0 }
BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); BT = sprintf("%c", 96) }
{ buf = (NR > 1 ? buf "\n" $0 : $0) }
END {
    n = length(buf); tok = ""; have = 0; ntok = 0; inS = 0; inD = 0; cdspec = ""; cddepth = 0; ghset = 0; ghval = ""; hostset = 0; hostval = ""
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
        # A subshell runs with a copy of the shell state, so a cd or an export of
        # GH_REPO inside ( ) must not leak to a later command. Save on "(",
        # restore on ")".
        if (c == "(") {
            push(); analyze(); reset()
            cddepth++
            cdsave[cddepth] = cdspec
            ghsetsave[cddepth] = ghset
            ghvalsave[cddepth] = ghval
            hostsetsave[cddepth] = hostset
            hostvalsave[cddepth] = hostval
            continue
        }
        if (c == ")") {
            push(); analyze(); reset()
            if (cddepth > 0) {
                cdspec = cdsave[cddepth]
                ghset = ghsetsave[cddepth]
                ghval = ghvalsave[cddepth]
                hostset = hostsetsave[cddepth]
                hostval = hostvalsave[cddepth]
                cddepth--
            }
            continue
        }
        if (c == ";" || c == "|" || c == "&" ||
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
while IFS="$(printf '\037')" read -r _noun _verb _flag _inline _cd _ghset _ghval _inhost _hostset _hostval _urlop; do
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

    # The host gh would use to complete an unqualified owner/name: GH_HOST set
    # inline on the call, else exported earlier on the line (empty when unset,
    # which means gh's default forge), else this process's ambient GH_HOST.
    if [ -n "${_inhost:-}" ]; then
        _eff_host=$_inhost
    elif [ "${_hostset:-0}" = "1" ]; then
        _eff_host=${_hostval:-github.com}
    else
        _eff_host=${GH_HOST:-github.com}
    fi
    [ -n "$_eff_host" ] || _eff_host=github.com

    # A `<url>` operand on issue/pr comment or pr review names the repository
    # itself; gh writes there whatever --repo says, so it is resolved first.
    _url_target=""
    [ -n "${_urlop:-}" ] && _url_target=$(repo_from_url "$_urlop")
    if [ -n "${_url_target:-}" ]; then
        _target=$_url_target
    elif [ -n "${_flag:-}" ]; then
        _target=$(norm_repo "$_flag" "$_eff_host")
    elif [ -n "${_inline:-}" ]; then
        _target=$(norm_repo "$_inline" "$_eff_host")
    elif [ "${_ghset:-0}" = "1" ]; then
        # An export earlier on the line is what gh sees, overriding any ambient
        # GH_REPO. An emptied or unset one leaves no target, so it resolves
        # against the working directory just as gh would.
        if [ -n "${_ghval:-}" ]; then
            _target=$(norm_repo "$_ghval" "$_eff_host")
        else
            _target=$(origin_of "$_base")
        fi
    elif [ -n "${GH_REPO:-}" ]; then
        _target=$(norm_repo "$GH_REPO" "$_eff_host")
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
