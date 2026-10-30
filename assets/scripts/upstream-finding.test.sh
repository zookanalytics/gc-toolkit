#!/usr/bin/env bash
# Hermetic test for assets/scripts/upstream-finding.sh — the prepare-only path.
# Stubbed gc and escalate.sh over a JSON store, a real throwaway git repo for
# the origin read, and a `gh` on PATH that fails loudly: this script must never
# reach GitHub, and the log proves it did not.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UF="$HERE/upstream-finding.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-upstream-finding-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# A public send is parked only with the preparer's reading of the target's
# security policy. Most cases below test something else, so "$SUT" passes a
# reading; the cases about the reading and the private report call "$UF".
POLICY_READ="No security policy: isSecurityPolicyEnabled is false for this repository."
SUT="$TMP/upstream-finding-with-policy"
printf '#!%s\nexec %q --security-policy %q "$@"\n' "${BASH:-/usr/bin/env bash}" "$UF" "$POLICY_READ" > "$SUT"
chmod +x "$SUT"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2' in: $1)" ; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
set -u
STORE="${STUB_STORE:?}"
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
[ "${1:-}" = "bd" ] || { echo "gc stub: unsupported '${1:-}'" >&2; exit 2; }
shift
case "${1:-}" in
  list)
    [ -n "${STUB_LIST_GARBAGE:-}" ] && { echo "bd: store unreachable" >&2; exit 1; }
    shift
    statuses=""; fields=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
        --metadata-field=*) fields+=("${1#--metadata-field=}") ;;
      esac
      shift || true
    done
    # An unfiltered listing would hide a status bug, so the stub honours the
    # filter the caller passed and nothing else.
    out=$(jq -c --arg st ",$statuses," '[ .[] | select(.status as $s | $st | contains("," + $s + ",")) ]' "$STORE")
    for f in ${fields[@]+"${fields[@]}"}; do
      k="${f%%=*}"; v="${f#*=}"
      out=$(printf '%s' "$out" | jq -c --arg k "$k" --arg v "$v" '[ .[] | select((.metadata[$k] // "") == $v) ]')
    done
    printf '%s\n' "$out" ;;
  show)
    [ -n "${STUB_SHOW_GARBAGE:-}" ] && { echo "bd: store unreachable" >&2; exit 1; }
    jq -c --arg id "${2:-}" '[.[] | select(.id == $id)]' "$STORE" ;;
  create)
    shift
    title=""; body=""; meta="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="${1:-}" ;;
        -d) shift; body="${1:-}" ;;
        --metadata) shift; meta="${1:-}"; [ -n "$meta" ] || meta="{}" ;;
      esac
      shift || true
    done
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    # STUB_DROP_KEYS lands the create without the named keys, a payload that
    # half-landed, so the read-back finds the rest.
    meta=$(printf '%s' "$meta" | jq -c --arg d "${STUB_DROP_KEYS:-}" \
      '($d | split(",")) as $drop | with_entries(select(.key as $k | $drop | index($k) | not))')
    tmp=$(mktemp)
    # The real `gc bd create` stamps --metadata (a JSON object) atomically; model
    # it so the visit carries the identity the create sets, not only what a
    # follow-up update writes.
    jq -c --arg id "up-$n" --arg t "$title" --arg d "$body" --argjson m "$meta" \
      '. + [{"id":$id,"status":"open","assignee":"","title":$t,"description":$d,"metadata":$m,"notes":""}]' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    printf '{"id":"up-%s"}\n' "$n" ;;
  update)
    shift; id="${1:-}"; shift
    tmp=$(mktemp); cp "$STORE" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          # STUB_DROP_KEYS models a write that reported success and half-landed.
          case ",${STUB_DROP_KEYS:-}," in *",$k,"*) shift || true; continue ;; esac
          jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
            'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
      shift || true
    done
    mv "$tmp" "$STORE"; echo "updated $id" ;;
  dep)
    [ "${2:-}" = "add" ] && printf '%s|%s|%s\n' "${3:-}" "${4:-}" "${5#--type=}" >> "${STUB_DEPS:?}" ;;
  *) echo "gc bd stub: unsupported '${1:-}'" >&2; exit 2 ;;
esac
STUB

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gh" <<'STUB'
printf '%s\n' "$*" >> "${STUB_GH_LOG:?}"
echo "gh stub: upstream-finding must never invoke gh" >&2
exit 99
STUB

