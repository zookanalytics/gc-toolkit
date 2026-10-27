package board

import (
	"reflect"
	"slices"
	"strings"
	"testing"
)

// gateAnchor builds a human gate the way source.collectGateAnchors admits one:
// a gate-kind anchor titled with its question, whose Subjects are the beads
// that wait on it through a `blocks` edge.
func gateAnchor(id, ask string, subjects ...string) Anchor {
	return Anchor{
		ID: id, Kind: KindGate, Source: KindGate, Rig: "gc-toolkit", Prefix: "tk",
		Title: ask, Subjects: subjects,
	}
}

// conversationAnchor builds a conversation the way the gather admits one: a
// task tracking subject, held by assignee — `human` while it waits in the
// operator's queue, a sitting's alias while a sitting holds it — and replying
// to the gates it answers.
func conversationAnchor(id, subject, title, assignee string, repliesTo ...string) Anchor {
	return Anchor{
		ID: id, Kind: KindConversation, Source: KindConversation, Rig: "gc-toolkit", Prefix: "tk",
		Title: title, Subjects: []string{subject}, Assignee: assignee, RepliesTo: repliesTo,
	}
}

// sittingAlias is the qualified alias a sitting holds conversation id under.
func sittingAlias(id string) string { return "gc-toolkit/gc-toolkit." + id }

// epicSubject is a plain live anchor with one open child, which bands
// stranded (HIGH) when nothing holds it.
func epicSubject(id string) Anchor {
	return Anchor{
		ID: id, Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
		Children: []Child{{ID: id + ".c", Status: "open"}},
	}
}

// gateBlocker is a human gate as a bead's own `blocks` listing carries it:
// open, under the given key.
func gateBlocker(id, key, title string) Blocker {
	return Blocker{ID: id, Title: title, Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: key,
		CreatedAt: daysAgo(3), UpdatedAt: daysAgo(3)}
}

// recommendationSubject is a bead a first reaction has stamped with a
// recommended execution formula, carrying the human gates its `blocks` listing
// names. It is the parked row the recommend exit's takeaway gives it.
func recommendationSubject(id, formula string, gates ...Blocker) Anchor {
	a := Anchor{
		ID: id, Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2),
		Title: "t " + id, Takeaway: "recommend " + formula, Notes: "## Proposal\nrun " + formula,
		Metadata: map[string]string{"gc.takeaway": "recommend " + formula, "gc.recommended_formula": formula},
	}
	for _, g := range gates {
		a.Blockers = append(a.Blockers, g)
		a.WaitingOn = append(a.WaitingOn, g.ID)
		if g.Status == "closed" {
			a.WaitingOnClosed = append(a.WaitingOnClosed, g.ID)
		}
	}
	return a
}

// gatesFor builds the gate anchors for each open gate in a bead's listing, as
// the gate gather admits them beside it.
func gatesFor(bead string, gates ...Blocker) []Anchor {
	var out []Anchor
	for _, g := range gates {
		if g.Status != "closed" {
			out = append(out, gateAnchor(g.ID, g.Title, bead))
		}
	}
	return out
}

