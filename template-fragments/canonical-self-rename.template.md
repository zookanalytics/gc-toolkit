{{ define "canonical-self-rename" }}
## Rename yourself when your focus shifts

Rotate your session title whenever your area of focus changes, so
`gc session list` and the session popup stay scannable:

```bash
gc session rename "$GC_SESSION_ID" "<3-8 word focus>"
```

A good title is forward-looking — lowercase verb + noun phrase naming
what you are working on now, not what already shipped. Rename again on
every shift; a role with its own title format (a subject-prefixed
visit, say) keeps that format. Operator-initiated form: the
`session-title` skill.
{{ end }}
