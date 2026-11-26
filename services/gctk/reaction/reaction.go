// Package reaction is gctk's first reaction: the run of mol-first-reaction
// that each bead filed into the placement queue, each patrol finding and each
// operator capture gets, which reads the bead once, writes a card on it and
// takes one of five exits (docs/human-engagement.md). It holds the rule of
// which bead may take a first reaction, which `gctk reaction check`, `sling`
// and `sweep` apply the same way, the sweep's candidate rule, which takes a
// bead by the mark its filer wrote, and its deadline, the list of beads filed
// with no mark that `gctk reaction unmarked` prints, and
// `gctk reaction dispose`, each exit's writes in their order and the rules that
// decide them: intake's (docs/steering.md), an emergency's confirmation on the
// default branch, the form each named agent takes its work in, and whether a
// hand-off reaches the named agent. It also holds `gctk reaction accept`, the
// operator's acceptance of the recommendation a recommend exit leaves, under
// the acceptance lock it runs in (accept.go). It asks waits what holds a bead
// and which runs work it, the arm to arm one, remove its arm and read whether
// a pour finished, the takeaway to write each exit's headline with its release
// and whether a bead carries one, the arm's record and the PR record what a
// bead carries, conversation which tasks are conversations, and prstatus which
// beads are human gates, and no domain asks it.
//
// A reaction disposes its subject and never closes it. Each exit orders its
// writes so that the write which dispatches, holds or gates the subject comes
// last, so a re-run of the same call after an exit stopped part way repeats
// its earlier writes harmlessly and finishes it. A subject that arrived held
// carries its hold from the start, so there the check that a re-offered
// reaction runs passes over the headline its own run wrote.
package reaction

import (
	"errors"
	"fmt"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/takeaway"
)

// recommendedFormulaKey is the action a recommend exit leaves for the
// operator's Accept, which that exit alone sets.
var recommendedFormulaKey = ledger.Declare("gc.recommended_formula", ledger.String,
	"The execution formula a first reaction's recommend exit puts to the operator beside the exit's human gate: "+
		"gctk reaction accept, which a sitting's sign-off runs with --accept, slings that formula at the bead. "+
		"gctk reaction dispose sets it once the gate is filed and clears it before any exit acts, so no "+
		"recommendation is older than the newest "+
		"first-reaction gate. gctk reaction accept clears it in the write that records its dispatch. "+
		"converse-invalidate-recommendation.sh clears it and converse-signoff.sh reads it, in shell "+
		"(docs/gctk-architecture.md, Debt). Absent or empty, the bead carries no recommendation.")

// The keys the dispose reads and does not write. No domain owns them yet.
var (
	anchorKey = ledger.ReadOnly("anchor_bead", ledger.String,
		"The bead whose PR a bead's work finishes. Intake admits such PR-finishing work to a pool.")
	failureKey = ledger.ReadOnly("failure_key", ledger.String,
		"The failure a tracker tracks, which assets/scripts/preexisting-failure.sh stamps in the create that files "+
			"the tracker. Intake admits a tracker to a pool, because a failure on a base branch is work to fix.")
)

// GateKey is the situation key of the human gate a ruling or a recommend files
// on its subject, one open gate per subject under it.
const GateKey = "first-reaction"

// The exits.
const (
	Actionable = "actionable"
	Recommend  = "recommend"
	Blocked    = "blocked"
	Close      = "close"
	Ruling     = "ruling"
)

// closer is the formula the close exit hands its subject to, which re-checks
// the call and closes the subject or asks the operator.
const closer = "mol-validate-close"

// defaultPool is the template of the pool, in the caller's rig, an actionable
// or a close exit routes to when it names none (rigPool names the pool).
const defaultPool = "polecat"

// GitHubWait bounds each GitHub read an emergency's check makes, so a stalled
// connection cannot hold the reaction and its pool slot.
const GitHubWait = 20 * time.Second

// GitHub is what an emergency's check asks of GitHub.
type GitHub interface {
	DefaultBranch(repo string) (string, error)
	HeadChecks(repo, ref string) (*gh.HeadChecks, error)
}

// Reactions is the reaction's verbs over one store: its ledger, the Gas City
// the exits reach, GitHub, the arm, and the caller's rig, which qualifies a
// pool and names the rig a sling runs under.
type Reactions struct {
	Ledger  *ledger.Ledger
	Runtime gascity.Runtime
	GitHub  GitHub
	// Arm arms a bead, as `gctk bead arm` does, and Disarm removes its arm, as
	// `gctk bead disarm` does.
	Arm    func(arm.Request) (string, error)
	Disarm func(id, reason string) (string, error)
	// Takeaway writes a bead's headline, and with a release takes the bead out
	// of play or sends it on, as `gctk bead takeaway` does, and says what
	// landed.
	Takeaway func(takeaway.Request) (string, error)
	// Sessions reads the city's live sessions, which an acceptance warns of
	// when one holds a conversation on its bead, nil to warn of none.
	Sessions func() ([]gascity.Session, error)
	// Rig is the rig the caller runs in, GC_RIG, empty when it names none.
	Rig string
	// DB is the store the caller named, a store's .beads directory, which a
	// remedy names, empty when gc routes the bead to its store.
	DB string
	// Origin reads the origin URL of a rig's checkout.
	Origin func(dir string) (string, error)
	// Now is the clock a note's time is read from.
	Now func() time.Time
	// Log takes each line the exit says as it goes, nil for none.
	Log func(string)

	// proactive is the rig's proactive pool once the roster has named it, so a
	// sweep reads the roster once for all its slings.
	proactive string
}

func (r *Reactions) say(format string, args ...any) {
	if r.Log != nil {
		r.Log(fmt.Sprintf(format, args...))
	}
}

func (r *Reactions) stamp() string {
	return r.now().UTC().Format("2006-01-02T15:04:05Z")
}

// UsageError is a call refused for what it asks, before anything is written.
type UsageError struct{ Msg string }

func (e *UsageError) Error() string { return e.Msg }

func usage(format string, args ...any) error {
	return &UsageError{Msg: fmt.Sprintf(format, args...)}
}

// errNotOpen marks a subject that is not open, to which no exit writes.
var errNotOpen = errors.New("the subject is not open")

// NotOpen reports whether err is a call that wrote nothing because its subject
// is not open.
func NotOpen(err error) bool { return errors.Is(err, errNotOpen) }
