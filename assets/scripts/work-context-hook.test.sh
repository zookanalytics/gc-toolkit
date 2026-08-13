#!/usr/bin/env bash
# work-context-hook.test.sh — hermetic test for the shipped PostToolUse hook
# overlays/work-context/.claude/hooks/work-context.sh (tk-osf13).
#
# The hook injects a work bead's description into the polecat's context right
# after the bead is claimed, because upstream mol-polecat-work reads the bead
# only through jq-filtered metadata queries and its `implement` step never reads
# the description at all. Every failure mode of that hook is SILENT by design —
# it exits 0 and prints nothing rather than blocking a tool call — so nothing at
# runtime can distinguish "correctly stayed quiet" from "broken and stayed
# quiet". That is exactly what this test exists to tell apart.
#
# It runs the SHIPPED script (never a copy), so the fixtures cannot drift from
# what polecats actually execute. Hermetic: no live city, no Dolt, no network.
# `gc` is stubbed by pointing HOME at a sandbox — the hook prepends
# "$HOME/go/bin" to PATH itself, so a stub placed there wins over the real gc.
#
# The test lives under assets/scripts/ rather than beside the hook because
# everything under overlays/work-context/.claude/ is STAGED into every polecat's
# work dir at session start; a test file there would ship to production sessions.
#
# Covered:
#   (1)  claim of a formula step -> resolves step->root->convoy->work bead and
#        injects that bead's description
#   (2)  emitted stdout is one valid JSON object with hookEventName=PostToolUse
#   (3)  tool_response as a Bash OBJECT ({stdout:...}) still yields the bead id.
#        This is the REAL payload shape: jq's tojson re-escapes the JSON the
#        command printed, so a scanner written against a bare string matches
#        nothing and the hook silently injects nothing forever.
#   (4)  city.toml warning noise ahead of the JSON does not defeat extraction
#   (5)  second claim in the same session -> silent (no duplicate injection)
#   (6)  a DIFFERENT work bead in the same session -> injects again
#   (7)  non-claim Bash command -> silent (the common path)
#   (8)  claimed bead with no gc.root_bead_id -> treated as the work bead itself
#   (9)  empty description -> silent (no empty banner)
#   (10) over-long description -> truncated with a pointer, and the WHOLE payload
#        is bounded. `cut -c` caps per LINE, so a multi-line description would
#        sail past an unbounded cap; this asserts the byte bound really holds.
#   (11) non-polecat template (refinery) -> silent
#   (12) non-claude provider -> silent
#   (13) empty/malformed stdin -> silent, exit 0
#   (14) every case exits 0 — a hook that fails must never block a tool call

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
HOOK="$REPO/overlays/work-context/.claude/hooks/work-context.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

if [ ! -s "$HOOK" ]; then
    echo "FATAL: missing hook script: $HOOK" >&2
    exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# --- gc stub -------------------------------------------------------------
# Serves fixtures from $GCSTUB_DIR: bead-<id>.json, convoy-<id>.json.
mkdir -p "$SANDBOX/home/go/bin" "$SANDBOX/fixtures" "$SANDBOX/tmp"
cat > "$SANDBOX/home/go/bin/gc" <<'STUB'
#!/bin/sh
case "$1 $2" in
    "bd show")     f="$GCSTUB_DIR/bead-$3.json";   [ -f "$f" ] && cat "$f" || echo '[]' ;;
    "convoy status") f="$GCSTUB_DIR/convoy-$3.json"; [ -f "$f" ] && cat "$f" || echo '{}' ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$SANDBOX/home/go/bin/gc"

FX="$SANDBOX/fixtures"
bead() { # bead <id> <json>
    printf '%s' "$2" > "$FX/bead-$1.json"
}

