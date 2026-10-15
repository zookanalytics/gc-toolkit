#!/usr/bin/env bash
# work-context-hook.test.sh — hermetic test for the shipped PostToolUse hook
# overlays/work-context/.claude/hooks/work-context.sh.
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
#   (14) a claim whose response carries no bead_id -> silent, even when
#        $GC_TRIGGER_BEAD_ID names an injectable bead. That variable is
#        spawn-fixed, so in a pool it names a bead the worker is not working,
#        and injecting it sends the polecat to do that bead under this claim.
#   (15) every case exits 0 — a hook that fails must never block a tool call
#   (16) a claimed workflow root whose molecule has a step in progress under
#        another session -> released in one write guarded on the claim's
#        assignee and status (route cleared, open, unassigned, a note naming
#        the running session), no step bead written, no formula body injected
#   (17) the same when the live step is open but held by a session, on a root
#        the claim left open, with the claimer read from $GC_SESSION_ID
#   (18) the same when the live step waits in the pool the root came from,
#        between one session's steps and the next
#   (19) an orphaned root, whose only open step is its control-dispatcher
#        finalizer, and a root with no steps at all -> injected as before,
#        nothing written
#   (20) a step claim and an ordinary work bead -> no step listing and no write
#   (21) a refused release (stale guard, exit 13) and a failed one -> no formula
#        body; the notice says nothing was released and, on failure, names the
#        release command
#   (22) a root whose steps cannot be read -> no formula body and no write
#   (23) a root held by a session other than the claimer -> no write

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

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-context-hook-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

