#!/usr/bin/env bash
# upstream-finding.sh — prepare an outbound GitHub write; never send it.
# A repo outside the rig's own origin is someone else's time to spend, so the
# send is the operator's (docs/outbound-sends.md). An agent that wants one runs
# the intended `gh` command through this script instead of running it: the
# command is parked verbatim on a bead as `gh_command`, ready to paste, and a
# visit asks a human for the send.
#   upstream-finding.sh --message <why this send is warranted>
#                       [--key <situation-key>] [--pool <converse pool>]
#                       -- gh <verb> --repo <owner/name> [args...]
# This script contacts nothing. It runs no `gh`, and it is not a send path a
# guard can be talked through.
# Exit: 0 parked, already parked or already answered · 1 could not file or
# verify · 2 usage, including a command this path cannot make pasteable.
set -uo pipefail

PROG="upstream-finding"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESCALATE="${GC_ESCALATE_TOOL:-$HERE/escalate.sh}"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: upstream-finding.sh --message <why this send is warranted>
                           [--key <situation-key>] [--pool <converse pool>]
                           -- gh <verb> --repo <owner/name> [args...]

  --message  what the operator is being asked to approve, in their terms: what
             was found, where it was hit, why it is worth someone else's time.
             The `gh` body is written for the upstream maintainer and does not
             answer this (required)
  --key      names the SITUATION: one bead per key, so a re-run of the same
             finding refreshes rather than files again. [A-Za-z0-9._-] only.
             Default: target repo, verb and a digest of the command
  --pool     converse pool the visit routes to; passed through to escalate.sh,
             which owns the default and the route check
  --         everything after it is the command, verbatim. It must name its
             target with `--repo <owner/name>`: the operator pastes it in
             their own shell, where an implicit repo resolves somewhere else
U
}

warn() { echo "$PROG: $*" >&2; }

MESSAGE=""; KEY=""; POOL_ARG=""; CMD=()
while [ $# -gt 0 ]; do
  case "$1" in
    --message) MESSAGE="${2:-}"; shift 2 || { usage; exit 2; } ;;
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

# The target repo, from whole-token matches only: a `--repo` inside a --body
# VALUE is one argv element with other text around it and never matches. Every
# occurrence must agree, because guessing which one gh would win with is the
# one mistake that sends a report to the wrong project.
TARGET=""; REPO_SEEN=0; skip=0
for i in "${!CMD[@]}"; do
  [ "$skip" = 1 ] && { skip=0; continue; }
  a="${CMD[$i]}"; v=""
  case "$a" in
    --repo|-R) v="${CMD[$((i + 1))]:-}"; skip=1 ;;
    --repo=*)  v="${a#--repo=}" ;;
    *) continue ;;
  esac
  REPO_SEEN=1
  [ -n "$v" ] || { warn "\`$a\` carries no repository"; exit 2; }
  if [ -n "$TARGET" ] && [ "$TARGET" != "$v" ]; then
    warn "the command names two different repositories ('$TARGET' and '$v'); name the target exactly once"
    exit 2
  fi
  TARGET="$v"
done
if [ "$REPO_SEEN" = 0 ]; then
  warn "the command names no repository. Add \`--repo <owner/name>\`: the operator pastes this in their own shell, where an implicit repo resolves against whatever they are standing in."
  exit 2
fi

# The flags that read a value out of a file park a path, not the value, and
# the path is gone by the time a human pastes the command.
for a in "${CMD[@]}"; do
  case "$a" in
    --body-file|-F|--body-file=*)
      warn "\`$a\` takes its value from a file, and the file is gone when the command is pasted. Inline the text (--body, or -f for a field)."
      exit 2 ;;
  esac
done

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
if [ "$NEED_TITLE" = 1 ] && ! cmd_has_flag --title -t; then MISSING+=("--title"); fi
if [ "$NEED_BODY" = 1 ] && ! cmd_has_flag --body -b; then MISSING+=("--body"); fi
if [ "${#MISSING[@]}" -gt 0 ]; then
  WANT="${MISSING[0]}"
  [ "${#MISSING[@]}" -gt 1 ] && WANT="${MISSING[0]} and ${MISSING[1]}"
  warn "\`$VERB\` with no inline $WANT would prompt for it when pasted — gh reads $WANT from an interactive prompt when the flag is omitted, so the parked command would stop and wait instead of carrying the prepared text. Add $WANT inline (a value, not a file)."
  exit 2
fi

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

bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }

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
# command they were shown while the caller believes the new one is parked.
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
  if [ "$EXISTING_CMD" != "$PASTE" ]; then
    warn "$EXISTING already carries key '$KEY' with a DIFFERENT command, and a human may already be reading it — nothing parked."
    warn "  parked there: $EXISTING_CMD"
    warn "  yours:        $PASTE"
    warn "  repair: re-run under a new --key, or close $EXISTING first."
    exit 2
  fi
fi

BEAD="$EXISTING"
if [ -z "$BEAD" ]; then
  HEADLINE="$VERB on $TARGET"
  TITLE="upstream send (awaiting operator): $(printf '%s' "$HEADLINE" | head -n 1 | cut -c1-120)"
  BODY="$MESSAGE

## The send, prepared not sent

Target repo: \`$TARGET\`$ORIGIN_NOTE

Paste this, unedited, to send it:

\`\`\`bash
$PASTE
\`\`\`

Nothing has been sent. A write to a repo the rig does not own is the operator's
to make, so an agent prepares the command and stops (docs/outbound-sends.md).
Closing this bead answers the ask either way: sent, or declined."

  BEAD=$(gc bd create -t task --title "$TITLE" -d "$BODY" --json | scrub | jq -r '.id // .[0].id' 2>/dev/null)
  [ -n "$BEAD" ] && [ "$BEAD" != "null" ] \
    || { warn "gc bd create returned no id — nothing parked; re-run rather than improvising another create form"; exit 1; }
  gc bd update "$BEAD" \
    --set-metadata "task_kind=upstream-send" \
    --set-metadata "upstream_send_key=$KEY" \
    --set-metadata "gh_target_repo=$TARGET" \
    --set-metadata "gh_verb=$VERB" \
    --set-metadata "gh_command=$PASTE" >/dev/null 2>&1

  # The command IS the deliverable and the key is what keeps one ask from
  # becoming three, so both are read back. A bead whose command did not land
  # asks a human to paste nothing.
  ROW=$(bd_json show "$BEAD")
  GOT_CMD=$(printf '%s' "$ROW" | jq -r '.[0].metadata.gh_command // ""' 2>/dev/null)
  GOT_KEY=$(printf '%s' "$ROW" | jq -r '.[0].metadata.upstream_send_key // ""' 2>/dev/null)
  if [ "$GOT_CMD" != "$PASTE" ] || [ "$GOT_KEY" != "$KEY" ]; then
    warn "bead $BEAD was created but its stamps did not read back; the command is in the description. Repair: gc bd update $BEAD --set-metadata upstream_send_key=$KEY --set-metadata gh_command=<the command>"
    exit 1
  fi
fi

# The visit is how a human hears about it; escalate.sh owns the route, the
# dedup and the refresh, so a re-run lands on the same visit.
ESC_MESSAGE="Approve or decline an outbound $VERB on $TARGET (bead $BEAD)

$MESSAGE

Paste this, unedited, to send it:

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
  echo "$PROG: parked $VERB on $TARGET as $BEAD [$KEY] — nothing sent"
fi
exit 0
