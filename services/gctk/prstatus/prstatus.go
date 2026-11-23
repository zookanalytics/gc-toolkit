// Package prstatus is the one definition of what holds a PR and where the PR
// stands. Every reader asks it: the PR's labels through `gctk pr status`
// (assets/scripts/pr-status-label.sh), gc-helm.sh engage through the same verb,
// and the helm board (services/helm), which imports the package. [Read] gathers
// what the city records about each anchor through a [Store], the reader's
// adapter onto the bead store, which holds no rule of its own. [Derive], [Held]
// and [Reasons] decide from the [Facts] it gathers. No reader gathers or decides
// any of it for itself, so the readers cannot disagree.
//
// Where the PR stands is the anchor's status: vocabulary — working, merging,
// needs-review, needs-attention — which says whose move it is on an open PR.
// A resolved PR has none: the label writer takes both label families off a PR
// that merged or closed, where GitHub's own state takes over.
//
// What holds an open PR is what the city will not clear on its own: an open
// human gate on the PR or behind a bead it waits on, review feedback the city has
// not answered, or a bead a person owes the next move on, among the PR's
// blockers or behind a bead it waits on, such as another PR waiting on a review
// that the PR's rework waits for. [Holding] reads the gates and the beads a
// person owes through the PR's `blocks` edges. [Held] names these as values of
// the `held:` label family, and more than one can stand. [Reasons] names each
// thing behind those values by its bead, each gate and each bead a person owes,
// and [RenderReasons] adds the PR's own review threads by what they say. Each
// names something a person has to act on, so the PR reads needs-attention while
// any stands.
//
// The facts are state the city records: the anchor's holds
// (merge_hold/rebase_hold), the open human gates and the beads a person owes the
// next move on that its `blocks` edges reach, the pr-facts.sh posture, the
// anchor's landing state (merge_result), the review runs attached to it, and
// its in-flight set — any live bead carrying anchor_bead, the same membership
// test pr-facts.sh applies in its own arms. The rule reads none of GitHub's
// state itself. It does not consult GitHub's review posture directly — the
// working -> needs-review flip rests on that live work, which closes as it
// hands back, so a sticky changes_requested never traps the value in working
// after the set empties.
//
// Gas Town's pending record is the record a PR's bead carries from its
// publication to its merge, whose values services/gctk/pr/record declares and
// docs/state-machine.md ("The pending record") defines. A PR on that record
// ([pr.OnRecord]) stands where the pr domain's evaluator says, in the same
// vocabulary: [Render], [RenderHeld] and
// [RenderReasons] read its answer beside the facts [Read] gathers. `gctk pr
// status`, and through it the labels and engage, and the rig board
// (services/helm/internal/rigboard) ask the evaluator over the read the one-PR
// update saved on the PR's bead and the store as it stands
// ([pr.FromStore]), so none of them reads GitHub, and a change in the city
// shows at its next read. A PR whose saved read is absent, or is not of the PR
// at the head the store holds, reads working until the PR watch's next pass
// reads it, unless something only a person clears holds it, which reads
// needs-attention.
//
// The evaluator reads GitHub's merge state, its draft flag and each required
// check, so it tells a required check still running from a wedge, which GitHub
// reports alike as BLOCKED. [Derive], [Held] and [Reasons] read the facts
// alone: for a bead off the record, such as the one engage asks what holds or
// one whose record a writer left half written, and for each merge anchor the
// walk reaches ([Holding]), which it weighs by its row because the walk reads
// no GitHub.
package prstatus

