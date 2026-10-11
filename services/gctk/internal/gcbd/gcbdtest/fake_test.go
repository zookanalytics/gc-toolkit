package gcbdtest

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

func str(s string) *string { return &s }

func bead(id string, status *string, meta map[string]any) gcbd.Bead {
	return gcbd.Bead{ID: id, Status: status, Metadata: meta}
}

func ids(rows []gcbd.Bead) string {
	out := make([]string, len(rows))
	for i, r := range rows {
		out[i] = r.ID
	}
	return strings.Join(out, ",")
}

// Show hands out the matching row, nil for an unknown id (the stub's `[]`), nil
// under STUB_SHOW_FAIL, and runs the hook first — so a hook that writes the
// store is seen by the read it precedes.
func TestShow(t *testing.T) {
	f := New(bead("a", str("open"), map[string]any{"k": "v"}), bead("b", nil, nil))
	if b := f.Show("a"); b == nil || b.Meta("k") != "v" || b.StatusLower() != "open" {
		t.Fatalf("Show(a) = %+v, want the stored row", b)
	}
	if b := f.ShowDirect("b"); b == nil || b.StatusLowerOr("open") != "open" {
		t.Fatalf("ShowDirect(b) = %+v, want the row with a nil status", b)
	}
	if f.Show("zz") != nil {
		t.Error("Show(unknown) != nil; the stub prints [] and the Client reads nil")
	}

	t.Run("the copy is not the store", func(t *testing.T) {
		b := f.Show("a")
		b.Metadata["k"] = "mutated"
		*b.Status = "closed"
		if got := f.Get("a"); got.Meta("k") != "v" || *got.Status != "open" {
			t.Errorf("mutating Show's row wrote the store: %+v", got)
		}
	})

	t.Run("ShowFail", func(t *testing.T) {
		f := New(bead("a", nil, nil))
		f.ShowFail = true
		if f.Show("a") != nil || f.ShowDirect("a") != nil {
			t.Error("Show under ShowFail != nil")
		}
	})

	t.Run("ShowHook runs before the read", func(t *testing.T) {
		f := New(bead("a", str("open"), nil))
		var seen []string
		f.ShowHook = func(id string) {
			seen = append(seen, id)
			f.Get("a").Status = str("closed")
		}
		if b := f.Show("a"); b == nil || b.StatusLower() != "closed" {
			t.Errorf("Show after the hook = %+v, want the hook's write (closed)", b)
		}
		if !reflect.DeepEqual(seen, []string{"a"}) {
			t.Errorf("hook saw %q, want [a]", seen)
		}
	})
}

// List is the stub's jq: status on `(.status // "open")`, exact against the
// set; fields split at the first `=` and compared through Meta's tostring; the
// key test is map presence; rows in store order.
func TestListFilters(t *testing.T) {
	f := New(
		bead("s-open", str("open"), map[string]any{"merge_result": "pull_request", "pr_number": 1, "flag": false}),
		bead("s-nil", nil, map[string]any{"merge_result": "pull_request", "eq": "a=b", "null": nil}),
		bead("s-empty", str(""), map[string]any{"merge_result": "pull_request"}),
		bead("s-closed", str("closed"), map[string]any{"merge_result": "pull_request", "pr_number": "1"}),
		bead("s-upper", str("OPEN"), nil),
		bead("s-num", str("in_progress"), map[string]any{"pr_number": 1.5, "n": 12}),
	)
	for _, tc := range []struct {
		name string
		q    gcbd.ListQuery
		want string
	}{
		{"no filter is every row", gcbd.ListQuery{}, "s-open,s-nil,s-empty,s-closed,s-upper,s-num"},
		{"status set, nil status reads open", gcbd.ListQuery{Status: []string{"open"}}, "s-open,s-nil"},
		{"empty-string status is its own status, and case is exact", gcbd.ListQuery{Status: []string{"open", "closed"}}, "s-open,s-nil,s-closed"},
		{"one comma element is the same set", gcbd.ListQuery{Status: []string{"open,in_progress"}}, "s-open,s-nil,s-num"},
		{"a lone empty status is no filter", gcbd.ListQuery{Status: []string{""}}, "s-open,s-nil,s-empty,s-closed,s-upper,s-num"},
		{"field match", gcbd.ListQuery{MetadataField: []string{"merge_result=pull_request"}}, "s-open,s-nil,s-empty,s-closed"},
		{"number 1 matches \"1\" and so does the string", gcbd.ListQuery{MetadataField: []string{"pr_number=1"}}, "s-open,s-closed"},
		{"float renders as jq tostring", gcbd.ListQuery{MetadataField: []string{"pr_number=1.5"}}, "s-num"},
		{"k= matches an absent key, a null and a false", gcbd.ListQuery{MetadataField: []string{"flag="}}, "s-open,s-nil,s-empty,s-closed,s-upper,s-num"},
		{"split at the first = only", gcbd.ListQuery{MetadataField: []string{"eq=a=b"}}, "s-nil"},
		{"no = makes the word both key and value", gcbd.ListQuery{MetadataField: []string{"n"}}, ""},
		{"every field must match", gcbd.ListQuery{MetadataField: []string{"merge_result=pull_request", "pr_number=1"}}, "s-open,s-closed"},
		{"field and status together", gcbd.ListQuery{MetadataField: []string{"merge_result=pull_request"}, Status: []string{"open"}}, "s-open,s-nil"},
		{"has key is presence, a null value counts", gcbd.ListQuery{HasMetadataKey: "null"}, "s-nil"},
		{"has key on a nil metadata map", gcbd.ListQuery{HasMetadataKey: "merge_result"}, "s-open,s-nil,s-empty,s-closed"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rows, ok := f.List(tc.q)
			if !ok {
				t.Fatal("ok=false with no fail knob set")
			}
			if got := ids(rows); got != tc.want {
				t.Errorf("List(%+v) = [%s], want [%s]", tc.q, got, tc.want)
			}
		})
	}
	// `n` with no `=`: the key n must equal the string "n"; make the control
	// positive so the branch is proven, not just empty.
	f.Beads = append(f.Beads, bead("s-word", nil, map[string]any{"n": "n"}))
	if rows, _ := f.List(gcbd.ListQuery{MetadataField: []string{"n"}}); ids(rows) != "s-word" {
		t.Errorf("List(n) = [%s], want [s-word]", ids(rows))
	}
}

