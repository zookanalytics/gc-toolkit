package rigboard

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"testing"
)

// The fixture is real gc-toolkit beads, cut from the store in the shape the
// listing reads: three epics with their members, gates, conversations,
// decisions and edges, and every bead the readers read about them.
// testdata/gc-toolkit.board.json is the document the read builds from it.
var (
	fixturePath = filepath.Join("testdata", "gc-toolkit.fixture.json")
	goldenPath  = filepath.Join("testdata", "gc-toolkit.board.json")
)

// fixtureEpics are the epics the fixture is cut around: the ones the Claude
// Design export of the board was drawn from, and the one the operator adopted
// the board's two views on.
var fixtureEpics = []string{"tk-wmwcdlc", "tk-ssm8qns", "tk-yhquh93", "tk-1tfzr71"}

// fixtureFile is the fixture as committed: what was cut and left out, and the
// beads, one per line.
type fixtureFile struct {
	About map[string]any    `json:"about"`
	Rows  []json.RawMessage `json:"rows"`
}

func loadFixture(t *testing.T) []json.RawMessage {
	t.Helper()
	raw, err := os.ReadFile(fixturePath)
	if err != nil {
		t.Fatal(err)
	}
	var f fixtureFile
	if err := json.Unmarshal(raw, &f); err != nil {
		t.Fatalf("%s: %v", fixturePath, err)
	}
	return f.Rows
}

// stubStore puts a gc on PATH that answers every read gctk's listing makes
// from rows, through the pack's stub store (assets/scripts/holds-store.stub.sh),
// so the board is read as the service reads it and no test restates a reader's
// rule. It returns the rig the rows are the store of.
func stubStore(t *testing.T, rows []json.RawMessage) Rig {
	t.Helper()
	for _, tool := range []string{"bash", "jq"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip(tool + " is not on PATH, so the stub store cannot answer")
		}
	}
	stub, err := filepath.Abs(filepath.Join("..", "..", "..", "..", "assets", "scripts", "holds-store.stub.sh"))
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	raw, err := json.Marshal(rows)
	if err != nil {
		t.Fatal(err)
	}
	store := filepath.Join(dir, "store.json")
	if err := os.WriteFile(store, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	shim := "#!/bin/sh\n[ \"$1\" = bd ] || exit 2\nshift\nexec bash \"$HOLDS_STUB\" answer \"$@\"\n"
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("HOLDS_STUB", stub)
	t.Setenv("HOLDS_STORE", store)
	t.Setenv("GC_NO_API", "1")
	return Rig{Name: "gc-toolkit", Store: "/fixture/gc-toolkit/.beads"}
}

// TestFixtureBoard builds the document from the fixture through the read
// itself, and holds it to the golden document. `go test ./internal/rigboard
// -run TestFixtureBoard -update` writes the golden again.
func TestFixtureBoard(t *testing.T) {
	rig := stubStore(t, loadFixture(t))
	doc, err := Read(context.Background(), rig)
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	got := encodeGolden(t, doc)
	if *updateTypes {
		if err := os.WriteFile(goldenPath, got, 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(goldenPath)
	if err != nil {
		t.Fatalf("%v; go test ./internal/rigboard -run TestFixtureBoard -update writes it", err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("the document built from %s differs from %s: go test ./internal/rigboard -run TestFixtureBoard -update writes it again, and git diff shows what moved", fixturePath, goldenPath)
	}
}

// encodeGolden writes the document with one row and one epic per line, so a
// change to the read shows in a diff as the rows and epics it moves.
func encodeGolden(t *testing.T, doc Document) []byte {
	t.Helper()
	var buf bytes.Buffer
	line := func(v any) string {
		b, err := json.Marshal(v)
		if err != nil {
			t.Fatal(err)
		}
		return string(b)
	}
	fmt.Fprintf(&buf, "{\n \"rig\": %s,\n \"rows\": {\n", line(doc.Rig))
	ids := make([]string, 0, len(doc.Rows))
	for id := range doc.Rows {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for i, id := range ids {
		sep := ","
		if i == len(ids)-1 {
			sep = ""
		}
		fmt.Fprintf(&buf, "  %s: %s%s\n", line(id), line(doc.Rows[id]), sep)
	}
	fmt.Fprintf(&buf, " },\n \"epics\": [\n")
	for i, e := range doc.Epics {
		sep := ","
		if i == len(doc.Epics)-1 {
			sep = ""
		}
		fmt.Fprintf(&buf, "  %s%s\n", line(e), sep)
	}
	fmt.Fprintf(&buf, " ],\n \"needs_you\": %s,\n \"work_queue\": %s,\n \"unprioritized\": %s\n}\n",
		line(doc.NeedsYou), line(doc.WorkQueue), line(doc.Unprioritized))
	return buf.Bytes()
}

// privateText matches text the fixture never carries whatever the city: a host
// path or an email address. The cut also leaves out the city's other rigs, by
// the names and bead ids the city gives at the time.
var privateText = regexp.MustCompile(`/Users/|/private/|/home/|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}`)

// TestFixtureHoldsNoPrivateText scans every string in the fixture and the
// golden document for a host path or an email address.
func TestFixtureHoldsNoPrivateText(t *testing.T) {
	for _, p := range []string{fixturePath, goldenPath} {
		raw, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		var v any
		if err := json.Unmarshal(raw, &v); err != nil {
			t.Fatalf("%s: %v", p, err)
		}
		walkStrings(v, func(s string) {
			if m := privateText.FindString(s); m != "" {
				t.Errorf("%s carries %q in %.80q", p, m, s)
			}
		})
	}
}

func walkStrings(v any, f func(string)) {
	switch x := v.(type) {
	case string:
		f(x)
	case []any:
		for _, e := range x {
			walkStrings(e, f)
		}
	case map[string]any:
		for k, e := range x {
			f(k)
			walkStrings(e, f)
		}
	}
}
