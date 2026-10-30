#!/usr/bin/env bash
# upstream-finding.sh — prepare an outbound GitHub write; never send it.
# A repo outside the rig's own origin is someone else's time to spend, so the
# send is the operator's (docs/outbound-sends.md). An agent that wants one runs
# the intended `gh` command through this script instead of running it: the
# command is parked verbatim on a bead as `gh_command`, ready to paste, and a
# visit asks a human for the send.
#   upstream-finding.sh --message <why this send is warranted>
#                       [--security-policy <the target's policy, as read>]
#                       [--key <situation-key>] [--pool <converse pool>]
#                       -- gh <verb> --repo <owner/name> [args...]
# A finding the target's security policy asks to receive privately is parked
# as GitHub's private vulnerability report instead:
#                       -- gh api --method POST
#                          repos/<owner/name>/security-advisories/reports
#                          -f summary=<one line> -f description=<the report>
# This script contacts nothing. It runs no `gh`, and it is not a send path a
# guard can be talked through.
# Exit: 0 parked, already parked or already answered · 1 could not file or
# verify · 2 usage, including a command this path cannot make pasteable, or a
# re-run whose command or reading differs from the send its key already parked.
set -uo pipefail

PROG="upstream-finding"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESCALATE="${GC_ESCALATE_TOOL:-$HERE/escalate.sh}"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: upstream-finding.sh --message <why this send is warranted>
                           [--security-policy <the target's policy, as read>]
                           [--key <situation-key>] [--pool <converse pool>]
                           -- gh <verb> --repo <owner/name> [args...]
       upstream-finding.sh --message <why this send is warranted> [...]
                           -- gh api --method POST
                              repos/<owner/name>/security-advisories/reports
                              -f summary=<one line> -f description=<the report>

  --message  what the operator is being asked to approve, in their terms: what
             was found, where it was hit, why it is worth someone else's time.
             The `gh` body is written for the upstream maintainer and does not
             answer this (required)
  --security-policy
             the target's security policy as you read it, and why it lets this
             report be public: where the policy is or that there is none, and
             whether this finding falls under it. A public send publishes its
             text the moment it is pasted, so every send but a private
             vulnerability report requires it
  --key      names the SITUATION: one bead per key, so a re-run of the same
             finding refreshes rather than files again. A re-run with another
             command or security-policy reading is refused: neither the bead
             nor its visit changes in place. [A-Za-z0-9._-] only.
             Default: target repo, verb and a digest of the command
  --pool     converse pool the visit routes to; passed through to escalate.sh,
             which owns the default and the route check
  --         everything after it is the command, verbatim. It must name its
             target with `--repo <owner/name>`, or a private vulnerability
             report in its endpoint path: the operator pastes it in their own
             shell, where an implicit repo resolves somewhere else
U
}

warn() { echo "$PROG: $*" >&2; }

MESSAGE=""; POLICY=""; KEY=""; POOL_ARG=""; CMD=()
while [ $# -gt 0 ]; do
  case "$1" in
    --message) MESSAGE="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --security-policy) POLICY="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --key)     KEY="${2:-}";     shift 2 || { usage; exit 2; } ;;
    --pool)    POOL_ARG="${2:-}"; shift 2 || { usage; exit 2; } ;;
    -h|--help) usage; exit 2 ;;
    --)        shift; CMD=("$@"); break ;;
    *) warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done

[ -n "$MESSAGE" ] || { warn "--message is required"; usage; exit 2; }
[ "${#CMD[@]}" -gt 0 ] || { warn "no command after --"; usage; exit 2; }
case "$(basename -- "${CMD[0]}")" in
  gh) : ;;
  *)
    # One argument carrying spaces is a command that was quoted as a string.
    # It cannot be parked: the parts are already fused, so nothing here can
    # tell an argument boundary from a space inside a body.
    if [ "${#CMD[@]}" = 1 ]; then
      case "${CMD[0]}" in
        *[[:space:]]*) warn "pass the command as separate arguments after --, not as one quoted string" ;;
      esac
    fi
    warn "the command must be a \`gh\` invocation (got '${CMD[0]}')"; usage; exit 2 ;;