ESC="$TMP/escalate.sh"
cat > "$ESC" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_ESC_LOG:?}"
[ -n "${STUB_ESC_RC:-}" ] && { echo "escalate: simulated failure" >&2; exit "$STUB_ESC_RC"; }
subject=""
while [ $# -gt 0 ]; do case "$1" in --subject) shift; subject="${1:-}" ;; esac; shift || true; done
echo "escalate: filed visit vis-1 on $subject"
STUB
chmod +x "$BIN/gc" "$BIN/gh" "$ESC"
export PATH="$BIN:$PATH"
export GC_ESCALATE_TOOL="$ESC"
export STUB_STORE="$TMP/beads.json" STUB_SEQ="$TMP/seq" STUB_DEPS="$TMP/deps.txt"
export STUB_GC_LOG="$TMP/gc.log" STUB_GH_LOG="$TMP/gh.log" STUB_ESC_LOG="$TMP/esc.log"
# A rig inherited from the ambient shell would point the stubs at a live city.
unset GC_RIG

# A real repository, so the own-origin refusal is proved against git's own
# answer rather than a stub's idea of one.
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" remote add origin git@github.com:zookanalytics/gc-toolkit.git
cd "$REPO" || exit 1

reset_state() {
  echo '[]' > "$STUB_STORE"; : > "$STUB_SEQ"
  : > "$STUB_GC_LOG"; : > "$STUB_GH_LOG"; : > "$STUB_ESC_LOG"; : > "$STUB_DEPS"
  unset STUB_ESC_RC STUB_DROP_KEYS
}
meta() { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
count() { jq 'length' "$STUB_STORE"; }

BODY_TEXT='sendSources never reaches the delta log.

`toUIMessageStream()` is called with no options at src/x.ts:264 — the "sources"
flag is dropped. Repro: $(npm test) with sendSources: true.'

# ── the happy path ────────────────────────────────────────────────────────
reset_state
OUT=$("$SUT" --message "Hit while working ra-kg9z6; the bug is in the pinned 0.7.1 runtime." \
  -- gh issue create --repo get-convex/agent --title "sendSources cannot be enabled" --body "$BODY_TEXT" 2>&1)
RC=$?
eq "$RC" "0" "parking a finding exits 0"
eq "$(count)" "1" "exactly one bead is filed"
has "$OUT" "parked issue create on get-convex/agent" "reports what it parked"
has "$OUT" "nothing sent" "says out loud that nothing was sent"
eq "$(meta up-1 gh_target_repo)" "get-convex/agent" "gh_target_repo is the target"
eq "$(meta up-1 gh_verb)" "issue create" "gh_verb is the two-word verb"
eq "$(meta up-1 task_kind)" "upstream-send" "task_kind marks the bead"
has "$(cat "$STUB_GC_LOG")" '--metadata {"task_kind":"upstream-send","upstream_send_key":' "the send and its key ride the create"
hasnt "$(cat "$STUB_GC_LOG")" "update up-1" "…with no second write to stamp them"
eq "$(< "$STUB_GH_LOG" wc -l | tr -d ' ')" "0" "gh is never invoked"

# The parked command must reassemble into the exact argv, body and all.
PARKED=$(meta up-1 gh_command)
eval "set -- $PARKED"
eq "$#" "9" "the parked command re-splits into the same argument count"
eq "$1" "gh" "argv[0] survives"
eq "$5" "get-convex/agent" "the repo survives"
eq "$9" "$BODY_TEXT" "a multi-line body with backticks, quotes and \$( ) survives verbatim"
case "$PARKED" in *$'\n'*) bad "the parked command is one pasteable line" ;; *) ok "the parked command is one pasteable line" ;; esac

# The bead a human reads carries the command too, not just the metadata.
DESC=$(jq -r '.[] | select(.id == "up-1") | .description' "$STUB_STORE")
has "$DESC" "$PARKED" "the description carries the pasteable command"
has "$DESC" "Hit while working ra-kg9z6" "the description carries the operator's rationale"

# The ask reaches a human, on this bead.
ESC=$(cat "$STUB_ESC_LOG")
has "$ESC" "--subject up-1" "escalate.sh is called on the new bead"
has "$ESC" "--key upstream-send-" "the visit carries the situation key"
has "$OUT" "filed visit vis-1" "the visit line is passed through to the caller"

# ── dedup ─────────────────────────────────────────────────────────────────
: > "$STUB_ESC_LOG"
OUT=$("$SUT" --message "same finding, second pass" \
  -- gh issue create --repo get-convex/agent --title "sendSources cannot be enabled" --body "$BODY_TEXT" 2>&1)
eq "$?" "0" "a repeat run exits 0"
eq "$(count)" "1" "a repeat run files no second bead"
has "$OUT" "already carries this send" "a repeat run says the ask already stands"
has "$(cat "$STUB_ESC_LOG")" "--subject up-1" "the repeat run refreshes the ask on the SAME bead"

