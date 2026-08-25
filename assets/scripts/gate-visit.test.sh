#!/usr/bin/env bash
# gate-visit.test.sh — regression test for the canonical gate-visit snippet
# and every consumer copy (spec: specs/2026-08-fresh-start/
# liveness-and-triage-spec.md §1; precedent: host-bead-skip.test.sh).
#
# Formula bodies are plain string substitution — there is no include
# mechanism — so the gate-visit convention lives as marker-delimited
# copies (# >>> gate-visit / # <<< gate-visit). This test extracts every
# copy from formulas/*.toml AND assets/scripts/*.sh — the convention is not
# formulas-only; gc-helm.sh's `open` verb carries the copy the operator front
# doors actually reach — and asserts the load-bearing invariants each stamp
# carries (each has a silent-failure trap the pack has paid for):
#   - the pool is the rig-qualified exact-match form (bare names sit
#     silently forever on the exact-string read side)
#   - the three metadata stamps ride one --set-metadata flag each
#     (comma-joined pairs become one garbage value)
#   - the visit is wired to its subject with a tracks edge (parent-child
#     would transmit the subject's blocked state to the visit)
#   - the visit title carries the "visit: " brand
#   - the create's id is guarded before use (an unguarded empty id
#     cascades into stamping nothing, and the silent failure is what
#     tempts agents to rewrite the block instead of re-running it)
# Hermetic: reads the repo only; no gc, no city.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
FDIR="$REPO/formulas"
SDIR="$REPO/assets/scripts"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
have() { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing: $2"; fi; }

extract() { # extract marked blocks from one file to stdout, blocks separated by \x1e
    awk '/# >>> gate-visit/{inb=1; next} /# <<< gate-visit/{inb=0; printf "\x1e"; next} inb' "$1"
}

echo "── canonical copy lives in mol-visit.toml ──"
CANON="$(extract "$FDIR/mol-visit.toml" | tr -d '\x1e')"
if [ -n "$CANON" ]; then ok "canonical block present"; else bad "canonical block present" "no marked block in mol-visit.toml"; fi

echo "── every consumer copy carries the invariants ──"
# CONSUMERS counts every marked copy checked; FORMULA_CONSUMERS and
# SCRIPT_CONSUMERS split that by surface so each census can assert its own
# floor (a formula copy going missing must not be masked by a script copy
# appearing, or the reverse).
CONSUMERS=0; FORMULA_CONSUMERS=0; SCRIPT_CONSUMERS=0; PROMPT_CONSUMERS=0
# check_file <path> — assert the invariants on every marked copy in one file.
# Fed by a heredoc, NOT a pipe: a pipe would run the loop in a subshell and
# the counters would come back zero.
check_file() {
    f="$1"
    blocks="$(extract "$f")"
    [ -n "$blocks" ] || return 0
    n=0
    while IFS= read -r -d $'\x1e' block; do
        [ -n "$(printf '%s' "$block" | tr -d '[:space:]')" ] || continue
        n=$((n + 1)); CONSUMERS=$((CONSUMERS + 1))
        case "$f" in *.toml)              FORMULA_CONSUMERS=$((FORMULA_CONSUMERS + 1)) ;;
                     *prompt.template.md) PROMPT_CONSUMERS=$((PROMPT_CONSUMERS + 1)) ;;
                     *)                   SCRIPT_CONSUMERS=$((SCRIPT_CONSUMERS + 1)) ;; esac
        name="$(basename "$f") block $n"
        tmp="$(mktemp)"
        # neutralize template placeholders so bash can parse the copy
        printf '%s\n' "$block" | sed 's/{{[a-z_]*}}/X/g' > "$tmp"
        if bash -n "$tmp" 2>/dev/null; then ok "$name: valid bash"; else bad "$name: valid bash" "bash -n failed"; fi
        # Leading whitespace tolerated: a copy living inside a shell function
        # (gc-helm.sh's cmd_open) is legitimately indented, and an assertion
        # anchored at column 0 would report a correct POOL line as "absent".
        pool_line="$(grep -E '^[[:space:]]*POOL=' "$tmp" || true)"
        case "$pool_line" in
            *'${GC_RIG:+$GC_RIG/}'*converse\") ok "$name: rig-qualified converse pool" ;;
            *) bad "$name: rig-qualified converse pool" "POOL line: ${pool_line:-absent}" ;;
        esac
        printf '%s' "$block" | grep -qE 'gc bd create -t task --title "visit: ' \
            && ok "$name: visit title brand" || bad "$name: visit title brand" 'no `--title "visit: …"` create'
        printf '%s' "$block" | grep -qF -- '--set-metadata "gc.routed_to=$POOL"' \
            && ok "$name: routed_to stamp, own flag" || bad "$name: routed_to stamp, own flag" "stamp absent or malformed"
        printf '%s' "$block" | grep -qE -- '--set-metadata "gc\.continuation_group=' \
            && ok "$name: continuation_group stamp, own flag" || bad "$name: continuation_group stamp, own flag" "stamp absent or malformed"
        printf '%s' "$block" | grep -qF -- '--set-metadata "task_kind=visit"' \
            && ok "$name: task_kind stamp, own flag" || bad "$name: task_kind stamp, own flag" "stamp absent or malformed"
        printf '%s' "$block" | grep -qF -- '[ -n "$VISIT" ] && [ "$VISIT" != "null" ]' \
            && ok "$name: create id guarded before use" || bad "$name: create id guarded before use" 'no `[ -n "$VISIT" ] && [ "$VISIT" != "null" ]` guard after the create'
        printf '%s' "$block" | grep -q -- '--type=tracks' \
            && ok "$name: tracks edge (non-blocking lineage)" || bad "$name: tracks edge (non-blocking lineage)" "dep add --type=tracks missing"
        printf '%s' "$block" | grep -q -- '--type=parent-child' \
            && bad "$name: no parent-child edge" "parent-child transmits the subject's block to the visit" || ok "$name: no parent-child edge"
        # The group stamp is READ BACK and repaired (tk-ax6y4): it can land
        # present-but-empty while sibling stamps in the same update land, and
        # an empty group disables converse's group-scoped re-claim fence.
        # TWO reads, counted: the first detects the lost stamp, the second
        # verifies the repair — a presence grep would stay green with the
        # detect read dropped, checking nothing.
        n_readback=$(printf '%s' "$block" | grep -cF -- 'GROUP_GOT=$(gc bd show "$VISIT" --json')
        if [ "${n_readback:-0}" -ge 2 ]; then
            ok "$name: group stamp read back, then re-read to verify the repair ($n_readback)"
        else
            bad "$name: group stamp read back, then re-read to verify the repair" \
                "found $n_readback read-back(s), want 2 — one to detect the lost stamp and one to say whether the repair landed (tk-ax6y4)"
        fi
        # ...and the read-back must REPAIR, not refuse: this block files the
        # one visit for its scope, so exiting on a lost stamp trades a quiet
        # degradation for an outage of the same surface.
        printf '%s' "$block" | grep -qF -- '--set-metadata "gc.continuation_group=' \
            && printf '%s' "$block" | grep -qE 'repairing \(tk-ax6y4\)' \
            && ok "$name: the read-back repairs and warns" \
            || bad "$name: the read-back repairs and warns" 'the read-back must re-stamp the group and warn, never exit'
        if printf '%s' "$block" | sed -n '/GROUP_GOT=/,$p' | grep -qE '(^|[^A-Za-z0-9_])exit[[:space:]]+[0-9]'; then
            bad "$name: the read-back never exits" 'a lost stamp must not abort the pass — the visit would never be filed at all'
        else
            ok "$name: the read-back never exits"
        fi
        rm -f "$tmp"
    done <<EOF2
