package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// merge.test.sh drives `gctk merge` end to end through stubbed gc/gh; these pin
// the pure pieces whose fail-closed reading is easy to lose in a refactor, and
// the supervisor-API read seam, which that suite cannot reach because its
// harness pins GC_NO_API.

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

// A re-read of an UNKNOWN merge state may differ from the pinned read only in
// the mergeability facts, and the hold names every other field that changed.
// The comparison is gh_pr_view_settled's jq `!=`, so key order and number
// spelling are no change, and a key one read lacks reads as null. Each want is
// what that jq prints for the same two reads.
func TestChangedFieldsMirrorsTheScriptsComparison(t *testing.T) {
	row := func(raw string) map[string]json.RawMessage {
		var r map[string]json.RawMessage
		if err := json.Unmarshal([]byte(raw), &r); err != nil {
			t.Fatal(err)
		}
		return r
	}
	pinned := row(`{"state":"OPEN","headRefOid":"a","headRepository":{"name":"r","id":1},"mergeStateStatus":"UNKNOWN","mergeable":"UNKNOWN","reviewDecision":""}`)
	for _, tc := range []struct{ again, want string }{
		{`{"state":"OPEN","headRefOid":"a","headRepository":{"id":1.0,"name":"r"},"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE","reviewDecision":"APPROVED"}`, ""},
		{`{"state":"MERGED","headRefOid":"b","headRepository":{"name":"r","id":1}}`, `headRefOid 'a' -> 'b', state 'OPEN' -> 'MERGED'`},
		{`{"state":"OPEN","headRefOid":"a","headRepository":{"name":"s","id":1}}`, `headRepository '{"name":"r","id":1}' -> '{"name":"s","id":1}'`},
		{`{"state":"OPEN","headRepository":{"name":"r","id":1}}`, `headRefOid 'a' -> 'null'`},
	} {
		if got := changedFields(pinned, row(tc.again)); got != tc.want {
			t.Errorf("changedFields(again=%s) = %q, want %q", tc.again, got, tc.want)
		}
	}
}

// `(.mergeStateStatus // "") | tostring`: a missing, null or false state reads
// as "", which the re-read spends like an UNKNOWN; any other value is computed.
func TestJqAltStringMirrorsAlternativeThenToString(t *testing.T) {
	for _, tc := range []struct{ raw, want string }{
		{``, ""}, {`null`, ""}, {`false`, ""}, {`"CLEAN"`, "CLEAN"}, {`true`, "true"}, {`5`, "5"},
	} {
		if got := jqAltString(json.RawMessage(tc.raw)); got != tc.want {
			t.Errorf("jqAltString(%q) = %q, want %q", tc.raw, got, tc.want)
		}
	}
}

// MERGE_STATE_REREADS and MERGE_STATE_REREAD_SECS take their default unless the
// value is all digits, as bd-lib.sh's case guard does, so a negative or garbled
// value cannot lift the pass's re-read budget.
func TestEnvCountTakesTheDefaultUnlessAllDigits(t *testing.T) {
	for _, tc := range []struct {
		val  string
		want int
	}{
		{"", 3}, {"0", 0}, {"7", 7}, {"-1", 3}, {"2x", 3}, {" 4", 3},
	} {
		t.Setenv("GCTK_TEST_COUNT", tc.val)
		if got := envCount("GCTK_TEST_COUNT", 3); got != tc.want {
			t.Errorf("envCount(%q) = %d, want %d", tc.val, got, tc.want)
		}
	}
}

// A binary run without GCTK_SCRIPTS_DIR refuses the pass: every helper would be
// a bare name, found through PATH if at all. A named directory is not refused
// for a helper it lacks, because merge.sh has no such pass-level check. A
// missing helper fails where it is called, and the pass still records a PR
// that has already merged (merge.test.sh pins that in both arms).
func TestHelperDirProblemRefusesOnlyAnUnsetDirectory(t *testing.T) {
	if p := helperDirProblem(""); !strings.Contains(p, "GCTK_SCRIPTS_DIR is unset") {
		t.Errorf("unset dir: problem = %q, want the unset diagnosis", p)
	}
	if p := helperDirProblem(t.TempDir()); p != "" {
		t.Errorf("a named dir without the helpers: problem = %q, want none", p)
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

// The merge decides off the anchor's live row, so both re-reads take it from
// the store, never from the supervisor API's cache: a merge_hold written after
// the daemon cached the bead must still hold the merge. The fake supervisor
// serves the anchor without the hold and the stubbed `gc` serves it with one.
// The Show control proves the daemon path is live here, so the anchorRow
// assertion cannot pass on a client that never consulted the daemon.
func TestAnchorRowReadsTheStoreNotTheSupervisorCache(t *testing.T) {
	const cached = `{"id":"H1","status":"open","metadata":{"merge_result":"pull_request","pr_number":"60"}}`
	const stored = `[{"id":"H1","status":"open","metadata":{"merge_result":"pull_request","pr_number":"60","merge_hold":"true"}}]`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, cached)
	}))
	t.Cleanup(srv.Close)
	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	host, port, err := net.SplitHostPort(u.Host)
	if err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	toml := fmt.Sprintf("[supervisor]\nbind = %q\nport = %s\n", host, port)
	if err := os.WriteFile(filepath.Join(home, "supervisor.toml"), []byte(toml), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := t.TempDir()
	stub := "#!/bin/sh\ncat <<'GCEOF'\n" + stored + "\nGCEOF\n"
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GC_NO_API", "")
	t.Setenv("GC_HOME", home)
	t.Setenv("GC_CITY_PATH", filepath.Join(t.TempDir(), "testcity"))
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	c := gcbd.New()
	if b := c.Show("H1"); b == nil || b.Meta("pr_number") != "60" || b.Meta("merge_hold") != "" {
		t.Fatalf("control: Show = %+v; want the supervisor's cached row, without merge_hold", b)
	}
	m := &merger{client: c}
	b, ok := m.anchorRow("H1")
	if !ok || b.Meta("merge_hold") != "true" {
		t.Fatalf("anchorRow = (%+v, %v); want the stored row, merge_hold=true, not the supervisor's cached row", b, ok)
	}
}