# --- gc stub -------------------------------------------------------------
# Serves fixtures from $GCSTUB_DIR: bead-<id>.json, convoy-<id>.json, and
# steps-<root>.json for `bd list --metadata-field gc.root_bead_id=<root>`, which
# like bd leaves out closed beads. steps-<root>.fail makes that listing fail.
# `bd update` applies to bead-<id>.json the way bd does: a stale --if-assignee
# or --if-status exits 13 and writes nothing, and an unguarded assignee change
# on another actor's in_progress claim is refused. update-<id>.rc makes the
# update exit with that code instead. Every call is appended to calls.log.
mkdir -p "$SANDBOX/home/go/bin" "$SANDBOX/fixtures" "$SANDBOX/tmp"
cat > "$SANDBOX/home/go/bin/gc" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GCSTUB_DIR/calls.log"
case "$1 $2" in
    "bd show")     f="$GCSTUB_DIR/bead-$3.json";   [ -f "$f" ] && cat "$f" || echo '[]' ;;
    "convoy status") f="$GCSTUB_DIR/convoy-$3.json"; [ -f "$f" ] && cat "$f" || echo '{}' ;;
    "bd list")
        root=""; prev=""
        for a in "$@"; do
            case "$a" in
                --metadata-field=gc.root_bead_id=*) root="${a#--metadata-field=gc.root_bead_id=}" ;;
                gc.root_bead_id=*) [ "$prev" = "--metadata-field" ] && root="${a#gc.root_bead_id=}" ;;
            esac
            prev="$a"
        done
        [ -n "$root" ] || exit 1
        [ -f "$GCSTUB_DIR/steps-$root.fail" ] && exit 1
        f="$GCSTUB_DIR/steps-$root.json"
        if [ -f "$f" ]; then jq -c '[ .[] | select(.status != "closed") ]' "$f"; else echo '[]'; fi ;;
    "bd update")
        id="$3"; shift 3
        f="$GCSTUB_DIR/bead-$id.json"
        [ -f "$f" ] || { echo "no issue found: $id" >&2; exit 1; }
        [ -f "$GCSTUB_DIR/update-$id.rc" ] && exit "$(cat "$GCSTUB_DIR/update-$id.rc")"
        has_ga=0; ga=""; has_gs=0; gs=""; has_st=0; st=""; has_as=0; as=""; notes=""; meta='{}'
        for a in "$@"; do
            case "$a" in
                --if-assignee=*) has_ga=1; ga="${a#--if-assignee=}" ;;
                --if-status=*) has_gs=1; gs="${a#--if-status=}" ;;
                --status=*) has_st=1; st="${a#--status=}" ;;
                --assignee=*) has_as=1; as="${a#--assignee=}" ;;
                --set-metadata=*) kv="${a#--set-metadata=}"
                    meta="$(printf '%s' "$meta" | jq -c --arg k "${kv%%=*}" --arg v "${kv#*=}" '. + {($k): $v}')" ;;
                --append-notes=*) notes="${a#--append-notes=}" ;;
                *) echo "stub: unsupported bd update argument: $a" >&2; exit 1 ;;
            esac
        done
        cur_a="$(jq -r '.[0].assignee // ""' "$f")"
        cur_s="$(jq -r '.[0].status // ""' "$f")"
        [ "$has_ga" = 1 ] && [ "$cur_a" != "$ga" ] && exit 13
        [ "$has_gs" = 1 ] && [ "$cur_s" != "$gs" ] && exit 13
        if [ "$has_as" = 1 ] && [ "$has_ga" = 0 ] && [ "$cur_s" = "in_progress" ] \
            && [ -n "$cur_a" ] && [ "$cur_a" != "${BEADS_ACTOR:-}" ]; then
            echo "cannot reassign $id: held by $cur_a" >&2; exit 1
        fi
        jq --argjson meta "$meta" --arg notes "$notes" \
            --arg st "$st" --argjson hst "$has_st" --arg as "$as" --argjson has "$has_as" '
            .[0] |= ((if $hst == 1 then .status = $st else . end)
              | (if $has == 1 then .assignee = $as else . end)
              | .metadata = ((.metadata // {}) + $meta)
              | (if $notes == "" then .
                 elif (.notes // "") == "" then .notes = $notes
                 else .notes = .notes + "\n" + $notes end))' \
            "$f" > "$f.tmp" && mv "$f.tmp" "$f" ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$SANDBOX/home/go/bin/gc"

FX="$SANDBOX/fixtures"
bead() { # bead <id> <json>
    printf '%s' "$2" > "$FX/bead-$1.json"
}
steps() { # steps <root-id> <json array of the root's step beads>
    printf '%s' "$2" > "$FX/steps-$1.json"
}
calls() { # calls <pattern>: lines of calls.log that contain <pattern>
    grep -F -e "$1" "$FX/calls.log" 2>/dev/null
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

ctx_of() { # ctx_of <hook stdout>: the injected additionalContext
    printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}
has_text() { # has_text <label> <context> <needle>
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) bad "$1" "wanted '$3' in: ${2:0:400}" ;;
    esac
}
no_body() { # no_body <label> <context>
    case "$2" in
        *FORMULA-BODY-MARKER*) bad "$1: no formula body injected" "context: ${2:0:300}" ;;
        *) ok "$1: no formula body injected" ;;
    esac
}
root_reads() { # root_reads <id>: status|assignee|route of the bead's fixture
    jq -r '.[0] | [.status, (.assignee // ""), ((.metadata // {})["gc.routed_to"] // "<absent>")] | join("|")' \
        "$FX/bead-$1.json" 2>/dev/null
}
released() { # released <label> <root>: the root reads open, unassigned, unrouted
    local got
    got="$(root_reads "$2")"
    [ "$got" = "open||" ] && ok "$1" || bad "$1" "status|assignee|route = $got"
}
unwritten() { # unwritten <label>: calls.log records no bd update
    local u
    u="$(calls 'bd update')"
    [ -z "$u" ] && ok "$1" || bad "$1" "update calls: $u"
}

echo "── injection ──"

# (1)(2)(3)(4) claim of a formula step, real object-shaped tool_response with
# warning noise ahead of the JSON.
: > "$FX/calls.log"
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
# (20) a step is no workflow root: its claim lists no steps and writes nothing.
[ -z "$(calls 'bd list')" ] && ok "step claim: lists no steps" \
    || bad "step claim: lists no steps" "list calls: $(calls 'bd list')"
unwritten "step claim: writes nothing"

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
: > "$FX/calls.log"
out4="$(run_hook "$(claim_payload s2 '{"bead_id":"tk-solo"}')")"
case "$(printf '%s' "$out4" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" in
    *SOLO-MARKER*) ok "non-formula claim: uses the claimed bead itself" ;;
    *) bad "non-formula claim: uses the claimed bead itself" "got: ${out4:0:200}" ;;
esac
# (20) an ordinary work bead carries no gc.kind: no step listing, no write.
[ -z "$(calls 'bd list')" ] && ok "non-formula claim: lists no steps" \
    || bad "non-formula claim: lists no steps" "list calls: $(calls 'bd list')"
unwritten "non-formula claim: writes nothing"

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

echo "── workflow roots ──"