esac

# The verb names the gh command — the label a human reads, and what the prompt
# guard below keys on. It is the first one or two non-flag words after `gh`, but
# gh accepts its global flags before the verb (notably `-R`/`--repo`, which
# takes a value), so leading flags are skipped first. The guard fires only for a
# recognised verb, so the verb must be found even when a global flag precedes it.
VERB=""; skip=0
for a in "${CMD[@]:1}"; do
  if [ "$skip" = 1 ]; then skip=0; continue; fi
  case "$a" in
    --repo|-R) skip=1; continue ;;   # global flag; its value is the next arg
    --repo=*)  continue ;;           # global flag with an attached value
    -*)        [ -n "$VERB" ] && break; continue ;;  # a later flag ends the verb; a leading one is skipped past
    *)         VERB="${VERB:+$VERB }$a"; case "$VERB" in *" "*) break ;; esac ;;
  esac
done
[ -n "$VERB" ] || VERB="gh"
# `gh api` takes its endpoint where another command takes a second verb word,
# so its verb is `api` alone. The endpoint is read with the report's checks.
case "$VERB" in "api "*) VERB="api" ;; esac

# gh reads the word AFTER a value flag as that flag's value, whatever it is:
# `gh issue create --title --body B` sets the title to `--body` and then chokes
# on the leftover `B`, and `--repo --title` takes `--title` as the repository. A
# usable inline value is therefore one that is present and is not itself another
# flag; the attached `--flag=value` form carries its own value and is checked
# where it is read. A flag whose value is missing or another flag is not carried
# by the parked command — gh rejects it on paste with "flag needs an argument"
# or "unknown argument".
is_value() { case "${1-}" in ''|-*) return 1 ;; *) return 0 ;; esac; }

# gh's --repo takes one [HOST/]OWNER/REPO token. A value that is another flag,
# empty, carries whitespace (two arguments fused into one), or names no
# owner/repo pair is not a target a human can paste.
valid_repo() {
  case "${1-}" in
    ''|-*|*[[:space:]]*) return 1 ;;
    */|/*|*//*)          return 1 ;;
    */*)                 return 0 ;;
    *)                   return 1 ;;
  esac
}

# The target repo, from whole-token matches only: a `--repo` inside a --body
# VALUE is one argv element with other text around it and never matches. Every
# occurrence must agree, because guessing which one gh would win with is the
# one mistake that sends a report to the wrong project.
TARGET=""; REPO_SEEN=0; skip=0
for i in "${!CMD[@]}"; do
  [ "$skip" = 1 ] && { skip=0; continue; }
  a="${CMD[$i]}"; v=""
  case "$a" in
    --repo|-R) v="${CMD[$((i + 1))]:-}"; skip=1 ;;   # value is the next token; consume it
    --repo=*)  v="${a#--repo=}" ;;
    *) continue ;;
  esac
  REPO_SEEN=1
  valid_repo "$v" || {
    warn "\`$a\` needs a repository in [HOST/]OWNER/REPO form (got '${v:-<end of command>}'); gh reads the next word as the value, so a following flag or a bare word leaves the target wrong"
    exit 2
  }
  if [ -n "$TARGET" ] && [ "$TARGET" != "$v" ]; then
    warn "the command names two different repositories ('$TARGET' and '$v'); name the target exactly once"
    exit 2
  fi
  TARGET="$v"
done
if [ "$REPO_SEEN" = 0 ] && [ "$VERB" != "api" ]; then
  warn "the command names no repository. Add \`--repo <owner/name>\`: the operator pastes this in their own shell, where an implicit repo resolves against whatever they are standing in."
  exit 2
fi

