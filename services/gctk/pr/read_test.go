package pr_test

import (
	"encoding/json"
	"maps"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// A saved read is GitHub's side of the bead's PR only while it names the PR the
// record names, at the head the store holds, with the bead's provenance instant
// (specs/tk-1tfzr71.134/design.md, section 2). Each case saves the read the
// one-PR update makes over a ready world, then moves the store the way its
// writers move it, and asks FromStore.

// readSaved is the world's metadata carrying the read the one-PR update saves
// over the world as it stands, which the evaluator answers ready over.
func (w *world) readSaved(t *testing.T) map[string]string {
	t.Helper()
	isReady(t, w.answer(t))
	return w.savedMD(t)
}

// savedMD is the bead's metadata as the one-PR update left it, once answer has
// had the update read the world's PR.
func (w *world) savedMD(t *testing.T) map[string]string {
	t.Helper()
	row, ok := w.store.Row(bead)
	if !ok {
		t.Fatal("the store lost the bead")
	}
	return maps.Clone(row.Metadata)
}

// savedRead is the read the one-PR update saves over the world as it stands.
func (w *world) savedRead(t *testing.T) *pr.SavedRead {
	t.Helper()
	w.answer(t)
	var s pr.SavedRead
	if err := json.Unmarshal([]byte(w.savedMD(t)["pr_github_read"]), &s); err != nil {
		t.Fatalf("the saved read does not decode: %v", err)
	}
	return &s
}

// unread fails unless a is the answer for a side of GitHub's that is unread:
// the condition alone, beside the store's conditions named, and no head judged.
func unread(t *testing.T, a pr.Answer, store ...pr.Kind) {
	t.Helper()
	only(t, a, append([]pr.Kind{pr.KindGitHubUnread}, store...)...)
	if a.Head != "" || a.Target != "" {
		t.Fatalf("judged head %q into %q over a read that is not current", a.Head, a.Target)
	}
}

func TestASavedReadIsCurrentOnlyAtTheHeadTheStoreHolds(t *testing.T) {
	t.Run("the read the one-PR update saved answers ready", func(t *testing.T) {
		w := ready()
		isReady(t, w.fromStore(t, w.readSaved(t)))
	})
	t.Run("a head the refinery published after the read", func(t *testing.T) {
		w := ready()
		md := w.readSaved(t)
		md["pr_head_sha"] = other
		unread(t, w.fromStore(t, md))
	})
	t.Run("no read saved", func(t *testing.T) {
		w := ready()
		unread(t, w.fromStore(t, w.md))
	})
	t.Run("the store's conditions stand beside it", func(t *testing.T) {
		w := ready()
		w.md["merge_hold"] = "true"
		w.others = append(w.others, fake.Bead{ID: "tk-child", Title: "rework", Status: "open",
			Metadata: map[string]string{"anchor_bead": bead}})
		unread(t, w.fromStore(t, w.md), pr.KindHold, pr.KindInFlight)
	})
}

func TestASavedReadOfAnotherPRIsNotCurrent(t *testing.T) {
	t.Run("another number", func(t *testing.T) {
		w := ready()
		md := w.readSaved(t)
		md["pr_number"], md["pr_url"] = "8", "https://github.com/acme/widgets/pull/8"
		unread(t, w.fromStore(t, md))
	})
	t.Run("another repository", func(t *testing.T) {
		w := ready()
		md := w.readSaved(t)
		md["pr_repo"], md["pr_url"] = "acme/gadgets", "https://github.com/acme/gadgets/pull/7"
		unread(t, w.fromStore(t, md))
	})
	t.Run("the record's repository in another case", func(t *testing.T) {
		w := ready()
		md := w.readSaved(t)
		md["pr_repo"] = "Acme/Widgets"
		isReady(t, w.fromStore(t, md))
	})
}

func TestASavedReadFromAnotherProvenanceInstantIsNotCurrent(t *testing.T) {
	w := ready()
	md := w.readSaved(t)
	md["pr_provenance_since"] = "2026-11-12T00:00:00Z"
	unread(t, w.fromStore(t, md))

	// The read keeps the instant it applied the definition from, so a read made
	// after the stamp is current again.
	w = ready()
	w.md["pr_provenance_since"] = "2026-11-12T00:00:00Z"
	isReady(t, w.fromStore(t, w.readSaved(t)))
}

// A requeue records the head it found as the store's, and saves the read it made
// there, so that read stays current until the refinery publishes again.
func TestAChangedHeadsReadIsCurrentAtTheObservedHead(t *testing.T) {
	changed := func() *world {
		w := ready()
		w.pr.Facts.HeadRefOid = other
		w.pr.Suites[other] = w.pr.Suites[head]
		w.md["review_results"] = `[{"head":"` + other + `","target":"main","passed":true}]`
		w.md["merge_result"] = "pull_request_head_changed"
		w.md["observed_pr_head_sha"] = other
		return w
	}
	t.Run("at the head found", func(t *testing.T) {
		w := changed()
		w.answer(t)
		a := w.fromStore(t, w.savedMD(t))
		only(t, a, pr.KindHead)
		if a.Head != other {
			t.Fatalf("judged head %q, want the observed head %q", a.Head, other)
		}
	})
	t.Run("at the validated head, read before the requeue", func(t *testing.T) {
		w := ready()
		md := w.readSaved(t)
		md["merge_result"], md["observed_pr_head_sha"] = "pull_request_head_changed", other
		unread(t, w.fromStore(t, md))
	})
	t.Run("a publication of the head found makes it current again", func(t *testing.T) {
		w := changed()
		w.answer(t)
		md := w.savedMD(t)
		md["merge_result"], md["pr_head_sha"] = "pull_request_pending", other
		delete(md, "observed_pr_head_sha")
		isReadyAt(t, w.fromStore(t, md), other)
	})
}

func TestASavedReadThatDoesNotDecodeAnswersNothing(t *testing.T) {
	w := ready()
	md := maps.Clone(w.md)
	md["pr_github_read"] = "{not json"
	w.put(md)
	if _, err := pr.FromStore(ledger.New(w.store), bead); err == nil {
		t.Fatal("answered over a saved read that did not decode")
	}
}

// A saved read is GitHub's side at one head only while it holds the PR, its
// checks and its conversation, the checks read at the PR's head.
func TestASavedReadMissingAPartOrSplitAcrossHeadsIsNotCurrent(t *testing.T) {
	for name, edit := range map[string]func(*pr.SavedRead){
		"no PR part":            func(s *pr.SavedRead) { s.PR = nil },
		"no checks":             func(s *pr.SavedRead) { s.Checks = nil },
		"no conversation":       func(s *pr.SavedRead) { s.Conversation = nil },
		"checks at a head gone": func(s *pr.SavedRead) { s.Checks.Head = other },
	} {
		t.Run(name, func(t *testing.T) {
			w := ready()
			s := w.savedRead(t)
			edit(s)
			raw, err := json.Marshal(s)
			if err != nil {
				t.Fatal(err)
			}
			md := maps.Clone(w.md)
			md["pr_github_read"] = string(raw)
			unread(t, w.fromStore(t, md))
		})
	}
	t.Run("no labels, which the rule does not read", func(t *testing.T) {
		w := ready()
		s := w.savedRead(t)
		s.Labels = nil
		raw, err := json.Marshal(s)
		if err != nil {
			t.Fatal(err)
		}
		md := maps.Clone(w.md)
		md["pr_github_read"] = string(raw)
		isReady(t, w.fromStore(t, md))
	})
}

// isReadyAt fails unless a is ready at h into main.
func isReadyAt(t *testing.T, a pr.Answer, h string) {
	t.Helper()
	if !a.Ready || a.Head != h || a.Target != "main" {
		t.Fatalf("ready=%v at %q into %q, conditions %+v, want ready at %s into main", a.Ready, a.Head, a.Target, a.Conditions, h)
	}
}
