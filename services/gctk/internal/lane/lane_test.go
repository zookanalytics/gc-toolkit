package lane

// The 16 shell assertions of assets/scripts/lane-state.test.sh, one Go test
// each, driven against gcbdtest.Fake and fake remotes — no subprocess, no PATH.
// Each carries the shell's ok-message so the two suites map one-to-one; the
// tests after them cover what the shell suite leaves untested (every failure
// of the fallback chain, the paginated stream's corners, OriginSlug).

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
)

// The fixtures of lane-state.test.sh, byte for byte.
const anchorJSON = `{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{"merge_result":"pull_request","check_set":"correctness","pr_number":"42"}}`

// review is the suite's review() helper: a closed review bead whose (status,
// verdict, outcome, check_name) vary per case.
func review(status, verdict, outcome string, check ...string) string {
	g := "correctness"
	if len(check) > 0 {
		g = check[0]
	}
	return fmt.Sprintf(`{"id":"rv-1","status":"%s","assignee":"","title":"review","notes":"","metadata":{"task_kind":"review","check_name":"%s","anchor_bead":"tk-anc","reviewed_oid":"deadbeef","signoff_verdict":"%s","gc.outcome":"%s"}}`, status, g, verdict, outcome)
}

// store decodes the suite's `store "[...]"` payload into a Fake, through the
// same decoder shape the Client uses (UseNumber), so a numeric pr_number reads
// back as jq's tostring would render it.
func store(t *testing.T, rows ...string) *gcbdtest.Fake {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader([]byte("[" + strings.Join(rows, ",") + "]")))
	dec.UseNumber()
	var beads []gcbd.Bead
	if err := dec.Decode(&beads); err != nil {
		t.Fatalf("fixture: %v", err)
	}
	return gcbdtest.New(beads...)
}

// streamApprover stands in for the gh stub: it serves the bytes a test wrote to
// $GH_DIR/reviews_42.json through the same stream reader GHApprover uses, and
// records what it was asked, so a test asserts the slug and PR the fallback
// named.
type streamApprover struct {
	body  string
	asked []string
}

func (a *streamApprover) ApprovedReviewOnPR(slug, pr string) (bool, bool) {
	a.asked = append(a.asked, slug+"#"+pr)
	return ApprovedInStream([]byte(a.body))
}

// fakeApprover answers a fixed pair.
type fakeApprover struct{ approved, ok bool }

func (a fakeApprover) ApprovedReviewOnPR(string, string) (bool, bool) { return a.approved, a.ok }

// fakeOrigin answers ok=false: a non-GitHub origin or one git could not read.
type fakeOrigin struct{}

func (fakeOrigin) Slug() (string, bool) { return "", false }

// remote is the harness's remote: STUB_ORIGIN_URL's slug and a reviews fixture.
func remote(body string) (Remote, *streamApprover) {
	a := &streamApprover{body: body}
	return Remote{Origin: FixedSlug("zook/gc-toolkit"), Approver: a}, a
}

// listArgs is the one `bd list` the derivation issues, as the stub logged it.
const listArgs = "bd list --metadata-field anchor_bead=tk-anc --status=open,in_progress,blocked,deferred,hooked,pinned,closed --limit=0 --json\n"

func green(t *testing.T, f *gcbdtest.Fake, r Remote, lane string, noRemote bool) Verdict {
	t.Helper()
	v, err := Green(f, r, "tk-anc", lane, noRemote)
	if (err != nil) != (v == Unreadable) {
		t.Fatalf("Green = (%v, %v): an error rides Unreadable and nothing else", v, err)
	}
	return v
}

func want(t *testing.T, got, want Verdict, msg string) {
	t.Helper()
	if got != want {
		t.Fatalf("%s: verdict %v, want %v", msg, got, want)
	}
}

// lane-state.test.sh #1: an unreviewed lane is not green
func TestUnreviewedLaneNotGreen(t *testing.T) {
	f := store(t, anchorJSON)
	want(t, green(t, f, Remote{}, "correctness", true), NotGreen, "an unreviewed lane derived green")
	if f.Log() != listArgs {
		t.Fatalf("calls:\n%s\nwant exactly the one list:\n%s", f.Log(), listArgs)
	}
}

