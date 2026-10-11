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
#   - each copy routes to the board (POOL="human", the literal the board's
#     gather matches on gc.routed_to == "human") or to a pool proved by
#     pool-route.sh against the live agent set; either way the conditional rig
#     prefix that renders bare for a rig-less caller is gone (a pool offer is
#     read by exact string equality, so a bare address sits silently forever)
#   - the three metadata stamps are each present and load-bearing, riding
#     either their own --set-metadata flag (comma-joined pairs become one
#     garbage value, so each rides its own) or a key in the create's jq-built
#     --metadata JSON (which stamps the identity atomically with the create, so
#     an interrupted stamp cannot leave a visit its dedup can never match)
#   - the visit is wired to its subject with a tracks edge (parent-child
#     would transmit the subject's blocked state to the visit)
#   - the visit title carries the "visit: " brand
#   - the create's id is guarded before use (an unguarded empty id
#     cascades into stamping nothing, and the silent failure is what
#     tempts agents to rewrite the block instead of re-running it)
#   - every FORMULA copy reuses the conversation visit already open on its
#     subject instead of filing a second one, and never reuses an escalate.sh
#     visit; this one is executed against every formula copy, because a step
#     re-run is exactly when the block runs twice. The two script copies keep
#     their own dedup outside the markers (gc-helm.sh open folds into any open
#     visit; escalate.sh keys on subject and escalation_key), and their own
#     tests cover it.
# Hermetic: reads the repo only; no gc, no city.
#
# run-tests-scope: tree

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
FDIR="$REPO/formulas"
SDIR="$REPO/assets/scripts"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
have() { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing: $2"; fi; }

# A load-bearing stamp rides EITHER its own --set-metadata flag (the own-flag
# form guards the comma-joined-pairs trap) OR a key in the create's jq-built
# --metadata JSON, which cannot hit that trap and stamps the identity atomically
# with the create. Accept both. $2 is the --set-metadata ERE, $3 the JSON key ERE.
stamped() { # <block> <set-metadata-ERE> <json-key-ERE>
    printf '%s' "$1" | grep -qE -- "$2" && return 0
    printf '%s' "$1" | grep -qF -- '--metadata "' \
        && printf '%s' "$1" | grep -qE -- "\"$3\"[[:space:]]*:" && return 0
    return 1
}

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
                     *)       SCRIPT_CONSUMERS=$((SCRIPT_CONSUMERS + 1)) ;; esac
        name="$(basename "$f") block $n"
        tmp="$(mktemp "${TMPDIR:-/tmp}/gctk-gate-visit-test.XXXXXX")"
        # neutralize template placeholders so bash can parse the copy
        printf '%s\n' "$block" | sed 's/{{[a-z_]*}}/X/g' > "$tmp"
        if bash -n "$tmp" 2>/dev/null; then ok "$name: valid bash"; else bad "$name: valid bash" "bash -n failed"; fi
        # Leading whitespace tolerated: a copy living inside a shell function
        # (gc-helm.sh's cmd_open) is legitimately indented, and an assertion
        # anchored at column 0 would report a correct POOL line as "absent".
        # A gate-visit copy routes EITHER to the board (POOL="human", the retired
        # converse pool's replacement; the board's gather matches
        # gc.routed_to == "human" exactly) OR to a pool proved by pool-route.sh
        # (a fix/rework or polecat pool that survives). EVERY POOL assignment is
        # checked, not the first: a copy that resolves the route and then
        # overwrites POOL is back where it started. (escalate.sh reassigns POOL
        # from --pool, but through pool-route.sh, so it too is a guarded call.)
        pool_lines="$(grep -E '^[[:space:]]*POOL=' "$tmp" || true)"
        unproved="$(printf '%s\n' "$pool_lines" \
            | grep -vE 'POOL="human"|POOL=\$\(.*POOL_ROUTE.*\)[[:space:]]*\|\|[[:space:]]*exit' || true)"
        if [ -n "$pool_lines" ] && [ -z "$unproved" ]; then
            ok "$name: every POOL assignment is the board literal or a guarded pool-route.sh call"
        else
            bad "$name: every POOL assignment is the board literal or a guarded pool-route.sh call" \
                "POOL line(s): ${pool_lines:-absent}"
        fi
        # The construct the resolver replaces must be GONE, not merely unused:
        # GC_RIG picks both the store the visit lands in and the rig segment a
        # rig-scoped pool carries, so a copy that rebuilds the address itself
        # renders it bare for a rig-less caller and files a visit nobody holds.
        case "$block" in
            *'${GC_RIG:+$GC_RIG/}'*)
                bad "$name: no conditional rig prefix" "the copy still builds an address out of GC_RIG" ;;
            *)  ok "$name: no conditional rig prefix" ;;
        esac
        # ...and a copy that RESOLVES a pool through the resolver must name the
        # SHARED one. A copy is free to bind it outside its own markers
        # (escalate.sh does), so the file carries the proof, not the block. A
        # board-only copy (POOL="human") resolves no pool and needs none.
        if printf '%s\n' "$pool_lines" | grep -qE 'POOL=\$\(.*POOL_ROUTE'; then
            if grep -qF 'pool-route.sh' "$f"; then
                ok "$name: POOL_ROUTE names the shared resolver"
            else
                bad "$name: POOL_ROUTE names the shared resolver" "no pool-route.sh anywhere in $f"
            fi
        else
            ok "$name: board route resolves no pool"
        fi
        printf '%s' "$block" | grep -qE 'gc bd create -t task --title "visit: ' \
            && ok "$name: visit title brand" || bad "$name: visit title brand" 'no `--title "visit: …"` create'
        stamped "$block" '--set-metadata "gc\.routed_to=\$POOL"' 'gc\.routed_to' \
            && ok "$name: routed_to stamped (own flag or create --metadata)" \
            || bad "$name: routed_to stamped" "no gc.routed_to via --set-metadata or the create's --metadata"
        stamped "$block" '--set-metadata "gc\.continuation_group=' 'gc\.continuation_group' \
            && ok "$name: continuation_group stamped (own flag or create --metadata)" \
            || bad "$name: continuation_group stamped" "no gc.continuation_group via --set-metadata or the create's --metadata"
        stamped "$block" '--set-metadata "task_kind=visit"' 'task_kind' \
            && ok "$name: task_kind stamped (own flag or create --metadata)" \
            || bad "$name: task_kind stamped" "no task_kind via --set-metadata or the create's --metadata"
        printf '%s' "$block" | grep -qF -- '[ -n "$VISIT" ] && [ "$VISIT" != "null" ]' \
            && ok "$name: create id guarded before use" || bad "$name: create id guarded before use" 'no `[ -n "$VISIT" ] && [ "$VISIT" != "null" ]` guard after the create'
        # bd states why it refused a create in the {"error": ...} object it
        # answers on stdout, so a copy that finds no id reads that reason out;
        # without it the operator learns only that no id came back.
        printf '%s' "$block" | grep -qF -- '(.error // empty)' \
            && ok "$name: a refused create reports bd's own reason" \
            || bad "$name: a refused create reports bd's own reason" "no read of the refusal's .error in the copy"
        printf '%s' "$block" | grep -q -- '--type=tracks' \
            && ok "$name: tracks edge (non-blocking lineage)" || bad "$name: tracks edge (non-blocking lineage)" "dep add --type=tracks missing"
        printf '%s' "$block" | grep -q -- '--type=parent-child' \
            && bad "$name: no parent-child edge" "parent-child transmits the subject's block to the visit" || ok "$name: no parent-child edge"
        # The group stamp is READ BACK and repaired: it can land
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
                "found $n_readback read-back(s), want 2 — one to detect the lost stamp and one to say whether the repair landed"
        fi
        # ...and the read-back must REPAIR, not refuse: this block files the
        # one visit for its scope, so exiting on a lost stamp trades a quiet
        # degradation for an outage of the same surface. The re-stamp grep is
        # scoped to the read-back arm (GROUP_GOT onward): the block's initial
        # stamp carries the same '--set-metadata "gc.continuation_group="', so a
        # block-wide grep stays green with the read-back's re-stamp deleted.
        printf '%s' "$block" | sed -n '/GROUP_GOT=/,$p' | grep -qF -- '--set-metadata "gc.continuation_group=' \
            && printf '%s' "$block" | grep -qE 'warning: gc\.continuation_group .* — repairing"' \
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
# Worker prompts carry no gate-visit copy: they are doctrine and defer the
# dispose mechanics to their formula (proactive → mol-first-reaction's
# advance-and-drain), so the formula and script sweeps above cover every
# shipped copy.

