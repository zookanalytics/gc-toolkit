package record_test

import (
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

const head = "1111111111111111111111111111111111111111"

func TestParseURLReadsAPullRequestsURL(t *testing.T) {
	host, repo, n, ok := record.ParseURL("https://github.com/acme/widgets/pull/7")
	if !ok || host != "github.com" || repo != "acme/widgets" || n != 7 {
		t.Fatalf("ParseURL = %q %q %d %v", host, repo, n, ok)
	}
	for _, bad := range []string{"https://github.com/acme/widgets/issues/7", "http://github.com/acme/widgets/pull/7",
		"https://github.com/acme/widgets/pull/0", "https://github.com/acme/pull/7", ""} {
		if _, _, _, ok := record.ParseURL(bad); ok {
			t.Errorf("ParseURL took %q", bad)
		}
	}
}

func TestAPublicationNamesItsPRWhole(t *testing.T) {
	good := record.Publication{URL: "https://github.com/acme/widgets/pull/7", Repo: "Acme/Widgets", Number: 7,
		Head: head, Target: "main"}
	if err := good.Valid(); err != nil {
		t.Fatal(err)
	}
	for name, p := range map[string]record.Publication{
		"another number": {URL: good.URL, Repo: good.Repo, Number: 8, Head: head, Target: "main"},
		"another repo":   {URL: good.URL, Repo: "acme/other", Number: 7, Head: head, Target: "main"},
		"a short head":   {URL: good.URL, Repo: good.Repo, Number: 7, Head: "1111111", Target: "main"},
		"no target":      {URL: good.URL, Repo: good.Repo, Number: 7, Head: head},
	} {
		if err := p.Valid(); err == nil {
			t.Errorf("%s: a publication that does not name its PR whole was valid", name)
		}
	}
}

// Read reads the record as it is stored, and only the marker set true marks it.
func TestReadReadsTheRecordAndItsMarker(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "blocked", Metadata: map[string]string{
		"merge_result": record.Pending, "pr_url": "u", "pr_reconcile_pending": "true", "pr_last_checked_at": "t"}})
	s.Put(fake.Bead{ID: "b-2", Status: "open", Metadata: map[string]string{"pr_reconcile_pending": "false"}})
	rows, err := ledger.New(s).Find(record.Marked())
	if err != nil || len(rows) != 2 {
		t.Fatalf("Marked found %d rows, %v", len(rows), err)
	}
	for _, r := range rows {
		rec, err := record.Read(r)
		if err != nil {
			t.Fatal(err)
		}
		if want := r.ID == "b-1"; rec.Marked != want {
			t.Errorf("%s reads marked %v", r.ID, rec.Marked)
		}
		if r.ID == "b-1" && (rec.Result != record.Pending || rec.URL != "u" || rec.CheckedAt != "t") {
			t.Errorf("b-1 reads %+v", rec)
		}
	}
	if !record.OnRecord(record.HeadChanged) || record.OnRecord(record.Merged) || !record.Exception(record.LegacyClosed) ||
		!record.Exception(record.CloseRefused) || record.Exception(record.Pending) {
		t.Fatal("the record's values read wrong")
	}
	for v, want := range map[string]bool{record.Merged: true, record.CloseRefused: true, record.MergedUnvalidatedHead: true,
		record.Pending: false, record.HeadChanged: false, record.ClosedUnmerged: false, record.EvidenceContradiction: false,
		record.LegacyClosed: false, record.Invalid: false, record.Incomplete: false, "merged": false, "": false} {
		if record.PRMerged(v) != want {
			t.Errorf("PRMerged(%q) = %v", v, !want)
		}
	}
	if !strings.HasPrefix(record.Result.Name(), "merge_result") {
		t.Fatal("the reading face names another key")
	}
}

// writes is the update each write makes, as its flags.
func writes(t *testing.T, act func(*ledger.Write)) []string {
	t.Helper()
	s := fake.New()
	s.Put(fake.Bead{ID: "b-1", Status: "open", Assignee: "rig/refinery"})
	l := ledger.New(s)
	w := l.Write("b-1")
	act(w)
	if err := l.Commit(w); err != nil {
		t.Fatal(err)
	}
	return s.Writes()[0].Args
}

func has(args []string, flag string) bool {
	for _, a := range args {
		if a == flag {
			return true
		}
	}
	return false
}

// The bead's assignee says who works it now: the writes that end the
// refinery's work on it assign it to nobody, the writes that hand it to the
// refinery assign the refinery, and a requeue that keeps the marker leaves the
// assignee as it is.
func TestTheRecordsWritesAssignTheBeadToWhoWorksItNow(t *testing.T) {
	const refinery = "rig/refinery"
	p := record.Publication{URL: "https://github.com/acme/widgets/pull/7", Repo: "acme/widgets", Number: 7, Head: head, Target: "main"}
	for name, c := range map[string]struct {
		act  func(*ledger.Write)
		want string
	}{
		"publish":         {func(w *ledger.Write) { record.Publish(w, p) }, "--assignee="},
		"block":           {record.Block, "--assignee="},
		"settle":          {func(w *ledger.Write) { record.Settle(w, refinery) }, "--assignee=" + refinery},
		"requeue handing": {func(w *ledger.Write) { record.Requeue(w, p.URL, head, "why", refinery) }, "--assignee=" + refinery},
		"revalidate":      {func(w *ledger.Write) { record.Revalidate(w, "why", refinery) }, "--assignee=" + refinery},
	} {
		if args := writes(t, c.act); !has(args, c.want) {
			t.Errorf("%s writes %q, want %s", name, args, c.want)
		}
	}
	kept := writes(t, func(w *ledger.Write) { record.Requeue(w, p.URL, head, "why", "") })
	for _, a := range kept {
		if strings.HasPrefix(a, "--assignee") || a == "pr_reconcile_pending" {
			t.Fatalf("a requeue that keeps the marker writes %q", kept)
		}
	}
	if handed := writes(t, func(w *ledger.Write) { record.Requeue(w, p.URL, head, "why", refinery) }); !has(handed, "pr_reconcile_pending") {
		t.Fatalf("a requeue that hands the head over keeps the marker: %q", handed)
	}
}