// lane-state.test.sh #2: a closed approve-verdict review derives green
func TestClosedApproveDerivesGreen(t *testing.T) {
	f := store(t, anchorJSON, review("closed", "approve", "recorded"))
	want(t, green(t, f, Remote{}, "correctness", true), IsGreen, "closed approve did not derive green")
}

// lane-state.test.sh #3: a superseded approve does not derive green
func TestSupersededApproveNotGreen(t *testing.T) {
	f := store(t, anchorJSON, review("closed", "approve", "superseded"))
	want(t, green(t, f, Remote{}, "correctness", true), NotGreen, "a superseded approve still derived green")
}

// lane-state.test.sh #4: a no-verdict recorded review is not local backing
func TestNoVerdictRecordedNotLocalBacking(t *testing.T) {
	f := store(t, anchorJSON, review("closed", "", "recorded"))
	want(t, green(t, f, Remote{}, "correctness", true), NotGreen, "a no-verdict recorded review derived green from local backing")
}

// lane-state.test.sh #5: a no-verdict superseded review is not local backing
func TestNoVerdictSupersededNotLocalBacking(t *testing.T) {
	f := store(t, anchorJSON, review("closed", "", "superseded"))
	want(t, green(t, f, Remote{}, "correctness", true), NotGreen, "a no-verdict superseded review derived green")
}

// lane-state.test.sh #6: a no-verdict-backed lane greens only via the GitHub-approval fallback
func TestNoVerdictLaneGreensViaGitHubFallback(t *testing.T) {
	f := store(t, anchorJSON, review("closed", "", "recorded"))
	r, a := remote(`[{"state":"APPROVED","id":7}]`)
	want(t, green(t, f, r, "correctness", false), IsGreen, "the GitHub-approval fallback did not green a no-verdict-backed lane")
	if strings.Join(a.asked, " ") != "zook/gc-toolkit#42" {
		t.Fatalf("fallback asked %q, want the origin slug and the anchor's pr_number once", a.asked)
	}
	if !strings.Contains(f.Log(), "bd show tk-anc\n") {
		t.Fatalf("the fallback reads the anchor for its pr_number; calls:\n%s", f.Log())
	}
}

// lane-state.test.sh #7: an approve verdict with no reviewed_oid is not local backing
func TestApproveWithoutReviewedOIDNotLocalBacking(t *testing.T) {
	f := store(t, anchorJSON, noOIDApprove)
	want(t, green(t, f, Remote{}, "correctness", true), NotGreen, "an approve verdict with no reviewed_oid derived green from local backing")
}

const noOIDApprove = `{"id":"rv-1","status":"closed","assignee":"","title":"r","notes":"","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-anc","signoff_verdict":"approve","gc.outcome":"recorded"}}`

// lane-state.test.sh #8: the GitHub-approval fallback greens a lane whose only local row lacks reviewed_oid
func TestFallbackGreensLaneLackingReviewedOID(t *testing.T) {
	f := store(t, anchorJSON, noOIDApprove)
	r, _ := remote(`[{"state":"APPROVED","id":9}]`)
	want(t, green(t, f, r, "correctness", false), IsGreen, "a no-reviewed_oid row blocked the GitHub-approval fallback")
}

// lane-state.test.sh #9: a closed request-changes review is not green
func TestRequestChangesNotGreen(t *testing.T) {
	f := store(t, anchorJSON, review("closed", "request-changes", "recorded"))
	want(t, green(t, f, Remote{}, "correctness", true), NotGreen, "a request-changes verdict derived green")
}

