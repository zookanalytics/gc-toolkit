#!/usr/bin/env bash
# probe.sh <label> <cwd> [extra claude flags...]
# Spawns ONE print-mode request and reports the first assistant record's seed.
# shellcheck disable=SC2012  # transcript filenames are UUIDs; `ls -t` is the cheapest
# newest-first sort and there is nothing here for find to protect against
set -uo pipefail
LABEL="$1"; PCWD="$2"; shift 2
RESULTS="${RESULTS:-/tmp/seed-results.tsv}"
proj=$(printf '%s' "$PCWD" | sed 's|[/.]|-|g')
dir="$HOME/.claude/projects/$proj"
before=""
[ -d "$dir" ] && before=$(ls "$dir"/*.jsonl 2>/dev/null | sort)
start=$(date +%s)
( cd "$PCWD" && timeout 300 claude --dangerously-skip-permissions --effort medium \
    --model "${PROBE_MODEL:-claude-sonnet-5}" --settings /home/zook/loomington/.gc/settings.json \
    "$@" -p 'Reply with the single word: ok' ) > "/tmp/seed-$LABEL.out" 2> "/tmp/seed-$LABEL.err"
rc=$?
elapsed=$(( $(date +%s) - start ))
after=$(ls "$dir"/*.jsonl 2>/dev/null | sort)
new=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)
[ -n "$new" ] || new=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
if [ -z "$new" ]; then
  printf '%s\t%s\tNO_TRANSCRIPT\t\t\t\t%s\t%s\n' "$LABEL" "$PCWD" "$rc" "$elapsed" >> "$RESULTS"
  echo "$LABEL: NO TRANSCRIPT (rc=$rc)"; exit 1
fi
row=$(jq -c -r 'select(.type=="assistant") | select(.message.usage != null)
  | [ ((.message.usage.input_tokens // 0)
       + (.message.usage.cache_creation_input_tokens // 0)
       + (.message.usage.cache_read_input_tokens // 0)),
      (.message.usage.input_tokens // 0),
      (.message.usage.cache_creation_input_tokens // 0),
      (.message.usage.cache_read_input_tokens // 0),
      (.message.model // "") ] | @tsv' "$new" 2>/dev/null | head -1)
printf '%s\t%s\t%s\t%s\t%s\n' "$LABEL" "$PCWD" "$row" "$rc" "$elapsed" >> "$RESULTS"
printf '%-26s seed=%s rc=%s %ss  (%s)\n' "$LABEL" "$(printf '%s' "$row" | cut -f1)" "$rc" "$elapsed" "$(basename "$new")"
