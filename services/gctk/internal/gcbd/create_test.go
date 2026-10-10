package gcbd

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// createStub puts a `gc` on PATH that logs each call's argv, one line per call,
// answers `bd create` with CREATE_REPLY at exit CREATE_RC, saves the create's
// stdin when it reads --body-file -, answers `bd show` with SHOW_REPLY, and
// answers `bd update` with a line. It returns the log path and the stdin path.
func createStub(t *testing.T, createReply string, createRC int, showReply string) (string, string) {
	t.Helper()
	t.Setenv("GC_NO_API", "1")
	dir := t.TempDir()
	log := filepath.Join(dir, "gc.log")
	stdin := filepath.Join(dir, "stdin")
	stub := `#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "bd create")
    case " $* " in *" --body-file - "*) cat > "$STUB_STDIN" ;; esac
    printf '%s\n' "$CREATE_REPLY"
    exit "$CREATE_RC" ;;
  "bd show") printf '%s\n' "$SHOW_REPLY" ;;
  "bd update") echo "updated $3" ;;
esac
`
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", log)
	t.Setenv("STUB_STDIN", stdin)
	t.Setenv("CREATE_REPLY", createReply)
	t.Setenv("CREATE_RC", strconv.Itoa(createRC))
	t.Setenv("SHOW_REPLY", showReply)
	return log, stdin
}

func calls(t *testing.T, log string) []string {
	t.Helper()
	raw, err := os.ReadFile(log)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		t.Fatal(err)
	}
	return strings.Split(strings.TrimRight(string(raw), "\n"), "\n")
}

func callsWith(lines []string, prefix string) []string {
	var out []string
	for _, l := range lines {
		if strings.HasPrefix(l, prefix) {
			out = append(out, l)
		}
	}
	return out
}

var reviewMeta = map[string]any{"task_kind": "review", "anchor_bead": "tk-anc", "pr_number": 42}

func TestCreateFilesTheMetadataInTheCreateAndReadsItBack(t *testing.T) {
	for _, reply := range []string{`{"id":"n-1"}`, `[{"id":"n-1"}]`} {
		log, _ := createStub(t, reply, 0,
			`[{"id":"n-1","status":"open","metadata":{"task_kind":"review","anchor_bead":"tk-anc","pr_number":"42"}}]`)
		id, err := New().Create(reviewMeta, "", "Review branch b -> main (correctness): t", "-t", "task")
		if err != nil || id != "n-1" {
			t.Fatalf("reply %s: Create = (%q, %v), want (n-1, nil)", reply, id, err)
		}
		lines := calls(t, log)
		creates := callsWith(lines, "bd create")
		if len(creates) != 1 {
			t.Fatalf("reply %s: %d creates, want 1: %q", reply, len(creates), lines)
		}
		if !strings.Contains(creates[0], `--metadata {"anchor_bead":"tk-anc","pr_number":42,"task_kind":"review"} --json`) {
			t.Errorf("reply %s: the create does not carry the payload: %q", reply, creates[0])
		}
		if got := callsWith(lines, "bd update"); len(got) != 0 {
			t.Errorf("reply %s: a landed create made a second write: %q", reply, got)
		}
		if got := callsWith(lines, "bd show n-1"); len(got) != 1 {
			t.Errorf("reply %s: want one read-back of n-1, got %q", reply, got)
		}
	}
}

func TestCreateSendsTheBodyOnStdin(t *testing.T) {
	log, stdin := createStub(t, `{"id":"n-1"}`, 0, `[{"id":"n-1","metadata":{"task_kind":"review"}}]`)
	if _, err := New().Create(map[string]any{"task_kind": "review"}, "line one\nline two\n", "t", "-t", "task"); err != nil {
		t.Fatalf("Create = %v", err)
	}
	got, err := os.ReadFile(stdin)
	if err != nil || string(got) != "line one\nline two\n" {
		t.Fatalf("stdin = %q (%v), want the body", got, err)
	}
	if c := callsWith(calls(t, log), "bd create"); len(c) != 1 || !strings.Contains(c[0], "--body-file -") {
		t.Errorf("the create does not read its body from stdin: %q", c)
	}
}

func TestCreateRefusesEmptyMetadataBeforeAnyCall(t *testing.T) {
	log, _ := createStub(t, `{"id":"n-1"}`, 0, `[]`)
	for _, meta := range []map[string]any{nil, {}} {
		id, err := New().Create(meta, "", "t", "-t", "task")
		if id != "" || !errors.Is(err, ErrNotFiled) {
			t.Errorf("Create(%v) = (%q, %v), want ErrNotFiled", meta, id, err)
		}
	}
	if lines := calls(t, log); len(lines) != 0 {
		t.Errorf("a refused payload still called gc: %q", lines)
	}
}