# ── an answered ask is not re-asked ───────────────────────────────────────
: > "$STUB_ESC_LOG"
tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-upstream-finding-test.XXXXXX"); jq -c 'map(if .id == "up-1" then .status = "closed" else . end)' "$STUB_STORE" > "$tmp" && mv "$tmp" "$STUB_STORE"
OUT=$("$SUT" --message "third pass, after the operator answered" \
  -- gh issue create --repo get-convex/agent --title "sendSources cannot be enabled" --body "$BODY_TEXT" 2>&1)
eq "$?" "0" "a run against a closed ask exits 0"
eq "$(count)" "1" "a closed ask is not re-filed"
has "$OUT" "a human has answered it" "it says the ask was already answered"
eq "$(< "$STUB_ESC_LOG" wc -l | tr -d ' ')" "0" "no visit is filed for an answered ask"

# ── a reused key with a different command is a divergence ─────────────────
reset_state
"$SUT" --key sendsources --message "first" \
  -- gh issue create --repo get-convex/agent --title "A" --body "one" >/dev/null 2>&1
OUT=$("$SUT" --key sendsources --message "second" \
  -- gh issue create --repo get-convex/agent --title "B" --body "two" 2>&1)
eq "$?" "2" "a changed command under a reused key is refused"
eq "$(count)" "1" "the divergent run files nothing"
has "$OUT" "DIFFERENT command" "the refusal names the divergence"
has "$OUT" "new --key" "the refusal says how to proceed"

# ── refusals that keep the parked command pasteable ───────────────────────
reset_state
OUT=$("$SUT" --message "why" -- gh issue create --title "T" --body "B" 2>&1)
eq "$?" "2" "a command naming no repository is refused"
eq "$(count)" "0" "nothing is filed for a command with no repository"
has "$OUT" "--repo <owner/name>" "the refusal names the missing flag"

OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --body-file /tmp/body.md 2>&1)
eq "$?" "2" "a --body-file is refused"
has "$OUT" "gone when the command is pasted" "the refusal says why a file path cannot be parked"
OUT=$("$SUT" --message "why" -- gh pr review 5 --repo a/b --comment -F/tmp/body.md 2>&1)
eq "$?" "2" "a -F with its path attached is refused too"
has "$OUT" "gone when the command is pasted" "the attached -F refusal says why"

OUT=$("$SUT" --message "why" -- "gh issue create --repo a/b --title T" 2>&1)
eq "$?" "2" "a command quoted into one argument is refused"
has "$OUT" "separate arguments after --" "the refusal names the mistake"

OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --repo c/d --title T --body B 2>&1)
eq "$?" "2" "two disagreeing repositories are refused"
has "$OUT" "exactly once" "the refusal asks for one target"

OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --repo a/b --title T --body B 2>&1)
eq "$?" "0" "a repeated but agreeing --repo is accepted"

# A --repo inside a body VALUE is text, not a target.
reset_state
OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title T \
  --body "run it as: gh issue list --repo other/repo" 2>&1)
eq "$?" "0" "a --repo inside a body value does not read as a second target"
eq "$(meta up-1 gh_target_repo)" "a/b" "the target comes from the flag, not the body text"

# ── a write that would prompt when pasted is refused ──────────────────────
# gh reads an omitted title or body from an interactive prompt, so a parked
# command that lacks one carries no prepared text — it would stop and wait.
reset_state
OUT=$("$SUT" --message "why" -- gh issue create --repo a/b 2>&1)
eq "$?" "2" "an issue create with neither title nor body is refused"
eq "$(count)" "0" "nothing is filed for a command that would prompt"
has "$OUT" "prompt" "the refusal says the command would prompt"
has "$OUT" "--title" "the refusal names the missing title"
has "$OUT" "--body" "the refusal names the missing body"

OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --body B 2>&1)
eq "$?" "2" "an issue create with no title is refused"
has "$OUT" "--title" "the refusal names the missing title"
hasnt "$OUT" "--body" "the refusal names only what is missing, not the present body"

OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title T 2>&1)
eq "$?" "2" "an issue create with no body is refused"
has "$OUT" "--body" "the refusal names the missing body"
hasnt "$OUT" "--title" "the refusal names only what is missing, not the present title"

OUT=$("$SUT" --message "why" -- gh issue comment 5 --repo a/b 2>&1)
eq "$?" "2" "an issue comment with no body is refused"
has "$OUT" "--body" "the comment refusal names the missing body"

# The short flags are the same flags, so they satisfy the requirement.
reset_state
"$SUT" --message "why" -- gh issue create --repo a/b -t T -b B >/dev/null 2>&1
eq "$?" "0" "short -t/-b satisfy the inline-content requirement"
eq "$(count)" "1" "the short-flag form parks one bead"

# pr create and pr comment prompt the same way, and are refused the same way.
reset_state
OUT=$("$SUT" --message "why" -- gh pr create --repo a/b 2>&1)
eq "$?" "2" "a pr create with neither title nor body is refused"
OUT=$("$SUT" --message "why" -- gh pr comment 5 --repo a/b 2>&1)
eq "$?" "2" "a pr comment with no body is refused"