$blocks
EOF2
}

for f in "$FDIR"/*.toml; do check_file "$f"; done
# The convention is not formulas-only: assets/scripts/gc-helm.sh's `open` verb
# carries a marked copy too, and it is the one the OPERATOR front doors reach
# (gc-visit-open.sh delegates its direct path to it rather than copying the
# block again). An unchecked copy is exactly how drift starts, so the script
# surface is swept on the same terms.
for f in "$SDIR"/*.sh; do
    case "$f" in *.test.sh) continue ;; esac    # tests quote the block; they do not ship it
    check_file "$f"
done
# ...and the PROMPT surface: agents/proactive ships a marked copy to an agent
# the same way a formula copy ships to a molecule, and an unswept copy is
# where a fix lands everywhere and still misses one.
for f in "$REPO"/agents/*/prompt.template.md; do
    [ -r "$f" ] || continue
    check_file "$f"
done

echo "── the read-back actually repairs (executed, not grepped) ──"
# The assertions above prove the TEXT is present; none proves the logic works,
# and the block exists to turn a silent failure into a loud one. So the
# canonical copy is extracted and RUN against a stub, once per outcome.
EXTMP="$(mktemp -d)"
trap 'rm -rf "$EXTMP"' EXIT
mkdir -p "$EXTMP/bin"
cat > "$EXTMP/bin/gc" <<'GVSTUB'
#!/usr/bin/env bash
# Serves the reads the block makes. LOST=1 makes the first stamp vanish —
# the observed failure: the update returns 0 and the value reads back empty.
case "$1 ${2:-}" in
  "bd create") echo '{"id":"v-1"}' ;;
  "bd update") printf 'UPDATE %s\n' "$*" >> "$LOG"
               case "$*" in *gc.continuation_group=*)
                 if [ -f "$STATE/stamped" ]; then touch "$STATE/repaired"; else touch "$STATE/stamped"; fi ;;
               esac ;;
  "bd dep")    printf 'DEP %s\n' "$*" >> "$LOG" ;;
  "bd show")   if [ "${LOST:-0}" = 1 ] && [ ! -f "$STATE/repaired" ]; then
                 echo '[{"id":"v-1","metadata":{"gc.continuation_group":""}}]'
               else
                 echo '[{"id":"v-1","metadata":{"gc.continuation_group":"sub-A"}}]'
               fi ;;