# The flags that read a value out of a file park a path, not the value, and
# the path is gone by the time a human pastes the command. gh api's -F/--field
# and --input read files too. gh takes a short flag's value attached (-Fpath)
# and reads a single-dash word one short flag at a time (-cF path is -c -F
# path), so a word whose letters reach an F counts as -F. That also takes a
# value attached to a short flag that begins with F (-bFoo) for -F, so such a
# value goes after a space.
for a in "${CMD[@]}"; do
  f="$a"; CLUSTER=""
  if [[ "$a" =~ ^-[[:alpha:]]*F ]]; then
    f="-F"
    case "$a" in -F*) : ;; *) CLUSTER=" gh reads \`$a\` one short flag at a time, so its F is -F. A value that begins with F goes after a space, not attached to its flag." ;; esac
  fi
  case "$VERB:$f" in
    api:-F|api:--field|api:--field=*)
      warn "\`$a\` reads a value from a file after @, and fills {owner} and {repo} from the directory the command is pasted in. Pass each field inline as a string with -f.$CLUSTER"
      exit 2 ;;
    api:--input|api:--input=*)
      warn "\`$a\` reads the request body from a file, and the file is gone when the command is pasted. Pass each field inline as a string with -f."
      exit 2 ;;
    *:--body-file|*:-F|*:--body-file=*)
      warn "\`$a\` takes its value from a file, and the file is gone when the command is pasted. Inline the text (--body, or -f for a field).$CLUSTER"
      exit 2 ;;
  esac
done

# A private vulnerability report is the one `gh api` write this path parks: it
# is the private channel a security policy can name that `gh` reaches
# (docs/outbound-sends.md). gh api has no --repo, so the report names its
# repository in the endpoint path, and literally, because a {owner} or {repo}
# placeholder fills in from the directory the command is pasted in.
PRIVATE_REPORT=0
REPORT_FORM="gh api --method POST repos/<owner>/<name>/security-advisories/reports -f summary=<one line> -f description=<the report>"
REPORT_RE='^/?repos/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/security-advisories/reports$'
# gh api's flags that take a value. The word after one is that value, not the
# endpoint; an attached value (--method=POST, -XPOST) takes no word.
API_VALUE_FLAGS="-X --method -F --field -f --raw-field -H --header -p --preview --input -t --template -q --jq --hostname --cache"
has_field() {
  local f
  for f in ${FIELDS[@]+"${FIELDS[@]}"}; do
    case "$f" in "$1="?*) return 0 ;; esac
  done
  return 1
}
if [ "$VERB" = "api" ]; then
  if [ "$REPO_SEEN" = 1 ]; then
    warn "\`gh api\` has no --repo flag, so gh rejects the pasted command. Name the repository in the endpoint path: $REPORT_FORM"
    exit 2
  fi
  ENDPOINT=""; METHOD="POST"; API_HOST=""; FIELDS=(); WORDS=0
  for (( i = 1; i < ${#CMD[@]}; i++ )); do
    a="${CMD[$i]}"
    # -i is gh api's one short flag that takes no value, so gh reads -iX POST
    # as -i -X POST, and the flag after the i's is read here as it stands alone.
    while [[ "$a" == -i?* ]]; do a="-${a#-i}"; done
    case "$a" in
      -X|--method)    METHOD="${CMD[$((i + 1))]:-}"; i=$((i + 1)) ;;
      --method=*)     METHOD="${a#--method=}" ;;
      -X?*)           METHOD="${a#-X}"; METHOD="${METHOD#=}" ;;
      --hostname)     API_HOST="${CMD[$((i + 1))]:-}"; i=$((i + 1)) ;;
      --hostname=*)   API_HOST="${a#--hostname=}" ;;
      -f|--raw-field) FIELDS+=("${CMD[$((i + 1))]:-}"); i=$((i + 1)) ;;
      --raw-field=*)  FIELDS+=("${a#--raw-field=}") ;;
      -f?*)           a="${a#-f}"; FIELDS+=("${a#=}") ;;
      --*=*)          : ;;
      -*)             case " $API_VALUE_FLAGS " in *" $a "*) i=$((i + 1)) ;; esac ;;
      *)              WORDS=$((WORDS + 1)); [ "$WORDS" = 2 ] && ENDPOINT="$a" ;;
    esac
  done
  if [ "$WORDS" -gt 2 ] || ! [[ "$ENDPOINT" =~ $REPORT_RE ]]; then
    MORE=""; [ "$WORDS" -gt 2 ] && MORE=" and more words after it"
    warn "the one \`gh api\` write this path parks is a private vulnerability report, one endpoint naming its repository literally: $REPORT_FORM (got '${ENDPOINT:-no endpoint}'$MORE). A {owner} or {repo} placeholder fills in from the directory the command is pasted in. Park any other write as the gh command for it, with --repo."
    exit 2
  fi
  # --hostname sends the report to another GitHub host, so the target the
  # operator reads names that host.
  TARGET="${API_HOST:+$API_HOST/}${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  if [ "$(printf '%s' "$METHOD" | tr '[:lower:]' '[:upper:]')" != "POST" ]; then
    warn "a private vulnerability report is a POST, and this command's method is '${METHOD}'. Leave --method out, or give POST."
    exit 2
  fi
  WANT=""
  has_field summary || WANT="-f summary=<one line>"
  has_field description || WANT="${WANT:+$WANT and }-f description=<the report>"
  if [ -n "$WANT" ]; then
    warn "GitHub refuses a private vulnerability report without a summary and a description, so the pasted command would fail. Add $WANT."
    exit 2
  fi
  PRIVATE_REPORT=1
