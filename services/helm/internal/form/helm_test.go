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
	sv, err := s.Save(context.Background(), SaveRequest{Ref: "tk-g", Subject: "tk-s", Question: q})
	if err != nil || sv.Conversation != "tk-c" || !sv.Filed {
		t.Fatalf("Save = %+v, %v", sv, err)
	}
	got := argv(t, dir)
	want := []string{"open", "tk-g", "--allow-duplicate", "--if-subject", "tk-s", "--reason", q, "--json"}
	if strings.Join(got, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("argv = %q, want %q", got, want)
	}
}

func TestASaveWithNoSubjectShownRunsNothing(t *testing.T) {
	s, dir := stubHelm(t, `{"subject":"tk-s","conversation":"tk-c","filed":true}`, "", 0)
	if _, err := s.Save(context.Background(), SaveRequest{Ref: "tk-s", Question: "q"}); err == nil {
		t.Fatal("a save with no subject to check it against ran")
	}
	if _, err := os.Stat(filepath.Join(dir, "count")); !os.IsNotExist(err) {
		t.Fatalf("the stand-in ran: %v", err)
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
	_, err := s.About(context.Background(), "tk-x", "")
	if err == nil || !strings.Contains(err.Error(), "bead not found") {
		t.Fatalf("err = %v", err)
	}
	if got := argv(t, dir); strings.Join(got, " ") != "conversations tk-x --json" {
		t.Fatalf("argv = %q", got)
	}
}

// A gate reached from a subject is read and saved from it: --from rides each,
// after the reference it qualifies.
func TestAGateReachedFromASubjectIsReadAndSavedFromIt(t *testing.T) {
	s, dir := stubHelm(t, `{"ref":"tk-g","subject":{"id":"tk-s"},"gate":"tk-g"}`+"\n", "", 0)
	a, err := s.About(context.Background(), "tk-g", "tk-s")
	if err != nil || a.Subject.ID != "tk-s" || a.Gate != "tk-g" {
		t.Fatalf("About = %+v, %v", a, err)
	}
	if got := argv(t, dir); strings.Join(got, " ") != "conversations tk-g --from tk-s --json" {
		t.Fatalf("About argv = %q", got)
	}
	s, dir = stubHelm(t, `{"subject":"tk-s","conversation":"tk-c","filed":true}`+"\n", "", 0)
	if _, err := s.Save(context.Background(), SaveRequest{Ref: "tk-g", Subject: "tk-s", From: "tk-s", Question: "q", Conversation: "tk-c"}); err != nil {
		t.Fatal(err)
	}
	want := []string{"open", "tk-g", "--allow-duplicate", "--if-subject", "tk-s", "--from", "tk-s", "--conversation", "tk-c", "--reason", "q", "--json"}
	if got := argv(t, dir); strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("Save argv = %q, want %q", got, want)
	}
}

func TestCityTakesAListWhoseStoreDidNotAllAnswer(t *testing.T) {
	s, _ := stubHelm(t, `{"conversations":[{"id":"tk-c","readiness":"ready"}],"rigs":[{"name":"gc-toolkit","converse":true}],"unread":["gascity"]}`,
		"gc-helm: conversations: the store of gascity could not be read, so its conversations are not listed.\n", 4)
	c, err := s.City(context.Background())
	if err != nil || len(c.Conversations) != 1 || len(c.Unread) != 1 || c.Rigs[0].Name != "gc-toolkit" || !c.Rigs[0].Converse {
		t.Fatalf("City = %+v, %v", c, err)
	}
	s, _ = stubHelm(t, "", "gc-helm: conversations: could not read 'gc session list'\n", 4)
	if _, err := s.City(context.Background()); err == nil {
		t.Fatal("a refusal with no list read as a list")
	}
}

// A list whose agent roster did not read lists no seat and says so, and is
// still the list.
func TestCityTakesAListWhoseRosterDidNotRead(t *testing.T) {
	s, _ := stubHelm(t, `{"conversations":[{"id":"tk-c","readiness":"ready"}],"rigs":[{"name":"gc-toolkit","converse":true}],"seats":[],"roster_unread":true,"unread":[]}`+"\n",
		"gc-helm: conversations: could not read 'gc agent list', which gives each seat's session its name, so no seat is listed.\n", 4)
	c, err := s.City(context.Background())
	if err != nil || !c.RosterUnread || len(c.Seats) != 0 || len(c.Conversations) != 1 || c.Rigs[0].Name != "gc-toolkit" {
		t.Fatalf("City = %+v, %v", c, err)
	}
}