// lane-state.test.sh #10: an in-flight review holds the lane out of green (reviewing)
func TestInFlightReviewHoldsLaneOutOfGreen(t *testing.T) {
	f := store(t, anchorJSON, review("closed", "approve", "recorded"),
		`{"id":"rv-2","status":"in_progress","assignee":"pool/x","title":"re-review","notes":"","metadata":{"task_kind":"review","check_name":"correctness","anchor_bead":"tk-anc"}}`)
	want(t, green(t, f, Remote{}, "correctness", true), NotGreen, "green while a review is in flight")
	// The in-flight check wins before the fallback is even consulted: with the
	// remote allowed and approving, the lane still holds.
	r, a := remote(`[{"state":"APPROVED","id":1}]`)
	want(t, green(t, f, r, "correctness", false), NotGreen, "green while a review is in flight, with the fallback allowed")
	if len(a.asked) != 0 {
		t.Fatalf("an in-flight lane consulted GitHub: %q", a.asked)
	}
}

const absentCheckName = `{"id":"rv-1","status":"closed","assignee":"","title":"r","notes":"","metadata":{"task_kind":"review","anchor_bead":"tk-anc","reviewed_oid":"deadbeef","signoff_verdict":"approve","gc.outcome":"recorded"}}`

// lane-state.test.sh #11: an absent check_name backs the correctness lane
func TestAbsentCheckNameBacksCorrectness(t *testing.T) {
	f := store(t, anchorJSON, absentCheckName)
	want(t, green(t, f, Remote{}, "correctness", true), IsGreen, "absent check_name did not back correctness")
}

// lane-state.test.sh #12: green is per-lane: correctness backing leaves arch not green
func TestGreenIsPerLane(t *testing.T) {
	f := store(t, anchorJSON, absentCheckName)
	want(t, green(t, f, Remote{}, "arch", true), NotGreen, "a correctness backing greened the arch lane")
}

// lane-state.test.sh #13: an APPROVED GitHub review backs the lane (fallback)
func TestApprovedGitHubReviewBacksLane(t *testing.T) {
	f := store(t, anchorJSON)
	r, _ := remote(`[{"state":"APPROVED","id":1}]`)
	want(t, green(t, f, r, "correctness", false), IsGreen, "GitHub approval fallback did not derive green")
}

// lane-state.test.sh #14: --no-remote is fail-closed: no local backing means not green
func TestNoRemoteFailClosed(t *testing.T) {
	f := store(t, anchorJSON)
	r, a := remote(`[{"state":"APPROVED","id":1}]`)
	want(t, green(t, f, r, "correctness", true), NotGreen, "--no-remote still consulted GitHub")
	if len(a.asked) != 0 || strings.Contains(f.Log(), "bd show") {
		t.Fatalf("--no-remote reached the fallback: asked=%q calls:\n%s", a.asked, f.Log())
	}
}

// lane-state.test.sh #15: a GitHub review that is not APPROVED is not green
func TestNonApprovedGitHubReviewNotGreen(t *testing.T) {
	f := store(t, anchorJSON)
	r, _ := remote(`[{"state":"COMMENTED","id":2}]`)
	want(t, green(t, f, r, "correctness", false), NotGreen, "a non-approving GitHub review derived green")
}

// lane-state.test.sh #16: an unreadable store exits 2 (fail-closed, not green)
func TestUnreadableStoreExits2(t *testing.T) {
	f := store(t, anchorJSON)
	f.ListFail = true
	v, err := Green(f, Remote{}, "tk-anc", "correctness", true)
	if v != Unreadable || int(v) != 2 {
		t.Fatalf("verdict %v (rc %d), want Unreadable (rc 2)", v, int(v))
	}
	if err == nil || err.Error() != "could not read review beads on tk-anc" {
		t.Fatalf("error %v, want the script's warning text", err)
	}
	// The same through STUB_LIST_FAIL_ON on a substring unique to this query, the
	// inducement merge.test.sh shares across both of its arms.
	f = store(t, anchorJSON)
	f.ListFailOn = "open,in_progress,blocked,deferred,hooked,pinned,closed"
	if v, _ := Green(f, Remote{}, "tk-anc", "correctness", true); v != Unreadable {
		t.Fatalf("ListFailOn the status list: verdict %v, want Unreadable", v)
	}
}

// --- the fallback chain's failures, untested by the shell suite: each is not green

