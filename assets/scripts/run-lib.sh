#!/usr/bin/env bash
# run-lib.sh — the single definition of how a workflow run links to the bead it
# works: the bead a run works, and the runs that work a bead. Sourced, never
# executed.
#
# A run is a workflow root and the steps poured beneath it. Gas City pours a
# graph.v2 run over an input convoy: the root names the convoy in
# gc.input_convoy_id, and the convoy tracks the bead the run works. A classic
# molecule names no convoy and records its bead in its issue variable,
# gc.var.issue. So a run works the one bead its input convoy tracks, or, when
# its root names no convoy, the bead its issue variable names. A convoy that
# tracks no bead, or more than one, names none, and so does a convoy the store
# does not return. A root whose issue variable names a bead its convoy does not
# track names none either: the run is wired wrong, and a reader that picked a
# side would act on a guess. A run is live until its root closes.
#
# Gas City leaves the bead a run works open, unassigned and unrouted, so this
# link is the only thing that tells a bead under a run from one waiting for
# work. Each formula step derives its own bead with `gc convoy status
# {{convoy_id}}`, which is Gas City's contract. Every other reader of the link
# asks this file.
#
# Three verbs, each printing one JSON array of runs, each run
#   {root, convoy, bead, formula, live}
# where convoy is "" for a root that names none, bead is "" for a run that
# names none, and formula is the root's gc.formula_name, "" when it records
# none:
#   run_lib runs <reader> <bead>    every run that works <bead>, live or not
#   run_lib subject <reader> <id>   the run <id> is the root of, or every run
#                                   poured over <id> when it is an input
#                                   convoy; [] for any other bead, and for one
#                                   the store does not return
#   run_lib map <reader> [all]      every live run in the store, or every run
#                                   with `all`, for a caller that judges many
#                                   beads in one pass
# <reader> is a command the caller defines: given bd's own arguments, it runs
# `gc bd` or `bd` against the caller's one store, with the pinning and time
# bound the caller needs, and exits non-zero when the read fails. A read that
# fails or does not parse fails the verb, which then prints nothing and returns
# 1, so no caller reads a failed read as no runs. A usage error returns 2.
#
# $RUN_JQ holds the rule as jq defs, for a caller that judges rows it has
# already read: run_is_root, run_convoy, run_tracked, run_of($convoys) and
# run_rows. It follows the in-variable jq convention (dispatch-path.sh).
#
# Readers: step-close.sh takes the live run poured over a step's --convoy as the
# molecule it closes in. The work-context hook takes the bead a claimed step's
# run works, and self-review-check.sh and gascity-keeper's rebase-check.sh take
# the bead their check loop's run works, which is the bead they certify.
# work-tree-holder.sh takes the bead each claimed step's run works when it asks
# whether a live session is working a tree. gate-ensure.sh takes the runs
# poured over a review, live or not, to judge whether a pour still drives it.
#
# run-lib.test.sh runs every verb over run-lib.fixture.json, the cases a copy
# of the rule in another language must agree with, as the Go copy in
# services/helm/internal/source/facts.go does in its fixture test. The suite
# fails when a reader stops sourcing this file or a file defines the rule's
# defs itself.
#
# A caller sources it beside itself, through a variable its suite can point at
# a stub of the verbs:
#   # shellcheck source=run-lib.sh
#   . "${GC_RUN_LIB:-$SCRIPTS_DIR/run-lib.sh}" || { echo "$PROG: cannot source run-lib.sh" >&2; exit 1; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# How many convoy ids one read of convoy rows names, so a map of every run
# never builds an argument the store refuses.
RUN_LIB_ID_BATCH=200