# --fill draws a PR's title and body from the commits, so it does not prompt.
reset_state
"$SUT" --message "why" -- gh pr create --repo a/b --fill >/dev/null 2>&1
eq "$?" "0" "pr create --fill needs no inline title or body"
eq "$(count)" "1" "the --fill form parks one bead"

# ── a global flag before the verb does not evade the prompt guard ─────────
# gh accepts `-R`/`--repo` before the verb (`gh --repo a/b issue create` is a
# valid shape), and --repo takes a value. The verb must be found past those, or
# the prompt guard — which fires only for a recognised verb — is silently
# skipped and an incomplete write is parked as pasteable.
reset_state
OUT=$("$SUT" --message "why" -- gh --repo a/b issue create 2>&1)
eq "$?" "2" "an issue create with --repo before the verb and no content is refused"
eq "$(count)" "0" "nothing is filed for the flag-first prompt case"
has "$OUT" "prompt" "the refusal says the command would prompt"
has "$OUT" "--title" "the refusal names the missing title"
has "$OUT" "--body" "the refusal names the missing body"

OUT=$("$SUT" --message "why" -- gh -R a/b issue create 2>&1)
eq "$?" "2" "a -R before the verb is refused the same way"

OUT=$("$SUT" --message "why" -- gh --repo=a/b issue create 2>&1)
eq "$?" "2" "a --repo=a/b with an attached value before the verb is refused the same way"

OUT=$("$SUT" --message "why" -- gh --repo a/b pr comment 5 2>&1)
eq "$?" "2" "a pr comment with --repo before the verb and no body is refused"
has "$OUT" "--body" "the refusal names the missing body"

# The valid flag-first form still parks, and the verb is read past the flag —
# not left as a bare `gh`, which is what let the incomplete form through.
reset_state
"$SUT" --message "why" -- gh --repo get-convex/agent issue create --title T --body B >/dev/null 2>&1
eq "$?" "0" "a complete issue create with --repo before the verb parks"
eq "$(count)" "1" "the flag-first form parks exactly one bead"
eq "$(meta up-1 gh_verb)" "issue create" "the verb is read past the leading --repo, not left as bare gh"
eq "$(meta up-1 gh_target_repo)" "get-convex/agent" "the target still resolves with --repo before the verb"

# ── a value flag whose value is missing or another flag is refused ────────
# gh reads the word after --repo/--title/--body as that flag's value, whatever
# it is, so a following flag or the end of the command leaves the flag with no
# value. gh then rejects the pasted command ("flag needs an argument" /
# "unknown argument"), so the parked form is not one a human can paste.
# Presence alone — the earlier test — let all of these through.
reset_state

# --repo whose value is the next flag, missing, empty, or a bare word: no target.
OUT=$("$SUT" --message "why" -- gh issue create --repo --title T --body B 2>&1)
eq "$?" "2" "a --repo whose value is the next flag is refused"
eq "$(count)" "0" "nothing is parked when --repo swallowed a flag as its target"
has "$OUT" "[HOST/]OWNER/REPO" "the refusal names the repository form expected"

OUT=$("$SUT" --message "why" -- gh issue create --title T --body B --repo 2>&1)
eq "$?" "2" "a --repo with no value at the end of the command is refused"

OUT=$("$SUT" --message "why" -- gh issue create --repo= --title T --body B 2>&1)
eq "$?" "2" "an attached --repo= with an empty value is refused"

OUT=$("$SUT" --message "why" -- gh issue create --repo notarepo --title T --body B 2>&1)
eq "$?" "2" "a --repo value that is not owner/repo is refused"
has "$OUT" "[HOST/]OWNER/REPO" "the bare-word refusal names the form expected"

# --title whose value is the next flag, or missing: gh would prompt for it.
OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title --body B 2>&1)
eq "$?" "2" "a --title whose value is the next flag is refused"
eq "$(count)" "0" "nothing is parked when --title has no value"
has "$OUT" "--title" "the refusal names the title as missing"
hasnt "$OUT" "--body" "the present body is not named as missing"

OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --body B --title 2>&1)
eq "$?" "2" "a --title with no value at the end is refused"
has "$OUT" "--title" "the end-of-command title refusal names the title"

# --body whose value is missing, or the next flag: gh would prompt for it.
OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title T --body 2>&1)
eq "$?" "2" "a --body with no value at the end is refused"
eq "$(count)" "0" "nothing is parked when --body has no value"
has "$OUT" "--body" "the refusal names the body as missing"
hasnt "$OUT" "--title" "the present title is not named as missing"

