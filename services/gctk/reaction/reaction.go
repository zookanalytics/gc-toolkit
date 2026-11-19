// Package reaction is gctk's first reaction: the run of mol-first-reaction
// every new bead gets, which reads the bead once, writes a card on it and takes
// one of five exits (docs/human-engagement.md). It holds the rule of which bead
// may take a first reaction, which `gctk reaction check`, `sling` and `sweep`
// apply the same way, the sweep's candidate rule and its deadline, and
// `gctk reaction dispose`, each exit's writes in their order and the rules that
// decide them: intake's (docs/steering.md), an emergency's confirmation on the
// default branch, the form each named agent takes its work in, and whether a
// route or a hand-off reaches someone, which `gctk reaction deliverable` asks of
// the rig's proactive pool. It asks waits what holds a bead and which runs work
// it, the arm to arm one, the arm's record and the PR record what a bead
// carries, conversation which tasks are conversations, and prstatus which beads
// are human gates, and no domain asks it.
//
// A reaction disposes its subject and never closes it. Each exit orders its
// writes so that the write which dispatches, holds or gates the subject comes
// last, so a re-run of the same call after an exit stopped part way repeats
// its earlier writes harmlessly and finishes it.
package reaction

import (
	"errors"
	"fmt"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// recommendedFormulaKey is the action a recommend exit leaves for the
// operator's Accept, which that exit alone sets.
var recommendedFormulaKey = ledger.Declare("gc.recommended_formula", ledger.String,
	"The execution formula a first reaction's recommend exit puts to the operator: the board offers Accept, "+
		"which slings that formula at the bead, beside the exit's human gate. gctk reaction dispose sets it once "+
		"the gate is filed and clears it before any exit acts, so no recommendation is older than the newest "+
		"first-reaction gate. gc-helm.sh accept and converse-invalidate-recommendation.sh clear it, and "+
		"converse-signoff.sh reads it, in shell (docs/gctk-architecture.md, Debt). Absent or empty, the bead "+
		"carries no recommendation.")

// The keys the dispose reads and does not write. No domain owns them yet.
var anchorKey = ledger.ReadOnly("anchor_bead", ledger.String,
	"The bead whose PR a bead's work finishes. Intake admits such PR-finishing work to a pool.")

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

// defaultPool is the pool, in the caller's rig, an actionable or a close exit
// routes to when it names none.
const defaultPool = "gc-toolkit.polecat"

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
	// Arm arms a bead, as `gctk bead arm` does.
	Arm func(arm.Request) (string, error)
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