# shellcheck disable=SC2016,SC2034  # jq source, its $names are jq's; read by the scripts that source this file
RUN_JQ='
  def run_meta: if (.metadata | type) == "object" then .metadata else {} end;
  def run_str($k): (run_meta[$k] // "") | tostring | gsub("^[[:space:]]+|[[:space:]]+$"; "");
  # A workflow root: a graph.v2 root, as Gas City marks one, or a classic
  # molecule.
  def run_is_root:
    (run_str("gc.kind") | ascii_downcase) == "workflow"
    or (run_str("gc.formula_contract") | ascii_downcase) == "graph.v2"
    or (((.issue_type // "") | tostring) == "molecule");
  # The input convoy a root names, "" when it names none.
  def run_convoy: run_str("gc.input_convoy_id");
  # The beads a convoy row tracks, from either shape bd prints an edge in: a
  # listing gives {depends_on_id, type}, a show gives {id, dependency_type}.
  def run_tracked:
    [ (.dependencies // [])[]? | objects
      | select(((.dependency_type // .type // "") | tostring) == "tracks")
      | ((.depends_on_id // .id // "") | tostring) | select(. != "") ] | unique;
  # The run this root row is, over $convoys, an object keyed by convoy id that
  # holds each convoy row the store returned.
  def run_of($convoys):
    run_convoy as $c
    | run_str("gc.var.issue") as $issue
    | (if $c == "" then $issue
       else (($convoys[$c] // null) | if . == null then [] else run_tracked end) as $t
         | (if ($t | length) == 1 then $t[0] else "" end) as $m
         | if $issue != "" and $issue != $m then "" else $m end
       end) as $bead
    | { root: ((.id // "") | tostring), convoy: $c, bead: $bead,
        formula: run_str("gc.formula_name"),
        live: (((.status // "") | tostring | ascii_downcase) != "closed") };
  # The runs among an array of rows: each root among them, over the convoys
  # among them, once each.
  def run_rows:
    [ .[]? | objects ] as $rows
    | ([ $rows[] | select(((.issue_type // "") | tostring) == "convoy")
         | {key: ((.id // "") | tostring), value: .} ] | from_entries) as $cv
    | [ $rows[] | select(run_is_root) | run_of($cv) ] | unique_by(.root);
'

# run_lib <verb> <reader> [<arg>] — the verbs above.
run_lib() {
    local verb="${1:-}" reader="${2:-}"
    [ -n "$reader" ] || { echo "run_lib: no reader given" >&2; return 2; }
    case "$verb" in
        runs|subject)
            [ -n "${3:-}" ] || { echo "run_lib $verb: no bead given" >&2; return 2; }
            "run_lib_$verb" "$reader" "$3" ;;
        map)
            case "${3:-}" in ''|all) ;; *) echo "run_lib map: unknown scope '$3'" >&2; return 2 ;; esac
            run_lib_map "$reader" "${3:-}" ;;
        *) echo "run_lib: unknown verb '$verb'" >&2; return 2 ;;
    esac
}

# run_lib_read <reader> <bd args...> — one read, printed only when it is a JSON
# array of objects. The `gc bd:` notice a store can print on stdout is dropped
# while the newline that ends its line still stands, then the read is
# scrubbed, as bd-lib.sh's bd_json does.
run_lib_read() {
    local reader="$1" raw
    shift
    raw="$("$reader" "$@" </dev/null 2>/dev/null)" || return 1
    raw="$(printf '%s\n' "$raw" | grep -a -vE '^gc bd:' | scrub)"
    printf '%s' "$raw" | jq -e 'type == "array" and all(.[]; type == "object")' >/dev/null 2>&1 || return 1
    printf '%s' "$raw"
}

# run_lib_join <array-json> <array-json> — the two arrays as one, joined on
# stdin, since a map of every run outgrows what one argument can carry.
run_lib_join() {
    { printf '%s\n' "$1"; printf '%s\n' "$2"; } | jq -cs 'add' 2>/dev/null
}

# run_lib_convoys <reader> <rows-json> — the rows with every convoy their roots
# name appended, read in batches of RUN_LIB_ID_BATCH ids.
run_lib_convoys() {
    local reader="$1" rows="$2" ids batch got
    ids="$(printf '%s' "$rows" | jq -r "$RUN_JQ"'[ .[] | select(run_is_root) | run_convoy | select(. != "") ] | unique | .[]' 2>/dev/null)" || return 1
    while [ -n "$ids" ]; do
        batch="$(printf '%s\n' "$ids" | head -n "$RUN_LIB_ID_BATCH" | paste -sd, -)"
        ids="$(printf '%s\n' "$ids" | tail -n +"$((RUN_LIB_ID_BATCH + 1))")"
        got="$(run_lib_read "$reader" list --id "$batch" --all --include-ephemeral --json --limit 0)" || return 1
        rows="$(run_lib_join "$rows" "$got")" || return 1
    done
    printf '%s' "$rows"
}

# run_lib_runs <reader> <bead> — the convoys that track the bead, the roots
# poured over each, and the roots that record the bead as their issue, judged
# together.
run_lib_runs() {
    local reader="$1" bead="$2" up convoys c got rows='[]'
    up="$(run_lib_read "$reader" dep list "$bead" --direction=up -t tracks --json)" || return 1
    convoys="$(printf '%s' "$up" | jq -r '[ .[] | select(((.issue_type // "") | tostring) == "convoy") | ((.id // "") | tostring) | select(. != "") ] | unique | .[]' 2>/dev/null)" || return 1
    for c in $convoys; do
        got="$(run_lib_read "$reader" list --metadata-field "gc.input_convoy_id=$c" --all --include-ephemeral --json --limit 0)" || return 1
        rows="$(run_lib_join "$rows" "$got")" || return 1
    done
    got="$(run_lib_read "$reader" list --metadata-field "gc.var.issue=$bead" --all --include-ephemeral --json --limit 0)" || return 1
    rows="$(run_lib_join "$rows" "$got")" || return 1
    rows="$(run_lib_convoys "$reader" "$rows")" || return 1
    printf '%s' "$rows" | jq -c --arg b "$bead" "$RUN_JQ"'run_rows | map(select(.bead == $b))' 2>/dev/null
}

# run_lib_subject <reader> <id> — the bead itself, then the roots poured over
# it when it is a convoy, or the convoy it names when it is a root.
run_lib_subject() {
    local reader="$1" id="$2" row kind got
    row="$(run_lib_read "$reader" list --id "$id" --all --include-ephemeral --json --limit 0)" || return 1
    kind="$(printf '%s' "$row" | jq -r --arg id "$id" "$RUN_JQ"'
        [ .[] | select(((.id // "") | tostring) == $id) ] | first
        | if . == null then "none"
          elif ((.issue_type // "") | tostring) == "convoy" then "convoy"
          elif run_is_root then "root"
          else "none" end' 2>/dev/null)" || return 1
    case "$kind" in
        convoy)
            got="$(run_lib_read "$reader" list --metadata-field "gc.input_convoy_id=$id" --all --include-ephemeral --json --limit 0)" || return 1
            row="$(run_lib_join "$row" "$got")" || return 1 ;;
        root)
            row="$(run_lib_convoys "$reader" "$row")" || return 1 ;;
        *)
            printf '[]'; return 0 ;;
    esac
    printf '%s' "$row" | jq -c --arg id "$id" "$RUN_JQ"'run_rows | map(select(.root == $id or .convoy == $id))' 2>/dev/null
}

# run_lib_map <reader> [all] — every root that names an input convoy or
# records an issue, live or with `all` of every status, and the convoys they
# name.
run_lib_map() {
    local reader="$1" scope="${2:-}" roots legacy rows
    if [ "$scope" = all ]; then
        roots="$(run_lib_read "$reader" list --has-metadata-key gc.input_convoy_id --all --include-ephemeral --json --limit 0)" || return 1
        legacy="$(run_lib_read "$reader" list --has-metadata-key gc.var.issue --all --include-ephemeral --json --limit 0)" || return 1
    else
        roots="$(run_lib_read "$reader" list --has-metadata-key gc.input_convoy_id --include-ephemeral --json --limit 0)" || return 1
        legacy="$(run_lib_read "$reader" list --has-metadata-key gc.var.issue --include-ephemeral --json --limit 0)" || return 1
    fi
    rows="$(run_lib_join "$roots" "$legacy")" || return 1
    rows="$(run_lib_convoys "$reader" "$rows")" || return 1
    printf '%s' "$rows" | jq -c "$RUN_JQ"'run_rows' 2>/dev/null
}
