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
// stdin when it reads --body-file -, and answers `bd update` with a line. `bd
// show` answers with SHOW_REPLY_<n>, where n is the number of updates so far,
// when the test set one (showAfter), and with SHOW_REPLY otherwise, so a test
// says what the store holds after each write. It returns the log path and the
// stdin path.
func createStub(t *testing.T, createReply string, createRC int, showReply string) (string, string) {
	t.Helper()
	t.Setenv("GC_NO_API", "1")
	dir := t.TempDir()
	log := filepath.Join(dir, "gc.log")
	stdin := filepath.Join(dir, "stdin")
	stub := `#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
n=$(grep -c '^bd update' "$STUB_LOG")
case "$1 $2" in
  "bd create")
    case " $* " in *" --body-file - "*) cat > "$STUB_STDIN" ;; esac
    printf '%s\n' "$CREATE_REPLY"
    exit "$CREATE_RC" ;;
  "bd show")
    v="SHOW_REPLY_$n"
    if [ -n "${!v+x}" ]; then printf '%s\n' "${!v}"; else printf '%s\n' "$SHOW_REPLY"; fi ;;
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

// showAfter sets what `bd show` answers once n updates have been made.
func showAfter(t *testing.T, n int, reply string) {
	t.Helper()
	t.Setenv("SHOW_REPLY_"+strconv.Itoa(n), reply)
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
		id, err := New().Create(reviewMeta, nil, "", "Review branch b -> main (correctness): t", "-t", "task")
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
	if _, err := New().Create(map[string]any{"task_kind": "review"}, nil, "line one\nline two\n", "t", "-t", "task"); err != nil {
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
		id, err := New().Create(meta, nil, "", "t", "-t", "task")
		if id != "" || !errors.Is(err, ErrNotFiled) {
			t.Errorf("Create(%v) = (%q, %v), want ErrNotFiled", meta, id, err)
		}
	}
	id, err := New().Create(reviewMeta, []string{"anchor_bead", "branch"}, "", "t")
	if id != "" || !errors.Is(err, ErrNotFiled) || !strings.Contains(err.Error(), `"branch"`) {
		t.Errorf("sel naming a key the metadata lacks: Create = (%q, %v), want ErrNotFiled naming it", id, err)
	}
	if lines := calls(t, log); len(lines) != 0 {
		t.Errorf("a refused payload still called gc: %q", lines)
	}
}

func TestCreateReportsWhatBdRefused(t *testing.T) {
	createStub(t, `{"error":"title too long"}`, 1, `[]`)
	id, err := New().Create(reviewMeta, nil, "", "t", "-t", "task")
	if id != "" || !errors.Is(err, ErrNotFiled) || !strings.Contains(err.Error(), "title too long") {
		t.Fatalf("Create = (%q, %v), want ErrNotFiled naming bd's reason", id, err)
	}
	for _, reply := range []string{`not-json`, ``, `[]`, `{"id":null}`, `{"id":""}`} {
		createStub(t, reply, 0, `[]`)
		if id, err := New().Create(reviewMeta, nil, "", "t"); id != "" || !errors.Is(err, ErrNotFiled) {
			t.Errorf("reply %q: Create = (%q, %v), want ErrNotFiled", reply, id, err)
		}
	}
}

const (
	bareRow   = `[{"id":"n-1","status":"open","metadata":{}}]`
	closedRow = `[{"id":"n-1","status":"closed","metadata":{"gc.outcome":"abandoned"}}]`
)

// A bead still bare after the second write is closed, and the close is read
// back before Create says nothing was filed.
func TestCreateClosesABeadThatLandedBare(t *testing.T) {
	log, _ := createStub(t, `{"id":"n-1"}`, 0, bareRow)
	showAfter(t, 2, closedRow)
	id, err := New().Create(reviewMeta, nil, "", "t", "-t", "task")
	if id != "" || !errors.Is(err, ErrNotFiled) || !strings.Contains(err.Error(), "was closed") {
		t.Fatalf("Create = (%q, %v), want ErrNotFiled with no id, closed", id, err)
	}
	updates := callsWith(calls(t, log), "bd update n-1")
	if len(updates) != 2 {
		t.Fatalf("want the second write and the close, got %q", updates)
	}
	for _, k := range []string{"anchor_bead=tk-anc", "pr_number=42", "task_kind=review"} {
		if !strings.Contains(updates[0], "--set-metadata "+k) {
			t.Errorf("the second write does not carry %s: %q", k, updates[0])
		}
	}
	if !strings.Contains(updates[1], "--status=closed --set-metadata gc.outcome=abandoned --append-notes") {
		t.Errorf("the bare bead was not closed as abandoned: %q", updates[1])
	}
	if got := callsWith(calls(t, log), "bd show n-1"); len(got) != 3 {
		t.Errorf("want the read-back, the read after the second write and the close's read-back, got %q", got)
	}
}

func TestCreateReportsACloseThatDidNotReadBack(t *testing.T) {
	createStub(t, `{"id":"n-1"}`, 0, bareRow)
	id, err := New().Create(reviewMeta, nil, "", "t")
	if id != "" || !errors.Is(err, ErrNotFiled) || !strings.Contains(err.Error(), "would not close") {
		t.Fatalf("Create = (%q, %v), want ErrNotFiled saying the bead would not close", id, err)
	}
}

func TestCreateWritesAShortBeadWholeOnce(t *testing.T) {
	log, _ := createStub(t, `{"id":"n-1"}`, 0, `[{"id":"n-1","metadata":{"task_kind":"review"}}]`)
	showAfter(t, 1, `[{"id":"n-1","metadata":{"task_kind":"review","anchor_bead":"tk-anc","pr_number":42}}]`)
	id, err := New().Create(reviewMeta, []string{"anchor_bead"}, "", "t")
	if id != "n-1" || err != nil {
		t.Fatalf("Create = (%q, %v), want (n-1, nil) once the second write lands", id, err)
	}
	if u := callsWith(calls(t, log), "bd update n-1"); len(u) != 1 {
		t.Errorf("want one write of the whole payload, got %q", u)
	}
}

// sel names the keys the caller's probe finds the bead by: still short of one
// after the second write, the bead is closed; short only of another, it is
// left open for the caller's next run.
func TestCreateClosesABeadShortOfASelKey(t *testing.T) {
	short := `[{"id":"n-1","status":"open","metadata":{"task_kind":"review","pr_number":42}}]`
	log, _ := createStub(t, `{"id":"n-1"}`, 0, short)
	showAfter(t, 2, closedRow)
	id, err := New().Create(reviewMeta, []string{"task_kind", "anchor_bead"}, "", "t")
	if id != "" || !errors.Is(err, ErrNotFiled) || !strings.Contains(err.Error(), "carrying anchor_bead") {
		t.Fatalf("Create = (%q, %v), want ErrNotFiled naming anchor_bead", id, err)
	}
	if u := callsWith(calls(t, log), "bd update n-1"); len(u) != 2 || !strings.Contains(u[1], "--status=closed") {
		t.Errorf("want the second write and then the close, got %q", u)
	}
	log, _ = createStub(t, `{"id":"n-1"}`, 0, short)
	id, err = New().Create(reviewMeta, []string{"task_kind", "pr_number"}, "", "t")
	if id != "n-1" || !errors.Is(err, ErrUnverified) || !strings.Contains(err.Error(), "short: anchor_bead") {
		t.Fatalf("short of an unselected key: Create = (%q, %v), want (n-1, ErrUnverified)", id, err)
	}
	if u := callsWith(calls(t, log), "bd update n-1"); len(u) != 1 || strings.Contains(u[0], "--status=closed") {
		t.Errorf("a findable bead was closed, or not written whole once: %q", u)
	}
}

func TestCreateLeavesAPartialOrUnreadBeadOpen(t *testing.T) {
	for name, tc := range map[string]struct {
		show    string
		updates int
	}{
		"partial":      {`[{"id":"n-1","metadata":{"task_kind":"review","anchor_bead":"tk-other","pr_number":42}}]`, 1},
		"missing key":  {`[{"id":"n-1","metadata":{"task_kind":"review"}}]`, 1},
		"unreadable":   {``, 0},
		"another bead": {`[{"id":"n-9","metadata":{"task_kind":"review","anchor_bead":"tk-anc","pr_number":42}}]`, 0},
		"empty answer": {`[]`, 0},
		"error object": {`{"error":"not found"}`, 0},
	} {
		log, _ := createStub(t, `{"id":"n-1"}`, 0, tc.show)
		id, err := New().Create(reviewMeta, nil, "", "t")
		if id != "n-1" || !errors.Is(err, ErrUnverified) {
			t.Errorf("%s: Create = (%q, %v), want (n-1, ErrUnverified)", name, id, err)
		}
		u := callsWith(calls(t, log), "bd update")
		if len(u) != tc.updates {
			t.Errorf("%s: want %d writes (the second write, never a close), got %q", name, tc.updates, u)
		}
		for _, l := range u {
			if strings.Contains(l, "--status=closed") {
				t.Errorf("%s: a findable or unread bead was closed: %q", name, l)
			}
		}
	}
}

// A value written as a number reads back as text after a re-stamp, and the
// reverse; both are the same value the way the scripts read it. false and null
// read back as themselves, typed or as text, and never match an empty value.
func TestCreateComparesValuesAsText(t *testing.T) {
	createStub(t, `{"id":"n-1"}`, 0, `[{"id":"n-1","metadata":{"n":"7","s":7,"b":"true"}}]`)
	if id, err := New().Create(map[string]any{"n": 7, "s": "7", "b": true}, nil, "", "t"); err != nil || id != "n-1" {
		t.Fatalf("Create = (%q, %v), want (n-1, nil)", id, err)
	}
	createStub(t, `{"id":"n-1"}`, 0, `[{"id":"n-1","metadata":{"f":false,"z":null,"sf":"false","sz":"null"}}]`)
	if id, err := New().Create(map[string]any{"f": false, "z": nil, "sf": false, "sz": nil}, nil, "", "t"); err != nil || id != "n-1" {
		t.Fatalf("false and null: Create = (%q, %v), want (n-1, nil)", id, err)
	}
	for _, got := range []string{`{"k":"v","f":""}`, `{"k":"v","f":null}`, `{"k":"v"}`} {
		createStub(t, `{"id":"n-1"}`, 0, `[{"id":"n-1","metadata":`+got+`}]`)
		if id, err := New().Create(map[string]any{"f": false, "k": "v"}, nil, "", "t"); !errors.Is(err, ErrUnverified) || id != "n-1" {
			t.Errorf("false against %s: Create = (%q, %v), want (n-1, ErrUnverified)", got, id, err)
		}
	}
}

func TestReadBackJudgesFalseAndNullAsThemselves(t *testing.T) {
	for _, tc := range []struct {
		meta, got map[string]any
		want      string
	}{
		{map[string]any{"f": false}, map[string]any{"f": false}, "landed"},
		{map[string]any{"f": false}, map[string]any{"f": "false"}, "landed"},
		{map[string]any{"f": false}, map[string]any{"f": ""}, "partial"},
		{map[string]any{"z": nil}, map[string]any{"z": nil}, "landed"},
		{map[string]any{"z": nil}, map[string]any{"z": ""}, "partial"},
		{map[string]any{"e": ""}, map[string]any{"e": false}, "partial"},
		{map[string]any{"f": false}, map[string]any{}, "bare"},
	} {
		if v, _ := readBack(tc.meta, tc.got); v != tc.want {
			t.Errorf("readBack(%v, %v) = %q, want %q", tc.meta, tc.got, v, tc.want)
		}
	}
}

func TestCreateReadsBackAndClosesInTheStoreItWrote(t *testing.T) {
	for _, args := range [][]string{{"t", "--db", "/x/.beads"}, {"t", "--db=/x/.beads"}} {
		log, _ := createStub(t, `{"id":"n-1"}`, 0, bareRow)
		showAfter(t, 2, closedRow)
		_, _ = New().Create(reviewMeta, nil, "", args...)
		lines := calls(t, log)
		s := callsWith(lines, "bd show n-1")
		if len(s) != 3 {
			t.Errorf("args %q: want three reads, got %q", args, s)
		}
		for _, l := range s {
			if !strings.Contains(l, "--db /x/.beads") {
				t.Errorf("args %q: a read does not name the create's store: %q", args, l)
			}
		}
		u := callsWith(lines, "bd update n-1")
		if len(u) != 2 {
			t.Errorf("args %q: want the second write and the close, got %q", args, u)
		}
		for _, l := range u {
			if !strings.Contains(l, "--db /x/.beads") {
				t.Errorf("args %q: a write does not name the create's store: %q", args, l)
			}
		}
	}
}