echo "── the read-back actually repairs (executed, not grepped) ──"
# The assertions above prove the TEXT is present; none proves the logic works,
# and the block exists to turn a silent failure into a loud one. So the
# canonical copy is extracted and RUN against a stub, once per outcome.
EXTMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gate-visit-test.XXXXXX")"
trap 'rm -rf "$EXTMP"' EXIT
mkdir -p "$EXTMP/bin"
cat > "$EXTMP/bin/gc" <<'GVSTUB'
#!/usr/bin/env bash
# Serves the reads the block makes. LOST=1 makes the first stamp vanish —
# the observed failure: the update returns 0 and the value reads back empty.
# $AGENTS is the live identity set the route is proved against; an arm that
# answered nothing would read as UNREADABLE, which fails open and would take
# the whole route check out of this suite. $LIST_JSON is the file the open-visit
# listing answers with; unset, the listing answers nothing, as a store with no
# open visit does.
case "$1 ${2:-}" in
  "agent list") printf '%s\n' "${AGENTS:-}" ;;
  "bd list")   printf 'LIST %s\n' "$*" >> "$LOG"
               if [ -n "${LIST_JSON:-}" ]; then cat "$LIST_JSON"; fi ;;
  "bd create") printf 'CREATE %s\n' "$*" >> "$LOG"
               # The title and body as bd received them, for the bound checks.
               while [ $# -gt 0 ]; do
                 case "$1" in
                   --title) printf '%s' "${2:-}" > "$STATE/title"; shift ;;
                   -d)      printf '%s' "${2:-}" > "$STATE/body"; shift ;;
                 esac
                 shift
               done
               # CREATE answers the ways bd does: the bead as an object (the
               # default) or as an array holding it, or a refusal, which is an
               # {"error": ...} object on stdout and exit 1.
               case "${CREATE:-object}" in
                 array)   echo '[{"id":"v-1"}]' ;;
                 refused) printf '{\n  "error": "%s",\n  "schema_version": 1\n}\n' "$REFUSAL"; exit 1 ;;
                 *)       echo '{"id":"v-1"}' ;;
               esac ;;
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
# The canonical copy parks on the board (POOL="human", the retired converse
# pool's replacement) and resolves no pool, so this run exercises the create and
# the continuation_group repair, not a route. The route-refusal proof lives with
# the surviving pool-route.sh call sites (escalate.test.sh executes it).
# The block locates visit-identity.sh through GC_PACK_DIR, GC_RIG_ROOT, the git
# toplevel and GC_CITY_PATH, in that order. Each run pins all four, so the copy
# in this repo answers and an ambient city's copy never does.
run_block_gv() { # <LOST> -> stdout+stderr of the block; $EXTMP/log side-effects
    rm -rf "$EXTMP/state"; mkdir -p "$EXTMP/state"; : > "$EXTMP/log"
    PATH="$EXTMP/bin:$PATH" LOG="$EXTMP/log" STATE="$EXTMP/state" LOST="$1" GC_RIG=rig \
        GC_PACK_DIR="" GC_RIG_ROOT="$REPO" GC_CITY_PATH="" LIST_JSON="" \
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

# The canonical copy bound to subject sub-A and a given visit text, in
# $EXTMP/block-v.sh. Bash substitution rather than sed, because the text
# carries newlines and multi-byte characters.
render_gv() { # <visit-text>
    local raw
    raw="$(awk '/# >>> gate-visit/{f = 1; next} /# <<< gate-visit/{f = 0} f' "$FDIR/mol-visit.toml")"
    raw="${raw//\{\{subject\}\}/sub-A}"
    raw="${raw//\{\{visit\}\}/"$1"}"
    printf '%s\n' "$raw" > "$EXTMP/block-v.sh"
}
# Pinned like run_block_gv: the open-visit listing answers nothing, so the
# block files, and only this repo's visit-identity.sh is in reach.
run_gv() { # <CREATE answer: object|array|refused> -> OUT, RC; title/body in $EXTMP/state
    rm -rf "$EXTMP/state"; mkdir -p "$EXTMP/state"; : > "$EXTMP/log"
    OUT="$(PATH="$EXTMP/bin:$PATH" LOG="$EXTMP/log" STATE="$EXTMP/state" LOST=0 CREATE="$1" \
        REFUSAL='validation failed: validation failed for issue : title must be 500 characters or less (got 544)' \
        GC_PACK_DIR="" GC_RIG_ROOT="$REPO" GC_CITY_PATH="" LIST_JSON="" \
        bash "$EXTMP/block-v.sh" 2>&1)"; RC=$?
}

echo "── the create's answer is read whatever its shape (executed) ──"
render_gv "why"
run_gv object
if [ "$RC" = 0 ] && [ "$(cat "$EXTMP/state/title")" = "visit: sub-A — why" ]; then
    ok "a short visit is the title tail verbatim"
else
    bad "a short visit is the title tail verbatim" "rc=$RC, title: $(cat "$EXTMP/state/title" 2>/dev/null)"
fi
run_gv array
if [ "$RC" = 0 ] && grep -q 'DEP .* add v-1 sub-A --type=tracks' "$EXTMP/log"; then
    ok "an array answer yields the id, and the visit is wired"
else
    bad "an array answer yields the id, and the visit is wired" "rc=$RC, out: $OUT"
fi
run_gv refused
if [ "$RC" != 0 ]; then ok "a refused create stops the block"; else bad "a refused create stops the block" "exited 0: $OUT"; fi
case "$OUT" in
    *"title must be 500 characters or less"*) ok "…and reports bd's own reason" ;;
    *) bad "…and reports bd's own reason" "the refusal's .error is not in: $OUT" ;;
