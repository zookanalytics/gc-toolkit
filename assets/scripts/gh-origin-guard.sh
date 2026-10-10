#!/bin/sh
# gh-origin-guard.sh — Claude PreToolUse hook: refuse an agent-typed `gh` write
# aimed at a repository this rig does not own, and a post on one it does own
# whose body does not carry the city's provenance mark.
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
# On a repository we own, a post (a comment, a review, a thread reply, or an
# edit of one) has to carry the provenance mark assets/scripts/pr-post.sh
# appends. pr-facts.sh tells the city's own posts from feedback by that mark,
# so an unmarked post under the city's login reads back as feedback and loops
# into rework (docs/gh-origin-guard.md, "Posts carry the city's mark").
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

# The repository gh writes to from directory $1 when the call names none (no
# --repo, no GH_REPO), or nothing when that cannot be established. $2 is the
# forge the call uses: GH_HOST, else github.com.
#
# gh does not read `origin` first (pkg/cmd/factory/default.go and
# context/context.go in gh's source). It ranks the remotes upstream, github,
# origin, then the rest as git lists them. It takes the first of them whose
# `remote.<name>.gh-resolved` git config is set, which is what
# `gh repo set-default` writes: `base` means that remote's repository, and an
# OWNER/REPO value means that repository on the remote's host. With no remote
# marked, and no terminal to ask in, it takes the first remote in that order.
# A remote whose URL names no repository is skipped. Before choosing, gh
# narrows the remotes by forge, using the hosts it is logged in to, or GH_HOST
# alone when that is set.
# That is gh's own configuration, which this guard does not read, so it chooses
# twice, among every remote and among the remotes on the forge the call uses,
# and answers only when the two choices agree.
wd_repo() {
    { [ -n "${1:-}" ] && [ -d "$1" ]; } || return 0
    _wr_rv=$(git -C "$1" remote -v 2>/dev/null) || return 0
    _wr_rs=$(git -C "$1" config --get-regexp '^remote\..*\.gh-resolved$' 2>/dev/null)
    # Exit 1 means no remote is marked. Any other failure stops gh as well.
    case $? in 0|1) : ;; *) return 0 ;; esac
    _wr=$(printf '%s\n\036\n%s\n' "$_wr_rv" "$_wr_rs" \
        | awk -v forge="$(printf '%s' "${2:-}" | tr 'A-Z' 'a-z')" '
# gh reads a remote URL with ParseURL (git/url.go) and FromURL
# (internal/ghrepo). This returns the repository as host/owner/name, empty when
# gh reads no repository from the URL and skips the remote, or "?" when this
# reading cannot be sure what gh reads. It does not follow the characters Go
# treats specially or rejects in a URL, such as escapes, a query, a fragment,
# brackets or spaces, nor a port that is not a number.
function ghurl(u,   rest, auth, path, p, seg, name) {
    if (u !~ /^[A-Za-z0-9._~:\/@+-]+$/) return "?"
    # gh reads an scp-style host:path as ssh://host/path.
    if (u !~ /^(ssh|git\+ssh|git|http|git\+https|https|ftp|ftps|file):/ && index(u, ":") > 0) {
        sub(/:/, "/", u); u = "ssh://" u
    }
    if (substr(u, 1, 2) == "//") return "?"
    # With no scheme and authority, the URL is a local path and names no host.
    if (!match(u, /^[A-Za-z][A-Za-z0-9+.-]*:\/\//)) return ""
    rest = substr(u, RLENGTH + 1)
    p = index(rest, "/")
    if (p) { auth = substr(rest, 1, p - 1); path = substr(rest, p + 1) }
    else { auth = rest; path = "" }
    while ((p = index(auth, "@")) > 0) auth = substr(auth, p + 1)
    if ((p = index(auth, ":")) > 0) {
        if (substr(auth, p + 1) !~ /^[0-9]*$/) return "?"
        auth = substr(auth, 1, p - 1)
    }
    if (auth == "") return ""
    auth = tolower(auth); sub(/^www\./, "", auth)
    sub(/^\/+/, "", path); sub(/\/+$/, "", path)
    if (split(path, seg, "/") != 2) return ""
    name = seg[2]; sub(/\.git$/, "", name)
    return auth "/" seg[1] "/" name
}
# The owner/name a gh-resolved value names (repository.ParseWithHost in
# go-gh): a URL, or OWNER/REPO with an optional HOST/ ahead of it. "?" when gh
# cannot read one, which stops the call.
function fullname(v,   n, f, r) {
    if (v ~ /^git@/ || v ~ /^(ssh|git\+ssh|git|http|git\+https|https):/) {
        r = ghurl(v)
        if (r == "" || r == "?") return "?"
        sub(/^[^\/]*\//, "", r)
        return r
    }
    n = split(v, f, "/")
    if (n == 2 && f[1] != "" && f[2] != "") return f[1] "/" f[2]
    if (n == 3 && f[1] != "" && f[2] != "" && f[3] != "") return f[2] "/" f[3]
    return "?"
}
function rank(nm) {
    nm = tolower(nm)
    return nm == "upstream" ? 3 : nm == "github" ? 2 : nm == "origin" ? 1 : 0
}
# The repository gh chooses among the remotes L[1..m], which stand in the
# order gh sorts them.
function choose(m, L,   k, i, v) {
    for (k = 1; k <= m; k++) {
        i = L[k]
        if (RES[i] == "") continue
        if (REPO[i] == "?") return "?"
        if (RES[i] == "base") return REPO[i]
        v = fullname(RES[i])
        return (v == "?") ? "?" : (HOST[i] "/" v)
    }
    return (m > 0) ? REPO[L[1]] : ""
}
$0 == "\036" { sect = 2; next }
sect != 2 {
    # git remote -v: <name> TAB <url> (fetch|push), grouped by remote.
    t = index($0, "\t")
    if (t == 0) next
    nm = substr($0, 1, t - 1); rest = substr($0, t + 1)
    if (!match(rest, /[ \t]+\((fetch|push)\)/)) next
    url = substr(rest, 1, RSTART - 1); kind = substr(rest, RSTART, RLENGTH)
    if (nr == 0 || NAME[nr] != nm) { nr++; NAME[nr] = nm }
    if (kind ~ /fetch/) FETCH[nr] = url; else PUSH[nr] = url
    next
}
{
    # remote.<name>.gh-resolved <value>. gh takes <name> to be the text between
    # the first two dots of the key, and the last line for a name wins.
    sp = index($0, " ")
    if (sp == 0) next
    key = substr($0, 1, sp - 1)
    d = index(key, ".")
    if (d == 0) next
    key = substr(key, d + 1)
    d = index(key, ".")
    if (d) key = substr(key, 1, d - 1)
    RESOLVED[key] = substr($0, sp + 1)
}
END {
    # gh sorts the remotes by rank. Go keeps the listed order among equal
    # ranks when a sort covers twelve remotes or fewer, and can reorder them
    # beyond that.
    if (nr > 12) exit
    for (i = 1; i <= nr; i++) {
        r = (i in FETCH) ? ghurl(FETCH[i]) : ""
        if (r == "" && (i in PUSH)) r = ghurl(PUSH[i])
        if (r == "") continue
        REPO[i] = r
        HOST[i] = (r == "?") ? "?" : substr(r, 1, index(r, "/") - 1)
        RES[i] = (NAME[i] in RESOLVED) ? RESOLVED[NAME[i]] : ""
    }
    na = 0; ne = 0
    for (s = 3; s >= 0; s--)
        for (i = 1; i <= nr; i++) {
            if (!(i in REPO) || rank(NAME[i]) != s) continue
            ALL[++na] = i
            if (HOST[i] == forge) ONF[++ne] = i
        }
    pa = choose(na, ALL); pe = choose(ne, ONF)
    if (pa == "" || pa == "?" || tolower(pa) != tolower(pe)) exit
    print pa
}' 2>/dev/null)
    [ -n "$_wr" ] || return 0
    norm_repo "$_wr"
}

# Resolve the repository a `gh api` endpoint writes to. gh reads the repository
# straight from the endpoint path, so this is the api analogue of repo_from_url.
# The endpoint is a REST path (`repos/OWNER/REPO/...`), a leading-slash path, or
# a full URL; $2 is the host gh would use for a relative path, and $3 is the
# host/owner/name that fills the owner and repo placeholders, or empty when none
# resolves.
# Prints one of:
#   host/owner/repo   a repos/OWNER/REPO path — the resolved target
#   @malformed        a repos/ path with no concrete owner and name, including a
#                     placeholder left unfilled — unresolvable, refused the way an
#                     unresolved porcelain target is
#   @nonrepos         any other endpoint; it names no repository and is left alone
# An api URL carries the api host (api.github.com, or HOST/api/v3 for an
# enterprise forge); both are mapped back to the forge host that a remote names,
# so the comparison is against the same identity origin_of produces.
api_endpoint_target() { # api_endpoint_target <endpoint> <effective-host> <fill-repo>
    # gh fills {owner} and {repo} across the whole endpoint before it reads a host
    # or a path from it, and takes only the owner and the name of the repository
    # it fills from. It fills the older :owner and :repo spellings the same way
    # wherever no letter, digit or underscore follows them. Filling first and
    # resolving the result the way a concrete endpoint resolves keeps the
    # endpoint's own host, and any concrete owner or name standing beside a
    # placeholder. The fill values come out of norm_repo, so they carry nothing
    # sed would read as syntax.
    _ep=${1:-}
    _fown=$(printf '%s' "${3:-}" | cut -d/ -f2)
    _fname=$(printf '%s' "${3:-}" | cut -d/ -f3)
    if [ -n "$_fown" ] && [ -n "$_fname" ]; then
        _ep=$(printf '%s' "$_ep" | sed \
            -e "s#{owner}#$_fown#g" -e "s#{repo}#$_fname#g" \
            -e "s#:owner\([^0-9A-Za-z_]\)#$_fown\1#g" -e "s#:owner\$#$_fown#" \
            -e "s#:repo\([^0-9A-Za-z_]\)#$_fname\1#g" -e "s#:repo\$#$_fname#")
    fi
    _ep=$(printf '%s' "$_ep" | tr -d '[:space:]')
    [ -n "$_ep" ] || { printf '@nonrepos'; return 0; }
    case "$_ep" in
        *://*)
            _rest=${_ep#*://}
            _host=$(printf '%s' "${_rest%%/*}" | tr 'A-Z' 'a-z')
            _path=${_rest#*/}
            [ "$_path" = "$_rest" ] && _path=""
            case "$_host" in api.github.com) _host=github.com ;; esac
            case "$_path" in api/v3/*) _path=${_path#api/v3/} ;; esac
            ;;
        *)
            _path=${_ep#/}
            _host=$(printf '%s' "${2:-github.com}" | tr 'A-Z' 'a-z')
            ;;
    esac
    _path=${_path%%\?*}
    case "$_path" in
        repos/*) : ;;
        *) printf '@nonrepos'; return 0 ;;
    esac
    _owner=$(printf '%s' "$_path" | cut -d/ -f2)
    _name=$(printf '%s' "$_path" | cut -d/ -f3)
    { [ -n "$_owner" ] && [ -n "$_name" ]; } || { printf '@malformed'; return 0; }
    _t=$(norm_repo "$_host/$_owner/$_name")
    [ -n "$_t" ] && printf '%s' "$_t" || printf '@malformed'
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
# Emits one line per guarded write, fields separated by \037, in the order the
# verdict loop reads them: noun, verb, --repo value, inline GH_REPO value, the
# pending cd destination, whether an earlier export/unset set GH_REPO in this
# shell (1/0), that exported value, the inline GH_HOST value, whether an earlier
# export/unset set GH_HOST (1/0), that exported value, the positional operand of
# a URL-capable verb (issue/pr comment, pr review), the api endpoint, whether
# the write posts, a review event, whether its body is written in an editor or
# a browser, the body, its body files, whether it stands in a here-document
# body, and a gh api call's --hostname. A unit separator rather than a tab,
# because the shell collapses runs of whitespace separators and an empty field
# would shift the next one into its place. The shell resolves origins; awk only
# lexes.
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
# gh parses a single-dash token as a run of shorthand flags. A boolean takes one
# letter and the run goes on, so `-iX POST` sets the method and `-iftitle=x` adds
# a field exactly as `-i -X POST` and `-i -f title=x` do. The first letter in
# vals, the shorthands that take a value, ends the run: its value is the rest of
# the token after an optional "=", or else the next token. Sets sflag to that
# letter, or "" when the run holds none, and sval to its value, and returns how
# many tokens the run used.
function shortrun(t, nxt, vals,   s, c) {
    sflag = ""; sval = ""
    s = substr(t, 2)
    while (s != "") {
        c = substr(s, 1, 1); s = substr(s, 2)
        if (index(vals, c) == 0) { if (substr(s, 1, 1) == "=") return 1; continue }
        sflag = c
        if (s ~ /^=./) { sval = substr(s, 2); return 1 }
        if (s != "") { sval = s; return 1 }
        sval = nxt
        return 2
    }
    return 1
}
# The body of a post travels on the scan line, so the characters that frame
# the line and its fields become spaces. The provenance mark is one line of
# plain text, so flattening never hides it or forges it.
function flat(s) { gsub("\n", " ", s); gsub("\036", " ", s); gsub("\037", " ", s); return s }
# One `gh api` field, given as key=value. A typed field (-F/--field) whose value
# starts with @ reads that file. The last body= wins, the way gh builds its
# request, and every value is kept for a GraphQL call, whose body rides in a
# variable of any name.
function apifield(typed, kv,   eq, k, v) {
    eq = index(kv, "=")
    if (eq == 0) return
    k = substr(kv, 1, eq - 1); v = substr(kv, eq + 1)
    if (typed && substr(v, 1, 1) == "@") {
        allfiles = allfiles "\036" substr(v, 2)
        if (k == "body") { abody = ""; afile = substr(v, 2) }
        return
    }
    allvals = allvals " " flat(v)
    if (k == "body") { abody = flat(v); afile = "" }
}
# The body of a porcelain comment or review, read from its flags the way gh
# reads them: -b/--body text, -F/--body-file path, the last one given winning.
# Sets pbody, pfile, pevent (approve or request-changes, which the city never
# posts) and pinter (an editor or browser body, which no scan can read), and
# clears ppost for --delete-last, which posts nothing.
function porcelain_post(from,   k, t, s, c, v) {
    ppost = 1; pbody = ""; pfile = ""; pevent = ""; pinter = 0
    k = from
    while (k <= ntok) {
        t = T[k]
        if (t == "--repo" || t == "-R" || t == "--attach") { k += 2; continue }
        if (t == "--body") { pbody = flat(T[k + 1]); pfile = ""; k += 2; continue }
        if (t ~ /^--body=/) { pbody = flat(substr(t, 8)); pfile = ""; k++; continue }
        if (t == "--body-file") { pfile = T[k + 1]; pbody = ""; k += 2; continue }
        if (t ~ /^--body-file=/) { pfile = substr(t, 13); pbody = ""; k++; continue }
        if (t == "--approve") { pevent = "approve"; k++; continue }
        if (t == "--request-changes") { pevent = "request-changes"; k++; continue }
        if (t == "--editor" || t == "--web") { pinter = 1; k++; continue }
        if (t == "--delete-last") { ppost = 0; k++; continue }
        if (substr(t, 1, 2) == "--") { k++; continue }
        if (t ~ /^-./) {
            # A shorthand run: -a, -r, -e and -w are booleans; -b, -F and -R take
            # the rest of the token after an optional "=", or else the next token.
            s = substr(t, 2)
            while (s != "") {
                c = substr(s, 1, 1); s = substr(s, 2)
                if (c == "a") { pevent = "approve"; continue }
                if (c == "r") { pevent = "request-changes"; continue }
                if (c == "e" || c == "w") { pinter = 1; continue }
                if (c == "b" || c == "F" || c == "R") {
                    if (substr(s, 1, 1) == "=") s = substr(s, 2)
                    if (s != "") v = s
                    else { v = T[k + 1]; k++ }
                    if (c == "b") { pbody = flat(v); pfile = "" }
                    if (c == "F") { pfile = v; pbody = "" }
                    s = ""
                }
            }
            k++; continue
        }
        k++
    }
}
function analyze(   i, j, k, w, noun, verb, key, repo, inl, inlhost, urlop, method, haveparams, endpoint, apihost, p, q, t, M, ep, postmut, apost, afiles) {
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
    # `gh api` reaches the same REST write endpoints the porcelain verbs do, so
    # it is guarded too. The method is explicit via -X/--method, else POST when a
    # field or body is added (-f/-F/--field/--raw-field/--input) and GET
    # otherwise, the way gh resolves it. Only a writing method is guarded; the
    # target is the endpoint, read by the shell verdict. graphql and a
    # methodless/endpointless call are left alone — the first because its
    # repository lives in the query, the second because gh rejects it.
    if (noun == "api") {
        method = ""; haveparams = 0; endpoint = ""; apihost = ""
        abody = ""; afile = ""; allvals = ""; allfiles = ""; ainput = ""
        p = i + 1
        while (p <= ntok) {
            t = T[p]
            if (t == "--method") { if (p < ntok) method = T[p + 1]; p += 2; continue }
            if (t ~ /^--method=/) { method = substr(t, 10); p++; continue }
            if (t == "--hostname") { if (p < ntok) apihost = T[p + 1]; p += 2; continue }
            if (t ~ /^--hostname=/) { apihost = substr(t, 12); p++; continue }
            if (t == "--raw-field" || t == "--field") { haveparams = 1; apifield(t == "--field", T[p + 1]); p += 2; continue }
            if (t ~ /^--raw-field=/) { haveparams = 1; apifield(0, substr(t, 13)); p++; continue }
            if (t ~ /^--field=/) { haveparams = 1; apifield(1, substr(t, 9)); p++; continue }
            if (t == "--input") { haveparams = 1; ainput = T[p + 1]; p += 2; continue }
            if (t ~ /^--input=/) { haveparams = 1; ainput = substr(t, 9); p++; continue }
            if (t == "--header" || t == "--jq" || t == "--template" ||
                t == "--cache" || t == "--preview") { p += 2; continue }
            if (substr(t, 1, 2) == "--") { p++; continue }
            # -X carries the method, -f and -F a field, and -H, -q, -t and -p a
            # value the verdict does not need; -i is the one boolean.
            if (t ~ /^-./) {
                p += shortrun(t, (p < ntok ? T[p + 1] : ""), "XfFHqtp")
                if (sflag == "X") method = sval
                if (sflag == "f" || sflag == "F") { haveparams = 1; apifield(sflag == "F", sval) }
                continue
            }
            if (endpoint == "") endpoint = t
            p++
        }
        M = toupper(method)
        if (M == "") { if (haveparams) M = "POST"; else M = "GET" }
        if (M != "POST" && M != "PATCH" && M != "PUT" && M != "DELETE") return
        if (endpoint == "") return
        ep = tolower(endpoint)
        if (ainput != "") allfiles = allfiles "\036" ainput
        if (ep == "graphql" || ep ~ /\/graphql$/ || ep ~ /^graphql\?/ || ep ~ /\/graphql\?/) {
            # A GraphQL call names no repository the origin rule can measure, so
            # only a mutation that posts or edits a comment or review is emitted,
            # for its provenance alone. Its body rides in a variable of any
            # name, so every field value is read.
            postmut = 0
            for (q = i + 1; q <= ntok; q++) if (T[q] ~ POSTMUT) postmut = 1
            if (!postmut) return
            printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", noun, "graphql", "", inl, cdspec, ghset, ghval, inlhost, hostset, hostval, "", endpoint, 1, "", 0, allvals, allfiles, inbody, ""
            return
        }
        verb = M; repo = ""; urlop = ""
        # A write to a comment, reply or review endpoint is a post. A dismissal,
        # a reaction and a reviewer re-request carry no body, and a DELETE posts
        # nothing.
        apost = 0
        if (M != "DELETE" && (ep ~ /(^|\/)repos\/[^\/]+\/[^\/]+\/(issues|pulls)\/([^\/?]+\/)?comments(\/|\?|$)/ ||
                              ep ~ /(^|\/)repos\/[^\/]+\/[^\/]+\/pulls\/[^\/?]+\/reviews(\/|\?|$)/) &&
            ep !~ /\/(dismissals|reactions|requested_reviewers)(\/|\?|$)/) apost = 1
        afiles = ""
        if (afile != "") afiles = "\036" afile
        if (ainput != "") afiles = afiles "\036" ainput
        printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", noun, verb, repo, inl, cdspec, ghset, ghval, inlhost, hostset, hostval, urlop, endpoint, apost, "", 0, abody, afiles, inbody, apihost
        return
    }
    # Exactly the verbs the ruling names, for the porcelain path.
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
    # issue comment, pr comment and pr review post a body on the conversation or
    # the review; the two creates post nothing pr-facts reads as feedback.
    ppost = 0; pbody = ""; pfile = ""; pevent = ""; pinter = 0
    if (verb == "comment" || verb == "review") porcelain_post(i + 2)
    printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", noun, verb, repo, inl, cdspec, ghset, ghval, inlhost, hostset, hostval, urlop, endpoint, ppost, pevent, pinter, pbody, (pfile != "" ? "\036" pfile : ""), inbody, ""
}
function reset(   k) { for (k = 1; k <= ntok; k++) delete T[k]; ntok = 0 }
# Mark the lines of every here-document body, its terminator included, in BODY.
# An opener counts only outside quotes, as the shell reads it; `<<<` is a
# here-string and opens none. The bodies queued on one line follow it in order,
# each up to the line that equals its delimiter, leading tabs dropped for <<-.
function hd_mark(   x, c, q, r, d, tk, ln, k, e, line, t) {
    q = ""; ln = 1; HQ = 0; x = 1
    while (x <= n) {
        c = substr(buf, x, 1)
        if (q == SQ) { if (c == SQ) q = ""; if (c == "\n") ln++; x++; continue }
        if (c == "\\") { if (substr(buf, x + 1, 1) == "\n") ln++; x += 2; continue }
        if (q == DQ) { if (c == DQ) q = ""; if (c == "\n") ln++; x++; continue }
        if (c == SQ || c == DQ) { q = c; x++; continue }
        if (c == "<" && substr(buf, x + 1, 1) == "<") {
            if (substr(buf, x + 2, 1) == "<") { x += 3; continue }
            r = substr(buf, x + 2); d = 0
            if (substr(r, 1, 1) == "-") { d = 1; r = substr(r, 2) }
            sub(/^[ \t]+/, "", r)
            if (match(r, /^[^ \t\n<>;&|()]+/) > 0) {
                tk = substr(r, 1, RLENGTH)
                gsub(SQ, "", tk); gsub(DQ, "", tk); gsub(/\\/, "", tk)
                HQ++; HQT[HQ] = tk; HQD[HQ] = d
            }
            x += 2; continue
        }
        if (c == "\n") {
            ln++; x++
            for (k = 1; k <= HQ; k++) {
                while (x <= n) {
                    e = index(substr(buf, x), "\n")
                    if (e == 0) { line = substr(buf, x); x = n + 1 }
                    else { line = substr(buf, x, e - 1); x += e }
                    BODY[ln] = 1
                    t = line
                    if (HQD[k]) sub(/^\t+/, "", t)
                    ln++
                    if (t == HQT[k]) break
                }
            }
            HQ = 0
            continue
        }
        x++
    }
}
BEGIN {
    SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); BT = sprintf("%c", 96)
    # The GraphQL mutations that post or edit a comment or review body, called
    # with their arguments.
    POSTMUT = "(addComment|addPullRequestReview[A-Za-z]*|submitPullRequestReview|updateIssueComment|updatePullRequestReview[A-Za-z]*)[ \t]*[(]"
}
{ buf = (NR > 1 ? buf "\n" $0 : $0) }
END {
    n = length(buf); tok = ""; have = 0; ntok = 0; inS = 0; inD = 0; cdspec = ""; cddepth = 0; ghset = 0; ghval = ""; hostset = 0; hostval = ""
    # A here-document body is lexed like any other line, so the origin rule
    # still reads a body fed to a shell, but each command found in one is
    # flagged (inbody): a body is far more often text being written than
    # commands being run. Quote state starts fresh at each side of a body, so a
    # quote inside one cannot swallow the commands after it.
    hd_mark()
    ln = 1; inbody = 0
    for (i = 1; i <= n; i++) {
        if (i > 1 && substr(buf, i - 1, 1) == "\n") {
            ln++
            if ((ln in BODY) != inbody) {
                push(); analyze(); reset()
                inS = 0; inD = 0; inbody = (ln in BODY)
            }
        }
        c = substr(buf, i, 1)
        if (inS) { if (c == SQ) inS = 0; else { tok = tok c; have = 1 } ; continue }
        if (inD) {
            if (c == DQ) { inD = 0; continue }
            if (c == "\\" && i < n) { i++; tok = tok substr(buf, i, 1); have = 1; continue }
            tok = tok c; have = 1; continue
        }
        if (c == SQ) { inS = 1; have = 1; continue }
        if (c == DQ) { inD = 1; have = 1; continue }
        if (c == "\\" && i < n) {
            i++
            # A backslash-newline is a line continuation Bash removes entirely;
            # keeping the newline would hide a noun or verb split across lines.
            if (substr(buf, i, 1) == "\n") continue
            tok = tok substr(buf, i, 1); have = 1; continue
        }
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

# --- provenance ----------------------------------------------------------

# The city posts on a pull request under the same login an operator's review
# tools can use, so pr-facts.sh tells the city's own post from feedback by the
# provenance mark pr-post.sh appends, never by the author. A post on a
# repository we own passes the origin rule and is then held to the mark: its
# body, inline or in a file this guard can read, has to carry it. What counts as
# the mark is pr-post.sh's own definition, read from beside this script.
GUARD_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
PR_POST="$GUARD_DIR/pr-post.sh"
CITY_DEF=""

city_marked() { # city_marked <text> — 0 when the text carries the city's mark
    [ -n "$CITY_DEF" ] || return 1
    printf '%s' "$1" | jq -Rs "$CITY_DEF"'{body: .} | gc_city_marked' 2>/dev/null | grep -qx true
}

# post_refusal <event> <interactive> <body> <files> <base> — prints why a post
# cannot be shown to carry the mark, or nothing when it can. <event> is a
# review's approve or request-changes, graphql for a GraphQL mutation, or empty.
# <files> are the body files the call reads, each led by \036; a relative one
# resolves against <base>.
post_refusal() {
    case "$1" in
        approve|request-changes)
            echo "the city never approves or requests changes on a pull request; it posts COMMENT reviews only"
            return 0 ;;
    esac
    if [ "$2" = "1" ]; then
        echo "a body written in an editor or a browser cannot be read here, so its mark cannot be shown"
        return 0
    fi
    if [ -z "$CITY_DEF" ]; then
        [ -x "$PR_POST" ] && CITY_DEF=$("$PR_POST" own-def 2>/dev/null)
        if [ -z "$CITY_DEF" ]; then
            echo "pr-post.sh, beside this guard, did not print its provenance definition, so no body can be shown to carry the mark"
            return 0
        fi
    fi
    city_marked "$3" && return 0
    _pr_ifs=$IFS
    IFS=$(printf '\036')
    set -f
    for _pf in $4; do
        case "$_pf" in
            ''|-) continue ;;
            \~/*) _pf="$HOME/${_pf#??}" ;;
            /*) : ;;
            *) [ -n "$5" ] || continue; _pf="$5/$_pf" ;;
        esac
        if [ -f "$_pf" ] && [ -r "$_pf" ] && city_marked "$(cat -- "$_pf" 2>/dev/null)"; then
            set +f; IFS=$_pr_ifs
            return 0
        fi
    done
    set +f; IFS=$_pr_ifs
    # A GraphQL body is every field value, the query among them, whose own
    # $variables are not the shell's.
    if [ "$1" = "graphql" ]; then
        echo "none of its fields carries a city mark this guard can read"
        return 0
    fi
    case "$3" in
        *'$'*|*'`'*) echo "its body is built by the shell as the command runs, so this guard cannot read a mark in it" ;;
        *[![:space:]]*) echo "its body carries no city mark" ;;
        *) [ -n "$4" ] && echo "its body file carries no city mark, or cannot be read here (standard input cannot)" \
               || echo "it gives no body this guard can read" ;;
    esac
}

# Every guarded write on the command line is judged, not only the first: a
# legitimate write chained ahead of an off-origin one must not shield it.
ALLOWED=$(allowed_origins)
OWNED=$(printf '%s' "$ALLOWED" | paste -sd, - 2>/dev/null)

NOUN=""; VERB=""; TARGET=""; REFUSE=""; UNMARKED=""; FROM_WD=""
while IFS="$(printf '\037')" read -r _noun _verb _flag _inline _cd _ghset _ghval _inhost _hostset _hostval _urlop _endpoint _post _event _inter _body _files _hd _apihost; do
    [ -n "${_noun:-}" ] || continue
    _wd=""

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

    # The forge the call uses: GH_HOST set inline on it, else exported earlier
    # on the line (empty when unset, which means gh's default forge), else this
    # process's ambient GH_HOST. gh completes an unqualified owner/name with
    # it, and narrows the working directory's remotes to it. A gh api call's
    # --hostname sends that call to another forge, and the remotes are still
    # narrowed by GH_HOST alone.
    if [ -n "${_inhost:-}" ]; then
        _forge=$_inhost
    elif [ "${_hostset:-0}" = "1" ]; then
        _forge=${_hostval:-github.com}
    else
        _forge=${GH_HOST:-github.com}
    fi
    [ -n "$_forge" ] || _forge=github.com
    _eff_host=${_apihost:-$_forge}

    # `gh api` names its repository in the endpoint, not in --repo, so it is
    # resolved on its own terms. An endpoint that names no repository is left
    # alone, and a repos path with no concrete owner and name resolves to
    # nothing and is refused. The owner and repo placeholders are filled from
    # GH_REPO, else from the repository gh picks from the working directory's
    # remotes, in the order gh consults the two.
    # A GraphQL mutation names no repository to measure; only its provenance is.
    # A post found in a here-document body is not held to the mark (inbody,
    # above); the origin rule below still reads it.
    if [ "$_noun" = "api" ] && [ "$_verb" = "graphql" ]; then
        [ "${_hd:-0}" = "1" ] && continue
        _why=$(post_refusal graphql 0 "${_body:-}" "${_files:-}" "$_base")
        if [ -n "$_why" ]; then
            NOUN=api; VERB=graphql; TARGET=""; UNMARKED=$_why
            break
        fi
        continue
    fi

    if [ "$_noun" = "api" ]; then
        _fill=""
        case "${_endpoint:-}" in
            *'{owner}'*|*'{repo}'*|*':owner'*|*':repo'*)
                if [ -n "${_inline:-}" ]; then
                    _fill=$(norm_repo "$_inline" "$_eff_host")
                elif [ "${_ghset:-0}" = "1" ] && [ -n "${_ghval:-}" ]; then
                    _fill=$(norm_repo "$_ghval" "$_eff_host")
                elif [ "${_ghset:-0}" = "1" ]; then
                    _fill=$(wd_repo "$_base" "$_forge"); _wd=1
                elif [ -n "${GH_REPO:-}" ]; then
                    _fill=$(norm_repo "$GH_REPO" "$_eff_host")
                else
                    _fill=$(wd_repo "$_base" "$_forge"); _wd=1
                fi ;;
        esac
        _api=$(api_endpoint_target "${_endpoint:-}" "$_eff_host" "$_fill")
        case "$_api" in
            @nonrepos) continue ;;
            @malformed) _target="" ;;
            *) _target=$_api ;;
        esac
    else
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
                _target=$(wd_repo "$_base" "$_forge"); _wd=1
            fi
        elif [ -n "${GH_REPO:-}" ]; then
            _target=$(norm_repo "$GH_REPO" "$_eff_host")
        else
            # No explicit target: gh picks a repository from the working
            # directory's remotes, so the guard resolves the same way rather
            # than waving the call through.
            _target=$(wd_repo "$_base" "$_forge"); _wd=1
        fi
    fi

    if [ -n "${ALLOWED:-}" ] && [ -n "${_target:-}" ] \
       && printf '%s\n' "$ALLOWED" | grep -Fxq "$_target"; then
        if [ "${_post:-0}" = "1" ] && [ "${_hd:-0}" != "1" ]; then
            _why=$(post_refusal "${_event:-}" "${_inter:-0}" "${_body:-}" "${_files:-}" "$_base")
            if [ -n "$_why" ]; then
                NOUN=$_noun; VERB=$_verb; TARGET=$_target; UNMARKED=$_why
                break
            fi
        fi
        continue
    fi

    NOUN=$_noun; VERB=$_verb; TARGET=${_target:-}; REFUSE=1; FROM_WD=$_wd
    break
done <<SCANLINES
$SCAN
SCANLINES

if [ -n "$UNMARKED" ]; then
    deny "gh-origin-guard: refused \`gh $NOUN $VERB\`${TARGET:+ on $TARGET}: $UNMARKED.

The city posts on a pull request under the same login an operator's review
tools can use, so pr-facts.sh tells the city's own posts from feedback by the
provenance mark, not by the author. A post without the mark reads back as
feedback, and the reconcile routes it into a rework child that answers the
city's own words.

Post through $PR_POST, which appends the mark:
  comment --repo <host/owner/name> --pr <n> --body-file <path>
  reply   --host <host> --thread <thread node id> --body-file <path>
  review  --repo <host/owner/name> --pr <n> --body-file <path>
  edit    --repo <host/owner/name> --comment <id> --body-file <path>
A body that already carries <!-- gc:city --> may be posted as it is."
fi

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

if [ -z "${TARGET:-}" ] && [ "$NOUN" = "api" ]; then
    deny "gh-origin-guard: refused \`gh api $VERB\`.

This call writes, but its endpoint names no repository that resolves: a
\`repos/OWNER/REPO\` path carries no concrete owner and name, or an \`{owner}\` or
\`{repo}\` placeholder had nothing to fill it: no GH_REPO is set, and the
working directory's remotes do not settle which repository gh would fill it
from. The repositories this session may write to are: $OWNED.

Name the repository in the endpoint (\`repos/OWNER/REPO/...\`), or hand the
operator the exact command. Bead $PREPARE_PATH_BEAD carries that path."
fi

if [ -z "${TARGET:-}" ]; then
    deny "gh-origin-guard: refused \`gh $NOUN $VERB\`.

No target repository could be resolved for this call: it names no --repo, and
the working directory's remotes do not settle which repository gh would write
to. The repositories this session may write to are: $OWNED.

Name the repository explicitly with \`--repo\` if the write belongs to one of
those. Bead $PREPARE_PATH_BEAD carries the path for a write that belongs
somewhere else."
fi

WD_NOTE=""
[ -n "$FROM_WD" ] && WD_NOTE="
This call leaves the repository to gh, which picks one from the working
directory's remotes. It takes the remote \`gh repo set-default\` marked, and
otherwise the first of upstream, github and origin, then the rest. If the write
belongs to one of ours, name that repository explicitly.
"

deny "gh-origin-guard: refused \`gh $NOUN $VERB\` aimed at $TARGET.

That repository is not ours. This session may write to: $OWNED.
${WD_NOTE}
Opening an issue or a PR, or leaving a comment, on anyone else's repository
spends their attention, and the operator holds that decision — an agent does not
make it on their behalf.

Instead of sending: prepare the exact command and file it for the operator to
run, which is the path bead $PREPARE_PATH_BEAD carries. If the operator has
already approved this specific send, they run it themselves.

Reads are unaffected: \`gh issue view\`, \`gh pr view\`, \`gh search\` and the
rest reach $TARGET normally."
