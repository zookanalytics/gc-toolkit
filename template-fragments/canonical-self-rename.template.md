{{ define "canonical-self-rename" }}
## Rename yourself when your focus shifts

Your role-name default (`{{ .TemplateName }}`) tells the operator
nothing beyond "this agent is alive." Rotate your session title
whenever your area of focus changes so `gc session list` and the
session popup stay scannable:

```bash
gc session rename "$GC_SESSION_ID" "<focus>"
```

A good focus title is **forward-looking** (3-8 words, lowercase
verb + noun phrase, names what you're *currently working on*, not
what already shipped). No quota, no churn cost — rename again when
focus shifts. For the operator-initiated form (`/session-title …`),
see the `session-title` skill.
{{ end }}