// TestSectionClassification pins the band each kind lands in.
func TestSectionClassification(t *testing.T) {
	anchors := []Anchor{
		// A pull request → review, whether or not the cadence recorded a position.
		{ID: "tk-pr", Kind: "merge", Source: "merge", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"merge_result": "pull_request", "pr_number": "7"}},
		// A decision → gate (a person must answer).
		{ID: "tk-dec", Kind: "decision", Source: "decision", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(1)},
		// A stranded epic → stalled.
		{ID: "tk-strand", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			Children: []Child{{ID: "tk-x", Status: "open"}}},
		// A healthy in-flight epic → active.
		{ID: "tk-active", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			Children: []Child{{ID: "tk-y", Status: "in_progress", Assignee: "sess-live"}}},
		// An empty anchor → cleanup.
		{ID: "tk-empty", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk"},
		// A closed anchor → done.
		{ID: "tk-closed", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk",
			ClosedAt: daysAgo(1), Children: []Child{{ID: "tk-z", Status: "closed"}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, liveOwners("sess-live"))

	want := map[string]string{
		"tk-pr":     SectionReview,
		"tk-dec":    SectionGate,
		"tk-strand": SectionStalled,
		"tk-active": SectionActive,
		"tk-empty":  SectionCleanup,
		"tk-closed": SectionDone,
	}
	for id, sec := range want {
		tile, ok := tileByID(b, id)
		if !ok {
			t.Fatalf("%s missing from board", id)
		}
		if tile.Section != sec {
			t.Errorf("%s: section = %q, want %q", id, tile.Section, sec)
		}
	}
}

// TestGateFoldsOntoEachBeadItBlocks is the shared-gate case's first step: an
// anchor and its rework child both wait on the anchor's bring-current gate.
// The gate folds onto both rows and leaves no row of its own. Each row is held
// and owed, and lists the gate among what its bead waits on. The child's needs
// is the gate's question; the merge anchor keeps its PR needs, whose `asking`
// names the same question.
func TestGateFoldsOntoEachBeadItBlocks(t *testing.T) {
	const ask = "Bring the branch current over the conflict?"
	gate := gateBlocker("tk-gate", "bring-current", ask)
	anchor := Anchor{ID: "tk-anchor", Kind: "merge", Source: "merge", Rig: "gc-toolkit", Prefix: "tk",
		Metadata: map[string]string{"merge_result": "pull_request", "pr_number": "7"},
		Blockers: []Blocker{gate}, WaitingOn: []string{"tk-gate"}}
	child := Anchor{ID: "tk-child", Kind: kindRework, Source: kindRework, Rig: "gc-toolkit", Prefix: "tk",
		Metadata: map[string]string{"anchor_bead": "tk-anchor", "task_kind": "rework"},
		Blockers: []Blocker{gate}, WaitingOn: []string{"tk-gate"}}
	b := BuildBoard([]Anchor{anchor, child, gateAnchor("tk-gate", ask, "tk-anchor", "tk-child")}, fixtureNow, false, nil, Facts{})

	if g, ok := tileByID(b, "tk-gate"); ok {
		t.Errorf("a gate whose beads have rows takes no row of its own; got one in %q", g.Section)
	}
	for _, id := range []string{"tk-anchor", "tk-child"} {
		row := mustTile(t, b, id)
		if !row.Held || !row.Owed || row.SittingState != SittingWaiting {
			t.Errorf("%s: a gate holds and owes each bead it blocks: held=%v owed=%v state=%q", id, row.Held, row.Owed, row.SittingState)
		}
		if !slices.Contains(row.WaitingOnOpen, "tk-gate") {
			t.Errorf("%s: the row lists the gate among what its bead waits on: %v", id, row.WaitingOnOpen)
		}
		if row.GatesInSession != nil {
			t.Errorf("%s: no sitting answers the gate: gates_in_session=%q", id, *row.GatesInSession)
		}
	}
	if got := mustTile(t, b, "tk-child").Needs; got != ask {
		t.Errorf("the child's needs is the gate's question: got %q", got)
	}
	if got := mustTile(t, b, "tk-anchor").Needs; got != "asking: "+ask {
		t.Errorf("the merge anchor's PR needs names the gate it is asking: got %q", got)
	}
}

// TestSharedGateAnsweredInTheAnchorsSitting is the shared-gate case's third and
// fourth steps. A conversation tracks the anchor alone, so the anchor's row is
// in session and the child's is not. The sitting replies to the gate, so both
// rows mark that gate in session.
func TestSharedGateAnsweredInTheAnchorsSitting(t *testing.T) {
	const ask = "Bring the branch current over the conflict?"
	conv := conversationAnchor("tk-conv", "tk-anchor", "the anchor", sittingAlias("tk-conv"))
	build := func(conv Anchor) Board {
		return BuildBoard([]Anchor{
			epicSubject("tk-anchor"), humanKid("tk-child"), gateAnchor("tk-gate", ask, "tk-anchor", "tk-child"), conv,
		}, fixtureNow, false, nil, liveOwners(sittingAlias("tk-conv")))
	}

	b := build(conv)
	if a := mustTile(t, b, "tk-anchor"); a.SittingState != SittingInSession || a.Needs != ask {
		t.Errorf("the anchor's row is in session and still names its gate: state=%q needs=%q", a.SittingState, a.Needs)
	}
	if c := mustTile(t, b, "tk-child"); c.SittingState != SittingWaiting || c.GatesInSession != nil {
		t.Errorf("the child's row is not in session before the sitting replies to the gate: state=%q", c.SittingState)
	}

	conv.RepliesTo = []string{"tk-gate"}
	b = build(conv)
	for _, id := range []string{"tk-anchor", "tk-child"} {
		row := mustTile(t, b, id)
		if row.GatesInSession == nil || *row.GatesInSession != ask {
			t.Errorf("%s: a gate the live sitting replies to is in session on every row it folds onto: %v", id, row.GatesInSession)
		}
		if !row.Owed {
			t.Errorf("%s: a gate in session is still open, and still owed", id)
		}
	}
	if c := mustTile(t, b, "tk-child"); c.SittingState != SittingWaiting {
		t.Errorf("no conversation tracks the child, so its row waits: got %q", c.SittingState)
	}
}

// TestEpicSittingAnswersItsMembersGate is the shared-gate case's second
// variant: the gate is on one member of an epic and the sitting is on the
// epic. The member's row marks the gate in session though no conversation
// tracks the member.
func TestEpicSittingAnswersItsMembersGate(t *testing.T) {
	const ask = "Which shape should the member take?"
	b := BuildBoard([]Anchor{
		epicWith("tk-epic", "tk-member"), humanKid("tk-member"),
		gateAnchor("tk-gate", ask, "tk-member"),
		conversationAnchor("tk-conv", "tk-epic", "the epic", sittingAlias("tk-conv"), "tk-gate"),
	}, fixtureNow, false, nil, liveOwners(sittingAlias("tk-conv")))

	m := mustTile(t, b, "tk-member")
	if m.GatesInSession == nil || *m.GatesInSession != ask || m.SittingState != SittingWaiting {
		t.Errorf("the member's row marks its gate in session and waits: gates_in_session=%v state=%q", m.GatesInSession, m.SittingState)
	}
	if e := mustTile(t, b, "tk-epic"); e.SittingState != SittingInSession || e.Owed {
		t.Errorf("the epic's row is in session and owes nothing for it: state=%q owed=%v", e.SittingState, e.Owed)
	}
}

// TestGateKeptWhenNoBeadHasARow: a gate whose beads have no row of their own
// keeps its row, so no open gate is off the board. Its NEEDS states the
// question, and its TITLE names the gate and its beads rather than repeating
// the question.
func TestGateKeptWhenNoBeadHasARow(t *testing.T) {
	b := BuildBoard([]Anchor{gateAnchor("tk-g", "Approve the rollout?", "tk-ghost")}, fixtureNow, false, nil, Facts{})

	g := mustTile(t, b, "tk-g")
	if g.Needs != "Approve the rollout?" || g.Title != "gate: tk-ghost" {
		t.Errorf("kept gate states its question beside a title naming its bead: title=%q needs=%q", g.Title, g.Needs)
	}
	if !g.Owed || g.Section != SectionGate || g.Severity != SevElevated {
		t.Errorf("kept gate is owed and bands as a gate: owed=%v section=%q severity=%s", g.Owed, g.Section, g.Severity)
	}
}

// TestConversationInTheQueueOwesItsBead: a conversation waiting in the
// operator's queue holds its bead and makes it owed, with the conversation's
// title as the row's needs. One whose sitting's session has ended waits the
// same way, read by the conversation's assignee or by its gc.session_name: a
// session that closed, one whose launch failed and was rolled back without
// closing it (failed-create), and one listed with no state.
func TestConversationInTheQueueOwesItsBead(t *testing.T) {
	const session = "gc-toolkit__converse-tk-conv"
	for _, tc := range []struct {
		name     string
		assignee string
		session  string
		facts    Facts
	}{
		{"queued", "human", "", Facts{}},
		{"sitting's session closed", sittingAlias("tk-conv"), "", Facts{OwnerState: map[string]string{sittingAlias("tk-conv"): "closed"}}},
		{"sitting's session failed to create", sittingAlias("tk-conv"), "", Facts{OwnerState: map[string]string{sittingAlias("tk-conv"): "failed-create"}}},
		{"sitting's session failed to create, by its session name", sittingAlias("tk-conv"), session, Facts{OwnerState: map[string]string{session: "failed-create"}}},
		{"sitting's session listed with no state", sittingAlias("tk-conv"), "", Facts{OwnerState: map[string]string{sittingAlias("tk-conv"): ""}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			conv := conversationAnchor("tk-conv", "tk-subj", "talk through the plan", tc.assignee)
			if tc.session != "" {
				conv.Metadata = map[string]string{mdSessionName: tc.session}
			}
			b := BuildBoard([]Anchor{epicSubject("tk-subj"), conv}, fixtureNow, false, nil, tc.facts)
			if _, ok := tileByID(b, "tk-conv"); ok {
				t.Errorf("the conversation folds onto its bead's row")
			}
			s := mustTile(t, b, "tk-subj")
			if !s.Held || !s.Owed || s.Needs != "talk through the plan" || s.SittingState != SittingWaiting {
				t.Errorf("a waiting conversation holds and owes its bead: held=%v owed=%v needs=%q state=%q", s.Held, s.Owed, s.Needs, s.SittingState)
			}
		})
	}
}

// TestConversationInSessionHoldsWithoutOwing: a conversation a live session
// holds keeps its bead held and in session, and owes the operator nothing,
// because the operator is in it. The session is found by the conversation's
// assignee or by its gc.session_name.
func TestConversationInSessionHoldsWithoutOwing(t *testing.T) {
	const session = "gc-toolkit__converse-tk-conv"
	for _, tc := range []struct {
		name    string
		session string
		facts   Facts
	}{
		{"by its assignee", "", liveOwners(sittingAlias("tk-conv"))},
		{"by its session name", session, liveOwners(session)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			conv := conversationAnchor("tk-conv", "tk-subj", "talk through the plan", sittingAlias("tk-conv"))
			if tc.session != "" {
				conv.Metadata = map[string]string{mdSessionName: tc.session}
			}
			b := BuildBoard([]Anchor{epicSubject("tk-subj"), conv}, fixtureNow, false, nil, tc.facts)

			s := mustTile(t, b, "tk-subj")
			if !s.Held || s.Owed || s.Needs != "in conversation" || s.SittingState != SittingInSession {
				t.Errorf("a live sitting holds its bead without owing it: held=%v owed=%v needs=%q state=%q", s.Held, s.Owed, s.Needs, s.SittingState)
			}
			if s.Stranded || s.Severity == SevHigh {
				t.Errorf("a held bead is not stranded: stranded=%v severity=%s", s.Stranded, s.Severity)
			}
		})
	}
}

// TestConversationKeptWhenItsBeadHasNoRow: a conversation about a bead that has
// no row keeps its own, held by the conversation it is.
func TestConversationKeptWhenItsBeadHasNoRow(t *testing.T) {
	queued := mustTile(t, BuildBoard([]Anchor{
		conversationAnchor("tk-conv", "tk-ghost", "investigate the flake", "human"),
	}, fixtureNow, false, nil, Facts{}), "tk-conv")
	if queued.Title != "conversation: tk-ghost" || queued.Needs != "investigate the flake" ||
		!queued.Owed || !queued.Held || queued.SittingState != SittingWaiting || queued.Section != SectionGate {
		t.Errorf("a kept queued conversation states its ask and waits: %+v", queued)
	}
	live := mustTile(t, BuildBoard([]Anchor{
		conversationAnchor("tk-conv", "tk-ghost", "investigate the flake", sittingAlias("tk-conv")),
	}, fixtureNow, false, nil, liveOwners(sittingAlias("tk-conv"))), "tk-conv")
	if live.Needs != "in conversation" || live.Owed || live.SittingState != SittingInSession {
		t.Errorf("a kept conversation in session owes nothing: needs=%q owed=%v state=%q", live.Needs, live.Owed, live.SittingState)
	}
}

// TestClosedWrapperDropsBesideItsSubject: a gate or a conversation that has
// itself closed asks nothing any more. A subject's row, live or DONE, stands
// for it, so the closed wrapper takes no row beside it, and its ask does not
// fold: the subject's row is exactly the row the subject has on its own.
func TestClosedWrapperDropsBesideItsSubject(t *testing.T) {
	for _, tc := range []struct {
		name          string
		wrapper       Anchor
		subjectClosed bool
	}{
		{"gate, live subject", gateAnchor("tk-wc", "an ask that ended", "tk-subj"), false},
		{"gate, DONE subject", gateAnchor("tk-wc", "an ask that ended", "tk-subj"), true},
		{"conversation, live subject", conversationAnchor("tk-wc", "tk-subj", "an ask that ended", "human"), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := tc.wrapper
			w.ClosedAt = daysAgo(1)
			subject := epicSubject("tk-subj")
			if tc.subjectClosed {
				subject.ClosedAt = daysAgo(2)
			}
			b := BuildBoard([]Anchor{w, subject}, fixtureNow, false, nil, Facts{})

			if wc, ok := tileByID(b, "tk-wc"); ok {
				t.Errorf("a closed wrapper beside its subject's row takes no row of its own; got one in %q", wc.Section)
			}
			alone := mustTile(t, BuildBoard([]Anchor{subject}, fixtureNow, false, nil, Facts{}), "tk-subj")
			if subj := mustTile(t, b, "tk-subj"); !reflect.DeepEqual(subj, alone) {
				t.Errorf("a closed wrapper leaves its subject's row as the subject has it alone:\n got  %+v\n want %+v", subj, alone)
			}
		})
	}
}