# A claimed formula step -> its workflow root -> the root's input convoy -> the
# single tracked member, which is the work bead.
bead tk-step1 '[{"id":"tk-step1","title":"Load context","metadata":{"gc.root_bead_id":"tk-root"}}]'
bead tk-root  '[{"id":"tk-root","title":"mol-polecat-work","metadata":{"gc.input_convoy_id":"tk-convoy"}}]'
printf '%s' '{"children":[{"id":"tk-work"}]}' > "$FX/convoy-tk-convoy.json"
bead tk-work  '[{"id":"tk-work","title":"Real bead title","description":"## Problem\nSPEC-MARKER-BODY\n\n## Asked-for fix\ndo the thing"}]'

# A bead claimed outside any formula: no gc.root_bead_id.
bead tk-solo  '[{"id":"tk-solo","title":"Standalone","description":"SOLO-MARKER"}]'

# Empty description.
bead tk-bare  '[{"id":"tk-bare","title":"Title only","description":""}]'

# Over-long, MULTI-LINE description: 400 lines x ~60 chars ~= 24000 chars, every
# line short. A per-line cap leaves this untouched; a byte cap bounds it.
{
    printf '[{"id":"tk-long","title":"Long","description":"'
    i=0
    while [ "$i" -lt 400 ]; do
        printf 'LONGLINE-%03d-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\n' "$i"
        i=$((i + 1))
    done
    printf 'TAIL-MARKER"}]'
} > "$FX/bead-tk-long.json"

# --- runner --------------------------------------------------------------
# Returns the hook's stdout; records exit status in RUN_RC.
RUN_RC=0
run_hook() { # run_hook <payload> [env assignments...]
    local payload="$1"; shift
    local out
    out="$(printf '%s' "$payload" | env -i \
        HOME="$SANDBOX/home" \
        PATH="/usr/bin:/bin" \
        TMPDIR="$SANDBOX/tmp" \
        GCSTUB_DIR="$FX" \
        GC_PROVIDER="claude" \
        GC_TEMPLATE="gc-toolkit/gc-toolkit.polecat" \
        "$@" \
        sh "$HOOK" 2>/dev/null)"
    RUN_RC=$?
    printf '%s' "$out"
}

claim_payload() { # claim_payload <session> <bead-id-json-blob>
    jq -nc --arg s "$1" --arg stdout "$2" \
        '{session_id: $s, tool_name: "Bash",
          tool_input: {command: "gc hook --claim --json"},
          tool_response: {stdout: $stdout, stderr: "", interrupted: false}}'
}

echo "── injection ──"

# (1)(2)(3)(4) claim of a formula step, real object-shaped tool_response with
# warning noise ahead of the JSON.
out="$(run_hook "$(claim_payload s1 'note: city.toml unreadable
{"schema_version":"1","ok":true,"bead_id":"tk-step1","assignee":"x"}')")"
rc="$RUN_RC"
[ "$rc" -eq 0 ] && ok "step claim: exit 0" || bad "step claim: exit 0" "rc=$rc"
if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    ok "step claim: stdout is valid JSON"
else
    bad "step claim: stdout is valid JSON" "got: ${out:0:200}"
fi
evt="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)"
[ "$evt" = "PostToolUse" ] && ok "step claim: hookEventName=PostToolUse" \
    || bad "step claim: hookEventName=PostToolUse" "got: '$evt'"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
case "$ctx" in
    *SPEC-MARKER-BODY*) ok "step claim: injects the WORK bead's description" ;;
    *) bad "step claim: injects the WORK bead's description" "context: ${ctx:0:200}" ;;
esac
case "$ctx" in
    *tk-work*) ok "step claim: names the work bead" ;;
    *) bad "step claim: names the work bead" "context: ${ctx:0:200}" ;;
esac
case "$ctx" in
    *"Real bead title"*) ok "step claim: carries the title" ;;
    *) bad "step claim: carries the title" "context: ${ctx:0:200}" ;;
esac

echo "── idempotence ──"

# (5) same session, same work bead -> silent.
out2="$(run_hook "$(claim_payload s1 '{"bead_id":"tk-step1"}')")"
[ -z "$out2" ] && ok "repeat claim in same session: silent" \
    || bad "repeat claim in same session: silent" "got: ${out2:0:120}"