fi

# This rig's own origin, for the one refusal that belongs here: preparing a
# send to the repo we own asks a human for permission we already have.
origin_repo() {
  local u out
  u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
  case "$u" in
    git@github.com:*|https://github.com/*|ssh://git@github.com/*)
      out=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
        -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    *) out="" ;;
  esac
  case "$out" in */*/*|/*|*/) out="" ;; */*) : ;; *) out="" ;; esac
  printf '%s' "$out"
}
# gh takes OWNER/REPO or HOST/OWNER/REPO; compare the owner/repo tail, and
# case-insensitively, the way GitHub resolves a repository.
repo_key() {
  local r="${1:-}"
  case "$r" in */*/*) r="${r#*/}" ;; esac
  printf '%s' "$r" | tr '[:upper:]' '[:lower:]'
}
ORIGIN_REPO="$(origin_repo)"
ORIGIN_NOTE=""
[ -n "$ORIGIN_REPO" ] && ORIGIN_NOTE=" — this rig's origin is \`$ORIGIN_REPO\`"
if [ -n "$ORIGIN_REPO" ] && [ "$(repo_key "$TARGET")" = "$(repo_key "$ORIGIN_REPO")" ]; then
  warn "'$TARGET' IS this rig's own origin — nothing to prepare. Sends to our own repo need no approval; run the command."
  exit 2
fi

# A parked command is pasted later, unedited, by a person, so it must run
# without stopping to prompt. Several gh write verbs prompt for a field they
# were not handed: `issue create` and `pr create` for a missing title or body,
# `issue comment` and `pr comment` for a missing body. A parked command that
# prompts carries no prepared text — it waits — so require the inline content
# each such verb needs. A verb that never prompts (a `gh api` write, or a read)
# is not listed here and passes untouched.
cmd_has_flag() {
  local want a
  for want in "$@"; do
    for a in "${CMD[@]}"; do
      case "$a" in "$want"|"$want"=*) return 0 ;; esac
    done
  done
  return 1
}
# A required value flag counts only when it carries a value: `--flag VALUE` with
# a VALUE that is not another flag, or `--flag=VALUE` with a non-empty VALUE.
# `--title` at the end of the command, or `--title --body`, satisfies
# cmd_has_flag but gh still prompts for the title — the flag is there, its value
# is not.
flag_has_value() {
  local want i total="${#CMD[@]}"
  for want in "$@"; do
    for (( i = 0; i < total; i++ )); do
      case "${CMD[$i]}" in
        "$want")   is_value "${CMD[$((i + 1))]:-}" && return 0 ;;
        "$want"=*) [ -n "${CMD[$i]#*=}" ] && return 0 ;;
      esac
    done
  done
  return 1
}
NEED_TITLE=0; NEED_BODY=0
case "$VERB" in
  "issue create"|"pr create")   NEED_TITLE=1; NEED_BODY=1 ;;
  "issue comment"|"pr comment") NEED_BODY=1 ;;