// TestClosedGateWithNoSubjectRowStaysDone: a closed gate whose beads have no
// row is the only trace of the question it asked, so it keeps its own row in
// the DONE band, as any closed anchor does.
func TestClosedGateWithNoSubjectRowStaysDone(t *testing.T) {
	g := gateAnchor("tk-gc", "an ask that ended", "tk-ghost")
	g.ClosedAt = daysAgo(1)
	if got := mustTile(t, BuildBoard([]Anchor{g}, fixtureNow, false, nil, Facts{}), "tk-gc"); got.Section != SectionDone || got.Owed {
		t.Errorf("the closed gate bands done and owes nothing: section=%q owed=%v", got.Section, got.Owed)
	}
}

// TestTwoGatesOneBead: two gates on one bead fold into a single row that counts
// them and lists both questions.
func TestTwoGatesOneBead(t *testing.T) {
	b := BuildBoard([]Anchor{
		gateAnchor("tk-ga", "first ask", "tk-subj"),
		gateAnchor("tk-gb", "second ask", "tk-subj"),
		{ID: "tk-subj", Kind: "convoy", Source: "convoy", Rig: "gc-toolkit", Prefix: "tk",
			Children: []Child{{ID: "tk-c1", Status: "open"}}},
	}, fixtureNow, false, nil, Facts{})

	for _, id := range []string{"tk-ga", "tk-gb"} {
		if _, ok := tileByID(b, id); ok {
			t.Errorf("%s folds away", id)
		}
	}
	if subj := mustTile(t, b, "tk-subj"); subj.Needs != "2× — first ask · second ask" {
		t.Errorf("folded subject counts and lists both asks: got %q", subj.Needs)
	}
}