import (
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// State is a PR anchor's status value: one label of the mutually-exclusive
// `status:` group. docs/pull-request-states.md ("The labels on a pull
// request") gives each value to a person, with what the person can do.
type State string

const (
	// Working: an unapproved PR the city is changing. Live work is anchored to
	// it (a rework or fix child, a validation pass, a review, a finding), or it
	// is a draft the city marks ready once its review loop passes. No human
	// input is needed.
	Working State = "working"
	// Merging: an approved PR with no known blocker. The city has it and
	// believes its next state is merged: required checks may still be running,
	// a merge-in rework or other city work may be in flight, or it waits for the
	// landing order's merge.
	Merging State = "merging"
	// NeedsReview: an unapproved PR with nothing in flight and nothing holding
	// it. The only thing left before it lands is a human's review verdict on its
	// settled head.
	NeedsReview State = "needs-review"
	// NeedsAttention: a blocker stands that the city will not clear on its own:
	// a merge or rebase hold, anything [Held] names, or a recorded posture the
	// derivation has no word for.
	NeedsAttention State = "needs-attention"
)

// Hold is a held: value, one thing that holds an open PR which the city will
// not clear on its own. Each value is a `held:` label of its own, beside the one
// status value, so more than one can stand at once. docs/pull-request-states.md
// gives each value to a person, with what the person can do.
type Hold string

const (
	// HeldGate: an open human gate holds the anchor ([Facts.Gates]). Only a
	// person clears it.
	HeldGate Hold = "gate"
	// HeldReview: review feedback the city has not answered holds the PR, on any
	// base, approved or not, and nothing in flight acts on it, so answering or
	// resolving it falls to a person: the review threads the evaluator finds
	// waiting on the city's answer, by the rule [RenderReasons] states.
	HeldReview Hold = "review"
	// HeldBlocked: a live blocker holds the PR that no automated actor will
	// clear: a bead a person owes the next move on that the PR waits on, on its
	// own blockers or behind a bead it waits on ([Facts.Owed]). Live work that
	// waits on such a bead is not the city changing the PR. A blocker the city
	// is changing or landing is no hold.
	HeldBlocked Hold = "blocked"
)

// Facts is the state the city records about the anchor, as stored. [Read]
// gathers it, and each string field carries the raw metadata value: Derive
// splits the dated posture and applies the truthiness rule itself.
type Facts struct {
	// MergeHold is metadata.merge_hold: any truthy value is an operator freeze or
	// other merge hold.
	MergeHold string
	// RebaseHold is metadata.rebase_hold: any truthy value is a rebase hold.
	RebaseHold string
	// Gates are the open human gates that hold the anchor, on the anchor itself
	// or behind a bead it waits on, nearest first, as [Holding] reads them
	// ([Holds.Gates]). Only a person clears a human gate. While one stands the
	// merge is refused: the landing order's evaluator holds a PR's merge on each
	// open wait of its bead, the gate on the anchor or the open blocker the gate
	// holds. So a gate reads as a hold, as merge_hold and rebase_hold do,
	// whatever work is in flight. A conversation is no human gate, so it is
	// never among them: one that holds the anchor's merge is among Owed.
	Gates []person.Blocker
	// Owed are the beads other than human gates that a person owes the next move
	// on, on the anchor's own blockers or behind a bead it waits on, nearest
	// first, as [Holding] reads them ([Holds.Owed]): a decision, a conversation
	// that holds the PR's merge until it closes, or another merge anchor whose
	// own state is a person's to move, such as a PR waiting on a review that a
	// rework of this one waits for. No automated actor will move any of them, so
	// each holds the PR.
	Owed []person.Blocker
	// Staying are the beads a person would owe that the PR waits on, on its own
	// blockers or behind a bead it waits on, while each waits on work of its own
	// first, as [Holding] reads them ([Holds.Staying]): a conversation whose
	// sitting stays for the work it sent, or a decision a ruling left waiting on
	// the work it sent. Each holds the merge until that work closes, so the PR
	// waits on that work first and is no person's move yet, approved or not.
	// Once the work closes, the bead is among Owed.
	Staying []person.Blocker
	// PRPosture is metadata.pr_posture, stored value@oid@instant. The value is
	// read before the first '@', and the oid after it is the head the posture
	// was read at, the current head as far as the city knows.
	PRPosture string
	// InFlightCount is the size of the anchor's in-flight set: every bead
	// carrying anchor_bead, any task_kind, at one of [InFlightStatuses] (a
	// rework or fix child, a validation pass, a review, a finding). Non-zero
	// means the city is acting on the PR.
	InFlightCount int
	// MergeResult is metadata.merge_result, the anchor's landing state. A value
	// pr.OnRecord names is a PR on Gas Town's pending record, which the pr
	// domain's evaluator answers for and [Render] renders.
	MergeResult string
	// Runs are the review runs attached to the anchor, open and closed: the
	// roots of mol-pr-review its own `blocks` edges name.
	Runs []Run
}

// Run is a review run attached to an anchor, as its root reads: its id, its
// status, the head and the target it was poured at, and when it closed.
type Run struct {
	ID, Status, Head, Target, ClosedAt string
}

// reviewFormula is the formula of a review run.
const reviewFormula = "mol-pr-review"

// runsOf is the review runs among an anchor's blockers.
func runsOf(blockers []person.Blocker) []Run {
	var out []Run
	for _, b := range blockers {
		if b.Metadata["gc.kind"] != "workflow" || b.Metadata["gc.formula_name"] != reviewFormula {
			continue
		}
		out = append(out, Run{ID: b.ID, Status: b.Status, Head: b.Metadata["gc.var.head"],
			Target: b.Metadata["gc.var.target"], ClosedAt: b.ClosedAt})
	}
	return out
}

// InFlightStatuses are the statuses at which a bead carrying anchor_bead is in
// its anchor's in-flight set, whatever its task_kind: bd-lib.sh's anchor
// statuses (_BD_ANCHOR_STATUSES) less closed. [Read] asks its [Store] for the set
// over them.
var InFlightStatuses = []string{"open", "in_progress", "blocked", "deferred", "hooked", "pinned"}

// Derive returns the state the anchor projects. Precedence:
// needs-attention > merging > working > needs-review. A blocker the city will
// not clear holds the PR whatever else stands. An approved PR with nothing
// blocking it is the city's to land, whatever work is in flight on the way. A
// bead among [Facts.Staying] holds the merge until the work it waits on closes,
// so the PR is working while one does, approved or not. Live city work on an
// unapproved PR comes before the review verdict it leads to, and the verdict is
// what remains when neither stands.
func Derive(f Facts) State {
	posture, _ := splitDated(f.PRPosture)

	// needs-attention: a blocker the city will not clear on its own. A hold
	// stands, or something [Reasons] names, each a thing a person has to act
	// on.
	if isSet(f.MergeHold) || isSet(f.RebaseHold) || len(Reasons(f)) > 0 {
		return NeedsAttention
	}
	// A recorded posture outside the vocabulary its writer declares is a state
	// the derivation cannot name.
	if !knownPosture(posture) {
		return NeedsAttention
	}

	// working: a bead that waits on work of its own first holds the merge, so
	// that work comes first, then the person's move on the bead.
	if len(f.Staying) > 0 {
		return Working
	}

	// merging: approved, and nothing known blocks the merge.
	if posture == "approved" {
		return Merging
	}

	// working: the city is changing an unapproved PR.
	if f.InFlightCount > 0 {
		return Working
	}

	// needs-review: only a human's verdict on the settled head is left.
	return NeedsReview
}

// Held returns what holds the PR, in the order gate, blocked, and nothing when
// the PR is not held: the held: value of each of its [Reasons], once each. A
// value stands only while its condition does, so the first derivation after
// the condition clears leaves it out. The merge freeze and the rebase hold are
// not among them: they read needs-attention in [Derive] with no held value of
// their own.
func Held(f Facts) []Hold { return holdsOf(Reasons(f)) }

// holdsOf is the held: value of each reason, once each, in their order. A
// reason that is the machine's fault stands for none.
func holdsOf(reasons []Reason) []Hold {
	var held []Hold
	for _, r := range reasons {
		if r.Held != "" && !slices.Contains(held, r.Held) {
			held = append(held, r.Held)
		}
	}
	return held
}

// Reason is one thing that holds an open PR: the held: value it stands for, and
// what it is. A human gate or a bead a person owes the next move on is a bead,
// which ID names and Title quotes, and engaging that bead is how a person acts
// on it. Review threads are the PR's own, so ID is empty and Title says what
// holds the PR. Held is empty for the machine's own fault, which no held: label
// names: a review run that ended without a result at the PR's head, or a gate a
// review run's failure filed ([IsMachineGate]). It reads needs-attention, as
// the city's machinery failing rather than a person's hold or a ruling owed.
type Reason struct {
	Held  Hold   `json:"held"`
	ID    string `json:"id"`
	Title string `json:"title"`
}

// gateReason is the reason a human gate holds the PR: a person's hold, or the
// machine's fault for a gate a review run's failure filed.
func gateReason(g person.Blocker) Reason {
	if IsMachineGate(g) {
		return Reason{ID: g.ID, Title: g.Title}
	}
	return Reason{Held: HeldGate, ID: g.ID, Title: g.Title}
}

// Reasons returns each thing that holds the PR, in the order of the held:
// values they stand for: each open human gate, nearest first, then each bead a
// person owes the next move on, nearest first. Nothing holds a PR whose list is
// empty.
func Reasons(f Facts) []Reason {
	var out []Reason
	for _, g := range f.Gates {
		out = append(out, gateReason(g))
	}
	for _, b := range f.Owed {
		out = append(out, Reason{Held: HeldBlocked, ID: b.ID, Title: b.Title})
	}
	return out
}

// threadsAwaiting says how many review threads wait on the city's answer.
func threadsAwaiting(n int) string {
	if n == 1 {
		return "1 review thread waits on the city's answer"
	}
	return fmt.Sprintf("%d review threads wait on the city's answer", n)
}

// knownPosture is the posture vocabulary pr-facts.sh records ([posture]
// postures in lifecycle/lifecycle.toml), plus no posture recorded yet.
func knownPosture(v string) bool {
	switch v {
	case "", "approved", "changes_requested", "commented", "review_required", "none":
		return true
	}
	return false
}

// isSet is the truthiness rule pr-facts.sh and pr-status-label.sh share,
// applied to the value as `(v // "") | tostring` renders it: null and false
// already arrive empty, and the string spellings of an unset flag are treated as
// unset too, so a hold means the same thing everywhere.
func isSet(v string) bool {
	switch v {
	case "", "false", "False", "FALSE", "0", "null":
		return false
	}
	return true
}

// splitDated splits a dated value, value@oid@instant, into its value and its
// oid. A bare value with no '@' reads whole with no oid.
func splitDated(s string) (value, oid string) {
	value = before(s, "@")
	if len(value) < len(s) {
		oid = before(s[len(value)+1:], "@")
	}
	return value, oid
}

// before returns the part of s before the first sep, or all of s when sep is
// absent — the split("@")[0] the dated posture needs.
func before(s, sep string) string {
	if i := strings.Index(s, sep); i >= 0 {
		return s[:i]
	}
	return s
}