# A molecule root's description is its formula body; FORMULA-BODY-MARKER stands
# for it. Each root below is claimed by a spare session, as the pool hands one
# out. Its finalizer is open and routed to the control dispatcher, which by
# itself does not make a molecule live.
root_fixture() { # root_fixture <id> <status> <assignee> <formula>
    bead "$1" "$(jq -nc --arg id "$1" --arg st "$2" --arg as "$3" --arg f "$4" \
        '[{id: $id, title: $f, status: $st, assignee: $as,
           description: "FORMULA-BODY-MARKER: load context, set up the worktree, implement",
           metadata: {"gc.kind": "workflow", "gc.formula_name": $f,
                      "gc.routed_to": "gc-toolkit/gc-toolkit.polecat"}}]')"
}
FINAL='"status":"open","metadata":{"gc.step_ref":"mol-polecat-work.workflow-finalize","gc.kind":"workflow-finalize","gc.routed_to":"gc-toolkit/core.control-dispatcher"}'

# (16) a step in progress under the running session.
root_fixture tk-liveroot in_progress lx-spare mol-polecat-work
steps tk-liveroot '[
  {"id":"tk-lr-load","status":"closed","assignee":"lx-runner","metadata":{"gc.root_bead_id":"tk-liveroot","gc.step_ref":"mol-polecat-work.load-context","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-lr-impl","status":"in_progress","assignee":"lx-runner","metadata":{"gc.root_bead_id":"tk-liveroot","gc.step_ref":"mol-polecat-work.implement","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-lr-final",'"$FINAL"'}]'
: > "$FX/calls.log"
out16="$(run_hook "$(claim_payload s16 '{"schema_version":"1","ok":true,"action":"work","reason":"claimed","bead_id":"tk-liveroot","assignee":"lx-spare","route":"gc-toolkit/gc-toolkit.polecat"}')")"
rc16="$RUN_RC"
ctx16="$(ctx_of "$out16")"
[ "$rc16" -eq 0 ] && ok "live root: exit 0" || bad "live root: exit 0" "rc=$rc16"
[ "$(printf '%s' "$out16" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)" = "PostToolUse" ] \
    && ok "live root: stdout is one PostToolUse object" \
    || bad "live root: stdout is one PostToolUse object" "got: ${out16:0:200}"
no_body "live root" "$ctx16"
has_text "live root: names the running step and its session" "$ctx16" \
    "mol-polecat-work.implement (tk-lr-impl) in progress under lx-runner"
has_text "live root: says the claim was released" "$ctx16" "released the claim"
has_text "live root: sends the session back to the hook" "$ctx16" "gc hook --claim --json again"
released "live root: reads open, unassigned and unrouted" tk-liveroot
case "$(jq -r '.[0].notes // ""' "$FX/bead-tk-liveroot.json")" in
    *"work-context hook"*lx-spare*"in progress under lx-runner"*) ok "live root: the note names the claimer and the running session" ;;
    *) bad "live root: the note names the claimer and the running session" "notes: $(jq -r '.[0].notes // ""' "$FX/bead-tk-liveroot.json")" ;;
esac
upd16="$(calls 'bd update')"
case "$upd16" in
    "bd update tk-liveroot "*"--if-assignee=lx-spare"*"--if-status=in_progress"*)
        [ "$(printf '%s\n' "$upd16" | grep -c .)" -eq 1 ] \
            && ok "live root: one write, guarded on the claim's assignee and status" \
            || bad "live root: one write, guarded on the claim's assignee and status" "update calls: $upd16" ;;
    *) bad "live root: one write, guarded on the claim's assignee and status" "update calls: $upd16" ;;
esac
[ -z "$(calls 'bd update tk-lr-')" ] && ok "live root: no step bead written" \
    || bad "live root: no step bead written" "$(calls 'bd update tk-lr-')"

# (16) a step in progress that names no session and no route still counts.
root_fixture tk-busyroot in_progress lx-spare1 mol-polecat-work
steps tk-busyroot '[{"id":"tk-br-impl","status":"in_progress","metadata":{"gc.root_bead_id":"tk-busyroot","gc.step_ref":"mol-polecat-work.implement"}},{"id":"tk-br-final",'"$FINAL"'}]'
ctx16b="$(ctx_of "$(run_hook "$(claim_payload s16b '{"bead_id":"tk-busyroot","assignee":"lx-spare1","route":"gc-toolkit/gc-toolkit.polecat"}')")")"
no_body "root with an unowned step in progress" "$ctx16b"
has_text "root with an unowned step in progress: names the step" "$ctx16b" \
    "mol-polecat-work.implement (tk-br-impl) in progress"