// TestFoldDatesTheRowByTheEarliestOwedAsk: the folded row's owed clock is the
// earliest of the asks that owe it — an open gate, a conversation waiting in
// the queue — so the queue orders the row by when the operator was first
// asked. A conversation a live sitting holds owes nothing, so it moves no
// clock.
func TestFoldDatesTheRowByTheEarliestOwedAsk(t *testing.T) {
	subject := epicSubject("tk-subj")
	subject.UpdatedAt = fixtureNow
	gate := gateAnchor("tk-g", "decide the rollout", "tk-subj")
	gate.UpdatedAt = daysAgo(5)
	queued := conversationAnchor("tk-cq", "tk-subj", "a queued concern", "human")
	queued.UpdatedAt = daysAgo(7)
	live := conversationAnchor("tk-cl", "tk-subj", "a live sitting", sittingAlias("tk-cl"))
	live.UpdatedAt = daysAgo(9)
	facts := liveOwners(sittingAlias("tk-cl"))

	if got := mustTile(t, BuildBoard([]Anchor{subject, gate, live}, fixtureNow, false, nil, facts), "tk-subj").PROwedSince; !got.Equal(daysAgo(5)) {
		t.Errorf("the gate dates the row, and the live sitting does not: got %v, want %v", got, daysAgo(5))
	}
	if got := mustTile(t, BuildBoard([]Anchor{subject, gate, queued, live}, fixtureNow, false, nil, facts), "tk-subj").PROwedSince; !got.Equal(daysAgo(7)) {
		t.Errorf("the earliest owed ask dates the row: got %v, want %v", got, daysAgo(7))
	}
}