esac
case "$OUT" in
    *"Cannot index"* | *"jq: error"*) bad "…and no jq error stands in for it" "jq leaked: $OUT" ;;
    *) ok "…and no jq error stands in for it" ;;
esac
if grep -qE '^(UPDATE|DEP) ' "$EXTMP/log"; then
    bad "…and nothing is stamped or wired" "wrote to a bead that does not exist: $(cat "$EXTMP/log")"
else
    ok "…and nothing is stamped or wired"
fi

echo "── a long visit is bounded in the title and whole in the body (executed) ──"
# Over bd's 500-byte title cap on its own, with a newline and a tab to collapse.
LONG_VISIT="$(printf 'word%.0s ' $(seq 1 150))
second	line   here"
render_gv "$LONG_VISIT"
run_gv object
TITLE="$(cat "$EXTMP/state/title" 2>/dev/null)"
TAIL="${TITLE#visit: sub-A — }"
if [ "$RC" = 0 ] && [ "$(wc -c < "$EXTMP/state/title")" -le 500 ]; then
    ok "the title fits bd's 500-byte cap ($(wc -c < "$EXTMP/state/title") bytes)"
else
    bad "the title fits bd's 500-byte cap" "rc=$RC, $(wc -c < "$EXTMP/state/title" 2>/dev/null) bytes: $OUT"