func TestFallbackMissingPRNumber(t *testing.T) {
	f := store(t, `{"id":"tk-anc","status":"open","metadata":{"merge_result":"pull_request"}}`)
	r, a := remote(`[{"state":"APPROVED","id":1}]`)
	want(t, green(t, f, r, "correctness", false), NotGreen, "an anchor with no pr_number greened via the fallback")
	if len(a.asked) != 0 {
		t.Fatalf("GitHub was asked with no PR to name: %q", a.asked)
	}
	// pr_number false or null is absent too (`// ""`).
	for _, pn := range []string{"false", "null", `""`} {
		f := store(t, `{"id":"tk-anc","status":"open","metadata":{"pr_number":`+pn+`}}`)
		want(t, green(t, f, r, "correctness", false), NotGreen, "pr_number "+pn+" greened via the fallback")
	}
	// A numeric pr_number names the PR as jq's tostring renders it.
	f = store(t, `{"id":"tk-anc","status":"open","metadata":{"pr_number":42}}`)
	want(t, green(t, f, r, "correctness", false), IsGreen, "a numeric pr_number did not reach the fallback")
	if strings.Join(a.asked, " ") != "zook/gc-toolkit#42" {
		t.Fatalf("asked %q, want zook/gc-toolkit#42", a.asked)
	}
}

func TestFallbackAnchorUnreadable(t *testing.T) {
	f := store(t, anchorJSON)
	f.ShowFail = true
	r, a := remote(`[{"state":"APPROVED","id":1}]`)
	want(t, green(t, f, r, "correctness", false), NotGreen, "an unreadable anchor greened via the fallback")
	if len(a.asked) != 0 {
		t.Fatalf("GitHub was asked with no PR to name: %q", a.asked)
	}
}

func TestFallbackOriginUnavailable(t *testing.T) {
	f := store(t, anchorJSON)
	r := Remote{Origin: fakeOrigin{}, Approver: fakeApprover{approved: true, ok: true}}
	want(t, green(t, f, r, "correctness", false), NotGreen, "a non-GitHub origin greened via the fallback")
	r = Remote{Origin: FixedSlug(""), Approver: fakeApprover{approved: true, ok: true}}
	want(t, green(t, f, r, "correctness", false), NotGreen, "an empty slug greened via the fallback")
}

func TestFallbackApproverUnavailable(t *testing.T) {
	f := store(t, anchorJSON)
	r := Remote{Origin: FixedSlug("zook/gc-toolkit"), Approver: fakeApprover{approved: true, ok: false}}
	want(t, green(t, f, r, "correctness", false), NotGreen, "an approver that could not answer (no gh, gh failed) greened the lane")
}

func TestFallbackApproverNotApproved(t *testing.T) {
	f := store(t, anchorJSON)
	r := Remote{Origin: FixedSlug("zook/gc-toolkit"), Approver: fakeApprover{approved: false, ok: true}}
	want(t, green(t, f, r, "correctness", false), NotGreen, "a PR with no APPROVED review greened the lane")
}

func TestFallbackZeroRemote(t *testing.T) {
	// The zero Remote has no seams: the fallback is unavailable, not green.
	f := store(t, anchorJSON)
	want(t, green(t, f, Remote{}, "correctness", false), NotGreen, "a zero Remote greened the lane")
	want(t, green(t, f, Remote{Origin: FixedSlug("zook/gc-toolkit")}, "correctness", false), NotGreen, "a Remote with no Approver greened the lane")
}

// --- the paginated stream, as jq -s '[ .[][]? ... ]' read it