OUT=$("$SUT" --message "why" -- gh issue comment 5 --body --repo a/b 2>&1)
eq "$?" "2" "a --body whose value is the next flag is refused"
has "$OUT" "--body" "the comment body refusal names the body"

# The attached --flag=value form carries its own value and still parks.
reset_state
"$SUT" --message "why" -- gh issue create --repo=get-convex/agent --title=T --body=B >/dev/null 2>&1
eq "$?" "0" "the attached --flag=value form parks"
eq "$(count)" "1" "the attached form parks exactly one bead"
eq "$(meta up-1 gh_target_repo)" "get-convex/agent" "the attached --repo=value resolves as the target"

# ── a subject-scoped write verb needs an explicit issue/PR selector ────────
# `issue comment`, `pr comment`, `pr review` and the other verbs that act on
# one existing issue or PR take it as a positional argument. gh rejects the
# pasted command without one ("accepts 1 arg(s), received 0"), and a pr verb
# with no selector falls back to the current branch — ambient state, not the
# reviewed finding. --repo is always present here, so the selector is required.
reset_state
OUT=$("$SUT" --message "why" -- gh issue comment --repo a/b --body B 2>&1)
eq "$?" "2" "an issue comment with a body but no issue selector is refused"
eq "$(count)" "0" "nothing is parked for a comment that names no issue"
has "$OUT" "specific issue or PR" "the refusal says the command names no target"

OUT=$("$SUT" --message "why" -- gh pr comment --repo a/b --body B 2>&1)
eq "$?" "2" "a pr comment with a body but no PR selector is refused"

OUT=$("$SUT" --message "why" -- gh pr review --repo a/b --approve 2>&1)
eq "$?" "2" "a pr review with no PR selector is refused"

OUT=$("$SUT" --message "why" -- gh --repo a/b issue comment --body B 2>&1)
eq "$?" "2" "the missing selector is caught with --repo before the verb too"

# gh reads the word after a value flag as that flag's value, so a bare --body
# value — even a number — is not the selector.
OUT=$("$SUT" --message "why" -- gh pr review --repo a/b --body "looks like text" 2>&1)
eq "$?" "2" "a --body value is not mistaken for the PR selector"
OUT=$("$SUT" --message "why" -- gh issue comment --repo a/b --body 42 2>&1)
eq "$?" "2" "a numeric --body value is not mistaken for the issue selector"

# With the selector present, the same commands park. The number, a URL, and a
# branch all satisfy it, and a boolean flag before it does not consume it.
reset_state
"$SUT" --message "why" -- gh issue comment 123 --repo get-convex/agent --body "ping" >/dev/null 2>&1
eq "$?" "0" "an issue comment with a number selector parks"
eq "$(count)" "1" "the selector form parks exactly one bead"
eq "$(meta up-1 gh_verb)" "issue comment" "the parked comment records its verb"

reset_state
"$SUT" --message "why" -- gh pr review 45 --repo get-convex/agent --approve >/dev/null 2>&1
eq "$?" "0" "a pr review with a number selector parks"
eq "$(count)" "1" "the review selector form parks one bead"

reset_state
"$SUT" --message "why" -- gh pr review --repo get-convex/agent --approve 45 >/dev/null 2>&1
eq "$?" "0" "a boolean flag does not swallow the selector that follows it"

reset_state
"$SUT" --message "why" -- gh pr comment https://github.com/get-convex/agent/pull/9 --repo get-convex/agent --body "ping" >/dev/null 2>&1
eq "$?" "0" "a URL selector parks"

reset_state
"$SUT" --message "why" -- gh pr comment mybranch --repo get-convex/agent --body "ping" >/dev/null 2>&1
eq "$?" "0" "a branch selector parks"

# ── the own-origin refusal ────────────────────────────────────────────────
reset_state
OUT=$("$SUT" --message "why" -- gh issue create --repo zookanalytics/gc-toolkit --title T --body B 2>&1)
eq "$?" "2" "preparing a send to the rig's own origin is refused"
eq "$(count)" "0" "nothing is filed for our own repo"
has "$OUT" "run the command" "the refusal says to just run it"
OUT=$("$SUT" --message "why" -- gh issue create --repo github.com/ZookAnalytics/GC-Toolkit --title T --body B 2>&1)
eq "$?" "2" "the own-origin match survives host prefix and case"

