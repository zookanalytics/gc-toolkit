package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// pace_start: an empty deadline is no deadline; one that is not epoch seconds
// leaves the walk unpaced and says so once; epoch 1 has always passed.
func TestNewPacerReadsTheDeadlineAsPaceStartDoes(t *testing.T) {
	future := strconv.FormatInt(time.Now().Unix()+600, 10)
	for _, tc := range []struct {
		deadline string
		spent    bool
		warn     bool
	}{
		{"", false, false},
		{"1", true, false},
		{future, false, false},
		{"99999999999999999999999", false, false},
		{"soon", false, true},
		{"17x", false, true},
		{"-5", false, true},
		{"1.5", false, true},
	} {
		var errb bytes.Buffer
		p := newPacer("", tc.deadline, &errb)
		if got := p.spent(); got != tc.spent {
			t.Errorf("deadline %q: spent = %v, want %v", tc.deadline, got, tc.spent)
		}
		want := ""
		if tc.warn {
			want = "merge: WARN --deadline '" + tc.deadline + "' is not epoch seconds; this pass is not paced\n"
		}
		if errb.String() != want {
			t.Errorf("deadline %q: stderr = %q, want %q", tc.deadline, errb.String(), want)
		}
	}
}

// A walk started past its deadline still visits one anchor, and the next visit
// is where it stops and where the next pass resumes. The anchor visited is
// recorded once that next visit begins.
func TestPacerVisitsOneAnchorPastTheDeadlineAndNamesWhereToResume(t *testing.T) {
	cur := filepath.Join(t.TempDir(), "merge.cursor")
	p := newPacer(cur, "1", &bytes.Buffer{})
	if !p.visit("A") {
		t.Fatal("the first visit past the deadline was refused; one is always made")
	}
	if p.visit("B") {
		t.Fatal("a second visit past the deadline went ahead")
	}
	p.end()
	if p.visited != 1 || p.resumeAt != "B" {
		t.Errorf("visited=%d resumeAt=%q, want 1 and B", p.visited, p.resumeAt)
	}
	if got := readFile(t, cur); got != "A\n" {
		t.Errorf("cursor = %q, want the anchor the walk finished, A", got)
	}
}

// An anchor counts as finished only once the walk's next visit begins, or the
// walk ends. A pass killed mid-anchor leaves the cursor on the anchor before
// it, so the next pass resumes at the one it was on.
func TestPacerRecordsAnAnchorWhenTheNextVisitBegins(t *testing.T) {
	cur := filepath.Join(t.TempDir(), "merge.cursor")
	p := newPacer(cur, "", &bytes.Buffer{})
	p.visit("A")
	if _, err := os.Stat(cur); !os.IsNotExist(err) {
		t.Fatalf("the cursor was written while A was still in hand (stat err %v)", err)
	}
	p.visit("B")
	if got := readFile(t, cur); got != "A\n" {
		t.Errorf("cursor after B began = %q, want A", got)
	}
	p.end()
	if got := readFile(t, cur); got != "B\n" {
		t.Errorf("cursor after the walk ended = %q, want B", got)
	}
	if p.visited != 2 || p.resumeAt != "" {
		t.Errorf("visited=%d resumeAt=%q, want 2 and none", p.visited, p.resumeAt)
	}
}

// A cursor that cannot be written costs the rotation, not the pass, and says so
// once however many anchors the walk finishes. With no cursor path nothing is
// recorded and nothing is said.
func TestPacerWarnsOnceWhenTheCursorCannotBeWritten(t *testing.T) {
	cur := filepath.Join(t.TempDir(), "missing-dir", "merge.cursor")
	var errb bytes.Buffer
	p := newPacer(cur, "", &errb)
	for _, id := range []string{"A", "B", "C"} {
		if !p.visit(id) {
			t.Fatalf("visit %s refused with no deadline", id)
		}
	}
	p.end()
	want := "merge: WARN cannot record progress in " + cur + "; the next pass starts the rotation over\n"
	if errb.String() != want {
		t.Errorf("stderr = %q, want one warning %q", errb.String(), want)
	}

	errb.Reset()
	p = newPacer("", "", &errb)
	p.visit("A")
	p.visit("B")
	p.end()
	if errb.Len() != 0 {
		t.Errorf("no cursor path: stderr = %q, want nothing", errb.String())
	}
}

// pace_order: id order starting after the cursor's id and wrapping, whether or
// not that id is still in the set. No cursor path keeps the order the rows
// came in, and an absent cursor file starts at the lowest id.
func TestPaceOrderRotatesAfterTheCursorAndWraps(t *testing.T) {
	rows := beadRows(t, `[{"id":"C"},{"id":"A"},{"id":"D"},{"id":"B"}]`)
	dir := t.TempDir()
	cur := filepath.Join(dir, "merge.cursor")
	if got := ids(paceOrder(rows, "")); got != "C,A,D,B" {
		t.Errorf("no cursor path: %s, want the rows as they came, C,A,D,B", got)
	}
	if got := ids(paceOrder(rows, cur)); got != "A,B,C,D" {
		t.Errorf("absent cursor file: %s, want A,B,C,D", got)
	}
	for _, tc := range []struct{ cursor, want string }{
		{"B\n", "C,D,A,B"},
		{"D\n", "A,B,C,D"},
		{"Z\n", "A,B,C,D"},
		{"BB\n", "C,D,A,B"},
		{"B", "C,D,A,B"},
		{"B\nD\n", "C,D,A,B"},
	} {
		if err := os.WriteFile(cur, []byte(tc.cursor), 0o644); err != nil {
			t.Fatal(err)
		}
		if got := ids(paceOrder(rows, cur)); got != tc.want {
			t.Errorf("cursor file %q: %s, want %s", tc.cursor, got, tc.want)
		}
	}
	if got := ids(rows); got != "C,A,D,B" {
		t.Errorf("paceOrder reordered its input in place: %s", got)
	}
}

func beadRows(t *testing.T, raw string) []*gcbd.Bead {
	t.Helper()
	var rows []gcbd.Bead
	dec := json.NewDecoder(strings.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&rows); err != nil {
		t.Fatal(err)
	}
	out := make([]*gcbd.Bead, len(rows))
	for i := range rows {
		out[i] = &rows[i]
	}
	return out
}

func ids(rows []*gcbd.Bead) string {
	s := make([]string, len(rows))
	for i, r := range rows {
		s[i] = r.ID
	}
	return strings.Join(s, ",")
}

func readFile(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
