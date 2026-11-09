package form

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/server"
)

// gcStub answers the gc calls `gc-helm.sh open` makes, from one rig's store kept
// as rows in $STATE/rows.json, and records each call in $STATE/calls. A marker
// file stalls one call, once, and the call it stalls writes $STATE/stalled:
// stall.after-subject stalls the first call after the subject's create, and
// stall.in-conversation-create stalls the conversation's create once its row is
// written, before it answers.
const gcStub = `#!/bin/sh
printf '%s\n' "$*" | tr '\n' ' ' >> "$STATE/calls"; echo >> "$STATE/calls"
stall() { rm -f "$STATE/stall.$1"; : > "$STATE/stalled"; sleep 60; }
if [ -e "$STATE/stall.after-subject" ] && grep -q '"tk-subj1"' "$STATE/rows.json"; then stall after-subject; fi
arg() { want=$1; shift; prev=; for a; do [ "$prev" = "$want" ] && { printf '%s' "$a"; return; }; prev=$a; done; }
case "$1 ${2:-}" in
"rig list") cat "$STATE/rigs.json" ;;
"agent list") echo '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse-opus"}]}' ;;
"bd create")
	deps=$(arg --deps "$@")
	if [ -z "$deps" ]; then id=tk-subj1; else id=tk-conv1; fi
	row=$(jq -nc --arg i "$id" --arg t "$(arg --title "$@")" --arg d "$(arg -d "$@")" --arg s "${deps#tracks:}" \
		'{id: $i, issue_type: "task", status: "open", title: $t, description: $d}
		 + (if $s == "" then {} else {assignee: "human", dependencies: [{type: "tracks", depends_on_id: $s}]} end)')
	jq --argjson r "$row" '. + [$r]' "$STATE/rows.json" > "$STATE/rows.new" && mv "$STATE/rows.new" "$STATE/rows.json"
	if [ -n "$deps" ] && [ -e "$STATE/stall.in-conversation-create" ]; then stall in-conversation-create; fi
	printf '{"id":"%s"}\n' "$id" ;;
"bd show") jq -c --arg i "$3" '[.[] | select(.id == $i)]' "$STATE/rows.json" ;;
"bd dep") jq -c --arg i "$4" --arg t "$(arg --type "$@")" \
	'[.[] | select(any(.dependencies[]?; .type == $t and .depends_on_id == $i)) | {id, status, assignee, issue_type, dependency_type: $t}]' "$STATE/rows.json" ;;
"bd list") jq -c --arg ids "$(arg --id "$@")" '[.[] | select(.id as $i | $ids | split(",") | index($i))]' "$STATE/rows.json" ;;
*) echo "stub gc: unhandled: $*" >&2; exit 1 ;;
esac
`