# ── a public send needs the target's security policy, as read ─────────────
# A parked send is pasted as it stands, so a public one publishes the finding
# the moment it is pasted. It is parked only once the preparer has read the
# target's security policy, and the operator reads that beside the command.
reset_state
OUT=$("$UF" --message "why" -- gh issue create --repo otherowner/widget --title T --body B 2>&1)
eq "$?" "2" "a public send with no security-policy reading is refused"
eq "$(count)" "0" "nothing is parked before the policy is read"
has "$OUT" "--security-policy" "the refusal names the reading it needs"
has "$OUT" "isSecurityPolicyEnabled securityPolicyUrl" "the refusal says how to find the policy"
has "$OUT" "repos/otherowner/widget/private-vulnerability-reporting" "the refusal says how to check for private reporting"
has "$OUT" "gh api --method POST repos/otherowner/widget/security-advisories/reports" "the refusal names this target's private report"
eq "$(< "$STUB_ESC_LOG" wc -l | tr -d ' ')" "0" "no human is asked to paste an unchecked public send"

OUT=$("$UF" --message "why" --security-policy "  " -- gh issue create --repo otherowner/widget --title T --body B 2>&1)
eq "$?" "2" "a blank reading is no reading"
OUT=$("$UF" --message "why" -- gh pr comment 7 --repo otherowner/widget --body B 2>&1)
eq "$?" "2" "a public comment needs the reading too"
eq "$(count)" "0" "nothing is parked for either"

reset_state
READING="SECURITY.md asks for vulnerabilities in private; this is a typo in the docs, not one."
"$UF" --message "why" --security-policy "$READING" \
  -- gh issue create --repo otherowner/widget --title T --body B >/dev/null 2>&1
eq "$?" "0" "a public send carrying the reading parks"
DESC=$(jq -r '.[] | select(.id == "up-1") | .description' "$STUB_STORE")
has "$DESC" "Public: everyone who can see otherowner/widget can read it once it is sent." "the bead says the send is public"
has "$DESC" "Security policy, as read before parking: $READING" "the bead carries the reading"
has "$(cat "$STUB_ESC_LOG")" "Security policy, as read before parking: $READING" "the visit carries the reading beside the command"

# ── a private vulnerability report parks as gh api ────────────────────────
# The private channel a security policy can name that gh reaches. gh api has
# no --repo, so the target is the repository its endpoint path names.
reset_state
REPORT_TEXT='GET /export returns rows the caller cannot read.

Repro: `curl -H "Authorization: $TOKEN" /export?all=1`.'
OUT=$("$UF" --message "why" -- gh api --method POST repos/otherowner/widget/security-advisories/reports \
  -f summary="Export skips the row access check" -f description="$REPORT_TEXT" -f severity=high 2>&1)
eq "$?" "0" "a private vulnerability report parks with no security-policy reading"
eq "$(count)" "1" "the report parks one bead"
has "$OUT" "parked private vulnerability report on otherowner/widget" "it reports the private report it parked"
eq "$(meta up-1 gh_target_repo)" "otherowner/widget" "the target is the repository the endpoint path names"
eq "$(meta up-1 gh_verb)" "api" "the verb is api, not the endpoint"
has "$(jq -r '.[] | select(.id == "up-1") | .title' "$STUB_STORE")" "private vulnerability report on otherowner/widget" "the title names the private channel"
DESC=$(jq -r '.[] | select(.id == "up-1") | .description' "$STUB_STORE")
has "$DESC" "Private: the report goes to the maintainers of otherowner/widget, not to a public page." "the bead says the send is private"
hasnt "$DESC" "Security policy, as read" "a report parked with no reading records none"
has "$(cat "$STUB_ESC_LOG")" "Approve or decline an outbound private vulnerability report on otherowner/widget" "the visit names the private channel"
PARKED=$(meta up-1 gh_command)
eval "set -- $PARKED"
eq "$#" "11" "the parked report re-splits into the same argument count"
eq "$5" "repos/otherowner/widget/security-advisories/reports" "the endpoint survives"
eq "$9" "description=$REPORT_TEXT" "a multi-line report with backticks, quotes and \$ survives verbatim"

# gh's other spellings of the same report park the same way: a leading slash,
# an attached method, attached fields, a lowercase method, and a value flag.
reset_state
"$UF" --message "why" -- gh api /repos/otherowner/widget/security-advisories/reports -XPOST \
  --raw-field=summary=S -fdescription=D >/dev/null 2>&1
eq "$?" "0" "a leading slash, -XPOST and attached fields park"
eq "$(meta up-1 gh_target_repo)" "otherowner/widget" "the leading-slash path still names the target"
reset_state
"$UF" --message "why" -- gh api repos/otherowner/widget/security-advisories/reports --method post \
  -f summary=S --jq .html_url -f description=D >/dev/null 2>&1
eq "$?" "0" "a lowercase method and a value flag among the fields park"
reset_state
"$UF" --message "why" -- gh api --hostname ghe.example.com repos/otherowner/widget/security-advisories/reports \
  -f summary=S -f description=D >/dev/null 2>&1
eq "$(meta up-1 gh_target_repo)" "ghe.example.com/otherowner/widget" "a report sent to another GitHub host names that host in its target"

