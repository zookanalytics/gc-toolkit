#!/bin/sh
# helm-fixture.sh — a gc-helm.sh stand-in that answers the conversation form
# from fixture data, so the form can be run and captured with no city behind it
# (docs/review-demo.md):
#
#   helm-svc form --helm services/helm/internal/form/testdata/helm-fixture.sh \
#       --models opus,fable,codex [--subject tk-demo1 | --rig gc-toolkit | --return]
#
# It answers the verbs the form calls: `conversations [<ref>] --json`, `open`,
# `engage <conversation> --no-input --no-attach` and the attach,
# `engage <conversation> --no-input`. A save and a start each take a second, as
# the real verbs take a few, so each acknowledgement can be seen landing. It
# writes nothing.
case "${1:-} ${2:-}" in
  "conversations --json")
    sleep 1
    cat <<'JSON'
{"conversations":[
 {"id":"tk-demo2","rig":"gc-toolkit","subject":"tk-demo1","subject_title":"Board: show a PR's held reason on its row","title":"why does the held label lag the gate by a cycle?","status":"in_progress","state":"live","readiness":"ready","created_at":"2026-11-08T10:00:00Z","session":{"id":"s-1","name":"s-1","state":"active","attached":false,"created_at":"2026-11-08T10:00:00Z"}},
 {"id":"tk-demo3","rig":"gc-toolkit","subject":"tk-demo4","subject_title":"Refinery: land siblings independently","title":"what would it take to land siblings on their own?","status":"open","state":"live","readiness":"starting","created_at":"2026-11-08T11:00:00Z","session":{"id":"s-2","name":"s-2","state":"start-pending","attached":false,"created_at":"2026-11-08T11:00:00Z"}},
 {"id":"tk-demo5","rig":"gascity","subject":"gc-demo6","subject_title":"Upstream: session wake on assignment","title":"is the wake path worth an upstream issue?","status":"in_progress","state":"left","readiness":"ended","created_at":"2026-11-07T15:00:00Z","session":null},
 {"id":"tk-demo7","rig":"gc-toolkit","subject":"tk-demo8","subject_title":"Intake: multi-line questions","title":"operator pick from the board","status":"open","state":"queue","readiness":"queued","created_at":"2026-11-08T09:00:00Z","session":null}],
 "rigs":[{"name":"gc-toolkit","converse":true,"suspended":false},{"name":"gascity","converse":true,"suspended":false},{"name":"paused","converse":true,"suspended":true}],
 "unread":[]}
JSON
    ;;
  "conversations tk-demo1"|"conversations tk-demo9")
    sleep 1
    cat <<'JSON'
{"ref":"tk-demo1","subject":{"id":"tk-demo1","title":"Board: show a PR's held reason on its row","status":"open","issue_type":"task","rig":"gc-toolkit"},
 "gate":"","conversation":"","closed":null,"refusal":"",
 "conversations":[
  {"id":"tk-demo2","rig":"gc-toolkit","subject":"tk-demo1","title":"why does the held label lag the gate by a cycle?","status":"in_progress","state":"live","readiness":"ready","session":{"id":"s-1","name":"s-1","state":"active","attached":false,"created_at":"2026-11-08T10:00:00Z"}},
  {"id":"tk-demo9","rig":"gc-toolkit","subject":"tk-demo1","title":"your question","status":"open","state":"live","readiness":"preparing","session":{"id":"s-9","name":"s-9","state":"active","attached":false,"created_at":"2026-11-08T12:00:00Z"}}],
 "holds":[{"held":"gate","id":"tk-demo10","title":"Approve the label wording"},{"held":"review","id":"","title":"2 review threads wait on the city's answer"}],"holds_read":true}
JSON
    ;;
  "conversations 1446")
    sleep 2
    echo '{"ref":"1446","candidates":[{"id":"tk-demo1","rig":"gc-toolkit","title":"Board: show a PR'"'"'s held reason on its row","status":"open"},{"id":"gc-demo6","rig":"gascity","title":"Upstream: session wake on assignment","status":"open"}]}'
    ;;
  "conversations "*)
    sleep 1
    echo "gc-helm: conversations: bead not found: '${2:-}' — no rig ledger answers for that id. Nothing read." >&2
    exit 4
    ;;
  "open "*)
    sleep 1
    echo '{"subject":"tk-demo1","conversation":"tk-demo9","filed":true}'
    ;;
  "engage "*)
    sleep 1
    case " $* " in
      *" --no-attach "*) echo "✓ converse-opus on existing conversation $2 for tk-demo1" ;;
      *) echo "(the fixture attaches nothing: $2)" ;;
    esac
    ;;
  *)
    echo "helm-fixture: no answer for: $*" >&2
    exit 2
    ;;
esac
