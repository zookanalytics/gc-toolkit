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
CONSUMERS=0; FORMULA_CONSUMERS=0; SCRIPT_CONSUMERS=0
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
        case "$f" in *.toml) FORMULA_CONSUMERS=$((FORMULA_CONSUMERS + 1)) ;;
                     *)      SCRIPT_CONSUMERS=$((SCRIPT_CONSUMERS + 1)) ;; esac
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

echo "── consumer census ──"
if [ "$FORMULA_CONSUMERS" -ge 4 ]; then
    ok "all four known formula consumers carry marked copies ($FORMULA_CONSUMERS found)"
else
    bad "all four known formula consumers carry marked copies" "expected >=4 (mol-visit, mol-first-reaction, mol-liveness-sweep, mol-triage-recurrence); found $FORMULA_CONSUMERS"
fi
if [ "$SCRIPT_CONSUMERS" -ge 1 ]; then
    ok "the script surface carries marked copies ($SCRIPT_CONSUMERS found)"
else
    bad "the script surface carries marked copies" "expected >=1 (gc-helm.sh open files the operator's visit); found $SCRIPT_CONSUMERS — did a copy get unmarked or hand-rolled?"
fi

echo
echo "gate-visit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
