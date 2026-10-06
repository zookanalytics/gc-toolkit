package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// merge.test.sh drives `gctk merge` end to end through stubbed gc/gh; these pin
// the pure pieces whose fail-closed reading is easy to lose in a refactor.

// `jq -cs` slurps the reviews stream whole or not at all. A stream that stops
// decoding after two good rows is unreadable, not a two-row history: the row
// it lost may be the veto, or the only approval.
func TestReviewStateRefusesAStreamThatStopsDecoding(t *testing.T) {
	good := `{"user":{"login":"human1"},"state":"APPROVED","commit_id":"h","submitted_at":"2026-01-01T00:00:00Z","id":1}` +
		`{"user":{"login":"human2"},"state":"COMMENTED","commit_id":"h","submitted_at":"2026-01-02T00:00:00Z","id":2}`
	for _, tail := range []string{
		`{"user":{"login":"human3"},"state":"CHANGES_REQ`, // truncated
		`garbage`, // garbled
		`"a string, not a review row"`,
	} {
		if _, ok := reviewState([]byte(good+tail), "bot"); ok {
			t.Errorf("reviewState(two rows + %q) ok = true; want false (unreadable)", tail)
		}
	}
	rs, ok := reviewState([]byte(good), "bot")
	if !ok || rs.approver != "human1" {
		t.Fatalf("reviewState(two good rows) = (%+v, %v); want approver human1, ok", rs, ok)
	}
}

// An empty history is a readable history with no reviews, as `jq -s` reads an
// empty stream as [].
func TestReviewStateReadsAnEmptyHistory(t *testing.T) {
	for _, raw := range []string{"", "   \n"} {
		rs, ok := reviewState([]byte(raw), "bot")
		if !ok || rs != (reviewSummary{}) {
			t.Errorf("reviewState(%q) = (%+v, %v); want the zero summary, ok", raw, rs, ok)
		}
	}
}

// `if has("isCrossRepository") then tostring else "" end`: only an absent key
// is empty. A present null is "null", which the cross-repo gate reports.
func TestJqHasToStringMirrorsHasThenToString(t *testing.T) {
	var absent struct {
		V json.RawMessage `json:"isCrossRepository"`
	}
	if err := json.Unmarshal([]byte(`{}`), &absent); err != nil {
		t.Fatal(err)
	}
	if got := jqHasToString(absent.V); got != "" {
		t.Errorf("absent key = %q, want empty", got)
	}
	for _, tc := range []struct{ raw, want string }{
		{`null`, "null"},
		{`false`, "false"},
		{`true`, "true"},
		{`"false"`, "false"},
	} {
		var row struct {
			V json.RawMessage `json:"isCrossRepository"`
		}
		if err := json.Unmarshal([]byte(`{"isCrossRepository":`+tc.raw+`}`), &row); err != nil {
			t.Fatal(err)
		}
		if got := jqHasToString(row.V); got != tc.want {
			t.Errorf("isCrossRepository=%s reads %q, want %q", tc.raw, got, tc.want)
		}
	}
}

// A binary run without GCTK_SCRIPTS_DIR, or with a directory missing the
// helpers every anchor's validation runs, refuses the pass rather than holding
// each anchor on a helper it cannot find.
func TestHelperDirProblemRefusesAnUnusableDirectory(t *testing.T) {
	if p := helperDirProblem(""); !strings.Contains(p, "GCTK_SCRIPTS_DIR is unset") {
		t.Errorf("unset dir: problem = %q, want the unset diagnosis", p)
	}
	dir := t.TempDir()
	if p := helperDirProblem(dir); !strings.Contains(p, "lane-state.sh or finalize-gate.sh") {
		t.Errorf("empty dir: problem = %q, want both missing helpers named", p)
	}
	for _, h := range mergeRequiredHelpers {
		if err := os.WriteFile(filepath.Join(dir, h), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if p := helperDirProblem(dir); p != "" {
		t.Errorf("complete dir: problem = %q, want none", p)
	}
	if err := os.Chmod(filepath.Join(dir, "finalize-gate.sh"), 0o644); err != nil {
		t.Fatal(err)
	}
	if p := helperDirProblem(dir); !strings.Contains(p, "finalize-gate.sh") || strings.Contains(p, "lane-state.sh") {
		t.Errorf("non-executable finalize-gate.sh: problem = %q, want only it named", p)
	}
}

// `(.status // "open")` defaults only a null or absent status. A row whose
// status is the empty string is not live and holds nothing.
func TestIsLiveDefaultsOnlyANullStatusToOpen(t *testing.T) {
	rows := func(raw string) []gcbd.Bead {
		dec := json.NewDecoder(bytes.NewReader([]byte(raw)))
		dec.UseNumber()
		var out []gcbd.Bead
		if err := dec.Decode(&out); err != nil {
			t.Fatal(err)
		}
		return out
	}
	for _, tc := range []struct {
		row  string
		live bool
	}{
		{`{"id":"x"}`, true},
		{`{"id":"x","status":null}`, true},
		{`{"id":"x","status":"BLOCKED"}`, true},
		{`{"id":"x","status":""}`, false},
		{`{"id":"x","status":"closed"}`, false},
	} {
		b := rows("[" + tc.row + "]")
		if got := isLive(&b[0]); got != tc.live {
			t.Errorf("isLive(%s) = %v, want %v", tc.row, got, tc.live)
		}
		if got := stuckHolder(b) != ""; got != tc.live {
			t.Errorf("stuckHolder(%s) holds = %v, want %v", tc.row, got, tc.live)
		}
	}
}