func TestCreateReportsWhatBdRefused(t *testing.T) {
	createStub(t, `{"error":"title too long"}`, 1, `[]`)
	id, err := New().Create(reviewMeta, "", "t", "-t", "task")
	if id != "" || !errors.Is(err, ErrNotFiled) || !strings.Contains(err.Error(), "title too long") {
		t.Fatalf("Create = (%q, %v), want ErrNotFiled naming bd's reason", id, err)
	}
	for _, reply := range []string{`not-json`, ``, `[]`, `{"id":null}`, `{"id":""}`} {
		createStub(t, reply, 0, `[]`)
		if id, err := New().Create(reviewMeta, "", "t"); id != "" || !errors.Is(err, ErrNotFiled) {
			t.Errorf("reply %q: Create = (%q, %v), want ErrNotFiled", reply, id, err)
		}
	}
}

func TestCreateClosesABeadThatLandedBare(t *testing.T) {
	log, _ := createStub(t, `{"id":"n-1"}`, 0, `[{"id":"n-1","status":"open","metadata":{}}]`)
	id, err := New().Create(reviewMeta, "", "t", "-t", "task")
	if id != "" || !errors.Is(err, ErrNotFiled) {
		t.Fatalf("Create = (%q, %v), want ErrNotFiled with no id", id, err)
	}
	updates := callsWith(calls(t, log), "bd update n-1")
	if len(updates) != 1 || !strings.Contains(updates[0], "--status=closed --set-metadata gc.outcome=abandoned --append-notes") {
		t.Fatalf("the bare bead was not closed as abandoned: %q", updates)
	}
}

func TestCreateLeavesAPartialOrUnreadBeadOpen(t *testing.T) {
	for name, show := range map[string]string{
		"partial":      `[{"id":"n-1","metadata":{"task_kind":"review","anchor_bead":"tk-other","pr_number":42}}]`,
		"missing key":  `[{"id":"n-1","metadata":{"task_kind":"review"}}]`,
		"unreadable":   ``,
		"another bead": `[{"id":"n-9","metadata":{"task_kind":"review","anchor_bead":"tk-anc","pr_number":42}}]`,
		"empty answer": `[]`,
		"error object": `{"error":"not found"}`,
	} {
		log, _ := createStub(t, `{"id":"n-1"}`, 0, show)
		id, err := New().Create(reviewMeta, "", "t")
		if id != "n-1" || !errors.Is(err, ErrUnverified) {
			t.Errorf("%s: Create = (%q, %v), want (n-1, ErrUnverified)", name, id, err)
		}
		if u := callsWith(calls(t, log), "bd update"); len(u) != 0 {
			t.Errorf("%s: an unverified bead was written to: %q", name, u)
		}
	}
}

// A value written as a number reads back as text after a re-stamp, and the
// reverse; both are the same value the way the scripts read it.
func TestCreateComparesValuesAsText(t *testing.T) {
	createStub(t, `{"id":"n-1"}`, 0, `[{"id":"n-1","metadata":{"n":"7","s":7,"b":"true"}}]`)
	if id, err := New().Create(map[string]any{"n": 7, "s": "7", "b": true}, "", "t"); err != nil || id != "n-1" {
		t.Fatalf("Create = (%q, %v), want (n-1, nil)", id, err)
	}
}

func TestCreateReadsBackAndClosesInTheStoreItWrote(t *testing.T) {
	for _, args := range [][]string{{"t", "--db", "/x/.beads"}, {"t", "--db=/x/.beads"}} {
		log, _ := createStub(t, `{"id":"n-1"}`, 0, `[{"id":"n-1","metadata":{}}]`)
		_, _ = New().Create(reviewMeta, "", args...)
		lines := calls(t, log)
		if s := callsWith(lines, "bd show n-1"); len(s) != 1 || !strings.Contains(s[0], "--db /x/.beads") {
			t.Errorf("args %q: the read-back does not name the create's store: %q", args, s)
		}
		if u := callsWith(lines, "bd update n-1"); len(u) != 1 || !strings.Contains(u[0], "--db /x/.beads") {
			t.Errorf("args %q: the close does not name the create's store: %q", args, u)
		}
	}
}