// TestHeldBeadRanksAlikeUnderAGateAndAQueuedConversation: a bead ranks the same
// with a gate on it as with a conversation waiting in the queue: held, so not
// stranded, at NORMAL, and owed in the gate section.
func TestHeldBeadRanksAlikeUnderAGateAndAQueuedConversation(t *testing.T) {
	gated := mustTile(t, BuildBoard([]Anchor{epicSubject("tk-subj"), gateAnchor("tk-g", "an ask", "tk-subj")},
		fixtureNow, false, nil, Facts{}), "tk-subj")
	queued := mustTile(t, BuildBoard([]Anchor{epicSubject("tk-subj"), conversationAnchor("tk-c", "tk-subj", "an ask", "human")},
		fixtureNow, false, nil, Facts{}), "tk-subj")
	for name, row := range map[string]Tile{"gate": gated, "queued conversation": queued} {
		if row.Severity != SevNormal || row.Stranded || !row.Held || !row.Owed || row.Section != SectionGate {
			t.Errorf("%s: severity=%s stranded=%v held=%v owed=%v section=%q", name, row.Severity, row.Stranded, row.Held, row.Owed, row.Section)
		}
	}
	if gated.RankScore != queued.RankScore {
		t.Errorf("a gate and a queued conversation rank a bead alike: %d vs %d", gated.RankScore, queued.RankScore)
	}
}

// TestClosedConversationIsOnTheCardAndHoldsNothing is the sittings-card case
// at the derive: a conversation a sign-off closed inside the window is on the
// card, with its close reason as the headline when the sitting left no
// takeaway, while its bead's row is not held, owed or in session because of
// it.
func TestClosedConversationIsOnTheCardAndHoldsNothing(t *testing.T) {
	const reason = "ship it once the flake is fixed"
	b := BuildBoard([]Anchor{epicSubject("tk-subj")}, fixtureNow, false, nil, Facts{Sittings: []Sitting{{
		ID: "tk-conv", Subject: "tk-subj", Title: "the plan", Status: "closed", OutcomeReason: reason,
		OpenedAt: daysAgo(1), ClosedAt: daysAgo(0),
	}}})

	if len(b.Sittings) != 1 || b.Sittings[0].Headline() != reason {
		t.Fatalf("the card lists the closed conversation with its close reason as headline: %+v", b.Sittings)
	}
	if s := mustTile(t, b, "tk-subj"); s.Held || s.Owed || s.SittingState != "" {
		t.Errorf("a closed conversation holds nothing: held=%v owed=%v state=%q", s.Held, s.Owed, s.SittingState)
	}
}

// TestAcceptWithheldWhileAnotherGateBlocks is the acceptance case's first step:
// a recommendation's gate and a needs-you finding's gate both block the anchor.
// Both fold onto its row and Needs prints both, Accept is withheld, and
// accept_withheld names the finding's gate.
func TestAcceptWithheldWhileAnotherGateBlocks(t *testing.T) {
	rec := gateBlocker("tk-rec", firstReactionKey, "Accept mol-polecat-work?")
	rev := gateBlocker("tk-rev", "review-needs-you.tk-f1", "Rule on the finding")
	anchors := append([]Anchor{recommendationSubject("tk-anchor", "mol-polecat-work", rec, rev)}, gatesFor("tk-anchor", rec, rev)...)
	row := mustTile(t, BuildBoard(anchors, fixtureNow, false, nil, Facts{}), "tk-anchor")

	if row.Acceptable || row.AcceptFormula != "" || row.Recommendation != nil {
		t.Errorf("another open gate withholds Accept: acceptable=%v formula=%q", row.Acceptable, row.AcceptFormula)
	}
	if row.AcceptWithheld == nil || *row.AcceptWithheld != "Rule on the finding" {
		t.Errorf("accept_withheld names the finding's gate: %v", row.AcceptWithheld)
	}
	if !strings.HasPrefix(row.Needs, "2× — ") || !strings.Contains(row.Needs, rec.Title) || !strings.Contains(row.Needs, rev.Title) {
		t.Errorf("Needs prints both gates: got %q", row.Needs)
	}
}

// TestAcceptOfferedOnceTheRecommendationsGateIsTheLast is the acceptance case's
// fourth step: with the finding's gate answered, the recommendation's gate is
// the last one open and unassigned, so the row offers Accept and withholds
// nothing.
func TestAcceptOfferedOnceTheRecommendationsGateIsTheLast(t *testing.T) {
	rec := gateBlocker("tk-rec", firstReactionKey, "Accept mol-polecat-work?")
	rev := gateBlocker("tk-rev", "review-needs-you.tk-f1", "Rule on the finding")
	rev.Status, rev.CloseReason = "closed", "ruled: fix the finding"
	anchors := append([]Anchor{recommendationSubject("tk-anchor", "mol-polecat-work", rec, rev)}, gatesFor("tk-anchor", rec, rev)...)
	row := mustTile(t, BuildBoard(anchors, fixtureNow, false, nil, Facts{}), "tk-anchor")

	if !row.Acceptable || row.AcceptFormula != "mol-polecat-work" || row.AcceptWithheld != nil {
		t.Errorf("the last gate open offers Accept: acceptable=%v formula=%q withheld=%v", row.Acceptable, row.AcceptFormula, row.AcceptWithheld)
	}
	if row.Recommendation == nil || row.Needs != rec.Title {
		t.Errorf("the acceptable row carries the card and names its gate: recommendation=%v needs=%q", row.Recommendation, row.Needs)
	}
}

