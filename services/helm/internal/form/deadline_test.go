package form

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/server"
)

// gcStub answers the gc calls `gc-helm.sh open` makes, from one rig's store kept
// as rows in $STATE/rows.json, and records each call in $STATE/calls. A create
// with a --deps files the next conversation, tk-conv1 and then tk-conv2, and
// `dep add` writes its edge onto the row. A marker file stalls one call, once,
// and the call it stalls writes $STATE/stalled: stall.after-subject stalls the
// first call after the subject's create, stall.in-conversation-create stalls the
// conversation's create once its row is written, before it answers, and
// stall.in-reply stalls the conversation's reply onto its gate before the edge
// is written, and lets the hold on an open PR's merge, written ahead of it, land.
const gcStub = `#!/bin/sh
printf '%s\n' "$*" | tr '\n' ' ' >> "$STATE/calls"; echo >> "$STATE/calls"
stall() { rm -f "$STATE/stall.$1"; : > "$STATE/stalled"; sleep 60; }
if [ -e "$STATE/stall.after-subject" ] && grep -q '"tk-subj1"' "$STATE/rows.json"; then stall after-subject; fi
arg() { want=$1; shift; prev=; for a; do [ "$prev" = "$want" ] && { printf '%s' "$a"; return; }; prev=$a; done; }
case "$1 ${2:-}" in
"rig list") cat "$STATE/rigs.json" ;;
"agent list") echo '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse-claude-opus"}]}' ;;
"bd create")
	deps=$(arg --deps "$@")
	if [ -z "$deps" ]; then id=tk-subj1; else id=tk-conv$(( $(jq '[.[] | select(.id | startswith("tk-conv"))] | length' "$STATE/rows.json") + 1 )); fi
	row=$(jq -nc --arg i "$id" --arg t "$(arg --title "$@")" --arg d "$(arg -d "$@")" --arg s "${deps#tracks:}" \
		'{id: $i, issue_type: "task", status: "open", title: $t, description: $d}
		 + (if $s == "" then {} else {assignee: "human", dependencies: [{type: "tracks", depends_on_id: $s}]} end)')
	jq --argjson r "$row" '. + [$r]' "$STATE/rows.json" > "$STATE/rows.new" && mv "$STATE/rows.new" "$STATE/rows.json"
	if [ -n "$deps" ] && [ -e "$STATE/stall.in-conversation-create" ]; then stall in-conversation-create; fi
	printf '{"id":"%s"}\n' "$id" ;;
"bd show") jq -c --arg i "$3" '[.[] | select(.id == $i)]' "$STATE/rows.json" ;;
"bd dep")
	if [ "$3" = add ]; then
		if [ -e "$STATE/stall.in-reply" ] && [ "$(arg --type "$@")" = replies-to ]; then stall in-reply; fi
		jq --arg i "$4" --arg g "$5" --arg t "$(arg --type "$@")" \
			'map(if .id == $i then .dependencies = ((.dependencies // []) + [{type: $t, depends_on_id: $g}]) else . end)' \
			"$STATE/rows.json" > "$STATE/rows.new" && mv "$STATE/rows.new" "$STATE/rows.json"
	else
		jq -c --arg i "$4" --arg t "$(arg --type "$@")" \
			'[.[] | select(any(.dependencies[]?; .type == $t and .depends_on_id == $i)) | {id, status, assignee, issue_type, dependency_type: $t}]' "$STATE/rows.json"
	fi ;;
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
			if len(h.starts) != 1 || h.starts[0] != "tk-conv1 claude-opus" {
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

// A save onto a gate on an open PR that runs past its deadline in the
// conversation's reply onto the gate, after the conversation is filed and holds
// the PR's merge, comes back with that conversation, so the form holds it and
// saves again onto it by its id. By then a sitting another terminal started has
// taken the conversation out of the operator's queue, where a save that looks
// for a queued conversation holding the same question no longer finds it, and
// has lifted the hold because it is helping the PR land. The save again
// completes the reply all the same and leaves the hold lifted, and the store
// holds one conversation.
func TestAGateSaveKilledInItsReplyIsSavedAgainOntoTheConversationItFiled(t *testing.T) {
	const q = "is the rollout safe to approve?"
	s, state := realOpen(t, 3*time.Second)
	rows := `[{"id": "tk-gate1", "issue_type": "gate", "await_type": "human", "status": "open", "title": "Approve the rollout", "description": "Approve it or say why not."},
		{"id": "tk-held1", "issue_type": "task", "status": "open", "title": "the rollout", "metadata": {"merge_result": "pull_request", "pr_number": "41"},
		 "dependencies": [{"type": "blocks", "depends_on_id": "tk-gate1"}]}]`
	for name, content := range map[string]string{"rows.json": rows, "stall.in-reply": ""} {
		if err := os.WriteFile(filepath.Join(state, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	a := subjectAbout("tk-held1", "gc-toolkit")
	a.Ref, a.Gate = "tk-gate1", "tk-gate1"
	h := &answers{fakeHelm: &fakeHelm{about: map[string]About{"tk-gate1": a}}, s: s}
	m := newFormOn(t, h, Options{Subject: "tk-gate1", DraftDir: t.TempDir()})
	settle(m)
	typeText(m, q)
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if _, err := os.Stat(filepath.Join(state, "stalled")); err != nil {
		calls, _ := os.ReadFile(filepath.Join(state, "calls"))
		t.Fatalf("the save ended before the stub stalled it (%+v); its calls:\n%s", h.got, calls)
	}
	filed := Saved{Subject: "tk-held1", Conversation: "tk-conv1", Filed: true}
	if len(h.got) != 1 || h.got[0].saved != filed || !errors.Is(h.got[0].err, server.ErrToolTimeout) {
		t.Fatalf("the save killed in its reply answered %+v, want %+v and the timeout", h.got, filed)
	}
	if m.scr != progressScreen || m.saved == nil || m.saved.Conversation != "tk-conv1" || m.saveErr == "" || len(h.starts) != 0 {
		t.Fatalf("after the killed save: screen %d, saved %+v, saveErr %q, starts %v", m.scr, m.saved, m.saveErr, h.starts)
	}

	// A sitting another terminal started takes the conversation, and lifts the
	// hold on the PR's merge that the killed save put on.
	b, err := os.ReadFile(filepath.Join(state, "rows.json"))
	if err != nil {
		t.Fatal(err)
	}
	var store []map[string]any
	if err := json.Unmarshal(b, &store); err != nil {
		t.Fatal(err)
	}
	lifted := false
	for _, r := range store {
		switch r["id"] {
		case "tk-conv1":
			r["status"], r["assignee"] = "in_progress", "c-tk-conv1"
		case "tk-held1":
			deps, _ := r["dependencies"].([]any)
			kept := []any{}
			for _, d := range deps {
				if e, _ := d.(map[string]any); e["type"] == "blocks" && e["depends_on_id"] == "tk-conv1" {
					lifted = true
					continue
				}
				kept = append(kept, d)
			}
			r["dependencies"] = kept
		}
	}
	if !lifted {
		t.Fatalf("the killed save put no hold on the merge of tk-held1's PR, so there was none to lift:\n%s", b)
	}
	if b, err = json.Marshal(store); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(state, "rows.json"), b, 0o644); err != nil {
		t.Fatal(err)
	}

	_, cmd = m.Update(key('r'))
	deliver(m, cmd)
	want := SaveRequest{Ref: "tk-gate1", Subject: "tk-held1", Question: q, Conversation: "tk-conv1"}
	if len(h.saves) != 2 || h.saves[1] != want {
		t.Fatalf("saves = %+v, want the save again onto tk-conv1", h.saves)
	}
	if len(h.got) != 2 || h.got[1].saved != filed || h.got[1].err != nil {
		t.Fatalf("the save again answered %+v", h.got)
	}
	if len(h.starts) != 1 || h.starts[0] != "tk-conv1 claude-opus" {
		t.Fatalf("starts = %v, want tk-conv1", h.starts)
	}
	if b, err = os.ReadFile(filepath.Join(state, "rows.json")); err != nil {
		t.Fatal(err)
	}
	var after []struct {
		ID           string
		Dependencies []struct {
			Type        string `json:"type"`
			DependsOnID string `json:"depends_on_id"`
		}
	}
	if err := json.Unmarshal(b, &after); err != nil {
		t.Fatal(err)
	}
	conversations, replied, held := 0, false, false
	for _, r := range after {
		for _, d := range r.Dependencies {
			switch {
			case d.Type == "tracks" && d.DependsOnID == "tk-held1":
				conversations++
			case r.ID == "tk-conv1" && d.Type == "replies-to" && d.DependsOnID == "tk-gate1":
				replied = true
			case r.ID == "tk-held1" && d.Type == "blocks" && d.DependsOnID == "tk-conv1":
				held = true
			}
		}
	}
	if conversations != 1 || !replied {
		t.Fatalf("the store holds %d conversations on tk-held1, and tk-conv1 replies to tk-gate1: %v, want one that replies:\n%s", conversations, replied, b)
	}
	if held {
		t.Fatalf("the save again put back the hold on the merge of tk-held1's PR that the sitting lifted:\n%s", b)
	}
	calls, err := os.ReadFile(filepath.Join(state, "calls"))
	if err != nil {
		t.Fatal(err)
	}
	if n := strings.Count(string(calls), "bd create "); n != 1 {
		t.Fatalf("bd create ran %d times, want once:\n%s", n, calls)
	}
}