esac
# `gh pr create --fill*` draws its title and body from the commits, so it does
# not prompt even when neither flag is given.
if [ "$VERB" = "pr create" ] && cmd_has_flag --fill --fill-first --fill-verbose; then
  NEED_TITLE=0; NEED_BODY=0
fi
MISSING=()
if [ "$NEED_TITLE" = 1 ] && ! flag_has_value --title -t; then MISSING+=("--title"); fi
if [ "$NEED_BODY" = 1 ] && ! flag_has_value --body -b; then MISSING+=("--body"); fi
if [ "${#MISSING[@]}" -gt 0 ]; then
  WANT="${MISSING[0]}"
  [ "${#MISSING[@]}" -gt 1 ] && WANT="${MISSING[0]} and ${MISSING[1]}"
  warn "\`$VERB\` with no inline $WANT would prompt for it when pasted — gh reads $WANT from an interactive prompt when the flag is omitted or carries no value, so the parked command would stop and wait instead of carrying the prepared text. Add $WANT inline (a value, not a file)."
  exit 2
fi

# A write verb whose target is an existing issue or PR needs that issue or PR
# named on the command line as a positional argument — a number, a URL, or a
# branch. gh rejects the pasted command without one (`gh issue comment --repo
# o/r --body B` fails with "accepts 1 arg(s), received 0"), and `pr comment`,
# `pr review` and the other pr verbs fall back to the current branch, which is
# ambient state rather than the reviewed finding. `create` verbs take no
# selector and are not listed. gh reads the word after a value flag as that
# flag's value, so those words are skipped when looking for the selector; the
# skip list errs long, because over-skipping only over-refuses.
SELECTOR_VALUE_FLAGS="--repo -R --body -b --body-file -F --title -t --milestone -m --label -l --add-label --remove-label --assignee --add-assignee --remove-assignee --project -p --add-project --remove-project --reviewer --add-reviewer --remove-reviewer --base -B --subject --author --author-email --match-head-commit --template"
has_selector() {
  local total="${#CMD[@]}" i skip=0 counted=0 tok
  local verb_words=1; case "$VERB" in *" "*) verb_words=2 ;; esac
  for (( i = 1; i < total; i++ )); do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    tok="${CMD[$i]}"
    case "$tok" in
      --*=*|-[A-Za-z]*=*) continue ;;   # attached value: consumes no next word
      -*) case " $SELECTOR_VALUE_FLAGS " in *" $tok "*) skip=1 ;; esac; continue ;;
      *)  if [ "$counted" -lt "$verb_words" ]; then counted=$((counted + 1)); continue; fi
          return 0 ;;                    # the first positional past the verb words
    esac
  done
  return 1
}
NEED_SELECTOR=0
case "$VERB" in
  "issue comment"|"issue close"|"issue reopen"|"issue edit"|"issue delete"|\
  "issue lock"|"issue unlock"|"issue pin"|"issue unpin"|"issue transfer"|\
  "pr comment"|"pr review"|"pr close"|"pr reopen"|"pr edit"|"pr merge"|\
  "pr ready"|"pr lock"|"pr unlock")
    NEED_SELECTOR=1 ;;
esac
if [ "$NEED_SELECTOR" = 1 ] && ! has_selector; then
  warn "\`$VERB\` acts on one specific issue or PR, but the command names none. gh takes the issue number, PR number, URL, or branch as a positional argument; without it the pasted command is rejected (\"accepts 1 arg(s), received 0\"), or a pr verb falls back to the current branch, which is not the reviewed finding. Name the target, e.g. \`$VERB 123 --repo $TARGET ...\`."
  exit 2
fi

