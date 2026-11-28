package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// The pass needs the agents whose sessions it reads: a run that names none is
// a usage error, refused before it reads anything.
func TestMailNotifyNeedsItsAgents(t *testing.T) {
	for _, args := range [][]string{
		{"mail", "notify"},
		{"mail", "notify", "--agents", ""},
		{"mail", "notify", "--agents", " , "},
	} {
		var out, errb bytes.Buffer
		if code := Run(args, "test", &out, &errb); code != 2 {
			t.Errorf("%q exited %d: %s", args, code, errb.String())
		}
		if out.Len() != 0 || !strings.Contains(errb.String(), "agents") {
			t.Errorf("%q printed %q and %q", args, out.String(), errb.String())
		}
	}
}

// mailStub puts a gc on PATH that answers a peek of the mail hq-m1, marks it
// unread, and answers its archive with archive, a line of shell.
func mailStub(t *testing.T, archive string) {
	t.Helper()
	bin := t.TempDir()
	stub := "#!/bin/sh\ncase \"$*\" in\n" +
		"  \"mail peek hq-m1 --json\") echo '{\"message\":{\"id\":\"hq-m1\",\"from\":\"tools/gc-toolkit.polecat\",\"subject\":\"NOTICE: x\",\"body\":\"b\"}}' ;;\n" +
		"  \"mail mark-unread hq-m1\") : ;;\n" +
		"  \"mail archive hq-m1\") " + archive + " ;;\n" +
		"  *) echo \"stub gc: no answer for $*\" >&2; exit 9 ;;\nesac\n"
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
}

// A finding filed whose mail did not archive succeeds, and names the command
// that archives the mail.
func TestAMailFindingThatDidNotArchiveNamesTheArchive(t *testing.T) {
	mailStub(t, "echo 'mail store busy' >&2; exit 1")
	scriptStub(t, "patrol-finding.sh")
	var out, errb bytes.Buffer
	if code := Run([]string{"mail", "finding", "hq-m1", "--key", "k"}, "", &out, &errb); code != 0 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	if !strings.Contains(errb.String(), "filed mail hq-m1 under k, but it was not archived: ") ||
		!strings.HasSuffix(errb.String(), ". Archive it with gc mail archive hq-m1\n") {
		t.Errorf("stderr %q", errb.String())
	}
}

// A filing whose bound passes while its writer runs ends the writer and files
// nothing.
func TestAMailFindingPastItsBoundEndsItsWriter(t *testing.T) {
	mailStub(t, ":")
	started := blockedWriter(t, "patrol-finding.sh")
	bound := mailFindingBound
	mailFindingBound = time.Second
	t.Cleanup(func() { mailFindingBound = bound })

	var out, errb bytes.Buffer
	code := make(chan int, 1)
	go func() { code <- Run([]string{"mail", "finding", "hq-m1", "--key", "k"}, "", &out, &errb) }()
	pid := started()
	select {
	case got := <-code:
		if got != 1 {
			t.Errorf("exit %d, want 1", got)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the filing did not end at its bound while its writer ran")
	}
	if !strings.Contains(errb.String(), "nothing filed for mail hq-m1") || !strings.Contains(errb.String(), "was stopped") {
		t.Errorf("stderr %q", errb.String())
	}
	writerGone(t, pid)
}
