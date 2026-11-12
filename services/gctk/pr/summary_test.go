package pr

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

func TestRecordWritesTheSummaryAndTheTitleInOneWrite(t *testing.T) {
	s := storeWith(anchor(map[string]string{"pr_summary": ""}))
	l := ledger.New(s)
	if err := Record(l, "A", Account{Summary: "Adds the widget.\n\nAnd its stand.", Title: "feat: add the widget and its stand"}); err != nil {
		t.Fatal(err)
	}
	want := []string{"--title", "feat: add the widget and its stand", "--set-metadata", "pr_summary=Adds the widget.\n\nAnd its stand."}
	if writes := s.Writes(); len(writes) != 1 || writes[0].ID != "A" || !slices.Equal(writes[0].Args, want) {
		t.Fatalf("writes = %+v, want one update of A %q", writes, want)
	}
	got, err := Summary(l, "A")
	if err != nil || got != "Adds the widget.\n\nAnd its stand." {
		t.Errorf("summary = %q, %v", got, err)
	}
	c := compose(t, s, Request{Head: head, Opening: true, Gates: gates, Summary: true})
	if c.Title != "feat: add the widget and its stand (A)" || !strings.Contains(c.Body, "## Summary\n\nAdds the widget.\n\nAnd its stand.\n") {
		t.Errorf("the PR does not carry the account recorded:\ntitle %q\n%s", c.Title, c.Body)
	}
}

func TestRecordWritesWhatTheAccountGives(t *testing.T) {
	t.Run("a summary alone keeps the title", func(t *testing.T) {
		s := storeWith(anchor(nil))
		if err := Record(ledger.New(s), "A", Account{Summary: "Reworked."}); err != nil {
			t.Fatal(err)
		}
		if writes := s.Writes(); len(writes) != 1 || !slices.Equal(writes[0].Args, []string{"--set-metadata", "pr_summary=Reworked."}) {
			t.Errorf("writes = %+v", writes)
		}
		if row, _ := s.Row("A"); row.Title != "feat: add the widget" {
			t.Errorf("title = %q", row.Title)
		}
	})
	t.Run("a title alone keeps the summary", func(t *testing.T) {
		s := storeWith(anchor(nil))
		if err := Record(ledger.New(s), "A", Account{Title: "fix: keep the widget"}); err != nil {
			t.Fatal(err)
		}
		if writes := s.Writes(); len(writes) != 1 || !slices.Equal(writes[0].Args, []string{"--title", "fix: keep the widget"}) {
			t.Errorf("writes = %+v", writes)
		}
		if row, _ := s.Row("A"); row.Metadata["pr_summary"] != "Adds the widget." {
			t.Errorf("summary = %q", row.Metadata["pr_summary"])
		}
	})
}

func TestRecordRefusesAnAccountWithNoWords(t *testing.T) {
	for name, a := range map[string]Account{
		"neither":             {},
		"a blank summary":     {Summary: " \n\t\r\n"},
		"a blank title":       {Summary: "Adds the widget.", Title: "  "},
		"a blank title alone": {Title: "\n"},
	} {
		t.Run(name, func(t *testing.T) {
			s := storeWith(anchor(nil))
			if err := Record(ledger.New(s), "A", a); !errors.Is(err, ErrNoWords) {
				t.Errorf("err = %v, want ErrNoWords", err)
			}
			if writes := s.Writes(); len(writes) != 0 {
				t.Errorf("a refused account wrote %+v", writes)
			}
		})
	}
}

func TestRecordFailsWhenTheWriteDoesNotLand(t *testing.T) {
	s := storeWith(anchor(nil))
	s.UpdateErr = errors.New("dolt timeout")
	err := Record(ledger.New(s), "A", Account{Summary: "Reworked.", Title: "fix: keep the widget"})
	if err == nil || !strings.Contains(err.Error(), "did not land") {
		t.Errorf("err = %v", err)
	}
	if err := Record(ledger.New(storeWith()), "A", Account{Summary: "Reworked."}); err == nil {
		t.Error("a write to a bead the store does not hold landed")
	}
}

func TestSummaryReadsWhatTheBeadRecords(t *testing.T) {
	closed := anchor(map[string]string{"pr_summary": "Landed."})
	closed.ID, closed.Status = "C", "closed"
	none := anchor(nil)
	none.ID = "N"
	delete(none.Metadata, "pr_summary")
	s := storeWith(anchor(nil), closed, none)
	l := ledger.New(s)
	for id, want := range map[string]string{"A": "Adds the widget.", "C": "Landed.", "N": ""} {
		if got, err := Summary(l, id); err != nil || got != want {
			t.Errorf("%s: summary = %q, %v; want %q", id, got, err, want)
		}
	}
	if _, err := Summary(l, "Z"); err == nil || !strings.Contains(err.Error(), "holds no bead Z") {
		t.Errorf("a bead the store does not hold = %v", err)
	}
	s.FindErr = errors.New("dolt timeout")
	if _, err := Summary(l, "A"); err == nil {
		t.Error("a read that failed answered")
	}
}
