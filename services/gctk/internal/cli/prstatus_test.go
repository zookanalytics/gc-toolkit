package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/prstatus/fixture"
)

// storeDerive runs `gctk pr status <anchor>` with extra over store, the rows
// the store stub serves (storeStub, bead_test.go), and returns what it printed,
// its exit, and each `gc` call it made, in order.
func storeDerive(t *testing.T, store, anchor string, extra ...string) (string, int, []string) {
	t.Helper()
	bin := t.TempDir()
	calls := filepath.Join(t.TempDir(), "calls")
	for name, body := range map[string]string{
		"gc-store": storeStub,
		"gc":       "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$STUB_CALLS\"\nexec \"$(dirname \"$0\")/gc-store\" \"$@\"\n",
	} {
		if err := os.WriteFile(filepath.Join(bin, name), []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_STORE", store)
	t.Setenv("STUB_CALLS", calls)
	var out, errbuf bytes.Buffer
	code := Run(append([]string{"pr", "status", anchor}, extra...), "", &out, &errbuf)
	raw, _ := os.ReadFile(calls)
	return out.String(), code, strings.Split(strings.TrimSpace(string(raw)), "\n")
}

// The status prints alone, and a read that does not answer derives nothing, so
// a caller leaves the labels as they are rather than flip them on a guess: an
// anchor the store does not hold, edges that do not decode, on the anchor or on
// a bead the walk reaches, and a store that does not answer.
func TestPRStatusDerive(t *testing.T) {
	const anchor = `{"id":"tk-a","status":"open","metadata":{}}`
	const gated = `{"id":"tk-a","status":"open","metadata":{},"dependencies":[{"id":"tk-g","dependency_type":"blocks"}]}`
	for _, tc := range []struct {
		name, store, want string
		code              int
	}{
		{"a rework in the in-flight set => working",
			`[` + anchor + `,{"id":"tk-k","status":"in_progress","metadata":{"task_kind":"rework","anchor_bead":"tk-a"}}]`, "working\n", 0},
		{"an operator freeze => needs-attention", `[{"id":"tk-a","status":"open","metadata":{"merge_hold":true}}]`, "needs-attention\n", 0},
		{"nothing outstanding => needs-review", `[` + anchor + `]`, "needs-review\n", 0},
		{"an in-progress human gate on the anchor => needs-attention",
			`[` + gated + `,{"id":"tk-g","status":"in_progress","issue_type":"gate","await_type":"human"}]`, "needs-attention\n", 0},
		{"an anchor the store does not hold => exit 2", `[]`, "", 2},
		{"edges on the anchor that do not decode => exit 2",
			`[{"id":"tk-a","status":"open","metadata":{},"dependencies":[{"dependency_type":"blocks"}]}]`, "", 2},
		{"edges on a bead the walk reaches that do not decode => exit 2",
			`[` + gated + `,{"id":"tk-g","status":"open","dependencies":[{"dependency_type":"blocks"}]}]`, "", 2},
		{"a store that does not answer => exit 2", `not json`, "", 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if out, code, _ := storeDerive(t, tc.store, "tk-a"); code != tc.code || out != tc.want {
				t.Fatalf("derive = (%q, %d), want (%q, %d)", out, code, tc.want, tc.code)
			}
		})
	}
}

// The command reads the store gc routes the anchor to through the ledger's
// listing, each bead once: the anchor's row, the beads that name it as their
// anchor, then one read per level of the beads its `blocks` edges reach, the
// level's own rows already read. Nothing behind a closed blocker is read, and
// nothing reads a visit or shows a bead.
func TestPRStatusReadsEachBeadOnce(t *testing.T) {
	store := `[
 {"id":"tk-a","status":"open","metadata":{},"dependencies":[{"id":"tk-x","dependency_type":"blocks"},{"id":"tk-y","dependency_type":"blocks"},{"id":"tk-z","dependency_type":"blocks"}]},
 {"id":"tk-x","status":"open","dependencies":[{"id":"tk-g","dependency_type":"blocks"}]},
 {"id":"tk-y","status":"open"},
 {"id":"tk-z","status":"closed","dependencies":[{"id":"tk-w","dependency_type":"blocks"}]},
 {"id":"tk-g","status":"open","issue_type":"gate","await_type":"human"},
 {"id":"tk-w","status":"open"},
 {"id":"tk-k","status":"open","metadata":{"anchor_bead":"tk-a"}}]`
	out, code, calls := storeDerive(t, store, "tk-a")
	if code != 0 || out != "needs-attention\n" {
		t.Fatalf("derive = (%q, %d), want the gate two beads away", out, code)
	}
	var reads []string
	named, anchored := map[string]int{}, 0
	for _, c := range calls {
		args := strings.Fields(c)
		if !slices.Contains(args, "list") {
			continue
		}
		if i := slices.Index(args, "--id"); i >= 0 && i+1 < len(args) {
			reads = append(reads, args[i+1])
			for _, id := range strings.Split(args[i+1], ",") {
				named[id]++
			}
		}
		if slices.Contains(args, "anchor_bead=tk-a") {
			anchored++
		}
	}
	if want := []string{"tk-a", "tk-x,tk-y,tk-z", "tk-g"}; !slices.Equal(reads, want) || anchored != 1 {
		t.Errorf("the reads named %v and the anchored beads %d times, want %v and once; calls:\n%s", reads, anchored, want, strings.Join(calls, "\n"))
	}
	for id, n := range named {
		if n > 1 {
			t.Errorf("%s was read %d times", id, n)
		}
	}
	for _, c := range calls {
		for _, stray := range []string{"bd show", "task_kind=visit", "gc.continuation_group", "bd dep list"} {
			if strings.Contains(c, stray) {
				t.Errorf("the derive made the read %q", c)
			}
		}
	}
}

// The anchor's row is the store's, whether or not the supervisor answers: a
// copy that still carries a merge_hold the bead no longer does changes
// nothing. The fake supervisor serves the anchor at the city's bead path.
func TestPRStatusReadsTheStoreNotTheSupervisorsCopy(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v0/city/testcity/bead/tk-a" {
			http.NotFound(w, r)
			return
		}
		fmt.Fprint(w, `{"id":"tk-a","status":"open","metadata":{"merge_hold":true}}`)
	}))
	t.Cleanup(srv.Close)
	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	if err := os.WriteFile(filepath.Join(home, "supervisor.toml"), []byte("[supervisor]\nport = "+u.Port()+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GC_HOME", home)
	t.Setenv("GC_CITY_PATH", filepath.Join(t.TempDir(), "testcity"))
	t.Setenv("GC_NO_API", "")
	if out, code, _ := storeDerive(t, `[{"id":"tk-a","status":"open","metadata":{}}]`, "tk-a"); code != 0 || out != "needs-review\n" {
		t.Fatalf("derive = (%q, %d), want (%q, 0), the store's row with no hold", out, code, "needs-review\n")
	}
}

// --json prints the status beside what holds the PR, the values the held:
// labels carry, in their order, each reason naming its bead: an empty array of
// each when nothing holds it, a gate and a decision on the anchor together, a
// decision with no status as an open one, and the merge freeze, which holds no
// held: value of its own.
func TestPRStatusDeriveHeld(t *testing.T) {
	const anchor = `{"id":"tk-a","status":"open","metadata":{},"dependencies":[{"id":"tk-g","dependency_type":"blocks"},{"id":"tk-d","dependency_type":"blocks"}]}`
	const gate = `{"id":"tk-g","title":"answer the review","status":"open","issue_type":"gate","await_type":"human"}`
	for _, tc := range []struct{ name, store, want string }{
		{"nothing holds the PR", `[{"id":"tk-a","status":"open","metadata":{}}]`,
			`{"status":"needs-review","held":[],"reasons":[]}`},
		{"a human gate and a decision on the anchor", `[` + anchor + `,` + gate + `,{"id":"tk-d","title":"pick one","status":"open","issue_type":"decision"}]`,
			`{"status":"needs-attention","held":["gate","blocked"],"reasons":[{"held":"gate","id":"tk-g","title":"answer the review"},{"held":"blocked","id":"tk-d","title":"pick one"}]}`},
		{"a decision with no status reads open", `[` + anchor + `,{"id":"tk-d","title":"pick one","issue_type":"decision"}]`,
			`{"status":"needs-attention","held":["blocked"],"reasons":[{"held":"blocked","id":"tk-d","title":"pick one"}]}`},
		{"the merge freeze reads needs-attention and holds nothing", `[{"id":"tk-a","status":"open","metadata":{"merge_hold":"true"}}]`,
			`{"status":"needs-attention","held":[],"reasons":[]}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if out, code, _ := storeDerive(t, tc.store, "tk-a", "--json"); code != 0 || out != tc.want+"\n" {
				t.Fatalf("derive --json = (%q, %d), want (%q, 0)", out, code, tc.want+"\n")
			}
		})
	}
}

// Every scenario the readers are tested against reaches the derive as the
// store's rows, and the derive answers what prstatus.Read gathers from the same
// beads through the fixture's store: the status, the held values and the
// reasons. The answer is the definition's own, so a change to it reaches this
// reader with no edit here, and a rule kept in this command would part from it.
func TestPRStatusDeriveReadsTheDefinition(t *testing.T) {
	scenarios, err := fixture.Scenarios()
	if err != nil {
		t.Fatal(err)
	}
	for _, sc := range scenarios {
		t.Run(sc.Name, func(t *testing.T) {
			want, err := sc.Answer()
			if err != nil {
				t.Fatal(err)
			}
			rows := []any{}
			for _, b := range sc.Beads {
				rows = append(rows, storeRow(b))
			}
			store, err := json.Marshal(rows)
			if err != nil {
				t.Fatal(err)
			}
			out, code, _ := storeDerive(t, string(store), sc.Anchor, "--json")
			var got struct {
				Status  prstatus.State    `json:"status"`
				Held    []prstatus.Hold   `json:"held"`
				Reasons []prstatus.Reason `json:"reasons"`
			}
			if code != 0 || json.Unmarshal([]byte(out), &got) != nil {
				t.Fatalf("derive --json = (%q, %d)", out, code)
			}
			if got.Status != want.Status || !slices.Equal(got.Held, want.Held) || !slices.Equal(got.Reasons, want.Reasons) {
				t.Errorf("derive --json = %+v\nthe definition gives status=%q held=%v reasons=%+v", got, want.Status, want.Held, want.Reasons)
			}
		})
	}
}

// storeRow is a scenario bead as the store stub holds it: its fields, and each
// edge of its own by the far bead and the edge's type.
func storeRow(b fixture.Bead) map[string]any {
	row := map[string]any{"id": b.ID, "title": b.Title, "status": b.Status, "metadata": b.Metadata}
	for k, v := range map[string]string{"issue_type": b.IssueType, "await_type": b.AwaitType, "assignee": b.Assignee} {
		if v != "" {
			row[k] = v
		}
	}
	deps := []any{}
	for _, edge := range []struct {
		kind string
		ids  []string
	}{{"blocks", b.WaitsOn}, {"tracks", b.Tracks}} {
		for _, id := range edge.ids {
			deps = append(deps, map[string]any{"id": id, "dependency_type": edge.kind})
		}
	}
	row["dependencies"] = deps
	return row
}

func TestPRStatusUsageErrors(t *testing.T) {
	for _, args := range [][]string{
		{"pr", "status"},
		{"pr", "status", ""},
		{"pr", "status", "tk-a", "tk-b"},
		{"pr", "status", "tk-a", "--all"},
	} {
		var out, errbuf bytes.Buffer
		if code := Run(args, "", &out, &errbuf); code != 1 {
			t.Errorf("gctk %q = %d, want 1", args, code)
		}
	}
	var out, errbuf bytes.Buffer
	if code := Run([]string{"pr", "bogus"}, "", &out, &errbuf); code != 2 {
		t.Errorf("a verb pr does not have = %d, want 2", code)
	}
}

// stPR is the PR st-1 owns on Gas Town's pending record.
const stPR = "https://github.com/acme/widgets/pull/7"

// savedRead is the read the one-PR update saves of st-1's PR at the head the
// refinery validated: open, approved, CLEAN, its required check passed and
// nothing waiting on the city. edit changes it before it is saved in parts.
func savedRead(t *testing.T, edit func(*pr.GitHubRead)) string {
	t.Helper()
	r := &pr.GitHubRead{ReadAt: "2026-11-15T09:00:00Z", URL: stPR, Number: 7, Repository: "acme/widgets",
		HeadBranch: "polecat/st-1", Base: "main", Head: validated, State: "OPEN", MergeState: "CLEAN",
		Checks:    []pr.RequiredRun{{Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS"}},
		Approvers: []string{"operator"}, Requesters: []string{}, Awaiting: []string{}}
	if edit != nil {
		edit(r)
	}
	raw, err := json.Marshal(inParts(r))
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// inParts is r, GitHub's side of a PR at one head, in the four parts the one-PR
// update saves it in, each read at r's instant.
func inParts(r *pr.GitHubRead) *pr.SavedRead {
	return &pr.SavedRead{
		PR: &pr.SavedPR{ReadAt: r.ReadAt, URL: r.URL, Number: r.Number, Repository: r.Repository,
			HeadBranch: r.HeadBranch, Base: r.Base, Head: r.Head, State: r.State, Draft: r.Draft, MergeState: r.MergeState},
		Checks: &pr.SavedChecks{ReadAt: r.ReadAt, Head: r.Head, Runs: r.Checks},
		Conversation: &pr.SavedConversation{ReadAt: r.ReadAt, Since: r.Since, Approvers: r.Approvers,
			Requesters: r.Requesters, Untaken: r.Untaken, Awaiting: r.Awaiting, Unresolved: []string{}},
		Labels: &pr.SavedLabels{ReadAt: r.ReadAt, Names: []string{}},
	}
}

// pendingStore is a store whose st-1 owns PR 7 on Gas Town's pending record, at
// the blocked status the record writes, with its record whole, a review result
// passed at the validated head and the read savedRead saves. md changes its
// metadata, where a nil value leaves the key off, deps are its own edges in a
// show's shape, and others are the store's other rows.
func pendingStore(t *testing.T, md map[string]any, deps []map[string]any, others ...map[string]any) string {
	t.Helper()
	rec := map[string]any{
		"merge_result": "pull_request_pending", "pr_url": stPR, "pr_number": "7", "pr_repo": "acme/widgets",
		"pr_head_sha": validated, "merged_target": "main", "branch": "polecat/st-1",
		"review_results": `[{"head":"` + validated + `","target":"main","passed":true}]`,
		"pr_github_read": savedRead(t, nil),
	}
	for k, v := range md {
		if v == nil {
			delete(rec, k)
			continue
		}
		rec[k] = v
	}
	row := map[string]any{"id": "st-1", "title": "the work", "status": "blocked", "metadata": rec}
	if deps != nil {
		row["dependencies"] = deps
	}
	raw, err := json.Marshal(append([]map[string]any{row}, others...))
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// pendingDerive runs `gctk pr status st-1` with extra over store, through the
// store stub, with a gh on PATH and a pr-post.sh in the scripts directory that
// each record their call. A PR on the pending record is derived from the store
// alone, so the test fails if either is called.
func pendingDerive(t *testing.T, store string, extra ...string) (string, int) {
	t.Helper()
	bin, scripts := t.TempDir(), t.TempDir()
	calls := filepath.Join(t.TempDir(), "calls")
	record := func(name string) string {
		return "#!/bin/sh\nprintf '" + name + " %s\\n' \"$*\" >> \"$OUTSIDE_CALLS\"\nexit 1\n"
	}
	for path, body := range map[string]string{
		filepath.Join(bin, "gc"):             storeStub,
		filepath.Join(bin, "gh"):             record("gh"),
		filepath.Join(scripts, "pr-post.sh"): record("pr-post.sh"),
	} {
		if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GCTK_SCRIPTS_DIR", scripts)
	t.Setenv("OUTSIDE_CALLS", calls)
	t.Setenv("STUB_STORE", store)
	var out, errbuf bytes.Buffer
	code := Run(append([]string{"pr", "status", "st-1"}, extra...), "", &out, &errbuf)
	if raw, err := os.ReadFile(calls); err == nil {
		t.Fatalf("gctk pr status called outside the store:\n%s", raw)
	}
	return out.String(), code
}

// An anchor on Gas Town's pending record reads the evaluator's answer over the
// read the one-PR update saved on it, which prstatus renders, and the
// command prints each condition not met, once for each status. It reads
// neither GitHub nor the definition of feedback.
func TestPRStatusOnThePendingRecord(t *testing.T) {
	const other = "2222222222222222222222222222222222222222"
	noApproval := "approval: no approval stands from an account that can push to the repository\n"
	unread := func(head string) string {
		return "github-unread: GitHub's side of the PR is not read at the head the store holds, " + head + ": "
	}
	unapproved := func(r *pr.GitHubRead) { r.Approvers = []string{} }
	type derived struct {
		Status     string            `json:"status"`
		Held       []string          `json:"held"`
		Reasons    []prstatus.Reason `json:"reasons"`
		Ready      *bool             `json:"ready"`
		Head       *string           `json:"head"`
		Target     *string           `json:"target"`
		Conditions []pr.Condition    `json:"conditions"`
	}
	decode := func(t *testing.T, store string) derived {
		t.Helper()
		out, code := pendingDerive(t, store, "--json")
		var got derived
		if code != 0 || json.Unmarshal([]byte(out), &got) != nil {
			t.Fatalf("derive --json = (%q, %d)", out, code)
		}
		return got
	}
	plain := func(t *testing.T, store, want string) {
		t.Helper()
		if out, code := pendingDerive(t, store); code != 0 || out != want {
			t.Fatalf("derive = (%q, %d), want (%q, 0)", out, code, want)
		}
	}

	t.Run("a ready PR reads merging, with no condition, judged at the saved read's head", func(t *testing.T) {
		store := pendingStore(t, nil, nil)
		plain(t, store, "merging\n")
		got := decode(t, store)
		if got.Status != "merging" || got.Ready == nil || !*got.Ready || got.Head == nil || *got.Head != validated ||
			got.Target == nil || *got.Target != "main" || got.Conditions == nil || len(got.Conditions) != 0 {
			t.Fatalf("derive --json = %+v, want ready at %s into main with an empty conditions array", got, validated)
		}
	})

	t.Run("an unapproved PR the review loop has yet to pass reads working, then each condition not met", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"review_results": nil, "pr_github_read": savedRead(t, unapproved)}, nil)
		plain(t, store, "working\n"+noApproval+"review: no review result passed at head "+validated+" into main\n")
	})

	t.Run("a PR waiting on an approval alone reads needs-review", func(t *testing.T) {
		plain(t, pendingStore(t, map[string]any{"pr_github_read": savedRead(t, unapproved)}, nil), "needs-review\n"+noApproval)
	})

	t.Run("a review thread waiting on the city's answer reads needs-attention, held: review", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"pr_github_read": savedRead(t, func(r *pr.GitHubRead) {
			r.Awaiting = []string{"T1"}
		})}, nil)
		plain(t, store, "needs-attention\nthread: review thread T1 waits on the city's answer\n")
		got := decode(t, store)
		if !slices.Equal(got.Held, []string{"review"}) || !reflect.DeepEqual(got.Reasons,
			[]prstatus.Reason{{Held: prstatus.HeldReview, Title: "1 review thread waits on the city's answer"}}) {
			t.Fatalf("derive --json = %+v, want held: review with the thread's reason", got)
		}
	})

	t.Run("a failed required check reads needs-attention", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"pr_github_read": savedRead(t, func(r *pr.GitHubRead) {
			r.Checks = []pr.RequiredRun{{Name: "test", Status: "COMPLETED", Conclusion: "FAILURE"}}
		})}, nil)
		plain(t, store, "needs-attention\ncheck-failed: required check test has a result at the head that did not pass (FAILURE)\n")
	})

	t.Run("a PR with no read saved reads working, GitHub's side unread and no head judged", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"pr_github_read": nil}, nil)
		plain(t, store, "working\n"+unread(validated)+"no read of GitHub is saved on the bead\n")
		got := decode(t, store)
		if got.Status != "working" || got.Ready == nil || *got.Ready || got.Head != nil || got.Target != nil ||
			len(got.Conditions) != 1 || got.Conditions[0].Kind != pr.KindGitHubUnread {
			t.Fatalf("derive --json = %+v, want working on github-unread alone, with no head or target", got)
		}
	})

	t.Run("a head the refinery published after the read reads working until the PR watch reads it", func(t *testing.T) {
		plain(t, pendingStore(t, map[string]any{"pr_head_sha": other}, nil),
			"working\n"+unread(other)+"the read is at head "+validated+"\n")
	})

	t.Run("an unread side beside a human gate reads needs-attention, held: gate", func(t *testing.T) {
		t.Setenv("STUB_BLOCKED", `[{"id":"st-1","blocked_by":["st-g"]}]`)
		t.Setenv("STUB_MARKS", `[{"id":"st-1"}]`)
		store := pendingStore(t, map[string]any{"pr_github_read": nil},
			[]map[string]any{{"id": "st-g", "dependency_type": "blocks", "title": "which way?", "status": "open",
				"issue_type": "gate", "await_type": "human"}},
			map[string]any{"id": "st-g", "title": "which way?", "status": "open", "issue_type": "gate",
				"await_type": "human", "assignee": "human"})
		out, code := pendingDerive(t, store)
		if code != 0 || !strings.HasPrefix(out, "needs-attention\n"+unread(validated)) ||
			!strings.Contains(out, "\nwait: the bead waits on st-g") {
			t.Fatalf("derive = (%q, %d), want needs-attention on github-unread and the wait on st-g", out, code)
		}
		got := decode(t, store)
		if !slices.Equal(got.Held, []string{"gate"}) ||
			!reflect.DeepEqual(got.Reasons, []prstatus.Reason{{Held: prstatus.HeldGate, ID: "st-g", Title: "which way?"}}) {
			t.Fatalf("derive --json = %+v, want held: gate naming st-g", got)
		}
	})

	t.Run("a saved read that does not decode derives nothing", func(t *testing.T) {
		store := pendingStore(t, map[string]any{"pr_github_read": "{not json"}, nil)
		if out, code := pendingDerive(t, store); code != 2 || out != "" {
			t.Fatalf("derive = (%q, %d), want (\"\", 2)", out, code)
		}
	})

	t.Run("an anchor off the record reads its recorded facts, and its --json carries no answer", func(t *testing.T) {
		out, code := pendingDerive(t, `[{"id":"st-1","status":"open","metadata":{"merge_result":"pull_request_closed_unmerged"}}]`, "--json")
		if code != 0 || strings.Contains(out, `"ready"`) || strings.Contains(out, `"conditions"`) {
			t.Fatalf("derive --json = (%q, %d), want the derivation alone", out, code)
		}
	})
}

// declared is the prefix a test rig's default branch declares as a
// third-party marker of posts that are not for review, one no real repository
// declares.
const declared = "[gctk-declared]:"

// declaringRig is a rig's checkout whose default branch declares prefix in its
// not-for-review.toml, or declares nothing when prefix is empty.
func declaringRig(t *testing.T, prefix string) string {
	t.Helper()
	dir := t.TempDir()
	git := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	git("init", "-q")
	if prefix != "" {
		if err := os.WriteFile(filepath.Join(dir, "not-for-review.toml"), []byte("[[marker]]\nprefix = \""+prefix+"\"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		git("add", "not-for-review.toml")
	}
	git("commit", "-q", "--allow-empty", "-m", "base")
	git("update-ref", "refs/remotes/origin/main", "HEAD")
	return dir
}

// packScripts has feedback.ScriptsDir name this checkout's scripts, whose
// pr-post.sh holds the one definition of feedback, and leaves GC_RIG_ROOT
// unset, which that definition reads only outside a repository.
func packScripts(t *testing.T) {
	t.Helper()
	dir, err := filepath.Abs("../../../../assets/scripts")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "pr-post.sh")); err != nil {
		t.Fatalf("pr-post.sh is not in %s: %v", dir, err)
	}
	t.Setenv("GCTK_SCRIPTS_DIR", dir)
	t.Setenv("GC_RIG_ROOT", "")
}

// readsDeclared reports whether a loaded definition reads the declaration of
// a rig that declares declared: a post that opens with it is no feedback
// there, and feedback where nothing declares it.
func readsDeclared(t *testing.T, f pr.Feedback) bool {
	t.Helper()
	got, err := f.Untaken("zook-bot", "2026-10-01T00:00:00Z", nil, nil, []feedback.Comment{
		{ID: 1, Author: "integration", Body: declared + " a status the integration posts", CreatedAt: "2026-11-12T01:00:00Z"},
		{ID: 2, Author: "operator", Body: "one more thing", CreatedAt: "2026-11-12T01:00:00Z"},
	})
	if err != nil {
		t.Fatal(err)
	}
	ids := got.Conversation
	switch {
	case slices.Equal(ids, []int64{2}):
		return true
	case slices.Equal(ids, []int64{1, 2}):
		return false
	}
	t.Fatalf("feedback %v, want [2] where the prefix is declared or [1 2] where it is not", ids)
	return false
}