released "root with an unowned step in progress: reads open, unassigned and unrouted" tk-busyroot

# (17) the live step is open and held by the running session, under a route of
# its own; the claim left the root open, and its response names no assignee,
# so $GC_SESSION_ID names the claimer.
root_fixture tk-heldroot open lx-spare2 mol-feedback-distiller
steps tk-heldroot '[
  {"id":"tk-hr-gate","status":"closed","assignee":"lx-runner2","metadata":{"gc.root_bead_id":"tk-heldroot","gc.step_ref":"mol-feedback-distiller.load-and-gate"}},
  {"id":"tk-hr-judge","status":"open","assignee":"lx-runner2","metadata":{"gc.root_bead_id":"tk-heldroot","gc.step_ref":"mol-feedback-distiller.judge-and-cluster","gc.routed_to":"gc-toolkit/gc-toolkit.furiosa"}}]'
: > "$FX/calls.log"
ctx17="$(ctx_of "$(run_hook "$(claim_payload s17 '{"action":"work","reason":"ready_assignment","bead_id":"tk-heldroot"}')" GC_SESSION_ID="lx-spare2")")"
no_body "held root" "$ctx17"
has_text "held root: names the step and its holder" "$ctx17" \
    "mol-feedback-distiller.judge-and-cluster (tk-hr-judge) held by lx-runner2"
released "held root: reads open, unassigned and unrouted" tk-heldroot
has_text "held root: the write is guarded on the open status it read" "$(calls 'bd update tk-heldroot')" \
    "--if-assignee=lx-spare2 --if-status=open"