fi
case "$TITLE" in
    *$'\n'* | *$'\t'*) bad "…on one line" "the title kept a newline or tab: $TITLE" ;;
    *) ok "…on one line" ;;
esac
if [ "$TAIL" != "$TITLE" ] && [ "$(printf '%s' "$TAIL" | jq -Rsr length)" -le 140 ]; then
    ok "…with the board headline cap on its tail"
else
    bad "…with the board headline cap on its tail" "tail: $TAIL"
fi
case "$TAIL" in
    *…) ok "…marking the cut with an ellipsis" ;;
    *) bad "…marking the cut with an ellipsis" "tail: $TAIL" ;;
esac
if cmp -s <(printf '%s' "$LONG_VISIT") "$EXTMP/state/body"; then
    ok "the body keeps the full visit text"
else
    bad "the body keeps the full visit text" "body: $(cat "$EXTMP/state/body" 2>/dev/null)"
fi
# bd counts bytes, so 140 characters of 4-byte text would overrun the cap.
render_gv "$(printf '\360\237\230\200%.0s' $(seq 1 200))"
run_gv object
if [ "$RC" = 0 ] && [ "$(wc -c < "$EXTMP/state/title")" -le 500 ]; then
    ok "a tail in 4-byte characters fits the byte cap too ($(wc -c < "$EXTMP/state/title") bytes)"
else
    bad "a tail in 4-byte characters fits the byte cap too" "rc=$RC, $(wc -c < "$EXTMP/state/title" 2>/dev/null) bytes"
fi

