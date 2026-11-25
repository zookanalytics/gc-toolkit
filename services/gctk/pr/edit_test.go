package pr_test

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// A review round's edit of the PR's title and body, on the draft cycle's
// world: the bead's PR open from its branch, published by the refinery from
// the summary the bead held then.

// editRequest is the composition a round's push asks for at head, with the
// gates resolved to none, as the refinery publishes.
func editRequest() pr.Request {
	return pr.Request{Head: head, Target: "main", Gates: []pr.Gate{}}
}

// newEditing is the world with the PR's title and body as the refinery
// published them from the summary "It did less.".
func newEditing(t *testing.T) *land {
	t.Helper()
	d := newCycle(t)
	d.pr.Facts.IsDraft = true
	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_summary"] = "It did less." })
	c, err := pr.Compose(d.l.Ledger, bead, editRequest())
	if err != nil {
		t.Fatal(err)
	}
	d.pr.Title, d.pr.Body = c.Title, c.Body
	return d
}

// edits is each edit asked of GitHub: the PR's node id and what it set.
func edits(g *ghfake.GitHub) []string {
	var out []string
	for _, a := range g.Asks() {
		if a.Method == "EditPullRequest" {
			out = append(out, a.ID+" "+a.Message)
		}
	}
	return out
}

// A round that rewrote the bead's title and summary brings both onto the PR
// in one edit, and the next push finds the PR carrying them and asks nothing.
func TestAnEditBringsThePRsTitleAndBodyCurrentWithItsBead(t *testing.T) {
	d := newEditing(t)
	d.edit(t, func(b *fake.Bead) {
		b.Title = "fix: the work done right"
		b.Metadata["pr_summary"] = "It does the work."
	})
	got, err := d.l.Edit(bead, "", editRequest())
	if err != nil || got.URL != prURL || !got.Title || !got.Body {
		t.Fatalf("the edit read %+v, %v; want the title and the body of %s edited", got, err, prURL)
	}
	if d.pr.Title != "fix: the work done right (tk-1)" || !strings.Contains(d.pr.Body, "It does the work.") ||
		strings.Contains(d.pr.Body, "It did less.") {
		t.Fatalf("the PR reads %q with body:\n%s", d.pr.Title, d.pr.Body)
	}
	if got := edits(d.github); !slices.Equal(got, []string{"PR_7 title and body"}) {
		t.Fatalf("asked %v; want one edit of both", got)
	}
	again, err := d.l.Edit(bead, "", editRequest())
	if err != nil || again.Title || again.Body || len(edits(d.github)) != 1 {
		t.Fatalf("a second push read %+v, %v, with edits %v; want nothing asked", again, err, edits(d.github))
	}
	if !d.pr.Facts.IsDraft {
		t.Fatal("the edit moved the PR's draft flag")
	}
}

// Only what moved is edited: a summary the bead rewrote edits the body alone,
// a title that differs only in spacing is the same title, and a bead whose
// title has no words leaves the PR's title as it stands. A body the
// composition cannot read back, one a person wrote, is left as it stands while
// the title still moves.
func TestAnEditSetsOnlyWhatMoved(t *testing.T) {
	d := newEditing(t)
	d.pr.Title = "chore:  the work\t(tk-1) "
	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_summary"] = "It does the work." })
	if got, err := d.l.Edit(bead, "", editRequest()); err != nil || got.Title || !got.Body {
		t.Fatalf("a rewritten summary read %+v, %v; want the body alone edited", got, err)
	}
	if got := edits(d.github); !slices.Equal(got, []string{"PR_7 body"}) {
		t.Fatalf("asked %v; want one edit of the body", got)
	}

	d = newEditing(t)
	d.edit(t, func(b *fake.Bead) { b.Title = " " })
	if got, err := d.l.Edit(bead, "", editRequest()); err != nil || got.Title || got.Body || len(edits(d.github)) != 0 {
		t.Fatalf("a bead whose title has no words read %+v, %v, with edits %v", got, err, edits(d.github))
	}

	d = newEditing(t)
	d.pr.Body = "A person wrote this body."
	d.edit(t, func(b *fake.Bead) {
		b.Title = "fix: the work done right"
		b.Metadata["pr_summary"] = "It does the work."
	})
	if got, err := d.l.Edit(bead, "", editRequest()); err != nil || !got.Title || got.Body {
		t.Fatalf("a hand-written body read %+v, %v; want the title alone edited", got, err)
	}
	if d.pr.Body != "A person wrote this body." {
		t.Fatalf("the hand-written body became:\n%s", d.pr.Body)
	}
}

// The PR is the one the bead owns, as for a return to draft: a bead that names
// none, a closed PR, one open from another branch and one outside the rig's
// origin are refused with nothing read of their text or edited.
func TestAnEditTakesOnlyAnOpenPRTheBeadOwns(t *testing.T) {
	var refused *pr.EditRefusal
	d := newEditing(t)
	d.edit(t, func(b *fake.Bead) { delete(b.Metadata, "pr_url"); delete(b.Metadata, "existing_pr") })
	if _, err := d.l.Edit(bead, "", editRequest()); !errors.As(err, &refused) {
		t.Fatalf("a bead that names no PR read as %v", err)
	}
	for name, change := range map[string]func(p *ghfake.PR){
		"closed":  func(p *ghfake.PR) { p.Facts.State = "CLOSED" },
		"another": func(p *ghfake.PR) { p.Facts.HeadRefName = "polecat/tk-2" },
	} {
		e := newEditing(t)
		e.edit(t, func(b *fake.Bead) { b.Metadata["pr_summary"] = "It does the work." })
		change(e.pr)
		if _, err := e.l.Edit(bead, "", editRequest()); !errors.As(err, &refused) || len(edits(e.github)) != 0 {
			t.Fatalf("a %s PR read as %v, with edits %v", name, err, edits(e.github))
		}
	}
	e := newEditing(t)
	var origin *pr.OriginError
	if _, err := e.l.Edit(bead, "https://github.com/acme/other/pull/7", editRequest()); !errors.As(err, &origin) {
		t.Fatalf("a PR outside the rig's origin read as %v", err)
	}
	if slices.Contains(e.github.Reads(), "PullRequestText") {
		t.Fatal("the text of a PR outside the rig's origin was read")
	}
}

// A read that does not answer edits nothing, and an edit GitHub refused or did
// not answer is an error whose retry finds the PR as it stands and edits what
// still differs.
func TestAnEditThatDoesNotLandIsAnErrorARetryFinishes(t *testing.T) {
	d := newEditing(t)
	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_summary"] = "It does the work." })
	d.github.Fail["PullRequestText"] = errors.New("gh: error connecting to api.github.com")
	if _, err := d.l.Edit(bead, "", editRequest()); err == nil || len(edits(d.github)) != 0 {
		t.Fatalf("an unanswered read read as %v, with edits %v", err, edits(d.github))
	}
	delete(d.github.Fail, "PullRequestText")
	d.github.Fail["EditPullRequest"] = errors.New("gh: HTTP 502")
	if _, err := d.l.Edit(bead, "", editRequest()); err == nil || strings.Contains(d.pr.Body, "It does the work.") {
		t.Fatalf("an unanswered edit read as %v, the body:\n%s", err, d.pr.Body)
	}
	delete(d.github.Fail, "EditPullRequest")
	if got, err := d.l.Edit(bead, "", editRequest()); err != nil || !got.Body || !strings.Contains(d.pr.Body, "It does the work.") {
		t.Fatalf("the retry read %+v, %v, the body:\n%s", got, err, d.pr.Body)
	}
}