// realOpen is the gc-helm.sh this module ships, run with gcStub first on PATH
// and nothing of the session's city in its environment, under timeout. It
// returns the Script and the directory the stub keeps its store in.
func realOpen(t *testing.T, timeout time.Duration) (Script, string) {
	t.Helper()
	dir := t.TempDir()
	state, bin, rig := filepath.Join(dir, "state"), filepath.Join(dir, "bin"), filepath.Join(dir, "rig")
	for _, d := range []string{state, bin, filepath.Join(rig, ".beads")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	rigs, err := json.Marshal(map[string]any{"rigs": []map[string]any{
		{"name": "gc-toolkit", "path": rig, "prefix": "tk", "suspended": false},
		{"name": "hq", "path": dir, "prefix": "hq", "hq": true, "running": true},
	}})
	if err != nil {
		t.Fatal(err)
	}
	for name, file := range map[string]struct {
		content string
		mode    os.FileMode
	}{
		"state/rigs.json": {string(rigs), 0o644},
		"state/rows.json": {"[]", 0o644},
		"bin/gc":          {gcStub, 0o755},
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(file.content), file.mode); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATE", state)
	t.Setenv("TMPDIR", dir)
	for _, k := range []string{"GC_CITY_PATH", "GC_CITY", "GC_CITY_ROOT", "GC_RIG", "BEADS_DIR", "GC_HELM_FIXTURE"} {
		t.Setenv(k, "")
		os.Unsetenv(k)
	}
	path, err := filepath.Abs("../../../../assets/scripts/gc-helm.sh")
	if err != nil {
		t.Fatal(err)
	}
	return Script{Path: path, Timeout: timeout}, state
}

// answers is fakeHelm whose saves run a Script, each request and answer
// recorded.
type answers struct {
	*fakeHelm
	s   Script
	got []savedMsg
}

func (h *answers) Save(ctx context.Context, req SaveRequest) (Saved, error) {
	h.saves = append(h.saves, req)
	sv, err := h.s.Save(ctx, req)
	h.got = append(h.got, savedMsg{saved: sv, err: err})
	return sv, err
}

// A save that runs past its deadline is killed with every process it started,
// so no trap of open's runs. A new topic's subject filed before the kill comes
// back all the same, the form keeps it, and the save again files the question
// onto it: it files the conversation the killed run did not reach, or lands on
// the one the killed run filed. Either way the store holds one subject and one
// conversation.
func TestANewTopicSaveKilledAtItsDeadlineKeepsItsSubject(t *testing.T) {
	const q = "why do sittings start slowly?"
	for _, stall := range []string{"after-subject", "in-conversation-create"} {
		t.Run(stall, func(t *testing.T) {
			s, state := realOpen(t, 3*time.Second)
			if err := os.WriteFile(filepath.Join(state, "stall."+stall), nil, 0o644); err != nil {
				t.Fatal(err)
			}
			h := &answers{fakeHelm: &fakeHelm{
				city:  rigCity(),
				about: map[string]About{"tk-subj1": subjectAbout("tk-subj1", "gc-toolkit")},
			}, s: s}
			m := newFormOn(t, h, Options{Rig: "gc-toolkit"})
			loadCity(m)
			typeText(m, q)
			_, cmd := m.Update(ctrl('s'))
			deliver(m, cmd)
			if _, err := os.Stat(filepath.Join(state, "stalled")); err != nil {
				calls, _ := os.ReadFile(filepath.Join(state, "calls"))
				t.Fatalf("the save ended before the stub stalled it (%+v); its calls:\n%s", h.got, calls)
			}
			if len(h.got) != 1 || h.got[0].saved != (Saved{Subject: "tk-subj1"}) || !errors.Is(h.got[0].err, server.ErrToolTimeout) {
				t.Fatalf("the killed save answered %+v with %v, want subject tk-subj1 and the timeout", h.got[0].saved, h.got[0].err)
			}
			if m.scr != composeScreen || m.ref() != "tk-subj1" || m.partial != "tk-subj1" || m.question.Value() != q {
				t.Fatalf("after the killed save: screen %d, subject %q, partial %q, question %q, status %q", m.scr, m.ref(), m.partial, m.question.Value(), m.status)
			}
			_, cmd = m.Update(ctrl('s'))
			deliver(m, cmd)
			want := SaveRequest{Ref: "tk-subj1", Subject: "tk-subj1", Question: q}
			if len(h.saves) != 2 || h.saves[1] != want {
				t.Fatalf("saves = %+v, want the save again onto tk-subj1", h.saves)
			}
			if h.got[1].saved != (Saved{Subject: "tk-subj1", Conversation: "tk-conv1", Filed: true}) || h.got[1].err != nil {
				t.Fatalf("the save again answered %+v", h.got[1])
			}
			if len(h.starts) != 1 || h.starts[0] != "tk-conv1 opus" {
				t.Fatalf("starts = %v, want tk-conv1", h.starts)
			}
			b, err := os.ReadFile(filepath.Join(state, "rows.json"))
			if err != nil {
				t.Fatal(err)
			}
			var rows []struct {
				ID, Assignee, Description string
			}
			if err := json.Unmarshal(b, &rows); err != nil {
				t.Fatal(err)
			}
			subjects, conversations := 0, 0
			for _, r := range rows {
				switch {
				case r.ID == "tk-subj1":
					subjects++
				case r.ID == "tk-conv1" && r.Assignee == "human" && r.Description == q:
					conversations++
				}
			}
			if subjects != 1 || conversations != 1 || len(rows) != 2 {
				t.Fatalf("the store holds %d subjects and %d conversations of %d rows, want one of each:\n%s", subjects, conversations, len(rows), b)
			}
		})
	}
}
