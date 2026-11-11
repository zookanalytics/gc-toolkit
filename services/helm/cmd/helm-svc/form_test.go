package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/form"
)

// An interrupt fails the form's program and a termination quits it, each before
// the form has left by its own path. runProgram prints where the form kept the
// question it did not save: after the program's error on stderr for the
// interrupt, and on stdout for the termination.
func TestAFormSomethingElseEndsPrintsWhereItKeptTheQuestion(t *testing.T) {
	for _, c := range []struct {
		name    string
		msg     tea.Msg
		code    int
		errLine string
	}{
		{"interrupt", tea.InterruptMsg{}, 1, "helm-svc form: program was killed: program was interrupted\n"},
		{"termination", tea.QuitMsg{}, 0, ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			drafts := filepath.Join(dir, "drafts")
			// No gc-helm.sh is there, so each read the form starts fails and
			// nothing can be filed.
			m := form.New(context.Background(), form.Script{Path: filepath.Join(dir, "gc-helm.sh")}, form.Options{
				Subject:  "tk-a",
				Question: "the question",
				DraftDir: drafts,
			})
			// No input, so the message the test sends is all the program gets.
			p := tea.NewProgram(m, tea.WithInput(nil), tea.WithOutput(io.Discard), tea.WithoutSignalHandler())
			var stdout, stderr bytes.Buffer
			exit := make(chan int, 1)
			go func() { exit <- runProgram(p, m, &stdout, &stderr) }()
			p.Send(c.msg)
			var code int
			select {
			case code = <-exit:
			case <-time.After(10 * time.Second):
				t.Fatal("the form's program did not end within ten seconds")
			}
			files, _ := filepath.Glob(filepath.Join(drafts, "engage-draft-*.txt"))
			if len(files) != 1 {
				t.Fatalf("draft files %v; stdout %q, stderr %q", files, stdout.String(), stderr.String())
			}
			if b, _ := os.ReadFile(files[0]); string(b) != "the question" {
				t.Fatalf("kept draft = %q", b)
			}
			printed, other := stdout.String(), stderr.String()
			if c.code != 0 {
				printed, other = other, printed
			}
			want := c.errLine + "Nothing was filed. Your question is kept in " + files[0]
			if code != c.code || !strings.HasPrefix(printed, want) || other != "" {
				t.Fatalf("exit %d, want %d; printed %q, want it to start %q; the other stream %q", code, c.code, printed, want, other)
			}
		})
	}
}

// attachHelm is a form.Helm whose city holds one conversation to return to,
// and whose attach is the command the test gives it.
type attachHelm struct{ attach *exec.Cmd }

func (h attachHelm) About(context.Context, string, string) (form.About, error) {
	return form.About{}, errors.New("no subject here")
}
func (h attachHelm) City(context.Context) (form.City, error) {
	return form.City{Conversations: []form.Conversation{{ID: "tk-c1", Readiness: form.Ready}}}, nil
}
func (h attachHelm) Save(context.Context, form.SaveRequest) (form.Saved, error) {
	return form.Saved{}, errors.New("no save here")
}
func (h attachHelm) Start(context.Context, string, string) error { return errors.New("no start here") }
func (h attachHelm) AttachCommand(string, string) *exec.Cmd      { return h.attach }
func (h attachHelm) SeatCommand(string) *exec.Cmd                { return h.attach }

// A form that leaves to attach to a sitting runs the attach once its program
// has returned, so what the attach prints, such as engage's reason when it
// attaches nothing, comes after the last screen the form drew, and the attach's
// exit status is the form's.
func TestTheAttachRunsOnceTheFormHasLeft(t *testing.T) {
	attach := exec.Command("sh", "-c", "echo attaching; echo 'gc-helm: engage: why it attached nothing' >&2; exit 4")
	m := form.New(context.Background(), attachHelm{attach: attach}, form.Options{Return: true, DraftDir: t.TempDir()})
	p := tea.NewProgram(m, tea.WithInput(nil), tea.WithOutput(io.Discard), tea.WithoutSignalHandler())
	var stdout, stderr bytes.Buffer
	exit := make(chan int, 1)
	go func() { exit <- runProgram(p, m, &stdout, &stderr) }()
	// The return list reads the city as it opens, and an Enter once that read
	// has landed attaches the conversation it selected.
	var code int
	deadline := time.After(10 * time.Second)
	for waiting := true; waiting; {
		select {
		case code = <-exit:
			waiting = false
		case <-time.After(20 * time.Millisecond):
			p.Send(tea.KeyPressMsg{Code: tea.KeyEnter})
		case <-deadline:
			t.Fatal("the form did not leave to attach within ten seconds")
		}
	}
	if code != 4 || stdout.String() != "attaching\n" || stderr.String() != "gc-helm: engage: why it attached nothing\n" {
		t.Fatalf("exit %d, want 4; stdout %q, stderr %q", code, stdout.String(), stderr.String())
	}
}

// An attach that cannot run says so, and one a signal ends exits as a shell
// reports it.
func TestAnAttachThatDoesNotEndByItselfSaysHow(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runAttach(exec.Command(filepath.Join(t.TempDir(), "no-such-attach")), &stdout, &stderr)
	if code != 1 || !strings.HasPrefix(stderr.String(), "helm-svc form: the attach did not run: ") || stdout.Len() != 0 {
		t.Fatalf("exit %d, stdout %q, stderr %q", code, stdout.String(), stderr.String())
	}
	stderr.Reset()
	if code := runAttach(exec.Command("sh", "-c", "kill -TERM $$"), &stdout, &stderr); code != 143 || stderr.Len() != 0 {
		t.Fatalf("an attach a TERM ended: exit %d, want 143; stderr %q", code, stderr.String())
	}
}

// The form opens on one screen, so --return and --home together are refused
// before anything opens.
func TestTheFormOpensOnOneScreen(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := runForm([]string{"--helm", "gc-helm.sh", "--return", "--home"}, &stdout, &stderr); code != 2 {
		t.Fatalf("--return with --home exited %d", code)
	}
	if !strings.Contains(stderr.String(), "pass one") {
		t.Fatalf("stderr = %q", stderr.String())
	}
}