func TestListFailKnobs(t *testing.T) {
	f := New(bead("a", nil, map[string]any{"pr_number": 7}))
	f.ListFail = true
	if _, ok := f.List(gcbd.ListQuery{}); ok {
		t.Error("ListFail: ok=true")
	}
	f.ListFail = false
	f.ListFailOn = "pr_number="
	if _, ok := f.List(gcbd.ListQuery{MetadataField: []string{"pr_number=7"}}); ok {
		t.Error("ListFailOn matched the argv but ok=true")
	}
	if rows, ok := f.List(gcbd.ListQuery{MetadataField: []string{"merge_result=pull_request"}, Status: []string{"open"}}); !ok || len(rows) != 0 {
		t.Errorf("ListFailOn on a non-matching argv = (%d rows, ok=%v), want (0, true)", len(rows), ok)
	}
	// The text can span flags, as the stub's `$*` match does.
	f.ListFailOn = "--status=open --limit=0"
	if _, ok := f.List(gcbd.ListQuery{Status: []string{"open"}}); ok {
		t.Error("ListFailOn spanning two flags did not fail the read")
	}
}

// DepList follows the stub's orientation: A|blocks|B means B depends on A;
// every other type means A depends on B. Rows come back in store order and
// unknown ids drop.
func TestDepList(t *testing.T) {
	f := New(bead("anchor", nil, nil), bead("child", nil, nil), bead("blocker", nil, nil), bead("other", nil, nil))
	f.Deps = []Edge{
		{"child", "parent-child", "anchor"}, // child depends on anchor
		{"blocker", "blocks", "anchor"},     // anchor depends on blocker
		{"ghost", "blocks", "anchor"},       // no row for ghost
		{"anchor", "tracks", "other"},       // anchor depends on other
	}
	for _, tc := range []struct {
		name string
		id   string
		q    gcbd.DepQuery
		want string
	}{
		{"children: up parent-child", "anchor", gcbd.DepQuery{Direction: "up", Type: "parent-child"}, "child"},
		{"blockers: down blocks", "anchor", gcbd.DepQuery{Direction: "down", Type: "blocks"}, "blocker"},
		{"down without a type is every dependency", "anchor", gcbd.DepQuery{Direction: "down"}, "blocker,other"},
		{"up blocks from the blocker's side", "blocker", gcbd.DepQuery{Direction: "up", Type: "blocks"}, "anchor"},
		{"up tracks", "other", gcbd.DepQuery{Direction: "up", Type: "tracks"}, "anchor"},
		{"no direction: who names me", "anchor", gcbd.DepQuery{}, "child,blocker"},
		{"no edges", "other", gcbd.DepQuery{Direction: "down"}, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rows, ok := f.DepList(tc.id, tc.q)
			if !ok {
				t.Fatal("ok=false with DepFail unset")
			}
			if got := ids(rows); got != tc.want {
				t.Errorf("DepList(%s, %+v) = [%s], want [%s]", tc.id, tc.q, got, tc.want)
			}
		})
	}
	f.DepFail = true
	if _, ok := f.DepList("anchor", gcbd.DepQuery{Direction: "down", Type: "blocks"}); ok {
		t.Error("DepFail: ok=true")
	}
}