echo "── a conversation visit already open on the subject is reused (executed) ──"
# One listing per row shape the reuse has to judge. A row is a visit on sub-A
# unless its arguments say otherwise; "-" is a visit with no tracks edge.
visit_row() { # <id> <status> <tracks-target|-> <group-stamp> [escalation_key] [task_kind]
    jq -nc --arg id "$1" --arg st "$2" --arg t "$3" --arg g "$4" --arg k "${5:-}" --arg tk "${6:-visit}" '
      { id: $id, status: $st,
        metadata: ({task_kind: $tk, "gc.continuation_group": $g}
                   + (if $k == "" then {} else {escalation_key: $k} end)),
        dependencies: (if $t == "-" then [] else [{type: "tracks", depends_on_id: $t}] end) }'
}
listing() { # <name> <row>... — writes the rows as one array to $EXTMP/list-<name>.json
    ls_name="$1"; shift
    printf '%s\n' "$@" | jq -sc '.' > "$EXTMP/list-$ls_name.json"
}
listing open        "$(visit_row v-9 open sub-A sub-A)"
listing in-progress "$(visit_row v-9 in_progress sub-A sub-A)"
listing edge-only   "$(visit_row v-9 open sub-A "")"
listing stamp-only  "$(visit_row v-9 open - sub-A)"
listing two         "$(visit_row v-7 open sub-A sub-A)" "$(visit_row v-3 open sub-A sub-A)"
listing keyed       "$(visit_row v-9 open sub-A sub-A deferred-dispatch-sling-failed)"
listing other       "$(visit_row v-9 open sub-B sub-B)"
listing stale-stamp "$(visit_row v-9 open sub-B sub-A)"
listing closed      "$(visit_row v-9 closed sub-A sub-A)"
listing not-a-visit "$(visit_row v-9 open sub-A sub-A "" task)"
printf 'not json\n' > "$EXTMP/list-unreadable.json"

# The canonical copy again, now reporting the visit it ended on.
{ cat "$EXTMP/block.sh"; printf '%s\n' 'printf "RESULT %s\n" "$VISIT"'; } > "$EXTMP/block-result.sh"
run_reuse() { # <script> <listing-name> [VAR=value...] -> stdout+stderr; $EXTMP/log side-effects
    rr_script="$1"; rr_list="$2"; shift 2
    rm -rf "$EXTMP/state"; mkdir -p "$EXTMP/state"; : > "$EXTMP/log"
    env PATH="$EXTMP/bin:$PATH" LOG="$EXTMP/log" STATE="$EXTMP/state" LOST=0 \
        GC_PACK_DIR="" GC_RIG_ROOT="$REPO" GC_CITY_PATH="" LIST_JSON="$EXTMP/list-$rr_list.json" \
        WORK_BEAD_ID=sub-A SUBJECT=sub-A "$@" bash "$rr_script" 2>&1
}
creates() { cr_n=$(grep -c '^CREATE ' "$EXTMP/log" 2>/dev/null); echo "${cr_n:-0}"; }
result_of() { printf '%s\n' "$1" | sed -n 's/^RESULT //p' | tail -n 1; }
reuse_case() { # <listing-name> <reuse:<id>|file> <label>
    out="$(run_reuse "$EXTMP/block-result.sh" "$1")"
    case "$2" in
        reuse:*)
            if [ "$(creates)" = "0" ] && [ "$(result_of "$out")" = "${2#reuse:}" ]; then ok "$3"
            else bad "$3" "want ${2#reuse:} reused and nothing created; got VISIT='$(result_of "$out")' after $(creates) create(s): $out"; fi ;;
        file)
            if [ "$(creates)" = "1" ] && [ "$(result_of "$out")" = "v-1" ]; then ok "$3"
            else bad "$3" "want one fresh visit (v-1); got VISIT='$(result_of "$out")' after $(creates) create(s): $out"; fi ;;
    esac
}
reuse_case open        reuse:v-9 "an open conversation visit on the subject is reused, and nothing is filed"
reuse_case in-progress reuse:v-9 "…as is one a sitting holds (in_progress)"
reuse_case edge-only   reuse:v-9 "…matched by its tracks edge when its group stamp landed empty"
reuse_case stamp-only  reuse:v-9 "…or by its group stamp when it has no tracks edge"
reuse_case two         reuse:v-3 "…and of two, the lowest id (the tiebreak converse's fold uses)"
reuse_case keyed       file      "an escalate.sh visit (escalation_key) never stands in — the block files its own"
reuse_case other       file      "a visit on another subject is not reused"
reuse_case stale-stamp file      "a stale group stamp beside a tracks edge to another subject does not match"
reuse_case closed      file      "a closed row the listing let through is not reused"
reuse_case not-a-visit file      "a non-visit row the listing let through is not reused"
reuse_case unreadable  file      "a listing that does not read files anyway"

