#!/usr/bin/env bash
# bring-current-audit — the worker's account of bringing a branch current, and
# the words every message a person reads about it is composed from.
#
# Bringing a branch current merges its base in. When git cannot merge a file on
# its own, the worker that resolves the conflict is the only party that knows
# what collided and why it chose what it chose, so it writes that down as it
# resolves: one entry per conflicted file, and one per edit beyond the merge.
# bring-current-guard.sh holds the hand-back to that coverage, stores the entries
# on the anchor beside its own diff evidence, and routes the round to triage, or
# rules on it itself on an anchor that opts out of review.
# Every message about the round is rendered here from that stored record: the
# round's account, collapsed in the triage verdict posted on the PR; the ask
# that opens that verdict and the note on a dismissed approval when the ruling
# lifts the approval; and the human gate that asks for a decision the worker
# could not make. None is composed from diff shapes alone.
#
# AN ENTRY. metadata.conflict_audit on the bead the worker holds is a JSON array
# of entries, one per path:
#   path        the file as git names it
#   collided    the two intents that met: what the base changed and why, and
#               what the branch changed and why
#   resolution  what the merge kept or wrote, and why
#   check       what a reviewer should look at to confirm it
#   rating      routine: adjacent-line collisions, overlapping comment edits, an
#               obvious composition. judgment: an informed decision, such as an
#               inferred intent, a side chosen on substance, or something new
#               written. The rating informs triage and gates nothing by itself.
#
# A QUESTION. When a conflict cannot be resolved without guessing, the worker
# pushes nothing. `ask` records the question as metadata.conflict_question and
# files a human gate on the anchor carrying the entries so far and the question.
# The gate holds the anchor's merge. The branch stays as it was last reviewed.
#
# Usage:
#   bring-current-audit.sh add --bead <id> --path <file> --collided <text>
#       --resolution <text> --check <text> --rating routine|judgment
#   bring-current-audit.sh ask --bead <id> --path <file> [--path <file> ...]
#       --collided <text> --question <text>
#   bring-current-audit.sh show (--bead <id> | --anchor <id>)
#   bring-current-audit.sh anchor --bead <id>
#   bring-current-audit.sh render --anchor <id> --as comment|dismissal|ask
# add records or replaces the entry for <file>. show prints the bead's entries,
# or the anchor's stored record, as JSON. anchor prints the bead `ask` files its
# gate on. render prints a message composed from the anchor's record; ask
# prints nothing when the ruling keeps the approval.
# Sourced (BASH_SOURCE != $0), it defines its functions and runs nothing, for
# bring-current-guard.sh.
# Exit: 0 done · 1 a read or a write failed, or the input was refused, and
# nothing was recorded · 2 usage
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

BCA_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$BCA_DIR/bd-lib.sh}" || { echo "bring-current-audit: cannot source bd-lib.sh beside this script" >&2; exit 2; }

# How many entries a dismissal note names before it counts the rest.
BCA_MAX_NOTE_ENTRIES=8

bca_meta() { # <row-json> <key>
  printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null
}