# A parked send is pasted as it stands, so whether its text may be public is
# settled before it is parked. A public write publishes the finding the moment
# it is pasted, so it carries the preparer's reading of the target's security
# policy, and the operator reads that beside the command. A private
# vulnerability report needs none: it reaches the maintainers alone.
POLICY_SET=0; READING=""
[ -n "$(printf '%s' "$POLICY" | tr -d '[:space:]')" ] && { POLICY_SET=1; READING="$POLICY"; }
if [ "$PRIVATE_REPORT" = 1 ]; then
  SEND_LABEL="private vulnerability report"
  CHANNEL="Private: the report goes to the maintainers of $TARGET, not to a public page."
else
  SEND_LABEL="$VERB"
  CHANNEL="Public: everyone who can see $TARGET can read it once it is sent."
  if [ "$POLICY_SET" = 0 ]; then
    # A target on another GitHub host is read on that host.
    OWNER_NAME="$TARGET"; HOST_ARG=""
    case "$OWNER_NAME" in */*/*) HOST_ARG="--hostname ${OWNER_NAME%%/*} "; OWNER_NAME="${OWNER_NAME#*/}" ;; esac
    OWNER="${OWNER_NAME%%/*}"; NAME="${OWNER_NAME#*/}"
    warn "\`$VERB\` on $TARGET is public: once pasted, everyone who can see $TARGET can read it. Read $TARGET's security policy first, and pass what it says as --security-policy \"<where it is or that there is none, and why it lets this report be public>\"."
    warn "  GitHub says whether $TARGET has one and where, its owner's default included: gh api ${HOST_ARG}graphql -f query='{repository(owner:\"$OWNER\",name:\"$NAME\"){isSecurityPolicyEnabled securityPolicyUrl}}'"
    warn "  If it asks for this finding in private, park the private channel it names instead. GitHub's private vulnerability reporting is one wherever gh api ${HOST_ARG}repos/$OWNER/$NAME/private-vulnerability-reporting reads {\"enabled\":true}: gh api ${HOST_ARG}--method POST repos/$OWNER/$NAME/security-advisories/reports -f summary=<one line> -f description=<the report>"
    warn "  A private channel gh cannot reach, such as an email address, is the operator's to use: ask through escalate.sh with the report in its message, and park nothing public."
    exit 2
  fi
fi
# A re-run reads the parked reading back from between these two labels, so the
# bead's description and the visit are written with them.
POLICY_LABEL="Security policy, as read before parking:"
PASTE_LABEL="Paste this, unedited, to send it:"
[ "$POLICY_SET" = 1 ] && CHANNEL="$CHANNEL
$POLICY_LABEL $POLICY"

# A stable digest over the exact argv, NUL-joined so no argument boundary can
# be forged by an argument's own bytes.
sig() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s\0' "$@" | sha256sum | cut -c1-12
  else
    printf '%s\0' "$@" | cksum | tr -d ' ' | cut -c1-12
  fi
}
slug() { printf '%s' "${1:-}" | tr -c 'A-Za-z0-9._-' '-' | sed -e 's#--*#-#g' -e 's#^-##' -e 's#-$##'; }

if [ -z "$KEY" ]; then
  KEY="$(slug "$(repo_key "$TARGET")")-$(slug "$VERB")-$(sig "${CMD[@]}")"
fi
case "$KEY" in
  *[!A-Za-z0-9._-]*) warn "--key must contain only [A-Za-z0-9._-] (got '$KEY')"; exit 2 ;;
esac

# The pasteable form. `printf %q` is what makes a multi-line body survive as
# one line, and the round-trip below is the proof that it did: re-split the
# parked string and require the exact argv back. Nothing is parked unless it
# reproduces, because a command that reassembles differently sends something
# other than what was reviewed. The eval reads only this script's own %q
# output, and `set --` runs nothing.
PASTE="$(printf '%q ' "${CMD[@]}")"; PASTE="${PASTE% }"
if [ "$(eval "set -- $PASTE"; sig "$@")" != "$(sig "${CMD[@]}")" ]; then
  warn "the command does not survive quoting — nothing parked. Report this: it is a bug in $PROG, not in your command."
  exit 1
