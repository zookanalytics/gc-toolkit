package board

import (
	"slices"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus/fixture"
)

// The anchor metadata a test writes to describe a PR, which prstatus.RowFacts
// reads and the board itself never spells.
const (
	mdMergeHold           = "merge_hold"
	mdRebaseHold          = "rebase_hold"
	mdOpenedAsDraft       = "opened_as_draft"
	mdDraftReadied        = "draft_readied"
	mdPRUnansweredThreads = "pr.unanswered_threads"
)

// buildBoard is BuildBoard over anchors as the beads source hands them over:
// each live merge anchor carries what prstatus.Read gathers about its PR. A test
// describes a PR by its rows, as the store holds them, and [withPRs] reads the
// facts through prstatus.Read, so the board's tests meet a PR's facts only as
// the definition gathers them. An anchor that already carries its facts keeps
// them.
func buildBoard(anchors []Anchor, now time.Time, partial bool, partialErrors []string, facts Facts) Board {
	return BuildBoard(withPRs(anchors), now, partial, partialErrors, facts)
}

// withPRs gives each live merge anchor that carries no PR facts the facts
// prstatus.Read gathers from [rowStore] over the anchors, and the bead behind
// each of its reasons that names one ([Anchor.PRReasons]).
func withPRs(anchors []Anchor) []Anchor {
	out := slices.Clone(anchors)
	store := rowStore(out)
	for i := range out {
		if a := out[i]; isMergeAnchor(a) && a.ClosedAt.IsZero() && a.PR == nil {
			out[i] = readPR(a, store, out)
		}
	}
	return out
}

// readPR is a with the facts prstatus.Read gathers about its PR from store, and
// the bead behind each of their reasons: one of the anchor's blockers, a gate
// row among rows, or the gate a test hands in behind.
func readPR(a Anchor, store prstatus.Store, rows []Anchor, behind ...Blocker) Anchor {
	facts, err := prstatus.Read([]string{a.ID}, store)
	if err != nil {
		panic("the PR's facts did not read: " + err.Error())
	}
	f := facts[a.ID]
	a.PR = &f
	a.PRReasons = nil
	for _, r := range prstatus.Reasons(f) {
		if r.ID == "" {
			continue
		}
		if b, ok := blockerNamed(r.ID, a.Blockers, behind, rows); ok {
			a.PRReasons = append(a.PRReasons, b)
		}
	}
	return a
}

// blockerNamed is the bead id names as the gather reads a blocker: one of the
// anchor's blockers or one handed in behind, or else a gate row.
func blockerNamed(id string, blockers, behind []Blocker, rows []Anchor) (Blocker, bool) {
	for _, b := range slices.Concat(blockers, behind) {
		if b.ID == id {
			return b, true
		}
	}
	for _, r := range rows {
		if r.ID == id && r.Source == KindGate {
			return Blocker{ID: r.ID, Title: r.Title, Status: "open", IssueType: "gate", AwaitType: "human"}, true
		}
	}
	return Blocker{}, false
}

// rowStore is the store the anchors describe: each anchor a bead waiting on its
// blockers, open unless it closed, each bead in more as a test hands it in, and
// each other blocker a bead of its own. An open
// gate row is a human gate, and each bead it is about waits on it. A row naming
// an anchor in anchor_bead is therefore in the anchor's in-flight set while it
// is live, as the store holds it. A conversation tracks its bead and blocks
// nothing, so it waits on nothing here.
func rowStore(anchors []Anchor, more ...fixture.Bead) *fixture.Store {
	var order []string
	beads := map[string]fixture.Bead{}
	put := func(b fixture.Bead) {
		if _, ok := beads[b.ID]; !ok {
			order = append(order, b.ID)
			beads[b.ID] = b
		}
	}
	for _, a := range anchors {
		b := fixture.Bead{ID: a.ID, Title: a.Title, Status: "open", Metadata: a.Metadata}
		if !a.ClosedAt.IsZero() {
			b.Status = "closed"
		}
		switch a.Source {
		case KindGate:
			b.IssueType, b.AwaitType = "gate", "human"
		case "decision":
			b.IssueType = "decision"
		default:
			b.IssueType = "task"
		}
		for _, bl := range a.Blockers {
			b.WaitsOn = append(b.WaitsOn, bl.ID)
		}
		put(b)
	}
	for _, b := range more {
		put(b)
	}
	for _, a := range anchors {
		for _, bl := range a.Blockers {
			put(fixture.Bead{ID: bl.ID, Title: bl.Title, Status: bl.Status, IssueType: bl.IssueType, AwaitType: bl.AwaitType,
				Metadata: map[string]string{"gc.routed_to": bl.RoutedTo}})
		}
	}
	for _, a := range anchors {
		if a.Source != KindGate || !a.ClosedAt.IsZero() {
			continue
		}
		for _, s := range a.Subjects {
			if w, ok := beads[s]; ok && !slices.Contains(w.WaitsOn, a.ID) {
				w.WaitsOn = append(w.WaitsOn, a.ID)
				beads[s] = w
			}
		}
	}
	list := make([]fixture.Bead, 0, len(order))
	for _, id := range order {
		list = append(list, beads[id])
	}
	return fixture.NewStore(list)
}

// member is a bead in an anchor's in-flight set: it names the anchor in
// anchor_bead, with its task_kind and status.
func member(id, taskKind, status string) Child {
	return Child{ID: id, Status: status, Metadata: map[string]string{mdTaskKind: taskKind}}
}

// withInFlight is a merge anchor whose in-flight set holds children beside the
// rows a board shows for it, read through prstatus.Read.
func withInFlight(a Anchor, children ...Child) Anchor {
	var more []fixture.Bead
	for _, c := range children {
		md := map[string]string{mdAnchorBead: a.ID}
		for k, v := range c.Metadata {
			md[k] = v
		}
		more = append(more, fixture.Bead{ID: c.ID, Status: c.Status, IssueType: "task", Metadata: md})
	}
	a.PR = nil
	return readPR(a, rowStore([]Anchor{a}, more...), nil)
}

// heldThroughRework is a merge anchor the way the beads source gathers one that
// waits on a rework which waits on open human gates: the rework in its `blocks`
// listing, and the gates among its PR's reasons, nearest first, as its walk
// reaches them.
func heldThroughRework(md map[string]string, gates ...Blocker) Anchor {
	a := mergeAnchor("tk-a", md, Blocker{ID: "tk-rw", Title: "fix the check", Status: "open", IssueType: "task"})
	rework := fixture.Bead{ID: "tk-rw", Title: "fix the check", Status: "open", IssueType: "task"}
	var more []fixture.Bead
	for _, g := range gates {
		rework.WaitsOn = append(rework.WaitsOn, g.ID)
		more = append(more, fixture.Bead{ID: g.ID, Title: g.Title, Status: g.Status, IssueType: g.IssueType, AwaitType: g.AwaitType})
	}
	store := rowStore([]Anchor{a}, append([]fixture.Bead{rework}, more...)...)
	return readPR(a, store, nil, gates...)
}
