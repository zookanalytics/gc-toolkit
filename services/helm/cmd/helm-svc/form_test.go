package main

import (
	"bytes"
	"context"
	"io"
	"os"
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