fi

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }

# One bead per situation, whatever its status. An open one is the same ask
# still waiting; a closed one is an ask a human already answered, and re-filing
# it re-asks a question that was settled.
EXISTING_LIST=$(bd_json list --status=open,in_progress,closed --metadata-field "upstream_send_key=$KEY" --limit=20)
# An unreadable listing is not an empty one. Say so and file: a duplicate ask
# is a bounded nuisance, a finding dropped because the store blinked is not.
case "$EXISTING_LIST" in
  \[*) : ;;
  *) warn "could not read the store to look for an existing ask — filing anyway, which may duplicate an open one" ;;
esac
EXISTING_ROW=$(printf '%s' "$EXISTING_LIST" \
  | jq -r --arg k "$KEY" \
      'if type == "array" then (.[] | select((.metadata.upstream_send_key // "") == $k) | [.id, (.status // "open")] | @tsv) else empty end' 2>/dev/null \
  | head -n 1)
EXISTING="${EXISTING_ROW%%$'\t'*}"; EXISTING_STATUS=""
case "$EXISTING_ROW" in *$'\t'*) EXISTING_STATUS="${EXISTING_ROW#*$'\t'}" ;; esac
if [ -n "$EXISTING" ] && [ "$EXISTING_STATUS" = "closed" ]; then
  echo "$PROG: $EXISTING already carries this send and is closed — a human has answered it. Nothing filed."
  exit 0
fi

