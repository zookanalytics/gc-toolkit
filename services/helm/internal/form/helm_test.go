package form

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// stubHelm writes a gc-helm.sh stand-in that records each argument of its run
// in its own file, prints out on stdout and err on stderr, and exits code.
func stubHelm(t *testing.T, out, err string, code int) (Script, string) {
	t.Helper()
	dir := t.TempDir()
	argDir := filepath.Join(dir, "args")
	if e := os.MkdirAll(argDir, 0o755); e != nil {
		t.Fatal(e)
	}
	body := `#!/bin/sh
i=0
for a in "$@"; do i=$((i + 1)); printf '%s' "$a" > "` + argDir + `/$i"; done
printf '%s' "$i" > "` + argDir + `/count"
cat "` + dir + `/out"
cat "` + dir + `/err" >&2
exit ` + strconv.Itoa(code) + `
`
	for name, content := range map[string]string{"out": out, "err": err} {
		if e := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); e != nil {
			t.Fatal(e)
		}
	}
	path := filepath.Join(dir, "gc-helm.sh")
	if e := os.WriteFile(path, []byte(body), 0o755); e != nil {
		t.Fatal(e)
	}
	return Script{Path: path}, argDir
}

// argv reads back the arguments the stand-in recorded.
func argv(t *testing.T, argDir string) []string {
	t.Helper()
	n, err := os.ReadFile(filepath.Join(argDir, "count"))
	if err != nil {
		t.Fatalf("the stand-in did not run: %v", err)
	}
	count, err := strconv.Atoi(string(n))
	if err != nil {
		t.Fatalf("argument count %q: %v", n, err)
	}
	var args []string
	for i := 1; i <= count; i++ {
		b, _ := os.ReadFile(filepath.Join(argDir, strconv.Itoa(i)))
		args = append(args, string(b))
	}
	return args
}

func TestSaveSendsTheQuestionAsOneUnchangedArgument(t *testing.T) {
	q := "line one\n\n\tindented — ünïcödé\ntrailing space \n"
	s, dir := stubHelm(t, `{"subject":"tk-s","conversation":"tk-c","filed":true}`+"\n", "", 0)
	sv, err := s.Save(context.Background(), SaveRequest{Ref: "tk-s", Question: q})
	if err != nil || sv.Conversation != "tk-c" || !sv.Filed {
		t.Fatalf("Save = %+v, %v", sv, err)
	}
	got := argv(t, dir)
	want := []string{"open", "tk-s", "--allow-duplicate", "--reason", q, "--json"}
	if strings.Join(got, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("argv = %q, want %q", got, want)
	}
}

func TestSaveFilesANewTopicInTheNamedRig(t *testing.T) {
	s, dir := stubHelm(t, `{"subject":"tk-s","conversation":"tk-c","filed":true}`, "", 0)
	if _, err := s.Save(context.Background(), SaveRequest{Rig: "gascity", Question: "q"}); err != nil {
		t.Fatal(err)
	}
	want := []string{"open", "--new-subject", "--rig", "gascity", "--reason", "q", "--json"}
	if got := argv(t, dir); strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("argv = %q", got)
	}
}

func TestASubjectFiledWithoutItsConversationComesBackWithTheError(t *testing.T) {
	s, _ := stubHelm(t, `{"subject":"tk-s","conversation":"","filed":false}`+"\n",
		"gc-helm: open: filed subject tk-s\ngc-helm: open: subject tk-s was filed, but its conversation was not.\n", 4)
	sv, err := s.Save(context.Background(), SaveRequest{Rig: "gc-toolkit", Question: "q"})
	var r *Refusal
	if !errors.As(err, &r) || r.Code != 4 || !strings.Contains(r.Why, "its conversation was not") {
		t.Fatalf("err = %v", err)
	}
	if sv.Subject != "tk-s" || sv.Filed {
		t.Fatalf("Saved = %+v", sv)
	}
}

func TestAboutRefusalCarriesTheScriptsSentence(t *testing.T) {
	s, dir := stubHelm(t, "", "gc-helm: conversations: bead not found: 'tk-x' — no rig ledger answers for that id. Nothing read.\n", 4)
	_, err := s.About(context.Background(), "tk-x")
	if err == nil || !strings.Contains(err.Error(), "bead not found") {
		t.Fatalf("err = %v", err)
	}
	if got := argv(t, dir); strings.Join(got, " ") != "conversations tk-x --json" {
		t.Fatalf("argv = %q", got)
	}
}

func TestCityTakesAListWhoseStoreDidNotAllAnswer(t *testing.T) {
	s, _ := stubHelm(t, `{"conversations":[{"id":"tk-c","readiness":"ready"}],"rigs":[{"name":"gc-toolkit","converse":true}],"unread":["gascity"]}`,
		"gc-helm: conversations: the store of gascity did not answer\n", 4)
	c, err := s.City(context.Background())
	if err != nil || len(c.Conversations) != 1 || len(c.Unread) != 1 || !c.Rigs[0].Hosts() {
		t.Fatalf("City = %+v, %v", c, err)
	}
	s, _ = stubHelm(t, "", "gc-helm: conversations: could not read 'gc session list'\n", 4)
	if _, err := s.City(context.Background()); err == nil {
		t.Fatal("a refusal with no list read as a list")
	}
}

func TestStartAndAttachUseEngage(t *testing.T) {
	s, dir := stubHelm(t, "", "", 0)
	if err := s.Start(context.Background(), "tk-c", "fable"); err != nil {
		t.Fatal(err)
	}
	if got := argv(t, dir); strings.Join(got, " ") != "engage tk-c --no-input --no-attach --model fable" {
		t.Fatalf("argv = %q", got)
	}
	cmd := s.AttachCommand("tk-c")
	if got := strings.Join(cmd.Args, " "); got != "sh "+s.Path+" engage tk-c --no-input" {
		t.Fatalf("attach = %q", got)
	}
}