reset_state
"$UF" --message "why" --security-policy "SECURITY.md asks for a private advisory." \
  -- gh api repos/otherowner/widget/security-advisories/reports -f summary=S -f description=D >/dev/null 2>&1
has "$(jq -r '.[] | select(.id == "up-1") | .description' "$STUB_STORE")" \
  "Security policy, as read before parking: SECURITY.md asks for a private advisory." "a reading given with a report is recorded"

# ── a gh api command that is not a pasteable private report is refused ───
reset_state
OUT=$("$UF" --message "why" -- gh api --method POST 'repos/{owner}/{repo}/security-advisories/reports' -f summary=S -f description=D 2>&1)
eq "$?" "2" "a placeholder endpoint is refused"
has "$OUT" "placeholder fills in from the directory" "the refusal says where a placeholder resolves"

OUT=$("$UF" --message "why" -- gh api --repo otherowner/widget repos/otherowner/widget/security-advisories/reports -f summary=S -f description=D 2>&1)
eq "$?" "2" "gh api with --repo is refused"
has "$OUT" "no --repo flag" "the refusal says gh api takes no --repo"

OUT=$("$UF" --message "why" --security-policy "$POLICY_READ" -- gh api --method POST repos/otherowner/widget/issues -f title=T -f body=B 2>&1)
eq "$?" "2" "a gh api write other than a private report is refused, with a reading or without"
has "$OUT" "got 'repos/otherowner/widget/issues'" "the refusal names the endpoint it got"

OUT=$("$UF" --message "why" -- gh api graphql -f query='mutation { x }' 2>&1)
eq "$?" "2" "a graphql call is refused"

OUT=$("$UF" --message "why" -- gh api repos/otherowner/widget/security-advisories/reports repos/otherowner/widget/issues -f summary=S -f description=D 2>&1)
eq "$?" "2" "a second endpoint is refused"
has "$OUT" "more words after it" "the refusal names the extra word"

OUT=$("$UF" --message "why" -- gh api --method GET repos/otherowner/widget/security-advisories/reports -f summary=S -f description=D 2>&1)
eq "$?" "2" "a report sent as GET is refused"
has "$OUT" "is a POST" "the refusal says a report is a POST"

OUT=$("$UF" --message "why" -- gh api repos/otherowner/widget/security-advisories/reports -f summary=S 2>&1)
eq "$?" "2" "a report with no description is refused"
has "$OUT" "-f description=<the report>" "the refusal names the missing description"
hasnt "$OUT" "-f summary=<one line>" "…and not the summary it carries"
OUT=$("$UF" --message "why" -- gh api repos/otherowner/widget/security-advisories/reports -f description=D -f summary= 2>&1)
eq "$?" "2" "an empty summary is refused"

OUT=$("$UF" --message "why" -- gh api repos/otherowner/widget/security-advisories/reports -f summary=S -F description=@report.md 2>&1)
eq "$?" "2" "-F on gh api is refused"
has "$OUT" "fills {owner} and {repo}" "the refusal says what -F reads besides the text"
OUT=$("$UF" --message "why" -- gh api repos/otherowner/widget/security-advisories/reports -f summary=S -f description=D -Fextra=@/etc/hosts 2>&1)
eq "$?" "2" "-F with its value attached is refused, so pasting reads no local file into the report"
OUT=$("$UF" --message "why" -- gh api repos/otherowner/widget/security-advisories/reports -f summary=S --field=description=@report.md 2>&1)
eq "$?" "2" "--field on gh api is refused"
OUT=$("$UF" --message "why" -- gh api repos/otherowner/widget/security-advisories/reports --input report.json 2>&1)
eq "$?" "2" "--input on gh api is refused"
has "$OUT" "Pass each field inline as a string with -f" "the refusal says how to pass a field"
OUT=$("$UF" --message "why" -- gh api repos/zookanalytics/gc-toolkit/security-advisories/reports -f summary=S -f description=D 2>&1)
eq "$?" "2" "a report to the rig's own origin is refused like any send there"
eq "$(count)" "0" "no refused report is parked"

