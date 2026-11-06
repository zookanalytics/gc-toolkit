package source

import (
	"encoding/json"
	"slices"
	"testing"

	"github.com/steveyegge/beads"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus/fixture"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// Every scenario the readers of what holds a PR are tested against reaches the
// board as the beads library returns its beads, through the real gather and
// BuildBoard. The PR's row answers what prstatus.Read gathers from the same beads
// through the in-memory store: its phase, its held values, and the bead behind
// each reason that names one. The answer is the definition's own, so a change to
// it reaches the board with no edit here, and a rule the board kept for itself
// would part from it. gctk's TestPRStatusDeriveReadsTheDefinition holds the PR's
// labels and gc-helm.sh engage, which read `gctk pr-status derive`, to the same
// scenarios the same way.
func TestBoardReadsTheDefinition(t *testing.T) {
	scenarios, err := fixture.Scenarios()
	if err != nil {
		t.Fatal(err)
	}
	for _, sc := range scenarios {
		t.Run(sc.Name, func(t *testing.T) {
			want, err := sc.Answer()
			if err != nil {
				t.Fatal(err)
			}
			res, anchor := gatherPreOpen(t, scenarioStore(t, sc), sc.Anchor)
			if anchor.PR == nil {
				t.Fatalf("the PR has no answer (partial %v)", res.PartialErrors)
			}
			b := board.BuildBoard(res.Anchors, testNow, res.Partial, res.PartialErrors, res.Facts)
			i := slices.IndexFunc(b.Tiles, func(tl board.Tile) bool { return tl.ID == sc.Anchor })
			if i < 0 {
				t.Fatalf("the PR has no row")
			}
			tile := b.Tiles[i]
			var held []string
			for _, h := range want.Held {
				held = append(held, string(h))
			}
			var named, reasons []string
			for _, r := range want.Reasons {
				if r.ID != "" {
					named = append(named, r.ID)
				}
			}
			for _, r := range anchor.PRReasons {
				reasons = append(reasons, r.ID)
			}
			if tile.PRPhase != string(want.Status) || !slices.Equal(tile.PRHeld, held) || !slices.Equal(reasons, named) {
				t.Errorf("pr_phase=%q pr_held=%v reasons=%v\nthe definition gives %q, %v and %v", tile.PRPhase, tile.PRHeld, reasons, want.Status, held, named)
			}
		})
	}
}

// scenarioStore is a scenario's beads as the beads library holds them: each a
// row of its issue type, and each edge of its own an outbound record onto the
// far bead.
func scenarioStore(t *testing.T, sc fixture.Scenario) *fakeStore {
	t.Helper()
	st := &fakeStore{issues: map[string][]*beads.Issue{}, depsDown: map[string][]*beads.IssueWithDependencyMetadata{}}
	rows := map[string]*beads.Issue{}
	for _, b := range sc.Beads {
		kind := b.IssueType
		if kind == "" {
			kind = "task"
		}
		meta := ""
		if len(b.Metadata) > 0 {
			raw, err := json.Marshal(b.Metadata)
			if err != nil {
				t.Fatal(err)
			}
			meta = string(raw)
		}
		iss := issue(b.ID, b.Title, kind, 2, testNow, meta)
		iss.Status = beads.Status(b.Status)
		iss.AwaitType = b.AwaitType
		iss.Assignee = b.Assignee
		if iss.Status == beads.StatusClosed {
			at := testNow
			iss.ClosedAt = &at
		}
		rows[b.ID] = iss
		st.issues[kind] = append(st.issues[kind], iss)
	}
	for _, b := range sc.Beads {
		for _, edge := range []struct {
			kind string
			ids  []string
		}{{"blocks", b.WaitsOn}, {"tracks", b.Tracks}} {
			for _, id := range edge.ids {
				if far, ok := rows[id]; ok {
					st.depsDown[b.ID] = append(st.depsDown[b.ID], &beads.IssueWithDependencyMetadata{Issue: *far, DependencyType: beads.DependencyType(edge.kind)})
				}
			}
		}
	}
	return st
}