# A JSON value stored in metadata. bd keeps an array or object as its text, so
# the text is parsed; one stored already parsed passes through. Prints compact
# JSON, or nothing when the key is absent or does not parse.
bca_meta_json() { # <row-json> <key>
  printf '%s' "$1" | jq -c --arg k "$2" '
    (.[0].metadata[$k] // null)
    | if type == "string" then (fromjson? // null) else . end
    | select(. != null)' 2>/dev/null
}

# Collapse control characters and runs of blanks, so an entry is one line of
# prose wherever it is rendered.
bca_flat() { printf '%s' "$1" | tr '\000-\037' ' ' | sed 's/  */ /g; s/^ //; s/ $//'; }

# The anchor of the bead a worker holds: the bead its anchor_bead names, else the
# open bead on its branch that carries a merge_result, else the bead itself (an
# anchor the refinery re-queued is handed back as itself). Prints the id; exit 1
# when the branch's beads could not be listed.
bca_anchor_of() { # <bead-row-json>
  local row="$1" id anchor branch rows
  id=$(printf '%s' "$row" | jq -r '.[0].id // ""' 2>/dev/null)
  anchor=$(bca_meta "$row" anchor_bead)
  if [ -z "$anchor" ]; then
    branch=$(bca_meta "$row" branch)
    if [ -n "$branch" ]; then
      rows=$(bd_list --status=open --metadata-field branch="$branch") || return 1
      anchor=$(printf '%s' "$rows" | jq -r --arg self "$id" '
        [ .[]? | select(.id != $self) | select((((.metadata // {}).merge_result // "") | tostring) != "") ]
        | sort_by(.created_at // .created // .id) | .[0].id // empty' 2>/dev/null)
    fi
  fi
  printf '%s\n' "${anchor:-$id}"
}

# True when the branch has a review to keep current: its anchor is gating, or a
# PR stands on it. A branch never handed to the refinery has nothing reviewed.
bca_reviewed() { # <anchor-row-json> <bead-row-json>
  local mr
  mr=$(bca_meta "$1" merge_result)
  case "$mr" in pre_open_gate|pull_request) return 0 ;; esac
  [ -n "$(bca_meta "$1" pr_number)$(bca_meta "$1" pr_url)$(bca_meta "$1" existing_pr)" ] && return 0
  [ -n "$(bca_meta "$2" pr_number)$(bca_meta "$2" pr_url)$(bca_meta "$2" existing_pr)" ]
}

# The jq definitions every rendering shares. A record is the object
# bring-current-guard.sh stores as metadata.bring_current_record.
BCA_RENDER_DEF='
def oneline: (. // "") | tostring | gsub("[\\s]+"; " ") | sub("^ "; "") | sub(" $"; "");
def sentence: oneline | if . == "" or test("[.!?…]$") then . else . + "." end;
def clip($n): oneline | if length > $n then .[0:($n - 1)] + "…" else . end;
def short: (. // "") | tostring | if test("^[0-9a-f]{13,}$") then .[0:12] else . end;
def count($n; $one; $many): if $n == 1 then "1 \($one)" else "\($n) \($many)" end;
def joinand: if length == 0 then "" elif length == 1 then .[0]
  elif length == 2 then "\(.[0]) and \(.[1])" else (.[:-1] | join(", ")) + ", and " + .[-1] end;
def covered: [ .evidence[]? | select(.covered == true) ];
def entries: [ .audit[]? | select(type == "object") ];
def unaccounted: . as $r
  | [ covered[] | . as $i
      | select([ $r | entries[] | select(.path == $i.path and (.round // "") == ($i.round // "")) ] | length == 0) ]
  | unique_by([.path, (.round // "")]);
def bare_line: "`\(.path)`, no entry from the worker. Git: \(.detail | sentence)";
def judgment_first: (map(select(.rating == "judgment")) + map(select(.rating != "judgment")));
def git_detail($p; $rd): [ .evidence[]? | select(.path == $p and (.round // "") == ($rd // "") and .covered == true) | .detail ] | .[0] // "";
def headline:
  (covered | map(select(.kind == "conflict")) | length) as $c
  | (covered | map(select(.kind != "conflict")) | length) as $b
  | "Merging \(.target // "the base") in (pushed head \(.head | short)) needed "
    + (if $c > 0 then count($c; "conflicted file"; "conflicted files") + " resolved by hand" else "no conflicted file resolved by hand" end)
    + (if $b > 0 then ", and " + count($b; "edit"; "edits") + " beyond what git merges on its own" else "" end) + ".";
def tally:
  (entries | map(select(.rating == "judgment")) | length) as $j
  | (entries | map(select(.rating != "judgment")) | length) as $o
  | (unaccounted | length) as $u
  | [ (if $j > 0 then "\($j) judgment" else empty end), (if $o > 0 then "\($o) routine" else empty end),
      (if $u > 0 then "\($u) without an entry" else empty end) ]
  | if length == 0 then "nothing accounted" else join(", ") end;
def lanes: ((.triage.reopen // []) + (.triage.add // [])) | unique;
def by_guard: (.triage.by? // "") == "guard";
def cap: if length > 0 then (.[0:1] | ascii_upcase) + .[1:] else . end;
def summary:
  "Bring-current round: " + tally + "; "
  + (if .triage == null then "triage has not ruled on it yet"
     else lanes as $l
       | if ($l | length) == 0 then "nothing reopens"
         else ($l | joinand) + (if ($l | length) == 1 then " re-checks" else " re-check" end) + " the merged code" end end)
  + (if .triage.dismiss == true then "; approval lifted" else "" end);
def ruling:
  if .triage == null then "Triage has not ruled on this round yet."
  else lanes as $l
    | (if by_guard then "Ruling: " else "Triage: " end)
      + (if ($l | length) == 0 then "nothing reopens"
         else ($l | joinand) + (if ($l | length) == 1 then " runs" else " run" end) + " again on the merged code" end)
      + (if .triage.dismiss == true then ", and the approval is lifted" else "" end) + "."
      + (if (.triage.reason // "") != "" then " Why: " + (.triage.reason | sentence) else "" end)
  end;
def ask:
  if .triage.dismiss != true then ""
  elif by_guard then
    "Needs you: check what bringing this branch current with \(.target // "the base") changed by hand (pushed head \(.head | short))."
    + (if (.triage.reason // "") != "" then " " + (.triage.reason | clip(300) | sentence | cap) else "" end)
    + " Your approval is lifted until you have checked it."
  else "Needs you: " + (.triage.reason | clip(300) | sentence) + " Your approval is lifted until you decide." end;
def entry_line($g):
  "`\(.path)`, \(.rating). Collided: \(.collided | sentence) Decided: \(.resolution | sentence) Check: \(.check | sentence)"
  + (if $g != "" then " Git: \($g | sentence)" else "" end);
def routine_line: "`\(.path)`, routine: \(.resolution | sentence)";
def generated: [ .evidence[]? | select(.kind == "generated") | .path ] | unique;
'

# Print a message composed from a record. <as> is one of:
#   comment    the round's account, one collapsed block in the triage verdict:
#              a summary line, then judgment entries in full and each routine
#              entry on one line, its whole decision. Its shape does not depend
#              on the ruling; only a ruling that lifts the approval says so.
#   ask        what a ruling that lifts the approval needs from the operator,
#              which opens the triage verdict; empty when the ruling keeps it.
#              It clips the ruling's reason, which the account's ruling line
#              carries whole, so a long reason cannot push the ask's closing
#              sentence past the dismissal note's length cap.
#   dismissal  one paragraph, the note on a dismissed approval: the same ask.
# A ruling the guard recorded itself (by: guard) is told as the guard's: no
# triage verdict posts it, so no form credits it to triage, and its dismissal
# note carries the entries no triage comment does.
bca_render_record() { # <record-json> <as>
  local rec="$1" as="$2"
  printf '%s' "$rec" | jq -r --arg as "$as" --argjson max "$BCA_MAX_NOTE_ENTRIES" "$BCA_RENDER_DEF"'
    . as $r
    | if $as == "comment" then
        "<details>\n<summary>" + summary + "</summary>\n\n"
        + headline + "\n\n" + ruling + "\n\n"
        + ((entries | map(select(.rating == "judgment"))
              | map(. as $e | ($r | git_detail($e.path; $e.round)) as $g | "- " + ($e | entry_line($g))))
           + (entries | map(select(.rating != "judgment")) | map("- " + routine_line))
           + (unaccounted | map("- " + bare_line)) | join("\n"))
        + (if (generated | length) > 0
           then "\n\nGenerated files the merge re-rendered, which need no entry: " + (generated | map("`" + . + "`") | joinand) + "."
           else "" end)
        + "\n\n</details>"
      elif $as == "ask" then ask
      elif by_guard then
        (entries | judgment_first) as $e
        | [ ask,
            (if ($e | length) > 0 then "Where to look: " + ($e[:$max] | map("\(.path): \(.resolution | clip(160) | sentence)") | join(" ")) else "" end),
            (if ($e | length) > $max then "And \(($e | length) - $max) more." else "" end),
            (unaccounted | if length > 0 then "No entry from the worker covers " + (map(.path) | unique | .[:$max] | joinand) + "." else "" end) ]
        | map(select(. != "")) | join(" ")
      else
        [ ask, "The triage comment on this PR has the round in full." ] | map(select(. != "")) | join(" ")
      end' 2>/dev/null
}

# The human gate that asks for a decision: a title line, then the body.
bca_render_question() { # <audit-json> <question-json> <bead> <anchor> <branch> <target> <head> <pr-number> <pr-url>
  jq -rn --argjson audit "$1" --argjson q "$2" --arg bead "$3" --arg anchor "$4" \
    --arg branch "$5" --arg target "$6" --arg head "$7" --arg num "$8" --arg url "$9" "$BCA_RENDER_DEF"'
    ([ $audit[]? | select(type == "object") ] | judgment_first) as $e
    | (if $num != "" then "PR#\($num)" else "branch \($branch)" end) as $who
    | "\($who) needs a decision before it can be brought current with \($target)\n"
      + "Bringing \($branch) (" + (if $num != "" then "PR#\($num), \($url)" else "anchor \($anchor), no PR yet" end)
      + ") current with \($target) stopped at a conflict the worker could not resolve without guessing. "
      + "Nothing was pushed: the branch is still at \($head | short), the state that was last reviewed.\n\n"
      + "The question: \($q.question | sentence)\n"
      + "What collided in " + ($q.paths | map("`" + . + "`") | joinand) + ": \($q.collided | sentence)\n\n"
      + (if ($e | length) > 0
         then "Resolved before the stop, not pushed:\n" + ($e | map("- `\(.path)`, \(.rating). Decided: \(.resolution | sentence)") | join("\n"))
         else "Nothing else was resolved before the stop." end) + "\n\n"
      + "Your call: answer the question here, and record the answer in the notes of \($bead). Then release it: when \($bead) waits on this gate, clearing the gate re-slings it, and when it is parked for a person, clear the gate and route it back to the polecat pool. The worker that resumes it merges \($target) in again with your answer."' 2>/dev/null
}

bca_usage() {
  echo "usage: bring-current-audit.sh add --bead <id> --path <file> --collided <text> --resolution <text> --check <text> --rating routine|judgment" >&2
  echo "       bring-current-audit.sh ask --bead <id> --path <file> [--path <file> ...] --collided <text> --question <text>" >&2
  echo "       bring-current-audit.sh show (--bead <id> | --anchor <id>)" >&2
  echo "       bring-current-audit.sh anchor --bead <id>" >&2
  echo "       bring-current-audit.sh render --anchor <id> --as comment|dismissal|ask" >&2
  exit 2
}

bca_cmd_add() {
  local bead="" path="" collided="" resolution="" check="" rating="" row audit entry new got
  while [ $# -gt 0 ]; do
    case "$1" in
      --bead) bead="${2:-}"; shift 2 ;;
      --path) path="${2:-}"; shift 2 ;;
      --collided) collided="${2:-}"; shift 2 ;;
      --resolution) resolution="${2:-}"; shift 2 ;;
      --check) check="${2:-}"; shift 2 ;;
      --rating) rating="${2:-}"; shift 2 ;;
      *) bca_usage ;;
    esac
  done
  [ -n "$bead" ] && [ -n "$path" ] || bca_usage
  case "$rating" in
    routine|judgment) : ;;
    *) echo "bring-current-audit: --rating is routine or judgment (got '$rating'); nothing recorded" >&2; return 1 ;;
  esac
  collided=$(bca_flat "$collided"); resolution=$(bca_flat "$resolution"); check=$(bca_flat "$check")
  if [ -z "$collided" ] || [ -z "$resolution" ] || [ -z "$check" ]; then
    echo "bring-current-audit: an entry says what collided, what was decided and why, and what a reviewer should check; one of --collided, --resolution, --check is empty, so nothing is recorded" >&2
    return 1
  fi
  row=$(bd_json show "$bead")
  printf '%s' "$row" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { echo "bring-current-audit: $bead could not be read; nothing recorded" >&2; return 1; }
  audit=$(bca_meta_json "$row" conflict_audit)
  printf '%s' "$audit" | jq -e 'type == "array"' >/dev/null 2>&1 || audit='[]'
  entry=$(jq -cn --arg p "$path" --arg c "$collided" --arg r "$resolution" --arg k "$check" --arg g "$rating" \
    '{path: $p, collided: $c, resolution: $r, check: $k, rating: $g}')
  new=$(printf '%s' "$audit" | jq -c --argjson e "$entry" '[ .[] | select(.path != $e.path) ] + [ $e ]')
  gc bd update "$bead" --set-metadata "conflict_audit=$new" >/dev/null 2>&1 || true
  got=$(bca_meta_json "$(bd_json show "$bead")" conflict_audit | jq -c --arg p "$path" '[ .[]? | select(.path == $p) ] | .[0] // empty' 2>/dev/null)
  if [ "$got" != "$entry" ]; then
    echo "bring-current-audit: the entry for $path did not read back on $bead; retry the same command" >&2
    return 1
  fi
  echo "bring-current-audit: recorded $path ($rating) on $bead; the audit holds $(printf '%s' "$new" | jq 'length') entries"
}

bca_cmd_ask() {
  local bead="" collided="" question="" paths=() row anchor arow branch target head num url q audit msg key title got
  while [ $# -gt 0 ]; do
    case "$1" in
      --bead) bead="${2:-}"; shift 2 ;;
      --path) paths+=("${2:-}"); shift 2 ;;
      --collided) collided="${2:-}"; shift 2 ;;
      --question) question="${2:-}"; shift 2 ;;
      *) bca_usage ;;
    esac
  done
  [ -n "$bead" ] && [ "${#paths[@]}" -gt 0 ] || bca_usage
  collided=$(bca_flat "$collided"); question=$(bca_flat "$question")
  if [ -z "$collided" ] || [ -z "$question" ]; then
    echo "bring-current-audit: a question names what collided and the one decision needed; --collided or --question is empty, so nothing is filed" >&2
    return 1
  fi
  row=$(bd_json show "$bead")
  printf '%s' "$row" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { echo "bring-current-audit: $bead could not be read; nothing filed" >&2; return 1; }
  anchor=$(bca_anchor_of "$row") || { echo "bring-current-audit: the beads on $bead's branch could not be listed; nothing filed" >&2; return 1; }
  if [ "$anchor" = "$bead" ]; then arow="$row"; else arow=$(bd_json show "$anchor"); fi
  printf '%s' "$arow" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { echo "bring-current-audit: anchor $anchor could not be read; nothing filed" >&2; return 1; }
  branch=$(bca_meta "$row" branch); [ -n "$branch" ] || branch=$(bca_meta "$arow" branch)
  target=$(bca_meta "$row" target); [ -n "$target" ] || target=$(bca_meta "$arow" target)
  [ -n "$target" ] || target=main
  head=$(git rev-parse -q --verify "refs/remotes/origin/$branch" 2>/dev/null)
  [ -n "$head" ] || head="its last pushed head"
  num=$(bca_meta "$arow" pr_number); url=$(bca_meta "$arow" pr_url)
  [ -n "$url" ] || url=$(bca_meta "$arow" existing_pr)
  [ -n "$num" ] || num=$(printf '%s' "$url" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p')
  q=$(printf '%s\n' "${paths[@]}" | jq -Rsc --arg c "$collided" --arg qq "$question" \
    '{paths: (split("\n") | map(select(. != ""))), collided: $c, question: $qq}')
  gc bd update "$bead" --set-metadata "conflict_question=$q" >/dev/null 2>&1 || true
  got=$(bca_meta_json "$(bd_json show "$bead")" conflict_question)
  if [ "$got" != "$q" ]; then
    echo "bring-current-audit: the question did not read back on $bead; nothing filed, retry the same command" >&2
    return 1
  fi
  audit=$(bca_meta_json "$row" conflict_audit)
  printf '%s' "$audit" | jq -e 'type == "array"' >/dev/null 2>&1 || audit='[]'
  msg=$(bca_render_question "$audit" "$q" "$bead" "$anchor" "$branch" "$target" "$head" "$num" "$url")
  [ -n "$msg" ] || { echo "bring-current-audit: the question could not be composed; nothing filed" >&2; return 1; }
  key="bring-current-question.$bead"
  # The human gate is what the caller waits on, so it has to be open. Each
  # round's question is an event of its own, though an earlier round's shares
  # this key, so the call declares no quiet window. The gate blocks the anchor,
  # which holds its merge, and the caller's await-ruling.sh gives the rework
  # bead its own edge onto it.
  if ! "$BCA_DIR/human-gate.sh" --subject "$anchor" --key "$key" --message "$msg" >/dev/null; then
    echo "bring-current-audit: the gate on $anchor did not land; the question is recorded on $bead, and nothing is held until a gate asks it" >&2
    return 1
  fi
  title="${msg%%$'\n'*}"
  echo "bring-current-audit: human gate filed on $anchor ($key): $title"
}

bca_cmd_show() {
  local bead="" anchor="" row a q
  while [ $# -gt 0 ]; do
    case "$1" in
      --bead) bead="${2:-}"; shift 2 ;;
      --anchor) anchor="${2:-}"; shift 2 ;;
      *) bca_usage ;;
    esac
  done
  if [ -n "$bead" ]; then
    row=$(bd_json show "$bead")
    printf '%s' "$row" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || { echo "bring-current-audit: $bead could not be read" >&2; return 1; }
    a=$(bca_meta_json "$row" conflict_audit)
    printf '%s' "$a" | jq -e 'type == "array"' >/dev/null 2>&1 || a='[]'
    q=$(bca_meta_json "$row" conflict_question)
    [ -n "$q" ] || q=null
    jq -n --argjson a "$a" --argjson q "$q" '{conflict_audit: $a, conflict_question: $q}'
    return 0
  fi
  [ -n "$anchor" ] || bca_usage
  row=$(bd_json show "$anchor")
  printf '%s' "$row" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || { echo "bring-current-audit: $anchor could not be read" >&2; return 1; }
  a=$(bca_meta_json "$row" bring_current_record)
  printf '%s' "${a:-null}" | jq .
}

bca_cmd_anchor() {
  local bead="" row
  while [ $# -gt 0 ]; do
    case "$1" in
      --bead) bead="${2:-}"; shift 2 ;;
      *) bca_usage ;;
    esac
  done
  [ -n "$bead" ] || bca_usage
  row=$(bd_json show "$bead")
  printf '%s' "$row" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || { echo "bring-current-audit: $bead could not be read" >&2; return 1; }
  bca_anchor_of "$row" || { echo "bring-current-audit: the beads on $bead's branch could not be listed" >&2; return 1; }
}

bca_cmd_render() {
  local anchor="" as="" row rec out
  while [ $# -gt 0 ]; do
    case "$1" in
      --anchor) anchor="${2:-}"; shift 2 ;;
      --as) as="${2:-}"; shift 2 ;;
      *) bca_usage ;;
    esac
  done
  [ -n "$anchor" ] || bca_usage
  case "$as" in comment|dismissal|ask) : ;; *) bca_usage ;; esac
  row=$(bd_json show "$anchor")
  rec=$(bca_meta_json "$row" bring_current_record)
  [ -n "$rec" ] || { echo "bring-current-audit: $anchor carries no bring-current record" >&2; return 1; }
  # An empty ask is a ruling that keeps the approval, so only jq's own status
  # tells it from a record that would not render.
  if ! out=$(bca_render_record "$rec" "$as") || { [ -z "$out" ] && [ "$as" != ask ]; }; then
    echo "bring-current-audit: the record on $anchor could not be rendered" >&2
    return 1
  fi
  [ -z "$out" ] || printf '%s\n' "$out"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    add)    shift; bca_cmd_add "$@" ;;
    ask)    shift; bca_cmd_ask "$@" ;;
    show)   shift; bca_cmd_show "$@" ;;
    anchor) shift; bca_cmd_anchor "$@" ;;
    render) shift; bca_cmd_render "$@" ;;
    *) bca_usage ;;
  esac
fi