OUT_REUSE="$(run_reuse "$EXTMP/block-result.sh" open)"
case "$OUT_REUSE" in
    *"visit v-9 is already open on sub-A"*) ok "the reuse is reported, not silent" ;;
    *) bad "the reuse is reported, not silent" "no reuse line in: $OUT_REUSE" ;;
esac
if grep -qE '^(UPDATE|DEP) ' "$EXTMP/log"; then
    bad "a reused visit is neither re-stamped nor re-wired" "$(cat "$EXTMP/log")"
else
    ok "a reused visit is neither re-stamped nor re-wired"
fi
if grep -qE '^LIST bd list --status=open,in_progress --metadata-field task_kind=visit( |$)' "$EXTMP/log"; then
    ok "the listing reads open and in_progress visits"
else
    bad "the listing reads open and in_progress visits" "listing call: $(grep '^LIST ' "$EXTMP/log" || echo none)"
fi
OUT_NOVI="$(run_reuse "$EXTMP/block-result.sh" open \
    GC_RIG_ROOT="$EXTMP/none" GC_CITY_PATH="$EXTMP/none" GIT_DIR="$EXTMP/none")"
if [ "$(creates)" = "1" ]; then
    case "$OUT_NOVI" in
        *"visit-identity.sh not found"*) ok "with no visit-identity.sh in reach the block says so and files" ;;
        *) bad "with no visit-identity.sh in reach the block says so and files" "filed without a warning: $OUT_NOVI" ;;
    esac
else
    bad "with no visit-identity.sh in reach the block says so and files" "$(creates) create(s): $OUT_NOVI"
fi

echo "── every formula copy reuses the open visit and files past an escalation (executed) ──"
# A step re-run is when a copy runs twice, so each formula copy is run, not
# grepped: its subject variable is bound, the board stub answers, and the run
# must end on the open visit (no create) and, beside only an escalation visit,
# on a fresh one.
COPIES_RUN=0
mkdir -p "$EXTMP/copies"
for f in "$FDIR"/*.toml; do
    awk -v out="$EXTMP/copies/$(basename "$f" .toml)" \
        '/# >>> gate-visit/{n++; f = 1; next} /# <<< gate-visit/{f = 0} f {print > (out "-" n ".sh")}' "$f"
done
for c in "$EXTMP"/copies/*.sh; do
    [ -f "$c" ] || continue
    name="$(basename "$c" .sh)"
    { sed 's/{{subject}}/sub-A/g; s/{{visit}}/why/g; s/{{binding_prefix}}/gc-toolkit./g' "$c"
      printf '%s\n' 'printf "RESULT %s\n" "$VISIT"'; } > "$c.run"
    COPIES_RUN=$((COPIES_RUN + 1))
    out="$(run_reuse "$c.run" open)"
    if [ "$(creates)" = "0" ] && [ "$(result_of "$out")" = "v-9" ]; then
        ok "$name: a second run reuses the conversation visit already open"
    else
        bad "$name: a second run reuses the conversation visit already open" "VISIT='$(result_of "$out")' after $(creates) create(s): $out"
    fi
    out="$(run_reuse "$c.run" keyed)"
    if [ "$(creates)" = "1" ] && [ "$(result_of "$out")" = "v-1" ]; then
        ok "$name: an open escalation visit does not stand in for it"
    else
        bad "$name: an open escalation visit does not stand in for it" "VISIT='$(result_of "$out")' after $(creates) create(s): $out"
    fi
done
if [ "$COPIES_RUN" -gt 0 ] && [ "$COPIES_RUN" -eq "$FORMULA_CONSUMERS" ]; then
    ok "every formula copy was run ($COPIES_RUN)"
else
    bad "every formula copy was run" "ran $COPIES_RUN of $FORMULA_CONSUMERS formula copies"
fi

echo "── consumer census ──"
if [ "$FORMULA_CONSUMERS" -ge 3 ]; then
    ok "the known formula consumers carry marked copies ($FORMULA_CONSUMERS found)"
else
    bad "the known formula consumers carry marked copies" "expected >=3 (mol-visit, mol-feedback-distiller, mol-validate-close); found $FORMULA_CONSUMERS"
fi
if [ "$SCRIPT_CONSUMERS" -ge 1 ]; then
    ok "the script surface carries marked copies ($SCRIPT_CONSUMERS found)"
else
    bad "the script surface carries marked copies" "expected >=1 (gc-helm.sh open files the operator's visit); found $SCRIPT_CONSUMERS — did a copy get unmarked or hand-rolled?"
fi

echo
echo "gate-visit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