# (18) between two sessions: implement has closed and the self-review
# iteration waits in the pool the root was claimed from.
root_fixture tk-gaproot in_progress lx-spare3 mol-polecat-work
steps tk-gaproot '[
  {"id":"tk-gr-impl","status":"closed","assignee":"lx-runner3","metadata":{"gc.root_bead_id":"tk-gaproot","gc.step_ref":"mol-polecat-work.implement","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-gr-iter","status":"open","metadata":{"gc.root_bead_id":"tk-gaproot","gc.step_ref":"self-review.iteration.1","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-gr-final",'"$FINAL"'}]'
: > "$FX/calls.log"
ctx18="$(ctx_of "$(run_hook "$(claim_payload s18 '{"bead_id":"tk-gaproot","assignee":"lx-spare3","route":"gc-toolkit/gc-toolkit.polecat"}')")")"
no_body "root between sessions" "$ctx18"
has_text "root between sessions: names the step waiting in the pool" "$ctx18" \
    "self-review.iteration.1 (tk-gr-iter) waiting in the pool"
released "root between sessions: reads open, unassigned and unrouted" tk-gaproot

# (19) an orphaned root: its steps have closed and only the finalizer is open.
# It is injected as before, under the work-bead header, and left as claimed.
root_fixture tk-orphanroot in_progress lx-spare4 mol-polecat-work
steps tk-orphanroot '[
  {"id":"tk-or-impl","status":"closed","assignee":"lx-gone","metadata":{"gc.root_bead_id":"tk-orphanroot","gc.step_ref":"mol-polecat-work.implement","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-or-final",'"$FINAL"'}]'
: > "$FX/calls.log"
ctx19="$(ctx_of "$(run_hook "$(claim_payload s19 '{"bead_id":"tk-orphanroot","assignee":"lx-spare4","route":"gc-toolkit/gc-toolkit.polecat"}')")")"
has_text "orphaned root: injected as before" "$ctx19" "Work bead tk-orphanroot"
has_text "orphaned root: carries its description" "$ctx19" "FORMULA-BODY-MARKER"
unwritten "orphaned root: writes nothing"
[ "$(root_reads tk-orphanroot)" = "in_progress|lx-spare4|gc-toolkit/gc-toolkit.polecat" ] \
    && ok "orphaned root: stays as claimed" \
    || bad "orphaned root: stays as claimed" "status|assignee|route = $(root_reads tk-orphanroot)"

# (19) a root with no steps at all, the shape of a root that is itself the work.
root_fixture tk-soloroot in_progress lx-spare5 mol-root-only
: > "$FX/calls.log"
ctx19b="$(ctx_of "$(run_hook "$(claim_payload s19b '{"bead_id":"tk-soloroot","assignee":"lx-spare5"}')")")"
has_text "root with no steps: injected as before" "$ctx19b" "Work bead tk-soloroot"
unwritten "root with no steps: writes nothing"

# (21) the release is refused: bd's guard found the root changed since the read.
root_fixture tk-raceroot in_progress lx-spare6 mol-polecat-work
steps tk-raceroot '[{"id":"tk-rr-impl","status":"in_progress","assignee":"lx-runner6","metadata":{"gc.root_bead_id":"tk-raceroot","gc.step_ref":"mol-polecat-work.implement"}}]'
printf '13' > "$FX/update-tk-raceroot.rc"
out21="$(run_hook "$(claim_payload s21 '{"bead_id":"tk-raceroot","assignee":"lx-spare6"}')")"
rc21="$RUN_RC"
ctx21="$(ctx_of "$out21")"
[ "$rc21" -eq 0 ] && ok "refused release: exit 0" || bad "refused release: exit 0" "rc=$rc21"
no_body "refused release" "$ctx21"
has_text "refused release: says nothing was written" "$ctx21" "wrote nothing"

# (21) the release fails: the notice names the release to run by hand.
root_fixture tk-failroot in_progress lx-spare7 mol-polecat-work
steps tk-failroot '[{"id":"tk-fr-impl","status":"in_progress","assignee":"lx-runner7","metadata":{"gc.root_bead_id":"tk-failroot","gc.step_ref":"mol-polecat-work.implement"}}]'
printf '1' > "$FX/update-tk-failroot.rc"
ctx21b="$(ctx_of "$(run_hook "$(claim_payload s21b '{"bead_id":"tk-failroot","assignee":"lx-spare7"}')")")"
no_body "failed release" "$ctx21b"
has_text "failed release: says the release failed" "$ctx21b" "could not release the claim (gc bd update exited 1)"
has_text "failed release: names the guarded release" "$ctx21b" \
    "gc bd update tk-failroot --if-assignee=lx-spare7 --if-status=in_progress"

# (22) the steps cannot be read, so nothing proves the molecule dead or live.
root_fixture tk-blindroot in_progress lx-spare8 mol-polecat-work
: > "$FX/steps-tk-blindroot.fail"
: > "$FX/calls.log"
out22="$(run_hook "$(claim_payload s22 '{"bead_id":"tk-blindroot","assignee":"lx-spare8"}')")"
rc22="$RUN_RC"
ctx22="$(ctx_of "$out22")"
[ "$rc22" -eq 0 ] && ok "unreadable steps: exit 0" || bad "unreadable steps: exit 0" "rc=$rc22"
no_body "unreadable steps" "$ctx22"
has_text "unreadable steps: says the steps could not be read" "$ctx22" "could not read its steps"
unwritten "unreadable steps: writes nothing"

# (23) the root is held by a session other than the one this claim names.
root_fixture tk-otherroot in_progress lx-someone mol-polecat-work
steps tk-otherroot '[{"id":"tk-ot-impl","status":"in_progress","assignee":"lx-runner9","metadata":{"gc.root_bead_id":"tk-otherroot","gc.step_ref":"mol-polecat-work.implement"}}]'
: > "$FX/calls.log"
ctx23="$(ctx_of "$(run_hook "$(claim_payload s23 '{"bead_id":"tk-otherroot","assignee":"lx-spare9"}')")")"
no_body "root another session holds" "$ctx23"
has_text "root another session holds: says it did not release it" "$ctx23" "did not release it"
unwritten "root another session holds: writes nothing"

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

# (14) a claim that printed no bead_id, which is what a redirected or swallowed
# stdout looks like. $GC_TRIGGER_BEAD_ID is spawn-fixed and survives every later
# claim, so a pool worker's copy names a bead it is not working.
noid="$(jq -nc '{session_id: "s7", tool_name: "Bash",
    tool_input: {command: "gc hook --claim --json > /dev/shm/claim.txt 2>&1"},
    tool_response: {stdout: "", stderr: "", interrupted: false}}')"
out12="$(run_hook "$noid" GC_TRIGGER_BEAD_ID="tk-solo")"
[ -z "$out12" ] && ok "claim with no bead_id: silent despite a stale trigger id" \
    || bad "claim with no bead_id: silent despite a stale trigger id" "got: ${out12:0:200}"
[ "$RUN_RC" -eq 0 ] && ok "claim with no bead_id: exit 0" \
    || bad "claim with no bead_id: exit 0" "rc=$RUN_RC"

echo
echo "work-context-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