// TestAcceptWithheldByAGateFiledOnAnotherBead is the acceptance case's second
// fixture: the other gate was filed on a sibling, and the anchor waits on it
// through a `blocks` edge of its own. The gate folds onto both rows, and Accept
// is withheld the same way.
func TestAcceptWithheldByAGateFiledOnAnotherBead(t *testing.T) {
	rec := gateBlocker("tk-rec", firstReactionKey, "Accept mol-polecat-work?")
	other := gateBlocker("tk-other", "review-needs-you.tk-f2", "Rule on the sibling's finding")
	anchors := []Anchor{
		recommendationSubject("tk-anchor", "mol-polecat-work", rec, other), humanKid("tk-sibling"),
		gateAnchor("tk-rec", rec.Title, "tk-anchor"), gateAnchor("tk-other", other.Title, "tk-sibling", "tk-anchor"),
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	row := mustTile(t, b, "tk-anchor")
	if row.Acceptable || row.AcceptWithheld == nil || *row.AcceptWithheld != other.Title {
		t.Errorf("a gate on another bead the anchor waits on withholds Accept: acceptable=%v withheld=%v", row.Acceptable, row.AcceptWithheld)
	}
	if sib := mustTile(t, b, "tk-sibling"); !sib.Owed || sib.Needs != other.Title {
		t.Errorf("the gate folds onto the sibling's row too: owed=%v needs=%q", sib.Owed, sib.Needs)
	}
}

// TestALiveSittingDoesNotWithholdAccept is the acceptance case's third fixture:
// a live sitting on the anchor replies to the recommendation's gate, and no
// other gate is open. The row is in session, gates_in_session names the
// recommendation's gate, and Accept is still offered.
func TestALiveSittingDoesNotWithholdAccept(t *testing.T) {
	rec := gateBlocker("tk-rec", firstReactionKey, "Accept mol-polecat-work?")
	anchors := append([]Anchor{
		recommendationSubject("tk-anchor", "mol-polecat-work", rec),
		conversationAnchor("tk-conv", "tk-anchor", rec.Title, sittingAlias("tk-conv"), "tk-rec"),
	}, gatesFor("tk-anchor", rec)...)
	row := mustTile(t, BuildBoard(anchors, fixtureNow, false, nil, liveOwners(sittingAlias("tk-conv"))), "tk-anchor")

	if row.SittingState != SittingInSession || row.GatesInSession == nil || *row.GatesInSession != rec.Title {
		t.Errorf("the row is in session on the recommendation's gate: state=%q gates_in_session=%v", row.SittingState, row.GatesInSession)
	}
	if !row.Acceptable || row.AcceptWithheld != nil {
		t.Errorf("a live sitting does not withhold Accept: acceptable=%v withheld=%v", row.Acceptable, row.AcceptWithheld)
	}
}

// TestRecommendationOnABeadWithAnOpenChildIsAcceptable is the acceptance case's
// fourth fixture: the recommendation's gate blocks a parent with an open
// child, and the row offers Accept as on any bead.
func TestRecommendationOnABeadWithAnOpenChildIsAcceptable(t *testing.T) {
	rec := gateBlocker("tk-rec", firstReactionKey, "Accept mol-polecat-work?")
	parent := recommendationSubject("tk-parent", "mol-polecat-work", rec)
	parent.Children = []Child{{ID: "tk-parent.1", Status: "open"}}
	if row := mustTile(t, BuildBoard(append([]Anchor{parent}, gatesFor("tk-parent", rec)...), fixtureNow, false, nil, Facts{}), "tk-parent"); !row.Acceptable {
		t.Errorf("a recommendation on a bead with an open child offers Accept: acceptable=%v", row.Acceptable)
	}
}

// TestUnfinishedAcceptanceKeepsTheBeadOwedAndAcceptable is the acceptance
// case's fifth fixture at the derive: an Accept stopped after its resolve
// leaves the recommendation's gate closed with its answer while the bead still
// carries the recommendation. The row is owed and held, offers Accept, and
// Needs names the closed gate. Only an Accept's own answer leaves an
// acceptance to finish: a sitting's ruling, or an Accept of another formula,
// leaves the row offering Discuss alone.
func TestUnfinishedAcceptanceKeepsTheBeadOwedAndAcceptable(t *testing.T) {
	build := func(reason string) Tile {
		rec := gateBlocker("tk-rec", firstReactionKey, "Accept mol-polecat-work?")
		rec.Status, rec.CloseReason, rec.UpdatedAt = "closed", reason, daysAgo(2)
		closed := gateAnchor("tk-rec", rec.Title, "tk-anchor")
		closed.ClosedAt = daysAgo(2)
		b := BuildBoard([]Anchor{recommendationSubject("tk-anchor", "mol-polecat-work", rec), closed}, fixtureNow, false, nil, Facts{})
		if _, ok := tileByID(b, "tk-rec"); ok {
			t.Errorf("the closed gate takes no row beside the bead's")
		}
		return mustTile(t, b, "tk-anchor")
	}

	row := build("ruled: accepted mol-polecat-work accept:0a1b2c3d")
	if !row.Owed || !row.Held || !row.Acceptable || row.Needs != "Accept mol-polecat-work?" || row.SittingState != SittingWaiting {
		t.Errorf("an unfinished acceptance is owed, held and acceptable: owed=%v held=%v acceptable=%v needs=%q state=%q",
			row.Owed, row.Held, row.Acceptable, row.Needs, row.SittingState)
	}
	if !row.PROwedSince.Equal(daysAgo(2)) {
		t.Errorf("the unfinished acceptance dates the row by its gate: got %v", row.PROwedSince)
	}
	if row.DispositionDue {
		t.Errorf("a recommendation's closed gate is not a blocker that landed")
	}
	for _, reason := range []string{"ruled: declined", "ruled: accepted mol-other accept:0a1b2c3d"} {
		if r := build(reason); r.Acceptable || r.Held || r.Owed || r.AcceptWithheld != nil {
			t.Errorf("%q leaves nothing to finish: acceptable=%v held=%v owed=%v", reason, r.Acceptable, r.Held, r.Owed)
		}
	}
}

// TestRecommendationsGateAssignedToAPersonIsDiscussOnly: a gate assigned to a
// person is that person's to clear, so the row does not offer Accept, and
// withholds nothing either, because the second condition fails.
func TestRecommendationsGateAssignedToAPersonIsDiscussOnly(t *testing.T) {
	rec := gateBlocker("tk-rec", firstReactionKey, "Accept mol-polecat-work?")
	rec.Assignee = "alice"
	row := mustTile(t, BuildBoard(append([]Anchor{recommendationSubject("tk-anchor", "mol-polecat-work", rec)}, gatesFor("tk-anchor", rec)...),
		fixtureNow, false, nil, Facts{}), "tk-anchor")
	if row.Acceptable || row.AcceptWithheld != nil {
		t.Errorf("an assigned recommendation gate is discuss-only: acceptable=%v withheld=%v", row.Acceptable, row.AcceptWithheld)
	}
}

// TestRecommendationWithNoGateOrNoFormulaIsDiscussOnly: Accept needs both the
// recommendation and the gate that asks it. A recommendation no gate asks, a
// first-reaction gate on a bead with no recommendation, and a recommendation
// whose waits could not be read each offer Discuss alone.
func TestRecommendationWithNoGateOrNoFormulaIsDiscussOnly(t *testing.T) {
	rec := gateBlocker("tk-rec", firstReactionKey, "Accept?")
	noFormula := recommendationSubject("tk-c", "", rec)
	delete(noFormula.Metadata, "gc.recommended_formula")
	unread := recommendationSubject("tk-d", "mol-polecat-work", rec)
	unread.WaitingUnknown = true
	for name, a := range map[string]Anchor{
		"no gate":      recommendationSubject("tk-b", "mol-polecat-work"),
		"no formula":   noFormula,
		"unread waits": unread,
	} {
		row := mustTile(t, BuildBoard([]Anchor{a}, fixtureNow, false, nil, Facts{}), a.ID)
		if row.Acceptable || row.AcceptFormula != "" || row.AcceptWithheld != nil {
			t.Errorf("%s: discuss-only: acceptable=%v formula=%q withheld=%v", name, row.Acceptable, row.AcceptFormula, row.AcceptWithheld)
		}
	}
}

// TestClosedHumanGateIsNotABlockerThatLanded: a parked bead whose only wait is a
// human gate that closed is not disposition-due, because the gate was a
// question and its answer is its close reason. Routed work that landed still
// is.
func TestClosedHumanGateIsNotABlockerThatLanded(t *testing.T) {
	parked := func(b Blocker) Anchor {
		return Anchor{ID: "tk-p", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk",
			Takeaway: "ruled: ship it", Metadata: map[string]string{"gc.takeaway": "ruled: ship it"},
			Blockers: []Blocker{b}, WaitingOn: []string{b.ID}, WaitingOnClosed: []string{b.ID}}
	}
	gate := gateBlocker("tk-g", "bring-current", "an answered question")
	gate.Status = "closed"
	if row := mustTile(t, BuildBoard([]Anchor{parked(gate)}, fixtureNow, false, nil, Facts{}), "tk-p"); row.DispositionDue || row.Owed {
		t.Errorf("a closed human gate is not a blocker that landed: disposition_due=%v owed=%v", row.DispositionDue, row.Owed)
	}
	work := Blocker{ID: "tk-w", Title: "routed fix", Status: "closed", IssueType: "task", RoutedTo: "gc-toolkit/gc-toolkit.polecat"}
	if row := mustTile(t, BuildBoard([]Anchor{parked(work)}, fixtureNow, false, nil, Facts{}), "tk-p"); !row.DispositionDue || !row.Owed {
		t.Errorf("routed work that landed is due a disposition: disposition_due=%v owed=%v", row.DispositionDue, row.Owed)
	}
}

// TestClusterTagging: at or above the threshold, rows sharing a section and a
// needs sentence are tagged; below it they are not.
func TestClusterTagging(t *testing.T) {
	anchors := []Anchor{
		// Three human-routed beads with no recorded question → identical needs.
		{ID: "tk-h1", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "tk-h2", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "tk-h3", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		// Two decisions → identical needs, but below the threshold.
		{ID: "tk-d1", Kind: "decision", Source: "decision", Rig: "gc-toolkit", Prefix: "tk"},
		{ID: "tk-d2", Kind: "decision", Source: "decision", Rig: "gc-toolkit", Prefix: "tk"},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})

	for _, id := range []string{"tk-h1", "tk-h2", "tk-h3"} {
		tile, _ := tileByID(b, id)
		if tile.ClusterKey == "" {
			t.Errorf("%s should be clustered (3 share the needs), got empty key", id)
		}
		if tile.ClusterKey != tile.Needs {
			t.Errorf("%s cluster key is its needs: key=%q needs=%q", id, tile.ClusterKey, tile.Needs)
		}
	}
	for _, id := range []string{"tk-d1", "tk-d2"} {
		tile, _ := tileByID(b, id)
		if tile.ClusterKey != "" {
			t.Errorf("%s should NOT cluster (only 2 share the needs), got %q", id, tile.ClusterKey)
		}
	}
}

// TestParkedParentBandsGateNotActive: a roll-up whose every open child is parked
// for the operator is waiting on the operator to rule those child rows, not
// active work — so it bands gate rather than masquerading as in-flight, even
// when its own route markers are empty.
func TestParkedParentBandsGateNotActive(t *testing.T) {
	anchors := []Anchor{
		{ID: "tk-parent", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", UpdatedAt: fixtureNow,
			Children: []Child{{ID: "tk-child", Status: "open", Metadata: map[string]string{"gc.routed_to": "human"}}}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	tile, ok := tileByID(b, "tk-parent")
	if !ok {
		t.Fatal("tk-parent missing")
	}
	if tile.Section != SectionGate {
		t.Errorf("a parent whose only open child is parked for the operator bands gate, got %q", tile.Section)
	}
}

// TestTakeawayRowsDoNotCluster: a row carrying a takeaway never clusters, however
// many share its needs — a deterministic headline templated across anchors
// (the bring-current question's) does not fold into a count-plus-id soup that
// loses the per-bead content. A deterministic STATE phrase, which no bead authored,
// still clusters.
func TestTakeawayRowsDoNotCluster(t *testing.T) {
	tmpl := "Needs a decision before its branch can be brought current; the gate on its anchor asks it"
	anchors := []Anchor{
		// Three parked beads with the SAME templated takeaway → must not cluster.
		{ID: "tk-t1", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.takeaway": tmpl}, Takeaway: tmpl},
		{ID: "tk-t2", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.takeaway": tmpl}, Takeaway: tmpl},
		{ID: "tk-t3", Kind: "parked", Source: "parked", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.takeaway": tmpl}, Takeaway: tmpl},
		// Three human beads with no takeaway and one shared state phrase → cluster.
		{ID: "tk-c1", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "tk-c2", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
		{ID: "tk-c3", Kind: "human", Source: "human", Rig: "gc-toolkit", Prefix: "tk",
			Metadata: map[string]string{"gc.routed_to": "human"}},
	}
	b := BuildBoard(anchors, fixtureNow, false, nil, Facts{})
	for _, id := range []string{"tk-t1", "tk-t2", "tk-t3"} {
		tile, _ := tileByID(b, id)
		if tile.ClusterKey != "" {
			t.Errorf("%s carries a takeaway and must not cluster, got key %q", id, tile.ClusterKey)
		}
	}
	for _, id := range []string{"tk-c1", "tk-c2", "tk-c3"} {
		tile, _ := tileByID(b, id)
		if tile.ClusterKey == "" {
			t.Errorf("%s is a takeaway-less state phrase shared by 3 and must still cluster", id)
		}
	}
}

// TestClusterRowsCollapse: ClusterRows folds a cluster to one line with every
// member, and leaves unclustered rows on their own line, in first-seen order.
func TestClusterRowsCollapse(t *testing.T) {
	tiles := []Tile{
		{ID: "a", Section: SectionGate, Needs: "same", ClusterKey: "same"},
		{ID: "b", Section: SectionGate, Needs: "solo"},
		{ID: "c", Section: SectionGate, Needs: "same", ClusterKey: "same"},
		{ID: "d", Section: SectionGate, Needs: "same", ClusterKey: "same"},
	}
	rows := ClusterRows(tiles)
	if len(rows) != 2 {
		t.Fatalf("want 2 render rows (one cluster + one solo), got %d", len(rows))
	}
	if rows[0].Tile.ID != "a" || len(rows[0].Members) != 3 {
		t.Errorf("cluster head is the first member and holds all 3: head=%s n=%d", rows[0].Tile.ID, len(rows[0].Members))
	}
	if rows[1].Tile.ID != "b" || len(rows[1].Members) != 1 {
		t.Errorf("solo row stands alone: id=%s n=%d", rows[1].Tile.ID, len(rows[1].Members))
	}
}

// TestGroupBySection returns only non-empty bands, in SectionOrder.
func TestGroupBySection(t *testing.T) {
	tiles := []Tile{
		{ID: "a", Section: SectionCleanup},
		{ID: "b", Section: SectionReview},
		{ID: "c", Section: SectionGate},
	}
	groups := GroupBySection(tiles)
	got := make([]string, len(groups))
	for i, g := range groups {
		got[i] = g.Key
	}
	want := []string{SectionReview, SectionGate, SectionCleanup}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("section order: got %v, want %v", got, want)
	}
}