func TestApprovedInStream(t *testing.T) {
	cases := []struct {
		name         string
		body         string
		approved, ok bool
	}{
		{"one approved page", `[{"state":"APPROVED","id":1}]`, true, true},
		{"commented only", `[{"state":"COMMENTED","id":2}]`, false, true},
		{"empty page", `[]`, false, true},
		{"two pages, approval on the second", "[{\"state\":\"COMMENTED\"}]\n[{\"state\":\"CHANGES_REQUESTED\"},{\"state\":\"APPROVED\"}]", true, true},
		{"a non-array page is skipped", `{"message":"Not Found"} [{"state":"APPROVED"}]`, true, true},
		{"only non-array pages", `{"message":"Not Found"} null 7`, false, true},
		{"a truncated stream is unreadable", `[{"state":"APPROVED"}] [{"state":"COMM`, false, false},
		{"a truncated stream is unreadable, approval or not", `[{"state":"COMMENTED"},{"sta`, false, false},
		{"garbage is unreadable", `not json`, false, false},
		{"a scalar element cannot be indexed", `["APPROVED"]`, false, false},
		{"a null element is skipped", `[null,{"state":"APPROVED"}]`, true, true},
		{"state must be exactly APPROVED", `[{"state":"approved"},{"state":"APPROVED "}]`, false, true},
		{"state null or false is absent", `[{"state":null},{"state":false}]`, false, true},
		{"C0 bytes are scrubbed before the decode", "[{\"state\":\"APP\x01ROVED\"}]\n[{\"state\":\"APPR\tOVED\"}]", true, true},
		{"whitespace only is an empty history", "  \n", false, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			approved, ok := ApprovedInStream([]byte(c.body))
			if approved != c.approved || ok != c.ok {
				t.Fatalf("ApprovedInStream(%q) = (%v, %v), want (%v, %v)", c.body, approved, ok, c.approved, c.ok)
			}
		})
	}
}

// --- OriginSlug: the three URL forms and every rejection

func TestOriginSlug(t *testing.T) {
	cases := []struct {
		url  string
		slug string
		ok   bool
	}{
		{"git@github.com:zook/gc-toolkit", "zook/gc-toolkit", true},
		{"https://github.com/zook/gc-toolkit", "zook/gc-toolkit", true},
		{"ssh://git@github.com/zook/gc-toolkit", "zook/gc-toolkit", true},
		{"git@github.com:zook/gc-toolkit.git", "zook/gc-toolkit", true},
		{"https://github.com/zook/gc-toolkit.git", "zook/gc-toolkit", true},
		{"https://github.com/zook/gc-toolkit/", "zook/gc-toolkit", true},
		{"https://github.com/zook/gc-toolkit.git/", "zook/gc-toolkit.git", true},
		{"https://github.com/zook/gc-toolkit///", "zook/gc-toolkit", true},
		// .git is stripped once, and before the slashes: a trailing slash shields it,
		// as it did under the script's sed chain.
		{"https://github.com/zook/gc-toolkit.git.git", "zook/gc-toolkit.git", true},
		// rejections
		{"", "", false},
		{"https://gitlab.com/zook/gc-toolkit", "", false},
		{"git@gitlab.com:zook/gc-toolkit", "", false},
		{"http://github.com/zook/gc-toolkit", "", false},
		{"https://github.com/zook/gc-toolkit/extra", "", false},
		{"https://github.com//zook", "", false},
		{"https://github.com/zook", "", false},
		{"https://github.com/", "", false},
		{"git@github.com:", "", false},
		{"git@github.com:/zook/gc-toolkit", "", false},
		{"ssh://git@github.com/zook", "", false},
	}
	for _, c := range cases {
		slug, ok := OriginSlug(c.url)
		if slug != c.slug || ok != c.ok {
			t.Errorf("OriginSlug(%q) = (%q, %v), want (%q, %v)", c.url, slug, ok, c.slug, c.ok)
		}
	}
}

func TestFixedSlug(t *testing.T) {
	if s, ok := FixedSlug("a/b").Slug(); s != "a/b" || !ok {
		t.Fatalf("FixedSlug(a/b).Slug() = (%q, %v)", s, ok)
	}
	if _, ok := FixedSlug("").Slug(); ok {
		t.Fatal("an empty FixedSlug is a slug")
	}
}

func TestVerdictExitCodes(t *testing.T) {
	if IsGreen != 0 || NotGreen != 1 || Unreadable != 2 {
		t.Fatalf("verdicts %d %d %d are not the script's exit codes 0 1 2", IsGreen, NotGreen, Unreadable)
	}
}