esac
exit 0
GVSTUB
chmod +x "$EXTMP/bin/gc"
# The canonical copy with its placeholders bound to a subject. awk directly,
# not extract(): the record separator extract() appends must not ride into a
# script that gets EXECUTED.
awk '/# >>> gate-visit/{f = 1; next} /# <<< gate-visit/{f = 0} f' "$FDIR/mol-visit.toml" \
    | sed 's/{{subject}}/sub-A/g; s/{{visit}}/why/g; s/{{binding_prefix}}/gc-toolkit./g' \
    > "$EXTMP/block.sh"
run_block_gv() { # <LOST> -> stdout+stderr of the block; $EXTMP/log side-effects
    rm -rf "$EXTMP/state"; mkdir -p "$EXTMP/state"; : > "$EXTMP/log"
    env PATH="$EXTMP/bin:$PATH" LOG="$EXTMP/log" STATE="$EXTMP/state" LOST="$1" GC_RIG=rig \
        bash "$EXTMP/block.sh" 2>&1
}
group_writes() { grep -c 'gc.continuation_group=' "$EXTMP/log" 2>/dev/null || echo 0; }

OUT_OK="$(run_block_gv 0)"
if [ "$(group_writes)" = "1" ]; then
    ok "a stamp that lands is written once and says nothing"
else
    bad "a stamp that lands is written once and says nothing" "wrote it $(group_writes) time(s); a repair fired on the happy path"
fi
case "$OUT_OK" in
    *warning:*) bad "the happy path is silent" "warned anyway: $OUT_OK" ;;
    *)          ok "the happy path is silent" ;;
esac

OUT_LOST="$(run_block_gv 1)"
case "$OUT_LOST" in
    *"warning: gc.continuation_group"*) ok "a lost stamp is reported, not swallowed" ;;
    *) bad "a lost stamp is reported, not swallowed" "no warning in: $OUT_LOST" ;;
esac
if [ "$(group_writes)" = "2" ]; then
    ok "…and re-stamped from the subject the block already holds"
else
    bad "…and re-stamped from the subject the block already holds" "wrote it $(group_writes) time(s), want 2 (original + repair)"
fi
case "$OUT_LOST" in
    *"the repair landed"*) ok "…and the outcome of the repair is stated" ;;
    *) bad "…and the outcome of the repair is stated" "no landed/not-landed line in: $OUT_LOST" ;;
esac
# The point of repairing rather than refusing: the visit still gets filed.
if grep -q 'DEP .*--type=tracks' "$EXTMP/log"; then
    ok "a lost stamp does not cost the pass — the visit is still filed and wired"
else
    bad "a lost stamp does not cost the pass" "the tracks edge was never added; the block aborted on a recoverable write loss"
fi

echo "── consumer census ──"
if [ "$FORMULA_CONSUMERS" -ge 3 ]; then
    ok "the known formula consumers carry marked copies ($FORMULA_CONSUMERS found)"
else
    bad "the known formula consumers carry marked copies" "expected >=3 (mol-visit, mol-first-reaction, mol-feedback-distiller); found $FORMULA_CONSUMERS"
fi
if [ "$SCRIPT_CONSUMERS" -ge 1 ]; then
    ok "the script surface carries marked copies ($SCRIPT_CONSUMERS found)"
else
    bad "the script surface carries marked copies" "expected >=1 (gc-helm.sh open files the operator's visit); found $SCRIPT_CONSUMERS — did a copy get unmarked or hand-rolled?"
fi
if [ "$PROMPT_CONSUMERS" -ge 1 ]; then
    ok "the prompt surface carries marked copies ($PROMPT_CONSUMERS found)"
else
    bad "the prompt surface carries marked copies" "expected >=1 (agents/proactive files a first-reaction visit); found $PROMPT_CONSUMERS — an unswept copy is where a fix lands everywhere and still misses one"
fi

echo
echo "gate-visit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
