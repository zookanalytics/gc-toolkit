package pr

import (
	"errors"
	"fmt"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// summaryKey is a bead's PR summary, the pr domain's own key. Gas Town's
// refinery fills a PR's summary from its bead's description, which is written
// before the work, so the change's author records this account once the work
// is done, and the PR's managed summary region carries it in place of the
// dispatch text.
var summaryKey = ledger.Declare("pr_summary", ledger.String,
	"The account of what a change does, for its PR, in freeform markdown. `gctk pr summary` is its one "+
		"writer: the polecat records it on the anchor at submit, and an integration effort's summary task on "+
		"the effort's landing bead once the effort's work has landed. The PR's managed summary region carries "+
		"it (`gctk pr compose`), and `gctk pr summary` prints it for a reader of the PR's text. Absent or "+
		"blank, the dispatch text stands in. Never cleared: the next record replaces it.")

// Account is what a change's author records for its PR: the summary, which
// says what the finished change does, and the change's subject line, which the
// bead takes as its title, since the PR's title is composed from it. An empty
// field leaves the bead's as it stands.
type Account struct {
	Summary string
	Title   string
}

// ErrNoWords is the error of an account Record refuses before any write: one
// that records neither a summary nor a title, or one whose summary or title
// has no words.
var ErrNoWords = errors.New("nothing to record")

// Record writes the account onto the bead in one write, whose exit decides
// whether it landed. A summary or a title given with no words, or an account
// that gives neither, is refused with ErrNoWords, and nothing is written.
func Record(l *ledger.Ledger, bead string, a Account) error {
	if a.Summary == "" && a.Title == "" {
		return fmt.Errorf("%w: give a summary, a title or both", ErrNoWords)
	}
	if a.Summary != "" && noWords(a.Summary) {
		return fmt.Errorf("%w: the summary has no words", ErrNoWords)
	}
	if a.Title != "" && noWords(a.Title) {
		return fmt.Errorf("%w: the title has no words", ErrNoWords)
	}
	w := l.Write(bead)
	if a.Title != "" {
		w.Title(a.Title)
	}
	if a.Summary != "" {
		summaryKey.Set(w, a.Summary)
	}
	return l.Commit(w)
}

// Summary is the PR summary the bead records, "" when it records none. A
// closed bead's reads as an open one's does. A bead the store does not hold, or
// one that does not read, returns an error.
func Summary(l *ledger.Ledger, bead string) (string, error) {
	recs, err := l.Find(ledger.ByID(bead).WithClosed())
	if err != nil {
		return "", err
	}
	for _, r := range recs {
		if r.ID != bead {
			continue
		}
		v, _, err := summaryKey.Get(r)
		return v, err
	}
	return "", fmt.Errorf("the store holds no bead %s", bead)
}

// noWords is text of whitespace alone, which a composition reads as no
// summary.
func noWords(s string) bool { return strings.TrimFunc(s, isSpace) == "" }
