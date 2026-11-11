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
	"slices"
	"sort"
	"strings"
	"testing"
)

// The fixture is real gc-toolkit beads, cut from the store in the shape the
// read gathers: three epics with their members, gates, conversations,
// decisions and edges, and every bead the readers read about them.
// testdata/gc-toolkit.board.json is the document the read builds from it.
var (
	fixturePath = filepath.Join("testdata", "gc-toolkit.fixture.json")
	goldenPath  = filepath.Join("testdata", "gc-toolkit.board.json")
)

// fixtureEpics are the epics the fixture is cut around: the ones the Claude
// Design export of the board was drawn from.
var fixtureEpics = []string{"tk-wmwcdlc", "tk-ssm8qns", "tk-yhquh93"}

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

// fakeGC answers the read's gc calls from rows, as the store would: the open
// listing with the gates, a parent's closed members, beads by id, and the one
// rig the fixture holds.
type fakeGC struct {
	rows  []bead
	calls [][]string
}

func newFakeGC(t *testing.T, raw []json.RawMessage) *fakeGC {
	t.Helper()
	f := &fakeGC{}
	for _, r := range raw {
		var b bead
		if err := json.Unmarshal(r, &b); err != nil {
			t.Fatal(err)
		}
		f.rows = append(f.rows, b)
	}
	return f
}

func flagValue(args []string, name string) (string, bool) {
	for i, a := range args {
		if a == name && i+1 < len(args) {
			return args[i+1], true
		}
	}
	return "", false
}

func (f *fakeGC) JSON(_ context.Context, out any, args ...string) error {
	f.calls = append(f.calls, slices.Clone(args))
	if len(args) >= 2 && args[0] == "rig" && args[1] == "list" {
		return remarshal(map[string]any{"rigs": []map[string]string{{"name": "gc-toolkit", "path": "/fixture/gc-toolkit"}}}, out)
	}
	if len(args) < 4 || args[0] != "bd" || args[3] != "list" {
		return fmt.Errorf("the fake gc answers no %v", args)
	}
	var rows []bead
	ids, byID := flagValue(args, "--id")
	parent, byParent := flagValue(args, "--parent")
	status, _ := flagValue(args, "--status")
	all := slices.Contains(args, "--all")
	for _, b := range f.rows {
		switch {
		case byID:
			if slices.Contains(strings.Split(ids, ","), b.ID) {
				rows = append(rows, b)
			}
		case byParent:
			if slices.Contains(b.parents(), parent) && (status == "" || b.status() == status) {
				rows = append(rows, b)
			}
		case all || b.open():
			if b.issueType() != "gate" || slices.Contains(args, "--include-gates") {
				rows = append(rows, b)
			}
		}
	}
	return remarshal(rows, out)
}

func remarshal(v, out any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, out)
}

// stubHolds runs the waits package over the fixture through the pack's stub
// store (assets/scripts/holds-store.stub.sh answering gctk's `gc bd` reads),
// so the fixture's answers are the package's and no test restates its rule.
func stubHolds(t *testing.T, raw []json.RawMessage) HoldsReader {
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
	rows, err := json.Marshal(raw)
	if err != nil {
		t.Fatal(err)
	}
	store := filepath.Join(dir, "store.json")
	if err := os.WriteFile(store, rows, 0o644); err != nil {
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
	return ReadHolds
}

// TestFixtureBoard builds the document from the fixture through the read's
// own gather, and holds it to the golden document. `go test
// ./internal/rigboard -run TestFixtureBoard -update` writes the golden again.
func TestFixtureBoard(t *testing.T) {
	raw := loadFixture(t)
	gc := newFakeGC(t, raw)
	readHolds := stubHolds(t, raw)
	rigs, err := ReadRigs(context.Background(), gc)
	if err != nil {
		t.Fatal(err)
	}
	doc, err := Read(context.Background(), gc, rigs[0], readHolds)
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

// encodeGolden writes the document with one row per line, so a change to the
// read shows in a diff as the rows it moves.
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
	fmt.Fprintf(&buf, " },\n \"epics\": %s,\n \"needs_you\": %s,\n \"work_queue\": %s,\n \"unprioritized\": %s\n}\n",
		line(doc.Epics), line(doc.NeedsYou), line(doc.WorkQueue), line(doc.Unprioritized))
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
