{{ define "file-feedback-observations" }}
## Feedback observations

When a turn brings you corrective feedback about *standing* agent
behavior — a PR review comment, an operator correction, a rework whose
cause was a habit rather than a one-off — do two things, in order: fix
the instance in front of you, then file one observation bead before the
turn ends:

```bash
OBS_META=$(jq -nc \
  --arg category "<free-slug>" \
  --arg scope "<repo:<rig> or agent:<role> or global — guess narrow>" \
  --arg directive "<standing or diff>" \
  --arg provenance "<pr:<owner/repo>#<n>:comment:<id> or bead:<id>:turn:<date>>" \
  '{task_kind: "observation", "obs.category": $category, "obs.scope": $scope,
    "obs.source": "self", "obs.directive": $directive, "obs.provenance": $provenance,
    "gc.outcome": "recorded"}')
OBS_JSON=$(gc bd create "obs: <one-line restatement of the feedback> (<source ref>)" \
  -t task -l learning -l observation --metadata "$OBS_META" --status=closed -d "## Statement
<the generalizable point>

## Quote
<verbatim feedback + link>

## Proposed norm
<draft rule text — explicitly non-binding>

## Context
<optional: what the diff was doing>" --json)
OBS=$(printf '%s' "$OBS_JSON" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
[ -n "$OBS" ] || { CREATE_ERR=$(printf '%s' "$OBS_JSON" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null); echo "observation not filed${CREATE_ERR:+: $CREATE_ERR}" >&2; exit 1; }
```

The metadata and the closed status ride the create, so the observation is
filed whole or not at all.

The provenance key's `<owner/repo>` is the full slug — derive it with
`gh repo view --json nameWithOwner -q .nameWithOwner`, or parse the
origin URL.

Provenance names the turn or the comment, not the finding, so it is only
half of the dedup key and `obs.category` is the other half. One turn can
bring two separate findings: file a bead for each and give them different
`obs.category` slugs. Identical slugs collapse the two into one
occurrence and the second is lost.

Filing is recording, not proposing: never edit a prompt, fragment, or
skill in response to feedback — the distiller and a reviewed PR do
that. Set `obs.directive=standing` only when the feedback itself states
universal intent ("never do this again", "fix this everywhere");
feedback about this diff is `obs.directive=diff`. Feedback about *this
change's content* (a bug, a wrong approach) is not an observation — it
is just review. When unsure, file it; the distiller's job is to judge,
yours is not to filter.

Operator fast path: "learn this: …" files the same bead with the
operator's wording as `## Statement`, and `"obs.source": "operator"` plus
`"obs.endorsed": "operator"` in its metadata.
{{ end }}
