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
	"strconv"
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

// merge.sh's loop: --deadline and --cursor each take the argument after them,
// even one that looks like a flag, and anything else is passed over. A flag
// that ends the arguments reads as empty.
func TestMergePaceArgsReadsTheFlagsAsMergeShDoes(t *testing.T) {
	for _, tc := range []struct {
		args             []string
		deadline, cursor string
	}{
		{nil, "", ""},
		{[]string{"--cursor", "/s/merge.cursor", "--deadline", "1791339999"}, "1791339999", "/s/merge.cursor"},
		{[]string{"stray", "--deadline", "5", "--other"}, "5", ""},
		{[]string{"--deadline", "--cursor", "c"}, "--cursor", ""},
		{[]string{"--cursor", "c", "--deadline"}, "", "c"},
	} {
		d, c := mergePaceArgs(tc.args)
		if d != tc.deadline || c != tc.cursor {
			t.Errorf("mergePaceArgs(%q) = (%q, %q), want (%q, %q)", tc.args, d, c, tc.deadline, tc.cursor)
		}
	}
}

// The visit order puts an anchor first unless what it read without a per-PR
// call already rules out its merge this pass. A PR that has left the open list
// goes first, for its record.
func TestLandsFirstHoldsBackOnlyWhatCannotLandThisPass(t *testing.T) {
	approved := `{"state":"APPROVED","submittedAt":"2026-08-20T01:00:00Z","databaseId":1,"author":{"login":"human1"}}`
	var nodes []openPR
	if err := json.Unmarshal([]byte(`[
	  {"number":1,"isDraft":false,"headRefOid":"h1","latestOpinionatedReviews":{"nodes":[`+approved+`]}},
	  {"number":2,"isDraft":true,"headRefOid":"h2","latestOpinionatedReviews":{"nodes":[`+approved+`]}},
	  {"number":3,"isDraft":false,"headRefOid":"h3","latestOpinionatedReviews":{"nodes":[]}},
	  {"number":4,"isDraft":false,"headRefOid":"h4","latestOpinionatedReviews":{"nodes":[{"state":"APPROVED","submittedAt":"2026-08-20T01:00:00Z","databaseId":1,"author":{"login":"bot"}}]}},
	  {"number":5,"isDraft":false,"headRefOid":"h5","latestOpinionatedReviews":{"nodes":[`+approved+`,{"state":"CHANGES_REQUESTED","submittedAt":"2026-08-21T01:00:00Z","databaseId":2,"author":{"login":"human2"}}]}},
	  {"number":6,"isDraft":false,"headRefOid":"h6","latestOpinionatedReviews":{"nodes":[{"state":"APPROVED","submittedAt":"2026-08-20T01:00:00Z","databaseId":1,"author":null}]}}
	]`), &nodes); err != nil {
		t.Fatal(err)
	}
	open := map[string]*openPR{}
	for i := range nodes {
		open[nodes[i].Number.String()] = &nodes[i]
	}
	for _, tc := range []struct {
		name  string
		meta  string // metadata members after pr_number
		num   string
		self  string
		first bool
	}{
		{"approved, nothing held", `,"check_set":"correctness"`, `"1"`, "bot", true},
		{"pr_number stored as a number", `,"check_set":"correctness"`, `1`, "bot", true},
		{"left the open list", `,"check_set":"correctness"`, `"9"`, "bot", true},
		{"left the open list, no acting login", `,"check_set":"correctness"`, `"9"`, "", true},
		{"no acting login", `,"check_set":"correctness"`, `"1"`, "", false},
		{"draft", `,"check_set":"correctness"`, `"2"`, "bot", false},
		{"merge_hold set", `,"check_set":"correctness","merge_hold":"true"`, `"1"`, "bot", false},
		{"merge_hold false", `,"check_set":"correctness","merge_hold":false`, `"1"`, "bot", true},
		{"merge_hold 0", `,"check_set":"correctness","merge_hold":"0"`, `"1"`, "bot", true},
		{"comments unanswered", `,"check_set":"correctness","pr_posture":"commented@h1@2026-10-06T00:00:00Z"`, `"1"`, "bot", false},
		{"another posture", `,"check_set":"correctness","pr_posture":"review_required@h1@2026-10-06T00:00:00Z"`, `"1"`, "bot", true},
		{"no check_set", `,"check_set":" , "`, `"1"`, "bot", false},
		{"no approval", `,"check_set":"correctness"`, `"3"`, "bot", false},
		{"only the acting login approved", `,"check_set":"correctness"`, `"4"`, "bot", false},
		{"a later veto", `,"check_set":"correctness"`, `"5"`, "bot", false},
		{"approved only by an account with no login", `,"check_set":"correctness"`, `"6"`, "bot", false},
		{"DIRTY at the live head", `,"check_set":"correctness","pr_merge_state":"DIRTY@h1"`, `"1"`, "bot", false},
		{"BLOCKED at the live head", `,"check_set":"correctness","pr_merge_state":"BLOCKED@h1"`, `"1"`, "bot", false},
		{"BEHIND at the live head", `,"check_set":"correctness","pr_merge_state":"BEHIND@h1"`, `"1"`, "bot", false},
		{"DIRTY at an older head", `,"check_set":"correctness","pr_merge_state":"DIRTY@h0"`, `"1"`, "bot", true},
		{"DIRTY with no head", `,"check_set":"correctness","pr_merge_state":"DIRTY"`, `"1"`, "bot", true},
		{"CLEAN at the live head", `,"check_set":"correctness","pr_merge_state":"CLEAN@h1"`, `"1"`, "bot", true},
		{"UNSTABLE at the live head", `,"check_set":"correctness","pr_merge_state":"UNSTABLE@h1"`, `"1"`, "bot", true},
		{"UNKNOWN at the live head", `,"check_set":"correctness","pr_merge_state":"UNKNOWN@h1"`, `"1"`, "bot", true},
	} {
		a := beadRows(t, `[{"id":"A1","metadata":{"pr_number":`+tc.num+tc.meta+`}}]`)[0]
		m := &merger{selfLogin: tc.self}
		if got := m.landsFirst(a, open); got != tc.first {
			t.Errorf("%s: landsFirst = %v, want %v", tc.name, got, tc.first)
		}
	}
}