// A rig's prefix, which the subject can name it by, and a subject's suspended
// rig are read from the verbs' answers.
func TestARigsPrefixAndASubjectsSuspendedRigAreRead(t *testing.T) {
	s, _ := stubHelm(t, `{"conversations":[],"rigs":[{"name":"gc-toolkit","prefix":"tk","converse":true,"suspended":true}],"unread":[]}`+"\n", "", 0)
	c, err := s.City(context.Background())
	if err != nil || len(c.Rigs) != 1 || c.Rigs[0] != (Rig{Name: "gc-toolkit", Prefix: "tk", Converse: true, Suspended: true}) {
		t.Fatalf("City = %+v, %v", c, err)
	}
	s, _ = stubHelm(t, `{"ref":"tk-a","subject":{"id":"tk-a","rig":"gc-toolkit"},"refusal":"","rig_suspended":true}`+"\n", "", 0)
	a, err := s.About(context.Background(), "tk-a", "")
	if err != nil || !a.RigSuspended || a.Refusal != "" || a.Subject.Rig != "gc-toolkit" {
		t.Fatalf("About = %+v, %v", a, err)
	}
}

// The seats are read from the city's list in its order, each with its
// session, or none.
func TestTheSeatsAreReadWithTheirSessions(t *testing.T) {
	s, _ := stubHelm(t, `{"conversations":[],"rigs":[{"name":"gc-toolkit","prefix":"tk","converse":true,"suspended":false}],`+
		`"seats":[{"seat":"mechanik","rig":"","session":{"id":"lx-m","name":"gc-toolkit__mechanik","state":"active","attached":true,"created_at":"2026-08-31T04:11:47Z"}},`+
		`{"seat":"po","rig":"gc-toolkit","session":null}],"unread":[]}`+"\n", "", 0)
	c, err := s.City(context.Background())
	if err != nil || len(c.Seats) != 2 || c.RosterUnread {
		t.Fatalf("City = %+v, %v", c, err)
	}
	if m := c.Seats[0]; m.Name != "mechanik" || m.Rig != "" || m.Session == nil || m.Session.State != "active" || !m.Session.Attached {
		t.Fatalf("mechanik's seat = %+v", m)
	}
	if po := c.Seats[1]; po.Name != "po" || po.Rig != "gc-toolkit" || po.Session != nil {
		t.Fatalf("the po's seat = %+v", po)
	}
}

func TestStartAndAttachUseEngage(t *testing.T) {
	s, dir := stubHelm(t, "", "", 0)
	if err := s.Start(context.Background(), "tk-c", "codex-astra"); err != nil {
		t.Fatal(err)
	}
	if got := argv(t, dir); strings.Join(got, " ") != "engage tk-c --no-input --no-attach --model codex-astra" {
		t.Fatalf("argv = %q", got)
	}
	cmd := s.AttachCommand("tk-c", "")
	if got := strings.Join(cmd.Args, " "); got != "sh "+s.Path+" engage tk-c --no-input" {
		t.Fatalf("attach = %q", got)
	}
	cmd = s.AttachCommand("tk-c", "codex-astra")
	if got := strings.Join(cmd.Args, " "); got != "sh "+s.Path+" engage tk-c --no-input --model codex-astra" {
		t.Fatalf("attach on a model = %q", got)
	}
}

// A seat opens through its own verb: a rig's po through po --rig, and mechanik
// through mechanik.
func TestASeatOpensThroughItsVerb(t *testing.T) {
	s := Script{Path: "/pack/gc-helm.sh"}
	for _, c := range []struct{ seat, rig, want string }{
		{"po", "gc-toolkit", "sh /pack/gc-helm.sh po --rig gc-toolkit"},
		{"mechanik", "", "sh /pack/gc-helm.sh mechanik"},
	} {
		if got := strings.Join(s.SeatCommand(c.seat, c.rig).Args, " "); got != c.want {
			t.Fatalf("%s = %q, want %q", c.seat, got, c.want)
		}
	}
}

func TestASaveAgainNamesTheConversationItCompletes(t *testing.T) {
	s, dir := stubHelm(t, `{"subject":"tk-s","conversation":"tk-c","filed":true}`, "", 0)
	if _, err := s.Save(context.Background(), SaveRequest{Ref: "tk-g", Subject: "tk-s", Question: "q", Conversation: "tk-c"}); err != nil {
		t.Fatal(err)
	}
	want := []string{"open", "tk-g", "--allow-duplicate", "--if-subject", "tk-s", "--conversation", "tk-c", "--reason", "q", "--json"}
	if got := argv(t, dir); strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("argv = %q, want %q", got, want)
	}
	// A save again that names no subject would file a new topic, so it runs nothing.
	s, dir = stubHelm(t, `{"subject":"tk-s","conversation":"tk-c","filed":true}`, "", 0)
	if _, err := s.Save(context.Background(), SaveRequest{Rig: "gc-toolkit", Question: "q", Conversation: "tk-c"}); err == nil {
		t.Fatal("a save again with no subject ran")
	}
	if _, err := os.Stat(filepath.Join(dir, "count")); !os.IsNotExist(err) {
		t.Fatalf("the stand-in ran: %v", err)
	}
}