# ── usage ─────────────────────────────────────────────────────────────────
OUT=$("$SUT" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "2" "--message is required"
OUT=$("$SUT" --message "why" 2>&1)
eq "$?" "2" "a run with no command is refused"
OUT=$("$SUT" --message "why" -- curl -X POST https://example.invalid 2>&1)
eq "$?" "2" "a command that is not gh is refused"
has "$OUT" "must be a \`gh\` invocation" "the refusal names what it accepts"
OUT=$("$SUT" --message "why" --key "bad key" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "2" "a key with characters the dedup read cannot carry is refused"

# ── short flag form ───────────────────────────────────────────────────────
reset_state
"$SUT" --message "why" -- gh issue comment 353 -R get-convex/agent --body "ping" >/dev/null 2>&1
eq "$?" "0" "-R is recognised as --repo"
eq "$(meta up-1 gh_target_repo)" "get-convex/agent" "the -R value is the target"
eq "$(meta up-1 gh_verb)" "issue comment" "a comment verb is labelled as itself"

# ── the pool passthrough ──────────────────────────────────────────────────
reset_state
"$SUT" --message "why" --pool "mycity/gc-toolkit.converse" \
  -- gh issue create --repo a/b --title T --body B >/dev/null 2>&1
has "$(cat "$STUB_ESC_LOG")" "--pool mycity/gc-toolkit.converse" "--pool reaches escalate.sh"

# ── failures that must not report a parked send ───────────────────────────
reset_state
export STUB_ESC_RC=1
OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "1" "a visit that could not be filed fails the run"
has "$OUT" "NO ONE HAS BEEN ASKED" "the failure says the ask never reached a human"
eq "$(count)" "1" "the bead survives the failed escalation, so a re-run reuses it"
unset STUB_ESC_RC

reset_state
export STUB_DROP_KEYS="gh_command"
OUT=$("$SUT" --message "why" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "1" "a command stamp that did not land fails the run"
has "$OUT" "did not read back" "the failure names the unverified stamp"
eq "$(< "$STUB_ESC_LOG" wc -l | tr -d ' ')" "0" "no human is asked to paste a command that is not on the bead"
unset STUB_DROP_KEYS

reset_state
OUT=$(GC_ESCALATE_TOOL="$TMP/nope.sh" "$SUT" --message "why" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "1" "a missing escalate.sh fails the run"
has "$OUT" "NO ONE HAS BEEN ASKED" "a missing escalate.sh says the ask never reached a human"

# ── an unreadable store is not an empty one ───────────────────────────────
reset_state
"$SUT" --message "why" -- gh issue create --repo a/b --title T --body B >/dev/null 2>&1
OUT=$(STUB_LIST_GARBAGE=1 "$SUT" --message "why" -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "0" "a store that cannot be read does not lose the finding"
has "$OUT" "could not read the store" "an unreadable listing is reported, not read as empty"
eq "$(count)" "2" "it files rather than dropping the finding, as the warning says"

# ── a bead that did not read back is not a divergence ─────────────────────
reset_state
"$SUT" --message "why" --key samekey -- gh issue create --repo a/b --title T --body B >/dev/null 2>&1
OUT=$(STUB_SHOW_GARBAGE=1 "$SUT" --message "why" --key samekey -- gh issue create --repo a/b --title T --body B 2>&1)
eq "$?" "1" "a bead whose parked command cannot be read fails the run"
has "$OUT" "not a divergence" "the failure separates a failed read from a changed command"
hasnt "$OUT" "DIFFERENT command" "a failed read is not reported as a changed command"
eq "$(count)" "1" "the unreadable bead is not duplicated under its own key"

# ── against the real escalate.sh ──────────────────────────────────────────
# The stub above proves this script's own behaviour; it cannot catch the two
# scripts disagreeing about flags. This case runs the REAL escalate.sh over the
# same stub store, so a drift in either argv contract fails here.
reset_state
OUT=$(GC_ESCALATE_TOOL="$HERE/escalate.sh" GC_RIG=testrig \
  "$SUT" --message "found while working a bead" --pool "testrig/gc-toolkit.converse" \
  -- gh issue create --repo get-convex/agent --title "T" --body "B" 2>&1)
eq "$?" "0" "the real escalate.sh accepts what this script passes it"
VISIT=$(jq -r '[.[] | select((.metadata.task_kind // "") == "visit")] | .[0].id // ""' "$STUB_STORE")
[ -n "$VISIT" ] && ok "the real escalate.sh filed a visit" || bad "the real escalate.sh filed a visit"
eq "$(meta "$VISIT" "gc.continuation_group")" "up-1" "the visit tracks the parked bead"
eq "$(meta "$VISIT" "gc.routed_to")" "testrig/gc-toolkit.converse" "the pool this script passed is the route the visit carries"
has "$(cat "$STUB_DEPS")" "$VISIT|up-1|tracks" "the visit tracks the bead by edge, not only by metadata"
has "$(jq -r --arg id "$VISIT" '.[] | select(.id == $id) | .description' "$STUB_STORE")" \
  "$(meta up-1 gh_command)" "the visit a human reads carries the pasteable command"
has "$(jq -r --arg id "$VISIT" '.[] | select(.id == $id) | .description' "$STUB_STORE")" \
  "Security policy, as read before parking: $POLICY_READ" "the visit a human reads carries the security-policy reading"

eq "$(< "$STUB_GH_LOG" wc -l | tr -d ' ')" "0" "gh was never invoked by any case"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