// Update parses the stub's spellings, coerces values as its jq does, applies
// in its order, and answers "updated <id>" even for an unknown id.
func TestUpdateWrites(t *testing.T) {
	f := New(bead("a", str("open"), map[string]any{"old": "x", "gone": 1}))
	out, err := f.Update("a",
		"--set-metadata", "merge_result=merged",
		"--set-metadata=pr_number= 42 ",
		"--set-metadata", "ratio=1.50",
		"--set-metadata", "big=1e2",
		"--set-metadata", "t=true", "--set-metadata", "n=null",
		"--set-metadata", "quoted=\"1\"", "--set-metadata", "plus=+1", "--set-metadata", "raw= text ",
		"--set-metadata", "eq=a=b",
		"--unset-metadata", "gone", "--unset-metadata=old",
		"--assignee", "someone",
		"--status=closed",
		"--append-notes", "first",
		"--description", "d1",
	)
	if err != nil || out != "updated a" {
		t.Fatalf("Update = (%q, %v), want (updated a, nil)", out, err)
	}
	b := f.Get("a")
	for k, want := range map[string]string{
		"merge_result": "merged",
		"pr_number":    "42",  // trimmed, typed as a number
		"ratio":        "1.5", // a number reads back as jq's tostring of the tonumber
		"big":          "100",
		"t":            "true",
		"n":            "", // null is stored (the key is present) and reads as ""
		"quoted":       `"1"`,
		"plus":         "+1", // not JSON's number grammar: raw text
		"raw":          " text ",
		"eq":           "a=b",
		"gone":         "",
		"old":          "",
	} {
		if got := b.Meta(k); got != want {
			t.Errorf("Meta(%s) = %q, want %q", k, got, want)
		}
	}
	if _, present := b.Metadata["n"]; !present {
		t.Error("k=null dropped the key; the stub stores a typed null")
	}
	if _, present := b.Metadata["gone"]; present {
		t.Error("--unset-metadata gone did not delete the key")
	}
	if b.AssigneeString() != "someone" || b.StatusLower() != "closed" || b.NotesString() != "first" {
		t.Errorf("assignee/status/notes = %q/%q/%q", b.AssigneeString(), b.StatusLower(), b.NotesString())
	}
	if f.Descriptions["a"] != "d1" {
		t.Errorf("description = %q, want d1", f.Descriptions["a"])
	}

	t.Run("notes append with a newline only after existing notes", func(t *testing.T) {
		if _, err := f.Update("a", "--append-notes", "second"); err != nil {
			t.Fatal(err)
		}
		if got := f.Get("a").NotesString(); got != "first\nsecond" {
			t.Errorf("notes = %q, want %q", got, "first\nsecond")
		}
	})

	t.Run("the = forms the stub does not parse are ignored", func(t *testing.T) {
		f := New(bead("a", str("open"), nil))
		if _, err := f.Update("a", "--status", "closed", "--append-notes=x", "-d", "desc", "--description=d2"); err != nil {
			t.Fatal(err)
		}
		b := f.Get("a")
		if b.StatusLower() != "open" || b.NotesString() != "" {
			t.Errorf("space-form --status or =-form --append-notes landed: %+v", b)
		}
		if f.Descriptions["a"] != "d2" {
			t.Errorf("description = %q, want d2 (the last spelling wins)", f.Descriptions["a"])
		}
	})

	t.Run("an empty assignee lands and a nil metadata map is created", func(t *testing.T) {
		f := New(gcbd.Bead{ID: "a", Assignee: "x"})
		if _, err := f.Update("a", "--assignee=", "--set-metadata", "k=v"); err != nil {
			t.Fatal(err)
		}
		if b := f.Get("a"); b.AssigneeString() != "" || b.Meta("k") != "v" {
			t.Errorf("row = %+v", b)
		}
	})

	t.Run("unknown id answers updated and writes nothing", func(t *testing.T) {
		f := New(bead("a", str("open"), nil))
		out, err := f.Update("zz", "--status=closed")
		if err != nil || out != "updated zz" {
			t.Errorf("Update(zz) = (%q, %v)", out, err)
		}
		if len(f.Beads) != 1 || f.Get("a").StatusLower() != "open" {
			t.Error("an unknown-id update touched the store")
		}
	})
}

