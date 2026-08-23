#!/usr/bin/env bash
# First-assistant-record seed census over the local Claude Code transcripts.
set -uo pipefail
out="$1"; shift
: > "$out"
find "$HOME/.claude/projects" -name '*.jsonl' -mtime -3 2>/dev/null | while IFS= read -r f; do
  jq -c -r --arg f "$f" '
    select(.type=="assistant")
    | select(.message.usage != null)
    | [ $f, (.cwd // ""), (.gitBranch // ""), (.version // ""),
        (.message.model // ""), (.effort // ""), (.entrypoint // ""),
        ((.message.usage.input_tokens // 0)
         + (.message.usage.cache_creation_input_tokens // 0)
         + (.message.usage.cache_read_input_tokens // 0)),
        (.message.usage.input_tokens // 0),
        (.message.usage.cache_creation_input_tokens // 0),
        (.message.usage.cache_read_input_tokens // 0),
        (.timestamp // "") ]
    | @tsv' "$f" 2>/dev/null | head -1
done >> "$out"
wc -l < "$out"
