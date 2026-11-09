package waits

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// An edge the listing has and the show row lacks is into another store only
// when the store does not hold its far bead. One the store holds was written
// between the two reads.
func TestForeignIsAnEdgeOntoABeadTheStoreDoesNotHold(t *testing.T) {
	listed := []ledger.Edge{
		{Type: ledger.EdgeBlocks, ID: "shown"},
		{Type: ledger.EdgeBlocks, ID: "late"},
		{Type: ledger.EdgeBlocks, ID: "xx-1"},
		{Type: "tracks", ID: "xx-2"},
	}
	shown := []ledger.Edge{{Type: ledger.EdgeBlocks, ID: "shown", Status: "open"}}
	got := foreignOf(listed, shown, map[string]bool{"shown": true, "late": true})
	if want := []Foreign{{ID: "xx-1", Type: "blocks"}}; !slices.Equal(got, want) {
		t.Errorf("foreign = %+v; want %+v", got, want)
	}
}
