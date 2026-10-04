package board

import "testing"

// TestAnchorOwnWorkflowCounts covers the common sling shape, where live work
// stands over the anchor's OWN bead rather than under a child. gc sling routes a
// work bead to the pool, mints an input convoy that TRACKS the work bead, and
// pours a molecule whose root and steps carry the live session. internal/source
// keys Facts.Inflight by the convoy MEMBER — the work bead, which is the anchor's
// own id — so the in-progress bead is a molecule STEP reached through the convoy,
// never a direct child. rollUp adds that bead to the live-work heads, so the
// counts, the band, the stranded test, the frontier and NEEDS all see it. An
// anchor whose own live work went uncounted would read in_progress_live=0 and,
// with any idle child, band HIGH/stranded and ask for an assignment it already
// has: a healthy in-flight anchor reported as the alarm case.
func TestAnchorOwnWorkflowCounts(t *testing.T) {
	live := liveOwners("gc-toolkit__polecat-lx-1")
	live.Inflight = map[string][]string{"tk-work": {"gc-toolkit__polecat-lx-1"}}

	t.Run("childless work bead reads in flight, not invisible", func(t *testing.T) {
		anchors := []Anchor{{ID: "tk-work", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2)}}
		tl := BuildBoard(anchors, fixtureNow, false, nil, live).Tiles[0]
		if tl.InProgressLive != 1 || tl.InFlight != 1 {
			t.Errorf("anchor's own live molecule must count: in_progress_live=%d in_flight=%d (want 1, 1)", tl.InProgressLive, tl.InFlight)
		}
		if !equalIDs(tl.InFlightHeads, []string{"tk-work"}) {
			t.Errorf("in_flight_heads names the anchor's own bead: got %v", tl.InFlightHeads)
		}
	})

	t.Run("idle child does not mask the anchor's own live work", func(t *testing.T) {
		anchors := []Anchor{{ID: "tk-work", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "c1", Status: "open"},
		}}}
		tl := BuildBoard(anchors, fixtureNow, false, nil, live).Tiles[0]
		if tl.InProgressLive != 1 {
			t.Errorf("in_progress_live=%d (want 1)", tl.InProgressLive)
		}
		if tl.Stranded || tl.Severity == SevHigh {
			t.Errorf("an anchor the city is working is not stranded/HIGH: sev=%s stranded=%v", tl.Severity, tl.Stranded)
		}
		// FRONTIER and NEEDS read the same count as the band, so neither asks for an
		// assignment the anchor already has.
		if tl.Frontier != "working · 1 open · 1 in flight" || tl.Needs != "in flight" {
			t.Errorf("every column reads the anchor's own live work: frontier=%q needs=%q (want %q, %q)",
				tl.Frontier, tl.Needs, "working · 1 open · 1 in flight", "in flight")
		}
	})

	// The guard the fold must not weaken: liveness is re-derived at derive time, so
	// a molecule whose session has drained stops counting and the anchor strands
	// again — a husk over the anchor's own bead must not read as in flight.
	t.Run("drained workflow over the anchor stops counting", func(t *testing.T) {
		anchors := []Anchor{{ID: "tk-work", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Prefix: "tk", Priority: ptr(2), Children: []Child{
			{ID: "c1", Status: "open"},
		}}}
		dead := Facts{Inflight: live.Inflight, OwnerState: map[string]string{"gc-toolkit__polecat-lx-1": "archived"}}
		tl := BuildBoard(anchors, fixtureNow, false, nil, dead).Tiles[0]
		if tl.InProgressLive != 0 || !tl.Stranded {
			t.Errorf("a drained molecule over the anchor stops counting and strands: in_progress_live=%d stranded=%v", tl.InProgressLive, tl.Stranded)
		}
		if tl.Needs != "decomposed, idle — assign or visit" {
			t.Errorf("a stranded anchor asks for an assignment: needs=%q", tl.Needs)
		}
	})
}