func TestUpdateRefusals(t *testing.T) {
	t.Run("UpdateFail refuses every write on the id", func(t *testing.T) {
		f := New(bead("a", str("open"), nil), bead("b", str("open"), nil))
		f.UpdateFail = map[string]bool{"a": true}
		out, err := f.Update("a", "--set-metadata", "k=v")
		if err == nil || out != "gc: simulated update refusal for a" || gcbd.ExitCode(err) != 1 {
			t.Errorf("Update(a) = (%q, %v, rc=%d)", out, err, gcbd.ExitCode(err))
		}
		var ee *ExitError
		if !errors.As(err, &ee) || ee.Code != 1 {
			t.Errorf("err is %T, want *ExitError rc 1", err)
		}
		if f.Get("a").Meta("k") != "" {
			t.Error("a refused update wrote the store")
		}
		if _, err := f.Update("b", "--set-metadata", "k=v"); err != nil {
			t.Errorf("Update(b) refused: %v", err)
		}
	})

	t.Run("CloseFail refuses only --status=closed", func(t *testing.T) {
		f := New(bead("a", str("open"), nil))
		f.CloseFail = map[string]bool{"a": true}
		if out, err := f.Update("a", "--set-metadata", "k=v"); err != nil || out != "updated a" {
			t.Errorf("metadata-only write under CloseFail = (%q, %v), want it to land", out, err)
		}
		out, err := f.Update("a", "--set-metadata", "k=w", "--status=closed")
		if err == nil || out != "gc: simulated close refusal for a" || gcbd.ExitCode(err) != 1 {
			t.Errorf("close under CloseFail = (%q, %v, rc=%d)", out, err, gcbd.ExitCode(err))
		}
		if b := f.Get("a"); b.Meta("k") != "v" || b.StatusLower() != "open" {
			t.Errorf("a refused close half-landed: %+v", b)
		}
	})

	t.Run("DropKeys drops named keys and fields, never notes", func(t *testing.T) {
		f := New(bead("a", str("open"), map[string]any{"drop": "old"}))
		f.DropKeys = map[string][]string{"a": {"drop", "status", "assignee", "description"}}
		out, err := f.Update("a",
			"--set-metadata", "drop=new", "--set-metadata", "keep=yes",
			"--unset-metadata", "drop",
			"--assignee", "x", "--status=closed", "--append-notes", "n", "--description", "d")
		if err != nil || out != "updated a" {
			t.Fatalf("Update = (%q, %v)", out, err)
		}
		b := f.Get("a")
		if b.Meta("drop") != "old" || b.Meta("keep") != "yes" {
			t.Errorf("metadata = %v, want drop untouched and keep written", b.Metadata)
		}
		if b.AssigneeString() != "" || b.StatusLower() != "open" || f.Descriptions["a"] != "" {
			t.Errorf("dropped fields landed: assignee=%q status=%q desc=%q", b.AssigneeString(), b.StatusLower(), f.Descriptions["a"])
		}
		if b.NotesString() != "n" {
			t.Errorf("notes = %q, want n (never dropped)", b.NotesString())
		}
	})
}

func TestExitErrorReportsItsCode(t *testing.T) {
	e := &ExitError{Code: 3, Stderr: "boom"}
	if gcbd.ExitCode(e) != 3 || !strings.Contains(e.Error(), "boom") {
		t.Errorf("ExitCode = %d, Error = %q", gcbd.ExitCode(e), e.Error())
	}
}

// Log is STUB_GC_LOG: one line per call, the argv after `gc`, in order.
func TestLogRendersTheStubLog(t *testing.T) {
	f := New(bead("M1", str("open"), map[string]any{"merge_result": "pull_request"}))
	f.Show("M1")
	f.List(gcbd.ListQuery{Status: []string{"open"}, MetadataField: []string{"merge_result=pull_request"}})
	f.DepList("M1", gcbd.DepQuery{Direction: "down", Type: "blocks"})
	f.Update("M1", "--set-metadata", "merge_result=merged", "--status=closed")
	f.ShowDirect("M1")
	want := strings.Join([]string{
		"bd show M1",
		"bd list --metadata-field merge_result=pull_request --status=open --limit=0 --json",
		"bd dep list M1 --direction=down -t blocks --json",
		"bd update M1 --set-metadata merge_result=merged --status=closed",
		"bd show M1",
	}, "\n") + "\n"
	if got := f.Log(); got != want {
		t.Errorf("Log() =\n%s\nwant\n%s", got, want)
	}
	if n := strings.Count(f.Log(), "\nbd update M1"); n != 1 {
		t.Errorf("merge.test.sh's `grep -c '^bd update M1'` would count %d, want 1", n)
	}
	if !reflect.DeepEqual(f.Calls[3], Call{Op: "update", ID: "M1", Args: []string{"--set-metadata", "merge_result=merged", "--status=closed"}}) {
		t.Errorf("Calls[3] = %+v", f.Calls[3])
	}
}