# A caller-supplied key claims "same situation", so a changed command under one
# is a divergence, not a refresh: the bead a human is reading would keep the
# command they were shown while the caller believes the new one is parked. A
# changed security-policy reading is a divergence under any key, because the
# reading is the operator's evidence that the send may be public, and a re-run
# rewrites neither the bead nor its visit.
if [ -n "$EXISTING" ]; then
  EXISTING_SHOW=$(bd_json show "$EXISTING")
  # Only a bead that was actually read can be called divergent. A failed read
  # presents as an empty parked command, which reads as a divergence and sends
  # the caller to the one repair that defeats the key: re-filing under another.
  if [ "$(printf '%s' "$EXISTING_SHOW" | jq -r 'if type == "array" then (.[0].id // "") else "" end' 2>/dev/null)" != "$EXISTING" ]; then
    warn "$EXISTING carries key '$KEY' but did not read back, so what is parked there is unknown — nothing parked. Re-run: this is a failed read, not a divergence."
    exit 1
  fi
  EXISTING_CMD=$(printf '%s' "$EXISTING_SHOW" | jq -r '.[0].metadata.gh_command // ""' 2>/dev/null)
  # The two labels bound the parked reading, so a reading that only begins or
  # ends it does not match. A bead with no reading differs from any reading
  # given now.
  SAME_READING=$(printf '%s' "$EXISTING_SHOW" | jq -r --arg l "$POLICY_LABEL" --arg p "$PASTE_LABEL" --arg r "$READING" '
    (.[0].description // "") as $d
    | if $r == "" then ($d | contains("\n" + $l + " ") | not)
      else ($d | contains("\n" + $l + " " + $r + "\n\n" + $p)) end' 2>/dev/null)
  if [ "$EXISTING_CMD" != "$PASTE" ]; then
    warn "$EXISTING already carries key '$KEY' with a DIFFERENT command, and a human may already be reading it — nothing parked."
    warn "  parked there: $EXISTING_CMD"
    warn "  yours:        $PASTE"
  elif [ "$SAME_READING" != "true" ]; then
    PARKED_READING=$(printf '%s' "$EXISTING_SHOW" | jq -r --arg l "$POLICY_LABEL" --arg p "$PASTE_LABEL" '
      (.[0].description // "") | split("\n" + $l + " ")
      | if length < 2 then "" else (.[1] | split("\n\n" + $p) | .[0]) end' 2>/dev/null)
    warn "$EXISTING already carries this send with a DIFFERENT security-policy reading, and a human may already be weighing it beside the command — nothing parked or refreshed."
    warn "  parked there: ${PARKED_READING:-no reading}"
    warn "  yours:        ${READING:-no reading}"
    warn "  If yours says the same in other words, the ask stands as parked and nothing needs doing."
  fi
  if [ "$EXISTING_CMD" != "$PASTE" ] || [ "$SAME_READING" != "true" ]; then
    warn "  repair: a re-run changes neither $EXISTING nor its visit, and its key files nothing once it is closed. Park yours under a new --key, and when yours replaces what $EXISTING shows, close $EXISTING with the reason."
    exit 2
  fi
fi

BEAD="$EXISTING"
if [ -z "$BEAD" ]; then
  HEADLINE="$SEND_LABEL on $TARGET"
  TITLE="upstream send (awaiting operator): $(printf '%s' "$HEADLINE" | head -n 1 | cut -c1-120)"
  BODY="$MESSAGE

## The send, prepared not sent

Target repo: \`$TARGET\`$ORIGIN_NOTE

$CHANNEL

$PASTE_LABEL

\`\`\`bash
$PASTE
\`\`\`

Nothing has been sent. A write to a repo the rig does not own is the operator's
to make, so an agent prepares the command and stops (docs/outbound-sends.md).
Closing this bead answers the ask either way: sent, or declined."

  # The command IS the deliverable and the key is what keeps one ask from
  # becoming three, so both ride the create with the rest of the send, and the
  # create reads them back. A bead whose command did not land asks a human to
  # paste nothing. A create whose reply was lost has still landed with its key,
  # and a re-run finds it above.
  META=$(jq -nc --arg k "$KEY" --arg t "$TARGET" --arg v "$VERB" --arg c "$PASTE" \
    '{task_kind: "upstream-send", upstream_send_key: $k, gh_target_repo: $t, gh_verb: $v, gh_command: $c}' 2>/dev/null)
  BEAD=$(bd_create "$META" -t task --title "$TITLE" -d "$BODY"); BEAD_RC=$?
  if [ "$BEAD_RC" -eq 2 ]; then
    warn "bead $BEAD was created but its stamps did not read back; the command is in the description. Repair: gc bd update $BEAD --set-metadata upstream_send_key=$KEY --set-metadata gh_command=<the command>"
    exit 1
  elif [ "$BEAD_RC" -ne 0 ]; then
    warn "gc bd create filed nothing — nothing parked; re-run rather than improvising another create form"
    exit 1
  fi
fi

# The visit is how a human hears about it; escalate.sh owns the route, the
# dedup and the refresh, so a re-run lands on the same visit.
ESC_MESSAGE="Approve or decline an outbound $SEND_LABEL on $TARGET (bead $BEAD)

$MESSAGE

$CHANNEL

$PASTE_LABEL

$PASTE

Nothing has been sent, and no agent may send it: a write to a repo this rig
does not own is yours to make (docs/outbound-sends.md). Declining is closing
$BEAD."

if [ ! -x "$ESCALATE" ]; then
  warn "no escalate.sh at $ESCALATE — bead $BEAD carries the command but NO ONE HAS BEEN ASKED. File the visit by hand, or set GC_ESCALATE_TOOL."
  exit 1
fi
ESC_ARGS=(--subject "$BEAD" --key "upstream-send-$KEY" --message "$ESC_MESSAGE")
[ -n "$POOL_ARG" ] && ESC_ARGS+=(--pool "$POOL_ARG")
if ! ESC_OUT=$("$ESCALATE" "${ESC_ARGS[@]}"); then
  warn "bead $BEAD carries the command but escalate.sh did not file a visit — NO ONE HAS BEEN ASKED. Re-run this command; it will reuse $BEAD."
  exit 1
fi
printf '%s\n' "$ESC_OUT"

if [ -n "$EXISTING" ]; then
  echo "$PROG: $BEAD already carries this send — refreshed the ask, nothing filed twice"
else
  echo "$PROG: parked $SEND_LABEL on $TARGET as $BEAD [$KEY] — nothing sent"
fi
exit 0