[ "$RUN_RC" -eq 0 ] && ok "repeat claim: exit 0" || bad "repeat claim: exit 0" "rc=$RUN_RC"

# (6) same session, DIFFERENT work bead -> injects again.
out3="$(run_hook "$(claim_payload s1 '{"bead_id":"tk-solo"}')")"
case "$(printf '%s' "$out3" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" in
    *SOLO-MARKER*) ok "different bead, same session: injects again" ;;
    *) bad "different bead, same session: injects again" "got: ${out3:0:200}" ;;
esac

echo "── resolution ──"

# (8) no gc.root_bead_id -> the claimed bead IS the work bead (fresh session).
out4="$(run_hook "$(claim_payload s2 '{"bead_id":"tk-solo"}')")"
case "$(printf '%s' "$out4" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" in
    *SOLO-MARKER*) ok "non-formula claim: uses the claimed bead itself" ;;
    *) bad "non-formula claim: uses the claimed bead itself" "got: ${out4:0:200}" ;;
esac

# (9) empty description -> silent.
out5="$(run_hook "$(claim_payload s3 '{"bead_id":"tk-bare"}')")"
[ -z "$out5" ] && ok "empty description: silent" \
    || bad "empty description: silent" "got: ${out5:0:120}"

# (10) over-long multi-line description -> bounded + pointer.
out6="$(run_hook "$(claim_payload s4 '{"bead_id":"tk-long"}')")"
ctx6="$(printf '%s' "$out6" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
n="${#ctx6}"
if [ "$n" -gt 0 ] && [ "$n" -lt 13000 ]; then
    ok "long description: whole payload bounded ($n chars)"
else
    bad "long description: whole payload bounded" "got $n chars; a per-line cap does not bound a multi-line body"
fi
case "$ctx6" in
    *truncated*) ok "long description: names the truncation" ;;
    *) bad "long description: names the truncation" "context tail: ${ctx6: -120}" ;;
esac
case "$ctx6" in
    *TAIL-MARKER*) bad "long description: tail dropped" "TAIL-MARKER survived a 12000-char cap" ;;
    *) ok "long description: tail dropped" ;;
esac

echo "── gates ──"

# (7) not a claim -> silent.
notclaim="$(jq -nc '{session_id: "s9", tool_name: "Bash",
    tool_input: {command: "git status --short"},
    tool_response: {stdout: "", stderr: ""}}')"
out7="$(run_hook "$notclaim")"
[ -z "$out7" ] && ok "non-claim command: silent" || bad "non-claim command: silent" "got: ${out7:0:120}"

# (11) non-polecat role -> silent.
out8="$(run_hook "$(claim_payload s5 '{"bead_id":"tk-solo"}')" GC_TEMPLATE="gc-toolkit/gc-toolkit.refinery")"
[ -z "$out8" ] && ok "refinery template: silent" || bad "refinery template: silent" "got: ${out8:0:120}"

# (12) non-claude provider -> silent (this overlay is Claude-only).
out9="$(run_hook "$(claim_payload s6 '{"bead_id":"tk-solo"}')" GC_PROVIDER="codex")"
[ -z "$out9" ] && ok "codex provider: silent" || bad "codex provider: silent" "got: ${out9:0:120}"

# (13) empty stdin, and malformed stdin.
out10="$(run_hook "")"
[ -z "$out10" ] && ok "empty stdin: silent" || bad "empty stdin: silent" "got: ${out10:0:120}"
[ "$RUN_RC" -eq 0 ] && ok "empty stdin: exit 0" || bad "empty stdin: exit 0" "rc=$RUN_RC"
out11="$(run_hook 'not json at all --claim')"
[ -z "$out11" ] && ok "malformed stdin: silent" || bad "malformed stdin: silent" "got: ${out11:0:120}"
[ "$RUN_RC" -eq 0 ] && ok "malformed stdin: exit 0" || bad "malformed stdin: exit 0" "rc=$RUN_RC"

echo
echo "work-context-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