// stubGH puts a `gh` on PATH that records its arguments and answers with the
// payload and exit status given.
func stubGH(t *testing.T, payload string, rc int) (argsFile string) {
	t.Helper()
	dir := t.TempDir()
	pf := filepath.Join(dir, "payload")
	if err := os.WriteFile(pf, []byte(payload), 0o644); err != nil {
		t.Fatal(err)
	}
	argsFile = filepath.Join(dir, "args")
	script := fmt.Sprintf("#!/bin/sh\nprintf '%%s' \"$*\" > '%s'\ncat '%s'\nexit %d\n", argsFile, pf, rc)
	if err := os.WriteFile(filepath.Join(dir, "gh"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return argsFile
}

// The open-PR read is one paginated GraphQL call, and `jq -s` reads its stream
// whole or not at all: a failed call, an empty answer, a page that does not
// decode, or a page with no pullRequests leaves the pass unpaced, never paced
// on the PRs that did decode.
func TestOpenPRsReadsTheWholeStreamOrNothing(t *testing.T) {
	page := func(more bool, nodes string) string {
		return `{"data":{"repository":{"pullRequests":{"pageInfo":{"hasNextPage":` + strconv.FormatBool(more) +
			`,"endCursor":"c"},"nodes":[` + nodes + `]}}}}`
	}
	p1 := page(true, `{"number":61,"isDraft":false,"headRefOid":"sha-61","latestOpinionatedReviews":{"nodes":[{"state":"APPROVED","submittedAt":"2026-08-20T01:00:00Z","databaseId":1,"author":{"login":"human1"}}]}}`)
	p2 := page(false, `{"number":62,"isDraft":true,"headRefOid":"sha-62","latestOpinionatedReviews":{"nodes":[]}}`)
	m := &merger{originHost: "github.com", originRepo: "zook/gc-toolkit"}

	args := stubGH(t, p1+"\n"+p2+"\n", 0)
	open, ok := m.openPRs()
	if !ok || len(open) != 2 || open["61"] == nil || open["62"] == nil || !open["62"].IsDraft {
		t.Fatalf("two good pages: (%v, ok=%v); want PRs 61 and 62, 62 a draft", open, ok)
	}
	if v := reviewVerdict(open["61"].reviews(), "bot"); v.approver != "human1" || v.veto != "" {
		t.Errorf("PR 61 verdict = %+v, want approver human1 and no veto", v)
	}
	want := "api graphql --hostname github.com --paginate -f query=" + openPRsQuery + " -f owner=zook -f repo=gc-toolkit"
	if got := readFile(t, args); got != want {
		t.Errorf("gh args =\n%s\nwant\n%s", got, want)
	}

	stubGH(t, page(false, ""), 0)
	if open, ok := m.openPRs(); !ok || len(open) != 0 {
		t.Errorf("an empty open list: (%v, ok=%v); want readable and empty", open, ok)
	}

	for _, tc := range []struct {
		name, payload string
		rc            int
	}{
		{"a failed call", p1, 1},
		{"no answer", "", 0},
		{"a page cut short", p1 + "\n" + p2[:40], 0},
		{"bytes that are not JSON after a good page", p1 + "\ngarbage", 0},
		{"a page with no pullRequests", p1 + "\n" + `{"data":{"repository":{"pullRequests":null}}}`, 0},
		{"a GraphQL error", `{"data":null,"errors":[{"message":"timeout"}]}`, 0},
		{"a node that does not decode", page(false, `{"number":63,"isDraft":"yes"}`), 0},
	} {
		stubGH(t, tc.payload, tc.rc)
		if open, ok := m.openPRs(); ok {
			t.Errorf("%s: (%v, ok=true); want unreadable", tc.name, open)
		}
	}
}
